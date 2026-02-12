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
#import "effects/XLEffectPanelDefinitions.h"
#import "layout/XLORS5Parser.h"

// Include C++ engine headers
// During transition period, these will delegate to the existing xLightsFrame
#include "../engine/SequenceEngine.h"
#include "../engine/adapters/SequenceStateAdapter.h"
#include "../engine/ModelEngine.h"
#include "../engine/OutputEngine.h"
#include "../engine/RenderEngine.h"
#include "../engine/EffectEngine.h"

// Native providers for standalone operation (Phase 4: Decoupling)
#include "providers/NativeModelProvider.h"
#include "providers/NativeSequenceProvider.h"
#include "providers/NativeOutputProvider.h"
#include "providers/NativeEffectProvider.h"
#include "providers/NativeRenderProvider.h"

// Access to xLightsFrame singleton during transition period (legacy mode only)
#ifndef XLIGHTS_NATIVE
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
#else
// Forward declarations for types used in method signatures (native mode)
// These methods will return stub values in native mode
class xLightsFrame;
class xLightsApp { public: static xLightsFrame* GetFrame() { return nullptr; } };
class SequenceElements;
class SequenceViewManager;
class SequenceView;
class Element;
class ModelElement;
class TimingElement;
class EffectLayer;
class Effect;
class Model;
class ModelGroup;
class AudioManager;
class xLightsXmlFile;
enum class ElementType { ELEMENT_TYPE_TIMING, ELEMENT_TYPE_MODEL, ELEMENT_TYPE_SUBMODEL, ELEMENT_TYPE_STRAND };
#endif // XLIGHTS_NATIVE

#include <string>
#include <vector>
#include <map>
#include <unordered_map>
#include <memory>
#include <set>

// Static singleton instance for standalone mode
static XLEngineBridge *_sharedBridge = nil;

@implementation XLEngineBridge {
    // --- Native Providers (owned by bridge in standalone mode) ---
    // These are used when running without wxWidgets
    std::unique_ptr<xlEngine::NativeModelProvider> _nativeModelProvider;
    std::unique_ptr<xlEngine::NativeSequenceProvider> _nativeSequenceProvider;
    std::unique_ptr<xlEngine::NativeOutputProvider> _nativeOutputProvider;
    std::unique_ptr<xlEngine::NativeEffectProvider> _nativeEffectProvider;
    std::unique_ptr<xlEngine::NativeRenderProvider> _nativeRenderProvider;

    // --- Legacy Adapters (used when wrapping xLightsFrame) ---
    // These are used during transition period for hybrid operation
    std::unique_ptr<xlEngine::SequenceStateAdapter> _sequenceStateAdapter;
    std::unique_ptr<xlEngine::OutputManagerAdapter> _outputManagerAdapter;

    // --- Engine Instances ---
    // These are the actual engines that perform operations
    std::unique_ptr<xlEngine::SequenceEngine> _sequenceEngine;
    std::unique_ptr<xlEngine::ModelEngine> _modelEngine;
    std::unique_ptr<xlEngine::OutputEngine> _outputEngine;
    std::unique_ptr<xlEngine::EffectEngine> _effectEngine;
    std::unique_ptr<xlEngine::RenderEngine> _renderEngine;

    // --- State Tracking ---
    BOOL _engineInitialized;
    BOOL _standaloneMode;       // YES = using native providers, NO = using xLightsFrame
    BOOL _legacySupportEnabled; // YES = will fall back to xLightsFrame if available
    std::string _showFolderPath;

    // --- Native Mode View Selection ---
    NSInteger _currentViewIndex;  // 0 = Master View, 1+ = custom views

    // --- Native Mode Group Tracking ---
    std::set<std::string> _groupNames;  // Element names that are model groups

    // --- Layout Group Selection ---
    std::string _currentLayoutGroup;  // Currently active layout group name

    // --- Auto-Save ---
    dispatch_source_t _autoSaveTimer;
    dispatch_queue_t _autoSaveQueue;
}

#pragma mark - Lifecycle

+ (XLEngineBridge *)sharedBridge {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedBridge = [[XLEngineBridge alloc] init];
    });
    return _sharedBridge;
}

- (instancetype)init {
    // Default init creates standalone mode (native providers only)
    return [self initWithLegacySupport:NO];
}

- (instancetype)initWithLegacySupport:(BOOL)legacySupport {
    self = [super init];
    if (self) {
        _engineInitialized = NO;
        _standaloneMode = YES;  // Start in standalone mode
        _legacySupportEnabled = legacySupport;
        _showFolderPath = "";
        _currentLayoutGroup = "Default";
        _autoSaveQueue = dispatch_queue_create("org.xlights.autosave", DISPATCH_QUEUE_SERIAL);

        if (_legacySupportEnabled) {
            // In legacy mode, try to initialize with xLightsFrame if available
            [self ensureEngineInitialized];
        }
        // In pure standalone mode, wait for loadShowFolder: to be called

        if (_engineInitialized) {
            if (_standaloneMode) {
                NSLog(@"XLEngineBridge initialized in standalone mode with native providers");
            } else {
                NSLog(@"XLEngineBridge initialized in legacy mode with xLightsFrame");
            }
        } else {
            NSLog(@"XLEngineBridge initialized (waiting for show folder or xLightsFrame)");
        }
    }
    return self;
}

- (void)rebuildGroupNamesFromShowXML {
    _groupNames.clear();
    if (_showFolderPath.empty()) return;

    NSString* showFolder = [NSString stringWithUTF8String:_showFolderPath.c_str()];
    NSString* rgbPath = [showFolder stringByAppendingPathComponent:@"xlights_rgbeffects.xml"];
    NSData* xmlData = [NSData dataWithContentsOfFile:rgbPath];
    if (!xmlData) return;

    NSError* error = nil;
    NSXMLDocument* xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (!xmlDoc || error) return;

    NSArray<NSXMLElement*>* groupNodes =
        [xmlDoc.rootElement nodesForXPath:@"//modelGroups/modelGroup" error:nil];
    for (NSXMLElement* groupElem in groupNodes) {
        NSString* groupName = [[groupElem attributeForName:@"name"] stringValue];
        if (groupName) {
            _groupNames.insert([groupName UTF8String]);
        }
    }
}

- (void)ensureEngineInitialized {
    if (_engineInitialized) return;

#ifndef XLIGHTS_NATIVE
    // If legacy support is enabled, try xLightsFrame first
    if (_legacySupportEnabled) {
        xLightsFrame* frame = xLightsApp::GetFrame();
        if (frame) {
            @try {
                // Create legacy adapters that wrap xLightsFrame
                _sequenceStateAdapter = std::make_unique<xlEngine::SequenceStateAdapter>(frame);
                _outputManagerAdapter = std::make_unique<xlEngine::OutputManagerAdapter>(
                    frame->GetOutputManager(), frame);

                // Create engines using legacy adapters
                _sequenceEngine = std::make_unique<xlEngine::SequenceEngine>(_sequenceStateAdapter.get());
                _modelEngine = std::make_unique<xlEngine::ModelEngine>(frame->AllModels);
                _outputEngine = std::make_unique<xlEngine::OutputEngine>(_outputManagerAdapter.get());
                _effectEngine = std::make_unique<xlEngine::EffectEngine>(frame);
                _renderEngine = std::make_unique<xlEngine::RenderEngine>(frame);

                _standaloneMode = NO;  // Using legacy mode
                _engineInitialized = YES;
                NSLog(@"XLEngineBridge: Engines created with xLightsFrame (legacy mode)");
                return;
            } @catch (NSException *exception) {
                NSLog(@"XLEngineBridge: Exception during legacy initialization: %@ - %@",
                      exception.name, exception.reason);
                // Fall through to try standalone initialization
            }
        }
    }
#endif

    // Initialize in standalone mode
    // In native build, always initialize providers (show folder is optional)
    // In legacy build, only initialize if we have a show folder
#ifdef XLIGHTS_NATIVE
    [self initializeStandaloneProviders];
#else
    if (!_showFolderPath.empty()) {
        [self initializeStandaloneProviders];
    }
#endif
}

- (void)initializeStandaloneProviders {
    if (_engineInitialized) return;

    @try {
        // Create native providers (no wxWidgets dependencies)
        _nativeModelProvider = std::make_unique<xlEngine::NativeModelProvider>();
        _nativeSequenceProvider = std::make_unique<xlEngine::NativeSequenceProvider>();
        _nativeOutputProvider = std::make_unique<xlEngine::NativeOutputProvider>();
        _nativeEffectProvider = std::make_unique<xlEngine::NativeEffectProvider>();
        _nativeRenderProvider = std::make_unique<xlEngine::NativeRenderProvider>();

        // Populate effect types for the native provider
        // This list matches the known xLights effect types
        std::vector<std::string> effectTypes = {
            "Adjust", "Arpeggio", "Bars", "Butterfly", "Candle", "Circles",
            "ColorWash", "Curtain", "DMX", "Duplicate", "Faces", "Fan",
            "Fill", "Fire", "Fireworks", "Galaxy", "Garlands", "Glediator",
            "Guitar", "Kaleidoscope", "Life", "Lightning", "Lines", "Liquid",
            "Marquee", "Meteors", "Morph", "MovingHead", "Music", "Off", "On",
            "Piano", "Pictures", "Pinwheel", "Plasma", "Ripple", "Servo",
            "Shader", "Shape", "Shimmer", "Shockwave", "SingleStrand", "Sketch",
            "Snowflakes", "Snowstorm", "Spirals", "Spirograph", "State", "Strobe",
            "Tendril", "Text", "Tree", "Twinkle", "Video", "VUMeter", "Warp", "Wave"
        };
        _nativeEffectProvider->setEffectTypes(effectTypes);

        // Load data from show folder
        if (!_showFolderPath.empty()) {
            _nativeModelProvider->loadModelsFromShowFolder(_showFolderPath);

            // Load output configuration from xlights_networks.xml
            std::string networksPath = _showFolderPath + "/xlights_networks.xml";
            _nativeOutputProvider->loadFromXML(networksPath);
        }

        // Create engines with native providers
        _sequenceEngine = std::make_unique<xlEngine::SequenceEngine>(_nativeSequenceProvider.get());
        _modelEngine = std::make_unique<xlEngine::ModelEngine>(_nativeModelProvider.get());
        _outputEngine = std::make_unique<xlEngine::OutputEngine>(_nativeOutputProvider.get());
        _effectEngine = std::make_unique<xlEngine::EffectEngine>(_nativeEffectProvider.get());
        _renderEngine = std::make_unique<xlEngine::RenderEngine>(_nativeRenderProvider.get());

        // Give RenderEngine access to providers for rendering
        _renderEngine->setModelProvider(_nativeModelProvider.get());
        _renderEngine->setOutputProvider(_nativeOutputProvider.get());
        _renderEngine->setEffectProvider(_nativeEffectProvider.get());

        _standaloneMode = YES;
        _engineInitialized = YES;
        NSLog(@"XLEngineBridge: Engines created with native providers (standalone mode)");
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception during standalone initialization: %@ - %@",
              exception.name, exception.reason);
        _engineInitialized = NO;
    }
}

- (BOOL)isEngineAvailable {
    [self ensureEngineInitialized];
    return _engineInitialized;
}

- (BOOL)isStandaloneMode {
    return _standaloneMode;
}

- (BOOL)loadShowFolder:(NSString *)showFolderPath {
    if (!showFolderPath || showFolderPath.length == 0) {
        NSLog(@"XLEngineBridge: Cannot load show folder - path is nil or empty");
        return NO;
    }

    // Check if directory exists
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:showFolderPath isDirectory:&isDir] || !isDir) {
        NSLog(@"XLEngineBridge: Cannot load show folder - directory not found: %@", showFolderPath);
        return NO;
    }

    // Store the path
    _showFolderPath = [showFolderPath UTF8String];

    // If already initialized in legacy mode, we can't switch
    if (_engineInitialized && !_standaloneMode) {
        NSLog(@"XLEngineBridge: Already initialized in legacy mode - cannot switch to standalone");
        return NO;
    }

    // If already initialized in standalone mode, reload the data
    if (_engineInitialized && _standaloneMode) {
        @try {
            if (_nativeModelProvider) {
                _nativeModelProvider->loadModelsFromShowFolder(_showFolderPath);
            }
            if (_nativeOutputProvider) {
                std::string networksPath = _showFolderPath + "/xlights_networks.xml";
                _nativeOutputProvider->loadFromXML(networksPath);
            }
            NSLog(@"XLEngineBridge: Reloaded show folder: %@", showFolderPath);
            return YES;
        } @catch (NSException *exception) {
            NSLog(@"XLEngineBridge: Exception reloading show folder: %@ - %@",
                  exception.name, exception.reason);
            return NO;
        }
    }

    // Initialize standalone providers
    [self initializeStandaloneProviders];
    return _engineInitialized;
}

- (NSString *)getShowFolderPath {
    if (_showFolderPath.empty()) {
        return nil;
    }
    return [NSString stringWithUTF8String:_showFolderPath.c_str()];
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

        if (result) {
            // Load effects into the NativeEffectProvider so the inspector can access them
            if (_nativeEffectProvider) {
                bool effectsLoaded = _nativeEffectProvider->loadFromSequenceFile(stdPath);
                NSLog(@"XLEngineBridge: loadFromSequenceFile = %s", effectsLoaded ? "YES" : "NO");
            }

            // Update render provider and effect provider with sequence timing
            if (_nativeSequenceProvider) {
                int frameMSVal = _nativeSequenceProvider->getFrameMS();
                int durationMSVal = (int)(_nativeSequenceProvider->getSequenceDuration() * 1000.0);
                if (frameMSVal > 0 && durationMSVal > 0) {
                    if (_nativeRenderProvider) {
                        _nativeRenderProvider->setSequenceInfo(frameMSVal, durationMSVal);
                    }
                }
                // Sync duration to effect provider (may be longer than XML if audio is longer)
                if (_nativeEffectProvider && durationMSVal > 0) {
                    _nativeEffectProvider->setSequenceLengthMS(durationMSVal);
                }
            }

            // Build group name set from show XML for icon display
            [self rebuildGroupNamesFromShowXML];

            // Try to load the corresponding FSEQ file for playback rendering
            [self loadFSEQForSequence:path];
        }

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
        // Resolve save path
        std::string savePath = path ? [path UTF8String] : "";
        if (savePath.empty() && _nativeSequenceProvider) {
            savePath = _nativeSequenceProvider->getSequencePath();
        }
        if (savePath.empty()) {
            NSLog(@"XLEngineBridge: Cannot save sequence - no file path");
            return NO;
        }

        // Update the sequence provider's stored path
        if (_nativeSequenceProvider) {
            _nativeSequenceProvider->setSequencePath(savePath);
        }

        // Build metadata (includes audio stems) and write XML via effect provider
        auto meta = [self buildSequenceMetadata];
        NSLog(@"[STEMS] saveSequence: path=%s, meta.audioStems.size=%lu", savePath.c_str(), (unsigned long)meta.audioStems.size());
        bool result = _nativeEffectProvider->saveToSequenceFile(savePath, meta);
        NSLog(@"[STEMS] saveSequence: saveToSequenceFile result=%s", result ? "YES" : "NO");
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

    // Close any loaded FSEQ file
    if (_renderEngine) {
        _renderEngine->closeFSEQ();
    }

    bool result = _sequenceEngine->closeSequence();
    NSLog(@"XLEngineBridge: closeSequence() = %s", result ? "YES" : "NO");
    return result ? YES : NO;
}

- (void)loadFSEQForSequence:(NSString *)sequencePath {
    if (!_renderEngine || !sequencePath) return;

    // Derive FSEQ path from sequence path: replace .xLights extension with .fseq
    NSString *fseqPath = nil;
    NSString *ext = [sequencePath pathExtension];

    if ([ext caseInsensitiveCompare:@"xLights"] == NSOrderedSame ||
        [ext caseInsensitiveCompare:@"xml"] == NSOrderedSame) {
        fseqPath = [[sequencePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"fseq"];
    } else {
        // Try appending .fseq to the base name
        fseqPath = [sequencePath stringByAppendingString:@".fseq"];
    }

    // Check if the FSEQ file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:fseqPath]) {
        // Also try in the show folder
        if (!_showFolderPath.empty()) {
            NSString *filename = [[sequencePath lastPathComponent] stringByDeletingPathExtension];
            NSString *altPath = [NSString stringWithFormat:@"%s/%@.fseq",
                                 _showFolderPath.c_str(), filename];
            if ([[NSFileManager defaultManager] fileExistsAtPath:altPath]) {
                fseqPath = altPath;
            } else {
                NSLog(@"XLEngineBridge: No FSEQ file found for sequence: %@", sequencePath);
                NSLog(@"XLEngineBridge: Tried: %@ and %@", fseqPath, altPath);
                return;
            }
        } else {
            NSLog(@"XLEngineBridge: No FSEQ file found at: %@", fseqPath);
            return;
        }
    }

    std::string stdFseqPath = [fseqPath UTF8String];
    bool loaded = _renderEngine->loadFSEQ(stdFseqPath);

    if (loaded) {
        int numFrames = _renderEngine->getNumFrames();
        int stepTime = _renderEngine->getFrameTimeMS();
        NSLog(@"XLEngineBridge: Loaded FSEQ file: %@ (%d frames, %dms step time)",
              fseqPath, numFrames, stepTime);
    } else {
        NSLog(@"XLEngineBridge: Failed to load FSEQ file: %@", fseqPath);
    }
}

- (BOOL)isSequenceLoaded {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) {
        return NO;
    }

    return _sequenceEngine->isSequenceLoaded() ? YES : NO;
}

- (BOOL)createSequence:(NSString *)name
            durationMS:(NSInteger)durationMS
               frameMS:(NSInteger)frameMS
             mediaFile:(NSString * _Nullable)mediaFile {
    [self ensureEngineInitialized];

    std::string stdName = name ? [name UTF8String] : "New Sequence";
    std::string media = mediaFile ? [mediaFile UTF8String] : "";

#ifdef XLIGHTS_NATIVE
    if (!_nativeSequenceProvider) {
        NSLog(@"XLEngineBridge: Cannot create sequence - sequence provider not available");
        return NO;
    }

    @try {
        double durationSec = durationMS / 1000.0;
        int frameMSInt = (int)frameMS;

        bool created = _nativeSequenceProvider->createNewSequence(
            stdName, durationSec, frameMSInt, media, _showFolderPath);

        if (!created) {
            NSLog(@"XLEngineBridge: NativeSequenceProvider failed to create sequence");
            return NO;
        }

        // Initialize the effect provider with a default timing track, groups, and models.
        // Matches legacy AddAllModelsToSequence(): groups first, then individual models.
        if (_nativeEffectProvider) {
            _nativeEffectProvider->clear();
            // Use actual duration from sequence provider (may be updated from audio file)
            int actualDurationMS = (int)(_nativeSequenceProvider->getSequenceDuration() * 1000.0);
            if (actualDurationMS <= 0) actualDurationMS = (int)durationMS;
            _nativeEffectProvider->setSequenceLengthMS(actualDurationMS);

            // Add a default timing track
            size_t timingIdx = _nativeEffectProvider->addElement(
                "New Timing", xlEngine::SequenceElementType::Timing);
            if (timingIdx != SIZE_MAX) {
                _nativeEffectProvider->setTimingTrackActive("New Timing");
            }

            // Parse groups and models from the show XML (xlights_rgbeffects.xml)
            // to get the correct ordering: groups first, then individual models
            _groupNames.clear();
            size_t groupCount = 0;
            size_t modelCount = 0;
            if (!_showFolderPath.empty()) {
                NSString* showFolder = [NSString stringWithUTF8String:_showFolderPath.c_str()];
                NSString* rgbPath = [showFolder stringByAppendingPathComponent:@"xlights_rgbeffects.xml"];
                NSData* xmlData = [NSData dataWithContentsOfFile:rgbPath];
                if (xmlData) {
                    NSError* xmlError = nil;
                    NSXMLDocument* xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&xmlError];
                    if (xmlDoc && !xmlError) {
                        // Add groups first (matches legacy ordering)
                        NSArray<NSXMLElement*>* groupNodes =
                            [xmlDoc.rootElement nodesForXPath:@"//modelGroups/modelGroup" error:nil];
                        for (NSXMLElement* groupElem in groupNodes) {
                            NSString* groupName = [[groupElem attributeForName:@"name"] stringValue];
                            if (groupName) {
                                std::string stdName = [groupName UTF8String];
                                _nativeEffectProvider->addElement(
                                    stdName, xlEngine::SequenceElementType::Model);
                                _groupNames.insert(stdName);
                                groupCount++;
                            }
                        }

                        // Then add individual models
                        NSArray<NSXMLElement*>* modelNodes =
                            [xmlDoc.rootElement nodesForXPath:@"//models/model" error:nil];
                        for (NSXMLElement* modelElem in modelNodes) {
                            NSString* modelName = [[modelElem attributeForName:@"name"] stringValue];
                            if (modelName) {
                                _nativeEffectProvider->addElement(
                                    [modelName UTF8String], xlEngine::SequenceElementType::Model);
                                modelCount++;
                            }
                        }
                    }
                }
            }

            // Fallback: if XML parsing didn't work, use model provider names
            if (groupCount == 0 && modelCount == 0 && _nativeModelProvider) {
                auto modelNames = _nativeModelProvider->getModelNames();
                for (const auto& modelName : modelNames) {
                    _nativeEffectProvider->addElement(
                        modelName, xlEngine::SequenceElementType::Model);
                }
                modelCount = modelNames.size();
            }

            NSLog(@"XLEngineBridge: Added %lu groups + %lu models to new sequence",
                  (unsigned long)groupCount, (unsigned long)modelCount);
        }

        NSLog(@"XLEngineBridge: createSequence completed - name: %@, duration: %ldms, frameMS: %ldms, media: %@",
              name, (long)durationMS, (long)frameMS, mediaFile ?: @"(none)");

        // Update render provider with sequence timing so renderAll knows frame count
        if (_nativeRenderProvider) {
            _nativeRenderProvider->setSequenceInfo((int)frameMS, (int)durationMS);
        }

        // Auto-save: write the .xsq file immediately to the show folder
        if (!_showFolderPath.empty()) {
            NSString *showFolder = [NSString stringWithUTF8String:_showFolderPath.c_str()];
            NSString *baseName = [NSString stringWithUTF8String:stdName.c_str()];
            NSString *xsqFile = [showFolder stringByAppendingPathComponent:
                                 [baseName stringByAppendingString:@".xsq"]];

            // Avoid overwriting existing sequences — append (2), (3), etc.
            NSFileManager *fm = [NSFileManager defaultManager];
            if ([fm fileExistsAtPath:xsqFile]) {
                int suffix = 2;
                while (suffix < 1000) {
                    NSString *candidate = [showFolder stringByAppendingPathComponent:
                                           [NSString stringWithFormat:@"%@ (%d).xsq", baseName, suffix]];
                    if (![fm fileExistsAtPath:candidate]) {
                        xsqFile = candidate;
                        break;
                    }
                    suffix++;
                }
            }

            std::string xsqPath = [xsqFile UTF8String];
            _nativeSequenceProvider->setSequencePath(xsqPath);
            auto meta = [self buildSequenceMetadata];
            _nativeEffectProvider->saveToSequenceFile(xsqPath, meta);
            NSLog(@"XLEngineBridge: Auto-saved new sequence to %s", xsqPath.c_str());
        }

        return YES;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception creating sequence: %@ - %@",
              exception.name, exception.reason);
        return NO;
    }
