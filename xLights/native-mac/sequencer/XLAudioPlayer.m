/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

static const CGFloat kDefaultPositionUpdateInterval = 50.0;  // 50ms = 20 updates/sec
static const CGFloat kMinPlaybackRate = 0.25;
static const CGFloat kMaxPlaybackRate = 4.0;

@interface XLAudioPlayer () {
    dispatch_source_t _positionTimer;
    dispatch_queue_t _timerQueue;
}

@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, strong) AVAudioPlayerNode *playerNode;
@property (nonatomic, strong) AVAudioUnitTimePitch *timePitchNode;
@property (nonatomic, strong) AVAudioFile *audioFile;
@property (nonatomic, strong) AVAudioPCMBuffer *audioBuffer;

@property (nonatomic, readwrite) XLAudioPlaybackState playbackState;
@property (nonatomic, readwrite) BOOL isLoaded;
@property (nonatomic, readwrite) CGFloat durationMS;
@property (nonatomic, readwrite, nullable) NSString *outputDeviceName;

@property (nonatomic, assign) AVAudioFramePosition lastKnownFrame;
@property (nonatomic, assign) NSTimeInterval lastKnownHostTime;
@property (nonatomic, assign) AVAudioFramePosition scheduledStartFrame;
@property (nonatomic, assign) BOOL isScheduled;
@property (nonatomic, assign) NSUInteger scheduleGeneration;  // Detects stale completion handlers

@end

@implementation XLAudioPlayer

#pragma mark - Singleton

+ (instancetype)sharedPlayer {
    static XLAudioPlayer *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[XLAudioPlayer alloc] init];
    });
    return sharedInstance;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _playbackState = XLAudioPlaybackStateStopped;
        _isLoaded = NO;
        _durationMS = 0;
        _playbackRate = 1.0;
        _volume = 1.0;
        _loopEnabled = NO;
        _positionUpdateIntervalMS = kDefaultPositionUpdateInterval;
        _lastKnownFrame = 0;
        _lastKnownHostTime = 0;
        _scheduledStartFrame = 0;
        _isScheduled = NO;
        _scheduleGeneration = 0;

        _timerQueue = dispatch_queue_create("org.xlights.audioplayer.timer", DISPATCH_QUEUE_SERIAL);

        [self setupAudioEngine];
    }
    return self;
}

- (void)dealloc {
    [self stopPositionTimer];
    [self unload];

    if (_audioEngine) {
        [_audioEngine stop];
        _audioEngine = nil;
    }
}

#pragma mark - Audio Engine Setup

- (void)setupAudioEngine {
    _audioEngine = [[AVAudioEngine alloc] init];
    _playerNode = [[AVAudioPlayerNode alloc] init];
    _timePitchNode = [[AVAudioUnitTimePitch alloc] init];

    [_audioEngine attachNode:_playerNode];
    [_audioEngine attachNode:_timePitchNode];

    // Connect: playerNode -> timePitch -> mainMixer
    AVAudioMixerNode *mainMixer = _audioEngine.mainMixerNode;
    AVAudioFormat *format = [mainMixer outputFormatForBus:0];

    [_audioEngine connect:_playerNode to:_timePitchNode format:format];
    [_audioEngine connect:_timePitchNode to:mainMixer format:format];

    // Set initial volume
    _playerNode.volume = _volume;

    // Prepare the engine
    NSError *error = nil;
    if (![_audioEngine startAndReturnError:&error]) {
        NSLog(@"XLAudioPlayer: Failed to start audio engine: %@", error.localizedDescription);
    }
}

#pragma mark - Loading

- (BOOL)loadAudioFile:(NSString *)path {
    if (!path || path.length == 0) {
        NSLog(@"XLAudioPlayer: Empty path provided");
        return NO;
    }

    // Stop any current playback
    [self stop];
    [self unload];

    NSURL *fileURL = [NSURL fileURLWithPath:path];
    NSError *error = nil;

    _audioFile = [[AVAudioFile alloc] initForReading:fileURL error:&error];
    if (!_audioFile) {
        NSLog(@"XLAudioPlayer: Failed to open audio file '%@': %@", path, error.localizedDescription);
        [self notifyError:error];
        return NO;
    }

    // Calculate duration
    double sampleRate = _audioFile.processingFormat.sampleRate;
    AVAudioFramePosition frameCount = _audioFile.length;
    _durationMS = (sampleRate > 0) ? (frameCount / sampleRate) * 1000.0 : 0;

    // Read the entire file into a buffer for low-latency playback
    AVAudioFormat *processingFormat = _audioFile.processingFormat;
    _audioBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                                frameCapacity:(AVAudioFrameCount)frameCount];
    if (!_audioBuffer) {
        NSLog(@"XLAudioPlayer: Failed to allocate audio buffer");
        _audioFile = nil;
        return NO;
    }

    if (![_audioFile readIntoBuffer:_audioBuffer error:&error]) {
        NSLog(@"XLAudioPlayer: Failed to read audio data: %@", error.localizedDescription);
        [self notifyError:error];
        _audioFile = nil;
        _audioBuffer = nil;
        return NO;
    }

    // Reconnect nodes with the correct format
    [_audioEngine disconnectNodeInput:_timePitchNode];
    [_audioEngine disconnectNodeOutput:_playerNode];

    [_audioEngine connect:_playerNode to:_timePitchNode format:processingFormat];
    [_audioEngine connect:_timePitchNode to:_audioEngine.mainMixerNode format:processingFormat];

    _isLoaded = YES;
    _lastKnownFrame = 0;
    _isScheduled = NO;

    NSLog(@"XLAudioPlayer: Loaded '%@' - %.2f sec, %.0f Hz, %u channels",
          path.lastPathComponent, _durationMS / 1000.0,
          processingFormat.sampleRate, (unsigned int)processingFormat.channelCount);

    return YES;
}

