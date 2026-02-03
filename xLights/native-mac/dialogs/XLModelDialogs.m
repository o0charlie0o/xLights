/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLModelDialogs.h"
#import "../XLEngineBridge.h"

static const CGFloat kLabelWidth = 130.0;

#pragma mark - XLModelChainDialog

@interface XLModelChainDialog ()

@property (nonatomic, strong) NSPopUpButton *chainFromPopup;
@property (nonatomic, strong) NSTextField *currentModelLabel;

@end

@implementation XLModelChainDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Model Chaining";
        self.minWidth = 400;
        self.minHeight = 180;
        _availableModels = @[];
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Current model info
    _currentModelLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Configuring chain for: %@", _modelName ?: @"(none)"]];
    _currentModelLabel.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:_currentModelLabel];

    // Chain from selection
    _chainFromPopup = [XLBaseSheetController createPopUpButton];
    [_chainFromPopup addItemWithTitle:@"(Start of chain)"];

    for (NSString *model in _availableModels) {
        if (![model isEqualToString:_modelName]) {
            [_chainFromPopup addItemWithTitle:model];
        }
    }

    if (_chainFromModel) {
        [_chainFromPopup selectItemWithTitle:_chainFromModel];
    }

    NSStackView *chainRow = [XLBaseSheetController formRowWithLabel:@"Chain From:"
                                                            control:_chainFromPopup
                                                         labelWidth:kLabelWidth];
    [stack addArrangedSubview:chainRow];

    // Info text
    NSTextField *infoLabel = [NSTextField wrappingLabelWithString:
        @"When chained, this model's starting channel will follow the end of the selected model."];
    infoLabel.textColor = [NSColor secondaryLabelColor];
    infoLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:infoLabel];
    [infoLabel.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [infoLabel.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    return stack;
}

- (void)okClicked:(id)sender {
    if (_chainFromPopup.indexOfSelectedItem == 0) {
        _chainFromModel = nil;
    } else {
        _chainFromModel = _chainFromPopup.selectedItem.title;
    }
    [super okClicked:sender];
}

@end

#pragma mark - XLStrandNodeNamesDialog

@interface XLStrandNodeNamesDialog () <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableStrandNames;
@property (nonatomic, strong) NSMutableArray<NSMutableArray<NSString *> *> *mutableNodeNames;

@end

@implementation XLStrandNodeNamesDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Strand/Node Names";
        self.minWidth = 450;
        self.minHeight = 400;
        _strandCount = 1;
        _mutableStrandNames = [NSMutableArray array];
        _mutableNodeNames = [NSMutableArray array];
        _nodesPerStrand = @[];
    }
    return self;
}

- (void)setStrandNames:(NSArray<NSString *> *)strandNames {
    _mutableStrandNames = [strandNames mutableCopy];
}

- (NSArray<NSString *> *)strandNames {
    return [_mutableStrandNames copy];
}

- (void)setNodeNames:(NSArray<NSArray<NSString *> *> *)nodeNames {
    _mutableNodeNames = [NSMutableArray array];
    for (NSArray<NSString *> *nodes in nodeNames) {
        [_mutableNodeNames addObject:[nodes mutableCopy]];
    }
}

- (NSArray<NSArray<NSString *> *> *)nodeNames {
    return [_mutableNodeNames copy];
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Model info
    NSTextField *modelLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Model: %@", _modelName ?: @"(none)"]];
    modelLabel.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:modelLabel];

    // Outline view for strands and nodes
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:280].active = YES;

    _outlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
    _outlineView.dataSource = self;
    _outlineView.delegate = self;
    _outlineView.rowHeight = 24;
    _outlineView.usesAlternatingRowBackgroundColors = YES;

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Strand/Node";
    nameColumn.width = 150;
    [_outlineView addTableColumn:nameColumn];

    NSTableColumn *customNameColumn = [[NSTableColumn alloc] initWithIdentifier:@"customName"];
    customNameColumn.title = @"Custom Name";
    customNameColumn.width = 200;
    customNameColumn.editable = YES;
    [_outlineView addTableColumn:customNameColumn];

    _outlineView.outlineTableColumn = nameColumn;

    scrollView.documentView = _outlineView;

    [stack addArrangedSubview:scrollView];
    [scrollView.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [scrollView.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    return stack;
}

- (void)sheetDidLoad {
    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];
}

