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

/// Check if the engine is available and initialized
- (BOOL)isEngineAvailable;

#pragma mark - Sequence Operations

- (BOOL)loadSequence:(NSString *)path;
- (BOOL)saveSequence:(NSString *)path;
- (BOOL)closeSequence;
- (BOOL)isSequenceLoaded;

/// Create a new sequence with the specified parameters.
/// @param durationMS Duration in milliseconds (0 to use media duration)
/// @param frameMS Frame interval in milliseconds (default: 50 for 20fps)
/// @param mediaFile Optional path to audio file (nil for animation sequence)
/// @return YES if sequence was created successfully
- (BOOL)createSequence:(NSInteger)durationMS
               frameMS:(NSInteger)frameMS
             mediaFile:(NSString * _Nullable)mediaFile;

/// Get information about the currently loaded sequence.
/// Returns nil if no sequence is loaded.
/// Dictionary keys: name, mediaFile, sequenceType, durationMS, frameTimeMS,
///                  numChannels, numFrames, author, song, artist, album, comment
- (NSDictionary *)getSequenceInfo;

#pragma mark - Playback Control

- (void)play;
- (void)pause;
- (void)stop;
- (void)seek:(NSInteger)positionMS;
- (void)seekToStart;
- (void)seekToEnd;
- (void)seekRelative:(NSInteger)deltaMS;

#pragma mark - Playback State

/// Get the current playback state: @"stopped", @"playing", or @"paused"
- (NSString *)getPlaybackState;

/// Get the current playback position in milliseconds
- (NSInteger)getPosition;

/// Get the sequence duration in milliseconds
- (NSInteger)getDuration;

/// Get the frame rate in frames per second
- (NSInteger)getFrameRate;

/// Get the frame time in milliseconds
- (NSInteger)getFrameTimeMS;

#pragma mark - Rendering

- (void)renderAll;
- (void)renderRange:(NSInteger)startMS endMS:(NSInteger)endMS;
- (void)abortRender;

/// Render a single frame at the specified time
- (void)renderFrame:(NSInteger)timeMS;

/// Render a single model at the specified time
- (void)renderModelFrame:(NSString *)modelName timeMS:(NSInteger)timeMS;

/// Get rendered pixel data for a model
/// Returns dictionary with: modelName, width, height, timeMS, pixels (NSData RGBA)
- (NSDictionary *)getFrameBuffer:(NSString *)modelName;

/// Get rendered node data for a model (output to hardware)
/// Returns array of dictionaries with: startChannel, channelCount, data (NSData)
- (NSArray<NSDictionary *> *)getNodeData:(NSString *)modelName;

/// Check if rendering is in progress
- (BOOL)isRendering;

#pragma mark - Model Operations

/// Get all model names (including groups)
- (NSArray<NSString *> *)getModelNames;

/// Get model names excluding groups
- (NSArray<NSString *> *)getModelNamesExcludingGroups;

/// Get group names only
- (NSArray<NSString *> *)getGroupNames;

/// Get detailed model info
- (NSDictionary *)getModelInfo:(NSString *)modelName;

/// Check if a model exists
- (BOOL)hasModel:(NSString *)modelName;

/// Update a model property
- (BOOL)updateModelProperty:(NSString *)modelName key:(NSString *)key value:(id)value;

/// Get a single model property
- (NSString *)getModelProperty:(NSString *)modelName key:(NSString *)key defaultValue:(NSString *)defaultValue;

/// Get all model properties as a dictionary
- (NSDictionary *)getModelProperties:(NSString *)modelName;

/// Create a new model with the given type, name, and properties
- (BOOL)createModel:(NSString *)modelType name:(NSString *)modelName properties:(NSDictionary *)properties;

/// Delete a model by name
- (BOOL)deleteModel:(NSString *)modelName;

/// Rename a model
- (BOOL)renameModel:(NSString *)oldName toName:(NSString *)newName;

/// Duplicate a model
- (BOOL)duplicateModel:(NSString *)modelName;

#pragma mark - Model Groups

/// Get all model groups with their member models
/// Returns array of dictionaries with: name, modelNames (array)
- (NSArray<NSDictionary *> *)getModelGroups;

/// Get a specific model group
/// Returns dictionary with: name, modelNames (array), defaultBufferStyle
- (NSDictionary *)getModelGroup:(NSString *)groupName;

