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

/// Objective-C++ bridge to the xlEngine C++ APIs.
///
/// This class converts between NSString/std::string, NSArray/std::vector, etc.
/// and provides Objective-C-friendly methods that internally call into the
/// C++ engine layer (SequenceEngine, ModelEngine, OutputEngine, etc.).
///
/// Pattern reference: xLights/graphics/metal/xlMetalGraphicsContext.mm
///
/// All methods are safe to call from any thread. The underlying C++ engines
/// handle thread safety internally. Callbacks are delivered via NSNotification
/// or delegate patterns (not implemented yet — Phase 1 focus is structure only).
@interface XLEngineBridge : NSObject

#pragma mark - Lifecycle

- (instancetype)init;

#pragma mark - Sequence Operations

- (BOOL)loadSequence:(NSString *)path;
- (BOOL)saveSequence:(NSString *)path;
- (BOOL)closeSequence;
- (BOOL)isSequenceLoaded;

#pragma mark - Playback Control

- (void)play;
- (void)pause;
- (void)stop;
- (void)seek:(NSInteger)positionMS;

#pragma mark - Rendering

- (void)renderAll;
- (void)renderRange:(NSInteger)startMS endMS:(NSInteger)endMS;
- (void)abortRender;

#pragma mark - Model Operations

- (NSArray<NSString *> *)getModelNames;
- (NSDictionary *)getModelInfo:(NSString *)modelName;
- (BOOL)hasModel:(NSString *)modelName;
- (BOOL)updateModelProperty:(NSString *)modelName key:(NSString *)key value:(id)value;

#pragma mark - Output Operations

- (NSArray<NSString *> *)getControllerNames;
- (NSDictionary *)getControllerInfo:(NSString *)controllerName;
- (BOOL)startOutput;
- (void)stopOutput;
- (BOOL)isOutputting;

#pragma mark - Effect Operations

- (NSArray<NSString *> *)getEffectTypes;
- (NSInteger)createEffect:(NSString *)modelName
                    layer:(NSInteger)layer
               effectType:(NSString *)effectType
               startTimeMS:(NSInteger)startMS
                 endTimeMS:(NSInteger)endMS;
- (BOOL)deleteEffect:(NSInteger)effectId;

#pragma mark - Utility

/// Convert std::string to NSString (utility method, publicly exposed for testing)
+ (NSString *)stringFromStdString:(const char *)stdString;

/// Convert NSString to std::string (utility method, publicly exposed for testing)
+ (void)stdStringFromString:(NSString *)nsString buffer:(char **)outBuffer;

@end
