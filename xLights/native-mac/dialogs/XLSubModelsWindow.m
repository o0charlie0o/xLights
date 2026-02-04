/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLSubModelsWindow.h"
#import "../XLEngineBridge.h"

static const CGFloat kWindowWidth = 1000.0;
static const CGFloat kWindowHeight = 700.0;

/// Pasteboard type for submodel copy/paste
NSString * const XLSubModelPasteboardType = @"com.xlights.submodel";

#pragma mark - XLNodeSelectionView

@interface XLNodeSelectionView () {
    float *_nodeX;
    float *_nodeY;
    NSInteger _capacity;
}
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) NSPoint dragStart;
@property (nonatomic, assign) NSPoint dragEnd;
@property (nonatomic, assign) NSInteger hoveredNodeIndex;
@property (nonatomic, strong) NSTextField *nodeInfoLabel;
@end

@implementation XLNodeSelectionView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _nodeCount = 0;
        _capacity = 0;
        _nodeX = NULL;
        _nodeY = NULL;
        _selectedNodes = [[NSMutableIndexSet alloc] init];
        _highlightedNodes = [[NSMutableIndexSet alloc] init];
        _selectionColor = [NSColor systemYellowColor];
        _highlightColor = [NSColor systemOrangeColor];
        _selectionEnabled = YES;
        _showNodeNumbers = YES;
        _hoveredNodeIndex = -1;

        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor controlBackgroundColor] CGColor];
        self.layer.borderWidth = 1;
        self.layer.borderColor = [[NSColor separatorColor] CGColor];
        self.layer.cornerRadius = 4;

        // Node info label for hover display
        _nodeInfoLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _nodeInfoLabel.editable = NO;
        _nodeInfoLabel.bordered = NO;
        _nodeInfoLabel.drawsBackground = YES;
        _nodeInfoLabel.backgroundColor = [NSColor colorWithWhite:0.2 alpha:0.9];
        _nodeInfoLabel.textColor = [NSColor whiteColor];
        _nodeInfoLabel.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightMedium];
        _nodeInfoLabel.alignment = NSTextAlignmentCenter;
        _nodeInfoLabel.hidden = YES;
        [self addSubview:_nodeInfoLabel];
    }
    return self;
}

- (void)dealloc {
    if (_nodeX) free(_nodeX);
    if (_nodeY) free(_nodeY);
}

- (float *)nodePositionsX { return _nodeX; }
- (float *)nodePositionsY { return _nodeY; }

- (void)setNodeCount:(NSInteger)count
          positionsX:(const float *)x
          positionsY:(const float *)y {
    if (count > _capacity) {
        if (_nodeX) free(_nodeX);
        if (_nodeY) free(_nodeY);
        _capacity = count * 2;
        _nodeX = (float *)malloc(_capacity * sizeof(float));
        _nodeY = (float *)malloc(_capacity * sizeof(float));
    }

    _nodeCount = count;
    if (count > 0) {
        memcpy(_nodeX, x, count * sizeof(float));
        memcpy(_nodeY, y, count * sizeof(float));
    }

    [self setNeedsDisplay:YES];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                options:(NSTrackingMouseMoved |
                                                        NSTrackingActiveInKeyWindow)
                                                  owner:self
                                               userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;
    CGFloat margin = 10;
    NSRect drawRect = NSInsetRect(bounds, margin, margin);

    // Draw background with gradient for depth
    NSGradient *bgGradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:0.15 alpha:1.0]
                                                           endingColor:[NSColor colorWithWhite:0.1 alpha:1.0]];
    [bgGradient drawInRect:bounds angle:90];

    // Draw subtle grid
    [[NSColor colorWithWhite:0.2 alpha:0.3] setStroke];
    for (int i = 0; i <= 10; i++) {
        CGFloat x = drawRect.origin.x + (i / 10.0) * drawRect.size.width;
        CGFloat y = drawRect.origin.y + (i / 10.0) * drawRect.size.height;
        NSBezierPath *gridLine = [NSBezierPath bezierPath];
        [gridLine moveToPoint:NSMakePoint(x, drawRect.origin.y)];
        [gridLine lineToPoint:NSMakePoint(x, NSMaxY(drawRect))];
        [gridLine setLineWidth:0.5];
        [gridLine stroke];
        [gridLine removeAllPoints];
        [gridLine moveToPoint:NSMakePoint(drawRect.origin.x, y)];
        [gridLine lineToPoint:NSMakePoint(NSMaxX(drawRect), y)];
        [gridLine stroke];
    }

    // Calculate node size based on count
    CGFloat nodeSize = MAX(4, MIN(12, bounds.size.width / MAX(1, sqrt(_nodeCount))));

    // First pass: draw unselected nodes
    for (NSInteger i = 0; i < _nodeCount; i++) {
        if ([_selectedNodes containsIndex:i] || [_highlightedNodes containsIndex:i] || i == _hoveredNodeIndex) {
            continue;
        }

        CGFloat x = drawRect.origin.x + _nodeX[i] * drawRect.size.width;
        CGFloat y = drawRect.origin.y + _nodeY[i] * drawRect.size.height;
        NSRect nodeRect = NSMakeRect(x - nodeSize/2, y - nodeSize/2, nodeSize, nodeSize);

        [[NSColor colorWithWhite:0.5 alpha:0.7] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:nodeRect] fill];
    }

    // Second pass: draw highlighted nodes (preview mode)
    for (NSInteger i = 0; i < _nodeCount; i++) {
        if (![_highlightedNodes containsIndex:i] || [_selectedNodes containsIndex:i]) continue;

        CGFloat x = drawRect.origin.x + _nodeX[i] * drawRect.size.width;
        CGFloat y = drawRect.origin.y + _nodeY[i] * drawRect.size.height;
        CGFloat highlightSize = nodeSize * 1.2;
        NSRect nodeRect = NSMakeRect(x - highlightSize/2, y - highlightSize/2, highlightSize, highlightSize);

        // Draw glow
        NSShadow *glow = [[NSShadow alloc] init];
        glow.shadowColor = [_highlightColor colorWithAlphaComponent:0.5];
        glow.shadowBlurRadius = 4;
        glow.shadowOffset = NSZeroSize;
        [NSGraphicsContext saveGraphicsState];
        [glow set];
        [_highlightColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:nodeRect] fill];
        [NSGraphicsContext restoreGraphicsState];
    }

    // Third pass: draw selected nodes
    for (NSInteger i = 0; i < _nodeCount; i++) {
        if (![_selectedNodes containsIndex:i]) continue;

        CGFloat x = drawRect.origin.x + _nodeX[i] * drawRect.size.width;
        CGFloat y = drawRect.origin.y + _nodeY[i] * drawRect.size.height;
        CGFloat selectedSize = nodeSize * 1.3;
        NSRect nodeRect = NSMakeRect(x - selectedSize/2, y - selectedSize/2, selectedSize, selectedSize);

        // Draw glow
        NSShadow *glow = [[NSShadow alloc] init];
        glow.shadowColor = [_selectionColor colorWithAlphaComponent:0.6];
        glow.shadowBlurRadius = 6;
        glow.shadowOffset = NSZeroSize;
        [NSGraphicsContext saveGraphicsState];
        [glow set];
        [_selectionColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:nodeRect] fill];
        [NSGraphicsContext restoreGraphicsState];
    }

    // Fourth pass: draw hovered node
    if (_hoveredNodeIndex >= 0 && _hoveredNodeIndex < _nodeCount) {
        CGFloat x = drawRect.origin.x + _nodeX[_hoveredNodeIndex] * drawRect.size.width;
        CGFloat y = drawRect.origin.y + _nodeY[_hoveredNodeIndex] * drawRect.size.height;
        CGFloat hoverSize = nodeSize * 1.5;
        NSRect nodeRect = NSMakeRect(x - hoverSize/2, y - hoverSize/2, hoverSize, hoverSize);

        // Draw hover ring
        [[NSColor whiteColor] setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(nodeRect, -2, -2)];
        ring.lineWidth = 2;
        [ring stroke];

        // Fill with selection or highlight color
        if ([_selectedNodes containsIndex:_hoveredNodeIndex]) {
            [_selectionColor setFill];
        } else {
            [[NSColor systemCyanColor] setFill];
        }
        [[NSBezierPath bezierPathWithOvalInRect:nodeRect] fill];
    }

    // Draw selection rectangle if dragging
    if (_isDragging) {
        [[NSColor selectedContentBackgroundColor] setFill];
        NSRect selRect = NSMakeRect(MIN(_dragStart.x, _dragEnd.x),
                                    MIN(_dragStart.y, _dragEnd.y),
                                    fabs(_dragEnd.x - _dragStart.x),
                                    fabs(_dragEnd.y - _dragStart.y));
        NSBezierPath *rectPath = [NSBezierPath bezierPathWithRect:selRect];

        // Fill with semi-transparent
        [[NSColor colorWithCalibratedRed:0.2 green:0.5 blue:1.0 alpha:0.15] setFill];
        [rectPath fill];

        // Stroke with dashed line
        [[NSColor selectedContentBackgroundColor] setStroke];
        rectPath.lineWidth = 1;
        CGFloat pattern[] = {4, 4};
        [rectPath setLineDash:pattern count:2 phase:0];
        [rectPath stroke];
    }

    // Draw selection count
    if (_selectedNodes.count > 0) {
        NSString *countStr = [NSString stringWithFormat:@"%ld selected", (long)_selectedNodes.count];
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10],
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
        };
        NSSize textSize = [countStr sizeWithAttributes:attrs];
        [countStr drawAtPoint:NSMakePoint(bounds.size.width - textSize.width - 5, 5) withAttributes:attrs];
    }
}

