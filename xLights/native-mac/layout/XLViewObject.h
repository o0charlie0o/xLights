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
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

/// View object type identifiers matching legacy xLights view object types
typedef NS_ENUM(NSInteger, XLViewObjectType) {
    XLViewObjectTypeImage = 0,
    XLViewObjectTypeGridlines,
    XLViewObjectTypeTerrain,
    XLViewObjectTypeRuler,
    XLViewObjectTypeMesh,
};

/// A view object is a decorative/reference item placed in the 3D layout preview.
/// Unlike models, view objects have no channels or effects — they are visual aids
/// such as image overlays, gridlines, terrain meshes, rulers, and 3D meshes.
@interface XLViewObject : NSObject

#pragma mark - Identity

/// Unique name for this view object
@property (nonatomic, copy) NSString *name;

/// The type of view object
@property (nonatomic, assign) XLViewObjectType objectType;

/// Whether this object is active/visible
@property (nonatomic, assign) BOOL active;

#pragma mark - Transform

/// World-space position (center of the object)
@property (nonatomic, assign) simd_float3 position;

/// Scale factors
@property (nonatomic, assign) simd_float3 scale;

/// Rotation in degrees (x, y, z)
@property (nonatomic, assign) simd_float3 rotation;

#pragma mark - Image Object Properties

/// File path for image objects
@property (nonatomic, copy, nullable) NSString *imagePath;

/// Transparency (0-100, where 0 = opaque)
@property (nonatomic, assign) NSInteger transparency;

/// Brightness (0-100)
@property (nonatomic, assign) NSInteger brightness;

/// Image width in pixels (read from file)
@property (nonatomic, assign) NSInteger imageWidth;

/// Image height in pixels (read from file)
@property (nonatomic, assign) NSInteger imageHeight;

#pragma mark - Gridlines Object Properties

/// Grid line spacing in world units
@property (nonatomic, assign) NSInteger gridLineSpacing;

/// Grid width in world units
@property (nonatomic, assign) NSInteger gridWidth;

/// Grid height in world units
@property (nonatomic, assign) NSInteger gridHeight;

/// Grid line color (RGBA)
@property (nonatomic, assign) simd_float4 gridColor;

/// Whether to draw axis lines (colored X/Y axes at center)
@property (nonatomic, assign) BOOL gridShowAxis;

#pragma mark - Selection State

/// Whether this object is currently selected
@property (nonatomic, assign) BOOL selected;

/// Whether this object is highlighted (hovered)
@property (nonatomic, assign) BOOL highlighted;

#pragma mark - Factory Methods

/// Create a new image view object with default properties
+ (instancetype)imageObjectWithName:(NSString *)name;

/// Create a new gridlines view object with default properties
+ (instancetype)gridlinesObjectWithName:(NSString *)name;

#pragma mark - Serialization

/// Create a view object from a saved dictionary
+ (nullable instancetype)objectFromDictionary:(NSDictionary *)dict;

/// Serialize to a dictionary for persistence
- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END
