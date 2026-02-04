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

#ifndef XLIGHTS_NATIVE
#include "adapters/RenderContextAdapter.h"
#include "../xLightsMain.h"
#include "../PixelBuffer.h"
#include "../RenderBuffer.h"
#include "../RenderCache.h"
#include "../GPURenderUtils.h"
#include "../models/ModelManager.h"
#include "../models/Model.h"
#include "../sequencer/SequenceElements.h"
#include "../SequenceData.h"
#endif

#include <algorithm>

namespace xlEngine {

#ifdef XLIGHTS_NATIVE
// Native build: stub implementation
// The native build uses NativeRenderProvider instead of the legacy adapter

RenderEngine::RenderEngine(IRenderProvider* provider)
    : _provider(provider)
{
}

RenderEngine::~RenderEngine()
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.clear();
}

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

void RenderEngine::renderFrame(int timeMS) {}
void RenderEngine::renderModelFrame(const std::string& modelName, int timeMS) {}
void RenderEngine::renderAll(RenderCompleteCallback callback) { if (callback) callback(false); }
void RenderEngine::renderRange(int startMS, int endMS, bool clear, RenderCompleteCallback callback) { if (callback) callback(false); }
void RenderEngine::renderModelRange(const std::string& modelName, int startMS, int endMS, bool clear) {}
bool RenderEngine::abortRender(int timeoutMS) { return true; }
FrameBuffer RenderEngine::getFrameBuffer(const std::string& modelName) const { return {}; }
std::vector<NodeChannelData> RenderEngine::getNodeData(const std::string& modelName) const { return {}; }
int RenderEngine::getLayerCount(const std::string& modelName) const { return 0; }
void RenderEngine::setMixMode(const std::string& modelName, int layer, MixMode mode) {}
MixMode RenderEngine::getMixMode(const std::string& modelName, int layer) const { return MixMode::Normal; }
std::vector<std::string> RenderEngine::getMixModeNames() { return {}; }
ModelRenderInfo RenderEngine::getModelRenderInfo(const std::string& modelName) const { return {}; }
std::vector<ModelRenderInfo> RenderEngine::getAllModelRenderInfo() const { return {}; }
void RenderEngine::invalidateCache(const std::string& modelName) {}
void RenderEngine::invalidateAllCaches() {}
bool RenderEngine::getGPUAvailable() const { return false; }
bool RenderEngine::getGPUEnabled() const { return false; }
void RenderEngine::setGPUEnabled(bool enabled) {}
void RenderEngine::setRenderMode(RenderMode mode) { _renderMode.store(mode); }
RenderMode RenderEngine::getRenderMode() const { return _renderMode.load(); }
bool RenderEngine::isRendering() const { return false; }
RenderStatus RenderEngine::getRenderStatus() const { return {}; }
int RenderEngine::getFrameTimeMS() const { return 50; }
int RenderEngine::getNumFrames() const { return 0; }

void RenderEngine::notifyModelFrameRendered(const std::string& modelName, int timeMS) {}
void RenderEngine::notifyFrameRendered(int timeMS) {}
void RenderEngine::notifyRenderComplete(bool wasCancelled) {}
void RenderEngine::notifyRenderProgress(const RenderStatus& status) {}
void RenderEngine::notifyRenderError(const std::string& modelName, const std::string& message) {}

#else
// Legacy build: full implementation using xLightsFrame and render pipeline

// --- Construction / destruction ---

RenderEngine::RenderEngine(IRenderProvider* provider)
    : _provider(provider)
    , _frame(nullptr)
{
    // If the provider is a RenderContextAdapter, extract the frame pointer
    // for legacy operations not yet abstracted.
    if (auto* adapter = dynamic_cast<RenderContextAdapter*>(provider)) {
        _frame = adapter->getFrame();
    }
}

RenderEngine::RenderEngine(xLightsFrame* frame)
    : _provider(nullptr)
    , _frame(frame)
{
    // Create an owned adapter to wrap the frame
    _ownedAdapter = std::make_unique<RenderContextAdapter>(frame);
    _provider = _ownedAdapter.get();
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
    // Frame rendering requires xLightsFrame for now as IRenderProvider
    // only provides frame-indexed render requests, not time-based.
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
    if (_provider) {
        _provider->cancelRender();
        // Provider's cancelRender is non-blocking; return true as best effort
        return true;
    }
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
    if (_provider) {
        return _provider->isGPUAvailable();
    }
    return GPURenderUtils::IsEnabled();
}

bool RenderEngine::getGPUEnabled() const
{
    if (_provider) {
        return _provider->isGPUEnabled();
    }
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
    if (_provider) {
        return _provider->isRendering();
    }
    if (!_frame) return false;
    return !_frame->renderProgressInfo.empty();
}

RenderStatus RenderEngine::getRenderStatus() const
{
    RenderStatus status;

    if (_provider) {
        status.isRendering = _provider->isRendering();
        status.framesTotal = _provider->getTotalFrames();
        status.progressPercent = _provider->getRenderProgress() * 100.0f;
        return status;
    }

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
    if (_provider) {
        return _provider->getFrameTimeMS();
    }
    if (!_frame) return 50;
    if (!_frame->_seqData.IsValidData()) return 50;
    return _frame->_seqData.FrameTime();
}

int RenderEngine::getNumFrames() const
{
    if (_provider) {
        return _provider->getTotalFrames();
    }
    if (!_frame) return 0;
    if (!_frame->_seqData.IsValidData()) return 0;
    return _frame->_seqData.NumFrames();
}

#endif // XLIGHTS_NATIVE

} // namespace xlEngine