- (void)clearSelection {
    [_selectedNodes removeAllIndexes];
    [self setNeedsDisplay:YES];
    [_delegate nodeSelectionViewDidChangeSelection:self];
}

- (void)clearHighlights {
    [_highlightedNodes removeAllIndexes];
    [self setNeedsDisplay:YES];
}

- (void)highlightNodesFromRangeString:(NSString *)rangeString {
    [_highlightedNodes removeAllIndexes];

    if (!rangeString || rangeString.length == 0) {
        [self setNeedsDisplay:YES];
        return;
    }

    NSArray *parts = [rangeString componentsSeparatedByString:@","];
    for (NSString *part in parts) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed containsString:@"-"]) {
            NSArray *range = [trimmed componentsSeparatedByString:@"-"];
            if (range.count == 2) {
                NSInteger start = [range[0] integerValue] - 1;
                NSInteger end = [range[1] integerValue] - 1;
                for (NSInteger i = MIN(start, end); i <= MAX(start, end); i++) {
                    if (i >= 0 && i < _nodeCount) {
                        [_highlightedNodes addIndex:i];
                    }
                }
            }
        } else {
            NSInteger idx = [trimmed integerValue] - 1;
            if (idx >= 0 && idx < _nodeCount) {
                [_highlightedNodes addIndex:idx];
            }
        }
    }

    [self setNeedsDisplay:YES];
}

- (NSInteger)nodeAtPoint:(NSPoint)point {
    NSRect bounds = self.bounds;
    CGFloat margin = 10;
    NSRect drawRect = NSInsetRect(bounds, margin, margin);
    CGFloat nodeSize = MAX(4, MIN(12, bounds.size.width / MAX(1, sqrt(_nodeCount))));
    CGFloat hitRadius = nodeSize + 4; // Slightly larger hit area

    for (NSInteger i = 0; i < _nodeCount; i++) {
        CGFloat x = drawRect.origin.x + _nodeX[i] * drawRect.size.width;
        CGFloat y = drawRect.origin.y + _nodeY[i] * drawRect.size.height;

        CGFloat dx = point.x - x;
        CGFloat dy = point.y - y;
        if (sqrt(dx*dx + dy*dy) < hitRadius) {
            return i;
        }
    }

    return -1;
}

- (void)scrollToNode:(NSInteger)nodeIndex {
    if (nodeIndex < 0 || nodeIndex >= _nodeCount) return;

    NSRect bounds = self.bounds;
    CGFloat margin = 10;
    NSRect drawRect = NSInsetRect(bounds, margin, margin);

    CGFloat x = drawRect.origin.x + _nodeX[nodeIndex] * drawRect.size.width;
    CGFloat y = drawRect.origin.y + _nodeY[nodeIndex] * drawRect.size.height;

    NSRect visibleRect = NSMakeRect(x - 50, y - 50, 100, 100);
    [self scrollRectToVisible:visibleRect];
}

- (void)selectNodesFromRangeString:(NSString *)rangeString {
    [_selectedNodes removeAllIndexes];

    if (!rangeString || rangeString.length == 0) return;

    NSArray *parts = [rangeString componentsSeparatedByString:@","];
    for (NSString *part in parts) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed containsString:@"-"]) {
            NSArray *range = [trimmed componentsSeparatedByString:@"-"];
            if (range.count == 2) {
                NSInteger start = [range[0] integerValue] - 1; // Convert to 0-indexed
                NSInteger end = [range[1] integerValue] - 1;
                for (NSInteger i = MIN(start, end); i <= MAX(start, end); i++) {
                    if (i >= 0 && i < _nodeCount) {
                        [_selectedNodes addIndex:i];
                    }
                }
            }
        } else {
            NSInteger idx = [trimmed integerValue] - 1;
            if (idx >= 0 && idx < _nodeCount) {
                [_selectedNodes addIndex:idx];
            }
        }
    }

    [self setNeedsDisplay:YES];
}

- (NSString *)selectedNodesAsRangeString {
    if (_selectedNodes.count == 0) return @"";

    NSMutableArray *ranges = [NSMutableArray array];
    __block NSInteger rangeStart = -1;
    __block NSInteger rangeEnd = -1;

    [_selectedNodes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger nodeNum = idx + 1; // Convert to 1-indexed

        if (rangeStart < 0) {
            rangeStart = nodeNum;
            rangeEnd = nodeNum;
        } else if (nodeNum == rangeEnd + 1) {
            rangeEnd = nodeNum;
        } else {
            // Finish previous range
            if (rangeStart == rangeEnd) {
                [ranges addObject:[NSString stringWithFormat:@"%ld", (long)rangeStart]];
            } else {
                [ranges addObject:[NSString stringWithFormat:@"%ld-%ld", (long)rangeStart, (long)rangeEnd]];
            }
            rangeStart = nodeNum;
            rangeEnd = nodeNum;
        }
    }];

    // Add final range
    if (rangeStart >= 0) {
        if (rangeStart == rangeEnd) {
            [ranges addObject:[NSString stringWithFormat:@"%ld", (long)rangeStart]];
        } else {
            [ranges addObject:[NSString stringWithFormat:@"%ld-%ld", (long)rangeStart, (long)rangeEnd]];
        }
    }

    return [ranges componentsJoinedByString:@","];
}

#pragma mark - Mouse Handling

- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger nodeIndex = [self nodeAtPoint:point];

    if (nodeIndex != _hoveredNodeIndex) {
        _hoveredNodeIndex = nodeIndex;
        [self setNeedsDisplay:YES];

        if (_showNodeNumbers && nodeIndex >= 0) {
            // Update and show node info label
            _nodeInfoLabel.stringValue = [NSString stringWithFormat:@"Node %ld", (long)(nodeIndex + 1)];
            [_nodeInfoLabel sizeToFit];

            NSRect labelFrame = _nodeInfoLabel.frame;
            labelFrame.size.width += 12;
            labelFrame.size.height += 4;
            labelFrame.origin.x = point.x - labelFrame.size.width / 2;
            labelFrame.origin.y = point.y + 15;

            // Keep label within bounds
            if (NSMaxX(labelFrame) > self.bounds.size.width - 5) {
                labelFrame.origin.x = self.bounds.size.width - labelFrame.size.width - 5;
            }
            if (labelFrame.origin.x < 5) {
                labelFrame.origin.x = 5;
            }

            _nodeInfoLabel.frame = labelFrame;
            _nodeInfoLabel.hidden = NO;
        } else {
            _nodeInfoLabel.hidden = YES;
        }

        if ([_delegate respondsToSelector:@selector(nodeSelectionView:didHoverNode:)]) {
            [_delegate nodeSelectionView:self didHoverNode:nodeIndex];
        }
    }
}

