/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLControllerModelWindow.h"

static const CGFloat kWindowWidth = 1200.0;
static const CGFloat kWindowHeight = 800.0;
static const CGFloat kDefaultBoxScale = 1.0;
static const CGFloat kDefaultFontScale = 1.0;

#pragma mark - XLControllerPortsView

@interface XLControllerPortsView () <NSDraggingDestination> {
    XLPortConfig *_portConfigs;
    XLModelAssignment **_portModels;
    NSInteger *_portModelCounts;
    NSInteger _portCapacity;
}
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@property (nonatomic, assign) NSInteger hoveredPort;
@property (nonatomic, assign) NSInteger selectedPort;
@property (nonatomic, copy) NSString *selectedModel;
@property (nonatomic, assign) NSPoint dropIndicatorPoint;
@property (nonatomic, assign) BOOL showDropIndicator;
@end

@implementation XLControllerPortsView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _portCount = 0;
        _portCapacity = XL_MAX_PORTS;
        _displayScale = kDefaultBoxScale;
        _fontScale = kDefaultFontScale;
        _scrollOffset = NSZeroPoint;
        _hoveredPort = -1;
        _selectedPort = -1;

        // Allocate port storage
        _portConfigs = (XLPortConfig *)calloc(_portCapacity, sizeof(XLPortConfig));
        _portModels = (XLModelAssignment **)calloc(_portCapacity, sizeof(XLModelAssignment *));
        _portModelCounts = (NSInteger *)calloc(_portCapacity, sizeof(NSInteger));

        for (NSInteger i = 0; i < _portCapacity; i++) {
            _portModels[i] = (XLModelAssignment *)calloc(XL_MAX_PORT_MODELS, sizeof(XLModelAssignment));
            _portModelCounts[i] = 0;
        }

        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];

        [self registerForDraggedTypes:@[NSPasteboardTypeString]];
    }
    return self;
}

- (void)dealloc {
    if (_portConfigs) free(_portConfigs);
    if (_portModelCounts) free(_portModelCounts);
    if (_portModels) {
        for (NSInteger i = 0; i < _portCapacity; i++) {
            if (_portModels[i]) free(_portModels[i]);
        }
        free(_portModels);
    }
}

- (void)setPortConfig:(XLPortConfig)config atIndex:(NSInteger)index {
    if (index < 0 || index >= _portCapacity) return;
    _portConfigs[index] = config;
    [self setNeedsDisplay:YES];
}

- (XLPortConfig)portConfigAtIndex:(NSInteger)index {
    if (index < 0 || index >= _portCapacity) {
        XLPortConfig empty = {0};
        return empty;
    }
    return _portConfigs[index];
}

