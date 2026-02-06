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

// RenderEngine: Pure C++ API for frame rendering and buffer access.
// Part of the xlEngine abstraction layer (Phase 2: Update Engines).
//
// This API wraps the existing PixelBuffer/RenderBuffer rendering pipeline
// to provide a wx-free interface suitable for use by both the existing
// wxWidgets UI and a future native AppKit UI. All data exchange uses
// std::string, std::vector, and plain structs -- no wxWidgets types
// cross this boundary.
//
// Architecture:
// - RenderEngine depends on IRenderProvider interface (not xLightsFrame directly)
// - For legacy wxWidgets code, use RenderContextAdapter to wrap xLightsFrame
// - For native macOS code, use NativeRenderProvider (future implementation)
// See DECOUPLING_GUIDE.md for architectural context.
//
// Thread safety: All public methods are safe to call from any thread.
// Rendering happens on background threads via the existing JobPool.
// Results can be read on any thread. Callbacks may fire from background
// threads; callers must dispatch to their own UI thread if needed.

#include <string>
#include <vector>
#include <functional>
#include <mutex>
#include <atomic>
#include <cstdint>
#include <map>
#include <memory>

#include "interfaces/IRenderProvider.h"
#include "interfaces/IModelProvider.h"
#include "interfaces/IOutputProvider.h"

class xLightsFrame;
class PixelBufferClass;
class FSEQFile;

namespace xlEngine {

// Rendering mode: CPU-only or GPU-accelerated (Metal on macOS, OpenGL elsewhere)
enum class RenderMode {
    CPU,
    GPU,
    Auto    // use GPU if available, fall back to CPU
};

// Layer blending modes mirroring MixTypes from PixelBuffer.h.
// The values are kept in sync with the existing enum so they can
// be cast directly when calling into the existing engine.
enum class MixMode {
    Normal = 0,
    Effect1,
    Effect2,
    Mask1,
    Mask2,
    Unmask1,
    Unmask2,
    TrueUnmask1,
    TrueUnmask2,
    OneRevealsTwo,
    TwoRevealsOne,
    Layered,
    Average,
    BottomTop,
    LeftRight,
    Shadow1on2,
    Shadow2on1,
    Additive,
    Subtractive,
    AsBrightness,
    Max,
    Min,
    Highlight,
    HighlightVibrant
};

// A snapshot of rendered pixel data for a single model at a single point in time.
// The pixel data is stored as a flat RGBA byte array in row-major order
// (bottom-to-top, matching the existing RenderBuffer layout).
struct FrameBuffer {
    std::string modelName;
    int width = 0;          // buffer width (pixels)
    int height = 0;         // buffer height (pixels)
    int timeMS = 0;         // time position this frame represents
    std::vector<uint8_t> pixels; // RGBA data: width * height * 4 bytes

    bool isValid() const { return !pixels.empty() && width > 0 && height > 0; }
    size_t pixelCount() const { return static_cast<size_t>(width) * height; }

    // Get RGBA values at a given pixel coordinate.
    // Returns (0,0,0,0) if out of range.
    void getPixel(int x, int y, uint8_t& r, uint8_t& g, uint8_t& b, uint8_t& a) const {
        if (x < 0 || x >= width || y < 0 || y >= height || pixels.empty()) {
            r = g = b = a = 0;
            return;
        }
        size_t idx = (static_cast<size_t>(y) * width + x) * 4;
        r = pixels[idx];
        g = pixels[idx + 1];
        b = pixels[idx + 2];
        a = pixels[idx + 3];
    }
};

// Per-node output data: channel values after rendering and dimming.
// Represents what would actually be sent to the hardware.
struct NodeChannelData {
    uint32_t startChannel = 0;
    uint32_t channelCount = 0;
    std::vector<uint8_t> data;
};

// Summary of a model's render state.
struct ModelRenderInfo {
    std::string modelName;
    int layerCount = 0;
    int bufferWidth = 0;
    int bufferHeight = 0;
    uint32_t nodeCount = 0;
    uint32_t channelCount = 0;
    bool isRendering = false;
};

// Status of an ongoing render operation.
struct RenderStatus {
    bool isRendering = false;
    int modelsTotal = 0;
    int modelsComplete = 0;
    int framesTotal = 0;
    int framesComplete = 0;
    float progressPercent = 0.0f;
};

// Callback interface for render completion and progress events.
class RenderEngineListener {
public:
    virtual ~RenderEngineListener() = default;

    // Called when a single model's frame has been rendered.
    virtual void onModelFrameRendered(const std::string& modelName, int timeMS) {}

