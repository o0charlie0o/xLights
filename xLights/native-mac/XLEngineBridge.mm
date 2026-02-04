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

// Access to xLightsFrame singleton during transition period
#include "../xLightsApp.h"
#include "../xLightsMain.h"

// Sequencer classes for element/effect access
#include "../sequencer/SequenceElements.h"
#include "../sequencer/Element.h"
#include "../sequencer/Effect.h"
#include "../sequencer/EffectLayer.h"
#include "../SequenceViewManager.h"

// Model classes for group detection
#include "../models/Model.h"
#include "../models/ModelGroup.h"

// Audio support
#include "../AudioManager.h"

#include <string>
#include <vector>
#include <map>
#include <memory>

@implementation XLEngineBridge {
    // The SequenceEngine instance - created lazily when xLightsFrame is available
    std::unique_ptr<xlEngine::SequenceEngine> _sequenceEngine;

    // The ModelEngine instance - wraps ModelManager
    std::unique_ptr<xlEngine::ModelEngine> _modelEngine;

    // The OutputEngine instance - wraps OutputManager
    std::unique_ptr<xlEngine::OutputEngine> _outputEngine;

    // The EffectEngine instance - wraps EffectManager/SequenceElements
    std::unique_ptr<xlEngine::EffectEngine> _effectEngine;

    // The RenderEngine instance - wraps rendering pipeline
    std::unique_ptr<xlEngine::RenderEngine> _renderEngine;

    // Track whether we've initialized the engine
    BOOL _engineInitialized;
}

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super init];
    if (self) {
        _engineInitialized = NO;

        // Try to initialize the engine immediately if frame is available
        [self ensureEngineInitialized];

        if (_engineInitialized) {
            NSLog(@"XLEngineBridge initialized with SequenceEngine");
        } else {
            NSLog(@"XLEngineBridge initialized (engine will be created when frame is available)");
        }
    }
    return self;
}

- (void)ensureEngineInitialized {
    if (_engineInitialized) return;

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (frame) {
        @try {
            _sequenceEngine = std::make_unique<xlEngine::SequenceEngine>(frame);
            _modelEngine = std::make_unique<xlEngine::ModelEngine>(frame->AllModels);
            _outputEngine = std::make_unique<xlEngine::OutputEngine>();
            // Pass frame to OutputEngine so it can properly toggle output checkbox state
            _outputEngine->initialize(frame->GetOutputManager(), frame);
            _effectEngine = std::make_unique<xlEngine::EffectEngine>(frame);
            _renderEngine = std::make_unique<xlEngine::RenderEngine>(frame);
            _engineInitialized = YES;
            NSLog(@"XLEngineBridge: All engines created successfully");
        } @catch (NSException *exception) {
            NSLog(@"XLEngineBridge: Exception during engine initialization: %@ - %@",
                  exception.name, exception.reason);
            _engineInitialized = NO;
        }
    }
}

- (BOOL)isEngineAvailable {
    [self ensureEngineInitialized];
    return _engineInitialized;
}

#pragma mark - Sequence Operations

- (BOOL)loadSequence:(NSString *)path {
    if (!path || path.length == 0) {
        NSLog(@"XLEngineBridge: Cannot load sequence - path is nil or empty");
        return NO;
    }

    // Check if file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSLog(@"XLEngineBridge: Cannot load sequence - file not found: %@", path);
        return NO;
    }

    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        NSLog(@"XLEngineBridge: Cannot load sequence - engine not available");
        return NO;
    }

    @try {
        std::string stdPath = [path UTF8String];
        bool result = _sequenceEngine->loadSequence(stdPath);
        NSLog(@"XLEngineBridge: loadSequence(%@) = %s", path, result ? "YES" : "NO");
        return result ? YES : NO;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception loading sequence '%@': %@ - %@",
              path, exception.name, exception.reason);
        return NO;
    }
}

- (BOOL)saveSequence:(NSString *)path {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        NSLog(@"XLEngineBridge: Cannot save sequence - engine not available");
        return NO;
    }

    if (![self isSequenceLoaded]) {
        NSLog(@"XLEngineBridge: Cannot save sequence - no sequence loaded");
        return NO;
    }

    // If path is provided, check that the directory exists
    if (path && path.length > 0) {
        NSString *directory = [path stringByDeletingLastPathComponent];
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&isDir] || !isDir) {
            NSLog(@"XLEngineBridge: Cannot save sequence - directory does not exist: %@", directory);
            return NO;
        }
    }

    @try {
        std::string stdPath = path ? [path UTF8String] : "";
        bool result = _sequenceEngine->saveSequence(stdPath);
        NSLog(@"XLEngineBridge: saveSequence(%@) = %s", path ?: @"<current>", result ? "YES" : "NO");
        return result ? YES : NO;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception saving sequence '%@': %@ - %@",
              path ?: @"<current>", exception.name, exception.reason);
        return NO;
    }
}

- (BOOL)closeSequence {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        NSLog(@"XLEngineBridge: Cannot close sequence - engine not available");
        return NO;
    }

    bool result = _sequenceEngine->closeSequence();
    NSLog(@"XLEngineBridge: closeSequence() = %s", result ? "YES" : "NO");
    return result ? YES : NO;
}

- (BOOL)isSequenceLoaded {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        return NO;
    }

    return _sequenceEngine->isSequenceLoaded() ? YES : NO;
}

- (BOOL)createSequence:(NSInteger)durationMS
               frameMS:(NSInteger)frameMS
             mediaFile:(NSString * _Nullable)mediaFile {
    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) {
        NSLog(@"XLEngineBridge: Cannot create sequence - xLightsFrame not available");
        return NO;
    }

    @try {
        // Convert parameters
        std::string media = mediaFile ? [mediaFile UTF8String] : "";
        uint32_t duration = (uint32_t)durationMS;
        uint32_t frameInterval = (uint32_t)frameMS;

        // Call NewSequence on the frame - this handles all the setup
        frame->NewSequence(media, duration, frameInterval, "");

        NSLog(@"XLEngineBridge: createSequence completed - duration: %ldms, frameMS: %ldms, media: %@",
              (long)durationMS, (long)frameMS, mediaFile ?: @"(none)");

        return [self isSequenceLoaded];
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception creating sequence: %@ - %@",
              exception.name, exception.reason);
        return NO;
    }
}

- (NSDictionary *)getSequenceInfo {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return nil;
    }

    @try {
        xlEngine::SequenceInfo info = _sequenceEngine->getSequenceInfo();

        // Safely convert strings, defaulting to empty string if null
        NSString *name = info.name.empty() ? @"" : [NSString stringWithUTF8String:info.name.c_str()];
        NSString *mediaFile = info.mediaFile.empty() ? @"" : [NSString stringWithUTF8String:info.mediaFile.c_str()];
        NSString *sequenceType = info.sequenceType.empty() ? @"" : [NSString stringWithUTF8String:info.sequenceType.c_str()];
        NSString *author = info.author.empty() ? @"" : [NSString stringWithUTF8String:info.author.c_str()];
        NSString *song = info.song.empty() ? @"" : [NSString stringWithUTF8String:info.song.c_str()];
        NSString *artist = info.artist.empty() ? @"" : [NSString stringWithUTF8String:info.artist.c_str()];
        NSString *album = info.album.empty() ? @"" : [NSString stringWithUTF8String:info.album.c_str()];
        NSString *comment = info.comment.empty() ? @"" : [NSString stringWithUTF8String:info.comment.c_str()];

        return @{
            @"name": name,
            @"mediaFile": mediaFile,
            @"sequenceType": sequenceType,
            @"durationMS": @(info.durationMS),
            @"frameTimeMS": @(info.frameTimeMS > 0 ? info.frameTimeMS : 50), // Default to 50ms (20fps)
            @"numChannels": @(info.numChannels),
            @"numFrames": @(info.numFrames),
            @"author": author,
            @"song": song,
            @"artist": artist,
            @"album": album,
            @"comment": comment,
        };
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception getting sequence info: %@ - %@",
              exception.name, exception.reason);
        return nil;
    }
}

#pragma mark - Playback Control

- (void)play {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        NSLog(@"XLEngineBridge: Cannot play - engine not available");
        return;
    }

    _sequenceEngine->play();
    NSLog(@"XLEngineBridge: play()");
}

- (void)pause {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        NSLog(@"XLEngineBridge: Cannot pause - engine not available");
        return;
    }

    _sequenceEngine->pause();
    NSLog(@"XLEngineBridge: pause()");
}

- (void)stop {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        NSLog(@"XLEngineBridge: Cannot stop - engine not available");
        return;
    }

    _sequenceEngine->stop();
    NSLog(@"XLEngineBridge: stop()");
}

- (void)seek:(NSInteger)positionMS {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        NSLog(@"XLEngineBridge: Cannot seek - engine not available");
        return;
    }

    _sequenceEngine->seek((int)positionMS);
    NSLog(@"XLEngineBridge: seek(%ld ms)", (long)positionMS);
}

- (void)seekToStart {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        NSLog(@"XLEngineBridge: Cannot seekToStart - engine not available");
        return;
    }

    _sequenceEngine->seekToStart();
    NSLog(@"XLEngineBridge: seekToStart()");
}

- (void)seekToEnd {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        NSLog(@"XLEngineBridge: Cannot seekToEnd - engine not available");
        return;
    }

    _sequenceEngine->seekToEnd();
    NSLog(@"XLEngineBridge: seekToEnd()");
}

- (void)seekRelative:(NSInteger)deltaMS {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        NSLog(@"XLEngineBridge: Cannot seekRelative - engine not available");
        return;
    }

    _sequenceEngine->seekRelative((int)deltaMS);
    NSLog(@"XLEngineBridge: seekRelative(%ld ms)", (long)deltaMS);
}

#pragma mark - Playback State

- (NSString *)getPlaybackState {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        return @"stopped";
    }

    xlEngine::PlaybackState state = _sequenceEngine->getPlaybackState();
    switch (state) {
        case xlEngine::PlaybackState::Playing:
            return @"playing";
        case xlEngine::PlaybackState::Paused:
            return @"paused";
        case xlEngine::PlaybackState::Stopped:
        default:
            return @"stopped";
    }
}

- (NSInteger)getPosition {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        return 0;
    }

    return _sequenceEngine->getPosition();
}

- (NSInteger)getDuration {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        return 0;
    }

    return _sequenceEngine->getDuration();
}

- (NSInteger)getFrameRate {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        return 0;
    }

    return _sequenceEngine->getFrameRate();
}

- (NSInteger)getFrameTimeMS {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        return 0;
    }

    return _sequenceEngine->getFrameTimeMS();
}

#pragma mark - Rendering

