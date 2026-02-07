/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLModelGroupWindow.h"
#import "../XLEngineBridge.h"

static const CGFloat kWindowWidth = 900.0;
static const CGFloat kWindowHeight = 600.0;

static const CGFloat kGroupListWidth = 220.0;

/// Layout type display names and their internal values.
/// Matches the legacy ModelGroupPanel layout types.
static NSArray<NSString *> *layoutTypeDisplayNames(void) {
    return @[@"Grid as Auto Sized", @"Minimal Grid as Auto Sized",
             @"Horizontal Stack", @"Vertical Stack"];
}

static NSArray<NSString *> *layoutTypeValues(void) {
    return @[@"grid", @"minimalGrid", @"horizontal", @"vertical"];
}

#pragma mark - Private Interface

@interface XLModelGroupWindow ()

/// Data
@property (nonatomic, copy) NSArray<NSDictionary *> *groups;
@property (nonatomic, copy) NSString *selectedGroupName;
@property (nonatomic, copy) NSArray<NSString *> *modelsInGroup;
@property (nonatomic, copy) NSArray<NSString *> *availableModels;
@property (nonatomic, copy) NSArray<NSString *> *filteredAvailableModels;
@property (nonatomic, assign, readwrite) BOOL hasChanges;

/// Group list (left pane)
@property (nonatomic, strong) NSTableView *groupTableView;
@property (nonatomic, strong) NSScrollView *groupScrollView;
@property (nonatomic, strong) NSSegmentedControl *groupButtons;

/// Models in group (right top)
@property (nonatomic, strong) NSTableView *membersTableView;
@property (nonatomic, strong) NSScrollView *membersScrollView;
@property (nonatomic, strong) NSTextField *membersLabel;

/// Available models (right bottom)
@property (nonatomic, strong) NSTableView *availableTableView;
@property (nonatomic, strong) NSScrollView *availableScrollView;
@property (nonatomic, strong) NSTextField *availableLabel;
@property (nonatomic, strong) NSSearchField *filterField;

/// Transfer buttons (between the two model lists)
@property (nonatomic, strong) NSButton *addButton;
@property (nonatomic, strong) NSButton *removeButton;
@property (nonatomic, strong) NSButton *moveUpButton;
@property (nonatomic, strong) NSButton *moveDownButton;

/// Group settings (below the group list)
@property (nonatomic, strong) NSPopUpButton *layoutTypePopup;
@property (nonatomic, strong) NSTextField *gridSizeField;

/// Checkboxes for available model filters
@property (nonatomic, strong) NSButton *showSubmodelsCheck;
@property (nonatomic, strong) NSButton *showGroupsCheck;

/// Completion handler
@property (nonatomic, copy) XLModelGroupWindowCompletion completion;

@end

@implementation XLModelGroupWindow

#pragma mark - Initialization

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, kWindowWidth, kWindowHeight);
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable |
                             NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];

    window.title = @"Model Group Management";
    window.minSize = NSMakeSize(700, 450);
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        _hasChanges = NO;
        _groups = @[];
        _modelsInGroup = @[];
        _availableModels = @[];
        _filteredAvailableModels = @[];
        [self buildUI];
    }
    return self;
}

- (void)showWithCompletion:(XLModelGroupWindowCompletion)completion {
    _completion = completion;

    [self reloadGroups];

    [self.window makeKeyAndOrderFront:nil];

    // Observe window close
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowWillClose:)
                                                 name:NSWindowWillCloseNotification
                                               object:self.window];
}

- (void)windowWillClose:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSWindowWillCloseNotification
                                                  object:self.window];
    if (_completion) {
        _completion(_hasChanges);
        _completion = nil;
    }
}

#pragma mark - UI Construction

