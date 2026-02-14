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
#import "xLights_Native-Swift.h"
#import <stdatomic.h>

@interface XLPlaybackController () <XLAudioPlayerDelegate> {
    CFAbsoluteTime _lastFrameTime;
    CFAbsoluteTime _playbackStartTime;
    NSInteger _playbackStartPositionMS;
    NSInteger _playOriginMS;  // Position where play was pressed; stop returns here
    BOOL _useNativeAudio;
    dispatch_source_t _fallbackTimer;
    atomic_bool _renderInProgress;  // Atomic: written on render queue, read on main queue

    // Render loop: runs on _renderQueue, decoupled from main queue
    dispatch_source_t _renderLoopTimer;
    atomic_bool _renderLoopActive;
    NSInteger _lastRenderedFrameMS;
}

@property (nonatomic, assign, readwrite) BOOL isPlaying;
@property (nonatomic, assign, readwrite) BOOL isPaused;
@property (nonatomic, assign, readwrite) NSInteger positionMS;
@property (nonatomic, assign, readwrite) NSInteger durationMS;
@property (nonatomic, assign, readwrite) NSInteger frameTimeMS;

@property (nonatomic, strong) dispatch_queue_t playbackQueue;
@property (nonatomic, strong) dispatch_queue_t renderQueue;

@end

@implementation XLPlaybackController

@dynamic sidebarPreviewView;
@dynamic renderInProgress;

- (XLMetalPreviewView *)sidebarPreviewView {
    return [XLSwiftUIWindowHelper shared].sidebarPreviewView;
}

- (BOOL)renderInProgress {
    return atomic_load(&_renderInProgress);
}

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
        _lastRenderedFrameMS = -1;

        _playbackQueue = dispatch_queue_create("com.xlights.playback", DISPATCH_QUEUE_SERIAL);
        _renderQueue = dispatch_queue_create("com.xlights.render", DISPATCH_QUEUE_SERIAL);
        atomic_init(&_renderInProgress, false);
        atomic_init(&_renderLoopActive, false);

        // Create native audio player
        _audioPlayer = [[XLAudioPlayer alloc] init];
        _audioPlayer.delegate = self;
    }
    return self;
}

- (void)dealloc {
    [self stopPlaybackTimer];
    [self stopRenderLoop];
}

#pragma mark - Render Loop (runs on render queue, independent of main queue)

/// Start a timer on the render queue that pulls audio position directly
/// and renders frames without going through the main queue. This makes
/// playback immune to main-queue stalls (system volume HUD, UI events, etc.).
- (void)startRenderLoop {
    [self stopRenderLoop];

    _lastRenderedFrameMS = -1;
    atomic_store(&_renderLoopActive, true);

    // Poll every 8ms on the render queue — frequent enough for 40fps (25ms/frame),
    // low overhead when no new frame is available (just reads audio position).
    _renderLoopTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _renderQueue);
    dispatch_source_set_timer(_renderLoopTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              8 * NSEC_PER_MSEC,
                              1 * NSEC_PER_MSEC);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_renderLoopTimer, ^{
        [weakSelf renderLoopTick];
    });

    dispatch_resume(_renderLoopTimer);
    NSLog(@"XLPlaybackController: Render loop started on render queue (8ms poll)");
}

- (void)stopRenderLoop {
    atomic_store(&_renderLoopActive, false);
    if (_renderLoopTimer) {
        dispatch_source_cancel(_renderLoopTimer);
        _renderLoopTimer = nil;
        NSLog(@"XLPlaybackController: Render loop stopped");
    }
}