// NSOutlineViewDataSource
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nil) {
        return _strandCount;
    }
    if ([item isKindOfClass:[NSNumber class]]) {
        NSInteger strandIndex = [item integerValue];
        if (strandIndex < _nodesPerStrand.count) {
            return [_nodesPerStrand[strandIndex] integerValue];
        }
    }
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nil) {
        return @(index);
    }
    return @[@([item integerValue]), @(index)];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[NSNumber class]];
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if ([tableColumn.identifier isEqualToString:@"name"]) {
        NSTextField *cell = [outlineView makeViewWithIdentifier:@"nameCell" owner:self];
        if (!cell) {
            cell = [NSTextField labelWithString:@""];
            cell.identifier = @"nameCell";
        }

        if ([item isKindOfClass:[NSNumber class]]) {
            cell.stringValue = [NSString stringWithFormat:@"Strand %ld", (long)([item integerValue] + 1)];
        } else if ([item isKindOfClass:[NSArray class]]) {
            NSArray *nodeInfo = item;
            cell.stringValue = [NSString stringWithFormat:@"Node %ld", (long)([nodeInfo[1] integerValue] + 1)];
        }
        return cell;
    } else {
        NSTextField *cell = [outlineView makeViewWithIdentifier:@"customCell" owner:self];
        if (!cell) {
            cell = [[NSTextField alloc] initWithFrame:NSZeroRect];
            cell.identifier = @"customCell";
            cell.bordered = YES;
            cell.editable = YES;
            cell.target = self;
            cell.action = @selector(nameEdited:);
        }

        if ([item isKindOfClass:[NSNumber class]]) {
            NSInteger strandIndex = [item integerValue];
            cell.stringValue = (strandIndex < _mutableStrandNames.count) ? _mutableStrandNames[strandIndex] : @"";
            cell.tag = strandIndex * 10000;
        } else if ([item isKindOfClass:[NSArray class]]) {
            NSArray *nodeInfo = item;
            NSInteger strandIndex = [nodeInfo[0] integerValue];
            NSInteger nodeIndex = [nodeInfo[1] integerValue];
            if (strandIndex < _mutableNodeNames.count && nodeIndex < _mutableNodeNames[strandIndex].count) {
                cell.stringValue = _mutableNodeNames[strandIndex][nodeIndex];
            } else {
                cell.stringValue = @"";
            }
            cell.tag = strandIndex * 10000 + nodeIndex + 1;
        }
        return cell;
    }
}

- (void)nameEdited:(NSTextField *)sender {
    NSInteger tag = sender.tag;
    NSInteger strandIndex = tag / 10000;
    NSInteger nodeOffset = tag % 10000;

    if (nodeOffset == 0) {
        // Strand name
        while (_mutableStrandNames.count <= strandIndex) {
            [_mutableStrandNames addObject:@""];
        }
        _mutableStrandNames[strandIndex] = sender.stringValue;
    } else {
        // Node name
        NSInteger nodeIndex = nodeOffset - 1;
        while (_mutableNodeNames.count <= strandIndex) {
            [_mutableNodeNames addObject:[NSMutableArray array]];
        }
        while (_mutableNodeNames[strandIndex].count <= nodeIndex) {
            [_mutableNodeNames[strandIndex] addObject:@""];
        }
        _mutableNodeNames[strandIndex][nodeIndex] = sender.stringValue;
    }
}

@end

#pragma mark - XLModelDimmingCurveDialog

@interface XLModelDimmingCurveDialog ()

@property (nonatomic, strong) NSPopUpButton *curveTypePopup;
@property (nonatomic, strong) NSSlider *gammaSlider;
@property (nonatomic, strong) NSTextField *gammaLabel;
@property (nonatomic, strong) NSSlider *brightnessSlider;
@property (nonatomic, strong) NSTextField *brightnessLabel;
@property (nonatomic, strong) NSButton *allChannelsCheckbox;

