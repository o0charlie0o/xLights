/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLModelCreationSheet.h"
#import "../XLEngineBridge.h"

// Model types - using C array to avoid heap corruption from wxWidgets
static const XLModelTypeDef kModelTypes[] = {
    { "Single Line", "Single Line", "line.diagonal", "Linear string of lights" },
    { "Matrix", "Matrix", "square.grid.3x3", "2D grid of pixels" },
    { "Arches", "Arches", "rainbow", "Arch or dome shapes" },
    { "Tree", "Tree", "triangle", "Christmas tree layouts" },
    { "Star", "Star", "star", "Star shapes" },
    { "Circle", "Circle", "circle", "Circular layouts" },
    { "Cube", "Cube", "cube", "3D cube layout" },
    { "Sphere", "Sphere", "globe", "Spherical layout" },
    { "Spinner", "Spinner", "rays", "Rotating spinner layout" },
    { "Candy Canes", "Candy Canes", "pencil", "Candy cane shapes" },
    { "Icicles", "Icicles", "chart.bar", "Icicle drops" },
    { "Window Frame", "Window Frame", "rectangle", "Window frame perimeter" },
    { "Wreath", "Wreath", "circle.circle", "Circular wreath" },
    { "Poly Line", "Poly Line", "scribble.variable", "Multi-segment line" },
    { "Channel Block", "Channel Block", "square.stack", "DMX channel block" },
    { "Custom", "Custom", "square.and.pencil", "Custom pixel layout" },
    { "Image", "Image", "photo", "Image-based layout" },
};
static const int kModelTypeCount = sizeof(kModelTypes) / sizeof(kModelTypes[0]);

static const CGFloat kSheetWidth = 600.0;
static const CGFloat kSheetHeight = 500.0;
static const CGFloat kGridCellSize = 100.0;
static const CGFloat kGridSpacing = 12.0;

#pragma mark - XLModelTypeCell

@interface XLModelTypeCell : NSCollectionViewItem
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, strong) NSTextField *nameLabel;
@end

@implementation XLModelTypeCell

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kGridCellSize, kGridCellSize)];
    view.wantsLayer = YES;
    view.layer.cornerRadius = 8.0;
    view.layer.borderWidth = 2.0;
    view.layer.borderColor = [NSColor clearColor].CGColor;

    _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [view addSubview:_iconView];

    _nameLabel = [NSTextField labelWithString:@""];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.alignment = NSTextAlignmentCenter;
    _nameLabel.font = [NSFont systemFontOfSize:11];
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [view addSubview:_nameLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [_iconView.topAnchor constraintEqualToAnchor:view.topAnchor constant:16],
        [_iconView.widthAnchor constraintEqualToConstant:40],
        [_iconView.heightAnchor constraintEqualToConstant:40],

        [_nameLabel.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [_nameLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:8],
        [_nameLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:4],
        [_nameLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-4],
    ]];

    self.view = view;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    if (selected) {
        self.view.layer.borderColor = [NSColor controlAccentColor].CGColor;
        self.view.layer.backgroundColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.1].CGColor;
    } else {
        self.view.layer.borderColor = [NSColor clearColor].CGColor;
        self.view.layer.backgroundColor = [[NSColor controlBackgroundColor] CGColor];
    }
}

@end

#pragma mark - XLModelCreationSheet

@interface XLModelCreationSheet () <NSCollectionViewDataSource, NSCollectionViewDelegate>

@property (nonatomic, strong) NSWindow *sheet;
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSCollectionView *typeGrid;
@property (nonatomic, strong) NSView *configContainer;
@property (nonatomic, strong) XLModelConfigViewController *configViewController;

@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *nextButton;
@property (nonatomic, strong) NSButton *createButton;

@property (nonatomic, weak) NSWindow *parentWindow;
@property (nonatomic, copy) XLModelCreationCompletion completion;

@property (nonatomic, assign) NSInteger selectedTypeIndex;
@property (nonatomic, assign) BOOL showingConfig;

@end

@implementation XLModelCreationSheet

- (instancetype)init {
    self = [super init];
    if (self) {
        _selectedTypeIndex = -1;
        _showingConfig = NO;
    }
    return self;
}

- (void)showAsSheetForWindow:(NSWindow *)parentWindow
               withModelType:(NSString *)modelType
                  completion:(XLModelCreationCompletion)completion {
    _parentWindow = parentWindow;
    _completion = completion;

    [self buildSheet];

    if (modelType) {
        [self selectModelType:modelType];
        [self showConfigurationView];
    }

    [parentWindow beginSheet:_sheet completionHandler:^(NSModalResponse returnCode) {
        // Sheet dismissed
    }];
}

