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

@class XLTransportBarView;
@class XLEngineBridge;

@protocol XLTransportBarDelegate <NSObject>
@optional
- (void)transportBar:(XLTransportBarView *)bar didSeekToPositionMS:(CGFloat)positionMS;
- (void)transportBarDidPlay:(XLTransportBarView *)bar;
- (void)transportBarDidPause:(XLTransportBarView *)bar;
- (void)transportBarDidStop:(XLTransportBarView *)bar;
- (void)transportBar:(XLTransportBarView *)bar didChangePlaybackRate:(CGFloat)rate;
- (void)transportBar:(XLTransportBarView *)bar didToggleLoop:(BOOL)loopEnabled;
- (void)transportBar:(XLTransportBarView *)bar didToggleOutput:(BOOL)outputEnabled;
- (void)transportBar:(XLTransportBarView *)bar didChangeZoomLevel:(CGFloat)zoomLevel;
- (void)transportBarDidRequestFitToWindow:(XLTransportBarView *)bar;
@end

@interface XLTransportBarView : NSView

@property (nonatomic, weak) id<XLTransportBarDelegate> delegate;
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Current playback position in ms. Updates the time display and scrub slider.
@property (nonatomic, assign) CGFloat currentPositionMS;

/// Total sequence duration in ms.
@property (nonatomic, assign) CGFloat totalDurationMS;

/// Whether currently playing.
@property (nonatomic, assign) BOOL isPlaying;

/// Whether loop is enabled.
@property (nonatomic, assign) BOOL loopEnabled;

/// Whether output (lights) is active.
@property (nonatomic, assign) BOOL outputEnabled;

/// Playback rate (1.0 = normal, 0.5 = half, 2.0 = double).
@property (nonatomic, assign) CGFloat playbackRate;

/// Timeline zoom level (pixels per ms). Default 0.1.
@property (nonatomic, assign) CGFloat zoomLevel;

/// Minimum allowed zoom level. Default 0.001.
@property (nonatomic, assign) CGFloat minZoomLevel;

/// Maximum allowed zoom level. Default 5.0.
@property (nonatomic, assign) CGFloat maxZoomLevel;

/// Update the time display for current position.
- (void)updateTimeDisplay;

@end
