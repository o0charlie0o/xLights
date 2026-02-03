/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "RenderEngine.h"

#include "../xLightsMain.h"
#include "../PixelBuffer.h"
#include "../RenderBuffer.h"
#include "../RenderCache.h"
#include "../GPURenderUtils.h"
#include "../models/ModelManager.h"
#include "../models/Model.h"
#include "../sequencer/SequenceElements.h"
#include "../SequenceData.h"

#include <algorithm>

namespace xlEngine {

// --- Construction / destruction ---

RenderEngine::RenderEngine(xLightsFrame* frame)
    : _frame(frame)
{
}

RenderEngine::~RenderEngine()
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.clear();
}

// --- Listener management ---

void RenderEngine::addListener(RenderEngineListener* listener)
{
    if (!listener) return;
    std::lock_guard<std::mutex> lock(_listenerMutex);
    if (std::find(_listeners.begin(), _listeners.end(), listener) == _listeners.end()) {
        _listeners.push_back(listener);
    }
}

void RenderEngine::removeListener(RenderEngineListener* listener)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.erase(
        std::remove(_listeners.begin(), _listeners.end(), listener),
        _listeners.end());
}

// --- Notification helpers ---

void RenderEngine::notifyModelFrameRendered(const std::string& modelName, int timeMS)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* l : _listeners) {
        l->onModelFrameRendered(modelName, timeMS);
    }
}

void RenderEngine::notifyFrameRendered(int timeMS)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* l : _listeners) {
        l->onFrameRendered(timeMS);
    }
}

void RenderEngine::notifyRenderComplete(bool wasCancelled)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* l : _listeners) {
        l->onRenderComplete(wasCancelled);
    }
}

void RenderEngine::notifyRenderProgress(const RenderStatus& status)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* l : _listeners) {
        l->onRenderProgress(status);
    }
}

void RenderEngine::notifyRenderError(const std::string& modelName, const std::string& message)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* l : _listeners) {
        l->onRenderError(modelName, message);
    }
}

// --- Frame rendering ---

void RenderEngine::renderFrame(int timeMS)
{
    if (!_frame) return;

    SequenceData& seqData = _frame->_seqData;
    if (!seqData.IsValidData()) return;

    int frameTime = seqData.FrameTime();
    if (frameTime <= 0) return;

    _frame->RenderTimeSlice(timeMS, timeMS + frameTime, true);
}

void RenderEngine::renderModelFrame(const std::string& modelName, int timeMS)
{
    if (!_frame) return;

    SequenceData& seqData = _frame->_seqData;
    if (!seqData.IsValidData()) return;

    int frameTime = seqData.FrameTime();
    if (frameTime <= 0) return;

    _frame->RenderEffectForModel(modelName, timeMS, timeMS + frameTime, false);
}

void RenderEngine::renderAll(RenderCompleteCallback callback)
{
    if (!_frame) {
        if (callback) callback(false);
        return;
    }

    if (!_frame->_seqData.IsValidData()) {
        if (callback) callback(false);
        return;
    }

    auto wrappedCallback = [this, callback](bool aborted) {
        notifyRenderComplete(aborted);
        if (callback) callback(aborted);
    };

    _frame->RenderGridToSeqData(std::move(wrappedCallback));
}

void RenderEngine::renderRange(int startMS, int endMS, bool clear,
                               RenderCompleteCallback callback)
{
    if (!_frame) {
        if (callback) callback(false);
        return;
    }

    SequenceData& seqData = _frame->_seqData;
    if (!seqData.IsValidData()) {
        if (callback) callback(false);
        return;
    }

    _frame->RenderTimeSlice(startMS, endMS, clear);

    if (callback) callback(false);
}

void RenderEngine::renderModelRange(const std::string& modelName, int startMS, int endMS,
                                    bool clear)
{
    if (!_frame) return;
    if (!_frame->_seqData.IsValidData()) return;

    _frame->RenderEffectForModel(modelName, startMS, endMS, clear);
}

bool RenderEngine::abortRender(int timeoutMS)
{
    if (!_frame) return true;
    return _frame->AbortRender(timeoutMS);
}

// --- Buffer access ---

