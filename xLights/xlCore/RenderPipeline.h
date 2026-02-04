/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

/**
 * @file RenderPipeline.h
 * @brief Effect rendering orchestration for xlCore.
 *
 * The RenderPipeline manages:
 * - Per-model effect rendering
 * - Multi-layer blending
 * - Frame buffer management
 * - Parallel rendering across models
 * - Render caching for performance
 *
 * This replaces the legacy wxWidgets-dependent rendering system
 * with a pure C++ implementation suitable for the native macOS app.
 */

#include <string>
#include <vector>
#include <unordered_map>
#include <memory>
#include <mutex>
#include <atomic>
#include <functional>
#include <future>
#include <thread>
#include <condition_variable>
#include <queue>
#include <random>

#include "Types.h"
#include "Color.h"
#include "RenderContext.h"
#include "EffectManager.h"
#include "Sequence.h"
#include "Model.h"

namespace xlCore {

// Forward declarations
class AudioAnalyzer;

/**
 * @brief Blend modes for layer mixing.
 */
enum class BlendMode {
    Normal,         ///< Standard alpha blend
    Effect1,        ///< Average (50/50 blend)
    Effect2,        ///< Mask with effect on bottom
    Add,            ///< Additive blending
    Subtract,       ///< Subtractive blending
    Multiply,       ///< Multiplicative blending
    Screen,         ///< Screen blending
    Max,            ///< Maximum of each channel
    Min,            ///< Minimum of each channel
    Shadow,         ///< Shadow effect (darken)
    Highlight,      ///< Highlight effect (lighten)
    Unmask,         ///< Unmask with effect on bottom
    AsBrightness    ///< Use as brightness modifier
};

/**
 * @brief Layer configuration for rendering.
 */
struct LayerConfig {
    std::string effectType;     ///< Effect type name
    EffectSettings settings;    ///< Effect settings
    ColorPalette palette;       ///< Color palette
    BlendMode blendMode = BlendMode::Normal;
    int blendValue = 0;         ///< Blend value (0-100)
    double fadeInTime = 0.0;    ///< Fade in duration (seconds)
    double fadeOutTime = 0.0;   ///< Fade out duration (seconds)
    bool sparkles = false;      ///< Enable sparkle effect
    int sparklePercent = 0;     ///< Sparkle percentage (0-200)
    double brightness = 100.0;  ///< Layer brightness (0-100)
    double contrast = 0.0;      ///< Layer contrast (-100 to 100)
    bool mirrorH = false;       ///< Horizontal mirror
    bool mirrorV = false;       ///< Vertical mirror
    double zoomX = 100.0;       ///< Horizontal zoom (0-300)
    double zoomY = 100.0;       ///< Vertical zoom (0-300)
    double rotation = 0.0;      ///< Rotation in degrees (-360 to 360)
    int pivotX = 50;            ///< Pivot X (0-100)
    int pivotY = 50;            ///< Pivot Y (0-100)
};

/**
 * @brief Model render configuration.
 */
struct ModelRenderConfig {
    std::string modelName;
    int bufferWidth = 0;
    int bufferHeight = 0;
    std::vector<LayerConfig> layers;
};

/**
 * @brief Rendered frame result for a model.
 */
struct RenderedFrame {
    std::string modelName;
    int width = 0;
    int height = 0;
    int timeMS = 0;
    std::vector<Color> pixels;  ///< RGBA pixel data

    /**
     * @brief Get pixel data as raw bytes for GPU upload.
     */
    const uint8_t* pixelData() const {
        return reinterpret_cast<const uint8_t*>(pixels.data());
    }

    /**
     * @brief Get pixel data size in bytes.
     */
    size_t pixelDataSize() const {
        return pixels.size() * sizeof(Color);
    }
};

/**
 * @brief Render progress callback type.
 */
using RenderProgressCallback = std::function<void(int current, int total, const std::string& message)>;

/**
 * @brief Render completion callback type.
 */
using RenderCompleteCallback = std::function<void(bool success, const std::string& message)>;

/**
 * @brief Render job for a single frame/model.
 */
struct RenderJob {
    std::string modelName;
    int timeMS = 0;
    int frameIndex = 0;
    ModelRenderConfig config;
    std::promise<RenderedFrame> promise;
};

/**
 * @brief Render cache key.
 */
struct RenderCacheKey {
    std::string modelName;
    int timeMS;
    uint64_t settingsHash;

