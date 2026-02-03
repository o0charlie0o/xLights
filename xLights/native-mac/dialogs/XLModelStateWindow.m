/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLModelStateWindow.h"

static const CGFloat kWindowWidth = 1000.0;
static const CGFloat kWindowHeight = 700.0;

#pragma mark - XLStateNodeSelectionView

@interface XLStateNodeSelectionView () {
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

@implementation XLStateNodeSelectionView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _nodeX = NULL;
        _nodeY = NULL;
        _nodeCount = 0;
        _allocatedCount = 0;
        _internalSelectedNodes = [NSMutableIndexSet indexSet];
        _highlightedNodes = [NSMutableIndexSet indexSet];
        _highlightColor = [NSColor systemGreenColor];
        _selectionEnabled = YES;
        _colorDrawMode = @"Default";

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

- (void)highlightNodesForState:(NSString *)stateName withData:(XLStateData)data {
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
                if (i > 0) [_highlightedNodes addIndex:i - 1];
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
        _highlightColor = [NSColor systemGreenColor];
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
        NSInteger nodeNum = idx + 1;

        if (rangeStart < 0) {
            rangeStart = nodeNum;
            rangeEnd = nodeNum;
        } else if (nodeNum == rangeEnd + 1) {
            rangeEnd = nodeNum;
        } else {
            if (rangeStart == rangeEnd) {
                [ranges addObject:[NSString stringWithFormat:@"%ld", (long)rangeStart]];
            } else {
                [ranges addObject:[NSString stringWithFormat:@"%ld-%ld", (long)rangeStart, (long)rangeEnd]];
            }
            rangeStart = nodeNum;
            rangeEnd = nodeNum;
        }
    }];

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

    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(dirtyRect);

    [[NSColor separatorColor] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRect:bounds];
    [border stroke];

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

    for (NSInteger i = 0; i < _nodeCount; i++) {
        CGFloat x = drawRect.origin.x + (_nodeX[i] * drawRect.size.width);
        CGFloat y = drawRect.origin.y + (_nodeY[i] * drawRect.size.height);

        if (NSPointInRect(NSMakePoint(x, y), selRect)) {
            [_internalSelectedNodes addIndex:i];
        }
    }

    [self setNeedsDisplay:YES];

    if ([_delegate respondsToSelector:@selector(stateNodeSelectionViewDidChangeSelection:)]) {
        [_delegate stateNodeSelectionViewDidChangeSelection:self];
    }
}

@end

#pragma mark - XLStateGridView

@interface XLStateGridView () {
    XLStateData *_stateData;
    NSInteger _stateCapacity;
}
@property (nonatomic, assign) NSInteger internalStateCount;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@end

@implementation XLStateGridView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _stateType = XLStateTypeNodeRanges;
        _customColorsEnabled = NO;
        _selectedStateIndex = -1;
        _internalStateCount = 0;
        _stateCapacity = 100;
        _stateData = (XLStateData *)calloc(_stateCapacity, sizeof(XLStateData));

        [self setupUI];
    }
    return self;
}

- (void)dealloc {
    if (_stateData) free(_stateData);
}

- (NSInteger)stateCount {
    return _internalStateCount;
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

    // State name column
    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameCol.title = @"State";
    nameCol.width = 150;
    nameCol.editable = YES;
    [_tableView addTableColumn:nameCol];

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

- (void)ensureCapacity:(NSInteger)count {
    if (count > _stateCapacity) {
        NSInteger newCapacity = count * 2;
        XLStateData *newData = (XLStateData *)calloc(newCapacity, sizeof(XLStateData));
        if (_stateData) {
            memcpy(newData, _stateData, _stateCapacity * sizeof(XLStateData));
            free(_stateData);
        }
        _stateData = newData;
        _stateCapacity = newCapacity;
    }
}

- (XLStateData)stateDataAtIndex:(NSInteger)index {
    if (index < 0 || index >= _internalStateCount) {
        XLStateData empty = {0};
        return empty;
    }
    return _stateData[index];
}

- (void)setStateData:(XLStateData)data atIndex:(NSInteger)index {
    if (index < 0 || index >= _internalStateCount) return;
    _stateData[index] = data;
    [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:index]
                          columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 3)]];
}

- (void)addStateWithName:(NSString *)name {
    [self ensureCapacity:_internalStateCount + 1];

    XLStateData newState = {0};
    strlcpy(newState.stateName, [name UTF8String], sizeof(newState.stateName));
    newState.active = YES;

    _stateData[_internalStateCount] = newState;
    _internalStateCount++;

    [_tableView reloadData];

    if ([_delegate respondsToSelector:@selector(stateGridViewDidChange:)]) {
        [_delegate stateGridViewDidChange:self];
    }
}

