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
#include "render/BackgroundRenderQueue.h"
#include "render/DiskRenderCache.h"
#include "render/IRenderContext.h"
#include "interfaces/IEffectProvider.h"
#include <dispatch/dispatch.h>
#endif

#include <algorithm>
#include <cstring>
#include <chrono>
#include <set>
#include <sstream>
#include <unordered_map>

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
    // Cancel background rendering before tearing down coordinators
    _bgRenderQueue.reset();
    _bgCoordinator.reset();
    _bgContext.reset();

    disconnectEffectEngine();
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

void RenderEngine::setAudioProvider(IAudioProvider* provider)
{
    _audioProvider = provider;
}

// Lightweight IRenderContext adapter for the coordinator
namespace {
class RenderEngineContext : public IRenderContext {
public:
    RenderEngineContext(int frameTimeMS, double sequenceDuration,
                        IAudioProvider* audioProvider = nullptr)
        : _frameTimeMS(frameTimeMS), _duration(sequenceDuration),
          _audioProvider(audioProvider) {}

    void* getAudioManager() override { return nullptr; }
    IAudioProvider* getAudioProvider() override { return _audioProvider; }
    double getSequenceDuration() override { return _duration; }
    int getFrameTimeMS() override { return _frameTimeMS; }

private:
    int _frameTimeMS;
    double _duration;
    IAudioProvider* _audioProvider;
};
} // anonymous namespace

// --- FSEQ Loading ---

bool RenderEngine::loadFSEQ(const std::string& fseqPath)
{
    closeFSEQ();
    _fseqPath = fseqPath;

    auto newFile = std::shared_ptr<FSEQFile>(FSEQFile::openFSEQFile(fseqPath));
    if (!newFile) {
        return false;
    }

    // Prepare for reading all channels
    newFile->prepareRead({});

    {
        std::lock_guard<std::mutex> lock(_fseqMutex);
        _fseqFile = std::move(newFile);
    }

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
    _fseqLoaded = false; // set BEFORE destroying — readers check this first
    {
        std::lock_guard<std::mutex> lock(_fseqMutex);
        _fseqFile.reset();
    }
    _currentFrameIndex = -1;
    _currentFrameData.clear();
    _controllerStartChannels.clear();

    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        _modelChannelMap.clear();
        _bufferCache.clear();
    }
    {
        std::lock_guard<std::mutex> lock(_sidebarCacheMutex);
        _sidebarCache.clear();
    }
}

bool RenderEngine::isFSEQLoaded() const
{
    return _fseqLoaded;
}

// --- Controller Channel Map ---