- (void)mouseExited:(NSEvent *)event {
    _hoveredNodeIndex = -1;
    _nodeInfoLabel.hidden = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    if (!_selectionEnabled) return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    BOOL shiftDown = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    BOOL cmdDown = (event.modifierFlags & NSEventModifierFlagCommand) != 0;

    // Check for single node click
    NSInteger clickedNode = [self nodeAtPoint:point];

    if (clickedNode >= 0) {
        // Single node click
        if (cmdDown) {
            // Toggle selection
            if ([_selectedNodes containsIndex:clickedNode]) {
                [_selectedNodes removeIndex:clickedNode];
            } else {
                [_selectedNodes addIndex:clickedNode];
            }
        } else if (shiftDown && _selectedNodes.count > 0) {
            // Extend selection from last selected to clicked
            NSInteger lastSelected = _selectedNodes.lastIndex;
            NSInteger start = MIN(lastSelected, clickedNode);
            NSInteger end = MAX(lastSelected, clickedNode);
            for (NSInteger i = start; i <= end; i++) {
                [_selectedNodes addIndex:i];
            }
        } else {
            // Single selection
            [_selectedNodes removeAllIndexes];
            [_selectedNodes addIndex:clickedNode];
        }

        [self setNeedsDisplay:YES];
        [_delegate nodeSelectionViewDidChangeSelection:self];

        if ([_delegate respondsToSelector:@selector(nodeSelectionView:didClickNode:)]) {
            [_delegate nodeSelectionView:self didClickNode:clickedNode];
        }
        return;
    }

    // Start drag selection
    if (!shiftDown && !cmdDown) {
        [_selectedNodes removeAllIndexes];
    }

    _isDragging = YES;
    _dragStart = point;
    _dragEnd = point;
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_isDragging) return;

    _dragEnd = [self convertPoint:event.locationInWindow fromView:nil];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (!_isDragging) return;
    _isDragging = NO;

    NSRect bounds = self.bounds;
    CGFloat margin = 10;
    NSRect drawRect = NSInsetRect(bounds, margin, margin);

    // Calculate selection rectangle
    NSRect selRect = NSMakeRect(MIN(_dragStart.x, _dragEnd.x),
                                MIN(_dragStart.y, _dragEnd.y),
                                fabs(_dragEnd.x - _dragStart.x),
                                fabs(_dragEnd.y - _dragStart.y));

    // If small area, skip (already handled in mouseDown for single clicks)
    if (selRect.size.width < 5 && selRect.size.height < 5) {
        [self setNeedsDisplay:YES];
        return;
    }

    // Find nodes in selection
    BOOL cmdDown = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    for (NSInteger i = 0; i < _nodeCount; i++) {
        CGFloat x = drawRect.origin.x + _nodeX[i] * drawRect.size.width;
        CGFloat y = drawRect.origin.y + _nodeY[i] * drawRect.size.height;

        if (NSPointInRect(NSMakePoint(x, y), selRect)) {
            if (cmdDown) {
                // Toggle with cmd key
                if ([_selectedNodes containsIndex:i]) {
                    [_selectedNodes removeIndex:i];
                } else {
                    [_selectedNodes addIndex:i];
                }
            } else {
                [_selectedNodes addIndex:i];
            }
        }
    }

    [self setNeedsDisplay:YES];
    [_delegate nodeSelectionViewDidChangeSelection:self];
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 51 || event.keyCode == 117) { // Delete or Forward Delete
        [_selectedNodes removeAllIndexes];
        [self setNeedsDisplay:YES];
        [_delegate nodeSelectionViewDidChangeSelection:self];
    } else if (event.keyCode == 0 && (event.modifierFlags & NSEventModifierFlagCommand)) { // Cmd+A
        for (NSInteger i = 0; i < _nodeCount; i++) {
            [_selectedNodes addIndex:i];
        }
        [self setNeedsDisplay:YES];
        [_delegate nodeSelectionViewDidChangeSelection:self];
    } else {
        [super keyDown:event];
    }
}

- (BOOL)acceptsFirstResponder { return YES; }

- (BOOL)becomeFirstResponder {
    return YES;
}

@end

#pragma mark - XLSubBufferPanel

@interface XLSubBufferPanel ()
@property (nonatomic, strong) NSSlider *xSlider;
@property (nonatomic, strong) NSSlider *ySlider;
@property (nonatomic, strong) NSSlider *widthSlider;
@property (nonatomic, strong) NSSlider *heightSlider;
@property (nonatomic, strong) NSView *previewView;
@end

@implementation XLSubBufferPanel

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;
    [self addSubview:stack];

    // Preview view
    _previewView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 150)];
    _previewView.wantsLayer = YES;
    _previewView.layer.backgroundColor = [[NSColor darkGrayColor] CGColor];
    _previewView.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:_previewView];

    [NSLayoutConstraint activateConstraints:@[
        [_previewView.heightAnchor constraintEqualToConstant:150],
    ]];

    // X position
    [self addSliderRow:@"X Position:" slider:&_xSlider toStack:stack];
    // Y position
    [self addSliderRow:@"Y Position:" slider:&_ySlider toStack:stack];
    // Width
    [self addSliderRow:@"Width:" slider:&_widthSlider toStack:stack];
    _widthSlider.floatValue = 100;
    // Height
    [self addSliderRow:@"Height:" slider:&_heightSlider toStack:stack];
    _heightSlider.floatValue = 100;

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)addSliderRow:(NSString *)labelText slider:(NSSlider *__strong *)slider toStack:(NSStackView *)stack {
    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;

    NSTextField *label = [NSTextField labelWithString:labelText];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label.widthAnchor constraintEqualToConstant:80].active = YES;

    *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    (*slider).minValue = 0;
    (*slider).maxValue = 100;
    (*slider).floatValue = 0;
    [*slider setTarget:self];
    [*slider setAction:@selector(sliderChanged:)];

    NSTextField *valueLabel = [NSTextField labelWithString:@"0%"];
    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [valueLabel.widthAnchor constraintEqualToConstant:40].active = YES;
    valueLabel.tag = 100 + (slider - &_xSlider);

    [row addArrangedSubview:label];
    [row addArrangedSubview:*slider];
    [row addArrangedSubview:valueLabel];
    [stack addArrangedSubview:row];
}

- (void)sliderChanged:(NSSlider *)sender {
    [self updatePreview];
    [_delegate subBufferPanelDidChange:self];
}

- (void)updatePreview {
    [_previewView setNeedsDisplay:YES];
}

- (NSString *)subBufferString {
    return [NSString stringWithFormat:@"%.0f,%.0f,%.0f,%.0f",
            _xSlider.floatValue,
            _ySlider.floatValue,
            _xSlider.floatValue + _widthSlider.floatValue,
            _ySlider.floatValue + _heightSlider.floatValue];
}

- (void)setSubBufferString:(NSString *)subBufferString {
    if (!subBufferString || subBufferString.length == 0) {
        _xSlider.floatValue = 0;
        _ySlider.floatValue = 0;
        _widthSlider.floatValue = 100;
        _heightSlider.floatValue = 100;
        return;
    }

    NSArray *parts = [subBufferString componentsSeparatedByString:@","];
    if (parts.count >= 4) {
        float x1 = [parts[0] floatValue];
        float y1 = [parts[1] floatValue];
        float x2 = [parts[2] floatValue];
        float y2 = [parts[3] floatValue];

        _xSlider.floatValue = x1;
        _ySlider.floatValue = y1;
        _widthSlider.floatValue = x2 - x1;
        _heightSlider.floatValue = y2 - y1;
    }

    [self updatePreview];
}

@end

#pragma mark - XLStrandGridView

@interface XLStrandGridView ()
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSString *> *strands;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, assign) NSInteger selectedRow;
@end

@implementation XLStrandGridView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _strands = [NSMutableArray array];
        _strandCount = 0;
        _selectedRow = -1;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.borderType = NSBezelBorder;
    [self addSubview:_scrollView];

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.allowsMultipleSelection = NO;
    _tableView.rowHeight = 24;

    NSTableColumn *strandColumn = [[NSTableColumn alloc] initWithIdentifier:@"strand"];
    strandColumn.title = @"Row";
    strandColumn.width = 50;
    strandColumn.editable = NO;
    [_tableView addTableColumn:strandColumn];

    NSTableColumn *nodesColumn = [[NSTableColumn alloc] initWithIdentifier:@"nodes"];
    nodesColumn.title = @"Node Ranges (e.g., 1-10, 15, 20-25)";
    nodesColumn.width = 300;
    nodesColumn.editable = YES;
    [_tableView addTableColumn:nodesColumn];

    NSTableColumn *countColumn = [[NSTableColumn alloc] initWithIdentifier:@"count"];
    countColumn.title = @"Count";
    countColumn.width = 50;
    countColumn.editable = NO;
    [_tableView addTableColumn:countColumn];

    _scrollView.documentView = _tableView;

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (NSString *)strandAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_strands.count) return @"";
    return _strands[index];
}

- (void)setStrand:(NSString *)strand atIndex:(NSInteger)index {
    while (index >= (NSInteger)_strands.count) {
        [_strands addObject:@""];
    }
    _strands[index] = strand ?: @"";
    [_tableView reloadData];
    [_delegate strandGridViewDidChange:self];
}

- (void)addStrand {
    [_strands addObject:@""];
    _strandCount = _strands.count;
    [_tableView reloadData];
    [_delegate strandGridViewDidChange:self];
}