@end

@implementation XLModelDimmingCurveDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Dimming Curve";
        self.minWidth = 400;
        self.minHeight = 280;
        _curveType = @"gamma";
        _gammaValue = 2.2;
        _brightness = 100;
        _applyToAllChannels = YES;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Model name
    NSTextField *modelLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Model: %@", _modelName ?: @"(none)"]];
    [stack addArrangedSubview:modelLabel];

    // Curve type
    _curveTypePopup = [XLBaseSheetController createPopUpButton];
    [_curveTypePopup addItemWithTitle:@"Linear"];
    [_curveTypePopup addItemWithTitle:@"Gamma"];
    [_curveTypePopup addItemWithTitle:@"Logarithmic"];
    [_curveTypePopup addItemWithTitle:@"Exponential"];
    [_curveTypePopup addItemWithTitle:@"Custom"];
    [_curveTypePopup selectItemWithTitle:[_curveType capitalizedString]];
    [_curveTypePopup setTarget:self];
    [_curveTypePopup setAction:@selector(curveTypeChanged:)];

    NSStackView *typeRow = [XLBaseSheetController formRowWithLabel:@"Curve Type:"
                                                           control:_curveTypePopup
                                                        labelWidth:kLabelWidth];
    [stack addArrangedSubview:typeRow];

    // Gamma slider
    NSStackView *gammaRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    gammaRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    gammaRow.spacing = 8;

    NSTextField *gammaTitle = [NSTextField labelWithString:@"Gamma:"];
    gammaTitle.alignment = NSTextAlignmentRight;
    [gammaTitle.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _gammaSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _gammaSlider.minValue = 0.5;
    _gammaSlider.maxValue = 4.0;
    _gammaSlider.doubleValue = _gammaValue;
    [_gammaSlider setTarget:self];
    [_gammaSlider setAction:@selector(gammaChanged:)];
    [_gammaSlider.widthAnchor constraintEqualToConstant:180].active = YES;

    _gammaLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%.2f", _gammaValue]];
    [_gammaLabel.widthAnchor constraintEqualToConstant:50].active = YES;

    [gammaRow addArrangedSubview:gammaTitle];
    [gammaRow addArrangedSubview:_gammaSlider];
    [gammaRow addArrangedSubview:_gammaLabel];
    [stack addArrangedSubview:gammaRow];

    // Brightness slider
    NSStackView *brightRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    brightRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    brightRow.spacing = 8;

    NSTextField *brightTitle = [NSTextField labelWithString:@"Brightness:"];
    brightTitle.alignment = NSTextAlignmentRight;
    [brightTitle.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _brightnessSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _brightnessSlider.minValue = 0;
    _brightnessSlider.maxValue = 100;
    _brightnessSlider.integerValue = _brightness;
    [_brightnessSlider setTarget:self];
    [_brightnessSlider setAction:@selector(brightnessChanged:)];
    [_brightnessSlider.widthAnchor constraintEqualToConstant:180].active = YES;

    _brightnessLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld%%", (long)_brightness]];
    [_brightnessLabel.widthAnchor constraintEqualToConstant:50].active = YES;

    [brightRow addArrangedSubview:brightTitle];
    [brightRow addArrangedSubview:_brightnessSlider];
    [brightRow addArrangedSubview:_brightnessLabel];
    [stack addArrangedSubview:brightRow];

    // Apply to all channels
    _allChannelsCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Apply to all channels (R, G, B)"];
    _allChannelsCheckbox.state = _applyToAllChannels ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_allChannelsCheckbox];

    return stack;
}

- (void)curveTypeChanged:(id)sender {
    BOOL isGamma = [[_curveTypePopup.selectedItem.title lowercaseString] isEqualToString:@"gamma"];
    _gammaSlider.enabled = isGamma;
}

- (void)gammaChanged:(id)sender {
    _gammaLabel.stringValue = [NSString stringWithFormat:@"%.2f", _gammaSlider.doubleValue];
}

