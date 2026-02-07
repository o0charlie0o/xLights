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
#include "render/NativeRenderCoordinator.h"
#include "render/NativeSequenceData.h"
#include "render/IRenderContext.h"
#include "interfaces/IEffectProvider.h"
#endif

#include <algorithm>
#include <cstring>
#include <chrono>

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

void RenderEngine::setEffectProvider(IEffectProvider* provider)
{
    _effectProvider = provider;
}

// Lightweight IRenderContext adapter for the coordinator
namespace {
class RenderEngineContext : public IRenderContext {
public:
    RenderEngineContext(int frameTimeMS, double sequenceDuration)
        : _frameTimeMS(frameTimeMS), _duration(sequenceDuration) {}

    void* getAudioManager() override { return nullptr; }
    double getSequenceDuration() override { return _duration; }
    int getFrameTimeMS() override { return _frameTimeMS; }

private:
    int _frameTimeMS;
    double _duration;
};
} // anonymous namespace

// --- FSEQ Loading ---

bool RenderEngine::loadFSEQ(const std::string& fseqPath)
{
    closeFSEQ();
    _fseqPath = fseqPath;

    _fseqFile.reset(FSEQFile::openFSEQFile(fseqPath));
    if (!_fseqFile) {
        return false;
    }

    // Prepare for reading all channels
    _fseqFile->prepareRead({});

    // Build controller channel map for resolving !ControllerName:offset references
    buildControllerChannelMap();

    // Pre-compute total channel count for each model (needed for >ModelName:offset resolution)
    buildModelTotalChannelsMap();

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
    printf("RenderEngine: Building controller channel map — %zu controllers\n", count);
    for (size_t i = 0; i < count; i++) {
        auto info = _outputProvider->getController(i);
        if (info.has_value()) {
            printf("RenderEngine: Controller[%zu] '%s' — startCh=%d, channels=%d, protocol=%s\n",
                   i, info->name.c_str(), info->startChannel, info->channels,
                   info->protocol.c_str());
            if (!info->name.empty() && info->startChannel > 0) {
                _controllerStartChannels[info->name] = info->startChannel;
            }
        }
    }
}

// --- Model Total Channels Map ---

void RenderEngine::buildModelTotalChannelsMap()
{
    _modelTotalChannels.clear();
    _resolvedStartChannels.clear();
    if (!_modelProvider) return;

    ModelEngine tempEngine(_modelProvider);
    auto modelNames = _modelProvider->getModelNames();

    for (const auto& name : modelNames) {
        auto attrs = _modelProvider->getModelAttributes(name);
        if (attrs.empty()) continue;

        // Skip groups
        auto displayAs = attrs.find("DisplayAs");
        if (displayAs != attrs.end() && displayAs->second == "ModelGroup") continue;

        // Get node count from actual node generation
        auto nodes = tempEngine.getModelNodes(name);
        uint32_t nodeCount = static_cast<uint32_t>(nodes.size());
        if (nodeCount == 0) nodeCount = 1;

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

        _modelTotalChannels[name] = nodeCount * chansPerNode;
    }
}

// --- StartChannel Resolution ---