- (void)buildSheet {
    _sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kSheetWidth, kSheetHeight)
                                         styleMask:NSWindowStyleMaskTitled
                                           backing:NSBackingStoreBuffered
                                             defer:YES];
    _sheet.title = @"Create New Model";

    _contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSheetWidth, kSheetHeight)];
    _sheet.contentView = _contentView;

    [self buildTypePickerView];
    [self buildConfigContainer];
    [self buildButtonBar];

    [self updateButtonStates];
}

- (void)buildTypePickerView {
    // Title label
    NSTextField *titleLabel = [NSTextField labelWithString:@"Select Model Type"];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont boldSystemFontOfSize:16];
    [_contentView addSubview:titleLabel];

    // Collection view for model types
    NSCollectionViewFlowLayout *layout = [[NSCollectionViewFlowLayout alloc] init];
    layout.itemSize = NSMakeSize(kGridCellSize, kGridCellSize);
    layout.minimumInteritemSpacing = kGridSpacing;
    layout.minimumLineSpacing = kGridSpacing;
    layout.sectionInset = NSEdgeInsetsMake(kGridSpacing, kGridSpacing, kGridSpacing, kGridSpacing);

    _typeGrid = [[NSCollectionView alloc] initWithFrame:NSZeroRect];
    _typeGrid.collectionViewLayout = layout;
    _typeGrid.dataSource = self;
    _typeGrid.delegate = self;
    _typeGrid.selectable = YES;
    _typeGrid.allowsMultipleSelection = NO;
    _typeGrid.backgroundColors = @[[NSColor clearColor]];
    [_typeGrid registerClass:[XLModelTypeCell class] forItemWithIdentifier:@"ModelTypeCell"];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.documentView = _typeGrid;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.borderType = NSNoBorder;
    scrollView.drawsBackground = NO;
    [_contentView addSubview:scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:_contentView.topAnchor constant:20],
        [titleLabel.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:20],

        [scrollView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12],
        [scrollView.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor constant:-60],
    ]];
}

- (void)buildConfigContainer {
    _configContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 60, kSheetWidth, kSheetHeight - 60)];
    _configContainer.hidden = YES;
    _configContainer.wantsLayer = YES;
    [_contentView addSubview:_configContainer];
}

- (void)buildButtonBar {
    // Button bar at bottom
    NSView *buttonBar = [[NSView alloc] initWithFrame:NSZeroRect];
    buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentView addSubview:buttonBar];

    _cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelClicked:)];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    _cancelButton.keyEquivalent = @"\033"; // Escape
    [buttonBar addSubview:_cancelButton];

    _backButton = [NSButton buttonWithTitle:@"Back" target:self action:@selector(backClicked:)];
    _backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonBar addSubview:_backButton];

    _nextButton = [NSButton buttonWithTitle:@"Next" target:self action:@selector(nextClicked:)];
    _nextButton.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonBar addSubview:_nextButton];

    _createButton = [NSButton buttonWithTitle:@"Create" target:self action:@selector(createClicked:)];
    _createButton.translatesAutoresizingMaskIntoConstraints = NO;
    _createButton.keyEquivalent = @"\r"; // Return
    _createButton.bezelStyle = NSBezelStyleRounded;
    [buttonBar addSubview:_createButton];

    [NSLayoutConstraint activateConstraints:@[
        [buttonBar.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor],
        [buttonBar.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor],
        [buttonBar.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor],
        [buttonBar.heightAnchor constraintEqualToConstant:50],

        [_cancelButton.leadingAnchor constraintEqualToAnchor:buttonBar.leadingAnchor constant:20],
        [_cancelButton.centerYAnchor constraintEqualToAnchor:buttonBar.centerYAnchor],

        [_createButton.trailingAnchor constraintEqualToAnchor:buttonBar.trailingAnchor constant:-20],
        [_createButton.centerYAnchor constraintEqualToAnchor:buttonBar.centerYAnchor],

        [_nextButton.trailingAnchor constraintEqualToAnchor:_createButton.leadingAnchor constant:-8],
        [_nextButton.centerYAnchor constraintEqualToAnchor:buttonBar.centerYAnchor],

        [_backButton.trailingAnchor constraintEqualToAnchor:_nextButton.leadingAnchor constant:-8],
        [_backButton.centerYAnchor constraintEqualToAnchor:buttonBar.centerYAnchor],
    ]];
}

- (void)updateButtonStates {
    _backButton.hidden = !_showingConfig;
    _nextButton.hidden = _showingConfig;
    _createButton.hidden = !_showingConfig;
    _nextButton.enabled = _selectedTypeIndex >= 0;
}

