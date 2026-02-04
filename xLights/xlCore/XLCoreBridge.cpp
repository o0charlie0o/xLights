/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "XLCoreBridge.h"
#include "xlCore.h"
#include "EffectManager.h"
#include "RenderPipeline.h"

#include <string>
#include <cstring>
#include <algorithm>

using namespace xlCore;

// ============================================================================
// Internal structures
// ============================================================================

struct XLCoreEngine_ {
    bool initialized = false;
    RenderPipeline pipeline;

    XLCoreEngine_() {
        // Initialize the effect manager
        EffectManager::instance().initialize();
        initialized = true;
    }
};

struct XLCoreRenderContext_ {
    RenderContext context;

    XLCoreRenderContext_(int width, int height) : context(width, height) {}
};

struct XLCoreSequence_ {
    Sequence sequence;
};

// ============================================================================
// Helper functions
// ============================================================================

static int copyStringToBuffer(const std::string& str, char* buffer, int bufferSize) {
    if (!buffer || bufferSize <= 0) {
        return static_cast<int>(str.length());
    }

    int copyLen = std::min(static_cast<int>(str.length()), bufferSize - 1);
    std::memcpy(buffer, str.c_str(), copyLen);
    buffer[copyLen] = '\0';

    return static_cast<int>(str.length());
}

// ============================================================================
// Engine lifecycle
// ============================================================================

XLCoreEngineRef XLCoreEngineCreate(void) {
    return new XLCoreEngine_();
}

void XLCoreEngineDestroy(XLCoreEngineRef engine) {
    delete engine;
}

bool XLCoreEngineIsInitialized(XLCoreEngineRef engine) {
    return engine && engine->initialized;
}

// ============================================================================
// Effect management
// ============================================================================

int XLCoreGetEffectCount(XLCoreEngineRef engine) {
    if (!engine) return 0;
    return static_cast<int>(EffectManager::instance().effectNames().size());
}

int XLCoreGetEffectNameAtIndex(XLCoreEngineRef engine, int index, char* buffer, int bufferSize) {
    if (!engine) return 0;

    auto names = EffectManager::instance().effectNames();
    if (index < 0 || index >= static_cast<int>(names.size())) {
        return 0;
    }

    return copyStringToBuffer(names[index], buffer, bufferSize);
}

bool XLCoreHasEffect(XLCoreEngineRef engine, const char* effectName) {
    if (!engine || !effectName) return false;
    return EffectManager::instance().hasEffect(effectName);
}

int XLCoreGetEffectDescription(XLCoreEngineRef engine, const char* effectName,
                                char* buffer, int bufferSize) {
    if (!engine || !effectName) return 0;

    auto info = EffectManager::instance().getEffectInfo(effectName);
    if (!info) return 0;

    return copyStringToBuffer(info->description, buffer, bufferSize);
}

int XLCoreGetEffectCategory(XLCoreEngineRef engine, const char* effectName,
                             char* buffer, int bufferSize) {
    if (!engine || !effectName) return 0;

    auto info = EffectManager::instance().getEffectInfo(effectName);
    if (!info) return 0;

    return copyStringToBuffer(info->category, buffer, bufferSize);
}

int XLCoreGetEffectParameterCount(XLCoreEngineRef engine, const char* effectName) {
    if (!engine || !effectName) return 0;

    auto params = EffectManager::instance().getParameters(effectName);
    return static_cast<int>(params.size());
}

bool XLCoreGetEffectParameterInfo(XLCoreEngineRef engine, const char* effectName,
                                   int index, XLCoreParameterInfo* parameterInfo) {
    if (!engine || !effectName || !parameterInfo) return false;

    auto params = EffectManager::instance().getParameters(effectName);
    if (index < 0 || index >= static_cast<int>(params.size())) {
        return false;
    }

    const auto& param = params[index];

    copyStringToBuffer(param.key, parameterInfo->key, sizeof(parameterInfo->key));
    copyStringToBuffer(param.displayName, parameterInfo->displayName, sizeof(parameterInfo->displayName));
    copyStringToBuffer(param.description, parameterInfo->description, sizeof(parameterInfo->description));
    copyStringToBuffer(param.defaultValue, parameterInfo->defaultValue, sizeof(parameterInfo->defaultValue));

    parameterInfo->type = static_cast<int>(param.type);
    parameterInfo->minValue = param.minValue.value_or(0.0);
    parameterInfo->maxValue = param.maxValue.value_or(0.0);
    parameterInfo->step = param.step.value_or(1.0);
    parameterInfo->supportsValueCurve = param.supportsValueCurve;

    return true;
}

// ============================================================================
// Category management
// ============================================================================

int XLCoreGetCategoryCount(XLCoreEngineRef engine) {
    if (!engine) return 0;
    return static_cast<int>(EffectManager::instance().categories().size());
}

