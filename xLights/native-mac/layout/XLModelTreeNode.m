/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLModelTreeNode.h"

@implementation XLModelTreeNode

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _children = [[NSMutableArray alloc] init];
        _modelType = @"";
        _name = @"";
        _channelCount = 0;
        _shadowModelFor = @"";
    }
    return self;
}

+ (instancetype)nodeWithName:(NSString *)name type:(NSString *)modelType {
    XLModelTreeNode *node = [[XLModelTreeNode alloc] init];
    node.name = name;
    node.modelType = modelType;
    node.isGroup = NO;
    node.isSubmodel = NO;
    return node;
}

+ (instancetype)groupNodeWithName:(NSString *)name {
    XLModelTreeNode *node = [[XLModelTreeNode alloc] init];
    node.name = name;
    node.modelType = @"Group";
    node.isGroup = YES;
    node.isSubmodel = NO;
    return node;
}

+ (instancetype)submodelNodeWithName:(NSString *)name parentType:(NSString *)parentType {
    XLModelTreeNode *node = [[XLModelTreeNode alloc] init];
    node.name = name;
    node.modelType = parentType;
    node.isGroup = NO;
    node.isSubmodel = YES;
    return node;
}

#pragma mark - Icon Name

- (NSString *)iconName {
    if (_isGroup) {
        return @"folder";
    }
    if (_isSubmodel) {
        return @"square.on.square";
    }
    if (_isShadowModel) {
        return @"rectangle.on.rectangle";
    }

    static NSDictionary<NSString *, NSString *> *iconMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        iconMap = @{
            @"SingleLine":   @"line.horizontal",
            @"Poly Line":    @"line.diagonal",
            @"Matrix":       @"rectangle.grid.2x2",
            @"Arch":         @"rainbow",
            @"Arches":       @"rainbow",
            @"Custom":       @"star",
            @"Tree":         @"tree",
            @"Spinner":      @"arrow.triangle.2.circlepath",
            @"Sphere":       @"globe",
            @"Circle":       @"circle",
            @"Cube":         @"cube",
            @"Icicles":      @"line.3.horizontal.decrease",
            @"Candy Canes":  @"cane",
            @"Star":         @"star.fill",
            @"Window Frame": @"rectangle",
            @"Wreath":       @"circle.dashed",
            @"Channel Block":@"square.stack.3d.up",
            @"Image":        @"photo",
            @"DmxMovingHead":@"light.max",
            @"DmxGeneral":   @"light.min",
            @"DmxServo":     @"gearshape",
            @"DmxSkull":     @"theatermasks",
            @"DmxFloodlight":@"flashlight.on.fill",
            @"DmxFloodArea": @"rectangle.and.hand.point.up.left",
        };
    });

    NSString *icon = iconMap[_modelType];
    return icon ?: @"lightbulb";
}

#pragma mark - Child Management

- (void)addChild:(XLModelTreeNode *)child {
    child.parent = self;
    [_children addObject:child];
}

- (void)removeChild:(XLModelTreeNode *)child {
    child.parent = nil;
    [_children removeObject:child];
}

- (void)insertChild:(XLModelTreeNode *)child atIndex:(NSUInteger)index {
    child.parent = self;
    if (index >= _children.count) {
        [_children addObject:child];
    } else {
        [_children insertObject:child atIndex:index];
    }
}

- (BOOL)isLeaf {
    return _children.count == 0;
}

- (NSUInteger)childCount {
    return _children.count;
}

- (XLModelTreeNode *)childAtIndex:(NSUInteger)index {
    if (index >= _children.count) return nil;
    return _children[index];
}

#pragma mark - Description

- (NSString *)description {
    NSString *type = _isGroup ? @"Group" : (_isSubmodel ? @"Submodel" : _modelType);
    return [NSString stringWithFormat:@"<%@: %@ (%@, %ld ch, %lu children)>",
            NSStringFromClass([self class]), _name, type, (long)_channelCount, (unsigned long)_children.count];
}

@end
