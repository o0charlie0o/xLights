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

/// Waveform display type — matches legacy AUDIOSAMPLETYPE enum.
typedef NS_ENUM(NSInteger, XLWaveformType) {
    XLWaveformTypeRaw = 0,
    XLWaveformTypeBass,
    XLWaveformTypeTreble,
    XLWaveformTypeAlto,
    XLWaveformTypeCustom,
    XLWaveformTypeNonVocals,
};

/// Delegate protocol for waveform view interaction events.
@protocol XLWaveformViewDelegate <NSObject>
@optional

/// Called when the user clicks on the waveform to seek to a time position.
- (void)waveformView:(XLWaveformView *)view didSeekToTimeMS:(CGFloat)timeMS;

/// Called when the scroll offset changes (e.g. from scroll wheel input).
- (void)waveformView:(XLWaveformView *)view didChangeScrollOffset:(CGFloat)scrollOffsetX;

/// Called when the zoom level changes (e.g. from pinch gesture).
- (void)waveformView:(XLWaveformView *)view didChangeZoomLevel:(CGFloat)zoomLevel centeredOnPointX:(CGFloat)pointX;

/// Called when the user drags to select a loop region on the waveform.
- (void)waveformView:(XLWaveformView *)view didSelectLoopRegionFromTimeMS:(CGFloat)startMS toTimeMS:(CGFloat)endMS;

/// Called when the loop region is cleared (click or Escape).
- (void)waveformViewDidClearLoopRegion:(XLWaveformView *)view;

/// Forward a key event to the delegate for handling via key bindings.
/// Return YES if the delegate handled the event, NO to pass it up the responder chain.
- (BOOL)waveformView:(XLWaveformView *)view shouldHandleKeyEvent:(NSEvent *)event;

/// Called when the user selects "Render Selected Region" from the context menu.
- (void)waveformViewDidRequestRenderSelectedRegion:(XLWaveformView *)view;

/// Called when the waveform type changes via the context menu.
- (void)waveformView:(XLWaveformView *)view didChangeWaveformType:(XLWaveformType)type lowNote:(NSInteger)lowNote highNote:(NSInteger)highNote;

/// Called when the double-height toggle changes via the context menu.
- (void)waveformView:(XLWaveformView *)view didChangeDoubleHeight:(BOOL)doubleHeight;

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

/// Current waveform display type (raw, bass, treble, etc.).
@property (nonatomic, assign) XLWaveformType waveformType;

/// Whether the waveform is displayed at double height.
@property (nonatomic, assign) BOOL doubleHeight;

/// Low note for custom filtered waveform (0-127, -1 = unset).
@property (nonatomic, assign) NSInteger customLowNote;

/// High note for custom filtered waveform (0-127, -1 = unset).
@property (nonatomic, assign) NSInteger customHighNote;

/// Waveform fill color. If nil, defaults to a classic green.
@property (nonatomic, strong) NSColor *waveformColor;

/// Loop region start in milliseconds (-1 = no region).
@property (nonatomic, assign) CGFloat loopRegionStartMS;

/// Loop region end in milliseconds (-1 = no region).
@property (nonatomic, assign) CGFloat loopRegionEndMS;

/// Whether a valid loop region is currently set.
@property (nonatomic, readonly) BOOL hasLoopRegion;

/// Load audio sample data for display.
/// Generates the internal waveform overview used for rendering.
- (void)loadAudioData:(XLAudioSampleData *)audioData;

/// Clear the waveform display and release cached overview data.
- (void)clearWaveform;

/// Clear the loop region selection.
- (void)clearLoopRegion;

/// Force a redraw on the next display cycle.
- (void)setNeedsDisplay;

@end