- (void)renderAll {
    [self ensureEngineInitialized];
    if (!_renderEngine) {
        NSLog(@"XLEngineBridge: Cannot render - engine not available");
        return;
    }

    _renderEngine->renderAll(nullptr);
    NSLog(@"XLEngineBridge: renderAll()");
}

- (void)renderRange:(NSInteger)startMS endMS:(NSInteger)endMS {
    [self ensureEngineInitialized];
    if (!_renderEngine) {
        NSLog(@"XLEngineBridge: Cannot render - engine not available");
        return;
    }

    _renderEngine->renderRange((int)startMS, (int)endMS, false, nullptr);
    NSLog(@"XLEngineBridge: renderRange(%ld - %ld ms)", (long)startMS, (long)endMS);
}

- (void)abortRender {
    [self ensureEngineInitialized];
    if (!_renderEngine) {
        NSLog(@"XLEngineBridge: Cannot abort render - engine not available");
        return;
    }

    bool aborted = _renderEngine->abortRender();
    NSLog(@"XLEngineBridge: abortRender() = %s", aborted ? "YES" : "NO");
}

- (void)renderFrame:(NSInteger)timeMS {
    [self ensureEngineInitialized];
    if (!_renderEngine) {
        NSLog(@"XLEngineBridge: Cannot render frame - engine not available");
        return;
    }

    _renderEngine->renderFrame((int)timeMS);
}

- (void)renderModelFrame:(NSString *)modelName timeMS:(NSInteger)timeMS {
    if (!modelName) return;

    [self ensureEngineInitialized];
    if (!_renderEngine) {
        NSLog(@"XLEngineBridge: Cannot render model frame - engine not available");
        return;
    }

    std::string stdName = [modelName UTF8String];
    _renderEngine->renderModelFrame(stdName, (int)timeMS);
}

- (NSDictionary *)getFrameBuffer:(NSString *)modelName {
    if (!modelName) return nil;

    [self ensureEngineInitialized];
    if (!_renderEngine) {
        return nil;
    }

    std::string stdName = [modelName UTF8String];
    xlEngine::FrameBuffer fb = _renderEngine->getFrameBuffer(stdName);

    if (!fb.isValid()) {
        return nil;
    }

    NSData *pixelData = [NSData dataWithBytes:fb.pixels.data() length:fb.pixels.size()];

    return @{
        @"modelName": [NSString stringWithUTF8String:fb.modelName.c_str()],
        @"width": @(fb.width),
        @"height": @(fb.height),
        @"timeMS": @(fb.timeMS),
        @"pixels": pixelData,
    };
}

- (NSDictionary *)getPrerenderedFrameBuffer:(NSString *)modelName timeMS:(NSInteger)timeMS {
    if (!modelName) return nil;

    [self ensureEngineInitialized];
    if (!_renderEngine) {
        return nil;
    }

    std::string stdName = [modelName UTF8String];
    xlEngine::FrameBuffer fb = _renderEngine->getPrerenderedFrameBuffer(stdName, static_cast<int>(timeMS));

    if (!fb.isValid()) {
        return nil;
    }

    NSData *pixelData = [NSData dataWithBytes:fb.pixels.data() length:fb.pixels.size()];

    return @{
        @"modelName": [NSString stringWithUTF8String:fb.modelName.c_str()],
        @"width": @(fb.width),
        @"height": @(fb.height),
        @"timeMS": @(fb.timeMS),
        @"pixels": pixelData,
    };
}

- (NSArray<NSDictionary *> *)getNodeData:(NSString *)modelName {
    if (!modelName) return @[];

    [self ensureEngineInitialized];
    if (!_renderEngine) {
        return @[];
    }

    std::string stdName = [modelName UTF8String];
    std::vector<xlEngine::NodeChannelData> nodes = _renderEngine->getNodeData(stdName);

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:nodes.size()];
    for (const auto &node : nodes) {
        NSData *data = [NSData dataWithBytes:node.data.data() length:node.data.size()];
        [result addObject:@{
            @"startChannel": @(node.startChannel),
            @"channelCount": @(node.channelCount),
            @"data": data,
        }];
    }
    return result;
}

- (BOOL)isRendering {
    [self ensureEngineInitialized];
    if (!_renderEngine) {
        return NO;
    }

    return _renderEngine->isRendering() ? YES : NO;
}

#pragma mark - Model Operations

- (NSArray<NSString *> *)getModelNames {
    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot get model names - engine not available");
        return @[];
    }

    std::vector<std::string> names = _modelEngine->getModelNames();
    return [self arrayFromVector:names];
}

- (NSDictionary *)getModelInfo:(NSString *)modelName {
    if (!modelName) return nil;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot get model info - engine not available");
        return nil;
    }

    std::string stdName = [modelName UTF8String];
    if (!_modelEngine->hasModel(stdName)) {
        return nil;
    }

    xlEngine::ModelInfo info = _modelEngine->getModel(stdName);
    return [self dictFromModelInfo:info];
}

- (BOOL)hasModel:(NSString *)modelName {
    if (!modelName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        return NO;
    }

    std::string stdName = [modelName UTF8String];
    return _modelEngine->hasModel(stdName) ? YES : NO;
}

- (BOOL)updateModelProperty:(NSString *)modelName key:(NSString *)key value:(id)value {
    if (!modelName || !key) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot update model property - engine not available");
        return NO;
    }

    std::string stdName = [modelName UTF8String];
    std::string stdKey = [key UTF8String];

    // Convert value to string
    NSString *stringValue;
    if ([value isKindOfClass:[NSString class]]) {
        stringValue = value;
    } else if ([value isKindOfClass:[NSNumber class]]) {
        stringValue = [value stringValue];
    } else {
        stringValue = [value description];
    }
    std::string stdValue = [stringValue UTF8String];

    xlEngine::OperationResult result = _modelEngine->updateModelProperty(stdName, stdKey, stdValue);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to update model property: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)createModel:(NSString *)modelType name:(NSString *)modelName properties:(NSDictionary *)properties {
    if (!modelType || !modelName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot create model - engine not available");
        return NO;
    }

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

    xlEngine::OperationResult result = _modelEngine->createModel(stdType, stdName, stdProps);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to create model: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)deleteModel:(NSString *)modelName {
    if (!modelName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot delete model - engine not available");
        return NO;
    }

    std::string stdName = [modelName UTF8String];
    xlEngine::OperationResult result = _modelEngine->deleteModel(stdName);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to delete model: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)renameModel:(NSString *)oldName toName:(NSString *)newName {
    if (!oldName || !newName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot rename model - engine not available");
        return NO;
    }

    std::string stdOldName = [oldName UTF8String];
    std::string stdNewName = [newName UTF8String];
    xlEngine::OperationResult result = _modelEngine->renameModel(stdOldName, stdNewName);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to rename model: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)duplicateModel:(NSString *)modelName {
    if (!modelName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot duplicate model - engine not available");
        return NO;
    }

    // Note: ModelEngine doesn't currently have duplicateModel - this needs to be added
    // For now, we could implement by getting model info and creating a new model
    std::string stdName = [modelName UTF8String];
    if (!_modelEngine->hasModel(stdName)) {
        return NO;
    }

    // Generate unique name
    xlEngine::ModelInfo info = _modelEngine->getModel(stdName);
    std::string newName = info.name + " Copy";
    int counter = 1;
    while (_modelEngine->hasModel(newName)) {
        newName = info.name + " Copy " + std::to_string(++counter);
    }

    xlEngine::OperationResult result = _modelEngine->createModel(info.type, newName, info.properties);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to duplicate model: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (NSArray<NSString *> *)getModelNamesExcludingGroups {
    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot get model names - engine not available");
        return @[];
    }

    std::vector<std::string> names = _modelEngine->getModelNamesExcludingGroups();
    return [self arrayFromVector:names];
}

- (NSArray<NSString *> *)getGroupNames {
    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot get group names - engine not available");
        return @[];
    }

    std::vector<std::string> names = _modelEngine->getGroupNames();
    return [self arrayFromVector:names];
}

- (NSString *)getModelProperty:(NSString *)modelName key:(NSString *)key defaultValue:(NSString *)defaultValue {
    if (!modelName || !key) return defaultValue;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        return defaultValue;
    }

    std::string stdName = [modelName UTF8String];
    std::string stdKey = [key UTF8String];
    std::string stdDefault = defaultValue ? [defaultValue UTF8String] : "";
    std::string value = _modelEngine->getModelProperty(stdName, stdKey, stdDefault);
    return [NSString stringWithUTF8String:value.c_str()];
}

- (NSDictionary *)getModelProperties:(NSString *)modelName {
    if (!modelName) return @{};

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        return @{};
    }

    std::string stdName = [modelName UTF8String];
    std::map<std::string, std::string> props = _modelEngine->getModelProperties(stdName);
    return [self dictFromMap:props];
}

#pragma mark - Model Groups

- (NSArray<NSDictionary *> *)getModelGroups {
    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot get model groups - engine not available");
        return @[];
    }

    std::vector<xlEngine::ModelGroupInfo> groups = _modelEngine->getModelGroups();
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:groups.size()];
    for (const auto &group : groups) {
        NSMutableArray *modelNames = [NSMutableArray arrayWithCapacity:group.modelNames.size()];
        for (const auto &name : group.modelNames) {
            [modelNames addObject:[NSString stringWithUTF8String:name.c_str()]];
        }
        [result addObject:@{
            @"name": [NSString stringWithUTF8String:group.name.c_str()],
            @"modelNames": modelNames,
            @"defaultBufferStyle": [NSString stringWithUTF8String:group.defaultBufferStyle.c_str()],
        }];
    }
    return result;
}

- (NSDictionary *)getModelGroup:(NSString *)groupName {
    if (!groupName) return nil;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        return nil;
    }

    std::string stdName = [groupName UTF8String];
    xlEngine::ModelGroupInfo group = _modelEngine->getModelGroup(stdName);
    if (group.name.empty()) {
        return nil;
    }

    NSMutableArray *modelNames = [NSMutableArray arrayWithCapacity:group.modelNames.size()];
    for (const auto &name : group.modelNames) {
        [modelNames addObject:[NSString stringWithUTF8String:name.c_str()]];
    }
    return @{
        @"name": [NSString stringWithUTF8String:group.name.c_str()],
        @"modelNames": modelNames,
        @"defaultBufferStyle": [NSString stringWithUTF8String:group.defaultBufferStyle.c_str()],
    };
}

- (NSArray<NSString *> *)getGroupsContainingModel:(NSString *)modelName {
    if (!modelName) return @[];

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        return @[];
    }

    std::string stdName = [modelName UTF8String];
    std::vector<std::string> groups = _modelEngine->getGroupsContainingModel(stdName);
    return [self arrayFromVector:groups];
}

