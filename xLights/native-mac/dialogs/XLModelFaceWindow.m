/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLModelFaceWindow.h"

/// Standard phoneme names for lip sync animation.
const char * const kPhonemeNames[] = {
    "AI", "E", "etc", "FV", "L", "MBP", "O", "rest", "U", "WQ"
};
const int kPhonemeCount = 10;

static const CGFloat kWindowWidth = 1000.0;
static const CGFloat kWindowHeight = 700.0;

#pragma mark - XLFaceNodeSelectionView

@interface XLFaceNodeSelectionView () {
    float *_nodeX;
    float *_nodeY;
    NSInteger _allocatedCount;
}
@property (nonatomic, strong) NSMutableIndexSet *internalSelectedNodes;
@property (nonatomic, strong) NSMutableIndexSet *highlightedNodes;
@property (nonatomic, strong) NSColor *highlightColor;
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) NSPoint dragStart;
@property (nonatomic, assign) NSPoint dragEnd;
@end

@implementation XLFaceNodeSelectionView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _nodeX = NULL;
        _nodeY = NULL;
        _nodeCount = 0;
        _allocatedCount = 0;
        _internalSelectedNodes = [NSMutableIndexSet indexSet];
        _highlightedNodes = [NSMutableIndexSet indexSet];
        _highlightColor = [NSColor systemYellowColor];
        _selectionEnabled = YES;

        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor controlBackgroundColor] CGColor];
        self.layer.cornerRadius = 4.0;
    }
    return self;
}

- (void)dealloc {
    if (_nodeX) free(_nodeX);
    if (_nodeY) free(_nodeY);
}

- (float *)nodePositionsX { return _nodeX; }
- (float *)nodePositionsY { return _nodeY; }
- (NSMutableIndexSet *)selectedNodes { return _internalSelectedNodes; }

- (void)setNodeCount:(NSInteger)count positionsX:(const float *)x positionsY:(const float *)y {
    if (count > _allocatedCount) {
        if (_nodeX) free(_nodeX);
        if (_nodeY) free(_nodeY);
        _nodeX = (float *)malloc(count * sizeof(float));
        _nodeY = (float *)malloc(count * sizeof(float));
        _allocatedCount = count;
    }

    _nodeCount = count;
    if (count > 0 && x && y) {
        memcpy(_nodeX, x, count * sizeof(float));
        memcpy(_nodeY, y, count * sizeof(float));
    }

    [self setNeedsDisplay:YES];
}

- (void)highlightNodesForPhoneme:(NSString *)phoneme withData:(XLPhonemeData)data {
    [_highlightedNodes removeAllIndexes];

    // Parse node data string to get node indices
    NSString *nodeString = [NSString stringWithUTF8String:data.nodeData];
    NSArray *parts = [nodeString componentsSeparatedByString:@","];

    for (NSString *part in parts) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;

        NSRange dashRange = [trimmed rangeOfString:@"-"];
        if (dashRange.location != NSNotFound) {
            // Range like "1-10"
            NSInteger start = [[trimmed substringToIndex:dashRange.location] integerValue];
            NSInteger end = [[trimmed substringFromIndex:dashRange.location + 1] integerValue];
            for (NSInteger i = start; i <= end && i <= _nodeCount; i++) {
                if (i > 0) [_highlightedNodes addIndex:i - 1]; // Convert to 0-based
            }
        } else {
            // Single node
            NSInteger node = [trimmed integerValue];
            if (node > 0 && node <= _nodeCount) {
                [_highlightedNodes addIndex:node - 1];
            }
        }
    }

    if (data.hasCustomColor) {
        _highlightColor = [NSColor colorWithRed:data.colorRed / 255.0
                                          green:data.colorGreen / 255.0
                                           blue:data.colorBlue / 255.0
                                          alpha:1.0];
    } else {
        _highlightColor = [NSColor systemYellowColor];
    }

    [self setNeedsDisplay:YES];
}

- (void)clearHighlight {
    [_highlightedNodes removeAllIndexes];
    [self setNeedsDisplay:YES];
}

