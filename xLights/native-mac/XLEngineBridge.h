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
///
/// Standalone Operation (Phase 4: Decoupling):
/// XLEngineBridge can now operate without wxWidgets. In standalone mode, it uses
/// native providers (NativeModelProvider, NativeSequenceProvider, etc.) instead
/// of wrapping xLightsFrame. This enables the native macOS UI to function
/// independently of the wxWidgets application.
///
/// Usage:
/// - For standalone native app: [XLEngineBridge sharedBridge] uses native providers
/// - For hybrid operation during transition: initWithLegacySupport: wraps xLightsFrame
@interface XLEngineBridge : NSObject

#pragma mark - Lifecycle

/// Default initializer for standalone native operation.
/// Creates native providers (no wxWidgets dependencies).
- (instancetype)init;

/// Initializer for legacy/hybrid operation.
/// When enabled, wraps xLightsFrame for full compatibility during transition.
/// @param legacySupport If YES, uses xLightsFrame adapters when available.
///                      If NO, uses native providers only.
- (instancetype)initWithLegacySupport:(BOOL)legacySupport;

/// Shared singleton instance for standalone native operation.
/// Uses native providers only - no wxWidgets dependencies.
@property (class, readonly, strong) XLEngineBridge *sharedBridge;

/// Check if the engine is available and initialized
- (BOOL)isEngineAvailable;

/// Check if running in standalone mode (native providers only)
- (BOOL)isStandaloneMode;

/// Load show folder to initialize models and outputs.
/// Required for standalone mode before loading sequences.
/// @param showFolderPath Path to xLights show folder containing rgbeffects.xml
/// @return YES if show folder was loaded successfully
- (BOOL)loadShowFolder:(NSString *)showFolderPath;

/// Get the currently loaded show folder path.
/// Returns nil if no show folder is loaded.
- (NSString *)getShowFolderPath;

#pragma mark - Sequence Operations

- (BOOL)loadSequence:(NSString *)path;
- (BOOL)saveSequence:(NSString *)path;
- (BOOL)closeSequence;
- (BOOL)isSequenceLoaded;

/// Create a new sequence with the specified parameters.
/// @param name Sequence name (display name, used as filename when saving)
/// @param durationMS Duration in milliseconds (0 to use media duration)
/// @param frameMS Frame interval in milliseconds (default: 50 for 20fps)
/// @param mediaFile Optional path to audio file (nil for animation sequence)
/// @return YES if sequence was created successfully
- (BOOL)createSequence:(NSString *)name
            durationMS:(NSInteger)durationMS
               frameMS:(NSInteger)frameMS
             mediaFile:(NSString * _Nullable)mediaFile;

/// Get information about the currently loaded sequence.
/// Returns nil if no sequence is loaded.
/// Dictionary keys: name, mediaFile, sequenceType, durationMS, frameTimeMS,
///                  numChannels, numFrames, author, song, artist, album, comment
- (NSDictionary *)getSequenceInfo;

/// Audio stem references for XML persistence.
/// Set by the sequencer view controller when stems are imported/removed.
/// Array of dicts with keys: name, relativePath, color (#RRGGBB).
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *audioStemDicts;

/// Update sequence metadata (author, song info, comments, etc.).
/// Only modifies fields present in the dictionary; omitted keys are left unchanged.
/// Supported keys: author, song, artist, album, comment
/// @param info Dictionary of metadata fields to update
/// @return YES if the update was applied successfully
- (BOOL)setSequenceInfo:(NSDictionary *)info;

/// Render a sequence file to FSEQ output.
/// Loads the sequence, renders all effects, writes FSEQ, then closes.
/// @param sequencePath Full path to the .xsq/.xml sequence file
/// @param outputPath Full path for .fseq output (nil = same directory as sequence)
/// @param completion Called on main thread with success status and message
- (void)renderSequenceToFSEQ:(NSString *)sequencePath
                  outputPath:(NSString * _Nullable)outputPath
                  completion:(void (^)(BOOL success, NSString *message))completion;

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
- (void)forceRenderAll;
- (void)renderRange:(NSInteger)startMS endMS:(NSInteger)endMS;
- (void)abortRender;

