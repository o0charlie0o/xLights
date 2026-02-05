/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLPlaybackController.h"
#import "XLEngineBridge.h"
#import "layout/XLMetalPreviewView.h"
#import "sequencer/XLAudioPlayer.h"

@interface XLPlaybackController () <XLAudioPlayerDelegate> {
    CFAbsoluteTime _lastFrameTime;
    CFAbsoluteTime _playbackStartTime;
    NSInteger _playbackStartPositionMS;
    NSInteger _playOriginMS;  // Position where play was pressed; stop returns here
    BOOL _useNativeAudio;
    dispatch_source_t _fallbackTimer;
}

@property (nonatomic, assign, readwrite) BOOL isPlaying;
@property (nonatomic, assign, readwrite) BOOL isPaused;
@property (nonatomic, assign, readwrite) NSInteger positionMS;
@property (nonatomic, assign, readwrite) NSInteger durationMS;
@property (nonatomic, assign, readwrite) NSInteger frameTimeMS;

@property (nonatomic, strong) dispatch_queue_t playbackQueue;

@end

@implementation XLPlaybackController

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _playbackRate = 1.0;
        _loopEnabled = NO;
        _renderToPreview = YES;
        _isPlaying = NO;
        _isPaused = NO;
        _positionMS = 0;
        _durationMS = 0;
        _frameTimeMS = 50; // Default 20fps
        _volume = 1.0;
        _useNativeAudio = NO;
        _playOriginMS = 0;
        _loopRegionStartMS = -1;
        _loopRegionEndMS = -1;

        _playbackQueue = dispatch_queue_create("com.xlights.playback", DISPATCH_QUEUE_SERIAL);

        // Create native audio player
        _audioPlayer = [[XLAudioPlayer alloc] init];
        _audioPlayer.delegate = self;
    }
    return self;
}

- (void)dealloc {
    [self stopPlaybackTimer];
}

#pragma mark - Playback Timer

- (void)startPlaybackTimer {
    // When using native audio, the audio player's timer drives updates
    // Only start the fallback timer for sequences without audio
    if (_useNativeAudio && _audioPlayer.isLoaded) {
        NSLog(@"XLPlaybackController: Using audio player timer for position updates");
        return;
    }

    [self stopPlaybackTimer];

    NSLog(@"XLPlaybackController: Starting fallback GCD timer for non-audio playback");

    // Use GCD dispatch_source for reliable timing (same approach as XLAudioPlayer)
    _fallbackTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());

    // 50ms interval (20Hz) like original xLights
    uint64_t interval = 50 * NSEC_PER_MSEC;
    uint64_t leeway = 1 * NSEC_PER_MSEC;  // 1ms leeway

    dispatch_source_set_timer(_fallbackTimer,
                              dispatch_time(DISPATCH_TIME_NOW, interval),
                              interval,
                              leeway);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_fallbackTimer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf playbackTimerFired];
        }
    });

    dispatch_resume(_fallbackTimer);
}

- (void)stopPlaybackTimer {
    if (_fallbackTimer) {
        dispatch_source_cancel(_fallbackTimer);
        _fallbackTimer = nil;
        NSLog(@"XLPlaybackController: Fallback timer stopped");
    }
}

- (void)playbackTimerFired {
    // When using native audio, the audio player's timer drives updates
    // This method is only used for sequences without audio or when using engine audio
    if (_useNativeAudio && _audioPlayer.isLoaded) {
        return;  // Audio player callback handles updates
    }

    if (!_isPlaying || _isPaused) return;

    // Calculate current playback position based on elapsed time (wall clock timing)
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime elapsed = now - _playbackStartTime;
    NSInteger precisePositionMS = _playbackStartPositionMS + (NSInteger)(elapsed * 1000.0 * _playbackRate);

    // Clamp to valid range
    if (precisePositionMS < 0) precisePositionMS = 0;

    // Check for loop region or end of sequence
    if (self.hasLoopRegion && precisePositionMS >= _loopRegionEndMS) {
        // Loop back to region start
        precisePositionMS = _loopRegionStartMS;
        _playbackStartTime = now;
        _playbackStartPositionMS = _loopRegionStartMS;
    } else if (precisePositionMS >= _durationMS) {
        if (_loopEnabled) {
            // Loop back to start
            precisePositionMS = 0;
            _playbackStartTime = now;
            _playbackStartPositionMS = 0;
        } else {
            // Stop at end
            precisePositionMS = _durationMS;
            [self stop];
            return;
        }
    }

    // Notify delegate with precise position for smooth UI updates
    if ([_delegate respondsToSelector:@selector(playbackController:didUpdatePositionMS:)]) {
        [_delegate playbackController:self didUpdatePositionMS:precisePositionMS];
    }

    // Snap to frame boundaries for rendering (we only render at sequence frame rate)
    NSInteger snappedPositionMS = precisePositionMS;
    if (_frameTimeMS > 0) {
        snappedPositionMS = (precisePositionMS / _frameTimeMS) * _frameTimeMS;
    }

    // Render the current frame and send pixel data to the preview view
    if (snappedPositionMS != _positionMS) {
        _positionMS = snappedPositionMS;
        [self renderFrameAtTime:snappedPositionMS];
    }
}

