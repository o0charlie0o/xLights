/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLModelTreeViewController.h"
#import "XLModelTreeNode.h"
#import "XLViewObject.h"
#import "../XLEngineBridge.h"
#import "../dialogs/XLSubModelsWindow.h"
#import "../dialogs/XLModelStateWindow.h"
#import "../dialogs/XLModelDialogs.h"
#import "../dialogs/XLModelFaceWindow.h"

NSNotificationName const XLViewObjectSelectionDidChangeNotification = @"XLViewObjectSelectionDidChangeNotification";

static NSString * const kXLModelTreeDragType = @"com.xlights.modelTreeNode";

static NSString * const kColumnName = @"NameColumn";
static NSString * const kColumnStartChan = @"StartChanColumn";
static NSString * const kColumnEndChan = @"EndChanColumn";
static NSString * const kColumnController = @"ControllerColumn";

static NSString * const kViewObjectColumnName = @"VONameColumn";
static NSString * const kViewObjectColumnType = @"VOTypeColumn";

/// Tab indices for the Models / 3D Objects segmented control
typedef NS_ENUM(NSInteger, XLTreeTab) {
    XLTreeTabModels = 0,
    XLTreeTabViewObjects = 1,
};

@interface XLModelTreeViewController ()

// Tab control (Models / 3D Objects)
@property (nonatomic, strong) NSSegmentedControl *tabControl;

// Models tab views
@property (nonatomic, strong) NSView *modelsContainer;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong, readwrite) NSOutlineView *outlineView;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSSegmentedControl *footerButtons;

@property (nonatomic, strong) NSArray<XLModelTreeNode *> *allNodes;
@property (nonatomic, strong) NSArray<XLModelTreeNode *> *filteredNodes;
@property (nonatomic, copy) NSString *searchText;

@property (nonatomic, assign) BOOL suppressSelectionNotification;

@property (nonatomic, strong) XLSubModelsWindow *subModelsWindow;
@property (nonatomic, strong) XLModelStateWindow *stateDialog;
@property (nonatomic, strong) XLModelFaceWindow *faceDialog;

// 3D Objects tab views
@property (nonatomic, strong) NSView *viewObjectsContainer;
@property (nonatomic, strong) NSScrollView *viewObjectsScrollView;
@property (nonatomic, strong) NSTableView *viewObjectsTable;
@property (nonatomic, strong) NSSegmentedControl *viewObjectsFooterButtons;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *viewObjectsData;

@end

/// Tag values for context menu items (to identify actions in submenus)
typedef NS_ENUM(NSInteger, XLContextMenuTag) {
    XLContextTagNone = 0,

    // Align tags
    XLContextTagAlignTop = 100,
    XLContextTagAlignBottom,
    XLContextTagAlignLeft,
    XLContextTagAlignRight,
    XLContextTagAlignHCenter,
    XLContextTagAlignVCenter,

    // Distribute tags
    XLContextTagDistributeH = 200,
    XLContextTagDistributeV,

    // Resize tags
    XLContextTagResizeWidth = 300,
    XLContextTagResizeHeight,
    XLContextTagResizeSize,

    // Bulk edit tags
    XLContextTagBulkActive = 400,
    XLContextTagBulkInactive,
    XLContextTagBulkTagColor,
    XLContextTagBulkPreview,
    XLContextTagBulkPixelSize,
    XLContextTagBulkPixelStyle,
    XLContextTagBulkTransparency,
    XLContextTagBulkControllerName,
    XLContextTagBulkControllerPort,
    XLContextTagBulkControllerProtocol,
    XLContextTagBulkDimmingCurves,
};

@implementation XLModelTreeViewController

#pragma mark - View Lifecycle

- (void)loadView {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 600)];
    container.wantsLayer = YES;

    // Tab control (Models / 3D Objects) — hidden in 2D mode
    [self setupTabControl:container];

    // Models container (search + outline + footer)
    _modelsContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _modelsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:_modelsContainer];

    [self setupSearchField:_modelsContainer];
    [self setupOutlineView:_modelsContainer];
    [self setupFooterButtons:_modelsContainer];
    [self setupModelsConstraints:_modelsContainer];

    // 3D Objects container (table + footer) — hidden by default
    _viewObjectsContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _viewObjectsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _viewObjectsContainer.hidden = YES;
    [container addSubview:_viewObjectsContainer];

    [self setupViewObjectsTable:_viewObjectsContainer];
    [self setupViewObjectsFooter:_viewObjectsContainer];
    [self setupViewObjectsConstraints:_viewObjectsContainer];

    // Container-level constraints: tab control at top, then content area
    [self setupContainerConstraints:container];

    self.view = container;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadData];
}

#pragma mark - UI Setup

- (void)setupTabControl:(NSView *)container {
    _tabControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Models", @"3D Objects"]
                                                     trackingMode:NSSegmentSwitchTrackingSelectOne
                                                           target:self
                                                           action:@selector(tabControlChanged:)];
    _tabControl.translatesAutoresizingMaskIntoConstraints = NO;
    _tabControl.controlSize = NSControlSizeSmall;
    _tabControl.font = [NSFont systemFontOfSize:11];
    _tabControl.selectedSegment = XLTreeTabModels;
    _tabControl.hidden = !_show3D;  // Only visible in 3D mode
    [container addSubview:_tabControl];
}

- (void)setupSearchField:(NSView *)container {
    _searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.placeholderString = @"Filter Models";
    _searchField.delegate = self;
    _searchField.sendsSearchStringImmediately = YES;
    _searchField.sendsWholeSearchString = NO;
    [container addSubview:_searchField];
}

- (void)setupOutlineView:(NSView *)container {
    _outlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
    _outlineView.headerView = [[NSTableHeaderView alloc] init];
    _outlineView.allowsMultipleSelection = YES;
    _outlineView.allowsEmptySelection = YES;
    _outlineView.usesAlternatingRowBackgroundColors = YES;
    _outlineView.rowSizeStyle = NSTableViewRowSizeStyleSmall;
    _outlineView.indentationPerLevel = 18.0;
    _outlineView.autoresizesOutlineColumn = YES;
    _outlineView.floatsGroupRows = NO;
    _outlineView.dataSource = self;
    _outlineView.delegate = self;

    // Name column (outline column)
    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:kColumnName];
    nameColumn.title = @"Name";
    nameColumn.minWidth = 120;
    nameColumn.width = 180;
    nameColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    [_outlineView addTableColumn:nameColumn];
    _outlineView.outlineTableColumn = nameColumn;

    // Start Chan column
    NSTableColumn *startChanColumn = [[NSTableColumn alloc] initWithIdentifier:kColumnStartChan];
    startChanColumn.title = @"Start Chan";
    startChanColumn.minWidth = 50;
    startChanColumn.width = 80;
    startChanColumn.resizingMask = NSTableColumnUserResizingMask;
    [_outlineView addTableColumn:startChanColumn];

    // End Chan column
    NSTableColumn *endChanColumn = [[NSTableColumn alloc] initWithIdentifier:kColumnEndChan];
    endChanColumn.title = @"End Chan";
    endChanColumn.minWidth = 50;
    endChanColumn.width = 70;
    endChanColumn.resizingMask = NSTableColumnUserResizingMask;
    [_outlineView addTableColumn:endChanColumn];

    // Controller connection column
    NSTableColumn *controllerColumn = [[NSTableColumn alloc] initWithIdentifier:kColumnController];
    controllerColumn.title = @"Ctrlr Conn";
    controllerColumn.minWidth = 60;
    controllerColumn.width = 90;
    controllerColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    [_outlineView addTableColumn:controllerColumn];

    // Drag and drop
    [_outlineView registerForDraggedTypes:@[kXLModelTreeDragType]];
    _outlineView.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleSourceList;

    // Context menu (dynamic, rebuilt on each right-click via menuNeedsUpdate:)
    _outlineView.menu = [self buildContextMenu];

    // Scroll view
    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.documentView = _outlineView;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers = YES;
    _scrollView.borderType = NSNoBorder;
    _scrollView.drawsBackground = NO;
    [container addSubview:_scrollView];
}

- (void)setupFooterButtons:(NSView *)container {
    _footerButtons = [NSSegmentedControl segmentedControlWithImages:@[
        [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"Add"],
        [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Remove"],
        [NSImage imageWithSystemSymbolName:@"folder.badge.plus" accessibilityDescription:@"Group"],
    ] trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(footerButtonClicked:)];
    _footerButtons.translatesAutoresizingMaskIntoConstraints = NO;
    _footerButtons.segmentStyle = NSSegmentStyleSmallSquare;

    [_footerButtons setWidth:32 forSegment:0];
    [_footerButtons setWidth:32 forSegment:1];
    [_footerButtons setWidth:32 forSegment:2];

    [container addSubview:_footerButtons];
}

- (void)setupModelsConstraints:(NSView *)container {
    NSLayoutConstraint *searchTrailing = [_searchField.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-4];
    searchTrailing.priority = NSLayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        // Search field
        [_searchField.topAnchor constraintEqualToAnchor:container.topAnchor constant:4],
        [_searchField.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4],
        searchTrailing,
        [_searchField.heightAnchor constraintEqualToConstant:22],

        // Scroll view
        [_scrollView.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:4],
        [_scrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_footerButtons.topAnchor constant:-2],

        // Footer buttons
        [_footerButtons.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4],
        [_footerButtons.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4],
        [_footerButtons.heightAnchor constraintEqualToConstant:24],
    ]];
}

#pragma mark - 3D Objects Tab Setup

- (void)setupViewObjectsTable:(NSView *)container {
    _viewObjectsData = [[NSMutableArray alloc] init];

    _viewObjectsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _viewObjectsTable.headerView = [[NSTableHeaderView alloc] init];
    _viewObjectsTable.allowsMultipleSelection = NO;
    _viewObjectsTable.allowsEmptySelection = YES;
    _viewObjectsTable.usesAlternatingRowBackgroundColors = YES;
    _viewObjectsTable.rowSizeStyle = NSTableViewRowSizeStyleSmall;
    _viewObjectsTable.dataSource = self;
    _viewObjectsTable.delegate = self;

    // Name column
    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:kViewObjectColumnName];
    nameColumn.title = @"Name";
    nameColumn.minWidth = 100;
    nameColumn.width = 160;
    nameColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    [_viewObjectsTable addTableColumn:nameColumn];

    // Type column
    NSTableColumn *typeColumn = [[NSTableColumn alloc] initWithIdentifier:kViewObjectColumnType];
    typeColumn.title = @"Type";
    typeColumn.minWidth = 60;
    typeColumn.width = 80;
    typeColumn.resizingMask = NSTableColumnUserResizingMask;
    [_viewObjectsTable addTableColumn:typeColumn];

    _viewObjectsScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _viewObjectsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _viewObjectsScrollView.documentView = _viewObjectsTable;
    _viewObjectsScrollView.hasVerticalScroller = YES;
    _viewObjectsScrollView.hasHorizontalScroller = NO;
    _viewObjectsScrollView.autohidesScrollers = YES;
    _viewObjectsScrollView.borderType = NSNoBorder;
    _viewObjectsScrollView.drawsBackground = NO;
    [container addSubview:_viewObjectsScrollView];
}

