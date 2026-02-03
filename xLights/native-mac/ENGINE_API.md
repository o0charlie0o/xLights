# xLights Engine API Documentation

This document describes the `XLEngineBridge` API that connects the native macOS UI to the C++ xLights engine.

## Architecture Overview

```
+-------------------+     +------------------+     +------------------+
|   Native AppKit   | --> | XLEngineBridge   | --> |  C++ Engine      |
|   UI (Obj-C)      |     | (Obj-C++)        |     |  (xLightsFrame)  |
+-------------------+     +------------------+     +------------------+
```

The `XLEngineBridge` class is an Objective-C++ wrapper that:
1. Converts between Cocoa types (NSString, NSArray, NSDictionary) and C++ types (std::string, std::vector)
2. Provides thread-safe access to the C++ engine
3. Handles error propagation via NSError patterns

## Getting the Engine Bridge

Each `XLDocument` owns an `XLEngineBridge` instance:

```objc
@interface XLDocument : NSDocument
@property (nonatomic, strong, readonly) XLEngineBridge *engineBridge;
@end
```

View controllers access it through their document reference:

```objc
XLEngineBridge *engine = self.document.engineBridge;
```

## API Reference

### Lifecycle

```objc
- (instancetype)init;
- (BOOL)isEngineAvailable;
```

The bridge initializes automatically. Check `isEngineAvailable` before making calls.

---

### Sequence Operations

```objc
// File operations
- (BOOL)loadSequence:(NSString *)path;
- (BOOL)saveSequence:(NSString *)path;
- (BOOL)closeSequence;
- (BOOL)isSequenceLoaded;

// Sequence info - returns dictionary with:
// name, mediaFile, sequenceType, durationMS, frameTimeMS,
// numChannels, numFrames, author, song, artist, album, comment
- (NSDictionary *)getSequenceInfo;
```

**Example: Loading a Sequence**

```objc
if ([self.engineBridge loadSequence:@"/path/to/sequence.xlights"]) {
    NSDictionary *info = [self.engineBridge getSequenceInfo];
    NSLog(@"Loaded: %@, Duration: %@ms", info[@"name"], info[@"durationMS"]);
}
```

---

### Playback Control

```objc
// Transport
- (void)play;
- (void)pause;
- (void)stop;
- (void)seek:(NSInteger)positionMS;
- (void)seekToStart;
- (void)seekToEnd;
- (void)seekRelative:(NSInteger)deltaMS;

// State queries
- (NSString *)getPlaybackState;  // @"stopped", @"playing", @"paused"
- (NSInteger)getPosition;        // Current position in milliseconds
- (NSInteger)getDuration;        // Total duration in milliseconds
- (NSInteger)getFrameRate;       // Frames per second
- (NSInteger)getFrameTimeMS;     // Milliseconds per frame
```

**Example: Playback Control**

```objc
[self.engineBridge play];

// Check state
NSString *state = [self.engineBridge getPlaybackState];
if ([state isEqualToString:@"playing"]) {
    NSInteger position = [self.engineBridge getPosition];
    NSLog(@"Playing at %ldms", (long)position);
}

// Seek to 50% through sequence
NSInteger duration = [self.engineBridge getDuration];
[self.engineBridge seek:duration / 2];
```

---

### Rendering

```objc
// Batch rendering
- (void)renderAll;
- (void)renderRange:(NSInteger)startMS endMS:(NSInteger)endMS;
- (void)abortRender;
- (BOOL)isRendering;

// Frame rendering
- (void)renderFrame:(NSInteger)timeMS;
- (void)renderModelFrame:(NSString *)modelName timeMS:(NSInteger)timeMS;

// Pixel data access
// Returns: modelName, width, height, timeMS, pixels (NSData RGBA)
- (NSDictionary *)getFrameBuffer:(NSString *)modelName;

// Node data for hardware output
// Returns array of: startChannel, channelCount, data (NSData)
- (NSArray<NSDictionary *> *)getNodeData:(NSString *)modelName;
```

**Example: Rendering a Frame**

```objc
[self.engineBridge renderFrame:1000]; // Render at 1 second

NSDictionary *buffer = [self.engineBridge getFrameBuffer:@"MyModel"];
NSData *pixels = buffer[@"pixels"];
NSUInteger width = [buffer[@"width"] unsignedIntegerValue];
NSUInteger height = [buffer[@"height"] unsignedIntegerValue];

// pixels contains RGBA data: width * height * 4 bytes
```