uint32_t RenderEngine::resolveStartChannel(const std::string& startChannelStr)
{
    std::string sc = trimString(startChannelStr);
    if (sc.empty()) return 0;

    // Check memoization cache to avoid redundant chain resolution
    auto cacheIt = _resolvedStartChannels.find(sc);
    if (cacheIt != _resolvedStartChannels.end()) {
        return cacheIt->second;
    }

    uint32_t result = 0;

    // Format 1: Plain number (e.g., "124123") - 1-based
    if (sc[0] >= '0' && sc[0] <= '9') {
        try {
            int ch = std::stoi(sc);
            result = (ch > 0) ? static_cast<uint32_t>(ch - 1) : 0;
        } catch (...) {
            result = 0;
        }
    }
    // Format 2: IP reference (e.g., "#192.168.1.11:1:1" = #IP:universe:channel)
    else if (sc[0] == '#' && sc.size() > 1) {
        // Parse #IP:universe:channel
        size_t firstColon = sc.find(':', 1);
        if (firstColon != std::string::npos) {
            std::string ip = sc.substr(1, firstColon - 1);
            size_t secondColon = sc.find(':', firstColon + 1);
            int universe = 1, channel = 1;
            if (secondColon != std::string::npos) {
                try { universe = std::stoi(sc.substr(firstColon + 1, secondColon - firstColon - 1)); } catch (...) {}
                try { channel = std::stoi(sc.substr(secondColon + 1)); } catch (...) {}
            } else {
                try { universe = std::stoi(sc.substr(firstColon + 1)); } catch (...) {}
            }

            // Look up child network entry by IP and universe number.
            // Child entries are named like "E131_IP_universe" or "DDP_IP".
            bool found = false;
            for (const auto& [proto, prefix] : std::initializer_list<std::pair<const char*, const char*>>{
                    {"E131", "E131_"}, {"ArtNet", "ArtNet_"}, {"DDP", "DDP_"}}) {
                std::string lookupName = std::string(prefix) + ip;
                if (std::string(proto) != "DDP") {
                    lookupName += "_" + std::to_string(universe);
                }
                auto it = _controllerStartChannels.find(lookupName);
                if (it != _controllerStartChannels.end()) {
                    // Controller startChannel is 1-based, channel offset is 1-based
                    result = static_cast<uint32_t>(it->second - 1) + static_cast<uint32_t>(channel - 1);
                    found = true;
                    break;
                }
            }

            if (!found) {
                printf("RenderEngine: WARNING — cannot resolve '%s' (no controller at IP %s universe %d)\n",
                       sc.c_str(), ip.c_str(), universe);
            }
        }
    }
    // Format 3: Controller name reference (e.g., "!FPP-Chance:1")
    else if (sc[0] == '!' && sc.size() > 1) {
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
                result = (absChannel >= 0) ? static_cast<uint32_t>(absChannel) : 0;
            }
        }
    }
    // Format 3: Model reference (e.g., ">ModelName:1")
    // In xLights, ">ModelName:N" means "start at channel N after the END of ModelName"
    // So the absolute start = refModelStart + refModelTotalChannels + (N - 1)
    else if (sc[0] == '>' && sc.size() > 1 && _modelProvider) {
        size_t colonPos = sc.find(':');
        if (colonPos != std::string::npos) {
            std::string refModelName = sc.substr(1, colonPos - 1);
            std::string offsetStr = sc.substr(colonPos + 1);
            int offset = 1;
            try { offset = std::stoi(offsetStr); } catch (...) {}

            // Resolve the referenced model's start channel recursively
            auto refAttrs = _modelProvider->getModelAttributes(refModelName);
            auto refIt = refAttrs.find("StartChannel");
            if (refIt != refAttrs.end()) {
                uint32_t refStart = resolveStartChannel(refIt->second);

                // Look up the referenced model's total channel count from pre-computed map
                uint32_t refTotalChannels = 0;
                auto tcIt = _modelTotalChannels.find(refModelName);
                if (tcIt != _modelTotalChannels.end()) {
                    refTotalChannels = tcIt->second;
                }

                // Position after the referenced model's channels
                result = refStart + refTotalChannels + static_cast<uint32_t>(offset - 1);
            }
        }
    }

    // Cache the result for future lookups
    _resolvedStartChannels[sc] = result;
    return result;
}

// --- Model Channel Map ---