    bool operator==(const RenderCacheKey& other) const {
        return modelName == other.modelName &&
               timeMS == other.timeMS &&
               settingsHash == other.settingsHash;
    }
};

/**
 * @brief Hash function for RenderCacheKey.
 */
struct RenderCacheKeyHash {
    size_t operator()(const RenderCacheKey& key) const {
        size_t h1 = std::hash<std::string>{}(key.modelName);
        size_t h2 = std::hash<int>{}(key.timeMS);
        size_t h3 = std::hash<uint64_t>{}(key.settingsHash);
        return h1 ^ (h2 << 1) ^ (h3 << 2);
    }
};

/**
 * @brief Effect rendering orchestration.
 *
 * The RenderPipeline coordinates effect rendering across models,
 * handles layer blending, and manages render caching.
 *
 * Usage:
 * 1. Create pipeline with sequence data
 * 2. Configure models and their effects
 * 3. Call renderFrame() for single frames or renderRange() for batch
 * 4. Retrieve rendered frames via callbacks or getRenderedFrame()
 *
 * Thread safety:
 * - The pipeline is thread-safe for concurrent renderFrame() calls
 * - Different models can be rendered in parallel
 * - Same model/time combinations are serialized
 */
class RenderPipeline {
public:
    RenderPipeline();
    ~RenderPipeline();

    // Non-copyable
    RenderPipeline(const RenderPipeline&) = delete;
    RenderPipeline& operator=(const RenderPipeline&) = delete;

    // ========== Configuration ==========

    /**
     * @brief Set the sequence to render.
     */
    void setSequence(const Sequence& sequence);

    /**
     * @brief Set the sequence timing parameters.
     */
    void setTiming(int durationMS, int frameIntervalMS);

    /**
     * @brief Add a model to render.
     */
    void addModel(const std::string& name, int bufferWidth, int bufferHeight);

    /**
     * @brief Remove a model from rendering.
     */
    void removeModel(const std::string& name);

    /**
     * @brief Clear all models.
     */
    void clearModels();

    /**
     * @brief Configure layers for a model.
     */
    void setModelLayers(const std::string& modelName, const std::vector<LayerConfig>& layers);

    /**
     * @brief Get current layers for a model.
     */
    std::vector<LayerConfig> getModelLayers(const std::string& modelName) const;

    // ========== Audio Integration ==========

    /**
     * @brief Set audio analyzer for audio-reactive effects.
     */
    void setAudioAnalyzer(std::shared_ptr<AudioAnalyzer> analyzer);

    // ========== Single Frame Rendering ==========

    /**
     * @brief Render a single frame for a model.
     *
     * @param modelName Model to render
     * @param timeMS Time in milliseconds
     * @return Rendered frame data
     */
    RenderedFrame renderFrame(const std::string& modelName, int timeMS);

    /**
     * @brief Render all models at a specific time.
     *
     * @param timeMS Time in milliseconds
     * @return Map of model name to rendered frame
     */
    std::unordered_map<std::string, RenderedFrame> renderAllModels(int timeMS);

    /**
     * @brief Render frame asynchronously.
     */
    std::future<RenderedFrame> renderFrameAsync(const std::string& modelName, int timeMS);

    // ========== Batch Rendering ==========

    /**
     * @brief Render all frames in a time range.
     *
     * @param startMS Start time in milliseconds
     * @param endMS End time in milliseconds
     * @param progressCallback Optional progress callback
     */
    void renderRange(int startMS, int endMS, RenderProgressCallback progressCallback = nullptr);

    /**
     * @brief Render all frames asynchronously.
     */
    void renderRangeAsync(int startMS, int endMS,
                          RenderProgressCallback progressCallback = nullptr,
                          RenderCompleteCallback completeCallback = nullptr);

