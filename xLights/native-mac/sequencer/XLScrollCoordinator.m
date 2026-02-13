/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLScrollCoordinator.h"
#import "XLEffectsGridView.h"
#import "XLTimelineRulerView.h"
#import "XLWaveformView.h"
#import "XLRowHeadingsView.h"
#import "XLStemsContainerView.h"

static const CGFloat kDefaultMinZoom = 0.001;
static const CGFloat kDefaultMaxZoom = 10.0;
static const CGFloat kDefaultZoom = 0.1;

@implementation XLScrollCoordinator {
    // Store state as C primitives to be immune to wxWidgets heap corruption.
    // These values are the single source of truth.
    CGFloat _horizontalScrollOffset;
    CGFloat _verticalScrollOffset;
    CGFloat _zoomLevel;

    // Guard flag to prevent re-entrant updates during synchronization
    BOOL _isUpdatingViews;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _horizontalScrollOffset = 0.0;
        _verticalScrollOffset = 0.0;
        _zoomLevel = kDefaultZoom;
        _minZoomLevel = kDefaultMinZoom;
        _maxZoomLevel = kDefaultMaxZoom;
        _maxHorizontalScrollOffset = CGFLOAT_MAX;
        _maxVerticalScrollOffset = CGFLOAT_MAX;
        _isUpdatingViews = NO;
    }
    return self;
}

#pragma mark - Property Accessors (Read-Only)

- (CGFloat)horizontalScrollOffset {
    return _horizontalScrollOffset;
}

- (CGFloat)verticalScrollOffset {
    return _verticalScrollOffset;
}

- (CGFloat)zoomLevel {
    return _zoomLevel;
}

#pragma mark - Clamping Helpers

- (CGFloat)clampHorizontalOffset:(CGFloat)offset {
    if (offset < 0) return 0;
    if (offset > _maxHorizontalScrollOffset) return _maxHorizontalScrollOffset;
    return offset;
}

- (CGFloat)clampVerticalOffset:(CGFloat)offset {
    if (offset < 0) return 0;
    if (offset > _maxVerticalScrollOffset) return _maxVerticalScrollOffset;
    return offset;
}

- (CGFloat)clampZoomLevel:(CGFloat)zoom {
    if (zoom < _minZoomLevel) return _minZoomLevel;
    if (zoom > _maxZoomLevel) return _maxZoomLevel;
    return zoom;
}

#pragma mark - Update Methods

- (void)setHorizontalScrollOffset:(CGFloat)offsetX {
    CGFloat clamped = [self clampHorizontalOffset:offsetX];
    if (fabs(clamped - _horizontalScrollOffset) < 0.01) return;

    _horizontalScrollOffset = clamped;
    [self syncHorizontalScrollToAllViews];

    if ([_delegate respondsToSelector:@selector(scrollCoordinator:didChangeHorizontalScrollOffset:)]) {
        [_delegate scrollCoordinator:self didChangeHorizontalScrollOffset:_horizontalScrollOffset];
    }
}

- (void)setVerticalScrollOffset:(CGFloat)offsetY {
    CGFloat clamped = [self clampVerticalOffset:offsetY];
    if (fabs(clamped - _verticalScrollOffset) < 0.01) return;

    _verticalScrollOffset = clamped;
    [self syncVerticalScrollToAllViews];

    if ([_delegate respondsToSelector:@selector(scrollCoordinator:didChangeVerticalScrollOffset:)]) {
        [_delegate scrollCoordinator:self didChangeVerticalScrollOffset:_verticalScrollOffset];
    }
}

- (void)setZoomLevel:(CGFloat)zoomLevel {
    [self setZoomLevel:zoomLevel centeredOnPointX:-1];
}

- (void)setZoomLevel:(CGFloat)zoomLevel centeredOnPointX:(CGFloat)pointX {
    CGFloat clamped = [self clampZoomLevel:zoomLevel];
    if (fabs(clamped - _zoomLevel) < 0.00001) return;

    CGFloat oldZoom = _zoomLevel;
    _zoomLevel = clamped;

    // If a center point was provided, adjust horizontal scroll to keep that time position stable
    if (pointX >= 0) {
        CGFloat timeAtPoint = (pointX + _horizontalScrollOffset) / oldZoom;
        CGFloat newHScroll = timeAtPoint * _zoomLevel - pointX;
        _horizontalScrollOffset = [self clampHorizontalOffset:newHScroll];
    }

    [self syncZoomToAllViews];
    [self syncHorizontalScrollToAllViews];

    if ([_delegate respondsToSelector:@selector(scrollCoordinator:didChangeZoomLevel:)]) {
        [_delegate scrollCoordinator:self didChangeZoomLevel:_zoomLevel];
    }
}