- (void)setupViewObjectsFooter:(NSView *)container {
    _viewObjectsFooterButtons = [NSSegmentedControl segmentedControlWithImages:@[
        [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"Add Object"],
        [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Remove Object"],
    ] trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(viewObjectFooterClicked:)];
    _viewObjectsFooterButtons.translatesAutoresizingMaskIntoConstraints = NO;
    _viewObjectsFooterButtons.segmentStyle = NSSegmentStyleSmallSquare;
    [_viewObjectsFooterButtons setWidth:32 forSegment:0];
    [_viewObjectsFooterButtons setWidth:32 forSegment:1];
    [container addSubview:_viewObjectsFooterButtons];
}

- (void)setupViewObjectsConstraints:(NSView *)container {
    [NSLayoutConstraint activateConstraints:@[
        [_viewObjectsScrollView.topAnchor constraintEqualToAnchor:container.topAnchor constant:4],
        [_viewObjectsScrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_viewObjectsScrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_viewObjectsScrollView.bottomAnchor constraintEqualToAnchor:_viewObjectsFooterButtons.topAnchor constant:-2],

        [_viewObjectsFooterButtons.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4],
        [_viewObjectsFooterButtons.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4],
        [_viewObjectsFooterButtons.heightAnchor constraintEqualToConstant:24],
    ]];
}

- (void)setupContainerConstraints:(NSView *)container {
    // Tab control at the top, pinned to leading/trailing
    NSLayoutConstraint *tabTrailing = [_tabControl.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-4];
    tabTrailing.priority = NSLayoutPriorityDefaultHigh;

    // When tab control is hidden, the content area reaches the top.
    // When visible, content area starts below the tab control.
    // We use two sets of top constraints with different priorities.
    NSLayoutConstraint *modelsTopBelowTab = [_modelsContainer.topAnchor constraintEqualToAnchor:_tabControl.bottomAnchor constant:4];
    NSLayoutConstraint *modelsTopAtTop = [_modelsContainer.topAnchor constraintEqualToAnchor:container.topAnchor];
    modelsTopBelowTab.priority = NSLayoutPriorityDefaultHigh;
    modelsTopAtTop.priority = NSLayoutPriorityDefaultLow;

    NSLayoutConstraint *voTopBelowTab = [_viewObjectsContainer.topAnchor constraintEqualToAnchor:_tabControl.bottomAnchor constant:4];
    voTopBelowTab.priority = NSLayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        // Tab control
        [_tabControl.topAnchor constraintEqualToAnchor:container.topAnchor constant:4],
        [_tabControl.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4],
        tabTrailing,
        [_tabControl.heightAnchor constraintEqualToConstant:22],

        // Models container
        modelsTopBelowTab,
        modelsTopAtTop,
        [_modelsContainer.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_modelsContainer.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_modelsContainer.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        // View objects container (same frame as models container)
        voTopBelowTab,
        [_viewObjectsContainer.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_viewObjectsContainer.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_viewObjectsContainer.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
}

#pragma mark - Data Loading

- (void)reloadData {
    [self loadModelTreeFromEngine];

    if (_searchText.length > 0) {
        [self applySearchFilter];
    } else {
        _filteredNodes = _allNodes;
    }

    _rootNodes = _filteredNodes;
    [_outlineView reloadData];
}

- (void)loadModelTreeFromEngine {
    if (!_engineBridge) {
        _allNodes = @[];
        return;
    }

    NSMutableArray<XLModelTreeNode *> *nodes = [[NSMutableArray alloc] init];
    NSMutableSet<NSString *> *modelsInGroups = [[NSMutableSet alloc] init];

    // First pass: collect all groups and track which models are in groups
    NSArray<NSDictionary *> *groups = [_engineBridge getModelGroups];
    for (NSDictionary *groupInfo in groups) {
        NSString *groupName = groupInfo[@"name"];
        NSArray<NSString *> *memberNames = groupInfo[@"modelNames"];

        XLModelTreeNode *groupNode = [XLModelTreeNode groupNodeWithName:groupName];

        for (NSString *memberName in memberNames) {
            [modelsInGroups addObject:memberName];

            NSDictionary *memberInfo = [_engineBridge getModelInfo:memberName];
            if (!memberInfo) continue;

            NSString *modelType = memberInfo[@"type"] ?: @"Unknown";
            XLModelTreeNode *childNode = [XLModelTreeNode nodeWithName:memberName type:modelType];
            childNode.channelCount = [memberInfo[@"channelCount"] integerValue];
            [self populateChannelInfoForNode:childNode fromInfo:memberInfo];
            [self populateShadowInfoForNode:childNode];
            [self loadSubmodelsForNode:childNode modelName:memberName];
            [groupNode addChild:childNode];
        }

        [nodes addObject:groupNode];
    }

    // Second pass: add models that are not in any group (excluding groups themselves)
    NSArray<NSString *> *modelNames = [_engineBridge getModelNamesExcludingGroups];
    for (NSString *modelName in modelNames) {
        // Skip models that are already children of a group
        if ([modelsInGroups containsObject:modelName]) continue;

        NSDictionary *info = [_engineBridge getModelInfo:modelName];
        if (!info) continue;

        NSString *modelType = info[@"type"] ?: @"Unknown";
        XLModelTreeNode *node = [XLModelTreeNode nodeWithName:modelName type:modelType];
        node.channelCount = [info[@"channelCount"] integerValue];
        [self populateChannelInfoForNode:node fromInfo:info];
        [self populateShadowInfoForNode:node];
        [self loadSubmodelsForNode:node modelName:modelName];

        [nodes addObject:node];
    }

    _allNodes = [nodes copy];
}

- (void)populateChannelInfoForNode:(XLModelTreeNode *)node fromInfo:(NSDictionary *)info {
    node.startChannel = info[@"startChannel"] ?: @"";
    node.endChannel = [info[@"endChannel"] integerValue];

    NSString *controllerName = info[@"controllerName"];
    NSInteger port = [info[@"port"] integerValue];
    if (controllerName.length > 0 && port > 0) {
        node.controllerConnection = [NSString stringWithFormat:@"%@:%ld", controllerName, (long)port];
    } else if (controllerName.length > 0) {
        node.controllerConnection = controllerName;
    } else {
        node.controllerConnection = @"";
    }
}

- (void)populateShadowInfoForNode:(XLModelTreeNode *)node {
    if (!_engineBridge || !node.name) return;
    NSString *shadowFor = [_engineBridge getShadowModelFor:node.name];
    if (shadowFor && shadowFor.length > 0) {
        node.isShadowModel = YES;
        node.shadowModelFor = shadowFor;
    }
}

- (void)loadSubmodelsForNode:(XLModelTreeNode *)node modelName:(NSString *)modelName {
    if (!_engineBridge) return;

    NSArray<NSDictionary *> *submodels = [_engineBridge getSubmodels:modelName];
    for (NSDictionary *submodelInfo in submodels) {
        NSString *submodelName = submodelInfo[@"name"];
        if (!submodelName) continue;

        XLModelTreeNode *subNode = [XLModelTreeNode submodelNodeWithName:submodelName
                                                             parentType:node.modelType];
        subNode.channelCount = [submodelInfo[@"channelCount"] integerValue];
        [node addChild:subNode];
    }
}

#pragma mark - Search / Filter

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == _searchField) {
        _searchText = _searchField.stringValue;
        if (_searchText.length == 0) {
            _filteredNodes = _allNodes;
        } else {
            [self applySearchFilter];
        }
        _rootNodes = _filteredNodes;
        [_outlineView reloadData];
        if (_searchText.length > 0) {
            [_outlineView expandItem:nil expandChildren:YES];
        }
    }
}

- (void)applySearchFilter {
    NSMutableArray<XLModelTreeNode *> *filtered = [[NSMutableArray alloc] init];
    NSString *lowercaseSearch = [_searchText lowercaseString];

    for (XLModelTreeNode *node in _allNodes) {
        XLModelTreeNode *match = [self filterNode:node withSearch:lowercaseSearch];
        if (match) {
            [filtered addObject:match];
        }
    }

    _filteredNodes = [filtered copy];
}

- (XLModelTreeNode *)filterNode:(XLModelTreeNode *)node withSearch:(NSString *)search {
    BOOL nameMatches = [[node.name lowercaseString] containsString:search];

    if (node.isLeaf) {
        return nameMatches ? node : nil;
    }

    NSMutableArray<XLModelTreeNode *> *matchingChildren = [[NSMutableArray alloc] init];
    for (XLModelTreeNode *child in node.children) {
        XLModelTreeNode *match = [self filterNode:child withSearch:search];
        if (match) {
            [matchingChildren addObject:match];
        }
    }

    if (nameMatches || matchingChildren.count > 0) {
        if (matchingChildren.count == node.children.count) {
            return node;
        }
        XLModelTreeNode *filteredNode;
        if (node.isGroup) {
            filteredNode = [XLModelTreeNode groupNodeWithName:node.name];
        } else {
            filteredNode = [XLModelTreeNode nodeWithName:node.name type:node.modelType];
            filteredNode.channelCount = node.channelCount;
            filteredNode.startChannel = node.startChannel;
            filteredNode.endChannel = node.endChannel;
            filteredNode.controllerConnection = node.controllerConnection;
        }
        for (XLModelTreeNode *child in matchingChildren) {
            [filteredNode addChild:child];
        }
        return filteredNode;
    }

    return nil;
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nil) {
        return (NSInteger)_rootNodes.count;
    }
    XLModelTreeNode *node = (XLModelTreeNode *)item;
    return (NSInteger)node.childCount;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nil) {
        return _rootNodes[index];
    }
    XLModelTreeNode *node = (XLModelTreeNode *)item;
    return [node childAtIndex:(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    XLModelTreeNode *node = (XLModelTreeNode *)item;
    return ![node isLeaf];
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    XLModelTreeNode *node = (XLModelTreeNode *)item;
    NSString *columnId = tableColumn.identifier;

    if ([columnId isEqualToString:kColumnName]) {
        return [self nameCellForNode:node inOutlineView:outlineView];
    }
    else if ([columnId isEqualToString:kColumnStartChan]) {
        NSString *text = node.startChannel.length > 0 ? node.startChannel : @"";
        NSTableCellView *cell = [self textCellWithIdentifier:kColumnStartChan text:text inOutlineView:outlineView];
        cell.textField.alignment = NSTextAlignmentRight;
        cell.textField.font = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular];
        return cell;
    }
    else if ([columnId isEqualToString:kColumnEndChan]) {
        NSString *text = node.endChannel > 0 ? [NSString stringWithFormat:@"%ld", (long)node.endChannel] : @"";
        NSTableCellView *cell = [self textCellWithIdentifier:kColumnEndChan text:text inOutlineView:outlineView];
        cell.textField.alignment = NSTextAlignmentRight;
        cell.textField.font = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular];
        return cell;
    }
    else if ([columnId isEqualToString:kColumnController]) {
        return [self textCellWithIdentifier:kColumnController
                                      text:node.controllerConnection ?: @""
                              inOutlineView:outlineView];
    }

    return nil;
}