/// Render a single frame at the specified time
- (void)renderFrame:(NSInteger)timeMS;

/// Render a single model at the specified time
- (void)renderModelFrame:(NSString *)modelName timeMS:(NSInteger)timeMS;

/// Get rendered pixel data for a model
/// Returns dictionary with: modelName, width, height, timeMS, pixels (NSData RGBA)
- (NSDictionary *)getFrameBuffer:(NSString *)modelName;

/// Get all rendered frame buffers in a single call.
/// Returns only models with valid pixel data. Much more efficient than
/// calling getFrameBuffer: for each model individually.
- (NSArray<NSDictionary *> *)getAllFrameBuffers;

/// Zero-copy frame buffer iteration.  The block is invoked once per valid
/// buffer while the engine holds its internal lock.  The pixel pointer is
/// only valid for the duration of the block call; callers that need the
/// data beyond that must copy it (e.g. into NSData).
- (void)enumerateFrameBuffersWithBlock:(void (^)(NSString *modelName,
                                                 const uint8_t *pixels,
                                                 NSUInteger pixelBytes,
                                                 NSUInteger width,
                                                 NSUInteger height))block;

/// Get pre-rendered pixel data for a model at a specific time.
/// This reads from the pre-rendered SequenceData (after renderAll) and does NOT trigger
/// a new render. Suitable for use during playback. Returns nil if data is not available.
/// Returns dictionary with: modelName, width, height, timeMS, pixels (NSData RGBA)
- (NSDictionary *)getPrerenderedFrameBuffer:(NSString *)modelName timeMS:(NSInteger)timeMS;

/// Get rendered node data for a model (output to hardware)
/// Returns array of dictionaries with: startChannel, channelCount, data (NSData)
- (NSArray<NSDictionary *> *)getNodeData:(NSString *)modelName;

/// Check if rendering is in progress
- (BOOL)isRendering;

/// Get render progress (0.0 to 1.0)
- (float)getRenderProgress;

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

/// Get a single model property (convenience, uses empty default)
- (NSString *)getModelProperty:(NSString *)modelName key:(NSString *)key;

/// Get all model properties as a dictionary
- (NSDictionary *)getModelProperties:(NSString *)modelName;

/// Get the smart remote number for a model (0=None, 1=A, 2=B, 3=C, etc.)
- (NSInteger)getSmartRemote:(NSString *)modelName;

/// Get the smart remote type for a model
- (NSString *)getSmartRemoteType:(NSString *)modelName;

/// Set the smart remote number for a model (0=None, 1=A, 2=B, 3=C, etc.)
- (BOOL)setSmartRemote:(NSString *)modelName value:(NSInteger)smartRemote;

/// Set the smart remote type for a model
- (BOOL)setSmartRemoteType:(NSString *)modelName value:(NSString *)type;

/// Get dimming curve info for a model.
/// Returns dictionary with keys "all", "red", "green", "blue" containing
/// sub-dictionaries with "gamma", "brightness", and/or "filename" keys.
/// Returns empty dictionary if no dimming curve is configured.
- (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)getDimmingInfo:(NSString *)modelName;

/// Set dimming curve info for a model.
/// Pass an empty dictionary (or nil) to clear the dimming curve.
/// @param dimmingInfo Dictionary with channel keys ("all", "red", "green", "blue")
///                     mapping to parameter dictionaries ("gamma", "brightness", "filename")
/// @param modelName Name of the model to update
/// @return YES if the dimming info was set successfully
- (BOOL)setDimmingInfo:(NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)dimmingInfo
              forModel:(NSString *)modelName;

/// Create a new model with the given type, name, and properties
- (BOOL)createModel:(NSString *)modelType name:(NSString *)modelName properties:(NSDictionary *)properties;

/// Delete a model by name
- (BOOL)deleteModel:(NSString *)modelName;

/// Rename a model
- (BOOL)renameModel:(NSString *)oldName toName:(NSString *)newName;

/// Duplicate a model
- (BOOL)duplicateModel:(NSString *)modelName;

/// Duplicate a model and return the new name
- (NSString *)duplicateModelReturningName:(NSString *)modelName;

