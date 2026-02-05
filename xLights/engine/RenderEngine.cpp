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
#else
#include "../FSEQFile.h"
#include "ModelEngine.h"
#endif

#include <algorithm>

namespace xlEngine {

#ifdef XLIGHTS_NATIVE
// Native build: FSEQ-based rendering implementation
// Reads pre-rendered channel data from FSEQ files and maps to model pixels.

// Helper to parse StartChannel strings
static std::string trimString(const std::string& s) {
    size_t start = s.find_first_not_of(" \t\r\n");
    if (start == std::string::npos) return "";
    size_t end = s.find_last_not_of(" \t\r\n");
    return s.substr(start, end - start + 1);
}

RenderEngine::RenderEngine(IRenderProvider* provider)
    : _provider(provider)
{
}

RenderEngine::~RenderEngine()
{
    closeFSEQ();
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

// --- FSEQ Provider Setters ---

void RenderEngine::setModelProvider(IModelProvider* provider)
{
    _modelProvider = provider;
}

void RenderEngine::setOutputProvider(IOutputProvider* provider)
{
    _outputProvider = provider;
}

// --- FSEQ Loading ---

bool RenderEngine::loadFSEQ(const std::string& fseqPath)
{
    closeFSEQ();

    _fseqFile.reset(FSEQFile::openFSEQFile(fseqPath));
    if (!_fseqFile) {
        return false;
    }

    // Prepare for reading all channels
    _fseqFile->prepareRead({});

    // Build controller channel map for resolving !ControllerName:offset references
    buildControllerChannelMap();

    // Build model-to-channel mapping
    buildModelChannelMap();

    _fseqLoaded = true;
    _currentFrameIndex = -1;
    _currentFrameData.clear();

    return true;
}

void RenderEngine::closeFSEQ()
{
    _fseqFile.reset();
    _fseqLoaded = false;
    _currentFrameIndex = -1;
    _currentFrameData.clear();
    _modelChannelMap.clear();
    _controllerStartChannels.clear();

    std::lock_guard<std::mutex> lock(_bufferCacheMutex);
    _bufferCache.clear();
}

bool RenderEngine::isFSEQLoaded() const
{
    return _fseqLoaded;
}

// --- Controller Channel Map ---

void RenderEngine::buildControllerChannelMap()
{
    _controllerStartChannels.clear();
    if (!_outputProvider) return;

    size_t count = _outputProvider->getControllerCount();
    for (size_t i = 0; i < count; i++) {
        auto info = _outputProvider->getController(i);
        if (info.has_value() && !info->name.empty() && info->startChannel > 0) {
            _controllerStartChannels[info->name] = info->startChannel;
        }
    }
}

// --- StartChannel Resolution ---

uint32_t RenderEngine::resolveStartChannel(const std::string& startChannelStr)
{
    std::string sc = trimString(startChannelStr);
    if (sc.empty()) return 0;

    // Format 1: Plain number (e.g., "124123") - 1-based
    if (sc[0] >= '0' && sc[0] <= '9') {
        try {
            int ch = std::stoi(sc);
            return (ch > 0) ? static_cast<uint32_t>(ch - 1) : 0;
        } catch (...) {
            return 0;
        }
    }

    // Format 2: Controller reference (e.g., "!FPP-Chance:1")
    if (sc[0] == '!' && sc.size() > 1) {
        size_t colonPos = sc.find(':');
        if (colonPos != std::string::npos) {
            std::string controllerName = sc.substr(1, colonPos - 1);
            std::string offsetStr = sc.substr(colonPos + 1);
            int offset = 1;
            try { offset = std::stoi(offsetStr); } catch (...) {}

            auto it = _controllerStartChannels.find(controllerName);
            if (it != _controllerStartChannels.end()) {
                // Controller startChannel is 1-based, offset is 1-based
                // Absolute channel = controllerStart + offset - 1 (still 1-based)
                // Convert to 0-based: subtract 1 more
                int32_t absChannel = it->second + offset - 2;
                return (absChannel >= 0) ? static_cast<uint32_t>(absChannel) : 0;
            }
        }
        return 0;
    }

    // Format 3: Model reference (e.g., ">ModelName:1")
    if (sc[0] == '>' && sc.size() > 1 && _modelProvider) {
        size_t colonPos = sc.find(':');
        if (colonPos != std::string::npos) {
            std::string refModelName = sc.substr(1, colonPos - 1);
            std::string offsetStr = sc.substr(colonPos + 1);
            int offset = 1;
            try { offset = std::stoi(offsetStr); } catch (...) {}

            // Look up the referenced model's StartChannel and resolve recursively
            auto refAttrs = _modelProvider->getModelAttributes(refModelName);
            auto refIt = refAttrs.find("StartChannel");
            if (refIt != refAttrs.end()) {
                uint32_t refStart = resolveStartChannel(refIt->second);
                // Offset is 1-based relative to the referenced model's start
                return refStart + static_cast<uint32_t>(offset - 1);
            }
        }
        return 0;
    }

    return 0;
}

// --- Model Channel Map ---

void RenderEngine::buildModelChannelMap()
{
    _modelChannelMap.clear();
    if (!_modelProvider) return;

    auto modelNames = _modelProvider->getModelNames();
    // Use a temporary ModelEngine to get node data
    ModelEngine tempEngine(_modelProvider);

    for (const auto& name : modelNames) {
        auto attrs = _modelProvider->getModelAttributes(name);
        if (attrs.empty()) continue;

        // Skip groups
        auto displayAs = attrs.find("DisplayAs");
        if (displayAs != attrs.end() && displayAs->second == "ModelGroup") continue;

        // Get StartChannel
        auto scIt = attrs.find("StartChannel");
        if (scIt == attrs.end() || scIt->second.empty()) continue;

        uint32_t absStart = resolveStartChannel(scIt->second);

        // Get node data for buffer mapping
        auto nodes = tempEngine.getModelNodes(name);
        if (nodes.empty()) continue;

        // Determine channels per node from StringType
        uint32_t chansPerNode = 3; // default RGB
        auto stIt = attrs.find("StringType");
        if (stIt != attrs.end()) {
            const std::string& st = stIt->second;
            if (st.find("4 Channel") != std::string::npos ||
                st.find("RGBW") != std::string::npos) {
                chansPerNode = 4;
            } else if (st.find("Single Color") != std::string::npos) {
                chansPerNode = 1;
            }
        }

        // Calculate buffer dimensions from node coordinates
        int maxBufX = 0, maxBufY = 0;
        for (const auto& node : nodes) {
            if (node.bufX > maxBufX) maxBufX = node.bufX;
            if (node.bufY > maxBufY) maxBufY = node.bufY;
        }

        ModelChannelInfo info;
        info.absStartChannel = absStart;
        info.nodeCount = static_cast<uint32_t>(nodes.size());
        info.chansPerNode = chansPerNode;
        info.bufferWidth = maxBufX + 1;
        info.bufferHeight = maxBufY + 1;

        info.nodeBufCoords.reserve(nodes.size());
        for (const auto& node : nodes) {
            info.nodeBufCoords.push_back({node.bufX, node.bufY});
        }

        _modelChannelMap[name] = std::move(info);
    }
}

// --- Frame Rendering ---

void RenderEngine::renderFrame(int timeMS)
{
    if (!_fseqLoaded || !_fseqFile) return;

    int stepTime = _fseqFile->getStepTime();
    if (stepTime <= 0) stepTime = 50;

    int frameIndex = timeMS / stepTime;
    if (frameIndex < 0) frameIndex = 0;
    int numFrames = static_cast<int>(_fseqFile->getNumFrames());
    if (numFrames > 0 && frameIndex >= numFrames) {
        frameIndex = numFrames - 1;
    }

    // Skip if we already have this frame cached
    if (frameIndex == _currentFrameIndex) return;

    // Read frame data from FSEQ
    FSEQFile::FrameData* fd = _fseqFile->getFrame(static_cast<uint32_t>(frameIndex));
    if (!fd) return;

    uint32_t maxCh = static_cast<uint32_t>(_fseqFile->getChannelCount());
    _currentFrameData.resize(maxCh, 0);
    fd->readFrame(_currentFrameData.data(), maxCh);
    delete fd;
    _currentFrameIndex = frameIndex;

    // Build FrameBuffers for all mapped models
    std::lock_guard<std::mutex> lock(_bufferCacheMutex);
    _bufferCache.clear();

    for (const auto& [modelName, chInfo] : _modelChannelMap) {
        if (chInfo.bufferWidth <= 0 || chInfo.bufferHeight <= 0) continue;

        FrameBuffer fb;
        fb.modelName = modelName;
        fb.width = chInfo.bufferWidth;
        fb.height = chInfo.bufferHeight;
        fb.timeMS = timeMS;
        fb.pixels.resize(static_cast<size_t>(fb.width) * fb.height * 4, 0);

        // Map each node's channel data to the pixel buffer
        for (uint32_t i = 0; i < chInfo.nodeCount; i++) {
            uint32_t nodeChannel = chInfo.absStartChannel + (i * chInfo.chansPerNode);
            if (nodeChannel + 2 >= static_cast<uint32_t>(_currentFrameData.size())) continue;

            uint8_t r = _currentFrameData[nodeChannel];
            uint8_t g = _currentFrameData[nodeChannel + 1];
            uint8_t b = _currentFrameData[nodeChannel + 2];

            int bx = chInfo.nodeBufCoords[i].first;
            int by = chInfo.nodeBufCoords[i].second;
            if (bx < 0 || bx >= fb.width || by < 0 || by >= fb.height) continue;

            size_t idx = (static_cast<size_t>(by) * fb.width + bx) * 4;
            fb.pixels[idx]     = r;
            fb.pixels[idx + 1] = g;
            fb.pixels[idx + 2] = b;
            fb.pixels[idx + 3] = 255;
        }

        _bufferCache[modelName] = std::move(fb);
    }

    notifyFrameRendered(timeMS);
}

void RenderEngine::renderModelFrame(const std::string& modelName, int timeMS)
{
    // For FSEQ playback, just render the full frame (it's fast)
    renderFrame(timeMS);
}

void RenderEngine::renderAll(RenderCompleteCallback callback)
{
    // No-op for FSEQ playback (data is already pre-rendered in the file)
    if (callback) callback(false);
}

void RenderEngine::renderRange(int startMS, int endMS, bool clear, RenderCompleteCallback callback)
{
    if (callback) callback(false);
}

void RenderEngine::renderModelRange(const std::string& modelName, int startMS, int endMS, bool clear) {}
bool RenderEngine::abortRender(int timeoutMS) { return true; }

FrameBuffer RenderEngine::getFrameBuffer(const std::string& modelName) const
{
    std::lock_guard<std::mutex> lock(_bufferCacheMutex);
    auto it = _bufferCache.find(modelName);
    if (it != _bufferCache.end()) {
        return it->second;
    }
    return {};
}

std::vector<NodeChannelData> RenderEngine::getNodeData(const std::string& modelName) const
{
    if (!_fseqLoaded) return {};

    auto mapIt = _modelChannelMap.find(modelName);
    if (mapIt == _modelChannelMap.end()) return {};

    const auto& chInfo = mapIt->second;
    std::vector<NodeChannelData> result;
    result.reserve(chInfo.nodeCount);

    for (uint32_t i = 0; i < chInfo.nodeCount; i++) {
        NodeChannelData ncd;
        ncd.startChannel = chInfo.absStartChannel + (i * chInfo.chansPerNode);
        ncd.channelCount = chInfo.chansPerNode;
        ncd.data.resize(chInfo.chansPerNode, 0);

        if (_currentFrameIndex >= 0 && ncd.startChannel + chInfo.chansPerNode <= _currentFrameData.size()) {
            for (uint32_t c = 0; c < chInfo.chansPerNode; c++) {
                ncd.data[c] = _currentFrameData[ncd.startChannel + c];
            }
        }
        result.push_back(std::move(ncd));
    }
    return result;
}

int RenderEngine::getLayerCount(const std::string& modelName) const { return 0; }
void RenderEngine::setMixMode(const std::string& modelName, int layer, MixMode mode) {}
MixMode RenderEngine::getMixMode(const std::string& modelName, int layer) const { return MixMode::Normal; }
std::vector<std::string> RenderEngine::getMixModeNames() { return {}; }

ModelRenderInfo RenderEngine::getModelRenderInfo(const std::string& modelName) const
{
    ModelRenderInfo info;
    auto it = _modelChannelMap.find(modelName);
    if (it != _modelChannelMap.end()) {
        info.modelName = modelName;
        info.bufferWidth = it->second.bufferWidth;
        info.bufferHeight = it->second.bufferHeight;
        info.nodeCount = it->second.nodeCount;
        info.channelCount = it->second.nodeCount * it->second.chansPerNode;
    }
    return info;
}

std::vector<ModelRenderInfo> RenderEngine::getAllModelRenderInfo() const
{
    std::vector<ModelRenderInfo> result;
    for (const auto& [name, _] : _modelChannelMap) {
        result.push_back(getModelRenderInfo(name));
    }
    return result;
}

void RenderEngine::invalidateCache(const std::string& modelName)
{
    std::lock_guard<std::mutex> lock(_bufferCacheMutex);
    _bufferCache.erase(modelName);
    _currentFrameIndex = -1; // Force re-read on next renderFrame
}

void RenderEngine::invalidateAllCaches()
{
    std::lock_guard<std::mutex> lock(_bufferCacheMutex);
    _bufferCache.clear();
    _currentFrameIndex = -1;
}

bool RenderEngine::getGPUAvailable() const { return false; }
bool RenderEngine::getGPUEnabled() const { return false; }
void RenderEngine::setGPUEnabled(bool enabled) {}
void RenderEngine::setRenderMode(RenderMode mode) { _renderMode.store(mode); }
RenderMode RenderEngine::getRenderMode() const { return _renderMode.load(); }
bool RenderEngine::isRendering() const { return false; }
RenderStatus RenderEngine::getRenderStatus() const { return {}; }

int RenderEngine::getFrameTimeMS() const
{
    if (_fseqLoaded && _fseqFile) {
        return _fseqFile->getStepTime();
    }
    return 50;
}

int RenderEngine::getNumFrames() const
{
    if (_fseqLoaded && _fseqFile) {
        return static_cast<int>(_fseqFile->getNumFrames());
    }
    return 0;
}

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
