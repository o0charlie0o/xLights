/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLCustomModelWindow.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const CGFloat kWindowWidth = 1200.0;
static const CGFloat kWindowHeight = 800.0;
static const CGFloat kDefaultCellSize = 30.0;
static const CGFloat kMinCellSize = 10.0;
static const CGFloat kMaxCellSize = 80.0;

#pragma mark - XLCustomModelGridView

@interface XLCustomModelGridView () {
    // Use C arrays for node data to avoid heap corruption
    XLCustomNode *_nodeData;
    NSInteger _dataWidth;
    NSInteger _dataHeight;
    NSInteger _dataDepth;
    size_t _dataCapacity;
}

@property (nonatomic, strong) NSMutableSet<NSValue *> *selection;
@property (nonatomic, strong) NSMutableArray<NSData *> *undoStack;
@property (nonatomic, strong) NSMutableArray<NSData *> *redoStack;
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) NSPoint dragStart;
@property (nonatomic, strong) NSData *clipboard;

@end

@implementation XLCustomModelGridView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _gridWidth = 10;
        _gridHeight = 10;
        _currentLayer = 0;
        _cellSize = kDefaultCellSize;
        _showWiring = NO;
        _showDuplicates = NO;
        _autoIncrement = YES;
        _nextNodeNumber = 1;
        _backgroundAlpha = 0.5;

        _selection = [NSMutableSet set];
        _undoStack = [NSMutableArray array];
        _redoStack = [NSMutableArray array];

        // Allocate initial node data
        _dataWidth = _gridWidth;
        _dataHeight = _gridHeight;
        _dataDepth = 1;
        _dataCapacity = _dataWidth * _dataHeight * _dataDepth;
        _nodeData = (XLCustomNode *)calloc(_dataCapacity, sizeof(XLCustomNode));

        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];
    }
    return self;
}

- (void)dealloc {
    if (_nodeData) {
        free(_nodeData);
        _nodeData = NULL;
    }
}

- (void)ensureCapacity {
    size_t required = _gridWidth * _gridHeight * (_currentLayer + 1);
    if (required > _dataCapacity) {
        size_t newCapacity = required * 2;
        XLCustomNode *newData = (XLCustomNode *)calloc(newCapacity, sizeof(XLCustomNode));
        if (_nodeData) {
            memcpy(newData, _nodeData, _dataCapacity * sizeof(XLCustomNode));
            free(_nodeData);
        }
        _nodeData = newData;
        _dataCapacity = newCapacity;
        _dataWidth = _gridWidth;
        _dataHeight = _gridHeight;
        _dataDepth = _currentLayer + 1;
    }
}

- (NSInteger)indexForX:(NSInteger)x y:(NSInteger)y layer:(NSInteger)layer {
    if (x < 0 || x >= _gridWidth || y < 0 || y >= _gridHeight || layer < 0) {
        return -1;
    }
    return (layer * _gridWidth * _gridHeight) + (y * _gridWidth) + x;
}

- (XLCustomNode)nodeAtX:(NSInteger)x y:(NSInteger)y layer:(NSInteger)layer {
    XLCustomNode empty = {0, 0, 0, 0};
    NSInteger idx = [self indexForX:x y:y layer:layer];
    if (idx < 0 || idx >= (NSInteger)_dataCapacity) return empty;
    return _nodeData[idx];
}

- (void)setNode:(XLCustomNode)node atX:(NSInteger)x y:(NSInteger)y layer:(NSInteger)layer {
    [self ensureCapacity];
    NSInteger idx = [self indexForX:x y:y layer:layer];
    if (idx < 0 || idx >= (NSInteger)_dataCapacity) return;
    _nodeData[idx] = node;
    [self setNeedsDisplay:YES];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                options:(NSTrackingMouseEnteredAndExited |
                                                        NSTrackingMouseMoved |
                                                        NSTrackingActiveInKeyWindow)
                                                  owner:self
                                               userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    // Draw background image if present
    if (_backgroundImage) {
        [NSGraphicsContext saveGraphicsState];
        [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];

        NSRect imageRect = NSMakeRect(0, 0, _gridWidth * _cellSize, _gridHeight * _cellSize);
        [_backgroundImage drawInRect:imageRect
                            fromRect:NSZeroRect
                           operation:NSCompositingOperationSourceOver
                            fraction:_backgroundAlpha];

        [NSGraphicsContext restoreGraphicsState];
    }

    // Draw grid
    [self drawGrid];

    // Draw nodes
    [self drawNodes];

    // Draw wiring if enabled
    if (_showWiring) {
        [self drawWiring];
    }

    // Draw selection
    [self drawSelection];

    // Highlight duplicates if enabled
    if (_showDuplicates) {
        [self highlightDuplicates];
    }
}

- (void)drawGrid {
    [[NSColor gridColor] setStroke];
    NSBezierPath *gridPath = [NSBezierPath bezierPath];
    gridPath.lineWidth = 0.5;

    // Vertical lines
    for (NSInteger x = 0; x <= _gridWidth; x++) {
        CGFloat xPos = x * _cellSize;
        [gridPath moveToPoint:NSMakePoint(xPos, 0)];
        [gridPath lineToPoint:NSMakePoint(xPos, _gridHeight * _cellSize)];
    }

    // Horizontal lines
    for (NSInteger y = 0; y <= _gridHeight; y++) {
        CGFloat yPos = y * _cellSize;
        [gridPath moveToPoint:NSMakePoint(0, yPos)];
        [gridPath lineToPoint:NSMakePoint(_gridWidth * _cellSize, yPos)];
    }

    [gridPath stroke];
}