- (void)setModels:(const XLModelAssignment *)models count:(NSInteger)count forPort:(NSInteger)port {
    if (port < 0 || port >= _portCapacity) return;

    _portModelCounts[port] = MIN(count, XL_MAX_PORT_MODELS);
    if (count > 0 && models) {
        memcpy(_portModels[port], models, _portModelCounts[port] * sizeof(XLModelAssignment));
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
                                                        NSTrackingMouseEnteredAndExited |
                                                        NSTrackingActiveInKeyWindow)
                                                  owner:self
                                               userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    // Background
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(dirtyRect);

    CGFloat portHeight = 60 * _displayScale;
    CGFloat portSpacing = 10 * _displayScale;
    CGFloat modelBoxWidth = 100 * _displayScale;
    CGFloat modelBoxHeight = 40 * _displayScale;
    CGFloat leftMargin = 80 * _displayScale;

    NSDictionary *labelAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 * _fontScale],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };

    NSDictionary *modelAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10 * _fontScale],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };

    for (NSInteger p = 0; p < _portCount; p++) {
        CGFloat y = self.bounds.size.height - (p + 1) * (portHeight + portSpacing) - _scrollOffset.y;

        if (y + portHeight < 0 || y > self.bounds.size.height) continue;

        XLPortConfig *port = &_portConfigs[p];

        // Port background
        NSRect portRect = NSMakeRect(0, y, self.bounds.size.width, portHeight);
        if (p == _selectedPort) {
            [[NSColor selectedContentBackgroundColor] setFill];
        } else if (p == _hoveredPort) {
            [[[NSColor controlAccentColor] colorWithAlphaComponent:0.1] setFill];
        } else {
            [[NSColor controlBackgroundColor] setFill];
        }
        NSRectFill(portRect);

        // Port border
        [[NSColor separatorColor] setStroke];
        [NSBezierPath strokeRect:portRect];

        // Port label
        NSString *portLabel = [NSString stringWithFormat:@"Port %d\n%s",
                              port->portNumber, port->protocol];
        [portLabel drawInRect:NSMakeRect(5, y + 5, leftMargin - 10, portHeight - 10)
               withAttributes:labelAttrs];

        // Draw models on this port
        CGFloat modelX = leftMargin;
        for (NSInteger m = 0; m < _portModelCounts[p]; m++) {
            XLModelAssignment *model = &_portModels[p][m];

            NSRect modelRect = NSMakeRect(modelX - _scrollOffset.x, y + 10,
                                         modelBoxWidth, modelBoxHeight);

            // Model box
            if (model->hasWarning) {
                [[NSColor systemYellowColor] setFill];
            } else {
                [[NSColor systemBlueColor] setFill];
            }
            NSBezierPath *modelPath = [NSBezierPath bezierPathWithRoundedRect:modelRect
                                                                      xRadius:4 yRadius:4];
            [modelPath fill];

            // Model name
            NSString *modelName = [NSString stringWithUTF8String:model->modelName];
            NSString *channelInfo = [NSString stringWithFormat:@"Ch %d", model->startChannel];

            NSRect nameRect = NSInsetRect(modelRect, 4, 4);
            [modelName drawInRect:NSMakeRect(nameRect.origin.x, nameRect.origin.y + nameRect.size.height/2,
                                            nameRect.size.width, nameRect.size.height/2)
                   withAttributes:modelAttrs];
            [channelInfo drawInRect:NSMakeRect(nameRect.origin.x, nameRect.origin.y,
                                              nameRect.size.width, nameRect.size.height/2)
                     withAttributes:modelAttrs];

            modelX += modelBoxWidth + 5;
        }
    }

    // Drop indicator
    if (_showDropIndicator) {
        [[NSColor controlAccentColor] setStroke];
        NSBezierPath *indicator = [NSBezierPath bezierPath];
        [indicator moveToPoint:NSMakePoint(_dropIndicatorPoint.x - 10, _dropIndicatorPoint.y)];
        [indicator lineToPoint:NSMakePoint(_dropIndicatorPoint.x + 10, _dropIndicatorPoint.y)];
        indicator.lineWidth = 3;
        [indicator stroke];
    }
}

#pragma mark - Mouse Handling

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    NSInteger port = [self portAtPoint:point];
    NSString *model = [self modelAtPoint:point];

    if (model) {
        _selectedModel = model;
        _selectedPort = port;
        [_delegate controllerPortsView:self didSelectModel:model onPort:port];
    } else if (port >= 0) {
        _selectedPort = port;
        _selectedModel = nil;
        [_delegate controllerPortsView:self didSelectPort:port];
    }

    [self setNeedsDisplay:YES];
}

