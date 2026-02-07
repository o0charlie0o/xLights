/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLLayoutViewController.h"
#import "XLEngineBridge.h"
#import "layout/XLCameraController.h"
#import "layout/XLModelTreeNode.h"
#import "layout/XLModelCreationSheet.h"
#import "layout/XLModelImportSheet.h"
#import "layout/XLVendorModelWindowController.h"
#import "layout/XLManipulationHandlesRenderer.h"
#import "layout/XLModelPropertiesView.h"
#import "layout/XLLayoutUndoController.h"
#import "dialogs/XLCustomModelWindow.h"
#import "dialogs/XLModelGroupWindow.h"
#import "input/XLKeyboardHandler.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const CGFloat kModelTreeMinWidth = 200.0;
static const CGFloat kModelTreeDefaultWidth = 280.0;
static const CGFloat kPropertiesMinWidth = 200.0;
static const CGFloat kPropertiesDefaultWidth = 260.0;

/// Custom pasteboard type for model clipboard data
static NSPasteboardType const XLModelPasteboardType = @"com.xlights.model";

/// Position offset (in world units) applied to each pasted model to avoid stacking
static const float kPastePositionOffset = 40.0f;

/// Time window (seconds) for coalescing rapid nudge operations into one undo group
static const NSTimeInterval kNudgeCoalesceInterval = 0.5;

/// NSUserDefaults keys for layout view state
static NSString * const kLayoutShow3DKey = @"XLLayoutShow3D";
static NSString * const kLayoutOverlapChecksKey = @"XLLayoutOverlapChecksEnabled";

@interface XLLayoutViewController ()

@property (nonatomic, strong) NSSplitViewController *splitController;
@property (nonatomic, strong) XLModelCreationSheet *modelCreationSheet;
@property (nonatomic, strong) XLModelImportSheet *modelImportSheet;
@property (nonatomic, strong) XLVendorModelWindowController *vendorModelWindowController;
@property (nonatomic, strong) NSScrollView *propertiesScrollView;
@property (nonatomic, strong, readwrite) XLLayoutUndoController *undoController;
@property (nonatomic, assign) XLToolMode manipulationToolMode;
@property (nonatomic, assign) BOOL initialDividersSet;

/// Nudge undo coalescing: accumulate rapid nudges into a single undo operation
@property (nonatomic, assign) BOOL nudgeUndoGroupOpen;
@property (nonatomic, strong) NSTimer *nudgeCoalesceTimer;
@property (nonatomic, copy) NSString *nudgeModelName;
@property (nonatomic, assign) float nudgeStartX;
@property (nonatomic, assign) float nudgeStartY;

/// Layout group selector and toolbar
@property (nonatomic, strong, readwrite) NSPopUpButton *layoutGroupSelector;
@property (nonatomic, copy, readwrite) NSString *currentLayoutGroup;

/// Model type creation toolbar
@property (nonatomic, strong, readwrite) NSScrollView *modelTypeToolbar;

/// 2D/3D mode and overlap controls
@property (nonatomic, strong, readwrite) NSSegmentedControl *viewModeControl;
@property (nonatomic, strong, readwrite) NSButton *overlapCheckToggle;

/// Model group management window
@property (nonatomic, strong) XLModelGroupWindow *modelGroupWindow;

@end

@implementation XLLayoutViewController

- (void)loadView {
    _currentLayoutGroup = @"Default";

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 600)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor colorWithWhite:0.16 alpha:1.0] CGColor];

    // Layout group toolbar
    NSView *toolbarView = [[NSView alloc] initWithFrame:NSZeroRect];
    toolbarView.translatesAutoresizingMaskIntoConstraints = NO;
    toolbarView.wantsLayer = YES;
    toolbarView.layer.backgroundColor = [[NSColor colorWithWhite:0.14 alpha:1.0] CGColor];
    [view addSubview:toolbarView];

    NSTextField *previewLabel = [NSTextField labelWithString:@"Preview:"];
    previewLabel.translatesAutoresizingMaskIntoConstraints = NO;
    previewLabel.textColor = [NSColor secondaryLabelColor];
    previewLabel.font = [NSFont systemFontOfSize:11];
    [toolbarView addSubview:previewLabel];

    _layoutGroupSelector = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _layoutGroupSelector.translatesAutoresizingMaskIntoConstraints = NO;
    _layoutGroupSelector.controlSize = NSControlSizeSmall;
    _layoutGroupSelector.font = [NSFont systemFontOfSize:11];
    _layoutGroupSelector.target = self;
    _layoutGroupSelector.action = @selector(layoutGroupSelectorChanged:);
    [toolbarView addSubview:_layoutGroupSelector];

    // 2D/3D mode segmented control (right side of toolbar)
    _viewModeControl = [NSSegmentedControl segmentedControlWithLabels:@[@"2D", @"3D"]
                                                         trackingMode:NSSegmentSwitchTrackingSelectOne
                                                               target:self
                                                               action:@selector(viewModeChanged:)];
    _viewModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    _viewModeControl.controlSize = NSControlSizeSmall;
    _viewModeControl.font = [NSFont systemFontOfSize:11];
    [_viewModeControl setWidth:32 forSegment:0];
    [_viewModeControl setWidth:32 forSegment:1];

    // Restore saved state (default to 3D)
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL show3D = YES;
    if ([defaults objectForKey:kLayoutShow3DKey] != nil) {
        show3D = [defaults boolForKey:kLayoutShow3DKey];
    }
    _viewModeControl.selectedSegment = show3D ? 1 : 0;
    [toolbarView addSubview:_viewModeControl];

    // Overlap checks toggle (right side of toolbar, after 2D/3D control)
    _overlapCheckToggle = [NSButton checkboxWithTitle:@"Overlap checks"
                                               target:self
                                               action:@selector(overlapCheckToggled:)];
    _overlapCheckToggle.translatesAutoresizingMaskIntoConstraints = NO;
    _overlapCheckToggle.controlSize = NSControlSizeSmall;
    _overlapCheckToggle.font = [NSFont systemFontOfSize:11];
    _overlapCheckToggle.contentTintColor = [NSColor secondaryLabelColor];

    BOOL overlapChecks = [defaults boolForKey:kLayoutOverlapChecksKey];
    _overlapCheckToggle.state = overlapChecks ? NSControlStateValueOn : NSControlStateValueOff;
    [toolbarView addSubview:_overlapCheckToggle];

    [NSLayoutConstraint activateConstraints:@[
        [toolbarView.topAnchor constraintEqualToAnchor:view.topAnchor],
        [toolbarView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [toolbarView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [toolbarView.heightAnchor constraintEqualToConstant:28],

        [previewLabel.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [previewLabel.leadingAnchor constraintEqualToAnchor:toolbarView.leadingAnchor constant:8],

        [_layoutGroupSelector.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [_layoutGroupSelector.leadingAnchor constraintEqualToAnchor:previewLabel.trailingAnchor constant:4],
        [_layoutGroupSelector.widthAnchor constraintGreaterThanOrEqualToConstant:140],

        [_overlapCheckToggle.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [_overlapCheckToggle.trailingAnchor constraintEqualToAnchor:toolbarView.trailingAnchor constant:-8],

        [_viewModeControl.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [_viewModeControl.trailingAnchor constraintEqualToAnchor:_overlapCheckToggle.leadingAnchor constant:-12],
    ]];

    // Model type creation toolbar (scrollable horizontal button bar)
    _modelTypeToolbar = [self buildModelTypeToolbar];
    _modelTypeToolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:_modelTypeToolbar];

    [NSLayoutConstraint activateConstraints:@[
        [_modelTypeToolbar.topAnchor constraintEqualToAnchor:toolbarView.bottomAnchor],
        [_modelTypeToolbar.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_modelTypeToolbar.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_modelTypeToolbar.heightAnchor constraintEqualToConstant:34],
    ]];

    // Build split view using NSSplitViewController + NSSplitViewItem pattern
    // (matches XLMainWindowController's setupSplitView approach)
    _splitController = [[NSSplitViewController alloc] init];
    _splitController.splitView.vertical = YES;
    _splitController.splitView.dividerStyle = NSSplitViewDividerStyleThin;

    // Model tree (left sidebar)
    _modelTreeController = [[XLModelTreeViewController alloc] init];
    _modelTreeController.delegate = self;
    _modelTreeController.engineBridge = self.engineBridge;
    _modelTreeController.show3D = show3D;

    NSSplitViewItem *treeItem = [NSSplitViewItem splitViewItemWithViewController:_modelTreeController];
    treeItem.canCollapse = NO;
    treeItem.minimumThickness = kModelTreeMinWidth;
    treeItem.holdingPriority = NSLayoutPriorityDefaultLow + 10;
    [_splitController addSplitViewItem:treeItem];

    // Preview (center)
    _previewView = [[XLMetalPreviewView alloc] initWithFrame:NSZeroRect];
    _previewView.delegate = self;
    _previewView.show3D = show3D;
    _previewView.showGrid = YES;

    NSViewController *previewVC = [[NSViewController alloc] init];
    previewVC.view = _previewView;
    NSSplitViewItem *previewItem = [NSSplitViewItem splitViewItemWithViewController:previewVC];
    previewItem.canCollapse = NO;
    previewItem.minimumThickness = 300.0;
    previewItem.holdingPriority = NSLayoutPriorityDefaultHigh;
    [_splitController addSplitViewItem:previewItem];

    // Properties (right sidebar) - in a scroll view
    _propertiesView = [[XLModelPropertiesView alloc] initWithFrame:NSZeroRect];
    _propertiesView.translatesAutoresizingMaskIntoConstraints = NO;
    _propertiesView.delegate = self;
    _propertiesView.engineBridge = self.engineBridge;

    _propertiesScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _propertiesScrollView.hasVerticalScroller = YES;
    _propertiesScrollView.hasHorizontalScroller = NO;
    _propertiesScrollView.autohidesScrollers = YES;
    _propertiesScrollView.borderType = NSNoBorder;
    _propertiesScrollView.drawsBackground = YES;
    _propertiesScrollView.backgroundColor = [NSColor colorWithWhite:0.18 alpha:1.0];
    _propertiesScrollView.documentView = _propertiesView;

    // Set up document view constraints within scroll view
    [NSLayoutConstraint activateConstraints:@[
        [_propertiesView.topAnchor constraintEqualToAnchor:_propertiesScrollView.contentView.topAnchor],
        [_propertiesView.leadingAnchor constraintEqualToAnchor:_propertiesScrollView.contentView.leadingAnchor],
        [_propertiesView.trailingAnchor constraintEqualToAnchor:_propertiesScrollView.contentView.trailingAnchor],
    ]];

    NSViewController *propertiesVC = [[NSViewController alloc] init];
    propertiesVC.view = _propertiesScrollView;
    NSSplitViewItem *propertiesItem = [NSSplitViewItem splitViewItemWithViewController:propertiesVC];
    propertiesItem.canCollapse = NO;
    propertiesItem.minimumThickness = kPropertiesMinWidth;
    propertiesItem.holdingPriority = NSLayoutPriorityDefaultLow + 10;
    [_splitController addSplitViewItem:propertiesItem];

    // Embed the split view controller as a child for proper containment
    NSView *splitView = _splitController.view;
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:splitView];

    [NSLayoutConstraint activateConstraints:@[
        [splitView.topAnchor constraintEqualToAnchor:_modelTypeToolbar.bottomAnchor],
        [splitView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [splitView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [splitView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
    ]];

    self.view = view;

    // Add as child VC after self.view is set (addChildViewController requires valid view)
    [self addChildViewController:_splitController];
}

#pragma mark - Model Type Toolbar

- (NSButton *)modelTypeButtonWithSymbol:(NSString *)symbolName
                                tooltip:(NSString *)tooltip
                                    tag:(NSInteger)tag {
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName
                                      accessibilityDescription:tooltip];
    NSButton *button = [NSButton buttonWithImage:image target:self action:@selector(modelTypeButtonClicked:)];
    button.bezelStyle = NSBezelStyleAccessoryBarAction;
    button.bordered = YES;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = tooltip;
    button.tag = tag;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:30],
        [button.heightAnchor constraintEqualToConstant:24],
    ]];
    return button;
}

- (NSScrollView *)buildModelTypeToolbar {
    // Model types with SF Symbol names and display names (used as type key for creation sheet)
    NSArray<NSArray<NSString *> *> *modelTypes = @[
        @[@"archway",                        @"Arches"],
        @[@"arrow.up.and.down.and.sparkles", @"Candy Canes"],
        @[@"rectangle.split.3x1",            @"Channel Block"],
        @[@"circle",                         @"Circle"],
        @[@"cube",                           @"Cube"],
        @[@"square.dashed",                  @"Custom"],
        @[@"light.recessed",                 @"DMX"],
        @[@"chevron.down",                   @"Icicles"],
        @[@"photo",                          @"Image"],
        @[@"square.grid.3x3",               @"Matrix"],
        @[@"point.topleft.down.to.point.bottomright.curvepath", @"Poly Line"],
        @[@"line.diagonal",                  @"Single Line"],
        @[@"globe",                          @"Sphere"],
        @[@"arrow.trianglehead.2.clockwise.rotate.90", @"Spinner"],
        @[@"star",                           @"Star"],
        @[@"tree",                           @"Tree"],
        @[@"window.ceiling",                 @"Window Frame"],
    ];

    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.spacing = 2;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.edgeInsets = NSEdgeInsetsMake(0, 6, 0, 6);
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    for (NSUInteger i = 0; i < modelTypes.count; i++) {
        NSString *symbol = modelTypes[i][0];
        NSString *typeName = modelTypes[i][1];
        NSButton *btn = [self modelTypeButtonWithSymbol:symbol tooltip:typeName tag:(NSInteger)i];
        [stack addArrangedSubview:btn];
    }

    // Separator between model types and utility buttons
    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [separator.widthAnchor constraintEqualToConstant:1],
        [separator.heightAnchor constraintEqualToConstant:18],
    ]];
    [stack addArrangedSubview:separator];

    // Download vendor models button
    NSButton *downloadBtn = [self modelTypeButtonWithSymbol:@"arrow.down.circle"
                                                   tooltip:@"Download Vendor Models"
                                                       tag:100];
    [stack addArrangedSubview:downloadBtn];

    // Import custom model button
    NSButton *importBtn = [self modelTypeButtonWithSymbol:@"square.and.arrow.down"
                                                 tooltip:@"Import Model"
                                                     tag:101];
    [stack addArrangedSubview:importBtn];

    // Wrap in scroll view for horizontal scrolling when window is narrow
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasHorizontalScroller = YES;
    scrollView.hasVerticalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSNoBorder;
    scrollView.drawsBackground = YES;
    scrollView.backgroundColor = [NSColor colorWithWhite:0.15 alpha:1.0];
    scrollView.documentView = stack;

    NSClipView *clipView = scrollView.contentView;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:clipView.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:clipView.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:clipView.leadingAnchor],
        [stack.heightAnchor constraintEqualToAnchor:clipView.heightAnchor],
    ]];

    return scrollView;
}