- (void)drawNodes {
    NSDictionary *textAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:_cellSize * 0.35 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };

    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
            if (node.nodeNumber > 0) {
                NSRect cellRect = NSMakeRect(x * _cellSize + 1, y * _cellSize + 1,
                                            _cellSize - 2, _cellSize - 2);

                // Fill with node color
                NSColor *fillColor;
                if (node.red > 0 || node.green > 0 || node.blue > 0) {
                    fillColor = [NSColor colorWithRed:node.red/255.0
                                                green:node.green/255.0
                                                 blue:node.blue/255.0
                                                alpha:1.0];
                } else {
                    fillColor = [NSColor controlAccentColor];
                }
                [fillColor setFill];
                NSRectFill(cellRect);

                // Draw node number
                NSString *numStr = [NSString stringWithFormat:@"%d", node.nodeNumber];
                NSSize textSize = [numStr sizeWithAttributes:textAttrs];
                NSPoint textPoint = NSMakePoint(
                    cellRect.origin.x + (cellRect.size.width - textSize.width) / 2,
                    cellRect.origin.y + (cellRect.size.height - textSize.height) / 2
                );
                [numStr drawAtPoint:textPoint withAttributes:textAttrs];
            }
        }
    }
}

- (void)drawWiring {
    [[NSColor systemGreenColor] setStroke];
    NSBezierPath *wirePath = [NSBezierPath bezierPath];
    wirePath.lineWidth = 2.0;

    // Find max node number
    int maxNode = 0;
    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
            if (node.nodeNumber > maxNode) maxNode = node.nodeNumber;
        }
    }

    // Draw lines between consecutive nodes
    NSPoint lastPoint = NSZeroPoint;
    BOOL hasLast = NO;

    for (int n = 1; n <= maxNode; n++) {
        NSPoint pt = [self findNode:n];
        if (pt.x >= 0 && pt.y >= 0) {
            NSPoint center = NSMakePoint((pt.x + 0.5) * _cellSize, (pt.y + 0.5) * _cellSize);
            if (hasLast) {
                [wirePath moveToPoint:lastPoint];
                [wirePath lineToPoint:center];
            }
            lastPoint = center;
            hasLast = YES;
        }
    }

    [wirePath stroke];
}

- (void)drawSelection {
    [[NSColor selectedContentBackgroundColor] setStroke];
    NSBezierPath *selPath = [NSBezierPath bezierPath];
    selPath.lineWidth = 3.0;

    for (NSValue *val in _selection) {
        NSPoint pt = val.pointValue;
        NSRect cellRect = NSMakeRect(pt.x * _cellSize, pt.y * _cellSize, _cellSize, _cellSize);
        [selPath appendBezierPathWithRect:cellRect];
    }

    [selPath stroke];
}

- (void)highlightDuplicates {
    NSArray *duplicates = [self findDuplicateNodes];
    if (duplicates.count == 0) return;

    [[NSColor systemRedColor] setFill];

    for (NSNumber *nodeNum in duplicates) {
        int n = nodeNum.intValue;
        for (NSInteger y = 0; y < _gridHeight; y++) {
            for (NSInteger x = 0; x < _gridWidth; x++) {
                XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
                if (node.nodeNumber == n) {
                    NSRect cellRect = NSMakeRect(x * _cellSize + _cellSize * 0.1,
                                                y * _cellSize + _cellSize * 0.1,
                                                _cellSize * 0.8, _cellSize * 0.8);
                    NSRectFillUsingOperation(cellRect, NSCompositingOperationSourceOver);
                }
            }
        }
    }
}

#pragma mark - Selection

- (void)clearSelection {
    [_selection removeAllObjects];
    [self setNeedsDisplay:YES];
}

- (void)selectCellAtX:(NSInteger)x y:(NSInteger)y {
    [_selection addObject:[NSValue valueWithPoint:NSMakePoint(x, y)]];
    [self setNeedsDisplay:YES];
    [_delegate customModelGrid:self didSelectCellAtX:x y:y];
}

- (NSArray<NSValue *> *)selectedCells {
    return _selection.allObjects;
}

#pragma mark - Clipboard Operations

- (void)saveUndoState {
    size_t dataSize = _dataCapacity * sizeof(XLCustomNode);
    NSData *state = [NSData dataWithBytes:_nodeData length:dataSize];
    [_undoStack addObject:state];

    // Limit undo stack
    while (_undoStack.count > 100) {
        [_undoStack removeObjectAtIndex:0];
    }

    // Clear redo stack
    [_redoStack removeAllObjects];
}

- (void)deleteSelectedCells {
    if (_selection.count == 0) return;

    [self saveUndoState];

    for (NSValue *val in _selection) {
        NSPoint pt = val.pointValue;
        XLCustomNode empty = {0, 0, 0, 0};
        [self setNode:empty atX:(NSInteger)pt.x y:(NSInteger)pt.y layer:_currentLayer];
    }

    [_delegate customModelGridDidChange:self];
}

- (void)copySelection {
    if (_selection.count == 0) return;

    NSMutableData *data = [NSMutableData data];

    // Store selection bounds
    CGFloat minX = CGFLOAT_MAX, minY = CGFLOAT_MAX;
    CGFloat maxX = -1, maxY = -1;

    for (NSValue *val in _selection) {
        NSPoint pt = val.pointValue;
        minX = MIN(minX, pt.x);
        minY = MIN(minY, pt.y);
        maxX = MAX(maxX, pt.x);
        maxY = MAX(maxY, pt.y);
    }

    NSInteger w = (NSInteger)(maxX - minX + 1);
    NSInteger h = (NSInteger)(maxY - minY + 1);

    // Store dimensions
    [data appendBytes:&w length:sizeof(w)];
    [data appendBytes:&h length:sizeof(h)];

    // Store nodes
    for (NSInteger y = (NSInteger)minY; y <= (NSInteger)maxY; y++) {
        for (NSInteger x = (NSInteger)minX; x <= (NSInteger)maxX; x++) {
            XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
            [data appendBytes:&node length:sizeof(node)];
        }
    }

    _clipboard = data;
}

