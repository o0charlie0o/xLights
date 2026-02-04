/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "RenderPipeline.h"
#include "EffectManager.h"

#include <chrono>
#include <algorithm>
#include <cmath>
#include <functional>

namespace xlCore {

// ============================================================================
// RenderPipeline Implementation
// ============================================================================

RenderPipeline::RenderPipeline() {
    // Determine optimal thread count
    m_threadCount = std::max(1, static_cast<int>(std::thread::hardware_concurrency()) - 1);
}

RenderPipeline::~RenderPipeline() {
    shutdownThreadPool();
}

void RenderPipeline::setSequence(const Sequence& sequence) {
    std::lock_guard<std::mutex> lock(m_configMutex);

    m_durationMS = sequence.metadata.durationMS();
    m_frameIntervalMS = sequence.metadata.frameIntervalMS;

    // Clear cache when sequence changes
    clearCache();
}

void RenderPipeline::setTiming(int durationMS, int frameIntervalMS) {
    std::lock_guard<std::mutex> lock(m_configMutex);

    m_durationMS = durationMS;
    m_frameIntervalMS = frameIntervalMS;
}

void RenderPipeline::addModel(const std::string& name, int bufferWidth, int bufferHeight) {
    std::lock_guard<std::mutex> lock(m_configMutex);

    ModelRenderConfig config;
    config.modelName = name;
    config.bufferWidth = bufferWidth;
    config.bufferHeight = bufferHeight;

    m_modelConfigs[name] = config;
}

void RenderPipeline::removeModel(const std::string& name) {
    std::lock_guard<std::mutex> lock(m_configMutex);
    m_modelConfigs.erase(name);
    clearCacheForModel(name);
}

void RenderPipeline::clearModels() {
    std::lock_guard<std::mutex> lock(m_configMutex);
    m_modelConfigs.clear();
    clearCache();
}

void RenderPipeline::setModelLayers(const std::string& modelName, const std::vector<LayerConfig>& layers) {
    std::lock_guard<std::mutex> lock(m_configMutex);

    auto it = m_modelConfigs.find(modelName);
    if (it != m_modelConfigs.end()) {
        it->second.layers = layers;
        clearCacheForModel(modelName);
    }
}

std::vector<LayerConfig> RenderPipeline::getModelLayers(const std::string& modelName) const {
    std::lock_guard<std::mutex> lock(m_configMutex);

    auto it = m_modelConfigs.find(modelName);
    if (it != m_modelConfigs.end()) {
        return it->second.layers;
    }
    return {};
}

void RenderPipeline::setAudioAnalyzer(std::shared_ptr<AudioAnalyzer> analyzer) {
    m_audioAnalyzer = analyzer;
}

RenderedFrame RenderPipeline::renderFrame(const std::string& modelName, int timeMS) {
    // Get model config
    ModelRenderConfig config;
    {
        std::lock_guard<std::mutex> lock(m_configMutex);
        auto it = m_modelConfigs.find(modelName);
        if (it == m_modelConfigs.end()) {
            // Return empty frame for unknown model
            RenderedFrame empty;
            empty.modelName = modelName;
            empty.timeMS = timeMS;
            return empty;
        }
        config = it->second;
    }

    // Check cache
    if (m_cacheEnabled) {
        RenderCacheKey key{modelName, timeMS, computeSettingsHash(config)};
        std::lock_guard<std::mutex> cacheLock(m_cacheMutex);
        auto it = m_cache.find(key);
        if (it != m_cache.end()) {
            std::lock_guard<std::mutex> statsLock(m_statsMutex);
            m_stats.cacheHits++;
            return it->second;
        }
    }

    // Render the frame
    auto startTime = std::chrono::high_resolution_clock::now();

    RenderedFrame result = renderFrameInternal(config, timeMS);

    auto endTime = std::chrono::high_resolution_clock::now();
    double renderTimeMs = std::chrono::duration<double, std::milli>(endTime - startTime).count();

    // Update statistics
    {
        std::lock_guard<std::mutex> statsLock(m_statsMutex);
        m_stats.framesRendered++;
        m_stats.cacheMisses++;
        m_stats.totalRenderTimeMs += renderTimeMs;
        m_stats.avgRenderTimeMs = m_stats.totalRenderTimeMs / m_stats.framesRendered;
    }

    // Cache the result
    if (m_cacheEnabled) {
        RenderCacheKey key{modelName, timeMS, computeSettingsHash(config)};
        std::lock_guard<std::mutex> cacheLock(m_cacheMutex);
        m_cache[key] = result;
        pruneCache();
    }

    return result;
}

std::unordered_map<std::string, RenderedFrame> RenderPipeline::renderAllModels(int timeMS) {
    std::unordered_map<std::string, RenderedFrame> results;

    std::vector<std::string> modelNames;
    {
        std::lock_guard<std::mutex> lock(m_configMutex);
        for (const auto& [name, config] : m_modelConfigs) {
            modelNames.push_back(name);
        }
    }

    // Render each model (could be parallelized)
    for (const auto& name : modelNames) {
        results[name] = renderFrame(name, timeMS);
    }

    return results;
}

std::future<RenderedFrame> RenderPipeline::renderFrameAsync(const std::string& modelName, int timeMS) {
    // Simple async implementation using std::async
    return std::async(std::launch::async, [this, modelName, timeMS]() {
        return renderFrame(modelName, timeMS);
    });
}

void RenderPipeline::renderRange(int startMS, int endMS, RenderProgressCallback progressCallback) {
    m_rendering = true;
    m_abortRequested = false;

    int totalFrames = (endMS - startMS) / m_frameIntervalMS;
    int currentFrame = 0;

    for (int timeMS = startMS; timeMS < endMS && !m_abortRequested; timeMS += m_frameIntervalMS) {
        renderAllModels(timeMS);
        currentFrame++;

        if (progressCallback) {
            progressCallback(currentFrame, totalFrames,
                           "Rendering frame " + std::to_string(currentFrame) + " of " + std::to_string(totalFrames));
        }
    }

    m_rendering = false;
}

void RenderPipeline::renderRangeAsync(int startMS, int endMS,
                                       RenderProgressCallback progressCallback,
                                       RenderCompleteCallback completeCallback) {
    std::thread([this, startMS, endMS, progressCallback, completeCallback]() {
        try {
            renderRange(startMS, endMS, progressCallback);
            if (completeCallback) {
                completeCallback(true, "Render complete");
            }
        } catch (const std::exception& e) {
            if (completeCallback) {
                completeCallback(false, std::string("Render failed: ") + e.what());
            }
        }
    }).detach();
}

void RenderPipeline::renderAll(RenderProgressCallback progressCallback) {
    renderRange(0, m_durationMS, progressCallback);
}

void RenderPipeline::abortRender() {
    m_abortRequested = true;
}

void RenderPipeline::clearCache() {
    std::lock_guard<std::mutex> lock(m_cacheMutex);
    m_cache.clear();
}

void RenderPipeline::clearCacheForModel(const std::string& modelName) {
    std::lock_guard<std::mutex> lock(m_cacheMutex);

    for (auto it = m_cache.begin(); it != m_cache.end();) {
        if (it->first.modelName == modelName) {
            it = m_cache.erase(it);
        } else {
            ++it;
        }
    }
}

void RenderPipeline::clearCacheForRange(int startMS, int endMS) {
    std::lock_guard<std::mutex> lock(m_cacheMutex);

    for (auto it = m_cache.begin(); it != m_cache.end();) {
        if (it->first.timeMS >= startMS && it->first.timeMS < endMS) {
            it = m_cache.erase(it);
        } else {
            ++it;
        }
    }
}

std::optional<RenderedFrame> RenderPipeline::getCachedFrame(const std::string& modelName, int timeMS) {
    if (!m_cacheEnabled) {
        return std::nullopt;
    }

    ModelRenderConfig config;
    {
        std::lock_guard<std::mutex> lock(m_configMutex);
        auto it = m_modelConfigs.find(modelName);
        if (it == m_modelConfigs.end()) {
            return std::nullopt;
        }
        config = it->second;
    }

    RenderCacheKey key{modelName, timeMS, computeSettingsHash(config)};

    std::lock_guard<std::mutex> lock(m_cacheMutex);
    auto it = m_cache.find(key);
    if (it != m_cache.end()) {
        return it->second;
    }

    return std::nullopt;
}

std::vector<uint8_t> RenderPipeline::getOutputData(const std::string& modelName, int timeMS) {
    auto frame = renderFrame(modelName, timeMS);
    std::vector<uint8_t> result;
    result.reserve(frame.pixels.size() * 3); // RGB only (no alpha for output)

    for (const auto& pixel : frame.pixels) {
        result.push_back(pixel.red);
        result.push_back(pixel.green);
        result.push_back(pixel.blue);
    }

    return result;
}

RenderPipeline::Statistics RenderPipeline::getStatistics() const {
    std::lock_guard<std::mutex> lock(m_statsMutex);
    return m_stats;
}

void RenderPipeline::resetStatistics() {
    std::lock_guard<std::mutex> lock(m_statsMutex);
    m_stats = Statistics{};
}

void RenderPipeline::setThreadCount(int count) {
    if (count <= 0) {
        m_threadCount = std::max(1, static_cast<int>(std::thread::hardware_concurrency()) - 1);
    } else {
        m_threadCount = count;
    }
}

// ============================================================================
// Internal Rendering Methods
// ============================================================================

RenderedFrame RenderPipeline::renderFrameInternal(const ModelRenderConfig& config, int timeMS) {
    RenderedFrame result;
    result.modelName = config.modelName;
    result.width = config.bufferWidth;
    result.height = config.bufferHeight;
    result.timeMS = timeMS;

    if (config.bufferWidth <= 0 || config.bufferHeight <= 0) {
        return result;
    }

    // Create render context
    RenderContext ctx(config.bufferWidth, config.bufferHeight);
    ctx.clearTransparent();

    // Create render state
    RenderState state;
    state.timeSeconds = timeMS / 1000.0;
    state.bufferWidth = config.bufferWidth;
    state.bufferHeight = config.bufferHeight;
    state.sequenceFrameIndex = timeMS / m_frameIntervalMS;

    // Render each layer
    for (size_t layerIdx = 0; layerIdx < config.layers.size(); ++layerIdx) {
        const auto& layer = config.layers[layerIdx];

        if (layer.effectType.empty()) {
            continue;
        }

        // Create layer render context
        RenderContext layerCtx(config.bufferWidth, config.bufferHeight);
        layerCtx.clearTransparent();

        // Update render state for this layer
        RenderState layerState = state;
        layerState.frameIndex = layerIdx;

        // Render the effect
        renderLayer(layerCtx, layer, layerState);

        // Apply transforms (zoom, rotation, mirror)
        applyTransforms(layerCtx, layer);

        // Blend layer onto main context
        double fade = 1.0;
        // TODO: Calculate fade based on fadeInTime/fadeOutTime and current position

        blendLayers(ctx, layerCtx, layer.blendMode, layer.blendValue, fade);
    }

    // Copy pixels to result
    size_t pixelCount = static_cast<size_t>(config.bufferWidth) * config.bufferHeight;
    result.pixels.resize(pixelCount);

    const Color* ctxPixels = ctx.pixels();
    for (size_t i = 0; i < pixelCount; ++i) {
        result.pixels[i] = ctxPixels[i];
    }

    return result;
}

void RenderPipeline::renderLayer(RenderContext& ctx, const LayerConfig& layer,
                                  const RenderState& state) {
    // Get effect instance from thread pool
    EffectPool& pool = EffectManager::instance().getThreadPool();
    EffectInstance* instance = pool.getInstance(layer.effectType, layer.settings);

    if (!instance) {
        return;
    }

    // Update state with effect timing (would come from SequenceEffect in real use)
    RenderState effectState = state;
    effectState.effectStartTime = 0.0;
    effectState.effectEndTime = m_durationMS / 1000.0;
    effectState.updateProgress();

    // Render the effect
    instance->render(ctx, effectState);

    // Apply brightness/contrast
    if (std::abs(layer.brightness - 100.0) > 0.001 || std::abs(layer.contrast) > 0.001) {
        double brightnessFactor = layer.brightness / 100.0;
        double contrastFactor = (100.0 + layer.contrast) / 100.0;

        for (int y = 0; y < ctx.height(); ++y) {
            for (int x = 0; x < ctx.width(); ++x) {
                Color c = ctx.getPixel(x, y);

                // Apply contrast (centered at 128)
                int r = static_cast<int>((c.red - 128) * contrastFactor + 128);
                int g = static_cast<int>((c.green - 128) * contrastFactor + 128);
                int b = static_cast<int>((c.blue - 128) * contrastFactor + 128);

                // Apply brightness
                r = static_cast<int>(r * brightnessFactor);
                g = static_cast<int>(g * brightnessFactor);
                b = static_cast<int>(b * brightnessFactor);

                // Clamp
                c.red = static_cast<uint8_t>(std::clamp(r, 0, 255));
                c.green = static_cast<uint8_t>(std::clamp(g, 0, 255));
                c.blue = static_cast<uint8_t>(std::clamp(b, 0, 255));

                ctx.setPixel(x, y, c);
            }
        }
    }

    // Apply sparkles
    if (layer.sparkles && layer.sparklePercent > 0) {
        static thread_local std::mt19937 rng(std::random_device{}());
        std::uniform_int_distribution<int> dist(0, 100);

        for (int y = 0; y < ctx.height(); ++y) {
            for (int x = 0; x < ctx.width(); ++x) {
                if (dist(rng) < layer.sparklePercent) {
                    Color c = ctx.getPixel(x, y);
                    // Sparkle: brighten the pixel
                    c.red = 255;
                    c.green = 255;
                    c.blue = 255;
                    ctx.setPixel(x, y, c);
                }
            }
        }
    }
}

void RenderPipeline::blendLayers(RenderContext& dest, const RenderContext& src,
                                  BlendMode mode, int blendValue, double fade) {
    if (src.width() != dest.width() || src.height() != dest.height()) {
        return;
    }

    double alpha = fade * (blendValue / 100.0);
    alpha = std::clamp(alpha, 0.0, 1.0);

    for (int y = 0; y < dest.height(); ++y) {
        for (int x = 0; x < dest.width(); ++x) {
            Color d = dest.getPixel(x, y);
            Color s = src.getPixel(x, y);
            Color result;

            switch (mode) {
                case BlendMode::Normal:
                default: {
                    // Standard alpha blend
                    double srcAlpha = (s.alpha / 255.0) * alpha;
                    double dstAlpha = d.alpha / 255.0;
                    double outAlpha = srcAlpha + dstAlpha * (1.0 - srcAlpha);

                    if (outAlpha > 0.001) {
                        result.red = static_cast<uint8_t>((s.red * srcAlpha + d.red * dstAlpha * (1.0 - srcAlpha)) / outAlpha);
                        result.green = static_cast<uint8_t>((s.green * srcAlpha + d.green * dstAlpha * (1.0 - srcAlpha)) / outAlpha);
                        result.blue = static_cast<uint8_t>((s.blue * srcAlpha + d.blue * dstAlpha * (1.0 - srcAlpha)) / outAlpha);
                        result.alpha = static_cast<uint8_t>(outAlpha * 255);
                    } else {
                        result = d;
                    }
                    break;
                }

                case BlendMode::Add:
                    result.red = static_cast<uint8_t>(std::min(255, d.red + static_cast<int>(s.red * alpha)));
                    result.green = static_cast<uint8_t>(std::min(255, d.green + static_cast<int>(s.green * alpha)));
                    result.blue = static_cast<uint8_t>(std::min(255, d.blue + static_cast<int>(s.blue * alpha)));
                    result.alpha = std::max(d.alpha, s.alpha);
                    break;

                case BlendMode::Subtract:
                    result.red = static_cast<uint8_t>(std::max(0, d.red - static_cast<int>(s.red * alpha)));
                    result.green = static_cast<uint8_t>(std::max(0, d.green - static_cast<int>(s.green * alpha)));
                    result.blue = static_cast<uint8_t>(std::max(0, d.blue - static_cast<int>(s.blue * alpha)));
                    result.alpha = d.alpha;
                    break;

                case BlendMode::Multiply:
                    result.red = static_cast<uint8_t>((d.red * s.red) / 255);
                    result.green = static_cast<uint8_t>((d.green * s.green) / 255);
                    result.blue = static_cast<uint8_t>((d.blue * s.blue) / 255);
                    result.alpha = std::max(d.alpha, s.alpha);
                    break;

                case BlendMode::Screen:
                    result.red = static_cast<uint8_t>(255 - ((255 - d.red) * (255 - s.red)) / 255);
                    result.green = static_cast<uint8_t>(255 - ((255 - d.green) * (255 - s.green)) / 255);
                    result.blue = static_cast<uint8_t>(255 - ((255 - d.blue) * (255 - s.blue)) / 255);
                    result.alpha = std::max(d.alpha, s.alpha);
                    break;

                case BlendMode::Max:
                    result.red = std::max(d.red, s.red);
                    result.green = std::max(d.green, s.green);
                    result.blue = std::max(d.blue, s.blue);
                    result.alpha = std::max(d.alpha, s.alpha);
                    break;

                case BlendMode::Min:
                    result.red = std::min(d.red, s.red);
                    result.green = std::min(d.green, s.green);
                    result.blue = std::min(d.blue, s.blue);
                    result.alpha = std::max(d.alpha, s.alpha);
                    break;

                case BlendMode::Effect1: // Average
                    result.red = static_cast<uint8_t>((d.red + s.red) / 2);
                    result.green = static_cast<uint8_t>((d.green + s.green) / 2);
                    result.blue = static_cast<uint8_t>((d.blue + s.blue) / 2);
                    result.alpha = std::max(d.alpha, s.alpha);
                    break;

                case BlendMode::Shadow:
                    // Darken
                    result.red = std::min(d.red, s.red);
                    result.green = std::min(d.green, s.green);
                    result.blue = std::min(d.blue, s.blue);
                    result.alpha = std::max(d.alpha, s.alpha);
                    break;

                case BlendMode::Highlight:
                    // Lighten
                    result.red = std::max(d.red, s.red);
                    result.green = std::max(d.green, s.green);
                    result.blue = std::max(d.blue, s.blue);
                    result.alpha = std::max(d.alpha, s.alpha);
                    break;
            }

            dest.setPixel(x, y, result);
        }
    }
}

void RenderPipeline::applyTransforms(RenderContext& ctx, const LayerConfig& layer) {
    // Apply mirrors
    if (layer.mirrorH) {
        for (int y = 0; y < ctx.height(); ++y) {
            for (int x = 0; x < ctx.width() / 2; ++x) {
                int mirrorX = ctx.width() - 1 - x;
                Color temp = ctx.getPixel(x, y);
                ctx.setPixel(x, y, ctx.getPixel(mirrorX, y));
                ctx.setPixel(mirrorX, y, temp);
            }
        }
    }

    if (layer.mirrorV) {
        for (int y = 0; y < ctx.height() / 2; ++y) {
            for (int x = 0; x < ctx.width(); ++x) {
                int mirrorY = ctx.height() - 1 - y;
                Color temp = ctx.getPixel(x, y);
                ctx.setPixel(x, y, ctx.getPixel(x, mirrorY));
                ctx.setPixel(x, mirrorY, temp);
            }
        }
    }

    // TODO: Implement zoom and rotation transforms
    // These require more complex pixel interpolation
}

uint64_t RenderPipeline::computeSettingsHash(const ModelRenderConfig& config) const {
    std::hash<std::string> strHash;
    uint64_t hash = strHash(config.modelName);

    for (const auto& layer : config.layers) {
        hash ^= strHash(layer.effectType) << 1;
        hash ^= strHash(layer.settings.toString()) << 2;
        hash ^= static_cast<uint64_t>(layer.blendMode) << 3;
        hash ^= static_cast<uint64_t>(layer.blendValue) << 4;
    }

    return hash;
}

void RenderPipeline::pruneCache() {
    // Simple LRU-like pruning: remove oldest entries if over limit
    if (m_cache.size() > m_maxCacheSize) {
        // For simplicity, just clear half the cache
        // A real implementation would use proper LRU tracking
        size_t toRemove = m_cache.size() / 2;
        auto it = m_cache.begin();
        while (toRemove > 0 && it != m_cache.end()) {
            it = m_cache.erase(it);
            --toRemove;
        }
    }
}

void RenderPipeline::initializeThreadPool() {
    if (m_running) return;

    m_running = true;
    m_threads.reserve(m_threadCount);

    for (int i = 0; i < m_threadCount; ++i) {
        m_threads.emplace_back(&RenderPipeline::workerThread, this);
    }
}

void RenderPipeline::shutdownThreadPool() {
    {
        std::lock_guard<std::mutex> lock(m_queueMutex);
        m_running = false;
    }
    m_queueCondition.notify_all();

    for (auto& thread : m_threads) {
        if (thread.joinable()) {
            thread.join();
        }
    }
    m_threads.clear();
}

void RenderPipeline::workerThread() {
    while (true) {
        RenderJob job;
        {
            std::unique_lock<std::mutex> lock(m_queueMutex);
            m_queueCondition.wait(lock, [this]() {
                return !m_running || !m_jobQueue.empty();
            });

            if (!m_running && m_jobQueue.empty()) {
                return;
            }

            job = std::move(m_jobQueue.front());
            m_jobQueue.pop();
        }

        // Execute the job
        RenderedFrame result = renderFrameInternal(job.config, job.timeMS);
        job.promise.set_value(std::move(result));
    }
}

// ============================================================================
// Convenience Functions
// ============================================================================

RenderedFrame renderEffectPreview(
    const std::string& effectType,
    const EffectSettings& settings,
    int width, int height,
    double progress) {

    RenderedFrame result;
    result.width = width;
    result.height = height;
    result.timeMS = 0;

    if (width <= 0 || height <= 0) {
        return result;
    }

    // Create effect
    auto& manager = EffectManager::instance();
    auto effect = manager.createEffect(effectType);
    if (!effect) {
        return result;
    }

    // Create render context
    RenderContext ctx(width, height);
    ctx.clearTransparent();

    // Create render state
    RenderState state;
    state.timeSeconds = progress;
    state.effectStartTime = 0.0;
    state.effectEndTime = 1.0;
    state.progress = progress;
    state.bufferWidth = width;
    state.bufferHeight = height;

    // Render
    effect->prepareForRender(settings);
    effect->render(ctx, settings, state);
    effect->cleanupAfterRender();

    // Copy pixels
    size_t pixelCount = static_cast<size_t>(width) * height;
    result.pixels.resize(pixelCount);

    const Color* ctxPixels = ctx.pixels();
    for (size_t i = 0; i < pixelCount; ++i) {
        result.pixels[i] = ctxPixels[i];
    }

    return result;
}

} // namespace xlCore