#pragma mark - Submodels

- (NSArray<NSDictionary *> *)getSubmodels:(NSString *)modelName {
    if (!modelName) return @[];

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        return @[];
    }

    std::string stdName = [modelName UTF8String];
    std::vector<xlEngine::SubmodelInfo> submodels = _modelEngine->getSubmodels(stdName);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:submodels.size()];
    for (const auto &sm : submodels) {
        [result addObject:@{
            @"name": [NSString stringWithUTF8String:sm.name.c_str()],
            @"fullName": [NSString stringWithUTF8String:sm.fullName.c_str()],
            @"nodeCount": @(sm.nodeCount),
            @"channelCount": @(sm.channelCount),
        }];
    }
    return result;
}

- (BOOL)hasSubmodel:(NSString *)modelName submodelName:(NSString *)submodelName {
    if (!modelName || !submodelName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        return NO;
    }

    std::string stdModel = [modelName UTF8String];
    std::string stdSubmodel = [submodelName UTF8String];
    return _modelEngine->hasSubmodel(stdModel, stdSubmodel) ? YES : NO;
}

#pragma mark - Model Geometry

- (NSArray<NSDictionary *> *)getModelNodes:(NSString *)modelName {
    if (!modelName) return @[];

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        return @[];
    }

    std::string stdName = [modelName UTF8String];
    std::vector<xlEngine::NodeCoord> nodes = _modelEngine->getModelNodes(stdName);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:nodes.size()];
    for (const auto &node : nodes) {
        [result addObject:@{
            @"x": @(node.x),
            @"y": @(node.y),
            @"z": @(node.z),
            @"bufX": @(node.bufX),
            @"bufY": @(node.bufY),
            @"channel": @(node.actChannel),
            @"channelCount": @(node.channelCount),
            @"stringNum": @(node.stringNum),
        }];
    }
    return result;
}

- (NSUInteger)getModelNodeCount:(NSString *)modelName {
    if (!modelName) return 0;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        return 0;
    }

    std::string stdName = [modelName UTF8String];
    return _modelEngine->getModelNodeCount(stdName);
}

- (NSUInteger)getModelChannelCount:(NSString *)modelName {
    if (!modelName) return 0;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        return 0;
    }

    std::string stdName = [modelName UTF8String];
    return _modelEngine->getModelChannelCount(stdName);
}

- (NSDictionary *)getModelBounds:(NSString *)modelName {
    if (!modelName) return nil;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        return nil;
    }

    std::string stdName = [modelName UTF8String];
    xlEngine::ModelEngine::BoundingBox box = _modelEngine->getModelBounds(stdName);
    return @{
        @"minX": @(box.minX),
        @"maxX": @(box.maxX),
        @"minY": @(box.minY),
        @"maxY": @(box.maxY),
        @"minZ": @(box.minZ),
        @"maxZ": @(box.maxZ),
    };
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
    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot get controller names - engine not available");
        return @[];
    }

    std::vector<std::string> names = _outputEngine->getControllerNames();
    return [self arrayFromVector:names];
}

- (NSDictionary *)getControllerInfo:(NSString *)controllerName {
    if (!controllerName) return nil;

    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot get controller info - engine not available");
        return nil;
    }

    std::string stdName = [controllerName UTF8String];
    if (!_outputEngine->controllerExists(stdName)) {
        return nil;
    }

    xlEngine::ControllerConfig config = _outputEngine->getController(stdName);
    return [self dictFromControllerConfig:config];
}

- (BOOL)startOutput {
    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot start output - engine not available");
        return NO;
    }

    bool result = _outputEngine->startOutput();
    NSLog(@"XLEngineBridge: startOutput() = %s", result ? "YES" : "NO");
    return result ? YES : NO;
}

- (void)stopOutput {
    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot stop output - engine not available");
        return;
    }

    _outputEngine->stopOutput();
    NSLog(@"XLEngineBridge: stopOutput()");
}

- (BOOL)isOutputting {
    [self ensureEngineInitialized];
    if (!_outputEngine) {
        return NO;
    }

    return _outputEngine->isOutputting() ? YES : NO;
}

#pragma mark - Port Configuration

- (NSArray<NSDictionary *> *)getPortsForController:(NSString *)controllerName {
    if (!controllerName) return @[];

    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot get ports - engine not available");
        return @[];
    }

    std::string stdName = [controllerName UTF8String];
    std::vector<xlEngine::PortConfig> ports = _outputEngine->getControllerPorts(stdName);
    return [self arrayFromPortConfigs:ports];
}

- (BOOL)updatePort:(NSString *)controllerName
              port:(NSInteger)portNumber
        properties:(NSDictionary *)properties {
    if (!controllerName || !properties) return NO;

    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot update port - engine not available");
        return NO;
    }

    std::string stdName = [controllerName UTF8String];

    // Get current port configuration
    std::vector<xlEngine::PortConfig> ports = _outputEngine->getControllerPorts(stdName);
    if (portNumber < 1 || portNumber > (NSInteger)ports.size()) {
        NSLog(@"XLEngineBridge: Port %ld not found on controller %@", (long)portNumber, controllerName);
        return NO;
    }

    // Find the port config (port numbers are 1-indexed)
    xlEngine::PortConfig config = ports[portNumber - 1];

    // Apply properties from the dictionary
    if (properties[@"protocol"]) {
        config.protocol = [properties[@"protocol"] UTF8String];
    }
    if (properties[@"startChannel"]) {
        config.startChannel = [properties[@"startChannel"] intValue];
    }
    if (properties[@"channelCount"] || properties[@"channels"]) {
        NSNumber *channels = properties[@"channelCount"] ?: properties[@"channels"];
        config.channels = [channels intValue];
    }
    if (properties[@"brightness"]) {
        config.brightness = [properties[@"brightness"] intValue];
    }
    if (properties[@"gamma"]) {
        config.gamma = [properties[@"gamma"] floatValue];
    }
    if (properties[@"nullPixelsStart"] || properties[@"nullPixels"]) {
        NSNumber *nullPx = properties[@"nullPixelsStart"] ?: properties[@"nullPixels"];
        config.nullPixels = [nullPx intValue];
    }
    if (properties[@"nullPixelsEnd"]) {
        config.endNullPixels = [properties[@"nullPixelsEnd"] intValue];
    }
    if (properties[@"colorOrder"]) {
        config.colorOrder = [properties[@"colorOrder"] UTF8String];
    }
    if (properties[@"groupCount"]) {
        config.groupCount = [properties[@"groupCount"] intValue];
    }
    if (properties[@"reverse"]) {
        config.reverse = [properties[@"reverse"] boolValue];
    }
    if (properties[@"zigZag"]) {
        config.zigZag = [properties[@"zigZag"] intValue];
    }
    if (properties[@"smartRemoteType"]) {
        config.smartRemoteType = [properties[@"smartRemoteType"] UTF8String];
    }

    xlEngine::OperationResult result = _outputEngine->setPortConfig(stdName, (int)portNumber, config);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to update port %ld on %@: %s",
              (long)portNumber, controllerName, result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)assignModel:(NSString *)modelName
       toController:(NSString *)controllerName
               port:(NSInteger)portNumber {
    if (!modelName || !controllerName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot assign model - engine not available");
        return NO;
    }

    std::string stdModel = [modelName UTF8String];
    std::string stdController = [controllerName UTF8String];

    // Update the model's Controller property to assign it to a controller:port
    // Format: "ControllerName:port" (e.g. "Falcon F48:1")
    std::string controllerSpec = stdController + ":" + std::to_string(portNumber);
    xlEngine::OperationResult result = _modelEngine->updateModelProperty(stdModel, "Controller", controllerSpec);

    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to assign model %@ to %@:%ld: %s",
              modelName, controllerName, (long)portNumber, result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)removeModelFromController:(NSString *)controllerName
                             port:(NSInteger)portNumber {
    if (!controllerName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine || !_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot remove model from controller - engine not available");
        return NO;
    }

    std::string stdController = [controllerName UTF8String];

    // To remove a model from a controller port, we need to find which model
    // is assigned to this controller:port and clear its Controller property.
    // Find the model assigned to this controller and port
    std::string controllerSpec = stdController + ":" + std::to_string(portNumber);

    // Search all models to find one assigned to this controller:port
    std::vector<std::string> modelNames = _modelEngine->getModelNames();
    for (const auto& name : modelNames) {
        std::string assignedController = _modelEngine->getModelProperty(name, "Controller", "");
        if (assignedController == controllerSpec) {
            // Clear the model's controller assignment
            xlEngine::OperationResult result = _modelEngine->updateModelProperty(name, "Controller", "");
            if (!result.success) {
                NSLog(@"XLEngineBridge: Failed to remove model %s from %@:%ld: %s",
                      name.c_str(), controllerName, (long)portNumber, result.message.c_str());
                return NO;
            }
            return YES;
        }
    }

    // No model found on that port - nothing to remove
    return YES;
}

- (NSDictionary *)getControllerCapabilities:(NSString *)controllerName {
    if (!controllerName) return nil;

    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot get controller capabilities - engine not available");
        return nil;
    }

    std::string stdName = [controllerName UTF8String];
    xlEngine::ControllerCapabilities caps = _outputEngine->getControllerCapabilities(stdName);
    return [self dictFromControllerCapabilities:caps];
}

- (NSInteger)getTotalChannels {
    [self ensureEngineInitialized];
    if (!_outputEngine) {
        return 0;
    }

    return (NSInteger)_outputEngine->getTotalChannels();
}

- (BOOL)isOutputDirty {
    [self ensureEngineInitialized];
    if (!_outputEngine) {
        return NO;
    }

    return _outputEngine->isDirty() ? YES : NO;
}

- (BOOL)saveOutputConfiguration {
    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot save output configuration - engine not available");
        return NO;
    }

    xlEngine::OperationResult result = _outputEngine->save();
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to save output configuration: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

#pragma mark - Controller Discovery

- (void)discoverControllers:(void (^)(BOOL success, NSArray<NSDictionary *> *controllers))completion {
    if (!completion) return;

    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot discover controllers - engine not available");
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, @[]);
        });
        return;
    }

    // Capture self for the callback block
    __weak typeof(self) weakSelf = self;

    _outputEngine->discoverControllers([weakSelf, completion](bool success, const std::vector<xlEngine::DiscoveredController>& controllers) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @[]);
            });
            return;
        }

        NSMutableArray *result = [NSMutableArray arrayWithCapacity:controllers.size()];
        for (const auto &controller : controllers) {
            [result addObject:[strongSelf dictFromDiscoveredController:controller]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(success ? YES : NO, result);
        });
    });
}