- (void)buildUI {
    NSView *content = self.window.contentView;
    content.wantsLayer = YES;

    // === Left pane: Group list ===
    [self buildGroupListPane:content];

    // === Right pane: Model membership ===
    [self buildModelMembershipPane:content];

    // === Bottom bar: Close button ===
    NSButton *closeButton = [NSButton buttonWithTitle:@"Close"
                                               target:self
                                               action:@selector(closeAction:)];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    closeButton.keyEquivalent = @"\r";
    [content addSubview:closeButton];

    // === Layout ===
    NSView *leftPane = _groupScrollView.superview ?: _groupScrollView;

    [NSLayoutConstraint activateConstraints:@[
        // Close button
        [closeButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [closeButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],
    ]];
}

- (void)buildGroupListPane:(NSView *)content {
    // Container for the left pane
    NSView *leftContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    leftContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:leftContainer];

    // Group list label
    NSTextField *groupLabel = [NSTextField labelWithString:@"Model Groups"];
    groupLabel.translatesAutoresizingMaskIntoConstraints = NO;
    groupLabel.font = [NSFont boldSystemFontOfSize:12];
    [leftContainer addSubview:groupLabel];

    // Group table view
    _groupTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _groupTableView.dataSource = self;
    _groupTableView.delegate = self;
    _groupTableView.rowSizeStyle = NSTableViewRowSizeStyleSmall;
    _groupTableView.usesAlternatingRowBackgroundColors = YES;
    _groupTableView.allowsEmptySelection = YES;
    _groupTableView.headerView = nil;

    NSTableColumn *groupColumn = [[NSTableColumn alloc] initWithIdentifier:@"GroupName"];
    groupColumn.title = @"Group";
    groupColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_groupTableView addTableColumn:groupColumn];

    _groupScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _groupScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _groupScrollView.documentView = _groupTableView;
    _groupScrollView.hasVerticalScroller = YES;
    _groupScrollView.hasHorizontalScroller = NO;
    _groupScrollView.autohidesScrollers = YES;
    _groupScrollView.borderType = NSBezelBorder;
    [leftContainer addSubview:_groupScrollView];

    // Group CRUD buttons
    _groupButtons = [NSSegmentedControl segmentedControlWithImages:@[
        [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"Add Group"],
        [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Delete Group"],
        [NSImage imageWithSystemSymbolName:@"pencil" accessibilityDescription:@"Rename Group"],
    ] trackingMode:NSSegmentSwitchTrackingMomentary
        target:self
        action:@selector(groupButtonClicked:)];
    _groupButtons.translatesAutoresizingMaskIntoConstraints = NO;
    _groupButtons.segmentStyle = NSSegmentStyleSmallSquare;
    [_groupButtons setWidth:32 forSegment:0];
    [_groupButtons setWidth:32 forSegment:1];
    [_groupButtons setWidth:32 forSegment:2];
    [leftContainer addSubview:_groupButtons];

    // Layout type
    NSTextField *layoutLabel = [NSTextField labelWithString:@"Layout:"];
    layoutLabel.translatesAutoresizingMaskIntoConstraints = NO;
    layoutLabel.font = [NSFont systemFontOfSize:11];
    [leftContainer addSubview:layoutLabel];

    _layoutTypePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _layoutTypePopup.translatesAutoresizingMaskIntoConstraints = NO;
    _layoutTypePopup.controlSize = NSControlSizeSmall;
    _layoutTypePopup.font = [NSFont systemFontOfSize:11];
    [_layoutTypePopup addItemsWithTitles:layoutTypeDisplayNames()];
    _layoutTypePopup.target = self;
    _layoutTypePopup.action = @selector(layoutTypeChanged:);
    [leftContainer addSubview:_layoutTypePopup];

    // Grid size
    NSTextField *gridLabel = [NSTextField labelWithString:@"Grid Size:"];
    gridLabel.translatesAutoresizingMaskIntoConstraints = NO;
    gridLabel.font = [NSFont systemFontOfSize:11];
    [leftContainer addSubview:gridLabel];

    _gridSizeField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _gridSizeField.translatesAutoresizingMaskIntoConstraints = NO;
    _gridSizeField.controlSize = NSControlSizeSmall;
    _gridSizeField.font = [NSFont systemFontOfSize:11];
    _gridSizeField.stringValue = @"400";
    _gridSizeField.target = self;
    _gridSizeField.action = @selector(gridSizeChanged:);

    NSNumberFormatter *numFmt = [[NSNumberFormatter alloc] init];
    numFmt.numberStyle = NSNumberFormatterDecimalStyle;
    numFmt.minimum = @(1);
    numFmt.maximum = @(5000);
    numFmt.allowsFloats = NO;
    _gridSizeField.formatter = numFmt;
    [leftContainer addSubview:_gridSizeField];

    // Left pane constraints
    [NSLayoutConstraint activateConstraints:@[
        [leftContainer.topAnchor constraintEqualToAnchor:content.topAnchor],
        [leftContainer.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [leftContainer.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [leftContainer.widthAnchor constraintEqualToConstant:kGroupListWidth],

        [groupLabel.topAnchor constraintEqualToAnchor:leftContainer.topAnchor constant:12],
        [groupLabel.leadingAnchor constraintEqualToAnchor:leftContainer.leadingAnchor constant:12],

        [_groupScrollView.topAnchor constraintEqualToAnchor:groupLabel.bottomAnchor constant:6],
        [_groupScrollView.leadingAnchor constraintEqualToAnchor:leftContainer.leadingAnchor constant:8],
        [_groupScrollView.trailingAnchor constraintEqualToAnchor:leftContainer.trailingAnchor constant:-8],

        [_groupButtons.topAnchor constraintEqualToAnchor:_groupScrollView.bottomAnchor constant:4],
        [_groupButtons.leadingAnchor constraintEqualToAnchor:leftContainer.leadingAnchor constant:8],
        [_groupButtons.heightAnchor constraintEqualToConstant:24],

        [layoutLabel.topAnchor constraintEqualToAnchor:_groupButtons.bottomAnchor constant:12],
        [layoutLabel.leadingAnchor constraintEqualToAnchor:leftContainer.leadingAnchor constant:12],

        [_layoutTypePopup.topAnchor constraintEqualToAnchor:layoutLabel.bottomAnchor constant:2],
        [_layoutTypePopup.leadingAnchor constraintEqualToAnchor:leftContainer.leadingAnchor constant:8],
        [_layoutTypePopup.trailingAnchor constraintEqualToAnchor:leftContainer.trailingAnchor constant:-8],

        [gridLabel.topAnchor constraintEqualToAnchor:_layoutTypePopup.bottomAnchor constant:8],
        [gridLabel.leadingAnchor constraintEqualToAnchor:leftContainer.leadingAnchor constant:12],

        [_gridSizeField.topAnchor constraintEqualToAnchor:gridLabel.bottomAnchor constant:2],
        [_gridSizeField.leadingAnchor constraintEqualToAnchor:leftContainer.leadingAnchor constant:8],
        [_gridSizeField.widthAnchor constraintEqualToConstant:80],

        [_gridSizeField.bottomAnchor constraintLessThanOrEqualToAnchor:leftContainer.bottomAnchor constant:-50],

        // The scroll view takes most of the remaining space
        [_groupScrollView.bottomAnchor constraintEqualToAnchor:_groupButtons.topAnchor constant:-4],
    ]];
}

- (void)buildModelMembershipPane:(NSView *)content {
    // Right container
    NSView *rightContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    rightContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:rightContainer];

    // === Top section: Models in group ===
    _membersLabel = [NSTextField labelWithString:@"Models in Group:"];
    _membersLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _membersLabel.font = [NSFont boldSystemFontOfSize:12];
    [rightContainer addSubview:_membersLabel];

    _membersTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _membersTableView.dataSource = self;
    _membersTableView.delegate = self;
    _membersTableView.rowSizeStyle = NSTableViewRowSizeStyleSmall;
    _membersTableView.usesAlternatingRowBackgroundColors = YES;
    _membersTableView.allowsMultipleSelection = YES;
    _membersTableView.allowsEmptySelection = YES;
    _membersTableView.headerView = nil;
    _membersTableView.doubleAction = @selector(removeSelectedModels:);
    _membersTableView.target = self;

    NSTableColumn *memberCol = [[NSTableColumn alloc] initWithIdentifier:@"MemberName"];
    memberCol.title = @"Model";
    memberCol.resizingMask = NSTableColumnAutoresizingMask;
    [_membersTableView addTableColumn:memberCol];

    _membersScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _membersScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _membersScrollView.documentView = _membersTableView;
    _membersScrollView.hasVerticalScroller = YES;
    _membersScrollView.autohidesScrollers = YES;
    _membersScrollView.borderType = NSBezelBorder;
    [rightContainer addSubview:_membersScrollView];

    // Transfer buttons (vertical stack between the two lists)
    NSView *buttonColumn = [[NSView alloc] initWithFrame:NSZeroRect];
    buttonColumn.translatesAutoresizingMaskIntoConstraints = NO;
    [rightContainer addSubview:buttonColumn];

    _removeButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.down"
                                               accessibilityDescription:@"Remove from group"]
                                       target:self
                                       action:@selector(removeSelectedModels:)];
    _removeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _removeButton.bezelStyle = NSBezelStyleSmallSquare;
    _removeButton.toolTip = @"Remove selected models from group";
    [buttonColumn addSubview:_removeButton];

    _addButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.up"
                                            accessibilityDescription:@"Add to group"]
                                    target:self
                                    action:@selector(addSelectedModels:)];
    _addButton.translatesAutoresizingMaskIntoConstraints = NO;
    _addButton.bezelStyle = NSBezelStyleSmallSquare;
    _addButton.toolTip = @"Add selected models to group";
    [buttonColumn addSubview:_addButton];

    _moveUpButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.up"
                                               accessibilityDescription:@"Move up"]
                                       target:self
                                       action:@selector(moveModelUp:)];
    _moveUpButton.translatesAutoresizingMaskIntoConstraints = NO;
    _moveUpButton.bezelStyle = NSBezelStyleSmallSquare;
    _moveUpButton.toolTip = @"Move selected model up in group order";
    [buttonColumn addSubview:_moveUpButton];

    _moveDownButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.down"
                                                 accessibilityDescription:@"Move down"]
                                         target:self
                                         action:@selector(moveModelDown:)];
    _moveDownButton.translatesAutoresizingMaskIntoConstraints = NO;
    _moveDownButton.bezelStyle = NSBezelStyleSmallSquare;
    _moveDownButton.toolTip = @"Move selected model down in group order";
    [buttonColumn addSubview:_moveDownButton];

    [NSLayoutConstraint activateConstraints:@[
        [_removeButton.topAnchor constraintEqualToAnchor:buttonColumn.topAnchor],
        [_removeButton.centerXAnchor constraintEqualToAnchor:buttonColumn.centerXAnchor],
        [_removeButton.widthAnchor constraintEqualToConstant:28],
        [_removeButton.heightAnchor constraintEqualToConstant:28],

        [_addButton.topAnchor constraintEqualToAnchor:_removeButton.bottomAnchor constant:4],
        [_addButton.centerXAnchor constraintEqualToAnchor:buttonColumn.centerXAnchor],
        [_addButton.widthAnchor constraintEqualToConstant:28],
        [_addButton.heightAnchor constraintEqualToConstant:28],

        [_moveUpButton.topAnchor constraintEqualToAnchor:_addButton.bottomAnchor constant:12],
        [_moveUpButton.centerXAnchor constraintEqualToAnchor:buttonColumn.centerXAnchor],
        [_moveUpButton.widthAnchor constraintEqualToConstant:28],
        [_moveUpButton.heightAnchor constraintEqualToConstant:28],

        [_moveDownButton.topAnchor constraintEqualToAnchor:_moveUpButton.bottomAnchor constant:4],
        [_moveDownButton.centerXAnchor constraintEqualToAnchor:buttonColumn.centerXAnchor],
        [_moveDownButton.widthAnchor constraintEqualToConstant:28],
        [_moveDownButton.heightAnchor constraintEqualToConstant:28],
    ]];

    // === Bottom section: Available models ===
    _availableLabel = [NSTextField labelWithString:@"Available Models:"];
    _availableLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _availableLabel.font = [NSFont boldSystemFontOfSize:12];
    [rightContainer addSubview:_availableLabel];

    // Filter checkboxes
    _showSubmodelsCheck = [NSButton checkboxWithTitle:@"Submodels"
                                              target:self
                                              action:@selector(filterChanged:)];
    _showSubmodelsCheck.translatesAutoresizingMaskIntoConstraints = NO;
    _showSubmodelsCheck.controlSize = NSControlSizeSmall;
    _showSubmodelsCheck.font = [NSFont systemFontOfSize:10];
    _showSubmodelsCheck.state = NSControlStateValueOff;
    [rightContainer addSubview:_showSubmodelsCheck];

    _showGroupsCheck = [NSButton checkboxWithTitle:@"Groups"
                                            target:self
                                            action:@selector(filterChanged:)];
    _showGroupsCheck.translatesAutoresizingMaskIntoConstraints = NO;
    _showGroupsCheck.controlSize = NSControlSizeSmall;
    _showGroupsCheck.font = [NSFont systemFontOfSize:10];
    _showGroupsCheck.state = NSControlStateValueOff;
    [rightContainer addSubview:_showGroupsCheck];

    // Filter search field
    _filterField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _filterField.translatesAutoresizingMaskIntoConstraints = NO;
    _filterField.placeholderString = @"Filter models...";
    _filterField.controlSize = NSControlSizeSmall;
    _filterField.delegate = self;
    _filterField.sendsSearchStringImmediately = YES;
    _filterField.target = self;
    _filterField.action = @selector(filterTextChanged:);
    [rightContainer addSubview:_filterField];

    _availableTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _availableTableView.dataSource = self;
    _availableTableView.delegate = self;
    _availableTableView.rowSizeStyle = NSTableViewRowSizeStyleSmall;
    _availableTableView.usesAlternatingRowBackgroundColors = YES;
    _availableTableView.allowsMultipleSelection = YES;
    _availableTableView.allowsEmptySelection = YES;
    _availableTableView.headerView = nil;
    _availableTableView.doubleAction = @selector(addSelectedModels:);
    _availableTableView.target = self;

    NSTableColumn *availCol = [[NSTableColumn alloc] initWithIdentifier:@"AvailableName"];
    availCol.title = @"Model";
    availCol.resizingMask = NSTableColumnAutoresizingMask;
    [_availableTableView addTableColumn:availCol];

    _availableScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _availableScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _availableScrollView.documentView = _availableTableView;
    _availableScrollView.hasVerticalScroller = YES;
    _availableScrollView.autohidesScrollers = YES;
    _availableScrollView.borderType = NSBezelBorder;
    [rightContainer addSubview:_availableScrollView];

    // Right pane constraints
    [NSLayoutConstraint activateConstraints:@[
        [rightContainer.topAnchor constraintEqualToAnchor:content.topAnchor],
        [rightContainer.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:kGroupListWidth],
        [rightContainer.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [rightContainer.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],

        // Models in group label
        [_membersLabel.topAnchor constraintEqualToAnchor:rightContainer.topAnchor constant:12],
        [_membersLabel.leadingAnchor constraintEqualToAnchor:rightContainer.leadingAnchor constant:12],

        // Models in group table (top half)
        [_membersScrollView.topAnchor constraintEqualToAnchor:_membersLabel.bottomAnchor constant:6],
        [_membersScrollView.leadingAnchor constraintEqualToAnchor:rightContainer.leadingAnchor constant:8],
        [_membersScrollView.trailingAnchor constraintEqualToAnchor:buttonColumn.leadingAnchor constant:-4],

        // Button column
        [buttonColumn.trailingAnchor constraintEqualToAnchor:rightContainer.trailingAnchor constant:-8],
        [buttonColumn.widthAnchor constraintEqualToConstant:36],
        [buttonColumn.centerYAnchor constraintEqualToAnchor:_membersScrollView.centerYAnchor],

        // Members scroll view takes top ~45% of height
        [_membersScrollView.heightAnchor constraintEqualToAnchor:rightContainer.heightAnchor
                                                       multiplier:0.42 constant:-40],

        // Available models label row
        [_availableLabel.topAnchor constraintEqualToAnchor:_membersScrollView.bottomAnchor constant:10],
        [_availableLabel.leadingAnchor constraintEqualToAnchor:rightContainer.leadingAnchor constant:12],

        [_showSubmodelsCheck.centerYAnchor constraintEqualToAnchor:_availableLabel.centerYAnchor],
        [_showSubmodelsCheck.leadingAnchor constraintEqualToAnchor:_availableLabel.trailingAnchor constant:12],

        [_showGroupsCheck.centerYAnchor constraintEqualToAnchor:_availableLabel.centerYAnchor],
        [_showGroupsCheck.leadingAnchor constraintEqualToAnchor:_showSubmodelsCheck.trailingAnchor constant:8],

        // Filter field
        [_filterField.topAnchor constraintEqualToAnchor:_availableLabel.bottomAnchor constant:4],
        [_filterField.leadingAnchor constraintEqualToAnchor:rightContainer.leadingAnchor constant:8],
        [_filterField.trailingAnchor constraintEqualToAnchor:rightContainer.trailingAnchor constant:-8],

        // Available models table (bottom half)
        [_availableScrollView.topAnchor constraintEqualToAnchor:_filterField.bottomAnchor constant:4],
        [_availableScrollView.leadingAnchor constraintEqualToAnchor:rightContainer.leadingAnchor constant:8],
        [_availableScrollView.trailingAnchor constraintEqualToAnchor:rightContainer.trailingAnchor constant:-8],
        [_availableScrollView.bottomAnchor constraintEqualToAnchor:rightContainer.bottomAnchor constant:-50],
    ]];
}