- (NSTableCellView *)nameCellForNode:(XLModelTreeNode *)node inOutlineView:(NSOutlineView *)outlineView {
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:kColumnName owner:self];

    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = kColumnName;

        NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.imageScaling = NSImageScaleProportionallyDown;
        [cell addSubview:imageView];
        cell.imageView = imageView;

        NSTextField *textField = [NSTextField textFieldWithString:@""];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.bordered = NO;
        textField.drawsBackground = NO;
        textField.editable = NO;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        textField.font = [NSFont systemFontOfSize:12];
        [cell addSubview:textField];
        cell.textField = textField;

        [NSLayoutConstraint activateConstraints:@[
            [imageView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [imageView.widthAnchor constraintEqualToConstant:16],
            [imageView.heightAnchor constraintEqualToConstant:16],
            [textField.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor constant:4],
            [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    NSImage *icon = [NSImage imageWithSystemSymbolName:node.iconName accessibilityDescription:node.modelType];
    if (icon) {
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightRegular];
        cell.imageView.image = [icon imageWithSymbolConfiguration:config];
        if (node.isGroup) {
            cell.imageView.contentTintColor = [NSColor systemOrangeColor];
        } else if (node.isShadowModel) {
            cell.imageView.contentTintColor = [NSColor systemPurpleColor];
        } else {
            cell.imageView.contentTintColor = [NSColor secondaryLabelColor];
        }
    }

    cell.textField.stringValue = node.name ?: @"";
    if (node.isGroup) {
        cell.textField.font = [NSFont boldSystemFontOfSize:12];
        cell.textField.textColor = [NSColor labelColor];
    } else if (node.isShadowModel) {
        cell.textField.font = [NSFont systemFontOfSize:12];
        cell.textField.textColor = [NSColor systemPurpleColor];
    } else {
        cell.textField.font = [NSFont systemFontOfSize:12];
        cell.textField.textColor = [NSColor labelColor];
    }

    return cell;
}

- (NSTableCellView *)textCellWithIdentifier:(NSString *)identifier text:(NSString *)text inOutlineView:(NSOutlineView *)outlineView {
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:identifier owner:self];

    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = identifier;

        NSTextField *textField = [NSTextField textFieldWithString:@""];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.bordered = NO;
        textField.drawsBackground = NO;
        textField.editable = NO;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        textField.font = [NSFont systemFontOfSize:11];
        textField.textColor = [NSColor secondaryLabelColor];
        [cell addSubview:textField];
        cell.textField = textField;

        [NSLayoutConstraint activateConstraints:@[
            [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    cell.textField.stringValue = text ?: @"";
    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    if (_suppressSelectionNotification) return;

    NSInteger row = _outlineView.selectedRow;
    if (row < 0) return;

    XLModelTreeNode *node = [_outlineView itemAtRow:row];
    if (!node) return;

    if (node.isSubmodel && node.parent) {
        if ([_delegate respondsToSelector:@selector(modelTree:didSelectSubmodel:ofModel:)]) {
            [_delegate modelTree:self didSelectSubmodel:node.name ofModel:node.parent.name];
        }
    } else {
        NSString *name = node.name;
        if (name && [_delegate respondsToSelector:@selector(modelTree:didSelectModel:)]) {
            [_delegate modelTree:self didSelectModel:name];
        }
    }
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
    return 22.0;
}

#pragma mark - Drag and Drop

- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)outlineView pasteboardWriterForItem:(id)item {
    XLModelTreeNode *node = (XLModelTreeNode *)item;

    // Submodels cannot be dragged
    if (node.isSubmodel) return nil;

    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setString:node.name forType:kXLModelTreeDragType];
    return pbItem;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView
                  validateDrop:(id<NSDraggingInfo>)info
                  proposedItem:(id)item
            proposedChildIndex:(NSInteger)index {
    XLModelTreeNode *targetNode = (XLModelTreeNode *)item;

    // Collect dragged model names from the pasteboard
    NSPasteboard *pb = info.draggingPasteboard;
    NSArray<NSPasteboardItem *> *pbItems = pb.pasteboardItems;
    NSMutableSet<NSString *> *draggedNames = [[NSMutableSet alloc] init];
    for (NSPasteboardItem *pbItem in pbItems) {
        NSString *name = [pbItem stringForType:kXLModelTreeDragType];
        if (name) [draggedNames addObject:name];
    }

    if (draggedNames.count == 0) return NSDragOperationNone;

    // Prevent dropping a group onto itself
    if (targetNode && [draggedNames containsObject:targetNode.name]) {
        return NSDragOperationNone;
    }

    // Prevent dropping onto a submodel
    if (targetNode && targetNode.isSubmodel) {
        return NSDragOperationNone;
    }

    // Prevent dropping onto a regular model (non-group) -- they can't have model children
    if (targetNode && !targetNode.isGroup) {
        return NSDragOperationNone;
    }

    // Allow dropping between items inside a group (reorder within group)
    if (targetNode && targetNode.isGroup && index != NSOutlineViewDropOnItemIndex) {
        return NSDragOperationMove;
    }

    // Allow dropping ON a group (appends to end of group)
    if (targetNode && targetNode.isGroup && index == NSOutlineViewDropOnItemIndex) {
        return NSDragOperationMove;
    }

    // Allow reordering at root level (between root items)
    if (targetNode == nil && index != NSOutlineViewDropOnItemIndex) {
        return NSDragOperationMove;
    }

    return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
          acceptDrop:(id<NSDraggingInfo>)info
                item:(id)item
          childIndex:(NSInteger)index {
    NSPasteboard *pb = info.draggingPasteboard;
    NSArray<NSPasteboardItem *> *pbItems = pb.pasteboardItems;

    // Collect all dragged model names in order
    NSMutableArray<NSString *> *draggedNames = [[NSMutableArray alloc] init];
    for (NSPasteboardItem *pbItem in pbItems) {
        NSString *name = [pbItem stringForType:kXLModelTreeDragType];
        if (name) [draggedNames addObject:name];
    }

    if (draggedNames.count == 0) return NO;

    XLModelTreeNode *targetNode = (XLModelTreeNode *)item;
    NSString *groupName = targetNode ? targetNode.name : nil;

    // Notify delegate for each dragged model so the engine can persist the change.
    // Process in order so index adjustments are sequential.
    if ([_delegate respondsToSelector:@selector(modelTree:didMoveModel:toGroup:atIndex:)]) {
        NSInteger insertIndex = index;
        for (NSString *modelName in draggedNames) {
            [_delegate modelTree:self didMoveModel:modelName toGroup:groupName atIndex:insertIndex];
            // Increment index for next item so ordering is preserved
            if (insertIndex >= 0) {
                insertIndex++;
            }
        }
    }

    [self reloadData];
    return YES;
}

#pragma mark - Context Menu

- (NSMenu *)buildContextMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Model Actions"];
    menu.delegate = self;
    menu.autoenablesItems = NO;
    return menu;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != _outlineView.menu) return;

    [menu removeAllItems];

    NSIndexSet *selectedRows = _outlineView.selectedRowIndexes;
    NSInteger selCount = (NSInteger)selectedRows.count;

    // Gather selection info
    __block XLModelTreeNode *primaryNode = nil;
    __block BOOL hasGroup = NO;
    __block BOOL hasModel = NO;
    __block BOOL hasSubmodel = NO;

    [selectedRows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        XLModelTreeNode *node = [self.outlineView itemAtRow:(NSInteger)idx];
        if (!node) return;
        if (!primaryNode) primaryNode = node;
        if (node.isGroup) hasGroup = YES;
        else if (node.isSubmodel) hasSubmodel = YES;
        else hasModel = YES;
    }];

    // -- Always available: Add Model / Add Group / Import --
    [self addModelCreationItemsToMenu:menu];
    [menu addItem:[NSMenuItem separatorItem]];

    if (selCount == 0) {
        // No selection: only creation items above, plus expand/collapse
        [self addExpandCollapseItemsToMenu:menu];
        return;
    }

    if (selCount == 1 && !hasSubmodel) {
        // --- Single model or group selection ---
        [self addSingleSelectionItemsToMenu:menu node:primaryNode];
    } else if (selCount == 1 && hasSubmodel) {
        // Submodel: limited options
        NSMenuItem *renameItem = [[NSMenuItem alloc] initWithTitle:@"Rename"
                                                           action:@selector(contextRename:)
                                                    keyEquivalent:@""];
        renameItem.target = self;
        [menu addItem:renameItem];
    } else if (selCount > 1) {
        // --- Multiple selection ---
        [self addMultiSelectionItemsToMenu:menu count:selCount hasGroup:hasGroup hasSubmodel:hasSubmodel];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    [self addExpandCollapseItemsToMenu:menu];
}

- (void)addModelCreationItemsToMenu:(NSMenu *)menu {
    NSMenuItem *addItem = [[NSMenuItem alloc] initWithTitle:@"Add Model" action:nil keyEquivalent:@""];
    NSMenu *addSubmenu = [[NSMenu alloc] initWithTitle:@"Add Model"];

    NSArray *modelTypes = @[
        @"Single Line", @"Matrix", @"Arch", @"Custom",
        @"Tree", @"Spinner", @"Sphere", @"Circle",
        @"Cube", @"Icicles", @"Candy Canes", @"Star",
        @"Window Frame", @"Wreath", @"Channel Block", @"Poly Line",
        @"Image",
    ];

    for (NSString *type in modelTypes) {
        NSMenuItem *typeItem = [[NSMenuItem alloc] initWithTitle:type
                                                         action:@selector(contextAddModel:)
                                                  keyEquivalent:@""];
        typeItem.target = self;
        typeItem.representedObject = type;
        [addSubmenu addItem:typeItem];
    }
    addItem.submenu = addSubmenu;
    [menu addItem:addItem];

    NSMenuItem *addGroupItem = [[NSMenuItem alloc] initWithTitle:@"Add Group"
                                                         action:@selector(contextAddGroup:)
                                                  keyEquivalent:@""];
    addGroupItem.target = self;
    [menu addItem:addGroupItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *importItem = [[NSMenuItem alloc] initWithTitle:@"Import Model..."
                                                       action:@selector(contextImportModel:)
                                                keyEquivalent:@"i"];
    importItem.target = self;
    importItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [menu addItem:importItem];
}

- (void)addExpandCollapseItemsToMenu:(NSMenu *)menu {
    NSMenuItem *expandItem = [[NSMenuItem alloc] initWithTitle:@"Expand All"
                                                       action:@selector(expandAll)
                                                keyEquivalent:@""];
    expandItem.target = self;
    [menu addItem:expandItem];

    NSMenuItem *collapseItem = [[NSMenuItem alloc] initWithTitle:@"Collapse All"
                                                         action:@selector(collapseAll)
                                                  keyEquivalent:@""];
    collapseItem.target = self;
    [menu addItem:collapseItem];

    // Delete Empty Groups
    NSMenuItem *deleteEmptyItem = [[NSMenuItem alloc] initWithTitle:@"Delete Empty Groups"
                                                            action:@selector(contextDeleteEmptyGroups:)
                                                     keyEquivalent:@""];
    deleteEmptyItem.target = self;
    [menu addItem:deleteEmptyItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // Manage Groups
    NSMenuItem *manageGroupsItem = [[NSMenuItem alloc] initWithTitle:@"Manage Groups..."
                                                              action:@selector(contextManageGroups:)
                                                       keyEquivalent:@""];
    manageGroupsItem.target = self;
    [menu addItem:manageGroupsItem];
}

- (void)addSingleSelectionItemsToMenu:(NSMenu *)menu node:(XLModelTreeNode *)node {
    // Duplicate
    NSMenuItem *duplicateItem = [[NSMenuItem alloc] initWithTitle:@"Duplicate"
                                                          action:@selector(contextDuplicate:)
                                                   keyEquivalent:@"d"];
    duplicateItem.target = self;
    duplicateItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [menu addItem:duplicateItem];

    if (!node.isGroup) {
        NSMenuItem *shadowItem = [[NSMenuItem alloc] initWithTitle:@"Create Shadow Model"
                                                            action:@selector(contextCreateShadowModel:)
                                                     keyEquivalent:@""];
        shadowItem.target = self;
        [menu addItem:shadowItem];
    }

    // Delete
    NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete"
                                                       action:@selector(contextDelete:)
                                                keyEquivalent:@""];
    deleteItem.target = self;
    [menu addItem:deleteItem];

    // Rename
    NSMenuItem *renameItem = [[NSMenuItem alloc] initWithTitle:@"Rename"
                                                       action:@selector(contextRename:)
                                                keyEquivalent:@""];
    renameItem.target = self;
    [menu addItem:renameItem];

    [menu addItem:[NSMenuItem separatorItem]];

    if (node.isGroup) {
        // --- Group-specific items ---

        // Ungroup
        NSMenuItem *ungroupItem = [[NSMenuItem alloc] initWithTitle:@"Ungroup"
                                                             action:@selector(contextUngroup:)
                                                      keyEquivalent:@""];
        ungroupItem.target = self;
        [menu addItem:ungroupItem];

        // Clone Group
        NSMenuItem *cloneItem = [[NSMenuItem alloc] initWithTitle:@"Clone Group"
                                                           action:@selector(contextCloneGroup:)
                                                    keyEquivalent:@""];
        cloneItem.target = self;
        [menu addItem:cloneItem];
    } else {
        // --- Single model items ---

        // Lock / Unlock
        NSMenuItem *lockItem = [[NSMenuItem alloc] initWithTitle:@"Lock"
                                                          action:@selector(contextLock:)
                                                   keyEquivalent:@""];
        lockItem.target = self;
        [menu addItem:lockItem];

        NSMenuItem *unlockItem = [[NSMenuItem alloc] initWithTitle:@"Unlock"
                                                            action:@selector(contextUnlock:)
                                                     keyEquivalent:@""];
        unlockItem.target = self;
        [menu addItem:unlockItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Node Layout (placeholder)
        NSMenuItem *nodeLayoutItem = [[NSMenuItem alloc] initWithTitle:@"Node Layout"
                                                               action:@selector(contextNodeLayout:)
                                                        keyEquivalent:@""];
        nodeLayoutItem.target = self;
        [menu addItem:nodeLayoutItem];

        // Edit Submodels
        NSMenuItem *subModelsItem = [[NSMenuItem alloc] initWithTitle:@"Edit Submodels..."
                                                               action:@selector(contextEditSubmodels:)
                                                        keyEquivalent:@""];
        subModelsItem.target = self;
        [menu addItem:subModelsItem];

        // Edit States
        NSMenuItem *statesItem = [[NSMenuItem alloc] initWithTitle:@"Edit States..."
                                                             action:@selector(contextEditStates:)
                                                      keyEquivalent:@""];
        statesItem.target = self;
        [menu addItem:statesItem];

        // Edit Faces
        NSMenuItem *facesItem = [[NSMenuItem alloc] initWithTitle:@"Edit Faces..."
                                                            action:@selector(contextEditFaces:)
                                                     keyEquivalent:@""];
        facesItem.target = self;
        [menu addItem:facesItem];

        // Wiring View (placeholder)
        NSMenuItem *wiringItem = [[NSMenuItem alloc] initWithTitle:@"Wiring View"
                                                            action:@selector(contextWiringView:)
                                                     keyEquivalent:@""];
        wiringItem.target = self;
        [menu addItem:wiringItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Export as Custom xLights Model (placeholder)
        NSMenuItem *exportCustomItem = [[NSMenuItem alloc] initWithTitle:@"Export as Custom xLights Model"
                                                                 action:@selector(contextExportAsCustom:)
                                                          keyEquivalent:@""];
        exportCustomItem.target = self;
        [menu addItem:exportCustomItem];

        // Export xLights Model (placeholder)
        NSMenuItem *exportModelItem = [[NSMenuItem alloc] initWithTitle:@"Export xLights Model (.xmodel)"
                                                                action:@selector(contextExportXModel:)
                                                         keyEquivalent:@""];
        exportModelItem.target = self;
        [menu addItem:exportModelItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Flip Horizontal / Vertical
        NSMenuItem *flipHItem = [[NSMenuItem alloc] initWithTitle:@"Flip Horizontal"
                                                           action:@selector(contextFlipHorizontal:)
                                                    keyEquivalent:@""];
        flipHItem.target = self;
        [menu addItem:flipHItem];

        NSMenuItem *flipVItem = [[NSMenuItem alloc] initWithTitle:@"Flip Vertical"
                                                           action:@selector(contextFlipVertical:)
                                                    keyEquivalent:@""];
        flipVItem.target = self;
        [menu addItem:flipVItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Replace Model (only if there are other models to replace)
        NSArray<NSString *> *allModelNames = [_engineBridge getModelNamesExcludingGroups];
        if (allModelNames.count > 1) {
            NSMenuItem *replaceItem = [[NSMenuItem alloc] initWithTitle:@"Replace A Model With This Model"
                                                                action:@selector(contextReplaceModel:)
                                                         keyEquivalent:@""];
            replaceItem.target = self;
            [menu addItem:replaceItem];
        }

        [menu addItem:[NSMenuItem separatorItem]];

        // Group Selected Models (available even with single selection for grouping)
        NSMenuItem *groupItem = [[NSMenuItem alloc] initWithTitle:@"Create Group"
                                                           action:@selector(contextGroupSelected:)
                                                    keyEquivalent:@""];
        groupItem.target = self;
        [menu addItem:groupItem];

        // Add to Existing Groups submenu
        [self addGroupMembershipItemsToMenu:menu forModel:node.name];
    }
}

- (void)addMultiSelectionItemsToMenu:(NSMenu *)menu count:(NSInteger)count hasGroup:(BOOL)hasGroup hasSubmodel:(BOOL)hasSubmodel {

    if (!hasSubmodel) {
        // Duplicate / Delete
        NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Delete %ld Items", (long)count]
                                                           action:@selector(contextDelete:)
                                                    keyEquivalent:@""];
        deleteItem.target = self;
        [menu addItem:deleteItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Lock / Unlock all selected
        NSMenuItem *lockItem = [[NSMenuItem alloc] initWithTitle:@"Lock Selected"
                                                          action:@selector(contextLockAll:)
                                                   keyEquivalent:@""];
        lockItem.target = self;
        [menu addItem:lockItem];

        NSMenuItem *unlockItem = [[NSMenuItem alloc] initWithTitle:@"Unlock Selected"
                                                            action:@selector(contextUnlockAll:)
                                                     keyEquivalent:@""];
        unlockItem.target = self;
        [menu addItem:unlockItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Group Selected Models
        NSMenuItem *groupItem = [[NSMenuItem alloc] initWithTitle:@"Group Selected Models"
                                                           action:@selector(contextGroupSelected:)
                                                    keyEquivalent:@""];
        groupItem.target = self;
        [menu addItem:groupItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Flip all selected
        NSMenuItem *flipHItem = [[NSMenuItem alloc] initWithTitle:@"Flip Horizontal"
                                                           action:@selector(contextFlipHorizontal:)
                                                    keyEquivalent:@""];
        flipHItem.target = self;
        [menu addItem:flipHItem];

        NSMenuItem *flipVItem = [[NSMenuItem alloc] initWithTitle:@"Flip Vertical"
                                                           action:@selector(contextFlipVertical:)
                                                    keyEquivalent:@""];
        flipVItem.target = self;
        [menu addItem:flipVItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Bulk Edit submenu
        NSMenuItem *bulkEditItem = [[NSMenuItem alloc] initWithTitle:@"Bulk Edit" action:nil keyEquivalent:@""];
        bulkEditItem.submenu = [self buildBulkEditSubmenu];
        [menu addItem:bulkEditItem];

        // Align submenu
        NSMenuItem *alignItem = [[NSMenuItem alloc] initWithTitle:@"Align" action:nil keyEquivalent:@""];
        alignItem.submenu = [self buildAlignSubmenu];
        [menu addItem:alignItem];

        // Distribute submenu
        NSMenuItem *distItem = [[NSMenuItem alloc] initWithTitle:@"Distribute" action:nil keyEquivalent:@""];
        distItem.submenu = [self buildDistributeSubmenu];
        [menu addItem:distItem];

        // Resize submenu
        NSMenuItem *resizeItem = [[NSMenuItem alloc] initWithTitle:@"Resize" action:nil keyEquivalent:@""];
        resizeItem.submenu = [self buildResizeSubmenu];
        [menu addItem:resizeItem];
    }
}

- (void)addGroupMembershipItemsToMenu:(NSMenu *)menu forModel:(NSString *)modelName {
    if (!_engineBridge) return;

    NSArray<NSDictionary *> *groups = [_engineBridge getModelGroups];
    if (groups.count == 0) return;

    // Add to Existing Groups submenu
    NSMenuItem *addToGroupItem = [[NSMenuItem alloc] initWithTitle:@"Add to Existing Groups" action:nil keyEquivalent:@""];
    NSMenu *addToGroupSubmenu = [[NSMenu alloc] initWithTitle:@"Add to Groups"];
    BOOL hasAddOptions = NO;

    for (NSDictionary *group in groups) {
        NSString *groupName = group[@"name"];
        NSArray<NSString *> *members = group[@"modelNames"];
        // Only show groups the model is NOT already in
        if (![members containsObject:modelName]) {
            NSMenuItem *gItem = [[NSMenuItem alloc] initWithTitle:groupName
                                                          action:@selector(contextAddToGroup:)
                                                   keyEquivalent:@""];
            gItem.target = self;
            gItem.representedObject = groupName;
            [addToGroupSubmenu addItem:gItem];
            hasAddOptions = YES;
        }
    }

    if (hasAddOptions) {
        addToGroupItem.submenu = addToGroupSubmenu;
        [menu addItem:addToGroupItem];
    }

    // Remove from Existing Groups submenu
    NSMenuItem *removeFromGroupItem = [[NSMenuItem alloc] initWithTitle:@"Remove from Existing Groups" action:nil keyEquivalent:@""];
    NSMenu *removeFromGroupSubmenu = [[NSMenu alloc] initWithTitle:@"Remove from Groups"];
    BOOL hasRemoveOptions = NO;

    for (NSDictionary *group in groups) {
        NSString *groupName = group[@"name"];
        NSArray<NSString *> *members = group[@"modelNames"];
        // Only show groups the model IS in
        if ([members containsObject:modelName]) {
            NSMenuItem *gItem = [[NSMenuItem alloc] initWithTitle:groupName
                                                          action:@selector(contextRemoveFromGroup:)
                                                   keyEquivalent:@""];
            gItem.target = self;
            gItem.representedObject = groupName;
            [removeFromGroupSubmenu addItem:gItem];
            hasRemoveOptions = YES;
        }
    }

    if (hasRemoveOptions) {
        removeFromGroupItem.submenu = removeFromGroupSubmenu;
        [menu addItem:removeFromGroupItem];
    }
}

#pragma mark - Submenus

- (NSMenu *)buildBulkEditSubmenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Bulk Edit"];

    struct { NSString *title; XLContextMenuTag tag; } items[] = {
        { @"Active", XLContextTagBulkActive },
        { @"Inactive", XLContextTagBulkInactive },
        { @"Tag Color", XLContextTagBulkTagColor },
        { @"Preview", XLContextTagBulkPreview },
        { @"Pixel Size", XLContextTagBulkPixelSize },
        { @"Pixel Style", XLContextTagBulkPixelStyle },
        { @"Transparency", XLContextTagBulkTransparency },
        { @"Controller Name", XLContextTagBulkControllerName },
        { @"Controller Port", XLContextTagBulkControllerPort },
        { @"Controller Protocol", XLContextTagBulkControllerProtocol },
        { @"Dimming Curves", XLContextTagBulkDimmingCurves },
    };

    for (size_t i = 0; i < sizeof(items)/sizeof(items[0]); i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:items[i].title
                                                     action:@selector(contextBulkEdit:)
                                              keyEquivalent:@""];
        item.target = self;
        item.tag = items[i].tag;
        [menu addItem:item];

        // Separator after Inactive
        if (items[i].tag == XLContextTagBulkInactive) {
            [menu addItem:[NSMenuItem separatorItem]];
        }
        // Separator after Transparency
        if (items[i].tag == XLContextTagBulkTransparency) {
            [menu addItem:[NSMenuItem separatorItem]];
        }
    }

    return menu;
}

- (NSMenu *)buildAlignSubmenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Align"];

    struct { NSString *title; XLContextMenuTag tag; } items[] = {
        { @"Top", XLContextTagAlignTop },
        { @"Bottom", XLContextTagAlignBottom },
        { @"Left", XLContextTagAlignLeft },
        { @"Right", XLContextTagAlignRight },
        { @"Horizontal Center", XLContextTagAlignHCenter },
        { @"Vertical Center", XLContextTagAlignVCenter },
    };

    for (size_t i = 0; i < sizeof(items)/sizeof(items[0]); i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:items[i].title
                                                     action:@selector(contextAlign:)
                                              keyEquivalent:@""];
        item.target = self;
        item.tag = items[i].tag;
        [menu addItem:item];
    }

    return menu;
}

- (NSMenu *)buildDistributeSubmenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Distribute"];

    NSMenuItem *hItem = [[NSMenuItem alloc] initWithTitle:@"Horizontal"
                                                  action:@selector(contextDistribute:)
                                           keyEquivalent:@""];
    hItem.target = self;
    hItem.tag = XLContextTagDistributeH;
    [menu addItem:hItem];

    NSMenuItem *vItem = [[NSMenuItem alloc] initWithTitle:@"Vertical"
                                                  action:@selector(contextDistribute:)
                                           keyEquivalent:@""];
    vItem.target = self;
    vItem.tag = XLContextTagDistributeV;
    [menu addItem:vItem];

    return menu;
}

- (NSMenu *)buildResizeSubmenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Resize"];

    struct { NSString *title; XLContextMenuTag tag; } items[] = {
        { @"Match Width", XLContextTagResizeWidth },
        { @"Match Height", XLContextTagResizeHeight },
        { @"Match Size", XLContextTagResizeSize },
    };

    for (size_t i = 0; i < sizeof(items)/sizeof(items[0]); i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:items[i].title
                                                     action:@selector(contextResize:)
                                              keyEquivalent:@""];
        item.target = self;
        item.tag = items[i].tag;
        [menu addItem:item];
    }

    return menu;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    // Dynamic menu is built in menuNeedsUpdate:, items are always valid
    return YES;
}

#pragma mark - Context Menu Actions (Basic)

- (void)contextAddModel:(NSMenuItem *)sender {
    NSString *modelType = sender.representedObject;
    if ([_delegate respondsToSelector:@selector(modelTree:didRequestAddModelOfType:)]) {
        [_delegate modelTree:self didRequestAddModelOfType:modelType];
    }
}

- (void)contextAddGroup:(id)sender {
    if ([_delegate respondsToSelector:@selector(modelTree:didRequestAddModelOfType:)]) {
        [_delegate modelTree:self didRequestAddModelOfType:@"Group"];
    }
}

- (void)contextImportModel:(id)sender {
    if ([_delegate respondsToSelector:@selector(modelTreeDidRequestImportModel:)]) {
        [_delegate modelTreeDidRequestImportModel:self];
    }
}

- (void)contextDuplicate:(id)sender {
    NSString *name = [self selectedModelName];
    if (name && [_delegate respondsToSelector:@selector(modelTree:didRequestDuplicateModel:)]) {
        [_delegate modelTree:self didRequestDuplicateModel:name];
    }
}

- (void)contextCreateShadowModel:(id)sender {
    NSString *name = [self selectedModelName];
    if (!name || !_engineBridge) return;

    NSString *shadowName = [_engineBridge createShadowModel:name];
    if (!shadowName) {
        NSLog(@"XLModelTreeViewController: Failed to create shadow model for %@", name);
        return;
    }

    [self loadModelTreeFromEngine];
    _filteredNodes = _allNodes;
    _rootNodes = _filteredNodes;
    [_outlineView reloadData];

    [self selectModelWithName:shadowName];

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"XLModelListDidChangeNotification"
                      object:self];
}

- (void)contextDelete:(id)sender {
    NSArray<NSString *> *names = [self selectedModelNames];
    if (names.count == 0) return;

    NSString *message;
    if (names.count == 1) {
        message = [NSString stringWithFormat:@"Delete \"%@\"?", names.firstObject];
    } else {
        message = [NSString stringWithFormat:@"Delete %lu selected items?", (unsigned long)names.count];
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = @"This action cannot be undone.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;
    alert.buttons.firstObject.hasDestructiveAction = YES;

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            if ([self.delegate respondsToSelector:@selector(modelTree:didRequestDeleteModel:)]) {
                for (NSString *name in names) {
                    [self.delegate modelTree:self didRequestDeleteModel:name];
                }
            }
        }
    }];
}