- (void)brightnessChanged:(id)sender {
    _brightnessLabel.stringValue = [NSString stringWithFormat:@"%ld%%", (long)_brightnessSlider.integerValue];
}

- (void)okClicked:(id)sender {
    _curveType = [_curveTypePopup.selectedItem.title lowercaseString];
    _gammaValue = _gammaSlider.doubleValue;
    _brightness = _brightnessSlider.integerValue;
    _applyToAllChannels = (_allChannelsCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end

#pragma mark - XLEditAliasesDialog

@interface XLEditAliasesDialog () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableAliases;

@end

@implementation XLEditAliasesDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Edit Aliases";
        self.minWidth = 400;
        self.minHeight = 300;
        _mutableAliases = [NSMutableArray array];
    }
    return self;
}

- (void)setAliases:(NSArray<NSString *> *)aliases {
    _mutableAliases = [aliases mutableCopy];
}

- (NSArray<NSString *> *)aliases {
    return [_mutableAliases copy];
}

- (void)addAlias:(NSString *)alias {
    [_mutableAliases addObject:alias];
    [_tableView reloadData];
}

- (void)removeAliasAtIndex:(NSUInteger)index {
    if (index < _mutableAliases.count) {
        [_mutableAliases removeObjectAtIndex:index];
        [_tableView reloadData];
    }
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Element name
    NSTextField *elementLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Aliases for: %@", _elementName ?: @"(none)"]];
    elementLabel.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:elementLabel];

    // Table
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 24;

    NSTableColumn *aliasColumn = [[NSTableColumn alloc] initWithIdentifier:@"alias"];
    aliasColumn.title = @"Alias";
    aliasColumn.width = 340;
    aliasColumn.editable = YES;
    [_tableView addTableColumn:aliasColumn];

    scrollView.documentView = _tableView;

    [stack addArrangedSubview:scrollView];
    [scrollView.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [scrollView.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    // Add/Remove buttons
    NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 8;

    NSButton *addBtn = [NSButton buttonWithTitle:@"Add Alias" target:self action:@selector(addNewAlias:)];
    NSButton *removeBtn = [NSButton buttonWithTitle:@"Remove" target:self action:@selector(removeSelectedAlias:)];

    [buttonRow addArrangedSubview:addBtn];
    [buttonRow addArrangedSubview:removeBtn];
    [stack addArrangedSubview:buttonRow];

    return stack;
}

- (void)addNewAlias:(id)sender {
    [_mutableAliases addObject:@"New Alias"];
    [_tableView reloadData];
    NSInteger lastRow = _mutableAliases.count - 1;
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:lastRow] byExtendingSelection:NO];
    [_tableView editColumn:0 row:lastRow withEvent:nil select:YES];
}

