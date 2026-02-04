/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

/**
 * @file XLCoreAdapter.h
 * @brief Objective-C adapter for xlCore library.
 *
 * This class provides an Objective-C interface to the xlCore library,
 * allowing native macOS code to use the modernized rendering engine.
 *
 * XLCoreAdapter can be used alongside or as a replacement for XLEngineBridge.
 * During the transition period, XLEngineBridge delegates to legacy xLightsFrame
 * while XLCoreAdapter uses the pure C++ xlCore library directly.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @brief Parameter type enumeration matching xlCore::ParameterType.
 */
typedef NS_ENUM(NSInteger, XLCoreParameterType) {
    XLCoreParameterTypeInt = 0,
    XLCoreParameterTypeDouble = 1,
    XLCoreParameterTypeBool = 2,
    XLCoreParameterTypeString = 3,
    XLCoreParameterTypeColor = 4,
    XLCoreParameterTypeChoice = 5,
    XLCoreParameterTypeFile = 6,
    XLCoreParameterTypeValueCurve = 7,
    XLCoreParameterTypeColorCurve = 8
};

/**
 * @brief Effect parameter information.
 */
@interface XLCoreEffectParameter : NSObject

@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, copy, readonly) NSString *paramDescription;
@property (nonatomic, assign, readonly) XLCoreParameterType type;
@property (nonatomic, copy, readonly) NSString *defaultValue;
@property (nonatomic, assign, readonly) double minValue;
@property (nonatomic, assign, readonly) double maxValue;
@property (nonatomic, assign, readonly) double step;
@property (nonatomic, assign, readonly) BOOL supportsValueCurve;

@end

/**
 * @brief Effect information.
 */
@interface XLCoreEffectInfo : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *effectDescription;
@property (nonatomic, copy, readonly) NSString *category;
@property (nonatomic, copy, readonly) NSString *tooltip;
@property (nonatomic, assign, readonly) BOOL canBeRandom;
@property (nonatomic, assign, readonly) BOOL supportsRenderCache;
@property (nonatomic, assign, readonly) BOOL canRenderOnBackgroundThread;
@property (nonatomic, assign, readonly) NSInteger colorCount;
@property (nonatomic, strong, readonly) NSArray<XLCoreEffectParameter *> *parameters;

@end

/**
 * @brief Render statistics.
 */
@interface XLCoreRenderStats : NSObject

@property (nonatomic, assign, readonly) NSUInteger framesRendered;
@property (nonatomic, assign, readonly) NSUInteger cacheHits;
@property (nonatomic, assign, readonly) NSUInteger cacheMisses;
@property (nonatomic, assign, readonly) double avgRenderTimeMs;
@property (nonatomic, assign, readonly) double totalRenderTimeMs;

@end

/**
 * @brief Rendered frame data.
 */
@interface XLCoreRenderedFrame : NSObject

@property (nonatomic, copy, readonly) NSString *modelName;
@property (nonatomic, assign, readonly) NSInteger width;
@property (nonatomic, assign, readonly) NSInteger height;
@property (nonatomic, assign, readonly) NSInteger timeMS;
@property (nonatomic, strong, readonly) NSData *pixelData; // RGBA, 4 bytes per pixel

@end

/**
 * @brief Objective-C adapter for xlCore library.
 *
 * This adapter provides a native Objective-C interface to the xlCore
 * rendering engine. It can be used instead of or alongside XLEngineBridge.
 *
 * Usage:
 * 1. Get the shared instance via +sharedAdapter
 * 2. Query effects and their parameters
 * 3. Render effects to pixel buffers
 * 4. Use the render pipeline for sequence rendering
 */
@interface XLCoreAdapter : NSObject

#pragma mark - Lifecycle

/**
 * @brief Get the shared adapter instance.
 */
+ (instancetype)sharedAdapter;

/**
 * @brief Check if the adapter is initialized and ready.
 */
@property (nonatomic, readonly) BOOL isReady;

#pragma mark - Effect Information

/**
 * @brief Get all registered effect names.
 */
- (NSArray<NSString *> *)effectNames;

/**
 * @brief Get all effect category names.
 */
- (NSArray<NSString *> *)categoryNames;

/**
 * @brief Get effect names in a specific category.
 */