void RenderEngine::buildControllerChannelMap()
{
    _controllerStartChannels.clear();
    if (!_outputProvider) {
        printf("[CHANNEL_MAP] buildControllerChannelMap: NO outputProvider — all controller/IP-based start channels will resolve to 0!\n");
        return;
    }

    size_t count = _outputProvider->getControllerCount();
    printf("[CHANNEL_MAP] buildControllerChannelMap: %zu controllers from outputProvider\n", count);
    for (size_t i = 0; i < count; i++) {
        auto info = _outputProvider->getController(i);
        if (!info.has_value()) continue;

        printf("[CHANNEL_MAP]   Controller[%zu] name='%s' ip='%s' startCh=%d channels=%d protocol='%s' outputCount=%d startUniverse=%d\n",
               i, info->name.c_str(), info->ip.c_str(), info->startChannel, info->channels,
               info->protocol.c_str(), info->outputCount, info->startUniverse);

        // Register by controller name (for !ControllerName:offset format)
        if (!info->name.empty() && info->startChannel > 0) {
            _controllerStartChannels[info->name] = info->startChannel;
        }

        // Register per-universe lookup entries for #IP:universe:channel format.
        // For E131/ArtNet: register "{protocol}_{ip}_{universe}" for each universe.
        // For DDP: register "DDP_{ip}".
        if (!info->ip.empty() && info->startChannel > 0 && info->outputCount > 0) {
            std::string proto = info->protocol;
            if (proto == "E1.31") proto = "E131"; // normalize

            if (proto == "DDP") {
                std::string key = "DDP_" + info->ip;
                _controllerStartChannels[key] = info->startChannel;
            } else if (proto == "E131" || proto == "ArtNet") {
                int channelsPerUniverse = info->channels / info->outputCount;
                if (channelsPerUniverse <= 0) channelsPerUniverse = 510; // E131 default

                for (int u = 0; u < info->outputCount; u++) {
                    int universeNum = info->startUniverse + u;
                    int32_t univStartCh = info->startChannel + (u * channelsPerUniverse);
                    std::string key = proto + "_" + info->ip + "_" + std::to_string(universeNum);
                    _controllerStartChannels[key] = univStartCh;
                }
            }
        }
    }
    printf("[CHANNEL_MAP] buildControllerChannelMap: %zu total lookup entries\n",
           _controllerStartChannels.size());
    for (const auto& [key, startCh] : _controllerStartChannels) {
        printf("[CHANNEL_MAP]   lookup '%s' → startCh=%d\n", key.c_str(), startCh);
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
    // Format 2: Universe/IP reference
    // 3-part: "#192.168.1.11:1:1" = #IP:universe:channel
    // 2-part: "#1:1" = #universe:channel (search all controllers)
    else if (sc[0] == '#' && sc.size() > 1) {
        size_t firstColon = sc.find(':', 1);
        if (firstColon != std::string::npos) {
            std::string firstPart = sc.substr(1, firstColon - 1);
            size_t secondColon = sc.find(':', firstColon + 1);

            if (secondColon != std::string::npos) {
                // 3-part: #IP:universe:channel
                std::string ip = firstPart;
                int universe = 1, channel = 1;
                try { universe = std::stoi(sc.substr(firstColon + 1, secondColon - firstColon - 1)); } catch (...) {}
                try { channel = std::stoi(sc.substr(secondColon + 1)); } catch (...) {}

                // Look up by IP and universe: "E131_IP_universe" or "DDP_IP"
                bool found = false;
                for (const char* proto : {"E131", "ArtNet", "DDP"}) {
                    std::string key = std::string(proto) + "_" + ip;
                    if (std::string(proto) != "DDP") {
                        key += "_" + std::to_string(universe);
                    }
                    auto it = _controllerStartChannels.find(key);
                    if (it != _controllerStartChannels.end()) {
                        result = static_cast<uint32_t>(it->second - 1) + static_cast<uint32_t>(channel - 1);
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    printf("RenderEngine: WARNING — cannot resolve '%s' (no controller at IP %s universe %d)\n",
                           sc.c_str(), ip.c_str(), universe);
                }
            } else {
                // 2-part: #universe:channel (search all controllers for matching universe)
                int universe = 1, channel = 1;
                try { universe = std::stoi(firstPart); } catch (...) {}
                try { channel = std::stoi(sc.substr(firstColon + 1)); } catch (...) {}

                bool found = false;
                for (const char* proto : {"E131", "ArtNet"}) {
                    std::string suffix = "_" + std::to_string(universe);
                    for (const auto& [key, startCh] : _controllerStartChannels) {
                        if (key.size() > suffix.size() &&
                            key.compare(0, strlen(proto), proto) == 0 &&
                            key.compare(key.size() - suffix.size(), suffix.size(), suffix) == 0) {
                            result = static_cast<uint32_t>(startCh - 1) + static_cast<uint32_t>(channel - 1);
                            found = true;
                            break;
                        }
                    }
                    if (found) break;
                }
                if (!found) {
                    printf("RenderEngine: WARNING — cannot resolve '%s' (no controller with universe %d)\n",
                           sc.c_str(), universe);
                }
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
    printf("[CHANNEL_MAP] resolveStartChannel('%s') → %u (0-based)\n", sc.c_str(), result);
    return result;
}

int32_t RenderEngine::computeRequiredChannels()
{
    if (!_modelProvider) return 0;

    int32_t maxEndChannel = 0;
    auto modelNames = _modelProvider->getModelNames();
    ModelEngine tempEngine(_modelProvider);

    for (const auto& name : modelNames) {
        auto attrs = _modelProvider->getModelAttributes(name);
        auto displayAs = attrs.find("DisplayAs");
        if (displayAs != attrs.end() && displayAs->second == "ModelGroup") continue;
        auto scIt = attrs.find("StartChannel");
        if (scIt == attrs.end() || scIt->second.empty()) continue;

        uint32_t startCh = resolveStartChannel(scIt->second);
        auto nodes = tempEngine.getModelNodes(name);
        if (nodes.empty()) continue;

        uint32_t chansPerNode = 3;
        auto stIt = attrs.find("StringType");
        if (stIt != attrs.end()) {
            const auto& st = stIt->second;
            if (st.find("4 Channel") != std::string::npos ||
                st.find("RGBW") != std::string::npos) chansPerNode = 4;
            else if (st.find("Single Color") != std::string::npos) chansPerNode = 1;
        }
        uint32_t endCh = startCh + static_cast<uint32_t>(nodes.size()) * chansPerNode;
        if (static_cast<int32_t>(endCh) > maxEndChannel) {
            maxEndChannel = static_cast<int32_t>(endCh);
        }
    }
    return maxEndChannel;
}

// --- Model Channel Map ---

void RenderEngine::buildModelChannelMap()
{
    // Lock to prevent data race with renderFrame() iterating on background thread
    std::lock_guard<std::mutex> lock(_bufferCacheMutex);
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

    // Second pass: for submodel refs like "Singing Tree/Outline", ensure the parent
    // model "Singing Tree" is in the map. The batch render writes channel data for parent
    // models, but getModelNames() may only return submodel refs.
    printf("[CHANNEL_MAP] Second pass: checking %zu model names for submodel refs\n", modelNames.size());
    int subRefCount = 0;
    std::set<std::string> parentsSeen;
    for (const auto& name : modelNames) {
        size_t slash = name.find('/');
        if (slash == std::string::npos) continue;
        subRefCount++;
        std::string parentName = name.substr(0, slash);
        if (_modelChannelMap.count(parentName)) {
            printf("[CHANNEL_MAP]   subref '%s' → parent '%s' ALREADY in map\n", name.c_str(), parentName.c_str());
            continue;
        }
        if (!parentsSeen.insert(parentName).second) continue; // already tried

        printf("[CHANNEL_MAP]   subref '%s' → trying to add parent '%s'\n", name.c_str(), parentName.c_str());
        auto parentAttrs = _modelProvider->getModelAttributes(parentName);
        if (parentAttrs.empty()) {
            printf("[CHANNEL_MAP]   Parent '%s' — empty attributes, skipping\n", parentName.c_str());
            continue;
        }
        auto displayAs = parentAttrs.find("DisplayAs");
        if (displayAs != parentAttrs.end() && displayAs->second == "ModelGroup") continue;

        auto scIt = parentAttrs.find("StartChannel");
        if (scIt == parentAttrs.end() || scIt->second.empty()) continue;

        uint32_t absStart = resolveStartChannel(scIt->second);
        auto parentNodes = tempEngine.getModelNodes(parentName);
        if (parentNodes.empty()) continue;

        uint32_t chansPerNode = 3;
        uint8_t rOff = 0, gOff = 1, bOff = 2;
        auto stIt = parentAttrs.find("StringType");
        if (stIt != parentAttrs.end()) {
            const std::string& st = stIt->second;
            if (st.find("4 Channel") != std::string::npos ||
                st.find("RGBW") != std::string::npos) {
                chansPerNode = 4;
            } else if (st.find("Single Color") != std::string::npos) {
                chansPerNode = 1;
            }
            if (chansPerNode >= 3 && st.size() >= 3) {
                std::string colorChars;
                int baseOffset = 0;
                if (st[0] == 'W' && st.size() >= 4 && st[1] >= 'A' && st[1] <= 'Z') {
                    colorChars = st.substr(1, 3); baseOffset = 1;
                } else if (st.compare(0, 10, "4 Channel ") == 0 && st.size() >= 14) {
                    std::string suffix = st.substr(10);
                    if (suffix[0] == 'W') { colorChars = suffix.substr(1, 3); baseOffset = 1; }
                    else { colorChars = suffix.substr(0, 3); baseOffset = 0; }
                } else if (st[0] >= 'A' && st[0] <= 'Z') {
                    colorChars = st.substr(0, 3); baseOffset = 0;
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

        int maxBufX = 0, maxBufY = 0;
        for (const auto& node : parentNodes) {
            if (node.bufX > maxBufX) maxBufX = node.bufX;
            if (node.bufY > maxBufY) maxBufY = node.bufY;
        }

        ModelChannelInfo info;
        info.absStartChannel = absStart;
        info.nodeCount = static_cast<uint32_t>(parentNodes.size());
        info.chansPerNode = chansPerNode;
        info.bufferWidth = maxBufX + 1;
        info.bufferHeight = maxBufY + 1;
        info.rOffset = rOff;
        info.gOffset = gOff;
        info.bOffset = bOff;
        info.nodeBufCoords.reserve(parentNodes.size());
        for (const auto& node : parentNodes) {
            info.nodeBufCoords.push_back({node.bufX, node.bufY});
        }

        printf("[CHANNEL_MAP] Added parent '%s' from subref '%s': startCh=%u nodes=%u buffer=%dx%d\n",
               parentName.c_str(), name.c_str(), absStart, info.nodeCount,
               info.bufferWidth, info.bufferHeight);
        _modelChannelMap[parentName] = std::move(info);
    }

    printf("[CHANNEL_MAP] buildModelChannelMap: mapped %zu models out of %zu total (%zu skipped)\n",
           _modelChannelMap.size(), modelNames.size(), skippedCount);
    for (const auto& [name, chInfo] : _modelChannelMap) {
        printf("[CHANNEL_MAP]   model='%s' absStartCh=%u nodes=%u buffer=%dx%d chansPerNode=%u rgbOff=[%d,%d,%d]\n",
               name.c_str(), chInfo.absStartChannel, chInfo.nodeCount,
               chInfo.bufferWidth, chInfo.bufferHeight, chInfo.chansPerNode,
               chInfo.rOffset, chInfo.gOffset, chInfo.bOffset);
    }
}

// --- Frame Rendering ---

void RenderEngine::renderFrame(int timeMS)
{
    // Skip frame rendering while a batch render (renderAll/forceRenderAll) is
    // in progress on a background thread. Those methods modify _renderedData,
    // _fseqFile, _modelChannelMap, etc. without fine-grained locking. The
    // preview will briefly freeze during rendering, then resume with correct data.
    if (_renderInProgress.load(std::memory_order_acquire)) return;

    // Log path changes and periodic state.
    // Counters reset on path changes AND on render generation bumps (after renderAll).
    static bool sRdbgResetCounters = false;
    {
        static int sLastPath = 0; // 0=none, 1=fseq, 2=prerendered, 3=live
        static int sFrameCount = 0;
        static uint32_t sLastGen = 0;
        int path = 0;
        if (_fseqLoaded.load(std::memory_order_relaxed)) {
            std::lock_guard<std::mutex> fLock(_fseqMutex);
            if (_fseqFile) path = 1;
        }
        if (path == 0 && _renderedData && _renderedData->isValid() && !_modelChannelMap.empty()) path = 2;
        if (path == 0 && _effectProvider && _modelProvider) path = 3;

        // Reset counters on path change OR render generation change
        uint32_t curGen = _renderGeneration.load(std::memory_order_relaxed);
        if (path != sLastPath || curGen != sLastGen) {
            const char* names[] = {"NONE", "FSEQ", "PRERENDERED", "LIVE"};
            if (path != sLastPath) {
                printf("[RDBG] renderFrame(%dms): PATH CHANGE %s → %s (fseq=%d rendData=%d map=%zu gen=%u)\n",
                       timeMS, names[sLastPath], names[path],
                       _fseqLoaded.load(std::memory_order_relaxed), (_renderedData != nullptr),
                       _modelChannelMap.size(), curGen);
            } else {
                printf("[RDBG] renderFrame(%dms): RENDER GEN %u → %u on %s path (map=%zu)\n",
                       timeMS, sLastGen, curGen, names[path], _modelChannelMap.size());
            }
            sLastPath = path;
            sLastGen = curGen;
            sFrameCount = 0;
            sRdbgResetCounters = true;
        }
        sFrameCount++;
        // Log first 20 frames after each reset and then every 200th
        if (sFrameCount <= 20 || sFrameCount % 200 == 0) {
            if (path == 2 && _renderedData) {
                int st = static_cast<int>(_renderedData->getFrameTimeMS());
                if (st <= 0) st = 25;
                int fi = timeMS / st;
                uint32_t nz = 0;
                const uint8_t* fd = _renderedData->getFrame(static_cast<uint32_t>(fi));
                if (fd) {
                    uint32_t nc = _renderedData->getNumChannels();
                    for (uint32_t i = 0; i < nc && i < 1000; ++i) {
                        if (fd[i] != 0) nz++;
                    }
                }
                printf("[RDBG] renderFrame(%dms): path=2 gen=%u call#%d frameIdx=%d/%u nonZero(first1k)=%u\n",
                       timeMS, curGen, sFrameCount, fi, _renderedData->getNumFrames(), nz);
            } else {
                printf("[RDBG] renderFrame(%dms): path=%d gen=%u call#%d\n", timeMS, path, curGen, sFrameCount);
            }
        }
    }

    // Grab a local shared_ptr to the FSEQ file — keeps the object alive
    // even if forceRenderAll resets _fseqFile on another thread.
    std::shared_ptr<FSEQFile> localFseq;
    if (_fseqLoaded.load(std::memory_order_acquire)) {
        std::lock_guard<std::mutex> lock(_fseqMutex);
        localFseq = _fseqFile;
    }

    if (localFseq) {
        // FSEQ playback path: read pre-rendered channel data
        int stepTime = localFseq->getStepTime();
        if (stepTime <= 0) stepTime = 50;

        int frameIndex = timeMS / stepTime;
        if (frameIndex < 0) frameIndex = 0;
        int numFrames = static_cast<int>(localFseq->getNumFrames());
        if (numFrames > 0 && frameIndex >= numFrames) {
            frameIndex = numFrames - 1;
        }

        // Skip if we already have this frame cached
        if (frameIndex == _currentFrameIndex) return;

        // Log first FSEQ frame read (reset on path change)
        static bool firstFseqFrame = true;
        if (sRdbgResetCounters) { firstFseqFrame = true; }
        if (firstFseqFrame) {
            uint32_t maxCh = static_cast<uint32_t>(localFseq->getChannelCount());
            printf("[RDBG] renderFrame(FSEQ): first frame at %dms, frameIndex=%d, numFrames=%d, channels=%u, models=%zu\n",
                   timeMS, frameIndex, numFrames, maxCh, _modelChannelMap.size());
            firstFseqFrame = false;
        }

        // Read frame data from FSEQ (no lock held — local shared_ptr keeps object alive)
        FSEQFile::FrameData* fd = localFseq->getFrame(static_cast<uint32_t>(frameIndex));
        if (!fd) return;

        uint32_t maxCh = static_cast<uint32_t>(localFseq->getChannelCount());
        _currentFrameData.resize(maxCh, 0);
        fd->readFrame(_currentFrameData.data(), maxCh);
        delete fd;
        _currentFrameIndex = frameIndex;

        // Overlay: patch dirty models' channel data from _renderedData.
        // When an effect is edited, the background render queue re-renders
        // only the affected model into _renderedData. Once complete, we copy
        // that model's channel range over the stale FSEQ data so the user
        // sees the updated effect without re-rendering the entire sequence.
        if (_renderedData && _renderedData->isValid() && _bgRenderQueue) {
            auto completed = _bgRenderQueue->getCompletedModels();
            if (!completed.empty()) {
                const uint8_t* overlayFrame = _renderedData->getFrame(
                    static_cast<uint32_t>(frameIndex));
                if (overlayFrame) {
                    std::lock_guard<std::mutex> dLock(_dirtyMutex);
                    for (const auto& mName : completed) {
                        auto rangeIt = _modelChannelRanges.find(mName);
                        if (rangeIt == _modelChannelRanges.end()) continue;
                        uint32_t startCh = rangeIt->second.first;
                        uint32_t chCount = rangeIt->second.second;
                        if (startCh + chCount <= maxCh) {
                            std::memcpy(_currentFrameData.data() + startCh,
                                        overlayFrame + startCh, chCount);
                        }
                    }
                    // Log first overlay application
                    static int overlayLogCount = 0;
                    if (overlayLogCount < 5) {
                        printf("[RDBG] renderFrame(FSEQ): overlaid %zu model(s) from _renderedData at frame %d\n",
                               completed.size(), frameIndex);
                        overlayLogCount++;
                    }
                }
            }
        }

        // Build FrameBuffers for all mapped models
        int modelsWithPixels = 0;
        {
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

                int nonBlackPixels = 0;
                for (uint32_t i = 0; i < chInfo.nodeCount; i++) {
                    uint32_t nodeChannel = chInfo.absStartChannel + (i * chInfo.chansPerNode);
                    if (nodeChannel + chInfo.chansPerNode > static_cast<uint32_t>(_currentFrameData.size())) continue;

                    uint8_t r = _currentFrameData[nodeChannel + chInfo.rOffset];
                    uint8_t g = _currentFrameData[nodeChannel + chInfo.gOffset];
                    uint8_t b = _currentFrameData[nodeChannel + chInfo.bOffset];

                    if (r > 0 || g > 0 || b > 0) nonBlackPixels++;

                    int bx = chInfo.nodeBufCoords[i].first;
                    int by = chInfo.nodeBufCoords[i].second;
                    if (bx < 0 || bx >= fb.width || by < 0 || by >= fb.height) continue;

                    size_t idx = (static_cast<size_t>(by) * fb.width + bx) * 4;
                    fb.pixels[idx]     = r;
                    fb.pixels[idx + 1] = g;
                    fb.pixels[idx + 2] = b;
                    fb.pixels[idx + 3] = 255;
                }

                if (nonBlackPixels > 0) modelsWithPixels++;
                _bufferCache[modelName] = std::move(fb);
            }

            // Synthesize submodel FrameBuffers for any submodel refs in getModelNames()
            // that aren't directly in _modelChannelMap but whose parent model IS.
            if (_modelProvider) {
                auto allNames = _modelProvider->getModelNames();
                for (const auto& name : allNames) {
                    size_t slash = name.find('/');
                    if (slash == std::string::npos) continue;
                    if (_bufferCache.count(name)) continue;
                    std::string parentName = name.substr(0, slash);
                    auto parentIt = _modelChannelMap.find(parentName);
                    if (parentIt == _modelChannelMap.end()) continue;
                    synthesizeSubmodelFrameBuffer(name, parentIt->second, timeMS);
                }
            }
        } // release _bufferCacheMutex before logging and notifying

        // Log stats on first few FSEQ frames (reset on path change)
        static int fseqFrameLogCount = 0;
        if (sRdbgResetCounters) { fseqFrameLogCount = 0; sRdbgResetCounters = false; }
        if (fseqFrameLogCount < 3) {
            printf("[RDBG] renderFrame(FSEQ): t=%dms frame %d — %d/%zu models have non-black pixels, dataSz=%zu\n",
                   timeMS, frameIndex, modelsWithPixels, _modelChannelMap.size(), _currentFrameData.size());

            // Detailed: which models have non-zero pixels?
            int litCount = 0;
            for (const auto& [mn, ci] : _modelChannelMap) {
                int nzNodes = 0;
                for (uint32_t n = 0; n < ci.nodeCount && n < 50; n++) {
                    uint32_t ch = ci.absStartChannel + n * ci.chansPerNode;
                    if (ch + ci.chansPerNode > static_cast<uint32_t>(_currentFrameData.size())) break;
                    if (_currentFrameData[ch] != 0 || _currentFrameData[ch+1] != 0 || _currentFrameData[ch+2] != 0)
                        nzNodes++;
                }
                if (nzNodes > 0) {
                    if (litCount < 10)
                        printf("[RDBG]   FSEQ LIT model '%s' startCh=%u nodes=%u nzNodes=%d\n",
                               mn.c_str(), ci.absStartChannel, ci.nodeCount, nzNodes);
                    litCount++;
                }
            }
            printf("[RDBG]   FSEQ total lit models: %d/%zu at t=%dms\n", litCount, _modelChannelMap.size(), timeMS);
            fseqFrameLogCount++;
        }

        notifyFrameRendered(timeMS);
    } else if (_renderedData && _renderedData->isValid() && !_modelChannelMap.empty()) {
        // Pre-rendered data path: read from in-memory rendered data (from renderAll).
        // Dirty models have their channels zeroed in invalidateModel() so they show
        // black until re-rendered (via background queue or next Render All).
        int stepTime = static_cast<int>(_renderedData->getFrameTimeMS());
        if (stepTime <= 0) stepTime = 50;

        // One-time diagnostic: log pre-rendered data dimensions + sample frames
        static bool prerenderedDiagLogged = false;
        if (sRdbgResetCounters) prerenderedDiagLogged = false;
        if (!prerenderedDiagLogged) {
            uint32_t nFrames = _renderedData->getNumFrames();
            uint32_t nc = _renderedData->getNumChannels();
            printf("[RDBG] PRERENDERED DATA: stepTime=%d numFrames=%u numChannels=%u totalBytes=%zu mapModels=%zu\n",
                   stepTime, nFrames, nc, _renderedData->getTotalBytes(), _modelChannelMap.size());

            // Scan for first and last non-zero frames, and sample frames across sequence
            uint32_t firstNZ = UINT32_MAX, lastNZ = 0;
            int nzFrameCount = 0;
            // Sample: scan every 100th frame plus the first 600
            for (uint32_t fi = 0; fi < nFrames; fi++) {
                if (fi >= 600 && fi % 100 != 0) continue; // scan first 600 + every 100th
                const uint8_t* fd = _renderedData->getFrame(fi);
                if (!fd) continue;
                uint32_t nz = 0;
                for (uint32_t c = 0; c < nc; c++) {
                    if (fd[c] != 0) { nz++; if (nz > 10) break; } // just detect presence
                }
                if (nz > 0) {
                    nzFrameCount++;
                    if (fi < firstNZ) firstNZ = fi;
                    if (fi > lastNZ) lastNZ = fi;
                }
            }
            printf("[RDBG] PRERENDERED DATA: firstNZ frame=%u (%ums), lastNZ frame=%u (%ums), nzFrames(sampled)=%d\n",
                   firstNZ, firstNZ * stepTime, lastNZ, lastNZ * stepTime, nzFrameCount);
            // Show a few sample frames: 0, 25%, 50%, 75%, 100%
            uint32_t sampleFrames[] = {0, nFrames/4, nFrames/2, nFrames*3/4, nFrames > 0 ? nFrames-1 : 0};
            for (int s = 0; s < 5; s++) {
                uint32_t sf = sampleFrames[s];
                if (sf >= nFrames) continue;
                const uint8_t* fd = _renderedData->getFrame(sf);
                uint32_t nz = 0;
                if (fd) { for (uint32_t c = 0; c < nc; c++) { if (fd[c] != 0) nz++; } }
                printf("[RDBG] PRERENDERED SAMPLE: frame[%u] t=%ums nonZero=%u/%u\n",
                       sf, sf * stepTime, nz, nc);
            }
            prerenderedDiagLogged = true;
        }

        int frameIndex = timeMS / stepTime;
        if (frameIndex < 0) frameIndex = 0;
        int numFrames = static_cast<int>(_renderedData->getNumFrames());
        if (numFrames > 0 && frameIndex >= numFrames) {
            frameIndex = numFrames - 1;
        }

        // Skip if we already have this frame cached
        if (frameIndex == _currentFrameIndex) {
            // Log early returns to detect stale-cache issues
            static int earlyReturnCount = 0;
            static int earlyReturnLogCount = 0;
            if (sRdbgResetCounters) { earlyReturnCount = 0; earlyReturnLogCount = 0; }
            earlyReturnCount++;
            if (earlyReturnLogCount < 5) {
                printf("[RDBG] PRERENDERED early-return: t=%dms frameIdx=%d (same as cached, earlyReturns=%d)\n",
                       timeMS, frameIndex, earlyReturnCount);
                earlyReturnLogCount++;
            }
            return;
        }

        // Read frame data from pre-rendered buffer
        const uint8_t* frameData = _renderedData->getFrame(static_cast<uint32_t>(frameIndex));
        if (!frameData) return;

        uint32_t numChannels = _renderedData->getNumChannels();
        _currentFrameData.resize(numChannels, 0);
        std::memcpy(_currentFrameData.data(), frameData, numChannels);
        _currentFrameIndex = frameIndex;

        // PRERENDERED frame diagnostics — comprehensive logging:
        // First 20 frames: always log. After that: log any frame with nonZero > 0
        // (rate-limited to every 40th such frame to avoid flood).
        static int prerenderedLogCount = 0;
        static int prerenderedNZLogCount = 0;
        static int prerenderedTotalFrames = 0;
        static int prerenderedNZFrames = 0;
        if (sRdbgResetCounters) {
            prerenderedLogCount = 0;
            prerenderedNZLogCount = 0;
            prerenderedTotalFrames = 0;
            prerenderedNZFrames = 0;
        }
        prerenderedTotalFrames++;
        {
            // Quick check: does this frame have any non-zero data?
            uint32_t nonZero = 0;
            for (uint32_t i = 0; i < numChannels; ++i) {
                if (_currentFrameData[i] != 0) { nonZero++; if (nonZero > 100) break; }
            }
            bool hasData = (nonZero > 0);
            if (hasData) prerenderedNZFrames++;

            // Log first 20 frames always, then every 40th non-zero frame
            bool shouldLog = (prerenderedLogCount < 20) ||
                             (hasData && (prerenderedNZLogCount % 40 == 0));
            if (hasData) prerenderedNZLogCount++;

            if (shouldLog) {
                // Full nonZero count for logged frames
                if (nonZero <= 100) {
                    nonZero = 0;
                    for (uint32_t i = 0; i < numChannels; ++i) {
                        if (_currentFrameData[i] != 0) nonZero++;
                    }
                }
                printf("[RDBG] renderFrame(PRERENDERED): t=%dms frameIdx=%d/%d stepTime=%d nonZero=%u/%u (frame#%d, nzFrames=%d)\n",
                       timeMS, frameIndex, numFrames, stepTime, nonZero, numChannels,
                       prerenderedTotalFrames, prerenderedNZFrames);
                prerenderedLogCount++;
            }

            // Every 200th frame, log a status summary regardless
            if (prerenderedTotalFrames % 200 == 0) {
                printf("[RDBG] PRERENDERED STATUS: frame#%d t=%dms frameIdx=%d nzFrames=%d/%d (%.1f%%)\n",
                       prerenderedTotalFrames, timeMS, frameIndex,
                       prerenderedNZFrames, prerenderedTotalFrames,
                       prerenderedTotalFrames > 0 ? 100.0 * prerenderedNZFrames / prerenderedTotalFrames : 0.0);
            }
        }

        // Build FrameBuffers for all mapped models (same logic as FSEQ path)
        int modelsWithPixels = 0;
        {
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

                int nonBlackPixels = 0;
                for (uint32_t i = 0; i < chInfo.nodeCount; i++) {
                    uint32_t nodeChannel = chInfo.absStartChannel + (i * chInfo.chansPerNode);
                    if (nodeChannel + chInfo.chansPerNode > static_cast<uint32_t>(_currentFrameData.size())) continue;

                    uint8_t r = _currentFrameData[nodeChannel + chInfo.rOffset];
                    uint8_t g = _currentFrameData[nodeChannel + chInfo.gOffset];
                    uint8_t b = _currentFrameData[nodeChannel + chInfo.bOffset];

                    if (r > 0 || g > 0 || b > 0) nonBlackPixels++;

                    int bx = chInfo.nodeBufCoords[i].first;
                    int by = chInfo.nodeBufCoords[i].second;
                    if (bx < 0 || bx >= fb.width || by < 0 || by >= fb.height) continue;

                    size_t idx = (static_cast<size_t>(by) * fb.width + bx) * 4;
                    fb.pixels[idx]     = r;
                    fb.pixels[idx + 1] = g;
                    fb.pixels[idx + 2] = b;
                    fb.pixels[idx + 3] = 255;
                }

                if (nonBlackPixels > 0) modelsWithPixels++;

                // Pixel-level diagnostic: log actual RGB values for first lit model
                static int pixelDiagCount = 0;
                if (sRdbgResetCounters) pixelDiagCount = 0;
                if (nonBlackPixels > 0 && pixelDiagCount < 2) {
                    printf("[RDBG-PIX] PRERENDERED model '%s' t=%dms: startCh=%u nodes=%u chPerNode=%u rgbOff=[%d,%d,%d] nonBlack=%d buf=%dx%d\n",
                           modelName.c_str(), timeMS, chInfo.absStartChannel, chInfo.nodeCount,
                           chInfo.chansPerNode, chInfo.rOffset, chInfo.gOffset, chInfo.bOffset,
                           nonBlackPixels, fb.width, fb.height);
                    // Dump first 5 non-black pixel values from the FrameBuffer
                    int shown = 0;
                    for (uint32_t ni = 0; ni < chInfo.nodeCount && shown < 5; ni++) {
                        int bx = chInfo.nodeBufCoords[ni].first;
                        int by = chInfo.nodeBufCoords[ni].second;
                        if (bx < 0 || bx >= fb.width || by < 0 || by >= fb.height) continue;
                        size_t pi = (static_cast<size_t>(by) * fb.width + bx) * 4;
                        uint8_t pr = fb.pixels[pi], pg = fb.pixels[pi+1], pb = fb.pixels[pi+2];
                        if (pr == 0 && pg == 0 && pb == 0) continue;
                        // Also show raw channel bytes at this node's offset
                        uint32_t ch = chInfo.absStartChannel + ni * chInfo.chansPerNode;
                        printf("[RDBG-PIX]   node[%u] buf(%d,%d) fb=(%d,%d,%d) raw_ch[%u]=(%d,%d,%d)\n",
                               ni, bx, by, pr, pg, pb, ch,
                               (ch < numChannels) ? _currentFrameData[ch] : 0,
                               (ch+1 < numChannels) ? _currentFrameData[ch+1] : 0,
                               (ch+2 < numChannels) ? _currentFrameData[ch+2] : 0);
                        shown++;
                    }
                    pixelDiagCount++;
                }

                _bufferCache[modelName] = std::move(fb);
            }

            // Synthesize submodel FrameBuffers for submodel refs (same as FSEQ path)
            if (_modelProvider) {
                auto allNames = _modelProvider->getModelNames();
                for (const auto& name : allNames) {
                    size_t slash = name.find('/');
                    if (slash == std::string::npos) continue;
                    if (_bufferCache.count(name)) continue;
                    std::string parentName = name.substr(0, slash);
                    auto parentIt = _modelChannelMap.find(parentName);
                    if (parentIt == _modelChannelMap.end()) continue;
                    synthesizeSubmodelFrameBuffer(name, parentIt->second, timeMS);
                }
            }
        } // release _bufferCacheMutex before logging and notifying

        // Log stats on first few frames and after each render completion
        static int prerenderedFrameLogCount = 0;
        if (sRdbgResetCounters) { prerenderedFrameLogCount = 0; sRdbgResetCounters = false; }
        if (prerenderedFrameLogCount < 8) {
            printf("[RDBG] renderFrame(PRERENDERED): t=%dms frame %d — %d/%zu models have non-black pixels, bufferCache=%zu\n",
                   timeMS, frameIndex, modelsWithPixels, _modelChannelMap.size(), _bufferCache.size());
            prerenderedFrameLogCount++;
        }

        notifyFrameRendered(timeMS);
    } else if (_effectProvider && _modelProvider) {
        // Effect-based live rendering with persistent state.
        // The coordinator and its ModelJobs are kept alive across frames so
        // stateful effects (Fire, etc.) accumulate properly.
        //
        // Models are rendered in parallel using GCD dispatch_apply.
        // Each model has its own pixel buffer, so there is no contention
        // between models during rendering. The only shared state is the
        // render cache, which uses its own mutex.
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

        // Capture a shared_ptr to the coordinator so it stays alive even if
        // invalidateAllCaches() resets _liveCoordinator on another thread.
        std::shared_ptr<NativeRenderCoordinator> coordinator;
        {
            std::lock_guard<std::mutex> lock(_bufferCacheMutex);

            if (!_liveCoordinator) {
                _liveContext = std::make_shared<RenderEngineContext>(frameTimeMS, durationSec, _audioProvider);
                _liveCoordinator = std::make_shared<NativeRenderCoordinator>(
                    _effectProvider, _modelProvider, _liveContext.get());
                _lastLiveRenderTimeMS = -1;
            }

            if (_lastLiveRenderTimeMS >= 0 && timeMS < _lastLiveRenderTimeMS) {
                _liveCoordinator->resetPersistentState();
            }
            _lastLiveRenderTimeMS = timeMS;

            coordinator = _liveCoordinator;
        }
        // _bufferCacheMutex released — coordinator is kept alive by shared_ptr.

        // Log which rendering path we're on (once)
        static bool sLivePathLogged = false;
        if (!sLivePathLogged) {
            printf("[SUBDBG] renderFrame(%dms): LIVE EFFECT PATH (parallel), %zu models from provider\n",
                   timeMS, modelNames.size());
            sLivePathLogged = true;
        }

        // Render all models in parallel via the coordinator.
        auto allFrames = coordinator->renderAllModelsStateful(modelNames, timeMS);

        // Write results to _bufferCache under the lock.
        int modelsRendered = 0;
        {
            std::lock_guard<std::mutex> lock(_bufferCacheMutex);
            _bufferCache.clear();

            for (size_t i = 0; i < allFrames.size(); ++i) {
                auto& rf = allFrames[i];
                if (rf.isValid()) {
                    modelsRendered++;
                    FrameBuffer fb;
                    fb.modelName = rf.modelName;
                    fb.width = rf.width;
                    fb.height = rf.height;
                    fb.timeMS = rf.timeMS;
                    fb.pixels = std::move(rf.pixels);
                    _bufferCache[modelNames[i]] = std::move(fb);
                }
            }
        }

        auto frameEnd = std::chrono::steady_clock::now();
        auto frameUS = std::chrono::duration_cast<std::chrono::microseconds>(frameEnd - frameStart).count();
        printf("[LiveRender] Frame @%dms: %d/%zu models in %.1fms (budget=%dms)\n",
               timeMS, modelsRendered, modelNames.size(), frameUS / 1000.0, frameTimeMS);

        notifyFrameRendered(timeMS);
    }
}

void RenderEngine::renderModelFrame(const std::string& modelName, int timeMS)
{
    if (_renderInProgress.load(std::memory_order_acquire)) return;

    bool isSubRef = (modelName.find('/') != std::string::npos);

    bool haveFseq = false;
    if (_fseqLoaded.load(std::memory_order_acquire)) {
        std::lock_guard<std::mutex> lock(_fseqMutex);
        haveFseq = (_fseqFile != nullptr);
    }

    if (haveFseq || (_renderedData && _renderedData->isValid() && !_modelChannelMap.empty())) {
        // FSEQ / PRERENDERED path: build ONLY the requested model's FrameBuffer
        // into _sidebarCache. Do NOT call renderFrame() here — that would overwrite
        // _bufferCache (shared with the playback controller's render loop), causing
        // the playback display to show stale sidebar-time data instead of the
        // correct playback-time data.
        std::string physicalModel = isSubRef ? modelName.substr(0, modelName.find('/')) : modelName;
        auto chIt = _modelChannelMap.find(physicalModel);
        if (chIt == _modelChannelMap.end()) return;
        const auto& chInfo = chIt->second;
        if (chInfo.bufferWidth <= 0 || chInfo.bufferHeight <= 0) return;

        // Read frame data from the appropriate source
        int stepTime = 25;
        uint32_t numChannels = 0;
        std::vector<uint8_t> localFrameData;

        if (haveFseq) {
            std::shared_ptr<FSEQFile> localFseq;
            {
                std::lock_guard<std::mutex> fLock(_fseqMutex);
                localFseq = _fseqFile;
            }
            if (!localFseq) return;
            stepTime = localFseq->getStepTime();
            if (stepTime <= 0) stepTime = 50;
            int frameIndex = timeMS / stepTime;
            if (frameIndex < 0) frameIndex = 0;
            int nf = static_cast<int>(localFseq->getNumFrames());
            if (nf > 0 && frameIndex >= nf) frameIndex = nf - 1;
            numChannels = static_cast<uint32_t>(localFseq->getChannelCount());
            localFrameData.resize(numChannels, 0);
            FSEQFile::FrameData* fd = localFseq->getFrame(static_cast<uint32_t>(frameIndex));
            if (!fd) return;
            fd->readFrame(localFrameData.data(), numChannels);
            delete fd;
        } else {
            stepTime = static_cast<int>(_renderedData->getFrameTimeMS());
            if (stepTime <= 0) stepTime = 25;
            int frameIndex = timeMS / stepTime;
            if (frameIndex < 0) frameIndex = 0;
            int nf = static_cast<int>(_renderedData->getNumFrames());
            if (nf > 0 && frameIndex >= nf) frameIndex = nf - 1;
            const uint8_t* frameData = _renderedData->getFrame(static_cast<uint32_t>(frameIndex));
            if (!frameData) return;
            numChannels = _renderedData->getNumChannels();
            localFrameData.assign(frameData, frameData + numChannels);
        }

        // Build FrameBuffer for this model only
        FrameBuffer fb;
        fb.modelName = physicalModel;
        fb.width = chInfo.bufferWidth;
        fb.height = chInfo.bufferHeight;
        fb.timeMS = timeMS;
        fb.pixels.resize(static_cast<size_t>(fb.width) * fb.height * 4, 0);

        for (uint32_t i = 0; i < chInfo.nodeCount; i++) {
            uint32_t nodeChannel = chInfo.absStartChannel + (i * chInfo.chansPerNode);
            if (nodeChannel + chInfo.chansPerNode > numChannels) continue;

            uint8_t r = localFrameData[nodeChannel + chInfo.rOffset];
            uint8_t g = localFrameData[nodeChannel + chInfo.gOffset];
            uint8_t b = localFrameData[nodeChannel + chInfo.bOffset];

            int bx = chInfo.nodeBufCoords[i].first;
            int by = chInfo.nodeBufCoords[i].second;
            if (bx < 0 || bx >= fb.width || by < 0 || by >= fb.height) continue;

            size_t idx = (static_cast<size_t>(by) * fb.width + bx) * 4;
            fb.pixels[idx]     = r;
            fb.pixels[idx + 1] = g;
            fb.pixels[idx + 2] = b;
            fb.pixels[idx + 3] = 255;
        }

        {
            std::lock_guard<std::mutex> lock(_sidebarCacheMutex);
            _sidebarCache[physicalModel] = std::move(fb);
        }

        // For submodel refs, synthesize from the local frame data
        if (isSubRef) {
            synthesizeSubmodelBuffer(modelName, timeMS);
        }

        notifyModelFrameRendered(modelName, timeMS);
    } else if (_effectProvider && _modelProvider) {
        if (isSubRef) {
            static std::set<std::string> sLogged;
            if (sLogged.insert(modelName).second)
                printf("[GRP] renderModelFrame('%s'): PATH=live\n", modelName.c_str());
        }
        // Targeted single-model live rendering with persistent state.
        // Uses a SEPARATE coordinator from renderFrame() so the two paths
        // don't interfere with each other during concurrent playback.
        int frameTimeMS = _provider ? _provider->getFrameTimeMS() : 50;
        if (frameTimeMS <= 0) frameTimeMS = 50;

        int durationMS = _provider ? _provider->getSequenceDurationMS() : 0;
        if (durationMS <= 0) {
            int totalFrames = _provider ? _provider->getTotalFrames() : 0;
            durationMS = (totalFrames > 0) ? totalFrames * frameTimeMS : 60000;
        }
        double durationSec = durationMS / 1000.0;

        std::lock_guard<std::mutex> lock(_sidebarCacheMutex);

        // Create or reuse persistent sidebar coordinator.
        if (!_sidebarCoordinator) {
            _sidebarContext = std::make_unique<RenderEngineContext>(frameTimeMS, durationSec, _audioProvider);
            _sidebarCoordinator = std::make_unique<NativeRenderCoordinator>(
                _effectProvider, _modelProvider, _sidebarContext.get());
            _lastSidebarRenderTimeMS = -1;
        }

        if (_lastSidebarRenderTimeMS >= 0 && timeMS < _lastSidebarRenderTimeMS) {
            _sidebarCoordinator->resetPersistentState(modelName);
        }
        _lastSidebarRenderTimeMS = timeMS;

        RenderedFrame rf = _sidebarCoordinator->renderModelFrameStateful(modelName, timeMS);
        if (rf.isValid()) {
            FrameBuffer fb;
            fb.modelName = rf.modelName;
            fb.width = rf.width;
            fb.height = rf.height;
            fb.timeMS = rf.timeMS;
            fb.pixels = std::move(rf.pixels);
            _sidebarCache[modelName] = std::move(fb);

            notifyModelFrameRendered(modelName, timeMS);
        } else if (isSubRef) {
            static std::set<std::string> sLogged;
            if (sLogged.insert(modelName).second)
                printf("[GRP] renderModelFrame('%s'): INVALID result\n", modelName.c_str());
        }
    }
}

void RenderEngine::synthesizeSubmodelBuffer(const std::string& subRefName, int timeMS)
{
    // Copy _currentFrameData under lock to avoid race with renderFrame()
    // which runs on a different thread and modifies it.
    std::vector<uint8_t> localFrameData;
    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        if (_currentFrameData.empty()) return;
        localFrameData = _currentFrameData;
    }
    if (!_modelProvider) return;

    // Parse "Parent/Sub" into parent and submodel names
    size_t slash = subRefName.find('/');
    if (slash == std::string::npos) return;
    std::string parentName = subRefName.substr(0, slash);
    std::string subName = subRefName.substr(slash + 1);

    // Look up parent's channel info from _modelChannelMap
    auto parentIt = _modelChannelMap.find(parentName);
    if (parentIt == _modelChannelMap.end()) return;
    const ModelChannelInfo& parentChInfo = parentIt->second;

    // Get parent model's full node coordinates
    auto parentAttrs = _modelProvider->getModelAttributes(parentName);
    if (parentAttrs.empty()) return;

    auto allParentNodes = generateNodesFromAttributes(parentAttrs);
    if (allParentNodes.empty()) return;

    // Get submodel attributes and filter to submodel nodes
    auto subAttrs = _modelProvider->getSubmodelAttributes(parentName, subName);
    if (subAttrs.empty()) return;

    auto subNodes = filterNodesToSubmodel(allParentNodes, subAttrs);
    if (subNodes.empty()) return;

    // Determine submodel buffer dimensions from filtered node coordinates
    int maxBufX = 0, maxBufY = 0;
    for (const auto& nc : subNodes) {
        if (nc.bufX > maxBufX) maxBufX = nc.bufX;
        if (nc.bufY > maxBufY) maxBufY = nc.bufY;
    }
    int subBufW = maxBufX + 1;
    int subBufH = maxBufY + 1;

    // Build a FrameBuffer for the submodel
    FrameBuffer fb;
    fb.modelName = subRefName;
    fb.width = subBufW;
    fb.height = subBufH;
    fb.timeMS = timeMS;
    fb.pixels.resize(static_cast<size_t>(subBufW) * subBufH * 4, 0);

    // filterNodesToSubmodel preserves the original node ordering within the
    // parent model, but reassigns bufX/bufY for compact layout. We need to
    // map each submodel node back to its parent node index to read channel data.
    //
    // Strategy: filterNodesToSubmodel uses getSubmodelNodeIndices internally.
    // We replicate that to get the parent node indices.

    // Parse the submodel's strand ranges to get parent node indices (same as
    // getSubmodelNodeIndices in NativeRenderCoordinator.cpp)
    std::vector<int> parentNodeIndices;
    {
        auto typeIt = subAttrs.find("type");
        bool isSubBuffer = (typeIt != subAttrs.end() && typeIt->second == "subbuffer");

        if (isSubBuffer) {
            // Subbuffer type: all parent nodes map through
            for (int i = 0; i < static_cast<int>(allParentNodes.size()); i++) {
                parentNodeIndices.push_back(i);
            }
        } else {
            for (int lineIdx = 0; lineIdx < 100; ++lineIdx) {
                std::string key = "line" + std::to_string(lineIdx);
                auto it = subAttrs.find(key);
                if (it == subAttrs.end() || it->second.empty()) {
                    if (lineIdx > 0) break;
                    continue;
                }
                std::istringstream stream(it->second);
                std::string token;
                while (std::getline(stream, token, ',')) {
                    size_t start = token.find_first_not_of(" \t");
                    size_t end = token.find_last_not_of(" \t");
                    if (start == std::string::npos) continue;
                    token = token.substr(start, end - start + 1);
                    if (token.empty()) continue;

                    size_t dashPos = token.find('-');
                    int rangeStart, rangeEnd;
                    if (dashPos != std::string::npos) {
                        rangeStart = std::atoi(token.substr(0, dashPos).c_str()) - 1;
                        rangeEnd = std::atoi(token.substr(dashPos + 1).c_str()) - 1;
                        if (rangeStart < 0) rangeStart = 0;
                        if (rangeEnd < rangeStart) std::swap(rangeStart, rangeEnd);
                    } else {
                        rangeStart = rangeEnd = std::atoi(token.c_str()) - 1;
                        if (rangeStart < 0) continue;
                    }
                    for (int idx = rangeStart; idx <= rangeEnd; idx++) {
                        if (idx >= 0 && idx < static_cast<int>(allParentNodes.size())) {
                            parentNodeIndices.push_back(idx);
                        }
                    }
                }
            }
        }
    }

    // Map each submodel node to its pixel data from parent's channel data.
    // subNodes[i] corresponds to parentNodeIndices[i].
    size_t subNodeCount = std::min(subNodes.size(), parentNodeIndices.size());
    int nonBlackPixels = 0;
    for (size_t i = 0; i < subNodeCount; i++) {
        int parentIdx = parentNodeIndices[i];
        uint32_t nodeChannel = parentChInfo.absStartChannel +
                               (static_cast<uint32_t>(parentIdx) * parentChInfo.chansPerNode);
        if (nodeChannel + parentChInfo.chansPerNode > static_cast<uint32_t>(localFrameData.size()))
            continue;

        uint8_t r = localFrameData[nodeChannel + parentChInfo.rOffset];
        uint8_t g = localFrameData[nodeChannel + parentChInfo.gOffset];
        uint8_t b = localFrameData[nodeChannel + parentChInfo.bOffset];

        if (r > 0 || g > 0 || b > 0) nonBlackPixels++;

        int bx = subNodes[i].bufX;
        int by = subNodes[i].bufY;
        if (bx < 0 || bx >= subBufW || by < 0 || by >= subBufH) continue;

        size_t pIdx = (static_cast<size_t>(by) * subBufW + bx) * 4;
        fb.pixels[pIdx]     = r;
        fb.pixels[pIdx + 1] = g;
        fb.pixels[pIdx + 2] = b;
        fb.pixels[pIdx + 3] = 255;
    }

    static std::set<std::string> sLogged;
    if (sLogged.insert(subRefName).second) {
        printf("[GRP] synthesizeSubmodelBuffer('%s'): %zu subNodes, buffer=%dx%d, %d non-black pixels\n",
               subRefName.c_str(), subNodeCount, subBufW, subBufH, nonBlackPixels);
    }

    std::lock_guard<std::mutex> lock(_sidebarCacheMutex);
    _sidebarCache[subRefName] = std::move(fb);
}

void RenderEngine::synthesizeSubmodelFrameBuffer(
    const std::string& subRefName, const ModelChannelInfo& parentChInfo, int timeMS)
{
    // Caller must hold _bufferCacheMutex.
    if (!_modelProvider || _currentFrameData.empty()) return;

    size_t slash = subRefName.find('/');
    if (slash == std::string::npos) return;
    std::string parentName = subRefName.substr(0, slash);
    std::string subName = subRefName.substr(slash + 1);

    auto parentAttrs = _modelProvider->getModelAttributes(parentName);
    if (parentAttrs.empty()) return;

    auto allParentNodes = generateNodesFromAttributes(parentAttrs);
    if (allParentNodes.empty()) return;

    auto subAttrs = _modelProvider->getSubmodelAttributes(parentName, subName);
    if (subAttrs.empty()) return;

    auto subNodes = filterNodesToSubmodel(allParentNodes, subAttrs);
    if (subNodes.empty()) return;

    // Get parent node indices for channel data lookup
    std::vector<int> parentNodeIndices;
    {
        auto typeIt = subAttrs.find("type");
        bool isSubBuffer = (typeIt != subAttrs.end() && typeIt->second == "subbuffer");
        if (isSubBuffer) {
            for (int i = 0; i < static_cast<int>(allParentNodes.size()); i++)
                parentNodeIndices.push_back(i);
        } else {
            for (int lineIdx = 0; lineIdx < 100; ++lineIdx) {
                std::string key = "line" + std::to_string(lineIdx);
                auto it = subAttrs.find(key);
                if (it == subAttrs.end() || it->second.empty()) {
                    if (lineIdx > 0) break;
                    continue;
                }
                std::istringstream stream(it->second);
                std::string token;
                while (std::getline(stream, token, ',')) {
                    size_t start = token.find_first_not_of(" \t");
                    size_t end = token.find_last_not_of(" \t");
                    if (start == std::string::npos) continue;
                    token = token.substr(start, end - start + 1);
                    if (token.empty()) continue;
                    size_t dashPos = token.find('-');
                    int rangeStart, rangeEnd;
                    if (dashPos != std::string::npos) {
                        rangeStart = std::atoi(token.substr(0, dashPos).c_str()) - 1;
                        rangeEnd = std::atoi(token.substr(dashPos + 1).c_str()) - 1;
                        if (rangeStart < 0) rangeStart = 0;
                        if (rangeEnd < rangeStart) std::swap(rangeStart, rangeEnd);
                    } else {
                        rangeStart = rangeEnd = std::atoi(token.c_str()) - 1;
                        if (rangeStart < 0) continue;
                    }
                    for (int idx = rangeStart; idx <= rangeEnd; idx++) {
                        if (idx >= 0 && idx < static_cast<int>(allParentNodes.size()))
                            parentNodeIndices.push_back(idx);
                    }
                }
            }
        }
    }

    // Determine submodel buffer dimensions
    int maxBufX = 0, maxBufY = 0;
    for (const auto& nc : subNodes) {
        if (nc.bufX > maxBufX) maxBufX = nc.bufX;
        if (nc.bufY > maxBufY) maxBufY = nc.bufY;
    }
    int subBufW = maxBufX + 1;
    int subBufH = maxBufY + 1;

    FrameBuffer fb;
    fb.modelName = subRefName;
    fb.width = subBufW;
    fb.height = subBufH;
    fb.timeMS = timeMS;
    fb.pixels.resize(static_cast<size_t>(subBufW) * subBufH * 4, 0);

    size_t subNodeCount = std::min(subNodes.size(), parentNodeIndices.size());
    uint32_t dataSize = static_cast<uint32_t>(_currentFrameData.size());
    int nonBlackPixels = 0;
    for (size_t i = 0; i < subNodeCount; i++) {
        int parentIdx = parentNodeIndices[i];
        if (parentIdx < 0 || parentIdx >= static_cast<int>(parentChInfo.nodeCount)) continue;
        uint32_t nodeChannel = parentChInfo.absStartChannel +
                               (static_cast<uint32_t>(parentIdx) * parentChInfo.chansPerNode);
        if (nodeChannel + parentChInfo.chansPerNode > dataSize) continue;

        uint8_t r = _currentFrameData[nodeChannel + parentChInfo.rOffset];
        uint8_t g = _currentFrameData[nodeChannel + parentChInfo.gOffset];
        uint8_t b = _currentFrameData[nodeChannel + parentChInfo.bOffset];

        if (r > 0 || g > 0 || b > 0) nonBlackPixels++;

        int bx = subNodes[i].bufX;
        int by = subNodes[i].bufY;
        if (bx < 0 || bx >= subBufW || by < 0 || by >= subBufH) continue;

        size_t pIdx = (static_cast<size_t>(by) * subBufW + bx) * 4;
        fb.pixels[pIdx]     = r;
        fb.pixels[pIdx + 1] = g;
        fb.pixels[pIdx + 2] = b;
        fb.pixels[pIdx + 3] = 255;
    }

    static std::set<std::string> sLogged;
    if (sLogged.insert(subRefName).second) {
        printf("[SUBDBG] synthesizeSubmodelFrameBuffer('%s'): %zu subNodes, buffer=%dx%d, %d non-black, parentStart=%u parentNodes=%u\n",
               subRefName.c_str(), subNodeCount, subBufW, subBufH, nonBlackPixels,
               parentChInfo.absStartChannel, parentChInfo.nodeCount);
    }

    _bufferCache[subRefName] = std::move(fb);
}

void RenderEngine::forceRenderAll(RenderCompleteCallback callback)
{
    // Prevent concurrent renders and block renderFrame() on main thread.
    if (_renderInProgress.exchange(true, std::memory_order_acq_rel)) {
        printf("[RDBG] forceRenderAll: SKIPPED (already rendering)\n");
        if (callback) callback(true);
        return;
    }
    {
        std::lock_guard<std::mutex> lock(_dirtyMutex);
        printf("[RDBG] forceRenderAll: ENTRY — allDirty=%d dirtyModels=%zu renderedData=%s fseqLoaded=%d channelRanges=%zu\n",
               _allDirty.load(), _dirtyModels.size(),
               (_renderedData && _renderedData->isValid()) ? "valid" : "null",
               _fseqLoaded.load(), _modelChannelRanges.size());
    }
    printf("RenderEngine::forceRenderAll — clearing all caches and forcing full render\n");

    // Destroy background render queue FIRST — its destructor waits for
    // in-progress renders that write to _renderedData. Destroying
    // _renderedData first would cause use-after-free.
    _bgRenderQueue.reset();
    _bgCoordinator.reset();
    _bgContext.reset();

    // Now safe to destroy the rest.
    _renderedData.reset();
    _fseqLoaded = false;
    {
        std::lock_guard<std::mutex> lock(_fseqMutex);
        _fseqFile.reset();
    }

    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        _bufferCache.clear();
        _modelChannelMap.clear();
        _currentFrameIndex = -1;
        _currentFrameData.clear();
        _liveCoordinator.reset();
        _liveContext.reset();
        _lastLiveRenderTimeMS = -1;
    }
    {
        std::lock_guard<std::mutex> lock(_sidebarCacheMutex);
        _sidebarCache.clear();
        _sidebarCoordinator.reset();
        _sidebarContext.reset();
        _lastSidebarRenderTimeMS = -1;
    }
    {
        std::lock_guard<std::mutex> lock(_dirtyMutex);
        _allDirty.store(true);
        _dirtyModels.clear();
        _modelChannelRanges.clear();
    }

    // Clear resolved channel caches so they're rebuilt fresh
    _controllerStartChannels.clear();
    _modelTotalChannels.clear();
    _resolvedStartChannels.clear();

    // Clear disk cache
    if (_diskCache) {
        _diskCache->clearAll();
    }

    renderAll(callback);
}

void RenderEngine::reRenderForEffectChange(RenderCompleteCallback callback)
{
    // Lighter than forceRenderAll: preserves _modelChannelMap and
    // resolved start channel caches. Only effects changed, not model layout.
    if (_renderInProgress.exchange(true, std::memory_order_acq_rel)) {
        printf("[RDBG] reRenderForEffectChange: SKIPPED (already rendering)\n");
        if (callback) callback(true);
        return;
    }

    printf("[RDBG] reRenderForEffectChange: ENTRY — preserving channel map (size=%zu)\n",
           _modelChannelMap.size());

    // Destroy background render queue first (same safety as forceRenderAll)
    _bgRenderQueue.reset();
    _bgCoordinator.reset();
    _bgContext.reset();

    // Destroy rendered data and FSEQ (will be re-rendered)
    _renderedData.reset();
    _fseqLoaded = false;
    {
        std::lock_guard<std::mutex> lock(_fseqMutex);
        _fseqFile.reset();
    }

    // Clear pixel caches but PRESERVE _modelChannelMap
    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        _bufferCache.clear();
        // NOTE: _modelChannelMap is NOT cleared — model layout didn't change
        _currentFrameIndex = -1;
        _currentFrameData.clear();
        _liveCoordinator.reset();
        _liveContext.reset();
        _lastLiveRenderTimeMS = -1;
    }
    {
        std::lock_guard<std::mutex> lock(_sidebarCacheMutex);
        _sidebarCache.clear();
        _sidebarCoordinator.reset();
        _sidebarContext.reset();
        _lastSidebarRenderTimeMS = -1;
    }
    {
        std::lock_guard<std::mutex> lock(_dirtyMutex);
        _allDirty.store(true);
        _dirtyModels.clear();
        // NOTE: _modelChannelRanges is NOT cleared — model layout didn't change
    }

    // NOTE: _controllerStartChannels, _modelTotalChannels,
    // _resolvedStartChannels are NOT cleared — these are layout-dependent,
    // not effect-dependent.

    // Clear disk cache (effect data changed, cached renders are stale)
    if (_diskCache) {
        _diskCache->clearAll();
    }

    renderAll(callback);
}

void RenderEngine::renderAll(RenderCompleteCallback callback)
{
    // Set _renderInProgress if not already set (forceRenderAll sets it first).
    // This blocks renderFrame() on the main thread during the entire render.
    bool wasAlreadyInProgress = _renderInProgress.exchange(true, std::memory_order_acq_rel);
    {
        std::lock_guard<std::mutex> lock(_dirtyMutex);
        printf("[RDBG] renderAll: ENTRY — allDirty=%d dirtyModels=%zu renderedData=%s fseqLoaded=%d mapSize=%zu wasAlreadyInProgress=%d\n",
               _allDirty.load(), _dirtyModels.size(),
               (_renderedData && _renderedData->isValid()) ? "valid" : "null",
               _fseqLoaded.load(), _modelChannelMap.size(), wasAlreadyInProgress);
    }

    if (!_effectProvider || !_modelProvider) {
        printf("RenderEngine::renderAll — missing effect or model provider, skipping\n");
        if (!wasAlreadyInProgress) _renderInProgress.store(false, std::memory_order_release);
        if (callback) callback(false);
        notifyRenderComplete(false);
        return;
    }

    // --- Fast path: nothing dirty, rendered data still valid ---
    {
        std::lock_guard<std::mutex> lock(_dirtyMutex);
        if (!_allDirty.load() && _dirtyModels.empty() && _renderedData && _renderedData->isValid()) {
            printf("RenderEngine::renderAll — nothing dirty, instant return (0ms)\n");
            // Close stale FSEQ so renderFrame uses pre-rendered data path
            _fseqLoaded = false;
            {
                std::lock_guard<std::mutex> fLock(_fseqMutex);
                _fseqFile.reset();
            }
            // Reset frame cache so renderFrame picks up the existing data
            _currentFrameIndex = -1;
            _renderInProgress.store(false, std::memory_order_release);
            notifyRenderComplete(false);
            if (callback) callback(false);
            return;
        }
    }

    // Determine sequence parameters
    int frameTimeMS = getFrameTimeMS();
    int numFrames = getNumFrames();
    int32_t totalChannels = _outputProvider ? _outputProvider->getTotalChannels() : 0;
    int32_t requiredChannels = computeRequiredChannels();

    printf("[RDBG] renderAll: totalChannels=%d requiredChannels=%d numFrames=%d frameTimeMS=%d\n",
           totalChannels, requiredChannels, numFrames, frameTimeMS);

    // Use the larger of output channels and model-required channels
    if (requiredChannels > totalChannels) {
        printf("[RDBG] renderAll: expanding from %d to %d channels (models need more)\n",
               totalChannels, requiredChannels);
        totalChannels = requiredChannels;
    }

    if (numFrames <= 0 || totalChannels <= 0) {
        printf("[RDBG] renderAll: BAIL — invalid sequence: %d frames, %d channels\n",
               numFrames, totalChannels);
        _renderInProgress.store(false, std::memory_order_release);
        if (callback) callback(false);
        notifyRenderComplete(false);
        return;
    }

    // --- Incremental path: re-render only dirty models ---
    std::set<std::string> dirtyModels;
    bool fullRender = _allDirty.load();
    if (!fullRender) {
        std::lock_guard<std::mutex> lock(_dirtyMutex);
        dirtyModels = _dirtyModels;
    }

    if (!fullRender && _renderedData && _renderedData->isValid()
        && _renderedData->getNumChannels() == static_cast<uint32_t>(totalChannels)
        && _renderedData->getNumFrames() == static_cast<uint32_t>(numFrames)
        && !dirtyModels.empty()) {

        // Cancel background rendering — we're about to do a synchronous render.
        if (_bgRenderQueue) {
            _bgRenderQueue->cancelAll();
        }

        // Check which dirty models were already rendered in the background.
        // Remove them from the dirty set — their data is already in _renderedData.
        std::set<std::string> bgCompleted;
        if (_bgRenderQueue) {
            bgCompleted = _bgRenderQueue->getCompletedModels();
            for (const auto& m : bgCompleted) {
                dirtyModels.erase(m);
                _bgRenderQueue->clearCompletedModel(m);
            }
        }

        printf("RenderEngine::renderAll — INCREMENTAL: %zu dirty, %zu pre-rendered in bg\n",
               dirtyModels.size(), bgCompleted.size());
        for (const auto& m : dirtyModels) {
            printf("  still dirty: %s\n", m.c_str());
        }

        // If all dirty models were pre-rendered in the background, instant return.
        if (dirtyModels.empty()) {
            std::lock_guard<std::mutex> lock(_dirtyMutex);
            _dirtyModels.clear();
            // Close stale FSEQ so renderFrame uses pre-rendered data path
            _fseqLoaded = false;
            {
                std::lock_guard<std::mutex> fLock(_fseqMutex);
                _fseqFile.reset();
            }
            _currentFrameIndex = -1;

            printf("RenderEngine::renderAll — all dirty models pre-rendered in background (0ms)\n");
            _renderInProgress.store(false, std::memory_order_release);
            notifyRenderComplete(false);
            if (callback) callback(false);
            return;
        }

        auto wallStart = std::chrono::steady_clock::now();

        double duration = static_cast<double>(numFrames) * frameTimeMS / 1000.0;
        auto context = std::make_unique<RenderEngineContext>(frameTimeMS, duration, _audioProvider);

        // Zero dirty model channel ranges before re-rendering
        for (const auto& modelName : dirtyModels) {
            auto rangeIt = _modelChannelRanges.find(modelName);
            if (rangeIt != _modelChannelRanges.end()) {
                uint32_t startCh = rangeIt->second.first;
                uint32_t chCount = rangeIt->second.second;
                for (uint32_t f = 0; f < static_cast<uint32_t>(numFrames); ++f) {
                    uint8_t* frameData = _renderedData->getFrame(f);
                    if (frameData && startCh + chCount <= _renderedData->getNumChannels()) {
                        std::memset(frameData + startCh, 0, chCount);
                    }
                }
            }
        }

        // Ensure start channels are resolved
        if (_controllerStartChannels.empty()) {
            buildControllerChannelMap();
        }
        if (_modelTotalChannels.empty()) {
            buildModelTotalChannelsMap();
        }

        std::unordered_map<std::string, uint32_t> resolvedChannels;
        {
            auto modelNames = _modelProvider->getModelNames();
            for (const auto& name : modelNames) {
                auto attrs = _modelProvider->getModelAttributes(name);
                auto displayAs = attrs.find("DisplayAs");
                if (displayAs != attrs.end() && displayAs->second == "ModelGroup") continue;
                auto scIt = attrs.find("StartChannel");
                if (scIt != attrs.end() && !scIt->second.empty()) {
                    resolvedChannels[name] = resolveStartChannel(scIt->second);
                }
            }
        }

        // Create coordinator for incremental render
        _coordinator = std::make_unique<NativeRenderCoordinator>(
            _effectProvider, _modelProvider, context.get());
        _coordinator->setResolvedStartChannels(resolvedChannels);

        // Use renderModels for selective rendering
        std::vector<std::string> dirtyModelVec(dirtyModels.begin(), dirtyModels.end());
        bool completed = _coordinator->renderModels(dirtyModelVec, *_renderedData);

        _coordinator.reset();

        // Clear dirty state
        {
            std::lock_guard<std::mutex> lock(_dirtyMutex);
            _dirtyModels.clear();
        }

        _currentFrameIndex = -1;

        auto wallEnd = std::chrono::steady_clock::now();
        auto wallMS = std::chrono::duration<double, std::milli>(wallEnd - wallStart).count();
        printf("RenderEngine::renderAll — INCREMENTAL complete in %.1fms (%zu rendered, %zu from bg)\n",
               wallMS, dirtyModels.size(), bgCompleted.size());

        bool wasCancelled = !completed;
        _renderInProgress.store(false, std::memory_order_release);
        notifyRenderComplete(wasCancelled);
        if (callback) callback(wasCancelled);
        return;
    }

    // --- Full render path ---
    auto fullRenderWallStart = std::chrono::steady_clock::now();

    // Cancel background queue before full render (it references _renderedData
    // which will be replaced below).
    _bgRenderQueue.reset();
    _bgCoordinator.reset();
    _bgContext.reset();

    // Clear disk cache before full render to avoid stale data from previous sessions.
    if (_diskCache) {
        _diskCache->clearAll();
    }

    // Clear _modelChannelMap BEFORE allocating the new buffer. This forces
    // renderFrame() to use the LIVE path during the 10+ second render instead
    // of reading from the half-rendered _renderedData via the PRERENDERED path.
    // The map is rebuilt after rendering completes.
    _modelChannelMap.clear();

    double duration = static_cast<double>(numFrames) * frameTimeMS / 1000.0;
    printf("RenderEngine::renderAll — FULL render: %d frames (%dms), %d channels, %.1fs\n",
           numFrames, frameTimeMS, totalChannels, duration);

    // Create render context
    auto context = std::make_unique<RenderEngineContext>(frameTimeMS, duration, _audioProvider);

    // Render into a separate buffer, then swap into _renderedData when done.
    // This prevents renderFrame() from reading partially-rendered data.
    auto newRenderedData = std::make_unique<NativeSequenceData>(
        static_cast<uint32_t>(totalChannels),
        static_cast<uint32_t>(numFrames),
        static_cast<uint32_t>(frameTimeMS));

    // Resolve start channels BEFORE rendering
    if (_controllerStartChannels.empty()) {
        buildControllerChannelMap();
    }
    if (_modelTotalChannels.empty()) {
        buildModelTotalChannelsMap();
    }

    // Pre-resolve all model start channels
    std::unordered_map<std::string, uint32_t> resolvedChannels;
    {
        auto modelNames = _modelProvider->getModelNames();
        for (const auto& name : modelNames) {
            auto attrs = _modelProvider->getModelAttributes(name);
            auto displayAs = attrs.find("DisplayAs");
            if (displayAs != attrs.end() && displayAs->second == "ModelGroup") continue;
            auto scIt = attrs.find("StartChannel");
            if (scIt != attrs.end() && !scIt->second.empty()) {
                resolvedChannels[name] = resolveStartChannel(scIt->second);
            }
        }
        printf("RenderEngine::renderAll — pre-resolved %zu model start channels\n",
               resolvedChannels.size());
    }

    // Create coordinator and set up progress forwarding
    _coordinator = std::make_unique<NativeRenderCoordinator>(
        _effectProvider, _modelProvider, context.get());
    _coordinator->setResolvedStartChannels(resolvedChannels);

    // Bridge coordinator listener to RenderEngineListener
    class ListenerBridge : public RenderCoordinatorListener {
    public:
        explicit ListenerBridge(RenderEngine* engine) : _engine(engine) {}
        void onRenderProgress(float pct, int done, int total) override {
            RenderStatus status;
            status.isRendering = true;
            status.framesComplete = done;
            status.framesTotal = total;
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

    // Configure disk cache for persistence across sessions.
    if (!_showFolderPath.empty()) {
        if (!_diskCache) {
            _diskCache = std::make_unique<DiskRenderCache>();
        }
        // Build cache directory: ShowFolder/RenderCache/NATIVE_CACHE/
        std::string cacheDir = _showFolderPath + "/RenderCache/NATIVE_CACHE";
        _diskCache->setCacheDirectory(cacheDir);
        _coordinator->setDiskCache(_diskCache.get());
    }

    bool completed = _coordinator->renderAll(*newRenderedData);

    auto fullRenderWallEnd = std::chrono::steady_clock::now();
    auto fullRenderWallMS = std::chrono::duration<double, std::milli>(
        fullRenderWallEnd - fullRenderWallStart).count();

    _coordinator->setListener(nullptr);
    _coordinator.reset();

    // Swap the fully-rendered buffer into _renderedData atomically.
    // Until this point, _renderedData was null (or old) and _modelChannelMap
    // was empty, so renderFrame() used the LIVE path during rendering.
    _renderedData = std::move(newRenderedData);

    bool wasCancelled = !completed;
    notifyRenderComplete(wasCancelled);
    if (callback) callback(wasCancelled);

    // Clear stale sidebar cache from live rendering — prevents submodel entries
    // from the live preview persisting into prerender/FSEQ playback mode.
    {
        std::lock_guard<std::mutex> lock(_sidebarCacheMutex);
        _sidebarCache.clear();
    }

    // After successful render, build the model channel map so renderFrame()
    // can read from _renderedData instead of re-rendering effects live.
    if (!wasCancelled && _renderedData && _renderedData->isValid()) {
        // Close stale FSEQ so renderFrame() uses the pre-rendered data path
        // instead of reading from the old (now-overwritten) FSEQ file.
        // Don't use closeFSEQ() — it clears _modelChannelMap which we need.
        _fseqLoaded = false;
        {
            std::lock_guard<std::mutex> lock(_fseqMutex);
            _fseqFile.reset();
        }
        // Always rebuild the map after a full render — the previous map
        // may have stale absStartChannel offsets from an earlier _renderedData.
        buildControllerChannelMap();
        buildModelTotalChannelsMap();
        buildModelChannelMap();
        // Reset frame cache so next renderFrame reads from _renderedData
        _currentFrameIndex = -1;

        // Populate _modelChannelRanges for future incremental renders.
        // Each model's channel range is (startChannel, channelCount) so we
        // can zero just that range before re-rendering a dirty model.
        {
            std::lock_guard<std::mutex> lock(_dirtyMutex);
            _modelChannelRanges.clear();
            for (const auto& [name, chInfo] : _modelChannelMap) {
                uint32_t chCount = chInfo.nodeCount * chInfo.chansPerNode;
                if (chCount > 0) {
                    _modelChannelRanges[name] = {chInfo.absStartChannel, chCount};
                }
            }
        }

        // Clear dirty state after successful full render
        {
            std::lock_guard<std::mutex> lock(_dirtyMutex);
            _allDirty.store(false);
            _dirtyModels.clear();
        }

        printf("[RDBG] renderAll: FULL RENDER COMPLETE in %.1fms (%s) — %u frames, %u channels, stepTime=%u ms (renderAll used %dms), mapSize=%zu\n",
               fullRenderWallMS, wasCancelled ? "CANCELLED" : "ok",
               _renderedData->getNumFrames(), _renderedData->getNumChannels(),
               _renderedData->getFrameTimeMS(), frameTimeMS,
               _modelChannelMap.size());

        // Validate rendered data: dense sampling around the 13-15s range
        // where the second render shows unexpected nonZero data
        uint32_t numCh = _renderedData->getNumChannels();
        uint32_t nFrames = _renderedData->getNumFrames();
        uint32_t gen = _renderGeneration.load(std::memory_order_relaxed);
        uint32_t sampleTimes[] = {
            0, 5000, 10000, 12000, 12500, 13000, 13500, 13750,
            13900, 14000, 14100, 14200, 14300, 14500, 15000,
            17500, 20000, 25000, 30000, 35000
        };

        for (uint32_t st : sampleTimes) {
            uint32_t sf = st / frameTimeMS;
            if (sf >= nFrames) continue;
            const uint8_t* frameData = _renderedData->getFrame(sf);
            if (!frameData) continue;

            uint32_t nonZero = 0;
            for (uint32_t i = 0; i < numCh; ++i) {
                if (frameData[i] != 0) nonZero++;
            }
            printf("[RDBG] renderAll(gen=%u): frame[%u] (t=%ums): %u/%u non-zero channels\n",
                   gen, sf, st, nonZero, numCh);
        }

        // Sample up to 10 models at t=20s (within effect range) to check per-model data
        uint32_t sampleFrame = 20000 / frameTimeMS;
        if (sampleFrame >= nFrames) sampleFrame = nFrames / 2;
        const uint8_t* midData = _renderedData->getFrame(sampleFrame);
        if (midData) {
            printf("[RDBG] renderAll: sampling models at frame %u (t=%ums):\n",
                   sampleFrame, sampleFrame * frameTimeMS);
            int sampleCount = 0;
            for (const auto& [name, chInfo] : _modelChannelMap) {
                if (sampleCount >= 10) break;
                uint32_t ch = chInfo.absStartChannel;
                uint32_t end = ch + chInfo.nodeCount * chInfo.chansPerNode;
                uint32_t modelNonZero = 0;
                for (uint32_t i = ch; i < end && i < numCh; ++i) {
                    if (midData[i] != 0) modelNonZero++;
                }
                // First 6 bytes as hex
                char hexBuf[32] = {0};
                if (ch + 6 <= numCh) {
                    snprintf(hexBuf, sizeof(hexBuf), "[%02x %02x %02x %02x %02x %02x]",
                             midData[ch], midData[ch+1], midData[ch+2],
                             midData[ch+3], midData[ch+4], midData[ch+5]);
                }
                printf("[RDBG]   '%s' ch=%u..%u nodes=%u nonZero=%u bytes=%s\n",
                       name.c_str(), ch, end, chInfo.nodeCount, modelNonZero, hexBuf);
                sampleCount++;
            }
        }
    } else {
        printf("[RDBG] renderAll: FULL RENDER %s in %.1fms — renderedData=%s\n",
               wasCancelled ? "CANCELLED" : "FAILED", fullRenderWallMS,
               (_renderedData && _renderedData->isValid()) ? "valid" : "null/invalid");
    }

    // Bump render generation so renderFrame resets its diagnostic counters.
    uint32_t gen = _renderGeneration.fetch_add(1, std::memory_order_relaxed) + 1;

    // Allow renderFrame() to resume reading the freshly rendered data.
    _renderInProgress.store(false, std::memory_order_release);
    printf("[RDBG] renderAll: _renderInProgress → false, generation=%u\n", gen);
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
    int32_t requiredChannels = computeRequiredChannels();

    printf("[RDBG] renderRange: totalChannels=%d requiredChannels=%d numFrames=%d\n",
           totalChannels, requiredChannels, numFrames);

    if (requiredChannels > totalChannels) totalChannels = requiredChannels;

    if (numFrames <= 0 || totalChannels <= 0) {
        printf("[RDBG] renderRange: BAIL — %d frames, %d channels\n", numFrames, totalChannels);
        if (callback) callback(false);
        return;
    }

    double duration = static_cast<double>(numFrames) * frameTimeMS / 1000.0;
    auto context = std::make_unique<RenderEngineContext>(frameTimeMS, duration, _audioProvider);

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

    // Ensure start channels are resolved for correct channel mapping
    if (_controllerStartChannels.empty()) {
        buildControllerChannelMap();
    }
    if (_modelTotalChannels.empty()) {
        buildModelTotalChannelsMap();
    }

    std::unordered_map<std::string, uint32_t> resolvedChannels;
    {
        auto modelNames = _modelProvider->getModelNames();
        for (const auto& name : modelNames) {
            auto attrs = _modelProvider->getModelAttributes(name);
            auto displayAs = attrs.find("DisplayAs");
            if (displayAs != attrs.end() && displayAs->second == "ModelGroup") continue;
            auto scIt = attrs.find("StartChannel");
            if (scIt != attrs.end() && !scIt->second.empty()) {
                resolvedChannels[name] = resolveStartChannel(scIt->second);
            }
        }
    }

    _coordinator = std::make_unique<NativeRenderCoordinator>(
        _effectProvider, _modelProvider, context.get());
    _coordinator->setResolvedStartChannels(resolvedChannels);

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
    // Check sidebar cache first — it has the most recent per-model render
    // (from renderModelFrame), which is more current than batch renderFrame
    // results that may be stale after playback stops.
    {
        std::lock_guard<std::mutex> lock(_sidebarCacheMutex);
        auto it = _sidebarCache.find(modelName);
        if (it != _sidebarCache.end()) {
            return it->second;
        }
    }
    // Fall through to main buffer cache (populated by renderFrame)
    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        auto it = _bufferCache.find(modelName);
        if (it != _bufferCache.end()) {
            return it->second;
        }
    }
    return {};
}

std::vector<FrameBuffer> RenderEngine::getAllFrameBuffers() const
{
    std::vector<FrameBuffer> result;
    std::set<std::string> seen;

    // Collect from batch cache first — renderFrame() produces fresh data
    // each frame for all physical models. This is what the playback
    // controller needs for the house preview.
    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        result.reserve(_bufferCache.size());
        for (const auto& [name, fb] : _bufferCache) {
            if (fb.isValid()) {
                result.push_back(fb);
                seen.insert(name);
            }
        }
    }
    // Then add sidebar-only entries (submodel refs like "Singing Tree/Outline"
    // that aren't rendered by renderFrame's physical-model-only loop)
    {
        std::lock_guard<std::mutex> lock(_sidebarCacheMutex);
        for (const auto& [name, fb] : _sidebarCache) {
            if (fb.isValid() && seen.find(name) == seen.end()) {
                result.push_back(fb);
            }
        }
    }
    return result;
}

void RenderEngine::visitFrameBuffers(const FrameBufferVisitor& visitor) const
{
    std::set<std::string> seen;

    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        for (const auto& [name, fb] : _bufferCache) {
            if (fb.isValid()) {
                visitor(name, fb.pixels.data(), fb.pixels.size(),
                        fb.width, fb.height);
                seen.insert(name);
            }
        }
    }
    {
        std::lock_guard<std::mutex> lock(_sidebarCacheMutex);
        for (const auto& [name, fb] : _sidebarCache) {
            if (fb.isValid() && seen.find(name) == seen.end()) {
                visitor(name, fb.pixels.data(), fb.pixels.size(),
                        fb.width, fb.height);
            }
        }
    }
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
    // Cancel background render queue FIRST — its destructor waits for
    // in-progress renders that write to _renderedData. Destroying
    // _renderedData first would cause use-after-free.
    _bgRenderQueue.reset();
    _bgCoordinator.reset();
    _bgContext.reset();

    // Close FSEQ so the FSEQ playback path is no longer used.
    // Must be called before taking _bufferCacheMutex (closeFSEQ locks it too).
    closeFSEQ();

    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        _bufferCache.clear();
        _currentFrameIndex = -1;
        _currentFrameData.clear();
        _renderedData.reset();
        _liveCoordinator.reset();
        _liveContext.reset();
        _lastLiveRenderTimeMS = -1;
    }
    {
        std::lock_guard<std::mutex> lock(_sidebarCacheMutex);
        _sidebarCache.clear();
        _sidebarCoordinator.reset();
        _sidebarContext.reset();
        _lastSidebarRenderTimeMS = -1;
    }

    // Clear disk cache (full invalidation means all cached data is stale).
    if (_diskCache) {
        _diskCache->clearAll();
    }

    // Mark everything dirty
    {
        std::lock_guard<std::mutex> lock(_dirtyMutex);
        _allDirty.store(true);
        _dirtyModels.clear();
        _modelChannelRanges.clear();
    }
}

void RenderEngine::invalidateModel(const std::string& modelName)
{
    if (modelName.empty()) return;

    // Lightweight: just mark dirty and clear caches. NO allocation,
    // NO channel zeroing. Heavy work is done by the caller (e.g.,
    // invalidateModelAndGroup dispatches a background renderAll).
    printf("[RDBG] invalidateModel('%s'): marking dirty\n", modelName.c_str());

    {
        std::lock_guard<std::mutex> lock(_dirtyMutex);
        _dirtyModels.insert(modelName);
    }

    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        _bufferCache.erase(modelName);
        _currentFrameIndex = -1; // force re-read on next renderFrame

        if (_liveCoordinator) {
            _liveCoordinator->resetPersistentState(modelName);
            _liveCoordinator->invalidateCache(modelName);
        }
    }
    {
        std::lock_guard<std::mutex> lock(_sidebarCacheMutex);
        _sidebarCache.erase(modelName);
        if (_sidebarCoordinator) {
            _sidebarCoordinator->resetPersistentState(modelName);
            _sidebarCoordinator->invalidateCache(modelName);
        }
    }
}