- (void)modelTypeButtonClicked:(NSButton *)sender {
    NSInteger tag = sender.tag;

    if (tag == 100) {
        [self showVendorModelDownload];
        return;
    }
    if (tag == 101) {
        [self showModelImportSheet];
        return;
    }

    NSArray<NSString *> *modelTypes = @[
        @"Arches", @"Candy Canes", @"Channel Block", @"Circle",
        @"Cube", @"Custom", @"DMX", @"Icicles",
        @"Image", @"Matrix", @"Poly Line", @"Single Line",
        @"Sphere", @"Spinner", @"Star", @"Tree", @"Window Frame",
    ];

    if (tag >= 0 && tag < (NSInteger)modelTypes.count) {
        [self showModelCreationSheetForType:modelTypes[tag]];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Initialize undo controller
    _undoController = [[XLLayoutUndoController alloc] initWithEngineBridge:_engineBridge];
    _undoController.delegate = self;

    // Initialize keyboard handler for processing key bindings in layout scope
    NSString *showFolder = [self.engineBridge getShowFolderPath];
    NSLog(@"XLLayoutViewController viewDidLoad: showFolder from engineBridge = '%@'", showFolder);
    if (!showFolder || showFolder.length == 0) {
        showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
        NSLog(@"XLLayoutViewController: Fallback to UserDefaults showFolder = '%@'", showFolder);
    }
    self.keyboardHandler = [[XLKeyboardHandler alloc] initWithShowFolderPath:showFolder];
    self.keyboardHandler.delegate = self;
    NSLog(@"XLLayoutViewController: keyboardHandler initialized = %@, bindingCount = %lu",
          self.keyboardHandler, (unsigned long)[self.keyboardHandler bindingCount]);

    // Listen for show folder changes to reload key bindings
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showFolderDidChange:)
                                                 name:@"XLShowFolderDidChangeNotification"
                                               object:nil];

    // Listen for layout group list changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(layoutGroupListDidChange:)
                                                 name:@"XLLayoutGroupListDidChangeNotification"
                                               object:nil];

    // Listen for layout group selection changes from bridge
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(layoutGroupDidChange:)
                                                 name:@"XLLayoutGroupDidChangeNotification"
                                               object:nil];

    [self reloadLayoutGroupSelector];
    [_modelTreeController reloadData];
}

- (void)viewDidAppear {
    [super viewDidAppear];

    // Set initial divider positions after Auto Layout has stabilized.
    // Must be deferred because NSSplitViewController needs a layout pass first.
    if (!_initialDividersSet) {
        _initialDividersSet = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSSplitView *sv = self->_splitController.splitView;
            CGFloat totalWidth = sv.bounds.size.width;
            if (totalWidth > 0) {
                CGFloat previewWidth = totalWidth - kModelTreeDefaultWidth - kPropertiesDefaultWidth;
                if (previewWidth < 300) previewWidth = 300;
                [sv setPosition:kModelTreeDefaultWidth ofDividerAtIndex:0];
                [sv setPosition:kModelTreeDefaultWidth + previewWidth ofDividerAtIndex:1];
            }
        });
    }

    [_previewView startRenderLoop];
}

- (void)viewDidDisappear {
    [super viewDidDisappear];
    [self finalizeNudgeUndoGroup];
    [_previewView stopRenderLoop];
}

- (void)setEngineBridge:(XLEngineBridge *)engineBridge {
    _engineBridge = engineBridge;
    _modelTreeController.engineBridge = engineBridge;
    _propertiesView.engineBridge = engineBridge;
    _undoController.engineBridge = engineBridge;
}

#pragma mark - Layout Group Selector

- (void)reloadLayoutGroupSelector {
    [_layoutGroupSelector removeAllItems];
    NSArray<NSString *> *groups = [_engineBridge getLayoutGroupNames];
    if (groups.count == 0) {
        [_layoutGroupSelector addItemWithTitle:@"Default"];
    } else {
        for (NSString *group in groups) {
            [_layoutGroupSelector addItemWithTitle:group];
        }
    }
    // Select current group
    NSString *current = [_engineBridge getCurrentLayoutGroup];
    if (current) {
        [_layoutGroupSelector selectItemWithTitle:current];
        _currentLayoutGroup = current;
    }
}

- (void)layoutGroupSelectorChanged:(id)sender {
    NSString *selected = _layoutGroupSelector.titleOfSelectedItem;
    if (selected && ![selected isEqualToString:_currentLayoutGroup]) {
        _currentLayoutGroup = selected;
        [_engineBridge setCurrentLayoutGroup:selected];
        [_modelTreeController reloadData];
        [_previewView setNeedsDisplay:YES];
    }
}

- (void)layoutGroupListDidChange:(NSNotification *)notification {
    [self reloadLayoutGroupSelector];
}

- (void)layoutGroupDidChange:(NSNotification *)notification {
    NSString *groupName = notification.userInfo[@"groupName"];
    if (groupName) {
        _currentLayoutGroup = groupName;
        [_layoutGroupSelector selectItemWithTitle:groupName];
    }
    [_modelTreeController reloadData];
    [_previewView setNeedsDisplay:YES];
}

#pragma mark - XLMetalPreviewDelegate

- (void)previewView:(XLMetalPreviewView *)view didSelectModel:(NSString *)modelName {
    if (modelName) {
        [_modelTreeController selectModelWithName:modelName];
    } else {
        // Deselect all in tree
        [_modelTreeController.outlineView deselectAll:nil];
    }
}

- (void)previewView:(XLMetalPreviewView *)view didSelectModels:(NSArray<NSString *> *)modelNames {
    if (modelNames.count > 0) {
        [_modelTreeController selectModelsWithNames:modelNames];
        // Show properties for the primary (last) model
        NSString *primaryModel = modelNames.lastObject;
        NSDictionary *modelInfo = [_engineBridge getModelInfo:primaryModel];
        if (modelInfo) {
            [_propertiesView showPropertiesForModel:primaryModel info:modelInfo];
        }
    } else {
        [_modelTreeController.outlineView deselectAll:nil];
        [_propertiesView clearProperties];
    }
}

- (void)previewView:(XLMetalPreviewView *)view didChangeCamera:(XLCameraController *)camera {
}

#pragma mark - XLModelTreeDelegate

- (void)modelTree:(XLModelTreeViewController *)controller didSelectModel:(NSString *)modelName {
    NSLog(@"XLLayoutViewController: Model selected from tree: %@", modelName);
    // Check if the tree has multi-selection active
    NSArray<NSString *> *treeSelection = [controller selectedModelNames];
    if (treeSelection.count > 1) {
        [_previewView selectModels:treeSelection];
    } else {
        [self selectModel:modelName];
    }
}

- (void)modelTree:(XLModelTreeViewController *)controller didMoveModel:(NSString *)modelName toGroup:(NSString *)groupName atIndex:(NSInteger)index {
    NSLog(@"XLLayoutViewController: Model '%@' moved to group '%@' at index %ld", modelName, groupName, (long)index);

    if (!_engineBridge) return;

    // Find which groups currently contain this model so we can remove from old groups
    NSArray<NSString *> *currentGroups = [_engineBridge getGroupsContainingModel:modelName];

    if (groupName) {
        // Moving into a group: remove from any current groups first (except target)
        for (NSString *oldGroup in currentGroups) {
            if (![oldGroup isEqualToString:groupName]) {
                [_engineBridge removeModel:modelName fromGroup:oldGroup];
            }
        }

        // Add to target group if not already a member
        if (![currentGroups containsObject:groupName]) {
            [_engineBridge addModel:modelName toGroup:groupName];
        }
    } else {
        // Moving to root level: remove from all groups
        for (NSString *oldGroup in currentGroups) {
            [_engineBridge removeModel:modelName fromGroup:oldGroup];
        }
    }

    // Notify the rest of the app that model list changed
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"XLModelListDidChangeNotification"
                      object:self];
}

