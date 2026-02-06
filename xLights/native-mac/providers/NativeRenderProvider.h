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

// NativeRenderProvider: Native macOS implementation of IRenderProvider.
//
// This provider manages render buffers and GPU context natively using Metal
// without wxWidgets dependencies. It provides the rendering infrastructure
// for the native macOS UI.
//
// Part of the native macOS rebuild (Phase 3: Create Native Provider Implementations).
// See DECOUPLING_GUIDE.md for architectural context.
//
// Thread Safety:
// All methods are protected by internal mutexes for thread-safe access.
// Render operations may be requested from any thread, with callbacks
// potentially firing from background threads.
//
// Usage:
// - Create a NativeRenderProvider instance
// - Optionally provide an external data source via setSequenceDataSource()
// - Set progress/complete callbacks as needed
// - Call requestRender() to trigger background rendering
//
// Metal Infrastructure:
// This provider leverages the existing xlMetalGraphicsContext infrastructure
// for GPU-accelerated rendering. Metal shaders are already available in
// xLights/graphics/metal/.

#include "../../engine/interfaces/IRenderProvider.h"

#include <atomic>
#include <condition_variable>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// Forward declarations for existing classes (used during transition period)
class RenderBuffer;
class PixelBufferClass;
#ifndef XLIGHTS_NATIVE
class Model;
class ModelManager;
class SequenceData;
#endif

// Forward declare Objective-C types
#ifdef __OBJC__
@protocol MTLDevice;
@protocol MTLCommandQueue;
#else
typedef void* id;
#endif

namespace xlEngine {

// Sequence data source interface for native rendering.
// This allows NativeRenderProvider to access sequence data without
// depending on xLightsFrame directly.
class ISequenceDataSource {
public:
    virtual ~ISequenceDataSource() = default;

    // Get raw frame data for a frame index
    virtual const uint8_t* getFrameData(int frameIndex) const = 0;

    // Get total channel count
    virtual size_t getChannelCount() const = 0;

    // Get total frame count
    virtual int getFrameCount() const = 0;

    // Get frame time in milliseconds
    virtual int getFrameTimeMS() const = 0;

    // Get total duration in milliseconds
    virtual int getDurationMS() const = 0;

    // Check if data is valid/loaded
    virtual bool isValid() const = 0;
};

// Native render buffer wrapper for standalone operation.
// This provides a simple pixel buffer that doesn't depend on wxWidgets.
class ProviderPixelBuffer {
public:
    ProviderPixelBuffer(int width, int height);
    ~ProviderPixelBuffer();

    // Disable copy
    ProviderPixelBuffer(const ProviderPixelBuffer&) = delete;
    ProviderPixelBuffer& operator=(const ProviderPixelBuffer&) = delete;

    // Enable move
    ProviderPixelBuffer(ProviderPixelBuffer&& other) noexcept;
    ProviderPixelBuffer& operator=(ProviderPixelBuffer&& other) noexcept;

    // Pixel access
    void setPixel(int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t a = 255);
    void getPixel(int x, int y, uint8_t& r, uint8_t& g, uint8_t& b, uint8_t& a) const;

    // Clear to black
    void clear();

    // Raw access
    uint8_t* data() { return _pixels.data(); }
    const uint8_t* data() const { return _pixels.data(); }
    size_t dataSize() const { return _pixels.size(); }

    int width() const { return _width; }
    int height() const { return _height; }

private:
    int _width;
    int _height;
    std::vector<uint8_t> _pixels; // RGBA format
};

/// Native macOS implementation of IRenderProvider.
///
/// This class provides render pipeline access without wxWidgets runtime
/// dependencies. It uses Metal for GPU-accelerated rendering and manages
/// pixel buffers for models.
///
/// During the transition period, this provider can wrap an existing
/// ModelManager and SequenceData source. Long-term, it will use fully
/// native data structures.
class NativeRenderProvider : public IRenderProvider {
public:
    /// Constructs an empty NativeRenderProvider.
    NativeRenderProvider();

#ifndef XLIGHTS_NATIVE
    /// Constructs a NativeRenderProvider that wraps an existing ModelManager.
    /// This allows gradual transition from wxWidgets-based rendering.
    /// @param manager Reference to existing ModelManager. Must outlive this provider.
    explicit NativeRenderProvider(ModelManager& manager);
#endif

    ~NativeRenderProvider() override;

    // Non-copyable
    NativeRenderProvider(const NativeRenderProvider&) = delete;
    NativeRenderProvider& operator=(const NativeRenderProvider&) = delete;

    // --- IRenderProvider: Buffer Access ---

