/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLORS5Parser.h"

// Version number for model position format (matches CUR_MODEL_POS_VER in legacy)
static NSString * const kModelPosVersion = @"7";

#pragma mark - Internal S5 Data Structures

/// Raw parsed point from LOR S5 XML
typedef struct {
    float x;
    float y;
} S5Point;

/// Raw parsed model data from LOR S5 XML before conversion
@interface _XLORS5RawModel : NSObject
@property (nonatomic, copy) NSString *modelId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *shapeName;
@property (nonatomic, copy) NSString *deviceType;
@property (nonatomic, copy) NSString *bulbShape;
@property (nonatomic, copy) NSString *rgbOrder;
@property (nonatomic, copy) NSString *startLocation;
@property (nonatomic, copy) NSString *stringType;
@property (nonatomic, copy) NSString *traditionalColors;
@property (nonatomic, copy) NSString *traditionalType;
@property (nonatomic, copy) NSString *channelGrid;
@property (nonatomic, assign) int previewBulbSize;
@property (nonatomic, assign) BOOL separateIds;
@property (nonatomic, assign) BOOL individualChannels;
@property (nonatomic, assign) int opacity;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *parms;
@property (nonatomic, assign) S5Point offset;
@property (nonatomic, assign) S5Point scale;
@property (nonatomic, assign) float radians;
@property (nonatomic, copy) NSString *customWidth;
@property (nonatomic, copy) NSString *customHeight;
@property (nonatomic, copy) NSString *customGrid;
@property (nonatomic, strong) NSMutableArray<NSValue *> *points; // NSValue wrapping S5Point
@end

@implementation _XLORS5RawModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _parms = [NSMutableArray array];
        _points = [NSMutableArray array];
        _previewBulbSize = 2;
        _opacity = 0;
        _startLocation = @"n/a";
        S5Point zero = {0, 0};
        _offset = zero;
        S5Point one = {1, 1};
        _scale = one;
    }
    return self;
}

@end

#pragma mark - XLORS5ModelInfo

@implementation XLORS5ModelInfo
@end

#pragma mark - XLORS5GroupInfo

@implementation XLORS5GroupInfo
@end

#pragma mark - XLORS5Parser Internal

@interface XLORS5Parser ()
@end

@implementation XLORS5Parser

#pragma mark - Public API

+ (nullable NSArray<NSString *> *)previewNamesInFile:(NSString *)filePath {
    NSData *xmlData = [NSData dataWithContentsOfFile:filePath];
    if (!xmlData) return nil;

    NSError *error = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (!doc) {
        NSLog(@"XLORS5Parser: Failed to parse XML: %@", error);
        return nil;
    }

    NSXMLElement *root = [doc rootElement];
    if (!root) return nil;

    // If root is PreviewClass itself, it's a single-preview file
    if ([[root name] isEqualToString:@"PreviewClass"]) {
        NSString *name = [[root attributeForName:@"Name"] stringValue] ?: @"Default";
        return @[name];
    }

    // Otherwise collect all PreviewClass children
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSXMLElement *child in [root children]) {
        if ([[child name] isEqualToString:@"PreviewClass"]) {
            NSString *name = [[child attributeForName:@"Name"] stringValue];
            if (name) {
                [names addObject:name];
            }
        }
    }
    [names sortUsingSelector:@selector(compare:)];
    return names;
}

+ (BOOL)parseFile:(NSString *)filePath
      previewName:(nullable NSString *)previewName
     previewWidth:(int)previewWidth
    previewHeight:(int)previewHeight
           models:(NSArray<XLORS5ModelInfo *> *_Nullable *_Nonnull)outModels
           groups:(NSArray<XLORS5GroupInfo *> *_Nullable *_Nonnull)outGroups {

    NSData *xmlData = [NSData dataWithContentsOfFile:filePath];
    if (!xmlData) {
        NSLog(@"XLORS5Parser: Cannot read file: %@", filePath);
        return NO;
    }

    NSError *error = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (!doc) {
        NSLog(@"XLORS5Parser: Failed to parse XML: %@", error);
        return NO;
    }

    NSXMLElement *root = [doc rootElement];
    if (!root) return NO;

    NSXMLElement *previewNode = nil;

    if ([[root name] isEqualToString:@"PreviewClass"]) {
        previewNode = root;
    } else {
        // Find the requested preview
        for (NSXMLElement *child in [root children]) {
            if ([[child name] isEqualToString:@"PreviewClass"]) {
                if (!previewName || [[[child attributeForName:@"Name"] stringValue] isEqualToString:previewName]) {
                    previewNode = child;
                    break;
                }
            }
        }
    }

    if (!previewNode) {
        NSLog(@"XLORS5Parser: Preview '%@' not found", previewName);
        return NO;
    }

    return [self parsePreviewNode:previewNode
                     previewWidth:previewWidth
                    previewHeight:previewHeight
                           models:outModels
                           groups:outGroups];
}

+ (nullable XLORS5ModelInfo *)parseModelFile:(NSString *)filePath
                                previewWidth:(int)previewWidth
                               previewHeight:(int)previewHeight {
    NSData *xmlData = [NSData dataWithContentsOfFile:filePath];
    if (!xmlData) return nil;

    NSError *error = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (!doc) return nil;

    NSXMLElement *root = [doc rootElement];
    for (NSXMLElement *child in [root children]) {
        if ([[child name] isEqualToString:@"PropClass"]) {
            _XLORS5RawModel *raw = [self parseRawModel:child];
            if (raw) {
                return [self convertRawModel:raw previewWidth:previewWidth previewHeight:previewHeight];
            }
        }
    }
    return nil;
}

#pragma mark - Preview Parsing