int XLCoreGetCategoryNameAtIndex(XLCoreEngineRef engine, int index,
                                  char* buffer, int bufferSize) {
    if (!engine) return 0;

    auto categories = EffectManager::instance().categories();
    if (index < 0 || index >= static_cast<int>(categories.size())) {
        return 0;
    }

    return copyStringToBuffer(categories[index], buffer, bufferSize);
}

int XLCoreGetEffectsInCategoryCount(XLCoreEngineRef engine, const char* categoryName) {
    if (!engine || !categoryName) return 0;

    auto effects = EffectManager::instance().effectsInCategory(categoryName);
    return static_cast<int>(effects.size());
}

int XLCoreGetEffectInCategoryAtIndex(XLCoreEngineRef engine, const char* categoryName,
                                      int index, char* buffer, int bufferSize) {
    if (!engine || !categoryName) return 0;

    auto effects = EffectManager::instance().effectsInCategory(categoryName);
    if (index < 0 || index >= static_cast<int>(effects.size())) {
        return 0;
    }

    return copyStringToBuffer(effects[index], buffer, bufferSize);
}

// ============================================================================
// Rendering
// ============================================================================

XLCoreRenderContextRef XLCoreRenderContextCreate(int width, int height) {
    if (width <= 0 || height <= 0) return nullptr;
    return new XLCoreRenderContext_(width, height);
}

void XLCoreRenderContextDestroy(XLCoreRenderContextRef context) {
    delete context;
}

void XLCoreRenderContextClear(XLCoreRenderContextRef context) {
    if (context) {
        context->context.clear();
    }
}

void XLCoreRenderContextClearTransparent(XLCoreRenderContextRef context) {
    if (context) {
        context->context.clearTransparent();
    }
}

int XLCoreRenderContextGetWidth(XLCoreRenderContextRef context) {
    return context ? context->context.width() : 0;
}

int XLCoreRenderContextGetHeight(XLCoreRenderContextRef context) {
    return context ? context->context.height() : 0;
}

const uint8_t* XLCoreRenderContextGetPixelData(XLCoreRenderContextRef context) {
    return context ? context->context.pixelData() : nullptr;
}

size_t XLCoreRenderContextGetPixelDataSize(XLCoreRenderContextRef context) {
    return context ? context->context.pixelDataSize() : 0;
}

bool XLCoreRenderEffect(XLCoreRenderContextRef context,
                         const char* effectName,
                         const char* settings,
                         double progress) {
    return XLCoreRenderEffectWithTiming(context, effectName, settings,
                                         progress, 0.0, 1.0, 0);
}

bool XLCoreRenderEffectWithTiming(XLCoreRenderContextRef context,
                                   const char* effectName,
                                   const char* settings,
                                   double timeSeconds,
                                   double effectStartTime,
                                   double effectEndTime,
                                   int frameIndex) {
    if (!context || !effectName) return false;

    // Create effect
    auto effect = EffectManager::instance().createEffect(effectName);
    if (!effect) return false;

    // Parse settings
    EffectSettings effectSettings;
    if (settings && settings[0] != '\0') {
        effectSettings = EffectSettings::fromString(settings);
    }

    // Apply defaults
    effectSettings = EffectManager::instance().applyDefaults(effectName, effectSettings);

    // Create render state
    RenderState state;
    state.timeSeconds = timeSeconds;
    state.effectStartTime = effectStartTime;
    state.effectEndTime = effectEndTime;
    state.frameIndex = frameIndex;
    state.bufferWidth = context->context.width();
    state.bufferHeight = context->context.height();
    state.updateProgress();

    // Render
    effect->prepareForRender(effectSettings);
    effect->render(context->context, effectSettings, state);
    effect->cleanupAfterRender();

    return true;
}

// ============================================================================
// Sequence operations
// ============================================================================

XLCoreSequenceRef XLCoreSequenceLoad(XLCoreEngineRef engine, const char* path) {
    if (!engine || !path) return nullptr;

    auto seq = new XLCoreSequence_();

    SequenceSerializer serializer;
    auto result = serializer.loadXLights(path, seq->sequence);

    if (!result.success()) {
        delete seq;
        return nullptr;
    }

    return seq;
}

XLCoreSequenceRef XLCoreSequenceCreate(XLCoreEngineRef engine,
                                        int durationMS,
                                        int frameIntervalMS) {
    if (!engine) return nullptr;

    auto seq = new XLCoreSequence_();
    seq->sequence.metadata.setDurationMS(durationMS);
    seq->sequence.metadata.frameIntervalMS = frameIntervalMS;

    return seq;
}

void XLCoreSequenceDestroy(XLCoreSequenceRef sequence) {
    delete sequence;
}

bool XLCoreSequenceSave(XLCoreSequenceRef sequence, const char* path) {
    if (!sequence || !path) return false;

    SequenceSerializer serializer;
    auto result = serializer.saveXLights(path, sequence->sequence);

    return result.success();
}

int XLCoreSequenceGetDuration(XLCoreSequenceRef sequence) {
    return sequence ? sequence->sequence.metadata.durationMS() : 0;
}

