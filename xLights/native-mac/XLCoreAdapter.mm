/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLCoreAdapter.h"
#include "../xlCore/XLCoreBridge.h"

// ============================================================================
// XLCoreEffectParameter Implementation
// ============================================================================

@interface XLCoreEffectParameter ()
@property (nonatomic, copy, readwrite) NSString *key;
@property (nonatomic, copy, readwrite) NSString *displayName;
@property (nonatomic, copy, readwrite) NSString *paramDescription;
@property (nonatomic, assign, readwrite) XLCoreParameterType type;
@property (nonatomic, copy, readwrite) NSString *defaultValue;
@property (nonatomic, assign, readwrite) double minValue;
@property (nonatomic, assign, readwrite) double maxValue;
@property (nonatomic, assign, readwrite) double step;
@property (nonatomic, assign, readwrite) BOOL supportsValueCurve;
@end

@implementation XLCoreEffectParameter
@end

// ============================================================================
// XLCoreEffectInfo Implementation
// ============================================================================

@interface XLCoreEffectInfo ()
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *effectDescription;
@property (nonatomic, copy, readwrite) NSString *category;
@property (nonatomic, copy, readwrite) NSString *tooltip;
@property (nonatomic, assign, readwrite) BOOL canBeRandom;
@property (nonatomic, assign, readwrite) BOOL supportsRenderCache;
@property (nonatomic, assign, readwrite) BOOL canRenderOnBackgroundThread;
@property (nonatomic, assign, readwrite) NSInteger colorCount;
@property (nonatomic, strong, readwrite) NSArray<XLCoreEffectParameter *> *parameters;
@end

@implementation XLCoreEffectInfo
@end

// ============================================================================
// XLCoreRenderStats Implementation
// ============================================================================

@interface XLCoreRenderStats ()
@property (nonatomic, assign, readwrite) NSUInteger framesRendered;
@property (nonatomic, assign, readwrite) NSUInteger cacheHits;
@property (nonatomic, assign, readwrite) NSUInteger cacheMisses;
@property (nonatomic, assign, readwrite) double avgRenderTimeMs;
@property (nonatomic, assign, readwrite) double totalRenderTimeMs;
@end

@implementation XLCoreRenderStats
@end

// ============================================================================
// XLCoreRenderedFrame Implementation
// ============================================================================

@interface XLCoreRenderedFrame ()
@property (nonatomic, copy, readwrite) NSString *modelName;
@property (nonatomic, assign, readwrite) NSInteger width;
@property (nonatomic, assign, readwrite) NSInteger height;
@property (nonatomic, assign, readwrite) NSInteger timeMS;
@property (nonatomic, strong, readwrite) NSData *pixelData;
@end

@implementation XLCoreRenderedFrame
@end

// ============================================================================
// XLCoreAdapter Implementation
// ============================================================================

@interface XLCoreAdapter ()
@property (nonatomic, assign) XLCoreEngineRef engineRef;
@end

@implementation XLCoreAdapter

#pragma mark - Lifecycle

+ (instancetype)sharedAdapter {
    static XLCoreAdapter *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[XLCoreAdapter alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _engineRef = XLCoreEngineCreate();
        if (_engineRef) {
            NSLog(@"XLCoreAdapter: Engine created successfully");
        } else {
            NSLog(@"XLCoreAdapter: Failed to create engine");
        }
    }
    return self;
}

- (void)dealloc {
    if (_engineRef) {
        XLCoreEngineDestroy(_engineRef);
        _engineRef = NULL;
    }
}

- (BOOL)isReady {
    return _engineRef && XLCoreEngineIsInitialized(_engineRef);
}

#pragma mark - Effect Information

- (NSArray<NSString *> *)effectNames {
    if (!_engineRef) return @[];

    int count = XLCoreGetEffectCount(_engineRef);
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:count];

    char buffer[256];
    for (int i = 0; i < count; i++) {
        int len = XLCoreGetEffectNameAtIndex(_engineRef, i, buffer, sizeof(buffer));
        if (len > 0) {
            [names addObject:@(buffer)];
        }
    }

    return [names copy];
}

- (NSArray<NSString *> *)categoryNames {
    if (!_engineRef) return @[];

    int count = XLCoreGetCategoryCount(_engineRef);
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:count];

    char buffer[256];
    for (int i = 0; i < count; i++) {
        int len = XLCoreGetCategoryNameAtIndex(_engineRef, i, buffer, sizeof(buffer));
        if (len > 0) {
            [names addObject:@(buffer)];
        }
    }

    return [names copy];
}