- (BOOL)addDiscoveredController:(NSDictionary *)discoveredInfo {
    if (!discoveredInfo) return NO;

    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot add discovered controller - engine not available");
        return NO;
    }

    // Convert NSDictionary back to DiscoveredController struct
    xlEngine::DiscoveredController discovered;
    discovered.ip = discoveredInfo[@"ip"] ? [discoveredInfo[@"ip"] UTF8String] : "";
    discovered.hostname = discoveredInfo[@"hostname"] ? [discoveredInfo[@"hostname"] UTF8String] : "";
    discovered.vendor = discoveredInfo[@"vendor"] ? [discoveredInfo[@"vendor"] UTF8String] : "";
    discovered.model = discoveredInfo[@"model"] ? [discoveredInfo[@"model"] UTF8String] : "";
    discovered.variant = discoveredInfo[@"variant"] ? [discoveredInfo[@"variant"] UTF8String] : "";
    discovered.description = discoveredInfo[@"description"] ? [discoveredInfo[@"description"] UTF8String] : "";
    discovered.version = discoveredInfo[@"version"] ? [discoveredInfo[@"version"] UTF8String] : "";
    discovered.mode = discoveredInfo[@"mode"] ? [discoveredInfo[@"mode"] UTF8String] : "";
    discovered.platform = discoveredInfo[@"platform"] ? [discoveredInfo[@"platform"] UTF8String] : "";
    discovered.platformModel = discoveredInfo[@"platformModel"] ? [discoveredInfo[@"platformModel"] UTF8String] : "";
    discovered.uuid = discoveredInfo[@"uuid"] ? [discoveredInfo[@"uuid"] UTF8String] : "";
    discovered.proxy = discoveredInfo[@"proxy"] ? [discoveredInfo[@"proxy"] UTF8String] : "";
    discovered.majorVersion = discoveredInfo[@"majorVersion"] ? [discoveredInfo[@"majorVersion"] intValue] : 0;
    discovered.minorVersion = discoveredInfo[@"minorVersion"] ? [discoveredInfo[@"minorVersion"] intValue] : 0;
    discovered.patchVersion = discoveredInfo[@"patchVersion"] ? [discoveredInfo[@"patchVersion"] intValue] : 0;

    xlEngine::OperationResult result = _outputEngine->addDiscoveredController(discovered);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to add discovered controller: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (void)testController:(NSString *)controllerName completion:(void (^)(NSString *pingState))completion {
    if (!controllerName || !completion) return;

    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot test controller - engine not available");
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(@"Unknown");
        });
        return;
    }

    std::string stdName = [controllerName UTF8String];

    _outputEngine->testController(stdName, [completion](const std::string& controllerId, xlEngine::PingState state) {
        NSString *stateStr = @"Unknown";
        switch (state) {
            case xlEngine::PingState::OK: stateStr = @"OK"; break;
            case xlEngine::PingState::WebOK: stateStr = @"WebOK"; break;
            case xlEngine::PingState::Open: stateStr = @"Open"; break;
            case xlEngine::PingState::Opened: stateStr = @"Opened"; break;
            case xlEngine::PingState::AllFailed: stateStr = @"AllFailed"; break;
            case xlEngine::PingState::Unavailable: stateStr = @"Unavailable"; break;
            default: break;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(stateStr);
        });
    });
}

- (void)testAllControllers:(void (^)(NSString *controllerName, NSString *pingState))completion {
    if (!completion) return;

    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot test controllers - engine not available");
        return;
    }

    _outputEngine->testAllControllers([completion](const std::string& controllerId, xlEngine::PingState state) {
        NSString *nameStr = [NSString stringWithUTF8String:controllerId.c_str()];
        NSString *stateStr = @"Unknown";
        switch (state) {
            case xlEngine::PingState::OK: stateStr = @"OK"; break;
            case xlEngine::PingState::WebOK: stateStr = @"WebOK"; break;
            case xlEngine::PingState::Open: stateStr = @"Open"; break;
            case xlEngine::PingState::Opened: stateStr = @"Opened"; break;
            case xlEngine::PingState::AllFailed: stateStr = @"AllFailed"; break;
            case xlEngine::PingState::Unavailable: stateStr = @"Unavailable"; break;
            default: break;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nameStr, stateStr);
        });
    });
}

#pragma mark - Controller Upload

- (void)uploadToController:(NSString *)controllerName
                completion:(void (^)(BOOL success, NSString *message))completion {
    if (!controllerName || !completion) return;

    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot upload to controller - engine not available");
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, @"Engine not available");
        });
        return;
    }

    std::string stdName = [controllerName UTF8String];

    _outputEngine->uploadToController(stdName, [completion](bool success, const std::string& message) {
        NSString *msgStr = [NSString stringWithUTF8String:message.c_str()];

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(success ? YES : NO, msgStr);
        });
    });
}

- (void)uploadInputToController:(NSString *)controllerName
                     completion:(void (^)(BOOL success, NSString *message))completion {
    if (!controllerName || !completion) return;

    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot upload input to controller - engine not available");
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, @"Engine not available");
        });
        return;
    }

    std::string stdName = [controllerName UTF8String];

    _outputEngine->uploadInputToController(stdName, [completion](bool success, const std::string& message) {
        NSString *msgStr = [NSString stringWithUTF8String:message.c_str()];

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(success ? YES : NO, msgStr);
        });
    });
}

- (void)uploadOutputToController:(NSString *)controllerName
                      completion:(void (^)(BOOL success, NSString *message))completion {
    if (!controllerName || !completion) return;

    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot upload output to controller - engine not available");
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, @"Engine not available");
        });
        return;
    }

    std::string stdName = [controllerName UTF8String];

    _outputEngine->uploadOutputToController(stdName, [completion](bool success, const std::string& message) {
        NSString *msgStr = [NSString stringWithUTF8String:message.c_str()];

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(success ? YES : NO, msgStr);
        });
    });
}

#pragma mark - Sequence Views

- (NSArray<NSString *> *)getViewNames {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return @[@"Master View"];
    }

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return @[@"Master View"];

    SequenceViewManager* viewManager = frame->GetViewsManager();
    if (!viewManager) return @[@"Master View"];

    NSMutableArray<NSString *> *viewNames = [NSMutableArray array];

    // Get all views - Master View is always first
    auto views = viewManager->GetViews();
    for (auto* view : views) {
        if (view) {
            NSString *name = [NSString stringWithUTF8String:view->GetName().c_str()];
            [viewNames addObject:name];
        }
    }

    // Ensure at least Master View exists
    if (viewNames.count == 0) {
        [viewNames addObject:@"Master View"];
    }

    return [viewNames copy];
}

- (NSString *)getCurrentViewName {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return @"Master View";
    }

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return @"Master View";

    SequenceViewManager* viewManager = frame->GetViewsManager();
    if (!viewManager) return @"Master View";

    SequenceView* currentView = viewManager->GetSelectedView();
    if (!currentView) return @"Master View";

    return [NSString stringWithUTF8String:currentView->GetName().c_str()];
}

- (NSInteger)getCurrentViewIndex {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return 0;
    }

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return 0;

    SequenceElements& elements = frame->GetSequenceElements();
    return (NSInteger)elements.GetCurrentView();
}

- (BOOL)setCurrentView:(NSString *)viewName {
    if (!viewName) return NO;

    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return NO;
    }

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return NO;

    SequenceElements& elements = frame->GetSequenceElements();
    SequenceViewManager* viewManager = frame->GetViewsManager();
    if (!viewManager) return NO;

    std::string stdViewName = [viewName UTF8String];

    // Find the view index by name
    int viewIndex = viewManager->GetViewIndex(stdViewName);
    if (viewIndex < 0) {
        return NO;
    }

    // Only populate view for non-Master views (index > 0)
    // Master View (index 0) already contains all elements
    if (viewIndex > 0) {
        std::string modelsString = elements.GetViewModels(stdViewName);
        elements.AddMissingModelsToSequence(modelsString);
        elements.PopulateView(modelsString, viewIndex);
    }

    // Set as current view
    elements.SetCurrentView(viewIndex);

    // Set timing visibility for this view
    elements.SetTimingVisibility(stdViewName);

    return YES;
}

- (BOOL)setCurrentViewIndex:(NSInteger)viewIndex {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return NO;
    }

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return NO;

    SequenceElements& elements = frame->GetSequenceElements();
    SequenceViewManager* viewManager = frame->GetViewsManager();
    if (!viewManager) return NO;

    // Validate index
    if (viewIndex < 0 || viewIndex >= viewManager->GetViewCount()) {
        return NO;
    }

    // Get the view at this index
    SequenceView* view = viewManager->GetView((int)viewIndex);
    if (!view) return NO;

    std::string viewName = view->GetName();

    // Only populate view for non-Master views (index > 0)
    // Master View (index 0) already contains all elements
    if (viewIndex > 0) {
        std::string modelsString = elements.GetViewModels(viewName);
        elements.AddMissingModelsToSequence(modelsString);
        elements.PopulateView(modelsString, (int)viewIndex);
    }

    // Set as current view
    elements.SetCurrentView((int)viewIndex);

    // Set timing visibility for this view
    elements.SetTimingVisibility(viewName);

    return YES;
}

#pragma mark - Sequence Elements (for Sequencer View)

- (NSInteger)getSequenceElementCount {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return 0;
    }

    // Access SequenceElements through xLightsFrame
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return 0;

    SequenceElements& elements = frame->GetSequenceElements();
    int currentView = elements.GetCurrentView();
    return (NSInteger)elements.GetElementCount(currentView);
}

- (NSDictionary *)getSequenceElementAtIndex:(NSInteger)index {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return nil;
    }

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return nil;

    SequenceElements& elements = frame->GetSequenceElements();
    int currentView = elements.GetCurrentView();
    if (index < 0 || index >= (NSInteger)elements.GetElementCount(currentView)) {
        return nil;
    }

    Element* elem = elements.GetElement((size_t)index, currentView);
    if (!elem) return nil;

    NSString *typeString;
    BOOL isGroup = NO;
    BOOL hasSubmodels = NO;
    BOOL hasStrands = NO;
    NSInteger submodelCount = 0;
    NSInteger strandCount = 0;

    ElementType type = elem->GetType();
    switch (type) {
        case ElementType::ELEMENT_TYPE_TIMING:
            typeString = @"timing";
            break;
        case ElementType::ELEMENT_TYPE_MODEL: {
            // Check if this is actually a model group
            ModelElement* modelElem = dynamic_cast<ModelElement*>(elem);
            if (modelElem) {
                submodelCount = modelElem->GetSubModelCount();
                strandCount = modelElem->GetStrandCount();
                hasSubmodels = (submodelCount > 0);
                hasStrands = (strandCount > 0);

                // Check underlying model to see if it's a group
                Model* model = frame->AllModels[elem->GetName()];
                if (model && model->GetDisplayAs() == "ModelGroup") {
                    typeString = @"group";
                    isGroup = YES;
                } else {
                    typeString = @"model";
                }
            } else {
                typeString = @"model";
            }
            break;
        }
        case ElementType::ELEMENT_TYPE_SUBMODEL:
            typeString = @"submodel";
            break;
        case ElementType::ELEMENT_TYPE_STRAND:
            typeString = @"strand";
            break;
        default:
            typeString = @"unknown";
            break;
    }

    return @{
        @"name": [NSString stringWithUTF8String:elem->GetName().c_str()],
        @"type": typeString,
        @"effectLayerCount": @(elem->GetEffectLayerCount()),
        @"visible": @(elem->GetVisible()),
        @"collapsed": @(elem->GetCollapsed()),
        @"isGroup": @(isGroup),
        @"hasSubmodels": @(hasSubmodels),
        @"hasStrands": @(hasStrands),
        @"submodelCount": @(submodelCount),
        @"strandCount": @(strandCount),
    };
}

