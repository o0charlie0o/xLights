/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLEngineBridge.h"

// Include C++ engine headers
// During transition period, these will delegate to the existing xLightsFrame
#include "../engine/SequenceEngine.h"
#include "../engine/ModelEngine.h"
#include "../engine/OutputEngine.h"
#include "../engine/RenderEngine.h"
#include "../engine/EffectEngine.h"

#include <string>
#include <vector>
#include <map>

@implementation XLEngineBridge {
    // During the transition period, the engines are singletons accessed via
    // xLightsFrame. Once Phase 0 is complete, we'll hold pointers here.
    // For now, this is a placeholder that shows the pattern.

    // std::unique_ptr<xlEngine::SequenceEngine> _sequenceEngine;
    // std::unique_ptr<xlEngine::ModelEngine> _modelEngine;
    // std::unique_ptr<xlEngine::OutputEngine> _outputEngine;
    // std::unique_ptr<xlEngine::RenderEngine> _renderEngine;
    // std::unique_ptr<xlEngine::EffectEngine> _effectEngine;
}

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        // TODO: Initialize engine instances once Phase 0 is complete
        // For now, this is a stub that demonstrates the pattern

        NSLog(@"XLEngineBridge initialized (stub implementation)");
    }
    return self;
}

#pragma mark - Sequence Operations

- (BOOL)loadSequence:(NSString *)path {
    if (!path || path.length == 0) return NO;

    std::string stdPath = [path UTF8String];

    // TODO: Call into SequenceEngine once Phase 0 is complete
    // return _sequenceEngine->loadSequence(stdPath);

    NSLog(@"[Stub] loadSequence: %@", path);
    return YES; // stub
}

- (BOOL)saveSequence:(NSString *)path {
    std::string stdPath = path ? [path UTF8String] : "";

    // TODO: Call into SequenceEngine
    // return _sequenceEngine->saveSequence(stdPath);

    NSLog(@"[Stub] saveSequence: %@", path ?: @"<current>");
    return YES; // stub
}

- (BOOL)closeSequence {
    // TODO: Call into SequenceEngine
    // return _sequenceEngine->closeSequence();

    NSLog(@"[Stub] closeSequence");
    return YES; // stub
}

- (BOOL)isSequenceLoaded {
    // TODO: Call into SequenceEngine
    // return _sequenceEngine->isSequenceLoaded();

    return NO; // stub
}

#pragma mark - Playback Control

- (void)play {
    // TODO: Call into SequenceEngine
    // _sequenceEngine->play();

    NSLog(@"[Stub] play");
}

- (void)pause {
    // TODO: Call into SequenceEngine
    // _sequenceEngine->pause();

    NSLog(@"[Stub] pause");
}

- (void)stop {
    // TODO: Call into SequenceEngine
    // _sequenceEngine->stop();

    NSLog(@"[Stub] stop");
}

- (void)seek:(NSInteger)positionMS {
    // TODO: Call into SequenceEngine
    // _sequenceEngine->seek((int)positionMS);

    NSLog(@"[Stub] seek: %ld ms", (long)positionMS);
}

#pragma mark - Rendering

- (void)renderAll {
    // TODO: Call into RenderEngine
    // _renderEngine->renderAll(nullptr);

    NSLog(@"[Stub] renderAll");
}

- (void)renderRange:(NSInteger)startMS endMS:(NSInteger)endMS {
    // TODO: Call into RenderEngine
    // _renderEngine->renderRange((int)startMS, (int)endMS, false, nullptr);

    NSLog(@"[Stub] renderRange: %ld - %ld ms", (long)startMS, (long)endMS);
}

- (void)abortRender {
    // TODO: Call into RenderEngine
    // _renderEngine->abortRender();

    NSLog(@"[Stub] abortRender");
}

#pragma mark - Model Operations

- (NSArray<NSString *> *)getModelNames {
    // TODO: Call into ModelEngine
    // std::vector<std::string> names = _modelEngine->getModelNames();
    // return [self arrayFromVector:names];

    // Stub: return sample data
    return @[@"Mega Tree 1", @"Arch Left", @"Arch Right", @"Matrix"];
}

- (NSDictionary *)getModelInfo:(NSString *)modelName {
    if (!modelName) return nil;

    std::string stdName = [modelName UTF8String];

    // TODO: Call into ModelEngine
    // xlEngine::ModelInfo info = _modelEngine->getModel(stdName);
    // return [self dictFromModelInfo:info];

    // Stub: return sample data with all property keys used by XLModelPropertiesView
    return @{
        @"name": modelName,
        @"type": @"Single Line",
        @"description": @"",
        @"displayAs": @"Default",
        @"x": @(0.0), @"y": @(0.0), @"z": @(0.0),
        @"width": @(100.0), @"height": @(100.0), @"depth": @(0.0),
        @"rotationX": @(0.0), @"rotationY": @(0.0), @"rotationZ": @(0.0),
        @"scale": @(1.0), @"locked": @(NO),
        @"controllerName": @"No Controller",
        @"port": @(1), @"protocol": @"ws2811",
        @"startChannel": @(1), @"endChannel": @(100), @"channelCount": @(100),
        @"colorOrder": @"RGB", @"brightness": @(100),
        @"gamma": @(1.0), @"nullPixels": @(0),
        @"reverse": @(NO), @"groupCount": @(1), @"zigZag": @(0),
        @"nodeCount": @100,
    };
}

