/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLEffectsGridView.h"
#import "XLEffectsGridRenderer.h"
#import <CoreVideo/CVDisplayLink.h>

static const CGFloat kDefaultZoomLevel = 0.1;     // pixels per ms
static const CGFloat kDefaultMinZoom = 0.001;
static const CGFloat kDefaultMaxZoom = 5.0;
static const CGFloat kDefaultRowHeight = 22.0;
static const CGFloat kEdgeHitTestWidth = 6.0;      // pixels from edge to trigger resize
static const CGFloat kDragThreshold = 4.0;          // pixels before drag starts
static const CGFloat kMinimumEffectWidthMS = 10.0;  // minimum effect width in ms

@interface XLEffectsGridView () {
    CVDisplayLinkRef _displayLink;
}

@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) XLEffectsGridRenderer *renderer;

// Cached data from data source
@property (nonatomic, assign) NSInteger totalRows;
@property (nonatomic, assign) CGFloat sequenceLengthMS;
@property (nonatomic, strong) NSMutableArray<NSValue *> *effectRenderInfos;
@property (nonatomic, strong) NSArray<NSNumber *> *timingMarks;

// Mouse interaction state
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) BOOL isResizing;
@property (nonatomic, assign) BOOL isRubberBanding;
@property (nonatomic, assign) BOOL isMiddleMouseScrolling;
@property (nonatomic, assign) NSPoint mouseDownPoint;
@property (nonatomic, assign) NSPoint lastMousePoint;
@property (nonatomic, assign) CGPoint mouseDownScrollOffset;
@property (nonatomic, assign) NSInteger mouseDownRow;
@property (nonatomic, assign) NSInteger mouseDownEffectIndex;
@property (nonatomic, assign) XLEffectHitLocation mouseDownHitLocation;
@property (nonatomic, assign) CGFloat dragStartTimeMS;
@property (nonatomic, assign) CGFloat dragOriginalStartMS;
@property (nonatomic, assign) CGFloat dragOriginalEndMS;

// Rubber band selection
@property (nonatomic, assign) NSPoint rubberBandOrigin;
@property (nonatomic, assign) NSPoint rubberBandCurrent;

// Display link
@property (nonatomic, assign) BOOL needsRedraw;

@end

// CVDisplayLink callback
static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                     const CVTimeStamp *inNow,
                                     const CVTimeStamp *inOutputTime,
                                     CVOptionFlags flagsIn,
                                     CVOptionFlags *flagsOut,
                                     void *displayLinkContext)
{
    @autoreleasepool {
        XLEffectsGridView *view = (__bridge XLEffectsGridView *)displayLinkContext;
        if (view.needsRedraw) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [view drawGrid];
            });
        }
    }
    return kCVReturnSuccess;
}

@implementation XLEffectsGridView

#pragma mark - Initialization

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _zoomLevel = kDefaultZoomLevel;
    _minZoomLevel = kDefaultMinZoom;
    _maxZoomLevel = kDefaultMaxZoom;
    _rowHeight = kDefaultRowHeight;
    _playbackPositionMS = -1;
    _scrollOffset = CGPointZero;
    _selectedEffectID = -1;
    _totalRows = 0;
    _sequenceLengthMS = 0;
    _effectRenderInfos = [NSMutableArray array];
    _timingMarks = @[];
    _needsRedraw = YES;

    // Set up Metal layer - must set layer before wantsLayer for layer-hosting views
    _metalLayer = [CAMetalLayer layer];
    _metalLayer.device = MTLCreateSystemDefaultDevice();
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.contentsScale = self.window.backingScaleFactor ?: 2.0;
    _metalLayer.framebufferOnly = YES;
    self.layer = _metalLayer;
    self.wantsLayer = YES;

    // Initialize renderer (may return nil if Metal is unavailable)
    _renderer = [[XLEffectsGridRenderer alloc] initWithLayer:_metalLayer];
    if (!_renderer) {
        NSLog(@"XLEffectsGridView: Metal renderer unavailable, grid will not render");
    }

    // Set up display link for 60fps+ rendering
    [self setupDisplayLink];

    // Accept mouse events
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited
                                  | NSTrackingMouseMoved
                                  | NSTrackingActiveInActiveApp
                                  | NSTrackingInVisibleRect;
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                               options:options
                                                                 owner:self
                                                              userInfo:nil];
    [self addTrackingArea:trackingArea];
}

