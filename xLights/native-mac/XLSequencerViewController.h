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
@class XLTimelineRulerView;

/// View controller for the Sequencer tab.
///
/// This is the Logic Pro X moment — the effects grid, timeline, waveform,
/// row headings, and playback controls all as high-performance
/// Metal/CoreAnimation-backed views.
///
/// Reference: MetalTimeline spike for the Metal NSView pattern.
@interface XLSequencerViewController : NSViewController

@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// The timeline ruler at the top of the sequencer.
@property (nonatomic, strong, readonly) XLTimelineRulerView *timelineRuler;

@end