- (void)clearSelection {
    [_internalSelectedNodes removeAllIndexes];
    [self setNeedsDisplay:YES];
}

- (NSString *)selectedNodesAsRangeString {
    if (_internalSelectedNodes.count == 0) return @"";

    NSMutableArray *ranges = [NSMutableArray array];
    __block NSInteger rangeStart = -1;
    __block NSInteger rangeEnd = -1;

    [_internalSelectedNodes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger nodeNum = idx + 1; // Convert to 1-based

        if (rangeStart < 0) {
            rangeStart = nodeNum;
            rangeEnd = nodeNum;
        } else if (nodeNum == rangeEnd + 1) {
            rangeEnd = nodeNum;
        } else {
            // Output previous range
            if (rangeStart == rangeEnd) {
                [ranges addObject:[NSString stringWithFormat:@"%ld", (long)rangeStart]];
            } else {
                [ranges addObject:[NSString stringWithFormat:@"%ld-%ld", (long)rangeStart, (long)rangeEnd]];
            }
            rangeStart = nodeNum;
            rangeEnd = nodeNum;
        }
    }];

    // Output last range
    if (rangeStart >= 0) {
        if (rangeStart == rangeEnd) {
            [ranges addObject:[NSString stringWithFormat:@"%ld", (long)rangeStart]];
        } else {
            [ranges addObject:[NSString stringWithFormat:@"%ld-%ld", (long)rangeStart, (long)rangeEnd]];
        }
    }

    return [ranges componentsJoinedByString:@","];
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

    NSRect bounds = self.bounds;
    CGFloat margin = 10.0;
    NSRect drawRect = NSInsetRect(bounds, margin, margin);

    // Draw background
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(dirtyRect);

    // Draw border
    [[NSColor separatorColor] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRect:bounds];
    [border stroke];

    // Draw nodes
    CGFloat nodeSize = 6.0;

    for (NSInteger i = 0; i < _nodeCount; i++) {
        CGFloat x = drawRect.origin.x + (_nodeX[i] * drawRect.size.width);
        CGFloat y = drawRect.origin.y + (_nodeY[i] * drawRect.size.height);

        NSRect nodeRect = NSMakeRect(x - nodeSize/2, y - nodeSize/2, nodeSize, nodeSize);

        NSColor *fillColor;
        if ([_internalSelectedNodes containsIndex:i]) {
            fillColor = [NSColor controlAccentColor];
        } else if ([_highlightedNodes containsIndex:i]) {
            fillColor = _highlightColor;
        } else {
            fillColor = [NSColor secondaryLabelColor];
        }

        [fillColor setFill];
        NSBezierPath *nodePath = [NSBezierPath bezierPathWithOvalInRect:nodeRect];
        [nodePath fill];
    }

    // Draw selection rectangle if dragging
    if (_isDragging) {
        [[NSColor controlAccentColor] setStroke];
        NSColor *fillColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.1];
        [fillColor setFill];

        NSRect selRect = NSMakeRect(MIN(_dragStart.x, _dragEnd.x),
                                    MIN(_dragStart.y, _dragEnd.y),
                                    fabs(_dragEnd.x - _dragStart.x),
                                    fabs(_dragEnd.y - _dragStart.y));

        NSBezierPath *selPath = [NSBezierPath bezierPathWithRect:selRect];
        [selPath fill];
        [selPath stroke];
    }
}

