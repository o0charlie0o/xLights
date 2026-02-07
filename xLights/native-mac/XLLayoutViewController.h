#pragma once

/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import <Cocoa/Cocoa.h>
#import "layout/XLMetalPreviewView.h"
#import "layout/XLModelTreeViewController.h"
#import "layout/XLModelPropertiesView.h"
#import "layout/XLLayoutUndoController.h"
#import "input/XLKeyboardHandler.h"

@class XLEngineBridge;
@class XLKeyboardHandler;

/// View controller for the Layout/Preview tab.
///
/// Displays Metal-based 3D preview, model tree, and manipulation handles.
/// Layout: Left sidebar (model tree) | Center (Metal preview) | Right sidebar (properties)
/// The preview already uses Metal with integrated 2D/3D manipulation handles.
@interface XLLayoutViewController : NSViewController <XLMetalPreviewDelegate, XLModelTreeDelegate, XLModelPropertiesDelegate, XLLayoutUndoDelegate, XLKeyboardActionDelegate>

@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Keyboard handler for processing key bindings in layout scope.
@property (nonatomic, strong) XLKeyboardHandler *keyboardHandler;

/// The Metal preview view (3D model rendering surface)
@property (nonatomic, strong, readonly) XLMetalPreviewView *previewView;

/// The model tree view controller (left sidebar)
@property (nonatomic, strong, readonly) XLModelTreeViewController *modelTreeController;

/// The model properties view (right sidebar)
@property (nonatomic, strong, readonly) XLModelPropertiesView *propertiesView;

/// The undo controller for model manipulation operations
@property (nonatomic, strong, readonly) XLLayoutUndoController *undoController;

/// The layout group selector (preview chooser)
@property (nonatomic, strong, readonly) NSPopUpButton *layoutGroupSelector;

/// The currently active layout group name
@property (nonatomic, copy, readonly) NSString *currentLayoutGroup;

/// Show the model creation sheet for a given model type
- (void)showModelCreationSheetForType:(NSString *)modelType;

/// Show the model import sheet
- (void)showModelImportSheet;

/// Select a model and show its manipulation handles
- (void)selectModel:(NSString *)modelName;

/// Clear model selection
- (void)clearSelection;

/// Set the manipulation tool mode: 0=translate, 1=scale, 2=rotate
- (void)setToolMode:(NSInteger)mode;

/// Set the active manipulation axis: -1=none, 0=X, 1=Y, 2=Z
- (void)setActiveAxis:(NSInteger)axis;

/// Toggle between tool modes (translate -> scale -> rotate)
- (void)toggleToolMode;

/// Toggle between 2D and 3D view modes
- (void)toggle2D3DMode;

/// Configure snapping options
- (void)setGridSnapSize:(float)snapSize;
- (void)setAngleSnapDegrees:(float)angleDegrees;
- (void)setEdgeSnapEnabled:(BOOL)enabled;

/// Undo the last model manipulation
- (void)undo;

/// Redo the last undone model manipulation
- (void)redo;

/// Returns YES if undo is available
- (BOOL)canUndo;

/// Returns YES if redo is available
- (BOOL)canRedo;

@end
