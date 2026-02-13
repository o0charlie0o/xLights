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
@property (nonatomic, assign, readwrite) BOOL renderInProgress;

@property (nonatomic, strong) dispatch_queue_t playbackQueue;
@property (nonatomic, strong) dispatch_queue_t renderQueue;

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
        _renderQueue = dispatch_queue_create("com.xlights.render", DISPATCH_QUEUE_SERIAL);
        _renderInProgress = NO;

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

    // Match the sequence frame rate (e.g. 50ms for 20fps, 25ms for 40fps)
    uint64_t interval = (uint64_t)(_frameTimeMS > 0 ? _frameTimeMS : 50) * NSEC_PER_MSEC;
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
    NSLog(@"XLPlaybackController: play() called — isPlaying=%d isPaused=%d", _isPlaying, _isPaused);

    if (_isPlaying && !_isPaused) return;

    // If resuming from pause, just restart the timer
    BOOL resumingFromPause = _isPlaying && _isPaused;

    [self updateSequenceInfo];

    if (_durationMS <= 0) {
        NSLog(@"XLPlaybackController: Cannot play - no sequence loaded or duration is zero (durationMS=%ld)", (long)_durationMS);
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
    _playOriginMS = resumingFromPause ? _playOriginMS : _positionMS;
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

    // Render the initial frame immediately (don't wait for first timer fire)
    [self renderFrameAtTime:_positionMS];

    // Notify delegate of initial position so playhead updates immediately
    if ([_delegate respondsToSelector:@selector(playbackController:didUpdatePositionMS:)]) {
        [_delegate playbackController:self didUpdatePositionMS:_positionMS];
    }

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

    NSLog(@"XLPlaybackController: Playback started at %ldms, duration %ldms, frameTime %ldms, nativeAudio=%d, hasAudio=%d, previewView=%@",
          (long)_positionMS, (long)_durationMS, (long)_frameTimeMS, _useNativeAudio, (_useNativeAudio && _audioPlayer.isLoaded), _previewView);
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

    // Snap to frame boundary for rendering only (UI shows precise position)
    NSInteger renderPositionMS = positionMS;
    if (_frameTimeMS > 0) {
        renderPositionMS = (positionMS / _frameTimeMS) * _frameTimeMS;
    }

    _positionMS = renderPositionMS;

    // Seek audio to precise position (audio is continuous, no need to snap)
    if (_useNativeAudio && _audioPlayer.isLoaded) {
        [_audioPlayer seekToPosition:(CGFloat)positionMS];
    }

    // Update engine position at frame boundary (for rendering)
    [_engineBridge seek:renderPositionMS];

    // If playing, update start reference with precise position
    if (_isPlaying && !_isPaused) {
        _playbackStartTime = CFAbsoluteTimeGetCurrent();
        _playbackStartPositionMS = positionMS;
    }

    // Render the frame at the snapped position
    [self renderFrameAtTime:renderPositionMS];

    // Update preview position
    if (_previewView) {
        _previewView.playbackPositionMS = positionMS;
    }

    // Notify delegate with precise position for smooth UI
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
    static NSInteger _droppedFrames = 0;
    static NSInteger _totalFrameRequests = 0;
    _totalFrameRequests++;

    if (!_engineBridge) return;

    // Drop frame if a background render is already in progress
    if (_renderInProgress) {
        _droppedFrames++;
        if (_droppedFrames % 10 == 0) {
            NSLog(@"[FrameDrop] Dropped %ld of %ld frames (%.0f%%)",
                  (long)_droppedFrames, (long)_totalFrameRequests,
                  _droppedFrames * 100.0 / _totalFrameRequests);
        }
        return;
    }

    // Clamp time to valid range
    if (timeMS < 0) timeMS = 0;
    if (_durationMS > 0 && timeMS > _durationMS) timeMS = _durationMS;

    _renderInProgress = YES;

    XLEngineBridge *bridge = _engineBridge;
    __weak typeof(self) weakSelf = self;

    dispatch_async(_renderQueue, ^{
        @try {
            CFAbsoluteTime renderStart = CFAbsoluteTimeGetCurrent();

            // FSEQ read + buffer building happens off the main thread
            [bridge renderFrame:timeMS];

            CFAbsoluteTime afterRender = CFAbsoluteTimeGetCurrent();

            // Collect all rendered frame buffers in a single bulk call.
            // Only returns models with valid pixel data (typically 4 of 200),
            // avoiding 200 individual mutex lock/unlock + map lookup cycles.
            NSArray<NSDictionary *> *frameUpdates = [bridge getAllFrameBuffers];

            CFAbsoluteTime afterCollect = CFAbsoluteTimeGetCurrent();
            double renderMS = (afterRender - renderStart) * 1000.0;
            double collectMS = (afterCollect - afterRender) * 1000.0;
            double totalMS = renderMS + collectMS;

            if (totalMS > 40.0) { // Log frames taking > 40ms (near frame budget)
                NSLog(@"[RenderPipeline] @%ldms: render=%.1fms collect=%.1fms total=%.1fms models=%lu",
                      (long)timeMS, renderMS, collectMS, totalMS,
                      (unsigned long)frameUpdates.count);
            }

            // Switch to main thread only for the lightweight UI update
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;

                XLMetalPreviewView *preview = strongSelf.previewView;
                XLMetalPreviewView *sidebarPreview = strongSelf.sidebarPreviewView;
                if (frameUpdates.count > 0 && (preview || sidebarPreview)) {
                    for (NSDictionary *fb in frameUpdates) {
                        NSData *pixels = fb[@"pixels"];
                        NSUInteger width = [fb[@"width"] unsignedIntegerValue];
                        NSUInteger height = [fb[@"height"] unsignedIntegerValue];
                        NSString *name = fb[@"modelName"];

                        if (pixels && pixels.length > 0 && width > 0 && height > 0) {
                            [preview setRenderedPixels:pixels
                                              forModel:name
                                                 width:width
                                                height:height];
                            [sidebarPreview setRenderedPixels:pixels
                                                     forModel:name
                                                        width:width
                                                       height:height];
                        }
                    }

                    [preview updatePreviewForTime:timeMS];
                    [sidebarPreview updatePreviewForTime:timeMS];
                }

                strongSelf.renderInProgress = NO;

                // Notify delegate
                if ([strongSelf.delegate respondsToSelector:@selector(playbackController:didRenderFrameAtMS:)]) {
                    [strongSelf.delegate playbackController:strongSelf didRenderFrameAtMS:timeMS];
                }
            });
        } @catch (NSException *exception) {
            NSLog(@"XLPlaybackController: Exception rendering frame at %ldms: %@ - %@",
                  (long)timeMS, exception.name, exception.reason);
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf) strongSelf.renderInProgress = NO;
            });
        }
    });
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