/// Get groups containing a specific model
- (NSArray<NSString *> *)getGroupsContainingModel:(NSString *)modelName;

#pragma mark - Submodels

/// Get submodels of a model
/// Returns array of dictionaries with: name, fullName, nodeCount, channelCount
- (NSArray<NSDictionary *> *)getSubmodels:(NSString *)modelName;

/// Check if a model has a specific submodel
- (BOOL)hasSubmodel:(NSString *)modelName submodelName:(NSString *)submodelName;

#pragma mark - Model Geometry

/// Get node coordinates for a model (for visualization)
/// Returns array of dictionaries with: x, y, z, bufX, bufY, channel, channelCount, stringNum
- (NSArray<NSDictionary *> *)getModelNodes:(NSString *)modelName;

/// Get node count for a model
- (NSUInteger)getModelNodeCount:(NSString *)modelName;

/// Get channel count for a model
- (NSUInteger)getModelChannelCount:(NSString *)modelName;

/// Get bounding box for a model
/// Returns dictionary with: minX, maxX, minY, maxY, minZ, maxZ
- (NSDictionary *)getModelBounds:(NSString *)modelName;

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

/// Get total channel count across all controllers
- (NSInteger)getTotalChannels;

/// Check if output configuration has unsaved changes
- (BOOL)isOutputDirty;

/// Save output configuration
- (BOOL)saveOutputConfiguration;

#pragma mark - Controller Discovery

/// Discover controllers on the network asynchronously.
/// @param completion Block called with array of discovered controller dictionaries when complete.
///   Each dictionary contains: ip, hostname, vendor, model, variant, description, version,
///   mode, platform, majorVersion, minorVersion, patchVersion, alreadyConfigured, existingName.
- (void)discoverControllers:(void (^)(BOOL success, NSArray<NSDictionary *> *controllers))completion;

/// Add a discovered controller to the configuration.
/// @param discoveredInfo Dictionary from discovery results.
/// @return YES if successful.
- (BOOL)addDiscoveredController:(NSDictionary *)discoveredInfo;

/// Test connectivity to a specific controller.
/// @param controllerName Controller to test.
/// @param completion Block called with ping state: @"OK", @"WebOK", @"Open", @"Opened",
///   @"AllFailed", @"Unavailable", or @"Unknown".
- (void)testController:(NSString *)controllerName completion:(void (^)(NSString *pingState))completion;

/// Test connectivity to all controllers.
/// @param completion Block called for each controller with name and ping state.
- (void)testAllControllers:(void (^)(NSString *controllerName, NSString *pingState))completion;

#pragma mark - Controller Upload

/// Upload configuration to a controller.
/// @param controllerName Controller to upload to.
/// @param completion Block called with success status and message.
- (void)uploadToController:(NSString *)controllerName
                completion:(void (^)(BOOL success, NSString *message))completion;

/// Upload input configuration only to a controller.
/// @param controllerName Controller to upload to.
/// @param completion Block called with success status and message.
- (void)uploadInputToController:(NSString *)controllerName
                     completion:(void (^)(BOOL success, NSString *message))completion;

/// Upload output configuration only to a controller.
/// @param controllerName Controller to upload to.
/// @param completion Block called with success status and message.
- (void)uploadOutputToController:(NSString *)controllerName
                      completion:(void (^)(BOOL success, NSString *message))completion;

#pragma mark - Sequence Elements (for Sequencer View)

/// Get the number of elements (rows) in the sequence
- (NSInteger)getSequenceElementCount;

/// Get element info at a given index
/// Returns dictionary with: name, type (timing/model/submodel/strand), effectLayerCount, visible, collapsed
- (NSDictionary *)getSequenceElementAtIndex:(NSInteger)index;

/// Get all elements in the sequence
/// Returns array of element info dictionaries
- (NSArray<NSDictionary *> *)getSequenceElements;

/// Get effects for a sequence element at index and layer
/// Returns array of effect info dictionaries
- (NSArray<NSDictionary *> *)getEffectsForElementAtIndex:(NSInteger)index layer:(NSInteger)layer;

#pragma mark - Effect Operations

/// Get all available effect types
- (NSArray<NSString *> *)getEffectTypes;

/// Get detailed info about an effect type
/// Returns dictionary with: id, name, tooltip, canBeRandom, etc.
- (NSDictionary *)getEffectTypeInfo:(NSString *)effectType;