#else
    if (_standaloneMode) {
        NSLog(@"XLEngineBridge: createSequence not yet supported in standalone mode");
        return NO;
    }

    // Legacy mode: use xLightsFrame
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) {
        NSLog(@"XLEngineBridge: Cannot create sequence - xLightsFrame not available");
        return NO;
    }

    @try {
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
#endif
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

        NSMutableDictionary *result = [@{
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
        } mutableCopy];

        // Include audio stem references from loaded sequence metadata
#ifdef XLIGHTS_NATIVE
        if (_nativeSequenceProvider) {
            auto metadata = _nativeSequenceProvider->getMetadata();
            NSLog(@"[STEMS] getSequenceInfo: provider metadata has %lu audioStems", (unsigned long)metadata.audioStems.size());
            if (!metadata.audioStems.empty()) {
                NSMutableArray *stemDicts = [NSMutableArray array];
                for (const auto& stem : metadata.audioStems) {
                    NSLog(@"[STEMS]   provider stem: name=%s, relativePath=%s", stem.name.c_str(), stem.relativePath.c_str());
                    [stemDicts addObject:@{
                        @"name": [NSString stringWithUTF8String:stem.name.c_str()],
                        @"relativePath": [NSString stringWithUTF8String:stem.relativePath.c_str()],
                        @"color": [NSString stringWithUTF8String:stem.color.c_str()],
                    }];
                }
                result[@"audioStems"] = stemDicts;
            }
        }
#endif

        return [result copy];
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception getting sequence info: %@ - %@",
              exception.name, exception.reason);
        return nil;
    }
}

- (BOOL)setSequenceInfo:(NSDictionary *)info {
    if (!info) return NO;
    [self ensureEngineInitialized];
#ifdef XLIGHTS_NATIVE
    if (_nativeSequenceProvider) {
        auto metadata = _nativeSequenceProvider->getMetadata();
        BOOL changed = NO;
        NSString *author = info[@"author"];
        if (author) { metadata.author = [author UTF8String]; changed = YES; }
        NSString *song = info[@"song"];
        if (song) { metadata.song = [song UTF8String]; changed = YES; }
        NSString *artist = info[@"artist"];
        if (artist) { metadata.artist = [artist UTF8String]; changed = YES; }
        if (changed) {
            NSLog(@"XLEngineBridge: setSequenceInfo updated native metadata");
            [self scheduleAutoSave];
        }
        return changed;
    }
    return NO;
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return NO;
    @try {
        xLightsXmlFile* xmlFile = xLightsFrame::CurrentSeqXmlFile;
        if (!xmlFile) return NO;
        BOOL changed = NO;
        NSString *v;
        v = info[@"author"];
        if (v) { xmlFile->SetHeaderInfo(HEADER_INFO_TYPES::AUTHOR, wxString([v UTF8String])); changed = YES; }
        v = info[@"song"];
        if (v) { xmlFile->SetHeaderInfo(HEADER_INFO_TYPES::SONG, wxString([v UTF8String])); changed = YES; }
        v = info[@"artist"];
        if (v) { xmlFile->SetHeaderInfo(HEADER_INFO_TYPES::ARTIST, wxString([v UTF8String])); changed = YES; }
        v = info[@"album"];
        if (v) { xmlFile->SetHeaderInfo(HEADER_INFO_TYPES::ALBUM, wxString([v UTF8String])); changed = YES; }
        v = info[@"comment"];
        if (v) { xmlFile->SetHeaderInfo(HEADER_INFO_TYPES::COMMENT, wxString([v UTF8String])); changed = YES; }
        if (changed) NSLog(@"XLEngineBridge: setSequenceInfo updated sequence metadata");
        return changed;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception in setSequenceInfo: %@", exception.reason);
        return NO;
    }
#endif
}

- (void)renderSequenceToFSEQ:(NSString *)sequencePath
                  outputPath:(NSString * _Nullable)outputPath
                  completion:(void (^)(BOOL success, NSString *message))completion {
    if (!sequencePath) {
        if (completion) completion(NO, @"No sequence path provided");
        return;
    }
    [self ensureEngineInitialized];
#ifdef XLIGHTS_NATIVE
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, @"Batch rendering requires the full effect rendering pipeline.");
        });
    }
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) { if (completion) completion(NO, @"Engine not available"); return; }
    NSString *seqPath = [sequencePath copy];
    NSString *outPath = [outputPath copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            BOOL loadOK = [self loadSequence:seqPath];
            if (!loadOK) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(NO, [NSString stringWithFormat:@"Failed to load: %@", seqPath.lastPathComponent]);
                });
                return;
            }
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            __block BOOL aborted = NO;
            if (_renderEngine) {
                _renderEngine->renderAll([&aborted, sem](bool cancelled) {
                    aborted = cancelled;
                    dispatch_semaphore_signal(sem);
                });
                dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            }
            if (aborted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(NO, [NSString stringWithFormat:@"Aborted: %@", seqPath.lastPathComponent]);
                });
                return;
            }
            NSString *savePath = outPath ?: seqPath;
            BOOL saveOK = [self saveSequence:savePath];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (saveOK)
                    completion(YES, [NSString stringWithFormat:@"Rendered: %@", seqPath.lastPathComponent]);
                else
                    completion(NO, [NSString stringWithFormat:@"Save failed: %@", seqPath.lastPathComponent]);
            });
        } @catch (NSException *exception) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, [NSString stringWithFormat:@"Error: %@", exception.reason]);
            });
        }
    });
#endif
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

    NSLog(@"XLEngineBridge: renderAll() — dispatching to background");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        self->_renderEngine->renderAll(nullptr);
        NSLog(@"XLEngineBridge: renderAll() — complete");

        // Export FSEQ file alongside the sequence
        if (self->_nativeSequenceProvider) {
            std::string seqPath = self->_nativeSequenceProvider->getSequencePath();
            if (!seqPath.empty()) {
                // Derive FSEQ path: replace .xLights extension with .fseq
                std::string fseqPath;
                auto dotPos = seqPath.rfind('.');
                if (dotPos != std::string::npos) {
                    fseqPath = seqPath.substr(0, dotPos) + ".fseq";
                } else {
                    fseqPath = seqPath + ".fseq";
                }
                bool exported = self->_renderEngine->exportRenderedFSEQ(fseqPath, 2);
                if (exported) {
                    NSLog(@"XLEngineBridge: Exported FSEQ to %s", fseqPath.c_str());
                } else {
                    NSLog(@"XLEngineBridge: Failed to export FSEQ (no rendered data or write error)");
                }
            }
        }
    });
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

- (NSArray<NSDictionary *> *)getAllFrameBuffers {
    [self ensureEngineInitialized];
    if (!_renderEngine) return @[];

    auto buffers = _renderEngine->getAllFrameBuffers();
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:buffers.size()];

    for (const auto& fb : buffers) {
        NSData *pixelData = [NSData dataWithBytes:fb.pixels.data() length:fb.pixels.size()];
        [result addObject:@{
            @"modelName": [NSString stringWithUTF8String:fb.modelName.c_str()],
            @"width": @(fb.width),
            @"height": @(fb.height),
            @"timeMS": @(fb.timeMS),
            @"pixels": pixelData,
        }];
    }

    return result;
}

- (NSDictionary *)getPrerenderedFrameBuffer:(NSString *)modelName timeMS:(NSInteger)timeMS {
    // TODO: Implement when RenderEngine supports getPrerenderedFrameBuffer
    // This requires Phase 7 engine modernization to expose pre-rendered frame data
    return nil;
}

- (NSArray<NSDictionary *> *)getNodeData:(NSString *)modelName {
    // TODO: Implement when RenderEngine supports getNodeData
    // This requires Phase 7 engine modernization to expose node channel data
    return @[];
}

- (BOOL)isRendering {
    [self ensureEngineInitialized];
    if (!_renderEngine) {
        return NO;
    }

    return _renderEngine->isRendering() ? YES : NO;
}

- (float)getRenderProgress {
    [self ensureEngineInitialized];
    if (!_renderEngine) {
        return 0.0f;
    }

    auto status = _renderEngine->getRenderStatus();
    return status.progressPercent / 100.0f;
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

- (NSString *)duplicateModelReturningName:(NSString *)modelName {
    if (!modelName) return nil;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot duplicate model - engine not available");
        return nil;
    }

    std::string stdName = [modelName UTF8String];
    if (!_modelEngine->hasModel(stdName)) {
        return nil;
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
        return nil;
    }
    return [NSString stringWithUTF8String:newName.c_str()];
}

#pragma mark - Replace Model

- (BOOL)replaceModel:(NSString *)targetModelName
            withModel:(NSString *)replacementModelName
              options:(NSDictionary *)options {
    if (!targetModelName || !replacementModelName) return NO;
    if ([targetModelName isEqualToString:replacementModelName]) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot replace model - engine not available");
        return NO;
    }

    std::string stdTarget = [targetModelName UTF8String];
    std::string stdReplacement = [replacementModelName UTF8String];

    if (!_modelEngine->hasModel(stdTarget) || !_modelEngine->hasModel(stdReplacement)) {
        NSLog(@"XLEngineBridge: replaceModel - one or both models not found");
        return NO;
    }

    BOOL copyStartChannel = [options[@"copyStartChannel"] boolValue];
    BOOL copyPosition = [options[@"copyPosition"] boolValue];
    BOOL mergeSubmodels = [options[@"mergeSubmodels"] boolValue];

    // 1. Copy start channel and controller assignment from target to replacement
    if (copyStartChannel) {
        NSString *startChannel = [self getModelProperty:targetModelName key:@"ModelStartChannel" defaultValue:@""];
        if (startChannel.length > 0) {
            [self updateModelProperty:replacementModelName key:@"ModelStartChannel" value:startChannel];
        }
        NSString *controllerName = [self getModelProperty:targetModelName key:@"Controller" defaultValue:@""];
        [self updateModelProperty:replacementModelName key:@"Controller" value:controllerName];
        NSString *controllerPort = [self getModelProperty:targetModelName key:@"ControllerPort" defaultValue:@""];
        [self updateModelProperty:replacementModelName key:@"ControllerPort" value:controllerPort];
        NSString *protocol = [self getModelProperty:targetModelName key:@"Protocol" defaultValue:@""];
        [self updateModelProperty:replacementModelName key:@"Protocol" value:protocol];

        NSInteger smartRemote = [self getSmartRemote:targetModelName];
        [self setSmartRemote:replacementModelName value:smartRemote];
        NSString *smartRemoteType = [self getSmartRemoteType:targetModelName];
        if (smartRemoteType.length > 0) {
            [self setSmartRemoteType:replacementModelName value:smartRemoteType];
        }
    }

    // 2. Copy position, size, and rotation from target to replacement
    if (copyPosition) {
        NSArray *positionKeys = @[@"WorldPosX", @"WorldPosY", @"WorldPosZ",
                                   @"ScaleX", @"ScaleY", @"ScaleZ",
                                   @"RotateX", @"RotateY", @"RotateZ"];
        for (NSString *key in positionKeys) {
            NSString *value = [self getModelProperty:targetModelName key:key defaultValue:@""];
            if (value.length > 0) {
                [self updateModelProperty:replacementModelName key:key value:value];
            }
        }
    }

    // 3. Merge submodels from target into replacement
    if (mergeSubmodels) {
        NSArray<NSDictionary *> *targetSubmodels = [self getSubmodels:targetModelName];
        for (NSDictionary *subInfo in targetSubmodels) {
            NSString *subName = subInfo[@"name"];
            if (!subName) continue;
            // Skip if replacement already has a submodel with this name
            if ([self hasSubmodel:replacementModelName submodelName:subName]) continue;

            NSDictionary *subDef = [self getSubmodelDefinition:targetModelName submodelName:subName];
            if (subDef) {
                [self setSubmodel:replacementModelName submodelName:subName definition:subDef];
            }
        }
    }

    // 4. Update group memberships: replace target with replacement in all groups
    NSArray<NSString *> *groups = [self getGroupsContainingModel:targetModelName];
    for (NSString *groupName in groups) {
        [self addModel:replacementModelName toGroup:groupName];
        [self removeModel:targetModelName fromGroup:groupName];
    }

    // 5. Rename: replacement takes the target's name
    //    First rename target to a temporary name, then rename replacement to target's name
    NSString *tempName = @"__xlights_replace_temp__";
    [self renameModel:targetModelName toName:tempName];
    [self renameModel:replacementModelName toName:targetModelName];

    // 6. Delete the old target model (now named tempName)
    [self deleteModel:tempName];

    NSLog(@"XLEngineBridge: Replaced model '%@' with '%@'", targetModelName, replacementModelName);
    return YES;
}

#pragma mark - Shadow Model Operations (stubs)

- (NSString *)createShadowModel:(NSString *)sourceModelName {
    if (!sourceModelName) return nil;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot create shadow model - engine not available");
        return nil;
    }

    std::string stdName = [sourceModelName UTF8String];
    if (!_modelEngine->hasModel(stdName)) {
        return nil;
    }

    xlEngine::ModelInfo info = _modelEngine->getModel(stdName);

    std::string newName = info.name + " Shadow";
    int counter = 1;
    while (_modelEngine->hasModel(newName)) {
        newName = info.name + " Shadow " + std::to_string(++counter);
    }

    std::map<std::string, std::string> props = info.properties;
    props["ShadowModelFor"] = info.name;

    auto itX = props.find("WorldPosX");
    if (itX != props.end()) {
        try {
            double x = std::stod(itX->second);
            props["WorldPosX"] = std::to_string(x + 50.0);
        } catch (...) {}
    }

    xlEngine::OperationResult result = _modelEngine->createModel(info.type, newName, props);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to create shadow model: %s", result.message.c_str());
        return nil;
    }
    return [NSString stringWithUTF8String:newName.c_str()];
}

- (BOOL)isShadowModel:(NSString *)modelName {
    if (!modelName) return NO;
    NSDictionary *props = [self getModelProperties:modelName];
    NSString *shadowFor = props[@"ShadowModelFor"];
    return (shadowFor && shadowFor.length > 0);
}

- (NSString *)getShadowModelFor:(NSString *)modelName {
    if (!modelName) return @"";
    NSDictionary *props = [self getModelProperties:modelName];
    NSString *shadowFor = props[@"ShadowModelFor"];
    return shadowFor ?: @"";
}

- (BOOL)setShadowModelFor:(NSString *)modelName target:(NSString *)targetModelName {
    if (!modelName) return NO;
    return [self updateModelProperty:modelName key:@"ShadowModelFor" value:(targetModelName ?: @"")];
}

- (NSArray<NSString *> *)getModelsShadowing:(NSString *)modelName {
    if (!modelName) return @[];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSArray<NSString *> *allModels = [self getModelNames];
    for (NSString *name in allModels) {
        NSString *target = [self getShadowModelFor:name];
        if ([target isEqualToString:modelName]) {
            [result addObject:name];
        }
    }
    return result;
}

- (NSDictionary *)getModelData:(NSString *)modelName {
    if (!modelName) return @{};

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot get model data - engine not available");
        return @{};
    }

    std::string stdName = [modelName UTF8String];
    if (!_modelEngine->hasModel(stdName)) {
        return @{};
    }

    xlEngine::ModelInfo info = _modelEngine->getModel(stdName);
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];

    data[@"name"] = [NSString stringWithUTF8String:info.name.c_str()];
    data[@"type"] = [NSString stringWithUTF8String:info.type.c_str()];

    // Convert properties map to NSDictionary
    NSMutableDictionary *props = [[NSMutableDictionary alloc] init];
    for (const auto& pair : info.properties) {
        NSString *key = [NSString stringWithUTF8String:pair.first.c_str()];
        NSString *value = [NSString stringWithUTF8String:pair.second.c_str()];
        props[key] = value;
    }
    data[@"properties"] = props;

    return data;
}