- (void)loadAudioFileAsync:(NSString *)path
                completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = [self loadAudioFile:path];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(success, nil);
            });
        }
    });
}

- (void)unload {
    [self stop];

    _audioFile = nil;
    _audioBuffer = nil;
    _isLoaded = NO;
    _durationMS = 0;
    _lastKnownFrame = 0;
    _isScheduled = NO;
}

#pragma mark - Playback Control

- (void)play {
    if (!_isLoaded || !_audioBuffer) {
        NSLog(@"XLAudioPlayer: Cannot play - no audio loaded");
        return;
    }

    if (_playbackState == XLAudioPlaybackStatePlaying) {
        return;  // Already playing
    }

    // Ensure engine is running
    if (!_audioEngine.isRunning) {
        NSError *error = nil;
        if (![_audioEngine startAndReturnError:&error]) {
            NSLog(@"XLAudioPlayer: Failed to start audio engine: %@", error.localizedDescription);
            [self notifyError:error];
            return;
        }
    }

    if (_playbackState == XLAudioPlaybackStatePaused && _isScheduled) {
        // Resume from pause
        [_playerNode play];
    } else {
        // Start fresh or from a seek position
        [self schedulePlaybackFromFrame:_lastKnownFrame];
        [_playerNode play];
    }

    [self setPlaybackState:XLAudioPlaybackStatePlaying];
    [self startPositionTimer];

    NSLog(@"XLAudioPlayer: Playing from %.0f ms", self.currentPositionMS);
}

- (void)playFromPosition:(CGFloat)positionMS {
    [self seekToPosition:positionMS];
    [self play];
}

- (void)pause {
    if (_playbackState != XLAudioPlaybackStatePlaying) {
        return;
    }

    // Capture current position before pausing
    _lastKnownFrame = [self currentFramePosition];

    [_playerNode pause];
    [self setPlaybackState:XLAudioPlaybackStatePaused];
    [self stopPositionTimer];

    NSLog(@"XLAudioPlayer: Paused at %.0f ms", self.currentPositionMS);
}

- (void)stop {
    _scheduleGeneration++;  // Invalidate any pending completion handlers

    // Capture current position before stopping so seeks after stop are preserved.
    // Without this, _lastKnownFrame resets to 0 and any prior seekToPosition is lost.
    if (_playbackState == XLAudioPlaybackStatePlaying && _isScheduled) {
        _lastKnownFrame = [self currentFramePosition];
    }

    [_playerNode stop];
    _isScheduled = NO;
    [self setPlaybackState:XLAudioPlaybackStateStopped];
    [self stopPositionTimer];

    NSLog(@"XLAudioPlayer: Stopped at frame %lld (%.0f ms)", _lastKnownFrame, self.currentPositionMS);
}

- (void)togglePlayPause {
    if (_playbackState == XLAudioPlaybackStatePlaying) {
        [self pause];
    } else {
        [self play];
    }
}

#pragma mark - Seeking

- (void)seekToPosition:(CGFloat)positionMS {
    if (!_isLoaded || !_audioBuffer) {
        return;
    }

    positionMS = fmax(0, fmin(positionMS, _durationMS));

    double sampleRate = _audioFile.processingFormat.sampleRate;
    AVAudioFramePosition targetFrame = (AVAudioFramePosition)((positionMS / 1000.0) * sampleRate);

    BOOL wasPlaying = (_playbackState == XLAudioPlaybackStatePlaying);

    // Always stop the player node when seeking — whether playing or paused.
    // This clears any queued buffers so the next schedulePlaybackFromFrame:
    // starts fresh. Without this, a seek while paused leaves the old buffer
    // in the queue, and playerTime.sampleTime becomes cumulative across both
    // old and new buffers, causing position tracking to jump ahead.
    if (wasPlaying || _playbackState == XLAudioPlaybackStatePaused) {
        _scheduleGeneration++;
        [_playerNode stop];
    }

    _lastKnownFrame = targetFrame;
    _isScheduled = NO;

    if (wasPlaying) {
        [self schedulePlaybackFromFrame:targetFrame];
        [_playerNode play];
    }

    // Notify position update
    [self notifyPositionUpdate];
}