- (void)removeStrandAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_strands.count) return;
    [_strands removeObjectAtIndex:index];
    _strandCount = _strands.count;
    [_tableView reloadData];
    [_delegate strandGridViewDidChange:self];
}

- (void)moveStrandAtIndex:(NSInteger)from toIndex:(NSInteger)to {
    if (from < 0 || from >= (NSInteger)_strands.count) return;
    if (to < 0 || to >= (NSInteger)_strands.count) return;

    NSString *strand = _strands[from];
    [_strands removeObjectAtIndex:from];
    [_strands insertObject:strand atIndex:to];
    [_tableView reloadData];
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:to] byExtendingSelection:NO];
    [_delegate strandGridViewDidChange:self];
}

- (void)reverseStrandAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_strands.count) return;

    NSString *strand = _strands[index];
    NSArray *parts = [strand componentsSeparatedByString:@","];
    NSMutableArray *reversed = [NSMutableArray arrayWithCapacity:parts.count];

    for (NSString *part in [parts reverseObjectEnumerator]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed containsString:@"-"]) {
            // Reverse the range direction
            NSArray *range = [trimmed componentsSeparatedByString:@"-"];
            if (range.count == 2) {
                [reversed addObject:[NSString stringWithFormat:@"%@-%@", range[1], range[0]]];
            } else {
                [reversed addObject:trimmed];
            }
        } else {
            [reversed addObject:trimmed];
        }
    }

    _strands[index] = [reversed componentsJoinedByString:@","];
    [_tableView reloadData];
    [_delegate strandGridViewDidChange:self];
}

- (void)sortStrandAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_strands.count) return;

    NSString *strand = _strands[index];
    NSMutableArray<NSNumber *> *nodes = [NSMutableArray array];

    // Parse all nodes
    NSArray *parts = [strand componentsSeparatedByString:@","];
    for (NSString *part in parts) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed containsString:@"-"]) {
            NSArray *range = [trimmed componentsSeparatedByString:@"-"];
            if (range.count == 2) {
                NSInteger start = [range[0] integerValue];
                NSInteger end = [range[1] integerValue];
                for (NSInteger i = MIN(start, end); i <= MAX(start, end); i++) {
                    [nodes addObject:@(i)];
                }
            }
        } else if (trimmed.length > 0) {
            [nodes addObject:@([trimmed integerValue])];
        }
    }

    // Sort
    [nodes sortUsingSelector:@selector(compare:)];

    // Rebuild as ranges
    NSMutableArray *ranges = [NSMutableArray array];
    NSInteger rangeStart = -1, rangeEnd = -1;

    for (NSNumber *num in nodes) {
        NSInteger val = num.integerValue;
        if (rangeStart < 0) {
            rangeStart = rangeEnd = val;
        } else if (val == rangeEnd + 1) {
            rangeEnd = val;
        } else {
            if (rangeStart == rangeEnd) {
                [ranges addObject:[NSString stringWithFormat:@"%ld", (long)rangeStart]];
            } else {
                [ranges addObject:[NSString stringWithFormat:@"%ld-%ld", (long)rangeStart, (long)rangeEnd]];
            }
            rangeStart = rangeEnd = val;
        }
    }
    if (rangeStart >= 0) {
        if (rangeStart == rangeEnd) {
            [ranges addObject:[NSString stringWithFormat:@"%ld", (long)rangeStart]];
        } else {
            [ranges addObject:[NSString stringWithFormat:@"%ld-%ld", (long)rangeStart, (long)rangeEnd]];
        }
    }

    _strands[index] = [ranges componentsJoinedByString:@","];
    [_tableView reloadData];
    [_delegate strandGridViewDidChange:self];
}

- (NSArray<NSString *> *)allStrands {
    return [_strands copy];
}

- (void)setAllStrands:(NSArray<NSString *> *)strands {
    [_strands removeAllObjects];
    if (strands) {
        [_strands addObjectsFromArray:strands];
    }
    _strandCount = _strands.count;
    [_tableView reloadData];
}

- (NSInteger)countNodesInRange:(NSString *)rangeString {
    if (!rangeString || rangeString.length == 0) return 0;

    NSInteger count = 0;
    NSArray *parts = [rangeString componentsSeparatedByString:@","];
    for (NSString *part in parts) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed containsString:@"-"]) {
            NSArray *range = [trimmed componentsSeparatedByString:@"-"];
            if (range.count == 2) {
                NSInteger start = [range[0] integerValue];
                NSInteger end = [range[1] integerValue];
                count += labs(end - start) + 1;
            }
        } else if (trimmed.length > 0) {
            count++;
        }
    }
    return count;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _strands.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"strand"]) {
        return [NSString stringWithFormat:@"%ld", (long)(row + 1)];
    } else if ([tableColumn.identifier isEqualToString:@"nodes"]) {
        return (row < (NSInteger)_strands.count) ? _strands[row] : @"";
    } else if ([tableColumn.identifier isEqualToString:@"count"]) {
        NSString *nodes = (row < (NSInteger)_strands.count) ? _strands[row] : @"";
        return [NSString stringWithFormat:@"%ld", (long)[self countNodesInRange:nodes]];
    }
    return @"";
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"nodes"]) {
        [self setStrand:object atIndex:row];
    }
}

#pragma mark - NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    return [tableColumn.identifier isEqualToString:@"nodes"];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    _selectedRow = _tableView.selectedRow;
    if ([_delegate respondsToSelector:@selector(strandGridView:didSelectRow:)]) {
        [_delegate strandGridView:self didSelectRow:_selectedRow];
    }
}

@end

#pragma mark - XLSubModelsWindow

@interface XLSubModelsWindow () <XLNodeSelectionDelegate, XLSubBufferPanelDelegate, XLStrandGridDelegate> {
    XLSubModelInfo *_subModels;
    NSInteger _subModelCount;
    NSInteger _subModelCapacity;

    char (*_strandData)[XL_MAX_STRANDS_PER_SUBMODEL][XL_MAX_STRAND_LENGTH];
    int *_strandCounts;
}

@property (nonatomic, copy) NSString *modelName;
@property (nonatomic, strong) NSTableView *subModelList;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSSegmentedControl *typeSegment;
@property (nonatomic, strong) XLNodeSelectionView *nodeView;
@property (nonatomic, strong) XLSubBufferPanel *subBufferPanel;
@property (nonatomic, strong) XLStrandGridView *strandGrid;
@property (nonatomic, strong) NSPopUpButton *bufferStylePopup;

@property (nonatomic, copy) XLSubModelsCompletion completion;
@property (nonatomic, assign) NSInteger selectedSubModelIndex;
@property (nonatomic, assign) BOOL hasChanges;

// Additional UI elements
@property (nonatomic, strong) NSTextField *nodeCountLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *pasteButton;
@property (nonatomic, strong) NSPopUpButton *importPopup;

@end

@implementation XLSubModelsWindow

- (instancetype)initWithModelName:(NSString *)modelName {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowWidth, kWindowHeight)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = [NSString stringWithFormat:@"Sub Models: %@", modelName];
    window.minSize = NSMakeSize(800, 600);

    self = [super initWithWindow:window];
    if (self) {
        _modelName = [modelName copy];
        _selectedSubModelIndex = -1;
        _hasChanges = NO;
        _reloadLayout = NO;

        // Allocate submodel storage
        _subModelCapacity = XL_MAX_SUBMODELS;
        _subModels = (XLSubModelInfo *)calloc(_subModelCapacity, sizeof(XLSubModelInfo));
        _subModelCount = 0;

        _strandData = (char (*)[XL_MAX_STRANDS_PER_SUBMODEL][XL_MAX_STRAND_LENGTH])calloc(
            _subModelCapacity, XL_MAX_STRANDS_PER_SUBMODEL * XL_MAX_STRAND_LENGTH);
        _strandCounts = (int *)calloc(_subModelCapacity, sizeof(int));

        [self buildUI];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_subModels) free(_subModels);
    if (_strandData) free(_strandData);
    if (_strandCounts) free(_strandCounts);
}