    RenderBuffer* getRenderBuffer(const std::string& modelName) override;
    PixelBufferClass* getPixelBuffer(const std::string& modelName) override;

    // --- IRenderProvider: Frame Data Access ---

    RawFrameData getFrameData(int frameIndex) const override;
    size_t getTotalChannels() const override;

    // --- IRenderProvider: GPU / Graphics Context ---

    void* getGPUContext() override;
    bool isGPUAvailable() const override;
    bool isGPUEnabled() const override;

    // --- IRenderProvider: Render Control ---

    void requestRender(int startFrame, int endFrame) override;
    bool isRendering() const override;
    void cancelRender() override;
    float getRenderProgress() const override;

    // --- IRenderProvider: Callbacks ---

    void setRenderProgressCallback(RenderProgressCallback callback) override;
    void setRenderCompleteCallback(RenderCompleteCallback callback) override;

    // --- IRenderProvider: Sequence Information ---

    int getFrameTimeMS() const override;
    int getTotalFrames() const override;
    int getSequenceDurationMS() const override;

    // --- Native Configuration ---

    /// Sets the sequence data source for frame data access.
    /// @param source Pointer to data source. Must outlive this provider.
    void setSequenceDataSource(ISequenceDataSource* source);

    /// Sets sequence timing info directly (when no ISequenceDataSource is available).
    void setSequenceInfo(int frameTimeMS, int durationMS);

    /// Sets whether GPU rendering should be enabled.
    /// @param enabled true to enable GPU rendering.
    void setGPUEnabled(bool enabled);

    /// Gets a native pixel buffer for a model.
    /// @param modelName Name of the model.
    /// @return Pointer to the pixel buffer, or nullptr if not found.
    ProviderPixelBuffer* getProviderPixelBuffer(const std::string& modelName);

    /// Creates a native pixel buffer for a model.
    /// @param modelName Name of the model.
    /// @param width Buffer width.
    /// @param height Buffer height.
    /// @return Pointer to the created buffer.
    ProviderPixelBuffer* createProviderPixelBuffer(const std::string& modelName,
                                               int width, int height);

    /// Removes a native pixel buffer for a model.
    /// @param modelName Name of the model to remove buffer for.
    void removeProviderPixelBuffer(const std::string& modelName);

    /// Clears all native pixel buffers.
    void clearProviderPixelBuffers();

    /// Returns whether this provider is using an external ModelManager.
    /// @return true if wrapping an external ModelManager.
#ifndef XLIGHTS_NATIVE
    bool isUsingExternalManager() const { return _externalManager != nullptr; }
#else
    bool isUsingExternalManager() const { return false; }
#endif

    /// Gets the Metal device being used.
    /// @return The Metal device, or nil if not available.
    id getMetalDevice() const;

    /// Gets the Metal command queue being used.
    /// @return The Metal command queue, or nil if not available.
    id getMetalCommandQueue() const;

private:
    // Metal infrastructure initialization
    bool initializeMetal();
    void cleanupMetal();

    // Background render thread management
    void startRenderThread();
    void stopRenderThread();
    void renderThreadFunc();

    // Render a single frame
    void renderFrame(int frameIndex);

    // Notify callbacks
    void notifyProgress(float progress);
    void notifyComplete(bool wasCancelled);

#ifndef XLIGHTS_NATIVE
    // External ModelManager for transition period (not owned)
    ModelManager* _externalManager;
#endif

    // External sequence data source (not owned)
    ISequenceDataSource* _sequenceDataSource;

    // Direct sequence info (used when _sequenceDataSource is not set)
    int _directFrameTimeMS = 0;
    int _directDurationMS = 0;

    // Native pixel buffers per model
    std::map<std::string, std::unique_ptr<ProviderPixelBuffer>> _nativePixelBuffers;
    mutable std::mutex _bufferMutex;

    // Metal infrastructure
    id _metalDevice;
    id _metalCommandQueue;
    bool _gpuAvailable;
    std::atomic<bool> _gpuEnabled;

    // Render state
    std::atomic<bool> _isRendering;
    std::atomic<bool> _cancelRequested;
    std::atomic<float> _renderProgress;

    // Render request
    int _renderStartFrame;
    int _renderEndFrame;

    // Background render thread
    std::thread _renderThread;
    std::mutex _renderMutex;
    std::condition_variable _renderCondition;
    std::atomic<bool> _renderThreadRunning;
    std::atomic<bool> _renderRequested;

    // Callbacks
    RenderProgressCallback _progressCallback;
    RenderCompleteCallback _completeCallback;
    mutable std::mutex _callbackMutex;
};

} // namespace xlEngine