#pragma mark - NSCollectionViewDataSource

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return kModelTypeCount;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    XLModelTypeCell *cell = [collectionView makeItemWithIdentifier:@"ModelTypeCell" forIndexPath:indexPath];

    NSInteger index = indexPath.item;
    if (index >= 0 && index < kModelTypeCount) {
        const XLModelTypeDef *typeDef = &kModelTypes[index];

        NSString *iconName = [NSString stringWithUTF8String:typeDef->iconName];
        NSImage *icon = [NSImage imageWithSystemSymbolName:iconName accessibilityDescription:nil];
        if (icon) {
            NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:28 weight:NSFontWeightRegular];
            cell.iconView.image = [icon imageWithSymbolConfiguration:config];
            cell.iconView.contentTintColor = [NSColor secondaryLabelColor];
        }

        cell.nameLabel.stringValue = [NSString stringWithUTF8String:typeDef->displayName];
    }

    return cell;
}

#pragma mark - NSCollectionViewDelegate

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    NSIndexPath *indexPath = indexPaths.anyObject;
    if (indexPath) {
        _selectedTypeIndex = indexPath.item;
        [self updateButtonStates];
    }
}

- (void)collectionView:(NSCollectionView *)collectionView didDeselectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths {
    if (collectionView.selectionIndexPaths.count == 0) {
        _selectedTypeIndex = -1;
        [self updateButtonStates];
    }
}

#pragma mark - Actions

- (void)cancelClicked:(id)sender {
    [_parentWindow endSheet:_sheet returnCode:NSModalResponseCancel];
    if (_completion) {
        _completion(NO, nil);
    }
}

- (void)backClicked:(id)sender {
    [self showTypePickerView];
}

- (void)nextClicked:(id)sender {
    if (_selectedTypeIndex >= 0 && _selectedTypeIndex < kModelTypeCount) {
        [self showConfigurationView];
    }
}

- (void)createClicked:(id)sender {
    if (!_configViewController) return;

    NSString *error = [_configViewController validateConfiguration];
    if (error) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Invalid Configuration";
        alert.informativeText = error;
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:_sheet completionHandler:nil];
        return;
    }

    NSString *modelName = _configViewController.modelName;
    NSString *modelType = _configViewController.modelType;
    NSDictionary *properties = [_configViewController configurationProperties];

    // Create the model via engine bridge
    BOOL success = [_engineBridge createModel:modelType name:modelName properties:properties];

    [_parentWindow endSheet:_sheet returnCode:success ? NSModalResponseOK : NSModalResponseCancel];

    if (_completion) {
        _completion(success, success ? modelName : nil);
    }
}

#pragma mark - View Transitions

- (void)selectModelType:(NSString *)modelType {
    for (NSInteger i = 0; i < kModelTypeCount; i++) {
        if (strcmp(kModelTypes[i].typeId, [modelType UTF8String]) == 0) {
            _selectedTypeIndex = i;
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:i inSection:0];
            [_typeGrid selectItemsAtIndexPaths:[NSSet setWithObject:indexPath]
                                scrollPosition:NSCollectionViewScrollPositionCenteredVertically];
            break;
        }
    }
}

- (void)showTypePickerView {
    _showingConfig = NO;

    // Animate transition
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.2;
        self.configContainer.animator.alphaValue = 0.0;
    } completionHandler:^{
        self.configContainer.hidden = YES;
        self.configContainer.alphaValue = 1.0;

        // Remove config view controller
        if (self.configViewController) {
            [self.configViewController.view removeFromSuperview];
            self.configViewController = nil;
        }
    }];

    _sheet.title = @"Create New Model";
    [self updateButtonStates];
}

- (void)showConfigurationView {
    if (_selectedTypeIndex < 0 || _selectedTypeIndex >= kModelTypeCount) return;

    const XLModelTypeDef *typeDef = &kModelTypes[_selectedTypeIndex];
    NSString *typeId = [NSString stringWithUTF8String:typeDef->typeId];

    // Create appropriate config view controller
    _configViewController = [self configViewControllerForType:typeId];
    _configViewController.modelName = [self generateUniqueModelName:typeId];

    // Add config view to container
    NSView *configView = _configViewController.view;
    configView.frame = _configContainer.bounds;
    configView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_configContainer addSubview:configView];

    _showingConfig = YES;
    _configContainer.hidden = NO;
    _configContainer.alphaValue = 0.0;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.2;
        self.configContainer.animator.alphaValue = 1.0;
    } completionHandler:nil];

    _sheet.title = [NSString stringWithFormat:@"Create %@ Model", [NSString stringWithUTF8String:typeDef->displayName]];
    [self updateButtonStates];
}

