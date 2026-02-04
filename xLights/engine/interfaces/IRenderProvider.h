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

// IRenderProvider: Abstract interface for render pipeline access.
// Part of the xlEngine abstraction layer for decoupling native UI from wxWidgets.
//
// This interface allows engines to access rendering functionality without
// direct xLightsFrame dependencies. During the transition period, an adapter
// class will implement this interface by delegating to xLightsFrame.
// Eventually, a native implementation will provide the same functionality
// without any wxWidgets dependencies.
//
// Design principles:
// - Use ONLY std:: types (no wxWidgets types cross this boundary)
// - Pointers to existing classes (RenderBuffer, PixelBufferClass) are OK
//   for gradual migration
// - Thread-safe (render happens on background threads)
// - Callback-based for async operations
//
// Reference: DECOUPLING_GUIDE.md, IMPLEMENTATION_GUIDE.md

#include <string>
#include <vector>
#include <functional>
#include <cstdint>
#include <cstddef>

// Forward declarations for existing classes (used during transition period)
class RenderBuffer;
class PixelBufferClass;

namespace xlEngine {

// Forward declaration for graphics context abstraction
// During transition, this will be a pointer to the existing xlGraphicsContext
// Eventually it will be replaced with a pure C++ abstraction
class IGraphicsContext;

// Raw frame data view for a single frame of channel data.
// Does not own the data; valid only while the sequence is loaded.
struct RawFrameData {
    const uint8_t* data = nullptr;  // Raw channel data
    size_t channelCount = 0;        // Number of channels
    int frameIndex = 0;             // Frame index this data represents

    bool isValid() const { return data != nullptr && channelCount > 0; }

    uint8_t operator[](size_t channel) const {
        if (channel < channelCount && data) return data[channel];
        return 0;
    }
};

// Callback types for async render operations.
// Note: Callbacks may be invoked from background threads.
// Callers must dispatch to their own UI thread if needed.
using RenderProgressCallback = std::function<void(float progress)>;
using RenderCompleteCallback = std::function<void(bool wasCancelled)>;

// IRenderProvider: Abstract interface for render pipeline access.
//
// Thread safety: All methods must be safe to call from any thread.
// Implementations should use internal locking where necessary.
// Callbacks may fire from background threads.
//
// This interface abstracts the render pipeline so that:
// 1. RenderEngine can use it instead of direct xLightsFrame access
// 2. Native UI can provide its own implementation
// 3. Unit tests can provide mock implementations
class IRenderProvider {
public:
    virtual ~IRenderProvider() = default;

    // =========================================================================
    // Buffer Access
    // =========================================================================

    // Get the RenderBuffer for a specific model.
    // Returns nullptr if the model doesn't exist or has no render buffer.
    // The pointer remains valid until the model is removed or the sequence changes.
    // Thread-safe: May be called from any thread.
    virtual RenderBuffer* getRenderBuffer(const std::string& modelName) = 0;

    // Get the PixelBuffer for a specific model.
    // Returns nullptr if the model doesn't exist or has no pixel buffer.
    // The pointer remains valid until the model is removed or the sequence changes.
    // Thread-safe: May be called from any thread.
    virtual PixelBufferClass* getPixelBuffer(const std::string& modelName) = 0;

    // =========================================================================
    // Frame Data Access
    // =========================================================================

    // Get raw channel data for a specific frame.
    // Returns an invalid RawFrameData if frameIndex is out of range or no sequence is loaded.
    // The data pointer is valid only while the sequence is loaded and unchanged.
    // Thread-safe: May be called from any thread.
    virtual RawFrameData getFrameData(int frameIndex) const = 0;

    // Get the total number of channels in the current sequence.
    // Returns 0 if no sequence is loaded.
    virtual size_t getTotalChannels() const = 0;

    // =========================================================================
    // GPU / Graphics Context
    // =========================================================================

    // Get the graphics context for GPU-accelerated rendering.
    // Returns nullptr if GPU rendering is not available or not enabled.
    // The pointer type will be abstracted in the future; during transition
    // this returns a pointer that can be cast to xlGraphicsContext*.
    // Thread-safe: May be called from any thread, but the context itself
    // may only be used from the render thread.
    virtual void* getGPUContext() = 0;

    // Check if GPU rendering is available on this system.
    virtual bool isGPUAvailable() const = 0;

    // Check if GPU rendering is currently enabled.
    virtual bool isGPUEnabled() const = 0;

    // =========================================================================
    // Render Control
    // =========================================================================

    // Request rendering of a range of frames.
    // This triggers background rendering; use callbacks or isRendering() to track progress.
    // startFrame and endFrame are inclusive frame indices.
    // Thread-safe: May be called from any thread.
    virtual void requestRender(int startFrame, int endFrame) = 0;

    // Check if any rendering is currently in progress.
    // Thread-safe: May be called from any thread.
    virtual bool isRendering() const = 0;

    // Cancel any in-progress rendering.
    // This is a non-blocking call; rendering may not stop immediately.
    // Use isRendering() to check if rendering has actually stopped.
    // Thread-safe: May be called from any thread.
    virtual void cancelRender() = 0;

    // Get the current render progress as a value from 0.0 to 1.0.
    // Returns 0.0 if no rendering is in progress.
    // Thread-safe: May be called from any thread.
    virtual float getRenderProgress() const = 0;

    // =========================================================================
    // Callbacks
    // =========================================================================

    // Set a callback to be invoked periodically during rendering with progress updates.
    // The callback receives a float from 0.0 to 1.0 indicating progress.
    // Pass nullptr to clear the callback.
    // Note: The callback may be invoked from a background thread.
    // Thread-safe: May be called from any thread.
    virtual void setRenderProgressCallback(RenderProgressCallback callback) = 0;

    // Set a callback to be invoked when rendering completes.
    // The callback receives a bool indicating whether the render was cancelled.
    // Pass nullptr to clear the callback.
    // Note: The callback may be invoked from a background thread.
    // Thread-safe: May be called from any thread.
    virtual void setRenderCompleteCallback(RenderCompleteCallback callback) = 0;

    // =========================================================================
    // Sequence Information
    // =========================================================================

    // Get the frame time in milliseconds for the current sequence.
    // Returns 0 if no sequence is loaded.
    virtual int getFrameTimeMS() const = 0;

    // Get the total number of frames in the current sequence.
    // Returns 0 if no sequence is loaded.
    virtual int getTotalFrames() const = 0;

    // Get the sequence duration in milliseconds.
    // Returns 0 if no sequence is loaded.
    virtual int getSequenceDurationMS() const = 0;
};

} // namespace xlEngine