/// Replace one model with another: the replacement takes the target's name, position,
/// controller assignment, and group memberships. The target model is deleted.
/// Options dictionary controls behavior:
///   @"copyStartChannel" (BOOL) - copy the target's start channel to the replacement
///   @"copyPosition" (BOOL) - copy the target's position, size, and rotation to the replacement
///   @"mergeSubmodels" (BOOL) - merge the target's submodels into the replacement
/// Returns YES if the replacement was successful.
- (BOOL)replaceModel:(NSString *)targetModelName
            withModel:(NSString *)replacementModelName
              options:(NSDictionary *)options;

/// Create a shadow model for the given source model
- (NSString *)createShadowModel:(NSString *)sourceModelName;

/// Check if a model is a shadow model
- (BOOL)isShadowModel:(NSString *)modelName;

/// Get the name of the model that a shadow model mirrors
- (NSString *)getShadowModelFor:(NSString *)modelName;

/// Set or clear the shadow model target for a model
- (BOOL)setShadowModelFor:(NSString *)modelName target:(NSString *)targetModelName;

/// Get names of all models that shadow a given model
- (NSArray<NSString *> *)getModelsShadowing:(NSString *)modelName;

/// Get complete model data for undo/redo serialization
/// Returns all properties needed to recreate the model
- (NSDictionary *)getModelData:(NSString *)modelName;

/// Create a model from serialized data (for undo/redo)
/// @param modelData Dictionary containing model properties from getModelData:
/// @param modelName Name for the model
/// @return YES if successful
- (BOOL)createModelFromData:(NSDictionary *)modelData withName:(NSString *)modelName;

#pragma mark - Model Groups

/// Get all model groups with their member models
/// Returns array of dictionaries with: name, modelNames (array)
- (NSArray<NSDictionary *> *)getModelGroups;

/// Get a specific model group
/// Returns dictionary with: name, modelNames (array), defaultBufferStyle
- (NSDictionary *)getModelGroup:(NSString *)groupName;

/// Get groups containing a specific model
- (NSArray<NSString *> *)getGroupsContainingModel:(NSString *)modelName;

/// Create a new model group
/// @param groupName Name for the new group
/// @param modelNames Array of model names to include in the group (nil or empty for empty group)
/// @return YES if the group was created successfully
- (BOOL)createModelGroup:(NSString *)groupName withModels:(NSArray<NSString *> * _Nullable)modelNames;

/// Delete a model group
/// @param groupName Name of the group to delete
/// @return YES if the group was deleted successfully
- (BOOL)deleteModelGroup:(NSString *)groupName;

/// Rename a model group
/// @param oldName Current group name
/// @param newName New group name
/// @return YES if the group was renamed successfully
- (BOOL)renameModelGroup:(NSString *)oldName toName:(NSString *)newName;

/// Add a model to an existing group
/// @param modelName Model to add
/// @param groupName Group to add the model to
/// @return YES if the model was added successfully
- (BOOL)addModel:(NSString *)modelName toGroup:(NSString *)groupName;

/// Remove a model from a group
/// @param modelName Model to remove
/// @param groupName Group to remove the model from
/// @return YES if the model was removed successfully
- (BOOL)removeModel:(NSString *)modelName fromGroup:(NSString *)groupName;

#pragma mark - Submodels

/// Get submodels of a model
/// Returns array of dictionaries with: name, fullName, nodeCount, channelCount
- (NSArray<NSDictionary *> *)getSubmodels:(NSString *)modelName;

/// Check if a model has a specific submodel
- (BOOL)hasSubmodel:(NSString *)modelName submodelName:(NSString *)submodelName;

/// Get detailed submodel definition
/// Returns dictionary with: name, isRanges, vertical, bufferStyle, subBuffer, strands (array of strings)
- (NSDictionary *)getSubmodelDefinition:(NSString *)modelName submodelName:(NSString *)submodelName;

/// Create or update a submodel
/// @param modelName The parent model name
/// @param submodelName The submodel name
/// @param definition Dictionary with: isRanges (BOOL), vertical (BOOL), bufferStyle (string),
///                   subBuffer (string for buffer type), strands (array of strings for range type)
/// @return YES if successful
- (BOOL)setSubmodel:(NSString *)modelName
       submodelName:(NSString *)submodelName
         definition:(NSDictionary *)definition;

