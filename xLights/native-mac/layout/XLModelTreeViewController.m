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
#import "../XLEngineBridge.h"

static NSString * const kXLModelTreeDragType = @"com.xlights.modelTreeNode";

static NSString * const kColumnName = @"NameColumn";
static NSString * const kColumnType = @"TypeColumn";
static NSString * const kColumnChannels = @"ChannelsColumn";
static NSString * const kColumnController = @"ControllerColumn";

@interface XLModelTreeViewController ()

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong, readwrite) NSOutlineView *outlineView;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSSegmentedControl *footerButtons;

@property (nonatomic, strong) NSArray<XLModelTreeNode *> *allNodes;
@property (nonatomic, strong) NSArray<XLModelTreeNode *> *filteredNodes;
@property (nonatomic, copy) NSString *searchText;

@property (nonatomic, assign) BOOL suppressSelectionNotification;

@end

@implementation XLModelTreeViewController

#pragma mark - View Lifecycle

- (void)loadView {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 600)];
    container.wantsLayer = YES;

    [self setupSearchField:container];
    [self setupOutlineView:container];
    [self setupFooterButtons:container];
    [self setupConstraints:container];

    self.view = container;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadData];
}

#pragma mark - UI Setup

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

    // Type column
    NSTableColumn *typeColumn = [[NSTableColumn alloc] initWithIdentifier:kColumnType];
    typeColumn.title = @"Type";
    typeColumn.minWidth = 60;
    typeColumn.width = 80;
    typeColumn.resizingMask = NSTableColumnUserResizingMask;
    [_outlineView addTableColumn:typeColumn];

    // Channels column
    NSTableColumn *channelsColumn = [[NSTableColumn alloc] initWithIdentifier:kColumnChannels];
    channelsColumn.title = @"Ch";
    channelsColumn.minWidth = 40;
    channelsColumn.width = 50;
    channelsColumn.resizingMask = NSTableColumnUserResizingMask;
    [_outlineView addTableColumn:channelsColumn];

    // Controller column
    NSTableColumn *controllerColumn = [[NSTableColumn alloc] initWithIdentifier:kColumnController];
    controllerColumn.title = @"Controller";
    controllerColumn.minWidth = 60;
    controllerColumn.width = 90;
    controllerColumn.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    [_outlineView addTableColumn:controllerColumn];

    // Drag and drop
    [_outlineView registerForDraggedTypes:@[kXLModelTreeDragType]];
    _outlineView.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleSourceList;

    // Context menu
    _outlineView.menu = [self buildContextMenu];
    _outlineView.menu.delegate = (id<NSMenuDelegate>)self;

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

