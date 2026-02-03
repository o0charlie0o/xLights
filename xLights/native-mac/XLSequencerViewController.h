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
@class XLRowHeadingsView;

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

@end
