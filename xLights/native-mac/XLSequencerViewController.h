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

#import <Cocoa/Cocoa.h>
#import "input/XLKeyboardHandler.h"

@class XLEngineBridge;
@class XLEffectsGridView;
@class XLEffectPaletteView;
@class XLRowHeadingsView;
@class XLScrollCoordinator;
@class XLUndoController;
@class XLPlaybackController;
@class XLKeyboardHandler;
@class XLRenderProgressIndicator;

/// View controller for the Sequencer tab.
///
/// This is the Logic Pro X moment — the effects grid, timeline, waveform,
/// row headings, and playback controls all as high-performance
/// Metal/CoreAnimation-backed views.
///
/// Reference: MetalTimeline spike for the Metal NSView pattern.
@interface XLSequencerViewController : NSViewController <XLKeyboardActionDelegate>

@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// The Metal-backed effects grid (the core timeline view).
@property (nonatomic, strong, readonly) XLEffectsGridView *effectsGridView;

/// The row headings view (element names, expand/collapse, mute/solo).
@property (nonatomic, strong, readonly) XLRowHeadingsView *rowHeadingsView;

/// The effect palette view for selecting effect types to drag onto the timeline.
@property (nonatomic, strong, readonly) XLEffectPaletteView *effectPaletteView;

/// Show or hide the effect palette sidebar.
@property (nonatomic, assign) BOOL effectPaletteVisible;

/// The scroll coordinator that synchronizes scrolling and zooming across all views.
@property (nonatomic, strong, readonly) XLScrollCoordinator *scrollCoordinator;

/// The undo controller for managing undo/redo operations on effects.
@property (nonatomic, strong, readonly) XLUndoController *undoController;

/// Playback controller for coordinated audio and preview playback.
@property (nonatomic, strong) XLPlaybackController *playbackController;

/// Keyboard handler for processing key bindings.
@property (nonatomic, strong) XLKeyboardHandler *keyboardHandler;

/// Render progress indicator in the toolbar (set by XLMainWindowController).
@property (nonatomic, weak) XLRenderProgressIndicator *renderProgressIndicator;

/// Reload sequence data from the engine bridge.
/// Call this when a sequence is loaded or unloaded, or when elements/effects change.
/// Does NOT restore zoom level -- use loadZoomLevelForCurrentSequence for that.
- (void)reloadSequenceData;

/// Load the saved zoom level for the current sequence.
/// Call this only when initially opening/creating a sequence, not on every refresh.
- (void)loadZoomLevelForCurrentSequence;

/// Refresh the view selector dropdown with current views.
/// Called automatically by reloadSequenceData.
- (void)refreshViewSelector;

/// Refresh the timing track selector dropdown with current timing tracks.
- (void)refreshTimingTrackSelector;

#pragma mark - Timing Track Actions
- (void)addTimingTrack:(id)sender;
- (void)importTiming:(id)sender;
- (void)generateTiming:(id)sender;

#pragma mark - Playback Actions
/// Start playback.
- (void)play;

/// Pause playback.
- (void)pause;

/// Stop playback and return to play origin.
- (void)stop;

/// Render all effects.
- (void)renderAll;

#pragma mark - Zoom and Navigation Actions
/// Zoom in on the timeline (increase zoom level).
- (void)zoomIn:(id)sender;

/// Zoom out on the timeline (decrease zoom level).
- (void)zoomOut:(id)sender;

/// Zoom to fit the entire sequence in the view.
- (void)zoomToFit:(id)sender;

/// Seek to the start of the sequence.
- (void)seekToStart:(id)sender;

/// Seek to the end of the sequence.
- (void)seekToEnd:(id)sender;

#pragma mark - House Preview
/// Toggle the floating house preview window.
- (void)toggleHousePreview;

#pragma mark - Song Region Overlay
/// Set whether the song region color overlay is visible in the effects grid.
- (void)setSongRegionOverlayVisible:(BOOL)visible;

#pragma mark - Audio Stems
/// Toggle stems panel visibility (View menu).
- (void)toggleStemsPanel:(id)sender;
/// Import audio stem files via file picker.
- (void)importAudioStems:(id)sender;
/// Import stems from a folder (e.g., Demucs output).
- (void)importStemsFromFolder:(id)sender;
/// Remove all audio stems (with confirmation).
- (void)removeAllAudioStems:(id)sender;

/// Whether real sequence data is currently loaded (vs demo data).
@property (nonatomic, readonly) BOOL isUsingRealData;

/// Current sequence duration in milliseconds.
@property (nonatomic, readonly) CGFloat sequenceDurationMS;

@end