/// Delete a submodel
- (BOOL)deleteSubmodel:(NSString *)modelName submodelName:(NSString *)submodelName;

/// Rename a submodel
- (BOOL)renameSubmodel:(NSString *)modelName
               oldName:(NSString *)oldName
               newName:(NSString *)newName;

#pragma mark - Model Face Definitions

/// Get face definition names for a model
- (NSArray<NSString *> *)getFaceNames:(NSString *)modelName;

/// Get a face definition's data
/// Returns dictionary of key->value pairs (Type, phoneme-to-node mappings, colors, etc.)
- (NSDictionary *)getFaceDefinition:(NSString *)modelName faceName:(NSString *)faceName;

/// Get all face definitions for a model
/// Returns dictionary of faceName -> {key -> value}
- (NSDictionary<NSString *, NSDictionary *> *)getAllFaceDefinitions:(NSString *)modelName;

/// Set a face definition (create or update)
- (BOOL)setFaceDefinition:(NSString *)modelName
                  faceName:(NSString *)faceName
                definition:(NSDictionary *)definition;

/// Set all face definitions for a model (replaces all existing)
- (BOOL)setAllFaceDefinitions:(NSString *)modelName
                  definitions:(NSDictionary<NSString *, NSDictionary *> *)definitions;

/// Delete a face definition
- (BOOL)deleteFaceDefinition:(NSString *)modelName faceName:(NSString *)faceName;

/// Rename a face definition
- (BOOL)renameFaceDefinition:(NSString *)modelName
                     oldName:(NSString *)oldName
                     newName:(NSString *)newName;

#pragma mark - Model State Definitions

/// Get state definition names for a model
- (NSArray<NSString *> *)getStateNames:(NSString *)modelName;

/// Get a state definition's data
/// Returns dictionary of key->value pairs (Type, CustomColors, s001, s001-Name, s001-Color, etc.)
- (NSDictionary *)getStateDefinition:(NSString *)modelName stateName:(NSString *)stateName;

/// Get all state definitions for a model
/// Returns dictionary of stateName -> {key -> value}
- (NSDictionary<NSString *, NSDictionary *> *)getAllStateDefinitions:(NSString *)modelName;

/// Set a state definition (create or update)
- (BOOL)setStateDefinition:(NSString *)modelName
                  stateName:(NSString *)stateName
                 definition:(NSDictionary *)definition;

/// Set all state definitions for a model (replaces all existing)
- (BOOL)setAllStateDefinitions:(NSString *)modelName
                    definitions:(NSDictionary<NSString *, NSDictionary *> *)definitions;

/// Delete a state definition
- (BOOL)deleteStateDefinition:(NSString *)modelName stateName:(NSString *)stateName;

/// Rename a state definition
- (BOOL)renameStateDefinition:(NSString *)modelName
                      oldName:(NSString *)oldName
                      newName:(NSString *)newName;

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

/// Batch-fetch info, nodes, and bounds for all models in a single bridge call.
/// Returns an array of dictionaries, each containing:
///   - "name": model name (NSString)
///   - "info": model info dict (same as getModelInfo:)
///   - "nodes": array of node dicts (same as getModelNodes:)
///   - "bounds": bounding box dict (same as getModelBounds:)
/// Much faster than calling getModelInfo/getModelNodes/getModelBounds per model
/// (~55ms batch vs ~120ms per-model for 200 models).
- (NSArray<NSDictionary *> *)getAllModelData;

/// Batch-fetch for a subset of models. Pass nil for all models.
- (NSArray<NSDictionary *> *)getAllModelDataForNames:(NSArray<NSString *> *)modelNames;

/// Get 2D buffer-layout node data for a model group.
/// Returns per-member model data with flattened 2D coordinates suitable for
/// sidebar preview rendering (compact grid instead of scattered world positions).
/// Same dictionary format as getAllModelDataForNames: but with remapped coordinates.
- (NSArray<NSDictionary *> *)getGroupBufferData:(NSString *)groupName;

#pragma mark - Model Import Operations

/// Import a model from a .xmodel file
- (BOOL)importModelFromFile:(NSString *)filePath;

