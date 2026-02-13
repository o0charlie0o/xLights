/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLRowHeadingsView.h"
#import "XLEffectsGridRenderer.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kDisclosureSize = 10.0;
static const CGFloat kDisclosureLeftPadding = 4.0;
static const CGFloat kIconSize = 14.0;
static const CGFloat kIconPadding = 3.0;
static const CGFloat kIndentWidth = 16.0;
static const CGFloat kDragInsertionLineHeight = 2.0;
static const CGFloat kDragDistanceThreshold = 4.0;

#pragma mark - Row Cell Layer

@interface XLRowCellLayer : CALayer
@property (nonatomic, assign) NSInteger row;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, assign) BOOL expandable;
@property (nonatomic, assign) BOOL isSelected;
@property (nonatomic, assign) XLElementType elementType;
@property (nonatomic, assign) NSInteger indentLevel;
@property (nonatomic, assign) NSInteger timingColorIndex;
@property (nonatomic, assign) BOOL isFolder;
@property (nonatomic, assign) BOOL folderCollapsed;
@property (nonatomic, copy) NSString *name;
@end

@implementation XLRowCellLayer
@end

#pragma mark - XLRowHeadingsView

@interface XLRowHeadingsView () <NSDraggingSource> {
    // C array of row cell layers - immune to wxWidgets heap corruption for count access.
    // The layers themselves are still ObjC objects, but array indexing is pure C.
    __strong XLRowCellLayer **_rowCellLayersData;
    NSUInteger _rowCellLayersCount;
    NSUInteger _rowCellLayersCapacity;
}

@property (nonatomic, assign) NSInteger cachedRowCount;
@property (nonatomic, readwrite, strong) NSMutableIndexSet *selectedRows;
@property (nonatomic, strong) CALayer *insertionIndicatorLayer;
@property (nonatomic, strong) CALayer *folderDropHighlightLayer;
@property (nonatomic, assign) NSInteger dragSourceRow;
@property (nonatomic, assign) NSInteger dragTargetRow;
@property (nonatomic, assign) NSInteger dragOntoFolderRow;
@property (nonatomic, assign) BOOL dragSourceIsFolder;
@property (nonatomic, assign) BOOL dragSourceIsTiming;
@property (nonatomic, assign) BOOL deferredDeselect;
@property (nonatomic, assign) NSInteger deferredDeselectRow;
@property (nonatomic, assign) BOOL didDrag;
@property (nonatomic, assign) BOOL dragInitiated;
@property (nonatomic, assign) NSPoint mouseDownPoint;
@property (nonatomic, strong) NSTrackingArea *trackingArea;

@end

@implementation XLRowHeadingsView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.delegate = self;
        self.layer.backgroundColor = CGColorCreateGenericRGB(0.14, 0.14, 0.14, 1.0);
        _rowHeight = 22.0;
        _verticalScrollOffset = 0.0;
        _selectedRow = -1;
        _selectedRows = [NSMutableIndexSet indexSet];
        _cachedRowCount = 0;
        _dragSourceRow = -1;
        _dragTargetRow = -1;
        _dragOntoFolderRow = -1;
        _dragSourceIsFolder = NO;
        _dragSourceIsTiming = NO;

        // Initialize C array for row cell layers
        _rowCellLayersCapacity = 64;
        _rowCellLayersCount = 0;
        _rowCellLayersData = (__strong XLRowCellLayer **)calloc(_rowCellLayersCapacity, sizeof(XLRowCellLayer *));

        _insertionIndicatorLayer = [CALayer layer];
        _insertionIndicatorLayer.backgroundColor = CGColorCreateGenericRGB(0.3, 0.6, 1.0, 1.0);
        _insertionIndicatorLayer.hidden = YES;
        [self.layer addSublayer:_insertionIndicatorLayer];

        _folderDropHighlightLayer = [CALayer layer];
        _folderDropHighlightLayer.backgroundColor = CGColorCreateGenericRGB(0.85, 0.72, 0.40, 0.15);
        _folderDropHighlightLayer.borderColor = CGColorCreateGenericRGB(0.85, 0.72, 0.40, 0.6);
        _folderDropHighlightLayer.borderWidth = 1.5;
        _folderDropHighlightLayer.cornerRadius = 3.0;
        _folderDropHighlightLayer.hidden = YES;
        [self.layer addSublayer:_folderDropHighlightLayer];

        [self registerForDraggedTypes:@[NSPasteboardTypeString]];
    }
    return self;
}

- (void)dealloc {
    if (_rowCellLayersData) {
        // Clear strong references before freeing
        for (NSUInteger i = 0; i < _rowCellLayersCount; i++) {
            _rowCellLayersData[i] = nil;
        }
        free(_rowCellLayersData);
        _rowCellLayersData = NULL;
    }
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow)
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (BOOL)isFlipped {
    return YES;
}

#pragma mark - Public

- (void)setVerticalScrollOffset:(CGFloat)verticalScrollOffset {
    if (_verticalScrollOffset != verticalScrollOffset) {
        _verticalScrollOffset = verticalScrollOffset;
        [self layoutRowCells];
    }
}

- (void)setRowHeight:(CGFloat)rowHeight {
    if (_rowHeight != rowHeight) {
        _rowHeight = rowHeight;
        [self reloadData];
    }
}

- (void)setSelectedRow:(NSInteger)selectedRow {
    NSInteger oldSelected = _selectedRow;
    _selectedRow = selectedRow;
    // Keep selectedRows in sync for single-select callers
    [_selectedRows removeAllIndexes];
    if (selectedRow >= 0) {
        [_selectedRows addIndex:(NSUInteger)selectedRow];
    }
    if (oldSelected != selectedRow) {
        [self updateRowAppearance];
    }
}

- (void)reloadData {
    _cachedRowCount = 0;
    if (_dataSource) {
        _cachedRowCount = [_dataSource numberOfRowsInRowHeadings:self];
    }
    [self rebuildRowCells];
    [self layoutRowCellsForceRedraw:YES];
}

#pragma mark - Row Cell Management

- (void)rebuildRowCells {
    // Remove existing cells
    for (NSUInteger i = 0; i < _rowCellLayersCount; i++) {
        XLRowCellLayer *cell = _rowCellLayersData[i];
        if (cell) {
            [cell removeFromSuperlayer];
            _rowCellLayersData[i] = nil;
        }
    }
    _rowCellLayersCount = 0;

    // Ensure capacity for new cells
    NSUInteger needed = (NSUInteger)_cachedRowCount;
    if (needed > _rowCellLayersCapacity) {
        NSUInteger newCapacity = needed + 32;
        __strong XLRowCellLayer **newData = (__strong XLRowCellLayer **)calloc(newCapacity, sizeof(XLRowCellLayer *));
        // No need to copy - we cleared everything above
        free(_rowCellLayersData);
        _rowCellLayersData = newData;
        _rowCellLayersCapacity = newCapacity;
    }

    // Create new cells
    for (NSInteger i = 0; i < _cachedRowCount; i++) {
        XLRowCellLayer *cell = [self createCellForRow:i];
        [self.layer addSublayer:cell];
        _rowCellLayersData[_rowCellLayersCount++] = cell;
    }

    [self.layer addSublayer:_insertionIndicatorLayer];
    [self.layer addSublayer:_folderDropHighlightLayer];
}