/// Called every 8ms on _renderQueue. Reads audio position directly (no main queue),
/// snaps to frame boundary, and renders if we've crossed a new frame.
- (void)renderLoopTick {
    if (!atomic_load(&_renderLoopActive)) return;

    XLEngineBridge *bridge = _engineBridge;
    if (!bridge) return;

    // Read position directly from audio player — thread-safe, no main queue needed.
    // AVAudioPlayerNode.lastRenderTime and playerTimeForNodeTime: are thread-safe.
    CGFloat rawPositionMS;
    if (_useNativeAudio && _audioPlayer.isLoaded) {
        rawPositionMS = _audioPlayer.currentPositionMS;
    } else {
        // Fallback: wall-clock estimation
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        CFAbsoluteTime elapsed = now - _playbackStartTime;
        rawPositionMS = _playbackStartPositionMS + (CGFloat)(elapsed * 1000.0 * _playbackRate);
    }

    NSInteger positionMS = (NSInteger)rawPositionMS;

    // Clamp
    if (positionMS < 0) positionMS = 0;
    if (_durationMS > 0 && positionMS >= _durationMS) {
        // End of sequence — let the audio player's completion handler deal with looping/stopping
        return;
    }

    // Handle loop region
    if (self.hasLoopRegion && positionMS >= _loopRegionEndMS) {
        // The audio player delegate handles the actual seek-back on the main queue;
        // we just clamp our render position here to avoid rendering past the boundary.
        positionMS = _loopRegionStartMS;
    }

    // Snap to frame boundary
    NSInteger snappedMS = positionMS;
    if (_frameTimeMS > 0) {
        snappedMS = (positionMS / _frameTimeMS) * _frameTimeMS;
    }

    // Only render if we've crossed a new frame boundary
    if (snappedMS == _lastRenderedFrameMS) return;
    _lastRenderedFrameMS = snappedMS;

    // Render directly on this queue (we're already on _renderQueue)
    @try {
        CFAbsoluteTime renderStart = CFAbsoluteTimeGetCurrent();

        [bridge renderFrame:snappedMS];

        CFAbsoluteTime afterRender = CFAbsoluteTimeGetCurrent();

        // Collect all rendered frame buffers — immutable copies, safe to hand off
        NSArray<NSDictionary *> *frameUpdates = [bridge getAllFrameBuffers];

        CFAbsoluteTime afterCollect = CFAbsoluteTimeGetCurrent();
        double renderMS = (afterRender - renderStart) * 1000.0;
        double collectMS = (afterCollect - afterRender) * 1000.0;
        double totalMS = renderMS + collectMS;

        if (totalMS > 40.0) {
            NSLog(@"[PlaybackTrace] RenderLoop @%ldms: render=%.1fms collect=%.1fms total=%.1fms models=%lu",
                  (long)snappedMS, renderMS, collectMS, totalMS,
                  (unsigned long)frameUpdates.count);
        }

        // Deliver pixel data to main queue for preview update.
        // This is fire-and-forget — if the main queue is stalled, pixel updates
        // queue up and get applied when it unblocks. The render loop continues
        // independently regardless.
        __weak typeof(self) weakSelf = self;
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

                [preview updatePreviewForTime:snappedMS];
                [sidebarPreview updatePreviewForTime:snappedMS];
            }

            // Notify delegate
            if ([strongSelf.delegate respondsToSelector:@selector(playbackController:didRenderFrameAtMS:)]) {
                [strongSelf.delegate playbackController:strongSelf didRenderFrameAtMS:snappedMS];
            }
        });
    } @catch (NSException *exception) {
        NSLog(@"XLPlaybackController: Exception in render loop at %ldms: %@ - %@",
              (long)snappedMS, exception.name, exception.reason);
    }
}

#pragma mark - UI Position Timer (main queue — cosmetic only, not render-critical)

- (void)startPlaybackTimer {
    // When using native audio, the audio player's timer drives UI position updates.
    // Only start the fallback timer for sequences without audio.
    if (_useNativeAudio && _audioPlayer.isLoaded) {
        NSLog(@"XLPlaybackController: Using audio player timer for UI position updates");
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
    }
}