- (void)setScrollOffsetX:(CGFloat)offsetX Y:(CGFloat)offsetY {
    CGFloat clampedX = [self clampHorizontalOffset:offsetX];
    CGFloat clampedY = [self clampVerticalOffset:offsetY];

    BOOL changedX = fabs(clampedX - _horizontalScrollOffset) >= 0.01;
    BOOL changedY = fabs(clampedY - _verticalScrollOffset) >= 0.01;

    if (!changedX && !changedY) return;

    _horizontalScrollOffset = clampedX;
    _verticalScrollOffset = clampedY;

    if (changedX) [self syncHorizontalScrollToAllViews];
    if (changedY) [self syncVerticalScrollToAllViews];

    if (changedX && [_delegate respondsToSelector:@selector(scrollCoordinator:didChangeHorizontalScrollOffset:)]) {
        [_delegate scrollCoordinator:self didChangeHorizontalScrollOffset:_horizontalScrollOffset];
    }
    if (changedY && [_delegate respondsToSelector:@selector(scrollCoordinator:didChangeVerticalScrollOffset:)]) {
        [_delegate scrollCoordinator:self didChangeVerticalScrollOffset:_verticalScrollOffset];
    }
}

#pragma mark - View-Initiated Updates

- (void)viewDidScrollHorizontally:(CGFloat)offsetX fromView:(NSView *)view {
    if (_isUpdatingViews) return;

    CGFloat clamped = [self clampHorizontalOffset:offsetX];
    if (clamped == _horizontalScrollOffset) return;

    _horizontalScrollOffset = clamped;
    [self syncHorizontalScrollToAllViewsExcept:view];

    if ([_delegate respondsToSelector:@selector(scrollCoordinator:didChangeHorizontalScrollOffset:)]) {
        [_delegate scrollCoordinator:self didChangeHorizontalScrollOffset:_horizontalScrollOffset];
    }
}

- (void)viewDidScrollVertically:(CGFloat)offsetY fromView:(NSView *)view {
    if (_isUpdatingViews) return;

    CGFloat clamped = [self clampVerticalOffset:offsetY];
    if (clamped == _verticalScrollOffset) return;

    _verticalScrollOffset = clamped;
    [self syncVerticalScrollToAllViewsExcept:view];

    if ([_delegate respondsToSelector:@selector(scrollCoordinator:didChangeVerticalScrollOffset:)]) {
        [_delegate scrollCoordinator:self didChangeVerticalScrollOffset:_verticalScrollOffset];
    }
}

- (void)viewDidChangeZoomLevel:(CGFloat)zoomLevel
              centeredOnPointX:(CGFloat)pointX
                      fromView:(NSView *)view
{
    if (_isUpdatingViews) return;

    CGFloat clamped = [self clampZoomLevel:zoomLevel];
    if (clamped == _zoomLevel) return;

    CGFloat oldZoom = _zoomLevel;
    _zoomLevel = clamped;

    // Adjust horizontal scroll to keep the point under cursor stable
    if (pointX >= 0) {
        CGFloat timeAtPoint = (pointX + _horizontalScrollOffset) / oldZoom;
        CGFloat newHScroll = timeAtPoint * _zoomLevel - pointX;
        _horizontalScrollOffset = [self clampHorizontalOffset:newHScroll];
    }

    [self syncZoomToAllViewsExcept:view];
    [self syncHorizontalScrollToAllViewsExcept:view];

    if ([_delegate respondsToSelector:@selector(scrollCoordinator:didChangeZoomLevel:)]) {
        [_delegate scrollCoordinator:self didChangeZoomLevel:_zoomLevel];
    }
}

#pragma mark - Sync Methods

- (void)syncHorizontalScrollToAllViews {
    [self syncHorizontalScrollToAllViewsExcept:nil];
}