- (void)contextGroupSelected:(id)sender {
    NSArray<NSString *> *names = [self selectedModelNames];
    if (names.count >= 1 && [_delegate respondsToSelector:@selector(modelTree:didRequestGroupModels:)]) {
        [_delegate modelTree:self didRequestGroupModels:names];
    }
}

- (void)contextUngroup:(id)sender {
    NSString *name = [self selectedModelName];
    if (name && [_delegate respondsToSelector:@selector(modelTree:didRequestUngroupModel:)]) {
        [_delegate modelTree:self didRequestUngroupModel:name];
    }
}

- (void)contextRename:(id)sender {
    NSInteger row = _outlineView.selectedRow;
    if (row >= 0) {
        NSTableCellView *cellView = [_outlineView viewAtColumn:0 row:row makeIfNecessary:NO];
        if (cellView && cellView.textField) {
            cellView.textField.editable = YES;
            cellView.textField.delegate = (id<NSTextFieldDelegate>)self;
            [cellView.textField becomeFirstResponder];
        }
    }
}

#pragma mark - Context Menu Actions (Lock / Unlock)

- (void)contextLock:(id)sender {
    NSString *name = [self selectedModelName];
    if (name && [_delegate respondsToSelector:@selector(modelTree:didRequestLockModel:locked:)]) {
        [_delegate modelTree:self didRequestLockModel:name locked:YES];
    }
}