- (void)setupDisplayLink {
    CVDisplayLinkRef dl;
    CVDisplayLinkCreateWithActiveCGDisplays(&dl);
    CVDisplayLinkSetOutputCallback(dl, &displayLinkCallback, (__bridge void *)self);
    CVDisplayLinkStart(dl);
    _displayLink = dl;
}

- (void)dealloc {
    if (_displayLink) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
        _displayLink = NULL;
    }
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        _metalLayer.contentsScale = self.window.backingScaleFactor;
    }
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    _metalLayer.drawableSize = CGSizeMake(newSize.width * _metalLayer.contentsScale,
                                           newSize.height * _metalLayer.contentsScale);
    _needsRedraw = YES;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

#pragma mark - Data Loading

- (void)reloadData {
    [_effectRenderInfos removeAllObjects];

    if (!_dataSource) {
        _totalRows = 0;
        _sequenceLengthMS = 0;
        _timingMarks = @[];
        _needsRedraw = YES;
        return;
    }

    _totalRows = [_dataSource numberOfRowsInEffectsGrid:self];
    _sequenceLengthMS = [_dataSource sequenceLengthMSForEffectsGrid:self];

    if ([_dataSource respondsToSelector:@selector(timingMarksForEffectsGrid:)]) {
        _timingMarks = [_dataSource timingMarksForEffectsGrid:self] ?: @[];
    } else {
        _timingMarks = @[];
    }

    // Collect all effect render infos
    for (NSInteger row = 0; row < _totalRows; row++) {
        NSInteger effectCount = [_dataSource effectsGrid:self numberOfEffectsInRow:row];
        for (NSInteger i = 0; i < effectCount; i++) {
            XLEffectRenderInfo info = [_dataSource effectsGrid:self effectInfoForRow:row atIndex:i];
            info.row = row;
            NSValue *val = [NSValue valueWithBytes:&info objCType:@encode(XLEffectRenderInfo)];
            [_effectRenderInfos addObject:val];
        }
    }

    _needsRedraw = YES;
}

#pragma mark - Drawing

- (void)setNeedsDisplay {
    _needsRedraw = YES;
}

- (void)drawGrid {
    if (!_renderer || !_metalLayer) return;

    _needsRedraw = NO;

    CGSize viewSize = _metalLayer.drawableSize;
    if (viewSize.width <= 0 || viewSize.height <= 0) return;

    CGFloat scale = _metalLayer.contentsScale;
    CGPoint scaledScroll = CGPointMake(_scrollOffset.x * scale, _scrollOffset.y * scale);
    CGFloat scaledRowHeight = _rowHeight * scale;
    CGFloat scaledZoom = _zoomLevel * scale;

    [_renderer drawInLayer:_metalLayer
                  viewSize:viewSize
              scrollOffset:scaledScroll
                 zoomLevel:scaledZoom
                 rowHeight:scaledRowHeight
                 totalRows:_totalRows
          sequenceLengthMS:_sequenceLengthMS
                   effects:_effectRenderInfos
          selectedEffectID:_selectedEffectID
       playbackPositionMS:_playbackPositionMS
            timingMarksMS:_timingMarks];
}

#pragma mark - Coordinate Conversion

- (void)convertPoint:(NSPoint)viewPoint toTimeMS:(CGFloat *)outTimeMS row:(NSInteger *)outRow {
    if (outTimeMS) {
        *outTimeMS = (viewPoint.x + _scrollOffset.x) / _zoomLevel;
    }
    if (outRow) {
        *outRow = (NSInteger)floor((viewPoint.y + _scrollOffset.y) / _rowHeight);
    }
}

- (NSPoint)pointForTimeMS:(CGFloat)timeMS row:(NSInteger)row {
    CGFloat x = timeMS * _zoomLevel - _scrollOffset.x;
    CGFloat y = row * _rowHeight - _scrollOffset.y;
    return NSMakePoint(x, y);
}

#pragma mark - Scrolling

- (void)scrollToTimeMS:(CGFloat)timeMS {
    CGFloat x = timeMS * _zoomLevel - self.bounds.size.width * 0.5;
    _scrollOffset = CGPointMake(MAX(0, x), _scrollOffset.y);
    _needsRedraw = YES;

    if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeScrollOffset:)]) {
        [_delegate effectsGrid:self didChangeScrollOffset:_scrollOffset];
    }
}