- (void)mouseDown:(NSEvent *)event {
    if (!_selectionEnabled) return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    _dragStart = point;
    _dragEnd = point;
    _isDragging = YES;

    if (!(event.modifierFlags & NSEventModifierFlagShift)) {
        [_internalSelectedNodes removeAllIndexes];
    }

    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_selectionEnabled || !_isDragging) return;

    _dragEnd = [self convertPoint:event.locationInWindow fromView:nil];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (!_selectionEnabled || !_isDragging) return;

    _isDragging = NO;

    NSRect bounds = self.bounds;
    CGFloat margin = 10.0;
    NSRect drawRect = NSInsetRect(bounds, margin, margin);

    NSRect selRect = NSMakeRect(MIN(_dragStart.x, _dragEnd.x),
                                MIN(_dragStart.y, _dragEnd.y),
                                fabs(_dragEnd.x - _dragStart.x),
                                fabs(_dragEnd.y - _dragStart.y));

    // Select nodes in rectangle
    for (NSInteger i = 0; i < _nodeCount; i++) {
        CGFloat x = drawRect.origin.x + (_nodeX[i] * drawRect.size.width);
        CGFloat y = drawRect.origin.y + (_nodeY[i] * drawRect.size.height);

        if (NSPointInRect(NSMakePoint(x, y), selRect)) {
            [_internalSelectedNodes addIndex:i];
        }
    }

    [self setNeedsDisplay:YES];

    if ([_delegate respondsToSelector:@selector(faceNodeSelectionViewDidChangeSelection:)]) {
        [_delegate faceNodeSelectionViewDidChangeSelection:self];
    }
}

@end

#pragma mark - XLPhonemeGridView

@interface XLPhonemeGridView () {
    XLPhonemeData _phonemeData[XL_MAX_PHONEMES];
}
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@end

@implementation XLPhonemeGridView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _faceType = XLFaceTypeNodeRanges;
        _customColorsEnabled = NO;
        _selectedPhonemeIndex = -1;

        // Initialize phoneme data
        for (int i = 0; i < kPhonemeCount; i++) {
            memset(&_phonemeData[i], 0, sizeof(XLPhonemeData));
            strlcpy(_phonemeData[i].phonemeName, kPhonemeNames[i], sizeof(_phonemeData[i].phonemeName));
        }

        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.borderType = NSBezelBorder;

    _tableView = [[NSTableView alloc] initWithFrame:_scrollView.bounds];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.rowHeight = 24.0;
    _tableView.allowsColumnReordering = NO;
    _tableView.usesAlternatingRowBackgroundColors = YES;

    // Phoneme column
    NSTableColumn *phonemeCol = [[NSTableColumn alloc] initWithIdentifier:@"phoneme"];
    phonemeCol.title = @"Phoneme";
    phonemeCol.width = 80;
    phonemeCol.editable = NO;
    [_tableView addTableColumn:phonemeCol];

    // Nodes column
    NSTableColumn *nodesCol = [[NSTableColumn alloc] initWithIdentifier:@"nodes"];
    nodesCol.title = @"Nodes";
    nodesCol.width = 200;
    nodesCol.editable = YES;
    [_tableView addTableColumn:nodesCol];

    // Color column
    NSTableColumn *colorCol = [[NSTableColumn alloc] initWithIdentifier:@"color"];
    colorCol.title = @"Color";
    colorCol.width = 60;
    colorCol.editable = NO;
    [_tableView addTableColumn:colorCol];

    _scrollView.documentView = _tableView;
    [self addSubview:_scrollView];
}

- (XLPhonemeData)phonemeDataAtIndex:(NSInteger)index {
    if (index < 0 || index >= kPhonemeCount) {
        XLPhonemeData empty = {0};
        return empty;
    }
    return _phonemeData[index];
}

- (void)setPhonemeData:(XLPhonemeData)data atIndex:(NSInteger)index {
    if (index < 0 || index >= kPhonemeCount) return;
    _phonemeData[index] = data;
    [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:index]
                          columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 3)]];
}

- (void)getAllPhonemeData:(XLPhonemeData *)buffer count:(NSInteger)count {
    NSInteger copyCount = MIN(count, (NSInteger)kPhonemeCount);
    memcpy(buffer, _phonemeData, copyCount * sizeof(XLPhonemeData));
}