- (void)removeSelectedAlias:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row >= 0 && row < _mutableAliases.count) {
        [_mutableAliases removeObjectAtIndex:row];
        [_tableView reloadData];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _mutableAliases.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTextField *cell = [tableView makeViewWithIdentifier:@"aliasCell" owner:self];
    if (!cell) {
        cell = [[NSTextField alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"aliasCell";
        cell.bordered = YES;
        cell.editable = YES;
        cell.target = self;
        cell.action = @selector(aliasEdited:);
    }
    cell.stringValue = _mutableAliases[row];
    cell.tag = row;
    return cell;
}

- (void)aliasEdited:(NSTextField *)sender {
    NSInteger row = sender.tag;
    if (row >= 0 && row < _mutableAliases.count) {
        _mutableAliases[row] = sender.stringValue;
    }
}

@end

#pragma mark - XLSubModelGenerateDialog

@interface XLSubModelGenerateDialog ()

@property (nonatomic, strong) NSTextField *countField;
@property (nonatomic, strong) NSStepper *countStepper;
@property (nonatomic, strong) NSTextField *prefixField;
@property (nonatomic, strong) NSPopUpButton *typePopup;
@property (nonatomic, strong) NSButton *overlapCheckbox;

@end

@implementation XLSubModelGenerateDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Generate Submodels";
        self.minWidth = 400;
        self.minHeight = 250;
        _submodelCount = 4;
        _namingPrefix = @"Segment";
        _submodelType = @"horizontal";
        _allowOverlap = NO;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Model name
    NSTextField *modelLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Generate submodels for: %@", _modelName ?: @"(none)"]];
    modelLabel.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:modelLabel];

    // Number of submodels
    NSStackView *countRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    countRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    countRow.spacing = 8;

    NSTextField *countLabel = [NSTextField labelWithString:@"Number:"];
    countLabel.alignment = NSTextAlignmentRight;
    [countLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _countField = [XLBaseSheetController createNumericField];
    _countField.integerValue = _submodelCount;
    [_countField setTarget:self];
    [_countField setAction:@selector(countFieldChanged:)];
    [_countField.widthAnchor constraintEqualToConstant:60].active = YES;

    _countStepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    _countStepper.minValue = 2;
    _countStepper.maxValue = 100;
    _countStepper.integerValue = _submodelCount;
    [_countStepper setTarget:self];
    [_countStepper setAction:@selector(countStepperChanged:)];

    [countRow addArrangedSubview:countLabel];
    [countRow addArrangedSubview:_countField];
    [countRow addArrangedSubview:_countStepper];
    [stack addArrangedSubview:countRow];

    // Naming prefix
    _prefixField = [XLBaseSheetController createTextField];
    _prefixField.stringValue = _namingPrefix;
    [_prefixField.widthAnchor constraintEqualToConstant:150].active = YES;

    NSStackView *prefixRow = [XLBaseSheetController formRowWithLabel:@"Name Prefix:"
                                                             control:_prefixField
                                                          labelWidth:kLabelWidth];
    [stack addArrangedSubview:prefixRow];

    // Submodel type
    _typePopup = [XLBaseSheetController createPopUpButton];
    [_typePopup addItemWithTitle:@"Horizontal Segments"];
    [_typePopup addItemWithTitle:@"Vertical Segments"];
    [_typePopup addItemWithTitle:@"Node Ranges"];
    [_typePopup addItemWithTitle:@"Strand-based"];

    _typePopup.menu.itemArray[0].representedObject = @"horizontal";
    _typePopup.menu.itemArray[1].representedObject = @"vertical";
    _typePopup.menu.itemArray[2].representedObject = @"ranges";
    _typePopup.menu.itemArray[3].representedObject = @"strands";

    for (NSMenuItem *item in _typePopup.menu.itemArray) {
        if ([item.representedObject isEqualToString:_submodelType]) {
            [_typePopup selectItem:item];
            break;
        }
    }

    NSStackView *typeRow = [XLBaseSheetController formRowWithLabel:@"Type:"
                                                           control:_typePopup
                                                        labelWidth:kLabelWidth];
    [stack addArrangedSubview:typeRow];

    // Overlap option
    _overlapCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Allow overlapping submodels"];
    _overlapCheckbox.state = _allowOverlap ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_overlapCheckbox];

    return stack;
}

- (void)countFieldChanged:(id)sender {
    _countStepper.integerValue = _countField.integerValue;
}

- (void)countStepperChanged:(id)sender {
    _countField.integerValue = _countStepper.integerValue;
}

