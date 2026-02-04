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

static const CGFloat kModelTreeMinWidth = 200.0;
static const CGFloat kModelTreeDefaultWidth = 280.0;
static const CGFloat kPropertiesMinWidth = 200.0;
static const CGFloat kPropertiesDefaultWidth = 260.0;

@interface XLLayoutViewController ()

@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) XLModelCreationSheet *modelCreationSheet;
@property (nonatomic, strong) XLModelImportSheet *modelImportSheet;
@property (nonatomic, strong) NSScrollView *propertiesScrollView;
@property (nonatomic, strong, readwrite) XLLayoutUndoController *undoController;
@property (nonatomic, assign) XLToolMode manipulationToolMode;

@end

@implementation XLLayoutViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 600)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor colorWithWhite:0.16 alpha:1.0] CGColor];

    // Split view: model tree (left) | preview (center) | properties (right)
    _splitView = [[NSSplitView alloc] initWithFrame:view.bounds];
    _splitView.translatesAutoresizingMaskIntoConstraints = NO;
    _splitView.vertical = YES;
    _splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitView.delegate = (id<NSSplitViewDelegate>)self;
    [view addSubview:_splitView];

    [NSLayoutConstraint activateConstraints:@[
        [_splitView.topAnchor constraintEqualToAnchor:view.topAnchor],
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

    [_modelTreeController reloadData];
}

- (void)viewDidAppear {
    [super viewDidAppear];
    [_previewView startRenderLoop];
}

- (void)viewDidDisappear {
    [super viewDidDisappear];
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

@end
