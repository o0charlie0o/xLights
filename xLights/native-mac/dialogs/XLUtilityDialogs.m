/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLUtilityDialogs.h"

static const CGFloat kLabelWidth = 120.0;

#pragma mark - XLCheckboxSelectDialog

@interface XLCheckboxSelectDialog () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSMutableIndexSet *mutableSelectedIndices;
@property (nonatomic, strong) NSButton *selectAllButton;
@property (nonatomic, strong) NSButton *selectNoneButton;

@end

@implementation XLCheckboxSelectDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Select Items";
        self.minWidth = 350;
        self.minHeight = 300;
        _items = @[];
        _mutableSelectedIndices = [NSMutableIndexSet indexSet];
        _promptText = @"Select items:";
        _showSelectionButtons = YES;
    }
    return self;
}

- (instancetype)initWithItems:(NSArray<NSString *> *)items {
    self = [self init];
    if (self) {
        _items = [items copy];
    }
    return self;
}

- (instancetype)initWithItems:(NSArray<NSString *> *)items
             selectedIndices:(NSIndexSet *)selectedIndices {
    self = [self initWithItems:items];
    if (self) {
        if (selectedIndices) {
            _mutableSelectedIndices = [selectedIndices mutableCopy];
        }
    }
    return self;
}

- (NSIndexSet *)selectedIndices {
    return [_mutableSelectedIndices copy];
}

- (void)setSelectedIndices:(NSIndexSet *)selectedIndices {
    _mutableSelectedIndices = selectedIndices ? [selectedIndices mutableCopy] : [NSMutableIndexSet indexSet];
}

- (NSArray<NSString *> *)selectedItems {
    NSMutableArray *result = [NSMutableArray array];
    [_mutableSelectedIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if (idx < self.items.count) {
            [result addObject:self.items[idx]];
        }
    }];
    return result;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Prompt
    NSTextField *prompt = [NSTextField labelWithString:_promptText];
    [stack addArrangedSubview:prompt];

    // Table with checkboxes
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.allowsMultipleSelection = NO;
    _tableView.rowHeight = 24;
    _tableView.usesAlternatingRowBackgroundColors = YES;

    NSTableColumn *checkColumn = [[NSTableColumn alloc] initWithIdentifier:@"check"];
    checkColumn.title = @"";
    checkColumn.width = 30;
    checkColumn.minWidth = 30;
    checkColumn.maxWidth = 30;
    [_tableView addTableColumn:checkColumn];

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Item";
    nameColumn.width = 280;
    [_tableView addTableColumn:nameColumn];

    scrollView.documentView = _tableView;

    [stack addArrangedSubview:scrollView];
    [scrollView.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [scrollView.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    // Selection buttons
    if (_showSelectionButtons) {
        NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
        buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        buttonRow.spacing = 12;

        _selectAllButton = [NSButton buttonWithTitle:@"Select All" target:self action:@selector(selectAll:)];
        _selectNoneButton = [NSButton buttonWithTitle:@"Select None" target:self action:@selector(selectNone:)];

        [buttonRow addArrangedSubview:_selectAllButton];
        [buttonRow addArrangedSubview:_selectNoneButton];
        [stack addArrangedSubview:buttonRow];
    }

    return stack;
}

- (void)selectAll:(id)sender {
    [_mutableSelectedIndices addIndexesInRange:NSMakeRange(0, _items.count)];
    [_tableView reloadData];
}

- (void)selectNone:(id)sender {
    [_mutableSelectedIndices removeAllIndexes];
    [_tableView reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _items.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"check"]) {
        NSButton *checkbox = [tableView makeViewWithIdentifier:@"checkbox" owner:self];
        if (!checkbox) {
            checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxToggled:)];
            checkbox.identifier = @"checkbox";
        }
        checkbox.state = [_mutableSelectedIndices containsIndex:row] ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.tag = row;
        return checkbox;
    } else {
        NSTextField *cell = [tableView makeViewWithIdentifier:@"cell" owner:self];
        if (!cell) {
            cell = [NSTextField labelWithString:@""];
            cell.identifier = @"cell";
        }
        cell.stringValue = _items[row];
        return cell;
    }
}

