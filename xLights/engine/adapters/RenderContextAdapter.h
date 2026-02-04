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

// RenderContextAdapter: Legacy adapter that wraps xLightsFrame to provide
// the IRenderProvider interface. This allows RenderEngine to work with
// the existing wxWidgets-based infrastructure while being decoupled from
// direct xLightsFrame dependencies.
//
// This class is part of the transition strategy. Once the native macOS UI
// has its own NativeRenderProvider implementation, this adapter will only
// be used by the legacy wxWidgets UI.
//
// Part of the xlEngine abstraction layer (Phase 2: Update Engines).
// See DECOUPLING_GUIDE.md for architectural context.

#include "../interfaces/IRenderProvider.h"
#include <mutex>
#include <atomic>

class xLightsFrame;
class PixelBufferClass;
class RenderBuffer;

namespace xlEngine {

/// Adapter that wraps xLightsFrame to implement IRenderProvider.
///
/// This class provides backward compatibility during the transition from
/// direct xLightsFrame usage to interface-based design. It implements the
/// IRenderProvider interface by delegating to xLightsFrame methods.
///
/// Thread Safety:
/// All methods are safe to call from any thread. Internal synchronization
/// is provided where needed. Callbacks may fire from background threads.
class RenderContextAdapter : public IRenderProvider {
public:
    /// Constructs an adapter wrapping the given xLightsFrame.
    /// @param frame Pointer to the xLightsFrame to wrap. The frame must
    ///              outlive this adapter.
    explicit RenderContextAdapter(xLightsFrame* frame);

    ~RenderContextAdapter() override = default;

    // Non-copyable
    RenderContextAdapter(const RenderContextAdapter&) = delete;
    RenderContextAdapter& operator=(const RenderContextAdapter&) = delete;

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

    // --- Legacy Accessors (for transition period) ---

    /// Get the underlying xLightsFrame pointer.
    /// This should only be used during the transition period for functionality
    /// not yet abstracted into the interface.
    xLightsFrame* getFrame() const { return _frame; }

private:
    xLightsFrame* _frame;

    RenderProgressCallback _progressCallback;
    RenderCompleteCallback _completeCallback;
    mutable std::mutex _callbackMutex;
};

} // namespace xlEngine