- (void)setPlaybackPositionMS:(CGFloat)positionMS animated:(BOOL)animated {
    _playbackPositionMS = positionMS;
    _needsRedraw = YES;
}

- (void)clampScrollOffset {
    CGFloat maxScrollX = MAX(0, _sequenceLengthMS * _zoomLevel - self.bounds.size.width);
    CGFloat maxScrollY = MAX(0, _totalRows * _rowHeight - self.bounds.size.height);

    _scrollOffset = CGPointMake(
        MAX(0, MIN(_scrollOffset.x, maxScrollX)),
        MAX(0, MIN(_scrollOffset.y, maxScrollY))
    );
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event {
    // Handle double-click (AppKit delivers double-clicks as mouseDown with clickCount==2)
    if (event.clickCount == 2) {
        NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
        CGFloat timeMS;
        NSInteger row;
        [self convertPoint:loc toTimeMS:&timeMS row:&row];

        NSInteger hitEffectIndex = -1;
        XLEffectHitLocation hitLoc;
        [self hitTestPoint:loc effectIndex:&hitEffectIndex hitLocation:&hitLoc];

        if (hitEffectIndex >= 0) {
            if ([_delegate respondsToSelector:@selector(effectsGrid:didDoubleClickEffectAtRow:effectIndex:)]) {
                [_delegate effectsGrid:self didDoubleClickEffectAtRow:row effectIndex:hitEffectIndex];
            }
        }
        return;
    }

    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    _mouseDownPoint = loc;
    _lastMousePoint = loc;
    _isDragging = NO;
    _isResizing = NO;
    _isRubberBanding = NO;

    CGFloat timeMS;
    NSInteger row;
    [self convertPoint:loc toTimeMS:&timeMS row:&row];
    _mouseDownRow = row;

    // Find effect at click location
    NSInteger hitEffectIndex = -1;
    XLEffectHitLocation hitLoc = XLEffectHitLocationNone;
    [self hitTestPoint:loc effectIndex:&hitEffectIndex hitLocation:&hitLoc];

    _mouseDownEffectIndex = hitEffectIndex;
    _mouseDownHitLocation = hitLoc;

    if (hitEffectIndex >= 0) {
        // Select the effect
        _selectedEffectID = hitEffectIndex;
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(effectsGrid:didSelectEffectAtRow:effectIndex:)]) {
            [_delegate effectsGrid:self didSelectEffectAtRow:row effectIndex:hitEffectIndex];
        }

        // Store original timing for potential drag/resize
        XLEffectRenderInfo info;
        [_effectRenderInfos[hitEffectIndex] getValue:&info];
        _dragOriginalStartMS = info.startTimeMS;
        _dragOriginalEndMS = info.endTimeMS;
        _dragStartTimeMS = timeMS;
    } else {
        // Deselect
        _selectedEffectID = -1;
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(effectsGrid:didClickAtTimeMS:row:)]) {
            [_delegate effectsGrid:self didClickAtTimeMS:timeMS row:row];
        }

        // Start rubber band selection
        _rubberBandOrigin = loc;
        _rubberBandCurrent = loc;
    }
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = loc.x - _mouseDownPoint.x;
    CGFloat dy = loc.y - _mouseDownPoint.y;
    CGFloat distance = sqrt(dx * dx + dy * dy);

    if (distance < kDragThreshold && !_isDragging && !_isResizing && !_isRubberBanding) {
        return;
    }

    if (_mouseDownEffectIndex >= 0 && !_isDragging && !_isResizing) {
        if (_mouseDownHitLocation == XLEffectHitLocationLeftEdge ||
            _mouseDownHitLocation == XLEffectHitLocationRightEdge) {
            _isResizing = YES;
        } else {
            _isDragging = YES;
        }
    } else if (_mouseDownEffectIndex < 0 && !_isRubberBanding) {
        _isRubberBanding = YES;
    }

    if (_isResizing && _mouseDownEffectIndex >= 0) {
        CGFloat timeMS;
        [self convertPoint:loc toTimeMS:&timeMS row:NULL];
        CGFloat deltaMS = timeMS - _dragStartTimeMS;

        CGFloat newStart = _dragOriginalStartMS;
        CGFloat newEnd = _dragOriginalEndMS;

        if (_mouseDownHitLocation == XLEffectHitLocationLeftEdge) {
            newStart = _dragOriginalStartMS + deltaMS;
            newStart = MAX(0, MIN(newStart, newEnd - kMinimumEffectWidthMS));
        } else {
            newEnd = _dragOriginalEndMS + deltaMS;
            newEnd = MAX(newStart + kMinimumEffectWidthMS, MIN(newEnd, _sequenceLengthMS));
        }

        // Update the cached info for visual feedback
        XLEffectRenderInfo info;
        [_effectRenderInfos[_mouseDownEffectIndex] getValue:&info];
        info.startTimeMS = newStart;
        info.endTimeMS = newEnd;
        NSValue *val = [NSValue valueWithBytes:&info objCType:@encode(XLEffectRenderInfo)];
        _effectRenderInfos[_mouseDownEffectIndex] = val;

        _needsRedraw = YES;
    } else if (_isDragging && _mouseDownEffectIndex >= 0) {
        CGFloat timeMS;
        [self convertPoint:loc toTimeMS:&timeMS row:NULL];
        CGFloat deltaMS = timeMS - _dragStartTimeMS;
        CGFloat duration = _dragOriginalEndMS - _dragOriginalStartMS;
        CGFloat newStart = _dragOriginalStartMS + deltaMS;
        newStart = MAX(0, MIN(newStart, _sequenceLengthMS - duration));

        XLEffectRenderInfo info;
        [_effectRenderInfos[_mouseDownEffectIndex] getValue:&info];
        info.startTimeMS = newStart;
        info.endTimeMS = newStart + duration;
        NSValue *val = [NSValue valueWithBytes:&info objCType:@encode(XLEffectRenderInfo)];
        _effectRenderInfos[_mouseDownEffectIndex] = val;

        _needsRedraw = YES;
    } else if (_isRubberBanding) {
        _rubberBandCurrent = loc;
        _needsRedraw = YES;
    }

    _lastMousePoint = loc;
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];

    if (_isResizing && _mouseDownEffectIndex >= 0) {
        XLEffectRenderInfo info;
        [_effectRenderInfos[_mouseDownEffectIndex] getValue:&info];

        if ([_delegate respondsToSelector:@selector(effectsGrid:didResizeEffectAtRow:effectIndex:newStartTimeMS:newEndTimeMS:)]) {
            [_delegate effectsGrid:self
               didResizeEffectAtRow:info.row
                      effectIndex:_mouseDownEffectIndex
                    newStartTimeMS:info.startTimeMS
                      newEndTimeMS:info.endTimeMS];
        }
    } else if (_isDragging && _mouseDownEffectIndex >= 0) {
        XLEffectRenderInfo info;
        [_effectRenderInfos[_mouseDownEffectIndex] getValue:&info];

        if ([_delegate respondsToSelector:@selector(effectsGrid:didMoveEffectAtRow:effectIndex:toTimeMS:)]) {
            [_delegate effectsGrid:self
              didMoveEffectAtRow:_mouseDownRow
                    effectIndex:_mouseDownEffectIndex
                      toTimeMS:info.startTimeMS];
        }
    } else if (_isRubberBanding) {
        CGFloat startTimeMS, endTimeMS;
        NSInteger startRow, endRow;
        [self convertPoint:_rubberBandOrigin toTimeMS:&startTimeMS row:&startRow];
        [self convertPoint:_rubberBandCurrent toTimeMS:&endTimeMS row:&endRow];

        if (startTimeMS > endTimeMS) {
            CGFloat tmp = startTimeMS; startTimeMS = endTimeMS; endTimeMS = tmp;
        }
        if (startRow > endRow) {
            NSInteger tmp = startRow; startRow = endRow; endRow = tmp;
        }

        if ([_delegate respondsToSelector:@selector(effectsGrid:didSelectRangeFromRow:toRow:fromTimeMS:toTimeMS:)]) {
            [_delegate effectsGrid:self
              didSelectRangeFromRow:startRow
                             toRow:endRow
                        fromTimeMS:startTimeMS
                          toTimeMS:endTimeMS];
        }
    }

    _isDragging = NO;
    _isResizing = NO;
    _isRubberBanding = NO;
    _needsRedraw = YES;
}