- (void)buildUI {
    NSView *contentView = self.window.contentView;

    // Main split view
    NSSplitView *splitView = [[NSSplitView alloc] initWithFrame:contentView.bounds];
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    splitView.vertical = YES;
    splitView.dividerStyle = NSSplitViewDividerStyleThin;
    [contentView addSubview:splitView];

    // Left: Submodel list
    NSView *leftPanel = [self buildSubModelListPanel];
    [splitView addArrangedSubview:leftPanel];

    // Center: Editor
    NSView *centerPanel = [self buildEditorPanel];
    [splitView addArrangedSubview:centerPanel];

    // Right: Preview
    NSView *rightPanel = [self buildPreviewPanel];
    [splitView addArrangedSubview:rightPanel];

    [NSLayoutConstraint activateConstraints:@[
        [splitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [splitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [splitView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [splitView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-50],
    ]];

    // Bottom button bar
    NSStackView *buttonBar = [[NSStackView alloc] init];
    buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
    buttonBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonBar.spacing = 12;
    [contentView addSubview:buttonBar];

    NSButton *cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelClicked:)];
    cancelButton.keyEquivalent = @"\033";

    NSButton *okButton = [NSButton buttonWithTitle:@"OK" target:self action:@selector(okClicked:)];
    okButton.keyEquivalent = @"\r";

    [buttonBar addArrangedSubview:[[NSView alloc] init]];
    [buttonBar addArrangedSubview:cancelButton];
    [buttonBar addArrangedSubview:okButton];

    [NSLayoutConstraint activateConstraints:@[
        [buttonBar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:12],
        [buttonBar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-12],
        [buttonBar.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-12],
        [buttonBar.heightAnchor constraintEqualToConstant:30],
    ]];
}

- (NSView *)buildSubModelListPanel {
    NSView *panel = [[NSView alloc] initWithFrame:NSZeroRect];

    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;
    [panel addSubview:stack];

    // Title
    NSTextField *title = [NSTextField labelWithString:@"Sub Models"];
    title.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:title];

    // List
    NSScrollView *scrollView = [[NSScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;

    _subModelList = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _subModelList.dataSource = (id<NSTableViewDataSource>)self;
    _subModelList.delegate = (id<NSTableViewDelegate>)self;
    _subModelList.allowsMultipleSelection = YES;

    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameCol.title = @"Name";
    nameCol.width = 140;
    [_subModelList addTableColumn:nameCol];

    NSTableColumn *typeCol = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeCol.title = @"Type";
    typeCol.width = 60;
    [_subModelList addTableColumn:typeCol];

    scrollView.documentView = _subModelList;
    [stack addArrangedSubview:scrollView];

    // Row 1: Add/Remove buttons
    NSStackView *buttonRow1 = [[NSStackView alloc] init];
    buttonRow1.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow1.spacing = 4;

    NSButton *addBtn = [NSButton buttonWithTitle:@"Add" target:self action:@selector(addSubModelClicked:)];
    addBtn.toolTip = @"Add a new submodel";
    NSButton *removeBtn = [NSButton buttonWithTitle:@"Remove" target:self action:@selector(removeSubModelClicked:)];
    removeBtn.toolTip = @"Remove selected submodel(s)";
    NSButton *duplicateBtn = [NSButton buttonWithTitle:@"Duplicate" target:self action:@selector(copySubModelClicked:)];
    duplicateBtn.toolTip = @"Duplicate selected submodel";

    [buttonRow1 addArrangedSubview:addBtn];
    [buttonRow1 addArrangedSubview:removeBtn];
    [buttonRow1 addArrangedSubview:duplicateBtn];
    [stack addArrangedSubview:buttonRow1];

    // Row 2: Copy/Paste buttons
    NSStackView *buttonRow2 = [[NSStackView alloc] init];
    buttonRow2.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow2.spacing = 4;

    NSButton *copyBtn = [NSButton buttonWithTitle:@"Copy" target:self action:@selector(copyToPasteboard:)];
    copyBtn.toolTip = @"Copy selected submodel(s) to clipboard";
    _pasteButton = [NSButton buttonWithTitle:@"Paste" target:self action:@selector(pasteFromPasteboard:)];
    _pasteButton.toolTip = @"Paste submodel(s) from clipboard";
    _pasteButton.enabled = NO;

    [buttonRow2 addArrangedSubview:copyBtn];
    [buttonRow2 addArrangedSubview:_pasteButton];
    [stack addArrangedSubview:buttonRow2];

    // Row 3: Import/Export
    NSStackView *buttonRow3 = [[NSStackView alloc] init];
    buttonRow3.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow3.spacing = 4;

    _importPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    [_importPopup addItemWithTitle:@"Import..."];
    [_importPopup addItemWithTitle:@"From File..."];
    [_importPopup addItemWithTitle:@"From Model..."];
    [_importPopup addItemWithTitle:@"From Face Definition..."];
    [_importPopup addItemWithTitle:@"From State Definition..."];
    [_importPopup setTarget:self];
    [_importPopup setAction:@selector(importMenuSelected:)];

    NSButton *exportBtn = [NSButton buttonWithTitle:@"Export..." target:self action:@selector(exportClicked:)];

    [buttonRow3 addArrangedSubview:_importPopup];
    [buttonRow3 addArrangedSubview:exportBtn];
    [stack addArrangedSubview:buttonRow3];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:8],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-8],
    ]];

    // Monitor pasteboard for paste availability
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pasteboardChanged:)
                                                 name:NSApplicationDidBecomeActiveNotification
                                               object:nil];

    return panel;
}

- (NSView *)buildEditorPanel {
    NSView *panel = [[NSView alloc] initWithFrame:NSZeroRect];

    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 12;
    stack.alignment = NSLayoutAttributeLeading;
    [panel addSubview:stack];

    // Name field
    NSStackView *nameRow = [[NSStackView alloc] init];
    nameRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    nameRow.spacing = 8;

    NSTextField *nameLabel = [NSTextField labelWithString:@"Name:"];
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nameField.translatesAutoresizingMaskIntoConstraints = NO;
    [_nameField.widthAnchor constraintEqualToConstant:200].active = YES;
    [_nameField setTarget:self];
    [_nameField setAction:@selector(nameChanged:)];

    [nameRow addArrangedSubview:nameLabel];
    [nameRow addArrangedSubview:_nameField];
    [stack addArrangedSubview:nameRow];

    // Type segment
    _typeSegment = [[NSSegmentedControl alloc] init];
    [_typeSegment setSegmentCount:2];
    [_typeSegment setLabel:@"Node Ranges" forSegment:0];
    [_typeSegment setLabel:@"Sub Buffer" forSegment:1];
    _typeSegment.selectedSegment = 0;
    [_typeSegment setTarget:self];
    [_typeSegment setAction:@selector(typeChanged:)];
    [stack addArrangedSubview:_typeSegment];

    // Buffer style
    NSStackView *styleRow = [[NSStackView alloc] init];
    styleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    styleRow.spacing = 8;

    NSTextField *styleLabel = [NSTextField labelWithString:@"Buffer Style:"];
    _bufferStylePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_bufferStylePopup addItemsWithTitles:@[@"Default", @"Per Preview", @"Single Line",
                                            @"As Pixel", @"Horizontal Per Strand",
                                            @"Vertical Per Strand"]];
    [_bufferStylePopup setTarget:self];
    [_bufferStylePopup setAction:@selector(bufferStyleChanged:)];

    [styleRow addArrangedSubview:styleLabel];
    [styleRow addArrangedSubview:_bufferStylePopup];
    [stack addArrangedSubview:styleRow];

    // Strand grid (for node ranges mode)
    _strandGrid = [[XLStrandGridView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    _strandGrid.translatesAutoresizingMaskIntoConstraints = NO;
    _strandGrid.delegate = self;
    [stack addArrangedSubview:_strandGrid];

    [NSLayoutConstraint activateConstraints:@[
        [_strandGrid.heightAnchor constraintEqualToConstant:200],
        [_strandGrid.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];

    // Strand buttons
    NSStackView *strandButtons = [[NSStackView alloc] init];
    strandButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    strandButtons.spacing = 4;

    NSButton *addRowBtn = [NSButton buttonWithTitle:@"Add Row" target:self action:@selector(addStrandClicked:)];
    NSButton *removeRowBtn = [NSButton buttonWithTitle:@"Remove Row" target:self action:@selector(removeStrandClicked:)];
    NSButton *moveUpBtn = [NSButton buttonWithTitle:@"Move Up" target:self action:@selector(moveStrandUpClicked:)];
    NSButton *moveDownBtn = [NSButton buttonWithTitle:@"Move Down" target:self action:@selector(moveStrandDownClicked:)];
    NSButton *reverseBtn = [NSButton buttonWithTitle:@"Reverse" target:self action:@selector(reverseStrandClicked:)];

    [strandButtons addArrangedSubview:addRowBtn];
    [strandButtons addArrangedSubview:removeRowBtn];
    [strandButtons addArrangedSubview:moveUpBtn];
    [strandButtons addArrangedSubview:moveDownBtn];
    [strandButtons addArrangedSubview:reverseBtn];

    [stack addArrangedSubview:strandButtons];

    // Sub buffer panel (for subbuffer mode, initially hidden)
    _subBufferPanel = [[XLSubBufferPanel alloc] initWithFrame:NSMakeRect(0, 0, 400, 250)];
    _subBufferPanel.translatesAutoresizingMaskIntoConstraints = NO;
    _subBufferPanel.delegate = self;
    _subBufferPanel.hidden = YES;
    [stack addArrangedSubview:_subBufferPanel];

    [NSLayoutConstraint activateConstraints:@[
        [_subBufferPanel.heightAnchor constraintEqualToConstant:250],
        [_subBufferPanel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],
    ]];

    return panel;
}

- (NSView *)buildPreviewPanel {
    NSView *panel = [[NSView alloc] initWithFrame:NSZeroRect];

    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;
    [panel addSubview:stack];

    // Title with node count
    NSStackView *titleRow = [[NSStackView alloc] init];
    titleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    titleRow.spacing = 8;

    NSTextField *title = [NSTextField labelWithString:@"Model Preview"];
    title.font = [NSFont boldSystemFontOfSize:13];
    [titleRow addArrangedSubview:title];

    _nodeCountLabel = [NSTextField labelWithString:@""];
    _nodeCountLabel.textColor = [NSColor secondaryLabelColor];
    _nodeCountLabel.font = [NSFont systemFontOfSize:11];
    [titleRow addArrangedSubview:_nodeCountLabel];

    [stack addArrangedSubview:titleRow];

    _nodeView = [[XLNodeSelectionView alloc] initWithFrame:NSMakeRect(0, 0, 250, 250)];
    _nodeView.translatesAutoresizingMaskIntoConstraints = NO;
    _nodeView.delegate = self;
    _nodeView.showNodeNumbers = YES;
    [stack addArrangedSubview:_nodeView];

    [NSLayoutConstraint activateConstraints:@[
        [_nodeView.heightAnchor constraintGreaterThanOrEqualToConstant:200],
    ]];

    // Help text
    NSTextField *helpLabel = [NSTextField labelWithString:@"Click: select node | Drag: select area\nShift+click: extend | Cmd+click: toggle"];
    helpLabel.textColor = [NSColor tertiaryLabelColor];
    helpLabel.font = [NSFont systemFontOfSize:10];
    helpLabel.alignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:helpLabel];

    // Selection action buttons
    NSStackView *selectionRow = [[NSStackView alloc] init];
    selectionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    selectionRow.spacing = 4;

    NSButton *useSelectionBtn = [NSButton buttonWithTitle:@"Add to Row" target:self action:@selector(useSelectionClicked:)];
    useSelectionBtn.toolTip = @"Add selected nodes to current strand row";

    NSButton *newRowBtn = [NSButton buttonWithTitle:@"New Row" target:self action:@selector(newRowFromSelectionClicked:)];
    newRowBtn.toolTip = @"Create new strand row with selected nodes";

    NSButton *clearBtn = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clearSelectionClicked:)];
    clearBtn.toolTip = @"Clear node selection";

    [selectionRow addArrangedSubview:useSelectionBtn];
    [selectionRow addArrangedSubview:newRowBtn];
    [selectionRow addArrangedSubview:clearBtn];
    [stack addArrangedSubview:selectionRow];

    // Status label
    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.font = [NSFont systemFontOfSize:10];
    _statusLabel.alignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:_statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:8],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-8],
    ]];

    return panel;
}