---

### Model Operations

```objc
// Model queries
- (NSArray<NSString *> *)getModelNames;                // All models including groups
- (NSArray<NSString *> *)getModelNamesExcludingGroups; // Models only
- (NSArray<NSString *> *)getGroupNames;                // Groups only
- (BOOL)hasModel:(NSString *)modelName;

// Model info - returns dictionary with model properties
- (NSDictionary *)getModelInfo:(NSString *)modelName;

// Property access
- (NSString *)getModelProperty:(NSString *)modelName
                           key:(NSString *)key
                  defaultValue:(NSString *)defaultValue;
- (NSDictionary *)getModelProperties:(NSString *)modelName;
- (BOOL)updateModelProperty:(NSString *)modelName
                        key:(NSString *)key
                      value:(id)value;

// CRUD operations
- (BOOL)createModel:(NSString *)modelType
               name:(NSString *)modelName
         properties:(NSDictionary *)properties;
- (BOOL)deleteModel:(NSString *)modelName;
- (BOOL)renameModel:(NSString *)oldName toName:(NSString *)newName;
- (BOOL)duplicateModel:(NSString *)modelName;
```

**Example: Working with Models**

```objc
// List all models
NSArray *models = [self.engineBridge getModelNames];
for (NSString *name in models) {
    NSDictionary *info = [self.engineBridge getModelInfo:name];
    NSLog(@"Model: %@, Type: %@", name, info[@"modelType"]);
}

// Update a property
[self.engineBridge updateModelProperty:@"MyMatrix"
                                   key:@"parm1"
                                 value:@"10"];

// Create a new model
[self.engineBridge createModel:@"SingleLine"
                          name:@"NewStrip"
                    properties:@{@"parm1": @"50"}];
```

---

### Model Groups

```objc
// Group queries
// Returns array of: name, modelNames (array)
- (NSArray<NSDictionary *> *)getModelGroups;

// Returns: name, modelNames (array), defaultBufferStyle
- (NSDictionary *)getModelGroup:(NSString *)groupName;

// Get groups containing a model
- (NSArray<NSString *> *)getGroupsContainingModel:(NSString *)modelName;
```

---

### Submodels

```objc
// Returns array of: name, fullName, nodeCount, channelCount
- (NSArray<NSDictionary *> *)getSubmodels:(NSString *)modelName;
- (BOOL)hasSubmodel:(NSString *)modelName submodelName:(NSString *)submodelName;
```

---

### Model Geometry

```objc
// Node coordinates for visualization
// Returns array of: x, y, z, bufX, bufY, channel, channelCount, stringNum
- (NSArray<NSDictionary *> *)getModelNodes:(NSString *)modelName;

// Counts
- (NSUInteger)getModelNodeCount:(NSString *)modelName;
- (NSUInteger)getModelChannelCount:(NSString *)modelName;

// Bounds - returns: minX, maxX, minY, maxY, minZ, maxZ
- (NSDictionary *)getModelBounds:(NSString *)modelName;
```

**Example: Rendering Model Nodes**

```objc
NSArray *nodes = [self.engineBridge getModelNodes:@"MyModel"];
for (NSDictionary *node in nodes) {
    CGFloat x = [node[@"x"] floatValue];
    CGFloat y = [node[@"y"] floatValue];
    CGFloat z = [node[@"z"] floatValue];
    // Use for 3D visualization
}
```

---

### Model Import

```objc
- (BOOL)importModelFromFile:(NSString *)filePath;
- (BOOL)importModelFromFile:(NSString *)filePath modelName:(NSString *)modelName;
- (NSArray<NSDictionary *> *)getModelsInFile:(NSString *)filePath;
```

---

### Output/Controller Operations

```objc
// Controller list
- (NSArray<NSString *> *)getControllerNames;
- (NSDictionary *)getControllerInfo:(NSString *)controllerName;
- (NSDictionary *)getControllerCapabilities:(NSString *)controllerName;

// Output control
- (BOOL)startOutput;
- (void)stopOutput;
- (BOOL)isOutputting;

// Configuration
- (NSInteger)getTotalChannels;
- (BOOL)isOutputDirty;
- (BOOL)saveOutputConfiguration;
```