    // Called when all models for a given time have been rendered.
    virtual void onFrameRendered(int timeMS) {}

    // Called when a full render pass (all frames) is complete.
    virtual void onRenderComplete(bool wasCancelled) {}

    // Called periodically with progress updates during a full render.
    virtual void onRenderProgress(const RenderStatus& status) {}

    // Called on render errors.
    virtual void onRenderError(const std::string& modelName, const std::string& message) {}
};

// Callback type for one-shot async completion notifications.
using RenderCompleteCallback = std::function<void(bool wasCancelled)>;

// RenderEngine wraps the existing PixelBuffer/RenderBuffer pipeline
// behind a clean C++ interface. It uses the IRenderProvider interface
// for all render operations, allowing it to work with both legacy wxWidgets
// infrastructure (via RenderContextAdapter) and native implementations.
//
// For backward compatibility during the transition period, a constructor
// accepting xLightsFrame* is provided. It internally creates a
// RenderContextAdapter to wrap the frame.
class RenderEngine {
public:
    /// Construct with an IRenderProvider interface.
    /// This is the preferred constructor for new code.
    /// @param provider Pointer to the render provider. Must outlive this engine.
    explicit RenderEngine(IRenderProvider* provider);

#ifndef XLIGHTS_NATIVE
    /// Legacy constructor for backward compatibility.
    /// Creates a RenderContextAdapter internally to wrap the xLightsFrame.
    /// @param frame Pointer to xLightsFrame. Must outlive this engine.
    /// @deprecated Use RenderEngine(IRenderProvider*) instead.
    explicit RenderEngine(xLightsFrame* frame);
#endif

    ~RenderEngine();

    RenderEngine(const RenderEngine&) = delete;
    RenderEngine& operator=(const RenderEngine&) = delete;

    // --- Listener management ---

    void addListener(RenderEngineListener* listener);
    void removeListener(RenderEngineListener* listener);

    // --- Frame rendering ---

    // Render all models at the given time position.
    // This triggers background rendering via the existing JobPool.
    // Results can be retrieved via getFrameBuffer() once rendering
    // is complete (signalled via listener callbacks).
    void renderFrame(int timeMS);

    // Render a single model at the given time position.
    // More efficient than renderFrame() when only one model is needed.
    void renderModelFrame(const std::string& modelName, int timeMS);

    // Trigger a full render of all frames in the current sequence.
    // Progress is reported via listener callbacks.
    // The optional callback is invoked when the render is complete.
    void renderAll(RenderCompleteCallback callback = nullptr);

    // Render a range of frames for all models.
    void renderRange(int startMS, int endMS, bool clear = false,
                     RenderCompleteCallback callback = nullptr);

    // Render a range of frames for a specific model.
    void renderModelRange(const std::string& modelName, int startMS, int endMS,
                          bool clear = false);

    // Abort any in-progress rendering.
    // Returns true if all renders were successfully aborted within timeoutMS.
    bool abortRender(int timeoutMS = 60000);

    // --- Buffer access ---

    // Get the rendered pixel data for a model.
    // Returns a snapshot of the most recently rendered frame for that model.
    // The returned FrameBuffer contains a copy of the data, so it remains
    // valid even if the model is re-rendered.
    FrameBuffer getFrameBuffer(const std::string& modelName) const;

    // Get the rendered node/channel data for a model at the current frame.
    // This is the output data that would be sent to hardware controllers.
    std::vector<NodeChannelData> getNodeData(const std::string& modelName) const;

    // --- Layer management ---

    // Get the number of effect layers for a model.
    int getLayerCount(const std::string& modelName) const;

    // Set the mix/blend mode for a specific layer of a model.
    void setMixMode(const std::string& modelName, int layer, MixMode mode);

    // Get the current mix mode for a layer.
    MixMode getMixMode(const std::string& modelName, int layer) const;

    // Get names of all available mix modes.
    static std::vector<std::string> getMixModeNames();

    // --- Model render info ---

    // Get render information for a specific model.
    ModelRenderInfo getModelRenderInfo(const std::string& modelName) const;

    // Get render info for all models in the current sequence.
    std::vector<ModelRenderInfo> getAllModelRenderInfo() const;

    // --- Cache management ---

    // Invalidate the render cache for a specific model, forcing re-render.
    void invalidateCache(const std::string& modelName);

    // Invalidate all render caches, forcing a full re-render.
    void invalidateAllCaches();

    // --- GPU / render mode ---