- (XLRowCellLayer *)createCellForRow:(NSInteger)row {
    XLRowCellLayer *cell = [XLRowCellLayer layer];
    cell.delegate = self;
    cell.contentsScale = self.window.backingScaleFactor ?: 2.0;
    cell.row = row;

    if (_dataSource) {
        @try {
            cell.name = [_dataSource rowHeadings:self nameForRow:row] ?: @"";
            cell.elementType = [_dataSource rowHeadings:self elementTypeForRow:row];
            cell.expandable = [_dataSource rowHeadings:self isExpandableAtRow:row];
            cell.expanded = [_dataSource rowHeadings:self isExpandedAtRow:row];
            cell.indentLevel = [_dataSource rowHeadings:self indentLevelForRow:row];
            if ([_dataSource respondsToSelector:@selector(rowHeadings:timingColorIndexForRow:)]) {
                cell.timingColorIndex = [_dataSource rowHeadings:self timingColorIndexForRow:row];
            }
            if ([_dataSource respondsToSelector:@selector(rowHeadings:isFolderAtRow:)]) {
                cell.isFolder = [_dataSource rowHeadings:self isFolderAtRow:row];
            }
            if ([_dataSource respondsToSelector:@selector(rowHeadings:isFolderCollapsedAtRow:)]) {
                cell.folderCollapsed = [_dataSource rowHeadings:self isFolderCollapsedAtRow:row];
            }
        } @catch (NSException *exception) {
            NSLog(@"XLRowHeadingsView: Exception getting data for row %ld: %@ - %@",
                  (long)row, exception.name, exception.reason);
            cell.name = @"<Error>";
            cell.elementType = XLElementTypeModel;
            cell.expandable = NO;
            cell.expanded = NO;
            cell.indentLevel = 0;
        }
    } else {
        cell.name = @"";
        cell.elementType = XLElementTypeModel;
        cell.expandable = NO;
        cell.expanded = NO;
        cell.indentLevel = 0;
    }

    cell.isSelected = (row >= 0 && [_selectedRows containsIndex:(NSUInteger)row]);
    [cell setNeedsDisplay];

    return cell;
}

- (void)layoutRowCells {
    [self layoutRowCellsForceRedraw:NO];
}

- (void)layoutRowCellsForceRedraw:(BOOL)forceRedraw {
    CGFloat viewWidth = NSWidth(self.bounds);
    CGFloat viewHeight = NSHeight(self.bounds);
    NSInteger pinnedCount = _pinnedTimingRowCount;
    CGFloat pinnedHeight = pinnedCount * _rowHeight;

    // Scrollable zone: rows below pinned area
    CGFloat scrollableViewHeight = viewHeight - pinnedHeight;
    NSInteger firstScrollableVisible = (NSInteger)floor(_verticalScrollOffset / _rowHeight);
    NSInteger lastScrollableVisible = (NSInteger)ceil((_verticalScrollOffset + scrollableViewHeight) / _rowHeight);
    if (firstScrollableVisible < 0) firstScrollableVisible = 0;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    for (NSUInteger i = 0; i < _rowCellLayersCount; i++) {
        XLRowCellLayer *cell = _rowCellLayersData[i];
        if (!cell) continue;

        if ((NSInteger)i < pinnedCount) {
            // Pinned timing row: always visible at fixed position, above scrollable rows
            CGFloat y = (CGFloat)i * _rowHeight;
            BOOL wasHidden = cell.hidden;
            cell.frame = CGRectMake(0, y, viewWidth, _rowHeight);
            cell.zPosition = 1.0;
            cell.hidden = NO;
            if (wasHidden || forceRedraw) {
                [cell setNeedsDisplay];
            }
        } else {
            // Scrollable model row
            NSInteger scrollableIndex = (NSInteger)i - pinnedCount;
            if (scrollableIndex >= firstScrollableVisible && scrollableIndex <= lastScrollableVisible) {
                CGFloat y = pinnedHeight + scrollableIndex * _rowHeight - _verticalScrollOffset;
                BOOL wasHidden = cell.hidden;
                cell.frame = CGRectMake(0, y, viewWidth, _rowHeight);
                cell.zPosition = 0.0;
                cell.hidden = NO;
                if (wasHidden || forceRedraw) {
                    [cell setNeedsDisplay];
                }
            } else {
                cell.hidden = YES;
            }
        }
    }

    [CATransaction commit];
}

- (void)updateRowAppearance {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < _rowCellLayersCount; i++) {
        XLRowCellLayer *cell = _rowCellLayersData[i];
        if (!cell) continue;
        BOOL shouldBeSelected = (cell.row >= 0 && [_selectedRows containsIndex:(NSUInteger)cell.row]);
        if (cell.isSelected != shouldBeSelected) {
            cell.isSelected = shouldBeSelected;
            [cell setNeedsDisplay];
        }
    }
    [CATransaction commit];
}

#pragma mark - Drawing (CALayer delegate)

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    CGFloat scale = self.window.backingScaleFactor ?: 2.0;
    for (NSUInteger i = 0; i < _rowCellLayersCount; i++) {
        XLRowCellLayer *cell = _rowCellLayersData[i];
        if (cell) {
            cell.contentsScale = scale;
        }
    }
}

- (void)layout {
    [super layout];
    // Bounds changed, need to redraw cells at new width
    [self layoutRowCellsForceRedraw:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    // Background is handled by the layer; individual rows draw themselves via drawLayer:inContext:
}

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
    if (layer == self.layer) {
        // Draw main background
        CGContextSetRGBFillColor(ctx, 0.14, 0.14, 0.14, 1.0);
        CGContextFillRect(ctx, layer.bounds);
        return;
    }

    if (![layer isKindOfClass:[XLRowCellLayer class]]) {
        return;
    }

    XLRowCellLayer *cell = (XLRowCellLayer *)layer;
    CGRect bounds = layer.bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;

    // Row background — timing tracks always use their track color (brighter when selected)
    BOOL isEvenRow = (cell.row % 2 == 0);
    if (cell.elementType == XLElementTypeTiming) {
        // Opaque background first so scrollable rows don't bleed through pinned layers
        CGContextSetRGBFillColor(ctx, 0.14, 0.14, 0.14, 1.0);
        CGContextFillRect(ctx, bounds);
        CGFloat cr, cg, cb;
        XLTimingTrackColor(cell.timingColorIndex, &cr, &cg, &cb);
        CGFloat alpha = cell.isSelected ? 0.7 : 0.45;
        CGContextSetRGBFillColor(ctx, cr, cg, cb, alpha);
    } else if (cell.isFolder) {
        // Folder header: distinct warm gray background
        if (cell.isSelected) {
            CGContextSetRGBFillColor(ctx, 0.28, 0.26, 0.22, 1.0);
        } else {
            CGContextSetRGBFillColor(ctx, 0.20, 0.19, 0.17, 1.0);
        }
    } else if (cell.isSelected) {
        CGContextSetRGBFillColor(ctx, 0.22, 0.36, 0.55, 1.0);
    } else if (isEvenRow) {
        CGContextSetRGBFillColor(ctx, 0.15, 0.15, 0.15, 1.0);
    } else {
        CGContextSetRGBFillColor(ctx, 0.13, 0.13, 0.13, 1.0);
    }
    CGContextFillRect(ctx, bounds);

    // Bottom separator line
    CGContextSetRGBStrokeColor(ctx, 0.25, 0.25, 0.25, 1.0);
    CGContextSetLineWidth(ctx, 0.5);
    CGContextMoveToPoint(ctx, 0, h - 0.25);
    CGContextAddLineToPoint(ctx, w, h - 0.25);
    CGContextStrokePath(ctx);

    // Calculate horizontal positions
    CGFloat indent = cell.indentLevel * kIndentWidth;
    CGFloat xCursor = kDisclosureLeftPadding + indent;

    // Disclosure triangle
    if (cell.expandable) {
        [self drawDisclosureTriangleInContext:ctx
                                          at:CGPointMake(xCursor, (h - kDisclosureSize) / 2.0)
                                    expanded:cell.expanded];
    }
    xCursor += kDisclosureSize + kIconPadding;

    // Element type icon (SF Symbol) — folder rows use folder icon
    if (cell.isFolder) {
        NSString *folderSymbol = cell.folderCollapsed ? @"folder" : @"folder.fill";
        [self drawSFSymbolInContext:ctx
                               name:folderSymbol
                                 at:CGPointMake(xCursor, (h - kIconSize) / 2.0)
                               size:kIconSize
                              color:CGColorCreateGenericRGB(0.85, 0.72, 0.40, 1.0)];
    } else {
        [self drawIconForElementType:cell.elementType
                           inContext:ctx
                                  at:CGPointMake(xCursor, (h - kIconSize) / 2.0)
                                size:kIconSize];
    }
    xCursor += kIconSize + kIconPadding;

    // Name label (truncated with ellipsis) - extends to right edge with padding
    CGFloat maxTextWidth = w - kIconPadding - xCursor;
    if (maxTextWidth > 0 && cell.name.length > 0) {
        CGColorRef textColor;
        if (cell.isFolder) {
            textColor = cell.isSelected
                ? CGColorCreateGenericRGB(1.0, 1.0, 1.0, 1.0)
                : CGColorCreateGenericRGB(0.90, 0.82, 0.55, 1.0);
        } else {
            textColor = cell.isSelected
                ? CGColorCreateGenericRGB(1.0, 1.0, 1.0, 1.0)
                : CGColorCreateGenericRGB(0.85, 0.85, 0.85, 1.0);
        }
        [self drawTextInContext:ctx
                           text:cell.name
                           rect:CGRectMake(xCursor, 0, maxTextWidth, h)
                      textColor:textColor
                       fontSize:cell.isFolder ? 11.5 : 11.0];
    }
}