#pragma mark - Data Loading

- (void)reloadGroups {
    if (!_engineBridge) return;

    _groups = [_engineBridge getModelGroups];
    [_groupTableView reloadData];

    // Restore selection or select first group
    if (_selectedGroupName) {
        NSInteger idx = [self indexOfGroupNamed:_selectedGroupName];
        if (idx >= 0) {
            [_groupTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)idx]
                         byExtendingSelection:NO];
        } else if (_groups.count > 0) {
            _selectedGroupName = _groups.firstObject[@"name"];
            [_groupTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                         byExtendingSelection:NO];
        } else {
            _selectedGroupName = nil;
        }
    } else if (_groups.count > 0) {
        _selectedGroupName = _groups.firstObject[@"name"];
        [_groupTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                     byExtendingSelection:NO];
    }

    [self reloadGroupDetails];
}

- (void)reloadGroupDetails {
    if (!_selectedGroupName || !_engineBridge) {
        _modelsInGroup = @[];
        _availableModels = @[];
        _filteredAvailableModels = @[];
        _membersLabel.stringValue = @"Models in Group:";
        [_membersTableView reloadData];
        [_availableTableView reloadData];
        [self updateButtonStates];
        [self updateLayoutControls];
        return;
    }

    _membersLabel.stringValue = [NSString stringWithFormat:@"Models in \"%@\":", _selectedGroupName];

    // Get members of the selected group
    NSDictionary *groupInfo = [_engineBridge getModelGroup:_selectedGroupName];
    _modelsInGroup = groupInfo[@"modelNames"] ?: @[];

    // Build the set of models already in the group (for exclusion)
    NSMutableSet<NSString *> *inGroupSet = [NSMutableSet setWithArray:_modelsInGroup];
    [inGroupSet addObject:_selectedGroupName]; // exclude the group itself

    // Build available models list
    NSMutableArray<NSString *> *available = [[NSMutableArray alloc] init];

    // Get all models
    NSArray<NSString *> *allModels = [_engineBridge getModelNamesExcludingGroups];
    for (NSString *modelName in allModels) {
        if ([inGroupSet containsObject:modelName]) continue;
        [available addObject:modelName];
    }

    // Optionally add submodels
    if (_showSubmodelsCheck.state == NSControlStateValueOn) {
        for (NSString *modelName in allModels) {
            NSArray<NSDictionary *> *submodels = [_engineBridge getSubmodels:modelName];
            for (NSDictionary *sub in submodels) {
                NSString *fullName = [NSString stringWithFormat:@"%@/%@", modelName, sub[@"name"]];
                if (![inGroupSet containsObject:fullName]) {
                    [available addObject:fullName];
                }
            }
        }
    }

    // Optionally add other groups
    if (_showGroupsCheck.state == NSControlStateValueOn) {
        NSArray<NSString *> *groupNames = [_engineBridge getGroupNames];
        for (NSString *groupName in groupNames) {
            if ([inGroupSet containsObject:groupName]) continue;
            // Prevent circular references by not adding groups that contain this group
            [available addObject:groupName];
        }
    }

    [available sortUsingSelector:@selector(caseInsensitiveCompare:)];
    _availableModels = [available copy];

    [self applyAvailableFilter];

    [_membersTableView reloadData];
    [_availableTableView reloadData];
    [self updateButtonStates];
    [self updateLayoutControls];
}