void RenderEngine::invalidateModelAndGroup(const std::string& modelName)
{
    if (modelName.empty()) return;

    printf("[RDBG] invalidateModelAndGroup('%s')\n", modelName.c_str());

    // Always dirty the model/group itself
    invalidateModel(modelName);

    if (!_modelProvider) return;

    // Recursively expand groups to dirty all leaf physical models.
    // Uses a worklist to avoid deep recursion on nested groups.
    std::set<std::string> visited;
    std::vector<std::string> worklist = { modelName };
    int physicalCount = 0;

    while (!worklist.empty()) {
        std::string current = std::move(worklist.back());
        worklist.pop_back();
        if (!visited.insert(current).second) continue; // already visited

        auto attrs = _modelProvider->getModelAttributes(current);
        auto displayAs = attrs.find("DisplayAs");

        if (displayAs != attrs.end() && displayAs->second == "ModelGroup") {
            // Group — expand to members
            auto membersIt = attrs.find("models");
            if (membersIt != attrs.end()) {
                const std::string& members = membersIt->second;
                size_t pos = 0;
                while (pos < members.size()) {
                    size_t comma = members.find(',', pos);
                    if (comma == std::string::npos) comma = members.size();
                    std::string member = members.substr(pos, comma - pos);
                    size_t start = member.find_first_not_of(" \t");
                    size_t end = member.find_last_not_of(" \t");
                    if (start != std::string::npos) {
                        member = member.substr(start, end - start + 1);
                        size_t slash = member.find('/');
                        if (slash != std::string::npos) {
                            member = member.substr(0, slash);
                        }
                        if (!member.empty() && visited.find(member) == visited.end()) {
                            invalidateModel(member);
                            worklist.push_back(member);
                        }
                    }
                    pos = comma + 1;
                }
            }
        } else if (_modelChannelMap.count(current) > 0) {
            physicalCount++;
        }
    }

    printf("[RDBG] invalidateModelAndGroup('%s'): expanded to %zu models (%d physical), visited %zu total\n",
           modelName.c_str(), visited.size(), physicalCount, visited.size());

    // Clear ALL playback data so renderFrame falls back to LIVE path.
    // FSEQ must be cleared too — stale FSEQ data is as wrong as stale
    // pre-rendered data. LIVE path renders effects in real-time from
    // the effect provider, so it always reflects the current edit state.
    _fseqLoaded = false;
    {
        std::lock_guard<std::mutex> fLock(_fseqMutex);
        _fseqFile.reset();
    }
    {
        std::lock_guard<std::mutex> lock(_bufferCacheMutex);
        _renderedData.reset();
        _bufferCache.clear();
        _currentFrameIndex = -1;
        // Destroy live coordinator so it's recreated fresh with clean state
        _liveCoordinator.reset();
        _liveContext.reset();
        _lastLiveRenderTimeMS = -1;
    }
    printf("[RDBG] invalidateModelAndGroup('%s'): %zu models dirtied, cleared FSEQ+renderedData → LIVE fallback\n",
           modelName.c_str(), visited.size());

    // Also check if this physical model belongs to any group with effects
    if (visited.size() == 1 && physicalCount == 1) {
        auto allNames = _modelProvider->getModelNames();
        for (const auto& name : allNames) {
            if (visited.count(name)) continue;
            auto gAttrs = _modelProvider->getModelAttributes(name);
            auto gDisplay = gAttrs.find("DisplayAs");
            if (gDisplay == gAttrs.end() || gDisplay->second != "ModelGroup") continue;
            auto gMembers = gAttrs.find("models");
            if (gMembers == gAttrs.end()) continue;
            if (gMembers->second.find(modelName) != std::string::npos) {
                invalidateModel(name);
            }
        }
    }
}