- (void)insertStateAtIndex:(NSInteger)index withName:(NSString *)name {
    if (index < 0 || index > _internalStateCount) return;

    [self ensureCapacity:_internalStateCount + 1];

    // Shift existing states
    for (NSInteger i = _internalStateCount; i > index; i--) {
        _stateData[i] = _stateData[i - 1];
    }

    XLStateData newState = {0};
    strlcpy(newState.stateName, [name UTF8String], sizeof(newState.stateName));
    newState.active = YES;

    _stateData[index] = newState;
    _internalStateCount++;

    [_tableView reloadData];

    if ([_delegate respondsToSelector:@selector(stateGridViewDidChange:)]) {
        [_delegate stateGridViewDidChange:self];
    }
}

- (void)removeStateAtIndex:(NSInteger)index {
    if (index < 0 || index >= _internalStateCount) return;

    for (NSInteger i = index; i < _internalStateCount - 1; i++) {
        _stateData[i] = _stateData[i + 1];
    }
    _internalStateCount--;

    [_tableView reloadData];

    if ([_delegate respondsToSelector:@selector(stateGridViewDidChange:)]) {
        [_delegate stateGridViewDidChange:self];
    }
}

- (void)moveStateAtIndex:(NSInteger)from toIndex:(NSInteger)to {
    if (from < 0 || from >= _internalStateCount) return;
    if (to < 0 || to >= _internalStateCount) return;
    if (from == to) return;

    XLStateData temp = _stateData[from];

    if (from < to) {
        for (NSInteger i = from; i < to; i++) {
            _stateData[i] = _stateData[i + 1];
        }
    } else {
        for (NSInteger i = from; i > to; i--) {
            _stateData[i] = _stateData[i - 1];
        }
    }

    _stateData[to] = temp;
    [_tableView reloadData];

    if ([_delegate respondsToSelector:@selector(stateGridViewDidChange:)]) {
        [_delegate stateGridViewDidChange:self];
    }
}

- (void)sortStates {
    // Simple bubble sort for state names
    for (NSInteger i = 0; i < _internalStateCount - 1; i++) {
        for (NSInteger j = 0; j < _internalStateCount - i - 1; j++) {
            if (strcmp(_stateData[j].stateName, _stateData[j + 1].stateName) > 0) {
                XLStateData temp = _stateData[j];
                _stateData[j] = _stateData[j + 1];
                _stateData[j + 1] = temp;
            }
        }
    }

    [_tableView reloadData];

    if ([_delegate respondsToSelector:@selector(stateGridViewDidChange:)]) {
        [_delegate stateGridViewDidChange:self];
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _internalStateCount;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= _internalStateCount) return nil;

    NSString *identifier = tableColumn.identifier;

    if ([identifier isEqualToString:@"name"]) {
        return [NSString stringWithUTF8String:_stateData[row].stateName];
    } else if ([identifier isEqualToString:@"nodes"]) {
        return [NSString stringWithUTF8String:_stateData[row].nodeData];
    }

    return nil;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= _internalStateCount) return;

    NSString *identifier = tableColumn.identifier;

    if ([identifier isEqualToString:@"name"]) {
        NSString *value = object;
        strlcpy(_stateData[row].stateName, [value UTF8String] ?: "", sizeof(_stateData[row].stateName));
    } else if ([identifier isEqualToString:@"nodes"]) {
        NSString *value = object;
        strlcpy(_stateData[row].nodeData, [value UTF8String] ?: "", sizeof(_stateData[row].nodeData));
    }

    if ([_delegate respondsToSelector:@selector(stateGridViewDidChange:)]) {
        [_delegate stateGridViewDidChange:self];
    }
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    _selectedStateIndex = _tableView.selectedRow;

    if ([_delegate respondsToSelector:@selector(stateGridView:didSelectState:)]) {
        [_delegate stateGridView:self didSelectState:_selectedStateIndex];
    }
}

@end

#pragma mark - XLModelStateWindow

@interface XLModelStateWindow () <XLStateGridDelegate, XLStateNodeSelectionDelegate>
@property (nonatomic, copy) NSString *modelName;
@property (nonatomic, copy) XLModelStateCompletion completion;
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSTabView *stateTypeTabView;
@property (nonatomic, strong) NSPopUpButton *stateNamePopup;
@property (nonatomic, strong) NSPopUpButton *colorDrawPopup;
@property (nonatomic, strong) XLStateGridView *stateGrid;
@property (nonatomic, strong) XLStateNodeSelectionView *nodeSelectionView;
@property (nonatomic, strong) NSButton *outputToLightsCheckbox;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *stateDataDict;
@property (nonatomic, assign) BOOL hasUnsavedChanges;
@end