- (void)showWithCompletion:(XLSubModelsCompletion)completion {
    _completion = completion;
    [self.window center];
    [self showWindow:nil];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _subModelCount;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == _subModelList && row >= 0 && row < _subModelCount) {
        if ([tableColumn.identifier isEqualToString:@"name"]) {
            return [NSString stringWithUTF8String:_subModels[row].name];
        } else if ([tableColumn.identifier isEqualToString:@"type"]) {
            return _subModels[row].isRanges ? @"Ranges" : @"Buffer";
        }
    }
    return @"";
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object == _subModelList) {
        _selectedSubModelIndex = _subModelList.selectedRow;
        [self loadSelectedSubModel];
        [self updatePreviewHighlighting];
    }
}

- (void)loadSelectedSubModel {
    if (_selectedSubModelIndex < 0 || _selectedSubModelIndex >= _subModelCount) {
        _nameField.stringValue = @"";
        _nameField.enabled = NO;
        return;
    }

    _nameField.enabled = YES;
    XLSubModelInfo *sm = &_subModels[_selectedSubModelIndex];

    _nameField.stringValue = [NSString stringWithUTF8String:sm->name];
    _typeSegment.selectedSegment = sm->isRanges ? 0 : 1;

    [self typeChanged:nil];

    if (sm->isRanges) {
        // Load strands
        int strandCount = _strandCounts[_selectedSubModelIndex];
        _strandGrid.strandCount = strandCount;
        for (int i = 0; i < strandCount; i++) {
            NSString *strand = [NSString stringWithUTF8String:_strandData[_selectedSubModelIndex][i]];
            [_strandGrid setStrand:strand atIndex:i];
        }
    } else {
        _subBufferPanel.subBufferString = [NSString stringWithUTF8String:sm->subBuffer];
    }

    // Select buffer style
    NSString *style = [NSString stringWithUTF8String:sm->bufferStyle];
    [_bufferStylePopup selectItemWithTitle:style];
}

#pragma mark - Actions

- (void)addSubModelClicked:(id)sender {
    if (_subModelCount >= _subModelCapacity) return;

    // Generate unique name
    NSString *baseName = @"SubModel";
    int num = 1;
    BOOL unique = NO;
    NSString *name = baseName;

    while (!unique) {
        name = [NSString stringWithFormat:@"%@%d", baseName, num];
        unique = YES;
        for (NSInteger i = 0; i < _subModelCount; i++) {
            if (strcmp(_subModels[i].name, name.UTF8String) == 0) {
                unique = NO;
                break;
            }
        }
        num++;
    }

    XLSubModelInfo *sm = &_subModels[_subModelCount];
    memset(sm, 0, sizeof(XLSubModelInfo));
    strncpy(sm->name, name.UTF8String, sizeof(sm->name) - 1);
    strncpy(sm->oldName, name.UTF8String, sizeof(sm->oldName) - 1);
    sm->isRanges = YES;
    strncpy(sm->bufferStyle, "Default", sizeof(sm->bufferStyle) - 1);

    _strandCounts[_subModelCount] = 1;
    _strandData[_subModelCount][0][0] = '\0';

    _subModelCount++;
    [_subModelList reloadData];
    [_subModelList selectRowIndexes:[NSIndexSet indexSetWithIndex:_subModelCount - 1]
               byExtendingSelection:NO];

    _hasChanges = YES;
    _reloadLayout = YES;
}

- (void)removeSubModelClicked:(id)sender {
    if (_selectedSubModelIndex < 0 || _selectedSubModelIndex >= _subModelCount) return;

    // Shift remaining submodels
    for (NSInteger i = _selectedSubModelIndex; i < _subModelCount - 1; i++) {
        _subModels[i] = _subModels[i + 1];
        _strandCounts[i] = _strandCounts[i + 1];
        memcpy(_strandData[i], _strandData[i + 1], XL_MAX_STRANDS_PER_SUBMODEL * XL_MAX_STRAND_LENGTH);
    }

    _subModelCount--;
    [_subModelList reloadData];

    _hasChanges = YES;
    _reloadLayout = YES;
}

- (void)copySubModelClicked:(id)sender {
    if (_selectedSubModelIndex < 0 || _selectedSubModelIndex >= _subModelCount) return;
    if (_subModelCount >= _subModelCapacity) return;

    XLSubModelInfo *src = &_subModels[_selectedSubModelIndex];
    XLSubModelInfo *dst = &_subModels[_subModelCount];

    *dst = *src;

    // Generate unique name
    NSString *baseName = [NSString stringWithFormat:@"%s_Copy", src->name];
    strncpy(dst->name, baseName.UTF8String, sizeof(dst->name) - 1);
    strncpy(dst->oldName, "", sizeof(dst->oldName) - 1);

    // Copy strands
    _strandCounts[_subModelCount] = _strandCounts[_selectedSubModelIndex];
    memcpy(_strandData[_subModelCount], _strandData[_selectedSubModelIndex],
           XL_MAX_STRANDS_PER_SUBMODEL * XL_MAX_STRAND_LENGTH);

    _subModelCount++;
    [_subModelList reloadData];

    _hasChanges = YES;
    _reloadLayout = YES;
}

- (void)importMenuSelected:(id)sender {
    NSInteger index = [_importPopup indexOfSelectedItem];
    switch (index) {
        case 1: // From File
            [self importFromFile];
            break;
        case 2: // From Model
            [self importFromModelDialog];
            break;
        case 3: // From Face Definition
            [self importFromFaceDefinition];
            break;
        case 4: // From State Definition
            [self importFromStateDefinition];
            break;
        default:
            break;
    }
    [_importPopup selectItemAtIndex:0];
}