- (void)seekRelative:(CGFloat)deltaMS {
    CGFloat newPosition = self.currentPositionMS + deltaMS;
    [self seekToPosition:newPosition];
}

- (void)seekToStart {
    [self seekToPosition:0];
}

- (void)seekToEnd {
    [self seekToPosition:_durationMS];
}

#pragma mark - Scheduling

- (void)schedulePlaybackFromFrame:(AVAudioFramePosition)startFrame {
    if (!_audioBuffer || !_audioFile) {
        return;
    }

    AVAudioFrameCount totalFrames = _audioBuffer.frameLength;

    if (startFrame >= totalFrames) {
        if (_loopEnabled) {
            startFrame = 0;
        } else {
            [self handlePlaybackEnd];
            return;
        }
    }

    // Create a buffer segment starting from the current position
    AVAudioFrameCount remainingFrames = totalFrames - (AVAudioFrameCount)startFrame;
    AVAudioFormat *format = _audioBuffer.format;

    AVAudioPCMBuffer *segmentBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                                                    frameCapacity:remainingFrames];

    // Copy data from startFrame to end
    segmentBuffer.frameLength = remainingFrames;

    for (AVAudioChannelCount ch = 0; ch < format.channelCount; ch++) {
        if (format.isInterleaved) {
            // Interleaved format
            memcpy(segmentBuffer.floatChannelData[0],
                   _audioBuffer.floatChannelData[0] + startFrame * format.channelCount,
                   remainingFrames * format.channelCount * sizeof(float));
            break;
        } else {
            // Non-interleaved format
            memcpy(segmentBuffer.floatChannelData[ch],
                   _audioBuffer.floatChannelData[ch] + startFrame,
                   remainingFrames * sizeof(float));
        }
    }

    _scheduledStartFrame = startFrame;
    _isScheduled = YES;
    NSUInteger currentGeneration = _scheduleGeneration;

    __weak typeof(self) weakSelf = self;
    [_playerNode scheduleBuffer:segmentBuffer
                         atTime:nil
                        options:0
              completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            // Ignore stale completion handlers from previous play/stop cycles
            if (strongSelf.scheduleGeneration != currentGeneration) return;
            if (strongSelf.playbackState == XLAudioPlaybackStatePlaying) {
                [strongSelf handlePlaybackEnd];
            }
        });
    }];
}

- (void)handlePlaybackEnd {
    if (_loopEnabled && _isLoaded) {
        _lastKnownFrame = 0;
        [self schedulePlaybackFromFrame:0];
        [_playerNode play];
        NSLog(@"XLAudioPlayer: Looping to start");
    } else {
        [self stop];

        if ([_delegate respondsToSelector:@selector(audioPlayerDidReachEnd:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate audioPlayerDidReachEnd:self];
            });
        }

        NSLog(@"XLAudioPlayer: Reached end of audio");
    }
}

#pragma mark - Position Tracking

- (CGFloat)currentPositionMS {
    if (!_isLoaded || !_audioFile) {
        return 0;
    }

    AVAudioFramePosition frame = [self currentFramePosition];
    double sampleRate = _audioFile.processingFormat.sampleRate;

    return (sampleRate > 0) ? (frame / sampleRate) * 1000.0 : 0;
}

- (AVAudioFramePosition)currentFramePosition {
    if (!_isLoaded || !_audioFile || !_isScheduled) {
        return _lastKnownFrame;
    }

    if (_playbackState != XLAudioPlaybackStatePlaying) {
        return _lastKnownFrame;
    }

    AVAudioTime *nodeTime = _playerNode.lastRenderTime;
    if (!nodeTime || !nodeTime.isSampleTimeValid) {
        return _lastKnownFrame;
    }

    AVAudioTime *playerTime = [_playerNode playerTimeForNodeTime:nodeTime];
    if (!playerTime) {
        return _lastKnownFrame;
    }

    AVAudioFramePosition currentFrame = _scheduledStartFrame + playerTime.sampleTime;
    AVAudioFrameCount totalFrames = _audioBuffer.frameLength;

    if (currentFrame < 0) currentFrame = 0;
    if (currentFrame > totalFrames) currentFrame = totalFrames;

    return currentFrame;
}

#pragma mark - Position Timer