- (void)pasteAtSelection {
    if (!_clipboard || _selection.count == 0) return;

    [self saveUndoState];

    const void *bytes = _clipboard.bytes;
    NSInteger w, h;
    memcpy(&w, bytes, sizeof(w));
    memcpy(&h, bytes + sizeof(w), sizeof(h));

    // Paste at first selected cell
    NSPoint target = _selection.anyObject.pointValue;
    size_t offset = sizeof(w) + sizeof(h);

    for (NSInteger dy = 0; dy < h; dy++) {
        for (NSInteger dx = 0; dx < w; dx++) {
            XLCustomNode node;
            memcpy(&node, bytes + offset, sizeof(node));
            offset += sizeof(node);

            NSInteger x = (NSInteger)target.x + dx;
            NSInteger y = (NSInteger)target.y + dy;

            if (x >= 0 && x < _gridWidth && y >= 0 && y < _gridHeight) {
                [self setNode:node atX:x y:y layer:_currentLayer];
            }
        }
    }

    [_delegate customModelGridDidChange:self];
}

- (void)cutSelection {
    [self copySelection];
    [self deleteSelectedCells];
}

#pragma mark - Transform Operations

- (void)flipHorizontal {
    [self saveUndoState];

    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth / 2; x++) {
            NSInteger mirrorX = _gridWidth - 1 - x;
            XLCustomNode temp = [self nodeAtX:x y:y layer:_currentLayer];
            [self setNode:[self nodeAtX:mirrorX y:y layer:_currentLayer] atX:x y:y layer:_currentLayer];
            [self setNode:temp atX:mirrorX y:y layer:_currentLayer];
        }
    }

    [_delegate customModelGridDidChange:self];
}

- (void)flipVertical {
    [self saveUndoState];

    for (NSInteger y = 0; y < _gridHeight / 2; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            NSInteger mirrorY = _gridHeight - 1 - y;
            XLCustomNode temp = [self nodeAtX:x y:y layer:_currentLayer];
            [self setNode:[self nodeAtX:x y:mirrorY layer:_currentLayer] atX:x y:y layer:_currentLayer];
            [self setNode:temp atX:x y:mirrorY layer:_currentLayer];
        }
    }

    [_delegate customModelGridDidChange:self];
}

- (void)flipHorizontalSelected {
    if (_selection.count < 2) return;
    [self saveUndoState];

    // Find bounds
    CGFloat minX = CGFLOAT_MAX, maxX = -1;
    for (NSValue *val in _selection) {
        NSPoint pt = val.pointValue;
        minX = MIN(minX, pt.x);
        maxX = MAX(maxX, pt.x);
    }

    // Flip within selection
    NSMutableDictionary *nodeMap = [NSMutableDictionary dictionary];
    for (NSValue *val in _selection) {
        NSPoint pt = val.pointValue;
        XLCustomNode node = [self nodeAtX:(NSInteger)pt.x y:(NSInteger)pt.y layer:_currentLayer];
        NSInteger newX = (NSInteger)(minX + maxX - pt.x);
        NSString *key = [NSString stringWithFormat:@"%ld,%ld", (long)newX, (long)(NSInteger)pt.y];
        nodeMap[key] = [NSData dataWithBytes:&node length:sizeof(node)];
    }

    // Clear selection cells
    for (NSValue *val in _selection) {
        NSPoint pt = val.pointValue;
        XLCustomNode empty = {0, 0, 0, 0};
        [self setNode:empty atX:(NSInteger)pt.x y:(NSInteger)pt.y layer:_currentLayer];
    }

    // Place flipped nodes
    for (NSString *key in nodeMap) {
        NSArray *parts = [key componentsSeparatedByString:@","];
        NSInteger x = [parts[0] integerValue];
        NSInteger y = [parts[1] integerValue];
        XLCustomNode node;
        [nodeMap[key] getBytes:&node length:sizeof(node)];
        [self setNode:node atX:x y:y layer:_currentLayer];
    }

    [_delegate customModelGridDidChange:self];
}

- (void)flipVerticalSelected {
    if (_selection.count < 2) return;
    [self saveUndoState];

    CGFloat minY = CGFLOAT_MAX, maxY = -1;
    for (NSValue *val in _selection) {
        NSPoint pt = val.pointValue;
        minY = MIN(minY, pt.y);
        maxY = MAX(maxY, pt.y);
    }

    NSMutableDictionary *nodeMap = [NSMutableDictionary dictionary];
    for (NSValue *val in _selection) {
        NSPoint pt = val.pointValue;
        XLCustomNode node = [self nodeAtX:(NSInteger)pt.x y:(NSInteger)pt.y layer:_currentLayer];
        NSInteger newY = (NSInteger)(minY + maxY - pt.y);
        NSString *key = [NSString stringWithFormat:@"%ld,%ld", (long)(NSInteger)pt.x, (long)newY];
        nodeMap[key] = [NSData dataWithBytes:&node length:sizeof(node)];
    }

    for (NSValue *val in _selection) {
        NSPoint pt = val.pointValue;
        XLCustomNode empty = {0, 0, 0, 0};
        [self setNode:empty atX:(NSInteger)pt.x y:(NSInteger)pt.y layer:_currentLayer];
    }

    for (NSString *key in nodeMap) {
        NSArray *parts = [key componentsSeparatedByString:@","];
        NSInteger x = [parts[0] integerValue];
        NSInteger y = [parts[1] integerValue];
        XLCustomNode node;
        [nodeMap[key] getBytes:&node length:sizeof(node)];
        [self setNode:node atX:x y:y layer:_currentLayer];
    }

    [_delegate customModelGridDidChange:self];
}

- (void)rotate90 {
    [self saveUndoState];

    // Create temporary storage
    size_t tempSize = _gridWidth * _gridHeight * sizeof(XLCustomNode);
    XLCustomNode *temp = (XLCustomNode *)calloc(_gridWidth * _gridHeight, sizeof(XLCustomNode));

    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
            NSInteger newX = _gridHeight - 1 - y;
            NSInteger newY = x;
            if (newX >= 0 && newX < _gridHeight && newY >= 0 && newY < _gridWidth) {
                temp[newY * _gridHeight + newX] = node;
            }
        }
    }

    // Swap dimensions
    NSInteger oldWidth = _gridWidth;
    _gridWidth = _gridHeight;
    _gridHeight = oldWidth;

    // Copy back
    [self ensureCapacity];
    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            NSInteger idx = [self indexForX:x y:y layer:_currentLayer];
            if (idx >= 0 && idx < (NSInteger)_dataCapacity) {
                _nodeData[idx] = temp[y * _gridWidth + x];
            }
        }
    }

    free(temp);
    [self setNeedsDisplay:YES];
    [_delegate customModelGridDidChange:self];
}