- (XLModelConfigViewController *)configViewControllerForType:(NSString *)typeId {
    if ([typeId isEqualToString:@"Single Line"]) {
        return [[XLSingleLineConfigViewController alloc] initWithModelType:typeId];
    } else if ([typeId isEqualToString:@"Matrix"]) {
        return [[XLMatrixConfigViewController alloc] initWithModelType:typeId];
    } else if ([typeId isEqualToString:@"Arches"]) {
        return [[XLArchConfigViewController alloc] initWithModelType:typeId];
    } else if ([typeId isEqualToString:@"Tree"]) {
        return [[XLTreeConfigViewController alloc] initWithModelType:typeId];
    } else if ([typeId isEqualToString:@"Star"]) {
        return [[XLStarConfigViewController alloc] initWithModelType:typeId];
    } else if ([typeId isEqualToString:@"Circle"]) {
        return [[XLCircleConfigViewController alloc] initWithModelType:typeId];
    } else if ([typeId isEqualToString:@"Cube"]) {
        return [[XLCubeConfigViewController alloc] initWithModelType:typeId];
    } else if ([typeId isEqualToString:@"Sphere"]) {
        return [[XLSphereConfigViewController alloc] initWithModelType:typeId];
    } else if ([typeId isEqualToString:@"Custom"]) {
        return [[XLCustomConfigViewController alloc] initWithModelType:typeId];
    } else {
        return [[XLGenericConfigViewController alloc] initWithModelType:typeId];
    }
}

- (NSString *)generateUniqueModelName:(NSString *)typeId {
    // Generate unique name like "Matrix-1", "Matrix-2", etc.
    NSArray<NSString *> *existingNames = [_engineBridge getModelNames];
    NSString *baseName = [typeId stringByReplacingOccurrencesOfString:@" " withString:@""];

    for (int i = 1; i <= 1000; i++) {
        NSString *candidateName = [NSString stringWithFormat:@"%@-%d", baseName, i];
        BOOL exists = NO;
        for (NSString *name in existingNames) {
            if ([name isEqualToString:candidateName]) {
                exists = YES;
                break;
            }
        }
        if (!exists) {
            return candidateName;
        }
    }

    return [NSString stringWithFormat:@"%@-New", baseName];
}

- (void)dismiss {
    if (_parentWindow && _sheet) {
        [_parentWindow endSheet:_sheet returnCode:NSModalResponseCancel];
    }
}

@end

#pragma mark - XLModelConfigViewController

@implementation XLModelConfigViewController

- (instancetype)initWithModelType:(NSString *)modelType {
    self = [super init];
    if (self) {
        _modelType = [modelType copy];
        _modelName = @"";
    }
    return self;
}

- (NSDictionary<NSString *, id> *)configurationProperties {
    return @{};
}

- (NSString *)validateConfiguration {
    if (_modelName.length == 0) {
        return @"Model name cannot be empty.";
    }
    return nil;
}

@end

#pragma mark - XLSingleLineConfigViewController

@interface XLSingleLineConfigViewController ()
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *nodesField;
@property (nonatomic, strong) NSPopUpButton *startSidePopup;
@property (nonatomic, strong) NSPopUpButton *colorOrderPopup;
@end

@implementation XLSingleLineConfigViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSheetWidth, kSheetHeight - 60)];

    NSGridView *grid = [self createFormGrid];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:grid];

    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:view.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:40],
        [grid.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-40],
    ]];

    self.view = view;
}

- (NSGridView *)createFormGrid {
    // Name field
    NSTextField *nameLabel = [NSTextField labelWithString:@"Model Name:"];
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nameField.placeholderString = @"Enter model name";
    _nameField.stringValue = self.modelName;

    // Nodes field
    NSTextField *nodesLabel = [NSTextField labelWithString:@"Number of Nodes:"];
    _nodesField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nodesField.placeholderString = @"100";
    _nodesField.stringValue = @"100";

    // Start side
    NSTextField *startSideLabel = [NSTextField labelWithString:@"Start Side:"];
    _startSidePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_startSidePopup addItemsWithTitles:@[@"Left", @"Right"]];

    // Color order
    NSTextField *colorOrderLabel = [NSTextField labelWithString:@"Color Order:"];
    _colorOrderPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_colorOrderPopup addItemsWithTitles:@[@"RGB", @"RBG", @"GRB", @"GBR", @"BRG", @"BGR", @"RGBW", @"WRGB"]];

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[nameLabel, _nameField],
        @[nodesLabel, _nodesField],
        @[startSideLabel, _startSidePopup],
        @[colorOrderLabel, _colorOrderPopup],
    ]];

    grid.rowSpacing = 12;
    grid.columnSpacing = 12;

    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].width = 200;

    return grid;
}

- (void)setModelName:(NSString *)modelName {
    [super setModelName:modelName];
    _nameField.stringValue = modelName ?: @"";
}

- (NSString *)modelName {
    return _nameField.stringValue;
}

