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
#include <set>
#include <memory>

#include "interfaces/IRenderProvider.h"
#include "interfaces/IModelProvider.h"
#include "interfaces/IOutputProvider.h"
#include "EffectEngine.h"

class xLightsFrame;
class PixelBufferClass;
class FSEQFile;
class NativeSequenceData;

namespace xlEngine {

class BackgroundRenderQueue;
class DiskRenderCache;
class IAudioProvider;
class IEffectProvider;
class NativeRenderCoordinator;
struct IRenderContext;

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
class RenderEngine : public EffectEngineListener {
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

    // Force a complete re-render from scratch, clearing all caches
    // (in-memory, disk, dirty tracking). Use when the normal render
    // produces incorrect results or after major sequence changes.
    void forceRenderAll(RenderCompleteCallback callback = nullptr);

    // Re-render after an effect parameter/palette change.
    // Lighter than forceRenderAll: preserves _modelChannelMap and
    // resolved start channel caches (model layout hasn't changed).
    void reRenderForEffectChange(RenderCompleteCallback callback = nullptr);

    // Render a range of frames for all models.
    void renderRange(int startMS, int endMS, bool clear = false,
                     RenderCompleteCallback callback = nullptr);

    // Render a range of frames for a specific model.
    void renderModelRange(const std::string& modelName, int startMS, int endMS,
                          bool clear = false);

    // Abort any in-progress rendering.
    // Returns true if all renders were successfully aborted within timeoutMS.
    bool abortRender(int timeoutMS = 60000);

#ifdef XLIGHTS_NATIVE
    // Pre-warm the batch render coordinator on a background thread.
    // Creates the coordinator and runs preparePersistentJobs() so that
    // the first renderAll() can skip the ~1s job setup phase.
    // Call after loading a sequence (loadSequence / loadFSEQ).
    // Safe to call multiple times — no-op if already warmed.
    void warmUpCoordinator();
#endif

    // --- Buffer access ---

    // Get the rendered pixel data for a model.
    // Returns a snapshot of the most recently rendered frame for that model.
    // The returned FrameBuffer contains a copy of the data, so it remains
    // valid even if the model is re-rendered.
    FrameBuffer getFrameBuffer(const std::string& modelName) const;

    // Get all rendered frame buffers in a single lock. Returns only models
    // that have valid pixel data. Much more efficient than calling
    // getFrameBuffer() for each model individually (single lock instead of N).
    std::vector<FrameBuffer> getAllFrameBuffers() const;

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

#ifdef XLIGHTS_NATIVE
    // Mark a single model as dirty (needs re-render), without destroying
    // _renderedData. Clears the model's live cache entries and persistent state
    // but preserves all other pre-rendered data.
    void invalidateModel(const std::string& modelName);

    // Mark a model and its parent group (if any) as dirty. If the model IS
    // a group, also dirties all member models.
    void invalidateModelAndGroup(const std::string& modelName);

    // Set a callback invoked (on main queue) after a single dirty model
    // finishes background re-rendering. Used by Obj-C++ bridge to post
    // NSNotification for UI refresh.
    void setBackgroundRenderCallback(std::function<void(const std::string&)> cb);

    // Check if any models need re-rendering.
    bool hasDirtyModels() const;

    // Get the set of dirty model names.
    std::set<std::string> getDirtyModels() const;

    // Connect this engine to an EffectEngine to receive change notifications.
    // The engine will register/unregister itself as an EffectEngineListener.
    void connectEffectEngine(EffectEngine* engine);
    void disconnectEffectEngine();
#endif

    // --- Show folder ---

#ifdef XLIGHTS_NATIVE
    // Set the show folder path (needed for disk-backed render cache).
    // Must be called before renderAll() for disk caching to work.
    void setShowFolder(const std::string& path);
    const std::string& getShowFolder() const { return _showFolderPath; }
#endif

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

    // Set the effect provider for accessing sequence effect data during rendering.
    void setEffectProvider(IEffectProvider* provider);

    // Set the audio provider for audio-reactive effect rendering.
    // The provider supplies FFT spectrum, waveform, and level data.
    // Must be set before rendering effects that use audio data.
    void setAudioProvider(IAudioProvider* provider);

    // Load an FSEQ file for playback rendering.
    // Returns true if the file was loaded and channel mappings were resolved.
    bool loadFSEQ(const std::string& fseqPath);

    // Close the currently loaded FSEQ file and release resources.
    void closeFSEQ();

    // Check if an FSEQ file is loaded.
    bool isFSEQLoaded() const;

    // Export the most recently rendered data to an FSEQ file.
    // Returns true on success. Only valid after renderAll/renderRange completes.
    bool exportRenderedFSEQ(const std::string& outputPath, int compressionLevel = 2);

    // --- Zero-copy buffer access ---

    // Visitor callback type for zero-copy frame buffer iteration.
    // The pointer is valid only for the duration of the callback.
    using FrameBufferVisitor = std::function<void(
        const std::string& name, const uint8_t* pixels, size_t pixelBytes,
        int width, int height)>;

    // Iterate all valid frame buffers (batch + sidebar) under lock,
    // invoking the visitor for each. Avoids the deep-copy overhead of
    // getAllFrameBuffers(). The visitor must not call back into
    // RenderEngine (would deadlock).
    void visitFrameBuffers(const FrameBufferVisitor& visitor) const;
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
    // --- Native Render State ---
    IModelProvider* _modelProvider = nullptr;
    IOutputProvider* _outputProvider = nullptr;
    IEffectProvider* _effectProvider = nullptr;
    IAudioProvider* _audioProvider = nullptr;