- (void)rightMouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger port = [self portAtPoint:point];
    NSString *model = [self modelAtPoint:point];

    if (model) {
        [_delegate controllerPortsView:self requestContextMenuForModel:model atPoint:point];
    } else if (port >= 0) {
        [_delegate controllerPortsView:self requestContextMenuForPort:port atPoint:point];
    }
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger port = [self portAtPoint:point];

    if (port != _hoveredPort) {
        _hoveredPort = port;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseExited:(NSEvent *)event {
    _hoveredPort = -1;
    [self setNeedsDisplay:YES];
}

- (NSInteger)portAtPoint:(NSPoint)point {
    CGFloat portHeight = 60 * _displayScale;
    CGFloat portSpacing = 10 * _displayScale;

    for (NSInteger p = 0; p < _portCount; p++) {
        CGFloat y = self.bounds.size.height - (p + 1) * (portHeight + portSpacing) - _scrollOffset.y;
        if (point.y >= y && point.y <= y + portHeight) {
            return p;
        }
    }
    return -1;
}

- (NSString *)modelAtPoint:(NSPoint)point {
    NSInteger port = [self portAtPoint:point];
    if (port < 0) return nil;

    CGFloat portHeight = 60 * _displayScale;
    CGFloat portSpacing = 10 * _displayScale;
    CGFloat modelBoxWidth = 100 * _displayScale;
    CGFloat leftMargin = 80 * _displayScale;

    CGFloat y = self.bounds.size.height - (port + 1) * (portHeight + portSpacing) - _scrollOffset.y;
    CGFloat modelX = leftMargin;

    for (NSInteger m = 0; m < _portModelCounts[port]; m++) {
        NSRect modelRect = NSMakeRect(modelX - _scrollOffset.x, y + 10,
                                     modelBoxWidth, 40 * _displayScale);
        if (NSPointInRect(point, modelRect)) {
            return [NSString stringWithUTF8String:_portModels[port][m].modelName];
        }
        modelX += modelBoxWidth + 5;
    }

    return nil;
}

#pragma mark - Drag and Drop

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return NSDragOperationMove;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
    NSInteger port = [self portAtPoint:point];

    if (port >= 0) {
        _showDropIndicator = YES;
        CGFloat portHeight = 60 * _displayScale;
        CGFloat portSpacing = 10 * _displayScale;
        CGFloat y = self.bounds.size.height - (port + 1) * (portHeight + portSpacing) - _scrollOffset.y;
        _dropIndicatorPoint = NSMakePoint(point.x, y + portHeight / 2);
        [self setNeedsDisplay:YES];
        return NSDragOperationMove;
    }

    _showDropIndicator = NO;
    [self setNeedsDisplay:YES];
    return NSDragOperationNone;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    _showDropIndicator = NO;
    [self setNeedsDisplay:YES];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    _showDropIndicator = NO;

    NSPasteboard *pb = sender.draggingPasteboard;
    NSString *modelName = [pb stringForType:NSPasteboardTypeString];

    NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
    NSInteger port = [self portAtPoint:point];

    if (port >= 0 && modelName) {
        [_delegate controllerPortsView:self didDropModel:modelName onPort:port atPosition:0];
        return YES;
    }

    return NO;
}

@end

#pragma mark - XLUnassignedModelsView

@interface XLUnassignedModelsView () <NSDraggingSource>
@property (nonatomic, strong) NSMutableArray<NSString *> *models;
@property (nonatomic, strong) NSMutableArray<NSString *> *filteredModels;
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@property (nonatomic, assign) NSInteger hoveredIndex;
@property (nonatomic, assign) NSInteger selectedIndex;
@end

@implementation XLUnassignedModelsView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _models = [NSMutableArray array];
        _filteredModels = [NSMutableArray array];
        _filterString = @"";
        _hideOtherControllerModels = NO;
        _scrollOffset = 0;
        _hoveredIndex = -1;
        _selectedIndex = -1;

        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor controlBackgroundColor] CGColor];
    }
    return self;
}

- (void)setModelNames:(NSArray<NSString *> *)names {
    [_models removeAllObjects];
    [_models addObjectsFromArray:names];
    [self applyFilter];
}

- (void)setFilterString:(NSString *)filterString {
    _filterString = [filterString copy];
    [self applyFilter];
}