- (NSDictionary<NSString *, id> *)configurationProperties {
    return @{
        @"parm1": @(1), // Number of strings
        @"parm2": @([_nodesField integerValue]), // Nodes per string
        @"StartSide": _startSidePopup.selectedItem.title ?: @"L",
        @"Dir": @"L",
        @"StringType": @"RGB Nodes",
        @"PixelSize": @(2),
        @"Transparency": @(0),
        @"Antialias": @(1),
    };
}

- (NSString *)validateConfiguration {
    NSString *baseError = [super validateConfiguration];
    if (baseError) return baseError;

    NSInteger nodes = [_nodesField integerValue];
    if (nodes < 1 || nodes > 10000) {
        return @"Number of nodes must be between 1 and 10,000.";
    }

    return nil;
}

@end

#pragma mark - XLMatrixConfigViewController

@interface XLMatrixConfigViewController ()
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *stringsField;
@property (nonatomic, strong) NSTextField *nodesPerStringField;
@property (nonatomic, strong) NSPopUpButton *startCornerPopup;
@property (nonatomic, strong) NSPopUpButton *directionPopup;
@end

@implementation XLMatrixConfigViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSheetWidth, kSheetHeight - 60)];

    NSGridView *grid = [self createFormGrid];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:grid];

    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:view.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:40],
        [grid.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-40],
    ]];

    self.view = view;
}

- (NSGridView *)createFormGrid {
    NSTextField *nameLabel = [NSTextField labelWithString:@"Model Name:"];
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nameField.placeholderString = @"Enter model name";
    _nameField.stringValue = self.modelName;

    NSTextField *stringsLabel = [NSTextField labelWithString:@"Number of Strings:"];
    _stringsField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _stringsField.stringValue = @"16";

    NSTextField *nodesLabel = [NSTextField labelWithString:@"Nodes per String:"];
    _nodesPerStringField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nodesPerStringField.stringValue = @"50";

    NSTextField *startCornerLabel = [NSTextField labelWithString:@"Start Corner:"];
    _startCornerPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_startCornerPopup addItemsWithTitles:@[@"Bottom Left", @"Bottom Right", @"Top Left", @"Top Right"]];

    NSTextField *directionLabel = [NSTextField labelWithString:@"Direction:"];
    _directionPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_directionPopup addItemsWithTitles:@[@"Horizontal", @"Vertical"]];

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[nameLabel, _nameField],
        @[stringsLabel, _stringsField],
        @[nodesLabel, _nodesPerStringField],
        @[startCornerLabel, _startCornerPopup],
        @[directionLabel, _directionPopup],
    ]];

    grid.rowSpacing = 12;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].width = 200;

    return grid;
}

- (void)setModelName:(NSString *)modelName {
    [super setModelName:modelName];
    _nameField.stringValue = modelName ?: @"";
}

- (NSString *)modelName {
    return _nameField.stringValue;
}

- (NSDictionary<NSString *, id> *)configurationProperties {
    BOOL isVertical = [_directionPopup.selectedItem.title isEqualToString:@"Vertical"];
    NSString *displayAs = isVertical ? @"Vert Matrix" : @"Horiz Matrix";

    return @{
        @"DisplayAs": displayAs,
        @"parm1": @([_stringsField integerValue]),
        @"parm2": @([_nodesPerStringField integerValue]),
        @"StartSide": [self startSide],
        @"Dir": [self direction],
        @"StringType": @"RGB Nodes",
    };
}

- (NSString *)startSide {
    NSString *corner = _startCornerPopup.selectedItem.title;
    if ([corner containsString:@"Bottom"]) return @"B";
    return @"T";
}

- (NSString *)direction {
    NSString *corner = _startCornerPopup.selectedItem.title;
    if ([corner containsString:@"Left"]) return @"L";
    return @"R";
}

- (NSString *)validateConfiguration {
    NSString *baseError = [super validateConfiguration];
    if (baseError) return baseError;

    NSInteger strings = [_stringsField integerValue];
    if (strings < 1 || strings > 1000) {
        return @"Number of strings must be between 1 and 1,000.";
    }

    NSInteger nodes = [_nodesPerStringField integerValue];
    if (nodes < 1 || nodes > 10000) {
        return @"Nodes per string must be between 1 and 10,000.";
    }

    return nil;
}

@end

#pragma mark - XLArchConfigViewController

@interface XLArchConfigViewController ()
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *archesField;
@property (nonatomic, strong) NSTextField *nodesPerArchField;
@property (nonatomic, strong) NSTextField *archGapField;
@end

@implementation XLArchConfigViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSheetWidth, kSheetHeight - 60)];

    NSGridView *grid = [self createFormGrid];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:grid];

    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:view.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:40],
        [grid.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-40],
    ]];

    self.view = view;
}

