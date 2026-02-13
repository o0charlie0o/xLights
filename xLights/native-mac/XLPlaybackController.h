#pragma once

/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import <Foundation/Foundation.h>

@class XLEngineBridge;
@class XLMetalPreviewView;
@class XLPlaybackController;
@class XLAudioPlayer;

/// Delegate protocol for playback state changes.
@protocol XLPlaybackControllerDelegate <NSObject>
@optional

/// Called when playback starts.
- (void)playbackControllerDidStartPlayback:(XLPlaybackController *)controller;

/// Called when playback pauses.
- (void)playbackControllerDidPausePlayback:(XLPlaybackController *)controller;

/// Called when playback stops.
- (void)playbackControllerDidStopPlayback:(XLPlaybackController *)controller;

/// Called when the playback position changes.
- (void)playbackController:(XLPlaybackController *)controller
      didUpdatePositionMS:(NSInteger)positionMS;

/// Called when a frame has been rendered to the preview.
- (void)playbackController:(XLPlaybackController *)controller
       didRenderFrameAtMS:(NSInteger)timeMS;

@end

/// Coordinates real-time playback between the sequencer and preview.
///
/// XLPlaybackController manages the playback loop timing, requests frame renders
/// from the engine, and updates the preview view with rendered pixel data.
/// It uses a high-precision timer (CVDisplayLink-aligned or manual) to ensure
/// smooth playback at the sequence frame rate.
///
/// Usage:
/// 1. Set engineBridge and previewView
/// 2. Call play/pause/stop to control playback
/// 3. Implement delegate to receive position updates
@interface XLPlaybackController : NSObject

/// The engine bridge for playback control and rendering.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// The preview view to update with rendered frames (house preview).
@property (nonatomic, weak) XLMetalPreviewView *previewView;

/// Secondary preview view for the sidebar model preview.
@property (nonatomic, weak) XLMetalPreviewView *sidebarPreviewView;

/// The native audio player for audio playback.
/// If set, uses AVFoundation for audio; otherwise falls back to engine bridge.
@property (nonatomic, strong) XLAudioPlayer *audioPlayer;

/// Delegate for playback state changes.
@property (nonatomic, weak) id<XLPlaybackControllerDelegate> delegate;

#pragma mark - Playback State

/// Whether playback is currently active.
@property (nonatomic, readonly) BOOL isPlaying;

/// Whether playback is paused (vs stopped).
@property (nonatomic, readonly) BOOL isPaused;

/// Current playback position in milliseconds.
@property (nonatomic, readonly) NSInteger positionMS;

/// Sequence duration in milliseconds.
@property (nonatomic, readonly) NSInteger durationMS;

/// Frame time in milliseconds (determines playback rate).
@property (nonatomic, readonly) NSInteger frameTimeMS;

#pragma mark - Playback Options

/// Playback rate multiplier (1.0 = normal speed).
@property (nonatomic, assign) CGFloat playbackRate;

/// Whether to loop playback when reaching the end.
@property (nonatomic, assign) BOOL loopEnabled;

/// Loop region start in milliseconds (-1 = no region, use full sequence).
@property (nonatomic, assign) NSInteger loopRegionStartMS;

/// Loop region end in milliseconds (-1 = no region, use full sequence).
@property (nonatomic, assign) NSInteger loopRegionEndMS;

/// Whether a valid loop region is set.
@property (nonatomic, readonly) BOOL hasLoopRegion;

/// Clear the loop region, reverting to full-sequence looping.
- (void)clearLoopRegion;

/// Whether to render to the preview view during playback.
@property (nonatomic, assign) BOOL renderToPreview;

/// Volume level (0.0-1.0) for audio playback.
@property (nonatomic, assign) CGFloat volume;

/// Load audio for the current sequence. Call after setEngineBridge.
/// @param audioPath Path to the audio file associated with the sequence.
/// @return YES if audio was loaded successfully.
- (BOOL)loadAudioFile:(NSString *)audioPath;

#pragma mark - Playback Control

/// Start playback from the current position.
- (void)play;

/// Pause playback, maintaining current position.
- (void)pause;

/// Stop playback and reset to start.
- (void)stop;

/// Toggle between play and pause.
- (void)togglePlayPause;

/// Seek to a specific position.
- (void)seekToPositionMS:(NSInteger)positionMS;

/// Step forward by one frame.
- (void)stepForward;

/// Step backward by one frame.
- (void)stepBackward;

#pragma mark - Preview Rendering

/// Render and display the frame at the current position.
/// Use this for single-frame preview updates when not playing.
- (void)renderCurrentFrame;

/// Render and display a frame at the specified time.
/// @param timeMS Time position in milliseconds.
- (void)renderFrameAtTime:(NSInteger)timeMS;

/// Whether a background render is currently in progress.
/// When YES, new render requests are dropped to prevent queue buildup.
@property (nonatomic, readonly) BOOL renderInProgress;

@end