- (NSArray<NSDictionary *> *)getSequenceElements {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return @[];
    }

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return @[];

    SequenceElements& elements = frame->GetSequenceElements();
    int currentView = elements.GetCurrentView();
    NSMutableArray *result = [NSMutableArray array];

    for (size_t i = 0; i < elements.GetElementCount(currentView); i++) {
        NSDictionary *info = [self getSequenceElementAtIndex:(NSInteger)i];
        if (info) {
            NSMutableDictionary *infoWithIndex = [info mutableCopy];
            infoWithIndex[@"index"] = @(i);
            [result addObject:infoWithIndex];
        }
    }

    return result;
}

- (NSArray<NSDictionary *> *)getEffectsForElementAtIndex:(NSInteger)index layer:(NSInteger)layer {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return @[];
    }

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return @[];

    SequenceElements& elements = frame->GetSequenceElements();
    int currentView = elements.GetCurrentView();
    if (index < 0 || index >= (NSInteger)elements.GetElementCount(currentView)) {
        return @[];
    }

    Element* elem = elements.GetElement((size_t)index, currentView);
    if (!elem) return @[];

    if (layer < 0 || layer >= (NSInteger)elem->GetEffectLayerCount()) {
        return @[];
    }

    EffectLayer* effectLayer = elem->GetEffectLayer((int)layer);
    if (!effectLayer) return @[];

    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < effectLayer->GetEffectCount(); i++) {
        Effect* eff = effectLayer->GetEffect(i);
        if (!eff) continue;

        [result addObject:@{
            @"id": @(eff->GetID()),
            @"effectType": [NSString stringWithUTF8String:eff->GetEffectName().c_str()],
            @"effectIndex": @(eff->GetEffectIndex()),
            @"startTimeMS": @(eff->GetStartTimeMS()),
            @"endTimeMS": @(eff->GetEndTimeMS()),
            @"selected": @(eff->GetSelected()),
            @"protected": @(eff->IsLocked()),
        }];
    }

    return result;
}

#pragma mark - Effect Operations

- (NSArray<NSString *> *)getEffectTypes {
    [self ensureEngineInitialized];
    if (!_effectEngine) {
        NSLog(@"XLEngineBridge: Cannot get effect types - engine not available");
        return @[];
    }

    std::vector<xlEngine::EffectTypeInfo> types = _effectEngine->getEffectTypes();
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:types.size()];
    for (const auto &type : types) {
        [result addObject:[NSString stringWithUTF8String:type.name.c_str()]];
    }
    return result;
}

- (NSInteger)createEffect:(NSString *)modelName
                    layer:(NSInteger)layer
               effectType:(NSString *)effectType
               startTimeMS:(NSInteger)startMS
                 endTimeMS:(NSInteger)endMS {
    if (!modelName || !effectType) return -1;

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        NSLog(@"XLEngineBridge: Cannot create effect - engine not available");
        return -1;
    }

    std::string stdModel = [modelName UTF8String];
    std::string stdEffect = [effectType UTF8String];

    int effectId = _effectEngine->createEffect(stdModel, (int)layer, stdEffect, (int)startMS, (int)endMS);
    if (effectId < 0) {
        NSLog(@"XLEngineBridge: Failed to create effect %@ on %@", effectType, modelName);
    }
    return effectId;
}

- (BOOL)deleteEffect:(NSInteger)effectId {
    [self ensureEngineInitialized];
    if (!_effectEngine) {
        NSLog(@"XLEngineBridge: Cannot delete effect - engine not available");
        return NO;
    }

    bool result = _effectEngine->deleteEffect((int)effectId);
    if (!result) {
        NSLog(@"XLEngineBridge: Failed to delete effect %ld", (long)effectId);
    }
    return result ? YES : NO;
}

- (NSDictionary *)getEffect:(NSInteger)effectId {
    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return nil;
    }

    xlEngine::EffectInfo info;
    if (!_effectEngine->getEffect((int)effectId, info)) {
        return nil;
    }

    return [self dictFromEffectInfo:info];
}

- (NSDictionary *)getEffectTypeInfo:(NSString *)effectType {
    if (!effectType) return nil;

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return nil;
    }

    std::string stdType = [effectType UTF8String];
    xlEngine::EffectTypeInfo info;
    if (!_effectEngine->getEffectTypeInfo(stdType, info)) {
        return nil;
    }

    return @{
        @"id": @(info.id),
        @"name": [NSString stringWithUTF8String:info.name.c_str()],
        @"tooltip": [NSString stringWithUTF8String:info.tooltip.c_str()],
        @"canBeRandom": @(info.canBeRandom),
        @"canRenderPartialTime": @(info.canRenderPartialTime),
        @"maxColorCount": @(info.maxColorCount),
        @"appropriateOnNodes": @(info.appropriateOnNodes),
    };
}

- (NSArray<NSDictionary *> *)getEffectParameters:(NSString *)effectType {
    if (!effectType) return @[];

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return @[];
    }

    std::string stdType = [effectType UTF8String];
    std::vector<xlEngine::ParameterDefinition> params = _effectEngine->getEffectParameters(stdType);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:params.size()];
    for (const auto &param : params) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"key"] = [NSString stringWithUTF8String:param.key.c_str()];
        dict[@"displayLabel"] = [NSString stringWithUTF8String:param.displayLabel.c_str()];

        // Convert ParameterType enum to string to match Swift enum rawValue
        NSString *typeStr = @"string";
        switch (param.type) {
            case xlEngine::ParameterType::Int:
                typeStr = @"int";
                break;
            case xlEngine::ParameterType::Float:
                typeStr = @"float";
                break;
            case xlEngine::ParameterType::Bool:
                typeStr = @"bool";
                break;
            case xlEngine::ParameterType::String:
                typeStr = @"string";
                break;
            case xlEngine::ParameterType::Color:
                typeStr = @"color";
                break;
            case xlEngine::ParameterType::Choice:
                typeStr = @"choice";
                break;
            case xlEngine::ParameterType::File:
                typeStr = @"file";
                break;
            case xlEngine::ParameterType::ValueCurve:
                typeStr = @"valueCurve";
                break;
            case xlEngine::ParameterType::Font:
                typeStr = @"font";
                break;
            case xlEngine::ParameterType::ColorCurve:
                typeStr = @"colorCurve";
                break;
        }
        dict[@"type"] = typeStr;

        dict[@"group"] = [NSString stringWithUTF8String:param.group.c_str()];
        dict[@"minValue"] = @(param.minValue);
        dict[@"maxValue"] = @(param.maxValue);
        dict[@"defaultValue"] = [NSString stringWithFormat:@"%.2f", param.defaultValue];
        dict[@"supportsValueCurve"] = @(param.supportsValueCurve);

        NSMutableArray *choices = [NSMutableArray arrayWithCapacity:param.choices.size()];
        for (const auto &choice : param.choices) {
            [choices addObject:[NSString stringWithUTF8String:choice.c_str()]];
        }
        dict[@"choices"] = choices;

        [result addObject:dict];
    }
    return result;
}

- (BOOL)setEffectParameter:(NSInteger)effectId key:(NSString *)key value:(NSString *)value {
    if (!key || !value) return NO;

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return NO;
    }

    std::string stdKey = [key UTF8String];
    std::string stdValue = [value UTF8String];
    return _effectEngine->setEffectParameter((int)effectId, stdKey, stdValue) ? YES : NO;
}

- (NSString *)getEffectParameter:(NSInteger)effectId key:(NSString *)key {
    if (!key) return nil;

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return nil;
    }

    std::string stdKey = [key UTF8String];
    std::string value = _effectEngine->getEffectParameter((int)effectId, stdKey);
    return [NSString stringWithUTF8String:value.c_str()];
}

- (BOOL)setEffectSettings:(NSInteger)effectId settings:(NSString *)settings {
    if (!settings) return NO;

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return NO;
    }

    std::string stdSettings = [settings UTF8String];
    return _effectEngine->setEffectSettings((int)effectId, stdSettings) ? YES : NO;
}

- (NSString *)getEffectSettings:(NSInteger)effectId {
    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return nil;
    }

    std::string settings = _effectEngine->getEffectSettings((int)effectId);
    return [NSString stringWithUTF8String:settings.c_str()];
}

- (BOOL)setEffectPalette:(NSInteger)effectId palette:(NSString *)palette {
    if (!palette) return NO;

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return NO;
    }

    std::string stdPalette = [palette UTF8String];
    return _effectEngine->setEffectPalette((int)effectId, stdPalette) ? YES : NO;
}

- (NSString *)getEffectPalette:(NSInteger)effectId {
    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return nil;
    }

    std::string palette = _effectEngine->getEffectPalette((int)effectId);
    return [NSString stringWithUTF8String:palette.c_str()];
}

- (BOOL)moveEffect:(NSInteger)effectId startTimeMS:(NSInteger)startMS endTimeMS:(NSInteger)endMS {
    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return NO;
    }

    return _effectEngine->moveEffect((int)effectId, (int)startMS, (int)endMS) ? YES : NO;
}

- (NSArray<NSDictionary *> *)getEffectsForModel:(NSString *)modelName {
    if (!modelName) return @[];

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return @[];
    }

    std::string stdModel = [modelName UTF8String];
    std::vector<xlEngine::EffectInfo> effects = _effectEngine->getEffectsForModel(stdModel);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:effects.size()];
    for (const auto &info : effects) {
        [result addObject:[self dictFromEffectInfo:info]];
    }
    return result;
}