- (void)modelTree:(XLModelTreeViewController *)controller didRequestAddModelOfType:(NSString *)modelType {
    NSLog(@"XLLayoutViewController: Add model of type '%@' requested", modelType);
    [self showModelCreationSheetForType:modelType];
}

- (void)modelTree:(XLModelTreeViewController *)controller didRequestDeleteModel:(NSString *)modelName {
    NSLog(@"XLLayoutViewController: Delete model '%@' requested", modelName);

    // Capture model data for undo before deletion
    NSDictionary *modelData = [_engineBridge getModelData:modelName];

    // Delete via engine bridge
    BOOL success = [_engineBridge deleteModel:modelName];
    if (success) {
        // Register undo action
        [_undoController registerModelDeleted:modelName modelData:modelData];
        [_modelTreeController reloadData];
    }
}

- (void)modelTree:(XLModelTreeViewController *)controller didRequestDuplicateModel:(NSString *)modelName {
    NSLog(@"XLLayoutViewController: Duplicate model '%@' requested", modelName);

    // Duplicate via engine bridge - returns the new model name
    NSString *duplicateName = [_engineBridge duplicateModelReturningName:modelName];
    if (duplicateName) {
        // Get the duplicate's data for undo
        NSDictionary *duplicateData = [_engineBridge getModelData:duplicateName];

        // Register undo action
        [_undoController registerModelDuplicated:modelName
                                   duplicateName:duplicateName
                                   duplicateData:duplicateData];
        [_modelTreeController reloadData];
        [_modelTreeController selectModelWithName:duplicateName];
    }
}

- (void)modelTree:(XLModelTreeViewController *)controller didRequestGroupModels:(NSArray<NSString *> *)modelNames {
    NSLog(@"XLLayoutViewController: Group models requested: %@", modelNames);
}

- (void)modelTree:(XLModelTreeViewController *)controller didRequestUngroupModel:(NSString *)groupName {
    NSLog(@"XLLayoutViewController: Ungroup '%@' requested", groupName);
}

- (void)modelTree:(XLModelTreeViewController *)controller didRequestRenameModel:(NSString *)oldName toName:(NSString *)newName {
    NSLog(@"XLLayoutViewController: Rename model '%@' -> '%@' requested", oldName, newName);

    // Rename via engine bridge
    BOOL success = [_engineBridge renameModel:oldName toName:newName];
    if (success) {
        [_modelTreeController reloadData];
    }
}

- (void)modelTreeDidRequestImportModel:(XLModelTreeViewController *)controller {
    NSLog(@"XLLayoutViewController: Import model requested");
    [self showModelImportSheet];
}

- (void)modelTree:(XLModelTreeViewController *)controller
  didRequestReplaceModel:(NSString *)targetModelName
               withModel:(NSString *)replacementModelName
                 options:(NSDictionary *)options {
    NSLog(@"XLLayoutViewController: Replace model '%@' with '%@' requested", targetModelName, replacementModelName);

    BOOL success = [_engineBridge replaceModel:targetModelName
                                     withModel:replacementModelName
                                       options:options];
    if (success) {
        [_modelTreeController reloadData];
        [_previewView reloadModels];
        [self selectModel:targetModelName];
        [_modelTreeController selectModelWithName:targetModelName];
    }
}

#pragma mark - Model Creation and Import

- (void)showModelCreationSheetForType:(NSString *)modelType {
    if (!self.view.window) return;

    _modelCreationSheet = [[XLModelCreationSheet alloc] init];
    _modelCreationSheet.engineBridge = _engineBridge;

    __weak typeof(self) weakSelf = self;
    [_modelCreationSheet showAsSheetForWindow:self.view.window
                                withModelType:modelType
                                   completion:^(BOOL created, NSString *modelName) {
        if (created && modelName) {
            // Get model data for undo
            NSDictionary *modelData = [weakSelf.engineBridge getModelData:modelName];

            // Register undo action for model creation
            [weakSelf.undoController registerModelCreated:modelName modelData:modelData];

            [weakSelf.modelTreeController reloadData];
            [weakSelf.modelTreeController selectModelWithName:modelName];
        }
        weakSelf.modelCreationSheet = nil;
    }];
}

- (void)showModelImportSheet {
    if (!self.view.window) return;

    _modelImportSheet = [[XLModelImportSheet alloc] init];
    _modelImportSheet.engineBridge = _engineBridge;

    __weak typeof(self) weakSelf = self;
    [_modelImportSheet showAsSheetForWindow:self.view.window
                                 completion:^(BOOL imported, NSArray<NSString *> *importedModelNames) {
        if (imported && importedModelNames.count > 0) {
            [weakSelf.modelTreeController reloadData];
            [weakSelf.previewView reloadModels];
            [weakSelf selectModel:importedModelNames.firstObject];
            [weakSelf.modelTreeController selectModelWithName:importedModelNames.firstObject];
        }
        weakSelf.modelImportSheet = nil;
    }];
}

- (IBAction)importModels:(id)sender {
    [self showModelImportSheet];
}

- (IBAction)importModelsFromRGBEffects:(id)sender {
    if (!self.view.window) return;

    _modelImportSheet = [[XLModelImportSheet alloc] init];
    _modelImportSheet.engineBridge = _engineBridge;

    __weak typeof(self) weakSelf = self;
    [_modelImportSheet showRGBEffectsImportForWindow:self.view.window
                                          completion:^(BOOL imported, NSArray<NSString *> *importedModelNames) {
        if (imported && importedModelNames.count > 0) {
            [weakSelf.modelTreeController reloadData];
            [weakSelf.previewView reloadModels];
            [weakSelf selectModel:importedModelNames.firstObject];
            [weakSelf.modelTreeController selectModelWithName:importedModelNames.firstObject];
        }
        weakSelf.modelImportSheet = nil;
    }];
}

- (IBAction)importLORS5Models:(id)sender {
    if (!self.view.window) return;

    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    openPanel.title = @"Import LOR S5 Models";
    openPanel.message = @"Select an LOR S5 preview file (LORPreviews.xml or .lorprev)";
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = NO;
    openPanel.allowsMultipleSelection = NO;

    NSMutableArray<UTType *> *types = [NSMutableArray array];
    UTType *lorprevType = [UTType typeWithFilenameExtension:@"lorprev"];
    if (lorprevType) [types addObject:lorprevType];
    UTType *xmlType = [UTType typeWithIdentifier:@"public.xml"];
    if (xmlType) [types addObject:xmlType];
    openPanel.allowedContentTypes = types;

    __weak typeof(self) weakSelf = self;
    [openPanel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !openPanel.URL) return;
        [weakSelf performLORS5ImportFromFile:openPanel.URL.path];
    }];
}

- (void)performLORS5ImportFromFile:(NSString *)filePath {
    NSArray<NSString *> *previewNames = [_engineBridge getLORS5PreviewNames:filePath];

    if (!previewNames || previewNames.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Import Error";
        alert.informativeText = @"No previews found in the LOR S5 file.";
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
        return;
    }

    if (previewNames.count == 1) {
        [self executeLORS5Import:filePath previewName:previewNames[0]];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Select LOR S5 Preview";
        alert.informativeText = @"This file contains multiple previews. Choose which preview to import models from:";

        NSPopUpButton *previewPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 300, 28) pullsDown:NO];
        for (NSString *name in previewNames) {
            [previewPopup addItemWithTitle:name];
        }
        alert.accessoryView = previewPopup;

        [alert addButtonWithTitle:@"Import"];
        [alert addButtonWithTitle:@"Cancel"];

        __weak typeof(self) weakSelf = self;
        [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
            if (returnCode == NSAlertFirstButtonReturn) {
                [weakSelf executeLORS5Import:filePath previewName:previewPopup.titleOfSelectedItem];
            }
        }];
    }
}

- (void)executeLORS5Import:(NSString *)filePath previewName:(NSString *)previewName {
    NSString *layoutGroup = _currentLayoutGroup ?: @"Default";
    if ([layoutGroup isEqualToString:@"All Models"]) {
        layoutGroup = @"Default";
    }

    NSArray<NSString *> *importedNames = [_engineBridge importModelsFromLORS5File:filePath
                                                                     previewName:previewName
                                                                     layoutGroup:layoutGroup];

    if (importedNames.count > 0) {
        [_modelTreeController reloadData];
        [_previewView reloadModels];
        [self selectModel:importedNames.firstObject];
        [_modelTreeController selectModelWithName:importedNames.firstObject];

        NSAlert *successAlert = [[NSAlert alloc] init];
        successAlert.messageText = @"Import Complete";
        successAlert.informativeText = [NSString stringWithFormat:@"Successfully imported %lu model(s) from LOR S5 preview '%@'.",
                                        (unsigned long)importedNames.count, previewName];
        [successAlert addButtonWithTitle:@"OK"];
        [successAlert beginSheetModalForWindow:self.view.window completionHandler:nil];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Import Failed";
        alert.informativeText = @"No models could be imported from the LOR S5 file. Check the console log for details.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
    }
}

- (IBAction)exportModelToFile:(id)sender {
    NSString *selectedModel = [_modelTreeController selectedModelName];
    if (!selectedModel) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Model Selected";
        alert.informativeText = @"Please select a model in the layout tree before exporting.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    NSSavePanel *savePanel = [NSSavePanel savePanel];
    savePanel.title = @"Export Model";
    savePanel.nameFieldStringValue = [selectedModel stringByAppendingPathExtension:@"xmodel"];
    savePanel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"xmodel"]];

    [savePanel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && savePanel.URL) {
            NSDictionary *modelData = [self->_engineBridge getModelData:selectedModel];
            if (modelData) {
                // Build a simple xmodel XML from the model data
                NSMutableString *xml = [NSMutableString string];
                [xml appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
                [xml appendFormat:@"<model name=\"%@\"", selectedModel];

                NSDictionary *props = modelData[@"properties"];
                for (NSString *key in props) {
                    if ([key isEqualToString:@"name"]) continue;
                    NSString *value = [NSString stringWithFormat:@"%@", props[key]];
                    // Escape XML special characters
                    value = [value stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
                    value = [value stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
                    value = [value stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
                    value = [value stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
                    [xml appendFormat:@" %@=\"%@\"", key, value];
                }
                [xml appendString:@" />\n"];

                NSError *error = nil;
                BOOL written = [xml writeToURL:savePanel.URL
                                    atomically:YES
                                      encoding:NSUTF8StringEncoding
                                         error:&error];
                if (!written) {
                    NSLog(@"XLLayoutViewController: Failed to export model: %@", error);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSAlert *alert = [[NSAlert alloc] init];
                        alert.messageText = @"Export Failed";
                        alert.informativeText = [NSString stringWithFormat:@"Could not write model file: %@",
                                                 error.localizedDescription];
                        [alert addButtonWithTitle:@"OK"];
                        [alert runModal];
                    });
                } else {
                    NSLog(@"XLLayoutViewController: Exported model '%@' to %@", selectedModel, savePanel.URL.path);
                }
            }
        }
    }];
}