- (BOOL)createModelFromData:(NSDictionary *)modelData withName:(NSString *)modelName {
    if (!modelData || !modelName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot create model - engine not available");
        return NO;
    }

    NSString *type = modelData[@"type"];
    if (!type) {
        NSLog(@"XLEngineBridge: Cannot create model - missing type");
        return NO;
    }

    NSDictionary *props = modelData[@"properties"];
    std::map<std::string, std::string> stdProps;
    if (props) {
        for (NSString *key in props) {
            NSString *value = props[key];
            if (value) {
                stdProps[[key UTF8String]] = [value UTF8String];
            }
        }
    }

    std::string stdType = [type UTF8String];
    std::string stdName = [modelName UTF8String];

    xlEngine::OperationResult result = _modelEngine->createModel(stdType, stdName, stdProps);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to create model from data: %s", result.message.c_str());
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

- (NSString *)getModelProperty:(NSString *)modelName key:(NSString *)key {
    return [self getModelProperty:modelName key:key defaultValue:@""];
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

- (NSInteger)getSmartRemote:(NSString *)modelName {
    if (!modelName) return 0;
    [self ensureEngineInitialized];
    if (!_modelEngine) return 0;
    std::string stdName = [modelName UTF8String];
    return _modelEngine->getSmartRemote(stdName);
}

- (NSString *)getSmartRemoteType:(NSString *)modelName {
    if (!modelName) return @"";
    [self ensureEngineInitialized];
    if (!_modelEngine) return @"";
    std::string stdName = [modelName UTF8String];
    std::string type = _modelEngine->getSmartRemoteType(stdName);
    return [NSString stringWithUTF8String:type.c_str()];
}

- (BOOL)setSmartRemote:(NSString *)modelName value:(NSInteger)smartRemote {
    if (!modelName) return NO;
    [self ensureEngineInitialized];
    if (!_modelEngine) return NO;
    std::string stdName = [modelName UTF8String];
    xlEngine::OperationResult result = _modelEngine->setSmartRemote(stdName, (int)smartRemote);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to set smart remote: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)setSmartRemoteType:(NSString *)modelName value:(NSString *)type {
    if (!modelName || !type) return NO;
    [self ensureEngineInitialized];
    if (!_modelEngine) return NO;
    std::string stdName = [modelName UTF8String];
    std::string stdType = [type UTF8String];
    xlEngine::OperationResult result = _modelEngine->setSmartRemoteType(stdName, stdType);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to set smart remote type: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

#pragma mark - Dimming Curves

- (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)getDimmingInfo:(NSString *)modelName {
    if (!modelName) return @{};
    [self ensureEngineInitialized];
    if (!_modelEngine) return @{};

    std::string stdName = [modelName UTF8String];
    auto dimmingInfo = _modelEngine->getDimmingInfo(stdName);
    if (dimmingInfo.empty()) return @{};

    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:dimmingInfo.size()];
    for (const auto& channel : dimmingInfo) {
        NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:channel.second.size()];
        for (const auto& param : channel.second) {
            params[[NSString stringWithUTF8String:param.first.c_str()]] =
                [NSString stringWithUTF8String:param.second.c_str()];
        }
        result[[NSString stringWithUTF8String:channel.first.c_str()]] = params;
    }
    return result;
}

- (BOOL)setDimmingInfo:(NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)dimmingInfo
              forModel:(NSString *)modelName {
    if (!modelName) return NO;
    [self ensureEngineInitialized];
    if (!_modelEngine) return NO;

    std::string stdName = [modelName UTF8String];
    std::map<std::string, std::map<std::string, std::string>> stdInfo;

    if (dimmingInfo) {
        for (NSString *channelKey in dimmingInfo) {
            NSDictionary<NSString *, NSString *> *params = dimmingInfo[channelKey];
            std::map<std::string, std::string> stdParams;
            for (NSString *paramKey in params) {
                stdParams[[paramKey UTF8String]] = [params[paramKey] UTF8String];
            }
            stdInfo[[channelKey UTF8String]] = std::move(stdParams);
        }
    }

    xlEngine::OperationResult result = _modelEngine->setDimmingInfo(stdName, stdInfo);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to set dimming info: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
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

- (BOOL)createModelGroup:(NSString *)groupName withModels:(NSArray<NSString *> *)modelNames {
    if (!groupName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot create model group - engine not available");
        return NO;
    }

    std::string stdGroupName = [groupName UTF8String];
    std::vector<std::string> stdModelNames;
    if (modelNames) {
        stdModelNames.reserve(modelNames.count);
        for (NSString *name in modelNames) {
            stdModelNames.push_back([name UTF8String]);
        }
    }

    auto result = _modelEngine->createModelGroup(stdGroupName, stdModelNames);
    if (!result.success) {
        NSLog(@"XLEngineBridge: createModelGroup failed: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)deleteModelGroup:(NSString *)groupName {
    if (!groupName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot delete model group - engine not available");
        return NO;
    }

    std::string stdName = [groupName UTF8String];
    auto result = _modelEngine->deleteModelGroup(stdName);
    if (!result.success) {
        NSLog(@"XLEngineBridge: deleteModelGroup failed: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)renameModelGroup:(NSString *)oldName toName:(NSString *)newName {
    if (!oldName || !newName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot rename model group - engine not available");
        return NO;
    }

    std::string stdOldName = [oldName UTF8String];
    std::string stdNewName = [newName UTF8String];
    auto result = _modelEngine->renameModelGroup(stdOldName, stdNewName);
    if (!result.success) {
        NSLog(@"XLEngineBridge: renameModelGroup failed: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)addModel:(NSString *)modelName toGroup:(NSString *)groupName {
    if (!modelName || !groupName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot add model to group - engine not available");
        return NO;
    }

    std::string stdGroupName = [groupName UTF8String];
    std::string stdModelName = [modelName UTF8String];
    auto result = _modelEngine->addModelToGroup(stdGroupName, stdModelName);
    if (!result.success) {
        NSLog(@"XLEngineBridge: addModelToGroup failed: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)removeModel:(NSString *)modelName fromGroup:(NSString *)groupName {
    if (!modelName || !groupName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot remove model from group - engine not available");
        return NO;
    }

    std::string stdGroupName = [groupName UTF8String];
    std::string stdModelName = [modelName UTF8String];
    auto result = _modelEngine->removeModelFromGroup(stdGroupName, stdModelName);
    if (!result.success) {
        NSLog(@"XLEngineBridge: removeModelFromGroup failed: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
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

- (NSDictionary *)getSubmodelDefinition:(NSString *)modelName submodelName:(NSString *)submodelName {
    if (!modelName || !submodelName) return nil;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        return nil;
    }

    std::string stdModel = [modelName UTF8String];
    std::string stdSubmodel = [submodelName UTF8String];
    xlEngine::SubmodelDefinition def = _modelEngine->getSubmodelDefinition(stdModel, stdSubmodel);
    if (def.name.empty()) return nil;

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"name"] = [NSString stringWithUTF8String:def.name.c_str()];
    result[@"isRanges"] = @(def.isRanges);
    result[@"vertical"] = @(def.vertical);
    result[@"bufferStyle"] = [NSString stringWithUTF8String:def.bufferStyle.c_str()];
    result[@"subBuffer"] = [NSString stringWithUTF8String:def.subBuffer.c_str()];

    NSMutableArray *strands = [NSMutableArray arrayWithCapacity:def.strands.size()];
    for (const auto &strand : def.strands) {
        [strands addObject:[NSString stringWithUTF8String:strand.c_str()]];
    }
    result[@"strands"] = strands;

    return result;
}

- (BOOL)setSubmodel:(NSString *)modelName
       submodelName:(NSString *)submodelName
         definition:(NSDictionary *)definition {
    if (!modelName || !submodelName || !definition) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot set submodel - engine not available");
        return NO;
    }

    xlEngine::SubmodelDefinition def;
    def.name = [submodelName UTF8String];
    def.isRanges = [definition[@"isRanges"] boolValue];
    def.vertical = [definition[@"vertical"] boolValue];

    NSString *bufStyle = definition[@"bufferStyle"];
    def.bufferStyle = bufStyle ? [bufStyle UTF8String] : "Default";

    NSString *subBuf = definition[@"subBuffer"];
    def.subBuffer = subBuf ? [subBuf UTF8String] : "";

    NSArray *strands = definition[@"strands"];
    if (strands) {
        for (NSString *strand in strands) {
            def.strands.push_back([strand UTF8String]);
        }
    }

    std::string stdModel = [modelName UTF8String];
    std::string stdSubmodel = [submodelName UTF8String];
    xlEngine::OperationResult result = _modelEngine->setSubmodel(stdModel, stdSubmodel, def);
    if (!result.success) {
        NSLog(@"XLEngineBridge: setSubmodel failed: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)deleteSubmodel:(NSString *)modelName submodelName:(NSString *)submodelName {
    if (!modelName || !submodelName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot delete submodel - engine not available");
        return NO;
    }

    std::string stdModel = [modelName UTF8String];
    std::string stdSubmodel = [submodelName UTF8String];
    xlEngine::OperationResult result = _modelEngine->deleteSubmodel(stdModel, stdSubmodel);
    if (!result.success) {
        NSLog(@"XLEngineBridge: deleteSubmodel failed: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)renameSubmodel:(NSString *)modelName
               oldName:(NSString *)oldName
               newName:(NSString *)newName {
    if (!modelName || !oldName || !newName) return NO;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot rename submodel - engine not available");
        return NO;
    }

    std::string stdModel = [modelName UTF8String];
    std::string stdOld = [oldName UTF8String];
    std::string stdNew = [newName UTF8String];
    xlEngine::OperationResult result = _modelEngine->renameSubmodel(stdModel, stdOld, stdNew);
    if (!result.success) {
        NSLog(@"XLEngineBridge: renameSubmodel failed: %s", result.message.c_str());
    }
    return result.success ? YES : NO;
}

#pragma mark - Model Face Definitions

- (NSArray<NSString *> *)getFaceNames:(NSString *)modelName {
    if (!modelName) return @[];
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return @[];
    std::string stdName = [modelName UTF8String];
    std::vector<std::string> names = _nativeModelProvider->getFaceNames(stdName);
    return [self arrayFromVector:names];
}

- (NSDictionary *)getFaceDefinition:(NSString *)modelName faceName:(NSString *)faceName {
    if (!modelName || !faceName) return @{};
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return @{};
    std::string stdModel = [modelName UTF8String];
    std::string stdFace = [faceName UTF8String];
    std::map<std::string, std::string> def = _nativeModelProvider->getFaceDefinition(stdModel, stdFace);
    return [self dictFromMap:def];
}

- (NSDictionary<NSString *, NSDictionary *> *)getAllFaceDefinitions:(NSString *)modelName {
    if (!modelName) return @{};
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return @{};
    std::string stdName = [modelName UTF8String];
    auto allDefs = _nativeModelProvider->getAllFaceDefinitions(stdName);
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:allDefs.size()];
    for (const auto& pair : allDefs) {
        NSString *key = [NSString stringWithUTF8String:pair.first.c_str()];
        result[key] = [self dictFromMap:pair.second];
    }
    return result;
}

- (BOOL)setFaceDefinition:(NSString *)modelName
                  faceName:(NSString *)faceName
                definition:(NSDictionary *)definition {
    if (!modelName || !faceName || !definition) return NO;
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return NO;
    std::string stdModel = [modelName UTF8String];
    std::string stdFace = [faceName UTF8String];
    std::map<std::string, std::string> stdDef;
    for (NSString *key in definition) {
        NSString *value = [definition[key] description];
        if (value) {
            stdDef[[key UTF8String]] = [value UTF8String];
        }
    }
    return _nativeModelProvider->setFaceDefinition(stdModel, stdFace, stdDef) ? YES : NO;
}

- (BOOL)setAllFaceDefinitions:(NSString *)modelName
                  definitions:(NSDictionary<NSString *, NSDictionary *> *)definitions {
    if (!modelName || !definitions) return NO;
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return NO;
    std::string stdModel = [modelName UTF8String];
    std::map<std::string, std::map<std::string, std::string>> stdDefs;
    for (NSString *faceName in definitions) {
        NSDictionary *def = definitions[faceName];
        std::map<std::string, std::string> stdDef;
        for (NSString *key in def) {
            NSString *value = [def[key] description];
            if (value) {
                stdDef[[key UTF8String]] = [value UTF8String];
            }
        }
        stdDefs[[faceName UTF8String]] = std::move(stdDef);
    }
    return _nativeModelProvider->setAllFaceDefinitions(stdModel, stdDefs) ? YES : NO;
}

- (BOOL)deleteFaceDefinition:(NSString *)modelName faceName:(NSString *)faceName {
    if (!modelName || !faceName) return NO;
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return NO;
    std::string stdModel = [modelName UTF8String];
    std::string stdFace = [faceName UTF8String];
    return _nativeModelProvider->deleteFaceDefinition(stdModel, stdFace) ? YES : NO;
}

- (BOOL)renameFaceDefinition:(NSString *)modelName
                     oldName:(NSString *)oldName
                     newName:(NSString *)newName {
    if (!modelName || !oldName || !newName) return NO;
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return NO;
    std::string stdModel = [modelName UTF8String];
    std::string stdOld = [oldName UTF8String];
    std::string stdNew = [newName UTF8String];
    return _nativeModelProvider->renameFaceDefinition(stdModel, stdOld, stdNew) ? YES : NO;
}

#pragma mark - Model State Definitions

- (NSArray<NSString *> *)getStateNames:(NSString *)modelName {
    if (!modelName) return @[];
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return @[];
    std::string stdName = [modelName UTF8String];
    std::vector<std::string> names = _nativeModelProvider->getStateNames(stdName);
    return [self arrayFromVector:names];
}

- (NSDictionary *)getStateDefinition:(NSString *)modelName stateName:(NSString *)stateName {
    if (!modelName || !stateName) return @{};
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return @{};
    std::string stdModel = [modelName UTF8String];
    std::string stdState = [stateName UTF8String];
    std::map<std::string, std::string> def = _nativeModelProvider->getStateDefinition(stdModel, stdState);
    return [self dictFromMap:def];
}

- (NSDictionary<NSString *, NSDictionary *> *)getAllStateDefinitions:(NSString *)modelName {
    if (!modelName) return @{};
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return @{};
    std::string stdName = [modelName UTF8String];
    auto allDefs = _nativeModelProvider->getAllStateDefinitions(stdName);
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:allDefs.size()];
    for (const auto& pair : allDefs) {
        NSString *key = [NSString stringWithUTF8String:pair.first.c_str()];
        result[key] = [self dictFromMap:pair.second];
    }
    return result;
}

- (BOOL)setStateDefinition:(NSString *)modelName
                  stateName:(NSString *)stateName
                 definition:(NSDictionary *)definition {
    if (!modelName || !stateName || !definition) return NO;
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return NO;
    std::string stdModel = [modelName UTF8String];
    std::string stdState = [stateName UTF8String];
    std::map<std::string, std::string> stdDef;
    for (NSString *key in definition) {
        NSString *value = definition[key];
        if (value) {
            stdDef[[key UTF8String]] = [value UTF8String];
        }
    }
    return _nativeModelProvider->setStateDefinition(stdModel, stdState, stdDef) ? YES : NO;
}

- (BOOL)setAllStateDefinitions:(NSString *)modelName
                    definitions:(NSDictionary<NSString *, NSDictionary *> *)definitions {
    if (!modelName || !definitions) return NO;
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return NO;
    std::string stdModel = [modelName UTF8String];
    std::map<std::string, std::map<std::string, std::string>> stdDefs;
    for (NSString *stateName in definitions) {
        NSDictionary *def = definitions[stateName];
        std::map<std::string, std::string> stdDef;
        for (NSString *key in def) {
            NSString *value = def[key];
            if (value) {
                stdDef[[key UTF8String]] = [value UTF8String];
            }
        }
        stdDefs[[stateName UTF8String]] = std::move(stdDef);
    }
    return _nativeModelProvider->setAllStateDefinitions(stdModel, stdDefs) ? YES : NO;
}

- (BOOL)deleteStateDefinition:(NSString *)modelName stateName:(NSString *)stateName {
    if (!modelName || !stateName) return NO;
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return NO;
    std::string stdModel = [modelName UTF8String];
    std::string stdState = [stateName UTF8String];
    return _nativeModelProvider->deleteStateDefinition(stdModel, stdState) ? YES : NO;
}

- (BOOL)renameStateDefinition:(NSString *)modelName
                      oldName:(NSString *)oldName
                      newName:(NSString *)newName {
    if (!modelName || !oldName || !newName) return NO;
    [self ensureEngineInitialized];
    if (!_nativeModelProvider) return NO;
    std::string stdModel = [modelName UTF8String];
    std::string stdOld = [oldName UTF8String];
    std::string stdNew = [newName UTF8String];
    return _nativeModelProvider->renameStateDefinition(stdModel, stdOld, stdNew) ? YES : NO;
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

/// Map an .xmodel XML root element name to a user-facing model type string.
/// Traditional .xmodel files use the element name as the model type indicator.
+ (NSString *)modelTypeFromXMLElementName:(NSString *)elementName {
    static NSDictionary<NSString *, NSString *> *typeMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        typeMap = @{
            @"custommodel":    @"Custom",
            @"matrixmodel":    @"Matrix",
            @"treemodel":      @"Tree",
            @"archesmodel":    @"Arches",
            @"starmodel":      @"Star",
            @"polylinemodel":  @"Poly Line",
            @"multipointmodel":@"MultiPoint",
            @"circlemodel":    @"Circle",
            @"spheremodel":    @"Sphere",
            @"iciclemodel":    @"Icicles",
            @"Cubemodel":      @"Cube",
            @"dmxmodel":       @"DMX",
            @"dmxgeneral":     @"DmxGeneral",
            @"dmxservo":       @"DmxServo",
            @"dmxservo3axis":  @"DmxServo3d",
            @"dmxservo3d":     @"DmxServo3d",
        };
    });
    NSString *type = typeMap[elementName];
    if (!type) {
        // Check case-insensitive for element names like "Cubemodel"
        NSString *lower = [elementName lowercaseString];
        for (NSString *key in typeMap) {
            if ([[key lowercaseString] isEqualToString:lower]) {
                return typeMap[key];
            }
        }
    }
    return type ?: elementName;
}

/// Extract all XML attributes from an NSXMLElement as a dictionary.
+ (NSDictionary<NSString *, NSString *> *)attributesFromXMLElement:(NSXMLElement *)element {
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    for (NSXMLNode *attr in [element attributes]) {
        NSString *name = [attr name];
        NSString *value = [attr stringValue];
        if (name && value) {
            attrs[name] = value;
        }
    }
    return attrs;
}

/// Estimate channel count from model XML attributes.
/// Uses parm1 (width/nodes-per-string), parm2 (height/strings), and StringType.
+ (NSInteger)estimateChannelCountFromAttributes:(NSDictionary<NSString *, NSString *> *)attrs {
    NSInteger parm1 = [attrs[@"parm1"] integerValue];
    NSInteger parm2 = [attrs[@"parm2"] integerValue];
    if (parm1 <= 0) parm1 = 1;
    if (parm2 <= 0) parm2 = 1;

    NSInteger nodeCount = parm1 * parm2;

    NSString *stringType = attrs[@"StringType"];
    NSInteger channelsPerNode = 3; // default RGB
    if (stringType) {
        NSString *lower = [stringType lowercaseString];
        if ([lower containsString:@"single"]) {
            channelsPerNode = 1;
        } else if ([lower containsString:@"4"]) {
            channelsPerNode = 4; // RGBW
        }
    }

    return nodeCount * channelsPerNode;
}

/// Parse models from an .xmodel file (single model, traditional or XmlSerializer format).
/// Returns array of model info dictionaries.
- (NSArray<NSDictionary *> *)parseXModelFile:(NSString *)filePath {
    NSData *xmlData = [NSData dataWithContentsOfFile:filePath];
    if (!xmlData) {
        NSLog(@"XLEngineBridge: Cannot read file: %@", filePath);
        return @[];
    }

    NSError *error = nil;
    NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (!xmlDoc || error) {
        NSLog(@"XLEngineBridge: Failed to parse XML from %@: %@", filePath, error.localizedDescription);
        return @[];
    }

    NSXMLElement *root = [xmlDoc rootElement];
    if (!root) return @[];

    NSString *rootName = [root name];
    NSMutableArray<NSDictionary *> *models = [NSMutableArray array];

    // Check for XmlSerializer format: <models type="exported">
    if ([rootName isEqualToString:@"models"]) {
        NSString *typeAttr = [[root attributeForName:@"type"] stringValue];
        if ([typeAttr isEqualToString:@"exported"]) {
            // New serializer format: iterate <model> children
            for (NSXMLElement *child in [root children]) {
                if (![[child name] isEqualToString:@"model"]) continue;

                NSString *name = [[child attributeForName:@"name"] stringValue] ?: @"Unknown";
                NSString *displayAs = [[child attributeForName:@"DisplayAs"] stringValue] ?: @"Unknown";
                NSDictionary *attrs = [XLEngineBridge attributesFromXMLElement:child];
                NSInteger channels = [XLEngineBridge estimateChannelCountFromAttributes:attrs];

                [models addObject:@{
                    @"name": name,
                    @"type": displayAs,
                    @"channels": @(channels),
                }];
            }
            return models;
        }
        // Could also be an rgbeffects-style models container
        for (NSXMLElement *child in [root children]) {
            NSString *childName = [child name];
            if ([childName isEqualToString:@"model"] || [childName isEqualToString:@"modelGroup"]) {
                NSString *name = [[child attributeForName:@"name"] stringValue] ?: @"Unknown";
                NSString *displayAs = [[child attributeForName:@"DisplayAs"] stringValue] ?: childName;
                NSDictionary *attrs = [XLEngineBridge attributesFromXMLElement:child];
                NSInteger channels = [XLEngineBridge estimateChannelCountFromAttributes:attrs];
                [models addObject:@{
                    @"name": name,
                    @"type": displayAs,
                    @"channels": @(channels),
                }];
            }
        }
        if (models.count > 0) return models;
    }

    // Traditional .xmodel format: root element IS the model (e.g. <custommodel name="...">)
    NSString *name = [[root attributeForName:@"name"] stringValue] ?: @"Unknown";
    NSString *type = [XLEngineBridge modelTypeFromXMLElementName:rootName];
    NSDictionary *attrs = [XLEngineBridge attributesFromXMLElement:root];
    NSInteger channels = [XLEngineBridge estimateChannelCountFromAttributes:attrs];

    [models addObject:@{
        @"name": name,
        @"type": type,
        @"channels": @(channels),
    }];

    return models;
}

/// Parse models from an .xlights sequence or layout XML file.
/// Looks for model definitions within the XML structure.
- (NSArray<NSDictionary *> *)parseXLightsLayoutFile:(NSString *)filePath {
    NSData *xmlData = [NSData dataWithContentsOfFile:filePath];
    if (!xmlData) return @[];

    NSError *error = nil;
    NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (!xmlDoc || error) {
        NSLog(@"XLEngineBridge: Failed to parse layout XML from %@: %@", filePath, error.localizedDescription);
        return @[];
    }

    NSMutableArray<NSDictionary *> *models = [NSMutableArray array];

    // Search for model elements in common locations:
    // rgbeffects.xml: //models/model
    // sequence files may also contain model references
    NSArray<NSString *> *xpaths = @[
        @"//models/model",
        @"//model",
    ];

    NSMutableSet<NSString *> *seenNames = [NSMutableSet set];

    for (NSString *xpath in xpaths) {
        NSArray<NSXMLNode *> *nodes = [[xmlDoc rootElement] nodesForXPath:xpath error:nil];
        for (NSXMLNode *node in nodes) {
            if (![node isKindOfClass:[NSXMLElement class]]) continue;
            NSXMLElement *elem = (NSXMLElement *)node;

            NSString *name = [[elem attributeForName:@"name"] stringValue];
            if (!name || [seenNames containsObject:name]) continue;
            [seenNames addObject:name];

            NSString *displayAs = [[elem attributeForName:@"DisplayAs"] stringValue] ?: @"Unknown";
            NSDictionary *attrs = [XLEngineBridge attributesFromXMLElement:elem];
            NSInteger channels = [XLEngineBridge estimateChannelCountFromAttributes:attrs];

            [models addObject:@{
                @"name": name,
                @"type": displayAs,
                @"channels": @(channels),
            }];
        }
        if (models.count > 0) break;
    }

    return models;
}

/// Import a model from its XML attributes into the engine via createModel.
/// Extracts all XML attributes and child elements (submodels, faces, states).
- (BOOL)importModelFromXMLElement:(NSXMLElement *)element
                        modelType:(NSString *)modelType
                     originalName:(NSString *)originalName {
    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot import model - engine not available");
        return NO;
    }

    // Build properties map from all XML attributes
    std::map<std::string, std::string> props;
    for (NSXMLNode *attr in [element attributes]) {
        NSString *attrName = [attr name];
        NSString *attrValue = [attr stringValue];
        if (attrName && attrValue) {
            // Skip name - we'll set it separately to allow deconfliction
            if ([attrName isEqualToString:@"name"]) continue;
            props[[attrName UTF8String]] = [attrValue UTF8String];
        }
    }

    // Collect child element data (submodels, faceInfo, stateInfo, etc.)
    // Serialize child elements as XML strings so the model engine can reconstruct them
    for (NSXMLElement *child in [element children]) {
        NSString *childName = [child name];
        if (!childName) continue;

        if ([childName isEqualToString:@"subModel"] ||
            [childName isEqualToString:@"faceInfo"] ||
            [childName isEqualToString:@"stateInfo"] ||
            [childName isEqualToString:@"Aliases"] ||
            [childName isEqualToString:@"ControllerConnection"] ||
            [childName isEqualToString:@"dimensions"]) {
            // Store serialized child XML so the engine can reconstruct it
            NSString *key = [NSString stringWithFormat:@"__child_%@_%lu", childName, (unsigned long)[element childCount]];
            NSString *xmlStr = [child XMLString];
            if (xmlStr) {
                props[[key UTF8String]] = [xmlStr UTF8String];
            }
        }
    }

    // Generate a unique name via the model engine
    std::string baseName = [originalName UTF8String];
    std::string stdType = [modelType UTF8String];

    // Check if name is taken and generate unique one
    std::string finalName = baseName;
    int suffix = 2;
    while (_modelEngine->hasModel(finalName)) {
        finalName = baseName + "-" + std::to_string(suffix);
        suffix++;
    }

    xlEngine::OperationResult result = _modelEngine->createModel(stdType, finalName, props);
    if (!result.success) {
        NSLog(@"XLEngineBridge: Failed to import model '%s' as type '%s': %s",
              finalName.c_str(), stdType.c_str(), result.message.c_str());
    } else {
        NSLog(@"XLEngineBridge: Imported model '%s' (type: %s)", finalName.c_str(), stdType.c_str());
    }
    return result.success ? YES : NO;
}

- (BOOL)importModelFromFile:(NSString *)filePath {
    if (!filePath) return NO;

    NSData *xmlData = [NSData dataWithContentsOfFile:filePath];
    if (!xmlData) {
        NSLog(@"XLEngineBridge: Cannot read model file: %@", filePath);
        return NO;
    }

    NSError *error = nil;
    NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (!xmlDoc || error) {
        NSLog(@"XLEngineBridge: Failed to parse model XML from %@: %@", filePath, error.localizedDescription);
        return NO;
    }

    NSXMLElement *root = [xmlDoc rootElement];
    if (!root) return NO;

    NSString *rootName = [root name];

    // XmlSerializer format: <models type="exported"><model .../>...</models>
    if ([rootName isEqualToString:@"models"]) {
        NSString *typeAttr = [[root attributeForName:@"type"] stringValue];
        if ([typeAttr isEqualToString:@"exported"]) {
            BOOL anySuccess = NO;
            for (NSXMLElement *child in [root children]) {
                if (![[child name] isEqualToString:@"model"]) continue;
                NSString *name = [[child attributeForName:@"name"] stringValue] ?: @"Imported Model";
                NSString *displayAs = [[child attributeForName:@"DisplayAs"] stringValue] ?: @"Custom";
                if ([self importModelFromXMLElement:child modelType:displayAs originalName:name]) {
                    anySuccess = YES;
                }
            }
            return anySuccess;
        }
    }

    // Traditional .xmodel format: root element IS the model
    NSString *name = [[root attributeForName:@"name"] stringValue] ?: @"Imported Model";
    NSString *type = [XLEngineBridge modelTypeFromXMLElementName:rootName];

    return [self importModelFromXMLElement:root modelType:type originalName:name];
}

- (BOOL)importModelFromFile:(NSString *)filePath modelName:(NSString *)modelName {
    if (!filePath || !modelName) return NO;

    NSString *extension = [[filePath pathExtension] lowercaseString];

    NSData *xmlData = [NSData dataWithContentsOfFile:filePath];
    if (!xmlData) {
        NSLog(@"XLEngineBridge: Cannot read file: %@", filePath);
        return NO;
    }

    NSError *error = nil;
    NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (!xmlDoc || error) {
        NSLog(@"XLEngineBridge: Failed to parse XML from %@: %@", filePath, error.localizedDescription);
        return NO;
    }

    NSXMLElement *root = [xmlDoc rootElement];
    if (!root) return NO;

    // For .xmodel files, check if the single model matches the requested name
    if ([extension isEqualToString:@"xmodel"]) {
        NSString *rootName = [root name];

        // XmlSerializer format
        if ([rootName isEqualToString:@"models"]) {
            for (NSXMLElement *child in [root children]) {
                if (![[child name] isEqualToString:@"model"]) continue;
                NSString *name = [[child attributeForName:@"name"] stringValue];
                if ([name isEqualToString:modelName]) {
                    NSString *displayAs = [[child attributeForName:@"DisplayAs"] stringValue] ?: @"Custom";
                    return [self importModelFromXMLElement:child modelType:displayAs originalName:name];
                }
            }
            NSLog(@"XLEngineBridge: Model '%@' not found in serialized xmodel file", modelName);
            return NO;
        }

        // Traditional format - single model
        NSString *name = [[root attributeForName:@"name"] stringValue];
        if (!name || [name isEqualToString:modelName]) {
            NSString *type = [XLEngineBridge modelTypeFromXMLElementName:rootName];
            return [self importModelFromXMLElement:root modelType:type originalName:modelName];
        }
        NSLog(@"XLEngineBridge: Model name '%@' does not match file model '%@'", modelName, name);
        return NO;
    }

    // For .xlights / layout / sequence files, search for the named model
    NSArray<NSString *> *xpaths = @[
        @"//models/model",
        @"//model",
    ];

    for (NSString *xpath in xpaths) {
        NSArray<NSXMLNode *> *nodes = [root nodesForXPath:xpath error:nil];
        for (NSXMLNode *node in nodes) {
            if (![node isKindOfClass:[NSXMLElement class]]) continue;
            NSXMLElement *elem = (NSXMLElement *)node;
            NSString *name = [[elem attributeForName:@"name"] stringValue];
            if ([name isEqualToString:modelName]) {
                NSString *displayAs = [[elem attributeForName:@"DisplayAs"] stringValue] ?: @"Custom";
                return [self importModelFromXMLElement:elem modelType:displayAs originalName:name];
            }
        }
    }

    NSLog(@"XLEngineBridge: Model '%@' not found in file %@", modelName, filePath);
    return NO;
}

- (NSArray<NSDictionary *> *)getModelsInFile:(NSString *)filePath {
    if (!filePath) return @[];

    NSString *extension = [[filePath pathExtension] lowercaseString];

    if ([extension isEqualToString:@"xmodel"]) {
        return [self parseXModelFile:filePath];
    }

    // For .xlights, .xml, and other layout/sequence files
    NSArray<NSDictionary *> *models = [self parseXLightsLayoutFile:filePath];
    if (models.count == 0) {
        // Fall back to trying .xmodel parsing (some files may not have standard extensions)
        models = [self parseXModelFile:filePath];
    }
    return models;
}

#pragma mark - LOR S5 Import

- (nullable NSArray<NSString *> *)getLORS5PreviewNames:(NSString *)filePath {
    if (!filePath) return nil;
    return [XLORS5Parser previewNamesInFile:filePath];
}

- (nullable NSArray<NSString *> *)importModelsFromLORS5File:(NSString *)filePath
                                                previewName:(nullable NSString *)previewName
                                                layoutGroup:(NSString *)layoutGroup {
    if (!filePath) return nil;

    [self ensureEngineInitialized];
    if (!_modelEngine) {
        NSLog(@"XLEngineBridge: Cannot import LOR S5 models - engine not available");
        return nil;
    }

    int previewWidth = 1280;
    int previewHeight = 720;

    NSArray<XLORS5ModelInfo *> *models = nil;
    NSArray<XLORS5GroupInfo *> *groups = nil;

    BOOL parseResult = [XLORS5Parser parseFile:filePath
                                   previewName:previewName
                                  previewWidth:previewWidth
                                 previewHeight:previewHeight
                                        models:&models
                                        groups:&groups];

    if (!parseResult || !models) {
        NSLog(@"XLEngineBridge: Failed to parse LOR S5 file: %@", filePath);
        return nil;
    }

    NSLog(@"XLEngineBridge: Parsed %lu models and %lu groups from LOR S5 file",
          (unsigned long)models.count, (unsigned long)(groups ? groups.count : 0));

    // Import each model
    NSMutableArray<NSString *> *importedNames = [NSMutableArray array];
    for (XLORS5ModelInfo *modelInfo in models) {
        NSString *modelType = modelInfo.xlightsModelType;
        NSString *originalName = modelInfo.name;
        NSDictionary *properties = modelInfo.properties;

        if (!modelType || !originalName || !properties) continue;

        // Generate unique name
        std::string baseName = [originalName UTF8String];
        std::string finalName = baseName;
        int suffix = 2;
        while (_modelEngine->hasModel(finalName)) {
            finalName = baseName + "-" + std::to_string(suffix);
            suffix++;
        }

        // Merge in layout group
        NSMutableDictionary *mergedProps = [properties mutableCopy];
        if (layoutGroup.length > 0) {
            mergedProps[@"LayoutGroup"] = layoutGroup;
        }

        std::map<std::string, std::string> stdProps;
        for (NSString *key in mergedProps) {
            stdProps[[key UTF8String]] = [[mergedProps[key] description] UTF8String];
        }

        xlEngine::OperationResult result = _modelEngine->createModel([modelType UTF8String], finalName, stdProps);
        if (result.success) {
            NSString *importedName = [NSString stringWithUTF8String:finalName.c_str()];
            [importedNames addObject:importedName];
            NSLog(@"XLEngineBridge: Imported LOR S5 model '%s' (type: %@)", finalName.c_str(), modelType);
        } else {
            NSLog(@"XLEngineBridge: Failed to import LOR S5 model '%s': %s",
                  finalName.c_str(), result.message.c_str());
        }
    }

    // Import groups
    if (groups) {
        for (XLORS5GroupInfo *groupObj in groups) {
            NSString *groupName = groupObj.name;
            NSArray<NSString *> *memberIds = groupObj.memberIds;

            if (!groupName || !memberIds) continue;

            // Resolve member IDs to model names
            NSMutableArray<NSString *> *memberNames = [NSMutableArray array];
            for (NSString *memberId in memberIds) {
                for (XLORS5ModelInfo *modelInfo in models) {
                    if ([modelInfo.modelId isEqualToString:memberId] && modelInfo.name) {
                        [memberNames addObject:modelInfo.name];
                        break;
                    }
                }
            }

            if (memberNames.count == 0) continue;

            // Generate unique group name
            std::string baseGroupName = [groupName UTF8String];
            std::string finalGroupName = baseGroupName;
            int gsuffix = 2;
            while (_modelEngine->hasModel(finalGroupName)) {
                finalGroupName = baseGroupName + "-" + std::to_string(gsuffix);
                gsuffix++;
            }

            std::vector<std::string> stdMembers;
            for (NSString *name in memberNames) {
                stdMembers.push_back([name UTF8String]);
            }

            xlEngine::OperationResult groupResult = _modelEngine->createModelGroup(finalGroupName, stdMembers);
            if (groupResult.success) {
                NSLog(@"XLEngineBridge: Created LOR S5 group '%s' with %lu members",
                      finalGroupName.c_str(), (unsigned long)memberNames.count);
            }
        }
    }

    return importedNames;
}

#pragma mark - RGB Effects File Import

- (NSDictionary *)parseRGBEffectsFile:(NSString *)filePath {
    if (!filePath) return @{@"layoutGroups": @[], @"models": @[]};

    NSData *xmlData = [NSData dataWithContentsOfFile:filePath];
    if (!xmlData) {
        NSLog(@"XLEngineBridge: Cannot read RGB Effects file: %@", filePath);
        return @{@"layoutGroups": @[], @"models": @[]};
    }

    NSError *error = nil;
    NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (!xmlDoc || error) {
        NSLog(@"XLEngineBridge: Failed to parse RGB Effects XML from %@: %@", filePath, error.localizedDescription);
        return @{@"layoutGroups": @[], @"models": @[]};
    }

    NSXMLElement *root = [xmlDoc rootElement];
    if (!root) return @{@"layoutGroups": @[], @"models": @[]};

    NSMutableArray<NSDictionary *> *allModels = [NSMutableArray array];
    NSMutableOrderedSet<NSString *> *layoutGroups = [NSMutableOrderedSet orderedSet];

    // Always include Default and Unassigned
    [layoutGroups addObject:@"Default"];
    [layoutGroups addObject:@"Unassigned"];

    // Find <models> node and parse model children
    NSArray<NSXMLNode *> *modelsNodes = [root nodesForXPath:@"models" error:nil];
    NSXMLElement *modelsElement = nil;
    for (NSXMLNode *node in modelsNodes) {
        if ([node isKindOfClass:[NSXMLElement class]]) {
            modelsElement = (NSXMLElement *)node;
            break;
        }
    }

    if (modelsElement) {
        for (NSXMLElement *child in [modelsElement children]) {
            if (![[child name] isEqualToString:@"model"]) continue;

            NSString *name = [[child attributeForName:@"name"] stringValue];
            if (!name) continue;

            NSString *displayAs = [[child attributeForName:@"DisplayAs"] stringValue] ?: @"Unknown";
            NSString *layoutGroup = [[child attributeForName:@"LayoutGroup"] stringValue] ?: @"Default";
            NSDictionary *attrs = [XLEngineBridge attributesFromXMLElement:child];
            NSInteger channels = [XLEngineBridge estimateChannelCountFromAttributes:attrs];

            if (layoutGroup.length > 0 && ![layoutGroup isEqualToString:@"Default"] && ![layoutGroup isEqualToString:@"Unassigned"]) {
                [layoutGroups addObject:layoutGroup];
            }

            [allModels addObject:@{
                @"name": name,
                @"type": displayAs,
                @"channels": @(channels),
                @"layoutGroup": layoutGroup,
                @"isModelGroup": @NO,
            }];
        }
    }

    // Find <modelGroups> node and parse model group children
    NSArray<NSXMLNode *> *groupsNodes = [root nodesForXPath:@"modelGroups" error:nil];
    NSXMLElement *modelGroupsElement = nil;
    for (NSXMLNode *node in groupsNodes) {
        if ([node isKindOfClass:[NSXMLElement class]]) {
            modelGroupsElement = (NSXMLElement *)node;
            break;
        }
    }

    if (modelGroupsElement) {
        for (NSXMLElement *child in [modelGroupsElement children]) {
            if (![[child name] isEqualToString:@"modelGroup"]) continue;

            NSString *name = [[child attributeForName:@"name"] stringValue];
            if (!name) continue;

            NSString *layoutGroup = [[child attributeForName:@"LayoutGroup"] stringValue] ?: @"Default";
            NSString *memberModels = [[child attributeForName:@"models"] stringValue] ?: @"";

            if (layoutGroup.length > 0 && ![layoutGroup isEqualToString:@"Default"] && ![layoutGroup isEqualToString:@"Unassigned"]) {
                [layoutGroups addObject:layoutGroup];
            }

            [allModels addObject:@{
                @"name": name,
                @"type": @"ModelGroup",
                @"channels": @(0),
                @"layoutGroup": layoutGroup,
                @"isModelGroup": @YES,
                @"models": memberModels,
            }];
        }
    }

    // Collect layout groups from <layoutGroups> node as well
    NSArray<NSXMLNode *> *lgNodes = [root nodesForXPath:@"layoutGroups/layoutGroup" error:nil];
    for (NSXMLNode *node in lgNodes) {
        if (![node isKindOfClass:[NSXMLElement class]]) continue;
        NSXMLElement *elem = (NSXMLElement *)node;
        NSString *lgName = [[elem attributeForName:@"name"] stringValue];
        if (lgName.length > 0) {
            [layoutGroups addObject:lgName];
        }
    }

    return @{
        @"layoutGroups": [layoutGroups array],
        @"models": allModels,
    };
}

- (NSArray<NSString *> *)importModelsFromRGBEffectsFile:(NSString *)filePath
                                             modelNames:(NSArray<NSString *> *)modelNames
                                      targetLayoutGroup:(NSString *)targetLayoutGroup {
    if (!filePath || !modelNames || modelNames.count == 0) return @[];

    NSData *xmlData = [NSData dataWithContentsOfFile:filePath];
    if (!xmlData) {
        NSLog(@"XLEngineBridge: Cannot read RGB Effects file for import: %@", filePath);
        return @[];
    }

    NSError *error = nil;
    NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (!xmlDoc || error) {
        NSLog(@"XLEngineBridge: Failed to parse RGB Effects XML for import: %@", error.localizedDescription);
        return @[];
    }

    NSXMLElement *root = [xmlDoc rootElement];
    if (!root) return @[];

    NSSet<NSString *> *selectedNames = [NSSet setWithArray:modelNames];
    NSMutableArray<NSString *> *importedNames = [NSMutableArray array];

    // First pass: import regular models (not model groups)
    NSArray<NSXMLNode *> *modelNodes = [root nodesForXPath:@"models/model" error:nil];
    for (NSXMLNode *node in modelNodes) {
        if (![node isKindOfClass:[NSXMLElement class]]) continue;
        NSXMLElement *elem = (NSXMLElement *)node;

        NSString *name = [[elem attributeForName:@"name"] stringValue];
        if (!name || ![selectedNames containsObject:name]) continue;

        NSString *displayAs = [[elem attributeForName:@"DisplayAs"] stringValue] ?: @"Custom";

        // Override layout group if a target is specified
        if (targetLayoutGroup) {
            NSXMLNode *lgAttr = [elem attributeForName:@"LayoutGroup"];
            if (lgAttr) {
                [elem removeAttributeForName:@"LayoutGroup"];
            }
            [elem addAttribute:[NSXMLNode attributeWithName:@"LayoutGroup" stringValue:targetLayoutGroup]];
        }

        if ([self importModelFromXMLElement:elem modelType:displayAs originalName:name]) {
            [importedNames addObject:name];
        }
    }

    // Second pass: import model groups (after models exist)
    NSArray<NSXMLNode *> *groupNodes = [root nodesForXPath:@"modelGroups/modelGroup" error:nil];
    for (NSXMLNode *node in groupNodes) {
        if (![node isKindOfClass:[NSXMLElement class]]) continue;
        NSXMLElement *elem = (NSXMLElement *)node;

        NSString *name = [[elem attributeForName:@"name"] stringValue];
        if (!name || ![selectedNames containsObject:name]) continue;

        NSString *memberModelsStr = [[elem attributeForName:@"models"] stringValue] ?: @"";
        NSArray<NSString *> *memberModels = [memberModelsStr componentsSeparatedByString:@","];

        // Filter member models to only include those that exist (were imported or already exist)
        NSMutableArray<NSString *> *validMembers = [NSMutableArray array];
        for (NSString *member in memberModels) {
            NSString *trimmed = [member stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length == 0) continue;
            if ([self hasModel:trimmed]) {
                [validMembers addObject:trimmed];
            }
        }

        // Create the model group
        if ([self createModelGroupFromImport:name members:validMembers targetLayoutGroup:targetLayoutGroup]) {
            [importedNames addObject:name];
        }
    }

    return importedNames;
}

/// Internal helper: create a model group during import
- (BOOL)createModelGroupFromImport:(NSString *)groupName
                           members:(NSArray<NSString *> *)members
                 targetLayoutGroup:(NSString *)targetLayoutGroup {
    [self ensureEngineInitialized];
    if (!_modelEngine) return NO;

    std::string stdGroupName = [groupName UTF8String];

    // Generate unique name if group already exists
    std::string finalName = stdGroupName;
    int suffix = 2;
    while (_modelEngine->hasModel(finalName)) {
        finalName = stdGroupName + "-" + std::to_string(suffix);
        suffix++;
    }

    std::vector<std::string> stdMembers;
    for (NSString *m in members) {
        stdMembers.push_back([m UTF8String]);
    }

    auto result = _modelEngine->createModelGroup(finalName, stdMembers);
    if (result.success) {
        NSLog(@"XLEngineBridge: Imported model group '%s' with %lu members", finalName.c_str(), (unsigned long)members.count);

        // Set the layout group on the newly created group
        if (targetLayoutGroup) {
            std::map<std::string, std::string> props;
            props["LayoutGroup"] = [targetLayoutGroup UTF8String];
            _modelEngine->updateModelProperty(finalName, "LayoutGroup", [targetLayoutGroup UTF8String]);
        }
    } else {
        NSLog(@"XLEngineBridge: Failed to import model group '%s': %s", finalName.c_str(), result.message.c_str());
    }
    return result.success ? YES : NO;
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

- (BOOL)unlinkControllerFromBase:(NSString *)controllerName {
    if (!controllerName) return NO;

    [self ensureEngineInitialized];
    if (!_outputEngine) {
        NSLog(@"XLEngineBridge: Cannot unlink controller - engine not available");
        return NO;
    }

    std::string stdName = [controllerName UTF8String];
    if (!_outputEngine->controllerExists(stdName)) {
        return NO;
    }

    xlEngine::ControllerConfig config = _outputEngine->getController(stdName);
    config.fromBase = false;
    xlEngine::OperationResult result = _outputEngine->updateController(stdName, config);
    if (result.success) {
        _outputEngine->save();
    }
    return result.success ? YES : NO;
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

- (NSArray<NSString *> *)getOutputIPs {
    // TODO: Implement when OutputEngine supports this
    // For now, return empty array
    return @[];
}

- (NSArray<NSNumber *> *)getAllUniverses {
    // TODO: Implement when OutputEngine supports this
    // For now, return empty array
    return @[];
}

- (NSArray<NSNumber *> *)getUniversesForIP:(NSString *)ip {
    // TODO: Implement when OutputEngine supports this
    // For now, return empty array
    return @[];
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
    } else {
        [self recalculateStartChannels];
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
            [self recalculateStartChannels];
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


- (BOOL)exportControllerConfig:(NSString *)filePath {
    [self ensureEngineInitialized];

    if (!filePath || filePath.length == 0) {
        NSLog(@"XLEngineBridge: Cannot export controller config - no file path provided");
        return NO;
    }

    // Native mode: use NativeOutputProvider's saveToXML directly
    if (_nativeOutputProvider) {
        std::string stdPath = [filePath UTF8String];
        bool ok = _nativeOutputProvider->saveToXML(stdPath);
        if (!ok) {
            NSLog(@"XLEngineBridge: Failed to export controller config to %@", filePath);
        }
        return ok ? YES : NO;
    }

#ifndef XLIGHTS_NATIVE
    // Legacy mode: copy the show folder's networks file to the export path
    if (!_showFolderPath.empty()) {
        std::string srcPath = _showFolderPath + "/xlights_networks.xml";
        NSString *src = [NSString stringWithUTF8String:srcPath.c_str()];
        NSError *error = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:src]) {
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
            if ([[NSFileManager defaultManager] copyItemAtPath:src toPath:filePath error:&error]) {
                return YES;
            }
            NSLog(@"XLEngineBridge: Failed to export (copy) controller config: %@", error.localizedDescription);
        }
    }
#endif

    NSLog(@"XLEngineBridge: Cannot export controller config - no provider available");
    return NO;
}

- (BOOL)importControllerConfig:(NSString *)filePath {
    [self ensureEngineInitialized];

    if (!filePath || filePath.length == 0) {
        NSLog(@"XLEngineBridge: Cannot import controller config - no file path provided");
        return NO;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"XLEngineBridge: Cannot import controller config - file does not exist: %@", filePath);
        return NO;
    }

    // Native mode: use NativeOutputProvider's loadFromXML
    if (_nativeOutputProvider) {
        std::string stdPath = [filePath UTF8String];

        // Clear existing controllers and load from the new file
        _nativeOutputProvider->clearControllers();
        bool ok = _nativeOutputProvider->loadFromXML(stdPath);
        if (!ok) {
            NSLog(@"XLEngineBridge: Failed to import controller config from %@", filePath);
            // Attempt to reload the original config
            if (!_showFolderPath.empty()) {
                std::string networksPath = _showFolderPath + "/xlights_networks.xml";
                _nativeOutputProvider->loadFromXML(networksPath);
            }
            return NO;
        }

        // Also save to the show folder so the import persists
        if (!_showFolderPath.empty()) {
            std::string networksPath = _showFolderPath + "/xlights_networks.xml";
            _nativeOutputProvider->saveToXML(networksPath);
        }

        NSLog(@"XLEngineBridge: Successfully imported controller config from %@", filePath);
        return YES;
    }

#ifndef XLIGHTS_NATIVE
    // Legacy mode: copy the file into the show folder and reload
    if (!_showFolderPath.empty()) {
        std::string destPath = _showFolderPath + "/xlights_networks.xml";
        NSString *dest = [NSString stringWithUTF8String:destPath.c_str()];
        NSError *error = nil;

        // Back up existing file
        NSString *backup = [dest stringByAppendingString:@".bak"];
        [[NSFileManager defaultManager] removeItemAtPath:backup error:nil];
        [[NSFileManager defaultManager] copyItemAtPath:dest toPath:backup error:nil];

        // Replace with imported file
        [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
        if ([[NSFileManager defaultManager] copyItemAtPath:filePath toPath:dest error:&error]) {
            NSLog(@"XLEngineBridge: Imported controller config (legacy mode)");
            return YES;
        }
        NSLog(@"XLEngineBridge: Failed to import (copy) controller config: %@", error.localizedDescription);
    }
#endif

    NSLog(@"XLEngineBridge: Cannot import controller config - no provider available");
    return NO;
}

- (void)recalculateStartChannels {
    [self ensureEngineInitialized];
    if (!_outputEngine || !_modelEngine) return;
#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"XLChannelsDidRecalculateNotification" object:self];
        return;
    }
    std::vector<xlEngine::ControllerConfig> controllers = _outputEngine->getControllers();
    std::vector<std::string> allModelNames = _modelEngine->getModelNames();
    struct ModelPortInfo { std::string name; std::string protocol; int port; std::string modelChain; int channelCount; };
    std::map<std::string, std::map<int, std::vector<ModelPortInfo>>> controllerPortModels;
    for (const auto& mn : allModelNames) {
        auto props = _modelEngine->getModelProperties(mn);
        std::string ctrl; auto cIt = props.find("Controller"); if (cIt != props.end()) ctrl = cIt->second;
        if (ctrl.empty()) continue;
        std::string proto; int pt = 0; std::string mc;
        auto pIt = props.find("ControllerConnection.Protocol"); if (pIt != props.end()) proto = pIt->second;
        auto ptIt = props.find("ControllerConnection.Port");
        if (ptIt != props.end()) { try { pt = std::stoi(ptIt->second); } catch (...) {} }
        auto mcIt = props.find("ControllerConnection.ModelChain"); if (mcIt != props.end()) mc = mcIt->second;
        if (pt <= 0) continue;
        int p1 = 0, p2 = 0, cpn = 3;
        auto p1It = props.find("parm1"); if (p1It != props.end()) { try { p1 = std::stoi(p1It->second); } catch (...) {} }
        auto p2It = props.find("parm2"); if (p2It != props.end()) { try { p2 = std::stoi(p2It->second); } catch (...) {} }
        if (p2 <= 0) p2 = 1;
        auto stIt = props.find("StringType");
        if (stIt != props.end()) {
            if (stIt->second.find("Single") != std::string::npos) cpn = 1;
            else if (stIt->second.find("4 Channel") != std::string::npos || stIt->second.find("RGBW") != std::string::npos) cpn = 4;
        }
        int cc = p1 * p2 * cpn; if (cc <= 0) cc = 1;
        controllerPortModels[ctrl][pt].push_back({mn, proto, pt, mc, cc});
    }
    for (const auto& c : controllers) {
        auto cIt2 = controllerPortModels.find(c.name); if (cIt2 == controllerPortModels.end()) continue;
        int32_t ch = 1;
        for (auto& [pn, mdls] : cIt2->second) {
            if (mdls.size() > 1) {
                std::vector<ModelPortInfo> s; s.reserve(mdls.size());
                for (auto it = mdls.begin(); it != mdls.end(); ++it) {
                    if (it->modelChain.empty() || it->modelChain == "Beginning") { s.push_back(*it); mdls.erase(it); break; }
                }
                if (s.empty() && !mdls.empty()) { s.push_back(mdls.front()); mdls.erase(mdls.begin()); }
                while (!mdls.empty()) {
                    std::string nc = ">" + s.back().name; bool f = false;
                    for (auto it = mdls.begin(); it != mdls.end(); ++it) {
                        if (it->modelChain == nc) { s.push_back(*it); mdls.erase(it); f = true; break; }
                    }
                    if (!f) { for (auto& m : mdls) s.push_back(m); mdls.clear(); }
                }
                mdls = s;
            }
            for (const auto& m : mdls) {
                _nativeModelProvider->setModelAttribute(m.name, "StartChannel", "!" + c.name + ":" + std::to_string(ch));
                ch += m.channelCount;
            }
        }
        if (c.autoSize && ch > 1) { xlEngine::ControllerConfig u = c; u.channels = ch - 1; _outputEngine->updateController(c.name, u); }
    }
    NSLog(@"XLEngineBridge: Recalculated start channels for all models");
#endif
    [[NSNotificationCenter defaultCenter] postNotificationName:@"XLChannelsDidRecalculateNotification" object:self];
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
    } else {
        [self recalculateStartChannels];
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

#ifdef XLIGHTS_NATIVE
    // Native mode - get views from NativeModelProvider
    if (!_nativeModelProvider) {
        return @[@"Master View"];
    }

    NSMutableArray<NSString *> *viewNames = [NSMutableArray array];
    auto names = _nativeModelProvider->getViewNames();
    for (const auto& name : names) {
        [viewNames addObject:[NSString stringWithUTF8String:name.c_str()]];
    }

    // Ensure at least Master View exists
    if (viewNames.count == 0) {
        [viewNames addObject:@"Master View"];
    }

    return [viewNames copy];
#else
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
#endif
}

- (NSString *)getCurrentViewName {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return @"Master View";
    }
#ifdef XLIGHTS_NATIVE
    // Native mode - return selected view name
    if (_nativeModelProvider) {
        auto viewNames = _nativeModelProvider->getViewNames();
        if ((size_t)_currentViewIndex < viewNames.size()) {
            return [NSString stringWithUTF8String:viewNames[_currentViewIndex].c_str()];
        }
    }
    return @"Master View";
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return @"Master View";

    SequenceViewManager* viewManager = frame->GetViewsManager();
    if (!viewManager) return @"Master View";

    SequenceView* currentView = viewManager->GetSelectedView();
    if (!currentView) return @"Master View";

    return [NSString stringWithUTF8String:currentView->GetName().c_str()];
#endif
}

- (NSInteger)getCurrentViewIndex {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return 0;
    }
#ifdef XLIGHTS_NATIVE
    // Native mode - return stored view index
    return _currentViewIndex;
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return 0;

    SequenceElements& elements = frame->GetSequenceElements();
    return (NSInteger)elements.GetCurrentView();
#endif
}

- (BOOL)setCurrentView:(NSString *)viewName {
    if (!viewName) return NO;
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return NO;
    }
#ifdef XLIGHTS_NATIVE
    // Native mode - store view selection and find the view index
    if (!_nativeModelProvider) return NO;

    std::string stdViewName = [viewName UTF8String];
    auto viewNames = _nativeModelProvider->getViewNames();

    // Find the view index
    for (size_t i = 0; i < viewNames.size(); i++) {
        if (viewNames[i] == stdViewName) {
            _currentViewIndex = (NSInteger)i;
            NSLog(@"XLEngineBridge: Set current view to '%s' (index %zu)", stdViewName.c_str(), i);
            return YES;
        }
    }
    return NO;
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return NO;

    SequenceElements& elements = frame->GetSequenceElements();
    SequenceViewManager* viewManager = frame->GetViewsManager();
    if (!viewManager) return NO;

    std::string stdViewName = [viewName UTF8String];
    int viewIndex = viewManager->GetViewIndex(stdViewName);
    if (viewIndex < 0) return NO;

    if (viewIndex > 0) {
        std::string modelsString = elements.GetViewModels(stdViewName);
        elements.AddMissingModelsToSequence(modelsString);
        elements.PopulateView(modelsString, viewIndex);
    }
    elements.SetCurrentView(viewIndex);
    elements.SetTimingVisibility(stdViewName);
    return YES;
#endif
}

- (BOOL)setCurrentViewIndex:(NSInteger)viewIndex {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return NO;
    }
#ifdef XLIGHTS_NATIVE
    // Native mode - validate and store view index
    if (!_nativeModelProvider) return NO;

    size_t viewCount = _nativeModelProvider->getViewCount();
    if (viewIndex < 0 || (size_t)viewIndex >= viewCount) return NO;

    _currentViewIndex = viewIndex;
    auto viewNames = _nativeModelProvider->getViewNames();
    if ((size_t)viewIndex < viewNames.size()) {
        NSLog(@"XLEngineBridge: Set current view index to %ld ('%s')",
              (long)viewIndex, viewNames[viewIndex].c_str());
    }
    return YES;
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return NO;

    SequenceElements& elements = frame->GetSequenceElements();
    SequenceViewManager* viewManager = frame->GetViewsManager();
    if (!viewManager) return NO;

    if (viewIndex < 0 || viewIndex >= viewManager->GetViewCount()) return NO;

    SequenceView* view = viewManager->GetView((int)viewIndex);
    if (!view) return NO;

    std::string viewName = view->GetName();
    if (viewIndex > 0) {
        std::string modelsString = elements.GetViewModels(viewName);
        elements.AddMissingModelsToSequence(modelsString);
        elements.PopulateView(modelsString, (int)viewIndex);
    }
    elements.SetCurrentView((int)viewIndex);
    elements.SetTimingVisibility(viewName);
    return YES;
#endif
}

#pragma mark - Sequence Elements (for Sequencer View)

- (NSInteger)getSequenceElementCount {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return 0;
    }
#ifdef XLIGHTS_NATIVE
    return 0;  // Native mode stub
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return 0;
    SequenceElements& elements = frame->GetSequenceElements();
    int currentView = elements.GetCurrentView();
    return (NSInteger)elements.GetElementCount(currentView);
#endif
}

- (NSDictionary *)getSequenceElementAtIndex:(NSInteger)index {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return nil;
    }
#ifdef XLIGHTS_NATIVE
    return nil;  // Native mode stub
#else
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
            ModelElement* modelElem = dynamic_cast<ModelElement*>(elem);
            if (modelElem) {
                submodelCount = modelElem->GetSubModelCount();
                strandCount = modelElem->GetStrandCount();
                hasSubmodels = (submodelCount > 0);
                hasStrands = (strandCount > 0);
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
#endif
}

- (NSArray<NSDictionary *> *)getSequenceElements {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return @[];
    }
#ifdef XLIGHTS_NATIVE
    // Get elements from the effect provider (authoritative source for both
    // loaded sequences and newly created ones)
    if (!_nativeEffectProvider) {
        return @[];
    }

    size_t elementCount = _nativeEffectProvider->getElementCount();

    // Build name→index lookup for the effect provider
    std::unordered_map<std::string, size_t> nameToIndex;
    nameToIndex.reserve(elementCount);
    for (size_t i = 0; i < elementCount; i++) {
        xlEngine::ElementInfo ei;
        if (_nativeEffectProvider->getElement(i, ei)) {
            nameToIndex[ei.name] = i;
        }
    }

    // Get the current view's ordered model list
    std::vector<std::string> viewModelOrder;
    if (_nativeModelProvider) {
        auto viewInfo = _nativeModelProvider->getViewAtIndex((size_t)_currentViewIndex);
        viewModelOrder = viewInfo.models;
    }
    std::set<std::string> viewModelSet(viewModelOrder.begin(), viewModelOrder.end());

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:elementCount];

    // Helper block to build a dictionary for an element at effect provider index
    auto buildElementDict = [&](size_t idx) -> NSDictionary* {
        xlEngine::ElementInfo elemInfo;
        if (!_nativeEffectProvider->getElement(idx, elemInfo)) {
            return nil;
        }

        NSString* typeString = @"model";
        if (elemInfo.type == xlEngine::SequenceElementType::Timing) {
            typeString = @"timing";
        }

        BOOL isGroup = (_groupNames.find(elemInfo.name) != _groupNames.end()) ? YES : NO;
        NSString* elementType = isGroup ? @"group" : typeString;

        std::string folderStr = _nativeEffectProvider->getElementFolder(elemInfo.name);
        NSString* folder = folderStr.empty() ? @"" : [NSString stringWithUTF8String:folderStr.c_str()];

        return @{
            @"index": @(idx),
            @"name": [NSString stringWithUTF8String:elemInfo.name.c_str()],
            @"type": elementType,
            @"effectLayerCount": @(elemInfo.effectLayerCount),
            @"effectCount": @(elemInfo.effectCount),
            @"visible": @(elemInfo.visible),
            @"collapsed": @(elemInfo.collapsed),
            @"isGroup": @(isGroup),
            @"hasSubmodels": @NO,
            @"hasStrands": @NO,
            @"submodelCount": @0,
            @"strandCount": @0,
            @"folder": folder,
        };
    };

    // 1. Add timing tracks first (in effect provider order)
    for (size_t i = 0; i < elementCount; i++) {
        xlEngine::ElementInfo ei;
        if (_nativeEffectProvider->getElement(i, ei) &&
            ei.type == xlEngine::SequenceElementType::Timing) {
            NSDictionary* info = buildElementDict(i);
            if (info) [result addObject:info];
        }
    }

    // 2. Add models/groups in view order
    for (const auto& modelName : viewModelOrder) {
        auto it = nameToIndex.find(modelName);
        if (it != nameToIndex.end()) {
            xlEngine::ElementInfo ei;
            if (_nativeEffectProvider->getElement(it->second, ei) &&
                ei.type != xlEngine::SequenceElementType::Timing) {
                NSDictionary* info = buildElementDict(it->second);
                if (info) [result addObject:info];
            }
        }
    }

    NSLog(@"XLEngineBridge: getSequenceElements returning %lu elements (view index %ld)",
          (unsigned long)result.count, (long)_currentViewIndex);
    return result;
#else
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
#endif
}

- (NSArray<NSDictionary *> *)getEffectsForElementAtIndex:(NSInteger)index layer:(NSInteger)layer {
    [self ensureEngineInitialized];
    if (!_sequenceEngine || !_sequenceEngine->isSequenceLoaded()) {
        return @[];
    }
#ifdef XLIGHTS_NATIVE
    // Use NativeEffectProvider so effect IDs are consistent with the EffectEngine
    if (_nativeEffectProvider) {
        auto effects = _nativeEffectProvider->getEffectsOnLayer(static_cast<size_t>(index), static_cast<size_t>(layer));
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:effects.size()];
        for (const auto& eff : effects) {
            // Extract fade in/out values (stored in seconds, convert to ms)
            double fadeInMS = 0.0;
            double fadeOutMS = 0.0;
            auto itIn = eff.settings.find("T_TEXTCTRL_Fadein");
            if (itIn != eff.settings.end()) {
                fadeInMS = std::atof(itIn->second.c_str()) * 1000.0;
            }
            auto itOut = eff.settings.find("T_TEXTCTRL_Fadeout");
            if (itOut != eff.settings.end()) {
                fadeOutMS = std::atof(itOut->second.c_str()) * 1000.0;
            }
            [result addObject:@{
                @"id": @(static_cast<long long>(eff.effectId)),
                @"effectType": [NSString stringWithUTF8String:eff.effectType.c_str()],
                @"effectIndex": @(eff.effectTypeIndex),
                @"startTimeMS": @(eff.startTimeMS),
                @"endTimeMS": @(eff.endTimeMS),
                @"paletteIndex": @(0),
                @"selected": @(eff.selected),
                @"protected": @(eff.protected_),
                @"fadeInMS": @(fadeInMS),
                @"fadeOutMS": @(fadeOutMS),
            }];
        }
        return result;
    }

    // Fallback to sequence provider if effect provider not available
    if (!_nativeSequenceProvider) {
        return @[];
    }

    const auto& elements = _nativeSequenceProvider->getElements();
    if (index < 0 || (size_t)index >= elements.size()) {
        return @[];
    }

    const auto& elem = elements[index];
    if (layer < 0 || (size_t)layer >= elem.layers.size()) {
        return @[];
    }

    const auto& effectLayer = elem.layers[layer];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:effectLayer.effects.size()];

    for (size_t i = 0; i < effectLayer.effects.size(); i++) {
        const auto& eff = effectLayer.effects[i];
        [result addObject:@{
            @"id": @(i),
            @"effectType": [NSString stringWithUTF8String:eff.name.c_str()],
            @"effectIndex": @(eff.effectIndex),
            @"startTimeMS": @(eff.startTimeMS),
            @"endTimeMS": @(eff.endTimeMS),
            @"paletteIndex": @(eff.paletteIndex),
            @"selected": @NO,
            @"protected": @NO,
        }];
    }

    return result;
#else
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
#endif
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
    if (effectId >= 0) {
        [self scheduleAutoSave];
    } else {
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
    if (result) {
        [self scheduleAutoSave];
    } else {
        NSLog(@"XLEngineBridge: Failed to delete effect %ld", (long)effectId);
    }
    return result ? YES : NO;
}

- (NSDictionary *)getEffect:(NSInteger)effectId {
    [self ensureEngineInitialized];
    if (!_effectEngine) {
        NSLog(@"[EffectInspector] bridge.getEffect(%ld): no engine", (long)effectId);
        return nil;
    }

    xlEngine::EffectInfo info;
    bool found = _effectEngine->getEffect((int)effectId, info);
    if (!found) {
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

    // Use the static panel registry as the primary source — it has proper
    // labels, min/max, defaults, and choices for all defined effects.
    const XLEffectPanelDef *panelDef = [[XLEffectPanelRegistry sharedRegistry] definitionForEffect:effectType];
    if (panelDef && panelDef->parameters) {
        NSMutableArray *result = [NSMutableArray array];
        for (const XLParameterDef *p = panelDef->parameters; p->key != NULL; p++) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            dict[@"key"] = [NSString stringWithUTF8String:p->key];
            dict[@"displayLabel"] = [NSString stringWithUTF8String:p->displayLabel];

            NSString *typeStr = @"string";
            switch (p->type) {
                case XLParameterTypeInt:    typeStr = @"int"; break;
                case XLParameterTypeFloat:  typeStr = @"float"; break;
                case XLParameterTypeBool:   typeStr = @"bool"; break;
                case XLParameterTypeChoice: typeStr = @"choice"; break;
                case XLParameterTypeColor:  typeStr = @"color"; break;
                case XLParameterTypeString: typeStr = @"string"; break;
                case XLParameterTypeFile:   typeStr = @"file"; break;
                case XLParameterTypeFont:   typeStr = @"font"; break;
                case XLParameterTypeValueCurve:  typeStr = @"valueCurve"; break;
                case XLParameterTypeColorCurve:  typeStr = @"colorCurve"; break;
            }
            dict[@"type"] = typeStr;

            dict[@"group"] = [NSString stringWithUTF8String:p->group];
            dict[@"minValue"] = @(p->minValue);
            dict[@"maxValue"] = @(p->maxValue);
            dict[@"defaultValue"] = [NSString stringWithFormat:@"%.2f", p->defaultValue];
            dict[@"supportsValueCurve"] = @((p->flags & XLParameterFlagsSupportsValueCurve) != 0);

            if (p->choices) {
                NSMutableArray *choices = [NSMutableArray array];
                for (const char * const *c = p->choices; *c != NULL; c++) {
                    [choices addObject:[NSString stringWithUTF8String:*c]];
                }
                dict[@"choices"] = choices;
            } else {
                dict[@"choices"] = @[];
            }

            [result addObject:dict];
        }
        return result;
    }

    // Fallback: use the engine's buildDefaultParameters (scans existing effects)
    [self ensureEngineInitialized];
    if (!_effectEngine) {
        NSLog(@"[EffectInspector] bridge.getEffectParameters('%@'): no engine and no panel definition", effectType);
        return @[];
    }

    std::string stdType = [effectType UTF8String];
    std::vector<xlEngine::ParameterDefinition> params = _effectEngine->getEffectParameters(stdType);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:params.size()];
    for (const auto &param : params) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"key"] = [NSString stringWithUTF8String:param.key.c_str()];
        dict[@"displayLabel"] = [NSString stringWithUTF8String:param.displayLabel.c_str()];

        NSString *typeStr = @"string";
        switch (param.type) {
            case xlEngine::ParameterType::Int:         typeStr = @"int"; break;
            case xlEngine::ParameterType::Float:       typeStr = @"float"; break;
            case xlEngine::ParameterType::Bool:        typeStr = @"bool"; break;
            case xlEngine::ParameterType::String:      typeStr = @"string"; break;
            case xlEngine::ParameterType::Color:       typeStr = @"color"; break;
            case xlEngine::ParameterType::Choice:      typeStr = @"choice"; break;
            case xlEngine::ParameterType::File:        typeStr = @"file"; break;
            case xlEngine::ParameterType::ValueCurve:  typeStr = @"valueCurve"; break;
            case xlEngine::ParameterType::Font:        typeStr = @"font"; break;
            case xlEngine::ParameterType::ColorCurve:  typeStr = @"colorCurve"; break;
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
    BOOL result = _effectEngine->setEffectParameter((int)effectId, stdKey, stdValue) ? YES : NO;
    if (result) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"XLEffectDidChangeNotification" object:self];
        [self scheduleAutoSave];
    }
    return result;
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
    BOOL result = _effectEngine->setEffectSettings((int)effectId, stdSettings) ? YES : NO;
    if (result) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"XLEffectDidChangeNotification" object:self];
        [self scheduleAutoSave];
    }
    return result;
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
    BOOL result = _effectEngine->setEffectPalette((int)effectId, stdPalette) ? YES : NO;
    if (result) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"XLEffectDidChangeNotification" object:self];
        [self scheduleAutoSave];
    }
    return result;
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

    BOOL result = _effectEngine->moveEffect((int)effectId, (int)startMS, (int)endMS) ? YES : NO;
    if (result) {
        [self scheduleAutoSave];
    }
    return result;
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
    NSInteger result = _effectEngine->addLayer(stdModel);
    if (result >= 0) {
        [self scheduleAutoSave];
    }
    return result;
}