@implementation XLModelStateWindow

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
        _stateDataDict = [NSMutableDictionary dictionary];
        _hasUnsavedChanges = NO;
        _outputToLights = NO;
        _needsReload = NO;

        window.title = [NSString stringWithFormat:@"Model States - %@", modelName];
        window.delegate = (id<NSWindowDelegate>)self;
        [window center];

        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    // Top bar with state selection
    NSView *topBar = [[NSView alloc] initWithFrame:NSMakeRect(0, kWindowHeight - 50, kWindowWidth, 50)];
    topBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

    NSTextField *label = [NSTextField labelWithString:@"State Definition:"];
    label.frame = NSMakeRect(10, 15, 100, 20);
    [topBar addSubview:label];

    _stateNamePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(115, 12, 200, 26) pullsDown:NO];
    [_stateNamePopup addItemWithTitle:@"Default"];
    _stateNamePopup.target = self;
    _stateNamePopup.action = @selector(stateNameChanged:);
    [topBar addSubview:_stateNamePopup];

    NSButton *addButton = [[NSButton alloc] initWithFrame:NSMakeRect(320, 12, 30, 26)];
    addButton.bezelStyle = NSBezelStyleRounded;
    addButton.title = @"+";
    addButton.target = self;
    addButton.action = @selector(addStateDefinition:);
    [topBar addSubview:addButton];

    NSButton *deleteButton = [[NSButton alloc] initWithFrame:NSMakeRect(355, 12, 30, 26)];
    deleteButton.bezelStyle = NSBezelStyleRounded;
    deleteButton.title = @"-";
    deleteButton.target = self;
    deleteButton.action = @selector(deleteStateDefinition:);
    [topBar addSubview:deleteButton];

    NSButton *importButton = [[NSButton alloc] initWithFrame:NSMakeRect(400, 12, 70, 26)];
    importButton.bezelStyle = NSBezelStyleRounded;
    importButton.title = @"Import";
    importButton.target = self;
    importButton.action = @selector(importStates:);
    [topBar addSubview:importButton];

    NSButton *seg7Button = [[NSButton alloc] initWithFrame:NSMakeRect(475, 12, 90, 26)];
    seg7Button.bezelStyle = NSBezelStyleRounded;
    seg7Button.title = @"7 Segment";
    seg7Button.target = self;
    seg7Button.action = @selector(import7Segment:);
    [topBar addSubview:seg7Button];

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

    // Left side - state type tabs and grid
    NSView *leftPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, kWindowHeight - 100)];

    _stateTypeTabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 500, kWindowHeight - 100)];
    _stateTypeTabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Single Node tab
    NSTabViewItem *singleNodeTab = [[NSTabViewItem alloc] initWithIdentifier:@"singleNode"];
    singleNodeTab.label = @"Single Node";
    [_stateTypeTabView addTabViewItem:singleNodeTab];

    // Node Ranges tab
    NSTabViewItem *nodeRangesTab = [[NSTabViewItem alloc] initWithIdentifier:@"nodeRanges"];
    nodeRangesTab.label = @"Node Ranges";

    _stateGrid = [[XLStateGridView alloc] initWithFrame:NSMakeRect(0, 0, 480, 400)];
    _stateGrid.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _stateGrid.delegate = self;
    [nodeRangesTab.view addSubview:_stateGrid];

    // Add state button in tab
    NSButton *addStateButton = [[NSButton alloc] initWithFrame:NSMakeRect(10, 410, 100, 26)];
    addStateButton.bezelStyle = NSBezelStyleRounded;
    addStateButton.title = @"Add State";
    addStateButton.target = self;
    addStateButton.action = @selector(addState:);
    [nodeRangesTab.view addSubview:addStateButton];

    [_stateTypeTabView addTabViewItem:nodeRangesTab];

    [leftPanel addSubview:_stateTypeTabView];
    [_splitView addSubview:leftPanel];

    // Right side - model preview
    NSView *rightPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, kWindowHeight - 100)];

    // Color draw mode popup
    NSTextField *colorLabel = [NSTextField labelWithString:@"Color Draw:"];
    colorLabel.frame = NSMakeRect(10, kWindowHeight - 130, 80, 20);
    [rightPanel addSubview:colorLabel];

    _colorDrawPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(90, kWindowHeight - 133, 120, 26) pullsDown:NO];
    [_colorDrawPopup addItemWithTitle:@"Default"];
    [_colorDrawPopup addItemWithTitle:@"State Color"];
    [_colorDrawPopup addItemWithTitle:@"Model Color"];
    _colorDrawPopup.target = self;
    _colorDrawPopup.action = @selector(colorDrawModeChanged:);
    [rightPanel addSubview:_colorDrawPopup];

    _nodeSelectionView = [[XLStateNodeSelectionView alloc] initWithFrame:NSMakeRect(10, 10, 380, 380)];
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