- (BOOL)hasModel:(NSString *)modelName {
    if (!modelName) return NO;

    std::string stdName = [modelName UTF8String];

    // TODO: Call into ModelEngine
    // return _modelEngine->hasModel(stdName);

    return YES; // stub
}

- (BOOL)updateModelProperty:(NSString *)modelName key:(NSString *)key value:(id)value {
    if (!modelName || !key) return NO;

    // TODO: Call into ModelEngine to apply the property change
    // std::string stdName = [modelName UTF8String];
    // std::string stdKey = [key UTF8String];
    // return _modelEngine->setProperty(stdName, stdKey, value);

    NSLog(@"[Stub] updateModelProperty %@ key=%@ value=%@", modelName, key, value);
    return YES; // stub
}

- (BOOL)createModel:(NSString *)modelType name:(NSString *)modelName properties:(NSDictionary *)properties {
    if (!modelType || !modelName) return NO;

    std::string stdType = [modelType UTF8String];
    std::string stdName = [modelName UTF8String];

    // Convert properties to std::map
    std::map<std::string, std::string> stdProps;
    for (NSString *key in properties) {
        id value = properties[key];
        NSString *stringValue;
        if ([value isKindOfClass:[NSString class]]) {
            stringValue = value;
        } else if ([value isKindOfClass:[NSNumber class]]) {
            stringValue = [value stringValue];
        } else {
            stringValue = [value description];
        }
        stdProps[[key UTF8String]] = [stringValue UTF8String];
    }

    // TODO: Call into ModelEngine
    // xlEngine::OperationResult result = _modelEngine->createModel(stdType, stdName, stdProps);
    // return result.success;

    NSLog(@"[Stub] createModel type=%@ name=%@ properties=%@", modelType, modelName, properties);
    return YES; // stub
}

- (BOOL)deleteModel:(NSString *)modelName {
    if (!modelName) return NO;

    std::string stdName = [modelName UTF8String];

    // TODO: Call into ModelEngine
    // xlEngine::OperationResult result = _modelEngine->deleteModel(stdName);
    // return result.success;

    NSLog(@"[Stub] deleteModel: %@", modelName);
    return YES; // stub
}

- (BOOL)renameModel:(NSString *)oldName toName:(NSString *)newName {
    if (!oldName || !newName) return NO;

    std::string stdOldName = [oldName UTF8String];
    std::string stdNewName = [newName UTF8String];

    // TODO: Call into ModelEngine
    // xlEngine::OperationResult result = _modelEngine->renameModel(stdOldName, stdNewName);
    // return result.success;

    NSLog(@"[Stub] renameModel: %@ -> %@", oldName, newName);
    return YES; // stub
}

- (BOOL)duplicateModel:(NSString *)modelName {
    if (!modelName) return NO;

    std::string stdName = [modelName UTF8String];

    // TODO: Call into ModelEngine - duplicateModel would create a copy with unique name
    // xlEngine::OperationResult result = _modelEngine->duplicateModel(stdName);
    // return result.success;

    NSLog(@"[Stub] duplicateModel: %@", modelName);
    return YES; // stub
}

#pragma mark - Model Import Operations

- (BOOL)importModelFromFile:(NSString *)filePath {
    if (!filePath) return NO;

    std::string stdPath = [filePath UTF8String];

    // TODO: Call into ModelEngine
    // xlEngine::OperationResult result = _modelEngine->importFromFile(stdPath);
    // return result.success;

    NSLog(@"[Stub] importModelFromFile: %@", filePath);
    return YES; // stub
}

- (BOOL)importModelFromFile:(NSString *)filePath modelName:(NSString *)modelName {
    if (!filePath || !modelName) return NO;

    std::string stdPath = [filePath UTF8String];
    std::string stdName = [modelName UTF8String];

    // TODO: Call into ModelEngine
    // xlEngine::OperationResult result = _modelEngine->importFromFile(stdPath, stdName);
    // return result.success;

    NSLog(@"[Stub] importModelFromFile: %@ modelName: %@", filePath, modelName);
    return YES; // stub
}