- (void)importFromFile {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[@"xmodel", @"xml"];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.title = @"Import Submodels";

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSURL *url = panel.URL;
            // TODO: Parse the xmodel file and import submodels
            NSLog(@"Import submodels from: %@", url.path);
        }
    }];
}

- (void)importFromModelDialog {
    if (!_engineBridge) return;

    NSArray *modelNames = [_engineBridge getModelNamesExcludingGroups];
    if (modelNames.count == 0) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Import Submodels from Model";
    alert.informativeText = @"Select a model to import submodels from:";

    NSPopUpButton *modelPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 250, 24) pullsDown:NO];
    for (NSString *name in modelNames) {
        if (![name isEqualToString:_modelName]) {
            [modelPopup addItemWithTitle:name];
        }
    }
    alert.accessoryView = modelPopup;

    [alert addButtonWithTitle:@"Import"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString *sourceModel = modelPopup.selectedItem.title;
            [self importFromModel:sourceModel];
        }
    }];
}

- (void)importFromModel:(NSString *)sourceModelName {
    if (!_engineBridge || !sourceModelName) return;

    NSArray<NSDictionary *> *submodels = [_engineBridge getSubmodels:sourceModelName];
    if (submodels.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Submodels Found";
        alert.informativeText = [NSString stringWithFormat:@"The model '%@' has no submodels to import.", sourceModelName];
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    // TODO: Fetch full submodel definitions and add them
    NSLog(@"Importing %lu submodels from %@", (unsigned long)submodels.count, sourceModelName);

    _hasChanges = YES;
    _reloadLayout = YES;
    [_subModelList reloadData];
}

- (void)importFromFaceDefinition {
    // TODO: Get face definitions from model and create submodels
    NSLog(@"Import from face definition - not yet implemented");
}

- (void)importFromStateDefinition {
    // TODO: Get state definitions from model and create submodels
    NSLog(@"Import from state definition - not yet implemented");
}

- (void)exportClicked:(id)sender {
    if (_selectedSubModelIndex < 0 || _selectedSubModelIndex >= _subModelCount) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Submodel Selected";
        alert.informativeText = @"Please select a submodel to export.";
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"xmodel"];
    panel.canCreateDirectories = YES;
    panel.title = @"Export Submodel";

    NSString *submodelName = [NSString stringWithUTF8String:_subModels[_selectedSubModelIndex].name];
    panel.nameFieldStringValue = [submodelName stringByAppendingPathExtension:@"xmodel"];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            [self exportSelectedToFile:panel.URL];
        }
    }];
}

- (void)exportSelectedToFile:(NSURL *)fileURL {
    // TODO: Export submodel to xmodel format
    NSLog(@"Export submodel to: %@", fileURL.path);
}

#pragma mark - Copy/Paste

- (void)copyToPasteboard:(id)sender {
    [self copySelectedSubmodels];
}

- (void)pasteFromPasteboard:(id)sender {
    [self pasteSubmodels];
}

- (void)copySelectedSubmodels {
    NSIndexSet *selectedIndexes = _subModelList.selectedRowIndexes;
    if (selectedIndexes.count == 0) return;

    NSMutableArray *submodelData = [NSMutableArray array];

    [selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if (idx < (NSUInteger)self->_subModelCount) {
            XLSubModelInfo *sm = &self->_subModels[idx];
            NSMutableDictionary *data = [NSMutableDictionary dictionary];
            data[@"name"] = [NSString stringWithUTF8String:sm->name];
            data[@"isRanges"] = @(sm->isRanges);
            data[@"vertical"] = @(sm->vertical);
            data[@"bufferStyle"] = [NSString stringWithUTF8String:sm->bufferStyle];
            data[@"subBuffer"] = [NSString stringWithUTF8String:sm->subBuffer];

            // Copy strand data
            int strandCount = self->_strandCounts[idx];
            NSMutableArray *strands = [NSMutableArray arrayWithCapacity:strandCount];
            for (int i = 0; i < strandCount; i++) {
                [strands addObject:[NSString stringWithUTF8String:self->_strandData[idx][i]]];
            }
            data[@"strands"] = strands;

            [submodelData addObject:data];
        }
    }];

    if (submodelData.count > 0) {
        NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:submodelData
                                                     requiringSecureCoding:NO
                                                                     error:nil];
        if (archivedData) {
            NSPasteboard *pb = [NSPasteboard generalPasteboard];
            [pb clearContents];
            [pb setData:archivedData forType:XLSubModelPasteboardType];

            _statusLabel.stringValue = [NSString stringWithFormat:@"Copied %lu submodel(s)", (unsigned long)submodelData.count];
        }
    }

    [self updatePasteButtonState];
}

- (void)pasteSubmodels {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSData *data = [pb dataForType:XLSubModelPasteboardType];
    if (!data) return;

    NSSet *classes = [NSSet setWithObjects:[NSArray class], [NSDictionary class], [NSString class], [NSNumber class], nil];
    NSArray *submodelData = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
    if (!submodelData || submodelData.count == 0) return;

    NSInteger pastedCount = 0;
    for (NSDictionary *smData in submodelData) {
        if (_subModelCount >= _subModelCapacity) break;

        // Generate unique name
        NSString *baseName = smData[@"name"];
        NSString *uniqueName = [self generateUniqueName:baseName];

        XLSubModelInfo *sm = &_subModels[_subModelCount];
        memset(sm, 0, sizeof(XLSubModelInfo));
        strncpy(sm->name, uniqueName.UTF8String, sizeof(sm->name) - 1);
        strncpy(sm->oldName, "", sizeof(sm->oldName) - 1); // New submodel
        sm->isRanges = [smData[@"isRanges"] boolValue];
        sm->vertical = [smData[@"vertical"] boolValue];

        NSString *bufferStyle = smData[@"bufferStyle"] ?: @"Default";
        strncpy(sm->bufferStyle, bufferStyle.UTF8String, sizeof(sm->bufferStyle) - 1);

        NSString *subBuffer = smData[@"subBuffer"] ?: @"";
        strncpy(sm->subBuffer, subBuffer.UTF8String, sizeof(sm->subBuffer) - 1);

        // Copy strand data
        NSArray *strands = smData[@"strands"];
        _strandCounts[_subModelCount] = (int)MIN(strands.count, (NSUInteger)XL_MAX_STRANDS_PER_SUBMODEL);
        for (int i = 0; i < _strandCounts[_subModelCount]; i++) {
            strncpy(_strandData[_subModelCount][i], [strands[i] UTF8String], XL_MAX_STRAND_LENGTH - 1);
        }

        _subModelCount++;
        pastedCount++;
    }

    if (pastedCount > 0) {
        _hasChanges = YES;
        _reloadLayout = YES;
        [_subModelList reloadData];
        _statusLabel.stringValue = [NSString stringWithFormat:@"Pasted %ld submodel(s)", (long)pastedCount];
    }
}

- (void)updatePasteButtonState {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSData *data = [pb dataForType:XLSubModelPasteboardType];
    _pasteButton.enabled = (data != nil);
}

- (void)pasteboardChanged:(NSNotification *)notification {
    [self updatePasteButtonState];
}

- (NSString *)generateUniqueName:(NSString *)baseName {
    NSString *name = baseName;
    int suffix = 1;
    BOOL unique = NO;

    while (!unique) {
        unique = YES;
        for (NSInteger i = 0; i < _subModelCount; i++) {
            if (strcmp(_subModels[i].name, name.UTF8String) == 0) {
                unique = NO;
                name = [NSString stringWithFormat:@"%@_%d", baseName, suffix++];
                break;
            }
        }
    }

    return name;
}

- (void)nameChanged:(id)sender {
    if (_selectedSubModelIndex < 0) return;

    NSString *newName = _nameField.stringValue;
    strncpy(_subModels[_selectedSubModelIndex].name, newName.UTF8String,
            sizeof(_subModels[_selectedSubModelIndex].name) - 1);

    [_subModelList reloadData];
    _hasChanges = YES;
    _reloadLayout = YES;
}

- (void)typeChanged:(id)sender {
    BOOL isRanges = (_typeSegment.selectedSegment == 0);

    _strandGrid.hidden = !isRanges;
    _subBufferPanel.hidden = isRanges;

    if (_selectedSubModelIndex >= 0) {
        _subModels[_selectedSubModelIndex].isRanges = isRanges;
        _hasChanges = YES;
    }
}