- (void)contextUnlock:(id)sender {
    NSString *name = [self selectedModelName];
    if (name && [_delegate respondsToSelector:@selector(modelTree:didRequestLockModel:locked:)]) {
        [_delegate modelTree:self didRequestLockModel:name locked:NO];
    }
}

- (void)contextLockAll:(id)sender {
    NSArray<NSString *> *names = [self selectedModelNames];
    if ([_delegate respondsToSelector:@selector(modelTree:didRequestLockModel:locked:)]) {
        for (NSString *name in names) {
            [_delegate modelTree:self didRequestLockModel:name locked:YES];
        }
    }
}

- (void)contextUnlockAll:(id)sender {
    NSArray<NSString *> *names = [self selectedModelNames];
    if ([_delegate respondsToSelector:@selector(modelTree:didRequestLockModel:locked:)]) {
        for (NSString *name in names) {
            [_delegate modelTree:self didRequestLockModel:name locked:NO];
        }
    }
}

#pragma mark - Context Menu Actions (Flip)

- (void)contextFlipHorizontal:(id)sender {
    NSArray<NSString *> *names = [self selectedModelNames];
    if ([_delegate respondsToSelector:@selector(modelTree:didRequestFlipModel:horizontal:)]) {
        for (NSString *name in names) {
            [_delegate modelTree:self didRequestFlipModel:name horizontal:YES];
        }
    }
}

- (void)contextFlipVertical:(id)sender {
    NSArray<NSString *> *names = [self selectedModelNames];
    if ([_delegate respondsToSelector:@selector(modelTree:didRequestFlipModel:horizontal:)]) {
        for (NSString *name in names) {
            [_delegate modelTree:self didRequestFlipModel:name horizontal:NO];
        }
    }
}

#pragma mark - Context Menu Actions (Replace Model)

- (void)contextReplaceModel:(id)sender {
    NSString *replacementModelName = [self selectedModelName];
    if (!replacementModelName || !_engineBridge) return;

    // Build list of models that can be replaced (all models except the selected one)
    NSArray<NSString *> *allModelNames = [_engineBridge getModelNamesExcludingGroups];
    NSMutableArray<NSString *> *choices = [[NSMutableArray alloc] init];
    for (NSString *name in allModelNames) {
        if (![name isEqualToString:replacementModelName]) {
            [choices addObject:name];
        }
    }

    if (choices.count == 0) return;

    // Show picker to select the model to replace
    NSAlert *pickerAlert = [[NSAlert alloc] init];
    pickerAlert.messageText = @"Replace Model";
    pickerAlert.informativeText = [NSString stringWithFormat:@"Select the model to replace with \"%@\".", replacementModelName];
    [pickerAlert addButtonWithTitle:@"Replace"];
    [pickerAlert addButtonWithTitle:@"Cancel"];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 300, 25) pullsDown:NO];
    [popup addItemsWithTitles:choices];
    pickerAlert.accessoryView = popup;

    [pickerAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) return;

        NSString *targetModelName = popup.titleOfSelectedItem;
        if (!targetModelName) return;

        // Ask about start channel
        BOOL copyStartChannel = NO;
        NSString *targetStartChannel = [self->_engineBridge getModelProperty:targetModelName key:@"ModelStartChannel" defaultValue:@""];
        NSString *replacementStartChannel = [self->_engineBridge getModelProperty:replacementModelName key:@"ModelStartChannel" defaultValue:@""];
        NSString *targetController = [self->_engineBridge getModelProperty:targetModelName key:@"Controller" defaultValue:@""];
        NSString *replacementController = [self->_engineBridge getModelProperty:replacementModelName key:@"Controller" defaultValue:@""];

        BOOL channelsDiffer = ![targetStartChannel isEqualToString:replacementStartChannel];
        BOOL controllersDiffer = ![targetController isEqualToString:replacementController] &&
            (replacementController.length == 0 || [replacementController isEqualToString:@"No Controller"]);

        if (channelsDiffer || controllersDiffer) {
            NSString *msg = [NSString stringWithFormat:
                @"Should I copy the replaced model's start channel '%@' to the replacement model whose start channel is currently '%@'?",
                targetStartChannel, replacementStartChannel];
            NSAlert *channelAlert = [[NSAlert alloc] init];
            channelAlert.messageText = @"Update Start Channel";
            channelAlert.informativeText = msg;
            [channelAlert addButtonWithTitle:@"Yes"];
            [channelAlert addButtonWithTitle:@"No"];
            copyStartChannel = ([channelAlert runModal] == NSAlertFirstButtonReturn);
        }

        // Ask about submodels
        BOOL mergeSubmodels = NO;
        NSArray<NSDictionary *> *targetSubmodels = [self->_engineBridge getSubmodels:targetModelName];
        if (targetSubmodels.count > 0) {
            NSAlert *subAlert = [[NSAlert alloc] init];
            subAlert.messageText = @"Merge Submodels";
            subAlert.informativeText = [NSString stringWithFormat:
                @"The model being replaced has %lu submodel(s). Merge them into the replacement?",
                (unsigned long)targetSubmodels.count];
            [subAlert addButtonWithTitle:@"Yes"];
            [subAlert addButtonWithTitle:@"No"];
            mergeSubmodels = ([subAlert runModal] == NSAlertFirstButtonReturn);
        }

        // Ask about position
        BOOL copyPosition = NO;
        {
            NSString *msg = [NSString stringWithFormat:
                @"Use original size and position of \"%@\"?", targetModelName];
            NSAlert *posAlert = [[NSAlert alloc] init];
            posAlert.messageText = @"Use Original Position";
            posAlert.informativeText = msg;
            [posAlert addButtonWithTitle:@"Yes"];
            [posAlert addButtonWithTitle:@"No"];
            copyPosition = ([posAlert runModal] == NSAlertFirstButtonReturn);
        }

        // Perform the replacement
        NSDictionary *options = @{
            @"copyStartChannel": @(copyStartChannel),
            @"copyPosition": @(copyPosition),
            @"mergeSubmodels": @(mergeSubmodels),
        };

        if ([self.delegate respondsToSelector:@selector(modelTree:didRequestReplaceModel:withModel:options:)]) {
            [self.delegate modelTree:self
              didRequestReplaceModel:targetModelName
                           withModel:replacementModelName
                             options:options];
        }
    }];
}

#pragma mark - Context Menu Actions (Placeholder Dialogs)

- (void)contextNodeLayout:(id)sender {
    [self showNotImplementedAlert:@"Node Layout"
                          detail:@"The Node Layout dialog will allow visual editing of individual node positions within the model."];
}