- (void)checkboxToggled:(NSButton *)sender {
    NSInteger row = sender.tag;
    if (sender.state == NSControlStateValueOn) {
        [_mutableSelectedIndices addIndex:row];
    } else {
        [_mutableSelectedIndices removeIndex:row];
    }
}

- (NSString *)validate {
    if (_mutableSelectedIndices.count == 0) {
        return @"Please select at least one item.";
    }
    return nil;
}

@end

#pragma mark - XLAlignmentDialog

@interface XLAlignmentDialog ()

@property (nonatomic, strong) NSMatrix *alignmentMatrix;

@end

@implementation XLAlignmentDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Alignment";
        self.minWidth = 220;
        self.minHeight = 200;
        _horizontalAlignment = XLHorizontalAlignmentCenter;
        _verticalAlignment = XLVerticalAlignmentMiddle;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 12;

    NSTextField *prompt = [NSTextField labelWithString:@"Select alignment position:"];
    [stack addArrangedSubview:prompt];

    // Create 3x3 grid of radio buttons
    NSView *gridContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 150, 150)];
    gridContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [gridContainer.widthAnchor constraintEqualToConstant:150].active = YES;
    [gridContainer.heightAnchor constraintEqualToConstant:150].active = YES;

    NSArray *positions = @[
        @[@"TL", @"TC", @"TR"],
        @[@"ML", @"MC", @"MR"],
        @[@"BL", @"BC", @"BR"]
    ];

    NSArray *titles = @[
        @[@"Top\nLeft", @"Top\nCenter", @"Top\nRight"],
        @[@"Middle\nLeft", @"Center", @"Middle\nRight"],
        @[@"Bottom\nLeft", @"Bottom\nCenter", @"Bottom\nRight"]
    ];

    for (NSInteger row = 0; row < 3; row++) {
        for (NSInteger col = 0; col < 3; col++) {
            NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(col * 50, (2 - row) * 50, 48, 48)];
            btn.buttonType = NSButtonTypeOnOff;
            btn.bezelStyle = NSBezelStyleSmallSquare;
            btn.title = @"";
            btn.tag = row * 3 + col;
            [btn setTarget:self];
            [btn setAction:@selector(alignmentButtonClicked:)];

            // Set initial state
            if (row == _verticalAlignment && col == _horizontalAlignment) {
                btn.state = NSControlStateValueOn;
            }

            // Add accessibility label
            btn.accessibilityLabel = titles[row][col];

            [gridContainer addSubview:btn];
        }
    }

    [stack addArrangedSubview:gridContainer];

    // Add labels for clarity
    NSStackView *labelRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    labelRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    labelRow.distribution = NSStackViewDistributionEqualSpacing;

    NSTextField *leftLabel = [NSTextField labelWithString:@"Left"];
    leftLabel.font = [NSFont systemFontOfSize:10];
    leftLabel.textColor = [NSColor secondaryLabelColor];

    NSTextField *centerLabel = [NSTextField labelWithString:@"Center"];
    centerLabel.font = [NSFont systemFontOfSize:10];
    centerLabel.textColor = [NSColor secondaryLabelColor];

    NSTextField *rightLabel = [NSTextField labelWithString:@"Right"];
    rightLabel.font = [NSFont systemFontOfSize:10];
    rightLabel.textColor = [NSColor secondaryLabelColor];

    [labelRow addArrangedSubview:leftLabel];
    [labelRow addArrangedSubview:centerLabel];
    [labelRow addArrangedSubview:rightLabel];
    [labelRow.widthAnchor constraintEqualToConstant:150].active = YES;
    [stack addArrangedSubview:labelRow];

    return stack;
}

- (void)alignmentButtonClicked:(NSButton *)sender {
    // Deselect all buttons
    for (NSView *subview in sender.superview.subviews) {
        if ([subview isKindOfClass:[NSButton class]]) {
            ((NSButton *)subview).state = NSControlStateValueOff;
        }
    }

    // Select clicked button
    sender.state = NSControlStateValueOn;

    NSInteger tag = sender.tag;
    _verticalAlignment = tag / 3;
    _horizontalAlignment = tag % 3;
}

@end

#pragma mark - XLDuplicateDialog

@interface XLDuplicateDialog ()