- (void)setAllPhonemeData:(const XLPhonemeData *)buffer count:(NSInteger)count {
    NSInteger copyCount = MIN(count, (NSInteger)kPhonemeCount);
    memcpy(_phonemeData, buffer, copyCount * sizeof(XLPhonemeData));
    [_tableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return kPhonemeCount;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= kPhonemeCount) return nil;

    NSString *identifier = tableColumn.identifier;

    if ([identifier isEqualToString:@"phoneme"]) {
        return [NSString stringWithUTF8String:_phonemeData[row].phonemeName];
    } else if ([identifier isEqualToString:@"nodes"]) {
        return [NSString stringWithUTF8String:_phonemeData[row].nodeData];
    }

    return nil;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= kPhonemeCount) return;

    NSString *identifier = tableColumn.identifier;

    if ([identifier isEqualToString:@"nodes"]) {
        NSString *value = object;
        strlcpy(_phonemeData[row].nodeData, [value UTF8String] ?: "", sizeof(_phonemeData[row].nodeData));

        if ([_delegate respondsToSelector:@selector(phonemeGridViewDidChange:)]) {
            [_delegate phonemeGridViewDidChange:self];
        }
    }
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    _selectedPhonemeIndex = _tableView.selectedRow;

    if ([_delegate respondsToSelector:@selector(phonemeGridView:didSelectPhoneme:)]) {
        [_delegate phonemeGridView:self didSelectPhoneme:_selectedPhonemeIndex];
    }
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *identifier = tableColumn.identifier;

    if ([identifier isEqualToString:@"color"]) {
        NSView *cellView = [tableView makeViewWithIdentifier:@"colorCell" owner:self];
        if (!cellView) {
            cellView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 60, 24)];
            cellView.identifier = @"colorCell";

            NSButton *colorButton = [[NSButton alloc] initWithFrame:NSMakeRect(5, 2, 50, 20)];
            colorButton.bezelStyle = NSBezelStyleSmallSquare;
            colorButton.tag = row;
            colorButton.target = self;
            colorButton.action = @selector(colorButtonClicked:);
            [cellView addSubview:colorButton];
        }

        NSButton *button = cellView.subviews.firstObject;
        button.tag = row;

        if (_phonemeData[row].hasCustomColor) {
            button.wantsLayer = YES;
            button.layer.backgroundColor = [NSColor colorWithRed:_phonemeData[row].colorRed / 255.0
                                                           green:_phonemeData[row].colorGreen / 255.0
                                                            blue:_phonemeData[row].colorBlue / 255.0
                                                           alpha:1.0].CGColor;
            button.title = @"";
        } else {
            button.wantsLayer = NO;
            button.title = @"Auto";
        }

        return cellView;
    }

    return nil;
}

- (void)colorButtonClicked:(NSButton *)sender {
    NSInteger row = sender.tag;
    if (row < 0 || row >= kPhonemeCount) return;

    NSColorPanel *colorPanel = [NSColorPanel sharedColorPanel];
    colorPanel.target = self;
    colorPanel.action = @selector(colorPanelChanged:);

    if (_phonemeData[row].hasCustomColor) {
        colorPanel.color = [NSColor colorWithRed:_phonemeData[row].colorRed / 255.0
                                           green:_phonemeData[row].colorGreen / 255.0
                                            blue:_phonemeData[row].colorBlue / 255.0
                                           alpha:1.0];
    }

    [colorPanel makeKeyAndOrderFront:self];
}

- (void)colorPanelChanged:(NSColorPanel *)colorPanel {
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= kPhonemeCount) return;

    NSColor *color = [colorPanel.color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    _phonemeData[row].colorRed = (uint8_t)(color.redComponent * 255);
    _phonemeData[row].colorGreen = (uint8_t)(color.greenComponent * 255);
    _phonemeData[row].colorBlue = (uint8_t)(color.blueComponent * 255);
    _phonemeData[row].hasCustomColor = YES;

    [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
                          columnIndexes:[NSIndexSet indexSetWithIndex:2]];

    if ([_delegate respondsToSelector:@selector(phonemeGridViewDidChange:)]) {
        [_delegate phonemeGridViewDidChange:self];
    }
}

@end

#pragma mark - XLMatrixFacePanel