- (NSArray<NSString *> *)effectsInCategory:(NSString *)categoryName;

/**
 * @brief Check if an effect is registered.
 */
- (BOOL)hasEffect:(NSString *)effectName;

/**
 * @brief Get detailed effect information.
 */
- (nullable XLCoreEffectInfo *)effectInfo:(NSString *)effectName;

/**
 * @brief Get parameters for an effect.
 */
- (NSArray<XLCoreEffectParameter *> *)parametersForEffect:(NSString *)effectName;

#pragma mark - Effect Rendering

/**
 * @brief Render an effect preview.
 *
 * @param effectName Effect type name
 * @param settings Settings dictionary (key=NSString, value=NSString or NSNumber)
 * @param width Buffer width
 * @param height Buffer height
 * @param progress Progress value (0.0 to 1.0)
 * @return Pixel data (RGBA, 4 bytes per pixel) or nil on failure
 */
- (nullable NSData *)renderEffectPreview:(NSString *)effectName
                                settings:(NSDictionary<NSString *, id> *)settings
                                   width:(NSInteger)width
                                  height:(NSInteger)height
                                progress:(double)progress;

/**
 * @brief Render an effect with full timing control.
 *
 * @param effectName Effect type name
 * @param settings Settings dictionary
 * @param width Buffer width
 * @param height Buffer height
 * @param timeSeconds Current time in seconds
 * @param startTime Effect start time in seconds
 * @param endTime Effect end time in seconds
 * @return Pixel data (RGBA, 4 bytes per pixel) or nil on failure
 */
- (nullable NSData *)renderEffect:(NSString *)effectName
                         settings:(NSDictionary<NSString *, id> *)settings
                            width:(NSInteger)width
                           height:(NSInteger)height
                      timeSeconds:(double)timeSeconds
                        startTime:(double)startTime
                          endTime:(double)endTime;

#pragma mark - Render Pipeline

/**
 * @brief Initialize the render pipeline for a duration.
 *
 * @param durationMS Sequence duration in milliseconds
 * @param frameIntervalMS Frame interval in milliseconds
 */
- (void)initializePipelineWithDuration:(NSInteger)durationMS
                       frameIntervalMS:(NSInteger)frameIntervalMS;

/**
 * @brief Add a model to the render pipeline.
 */
- (void)addModelToPipeline:(NSString *)modelName
               bufferWidth:(NSInteger)width
              bufferHeight:(NSInteger)height;

/**
 * @brief Remove a model from the render pipeline.
 */
- (void)removeModelFromPipeline:(NSString *)modelName;

/**
 * @brief Render a single frame for a model.
 */
- (nullable XLCoreRenderedFrame *)renderModelFrame:(NSString *)modelName
                                            timeMS:(NSInteger)timeMS;

/**
 * @brief Check if rendering is in progress.
 */
@property (nonatomic, readonly) BOOL isRendering;

/**
 * @brief Abort rendering in progress.
 */
- (void)abortRender;

#pragma mark - Statistics

/**
 * @brief Get render statistics.
 */
- (XLCoreRenderStats *)renderStats;

/**
 * @brief Reset render statistics.
 */
- (void)resetRenderStats;

#pragma mark - Color Utilities

/**
 * @brief Parse a color string to RGB components.
 */
- (BOOL)parseColorString:(NSString *)colorStr
                     red:(NSUInteger *)red
                   green:(NSUInteger *)green
                    blue:(NSUInteger *)blue;

/**
 * @brief Convert RGB to color string.
 */
- (NSString *)colorStringFromRed:(NSUInteger)red
                           green:(NSUInteger)green
                            blue:(NSUInteger)blue;

/**
 * @brief Convert HSV to RGB.
 */
- (void)convertHSVToRGBWithHue:(double)hue
                    saturation:(double)saturation
                         value:(double)value
                           red:(NSUInteger *)red
                         green:(NSUInteger *)green
                          blue:(NSUInteger *)blue;

/**
 * @brief Convert RGB to HSV.
 */
- (void)convertRGBToHSVWithRed:(NSUInteger)red
                         green:(NSUInteger)green
                          blue:(NSUInteger)blue
                           hue:(double *)hue
                    saturation:(double *)saturation
                         value:(double *)value;

@end

NS_ASSUME_NONNULL_END
