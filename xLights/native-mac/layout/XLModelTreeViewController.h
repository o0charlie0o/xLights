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

/// User requested importing a model from file
- (void)modelTreeDidRequestImportModel:(XLModelTreeViewController *)controller;

/// User requested locking/unlocking a model
- (void)modelTree:(XLModelTreeViewController *)controller didRequestLockModel:(NSString *)modelName locked:(BOOL)locked;

/// User requested flipping a model
- (void)modelTree:(XLModelTreeViewController *)controller didRequestFlipModel:(NSString *)modelName horizontal:(BOOL)horizontal;

/// User requested adding models to an existing group
- (void)modelTree:(XLModelTreeViewController *)controller didRequestAddModels:(NSArray<NSString *> *)modelNames toGroup:(NSString *)groupName;

/// User requested removing a model from a group
- (void)modelTree:(XLModelTreeViewController *)controller didRequestRemoveModel:(NSString *)modelName fromGroup:(NSString *)groupName;

/// User requested cloning a group
- (void)modelTree:(XLModelTreeViewController *)controller didRequestCloneGroup:(NSString *)groupName;

/// User requested replacing a model with another model.
/// The replacement model takes the target's name and (optionally) its position, controller, and submodels.
/// @param targetModelName The model being replaced (will be deleted)
/// @param replacementModelName The model replacing the target (will be renamed to target's name)
/// @param options Dictionary with keys: copyStartChannel, copyPosition, mergeSubmodels (all BOOL)
- (void)modelTree:(XLModelTreeViewController *)controller
  didRequestReplaceModel:(NSString *)targetModelName
               withModel:(NSString *)replacementModelName
                 options:(NSDictionary *)options;

/// User requested opening the model group management window
- (void)modelTreeDidRequestManageGroups:(XLModelTreeViewController *)controller;

@end

/// NSOutlineView-based model hierarchy tree for the Layout tab.
///
/// Displays the model hierarchy: groups -> models -> submodels.
/// Supports drag-and-drop reordering, context menus, search filtering,
/// and multi-selection.
///
/// Columns:
///   - Name (with icon based on model type)
///   - Start Chan (start channel string, right-aligned)
///   - End Chan (end channel number, right-aligned)
///   - Ctrlr Conn (controller:port assignment)
/// Notification posted when the 3D Objects list selection changes.
/// userInfo contains @"objectName" (NSString, may be nil).
extern NSNotificationName const XLViewObjectSelectionDidChangeNotification;

@interface XLModelTreeViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate, NSMenuDelegate, NSTableViewDataSource, NSTableViewDelegate>

/// The outline view displaying the model tree
@property (nonatomic, strong, readonly) NSOutlineView *outlineView;

/// Delegate for tree actions
@property (nonatomic, weak) id<XLModelTreeDelegate> delegate;

/// Engine bridge for querying model data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Top-level items in the tree (groups and ungrouped models)
@property (nonatomic, copy) NSArray<XLModelTreeNode *> *rootNodes;

/// Whether the layout is in 3D mode (controls visibility of 3D Objects tab)
@property (nonatomic, assign) BOOL show3D;

/// Reload data from the engine bridge
- (void)reloadData;

/// Reload the 3D Objects list from the engine bridge
- (void)reloadViewObjects;

/// Programmatically select a model by name (for syncing with preview)
- (void)selectModelWithName:(NSString *)name;

/// Programmatically select multiple models by name (for syncing with preview)
- (void)selectModelsWithNames:(NSArray<NSString *> *)names;

/// Expand all tree items
- (void)expandAll;

/// Collapse all tree items
- (void)collapseAll;

/// The name of the currently selected model (nil if no selection or multi-select)
- (NSString *)selectedModelName;

/// Names of all currently selected models
- (NSArray<NSString *> *)selectedModelNames;

@end