- (NSInteger)insertLayer:(NSString *)modelName atIndex:(NSInteger)index {
    if (!modelName) return -1;

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return -1;
    }

    std::string stdModel = [modelName UTF8String];
    NSInteger result = _effectEngine->insertLayer(stdModel, (int)index);
    if (result >= 0) {
        [self scheduleAutoSave];
    }
    return result;
}

- (BOOL)removeLayer:(NSString *)modelName layer:(NSInteger)layer {
    if (!modelName) return NO;

    [self ensureEngineInitialized];
    if (!_effectEngine) {
        return NO;
    }

    std::string stdModel = [modelName UTF8String];
    BOOL result = _effectEngine->removeLayer(stdModel, (int)layer) ? YES : NO;
    if (result) {
        [self scheduleAutoSave];
    }
    return result;
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
    BOOL result = _effectEngine->convertEffectType((int)effectId, stdType) ? YES : NO;
    if (result) {
        [self scheduleAutoSave];
    }
    return result;
}

- (BOOL)setEffectLocked:(NSInteger)effectId locked:(BOOL)locked {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeEffectProvider) return NO;
    auto result = _nativeEffectProvider->setEffectLocked((int64_t)effectId, locked ? true : false);
    if (result.success) [self scheduleAutoSave];
    return result.success ? YES : NO;