- (void)rightMouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat timeMS;
    NSInteger row;
    [self convertPoint:loc toTimeMS:&timeMS row:&row];

    NSInteger hitEffectIndex = -1;
    XLEffectHitLocation hitLoc;
    [self hitTestPoint:loc effectIndex:&hitEffectIndex hitLocation:&hitLoc];

    if (hitEffectIndex >= 0) {
        _selectedEffectID = hitEffectIndex;
        _needsRedraw = YES;
    }

    if ([_delegate respondsToSelector:@selector(effectsGrid:contextMenuForRow:effectIndex:atTimeMS:)]) {
        NSMenu *menu = [_delegate effectsGrid:self
                          contextMenuForRow:row
                               effectIndex:hitEffectIndex
                                  atTimeMS:timeMS];
        if (menu) {
            [NSMenu popUpContextMenu:menu withEvent:event forView:self];
        }
    }
}

- (void)otherMouseDown:(NSEvent *)event {
    if (event.buttonNumber == 2) {
        _isMiddleMouseScrolling = YES;
        _mouseDownPoint = [self convertPoint:event.locationInWindow fromView:nil];
        _mouseDownScrollOffset = _scrollOffset;
        [[NSCursor closedHandCursor] push];
    }
}

- (void)otherMouseDragged:(NSEvent *)event {
    if (_isMiddleMouseScrolling) {
        NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
        CGFloat dx = loc.x - _mouseDownPoint.x;
        CGFloat dy = loc.y - _mouseDownPoint.y;
        _scrollOffset = CGPointMake(_mouseDownScrollOffset.x - dx,
                                    _mouseDownScrollOffset.y - dy);
        [self clampScrollOffset];
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeScrollOffset:)]) {
            [_delegate effectsGrid:self didChangeScrollOffset:_scrollOffset];
        }
    }
}