- (void)syncHorizontalScrollToAllViewsExcept:(NSView *)exceptView {
    if (_isUpdatingViews) return;
    _isUpdatingViews = YES;

    // Batch all updates in a single CATransaction for smooth animation
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (_timelineRulerView && _timelineRulerView != exceptView) {
        _timelineRulerView.scrollOffset = _horizontalScrollOffset;
    }

    if (_effectsGridView && _effectsGridView != exceptView) {
        CGPoint gridScroll = _effectsGridView.scrollOffset;
        gridScroll.x = _horizontalScrollOffset;
        _effectsGridView.scrollOffset = gridScroll;
    }

    if (_waveformView && _waveformView != exceptView) {
        _waveformView.scrollOffsetX = _horizontalScrollOffset;
    }

    if (_stemsContainerView) {
        [_stemsContainerView setScrollOffsetX:_horizontalScrollOffset];
    }

    [CATransaction commit];

    _isUpdatingViews = NO;
}

- (void)syncVerticalScrollToAllViews {
    [self syncVerticalScrollToAllViewsExcept:nil];
}

- (void)syncVerticalScrollToAllViewsExcept:(NSView *)exceptView {
    if (_isUpdatingViews) return;
    _isUpdatingViews = YES;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (_effectsGridView && _effectsGridView != exceptView) {
        CGPoint gridScroll = _effectsGridView.scrollOffset;
        gridScroll.y = _verticalScrollOffset;
        _effectsGridView.scrollOffset = gridScroll;
    }

    if (_rowHeadingsView && _rowHeadingsView != exceptView) {
        _rowHeadingsView.verticalScrollOffset = _verticalScrollOffset;
    }

    [CATransaction commit];

    _isUpdatingViews = NO;
}

- (void)syncZoomToAllViews {
    [self syncZoomToAllViewsExcept:nil];
}

- (void)syncZoomToAllViewsExcept:(NSView *)exceptView {
    if (_isUpdatingViews) return;
    _isUpdatingViews = YES;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (_timelineRulerView && _timelineRulerView != exceptView) {
        _timelineRulerView.zoomLevel = _zoomLevel;
    }

    if (_effectsGridView && _effectsGridView != exceptView) {
        _effectsGridView.zoomLevel = _zoomLevel;
    }

    if (_waveformView && _waveformView != exceptView) {
        _waveformView.zoomLevel = _zoomLevel;
    }

    if (_stemsContainerView) {
        [_stemsContainerView setZoomLevel:_zoomLevel];
    }

    [CATransaction commit];

    _isUpdatingViews = NO;
}

#pragma mark - Scroll Navigation

- (void)scrollToTimeMS:(CGFloat)timeMS animated:(BOOL)animated {
    // Get view width from effects grid (or default if not set)
    CGFloat viewWidth = 800.0;
    if (_effectsGridView) {
        viewWidth = NSWidth(_effectsGridView.bounds);
    } else if (_timelineRulerView) {
        viewWidth = NSWidth(_timelineRulerView.bounds);
    }

    // Calculate offset to center the time in view
    CGFloat targetX = timeMS * _zoomLevel - viewWidth / 2.0;

    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.25;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [self setHorizontalScrollOffset:targetX];
        }];
    } else {
        [self setHorizontalScrollOffset:targetX];
    }
}

- (void)scrollToRow:(NSInteger)row withRowHeight:(CGFloat)rowHeight animated:(BOOL)animated {
    // Get view height from effects grid
    CGFloat viewHeight = 400.0;
    if (_effectsGridView) {
        viewHeight = NSHeight(_effectsGridView.bounds);
    }

    // Calculate offset to center the row in view
    CGFloat rowY = row * rowHeight;
    CGFloat targetY = rowY - viewHeight / 2.0 + rowHeight / 2.0;

    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.25;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [self setVerticalScrollOffset:targetY];
        }];
    } else {
        [self setVerticalScrollOffset:targetY];
    }
}

- (void)scrollToTimeMS:(CGFloat)timeMS
                   row:(NSInteger)row
         withRowHeight:(CGFloat)rowHeight
              animated:(BOOL)animated
{
    // Get view dimensions
    CGFloat viewWidth = 800.0;
    CGFloat viewHeight = 400.0;
    if (_effectsGridView) {
        viewWidth = NSWidth(_effectsGridView.bounds);
        viewHeight = NSHeight(_effectsGridView.bounds);
    }

    // Calculate offsets to center the position
    CGFloat targetX = timeMS * _zoomLevel - viewWidth / 2.0;
    CGFloat rowY = row * rowHeight;
    CGFloat targetY = rowY - viewHeight / 2.0 + rowHeight / 2.0;

    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.25;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [self setScrollOffsetX:targetX Y:targetY];
        }];
    } else {
        [self setScrollOffsetX:targetX Y:targetY];
    }
}