#pragma mark - Drawing Helpers

- (void)drawDisclosureTriangleInContext:(CGContextRef)ctx
                                     at:(CGPoint)origin
                               expanded:(BOOL)expanded {
    CGContextSaveGState(ctx);
    CGContextSetRGBFillColor(ctx, 0.6, 0.6, 0.6, 1.0);

    CGFloat cx = origin.x + kDisclosureSize / 2.0;
    CGFloat cy = origin.y + kDisclosureSize / 2.0;

    if (expanded) {
        // Downward pointing triangle
        CGContextMoveToPoint(ctx, cx - 4.0, cy - 2.0);
        CGContextAddLineToPoint(ctx, cx + 4.0, cy - 2.0);
        CGContextAddLineToPoint(ctx, cx, cy + 3.0);
    } else {
        // Right pointing triangle
        CGContextMoveToPoint(ctx, cx - 2.0, cy - 4.0);
        CGContextAddLineToPoint(ctx, cx + 3.0, cy);
        CGContextAddLineToPoint(ctx, cx - 2.0, cy + 4.0);
    }
    CGContextClosePath(ctx);
    CGContextFillPath(ctx);
    CGContextRestoreGState(ctx);
}

- (void)drawIconForElementType:(XLElementType)type
                     inContext:(CGContextRef)ctx
                            at:(CGPoint)origin
                          size:(CGFloat)size {
    NSString *symbolName = nil;
    switch (type) {
        case XLElementTypeModel:
            symbolName = @"lightbulb";  // Single light/prop
            break;
        case XLElementTypeSubmodel:
            symbolName = @"cube";
            break;
        case XLElementTypeStrand:
            symbolName = @"line.3.horizontal";
            break;
        case XLElementTypeTiming:
            symbolName = @"metronome";
            break;
        case XLElementTypeModelGroup:
            symbolName = @"square.grid.2x2";  // Group of items
            break;
    }

    if (!symbolName) return;

    NSImage *symbol = [NSImage imageWithSystemSymbolName:symbolName
                                accessibilityDescription:nil];
    if (!symbol) return;

    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:gc];

    NSImageSymbolConfiguration *config =
        [NSImageSymbolConfiguration configurationWithPointSize:size * 0.7
                                                       weight:NSFontWeightRegular
                                                        scale:NSImageSymbolScaleSmall];
    NSImage *configured = [symbol imageWithSymbolConfiguration:config];

    NSRect iconRect = NSMakeRect(origin.x, origin.y, size, size);
    [configured drawInRect:iconRect
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver
                  fraction:0.7
            respectFlipped:YES
                     hints:nil];

    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawSFSymbolInContext:(CGContextRef)ctx
                         name:(NSString *)symbolName
                           at:(CGPoint)origin
                         size:(CGFloat)size
                        color:(CGColorRef)tintColor {
    NSImage *symbol = [NSImage imageWithSystemSymbolName:symbolName
                                accessibilityDescription:nil];
    if (!symbol) return;

    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:gc];

    NSColor *nsColor = [NSColor colorWithCGColor:tintColor];
    NSImageSymbolConfiguration *sizeConfig =
        [NSImageSymbolConfiguration configurationWithPointSize:size * 0.7
                                                       weight:NSFontWeightMedium
                                                        scale:NSImageSymbolScaleSmall];
    NSImageSymbolConfiguration *colorConfig =
        [NSImageSymbolConfiguration configurationWithHierarchicalColor:nsColor];
    NSImageSymbolConfiguration *combined = [sizeConfig configurationByApplyingConfiguration:colorConfig];
    NSImage *configured = [symbol imageWithSymbolConfiguration:combined];

    NSRect iconRect = NSMakeRect(origin.x, origin.y, size, size);
    [configured drawInRect:iconRect
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:0.9
        respectFlipped:YES
                 hints:nil];

    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawTextInContext:(CGContextRef)ctx
                     text:(NSString *)text
                     rect:(CGRect)rect
                textColor:(CGColorRef)color
                 fontSize:(CGFloat)fontSize {
    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:gc];

    NSColor *nsColor = [NSColor colorWithCGColor:color];
    if (!nsColor) nsColor = [NSColor whiteColor];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    style.alignment = NSTextAlignmentLeft;

    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: nsColor,
        NSParagraphStyleAttributeName: style,
    };

    NSSize textSize = [text sizeWithAttributes:attrs];
    CGFloat ty = rect.origin.y + (rect.size.height - textSize.height) / 2.0;
    NSRect drawRect = NSMakeRect(rect.origin.x, ty, rect.size.width, textSize.height);
    [text drawInRect:drawRect withAttributes:attrs];

    [NSGraphicsContext restoreGraphicsState];
}

#pragma mark - Hit Testing

- (NSInteger)rowAtPoint:(NSPoint)point {
    CGFloat pinnedHeight = _pinnedTimingRowCount * _rowHeight;
    NSInteger row;
    if (_pinnedTimingRowCount > 0 && point.y < pinnedHeight) {
        row = (NSInteger)floor(point.y / _rowHeight);
    } else {
        row = _pinnedTimingRowCount + (NSInteger)floor((point.y - pinnedHeight + _verticalScrollOffset) / _rowHeight);
    }
    if (row < 0 || row >= _cachedRowCount) return -1;
    return row;
}

