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

static const CGFloat kModelTreeMinWidth = 200.0;
static const CGFloat kModelTreeDefaultWidth = 280.0;

@interface XLLayoutViewController ()

@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) XLModelCreationSheet *modelCreationSheet;
@property (nonatomic, strong) XLModelImportSheet *modelImportSheet;

@end

@implementation XLLayoutViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor colorWithWhite:0.16 alpha:1.0] CGColor];

    // Split view: model tree (left) | preview (right)
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

    // Model tree (left)
    _modelTreeController = [[XLModelTreeViewController alloc] init];
    _modelTreeController.delegate = self;
    _modelTreeController.engineBridge = self.engineBridge;

    NSView *treeView = _modelTreeController.view;
    treeView.translatesAutoresizingMaskIntoConstraints = NO;
    [_splitView addSubview:treeView];

    // Preview (right)
    _previewView = [[XLMetalPreviewView alloc] initWithFrame:NSZeroRect];
    _previewView.translatesAutoresizingMaskIntoConstraints = NO;
    _previewView.delegate = self;
    _previewView.show3D = YES;
    _previewView.showGrid = YES;
    [_splitView addSubview:_previewView];

    // Set initial split position
    [_splitView setPosition:kModelTreeDefaultWidth ofDividerAtIndex:0];

    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
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
}

#pragma mark - NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex {
    return kModelTreeMinWidth;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex {
    return proposedMax - 400; // Min width for preview
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

    // Delete via engine bridge
    BOOL success = [_engineBridge deleteModel:modelName];
    if (success) {
        [_modelTreeController reloadData];
    }
}

- (void)modelTree:(XLModelTreeViewController *)controller didRequestDuplicateModel:(NSString *)modelName {
    NSLog(@"XLLayoutViewController: Duplicate model '%@' requested", modelName);

    // Duplicate via engine bridge
    BOOL success = [_engineBridge duplicateModel:modelName];
    if (success) {
        [_modelTreeController reloadData];
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
        if (created) {
            [weakSelf.modelTreeController reloadData];
            if (modelName) {
                [weakSelf.modelTreeController selectModelWithName:modelName];
            }
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

@end