@property (nonatomic, strong) NSTextField *countField;
@property (nonatomic, strong) NSStepper *countStepper;
@property (nonatomic, strong) NSTextField *gapField;
@property (nonatomic, strong) NSButton *retainCheckbox;

@end

@implementation XLDuplicateDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Duplicate";
        self.minWidth = 300;
        self.minHeight = 180;
        _copyCount = 1;
        _gapMs = 0;
        _retainDuration = NO;
        _maxCopies = 100;
        _showGapField = YES;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Count row
    NSStackView *countRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    countRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    countRow.spacing = 8;

    NSTextField *countLabel = [NSTextField labelWithString:@"Number of Copies:"];
    countLabel.alignment = NSTextAlignmentRight;
    [countLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _countField = [XLBaseSheetController createNumericField];
    _countField.integerValue = _copyCount;
    [_countField setTarget:self];
    [_countField setAction:@selector(countFieldChanged:)];
    [_countField.widthAnchor constraintEqualToConstant:60].active = YES;

    _countStepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    _countStepper.minValue = 1;
    _countStepper.maxValue = _maxCopies;
    _countStepper.increment = 1;
    _countStepper.integerValue = _copyCount;
    [_countStepper setTarget:self];
    [_countStepper setAction:@selector(countStepperChanged:)];

    [countRow addArrangedSubview:countLabel];
    [countRow addArrangedSubview:_countField];
    [countRow addArrangedSubview:_countStepper];
    [stack addArrangedSubview:countRow];

    // Gap row (optional)
    if (_showGapField) {
        NSStackView *gapRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
        gapRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        gapRow.spacing = 8;

        NSTextField *gapLabel = [NSTextField labelWithString:@"Gap (ms):"];
        gapLabel.alignment = NSTextAlignmentRight;
        [gapLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

        _gapField = [XLBaseSheetController createNumericField];
        _gapField.integerValue = _gapMs;
        [_gapField.widthAnchor constraintEqualToConstant:80].active = YES;

        [gapRow addArrangedSubview:gapLabel];
        [gapRow addArrangedSubview:_gapField];
        [stack addArrangedSubview:gapRow];
    }

    // Retain duration checkbox
    _retainCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Retain original duration"];
    _retainCheckbox.state = _retainDuration ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_retainCheckbox];

    return stack;
}

- (void)countFieldChanged:(id)sender {
    _countStepper.integerValue = _countField.integerValue;
}

- (void)countStepperChanged:(id)sender {
    _countField.integerValue = _countStepper.integerValue;
}

- (NSString *)validate {
    if (_countField.integerValue < 1 || _countField.integerValue > _maxCopies) {
        return [NSString stringWithFormat:@"Number of copies must be between 1 and %ld.", (long)_maxCopies];
    }
    if (_showGapField && _gapField.integerValue < 0) {
        return @"Gap cannot be negative.";
    }
    return nil;
}

- (void)okClicked:(id)sender {
    _copyCount = _countField.integerValue;
    if (_showGapField) {
        _gapMs = _gapField.integerValue;
    }
    _retainDuration = (_retainCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end

#pragma mark - XLSelectTimingsDialog

@interface XLSelectTimingsDialog () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSMutableIndexSet *mutableSelectedIndices;

@end

@implementation XLSelectTimingsDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Select Timing Tracks";
        self.minWidth = 350;
        self.minHeight = 280;
        _timingTracks = @[];
        _mutableSelectedIndices = [NSMutableIndexSet indexSet];
    }
    return self;
}

- (NSIndexSet *)selectedIndices {
    return [_mutableSelectedIndices copy];
}

- (void)setSelectedIndices:(NSIndexSet *)selectedIndices {
    _mutableSelectedIndices = selectedIndices ? [selectedIndices mutableCopy] : [NSMutableIndexSet indexSet];
}