- (BOOL)isPointInDisclosureTriangle:(NSPoint)point forRow:(NSInteger)row {
    if (row < 0 || row >= _cachedRowCount) return NO;
    if (!_dataSource) return NO;
    if (![_dataSource rowHeadings:self isExpandableAtRow:row]) return NO;

    NSInteger indent = [_dataSource rowHeadings:self indentLevelForRow:row];
    CGFloat xStart = kDisclosureLeftPadding + indent * kIndentWidth;
    CGFloat xEnd = xStart + kDisclosureSize;

    return (point.x >= xStart && point.x <= xEnd);
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [self rowAtPoint:point];

    // Always reset drag state before any early returns to prevent stale state
    _dragInitiated = NO;
    _didDrag = NO;
    _deferredDeselect = NO;
    _mouseDownPoint = point;

    NSLog(@"[RowDrag] mouseDown row=%ld pt=(%.1f,%.1f) clicks=%ld",
          (long)row, point.x, point.y, (long)event.clickCount);

    if (row < 0) return;

    // Double-click: toggle expand/collapse
    if (event.clickCount == 2) {
        if (_dataSource && [_dataSource rowHeadings:self isExpandableAtRow:row]) {
            if ([_delegate respondsToSelector:@selector(rowHeadings:didToggleExpandAtRow:)]) {
                [_delegate rowHeadings:self didToggleExpandAtRow:row];
            }
        }
        return;
    }

    // Single click on disclosure triangle
    if ([self isPointInDisclosureTriangle:point forRow:row]) {
        if ([_delegate respondsToSelector:@selector(rowHeadings:didToggleExpandAtRow:)]) {
            [_delegate rowHeadings:self didToggleExpandAtRow:row];
        }
        return;
    }

    // Multi-select: Cmd-click toggles individual row, Shift-click selects range
    NSUInteger modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;

    if (modifiers & NSEventModifierFlagCommand) {
        // Cmd-click: toggle this row in/out of selection
        if ([_selectedRows containsIndex:(NSUInteger)row]) {
            [_selectedRows removeIndex:(NSUInteger)row];
        } else {
            [_selectedRows addIndex:(NSUInteger)row];
        }
        _selectedRow = row;
        [self updateRowAppearance];
    } else if (modifiers & NSEventModifierFlagShift) {
        // Shift-click: select range from anchor (selectedRow) to clicked row
        NSInteger anchor = _selectedRow;
        if (anchor < 0) anchor = row;
        NSInteger lo = MIN(anchor, row);
        NSInteger hi = MAX(anchor, row);
        [_selectedRows removeAllIndexes];
        [_selectedRows addIndexesInRange:NSMakeRange((NSUInteger)lo, (NSUInteger)(hi - lo + 1))];
        // Keep _selectedRow as the anchor, don't change it
        [self updateRowAppearance];
    } else if (_selectedRows.count > 1 && [_selectedRows containsIndex:(NSUInteger)row]) {
        // Plain click on an already-selected row in a multi-selection:
        // Defer the single-select to mouseUp so a drag can use the full selection
        _deferredDeselect = YES;
        _deferredDeselectRow = row;
        _selectedRow = row;
    } else {
        // Plain click: single select
        _selectedRow = row;
        [_selectedRows removeAllIndexes];
        [_selectedRows addIndex:(NSUInteger)row];
        [self updateRowAppearance];
    }

    if ([_delegate respondsToSelector:@selector(rowHeadings:didSelectRow:)]) {
        [_delegate rowHeadings:self didSelectRow:row];
    }
}

- (void)mouseUp:(NSEvent *)event {
    NSLog(@"[RowDrag] mouseUp didDrag=%d dragInitiated=%d deferredDeselect=%d",
          _didDrag, _dragInitiated, _deferredDeselect);
    // If we deferred a deselect (plain click on multi-selected row) and no drag happened,
    // now reduce to single selection
    if (_deferredDeselect && !_didDrag) {
        _selectedRow = _deferredDeselectRow;
        [_selectedRows removeAllIndexes];
        [_selectedRows addIndex:(NSUInteger)_deferredDeselectRow];
        [self updateRowAppearance];
    }
    _deferredDeselect = NO;
    _didDrag = NO;
}

- (void)rightMouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [self rowAtPoint:point];

    if (row < 0) return;

    // If right-clicking within an existing multi-selection, keep it
    if (![_selectedRows containsIndex:(NSUInteger)row]) {
        self.selectedRow = row;
    }

    NSMenu *menu = nil;
    if ([_delegate respondsToSelector:@selector(rowHeadings:contextMenuForRow:)]) {
        menu = [_delegate rowHeadings:self contextMenuForRow:row];
    }

    if (!menu) {
        menu = [self defaultContextMenuForRow:row];
    }

    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (NSMenu *)defaultContextMenuForRow:(NSInteger)row {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Row Actions"];

    // Check if this is a folder row
    BOOL isFolder = NO;
    if ([_dataSource respondsToSelector:@selector(rowHeadings:isFolderAtRow:)]) {
        isFolder = [_dataSource rowHeadings:self isFolderAtRow:row];
    }

    if (isFolder) {
        [self buildFolderContextMenu:menu forRow:row];
        return menu;
    }

    // Determine element type for this row
    XLElementType elementType = XLElementTypeModel;

    if (_dataSource) {
        elementType = [_dataSource rowHeadings:self elementTypeForRow:row];
    }

    if (elementType == XLElementTypeTiming) {
        [self buildTimingContextMenu:menu forRow:row];
    } else {
        [self buildModelContextMenu:menu forRow:row elementType:elementType];
    }

    return menu;
}