- (void)reverseNodeNumbers {
    [self saveUndoState];

    int maxNode = 0;
    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
            if (node.nodeNumber > maxNode) maxNode = node.nodeNumber;
        }
    }

    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            NSInteger idx = [self indexForX:x y:y layer:_currentLayer];
            if (idx >= 0 && _nodeData[idx].nodeNumber > 0) {
                _nodeData[idx].nodeNumber = maxNode + 1 - _nodeData[idx].nodeNumber;
            }
        }
    }

    [self setNeedsDisplay:YES];
    [_delegate customModelGridDidChange:self];
}

- (void)shiftNodeNumbersBy:(int)amount {
    [self saveUndoState];

    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            NSInteger idx = [self indexForX:x y:y layer:_currentLayer];
            if (idx >= 0 && _nodeData[idx].nodeNumber > 0) {
                _nodeData[idx].nodeNumber = MAX(1, _nodeData[idx].nodeNumber + amount);
            }
        }
    }

    [self setNeedsDisplay:YES];
    [_delegate customModelGridDidChange:self];
}

#pragma mark - Search and Analysis

- (NSPoint)findNode:(int)nodeNumber {
    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
            if (node.nodeNumber == nodeNumber) {
                return NSMakePoint(x, y);
            }
        }
    }
    return NSMakePoint(-1, -1);
}

- (NSArray<NSNumber *> *)findDuplicateNodes {
    NSMutableDictionary<NSNumber *, NSNumber *> *counts = [NSMutableDictionary dictionary];

    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
            if (node.nodeNumber > 0) {
                NSNumber *key = @(node.nodeNumber);
                counts[key] = @(counts[key].intValue + 1);
            }
        }
    }

    NSMutableArray *duplicates = [NSMutableArray array];
    for (NSNumber *key in counts) {
        if (counts[key].intValue > 1) {
            [duplicates addObject:key];
        }
    }

    return duplicates;
}

- (void)clearAll {
    [self saveUndoState];
    memset(_nodeData, 0, _dataCapacity * sizeof(XLCustomNode));
    [self setNeedsDisplay:YES];
    [_delegate customModelGridDidChange:self];
}

- (void)compressSpace {
    [self saveUndoState];

    // Find used bounds
    NSInteger minX = _gridWidth, maxX = -1;
    NSInteger minY = _gridHeight, maxY = -1;

    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
            if (node.nodeNumber > 0) {
                minX = MIN(minX, x);
                maxX = MAX(maxX, x);
                minY = MIN(minY, y);
                maxY = MAX(maxY, y);
            }
        }
    }

    if (maxX < 0) return; // Empty grid

    // Shift all nodes
    NSInteger shiftX = minX;
    NSInteger shiftY = minY;

    for (NSInteger y = minY; y <= maxY; y++) {
        for (NSInteger x = minX; x <= maxX; x++) {
            XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
            [self setNode:(XLCustomNode){0,0,0,0} atX:x y:y layer:_currentLayer];
            [self setNode:node atX:x - shiftX y:y - shiftY layer:_currentLayer];
        }
    }

    _gridWidth = maxX - minX + 1;
    _gridHeight = maxY - minY + 1;

    [self setNeedsDisplay:YES];
    [_delegate customModelGridDidChange:self];
}

- (void)expandSpaceByFactor:(float)factor {
    [self saveUndoState];

    NSInteger newWidth = (NSInteger)(_gridWidth * factor);
    NSInteger newHeight = (NSInteger)(_gridHeight * factor);

    // Create temp storage
    size_t tempSize = newWidth * newHeight * sizeof(XLCustomNode);
    XLCustomNode *temp = (XLCustomNode *)calloc(newWidth * newHeight, sizeof(XLCustomNode));

    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
            NSInteger newX = (NSInteger)(x * factor);
            NSInteger newY = (NSInteger)(y * factor);
            temp[newY * newWidth + newX] = node;
        }
    }

    _gridWidth = newWidth;
    _gridHeight = newHeight;
    [self ensureCapacity];

    for (NSInteger y = 0; y < _gridHeight; y++) {
        for (NSInteger x = 0; x < _gridWidth; x++) {
            [self setNode:temp[y * _gridWidth + x] atX:x y:y layer:_currentLayer];
        }
    }

    free(temp);
    [self setNeedsDisplay:YES];
    [_delegate customModelGridDidChange:self];
}

#pragma mark - Import/Export