- (void)showVendorModelDownload {
    if (!_vendorModelWindowController) {
        _vendorModelWindowController = [[XLVendorModelWindowController alloc] init];
    }
    _vendorModelWindowController.engineBridge = _engineBridge;
    _vendorModelWindowController.showFolderPath = [_engineBridge getShowFolderPath];

    __weak typeof(self) weakSelf = self;
    [_vendorModelWindowController showWithCompletion:^(BOOL imported, NSString *modelFilePath) {
        if (imported) {
            [weakSelf.modelTreeController reloadData];

            // Try to select the imported model
            if (modelFilePath) {
                NSString *modelName = [[modelFilePath lastPathComponent] stringByDeletingPathExtension];
                [weakSelf.modelTreeController selectModelWithName:modelName];
            }
        }
    }];
}

#pragma mark - Model Selection and Manipulation

- (void)selectModel:(NSString *)modelName {
    if (!modelName) {
        [self clearSelection];
        return;
    }

    _previewView.selectedModelName = modelName;

    // Get model info from engine bridge and set up handles
    NSDictionary *modelInfo = [_engineBridge getModelInfo:modelName];
    if (modelInfo) {
        // Extract position
        simd_float3 position = simd_make_float3(
            [modelInfo[@"WorldPosX"] floatValue],
            [modelInfo[@"WorldPosY"] floatValue],
            [modelInfo[@"WorldPosZ"] floatValue]
        );

        // Extract scale
        simd_float3 scale = simd_make_float3(
            [modelInfo[@"ScaleX"] floatValue] ?: 1.0f,
            [modelInfo[@"ScaleY"] floatValue] ?: 1.0f,
            [modelInfo[@"ScaleZ"] floatValue] ?: 1.0f
        );

        // Extract rotation
        simd_float3 rotation = simd_make_float3(
            [modelInfo[@"RotateX"] floatValue],
            [modelInfo[@"RotateY"] floatValue],
            [modelInfo[@"RotateZ"] floatValue]
        );

        // Extract render dimensions (computed from buffer dims in dictFromModelInfo)
        float renderWidth = [modelInfo[@"RenderWidth"] floatValue];
        float renderHeight = [modelInfo[@"RenderHeight"] floatValue];
        float renderDepth = [modelInfo[@"RenderDepth"] floatValue];
        if (renderWidth < 0.001f) renderWidth = 1.0f;
        if (renderHeight < 0.001f) renderHeight = 1.0f;
        if (renderDepth < 0.001f) renderDepth = 2.0f;

        BOOL isLocked = [modelInfo[@"Locked"] boolValue];
        BOOL supportsZScaling = [modelInfo[@"SupportsZScaling"] boolValue];

        // Bounding box in local space centered at origin, matching legacy BoxedScreenLocation
        simd_float3 bbMin = simd_make_float3(-renderWidth/2, -renderHeight/2, -renderDepth/2);
        simd_float3 bbMax = simd_make_float3(renderWidth/2, renderHeight/2, renderDepth/2);

        [_previewView setModelTransformWithPosition:position
                                              scale:scale
                                           rotation:rotation
                                     boundingBoxMin:bbMin
                                     boundingBoxMax:bbMax
                                        renderWidth:renderWidth
                                       renderHeight:renderHeight
                                        renderDepth:renderDepth
                                           isLocked:isLocked
                                   supportsZScaling:supportsZScaling];

        // Update properties view with real model data
        [_propertiesView showPropertiesForModel:modelName info:modelInfo];
    }

    [_modelTreeController selectModelWithName:modelName];
}

- (void)clearSelection {
    _previewView.selectedModelName = nil;
    [_previewView clearModelSelection];
    [_propertiesView clearProperties];
}

- (void)setToolMode:(NSInteger)mode {
    [_previewView setToolMode:mode];
}

- (void)setActiveAxis:(NSInteger)axis {
    [_previewView setActiveAxis:axis];
}

- (void)toggleToolMode {
    [_previewView toggleToolMode];
}

- (void)toggle2D3DMode {
    _previewView.show3D = !_previewView.show3D;
    _viewModeControl.selectedSegment = _previewView.show3D ? 1 : 0;
    [[NSUserDefaults standardUserDefaults] setBool:_previewView.show3D forKey:kLayoutShow3DKey];
    _modelTreeController.show3D = _previewView.show3D;
}

- (void)viewModeChanged:(NSSegmentedControl *)sender {
    BOOL show3D = (sender.selectedSegment == 1);
    _previewView.show3D = show3D;
    [[NSUserDefaults standardUserDefaults] setBool:show3D forKey:kLayoutShow3DKey];
    _modelTreeController.show3D = show3D;
    [_previewView setNeedsDisplay:YES];
}

- (void)overlapCheckToggled:(NSButton *)sender {
    BOOL enabled = (sender.state == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kLayoutOverlapChecksKey];
}

- (BOOL)overlapChecksEnabled {
    return (_overlapCheckToggle.state == NSControlStateValueOn);
}

- (void)setGridSnapSize:(float)snapSize {
    [_previewView setGridSnapSize:snapSize];
}

- (void)setAngleSnapDegrees:(float)angleDegrees {
    [_previewView setAngleSnapDegrees:angleDegrees];
}

- (void)setEdgeSnapEnabled:(BOOL)enabled {
    [_previewView setEdgeSnapEnabled:enabled];
}

#pragma mark - XLMetalPreviewDelegate (Manipulation)

- (void)previewView:(XLMetalPreviewView *)view didBeginManipulatingModel:(NSString *)modelName {
    NSLog(@"XLLayoutViewController: Begin manipulating model '%@'", modelName);

    // Capture current transform state for undo
    if (modelName) {
        NSDictionary *modelInfo = [_engineBridge getModelInfo:modelName];
        if (modelInfo) {
            XLModelTransformSnapshot snapshot;
            snapshot.position = simd_make_float3(
                [modelInfo[@"WorldPosX"] floatValue],
                [modelInfo[@"WorldPosY"] floatValue],
                [modelInfo[@"WorldPosZ"] floatValue]
            );
            snapshot.scale = simd_make_float3(
                [modelInfo[@"ScaleX"] floatValue] ?: 1.0f,
                [modelInfo[@"ScaleY"] floatValue] ?: 1.0f,
                [modelInfo[@"ScaleZ"] floatValue] ?: 1.0f
            );
            snapshot.rotation = simd_make_float3(
                [modelInfo[@"RotateX"] floatValue],
                [modelInfo[@"RotateY"] floatValue],
                [modelInfo[@"RotateZ"] floatValue]
            );

            [_undoController captureModelTransform:modelName snapshot:snapshot];

            // Track the current tool mode for registering the right action type
            _manipulationToolMode = _previewView.handlesRenderer.toolMode;
        }
    }
}

- (void)previewView:(XLMetalPreviewView *)view didManipulateModelWithDelta:(simd_float3)delta {
    NSString *modelName = _previewView.selectedModelName;
    if (!modelName) return;

    // Get current transform from handles renderer
    XLManipulationHandlesRenderer *handles = _previewView.handlesRenderer;
    XLModelTransform transform = [handles modelTransform];

    // Update model via engine bridge
    [_engineBridge updateModelProperty:modelName key:@"WorldPosX" value:@(transform.position.x)];
    [_engineBridge updateModelProperty:modelName key:@"WorldPosY" value:@(transform.position.y)];
    [_engineBridge updateModelProperty:modelName key:@"WorldPosZ" value:@(transform.position.z)];
    [_engineBridge updateModelProperty:modelName key:@"ScaleX" value:@(transform.scale.x)];
    [_engineBridge updateModelProperty:modelName key:@"ScaleY" value:@(transform.scale.y)];
    [_engineBridge updateModelProperty:modelName key:@"ScaleZ" value:@(transform.scale.z)];
    [_engineBridge updateModelProperty:modelName key:@"RotateX" value:@(transform.rotation.x)];
    [_engineBridge updateModelProperty:modelName key:@"RotateY" value:@(transform.rotation.y)];
    [_engineBridge updateModelProperty:modelName key:@"RotateZ" value:@(transform.rotation.z)];
}

- (void)previewView:(XLMetalPreviewView *)view didEndManipulatingModel:(NSString *)modelName {
    NSLog(@"XLLayoutViewController: End manipulating model '%@'", modelName);

    // Register the completed manipulation for undo
    if (modelName) {
        XLManipulationHandlesRenderer *handles = _previewView.handlesRenderer;
        XLModelTransform transform = [handles modelTransform];

        XLModelTransformSnapshot newSnapshot;
        newSnapshot.position = transform.position;
        newSnapshot.scale = transform.scale;
        newSnapshot.rotation = transform.rotation;

        // Register based on the tool mode that was active
        switch (_manipulationToolMode) {
            case XLToolModeTranslate:
            case XLToolModeXYTranslate:
            case XLToolModeElevate:
                [_undoController registerTranslate:modelName newSnapshot:newSnapshot];
                break;
            case XLToolModeScale:
                [_undoController registerScale:modelName newSnapshot:newSnapshot];
                break;
            case XLToolModeRotate:
                [_undoController registerRotate:modelName newSnapshot:newSnapshot];
                break;
            default:
                // Default to translate for unknown modes
                [_undoController registerTranslate:modelName newSnapshot:newSnapshot];
                break;
        }
    }

    // Trigger a full refresh to ensure model state is synced
    [_modelTreeController reloadData];

    // Re-select to refresh properties view
    if (modelName) {
        NSDictionary *modelInfo = [_engineBridge getModelInfo:modelName];
        if (modelInfo) {
            [_propertiesView showPropertiesForModel:modelName info:modelInfo];
        }
    }
}

#pragma mark - Arrow Key Nudge

- (void)previewView:(XLMetalPreviewView *)view didNudgeModelWithDeltaX:(float)deltaX deltaY:(float)deltaY {
    NSString *modelName = _previewView.selectedModelName;
    if (!modelName) return;

    NSDictionary *modelInfo = [_engineBridge getModelInfo:modelName];
    if (!modelInfo) return;

    if ([modelInfo[@"Locked"] boolValue]) return;

    float curX = [modelInfo[@"WorldPosX"] floatValue];
    float curY = [modelInfo[@"WorldPosY"] floatValue];
    float newX = curX + deltaX;
    float newY = curY + deltaY;

    if (_nudgeUndoGroupOpen && [_nudgeModelName isEqualToString:modelName]) {
        // Continue an existing nudge sequence -- just reset the coalesce timer
        [_nudgeCoalesceTimer invalidate];
    } else {
        // Finalize any previous nudge group before starting a new one
        [self finalizeNudgeUndoGroup];
        _nudgeModelName = modelName;
        _nudgeStartX = curX;
        _nudgeStartY = curY;
        _nudgeUndoGroupOpen = YES;
    }

    // Apply the delta immediately
    [_engineBridge updateModelProperty:modelName key:@"WorldPosX" value:@(newX)];
    [_engineBridge updateModelProperty:modelName key:@"WorldPosY" value:@(newY)];

    // Restart the coalesce timer; when it fires the undo entry is registered
    _nudgeCoalesceTimer = [NSTimer scheduledTimerWithTimeInterval:kNudgeCoalesceInterval
                                                          target:self
                                                        selector:@selector(nudgeCoalesceTimerFired:)
                                                        userInfo:nil
                                                         repeats:NO];

    // Refresh the preview and properties
    [self selectModel:modelName];
}