- (void)applyAvailableFilter {
    NSString *filterText = [_filterField.stringValue stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (filterText.length == 0) {
        _filteredAvailableModels = _availableModels;
    } else {
        NSString *lowerFilter = [filterText lowercaseString];
        NSMutableArray<NSString *> *filtered = [[NSMutableArray alloc] init];
        for (NSString *name in _availableModels) {
            if ([[name lowercaseString] containsString:lowerFilter]) {
                [filtered addObject:name];
            }
        }
        _filteredAvailableModels = [filtered copy];
    }
}

- (void)updateLayoutControls {
    BOOL hasSelection = (_selectedGroupName != nil);
    _layoutTypePopup.enabled = hasSelection;
    _gridSizeField.enabled = hasSelection;

    if (!hasSelection) {
        [_layoutTypePopup selectItemAtIndex:1]; // Default: Minimal Grid
        _gridSizeField.stringValue = @"400";
        return;
    }

    // Read current group properties via the model properties API
    NSString *layoutValue = [_engineBridge getModelProperty:_selectedGroupName key:@"layout" defaultValue:@"minimalGrid"];
    NSArray<NSString *> *values = layoutTypeValues();
    NSUInteger idx = [values indexOfObject:layoutValue];
    if (idx != NSNotFound) {
        [_layoutTypePopup selectItemAtIndex:(NSInteger)idx];
    } else {
        [_layoutTypePopup selectItemAtIndex:1];
    }

    NSString *gridSize = [_engineBridge getModelProperty:_selectedGroupName key:@"GridSize" defaultValue:@"400"];
    _gridSizeField.stringValue = gridSize;
}

- (NSInteger)indexOfGroupNamed:(NSString *)name {
    for (NSUInteger i = 0; i < _groups.count; i++) {
        if ([_groups[i][@"name"] isEqualToString:name]) {
            return (NSInteger)i;
        }
    }
    return -1;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == _groupTableView) {
        return (NSInteger)_groups.count;
    }
    if (tableView == _membersTableView) {
        return (NSInteger)_modelsInGroup.count;
    }
    if (tableView == _availableTableView) {
        return (NSInteger)_filteredAvailableModels.count;
    }
    return 0;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *identifier = tableColumn.identifier;

    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = identifier;

        NSTextField *tf = [NSTextField textFieldWithString:@""];
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        tf.bordered = NO;
        tf.drawsBackground = NO;
        tf.editable = NO;
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        tf.font = [NSFont systemFontOfSize:12];
        [cell addSubview:tf];
        cell.textField = tf;

        [NSLayoutConstraint activateConstraints:@[
            [tf.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
            [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    if (tableView == _groupTableView) {
        NSString *name = _groups[row][@"name"];
        cell.textField.stringValue = name ?: @"";
        cell.textField.font = [NSFont boldSystemFontOfSize:12];
        cell.textField.textColor = [NSColor labelColor];
    }
    else if (tableView == _membersTableView) {
        NSString *name = _modelsInGroup[row];
        cell.textField.stringValue = name ?: @"";
        cell.textField.font = [NSFont systemFontOfSize:12];

        // Color groups blue, submodels orange, regular models default
        if ([name containsString:@"/"]) {
            cell.textField.textColor = [NSColor systemOrangeColor];
        } else {
            // Check if this is a group
            BOOL isGroup = NO;
            NSArray<NSString *> *groupNames = [_engineBridge getGroupNames];
            for (NSString *gn in groupNames) {
                if ([gn isEqualToString:name]) {
                    isGroup = YES;
                    break;
                }
            }
            cell.textField.textColor = isGroup ? [NSColor systemBlueColor] : [NSColor labelColor];
        }
    }
    else if (tableView == _availableTableView) {
        NSString *name = _filteredAvailableModels[row];
        cell.textField.stringValue = name ?: @"";
        cell.textField.font = [NSFont systemFontOfSize:12];

        if ([name containsString:@"/"]) {
            cell.textField.textColor = [NSColor systemOrangeColor];
        } else {
            BOOL isGroup = NO;
            NSArray<NSString *> *groupNames = [_engineBridge getGroupNames];
            for (NSString *gn in groupNames) {
                if ([gn isEqualToString:name]) {
                    isGroup = YES;
                    break;
                }
            }
            cell.textField.textColor = isGroup ? [NSColor systemBlueColor] : [NSColor labelColor];
        }
    }

    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *tv = notification.object;

    if (tv == _groupTableView) {
        NSInteger row = _groupTableView.selectedRow;
        if (row >= 0 && row < (NSInteger)_groups.count) {
            _selectedGroupName = _groups[row][@"name"];
        } else {
            _selectedGroupName = nil;
        }
        [self reloadGroupDetails];
    }

    [self updateButtonStates];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return 22.0;
}

#pragma mark - Button State Management

- (void)updateButtonStates {
    BOOL hasGroup = (_selectedGroupName != nil);
    BOOL hasMemberSelection = (_membersTableView.selectedRow >= 0);
    BOOL hasAvailableSelection = (_availableTableView.selectedRow >= 0);

    _addButton.enabled = hasGroup && hasAvailableSelection;
    _removeButton.enabled = hasGroup && hasMemberSelection;
    _moveUpButton.enabled = hasGroup && hasMemberSelection && _membersTableView.selectedRow > 0;
    _moveDownButton.enabled = hasGroup && hasMemberSelection &&
        _membersTableView.selectedRow < (NSInteger)_modelsInGroup.count - 1;

    // Group buttons: delete and rename need selection
    [_groupButtons setEnabled:YES forSegment:0];  // Add always enabled
    [_groupButtons setEnabled:hasGroup forSegment:1];  // Delete needs selection
    [_groupButtons setEnabled:hasGroup forSegment:2];  // Rename needs selection
}

#pragma mark - Group CRUD Actions

- (void)groupButtonClicked:(NSSegmentedControl *)sender {
    switch (sender.selectedSegment) {
        case 0: [self createGroup]; break;
        case 1: [self deleteGroup]; break;
        case 2: [self renameGroup]; break;
    }
}

- (void)createGroup {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Create New Model Group";
    alert.informativeText = @"Enter a name for the new model group:";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
    input.placeholderString = @"Group name";
    alert.accessoryView = input;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) return;

        NSString *name = [input.stringValue stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length == 0) return;

        BOOL success = [self->_engineBridge createModelGroup:name withModels:nil];
        if (success) {
            self.hasChanges = YES;
            self.selectedGroupName = name;
            [self reloadGroups];
        } else {
            NSAlert *errorAlert = [[NSAlert alloc] init];
            errorAlert.messageText = @"Cannot Create Group";
            errorAlert.informativeText = [NSString stringWithFormat:
                @"A group named '%@' already exists or the name is invalid.", name];
            [errorAlert beginSheetModalForWindow:self.window completionHandler:nil];
        }
    }];
}

- (void)deleteGroup {
    if (!_selectedGroupName) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Delete group \"%@\"?", _selectedGroupName];
    alert.informativeText = @"Models in the group will not be deleted.";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.buttons.firstObject.hasDestructiveAction = YES;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) return;

        BOOL success = [self->_engineBridge deleteModelGroup:self->_selectedGroupName];
        if (success) {
            self.hasChanges = YES;
            self.selectedGroupName = nil;
            [self reloadGroups];
        }
    }];
}