- (void)otherMouseUp:(NSEvent *)event {
    if (_isMiddleMouseScrolling) {
        _isMiddleMouseScrolling = NO;
        [NSCursor pop];
    }
}

- (void)scrollWheel:(NSEvent *)event {
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        // Cmd+Scroll = Zoom
        CGFloat zoomDelta = event.scrollingDeltaY * 0.01;
        CGFloat newZoom = _zoomLevel * (1.0 + zoomDelta);
        newZoom = MAX(_minZoomLevel, MIN(newZoom, _maxZoomLevel));

        // Zoom centered on mouse position
        NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
        CGFloat timeAtMouse = (loc.x + _scrollOffset.x) / _zoomLevel;

        _zoomLevel = newZoom;

        // Adjust scroll to keep the time under the mouse stationary
        _scrollOffset = CGPointMake(timeAtMouse * _zoomLevel - loc.x, _scrollOffset.y);
        [self clampScrollOffset];
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeZoomLevel:)]) {
            [_delegate effectsGrid:self didChangeZoomLevel:_zoomLevel];
        }
        if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeScrollOffset:)]) {
            [_delegate effectsGrid:self didChangeScrollOffset:_scrollOffset];
        }
    } else {
        // Normal scroll
        CGFloat dx = event.scrollingDeltaX;
        CGFloat dy = event.scrollingDeltaY;

        // Shift+scroll = horizontal
        if (event.modifierFlags & NSEventModifierFlagShift) {
            dx = dy;
            dy = 0;
        }

        _scrollOffset = CGPointMake(_scrollOffset.x - dx, _scrollOffset.y - dy);
        [self clampScrollOffset];
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeScrollOffset:)]) {
            [_delegate effectsGrid:self didChangeScrollOffset:_scrollOffset];
        }
    }
}

- (void)magnifyWithEvent:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat timeAtMouse = (loc.x + _scrollOffset.x) / _zoomLevel;

    CGFloat newZoom = _zoomLevel * (1.0 + event.magnification);
    newZoom = MAX(_minZoomLevel, MIN(newZoom, _maxZoomLevel));
    _zoomLevel = newZoom;

    _scrollOffset = CGPointMake(timeAtMouse * _zoomLevel - loc.x, _scrollOffset.y);
    [self clampScrollOffset];
    _needsRedraw = YES;

    if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeZoomLevel:)]) {
        [_delegate effectsGrid:self didChangeZoomLevel:_zoomLevel];
    }
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];

    NSInteger hitEffectIndex = -1;
    XLEffectHitLocation hitLoc;
    [self hitTestPoint:loc effectIndex:&hitEffectIndex hitLocation:&hitLoc];

    // Update cursor based on hit location
    switch (hitLoc) {
        case XLEffectHitLocationLeftEdge:
        case XLEffectHitLocationRightEdge:
            [[NSCursor resizeLeftRightCursor] set];
            break;
        case XLEffectHitLocationCenter:
            [[NSCursor openHandCursor] set];
            break;
        default:
            [[NSCursor arrowCursor] set];
            break;
    }
}