- (void)nudgeCoalesceTimerFired:(NSTimer *)timer {
    [self finalizeNudgeUndoGroup];
}

- (void)finalizeNudgeUndoGroup {
    if (!_nudgeUndoGroupOpen) return;

    NSString *modelName = _nudgeModelName;
    if (modelName) {
        NSDictionary *modelInfo = [_engineBridge getModelInfo:modelName];
        if (modelInfo) {
            float finalX = [modelInfo[@"WorldPosX"] floatValue];
            float finalY = [modelInfo[@"WorldPosY"] floatValue];

            // Register a single undo entry spanning start -> final position
            [_undoController beginUndoGroup:@"Nudge"];
            [_undoController registerPropertyChange:modelName
                                                key:@"WorldPosX"
                                           oldValue:@(_nudgeStartX)
                                           newValue:@(finalX)];
            [_undoController registerPropertyChange:modelName
                                                key:@"WorldPosY"
                                           oldValue:@(_nudgeStartY)
                                           newValue:@(finalY)];
            [_undoController endUndoGroup];
        }
    }

    _nudgeUndoGroupOpen = NO;
    _nudgeModelName = nil;
    _nudgeCoalesceTimer = nil;
}

#pragma mark - XLModelPropertiesDelegate

- (void)modelProperties:(XLModelPropertiesView *)view
       didChangeProperty:(NSString *)key
                   value:(id)value
                forModel:(NSString *)modelName {
    NSLog(@"XLLayoutViewController: Property '%@' changed to '%@' for model '%@'", key, value, modelName);

    // Get old value for undo
    NSDictionary *modelInfo = [_engineBridge getModelInfo:modelName];
    id oldValue = modelInfo[key];

    // Update model via engine bridge
    BOOL success = [_engineBridge updateModelProperty:modelName key:key value:value];
    if (success) {
        // Register property change for undo
        [_undoController registerPropertyChange:modelName key:key oldValue:oldValue newValue:value];

        // Refresh the model tree if name changed
        if ([key isEqualToString:@"name"]) {
            [_modelTreeController reloadData];
            [_modelTreeController selectModelWithName:value];
        }

        // Refresh preview view handles if position/scale/rotation changed
        // Keys are now mapped to engine keys by XLModelPropertiesView
        NSSet *transformKeys = [NSSet setWithArray:@[
            @"WorldPosX", @"WorldPosY", @"WorldPosZ",
            @"ScaleX", @"ScaleY", @"ScaleZ", @"Scale",
            @"RotateX", @"RotateY", @"RotateZ",
            @"Locked"
        ]];
        if ([transformKeys containsObject:key]) {
            [self selectModel:modelName];
        }
    }
}

- (void)modelPropertiesDidRequestEditCustomModel:(XLModelPropertiesView *)view
                                        forModel:(NSString *)modelName {
    XLCustomModelWindow *customModelWindow = [[XLCustomModelWindow alloc] initWithModelName:modelName];
    customModelWindow.engineBridge = _engineBridge;

    [customModelWindow showWithCompletion:^(BOOL saved) {
        if (saved) {
            [self selectModel:modelName];
            [self.modelTreeController reloadData];
        }
    }];
}

#pragma mark - XLLayoutUndoDelegate

- (void)layoutUndoController:(XLLayoutUndoController *)controller
        didRestoreModelNamed:(NSString *)modelName {
    // Refresh UI after undo/redo
    [_modelTreeController reloadData];
    [_previewView reloadModels];

    // Re-select the model to update handles and properties
    if (modelName) {
        [self selectModel:modelName];
    }
}

- (void)layoutUndoController:(XLLayoutUndoController *)controller
         didChangeModelNamed:(NSString *)modelName
                   wasCreate:(BOOL)wasCreate {
    // Refresh UI after model create/delete undo/redo
    [_modelTreeController reloadData];
    [_previewView reloadModels];

    if (wasCreate && modelName) {
        [self selectModel:modelName];
    } else if (!wasCreate) {
        [self clearSelection];
    }
}

#pragma mark - XLMetalPreviewDelegate (Context Menu)

- (void)previewView:(XLMetalPreviewView *)view didRequestLockModel:(NSString *)modelName lock:(BOOL)lock {
    BOOL success = [_engineBridge updateModelProperty:modelName key:@"Locked" value:@(lock)];
    if (success) {
        [_undoController registerPropertyChange:modelName key:@"Locked" oldValue:@(!lock) newValue:@(lock)];
        [self selectModel:modelName];
        [_previewView reloadModels];
    }
}

- (void)previewView:(XLMetalPreviewView *)view didRequestDeleteModel:(NSString *)modelName {
    NSDictionary *modelData = [_engineBridge getModelData:modelName];
    BOOL success = [_engineBridge deleteModel:modelName];
    if (success) {
        [_undoController registerModelDeleted:modelName modelData:modelData];
        [self clearSelection];
        [_modelTreeController reloadData];
        [_previewView reloadModels];
    }
}

- (void)previewView:(XLMetalPreviewView *)view didRequestFlipModel:(NSString *)modelName horizontal:(BOOL)horizontal {
    NSDictionary *info = [_engineBridge getModelInfo:modelName];
    if (!info) return;

    NSString *key = horizontal ? @"ScaleX" : @"ScaleY";
    float currentScale = [info[key] floatValue];
    if (currentScale == 0) currentScale = 1.0f;
    float newScale = -currentScale;

    BOOL success = [_engineBridge updateModelProperty:modelName key:key value:@(newScale)];
    if (success) {
        [_undoController registerPropertyChange:modelName key:key oldValue:@(currentScale) newValue:@(newScale)];
        [self selectModel:modelName];
        [_previewView reloadModels];
    }
}

- (void)previewView:(XLMetalPreviewView *)view didRequestAlignModels:(NSString *)alignment {
    BOOL isGroundAlign = [alignment isEqualToString:@"Align With Ground"];
    NSArray<NSString *> *selectedNames = [_modelTreeController selectedModelNames];

    // Ground alignment works on 1+ models; all others need 2+
    if (isGroundAlign) {
        if (selectedNames.count < 1) return;
    } else {
        if (selectedNames.count < 2) return;
    }

    // Use the first selected model as the reference (not used for ground align)
    NSString *refName = selectedNames.firstObject;
    NSDictionary *refBounds = isGroundAlign ? nil : [_engineBridge getModelBounds:refName];
    if (!isGroundAlign && !refBounds) return;

    float refMinX = [refBounds[@"minX"] floatValue];
    float refMaxX = [refBounds[@"maxX"] floatValue];
    float refMinY = [refBounds[@"minY"] floatValue];
    float refMaxY = [refBounds[@"maxY"] floatValue];
    float refMinZ = [refBounds[@"minZ"] floatValue];
    float refMaxZ = [refBounds[@"maxZ"] floatValue];

    NSString *actionName = [NSString stringWithFormat:@"Align %@", alignment];
    [_undoController beginUndoGroup:actionName];

    // For ground alignment, iterate all selected models (including first).
    // For other alignments, skip the reference model (first).
    NSUInteger startIndex = isGroundAlign ? 0 : 1;

    for (NSUInteger i = startIndex; i < selectedNames.count; i++) {
        NSString *name = selectedNames[i];
        NSDictionary *bounds = [_engineBridge getModelBounds:name];
        NSDictionary *info = [_engineBridge getModelInfo:name];
        if (!bounds || !info) continue;

        float curMinX = [bounds[@"minX"] floatValue];
        float curMaxX = [bounds[@"maxX"] floatValue];
        float curMinY = [bounds[@"minY"] floatValue];
        float curMaxY = [bounds[@"maxY"] floatValue];
        float curMinZ = [bounds[@"minZ"] floatValue];
        float curMaxZ = [bounds[@"maxZ"] floatValue];
        float curPosX = [info[@"WorldPosX"] floatValue];
        float curPosY = [info[@"WorldPosY"] floatValue];
        float curPosZ = [info[@"WorldPosZ"] floatValue];

        float newPosX = curPosX;
        float newPosY = curPosY;
        float newPosZ = curPosZ;

        if ([alignment isEqualToString:@"Top"]) {
            newPosY = curPosY + (refMaxY - curMaxY);
        } else if ([alignment isEqualToString:@"Bottom"]) {
            newPosY = curPosY + (refMinY - curMinY);
        } else if ([alignment isEqualToString:@"Left"]) {
            newPosX = curPosX + (refMinX - curMinX);
        } else if ([alignment isEqualToString:@"Right"]) {
            newPosX = curPosX + (refMaxX - curMaxX);
        } else if ([alignment isEqualToString:@"Horizontal Center"]) {
            float refCenterX = (refMinX + refMaxX) / 2.0f;
            float curCenterX = (curMinX + curMaxX) / 2.0f;
            newPosX = curPosX + (refCenterX - curCenterX);
        } else if ([alignment isEqualToString:@"Vertical Center"]) {
            float refCenterY = (refMinY + refMaxY) / 2.0f;
            float curCenterY = (curMinY + curMaxY) / 2.0f;
            newPosY = curPosY + (refCenterY - curCenterY);
        } else if ([alignment isEqualToString:@"Front"]) {
            newPosZ = curPosZ + (refMinZ - curMinZ);
        } else if ([alignment isEqualToString:@"Back"]) {
            newPosZ = curPosZ + (refMaxZ - curMaxZ);
        } else if ([alignment isEqualToString:@"Depth Center"]) {
            float refCenterZ = (refMinZ + refMaxZ) / 2.0f;
            float curCenterZ = (curMinZ + curMaxZ) / 2.0f;
            newPosZ = curPosZ + (refCenterZ - curCenterZ);
        } else if (isGroundAlign) {
            newPosY = curPosY - curMinY;
        }

        if (newPosX != curPosX) {
            [_undoController registerPropertyChange:name key:@"WorldPosX" oldValue:@(curPosX) newValue:@(newPosX)];
            [_engineBridge updateModelProperty:name key:@"WorldPosX" value:@(newPosX)];
        }
        if (newPosY != curPosY) {
            [_undoController registerPropertyChange:name key:@"WorldPosY" oldValue:@(curPosY) newValue:@(newPosY)];
            [_engineBridge updateModelProperty:name key:@"WorldPosY" value:@(newPosY)];
        }
        if (newPosZ != curPosZ) {
            [_undoController registerPropertyChange:name key:@"WorldPosZ" oldValue:@(curPosZ) newValue:@(newPosZ)];
            [_engineBridge updateModelProperty:name key:@"WorldPosZ" value:@(newPosZ)];
        }
    }

    [_undoController endUndoGroup];

    [_previewView reloadModels];
    [self selectModel:_previewView.selectedModelName];
}