/// Get parameter definitions for an effect type
/// Returns array of parameter dictionaries with: key, displayLabel, type, minValue, maxValue, etc.
- (NSArray<NSDictionary *> *)getEffectParameters:(NSString *)effectType;

/// Create a new effect. Returns effect ID or -1 on failure.
- (NSInteger)createEffect:(NSString *)modelName
                    layer:(NSInteger)layer
               effectType:(NSString *)effectType
              startTimeMS:(NSInteger)startMS
                endTimeMS:(NSInteger)endMS;

/// Delete an effect by ID
- (BOOL)deleteEffect:(NSInteger)effectId;

/// Get effect info by ID
/// Returns dictionary with: id, effectType, modelName, layerIndex, startTimeMS, endTimeMS, settings, palette, etc.
- (NSDictionary *)getEffect:(NSInteger)effectId;

/// Set a single effect parameter
- (BOOL)setEffectParameter:(NSInteger)effectId key:(NSString *)key value:(NSString *)value;

/// Get a single effect parameter value
- (NSString *)getEffectParameter:(NSInteger)effectId key:(NSString *)key;

/// Set all effect settings at once (serialized settings string)
- (BOOL)setEffectSettings:(NSInteger)effectId settings:(NSString *)settings;

/// Get all effect settings as a serialized string
- (NSString *)getEffectSettings:(NSInteger)effectId;

/// Set the effect palette (colors)
- (BOOL)setEffectPalette:(NSInteger)effectId palette:(NSString *)palette;

/// Get the effect palette as a serialized string
- (NSString *)getEffectPalette:(NSInteger)effectId;

/// Move an effect to a new time range
- (BOOL)moveEffect:(NSInteger)effectId startTimeMS:(NSInteger)startMS endTimeMS:(NSInteger)endMS;

/// Get all effects for a model
- (NSArray<NSDictionary *> *)getEffectsForModel:(NSString *)modelName;

/// Get effects active at a specific time on a model
- (NSArray<NSDictionary *> *)getEffectsAtTime:(NSString *)modelName timeMS:(NSInteger)timeMS;

/// Get effects on a specific layer of a model
- (NSArray<NSDictionary *> *)getEffectsForLayer:(NSString *)modelName layer:(NSInteger)layer;

/// Get the number of effect layers on a model
- (NSInteger)getLayerCount:(NSString *)modelName;

/// Add a new effect layer to a model
- (NSInteger)addLayer:(NSString *)modelName;

/// Remove an effect layer from a model
- (BOOL)removeLayer:(NSString *)modelName layer:(NSInteger)layer;

/// Select an effect
- (BOOL)selectEffect:(NSInteger)effectId;

/// Deselect all effects
- (void)deselectAllEffects;

/// Get IDs of all selected effects
- (NSArray<NSNumber *> *)getSelectedEffectIds;

/// Convert an effect to a different type
- (BOOL)convertEffectType:(NSInteger)effectId newType:(NSString *)newType;

#pragma mark - Audio Operations

/// Get the media file path for the current sequence
/// Returns nil if no sequence is loaded or no media file is set
- (NSString *)getMediaFilePath;

/// Check if audio is loaded for the current sequence
- (BOOL)isAudioLoaded;

/// Get audio file information
/// Returns dictionary with: filePath, durationMS, sampleRate, channels, title, artist, album
- (NSDictionary *)getAudioInfo;

/// Get raw audio samples for a time range (for waveform rendering)
/// Returns dictionary with: leftChannel (NSData of floats), rightChannel (NSData of floats),
///                          sampleCount, sampleRate
- (NSDictionary *)getAudioSamples:(NSInteger)startMS endMS:(NSInteger)endMS;

/// Get min/max amplitude for a time range (for quick waveform overview)
/// Returns dictionary with: minLeft, maxLeft, minRight, maxRight
- (NSDictionary *)getAudioAmplitudeRange:(NSInteger)startMS endMS:(NSInteger)endMS;

/// Set audio playback volume (0-100)
- (void)setAudioVolume:(NSInteger)volume;

/// Get current audio playback volume
- (NSInteger)getAudioVolume;

#pragma mark - Utility

/// Convert std::string to NSString (utility method, publicly exposed for testing)
+ (NSString *)stringFromStdString:(const char *)stdString;

/// Convert NSString to std::string (utility method, publicly exposed for testing)
+ (void)stdStringFromString:(NSString *)nsString buffer:(char **)outBuffer;

@end
