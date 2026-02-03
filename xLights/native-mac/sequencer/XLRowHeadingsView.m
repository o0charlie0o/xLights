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
#import <QuartzCore/QuartzCore.h>

static const CGFloat kDisclosureSize = 10.0;
static const CGFloat kDisclosureLeftPadding = 4.0;
static const CGFloat kIconSize = 14.0;
static const CGFloat kIconPadding = 3.0;
static const CGFloat kIndentWidth = 16.0;
static const CGFloat kMuteSoloButtonWidth = 16.0;
static const CGFloat kMuteSoloButtonPadding = 2.0;
static const CGFloat kDragInsertionLineHeight = 2.0;

#pragma mark - Row Cell Layer

@interface XLRowCellLayer : CALayer
@property (nonatomic, assign) NSInteger row;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, assign) BOOL expandable;
@property (nonatomic, assign) BOOL isSelected;
@property (nonatomic, assign) XLElementType elementType;
@property (nonatomic, assign) NSInteger indentLevel;
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
@property (nonatomic, strong) CALayer *insertionIndicatorLayer;
@property (nonatomic, assign) NSInteger dragSourceRow;
@property (nonatomic, assign) NSInteger dragTargetRow;
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
        _cachedRowCount = 0;
        _dragSourceRow = -1;
        _dragTargetRow = -1;

        // Initialize C array for row cell layers
        _rowCellLayersCapacity = 64;
        _rowCellLayersCount = 0;
        _rowCellLayersData = (__strong XLRowCellLayer **)calloc(_rowCellLayersCapacity, sizeof(XLRowCellLayer *));

        _insertionIndicatorLayer = [CALayer layer];
        _insertionIndicatorLayer.backgroundColor = CGColorCreateGenericRGB(0.3, 0.6, 1.0, 1.0);
        _insertionIndicatorLayer.hidden = YES;
        [self.layer addSublayer:_insertionIndicatorLayer];

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
    [self layoutRowCells];
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

    cell.isSelected = (row == _selectedRow);
    [cell setNeedsDisplay];

    return cell;
}