- (void)previewView:(XLMetalPreviewView *)view didRequestDistributeModels:(NSString *)direction {
    NSArray<NSString *> *selectedNames = [_modelTreeController selectedModelNames];
    if (selectedNames.count < 3) return;

    // Determine which axis to distribute along
    NSString *posKey;
    NSString *boundsMinKey;
    NSString *boundsMaxKey;
    if ([direction isEqualToString:@"Horizontal"]) {
        posKey = @"WorldPosX";
        boundsMinKey = @"minX";
        boundsMaxKey = @"maxX";
    } else if ([direction isEqualToString:@"Depth"]) {
        posKey = @"WorldPosZ";
        boundsMinKey = @"minZ";
        boundsMaxKey = @"maxZ";
    } else {
        posKey = @"WorldPosY";
        boundsMinKey = @"minY";
        boundsMaxKey = @"maxY";
    }

    // Collect positions and sort
    NSMutableArray<NSDictionary *> *models = [NSMutableArray array];
    for (NSString *name in selectedNames) {
        NSDictionary *bounds = [_engineBridge getModelBounds:name];
        NSDictionary *info = [_engineBridge getModelInfo:name];
        if (!bounds || !info) continue;

        float center = ([bounds[boundsMinKey] floatValue] + [bounds[boundsMaxKey] floatValue]) / 2.0f;
        [models addObject:@{@"name": name, @"center": @(center), @"info": info}];
    }

    if (models.count < 3) return;

    [models sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"center"] compare:b[@"center"]];
    }];

    float firstCenter = [models.firstObject[@"center"] floatValue];
    float lastCenter = [models.lastObject[@"center"] floatValue];
    float spacing = (lastCenter - firstCenter) / (float)(models.count - 1);

    // Begin undo group for the batch operation
    [_undoController.undoManager beginUndoGrouping];

    for (NSUInteger i = 1; i < models.count - 1; i++) {
        NSDictionary *model = models[i];
        NSString *name = model[@"name"];
        NSDictionary *info = model[@"info"];
        float currentCenter = [model[@"center"] floatValue];
        float targetCenter = firstCenter + spacing * (float)i;
        float delta = targetCenter - currentCenter;

        float currentPos = [info[posKey] floatValue];
        float newPos = currentPos + delta;
        [_undoController registerPropertyChange:name key:posKey oldValue:@(currentPos) newValue:@(newPos)];
        [_engineBridge updateModelProperty:name key:posKey value:@(newPos)];
    }

    [_undoController.undoManager endUndoGrouping];
    [_undoController.undoManager setActionName:[NSString stringWithFormat:@"Distribute %@", direction]];

    [_previewView reloadModels];
    [self selectModel:_previewView.selectedModelName];
}

- (void)previewView:(XLMetalPreviewView *)view didRequestResizeModels:(NSString *)dimension {
    NSArray<NSString *> *selectedNames = [_modelTreeController selectedModelNames];
    if (selectedNames.count < 2) return;

    // Use the first selected model as the reference
    NSString *refName = selectedNames.firstObject;
    NSDictionary *refBounds = [_engineBridge getModelBounds:refName];
    if (!refBounds) return;

    float refWidth = [refBounds[@"maxX"] floatValue] - [refBounds[@"minX"] floatValue];
    float refHeight = [refBounds[@"maxY"] floatValue] - [refBounds[@"minY"] floatValue];

    BOOL matchWidth = [dimension isEqualToString:@"Match Width"] || [dimension isEqualToString:@"Match Size"];
    BOOL matchHeight = [dimension isEqualToString:@"Match Height"] || [dimension isEqualToString:@"Match Size"];

    [_undoController beginUndoGroup:[NSString stringWithFormat:@"Resize %@", dimension]];

    for (NSUInteger i = 1; i < selectedNames.count; i++) {
        NSString *name = selectedNames[i];
        NSDictionary *bounds = [_engineBridge getModelBounds:name];
        NSDictionary *info = [_engineBridge getModelInfo:name];
        if (!bounds || !info) continue;

        float curWidth = [bounds[@"maxX"] floatValue] - [bounds[@"minX"] floatValue];
        float curHeight = [bounds[@"maxY"] floatValue] - [bounds[@"minY"] floatValue];

        if (matchWidth && curWidth > 0.01f) {
            float curScaleX = [info[@"ScaleX"] floatValue];
            if (curScaleX == 0) curScaleX = 1.0f;
            float newScaleX = curScaleX * (refWidth / curWidth);
            [_undoController registerPropertyChange:name key:@"ScaleX" oldValue:@(curScaleX) newValue:@(newScaleX)];
            [_engineBridge updateModelProperty:name key:@"ScaleX" value:@(newScaleX)];
        }
        if (matchHeight && curHeight > 0.01f) {
            float curScaleY = [info[@"ScaleY"] floatValue];
            if (curScaleY == 0) curScaleY = 1.0f;
            float newScaleY = curScaleY * (refHeight / curHeight);
            [_undoController registerPropertyChange:name key:@"ScaleY" oldValue:@(curScaleY) newValue:@(newScaleY)];
            [_engineBridge updateModelProperty:name key:@"ScaleY" value:@(newScaleY)];
        }
    }

    [_undoController endUndoGroup];

    [_previewView reloadModels];
    [self selectModel:_previewView.selectedModelName];
}

- (void)previewView:(XLMetalPreviewView *)view didRequestBulkEdit:(NSString *)editType {
    NSArray<NSString *> *selectedNames = [_modelTreeController selectedModelNames];
    if (selectedNames.count == 0) {
        // Fall back to the single selected model in the preview
        if (_previewView.selectedModelName) {
            selectedNames = @[_previewView.selectedModelName];
        } else {
            return;
        }
    }

    // Map the edit type string to bulk edit operations
    if ([editType isEqualToString:@"Active"]) {
        [self bulkSetProperty:@"Active" value:@"1" forModels:selectedNames];
    } else if ([editType isEqualToString:@"Inactive"]) {
        [self bulkSetProperty:@"Active" value:@"0" forModels:selectedNames];
    } else if ([editType isEqualToString:@"Tag Color"]) {
        [self bulkEditTagColorForModels:selectedNames];
    } else if ([editType isEqualToString:@"Preview"]) {
        [self bulkEditTextProperty:@"LayoutGroup"
                             title:@"Set Preview Group"
                           message:[NSString stringWithFormat:@"Enter the preview/layout group for %lu selected models.", (unsigned long)selectedNames.count]
                      defaultValue:@"Default"
                         forModels:selectedNames];
    } else if ([editType isEqualToString:@"Pixel Size"]) {
        [self bulkEditSliderProperty:@"PixelSize"
                               title:@"Set Pixel Size"
                             message:[NSString stringWithFormat:@"Choose pixel size for %lu selected models.", (unsigned long)selectedNames.count]
                            minValue:1 maxValue:10 defaultValue:2 integerOnly:YES
                           forModels:selectedNames];
    } else if ([editType isEqualToString:@"Pixel Style"]) {
        [self bulkEditPickerProperty:@"PixelStyle"
                               title:@"Set Pixel Style"
                             message:[NSString stringWithFormat:@"Choose pixel style for %lu selected models.", (unsigned long)selectedNames.count]
                             options:@[@"Square", @"Circle", @"Smooth Circle", @"Blended Circle"]
                            useIndex:YES
                           forModels:selectedNames];
    } else if ([editType isEqualToString:@"Transparency"]) {
        [self bulkEditSliderProperty:@"Transparency"
                               title:@"Set Transparency"
                             message:[NSString stringWithFormat:@"Choose transparency for %lu selected models (0 = opaque, 100 = fully transparent).", (unsigned long)selectedNames.count]
                            minValue:0 maxValue:100 defaultValue:0 integerOnly:YES
                           forModels:selectedNames];
    } else if ([editType isEqualToString:@"Controller Name"]) {
        NSMutableArray *options = [NSMutableArray arrayWithObject:@"(None)"];
        NSArray<NSString *> *controllerNames = [_engineBridge getControllerNames];
        if (controllerNames.count > 0) {
            [options addObjectsFromArray:controllerNames];
        }
        [self bulkEditPickerProperty:@"Controller"
                               title:@"Set Controller Name"
                             message:[NSString stringWithFormat:@"Choose controller for %lu selected models.", (unsigned long)selectedNames.count]
                             options:options
                            useIndex:NO
                           forModels:selectedNames];
    } else if ([editType isEqualToString:@"Controller Port"]) {
        [self bulkEditTextProperty:@"ControllerPort"
                             title:@"Set Controller Port"
                           message:[NSString stringWithFormat:@"Enter the port number for %lu selected models.", (unsigned long)selectedNames.count]
                      defaultValue:@"1"
                         forModels:selectedNames];
    } else if ([editType isEqualToString:@"Controller Protocol"]) {
        [self bulkEditPickerProperty:@"Protocol"
                               title:@"Set Controller Protocol"
                             message:[NSString stringWithFormat:@"Choose protocol for %lu selected models.", (unsigned long)selectedNames.count]
                             options:@[@"ws2811", @"WS2801", @"TLS3001", @"LPD6803", @"LPD8806",
                                       @"APA102", @"APA109", @"ICICOB", @"SM16716",
                                       @"DMX", @"LOR", @"Renard", @"Open DMX"]
                            useIndex:NO
                           forModels:selectedNames];
    }

    [_previewView reloadModels];
}

#pragma mark - XLMetalPreviewDelegate (New Context Menu Operations)

- (NSArray<NSString *> *)previewViewSelectedModelNames:(XLMetalPreviewView *)view {
    NSArray<NSString *> *treeSelection = [_modelTreeController selectedModelNames];
    if (treeSelection.count > 0) return treeSelection;
    if (view.selectedModelName) return @[view.selectedModelName];
    return @[];
}

- (void)previewViewDidRequestDeletePreview:(XLMetalPreviewView *)view {
    NSString *currentGroup = _currentLayoutGroup;
    if (!currentGroup || [currentGroup isEqualToString:@"Default"]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Cannot Delete Default Preview";
        alert.informativeText = @"The Default preview cannot be deleted.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Delete Preview \"%@\"?", currentGroup];
    alert.informativeText = @"This will remove the preview and unassign all models in it. This cannot be undone.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;
    alert.buttons.firstObject.hasDestructiveAction = YES;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        BOOL success = [_engineBridge deleteLayoutGroup:currentGroup];
        if (success) {
            [self reloadLayoutGroupSelector];
            [_modelTreeController reloadData];
            [_previewView reloadModels];
        }
    }
}