bool RenderEngine::hasDirtyModels() const
{
    if (_allDirty.load()) return true;
    std::lock_guard<std::mutex> lock(_dirtyMutex);
    return !_dirtyModels.empty();
}

std::set<std::string> RenderEngine::getDirtyModels() const
{
    std::lock_guard<std::mutex> lock(_dirtyMutex);
    return _dirtyModels;
}

void RenderEngine::connectEffectEngine(EffectEngine* engine)
{
    disconnectEffectEngine();
    if (engine) {
        _connectedEffectEngine = engine;
        engine->addListener(this);
    }
}

void RenderEngine::disconnectEffectEngine()
{
    if (_connectedEffectEngine) {
        _connectedEffectEngine->removeListener(this);
        _connectedEffectEngine = nullptr;
    }
}

// --- Show folder ---

void RenderEngine::setShowFolder(const std::string& path)
{
    _showFolderPath = path;
    printf("RenderEngine: show folder set to '%s'\n", path.c_str());
}

// --- Background render queue ---

void RenderEngine::ensureBackgroundRenderQueue()
{
    if (_bgRenderQueue) return;
    if (!_effectProvider || !_modelProvider) return;

    int frameTimeMS = getFrameTimeMS();
    int numFrames = getNumFrames();
    if (numFrames <= 0 || frameTimeMS <= 0) return;

    // Allocate _renderedData if it doesn't exist yet (e.g., after fresh FSEQ load).
    // Zeroed initially — the FSEQ provides the baseline for unmodified models,
    // and the background queue fills in only the dirty models' channel ranges.
    if (!_renderedData || !_renderedData->isValid()) {
        int32_t totalChannels = computeRequiredChannels();
        if (_outputProvider) {
            int32_t outputChannels = _outputProvider->getTotalChannels();
            if (outputChannels > totalChannels) totalChannels = outputChannels;
        }
        if (totalChannels <= 0) return;

        _renderedData = std::make_unique<NativeSequenceData>(
            static_cast<uint32_t>(totalChannels),
            static_cast<uint32_t>(numFrames),
            static_cast<uint32_t>(frameTimeMS));
        printf("[RDBG] ensureBackgroundRenderQueue: allocated _renderedData (%d channels, %d frames)\n",
               totalChannels, numFrames);
    }

    // Ensure model channel map is built (needed for channel ranges)
    if (_modelChannelMap.empty()) {
        if (_controllerStartChannels.empty()) buildControllerChannelMap();
        if (_modelTotalChannels.empty()) buildModelTotalChannelsMap();
        buildModelChannelMap();
    }

    // Ensure _modelChannelRanges is populated (needed for FSEQ overlay)
    {
        std::lock_guard<std::mutex> lock(_dirtyMutex);
        if (_modelChannelRanges.empty() && !_modelChannelMap.empty()) {
            for (const auto& [name, chInfo] : _modelChannelMap) {
                uint32_t chCount = chInfo.nodeCount * chInfo.chansPerNode;
                if (chCount > 0) {
                    _modelChannelRanges[name] = {chInfo.absStartChannel, chCount};
                }
            }
            printf("[RDBG] ensureBackgroundRenderQueue: populated %zu model channel ranges\n",
                   _modelChannelRanges.size());
        }
    }

    // Create a dedicated coordinator for background rendering.
    double duration = static_cast<double>(numFrames) * frameTimeMS / 1000.0;
    _bgContext = std::make_unique<RenderEngineContext>(frameTimeMS, duration, _audioProvider);
    _bgCoordinator = std::make_unique<NativeRenderCoordinator>(
        _effectProvider, _modelProvider, _bgContext.get());

    // Resolve start channels for the background coordinator
    if (_controllerStartChannels.empty()) {
        buildControllerChannelMap();
    }
    if (_modelTotalChannels.empty()) {
        buildModelTotalChannelsMap();
    }
    std::unordered_map<std::string, uint32_t> resolvedChannels;
    {
        auto modelNames = _modelProvider->getModelNames();
        for (const auto& name : modelNames) {
            auto attrs = _modelProvider->getModelAttributes(name);
            auto displayAs = attrs.find("DisplayAs");
            if (displayAs != attrs.end() && displayAs->second == "ModelGroup") continue;
            auto scIt = attrs.find("StartChannel");
            if (scIt != attrs.end() && !scIt->second.empty()) {
                resolvedChannels[name] = resolveStartChannel(scIt->second);
            }
        }
    }
    _bgCoordinator->setResolvedStartChannels(resolvedChannels);

    _bgRenderQueue = std::make_unique<BackgroundRenderQueue>(
        _bgCoordinator.get(), _renderedData.get());

    printf("[RDBG] ensureBackgroundRenderQueue: queue created with %zu resolved channels\n",
           resolvedChannels.size());
}