- (void)buildModelContextMenu:(NSMenu *)menu forRow:(NSInteger)row elementType:(XLElementType)elementType {
    // --- Layer Management Section ---
    if (elementType == XLElementTypeModel ||
        elementType == XLElementTypeSubmodel ||
        elementType == XLElementTypeStrand ||
        elementType == XLElementTypeModelGroup) {

        NSMenuItem *insertAbove = [[NSMenuItem alloc] initWithTitle:@"Insert Layer Above"
                                                             action:@selector(contextInsertLayerAbove:)
                                                      keyEquivalent:@""];
        insertAbove.target = self;
        insertAbove.tag = row;
        [menu addItem:insertAbove];

        NSMenuItem *insertBelow = [[NSMenuItem alloc] initWithTitle:@"Insert Layer Below"
                                                             action:@selector(contextInsertLayerBelow:)
                                                      keyEquivalent:@""];
        insertBelow.target = self;
        insertBelow.tag = row;
        [menu addItem:insertBelow];

        NSMenuItem *insertMultiple = [[NSMenuItem alloc] initWithTitle:@"Insert Multiple Layers Below"
                                                               action:@selector(contextInsertMultipleLayersBelow:)
                                                        keyEquivalent:@""];
        insertMultiple.target = self;
        insertMultiple.tag = row;
        [menu addItem:insertMultiple];

        NSMenuItem *deleteLayer = [[NSMenuItem alloc] initWithTitle:@"Delete Layer"
                                                             action:@selector(contextDeleteLayer:)
                                                      keyEquivalent:@""];
        deleteLayer.target = self;
        deleteLayer.tag = row;
        [menu addItem:deleteLayer];

        NSMenuItem *deleteMultiple = [[NSMenuItem alloc] initWithTitle:@"Delete Multiple Layers"
                                                               action:@selector(contextDeleteMultipleLayers:)
                                                        keyEquivalent:@""];
        deleteMultiple.target = self;
        deleteMultiple.tag = row;
        [menu addItem:deleteMultiple];

        NSMenuItem *deleteUnused = [[NSMenuItem alloc] initWithTitle:@"Delete Unused Layers"
                                                              action:@selector(contextDeleteUnusedLayers:)
                                                       keyEquivalent:@""];
        deleteUnused.target = self;
        deleteUnused.tag = row;
        [menu addItem:deleteUnused];

        NSMenuItem *editName = [[NSMenuItem alloc] initWithTitle:@"Edit Layer Name"
                                                          action:@selector(contextEditLayerName:)
                                                   keyEquivalent:@""];
        editName.target = self;
        editName.tag = row;
        [menu addItem:editName];

        [menu addItem:[NSMenuItem separatorItem]];
    }

    // --- Model Structure Section ---
    NSMenuItem *toggleStrands = [[NSMenuItem alloc] initWithTitle:@"Toggle Strands"
                                                          action:@selector(contextToggleStrands:)
                                                   keyEquivalent:@""];
    toggleStrands.target = self;
    toggleStrands.tag = row;
    [menu addItem:toggleStrands];

    NSMenuItem *showAllEffects = [[NSMenuItem alloc] initWithTitle:@"Show All Effects"
                                                           action:@selector(contextShowAllEffects:)
                                                    keyEquivalent:@""];
    showAllEffects.target = self;
    showAllEffects.tag = row;
    [menu addItem:showAllEffects];

    // Collapse All Models
    NSMenuItem *collapseModels = [[NSMenuItem alloc] initWithTitle:@"Collapse All Models"
                                                           action:@selector(contextCollapseAllModels:)
                                                    keyEquivalent:@""];
    collapseModels.target = self;
    collapseModels.tag = row;
    [menu addItem:collapseModels];

    // Collapse All Layers
    NSMenuItem *collapseLayers = [[NSMenuItem alloc] initWithTitle:@"Collapse All Layers"
                                                           action:@selector(contextCollapseAllLayers:)
                                                    keyEquivalent:@""];
    collapseLayers.target = self;
    collapseLayers.tag = row;
    [menu addItem:collapseLayers];

    // Collapse/Expand All Folders
    NSMenuItem *collapseFolders = [[NSMenuItem alloc] initWithTitle:@"Collapse All Folders"
                                                            action:@selector(contextCollapseAllFolders:)
                                                     keyEquivalent:@""];
    collapseFolders.target = self;
    collapseFolders.tag = row;
    [menu addItem:collapseFolders];

    NSMenuItem *expandFolders = [[NSMenuItem alloc] initWithTitle:@"Expand All Folders"
                                                          action:@selector(contextExpandAllFolders:)
                                                   keyEquivalent:@""];
    expandFolders.target = self;
    expandFolders.tag = row;
    [menu addItem:expandFolders];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Track Folder ---
    NSMenuItem *createFolder = [[NSMenuItem alloc] initWithTitle:@"Create Track Folder"
                                                         action:@selector(contextCreateFolder:)
                                                  keyEquivalent:@""];
    createFolder.target = self;
    createFolder.tag = row;
    [menu addItem:createFolder];

    NSMenuItem *removeFromFolder = [[NSMenuItem alloc] initWithTitle:@"Remove from Folder"
                                                             action:@selector(contextRemoveFromFolder:)
                                                      keyEquivalent:@""];
    removeFromFolder.target = self;
    removeFromFolder.tag = row;
    [menu addItem:removeFromFolder];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Render Enable/Disable ---
    BOOL isRenderDisabled = NO;
    if ([_delegate respondsToSelector:@selector(rowHeadingsIsRenderDisabledAtRow:row:)]) {
        isRenderDisabled = [_delegate rowHeadingsIsRenderDisabledAtRow:self row:row];
    }
    NSString *renderTitle = isRenderDisabled ? @"Enable Render" : @"Disable Render";
    NSMenuItem *toggleRender = [[NSMenuItem alloc] initWithTitle:renderTitle
                                                         action:@selector(contextToggleRenderDisabled:)
                                                  keyEquivalent:@""];
    toggleRender.target = self;
    toggleRender.tag = row;
    [menu addItem:toggleRender];

    BOOL hasAnyDisabled = NO;
    if ([_delegate respondsToSelector:@selector(rowHeadingsHasAnyRenderDisabled:)]) {
        hasAnyDisabled = [_delegate rowHeadingsHasAnyRenderDisabled:self];
    }
    if (hasAnyDisabled) {
        NSMenuItem *enableAll = [[NSMenuItem alloc] initWithTitle:@"Enable Render On All Models"
                                                          action:@selector(contextEnableRenderAll:)
                                                   keyEquivalent:@""];
        enableAll.target = self;
        enableAll.tag = row;
        [menu addItem:enableAll];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Playback / Export ---
    NSMenuItem *playModel = [[NSMenuItem alloc] initWithTitle:@"Play Model"
                                                      action:@selector(contextPlayModel:)
                                               keyEquivalent:@""];
    playModel.target = self;
    playModel.tag = row;
    [menu addItem:playModel];

    NSMenuItem *exportModel = [[NSMenuItem alloc] initWithTitle:@"Export Model"
                                                        action:@selector(contextExportModel:)
                                                 keyEquivalent:@""];
    exportModel.target = self;
    exportModel.tag = row;
    [menu addItem:exportModel];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Effect Operations ---
    NSMenuItem *selectAll = [[NSMenuItem alloc] initWithTitle:@"Select All Model Effects"
                                                      action:@selector(contextSelectAllModelEffects:)
                                               keyEquivalent:@""];
    selectAll.target = self;
    selectAll.tag = row;
    [menu addItem:selectAll];

    NSMenuItem *copyEffects = [[NSMenuItem alloc] initWithTitle:@"Copy Model Effects"
                                                        action:@selector(contextCopyModelEffects:)
                                                 keyEquivalent:@""];
    copyEffects.target = self;
    copyEffects.tag = row;
    [menu addItem:copyEffects];

    NSMenuItem *cutEffects = [[NSMenuItem alloc] initWithTitle:@"Cut Model Effects"
                                                       action:@selector(contextCutModelEffects:)
                                                keyEquivalent:@""];
    cutEffects.target = self;
    cutEffects.tag = row;
    [menu addItem:cutEffects];

    NSMenuItem *pasteEffects = [[NSMenuItem alloc] initWithTitle:@"Paste Model Effects"
                                                         action:@selector(contextPasteModelEffects:)
                                                  keyEquivalent:@""];
    pasteEffects.target = self;
    pasteEffects.tag = row;
    [menu addItem:pasteEffects];

    NSMenuItem *deleteEffects = [[NSMenuItem alloc] initWithTitle:@"Delete Model Effects"
                                                          action:@selector(contextDeleteModelEffects:)
                                                   keyEquivalent:@""];
    deleteEffects.target = self;
    deleteEffects.tag = row;
    [menu addItem:deleteEffects];

    NSMenuItem *copyInclSubs = [[NSMenuItem alloc] initWithTitle:@"Copy Effects incl SubModels"
                                                         action:@selector(contextCopyModelEffectsInclSubmodels:)
                                                  keyEquivalent:@""];
    copyInclSubs.target = self;
    copyInclSubs.tag = row;
    [menu addItem:copyInclSubs];
}

- (void)buildFolderContextMenu:(NSMenu *)menu forRow:(NSInteger)row {
    BOOL isCollapsed = NO;
    if ([_dataSource respondsToSelector:@selector(rowHeadings:isFolderCollapsedAtRow:)]) {
        isCollapsed = [_dataSource rowHeadings:self isFolderCollapsedAtRow:row];
    }

    NSString *expandCollapseTitle = isCollapsed ? @"Expand Folder" : @"Collapse Folder";
    NSMenuItem *expandCollapse = [[NSMenuItem alloc] initWithTitle:expandCollapseTitle
                                                           action:@selector(contextToggleFolderExpand:)
                                                    keyEquivalent:@""];
    expandCollapse.target = self;
    expandCollapse.tag = row;
    [menu addItem:expandCollapse];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *renameFolder = [[NSMenuItem alloc] initWithTitle:@"Rename Folder"
                                                         action:@selector(contextRenameFolder:)
                                                  keyEquivalent:@""];
    renameFolder.target = self;
    renameFolder.tag = row;
    [menu addItem:renameFolder];

    NSMenuItem *deleteFolder = [[NSMenuItem alloc] initWithTitle:@"Delete Folder"
                                                         action:@selector(contextDeleteFolder:)
                                                  keyEquivalent:@""];
    deleteFolder.target = self;
    deleteFolder.tag = row;
    [menu addItem:deleteFolder];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *collapseFolders = [[NSMenuItem alloc] initWithTitle:@"Collapse All Folders"
                                                            action:@selector(contextCollapseAllFolders:)
                                                     keyEquivalent:@""];
    collapseFolders.target = self;
    collapseFolders.tag = row;
    [menu addItem:collapseFolders];

    NSMenuItem *expandFolders = [[NSMenuItem alloc] initWithTitle:@"Expand All Folders"
                                                          action:@selector(contextExpandAllFolders:)
                                                   keyEquivalent:@""];
    expandFolders.target = self;
    expandFolders.tag = row;
    [menu addItem:expandFolders];
}

- (void)buildTimingContextMenu:(NSMenu *)menu forRow:(NSInteger)row {
    // --- Timing Track Management ---
    NSMenuItem *addTiming = [[NSMenuItem alloc] initWithTitle:@"Add Timing Track"
                                                      action:@selector(contextAddTimingTrack:)
                                               keyEquivalent:@""];
    addTiming.target = self;
    addTiming.tag = row;
    [menu addItem:addTiming];

    NSMenuItem *renameTiming = [[NSMenuItem alloc] initWithTitle:@"Rename Timing Track"
                                                         action:@selector(contextRenameTimingTrack:)
                                                  keyEquivalent:@""];
    renameTiming.target = self;
    renameTiming.tag = row;
    [menu addItem:renameTiming];

    NSMenuItem *deleteTiming = [[NSMenuItem alloc] initWithTitle:@"Delete Timing Track"
                                                         action:@selector(contextDeleteTimingTrack:)
                                                  keyEquivalent:@""];
    deleteTiming.target = self;
    deleteTiming.tag = row;
    [menu addItem:deleteTiming];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Import / Export ---
    NSMenuItem *importTiming = [[NSMenuItem alloc] initWithTitle:@"Import Timing Track"
                                                         action:@selector(contextImportTimingTrack:)
                                                  keyEquivalent:@""];
    importTiming.target = self;
    importTiming.tag = row;
    [menu addItem:importTiming];

    NSMenuItem *exportTiming = [[NSMenuItem alloc] initWithTitle:@"Export Timing Track"
                                                         action:@selector(contextExportTimingTrack:)
                                                  keyEquivalent:@""];
    exportTiming.target = self;
    exportTiming.tag = row;
    [menu addItem:exportTiming];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Visibility ---
    NSMenuItem *hideAll = [[NSMenuItem alloc] initWithTitle:@"Hide All Timing Tracks"
                                                    action:@selector(contextHideAllTimingTracks:)
                                             keyEquivalent:@""];
    hideAll.target = self;
    hideAll.tag = row;
    [menu addItem:hideAll];

    NSMenuItem *showAll = [[NSMenuItem alloc] initWithTitle:@"Show All Timing Tracks"
                                                    action:@selector(contextShowAllTimingTracks:)
                                             keyEquivalent:@""];
    showAll.target = self;
    showAll.tag = row;
    [menu addItem:showAll];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Lyrics / Notes / Breakdown ---
    NSMenuItem *importNotes = [[NSMenuItem alloc] initWithTitle:@"Import Notes"
                                                        action:@selector(contextImportNotes:)
                                                 keyEquivalent:@""];
    importNotes.target = self;
    importNotes.tag = row;
    [menu addItem:importNotes];

    NSMenuItem *importLyrics = [[NSMenuItem alloc] initWithTitle:@"Import Lyrics"
                                                         action:@selector(contextImportLyrics:)
                                                  keyEquivalent:@""];
    importLyrics.target = self;
    importLyrics.tag = row;
    [menu addItem:importLyrics];

    NSMenuItem *breakdownPhrases = [[NSMenuItem alloc] initWithTitle:@"Breakdown Phrases"
                                                             action:@selector(contextBreakdownPhrases:)
                                                      keyEquivalent:@""];
    breakdownPhrases.target = self;
    breakdownPhrases.tag = row;
    [menu addItem:breakdownPhrases];

    NSMenuItem *breakdownWords = [[NSMenuItem alloc] initWithTitle:@"Breakdown Words"
                                                           action:@selector(contextBreakdownWords:)
                                                    keyEquivalent:@""];
    breakdownWords.target = self;
    breakdownWords.tag = row;
    [menu addItem:breakdownWords];
}

#pragma mark - Context Menu Actions

- (void)contextInsertLayerAbove:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:insertLayerAboveRow:)]) {
        [_delegate rowHeadings:self insertLayerAboveRow:row];
    }
}