- (void)previewViewDidRequestRenamePreview:(XLMetalPreviewView *)view {
    NSString *currentGroup = _currentLayoutGroup;
    if (!currentGroup || [currentGroup isEqualToString:@"Default"]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Cannot Rename Default Preview";
        alert.informativeText = @"The Default preview cannot be renamed.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename Preview";
    alert.informativeText = [NSString stringWithFormat:@"Enter a new name for preview \"%@\":", currentGroup];
    [alert addButtonWithTitle:@"Rename"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
    input.stringValue = currentGroup;
    alert.accessoryView = input;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *newName = input.stringValue;
        if (newName.length > 0 && ![newName isEqualToString:currentGroup]) {
            BOOL success = [_engineBridge renameLayoutGroup:currentGroup toName:newName];
            if (success) {
                [self reloadLayoutGroupSelector];
                [_modelTreeController reloadData];
                [_previewView reloadModels];
            }
        }
    }
}

- (void)previewViewDidRequestPrintLayoutImage:(XLMetalPreviewView *)view {
    NSLog(@"XLLayoutViewController: Print Layout Image not yet implemented");
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Print Layout Image";
    alert.informativeText = @"This feature is not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)previewViewDidRequestSaveLayoutImage:(XLMetalPreviewView *)view {
    NSLog(@"XLLayoutViewController: Save Layout Image not yet implemented");
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save Layout Image";
    alert.informativeText = @"This feature is not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)previewViewDidRequestImportModels:(XLMetalPreviewView *)view {
    [self showModelImportSheet];
}

- (void)previewViewDidRequestImportPreviews:(XLMetalPreviewView *)view {
    [self importModelsFromRGBEffects:nil];
}

- (void)previewView:(XLMetalPreviewView *)view didRequestNodeLayout:(NSString *)modelName {
    NSLog(@"XLLayoutViewController: Node Layout for '%@' not yet implemented", modelName);
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Node Layout - Not Yet Implemented";
    alert.informativeText = @"The Node Layout dialog will allow visual editing of individual node positions within the model.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)previewView:(XLMetalPreviewView *)view didRequestWiringView:(NSString *)modelName {
    NSLog(@"XLLayoutViewController: Wiring View for '%@' not yet implemented", modelName);
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Wiring View - Not Yet Implemented";
    alert.informativeText = @"The Wiring View dialog will show the physical wiring order and connections for the model.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)previewView:(XLMetalPreviewView *)view didRequestExportAsCustomModel:(NSString *)modelName {
    NSLog(@"XLLayoutViewController: Export as Custom Model for '%@' not yet implemented", modelName);
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Export as Custom xLights Model - Not Yet Implemented";
    alert.informativeText = @"This will export the current model as a Custom model type that can be imported into other shows.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)previewView:(XLMetalPreviewView *)view didRequestExportXModel:(NSString *)modelName {
    // Reuse the existing export implementation - temporarily select this model
    NSString *previousSelection = [_modelTreeController selectedModelName];
    [_modelTreeController selectModelWithName:modelName];
    [self exportModelToFile:nil];
    if (previousSelection) {
        [_modelTreeController selectModelWithName:previousSelection];
    }
}

- (void)previewView:(XLMetalPreviewView *)view didRequestAddModel:(NSString *)modelName toGroup:(NSString *)groupName {
    BOOL success = [_engineBridge addModel:modelName toGroup:groupName];
    if (success) {
        [_modelTreeController reloadData];
        NSLog(@"XLLayoutViewController: Added model '%@' to group '%@'", modelName, groupName);
    }
}

- (void)previewView:(XLMetalPreviewView *)view didRequestCreateGroupFromModels:(NSArray<NSString *> *)modelNames {
    if (modelNames.count == 0) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Create Group";
    alert.informativeText = [NSString stringWithFormat:@"Enter a name for the new group (%lu models):", (unsigned long)modelNames.count];
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
    input.placeholderString = @"Group Name";
    alert.accessoryView = input;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *groupName = input.stringValue;
        if (groupName.length > 0) {
            BOOL success = [_engineBridge createModelGroup:groupName withModels:modelNames];
            if (success) {
                [_modelTreeController reloadData];
                [_previewView reloadModels];
                NSLog(@"XLLayoutViewController: Created group '%@' with %lu models", groupName, (unsigned long)modelNames.count);
            } else {
                NSAlert *errorAlert = [[NSAlert alloc] init];
                errorAlert.messageText = @"Cannot Create Group";
                errorAlert.informativeText = [NSString stringWithFormat:@"A model or group named \"%@\" already exists.", groupName];
                [errorAlert addButtonWithTitle:@"OK"];
                [errorAlert runModal];
            }
        }
    }
}

- (void)previewView:(XLMetalPreviewView *)view didRequestLockModels:(NSArray<NSString *> *)modelNames lock:(BOOL)lock {
    for (NSString *name in modelNames) {
        [_engineBridge updateModelProperty:name key:@"Locked" value:@(lock)];
    }
    [_previewView reloadModels];
    if (_previewView.selectedModelName) {
        [self selectModel:_previewView.selectedModelName];
    }
}

- (void)previewView:(XLMetalPreviewView *)view didRequestDeleteModels:(NSArray<NSString *> *)modelNames {
    for (NSString *name in modelNames) {
        NSDictionary *modelData = [_engineBridge getModelData:name];
        BOOL success = [_engineBridge deleteModel:name];
        if (success) {
            [_undoController registerModelDeleted:name modelData:modelData];
        }
    }
    [self clearSelection];
    [_modelTreeController reloadData];
    [_previewView reloadModels];
}

#pragma mark - Bulk Edit Helpers (Preview Context Menu)

- (void)bulkSetProperty:(NSString *)key value:(NSString *)value forModels:(NSArray<NSString *> *)modelNames {
    for (NSString *name in modelNames) {
        [_engineBridge updateModelProperty:name key:key value:value];
    }
    [_modelTreeController reloadData];
    [_previewView reloadModels];
}

- (void)bulkEditTagColorForModels:(NSArray<NSString *> *)modelNames {
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

- (void)bulkEditTextProperty:(NSString *)key
                       title:(NSString *)title
                     message:(NSString *)message
                defaultValue:(NSString *)defaultValue
                   forModels:(NSArray<NSString *> *)modelNames {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
    input.stringValue = defaultValue ?: @"";
    alert.accessoryView = input;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *value = input.stringValue;
        if (value.length > 0) {
            [self bulkSetProperty:key value:value forModels:modelNames];
        }
    }
}

- (void)bulkEditSliderProperty:(NSString *)key
                         title:(NSString *)title
                       message:(NSString *)message
                      minValue:(double)minValue
                      maxValue:(double)maxValue
                  defaultValue:(double)defaultValue
                   integerOnly:(BOOL)integerOnly
                     forModels:(NSArray<NSString *> *)modelNames {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 30)];
    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(0, 0, 190, 20)];
    slider.minValue = minValue;
    slider.maxValue = maxValue;
    slider.doubleValue = defaultValue;
    if (integerOnly && (maxValue - minValue) <= 20) {
        slider.numberOfTickMarks = (NSInteger)(maxValue - minValue) + 1;
        slider.allowsTickMarkValuesOnly = YES;
    }

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(200, 2, 50, 20)];
    label.editable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    label.alignment = NSTextAlignmentRight;

    if (integerOnly) {
        label.stringValue = [NSString stringWithFormat:@"%ld", (long)slider.integerValue];
        [label bind:NSValueBinding toObject:slider withKeyPath:@"integerValue" options:nil];
    } else {
        label.stringValue = [NSString stringWithFormat:@"%.1f", slider.doubleValue];
        [label bind:NSValueBinding toObject:slider withKeyPath:@"doubleValue" options:nil];
    }

    [container addSubview:slider];
    [container addSubview:label];
    alert.accessoryView = container;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *value;
        if (integerOnly) {
            value = [NSString stringWithFormat:@"%ld", (long)slider.integerValue];
        } else {
            value = [NSString stringWithFormat:@"%.2f", slider.doubleValue];
        }
        [self bulkSetProperty:key value:value forModels:modelNames];
    }
}

- (void)bulkEditPickerProperty:(NSString *)key
                         title:(NSString *)title
                       message:(NSString *)message
                       options:(NSArray<NSString *> *)options
                      useIndex:(BOOL)useIndex
                     forModels:(NSArray<NSString *> *)modelNames {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 250, 25) pullsDown:NO];
    [popup addItemsWithTitles:options];
    alert.accessoryView = popup;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *value;
        if (useIndex) {
            value = [NSString stringWithFormat:@"%ld", (long)popup.indexOfSelectedItem];
        } else {
            value = popup.titleOfSelectedItem;
            if ([value isEqualToString:@"(None)"]) {
                value = @"";
            }
        }
        [self bulkSetProperty:key value:value forModels:modelNames];
    }
}

#pragma mark - Copy/Cut/Paste

- (NSArray<NSString *> *)selectedModelNamesForClipboard {
    NSArray<NSString *> *treeSelection = [_modelTreeController selectedModelNames];
    if (treeSelection.count > 0) {
        return treeSelection;
    }
    NSString *previewSelection = _previewView.selectedModelName;
    if (previewSelection) {
        return @[previewSelection];
    }
    return @[];
}

- (NSString *)generateUniquePasteName:(NSString *)baseName {
    NSArray<NSString *> *existingNames = [_engineBridge getModelNames];
    NSSet<NSString *> *existingSet = [NSSet setWithArray:existingNames];

    NSString *candidate = [NSString stringWithFormat:@"%@_copy", baseName];
    if (![existingSet containsObject:candidate]) {
        return candidate;
    }
    for (int i = 2; i <= 1000; i++) {
        candidate = [NSString stringWithFormat:@"%@_copy-%d", baseName, i];
        if (![existingSet containsObject:candidate]) {
            return candidate;
        }
    }
    return [NSString stringWithFormat:@"%@_copy-%u", baseName, arc4random()];
}

- (void)copy:(id)sender {
    NSArray<NSString *> *selectedNames = [self selectedModelNamesForClipboard];
    if (selectedNames.count == 0) return;

    NSMutableArray<NSDictionary *> *modelsData = [[NSMutableArray alloc] init];
    for (NSString *name in selectedNames) {
        NSDictionary *data = [_engineBridge getModelData:name];
        if (data && data.count > 0) {
            [modelsData addObject:data];
        }
    }

    if (modelsData.count == 0) return;

    NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:modelsData
                                             requiringSecureCoding:NO
                                                             error:nil];
    if (!archived) {
        NSLog(@"XLLayoutViewController: Failed to archive model data for clipboard");
        return;
    }

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setData:archived forType:XLModelPasteboardType];

    NSLog(@"XLLayoutViewController: Copied %lu model(s) to clipboard", (unsigned long)modelsData.count);
}

- (void)cut:(id)sender {
    NSArray<NSString *> *selectedNames = [self selectedModelNamesForClipboard];
    if (selectedNames.count == 0) return;

    [self copy:sender];

    for (NSString *name in selectedNames) {
        NSDictionary *modelData = [_engineBridge getModelData:name];
        BOOL success = [_engineBridge deleteModel:name];
        if (success) {
            [_undoController registerModelDeleted:name modelData:modelData];
        }
    }

    [self clearSelection];
    [_modelTreeController reloadData];
    [_previewView reloadModels];

    NSLog(@"XLLayoutViewController: Cut %lu model(s)", (unsigned long)selectedNames.count);
}