---

### Port Configuration

```objc
// Get port configurations for a controller
// Returns array of: port, type, protocol, startChannel, channelCount,
//                   brightness, gamma, colorOrder, smartRemote
- (NSArray<NSDictionary *> *)getPortsForController:(NSString *)controllerName;

// Update port configuration
- (BOOL)updatePort:(NSString *)controllerName
              port:(NSInteger)portNumber
        properties:(NSDictionary *)properties;

// Model-to-port assignment
- (BOOL)assignModel:(NSString *)modelName
       toController:(NSString *)controllerName
               port:(NSInteger)portNumber;

- (BOOL)removeModelFromController:(NSString *)controllerName
                             port:(NSInteger)portNumber;
```

---

### Controller Discovery

```objc
// Async discovery - completion called on main queue
- (void)discoverControllers:(void (^)(BOOL success, NSArray<NSDictionary *> *controllers))completion;

// Add discovered controller
- (BOOL)addDiscoveredController:(NSDictionary *)discoveredInfo;

// Connectivity tests
- (void)testController:(NSString *)controllerName
            completion:(void (^)(NSString *pingState))completion;

- (void)testAllControllers:(void (^)(NSString *controllerName, NSString *pingState))completion;
```

**Example: Controller Discovery**

```objc
[self.engineBridge discoverControllers:^(BOOL success, NSArray<NSDictionary *> *controllers) {
    if (success) {
        for (NSDictionary *controller in controllers) {
            NSLog(@"Found: %@ at %@", controller[@"hostname"], controller[@"ip"]);

            // Add if not already configured
            if (![controller[@"alreadyConfigured"] boolValue]) {
                [self.engineBridge addDiscoveredController:controller];
            }
        }
    }
}];
```

---

### Controller Upload

```objc
// Upload configuration to controller
- (void)uploadToController:(NSString *)controllerName
                completion:(void (^)(BOOL success, NSString *message))completion;

// Upload input/output configuration separately
- (void)uploadInputToController:(NSString *)controllerName
                     completion:(void (^)(BOOL success, NSString *message))completion;

- (void)uploadOutputToController:(NSString *)controllerName
                      completion:(void (^)(BOOL success, NSString *message))completion;
```

---

### Sequence Elements

```objc
// Element queries
- (NSInteger)getSequenceElementCount;

// Returns: name, type (timing/model/submodel/strand), effectLayerCount, visible, collapsed
- (NSDictionary *)getSequenceElementAtIndex:(NSInteger)index;
- (NSArray<NSDictionary *> *)getSequenceElements;

// Effects on element
- (NSArray<NSDictionary *> *)getEffectsForElementAtIndex:(NSInteger)index
                                                   layer:(NSInteger)layer;
```

---

### Effect Operations

```objc
// Effect types
- (NSArray<NSString *> *)getEffectTypes;
- (NSDictionary *)getEffectTypeInfo:(NSString *)effectType;
- (NSArray<NSDictionary *> *)getEffectParameters:(NSString *)effectType;

// Effect CRUD
- (NSInteger)createEffect:(NSString *)modelName
                    layer:(NSInteger)layer
               effectType:(NSString *)effectType
              startTimeMS:(NSInteger)startMS
                endTimeMS:(NSInteger)endMS;  // Returns effect ID or -1

- (BOOL)deleteEffect:(NSInteger)effectId;

// Effect info - returns: id, effectType, modelName, layerIndex,
//                        startTimeMS, endTimeMS, settings, palette
- (NSDictionary *)getEffect:(NSInteger)effectId;

// Effect parameters
- (BOOL)setEffectParameter:(NSInteger)effectId key:(NSString *)key value:(NSString *)value;
- (NSString *)getEffectParameter:(NSInteger)effectId key:(NSString *)key;
- (BOOL)setEffectSettings:(NSInteger)effectId settings:(NSString *)settings;
- (NSString *)getEffectSettings:(NSInteger)effectId;

// Effect palette (colors)
- (BOOL)setEffectPalette:(NSInteger)effectId palette:(NSString *)palette;
- (NSString *)getEffectPalette:(NSInteger)effectId;

// Effect manipulation
- (BOOL)moveEffect:(NSInteger)effectId startTimeMS:(NSInteger)startMS endTimeMS:(NSInteger)endMS;
- (BOOL)convertEffectType:(NSInteger)effectId newType:(NSString *)newType;

// Effect queries
- (NSArray<NSDictionary *> *)getEffectsForModel:(NSString *)modelName;
- (NSArray<NSDictionary *> *)getEffectsAtTime:(NSString *)modelName timeMS:(NSInteger)timeMS;
- (NSArray<NSDictionary *> *)getEffectsForLayer:(NSString *)modelName layer:(NSInteger)layer;

// Layer management
- (NSInteger)getLayerCount:(NSString *)modelName;
- (NSInteger)addLayer:(NSString *)modelName;
- (BOOL)removeLayer:(NSString *)modelName layer:(NSInteger)layer;

// Selection
- (BOOL)selectEffect:(NSInteger)effectId;
- (void)deselectAllEffects;
- (NSArray<NSNumber *> *)getSelectedEffectIds;
```

