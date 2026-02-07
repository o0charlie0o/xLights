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
#import "layout/XLManipulationHandlesRenderer.h"
#import "layout/XLModelPropertiesView.h"
#import "layout/XLLayoutUndoController.h"
#import "input/XLKeyboardHandler.h"

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

@interface XLLayoutViewController ()

@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) XLModelCreationSheet *modelCreationSheet;
@property (nonatomic, strong) XLModelImportSheet *modelImportSheet;
@property (nonatomic, strong) NSScrollView *propertiesScrollView;
@property (nonatomic, strong, readwrite) XLLayoutUndoController *undoController;
@property (nonatomic, assign) XLToolMode manipulationToolMode;

/// Nudge undo coalescing: accumulate rapid nudges into a single undo operation
@property (nonatomic, assign) BOOL nudgeUndoGroupOpen;
@property (nonatomic, strong) NSTimer *nudgeCoalesceTimer;
@property (nonatomic, copy) NSString *nudgeModelName;
@property (nonatomic, assign) float nudgeStartX;
@property (nonatomic, assign) float nudgeStartY;

/// Layout group selector and toolbar
@property (nonatomic, strong, readwrite) NSPopUpButton *layoutGroupSelector;
@property (nonatomic, copy, readwrite) NSString *currentLayoutGroup;

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
    ]];

    // Split view: model tree (left) | preview (center) | properties (right)
    _splitView = [[NSSplitView alloc] initWithFrame:view.bounds];
    _splitView.translatesAutoresizingMaskIntoConstraints = NO;
    _splitView.vertical = YES;
    _splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitView.delegate = (id<NSSplitViewDelegate>)self;
    [view addSubview:_splitView];

    [NSLayoutConstraint activateConstraints:@[
        [_splitView.topAnchor constraintEqualToAnchor:toolbarView.bottomAnchor],
        [_splitView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [_splitView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_splitView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
    ]];

    // Model tree (left sidebar)
    _modelTreeController = [[XLModelTreeViewController alloc] init];
    _modelTreeController.delegate = self;
    _modelTreeController.engineBridge = self.engineBridge;

    NSView *treeView = _modelTreeController.view;
    treeView.translatesAutoresizingMaskIntoConstraints = NO;
    [_splitView addSubview:treeView];

    // Preview (center)
    _previewView = [[XLMetalPreviewView alloc] initWithFrame:NSZeroRect];
    _previewView.translatesAutoresizingMaskIntoConstraints = NO;
    _previewView.delegate = self;
    _previewView.show3D = YES;
    _previewView.showGrid = YES;
    [_splitView addSubview:_previewView];

    // Properties (right sidebar) - in a scroll view
    _propertiesView = [[XLModelPropertiesView alloc] initWithFrame:NSZeroRect];
    _propertiesView.translatesAutoresizingMaskIntoConstraints = NO;
    _propertiesView.delegate = self;
    _propertiesView.engineBridge = self.engineBridge;

    _propertiesScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _propertiesScrollView.translatesAutoresizingMaskIntoConstraints = NO;
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

    [_splitView addSubview:_propertiesScrollView];

    // Set initial split positions
    CGFloat totalWidth = view.bounds.size.width;
    CGFloat previewWidth = totalWidth - kModelTreeDefaultWidth - kPropertiesDefaultWidth;
    [_splitView setPosition:kModelTreeDefaultWidth ofDividerAtIndex:0];
    [_splitView setPosition:kModelTreeDefaultWidth + previewWidth ofDividerAtIndex:1];

    self.view = view;
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

#pragma mark - NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex {
    if (dividerIndex == 0) {
        // Left divider: minimum for model tree
        return kModelTreeMinWidth;
    } else {
        // Right divider: minimum preview width (leave room for properties)
        return kModelTreeMinWidth + 300; // model tree + min preview
    }
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex {
    if (dividerIndex == 0) {
        // Left divider: leave room for preview and properties
        return proposedMax - 300 - kPropertiesMinWidth;
    } else {
        // Right divider: leave room for properties
        return proposedMax - kPropertiesMinWidth;
    }
}

#pragma mark - XLMetalPreviewDelegate

- (void)previewView:(XLMetalPreviewView *)view didSelectModel:(NSString *)modelName {
    if (modelName) {
        [_modelTreeController selectModelWithName:modelName];
    }
}

- (void)previewView:(XLMetalPreviewView *)view didChangeCamera:(XLCameraController *)camera {
}

#pragma mark - XLModelTreeDelegate

- (void)modelTree:(XLModelTreeViewController *)controller didSelectModel:(NSString *)modelName {
    NSLog(@"XLLayoutViewController: Model selected from tree: %@", modelName);
    [self selectModel:modelName];
}

- (void)modelTree:(XLModelTreeViewController *)controller didMoveModel:(NSString *)modelName toGroup:(NSString *)groupName atIndex:(NSInteger)index {
    NSLog(@"XLLayoutViewController: Model '%@' moved to group '%@' at index %ld", modelName, groupName, (long)index);
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
            // Select first imported model
            [weakSelf.modelTreeController selectModelWithName:importedModelNames.firstObject];
        }
        weakSelf.modelImportSheet = nil;
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

        // Extract render dimensions
        float renderWidth = [modelInfo[@"RenderWidth"] floatValue] ?: 100.0f;
        float renderHeight = [modelInfo[@"RenderHeight"] floatValue] ?: 100.0f;
        float renderDepth = [modelInfo[@"RenderDepth"] floatValue] ?: 100.0f;

        BOOL isLocked = [modelInfo[@"Locked"] boolValue];
        BOOL supportsZScaling = [modelInfo[@"SupportsZScaling"] boolValue];

        // Bounding box (use render dimensions as approximation)
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

@end