- (NSArray<NSString *> *)effectsInCategory:(NSString *)categoryName {
    if (!_engineRef || !categoryName) return @[];

    int count = XLCoreGetEffectsInCategoryCount(_engineRef, [categoryName UTF8String]);
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:count];

    char buffer[256];
    for (int i = 0; i < count; i++) {
        int len = XLCoreGetEffectInCategoryAtIndex(_engineRef, [categoryName UTF8String],
                                                    i, buffer, sizeof(buffer));
        if (len > 0) {
            [names addObject:@(buffer)];
        }
    }

    return [names copy];
}

- (BOOL)hasEffect:(NSString *)effectName {
    if (!_engineRef || !effectName) return NO;
    return XLCoreHasEffect(_engineRef, [effectName UTF8String]);
}

- (nullable XLCoreEffectInfo *)effectInfo:(NSString *)effectName {
    if (!_engineRef || !effectName) return nil;
    if (!XLCoreHasEffect(_engineRef, [effectName UTF8String])) return nil;

    XLCoreEffectInfo *info = [[XLCoreEffectInfo alloc] init];
    info.name = effectName;

    char buffer[512];

    int len = XLCoreGetEffectDescription(_engineRef, [effectName UTF8String],
                                          buffer, sizeof(buffer));
    info.effectDescription = len > 0 ? @(buffer) : @"";

    len = XLCoreGetEffectCategory(_engineRef, [effectName UTF8String],
                                   buffer, sizeof(buffer));
    info.category = len > 0 ? @(buffer) : @"Misc";

    info.tooltip = info.effectDescription;
    info.parameters = [self parametersForEffect:effectName];

    return info;
}

- (NSArray<XLCoreEffectParameter *> *)parametersForEffect:(NSString *)effectName {
    if (!_engineRef || !effectName) return @[];

    int count = XLCoreGetEffectParameterCount(_engineRef, [effectName UTF8String]);
    NSMutableArray<XLCoreEffectParameter *> *params = [NSMutableArray arrayWithCapacity:count];

    for (int i = 0; i < count; i++) {
        XLCoreParameterInfo cInfo;
        if (XLCoreGetEffectParameterInfo(_engineRef, [effectName UTF8String], i, &cInfo)) {
            XLCoreEffectParameter *param = [[XLCoreEffectParameter alloc] init];
            param.key = @(cInfo.key);
            param.displayName = @(cInfo.displayName);
            param.paramDescription = @(cInfo.description);
            param.type = (XLCoreParameterType)cInfo.type;
            param.defaultValue = @(cInfo.defaultValue);
            param.minValue = cInfo.minValue;
            param.maxValue = cInfo.maxValue;
            param.step = cInfo.step;
            param.supportsValueCurve = cInfo.supportsValueCurve;

            [params addObject:param];
        }
    }

    return [params copy];
}

#pragma mark - Effect Rendering

- (nullable NSString *)settingsStringFromDictionary:(NSDictionary<NSString *, id> *)settings {
    if (!settings || settings.count == 0) return @"";

    NSMutableArray<NSString *> *pairs = [NSMutableArray arrayWithCapacity:settings.count];
    for (NSString *key in settings) {
        id value = settings[key];
        NSString *valueStr;

        if ([value isKindOfClass:[NSNumber class]]) {
            valueStr = [value stringValue];
        } else if ([value isKindOfClass:[NSString class]]) {
            valueStr = value;
        } else {
            valueStr = [value description];
        }

        [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, valueStr]];
    }

    return [pairs componentsJoinedByString:@","];
}

- (nullable NSData *)renderEffectPreview:(NSString *)effectName
                                settings:(NSDictionary<NSString *, id> *)settings
                                   width:(NSInteger)width
                                  height:(NSInteger)height
                                progress:(double)progress {
    return [self renderEffect:effectName
                     settings:settings
                        width:width
                       height:height
                  timeSeconds:progress
                    startTime:0.0
                      endTime:1.0];
}

- (nullable NSData *)renderEffect:(NSString *)effectName
                         settings:(NSDictionary<NSString *, id> *)settings
                            width:(NSInteger)width
                           height:(NSInteger)height
                      timeSeconds:(double)timeSeconds
                        startTime:(double)startTime
                          endTime:(double)endTime {
    if (!_engineRef || !effectName || width <= 0 || height <= 0) return nil;

    // Create render context
    XLCoreRenderContextRef ctx = XLCoreRenderContextCreate((int)width, (int)height);
    if (!ctx) return nil;

    // Clear to transparent
    XLCoreRenderContextClearTransparent(ctx);

    // Build settings string
    NSString *settingsStr = [self settingsStringFromDictionary:settings];

    // Render
    bool success = XLCoreRenderEffectWithTiming(ctx,
                                                 [effectName UTF8String],
                                                 [settingsStr UTF8String],
                                                 timeSeconds,
                                                 startTime,
                                                 endTime,
                                                 0);

    NSData *result = nil;
    if (success) {
        const uint8_t *pixels = XLCoreRenderContextGetPixelData(ctx);
        size_t size = XLCoreRenderContextGetPixelDataSize(ctx);
        if (pixels && size > 0) {
            result = [NSData dataWithBytes:pixels length:size];
        }
    }

    XLCoreRenderContextDestroy(ctx);
    return result;
}

