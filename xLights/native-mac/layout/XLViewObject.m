/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLViewObject.h"

@implementation XLViewObject

- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"";
        _objectType = XLViewObjectTypeImage;
        _active = YES;
        _position = simd_make_float3(0.0f, 0.0f, 0.0f);
        _scale = simd_make_float3(1.0f, 1.0f, 1.0f);
        _rotation = simd_make_float3(0.0f, 0.0f, 0.0f);

        // Image defaults
        _transparency = 0;
        _brightness = 100;
        _imageWidth = 0;
        _imageHeight = 0;

        // Gridlines defaults
        _gridLineSpacing = 50;
        _gridWidth = 1000;
        _gridHeight = 1000;
        _gridColor = simd_make_float4(0.0f, 0.5f, 0.0f, 1.0f); // Green, matching legacy
        _gridShowAxis = NO;

        _selected = NO;
        _highlighted = NO;
    }
    return self;
}

+ (instancetype)imageObjectWithName:(NSString *)name {
    XLViewObject *obj = [[XLViewObject alloc] init];
    obj.name = name;
    obj.objectType = XLViewObjectTypeImage;
    obj.transparency = 0;
    obj.brightness = 100;
    return obj;
}

+ (instancetype)gridlinesObjectWithName:(NSString *)name {
    XLViewObject *obj = [[XLViewObject alloc] init];
    obj.name = name;
    obj.objectType = XLViewObjectTypeGridlines;
    obj.gridLineSpacing = 50;
    obj.gridWidth = 1000;
    obj.gridHeight = 1000;
    obj.gridColor = simd_make_float4(0.0f, 0.5f, 0.0f, 1.0f);
    obj.gridShowAxis = NO;
    return obj;
}

#pragma mark - Serialization

+ (nullable instancetype)objectFromDictionary:(NSDictionary *)dict {
    NSString *name = dict[@"name"];
    NSString *typeStr = dict[@"type"];
    if (!name || !typeStr) return nil;

    XLViewObject *obj = [[XLViewObject alloc] init];
    obj.name = name;
    obj.active = [dict[@"active"] boolValue];

    // Position
    obj.position = simd_make_float3(
        [dict[@"posX"] floatValue],
        [dict[@"posY"] floatValue],
        [dict[@"posZ"] floatValue]
    );

    // Scale
    obj.scale = simd_make_float3(
        dict[@"scaleX"] ? [dict[@"scaleX"] floatValue] : 1.0f,
        dict[@"scaleY"] ? [dict[@"scaleY"] floatValue] : 1.0f,
        dict[@"scaleZ"] ? [dict[@"scaleZ"] floatValue] : 1.0f
    );

    // Rotation
    obj.rotation = simd_make_float3(
        [dict[@"rotX"] floatValue],
        [dict[@"rotY"] floatValue],
        [dict[@"rotZ"] floatValue]
    );

    if ([typeStr isEqualToString:@"Image"]) {
        obj.objectType = XLViewObjectTypeImage;
        obj.imagePath = dict[@"imagePath"];
        obj.transparency = [dict[@"transparency"] integerValue];
        obj.brightness = dict[@"brightness"] ? [dict[@"brightness"] integerValue] : 100;
        obj.imageWidth = [dict[@"imageWidth"] integerValue];
        obj.imageHeight = [dict[@"imageHeight"] integerValue];
    } else if ([typeStr isEqualToString:@"Gridlines"]) {
        obj.objectType = XLViewObjectTypeGridlines;
        obj.gridLineSpacing = dict[@"gridLineSpacing"] ? [dict[@"gridLineSpacing"] integerValue] : 50;
        obj.gridWidth = dict[@"gridWidth"] ? [dict[@"gridWidth"] integerValue] : 1000;
        obj.gridHeight = dict[@"gridHeight"] ? [dict[@"gridHeight"] integerValue] : 1000;
        obj.gridShowAxis = [dict[@"gridShowAxis"] boolValue];
        if (dict[@"gridColorR"]) {
            obj.gridColor = simd_make_float4(
                [dict[@"gridColorR"] floatValue],
                [dict[@"gridColorG"] floatValue],
                [dict[@"gridColorB"] floatValue],
                dict[@"gridColorA"] ? [dict[@"gridColorA"] floatValue] : 1.0f
            );
        }
    } else {
        return nil; // Unknown type
    }

    return obj;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"name"] = _name;
    dict[@"active"] = @(_active);

    // Position
    dict[@"posX"] = @(_position.x);
    dict[@"posY"] = @(_position.y);
    dict[@"posZ"] = @(_position.z);

    // Scale
    dict[@"scaleX"] = @(_scale.x);
    dict[@"scaleY"] = @(_scale.y);
    dict[@"scaleZ"] = @(_scale.z);

    // Rotation
    dict[@"rotX"] = @(_rotation.x);
    dict[@"rotY"] = @(_rotation.y);
    dict[@"rotZ"] = @(_rotation.z);

    switch (_objectType) {
        case XLViewObjectTypeImage:
            dict[@"type"] = @"Image";
            if (_imagePath) dict[@"imagePath"] = _imagePath;
            dict[@"transparency"] = @(_transparency);
            dict[@"brightness"] = @(_brightness);
            dict[@"imageWidth"] = @(_imageWidth);
            dict[@"imageHeight"] = @(_imageHeight);
            break;

        case XLViewObjectTypeGridlines:
            dict[@"type"] = @"Gridlines";
            dict[@"gridLineSpacing"] = @(_gridLineSpacing);
            dict[@"gridWidth"] = @(_gridWidth);
            dict[@"gridHeight"] = @(_gridHeight);
            dict[@"gridShowAxis"] = @(_gridShowAxis);
            dict[@"gridColorR"] = @(_gridColor.x);
            dict[@"gridColorG"] = @(_gridColor.y);
            dict[@"gridColorB"] = @(_gridColor.z);
            dict[@"gridColorA"] = @(_gridColor.w);
            break;

        default:
            dict[@"type"] = @"Unknown";
            break;
    }

    return [dict copy];
}

- (NSString *)description {
    NSString *typeStr;
    switch (_objectType) {
        case XLViewObjectTypeImage: typeStr = @"Image"; break;
        case XLViewObjectTypeGridlines: typeStr = @"Gridlines"; break;
        case XLViewObjectTypeTerrain: typeStr = @"Terrain"; break;
        case XLViewObjectTypeRuler: typeStr = @"Ruler"; break;
        case XLViewObjectTypeMesh: typeStr = @"Mesh"; break;
    }
    return [NSString stringWithFormat:@"<XLViewObject: %@ type=%@ active=%@ pos=(%.0f,%.0f,%.0f)>",
            _name, typeStr, _active ? @"YES" : @"NO",
            _position.x, _position.y, _position.z];
}

@end