- (void)paste:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSData *archived = [pb dataForType:XLModelPasteboardType];
    if (!archived) return;

    NSSet *allowedClasses = [NSSet setWithArray:@[
        [NSArray class], [NSDictionary class], [NSString class], [NSNumber class]
    ]];
    NSArray<NSDictionary *> *modelsData = [NSKeyedUnarchiver unarchivedObjectOfClasses:allowedClasses
                                                                              fromData:archived
                                                                                 error:nil];
    if (!modelsData || modelsData.count == 0) {
        NSLog(@"XLLayoutViewController: Failed to unarchive model data from clipboard");
        return;
    }

    NSString *lastPastedName = nil;

    for (NSDictionary *modelData in modelsData) {
        NSString *originalName = modelData[@"name"];
        if (!originalName) continue;

        NSString *newName = [self generateUniquePasteName:originalName];
        NSMutableDictionary *pasteData = [modelData mutableCopy];

        NSMutableDictionary *props = [pasteData[@"properties"] mutableCopy];
        if (props) {
            // Offset X position to avoid stacking on the original
            float posX = [props[@"WorldPosX"] floatValue];
            props[@"WorldPosX"] = [NSString stringWithFormat:@"%f", posX + kPastePositionOffset];

            // Reset controller assignment so pasted model doesn't conflict
            [props removeObjectForKey:@"Controller"];
            [props removeObjectForKey:@"ModelChain"];
            props[@"StartChannel"] = @"1";

            // Unlock pasted model
            props[@"Locked"] = @"0";

            pasteData[@"properties"] = props;
        }

        BOOL success = [_engineBridge createModelFromData:pasteData withName:newName];
        if (success) {
            NSDictionary *createdData = [_engineBridge getModelData:newName];
            [_undoController registerModelCreated:newName modelData:createdData];
            lastPastedName = newName;
            NSLog(@"XLLayoutViewController: Pasted model '%@' as '%@'", originalName, newName);
        } else {
            NSLog(@"XLLayoutViewController: Failed to paste model '%@' as '%@'", originalName, newName);
        }
    }

    [_modelTreeController reloadData];
    [_previewView reloadModels];

    if (lastPastedName) {
        [self selectModel:lastPastedName];
        [_modelTreeController selectModelWithName:lastPastedName];
    }
}

- (void)delete:(id)sender {
    NSArray<NSString *> *selectedNames = [self selectedModelNamesForClipboard];
    if (selectedNames.count == 0) return;

    for (NSString *name in selectedNames) {
        NSDictionary *modelData = [_engineBridge getModelData:name];
        BOOL success = [_engineBridge deleteModel:name];
        if (success) {
            [_undoController registerModelDeleted:name modelData:modelData];
        }
    }

    [self clearSelection];
    [_modelTreeController reloadData];
    [_previewView reloadModels];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;

    if (action == @selector(copy:) || action == @selector(cut:) || action == @selector(delete:)) {
        return [self selectedModelNamesForClipboard].count > 0;
    }

    if (action == @selector(paste:)) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        return [pb.types containsObject:XLModelPasteboardType];
    }

    if (action == @selector(undo:)) {
        return [_undoController canUndo];
    }

    if (action == @selector(redo:)) {
        return [_undoController canRedo];
    }

    if (action == @selector(importModels:)) {
        return YES;
    }

    if (action == @selector(importModelsFromRGBEffects:)) {
        return YES;
    }

    if (action == @selector(importLORS5Models:)) {
        return YES;
    }

    if (action == @selector(exportModelToFile:)) {
        return [_modelTreeController selectedModelName] != nil;
    }

    return YES;
}

#pragma mark - Undo/Redo Actions

- (void)undo {
    [_undoController undo];
}

- (void)redo {
    [_undoController redo];
}

- (BOOL)canUndo {
    return [_undoController canUndo];
}

- (BOOL)canRedo {
    return [_undoController canRedo];
}

#pragma mark - First Responder & Keyboard Handling

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    if (![_keyboardHandler handleKeyEvent:event inScope:XLKeyScopeLayout]) {
        [super keyDown:event];
    }
}

- (void)showFolderDidChange:(NSNotification *)notification {
    NSString *newPath = notification.userInfo[@"path"];
    if (newPath) {
        [_keyboardHandler setShowFolderPath:newPath];
    } else {
        NSString *showFolder = [self.engineBridge getShowFolderPath];
        [_keyboardHandler setShowFolderPath:showFolder];
    }
}

#pragma mark - XLKeyboardActionDelegate

- (BOOL)performKeyAction:(NSString *)actionType
              effectName:(NSString *)effectName
          effectSettings:(NSString *)effectSettings
                 inScope:(XLKeyScope)scope {

    NSLog(@"XLLayoutViewController performKeyAction: actionType='%@', scope=%ld",
          actionType, (long)scope);

    // Undo/Redo (available in all scopes)
    if ([actionType isEqualToString:@"UNDO"]) {
        [_undoController undo];
        return YES;
    }
    if ([actionType isEqualToString:@"REDO"]) {
        [_undoController redo];
        return YES;
    }

    // Model lock/unlock actions
    if ([actionType isEqualToString:@"LOCK_MODEL"]) {
        NSString *modelName = _previewView.selectedModelName;
        if (modelName) {
            [self previewView:_previewView didRequestLockModel:modelName lock:YES];
        }
        return YES;
    }
    if ([actionType isEqualToString:@"UNLOCK_MODEL"]) {
        NSString *modelName = _previewView.selectedModelName;
        if (modelName) {
            [self previewView:_previewView didRequestLockModel:modelName lock:NO];
        }
        return YES;
    }

    // Model alignment actions
    if ([actionType isEqualToString:@"MODEL_ALIGN_TOP"]) {
        [self previewView:_previewView didRequestAlignModels:@"Top"];
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_ALIGN_BOTTOM"]) {
        [self previewView:_previewView didRequestAlignModels:@"Bottom"];
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_ALIGN_LEFT"]) {
        [self previewView:_previewView didRequestAlignModels:@"Left"];
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_ALIGN_RIGHT"]) {
        [self previewView:_previewView didRequestAlignModels:@"Right"];
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_ALIGN_CENTER_VERT"]) {
        [self previewView:_previewView didRequestAlignModels:@"Vertical Center"];
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_ALIGN_CENTER_HORIZ"]) {
        [self previewView:_previewView didRequestAlignModels:@"Horizontal Center"];
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_ALIGN_BACKS"]) {
        [self previewView:_previewView didRequestAlignModels:@"Back"];
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_ALIGN_FRONTS"]) {
        [self previewView:_previewView didRequestAlignModels:@"Front"];
        return YES;
    }

    // Model distribute actions
    if ([actionType isEqualToString:@"MODEL_DISTRIBUTE_HORIZ"]) {
        [self previewView:_previewView didRequestDistributeModels:@"Horizontal"];
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_DISTRIBUTE_VERT"]) {
        [self previewView:_previewView didRequestDistributeModels:@"Vertical"];
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_DISTRIBUTE_DEPTH"]) {
        [self previewView:_previewView didRequestDistributeModels:@"Depth"];
        return YES;
    }

    // Model flip actions
    if ([actionType isEqualToString:@"MODEL_FLIP_HORIZ"]) {
        NSString *modelName = _previewView.selectedModelName;
        if (modelName) {
            [self previewView:_previewView didRequestFlipModel:modelName horizontal:YES];
        }
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_FLIP_VERT"]) {
        NSString *modelName = _previewView.selectedModelName;
        if (modelName) {
            [self previewView:_previewView didRequestFlipModel:modelName horizontal:NO];
        }
        return YES;
    }

    // --- Selection and Grouping ---

    if ([actionType isEqualToString:@"SELECT_ALL_MODELS"]) {
        NSOutlineView *outlineView = _modelTreeController.outlineView;
        NSInteger rowCount = outlineView.numberOfRows;
        if (rowCount > 0) {
            NSMutableIndexSet *indexSet = [[NSMutableIndexSet alloc] init];
            for (NSInteger row = 0; row < rowCount; row++) {
                [indexSet addIndex:(NSUInteger)row];
            }
            [outlineView selectRowIndexes:indexSet byExtendingSelection:NO];
            NSLog(@"XLLayoutViewController: Selected all %ld rows in model tree", (long)rowCount);
        }
        return YES;
    }

    if ([actionType isEqualToString:@"GROUP_MODELS"]) {
        NSArray<NSString *> *selectedNames = [_modelTreeController selectedModelNames];
        if (selectedNames.count >= 1) {
            if ([_modelTreeController.delegate respondsToSelector:@selector(modelTree:didRequestGroupModels:)]) {
                [_modelTreeController.delegate modelTree:_modelTreeController didRequestGroupModels:selectedNames];
            }
        } else {
            NSLog(@"XLLayoutViewController: GROUP_MODELS — no models selected");
        }
        return YES;
    }

    if ([actionType isEqualToString:@"MODEL_ALIGN_GROUND"]) {
        [self previewView:_previewView didRequestAlignModels:@"Align With Ground"];
        return YES;
    }

    // --- Model Editing Dialogs ---

    if ([actionType isEqualToString:@"MODEL_SUBMODELS"]) {
        NSLog(@"TODO: MODEL_SUBMODELS not yet implemented");
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_FACES"]) {
        NSLog(@"TODO: MODEL_FACES not yet implemented");
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_STATES"]) {
        NSLog(@"TODO: MODEL_STATES not yet implemented");
        return YES;
    }
    if ([actionType isEqualToString:@"MODEL_MODELDATA"]) {
        NSLog(@"TODO: MODEL_MODELDATA not yet implemented");
        return YES;
    }

    // --- Layout Misc ---

    if ([actionType isEqualToString:@"WIRING_VIEW"]) {
        NSLog(@"TODO: WIRING_VIEW not yet implemented");
        return YES;
    }
    if ([actionType isEqualToString:@"EXPORT_MODEL_CAD"]) {
        NSLog(@"TODO: EXPORT_MODEL_CAD not yet implemented");
        return YES;
    }
    if ([actionType isEqualToString:@"EXPORT_LAYOUT_DXF"]) {
        NSLog(@"TODO: EXPORT_LAYOUT_DXF not yet implemented");
        return YES;
    }
    if ([actionType isEqualToString:@"NODE_LAYOUT"]) {
        NSLog(@"TODO: NODE_LAYOUT not yet implemented");
        return YES;
    }
    if ([actionType isEqualToString:@"SAVE_LAYOUT"]) {
        NSLog(@"TODO: SAVE_LAYOUT not yet implemented");
        return YES;
    }

    NSLog(@"XLLayoutViewController: Unhandled layout key action: %@", actionType);
    return NO;
}

#pragma mark - Model Group Management

- (void)modelTreeDidRequestManageGroups:(XLModelTreeViewController *)controller {
    [self showModelGroupManagement];
}

- (void)showModelGroupManagement {
    if (_modelGroupWindow) {
        [_modelGroupWindow.window makeKeyAndOrderFront:nil];
        return;
    }

    _modelGroupWindow = [[XLModelGroupWindow alloc] init];
    _modelGroupWindow.engineBridge = _engineBridge;

    __weak typeof(self) weakSelf = self;
    [_modelGroupWindow showWithCompletion:^(BOOL changed) {
        if (changed) {
            [weakSelf.modelTreeController reloadData];
            [weakSelf.previewView reloadModels];
        }
        weakSelf.modelGroupWindow = nil;
    }];
}

@end