- (void)setupConstraints:(NSView *)container {
    [NSLayoutConstraint activateConstraints:@[
        // Search field
        [_searchField.topAnchor constraintEqualToAnchor:container.topAnchor constant:4],
        [_searchField.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4],
        [_searchField.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-4],
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

    NSArray<NSString *> *modelNames = [_engineBridge getModelNames];
    for (NSString *modelName in modelNames) {
        NSDictionary *info = [_engineBridge getModelInfo:modelName];
        if (!info) continue;

        XLModelTreeNode *node;
        BOOL isGroup = [info[@"IsGroup"] boolValue];

        if (isGroup) {
            node = [XLModelTreeNode groupNodeWithName:modelName];
            NSArray *memberNames = info[@"Models"];
            for (NSString *memberName in memberNames) {
                NSDictionary *memberInfo = [_engineBridge getModelInfo:memberName];
                XLModelTreeNode *childNode = [XLModelTreeNode nodeWithName:memberName
                                                                     type:memberInfo[@"DisplayAs"] ?: @"Unknown"];
                childNode.channelCount = [memberInfo[@"ChannelCount"] integerValue];
                childNode.controllerName = memberInfo[@"Controller"];
                [self loadSubmodelsForNode:childNode info:memberInfo];
                [node addChild:childNode];
            }
        } else {
            NSString *displayAs = info[@"DisplayAs"] ?: @"Unknown";
            node = [XLModelTreeNode nodeWithName:modelName type:displayAs];
            node.channelCount = [info[@"ChannelCount"] integerValue];
            node.controllerName = info[@"Controller"];
            [self loadSubmodelsForNode:node info:info];
        }

        [nodes addObject:node];
    }

    _allNodes = [nodes copy];
}

- (void)loadSubmodelsForNode:(XLModelTreeNode *)node info:(NSDictionary *)info {
    NSArray *submodels = info[@"Submodels"];
    for (NSString *submodelName in submodels) {
        XLModelTreeNode *subNode = [XLModelTreeNode submodelNodeWithName:submodelName
                                                             parentType:node.modelType];
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
            filteredNode.controllerName = node.controllerName;
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
    else if ([columnId isEqualToString:kColumnType]) {
        return [self textCellWithIdentifier:kColumnType
                                      text:node.isGroup ? @"Group" : (node.isSubmodel ? @"Submodel" : node.modelType)
                              inOutlineView:outlineView];
    }
    else if ([columnId isEqualToString:kColumnChannels]) {
        NSString *text = node.channelCount > 0 ? [NSString stringWithFormat:@"%ld", (long)node.channelCount] : @"";
        NSTableCellView *cell = [self textCellWithIdentifier:kColumnChannels text:text inOutlineView:outlineView];
        cell.textField.alignment = NSTextAlignmentRight;
        return cell;
    }
    else if ([columnId isEqualToString:kColumnController]) {
        return [self textCellWithIdentifier:kColumnController
                                      text:node.controllerName ?: @""
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
        cell.imageView.contentTintColor = node.isGroup ? [NSColor systemOrangeColor] : [NSColor secondaryLabelColor];
    }

    cell.textField.stringValue = node.name ?: @"";
    if (node.isGroup) {
        cell.textField.font = [NSFont boldSystemFontOfSize:12];
    } else {
        cell.textField.font = [NSFont systemFontOfSize:12];
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

    NSString *name = [self selectedModelName];
    if (name && [_delegate respondsToSelector:@selector(modelTree:didSelectModel:)]) {
        [_delegate modelTree:self didSelectModel:name];
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

    // Allow drops onto groups
    if (targetNode && targetNode.isGroup) {
        return NSDragOperationMove;
    }

    // Allow reordering at root level
    if (targetNode == nil && index != NSOutlineViewDropOnItemIndex) {
        return NSDragOperationMove;
    }

    // Allow dropping on root to move to root level
    if (targetNode == nil && index == NSOutlineViewDropOnItemIndex) {
        return NSDragOperationNone;
    }

    return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
          acceptDrop:(id<NSDraggingInfo>)info
                item:(id)item
          childIndex:(NSInteger)index {
    NSPasteboard *pb = info.draggingPasteboard;
    NSString *modelName = [pb stringForType:kXLModelTreeDragType];
    if (!modelName) return NO;

    XLModelTreeNode *targetNode = (XLModelTreeNode *)item;
    NSString *groupName = targetNode ? targetNode.name : nil;

    if ([_delegate respondsToSelector:@selector(modelTree:didMoveModel:toGroup:atIndex:)]) {
        [_delegate modelTree:self didMoveModel:modelName toGroup:groupName atIndex:index];
    }

    [self reloadData];
    return YES;
}

#pragma mark - Context Menu

- (NSMenu *)buildContextMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Model Actions"];

    // Add Model submenu
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

    NSMenuItem *duplicateItem = [[NSMenuItem alloc] initWithTitle:@"Duplicate Model"
                                                          action:@selector(contextDuplicate:)
                                                   keyEquivalent:@"d"];
    duplicateItem.target = self;
    duplicateItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [menu addItem:duplicateItem];

    NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete Model"
                                                       action:@selector(contextDelete:)
                                                keyEquivalent:@""];
    deleteItem.target = self;
    [menu addItem:deleteItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *groupSelectedItem = [[NSMenuItem alloc] initWithTitle:@"Group Selected Models"
                                                              action:@selector(contextGroupSelected:)
                                                       keyEquivalent:@""];
    groupSelectedItem.target = self;
    [menu addItem:groupSelectedItem];

    NSMenuItem *ungroupItem = [[NSMenuItem alloc] initWithTitle:@"Ungroup"
                                                        action:@selector(contextUngroup:)
                                                 keyEquivalent:@""];
    ungroupItem.target = self;
    [menu addItem:ungroupItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *renameItem = [[NSMenuItem alloc] initWithTitle:@"Rename"
                                                       action:@selector(contextRename:)
                                                keyEquivalent:@""];
    renameItem.target = self;
    [menu addItem:renameItem];

    return menu;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    NSInteger selectedRow = _outlineView.selectedRow;
    XLModelTreeNode *selectedNode = (selectedRow >= 0)
        ? [_outlineView itemAtRow:selectedRow] : nil;

    if (menuItem.action == @selector(contextDuplicate:) ||
        menuItem.action == @selector(contextDelete:) ||
        menuItem.action == @selector(contextRename:)) {
        return selectedNode != nil && !selectedNode.isSubmodel;
    }

    if (menuItem.action == @selector(contextGroupSelected:)) {
        return _outlineView.numberOfSelectedRows >= 2;
    }

    if (menuItem.action == @selector(contextUngroup:)) {
        return selectedNode != nil && selectedNode.isGroup;
    }

    return YES;
}

#pragma mark - Context Menu Actions

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

- (void)contextDuplicate:(id)sender {
    NSString *name = [self selectedModelName];
    if (name && [_delegate respondsToSelector:@selector(modelTree:didRequestDuplicateModel:)]) {
        [_delegate modelTree:self didRequestDuplicateModel:name];
    }
}

- (void)contextDelete:(id)sender {
    NSString *name = [self selectedModelName];
    if (!name) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Delete \"%@\"?", name];
    alert.informativeText = @"This action cannot be undone.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;
    alert.buttons.firstObject.hasDestructiveAction = YES;

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            if ([self.delegate respondsToSelector:@selector(modelTree:didRequestDeleteModel:)]) {
                [self.delegate modelTree:self didRequestDeleteModel:name];
            }
        }
    }];
}

- (void)contextGroupSelected:(id)sender {
    NSArray<NSString *> *names = [self selectedModelNames];
    if (names.count >= 2 && [_delegate respondsToSelector:@selector(modelTree:didRequestGroupModels:)]) {
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

@end