- (void)bufferStyleChanged:(id)sender {
    if (_selectedSubModelIndex < 0) return;

    NSString *style = _bufferStylePopup.selectedItem.title;
    strncpy(_subModels[_selectedSubModelIndex].bufferStyle, style.UTF8String,
            sizeof(_subModels[_selectedSubModelIndex].bufferStyle) - 1);
    _hasChanges = YES;
}

- (void)addStrandClicked:(id)sender {
    [_strandGrid addStrand];
    if (_selectedSubModelIndex >= 0) {
        _strandCounts[_selectedSubModelIndex] = (int)_strandGrid.strandCount;
    }
    _hasChanges = YES;
}

- (void)removeStrandClicked:(id)sender {
    NSInteger row = _strandGrid.strandCount - 1;
    if (row >= 0) {
        [_strandGrid removeStrandAtIndex:row];
        if (_selectedSubModelIndex >= 0) {
            _strandCounts[_selectedSubModelIndex] = (int)_strandGrid.strandCount;
        }
    }
    _hasChanges = YES;
}

- (void)useSelectionClicked:(id)sender {
    NSString *rangeString = [_nodeView selectedNodesAsRangeString];
    if (rangeString.length == 0) {
        _statusLabel.stringValue = @"No nodes selected";
        return;
    }

    NSInteger selectedRow = _strandGrid.selectedRow;
    if (selectedRow < 0) {
        selectedRow = 0;
    }

    if (_strandGrid.strandCount == 0) {
        [_strandGrid addStrand];
        selectedRow = 0;
    }

    // Append to existing strand content
    NSString *existingStrand = [_strandGrid strandAtIndex:selectedRow];
    NSString *newStrand;
    if (existingStrand.length > 0) {
        newStrand = [NSString stringWithFormat:@"%@,%@", existingStrand, rangeString];
    } else {
        newStrand = rangeString;
    }

    [_strandGrid setStrand:newStrand atIndex:selectedRow];
    [_nodeView clearSelection];
    _hasChanges = YES;
    _statusLabel.stringValue = [NSString stringWithFormat:@"Added to row %ld", (long)(selectedRow + 1)];
}

- (void)newRowFromSelectionClicked:(id)sender {
    NSString *rangeString = [_nodeView selectedNodesAsRangeString];
    if (rangeString.length == 0) {
        _statusLabel.stringValue = @"No nodes selected";
        return;
    }

    [_strandGrid addStrand];
    NSInteger newRow = _strandGrid.strandCount - 1;
    [_strandGrid setStrand:rangeString atIndex:newRow];
    [_nodeView clearSelection];
    _hasChanges = YES;
    _statusLabel.stringValue = [NSString stringWithFormat:@"Created row %ld", (long)(newRow + 1)];
}

- (void)clearSelectionClicked:(id)sender {
    [_nodeView clearSelection];
    _statusLabel.stringValue = @"Selection cleared";
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

#pragma mark - Delegates

- (void)nodeSelectionViewDidChangeSelection:(XLNodeSelectionView *)view {
    NSInteger count = view.selectedNodes.count;
    if (count > 0) {
        _statusLabel.stringValue = [NSString stringWithFormat:@"%ld node%@ selected", (long)count, count == 1 ? @"" : @"s"];
    } else {
        _statusLabel.stringValue = @"";
    }
}

- (void)nodeSelectionView:(XLNodeSelectionView *)view didHoverNode:(NSInteger)nodeIndex {
    // Could update a status display with node details
}

- (void)nodeSelectionView:(XLNodeSelectionView *)view didClickNode:(NSInteger)nodeIndex {
    // Auto-update when node is clicked - the selection change will handle it
}

- (void)subBufferPanelDidChange:(XLSubBufferPanel *)panel {
    if (_selectedSubModelIndex < 0) return;

    NSString *subBuffer = panel.subBufferString;
    strncpy(_subModels[_selectedSubModelIndex].subBuffer, subBuffer.UTF8String,
            sizeof(_subModels[_selectedSubModelIndex].subBuffer) - 1);
    _hasChanges = YES;
}

- (void)strandGridViewDidChange:(XLStrandGridView *)view {
    if (_selectedSubModelIndex < 0) return;

    _strandCounts[_selectedSubModelIndex] = (int)view.strandCount;
    for (NSInteger i = 0; i < view.strandCount && i < XL_MAX_STRANDS_PER_SUBMODEL; i++) {
        NSString *strand = [view strandAtIndex:i];
        strncpy(_strandData[_selectedSubModelIndex][i], strand.UTF8String, XL_MAX_STRAND_LENGTH - 1);
    }
    _hasChanges = YES;

    // Update preview highlighting
    [self updatePreviewHighlighting];
}

- (void)strandGridView:(XLStrandGridView *)view didSelectRow:(NSInteger)row {
    // Highlight nodes for this row in the preview
    if (row >= 0 && row < _strandGrid.strandCount) {
        NSString *rangeString = [_strandGrid strandAtIndex:row];
        [_nodeView highlightNodesFromRangeString:rangeString];
    } else {
        [_nodeView clearHighlights];
    }
}

#pragma mark - Preview Updating

- (void)updatePreviewHighlighting {
    // Combine all strand ranges and highlight them
    NSMutableString *allRanges = [NSMutableString string];
    for (NSInteger i = 0; i < _strandGrid.strandCount; i++) {
        NSString *strand = [_strandGrid strandAtIndex:i];
        if (strand.length > 0) {
            if (allRanges.length > 0) {
                [allRanges appendString:@","];
            }
            [allRanges appendString:strand];
        }
    }

    [_nodeView highlightNodesFromRangeString:allRanges];
}

#pragma mark - Load Model Node Data

- (void)loadModelNodeData {
    if (!_engineBridge || !_modelName) {
        _nodeCountLabel.stringValue = @"(no model data)";
        return;
    }

    NSArray<NSDictionary *> *nodes = [_engineBridge getModelNodes:_modelName];
    if (nodes.count == 0) {
        _nodeCountLabel.stringValue = @"(no nodes)";
        return;
    }

    _nodeCountLabel.stringValue = [NSString stringWithFormat:@"(%lu nodes)", (unsigned long)nodes.count];

    // Calculate bounds for normalization
    float minX = FLT_MAX, maxX = -FLT_MAX;
    float minY = FLT_MAX, maxY = -FLT_MAX;

    for (NSDictionary *node in nodes) {
        float x = [node[@"x"] floatValue];
        float y = [node[@"y"] floatValue];
        minX = fminf(minX, x);
        maxX = fmaxf(maxX, x);
        minY = fminf(minY, y);
        maxY = fmaxf(maxY, y);
    }

    float rangeX = maxX - minX;
    float rangeY = maxY - minY;
    if (rangeX < 0.001f) rangeX = 1.0f;
    if (rangeY < 0.001f) rangeY = 1.0f;

    // Convert to normalized coordinates
    float *xCoords = (float *)malloc(nodes.count * sizeof(float));
    float *yCoords = (float *)malloc(nodes.count * sizeof(float));

    for (NSUInteger i = 0; i < nodes.count; i++) {
        NSDictionary *node = nodes[i];
        float x = [node[@"x"] floatValue];
        float y = [node[@"y"] floatValue];
        xCoords[i] = (x - minX) / rangeX;
        yCoords[i] = (y - minY) / rangeY;
    }

    [_nodeView setNodeCount:nodes.count positionsX:xCoords positionsY:yCoords];

    free(xCoords);
    free(yCoords);
}

#pragma mark - Strand Operations

- (void)moveStrandUpClicked:(id)sender {
    NSInteger selectedRow = _strandGrid.selectedRow;
    if (selectedRow > 0) {
        [_strandGrid moveStrandAtIndex:selectedRow toIndex:selectedRow - 1];
        if (_selectedSubModelIndex >= 0) {
            _strandCounts[_selectedSubModelIndex] = (int)_strandGrid.strandCount;
        }
        _hasChanges = YES;
    }
}

- (void)moveStrandDownClicked:(id)sender {
    NSInteger selectedRow = _strandGrid.selectedRow;
    if (selectedRow >= 0 && selectedRow < _strandGrid.strandCount - 1) {
        [_strandGrid moveStrandAtIndex:selectedRow toIndex:selectedRow + 1];
        if (_selectedSubModelIndex >= 0) {
            _strandCounts[_selectedSubModelIndex] = (int)_strandGrid.strandCount;
        }
        _hasChanges = YES;
    }
}

- (void)reverseStrandClicked:(id)sender {
    NSInteger selectedRow = _strandGrid.selectedRow;
    if (selectedRow >= 0) {
        [_strandGrid reverseStrandAtIndex:selectedRow];
        _hasChanges = YES;
    }
}

@end