- (void)contextEditSubmodels:(id)sender {
    NSString *name = [self selectedModelName];
    if (!name || !_engineBridge) return;

    _subModelsWindow = [[XLSubModelsWindow alloc] initWithModelName:name];
    _subModelsWindow.engineBridge = _engineBridge;
    [_subModelsWindow showWithCompletion:^(BOOL saved) {
        self->_subModelsWindow = nil;
        if (saved) {
            [self reloadData];
        }
    }];
}

- (void)contextEditStates:(id)sender {
    NSString *name = [self selectedModelName];
    if (!name || !_engineBridge) return;

    _stateDialog = [[XLModelStateWindow alloc] initWithModelName:name];
    _stateDialog.engineBridge = _engineBridge;

    // Load state definitions from bridge
    NSDictionary *stateData = [_engineBridge getAllStateDefinitions:name];
    if (stateData) {
        [_stateDialog setStateInfo:stateData];
    }

    [_stateDialog showWithCompletion:^(BOOL saved) {
        if (saved) {
            // Save state definitions back through bridge
            NSDictionary *updatedStates = [self->_stateDialog stateInfo];
            if (updatedStates) {
                [self->_engineBridge setAllStateDefinitions:name definitions:updatedStates];
            }
            [self reloadData];
        }
        self->_stateDialog = nil;
    }];
}

- (void)contextEditFaces:(id)sender {
    NSString *name = [self selectedModelName];
    if (!name || !_engineBridge) return;

    _faceDialog = [[XLModelFaceWindow alloc] initWithModelName:name];
    _faceDialog.engineBridge = _engineBridge;

    // Load face definitions from bridge
    NSDictionary *faceData = [_engineBridge getAllFaceDefinitions:name];
    if (faceData) {
        [_faceDialog setFaceInfo:faceData];
    }

    [_faceDialog showWithCompletion:^(BOOL saved) {
        if (saved) {
            // Save face definitions back through bridge
            NSDictionary *updatedFaces = [self->_faceDialog faceInfo];
            if (updatedFaces) {
                [self->_engineBridge setAllFaceDefinitions:name definitions:updatedFaces];
            }
            [self reloadData];
        }
        self->_faceDialog = nil;
    }];
}

- (void)contextWiringView:(id)sender {
    [self showNotImplementedAlert:@"Wiring View"
                          detail:@"The Wiring View dialog will show the physical wiring order and connections for the model."];
}

- (void)contextExportAsCustom:(id)sender {
    [self showNotImplementedAlert:@"Export as Custom xLights Model"
                          detail:@"This will export the current model as a Custom model type that can be imported into other shows."];
}

- (void)contextExportXModel:(id)sender {
    [self showNotImplementedAlert:@"Export xLights Model (.xmodel)"
                          detail:@"This will export the current model as an .xmodel file that can be shared and imported."];
}

- (void)showNotImplementedAlert:(NSString *)feature detail:(NSString *)detail {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"%@ - Not Yet Implemented", feature];
    alert.informativeText = detail;
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    if (self.view.window) {
        [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
    } else {
        [alert runModal];
    }
}

#pragma mark - Context Menu Actions (Group Membership)

- (void)contextAddToGroup:(NSMenuItem *)sender {
    NSString *groupName = sender.representedObject;
    NSArray<NSString *> *names = [self selectedModelNames];
    if (groupName && names.count > 0 && [_delegate respondsToSelector:@selector(modelTree:didRequestAddModels:toGroup:)]) {
        [_delegate modelTree:self didRequestAddModels:names toGroup:groupName];
    }
}

- (void)contextRemoveFromGroup:(NSMenuItem *)sender {
    NSString *groupName = sender.representedObject;
    NSString *modelName = [self selectedModelName];
    if (groupName && modelName && [_delegate respondsToSelector:@selector(modelTree:didRequestRemoveModel:fromGroup:)]) {
        [_delegate modelTree:self didRequestRemoveModel:modelName fromGroup:groupName];
    }
}

- (void)contextCloneGroup:(id)sender {
    NSString *name = [self selectedModelName];
    if (name && [_delegate respondsToSelector:@selector(modelTree:didRequestCloneGroup:)]) {
        [_delegate modelTree:self didRequestCloneGroup:name];
    }
}

- (void)contextDeleteEmptyGroups:(id)sender {
    if (!_engineBridge) return;

    NSArray<NSDictionary *> *groups = [_engineBridge getModelGroups];
    NSMutableArray<NSString *> *emptyGroups = [[NSMutableArray alloc] init];

    for (NSDictionary *group in groups) {
        NSArray *members = group[@"modelNames"];
        if (members.count == 0) {
            [emptyGroups addObject:group[@"name"]];
        }
    }

    if (emptyGroups.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Empty Groups";
        alert.informativeText = @"All groups contain at least one model.";
        alert.alertStyle = NSAlertStyleInformational;
        [alert addButtonWithTitle:@"OK"];
        if (self.view.window) {
            [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
        } else {
            [alert runModal];
        }
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Delete %lu Empty Group%@?",
                         (unsigned long)emptyGroups.count,
                         emptyGroups.count == 1 ? @"" : @"s"];
    alert.informativeText = [NSString stringWithFormat:@"The following empty groups will be deleted:\n%@",
                             [emptyGroups componentsJoinedByString:@", "]];
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;
    alert.buttons.firstObject.hasDestructiveAction = YES;

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            if ([self.delegate respondsToSelector:@selector(modelTree:didRequestDeleteModel:)]) {
                for (NSString *groupName in emptyGroups) {
                    [self.delegate modelTree:self didRequestDeleteModel:groupName];
                }
            }
            [self reloadData];
        }
    }];
}

- (void)contextManageGroups:(id)sender {
    if ([_delegate respondsToSelector:@selector(modelTreeDidRequestManageGroups:)]) {
        [_delegate modelTreeDidRequestManageGroups:self];
    }
}

#pragma mark - Context Menu Actions (Bulk Edit)

- (void)contextBulkEdit:(NSMenuItem *)sender {
    NSArray<NSString *> *names = [self selectedModelNames];
    if (names.count == 0 || !_engineBridge) return;

    switch (sender.tag) {
        case XLContextTagBulkActive:
            [self bulkSetProperty:@"Active" value:@"1" forModels:names];
            break;
        case XLContextTagBulkInactive:
            [self bulkSetProperty:@"Active" value:@"0" forModels:names];
            break;
        case XLContextTagBulkTagColor:
            [self bulkEditTagColorForModels:names];
            break;
        case XLContextTagBulkPreview:
            [self bulkEditPreviewForModels:names];
            break;
        case XLContextTagBulkPixelSize:
            [self bulkEditPixelSizeForModels:names];
            break;
        case XLContextTagBulkPixelStyle:
            [self bulkEditPixelStyleForModels:names];
            break;
        case XLContextTagBulkTransparency:
            [self bulkEditTransparencyForModels:names];
            break;
        case XLContextTagBulkControllerName:
            [self bulkEditControllerNameForModels:names];
            break;
        case XLContextTagBulkControllerPort:
            [self bulkEditControllerPortForModels:names];
            break;
        case XLContextTagBulkControllerProtocol:
            [self bulkEditControllerProtocolForModels:names];
            break;
        case XLContextTagBulkDimmingCurves:
            [self bulkEditDimmingCurvesForModels:names];
            break;
        default:
            break;
    }
}

- (void)bulkSetProperty:(NSString *)key value:(NSString *)value forModels:(NSArray<NSString *> *)modelNames {
    for (NSString *name in modelNames) {
        [_engineBridge updateModelProperty:name key:key value:value];
    }
    [self reloadData];
}

- (void)bulkEditDimmingCurvesForModels:(NSArray<NSString *> *)modelNames {
    if (!modelNames || modelNames.count == 0 || !_engineBridge) return;

    // Use the first model's dimming info as initial values
    NSString *firstModel = modelNames.firstObject;
    NSDictionary *dimmingInfo = [_engineBridge getDimmingInfo:firstModel];

    if (!dimmingInfo || dimmingInfo.count == 0) {
        NSString *brightness = [_engineBridge getModelProperty:firstModel key:@"ModelBrightness" defaultValue:@"0"];
        dimmingInfo = @{
            @"all": @{
                @"gamma": @"1.0",
                @"brightness": brightness ?: @"0"
            }
        };
    }

    XLModelDimmingCurveDialog *dialog = [[XLModelDimmingCurveDialog alloc] init];
    dialog.modelName = [NSString stringWithFormat:@"%lu models", (unsigned long)modelNames.count];
    [dialog initFromDimmingInfo:dimmingInfo];

    NSWindow *parentWindow = self.view.window;
    if (!parentWindow) return;

    [dialog presentAsSheetForWindow:parentWindow completion:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            NSDictionary *newInfo = [dialog exportDimmingInfo];
            for (NSString *name in modelNames) {
                [self->_engineBridge setDimmingInfo:newInfo forModel:name];
            }
            [self reloadData];
        }
    }];
}

- (void)bulkEditTagColorForModels:(NSArray<NSString *> *)modelNames {
    NSColorPanel *colorPanel = [NSColorPanel sharedColorPanel];
    colorPanel.showsAlpha = NO;
    colorPanel.color = [NSColor whiteColor];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Tag Color";
    alert.informativeText = [NSString stringWithFormat:@"Choose a tag color for %lu selected models.", (unsigned long)modelNames.count];
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];

    NSColorWell *colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 60, 30)];
    colorWell.color = [NSColor cyanColor];
    alert.accessoryView = colorWell;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSColor *color = [colorWell.color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        CGFloat r, g, b, a;
        [color getRed:&r green:&g blue:&b alpha:&a];
        NSString *colorStr = [NSString stringWithFormat:@"#%02X%02X%02X",
                              (int)(r * 255), (int)(g * 255), (int)(b * 255)];
        [self bulkSetProperty:@"TagColour" value:colorStr forModels:modelNames];
    }
}

- (void)bulkEditPreviewForModels:(NSArray<NSString *> *)modelNames {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Preview Group";
    alert.informativeText = [NSString stringWithFormat:@"Enter the preview/layout group for %lu selected models.", (unsigned long)modelNames.count];
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
    input.stringValue = @"Default";
    input.placeholderString = @"Preview Group Name";
    alert.accessoryView = input;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *value = input.stringValue;
        if (value.length > 0) {
            [self bulkSetProperty:@"LayoutGroup" value:value forModels:modelNames];
        }
    }
}

- (void)bulkEditPixelSizeForModels:(NSArray<NSString *> *)modelNames {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Pixel Size";
    alert.informativeText = [NSString stringWithFormat:@"Choose pixel size for %lu selected models.", (unsigned long)modelNames.count];
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 30)];
    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(0, 0, 190, 20)];
    slider.minValue = 1;
    slider.maxValue = 10;
    slider.integerValue = 2;
    slider.numberOfTickMarks = 10;
    slider.allowsTickMarkValuesOnly = YES;

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(200, 2, 50, 20)];
    label.editable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    label.stringValue = @"2";
    label.alignment = NSTextAlignmentRight;

    // Bind label to slider value
    [label bind:NSValueBinding toObject:slider withKeyPath:@"integerValue" options:nil];

    [container addSubview:slider];
    [container addSubview:label];
    alert.accessoryView = container;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *value = [NSString stringWithFormat:@"%ld", (long)slider.integerValue];
        [self bulkSetProperty:@"PixelSize" value:value forModels:modelNames];
    }
}