+ (BOOL)parsePreviewNode:(NSXMLElement *)preview
            previewWidth:(int)previewWidth
           previewHeight:(int)previewHeight
                  models:(NSArray<XLORS5ModelInfo *> *_Nullable *_Nonnull)outModels
                  groups:(NSArray<XLORS5GroupInfo *> *_Nullable *_Nonnull)outGroups {

    NSMutableArray<XLORS5ModelInfo *> *models = [NSMutableArray array];
    NSMutableArray<XLORS5GroupInfo *> *groups = [NSMutableArray array];

    for (NSXMLElement *child in [preview children]) {
        NSString *childName = [child name];

        if ([childName isEqualToString:@"PropClass"]) {
            _XLORS5RawModel *raw = [self parseRawModel:child];
            if (raw) {
                XLORS5ModelInfo *info = [self convertRawModel:raw
                                                previewWidth:previewWidth
                                               previewHeight:previewHeight];
                if (info) {
                    [models addObject:info];
                }
            }
        } else if ([childName isEqualToString:@"PropGroup"]) {
            XLORS5GroupInfo *group = [self parseGroup:child];
            if (group) {
                [groups addObject:group];
            }
        }
    }

    *outModels = models;
    *outGroups = groups;
    return YES;
}

#pragma mark - Raw Model Parsing

+ (_XLORS5RawModel *)parseRawModel:(NSXMLElement *)element {
    _XLORS5RawModel *model = [[_XLORS5RawModel alloc] init];

    model.modelId = [[element attributeForName:@"id"] stringValue] ?: @"";
    model.name = [[element attributeForName:@"Name"] stringValue] ?: @"Unnamed";
    model.bulbShape = [[element attributeForName:@"BulbShape"] stringValue] ?: @"";
    model.deviceType = [[element attributeForName:@"DeviceType"] stringValue] ?: @"";
    model.individualChannels = [[[element attributeForName:@"IndividualChannels"] stringValue] isEqualToString:@"True"];
    model.previewBulbSize = [[[element attributeForName:@"PreviewBulbSize"] stringValue] ?: @"2" intValue];
    model.rgbOrder = [[element attributeForName:@"RgbOrder"] stringValue] ?: @"";
    model.separateIds = [[[element attributeForName:@"SeparateIds"] stringValue] isEqualToString:@"True"];
    model.startLocation = [[element attributeForName:@"StartLocation"] stringValue] ?: @"n/a";
    model.stringType = [[element attributeForName:@"StringType"] stringValue] ?: @"";
    model.traditionalColors = [[element attributeForName:@"TraditionalColors"] stringValue] ?: @"";
    model.traditionalType = [[element attributeForName:@"TraditionalType"] stringValue] ?: @"";
    model.channelGrid = [[element attributeForName:@"ChannelGrid"] stringValue] ?: @"";
    model.opacity = [[[element attributeForName:@"Opacity"] stringValue] ?: @"0" intValue];

    // Parse Parm1, Parm2, ... ParmN
    [self parseParms:element into:model.parms];

    // Parse shape child element
    for (NSXMLElement *shape in [element children]) {
        if ([[shape name] isEqualToString:@"shape"]) {
            model.shapeName = [[shape attributeForName:@"ShapeName"] stringValue] ?: @"";
            model.customWidth = [[shape attributeForName:@"CustomWidth"] stringValue] ?: @"5";
            model.customHeight = [[shape attributeForName:@"CustomHeight"] stringValue] ?: @"5";
            model.customGrid = [[shape attributeForName:@"CustomGrid"] stringValue] ?: @"";

            S5Point offset;
            offset.x = [[[shape attributeForName:@"OffsetX"] stringValue] ?: @"0.0" floatValue];
            offset.y = [[[shape attributeForName:@"OffsetY"] stringValue] ?: @"0.0" floatValue];
            model.offset = offset;

            S5Point scale;
            scale.x = [[[shape attributeForName:@"ScaleX"] stringValue] ?: @"1.0" floatValue];
            scale.y = [[[shape attributeForName:@"ScaleY"] stringValue] ?: @"1.0" floatValue];
            model.scale = scale;

            model.radians = [[[shape attributeForName:@"Radians"] stringValue] ?: @"0.0" floatValue];

            [self parsePoints:shape into:model.points];
        }
    }

    return model;
}

+ (void)parseParms:(NSXMLElement *)element into:(NSMutableArray<NSNumber *> *)parms {
    for (int i = 1; i < 100; i++) {
        NSString *parmName = [NSString stringWithFormat:@"Parm%d", i];
        NSString *value = [[element attributeForName:parmName] stringValue];
        if (value) {
            [parms addObject:@([value intValue])];
        } else {
            break;
        }
    }
}

+ (void)parsePoints:(NSXMLElement *)element into:(NSMutableArray<NSValue *> *)points {
    for (NSXMLElement *child in [element children]) {
        if ([[child name] isEqualToString:@"point"]) {
            S5Point pt;
            pt.x = [[[child attributeForName:@"x"] stringValue] ?: @"0.0" floatValue];
            pt.y = [[[child attributeForName:@"y"] stringValue] ?: @"0.0" floatValue];
            [points addObject:[NSValue valueWithBytes:&pt objCType:@encode(S5Point)]];
        }
    }
}

+ (XLORS5GroupInfo *)parseGroup:(NSXMLElement *)element {
    XLORS5GroupInfo *group = [[XLORS5GroupInfo alloc] init];
    group.groupId = [[element attributeForName:@"id"] stringValue] ?: @"";
    group.name = [[element attributeForName:@"Name"] stringValue] ?: @"Group";

    NSMutableArray<NSString *> *memberIds = [NSMutableArray array];
    for (NSXMLElement *child in [element children]) {
        if ([[child name] isEqualToString:@"member"]) {
            NSString *memberId = [[child attributeForName:@"id"] stringValue];
            if (memberId) {
                [memberIds addObject:memberId];
            }
        }
    }
    group.memberIds = memberIds;
    return group;
}

#pragma mark - Model Conversion (S5 -> xLights)