#pragma mark - Zoom Presets

- (void)zoomToFitSequenceLength:(CGFloat)sequenceLengthMS viewWidth:(CGFloat)viewWidth {
    if (sequenceLengthMS <= 0 || viewWidth <= 0) return;

    // Add a small margin (5% on each side) for visual comfort
    CGFloat marginFraction = 0.05;
    CGFloat effectiveWidth = viewWidth * (1.0 - 2.0 * marginFraction);

    // Calculate zoom level to fit sequence in view
    CGFloat newZoom = effectiveWidth / sequenceLengthMS;
    newZoom = [self clampZoomLevel:newZoom];

    _zoomLevel = newZoom;

    // Reset horizontal scroll to show from the beginning with margin
    _horizontalScrollOffset = -viewWidth * marginFraction;
    _horizontalScrollOffset = [self clampHorizontalOffset:_horizontalScrollOffset];

    [self syncZoomToAllViews];
    [self syncHorizontalScrollToAllViews];

    if ([_delegate respondsToSelector:@selector(scrollCoordinator:didChangeZoomLevel:)]) {
        [_delegate scrollCoordinator:self didChangeZoomLevel:_zoomLevel];
    }
    if ([_delegate respondsToSelector:@selector(scrollCoordinator:didChangeHorizontalScrollOffset:)]) {
        [_delegate scrollCoordinator:self didChangeHorizontalScrollOffset:_horizontalScrollOffset];
    }
}

- (void)zoomToTimeRangeFromMS:(CGFloat)startMS toMS:(CGFloat)endMS viewWidth:(CGFloat)viewWidth {
    if (startMS >= endMS || viewWidth <= 0) return;

    // Add 10% padding on each side
    CGFloat range = endMS - startMS;
    CGFloat padding = range * 0.1;
    CGFloat paddedStart = MAX(0, startMS - padding);
    CGFloat paddedEnd = endMS + padding;

    CGFloat newZoom = viewWidth / (paddedEnd - paddedStart);
    newZoom = [self clampZoomLevel:newZoom];

    _zoomLevel = newZoom;
    _horizontalScrollOffset = paddedStart * newZoom;
    _horizontalScrollOffset = [self clampHorizontalOffset:_horizontalScrollOffset];

    [self syncZoomToAllViews];
    [self syncHorizontalScrollToAllViews];

    if ([_delegate respondsToSelector:@selector(scrollCoordinator:didChangeZoomLevel:)]) {
        [_delegate scrollCoordinator:self didChangeZoomLevel:_zoomLevel];
    }
    if ([_delegate respondsToSelector:@selector(scrollCoordinator:didChangeHorizontalScrollOffset:)]) {
        [_delegate scrollCoordinator:self didChangeHorizontalScrollOffset:_horizontalScrollOffset];
    }
}

- (void)setZoomLevel:(CGFloat)zoomLevel centeredOnPlayheadMS:(CGFloat)playheadMS viewWidth:(CGFloat)viewWidth {
    CGFloat clamped = [self clampZoomLevel:zoomLevel];
    if (fabs(clamped - _zoomLevel) < 0.00001) return;

    CGFloat oldZoom = _zoomLevel;
    _zoomLevel = clamped;

    // Calculate the pixel position of the playhead before zoom
    CGFloat playheadPixelBefore = playheadMS * oldZoom;

    // We want the playhead to be in the center of the view after zoom
    // newScrollOffset = playheadMS * newZoom - viewWidth / 2
    CGFloat newHScroll = playheadMS * _zoomLevel - viewWidth / 2.0;
    _horizontalScrollOffset = [self clampHorizontalOffset:newHScroll];

    [self syncZoomToAllViews];
    [self syncHorizontalScrollToAllViews];

    if ([_delegate respondsToSelector:@selector(scrollCoordinator:didChangeZoomLevel:)]) {
        [_delegate scrollCoordinator:self didChangeZoomLevel:_zoomLevel];
    }
}

@end