#else
    if (!_frame) return NO;
    auto* seqElements = &_frame->GetSequenceElements();
    for (size_t i = 0; i < seqElements->GetElementCount(); i++) {
        auto* element = seqElements->GetElement(i);
        for (int layer = 0; layer < element->GetEffectLayerCount(); layer++) {
            auto* effectLayer = element->GetEffectLayer(layer);
            for (int e = 0; e < effectLayer->GetEffectCount(); e++) {
                auto* eff = effectLayer->GetEffect(e);
                if (eff && eff->GetID() == (int)effectId) {
                    eff->SetLocked(locked ? true : false);
                    return YES;
                }
            }
        }
    }
    return NO;
#endif
}

- (BOOL)setEffectRenderDisabled:(NSInteger)effectId disabled:(BOOL)disabled {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeEffectProvider) return NO;
    auto result = _nativeEffectProvider->setEffectRenderDisabled((int64_t)effectId, disabled ? true : false);
    if (result.success) [self scheduleAutoSave];
    return result.success ? YES : NO;
#else
    if (!_frame) return NO;
    auto* seqElements = &_frame->GetSequenceElements();
    for (size_t i = 0; i < seqElements->GetElementCount(); i++) {
        auto* element = seqElements->GetElement(i);
        for (int layer = 0; layer < element->GetEffectLayerCount(); layer++) {
            auto* effectLayer = element->GetEffectLayer(layer);
            for (int e = 0; e < effectLayer->GetEffectCount(); e++) {
                auto* eff = effectLayer->GetEffect(e);
                if (eff && eff->GetID() == (int)effectId) {
                    eff->SetEffectRenderDisabled(disabled ? true : false);
                    return YES;
                }
            }
        }
    }
    return NO;