// --- EffectEngineListener callbacks ---

std::string RenderEngine::resolveModelNameFromEvent(const EffectEvent& event)
{
    // If the event has a model name, use it directly
    if (!event.modelName.empty()) return event.modelName;

    // Otherwise try to look up the element that contains this effect
    if (_effectProvider && event.effectId >= 0) {
        // Fast path: use getEffect() to look up by ID directly
        EffectInstanceInfo effInfo;
        if (_effectProvider->getEffect(static_cast<int64_t>(event.effectId), effInfo)) {
            // Got the effect — now get its parent element name
            ElementInfo elemInfo;
            if (_effectProvider->getElement(effInfo.elementIndex, elemInfo)) {
                return elemInfo.name;
            }
        }
    }
    return {};
}

void RenderEngine::onEffectCreated(const EffectEvent& event)
{
    std::string modelName = resolveModelNameFromEvent(event);
    if (!modelName.empty()) {
        invalidateModelAndGroup(modelName);
    }
}

void RenderEngine::onEffectDeleted(const EffectEvent& event)
{
    std::string modelName = resolveModelNameFromEvent(event);
    if (!modelName.empty()) {
        invalidateModelAndGroup(modelName);
    }
}

void RenderEngine::onEffectMoved(const EffectEvent& event)
{
    std::string modelName = resolveModelNameFromEvent(event);
    if (!modelName.empty()) {
        invalidateModelAndGroup(modelName);
    }
}