- (NSArray<NSDictionary *> *)getModelsInFile:(NSString *)filePath {
    if (!filePath) return @[];

    std::string stdPath = [filePath UTF8String];

    // TODO: Call into ModelEngine
    // std::vector<xlEngine::ModelInfo> models = _modelEngine->getModelsInFile(stdPath);
    // NSMutableArray *result = [NSMutableArray array];
    // for (const auto& m : models) {
    //     [result addObject:@{
    //         @"name": [NSString stringWithUTF8String:m.name.c_str()],
    //         @"type": [NSString stringWithUTF8String:m.type.c_str()],
    //         @"channels": @(m.channelCount),
    //     }];
    // }
    // return result;

    NSLog(@"[Stub] getModelsInFile: %@", filePath);

    // Stub: return sample models
    return @[
        @{@"name": @"Model1", @"type": @"Single Line", @"channels": @(300)},
        @{@"name": @"Model2", @"type": @"Matrix", @"channels": @(1200)},
        @{@"name": @"Model3", @"type": @"Tree", @"channels": @(900)},
    ];
}

#pragma mark - Output Operations

- (NSArray<NSString *> *)getControllerNames {
    // TODO: Call into OutputEngine
    // std::vector<std::string> names = _outputEngine->getControllerNames();
    // return [self arrayFromVector:names];

    // Stub: return sample data
    return @[@"FPP (192.168.1.10)", @"Falcon F48 (192.168.1.20)"];
}

- (NSDictionary *)getControllerInfo:(NSString *)controllerName {
    if (!controllerName) return nil;

    std::string stdName = [controllerName UTF8String];

    // TODO: Call into OutputEngine
    // xlEngine::ControllerConfig config = _outputEngine->getController(stdName);
    // return [self dictFromControllerConfig:config];

    // Stub: return sample data
    return @{
        @"name": controllerName,
        @"type": @"Ethernet",
        @"protocol": @"E131",
        @"ip": @"192.168.1.10",
    };
}

- (BOOL)startOutput {
    // TODO: Call into OutputEngine
    // return _outputEngine->startOutput();

    NSLog(@"[Stub] startOutput");
    return YES; // stub
}

- (void)stopOutput {
    // TODO: Call into OutputEngine
    // _outputEngine->stopOutput();

    NSLog(@"[Stub] stopOutput");
}

- (BOOL)isOutputting {
    // TODO: Call into OutputEngine
    // return _outputEngine->isOutputting();

    return NO; // stub
}

#pragma mark - Port Configuration

- (NSArray<NSDictionary *> *)getPortsForController:(NSString *)controllerName {
    if (!controllerName) return @[];

    std::string stdName = [controllerName UTF8String];

    // TODO: Call into OutputEngine
    // std::vector<xlEngine::PortConfig> ports = _outputEngine->getControllerPorts(stdName);
    // return [self arrayFromPortConfigs:ports];

    // Stub: return sample port data
    NSMutableArray *ports = [NSMutableArray array];

    // Generate 16 pixel ports
    for (int i = 1; i <= 16; i++) {
        [ports addObject:@{
            @"port": @(i),
            @"type": @"pixel",
            @"protocol": @"ws2811",
            @"startChannel": @(0),
            @"channelCount": @(0),
            @"pixelCount": @(0),
            @"brightness": @(100),
            @"gamma": @(1.0),
            @"colorOrder": @"RGB",
            @"nullPixelsStart": @(0),
            @"nullPixelsEnd": @(0),
            @"smartRemote": @(0),
            @"modelName": @"",
        }];
    }

    // Generate 4 serial ports
    for (int i = 1; i <= 4; i++) {
        [ports addObject:@{
            @"port": @(i),
            @"type": @"serial",
            @"protocol": @"DMX",
            @"startChannel": @(0),
            @"channelCount": @(0),
            @"brightness": @(100),
            @"gamma": @(1.0),
            @"colorOrder": @"",
            @"nullPixelsStart": @(0),
            @"nullPixelsEnd": @(0),
            @"smartRemote": @(0),
            @"modelName": @"",
        }];
    }

    return ports;
}

- (BOOL)updatePort:(NSString *)controllerName
              port:(NSInteger)portNumber
        properties:(NSDictionary *)properties {
    if (!controllerName || !properties) return NO;

    std::string stdName = [controllerName UTF8String];

    // TODO: Call into OutputEngine
    // xlEngine::PortConfig config = _outputEngine->getPortConfig(stdName, (int)portNumber);
    // Apply properties to config...
    // return _outputEngine->setPortConfig(stdName, (int)portNumber, config).success;

    NSLog(@"[Stub] updatePort %@ port %ld: %@", controllerName, (long)portNumber, properties);
    return YES; // stub
}

