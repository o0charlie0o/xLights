/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

#import <Cocoa/Cocoa.h>

@class XLStemData;

/// Height of a single mini waveform row in points.
static const CGFloat kMiniWaveformHeight = 30.0;

/// Lightweight CALayer-backed view rendering one stem's waveform.
/// Parent triggers redraws (no CVDisplayLink — avoids per-stem timer overhead).
@interface XLMiniWaveformView : NSView

/// The stem data to render (buckets, color, name).
@property (nonatomic, strong) XLStemData *stemData;

/// Current zoom level (pixels per millisecond). Set by scroll coordinator.
@property (nonatomic, assign) CGFloat zoomLevel;

/// Current horizontal scroll offset in points. Set by scroll coordinator.
@property (nonatomic, assign) CGFloat scrollOffsetX;

/// Total sequence length in milliseconds (for coordinate mapping).
@property (nonatomic, assign) CGFloat sequenceLengthMS;

/// Current playback position in milliseconds (for playhead line).
@property (nonatomic, assign) CGFloat playbackPositionMS;

/// Request a redraw on the next display cycle.
- (void)setNeedsRedraw;

@end