- (void)renameGroup {
    if (!_selectedGroupName) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename Model Group";
    alert.informativeText = @"Enter the new name:";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"Rename"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
    input.stringValue = _selectedGroupName;
    alert.accessoryView = input;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) return;

        NSString *newName = [input.stringValue stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (newName.length == 0 || [newName isEqualToString:self->_selectedGroupName]) return;

        BOOL success = [self->_engineBridge renameModelGroup:self->_selectedGroupName toName:newName];
        if (success) {
            self.hasChanges = YES;
            self.selectedGroupName = newName;
            [self reloadGroups];
        } else {
            NSAlert *errorAlert = [[NSAlert alloc] init];
            errorAlert.messageText = @"Cannot Rename Group";
            errorAlert.informativeText = [NSString stringWithFormat:
                @"A group named '%@' already exists or the name is invalid.", newName];
            [errorAlert beginSheetModalForWindow:self.window completionHandler:nil];
        }
    }];
}

#pragma mark - Model Add/Remove Actions

- (void)addSelectedModels:(id)sender {
    if (!_selectedGroupName) return;

    NSIndexSet *selectedRows = _availableTableView.selectedRowIndexes;
    if (selectedRows.count == 0) return;

    __block BOOL anyAdded = NO;
    [selectedRows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if (idx < self->_filteredAvailableModels.count) {
            NSString *modelName = self->_filteredAvailableModels[idx];
            BOOL success = [self->_engineBridge addModel:modelName toGroup:self->_selectedGroupName];
            if (success) anyAdded = YES;
        }
    }];

    if (anyAdded) {
        _hasChanges = YES;
        [self reloadGroupDetails];
        [self reloadGroups];
    }
}