- (void)layoutRowCells {
    CGFloat viewWidth = NSWidth(self.bounds);
    CGFloat viewHeight = NSHeight(self.bounds);

    NSInteger firstVisible = (NSInteger)floor(_verticalScrollOffset / _rowHeight);
    NSInteger lastVisible = (NSInteger)ceil((_verticalScrollOffset + viewHeight) / _rowHeight);
    if (firstVisible < 0) firstVisible = 0;
    if (lastVisible >= _cachedRowCount) lastVisible = _cachedRowCount - 1;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    for (NSUInteger i = 0; i < _rowCellLayersCount; i++) {
        XLRowCellLayer *cell = _rowCellLayersData[i];
        if (!cell) continue;
        if ((NSInteger)i >= firstVisible && (NSInteger)i <= lastVisible) {
            CGFloat y = (CGFloat)i * _rowHeight - _verticalScrollOffset;
            cell.frame = CGRectMake(0, y, viewWidth, _rowHeight);
            cell.hidden = NO;
            [cell setNeedsDisplay];
        } else {
            cell.hidden = YES;
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
        BOOL shouldBeSelected = (cell.row == _selectedRow);
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
    [self layoutRowCells];
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

    // Alternating row background
    BOOL isEvenRow = (cell.row % 2 == 0);
    if (cell.isSelected) {
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

    // Element type icon (SF Symbol)
    [self drawIconForElementType:cell.elementType
                       inContext:ctx
                              at:CGPointMake(xCursor, (h - kIconSize) / 2.0)
                            size:kIconSize];
    xCursor += kIconSize + kIconPadding;

    // Right side: mute/solo buttons area
    CGFloat rightEdge = w - kMuteSoloButtonPadding;
    CGFloat muteX = rightEdge - kMuteSoloButtonWidth;
    CGFloat soloX = muteX - kMuteSoloButtonPadding - kMuteSoloButtonWidth;

    // Draw solo button (S)
    [self drawSmallButtonInContext:ctx
                               at:CGRectMake(soloX, (h - kMuteSoloButtonWidth) / 2.0,
                                             kMuteSoloButtonWidth, kMuteSoloButtonWidth)
                            label:'S'
                            color:CGColorCreateGenericRGB(0.8, 0.7, 0.2, 1.0)
                           active:NO];

    // Draw mute button (M)
    [self drawSmallButtonInContext:ctx
                               at:CGRectMake(muteX, (h - kMuteSoloButtonWidth) / 2.0,
                                             kMuteSoloButtonWidth, kMuteSoloButtonWidth)
                            label:'M'
                            color:CGColorCreateGenericRGB(0.8, 0.3, 0.3, 1.0)
                           active:NO];

    // Name label (truncated with ellipsis)
    CGFloat maxTextWidth = soloX - kMuteSoloButtonPadding - xCursor;
    if (maxTextWidth > 0 && cell.name.length > 0) {
        [self drawTextInContext:ctx
                           text:cell.name
                           rect:CGRectMake(xCursor, 0, maxTextWidth, h)
                      textColor:cell.isSelected
                                    ? CGColorCreateGenericRGB(1.0, 1.0, 1.0, 1.0)
                                    : CGColorCreateGenericRGB(0.85, 0.85, 0.85, 1.0)
                       fontSize:11.0];
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
            symbolName = @"square.grid.2x2";
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
            symbolName = @"folder";
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

- (void)drawSmallButtonInContext:(CGContextRef)ctx
                              at:(CGRect)rect
                           label:(char)label
                           color:(CGColorRef)color
                          active:(BOOL)active {
    CGContextSaveGState(ctx);

    // Button background
    CGFloat cornerRadius = 3.0;
    if (active) {
        CGContextSetFillColorWithColor(ctx, color);
    } else {
        CGContextSetRGBFillColor(ctx, 0.22, 0.22, 0.22, 1.0);
    }

    CGPathRef path = CGPathCreateWithRoundedRect(rect, cornerRadius, cornerRadius, NULL);
    CGContextAddPath(ctx, path);
    CGContextFillPath(ctx);
    CGPathRelease(path);

    // Button border
    CGContextSetRGBStrokeColor(ctx, 0.35, 0.35, 0.35, 1.0);
    CGContextSetLineWidth(ctx, 0.5);
    path = CGPathCreateWithRoundedRect(rect, cornerRadius, cornerRadius, NULL);
    CGContextAddPath(ctx, path);
    CGContextStrokePath(ctx);
    CGPathRelease(path);

    // Label character
    NSString *labelStr = [NSString stringWithFormat:@"%c", label];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:8.0 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: active
            ? [NSColor blackColor]
            : [NSColor colorWithWhite:0.55 alpha:1.0],
    };

    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:gc];

    NSSize textSize = [labelStr sizeWithAttributes:attrs];
    CGFloat tx = rect.origin.x + (rect.size.width - textSize.width) / 2.0;
    CGFloat ty = rect.origin.y + (rect.size.height - textSize.height) / 2.0;
    [labelStr drawAtPoint:NSMakePoint(tx, ty) withAttributes:attrs];

    [NSGraphicsContext restoreGraphicsState];
    CGContextRestoreGState(ctx);
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
    CGFloat adjustedY = point.y + _verticalScrollOffset;
    NSInteger row = (NSInteger)floor(adjustedY / _rowHeight);
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

    // Single click: select row
    self.selectedRow = row;
    if ([_delegate respondsToSelector:@selector(rowHeadings:didSelectRow:)]) {
        [_delegate rowHeadings:self didSelectRow:row];
    }
}

- (void)mouseUp:(NSEvent *)event {
    // Reserved for drag completion if needed
}

- (void)rightMouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [self rowAtPoint:point];

    if (row < 0) return;

    self.selectedRow = row;

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

    NSMenuItem *addLayer = [[NSMenuItem alloc] initWithTitle:@"Add Layer"
                                                     action:@selector(contextAddLayer:)
                                              keyEquivalent:@""];
    addLayer.target = self;
    addLayer.tag = row;
    [menu addItem:addLayer];

    NSMenuItem *deleteElement = [[NSMenuItem alloc] initWithTitle:@"Delete Element"
                                                          action:@selector(contextDeleteElement:)
                                                   keyEquivalent:@""];
    deleteElement.target = self;
    deleteElement.tag = row;
    [menu addItem:deleteElement];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *solo = [[NSMenuItem alloc] initWithTitle:@"Solo"
                                                 action:@selector(contextSolo:)
                                          keyEquivalent:@""];
    solo.target = self;
    solo.tag = row;
    [menu addItem:solo];

    NSMenuItem *mute = [[NSMenuItem alloc] initWithTitle:@"Mute"
                                                 action:@selector(contextMute:)
                                          keyEquivalent:@""];
    mute.target = self;
    mute.tag = row;
    [menu addItem:mute];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *rename = [[NSMenuItem alloc] initWithTitle:@"Rename..."
                                                   action:@selector(contextRename:)
                                            keyEquivalent:@""];
    rename.target = self;
    rename.tag = row;
    [menu addItem:rename];

    return menu;
}

#pragma mark - Context Menu Actions

- (void)contextAddLayer:(NSMenuItem *)sender {
    NSLog(@"XLRowHeadingsView: Add Layer for row %ld", (long)sender.tag);
}

- (void)contextDeleteElement:(NSMenuItem *)sender {
    NSLog(@"XLRowHeadingsView: Delete Element for row %ld", (long)sender.tag);
}

- (void)contextSolo:(NSMenuItem *)sender {
    NSLog(@"XLRowHeadingsView: Solo for row %ld", (long)sender.tag);
}

- (void)contextMute:(NSMenuItem *)sender {
    NSLog(@"XLRowHeadingsView: Mute for row %ld", (long)sender.tag);
}

- (void)contextRename:(NSMenuItem *)sender {
    NSLog(@"XLRowHeadingsView: Rename for row %ld", (long)sender.tag);
}

#pragma mark - Drag and Drop (Source)

- (void)mouseDragged:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [self rowAtPoint:point];

    if (row < 0 || row >= _cachedRowCount) return;

    _dragSourceRow = row;

    NSString *dragString = [NSString stringWithFormat:@"row:%ld", (long)row];
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setString:dragString forType:NSPasteboardTypeString];

    NSDraggingItem *dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:pbItem];

    CGFloat y = row * _rowHeight - _verticalScrollOffset;
    NSRect rowRect = NSMakeRect(0, y, NSWidth(self.bounds), _rowHeight);
    [dragItem setDraggingFrame:rowRect contents:[self imageForRow:row]];

    [self beginDraggingSessionWithItems:@[dragItem] event:event source:self];
}

- (NSImage *)imageForRow:(NSInteger)row {
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
    if (targetRow >= _cachedRowCount) targetRow = _cachedRowCount;

    _dragTargetRow = targetRow;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat y = targetRow * _rowHeight - _verticalScrollOffset;
    _insertionIndicatorLayer.frame = CGRectMake(0, y - kDragInsertionLineHeight / 2.0,
                                                 NSWidth(self.bounds), kDragInsertionLineHeight);
    _insertionIndicatorLayer.hidden = NO;
    [CATransaction commit];

    return NSDragOperationMove;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _insertionIndicatorLayer.hidden = YES;
    [CATransaction commit];
    _dragTargetRow = -1;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _insertionIndicatorLayer.hidden = YES;
    [CATransaction commit];

    if (_dragSourceRow >= 0 && _dragTargetRow >= 0 && _dragSourceRow != _dragTargetRow) {
        if ([_delegate respondsToSelector:@selector(rowHeadings:didReorderRow:toRow:)]) {
            [_delegate rowHeadings:self didReorderRow:_dragSourceRow toRow:_dragTargetRow];
        }
    }

    _dragSourceRow = -1;
    _dragTargetRow = -1;
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