- (BOOL)assignModel:(NSString *)modelName
       toController:(NSString *)controllerName
               port:(NSInteger)portNumber {
    if (!modelName || !controllerName) return NO;

    std::string stdModel = [modelName UTF8String];
    std::string stdController = [controllerName UTF8String];

    // TODO: Call into OutputEngine/ModelEngine
    // This would update the model's controller assignment and port

    NSLog(@"[Stub] assignModel %@ to %@ port %ld", modelName, controllerName, (long)portNumber);
    return YES; // stub
}

- (BOOL)removeModelFromController:(NSString *)controllerName
                             port:(NSInteger)portNumber {
    if (!controllerName) return NO;

    std::string stdController = [controllerName UTF8String];

    // TODO: Call into OutputEngine/ModelEngine

    NSLog(@"[Stub] removeModel from %@ port %ld", controllerName, (long)portNumber);
    return YES; // stub
}

- (NSDictionary *)getControllerCapabilities:(NSString *)controllerName {
    if (!controllerName) return nil;

    std::string stdName = [controllerName UTF8String];

    // TODO: Call into OutputEngine
    // xlEngine::ControllerCapabilities caps = _outputEngine->getControllerCapabilities(stdName);
    // return [self dictFromCapabilities:caps];

    // Stub: return typical Falcon controller capabilities
    return @{
        @"maxPixelPorts": @(48),
        @"maxSerialPorts": @(4),
        @"maxPixelPortChannels": @(1024 * 3),
        @"maxSerialPortChannels": @(512),
        @"supportsSmartRemotes": @(YES),
        @"smartRemoteCount": @(6),
        @"supportsUpload": @(YES),
        @"supportsAutoLayout": @(YES),
        @"supportsAutoSize": @(YES),
        @"supportsBrightness": @(YES),
        @"supportsGamma": @(YES),
        @"pixelProtocols": @[@"ws2811", @"ws2801", @"apa102", @"lpd8806", @"tm1809", @"tm1804", @"sm16716"],
        @"serialProtocols": @[@"DMX", @"LOR", @"Renard"],
    };
}

#pragma mark - Effect Operations

- (NSArray<NSString *> *)getEffectTypes {
    // TODO: Call into EffectEngine
    // std::vector<xlEngine::EffectTypeInfo> types = _effectEngine->getEffectTypes();
    // NSMutableArray *result = [NSMutableArray array];
    // for (const auto &type : types) {
    //     [result addObject:[NSString stringWithUTF8String:type.name.c_str()]];
    // }
    // return result;

    // Stub: return sample data
    return @[@"Bars", @"Butterfly", @"Candle", @"Circles", @"Colorwash", @"Curtain",
             @"Fire", @"Fireworks", @"Faces", @"Fan", @"Galaxy", @"Garlands"];
}

- (NSInteger)createEffect:(NSString *)modelName
                    layer:(NSInteger)layer
               effectType:(NSString *)effectType
               startTimeMS:(NSInteger)startMS
                 endTimeMS:(NSInteger)endMS {
    if (!modelName || !effectType) return -1;

    std::string stdModel = [modelName UTF8String];
    std::string stdEffect = [effectType UTF8String];

    // TODO: Call into EffectEngine
    // return _effectEngine->createEffect(stdModel, (int)layer, stdEffect, (int)startMS, (int)endMS);

    NSLog(@"[Stub] createEffect: %@ on %@, layer %ld, %ld-%ld ms",
          effectType, modelName, (long)layer, (long)startMS, (long)endMS);

    return 1; // stub effect ID
}

- (BOOL)deleteEffect:(NSInteger)effectId {
    // TODO: Call into EffectEngine
    // return _effectEngine->deleteEffect((int)effectId);

    NSLog(@"[Stub] deleteEffect: %ld", (long)effectId);
    return YES; // stub
}

#pragma mark - Utility Conversion Methods

+ (NSString *)stringFromStdString:(const char *)stdString {
    if (!stdString) return nil;
    return [NSString stringWithUTF8String:stdString];
}

+ (void)stdStringFromString:(NSString *)nsString buffer:(char **)outBuffer {
    if (!nsString || !outBuffer) return;
    const char *utf8 = [nsString UTF8String];
    size_t len = strlen(utf8);
    *outBuffer = (char *)malloc(len + 1);
    strcpy(*outBuffer, utf8);
}

#pragma mark - Private Conversion Helpers

- (NSArray<NSString *> *)arrayFromVector:(const std::vector<std::string> &)vec {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:vec.size()];
    for (const auto &str : vec) {
        [result addObject:[NSString stringWithUTF8String:str.c_str()]];
    }
    return result;
}

- (NSDictionary *)dictFromMap:(const std::map<std::string, std::string> &)map {
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:map.size()];
    for (const auto &pair : map) {
        NSString *key = [NSString stringWithUTF8String:pair.first.c_str()];
        NSString *value = [NSString stringWithUTF8String:pair.second.c_str()];
        result[key] = value;
    }
    return result;
}

@end