- (NSArray<NSString *> *)selectedTimings {
    NSMutableArray *result = [NSMutableArray array];
    [_mutableSelectedIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if (idx < self.timingTracks.count) {
            [result addObject:self.timingTracks[idx]];
        }
    }];
    return result;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    NSTextField *prompt = [NSTextField labelWithString:@"Select timing tracks to include:"];
    [stack addArrangedSubview:prompt];

    // Table
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:160].active = YES;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 24;
    _tableView.usesAlternatingRowBackgroundColors = YES;

    NSTableColumn *checkColumn = [[NSTableColumn alloc] initWithIdentifier:@"check"];
    checkColumn.title = @"";
    checkColumn.width = 30;
    checkColumn.minWidth = 30;
    checkColumn.maxWidth = 30;
    [_tableView addTableColumn:checkColumn];

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Timing Track";
    nameColumn.width = 280;
    [_tableView addTableColumn:nameColumn];

    scrollView.documentView = _tableView;

    [stack addArrangedSubview:scrollView];
    [scrollView.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [scrollView.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    return stack;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _timingTracks.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"check"]) {
        NSButton *checkbox = [tableView makeViewWithIdentifier:@"checkbox" owner:self];
        if (!checkbox) {
            checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxToggled:)];
            checkbox.identifier = @"checkbox";
        }
        checkbox.state = [_mutableSelectedIndices containsIndex:row] ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.tag = row;
        return checkbox;
    } else {
        NSTextField *cell = [tableView makeViewWithIdentifier:@"cell" owner:self];
        if (!cell) {
            cell = [NSTextField labelWithString:@""];
            cell.identifier = @"cell";
        }
        cell.stringValue = _timingTracks[row];
        return cell;
    }
}

- (void)checkboxToggled:(NSButton *)sender {
    NSInteger row = sender.tag;
    if (sender.state == NSControlStateValueOn) {
        [_mutableSelectedIndices addIndex:row];
    } else {
        [_mutableSelectedIndices removeIndex:row];
    }
}

@end

#pragma mark - XLViewpointDialog

@interface XLViewpointDialog ()

@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *posXField;
@property (nonatomic, strong) NSTextField *posYField;
@property (nonatomic, strong) NSTextField *posZField;
@property (nonatomic, strong) NSTextField *rotXField;
@property (nonatomic, strong) NSTextField *rotYField;
@property (nonatomic, strong) NSTextField *rotZField;
@property (nonatomic, strong) NSTextField *fovField;
@property (nonatomic, strong) NSTextField *zoomField;

@end

@implementation XLViewpointDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Viewpoint";
        self.minWidth = 400;
        self.minHeight = 350;
        _viewpointName = @"New Viewpoint";
        _positionX = 0.0;
        _positionY = 0.0;
        _positionZ = 500.0;
        _rotationX = 0.0;
        _rotationY = 0.0;
        _rotationZ = 0.0;
        _fieldOfView = 45.0;
        _zoom = 1.0;
        _isNewViewpoint = YES;
    }
    return self;
}