+ (XLORS5ModelInfo *)convertRawModel:(_XLORS5RawModel *)raw
                        previewWidth:(int)pvwW
                       previewHeight:(int)pvwH {

    XLORS5ModelInfo *info = [[XLORS5ModelInfo alloc] init];
    info.name = raw.name;
    info.modelId = raw.modelId;
    info.shapeName = raw.shapeName;
    info.isUnknownShape = NO;

    NSMutableDictionary<NSString *, NSString *> *props = [NSMutableDictionary dictionary];

    NSString *shapeName = raw.shapeName ?: @"";

    if ([shapeName hasPrefix:@"Arch"]) {
        info.xlightsModelType = @"Arches";
        if ([raw.stringType isEqualToString:@"Traditional"]) {
            props[@"parm1"] = @"1";
            props[@"parm2"] = [self parmStr:raw index:0];
            props[@"parm3"] = [self parmStr:raw index:1];
        } else {
            props[@"parm1"] = @"1";
            props[@"parm2"] = [NSString stringWithFormat:@"%d", [self parmInt:raw index:0] * [self parmInt:raw index:1]];
        }
        [self setDirection:raw props:props];
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Bulb"]) {
        info.xlightsModelType = @"Custom";
        [self bulbToCustomModel:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Candycane"]) {
        info.xlightsModelType = @"Candy Canes";
        props[@"parm1"] = @"1";
        props[@"parm2"] = [NSString stringWithFormat:@"%d", [self parmInt:raw index:0] * [self parmInt:raw index:1]];
        if ([shapeName containsString:@"Left"]) {
            props[@"CandyCaneReverse"] = @"true";
        } else {
            props[@"CandyCaneReverse"] = @"false";
        }
        [self setDirection:raw props:props];
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Circles Nested"]) {
        info.xlightsModelType = @"Circle";
        int totalCount = 0;
        int totalLayers = 0;
        NSMutableString *layers = [NSMutableString string];
        // Skip first parm (center hollowness)
        for (NSUInteger i = 1; i < raw.parms.count; i++) {
            int val = raw.parms[i].intValue;
            if (val != 0) {
                totalCount += val;
                totalLayers++;
                if (layers.length > 0) [layers appendString:@","];
                [layers appendFormat:@"%d", val];
            }
        }
        props[@"parm1"] = @"1";
        props[@"parm2"] = [NSString stringWithFormat:@"%d", totalCount];
        props[@"parm3"] = raw.parms.count > 0 ? [raw.parms[0] stringValue] : @"0";
        props[@"LayerSizes"] = layers;

        props[@"StartSide"] = [raw.startLocation substringToIndex:MIN(1, raw.startLocation.length)];
        if ([raw.startLocation containsString:@"CCW"]) {
            props[@"Dir"] = @"L";
        } else {
            props[@"Dir"] = @"R";
        }
        if ([raw.startLocation containsString:@"Outer"]) {
            props[@"InsideOut"] = @"0";
        } else {
            props[@"InsideOut"] = @"1";
        }
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Custom"] || [shapeName hasPrefix:@"Advance"]) {
        info.xlightsModelType = @"Custom";
        props[@"parm1"] = raw.customWidth;
        props[@"parm2"] = raw.customHeight;
        props[@"CustomModel"] = raw.customGrid;
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Cylinder"]) {
        info.xlightsModelType = @"Tree";
        props[@"parm1"] = [self parmStr:raw index:0];
        props[@"parm2"] = [self parmStr:raw index:1];
        props[@"parm3"] = [NSString stringWithFormat:@"%d", [self parmInt:raw index:2] + 1];
        if (raw.parms.count > 4) {
            props[@"DisplayAs"] = [NSString stringWithFormat:@"Tree %d", raw.parms[4].intValue * 90];
        }
        props[@"TreeBottomTopRatio"] = @"1.0";

        if ([shapeName containsString:@"spiral"]) {
            float rotation = (float)[self parmInt:raw index:2] / 10.0f;
            if ([raw.startLocation containsString:@"CCW"]) {
                rotation *= -1;
            }
            props[@"TreeSpiralRotations"] = [NSString stringWithFormat:@"%f", rotation];
        }
        [self setDirection:raw props:props];
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Fan"]) {
        info.xlightsModelType = @"Spinner";
        props[@"parm1"] = [self parmStr:raw index:0];
        props[@"parm2"] = [self parmStr:raw index:1];
        props[@"parm3"] = @"1";
        props[@"StartAngle"] = @"90";
        props[@"Arc"] = @"180";
        if ([raw.startLocation containsString:@"Top"]) {
            props[@"StartSide"] = @"T";
        } else {
            props[@"StartSide"] = @"B";
        }
        if ([raw.startLocation containsString:@"CCW"]) {
            props[@"Dir"] = @"L";
        } else {
            props[@"Dir"] = @"R";
        }
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Firestick"]) {
        info.xlightsModelType = @"Single Line";
        props[@"parm1"] = [self parmStr:raw index:0];
        props[@"parm2"] = [self parmStr:raw index:1];
        [self scaleModelToSingleLine:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Icicles"]) {
        info.xlightsModelType = @"Icicles";
        int maxdrop = 0;
        int drops = 0;
        NSMutableArray<NSNumber *> *dropcounts = [NSMutableArray array];
        for (NSUInteger i = 1; i < raw.parms.count; i++) {
            int val = raw.parms[i].intValue;
            if (val != 0) {
                maxdrop = MAX(maxdrop, val);
                drops++;
                [dropcounts addObject:@(val)];
            }
        }
        int totalDrops = raw.parms.count > 0 ? raw.parms[0].intValue : 0;
        int totalNodes = 0;
        for (int i = 0; i < totalDrops; i++) {
            int idx = drops > 0 ? (i % drops) : 0;
            if (idx < (int)dropcounts.count) {
                totalNodes += dropcounts[idx].intValue;
            }
        }
        NSMutableString *dropPattern = [NSMutableString string];
        for (NSNumber *drp in dropcounts) {
            if (dropPattern.length > 0) [dropPattern appendString:@","];
            [dropPattern appendFormat:@"%d", drp.intValue];
        }
        props[@"parm1"] = @"1";
        props[@"parm2"] = [NSString stringWithFormat:@"%d", totalNodes];
        props[@"DropPattern"] = dropPattern;
        [self scaleIcicleToSingleLine:raw maxdrop:maxdrop props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Lines"]) {
        info.xlightsModelType = @"Poly Line";
        int totalNodes = raw.parms.count > 1 ? raw.parms[1].intValue : 0;
        props[@"parm2"] = [NSString stringWithFormat:@"%d", totalNodes];

        if ([shapeName containsString:@"-Connected"]) {
            [self scaleConnectedLine:raw props:props pvwW:pvwW pvwH:pvwH];
        } else if ([shapeName containsString:@"-Unconnected"]) {
            [self scaleUnconnectedLine:raw props:props pvwW:pvwW pvwH:pvwH];
        } else if ([shapeName containsString:@"-Closed Shape"]) {
            [self scaleClosedLine:raw props:props pvwW:pvwW pvwH:pvwH];
        }
        props[@"ScaleX"] = @"1.0000";
        props[@"ScaleY"] = @"1.0000";
        props[@"ScaleZ"] = @"1.0000";

    } else if ([shapeName hasPrefix:@"Matrix"]) {
        info.xlightsModelType = @"Matrix";
        props[@"parm1"] = [self parmStr:raw index:0];
        props[@"parm2"] = [self parmStr:raw index:1];
        props[@"parm3"] = [NSString stringWithFormat:@"%d", [self parmInt:raw index:2] + 1];
        if ([shapeName containsString:@"Vertical"]) {
            props[@"DisplayAs"] = @"Vert Matrix";
        } else {
            props[@"DisplayAs"] = @"Horiz Matrix";
        }
        [self setDirection:raw props:props];
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Sphere"]) {
        info.xlightsModelType = @"Sphere";
        props[@"parm1"] = [self parmStr:raw index:0];
        props[@"parm2"] = [self parmStr:raw index:1];
        props[@"parm3"] = [NSString stringWithFormat:@"%d", [self parmInt:raw index:2] + 1];
        if (raw.parms.count > 4) {
            props[@"Degrees"] = [NSString stringWithFormat:@"%d", raw.parms[4].intValue * 90];
        }
        if (raw.parms.count > 5) {
            float pct = (float)raw.parms[5].intValue / 100.0f;
            props[@"StartLatitude"] = [NSString stringWithFormat:@"%d", (int)(pct * -86.0f)];
            props[@"EndLatitude"] = [NSString stringWithFormat:@"%d", (int)(pct * 86.0f)];
        }
        [self setDirection:raw props:props];
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Spokes"]) {
        info.xlightsModelType = @"Spinner";
        props[@"parm1"] = [self parmStr:raw index:0];
        props[@"parm2"] = [self parmStr:raw index:1];
        props[@"parm3"] = @"1";
        if ([raw.startLocation containsString:@"Top"]) {
            props[@"StartSide"] = @"T";
        } else {
            props[@"StartSide"] = @"B";
        }
        if ([raw.startLocation containsString:@"Counter"]) {
            props[@"Dir"] = @"L";
        } else {
            props[@"Dir"] = @"R";
        }
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Star"]) {
        info.xlightsModelType = @"Star";
        if ([shapeName containsString:@"Nested"]) {
            int totalCount = 0;
            NSMutableString *layers = [NSMutableString string];
            for (NSNumber *layer in raw.parms) {
                if (layer.intValue != 0) {
                    totalCount += layer.intValue;
                    // Prepend (reversed order, matches legacy behavior)
                    if (layers.length > 0) {
                        [layers insertString:@"," atIndex:0];
                    }
                    [layers insertString:[NSString stringWithFormat:@"%d", layer.intValue] atIndex:0];
                }
            }
            props[@"parm1"] = @"1";
            props[@"parm2"] = [NSString stringWithFormat:@"%d", totalCount];
            props[@"parm3"] = @"5";
            props[@"LayerSizes"] = layers;
        } else {
            props[@"parm1"] = [self parmStr:raw index:0];
            props[@"parm2"] = [self parmStr:raw index:1];
            props[@"parm3"] = [self parmStr:raw index:2];
            if (raw.parms.count > 3) {
                float ratio = 2.618034f * ((float)raw.parms[3].intValue / 10.0f);
                props[@"starRatio"] = [NSString stringWithFormat:@"%lf", ratio];
            }
        }

        // Convert start location
        NSString *startLoc = raw.startLocation;
        if ([startLoc hasSuffix:@"-CW"]) {
            startLoc = [startLoc stringByReplacingOccurrencesOfString:@"-CW" withString:@" Ctr-CCW"];
        }
        if ([startLoc hasSuffix:@"-CCW"]) {
            startLoc = [startLoc stringByReplacingOccurrencesOfString:@"-CCW" withString:@" Ctr-CW"];
        }
        props[@"StarStartLocation"] = startLoc;
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Tree"]) {
        info.xlightsModelType = @"Tree";
        props[@"parm1"] = [self parmStr:raw index:0];
        props[@"parm2"] = [self parmStr:raw index:1];
        props[@"DisplayAs"] = [self decodeTreeType:shapeName];

        if ([shapeName containsString:@"spiral"]) {
            float rotation = (float)[self parmInt:raw index:2] / 10.0f;
            if ([raw.startLocation containsString:@"CCW"]) {
                rotation *= -1;
            }
            props[@"TreeSpiralRotations"] = [NSString stringWithFormat:@"%f", rotation];
        } else {
            props[@"parm3"] = [NSString stringWithFormat:@"%d", [self parmInt:raw index:2] + 1];
        }
        [self setDirection:raw props:props];
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Window Frame"]) {
        info.xlightsModelType = @"Window Frame";
        props[@"parm1"] = [self parmStr:raw index:0];
        props[@"parm2"] = [self parmStr:raw index:1];
        props[@"parm3"] = [self parmStr:raw index:2];
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else if ([shapeName hasPrefix:@"Wreath"]) {
        info.xlightsModelType = @"Circle";
        props[@"parm1"] = [self parmStr:raw index:0];
        props[@"parm2"] = [self parmStr:raw index:1];
        if ([raw.startLocation containsString:@"Top"] || [raw.startLocation containsString:@"Bottom"]) {
            props[@"StartSide"] = [raw.startLocation substringToIndex:MIN(1, raw.startLocation.length)];
        }
        if ([raw.startLocation containsString:@"CCW"]) {
            props[@"Dir"] = @"L";
        } else {
            props[@"Dir"] = @"R";
        }
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];

    } else {
        // Unknown shape - fall back to Single Line
        info.xlightsModelType = @"Single Line";
        info.isUnknownShape = YES;
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];
        NSLog(@"XLORS5Parser: Unknown LOR S5 shape '%@' for model '%@', using Single Line", shapeName, raw.name);
    }

    // Set string type, bulb type, and start channel
    [self setStringType:raw props:props];
    [self setBulbTypeSize:raw props:props];
    [self setStartChannel:raw props:props supportsMultiString:[self shapeSupportsMultiString:shapeName]];

    info.properties = props;
    return info;
}

#pragma mark - Direction and String Type Helpers

+ (void)setDirection:(_XLORS5RawModel *)raw props:(NSMutableDictionary *)props {
    if ([raw.startLocation containsString:@"Left"]) {
        props[@"Dir"] = @"L";
    }
    if ([raw.startLocation containsString:@"Right"]) {
        props[@"Dir"] = @"R";
    }
    if ([raw.startLocation containsString:@"Bottom"]) {
        props[@"StartSide"] = @"B";
    }
    if ([raw.startLocation containsString:@"Top"]) {
        props[@"StartSide"] = @"T";
    }
}

+ (void)setStringType:(_XLORS5RawModel *)raw props:(NSMutableDictionary *)props {
    if ([raw.stringType isEqualToString:@"Traditional"]) {
        if ([raw.traditionalType isEqualToString:@"Multicolor_string_1_ch"]) {
            if ([raw.traditionalColors containsString:@","]) {
                props[@"StringType"] = @"Single Color Intensity";
            } else {
                if ([raw.traditionalColors isEqualToString:@"Red"] ||
                    [raw.traditionalColors isEqualToString:@"Blue"] ||
                    [raw.traditionalColors isEqualToString:@"Green"] ||
                    [raw.traditionalColors isEqualToString:@"White"]) {
                    props[@"StringType"] = [NSString stringWithFormat:@"Single Color %@", raw.traditionalColors];
                } else {
                    props[@"StringType"] = @"Single Color Custom";
                    props[@"CustomColor"] = raw.traditionalColors;
                }
            }
        } else if ([raw.traditionalType isEqualToString:@"Channel_per_color"]) {
            if (![raw.traditionalColors containsString:@","]) {
                props[@"StringType"] = [NSString stringWithFormat:@"Single Color %@", raw.traditionalColors];
            } else {
                props[@"StringType"] = @"Superstring";
            }
        }
    } else if ([raw.stringType isEqualToString:@"DumbRGB"]) {
        if ([raw.rgbOrder containsString:@"RGB"]) {
            props[@"StringType"] = @"3 Channel RGB";
        } else {
            props[@"StringType"] = @"Superstring";
        }
    } else if ([raw.stringType isEqualToString:@"RGB"]) {
        NSString *order = [raw.rgbOrder stringByReplacingOccurrencesOfString:@"order" withString:@"Nodes"];
        props[@"StringType"] = order;
    }
}

+ (void)setBulbTypeSize:(_XLORS5RawModel *)raw props:(NSMutableDictionary *)props {
    if ([raw.bulbShape isEqualToString:@"Square"]) {
        props[@"Antialias"] = @"0";
    }
    props[@"PixelSize"] = [NSString stringWithFormat:@"%d", raw.previewBulbSize];
    // Opacity 255 = full dark (255-0), Transparency 0-100
    int transparency = (int)((255.0 - raw.opacity) / 2.55);
    props[@"Transparency"] = [NSString stringWithFormat:@"%d", transparency];
}

+ (void)setStartChannel:(_XLORS5RawModel *)raw props:(NSMutableDictionary *)props supportsMultiString:(BOOL)multiString {
    if (![raw.deviceType isEqualToString:@"DMX"]) return;

    if ([raw.channelGrid containsString:@";"] && multiString) {
        NSArray<NSString *> *addresses = [raw.channelGrid componentsSeparatedByString:@";"];
        props[@"Advanced"] = @"1";
        int i = 0;
        for (NSString *address in addresses) {
            int universe = 0, chan = 0;
            if ([self getStartUniverseChan:address universe:&universe channel:&chan]) {
                NSString *key = [NSString stringWithFormat:@"ModelStartChannel%d", i];
                props[key] = [NSString stringWithFormat:@"#%d:%d", universe, chan];
            }
            i++;
        }
    } else {
        int universe = 0, chan = 0;
        if ([self getStartUniverseChan:raw.channelGrid universe:&universe channel:&chan]) {
            props[@"StartChannel"] = [NSString stringWithFormat:@"#%d:%d", universe, chan];
        }
    }
}

+ (BOOL)getStartUniverseChan:(NSString *)value universe:(int *)unv channel:(int *)chan {
    NSArray<NSString *> *parts = [value componentsSeparatedByString:@","];
    if (parts.count == 5 || parts.count == 6) {
        *unv = [parts[1] intValue];
        *chan = [parts[2] intValue];
        return YES;
    }
    return NO;
}

+ (BOOL)shapeSupportsMultiString:(NSString *)shapeName {
    return ([shapeName hasPrefix:@"Fan"] ||
            [shapeName hasPrefix:@"Matrix"] ||
            [shapeName hasPrefix:@"Spokes"] ||
            ([shapeName hasPrefix:@"Star"] && ![shapeName containsString:@"Nested"]) ||
            [shapeName hasPrefix:@"Tree"]);
}

#pragma mark - Scaling Helpers

+ (S5Point)scalePointToXLights:(S5Point)pt pvwW:(int)pvwW pvwH:(int)pvwH {
    S5Point result;
    result.x = ((float)pvwW / 2.0f) * (pt.x + 1.0f);
    result.y = ((float)pvwH / 2.0f) * (pt.y + 1.0f);
    return result;
}

+ (S5Point)getSizeFromScale:(S5Point)scale pvwW:(int)pvwW pvwH:(int)pvwH {
    float width = 1.0f;
    float height = 1.0f;

    if (scale.x < 5.0f) {
        width = ((float)pvwW / 2.0f) * scale.x;
    } else {
        width = ((float)pvwW / 2.0f) * scale.y;
    }
    if (scale.y < 5.0f) {
        height = ((float)pvwH / 2.0f) * scale.y;
    } else {
        height = ((float)pvwH / 2.0f) * scale.x;
    }
    S5Point result = { width, height };
    return result;
}

+ (void)scaleToPreview:(_XLORS5RawModel *)raw props:(NSMutableDictionary *)props
                  pvwW:(int)pvwW pvwH:(int)pvwH {
    props[@"versionNumber"] = kModelPosVersion;

    S5Point center = [self scalePointToXLights:raw.offset pvwW:pvwW pvwH:pvwH];
    S5Point xSize = [self getSizeFromScale:raw.scale pvwW:pvwW pvwH:pvwH];

    // Use a default base size if the model has not been initialized
    float bwidth = 10.0f;
    float bheight = 10.0f;

    float scalex = xSize.x / bwidth;
    float scaley = xSize.y / bheight;
    float rotatez = 0.0f;
    if (raw.radians != 0.0f) {
        rotatez = raw.radians * 180.0f / M_PI;
    }

    props[@"WorldPosX"] = [NSString stringWithFormat:@"%6.4f", center.x];
    props[@"WorldPosY"] = [NSString stringWithFormat:@"%6.4f", center.y];
    props[@"WorldPosZ"] = [NSString stringWithFormat:@"%6.4f", 0.0f];
    props[@"ScaleX"] = [NSString stringWithFormat:@"%6.4f", scalex];
    props[@"ScaleY"] = [NSString stringWithFormat:@"%6.4f", scaley];
    props[@"ScaleZ"] = [NSString stringWithFormat:@"%6.4f", scalex];

    props[@"RotateX"] = [NSString stringWithFormat:@"%4.8f", 0.0f];
    props[@"RotateY"] = [NSString stringWithFormat:@"%4.8f", 0.0f];
    props[@"RotateZ"] = [NSString stringWithFormat:@"%4.8f", rotatez];
}

+ (void)scaleModelToSingleLine:(_XLORS5RawModel *)raw props:(NSMutableDictionary *)props
                          pvwW:(int)pvwW pvwH:(int)pvwH {
    S5Point center = [self scalePointToXLights:raw.offset pvwW:pvwW pvwH:pvwH];
    S5Point xSize = [self getSizeFromScale:raw.scale pvwW:pvwW pvwH:pvwH];

    if ([raw.startLocation isEqualToString:@"Top"]) {
        props[@"WorldPosX"] = [NSString stringWithFormat:@"%6.4f", center.x];
        props[@"WorldPosY"] = [NSString stringWithFormat:@"%6.4f", center.y + xSize.y / 2.0f];
        props[@"X2"] = @"0.0000";
        props[@"Y2"] = [NSString stringWithFormat:@"%6.4f", -(xSize.y / 2.0f)];
    } else if ([raw.startLocation isEqualToString:@"Bottom"]) {
        props[@"WorldPosX"] = [NSString stringWithFormat:@"%6.4f", center.x];
        props[@"WorldPosY"] = [NSString stringWithFormat:@"%6.4f", center.y - xSize.y / 2.0f];
        props[@"X2"] = @"0.0000";
        props[@"Y2"] = [NSString stringWithFormat:@"%6.4f", xSize.y / 2.0f];
    } else if ([raw.startLocation isEqualToString:@"Left"]) {
        props[@"WorldPosX"] = [NSString stringWithFormat:@"%6.4f", center.x + xSize.x / 2.0f];
        props[@"WorldPosY"] = [NSString stringWithFormat:@"%6.4f", center.y];
        props[@"X2"] = [NSString stringWithFormat:@"%6.4f", -(xSize.x / 2.0f)];
        props[@"Y2"] = @"0.0000";
    } else if ([raw.startLocation isEqualToString:@"Right"]) {
        props[@"WorldPosX"] = [NSString stringWithFormat:@"%6.4f", center.x - xSize.x / 2.0f];
        props[@"WorldPosY"] = [NSString stringWithFormat:@"%6.4f", center.y];
        props[@"X2"] = [NSString stringWithFormat:@"%6.4f", xSize.x / 2.0f];
        props[@"Y2"] = @"0.0000";
    } else {
        props[@"WorldPosX"] = [NSString stringWithFormat:@"%6.4f", center.x];
        props[@"WorldPosY"] = [NSString stringWithFormat:@"%6.4f", center.y];
        props[@"X2"] = [NSString stringWithFormat:@"%6.4f", xSize.x];
        props[@"Y2"] = [NSString stringWithFormat:@"%6.4f", xSize.y];
    }

    props[@"WorldPosZ"] = @"0.0000";
    props[@"Z2"] = @"0.0000";
    props[@"ScaleX"] = @"1.0000";
    props[@"ScaleY"] = @"1.0000";
    props[@"ScaleZ"] = @"1.0000";
    props[@"versionNumber"] = kModelPosVersion;
}

+ (void)scaleIcicleToSingleLine:(_XLORS5RawModel *)raw maxdrop:(int)maxdrop
                          props:(NSMutableDictionary *)props pvwW:(int)pvwW pvwH:(int)pvwH {
    if (raw.points.count < 4) return;

    props[@"versionNumber"] = kModelPosVersion;

    S5Point pt0, pt1, pt3;
    [raw.points[0] getValue:&pt0];
    [raw.points[1] getValue:&pt1];
    [raw.points[3] getValue:&pt3];

    S5Point first = [self scalePointToXLights:pt0 pvwW:pvwW pvwH:pvwH];
    S5Point second = [self scalePointToXLights:pt1 pvwW:pvwW pvwH:pvwH];
    S5Point fourth = [self scalePointToXLights:pt3 pvwW:pvwW pvwH:pvwH];

    props[@"WorldPosX"] = [NSString stringWithFormat:@"%6.4f", first.x];
    props[@"WorldPosY"] = [NSString stringWithFormat:@"%6.4f", first.y];
    props[@"WorldPosZ"] = @"0.0000";
    props[@"X2"] = [NSString stringWithFormat:@"%6.4f", second.x - first.x];
    props[@"Y2"] = [NSString stringWithFormat:@"%6.4f", second.y - first.y];
    props[@"Z2"] = @"0.0000";

    float newHeight = ((first.y - fourth.y) / (float)maxdrop) / 50.0f;
    props[@"Height"] = [NSString stringWithFormat:@"%6.4f", newHeight * -1.0f];

    props[@"ScaleX"] = @"1.0000";
    props[@"ScaleY"] = @"1.0000";
    props[@"ScaleZ"] = @"1.0000";
}

#pragma mark - Poly Line Scaling

+ (S5Point)getPointFromArray:(NSArray<NSValue *> *)points index:(NSUInteger)idx {
    S5Point pt = {0, 0};
    if (idx < points.count) {
        [points[idx] getValue:&pt];
    }
    return pt;
}

+ (void)scaleConnectedLine:(_XLORS5RawModel *)raw props:(NSMutableDictionary *)props
                      pvwW:(int)pvwW pvwH:(int)pvwH {
    if (raw.points.count == 0) return;

    NSMutableString *pointData = [NSMutableString string];
    S5Point worldPt = {0, 0};

    for (NSUInteger i = 0; i < raw.points.count; i++) {
        S5Point pt = [self getPointFromArray:raw.points index:i];
        if (i == 0) {
            worldPt = [self scalePointToXLights:pt pvwW:pvwW pvwH:pvwH];
            [pointData appendString:@"0.0,0.0,0.0,"];
        } else {
            S5Point scaled = [self scalePointToXLights:pt pvwW:pvwW pvwH:pvwH];
            [pointData appendFormat:@"%f,%f,0.0,", scaled.x - worldPt.x, scaled.y - worldPt.y];
        }
    }
    // Remove trailing comma
    if (pointData.length > 0) {
        [pointData deleteCharactersInRange:NSMakeRange(pointData.length - 1, 1)];
    }

    props[@"NumPoints"] = [NSString stringWithFormat:@"%d", (int)raw.points.count];
    props[@"PointData"] = pointData;
    props[@"WorldPosX"] = [NSString stringWithFormat:@"%6.4f", worldPt.x];
    props[@"WorldPosY"] = [NSString stringWithFormat:@"%6.4f", worldPt.y];
    props[@"WorldPosZ"] = @"0.0";
    props[@"versionNumber"] = kModelPosVersion;
}

+ (void)scaleUnconnectedLine:(_XLORS5RawModel *)raw props:(NSMutableDictionary *)props
                        pvwW:(int)pvwW pvwH:(int)pvwH {
    if (raw.points.count == 0) return;

    NSMutableString *pointData = [NSMutableString string];
    int pointCount = 0;
    S5Point worldPt = {0, 0};

    for (NSUInteger i = 0; i + 1 < raw.points.count; i += 2) {
        S5Point pt = [self getPointFromArray:raw.points index:i];
        if (i == 0) {
            worldPt = [self scalePointToXLights:pt pvwW:pvwW pvwH:pvwH];
            [pointData appendString:@"0.0,0.0,0.0,"];
        } else {
            S5Point scaled = [self scalePointToXLights:pt pvwW:pvwW pvwH:pvwH];
            [pointData appendFormat:@"%f,%f,0.0,", scaled.x - worldPt.x, scaled.y - worldPt.y];
        }
        pointCount++;
    }

    S5Point lastRaw = [self getPointFromArray:raw.points index:raw.points.count - 1];
    S5Point lastPt = [self scalePointToXLights:lastRaw pvwW:pvwW pvwH:pvwH];
    [pointData appendFormat:@"%f,%f,0.0", lastPt.x - worldPt.x, lastPt.y - worldPt.y];
    pointCount++;

    props[@"NumPoints"] = [NSString stringWithFormat:@"%d", pointCount];
    props[@"PointData"] = pointData;
    props[@"WorldPosX"] = [NSString stringWithFormat:@"%6.4f", worldPt.x];
    props[@"WorldPosY"] = [NSString stringWithFormat:@"%6.4f", worldPt.y];
    props[@"WorldPosZ"] = @"0.0";
    props[@"versionNumber"] = kModelPosVersion;
}

+ (void)scaleClosedLine:(_XLORS5RawModel *)raw props:(NSMutableDictionary *)props
                   pvwW:(int)pvwW pvwH:(int)pvwH {
    if (raw.points.count == 0) return;

    NSMutableString *pointData = [NSMutableString string];
    S5Point worldPt = {0, 0};

    for (NSUInteger i = 0; i < raw.points.count; i++) {
        S5Point pt = [self getPointFromArray:raw.points index:i];
        if (i == 0) {
            worldPt = [self scalePointToXLights:pt pvwW:pvwW pvwH:pvwH];
            [pointData appendString:@"0.0,0.0,0.0,"];
        } else {
            S5Point scaled = [self scalePointToXLights:pt pvwW:pvwW pvwH:pvwH];
            [pointData appendFormat:@"%f,%f,0.0,", scaled.x - worldPt.x, scaled.y - worldPt.y];
        }
    }
    // Loop back to first point
    [pointData appendString:@"0.0,0.0,0.0"];

    props[@"NumPoints"] = [NSString stringWithFormat:@"%d", (int)raw.points.count + 1];
    props[@"PointData"] = pointData;
    props[@"WorldPosX"] = [NSString stringWithFormat:@"%6.4f", worldPt.x];
    props[@"WorldPosY"] = [NSString stringWithFormat:@"%6.4f", worldPt.y];
    props[@"WorldPosZ"] = @"0.0";
    props[@"versionNumber"] = kModelPosVersion;
}

#pragma mark - Bulb to Custom Model

+ (void)bulbToCustomModel:(_XLORS5RawModel *)raw props:(NSMutableDictionary *)props
                     pvwW:(int)pvwW pvwH:(int)pvwH {
    if (raw.points.count == 0) {
        [self scaleToPreview:raw props:props pvwW:pvwW pvwH:pvwH];
        return;
    }

    // Get min/max of points
    S5Point minPt = {FLT_MAX, FLT_MAX};
    S5Point maxPt = {-FLT_MAX, -FLT_MAX};
    for (NSValue *val in raw.points) {
        S5Point pt;
        [val getValue:&pt];
        minPt.x = MIN(minPt.x, pt.x);
        minPt.y = MIN(minPt.y, pt.y);
        maxPt.x = MAX(maxPt.x, pt.x);
        maxPt.y = MAX(maxPt.y, pt.y);
    }

    S5Point size = { maxPt.x - minPt.x, maxPt.y - minPt.y };
    S5Point center = { minPt.x + size.x / 2.0f, minPt.y + size.y / 2.0f };

    // Find appropriate scale factor
    int scale = 10;
    while (![self findBulbModelScale:scale points:raw.points]) {
        scale += 10;
        if (scale > 101) {
            scale = 100;
            break;
        }
    }

    int scaleMinX = (int)(minPt.x * scale);
    int scaleMinY = (int)(minPt.y * scale);
    int scaleSizeX = (int)(size.x * scale);
    int scaleSizeY = (int)(size.y * scale);

    // Scale all bulb points
    NSMutableArray<NSValue *> *scaledBulbs = [NSMutableArray array];
    for (NSValue *val in raw.points) {
        S5Point pt;
        [val getValue:&pt];
        S5Point scaled = { (float)((int)(pt.x * scale) - scaleMinX),
                          (float)((int)(pt.y * scale) - scaleMinY) };
        [scaledBulbs addObject:[NSValue valueWithBytes:&scaled objCType:@encode(S5Point)]];
    }

    // Build custom model grid
    NSMutableString *cm = [NSMutableString string];
    for (int y = 0; y <= scaleSizeY; y++) {
        for (int x = 0; x <= scaleSizeX; x++) {
            BOOL found = NO;
            for (NSValue *val in scaledBulbs) {
                S5Point pt;
                [val getValue:&pt];
                if ((int)pt.x == x && (int)pt.y == y) {
                    found = YES;
                    break;
                }
            }
            if (found) {
                [cm appendString:@"1,"];
            } else {
                [cm appendString:@","];
            }
        }
        [cm appendString:@";"];
    }
    // Remove last semicolon
    if (cm.length > 0) {
        [cm deleteCharactersInRange:NSMakeRange(cm.length - 1, 1)];
    }

    props[@"parm1"] = [NSString stringWithFormat:@"%d", scaleSizeX + 1];
    props[@"parm2"] = [NSString stringWithFormat:@"%d", scaleSizeY + 1];
    props[@"CustomModel"] = cm;

    // Scale position
    props[@"versionNumber"] = kModelPosVersion;
    S5Point xlCenter = [self scalePointToXLights:center pvwW:pvwW pvwH:pvwH];
    S5Point xlSize = [self getSizeFromScale:size pvwW:pvwW pvwH:pvwH];

    props[@"WorldPosX"] = [NSString stringWithFormat:@"%6.4f", xlCenter.x];
    props[@"WorldPosY"] = [NSString stringWithFormat:@"%6.4f", xlCenter.y];
    props[@"WorldPosZ"] = [NSString stringWithFormat:@"%6.4f", 0.0f];
    props[@"ScaleX"] = [NSString stringWithFormat:@"%6.4f", xlSize.x * (1.0f / scale)];
    props[@"ScaleY"] = [NSString stringWithFormat:@"%6.4f", xlSize.y * (1.0f / scale)];
    props[@"ScaleZ"] = [NSString stringWithFormat:@"%6.4f", xlSize.x * (1.0f / scale)];
    props[@"RotateX"] = @"0.0000";
    props[@"RotateY"] = @"0.0000";
    props[@"RotateZ"] = @"0.0000";
}

+ (BOOL)findBulbModelScale:(int)scale points:(NSArray<NSValue *> *)points {
    if (points.count <= 1) return YES;

    for (NSUInteger i = 0; i < points.count; i++) {
        S5Point pt1;
        [points[i] getValue:&pt1];
        for (NSUInteger j = i + 1; j < points.count; j++) {
            S5Point pt2;
            [points[j] getValue:&pt2];
            if ((int)(pt1.x * scale) == (int)(pt2.x * scale) &&
                (int)(pt1.y * scale) == (int)(pt2.y * scale)) {
                return NO;
            }
        }
    }
    return YES;
}

#pragma mark - Tree Type Decoder

+ (NSString *)decodeTreeType:(NSString *)value {
    NSArray<NSString *> *parts = [value componentsSeparatedByString:@" "];
    if (parts.count > 1) {
        return [NSString stringWithFormat:@"%@ %@", parts[0], parts[1]];
    }
    return @"Tree 360";
}

#pragma mark - Parm Access Helpers

+ (NSString *)parmStr:(_XLORS5RawModel *)raw index:(NSUInteger)idx {
    if (idx < raw.parms.count) {
        return [raw.parms[idx] stringValue];
    }
    return @"0";
}

+ (int)parmInt:(_XLORS5RawModel *)raw index:(NSUInteger)idx {
    if (idx < raw.parms.count) {
        return raw.parms[idx].intValue;
    }
    return 0;
}

@end