#endif
}

- (BOOL)resetEffectToDefaults:(NSInteger)effectId {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeEffectProvider) return NO;
    auto result = _nativeEffectProvider->resetEffectToDefaults((int64_t)effectId);
    if (result.success) [self scheduleAutoSave];
    return result.success ? YES : NO;
#else
    if (!_frame) return NO;
    auto* seqElements = &_frame->GetSequenceElements();
    for (size_t i = 0; i < seqElements->GetElementCount(); i++) {
        auto* element = seqElements->GetElement(i);
        for (int layer = 0; layer < element->GetEffectLayerCount(); layer++) {
            auto* effectLayer = element->GetEffectLayer(layer);
            for (int e = 0; e < effectLayer->GetEffectCount(); e++) {
                auto* eff = effectLayer->GetEffect(e);
                if (eff && eff->GetID() == (int)effectId) {
                    eff->SetSettings("", false);
                    eff->SetPalette("");
                    eff->IncrementChangeCount();
                    return YES;
                }
            }
        }
    }
    return NO;
#endif
}

#pragma mark - Auto-Save

- (void)setAudioStemDicts:(NSArray<NSDictionary<NSString *,NSString *> *> *)audioStemDicts {
    _audioStemDicts = [audioStemDicts copy];
    if (_audioStemDicts.count > 0) {
        NSLog(@"[STEMS] setAudioStemDicts: %lu stems, scheduling auto-save", (unsigned long)_audioStemDicts.count);
        [self scheduleAutoSave];
    }
}

- (void)scheduleAutoSave {
    // Invalidate pre-rendered data immediately so the live preview path
    // is used instead of stale renderAll output.
    if (_renderEngine) {
        _renderEngine->invalidateAllCaches();
    }

    if (_autoSaveTimer) {
        dispatch_source_cancel(_autoSaveTimer);
        _autoSaveTimer = nil;
    }

    _autoSaveTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _autoSaveQueue);
    dispatch_source_set_timer(_autoSaveTimer,
        dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(_autoSaveTimer, ^{
        [self performAutoSave];
    });
    dispatch_resume(_autoSaveTimer);
}

- (xlEngine::NativeEffectProvider::SequenceMetadata)buildSequenceMetadata {
    xlEngine::NativeEffectProvider::SequenceMetadata meta;
    if (_nativeSequenceProvider) {
        meta.durationSeconds = _nativeSequenceProvider->getSequenceDuration();
        meta.frameMS = _nativeSequenceProvider->getFrameMS();
        meta.mediaFile = _nativeSequenceProvider->getMediaPath();
        std::string seqType = _nativeSequenceProvider->getSequenceType();
        meta.sequenceType = seqType.empty() ? "Animation" : seqType;
    }
    // Include audio stems
    NSLog(@"[STEMS] buildSequenceMetadata: _audioStemDicts count=%lu", (unsigned long)_audioStemDicts.count);
    for (NSDictionary *dict in _audioStemDicts) {
        xlEngine::NativeEffectProvider::StemReference ref;
        ref.name = [dict[@"name"] UTF8String] ?: "";
        ref.relativePath = [dict[@"relativePath"] UTF8String] ?: "";
        ref.color = [dict[@"color"] UTF8String] ?: "";
        NSLog(@"[STEMS]   meta stem: name=%@, relativePath=%@", dict[@"name"], dict[@"relativePath"]);
        meta.audioStems.push_back(ref);
    }
    return meta;
}

- (void)performAutoSave {
    if (!_nativeEffectProvider || !_nativeSequenceProvider) return;
    std::string path = _nativeSequenceProvider->getSequencePath();
    if (path.empty()) return;

    auto meta = [self buildSequenceMetadata];
    bool saved = _nativeEffectProvider->saveToSequenceFile(path, meta);
    if (saved) {
        NSLog(@"XLEngineBridge: Auto-saved sequence to %s", path.c_str());
    }
}

#pragma mark - Timing Track Operations

- (NSArray<NSDictionary *> *)getTimingTracks {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeEffectProvider) return @[];

    size_t count = _nativeEffectProvider->getElementCount();
    NSMutableArray *result = [NSMutableArray array];
    for (size_t i = 0; i < count; i++) {
        xlEngine::ElementInfo info;
        if (!_nativeEffectProvider->getElement(i, info)) continue;
        if (info.type != xlEngine::SequenceElementType::Timing) continue;

        NSMutableDictionary *trackInfo = [NSMutableDictionary dictionary];
        trackInfo[@"name"] = [NSString stringWithUTF8String:info.name.c_str()];
        trackInfo[@"layerCount"] = @(info.effectLayerCount);
        trackInfo[@"isActive"] = @(info.isActive);
        trackInfo[@"isFixed"] = @(info.fixedTiming > 0);
        trackInfo[@"fixedInterval"] = @(info.fixedTiming);
        [result addObject:trackInfo];
    }
    return result;
#else
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
#endif
}

- (NSString *)getActiveTimingTrackName {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeEffectProvider) return nil;

    size_t count = _nativeEffectProvider->getElementCount();
    for (size_t i = 0; i < count; i++) {
        xlEngine::ElementInfo info;
        if (!_nativeEffectProvider->getElement(i, info)) continue;
        if (info.type == xlEngine::SequenceElementType::Timing && info.isActive) {
            return [NSString stringWithUTF8String:info.name.c_str()];
        }
    }
    return nil;
#else
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
#endif
}

- (BOOL)setActiveTimingTrack:(NSString *)trackName {
    if (!trackName) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeEffectProvider) return NO;

    std::string stdName = [trackName UTF8String];
    BOOL success = _nativeEffectProvider->setTimingTrackActive(stdName);
    if (success) {
        NSLog(@"XLEngineBridge: Activated timing track: %@", trackName);
    } else {
        NSLog(@"XLEngineBridge: Timing track not found: %@", trackName);
    }
    return success;
#else
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
#endif
}

- (void)deactivateAllTimingTracks {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (_nativeEffectProvider) {
        _nativeEffectProvider->deactivateAllTimingTracks();
        NSLog(@"XLEngineBridge: Deactivated all timing tracks");
    }
#else
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
#endif
}

- (NSArray<NSDictionary *> *)getTimingMarks:(NSString *)trackName layer:(NSInteger)layer {
    if (!trackName) return @[];

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeEffectProvider) return @[];

    std::string stdName = [trackName UTF8String];
    size_t elementIndex = _nativeEffectProvider->getElementIndex(stdName);
    if (elementIndex == SIZE_MAX) return @[];

    xlEngine::ElementInfo elemInfo;
    if (!_nativeEffectProvider->getElement(elementIndex, elemInfo)) return @[];
    if (elemInfo.type != xlEngine::SequenceElementType::Timing) return @[];

    if (layer < 0 || (size_t)layer >= _nativeEffectProvider->getEffectLayerCount(elementIndex)) return @[];

    auto effects = _nativeEffectProvider->getEffectsOnLayer(elementIndex, (size_t)layer);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:effects.size()];
    for (const auto& eff : effects) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[@"id"] = @(eff.effectId);
        info[@"startTimeMS"] = @(eff.startTimeMS);
        info[@"endTimeMS"] = @(eff.endTimeMS);
        info[@"label"] = [NSString stringWithUTF8String:eff.effectType.c_str()];
        [result addObject:info];
    }
    return result;
#else
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
#endif
}

- (NSArray<NSNumber *> *)getActiveTimingMarkTimes {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeEffectProvider) return @[];

    // Find the active timing track
    size_t elementCount = _nativeEffectProvider->getElementCount();
    size_t activeIndex = SIZE_MAX;
    size_t activeLayerCount = 0;
    for (size_t i = 0; i < elementCount; i++) {
        xlEngine::ElementInfo info;
        if (!_nativeEffectProvider->getElement(i, info)) continue;
        if (info.type == xlEngine::SequenceElementType::Timing && info.isActive) {
            activeIndex = i;
            activeLayerCount = info.effectLayerCount;
            break;
        }
    }

    if (activeIndex == SIZE_MAX) return @[];

    // Use the lowest (most granular) layer for grid lines.
    // For lyric tracks: layer 0 = phrases, layer 1 = words, layer 2 = phonemes.
    // The most granular layer provides the finest snap-to grid.
    size_t targetLayer = (activeLayerCount > 0) ? (activeLayerCount - 1) : 0;
    auto effects = _nativeEffectProvider->getEffectsOnLayer(activeIndex, targetLayer);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:effects.size() * 2];
    for (const auto& eff : effects) {
        [result addObject:@(eff.startTimeMS)];
        if (eff.endTimeMS != eff.startTimeMS) {
            [result addObject:@(eff.endTimeMS)];
        }
    }
    return result;
#else
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

        // Use the lowest (most granular) layer for grid lines
        int layerCount = activeTe->GetEffectLayerCount();
        int targetLayer = (layerCount > 0) ? (layerCount - 1) : 0;
        EffectLayer* el = activeTe->GetEffectLayer(targetLayer);
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
#endif
}

- (NSInteger)createTimingMark:(NSString *)trackName
                        layer:(NSInteger)layer
                  startTimeMS:(NSInteger)startTimeMS
                    endTimeMS:(NSInteger)endTimeMS
                        label:(NSString * _Nullable)label {
    if (!trackName) return -1;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeEffectProvider) return -1;

    std::string stdName = [trackName UTF8String];
    size_t elementIndex = _nativeEffectProvider->getElementIndex(stdName);
    if (elementIndex == SIZE_MAX) return -1;

    xlEngine::ElementInfo elemInfo;
    if (!_nativeEffectProvider->getElement(elementIndex, elemInfo)) return -1;
    if (elemInfo.type != xlEngine::SequenceElementType::Timing) return -1;

    if (layer < 0 || (size_t)layer >= _nativeEffectProvider->getEffectLayerCount(elementIndex)) return -1;

    std::string labelStr = label ? [label UTF8String] : "";
    auto result = _nativeEffectProvider->createEffect(elementIndex, (size_t)layer,
                                                       labelStr, (int)startTimeMS, (int)endTimeMS);
    if (result.success) {
        NSLog(@"XLEngineBridge: Created timing mark '%s' at %ld-%ld ms",
              labelStr.c_str(), (long)startTimeMS, (long)endTimeMS);
        [self scheduleAutoSave];
        return (NSInteger)result.effectId;
    }
    return -1;
#else
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
#endif
}

- (BOOL)moveTimingMark:(NSInteger)markId startTimeMS:(NSInteger)startMS endTimeMS:(NSInteger)endMS {
    // Use the existing moveEffect method since timing marks are effects
    return [self moveEffect:markId startTimeMS:startMS endTimeMS:endMS];
}

- (BOOL)setTimingMarkLabel:(NSInteger)markId label:(NSString *)label {
    if (!label) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeEffectProvider) return NO;

    std::string stdLabel = [label UTF8String];
    auto result = _nativeEffectProvider->updateEffectType(static_cast<int64_t>(markId), stdLabel);
    if (result.success) {
        NSLog(@"XLEngineBridge: Set timing mark %ld label to '%@'", (long)markId, label);
        [self scheduleAutoSave];
    } else {
        NSLog(@"XLEngineBridge: Failed to set timing mark %ld label", (long)markId);
    }
    return result.success ? YES : NO;
#else
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
#endif
}

- (BOOL)deleteTimingMark:(NSInteger)markId {
    // Use the existing deleteEffect method since timing marks are effects
    return [self deleteEffect:markId];
}

- (NSDictionary *)getTimingMark:(NSInteger)markId {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    return nil;  // TODO: Implement native timing marks
#else
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
#endif
}

- (BOOL)createTimingTrack:(NSString *)name {
    if (!name) return NO;

    [self ensureEngineInitialized];

#ifndef XLIGHTS_NATIVE
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
#else
    if (!_nativeEffectProvider) return NO;

    std::string stdName = [name UTF8String];
    size_t idx = _nativeEffectProvider->addElement(stdName, xlEngine::SequenceElementType::Timing);
    if (idx != SIZE_MAX) {
        NSLog(@"XLEngineBridge: Created native timing track: %@", name);
        [self scheduleAutoSave];
        return YES;
    }
    NSLog(@"XLEngineBridge: Failed to create native timing track: %@", name);
    return NO;
#endif
}

- (BOOL)createTimingTrack:(NSString *)name timingType:(NSString *)timingType {
    return [self createTimingTrack:name];
}

- (BOOL)importTimingTrack:(NSString *)trackName fromSequence:(NSString *)sequenceFile asTrackName:(NSString *)newTrackName {
    if (!trackName || !sequenceFile) return NO;

    NSString *targetName = newTrackName ?: trackName;

    // Read the source sequence XML file
    NSError *error = nil;
    NSString *xmlContent = [NSString stringWithContentsOfFile:sequenceFile
                                                    encoding:NSUTF8StringEncoding
                                                       error:&error];
    if (!xmlContent || error) {
        NSLog(@"XLEngineBridge: Failed to read sequence file for import: %@", error);
        return NO;
    }

    // Parse the XML to find the timing track
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xmlContent
                                                         options:0
                                                           error:&error];
    if (!doc || error) {
        NSLog(@"XLEngineBridge: Failed to parse sequence XML: %@", error);
        return NO;
    }

    // Find timing elements in the source sequence
    NSArray *elements = [doc.rootElement elementsForName:@"Element"];
    NSXMLElement *sourceTimingElement = nil;
    for (NSXMLElement *elem in elements) {
        NSString *type = [[elem attributeForName:@"type"] stringValue];
        NSString *name = [[elem attributeForName:@"name"] stringValue];
        if ([type isEqualToString:@"timing"] && [name isEqualToString:trackName]) {
            sourceTimingElement = elem;
            break;
        }
    }

    if (!sourceTimingElement) {
        NSLog(@"XLEngineBridge: Timing track '%@' not found in source sequence", trackName);
        return NO;
    }

    // Create the new timing track
    if (![self createTimingTrack:targetName]) {
        NSLog(@"XLEngineBridge: Failed to create target timing track '%@'", targetName);
        return NO;
    }

    // Copy timing marks from source to new track
    NSArray *layers = [sourceTimingElement elementsForName:@"EffectLayer"];
    for (NSUInteger layerIdx = 0; layerIdx < layers.count; layerIdx++) {
        NSXMLElement *layerElem = layers[layerIdx];
        NSArray *effects = [layerElem elementsForName:@"Effect"];
        for (NSXMLElement *effectElem in effects) {
            NSString *label = [[effectElem attributeForName:@"name"] stringValue] ?: @"";
            NSString *startStr = [[effectElem attributeForName:@"startCentisecond"] stringValue];
            NSString *endStr = [[effectElem attributeForName:@"endCentisecond"] stringValue];

            if (startStr && endStr) {
                NSInteger startMS = [startStr integerValue] * 10;
                NSInteger endMS = [endStr integerValue] * 10;
                [self createTimingMark:targetName layer:(NSInteger)layerIdx
                           startTimeMS:startMS endTimeMS:endMS label:label];
            }
        }
    }

    NSLog(@"XLEngineBridge: Imported timing track '%@' as '%@'", trackName, targetName);
    return YES;
}