- (void)sheetDidLoad {
    self.title = _isNewViewpoint ? @"New Viewpoint" : @"Edit Viewpoint";
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;

    // Name
    _nameField = [XLBaseSheetController createTextField];
    _nameField.stringValue = _viewpointName;
    [_nameField.widthAnchor constraintEqualToConstant:200].active = YES;
    NSStackView *nameRow = [XLBaseSheetController formRowWithLabel:@"Name:" control:_nameField labelWidth:80];
    [stack addArrangedSubview:nameRow];

    // Separator
    NSBox *separator1 = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator1.boxType = NSBoxSeparator;
    [stack addArrangedSubview:separator1];
    [separator1.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [separator1.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    // Position section
    NSTextField *posLabel = [NSTextField labelWithString:@"Position"];
    posLabel.font = [NSFont boldSystemFontOfSize:12];
    [stack addArrangedSubview:posLabel];

    NSStackView *posRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    posRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    posRow.spacing = 16;

    _posXField = [self createCoordinateFieldWithLabel:@"X:" value:_positionX inContainer:posRow];
    _posYField = [self createCoordinateFieldWithLabel:@"Y:" value:_positionY inContainer:posRow];
    _posZField = [self createCoordinateFieldWithLabel:@"Z:" value:_positionZ inContainer:posRow];

    [stack addArrangedSubview:posRow];

    // Rotation section
    NSTextField *rotLabel = [NSTextField labelWithString:@"Rotation"];
    rotLabel.font = [NSFont boldSystemFontOfSize:12];
    [stack addArrangedSubview:rotLabel];

    NSStackView *rotRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    rotRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    rotRow.spacing = 16;

    _rotXField = [self createCoordinateFieldWithLabel:@"Pitch:" value:_rotationX inContainer:rotRow];
    _rotYField = [self createCoordinateFieldWithLabel:@"Yaw:" value:_rotationY inContainer:rotRow];
    _rotZField = [self createCoordinateFieldWithLabel:@"Roll:" value:_rotationZ inContainer:rotRow];

    [stack addArrangedSubview:rotRow];

    // Camera section
    NSBox *separator2 = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator2.boxType = NSBoxSeparator;
    [stack addArrangedSubview:separator2];
    [separator2.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [separator2.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    NSTextField *camLabel = [NSTextField labelWithString:@"Camera"];
    camLabel.font = [NSFont boldSystemFontOfSize:12];
    [stack addArrangedSubview:camLabel];

    NSStackView *camRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    camRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    camRow.spacing = 16;

    _fovField = [self createCoordinateFieldWithLabel:@"FOV:" value:_fieldOfView inContainer:camRow];
    _zoomField = [self createCoordinateFieldWithLabel:@"Zoom:" value:_zoom inContainer:camRow];

    [stack addArrangedSubview:camRow];

    return stack;
}

- (NSTextField *)createCoordinateFieldWithLabel:(NSString *)labelText value:(double)value inContainer:(NSStackView *)container {
    NSStackView *fieldStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    fieldStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fieldStack.spacing = 4;

    NSTextField *label = [NSTextField labelWithString:labelText];
    label.font = [NSFont systemFontOfSize:11];
    [label.widthAnchor constraintEqualToConstant:35].active = YES;

    NSTextField *field = [XLBaseSheetController createTextField];
    field.stringValue = [NSString stringWithFormat:@"%.2f", value];
    [field.widthAnchor constraintEqualToConstant:70].active = YES;

    [fieldStack addArrangedSubview:label];
    [fieldStack addArrangedSubview:field];
    [container addArrangedSubview:fieldStack];

    return field;
}

- (NSString *)validate {
    if (_nameField.stringValue.length == 0) {
        return @"Please enter a viewpoint name.";
    }
    return nil;
}

- (void)okClicked:(id)sender {
    _viewpointName = _nameField.stringValue;
    _positionX = [_posXField doubleValue];
    _positionY = [_posYField doubleValue];
    _positionZ = [_posZField doubleValue];
    _rotationX = [_rotXField doubleValue];
    _rotationY = [_rotYField doubleValue];
    _rotationZ = [_rotZField doubleValue];
    _fieldOfView = [_fovField doubleValue];
    _zoom = [_zoomField doubleValue];
    [super okClicked:sender];
}

@end

#pragma mark - XLPaletteManagementDialog

@interface XLPaletteManagementDialog () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTableView *tableView;

@end

@implementation XLPaletteManagementDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Palette Management";
        self.okButtonTitle = @"Close";
        self.cancelButtonTitle = nil; // Hide cancel button
        self.minWidth = 400;
        self.minHeight = 350;
        _paletteNames = @[];
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Table
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 24;
    _tableView.usesAlternatingRowBackgroundColors = YES;

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Palette Name";
    nameColumn.width = 350;
    [_tableView addTableColumn:nameColumn];

    scrollView.documentView = _tableView;

    [stack addArrangedSubview:scrollView];
    [scrollView.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [scrollView.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    // Action buttons
    NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 8;

    NSButton *loadBtn = [NSButton buttonWithTitle:@"Load" target:self action:@selector(loadPalette:)];
    NSButton *saveBtn = [NSButton buttonWithTitle:@"Save" target:self action:@selector(savePalette:)];
    NSButton *deleteBtn = [NSButton buttonWithTitle:@"Delete" target:self action:@selector(deletePalette:)];
    NSButton *copyBtn = [NSButton buttonWithTitle:@"Copy" target:self action:@selector(copyPalette:)];

    [buttonRow addArrangedSubview:loadBtn];
    [buttonRow addArrangedSubview:saveBtn];
    [buttonRow addArrangedSubview:deleteBtn];
    [buttonRow addArrangedSubview:copyBtn];

    [stack addArrangedSubview:buttonRow];

    return stack;
}

- (void)loadPalette:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row >= 0 && row < _paletteNames.count) {
        if (_paletteActionHandler) {
            _paletteActionHandler(@"load", _paletteNames[row]);
        }
    }
}

- (void)savePalette:(id)sender {
    if (_paletteActionHandler) {
        _paletteActionHandler(@"save", @"");
    }
}

- (void)deletePalette:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row >= 0 && row < _paletteNames.count) {
        if (_paletteActionHandler) {
            _paletteActionHandler(@"delete", _paletteNames[row]);
        }
    }
}

- (void)copyPalette:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row >= 0 && row < _paletteNames.count) {
        if (_paletteActionHandler) {
            _paletteActionHandler(@"copy", _paletteNames[row]);
        }
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _paletteNames.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTextField *cell = [tableView makeViewWithIdentifier:@"cell" owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = @"cell";
    }
    cell.stringValue = _paletteNames[row];
    return cell;
}