void RenderEngine::buildModelChannelMap()
{
    _modelChannelMap.clear();
    if (!_modelProvider) return;

    auto modelNames = _modelProvider->getModelNames();
    // Use a temporary ModelEngine to get node data
    ModelEngine tempEngine(_modelProvider);

    size_t skippedCount = 0;

    for (const auto& name : modelNames) {
        auto attrs = _modelProvider->getModelAttributes(name);
        if (attrs.empty()) {
            printf("RenderEngine: Model '%s' skipped — empty attributes\n", name.c_str());
            skippedCount++;
            continue;
        }

        // Skip groups
        auto displayAs = attrs.find("DisplayAs");
        if (displayAs != attrs.end() && displayAs->second == "ModelGroup") continue;

        std::string displayAsStr = (displayAs != attrs.end()) ? displayAs->second : "Unknown";

        // Get StartChannel
        auto scIt = attrs.find("StartChannel");
        if (scIt == attrs.end() || scIt->second.empty()) {
            printf("RenderEngine: Model '%s' (%s) skipped — no StartChannel attribute\n",
                   name.c_str(), displayAsStr.c_str());
            skippedCount++;
            continue;
        }

        uint32_t absStart = resolveStartChannel(scIt->second);

        // Get node data for buffer mapping
        auto nodes = tempEngine.getModelNodes(name);
        if (nodes.empty()) {
            printf("RenderEngine: Model '%s' (%s) skipped — no nodes generated\n",
                   name.c_str(), displayAsStr.c_str());
            skippedCount++;
            continue;
        }

        // Determine channels per node and color order from StringType
        uint32_t chansPerNode = 3; // default RGB
        uint8_t rOff = 0, gOff = 1, bOff = 2; // default RGB order
        auto stIt = attrs.find("StringType");
        if (stIt != attrs.end()) {
            const std::string& st = stIt->second;
            if (st.find("4 Channel") != std::string::npos ||
                st.find("RGBW") != std::string::npos) {
                chansPerNode = 4;
            } else if (st.find("Single Color") != std::string::npos) {
                chansPerNode = 1;
            }
            // Parse color order from StringType.
            // FSEQ stores data in the controller's native color order.
            // We need to map back to RGB for display.
            // StringType formats: "RGB Nodes", "GRB Nodes", "RGBW Nodes", "WRGB Nodes",
            //                     "4 Channel RGBW", "4 Channel WRGB", etc.
            if (chansPerNode >= 3 && st.size() >= 3) {
                std::string colorChars;
                int baseOffset = 0;
                if (st[0] == 'W' && st.size() >= 4 && st[1] >= 'A' && st[1] <= 'Z') {
                    // W-prefix: WRGB, WGRB, etc. — W at ch0, color at ch1-3
                    colorChars = st.substr(1, 3);
                    baseOffset = 1;
                } else if (st.compare(0, 10, "4 Channel ") == 0 && st.size() >= 14) {
                    // "4 Channel RGBW" or "4 Channel WRGB"
                    std::string suffix = st.substr(10);
                    if (suffix[0] == 'W') {
                        colorChars = suffix.substr(1, 3);
                        baseOffset = 1;
                    } else {
                        colorChars = suffix.substr(0, 3);
                        baseOffset = 0;
                    }
                } else if (st[0] >= 'A' && st[0] <= 'Z') {
                    // Standard: RGB, GRB, BRG, etc. (3-ch or RGBW with W suffix)
                    colorChars = st.substr(0, 3);
                    baseOffset = 0;
                }
                if (colorChars.size() == 3) {
                    for (int ci = 0; ci < 3; ci++) {
                        if (colorChars[ci] == 'R') rOff = static_cast<uint8_t>(ci + baseOffset);
                        else if (colorChars[ci] == 'G') gOff = static_cast<uint8_t>(ci + baseOffset);
                        else if (colorChars[ci] == 'B') bOff = static_cast<uint8_t>(ci + baseOffset);
                    }
                }
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
        info.rOffset = rOff;
        info.gOffset = gOff;
        info.bOffset = bOff;

        info.nodeBufCoords.reserve(nodes.size());
        for (const auto& node : nodes) {
            info.nodeBufCoords.push_back({node.bufX, node.bufY});
        }

        std::string stringTypeStr = (stIt != attrs.end()) ? stIt->second : "default";

        printf("RenderEngine: Model '%s' (%s) mapped — startCh=%u (%s), nodes=%u, buffer=%dx%d, chansPerNode=%u, stringType='%s', rgbOffsets=[%d,%d,%d]\n",
               name.c_str(), displayAsStr.c_str(), info.absStartChannel,
               scIt->second.c_str(), info.nodeCount,
               info.bufferWidth, info.bufferHeight, info.chansPerNode,
               stringTypeStr.c_str(), info.rOffset, info.gOffset, info.bOffset);

        // Extra diagnostics for matrix models: show zigzag parameters and first node coords
        if (displayAsStr.find("Matrix") != std::string::npos) {
            auto dirIt = attrs.find("Dir");
            auto ssIt = attrs.find("StartSide");
            auto nzIt = attrs.find("NoZig");
            auto p1It = attrs.find("parm1");
            auto p2It = attrs.find("parm2");
            auto p3It = attrs.find("parm3");
            int p1v = p1It != attrs.end() ? atoi(p1It->second.c_str()) : 0;
            int p2v = p2It != attrs.end() ? atoi(p2It->second.c_str()) : 0;
            int p3v = p3It != attrs.end() ? atoi(p3It->second.c_str()) : 1;
            printf("RenderEngine:   Matrix params — Dir='%s', StartSide='%s', NoZig='%s', parm1=%d, parm2=%d, parm3=%d\n",
                   dirIt != attrs.end() ? dirIt->second.c_str() : "(missing)",
                   ssIt != attrs.end() ? ssIt->second.c_str() : "(missing)",
                   nzIt != attrs.end() ? nzIt->second.c_str() : "(missing)",
                   p1v, p2v, p3v);
            // Show first 5 node buffer coords
            size_t n = info.nodeBufCoords.size();
            size_t show = std::min(n, (size_t)5);
            printf("RenderEngine:   First %zu nodes: ", show);
            for (size_t j = 0; j < show; j++) {
                printf("[%d](%d,%d) ", (int)j, info.nodeBufCoords[j].first, info.nodeBufCoords[j].second);
            }
            printf("\n");
            if (n > 10) {
                // Show nodes at strand boundary (pixelsPerStrand-1, pixelsPerStrand, pixelsPerStrand+1)
                if (p3v < 1) p3v = 1;
                int pps = p2v / p3v;
                if (pps > 0 && (size_t)(pps + 1) < n) {
                    printf("RenderEngine:   Strand boundary (pps=%d): [%d](%d,%d) [%d](%d,%d) [%d](%d,%d)\n",
                           pps,
                           pps-1, info.nodeBufCoords[pps-1].first, info.nodeBufCoords[pps-1].second,
                           pps, info.nodeBufCoords[pps].first, info.nodeBufCoords[pps].second,
                           pps+1, info.nodeBufCoords[pps+1].first, info.nodeBufCoords[pps+1].second);
                }
            }
        }

        _modelChannelMap[name] = std::move(info);
    }

    printf("RenderEngine: Mapped %zu models out of %zu total (%zu skipped)\n",
           _modelChannelMap.size(), modelNames.size(), skippedCount);
}

// --- Frame Rendering ---

void RenderEngine::renderFrame(int timeMS)
{
    if (_fseqLoaded && _fseqFile) {
        // FSEQ playback path: read pre-rendered channel data
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
                if (nodeChannel + chInfo.chansPerNode > static_cast<uint32_t>(_currentFrameData.size())) continue;

                uint8_t r = _currentFrameData[nodeChannel + chInfo.rOffset];
                uint8_t g = _currentFrameData[nodeChannel + chInfo.gOffset];
                uint8_t b = _currentFrameData[nodeChannel + chInfo.bOffset];

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
    } else if (_renderedData && _renderedData->isValid() && !_modelChannelMap.empty()) {
        // Pre-rendered data path: read from in-memory rendered data (from renderAll)
        // This is the same as the FSEQ path but reads from NativeSequenceData in memory.
        int stepTime = static_cast<int>(_renderedData->getFrameTimeMS());
        if (stepTime <= 0) stepTime = 50;

        int frameIndex = timeMS / stepTime;
        if (frameIndex < 0) frameIndex = 0;
        int numFrames = static_cast<int>(_renderedData->getNumFrames());
        if (numFrames > 0 && frameIndex >= numFrames) {
            frameIndex = numFrames - 1;
        }

        // Skip if we already have this frame cached
        if (frameIndex == _currentFrameIndex) return;

        // Read frame data from pre-rendered buffer
        const uint8_t* frameData = _renderedData->getFrame(static_cast<uint32_t>(frameIndex));
        if (!frameData) return;

        uint32_t numChannels = _renderedData->getNumChannels();
        _currentFrameData.resize(numChannels, 0);
        std::memcpy(_currentFrameData.data(), frameData, numChannels);
        _currentFrameIndex = frameIndex;

        // Build FrameBuffers for all mapped models (same logic as FSEQ path)
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

            for (uint32_t i = 0; i < chInfo.nodeCount; i++) {
                uint32_t nodeChannel = chInfo.absStartChannel + (i * chInfo.chansPerNode);
                if (nodeChannel + chInfo.chansPerNode > static_cast<uint32_t>(_currentFrameData.size())) continue;

                uint8_t r = _currentFrameData[nodeChannel + chInfo.rOffset];
                uint8_t g = _currentFrameData[nodeChannel + chInfo.gOffset];
                uint8_t b = _currentFrameData[nodeChannel + chInfo.bOffset];

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
    } else if (_effectProvider && _modelProvider) {
        // Effect-based live rendering with persistent state.
        // The coordinator and its ModelJobs are kept alive across frames so
        // stateful effects (Fire, etc.) accumulate properly.
        int frameTimeMS = _provider ? _provider->getFrameTimeMS() : 50;
        if (frameTimeMS <= 0) frameTimeMS = 50;

        int durationMS = _provider ? _provider->getSequenceDurationMS() : 0;
        if (durationMS <= 0) {
            int totalFrames = _provider ? _provider->getTotalFrames() : 0;
            durationMS = (totalFrames > 0) ? totalFrames * frameTimeMS : 60000;
        }
        double durationSec = durationMS / 1000.0;

        auto modelNames = _modelProvider->getModelNames();

        auto frameStart = std::chrono::steady_clock::now();
        int modelsRendered = 0;

        std::lock_guard<std::mutex> lock(_bufferCacheMutex);

        // Create or reuse persistent live coordinator.
        // Must be under _bufferCacheMutex because invalidateAllCaches() can
        // reset _liveCoordinator from another thread while holding this lock.
        if (!_liveCoordinator) {
            _liveContext = std::make_unique<RenderEngineContext>(frameTimeMS, durationSec);
            _liveCoordinator = std::make_unique<NativeRenderCoordinator>(
                _effectProvider, _modelProvider, _liveContext.get());
            _lastLiveRenderTimeMS = -1;
        }

        // Detect backward scrub: if time went backward, reset effect state
        // so stateful effects restart cleanly rather than showing stale data.
        if (_lastLiveRenderTimeMS >= 0 && timeMS < _lastLiveRenderTimeMS) {
            _liveCoordinator->resetPersistentState();
        }
        _lastLiveRenderTimeMS = timeMS;
        _bufferCache.clear();

        for (const auto& name : modelNames) {
            auto modelStart = std::chrono::steady_clock::now();
            RenderedFrame rf = _liveCoordinator->renderModelFrameStateful(name, timeMS);
            auto modelEnd = std::chrono::steady_clock::now();
            auto modelUS = std::chrono::duration_cast<std::chrono::microseconds>(modelEnd - modelStart).count();

            if (rf.isValid()) {
                if (modelUS > 2000) { // Log models taking > 2ms
                    printf("[LiveRender] Model '%s' took %.1fms (%dx%d)\n",
                           name.c_str(), modelUS / 1000.0, rf.width, rf.height);
                }
                modelsRendered++;
                FrameBuffer fb;
                fb.modelName = rf.modelName;
                fb.width = rf.width;
                fb.height = rf.height;
                fb.timeMS = rf.timeMS;
                fb.pixels = std::move(rf.pixels);
                _bufferCache[name] = std::move(fb);
            }
            // Models with no effects return empty frames — skip them entirely.
            // No need to create zeroed buffers for 196 inactive models.
        }

        auto frameEnd = std::chrono::steady_clock::now();
        auto frameUS = std::chrono::duration_cast<std::chrono::microseconds>(frameEnd - frameStart).count();
        printf("[LiveRender] Frame @%dms: %d models rendered in %.1fms (budget=%dms)\n",
               timeMS, modelsRendered, frameUS / 1000.0, frameTimeMS);

        notifyFrameRendered(timeMS);
    }
}

void RenderEngine::renderModelFrame(const std::string& modelName, int timeMS)
{
    if (_fseqLoaded && _fseqFile) {
        // For FSEQ playback, render the full frame (channel data is interleaved)
        renderFrame(timeMS);
    } else if (_renderedData && _renderedData->isValid() && !_modelChannelMap.empty()) {
        // Pre-rendered data available — use the full-frame path which reads from memory
        renderFrame(timeMS);
    } else if (_effectProvider && _modelProvider) {
        // Targeted single-model live rendering with persistent state
        int frameTimeMS = _provider ? _provider->getFrameTimeMS() : 50;
        if (frameTimeMS <= 0) frameTimeMS = 50;

        int durationMS = _provider ? _provider->getSequenceDurationMS() : 0;
        if (durationMS <= 0) {
            int totalFrames = _provider ? _provider->getTotalFrames() : 0;
            durationMS = (totalFrames > 0) ? totalFrames * frameTimeMS : 60000;
        }
        double durationSec = durationMS / 1000.0;

        std::lock_guard<std::mutex> lock(_bufferCacheMutex);

        // Create or reuse persistent live coordinator.
        // Must be under _bufferCacheMutex because invalidateAllCaches() can
        // reset _liveCoordinator from another thread while holding this lock.
        if (!_liveCoordinator) {
            _liveContext = std::make_unique<RenderEngineContext>(frameTimeMS, durationSec);
            _liveCoordinator = std::make_unique<NativeRenderCoordinator>(
                _effectProvider, _modelProvider, _liveContext.get());
            _lastLiveRenderTimeMS = -1;
        }

        if (_lastLiveRenderTimeMS >= 0 && timeMS < _lastLiveRenderTimeMS) {
            _liveCoordinator->resetPersistentState(modelName);
        }
        _lastLiveRenderTimeMS = timeMS;

        RenderedFrame rf = _liveCoordinator->renderModelFrameStateful(modelName, timeMS);
        if (rf.isValid()) {
            FrameBuffer fb;
            fb.modelName = rf.modelName;
            fb.width = rf.width;
            fb.height = rf.height;
            fb.timeMS = rf.timeMS;
            fb.pixels = std::move(rf.pixels);
            _bufferCache[modelName] = std::move(fb);

            notifyModelFrameRendered(modelName, timeMS);
        }
    }
}

void RenderEngine::renderAll(RenderCompleteCallback callback)
{
    if (!_effectProvider || !_modelProvider) {
        printf("RenderEngine::renderAll — missing effect or model provider, skipping\n");
        if (callback) callback(false);
        notifyRenderComplete(false);
        return;
    }

    // Determine sequence parameters
    int frameTimeMS = getFrameTimeMS();
    int numFrames = getNumFrames();
    int32_t totalChannels = _outputProvider ? _outputProvider->getTotalChannels() : 0;

    if (numFrames <= 0 || totalChannels <= 0) {
        printf("RenderEngine::renderAll — invalid sequence: %d frames, %d channels\n",
               numFrames, totalChannels);
        if (callback) callback(false);
        notifyRenderComplete(false);
        return;
    }

    double duration = static_cast<double>(numFrames) * frameTimeMS / 1000.0;
    printf("RenderEngine::renderAll — rendering %d frames (%dms), %d channels, %.1fs\n",
           numFrames, frameTimeMS, totalChannels, duration);

    // Create render context
    auto context = std::make_unique<RenderEngineContext>(frameTimeMS, duration);

    // Allocate output buffer
    _renderedData = std::make_unique<NativeSequenceData>(
        static_cast<uint32_t>(totalChannels),
        static_cast<uint32_t>(numFrames),
        static_cast<uint32_t>(frameTimeMS));

    // Create coordinator and set up progress forwarding
    _coordinator = std::make_unique<NativeRenderCoordinator>(
        _effectProvider, _modelProvider, context.get());

    // Bridge coordinator listener to RenderEngineListener
    class ListenerBridge : public RenderCoordinatorListener {
    public:
        explicit ListenerBridge(RenderEngine* engine) : _engine(engine) {}
        void onRenderProgress(float pct, int done, int total) override {
            RenderStatus status;
            status.isRendering = true;
            status.modelsComplete = done;
            status.modelsTotal = total;
            status.progressPercent = pct;
            _engine->notifyRenderProgress(status);
        }
        void onRenderError(const std::string& model, const std::string& msg) override {
            _engine->notifyRenderError(model, msg);
        }
    private:
        RenderEngine* _engine;
    };

    ListenerBridge bridge(this);
    _coordinator->setListener(&bridge);

    bool completed = _coordinator->renderAll(*_renderedData);

    _coordinator->setListener(nullptr);
    _coordinator.reset();

    bool wasCancelled = !completed;
    notifyRenderComplete(wasCancelled);
    if (callback) callback(wasCancelled);

    // After successful render, build the model channel map so renderFrame()
    // can read from _renderedData instead of re-rendering effects live.
    if (!wasCancelled && _renderedData && _renderedData->isValid()) {
        if (_modelChannelMap.empty()) {
            buildControllerChannelMap();
            buildModelTotalChannelsMap();
            buildModelChannelMap();
        }
        // Reset frame cache so next renderFrame reads from _renderedData
        _currentFrameIndex = -1;
        printf("RenderEngine::renderAll — rendered data ready for preview (%u frames, %u channels)\n",
               _renderedData->getNumFrames(), _renderedData->getNumChannels());
    }

    printf("RenderEngine::renderAll — %s\n", wasCancelled ? "cancelled" : "complete");
}

void RenderEngine::renderRange(int startMS, int endMS, bool clear,
                               RenderCompleteCallback callback)
{
    if (!_effectProvider || !_modelProvider) {
        if (callback) callback(false);
        return;
    }

    int frameTimeMS = getFrameTimeMS();
    int32_t totalChannels = _outputProvider ? _outputProvider->getTotalChannels() : 0;
    int numFrames = getNumFrames();

    if (numFrames <= 0 || totalChannels <= 0) {
        if (callback) callback(false);
        return;
    }

    double duration = static_cast<double>(numFrames) * frameTimeMS / 1000.0;
    auto context = std::make_unique<RenderEngineContext>(frameTimeMS, duration);

    // Reuse or create sequence data buffer
    if (!_renderedData || _renderedData->getNumChannels() != static_cast<uint32_t>(totalChannels)
        || _renderedData->getNumFrames() != static_cast<uint32_t>(numFrames)) {
        _renderedData = std::make_unique<NativeSequenceData>(
            static_cast<uint32_t>(totalChannels),
            static_cast<uint32_t>(numFrames),
            static_cast<uint32_t>(frameTimeMS));
    }

    if (clear) {
        int startFrame = startMS / frameTimeMS;
        int endFrame = std::min(endMS / frameTimeMS, numFrames);
        for (int f = startFrame; f < endFrame; ++f) {
            _renderedData->zeroFrame(static_cast<uint32_t>(f));
        }
    }

    _coordinator = std::make_unique<NativeRenderCoordinator>(
        _effectProvider, _modelProvider, context.get());

    bool completed = _coordinator->renderRange(startMS, endMS, *_renderedData);

    _coordinator.reset();

    bool wasCancelled = !completed;
    notifyRenderComplete(wasCancelled);
    if (callback) callback(wasCancelled);
}

void RenderEngine::renderModelRange(const std::string& modelName,
                                    int startMS, int endMS, bool clear)
{
    // For now, render the full range (model-specific filtering can be added later)
    renderRange(startMS, endMS, clear, nullptr);
}

bool RenderEngine::abortRender(int timeoutMS)
{
    if (_coordinator) {
        _coordinator->abort();
        // Wait for completion (coordinator blocks in renderAll/renderRange)
        // The abort flag will cause the render to exit within one frame time
        return true;
    }
    return true;
}

bool RenderEngine::exportRenderedFSEQ(const std::string& outputPath,
                                      int compressionLevel)
{
    if (!_renderedData) return false;
    return _renderedData->exportToFSEQ(outputPath, compressionLevel);
}

FrameBuffer RenderEngine::getFrameBuffer(const std::string& modelName) const
{
    std::lock_guard<std::mutex> lock(_bufferCacheMutex);
    auto it = _bufferCache.find(modelName);
    if (it != _bufferCache.end()) {
        return it->second;
    }
    return {};
}

std::vector<FrameBuffer> RenderEngine::getAllFrameBuffers() const
{
    std::lock_guard<std::mutex> lock(_bufferCacheMutex);
    std::vector<FrameBuffer> result;
    result.reserve(_bufferCache.size());
    for (const auto& [name, fb] : _bufferCache) {
        if (fb.isValid()) {
            result.push_back(fb);
        }
    }
    return result;
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
    // Reset persistent state for this model so stale effect caches don't linger
    if (_liveCoordinator) {
        _liveCoordinator->resetPersistentState(modelName);
    }
}

void RenderEngine::invalidateAllCaches()
{
    // Close FSEQ so the FSEQ playback path is no longer used.
    // Must be called before taking _bufferCacheMutex (closeFSEQ locks it too).
    closeFSEQ();

    std::lock_guard<std::mutex> lock(_bufferCacheMutex);
    _bufferCache.clear();
    _currentFrameIndex = -1;
    // Discard pre-rendered data so the live effect path is used until
    // the user clicks Render All again.
    _renderedData.reset();
    // Destroy the live coordinator so it's recreated fresh
    _liveCoordinator.reset();
    _liveContext.reset();
    _lastLiveRenderTimeMS = -1;
}

bool RenderEngine::getGPUAvailable() const { return false; }
bool RenderEngine::getGPUEnabled() const { return false; }
void RenderEngine::setGPUEnabled(bool enabled) {}
void RenderEngine::setRenderMode(RenderMode mode) { _renderMode.store(mode); }
RenderMode RenderEngine::getRenderMode() const { return _renderMode.load(); }
bool RenderEngine::isRendering() const {
    return _coordinator && _coordinator->isRendering();
}

RenderStatus RenderEngine::getRenderStatus() const {
    RenderStatus status;
    status.isRendering = isRendering();
    if (_fseqLoaded && _fseqFile) {
        status.framesTotal = static_cast<int>(_fseqFile->getNumFrames());
    } else {
        status.framesTotal = getNumFrames();
    }
    if (status.isRendering && _coordinator) {
        status.progressPercent = _coordinator->getProgress() * 100.0f;
    }
    return status;
}

int RenderEngine::getFrameTimeMS() const
{
    if (_fseqLoaded && _fseqFile) {
        return _fseqFile->getStepTime();
    }
    if (_provider) {
        int ft = _provider->getFrameTimeMS();
        if (ft > 0) return ft;
    }
    return 50;
}

int RenderEngine::getNumFrames() const
{
    if (_fseqLoaded && _fseqFile) {
        return static_cast<int>(_fseqFile->getNumFrames());
    }
    if (_provider) {
        int n = _provider->getTotalFrames();
        if (n > 0) return n;
    }
    // Estimate from effect provider's sequence duration
    if (_provider) {
        int durationMS = _provider->getSequenceDurationMS();
        int frameTimeMS = getFrameTimeMS();
        if (durationMS > 0 && frameTimeMS > 0) {
            return durationMS / frameTimeMS;
        }
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
