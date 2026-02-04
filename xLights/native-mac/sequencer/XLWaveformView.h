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

@class XLWaveformView;
@class XLAudioSampleData;

/// Delegate protocol for waveform view interaction events.
@protocol XLWaveformViewDelegate <NSObject>
@optional

/// Called when the user clicks on the waveform to seek to a time position.
- (void)waveformView:(XLWaveformView *)view didSeekToTimeMS:(CGFloat)timeMS;

/// Called when the scroll offset changes (e.g. from scroll wheel input).
- (void)waveformView:(XLWaveformView *)view didChangeScrollOffset:(CGFloat)scrollOffsetX;

/// Called when the zoom level changes (e.g. from pinch gesture).
- (void)waveformView:(XLWaveformView *)view didChangeZoomLevel:(CGFloat)zoomLevel centeredOnPointX:(CGFloat)pointX;

@end

/// CALayer-backed waveform display view for the native macOS sequencer.
///
/// Renders audio waveform data using CoreGraphics, with support for
/// mono and stereo display, zoom/scroll synchronization with the effects
/// grid and timeline ruler, and click-to-seek interaction.
///
/// Reference: xLights/sequencer/Waveform.h/cpp (wxWidgets original)
/// Design reference: Logic Pro X / GarageBand waveform display
@interface XLWaveformView : NSView

/// Delegate for receiving interaction events.
@property (nonatomic, weak) id<XLWaveformViewDelegate> delegate;

/// Horizontal zoom level (pixels per millisecond) — synced with effects grid.
@property (nonatomic, assign) CGFloat zoomLevel;

/// Horizontal scroll offset in points — synced with effects grid.
@property (nonatomic, assign) CGFloat scrollOffsetX;

/// Current playback position in milliseconds (-1 = not shown).
@property (nonatomic, assign) CGFloat playbackPositionMS;

/// Mouse cursor position in milliseconds from the effects grid (-1 = not shown).
/// This shows a vertical line indicating where the mouse is in the timeline.
@property (nonatomic, assign) CGFloat cursorPositionMS;

/// Total sequence duration in milliseconds.
@property (nonatomic, assign) CGFloat sequenceLengthMS;

/// Whether to show separate stereo channels (top=L, bottom=R) or combined mono.
@property (nonatomic, assign) BOOL showStereo;

/// Waveform fill color. If nil, defaults to a classic green.
@property (nonatomic, strong) NSColor *waveformColor;

/// Load audio sample data for display.
/// Generates the internal waveform overview used for rendering.
- (void)loadAudioData:(XLAudioSampleData *)audioData;

/// Clear the waveform display and release cached overview data.
- (void)clearWaveform;

/// Force a redraw on the next display cycle.
- (void)setNeedsDisplay;

@end