@end

#pragma mark - XLNoteRangeDialog

@interface XLNoteRangeDialog ()

@property (nonatomic, strong) NSSlider *minSlider;
@property (nonatomic, strong) NSSlider *maxSlider;
@property (nonatomic, strong) NSTextField *minLabel;
@property (nonatomic, strong) NSTextField *maxLabel;

@end

@implementation XLNoteRangeDialog

static NSString *noteNameForMidi(NSInteger midi) {
    static NSArray *noteNames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        noteNames = @[@"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B"];
    });
    NSInteger octave = midi / 12 - 1;
    NSInteger note = midi % 12;
    return [NSString stringWithFormat:@"%@%ld", noteNames[note], (long)octave];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Note Range";
        self.minWidth = 400;
        self.minHeight = 180;
        _minNote = 36;  // C2
        _maxNote = 96;  // C7
        _showNoteNames = YES;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 16;

    // Min note row
    NSStackView *minRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    minRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    minRow.spacing = 8;

    NSTextField *minTitle = [NSTextField labelWithString:@"Min Note:"];
    [minTitle.widthAnchor constraintEqualToConstant:70].active = YES;

    _minSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _minSlider.minValue = 0;
    _minSlider.maxValue = 127;
    _minSlider.integerValue = _minNote;
    [_minSlider setTarget:self];
    [_minSlider setAction:@selector(minSliderChanged:)];
    [_minSlider.widthAnchor constraintEqualToConstant:200].active = YES;

    _minLabel = [NSTextField labelWithString:[self labelForNote:_minNote]];
    [_minLabel.widthAnchor constraintEqualToConstant:80].active = YES;

    [minRow addArrangedSubview:minTitle];
    [minRow addArrangedSubview:_minSlider];
    [minRow addArrangedSubview:_minLabel];
    [stack addArrangedSubview:minRow];

    // Max note row
    NSStackView *maxRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    maxRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    maxRow.spacing = 8;

    NSTextField *maxTitle = [NSTextField labelWithString:@"Max Note:"];
    [maxTitle.widthAnchor constraintEqualToConstant:70].active = YES;

    _maxSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _maxSlider.minValue = 0;
    _maxSlider.maxValue = 127;
    _maxSlider.integerValue = _maxNote;
    [_maxSlider setTarget:self];
    [_maxSlider setAction:@selector(maxSliderChanged:)];
    [_maxSlider.widthAnchor constraintEqualToConstant:200].active = YES;

    _maxLabel = [NSTextField labelWithString:[self labelForNote:_maxNote]];
    [_maxLabel.widthAnchor constraintEqualToConstant:80].active = YES;

    [maxRow addArrangedSubview:maxTitle];
    [maxRow addArrangedSubview:_maxSlider];
    [maxRow addArrangedSubview:_maxLabel];
    [stack addArrangedSubview:maxRow];

    return stack;
}

- (NSString *)labelForNote:(NSInteger)note {
    if (_showNoteNames) {
        return [NSString stringWithFormat:@"%ld (%@)", (long)note, noteNameForMidi(note)];
    }
    return [NSString stringWithFormat:@"%ld", (long)note];
}

- (void)minSliderChanged:(id)sender {
    _minLabel.stringValue = [self labelForNote:_minSlider.integerValue];
    if (_minSlider.integerValue > _maxSlider.integerValue) {
        _maxSlider.integerValue = _minSlider.integerValue;
        _maxLabel.stringValue = [self labelForNote:_maxSlider.integerValue];
    }
}