- (void)importFromString:(NSString *)data {
    [self saveUndoState];

    NSArray *rows = [data componentsSeparatedByString:@";"];

    // First pass: determine dimensions
    NSInteger maxWidth = 0;
    NSInteger height = rows.count;

    for (NSString *row in rows) {
        NSArray *cells = [row componentsSeparatedByString:@","];
        maxWidth = MAX(maxWidth, (NSInteger)cells.count);
    }

    _gridWidth = maxWidth;
    _gridHeight = height;
    [self ensureCapacity];

    // Clear and fill
    memset(_nodeData, 0, _dataCapacity * sizeof(XLCustomNode));

    NSInteger y = 0;
    for (NSString *row in rows) {
        NSArray *cells = [row componentsSeparatedByString:@","];
        NSInteger x = 0;
        for (NSString *cell in cells) {
            NSString *trimmed = [cell stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            int nodeNum = trimmed.intValue;
            if (nodeNum > 0) {
                XLCustomNode node = {nodeNum, 255, 255, 255};
                [self setNode:node atX:x y:y layer:_currentLayer];
            }
            x++;
        }
        y++;
    }

    [self setNeedsDisplay:YES];
    [_delegate customModelGridDidChange:self];
}

- (NSString *)exportToString {
    NSMutableString *result = [NSMutableString string];

    for (NSInteger y = 0; y < _gridHeight; y++) {
        NSMutableArray *rowCells = [NSMutableArray array];
        for (NSInteger x = 0; x < _gridWidth; x++) {
            XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
            if (node.nodeNumber > 0) {
                [rowCells addObject:[NSString stringWithFormat:@"%d", node.nodeNumber]];
            } else {
                [rowCells addObject:@""];
            }
        }
        [result appendString:[rowCells componentsJoinedByString:@","]];
        if (y < _gridHeight - 1) {
            [result appendString:@";"];
        }
    }

    return result;
}

#pragma mark - Undo/Redo

- (void)undo {
    if (_undoStack.count == 0) return;

    // Save current state to redo
    size_t dataSize = _dataCapacity * sizeof(XLCustomNode);
    [_redoStack addObject:[NSData dataWithBytes:_nodeData length:dataSize]];

    // Restore from undo
    NSData *state = _undoStack.lastObject;
    [_undoStack removeLastObject];
    memcpy(_nodeData, state.bytes, MIN(state.length, dataSize));

    [self setNeedsDisplay:YES];
    [_delegate customModelGridDidChange:self];
}

- (void)redo {
    if (_redoStack.count == 0) return;

    size_t dataSize = _dataCapacity * sizeof(XLCustomNode);
    [_undoStack addObject:[NSData dataWithBytes:_nodeData length:dataSize]];

    NSData *state = _redoStack.lastObject;
    [_redoStack removeLastObject];
    memcpy(_nodeData, state.bytes, MIN(state.length, dataSize));

    [self setNeedsDisplay:YES];
    [_delegate customModelGridDidChange:self];
}

- (BOOL)canUndo { return _undoStack.count > 0; }
- (BOOL)canRedo { return _redoStack.count > 0; }

#pragma mark - Zoom

- (void)zoomIn {
    _cellSize = MIN(_cellSize + 5, kMaxCellSize);
    [self setNeedsDisplay:YES];
}

- (void)zoomOut {
    _cellSize = MAX(_cellSize - 5, kMinCellSize);
    [self setNeedsDisplay:YES];
}

- (void)zoomToFit {
    NSSize viewSize = self.superview.bounds.size;
    CGFloat cellW = viewSize.width / _gridWidth;
    CGFloat cellH = viewSize.height / _gridHeight;
    _cellSize = MAX(kMinCellSize, MIN(kMaxCellSize, MIN(cellW, cellH)));
    [self setNeedsDisplay:YES];
}

#pragma mark - Mouse Handling

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger x = (NSInteger)(point.x / _cellSize);
    NSInteger y = (NSInteger)(point.y / _cellSize);

    if (x < 0 || x >= _gridWidth || y < 0 || y >= _gridHeight) return;

    BOOL shiftDown = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    BOOL cmdDown = (event.modifierFlags & NSEventModifierFlagCommand) != 0;

    if (!shiftDown && !cmdDown) {
        [_selection removeAllObjects];
    }

    [self selectCellAtX:x y:y];

    if (event.clickCount == 2) {
        // Double-click: edit node
        XLCustomNode node = [self nodeAtX:x y:y layer:_currentLayer];
        if (node.nodeNumber == 0 && _autoIncrement) {
            // Place next node
            [self saveUndoState];
            node.nodeNumber = _nextNodeNumber++;
            node.red = 255;
            node.green = 255;
            node.blue = 255;
            [self setNode:node atX:x y:y layer:_currentLayer];
            [_delegate customModelGridDidChange:self];
        }
    }

    _isDragging = YES;
    _dragStart = point;
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_isDragging) return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger x = (NSInteger)(point.x / _cellSize);
    NSInteger y = (NSInteger)(point.y / _cellSize);

    if (x >= 0 && x < _gridWidth && y >= 0 && y < _gridHeight) {
        [self selectCellAtX:x y:y];
    }
}

- (void)mouseUp:(NSEvent *)event {
    _isDragging = NO;
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 51 || event.keyCode == 117) { // Delete/Backspace
        [self deleteSelectedCells];
    } else if (event.modifierFlags & NSEventModifierFlagCommand) {
        if ([event.characters isEqualToString:@"z"]) {
            if (event.modifierFlags & NSEventModifierFlagShift) {
                [self redo];
            } else {
                [self undo];
            }
        } else if ([event.characters isEqualToString:@"c"]) {
            [self copySelection];
        } else if ([event.characters isEqualToString:@"v"]) {
            [self pasteAtSelection];
        } else if ([event.characters isEqualToString:@"x"]) {
            [self cutSelection];
        } else if ([event.characters isEqualToString:@"a"]) {
            // Select all
            [_selection removeAllObjects];
            for (NSInteger y = 0; y < _gridHeight; y++) {
                for (NSInteger x = 0; x < _gridWidth; x++) {
                    [_selection addObject:[NSValue valueWithPoint:NSMakePoint(x, y)]];
                }
            }
            [self setNeedsDisplay:YES];
        }
    } else {
        [super keyDown:event];
    }
}

- (BOOL)acceptsFirstResponder { return YES; }

@end

#pragma mark - XLCustomModel3DPreview

@implementation XLCustomModel3DPreview {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLBuffer> _vertexBuffer;
    NSInteger _nodeCount;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _device = MTLCreateSystemDefaultDevice();
        self.device = _device;
        self.clearColor = MTLClearColorMake(0.1, 0.1, 0.1, 1.0);

        _commandQueue = [_device newCommandQueue];
        _rotationX = 0;
        _rotationY = 0;
        _zoom = 1.0;
        _highlightedNode = -1;
        _showWiring = NO;

        [self setupPipeline];
    }
    return self;
}

- (void)setupPipeline {
    // Basic pipeline for rendering points
    // In a full implementation, this would use actual Metal shaders
    // For now, this is a placeholder that can be filled in
}