**Example: Creating an Effect**

```objc
NSInteger effectId = [self.engineBridge createEffect:@"MyModel"
                                               layer:0
                                          effectType:@"Bars"
                                         startTimeMS:0
                                           endTimeMS:5000];
if (effectId >= 0) {
    [self.engineBridge setEffectParameter:effectId key:@"E_SLIDER_Bars_BarCount" value:@"10"];
    [self.engineBridge setEffectPalette:effectId palette:@"C_BUTTON_Palette1=#FF0000"];
}
```

---

### Audio Operations

```objc
// Media file access
- (NSString *)getMediaFilePath;
- (BOOL)isAudioLoaded;

// Audio info - returns: filePath, durationMS, sampleRate, channels, title, artist, album
- (NSDictionary *)getAudioInfo;

// Audio samples for waveform rendering
// Returns: leftChannel (NSData), rightChannel (NSData), sampleCount, sampleRate
- (NSDictionary *)getAudioSamples:(NSInteger)startMS endMS:(NSInteger)endMS;

// Amplitude range for quick overview
// Returns: minLeft, maxLeft, minRight, maxRight
- (NSDictionary *)getAudioAmplitudeRange:(NSInteger)startMS endMS:(NSInteger)endMS;

// Volume control
- (void)setAudioVolume:(NSInteger)volume;  // 0-100
- (NSInteger)getAudioVolume;
```

**Example: Rendering Audio Waveform**

```objc
NSDictionary *samples = [self.engineBridge getAudioSamples:0 endMS:10000];
NSData *leftChannel = samples[@"leftChannel"];
NSData *rightChannel = samples[@"rightChannel"];
NSUInteger sampleCount = [samples[@"sampleCount"] unsignedIntegerValue];

const float *leftData = (const float *)leftChannel.bytes;
for (NSUInteger i = 0; i < sampleCount; i++) {
    float amplitude = leftData[i];
    // Draw waveform
}
```

---

## Thread Safety

All `XLEngineBridge` methods are safe to call from the main thread. The bridge handles any necessary thread marshaling internally.

For background operations (discovery, upload), completion blocks are delivered on the main queue.

## Error Handling

Methods that can fail return `BOOL` (YES for success) or `nil`/negative values for failure. Check return values before proceeding.

```objc
if (![self.engineBridge loadSequence:path]) {
    NSLog(@"Failed to load sequence");
    return;
}
```

For async operations, check the success parameter in completion blocks:

```objc
[self.engineBridge discoverControllers:^(BOOL success, NSArray *controllers) {
    if (!success) {
        NSLog(@"Discovery failed");
        return;
    }
    // Process controllers
}];
```

## Performance Tips

1. **Cache model lists**: Don't call `getModelNames` every frame
2. **Batch property updates**: Collect changes and apply together
3. **Use frame rendering sparingly**: Only render visible frames
4. **Prefer amplitude range over samples**: For waveform overviews

## Related Files

- `XLEngineBridge.h` - Full API declarations
- `XLEngineBridge.mm` - Implementation
- `XLDocumentBridge.h/mm` - C++ to AppKit callbacks
- `IMPLEMENTATION_GUIDE.md` - Architecture overview