- (NSGridView *)createFormGrid {
    NSTextField *nameLabel = [NSTextField labelWithString:@"Model Name:"];
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nameField.stringValue = self.modelName;

    NSTextField *archesLabel = [NSTextField labelWithString:@"Number of Arches:"];
    _archesField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _archesField.stringValue = @"1";

    NSTextField *nodesLabel = [NSTextField labelWithString:@"Nodes per Arch:"];
    _nodesPerArchField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nodesPerArchField.stringValue = @"25";

    NSTextField *gapLabel = [NSTextField labelWithString:@"Arch Gap:"];
    _archGapField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _archGapField.stringValue = @"0";

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[nameLabel, _nameField],
        @[archesLabel, _archesField],
        @[nodesLabel, _nodesPerArchField],
        @[gapLabel, _archGapField],
    ]];

    grid.rowSpacing = 12;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].width = 200;

    return grid;
}

- (void)setModelName:(NSString *)modelName {
    [super setModelName:modelName];
    _nameField.stringValue = modelName ?: @"";
}

- (NSString *)modelName {
    return _nameField.stringValue;
}

- (NSDictionary<NSString *, id> *)configurationProperties {
    return @{
        @"parm1": @([_archesField integerValue]),
        @"parm2": @([_nodesPerArchField integerValue]),
        @"parm3": @(1), // Lights per node
        @"Arc": @(180),
        @"StringType": @"RGB Nodes",
    };
}

@end

#pragma mark - XLTreeConfigViewController

@interface XLTreeConfigViewController ()
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *stringsField;
@property (nonatomic, strong) NSTextField *nodesPerStringField;
@property (nonatomic, strong) NSPopUpButton *treeTypePopup;
@end

@implementation XLTreeConfigViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSheetWidth, kSheetHeight - 60)];

    NSGridView *grid = [self createFormGrid];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:grid];

    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:view.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:40],
        [grid.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-40],
    ]];

    self.view = view;
}

- (NSGridView *)createFormGrid {
    NSTextField *nameLabel = [NSTextField labelWithString:@"Model Name:"];
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nameField.stringValue = self.modelName;

    NSTextField *typeLabel = [NSTextField labelWithString:@"Tree Type:"];
    _treeTypePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_treeTypePopup addItemsWithTitles:@[@"Tree Flat", @"Tree 360", @"Tree Ribbon"]];

    NSTextField *stringsLabel = [NSTextField labelWithString:@"Number of Strings:"];
    _stringsField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _stringsField.stringValue = @"16";

    NSTextField *nodesLabel = [NSTextField labelWithString:@"Nodes per String:"];
    _nodesPerStringField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nodesPerStringField.stringValue = @"50";

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[nameLabel, _nameField],
        @[typeLabel, _treeTypePopup],
        @[stringsLabel, _stringsField],
        @[nodesLabel, _nodesPerStringField],
    ]];

    grid.rowSpacing = 12;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].width = 200;

    return grid;
}

- (void)setModelName:(NSString *)modelName {
    [super setModelName:modelName];
    _nameField.stringValue = modelName ?: @"";
}

- (NSString *)modelName {
    return _nameField.stringValue;
}

- (NSDictionary<NSString *, id> *)configurationProperties {
    return @{
        @"DisplayAs": _treeTypePopup.selectedItem.title ?: @"Tree Flat",
        @"parm1": @([_stringsField integerValue]),
        @"parm2": @([_nodesPerStringField integerValue]),
        @"parm3": @(1),
        @"StringType": @"RGB Nodes",
    };
}

@end

#pragma mark - XLStarConfigViewController

@interface XLStarConfigViewController ()
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *pointsField;
@property (nonatomic, strong) NSTextField *nodesPerLayerField;
@property (nonatomic, strong) NSTextField *layersField;
@end

@implementation XLStarConfigViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSheetWidth, kSheetHeight - 60)];

    NSGridView *grid = [self createFormGrid];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:grid];

    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:view.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:40],
        [grid.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-40],
    ]];

    self.view = view;
}

- (NSGridView *)createFormGrid {
    NSTextField *nameLabel = [NSTextField labelWithString:@"Model Name:"];
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nameField.stringValue = self.modelName;

    NSTextField *pointsLabel = [NSTextField labelWithString:@"Number of Points:"];
    _pointsField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _pointsField.stringValue = @"5";

    NSTextField *nodesLabel = [NSTextField labelWithString:@"Nodes per Layer:"];
    _nodesPerLayerField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nodesPerLayerField.stringValue = @"50";

    NSTextField *layersLabel = [NSTextField labelWithString:@"Number of Layers:"];
    _layersField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _layersField.stringValue = @"1";

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[nameLabel, _nameField],
        @[pointsLabel, _pointsField],
        @[nodesLabel, _nodesPerLayerField],
        @[layersLabel, _layersField],
    ]];

    grid.rowSpacing = 12;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].width = 200;

    return grid;
}