- (void)applyFilter {
    [_filteredModels removeAllObjects];

    for (NSString *model in _models) {
        if (_filterString.length == 0 ||
            [model localizedCaseInsensitiveContainsString:_filterString]) {
            [_filteredModels addObject:model];
        }
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
                                                        NSTrackingMouseEnteredAndExited |
                                                        NSTrackingActiveInKeyWindow)
                                                  owner:self
                                               userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(dirtyRect);

    CGFloat rowHeight = 24;
    CGFloat y = self.bounds.size.height - rowHeight + _scrollOffset;

    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };

    for (NSInteger i = 0; i < (NSInteger)_filteredModels.count; i++) {
        if (y + rowHeight < 0) {
            y -= rowHeight;
            continue;
        }
        if (y > self.bounds.size.height) break;

        NSRect rowRect = NSMakeRect(0, y, self.bounds.size.width, rowHeight);

        if (i == _selectedIndex) {
            [[NSColor selectedContentBackgroundColor] setFill];
            NSRectFill(rowRect);
        } else if (i == _hoveredIndex) {
            [[[NSColor controlAccentColor] colorWithAlphaComponent:0.1] setFill];
            NSRectFill(rowRect);
        }

        [_filteredModels[i] drawInRect:NSInsetRect(rowRect, 8, 2) withAttributes:attrs];

        y -= rowHeight;
    }
}

#pragma mark - Mouse Handling

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger index = [self indexAtPoint:point];

    _selectedIndex = index;
    [self setNeedsDisplay:YES];

    if (index >= 0 && index < (NSInteger)_filteredModels.count) {
        [_delegate unassignedModelsView:self didSelectModel:_filteredModels[index]];

        if (event.clickCount == 2) {
            [_delegate unassignedModelsView:self didDoubleClickModel:_filteredModels[index]];
        }
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (_selectedIndex < 0 || _selectedIndex >= (NSInteger)_filteredModels.count) return;

    NSString *modelName = _filteredModels[_selectedIndex];

    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setString:modelName forType:NSPasteboardTypeString];

    NSDraggingItem *dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:pbItem];

    NSRect rowRect = NSMakeRect(0, self.bounds.size.height - (_selectedIndex + 1) * 24 + _scrollOffset,
                               self.bounds.size.width, 24);
    [dragItem setDraggingFrame:rowRect contents:nil];

    [self beginDraggingSessionWithItems:@[dragItem] event:event source:self];

    [_delegate unassignedModelsView:self didBeginDragForModel:modelName];
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger index = [self indexAtPoint:point];

    if (index != _hoveredIndex) {
        _hoveredIndex = index;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseExited:(NSEvent *)event {
    _hoveredIndex = -1;
    [self setNeedsDisplay:YES];
}

- (NSInteger)indexAtPoint:(NSPoint)point {
    CGFloat rowHeight = 24;
    CGFloat y = self.bounds.size.height - point.y + _scrollOffset;
    return (NSInteger)(y / rowHeight);
}

#pragma mark - NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationMove;
}

@end

#pragma mark - XLControllerModelWindow

@interface XLControllerModelWindow () <XLControllerPortsViewDelegate, XLUnassignedModelsViewDelegate>

@property (nonatomic, copy) NSString *controllerName;
@property (nonatomic, strong) XLControllerPortsView *portsView;
@property (nonatomic, strong) XLUnassignedModelsView *modelsView;
@property (nonatomic, strong) NSScrollView *portsScrollView;
@property (nonatomic, strong) NSScrollView *modelsScrollView;
@property (nonatomic, strong) NSSlider *boxScaleSlider;
@property (nonatomic, strong) NSSlider *fontScaleSlider;
@property (nonatomic, strong) NSTextField *statusField;
@property (nonatomic, strong) NSButton *hideOtherCheckbox;

@property (nonatomic, copy) XLControllerModelCompletion completion;
@property (nonatomic, assign) BOOL hasChanges;

@end

@implementation XLControllerModelWindow

