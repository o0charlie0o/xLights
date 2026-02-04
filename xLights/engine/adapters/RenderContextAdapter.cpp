/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "RenderContextAdapter.h"

#include "../../xLightsMain.h"
#include "../../PixelBuffer.h"
#include "../../RenderBuffer.h"
#include "../../SequenceData.h"
#include "../../GPURenderUtils.h"
#include "../../models/Model.h"
#include "../../sequencer/SequenceElements.h"

namespace xlEngine {

RenderContextAdapter::RenderContextAdapter(xLightsFrame* frame)
    : _frame(frame)
{
}

// --- Buffer Access ---

RenderBuffer* RenderContextAdapter::getRenderBuffer(const std::string& modelName)
{
    if (!_frame) return nullptr;

    // RenderBuffer is accessed through PixelBufferClass which is created
    // per-render-job. During the transition period, we can't provide direct
    // access to the RenderBuffer without a render in progress.
    // Return nullptr for now; this will be properly connected when
    // RenderEngine fully owns the render pipeline.
    return nullptr;
}

PixelBufferClass* RenderContextAdapter::getPixelBuffer(const std::string& modelName)
{
    if (!_frame) return nullptr;

    // Similar to getRenderBuffer, PixelBufferClass is created per-render-job.
    // Return nullptr during transition.
    return nullptr;
}

// --- Frame Data Access ---

RawFrameData RenderContextAdapter::getFrameData(int frameIndex) const
{
    RawFrameData result;
    if (!_frame) return result;

    SequenceData& seqData = _frame->_seqData;
    if (!seqData.IsValidData()) return result;

    int numFrames = seqData.NumFrames();
    if (frameIndex < 0 || frameIndex >= numFrames) return result;

    result.data = seqData[frameIndex];
    result.channelCount = seqData.NumChannels();
    result.frameIndex = frameIndex;

    return result;
}

size_t RenderContextAdapter::getTotalChannels() const
{
    if (!_frame) return 0;

    SequenceData& seqData = _frame->_seqData;
    if (!seqData.IsValidData()) return 0;

    return seqData.NumChannels();
}

// --- GPU / Graphics Context ---

void* RenderContextAdapter::getGPUContext()
{
    // GPU context access through xLightsFrame.
    // During the transition period, we return nullptr as the GPU context
    // is managed internally by the render pipeline.
    return nullptr;
}

bool RenderContextAdapter::isGPUAvailable() const
{
    return GPURenderUtils::IsEnabled();
}

bool RenderContextAdapter::isGPUEnabled() const
{
    if (!_frame) return false;
    return _frame->UseGPURendering();
}

// --- Render Control ---

void RenderContextAdapter::requestRender(int startFrame, int endFrame)
{
    if (!_frame) return;

    SequenceData& seqData = _frame->_seqData;
    if (!seqData.IsValidData()) return;

    int frameTime = seqData.FrameTime();
    if (frameTime <= 0) return;

    int startMS = startFrame * frameTime;
    int endMS = (endFrame + 1) * frameTime;

    _frame->RenderTimeSlice(startMS, endMS, true);
}

bool RenderContextAdapter::isRendering() const
{
    if (!_frame) return false;
    return !_frame->renderProgressInfo.empty();
}

void RenderContextAdapter::cancelRender()
{
    if (!_frame) return;
    _frame->AbortRender();
}

float RenderContextAdapter::getRenderProgress() const
{
    if (!_frame) return 0.0f;

    // renderProgressInfo provides progress tracking but detailed access
    // requires integration with the render pipeline. For now, return
    // a simple binary progress (0 or 1) based on whether rendering is active.
    if (_frame->renderProgressInfo.empty()) {
        return 0.0f;
    }
    return 0.5f; // Unknown progress during render
}

// --- Callbacks ---

void RenderContextAdapter::setRenderProgressCallback(RenderProgressCallback callback)
{
    std::lock_guard<std::mutex> lock(_callbackMutex);
    _progressCallback = std::move(callback);
}

void RenderContextAdapter::setRenderCompleteCallback(RenderCompleteCallback callback)
{
    std::lock_guard<std::mutex> lock(_callbackMutex);
    _completeCallback = std::move(callback);
}

// --- Sequence Information ---

int RenderContextAdapter::getFrameTimeMS() const
{
    if (!_frame) return 50; // Default frame time

    SequenceData& seqData = _frame->_seqData;
    if (!seqData.IsValidData()) return 50;

    return seqData.FrameTime();
}

int RenderContextAdapter::getTotalFrames() const
{
    if (!_frame) return 0;

    SequenceData& seqData = _frame->_seqData;
    if (!seqData.IsValidData()) return 0;

    return seqData.NumFrames();
}

int RenderContextAdapter::getSequenceDurationMS() const
{
    if (!_frame) return 0;

    SequenceData& seqData = _frame->_seqData;
    if (!seqData.IsValidData()) return 0;

    return seqData.TotalTime();
}

} // namespace xlEngine
