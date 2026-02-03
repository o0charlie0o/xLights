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

static const CGFloat kWindowWidth = 1000.0;
static const CGFloat kWindowHeight = 700.0;

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
        _selectionColor = [NSColor systemYellowColor];
        _selectionEnabled = YES;

        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor controlBackgroundColor] CGColor];
        self.layer.borderWidth = 1;
        self.layer.borderColor = [[NSColor separatorColor] CGColor];
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

    // Draw background
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(dirtyRect);

    // Draw nodes
    CGFloat nodeSize = MAX(4, MIN(10, bounds.size.width / MAX(1, sqrt(_nodeCount))));

    for (NSInteger i = 0; i < _nodeCount; i++) {
        CGFloat x = drawRect.origin.x + _nodeX[i] * drawRect.size.width;
        CGFloat y = drawRect.origin.y + _nodeY[i] * drawRect.size.height;

        NSRect nodeRect = NSMakeRect(x - nodeSize/2, y - nodeSize/2, nodeSize, nodeSize);

        if ([_selectedNodes containsIndex:i]) {
            [_selectionColor setFill];
        } else {
            [[NSColor tertiaryLabelColor] setFill];
        }

        [[NSBezierPath bezierPathWithOvalInRect:nodeRect] fill];
    }

    // Draw selection rectangle if dragging
    if (_isDragging) {
        [[NSColor selectedContentBackgroundColor] setStroke];
        NSBezierPath *selRect = [NSBezierPath bezierPathWithRect:
            NSMakeRect(MIN(_dragStart.x, _dragEnd.x),
                      MIN(_dragStart.y, _dragEnd.y),
                      fabs(_dragEnd.x - _dragStart.x),
                      fabs(_dragEnd.y - _dragStart.y))];
        selRect.lineWidth = 1;
        CGFloat pattern[] = {4, 4};
        [selRect setLineDash:pattern count:2 phase:0];
        [selRect stroke];
    }
}

- (void)clearSelection {
    [_selectedNodes removeAllIndexes];
    [self setNeedsDisplay:YES];
    [_delegate nodeSelectionViewDidChangeSelection:self];
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

- (void)mouseDown:(NSEvent *)event {
    if (!_selectionEnabled) return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    BOOL shiftDown = (event.modifierFlags & NSEventModifierFlagShift) != 0;

    if (!shiftDown) {
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

    // If small area, do single-node selection
    if (selRect.size.width < 5 && selRect.size.height < 5) {
        selRect = NSInsetRect(selRect, -10, -10);
    }

    // Find nodes in selection
    for (NSInteger i = 0; i < _nodeCount; i++) {
        CGFloat x = drawRect.origin.x + _nodeX[i] * drawRect.size.width;
        CGFloat y = drawRect.origin.y + _nodeY[i] * drawRect.size.height;

        if (NSPointInRect(NSMakePoint(x, y), selRect)) {
            [_selectedNodes addIndex:i];
        }
    }

    [self setNeedsDisplay:YES];
    [_delegate nodeSelectionViewDidChangeSelection:self];
}

- (BOOL)acceptsFirstResponder { return YES; }

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
@end

@implementation XLStrandGridView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _strands = [NSMutableArray array];
        _strandCount = 0;
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

    NSTableColumn *strandColumn = [[NSTableColumn alloc] initWithIdentifier:@"strand"];
    strandColumn.title = @"Strand";
    strandColumn.width = 60;
    [_tableView addTableColumn:strandColumn];

    NSTableColumn *nodesColumn = [[NSTableColumn alloc] initWithIdentifier:@"nodes"];
    nodesColumn.title = @"Node Ranges";
    nodesColumn.width = 300;
    [_tableView addTableColumn:nodesColumn];

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
    [_delegate strandGridViewDidChange:self];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _strands.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"strand"]) {
        return [NSString stringWithFormat:@"Strand %ld", (long)(row + 1)];
    } else {
        return (row < (NSInteger)_strands.count) ? _strands[row] : @"";
    }
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

    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameCol.title = @"Name";
    nameCol.width = 180;
    [_subModelList addTableColumn:nameCol];

    scrollView.documentView = _subModelList;
    [stack addArrangedSubview:scrollView];

    // Buttons
    NSStackView *buttonRow = [[NSStackView alloc] init];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 4;

    NSButton *addBtn = [NSButton buttonWithTitle:@"Add" target:self action:@selector(addSubModelClicked:)];
    NSButton *removeBtn = [NSButton buttonWithTitle:@"Remove" target:self action:@selector(removeSubModelClicked:)];
    NSButton *copyBtn = [NSButton buttonWithTitle:@"Copy" target:self action:@selector(copySubModelClicked:)];
    NSButton *importBtn = [NSButton buttonWithTitle:@"Import..." target:self action:@selector(importClicked:)];
    NSButton *exportBtn = [NSButton buttonWithTitle:@"Export..." target:self action:@selector(exportClicked:)];

    [buttonRow addArrangedSubview:addBtn];
    [buttonRow addArrangedSubview:removeBtn];
    [buttonRow addArrangedSubview:copyBtn];
    [buttonRow addArrangedSubview:importBtn];
    [buttonRow addArrangedSubview:exportBtn];

    [stack addArrangedSubview:buttonRow];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:8],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-8],
    ]];

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

    NSTextField *title = [NSTextField labelWithString:@"Model Preview"];
    title.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:title];

    _nodeView = [[XLNodeSelectionView alloc] initWithFrame:NSMakeRect(0, 0, 250, 250)];
    _nodeView.translatesAutoresizingMaskIntoConstraints = NO;
    _nodeView.delegate = self;
    [stack addArrangedSubview:_nodeView];

    [NSLayoutConstraint activateConstraints:@[
        [_nodeView.heightAnchor constraintGreaterThanOrEqualToConstant:200],
    ]];

    // Selection info
    NSTextField *selectionLabel = [NSTextField labelWithString:@"Click and drag to select nodes"];
    selectionLabel.textColor = [NSColor secondaryLabelColor];
    selectionLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:selectionLabel];

    NSButton *useSelectionBtn = [NSButton buttonWithTitle:@"Use Selection" target:self action:@selector(useSelectionClicked:)];
    [stack addArrangedSubview:useSelectionBtn];

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
    if (row >= 0 && row < _subModelCount) {
        return [NSString stringWithUTF8String:_subModels[row].name];
    }
    return @"";
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    _selectedSubModelIndex = _subModelList.selectedRow;
    [self loadSelectedSubModel];
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

- (void)importClicked:(id)sender {
    // Import from file - implementation would open a file picker
}

- (void)exportClicked:(id)sender {
    // Export to file - implementation would open a save panel
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

- (void)moveStrandUpClicked:(id)sender {
    // Would need selected row tracking in strand grid
}

- (void)moveStrandDownClicked:(id)sender {
    // Would need selected row tracking in strand grid
}

- (void)reverseStrandClicked:(id)sender {
    // Reverse the node order in selected strand
}

- (void)useSelectionClicked:(id)sender {
    NSString *rangeString = [_nodeView selectedNodesAsRangeString];
    if (rangeString.length > 0 && _strandGrid.strandCount > 0) {
        [_strandGrid setStrand:rangeString atIndex:0];
        _hasChanges = YES;
    }
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
    // Update display
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
}

@end