/// Import a specific model from a sequence/layout file
- (BOOL)importModelFromFile:(NSString *)filePath modelName:(NSString *)modelName;

/// Get list of models contained in a file (for sequence/layout files)
- (NSArray<NSDictionary *> *)getModelsInFile:(NSString *)filePath;

#pragma mark - LOR S5 Import

/// Get available preview names from an LOR S5 preview file.
/// @param filePath Path to the LOR S5 preview file (.lorprev, LORPreviews.xml)
/// @return Array of preview names, or nil on error
- (nullable NSArray<NSString *> *)getLORS5PreviewNames:(NSString *)filePath;

/// Import all models and groups from an LOR S5 preview file.
/// @param filePath Path to the LOR S5 preview file
/// @param previewName Name of the preview to import (nil for first/only preview)
/// @param layoutGroup Layout group to assign imported models to
/// @return Array of imported model names, or nil on error
- (nullable NSArray<NSString *> *)importModelsFromLORS5File:(NSString *)filePath
                                                previewName:(nullable NSString *)previewName
                                                layoutGroup:(NSString *)layoutGroup;

#pragma mark - RGB Effects File Import

/// Parse an xlights_rgbeffects.xml file and return its contents organized by layout group.
/// Returns a dictionary with:
///   @"layoutGroups": NSArray of NSString (layout group names found in file, always includes "Default" and "Unassigned")
///   @"models": NSArray of NSDictionary, each with: name, type, channels, layoutGroup, isModelGroup (BOOL),
///              and for model groups: models (comma-separated member names)
- (NSDictionary *)parseRGBEffectsFile:(NSString *)filePath;

/// Import selected models and model groups from an xlights_rgbeffects.xml file.
/// @param filePath Path to the xlights_rgbeffects.xml file
/// @param modelNames Array of model/group names to import
/// @param targetLayoutGroup The layout group to assign imported models to (nil = keep original)
/// @return Array of successfully imported model names
- (NSArray<NSString *> *)importModelsFromRGBEffectsFile:(NSString *)filePath
                                             modelNames:(NSArray<NSString *> *)modelNames
                                      targetLayoutGroup:(NSString * _Nullable)targetLayoutGroup;

#pragma mark - Output Operations

- (NSArray<NSString *> *)getControllerNames;
- (NSDictionary *)getControllerInfo:(NSString *)controllerName;
/// Unlink a controller from its base show folder (sets fromBase=false).
- (BOOL)unlinkControllerFromBase:(NSString *)controllerName;
- (BOOL)startOutput;
- (void)stopOutput;
- (BOOL)isOutputting;

/// Get all unique IP addresses used by outputs
- (NSArray<NSString *> *)getOutputIPs;

/// Get all universes configured across all outputs
- (NSArray<NSNumber *> *)getAllUniverses;

/// Get universes for a specific IP address
- (NSArray<NSNumber *> *)getUniversesForIP:(NSString *)ip;

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


/// Export controller configuration to an XML file.
/// The exported file uses the same format as xlights_networks.xml for compatibility.
/// @param filePath Destination file path for the exported XML
/// @return YES if export was successful
- (BOOL)exportControllerConfig:(NSString *)filePath;

/// Import controller configuration from an XML file.
/// Replaces all current controllers with those from the imported file.
/// The file should be in xlights_networks.xml format.
/// @param filePath Path to the XML file to import
/// @return YES if import was successful
- (BOOL)importControllerConfig:(NSString *)filePath;

/// Recalculate start channels for all models based on controller/port assignments.
/// Automatically called when controllers, ports, or model assignments change.
/// Posts XLChannelsDidRecalculateNotification when complete.
- (void)recalculateStartChannels;

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

#pragma mark - Sequence Views

/// Get list of all view names (Master View is always first)
- (NSArray<NSString *> *)getViewNames;

/// Get the currently selected view name
- (NSString *)getCurrentViewName;

/// Get the currently selected view index (0 = Master View)
- (NSInteger)getCurrentViewIndex;

/// Set the current view by name. Returns YES on success.
- (BOOL)setCurrentView:(NSString *)viewName;

/// Set the current view by index. Returns YES on success.
- (BOOL)setCurrentViewIndex:(NSInteger)viewIndex;

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