- (void)setNodePositions:(const XLCustomNode *)nodes
                   width:(NSInteger)width
                  height:(NSInteger)height
                   depth:(NSInteger)depth {
    _nodeCount = 0;

    // Count actual nodes
    for (NSInteger z = 0; z < depth; z++) {
        for (NSInteger y = 0; y < height; y++) {
            for (NSInteger x = 0; x < width; x++) {
                NSInteger idx = z * width * height + y * width + x;
                if (nodes[idx].nodeNumber > 0) {
                    _nodeCount++;
                }
            }
        }
    }

    [self setNeedsDisplay:YES];
}

- (void)setNodeColors:(const uint8_t *)rgbData nodeCount:(NSInteger)count {
    // Update colors from live output
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    // Placeholder rendering - in full implementation would use Metal
    [[NSColor darkGrayColor] setFill];
    NSRectFill(dirtyRect);

    // Draw info text
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName: [NSColor lightGrayColor]
    };
    [@"3D Preview" drawAtPoint:NSMakePoint(10, dirtyRect.size.height - 25) withAttributes:attrs];
    [[NSString stringWithFormat:@"Nodes: %ld", (long)_nodeCount] drawAtPoint:NSMakePoint(10, dirtyRect.size.height - 40) withAttributes:attrs];
}

@end

#pragma mark - XLCustomModelLayerTabView

@implementation XLCustomModelLayerTabView {
    NSMutableArray<NSButton *> *_layerButtons;
    NSButton *_addButton;
    NSButton *_removeButton;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _layerCount = 1;
        _selectedLayer = 0;
        _layerButtons = [NSMutableArray array];

        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // Will be populated with layer tabs
    [self rebuildButtons];
}

- (void)rebuildButtons {
    for (NSButton *btn in _layerButtons) {
        [btn removeFromSuperview];
    }
    [_layerButtons removeAllObjects];

    CGFloat x = 0;
    CGFloat buttonWidth = 60;
    CGFloat buttonHeight = 24;

    for (NSInteger i = 0; i < _layerCount; i++) {
        NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(x, 0, buttonWidth, buttonHeight)];
        btn.title = [NSString stringWithFormat:@"Layer %ld", (long)(i + 1)];
        btn.bezelStyle = NSBezelStyleRounded;
        btn.tag = i;
        [btn setTarget:self];
        [btn setAction:@selector(layerButtonClicked:)];

        if (i == _selectedLayer) {
            btn.state = NSControlStateValueOn;
        }

        [self addSubview:btn];
        [_layerButtons addObject:btn];
        x += buttonWidth + 4;
    }

    // Add/remove buttons
    _addButton = [[NSButton alloc] initWithFrame:NSMakeRect(x, 0, 30, buttonHeight)];
    _addButton.title = @"+";
    _addButton.bezelStyle = NSBezelStyleRounded;
    [_addButton setTarget:self];
    [_addButton setAction:@selector(addLayerClicked:)];
    [self addSubview:_addButton];
    x += 34;

    _removeButton = [[NSButton alloc] initWithFrame:NSMakeRect(x, 0, 30, buttonHeight)];
    _removeButton.title = @"-";
    _removeButton.bezelStyle = NSBezelStyleRounded;
    _removeButton.enabled = _layerCount > 1;
    [_removeButton setTarget:self];
    [_removeButton setAction:@selector(removeLayerClicked:)];
    [self addSubview:_removeButton];
}

- (void)layerButtonClicked:(NSButton *)sender {
    _selectedLayer = sender.tag;
    for (NSButton *btn in _layerButtons) {
        btn.state = (btn.tag == _selectedLayer) ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [_delegate layerTabView:self didSelectLayer:_selectedLayer];
}

- (void)addLayerClicked:(id)sender {
    _layerCount++;
    [self rebuildButtons];
    [_delegate layerTabViewDidAddLayer:self];
}

- (void)removeLayerClicked:(id)sender {
    if (_layerCount <= 1) return;
    _layerCount--;
    if (_selectedLayer >= _layerCount) {
        _selectedLayer = _layerCount - 1;
    }
    [self rebuildButtons];
    [_delegate layerTabViewDidRemoveLayer:self];
}

- (void)addLayer {
    [self addLayerClicked:nil];
}

- (void)removeCurrentLayer {
    [self removeLayerClicked:nil];
}

- (void)copyLayer:(NSInteger)from to:(NSInteger)to {
    // Delegate handles the actual copy
}

@end

#pragma mark - XLCustomModelWindow

@interface XLCustomModelWindow () <XLCustomModelGridDelegate, XLCustomModelLayerDelegate>

@property (nonatomic, copy) NSString *modelName;
@property (nonatomic, strong) XLCustomModelGridView *gridView;
@property (nonatomic, strong) XLCustomModel3DPreview *previewView;
@property (nonatomic, strong) XLCustomModelLayerTabView *layerTabs;

@property (nonatomic, strong) NSTextField *widthField;
@property (nonatomic, strong) NSTextField *heightField;
@property (nonatomic, strong) NSTextField *nextNodeField;

@property (nonatomic, strong) NSButton *autoIncrementCheckbox;
@property (nonatomic, strong) NSButton *showWiringCheckbox;
@property (nonatomic, strong) NSButton *showDuplicatesCheckbox;

@property (nonatomic, strong) NSScrollView *gridScrollView;
@property (nonatomic, strong) NSSlider *backgroundSlider;
@property (nonatomic, strong) NSImageView *backgroundImageView;

@property (nonatomic, copy) XLCustomModelCompletion completion;
@property (nonatomic, assign) BOOL isNewModel;

@end

@implementation XLCustomModelWindow

- (instancetype)initWithModelName:(NSString *)modelName {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowWidth, kWindowHeight)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = [NSString stringWithFormat:@"Custom Model: %@", modelName];
    window.minSize = NSMakeSize(800, 600);

    self = [super initWithWindow:window];
    if (self) {
        _modelName = [modelName copy];
        _isNewModel = NO;
        _hasChanges = NO;

        [self buildUI];
    }
    return self;
}