- (instancetype)initWithControllerName:(NSString *)controllerName {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowWidth, kWindowHeight)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = [NSString stringWithFormat:@"Controller Visualizer: %@", controllerName];
    window.minSize = NSMakeSize(900, 600);

    self = [super initWithWindow:window];
    if (self) {
        _controllerName = [controllerName copy];
        _hasChanges = NO;

        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSView *contentView = self.window.contentView;

    // Top toolbar
    NSStackView *toolbar = [[NSStackView alloc] init];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 16;
    toolbar.edgeInsets = NSEdgeInsetsMake(8, 12, 8, 12);
    [contentView addSubview:toolbar];

    // Scale controls
    NSTextField *boxLabel = [NSTextField labelWithString:@"Box Scale:"];
    _boxScaleSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _boxScaleSlider.minValue = 0.5;
    _boxScaleSlider.maxValue = 2.0;
    _boxScaleSlider.floatValue = 1.0;
    _boxScaleSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [_boxScaleSlider.widthAnchor constraintEqualToConstant:100].active = YES;
    [_boxScaleSlider setTarget:self];
    [_boxScaleSlider setAction:@selector(scaleChanged:)];

    NSTextField *fontLabel = [NSTextField labelWithString:@"Font Scale:"];
    _fontScaleSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _fontScaleSlider.minValue = 0.5;
    _fontScaleSlider.maxValue = 2.0;
    _fontScaleSlider.floatValue = 1.0;
    _fontScaleSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [_fontScaleSlider.widthAnchor constraintEqualToConstant:100].active = YES;
    [_fontScaleSlider setTarget:self];
    [_fontScaleSlider setAction:@selector(scaleChanged:)];

    [toolbar addArrangedSubview:boxLabel];
    [toolbar addArrangedSubview:_boxScaleSlider];
    [toolbar addArrangedSubview:fontLabel];
    [toolbar addArrangedSubview:_fontScaleSlider];

    // Print/Export buttons
    NSButton *printBtn = [NSButton buttonWithTitle:@"Print" target:self action:@selector(printClicked:)];
    NSButton *exportBtn = [NSButton buttonWithTitle:@"Export CSV" target:self action:@selector(exportCSVClicked:)];
    [toolbar addArrangedSubview:[[NSView alloc] init]]; // Spacer
    [toolbar addArrangedSubview:printBtn];
    [toolbar addArrangedSubview:exportBtn];

    // Main split view
    NSSplitView *splitView = [[NSSplitView alloc] initWithFrame:NSZeroRect];
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    splitView.vertical = YES;
    splitView.dividerStyle = NSSplitViewDividerStyleThin;
    [contentView addSubview:splitView];

    // Left: Controller ports
    NSView *leftPanel = [[NSView alloc] initWithFrame:NSZeroRect];

    _portsScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _portsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _portsScrollView.hasVerticalScroller = YES;
    _portsScrollView.hasHorizontalScroller = YES;
    _portsScrollView.borderType = NSNoBorder;

    _portsView = [[XLControllerPortsView alloc] initWithFrame:NSMakeRect(0, 0, 800, 1000)];
    _portsView.delegate = self;
    _portsScrollView.documentView = _portsView;

    [leftPanel addSubview:_portsScrollView];
    [NSLayoutConstraint activateConstraints:@[
        [_portsScrollView.leadingAnchor constraintEqualToAnchor:leftPanel.leadingAnchor],
        [_portsScrollView.trailingAnchor constraintEqualToAnchor:leftPanel.trailingAnchor],
        [_portsScrollView.topAnchor constraintEqualToAnchor:leftPanel.topAnchor],
        [_portsScrollView.bottomAnchor constraintEqualToAnchor:leftPanel.bottomAnchor],
    ]];

    [splitView addArrangedSubview:leftPanel];

    // Right: Unassigned models
    NSView *rightPanel = [[NSView alloc] initWithFrame:NSZeroRect];

    NSTextField *modelsTitle = [NSTextField labelWithString:@"Unassigned Models"];
    modelsTitle.translatesAutoresizingMaskIntoConstraints = NO;
    modelsTitle.font = [NSFont boldSystemFontOfSize:12];
    [rightPanel addSubview:modelsTitle];

    _hideOtherCheckbox = [NSButton checkboxWithTitle:@"Hide other controller models"
                                              target:self action:@selector(hideOtherChanged:)];
    _hideOtherCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    [rightPanel addSubview:_hideOtherCheckbox];

    _modelsScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _modelsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _modelsScrollView.hasVerticalScroller = YES;
    _modelsScrollView.borderType = NSBezelBorder;

    _modelsView = [[XLUnassignedModelsView alloc] initWithFrame:NSMakeRect(0, 0, 200, 500)];
    _modelsView.delegate = self;
    _modelsScrollView.documentView = _modelsView;

    [rightPanel addSubview:_modelsScrollView];

    [NSLayoutConstraint activateConstraints:@[
        [modelsTitle.topAnchor constraintEqualToAnchor:rightPanel.topAnchor constant:8],
        [modelsTitle.leadingAnchor constraintEqualToAnchor:rightPanel.leadingAnchor constant:8],

        [_hideOtherCheckbox.topAnchor constraintEqualToAnchor:modelsTitle.bottomAnchor constant:8],
        [_hideOtherCheckbox.leadingAnchor constraintEqualToAnchor:rightPanel.leadingAnchor constant:8],

        [_modelsScrollView.topAnchor constraintEqualToAnchor:_hideOtherCheckbox.bottomAnchor constant:8],
        [_modelsScrollView.leadingAnchor constraintEqualToAnchor:rightPanel.leadingAnchor constant:8],
        [_modelsScrollView.trailingAnchor constraintEqualToAnchor:rightPanel.trailingAnchor constant:-8],
        [_modelsScrollView.bottomAnchor constraintEqualToAnchor:rightPanel.bottomAnchor constant:-8],
    ]];

    [splitView addArrangedSubview:rightPanel];

    // Bottom status bar
    _statusField = [NSTextField labelWithString:@""];
    _statusField.translatesAutoresizingMaskIntoConstraints = NO;
    _statusField.textColor = [NSColor secondaryLabelColor];
    [contentView addSubview:_statusField];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:44],

        [splitView.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [splitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [splitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [splitView.bottomAnchor constraintEqualToAnchor:_statusField.topAnchor constant:-8],

        [_statusField.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:12],
        [_statusField.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-12],
        [_statusField.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-8],
        [_statusField.heightAnchor constraintEqualToConstant:20],
    ]];

    // Set initial split position
    [splitView setPosition:kWindowWidth * 0.75 ofDividerAtIndex:0];
}