- (void)bulkEditPixelStyleForModels:(NSArray<NSString *> *)modelNames {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Pixel Style";
    alert.informativeText = [NSString stringWithFormat:@"Choose pixel style for %lu selected models.", (unsigned long)modelNames.count];
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 250, 25) pullsDown:NO];
    [popup addItemsWithTitles:@[@"Square", @"Circle", @"Smooth Circle", @"Blended Circle"]];
    alert.accessoryView = popup;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        // Pixel style is stored as an integer index
        NSString *value = [NSString stringWithFormat:@"%ld", (long)popup.indexOfSelectedItem];
        [self bulkSetProperty:@"PixelStyle" value:value forModels:modelNames];
    }
}

- (void)bulkEditTransparencyForModels:(NSArray<NSString *> *)modelNames {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Transparency";
    alert.informativeText = [NSString stringWithFormat:@"Choose transparency for %lu selected models (0 = opaque, 100 = fully transparent).", (unsigned long)modelNames.count];
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 30)];
    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(0, 0, 190, 20)];
    slider.minValue = 0;
    slider.maxValue = 100;
    slider.integerValue = 0;

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(200, 2, 50, 20)];
    label.editable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    label.stringValue = @"0";
    label.alignment = NSTextAlignmentRight;

    [label bind:NSValueBinding toObject:slider withKeyPath:@"integerValue" options:nil];

    [container addSubview:slider];
    [container addSubview:label];
    alert.accessoryView = container;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *value = [NSString stringWithFormat:@"%ld", (long)slider.integerValue];
        [self bulkSetProperty:@"Transparency" value:value forModels:modelNames];
    }
}

- (void)bulkEditControllerNameForModels:(NSArray<NSString *> *)modelNames {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Controller Name";
    alert.informativeText = [NSString stringWithFormat:@"Choose controller for %lu selected models.", (unsigned long)modelNames.count];
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 250, 25) pullsDown:NO];
    [popup addItemWithTitle:@"(None)"];
    NSArray<NSString *> *controllerNames = [_engineBridge getControllerNames];
    if (controllerNames.count > 0) {
        [popup addItemsWithTitles:controllerNames];
    }
    alert.accessoryView = popup;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *value = popup.titleOfSelectedItem;
        if ([value isEqualToString:@"(None)"]) {
            value = @"";
        }
        [self bulkSetProperty:@"Controller" value:value forModels:modelNames];
    }
}

- (void)bulkEditControllerPortForModels:(NSArray<NSString *> *)modelNames {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Controller Port";
    alert.informativeText = [NSString stringWithFormat:@"Enter the port number for %lu selected models.", (unsigned long)modelNames.count];
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    input.placeholderString = @"Port #";
    input.stringValue = @"1";

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimum = @(1);
    formatter.maximum = @(512);
    formatter.allowsFloats = NO;
    input.formatter = formatter;

    alert.accessoryView = input;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *value = input.stringValue;
        if (value.length > 0) {
            [self bulkSetProperty:@"ControllerPort" value:value forModels:modelNames];
        }
    }
}

- (void)bulkEditControllerProtocolForModels:(NSArray<NSString *> *)modelNames {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Controller Protocol";
    alert.informativeText = [NSString stringWithFormat:@"Choose protocol for %lu selected models.", (unsigned long)modelNames.count];
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 250, 25) pullsDown:NO];
    [popup addItemsWithTitles:@[@"ws2811", @"WS2801", @"TLS3001", @"LPD6803", @"LPD8806",
                                @"APA102", @"APA109", @"ICICOB", @"SM16716",
                                @"DMX", @"LOR", @"Renard", @"Open DMX"]];
    alert.accessoryView = popup;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *value = popup.titleOfSelectedItem;
        [self bulkSetProperty:@"Protocol" value:value forModels:modelNames];
    }
}

#pragma mark - Context Menu Actions (Align / Distribute / Resize)

- (void)contextAlign:(NSMenuItem *)sender {
    NSArray<NSString *> *names = [self selectedModelNames];
    if (names.count < 2 || !_engineBridge) {
        return;
    }

    NSString *alignType;
    switch (sender.tag) {
        case XLContextTagAlignTop:     alignType = @"top"; break;
        case XLContextTagAlignBottom:  alignType = @"bottom"; break;
        case XLContextTagAlignLeft:    alignType = @"left"; break;
        case XLContextTagAlignRight:   alignType = @"right"; break;
        case XLContextTagAlignHCenter: alignType = @"hcenter"; break;
        case XLContextTagAlignVCenter: alignType = @"vcenter"; break;
        default: return;
    }

    // Get the reference model bounds (first selected model)
    NSDictionary *refBounds = [_engineBridge getModelBounds:names.firstObject];
    if (!refBounds) return;

    float refMinX = [refBounds[@"minX"] floatValue];
    float refMaxX = [refBounds[@"maxX"] floatValue];
    float refMinY = [refBounds[@"minY"] floatValue];
    float refMaxY = [refBounds[@"maxY"] floatValue];
    float refCenterX = (refMinX + refMaxX) / 2.0f;
    float refCenterY = (refMinY + refMaxY) / 2.0f;

    for (NSUInteger i = 1; i < names.count; i++) {
        NSString *modelName = names[i];
        NSDictionary *bounds = [_engineBridge getModelBounds:modelName];
        if (!bounds) continue;

        float curMinX = [bounds[@"minX"] floatValue];
        float curMaxX = [bounds[@"maxX"] floatValue];
        float curMinY = [bounds[@"minY"] floatValue];
        float curMaxY = [bounds[@"maxY"] floatValue];

        float offsetX = 0, offsetY = 0;

        if ([alignType isEqualToString:@"top"]) {
            offsetY = refMaxY - curMaxY;
        } else if ([alignType isEqualToString:@"bottom"]) {
            offsetY = refMinY - curMinY;
        } else if ([alignType isEqualToString:@"left"]) {
            offsetX = refMinX - curMinX;
        } else if ([alignType isEqualToString:@"right"]) {
            offsetX = refMaxX - curMaxX;
        } else if ([alignType isEqualToString:@"hcenter"]) {
            float curCenterX = (curMinX + curMaxX) / 2.0f;
            offsetX = refCenterX - curCenterX;
        } else if ([alignType isEqualToString:@"vcenter"]) {
            float curCenterY = (curMinY + curMaxY) / 2.0f;
            offsetY = refCenterY - curCenterY;
        }

        if (offsetX != 0 || offsetY != 0) {
            // Read current position and apply offset
            NSString *curWorldX = [_engineBridge getModelProperty:modelName key:@"WorldPosX" defaultValue:@"0"];
            NSString *curWorldY = [_engineBridge getModelProperty:modelName key:@"WorldPosY" defaultValue:@"0"];
            float newX = [curWorldX floatValue] + offsetX;
            float newY = [curWorldY floatValue] + offsetY;
            [_engineBridge updateModelProperty:modelName key:@"WorldPosX" value:[NSString stringWithFormat:@"%.6f", newX]];
            [_engineBridge updateModelProperty:modelName key:@"WorldPosY" value:[NSString stringWithFormat:@"%.6f", newY]];
        }
    }
}

- (void)contextDistribute:(NSMenuItem *)sender {
    NSArray<NSString *> *names = [self selectedModelNames];
    if (names.count < 3 || !_engineBridge) {
        if (names.count < 3) {
            [self showNotImplementedAlert:@"Distribute"
                                  detail:@"Distribute requires at least 3 selected models."];
        }
        return;
    }

    BOOL horizontal = (sender.tag == XLContextTagDistributeH);

    // Gather centers and sort by position
    NSMutableArray<NSDictionary *> *modelPositions = [[NSMutableArray alloc] init];
    for (NSString *name in names) {
        NSDictionary *bounds = [_engineBridge getModelBounds:name];
        if (!bounds) continue;
        float center;
        if (horizontal) {
            center = ([bounds[@"minX"] floatValue] + [bounds[@"maxX"] floatValue]) / 2.0f;
        } else {
            center = ([bounds[@"minY"] floatValue] + [bounds[@"maxY"] floatValue]) / 2.0f;
        }
        [modelPositions addObject:@{ @"name": name, @"center": @(center) }];
    }

    [modelPositions sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"center"] compare:b[@"center"]];
    }];

    if (modelPositions.count < 3) return;

    float firstCenter = [modelPositions.firstObject[@"center"] floatValue];
    float lastCenter = [modelPositions.lastObject[@"center"] floatValue];
    float step = (lastCenter - firstCenter) / (float)(modelPositions.count - 1);

    for (NSUInteger i = 1; i < modelPositions.count - 1; i++) {
        NSString *modelName = modelPositions[i][@"name"];
        float currentCenter = [modelPositions[i][@"center"] floatValue];
        float targetCenter = firstCenter + step * (float)i;
        float offset = targetCenter - currentCenter;

        if (offset != 0) {
            NSString *key = horizontal ? @"WorldPosX" : @"WorldPosY";
            NSString *curVal = [_engineBridge getModelProperty:modelName key:key defaultValue:@"0"];
            float newVal = [curVal floatValue] + offset;
            [_engineBridge updateModelProperty:modelName key:key value:[NSString stringWithFormat:@"%.6f", newVal]];
        }
    }
}

- (void)contextResize:(NSMenuItem *)sender {
    NSArray<NSString *> *names = [self selectedModelNames];
    if (names.count < 2 || !_engineBridge) {
        return;
    }

    BOOL matchWidth = (sender.tag == XLContextTagResizeWidth || sender.tag == XLContextTagResizeSize);
    BOOL matchHeight = (sender.tag == XLContextTagResizeHeight || sender.tag == XLContextTagResizeSize);

    // Reference is the first selected model
    NSDictionary *refBounds = [_engineBridge getModelBounds:names.firstObject];
    if (!refBounds) return;

    float refWidth = [refBounds[@"maxX"] floatValue] - [refBounds[@"minX"] floatValue];
    float refHeight = [refBounds[@"maxY"] floatValue] - [refBounds[@"minY"] floatValue];

    for (NSUInteger i = 1; i < names.count; i++) {
        NSString *modelName = names[i];
        NSDictionary *bounds = [_engineBridge getModelBounds:modelName];
        if (!bounds) continue;

        float curWidth = [bounds[@"maxX"] floatValue] - [bounds[@"minX"] floatValue];
        float curHeight = [bounds[@"maxY"] floatValue] - [bounds[@"minY"] floatValue];

        if (matchWidth && curWidth > 0) {
            NSString *curScaleX = [_engineBridge getModelProperty:modelName key:@"ScaleX" defaultValue:@"1"];
            float scaleX = [curScaleX floatValue] * (refWidth / curWidth);
            [_engineBridge updateModelProperty:modelName key:@"ScaleX" value:[NSString stringWithFormat:@"%.6f", scaleX]];
        }
        if (matchHeight && curHeight > 0) {
            NSString *curScaleY = [_engineBridge getModelProperty:modelName key:@"ScaleY" defaultValue:@"1"];
            float scaleY = [curScaleY floatValue] * (refHeight / curHeight);
            [_engineBridge updateModelProperty:modelName key:@"ScaleY" value:[NSString stringWithFormat:@"%.6f", scaleY]];
        }
    }
}

#pragma mark - NSTextFieldDelegate (Rename)

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *field = notification.object;
    if (field == _searchField) return;

    NSInteger row = _outlineView.selectedRow;
    if (row < 0) return;

    XLModelTreeNode *node = [_outlineView itemAtRow:row];
    if (!node) return;

    NSString *newName = field.stringValue;
    NSString *oldName = node.name;

    field.editable = NO;

    if (newName.length > 0 && ![newName isEqualToString:oldName]) {
        if ([_delegate respondsToSelector:@selector(modelTree:didRequestRenameModel:toName:)]) {
            [_delegate modelTree:self didRequestRenameModel:oldName toName:newName];
        }
    } else {
        field.stringValue = oldName;
    }
}

#pragma mark - Footer Button Actions

- (void)footerButtonClicked:(NSSegmentedControl *)sender {
    NSInteger segment = sender.selectedSegment;

    switch (segment) {
        case 0: // Add
            [self showAddModelMenu];
            break;
        case 1: // Remove
            [self contextDelete:sender];
            break;
        case 2: // Group
            [self contextGroupSelected:sender];
            break;
    }
}