- (void)startPositionTimer {
    [self stopPositionTimer];

    NSTimeInterval interval = _positionUpdateIntervalMS / 1000.0;

    _positionTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _timerQueue);

    dispatch_source_set_timer(_positionTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
                              (uint64_t)(interval * NSEC_PER_SEC),
                              (uint64_t)(0.001 * NSEC_PER_SEC));

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_positionTimer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.playbackState == XLAudioPlaybackStatePlaying) {
            [strongSelf notifyPositionUpdate];
        }
    });

    dispatch_resume(_positionTimer);
}

- (void)stopPositionTimer {
    if (_positionTimer) {
        dispatch_source_cancel(_positionTimer);
        _positionTimer = nil;
    }
}

- (void)notifyPositionUpdate {
    CGFloat positionMS = self.currentPositionMS;
    NSUInteger currentGeneration = _scheduleGeneration;

    if ([_delegate respondsToSelector:@selector(audioPlayer:didUpdatePosition:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Discard stale updates queued before stop was called
            if (self.scheduleGeneration != currentGeneration) return;
            if (self.playbackState != XLAudioPlaybackStatePlaying) return;
            [self.delegate audioPlayer:self didUpdatePosition:positionMS];
        });
    }
}

#pragma mark - Property Setters

- (void)setPlaybackRate:(CGFloat)playbackRate {
    _playbackRate = fmax(kMinPlaybackRate, fmin(playbackRate, kMaxPlaybackRate));
    _timePitchNode.rate = _playbackRate;
}

- (void)setVolume:(CGFloat)volume {
    _volume = fmax(0.0, fmin(volume, 1.0));
    _playerNode.volume = _volume;
}

- (void)setPlaybackState:(XLAudioPlaybackState)playbackState {
    if (_playbackState != playbackState) {
        _playbackState = playbackState;

        if ([_delegate respondsToSelector:@selector(audioPlayer:didChangeState:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate audioPlayer:self didChangeState:playbackState];
            });
        }
    }
}

#pragma mark - Audio Output Device

+ (NSArray<NSString *> *)availableOutputDevices {
    // Use AudioObjectGetPropertyData to enumerate devices
    AudioObjectPropertyAddress propertyAddress = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                                      &propertyAddress,
                                                      0, NULL, &dataSize);
    if (status != noErr) {
        return @[];
    }

    UInt32 deviceCount = dataSize / sizeof(AudioDeviceID);
    AudioDeviceID *devices = (AudioDeviceID *)malloc(dataSize);

    status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                         &propertyAddress,
                                         0, NULL, &dataSize, devices);
    if (status != noErr) {
        free(devices);
        return @[];
    }

    NSMutableArray *outputDevices = [NSMutableArray array];

    for (UInt32 i = 0; i < deviceCount; i++) {
        // Check if device has output channels
        AudioObjectPropertyAddress outputAddress = {
            kAudioDevicePropertyStreamConfiguration,
            kAudioDevicePropertyScopeOutput,
            kAudioObjectPropertyElementMain
        };

        UInt32 configSize = 0;
        status = AudioObjectGetPropertyDataSize(devices[i], &outputAddress, 0, NULL, &configSize);
        if (status != noErr) continue;

        AudioBufferList *bufferList = (AudioBufferList *)malloc(configSize);
        status = AudioObjectGetPropertyData(devices[i], &outputAddress, 0, NULL, &configSize, bufferList);

        BOOL hasOutput = NO;
        if (status == noErr) {
            for (UInt32 j = 0; j < bufferList->mNumberBuffers; j++) {
                if (bufferList->mBuffers[j].mNumberChannels > 0) {
                    hasOutput = YES;
                    break;
                }
            }
        }
        free(bufferList);

        if (!hasOutput) continue;

        // Get device name
        AudioObjectPropertyAddress nameAddress = {
            kAudioDevicePropertyDeviceNameCFString,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };

        CFStringRef deviceName = NULL;
        UInt32 nameSize = sizeof(deviceName);
        status = AudioObjectGetPropertyData(devices[i], &nameAddress, 0, NULL, &nameSize, &deviceName);

        if (status == noErr && deviceName) {
            [outputDevices addObject:(__bridge_transfer NSString *)deviceName];
        }
    }

    free(devices);
    return outputDevices;
}

- (BOOL)setOutputDevice:(nullable NSString *)deviceName {
    // For now, we rely on the system default device
    // Full device selection requires more complex AVAudioEngine configuration
    _outputDeviceName = deviceName;
    NSLog(@"XLAudioPlayer: Output device selection not yet implemented, using system default");
    return YES;
}

#pragma mark - Error Handling

- (void)notifyError:(NSError *)error {
    if ([_delegate respondsToSelector:@selector(audioPlayer:didEncounterError:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate audioPlayer:self didEncounterError:error];
        });
    }
}

@end