- (void)contextInsertLayerBelow:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:insertLayerBelowRow:)]) {
        [_delegate rowHeadings:self insertLayerBelowRow:row];
    }
}

- (void)contextInsertMultipleLayersBelow:(NSMenuItem *)sender {
    NSInteger row = sender.tag;

    // Show count dialog using NSAlert with an accessory text field
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Insert Multiple Layers";
    alert.informativeText = @"Enter number of layers to insert:";
    [alert addButtonWithTitle:@"Insert"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    input.stringValue = @"2";
    alert.accessoryView = input;

    [alert.window makeFirstResponder:input];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSInteger count = input.integerValue;
        if (count > 0 && count <= 100) {
            if ([_delegate respondsToSelector:@selector(rowHeadings:insertMultipleLayersBelowRow:count:)]) {
                [_delegate rowHeadings:self insertMultipleLayersBelowRow:row count:count];
            }
        }
    }
}

- (void)contextDeleteLayer:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:deleteLayerAtRow:)]) {
        [_delegate rowHeadings:self deleteLayerAtRow:row];
    }
}

- (void)contextDeleteMultipleLayers:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:deleteMultipleLayersAtRow:)]) {
        [_delegate rowHeadings:self deleteMultipleLayersAtRow:row];
    }
}

- (void)contextDeleteUnusedLayers:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:deleteUnusedLayersAtRow:)]) {
        [_delegate rowHeadings:self deleteUnusedLayersAtRow:row];
    }
}

- (void)contextEditLayerName:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:editLayerNameAtRow:)]) {
        [_delegate rowHeadings:self editLayerNameAtRow:row];
    }
}

- (void)contextCollapseAllModels:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(rowHeadingsCollapseAllModels:)]) {
        [_delegate rowHeadingsCollapseAllModels:self];
    }
}

- (void)contextCollapseAllLayers:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(rowHeadingsCollapseAllLayers:)]) {
        [_delegate rowHeadingsCollapseAllLayers:self];
    }
}

#pragma mark - Model Context Menu Actions

- (void)contextToggleStrands:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:toggleStrandsAtRow:)]) {
        [_delegate rowHeadings:self toggleStrandsAtRow:row];
    }
}

- (void)contextShowAllEffects:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:showAllEffectsAtRow:)]) {
        [_delegate rowHeadings:self showAllEffectsAtRow:row];
    }
}

- (void)contextToggleRenderDisabled:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:toggleRenderDisabledAtRow:)]) {
        [_delegate rowHeadings:self toggleRenderDisabledAtRow:row];
    }
}