- (void)showWithCompletion:(XLModelStateCompletion)completion {
    _completion = [completion copy];
    [self showWindow:nil];
}

- (void)stateNameChanged:(NSPopUpButton *)sender {
    // Load state data for selected definition
}

- (void)addStateDefinition:(NSButton *)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"New State Definition";
    alert.informativeText = @"Enter a name for the new state definition:";

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    input.stringValue = @"";
    alert.accessoryView = input;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn && input.stringValue.length > 0) {
            [self->_stateNamePopup addItemWithTitle:input.stringValue];
            [self->_stateNamePopup selectItemWithTitle:input.stringValue];
            self->_hasUnsavedChanges = YES;
        }
    }];
}

- (void)deleteStateDefinition:(NSButton *)sender {
    NSString *selected = _stateNamePopup.selectedItem.title;
    if ([selected isEqualToString:@"Default"]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Cannot Delete";
        alert.informativeText = @"The Default state definition cannot be deleted.";
        [alert runModal];
        return;
    }

    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Delete State Definition";
    confirm.informativeText = [NSString stringWithFormat:@"Are you sure you want to delete '%@'?", selected];
    [confirm addButtonWithTitle:@"Delete"];
    [confirm addButtonWithTitle:@"Cancel"];

    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [self->_stateNamePopup removeItemWithTitle:selected];
            [self->_stateDataDict removeObjectForKey:selected];
            self->_hasUnsavedChanges = YES;
        }
    }];
}

- (void)addState:(NSButton *)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"New State";
    alert.informativeText = @"Enter a name for the new state:";

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    input.stringValue = @"";
    alert.accessoryView = input;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn && input.stringValue.length > 0) {
            [self->_stateGrid addStateWithName:input.stringValue];
            self->_hasUnsavedChanges = YES;
        }
    }];
}

- (void)importStates:(NSButton *)sender {
    // Import from file or other model
}

- (void)import7Segment:(NSButton *)sender {
    [self import7SegmentStates];
}

- (void)import7SegmentStates {
    // Add standard 7-segment display states (0-9, A-F, and segments a-g)
    NSArray *digits = @[@"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9",
                        @"A", @"b", @"C", @"d", @"E", @"F"];

    for (NSString *digit in digits) {
        [_stateGrid addStateWithName:digit];
    }

    // Add individual segments
    NSArray *segments = @[@"a", @"b", @"c", @"d", @"e", @"f", @"g", @"dp"];
    for (NSString *segment in segments) {
        [_stateGrid addStateWithName:[NSString stringWithFormat:@"Seg-%@", segment]];
    }

    _hasUnsavedChanges = YES;
}

- (void)outputToLightsChanged:(NSButton *)sender {
    _outputToLights = (sender.state == NSControlStateValueOn);
}

- (void)colorDrawModeChanged:(NSPopUpButton *)sender {
    _nodeSelectionView.colorDrawMode = sender.selectedItem.title;
    [_nodeSelectionView setNeedsDisplay:YES];
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

- (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)stateInfo {
    return [_stateDataDict copy];
}

- (void)setStateInfo:(NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)info {
    [_stateDataDict removeAllObjects];
    [_stateDataDict addEntriesFromDictionary:info];

    [_stateNamePopup removeAllItems];
    NSArray *sortedKeys = [[info allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sortedKeys) {
        [_stateNamePopup addItemWithTitle:key];
    }

    if (_stateNamePopup.numberOfItems == 0) {
        [_stateNamePopup addItemWithTitle:@"Default"];
    }
}

#pragma mark - XLStateGridDelegate

- (void)stateGridViewDidChange:(XLStateGridView *)view {
    _hasUnsavedChanges = YES;
}

- (void)stateGridView:(XLStateGridView *)view didSelectState:(NSInteger)index {
    XLStateData data = [view stateDataAtIndex:index];
    [_nodeSelectionView highlightNodesForState:[NSString stringWithUTF8String:data.stateName]
                                      withData:data];
}

#pragma mark - XLStateNodeSelectionDelegate

- (void)stateNodeSelectionViewDidChangeSelection:(XLStateNodeSelectionView *)view {
    NSInteger selectedState = _stateGrid.selectedStateIndex;
    if (selectedState < 0) return;

    NSString *rangeString = [view selectedNodesAsRangeString];
    XLStateData data = [_stateGrid stateDataAtIndex:selectedState];
    strlcpy(data.nodeData, [rangeString UTF8String], sizeof(data.nodeData));
    [_stateGrid setStateData:data atIndex:selectedState];

    _hasUnsavedChanges = YES;
}

@end