void RenderEngine::onEffectSettingChanged(const EffectEvent& event)
{
    std::string modelName = resolveModelNameFromEvent(event);
    printf("[RDBG] onEffectSettingChanged: effectId=%d key='%s' → model='%s'\n",
           event.effectId, event.paramKey.c_str(), modelName.c_str());
    if (!modelName.empty()) {
        invalidateModelAndGroup(modelName);
    }
}

void RenderEngine::onEffectPaletteChanged(const EffectEvent& event)
{
    std::string modelName = resolveModelNameFromEvent(event);
    printf("[RDBG] onEffectPaletteChanged: effectId=%d → model='%s'\n",
           event.effectId, modelName.c_str());
    if (!modelName.empty()) {
        invalidateModelAndGroup(modelName);
    }
}

void RenderEngine::onEffectTypeChanged(const EffectEvent& event)
{
    std::string modelName = resolveModelNameFromEvent(event);
    if (!modelName.empty()) {
        invalidateModelAndGroup(modelName);
    }
}

bool RenderEngine::getGPUAvailable() const { return false; }
bool RenderEngine::getGPUEnabled() const { return false; }
void RenderEngine::setGPUEnabled(bool enabled) {}
void RenderEngine::setRenderMode(RenderMode mode) { _renderMode.store(mode); }
RenderMode RenderEngine::getRenderMode() const { return _renderMode.load(); }
bool RenderEngine::isRendering() const {
    return _renderInProgress.load(std::memory_order_acquire)
        || (_coordinator && _coordinator->isRendering());
}

RenderStatus RenderEngine::getRenderStatus() const {
    RenderStatus status;
    status.isRendering = isRendering();
    std::shared_ptr<FSEQFile> localFseq;
    if (_fseqLoaded) {
        std::lock_guard<std::mutex> lock(_fseqMutex);
        localFseq = _fseqFile;
    }
    if (localFseq) {
        status.framesTotal = static_cast<int>(localFseq->getNumFrames());
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
    if (_fseqLoaded) {
        std::lock_guard<std::mutex> lock(_fseqMutex);
        if (_fseqFile) return _fseqFile->getStepTime();
    }
    if (_provider) {
        int ft = _provider->getFrameTimeMS();
        if (ft > 0) return ft;
    }
    return 50;
}

int RenderEngine::getNumFrames() const
{
    if (_fseqLoaded) {
        std::lock_guard<std::mutex> lock(_fseqMutex);
        if (_fseqFile) return static_cast<int>(_fseqFile->getNumFrames());
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