- (void)showWithCompletion:(XLControllerModelCompletion)completion {
    _completion = completion;
    [self.window center];
    [self showWindow:nil];
}

#pragma mark - Actions

- (void)scaleChanged:(id)sender {
    _portsView.displayScale = _boxScaleSlider.floatValue;
    _portsView.fontScale = _fontScaleSlider.floatValue;
    [_portsView setNeedsDisplay:YES];
}

- (void)hideOtherChanged:(id)sender {
    _modelsView.hideOtherControllerModels = (_hideOtherCheckbox.state == NSControlStateValueOn);
}

- (void)printClicked:(id)sender {
    [self printLayout];
}

- (void)exportCSVClicked:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithIdentifier:@"public.comma-separated-values-text"]];
    panel.nameFieldStringValue = [NSString stringWithFormat:@"%@.csv", _controllerName];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            [self exportToCSV:panel.URL];
        }
    }];
}

- (void)printLayout {
    NSPrintInfo *printInfo = [NSPrintInfo sharedPrintInfo];
    NSPrintOperation *op = [NSPrintOperation printOperationWithView:_portsView printInfo:printInfo];
    [op runOperationModalForWindow:self.window delegate:nil didRunSelector:nil contextInfo:nil];
}

- (void)exportToCSV:(NSURL *)url {
    NSMutableString *csv = [NSMutableString string];

    [csv appendString:@"Port,Protocol,Model,Start Channel,Channels,String\n"];

    for (NSInteger p = 0; p < _portsView.portCount; p++) {
        XLPortConfig config = [_portsView portConfigAtIndex:p];

        // Would iterate through models on each port
        [csv appendFormat:@"%d,%s,,,,\n", config.portNumber, config.protocol];
    }

    [csv writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark - XLControllerPortsViewDelegate

- (void)controllerPortsView:(XLControllerPortsView *)view didSelectPort:(NSInteger)port {
    XLPortConfig config = [view portConfigAtIndex:port];
    _statusField.stringValue = [NSString stringWithFormat:@"Port %d - %s - %d pixels",
                               config.portNumber, config.protocol, config.pixelCount];
}

- (void)controllerPortsView:(XLControllerPortsView *)view didSelectModel:(NSString *)modelName onPort:(NSInteger)port {
    _statusField.stringValue = [NSString stringWithFormat:@"Model: %@ on Port %ld", modelName, (long)port + 1];
}

- (void)controllerPortsView:(XLControllerPortsView *)view didDropModel:(NSString *)modelName onPort:(NSInteger)port atPosition:(NSInteger)position {
    // Handle model assignment
    _hasChanges = YES;
    _statusField.stringValue = [NSString stringWithFormat:@"Assigned %@ to Port %ld", modelName, (long)port + 1];
}

- (void)controllerPortsView:(XLControllerPortsView *)view requestContextMenuForPort:(NSInteger)port atPoint:(NSPoint)point {
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Remove All Models" action:@selector(removeAllModelsFromPort:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Set Protocol..." action:@selector(setPortProtocol:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Set Brightness..." action:@selector(setPortBrightness:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Set Color Order..." action:@selector(setPortColorOrder:) keyEquivalent:@""];

    [menu popUpMenuPositioningItem:nil atLocation:point inView:view];
}

- (void)controllerPortsView:(XLControllerPortsView *)view requestContextMenuForModel:(NSString *)modelName atPoint:(NSPoint)point {
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Remove from Port" action:@selector(removeModelFromPort:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Move to Port..." action:@selector(moveModelToPort:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Set Start Channel..." action:@selector(setModelStartChannel:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Set Brightness..." action:@selector(setModelBrightness:) keyEquivalent:@""];

    [menu popUpMenuPositioningItem:nil atLocation:point inView:view];
}

#pragma mark - XLUnassignedModelsViewDelegate

- (void)unassignedModelsView:(XLUnassignedModelsView *)view didSelectModel:(NSString *)modelName {
    _statusField.stringValue = [NSString stringWithFormat:@"Selected: %@", modelName];
}

- (void)unassignedModelsView:(XLUnassignedModelsView *)view didDoubleClickModel:(NSString *)modelName {
    // Could open model properties
}

- (void)unassignedModelsView:(XLUnassignedModelsView *)view didBeginDragForModel:(NSString *)modelName {
    _statusField.stringValue = [NSString stringWithFormat:@"Dragging: %@", modelName];
}

#pragma mark - Context Menu Actions

- (void)removeAllModelsFromPort:(id)sender {
    _hasChanges = YES;
}

- (void)setPortProtocol:(id)sender {
    // Show protocol picker
}

- (void)setPortBrightness:(id)sender {
    // Show brightness slider
}

- (void)setPortColorOrder:(id)sender {
    // Show color order picker
}

- (void)removeModelFromPort:(id)sender {
    _hasChanges = YES;
}

- (void)moveModelToPort:(id)sender {
    // Show port picker
}

- (void)setModelStartChannel:(id)sender {
    // Show channel input
}

- (void)setModelBrightness:(id)sender {
    // Show brightness slider
}

@end