- (void)okClicked:(id)sender {
    _submodelCount = _countField.integerValue;
    _namingPrefix = _prefixField.stringValue;
    _submodelType = _typePopup.selectedItem.representedObject;
    _allowOverlap = (_overlapCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end

#pragma mark - XLSevenSegmentDialog

@interface XLSevenSegmentDialog ()

@property (nonatomic, strong) NSTextField *digitCountField;
@property (nonatomic, strong) NSSlider *thicknessSlider;
@property (nonatomic, strong) NSSlider *spacingSlider;
@property (nonatomic, strong) NSButton *decimalCheckbox;
@property (nonatomic, strong) NSButton *colonCheckbox;
@property (nonatomic, strong) NSPopUpButton *orderingPopup;

@end

@implementation XLSevenSegmentDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Seven Segment Configuration";
        self.minWidth = 400;
        self.minHeight = 300;
        _digitCount = 4;
        _segmentThickness = 3.0;
        _digitSpacing = 5.0;
        _includeDecimalPoints = NO;
        _includeColons = NO;
        _nodeOrdering = @"clockwise";
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Digit count
    _digitCountField = [XLBaseSheetController createNumericField];
    _digitCountField.integerValue = _digitCount;
    [_digitCountField.widthAnchor constraintEqualToConstant:60].active = YES;

    NSStackView *countRow = [XLBaseSheetController formRowWithLabel:@"Number of Digits:"
                                                            control:_digitCountField
                                                         labelWidth:kLabelWidth];
    [stack addArrangedSubview:countRow];

    // Segment thickness
    NSStackView *thickRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    thickRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    thickRow.spacing = 8;

    NSTextField *thickLabel = [NSTextField labelWithString:@"Thickness:"];
    thickLabel.alignment = NSTextAlignmentRight;
    [thickLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _thicknessSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _thicknessSlider.minValue = 1;
    _thicknessSlider.maxValue = 10;
    _thicknessSlider.doubleValue = _segmentThickness;
    [_thicknessSlider.widthAnchor constraintEqualToConstant:150].active = YES;

    [thickRow addArrangedSubview:thickLabel];
    [thickRow addArrangedSubview:_thicknessSlider];
    [stack addArrangedSubview:thickRow];

    // Digit spacing
    NSStackView *spaceRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    spaceRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    spaceRow.spacing = 8;

    NSTextField *spaceLabel = [NSTextField labelWithString:@"Digit Spacing:"];
    spaceLabel.alignment = NSTextAlignmentRight;
    [spaceLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _spacingSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _spacingSlider.minValue = 0;
    _spacingSlider.maxValue = 20;
    _spacingSlider.doubleValue = _digitSpacing;
    [_spacingSlider.widthAnchor constraintEqualToConstant:150].active = YES;

    [spaceRow addArrangedSubview:spaceLabel];
    [spaceRow addArrangedSubview:_spacingSlider];
    [stack addArrangedSubview:spaceRow];

    // Node ordering
    _orderingPopup = [XLBaseSheetController createPopUpButton];
    [_orderingPopup addItemWithTitle:@"Clockwise from Top"];
    [_orderingPopup addItemWithTitle:@"Counter-clockwise from Top"];
    [_orderingPopup addItemWithTitle:@"Standard (A-G)"];

    NSStackView *orderRow = [XLBaseSheetController formRowWithLabel:@"Node Ordering:"
                                                            control:_orderingPopup
                                                         labelWidth:kLabelWidth];
    [stack addArrangedSubview:orderRow];

    // Checkboxes
    _decimalCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Include decimal points"];
    _decimalCheckbox.state = _includeDecimalPoints ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_decimalCheckbox];

    _colonCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Include colons (for time display)"];
    _colonCheckbox.state = _includeColons ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_colonCheckbox];

    return stack;
}

- (void)okClicked:(id)sender {
    _digitCount = _digitCountField.integerValue;
    _segmentThickness = _thicknessSlider.doubleValue;
    _digitSpacing = _spacingSlider.doubleValue;
    _includeDecimalPoints = (_decimalCheckbox.state == NSControlStateValueOn);
    _includeColons = (_colonCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end

#pragma mark - XLAutoLabelDialog

@interface XLAutoLabelDialog ()

@property (nonatomic, strong) NSTextField *startField;
@property (nonatomic, strong) NSTextField *prefixField;
@property (nonatomic, strong) NSTextField *suffixField;
@property (nonatomic, strong) NSTextField *incrementField;
@property (nonatomic, strong) NSTextField *paddingField;

@end

@implementation XLAutoLabelDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Auto Label";
        self.minWidth = 350;
        self.minHeight = 250;
        _startNumber = 1;
        _prefix = @"";
        _suffix = @"";
        _incrementStep = 1;
        _padding = 0;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;

    // Start number
    _startField = [XLBaseSheetController createNumericField];
    _startField.integerValue = _startNumber;
    [_startField.widthAnchor constraintEqualToConstant:80].active = YES;

    NSStackView *startRow = [XLBaseSheetController formRowWithLabel:@"Start Number:"
                                                            control:_startField
                                                         labelWidth:100];
    [stack addArrangedSubview:startRow];

    // Prefix
    _prefixField = [XLBaseSheetController createTextField];
    _prefixField.stringValue = _prefix;
    _prefixField.placeholderString = @"e.g., Node_";
    [_prefixField.widthAnchor constraintEqualToConstant:120].active = YES;

    NSStackView *prefixRow = [XLBaseSheetController formRowWithLabel:@"Prefix:"
                                                             control:_prefixField
                                                          labelWidth:100];
    [stack addArrangedSubview:prefixRow];

    // Suffix
    _suffixField = [XLBaseSheetController createTextField];
    _suffixField.stringValue = _suffix;
    _suffixField.placeholderString = @"e.g., _LED";
    [_suffixField.widthAnchor constraintEqualToConstant:120].active = YES;

    NSStackView *suffixRow = [XLBaseSheetController formRowWithLabel:@"Suffix:"
                                                             control:_suffixField
                                                          labelWidth:100];
    [stack addArrangedSubview:suffixRow];

    // Increment
    _incrementField = [XLBaseSheetController createNumericField];
    _incrementField.integerValue = _incrementStep;
    [_incrementField.widthAnchor constraintEqualToConstant:60].active = YES;

    NSStackView *incRow = [XLBaseSheetController formRowWithLabel:@"Increment:"
                                                          control:_incrementField
                                                       labelWidth:100];
    [stack addArrangedSubview:incRow];

    // Padding
    _paddingField = [XLBaseSheetController createNumericField];
    _paddingField.integerValue = _padding;
    _paddingField.placeholderString = @"0";
    [_paddingField.widthAnchor constraintEqualToConstant:60].active = YES;

    NSStackView *padRow = [XLBaseSheetController formRowWithLabel:@"Zero Padding:"
                                                          control:_paddingField
                                                       labelWidth:100];
    [stack addArrangedSubview:padRow];

    // Preview
    NSTextField *previewLabel = [NSTextField labelWithString:@"Preview: Node_001_LED, Node_002_LED, ..."];
    previewLabel.textColor = [NSColor secondaryLabelColor];
    previewLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:previewLabel];

    return stack;
}

- (void)okClicked:(id)sender {
    _startNumber = _startField.integerValue;
    _prefix = _prefixField.stringValue;
    _suffix = _suffixField.stringValue;
    _incrementStep = _incrementField.integerValue;
    _padding = _paddingField.integerValue;
    [super okClicked:sender];
}

@end

#pragma mark - Window Controllers (Stubs)

@implementation XLWiringDialog

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Wiring Diagram";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        _showFrontView = YES;
        _showNodeNumbers = YES;
        _showControllerConnections = NO;
        _zoomLevel = 1.0;
    }
    return self;
}

