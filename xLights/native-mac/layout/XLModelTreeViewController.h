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

@class XLModelTreeNode;
@class XLModelTreeViewController;
@class XLEngineBridge;

/// Delegate protocol for model tree view controller events.
///
/// All delegate methods are called on the main thread.
@protocol XLModelTreeDelegate <NSObject>

@optional

/// Selection changed in the model tree
- (void)modelTree:(XLModelTreeViewController *)controller didSelectModel:(NSString *)modelName;

/// A model was moved via drag-and-drop
- (void)modelTree:(XLModelTreeViewController *)controller
     didMoveModel:(NSString *)modelName
          toGroup:(NSString *)groupName
          atIndex:(NSInteger)index;

/// User requested adding a new model of the given type
- (void)modelTree:(XLModelTreeViewController *)controller didRequestAddModelOfType:(NSString *)modelType;

/// User requested deleting a model
- (void)modelTree:(XLModelTreeViewController *)controller didRequestDeleteModel:(NSString *)modelName;

/// User requested duplicating a model
- (void)modelTree:(XLModelTreeViewController *)controller didRequestDuplicateModel:(NSString *)modelName;

/// User requested grouping the selected models
- (void)modelTree:(XLModelTreeViewController *)controller didRequestGroupModels:(NSArray<NSString *> *)modelNames;

/// User requested ungrouping a model group
- (void)modelTree:(XLModelTreeViewController *)controller didRequestUngroupModel:(NSString *)groupName;

/// User requested renaming a model
- (void)modelTree:(XLModelTreeViewController *)controller didRequestRenameModel:(NSString *)oldName toName:(NSString *)newName;

@end

/// NSOutlineView-based model hierarchy tree for the Layout tab.
///
/// Displays the model hierarchy: groups -> models -> submodels.
/// Supports drag-and-drop reordering, context menus, search filtering,
/// and multi-selection.
///
/// Columns:
///   - Name (with icon based on model type)
///   - Type (model type string)
///   - Channels (channel count, right-aligned)
///   - Controller (controller assignment)
@interface XLModelTreeViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate>

/// The outline view displaying the model tree
@property (nonatomic, strong, readonly) NSOutlineView *outlineView;

/// Delegate for tree actions
@property (nonatomic, weak) id<XLModelTreeDelegate> delegate;

/// Engine bridge for querying model data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Top-level items in the tree (groups and ungrouped models)
@property (nonatomic, copy) NSArray<XLModelTreeNode *> *rootNodes;

/// Reload data from the engine bridge
- (void)reloadData;

/// Programmatically select a model by name (for syncing with preview)
- (void)selectModelWithName:(NSString *)name;

/// Expand all tree items
- (void)expandAll;

/// Collapse all tree items
- (void)collapseAll;

/// The name of the currently selected model (nil if no selection or multi-select)
- (NSString *)selectedModelName;

/// Names of all currently selected models
- (NSArray<NSString *> *)selectedModelNames;

@end