- (void)setModelName:(NSString *)modelName {
    [super setModelName:modelName];
    _nameField.stringValue = modelName ?: @"";
}

- (NSString *)modelName {
    return _nameField.stringValue;
}

- (NSDictionary<NSString *, id> *)configurationProperties {
    return @{
        @"parm1": @([_layersField integerValue]),
        @"parm2": @([_nodesPerLayerField integerValue]),
        @"parm3": @([_pointsField integerValue]),
        @"StarStartLocation": @"Bottom Ctr",
        @"StringType": @"RGB Nodes",
    };
}

@end

#pragma mark - XLCircleConfigViewController

@interface XLCircleConfigViewController ()
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *nodesField;
@property (nonatomic, strong) NSTextField *layersField;
@end

@implementation XLCircleConfigViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSheetWidth, kSheetHeight - 60)];

    NSGridView *grid = [self createFormGrid];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:grid];

    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:view.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:40],
        [grid.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-40],
    ]];

    self.view = view;
}

- (NSGridView *)createFormGrid {
    NSTextField *nameLabel = [NSTextField labelWithString:@"Model Name:"];
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nameField.stringValue = self.modelName;

    NSTextField *layersLabel = [NSTextField labelWithString:@"Number of Layers:"];
    _layersField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _layersField.stringValue = @"1";

    NSTextField *nodesLabel = [NSTextField labelWithString:@"Nodes per Layer:"];
    _nodesField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nodesField.stringValue = @"50";

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[nameLabel, _nameField],
        @[layersLabel, _layersField],
        @[nodesLabel, _nodesField],
    ]];

    grid.rowSpacing = 12;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].width = 200;

    return grid;
}

- (void)setModelName:(NSString *)modelName {
    [super setModelName:modelName];
    _nameField.stringValue = modelName ?: @"";
}

- (NSString *)modelName {
    return _nameField.stringValue;
}

- (NSDictionary<NSString *, id> *)configurationProperties {
    return @{
        @"parm1": @([_layersField integerValue]),
        @"parm2": @([_nodesField integerValue]),
        @"parm3": @(1),
        @"StringType": @"RGB Nodes",
    };
}

@end

#pragma mark - XLCubeConfigViewController

@interface XLCubeConfigViewController ()
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *widthField;
@property (nonatomic, strong) NSTextField *heightField;
@property (nonatomic, strong) NSTextField *depthField;
@end

@implementation XLCubeConfigViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSheetWidth, kSheetHeight - 60)];

    NSGridView *grid = [self createFormGrid];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:grid];

    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:view.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:40],
        [grid.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-40],
    ]];

    self.view = view;
}

- (NSGridView *)createFormGrid {
    NSTextField *nameLabel = [NSTextField labelWithString:@"Model Name:"];
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nameField.stringValue = self.modelName;

    NSTextField *widthLabel = [NSTextField labelWithString:@"Width (nodes):"];
    _widthField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _widthField.stringValue = @"10";

    NSTextField *heightLabel = [NSTextField labelWithString:@"Height (nodes):"];
    _heightField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _heightField.stringValue = @"10";

    NSTextField *depthLabel = [NSTextField labelWithString:@"Depth (nodes):"];
    _depthField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _depthField.stringValue = @"10";

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[nameLabel, _nameField],
        @[widthLabel, _widthField],
        @[heightLabel, _heightField],
        @[depthLabel, _depthField],
    ]];

    grid.rowSpacing = 12;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].width = 200;

    return grid;
}

- (void)setModelName:(NSString *)modelName {
    [super setModelName:modelName];
    _nameField.stringValue = modelName ?: @"";
}

- (NSString *)modelName {
    return _nameField.stringValue;
}

- (NSDictionary<NSString *, id> *)configurationProperties {
    return @{
        @"parm1": @([_widthField integerValue]),
        @"parm2": @([_heightField integerValue]),
        @"parm3": @([_depthField integerValue]),
        @"StringType": @"RGB Nodes",
    };
}

@end

#pragma mark - XLSphereConfigViewController

@interface XLSphereConfigViewController ()
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *stringsField;
@property (nonatomic, strong) NSTextField *nodesPerStringField;
@end

@implementation XLSphereConfigViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSheetWidth, kSheetHeight - 60)];

    NSGridView *grid = [self createFormGrid];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:grid];

    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:view.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:40],
        [grid.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-40],
    ]];

    self.view = view;
}

