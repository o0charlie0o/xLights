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
#import <QuartzCore/CVDisplayLink.h>

@interface XLPlaybackController () <XLAudioPlayerDelegate> {
    CVDisplayLinkRef _displayLink;
    CFAbsoluteTime _lastFrameTime;
    CFAbsoluteTime _playbackStartTime;
    NSInteger _playbackStartPositionMS;
    BOOL _useNativeAudio;
}

@property (nonatomic, assign, readwrite) BOOL isPlaying;
@property (nonatomic, assign, readwrite) BOOL isPaused;
@property (nonatomic, assign, readwrite) NSInteger positionMS;
@property (nonatomic, assign, readwrite) NSInteger durationMS;
@property (nonatomic, assign, readwrite) NSInteger frameTimeMS;

@property (nonatomic, strong) dispatch_queue_t playbackQueue;
@property (nonatomic, strong) NSTimer *playbackTimer;

@end

// Display link callback for frame timing
static CVReturn PlaybackDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                            const CVTimeStamp *inNow,
                                            const CVTimeStamp *inOutputTime,
                                            CVOptionFlags flagsIn,
                                            CVOptionFlags *flagsOut,
                                            void *displayLinkContext) {
    @autoreleasepool {
        XLPlaybackController *controller = (__bridge XLPlaybackController *)displayLinkContext;
        [controller displayLinkFired];
    }
    return kCVReturnSuccess;
}

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

        _playbackQueue = dispatch_queue_create("com.xlights.playback", DISPATCH_QUEUE_SERIAL);

        // Create native audio player
        _audioPlayer = [[XLAudioPlayer alloc] init];
        _audioPlayer.delegate = self;

        [self setupDisplayLink];
    }
    return self;
}

- (void)dealloc {
    [self stopDisplayLink];
}

#pragma mark - Display Link Setup

- (void)setupDisplayLink {
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &PlaybackDisplayLinkCallback, (__bridge void *)self);
}

- (void)startDisplayLink {
    if (_displayLink && !CVDisplayLinkIsRunning(_displayLink)) {
        CVDisplayLinkStart(_displayLink);
    }
}

- (void)stopDisplayLink {
    if (_displayLink && CVDisplayLinkIsRunning(_displayLink)) {
        CVDisplayLinkStop(_displayLink);
    }
}

- (void)displayLinkFired {
    if (!_isPlaying || _isPaused) return;

    // Calculate current playback position based on elapsed time
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime elapsed = now - _playbackStartTime;
    NSInteger newPositionMS = _playbackStartPositionMS + (NSInteger)(elapsed * 1000.0 * _playbackRate);

    // Snap to frame boundaries
    if (_frameTimeMS > 0) {
        newPositionMS = (newPositionMS / _frameTimeMS) * _frameTimeMS;
    }

    // Check for end of sequence
    if (newPositionMS >= _durationMS) {
        if (_loopEnabled) {
            // Loop back to start
            newPositionMS = 0;
            _playbackStartTime = now;
            _playbackStartPositionMS = 0;
        } else {
            // Stop at end
            newPositionMS = _durationMS;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stop];
            });
            return;
        }
    }

    // Only update if position actually changed
    if (newPositionMS != _positionMS) {
        _positionMS = newPositionMS;

        // Render the frame for preview
        if (_renderToPreview) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self renderFrameAtTime:newPositionMS];

                // Notify delegate of position change
                if ([self.delegate respondsToSelector:@selector(playbackController:didUpdatePositionMS:)]) {
                    [self.delegate playbackController:self didUpdatePositionMS:newPositionMS];
                }
            });
        }
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

#pragma mark - Playback Control

- (void)play {
    if (_isPlaying && !_isPaused) return;

    [self updateSequenceInfo];

    if (_durationMS <= 0) {
        NSLog(@"XLPlaybackController: Cannot play - no sequence loaded");
        return;
    }

    _isPlaying = YES;
    _isPaused = NO;
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
    [self startDisplayLink];

    // Start audio playback
    if (_useNativeAudio && _audioPlayer.isLoaded) {
        // Use native AVFoundation audio
        [_audioPlayer playFromPosition:(CGFloat)_positionMS];
    } else {
        // Fall back to engine audio
        [_engineBridge play];
    }

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(playbackControllerDidStartPlayback:)]) {
        [_delegate playbackControllerDidStartPlayback:self];
    }

    NSLog(@"XLPlaybackController: Playback started at %ldms, duration %ldms, frameTime %ldms, nativeAudio=%d",
          (long)_positionMS, (long)_durationMS, (long)_frameTimeMS, _useNativeAudio);
}

- (void)pause {
    if (!_isPlaying || _isPaused) return;

    _isPaused = YES;
    [self stopDisplayLink];

    // Pause audio
    if (_useNativeAudio && _audioPlayer.isLoaded) {
        [_audioPlayer pause];
    } else {
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

    [self stopDisplayLink];

    // Reset position
    _positionMS = 0;

    // Disable preview rendering
    if (_previewView) {
        _previewView.previewRenderingActive = NO;
        _previewView.playbackPositionMS = 0;
    }

    // Stop audio
    if (_useNativeAudio && _audioPlayer.isLoaded) {
        [_audioPlayer stop];
    } else {
        [_engineBridge stop];
    }

    // Notify delegate
    if (wasPlaying) {
        if ([_delegate respondsToSelector:@selector(playbackControllerDidStopPlayback:)]) {
            [_delegate playbackControllerDidStopPlayback:self];
        }
    }

    // Notify of position reset
    if ([_delegate respondsToSelector:@selector(playbackController:didUpdatePositionMS:)]) {
        [_delegate playbackController:self didUpdatePositionMS:0];
    }

    NSLog(@"XLPlaybackController: Playback stopped");
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
    if (!_engineBridge || !_previewView) return;

    // Request the engine to render this frame
    [_engineBridge renderFrame:timeMS];

    // Get rendered pixel data for each model and update the preview
    NSArray<NSString *> *modelNames = [_engineBridge getModelNamesExcludingGroups];
    for (NSString *modelName in modelNames) {
        NSDictionary *frameBuffer = [_engineBridge getFrameBuffer:modelName];
        if (frameBuffer) {
            NSData *pixels = frameBuffer[@"pixels"];
            NSUInteger width = [frameBuffer[@"width"] unsignedIntegerValue];
            NSUInteger height = [frameBuffer[@"height"] unsignedIntegerValue];

            if (pixels && width > 0 && height > 0) {
                [_previewView setRenderedPixels:pixels
                                       forModel:modelName
                                          width:width
                                         height:height];
            }
        }
    }

    // Tell preview to update for this time
    [_previewView updatePreviewForTime:timeMS];

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
    // When using native audio, sync our position to audio position
    // This ensures visual elements stay in sync with audio
    if (_useNativeAudio && _isPlaying && !_isPaused) {
        _positionMS = (NSInteger)positionMS;
    }
}

- (void)audioPlayerDidReachEnd:(XLAudioPlayer *)player {
    // Audio reached end - handle looping or stop
    if (_loopEnabled) {
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