- (void)contextEnableRenderAll:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(rowHeadingsEnableRenderOnAllModels:)]) {
        [_delegate rowHeadingsEnableRenderOnAllModels:self];
    }
}

- (void)contextPlayModel:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:playModelAtRow:)]) {
        [_delegate rowHeadings:self playModelAtRow:row];
    }
}

- (void)contextExportModel:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:exportModelAtRow:)]) {
        [_delegate rowHeadings:self exportModelAtRow:row];
    }
}

- (void)contextSelectAllModelEffects:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:selectAllModelEffectsAtRow:)]) {
        [_delegate rowHeadings:self selectAllModelEffectsAtRow:row];
    }
}

- (void)contextCopyModelEffects:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:copyModelEffectsAtRow:)]) {
        [_delegate rowHeadings:self copyModelEffectsAtRow:row];
    }
}

- (void)contextCutModelEffects:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:cutModelEffectsAtRow:)]) {
        [_delegate rowHeadings:self cutModelEffectsAtRow:row];
    }
}

- (void)contextPasteModelEffects:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:pasteModelEffectsAtRow:)]) {
        [_delegate rowHeadings:self pasteModelEffectsAtRow:row];
    }
}

- (void)contextDeleteModelEffects:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:deleteModelEffectsAtRow:)]) {
        [_delegate rowHeadings:self deleteModelEffectsAtRow:row];
    }
}

- (void)contextCopyModelEffectsInclSubmodels:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:copyModelEffectsIncludingSubmodelsAtRow:)]) {
        [_delegate rowHeadings:self copyModelEffectsIncludingSubmodelsAtRow:row];
    }
}

#pragma mark - Timing Context Menu Actions

- (void)contextAddTimingTrack:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(rowHeadingsAddTimingTrack:)]) {
        [_delegate rowHeadingsAddTimingTrack:self];
    }
}

- (void)contextRenameTimingTrack:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:renameTimingTrackAtRow:)]) {
        [_delegate rowHeadings:self renameTimingTrackAtRow:row];
    }
}

- (void)contextDeleteTimingTrack:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:deleteTimingTrackAtRow:)]) {
        [_delegate rowHeadings:self deleteTimingTrackAtRow:row];
    }
}

- (void)contextImportTimingTrack:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:importTimingTrackAtRow:)]) {
        [_delegate rowHeadings:self importTimingTrackAtRow:row];
    }
}

- (void)contextExportTimingTrack:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:exportTimingTrackAtRow:)]) {
        [_delegate rowHeadings:self exportTimingTrackAtRow:row];
    }
}

- (void)contextHideAllTimingTracks:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(rowHeadingsHideAllTimingTracks:)]) {
        [_delegate rowHeadingsHideAllTimingTracks:self];
    }
}

- (void)contextShowAllTimingTracks:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(rowHeadingsShowAllTimingTracks:)]) {
        [_delegate rowHeadingsShowAllTimingTracks:self];
    }
}

- (void)contextImportNotes:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:importNotesAtRow:)]) {
        [_delegate rowHeadings:self importNotesAtRow:row];
    }
}

- (void)contextImportLyrics:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:importLyricsAtRow:)]) {
        [_delegate rowHeadings:self importLyricsAtRow:row];
    }
}

- (void)contextBreakdownPhrases:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:breakdownPhrasesAtRow:)]) {
        [_delegate rowHeadings:self breakdownPhrasesAtRow:row];
    }
}

- (void)contextBreakdownWords:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:breakdownWordsAtRow:)]) {
        [_delegate rowHeadings:self breakdownWordsAtRow:row];
    }
}

// --- Track Folder Context Menu Actions ---

- (void)contextToggleFolderExpand:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:didToggleExpandAtRow:)]) {
        [_delegate rowHeadings:self didToggleExpandAtRow:row];
    }
}

- (void)contextRenameFolder:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:renameFolderAtRow:)]) {
        [_delegate rowHeadings:self renameFolderAtRow:row];
    }
}

- (void)contextDeleteFolder:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:deleteFolderAtRow:)]) {
        [_delegate rowHeadings:self deleteFolderAtRow:row];
    }
}

- (void)contextCollapseAllFolders:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(rowHeadingsCollapseAllFolders:)]) {
        [_delegate rowHeadingsCollapseAllFolders:self];
    }
}

- (void)contextExpandAllFolders:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(rowHeadingsExpandAllFolders:)]) {
        [_delegate rowHeadingsExpandAllFolders:self];
    }
}

- (void)contextCreateFolder:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:createFolderFromRow:)]) {
        [_delegate rowHeadings:self createFolderFromRow:row];
    }
}

- (void)contextRemoveFromFolder:(NSMenuItem *)sender {
    NSInteger row = sender.tag;
    if ([_delegate respondsToSelector:@selector(rowHeadings:removeFromFolderAtRow:)]) {
        [_delegate rowHeadings:self removeFromFolderAtRow:row];
    }
}

#pragma mark - Drag and Drop (Source)

- (void)mouseDragged:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    // Require minimum drag distance before initiating drag session
    if (!_dragInitiated) {
        CGFloat dx = point.x - _mouseDownPoint.x;
        CGFloat dy = point.y - _mouseDownPoint.y;
        CGFloat dist = sqrt(dx * dx + dy * dy);
        NSLog(@"[RowDrag] mouseDragged below threshold dist=%.1f (need %.1f) pt=(%.1f,%.1f)",
              dist, kDragDistanceThreshold, point.x, point.y);
        if (dist < kDragDistanceThreshold) return;
        NSLog(@"[RowDrag] mouseDragged THRESHOLD MET — initiating drag");
        _dragInitiated = YES;
    }

    NSInteger row = [self rowAtPoint:_mouseDownPoint];
    NSLog(@"[RowDrag] mouseDragged beginDraggingSession row=%ld", (long)row);

    if (row < 0 || row >= _cachedRowCount) return;

    _didDrag = YES;
    _deferredDeselect = NO;
    _dragSourceRow = row;
    _dragOntoFolderRow = -1;

    // Record source row properties for drop validation
    _dragSourceIsFolder = NO;
    _dragSourceIsTiming = NO;
    if (_dataSource) {
        if ([_dataSource respondsToSelector:@selector(rowHeadings:isFolderAtRow:)]) {
            _dragSourceIsFolder = [_dataSource rowHeadings:self isFolderAtRow:row];
        }
        XLElementType type = [_dataSource rowHeadings:self elementTypeForRow:row];
        _dragSourceIsTiming = (type == XLElementTypeTiming);
    }

    NSString *dragString = [NSString stringWithFormat:@"row:%ld", (long)row];
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setString:dragString forType:NSPasteboardTypeString];

    NSDraggingItem *dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:pbItem];

    // Calculate visual row rect accounting for pinned timing area
    CGFloat pinnedHeight = _pinnedTimingRowCount * _rowHeight;
    CGFloat y;
    if (row < _pinnedTimingRowCount) {
        y = row * _rowHeight;
    } else {
        y = pinnedHeight + (row - _pinnedTimingRowCount) * _rowHeight - _verticalScrollOffset;
    }
    // Determine drag count from multi-selection
    NSUInteger dragCount = 1;
    if (_selectedRows.count > 1 && [_selectedRows containsIndex:(NSUInteger)row]) {
        dragCount = _selectedRows.count;
    }

    NSRect rowRect = NSMakeRect(0, y, NSWidth(self.bounds), _rowHeight);
    [dragItem setDraggingFrame:rowRect contents:[self imageForRow:row dragCount:dragCount]];

    [self beginDraggingSessionWithItems:@[dragItem] event:event source:self];
}

