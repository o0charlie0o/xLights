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

@class XLEffectsGridView;
@class XLTimelineRulerView;
@class XLWaveformView;
@class XLRowHeadingsView;
@class XLScrollCoordinator;

/// Protocol for receiving scroll/zoom change notifications.
/// All methods are optional; implement only what you need.
@protocol XLScrollCoordinatorDelegate <NSObject>
@optional

/// Called when the horizontal scroll offset changes.
- (void)scrollCoordinator:(XLScrollCoordinator *)coordinator
    didChangeHorizontalScrollOffset:(CGFloat)offsetX;

/// Called when the vertical scroll offset changes.
- (void)scrollCoordinator:(XLScrollCoordinator *)coordinator
    didChangeVerticalScrollOffset:(CGFloat)offsetY;

/// Called when the zoom level changes.
- (void)scrollCoordinator:(XLScrollCoordinator *)coordinator
    didChangeZoomLevel:(CGFloat)zoomLevel;

@end

/// Coordinates scroll and zoom synchronization across the four main sequencer views:
/// - XLTimelineRulerView (horizontal scroll + zoom)
/// - XLEffectsGridView (horizontal + vertical scroll + zoom)
/// - XLWaveformView (horizontal scroll + zoom)
/// - XLRowHeadingsView (vertical scroll only)
///
/// This class maintains a single source of truth for scroll/zoom state and
/// atomically updates all registered views when state changes. This prevents
/// infinite notification loops and ensures smooth 120Hz ProMotion performance.
///
/// State values are stored as C primitives (CGFloat) to be immune to the
/// wxWidgets/C++ heap corruption that affects ObjC object pointers.
@interface XLScrollCoordinator : NSObject

#pragma mark - View Registration

/// The timeline ruler view (horizontal scroll + zoom).
@property (nonatomic, weak) XLTimelineRulerView *timelineRulerView;

/// The effects grid view (horizontal + vertical scroll + zoom).
@property (nonatomic, weak) XLEffectsGridView *effectsGridView;

/// The waveform view (horizontal scroll + zoom).
@property (nonatomic, weak) XLWaveformView *waveformView;

/// The row headings view (vertical scroll only).
@property (nonatomic, weak) XLRowHeadingsView *rowHeadingsView;

/// Delegate for receiving scroll/zoom change notifications.
@property (nonatomic, weak) id<XLScrollCoordinatorDelegate> delegate;

#pragma mark - Scroll State (Single Source of Truth)

/// Horizontal scroll offset in points (time axis).
/// Shared by: timeline ruler, effects grid, waveform.
@property (nonatomic, readonly) CGFloat horizontalScrollOffset;

/// Vertical scroll offset in points (row axis).
/// Shared by: effects grid, row headings.
@property (nonatomic, readonly) CGFloat verticalScrollOffset;

/// Zoom level (pixels per millisecond).
/// Shared by: timeline ruler, effects grid, waveform.
@property (nonatomic, readonly) CGFloat zoomLevel;

#pragma mark - Scroll Limits

/// Maximum horizontal scroll offset (sequence length * zoom - view width).
/// Set this when sequence length or view width changes.
@property (nonatomic, assign) CGFloat maxHorizontalScrollOffset;

/// Maximum vertical scroll offset (total rows * row height - view height).
/// Set this when row count, row height, or view height changes.
@property (nonatomic, assign) CGFloat maxVerticalScrollOffset;

/// Minimum zoom level. Default: 0.001
@property (nonatomic, assign) CGFloat minZoomLevel;

/// Maximum zoom level. Default: 10.0
@property (nonatomic, assign) CGFloat maxZoomLevel;

#pragma mark - Update Methods

/// Set the horizontal scroll offset. Updates all horizontally-scrolling views.
/// The offset is clamped to [0, maxHorizontalScrollOffset].
- (void)setHorizontalScrollOffset:(CGFloat)offsetX;

/// Set the vertical scroll offset. Updates all vertically-scrolling views.
/// The offset is clamped to [0, maxVerticalScrollOffset].
- (void)setVerticalScrollOffset:(CGFloat)offsetY;

/// Set the zoom level. Updates all zoomable views.
/// The zoom is clamped to [minZoomLevel, maxZoomLevel].
/// Optionally centers the zoom on a specific x coordinate.
- (void)setZoomLevel:(CGFloat)zoomLevel centeredOnPointX:(CGFloat)pointX;

/// Set the zoom level. Updates all zoomable views.
/// The zoom is clamped to [minZoomLevel, maxZoomLevel].
- (void)setZoomLevel:(CGFloat)zoomLevel;

/// Convenience method to set both horizontal and vertical scroll at once.
- (void)setScrollOffsetX:(CGFloat)offsetX Y:(CGFloat)offsetY;

#pragma mark - View-Initiated Updates

/// Called by a view when the user scrolls horizontally.
/// The coordinator updates all other horizontal views.
- (void)viewDidScrollHorizontally:(CGFloat)offsetX fromView:(NSView *)view;

/// Called by a view when the user scrolls vertically.
/// The coordinator updates all other vertical views.
- (void)viewDidScrollVertically:(CGFloat)offsetY fromView:(NSView *)view;

/// Called by a view when the user changes zoom level.
/// The coordinator updates all other zoomable views.
/// @param zoomLevel New zoom level
/// @param pointX Point in view coordinates to keep stationary during zoom
/// @param view The view that initiated the zoom change
- (void)viewDidChangeZoomLevel:(CGFloat)zoomLevel
              centeredOnPointX:(CGFloat)pointX
                      fromView:(NSView *)view;

#pragma mark - Scroll Navigation

/// Scroll to make a specific time visible (centered if possible).
- (void)scrollToTimeMS:(CGFloat)timeMS animated:(BOOL)animated;

/// Scroll to make a specific row visible (centered if possible).
- (void)scrollToRow:(NSInteger)row withRowHeight:(CGFloat)rowHeight animated:(BOOL)animated;

/// Scroll to make a specific time and row visible.
- (void)scrollToTimeMS:(CGFloat)timeMS row:(NSInteger)row withRowHeight:(CGFloat)rowHeight animated:(BOOL)animated;

@end