    /**
     * @brief Render entire sequence.
     */
    void renderAll(RenderProgressCallback progressCallback = nullptr);

    /**
     * @brief Abort rendering in progress.
     */
    void abortRender();

    /**
     * @brief Check if rendering is in progress.
     */
    bool isRendering() const { return m_rendering.load(); }

    // ========== Render Cache ==========

    /**
     * @brief Enable/disable render caching.
     */
    void setCacheEnabled(bool enabled) { m_cacheEnabled = enabled; }
    bool isCacheEnabled() const { return m_cacheEnabled; }

    /**
     * @brief Clear the render cache.
     */
    void clearCache();

    /**
     * @brief Clear cache for a specific model.
     */
    void clearCacheForModel(const std::string& modelName);

    /**
     * @brief Clear cache for a time range.
     */
    void clearCacheForRange(int startMS, int endMS);

    /**
     * @brief Set maximum cache size (number of frames).
     */
    void setMaxCacheSize(size_t maxFrames) { m_maxCacheSize = maxFrames; }

    // ========== Rendered Frame Access ==========

    /**
     * @brief Get a previously rendered frame from cache.
     *
     * @return Frame if cached, empty optional otherwise
     */
    std::optional<RenderedFrame> getCachedFrame(const std::string& modelName, int timeMS);

    /**
     * @brief Get raw pixel data for a model at a time (for hardware output).
     */
    std::vector<uint8_t> getOutputData(const std::string& modelName, int timeMS);

    // ========== Statistics ==========

    /**
     * @brief Get render statistics.
     */
    struct Statistics {
        size_t framesRendered = 0;
        size_t cacheHits = 0;
        size_t cacheMisses = 0;
        double avgRenderTimeMs = 0.0;
        double totalRenderTimeMs = 0.0;
    };

    Statistics getStatistics() const;
    void resetStatistics();

    // ========== Thread Pool Control ==========

    /**
     * @brief Set number of render threads (0 = auto based on CPU cores).
     */
    void setThreadCount(int count);

    /**
     * @brief Get current thread count.
     */
    int threadCount() const { return m_threadCount; }

private:
    // Internal rendering methods
    RenderedFrame renderFrameInternal(const ModelRenderConfig& config, int timeMS);
    void renderLayer(RenderContext& ctx, const LayerConfig& layer,
                     const RenderState& state);
    void blendLayers(RenderContext& dest, const RenderContext& src,
                     BlendMode mode, int blendValue, double fade);
    void applyTransforms(RenderContext& ctx, const LayerConfig& layer);

    // Cache management
    uint64_t computeSettingsHash(const ModelRenderConfig& config) const;
    void pruneCache();

    // Thread pool
    void initializeThreadPool();
    void shutdownThreadPool();
    void workerThread();

    // Configuration
    std::unordered_map<std::string, ModelRenderConfig> m_modelConfigs;
    mutable std::mutex m_configMutex;

    // Timing
    int m_durationMS = 0;
    int m_frameIntervalMS = 50;

    // Audio
    std::shared_ptr<AudioAnalyzer> m_audioAnalyzer;

    // Cache
    std::unordered_map<RenderCacheKey, RenderedFrame, RenderCacheKeyHash> m_cache;
    mutable std::mutex m_cacheMutex;
    bool m_cacheEnabled = true;
    size_t m_maxCacheSize = 10000;

    // Thread pool
    std::vector<std::thread> m_threads;
    std::queue<RenderJob> m_jobQueue;
    std::mutex m_queueMutex;
    std::condition_variable m_queueCondition;
    std::atomic<bool> m_running{false};
    std::atomic<bool> m_rendering{false};
    std::atomic<bool> m_abortRequested{false};
    int m_threadCount = 0;

    // Statistics
    mutable std::mutex m_statsMutex;
    Statistics m_stats;
};

/**
 * @brief Convenience function to render a single effect for preview.
 *
 * Creates a temporary pipeline and renders the effect.
 */
RenderedFrame renderEffectPreview(
    const std::string& effectType,
    const EffectSettings& settings,
    int width, int height,
    double progress = 0.5);

} // namespace xlCore