FrameBuffer RenderEngine::getFrameBuffer(const std::string& modelName) const
{
    if (!_frame) return {};

    // Check our local cache first.
    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        auto it = _bufferCache.find(modelName);
        if (it != _bufferCache.end()) {
            return it->second;
        }
    }

    // If not in the cache, build a FrameBuffer from the model's node
    // structure and buffer dimensions. The actual pixel data comes from
    // the RenderBuffer when a render is in progress, or from the
    // SequenceData when reading previously rendered data.
    //
    // Since we need to know the current playback position to read the
    // right frame from SequenceData, and that requires coordination
    // with the SequenceEngine, we return a correctly-sized but empty
    // buffer here. The buffer gets populated via extractFrameBuffer()
    // during active rendering.
    Model* model = _frame->GetModel(modelName);
    if (!model) return {};

    FrameBuffer fb;
    fb.modelName = modelName;
    fb.width = model->GetDefaultBufferWi();
    fb.height = model->GetDefaultBufferHt();

    if (fb.width <= 0 || fb.height <= 0) return {};

    size_t pixelBytes = static_cast<size_t>(fb.width) * fb.height * 4;
    fb.pixels.resize(pixelBytes, 0);

    return fb;
}

FrameBuffer RenderEngine::extractFrameBuffer(const std::string& modelName,
                                             PixelBufferClass* pixelBuffer,
                                             int timeMS) const
{
    FrameBuffer fb;
    if (!pixelBuffer) return fb;

    fb.modelName = modelName;
    fb.timeMS = timeMS;

    RenderBuffer& renderBuf = pixelBuffer->BufferForLayer(0, 0);
    fb.width = renderBuf.BufferWi;
    fb.height = renderBuf.BufferHt;

    if (fb.width <= 0 || fb.height <= 0) return fb;

    size_t pixelBytes = static_cast<size_t>(fb.width) * fb.height * 4;
    fb.pixels.resize(pixelBytes);

    xlColor* pixels = renderBuf.GetPixels();
    if (!pixels) return fb;

    for (int y = 0; y < fb.height; ++y) {
        for (int x = 0; x < fb.width; ++x) {
            const xlColor& c = pixels[y * fb.width + x];
            size_t idx = (static_cast<size_t>(y) * fb.width + x) * 4;
            fb.pixels[idx] = c.red;
            fb.pixels[idx + 1] = c.green;
            fb.pixels[idx + 2] = c.blue;
            fb.pixels[idx + 3] = c.alpha;
        }
    }

    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        _bufferCache[modelName] = fb;
    }

    return fb;
}

std::vector<NodeChannelData> RenderEngine::getNodeData(const std::string& modelName) const
{
    std::vector<NodeChannelData> result;
    if (!_frame) return result;

    Model* model = _frame->GetModel(modelName);
    if (!model) return result;

    SequenceData& seqData = _frame->_seqData;
    if (!seqData.IsValidData()) return result;

    int nodeCount = model->GetNodeCount();
    int chanPerNode = model->GetChanCountPerNode();

    result.reserve(nodeCount);
    for (int n = 0; n < nodeCount; ++n) {
        NodeChannelData ncd;
        ncd.startChannel = model->NodeStartChannel(n);
        ncd.channelCount = chanPerNode;
        ncd.data.resize(chanPerNode, 0);
        result.push_back(std::move(ncd));
    }

    return result;
}

// --- Layer management ---

int RenderEngine::getLayerCount(const std::string& modelName) const
{
    if (!_frame) return 0;

    SequenceElements& elements = _frame->GetSequenceElements();
    Element* el = elements.GetElement(modelName);
    if (!el) return 0;

    return el->GetEffectLayerCount();
}

void RenderEngine::setMixMode(const std::string& modelName, int layer, MixMode mode)
{
    // Mix modes are applied through the effect settings in the existing
    // rendering pipeline via PixelBufferClass::SetLayerSettings().
    // The PixelBufferClass is created per RenderJob and destroyed after
    // the render completes. During the transition period, mix mode
    // changes should go through the effect/layer settings map.
    // This will be fully connected when the engine owns the pipeline.
}

MixMode RenderEngine::getMixMode(const std::string& modelName, int layer) const
{
    // The active mix mode is a per-render-job property stored in
    // PixelBufferClass::LayerInfo. Since render jobs are transient,
    // return the default during the transition period.
    return MixMode::Normal;
}

