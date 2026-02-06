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

// NativeRenderCoordinator: Parallel rendering orchestrator for the native macOS build.
//
// Dispatches per-model render jobs across multiple threads using a work-stealing
// pattern. Each model gets its own NativePixelBuffer and renders all frames
// independently. The output is written to a shared NativeSequenceData buffer
// (non-overlapping channel ranges per model ensure thread safety).
//
// Architecture:
//   - IEffectProvider supplies sequence elements and effect data
//   - IModelProvider supplies model geometry and channel mapping
//   - IRenderContext supplies timing and audio info
//   - Each model's render job:
//       For each frame:
//         For each layer: query effect, configure buffer, call Render()
//         NativePixelBuffer::calcOutput() blends layers
//         NativePixelBuffer::getColors() writes to NativeSequenceData
//
// Thread safety: renderRange() and renderAll() block until complete.
// Multiple threads render different models in parallel. abort() is safe
// to call from any thread.

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "NativePixelBuffer.h"

class NativeSequenceData;
class NativeRenderBuffer;

namespace xlEngine {

struct EffectInstanceInfo;
class IEffectProvider;
class IModelProvider;

// Callback interface for render progress and completion events.
class RenderCoordinatorListener {
public:
    virtual ~RenderCoordinatorListener() = default;
    virtual void onModelFrameRendered(const std::string& modelName, int timeMS) {}
    virtual void onFrameRendered(int timeMS) {}
    virtual void onRenderComplete(bool wasCancelled) {}
    virtual void onRenderProgress(float percent, int modelsComplete, int modelsTotal) {}
    virtual void onRenderError(const std::string& modelName, const std::string& message) {}
};

// A rendered frame snapshot for a single model (pixel data as RGBA).
struct RenderedFrame {
    std::string modelName;
    int width = 0;
    int height = 0;
    int timeMS = 0;
    std::vector<uint8_t> pixels; // RGBA, width * height * 4 bytes

    bool isValid() const { return !pixels.empty() && width > 0 && height > 0; }
};

// Model geometry info extracted for rendering.
struct ModelGeometry {
    std::string name;
    int bufferWi = 1;
    int bufferHt = 1;
    uint32_t nodeCount = 0;
    uint32_t channelCount = 0;
    uint32_t startChannel = 0; // 0-based absolute start channel
    std::vector<NativeNodeInfo> nodes;
};

class NativeRenderCoordinator {
public:
    NativeRenderCoordinator(IEffectProvider* effectProvider,
                            IModelProvider* modelProvider,
                            IRenderContext* context);
    ~NativeRenderCoordinator();

    NativeRenderCoordinator(const NativeRenderCoordinator&) = delete;
    NativeRenderCoordinator& operator=(const NativeRenderCoordinator&) = delete;

    void setListener(RenderCoordinatorListener* listener);

    // Render all models for the full sequence duration.
    // Returns true if completed, false if aborted.
    bool renderAll(NativeSequenceData& output);

    // Render all models for a time range.
    // Returns true if completed, false if aborted.
    bool renderRange(int startMS, int endMS, NativeSequenceData& output);

    // Render a single model at a single time for preview.
    RenderedFrame renderModelFrame(const std::string& modelName, int timeMS);

    // Abort the current render. Thread-safe.
    void abort();

    // Check if rendering is active.
    bool isRendering() const;

    // Get current render progress (0.0 to 1.0).
    float getProgress() const;

private:
    // Per-model render job
    struct ModelJob {
        ModelGeometry geometry;
        size_t elementIndex = 0;
        size_t layerCount = 0;
        std::unique_ptr<NativePixelBuffer> pixelBuffer;
    };

    std::vector<ModelJob> buildModelJobs();
    ModelGeometry extractGeometry(const std::string& modelName);
    size_t findParentGroupElement(const std::string& modelName);

    void renderModel(ModelJob& job, int startMS, int endMS,
                     NativeSequenceData& output);
    void renderModelAtTime(ModelJob& job, int timeMS);
    bool renderNativeEffect(const EffectInstanceInfo& effectInfo, NativeRenderBuffer& buf);
    void writeModelOutput(const ModelJob& job, int frameIndex,
                          NativeSequenceData& output);

    IEffectProvider* _effectProvider;
    IModelProvider* _modelProvider;
    IRenderContext* _context;
    RenderCoordinatorListener* _listener = nullptr;

    std::atomic<bool> _abort{false};
    std::atomic<bool> _rendering{false};
    std::atomic<float> _progress{0.0f};
    mutable std::mutex _listenerMutex;
};

} // namespace xlEngine