- (void)playbackTimerFired {
    // When using native audio, the audio player's timer drives UI updates
    // This method is only used for sequences without audio or when using engine audio
    if (_useNativeAudio && _audioPlayer.isLoaded) {
        return;  // Audio player callback handles UI updates
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

    // Notify delegate with precise position for smooth UI updates (playhead, transport bar)
    if ([_delegate respondsToSelector:@selector(playbackController:didUpdatePositionMS:)]) {
        [_delegate playbackController:self didUpdatePositionMS:precisePositionMS];
    }

    // Update _positionMS for consistency
    NSInteger snappedPositionMS = precisePositionMS;
    if (_frameTimeMS > 0) {
        snappedPositionMS = (precisePositionMS / _frameTimeMS) * _frameTimeMS;
    }
    _positionMS = snappedPositionMS;
    // Note: actual rendering is handled by the render loop on the render queue
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

    // Start the UI position timer (for playhead, transport bar — cosmetic only)
    [self startPlaybackTimer];

    // Start the render loop on the render queue (decoupled from main queue).
    // This pulls audio position directly and renders independently,
    // so main-queue stalls (system volume HUD, UI events) don't cause frame drops.
    [self startRenderLoop];

    // Render the initial frame immediately (don't wait for first timer fire)
    [self renderFrameAtTime:_positionMS];

    // Notify delegate of initial position so playhead updates immediately
    if ([_delegate respondsToSelector:@selector(playbackController:didUpdatePositionMS:)]) {
        [_delegate playbackController:self didUpdatePositionMS:_positionMS];
    }

    // Start audio playback (if audio is available)
    if (_useNativeAudio && _audioPlayer.isLoaded) {
        // Ensure engine audio is stopped to prevent double playback
        if (_engineBridge) {
            [_engineBridge stop];
        }
        // Use native AVFoundation audio — always specify position explicitly
        // to ensure we play from _positionMS regardless of audio player's
        // internal state (which may have been reset by a prior stop)
        [_audioPlayer playFromPosition:(CGFloat)_positionMS];
    } else if (_engineBridge) {
        // Stop native audio first
        [_audioPlayer stop];
        // Fall back to engine audio — seek to correct position before playing
        [_engineBridge seek:_positionMS];
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
    [self stopRenderLoop];

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
    [self stopRenderLoop];

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
        // Seek engine to return position so it matches UI state
        [_engineBridge seek:returnPosition];
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
        // Reset render loop's frame tracking so next tick renders immediately
        _lastRenderedFrameMS = -1;
    }

    // Render the frame at the snapped position (one-shot, for immediate feedback)
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

#pragma mark - One-Shot Preview Rendering (for seek, step, initial frame)

- (void)renderCurrentFrame {
    [self renderFrameAtTime:_positionMS];
}

- (void)renderFrameAtTime:(NSInteger)timeMS {
    if (!_engineBridge) return;

    // Drop frame if a background render is already in progress
    if (atomic_load(&_renderInProgress)) {
        return;
    }

    // Clamp time to valid range
    if (timeMS < 0) timeMS = 0;
    if (_durationMS > 0 && timeMS > _durationMS) timeMS = _durationMS;

    atomic_store(&_renderInProgress, true);

    XLEngineBridge *bridge = _engineBridge;
    __weak typeof(self) weakSelf = self;

    dispatch_async(_renderQueue, ^{
        @try {
            [bridge renderFrame:timeMS];
            NSArray<NSDictionary *> *frameUpdates = [bridge getAllFrameBuffers];

            atomic_store(&_renderInProgress, false);

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

                if ([strongSelf.delegate respondsToSelector:@selector(playbackController:didRenderFrameAtMS:)]) {
                    [strongSelf.delegate playbackController:strongSelf didRenderFrameAtMS:timeMS];
                }
            });
        } @catch (NSException *exception) {
            NSLog(@"XLPlaybackController: Exception rendering frame at %ldms: %@ - %@",
                  (long)timeMS, exception.name, exception.reason);
            atomic_store(&_renderInProgress, false);
        }
    });
}

#pragma mark - XLAudioPlayerDelegate

- (void)audioPlayer:(XLAudioPlayer *)player didChangeState:(XLAudioPlaybackState)state {
    // Audio state changes are handled internally
}

- (void)audioPlayer:(XLAudioPlayer *)player didUpdatePosition:(CGFloat)positionMS {
    // UI position updates only — rendering is handled by the render loop on the render queue.
    // This callback comes from the audio player's timer via the main queue. If the main queue
    // is stalled (system volume HUD, etc.), these updates are delayed, but that only affects
    // cosmetic UI (playhead position) — not frame rendering.
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

        // Update UI position (playhead, transport bar, waveform cursor, etc.)
        if ([_delegate respondsToSelector:@selector(playbackController:didUpdatePositionMS:)]) {
            [_delegate playbackController:self didUpdatePositionMS:audioPositionMS];
        }

        // Track position for consistency
        NSInteger snappedPositionMS = audioPositionMS;
        if (_frameTimeMS > 0) {
            snappedPositionMS = (audioPositionMS / _frameTimeMS) * _frameTimeMS;
        }
        _positionMS = snappedPositionMS;
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