@interface XLMatrixFacePanel () {
    XLMatrixFaceData _matrixData[XL_MAX_PHONEMES];
}
@property (nonatomic, strong) NSCollectionView *collectionView;
@property (nonatomic, strong) NSScrollView *scrollView;
@end

@implementation XLMatrixFacePanel

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _imagePlacement = @"Centered";

        // Initialize matrix data
        for (int i = 0; i < kPhonemeCount; i++) {
            memset(&_matrixData[i], 0, sizeof(XLMatrixFaceData));
            strlcpy(_matrixData[i].phonemeName, kPhonemeNames[i], sizeof(_matrixData[i].phonemeName));
        }

        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.hasVerticalScroller = YES;

    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.itemSize = NSMakeSize(100, 120);
    layout.minimumInteritemSpacing = 10;
    layout.minimumLineSpacing = 10;
    layout.sectionInset = NSEdgeInsetsMake(10, 10, 10, 10);

    _collectionView = [[NSCollectionView alloc] initWithFrame:_scrollView.bounds];
    _collectionView.collectionViewLayout = layout;
    _collectionView.backgroundColors = @[[NSColor controlBackgroundColor]];

    _scrollView.documentView = _collectionView;
    [self addSubview:_scrollView];
}

- (XLMatrixFaceData)matrixDataAtIndex:(NSInteger)index {
    if (index < 0 || index >= kPhonemeCount) {
        XLMatrixFaceData empty = {0};
        return empty;
    }
    return _matrixData[index];
}

- (void)setMatrixData:(XLMatrixFaceData)data atIndex:(NSInteger)index {
    if (index < 0 || index >= kPhonemeCount) return;
    _matrixData[index] = data;
    [_collectionView reloadData];
}

@end

#pragma mark - XLModelFaceWindow

@interface XLModelFaceWindow () <XLPhonemeGridDelegate, XLFaceNodeSelectionDelegate>
@property (nonatomic, copy) NSString *modelName;
@property (nonatomic, copy) XLModelFaceCompletion completion;
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSTabView *faceTypeTabView;
@property (nonatomic, strong) NSPopUpButton *faceNamePopup;
@property (nonatomic, strong) XLPhonemeGridView *phonemeGrid;
@property (nonatomic, strong) XLMatrixFacePanel *matrixPanel;
@property (nonatomic, strong) XLFaceNodeSelectionView *nodeSelectionView;
@property (nonatomic, strong) NSButton *outputToLightsCheckbox;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *faceDataDict;
@property (nonatomic, assign) BOOL hasUnsavedChanges;
@end

@implementation XLModelFaceWindow

