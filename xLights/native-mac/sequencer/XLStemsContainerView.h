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

@class XLStemManager;
@class XLScrollCoordinator;
@class XLStemsContainerView;

/// Header bar height.
static const CGFloat kStemsHeaderHeight = 22.0;

/// Resize handle height.
static const CGFloat kStemsResizeHandleHeight = 6.0;

/// Default expanded height.
static const CGFloat kStemsDefaultExpandedHeight = 120.0;

/// Minimum expanded height (header + 1 stem + handle).
static const CGFloat kStemsMinExpandedHeight = 58.0;

/// Maximum expanded height.
static const CGFloat kStemsMaxExpandedHeight = 400.0;

@protocol XLStemsContainerDelegate <NSObject>
@optional

/// Called during resize drag. The delegate should update the height constraint.
- (void)stemsContainer:(XLStemsContainerView *)container didChangeHeight:(CGFloat)newHeight;

/// Called when the Import button is clicked.
- (void)stemsContainerDidRequestImport:(XLStemsContainerView *)container;

/// Called when the Import from Folder button is clicked.
- (void)stemsContainerDidRequestImportFromFolder:(XLStemsContainerView *)container;

@end

/// Container view sitting between the waveform and effects grid.
/// Contains a header bar (collapse/expand, label, import button),
/// row headers on the left, a scrollable area of mini waveforms, and a resize handle.
@interface XLStemsContainerView : NSView

/// The stem manager providing data.
@property (nonatomic, strong) XLStemManager *stemManager;

/// Delegate for layout and import actions.
@property (nonatomic, weak) id<XLStemsContainerDelegate> delegate;

/// Whether the panel is collapsed.
@property (nonatomic, assign) BOOL collapsed;

/// Width of the left-side row headers area (should match kRowHeaderWidth).
@property (nonatomic, assign) CGFloat rowHeaderWidth;

/// Scroll coordinator for forwarding horizontal scroll/zoom events.
@property (nonatomic, weak) XLScrollCoordinator *scrollCoordinator;

/// Toggle collapse/expand with animation.
- (void)toggleCollapsed;

/// Update all mini waveforms with current scroll/zoom state.
- (void)setScrollOffsetX:(CGFloat)offsetX;
- (void)setZoomLevel:(CGFloat)zoomLevel;
- (void)setSequenceLengthMS:(CGFloat)lengthMS;
- (void)setPlaybackPositionMS:(CGFloat)positionMS;

/// Rebuild mini waveform subviews from stem manager data.
- (void)reloadStems;

/// Current total height (0 if collapsed, header + content + handle if expanded).
- (CGFloat)currentHeight;

@end