int XLCoreSequenceGetFrameInterval(XLCoreSequenceRef sequence) {
    return sequence ? sequence->sequence.metadata.frameIntervalMS : 50;
}

int XLCoreSequenceGetElementCount(XLCoreSequenceRef sequence) {
    return sequence ? static_cast<int>(sequence->sequence.elements.size()) : 0;
}

int XLCoreSequenceGetElementName(XLCoreSequenceRef sequence, int index,
                                  char* buffer, int bufferSize) {
    if (!sequence || index < 0 || index >= static_cast<int>(sequence->sequence.elements.size())) {
        return 0;
    }

    return copyStringToBuffer(sequence->sequence.elements[index].name, buffer, bufferSize);
}

// ============================================================================
// Render pipeline
// ============================================================================

void XLCoreSetupRenderPipeline(XLCoreEngineRef engine, XLCoreSequenceRef sequence) {
    if (!engine || !sequence) return;

    engine->pipeline.setSequence(sequence->sequence);
}

void XLCoreAddModelToPipeline(XLCoreEngineRef engine,
                               const char* modelName,
                               int bufferWidth,
                               int bufferHeight) {
    if (!engine || !modelName) return;

    engine->pipeline.addModel(modelName, bufferWidth, bufferHeight);
}

bool XLCoreRenderModelFrame(XLCoreEngineRef engine,
                             const char* modelName,
                             int timeMS,
                             uint8_t* buffer,
                             size_t bufferSize) {
    if (!engine || !modelName || !buffer) return false;

    auto frame = engine->pipeline.renderFrame(modelName, timeMS);

    if (frame.pixels.empty()) return false;

    size_t dataSize = frame.pixels.size() * sizeof(Color);
    if (bufferSize < dataSize) return false;

    std::memcpy(buffer, frame.pixels.data(), dataSize);
    return true;
}

void XLCoreRenderRange(XLCoreEngineRef engine,
                        int startMS,
                        int endMS,
                        XLCoreProgressCallback progressCallback,
                        XLCoreCompletionCallback completionCallback,
                        void* callbackContext) {
    if (!engine) return;

    // Wrap callbacks
    RenderProgressCallback progress = nullptr;
    if (progressCallback) {
        progress = [progressCallback, callbackContext](int current, int total, const std::string& message) {
            progressCallback(current, total, message.c_str(), callbackContext);
        };
    }

    RenderCompleteCallback complete = nullptr;
    if (completionCallback) {
        complete = [completionCallback, callbackContext](bool success, const std::string& message) {
            completionCallback(success, message.c_str(), callbackContext);
        };
    }

    engine->pipeline.renderRangeAsync(startMS, endMS, progress, complete);
}

void XLCoreAbortRender(XLCoreEngineRef engine) {
    if (engine) {
        engine->pipeline.abortRender();
    }
}

bool XLCoreIsRendering(XLCoreEngineRef engine) {
    return engine ? engine->pipeline.isRendering() : false;
}

// ============================================================================
// Statistics
// ============================================================================

void XLCoreGetRenderStatistics(XLCoreEngineRef engine, XLCoreRenderStatistics* stats) {
    if (!engine || !stats) return;

    auto pipelineStats = engine->pipeline.getStatistics();

    stats->framesRendered = pipelineStats.framesRendered;
    stats->cacheHits = pipelineStats.cacheHits;
    stats->cacheMisses = pipelineStats.cacheMisses;
    stats->avgRenderTimeMs = pipelineStats.avgRenderTimeMs;
    stats->totalRenderTimeMs = pipelineStats.totalRenderTimeMs;
}

void XLCoreResetRenderStatistics(XLCoreEngineRef engine) {
    if (engine) {
        engine->pipeline.resetStatistics();
    }
}

// ============================================================================
// Color utilities
// ============================================================================

bool XLCoreParseColor(const char* colorStr, uint8_t* r, uint8_t* g, uint8_t* b) {
    if (!colorStr || !r || !g || !b) return false;

    Color c(colorStr);
    *r = c.red;
    *g = c.green;
    *b = c.blue;

    return true;
}

int XLCoreColorToString(uint8_t r, uint8_t g, uint8_t b, char* buffer, int bufferSize) {
    Color c(r, g, b);
    return copyStringToBuffer(c.toString(), buffer, bufferSize);
}

void XLCoreHSVToRGB(double h, double s, double v, uint8_t* r, uint8_t* g, uint8_t* b) {
    if (!r || !g || !b) return;

    HSV hsv;
    hsv.hue = h;
    hsv.saturation = s;
    hsv.value = v;

    Color c(hsv);
    *r = c.red;
    *g = c.green;
    *b = c.blue;
}

void XLCoreRGBToHSV(uint8_t r, uint8_t g, uint8_t b, double* h, double* s, double* v) {
    if (!h || !s || !v) return;

    Color c(r, g, b);
    HSV hsv = c.toHSV();

    *h = hsv.hue;
    *s = hsv.saturation;
    *v = hsv.value;
}
