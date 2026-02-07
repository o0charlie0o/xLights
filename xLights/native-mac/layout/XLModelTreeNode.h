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

#import <Foundation/Foundation.h>

/// Data model node for the model hierarchy tree.
///
/// Represents a single item in the NSOutlineView tree: a model group,
/// an individual model, or a submodel. Mirrors the hierarchy from
/// ModelManager (groups -> models -> submodels).
@interface XLModelTreeNode : NSObject

/// Display name of the model/group/submodel
@property (nonatomic, copy) NSString *name;

/// Model type string ("SingleLine", "Matrix", "Arch", "Custom", etc.)
@property (nonatomic, copy) NSString *modelType;

/// Number of channels this model uses
@property (nonatomic, assign) NSInteger channelCount;

/// Start channel string (e.g. "1" or ">ControllerName:1")
@property (nonatomic, copy) NSString *startChannel;

/// Numeric end channel (last channel number, 1-based)
@property (nonatomic, assign) NSInteger endChannel;

/// Controller connection string (e.g. "ControllerName:1")
@property (nonatomic, copy) NSString *controllerConnection;

/// Child nodes (models in a group, or submodels in a model)
@property (nonatomic, strong) NSMutableArray<XLModelTreeNode *> *children;

/// Whether this node is a model group
@property (nonatomic, assign) BOOL isGroup;

/// Whether this node is a submodel
@property (nonatomic, assign) BOOL isSubmodel;

/// Whether this node is a shadow model
@property (nonatomic, assign) BOOL isShadowModel;

/// Name of the model this shadow model mirrors (empty string if not a shadow)
@property (nonatomic, copy) NSString *shadowModelFor;

/// SF Symbol name for this node's model type (computed from modelType)
@property (nonatomic, readonly) NSString *iconName;

/// Weak reference to parent node (nil for root-level items)
@property (nonatomic, weak) XLModelTreeNode *parent;

/// Convenience constructor for a model node
+ (instancetype)nodeWithName:(NSString *)name type:(NSString *)modelType;

/// Convenience constructor for a group node
+ (instancetype)groupNodeWithName:(NSString *)name;

/// Convenience constructor for a submodel node
+ (instancetype)submodelNodeWithName:(NSString *)name parentType:(NSString *)parentType;

/// Add a child node (sets the child's parent to self)
- (void)addChild:(XLModelTreeNode *)child;

/// Remove a child node (clears the child's parent)
- (void)removeChild:(XLModelTreeNode *)child;

/// Insert a child at a specific index
- (void)insertChild:(XLModelTreeNode *)child atIndex:(NSUInteger)index;

/// Whether this is a leaf node (no children)
- (BOOL)isLeaf;

/// Number of children
- (NSUInteger)childCount;

/// Child at index
- (XLModelTreeNode *)childAtIndex:(NSUInteger)index;

@end