/// Insert a new effect layer at a specific index
- (NSInteger)insertLayer:(NSString *)modelName atIndex:(NSInteger)index;

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

/// Set whether an effect is locked (prevents editing)
- (BOOL)setEffectLocked:(NSInteger)effectId locked:(BOOL)locked;

/// Set whether an effect's rendering is disabled
- (BOOL)setEffectRenderDisabled:(NSInteger)effectId disabled:(BOOL)disabled;

/// Reset an effect to its default settings
- (BOOL)resetEffectToDefaults:(NSInteger)effectId;

#pragma mark - Timing Track Operations

/// Get list of timing tracks in the sequence
/// Returns array of dictionaries with: name, layerCount, isActive, isFixed, fixedInterval
- (NSArray<NSDictionary *> *)getTimingTracks;

/// Get the currently active timing track name (nil if none active)
- (NSString *)getActiveTimingTrackName;

/// Set the active timing track by name
- (BOOL)setActiveTimingTrack:(NSString *)trackName;

/// Deactivate all timing tracks
- (void)deactivateAllTimingTracks;

/// Get timing marks for a track and layer
/// Returns array of dictionaries with: id, startTimeMS, endTimeMS, label
- (NSArray<NSDictionary *> *)getTimingMarks:(NSString *)trackName layer:(NSInteger)layer;

/// Get all timing mark times from the active timing track (for snap-to-grid)
/// Returns array of NSNumber containing millisecond values
- (NSArray<NSNumber *> *)getActiveTimingMarkTimes;

/// Create a new timing mark on the specified track and layer
/// @param trackName The timing track name
/// @param layer The layer index (0-based)
/// @param startTimeMS Start time in milliseconds
/// @param endTimeMS End time in milliseconds
/// @param label Optional label for the timing mark (nil for no label)
/// @return Effect ID of the new timing mark, or -1 on failure
- (NSInteger)createTimingMark:(NSString *)trackName
                        layer:(NSInteger)layer
                  startTimeMS:(NSInteger)startTimeMS
                    endTimeMS:(NSInteger)endTimeMS
                        label:(NSString * _Nullable)label;

/// Move a timing mark to a new time range
- (BOOL)moveTimingMark:(NSInteger)markId startTimeMS:(NSInteger)startMS endTimeMS:(NSInteger)endMS;

/// Update a timing mark's label
- (BOOL)setTimingMarkLabel:(NSInteger)markId label:(NSString *)label;

/// Delete a timing mark
- (BOOL)deleteTimingMark:(NSInteger)markId;

/// Get timing mark info by ID
/// Returns dictionary with: id, trackName, layer, startTimeMS, endTimeMS, label
- (NSDictionary *)getTimingMark:(NSInteger)markId;

/// Create a new timing track with the given name
/// @return YES if successful
- (BOOL)createTimingTrack:(NSString *)name;

/// Create a new timing track with the given name and type
/// @param name The name for the new timing track
/// @param timingType The type of timing (e.g., "Empty", "Fixed Interval", "Metronome")
/// @return YES if successful
- (BOOL)createTimingTrack:(NSString *)name timingType:(NSString *)timingType;

/// Import a timing track from another sequence file
/// @param trackName Name of track in source file to import
/// @param sequenceFile Path to source sequence file
/// @param newTrackName Name for the imported track in current sequence
/// @return YES if successful
- (BOOL)importTimingTrack:(NSString *)trackName fromSequence:(NSString *)sequenceFile asTrackName:(NSString *)newTrackName;

/// Delete a timing track by name
- (BOOL)deleteTimingTrack:(NSString *)name;

/// Rename a timing track
- (BOOL)renameTimingTrack:(NSString *)oldName toName:(NSString *)newName;

/// Get phonemes for a word using the phoneme dictionary
/// Returns array of phoneme strings (e.g. @[@"AI", @"etc", @"rest"]) or empty array if unknown
- (NSArray<NSString *> *)getPhonemesForWord:(NSString *)word;

#pragma mark - Track Folders

/// Get all track folders.
/// Returns array of dictionaries with: name, collapsed (BOOL)
- (NSArray<NSDictionary *> *)getTrackFolders;

/// Create a new track folder.
/// @return YES if created successfully
- (BOOL)createTrackFolder:(NSString *)name;