#pragma mark - Engine Bridge Updates

- (void)setEngineBridge:(XLEngineBridge *)engineBridge {
    _engineBridge = engineBridge;
    [self updateSequenceInfo];
}

- (void)updateSequenceInfo {
    if (!_engineBridge || ![_engineBridge isSequenceLoaded]) {
        _durationMS = 0;
        _frameTimeMS = 50;
        return;
    }

    _durationMS = [_engineBridge getDuration];
    _frameTimeMS = [_engineBridge getFrameTimeMS];
    if (_frameTimeMS <= 0) _frameTimeMS = 50; // Default to 20fps
}

#pragma mark - Audio Loading

- (BOOL)loadAudioFile:(NSString *)audioPath {
    if (!audioPath || audioPath.length == 0) {
        _useNativeAudio = NO;
        return NO;
    }

    // Check if file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:audioPath]) {
        NSLog(@"XLPlaybackController: Audio file not found: %@", audioPath);
        _useNativeAudio = NO;
        return NO;
    }

    // Load into native audio player
    BOOL success = [_audioPlayer loadAudioFile:audioPath];
    _useNativeAudio = success;

    if (success) {
        _audioPlayer.playbackRate = _playbackRate;
        _audioPlayer.volume = _volume;
        _audioPlayer.loopEnabled = _loopEnabled;
        NSLog(@"XLPlaybackController: Loaded native audio: %@", audioPath.lastPathComponent);
    } else {
        NSLog(@"XLPlaybackController: Failed to load native audio, will use engine audio");
    }

    return success;
}

#pragma mark - Property Setters

- (void)setPlaybackRate:(CGFloat)playbackRate {
    _playbackRate = playbackRate;
    _audioPlayer.playbackRate = playbackRate;
}

- (void)setLoopEnabled:(BOOL)loopEnabled {
    _loopEnabled = loopEnabled;
    _audioPlayer.loopEnabled = loopEnabled;
}

- (void)setVolume:(CGFloat)volume {
    _volume = fmax(0.0, fmin(1.0, volume));
    _audioPlayer.volume = _volume;
}

- (BOOL)hasLoopRegion {
    return _loopRegionStartMS >= 0 && _loopRegionEndMS >= 0 && _loopRegionEndMS > _loopRegionStartMS;
}

- (void)clearLoopRegion {
    _loopRegionStartMS = -1;
    _loopRegionEndMS = -1;
}

#pragma mark - Playback Control

- (void)play {
    if (_isPlaying && !_isPaused) return;

    [self updateSequenceInfo];

    if (_durationMS <= 0) {
        NSLog(@"XLPlaybackController: Cannot play - no sequence loaded or duration is zero");
        // Notify delegate of failure
        if ([_delegate respondsToSelector:@selector(playbackControllerDidStopPlayback:)]) {
            [_delegate playbackControllerDidStopPlayback:self];
        }
        return;
    }

    // Clamp position to valid range
    if (_positionMS < 0) _positionMS = 0;
    if (_positionMS >= _durationMS) _positionMS = 0;

    // If loop region is set, ensure we start within it
    if (self.hasLoopRegion) {
        if (_positionMS < _loopRegionStartMS || _positionMS >= _loopRegionEndMS) {
            _positionMS = _loopRegionStartMS;
        }
    }

    _isPlaying = YES;
    _isPaused = NO;
    _playOriginMS = _positionMS;  // Remember where play was pressed
    _playbackStartTime = CFAbsoluteTimeGetCurrent();
    _playbackStartPositionMS = _positionMS;
    _lastFrameTime = _playbackStartTime;

    // Enable preview rendering
    if (_previewView) {
        _previewView.previewRenderingActive = YES;
        _previewView.sequenceDurationMS = _durationMS;
        _previewView.frameTimeMS = _frameTimeMS;
    }

    // Start the playback loop (for frame timing and preview rendering)
    [self startPlaybackTimer];

    // Start audio playback (if audio is available)
    if (_useNativeAudio && _audioPlayer.isLoaded) {
        // Stop engine audio first to prevent double playback
        if (_engineBridge) {
            [_engineBridge stop];
        }
        // Use native AVFoundation audio
        [_audioPlayer playFromPosition:(CGFloat)_positionMS];
    } else if (_engineBridge) {
        // Stop native audio first
        [_audioPlayer stop];
        // Fall back to engine audio
        [_engineBridge play];
    }
    // Note: Playback can continue without audio for sequences without media files

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(playbackControllerDidStartPlayback:)]) {
        [_delegate playbackControllerDidStartPlayback:self];
    }

    NSLog(@"XLPlaybackController: Playback started at %ldms, duration %ldms, frameTime %ldms, nativeAudio=%d, hasAudio=%d",
          (long)_positionMS, (long)_durationMS, (long)_frameTimeMS, _useNativeAudio, (_useNativeAudio && _audioPlayer.isLoaded));
}