#pragma mark - Keyboard Events

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 51 || event.keyCode == 117) {
        // Delete or Forward Delete
        // Will be handled by responder chain / menu actions
        [super keyDown:event];
        return;
    }

    // Arrow key navigation
    switch (event.keyCode) {
        case 123: // Left arrow
            if (_selectedEffectID >= 0 && (event.modifierFlags & NSEventModifierFlagShift)) {
                // Shift+Left: move effect left
            }
            break;
        case 124: // Right arrow
            if (_selectedEffectID >= 0 && (event.modifierFlags & NSEventModifierFlagShift)) {
                // Shift+Right: move effect right
            }
            break;
        default:
            [super keyDown:event];
            break;
    }
}

#pragma mark - Hit Testing

- (void)hitTestPoint:(NSPoint)viewPoint
        effectIndex:(NSInteger *)outEffectIndex
        hitLocation:(XLEffectHitLocation *)outHitLocation
{
    *outEffectIndex = -1;
    *outHitLocation = XLEffectHitLocationNone;

    CGFloat timeMS;
    NSInteger row;
    [self convertPoint:viewPoint toTimeMS:&timeMS row:&row];

    if (row < 0 || row >= _totalRows) return;

    for (NSInteger i = 0; i < (NSInteger)_effectRenderInfos.count; i++) {
        XLEffectRenderInfo info;
        [_effectRenderInfos[i] getValue:&info];

        if (info.row != row) continue;
        if (timeMS < info.startTimeMS || timeMS > info.endTimeMS) continue;

        *outEffectIndex = i;

        // Determine hit location within the effect
        CGFloat x1 = info.startTimeMS * _zoomLevel - _scrollOffset.x;
        CGFloat x2 = info.endTimeMS * _zoomLevel - _scrollOffset.x;

        if (viewPoint.x - x1 < kEdgeHitTestWidth) {
            *outHitLocation = XLEffectHitLocationLeftEdge;
        } else if (x2 - viewPoint.x < kEdgeHitTestWidth) {
            *outHitLocation = XLEffectHitLocationRightEdge;
        } else {
            *outHitLocation = XLEffectHitLocationCenter;
        }
        return;
    }
}

#pragma mark - Properties

- (void)setZoomLevel:(CGFloat)zoomLevel {
    _zoomLevel = MAX(_minZoomLevel, MIN(zoomLevel, _maxZoomLevel));
    _needsRedraw = YES;
}

- (void)setScrollOffset:(CGPoint)scrollOffset {
    _scrollOffset = scrollOffset;
    [self clampScrollOffset];
    _needsRedraw = YES;
}

- (void)setRowHeight:(CGFloat)rowHeight {
    _rowHeight = MAX(14.0, MIN(rowHeight, 80.0));
    _needsRedraw = YES;
}

- (void)setSelectedEffectID:(NSInteger)selectedEffectID {
    if (_selectedEffectID != selectedEffectID) {
        // Update selection state in cached render infos
        if (_selectedEffectID >= 0 && _selectedEffectID < (NSInteger)_effectRenderInfos.count) {
            XLEffectRenderInfo info;
            [_effectRenderInfos[_selectedEffectID] getValue:&info];
            info.selected = NO;
            _effectRenderInfos[_selectedEffectID] = [NSValue valueWithBytes:&info
                                                                    objCType:@encode(XLEffectRenderInfo)];
        }
        _selectedEffectID = selectedEffectID;
        if (_selectedEffectID >= 0 && _selectedEffectID < (NSInteger)_effectRenderInfos.count) {
            XLEffectRenderInfo info;
            [_effectRenderInfos[_selectedEffectID] getValue:&info];
            info.selected = YES;
            _effectRenderInfos[_selectedEffectID] = [NSValue valueWithBytes:&info
                                                                    objCType:@encode(XLEffectRenderInfo)];
        }
        _needsRedraw = YES;
    }
}

@end