- (instancetype)initWithModelName:(NSString *)modelName {
    NSRect windowRect = NSMakeRect(0, 0, kWindowWidth, kWindowHeight);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:windowRect
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskMiniaturizable |
                                                            NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];

    self = [super initWithWindow:window];
    if (self) {
        _modelName = [modelName copy];
        _faceDataDict = [NSMutableDictionary dictionary];
        _hasUnsavedChanges = NO;
        _outputToLights = NO;
        _needsReload = NO;

        window.title = [NSString stringWithFormat:@"Model Faces - %@", modelName];
        window.delegate = (id<NSWindowDelegate>)self;
        [window center];

        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    // Top bar with face selection
    NSView *topBar = [[NSView alloc] initWithFrame:NSMakeRect(0, kWindowHeight - 50, kWindowWidth, 50)];
    topBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

    NSTextField *label = [NSTextField labelWithString:@"Face Definition:"];
    label.frame = NSMakeRect(10, 15, 100, 20);
    [topBar addSubview:label];

    _faceNamePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(115, 12, 200, 26) pullsDown:NO];
    [_faceNamePopup addItemWithTitle:@"Default"];
    _faceNamePopup.target = self;
    _faceNamePopup.action = @selector(faceNameChanged:);
    [topBar addSubview:_faceNamePopup];

    NSButton *addButton = [[NSButton alloc] initWithFrame:NSMakeRect(320, 12, 30, 26)];
    addButton.bezelStyle = NSBezelStyleRounded;
    addButton.title = @"+";
    addButton.target = self;
    addButton.action = @selector(addFaceDefinition:);
    [topBar addSubview:addButton];

    NSButton *deleteButton = [[NSButton alloc] initWithFrame:NSMakeRect(355, 12, 30, 26)];
    deleteButton.bezelStyle = NSBezelStyleRounded;
    deleteButton.title = @"-";
    deleteButton.target = self;
    deleteButton.action = @selector(deleteFaceDefinition:);
    [topBar addSubview:deleteButton];

    _outputToLightsCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(kWindowWidth - 150, 15, 140, 20)];
    _outputToLightsCheckbox.buttonType = NSButtonTypeSwitch;
    _outputToLightsCheckbox.title = @"Output to Lights";
    _outputToLightsCheckbox.target = self;
    _outputToLightsCheckbox.action = @selector(outputToLightsChanged:);
    _outputToLightsCheckbox.autoresizingMask = NSViewMinXMargin;
    [topBar addSubview:_outputToLightsCheckbox];

    [contentView addSubview:topBar];

    // Main split view
    _splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 50, kWindowWidth, kWindowHeight - 100)];
    _splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitView.vertical = YES;

    // Left side - face type tabs and grid
    NSView *leftPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, kWindowHeight - 100)];

    _faceTypeTabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 500, kWindowHeight - 100)];
    _faceTypeTabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Single Node tab
    NSTabViewItem *singleNodeTab = [[NSTabViewItem alloc] initWithIdentifier:@"singleNode"];
    singleNodeTab.label = @"Single Node";
    [_faceTypeTabView addTabViewItem:singleNodeTab];

    // Node Ranges tab
    NSTabViewItem *nodeRangesTab = [[NSTabViewItem alloc] initWithIdentifier:@"nodeRanges"];
    nodeRangesTab.label = @"Node Ranges";

    _phonemeGrid = [[XLPhonemeGridView alloc] initWithFrame:NSMakeRect(0, 0, 480, 400)];
    _phonemeGrid.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _phonemeGrid.delegate = self;
    [nodeRangesTab.view addSubview:_phonemeGrid];

    [_faceTypeTabView addTabViewItem:nodeRangesTab];

    // Matrix tab
    NSTabViewItem *matrixTab = [[NSTabViewItem alloc] initWithIdentifier:@"matrix"];
    matrixTab.label = @"Matrix";

    _matrixPanel = [[XLMatrixFacePanel alloc] initWithFrame:NSMakeRect(0, 0, 480, 400)];
    _matrixPanel.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [matrixTab.view addSubview:_matrixPanel];

    [_faceTypeTabView addTabViewItem:matrixTab];

    [leftPanel addSubview:_faceTypeTabView];
    [_splitView addSubview:leftPanel];

    // Right side - model preview
    NSView *rightPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, kWindowHeight - 100)];

    _nodeSelectionView = [[XLFaceNodeSelectionView alloc] initWithFrame:NSMakeRect(10, 10, 380, 380)];
    _nodeSelectionView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _nodeSelectionView.delegate = self;
    [rightPanel addSubview:_nodeSelectionView];

    [_splitView addSubview:rightPanel];

    [contentView addSubview:_splitView];

    // Bottom bar with buttons
    NSView *bottomBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kWindowWidth, 50)];
    bottomBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;

    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(kWindowWidth - 180, 10, 80, 30)];
    cancelButton.bezelStyle = NSBezelStyleRounded;
    cancelButton.title = @"Cancel";
    cancelButton.keyEquivalent = @"\033";
    cancelButton.target = self;
    cancelButton.action = @selector(cancelClicked:);
    cancelButton.autoresizingMask = NSViewMinXMargin;
    [bottomBar addSubview:cancelButton];

    NSButton *okButton = [[NSButton alloc] initWithFrame:NSMakeRect(kWindowWidth - 90, 10, 80, 30)];
    okButton.bezelStyle = NSBezelStyleRounded;
    okButton.title = @"OK";
    okButton.keyEquivalent = @"\r";
    okButton.target = self;
    okButton.action = @selector(okClicked:);
    okButton.autoresizingMask = NSViewMinXMargin;
    [bottomBar addSubview:okButton];

    [contentView addSubview:bottomBar];
}