- (void)removeSelectedModels:(id)sender {
    if (!_selectedGroupName) return;

    NSIndexSet *selectedRows = _membersTableView.selectedRowIndexes;
    if (selectedRows.count == 0) return;

    // Collect names before modifying (indices will shift)
    NSMutableArray<NSString *> *namesToRemove = [[NSMutableArray alloc] init];
    [selectedRows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if (idx < self->_modelsInGroup.count) {
            [namesToRemove addObject:self->_modelsInGroup[idx]];
        }
    }];

    BOOL anyRemoved = NO;
    for (NSString *name in namesToRemove) {
        BOOL success = [_engineBridge removeModel:name fromGroup:_selectedGroupName];
        if (success) anyRemoved = YES;
    }

    if (anyRemoved) {
        _hasChanges = YES;
        [self reloadGroupDetails];
        [self reloadGroups];
    }
}

- (void)moveModelUp:(id)sender {
    if (!_selectedGroupName) return;

    NSInteger row = _membersTableView.selectedRow;
    if (row <= 0 || row >= (NSInteger)_modelsInGroup.count) return;

    // Reorder by removing and re-adding at the right position
    // The bridge API doesn't have a reorder method, so we rebuild the list
    NSMutableArray<NSString *> *newOrder = [_modelsInGroup mutableCopy];
    NSString *model = newOrder[row];
    [newOrder removeObjectAtIndex:(NSUInteger)row];
    [newOrder insertObject:model atIndex:(NSUInteger)(row - 1)];

    [self rebuildGroupWithModels:newOrder];

    // Re-select the moved item
    [_membersTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)(row - 1)]
                   byExtendingSelection:NO];
}