- (NSArray<NSDictionary *> *)getEffectsAtTime:(NSString *)modelName timeMS:(NSInteger)timeMS {
    if (!modelName) return @[];

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return @[];
    }

    std::string stdModel = [modelName UTF8String];
    std::vector<xlEngine::EffectInfo> effects = _effectEngine->getEffectsAtTime(stdModel, (int)timeMS);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:effects.size()];
    for (const auto &info : effects) {
        [result addObject:[self dictFromEffectInfo:info]];
    }
    return result;
}

- (NSArray<NSDictionary *> *)getEffectsForLayer:(NSString *)modelName layer:(NSInteger)layer {
    if (!modelName) return @[];

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return @[];
    }

    std::string stdModel = [modelName UTF8String];
    std::vector<xlEngine::EffectInfo> effects = _effectEngine->getEffectsForLayer(stdModel, (int)layer);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:effects.size()];
    for (const auto &info : effects) {
        [result addObject:[self dictFromEffectInfo:info]];
    }
    return result;
}

- (NSInteger)getLayerCount:(NSString *)modelName {
    if (!modelName) return 0;

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return 0;
    }

    std::string stdModel = [modelName UTF8String];
    return _effectEngine->getLayerCount(stdModel);
}

- (NSInteger)addLayer:(NSString *)modelName {
    if (!modelName) return -1;

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return -1;
    }

    std::string stdModel = [modelName UTF8String];
    return _effectEngine->addLayer(stdModel);
}

- (BOOL)removeLayer:(NSString *)modelName layer:(NSInteger)layer {
    if (!modelName) return NO;

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return NO;
    }

    std::string stdModel = [modelName UTF8String];
    return _effectEngine->removeLayer(stdModel, (int)layer) ? YES : NO;
}

- (BOOL)selectEffect:(NSInteger)effectId {
    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return NO;
    }

    return _effectEngine->selectEffect((int)effectId) ? YES : NO;
}

- (void)deselectAllEffects {
    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return;
    }

    _effectEngine->deselectAllEffects();
}

- (NSArray<NSNumber *> *)getSelectedEffectIds {
    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return @[];
    }

    std::vector<int> ids = _effectEngine->getSelectedEffectIds();
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:ids.size()];
    for (int effectId : ids) {
        [result addObject:@(effectId)];
    }
    return result;
}

- (BOOL)convertEffectType:(NSInteger)effectId newType:(NSString *)newType {
    if (!newType) return NO;

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return NO;
    }

    std::string stdType = [newType UTF8String];
    return _effectEngine->convertEffectType((int)effectId, stdType) ? YES : NO;
}

#pragma mark - Timing Track Operations

- (NSArray<NSDictionary *> *)getTimingTracks {
    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return @[];

    @try {
        SequenceElements& elements = frame->GetSequenceElements();
        int timingCount = elements.GetNumberOfTimingElements();

        NSMutableArray *result = [NSMutableArray arrayWithCapacity:timingCount];
        for (int i = 0; i < timingCount; i++) {
            TimingElement* te = elements.GetTimingElement(i);
            if (!te) continue;

            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[@"name"] = [NSString stringWithUTF8String:te->GetName().c_str()];
            info[@"layerCount"] = @(te->GetEffectLayerCount());
            info[@"isActive"] = @(te->GetActive());
            info[@"isFixed"] = @(te->IsFixedTiming());
            info[@"fixedInterval"] = @(te->GetFixedTiming());
            info[@"subType"] = [NSString stringWithUTF8String:te->GetSubType().c_str()];
            [result addObject:info];
        }
        return result;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception getting timing tracks: %@ - %@",
              exception.name, exception.reason);
        return @[];
    }
}

- (NSString *)getActiveTimingTrackName {
    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return nil;

    @try {
        SequenceElements& elements = frame->GetSequenceElements();
        int timingCount = elements.GetNumberOfTimingElements();

        for (int i = 0; i < timingCount; i++) {
            TimingElement* te = elements.GetTimingElement(i);
            if (te && te->GetActive()) {
                return [NSString stringWithUTF8String:te->GetName().c_str()];
            }
        }
        return nil;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception getting active timing track: %@ - %@",
              exception.name, exception.reason);
        return nil;
    }
}

- (BOOL)setActiveTimingTrack:(NSString *)trackName {
    if (!trackName) return NO;

    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return NO;

    @try {
        SequenceElements& elements = frame->GetSequenceElements();
        std::string stdName = [trackName UTF8String];

        // Deactivate all first
        elements.DeactivateAllTimingElements();

        // Find and activate the requested track
        TimingElement* te = elements.GetTimingElement(stdName);
        if (te) {
            te->SetActive(true);
            NSLog(@"XLEngineBridge: Activated timing track: %@", trackName);
            return YES;
        }
        NSLog(@"XLEngineBridge: Timing track not found: %@", trackName);
        return NO;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception setting active timing track: %@ - %@",
              exception.name, exception.reason);
        return NO;
    }
}

- (void)deactivateAllTimingTracks {
    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return;

    @try {
        SequenceElements& elements = frame->GetSequenceElements();
        elements.DeactivateAllTimingElements();
        NSLog(@"XLEngineBridge: Deactivated all timing tracks");
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception deactivating timing tracks: %@ - %@",
              exception.name, exception.reason);
    }
}

- (NSArray<NSDictionary *> *)getTimingMarks:(NSString *)trackName layer:(NSInteger)layer {
    if (!trackName) return @[];

    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return @[];

    @try {
        SequenceElements& elements = frame->GetSequenceElements();
        std::string stdName = [trackName UTF8String];

        TimingElement* te = elements.GetTimingElement(stdName);
        if (!te) {
            NSLog(@"XLEngineBridge: Timing track not found: %@", trackName);
            return @[];
        }

        if (layer < 0 || layer >= te->GetEffectLayerCount()) {
            NSLog(@"XLEngineBridge: Invalid layer %ld for timing track %@", (long)layer, trackName);
            return @[];
        }

        EffectLayer* el = te->GetEffectLayer((int)layer);
        if (!el) return @[];

        const std::vector<Effect*>& effects = el->GetEffects();
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:effects.size()];

        for (Effect* eff : effects) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[@"id"] = @(eff->GetID());
            info[@"startTimeMS"] = @(eff->GetStartTimeMS());
            info[@"endTimeMS"] = @(eff->GetEndTimeMS());

            // For timing marks, the "effect name" is the label
            std::string label = eff->GetEffectName();
            info[@"label"] = [NSString stringWithUTF8String:label.c_str()];

            [result addObject:info];
        }
        return result;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception getting timing marks: %@ - %@",
              exception.name, exception.reason);
        return @[];
    }
}

- (NSArray<NSNumber *> *)getActiveTimingMarkTimes {
    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return @[];

    @try {
        SequenceElements& elements = frame->GetSequenceElements();
        int timingCount = elements.GetNumberOfTimingElements();

        // Find the active timing track
        TimingElement* activeTe = nil;
        for (int i = 0; i < timingCount; i++) {
            TimingElement* te = elements.GetTimingElement(i);
            if (te && te->GetActive()) {
                activeTe = te;
                break;
            }
        }

        if (!activeTe) return @[];

        // Collect all timing mark start times from layer 0 (the main timing layer)
        EffectLayer* el = activeTe->GetEffectLayer(0);
        if (!el) return @[];

        const std::vector<Effect*>& effects = el->GetEffects();
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:effects.size() * 2];

        for (Effect* eff : effects) {
            // Add both start and end times for snap-to-grid
            [result addObject:@(eff->GetStartTimeMS())];
            // Only add end time if different from start
            if (eff->GetEndTimeMS() != eff->GetStartTimeMS()) {
                [result addObject:@(eff->GetEndTimeMS())];
            }
        }

        return result;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception getting active timing mark times: %@ - %@",
              exception.name, exception.reason);
        return @[];
    }
}

- (NSInteger)createTimingMark:(NSString *)trackName
                        layer:(NSInteger)layer
                  startTimeMS:(NSInteger)startTimeMS
                    endTimeMS:(NSInteger)endTimeMS
                        label:(NSString * _Nullable)label {
    if (!trackName) return -1;

    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return -1;

    @try {
        SequenceElements& elements = frame->GetSequenceElements();
        std::string stdName = [trackName UTF8String];

        TimingElement* te = elements.GetTimingElement(stdName);
        if (!te) {
            NSLog(@"XLEngineBridge: Timing track not found: %@", trackName);
            return -1;
        }

        if (layer < 0 || layer >= te->GetEffectLayerCount()) {
            NSLog(@"XLEngineBridge: Invalid layer %ld for timing track %@", (long)layer, trackName);
            return -1;
        }

        EffectLayer* el = te->GetEffectLayer((int)layer);
        if (!el) return -1;

        // For timing marks, the label is stored as the effect name
        std::string labelStr = label ? [label UTF8String] : "";

        // Create the timing mark (effect with empty settings and palette)
        Effect* eff = el->AddEffect(0, labelStr, "", "",
                                     (int)startTimeMS, (int)endTimeMS,
                                     EFFECT_NOT_SELECTED, false);

        if (eff) {
            NSLog(@"XLEngineBridge: Created timing mark '%s' at %ld-%ld ms",
                  labelStr.c_str(), (long)startTimeMS, (long)endTimeMS);
            return eff->GetID();
        }
        return -1;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception creating timing mark: %@ - %@",
              exception.name, exception.reason);
        return -1;
    }
}

- (BOOL)moveTimingMark:(NSInteger)markId startTimeMS:(NSInteger)startMS endTimeMS:(NSInteger)endMS {
    // Use the existing moveEffect method since timing marks are effects
    return [self moveEffect:markId startTimeMS:startMS endTimeMS:endMS];
}

- (BOOL)setTimingMarkLabel:(NSInteger)markId label:(NSString *)label {
    if (!label) return NO;

    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return NO;

    @try {
        SequenceElements& elements = frame->GetSequenceElements();

        // Find the effect across all timing elements
        int timingCount = elements.GetNumberOfTimingElements();
        for (int i = 0; i < timingCount; i++) {
            TimingElement* te = elements.GetTimingElement(i);
            if (!te) continue;

            for (int layerIdx = 0; layerIdx < te->GetEffectLayerCount(); layerIdx++) {
                EffectLayer* el = te->GetEffectLayer(layerIdx);
                if (!el) continue;

                Effect* eff = el->GetEffectFromID((int)markId);
                if (eff) {
                    std::string stdLabel = [label UTF8String];
                    eff->SetEffectName(stdLabel);
                    NSLog(@"XLEngineBridge: Set timing mark %ld label to '%@'", (long)markId, label);
                    return YES;
                }
            }
        }
        NSLog(@"XLEngineBridge: Timing mark not found: %ld", (long)markId);
        return NO;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception setting timing mark label: %@ - %@",
              exception.name, exception.reason);
        return NO;
    }
}