- (BOOL)deleteTimingTrack:(NSString *)name {
    if (!name) return NO;

    [self ensureEngineInitialized];

#ifndef XLIGHTS_NATIVE
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
#else
    if (!_nativeEffectProvider) return NO;

    std::string stdName = [name UTF8String];
    size_t elementIndex = _nativeEffectProvider->getElementIndex(stdName);
    if (elementIndex == SIZE_MAX) {
        NSLog(@"XLEngineBridge: Timing track not found: %@", name);
        return NO;
    }

    xlEngine::ElementInfo elemInfo;
    if (!_nativeEffectProvider->getElement(elementIndex, elemInfo)) return NO;
    if (elemInfo.type != xlEngine::SequenceElementType::Timing) {
        NSLog(@"XLEngineBridge: Element '%@' is not a timing track", name);
        return NO;
    }

    if (_nativeEffectProvider->removeElement(elementIndex)) {
        NSLog(@"XLEngineBridge: Deleted timing track: %@", name);
        [self scheduleAutoSave];
        return YES;
    }
    return NO;
#endif
}

- (BOOL)renameTimingTrack:(NSString *)oldName toName:(NSString *)newName {
    if (!oldName || !newName) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    NSLog(@"XLEngineBridge: renameTimingTrack not yet supported in native build");
    return NO;
#else
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
#endif
}

- (NSArray<NSString *> *)getPhonemesForWord:(NSString *)word {
    if (!word || word.length == 0) return @[];

#ifdef XLIGHTS_NATIVE
    // Native build: return empty (dictionary not available yet)
    return @[];
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) return @[];

    @try {
        frame->dictionary.LoadDictionaries(frame->CurrentDir, frame);
        wxArrayString phonemes;
        frame->dictionary.BreakdownWord(wxString([word UTF8String]), phonemes);

        NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:phonemes.Count()];
        for (size_t i = 0; i < phonemes.Count(); i++) {
            [result addObject:[NSString stringWithUTF8String:phonemes[i].ToStdString().c_str()]];
        }
        return result;
    } @catch (NSException *exception) {
        NSLog(@"XLEngineBridge: Exception getting phonemes for word '%@': %@ - %@",
              word, exception.name, exception.reason);
        return @[];
    }
#endif
}

#pragma mark - Track Folders

- (NSArray<NSDictionary *> *)getTrackFolders {
#ifdef XLIGHTS_NATIVE
    if (!_nativeEffectProvider) return @[];

    auto folders = _nativeEffectProvider->getTrackFolders();
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:folders.size()];
    for (const auto& folder : folders) {
        [result addObject:@{
            @"name": [NSString stringWithUTF8String:folder.name.c_str()],
            @"collapsed": @(folder.collapsed),
        }];
    }
    return result;
#else
    return @[];
#endif
}

- (BOOL)createTrackFolder:(NSString *)name {
#ifdef XLIGHTS_NATIVE
    if (!name || !_nativeEffectProvider) return NO;
    return _nativeEffectProvider->createTrackFolder(std::string([name UTF8String])) ? YES : NO;
#else
    return NO;
#endif
}

- (BOOL)deleteTrackFolder:(NSString *)name {
#ifdef XLIGHTS_NATIVE
    if (!name || !_nativeEffectProvider) return NO;
    return _nativeEffectProvider->deleteTrackFolder(std::string([name UTF8String])) ? YES : NO;
#else
    return NO;
#endif
}

- (BOOL)renameTrackFolder:(NSString *)oldName toName:(NSString *)newName {
#ifdef XLIGHTS_NATIVE
    if (!oldName || !newName || !_nativeEffectProvider) return NO;
    return _nativeEffectProvider->renameTrackFolder(
        std::string([oldName UTF8String]),
        std::string([newName UTF8String])) ? YES : NO;
#else
    return NO;
#endif
}

- (BOOL)setElement:(NSString *)elementName folder:(NSString *)folderName {
#ifdef XLIGHTS_NATIVE
    if (!elementName || !_nativeEffectProvider) return NO;
    std::string folder = folderName ? std::string([folderName UTF8String]) : "";
    return _nativeEffectProvider->setElementFolder(
        std::string([elementName UTF8String]), folder) ? YES : NO;
#else
    return NO;
#endif
}

- (NSString *)getElementFolder:(NSString *)elementName {
#ifdef XLIGHTS_NATIVE
    if (!elementName || !_nativeEffectProvider) return nil;
    std::string folder = _nativeEffectProvider->getElementFolder(std::string([elementName UTF8String]));
    return folder.empty() ? nil : [NSString stringWithUTF8String:folder.c_str()];
#else
    return nil;
#endif
}

- (BOOL)setTrackFolderCollapsed:(NSString *)name collapsed:(BOOL)collapsed {
#ifdef XLIGHTS_NATIVE
    if (!name || !_nativeEffectProvider) return NO;
    return _nativeEffectProvider->setTrackFolderCollapsed(
        std::string([name UTF8String]), collapsed) ? YES : NO;
#else
    return NO;
#endif
}

#pragma mark - Song Structure Regions

- (NSArray<NSDictionary *> *)getSongStructureRegions {
#ifdef XLIGHTS_NATIVE
    if (!_nativeEffectProvider) return @[];

    auto regions = _nativeEffectProvider->getSongStructureRegions();
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:regions.size()];
    for (const auto& region : regions) {
        [result addObject:@{
            @"regionId": @(region.regionId),
            @"startTimeMS": @(region.startTimeMS),
            @"endTimeMS": @(region.endTimeMS),
            @"name": [NSString stringWithUTF8String:region.name.c_str()],
            @"colorARGB": @(region.colorARGB),
        }];
    }
    return result;
#else
    return @[];
#endif
}

- (void)addSongStructureBoundaryAtTimeMS:(NSInteger)timeMS {
#ifdef XLIGHTS_NATIVE
    if (_nativeEffectProvider) {
        _nativeEffectProvider->addSongStructureBoundary((int)timeMS);
        [self scheduleAutoSave];
    }
#endif
}

- (void)moveSongStructureBoundary:(NSInteger)idx toTimeMS:(NSInteger)newTimeMS {
#ifdef XLIGHTS_NATIVE
    if (_nativeEffectProvider) {
        _nativeEffectProvider->moveSongStructureBoundary((size_t)idx, (int)newTimeMS);
        [self scheduleAutoSave];
    }
#endif
}

- (void)deleteSongStructureBoundary:(NSInteger)idx {
#ifdef XLIGHTS_NATIVE
    if (_nativeEffectProvider) {
        _nativeEffectProvider->deleteSongStructureBoundary((size_t)idx);
        [self scheduleAutoSave];
    }
#endif
}

- (void)setSongStructureRegion:(NSInteger)regionId name:(NSString *)name colorARGB:(uint32_t)colorARGB {
#ifdef XLIGHTS_NATIVE
    if (_nativeEffectProvider) {
        std::string nameStr = name ? std::string([name UTF8String]) : "";
        _nativeEffectProvider->updateSongStructureRegion((int64_t)regionId, nameStr, colorARGB);
        [self scheduleAutoSave];
    }
#endif
}

- (void)clearSongStructure {
#ifdef XLIGHTS_NATIVE
    if (_nativeEffectProvider) {
        _nativeEffectProvider->clearSongStructure();
        [self scheduleAutoSave];
    }
#endif
}

#pragma mark - Audio Operations

- (NSString *)getMediaFilePath {
    [self ensureEngineInitialized];
    if (!_sequenceEngine) return nil;

#ifdef XLIGHTS_NATIVE
    // For native build, get media path from SequenceEngine
    if (_sequenceEngine && _sequenceEngine->isSequenceLoaded()) {
        xlEngine::SequenceInfo info = _sequenceEngine->getSequenceInfo();
        if (!info.mediaFile.empty()) {
            return [NSString stringWithUTF8String:info.mediaFile.c_str()];
        }
    }
    return nil;
#else
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
#endif
}

- (BOOL)isAudioLoaded {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    // For native build, check if we have a media file
    NSString *mediaPath = [self getMediaFilePath];
    return mediaPath != nil && [[NSFileManager defaultManager] fileExistsAtPath:mediaPath];
#else
    xLightsXmlFile* seqFile = xLightsFrame::CurrentSeqXmlFile;
    if (!seqFile) return NO;

    AudioManager* audio = seqFile->GetMedia();
    return audio != nullptr && audio->IsOk();
#endif
}

- (NSDictionary *)getAudioInfo {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    // For native build, return basic info from SequenceEngine
    NSString *mediaPath = [self getMediaFilePath];
    if (!mediaPath) return nil;

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"filePath"] = mediaPath;
    // Other fields would need native audio analysis
    return info;
#else
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
#endif
}

- (NSDictionary *)getAudioSamples:(NSInteger)startMS endMS:(NSInteger)endMS {
    [self ensureEngineInitialized];

    // Validate time range
    if (startMS < 0) startMS = 0;
    if (endMS <= startMS) {
        NSLog(@"XLEngineBridge: Invalid audio sample range: %ld to %ld", (long)startMS, (long)endMS);
        return nil;
    }

#ifdef XLIGHTS_NATIVE
    // TODO: Implement native audio sample access
    return nil;
#else
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
#endif
}

- (NSDictionary *)getAudioAmplitudeRange:(NSInteger)startMS endMS:(NSInteger)endMS {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    // TODO: Implement native audio amplitude analysis
    return nil;
#else
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
#endif
}

- (void)setAudioVolume:(NSInteger)volume {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (_nativeSequenceProvider) {
        double vol = std::max(0, std::min((int)volume, 100)) / 100.0;
        _nativeSequenceProvider->setVolume(vol);
    }
#else
    xLightsXmlFile* seqFile = xLightsFrame::CurrentSeqXmlFile;
    if (!seqFile) return;

    AudioManager* audio = seqFile->GetMedia();
    if (audio) {
        audio->SetVolume((int)volume);
    }
#endif
}

- (NSInteger)getAudioVolume {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (_nativeSequenceProvider) {
        return (NSInteger)(_nativeSequenceProvider->getVolume() * 100.0);
    }
    return 100;
#else
    xLightsXmlFile* seqFile = xLightsFrame::CurrentSeqXmlFile;
    if (!seqFile) return 100;

    AudioManager* audio = seqFile->GetMedia();
    if (audio) {
        return audio->GetVolume();
    }
    return 100;
#endif
}

- (void)setPlaybackSpeed:(double)speed {
    double clampedSpeed = std::max(0.1, std::min(speed, 10.0));

#ifdef XLIGHTS_NATIVE
    if (_nativeSequenceProvider) {
        _nativeSequenceProvider->setPlaybackRate(clampedSpeed);
    }
#else
    NSLog(@"XLEngineBridge: setPlaybackSpeed not yet implemented for legacy build (%.2fx)", clampedSpeed);
#endif
}

- (double)getPlaybackSpeed {
#ifdef XLIGHTS_NATIVE
    if (_nativeSequenceProvider) {
        return _nativeSequenceProvider->getPlaybackRate();
    }
#endif
    return 1.0;
}

#pragma mark - View Objects (3D Objects)

- (NSArray<NSDictionary *> *)getViewObjects {
    // Stub: view object persistence not yet wired to C++ engine.
    // Returns empty array until engine-level view object management is implemented.
    return @[];
}

- (NSDictionary *)getViewObject:(NSString *)objectName {
    // Stub
    return nil;
}

- (BOOL)addViewObject:(NSString *)objectType name:(NSString *)name properties:(NSDictionary *)properties {
    // Stub
    NSLog(@"XLEngineBridge: addViewObject:%@ name:%@ (stub)", objectType, name);
    return NO;
}

- (BOOL)removeViewObject:(NSString *)objectName {
    // Stub
    NSLog(@"XLEngineBridge: removeViewObject:%@ (stub)", objectName);
    return NO;
}

- (BOOL)updateViewObjectProperty:(NSString *)objectName key:(NSString *)key value:(id)value {
    // Stub
    NSLog(@"XLEngineBridge: updateViewObjectProperty:%@ key:%@ (stub)", objectName, key);
    return NO;
}

- (BOOL)renameViewObject:(NSString *)oldName toName:(NSString *)newName {
    // Stub
    NSLog(@"XLEngineBridge: renameViewObject:%@ -> %@ (stub)", oldName, newName);
    return NO;
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
    result[@"smartRemote"] = @(info.smartRemote);
    result[@"smartRemoteType"] = [NSString stringWithUTF8String:info.smartRemoteType.c_str()];
    result[@"isActive"] = @(info.isActive);
    result[@"isGroupModel"] = @(info.isGroupModel);

    // Compute RenderWidth/RenderHeight/RenderDepth from buffer dimensions.
    // These match what the legacy BoxedScreenLocation::SetRenderSize receives
    // during InitModel (e.g. MatrixModel sets RenderWi=BufferWi, RenderHt=BufferHt).
    // defaultBufferWi/Ht already mirror the legacy RenderWi/RenderHt for all
    // model types that call CopyBufCoord2ScreenCoord.
    float renderW = (info.defaultBufferWi > 0) ? (float)info.defaultBufferWi : 1.0f;
    float renderH = (info.defaultBufferHt > 0) ? (float)info.defaultBufferHt : 1.0f;
    float renderD = 2.0f;  // legacy default depth for most boxed models
    result[@"RenderWidth"] = @(renderW);
    result[@"RenderHeight"] = @(renderH);
    result[@"RenderDepth"] = @(renderD);

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
    result[@"fromBase"] = @(config.fromBase);

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

#pragma mark - Pixel Test Operations

- (void)setTestChannel:(NSInteger)channel value:(NSUInteger)value {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    // TODO: Implement native pixel test via OutputEngine
    if (_outputEngine) {
        // _outputEngine->setChannel(channel - 1, value);
    }
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) {
        NSLog(@"XLEngineBridge: Cannot set test channel - xLightsFrame not available");
        return;
    }

    OutputManager* outputManager = frame->GetOutputManager();
    if (outputManager) {
        // Channel is 1-indexed from the API, OutputManager expects 0-indexed
        outputManager->SetOneChannel((int32_t)(channel - 1), (unsigned char)value);
    }
#endif
}

- (void)setTestChannels:(NSInteger)startChannel data:(NSData *)data {
    if (!data || data.length == 0) return;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    // TODO: Implement native pixel test via OutputEngine
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) {
        NSLog(@"XLEngineBridge: Cannot set test channels - xLightsFrame not available");
        return;
    }

    OutputManager* outputManager = frame->GetOutputManager();
    if (outputManager) {
        // Channel is 1-indexed from the API, OutputManager expects 0-indexed
        outputManager->SetManyChannels((int32_t)(startChannel - 1),
                                       (unsigned char*)data.bytes,
                                       data.length);
    }
#endif
}

- (void)allTestChannelsOff {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    // TODO: Implement native pixel test via OutputEngine
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) {
        NSLog(@"XLEngineBridge: Cannot turn off test channels - xLightsFrame not available");
        return;
    }

    OutputManager* outputManager = frame->GetOutputManager();
    if (outputManager) {
        outputManager->AllOff();
    }
#endif
}

- (void)startTestFrame {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    // TODO: Implement native pixel test via OutputEngine
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) {
        return;
    }

    OutputManager* outputManager = frame->GetOutputManager();
    if (outputManager) {
        outputManager->StartFrame(0);
    }
#endif
}

- (void)endTestFrame {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    // TODO: Implement native pixel test via OutputEngine
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) {
        return;
    }

    OutputManager* outputManager = frame->GetOutputManager();
    if (outputManager) {
        outputManager->EndFrame();
    }
#endif
}

- (NSInteger)getTotalTestChannels {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    // TODO: Implement native total channels
    return 0;
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) {
        return 0;
    }

    OutputManager* outputManager = frame->GetOutputManager();
    if (outputManager) {
        return outputManager->GetTotalChannels();
    }
    return 0;
#endif
}

- (NSDictionary *)getModelChannelInfo:(NSString *)modelName {
    if (!modelName) return nil;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    // Get model info from ModelEngine
    if (_modelEngine) {
        std::string stdName = [modelName UTF8String];
        xlEngine::ModelInfo info = _modelEngine->getModel(stdName);
        if (!info.name.empty()) {
            return @{
                @"startChannel": @(info.firstChannel + 1),
                @"channelCount": @(info.channelCount),
                @"nodeCount": @(info.nodeCount)
            };
        }
    }
    return nil;
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) {
        return nil;
    }

    std::string stdName = [modelName UTF8String];
    Model* model = frame->AllModels[stdName];
    if (!model) {
        return nil;
    }

    return @{
        @"startChannel": @(model->GetFirstChannel() + 1),
        @"channelCount": @(model->GetChanCount()),
        @"nodeCount": @(model->GetNodeCount())
    };
#endif
}

- (NSArray<NSDictionary *> *)getModelChannelRanges:(NSString *)modelName {
    if (!modelName) return @[];

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_modelEngine) return @[];

    std::string stdName = [modelName UTF8String];
    xlEngine::ModelInfo info = _modelEngine->getModel(stdName);
    if (info.name.empty() || info.nodeCount == 0) return @[];

    uint32_t chansPerNode = (info.nodeCount > 0) ? info.channelCount / info.nodeCount : 3;
    if (chansPerNode == 0) chansPerNode = 3;

    NSMutableArray *ranges = [NSMutableArray array];
    for (uint32_t nodeIdx = 0; nodeIdx < info.nodeCount; nodeIdx++) {
        uint32_t nodeStartCh = info.firstChannel + nodeIdx * chansPerNode;

        [ranges addObject:@{
            @"nodeIndex": @(nodeIdx),
            @"startChannel": @(nodeStartCh + 1), // Convert to 1-indexed
            @"endChannel": @(nodeStartCh + chansPerNode), // 1-indexed, inclusive
            @"channelCount": @(chansPerNode)
        }];
    }

    return ranges;
#else
    xLightsFrame* frame = xLightsApp::GetFrame();
    if (!frame) {
        return @[];
    }

    std::string stdName = [modelName UTF8String];
    Model* model = frame->AllModels[stdName];
    if (!model) {
        return @[];
    }

    NSMutableArray *ranges = [NSMutableArray array];

    // Get node information
    size_t nodeCount = model->GetNodeCount();
    for (size_t nodeIdx = 0; nodeIdx < nodeCount; nodeIdx++) {
        int32_t startChannel = model->NodeStartChannel(nodeIdx);
        size_t channelCount = model->GetChanCountPerNode();

        [ranges addObject:@{
            @"nodeIndex": @(nodeIdx),
            @"startChannel": @(startChannel + 1), // Convert to 1-indexed
            @"endChannel": @(startChannel + channelCount), // 1-indexed, inclusive
            @"channelCount": @(channelCount)
        }];
    }

    return ranges;
#endif
}

#pragma mark - Layout Group Operations

- (NSArray<NSString *> *)getLayoutGroupNames {
    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return @[@"Default", @"All Models", @"Unassigned"];

    auto names = _nativeModelProvider->getLayoutGroupNames();
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:names.size()];
    for (const auto& name : names) {
        [result addObject:[NSString stringWithUTF8String:name.c_str()]];
    }
    return result;
#else
    return @[@"Default", @"All Models", @"Unassigned"];
#endif
}

- (NSString *)getCurrentLayoutGroup {
    return [NSString stringWithUTF8String:_currentLayoutGroup.c_str()];
}

- (BOOL)setCurrentLayoutGroup:(NSString *)groupName {
    if (!groupName) return NO;

    _currentLayoutGroup = [groupName UTF8String];

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"XLLayoutGroupDidChangeNotification"
                      object:self
                    userInfo:@{@"groupName": groupName}];

    return YES;
}

- (BOOL)createLayoutGroup:(NSString *)name {
    if (!name) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return NO;

    bool result = _nativeModelProvider->createLayoutGroup([name UTF8String]);
    if (result) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"XLLayoutGroupListDidChangeNotification"
                          object:self];
    }
    return result ? YES : NO;
#else
    return NO;
#endif
}

- (BOOL)deleteLayoutGroup:(NSString *)name {
    if (!name) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return NO;

    std::string stdName = [name UTF8String];
    bool result = _nativeModelProvider->deleteLayoutGroup(stdName);
    if (result) {
        if (_currentLayoutGroup == stdName) {
            _currentLayoutGroup = "Default";
        }
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"XLLayoutGroupListDidChangeNotification"
                          object:self];
    }
    return result ? YES : NO;
#else
    return NO;
#endif
}

- (BOOL)renameLayoutGroup:(NSString *)oldName toName:(NSString *)newName {
    if (!oldName || !newName) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return NO;

    std::string stdOldName = [oldName UTF8String];
    bool result = _nativeModelProvider->renameLayoutGroup(stdOldName, [newName UTF8String]);
    if (result) {
        if (_currentLayoutGroup == stdOldName) {
            _currentLayoutGroup = [newName UTF8String];
        }
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"XLLayoutGroupListDidChangeNotification"
                          object:self];
    }
    return result ? YES : NO;
#else
    return NO;
#endif
}

- (NSDictionary *)getLayoutGroupSettings:(NSString *)groupName {
    if (!groupName) return nil;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return nil;

    auto info = _nativeModelProvider->getLayoutGroup([groupName UTF8String]);
    return @{
        @"name": [NSString stringWithUTF8String:info.name.c_str()],
        @"backgroundImage": [NSString stringWithUTF8String:info.backgroundImage.c_str()],
        @"backgroundBrightness": @(info.backgroundBrightness),
        @"backgroundAlpha": @(info.backgroundAlpha),
        @"scaleBackgroundImage": @(info.scaleBackgroundImage),
    };
#else
    return @{@"name": groupName};
#endif
}