- (void)moveModelDown:(id)sender {
    if (!_selectedGroupName) return;

    NSInteger row = _membersTableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_modelsInGroup.count - 1) return;

    NSMutableArray<NSString *> *newOrder = [_modelsInGroup mutableCopy];
    NSString *model = newOrder[row];
    [newOrder removeObjectAtIndex:(NSUInteger)row];
    [newOrder insertObject:model atIndex:(NSUInteger)(row + 1)];

    [self rebuildGroupWithModels:newOrder];

    // Re-select the moved item
    [_membersTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)(row + 1)]
                   byExtendingSelection:NO];
}

- (void)rebuildGroupWithModels:(NSArray<NSString *> *)modelNames {
    // Remove all models and re-add in new order
    for (NSString *name in _modelsInGroup) {
        [_engineBridge removeModel:name fromGroup:_selectedGroupName];
    }
    for (NSString *name in modelNames) {
        [_engineBridge addModel:name toGroup:_selectedGroupName];
    }

    _hasChanges = YES;
    [self reloadGroupDetails];
    [self reloadGroups];
}

#pragma mark - Group Settings Actions

- (void)layoutTypeChanged:(id)sender {
    if (!_selectedGroupName) return;

    NSInteger idx = _layoutTypePopup.indexOfSelectedItem;
    NSArray<NSString *> *values = layoutTypeValues();
    if (idx >= 0 && idx < (NSInteger)values.count) {
        [_engineBridge updateModelProperty:_selectedGroupName key:@"layout" value:values[idx]];
        _hasChanges = YES;
    }
}

- (void)gridSizeChanged:(id)sender {
    if (!_selectedGroupName) return;

    NSString *value = _gridSizeField.stringValue;
    if (value.length > 0) {
        [_engineBridge updateModelProperty:_selectedGroupName key:@"GridSize" value:value];
        _hasChanges = YES;
    }
}

#pragma mark - Filter Actions

- (void)filterChanged:(id)sender {
    [self reloadGroupDetails];
}

- (void)filterTextChanged:(id)sender {
    [self applyAvailableFilter];
    [_availableTableView reloadData];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == _filterField) {
        [self applyAvailableFilter];
        [_availableTableView reloadData];
    }
}

#pragma mark - Close Action

- (void)closeAction:(id)sender {
    [self.window close];
}

@end