- (void)pause {
    if (!_isPlaying || _isPaused) return;

    _isPaused = YES;
    [self stopPlaybackTimer];

    // Pause both audio systems to ensure both are paused
    [_audioPlayer pause];
    if (_engineBridge) {
        [_engineBridge pause];
    }

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(playbackControllerDidPausePlayback:)]) {
        [_delegate playbackControllerDidPausePlayback:self];
    }

    NSLog(@"XLPlaybackController: Playback paused at %ldms", (long)_positionMS);
}

- (void)stop {
    BOOL wasPlaying = _isPlaying;
    _isPlaying = NO;
    _isPaused = NO;

    [self stopPlaybackTimer];

    // Return to where play was originally pressed
    NSInteger returnPosition = wasPlaying ? _playOriginMS : 0;
    _positionMS = returnPosition;

    // Disable preview rendering
    if (_previewView) {
        _previewView.previewRenderingActive = NO;
        _previewView.playbackPositionMS = returnPosition;
    }

    // Stop both audio systems to ensure no double playback
    [_audioPlayer stop];
    if (_engineBridge) {
        [_engineBridge stop];
    }

    // Notify delegate
    if (wasPlaying) {
        if ([_delegate respondsToSelector:@selector(playbackControllerDidStopPlayback:)]) {
            [_delegate playbackControllerDidStopPlayback:self];
        }
    }

    // Notify of position reset to play origin
    if ([_delegate respondsToSelector:@selector(playbackController:didUpdatePositionMS:)]) {
        [_delegate playbackController:self didUpdatePositionMS:returnPosition];
    }

    NSLog(@"XLPlaybackController: Playback stopped, returning to %ldms", (long)returnPosition);
}

- (void)togglePlayPause {
    if (_isPlaying && !_isPaused) {
        [self pause];
    } else {
        [self play];
    }
}

- (void)seekToPositionMS:(NSInteger)positionMS {
    // Clamp to valid range
    if (positionMS < 0) positionMS = 0;
    if (_durationMS > 0 && positionMS > _durationMS) {
        positionMS = _durationMS;
    }

    // Snap to frame boundary
    if (_frameTimeMS > 0) {
        positionMS = (positionMS / _frameTimeMS) * _frameTimeMS;
    }

    _positionMS = positionMS;

    // Seek audio
    if (_useNativeAudio && _audioPlayer.isLoaded) {
        [_audioPlayer seekToPosition:(CGFloat)positionMS];
    }

    // Update engine position (for rendering, not audio)
    [_engineBridge seek:positionMS];

    // If playing, update start reference
    if (_isPlaying && !_isPaused) {
        _playbackStartTime = CFAbsoluteTimeGetCurrent();
        _playbackStartPositionMS = positionMS;
    }

    // Render the frame at the new position
    [self renderFrameAtTime:positionMS];

    // Update preview position
    if (_previewView) {
        _previewView.playbackPositionMS = positionMS;
    }

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(playbackController:didUpdatePositionMS:)]) {
        [_delegate playbackController:self didUpdatePositionMS:positionMS];
    }
}

- (void)stepForward {
    NSInteger newPosition = _positionMS + _frameTimeMS;
    if (newPosition > _durationMS) {
        newPosition = _durationMS;
    }
    [self seekToPositionMS:newPosition];
}

- (void)stepBackward {
    NSInteger newPosition = _positionMS - _frameTimeMS;
    if (newPosition < 0) {
        newPosition = 0;
    }
    [self seekToPositionMS:newPosition];
}

#pragma mark - Preview Rendering

- (void)renderCurrentFrame {
    [self renderFrameAtTime:_positionMS];
}