- (NSGridView *)createFormGrid {
    NSTextField *nameLabel = [NSTextField labelWithString:@"Model Name:"];
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nameField.stringValue = self.modelName;

    NSTextField *stringsLabel = [NSTextField labelWithString:@"Number of Strings:"];
    _stringsField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _stringsField.stringValue = @"16";

    NSTextField *nodesLabel = [NSTextField labelWithString:@"Nodes per String:"];
    _nodesPerStringField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nodesPerStringField.stringValue = @"50";

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[nameLabel, _nameField],
        @[stringsLabel, _stringsField],
        @[nodesLabel, _nodesPerStringField],
    ]];

    grid.rowSpacing = 12;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].width = 200;

    return grid;
}

- (void)setModelName:(NSString *)modelName {
    [super setModelName:modelName];
    _nameField.stringValue = modelName ?: @"";
}

- (NSString *)modelName {
    return _nameField.stringValue;
}

- (NSDictionary<NSString *, id> *)configurationProperties {
    return @{
        @"DisplayAs": @"Sphere 360",
        @"parm1": @([_stringsField integerValue]),
        @"parm2": @([_nodesPerStringField integerValue]),
        @"parm3": @(1),
        @"StringType": @"RGB Nodes",
    };
}

@end

#pragma mark - XLCustomConfigViewController

@interface XLCustomConfigViewController ()
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *widthField;
@property (nonatomic, strong) NSTextField *heightField;
@property (nonatomic, strong) NSTextField *infoLabel;
@end

@implementation XLCustomConfigViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSheetWidth, kSheetHeight - 60)];

    NSGridView *grid = [self createFormGrid];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:grid];

    _infoLabel = [NSTextField wrappingLabelWithString:@"This creates a basic custom model. After creation, select the model and click 'Edit Custom Model...' in the properties panel to define the pixel layout."];
    _infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _infoLabel.textColor = [NSColor secondaryLabelColor];
    _infoLabel.font = [NSFont systemFontOfSize:11];
    [view addSubview:_infoLabel];

    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:view.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:40],
        [grid.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-40],

        [_infoLabel.topAnchor constraintEqualToAnchor:grid.bottomAnchor constant:20],
        [_infoLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:40],
        [_infoLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-40],
    ]];

    self.view = view;
}

- (NSGridView *)createFormGrid {
    NSTextField *nameLabel = [NSTextField labelWithString:@"Model Name:"];
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nameField.stringValue = self.modelName;

    NSTextField *widthLabel = [NSTextField labelWithString:@"Grid Width:"];
    _widthField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _widthField.stringValue = @"10";

    NSTextField *heightLabel = [NSTextField labelWithString:@"Grid Height:"];
    _heightField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _heightField.stringValue = @"10";

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[nameLabel, _nameField],
        @[widthLabel, _widthField],
        @[heightLabel, _heightField],
    ]];

    grid.rowSpacing = 12;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].width = 200;

    return grid;
}

- (void)setModelName:(NSString *)modelName {
    [super setModelName:modelName];
    _nameField.stringValue = modelName ?: @"";
}

- (NSString *)modelName {
    return _nameField.stringValue;
}

- (NSDictionary<NSString *, id> *)configurationProperties {
    return @{
        @"parm1": @([_widthField integerValue]),
        @"parm2": @([_heightField integerValue]),
        @"CustomModel": @"",
        @"StringType": @"RGB Nodes",
    };
}

@end

#pragma mark - XLGenericConfigViewController

@interface XLGenericConfigViewController ()
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *nodesField;
@end

@implementation XLGenericConfigViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSheetWidth, kSheetHeight - 60)];

    NSGridView *grid = [self createFormGrid];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:grid];

    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:view.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:40],
        [grid.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-40],
    ]];

    self.view = view;
}

- (NSGridView *)createFormGrid {
    NSTextField *nameLabel = [NSTextField labelWithString:@"Model Name:"];
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nameField.stringValue = self.modelName;

    NSTextField *nodesLabel = [NSTextField labelWithString:@"Number of Nodes:"];
    _nodesField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nodesField.stringValue = @"100";

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[nameLabel, _nameField],
        @[nodesLabel, _nodesField],
    ]];

    grid.rowSpacing = 12;
    grid.columnSpacing = 12;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].width = 200;

    return grid;
}

- (void)setModelName:(NSString *)modelName {
    [super setModelName:modelName];
    _nameField.stringValue = modelName ?: @"";
}

- (NSString *)modelName {
    return _nameField.stringValue;
}

- (NSDictionary<NSString *, id> *)configurationProperties {
    return @{
        @"parm1": @(1),
        @"parm2": @([_nodesField integerValue]),
        @"StringType": @"RGB Nodes",
    };
}

@end
