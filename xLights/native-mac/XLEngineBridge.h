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

/// Create a new model with the given type, name, and properties
- (BOOL)createModel:(NSString *)modelType name:(NSString *)modelName properties:(NSDictionary *)properties;

/// Delete a model by name
- (BOOL)deleteModel:(NSString *)modelName;

/// Rename a model
- (BOOL)renameModel:(NSString *)oldName toName:(NSString *)newName;

/// Duplicate a model
- (BOOL)duplicateModel:(NSString *)modelName;

#pragma mark - Model Import Operations

/// Import a model from a .xmodel file
- (BOOL)importModelFromFile:(NSString *)filePath;

/// Import a specific model from a sequence/layout file
- (BOOL)importModelFromFile:(NSString *)filePath modelName:(NSString *)modelName;

/// Get list of models contained in a file (for sequence/layout files)
- (NSArray<NSDictionary *> *)getModelsInFile:(NSString *)filePath;

#pragma mark - Output Operations

- (NSArray<NSString *> *)getControllerNames;
- (NSDictionary *)getControllerInfo:(NSString *)controllerName;
- (BOOL)startOutput;
- (void)stopOutput;
- (BOOL)isOutputting;

#pragma mark - Port Configuration

/// Get port configurations for a controller.
/// Returns an array of dictionaries with port info:
///   @"port", @"type", @"protocol", @"startChannel", @"channelCount",
///   @"brightness", @"gamma", @"colorOrder", @"smartRemote"
- (NSArray<NSDictionary *> *)getPortsForController:(NSString *)controllerName;

/// Update a port configuration.
/// @param controllerName The controller containing the port.
/// @param portNumber The port number (1-indexed).
/// @param properties Dictionary of properties to update.
/// @return YES if successful.
- (BOOL)updatePort:(NSString *)controllerName
              port:(NSInteger)portNumber
        properties:(NSDictionary *)properties;

/// Assign a model to a port.
/// @param modelName The model to assign.
/// @param controllerName The controller name.
/// @param portNumber The port number (1-indexed).
/// @return YES if successful.
- (BOOL)assignModel:(NSString *)modelName
       toController:(NSString *)controllerName
               port:(NSInteger)portNumber;

/// Remove model assignment from a port.
/// @param controllerName The controller name.
/// @param portNumber The port number.
/// @return YES if successful.
- (BOOL)removeModelFromController:(NSString *)controllerName
                             port:(NSInteger)portNumber;

/// Get controller capabilities (max ports, protocols, etc.)
- (NSDictionary *)getControllerCapabilities:(NSString *)controllerName;

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