- (void)showWithCompletion:(XLModelFaceCompletion)completion {
    _completion = [completion copy];
    [self showWindow:nil];
}

- (void)faceNameChanged:(NSPopUpButton *)sender {
    // Load face data for selected name
}

- (void)addFaceDefinition:(NSButton *)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"New Face Definition";
    alert.informativeText = @"Enter a name for the new face definition:";

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    input.stringValue = @"";
    alert.accessoryView = input;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn && input.stringValue.length > 0) {
            [self->_faceNamePopup addItemWithTitle:input.stringValue];
            [self->_faceNamePopup selectItemWithTitle:input.stringValue];
            self->_hasUnsavedChanges = YES;
        }
    }];
}

- (void)deleteFaceDefinition:(NSButton *)sender {
    NSString *selected = _faceNamePopup.selectedItem.title;
    if ([selected isEqualToString:@"Default"]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Cannot Delete";
        alert.informativeText = @"The Default face definition cannot be deleted.";
        [alert runModal];
        return;
    }

    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Delete Face Definition";
    confirm.informativeText = [NSString stringWithFormat:@"Are you sure you want to delete '%@'?", selected];
    [confirm addButtonWithTitle:@"Delete"];
    [confirm addButtonWithTitle:@"Cancel"];

    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [self->_faceNamePopup removeItemWithTitle:selected];
            [self->_faceDataDict removeObjectForKey:selected];
            self->_hasUnsavedChanges = YES;
        }
    }];
}

- (void)outputToLightsChanged:(NSButton *)sender {
    _outputToLights = (sender.state == NSControlStateValueOn);
}

- (void)okClicked:(NSButton *)sender {
    _needsReload = _hasUnsavedChanges;
    [self.window close];
    if (_completion) {
        _completion(YES);
    }
}

- (void)cancelClicked:(NSButton *)sender {
    [self.window close];
    if (_completion) {
        _completion(NO);
    }
}

- (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)faceInfo {
    return [_faceDataDict copy];
}

- (void)setFaceInfo:(NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)info {
    [_faceDataDict removeAllObjects];
    [_faceDataDict addEntriesFromDictionary:info];

    [_faceNamePopup removeAllItems];
    NSArray *sortedKeys = [[info allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sortedKeys) {
        [_faceNamePopup addItemWithTitle:key];
    }

    if (_faceNamePopup.numberOfItems == 0) {
        [_faceNamePopup addItemWithTitle:@"Default"];
    }
}

#pragma mark - XLPhonemeGridDelegate

- (void)phonemeGridViewDidChange:(XLPhonemeGridView *)view {
    _hasUnsavedChanges = YES;
}

- (void)phonemeGridView:(XLPhonemeGridView *)view didSelectPhoneme:(NSInteger)index {
    XLPhonemeData data = [view phonemeDataAtIndex:index];
    [_nodeSelectionView highlightNodesForPhoneme:[NSString stringWithUTF8String:data.phonemeName]
                                        withData:data];
}

#pragma mark - XLFaceNodeSelectionDelegate

- (void)faceNodeSelectionViewDidChangeSelection:(XLFaceNodeSelectionView *)view {
    NSInteger selectedPhoneme = _phonemeGrid.selectedPhonemeIndex;
    if (selectedPhoneme < 0) return;

    NSString *rangeString = [view selectedNodesAsRangeString];
    XLPhonemeData data = [_phonemeGrid phonemeDataAtIndex:selectedPhoneme];
    strlcpy(data.nodeData, [rangeString UTF8String], sizeof(data.nodeData));
    [_phonemeGrid setPhonemeData:data atIndex:selectedPhoneme];

    _hasUnsavedChanges = YES;
}

@end
