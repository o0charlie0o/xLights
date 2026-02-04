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

@class XLEngineBridge;
@class XLEffectsGridView;
@class XLEffectPaletteView;
@class XLRowHeadingsView;
@class XLScrollCoordinator;
@class XLUndoController;
@class XLPlaybackController;

/// View controller for the Sequencer tab.
///
/// This is the Logic Pro X moment — the effects grid, timeline, waveform,
/// row headings, and playback controls all as high-performance
/// Metal/CoreAnimation-backed views.
///
/// Reference: MetalTimeline spike for the Metal NSView pattern.
@interface XLSequencerViewController : NSViewController

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

/// Reload sequence data from the engine bridge.
/// Call this when a sequence is loaded or unloaded, or when elements/effects change.
- (void)reloadSequenceData;

/// Refresh the view selector dropdown with current views.
/// Called automatically by reloadSequenceData.
- (void)refreshViewSelector;

/// Whether real sequence data is currently loaded (vs demo data).
@property (nonatomic, readonly) BOOL isUsingRealData;

/// Current sequence duration in milliseconds.
@property (nonatomic, readonly) CGFloat sequenceDurationMS;

@end