- (NSImage *)imageForRow:(NSInteger)row dragCount:(NSUInteger)count {
    CGFloat w = NSWidth(self.bounds);
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(w, _rowHeight)];
    [image lockFocus];

    NSString *name = @"";
    if (_dataSource) {
        name = [_dataSource rowHeadings:self nameForRow:row];
    }
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.0],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };
    [[NSColor colorWithWhite:0.2 alpha:0.8] setFill];
    NSRectFill(NSMakeRect(0, 0, w, _rowHeight));
    [name drawAtPoint:NSMakePoint(20, (_rowHeight - 14) / 2.0) withAttributes:attrs];

    // Draw count badge for multi-item drag
    if (count > 1) {
        NSString *badgeText = [NSString stringWithFormat:@"%lu", (unsigned long)count];
        NSDictionary *badgeAttrs = @{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:10.0],
            NSForegroundColorAttributeName: [NSColor whiteColor],
        };
        NSSize textSize = [badgeText sizeWithAttributes:badgeAttrs];
        CGFloat badgeW = MAX(textSize.width + 8, _rowHeight - 4);
        CGFloat badgeH = _rowHeight - 4;
        CGFloat badgeX = w - badgeW - 6;
        CGFloat badgeY = 2;
        NSRect badgeRect = NSMakeRect(badgeX, badgeY, badgeW, badgeH);

        [[NSColor colorWithRed:0.35 green:0.55 blue:0.85 alpha:1.0] setFill];
        NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:badgeRect
                                                             xRadius:badgeH / 2.0
                                                             yRadius:badgeH / 2.0];
        [pill fill];

        CGFloat tx = badgeX + (badgeW - textSize.width) / 2.0;
        CGFloat ty = badgeY + (badgeH - textSize.height) / 2.0;
        [badgeText drawAtPoint:NSMakePoint(tx, ty) withAttributes:badgeAttrs];
    }

    [image unlockFocus];
    return image;
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationMove;
}

#pragma mark - Drag and Drop (Destination)

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return NSDragOperationMove;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
    NSInteger targetRow = [self rowAtPoint:point];

    if (targetRow < 0) targetRow = 0;
    if (targetRow >= _cachedRowCount) targetRow = _cachedRowCount - 1;

    // Don't allow dropping onto self
    if (targetRow == _dragSourceRow) {
        _dragTargetRow = -1;
        _dragOntoFolderRow = -1;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _insertionIndicatorLayer.hidden = YES;
        _folderDropHighlightLayer.hidden = YES;
        [CATransaction commit];
        return NSDragOperationNone;
    }

    // Check if target is a folder row
    BOOL targetIsFolder = NO;
    if (targetRow >= 0 && targetRow < _cachedRowCount && _dataSource) {
        if ([_dataSource respondsToSelector:@selector(rowHeadings:isFolderAtRow:)]) {
            targetIsFolder = [_dataSource rowHeadings:self isFolderAtRow:targetRow];
        }
    }

    // Timing tracks and folders can't be dropped into folders
    BOOL canDropIntoFolder = targetIsFolder && !_dragSourceIsTiming && !_dragSourceIsFolder;

    // Calculate position within the target row
    CGFloat pinnedHeight = _pinnedTimingRowCount * _rowHeight;
    CGFloat rowY;
    if (targetRow < _pinnedTimingRowCount) {
        rowY = targetRow * _rowHeight;
    } else {
        rowY = pinnedHeight + (targetRow - _pinnedTimingRowCount) * _rowHeight - _verticalScrollOffset;
    }
    CGFloat relativeY = point.y - rowY;
    CGFloat fraction = relativeY / _rowHeight;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (canDropIntoFolder && fraction > 0.25 && fraction < 0.75) {
        // Drop INTO the folder — highlight the folder row
        _dragOntoFolderRow = targetRow;
        _dragTargetRow = -1;
        _insertionIndicatorLayer.hidden = YES;

        _folderDropHighlightLayer.frame = CGRectMake(2, rowY + 1,
                                                      NSWidth(self.bounds) - 4, _rowHeight - 2);
        _folderDropHighlightLayer.hidden = NO;
    } else {
        // Standard insertion line between rows
        _dragOntoFolderRow = -1;
        _folderDropHighlightLayer.hidden = YES;

        NSInteger insertRow;
        if (fraction < 0.5) {
            insertRow = targetRow;
        } else {
            insertRow = targetRow + 1;
        }
        if (insertRow > _cachedRowCount) insertRow = _cachedRowCount;

        _dragTargetRow = insertRow;

        CGFloat lineY;
        if (insertRow < _pinnedTimingRowCount) {
            lineY = insertRow * _rowHeight;
        } else {
            lineY = pinnedHeight + (insertRow - _pinnedTimingRowCount) * _rowHeight - _verticalScrollOffset;
        }
        _insertionIndicatorLayer.frame = CGRectMake(0, lineY - kDragInsertionLineHeight / 2.0,
                                                     NSWidth(self.bounds), kDragInsertionLineHeight);
        _insertionIndicatorLayer.hidden = NO;
    }

    [CATransaction commit];
    return NSDragOperationMove;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _insertionIndicatorLayer.hidden = YES;
    _folderDropHighlightLayer.hidden = YES;
    [CATransaction commit];
    _dragTargetRow = -1;
    _dragOntoFolderRow = -1;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _insertionIndicatorLayer.hidden = YES;
    _folderDropHighlightLayer.hidden = YES;
    [CATransaction commit];

    if (_dragSourceRow >= 0) {
        if (_dragOntoFolderRow >= 0 && _dragOntoFolderRow < _cachedRowCount) {
            // Drop into folder — delegate reads selectedRows for multi-move
            NSString *folderName = nil;
            if (_dataSource) {
                folderName = [_dataSource rowHeadings:self nameForRow:_dragOntoFolderRow];
            }
            if (folderName && [_delegate respondsToSelector:@selector(rowHeadings:moveRowToFolder:folderName:)]) {
                [_delegate rowHeadings:self moveRowToFolder:_dragSourceRow folderName:folderName];
            }
        } else if (_dragTargetRow >= 0 && _dragSourceRow != _dragTargetRow) {
            // Standard reorder
            if ([_delegate respondsToSelector:@selector(rowHeadings:didReorderRow:toRow:)]) {
                [_delegate rowHeadings:self didReorderRow:_dragSourceRow toRow:_dragTargetRow];
            }
        }
    }

    // Clear selection AFTER delegate call (it needs selectedRows for multi-move),
    // then refresh visuals since reloadData already rebuilt cells with old selection
    _selectedRow = -1;
    [_selectedRows removeAllIndexes];
    [self updateRowAppearance];

    _dragSourceRow = -1;
    _dragTargetRow = -1;
    _dragOntoFolderRow = -1;
    _dragSourceIsFolder = NO;
    _dragSourceIsTiming = NO;
    return YES;
}

#pragma mark - Scroll Wheel

- (void)scrollWheel:(NSEvent *)event {
    // Vertical scrolling for row headings
    CGFloat dy = event.scrollingDeltaY;

    if (fabs(dy) > 0.01) {
        _verticalScrollOffset = fmax(0, _verticalScrollOffset - dy);
        [self layoutRowCells];

        if ([_delegate respondsToSelector:@selector(rowHeadings:didChangeVerticalScrollOffset:)]) {
            [_delegate rowHeadings:self didChangeVerticalScrollOffset:_verticalScrollOffset];
        }
    } else {
        // Forward any other scroll events (horizontal) to parent
        [self.nextResponder scrollWheel:event];
    }
}

@end