#pragma mark - Render Pipeline

- (void)initializePipelineWithDuration:(NSInteger)durationMS
                       frameIntervalMS:(NSInteger)frameIntervalMS {
    // Pipeline is internally managed by the engine
    // This method is for API compatibility
}

- (void)addModelToPipeline:(NSString *)modelName
               bufferWidth:(NSInteger)width
              bufferHeight:(NSInteger)height {
    if (!_engineRef || !modelName) return;
    XLCoreAddModelToPipeline(_engineRef, [modelName UTF8String], (int)width, (int)height);
}

- (void)removeModelFromPipeline:(NSString *)modelName {
    // The C API doesn't have this yet, so this is a no-op
    // Future implementation would call XLCoreRemoveModelFromPipeline
}

- (nullable XLCoreRenderedFrame *)renderModelFrame:(NSString *)modelName
                                            timeMS:(NSInteger)timeMS {
    if (!_engineRef || !modelName) return nil;

    // Get model dimensions from pipeline config
    // For now, we'll use a default size since we don't have access to the config
    // In a full implementation, we'd query the pipeline for the model's buffer dimensions
    NSInteger width = 50;
    NSInteger height = 50;

    size_t bufferSize = (size_t)(width * height * 4);
    uint8_t *buffer = (uint8_t *)malloc(bufferSize);
    if (!buffer) return nil;

    bool success = XLCoreRenderModelFrame(_engineRef,
                                           [modelName UTF8String],
                                           (int)timeMS,
                                           buffer,
                                           bufferSize);

    if (!success) {
        free(buffer);
        return nil;
    }

    XLCoreRenderedFrame *frame = [[XLCoreRenderedFrame alloc] init];
    frame.modelName = modelName;
    frame.width = width;
    frame.height = height;
    frame.timeMS = timeMS;
    frame.pixelData = [NSData dataWithBytesNoCopy:buffer length:bufferSize freeWhenDone:YES];

    return frame;
}

- (BOOL)isRendering {
    if (!_engineRef) return NO;
    return XLCoreIsRendering(_engineRef);
}

- (void)abortRender {
    if (_engineRef) {
        XLCoreAbortRender(_engineRef);
    }
}

#pragma mark - Statistics

- (XLCoreRenderStats *)renderStats {
    XLCoreRenderStats *stats = [[XLCoreRenderStats alloc] init];

    if (_engineRef) {
        XLCoreRenderStatistics cStats;
        XLCoreGetRenderStatistics(_engineRef, &cStats);

        stats.framesRendered = cStats.framesRendered;
        stats.cacheHits = cStats.cacheHits;
        stats.cacheMisses = cStats.cacheMisses;
        stats.avgRenderTimeMs = cStats.avgRenderTimeMs;
        stats.totalRenderTimeMs = cStats.totalRenderTimeMs;
    }

    return stats;
}

- (void)resetRenderStats {
    if (_engineRef) {
        XLCoreResetRenderStatistics(_engineRef);
    }
}

#pragma mark - Color Utilities

- (BOOL)parseColorString:(NSString *)colorStr
                     red:(NSUInteger *)red
                   green:(NSUInteger *)green
                    blue:(NSUInteger *)blue {
    if (!colorStr || !red || !green || !blue) return NO;

    uint8_t r, g, b;
    bool success = XLCoreParseColor([colorStr UTF8String], &r, &g, &b);

    if (success) {
        *red = r;
        *green = g;
        *blue = b;
    }

    return success;
}

- (NSString *)colorStringFromRed:(NSUInteger)red
                           green:(NSUInteger)green
                            blue:(NSUInteger)blue {
    char buffer[16];
    XLCoreColorToString((uint8_t)red, (uint8_t)green, (uint8_t)blue, buffer, sizeof(buffer));
    return @(buffer);
}

- (void)convertHSVToRGBWithHue:(double)hue
                    saturation:(double)saturation
                         value:(double)value
                           red:(NSUInteger *)red
                         green:(NSUInteger *)green
                          blue:(NSUInteger *)blue {
    if (!red || !green || !blue) return;

    uint8_t r, g, b;
    XLCoreHSVToRGB(hue, saturation, value, &r, &g, &b);

    *red = r;
    *green = g;
    *blue = b;
}

- (void)convertRGBToHSVWithRed:(NSUInteger)red
                         green:(NSUInteger)green
                          blue:(NSUInteger)blue
                           hue:(double *)hue
                    saturation:(double *)saturation
                         value:(double *)value {
    if (!hue || !saturation || !value) return;

    XLCoreRGBToHSV((uint8_t)red, (uint8_t)green, (uint8_t)blue, hue, saturation, value);
}

@end