- (void)showWithCompletion:(void (^)(void))completion {
    // TODO: Implement full wiring diagram view
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

@end

@implementation XLPixelTestDialog

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 350)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Pixel Test";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        _modelNames = @[];
        _testMode = @"chase";
        _testColor = [NSColor whiteColor];
        _chaseSpeedMs = 100;
    }
    return self;
}

- (void)showWithCompletion:(void (^)(void))completion {
    // TODO: Implement full pixel test interface
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

@end

@implementation XLGenerateCustomModelDialog

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Generate Custom Model";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        _detectionThreshold = 128;
        _minimumBrightness = 10;
        _modelName = @"Custom Model";
        _blurAmount = 0;
    }
    return self;
}

- (void)showWithCompletion:(void (^)(BOOL))completion {
    // TODO: Implement full custom model generation
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

@end

@implementation XLPathGenerationDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Path Generation";
        self.minWidth = 350;
        self.minHeight = 200;
        _nodeCount = 50;
        _pathType = @"linear";
        _reverseDirection = NO;
        _closedLoop = NO;
    }
    return self;
}

- (NSView *)buildContentView {
    // TODO: Full implementation
    NSTextField *placeholder = [NSTextField labelWithString:@"Path generation options will appear here"];
    return placeholder;
}

@end