    // Render coordinator for batch rendering (renderAll/renderRange).
    // Persisted across renders so preparePersistentJobs can reuse ModelJob objects.
    std::unique_ptr<NativeRenderCoordinator> _coordinator;
    std::unique_ptr<IRenderContext> _warmUpContext; // keeps context alive between warm-up and first render
    std::unordered_map<std::string, uint32_t> _cachedResolvedChannels; // from warm-up
    std::unique_ptr<NativeSequenceData> _preAllocatedRenderData; // from warm-up
    std::unique_ptr<NativeSequenceData> _renderedData;
    std::string _fseqPath; // Path of currently loaded FSEQ

    // Persistent coordinator for batch live preview rendering (renderFrame).
    // Kept alive across renderFrame() calls so stateful effects accumulate.
    // Uses shared_ptr so the parallel render loop can hold a reference even
    // if invalidateAllCaches() resets it from another thread.
    std::shared_ptr<NativeRenderCoordinator> _liveCoordinator;
    std::shared_ptr<IRenderContext> _liveContext;
    int _lastLiveRenderTimeMS = -1; // for backward scrub detection

    // Separate coordinator for per-model sidebar rendering (renderModelFrame).
    // Isolated from the batch path so they don't share _lastLiveRenderTimeMS
    // or persistent state — prevents mutual resetPersistentState() calls
    // and _bufferCache.clear() interference during concurrent playback.
    std::unique_ptr<NativeRenderCoordinator> _sidebarCoordinator;
    std::unique_ptr<IRenderContext> _sidebarContext;
    int _lastSidebarRenderTimeMS = -1;

    // --- FSEQ Playback State ---

    // shared_ptr so renderFrame() can hold a local copy while
    // forceRenderAll() resets the main pointer from another thread.
    std::shared_ptr<FSEQFile> _fseqFile;
    mutable std::mutex _fseqMutex; // protects _fseqFile pointer swaps
    std::vector<uint8_t> _currentFrameData;
    int _currentFrameIndex = -1;
    std::atomic<bool> _fseqLoaded{false};

    // Guard flag: when true, renderFrame() returns immediately.
    // Prevents data races between background renderAll/forceRenderAll
    // and main-thread renderFrame which share _renderedData, _fseqFile,
    // _modelChannelMap, and other state without fine-grained locking.
    std::atomic<bool> _renderInProgress{false};

    // Incremented each time renderAll completes. renderFrame uses this to
    // reset per-path diagnostic counters so we get fresh logs after each render.
    std::atomic<uint32_t> _renderGeneration{0};

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

    // Compute the minimum channel buffer size needed to hold all model data.
    // Scans all models and returns the highest end channel (start + nodeCount * chansPerNode).
    int32_t computeRequiredChannels();

    // Synthesize a submodel-specific FrameBuffer from the parent model's channel
    // data (FSEQ or pre-rendered). Stores result in _sidebarCache.
    void synthesizeSubmodelBuffer(const std::string& subRefName, int timeMS);

    // Synthesize a submodel FrameBuffer from parent's channel data and store
    // in _bufferCache. Used by the FSEQ/prerendered renderFrame() paths.
    // Caller must hold _bufferCacheMutex.
    void synthesizeSubmodelFrameBuffer(const std::string& subRefName,
                                       const ModelChannelInfo& parentChInfo,
                                       int timeMS);
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

    // Separate cache for per-model sidebar renders — not cleared by renderFrame().
    mutable std::mutex _sidebarCacheMutex;
    mutable std::map<std::string, FrameBuffer> _sidebarCache;

#ifdef XLIGHTS_NATIVE
    // --- EffectEngineListener overrides (native build only) ---
    void onEffectCreated(const EffectEvent& event) override;
    void onEffectDeleted(const EffectEvent& event) override;
    void onEffectMoved(const EffectEvent& event) override;
    void onEffectSettingChanged(const EffectEvent& event) override;
    void onEffectPaletteChanged(const EffectEvent& event) override;
    void onEffectTypeChanged(const EffectEvent& event) override;

    // --- Dirty tracking state ---
    std::set<std::string> _dirtyModels;
    std::atomic<bool> _allDirty{true};
    mutable std::mutex _dirtyMutex;
    std::map<std::string, std::pair<uint32_t, uint32_t>> _modelChannelRanges;
    EffectEngine* _connectedEffectEngine = nullptr;
    std::string resolveModelNameFromEvent(const EffectEvent& event);

    // --- Show folder path and disk render cache ---
    std::string _showFolderPath;
    std::unique_ptr<DiskRenderCache> _diskCache;

    // --- Background render queue (Phase 4) ---
    std::unique_ptr<BackgroundRenderQueue> _bgRenderQueue;
    // Dedicated coordinator for background rendering — isolated from
    // the batch (_coordinator) and live preview (_liveCoordinator) paths.
    std::unique_ptr<NativeRenderCoordinator> _bgCoordinator;
    std::unique_ptr<IRenderContext> _bgContext;
    void ensureBackgroundRenderQueue();
    void notifyBackgroundRenderComplete(const std::string& modelName);

    // Live-render dirty models at timeMS using _liveCoordinator and insert
    // results into _bufferCache. Returns the number of models rendered.
    int liveRenderDirtyModels(int timeMS);

    // Build resolved start channel map from _modelChannelMap for coordinators.
    std::unordered_map<std::string, uint32_t> buildResolvedChannelMap() const;

    // Detect if dirty models share a common group parent. Returns the group
    // name if found (non-empty), or empty string if no group context.
    std::string findDirtyGroupParent(const std::set<std::string>& dirtyModels) const;

    // Callback invoked on a bg thread after a single dirty model finishes
    // background re-rendering. Set from Obj-C++ bridge to post UI notifications.
    std::function<void(const std::string&)> _bgRenderCompleteCallback;
#endif
};

} // namespace xlEngine