- (BOOL)deleteTimingMark:(NSInteger)markId {
    // Use the existing deleteEffect method since timing marks are effects
    return [self deleteEffect:markId];
}

- (NSDictionary *)getTimingMark:(NSInteger)markId {
    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return nil;

    @try {
        SequenceElements& elements = frame->GetSequenceElements();

        // Find the effect across all timing elements
        int timingCount = elements.GetNumberOfTimingElements();
        for (int i = 0; i < timingCount; i++) {
            TimingElement* te = elements.GetTimingElement(i);
            if (!te) continue;

            for (int layerIdx = 0; layerIdx < te->GetEffectLayerCount(); layerIdx++) {
                EffectLayer* el = te->GetEffectLayer(layerIdx);
                if (!el) continue;

                Effect* eff = el->GetEffectFromID((int)markId);
                if (eff) {
                    NSMutableDictionary *info = [NSMutableDictionary dictionary];
                    info[@"id"] = @(eff->GetID());
                    info[@"trackName"] = [NSString stringWithUTF8String:te->GetName().c_str()];
                    info[@"layer"] = @(layerIdx);
                    info[@"startTimeMS"] = @(eff->GetStartTimeMS());
                    info[@"endTimeMS"] = @(eff->GetEndTimeMS());
                    info[@"label"] = [NSString stringWithUTF8String:eff->GetEffectName().c_str()];
                    return info;
                }
            }
        }
        return nil;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception getting timing mark: %@ - %@",
              exception.name, exception.reason);
        return nil;
    }
}

- (BOOL)createTimingTrack:(NSString *)name {
    if (!name) return NO;

    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return NO;

    @try {
        std::string stdName = [name UTF8String];
        TimingElement* te = frame->AddTimingElement(stdName, "");
        if (te) {
            NSLog(@"XLEngineBridge: Created timing track: %@", name);
            return YES;
        }
        return NO;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception creating timing track: %@ - %@",
              exception.name, exception.reason);
        return NO;
    }
}

- (BOOL)deleteTimingTrack:(NSString *)name {
    if (!name) return NO;

    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return NO;

    @try {
        std::string stdName = [name UTF8String];
        frame->DeleteTimingElement(stdName);
        NSLog(@"XLEngineBridge: Deleted timing track: %@", name);
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception deleting timing track: %@ - %@",
              exception.name, exception.reason);
        return NO;
    }
}

- (BOOL)renameTimingTrack:(NSString *)oldName toName:(NSString *)newName {
    if (!oldName || !newName) return NO;

    [self ensureEngineInitialized];

    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return NO;

    @try {
        std::string stdOld = [oldName UTF8String];
        std::string stdNew = [newName UTF8String];
        frame->RenameTimingElement(stdOld, stdNew);
        NSLog(@"XLEngineBridge: Renamed timing track '%@' to '%@'", oldName, newName);
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception renaming timing track: %@ - %@",
              exception.name, exception.reason);
        return NO;
    }
}

#pragma mark - Audio Operations

- (NSString *)getMediaFilePath {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) return nil;

    @try {
        xLightsXmlFile* seqFile = xLightsFrame::CurrentSeqXmlFile;
        if (!seqFile) return nil;

        AudioManager* audio = seqFile->GetMedia();
        if (!audio) return nil;

        std::string filePath = audio->FileName();
        if (filePath.empty()) return nil;

        NSString *path = [NSString stringWithUTF8String:filePath.c_str()];

        // Verify the file exists
        if (path && ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSLog(@"XLEngineBridge: Media file path exists but file not found: %@", path);
            return nil;
        }

        return path;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception getting media file path: %@ - %@",
              exception.name, exception.reason);
        return nil;
    }
}

- (BOOL)isAudioLoaded {
    [self ensureEngineInitialized];

    xLightsXmlFile* seqFile = xLightsFrame::CurrentSeqXmlFile;
    if (!seqFile) return NO;

    AudioManager* audio = seqFile->GetMedia();
    return audio != nullptr && audio->IsOk();
}

- (NSDictionary *)getAudioInfo {
    [self ensureEngineInitialized];

    xLightsXmlFile* seqFile = xLightsFrame::CurrentSeqXmlFile;
    if (!seqFile) return nil;

    AudioManager* audio = seqFile->GetMedia();
    if (!audio || !audio->IsOk()) return nil;

    NSMutableDictionary *info = [NSMutableDictionary dictionary];

    info[@"filePath"] = [NSString stringWithUTF8String:audio->FileName().c_str()];
    info[@"durationMS"] = @(audio->LengthMS());
    info[@"sampleRate"] = @(audio->GetSampleRate());
    info[@"channels"] = @(audio->GetChannels());
    info[@"bitRate"] = @(audio->GetBitRate());
    info[@"title"] = [NSString stringWithUTF8String:audio->Title().c_str()];
    info[@"artist"] = [NSString stringWithUTF8String:audio->Artist().c_str()];
    info[@"album"] = [NSString stringWithUTF8String:audio->Album().c_str()];

    return info;
}

- (NSDictionary *)getAudioSamples:(NSInteger)startMS endMS:(NSInteger)endMS {
    [self ensureEngineInitialized];

    // Validate time range
    if (startMS < 0) startMS = 0;
    if (endMS <= startMS) {
        NSLog(@"XLEngineBridge: Invalid audio sample range: %ld to %ld", (long)startMS, (long)endMS);
        return nil;
    }

    @try {
        xLightsXmlFile* seqFile = xLightsFrame::CurrentSeqXmlFile;
        if (!seqFile) {
            NSLog(@"XLEngineBridge: No sequence file loaded for audio samples");
            return nil;
        }

        AudioManager* audio = seqFile->GetMedia();
        if (!audio || !audio->IsOk()) {
            // This is normal for sequences without audio - don't log as error
            return nil;
        }

        long sampleRate = audio->GetSampleRate();
        long trackSize = audio->GetTrackSize();
        int channels = audio->GetChannels();

        if (sampleRate <= 0 || trackSize <= 0) {
            NSLog(@"XLEngineBridge: Invalid audio format - sampleRate: %ld, trackSize: %ld",
                  sampleRate, trackSize);
            return nil;
        }

        // Convert milliseconds to sample offsets
        long startSample = (startMS * sampleRate) / 1000;
        long endSample = (endMS * sampleRate) / 1000;

        if (startSample < 0) startSample = 0;
        if (endSample > trackSize) endSample = trackSize;
        if (endSample <= startSample) return nil;

        long sampleCount = endSample - startSample;

        // Sanity check sample count to avoid huge allocations
        if (sampleCount > 10000000) {
            NSLog(@"XLEngineBridge: Requested sample count too large: %ld", sampleCount);
            return nil;
        }

        // Allocate output buffers
        NSMutableData *leftData = [NSMutableData dataWithLength:sampleCount * sizeof(float)];
        NSMutableData *rightData = [NSMutableData dataWithLength:sampleCount * sizeof(float)];

        if (!leftData || !rightData) {
            NSLog(@"XLEngineBridge: Failed to allocate audio sample buffers");
            return nil;
        }

        float *leftPtr = (float *)leftData.mutableBytes;
        float *rightPtr = (float *)rightData.mutableBytes;

        // Get audio data pointers
        float *rawLeft = audio->GetRawLeftDataPtr(startSample);
        float *rawRight = audio->GetRawRightDataPtr(startSample);

        if (rawLeft) {
            memcpy(leftPtr, rawLeft, sampleCount * sizeof(float));
        } else {
            // No left channel data - zero fill
            memset(leftPtr, 0, sampleCount * sizeof(float));
        }

        if (rawRight && channels >= 2) {
            memcpy(rightPtr, rawRight, sampleCount * sizeof(float));
        } else if (rawLeft) {
            // Mono - copy left to right
            memcpy(rightPtr, rawLeft, sampleCount * sizeof(float));
        } else {
            // No audio data - zero fill
            memset(rightPtr, 0, sampleCount * sizeof(float));
        }

        return @{
            @"leftChannel": leftData,
            @"rightChannel": rightData,
            @"sampleCount": @(sampleCount),
            @"sampleRate": @(sampleRate)
        };
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception getting audio samples: %@ - %@",
              exception.name, exception.reason);
        return nil;
    }
}

- (NSDictionary *)getAudioAmplitudeRange:(NSInteger)startMS endMS:(NSInteger)endMS {
    [self ensureEngineInitialized];

    xLightsXmlFile* seqFile = xLightsFrame::CurrentSeqXmlFile;
    if (!seqFile) return nil;

    AudioManager* audio = seqFile->GetMedia();
    if (!audio || !audio->IsOk()) return nil;

    long sampleRate = audio->GetSampleRate();
    long trackSize = audio->GetTrackSize();

    // Convert milliseconds to sample offsets
    long startSample = (startMS * sampleRate) / 1000;
    long endSample = (endMS * sampleRate) / 1000;

    if (startSample < 0) startSample = 0;
    if (endSample > trackSize) endSample = trackSize;
    if (endSample <= startSample) return nil;

    float minLeft = 0.0f, maxLeft = 0.0f;
    audio->GetLeftDataMinMax(startSample, endSample, minLeft, maxLeft);

    // For right channel, use left data if mono
    float minRight = minLeft, maxRight = maxLeft;
    if (audio->GetChannels() >= 2) {
        // AudioManager only provides GetLeftDataMinMax, so for right channel
        // we need to iterate manually or use the same data
        // For now, use the left channel data for both (most sequences are similar L/R)
        // A more complete implementation would add GetRightDataMinMax to AudioManager
    }

    return @{
        @"minLeft": @(minLeft),
        @"maxLeft": @(maxLeft),
        @"minRight": @(minRight),
        @"maxRight": @(maxRight)
    };
}

- (void)setAudioVolume:(NSInteger)volume {
    [self ensureEngineInitialized];

    xLightsXmlFile* seqFile = xLightsFrame::CurrentSeqXmlFile;
    if (!seqFile) return;

    AudioManager* audio = seqFile->GetMedia();
    if (audio) {
        audio->SetVolume((int)volume);
    }
}