std::vector<std::string> RenderEngine::getMixModeNames()
{
    return PixelBufferClass::GetMixTypes();
}

// --- Model render info ---

ModelRenderInfo RenderEngine::getModelRenderInfo(const std::string& modelName) const
{
    ModelRenderInfo info;
    if (!_frame) return info;

    Model* model = _frame->GetModel(modelName);
    if (!model) return info;

    info.modelName = modelName;
    info.bufferWidth = model->GetDefaultBufferWi();
    info.bufferHeight = model->GetDefaultBufferHt();
    info.nodeCount = model->GetNodeCount();
    info.channelCount = model->GetActChanCount();

    SequenceElements& elements = _frame->GetSequenceElements();
    Element* el = elements.GetElement(modelName);
    if (el) {
        info.layerCount = el->GetEffectLayerCount();
    }

    // Use renderProgressInfo (public) to determine if rendering is active.
    info.isRendering = !_frame->renderProgressInfo.empty();

    return info;
}

std::vector<ModelRenderInfo> RenderEngine::getAllModelRenderInfo() const
{
    std::vector<ModelRenderInfo> result;
    if (!_frame) return result;

    const ModelManager& mm = _frame->AllModels;
    for (auto it = mm.begin(); it != mm.end(); ++it) {
        result.push_back(getModelRenderInfo(it->first));
    }

    return result;
}

// --- Cache management ---

void RenderEngine::invalidateCache(const std::string& modelName)
{
    if (!_frame) return;

    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        _bufferCache.erase(modelName);
    }

    SequenceElements& elements = _frame->GetSequenceElements();
    Element* el = elements.GetElement(modelName);
    if (el) {
        SequenceData& seqData = _frame->_seqData;
        if (seqData.IsValidData()) {
            el->SetDirtyRange(0, seqData.TotalTime());
        }
    }
}

void RenderEngine::invalidateAllCaches()
{
    if (!_frame) return;

    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        _bufferCache.clear();
    }

    _frame->MarkModelsAsNeedingRender();
}

// --- GPU / render mode ---

bool RenderEngine::getGPUAvailable() const
{
    return GPURenderUtils::IsEnabled();
}

bool RenderEngine::getGPUEnabled() const
{
    if (!_frame) return false;
    return _frame->UseGPURendering();
}

void RenderEngine::setGPUEnabled(bool enabled)
{
    if (!_frame) return;
    _frame->SetUseGPURendering(enabled);
}

void RenderEngine::setRenderMode(RenderMode mode)
{
    _renderMode.store(mode);

    switch (mode) {
    case RenderMode::CPU:
        setGPUEnabled(false);
        break;
    case RenderMode::GPU:
        if (getGPUAvailable()) {
            setGPUEnabled(true);
        }
        break;
    case RenderMode::Auto:
        setGPUEnabled(getGPUAvailable());
        break;
    }
}

RenderMode RenderEngine::getRenderMode() const
{
    return _renderMode.load();
}

// --- Render state queries ---

bool RenderEngine::isRendering() const
{
    if (!_frame) return false;
    return !_frame->renderProgressInfo.empty();
}

RenderStatus RenderEngine::getRenderStatus() const
{
    RenderStatus status;
    if (!_frame) return status;

    status.isRendering = !_frame->renderProgressInfo.empty();

    if (_frame->_seqData.IsValidData()) {
        status.framesTotal = _frame->_seqData.NumFrames();
    }

    // RenderProgressInfo is forward-declared in xLightsMain.h and defined
    // in Render.cpp. We can check whether the list is empty but cannot
    // access the member fields from this compilation unit. Detailed
    // progress tracking will be implemented when the engine fully owns
    // the render pipeline, or via a public accessor added to xLightsFrame.
    //
    // For now, report basic state: rendering vs not rendering.
    if (status.isRendering && status.framesTotal > 0) {
        status.progressPercent = 0.0f; // unknown until fully connected
    }

    return status;
}

int RenderEngine::getFrameTimeMS() const
{
    if (!_frame) return 50;
    if (!_frame->_seqData.IsValidData()) return 50;
    return _frame->_seqData.FrameTime();
}

int RenderEngine::getNumFrames() const
{
    if (!_frame) return 0;
    if (!_frame->_seqData.IsValidData()) return 0;
    return _frame->_seqData.NumFrames();
}

} // namespace xlEngine