/// Delete a track folder. Elements become ungrouped.
/// @return YES if deleted successfully
- (BOOL)deleteTrackFolder:(NSString *)name;

/// Rename a track folder.
/// @return YES if renamed successfully
- (BOOL)renameTrackFolder:(NSString *)oldName toName:(NSString *)newName;

/// Assign an element to a folder (nil or empty = remove from folder).
/// @return YES if successful
- (BOOL)setElement:(NSString *)elementName folder:(NSString * _Nullable)folderName;

/// Get the folder name for an element (nil if not in a folder).
- (NSString * _Nullable)getElementFolder:(NSString *)elementName;

/// Set a track folder's collapsed state.
/// @return YES if successful
- (BOOL)setTrackFolderCollapsed:(NSString *)name collapsed:(BOOL)collapsed;

#pragma mark - Song Structure Regions

/// Get all song structure regions.
/// Returns array of dictionaries with: regionId, startTimeMS, endTimeMS, name, colorARGB
- (NSArray<NSDictionary *> *)getSongStructureRegions;

/// Add a boundary at the given time (splits the region containing it).
/// If no regions exist, creates two regions spanning the full sequence.
- (void)addSongStructureBoundaryAtTimeMS:(NSInteger)timeMS;

/// Move an internal boundary to a new position.
/// @param idx 0-based index of boundary between regions (boundary 0 is between region 0 and 1)
/// @param newTimeMS New boundary position in milliseconds
- (void)moveSongStructureBoundary:(NSInteger)idx toTimeMS:(NSInteger)newTimeMS;

/// Delete an internal boundary, merging two adjacent regions (keeps left name/color).
- (void)deleteSongStructureBoundary:(NSInteger)idx;

/// Update a region's name and color.
- (void)setSongStructureRegion:(NSInteger)regionId name:(NSString *)name colorARGB:(uint32_t)colorARGB;

/// Remove all song structure regions.
- (void)clearSongStructure;

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

/// Set playback speed as a multiplier (e.g. 0.25 = 1/4x, 1.0 = normal, 4.0 = 4x)
- (void)setPlaybackSpeed:(double)speed;

/// Get current playback speed multiplier
- (double)getPlaybackSpeed;

#pragma mark - Pixel Test Operations

/// Set a single channel to a specific value (0-255).
/// @param channel Absolute channel number (1-indexed)
/// @param value Brightness value (0-255)
- (void)setTestChannel:(NSInteger)channel value:(NSUInteger)value;

/// Set multiple channels to specific values.
/// @param startChannel Starting absolute channel number (1-indexed)
/// @param data NSData containing byte values for each channel
- (void)setTestChannels:(NSInteger)startChannel data:(NSData *)data;

/// Turn off all channels (all outputs set to 0)
- (void)allTestChannelsOff;

/// Start a frame for test output
- (void)startTestFrame;

/// End a frame and send test output data to controllers
- (void)endTestFrame;

/// Get the total number of channels configured
- (NSInteger)getTotalTestChannels;

/// Get channels for a specific model.
/// Returns dictionary with: startChannel (1-indexed), channelCount, nodeCount
- (NSDictionary *)getModelChannelInfo:(NSString *)modelName;

/// Get all channel ranges for a model (including submodels).
/// Returns array of dictionaries with: startChannel, endChannel, nodeIndex
- (NSArray<NSDictionary *> *)getModelChannelRanges:(NSString *)modelName;

#pragma mark - Layout Group Operations

/// Get all layout group (preview) names.
/// Always includes "Default", "All Models", "Unassigned" plus any custom groups.
- (NSArray<NSString *> *)getLayoutGroupNames;

/// Get the currently active layout group name.
- (NSString *)getCurrentLayoutGroup;

/// Set the current layout group. Updates the model filter for preview and tree.
- (BOOL)setCurrentLayoutGroup:(NSString *)groupName;

/// Create a new layout group (preview).
/// Name must not be "Default", "All Models", or "Unassigned".
- (BOOL)createLayoutGroup:(NSString *)name;

/// Delete a layout group. Cannot delete "Default".
/// Models assigned to this group will be reassigned to "Unassigned".
- (BOOL)deleteLayoutGroup:(NSString *)name;