- (NSInteger)getAudioVolume {
    [self ensureEngineInitialized];

    xLightsXmlFile* seqFile = xLightsFrame::CurrentSeqXmlFile;
    if (!seqFile) return 100;

    AudioManager* audio = seqFile->GetMedia();
    if (audio) {
        return audio->GetVolume();
    }
    return 100;
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

- (NSDictionary *)dictFromModelInfo:(const xlEngine::ModelInfo &)info {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    result[@"name"] = [NSString stringWithUTF8String:info.name.c_str()];
    result[@"type"] = [NSString stringWithUTF8String:info.type.c_str()];
    result[@"description"] = [NSString stringWithUTF8String:info.description.c_str()];
    result[@"nodeCount"] = @(info.nodeCount);
    result[@"channelCount"] = @(info.channelCount);
    result[@"startChannel"] = [NSString stringWithUTF8String:info.startChannel.c_str()];
    result[@"firstChannel"] = @(info.firstChannel);
    result[@"endChannel"] = @(info.lastChannel);
    result[@"defaultBufferWi"] = @(info.defaultBufferWi);
    result[@"defaultBufferHt"] = @(info.defaultBufferHt);
    result[@"layoutGroup"] = [NSString stringWithUTF8String:info.layoutGroup.c_str()];
    result[@"controllerName"] = [NSString stringWithUTF8String:info.controllerName.c_str()];
    result[@"protocol"] = [NSString stringWithUTF8String:info.controllerProtocol.c_str()];
    result[@"port"] = @(info.controllerPort);
    result[@"isActive"] = @(info.isActive);
    result[@"isGroupModel"] = @(info.isGroupModel);

    // Include all XML properties
    for (const auto &pair : info.properties) {
        NSString *key = [NSString stringWithUTF8String:pair.first.c_str()];
        NSString *value = [NSString stringWithUTF8String:pair.second.c_str()];
        if (result[key] == nil) {
            result[key] = value;
        }
    }

    return result;
}

- (NSDictionary *)dictFromControllerConfig:(const xlEngine::ControllerConfig &)config {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    result[@"name"] = [NSString stringWithUTF8String:config.name.c_str()];
    result[@"description"] = [NSString stringWithUTF8String:config.description.c_str()];
    result[@"id"] = @(config.id);

    // Controller type
    NSString *typeStr = @"Unknown";
    switch (config.type) {
        case xlEngine::ControllerType::Ethernet: typeStr = @"Ethernet"; break;
        case xlEngine::ControllerType::Serial: typeStr = @"Serial"; break;
        case xlEngine::ControllerType::Null: typeStr = @"Null"; break;
    }
    result[@"type"] = typeStr;

    result[@"ip"] = [NSString stringWithUTF8String:config.ip.c_str()];
    result[@"commPort"] = [NSString stringWithUTF8String:config.commPort.c_str()];
    result[@"baudRate"] = @(config.baudRate);
    result[@"protocol"] = [NSString stringWithUTF8String:config.protocol.c_str()];
    result[@"fppProxy"] = [NSString stringWithUTF8String:config.fppProxy.c_str()];
    result[@"forceLocalIP"] = [NSString stringWithUTF8String:config.forceLocalIP.c_str()];

    result[@"vendor"] = [NSString stringWithUTF8String:config.vendor.c_str()];
    result[@"model"] = [NSString stringWithUTF8String:config.model.c_str()];
    result[@"variant"] = [NSString stringWithUTF8String:config.variant.c_str()];

    // Active state
    NSString *activeStr = @"Active";
    switch (config.active) {
        case xlEngine::ActiveState::Active: activeStr = @"Active"; break;
        case xlEngine::ActiveState::Inactive: activeStr = @"Inactive"; break;
        case xlEngine::ActiveState::ActiveInXLightsOnly: activeStr = @"xLights Only"; break;
    }
    result[@"active"] = activeStr;

    result[@"autoLayout"] = @(config.autoLayout);
    result[@"autoSize"] = @(config.autoSize);
    result[@"autoUpload"] = @(config.autoUpload);
    result[@"fullxLightsControl"] = @(config.fullxLightsControl);
    result[@"defaultBrightness"] = @(config.defaultBrightness);
    result[@"defaultGamma"] = @(config.defaultGamma);
    result[@"suppressDuplicateFrames"] = @(config.suppressDuplicateFrames);
    result[@"monitor"] = @(config.monitor);
    result[@"managed"] = @(config.managed);

    result[@"startChannel"] = @(config.startChannel);
    result[@"endChannel"] = @(config.endChannel);
    result[@"channels"] = @(config.channels);
    result[@"outputCount"] = @(config.outputCount);

    return result;
}

- (NSArray<NSDictionary *> *)arrayFromPortConfigs:(const std::vector<xlEngine::PortConfig> &)ports {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:ports.size()];
    for (const auto &port : ports) {
        [result addObject:@{
            @"port": @(port.portNumber),
            @"protocol": [NSString stringWithUTF8String:port.protocol.c_str()],
            @"startChannel": @(port.startChannel),
            @"channelCount": @(port.channels),
            @"brightness": @(port.brightness),
            @"gamma": @(port.gamma),
            @"nullPixelsStart": @(port.nullPixels),
            @"nullPixelsEnd": @(port.endNullPixels),
            @"colorOrder": [NSString stringWithUTF8String:port.colorOrder.c_str()],
            @"groupCount": @(port.groupCount),
            @"reverse": @(port.reverse),
            @"zigZag": @(port.zigZag),
            @"smartRemoteType": [NSString stringWithUTF8String:port.smartRemoteType.c_str()],
        }];
    }
    return result;
}

- (NSDictionary *)dictFromControllerCapabilities:(const xlEngine::ControllerCapabilities &)caps {
    // Convert pixel protocols vector to NSArray
    NSMutableArray *pixelProtocols = [NSMutableArray arrayWithCapacity:caps.pixelProtocols.size()];
    for (const auto &proto : caps.pixelProtocols) {
        [pixelProtocols addObject:[NSString stringWithUTF8String:proto.c_str()]];
    }

    // Convert serial protocols vector to NSArray
    NSMutableArray *serialProtocols = [NSMutableArray arrayWithCapacity:caps.serialProtocols.size()];
    for (const auto &proto : caps.serialProtocols) {
        [serialProtocols addObject:[NSString stringWithUTF8String:proto.c_str()]];
    }

    // Convert input protocols vector to NSArray
    NSMutableArray *inputProtocols = [NSMutableArray arrayWithCapacity:caps.inputProtocols.size()];
    for (const auto &proto : caps.inputProtocols) {
        [inputProtocols addObject:[NSString stringWithUTF8String:proto.c_str()]];
    }

    return @{
        @"supportsUpload": @(caps.supportsUpload),
        @"supportsInputOnlyUpload": @(caps.supportsInputOnlyUpload),
        @"supportsAutoLayout": @(caps.supportsAutoLayout),
        @"supportsAutoUpload": @(caps.supportsAutoUpload),
        @"supportsAutoSize": @(caps.supportsAutoSize),
        @"supportsFullxLightsControl": @(caps.supportsFullxLightsControl),
        @"supportsPixelPortBrightness": @(caps.supportsPixelPortBrightness),
        @"supportsPixelPortGamma": @(caps.supportsPixelPortGamma),
        @"supportsDefaultBrightness": @(caps.supportsDefaultBrightness),
        @"supportsDefaultGamma": @(caps.supportsDefaultGamma),
        @"supportsSmartRemotes": @(caps.supportsSmartRemotes),
        @"supportsVirtualStrings": @(caps.supportsVirtualStrings),
        @"supportsUniversePerString": @(caps.supportsUniversePerString),
        @"supportsLEDPanelMatrix": @(caps.supportsLEDPanelMatrix),
        @"supportsVirtualMatrix": @(caps.supportsVirtualMatrix),
        @"maxPixelPorts": @(caps.maxPixelPort),
        @"maxSerialPorts": @(caps.maxSerialPort),
        @"maxPixelPortChannels": @(caps.maxPixelPortChannels),
        @"maxSerialPortChannels": @(caps.maxSerialPortChannels),
        @"maxInputE131Universes": @(caps.maxInputE131Universes),
        @"smartRemoteCount": @(caps.smartRemoteCount),
        @"pixelProtocols": pixelProtocols,
        @"serialProtocols": serialProtocols,
        @"inputProtocols": inputProtocols,
    };
}

- (NSDictionary *)dictFromDiscoveredController:(const xlEngine::DiscoveredController &)discovered {
    return @{
        @"ip": [NSString stringWithUTF8String:discovered.ip.c_str()],
        @"hostname": [NSString stringWithUTF8String:discovered.hostname.c_str()],
        @"vendor": [NSString stringWithUTF8String:discovered.vendor.c_str()],
        @"model": [NSString stringWithUTF8String:discovered.model.c_str()],
        @"variant": [NSString stringWithUTF8String:discovered.variant.c_str()],
        @"description": [NSString stringWithUTF8String:discovered.description.c_str()],
        @"version": [NSString stringWithUTF8String:discovered.version.c_str()],
        @"mode": [NSString stringWithUTF8String:discovered.mode.c_str()],
        @"platform": [NSString stringWithUTF8String:discovered.platform.c_str()],
        @"platformModel": [NSString stringWithUTF8String:discovered.platformModel.c_str()],
        @"uuid": [NSString stringWithUTF8String:discovered.uuid.c_str()],
        @"proxy": [NSString stringWithUTF8String:discovered.proxy.c_str()],
        @"majorVersion": @(discovered.majorVersion),
        @"minorVersion": @(discovered.minorVersion),
        @"patchVersion": @(discovered.patchVersion),
        @"alreadyConfigured": @(discovered.alreadyConfigured),
        @"existingName": [NSString stringWithUTF8String:discovered.existingName.c_str()],
    };
}

- (NSDictionary *)dictFromEffectInfo:(const xlEngine::EffectInfo &)info {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    result[@"id"] = @(info.id);
    result[@"effectType"] = [NSString stringWithUTF8String:info.effectType.c_str()];
    result[@"effectIndex"] = @(info.effectIndex);
    result[@"modelName"] = [NSString stringWithUTF8String:info.modelName.c_str()];
    result[@"layerIndex"] = @(info.layerIndex);
    result[@"startTimeMS"] = @(info.startTimeMS);
    result[@"endTimeMS"] = @(info.endTimeMS);
    result[@"isSelected"] = @(info.isSelected);
    result[@"isProtected"] = @(info.isProtected);
    result[@"isLocked"] = @(info.isLocked);
    result[@"isRenderDisabled"] = @(info.isRenderDisabled);

    // Convert settings map
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithCapacity:info.settings.size()];
    for (const auto &pair : info.settings) {
        NSString *key = [NSString stringWithUTF8String:pair.first.c_str()];
        NSString *value = [NSString stringWithUTF8String:pair.second.c_str()];
        settings[key] = value;
    }
    result[@"settings"] = settings;

    // Convert palette map
    NSMutableDictionary *palette = [NSMutableDictionary dictionaryWithCapacity:info.palette.size()];
    for (const auto &pair : info.palette) {
        NSString *key = [NSString stringWithUTF8String:pair.first.c_str()];
        NSString *value = [NSString stringWithUTF8String:pair.second.c_str()];
        palette[key] = value;
    }
    result[@"palette"] = palette;

    return result;
}

@end