- (BOOL)updateLayoutGroupSettings:(NSString *)groupName settings:(NSDictionary *)settings {
    if (!groupName || !settings) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return NO;

    auto current = _nativeModelProvider->getLayoutGroup([groupName UTF8String]);

    if (settings[@"backgroundImage"]) {
        current.backgroundImage = [settings[@"backgroundImage"] UTF8String];
    }
    if (settings[@"backgroundBrightness"]) {
        current.backgroundBrightness = [settings[@"backgroundBrightness"] intValue];
    }
    if (settings[@"backgroundAlpha"]) {
        current.backgroundAlpha = [settings[@"backgroundAlpha"] intValue];
    }
    if (settings[@"scaleBackgroundImage"]) {
        current.scaleBackgroundImage = [settings[@"scaleBackgroundImage"] boolValue];
    }

    return _nativeModelProvider->updateLayoutGroup([groupName UTF8String], current) ? YES : NO;
#else
    return NO;
#endif
}

- (NSArray<NSString *> *)getModelsForLayoutGroup:(NSString *)groupName {
    if (!groupName) return @[];

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return @[];

    auto names = _nativeModelProvider->getModelsForLayoutGroup([groupName UTF8String]);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:names.size()];
    for (const auto& name : names) {
        [result addObject:[NSString stringWithUTF8String:name.c_str()]];
    }
    return result;
#else
    return @[];
#endif
}


#pragma mark - Polyline Point Editing

- (BOOL)isPolylineModel:(NSString *)modelName {
    if (!modelName) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return NO;

    auto attrs = _nativeModelProvider->getModelAttributes([modelName UTF8String]);
    auto it = attrs.find("DisplayAs");
    if (it != attrs.end()) {
        return (it->second == "Poly Line" || it->second == "MultiPoint");
    }
    return NO;
#else
    return NO;
#endif
}

- (NSArray<NSDictionary *> *)getPolylinePoints:(NSString *)modelName {
    if (!modelName) return nil;
    if (![self isPolylineModel:modelName]) return nil;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return nil;

    auto attrs = _nativeModelProvider->getModelAttributes([modelName UTF8String]);

    // Parse world transform
    float worldX = 0, worldY = 0, worldZ = 0;
    float scaleX = 1, scaleY = 1, scaleZ = 1;

    auto itWX = attrs.find("WorldPosX"); if (itWX != attrs.end()) worldX = std::stof(itWX->second);
    auto itWY = attrs.find("WorldPosY"); if (itWY != attrs.end()) worldY = std::stof(itWY->second);
    auto itWZ = attrs.find("WorldPosZ"); if (itWZ != attrs.end()) worldZ = std::stof(itWZ->second);
    auto itSX = attrs.find("ScaleX"); if (itSX != attrs.end()) scaleX = std::stof(itSX->second);
    auto itSY = attrs.find("ScaleY"); if (itSY != attrs.end()) scaleY = std::stof(itSY->second);
    auto itSZ = attrs.find("ScaleZ"); if (itSZ != attrs.end()) scaleZ = std::stof(itSZ->second);

    // Parse number of points
    int numPoints = 2;
    auto itNP = attrs.find("NumPoints"); if (itNP != attrs.end()) numPoints = std::stoi(itNP->second);
    if (numPoints < 2) numPoints = 2;

    // Parse PointData (comma-separated x,y,z triples in local coords)
    std::vector<float> localCoords;
    auto itPD = attrs.find("PointData");
    if (itPD != attrs.end()) {
        std::stringstream ss(itPD->second);
        std::string token;
        while (std::getline(ss, token, ',')) {
            try { localCoords.push_back(std::stof(token)); }
            catch (...) { localCoords.push_back(0.0f); }
        }
    }

    // Ensure we have enough coordinate data
    while ((int)localCoords.size() < numPoints * 3) {
        localCoords.push_back(0.0f);
    }

    // Parse cPointData (curve control points: seg_num,cp0x,cp0y,cp0z,cp1x,cp1y,cp1z)
    std::map<int, std::vector<float>> curveData;
    auto itCD = attrs.find("cPointData");
    if (itCD != attrs.end() && !itCD->second.empty()) {
        std::stringstream ss(itCD->second);
        std::string token;
        std::vector<float> values;
        while (std::getline(ss, token, ',')) {
            try { values.push_back(std::stof(token)); }
            catch (...) { values.push_back(0.0f); }
        }
        // Each curve is 7 values: seg_num, cp0x, cp0y, cp0z, cp1x, cp1y, cp1z
        for (size_t i = 0; i + 6 < values.size(); i += 7) {
            int segNum = (int)values[i];
            curveData[segNum] = {values[i+1], values[i+2], values[i+3],
                                 values[i+4], values[i+5], values[i+6]};
        }
    }

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:numPoints];
    for (int i = 0; i < numPoints; i++) {
        float lx = localCoords[i * 3];
        float ly = localCoords[i * 3 + 1];
        float lz = localCoords[i * 3 + 2];

        // Convert local to world space
        float wx = lx * scaleX + worldX;
        float wy = ly * scaleY + worldY;
        float wz = lz * scaleZ + worldZ;

        NSMutableDictionary *pt = [NSMutableDictionary dictionary];
        pt[@"x"] = @(wx);
        pt[@"y"] = @(wy);
        pt[@"z"] = @(wz);

        auto curveIt = curveData.find(i);
        if (curveIt != curveData.end() && curveIt->second.size() >= 6) {
            pt[@"hasCurve"] = @YES;
            // Curve control points are in local coords, convert to world
            pt[@"cp0x"] = @(curveIt->second[0] * scaleX + worldX);
            pt[@"cp0y"] = @(curveIt->second[1] * scaleY + worldY);
            pt[@"cp0z"] = @(curveIt->second[2] * scaleZ + worldZ);
            pt[@"cp1x"] = @(curveIt->second[3] * scaleX + worldX);
            pt[@"cp1y"] = @(curveIt->second[4] * scaleY + worldY);
            pt[@"cp1z"] = @(curveIt->second[5] * scaleZ + worldZ);
        } else {
            pt[@"hasCurve"] = @NO;
            pt[@"cp0x"] = @(0.0f);
            pt[@"cp0y"] = @(0.0f);
            pt[@"cp0z"] = @(0.0f);
            pt[@"cp1x"] = @(0.0f);
            pt[@"cp1y"] = @(0.0f);
            pt[@"cp1z"] = @(0.0f);
        }

        [result addObject:pt];
    }

    return result;
#else
    return nil;
#endif
}

- (NSInteger)getPolylinePointCount:(NSString *)modelName {
    if (!modelName) return 0;
    if (![self isPolylineModel:modelName]) return 0;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return 0;

    auto attrs = _nativeModelProvider->getModelAttributes([modelName UTF8String]);
    auto it = attrs.find("NumPoints");
    if (it != attrs.end()) {
        return std::stoi(it->second);
    }
    return 2;
#else
    return 0;
#endif
}

- (BOOL)movePolylinePoint:(NSString *)modelName index:(NSInteger)pointIndex
                        x:(float)worldX y:(float)worldY z:(float)worldZ {
    if (!modelName) return NO;
    if (![self isPolylineModel:modelName]) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return NO;

    auto attrs = _nativeModelProvider->getModelAttributes([modelName UTF8String]);

    float wx = 0, wy = 0, wz = 0;
    float sx = 1, sy = 1, sz = 1;
    auto itWX = attrs.find("WorldPosX"); if (itWX != attrs.end()) wx = std::stof(itWX->second);
    auto itWY = attrs.find("WorldPosY"); if (itWY != attrs.end()) wy = std::stof(itWY->second);
    auto itWZ = attrs.find("WorldPosZ"); if (itWZ != attrs.end()) wz = std::stof(itWZ->second);
    auto itSX = attrs.find("ScaleX"); if (itSX != attrs.end()) sx = std::stof(itSX->second);
    auto itSY = attrs.find("ScaleY"); if (itSY != attrs.end()) sy = std::stof(itSY->second);
    auto itSZ = attrs.find("ScaleZ"); if (itSZ != attrs.end()) sz = std::stof(itSZ->second);

    // Convert world to local
    float lx = (sx != 0) ? (worldX - wx) / sx : 0;
    float ly = (sy != 0) ? (worldY - wy) / sy : 0;
    float lz = (sz != 0) ? (worldZ - wz) / sz : 0;

    // Parse existing PointData
    int numPoints = 2;
    auto itNP = attrs.find("NumPoints"); if (itNP != attrs.end()) numPoints = std::stoi(itNP->second);

    std::vector<float> coords;
    auto itPD = attrs.find("PointData");
    if (itPD != attrs.end()) {
        std::stringstream ss(itPD->second);
        std::string token;
        while (std::getline(ss, token, ',')) {
            try { coords.push_back(std::stof(token)); }
            catch (...) { coords.push_back(0.0f); }
        }
    }
    while ((int)coords.size() < numPoints * 3) coords.push_back(0.0f);

    if (pointIndex < 0 || pointIndex >= numPoints) return NO;

    coords[pointIndex * 3] = lx;
    coords[pointIndex * 3 + 1] = ly;
    coords[pointIndex * 3 + 2] = lz;

    // Rebuild PointData string
    std::ostringstream oss;
    for (size_t i = 0; i < coords.size(); i++) {
        if (i > 0) oss << ",";
        oss << coords[i];
    }

    _nativeModelProvider->setModelAttribute([modelName UTF8String], "PointData", oss.str());
    return YES;
#else
    return NO;
#endif
}

- (BOOL)movePolylineCurvePoint:(NSString *)modelName segmentIndex:(NSInteger)segmentIndex
                  controlPoint:(NSInteger)cpIndex
                             x:(float)worldX y:(float)worldY z:(float)worldZ {
    if (!modelName) return NO;
    if (![self isPolylineModel:modelName]) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return NO;

    auto attrs = _nativeModelProvider->getModelAttributes([modelName UTF8String]);

    float wx = 0, wy = 0, wz = 0;
    float sx = 1, sy = 1, sz = 1;
    auto itWX = attrs.find("WorldPosX"); if (itWX != attrs.end()) wx = std::stof(itWX->second);
    auto itWY = attrs.find("WorldPosY"); if (itWY != attrs.end()) wy = std::stof(itWY->second);
    auto itWZ = attrs.find("WorldPosZ"); if (itWZ != attrs.end()) wz = std::stof(itWZ->second);
    auto itSX = attrs.find("ScaleX"); if (itSX != attrs.end()) sx = std::stof(itSX->second);
    auto itSY = attrs.find("ScaleY"); if (itSY != attrs.end()) sy = std::stof(itSY->second);
    auto itSZ = attrs.find("ScaleZ"); if (itSZ != attrs.end()) sz = std::stof(itSZ->second);

    float lx = (sx != 0) ? (worldX - wx) / sx : 0;
    float ly = (sy != 0) ? (worldY - wy) / sy : 0;
    float lz = (sz != 0) ? (worldZ - wz) / sz : 0;

    // Parse cPointData
    auto itCD = attrs.find("cPointData");
    if (itCD == attrs.end()) return NO;

    std::vector<float> values;
    {
        std::stringstream ss(itCD->second);
        std::string token;
        while (std::getline(ss, token, ',')) {
            try { values.push_back(std::stof(token)); }
            catch (...) { values.push_back(0.0f); }
        }
    }

    // Find the curve entry for this segment
    for (size_t i = 0; i + 6 < values.size(); i += 7) {
        if ((int)values[i] == segmentIndex) {
            if (cpIndex == 0) {
                values[i+1] = lx;
                values[i+2] = ly;
                values[i+3] = lz;
            } else {
                values[i+4] = lx;
                values[i+5] = ly;
                values[i+6] = lz;
            }

            std::ostringstream oss;
            for (size_t j = 0; j < values.size(); j++) {
                if (j > 0) oss << ",";
                oss << values[j];
            }
            _nativeModelProvider->setModelAttribute([modelName UTF8String], "cPointData", oss.str());
            return YES;
        }
    }
    return NO;
#else
    return NO;
#endif
}

- (BOOL)insertPolylinePoint:(NSString *)modelName afterSegment:(NSInteger)afterSegment {
    if (!modelName) return NO;
    if (![self isPolylineModel:modelName]) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return NO;

    auto attrs = _nativeModelProvider->getModelAttributes([modelName UTF8String]);

    int numPoints = 2;
    auto itNP = attrs.find("NumPoints"); if (itNP != attrs.end()) numPoints = std::stoi(itNP->second);

    if (afterSegment < 0 || afterSegment >= numPoints - 1) return NO;

    std::vector<float> coords;
    auto itPD = attrs.find("PointData");
    if (itPD != attrs.end()) {
        std::stringstream ss(itPD->second);
        std::string token;
        while (std::getline(ss, token, ',')) {
            try { coords.push_back(std::stof(token)); }
            catch (...) { coords.push_back(0.0f); }
        }
    }
    while ((int)coords.size() < numPoints * 3) coords.push_back(0.0f);

    // Calculate midpoint between afterSegment and afterSegment+1
    int idx1 = (int)afterSegment * 3;
    int idx2 = ((int)afterSegment + 1) * 3;
    float mx = (coords[idx1] + coords[idx2]) / 2.0f;
    float my = (coords[idx1+1] + coords[idx2+1]) / 2.0f;
    float mz = (coords[idx1+2] + coords[idx2+2]) / 2.0f;

    // Insert at position afterSegment+1
    int insertIdx = ((int)afterSegment + 1) * 3;
    coords.insert(coords.begin() + insertIdx, {mx, my, mz});

    numPoints++;

    // Rebuild PointData
    std::ostringstream oss;
    for (size_t i = 0; i < coords.size(); i++) {
        if (i > 0) oss << ",";
        oss << coords[i];
    }

    // Update cPointData: increment segment indices for curves after the insertion point
    auto itCD = attrs.find("cPointData");
    if (itCD != attrs.end() && !itCD->second.empty()) {
        std::vector<float> cvals;
        std::stringstream css(itCD->second);
        std::string token;
        while (std::getline(css, token, ',')) {
            try { cvals.push_back(std::stof(token)); }
            catch (...) { cvals.push_back(0.0f); }
        }
        for (size_t i = 0; i + 6 < cvals.size(); i += 7) {
            if ((int)cvals[i] > afterSegment) {
                cvals[i] += 1;
            }
        }
        std::ostringstream coss;
        for (size_t i = 0; i < cvals.size(); i++) {
            if (i > 0) coss << ",";
            coss << cvals[i];
        }
        _nativeModelProvider->setModelAttribute([modelName UTF8String], "cPointData", coss.str());
    }

    _nativeModelProvider->setModelAttribute([modelName UTF8String], "PointData", oss.str());
    _nativeModelProvider->setModelAttribute([modelName UTF8String], "NumPoints", std::to_string(numPoints));
    return YES;
#else
    return NO;
#endif
}

- (BOOL)deletePolylinePoint:(NSString *)modelName index:(NSInteger)pointIndex {
    if (!modelName) return NO;
    if (![self isPolylineModel:modelName]) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return NO;

    auto attrs = _nativeModelProvider->getModelAttributes([modelName UTF8String]);

    int numPoints = 2;
    auto itNP = attrs.find("NumPoints"); if (itNP != attrs.end()) numPoints = std::stoi(itNP->second);

    if (pointIndex < 0 || pointIndex >= numPoints || numPoints <= 2) return NO;

    std::vector<float> coords;
    auto itPD = attrs.find("PointData");
    if (itPD != attrs.end()) {
        std::stringstream ss(itPD->second);
        std::string token;
        while (std::getline(ss, token, ',')) {
            try { coords.push_back(std::stof(token)); }
            catch (...) { coords.push_back(0.0f); }
        }
    }
    while ((int)coords.size() < numPoints * 3) coords.push_back(0.0f);

    // Remove the point
    int removeIdx = (int)pointIndex * 3;
    if (removeIdx + 2 < (int)coords.size()) {
        coords.erase(coords.begin() + removeIdx, coords.begin() + removeIdx + 3);
    }
    numPoints--;

    // Rebuild PointData
    std::ostringstream oss;
    for (size_t i = 0; i < coords.size(); i++) {
        if (i > 0) oss << ",";
        oss << coords[i];
    }

    // Update cPointData: remove curves referencing deleted point, adjust indices
    auto itCD = attrs.find("cPointData");
    if (itCD != attrs.end() && !itCD->second.empty()) {
        std::vector<float> cvals;
        std::stringstream css(itCD->second);
        std::string token;
        while (std::getline(css, token, ',')) {
            try { cvals.push_back(std::stof(token)); }
            catch (...) { cvals.push_back(0.0f); }
        }

        std::vector<float> newCvals;
        for (size_t i = 0; i + 6 < cvals.size(); i += 7) {
            int segNum = (int)cvals[i];
            // Remove curves that start at or end at the deleted point
            if (segNum == pointIndex || segNum == pointIndex - 1) continue;
            if (segNum > pointIndex) segNum--;
            if (segNum >= 0 && segNum < numPoints - 1) {
                newCvals.push_back((float)segNum);
                for (int j = 1; j <= 6; j++) newCvals.push_back(cvals[i+j]);
            }
        }

        std::ostringstream coss;
        for (size_t i = 0; i < newCvals.size(); i++) {
            if (i > 0) coss << ",";
            coss << newCvals[i];
        }
        _nativeModelProvider->setModelAttribute([modelName UTF8String], "cPointData", coss.str());
    }

    _nativeModelProvider->setModelAttribute([modelName UTF8String], "PointData", oss.str());
    _nativeModelProvider->setModelAttribute([modelName UTF8String], "NumPoints", std::to_string(numPoints));
    return YES;
#else
    return NO;
#endif
}

- (BOOL)setPolylineCurve:(NSString *)modelName segment:(NSInteger)segmentIndex create:(BOOL)create {
    if (!modelName) return NO;
    if (![self isPolylineModel:modelName]) return NO;
    if (![self polylineModelSupportsCurves:modelName]) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return NO;

    auto attrs = _nativeModelProvider->getModelAttributes([modelName UTF8String]);

    int numPoints = 2;
    auto itNP = attrs.find("NumPoints"); if (itNP != attrs.end()) numPoints = std::stoi(itNP->second);
    if (segmentIndex < 0 || segmentIndex >= numPoints - 1) return NO;

    // Parse existing cPointData
    std::vector<float> cvals;
    auto itCD = attrs.find("cPointData");
    if (itCD != attrs.end() && !itCD->second.empty()) {
        std::stringstream ss(itCD->second);
        std::string token;
        while (std::getline(ss, token, ',')) {
            try { cvals.push_back(std::stof(token)); }
            catch (...) { cvals.push_back(0.0f); }
        }
    }

    if (create) {
        // Check if curve already exists for this segment
        for (size_t i = 0; i + 6 < cvals.size(); i += 7) {
            if ((int)cvals[i] == segmentIndex) return YES; // Already exists
        }

        // Parse PointData to get segment endpoints for default control points
        std::vector<float> coords;
        auto itPD = attrs.find("PointData");
        if (itPD != attrs.end()) {
            std::stringstream ss(itPD->second);
            std::string token;
            while (std::getline(ss, token, ',')) {
                try { coords.push_back(std::stof(token)); }
                catch (...) { coords.push_back(0.0f); }
            }
        }
        while ((int)coords.size() < numPoints * 3) coords.push_back(0.0f);

        // Default control points: 1/3 and 2/3 along the segment
        int i1 = (int)segmentIndex * 3;
        int i2 = ((int)segmentIndex + 1) * 3;
        float dx = coords[i2] - coords[i1];
        float dy = coords[i2+1] - coords[i1+1];
        float dz = coords[i2+2] - coords[i1+2];

        float cp0x = coords[i1] + dx * 0.333f;
        float cp0y = coords[i1+1] + dy * 0.333f;
        float cp0z = coords[i1+2] + dz * 0.333f;
        float cp1x = coords[i1] + dx * 0.667f;
        float cp1y = coords[i1+1] + dy * 0.667f;
        float cp1z = coords[i1+2] + dz * 0.667f;

        cvals.push_back((float)segmentIndex);
        cvals.push_back(cp0x); cvals.push_back(cp0y); cvals.push_back(cp0z);
        cvals.push_back(cp1x); cvals.push_back(cp1y); cvals.push_back(cp1z);
    } else {
        // Remove curve for this segment
        std::vector<float> newCvals;
        for (size_t i = 0; i + 6 < cvals.size(); i += 7) {
            if ((int)cvals[i] != segmentIndex) {
                for (int j = 0; j < 7; j++) newCvals.push_back(cvals[i+j]);
            }
        }
        cvals = newCvals;
    }

    std::ostringstream oss;
    for (size_t i = 0; i < cvals.size(); i++) {
        if (i > 0) oss << ",";
        oss << cvals[i];
    }
    _nativeModelProvider->setModelAttribute([modelName UTF8String], "cPointData", oss.str());
    return YES;
#else
    return NO;
#endif
}

- (BOOL)polylineModelSupportsCurves:(NSString *)modelName {
    if (!modelName) return NO;

    [self ensureEngineInitialized];

#ifdef XLIGHTS_NATIVE
    if (!_nativeModelProvider) return NO;

    auto attrs = _nativeModelProvider->getModelAttributes([modelName UTF8String]);
    auto it = attrs.find("DisplayAs");
    if (it != attrs.end()) {
        return (it->second == "Poly Line");
    }
    return NO;
#else
    return NO;
#endif
}

@end