- (void)maxSliderChanged:(id)sender {
    _maxLabel.stringValue = [self labelForNote:_maxSlider.integerValue];
    if (_maxSlider.integerValue < _minSlider.integerValue) {
        _minSlider.integerValue = _maxSlider.integerValue;
        _minLabel.stringValue = [self labelForNote:_minSlider.integerValue];
    }
}

- (void)okClicked:(id)sender {
    _minNote = _minSlider.integerValue;
    _maxNote = _maxSlider.integerValue;
    [super okClicked:sender];
}

@end

#pragma mark - XLCustomTimingDialog

@interface XLCustomTimingDialog ()

@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *intervalField;
@property (nonatomic, strong) NSButton *fixedCheckbox;

@end

@implementation XLCustomTimingDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Custom Timing";
        self.minWidth = 350;
        self.minHeight = 180;
        _timingName = @"New Timing";
        _intervalMs = 50;
        _isFixedTiming = NO;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Name
    _nameField = [XLBaseSheetController createTextField];
    _nameField.stringValue = _timingName;
    [_nameField.widthAnchor constraintEqualToConstant:200].active = YES;
    NSStackView *nameRow = [XLBaseSheetController formRowWithLabel:@"Name:" control:_nameField labelWidth:kLabelWidth];
    [stack addArrangedSubview:nameRow];

    // Interval
    NSStackView *intervalRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    intervalRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    intervalRow.spacing = 8;

    NSTextField *intervalLabel = [NSTextField labelWithString:@"Interval:"];
    intervalLabel.alignment = NSTextAlignmentRight;
    [intervalLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _intervalField = [XLBaseSheetController createNumericField];
    _intervalField.integerValue = _intervalMs;
    [_intervalField.widthAnchor constraintEqualToConstant:80].active = YES;

    NSTextField *msLabel = [NSTextField labelWithString:@"ms"];
    msLabel.textColor = [NSColor secondaryLabelColor];

    [intervalRow addArrangedSubview:intervalLabel];
    [intervalRow addArrangedSubview:_intervalField];
    [intervalRow addArrangedSubview:msLabel];
    [stack addArrangedSubview:intervalRow];

    // Fixed timing checkbox
    _fixedCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Fixed timing interval"];
    _fixedCheckbox.state = _isFixedTiming ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_fixedCheckbox];

    return stack;
}

- (NSString *)validate {
    if (_nameField.stringValue.length == 0) {
        return @"Please enter a timing name.";
    }
    if (_intervalField.integerValue < 10 || _intervalField.integerValue > 1000) {
        return @"Interval must be between 10 and 1000 ms.";
    }
    return nil;
}