- (void)showAddModelMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Add"];

    NSArray *modelTypes = @[
        @"Single Line", @"Matrix", @"Arch", @"Custom", @"Tree",
        @"Spinner", @"Sphere", @"Cube", @"Star",
    ];

    for (NSString *type in modelTypes) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:type
                                                      action:@selector(contextAddModel:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = type;
        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *groupItem = [[NSMenuItem alloc] initWithTitle:@"New Group"
                                                      action:@selector(contextAddGroup:)
                                               keyEquivalent:@""];
    groupItem.target = self;
    [menu addItem:groupItem];

    NSRect buttonRect = [_footerButtons convertRect:[_footerButtons bounds] toView:nil];
    NSPoint menuLocation = NSMakePoint(NSMinX(buttonRect), NSMinY(buttonRect));
    menuLocation = [self.view.window convertRectToScreen:NSMakeRect(menuLocation.x, menuLocation.y, 0, 0)].origin;

    [menu popUpMenuPositioningItem:nil atLocation:NSZeroPoint inView:_footerButtons];
}

#pragma mark - Selection

- (void)selectModelWithName:(NSString *)name {
    if (!name) return;

    _suppressSelectionNotification = YES;

    XLModelTreeNode *targetNode = [self findNodeWithName:name inNodes:_rootNodes];
    if (targetNode) {
        // Expand parent if needed
        if (targetNode.parent) {
            [_outlineView expandItem:targetNode.parent];
        }

        NSInteger row = [_outlineView rowForItem:targetNode];
        if (row >= 0) {
            NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:(NSUInteger)row];
            [_outlineView selectRowIndexes:indexSet byExtendingSelection:NO];
            [_outlineView scrollRowToVisible:row];
        }
    }

    _suppressSelectionNotification = NO;
}

- (void)selectModelsWithNames:(NSArray<NSString *> *)names {
    if (!names || names.count == 0) return;

    _suppressSelectionNotification = YES;

    NSMutableIndexSet *indexSet = [[NSMutableIndexSet alloc] init];

    for (NSString *name in names) {
        XLModelTreeNode *targetNode = [self findNodeWithName:name inNodes:_rootNodes];
        if (targetNode) {
            if (targetNode.parent) {
                [_outlineView expandItem:targetNode.parent];
            }
            NSInteger row = [_outlineView rowForItem:targetNode];
            if (row >= 0) {
                [indexSet addIndex:(NSUInteger)row];
            }
        }
    }

    if (indexSet.count > 0) {
        [_outlineView selectRowIndexes:indexSet byExtendingSelection:NO];
        [_outlineView scrollRowToVisible:(NSInteger)indexSet.firstIndex];
    }

    _suppressSelectionNotification = NO;
}

- (XLModelTreeNode *)findNodeWithName:(NSString *)name inNodes:(NSArray<XLModelTreeNode *> *)nodes {
    for (XLModelTreeNode *node in nodes) {
        if ([node.name isEqualToString:name]) {
            return node;
        }
        XLModelTreeNode *child = [self findNodeWithName:name inNodes:node.children];
        if (child) return child;
    }
    return nil;
}

- (NSString *)selectedModelName {
    NSInteger row = _outlineView.selectedRow;
    if (row < 0) return nil;

    XLModelTreeNode *node = [_outlineView itemAtRow:row];
    return node.name;
}

- (NSArray<NSString *> *)selectedModelNames {
    NSIndexSet *selectedRows = _outlineView.selectedRowIndexes;
    NSMutableArray<NSString *> *names = [[NSMutableArray alloc] init];

    [selectedRows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        XLModelTreeNode *node = [self.outlineView itemAtRow:(NSInteger)idx];
        if (node && !node.isSubmodel) {
            [names addObject:node.name];
        }
    }];

    return [names copy];
}

#pragma mark - Expand / Collapse

- (void)expandAll {
    [_outlineView expandItem:nil expandChildren:YES];
}

- (void)collapseAll {
    [_outlineView collapseItem:nil collapseChildren:YES];
}

#pragma mark - Setters

- (void)setRootNodes:(NSArray<XLModelTreeNode *> *)rootNodes {
    _rootNodes = [rootNodes copy];
    _allNodes = [rootNodes copy];
    [_outlineView reloadData];
}

- (void)setShow3D:(BOOL)show3D {
    _show3D = show3D;
    _tabControl.hidden = !show3D;

    if (!show3D) {
        // Switch back to Models tab when leaving 3D mode
        _tabControl.selectedSegment = XLTreeTabModels;
        _modelsContainer.hidden = NO;
        _viewObjectsContainer.hidden = YES;
    }
}

#pragma mark - Tab Control

- (void)tabControlChanged:(NSSegmentedControl *)sender {
    XLTreeTab selectedTab = (XLTreeTab)sender.selectedSegment;

    switch (selectedTab) {
        case XLTreeTabModels:
            _modelsContainer.hidden = NO;
            _viewObjectsContainer.hidden = YES;
            break;

        case XLTreeTabViewObjects:
            _modelsContainer.hidden = YES;
            _viewObjectsContainer.hidden = NO;
            [self reloadViewObjects];
            break;
    }
}

#pragma mark - 3D Objects Data

- (void)reloadViewObjects {
    [_viewObjectsData removeAllObjects];

    if (_engineBridge) {
        NSArray<NSDictionary *> *objects = [_engineBridge getViewObjects];
        [_viewObjectsData addObjectsFromArray:objects];
    }

    [_viewObjectsTable reloadData];
}

#pragma mark - 3D Objects NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == _viewObjectsTable) {
        return (NSInteger)_viewObjectsData.count;
    }
    return 0;
}

#pragma mark - 3D Objects NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView != _viewObjectsTable) return nil;
    if (row < 0 || row >= (NSInteger)_viewObjectsData.count) return nil;

    NSDictionary *objectInfo = _viewObjectsData[(NSUInteger)row];
    NSString *columnId = tableColumn.identifier;

    if ([columnId isEqualToString:kViewObjectColumnName]) {
        NSTableCellView *cell = [tableView makeViewWithIdentifier:kViewObjectColumnName owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
            cell.identifier = kViewObjectColumnName;

            NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
            imageView.translatesAutoresizingMaskIntoConstraints = NO;
            imageView.imageScaling = NSImageScaleProportionallyDown;
            [cell addSubview:imageView];
            cell.imageView = imageView;

            NSTextField *textField = [NSTextField textFieldWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.bordered = NO;
            textField.drawsBackground = NO;
            textField.editable = NO;
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            textField.font = [NSFont systemFontOfSize:12];
            [cell addSubview:textField];
            cell.textField = textField;

            [NSLayoutConstraint activateConstraints:@[
                [imageView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
                [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
                [imageView.widthAnchor constraintEqualToConstant:16],
                [imageView.heightAnchor constraintEqualToConstant:16],
                [textField.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor constant:4],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }

        NSString *name = objectInfo[@"name"] ?: @"";
        NSString *typeStr = objectInfo[@"type"] ?: @"Unknown";
        NSString *iconName = [self iconNameForViewObjectType:typeStr];

        cell.textField.stringValue = name;
        cell.textField.textColor = [NSColor labelColor];

        NSImage *icon = [NSImage imageWithSystemSymbolName:iconName accessibilityDescription:typeStr];
        if (icon) {
            NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightRegular];
            cell.imageView.image = [icon imageWithSymbolConfiguration:config];
            cell.imageView.contentTintColor = [NSColor systemTealColor];
        }

        return cell;
    }
    else if ([columnId isEqualToString:kViewObjectColumnType]) {
        NSTableCellView *cell = [tableView makeViewWithIdentifier:kViewObjectColumnType owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
            cell.identifier = kViewObjectColumnType;

            NSTextField *textField = [NSTextField textFieldWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.bordered = NO;
            textField.drawsBackground = NO;
            textField.editable = NO;
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            textField.font = [NSFont systemFontOfSize:11];
            textField.textColor = [NSColor secondaryLabelColor];
            [cell addSubview:textField];
            cell.textField = textField;

            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            ]];
        }

        cell.textField.stringValue = objectInfo[@"type"] ?: @"Unknown";
        return cell;
    }

    return nil;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    if (tableView == _viewObjectsTable) {
        return 22.0;
    }
    return 22.0;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object != _viewObjectsTable) return;

    NSInteger row = _viewObjectsTable.selectedRow;
    NSString *objectName = nil;
    if (row >= 0 && row < (NSInteger)_viewObjectsData.count) {
        objectName = _viewObjectsData[(NSUInteger)row][@"name"];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:XLViewObjectSelectionDidChangeNotification
                                                        object:self
                                                      userInfo:objectName ? @{@"objectName": objectName} : nil];
}

- (NSString *)iconNameForViewObjectType:(NSString *)typeStr {
    if ([typeStr isEqualToString:@"Image"]) return @"photo";
    if ([typeStr isEqualToString:@"Gridlines"]) return @"grid";
    if ([typeStr isEqualToString:@"Mesh"]) return @"cube.transparent";
    if ([typeStr isEqualToString:@"Terrain"]) return @"mountain.2";
    if ([typeStr isEqualToString:@"Ruler"]) return @"ruler";
    return @"questionmark.square";
}

#pragma mark - 3D Objects Footer Actions

- (void)viewObjectFooterClicked:(NSSegmentedControl *)sender {
    NSInteger segment = sender.selectedSegment;

    switch (segment) {
        case 0: // Add
            [self showAddViewObjectMenu];
            break;
        case 1: // Remove
            [self removeSelectedViewObject];
            break;
    }
}

- (void)showAddViewObjectMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Add Object"];

    NSArray *objectTypes = @[
        @[@"Image", @"photo"],
        @[@"Gridlines", @"grid"],
        @[@"Mesh", @"cube.transparent"],
        @[@"Terrain", @"mountain.2"],
        @[@"Ruler", @"ruler"],
    ];

    for (NSArray *typeInfo in objectTypes) {
        NSString *typeName = typeInfo[0];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:typeName
                                                      action:@selector(addViewObjectOfType:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = typeName;

        NSImage *icon = [NSImage imageWithSystemSymbolName:typeInfo[1] accessibilityDescription:typeName];
        if (icon) {
            item.image = icon;
        }

        [menu addItem:item];
    }

    [menu popUpMenuPositioningItem:nil atLocation:NSZeroPoint inView:_viewObjectsFooterButtons];
}

- (void)addViewObjectOfType:(NSMenuItem *)sender {
    NSString *typeName = sender.representedObject;
    if (!typeName) return;

    // Generate a unique default name
    NSString *baseName = typeName;
    NSString *name = baseName;
    NSInteger counter = 1;
    while ([self viewObjectExistsWithName:name]) {
        counter++;
        name = [NSString stringWithFormat:@"%@ %ld", baseName, (long)counter];
    }

    if (_engineBridge) {
        [_engineBridge addViewObject:typeName name:name properties:nil];
    }

    [self reloadViewObjects];
}

- (void)removeSelectedViewObject {
    NSInteger row = _viewObjectsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)_viewObjectsData.count) return;

    NSString *objectName = _viewObjectsData[(NSUInteger)row][@"name"];
    if (!objectName) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Delete \"%@\"?", objectName];
    alert.informativeText = @"This action cannot be undone.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.buttons.firstObject.hasDestructiveAction = YES;

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            if (self.engineBridge) {
                [self.engineBridge removeViewObject:objectName];
            }
            [self reloadViewObjects];
        }
    }];
}

- (BOOL)viewObjectExistsWithName:(NSString *)name {
    for (NSDictionary *obj in _viewObjectsData) {
        if ([obj[@"name"] isEqualToString:name]) return YES;
    }
    return NO;
}

@end