- (instancetype)initForNewModel {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowWidth, kWindowHeight)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"New Custom Model";
    window.minSize = NSMakeSize(800, 600);

    self = [super initWithWindow:window];
    if (self) {
        _modelName = @"Custom";
        _isNewModel = YES;
        _hasChanges = NO;

        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSView *contentView = self.window.contentView;

    // Create split view
    NSSplitView *splitView = [[NSSplitView alloc] initWithFrame:contentView.bounds];
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    splitView.vertical = YES;
    splitView.dividerStyle = NSSplitViewDividerStyleThin;
    [contentView addSubview:splitView];

    // Left panel: Grid editor
    NSView *leftPanel = [[NSView alloc] initWithFrame:NSZeroRect];
    [splitView addArrangedSubview:leftPanel];

    // Right panel: Preview and controls
    NSView *rightPanel = [[NSView alloc] initWithFrame:NSZeroRect];
    [splitView addArrangedSubview:rightPanel];

    [NSLayoutConstraint activateConstraints:@[
        [splitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [splitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [splitView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [splitView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
    ]];

    [self buildLeftPanel:leftPanel];
    [self buildRightPanel:rightPanel];
}

- (void)buildLeftPanel:(NSView *)panel {
    // Toolbar
    NSStackView *toolbar = [[NSStackView alloc] init];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 8;
    [panel addSubview:toolbar];

    // Dimensions
    NSTextField *widthLabel = [NSTextField labelWithString:@"Width:"];
    _widthField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 50, 22)];
    _widthField.stringValue = @"10";
    [_widthField setTarget:self];
    [_widthField setAction:@selector(dimensionsChanged:)];

    NSTextField *heightLabel = [NSTextField labelWithString:@"Height:"];
    _heightField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 50, 22)];
    _heightField.stringValue = @"10";
    [_heightField setTarget:self];
    [_heightField setAction:@selector(dimensionsChanged:)];

    [toolbar addArrangedSubview:widthLabel];
    [toolbar addArrangedSubview:_widthField];
    [toolbar addArrangedSubview:heightLabel];
    [toolbar addArrangedSubview:_heightField];

    // Zoom buttons
    NSButton *zoomIn = [NSButton buttonWithTitle:@"+" target:self action:@selector(zoomInClicked:)];
    NSButton *zoomOut = [NSButton buttonWithTitle:@"-" target:self action:@selector(zoomOutClicked:)];
    [toolbar addArrangedSubview:zoomOut];
    [toolbar addArrangedSubview:zoomIn];

    // Layer tabs
    _layerTabs = [[XLCustomModelLayerTabView alloc] initWithFrame:NSMakeRect(0, 0, 400, 28)];
    _layerTabs.translatesAutoresizingMaskIntoConstraints = NO;
    _layerTabs.delegate = self;
    [panel addSubview:_layerTabs];

    // Grid view in scroll view
    _gridScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _gridScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _gridScrollView.hasVerticalScroller = YES;
    _gridScrollView.hasHorizontalScroller = YES;
    _gridScrollView.borderType = NSBezelBorder;

    _gridView = [[XLCustomModelGridView alloc] initWithFrame:NSMakeRect(0, 0, 500, 500)];
    _gridView.delegate = self;
    _gridScrollView.documentView = _gridView;

    [panel addSubview:_gridScrollView];

    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:panel.topAnchor constant:8],
        [toolbar.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
        [toolbar.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],
        [toolbar.heightAnchor constraintEqualToConstant:30],

        [_layerTabs.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:8],
        [_layerTabs.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
        [_layerTabs.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],
        [_layerTabs.heightAnchor constraintEqualToConstant:28],

        [_gridScrollView.topAnchor constraintEqualToAnchor:_layerTabs.bottomAnchor constant:8],
        [_gridScrollView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
        [_gridScrollView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],
        [_gridScrollView.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-8],
    ]];
}

- (void)buildRightPanel:(NSView *)panel {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 12;
    stack.alignment = NSLayoutAttributeLeading;
    [panel addSubview:stack];

    // 3D Preview
    _previewView = [[XLCustomModel3DPreview alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    _previewView.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:_previewView];

    [NSLayoutConstraint activateConstraints:@[
        [_previewView.heightAnchor constraintEqualToConstant:200],
        [_previewView.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];

    // Node numbering controls
    NSTextField *nextLabel = [NSTextField labelWithString:@"Next Node Number:"];
    _nextNodeField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nextNodeField.stringValue = @"1";
    _nextNodeField.translatesAutoresizingMaskIntoConstraints = NO;
    [_nextNodeField.widthAnchor constraintEqualToConstant:60].active = YES;
    [_nextNodeField setTarget:self];
    [_nextNodeField setAction:@selector(nextNodeChanged:)];

    NSStackView *nodeRow = [NSStackView stackViewWithViews:@[nextLabel, _nextNodeField]];
    nodeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    [stack addArrangedSubview:nodeRow];

    // Checkboxes
    _autoIncrementCheckbox = [NSButton checkboxWithTitle:@"Auto-increment node numbers"
                                                  target:self action:@selector(optionChanged:)];
    _autoIncrementCheckbox.state = NSControlStateValueOn;
    [stack addArrangedSubview:_autoIncrementCheckbox];

    _showWiringCheckbox = [NSButton checkboxWithTitle:@"Show wiring"
                                               target:self action:@selector(optionChanged:)];
    [stack addArrangedSubview:_showWiringCheckbox];

    _showDuplicatesCheckbox = [NSButton checkboxWithTitle:@"Highlight duplicates"
                                                   target:self action:@selector(optionChanged:)];
    [stack addArrangedSubview:_showDuplicatesCheckbox];

    // Background image controls
    NSTextField *bgLabel = [NSTextField labelWithString:@"Background Image:"];
    [stack addArrangedSubview:bgLabel];

    NSButton *loadBgButton = [NSButton buttonWithTitle:@"Load Image..." target:self action:@selector(loadBackgroundClicked:)];
    NSButton *clearBgButton = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clearBackgroundClicked:)];
    NSStackView *bgRow = [NSStackView stackViewWithViews:@[loadBgButton, clearBgButton]];
    [stack addArrangedSubview:bgRow];

    NSTextField *alphaLabel = [NSTextField labelWithString:@"Background Opacity:"];
    _backgroundSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _backgroundSlider.minValue = 0;
    _backgroundSlider.maxValue = 100;
    _backgroundSlider.integerValue = 50;
    [_backgroundSlider setTarget:self];
    [_backgroundSlider setAction:@selector(backgroundAlphaChanged:)];

    NSStackView *alphaRow = [NSStackView stackViewWithViews:@[alphaLabel, _backgroundSlider]];
    [stack addArrangedSubview:alphaRow];

    // Operation buttons
    NSTextField *opsLabel = [NSTextField labelWithString:@"Operations:"];
    opsLabel.font = [NSFont boldSystemFontOfSize:12];
    [stack addArrangedSubview:opsLabel];

    NSButton *flipH = [NSButton buttonWithTitle:@"Flip Horizontal" target:self action:@selector(flipHClicked:)];
    NSButton *flipV = [NSButton buttonWithTitle:@"Flip Vertical" target:self action:@selector(flipVClicked:)];
    NSButton *rotate = [NSButton buttonWithTitle:@"Rotate 90" target:self action:@selector(rotateClicked:)];
    NSButton *reverse = [NSButton buttonWithTitle:@"Reverse Numbers" target:self action:@selector(reverseClicked:)];
    NSButton *compress = [NSButton buttonWithTitle:@"Compress Space" target:self action:@selector(compressClicked:)];

    [stack addArrangedSubview:flipH];
    [stack addArrangedSubview:flipV];
    [stack addArrangedSubview:rotate];
    [stack addArrangedSubview:reverse];
    [stack addArrangedSubview:compress];

    // Bottom buttons
    NSView *spacer = [[NSView alloc] init];
    [stack addArrangedSubview:spacer];

    NSButton *cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelClicked:)];
    cancelButton.keyEquivalent = @"\033";

    NSButton *okButton = [NSButton buttonWithTitle:@"OK" target:self action:@selector(okClicked:)];
    okButton.keyEquivalent = @"\r";

    NSStackView *buttonRow = [NSStackView stackViewWithViews:@[cancelButton, okButton]];
    buttonRow.spacing = 12;
    [stack addArrangedSubview:buttonRow];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-12],
    ]];
}