/// Rename a layout group. Cannot rename "Default".
- (BOOL)renameLayoutGroup:(NSString *)oldName toName:(NSString *)newName;

/// Get layout group settings (background image, brightness, alpha).
/// Returns dictionary with: name, backgroundImage, backgroundBrightness, backgroundAlpha, scaleBackgroundImage
- (NSDictionary *)getLayoutGroupSettings:(NSString *)groupName;

/// Update layout group settings.
/// Supported keys: backgroundImage, backgroundBrightness, backgroundAlpha, scaleBackgroundImage
- (BOOL)updateLayoutGroupSettings:(NSString *)groupName settings:(NSDictionary *)settings;

/// Get model names visible in a specific layout group.
- (NSArray<NSString *> *)getModelsForLayoutGroup:(NSString *)groupName;

#pragma mark - Polyline Point Editing

/// Check if a model is a polyline or multi-point type
- (BOOL)isPolylineModel:(NSString *)modelName;

/// Get polyline points as array of dictionaries.
/// Each dict has: x, y, z (world-space), hasCurve (BOOL), cp0x/cp0y/cp0z, cp1x/cp1y/cp1z
- (NSArray<NSDictionary *> *)getPolylinePoints:(NSString *)modelName;

/// Get the number of points in a polyline model
- (NSInteger)getPolylinePointCount:(NSString *)modelName;

/// Move a polyline point to a new world-space position
- (BOOL)movePolylinePoint:(NSString *)modelName index:(NSInteger)pointIndex
                        x:(float)worldX y:(float)worldY z:(float)worldZ;

/// Move a curve control point to a new world-space position
- (BOOL)movePolylineCurvePoint:(NSString *)modelName segmentIndex:(NSInteger)segmentIndex
                  controlPoint:(NSInteger)cpIndex
                             x:(float)worldX y:(float)worldY z:(float)worldZ;

/// Insert a new point after the given segment (midpoint between segment endpoints)
- (BOOL)insertPolylinePoint:(NSString *)modelName afterSegment:(NSInteger)afterSegment;

/// Delete a polyline point at the given index
- (BOOL)deletePolylinePoint:(NSString *)modelName index:(NSInteger)pointIndex;

/// Add or remove a Bezier curve on a segment
- (BOOL)setPolylineCurve:(NSString *)modelName segment:(NSInteger)segmentIndex create:(BOOL)create;

/// Check if a polyline model supports curves (Poly Line yes, MultiPoint no)
- (BOOL)polylineModelSupportsCurves:(NSString *)modelName;

#pragma mark - View Objects (3D Objects)

/// Get all view objects in the current layout.
/// Returns array of dictionaries with: name, type, active, posX, posY, posZ, etc.
- (NSArray<NSDictionary *> *)getViewObjects;

/// Get a specific view object by name.
/// Returns dictionary with view object properties, or nil if not found.
- (NSDictionary *)getViewObject:(NSString *)objectName;

/// Add a new view object.
/// @param objectType Type string: "Image", "Gridlines", "Mesh", "Terrain", "Ruler"
/// @param name Name for the new object
/// @param properties Optional initial properties
/// @return YES if the object was created successfully
- (BOOL)addViewObject:(NSString *)objectType name:(NSString *)name properties:(NSDictionary * _Nullable)properties;

/// Remove a view object by name.
/// @return YES if the object was removed
- (BOOL)removeViewObject:(NSString *)objectName;

/// Update a view object property.
/// @param objectName Name of the view object
/// @param key Property key to update
/// @param value New value
/// @return YES if the property was updated
- (BOOL)updateViewObjectProperty:(NSString *)objectName key:(NSString *)key value:(id)value;

/// Rename a view object.
/// @return YES if the rename was successful
- (BOOL)renameViewObject:(NSString *)oldName toName:(NSString *)newName;

#pragma mark - Utility

/// Convert std::string to NSString (utility method, publicly exposed for testing)
+ (NSString *)stringFromStdString:(const char *)stdString;

/// Convert NSString to std::string (utility method, publicly exposed for testing)
+ (void)stdStringFromString:(NSString *)nsString buffer:(char **)outBuffer;

@end