    // Check whether GPU-accelerated rendering is available.
    bool getGPUAvailable() const;

    // Check whether GPU rendering is currently enabled.
    bool getGPUEnabled() const;

    // Set whether to use GPU rendering.
    void setGPUEnabled(bool enabled);

    // Set the rendering mode (CPU, GPU, or Auto).
    void setRenderMode(RenderMode mode);

    // Get the current rendering mode.
    RenderMode getRenderMode() const;

    // --- Render state queries ---

    // Check if any rendering is currently in progress.
    bool isRendering() const;

    // Get the current render status (progress, frame counts, etc.)
    RenderStatus getRenderStatus() const;

    // Get the frame time in milliseconds for the current sequence.
    int getFrameTimeMS() const;

    // Get the total number of frames in the current sequence.
    int getNumFrames() const;

#ifdef XLIGHTS_NATIVE
    // --- FSEQ Playback (Native Build Only) ---

    // Set the model provider for accessing model data during FSEQ rendering.
    void setModelProvider(IModelProvider* provider);

    // Set the output provider for resolving controller channel mappings.
    void setOutputProvider(IOutputProvider* provider);

    // Load an FSEQ file for playback rendering.
    // Returns true if the file was loaded and channel mappings were resolved.
    bool loadFSEQ(const std::string& fseqPath);

    // Close the currently loaded FSEQ file and release resources.
    void closeFSEQ();

    // Check if an FSEQ file is loaded.
    bool isFSEQLoaded() const;
#endif

private:
    // Notification helpers
    void notifyModelFrameRendered(const std::string& modelName, int timeMS);
    void notifyFrameRendered(int timeMS);
    void notifyRenderComplete(bool wasCancelled);
    void notifyRenderProgress(const RenderStatus& status);
    void notifyRenderError(const std::string& modelName, const std::string& message);

    // Extract pixel data from a PixelBufferClass into a FrameBuffer.
    FrameBuffer extractFrameBuffer(const std::string& modelName,
                                   PixelBufferClass* pixelBuffer, int timeMS) const;

    IRenderProvider* _provider; // render provider interface

#ifdef XLIGHTS_NATIVE
    // --- FSEQ Playback State (Native Build) ---
    IModelProvider* _modelProvider = nullptr;
    IOutputProvider* _outputProvider = nullptr;

    std::unique_ptr<FSEQFile> _fseqFile;
    std::vector<uint8_t> _currentFrameData;
    int _currentFrameIndex = -1;
    bool _fseqLoaded = false;

    // Cached channel info per model for FSEQ rendering
    struct ModelChannelInfo {
        uint32_t absStartChannel = 0;  // 0-based absolute channel in FSEQ data
        uint32_t nodeCount = 0;
        uint32_t chansPerNode = 3;     // default RGB
        int bufferWidth = 0;
        int bufferHeight = 0;
        std::vector<std::pair<int,int>> nodeBufCoords; // (bufX, bufY) per node
        // Color order offsets within each node's channels.
        // FSEQ stores data in the controller's native color order (e.g. GRB for WS2812B).
        // These offsets map back to RGB for display.
        uint8_t rOffset = 0;
        uint8_t gOffset = 1;
        uint8_t bOffset = 2;
    };
    std::map<std::string, ModelChannelInfo> _modelChannelMap;

    // Controller name → absolute start channel (1-based, from xlights_networks.xml)
    std::map<std::string, int32_t> _controllerStartChannels;

    // Pre-computed model total channel counts (for resolving >ModelName:offset chains)
    std::map<std::string, uint32_t> _modelTotalChannels;

    // Memoization cache for resolved start channels
    std::map<std::string, uint32_t> _resolvedStartChannels;

    // Channel resolution helpers
    void buildModelChannelMap();
    void buildControllerChannelMap();
    void buildModelTotalChannelsMap();
    uint32_t resolveStartChannel(const std::string& startChannelStr);
#else
    // Owned adapter when constructed with xLightsFrame* (legacy mode)
    std::unique_ptr<class RenderContextAdapter> _ownedAdapter;

    // Legacy frame pointer for functionality not yet abstracted.
    // Will be removed once fully decoupled.
    xLightsFrame* _frame;
#endif

    std::vector<RenderEngineListener*> _listeners;
    mutable std::mutex _listenerMutex;

    std::atomic<RenderMode> _renderMode{RenderMode::Auto};
    mutable std::mutex _bufferCacheMutex;
    mutable std::map<std::string, FrameBuffer> _bufferCache;
};

} // namespace xlEngine