- (void)showWithCompletion:(XLCustomModelCompletion)completion {
    _completion = completion;
    [self.window center];
    [self showWindow:nil];
}

- (NSDictionary<NSString *, id> *)modelData {
    return @{
        @"CustomModel": [_gridView exportToString],
        @"parm1": @(_gridView.gridWidth),
        @"parm2": @(_gridView.gridHeight),
    };
}

#pragma mark - Actions

- (void)dimensionsChanged:(id)sender {
    _gridView.gridWidth = _widthField.integerValue;
    _gridView.gridHeight = _heightField.integerValue;
    [_gridView setNeedsDisplay:YES];
    _hasChanges = YES;
}

- (void)zoomInClicked:(id)sender {
    [_gridView zoomIn];
}

- (void)zoomOutClicked:(id)sender {
    [_gridView zoomOut];
}

- (void)nextNodeChanged:(id)sender {
    _gridView.nextNodeNumber = _nextNodeField.intValue;
}

- (void)optionChanged:(id)sender {
    _gridView.autoIncrement = (_autoIncrementCheckbox.state == NSControlStateValueOn);
    _gridView.showWiring = (_showWiringCheckbox.state == NSControlStateValueOn);
    _gridView.showDuplicates = (_showDuplicatesCheckbox.state == NSControlStateValueOn);
    [_gridView setNeedsDisplay:YES];
}

- (void)loadBackgroundClicked:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithIdentifier:@"public.image"]];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            NSImage *image = [[NSImage alloc] initWithContentsOfURL:panel.URL];
            self.gridView.backgroundImage = image;
            [self.gridView setNeedsDisplay:YES];
        }
    }];
}

- (void)clearBackgroundClicked:(id)sender {
    _gridView.backgroundImage = nil;
    [_gridView setNeedsDisplay:YES];
}

- (void)backgroundAlphaChanged:(id)sender {
    _gridView.backgroundAlpha = _backgroundSlider.floatValue / 100.0;
    [_gridView setNeedsDisplay:YES];
}

- (void)flipHClicked:(id)sender {
    [_gridView flipHorizontal];
    _hasChanges = YES;
}

- (void)flipVClicked:(id)sender {
    [_gridView flipVertical];
    _hasChanges = YES;
}

- (void)rotateClicked:(id)sender {
    [_gridView rotate90];
    _hasChanges = YES;
}

- (void)reverseClicked:(id)sender {
    [_gridView reverseNodeNumbers];
    _hasChanges = YES;
}

- (void)compressClicked:(id)sender {
    [_gridView compressSpace];
    _hasChanges = YES;
}

- (void)cancelClicked:(id)sender {
    [self.window close];
    if (_completion) {
        _completion(NO);
    }
}

- (void)okClicked:(id)sender {
    [self.window close];
    if (_completion) {
        _completion(_hasChanges);
    }
}

#pragma mark - XLCustomModelGridDelegate

- (void)customModelGridDidChange:(XLCustomModelGridView *)grid {
    _hasChanges = YES;
    _nextNodeField.intValue = grid.nextNodeNumber;
}

- (void)customModelGrid:(XLCustomModelGridView *)grid didSelectCellAtX:(NSInteger)x y:(NSInteger)y {
    // Could update status bar
}

- (void)customModelGrid:(XLCustomModelGridView *)grid didHoverOverCellAtX:(NSInteger)x y:(NSInteger)y {
    // Could update status bar
}

#pragma mark - XLCustomModelLayerDelegate

- (void)layerTabView:(XLCustomModelLayerTabView *)tabView didSelectLayer:(NSInteger)layer {
    _gridView.currentLayer = layer;
    [_gridView setNeedsDisplay:YES];
}

- (void)layerTabViewDidAddLayer:(XLCustomModelLayerTabView *)tabView {
    _hasChanges = YES;
}

- (void)layerTabViewDidRemoveLayer:(XLCustomModelLayerTabView *)tabView {
    _hasChanges = YES;
}

@end