- (void)renderFrameAtTime:(NSInteger)timeMS {
    // NOTE: This method is called for seek/scrub operations (user-initiated),
    // NOT during playback. During playback, we read pre-rendered data from _seqData.
    // This must run on the main thread because the C++ engine uses wxWidgets.

    if (!_engineBridge) {
        return;
    }

    // Ensure we're on main thread for wxWidgets calls
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self renderFrameAtTime:timeMS];
        });
        return;
    }

    // Clamp time to valid range
    if (timeMS < 0) timeMS = 0;
    if (_durationMS > 0 && timeMS > _durationMS) timeMS = _durationMS;

    // Request the engine to render this frame
    @try {
        [_engineBridge renderFrame:timeMS];

        // Get rendered pixel data for each model and update the preview
        if (_previewView) {
            NSArray<NSString *> *modelNames = [_engineBridge getModelNamesExcludingGroups];
            if (modelNames && modelNames.count > 0) {
                for (NSString *modelName in modelNames) {
                    if (!modelName || modelName.length == 0) continue;

                    NSDictionary *frameBuffer = [_engineBridge getFrameBuffer:modelName];
                    if (frameBuffer) {
                        NSData *pixels = frameBuffer[@"pixels"];
                        NSUInteger width = [frameBuffer[@"width"] unsignedIntegerValue];
                        NSUInteger height = [frameBuffer[@"height"] unsignedIntegerValue];

                        if (pixels && pixels.length > 0 && width > 0 && height > 0) {
                            [_previewView setRenderedPixels:pixels
                                                   forModel:modelName
                                                      width:width
                                                     height:height];
                        }
                    }
                }
            }

            [_previewView updatePreviewForTime:timeMS];
        }
    } @catch (NSException *exception) {
        NSLog(@"XLPlaybackController: Exception rendering frame at %ldms: %@ - %@",
              (long)timeMS, exception.name, exception.reason);
    }

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(playbackController:didRenderFrameAtMS:)]) {
        [_delegate playbackController:self didRenderFrameAtMS:timeMS];
    }
}

#pragma mark - XLAudioPlayerDelegate

- (void)audioPlayer:(XLAudioPlayer *)player didChangeState:(XLAudioPlaybackState)state {
    // Audio state changes are handled internally
    // The display link callback still controls frame timing
}

- (void)audioPlayer:(XLAudioPlayer *)player didUpdatePosition:(CGFloat)positionMS {
    // When using native audio, the audio player's timer drives our updates
    // This ensures visual elements stay perfectly in sync with audio
    if (_useNativeAudio && _isPlaying && !_isPaused) {
        NSInteger audioPositionMS = (NSInteger)positionMS;

        // Check loop region boundary
        if (self.hasLoopRegion && audioPositionMS >= _loopRegionEndMS) {
            // Seek audio back to region start
            [_audioPlayer seekToPosition:(CGFloat)_loopRegionStartMS];
            _playbackStartTime = CFAbsoluteTimeGetCurrent();
            _playbackStartPositionMS = _loopRegionStartMS;
            audioPositionMS = _loopRegionStartMS;
        }

        // Notify delegate with the audio-driven position for smooth UI updates
        if ([_delegate respondsToSelector:@selector(playbackController:didUpdatePositionMS:)]) {
            [_delegate playbackController:self didUpdatePositionMS:audioPositionMS];
        }

        // Snap to frame boundaries for position tracking
        NSInteger snappedPositionMS = audioPositionMS;
        if (_frameTimeMS > 0) {
            snappedPositionMS = (audioPositionMS / _frameTimeMS) * _frameTimeMS;
        }

        if (snappedPositionMS != _positionMS) {
            _positionMS = snappedPositionMS;
            [self renderFrameAtTime:snappedPositionMS];
        }
    }
}

- (void)audioPlayerDidReachEnd:(XLAudioPlayer *)player {
    // Audio reached end - handle loop region, looping, or stop
    if (self.hasLoopRegion) {
        // Seek back to region start
        [_audioPlayer seekToPosition:(CGFloat)_loopRegionStartMS];
        [_audioPlayer playFromPosition:(CGFloat)_loopRegionStartMS];
        _playbackStartTime = CFAbsoluteTimeGetCurrent();
        _playbackStartPositionMS = _loopRegionStartMS;
    } else if (_loopEnabled) {
        // Audio player handles its own looping
        _playbackStartTime = CFAbsoluteTimeGetCurrent();
        _playbackStartPositionMS = 0;
    } else {
        // Stop playback
        dispatch_async(dispatch_get_main_queue(), ^{
            [self stop];
        });
    }
}

- (void)audioPlayer:(XLAudioPlayer *)player didEncounterError:(NSError *)error {
    NSLog(@"XLPlaybackController: Audio error: %@", error.localizedDescription);

    // Fall back to engine audio if native audio fails
    _useNativeAudio = NO;

    // If we were playing, restart with engine audio
    if (_isPlaying && !_isPaused) {
        [_engineBridge play];
    }
}

@end