- (void)okClicked:(id)sender {
    _timingName = _nameField.stringValue;
    _intervalMs = _intervalField.integerValue;
    _isFixedTiming = (_fixedCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end

#pragma mark - XLEmailDialog

@interface XLEmailDialog ()

@property (nonatomic, strong) NSTextField *recipientField;
@property (nonatomic, strong) NSTextField *subjectField;
@property (nonatomic, strong) NSScrollView *bodyScrollView;
@property (nonatomic, strong) NSButton *attachmentCheckbox;
@property (nonatomic, strong) NSTextField *attachmentPathField;
@property (nonatomic, strong) NSButton *browseButton;

@end

@implementation XLEmailDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Send Email";
        self.okButtonTitle = @"Send";
        self.minWidth = 450;
        self.minHeight = 350;
        _recipientEmail = @"";
        _subject = @"";
        _body = @"";
        _includeAttachment = NO;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;

    // Recipient
    _recipientField = [XLBaseSheetController createTextField];
    _recipientField.stringValue = _recipientEmail;
    _recipientField.placeholderString = @"recipient@example.com";
    [_recipientField.widthAnchor constraintEqualToConstant:280].active = YES;
    NSStackView *recipientRow = [XLBaseSheetController formRowWithLabel:@"To:" control:_recipientField labelWidth:80];
    [stack addArrangedSubview:recipientRow];

    // Subject
    _subjectField = [XLBaseSheetController createTextField];
    _subjectField.stringValue = _subject;
    [_subjectField.widthAnchor constraintEqualToConstant:280].active = YES;
    NSStackView *subjectRow = [XLBaseSheetController formRowWithLabel:@"Subject:" control:_subjectField labelWidth:80];
    [stack addArrangedSubview:subjectRow];

    // Body
    _bodyScrollView = [XLBaseSheetController createTextViewWithHeight:120];
    NSTextView *textView = [XLBaseSheetController textViewFromScrollView:_bodyScrollView];
    textView.string = _body;

    NSTextField *bodyLabel = [NSTextField labelWithString:@"Message:"];
    bodyLabel.alignment = NSTextAlignmentRight;

    NSStackView *bodyRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    bodyRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bodyRow.alignment = NSLayoutAttributeTop;
    bodyRow.spacing = 8;
    [bodyLabel.widthAnchor constraintEqualToConstant:80].active = YES;
    [bodyRow addArrangedSubview:bodyLabel];
    [bodyRow addArrangedSubview:_bodyScrollView];
    [stack addArrangedSubview:bodyRow];
    [_bodyScrollView.widthAnchor constraintEqualToConstant:280].active = YES;

    // Attachment
    _attachmentCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Include attachment"];
    _attachmentCheckbox.state = _includeAttachment ? NSControlStateValueOn : NSControlStateValueOff;
    [_attachmentCheckbox setTarget:self];
    [_attachmentCheckbox setAction:@selector(attachmentToggled:)];
    [stack addArrangedSubview:_attachmentCheckbox];

    // Attachment path
    NSStackView *attachRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    attachRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    attachRow.spacing = 8;

    NSTextField *attachLabel = [NSTextField labelWithString:@"File:"];
    attachLabel.alignment = NSTextAlignmentRight;
    [attachLabel.widthAnchor constraintEqualToConstant:80].active = YES;

    _attachmentPathField = [XLBaseSheetController createTextField];
    _attachmentPathField.editable = NO;
    _attachmentPathField.stringValue = _attachmentPath ?: @"";
    _attachmentPathField.enabled = _includeAttachment;
    [_attachmentPathField.widthAnchor constraintEqualToConstant:200].active = YES;

    _browseButton = [NSButton buttonWithTitle:@"Browse..." target:self action:@selector(browseAttachment:)];
    _browseButton.enabled = _includeAttachment;

    [attachRow addArrangedSubview:attachLabel];
    [attachRow addArrangedSubview:_attachmentPathField];
    [attachRow addArrangedSubview:_browseButton];
    [stack addArrangedSubview:attachRow];

    return stack;
}

- (void)attachmentToggled:(id)sender {
    BOOL enabled = (_attachmentCheckbox.state == NSControlStateValueOn);
    _attachmentPathField.enabled = enabled;
    _browseButton.enabled = enabled;
}

- (void)browseAttachment:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;

    [panel beginSheetModalForWindow:self.sheet completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            self.attachmentPathField.stringValue = panel.URL.path;
            self.attachmentPath = panel.URL.path;
        }
    }];
}

- (NSString *)validate {
    if (_recipientField.stringValue.length == 0) {
        return @"Please enter a recipient email address.";
    }
    // Basic email validation
    NSString *email = _recipientField.stringValue;
    if ([email rangeOfString:@"@"].location == NSNotFound ||
        [email rangeOfString:@"."].location == NSNotFound) {
        return @"Please enter a valid email address.";
    }
    if (_subjectField.stringValue.length == 0) {
        return @"Please enter a subject.";
    }
    if (_attachmentCheckbox.state == NSControlStateValueOn &&
        _attachmentPathField.stringValue.length == 0) {
        return @"Please select an attachment file.";
    }
    return nil;
}

- (void)okClicked:(id)sender {
    _recipientEmail = _recipientField.stringValue;
    _subject = _subjectField.stringValue;
    NSTextView *textView = [XLBaseSheetController textViewFromScrollView:_bodyScrollView];
    _body = textView.string;
    _includeAttachment = (_attachmentCheckbox.state == NSControlStateValueOn);
    if (_includeAttachment) {
        _attachmentPath = _attachmentPathField.stringValue;
    }
    [super okClicked:sender];
}

@end
