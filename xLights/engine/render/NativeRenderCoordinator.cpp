/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "NativeRenderCoordinator.h"
#include "NativeSequenceData.h"
#include "NativeRenderBuffer.h"
#include "NativeDrawingContext.h"
#include "IRenderContext.h"
#include "../interfaces/IAudioProvider.h"
#include "../interfaces/IEffectProvider.h"
#include "../interfaces/IModelProvider.h"
#include "../ModelEngine.h"

#include "NativeImageLoader.h"
#include "NativeVideoReader.h"

#include <Box2D/Box2D.h>

#include "../../ValueCurve.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <functional>
#include <list>
#include <set>
#include <unordered_map>
#include <regex>
#include <sstream>
#include <thread>

namespace xlEngine {

// =========================================================================
// Static helpers (needed early for job creation and group lookups)
// =========================================================================

// Parse comma-separated member list and trim whitespace.
static std::vector<std::string> parseMemberList(const std::string& members) {
    std::vector<std::string> result;
    size_t pos = 0;
    while (pos < members.size()) {
        size_t comma = members.find(',', pos);
        if (comma == std::string::npos) comma = members.size();
        std::string member = members.substr(pos, comma - pos);
        while (!member.empty() && member.front() == ' ') member.erase(member.begin());
        while (!member.empty() && member.back() == ' ') member.pop_back();
        if (!member.empty()) result.push_back(member);
        pos = comma + 1;
    }
    return result;
}

// Returns the set of parent node indices that belong to a submodel,
// based on the submodel's strand range attributes (line0, line1, ...).
// Used for computing pixel masks when a group contains submodel refs.
static std::set<int> getSubmodelNodeIndices(
    int parentNodeCount,
    const std::map<std::string, std::string>& subAttrs)
{
    std::set<int> indices;
    auto typeIt = subAttrs.find("type");
    if (typeIt != subAttrs.end() && typeIt->second == "subbuffer") {
        for (int i = 0; i < parentNodeCount; i++) indices.insert(i);
        return indices;
    }

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

            size_t dash = token.find('-');
            int rangeStart, rangeEnd;
            if (dash != std::string::npos) {
                rangeStart = std::atoi(token.substr(0, dash).c_str()) - 1;
                rangeEnd = std::atoi(token.substr(dash + 1).c_str()) - 1;
                if (rangeStart < 0) rangeStart = 0;
                if (rangeEnd < rangeStart) std::swap(rangeStart, rangeEnd);
            } else {
                rangeStart = rangeEnd = std::atoi(token.c_str()) - 1;
                if (rangeStart < 0) continue;
            }
            for (int idx = rangeStart; idx <= rangeEnd; idx++) {
                if (idx >= 0 && idx < parentNodeCount) indices.insert(idx);
            }
        }
    }
    return indices;
}

// Recursively collect submodel refs matching a given parent model name
// from a group's member list, including nested groups.
// e.g. If group has members "A/Sub1, NestedGroup" and NestedGroup has "A/Sub2",
// this collects both "A/Sub1" and "A/Sub2" for parentModelName="A".
static void collectSubmodelRefsRecursive(
    const std::string& parentModelName,
    const std::string& membersStr,
    IModelProvider* modelProvider,
    std::vector<std::string>& subRefs,
    bool& directMatch,
    std::set<std::string>& visited)
{
    if (directMatch) return; // short-circuit if parent is already a direct member

    auto memberList = parseMemberList(membersStr);
    for (const auto& member : memberList) {
        if (directMatch) return;

        // Direct match: the parent model itself is a member
        if (member == parentModelName) {
            directMatch = true;
            return;
        }

        // Submodel ref match: "ParentModel/SubName"
        size_t sl = member.find('/');
        if (sl != std::string::npos && member.substr(0, sl) == parentModelName) {
            subRefs.push_back(member);
            continue;
        }

        // Recurse into nested groups (with cycle protection)
        if (visited.count(member)) continue;
        auto memberAttrs = modelProvider->getModelAttributes(member);
        auto modelsIt = memberAttrs.find("models");
        if (modelsIt != memberAttrs.end() && !modelsIt->second.empty()) {
            visited.insert(member);
            collectSubmodelRefsRecursive(parentModelName, modelsIt->second,
                                         modelProvider, subRefs, directMatch, visited);
        }
    }
}

// =========================================================================
// Layer settings parsing — extract B_ prefix keys from effect settings
// and populate NativeLayerInfo. Mirrors legacy SetLayerSettings().
// =========================================================================

static int getSettingsInt(const std::map<std::string, std::string>& settings,
                          const std::string& key, int defaultVal) {
    auto it = settings.find(key);
    if (it == settings.end() || it->second.empty()) return defaultVal;
    try { return std::stoi(it->second); }
    catch (...) { return defaultVal; }
}

static double getSettingsDouble(const std::map<std::string, std::string>& settings,
                                const std::string& key, double defaultVal) {
    auto it = settings.find(key);
    if (it == settings.end() || it->second.empty()) return defaultVal;
    try { return std::stod(it->second); }
    catch (...) { return defaultVal; }
}

static bool getSettingsBool(const std::map<std::string, std::string>& settings,
                            const std::string& key, bool defaultVal = false) {
    auto it = settings.find(key);
    if (it == settings.end()) return defaultVal;
    return it->second == "1" || it->second == "true" || it->second == "TRUE";
}

static std::string getSettingsStr(const std::map<std::string, std::string>& settings,
                                  const std::string& key, const std::string& defaultVal = "") {
    auto it = settings.find(key);
    if (it == settings.end()) return defaultVal;
    return it->second;
}

static NativeMixType parseMixType(const std::string& name) {
    // Map from display names (stored in B_CHOICE_LayerMethod) to NativeMixType.
    // Matches the MixTypesMap in legacy PixelBuffer.cpp.
    static const std::map<std::string, NativeMixType> map = {
        {"Normal",            NativeMixType::Mix_Normal},
        {"Effect 1",          NativeMixType::Mix_Effect1},
        {"Effect 2",          NativeMixType::Mix_Effect2},
        {"1 is Mask",         NativeMixType::Mix_Mask1},
        {"2 is Mask",         NativeMixType::Mix_Mask2},
        {"1 is Unmask",       NativeMixType::Mix_Unmask1},
        {"2 is Unmask",       NativeMixType::Mix_Unmask2},
        {"1 is True Unmask",  NativeMixType::Mix_TrueUnmask1},
        {"2 is True Unmask",  NativeMixType::Mix_TrueUnmask2},
        {"1 reveals 2",       NativeMixType::Mix_1_reveals_2},
        {"2 reveals 1",       NativeMixType::Mix_2_reveals_1},
        {"Shadow 1 on 2",     NativeMixType::Mix_Shadow_1on2},
        {"Shadow 2 on 1",     NativeMixType::Mix_Shadow_2on1},
        {"Layered",           NativeMixType::Mix_Layered},
        {"Highlight",         NativeMixType::Mix_Highlight},
        {"Highlight Vibrant", NativeMixType::Mix_Highlight_Vibrant},
        {"Additive",          NativeMixType::Mix_Additive},
        {"Subtractive",       NativeMixType::Mix_Subtractive},
        {"Brightness",        NativeMixType::Mix_AsBrightness},
        {"Average",           NativeMixType::Mix_Average},
        {"Bottom-Top",        NativeMixType::Mix_BottomTop},
        {"Left-Right",        NativeMixType::Mix_LeftRight},
        {"Max",               NativeMixType::Mix_Max},
        {"Min",               NativeMixType::Mix_Min},
    };
    auto it = map.find(name);
    return (it != map.end()) ? it->second : NativeMixType::Mix_Normal;
}

// Parse layer settings from the effect's settings map (B_ prefixed keys)
// and populate a NativeLayerInfo struct. Matches legacy SetLayerSettings().
static NativeLayerInfo parseLayerSettings(
    const std::map<std::string, std::string>& settings, int frameTimeMS)
{
    NativeLayerInfo info;

    // Persistent (overlay background)
    info.persistent = getSettingsBool(settings, "B_CHECKBOX_OverlayBkg");

    // Fade in/out (seconds → frames)
    double fadeInSec = getSettingsDouble(settings, "B_TEXTCTRL_Fadein", 0.0);
    double fadeOutSec = getSettingsDouble(settings, "B_TEXTCTRL_Fadeout", 0.0);
    info.fadeInSteps = (frameTimeMS > 0)
        ? static_cast<float>((int)(fadeInSec * 1000) / frameTimeMS) : 0.0f;
    info.fadeOutSteps = (frameTimeMS > 0)
        ? static_cast<float>((int)(fadeOutSec * 1000) / frameTimeMS) : 0.0f;

    // Blur
    info.blur = getSettingsInt(settings, "B_SLIDER_Blur", 1);

    // Sparkle
    info.sparkle_count = getSettingsInt(settings, "B_SLIDER_SparkleFrequency", 0);
    info.use_music_sparkle_count = getSettingsBool(settings, "B_CHECKBOX_MusicSparkles");

    // Sparkle color
    std::string sparkColStr = getSettingsStr(settings, "B_COLOURPICKERCTRL_SparklesColour", "#FFFFFF");
    if (!sparkColStr.empty()) {
        info.sparklesColour.SetFromString(sparkColStr);
    }

    // Brightness / contrast
    info.brightness = static_cast<float>(getSettingsInt(settings, "B_SLIDER_Brightness", 100));
    info.contrast = getSettingsInt(settings, "B_SLIDER_Contrast", 0);

    // HSV adjustments
    info.hueAdjust = static_cast<float>(getSettingsInt(settings, "B_SLIDER_Color_HueAdjust", 0));
    info.saturationAdjust = static_cast<float>(getSettingsInt(settings, "B_SLIDER_Color_SaturationAdjust", 0));
    info.valueAdjust = static_cast<float>(getSettingsInt(settings, "B_SLIDER_Color_ValueAdjust", 0));

    // Mix type
    std::string mixName = getSettingsStr(settings, "B_CHOICE_LayerMethod", "Normal");
    info.mixType = parseMixType(mixName);

    // Mix threshold and morph
    info.mixThreshold = static_cast<float>(
        getSettingsInt(settings, "B_SLIDER_EffectLayerMix", 0)) / 100.0f;
    info.effectMixVary = getSettingsBool(settings, "B_CHECKBOX_LayerMorph");

    // Canvas mode
    info.canvas = getSettingsBool(settings, "B_CHECKBOX_Canvas");

    // Chroma key
    info.isChromaKey = getSettingsBool(settings, "B_CHECKBOX_Chroma");
    info.chromaSensitivity = getSettingsInt(settings, "B_SLIDER_ChromaSensitivity", 1);
    std::string chromaColStr = getSettingsStr(settings, "B_COLOURPICKERCTRL_ChromaColour", "");
    if (!chromaColStr.empty()) {
        info.chromaKeyColour.SetFromString(chromaColStr);
    }

    // Transition types
    std::string inTransStr = getSettingsStr(settings, "B_CHOICE_In_Transition_Type", "Fade");
    std::string outTransStr = getSettingsStr(settings, "B_CHOICE_Out_Transition_Type", "Fade");
    // Store as simple integer codes: 0=Fade (only Fade is fully supported for now)
    info.inTransitionType = (inTransStr == "Fade") ? 0 : 1;
    info.outTransitionType = (outTransStr == "Fade") ? 0 : 1;
    info.inTransitionAdjust = static_cast<float>(
        getSettingsInt(settings, "B_SLIDER_In_Transition_Adjust", 0));
    info.outTransitionAdjust = static_cast<float>(
        getSettingsInt(settings, "B_SLIDER_Out_Transition_Adjust", 0));
    info.inTransitionReverse = getSettingsBool(settings, "B_CHECKBOX_In_Transition_Reverse");
    info.outTransitionReverse = getSettingsBool(settings, "B_CHECKBOX_Out_Transition_Reverse");

    return info;
}

// =========================================================================
// Construction / destruction
// =========================================================================

NativeRenderCoordinator::NativeRenderCoordinator(
    IEffectProvider* effectProvider,
    IModelProvider* modelProvider,
    IRenderContext* context)
    : _effectProvider(effectProvider)
    , _modelProvider(modelProvider)
    , _context(context)
{
}

NativeRenderCoordinator::~NativeRenderCoordinator() {
    abort();
}

void NativeRenderCoordinator::setListener(RenderCoordinatorListener* listener) {
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listener = listener;
}

void NativeRenderCoordinator::setResolvedStartChannels(
    const std::unordered_map<std::string, uint32_t>& channels) {
    _resolvedStartChannels = channels;
}

// =========================================================================
// Public render API
// =========================================================================

bool NativeRenderCoordinator::renderAll(NativeSequenceData& output) {
    if (!_context) return false;
    double duration = _context->getSequenceDuration();
    int endMS = static_cast<int>(duration * 1000.0);
    return renderRange(0, endMS, output);
}

bool NativeRenderCoordinator::renderRange(
    int startMS, int endMS, NativeSequenceData& output)
{
    if (!_effectProvider || !_modelProvider || !_context) return false;

    // Ensure only one render at a time
    bool expected = false;
    if (!_rendering.compare_exchange_strong(expected, true)) return false;

    _abort.store(false);
    _progress.store(0.0f);

    int frameTimeMS = _context->getFrameTimeMS();
    if (frameTimeMS <= 0) frameTimeMS = 50;

    auto jobs = buildModelJobs();
    if (jobs.empty()) {
        _rendering.store(false);
        std::lock_guard<std::mutex> lock(_listenerMutex);
        if (_listener) _listener->onRenderComplete(false);
        return true;
    }

    // Build render dependency tiers. Jobs within a tier have no channel
    // overlap and can run in parallel. Tiers execute sequentially so that
    // models sharing channels (groups + members, overlapping ranges) render
    // in deterministic order matching legacy element precedence.
    auto tiers = buildRenderTiers(jobs);

    int totalModels = static_cast<int>(jobs.size());
    std::atomic<int> modelsComplete{0};

    unsigned int maxThreads = std::max(1u, std::thread::hardware_concurrency());

    for (const auto& tierIndices : tiers) {
        if (_abort.load()) break;

        // Dispatch all jobs in this tier in parallel
        unsigned int numThreads = std::min(
            static_cast<unsigned int>(tierIndices.size()), maxThreads);

        std::atomic<size_t> nextInTier{0};
        std::vector<std::thread> threads;
        threads.reserve(numThreads);

        for (unsigned int t = 0; t < numThreads; ++t) {
            threads.emplace_back([&]() {
                size_t localIdx;
                while ((localIdx = nextInTier.fetch_add(1)) < tierIndices.size()) {
                    if (_abort.load()) return;

                    size_t jobIdx = tierIndices[localIdx];
                    renderModel(jobs[jobIdx], startMS, endMS, output);

                    int completed = modelsComplete.fetch_add(1) + 1;
                    float pct = static_cast<float>(completed) /
                                static_cast<float>(totalModels);
                    _progress.store(pct);
                    std::lock_guard<std::mutex> lock(_listenerMutex);
                    if (_listener) {
                        _listener->onRenderProgress(pct * 100.0f, completed, totalModels);
                    }
                }
            });
        }

        for (auto& t : threads) t.join();
    }

    bool wasCancelled = _abort.load();
    _rendering.store(false);

    {
        std::lock_guard<std::mutex> lock(_listenerMutex);
        if (_listener) _listener->onRenderComplete(wasCancelled);
    }

    return !wasCancelled;
}

RenderedFrame NativeRenderCoordinator::renderModelFrame(
    const std::string& modelName, int timeMS)
{
    RenderedFrame result;
    result.modelName = modelName;
    result.timeMS = timeMS;

    if (!_effectProvider || !_modelProvider || !_context) return result;

    ModelGeometry geom = extractGeometry(modelName);
    if (geom.bufferWi <= 0 || geom.bufferHt <= 0) return result;

    // Always populate dimensions so callers can create black buffers for no-effect models
    result.width = geom.bufferWi;
    result.height = geom.bufferHt;

    size_t ownElemIdx = _effectProvider->getElementIndex(modelName);

    bool hasOwnEffects = false;
    size_t ownLayerCount = 0;
    if (ownElemIdx != SIZE_MAX) {
        ElementInfo info;
        if (_effectProvider->getElement(ownElemIdx, info)) {
            hasOwnEffects = (info.effectCount > 0);
            ownLayerCount = info.effectLayerCount;
        }
    }

    // Always check for parent group with effects
    size_t groupIdx = SIZE_MAX;
    size_t groupLayerCount = 0;
    {
        size_t gIdx = findParentGroupElement(modelName);
        if (gIdx != SIZE_MAX) {
            ElementInfo groupInfo;
            if (_effectProvider->getElement(gIdx, groupInfo)) {
                groupIdx = gIdx;
                groupLayerCount = groupInfo.effectLayerCount;
            }
        }
    }

    if (!hasOwnEffects && groupIdx == SIZE_MAX) return result;

    size_t elemIdx;
    size_t totalLayerCount;
    if (groupIdx != SIZE_MAX && hasOwnEffects) {
        elemIdx = ownElemIdx;
        totalLayerCount = groupLayerCount + ownLayerCount;
    } else if (groupIdx != SIZE_MAX) {
        elemIdx = groupIdx;
        totalLayerCount = groupLayerCount;
    } else {
        elemIdx = ownElemIdx;
        totalLayerCount = ownLayerCount;
    }
    if (totalLayerCount == 0) totalLayerCount = 1;

    int w = geom.bufferWi;
    int h = geom.bufferHt;

    ModelJob job;
    job.elementIndex = elemIdx;
    job.layerCount = totalLayerCount;
    job.groupElementIndex = groupIdx;
    job.groupLayerCount = groupLayerCount;
    job.pixelBuffer = std::make_unique<NativePixelBuffer>(
        _context, w, h, static_cast<int>(totalLayerCount), geom.nodes);
    job.geometry = std::move(geom);

    renderModelAtTime(job, timeMS);

    // Bulk copy RGBA pixel data from the blended output buffer
    result.width = w;
    result.height = h;
    const uint8_t* pixelData = job.pixelBuffer->getBlendedPixelData();
    size_t dataSize = job.pixelBuffer->getBlendedPixelDataSize();
    if (pixelData && dataSize > 0) {
        result.pixels.resize(dataSize);
        std::memcpy(result.pixels.data(), pixelData, dataSize);
    }

    return result;
}

RenderedFrame NativeRenderCoordinator::renderModelFrameStateful(
    const std::string& modelName, int timeMS)
{
    RenderedFrame result;
    result.modelName = modelName;
    result.timeMS = timeMS;

    if (!_effectProvider || !_modelProvider || !_context) return result;

    std::lock_guard<std::recursive_mutex> lock(_stateMutex);

    // Fast path: skip models already known to have no effects
    if (_skippedModels.count(modelName)) {
        static std::set<std::string> sSkipLogged;
        if (sSkipLogged.insert(modelName).second)
            printf("[SUBDBG] renderModelFrameStateful('%s'): SKIPPED (in _skippedModels)\n", modelName.c_str());
        return result;
    }

    // Look up or create persistent ModelJob for this model
    auto it = _persistentJobs.find(modelName);
    if (it == _persistentJobs.end()) {
        ModelGeometry geom = extractGeometry(modelName);
        if (geom.bufferWi <= 0 || geom.bufferHt <= 0) {
            printf("[SUBDBG] renderModelFrameStateful('%s'): SKIPPED (bad geometry %dx%d)\n",
                   modelName.c_str(), geom.bufferWi, geom.bufferHt);
            _skippedModels.insert(modelName);
            return result;
        }

        size_t ownElemIdx = _effectProvider->getElementIndex(modelName);

        bool hasOwnEffects = false;
        size_t ownLayerCount = 0;
        if (ownElemIdx != SIZE_MAX) {
            ElementInfo info;
            if (_effectProvider->getElement(ownElemIdx, info)) {
                hasOwnEffects = (info.effectCount > 0);
                ownLayerCount = info.effectLayerCount;
            }
        }

        // Always check for parent group with effects (group effects cascade
        // to ALL members, even those with their own effects).
        size_t groupIdx = SIZE_MAX;
        size_t groupLayerCount = 0;
        std::string matchedGroupName;
        {
            size_t gIdx = findParentGroupElement(modelName);
            if (gIdx != SIZE_MAX) {
                ElementInfo groupInfo;
                if (_effectProvider->getElement(gIdx, groupInfo)) {
                    groupIdx = gIdx;
                    groupLayerCount = groupInfo.effectLayerCount;
                    matchedGroupName = groupInfo.name;
                }
            }
        }

        // Need at least one source of effects
        if (!hasOwnEffects && groupIdx == SIZE_MAX) {
            _skippedModels.insert(modelName);
            return result;
        }

        // Compute total layers: group layers + model's own layers
        size_t elemIdx; // primary element for the job
        size_t totalLayerCount;
        if (groupIdx != SIZE_MAX && hasOwnEffects) {
            elemIdx = ownElemIdx;
            totalLayerCount = groupLayerCount + ownLayerCount;
        } else if (groupIdx != SIZE_MAX) {
            elemIdx = groupIdx;
            totalLayerCount = groupLayerCount;
        } else {
            elemIdx = ownElemIdx;
            totalLayerCount = ownLayerCount;
        }
        if (totalLayerCount == 0) totalLayerCount = 1;

        int w = geom.bufferWi;
        int h = geom.bufferHt;

        ModelJob job;
        job.elementIndex = elemIdx;
        job.layerCount = totalLayerCount;
        job.groupElementIndex = groupIdx;
        job.groupLayerCount = groupLayerCount;
        job.pixelBuffer = std::make_unique<NativePixelBuffer>(
            _context, w, h, static_cast<int>(totalLayerCount), geom.nodes);
        job.geometry = std::move(geom);

        // Compute submodel mask for physical models matched through submodel refs.
        // When a group contains "ParentModel/Sub" (not "ParentModel" directly),
        // only the submodel's nodes should be lit in the house preview.
        // Recurses into nested groups to find all submodel refs for this parent.
        if (!matchedGroupName.empty() && modelName.find('/') == std::string::npos) {
            auto groupAttrs = _modelProvider->getModelAttributes(matchedGroupName);
            auto membersIt = groupAttrs.find("models");
            if (membersIt != groupAttrs.end()) {
                bool directMatch = false;
                std::vector<std::string> subRefs;
                std::set<std::string> visited;
                visited.insert(matchedGroupName);
                collectSubmodelRefsRecursive(modelName, membersIt->second,
                                             _modelProvider, subRefs, directMatch, visited);

                if (!directMatch && !subRefs.empty()) {
                    auto parentAttrs = _modelProvider->getModelAttributes(modelName);
                    auto allParentNodes = generateNodesFromAttributes(parentAttrs);
                    std::set<std::pair<int,int>> validPos;
                    for (const auto& ref : subRefs) {
                        size_t sl = ref.find('/');
                        std::string subName = ref.substr(sl + 1);
                        auto subAttrs = _modelProvider->getSubmodelAttributes(modelName, subName);
                        if (!subAttrs.empty()) {
                            auto nodeIndices = getSubmodelNodeIndices(
                                static_cast<int>(allParentNodes.size()), subAttrs);
                            for (int idx : nodeIndices) {
                                validPos.insert({allParentNodes[idx].bufX,
                                                 allParentNodes[idx].bufY});
                            }
                        }
                    }
                    if (!validPos.empty()) {
                        job.hasSubmodelMask = true;
                        job.submodelMaskPositions = validPos;
                        job.pixelBuffer->setSubmodelMask(validPos);
                        printf("[GRP] Submodel mask for '%s': %zu valid pixel positions from %zu refs\n",
                               modelName.c_str(), job.submodelMaskPositions.size(), subRefs.size());
                    }
                }
            }
        }

        auto [inserted, _] = _persistentJobs.emplace(modelName, std::move(job));
        it = inserted;
    }

    ModelJob& job = it->second;
    int w = job.geometry.bufferWi;
    int h = job.geometry.bufferHt;

    result.width = w;
    result.height = h;

    renderModelAtTime(job, timeMS);

    // Bulk copy RGBA pixel data from the blended output buffer.
    // xlColor is {red, green, blue, alpha} = 4 bytes in RGBA order,
    // matching the result pixel format exactly. memcpy is significantly
    // faster than per-pixel getBlendedPixel() calls.
    const uint8_t* pixelData = job.pixelBuffer->getBlendedPixelData();
    size_t dataSize = job.pixelBuffer->getBlendedPixelDataSize();
    if (pixelData && dataSize > 0) {
        result.pixels.resize(dataSize);
        std::memcpy(result.pixels.data(), pixelData, dataSize);

        // Count non-black pixels before mask (once per model)
        {
            static std::set<std::string> sPixDbg;
            if (sPixDbg.insert(modelName).second) {
                int nonBlack = 0;
                for (size_t px = 0; px < dataSize; px += 4) {
                    if (result.pixels[px] || result.pixels[px+1] || result.pixels[px+2])
                        nonBlack++;
                }
                printf("[SUBDBG] stateful '%s': %dx%d, %d non-black pixels BEFORE mask, hasMask=%d maskSize=%zu\n",
                       modelName.c_str(), w, h, nonBlack,
                       job.hasSubmodelMask, job.submodelMaskPositions.size());
            }
        }

        // Apply submodel mask: zero out pixels that don't belong to any
        // matched submodel ref. This ensures the house preview only lights
        // the submodel's nodes, not the entire parent model.
        if (job.hasSubmodelMask && !job.submodelMaskPositions.empty()) {
            int kept = 0, zeroed = 0;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    if (job.submodelMaskPositions.find({x, y}) ==
                        job.submodelMaskPositions.end()) {
                        size_t pIdx = (static_cast<size_t>(y) * w + x) * 4;
                        if (pIdx + 3 < result.pixels.size()) {
                            result.pixels[pIdx] = 0;
                            result.pixels[pIdx + 1] = 0;
                            result.pixels[pIdx + 2] = 0;
                            result.pixels[pIdx + 3] = 0;
                            zeroed++;
                        }
                    } else {
                        kept++;
                    }
                }
            }
            static std::set<std::string> sMaskDbg;
            if (sMaskDbg.insert(modelName).second) {
                int nonBlackAfter = 0;
                for (size_t px = 0; px < result.pixels.size(); px += 4) {
                    if (result.pixels[px] || result.pixels[px+1] || result.pixels[px+2])
                        nonBlackAfter++;
                }
                printf("[SUBDBG] stateful '%s': AFTER mask: kept=%d zeroed=%d nonBlackAfter=%d\n",
                       modelName.c_str(), kept, zeroed, nonBlackAfter);
            }
        }
    } else {
        static std::set<std::string> sNoData;
        if (sNoData.insert(modelName).second)
            printf("[SUBDBG] stateful '%s': NO blended pixel data (pixelData=%p dataSize=%zu)\n",
                   modelName.c_str(), (void*)pixelData, dataSize);
    }

    return result;
}

void NativeRenderCoordinator::resetPersistentState() {
    std::lock_guard<std::recursive_mutex> lock(_stateMutex);
    _persistentJobs.clear();
    _skippedModels.clear();
}

void NativeRenderCoordinator::resetPersistentState(const std::string& modelName) {
    std::lock_guard<std::recursive_mutex> lock(_stateMutex);
    _persistentJobs.erase(modelName);
    _skippedModels.erase(modelName);
}

void NativeRenderCoordinator::abort() {
    _abort.store(true);
}

bool NativeRenderCoordinator::isRendering() const {
    return _rendering.load();
}

float NativeRenderCoordinator::getProgress() const {
    return _progress.load();
}

// =========================================================================
// Job building
// =========================================================================

std::vector<NativeRenderCoordinator::ModelJob>
NativeRenderCoordinator::buildModelJobs()
{
    std::vector<ModelJob> jobs;

    size_t elementCount = _effectProvider->getElementCount();
    for (size_t i = 0; i < elementCount; ++i) {
        ElementInfo info;
        if (!_effectProvider->getElement(i, info)) continue;

        // Only render top-level Model elements.
        // Submodels, strands, and timing elements are skipped.
        if (info.type != SequenceElementType::Model) continue;
        if (info.renderDisabled) continue;

        // Skip model groups — they don't have physical nodes.
        // Their effects cascade to member models via findParentGroupElement().
        if (_modelProvider) {
            auto attrs = _modelProvider->getModelAttributes(info.name);
            auto displayAs = attrs.find("DisplayAs");
            if (displayAs != attrs.end() && displayAs->second == "ModelGroup") continue;
        }

        ModelGeometry geom = extractGeometry(info.name);
        if (geom.bufferWi <= 0 || geom.bufferHt <= 0) continue;

        // Determine which elements provide effects for this model.
        // A model can have BOTH its own effects AND inherit effects from a
        // parent group. Group layers come first, then model's own layers.
        size_t ownElementIdx = i;
        size_t ownLayerCount = info.effectLayerCount;
        bool hasOwnEffects = (info.effectCount > 0);

        // Always check for parent group with effects (group effects cascade
        // to ALL members, even those with their own effects).
        size_t groupIdx = SIZE_MAX;
        size_t groupLayerCount = 0;
        std::string matchedGroupName;
        {
            size_t gIdx = findParentGroupElement(info.name);
            if (gIdx != SIZE_MAX) {
                ElementInfo groupInfo;
                if (_effectProvider->getElement(gIdx, groupInfo)) {
                    groupIdx = gIdx;
                    groupLayerCount = groupInfo.effectLayerCount;
                    matchedGroupName = groupInfo.name;
                }
            }
        }

        // Compute total layer count: group layers + model layers
        size_t effectElementIdx;
        size_t totalLayerCount;
        if (groupIdx != SIZE_MAX && hasOwnEffects) {
            // Both: group layers first, then model's own layers
            effectElementIdx = ownElementIdx; // primary element is the model's own
            totalLayerCount = groupLayerCount + ownLayerCount;
        } else if (groupIdx != SIZE_MAX) {
            // Group only (model has no own effects)
            effectElementIdx = groupIdx;
            totalLayerCount = groupLayerCount;
        } else {
            // Model only (no parent group)
            effectElementIdx = ownElementIdx;
            totalLayerCount = ownLayerCount;
        }

        if (totalLayerCount == 0) totalLayerCount = 1;

        ModelJob job;
        job.elementIndex = effectElementIdx;
        job.layerCount = totalLayerCount;
        job.groupElementIndex = groupIdx;
        job.groupLayerCount = groupLayerCount;
        job.pixelBuffer = std::make_unique<NativePixelBuffer>(
            _context, geom.bufferWi, geom.bufferHt,
            static_cast<int>(totalLayerCount), geom.nodes);

        // Compute submodel mask (same logic as renderModelFrameStateful).
        // Recurses into nested groups to find all submodel refs for this parent.
        if (!matchedGroupName.empty() && info.name.find('/') == std::string::npos) {
            auto groupAttrs = _modelProvider->getModelAttributes(matchedGroupName);
            auto membersIt = groupAttrs.find("models");
            if (membersIt != groupAttrs.end()) {
                bool directMatch = false;
                std::vector<std::string> subRefs;
                std::set<std::string> visited;
                visited.insert(matchedGroupName);
                collectSubmodelRefsRecursive(info.name, membersIt->second,
                                             _modelProvider, subRefs, directMatch, visited);

                if (!directMatch && !subRefs.empty()) {
                    auto parentAttrs = _modelProvider->getModelAttributes(info.name);
                    auto allParentNodes = generateNodesFromAttributes(parentAttrs);
                    std::set<std::pair<int,int>> validPos;
                    for (const auto& ref : subRefs) {
                        size_t sl = ref.find('/');
                        std::string subName = ref.substr(sl + 1);
                        auto subAttrs = _modelProvider->getSubmodelAttributes(info.name, subName);
                        if (!subAttrs.empty()) {
                            auto nodeIndices = getSubmodelNodeIndices(
                                static_cast<int>(allParentNodes.size()), subAttrs);
                            for (int idx : nodeIndices) {
                                validPos.insert({allParentNodes[idx].bufX,
                                                 allParentNodes[idx].bufY});
                            }
                        }
                    }
                    if (!validPos.empty()) {
                        job.hasSubmodelMask = true;
                        job.submodelMaskPositions = validPos;
                        job.pixelBuffer->setSubmodelMask(validPos);
                    }
                }
            }
        }

        job.geometry = std::move(geom);
        jobs.push_back(std::move(job));
    }

    return jobs;
}

// =========================================================================
// Render dependency ordering
// =========================================================================

std::vector<std::vector<size_t>>
NativeRenderCoordinator::buildRenderTiers(const std::vector<ModelJob>& jobs)
{
    if (jobs.empty()) return {};

    // Step 1: Compute merged channel ranges for each job.
    // Each job's channel range is [startChannel, startChannel + channelCount).
    // A job may also inherit channels from a parent group, which we detect
    // via the groupElementIndex field — all jobs sharing the same group
    // inherently overlap in the group's channel space.
    struct ChannelRange {
        uint32_t start = UINT32_MAX;
        uint32_t end = 0; // exclusive
    };

    std::vector<ChannelRange> ranges(jobs.size());
    for (size_t i = 0; i < jobs.size(); ++i) {
        const auto& geom = jobs[i].geometry;
        if (geom.nodes.empty()) continue;

        // Compute the actual channel range from node data (most accurate)
        uint32_t minCh = UINT32_MAX;
        uint32_t maxCh = 0;
        for (const auto& node : geom.nodes) {
            uint32_t nodeStart = node.actChannel;
            uint32_t nodeEnd = nodeStart + static_cast<uint32_t>(node.channelsPerNode);
            if (nodeStart < minCh) minCh = nodeStart;
            if (nodeEnd > maxCh) maxCh = nodeEnd;
        }
        ranges[i].start = minCh;
        ranges[i].end = maxCh;
    }

    // Step 2: Detect overlaps. Two jobs overlap if their channel ranges
    // intersect OR if they share the same parent group element.
    // Build an adjacency list of overlapping job pairs.
    std::vector<std::vector<size_t>> overlaps(jobs.size());
    for (size_t i = 0; i < jobs.size(); ++i) {
        for (size_t j = i + 1; j < jobs.size(); ++j) {
            bool hasOverlap = false;

            // Check channel range overlap
            if (ranges[i].start < ranges[j].end &&
                ranges[j].start < ranges[i].end) {
                hasOverlap = true;
            }

            // Check shared parent group (inherently overlapping)
            if (!hasOverlap &&
                jobs[i].groupElementIndex != SIZE_MAX &&
                jobs[i].groupElementIndex == jobs[j].groupElementIndex) {
                hasOverlap = true;
            }

            if (hasOverlap) {
                overlaps[i].push_back(j);
                overlaps[j].push_back(i);
            }
        }
    }

    // Step 3: Assign jobs to tiers using a greedy coloring approach.
    // Jobs with no overlaps go in tier 0. A job with overlaps goes in the
    // first tier where none of its overlapping jobs are already placed.
    // Element order is preserved within tiers (earlier elements render first
    // within a tier, matching legacy precedence from sequence element order).
    std::vector<int> tier(jobs.size(), -1);
    int maxTier = 0;

    for (size_t i = 0; i < jobs.size(); ++i) {
        if (overlaps[i].empty()) {
            // No overlaps — can go in tier 0
            tier[i] = 0;
            continue;
        }

        // Find the minimum tier not occupied by any already-assigned neighbor
        // that comes BEFORE this job in element order.
        // Jobs overlapping with earlier jobs must go in a later tier.
        int minTier = 0;
        for (size_t neighbor : overlaps[i]) {
            if (tier[neighbor] >= 0 && neighbor < i) {
                // This neighbor was assigned and comes before us — we must go after it
                if (tier[neighbor] >= minTier) {
                    minTier = tier[neighbor] + 1;
                }
            }
        }
        tier[i] = minTier;
        if (minTier > maxTier) maxTier = minTier;
    }

    // Step 4: Build the tier vectors
    std::vector<std::vector<size_t>> tiers(maxTier + 1);
    for (size_t i = 0; i < jobs.size(); ++i) {
        tiers[tier[i]].push_back(i);
    }

    // Log the tier structure for debugging
    if (tiers.size() > 1) {
        printf("[RENDER_ORDER] %zu jobs split into %zu tiers:\n",
               jobs.size(), tiers.size());
        for (size_t t = 0; t < tiers.size(); ++t) {
            printf("[RENDER_ORDER]   Tier %zu (%zu jobs):", t, tiers[t].size());
            for (size_t idx : tiers[t]) {
                printf(" %s[ch%u-%u]", jobs[idx].geometry.name.c_str(),
                       ranges[idx].start, ranges[idx].end);
            }
            printf("\n");
        }
    }

    return tiers;
}

// =========================================================================
// Model geometry extraction
// =========================================================================

ModelGeometry NativeRenderCoordinator::extractGeometry(
    const std::string& modelName)
{
    ModelGeometry geom;
    geom.name = modelName;

    auto attrs = _modelProvider->getModelAttributes(modelName);

    // Handle submodel references ("ParentModel/SubmodelName"):
    // use the parent model's attributes for geometry generation,
    // then filter to just the submodel's node subset.
    std::string parentName;
    std::string subName;
    if (attrs.empty()) {
        size_t slash = modelName.find('/');
        if (slash != std::string::npos) {
            parentName = modelName.substr(0, slash);
            subName = modelName.substr(slash + 1);
            attrs = _modelProvider->getModelAttributes(parentName);
        }
    }

    // Use the shared node generation function to get correct bufX/bufY
    auto nodeCoords = generateNodesFromAttributes(attrs);

    // If this is a submodel reference, filter nodes to just the submodel's strand ranges
    if (!subName.empty() && !nodeCoords.empty()) {
        auto subAttrs = _modelProvider->getSubmodelAttributes(parentName, subName);
        if (!subAttrs.empty()) {
            size_t before = nodeCoords.size();
            nodeCoords = filterNodesToSubmodel(nodeCoords, subAttrs);
            static std::set<std::string> sLogged;
            if (sLogged.insert(modelName).second) {
                printf("[GRP] extractGeometry('%s'): %zu→%zu nodes (subAttrs=%zu)\n",
                       modelName.c_str(), before, nodeCoords.size(), subAttrs.size());
            }
        } else {
            static std::set<std::string> sLogged;
            if (sLogged.insert(modelName).second) {
                printf("[GRP] extractGeometry('%s'): NO subAttrs for '%s'/'%s' — using all %zu nodes!\n",
                       modelName.c_str(), parentName.c_str(), subName.c_str(), nodeCoords.size());
            }
        }
    }

    if (nodeCoords.empty()) return geom;

    // Derive buffer dimensions from actual max bufX/bufY values
    int maxBufX = 0, maxBufY = 0;
    for (const auto& nc : nodeCoords) {
        if (nc.bufX > maxBufX) maxBufX = nc.bufX;
        if (nc.bufY > maxBufY) maxBufY = nc.bufY;
    }
    geom.bufferWi = maxBufX + 1;
    geom.bufferHt = maxBufY + 1;

    // Start channel: use pre-resolved value if available (handles complex formats
    // like #IP:univ:ch, !Controller:ch, >Model:offset), fall back to atoi for plain numbers.
    auto scAttrIt = attrs.find("StartChannel");
    std::string scAttrStr = (scAttrIt != attrs.end()) ? scAttrIt->second : "(none)";

    auto resolvedIt = _resolvedStartChannels.find(modelName);
    if (resolvedIt != _resolvedStartChannels.end()) {
        geom.startChannel = resolvedIt->second;
        printf("[CHANNEL_MAP] extractGeometry('%s'): startCh='%s' → resolved=%u (from pre-resolved map)\n",
               modelName.c_str(), scAttrStr.c_str(), geom.startChannel);
    } else {
        if (scAttrIt != attrs.end() && !scAttrIt->second.empty()) {
            int sc = std::atoi(scAttrIt->second.c_str());
            if (sc > 0) geom.startChannel = static_cast<uint32_t>(sc - 1);
        }
        printf("[CHANNEL_MAP] extractGeometry('%s'): startCh='%s' → atoi=%u (NO pre-resolved entry)\n",
               modelName.c_str(), scAttrStr.c_str(), geom.startChannel);
    }

    // Determine channels per node and color order from StringType attribute.
    // StringType formats: "RGB Nodes", "GRB Nodes", "RGBW Nodes", "WRGB Nodes",
    //                     "4 Channel RGBW", "4 Channel WRGB", "Single Color", etc.
    int chansPerNode = 3;
    int rOff = 0, gOff = 1, bOff = 2, wOff = 3;
    auto stIt = attrs.find("StringType");
    if (stIt != attrs.end()) {
        const std::string& st = stIt->second;
        if (st.find("4 Channel") != std::string::npos ||
            st.find("RGBW") != std::string::npos ||
            st.find("WRGB") != std::string::npos) {
            chansPerNode = 4;
        } else if (st.find("Single Color") != std::string::npos) {
            chansPerNode = 1;
        }

        // Parse color order from StringType
        if (chansPerNode >= 3 && st.size() >= 3) {
            std::string colorChars;
            int baseOffset = 0;
            if (st[0] == 'W' && st.size() >= 4 && st[1] >= 'A' && st[1] <= 'Z') {
                colorChars = st.substr(1, 3);
                baseOffset = 1;
                wOff = 0;
            } else if (st.compare(0, 10, "4 Channel ") == 0 && st.size() >= 14) {
                std::string suffix = st.substr(10);
                if (suffix[0] == 'W') {
                    colorChars = suffix.substr(1, 3);
                    baseOffset = 1;
                    wOff = 0;
                } else {
                    colorChars = suffix.substr(0, 3);
                    baseOffset = 0;
                    wOff = 3;
                }
            } else if (st[0] >= 'A' && st[0] <= 'Z') {
                colorChars = st.substr(0, 3);
                baseOffset = 0;
            }
            if (colorChars.size() == 3) {
                for (int ci = 0; ci < 3; ci++) {
                    if (colorChars[ci] == 'R') rOff = ci + baseOffset;
                    else if (colorChars[ci] == 'G') gOff = ci + baseOffset;
                    else if (colorChars[ci] == 'B') bOff = ci + baseOffset;
                }
            }
        }
    }

    geom.nodeCount = static_cast<uint32_t>(nodeCoords.size());
    geom.channelCount = geom.nodeCount * chansPerNode;

    // Build node info with correct bufX/bufY from the model-type-specific generation
    geom.nodes.resize(geom.nodeCount);
    for (uint32_t n = 0; n < geom.nodeCount; ++n) {
        NativeNodeInfo& node = geom.nodes[n];
        node.bufX = nodeCoords[n].bufX;
        node.bufY = nodeCoords[n].bufY;
        node.actChannel = geom.startChannel + n * chansPerNode;
        node.channelsPerNode = chansPerNode;
        // colorOrder maps output channel index -> source RGBA index.
        // For GRB: ch0=G(1), ch1=R(0), ch2=B(2) -> colorOrder = {1, 0, 2}
        node.colorOrder[rOff] = 0; // R source
        node.colorOrder[gOff] = 1; // G source
        node.colorOrder[bOff] = 2; // B source
        if (chansPerNode == 4) {
            node.colorOrder[wOff] = 3; // W source
        }
    }

    return geom;
}

// =========================================================================
// Group membership lookup
// =========================================================================

// Recursively check if modelName is contained in a group's member list,
// expanding nested groups and matching submodel parent models.
static bool isModelInGroup(const std::string& modelName,
                           const std::string& membersStr,
                           IModelProvider* modelProvider,
                           int depth = 0)
{
    if (depth > 10) return false; // prevent infinite recursion

    auto memberList = parseMemberList(membersStr);
    for (const auto& member : memberList) {
        // Direct match
        if (member == modelName) return true;

        // Submodel match: if member is "ParentModel/Sub" and we're looking for "ParentModel"
        // or if modelName is "ParentModel/Sub" and member is "ParentModel"
        size_t slash = member.find('/');
        if (slash != std::string::npos) {
            std::string parentPart = member.substr(0, slash);
            if (parentPart == modelName) return true;
        }
        slash = modelName.find('/');
        if (slash != std::string::npos) {
            std::string parentPart = modelName.substr(0, slash);
            if (member == parentPart) return true;
        }

        // Nested group: check if this member is a group and recurse
        auto memberAttrs = modelProvider->getModelAttributes(member);
        auto modelsIt = memberAttrs.find("models");
        if (modelsIt != memberAttrs.end() && !modelsIt->second.empty()) {
            if (isModelInGroup(modelName, modelsIt->second, modelProvider, depth + 1)) {
                return true;
            }
        }
    }
    return false;
}

size_t NativeRenderCoordinator::findParentGroupElement(
    const std::string& modelName)
{
    if (!_effectProvider || !_modelProvider) return SIZE_MAX;

    static const std::set<std::string> sMissingModels = {
        "Large Gift 1", "Flake Icicle 41", "Pixel Stake 50",
        "Pixel Stake 52", "Pixel Stake 54"
    };
    bool debugThis = sMissingModels.count(modelName) > 0;

    size_t elementCount = _effectProvider->getElementCount();
    int groupsWithEffects = 0;
    for (size_t i = 0; i < elementCount; ++i) {
        ElementInfo info;
        if (!_effectProvider->getElement(i, info)) continue;
        if (info.effectCount == 0) continue;

        // Check if this element is a group by looking for the "models" attribute
        auto attrs = _modelProvider->getModelAttributes(info.name);
        auto it = attrs.find("models");
        if (it == attrs.end() || it->second.empty()) continue;

        groupsWithEffects++;
        bool found = isModelInGroup(modelName, it->second, _modelProvider);
        if (debugThis) {
            static std::set<std::string> sLogged;
            std::string key = modelName + "|" + info.name;
            if (sLogged.insert(key).second) {
                printf("[FIND_GROUP] '%s': checking group '%s' (effects=%zu, members=%zu chars) → %s\n",
                       modelName.c_str(), info.name.c_str(), info.effectCount,
                       it->second.size(), found ? "MATCH" : "no");
            }
        }
        if (found) {
            return i;
        }
    }
    if (debugThis) {
        static std::set<std::string> sLogged2;
        if (sLogged2.insert(modelName).second) {
            printf("[FIND_GROUP] '%s': NO match found (checked %d groups with effects out of %zu elements)\n",
                   modelName.c_str(), groupsWithEffects, elementCount);
        }
    }
    return SIZE_MAX;
}

// =========================================================================
// Per-model rendering
// =========================================================================

void NativeRenderCoordinator::renderModel(
    ModelJob& job, int startMS, int endMS, NativeSequenceData& output)
{
    int frameTimeMS = _context->getFrameTimeMS();
    if (frameTimeMS <= 0) frameTimeMS = 50;

    for (int timeMS = startMS; timeMS < endMS; timeMS += frameTimeMS) {
        if (_abort.load()) return;

        int frameIndex = timeMS / frameTimeMS;

        renderModelAtTime(job, timeMS);
        writeModelOutput(job, frameIndex, output);

        {
            std::lock_guard<std::mutex> lock(_listenerMutex);
            if (_listener) {
                _listener->onModelFrameRendered(job.geometry.name, timeMS);
            }
        }
    }
}

void NativeRenderCoordinator::renderModelAtTime(ModelJob& job, int timeMS) {
    int frameTimeMS = _context->getFrameTimeMS();
    if (frameTimeMS <= 0) frameTimeMS = 50;
    int period = timeMS / frameTimeMS;

    // Don't call pixelBuffer->clear() unconditionally — persistent layers
    // need their previous frame data to survive. We'll clear each layer
    // individually below based on its settings.

    std::vector<bool> validLayers(job.layerCount, false);

    for (size_t layer = 0; layer < job.layerCount; ++layer) {
        NativeRenderBuffer& buf = job.pixelBuffer->getLayerBuffer(
            static_cast<int>(layer));

        // Determine which element and layer index to query.
        // Group layers come first (0..groupLayerCount-1), then model's own layers.
        size_t srcElementIdx;
        size_t srcLayerIdx;
        if (job.groupElementIndex != SIZE_MAX && layer < job.groupLayerCount) {
            srcElementIdx = job.groupElementIndex;
            srcLayerIdx = layer;
        } else {
            srcElementIdx = job.elementIndex;
            srcLayerIdx = (job.groupElementIndex != SIZE_MAX)
                          ? layer - job.groupLayerCount
                          : layer;
        }

        EffectInstanceInfo effectInfo;
        if (!_effectProvider->getEffectAtTime(
                srcElementIdx, srcLayerIdx, timeMS, effectInfo)) {
            // No effect on this layer at this time — clear it unless persistent.
            // (We can't know persistent without the effect, so default to clearing.)
            buf.Clear();
            continue;
        }

        // Parse and apply layer settings (B_ prefix keys) from the effect.
        // This populates mix type, brightness, contrast, sparkle, HSV adjust,
        // fade, blur, persistent, canvas, chroma key — matching legacy
        // SetLayerSettings() behavior.
        NativeLayerInfo layerInfo = parseLayerSettings(effectInfo.settings, frameTimeMS);
        job.pixelBuffer->setLayerSettings(static_cast<int>(layer), layerInfo);

        // Clear the layer buffer unless persistent (overlay background).
        // Persistent layers keep previous frame data so effects accumulate.
        if (!layerInfo.persistent) {
            buf.Clear();
        }

        // Configure render buffer timing state
        buf.SetFrameTimeInMs(frameTimeMS);
        buf.SetEffectDuration(effectInfo.startTimeMS, effectInfo.endTimeMS);
        buf.SetState(period, period == effectInfo.startTimeMS / frameTimeMS);
        buf.cur_model = job.geometry.name;

        // Set palette colors from the effect's palette map.
        xlColorVector colors;
        for (int ci = 1; ci <= 8; ++ci) {
            std::string checkKey = "C_CHECKBOX_Palette" + std::to_string(ci);
            auto cit = effectInfo.palette.find(checkKey);
            if (cit == effectInfo.palette.end() || cit->second != "1") continue;

            std::string key = "C_BUTTON_Palette" + std::to_string(ci);
            auto pit = effectInfo.palette.find(key);
            if (pit == effectInfo.palette.end() || pit->second.empty()) continue;

            const std::string& val = pit->second;
            if (val.size() >= 7 && val[0] == '#') {
                unsigned int hex = 0;
                if (std::sscanf(val.c_str() + 1, "%06x", &hex) == 1) {
                    colors.push_back(xlColor(
                        static_cast<uint8_t>((hex >> 16) & 0xFF),
                        static_cast<uint8_t>((hex >> 8) & 0xFF),
                        static_cast<uint8_t>(hex & 0xFF)));
                }
            }
        }
        if (colors.empty()) {
            colors.push_back(xlWHITE);
        }
        buf.SetPalette(colors);

        bool rendered = renderNativeEffect(effectInfo, buf);
        validLayers[layer] = rendered;
    }

    job.pixelBuffer->calcOutput(period, validLayers);
}

// =========================================================================
// Timing track helpers for Piano/Guitar/Arpeggio effects
// =========================================================================

size_t NativeRenderCoordinator::findTimingTrackElement(const std::string& trackName) {
    if (trackName.empty() || !_effectProvider) return SIZE_MAX;
    size_t count = _effectProvider->getElementCount();
    for (size_t i = 0; i < count; ++i) {
        ElementInfo info;
        if (!_effectProvider->getElement(i, info)) continue;
        if (info.type == SequenceElementType::Timing && info.name == trackName) {
            return i;
        }
    }
    return SIZE_MAX;
}

std::vector<EffectInstanceInfo> NativeRenderCoordinator::getTimingMarks(const std::string& trackName) {
    size_t elemIdx = findTimingTrackElement(trackName);
    if (elemIdx == SIZE_MAX) return {};
    return _effectProvider->getEffectsOnLayer(elemIdx, 0);
}

bool NativeRenderCoordinator::getTimingMarkAtTime(const std::string& trackName, int timeMS, EffectInstanceInfo& outMark) {
    size_t elemIdx = findTimingTrackElement(trackName);
    if (elemIdx == SIZE_MAX) return false;
    return _effectProvider->getEffectAtTime(elemIdx, 0, timeMS, outMark);
}

// =========================================================================
// Value Curve helpers for native effect rendering
// =========================================================================

// Check if a string value is a value curve definition
static bool isValueCurveString(const std::string& val) {
    return val.find("Active=TRUE") != std::string::npos &&
           val.find("Id=ValueCurve") != std::string::npos;
}

// Cache of parsed ValueCurve objects, keyed by serialized string.
// Avoids re-parsing the VC string on every frame.
static std::unordered_map<std::string, ValueCurve> sValueCurveCache;

static ValueCurve& getCachedValueCurve(const std::string& data,
                                        int minVal, int maxVal, int divisor) {
    auto cacheIt = sValueCurveCache.find(data);
    if (cacheIt != sValueCurveCache.end()) {
        return cacheIt->second;
    }
    ValueCurve& vc = sValueCurveCache[data];
    vc.SetDivisor(divisor);
    vc.SetLimits(minVal, maxVal);
    vc.Deserialise(data);
    printf("[VC] Parsed ValueCurve: type=%s, min=%d, max=%d, divisor=%d\n",
           vc.GetType().c_str(), minVal, maxVal, divisor);
    return vc;
}

// Read an int parameter with value curve support.
// Checks for value curve data in BOTH the VC key (E_VALUECURVE_*) and the slider key.
// offset = 0.0..1.0 position within the effect duration.
static int getSettingInt(const std::map<std::string, std::string>& settings,
                         const std::string& sliderKey, int defaultVal,
                         float offset, int startMS, int endMS,
                         int minVal = 0, int maxVal = 100, int divisor = 1) {
    // First check for a dedicated E_VALUECURVE_ key
    std::string vcKey = sliderKey;
    auto pos = vcKey.find("E_SLIDER_");
    if (pos != std::string::npos) {
        vcKey.replace(pos, 9, "E_VALUECURVE_");
    }

    // Check VC key first, then slider key for VC data
    for (const auto& key : {vcKey, sliderKey}) {
        auto it = settings.find(key);
        if (it != settings.end() && isValueCurveString(it->second)) {
            ValueCurve& vc = getCachedValueCurve(it->second, minVal, maxVal, divisor);
            if (vc.IsActive()) {
                return static_cast<int>(vc.GetOutputValueAt(offset, startMS, endMS));
            }
        }
    }

    // Fall back to plain numeric value
    auto it = settings.find(sliderKey);
    if (it != settings.end() && !it->second.empty()) {
        return std::atoi(it->second.c_str());
    }
    return defaultVal;
}

// Read a double parameter with value curve support.
static double getSettingDouble(const std::map<std::string, std::string>& settings,
                               const std::string& sliderKey, double defaultVal,
                               float offset, int startMS, int endMS,
                               int minVal = 0, int maxVal = 100, int divisor = 1) {
    // First check for a dedicated E_VALUECURVE_ key
    std::string vcKey = sliderKey;
    auto pos = vcKey.find("E_SLIDER_");
    if (pos != std::string::npos) {
        vcKey.replace(pos, 9, "E_VALUECURVE_");
    }

    // Check VC key first, then slider key for VC data
    for (const auto& key : {vcKey, sliderKey}) {
        auto it = settings.find(key);
        if (it != settings.end() && isValueCurveString(it->second)) {
            ValueCurve& vc = getCachedValueCurve(it->second, minVal, maxVal, divisor);
            if (vc.IsActive()) {
                return static_cast<double>(vc.GetOutputValueAt(offset, startMS, endMS)) / divisor;
            }
        }
    }

    // Fall back to plain numeric value
    auto it = settings.find(sliderKey);
    if (it != settings.end() && !it->second.empty()) {
        return std::atof(it->second.c_str()) / divisor;
    }
    return defaultVal;
}

// =========================================================================

bool NativeRenderCoordinator::renderNativeEffect(
    const EffectInstanceInfo& effectInfo, NativeRenderBuffer& buf)
{
    const std::string& type = effectInfo.effectType;

    if (type == "On") {
        // Native "On" effect: fill all pixels with the first palette color.
        // Settings: E_TEXTCTRL_Eff_On_Start (default 100), E_TEXTCTRL_Eff_On_End (default 100)
        int startIntensity = 100;
        int endIntensity = 100;

        auto it = effectInfo.settings.find("E_TEXTCTRL_Eff_On_Start");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            startIntensity = std::atoi(it->second.c_str());
        }
        it = effectInfo.settings.find("E_TEXTCTRL_Eff_On_End");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            endIntensity = std::atoi(it->second.c_str());
        }

        xlColor color;
        buf.palette.GetColor(0, color);

        // Apply intensity ramp
        if (startIntensity != 100 || endIntensity != 100) {
            float pos = buf.GetEffectTimeIntervalPosition();
            double d = startIntensity + (endIntensity - startIntensity) * (double)pos;
            d = d / 100.0;
            HSVValue hsv = color.asHSV();
            hsv.value = hsv.value * d;
            color = hsv;
        }

        buf.Fill(color);
        return true;
    }

    if (type == "Color Wash" || type == "ColorWash") {
        // Native Color Wash — port of legacy ColorWashEffect::Render
        float oset = buf.GetEffectTimeIntervalPosition();

        // Read settings
        double cycles = 1.0;
        auto it = effectInfo.settings.find("E_TEXTCTRL_ColorWash_Cycles");
        if (it != effectInfo.settings.end() && !it->second.empty())
            cycles = std::atof(it->second.c_str());
        if (cycles < 0.0) cycles = 0.0;

        bool horizFade = false, vertFade = false, reverseFades = false;
        bool shimmer = false, circularPalette = false;
        it = effectInfo.settings.find("E_CHECKBOX_ColorWash_HFade");
        if (it != effectInfo.settings.end()) horizFade = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_ColorWash_VFade");
        if (it != effectInfo.settings.end()) vertFade = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_ColorWash_ReverseFades");
        if (it != effectInfo.settings.end()) reverseFades = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_ColorWash_Shimmer");
        if (it != effectInfo.settings.end()) shimmer = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_ColorWash_CircularPalette");
        if (it != effectInfo.settings.end()) circularPalette = (it->second == "1");

        // Get blended color at current position with cycles
        double position = buf.GetEffectTimeIntervalPosition(cycles);
        xlColor color;
        buf.GetMultiColorBlend(position, circularPalette, color);

        int endX = buf.BufferWi - 1;
        int endY = buf.BufferHt - 1;

        int tot = buf.curPeriod - buf.curEffStartPer;
        if (!shimmer || (tot % 2) == 0) {
            double halfHt = (double)endY / 2.0;
            double halfWi = (double)endX / 2.0;

            xlColor orig = color;
            HSVValue hsvOrig = color.asHSV();

            for (int x = 0; x <= endX; x++) {
                HSVValue hsv = hsvOrig;
                xlColor colX = orig;

                if (horizFade) {
                    double mult;
                    if (reverseFades) {
                        mult = (halfWi > 0) ? std::abs(halfWi - x) / halfWi : 0.0;
                    } else {
                        mult = (halfWi > 0) ? 1.0 - std::abs(halfWi - x) / halfWi : 1.0;
                    }
                    hsv.value *= mult;
                    colX = xlColor(hsv);
                }

                for (int y = 0; y <= endY; y++) {
                    xlColor colFinal = colX;
                    if (vertFade) {
                        HSVValue hsv2 = colX.asHSV();
                        double mult;
                        if (reverseFades) {
                            mult = (halfHt > 0) ? std::abs(halfHt - y) / halfHt : 0.0;
                        } else {
                            mult = (halfHt > 0) ? 1.0 - std::abs(halfHt - y) / halfHt : 1.0;
                        }
                        hsv2.value *= mult;
                        colFinal = xlColor(hsv2);
                    }
                    buf.SetPixel(x, y, colFinal);
                }
            }
        }
        // shimmer odd frames: leave buffer black (cleared state)

        return true;
    }

    if (type == "Fire") {
        // Native Fire effect — port of legacy FireEffect::Render
        int heightPct = 50;
        int hueShift = 0;
        int loc = 0; // 0=Bottom, 1=Top, 2=Left, 3=Right

        auto it = effectInfo.settings.find("E_SLIDER_Fire_Height");
        if (it != effectInfo.settings.end() && !it->second.empty())
            heightPct = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fire_HueShift");
        if (it != effectInfo.settings.end() && !it->second.empty())
            hueShift = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_CHOICE_Fire_Location");
        if (it != effectInfo.settings.end()) {
            if (it->second == "Top") loc = 1;
            else if (it->second == "Left") loc = 2;
            else if (it->second == "Right") loc = 3;
        }
        if (heightPct < 1) heightPct = 1;

        int curWi = buf.BufferWi;
        int curHt = buf.BufferHt;
        if (loc == 2 || loc == 3) std::swap(curHt, curWi);
        if (curHt < 1) curHt = 1;

        // Build fire palette: 100 black→red + 100 red→yellow
        static thread_local std::vector<xlColor> firePalette;
        static thread_local std::vector<xlColor> firePaletteAlpha;
        if (firePalette.empty()) {
            firePalette.resize(200);
            firePaletteAlpha.resize(200);
            for (int i = 0; i < 100; i++) {
                HSVValue hsv(0.0, 1.0, (double)i / 100.0);
                firePalette[i] = xlColor(hsv);
                firePaletteAlpha[i] = xlColor(255, 0, 0, i * 255 / 100);
            }
            HSVValue hsv(0.0, 1.0, 1.0);
            for (int i = 0; i < 100; i++) {
                firePalette[100 + i] = xlColor(hsv);
                firePaletteAlpha[100 + i] = xlColor(hsv);
                hsv.hue += 0.00166666;
            }
        }

        // Fire buffer: persistent via infoCache for multi-frame renders
        struct FireCache : public EffectRenderCache {
            std::vector<int> fireBuffer;
            int maxWi = 0, maxHt = 0;
        };

        FireCache* cache = dynamic_cast<FireCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new FireCache();
            buf.infoCache[0] = cache;
        }

        if (buf.needToInit || cache->maxWi != curWi || cache->maxHt != curHt) {
            buf.needToInit = false;
            cache->maxWi = curWi;
            cache->maxHt = curHt;
            cache->fireBuffer.assign(curWi * curHt, 0);
        }

        auto& fb = cache->fireBuffer;
        int maxWi = cache->maxWi;
        int maxHt = cache->maxHt;
        int palSize = 200;

        // Seed bottom row with random hot values
        for (int x = 0; x < maxWi; x++) {
            int r = (x % 2 == 0) ? 190 + (std::rand() % 10) : 100 + (std::rand() % 50);
            if (x < maxWi && maxHt > 0) fb[0 * maxWi + x] = r;
        }

        // Propagate fire upward
        int step = 255 * 100 / curHt / heightPct;
        for (int y = 1; y < maxHt; y++) {
            for (int x = 0; x < maxWi; x++) {
                int n = 0, sum = 0;
                auto getVal = [&](int gx, int gy) -> int {
                    if (gx >= 0 && gx < maxWi && gy >= 0 && gy < maxHt)
                        return fb[gy * maxWi + gx];
                    return -1;
                };
                int v;
                v = getVal(x - 1, y - 1); if (v >= 0) { sum += v; n++; }
                v = getVal(x + 1, y - 1); if (v >= 0) { sum += v; n++; }
                v = getVal(x, y - 1);     if (v >= 0) { sum += v; n++; }
                v = getVal(x, y - 1);     if (v >= 0) { sum += v; n++; }

                int newIdx = n > 0 ? sum / n : 0;
                if (newIdx > 0) {
                    newIdx += (std::rand() % 100 < 20) ? step : -step;
                    if (newIdx < 0) newIdx = 0;
                    if (newIdx >= palSize) newIdx = palSize - 1;
                }
                fb[y * maxWi + x] = newIdx;
            }
        }

        // Render fire to pixel buffer
        for (int y = 0; y < curHt; y++) {
            for (int x = 0; x < curWi; x++) {
                int xp = x, yp = y;
                if (loc == 1 || loc == 3) yp = curHt - y - 1;
                if (loc == 2 || loc == 3) std::swap(xp, yp);

                int idx = (y < maxHt && x < maxWi) ? fb[y * maxWi + x] : 0;
                if (idx < 0) idx = 0;
                if (idx >= palSize) idx = palSize - 1;

                if (hueShift > 0) {
                    HSVValue hsv = firePalette[idx].asHSV();
                    hsv.hue += hueShift / 100.0;
                    if (hsv.hue > 1.0) hsv.hue = 1.0;
                    buf.SetPixel(xp, yp, xlColor(hsv));
                } else {
                    buf.SetPixel(xp, yp, firePalette[idx]);
                }
            }
        }
        return true;
    }


    if (type == "Adjust") {
        // Native Adjust effect: reads existing pixel data and adjusts
        // brightness, contrast, saturation, hue, and value.
        // Typically used in canvas mode on top of other effects.
        int brightness = 100;
        int contrast = 0;
        int saturation = 100;
        int hueShift = 0;
        int valuePct = 100;

        auto it = effectInfo.settings.find("E_SLIDER_Adjust_Brightness");
        if (it != effectInfo.settings.end() && !it->second.empty())
            brightness = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Adjust_Contrast");
        if (it != effectInfo.settings.end() && !it->second.empty())
            contrast = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Adjust_Saturation");
        if (it != effectInfo.settings.end() && !it->second.empty())
            saturation = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Adjust_Hue");
        if (it != effectInfo.settings.end() && !it->second.empty())
            hueShift = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Adjust_Value");
        if (it != effectInfo.settings.end() && !it->second.empty())
            valuePct = std::atoi(it->second.c_str());

        // Early exit if all adjustments are at identity values
        if (brightness == 100 && contrast == 0 && saturation == 100 &&
            hueShift == 0 && valuePct == 100) {
            return true;
        }

        // Precompute contrast lookup table (maps 0-255 input to 0-255 output).
        // Contrast formula: shift to center (-128), scale, shift back.
        // contrast range: -100..100 mapped to factor 0..~3.
        uint8_t contrastLUT[256];
        if (contrast != 0) {
            double factor;
            if (contrast > 0) {
                // Map 0..100 to factor 1..infinity (using tangent-like curve)
                factor = (100.0 + contrast) / (100.0 - std::min(contrast, 99));
            } else {
                // Map -100..0 to factor 0..1
                factor = (100.0 + contrast) / 100.0;
            }
            for (int i = 0; i < 256; i++) {
                double val = ((i / 255.0 - 0.5) * factor + 0.5) * 255.0;
                contrastLUT[i] = static_cast<uint8_t>(std::clamp(static_cast<int>(val + 0.5), 0, 255));
            }
        }

        double brightFactor = brightness / 100.0;   // 0..4.0, 1.0 = identity
        double satFactor = saturation / 100.0;       // 0..2.0, 1.0 = identity
        double hueOffset = hueShift / 100.0;         // -1.0..1.0, 0.0 = identity
        double valFactor = valuePct / 100.0;         // 0..2.0, 1.0 = identity

        xlColor* pixels = buf.GetPixels();
        uint32_t pixelCount = buf.GetPixelCount();

        for (uint32_t i = 0; i < pixelCount; ++i) {
            xlColor c = pixels[i];

            // Skip fully transparent or black pixels (nothing to adjust)
            if (c.red == 0 && c.green == 0 && c.blue == 0) continue;

            // Apply brightness (scale RGB channels)
            if (brightness != 100) {
                int r = static_cast<int>(c.red * brightFactor + 0.5);
                int g = static_cast<int>(c.green * brightFactor + 0.5);
                int b = static_cast<int>(c.blue * brightFactor + 0.5);
                c.red = static_cast<uint8_t>(std::clamp(r, 0, 255));
                c.green = static_cast<uint8_t>(std::clamp(g, 0, 255));
                c.blue = static_cast<uint8_t>(std::clamp(b, 0, 255));
            }

            // Apply contrast (via precomputed LUT)
            if (contrast != 0) {
                c.red = contrastLUT[c.red];
                c.green = contrastLUT[c.green];
                c.blue = contrastLUT[c.blue];
            }

            // Apply saturation, hue shift, and HSV value adjustments
            if (saturation != 100 || hueShift != 0 || valuePct != 100) {
                HSVValue hsv = c.asHSV();

                if (saturation != 100) {
                    hsv.saturation *= satFactor;
                    if (hsv.saturation > 1.0) hsv.saturation = 1.0;
                    if (hsv.saturation < 0.0) hsv.saturation = 0.0;
                }

                if (hueShift != 0) {
                    hsv.hue += hueOffset;
                    // Wrap hue into 0..1 range
                    while (hsv.hue < 0.0) hsv.hue += 1.0;
                    while (hsv.hue > 1.0) hsv.hue -= 1.0;
                }

                if (valuePct != 100) {
                    hsv.value *= valFactor;
                    if (hsv.value > 1.0) hsv.value = 1.0;
                    if (hsv.value < 0.0) hsv.value = 0.0;
                }

                uint8_t origAlpha = c.alpha;
                c = xlColor(hsv);
                c.alpha = origAlpha;
            }

            pixels[i] = c;
        }

        return true;
    }


    if (type == "Bars") {
        // Native Bars effect — port of legacy BarsEffect::Render

        float vcOffset = buf.GetEffectTimeIntervalPosition();
        int startMS = effectInfo.startTimeMS;
        int endMS = effectInfo.endTimeMS;

        // Read settings with value curve support
        int paletteRepeat = getSettingInt(effectInfo.settings, "E_SLIDER_Bars_BarCount", 1,
                                          vcOffset, startMS, endMS, 1, 50);
        double cycles = getSettingDouble(effectInfo.settings, "E_SLIDER_Bars_Cycles", 1.0,
                                          vcOffset, startMS, endMS, 0, 500, 10);
        double center = getSettingDouble(effectInfo.settings, "E_SLIDER_Bars_Center", 0.0,
                                          vcOffset, startMS, endMS, -100, 100, 1);

        std::string directionStr = "up";
        bool highlight = false;
        bool useFirstColorForHighlight = false;
        bool show3D = false;
        bool gradient = false;

        auto it = effectInfo.settings.find("E_CHOICE_Bars_Direction");
        if (it != effectInfo.settings.end() && !it->second.empty())
            directionStr = it->second;

        it = effectInfo.settings.find("E_CHECKBOX_Bars_Highlight");
        if (it != effectInfo.settings.end())
            highlight = (it->second == "1");

        it = effectInfo.settings.find("E_CHECKBOX_Bars_UseFirstColorForHighlight");
        if (it != effectInfo.settings.end())
            useFirstColorForHighlight = highlight && (it->second == "1");

        it = effectInfo.settings.find("E_CHECKBOX_Bars_3D");
        if (it != effectInfo.settings.end())
            show3D = (it->second == "1");

        it = effectInfo.settings.find("E_CHECKBOX_Bars_Gradient");
        if (it != effectInfo.settings.end())
            gradient = (it->second == "1");

        // Parse direction string to integer
        int direction = 0;
        if (directionStr == "up") direction = 0;
        else if (directionStr == "down") direction = 1;
        else if (directionStr == "expand") direction = 2;
        else if (directionStr == "compress") direction = 3;
        else if (directionStr == "Left") direction = 4;
        else if (directionStr == "Right") direction = 5;
        else if (directionStr == "H-expand") direction = 6;
        else if (directionStr == "H-compress") direction = 7;
        else if (directionStr == "Alternate Up") direction = 8;
        else if (directionStr == "Alternate Down") direction = 9;
        else if (directionStr == "Alternate Left") direction = 10;
        else if (directionStr == "Alternate Right") direction = 11;
        else if (directionStr == "Custom Horz") direction = 12;
        else if (directionStr == "Custom Vert") direction = 13;

        size_t colorcnt = buf.GetColorCount();
        if (colorcnt == 0)
            colorcnt = 1;

        xlColor highlightColor;
        if (highlight && useFirstColorForHighlight) {
            if (colorcnt == 1) {
                useFirstColorForHighlight = false;
            } else {
                colorcnt -= 1;
            }
        }

        int barCount = paletteRepeat * colorcnt;
        if (barCount < 1)
            barCount = 1;

        float offset = buf.GetEffectTimeIntervalPosition();
        double position = buf.GetEffectTimeIntervalPosition(cycles);

        xlColor color;

        if (direction < 4 || direction == 8 || direction == 9) {
            // Vertical directions: up, down, expand, compress, alternate up/down
            int barHt = (int)std::ceil((float)buf.BufferHt / (float)barCount);
            if (barHt < 1)
                barHt = 1;
            int newCenter = buf.BufferHt * (100 + center) / 200;
            int blockHt = colorcnt * barHt;
            if (blockHt < 1)
                blockHt = 1;

            int f_offset = position * blockHt;
            if (direction == 8 || direction == 9) {
                f_offset = floor(position * barCount) * barHt;
            }
            int dir = direction > 4 ? direction - 8 : direction;

            for (int y = -2 * buf.BufferHt; y < 2 * buf.BufferHt; ++y) {
                int n = buf.BufferHt + y + f_offset;
                int colorIdx = std::abs(n % blockHt) / barHt;
                if (useFirstColorForHighlight) {
                    colorIdx += 1;
                }
                int color2 = (colorIdx + 1) % colorcnt;
                double pct = (double)std::abs(n % barHt) / (double)barHt;

                if (useFirstColorForHighlight) {
                    buf.palette.GetColor(0, highlightColor);
                } else {
                    highlightColor = xlWHITE;
                }

                if (buf.allowAlpha) {
                    buf.palette.GetColor(colorIdx, color);
                    if (gradient)
                        buf.Get2ColorBlend(colorIdx, color2, pct, color);
                    if (highlight && n % barHt == 0)
                        color = highlightColor;
                    if (show3D) {
                        int numerator = barHt - std::abs(n % barHt) - 1;
                        color.alpha = 255.0 * double(numerator) / double(barHt);
                    }
                } else {
                    buf.palette.GetColor(colorIdx, color);
                    if (gradient)
                        buf.Get2ColorBlend(colorIdx, color2, pct, color);
                    HSVValue hsv = color.asHSV();
                    if (highlight && n % barHt == 0)
                        hsv.saturation = 0.0;
                    if (show3D) {
                        int numerator = barHt - std::abs(n % barHt) - 1;
                        hsv.value *= double(numerator) / double(barHt);
                    }
                    color = hsv;
                }

                switch (dir) {
                case 1:
                    // down
                    for (int x = 0; x < buf.BufferWi; ++x) {
                        buf.SetPixel(x, y, color);
                    }
                    break;
                case 2:
                    // expand
                    if (y <= newCenter) {
                        for (int x = 0; x < buf.BufferWi; ++x) {
                            buf.SetPixel(x, y, color);
                            buf.SetPixel(x, newCenter + (newCenter - y), color);
                        }
                    }
                    break;
                case 3:
                    // compress
                    if (y >= newCenter) {
                        for (int x = 0; x < buf.BufferWi; ++x) {
                            buf.SetPixel(x, y, color);
                            buf.SetPixel(x, newCenter + (newCenter - y), color);
                        }
                    }
                    break;
                default:
                    // up
                    for (int x = 0; x < buf.BufferWi; ++x) {
                        buf.SetPixel(x, buf.BufferHt - y - 1, color);
                    }
                    break;
                }
            }
        } else if (direction == 12 || direction == 13) {
            // Custom Horz / Custom Vert
            int width = buf.BufferWi;
            int height = buf.BufferHt;
            if (direction == 13) {
                std::swap(width, height);
            }
            int BarWi = (int)std::ceil((float)width / (float)barCount);
            if (BarWi < 1)
                BarWi = 1;
            int NewCenter = (width * (100.0 + center) / 200.0 - width / 2);
            int BlockWi = colorcnt * BarWi;
            if (BlockWi < 1)
                BlockWi = 1;

            for (int x = -2 * width; x < 2 * width; ++x) {
                int n = width + x;
                int colorIdx = (n % BlockWi) / BarWi;
                if (useFirstColorForHighlight) {
                    colorIdx += 1;
                }
                int color2 = (colorIdx + 1) % colorcnt;
                double pct = (double)(n % BarWi) / (double)BarWi;
                if (useFirstColorForHighlight) {
                    buf.palette.GetColor(0, highlightColor);
                } else {
                    highlightColor = xlWHITE;
                }

                if (buf.allowAlpha) {
                    buf.palette.GetColor(colorIdx, color);
                    if (gradient)
                        buf.Get2ColorBlend(colorIdx, color2, pct, color);
                    if (highlight && n % BarWi == 0)
                        color = highlightColor;
                    if (show3D)
                        color.alpha = 255.0 * double(BarWi - n % BarWi - 1) / BarWi;
                } else {
                    buf.palette.GetColor(colorIdx, color);
                    if (gradient)
                        buf.Get2ColorBlend(colorIdx, color2, pct, color);
                    HSVValue hsv = color.asHSV();
                    if (highlight && n % BarWi == 0)
                        hsv.saturation = 0.0;
                    if (show3D)
                        hsv.value *= double(BarWi - n % BarWi - 1) / BarWi;
                    color = hsv;
                }

                int position_x = width - x - 1 + NewCenter;
                for (int y = 0; y < height; ++y) {
                    if (direction == 12) {
                        buf.SetPixel(position_x, y, color);
                    } else {
                        buf.SetPixel(y, position_x, color);
                    }
                }
            }
        } else {
            // Horizontal directions: left, right, H-expand, H-compress, alternate left/right
            int barWi = (int)std::ceil((float)buf.BufferWi / (float)barCount);
            if (barWi < 1)
                barWi = 1;
            int newCenter = buf.BufferWi * (100 + center) / 200;
            int blockWi = colorcnt * barWi;
            if (blockWi < 1)
                blockWi = 1;
            int f_offset = position * blockWi;
            if (direction > 9) {
                f_offset = floor(position * barCount) * barWi;
            }

            int dir = direction > 9 ? direction - 6 : direction;
            for (int x = -2 * buf.BufferWi; x < 2 * buf.BufferWi; ++x) {
                int n = buf.BufferWi + x + f_offset;
                int colorIdx = (n % blockWi) / barWi;
                if (useFirstColorForHighlight) {
                    colorIdx += 1;
                }
                int color2 = (colorIdx + 1) % colorcnt;
                double pct = (double)(n % barWi) / (double)barWi;
                if (useFirstColorForHighlight) {
                    buf.palette.GetColor(0, highlightColor);
                } else {
                    highlightColor = xlWHITE;
                }

                if (buf.allowAlpha) {
                    buf.palette.GetColor(colorIdx, color);
                    if (gradient)
                        buf.Get2ColorBlend(colorIdx, color2, pct, color);
                    if (highlight && n % barWi == 0)
                        color = highlightColor;
                    if (show3D)
                        color.alpha = 255.0 * double(barWi - n % barWi - 1) / (double)barWi;
                } else {
                    buf.palette.GetColor(colorIdx, color);
                    if (gradient)
                        buf.Get2ColorBlend(colorIdx, color2, pct, color);
                    HSVValue hsv = color.asHSV();
                    if (highlight && n % barWi == 0)
                        hsv = highlightColor.asHSV();
                    if (show3D)
                        hsv.value *= double(barWi - n % barWi - 1) / barWi;
                    color = hsv;
                }

                switch (dir) {
                case 5:
                    // right
                    for (int y = 0; y < buf.BufferHt; ++y) {
                        buf.SetPixel(buf.BufferWi - x - 1, y, color);
                    }
                    break;
                case 6:
                    // H-expand
                    if (x <= newCenter) {
                        for (int y = 0; y < buf.BufferHt; ++y) {
                            buf.SetPixel(x, y, color);
                            buf.SetPixel(newCenter + (newCenter - x), y, color);
                        }
                    }
                    break;
                case 7:
                    // H-compress
                    if (x >= newCenter) {
                        for (int y = 0; y < buf.BufferHt; ++y) {
                            buf.SetPixel(x, y, color);
                            buf.SetPixel(newCenter + (newCenter - x), y, color);
                        }
                    }
                    break;
                default:
                    // left
                    for (int y = 0; y < buf.BufferHt; ++y) {
                        buf.SetPixel(x, y, color);
                    }
                    break;
                }
            }
        }

        return true;
    }


    if (type == "Butterfly") {
        // Native Butterfly effect — port of legacy ISPC-based ButterflyEffect::Render
        //
        // Settings keys (from XLEffectPanelDefinitions.mm kButterflyParameters):
        //   E_SLIDER_Butterfly_Style   (1-10, default 1)
        //   E_SLIDER_Butterfly_Chunks  (1-10, default 1)
        //   E_SLIDER_Butterfly_Skip    (2-10, default 2)
        //   E_SLIDER_Butterfly_Speed   (0-100, default 10)
        //   E_CHOICE_Butterfly_Colors  ("Rainbow" or "Palette", default "Rainbow")
        //   E_CHOICE_Butterfly_Direction ("Normal" or "Reverse", default "Normal")

        int style = 1;
        int chunks = 1;
        int skip = 2;
        int speed = 10;
        int colorScheme = 0; // 0=Rainbow, 1=Palette
        int direction = 0;   // 0=Normal, 1=Reverse

        auto it = effectInfo.settings.find("E_SLIDER_Butterfly_Style");
        if (it != effectInfo.settings.end() && !it->second.empty())
            style = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Butterfly_Chunks");
        if (it != effectInfo.settings.end() && !it->second.empty())
            chunks = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Butterfly_Skip");
        if (it != effectInfo.settings.end() && !it->second.empty())
            skip = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Butterfly_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            speed = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_CHOICE_Butterfly_Colors");
        if (it != effectInfo.settings.end() && it->second == "Palette")
            colorScheme = 1;

        it = effectInfo.settings.find("E_CHOICE_Butterfly_Direction");
        if (it != effectInfo.settings.end() && it->second == "Reverse")
            direction = 1;

        const int curState = (buf.curPeriod - buf.curEffStartPer) * speed * buf.frameTimeInMs / 50;
        const double offset = (direction == 1 ? -1.0 : 1.0) * (double)curState / 200.0;
        const size_t colorcnt = buf.GetColorCount();
        const int width = buf.BufferWi;
        const int height = buf.BufferHt;

        // Plasma styles (6-10) use different time calculation
        double plasmaTime = 0.0;
        if (style > 5) {
            int state = buf.curPeriod - buf.curEffStartPer;
            double speedPlasma = (style == 10) ? (101 - speed) * 3.0 : (101 - speed) * 5.0;
            plasmaTime = (state + 1.0) / speedPlasma;
        }

        // HSV hue-only to RGB (s=1, v=1) — port of ISPC h2rgb
        auto h2rgb = [](float h) -> xlColor {
            h = std::max(0.0f, std::min(h, 1.0f));
            float hue = h * 6.0f;
            int i = (int)std::floor(hue);
            float f = hue - (float)i;
            float r, g, b;
            switch (i) {
                case 6:
                case 0:  r = 1.0f; g = f;        b = 0.0f;      break;
                case 1:  r = 1.0f - f; g = 1.0f; b = 0.0f;      break;
                case 2:  r = 0.0f; g = 1.0f;     b = f;          break;
                case 3:  r = 0.0f; g = 1.0f - f; b = 1.0f;      break;
                case 4:  r = f;    g = 0.0f;     b = 1.0f;      break;
                default: r = 1.0f; g = 0.0f;     b = 1.0f - f;  break;
            }
            return xlColor((uint8_t)(r * 255.0f), (uint8_t)(g * 255.0f), (uint8_t)(b * 255.0f));
        };

        // Per-pixel color assignment helper
        auto setColorForH = [&](int x, int y, float h, bool skipCheck) {
            if (skipCheck && chunks > 1 && (int)(h * chunks) % skip == 0)
                return;
            if (colorScheme == 0) {
                buf.SetPixel(x, y, h2rgb(h));
            } else {
                xlColor color;
                buf.GetMultiColorBlend(h, false, color);
                buf.SetPixel(x, y, color);
            }
        };

        const float pi = 3.14159f;
        const float pi2 = pi * 2.0f;

        if (style <= 5) {
            // Styles 1-5: mathematical butterfly patterns
            for (int y = 0; y < height; y++) {
                for (int x = 0; x < width; x++) {
                    float fx = (float)x;
                    float fy = (float)y;
                    float h = 0.0f;

                    switch (style) {
                        case 1: {
                            // x*y^3 - y*x^3 variant
                            float sz = (float)(height + width);
                            float rsz = pi2 / sz;
                            float x2 = fx * fx;
                            float y2 = fy * fy;
                            float n = std::abs((x2 - y2) * std::sin((float)offset + (fx + fy) * rsz));
                            float d = x2 + y2;
                            h = d > 0.001f ? std::min(n / d, 1.0f) : 0.0f;
                            break;
                        }
                        case 2: {
                            // Expanding/contracting circle
                            int maxframe = height * 2;
                            int frame = (height * curState / 200) % maxframe;
                            float f = (frame < height) ? (float)(frame + 1) : (float)(maxframe - frame);
                            float x1 = (fx - (float)width / 2.0f) / f;
                            float y1 = (fy - (float)height / 2.0f) / f;
                            h = std::sqrt(x1 * x1 + y1 * y1);
                            break;
                        }
                        case 3: {
                            // sin*cos pattern
                            int maxframe = height * 2;
                            int frame = (height * curState / 200) % maxframe;
                            float f = (frame < maxframe / 2) ? (float)(frame + 1) : (float)(maxframe - frame);
                            f = f * 0.1f + (float)height / 60.0f;
                            float x1 = (fx - (float)width / 2.0f) / f;
                            float y1 = (fy - (float)height / 2.0f) / f;
                            h = std::sin(x1) * std::cos(y1);
                            break;
                        }
                        case 4: {
                            // Like style 1 but with fractional part (allows wrapping)
                            float sz = (float)(height + width);
                            float rsz = pi2 / sz;
                            float n = (fx * fx - fy * fy) * std::sin((float)offset + (fx + fy) * rsz);
                            float d = fx * fx + fy * fy;
                            h = d > 0.001f ? n / d : 0.0f;
                            float intpart = std::floor(h);
                            h = h - intpart;
                            if (h < 0.0f) h = 1.0f + h;
                            break;
                        }
                        case 5: {
                            // Fix colors on pixels at {0,1} and {1,0}
                            float ax = fx, ay = fy;
                            if (x == 0 && y == 1) ay += 1.0f;
                            if (x == 1 && y == 0) ax += 1.0f;
                            float n = std::abs((ax * ax - ay * ay) *
                                std::sin((float)offset + (ax + ay) * pi2 / (float)(height * width)));
                            float d = ax * ax + ay * ay;
                            h = d > 0.001f ? n / d : 0.0f;
                            break;
                        }
                    }

                    setColorForH(x, y, h, true);
                }
            }
        } else {
            // Styles 6-10: plasma patterns
            const float invh = 1.0f / (float)height;
            const float invw = 1.0f / (float)width;
            const float time = (float)plasmaTime;
            const float halfTime = time / 2.0f;
            const float thirdTime = time / 3.0f;
            const float fifthTime = time / 5.0f;
            const float oneThird = 1.0f / 3.0f;
            const float fchunks = (float)chunks;

            for (int y = 0; y < height; y++) {
                for (int x = 0; x < width; x++) {
                    float fx = (float)x;
                    float fy = (float)y;

                    float rx = fx * invw - 0.5f;
                    float ry = fy * invh - 0.5f;

                    // 1st equation
                    float v = std::sin(rx * 10.0f + time);

                    // 2nd equation
                    v += std::sin(10.0f * (rx * std::sin(halfTime) + ry * std::cos(thirdTime)) + time);

                    // 3rd equation
                    float cx = rx + 0.5f * std::sin(fifthTime);
                    float cy = ry + 0.5f * std::cos(thirdTime);
                    v += std::sin(std::sqrt(100.0f * (cx * cx + cy * cy) + 1.0f + time));

                    v += std::sin(rx + time);
                    v += std::sin((ry + time) * 0.5f);
                    v += std::sin((rx + ry + time) * 0.5f);

                    v += std::sin(std::sqrt(rx * rx + ry * ry + 1.0f) + time);
                    v = v * 0.5f;

                    xlColor color;
                    switch (style) {
                        case 6:
                            color.Set(
                                (uint8_t)((std::sin(v * fchunks * pi) + 1.0f) * 128.0f),
                                (uint8_t)((std::cos(v * fchunks * pi) + 1.0f) * 128.0f),
                                0);
                            break;
                        case 7:
                            color.Set(
                                1,
                                (uint8_t)((std::cos(v * fchunks * pi) + 1.0f) * 128.0f),
                                (uint8_t)((std::sin(v * fchunks * pi) + 1.0f) * 128.0f));
                            break;
                        case 8:
                            color.Set(
                                (uint8_t)((std::sin(v * fchunks * pi) + 1.0f) * 128.0f),
                                (uint8_t)((std::sin(v * fchunks * pi + 2.0f * pi * oneThird) + 1.0f) * 128.0f),
                                (uint8_t)((std::sin(v * fchunks * pi + 4.0f * pi * oneThird) + 1.0f) * 128.0f));
                            break;
                        case 9: {
                            uint8_t gray = (uint8_t)((std::sin(v * fchunks * pi) + 1.0f) * 128.0f);
                            color.Set(gray, gray, gray);
                            break;
                        }
                        case 10:
                            if (colorcnt >= 2) {
                                float h = std::sin(v * fchunks * pi + 2.0f * pi * oneThird) + 0.5f;
                                buf.GetMultiColorBlend(h, false, color);
                            } else {
                                color.Set(0, 0, 0);
                            }
                            break;
                        default:
                            color.Set(0, 0, 0);
                            break;
                    }
                    buf.SetPixel(x, y, color);
                }
            }
        }
        return true;
    }


    if (type == "Candle") {
        // Native Candle effect -- per-node flame simulation.
        // Faithfully ported from CandleEffect::Render / CandleEffect::Update.
        //
        // Each flame node tracks five state bytes (flameprimer, flamer, wind,
        // flameprimeg, flameg) that evolve every frame. The render cache
        // persists these across frames so the flame flickers realistically.
        //
        // Audio-reactive wind (GrowWithMusic) is NOT implemented in the
        // legacy Render() method -- it only appears in CheckEffectSettings
        // as a validation warning. No stub needed.

        // --- Read settings --------------------------------------------------
        int flameAgility = 2;
        int windBaseline = 30;
        int windVariability = 5;
        int windCalmness = 2;
        bool perNode = false;
        bool usePalette = false;

        auto it = effectInfo.settings.find("E_SLIDER_Candle_FlameAgility");
        if (it != effectInfo.settings.end() && !it->second.empty())
            flameAgility = std::clamp(std::atoi(it->second.c_str()), 1, 10);

        it = effectInfo.settings.find("E_SLIDER_Candle_WindBaseline");
        if (it != effectInfo.settings.end() && !it->second.empty())
            windBaseline = std::clamp(std::atoi(it->second.c_str()), 0, 255);

        it = effectInfo.settings.find("E_SLIDER_Candle_WindVariability");
        if (it != effectInfo.settings.end() && !it->second.empty())
            windVariability = std::clamp(std::atoi(it->second.c_str()), 0, 10);

        it = effectInfo.settings.find("E_SLIDER_Candle_WindCalmness");
        if (it != effectInfo.settings.end() && !it->second.empty())
            windCalmness = std::clamp(std::atoi(it->second.c_str()), 0, 10);

        it = effectInfo.settings.find("E_CHECKBOX_PerNode");
        if (it != effectInfo.settings.end())
            perNode = (it->second == "1");

        it = effectInfo.settings.find("E_CHECKBOX_UsePalette");
        if (it != effectInfo.settings.end())
            usePalette = (it->second == "1");

        // --- Palette colors (when usePalette is true) ------------------------
        xlColor c1 = xlWHITE, c2 = xlBLACK;
        if (usePalette) {
            if (buf.palette.ExplicitSize() > 0) {
                c1 = buf.palette.GetColor(0);
                c2 = (buf.palette.ExplicitSize() > 1) ? buf.palette.GetColor(1) : xlBLACK;
            }
        }

        // --- Per-node flame state (CandleState) in render cache --------------
        // Mirrors the legacy CandleState struct exactly.
        struct CandleState {
            uint8_t flameprimer;
            uint8_t flamer;
            uint8_t wind;
            uint8_t flameprimeg;
            uint8_t flameg;

            void init() {
                auto r01 = []() -> double {
                    return static_cast<double>(std::rand()) / static_cast<double>(RAND_MAX);
                };
                flamer = static_cast<uint8_t>(r01() * 255);
                flameprimer = static_cast<uint8_t>(r01() * 255);
                flameg = static_cast<uint8_t>(r01() * flamer);
                flameprimeg = static_cast<uint8_t>(r01() * flameprimer);
                wind = static_cast<uint8_t>(r01() * 255);
            }
        };

        struct CandleCache : public EffectRenderCache {
            std::vector<CandleState> states;
            int maxWid = 0;
        };

        CandleCache* cache = dynamic_cast<CandleCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new CandleCache();
            buf.infoCache[0] = cache;
        }

        // --- Initialise on first frame or if cache is empty ------------------
        if (buf.needToInit) {
            buf.needToInit = false;

            int numStates = 1;
            if (perNode) {
                cache->maxWid = buf.BufferWi;
                numStates = buf.BufferWi * buf.BufferHt;
            }
            if (numStates > static_cast<int>(cache->states.size())) {
                cache->states.resize(numStates);
            }
            for (int i = 0; i < numStates; i++) {
                cache->states[i].init();
            }
        }

        // --- Flame update function (direct port of CandleEffect::Update) -----
        auto updateFlame = [](uint8_t& flameprime, uint8_t& flame,
                              uint8_t& wind, int wVar, int fAgil,
                              int wCalm, int wBase) {
            auto r01 = []() -> double {
                return static_cast<double>(std::rand()) / static_cast<double>(RAND_MAX);
            };

            // Simulate wind gusts
            if (static_cast<uint8_t>(r01() * 255.0) < wVar)
                wind = static_cast<uint8_t>(r01() * 255.0);

            // Wind settles toward baseline
            if (wind > wBase)
                wind--;

            // Flame brightens
            if (flame < 255)
                flame++;

            // Wind may knock the flame down
            if (static_cast<uint8_t>(r01() * 255) < (wind >> wCalm))
                flame = static_cast<uint8_t>(r01() * 255);

            // Low-pass filter for inertia
            if (flame > flameprime) {
                if (flameprime < (255 - fAgil))
                    flameprime += fAgil;
            } else {
                if (flameprime > fAgil)
                    flameprime -= fAgil;
            }
        };

        // --- Render ----------------------------------------------------------
        auto& states = cache->states;

        if (perNode) {
            int maxW = cache->maxWid;
            for (int y = 0; y < buf.BufferHt; y++) {
                for (int x = 0; x < buf.BufferWi; x++) {
                    int index = y * maxW + x;
                    if (index >= static_cast<int>(states.size()))
                        continue;

                    CandleState& st = states[index];

                    updateFlame(st.flameprimer, st.flamer, st.wind,
                                windVariability, flameAgility,
                                windCalmness, windBaseline);
                    updateFlame(st.flameprimeg, st.flameg, st.wind,
                                windVariability, flameAgility,
                                windCalmness, windBaseline);

                    // Clamp green channel to red channel
                    if (st.flameprimeg > st.flameprimer)
                        st.flameprimeg = st.flameprimer;
                    if (st.flameg > st.flamer)
                        st.flameprimeg = st.flameprimer;

                    xlColor c;
                    if (usePalette) {
                        float t = static_cast<float>(st.flameprimer) / 255.0f;
                        c.red   = static_cast<uint8_t>(c1.red   * (1.0f - t) + c2.red   * t);
                        c.green = static_cast<uint8_t>(c1.green * (1.0f - t) + c2.green * t);
                        c.blue  = static_cast<uint8_t>(c1.blue  * (1.0f - t) + c2.blue  * t);
                    } else {
                        c = xlColor(st.flameprimer, st.flameprimeg / 2, 0);
                    }
                    buf.SetPixel(x, y, c);
                }
            }
        } else {
            // Single-state mode: all pixels share one flame
            CandleState& st = states[0];

            updateFlame(st.flameprimer, st.flamer, st.wind,
                        windVariability, flameAgility,
                        windCalmness, windBaseline);
            updateFlame(st.flameprimeg, st.flameg, st.wind,
                        windVariability, flameAgility,
                        windCalmness, windBaseline);

            if (st.flameprimeg > st.flameprimer)
                st.flameprimeg = st.flameprimer;
            if (st.flameg > st.flamer)
                st.flameprimeg = st.flameprimer;

            xlColor c;
            if (usePalette) {
                float t = static_cast<float>(st.flameprimer) / 255.0f;
                c.red   = static_cast<uint8_t>(c1.red   * (1.0f - t) + c2.red   * t);
                c.green = static_cast<uint8_t>(c1.green * (1.0f - t) + c2.green * t);
                c.blue  = static_cast<uint8_t>(c1.blue  * (1.0f - t) + c2.blue  * t);
            } else {
                c = xlColor(st.flameprimer, st.flameprimeg / 2, 0);
            }

            for (int y = 0; y < buf.BufferHt; y++) {
                for (int x = 0; x < buf.BufferWi; x++) {
                    buf.SetPixel(x, y, c);
                }
            }
        }
        return true;
    }


    if (type == "Circles") {
        // Native Circles effect — faithful port of CirclesEffect::Render
        // Ball physics simulation with persistent state via EffectRenderCache.

        static const int MAX_RGB_BALLS = 20;

        // --- RgbBalls: ball with position, velocity, radius, color ---
        struct RgbBalls {
            float _x = 0, _y = 0;
            float _dx = 0, _dy = 0;
            float _radius = 0;
            float _t = 0;
            float dir = 1.0f;
            float _angle = 0;
            float _spd = 0;
            int _colorindex = 0;

            void Reset(float x, float y, float speed, float angle, float radius, int colorindex) {
                _angle = angle;
                _spd = speed;
                _x = x;
                _y = y;
                _dx = speed * std::cos(angle);
                _dy = speed * std::sin(angle);
                _radius = radius;
                _colorindex = colorindex;
                _t = (float)M_PI / 6.0f;
                dir = 1.0f;
            }

            void updatePosition(float incr, int width, int height) {
                _x += _dx * incr;
                _x = _x > width ? 0 : _x;
                _x = _x < 0 ? width : _x;
                _y += _dy * incr;
                _y = _y > height ? 0 : _y;
                _y = _y < 0 ? height : _y;
            }

            void Bounce(int width, int height) {
                if (_x - _radius <= 0) {
                    _dx = std::fabs(_dx);
                    if (_dx < 0.2f) _dx = 0.2f;
                }
                if (_x + _radius >= width) {
                    _dx = -std::fabs(_dx);
                    if (_dx > -0.2f) _dx = -0.2f;
                }
                if (_y - _radius <= 0) {
                    _dy = std::fabs(_dy);
                    if (_dy < 0.2f) _dy = 0.2f;
                }
                if (_y + _radius >= height) {
                    _dy = -std::fabs(_dy);
                    if (_dy > -0.2f) _dy = -0.2f;
                }
            }
        };

        // --- MetaBall: extends RgbBalls with metaball equation ---
        struct MetaBall : public RgbBalls {
            float Equation(float x, float y) {
                if ((x == _x) && (y == _y)) return 1.0f;
                return (_radius / (std::sqrt((x - _x) * (x - _x) + (y - _y) * (y - _y))));
            }
        };

        // --- Persistent cache for ball state across frames ---
        struct CirclesCache : public EffectRenderCache {
            CirclesCache() : numBalls(0), metaType(false) {
                balls.resize(MAX_RGB_BALLS);
                metaballs.resize(MAX_RGB_BALLS);
            }
            ~CirclesCache() override = default;
            bool metaType;
            int numBalls;
            std::vector<RgbBalls> balls;
            std::vector<MetaBall> metaballs;
        };

        // Read settings
        int number = 3;
        int circleSpeed = 10;
        int radius = 5;

        auto it = effectInfo.settings.find("E_SLIDER_Circles_Count");
        if (it != effectInfo.settings.end() && !it->second.empty())
            number = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Circles_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            circleSpeed = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Circles_Size");
        if (it != effectInfo.settings.end() && !it->second.empty())
            radius = std::atoi(it->second.c_str());

        bool plasma = false, radial = false, radial_3D = false;
        bool fade = false, bubbles = false, collide = false, bounce = false;

        it = effectInfo.settings.find("E_CHECKBOX_Circles_Plasma");
        if (it != effectInfo.settings.end()) plasma = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Circles_Radial");
        if (it != effectInfo.settings.end()) radial = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Circles_Linear_Fade");
        if (it != effectInfo.settings.end()) fade = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Circles_Bubbles");
        if (it != effectInfo.settings.end()) bubbles = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Circles_Collide");
        if (it != effectInfo.settings.end()) collide = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Circles_Bounce");
        if (it != effectInfo.settings.end()) bounce = (it->second == "1");

        // The native panel also has E_CHOICE_Circles_Type: "Radial", "Radial 3D",
        // "Concentric", "Concentric Plasma". Map these to the legacy boolean flags.
        it = effectInfo.settings.find("E_CHOICE_Circles_Type");
        if (it != effectInfo.settings.end()) {
            if (it->second == "Radial") radial = true;
            else if (it->second == "Radial 3D") { radial = true; radial_3D = true; }
            else if (it->second == "Concentric Plasma") plasma = true;
            // "Concentric" = default balls mode, no flags
        }

        if (number > MAX_RGB_BALLS) number = MAX_RGB_BALLS;
        if (number < 1) number = 1;

        size_t colorCnt = buf.GetColorCount();

        int start_x = buf.BufferWi / 2;
        int start_y = buf.BufferHt / 2;

        int effectState = (buf.curPeriod - buf.curEffStartPer) * circleSpeed * buf.frameTimeInMs / 50;

        // --- Radial rendering mode ---
        if (radial || radial_3D) {
            // Radial: concentric rings expanding outward from center
            int barht = buf.BufferHt / (radius + 1);
            if (barht < 1) barht = 1;
            int maxRadius = effectState > buf.BufferHt ? buf.BufferHt : effectState / 2 + radius;
            int blockHt = (int)colorCnt * barht;
            if (blockHt < 1) blockHt = 1;
            int f_offset = effectState / 4 % (blockHt + 1);

            xlColor lastColor = xlBLACK;
            for (int ii = maxRadius; ii >= 0; ii--) {
                int n = ii - f_offset + blockHt;
                int colorIdx = (n) % blockHt / barht;
                HSVValue hsv;
                buf.palette.GetHSV(colorIdx, hsv);

                if (radial_3D) {
                    hsv.hue = (float)(ii + effectState) / ((float)maxRadius / (float)number);
                    if (hsv.hue > 1.0) hsv.hue = hsv.hue - (long)hsv.hue;
                    hsv.saturation = 1.0;
                    hsv.value = 1.0;
                }
                xlColor color(hsv);
                if (lastColor != color) {
                    buf.DrawCircle(start_x, start_y, ii, color, true);
                    lastColor = color;
                }
            }
            return true;
        }

        // --- Ball physics mode (default, plasma, bubbles, bounce, collide) ---

        CirclesCache* cache = dynamic_cast<CirclesCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new CirclesCache();
            buf.infoCache[0] = cache;
        }

        RgbBalls* effectBalls = plasma
            ? reinterpret_cast<RgbBalls*>(cache->metaballs.data())
            : cache->balls.data();

        // Initialize or re-initialize balls when needed
        if (buf.needToInit || radius != effectBalls[0]._radius ||
            number != cache->numBalls || cache->metaType != plasma) {

            for (int ii = 0; ii < number; ii++) {
                int colorIdx = 0;
                float angle, spd;

                if (ii >= cache->numBalls || buf.needToInit) {
                    start_x = std::rand() % buf.BufferWi;
                    start_y = std::rand() % buf.BufferHt;
                    colorIdx = ii % (int)colorCnt;
                    angle = std::rand() % 2 ? (float)(std::rand() % 90) : -(float)(std::rand() % 90);
                    spd = (float)(std::rand() % 3 + 1);
                } else {
                    start_x = (int)effectBalls[ii]._x;
                    start_y = (int)effectBalls[ii]._y;
                    colorIdx = effectBalls[ii]._colorindex;
                    angle = effectBalls[ii]._angle;
                    spd = effectBalls[ii]._spd;
                }

                effectBalls[ii].Reset((float)start_x, (float)start_y, spd, angle,
                                      (float)radius, colorIdx);

                if (bubbles) {
                    angle = 90.0f + (float)(std::rand() % 45) - 22.5f;
                    angle *= 2.0f * (float)M_PI / 180.0f;
                    effectBalls[ii]._dx = spd * std::cos(angle);
                    effectBalls[ii]._dy = spd * std::sin(angle);
                }
            }
            cache->numBalls = number;
            cache->metaType = plasma;
            buf.needToInit = false;
        } else {
            // Update ball positions
            for (int ii = 0; ii < number; ii++) {
                effectBalls[ii].updatePosition(
                    (float)circleSpeed * (float)buf.frameTimeInMs / 200.0f,
                    buf.BufferWi, buf.BufferHt);
            }
        }

        // Bounce off walls
        if (bounce) {
            for (int ii = 0; ii < number; ii++) {
                effectBalls[ii].Bounce(buf.BufferWi, buf.BufferHt);
            }
        }

        // Collision detection placeholder (matches legacy — stub)
        if (collide) {
            // update position if two balls collided (not implemented in legacy)
        }

        // Render
        if (plasma) {
            // MetaBall rendering: evaluate metaball field for every pixel
            MetaBall* metaballs = cache->metaballs.data();
            for (int row = 0; row < buf.BufferHt; row++) {
                for (int col = 0; col < buf.BufferWi; col++) {
                    float sum = 0.0f;
                    HSVValue hsv;
                    hsv.hue = 0.0f;
                    hsv.saturation = 0.0f;
                    hsv.value = 0.0f;

                    for (int ii = 0; ii < cache->numBalls; ii++) {
                        float val = metaballs[ii].Equation((float)col, (float)row);
                        sum += val;
                        HSVValue temp;
                        buf.palette.GetHSV(metaballs[ii]._colorindex, temp);
                        if (val > 0.30f) {
                            temp.value = val > 1.0f ? 1.0f : val;
                            hsv = buf.Get2ColorAdditive(hsv, temp);
                        }
                    }
                    if (sum >= 0.90f) {
                        buf.SetPixel(col, row, xlColor(hsv));
                    }
                }
            }
        } else {
            // Standard ball rendering
            for (int ii = 0; ii < number; ii++) {
                HSVValue hsv;
                buf.palette.GetHSV(cache->balls[ii]._colorindex, hsv);
                xlColor color(hsv);
                if (fade) {
                    buf.DrawFadingCircle(
                        (int)cache->balls[ii]._x, (int)cache->balls[ii]._y,
                        (int)cache->balls[ii]._radius, color,
                        !bounce && !collide);
                } else {
                    buf.DrawCircle(
                        (int)cache->balls[ii]._x, (int)cache->balls[ii]._y,
                        (int)cache->balls[ii]._radius, color,
                        !bubbles, !bounce && !collide);
                }
            }
        }
        return true;
    }


    if (type == "Curtain") {
        // Native Curtain effect — port of legacy CurtainEffect::Render

        // --- Read settings ---
        int swag = 3;
        float curtainSpeed = 1.0f;
        bool repeat = false;
        int edge = 0;   // 0=left, 1=center, 2=right, 3=bottom, 4=middle, 5=top
        int effect = 0; // 0=open, 1=close, 2=open then close, 3=close then open

        auto it = effectInfo.settings.find("E_SLIDER_Curtain_Swag");
        if (it != effectInfo.settings.end() && !it->second.empty())
            swag = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Curtain_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            curtainSpeed = static_cast<float>(std::atof(it->second.c_str())) / 10.0f;

        it = effectInfo.settings.find("E_CHECKBOX_Curtain_Repeat");
        if (it != effectInfo.settings.end())
            repeat = (it->second == "1");

        it = effectInfo.settings.find("E_CHOICE_Curtain_Edge");
        if (it != effectInfo.settings.end()) {
            const std::string& ev = it->second;
            if (ev == "left")        edge = 0;
            else if (ev == "center") edge = 1;
            else if (ev == "right")  edge = 2;
            else if (ev == "bottom") edge = 3;
            else if (ev == "middle") edge = 4;
            else if (ev == "top")    edge = 5;
        }

        it = effectInfo.settings.find("E_CHOICE_Curtain_Effect");
        if (it != effectInfo.settings.end()) {
            const std::string& ev = it->second;
            if (ev == "open")              effect = 0;
            else if (ev == "close")        effect = 1;
            else if (ev == "open then close") effect = 2;
            else if (ev == "close then open") effect = 3;
        }

        // --- Build swag array ---
        std::vector<int> SwagArray;
        int swaglen = buf.BufferHt > 1 ? swag * buf.BufferWi / 40 : 0;
        if (swaglen > 0) {
            double a = double(buf.BufferHt - 1) / (double(swaglen) * double(swaglen));
            for (int x = 0; x < swaglen; x++) {
                SwagArray.push_back(int(a * x * x));
            }
        }

        // --- Compute position ---
        double position;
        if (repeat) {
            position = buf.GetEffectTimeIntervalPosition(curtainSpeed);
        } else {
            position = buf.GetEffectTimeIntervalPosition() * curtainSpeed;
            if (position > 1.0) position = 1.0;
        }

        // --- Curtain render cache for open/close direction tracking ---
        struct CurtainCache : public EffectRenderCache {
            int LastCurtainDir = 0;
            int LastCurtainLimit = 0;
        };

        CurtainCache* cache = dynamic_cast<CurtainCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new CurtainCache();
            buf.infoCache[0] = cache;
        }

        // --- Compute limits ---
        int xlimit, ylimit;
        if (effect < 2) {
            // open or close
            xlimit = static_cast<int>(position * buf.BufferWi);
            ylimit = static_cast<int>(position * buf.BufferHt);
        } else {
            // open then close / close then open
            xlimit = position <= 0.5
                ? static_cast<int>(position * 2 * buf.BufferWi)
                : static_cast<int>((position - 0.5) * 2 * buf.BufferWi);
            ylimit = position <= 0.5
                ? static_cast<int>(position * 2 * buf.BufferHt)
                : static_cast<int>((position - 0.5) * 2 * buf.BufferHt);
        }

        // --- Determine curtain direction ---
        int CurtainDir;
        if (buf.curPeriod == buf.curEffStartPer || effect < 2) {
            CurtainDir = effect % 2;
        } else if (xlimit < cache->LastCurtainLimit) {
            CurtainDir = 1 - cache->LastCurtainDir;
        } else {
            CurtainDir = cache->LastCurtainDir;
        }
        cache->LastCurtainDir = CurtainDir;
        cache->LastCurtainLimit = xlimit;

        if (CurtainDir == 0) {
            xlimit = buf.BufferWi - xlimit - 1;
            ylimit = buf.BufferHt - ylimit - 1;
        }

        // --- Lambda: DrawCurtain (horizontal) ---
        auto DrawCurtain = [&](bool LeftEdge, int lim) {
            for (int i = 0; i < lim; i++) {
                xlColor color;
                buf.GetMultiColorBlend(double(i) / double(buf.BufferWi), true, color);
                int x = LeftEdge ? buf.BufferWi - i - 1 : i;
                for (int y = buf.BufferHt - 1; y >= 0; y--) {
                    buf.SetPixel(x, y, color);
                }
            }
            // swag
            for (size_t i = 0; i < SwagArray.size(); i++) {
                int x = lim + static_cast<int>(i);
                xlColor color;
                buf.GetMultiColorBlend(double(x) / double(buf.BufferWi), true, color);
                if (LeftEdge) x = buf.BufferWi - x - 1;
                for (int y = buf.BufferHt - 1; y > SwagArray[i]; y--) {
                    buf.SetPixel(x, y, color);
                }
            }
        };

        // --- Lambda: DrawCurtainVertical ---
        auto DrawCurtainVertical = [&](bool topEdge, int lim) {
            for (int i = 0; i < lim; i++) {
                xlColor color;
                buf.GetMultiColorBlend(double(i) / double(buf.BufferHt), true, color);
                int y = topEdge ? buf.BufferHt - i - 1 : i;
                for (int x = buf.BufferWi - 1; x >= 0; x--) {
                    buf.SetPixel(x, y, color);
                }
            }
            // swag
            for (size_t i = 0; i < SwagArray.size(); i++) {
                int y = lim + static_cast<int>(i);
                xlColor color;
                buf.GetMultiColorBlend(double(y) / double(buf.BufferHt), true, color);
                if (topEdge) y = buf.BufferHt - y - 1;
                for (int x = buf.BufferWi - 1; x > SwagArray[i]; x--) {
                    buf.SetPixel(x, y, color);
                }
            }
        };

        // --- Render based on edge selection ---
        switch (edge) {
        case 0: // left
            DrawCurtain(true, xlimit);
            break;
        case 1: // center
        {
            int middle = (xlimit + 1) / 2;
            DrawCurtain(true, middle);
            DrawCurtain(false, middle);
        }
        break;
        case 2: // right
            DrawCurtain(false, xlimit);
            break;
        case 3: // bottom
            DrawCurtainVertical(true, ylimit);
            break;
        case 4: // middle
        {
            int middle = (ylimit + 1) / 2;
            DrawCurtainVertical(true, middle);
            DrawCurtainVertical(false, middle);
        }
        break;
        case 5: // top
            DrawCurtainVertical(false, ylimit);
            break;
        default:
            break;
        }

        return true;
    }


    if (type == "DMX") {
        // Native DMX effect: writes per-channel intensity values to pixels.
        //
        // Each DMX channel (1..48) maps to a pixel in the buffer at (chan-1, 0).
        // Channels support static slider values, value curves for animation,
        // and an invert checkbox that flips the value (255 - value).
        //
        // The legacy effect has two modes based on model string type:
        //   - Single Color: each channel -> one monochrome pixel
        //   - RGB (3-color): every 3 channels -> one RGB pixel
        // Without model-specific string type info in the native pipeline, we
        // default to Single Color mode (one channel per pixel), which is the
        // most general representation and what DMX fixtures typically expect.

        float eff_pos = buf.GetEffectTimeIntervalPosition();
        long startMS = buf.GetStartTimeMS();
        long endMS = buf.GetEndTimeMS();
        int numPixels = buf.BufferWi; // available pixel slots

        for (int ch = 1; ch <= 48; ++ch) {
            if (ch - 1 >= numPixels) break; // buffer exhausted

            std::string chStr = std::to_string(ch);
            int value = 0;
            bool resolved = false;

            // TODO: Re-enable when ValueCurve is available in native build
#if 0
            std::string vcKey = "E_VALUECURVE_DMX" + chStr;
            auto vcIt = effectInfo.settings.find(vcKey);
            if (vcIt != effectInfo.settings.end() && !vcIt->second.empty()) {
                ValueCurve vc;
                vc.SetDivisor(1.0f);
                vc.SetLimits(0, 255);
                vc.Deserialise(vcIt->second);
                if (vc.IsActive()) {
                    value = static_cast<int>(vc.GetOutputValueAt(eff_pos, startMS, endMS));
                    resolved = true;
                }
            }
#endif

            // Fall back to static slider value
            if (!resolved) {
                std::string sliderKey = "E_SLIDER_DMX" + chStr;
                auto slIt = effectInfo.settings.find(sliderKey);
                if (slIt != effectInfo.settings.end() && !slIt->second.empty()) {
                    value = std::atoi(slIt->second.c_str());
                }
            }

            // Clamp to valid DMX range
            if (value < 0) value = 0;
            if (value > 255) value = 255;

            // Apply invert if checkbox is set
            std::string invKey = "E_CHECKBOX_INVDMX" + chStr;
            auto invIt = effectInfo.settings.find(invKey);
            if (invIt != effectInfo.settings.end() && invIt->second == "1") {
                value = 255 - value;
            }

            // Write as monochrome pixel (single color mode)
            xlColor color(static_cast<uint8_t>(value),
                          static_cast<uint8_t>(value),
                          static_cast<uint8_t>(value));
            buf.SetPixel(ch - 1, 0, color);
        }
        return true;
    }


    if (type == "Duplicate") {
        // The Duplicate effect mirrors another model/layer's effect at the same time.
        // In legacy xLights, this is handled *outside* the effect Render() method:
        // Render.cpp detects the Duplicate effect, looks up the source model+layer,
        // finds the effect at the current time, then renders *that* effect instead,
        // optionally overriding buffer/timing/palette/color settings.
        //
        // The legacy DuplicateEffect::Render() itself just asserts false -- it should
        // never be called because the render pipeline replaces it before reaching
        // the effect rendering stage.
        //
        // For the native pipeline, proper Duplicate support requires:
        //   1. Reading E_CHOICE_Duplicate_Model to get the source model name
        //   2. Reading E_SPINCTRL_Duplicate_Layer to get the source layer (1-based)
        //   3. Querying IEffectProvider::getEffectAtTime() on the source element/layer
        //      at the current time to find the effect being duplicated
        //   4. Recursively calling renderNativeEffect() with the source effect's info
        //   5. Applying override flags:
        //      - E_CHECKBOX_Duplicate_Override_Buffer: replace B_* settings
        //      - E_CHECKBOX_Duplicate_Override_Timing: replace T_* settings
        //      - E_CHECKBOX_Duplicate_Override_Palette: replace C_BUTTON_Palette*/C_CHECKBOX_Palette*
        //      - E_CHECKBOX_Duplicate_Override_Color: replace remaining C_* settings
        //
        // This requires cross-element access via _effectProvider, which renderNativeEffect()
        // currently does not have (it only receives the EffectInstanceInfo and buffer).
        // Full implementation needs refactoring renderNativeEffect() to accept the
        // coordinator or provider pointer, or moving Duplicate resolution into
        // renderModelAtTime() (before the renderNativeEffect call), mirroring the
        // legacy approach in Render.cpp.
        //
        // Stub: identify the source effect and attempt to render it if the provider
        // is accessible. Otherwise, leave the buffer black (unrendered).

        // Read Duplicate settings
        std::string sourceModel;
        int sourceLayer = 1; // 1-based in settings, 0-based for provider

        auto it = effectInfo.settings.find("E_CHOICE_Duplicate_Model");
        if (it != effectInfo.settings.end()) {
            sourceModel = it->second;
        }
        it = effectInfo.settings.find("E_SPINCTRL_Duplicate_Layer");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            sourceLayer = std::atoi(it->second.c_str());
        }

        if (sourceModel.empty() || sourceLayer < 1) {
            return false; // Invalid configuration -- no source specified
        }

        // TODO: To fully implement, renderNativeEffect needs access to _effectProvider
        // so it can call:
        //   size_t srcElementIdx = _effectProvider->getElementIndex(sourceModel);
        //   EffectInstanceInfo srcEffect;
        //   _effectProvider->getEffectAtTime(srcElementIdx, sourceLayer - 1, currentTimeMS, srcEffect);
        //   // Apply override flags from effectInfo.settings to srcEffect
        //   renderNativeEffect(srcEffect, buf);
        //
        // For now, return false to indicate this effect type is not yet rendered.
        // The buffer stays black, which is the standard behavior for unimplemented effects.
        return false;
    }


    if (type == "Faces") {
        // Native Faces effect stub.
        //
        // The full Faces effect requires model face definitions (Coro/SingleNode/
        // NodeRange/Matrix types), timing track phoneme lookup, SetNodePixel(),
        // GetModel(), SubModel/ModelGroup resolution, PicturesEffect for Matrix
        // faces, and FacesRenderCache with node-name and image caches. None of
        // this infrastructure is wired into the native render pipeline yet.
        //
        // This stub draws a simple coro-style face using palette colors so the
        // effect is visible during preview. It uses the same geometric approach
        // as the legacy "Rendered" face type (FacesEffect::mouth / drawoutline).
        //
        // Palette mapping (matching legacy):
        //   Color 0 = mouth
        //   Color 1 = outline (if enabled)
        //   Color 2 = eyes

        int Ht = buf.BufferHt;
        int Wt = buf.BufferWi;
        if (Ht < 2 || Wt < 2) {
            // Buffer too small for geometry -- fill with first palette color
            xlColor c;
            buf.palette.GetColor(0, c);
            buf.Fill(c);
            return true;
        }

        // Read settings
        std::string phoneme = "rest";
        auto sit = effectInfo.settings.find("E_CHOICE_Faces_Phoneme");
        if (sit != effectInfo.settings.end() && !sit->second.empty()) {
            phoneme = sit->second;
        }

        bool outline = false;
        sit = effectInfo.settings.find("E_CHECKBOX_Faces_Outline");
        if (sit != effectInfo.settings.end() && sit->second == "1") {
            outline = true;
        }

        std::string eyes = "Auto";
        sit = effectInfo.settings.find("E_CHOICE_Faces_Eyes");
        if (sit != effectInfo.settings.end() && !sit->second.empty()) {
            eyes = sit->second;
        }

        // Get palette colors
        size_t colorcnt = buf.GetColorCount();
        xlColor mouthColor;
        buf.palette.GetColor(0, mouthColor);
        HSVValue mouthHSV = mouthColor.asHSV();

        xlColor outlineColor;
        buf.palette.GetColor(1 % colorcnt, outlineColor);
        HSVValue outlineHSV = outlineColor.asHSV();

        xlColor eyeColor;
        buf.palette.GetColor(2 % colorcnt, eyeColor);

        int maxH = Ht - 1;
        int maxW = Wt - 1;

        // ---- Draw outline (face border) ----
        if (outline) {
            for (int y = 3; y < Ht - 3; y++) {
                buf.SetPixel(0, y, outlineHSV);
                buf.SetPixel(Wt - 1, y, outlineHSV);
            }
            for (int x = 3; x < Wt - 3; x++) {
                buf.SetPixel(x, 0, outlineHSV);
                buf.SetPixel(x, Ht - 1, outlineHSV);
            }
            // Corner pixels
            buf.SetPixel(2, 1, outlineHSV);
            buf.SetPixel(1, 2, outlineHSV);
            buf.SetPixel(Wt - 3, 1, outlineHSV);
            buf.SetPixel(Wt - 2, 2, outlineHSV);
            buf.SetPixel(Wt - 3, Ht - 2, outlineHSV);
            buf.SetPixel(Wt - 2, Ht - 3, outlineHSV);
            buf.SetPixel(2, Ht - 2, outlineHSV);
            buf.SetPixel(1, Ht - 3, outlineHSV);
        }

        // ---- Draw eyes ----
        // Simple eye blink: "Auto" treated as open for this stub
        bool eyesClosed = (eyes == "Closed");
        bool eyesOff = (eyes == "(off)");
        int startDeg = eyesClosed ? 180 : 0;
        int endDeg = 360;

        if (!eyesOff) {
            double radius = maxW * 0.08;
            auto drawEyeCircle = [&](int xc, int yc) {
                for (int deg = startDeg; deg < endDeg; deg++) {
                    double t = ((double)deg * M_PI) / 180.0;
                    int px = (int)((double)xc + radius * std::cos(t));
                    int py = (int)((double)yc + radius * std::sin(t));
                    if (px >= 0 && px < Wt && py >= 0 && py < Ht) {
                        buf.SetPixel(px, py, eyeColor);
                    }
                }
            };
            int eyeY = (int)(0.5 + maxH * 0.75);
            drawEyeCircle((int)(0.5 + maxW * 0.33), eyeY); // left eye
            drawEyeCircle((int)(0.5 + maxW * 0.66), eyeY); // right eye
        }

        // ---- Draw mouth based on phoneme ----
        // Phoneme-to-index mapping (matches legacy)
        int phonemeIdx = 9; // rest
        if (phoneme == "AI") phonemeIdx = 0;
        else if (phoneme == "E") phonemeIdx = 1;
        else if (phoneme == "FV") phonemeIdx = 2;
        else if (phoneme == "L") phonemeIdx = 3;
        else if (phoneme == "MBP") phonemeIdx = 4;
        else if (phoneme == "O") phonemeIdx = 5;
        else if (phoneme == "U") phonemeIdx = 6;
        else if (phoneme == "WQ") phonemeIdx = 7;
        else if (phoneme == "etc") phonemeIdx = 8;
        else if (phoneme == "(off)") phonemeIdx = 10;

        int x1 = (int)(maxW * 0.25);
        int x2 = (int)(maxW * 0.75);
        int x3 = (int)(maxW * 0.30);
        int x4 = (int)(maxW * 0.70);

        int y1 = (int)(maxH * 0.48);
        int y2 = (int)(maxH * 0.40);
        int y3 = (int)(maxH * 0.25);
        int y4 = (int)(maxH * 0.20);
        int y5 = (int)(maxH * 0.30);

        // Helper: draw horizontal line for mouth bottom + vertical sides
        auto drawMouthLine = [&](int lx1, int lx2, int ly1, int ly2) {
            for (int x = lx1 + 1; x < lx2; x++) {
                buf.SetPixel(x, ly2, mouthHSV);
            }
            for (int y = ly2 + 1; y <= ly1; y++) {
                buf.SetPixel(lx1, y, mouthHSV);
                buf.SetPixel(lx2, y, mouthHSV);
            }
        };

        // Helper: draw rectangle mouth
        auto drawMouthRect = [&](int lx1, int lx2, int ly1, int ly2) {
            for (int y = ly1 + 1; y < ly2; y++) {
                buf.SetPixel(lx1, y, mouthHSV);
                buf.SetPixel(lx2, y, mouthHSV);
            }
            for (int x = lx1 + 1; x < lx2; x++) {
                buf.SetPixel(x, ly1, mouthHSV);
                buf.SetPixel(x, ly2, mouthHSV);
            }
        };

        // Helper: draw circle mouth
        auto drawMouthCircle = [&](int xc, int yc, double radius) {
            for (int deg = 0; deg < 360; deg++) {
                double t = ((double)deg * M_PI) / 180.0;
                int px = (int)((double)xc + radius * std::cos(t));
                int py = (int)((double)yc + radius * std::sin(t));
                if (px >= 0 && px < Wt && py >= 0 && py < Ht) {
                    buf.SetPixel(px, py, mouthHSV);
                }
            }
        };

        if (phonemeIdx != 10) { // not "(off)"
            switch (phonemeIdx) {
                case 0: // AI
                    drawMouthLine(x1, x2, y1, y2);
                    drawMouthLine(x1, x2, y1, y4);
                    break;
                case 1: // E
                case 3: // L
                    drawMouthLine(x1, x2, y1, y2);
                    drawMouthLine(x1, x2, y1, y3);
                    break;
                case 2: // FV
                    drawMouthLine(x1, x2, y1, y2);
                    drawMouthLine(x1, x2, y1, y2 - 1);
                    break;
                case 4: // MBP
                case 9: // rest
                    drawMouthLine(x1, x2, y1, y2);
                    break;
                case 5: // O
                case 6: // U
                case 7: { // WQ
                    int xc = (int)(0.5 + maxW * 0.50);
                    int yc = (y2 - y5) / 2 + y5;
                    double r = (std::min(Wt, Ht)) * 0.15; // O
                    if (phonemeIdx == 6) r = (std::min(Wt, Ht)) * 0.10; // U
                    if (phonemeIdx == 7) r = (std::min(Wt, Ht)) * 0.05; // WQ
                    drawMouthCircle(xc, yc, r);
                } break;
                case 8: // etc
                    drawMouthRect(x3, x4, y5, y2);
                    break;
                default:
                    break;
            }
        }

        return true;
    }


    if (type == "Fan") {
        // Native Fan effect — port of legacy FanEffect::Render
        constexpr double PI = 3.141592653589793238463;

        float eff_pos = buf.GetEffectTimeIntervalPosition();

        // Read settings with defaults matching legacy SetDefaultParameters
        int center_x = 50;
        int center_y = 50;
        int start_radius = 1;
        int end_radius = 10;
        int start_angle = 0;
        int revolutions = 720;
        int num_blades = 3;
        int blade_width = 100;
        int blade_angle = 90;
        int num_elements = 1;
        int element_width = 100;
        int duration = 80;
        int acceleration = 0;
        bool reverse_dir = false;
        bool blend_edges = false;
        bool scale = true;

        auto it = effectInfo.settings.find("E_SLIDER_Fan_CenterX");
        if (it != effectInfo.settings.end() && !it->second.empty())
            center_x = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fan_CenterY");
        if (it != effectInfo.settings.end() && !it->second.empty())
            center_y = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fan_Start_Radius");
        if (it != effectInfo.settings.end() && !it->second.empty())
            start_radius = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fan_End_Radius");
        if (it != effectInfo.settings.end() && !it->second.empty())
            end_radius = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fan_Start_Angle");
        if (it != effectInfo.settings.end() && !it->second.empty())
            start_angle = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fan_Revolutions");
        if (it != effectInfo.settings.end() && !it->second.empty())
            revolutions = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fan_Num_Blades");
        if (it != effectInfo.settings.end() && !it->second.empty())
            num_blades = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fan_Blade_Width");
        if (it != effectInfo.settings.end() && !it->second.empty())
            blade_width = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fan_Blade_Angle");
        if (it != effectInfo.settings.end() && !it->second.empty())
            blade_angle = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fan_Num_Elements");
        if (it != effectInfo.settings.end() && !it->second.empty())
            num_elements = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fan_Element_Width");
        if (it != effectInfo.settings.end() && !it->second.empty())
            element_width = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fan_Duration");
        if (it != effectInfo.settings.end() && !it->second.empty())
            duration = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Fan_Accel");
        if (it != effectInfo.settings.end() && !it->second.empty())
            acceleration = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_CHECKBOX_Fan_Reverse");
        if (it != effectInfo.settings.end())
            reverse_dir = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Fan_Blend_Edges");
        if (it != effectInfo.settings.end())
            blend_edges = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Fan_Scale");
        if (it != effectInfo.settings.end())
            scale = (it->second == "1");

        int num_colors = static_cast<int>(buf.palette.Size());
        if (num_colors == 0)
            num_colors = 1;

        xlColor color;
        HSVValue hsv;
        double eff_pos_adj = buf.calcAccel(eff_pos, acceleration);
        double revs = static_cast<double>(revolutions);

        double effect_duration = duration / 100.0;
        double radius_rampup = (1.0 - effect_duration) / 2.0;

        double radius1 = start_radius;
        double radius2 = end_radius;

        if (scale) {
            double bufferMax = std::max(buf.BufferHt, buf.BufferWi);
            radius1 = radius1 * (bufferMax / 200.0);
            radius2 = radius2 * (bufferMax / 200.0);
            start_radius = static_cast<int>(start_radius * (bufferMax / 200.0));
            end_radius = static_cast<int>(end_radius * (bufferMax / 200.0));
        }

        int xc_adj = (center_x - 50) * buf.BufferWi / 100;
        int yc_adj = (center_y - 50) * buf.BufferHt / 100;

        double blade_div_angle = 360.0 / static_cast<double>(num_blades);
        double blade_width_angle = blade_div_angle * static_cast<double>(blade_width) / 100.0;
        double color_angle = blade_width_angle / static_cast<double>(num_colors);
        double angle_offset = eff_pos_adj * revs;
        double element_angle = color_angle / static_cast<double>(num_elements);
        double element_size = element_angle * static_cast<double>(element_width) / 100.0;

        if (effect_duration < 1.0) {
            double radius_delta = std::abs(radius2 - radius1);
            if (eff_pos_adj < radius_rampup) {
                // blade growing
                double pct = 1.0 - (eff_pos_adj / radius_rampup);
                if (radius2 > radius1)
                    radius2 = radius2 - radius_delta * pct;
                else
                    radius2 = radius2 + radius_delta * pct;
            } else if (eff_pos_adj > (1.0 - radius_rampup)) {
                // blade shrinking
                double pct = (1.0 - eff_pos_adj) / radius_rampup;
                if (radius2 > radius1)
                    radius1 = radius2 - radius_delta * pct;
                else
                    radius1 = radius2 + radius_delta * pct;
            }
        }

        if (radius1 > radius2) {
            std::swap(radius1, radius2);
        }

        int max_radius = std::max(start_radius, end_radius);

        for (int x = 0; x < buf.BufferWi; x++) {
            int x1 = x - xc_adj - (buf.BufferWi / 2);
            for (int y = 0; y < buf.BufferHt; y++) {
                int y1 = y - yc_adj - (buf.BufferHt / 2);
                double r = std::hypot(x1, y1);
                if (r >= radius1 && r <= radius2) {
                    double degrees_twist = (r / max_radius) * blade_angle;
                    double theta = ((std::atan2(x1, y1) * 180.0 / PI)) + degrees_twist + start_angle;
                    if (reverse_dir) {
                        theta = angle_offset - theta + 180.0;
                    } else {
                        theta = theta + 180.0 + angle_offset;
                    }
                    if (theta < 0.0) {
                        theta += 360.0;
                    }
                    double current_blade = theta / blade_div_angle;
                    double current_blade_angle = theta - static_cast<double>(static_cast<int>(current_blade) * blade_div_angle);

                    if (current_blade_angle <= blade_width_angle) {
                        double current_element = current_blade_angle / element_angle;
                        double current_element_angle = current_blade_angle - static_cast<double>(static_cast<int>(current_element) * element_angle);

                        if (current_element_angle <= element_size) {
                            int color_index = static_cast<int>(current_blade_angle / color_angle);
                            buf.palette.GetColor(color_index, color);

                            double color_pct = 1.0 - ((std::abs(current_element_angle - (element_size / 2.0)) * 2.0) / element_size);

                            hsv = color.asHSV();

                            if (blend_edges) {
                                if (buf.allowAlpha) {
                                    color.alpha = static_cast<uint8_t>(255.0 * color_pct);
                                } else {
                                    hsv.value = hsv.value * color_pct;
                                    color = hsv;
                                }
                            }
                            buf.SetPixel(x, y, color);
                        }
                    }
                }
            }
        }
        return true;
    }


    if (type == "Fill") {
        // Native Fill effect — port of legacy FillEffect::Render
        //
        // Parameters:
        //   E_SLIDER_Fill_Position (0-100, default 100) - how far to fill
        //   E_CHOICE_Fill_Direction (Up/Down/Left/Right, default "Up")
        //   E_SLIDER_Fill_Band_Size (0-250, default 0) - band width for color bands
        //   E_SLIDER_Fill_Skip_Size (0-250, default 0) - gap between bands
        //   E_SLIDER_Fill_Offset (0-100, default 0) - start offset
        //   E_CHECKBOX_Fill_Offset_In_Pixels (default true) - offset unit
        //   E_CHECKBOX_Fill_Color_Time (default false) - color varies by time vs position
        //   E_CHECKBOX_Fill_Wrap (default true) - wrap around buffer

        // Read settings
        int position = 100;
        int BandSize = 0;
        int SkipSize = 0;
        int offset = 0;
        bool offsetInPixels = true;
        bool colorByTime = false;
        bool wrap = true;
        std::string directionStr = "Up";

        auto it = effectInfo.settings.find("E_SLIDER_Fill_Position");
        if (it != effectInfo.settings.end() && !it->second.empty())
            position = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_CHOICE_Fill_Direction");
        if (it != effectInfo.settings.end() && !it->second.empty())
            directionStr = it->second;

        it = effectInfo.settings.find("E_SLIDER_Fill_Band_Size");
        if (it != effectInfo.settings.end() && !it->second.empty())
            BandSize = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Fill_Skip_Size");
        if (it != effectInfo.settings.end() && !it->second.empty())
            SkipSize = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Fill_Offset");
        if (it != effectInfo.settings.end() && !it->second.empty())
            offset = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_CHECKBOX_Fill_Offset_In_Pixels");
        if (it != effectInfo.settings.end())
            offsetInPixels = (it->second == "1");

        it = effectInfo.settings.find("E_CHECKBOX_Fill_Color_Time");
        if (it != effectInfo.settings.end())
            colorByTime = (it->second == "1");

        it = effectInfo.settings.find("E_CHECKBOX_Fill_Wrap");
        if (it != effectInfo.settings.end())
            wrap = (it->second == "1");

        // Parse direction: 0=Up, 1=Down, 2=Left, 3=Right
        int Direction = 0;
        if (directionStr == "Down") Direction = 1;
        else if (directionStr == "Left") Direction = 2;
        else if (directionStr == "Right") Direction = 3;

        double pos_pct = static_cast<double>(position) / 100.0;
        float eff_pos = buf.GetEffectTimeIntervalPosition();
        size_t colorcnt = buf.GetColorCount();

        // Adjust offset based on direction and units
        switch (Direction) {
        default:
        case 0: // Up
        case 1: // Down
            if (!offsetInPixels) {
                offset = ((buf.BufferHt - 1) * offset) / 100;
            } else {
                if (buf.BufferHt > 0) offset %= buf.BufferHt;
            }
            break;
        case 2: // Left
        case 3: // Right
            if (!offsetInPixels) {
                offset = ((buf.BufferWi - 1) * offset) / 100;
            } else {
                if (buf.BufferWi > 0) offset %= buf.BufferWi;
            }
            break;
        }

        // Color banding state
        int color_size = BandSize + SkipSize;
        int current_color = 0;
        int current_pos = 0;
        int target;

        xlColor color;

        // Helper: get blended color from position across palette
        auto getColorFromPosition = [&](double pos, xlColor& c) {
            double color_val = pos * (colorcnt - 1);
            int color_int = static_cast<int>(color_val);
            double color_pct = color_val - static_cast<double>(color_int);
            int color2 = std::min(color_int + 1, static_cast<int>(colorcnt) - 1);
            if (color_int < color2) {
                buf.Get2ColorBlend(color_int, color2, std::min(color_pct, 1.0), c);
            } else {
                buf.palette.GetColor(color2, c);
            }
        };

        // Helper: advance band color position
        auto updateFillColor = [&](int& cpos, int& band_color, int csize, int shift) {
            if (shift == 0) return;
            if (shift > 0) {
                int index = 0;
                while (index < shift) {
                    cpos++;
                    if (cpos >= csize) {
                        band_color++;
                        band_color %= static_cast<int>(colorcnt);
                        cpos = 0;
                    }
                    index++;
                }
            } else {
                int index = 0;
                while (index > shift) {
                    cpos--;
                    if (cpos < 0) {
                        band_color++;
                        band_color %= static_cast<int>(colorcnt);
                        cpos = csize - 1;
                    }
                    index--;
                }
            }
        };

        // When no banding, use time-based or position-based color
        if (BandSize == 0) {
            getColorFromPosition(static_cast<double>(eff_pos), color);
        }

        switch (Direction) {
        default:
        case 0: { // Up
            if (buf.BufferHt > 0) offset %= buf.BufferHt;
            if (wrap) {
                target = static_cast<int>(buf.BufferHt * pos_pct + offset);
            } else {
                target = offset + static_cast<int>((buf.BufferHt - offset) * pos_pct);
            }
            for (int y = offset; y < target; y++) {
                if (BandSize > 0) {
                    color = xlBLACK;
                    if (current_pos < BandSize) {
                        buf.palette.GetColor(current_color, color);
                    }
                }
                int y_pos = y;
                if (y_pos >= buf.BufferHt) y_pos -= buf.BufferHt;
                if (!colorByTime) {
                    double p = 0;
                    if (buf.BufferHt + offset - 1 != 0) {
                        p = static_cast<double>(y) / static_cast<double>(buf.BufferHt + offset - 1);
                    }
                    getColorFromPosition(p, color);
                }
                for (int x = 0; x < buf.BufferWi; x++) {
                    buf.SetPixel(x, y_pos, color);
                }
                if (BandSize > 0) {
                    updateFillColor(current_pos, current_color, color_size, 1);
                }
            }
            break;
        }
        case 1: { // Down
            if (buf.BufferHt > 0) offset %= buf.BufferHt;
            if (wrap) {
                target = static_cast<int>(buf.BufferHt * (1.0 - pos_pct) - offset);
            } else {
                target = static_cast<int>((buf.BufferHt - offset) * (1.0 - pos_pct));
            }
            for (int y = buf.BufferHt - 1 - offset; y >= target; y--) {
                if (BandSize > 0) {
                    color = xlBLACK;
                    if (current_pos < BandSize) {
                        buf.palette.GetColor(current_color, color);
                    }
                }
                int y_pos = y;
                if (y_pos < 0) y_pos += buf.BufferHt;
                if (!colorByTime) {
                    double p = 1.0;
                    if (buf.BufferHt + offset - 1 != 0) {
                        p = 1.0 - static_cast<double>(y) / static_cast<double>(buf.BufferHt + offset - 1);
                    }
                    getColorFromPosition(p, color);
                }
                for (int x = 0; x < buf.BufferWi; x++) {
                    buf.SetPixel(x, y_pos, color);
                }
                if (BandSize > 0) {
                    updateFillColor(current_pos, current_color, color_size, 1);
                }
            }
            break;
        }
        case 2: { // Left
            if (buf.BufferWi > 0) offset %= buf.BufferWi;
            if (wrap) {
                target = static_cast<int>(buf.BufferWi * (1.0 - pos_pct) - offset);
            } else {
                target = static_cast<int>((buf.BufferWi - offset) * (1.0 - pos_pct));
            }
            for (int x = buf.BufferWi - 1 - offset; x >= target; x--) {
                if (BandSize > 0) {
                    color = xlBLACK;
                    if (current_pos < BandSize) {
                        buf.palette.GetColor(current_color, color);
                    }
                }
                int x_pos = x;
                if (x_pos < 0) x_pos += buf.BufferWi;
                if (!colorByTime) {
                    double p = 1.0;
                    if (buf.BufferWi + offset - 1 != 0) {
                        p = 1.0 - static_cast<double>(x) / static_cast<double>(buf.BufferWi + offset - 1);
                    }
                    getColorFromPosition(p, color);
                }
                for (int y = 0; y < buf.BufferHt; y++) {
                    buf.SetPixel(x_pos, y, color);
                }
                if (BandSize > 0) {
                    updateFillColor(current_pos, current_color, color_size, 1);
                }
            }
            break;
        }
        case 3: { // Right
            if (buf.BufferWi > 0) offset %= buf.BufferWi;
            if (wrap) {
                target = static_cast<int>(buf.BufferWi * pos_pct + offset);
            } else {
                target = offset + static_cast<int>((buf.BufferWi - offset) * pos_pct);
            }
            for (int x = offset; x < target; x++) {
                if (BandSize > 0) {
                    color = xlBLACK;
                    if (current_pos < BandSize) {
                        buf.palette.GetColor(current_color, color);
                    }
                }
                int x_pos = x;
                if (x_pos >= buf.BufferWi) x_pos -= buf.BufferWi;
                if (!colorByTime) {
                    double p = 0;
                    if (buf.BufferWi + offset - 1 != 0) {
                        p = static_cast<double>(x) / static_cast<double>(buf.BufferWi + offset - 1);
                    }
                    getColorFromPosition(p, color);
                }
                for (int y = 0; y < buf.BufferHt; y++) {
                    buf.SetPixel(x_pos, y, color);
                }
                if (BandSize > 0) {
                    updateFillColor(current_pos, current_color, color_size, 1);
                }
            }
            break;
        }
        }

        return true;
    }


    if (type == "Fireworks") {
        // Native Fireworks effect — port of legacy FireworksEffect::Render
        // Full particle physics with gravity, velocity, fade. Audio-reactive
        // features (GrowWithMusic, FireTiming) are stubbed.

        // ------------------------------------------------------------------
        // Particle system classes (local to this block)
        // ------------------------------------------------------------------

        struct NativeFireworkParticle {
            double x, y, vx, vy;
            int fade;
            bool gravity;
            int colourIndex;
            bool holdColour;
            HSVValue startColour;
            int width, height;
            double fps;
            int age = 0;

            NativeFireworkParticle(int px, int py, double pvx, double pvy,
                                   int pfade, bool pgravity, int pColourIndex,
                                   bool pHoldColour, double velocity,
                                   int pWidth, int pHeight, int frameMS,
                                   const PaletteClass& palette)
                : x(px), y(py), fade(pfade), gravity(pgravity),
                  colourIndex(pColourIndex), holdColour(pHoldColour),
                  width(pWidth), height(pHeight)
            {
                if (holdColour) {
                    palette.GetHSV(colourIndex, startColour);
                }
                fps = 1000.0 / frameMS;

                double explosionVelocity =
                    (std::rand() - RAND_MAX / 2) * velocity / (RAND_MAX / 2);
                double angle = 2.0 * M_PI * std::rand() / RAND_MAX;
                vx = 3.0 * pvx / 100.0 + explosionVelocity * std::cos(angle);
                vy = 3.0 * -pvy / 100.0 + explosionVelocity * std::sin(angle);
            }

            bool Done() const {
                return (fade < age * 2 || x < 0 || y < 0 ||
                        x > width || (!gravity && y > height));
            }

            void Advance() {
                x += vx;
                if (gravity) {
                    vy += 0.98 / fps;
                }
                y += -vy;
                age++;
            }

            int GetX() const { return static_cast<int>(x); }
            int GetY() const { return static_cast<int>(y); }

            xlColor GetColour(const PaletteClass& palette, bool alpha) const {
                double v = ((10.0 * fade) - age * 20.0) / (10.0 * fade);
                if (v < 0.0) v = 0.0;

                HSVValue cv = startColour;
                if (holdColour) {
                    if (alpha) {
                        xlColor c(cv);
                        c.alpha = static_cast<uint8_t>(255.0 * v);
                        return c;
                    } else {
                        cv.value = v;
                        return xlColor(cv);
                    }
                } else {
                    palette.GetHSV(colourIndex, cv);
                    if (alpha) {
                        xlColor c(cv);
                        c.alpha = static_cast<uint8_t>(255.0 * v);
                        return c;
                    } else {
                        cv.value = v;
                        return xlColor(cv);
                    }
                }
            }
        };

        struct NativeFirework {
            enum { MAX_CYCLES = 500 };
            int cycles = 0;
            mutable bool done = false;
            std::vector<NativeFireworkParticle> particles;

            NativeFirework(int numParticles, int px, int py, double pvx, double pvy,
                           int pfade, bool pgravity, int pColourIndex,
                           bool pHoldColour, double velocity,
                           int pWidth, int pHeight, int frameMS,
                           const PaletteClass& palette)
            {
                particles.reserve(numParticles);
                for (int i = 0; i < numParticles; i++) {
                    particles.emplace_back(px, py, pvx, pvy, pfade, pgravity,
                                           pColourIndex, pHoldColour, velocity,
                                           pWidth, pHeight, frameMS, palette);
                }
            }

            void Advance() {
                cycles++;
                for (auto& p : particles) {
                    p.Advance();
                }
                if (Done()) particles.clear();
            }

            bool AllGone() const {
                for (const auto& p : particles) {
                    if (!p.Done()) return false;
                }
                done = true;
                return true;
            }

            bool Done() const {
                return done || cycles >= MAX_CYCLES || AllGone();
            }
        };

        struct FireworksCache : public EffectRenderCache {
            int sinceLastTriggered = 0;
            std::list<NativeFirework> fireworks;
            std::vector<int> firePeriods;
        };

        // ------------------------------------------------------------------
        // Read settings from effectInfo.settings (keys use E_ prefix)
        // ------------------------------------------------------------------

        // Number of explosions over the effect duration
        int numberOfExplosions = 10;
        auto it = effectInfo.settings.find("E_SLIDER_Fireworks_Count");
        if (it != effectInfo.settings.end() && !it->second.empty())
            numberOfExplosions = std::atoi(it->second.c_str());

        // Particles per explosion
        int particleCount = 25;
        it = effectInfo.settings.find("E_SLIDER_Fireworks_Particles");
        if (it != effectInfo.settings.end() && !it->second.empty())
            particleCount = std::atoi(it->second.c_str());

        // Particle velocity (explosion force)
        double particleVelocity = 2.0;
        it = effectInfo.settings.find("E_SLIDER_Fireworks_Velocity");
        if (it != effectInfo.settings.end() && !it->second.empty())
            particleVelocity = std::atof(it->second.c_str());

        // Fade duration
        int fade = 50;
        it = effectInfo.settings.find("E_SLIDER_Fireworks_Fade");
        if (it != effectInfo.settings.end() && !it->second.empty())
            fade = std::atoi(it->second.c_str());

        // X/Y directional velocity bias
        int xVelocity = 0;
        it = effectInfo.settings.find("E_SLIDER_Fireworks_XVelocity");
        if (it != effectInfo.settings.end() && !it->second.empty())
            xVelocity = std::atoi(it->second.c_str());

        int yVelocity = 0;
        it = effectInfo.settings.find("E_SLIDER_Fireworks_YVelocity");
        if (it != effectInfo.settings.end() && !it->second.empty())
            yVelocity = std::atoi(it->second.c_str());

        // X/Y location override (-1 = random)
        int xLocation = -1;
        it = effectInfo.settings.find("E_SLIDER_Fireworks_XLocation");
        if (it != effectInfo.settings.end() && !it->second.empty())
            xLocation = std::atoi(it->second.c_str());

        int yLocation = -1;
        it = effectInfo.settings.find("E_SLIDER_Fireworks_YLocation");
        if (it != effectInfo.settings.end() && !it->second.empty())
            yLocation = std::atoi(it->second.c_str());

        // Gravity toggle (native panel key: E_CHECKBOX_Fireworks_Fade, labeled "Gravity")
        bool gravity = true;
        it = effectInfo.settings.find("E_CHECKBOX_Fireworks_Fade");
        if (it != effectInfo.settings.end())
            gravity = (it->second == "1");

        // Hold color toggle
        bool holdColour = true;
        it = effectInfo.settings.find("E_CHECKBOX_Fireworks_HoldColour");
        if (it != effectInfo.settings.end())
            holdColour = (it->second == "1");

        // UseMusic — stubbed (audio-reactive not yet wired)
        bool useMusic = false;
        it = effectInfo.settings.find("E_CHECKBOX_Fireworks_UseMusic");
        if (it != effectInfo.settings.end())
            useMusic = (it->second == "1");
        // Force off — no audio access in native pipeline yet
        useMusic = false;

        // FireTiming — stubbed (timing track access not wired)
        bool useTiming = false;

        // ------------------------------------------------------------------
        // Render cache — persists particle state across frames
        // ------------------------------------------------------------------

        FireworksCache* cache = dynamic_cast<FireworksCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new FireworksCache();
            buf.infoCache[0] = cache;
        }

        auto& sinceLastTriggered = cache->sinceLastTriggered;
        auto& fireworks = cache->fireworks;
        auto& firePeriods = cache->firePeriods;

        size_t colorcnt = buf.GetColorCount();
        if (colorcnt == 0) colorcnt = 1;

        // ------------------------------------------------------------------
        // Helper lambda: compute firework start location
        // Port of FireworksEffect::GetFireworkLocation
        // ------------------------------------------------------------------
        auto getFireworkLocation = [](int width, int height,
                                      int overridex, int overridey)
            -> std::pair<int, int>
        {
            int startX, startY;
            if (overridex >= 0) {
                startX = overridex * width / 100;
            } else {
                int x25 = static_cast<int>(0.25f * width);
                int x75 = static_cast<int>(0.75f * width);
                startX = (x75 - x25 > 0) ? x25 + std::rand() % (x75 - x25) : 0;
            }
            if (overridey >= 0) {
                startY = overridey * height / 100;
            } else {
                int y25 = static_cast<int>(0.25f * height);
                int y75 = static_cast<int>(0.75f * height);
                startY = (y75 - y25 > 0) ? y25 + std::rand() % (y75 - y25) : 0;
            }
            return { startX, startY };
        };

        // ------------------------------------------------------------------
        // Initialization: schedule explosion times on first frame
        // ------------------------------------------------------------------

        if (buf.needToInit) {
            buf.needToInit = false;
            sinceLastTriggered = 0;
            fireworks.clear();
            firePeriods.clear();

            if (!useMusic && !useTiming) {
                // Pre-schedule random explosion periods across the effect duration
                int startPer, endPer;
                buf.GetEffectPeriods(startPer, endPer);
                for (int i = 0; i < numberOfExplosions; i++) {
                    double r = static_cast<double>(std::rand()) / RAND_MAX;
                    firePeriods.push_back(
                        startPer + static_cast<int>(r * (endPer - startPer)));
                }
            }
        }

        // ------------------------------------------------------------------
        // Trigger new fireworks based on mode
        // ------------------------------------------------------------------

        // useMusic path — stubbed, will not trigger (useMusic forced false above)

        // useTiming path — stubbed, will not trigger

        // Normal (pre-scheduled) path
        if (!useTiming && !useMusic && !firePeriods.empty()) {
            for (const auto& period : firePeriods) {
                if (period == buf.curPeriod) {
                    auto location = getFireworkLocation(
                        buf.BufferWi, buf.BufferHt, xLocation, yLocation);
                    int colourIndex = std::rand() % static_cast<int>(colorcnt);
                    fireworks.emplace_back(
                        particleCount,
                        location.first, location.second,
                        static_cast<double>(xVelocity),
                        static_cast<double>(yVelocity),
                        fade, gravity,
                        colourIndex, holdColour,
                        particleVelocity,
                        buf.BufferWi, buf.BufferHt,
                        buf.frameTimeInMs, buf.palette);
                }
            }
        }

        // ------------------------------------------------------------------
        // Advance and render all active fireworks
        // ------------------------------------------------------------------

        for (auto& fw : fireworks) {
            if (!fw.Done()) {
                for (const auto& p : fw.particles) {
                    if (!p.Done()) {
                        buf.SetPixel(p.GetX(), p.GetY(),
                                     p.GetColour(buf.palette, buf.allowAlpha));
                    }
                }
                fw.Advance();
            }
        }

        // Prune completed fireworks to avoid unbounded list growth
        fireworks.remove_if([](const NativeFirework& fw) { return fw.Done(); });

        return true;
    }


    if (type == "Galaxy") {
        // Native Galaxy effect — complex spiral rotation with acceleration.
        // Faithfully ported from legacy GalaxyEffect::Render().

        int center_x = 50, center_y = 50;
        int start_radius = 1, end_radius = 10;
        int start_angle = 0;
        int revolutions = 1440;
        int start_width = 5, end_width = 5;
        int duration = 20;
        int acceleration = 0;
        bool reverse_dir = false;
        bool blend_edges = true;
        bool inward = false;
        bool scale = true;

        auto getSetting = [&](const char* key) -> const std::string* {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty())
                return &it->second;
            return nullptr;
        };

        if (auto* v = getSetting("E_SLIDER_Galaxy_CenterX"))   center_x = std::atoi(v->c_str());
        if (auto* v = getSetting("E_SLIDER_Galaxy_CenterY"))   center_y = std::atoi(v->c_str());
        if (auto* v = getSetting("E_SLIDER_Galaxy_Start_Radius")) start_radius = std::atoi(v->c_str());
        if (auto* v = getSetting("E_SLIDER_Galaxy_End_Radius"))   end_radius = std::atoi(v->c_str());
        if (auto* v = getSetting("E_SLIDER_Galaxy_Start_Angle"))  start_angle = std::atoi(v->c_str());
        if (auto* v = getSetting("E_SLIDER_Galaxy_Revolutions"))  revolutions = std::atoi(v->c_str());
        if (auto* v = getSetting("E_SLIDER_Galaxy_Start_Width"))  start_width = std::atoi(v->c_str());
        if (auto* v = getSetting("E_SLIDER_Galaxy_End_Width"))    end_width = std::atoi(v->c_str());
        if (auto* v = getSetting("E_SLIDER_Galaxy_Duration"))     duration = std::atoi(v->c_str());
        if (auto* v = getSetting("E_SLIDER_Galaxy_Accel"))        acceleration = std::atoi(v->c_str());

        if (auto* v = getSetting("E_CHECKBOX_Galaxy_Reverse"))     reverse_dir = (*v == "1");
        if (auto* v = getSetting("E_CHECKBOX_Galaxy_Blend_Edges")) blend_edges = (*v == "1");
        if (auto* v = getSetting("E_CHECKBOX_Galaxy_Inward"))      inward = (*v == "1");
        // Galaxy_Scale defaults to true; only set false if explicitly "0"
        if (auto* v = getSetting("E_CHECKBOX_Galaxy_Scale"))       scale = (*v != "0");

        if (revolutions == 0)
            return true;

        int bufferWi = buf.BufferWi;
        int bufferHt = buf.BufferHt;
        int num_colors = static_cast<int>(buf.palette.Size());

        // Temp buffers for blend_edges mode
        std::vector<std::vector<double>> temp_colors_pct(bufferWi, std::vector<double>(bufferHt, 0.0));
        std::vector<std::vector<double>> pixel_age(bufferWi, std::vector<double>(bufferHt, 0.0));

        double eff_pos = buf.GetEffectTimeIntervalPosition();
        double eff_pos_adj = buf.calcAccel(eff_pos, acceleration);
        double revs = static_cast<double>(revolutions);

        double pos_x = bufferWi * center_x / 100.0;
        double pos_y = bufferHt * center_y / 100.0;

        double head_duration = duration / 100.0;
        double tail_length = revs * (1.0 - head_duration);
        double color_length = tail_length / num_colors;
        if (color_length < 1.0)
            color_length = 1.0;

        double tail_end_of_tail = ((revs + tail_length) * eff_pos_adj) - tail_length;
        double head_end_of_tail = tail_end_of_tail + tail_length;

        double radius1 = start_radius;
        double radius2 = end_radius;
        double width1 = start_width;
        double width2 = end_width;

        if (scale) {
            double bufferMax = std::max(bufferHt, bufferWi);
            radius1 = radius1 * (bufferMax / 200.0);
            radius2 = radius2 * (bufferMax / 200.0);
            width1 = width1 * (bufferMax / 100.0);
            width2 = width2 * (bufferMax / 100.0);
        }

        constexpr double PI = 3.14159265358979323846;
        auto toRadians = [](double degrees) -> double { return degrees * PI / 180.0; };

        auto getStep = [&](double radius) -> double {
            if (radius < 5.0) return 0.1;
            return (0.5 * 360.0 / (2.0 * PI * radius));
        };

        // Helper: compute endpoint color from palette position
        auto calcEndpointColor = [&](double end_ang, double /*start_ang*/,
                                     double head_eot, double col_len,
                                     int ncols) -> xlColor {
            double cv = (head_eot - end_ang) / col_len;
            int ci = static_cast<int>(cv);
            double cp = cv - static_cast<double>(ci);
            int c2 = std::min(ci + 1, ncols - 1);
            xlColor color;
            if (ci < c2) {
                buf.Get2ColorBlend(ci, c2, std::min(cp, 1.0), color);
            } else {
                buf.palette.GetColor(c2, color);
            }
            return color;
        };

        double half_width = 1.0;

        buf.ClearTempBuf();

        double last_check = (inward ? std::min(head_end_of_tail, revs)
                                    : std::max(0.0, tail_end_of_tail))
                            + static_cast<double>(start_angle);

        // =====================================================================
        // Section 1: Round off the first endpoint (head when inward, tail otherwise)
        // =====================================================================
        double adj_angle;
        double end_angle = inward ? std::min(head_end_of_tail, revs)
                                  : std::max(0.0, tail_end_of_tail);
        xlColor color = calcEndpointColor(end_angle, start_angle,
                                          head_end_of_tail, color_length, num_colors);
        double pct1 = end_angle / revs;
        double current_radius = radius2 * pct1 + radius1 * (1.0 - pct1);
        double current_width = width2 * pct1 + width1 * (1.0 - pct1);
        double current_delta = 0.0;
        double current_distance = 0.0;
        half_width = current_width / 2.0;
        double step = getStep(current_radius + half_width);

        if (current_radius >= half_width && half_width > 0.0) {
            for (double i = end_angle; current_distance <= half_width;
                 (inward ? i += step : i -= step)) {
                adj_angle = i + static_cast<double>(start_angle);
                if (reverse_dir) adj_angle *= -1.0;
                current_delta = std::abs(end_angle - i);
                current_distance = (2.0 * PI * current_radius * current_delta) / 360.0;
                HSVValue hsv(color);
                double full_brightness = hsv.value;
                if (half_width > current_distance) {
                    current_width = std::sqrt(half_width * half_width
                                              - current_distance * current_distance);
                    double inside_radius = std::max(0.0, current_radius - current_width);
                    for (double r = inside_radius;; r += 0.5) {
                        if (r > current_radius) r = current_radius;
                        double x1 = std::sin(toRadians(adj_angle)) * r + pos_x;
                        double y1 = std::cos(toRadians(adj_angle)) * r + pos_y;
                        double outside_radius = current_radius + (current_radius - r);
                        double x2 = std::sin(toRadians(adj_angle)) * outside_radius + pos_x;
                        double y2 = std::cos(toRadians(adj_angle)) * outside_radius + pos_y;
                        double head_fade_pct = std::clamp(
                            1.0 - (current_distance / half_width), 0.0, 1.0);
                        double color_pct2 = ((r - inside_radius)
                                             / (current_radius - inside_radius))
                                            * head_fade_pct;
                        if (blend_edges) {
                            if (hsv.value > 0.0) {
                                int ix1 = static_cast<int>(x1);
                                int iy1 = static_cast<int>(y1);
                                int ix2 = static_cast<int>(x2);
                                int iy2 = static_cast<int>(y2);
                                if (ix1 >= 0 && ix1 < bufferWi && iy1 >= 0 && iy1 < bufferHt) {
                                    buf.SetTempPixel(ix1, iy1, color);
                                    temp_colors_pct[ix1][iy1] = color_pct2;
                                }
                                if (ix2 >= 0 && ix2 < bufferWi && iy2 >= 0 && iy2 < bufferHt) {
                                    buf.SetTempPixel(ix2, iy2, color);
                                    temp_colors_pct[ix2][iy2] = color_pct2;
                                }
                            }
                        } else {
                            hsv.value = full_brightness * color_pct2;
                            if (hsv.value > 0.0) {
                                buf.SetPixel(static_cast<int>(x1), static_cast<int>(y1), hsv);
                                buf.SetPixel(static_cast<int>(x2), static_cast<int>(y2), hsv);
                            }
                        }
                        if (r >= current_radius) break;
                    }
                }
                step = getStep(current_radius + half_width);
            }
        }

        // =====================================================================
        // Section 2: Draw the main Galaxy spiral
        // =====================================================================
        for (double i = (inward ? std::min(head_end_of_tail, revs)
                                : std::max(0.0, tail_end_of_tail));
             (inward ? i >= std::max(0.0, tail_end_of_tail)
                     : i <= std::min(head_end_of_tail, revs));
             (inward ? i -= step : i += step)) {

            double adj_angle = i + static_cast<double>(start_angle);
            if (reverse_dir) adj_angle *= -1.0;

            double color_val = (head_end_of_tail - i) / color_length;
            int color_int = static_cast<int>(color_val);
            double color_pct = color_val - static_cast<double>(color_int);
            int color2 = std::min(color_int + 1, num_colors - 1);
            if (color_int < color2) {
                buf.Get2ColorBlend(color_int, color2, std::min(color_pct, 1.0), color);
            } else {
                buf.palette.GetColor(color2, color);
            }
            HSVValue hsv(color);
            double full_brightness = hsv.value;
            double pct = i / revs;
            current_radius = radius2 * pct + radius1 * (1.0 - pct);
            double cw = width2 * pct + width1 * (1.0 - pct);
            half_width = cw / 2.0;
            double inside_radius = current_radius - half_width;

            for (double r = inside_radius;; r += 0.5) {
                if (r > current_radius) r = current_radius;
                double x1 = std::sin(toRadians(adj_angle)) * r + pos_x;
                double y1 = std::cos(toRadians(adj_angle)) * r + pos_y;
                double outside_radius = current_radius + (current_radius - r);
                double x2 = std::sin(toRadians(adj_angle)) * outside_radius + pos_x;
                double y2 = std::cos(toRadians(adj_angle)) * outside_radius + pos_y;
                double color_pct2 = (r - inside_radius) / (current_radius - inside_radius);

                if (blend_edges) {
                    if (hsv.value > 0.0) {
                        int ix1 = static_cast<int>(x1);
                        int iy1 = static_cast<int>(y1);
                        int ix2 = static_cast<int>(x2);
                        int iy2 = static_cast<int>(y2);
                        if (ix1 >= 0 && ix1 < bufferWi && iy1 >= 0 && iy1 < bufferHt) {
                            buf.SetTempPixel(ix1, iy1, color);
                            temp_colors_pct[ix1][iy1] = color_pct2;
                            pixel_age[ix1][iy1] = std::abs(adj_angle);
                        }
                        if (ix2 >= 0 && ix2 < bufferWi && iy2 >= 0 && iy2 < bufferHt) {
                            buf.SetTempPixel(ix2, iy2, color);
                            temp_colors_pct[ix2][iy2] = color_pct2;
                            pixel_age[ix2][iy2] = std::abs(adj_angle);
                        }
                    }
                } else {
                    hsv.value = full_brightness * color_pct2;
                    if (hsv.value > 0.0) {
                        buf.SetPixel(static_cast<int>(x1), static_cast<int>(y1), hsv);
                        buf.SetPixel(static_cast<int>(x2), static_cast<int>(y2), hsv);
                    }
                }
                if (r >= current_radius) break;
            }

            // Periodically blend old temp data into final buffer (every 90 degrees)
            if (blend_edges &&
                ((inward ? (last_check - std::abs(adj_angle))
                         : (std::abs(adj_angle) - last_check)) >= 90.0)) {
                for (int x = 0; x < bufferWi; x++) {
                    for (int y = 0; y < bufferHt; y++) {
                        if (temp_colors_pct[x][y] > 0.0 &&
                            ((inward ? (pixel_age[x][y] - std::abs(adj_angle))
                                     : (std::abs(adj_angle) - pixel_age[x][y])) >= 180.0)) {
                            xlColor c_new;
                            buf.GetTempPixel(x, y, c_new);
                            xlColor c_old;
                            buf.GetPixel(x, y, c_old);
                            xlColor blended;
                            buf.Get2ColorAlphaBlend(c_old, c_new,
                                                    temp_colors_pct[x][y], blended);
                            buf.SetPixel(x, y, blended);
                            temp_colors_pct[x][y] = 0.0;
                            pixel_age[x][y] = 0.0;
                        }
                    }
                }
                last_check = std::abs(adj_angle);
            }
            step = getStep(current_radius + half_width);
        }

        // =====================================================================
        // Section 3: Round off the second endpoint
        // =====================================================================
        end_angle = inward ? std::max(0.1, tail_end_of_tail)
                           : std::min(head_end_of_tail, revs);
        color = calcEndpointColor(end_angle, start_angle,
                                  head_end_of_tail, color_length, num_colors);
        current_distance = 0.0;
        if (current_radius >= half_width && half_width > 0.0) {
            for (double i = end_angle; current_distance <= half_width;
                 (inward ? i -= step : i += step)) {
                adj_angle = i + static_cast<double>(start_angle);
                if (reverse_dir) adj_angle *= -1.0;
                current_delta = std::abs(end_angle - i);
                current_distance = (2.0 * PI * current_radius * current_delta) / 360.0;
                HSVValue hsv(color);
                double full_brightness = hsv.value;
                if (half_width > current_distance) {
                    current_width = std::sqrt(half_width * half_width
                                              - current_distance * current_distance);
                    double inside_radius = std::max(0.0, current_radius - current_width);
                    for (double r = inside_radius;; r += 0.5) {
                        if (r > current_radius) r = current_radius;
                        double x1 = std::sin(toRadians(adj_angle)) * r + pos_x;
                        double y1 = std::cos(toRadians(adj_angle)) * r + pos_y;
                        double outside_radius = current_radius + (current_radius - r);
                        double x2 = std::sin(toRadians(adj_angle)) * outside_radius + pos_x;
                        double y2 = std::cos(toRadians(adj_angle)) * outside_radius + pos_y;
                        double head_fade_pct = std::clamp(
                            1.0 - (current_distance / half_width), 0.0, 1.0);
                        double color_pct2 = ((r - inside_radius)
                                             / (current_radius - inside_radius))
                                            * head_fade_pct;
                        if (blend_edges) {
                            if (hsv.value > 0.0) {
                                int ix1 = static_cast<int>(x1);
                                int iy1 = static_cast<int>(y1);
                                int ix2 = static_cast<int>(x2);
                                int iy2 = static_cast<int>(y2);
                                if (ix1 >= 0 && ix1 < bufferWi && iy1 >= 0 && iy1 < bufferHt) {
                                    buf.SetTempPixel(ix1, iy1, color);
                                    temp_colors_pct[ix1][iy1] = color_pct2;
                                }
                                if (ix2 >= 0 && ix2 < bufferWi && iy2 >= 0 && iy2 < bufferHt) {
                                    buf.SetTempPixel(ix2, iy2, color);
                                    temp_colors_pct[ix2][iy2] = color_pct2;
                                }
                            }
                        } else {
                            hsv.value = full_brightness * color_pct2;
                            if (hsv.value > 0.0) {
                                buf.SetPixel(static_cast<int>(x1), static_cast<int>(y1), hsv);
                                buf.SetPixel(static_cast<int>(x2), static_cast<int>(y2), hsv);
                            }
                        }
                        if (r >= current_radius) break;
                    }
                }
                step = getStep(current_radius + half_width);
            }
        }

        // =====================================================================
        // Section 4: Final blend of remaining temp buffer data
        // =====================================================================
        if (blend_edges) {
            for (int x = 0; x < bufferWi; x++) {
                for (int y = 0; y < bufferHt; y++) {
                    if (temp_colors_pct[x][y] > 0.0) {
                        xlColor c_new;
                        buf.GetTempPixel(x, y, c_new);
                        xlColor c_old;
                        buf.GetPixel(x, y, c_old);
                        xlColor blended;
                        buf.Get2ColorAlphaBlend(c_old, c_new,
                                                temp_colors_pct[x][y], blended);
                        buf.SetPixel(x, y, blended);
                    }
                }
            }
        }
        return true;
    }


    if (type == "Garlands") {
        // Native Garlands effect — port of legacy GarlandsEffect::Render
        int GarlandType = 0;
        int Spacing = 10;
        int CyclesRaw = 10; // stored as int, divide by 10 for float
        std::string dirStr = "Up";

        auto it = effectInfo.settings.find("E_SLIDER_Garlands_Type");
        if (it != effectInfo.settings.end() && !it->second.empty())
            GarlandType = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Garlands_Spacing");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Spacing = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Garlands_Cycles");
        if (it != effectInfo.settings.end() && !it->second.empty())
            CyclesRaw = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_CHOICE_Garlands_Direction");
        if (it != effectInfo.settings.end() && !it->second.empty())
            dirStr = it->second;

        float cycles = static_cast<float>(CyclesRaw) / 10.0f;
        if (Spacing < 1) Spacing = 1;

        // Decode direction: 0=Up, 1=Down, 2=Left, 3=Right,
        // 4=Up then Down, 5=Down then Up, 6=Left then Right, 7=Right then Left
        int dir = 0;
        if (dirStr == "Down") dir = 1;
        else if (dirStr == "Left") dir = 2;
        else if (dirStr == "Right") dir = 3;
        else if (dirStr == "Up then Down") dir = 4;
        else if (dirStr == "Down then Up") dir = 5;
        else if (dirStr == "Left then Right") dir = 6;
        else if (dirStr == "Right then Left") dir = 7;

        double position = buf.GetEffectTimeIntervalPosition(cycles);
        if (dir > 3) {
            dir -= 4;
            if (position > 0.5) {
                position = (1.0 - position) * 2.0;
            } else {
                position *= 2.0;
            }
        }

        int buffMax = buf.BufferHt;
        int garlandWid = buf.BufferWi;
        if (dir > 1) {
            buffMax = buf.BufferWi;
            garlandWid = buf.BufferHt;
        }

        double PixelSpacing = Spacing * buffMax / 100.0;
        if (PixelSpacing < 2.0) PixelSpacing = 2.0;

        double total = buffMax * PixelSpacing - buffMax + 1;
        double positionOffset = total * position;

        for (int ring = 0; ring < buffMax; ring++) {
            double ratio = static_cast<double>(buffMax - ring - 1) / static_cast<double>(buffMax);
            xlColor color;
            buf.GetMultiColorBlend(ratio, false, color);

            int y = static_cast<int>(1.0 + ring * PixelSpacing - positionOffset);

            int ylimit = ring;
            for (int x = 0; x < garlandWid; x++) {
                int yadj = y;
                switch (GarlandType) {
                    case 1:
                        switch (x % 5) {
                            case 2: yadj -= 2; break;
                            case 1:
                            case 3: yadj -= 1; break;
                        }
                        break;
                    case 2:
                        switch (x % 5) {
                            case 2: yadj -= 4; break;
                            case 1:
                            case 3: yadj -= 2; break;
                        }
                        break;
                    case 3:
                        switch (x % 6) {
                            case 3: yadj -= 6; break;
                            case 2:
                            case 4: yadj -= 4; break;
                            case 1:
                            case 5: yadj -= 2; break;
                        }
                        break;
                    case 4:
                        switch (x % 5) {
                            case 1:
                            case 3: yadj -= 2; break;
                        }
                        break;
                }
                if (yadj < ylimit) yadj = ylimit;
                if (yadj < buffMax) {
                    if (dir == 1 || dir == 2) {
                        yadj = buffMax - yadj - 1;
                    }
                    if (dir > 1) {
                        buf.SetPixel(yadj, x, color);
                    } else {
                        buf.SetPixel(x, yadj, color);
                    }
                }
            }
        }
        return true;
    }


    if (type == "Kaleidoscope") {
        // Native Kaleidoscope effect: mirror/reflection of existing buffer content.
        // This is a canvas-mode effect — it operates on pixels already rendered by
        // underlying layers/effects, reflecting them across axis lines.
        //
        // Types: "2 Way Vertical", "2 Way Horizontal", "4 Way", "Diagonal", "8 Way"
        // Settings: X center (0-100%), Y center (0-100%), Size (unused for mirror),
        //           Rotation (0-359, used by Diagonal)

        std::string kalType = "2 Way Vertical";
        auto it = effectInfo.settings.find("E_CHOICE_Kaleidoscope_Type");
        if (it != effectInfo.settings.end() && !it->second.empty())
            kalType = it->second;

        int xPct = 50;
        it = effectInfo.settings.find("E_SLIDER_Kaleidoscope_X");
        if (it != effectInfo.settings.end() && !it->second.empty())
            xPct = std::atoi(it->second.c_str());

        int yPct = 50;
        it = effectInfo.settings.find("E_SLIDER_Kaleidoscope_Y");
        if (it != effectInfo.settings.end() && !it->second.empty())
            yPct = std::atoi(it->second.c_str());

        int rotation = 0;
        it = effectInfo.settings.find("E_SLIDER_Kaleidoscope_Rotation");
        if (it != effectInfo.settings.end() && !it->second.empty())
            rotation = std::atoi(it->second.c_str());

        int wi = buf.BufferWi;
        int ht = buf.BufferHt;
        if (wi < 1 || ht < 1) return true;

        // Convert percentage center to pixel coordinates
        int cx = xPct * wi / 100;
        int cy = yPct * ht / 100;

        // Clamp center to buffer bounds
        if (cx < 0) cx = 0;
        if (cx >= wi) cx = wi - 1;
        if (cy < 0) cy = 0;
        if (cy >= ht) cy = ht - 1;

        if (kalType == "2 Way Vertical") {
            // Mirror left half to right half across vertical axis at cx.
            // The left side (0..cx) is the source; reflect to right side.
            for (int y = 0; y < ht; y++) {
                for (int x = cx + 1; x < wi; x++) {
                    int srcX = cx - (x - cx);
                    if (srcX >= 0 && srcX < wi) {
                        buf.SetPixel(x, y, buf.GetPixel(srcX, y));
                    }
                }
            }
        } else if (kalType == "2 Way Horizontal") {
            // Mirror bottom half to top half across horizontal axis at cy.
            // The bottom side (0..cy) is the source; reflect to top side.
            for (int y = cy + 1; y < ht; y++) {
                int srcY = cy - (y - cy);
                if (srcY >= 0 && srcY < ht) {
                    for (int x = 0; x < wi; x++) {
                        buf.SetPixel(x, y, buf.GetPixel(x, srcY));
                    }
                }
            }
        } else if (kalType == "4 Way") {
            // Four-way mirror: reflect across both vertical and horizontal axes.
            // Source quadrant is bottom-left (0..cx, 0..cy).

            // Step 1: Mirror bottom-left to bottom-right (vertical axis)
            for (int y = 0; y <= cy && y < ht; y++) {
                for (int x = cx + 1; x < wi; x++) {
                    int srcX = cx - (x - cx);
                    if (srcX >= 0 && srcX < wi) {
                        buf.SetPixel(x, y, buf.GetPixel(srcX, y));
                    }
                }
            }
            // Step 2: Mirror entire bottom half to top half (horizontal axis)
            for (int y = cy + 1; y < ht; y++) {
                int srcY = cy - (y - cy);
                if (srcY >= 0 && srcY < ht) {
                    for (int x = 0; x < wi; x++) {
                        buf.SetPixel(x, y, buf.GetPixel(x, srcY));
                    }
                }
            }
        } else if (kalType == "Diagonal") {
            // Diagonal mirror: reflect across a line through (cx, cy) at the
            // given rotation angle. Pixels on one side are reflected to the other.
            double angleRad = rotation * M_PI / 180.0;
            double cosA = std::cos(angleRad);
            double sinA = std::sin(angleRad);

            // Direction vector of the mirror line
            double dx = cosA;
            double dy = sinA;

            for (int y = 0; y < ht; y++) {
                for (int x = 0; x < wi; x++) {
                    // Vector from center to this pixel
                    double px = x - cx;
                    double py = y - cy;

                    // Signed distance from the mirror line (positive = one side)
                    double dot = px * (-dy) + py * dx;

                    if (dot < 0) {
                        // This pixel is on the "reflection" side.
                        // Reflect across the line: p' = p - 2 * dot * normal
                        double nx = -dy;
                        double ny = dx;
                        double srcXf = x - 2.0 * dot * nx;
                        double srcYf = y - 2.0 * dot * ny;
                        int srcX = static_cast<int>(std::round(srcXf));
                        int srcY = static_cast<int>(std::round(srcYf));

                        if (srcX >= 0 && srcX < wi && srcY >= 0 && srcY < ht) {
                            buf.SetPixel(x, y, buf.GetPixel(srcX, srcY));
                        }
                    }
                }
            }
        } else if (kalType == "8 Way") {
            // Eight-way mirror: reflect across vertical, horizontal, and both
            // diagonal axes through (cx, cy). Source octant is the triangle in
            // the bottom-left between the vertical axis and the 45-degree diagonal.

            // Step 1: Mirror across the diagonal (y=x relative to center) within
            // the bottom-left quadrant. Source is below the diagonal.
            for (int y = 0; y <= cy && y < ht; y++) {
                for (int x = 0; x <= cx && x < wi; x++) {
                    int relX = cx - x;
                    int relY = cy - y;
                    if (relY > relX) {
                        // Above diagonal in bottom-left quadrant — reflect
                        int srcX = cx - relY;
                        int srcY = cy - relX;
                        if (srcX >= 0 && srcX < wi && srcY >= 0 && srcY < ht) {
                            buf.SetPixel(x, y, buf.GetPixel(srcX, srcY));
                        }
                    }
                }
            }

            // Step 2: Mirror bottom-left to bottom-right (vertical axis)
            for (int y = 0; y <= cy && y < ht; y++) {
                for (int x = cx + 1; x < wi; x++) {
                    int srcX = cx - (x - cx);
                    if (srcX >= 0 && srcX < wi) {
                        buf.SetPixel(x, y, buf.GetPixel(srcX, y));
                    }
                }
            }

            // Step 3: Mirror entire bottom half to top half (horizontal axis)
            for (int y = cy + 1; y < ht; y++) {
                int srcY = cy - (y - cy);
                if (srcY >= 0 && srcY < ht) {
                    for (int x = 0; x < wi; x++) {
                        buf.SetPixel(x, y, buf.GetPixel(x, srcY));
                    }
                }
            }
        }

        return true;
    }


    if (type == "Life") {
        // Native Life effect — Conway's Game of Life
        // Port of legacy LifeEffect::Render

        // Read settings
        int Count = 50;
        int Type = 0;   // Seed / rule variant
        int lspeed = 10;

        auto it = effectInfo.settings.find("E_SLIDER_Life_Count");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Count = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Life_Seed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Type = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Life_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            lspeed = std::atoi(it->second.c_str());

        int BufferHt = buf.BufferHt;
        int BufferWi = buf.BufferWi;
        if (BufferHt < 1) BufferHt = 1;

        // Persistent cache for Life state across frames
        struct LifeCache : public EffectRenderCache {
            int lastCount = 0;
            int lastType = 0;
            int lastState = 0;
        };

        LifeCache* cache = dynamic_cast<LifeCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new LifeCache();
            buf.infoCache[0] = cache;
        }

        // Scale count to buffer area (same formula as legacy)
        Count = BufferWi * BufferHt * Count / 200 + 1;

        // Initialize / re-seed when parameters change or on first frame
        if (buf.needToInit || Count != cache->lastCount || Type != cache->lastType) {
            buf.needToInit = false;
            cache->lastCount = Count;
            cache->lastType = Type;
            buf.ClearTempBuf();
            for (int i = 0; i < Count; i++) {
                int x = std::rand() % BufferWi;
                int y = std::rand() % BufferHt;
                xlColor color;
                double r01 = static_cast<double>(std::rand()) / static_cast<double>(RAND_MAX);
                buf.GetMultiColorBlend(static_cast<float>(r01), false, color);
                buf.SetTempPixel(x, y, color);
            }
        }

        // Speed gating: only advance the simulation every Nth frame
        int effectState = (buf.curPeriod - buf.curEffStartPer) * lspeed * buf.frameTimeInMs / 50;
        long TempState = effectState % 400 / 20;
        if (TempState == cache->lastState) {
            buf.CopyTempBufToPixels();
            return true;
        }
        cache->lastState = static_cast<int>(TempState);

        // Neighbor counting lambda (wrapping toroidal grid)
        auto countNeighbors = [&](int x0, int y0) -> int {
            static const int n_x[] = { -1, -1, -1, 0, 1, 1, 1, 0 };
            static const int n_y[] = { -1, 0, 1, 1, 1, 0, -1, -1 };
            int cnt = 0;
            for (int i = 0; i < 8; ++i) {
                int x = (x0 + n_x[i]) % BufferWi;
                int y = (y0 + n_y[i]) % BufferHt;
                if (x < 0) x += BufferWi;
                if (y < 0) y += BufferHt;
                if (buf.GetTempPixelRGB(x, y) != xlBLACK)
                    ++cnt;
            }
            return cnt;
        };

        // Apply Game of Life rules — read from temp buf, write to pixel buf
        for (int x = 0; x < BufferWi; x++) {
            for (int y = 0; y < BufferHt; y++) {
                xlColor color;
                buf.GetTempPixel(x, y, color);
                bool isLive = (color != xlBLACK);
                int cnt = countNeighbors(x, y);

                switch (Type) {
                case 0:
                    // B3/S23 — standard Conway's Game of Life
                    if (isLive && cnt >= 2 && cnt <= 3) {
                        buf.SetPixel(x, y, color);
                    } else if (!isLive && cnt == 3) {
                        double r01 = static_cast<double>(std::rand()) / static_cast<double>(RAND_MAX);
                        buf.GetMultiColorBlend(static_cast<float>(r01), false, color);
                        buf.SetPixel(x, y, color);
                    }
                    break;
                case 1:
                    // B35/S236
                    if (isLive && (cnt == 2 || cnt == 3 || cnt == 6)) {
                        buf.SetPixel(x, y, color);
                    } else if (!isLive && (cnt == 3 || cnt == 5)) {
                        double r01 = static_cast<double>(std::rand()) / static_cast<double>(RAND_MAX);
                        buf.GetMultiColorBlend(static_cast<float>(r01), false, color);
                        buf.SetPixel(x, y, color);
                    }
                    break;
                case 2:
                    // B357/S1358
                    if (isLive && (cnt == 1 || cnt == 3 || cnt == 5 || cnt == 8)) {
                        buf.SetPixel(x, y, color);
                    } else if (!isLive && (cnt == 3 || cnt == 5 || cnt == 7)) {
                        double r01 = static_cast<double>(std::rand()) / static_cast<double>(RAND_MAX);
                        buf.GetMultiColorBlend(static_cast<float>(r01), false, color);
                        buf.SetPixel(x, y, color);
                    }
                    break;
                case 3:
                    // B378/S235678
                    if (isLive && (cnt == 2 || cnt == 3 || cnt >= 5)) {
                        buf.SetPixel(x, y, color);
                    } else if (!isLive && (cnt == 3 || cnt == 7 || cnt == 8)) {
                        double r01 = static_cast<double>(std::rand()) / static_cast<double>(RAND_MAX);
                        buf.GetMultiColorBlend(static_cast<float>(r01), false, color);
                        buf.SetPixel(x, y, color);
                    }
                    break;
                case 4:
                    // B25678/S5678
                    if (isLive && (cnt >= 5)) {
                        buf.SetPixel(x, y, color);
                    } else if (!isLive && (cnt == 2 || cnt >= 5)) {
                        double r01 = static_cast<double>(std::rand()) / static_cast<double>(RAND_MAX);
                        buf.GetMultiColorBlend(static_cast<float>(r01), false, color);
                        buf.SetPixel(x, y, color);
                    }
                    break;
                }
            }
        }

        // Copy new generation back to temp buf for next frame
        buf.CopyPixelsToTempBuf();
        return true;
    }


    if (type == "Lightning") {
        // Native Lightning effect — port of legacy LightningEffect::Render
        // Draws animated lightning bolts with optional forking.

        constexpr int DIR_DOWN = 0;
        constexpr int DIR_UP = 1;
        constexpr int DIR_RIGHT = 2;
        constexpr int DIR_LEFT = 3;

        // --- Read settings ---
        // Helper: try native key first, then legacy key
        auto findSetting = [&](const char* nativeKey, const char* legacyKey) ->
            std::map<std::string, std::string>::const_iterator {
            auto it = effectInfo.settings.find(nativeKey);
            if (it != effectInfo.settings.end() && !it->second.empty())
                return it;
            if (legacyKey) {
                it = effectInfo.settings.find(legacyKey);
                if (it != effectInfo.settings.end() && !it->second.empty())
                    return it;
            }
            return effectInfo.settings.end();
        };

        int Number_Bolts = 10;
        int Number_Segments = 5;
        bool ForkedLightning = false;
        int topX = 0;
        int topY = 0;
        int botX = 0;
        int width = 1;
        int DIRECTION = DIR_UP;

        auto it = findSetting("E_SLIDER_Lightning_Number_Bolts", "E_SLIDER_Number_Bolts");
        if (it != effectInfo.settings.end())
            Number_Bolts = std::atoi(it->second.c_str());

        it = findSetting("E_SLIDER_Lightning_Number_Segments", "E_SLIDER_Number_Segments");
        if (it != effectInfo.settings.end())
            Number_Segments = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_CHECKBOX_ForkedLightning");
        if (it != effectInfo.settings.end())
            ForkedLightning = (it->second == "1");

        it = effectInfo.settings.find("E_SLIDER_Lightning_TopX");
        if (it != effectInfo.settings.end() && !it->second.empty())
            topX = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Lightning_TopY");
        if (it != effectInfo.settings.end() && !it->second.empty())
            topY = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Lightning_BOTX");
        if (it != effectInfo.settings.end() && !it->second.empty())
            botX = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Lightning_WIDTH");
        if (it != effectInfo.settings.end() && !it->second.empty())
            width = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_CHOICE_Lightning_Direction");
        if (it != effectInfo.settings.end()) {
            if (it->second == "Down") DIRECTION = DIR_DOWN;
            else if (it->second == "Up") DIRECTION = DIR_UP;
            else if (it->second == "Left") DIRECTION = DIR_LEFT;
            else if (it->second == "Right") DIRECTION = DIR_RIGHT;
        }

        // Clamp parameters
        Number_Bolts = std::clamp(Number_Bolts, 1, 50);
        Number_Segments = std::clamp(Number_Segments, 1, 20);
        width = std::clamp(width, 1, 7);

        int curState = (buf.curPeriod - buf.curEffStartPer);
        int xc = buf.BufferWi / 2;

        int StepSegment = buf.BufferHt / Number_Bolts;
        int segment = curState % Number_Bolts;
        segment *= 4;
        if (segment > Number_Bolts) segment = Number_Bolts;
        if (curState > Number_Bolts) segment = Number_Bolts;

        xlColor color;
        buf.palette.GetColor(0, color);

        // Local lambda: draw a lightning bolt segment using Bresenham + horizontal width
        auto drawBolt = [&](int x0, int y0, int x1, int y1, xlColor& c, int w) {
            int dx = std::abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
            int dy = std::abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
            int err = (dx > dy ? dx : -dy) / 2, e2;
            for (;;) {
                buf.DrawHLine(y0, x0 - w, x0 + w, c);
                if (x0 == x1 && y0 == y1)
                    break;
                e2 = err;
                if (e2 > -dx) {
                    err -= dy;
                    x0 += sx;
                }
                if (e2 < dy) {
                    err += dx;
                    y0 += sy;
                }
            }
        };

        int x1 = 0;
        int y1 = 0;
        if (DIRECTION == DIR_DOWN) {
            x1 = xc + topX;
            y1 = buf.BufferHt - topY;
        } else if (DIRECTION == DIR_UP) {
            x1 = xc + topX;
            y1 = topY;
        }

        int xoffset = static_cast<int>(curState * botX / 10.0);

        for (int i = 0; i <= segment; i++) {
            int j = std::rand() + 1;
            int x2 = 0;
            int y2 = 0;
            if (DIRECTION == DIR_UP || DIRECTION == DIR_DOWN) {
                if (i % 2 == 0) {
                    if (std::rand() % 2 == 0)
                        x2 = xc + topX - (j % Number_Segments);
                    else
                        x2 = xc + topX + (2 * (j % Number_Segments));
                } else {
                    if (std::rand() % 2 == 0)
                        x2 = xc + topX + (j % Number_Segments);
                    else
                        x2 = xc + topX - (3 * (j % Number_Segments));
                }
                if (DIRECTION == DIR_DOWN)
                    y2 = buf.BufferHt - (i * StepSegment) - topY;
                else if (DIRECTION == DIR_UP)
                    y2 = (i * StepSegment) + topY;
            }

            drawBolt(x1 + xoffset, y1, x2 + xoffset, y2, color, width);

            if (ForkedLightning) {
                if (i > (segment / 2)) {
                    int x3 = 0;
                    if (i % 2 == 1) {
                        if (std::rand() % 2 == 1)
                            x3 = xc + topX - (j % Number_Segments);
                        else
                            x3 = xc + topX + (2 * (j % Number_Segments));
                    } else {
                        if (std::rand() % 2 == 1)
                            x3 = xc + topX + (j % Number_Segments);
                        else
                            x3 = xc + topX - (3 * (j % Number_Segments));
                    }
                    drawBolt(x1 + xoffset, y1, x3 + xoffset, y2, color, width);
                }
            }
            x1 = x2;
            y1 = y2;
        }

        return true;
    }


    if (type == "Lines") {
        // Native Lines effect — port of legacy LinesEffect::Render
        // Bouncing line segments with optional trails and fading.

        // --- Read settings ---
        int objects = 2;
        int segments = 3;
        int thickness = 1;
        int speed = 1;
        int trails = 0;
        bool fadeTrails = true;

        auto it = effectInfo.settings.find("E_SLIDER_Lines_Objects");
        if (it != effectInfo.settings.end() && !it->second.empty())
            objects = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Lines_Segments");
        if (it != effectInfo.settings.end() && !it->second.empty())
            segments = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Lines_Thickness");
        if (it != effectInfo.settings.end() && !it->second.empty())
            thickness = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Lines_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            speed = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Lines_Trails");
        if (it != effectInfo.settings.end() && !it->second.empty())
            trails = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_CHECKBOX_Lines_FadeTrails");
        if (it != effectInfo.settings.end())
            fadeTrails = (it->second == "1");

        // --- Local helper types ---

        constexpr double kPi2 = 6.283185307;

        struct LinePoint {
            float _x;
            float _y;
            double _angle;
            void FlipX() {
                // toRadians(540) = 2*PI*540/360 = 3*PI = 9.42477796...
                _angle = (3.0 * M_PI) - _angle;
                if (_angle >= kPi2) {
                    _angle -= kPi2;
                }
            }
            void FlipY() {
                // toRadians(360) = 2*PI
                _angle = kPi2 - _angle;
            }
        };

        // --- Render cache ---
        struct LinesCache : public EffectRenderCache {
            // Each line object is a list of trail snapshots.
            // Each trail snapshot is a list of points (the segment vertices).
            std::vector<std::list<std::list<LinePoint>>> lineObjects;
        };

        LinesCache* cache = dynamic_cast<LinesCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new LinesCache();
            buf.infoCache[0] = cache;
        }

        if (buf.needToInit) {
            buf.needToInit = false;
        }

        auto& lines = cache->lineObjects;

        // Create / destroy line objects to match requested count
        while (static_cast<int>(lines.size()) > objects) {
            lines.pop_back();
        }
        while (static_cast<int>(lines.size()) < objects) {
            // Create a new line object with initial random points
            std::list<std::list<LinePoint>> newLine;
            std::list<LinePoint> pts;
            for (int s = 0; s < segments; s++) {
                LinePoint pt;
                pt._x = static_cast<float>(static_cast<double>(std::rand()) / RAND_MAX) * buf.BufferWi;
                pt._y = static_cast<float>(static_cast<double>(std::rand()) / RAND_MAX) * buf.BufferHt;
                pt._angle = (static_cast<double>(std::rand()) / RAND_MAX) * kPi2;
                pts.push_back(pt);
            }
            newLine.push_back(std::move(pts));
            lines.push_back(std::move(newLine));
        }

        // Advance all line objects
        for (auto& lineObj : lines) {
            // Trim excess trails
            while (static_cast<int>(lineObj.size()) > trails + 1) {
                lineObj.pop_back();
            }

            // Save the last trail as basis for new trail entry
            std::list<LinePoint> last = lineObj.back();

            // Advance all existing trail snapshots
            for (auto& trail : lineObj) {
                for (auto& pt : trail) {
                    float speedX = std::cos(pt._angle) * speed;
                    float speedY = std::sin(pt._angle) * speed;

                    float x = pt._x + speedX;
                    float y = pt._y + speedY;

                    // Bounce off walls
                    if (x < 0) {
                        x = std::abs(x);
                        pt.FlipX();
                    }
                    if (x >= buf.BufferWi) {
                        x = 2 * buf.BufferWi - x;
                        pt.FlipX();
                    }
                    if (y < 0) {
                        y = std::abs(y);
                        pt.FlipY();
                    }
                    if (y >= buf.BufferHt) {
                        y = 2 * buf.BufferHt - y;
                        pt.FlipY();
                    }
                    pt._x = x;
                    pt._y = y;
                }
            }

            // Add a new trail entry if needed
            if (static_cast<int>(lineObj.size()) < trails + 1) {
                lineObj.push_back(last);
            }
        }

        // --- Draw each line object ---
        // Use a temp buffer per line object and alpha-blend to main buffer
        // to minimize over-rendering artifacts.
        NativeRenderBuffer temp(buf);
        temp.SetAllowAlphaChannel(true);

        int colorIdx = 0;
        for (auto& lineObj : lines) {
            xlColor c = buf.palette.GetColor(colorIdx % buf.GetColorCount());
            colorIdx++;

            temp.Clear();

            // Draw trails in reverse order (oldest first) with optional fading
            int trailNum = 1;
            int totalTrails = static_cast<int>(lineObj.size());
            for (auto trailIt = lineObj.rbegin(); trailIt != lineObj.rend(); ++trailIt) {
                const auto& trail = *trailIt;
                xlColor drawColor = c;

                if (fadeTrails && trails > 0) {
                    drawColor.alpha = static_cast<uint8_t>(255 * trailNum / totalTrails);
                }
                trailNum++;

                // Draw the trail: connect consecutive points with thick lines
                if (trail.size() >= 2) {
                    auto it1 = trail.begin();
                    auto it2 = std::next(trail.begin());
                    while (it2 != trail.end()) {
                        temp.DrawThickLine(
                            static_cast<int>(it1->_x), static_cast<int>(it1->_y),
                            static_cast<int>(it2->_x), static_cast<int>(it2->_y),
                            drawColor, thickness, true);
                        ++it1;
                        ++it2;
                    }
                }
                // Also draw first-to-last (the legacy code draws front-to-back
                // and then all consecutive pairs; the front-to-back line is
                // redundant when there are only 2 points but matters for >2)
                if (trail.size() >= 2) {
                    auto& p1 = trail.front();
                    auto& p2 = trail.back();
                    temp.DrawThickLine(
                        static_cast<int>(p1._x), static_cast<int>(p1._y),
                        static_cast<int>(p2._x), static_cast<int>(p2._y),
                        drawColor, thickness, true);
                }
            }

            buf.AlphaBlend(temp);
        }

        return true;
    }


    if (type == "Marquee") {
        // Native Marquee effect — port of legacy MarqueeEffect::Render
        // Draws concentric rectangular marquee chase patterns around the buffer.

        float oset = buf.GetEffectTimeIntervalPosition();

        // Read settings with defaults matching legacy SetDefaultParameters
        int BandSize = 3;
        int SkipSize = 0;
        int Thickness = 1;
        int stagger = 0;
        int mSpeed = 3;
        int mStart = 0;
        int x_scale = 100;
        int y_scale = 100;
        int xc_adj = 0;
        int yc_adj = 0;
        bool reverse_dir = false;
        bool pixelOffsets = false;
        bool wrap_x = false;
        bool wrap_y = false;

        auto it = effectInfo.settings.find("E_SLIDER_Marquee_Band_Size");
        if (it != effectInfo.settings.end() && !it->second.empty())
            BandSize = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Marquee_Skip_Size");
        if (it != effectInfo.settings.end() && !it->second.empty())
            SkipSize = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Marquee_Thickness");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Thickness = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Marquee_Stagger");
        if (it != effectInfo.settings.end() && !it->second.empty())
            stagger = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Marquee_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            mSpeed = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Marquee_Start");
        if (it != effectInfo.settings.end() && !it->second.empty())
            mStart = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Marquee_ScaleX");
        if (it != effectInfo.settings.end() && !it->second.empty())
            x_scale = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Marquee_ScaleY");
        if (it != effectInfo.settings.end() && !it->second.empty())
            y_scale = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_MarqueeXC");
        if (it != effectInfo.settings.end() && !it->second.empty())
            xc_adj = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_MarqueeYC");
        if (it != effectInfo.settings.end() && !it->second.empty())
            yc_adj = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_CHECKBOX_Marquee_Reverse");
        if (it != effectInfo.settings.end()) reverse_dir = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Marquee_PixelOffsets");
        if (it != effectInfo.settings.end()) pixelOffsets = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Marquee_WrapX");
        if (it != effectInfo.settings.end()) wrap_x = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Marquee_WrapY");
        if (it != effectInfo.settings.end()) wrap_y = (it->second == "1");

        size_t colorcnt = buf.GetColorCount();
        int color_size = BandSize + SkipSize;
        int repeat_size = color_size * static_cast<int>(colorcnt);

        int eff_pos = buf.curPeriod - buf.curEffStartPer;
        int x = (mSpeed * eff_pos) / 5;

        int corner_x1 = 0;
        int corner_y1 = 0;
        int corner_x2 = static_cast<int>(std::round(((double)(buf.BufferWi * x_scale) / 100.0) - 1.0));
        int corner_y2 = static_cast<int>(std::round(((double)(buf.BufferHt * y_scale) / 100.0) - 1.0));

        int sign = 1;
        if (reverse_dir) {
            sign = -1;
        }

        int xoffset_adj = xc_adj;
        int yoffset_adj = yc_adj;
        if (!pixelOffsets) {
            xoffset_adj = static_cast<int>((xoffset_adj * buf.BufferWi) / 100.0);
            yoffset_adj = static_cast<int>((yoffset_adj * buf.BufferHt) / 100.0);
        }

        // UpdateMarqueeColor: advance position and color band through the
        // repeating color pattern by 'shift' steps.
        auto UpdateMarqueeColor = [&](int& position, int& band_color, int shift) {
            if (shift == 0) return;
            if (shift > 0) {
                int index = 0;
                while (index < shift) {
                    position++;
                    if (position >= color_size) {
                        band_color++;
                        band_color %= static_cast<int>(colorcnt);
                        position = 0;
                    }
                    index++;
                }
            } else {
                int index = 0;
                while (index > shift) {
                    position--;
                    if (position < 0) {
                        band_color++;
                        band_color %= static_cast<int>(colorcnt);
                        position = color_size - 1;
                    }
                    index--;
                }
            }
        };

        for (int thick = 0; thick < Thickness; thick++) {
            int current_color = (repeat_size > 0) ? (((x + mStart) % repeat_size) / color_size) : 0;
            int current_pos = (repeat_size > 0) ? (((x + mStart) % repeat_size) % color_size) : 0;
            if (sign < 0) {
                current_color = static_cast<int>(colorcnt) - current_color - 1;
            }

            if (corner_y2 != corner_y1) {
                // Top edge: left to right
                UpdateMarqueeColor(current_pos, current_color, thick * (stagger + 1) * sign);
                for (int x_pos = corner_x1; x_pos <= corner_x2; x_pos++) {
                    xlColor color = xlCLEAR;
                    if (current_pos < BandSize) {
                        buf.palette.GetColor(current_color, color);
                    }
                    buf.ProcessPixel(x_pos + xoffset_adj, corner_y2 + yoffset_adj, color, wrap_x, wrap_y);
                    UpdateMarqueeColor(current_pos, current_color, 1 * sign);
                }
                // Right edge: top to bottom
                UpdateMarqueeColor(current_pos, current_color, thick * 2 * sign);
                for (int y_pos = corner_y2; y_pos >= corner_y1; y_pos--) {
                    xlColor color = xlCLEAR;
                    if (current_pos < BandSize) {
                        buf.palette.GetColor(current_color, color);
                    }
                    buf.ProcessPixel(corner_x2 + xoffset_adj, y_pos + yoffset_adj, color, wrap_x, wrap_y);
                    UpdateMarqueeColor(current_pos, current_color, 1 * sign);
                }
            }
            // Bottom edge: right to left
            UpdateMarqueeColor(current_pos, current_color, thick * 2 * sign);
            for (int x_pos = corner_x2; x_pos >= corner_x1; x_pos--) {
                xlColor color = xlCLEAR;
                if (current_pos < BandSize) {
                    buf.palette.GetColor(current_color, color);
                }
                buf.ProcessPixel(x_pos + xoffset_adj, corner_y1 + yoffset_adj, color, wrap_x, wrap_y);
                UpdateMarqueeColor(current_pos, current_color, 1 * sign);
            }
            if (corner_y2 != corner_y1) {
                // Left edge: bottom to top (minus one at top to avoid corner overlap)
                UpdateMarqueeColor(current_pos, current_color, thick * 2 * sign);
                for (int y_pos = corner_y1; y_pos <= corner_y2 - 1; y_pos++) {
                    xlColor color = xlCLEAR;
                    if (current_pos < BandSize) {
                        buf.palette.GetColor(current_color, color);
                    }
                    buf.ProcessPixel(corner_x1 + xoffset_adj, y_pos + yoffset_adj, color, wrap_x, wrap_y);
                    UpdateMarqueeColor(current_pos, current_color, 1 * sign);
                }
            }

            // Shrink rectangle inward for next thickness layer
            corner_x1++;
            corner_y1++;
            corner_x2--;
            corner_y2--;
        }
        return true;
    }


    if (type == "Meteors") {
        // Native Meteors effect — faithful port of legacy MeteorsEffect::Render
        // with all sub-types: vertical, horizontal, implode, explode, icicles.
        //
        // Settings keys (native panel):
        //   E_CHOICE_Meteors_Type      = Falling, Falling2, Icicles, Icicles Bkg, Rain, Explode
        //   E_CHOICE_Meteors_Direction  = Down, Up, Left, Right
        //   E_SLIDER_Meteors_Count     = 1..100 (default 10)
        //   E_SLIDER_Meteors_Length    = 1..100 (default 25)
        //   E_SLIDER_Meteors_Speed     = 1..50  (default 10)
        //   E_SLIDER_Meteors_Swirl_Intensity = 0..20 (default 0)
        //   E_SLIDER_Meteors_XOffset   = -100..100 (default 0)
        //   E_SLIDER_Meteors_YOffset   = -100..100 (default 0)
        //   E_CHECKBOX_Meteors_UseMusic = 0/1 (default 0)
        //
        // Legacy keys (imported sequences, no E_ prefix):
        //   CHOICE_Meteors_Effect = Down, Up, Left, Right, Implode, Explode, Icicles, Icicles + bkg
        //   CHOICE_Meteors_Type   = Rainbow, Range, Palette

        // --- Helper types ---
        struct MeteorParticle {
            int x, y;
            HSVValue hsv;
            int h = 0; // variable length for icicle drip
        };

        struct MeteorRadialParticle {
            double x, y, dx, dy;
            int cnt;
            HSVValue hsv;
        };

        struct MeteorsCache : public EffectRenderCache {
            float effectState = 0;
            std::list<MeteorParticle> meteors;
            std::list<MeteorRadialParticle> meteorsRadial;
        };

        // --- Direction/type constants ---
        enum MeteorMode {
            METEOR_DOWN = 0,
            METEOR_UP = 1,
            METEOR_LEFT = 2,
            METEOR_RIGHT = 3,
            METEOR_IMPLODE = 4,
            METEOR_EXPLODE = 5,
            METEOR_ICICLES = 6,
            METEOR_ICICLES_BKG = 7
        };

        // --- Parse settings ---
        auto getStr = [&](const std::string& key, const std::string& def = "") -> std::string {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty())
                return it->second;
            return def;
        };
        auto getInt = [&](const std::string& key, int def) -> int {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty())
                return std::atoi(it->second.c_str());
            return def;
        };

        int Count = getInt("E_SLIDER_Meteors_Count", 10);
        int Length = getInt("E_SLIDER_Meteors_Length", 25);
        int mSpeed = getInt("E_SLIDER_Meteors_Speed", 10);
        int SwirlIntensity = getInt("E_SLIDER_Meteors_Swirl_Intensity", 0);
        int xoffset = getInt("E_SLIDER_Meteors_XOffset", 0);
        int yoffset = getInt("E_SLIDER_Meteors_YOffset", 0);
        int warmupFrames = getInt("E_SLIDER_Meteors_WarmupFrames", 0);

        // Determine meteor mode. The native panel separates type and direction;
        // the legacy panel combines them into a single CHOICE_Meteors_Effect.
        int meteorMode = METEOR_DOWN;

        // Try native keys first
        std::string nativeType = getStr("E_CHOICE_Meteors_Type", "");
        std::string nativeDir = getStr("E_CHOICE_Meteors_Direction", "");

        if (!nativeType.empty()) {
            // Native panel layout: Type selects behavior, Direction selects movement
            if (nativeType == "Explode") {
                meteorMode = METEOR_EXPLODE;
            } else if (nativeType == "Rain") {
                meteorMode = METEOR_IMPLODE;
            } else if (nativeType == "Icicles") {
                meteorMode = METEOR_ICICLES;
            } else if (nativeType == "Icicles Bkg") {
                meteorMode = METEOR_ICICLES_BKG;
            } else {
                // Falling / Falling2 — use direction
                if (nativeDir == "Up") meteorMode = METEOR_UP;
                else if (nativeDir == "Left") meteorMode = METEOR_LEFT;
                else if (nativeDir == "Right") meteorMode = METEOR_RIGHT;
                else meteorMode = METEOR_DOWN;
            }
        } else {
            // Legacy key fallback
            std::string legacyEffect = getStr("CHOICE_Meteors_Effect", "Down");
            if (legacyEffect == "Up") meteorMode = METEOR_UP;
            else if (legacyEffect == "Left") meteorMode = METEOR_LEFT;
            else if (legacyEffect == "Right") meteorMode = METEOR_RIGHT;
            else if (legacyEffect == "Implode") meteorMode = METEOR_IMPLODE;
            else if (legacyEffect == "Explode") meteorMode = METEOR_EXPLODE;
            else if (legacyEffect == "Icicles") meteorMode = METEOR_ICICLES;
            else if (legacyEffect == "Icicles + bkg") meteorMode = METEOR_ICICLES_BKG;
            else meteorMode = METEOR_DOWN;
        }

        // Determine color scheme: 0=rainbow, 1=range, 2=palette
        // Legacy uses CHOICE_Meteors_Type = Rainbow/Range/Palette
        // Native doesn't expose this — default to palette (use palette colors)
        int ColorScheme = 2; // default: palette
        {
            std::string legacyColor = getStr("CHOICE_Meteors_Type", "");
            if (legacyColor == "Rainbow") ColorScheme = 0;
            else if (legacyColor == "Range") ColorScheme = 1;
            else if (legacyColor == "Palette") ColorScheme = 2;
        }

        // FadeWithDistance for implode/explode
        bool fadeWithDistance = (getStr("E_CHECKBOX_FadeWithDistance", "0") == "1")
                            || (getStr("CHECKBOX_FadeWithDistance", "0") == "1");

        // --- Get/create render cache ---
        MeteorsCache* cache = dynamic_cast<MeteorsCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new MeteorsCache();
            buf.infoCache[0] = cache;
        }

        if (buf.needToInit) {
            buf.needToInit = false;
            cache->meteors.clear();
            cache->meteorsRadial.clear();
            auto calcOffset = [&](int sp) -> float {
                if (sp == 0) return 0.1f;
                return (float(sp * buf.frameTimeInMs)) / 50.0f;
            };
            cache->effectState = calcOffset(mSpeed);
        }

        // --- Helper lambdas ---
        auto calcEffectStateOffset = [&](int sp) -> float {
            if (sp == 0) return 0.1f;
            return (float(sp * buf.frameTimeInMs)) / 50.0f;
        };

        auto rand01 = []() -> double {
            return static_cast<double>(std::rand()) / static_cast<double>(RAND_MAX);
        };

        // Color assignment helper
        auto assignColor = [&](HSVValue& hsv, int scheme) {
            HSVValue hsv0, hsv1;
            buf.palette.GetHSV(0, hsv0);
            buf.palette.GetHSV(1, hsv1);
            size_t colorcnt = buf.GetColorCount();
            switch (scheme) {
                case 1:
                    buf.SetRangeColor(hsv0, hsv1, hsv);
                    break;
                case 2:
                    buf.palette.GetHSV(std::rand() % colorcnt, hsv);
                    break;
                default:
                    break;
            }
        };

        // =====================================================================
        // VERTICAL (Down / Up)
        // =====================================================================
        if (meteorMode == METEOR_DOWN || meteorMode == METEOR_UP) {
            // Add new meteors
            auto verticalAdd = [&]() {
                MeteorParticle m;
                for (int i = 0; i < buf.BufferWi; i++) {
                    if (std::rand() % 200 < Count) {
                        m.x = i;
                        m.y = buf.BufferHt - 1;
                        assignColor(m.hsv, ColorScheme);
                        cache->meteors.push_back(m);
                    }
                }
            };

            // Move meteors
            auto verticalMove = [&](int spd) {
                for (auto& meteor : cache->meteors) {
                    meteor.y -= spd;
                }
            };

            // Remove expired meteors
            auto verticalRemove = [&](int tailLen) {
                cache->meteors.remove_if([tailLen](const MeteorParticle& obj) {
                    return obj.y + tailLen < 0;
                });
            };

            // Warmup
            if (buf.curPeriod == buf.curEffStartPer) {
                for (int i = 0; i < warmupFrames; ++i) {
                    cache->effectState += calcEffectStateOffset(mSpeed);
                    int spd = static_cast<int>(cache->effectState) / 4;
                    cache->effectState -= spd * 4;

                    int TL = (buf.BufferHt < 10) ? Length / 10 : buf.BufferHt * Length / 100;
                    if (TL < 1) TL = 1;

                    verticalAdd();
                    verticalMove(spd);
                    verticalRemove(TL);
                }
            }

            cache->effectState += calcEffectStateOffset(mSpeed);
            int speed = static_cast<int>(cache->effectState) / 4;
            cache->effectState -= speed * 4;

            int TailLength = (buf.BufferHt < 10) ? Length / 10 : buf.BufferHt * Length / 100;
            if (TailLength < 1) TailLength = 1;

            verticalAdd();

            // Render meteors
            int n = 0;
            for (auto& meteor : cache->meteors) {
                HSVValue hsv;
                for (int ph = 0; ph <= TailLength; ph++) {
                    switch (ColorScheme) {
                        case 0:
                            hsv.hue = double(std::rand() % 1000) / 1000.0;
                            hsv.saturation = 1.0;
                            hsv.value = 1.0;
                            break;
                        default:
                            hsv = meteor.hsv;
                            break;
                    }

                    double swirl_phase = double(meteor.y) / 5.0 + double(n) / 100.0;
                    int dx = int(double(SwirlIntensity * buf.BufferWi) / 80.0 * buf.sin(swirl_phase));
                    int x = meteor.x + dx;
                    int y = meteor.y + ph;
                    if (meteorMode == METEOR_UP)
                        y = buf.BufferHt - y;

                    if (buf.allowAlpha) {
                        xlColor c(hsv);
                        c.alpha = static_cast<uint8_t>(255.0 * (1.0 - double(ph) / TailLength));
                        buf.SetPixel(x, y, c);
                    } else {
                        hsv.value *= 1.0 - double(ph) / TailLength;
                        buf.SetPixel(x, y, hsv);
                    }
                }
                n++;
            }

            verticalMove(speed);
            verticalRemove(TailLength);
        }

        // =====================================================================
        // HORIZONTAL (Left / Right)
        // =====================================================================
        else if (meteorMode == METEOR_LEFT || meteorMode == METEOR_RIGHT) {
            auto horizontalAdd = [&]() {
                MeteorParticle m;
                for (int i = 0; i < buf.BufferHt; i++) {
                    if (std::rand() % 200 < Count) {
                        m.x = buf.BufferWi - 1;
                        m.y = i;
                        assignColor(m.hsv, ColorScheme);
                        cache->meteors.push_back(m);
                    }
                }
            };

            auto horizontalMove = [&](int spd) {
                for (auto& meteor : cache->meteors) {
                    meteor.x -= spd;
                }
            };

            auto horizontalRemove = [&](int tailLen) {
                cache->meteors.remove_if([tailLen](const MeteorParticle& obj) {
                    return obj.x + tailLen < 0;
                });
            };

            if (buf.curPeriod == buf.curEffStartPer) {
                for (int i = 0; i < warmupFrames; ++i) {
                    cache->effectState += calcEffectStateOffset(mSpeed);
                    int spd = static_cast<int>(cache->effectState) / 4;
                    cache->effectState -= spd * 4;

                    int TL = (buf.BufferWi < 10) ? Length / 10 : buf.BufferWi * Length / 100;
                    if (TL < 1) TL = 1;

                    horizontalAdd();
                    horizontalMove(spd);
                    horizontalRemove(TL);
                }
            }

            cache->effectState += calcEffectStateOffset(mSpeed);
            int speed = static_cast<int>(cache->effectState) / 4;
            cache->effectState -= speed * 4;

            int TailLength = (buf.BufferWi < 10) ? Length / 10 : buf.BufferWi * Length / 100;
            if (TailLength < 1) TailLength = 1;

            horizontalAdd();

            int n = 0;
            for (auto& meteor : cache->meteors) {
                HSVValue hsv;
                for (int ph = 0; ph <= TailLength; ph++) {
                    switch (ColorScheme) {
                        case 0:
                            hsv.hue = double(std::rand() % 1000) / 1000.0;
                            hsv.saturation = 1.0;
                            hsv.value = 1.0;
                            break;
                        default:
                            hsv = meteor.hsv;
                            break;
                    }

                    double swirl_phase = double(meteor.x) / 5.0 + double(n) / 100.0;
                    int dy = int(double(SwirlIntensity * buf.BufferHt) / 80.0 * buf.sin(swirl_phase));

                    int x = meteor.x + ph;
                    int y = meteor.y + dy;
                    if (meteorMode == METEOR_RIGHT)
                        x = buf.BufferWi - x;

                    if (buf.allowAlpha) {
                        xlColor c(hsv);
                        c.alpha = static_cast<uint8_t>(255.0 * (1.0 - double(ph) / TailLength));
                        buf.SetPixel(x, y, c);
                    } else {
                        hsv.value *= 1.0 - double(ph) / TailLength;
                        buf.SetPixel(x, y, hsv);
                    }
                }
                n++;
            }

            horizontalMove(speed);
            horizontalRemove(TailLength);
        }

        // =====================================================================
        // IMPLODE (radial inward)
        // =====================================================================
        else if (meteorMode == METEOR_IMPLODE) {
            int truexoffset = xoffset * buf.BufferWi / 2 / 100;
            int trueyoffset = yoffset * buf.BufferHt / 2 / 100;
            int centerX = buf.BufferWi / 2 + truexoffset;
            int centerY = buf.BufferHt / 2 + trueyoffset;
            int MinDimension = std::min(buf.BufferHt, buf.BufferWi);

            auto calcMaxDiag = [&]() -> int {
                return std::max({
                    (int)std::sqrt((0 - centerX) * (0 - centerX) + (0 - centerY) * (0 - centerY)),
                    (int)std::sqrt((0 - centerX) * (0 - centerX) + (buf.BufferHt - centerY) * (buf.BufferHt - centerY)),
                    (int)std::sqrt((buf.BufferWi - centerX) * (buf.BufferWi - centerX) + (0 - centerY) * (0 - centerY)),
                    (int)std::sqrt((buf.BufferWi - centerX) * (buf.BufferWi - centerX) + (buf.BufferHt - centerY) * (buf.BufferHt - centerY))
                });
            };
            int maxdiag = calcMaxDiag();

            auto implodeAdd = [&]() {
                int TL = (maxdiag < 10) ? Length / 10 : maxdiag * Length / 100;
                if (TL < 1) TL = 1;

                MeteorRadialParticle m;
                m.cnt = 1;
                for (int i = 0; i < MinDimension; i++) {
                    if (std::rand() % 200 < Count) {
                        double angle;
                        if (buf.BufferHt == 1)
                            angle = double(std::rand() % 2) * M_PI;
                        else if (buf.BufferWi == 1)
                            angle = double(std::rand() % 2) * M_PI - (M_PI / 2.0);
                        else
                            angle = rand01() * 2.0 * M_PI;

                        m.dx = buf.cos(angle);
                        m.dy = buf.sin(angle);
                        m.x = centerX + double(maxdiag + TL) * m.dx;
                        m.y = centerY + double(maxdiag + TL) * m.dy;

                        assignColor(m.hsv, ColorScheme);
                        cache->meteorsRadial.push_back(m);
                    }
                }
            };

            auto implodeMove = [&](int spd) {
                for (auto& meteor : cache->meteorsRadial) {
                    float hdistance = 1.0f;
                    if (fadeWithDistance) {
                        float fx = meteor.x;
                        float fy = meteor.y;
                        hdistance = std::max(0.1f, (float)std::sqrt(
                            (fx - (float)centerX) * (fx - (float)centerX) +
                            (fy - (float)centerY) * (fy - (float)centerY)) / (float)maxdiag);
                    }
                    meteor.x -= meteor.dx * spd * hdistance;
                    meteor.y -= meteor.dy * spd * hdistance;
                    meteor.cnt++;
                }
            };

            auto implodeRemove = [&]() {
                cache->meteorsRadial.remove_if([centerX, centerY](const MeteorRadialParticle& obj) {
                    return (std::abs(obj.y - centerY) < 2) && (std::abs(obj.x - centerX) < 2);
                });
            };

            if (buf.curPeriod == buf.curEffStartPer) {
                for (int i = 0; i < warmupFrames; ++i) {
                    cache->effectState += calcEffectStateOffset(mSpeed);
                    int spd = static_cast<int>(cache->effectState) / 4;
                    cache->effectState -= spd * 4;

                    implodeAdd();
                    implodeMove(spd);
                    implodeRemove();
                }
            }

            cache->effectState += calcEffectStateOffset(mSpeed);
            int speed = static_cast<int>(cache->effectState) / 4;
            cache->effectState -= speed * 4;

            int TailLength = (maxdiag < 10) ? Length / 10 : maxdiag * Length / 100;
            if (TailLength < 1) TailLength = 1;

            implodeAdd();

            for (auto& meteor : cache->meteorsRadial) {
                HSVValue hsv;
                for (int ph = 0; ph <= TailLength; ph++) {
                    switch (ColorScheme) {
                        case 0:
                            hsv.hue = double(std::rand() % 1000) / 1000.0;
                            hsv.saturation = 1.0;
                            hsv.value = 1.0;
                            break;
                        default:
                            hsv = meteor.hsv;
                            break;
                    }

                    int x = int(meteor.x - meteor.dx * double(ph));
                    int y = int(meteor.y - meteor.dy * double(ph));

                    if ((std::abs(y - centerY) < 2) && (std::abs(x - centerX) < 2))
                        break;

                    if (fadeWithDistance) {
                        int distance = std::sqrt((x - centerX) * (x - centerX) +
                                                 (y - centerY) * (y - centerY));
                        if (distance < 10) distance = 10;
                        hsv.value *= double(distance) / maxdiag;
                    }

                    if (buf.allowAlpha) {
                        xlColor c(hsv);
                        c.alpha = static_cast<uint8_t>(255.0 * (double(ph) / TailLength));
                        buf.SetPixel(x, y, c);
                    } else {
                        hsv.value *= double(ph) / TailLength;
                        buf.SetPixel(x, y, hsv);
                    }
                }
            }

            implodeMove(speed);
            implodeRemove();
        }

        // =====================================================================
        // EXPLODE (radial outward)
        // =====================================================================
        else if (meteorMode == METEOR_EXPLODE) {
            int truexoffset = xoffset * buf.BufferWi / 2 / 100;
            int trueyoffset = yoffset * buf.BufferHt / 2 / 100;
            int centerX = buf.BufferWi / 2 + truexoffset;
            int centerY = buf.BufferHt / 2 + trueyoffset;
            int MinDimension = std::min(buf.BufferHt, buf.BufferWi);

            auto calcMaxDiag = [&]() -> int {
                return std::max({
                    (int)std::sqrt((0 - centerX) * (0 - centerX) + (0 - centerY) * (0 - centerY)),
                    (int)std::sqrt((0 - centerX) * (0 - centerX) + (buf.BufferHt - centerY) * (buf.BufferHt - centerY)),
                    (int)std::sqrt((buf.BufferWi - centerX) * (buf.BufferWi - centerX) + (0 - centerY) * (0 - centerY)),
                    (int)std::sqrt((buf.BufferWi - centerX) * (buf.BufferWi - centerX) + (buf.BufferHt - centerY) * (buf.BufferHt - centerY))
                });
            };
            int maxdiag = calcMaxDiag();

            auto explodeAdd = [&]() {
                MeteorRadialParticle m;
                m.x = centerX;
                m.y = centerY;
                m.cnt = 1;
                for (int i = 0; i < MinDimension; i++) {
                    if (std::rand() % 200 < Count) {
                        double angle;
                        if (buf.BufferHt == 1)
                            angle = double(std::rand() % 2) * M_PI;
                        else if (buf.BufferWi == 1)
                            angle = double(std::rand() % 2) * M_PI - (M_PI / 2.0);
                        else
                            angle = rand01() * 2.0 * M_PI;

                        m.dx = buf.cos(angle);
                        m.dy = buf.sin(angle);

                        assignColor(m.hsv, ColorScheme);
                        cache->meteorsRadial.push_back(m);
                    }
                }
            };

            auto explodeMove = [&](int spd) {
                for (auto& meteor : cache->meteorsRadial) {
                    float hdistance = 1.0f;
                    if (fadeWithDistance) {
                        float fx = meteor.x;
                        float fy = meteor.y;
                        hdistance = std::max(0.1f, (float)std::sqrt(
                            (fx - (float)centerX) * (fx - (float)centerX) +
                            (fy - (float)centerY) * (fy - (float)centerY)) / (float)maxdiag);
                    }
                    meteor.x += meteor.dx * spd * hdistance;
                    meteor.y += meteor.dy * spd * hdistance;
                    meteor.cnt++;
                }
            };

            auto explodeRemove = [&]() {
                int ht = buf.BufferHt;
                int wi = buf.BufferWi;
                cache->meteorsRadial.remove_if([ht, wi](const MeteorRadialParticle& obj) {
                    return obj.y < 0 || obj.x < 0 || obj.y > ht || obj.x > wi;
                });
            };

            if (buf.curPeriod == buf.curEffStartPer) {
                for (int i = 0; i < warmupFrames; ++i) {
                    cache->effectState += calcEffectStateOffset(mSpeed);
                    int spd = static_cast<int>(cache->effectState) / 4;
                    cache->effectState -= spd * 4;

                    explodeAdd();
                    explodeMove(spd);
                    explodeRemove();
                }
            }

            cache->effectState += calcEffectStateOffset(mSpeed);
            int speed = static_cast<int>(cache->effectState) / 4;
            cache->effectState -= speed * 4;

            int TailLength = (maxdiag < 10) ? Length / 10 : maxdiag * Length / 100;
            if (TailLength < 1) TailLength = 1;

            explodeAdd();

            for (auto& meteor : cache->meteorsRadial) {
                HSVValue hsv;
                for (int ph = 0; ph <= TailLength; ph++) {
                    switch (ColorScheme) {
                        case 0:
                            hsv.hue = double(std::rand() % 1000) / 1000.0;
                            hsv.saturation = 1.0;
                            hsv.value = 1.0;
                            break;
                        default:
                            hsv = meteor.hsv;
                            break;
                    }

                    int x = int(meteor.x + meteor.dx * double(ph));
                    int y = int(meteor.y + meteor.dy * double(ph));

                    if (fadeWithDistance) {
                        int distance = std::sqrt((x - centerX) * (x - centerX) +
                                                 (y - centerY) * (y - centerY));
                        if (distance < 10) distance = 10;
                        hsv.value *= double(distance) / maxdiag;
                    }

                    if (buf.allowAlpha) {
                        xlColor c(hsv);
                        c.alpha = static_cast<uint8_t>(255.0 * (double(ph) / TailLength));
                        buf.SetPixel(x, y, c);
                    } else {
                        hsv.value *= double(ph) / TailLength;
                        buf.SetPixel(x, y, hsv);
                    }
                }
            }

            explodeMove(speed);
            explodeRemove();
        }

        // =====================================================================
        // ICICLES / ICICLES + BKG (variable-length drip)
        // =====================================================================
        else if (meteorMode == METEOR_ICICLES || meteorMode == METEOR_ICICLES_BKG) {
            bool want_bkg = (meteorMode == METEOR_ICICLES_BKG);

            auto icicleAdd = [&]() {
                MeteorParticle m;
                for (int i = 0; i < buf.BufferWi; i++) {
                    if (std::rand() % 200 < Count) {
                        m.x = i;
                        m.y = buf.BufferHt - 1;
                        m.h = (std::rand() % (2 * buf.BufferHt)) / 3;

                        assignColor(m.hsv, ColorScheme);
                        cache->meteors.push_back(m);
                    }
                }
            };

            auto icicleMove = [&](int spd) {
                for (auto& meteor : cache->meteors) {
                    meteor.y -= spd;
                }
            };

            auto icicleRemove = [&]() {
                cache->meteors.remove_if([](const MeteorParticle& obj) {
                    return obj.y < -obj.h;
                });
            };

            if (buf.curPeriod == buf.curEffStartPer) {
                for (int i = 0; i < warmupFrames; ++i) {
                    cache->effectState += calcEffectStateOffset(mSpeed);
                    int spd = static_cast<int>(cache->effectState) / 4;
                    cache->effectState -= spd * 4;

                    icicleAdd();
                    icicleMove(spd);
                    icicleRemove();
                }
            }

            cache->effectState += calcEffectStateOffset(mSpeed);
            int speed = static_cast<int>(cache->effectState) / 4;
            cache->effectState -= speed * 4;

            int TailLength = (buf.BufferHt < 10) ? Length / 10 : buf.BufferHt * Length / 100;
            if (TailLength < 1) TailLength = 1;

            icicleAdd();

            // Draw background icicles if requested
            if (want_bkg) {
                xlColor bkgColor(100, 50, 255); // light blue
                int ystaggered[] = { 0, 5, 1, 2, 4 };
                for (int x = 0; x < buf.BufferWi; x += 3)
                    for (int y = 0; y < buf.BufferHt; y += 3)
                        buf.SetPixel(x, y + ystaggered[(x / 3) % 5], bkgColor);
            }

            int n = 0;
            for (auto& meteor : cache->meteors) {
                for (int ph = 0; ph <= TailLength; ph++) {
                    HSVValue hsv;
                    if (!ph || (ph <= meteor.h - meteor.y))
                        hsv = meteor.hsv; // colored drip tip
                    else {
                        hsv.value = .4;
                        hsv.hue = hsv.saturation = 0;
                    } // white icicle body

                    float swirl_phase = float(meteor.y) / 5.0f + float(n) / 100.0f;
                    int dx = int(float(SwirlIntensity * buf.BufferWi) / 80.0f * buf.sin(swirl_phase));

                    int x = meteor.x + dx;
                    int y = meteor.y + ph;
                    if (y < meteor.h)
                        continue; // variable length icicle drip
                    buf.SetPixel(x, y, hsv);
                }
                n++;
            }

            icicleMove(speed);
            icicleRemove();
        }

        return true;
    }


    if (type == "Morph") {
        // Native Morph effect — port of legacy MorphEffect::Render
        // Morphing between two line segments (start→end) with head/tail coloring,
        // repeat/stagger support, and acceleration.

        double eff_pos = buf.GetEffectTimeIntervalPosition();

        // Read all settings with defaults matching legacy SetDefaultParameters
        int start_x1 = 0, start_y1 = 0, start_x2 = 100, start_y2 = 0;
        int end_x1 = 0, end_y1 = 100, end_x2 = 100, end_y2 = 100;
        int start_length = 1, end_length = 1;
        int duration = 20, acceleration = 0;
        int repeat_count = 0, repeat_skip = 1, stagger = 0;
        bool start_linked = false, end_linked = false;
        bool showEntireHeadAtStart = false, auto_repeat = false;

        auto it = effectInfo.settings.find("E_SLIDER_Morph_Start_X1");
        if (it != effectInfo.settings.end() && !it->second.empty())
            start_x1 = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Morph_Start_Y1");
        if (it != effectInfo.settings.end() && !it->second.empty())
            start_y1 = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Morph_Start_X2");
        if (it != effectInfo.settings.end() && !it->second.empty())
            start_x2 = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Morph_Start_Y2");
        if (it != effectInfo.settings.end() && !it->second.empty())
            start_y2 = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Morph_End_X1");
        if (it != effectInfo.settings.end() && !it->second.empty())
            end_x1 = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Morph_End_Y1");
        if (it != effectInfo.settings.end() && !it->second.empty())
            end_y1 = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Morph_End_X2");
        if (it != effectInfo.settings.end() && !it->second.empty())
            end_x2 = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Morph_End_Y2");
        if (it != effectInfo.settings.end() && !it->second.empty())
            end_y2 = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_MorphStartLength");
        if (it != effectInfo.settings.end() && !it->second.empty())
            start_length = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_MorphEndLength");
        if (it != effectInfo.settings.end() && !it->second.empty())
            end_length = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_MorphDuration");
        if (it != effectInfo.settings.end() && !it->second.empty())
            duration = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_MorphAccel");
        if (it != effectInfo.settings.end() && !it->second.empty())
            acceleration = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Morph_Repeat_Count");
        if (it != effectInfo.settings.end() && !it->second.empty())
            repeat_count = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Morph_Repeat_Skip");
        if (it != effectInfo.settings.end() && !it->second.empty())
            repeat_skip = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Morph_Stagger");
        if (it != effectInfo.settings.end() && !it->second.empty())
            stagger = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_CHECKBOX_Morph_Start_Link");
        if (it != effectInfo.settings.end())
            start_linked = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Morph_End_Link");
        if (it != effectInfo.settings.end())
            end_linked = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_ShowHeadAtStart");
        if (it != effectInfo.settings.end())
            showEntireHeadAtStart = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Morph_AutoRepeat");
        if (it != effectInfo.settings.end())
            auto_repeat = (it->second == "1");

        // Helper: calcPosition maps 0-100 percentage to buffer coordinate
        auto calcPosition = [](int value, int base) -> int {
            if (value == 100) return (base - 1);
            double band = 100.0 / (double)base;
            return (int)((double)value / band);
        };

        // Helper: Bresenham line rasterization into coordinate vectors
        auto storeLine = [](int x0, int y0, int x1, int y1,
                            std::vector<int>& vx, std::vector<int>& vy) {
            int dx = std::abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
            int dy = std::abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
            int err = (dx > dy ? dx : -dy) / 2, e2;
            for (;;) {
                vx.push_back(x0);
                vy.push_back(y0);
                if (x0 == x1 && y0 == y1) break;
                e2 = err;
                if (e2 > -dx) { err -= dy; x0 += sx; }
                if (e2 < dy)  { err += dx; y0 += sy; }
            }
        };

        double step_size = 0.1;

        // Determine color indices based on palette size
        int hcols = 0, hcole = 1;
        int tcols = 2, tcole = 3;
        int num_tail_colors = 2;
        switch (buf.palette.Size()) {
            case 1:
                hcols = hcole = tcols = tcole = 0;
                break;
            case 2:
                hcols = hcole = 0;
                tcols = tcole = 1;
                break;
            case 3:
                hcols = hcole = 0;
                tcols = 1;
                tcole = 2;
                break;
            default:
                num_tail_colors = (int)buf.palette.Size() - 2;
                break;
        }

        // Map percentage positions to buffer coordinates
        int x1a = calcPosition(start_x1, buf.BufferWi);
        int y1a = calcPosition(start_y1, buf.BufferHt);
        int x2a = calcPosition(end_x1, buf.BufferWi);
        int y2a = calcPosition(end_y1, buf.BufferHt);

        int x1b, x2b, y1b, y2b;

        if (start_linked) {
            x1b = x1a;
            y1b = y1a;
        } else {
            x1b = calcPosition(start_x2, buf.BufferWi);
            y1b = calcPosition(start_y2, buf.BufferHt);
        }

        if (end_linked) {
            x2b = x2a;
            y2b = y2a;
        } else {
            x2b = calcPosition(end_x2, buf.BufferWi);
            y2b = calcPosition(end_y2, buf.BufferHt);
        }

        xlColor head_color, tail_color;

        // Compute direction
        int delta_xa = x2a - x1a;
        int delta_xb = x2b - x1b;
        int delta_ya = y2a - y1a;
        int delta_yb = y2b - y1b;
        int direction = delta_xa + delta_xb + delta_ya + delta_yb;
        int repeat_x = 0;
        int repeat_y = 0;
        double effect_pct = 1.0;
        double stagger_pct = 0.0;
        if (repeat_count > 0 || auto_repeat) {
            int maxmodel;
            if ((std::abs((float)delta_xa) + std::abs((float)delta_xb)) <
                (std::abs((float)delta_ya) + std::abs((float)delta_yb))) {
                repeat_x = repeat_skip;
                maxmodel = buf.BufferWi;
            } else {
                repeat_y = repeat_skip;
                maxmodel = buf.BufferHt;
            }

            if (auto_repeat) {
                int startx = std::max(1, std::abs(start_x1 - start_x2) * buf.BufferWi / 100);
                int starty = std::max(1, std::abs(start_y1 - start_y2) * buf.BufferHt / 100);
                int endx = std::max(1, std::abs(end_x1 - end_x2) * buf.BufferWi / 100);
                int endy = std::max(1, std::abs(end_y1 - end_y2) * buf.BufferHt / 100);
                int minmorph = std::min(startx, std::min(starty, std::min(endx, endy)));
                repeat_count = (maxmodel / (minmorph + repeat_skip - 1)) - 1;
            }

            double stagger_val = (double)(std::abs((double)stagger)) / 200.0;
            effect_pct = 1.0 / (1 + stagger_val * repeat_count);
            stagger_pct = effect_pct * stagger_val;
        }

        // Rasterize the two sides (side a and side b) via Bresenham
        std::vector<int> v_ax, v_ay, v_bx, v_by;
        storeLine(x1a, y1a, x2a, y2a, v_ax, v_ay);
        storeLine(x1b, y1b, x2b, y2b, v_bx, v_by);

        int size_a = (int)v_ax.size();
        int size_b = (int)v_bx.size();

        // Pointers to the longer and shorter side vectors
        std::vector<int>* v_lngx;
        std::vector<int>* v_lngy;
        std::vector<int>* v_shtx;
        std::vector<int>* v_shty;

        if (size_a > size_b) {
            v_lngx = &v_ax; v_lngy = &v_ay;
            v_shtx = &v_bx; v_shty = &v_by;
        } else {
            v_lngx = &v_bx; v_lngy = &v_by;
            v_shtx = &v_ax; v_shty = &v_ay;
        }

        double pos_a, pos_b;
        double total_tail_length, alpha_pct;
        double total_length = (double)v_lngx->size();
        double head_duration = duration / 100.0;
        double head_end_of_head_pos = total_length + 1;
        double tail_end_of_head_pos = total_length + 1;
        double head_end_of_tail_pos = -1;
        double tail_end_of_tail_pos = -1;

        for (int repeat = 0; repeat <= repeat_count; repeat++) {
            double eff_pos_adj = buf.calcAccel(eff_pos, acceleration);
            double eff_start_pct = (stagger >= 0) ? stagger_pct * repeat : stagger_pct * (repeat_count - repeat);
            double eff_end_pct = eff_start_pct + effect_pct;
            eff_pos_adj = (eff_pos_adj - eff_start_pct) / (eff_end_pct - eff_start_pct);
            if (eff_pos_adj < 0.0) {
                head_end_of_head_pos = -1;
                tail_end_of_head_pos = -1;
                head_end_of_tail_pos = -1;
                tail_end_of_tail_pos = -1;
                total_tail_length = 1.0;
                if (showEntireHeadAtStart) {
                    head_end_of_head_pos = start_length;
                }
            } else {
                if (head_duration > 0.0) {
                    double head_loc_pct = eff_pos_adj / head_duration;
                    head_end_of_head_pos = total_length * head_loc_pct;
                    double current_total_head_length = end_length * head_loc_pct + start_length * (1.0 - head_loc_pct);
                    head_end_of_head_pos += current_total_head_length * head_loc_pct * head_duration;
                    total_tail_length = total_length * (1 / head_duration - 1.0);
                    if (showEntireHeadAtStart) {
                        head_end_of_head_pos += current_total_head_length * (1.0 - eff_pos_adj);
                    }
                    tail_end_of_head_pos = head_end_of_head_pos - current_total_head_length;
                    head_end_of_tail_pos = tail_end_of_head_pos - step_size;
                    tail_end_of_tail_pos = head_end_of_tail_pos - total_tail_length;
                    buf.Get2ColorBlend(hcols, hcole, std::min(head_loc_pct, 1.0), head_color);
                } else {
                    total_tail_length = total_length;
                    head_end_of_tail_pos = total_length * 2 * eff_pos_adj;
                    tail_end_of_tail_pos = head_end_of_tail_pos - total_tail_length;
                }
            }

            // Draw the tail
            for (double i = std::min(head_end_of_tail_pos, total_length - 1);
                 i >= tail_end_of_tail_pos && i >= 0.0; i -= step_size) {
                double pct = ((total_length == 0) ? 0.0 : i / total_length);
                pos_a = i;
                pos_b = v_shtx->size() * pct;
                double tail_color_pct = (i - tail_end_of_tail_pos) / total_tail_length;
                if (num_tail_colors > 2) {
                    double color_index = ((double)num_tail_colors - 1.0) * (1.0 - tail_color_pct);
                    tail_color_pct = color_index - (double)((int)color_index);
                    tcols = (int)color_index + 2;
                    tcole = tcols + 1;
                    if (tcole == num_tail_colors + 1) {
                        alpha_pct = (1.0 - tail_color_pct);
                    } else {
                        alpha_pct = 1.0;
                    }
                    buf.Get2ColorBlend(tcols, tcole, tail_color_pct, tail_color);
                } else {
                    if (tail_color_pct > 0.5) {
                        alpha_pct = 1.0;
                    } else {
                        alpha_pct = tail_color_pct / 0.5;
                    }
                    buf.Get2ColorBlend(tcole, tcols, tail_color_pct, tail_color);
                }
                if (buf.allowAlpha) {
                    tail_color.alpha = (uint8_t)(255 * alpha_pct);
                }
                buf.DrawThickLine(
                    (*v_lngx)[(int)pos_a] + (repeat_x * repeat),
                    (*v_lngy)[(int)pos_a] + (repeat_y * repeat),
                    (*v_shtx)[(int)pos_b] + (repeat_x * repeat),
                    (*v_shty)[(int)pos_b] + (repeat_y * repeat),
                    tail_color, direction >= 0);
            }

            // Draw the head
            for (double i = std::max(tail_end_of_head_pos, 0.0);
                 i <= head_end_of_head_pos && i < total_length; i += step_size) {
                double pct = ((total_length == 0) ? 0.0 : i / total_length);
                pos_a = i;
                pos_b = v_shtx->size() * pct;
                buf.DrawThickLine(
                    (*v_lngx)[(int)pos_a] + (repeat_x * repeat),
                    (*v_lngy)[(int)pos_a] + (repeat_y * repeat),
                    (*v_shtx)[(int)pos_b] + (repeat_x * repeat),
                    (*v_shty)[(int)pos_b] + (repeat_y * repeat),
                    head_color, direction >= 0);
            }
        }

        return true;
    }


    if (type == "Off") {
        std::string style = "Black";
        auto it = effectInfo.settings.find("E_CHOICE_Off_Style");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            style = it->second;
        }

        if (style == "Transparent") {
            // Don't change any pixels — leave buffer as-is
        } else if (style == "Black") {
            buf.Fill(xlBLACK);
        } else if (style == "Black -> Transparent") {
            for (uint32_t i = 0; i < buf.GetPixelCount(); ++i) {
                if (buf.GetPixels()[i] == xlBLACK) {
                    buf.GetPixels()[i] = xlCLEAR;
                }
            }
        } else if (style == "Transparent -> Black") {
            for (uint32_t i = 0; i < buf.GetPixelCount(); ++i) {
                if (buf.GetPixels()[i] == xlCLEAR) {
                    buf.GetPixels()[i] = xlBLACK;
                }
            }
        }

        return true;
    }


    if (type == "Pinwheel") {
        // Native Pinwheel effect — port of legacy PinwheelEffect::Render
        // Supports both "New Render Method" (per-pixel) and old method (per-arm sweep).
        constexpr float PI_F = 3.14159265358979323846f;
        constexpr float PI_180 = PI_F / 180.0f;
        constexpr int PINWHEEL_SPEED_MAX = 50;

        float eff_pos = buf.GetEffectTimeIntervalPosition();

        // Read settings from effectInfo.settings with defaults
        int pinwheel_arms = 3;
        int pinwheel_twist = 0;
        int pinwheel_thickness = 0;
        bool pinwheel_rotation = true; // true = CW
        int pspeed = 10;
        int xc_adj = 0;
        int yc_adj = 0;
        int pinwheel_armsize = 100;
        int poffset = 0;
        std::string pinwheel_3d_str = "none";
        std::string pinwheel_style = "New Render Method";

        auto it = effectInfo.settings.find("E_SLIDER_Pinwheel_Arms");
        if (it != effectInfo.settings.end() && !it->second.empty())
            pinwheel_arms = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Pinwheel_Twist");
        if (it != effectInfo.settings.end() && !it->second.empty())
            pinwheel_twist = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Pinwheel_Thickness");
        if (it != effectInfo.settings.end() && !it->second.empty())
            pinwheel_thickness = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Pinwheel_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            pspeed = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Pinwheel_Offset");
        if (it != effectInfo.settings.end() && !it->second.empty())
            poffset = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_PinwheelXC");
        if (it != effectInfo.settings.end() && !it->second.empty())
            xc_adj = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_PinwheelYC");
        if (it != effectInfo.settings.end() && !it->second.empty())
            yc_adj = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Pinwheel_ArmSize");
        if (it != effectInfo.settings.end() && !it->second.empty())
            pinwheel_armsize = std::atoi(it->second.c_str());

        // Rotation: legacy uses E_CHECKBOX_Pinwheel_Rotation (checkbox, "1"=CW)
        // Native panel uses E_CHOICE_Pinwheel_Rotation ("CW"/"CCW")
        it = effectInfo.settings.find("E_CHECKBOX_Pinwheel_Rotation");
        if (it != effectInfo.settings.end())
            pinwheel_rotation = (it->second == "1");
        it = effectInfo.settings.find("E_CHOICE_Pinwheel_Rotation");
        if (it != effectInfo.settings.end())
            pinwheel_rotation = (it->second == "CW");

        it = effectInfo.settings.find("E_CHOICE_Pinwheel_3D");
        if (it != effectInfo.settings.end() && !it->second.empty())
            pinwheel_3d_str = it->second;
        it = effectInfo.settings.find("E_CHOICE_Pinwheel_Style");
        if (it != effectInfo.settings.end() && !it->second.empty())
            pinwheel_style = it->second;

        // Parse 3D type: 0=None, 1=3D, 2=3D Inverted, 3=Sweep
        int pw3dType = 0;
        if (pinwheel_3d_str == "3D") pw3dType = 1;
        else if (pinwheel_3d_str == "3D Inverted") pw3dType = 2;
        else if (pinwheel_3d_str == "Sweep") pw3dType = 3;

        if (pinwheel_arms < 1) pinwheel_arms = 1;
        int degrees_per_arm = 360 / pinwheel_arms;
        float armsize = pinwheel_armsize / 100.0f;

        size_t colorcnt = buf.GetColorCount();
        if (colorcnt == 0) colorcnt = 1;

        // Lambda: apply 3D color adjustment
        auto adjustColor = [&](xlColor& color, HSVValue& hsv, float round) {
            switch (pw3dType) {
                case 1: // 3D
                    if (buf.allowAlpha) {
                        color.alpha = static_cast<uint8_t>(255.0f - 255.0f * std::abs(round - 0.5f) / 0.5f);
                    } else {
                        hsv.value = 1.0 - hsv.value * std::abs(round - 0.5) / 0.5;
                        color = hsv;
                    }
                    break;
                case 2: // 3D Inverted
                    if (buf.allowAlpha) {
                        color.alpha = static_cast<uint8_t>(255.0f * std::abs(round - 0.5f) / 0.5f);
                    } else {
                        hsv.value = hsv.value * std::abs(round - 0.5) / 0.5;
                        color = hsv;
                    }
                    break;
                case 3: // Sweep
                    if (buf.allowAlpha) {
                        color.alpha = static_cast<uint8_t>(255.0f * round);
                    } else {
                        hsv.value = hsv.value * round;
                        color = hsv;
                    }
                    break;
                default:
                    break;
            }
        };

        if (pinwheel_style == "New Render Method") {
            // --- New Render Method: per-pixel approach (ported from ISPC PinwheelEffectStyle0) ---
            // Compute timing position based on frame count within effect
            float pos = static_cast<float>(
                (buf.curPeriod - buf.curEffStartPer) * pspeed * buf.frameTimeInMs)
                / static_cast<float>(PINWHEEL_SPEED_MAX);

            // Compute center and max_radius
            int xc_half = static_cast<int>(std::ceil(std::hypot(
                static_cast<float>(buf.BufferWi), static_cast<float>(buf.BufferHt)) / 2.0f));
            int xc_adj_px = (xc_adj * buf.BufferWi) / 200;
            int yc_adj_px = (yc_adj * buf.BufferHt) / 200;
            int max_radius = static_cast<int>(xc_half * armsize);

            if (pinwheel_thickness == 0) pinwheel_thickness = 1;
            float tmax = (pinwheel_thickness / 100.0f) * degrees_per_arm;

            // First pass: draw center lines for each arm (ensures visibility even on thin arms)
            for (int a = 0; a < pinwheel_arms; a++) {
                int colorIdx = (a + 1) % static_cast<int>(colorcnt);
                xlColor color;
                HSVValue hsv;
                buf.palette.GetColor(colorIdx, color);
                buf.palette.GetHSV(colorIdx, hsv);

                int angle = a * degrees_per_arm;
                if (pinwheel_rotation) {
                    angle = (270 - angle) + static_cast<int>(pos) + poffset;
                } else {
                    angle = angle - 90 - static_cast<int>(pos) - poffset;
                }

                if (max_radius != 0) {
                    for (float r = 0; r <= max_radius; r += 0.5f) {
                        int degrees_twist_r = static_cast<int>((r / max_radius) * pinwheel_twist);
                        int x = static_cast<int>(std::floor(
                            r * buf.cos((angle + degrees_twist_r) * PI_180)
                            + xc_adj_px + buf.BufferWi / 2));
                        int y = static_cast<int>(std::floor(
                            r * buf.sin((angle + degrees_twist_r) * PI_180)
                            + yc_adj_px + buf.BufferHt / 2));
                        buf.SetPixel(x, y, color);
                    }
                }
            }

            // Second pass: fill arms per-pixel (ported from ISPC kernel)
            if (max_radius != 0) {
                float halfW = static_cast<float>(buf.BufferWi) / 2.0f;
                float halfH = static_cast<float>(buf.BufferHt) / 2.0f;

                for (int y = 0; y < buf.BufferHt; y++) {
                    for (int x = 0; x < buf.BufferWi; x++) {
                        float y1 = static_cast<float>(y) - yc_adj_px - halfH;
                        float x1 = static_cast<float>(x) - xc_adj_px - halfW;
                        float r = std::sqrt(x1 * x1 + y1 * y1);

                        if (r <= max_radius && r > 0) {
                            float degrees_twist_r = (r / max_radius) * pinwheel_twist;
                            float theta = (std::atan2(x1, y1) * 180.0f / PI_F) + degrees_twist_r;
                            if (std::isnan(theta)) theta = 0.0f;

                            if (pinwheel_rotation) {
                                theta = pos + theta + (tmax / 2.0f) + poffset;
                            } else {
                                theta = pos - theta + (tmax / 2.0f) + poffset;
                            }

                            theta = theta + 540.0f;
                            int t2 = static_cast<int>(theta) % degrees_per_arm;
                            if (t2 <= static_cast<int>(tmax)) {
                                float round = static_cast<float>(t2) / tmax;
                                int t2_centered = std::abs(t2 - static_cast<int>(tmax / 2.0f)) * 2;
                                int colorIdx2 = (static_cast<int>(theta / degrees_per_arm)) % pinwheel_arms;

                                xlColor color;
                                HSVValue hsv;
                                buf.palette.GetColor(colorIdx2, color);
                                buf.palette.GetHSV(colorIdx2, hsv);

                                adjustColor(color, hsv, round);
                                buf.SetPixel(x, y, color);
                            }
                        }
                    }
                }
            }
        } else {
            // --- Old Render Method: per-arm radial sweep ---
            // Used by styles other than "New Render Method"
            double pos = static_cast<double>(
                (buf.curPeriod - buf.curEffStartPer) * pspeed * buf.frameTimeInMs)
                / static_cast<double>(PINWHEEL_SPEED_MAX);

            int xc = std::max(buf.BufferWi, buf.BufferHt) / 2;

            for (int a = 1; a <= pinwheel_arms; a++) {
                int colorIdx = a % static_cast<int>(colorcnt);

                int base_degrees;
                if (pinwheel_rotation) {
                    base_degrees = static_cast<int>((a - 1) * degrees_per_arm + pos + poffset);
                } else {
                    base_degrees = static_cast<int>((a - 1) * degrees_per_arm - pos + poffset);
                }

                float tmax_old = (pinwheel_thickness / 100.0f) * degrees_per_arm / 2.0f;
                for (float t = base_degrees - tmax_old; t <= base_degrees + tmax_old; t += 1.0f) {
                    float round = (t - base_degrees + tmax_old) / (2.0f * tmax_old + 1.0f);

                    // Draw arm at angle t
                    int arm_max_radius = static_cast<int>(xc * armsize);
                    int arm_xc = buf.BufferWi / 2;
                    int arm_yc = buf.BufferHt / 2;
                    arm_xc = arm_xc + ((xc_adj * arm_xc) / 100);
                    arm_yc = arm_yc + ((yc_adj * arm_yc) / 100);

                    xlColor color;
                    HSVValue hsv;
                    buf.palette.GetColor(colorIdx, color);
                    hsv = color.asHSV();
                    adjustColor(color, hsv, round);

                    if (arm_max_radius != 0) {
                        for (float r = 0.0f; r <= arm_max_radius; r += 0.5f) {
                            int degrees_twist_r = static_cast<int>((r / arm_max_radius) * pinwheel_twist);
                            int degrees = static_cast<int>(t) + degrees_twist_r;
                            float phi = degrees * PI_180;
                            int px = static_cast<int>(r * buf.cos(phi) + arm_xc);
                            int py = static_cast<int>(r * buf.sin(phi) + arm_yc);
                            buf.SetPixel(px, py, color);
                        }
                    }
                }
            }
        }
        return true;
    }


    if (type == "Plasma") {
        // Native Plasma effect — port of legacy PlasmaEffect + ISPC PlasmaFunctions
        // Reference: http://www.bidouille.org/prog/plasma

        // Read settings from native panel definitions
        int Style = 1;
        int Line_Density = 1;
        int PlasmaSpeed = 10;
        int ColorScheme = 0; // 0=Normal, 1=Preset1, 2=Preset2, 3=Preset3, 4=Preset4

        auto it = effectInfo.settings.find("E_CHOICE_Plasma_Algorithm");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            const std::string& alg = it->second;
            if (alg == "Plasma 1") Style = 1;
            else if (alg == "Plasma 2") Style = 2;
            else if (alg == "Plasma 3") Style = 3;
            else if (alg == "Plasma 4") Style = 4;
            else if (alg == "Plasma 5") Style = 5;
            else if (alg == "Plasma 6") Style = 6;
        }

        it = effectInfo.settings.find("E_SLIDER_Plasma_Line_Density");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Line_Density = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Plasma_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            PlasmaSpeed = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_CHOICE_Plasma_Color");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            const std::string& cs = it->second;
            if (cs == "Normal") ColorScheme = 0;
            else if (cs == "Preset 1") ColorScheme = 1;
            else if (cs == "Preset 2") ColorScheme = 2;
            else if (cs == "Preset 3") ColorScheme = 3;
            else if (cs == "Preset 4") ColorScheme = 4;
        }

        int width = buf.BufferWi;
        int height = buf.BufferHt;
        if (width < 1) width = 1;
        if (height < 1) height = 1;

        // Compute time-based animation state (matches legacy exactly)
        int state = buf.curPeriod - buf.curEffStartPer; // frames 0 to N
        double Speed_plasma = (101 - PlasmaSpeed) * 3; // large divisor
        double time = (state + 1.0) / Speed_plasma;

        double sin_time_5 = std::sin(time / 5.0);
        double cos_time_3 = std::cos(time / 3.0);
        double sin_time_2 = std::sin(time / 2.0);

        constexpr double PI = M_PI;
        constexpr double pi3 = M_PI / 3.0;

        // Lambda: compute the plasma value for a pixel (port of plasmaCalc_vldpi)
        auto plasmaCalc = [&](double x, double y) -> double {
            double rx = width > 1 ? (x / (double)(width - 1)) : 0.0;
            double rx2 = rx * rx;
            double cx = rx + 0.5 * sin_time_5;
            double cx2 = cx * cx;
            double sin_rx_time = std::sin(rx + time);

            // 1st equation
            double v = std::sin(rx * 10.0 + time);
            double ry = height > 1 ? (y / (double)(height - 1)) : 0.0;

            // 2nd equation
            v += std::sin(10.0 * (rx * sin_time_2 + ry * cos_time_3) + time);

            // 3rd equation
            double cy = ry + 0.5 * cos_time_3;
            v += std::sin(std::sqrt((Style * 50.0) * (cx2 + cy * cy) + time));

            // 4th-6th equations
            v += sin_rx_time;
            v += std::sin((ry + time) / 2.0);
            v += std::sin((rx + ry + time) / 2.0);

            // 7th equation
            v += std::sin(std::sqrt(rx2 + ry * ry) + time);
            v = v / 2.0;

            return v * Line_Density * PI;
        };

        // Render each pixel based on the color scheme
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                double vldpi = plasmaCalc((double)x, (double)y);
                xlColor color;

                switch (ColorScheme) {
                    case 0: {
                        // Normal: use palette multi-color blend
                        double h = (std::sin(vldpi + 2.0 * pi3) + 1.0) * 0.5;
                        buf.GetMultiColorBlend(static_cast<float>(h), false, color);
                        break;
                    }
                    case 1: {
                        // Preset 1: red/green channels from sin/cos
                        uint8_t r = (uint8_t)((std::sin(vldpi) + 1.0) * 255.0 / 2.0);
                        uint8_t g = (uint8_t)((std::cos(vldpi) + 1.0) * 255.0 / 2.0);
                        color.Set(r, g, 0);
                        break;
                    }
                    case 2: {
                        // Preset 2: blue/green from sin/cos, red=1
                        uint8_t b = (uint8_t)((std::sin(vldpi) + 1.0) * 255.0 / 2.0);
                        uint8_t g = (uint8_t)((std::cos(vldpi) + 1.0) * 255.0 / 2.0);
                        color.Set(1, g, b);
                        break;
                    }
                    case 3: {
                        // Preset 3: RGB from sin with phase offsets
                        uint8_t r = (uint8_t)((std::sin(vldpi) + 1.0) * 255.0 / 2.0);
                        uint8_t g = (uint8_t)((std::sin(vldpi + 2.0 * pi3) + 1.0) * 255.0 / 2.0);
                        uint8_t b = (uint8_t)((std::sin(vldpi + 4.0 * pi3) + 1.0) * 255.0 / 2.0);
                        color.Set(r, g, b);
                        break;
                    }
                    case 4: {
                        // Preset 4: grayscale from sin
                        uint8_t v = (uint8_t)((std::sin(vldpi) + 1.0) * 255.0 / 2.0);
                        color.Set(v, v, v);
                        break;
                    }
                    default: {
                        double h = (std::sin(vldpi + 2.0 * pi3) + 1.0) * 0.5;
                        buf.GetMultiColorBlend(static_cast<float>(h), false, color);
                        break;
                    }
                }

                buf.SetPixel(x, y, color);
            }
        }
        return true;
    }


    if (type == "Ripple") {
        // Native Ripple effect — port of legacy RippleEffect::Render (Old style)
        //
        // Settings keys (from XLEffectPanelDefinitions.mm / RippleEffect.h):
        //   E_CHOICE_Ripple_Object_To_Draw  — Circle, Square, Triangle, Star, Polygon,
        //                                      Heart, Tree, Candy Cane, Snow Flake,
        //                                      Crucifix, Present
        //   E_CHOICE_Ripple_Movement        — Explode, Implode, None
        //   E_SLIDER_Ripple_Thickness       — 1..100 (default 3)
        //   E_SLIDER_Ripple_Cycles          — 0..500 (raw slider; /10 = 0..50 cycles, default 10 = 1.0)
        //   E_SLIDER_Ripple_Points          — 4..7 (default 5, for Star/Polygon/Snowflake)
        //   E_SLIDER_Ripple_Rotation        — 0..359 (default 0)
        //   E_CHECKBOX_Ripple_3D            — "1"/"0" (default 0)

        // --- Helper lambdas for reading settings ---
        auto getSettingStr = [&](const char* key, const char* def) -> std::string {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty())
                return it->second;
            return def;
        };
        auto getSettingInt = [&](const char* key, int def) -> int {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty())
                return std::atoi(it->second.c_str());
            return def;
        };
        auto getSettingBool = [&](const char* key, bool def) -> bool {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty())
                return it->second == "1";
            return def;
        };

        // Read parameters
        std::string objectStr = getSettingStr("E_CHOICE_Ripple_Object_To_Draw", "Circle");
        std::string movementStr = getSettingStr("E_CHOICE_Ripple_Movement", "Explode");
        int thickness = getSettingInt("E_SLIDER_Ripple_Thickness", 3);
        int cyclesRaw = getSettingInt("E_SLIDER_Ripple_Cycles", 10);
        float cycles = static_cast<float>(cyclesRaw) / 10.0f;  // divisor = 10
        int points = getSettingInt("E_SLIDER_Ripple_Points", 5);
        int rotation = getSettingInt("E_SLIDER_Ripple_Rotation", 0);
        bool is3D = getSettingBool("E_CHECKBOX_Ripple_3D", false);

        // Movement constants
        const int MOVEMENT_EXPLODE = 0;
        const int MOVEMENT_IMPLODE = 1;
        // const int MOVEMENT_NONE = 2;  // not used by old-style draw

        int movement = MOVEMENT_EXPLODE;
        if (movementStr == "Implode") movement = MOVEMENT_IMPLODE;
        // "None" and others fall through to explode behavior in old-style

        // Object type constants
        const int OBJ_CIRCLE    = 0;
        const int OBJ_SQUARE    = 1;
        const int OBJ_TRIANGLE  = 2;
        const int OBJ_STAR      = 3;
        const int OBJ_POLYGON   = 4;
        const int OBJ_HEART     = 5;
        const int OBJ_TREE      = 6;
        const int OBJ_CANDYCANE = 7;
        const int OBJ_SNOWFLAKE = 8;
        const int OBJ_CRUCIFIX  = 9;
        const int OBJ_PRESENT   = 10;

        int objectType = OBJ_CIRCLE;
        if (objectStr == "Square")       objectType = OBJ_SQUARE;
        else if (objectStr == "Triangle")  objectType = OBJ_TRIANGLE;
        else if (objectStr == "Star")      objectType = OBJ_STAR;
        else if (objectStr == "Polygon")   objectType = OBJ_POLYGON;
        else if (objectStr == "Heart")     objectType = OBJ_HEART;
        else if (objectStr == "Tree")      objectType = OBJ_TREE;
        else if (objectStr == "Candy Cane") objectType = OBJ_CANDYCANE;
        else if (objectStr == "Snow Flake") objectType = OBJ_SNOWFLAKE;
        else if (objectStr == "Crucifix")  objectType = OBJ_CRUCIFIX;
        else if (objectStr == "Present")   objectType = OBJ_PRESENT;

        // Time position
        float oset = buf.GetEffectTimeIntervalPosition();
        double position = buf.GetEffectTimeIntervalPosition(cycles);

        // Center coordinates (xcc/ycc default to 0 in native panel)
        int xcc = 0;
        int ycc = 0;

        int xc = buf.BufferWi / 2 + xcc * (buf.BufferWi / 2) / 100;
        int yc = buf.BufferHt / 2 + ycc * (buf.BufferHt / 2) / 100;

        // Calculate max radius
        double maxRadius = 0.0;
        double maxRadiusX = std::max(xc, buf.BufferWi - xc);
        double maxRadiusY = std::max(yc, buf.BufferHt - yc);
        if (buf.BufferWi > buf.BufferHt) {
            maxRadius = maxRadiusX;
        } else {
            maxRadius = maxRadiusY;
        }

        float rx = static_cast<float>(position);

        // Color index based on position through the palette
        size_t colorcnt = buf.GetColorCount();
        int ColorIdx = static_cast<int>(rx * colorcnt);
        if (ColorIdx >= static_cast<int>(colorcnt))
            ColorIdx = static_cast<int>(colorcnt) - 1;
        if (ColorIdx < 0) ColorIdx = 0;

        // Calculate radius based on movement
        double radius, radiusX, radiusY, side;
        if (movement == MOVEMENT_IMPLODE) {
            radius = maxRadius - (maxRadius * rx);
            side = maxRadius - (maxRadius * rx);
            radiusX = maxRadiusX - (maxRadiusX * rx);
            radiusY = maxRadiusY - (maxRadiusY * rx);
        } else {
            radius = maxRadius * rx;
            side = maxRadius * rx;
            radiusX = maxRadiusX * rx;
            radiusY = maxRadiusY * rx;
        }

        HSVValue hsv;
        buf.palette.GetHSV(ColorIdx, hsv);

        // ---- Shape drawing (Old-style) ----

        if (objectType == OBJ_CIRCLE) {
            // Drawcircle
            xlColor color(hsv);
            for (float i = 0; i < thickness; i += 0.5f) {
                if (is3D) {
                    if (buf.allowAlpha) {
                        color.alpha = static_cast<uint8_t>(255.0 * (1.0 - (i / static_cast<float>(thickness))));
                    } else {
                        hsv.value *= 1.0 - (i / static_cast<float>(thickness));
                        color = hsv;
                    }
                }
                double r = radius;
                if (movement == MOVEMENT_EXPLODE) {
                    r = radius + i;
                } else {
                    r = radius - i;
                }
                if (r >= 0.0) {
                    for (double degrees = 0.0; degrees < 360.0; degrees += 1.0) {
                        double radian = degrees * (M_PI / 180.0);
                        int x = static_cast<int>(r * std::cos(radian) + xc);
                        int y = static_cast<int>(r * std::sin(radian) + yc);
                        buf.SetPixel(x, y, color);
                    }
                }
            }
        } else if (objectType == OBJ_SQUARE) {
            // Drawsquare
            int x1 = xc - static_cast<int>(radiusX);
            int x2 = xc + static_cast<int>(radiusX);
            int y1 = yc - static_cast<int>(radiusY);
            int y2 = yc + static_cast<int>(radiusY);

            xlColor color(hsv);
            for (int i = 0; i < thickness; i++) {
                if (is3D) {
                    if (buf.allowAlpha) {
                        color.alpha = static_cast<uint8_t>(255.0 * (1.0 - ((static_cast<float>(i) / 2.0f) / static_cast<float>(thickness))));
                    } else {
                        hsv.value *= 1.0 - ((static_cast<float>(i) / 2.0f) / static_cast<float>(thickness));
                        color = hsv;
                    }
                }
                if (movement == MOVEMENT_EXPLODE) {
                    for (int y = y1 + i; y <= y2 - i; y++) {
                        buf.SetPixel(x1 + i, y, color);
                        buf.SetPixel(x2 - i, y, color);
                    }
                    for (int x = x1 + i; x <= x2 - i; x++) {
                        buf.SetPixel(x, y1 + i, color);
                        buf.SetPixel(x, y2 - i, color);
                    }
                } else {
                    for (int y = y2 + i; y >= y1 - i; y--) {
                        buf.SetPixel(x1 - i, y, color);
                        buf.SetPixel(x2 + i, y, color);
                    }
                    for (int x = x2 + i; x >= x1 - i; x--) {
                        buf.SetPixel(x, y1 - i, color);
                        buf.SetPixel(x, y2 + i, color);
                    }
                }
            }
        } else if (objectType == OBJ_TRIANGLE) {
            // Drawtriangle
            if (side >= 0) {
                const double ROOT3DIV3 = 0.577350269;
                const double SIN30 = 0.5;
                const double COS30 = 0.866025404;

                xlColor color(hsv);
                for (int i = 0; i < thickness; i++) {
                    double r = (side + i) * ROOT3DIV3;
                    double ytop = yc + r;
                    int xtop = xc;
                    double xleft = xc - r * COS30;
                    double yleft = yc - r * SIN30;
                    double xright = xleft + side + i;
                    double yright = yleft;

                    if (is3D) {
                        if (buf.allowAlpha) {
                            color.alpha = static_cast<uint8_t>(255.0 * (1.0 - ((static_cast<float>(i) / 2.0f) / static_cast<float>(thickness))));
                        } else {
                            hsv.value *= 1.0 - ((static_cast<float>(i) / 2.0f) / static_cast<float>(thickness));
                            color = hsv;
                        }
                    }

                    buf.DrawLine(xtop, static_cast<int>(ytop),
                                 static_cast<int>(xleft), static_cast<int>(yleft), color);
                    buf.DrawLine(xtop, static_cast<int>(ytop),
                                 static_cast<int>(xright), static_cast<int>(yright), color);
                    buf.DrawLine(static_cast<int>(xleft), static_cast<int>(yleft),
                                 static_cast<int>(xright), static_cast<int>(yright), color);
                }
            }
        } else if (objectType == OBJ_STAR) {
            // Drawstar
            double offsetangle = 0.0;
            switch (points) {
                case 3: offsetangle = 90.0 - 360.0 / 3; break;
                case 4: break;
                case 5: offsetangle = 90.0 - 360.0 / 5; break;
                case 6: offsetangle = 30.0; break;
                case 7: offsetangle = 90.0 - 360.0 / 7; break;
                case 8: offsetangle = 90.0 - 360.0 / 8; break;
                default: break;
            }

            xlColor color(hsv);
            double drawRadius = radius;
            for (double i = 0; i < thickness; i += 0.5) {
                if (is3D) {
                    if (buf.allowAlpha) {
                        color.alpha = static_cast<uint8_t>(255.0 * (1.0 - (i / static_cast<double>(thickness))));
                    } else {
                        hsv.value *= 1.0 - (i / static_cast<double>(thickness));
                        color = hsv;
                    }
                }
                if (movement == MOVEMENT_EXPLODE) {
                    drawRadius = radius + i;
                } else {
                    drawRadius = radius - i;
                }

                if (drawRadius >= 0.0) {
                    double InnerRadius = drawRadius / 2.618034;
                    double increment = 360.0 / points;

                    for (double degrees = 0.0; degrees < 361.0; degrees += increment) {
                        double deg = degrees;
                        if (deg > 360.0) deg = 360.0;
                        double radian = (rotation + offsetangle + deg) * (M_PI / 180.0);
                        int xouter = static_cast<int>(drawRadius * std::cos(radian) + xc);
                        int youter = static_cast<int>(drawRadius * std::sin(radian) + yc);

                        radian = (rotation + offsetangle + deg + increment / 2.0) * (M_PI / 180.0);
                        int xinner = static_cast<int>(InnerRadius * std::cos(radian) + xc);
                        int yinner = static_cast<int>(InnerRadius * std::sin(radian) + yc);
                        buf.DrawLine(xinner, yinner, xouter, youter, color);

                        radian = (rotation + offsetangle + deg - increment / 2.0) * (M_PI / 180.0);
                        xinner = static_cast<int>(InnerRadius * std::cos(radian) + xc);
                        yinner = static_cast<int>(InnerRadius * std::sin(radian) + yc);
                        buf.DrawLine(xinner, yinner, xouter, youter, color);

                        if (deg >= 360.0) break;
                    }
                }
            }
        } else if (objectType == OBJ_POLYGON) {
            // Drawpolygon
            double increment = 360.0 / points;
            double polyRot = static_cast<double>(rotation);
            if (points % 2 != 0) polyRot += 90;
            if (points == 4) polyRot += 45;
            if (points == 8) polyRot += 22.5;

            xlColor color(hsv);
            double drawRadius = radius;
            for (double i = 0; i < thickness; i += 0.5) {
                if (is3D) {
                    if (buf.allowAlpha) {
                        color.alpha = static_cast<uint8_t>(255.0 * (1.0 - (i / static_cast<double>(thickness))));
                    } else {
                        hsv.value *= 1.0 - (i / static_cast<double>(thickness));
                        color = hsv;
                    }
                }
                if (movement == MOVEMENT_EXPLODE) {
                    drawRadius = radius + i;
                } else {
                    drawRadius = radius - i;
                }

                if (drawRadius >= 0) {
                    for (double degrees = 0.0; degrees < 361.0; degrees += increment) {
                        double deg = degrees;
                        if (deg > 360.0) deg = 360.0;
                        double radian = (polyRot + deg) * M_PI / 180.0;
                        int x1 = static_cast<int>(std::round(drawRadius * std::cos(radian))) + xc;
                        int y1 = static_cast<int>(std::round(drawRadius * std::sin(radian))) + yc;

                        radian = (polyRot + deg + increment) * M_PI / 180.0;
                        int x2 = static_cast<int>(std::round(drawRadius * std::cos(radian))) + xc;
                        int y2 = static_cast<int>(std::round(drawRadius * std::sin(radian))) + yc;

                        buf.DrawLine(x1, y1, x2, y2, color);
                        if (deg >= 360.0) break;
                    }
                } else {
                    break;
                }
            }
        } else if (objectType == OBJ_HEART) {
            // Drawheart
            xlColor color(hsv);
            double drawRadius = radius;
            for (float i = 0; i < thickness; i += 0.5f) {
                if (is3D) {
                    if (buf.allowAlpha) {
                        color.alpha = static_cast<uint8_t>(255.0 * (1.0 - (i / static_cast<float>(thickness))));
                    } else {
                        hsv.value *= 1.0 - (i / static_cast<float>(thickness));
                        color = hsv;
                    }
                }
                if (movement == MOVEMENT_EXPLODE) {
                    drawRadius = radius + i;
                } else {
                    drawRadius = radius - i;
                }

                if (drawRadius >= 0) {
                    double xincr = 0.01;
                    for (double x = -2.0; x <= 2.0; x += xincr) {
                        double y1 = std::sqrt(1.0 - (std::abs(x) - 1.0) * (std::abs(x) - 1.0));
                        double y2 = std::acos(1.0 - std::abs(x)) - M_PI;

                        double xx1 = std::round((x * drawRadius) / 2.0) + xc;
                        double yy1 = (y1 * drawRadius) / 2.0 + yc;
                        double yy2 = (y2 * drawRadius) / 2.0 + yc;

                        if (drawRadius >= 0) {
                            buf.SetPixel(static_cast<int>(xx1), static_cast<int>(std::round(yy1)), color);
                            buf.SetPixel(static_cast<int>(xx1), static_cast<int>(std::round(yy2)), color);

                            if (x + xincr > 2.0 || x == -2.0 + xincr) {
                                if (yy1 > yy2)
                                    std::swap(yy1, yy2);
                                for (double z = yy1; z < yy2; z += 0.5) {
                                    buf.SetPixel(static_cast<int>(xx1), static_cast<int>(std::round(z)), color);
                                }
                            }
                        } else {
                            break;
                        }
                    }
                } else {
                    break;
                }
            }
        } else if (objectType == OBJ_TREE) {
            // Drawtree
            struct pt { int x; int y; };
            struct line { pt start; pt end; };
            const line treeLines[] = {
                {{3,0},{5,0}}, {{5,0},{5,3}}, {{3,0},{3,3}},
                {{0,3},{8,3}}, {{0,3},{2,6}}, {{8,3},{6,6}},
                {{1,6},{2,6}}, {{6,6},{7,6}}, {{1,6},{3,9}},
                {{7,6},{5,9}}, {{2,9},{3,9}}, {{5,9},{6,9}},
                {{6,9},{4,11}}, {{2,9},{4,11}}
            };
            int lineCount = sizeof(treeLines) / sizeof(line);

            xlColor color(hsv);
            double drawRadius = radius;
            for (float i = 0; i < thickness; i += 0.5f) {
                if (is3D) {
                    if (buf.allowAlpha) {
                        color.alpha = static_cast<uint8_t>(255.0 * (1.0 - (i / static_cast<float>(thickness))));
                    } else {
                        hsv.value *= 1.0 - (i / static_cast<float>(thickness));
                        color = hsv;
                    }
                }
                if (movement == MOVEMENT_EXPLODE) {
                    drawRadius = radius + i;
                } else {
                    drawRadius = radius - i;
                }
                if (drawRadius >= 0) {
                    for (int j = 0; j < lineCount; ++j) {
                        int x1 = static_cast<int>(std::round((static_cast<double>(treeLines[j].start.x) - 4.0) / 11.0 * drawRadius));
                        int y1 = static_cast<int>(std::round((static_cast<double>(treeLines[j].start.y) - 4.0) / 11.0 * drawRadius));
                        int x2 = static_cast<int>(std::round((static_cast<double>(treeLines[j].end.x) - 4.0) / 11.0 * drawRadius));
                        int y2 = static_cast<int>(std::round((static_cast<double>(treeLines[j].end.y) - 4.0) / 11.0 * drawRadius));
                        buf.DrawLine(xc + x1, yc + y1, xc + x2, yc + y2, color);
                    }
                } else {
                    break;
                }
            }
        } else if (objectType == OBJ_CANDYCANE) {
            // Drawcandycane
            double originalRadius = radius;
            xlColor color(hsv);
            double drawRadius = radius;
            for (float i = 0; i < thickness; i += 0.5f) {
                if (is3D) {
                    if (buf.allowAlpha) {
                        color.alpha = static_cast<uint8_t>(255.0 * (1.0 - (i / static_cast<float>(thickness))));
                    } else {
                        hsv.value *= 1.0 - (i / static_cast<float>(thickness));
                        color = hsv;
                    }
                }
                if (movement == MOVEMENT_EXPLODE) {
                    drawRadius = radius + i;
                } else {
                    drawRadius = radius - i;
                }
                if (drawRadius >= 0) {
                    int cy1 = static_cast<int>(std::round(static_cast<double>(yc) + originalRadius / 6.0));
                    int cy2 = static_cast<int>(std::round(static_cast<double>(yc) - originalRadius / 2.0));
                    int cx = static_cast<int>(std::round(static_cast<double>(xc) + drawRadius / 2.0));
                    buf.DrawLine(cx, cy1, cx, cy2, color);

                    double r = drawRadius / 3.0;
                    for (double degrees = 0.0; degrees < 180.0; degrees += 1.0) {
                        double radian = degrees * (M_PI / 180.0);
                        int hx = static_cast<int>(std::round(r * std::cos(radian) + xc + originalRadius / 6.0));
                        int hy = static_cast<int>(std::round(r * std::sin(radian) + cy1));
                        buf.SetPixel(hx, hy, color);
                    }
                } else {
                    break;
                }
            }
        } else if (objectType == OBJ_SNOWFLAKE) {
            // Drawsnowflake
            double increment = 360.0 / (points * 2);
            double angle = static_cast<double>(rotation);

            xlColor color(hsv);
            if (radius >= 0) {
                for (int i = 0; i < points * 2; i++) {
                    double radian = angle * M_PI / 180.0;
                    int x1 = static_cast<int>(std::round(radius * std::cos(radian))) + xc;
                    int y1 = static_cast<int>(std::round(radius * std::sin(radian))) + yc;

                    radian = (180.0 + angle) * M_PI / 180.0;
                    int x2 = static_cast<int>(std::round(radius * std::cos(radian))) + xc;
                    int y2 = static_cast<int>(std::round(radius * std::sin(radian))) + yc;

                    buf.DrawLine(x1, y1, x2, y2, color);
                    angle += increment;
                }
            }
        } else if (objectType == OBJ_CRUCIFIX) {
            // Drawcrucifix
            struct pt { int x; int y; };
            struct line { pt start; pt end; };
            const line crossLines[] = {
                {{2,0},{2,6}}, {{2,6},{0,6}}, {{0,6},{0,7}},
                {{0,7},{2,7}}, {{2,7},{2,10}}, {{2,10},{3,10}},
                {{3,10},{3,7}}, {{3,7},{5,7}}, {{5,7},{5,6}},
                {{5,6},{3,6}}, {{3,6},{3,0}}, {{3,0},{2,0}}
            };
            int lineCount = sizeof(crossLines) / sizeof(line);

            xlColor color(hsv);
            double drawRadius = radius;
            for (float i = 0; i < thickness; i += 0.5f) {
                if (is3D) {
                    if (buf.allowAlpha) {
                        color.alpha = static_cast<uint8_t>(255.0 * (1.0 - (i / static_cast<float>(thickness))));
                    } else {
                        hsv.value *= 1.0 - (i / static_cast<float>(thickness));
                        color = hsv;
                    }
                }
                if (movement == MOVEMENT_EXPLODE) {
                    drawRadius = radius + i;
                } else {
                    drawRadius = radius - i;
                }
                if (drawRadius >= 0) {
                    for (int j = 0; j < lineCount; ++j) {
                        int x1 = static_cast<int>(std::round((static_cast<double>(crossLines[j].start.x) - 2.5) / 7.0 * drawRadius));
                        int y1 = static_cast<int>(std::round((static_cast<double>(crossLines[j].start.y) - 6.5) / 10.0 * drawRadius));
                        int x2 = static_cast<int>(std::round((static_cast<double>(crossLines[j].end.x) - 2.5) / 7.0 * drawRadius));
                        int y2 = static_cast<int>(std::round((static_cast<double>(crossLines[j].end.y) - 6.5) / 10.0 * drawRadius));
                        buf.DrawLine(xc + x1, yc + y1, xc + x2, yc + y2, color);
                    }
                } else {
                    break;
                }
            }
        } else if (objectType == OBJ_PRESENT) {
            // Drawpresent
            struct pt { int x; int y; };
            struct line { pt start; pt end; };
            const line presentLines[] = {
                {{0,0},{0,9}}, {{0,9},{10,9}}, {{10,9},{10,0}},
                {{10,0},{0,0}}, {{5,0},{5,9}}, {{5,9},{2,11}},
                {{2,11},{2,9}}, {{5,9},{8,11}}, {{8,11},{8,9}}
            };
            int lineCount = sizeof(presentLines) / sizeof(line);

            xlColor color(hsv);
            double drawRadius = radius;
            for (float i = 0; i < thickness; i += 0.5f) {
                if (is3D) {
                    if (buf.allowAlpha) {
                        color.alpha = static_cast<uint8_t>(255.0 * (1.0 - (i / static_cast<float>(thickness))));
                    } else {
                        hsv.value *= 1.0 - (i / static_cast<float>(thickness));
                        color = hsv;
                    }
                }
                if (movement == MOVEMENT_EXPLODE) {
                    drawRadius = radius + i;
                } else {
                    drawRadius = radius - i;
                }
                if (drawRadius >= 0) {
                    for (int j = 0; j < lineCount; ++j) {
                        int x1 = static_cast<int>(std::round((static_cast<double>(presentLines[j].start.x) - 5.0) / 7.0 * drawRadius));
                        int y1 = static_cast<int>(std::round((static_cast<double>(presentLines[j].start.y) - 5.5) / 10.0 * drawRadius));
                        int x2 = static_cast<int>(std::round((static_cast<double>(presentLines[j].end.x) - 5.0) / 7.0 * drawRadius));
                        int y2 = static_cast<int>(std::round((static_cast<double>(presentLines[j].end.y) - 5.5) / 10.0 * drawRadius));
                        buf.DrawLine(xc + x1, yc + y1, xc + x2, yc + y2, color);
                    }
                } else {
                    break;
                }
            }
        }

        return true;
    }


    if (type == "Servo") {
        // Native Servo effect stub — sets a single DMX channel value.
        // The Servo effect linearly interpolates a position (0-100%) between
        // a start value and end value over the effect duration, then maps
        // that position into the channel's min/max range (default 0-255).
        //
        // In the legacy build, the effect reads model-specific servo limits
        // from DmxServo/DmxSkull/DmxMovingHeadAdv model types. In this native
        // stub we use a simple 0-255 range (8-bit) or 0-65535 (16-bit) since
        // we don't have access to the DMX model hierarchy.

        float startPos = 0.0f;
        float endPos = 0.0f;
        bool is16bit = false;
        int channelIndex = 0; // 0-based pixel index for SetPixel

        // Read start position (E_TEXTCTRL_Servo)
        auto it = effectInfo.settings.find("E_TEXTCTRL_Servo");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            startPos = static_cast<float>(std::atof(it->second.c_str()));
        }

        // Read end position (E_TEXTCTRL_EndValue)
        it = effectInfo.settings.find("E_TEXTCTRL_EndValue");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            endPos = static_cast<float>(std::atof(it->second.c_str()));
        }

        // TODO: Re-enable when ValueCurve is available in native build
#if 0
        bool hasValueCurve = false;
        it = effectInfo.settings.find("E_VALUECURVE_Servo");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            hasValueCurve = true;
            ValueCurve vc(it->second);
            if (vc.IsActive()) {
                vc.SetLimits(0, 100);  // SERVO_MIN, SERVO_MAX
                vc.SetDivisor(1.0);    // SERVO_DIVISOR
                float pos = buf.GetEffectTimeIntervalPosition();
                startPos = vc.GetOutputValueAtDivided(pos,
                    buf.GetStartTimeMS(), buf.GetEndTimeMS());
            }
        }
#endif

        // 16-bit mode
        it = effectInfo.settings.find("E_CHECKBOX_16bit");
        if (it != effectInfo.settings.end() && it->second == "1") {
            is16bit = true;
        }

        // Channel selection — in legacy this is a node name lookup.
        // Here we parse the CHOICE_Channel setting as a 0-based index fallback.
        // If the setting looks like a number, use it; otherwise default to 0.
        it = effectInfo.settings.find("E_CHOICE_Channel");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            // Try to find a numeric channel index from the name
            // In the native build we don't have model node names, so
            // we attempt numeric parse; if it fails, channel stays 0.
            char* endptr = nullptr;
            long ch = std::strtol(it->second.c_str(), &endptr, 10);
            if (endptr != it->second.c_str() && ch >= 0) {
                channelIndex = static_cast<int>(ch);
            }
        }

        // Interpolate position over effect duration
        float effPos = buf.GetEffectTimeIntervalPosition();
        float position = startPos + (endPos - startPos) * effPos;

        // Map position (0-100) to channel value
        int minLimit = 0;
        int maxLimit = is16bit ? 65535 : 255;
        uint16_t value = static_cast<uint16_t>(
            minLimit + (maxLimit - minLimit) * (position / 100.0f));

        // Write the channel value as a greyscale pixel
        xlColor lsb_c = xlBLACK;
        xlColor msb_c = xlBLACK;
        uint8_t lsb = value & 0xFF;
        uint8_t msb = (value >> 8) & 0xFF;
        lsb_c.red = lsb;
        lsb_c.green = lsb;
        lsb_c.blue = lsb;

        if (is16bit) {
            msb_c.red = msb;
            msb_c.green = msb;
            msb_c.blue = msb;
            buf.SetPixel(channelIndex, 0, msb_c);
            if (channelIndex + 1 < buf.BufferWi) {
                buf.SetPixel(channelIndex + 1, 0, lsb_c);
            }
        } else {
            buf.SetPixel(channelIndex, 0, lsb_c);
        }
        return true;
    }


    if (type == "Shimmer") {
        // Native Shimmer effect — port of legacy ShimmerEffect::Render
        // Settings: E_SLIDER_Shimmer_Duty_Factor (1-100, default 50)
        //           E_SLIDER_Shimmer_Cycles (0-6000, default 10; divide by 10 for actual cycles)
        //           E_CHECKBOX_Shimmer_Use_All_Colors (0/1, default 0)
        //           E_CHECKBOX_PRE_2017_7 (0/1, default 0 — legacy compat flag)

        int dutyFactor = 50;
        double cycles = 1.0;
        bool useAllColors = false;
        bool pre2017_7 = false;

        auto it = effectInfo.settings.find("E_SLIDER_Shimmer_Duty_Factor");
        if (it != effectInfo.settings.end() && !it->second.empty())
            dutyFactor = std::atoi(it->second.c_str());
        if (dutyFactor < 1) dutyFactor = 1;
        if (dutyFactor > 100) dutyFactor = 100;

        it = effectInfo.settings.find("E_SLIDER_Shimmer_Cycles");
        if (it != effectInfo.settings.end() && !it->second.empty())
            cycles = std::atof(it->second.c_str()) / 10.0;

        it = effectInfo.settings.find("E_CHECKBOX_Shimmer_Use_All_Colors");
        if (it != effectInfo.settings.end())
            useAllColors = (it->second == "1");

        it = effectInfo.settings.find("E_CHECKBOX_PRE_2017_7");
        if (it != effectInfo.settings.end())
            pre2017_7 = (it->second == "1");

        int colorcnt = static_cast<int>(buf.GetColorCount());
        if (colorcnt < 1) colorcnt = 1;

        int ColorIdx = 0;

        if (pre2017_7) {
            double position = buf.GetEffectTimeIntervalPosition(static_cast<float>(cycles));

            ColorIdx = static_cast<int>(std::round(position * 0.999 * (double)colorcnt));

            double pos2 = position * colorcnt;
            while (pos2 > 1.0) {
                pos2 -= 1.0;
            }
            if (pos2 * 100 > dutyFactor) {
                return true; // black frame — duty cycle off
            }
        } else {
            // If cycles are too high, maximise out at on and off
            if (cycles > ((double)buf.curEffEndPer - (double)buf.curEffStartPer) / 2.0) {
                ColorIdx = (buf.curPeriod - buf.curEffStartPer) % (2 * colorcnt);
                if (ColorIdx % 2 == 0) {
                    ColorIdx /= 2;
                } else {
                    return true; // black frame — alternating off
                }
            } else {
                double position = buf.GetEffectTimeIntervalPosition(static_cast<float>(cycles));
                if (position > 1.0)
                    position = 0.0;

                // black if we are beyond the duty factor
                if (position >= (double)dutyFactor / 100.0)
                    return true; // black frame

                // work out the color based on cycle number
                int totalPeriods = buf.curEffEndPer - buf.curEffStartPer;
                if (totalPeriods < 1) totalPeriods = 1;
                int cycle = static_cast<int>(((buf.curPeriod - buf.curEffStartPer) * cycles) / totalPeriods);
                ColorIdx = cycle % colorcnt;
            }
        }

        // Clamp ColorIdx
        if (ColorIdx >= colorcnt) ColorIdx = colorcnt - 1;
        if (ColorIdx < 0) ColorIdx = 0;

        xlColor color;
        buf.palette.GetColor(static_cast<size_t>(ColorIdx), color);

        for (int y = 0; y < buf.BufferHt; y++) {
            for (int x = 0; x < buf.BufferWi; x++) {
                if (useAllColors) {
                    ColorIdx = std::rand() % colorcnt;
                    buf.palette.GetColor(static_cast<size_t>(ColorIdx), color);
                } else {
                    buf.palette.GetSpatialColor(static_cast<size_t>(ColorIdx),
                        (float)x / (float)buf.BufferWi,
                        (float)y / (float)buf.BufferHt, color);
                }
                buf.SetPixel(x, y, color);
            }
        }
        return true;
    }


    if (type == "Shockwave") {
        // Native Shockwave effect — port of legacy ShockwaveEffect::Render
        // Draws an expanding/contracting ring of color with optional edge blending.

        int cycles = 1;
        int center_x = 50;
        int center_y = 50;
        int start_radius = 1;
        int end_radius = 10;
        int start_width = 5;
        int end_width = 10;
        int acceleration = 0;
        bool blend_edges = true;
        bool scale = true;

        auto it = effectInfo.settings.find("E_SLIDER_Shockwave_Cycles");
        if (it != effectInfo.settings.end() && !it->second.empty())
            cycles = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Shockwave_CenterX");
        if (it != effectInfo.settings.end() && !it->second.empty())
            center_x = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Shockwave_CenterY");
        if (it != effectInfo.settings.end() && !it->second.empty())
            center_y = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Shockwave_Start_Radius");
        if (it != effectInfo.settings.end() && !it->second.empty())
            start_radius = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Shockwave_End_Radius");
        if (it != effectInfo.settings.end() && !it->second.empty())
            end_radius = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Shockwave_Start_Width");
        if (it != effectInfo.settings.end() && !it->second.empty())
            start_width = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Shockwave_End_Width");
        if (it != effectInfo.settings.end() && !it->second.empty())
            end_width = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Shockwave_Accel");
        if (it != effectInfo.settings.end() && !it->second.empty())
            acceleration = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_CHECKBOX_Shockwave_Blend_Edges");
        if (it != effectInfo.settings.end())
            blend_edges = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Shockwave_Scale");
        if (it != effectInfo.settings.end())
            scale = (it->second == "1");

        if (cycles < 1) cycles = 1;

        int num_colors = static_cast<int>(buf.palette.Size());
        if (num_colors == 0) num_colors = 1;

        float eff_pos = buf.GetEffectTimeIntervalPosition(static_cast<float>(cycles));
        double eff_pos_adj = buf.calcAccel(eff_pos, acceleration);

        // Compute blended color from palette based on adjusted position
        HSVValue hsv;
        xlColor color;
        double blend_pct = 1.0;
        if (num_colors > 1) {
            blend_pct = 1.0 / (num_colors - 1);
        }
        double color_pct1 = eff_pos_adj / blend_pct;
        int color_index = static_cast<int>(color_pct1);
        double color_blend = color_pct1 - static_cast<double>(color_index);
        buf.Get2ColorBlend(std::min(color_index, num_colors - 1),
                           std::min(color_index + 1, num_colors - 1),
                           static_cast<float>(std::min(color_blend, 1.0)), color);

        // Convert center from percentage to pixel coordinates
        int xc_adj = center_x * buf.BufferWi / 100;
        int yc_adj = center_y * buf.BufferHt / 100;

        // Compute radii, optionally scaled to buffer size
        double radius1 = static_cast<double>(start_radius);
        double radius2 = static_cast<double>(end_radius);
        if (scale) {
            double bufferMax = std::max(buf.BufferHt, buf.BufferWi);
            radius1 = radius1 * (bufferMax / 200.0);
            radius2 = radius2 * (bufferMax / 200.0);
            start_width = static_cast<int>(start_width * (bufferMax / 100.0));
            end_width = static_cast<int>(end_width * (bufferMax / 100.0));
        }

        double radius_center = radius1 + (radius2 - radius1) * eff_pos_adj;
        double half_width = (start_width + (end_width - start_width) * eff_pos_adj) / 2.0;
        if (half_width < 0.25) {
            half_width = 0.25;
        }
        radius1 = radius_center - half_width;
        radius2 = radius_center + half_width;
        if (radius1 < 0.0) radius1 = 0.0;

        // Render the shockwave ring
        for (int x = 0; x < buf.BufferWi; x++) {
            int x1 = x - xc_adj;
            for (int y = 0; y < buf.BufferHt; y++) {
                int y1 = y - yc_adj;
                double r = std::hypot(x1, y1);
                if (r >= radius1 && r <= radius2) {
                    hsv = color.asHSV();
                    if (blend_edges) {
                        double color_pct = 1.0 - std::abs(r - radius_center) / half_width;
                        xlColor ncolor(color);
                        if (buf.allowAlpha) {
                            ncolor.alpha = static_cast<uint8_t>(255.0 * color_pct);
                        } else {
                            hsv.value = hsv.value * color_pct;
                            ncolor = hsv;
                        }
                        buf.SetPixel(x, y, ncolor);
                    } else {
                        buf.SetPixel(x, y, color);
                    }
                }
            }
        }
        return true;
    }


    if (type == "SingleStrand") {
        // =====================================================================
        // Native SingleStrand effect — Chase + Skips sub-effects
        // Faithful port of legacy SingleStrandEffect::RenderSingleStrandChase,
        // RenderSingleStrandSkips, and draw_chase.
        // FX sub-effect omitted (requires WS2812FX library, not available in native build).
        // =====================================================================

        // Determine sub-effect type. Legacy uses E_NOTEBOOK_SSEFFECT_TYPE,
        // native panel uses E_CHOICE_SingleStrand_Type.
        std::string subType = "Chase";
        auto stIt = effectInfo.settings.find("E_CHOICE_SingleStrand_Type");
        if (stIt != effectInfo.settings.end() && !stIt->second.empty()) {
            subType = stIt->second;
        } else {
            stIt = effectInfo.settings.find("E_NOTEBOOK_SSEFFECT_TYPE");
            if (stIt != effectInfo.settings.end() && !stIt->second.empty()) {
                subType = stIt->second;
            }
        }

        // Helper lambda: read int setting with default
        auto getIntSetting = [&](const char* key, int def) -> int {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty())
                return std::atoi(it->second.c_str());
            return def;
        };
        // Helper lambda: read string setting with default
        auto getStrSetting = [&](const char* key, const char* def) -> std::string {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty())
                return it->second;
            return def;
        };
        // Helper lambda: read bool setting with default
        auto getBoolSetting = [&](const char* key, bool def) -> bool {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty())
                return (it->second == "1" || it->second == "true");
            return def;
        };

        if (subType == "Skips") {
            // =================================================================
            // Skips sub-effect
            // =================================================================
            int bandSize  = getIntSetting("E_SLIDER_Skips_BandSize", 1);
            int skipSize  = getIntSetting("E_SLIDER_Skips_SkipSize", 1);
            int startPos  = getIntSetting("E_SLIDER_Skips_StartPos", 1);
            int advances  = getIntSetting("E_SLIDER_Skips_Advance", 0);
            std::string dirStr = getStrSetting("E_CHOICE_Skips_Direction", "Left");

            // Map direction string to integer
            int direction = 0; // Right
            if (dirStr == "Left")        direction = 1;
            else if (dirStr == "From Middle") direction = 2;
            else if (dirStr == "To Middle")   direction = 3;

            int x = startPos - 1;
            int max = buf.BufferWi;
            if (direction > 1) {
                max = (max + 1) / 2;
            }

            size_t colorcnt = buf.GetColorCount();

            double position = buf.GetEffectTimeIntervalPosition() * (advances + 1.0) * 0.99;
            x += int(position) * bandSize;
            while (x > max) {
                x -= (bandSize + skipSize) * static_cast<int>(colorcnt);
            }

            // mapX lambda: maps x coordinate based on direction, sets second mirror pixel
            auto mapXFn = [](int xv, int maxv, int dir, int& second) -> int {
                second = -1;
                switch (dir) {
                    case 0: return xv;
                    case 1: return maxv - xv - 1;
                    case 2: second = maxv + xv; return maxv - xv - 1;
                    case 3: second = maxv * 2 - xv - 1; return xv;
                    default: break;
                }
                return -1;
            };

            int firstX = x;
            int colorIdx = 0;
            int second = 0;
            xlColor color;

            // Draw forward from start position
            while (x < max) {
                buf.palette.GetColor(colorIdx, color);
                colorIdx++;
                if (colorIdx >= static_cast<int>(colorcnt)) colorIdx = 0;

                for (int cnt = 0; cnt < bandSize && x < max; cnt++) {
                    int mappedX = mapXFn(x, max, direction, second);
                    if (mappedX >= 0 && mappedX < buf.BufferWi) {
                        for (int y = 0; y < buf.BufferHt; y++) {
                            buf.SetPixel(mappedX, y, color);
                        }
                    }
                    if (second >= 0 && second < buf.BufferWi) {
                        for (int y = 0; y < buf.BufferHt; y++) {
                            buf.SetPixel(second, y, color);
                        }
                    }
                    x++;
                }
                x += skipSize;
            }

            // Draw backward from start position
            colorIdx = static_cast<int>(buf.GetColorCount()) - 1;
            x = firstX - 1;
            while (x >= 0) {
                x -= skipSize;

                buf.palette.GetColor(colorIdx, color);
                colorIdx--;
                if (colorIdx < 0) colorIdx = static_cast<int>(buf.GetColorCount()) - 1;

                for (int cnt = 0; cnt < bandSize && x >= 0; cnt++) {
                    int mappedX = mapXFn(x, max, direction, second);
                    if (mappedX >= 0 && mappedX < buf.BufferWi) {
                        for (int y = 0; y < buf.BufferHt; y++) {
                            buf.SetPixel(mappedX, y, color);
                        }
                    }
                    if (second >= 0 && second < buf.BufferWi) {
                        for (int y = 0; y < buf.BufferHt; y++) {
                            buf.SetPixel(second, y, color);
                        }
                    }
                    x--;
                }
            }
        } else {
            // =================================================================
            // Chase sub-effect (default)
            // =================================================================
            std::string colorSchemeName = getStrSetting("E_CHOICE_SingleStrand_Colors", "Palette");
            int Number_Chases = getIntSetting("E_SLIDER_Number_Chases", 1);
            int chaseSize     = getIntSetting("E_SLIDER_Color_Mix1", 10);
            std::string Chase_Type1 = getStrSetting("E_CHOICE_Chase_Type1", "Left-Right");
            std::string Fade_Type   = getStrSetting("E_CHOICE_Fade_Type", "None");
            bool Chase_Group_All    = getBoolSetting("E_CHECKBOX_Chase_Group_All", false);

            // Chase_Rotations: slider value / divisor (10). Default slider=10 => 1.0
            float chaseSpeed = 1.0f;
            {
                auto it = effectInfo.settings.find("E_SLIDER_Chase_Rotations");
                if (it != effectInfo.settings.end() && !it->second.empty())
                    chaseSpeed = std::atof(it->second.c_str()) / 10.0f;
            }
            // Chase_Offset: slider value / divisor (10). Default slider=0 => 0.0
            float offset = 0.0f;
            {
                auto it = effectInfo.settings.find("E_SLIDER_Chase_Offset");
                if (it != effectInfo.settings.end() && !it->second.empty())
                    offset = std::atof(it->second.c_str()) / 10.0f;
            }

            int ColorScheme = (colorSchemeName == "Palette") ? 1 : 0;

            // Map chase type string to integer
            auto mapChaseTypeFn = [](const std::string& ct) -> int {
                if (ct == "Left-Right")          return 0;
                if (ct == "Right-Left")          return 1;
                if (ct == "Bounce from Left")    return 2;
                if (ct == "Bounce from Right")   return 3;
                if (ct == "Dual Chase")          return 4;
                if (ct == "From Middle")         return 5;
                if (ct == "To Middle")           return 6;
                if (ct == "Bounce to Middle")    return 7;
                if (ct == "Bounce from Middle")  return 8;
                if (ct == "Static Left-Right")   return 9;
                if (ct == "Static Right-Left")   return 10;
                if (ct == "Static Dual")         return 11;
                if (ct == "Static From Middle")  return 12;
                if (ct == "Static To Middle")    return 13;
                if (ct == "Static Double-Ended") return 14;
                return 0;
            };

            int chaseType = mapChaseTypeFn(Chase_Type1);

            int MaxNodes;
            if (Chase_Group_All) {
                MaxNodes = buf.BufferWi * buf.BufferHt;
            } else {
                MaxNodes = buf.BufferWi;
            }

            int ChaseDirection = (chaseType == 0 || chaseType == 2 || chaseType == 6 ||
                                  chaseType == 9 || chaseType == 13 || chaseType == 14) ? 1 : 0;

            bool Mirror = false;
            bool AutoReverse = false;
            bool Dual_Chases = false;
            bool Static = (chaseType >= 9 && chaseType <= 14);
            bool DoubleEnd = (chaseType == 14);

            switch (chaseType) {
                case 6: case 13: Mirror = true; break;
                case 5: case 12: Mirror = true; break;
                case 0: case 9: break;
                case 1: case 10: break;
                case 2: AutoReverse = true; break;
                case 3: AutoReverse = true; break;
                case 4: case 11: Dual_Chases = true; break;
                case 7: case 8:
                    Dual_Chases = true;
                    AutoReverse = true;
                    break;
                case 14:
                    Dual_Chases = true;
                    break;
                default: break;
            }
            // Fall-through cases from legacy switch — types 0,9 follow 6,13 Mirror path
            // Re-check: legacy uses fall-through. Let me replicate exact logic.
            // Legacy:
            //   case 6: case 13: Mirror=true; (falls through to case 0/9)
            //   case 5: case 12: Mirror=true; (falls through to case 1/10)
            // So Mirror is set for 5,6,12,13 and the break at 0,1,9,10 stops.
            // The switch above already handles this correctly since we break after each case.
            // Just ensure Mirror is set for the right types:
            Mirror = (chaseType == 5 || chaseType == 6 || chaseType == 12 || chaseType == 13);
            AutoReverse = (chaseType == 2 || chaseType == 3 || chaseType == 7 || chaseType == 8);
            Dual_Chases = (chaseType == 4 || chaseType == 7 || chaseType == 8 ||
                           chaseType == 11 || chaseType == 14);

            int width;
            if (Chase_Group_All) {
                width = MaxNodes;
            } else {
                width = buf.BufferWi;
            }

            if (Mirror) {
                if ((width % 2) == 0) {
                    width /= 2;
                } else {
                    width = (width + 1) / 2;
                }
            }
            if (width == 0) width = 1;

            int scaledChaseWidth = static_cast<int>(width * chaseSize / 100.0);
            if (scaledChaseWidth < 1) scaledChaseWidth = 1;

            // Time position within the effect
            double rtval = Static ? 0.0 : buf.GetEffectTimeIntervalPosition();
            if (chaseType == 8) {
                // Bounce from Middle starts in the middle
                rtval += 0.25 / chaseSpeed;
                if (rtval > 1.0) rtval -= 1.0;
            }
            rtval *= chaseSpeed;
            rtval += (offset / 100.0);
            while (rtval > 1.0) rtval -= 1.0;
            while (rtval < 0.0) rtval += 1.0;
            if (AutoReverse) rtval *= 2.0;

            if (Number_Chases < 1) Number_Chases = 1;
            if (ColorScheme < 0) ColorScheme = 0;
            float dx = static_cast<float>(width) / static_cast<float>(Number_Chases);
            if (dx < 1.0f) dx = 1.0f;

            int startState;
            if (Number_Chases > 1) {
                startState = static_cast<int>(width * rtval + 1);
            } else if (DoubleEnd) {
                startState = static_cast<int>((width + scaledChaseWidth * 2 - 1) * rtval + 1);
            } else {
                startState = static_cast<int>((width + scaledChaseWidth - 1) * rtval + 1);
                if (rtval >= 0.999999) startState -= 1;
            }

            // draw_chase lambda — port of legacy SingleStrandEffect::draw_chase
            auto draw_chase_fn = [&](int x_arg, int ChaseDir, bool mirror) {
                size_t colorcnt = buf.GetColorCount();
                int max_chase_width = static_cast<int>(width * chaseSize / 100.0);
                if (max_chase_width < 1) max_chase_width = 1;
                int middle_chase_index = 0;

                int pixels_per_chase = width / Number_Chases;
                if (pixels_per_chase < 1) pixels_per_chase = 1;

                HSVValue hsv0;
                buf.palette.GetHSV(0, hsv0);
                if (ColorScheme == 0) {
                    hsv0 = xlRED.asHSV();
                }
                float orig_v = hsv0.value;

                int firstX = x_arg;
                int direction = 1;

                if (AutoReverse) {
                    if (firstX < 0 && firstX > -max_chase_width) {
                        firstX = -firstX - 1;
                        direction = -1;
                    }
                    if (firstX < 0 || firstX >= width) {
                        int dif;
                        if (firstX < 0) {
                            firstX = -firstX - 1;
                            direction = -1;
                            dif = 0;
                        } else {
                            dif = firstX - width + 1;
                            firstX = width;
                            direction = -1;
                        }
                        while (dif) {
                            dif--;
                            firstX += direction;
                            if (firstX == (width - 1)) direction = -1;
                            if (firstX == 0) direction = 1;
                        }
                    }
                }

                if (Fade_Type != "None") {
                    if (max_chase_width % 2 == 0) {
                        middle_chase_index = (max_chase_width / 2) - 1;
                    } else {
                        middle_chase_index = max_chase_width / 2;
                    }
                }

                for (int i = 0; i < max_chase_width; i++) {
                    xlColor color;
                    if (ColorScheme == 0) {
                        HSVValue hsvRainbow = hsv0;
                        if (max_chase_width > 0)
                            hsvRainbow.hue = 1.0 - (i * 1.0 / max_chase_width);
                        color = xlColor(hsvRainbow);
                    }

                    int new_x;
                    if (AutoReverse) {
                        new_x = firstX + direction;
                        while (new_x < 0) { direction = 1; new_x = 0; }
                        while (new_x >= width) { direction = -1; new_x = width - 1; }
                        firstX = new_x;
                    } else if (Number_Chases > 1) {
                        new_x = x_arg + i;
                        while (new_x < 0) new_x += width;
                        while (new_x >= width) new_x -= width;
                    } else {
                        new_x = x_arg + i;
                    }

                    if (i < pixels_per_chase) {
                        if (ChaseDir == 0) {
                            new_x = width - new_x - 1;
                        }

                        if (ColorScheme != 0) {
                            int cidx;
                            if (colorcnt == 1) {
                                cidx = 0;
                            } else {
                                cidx = static_cast<int>(std::ceil(
                                    static_cast<double>((max_chase_width - i) * colorcnt) /
                                    static_cast<double>(max_chase_width))) - 1;
                            }
                            if (cidx >= static_cast<int>(colorcnt)) cidx = static_cast<int>(colorcnt) - 1;
                            buf.palette.GetColor(cidx, color);
                        }

                        // Apply fade
                        if (Fade_Type == "From Head") {
                            if (buf.allowAlpha) {
                                color.alpha = static_cast<uint8_t>(255.0 * (i + 1.0) / max_chase_width);
                            } else {
                                HSVValue hsv1 = color.asHSV();
                                hsv1.value = orig_v - ((max_chase_width - (i + 1.0)) / max_chase_width);
                                if (hsv1.value < 0.0) hsv1.value = 0.0;
                                color = xlColor(hsv1);
                            }
                        } else if (Fade_Type == "From Tail") {
                            if (buf.allowAlpha) {
                                color.alpha = static_cast<uint8_t>(255.0 * (max_chase_width - i + 1.0) / max_chase_width);
                            } else {
                                HSVValue hsv1 = color.asHSV();
                                hsv1.value = (max_chase_width - (i + 1.0)) / max_chase_width;
                                if (hsv1.value < 0.0) hsv1.value = 0.0;
                                color = xlColor(hsv1);
                            }
                        } else if (Fade_Type == "Head and Tail") {
                            if (buf.allowAlpha) {
                                if (i <= middle_chase_index) {
                                    color.alpha = static_cast<uint8_t>(255.0 * ((max_chase_width - (2.0 * i) + 0.0)) / max_chase_width);
                                } else {
                                    double a = (2.0 * i + 1.0 - max_chase_width) / max_chase_width;
                                    color.alpha = static_cast<uint8_t>(a > 1.0 ? 255.0 : 255.0 * a);
                                }
                            } else {
                                HSVValue hsv1 = color.asHSV();
                                if (i <= middle_chase_index) {
                                    hsv1.value = orig_v * (1.0 - (2.0 * i) / max_chase_width);
                                } else {
                                    hsv1.value = orig_v * ((2.0 * (i - middle_chase_index)) / max_chase_width);
                                }
                                if (hsv1.value > orig_v) hsv1.value = orig_v;
                                if (hsv1.value < 0.0) hsv1.value = 0.0;
                                color = xlColor(hsv1);
                            }
                        } else if (Fade_Type == "Middle") {
                            if (buf.allowAlpha) {
                                if (i >= middle_chase_index) {
                                    double a = (max_chase_width - i + 0.0) / (0.5 * max_chase_width);
                                    color.alpha = static_cast<uint8_t>(a > 1.0 ? 255.0 : 255.0 * a);
                                } else {
                                    double a = (i + 1.0 - max_chase_width) / (0.5 * max_chase_width);
                                    color.alpha = static_cast<uint8_t>(a > 1.0 ? 255.0 : 255.0 * a);
                                }
                            } else {
                                HSVValue hsv1 = color.asHSV();
                                if (i > middle_chase_index) {
                                    hsv1.value = (max_chase_width - (i + 1.0)) / (0.5 * max_chase_width);
                                } else {
                                    hsv1.value = orig_v - ((max_chase_width - (2.0 * i + 1.0)) / max_chase_width);
                                }
                                if (hsv1.value < 0.0) hsv1.value = 0.0;
                                color = xlColor(hsv1);
                            }
                        }

                        // Set pixels with fade blending for overlapping chases
                        if (new_x >= 0 && new_x <= width) {
                            if (Chase_Group_All) {
                                int py = new_x / buf.BufferWi;
                                int px = new_x % buf.BufferWi;
                                int mirrorx = buf.BufferWi * buf.BufferHt - new_x - 1;
                                int mirrory = mirrorx / buf.BufferWi;
                                mirrorx = mirrorx % buf.BufferWi;

                                if (Fade_Type != "None") {
                                    xlColor c;
                                    buf.GetPixel(px, py, c);
                                    if (c != xlBLACK) {
                                        if (buf.allowAlpha) {
                                            int a = color.alpha;
                                            color = color.AlphaBlend(c);
                                            color.alpha = c.alpha > a ? c.alpha : a;
                                        } else if (Fade_Type == "Middle" || Fade_Type == "From Tail" || Fade_Type == "Head and Tail") {
                                            color = color.ChannelMax(c);
                                        }
                                    }
                                }
                                buf.SetPixel(px, py, color);
                                if (mirror) {
                                    buf.SetPixel(mirrorx, mirrory, color);
                                }
                            } else {
                                if (Fade_Type != "None") {
                                    xlColor c;
                                    buf.GetPixel(new_x, 0, c);
                                    if (c != xlBLACK) {
                                        if (buf.allowAlpha) {
                                            int a = color.alpha;
                                            color = color.AlphaBlend(c);
                                            color.alpha = c.alpha > a ? c.alpha : a;
                                        } else if (Fade_Type == "Middle" || Fade_Type == "From Tail" || Fade_Type == "Head and Tail") {
                                            color = color.ChannelMax(c);
                                        }
                                    }
                                }
                                for (int y = 0; y < buf.BufferHt; y++) {
                                    buf.SetPixel(new_x, y, color);
                                    if (mirror) {
                                        buf.SetPixel(buf.BufferWi - new_x - 1, y, color);
                                    }
                                }
                            }
                        }
                    }
                }
            };

            // Draw each chase
            for (int chase = 0; chase < Number_Chases; chase++) {
                int x;
                if (AutoReverse) {
                    x = static_cast<int>(chase * dx + width * rtval - scaledChaseWidth / 2.0);
                } else {
                    x = static_cast<int>(chase * dx + startState - scaledChaseWidth);
                }

                draw_chase_fn(
                    DoubleEnd ? width - x - 1 * scaledChaseWidth : x,
                    bool(ChaseDirection) != DoubleEnd ? 1 : 0,
                    Mirror);
                if (Dual_Chases) {
                    draw_chase_fn(
                        DoubleEnd ? x - 1 * scaledChaseWidth : x,
                        bool(ChaseDirection) == DoubleEnd ? 1 : 0,
                        Mirror);
                }
            }
        }
        return true;
    }


    if (type == "Shape") {
        // --- Shape type constants ---
        constexpr int SHAPE_CIRCLE    = 0;
        constexpr int SHAPE_SQUARE    = 1;
        constexpr int SHAPE_TRIANGLE  = 2;
        constexpr int SHAPE_STAR      = 3;
        constexpr int SHAPE_PENTAGON  = 4;
        constexpr int SHAPE_HEXAGON   = 5;
        constexpr int SHAPE_OCTAGON   = 6;
        constexpr int SHAPE_HEART     = 7;
        constexpr int SHAPE_TREE      = 8;
        constexpr int SHAPE_CANDYCANE = 9;
        constexpr int SHAPE_SNOWFLAKE = 10;
        constexpr int SHAPE_CRUCIFIX  = 11;
        constexpr int SHAPE_PRESENT   = 12;
        constexpr int SHAPE_ELLIPSE   = 13;
        constexpr int SHAPE_EMOJI     = 14;
        constexpr int SHAPE_SVG       = 15;
        constexpr int REPEATTRIGGER   = 20;

        // --- Helper: read int setting with default ---
        auto getInt = [&](const char* key, int def) -> int {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty())
                return std::atoi(it->second.c_str());
            return def;
        };
        auto getBool = [&](const char* key, bool def) -> bool {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty())
                return it->second == "1";
            return def;
        };
        auto getString = [&](const char* key, const std::string& def) -> std::string {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end())
                return it->second;
            return def;
        };

        // --- Decode shape string to int ---
        auto decodeShape = [&](const std::string& s) -> int {
            if (s == "Circle")      return SHAPE_CIRCLE;
            if (s == "Square")      return SHAPE_SQUARE;
            if (s == "Triangle")    return SHAPE_TRIANGLE;
            if (s == "Star")        return SHAPE_STAR;
            if (s == "Pentagon")    return SHAPE_PENTAGON;
            if (s == "Hexagon")     return SHAPE_HEXAGON;
            if (s == "Octagon")     return SHAPE_OCTAGON;
            if (s == "Heart")       return SHAPE_HEART;
            if (s == "Tree")        return SHAPE_TREE;
            if (s == "Candy Cane")  return SHAPE_CANDYCANE;
            if (s == "Snowflake")   return SHAPE_SNOWFLAKE;
            if (s == "Crucifix")    return SHAPE_CRUCIFIX;
            if (s == "Present")     return SHAPE_PRESENT;
            if (s == "Ellipse")     return SHAPE_ELLIPSE;
            if (s == "Emoji")       return SHAPE_EMOJI;
            if (s == "SVG")         return SHAPE_SVG;
            return std::rand() % 14; // random built-in (exclude emoji/svg)
        };

        // --- Local random helper ---
        auto rand01 = []() -> double {
            return static_cast<double>(std::rand()) / static_cast<double>(RAND_MAX);
        };
        auto toRadians = [](double degrees) -> double {
            return 2.0 * M_PI * degrees / 360.0;
        };

        // --- Read settings (using E_ prefix keys as stored by the native provider) ---
        std::string objectStr = getString("E_CHOICE_Shape_ObjectToDraw", "Circle");
        int thickness  = getInt("E_SLIDER_Shape_Thickness", 1);
        int points     = getInt("E_SLIDER_Shape_Points", 5);
        bool randomLocation = getBool("E_CHECKBOX_Shape_RandomLocation", true);
        bool fadeAway       = getBool("E_CHECKBOX_Shape_FadeAway", true);
        bool startRandomly  = getBool("E_CHECKBOX_Shape_RandomInitial", true);
        bool holdColour     = getBool("E_CHECKBOX_Shape_HoldColour", true);
        int xc         = getInt("E_SLIDER_Shape_CentreX", 50) * buf.BufferWi / 100;
        int yc         = getInt("E_SLIDER_Shape_CentreY", 50) * buf.BufferHt / 100;
        int lifetime   = getInt("E_SLIDER_Shape_Lifetime", 5);
        int growth     = getInt("E_SLIDER_Shape_Growth", 10);
        int count      = getInt("E_SLIDER_Shape_Count", 5);
        int startSize  = getInt("E_SLIDER_Shape_StartSize", 5);
        int rotation   = getInt("E_SLIDER_Shape_Rotation", 0);
        int direction  = getInt("E_SLIDER_Shapes_Direction", 90);
        int velocity   = getInt("E_SLIDER_Shapes_Velocity", 0);
        bool randomMovement = getBool("E_CHECKBOX_Shapes_RandomMovement", false);
        bool useMusic  = getBool("E_CHECKBOX_Shape_UseMusic", false);
        int sensitivity = getInt("E_SLIDER_Shape_Sensitivity", 50);
        bool useTiming = getBool("E_CHECKBOX_Shape_FireTiming", false);

        int shapeToDraw = decodeShape(objectStr);

        // Emoji and SVG are not supported in the native render path — just return true
        if (shapeToDraw == SHAPE_EMOJI || shapeToDraw == SHAPE_SVG) {
            return true;
        }

        // Timing tracks not supported in native path yet
        if (useTiming) useTiming = false;

        // --- Per-shape instance data stored in the render cache ---
        struct ShapeInstance {
            int cx, cy;     // centre
            int mx, my;     // accumulated movement
            float size;
            int oset;       // age in frames
            int shape;
            float angle;    // radians
            int speed;
            int colourIndex;
            bool holdColour;
            xlColor color;

            void move() {
                int dx = static_cast<int>(speed * std::cos(angle));
                int dy = static_cast<int>(speed * std::sin(angle));
                mx += dx; my += dy;
                cx += dx; cy += dy;
            }
            void setCentre(int newX, int newY) {
                cx = newX + mx;
                cy = newY + my;
            }
            xlColor getColour(const xlEngine::PaletteClass& palette) const {
                if (holdColour) return color;
                return palette.GetColor(colourIndex);
            }
        };

        struct ShapeCache : public EffectRenderCache {
            std::vector<ShapeInstance*> shapes;
            int lastColorIdx = -1;
            int sinceLastTriggered = 0;

            ~ShapeCache() override { deleteAll(); }

            void deleteAll() {
                for (auto* s : shapes) delete s;
                shapes.clear();
            }
            void removeOld(int maxAge) {
                // sort so oldest (highest oset) are first
                // then remove from front
                while (!shapes.empty() && shapes.front()->oset > maxAge) {
                    delete shapes.front();
                    shapes.erase(shapes.begin());
                }
            }
            void sortShapes() {
                std::sort(shapes.begin(), shapes.end(),
                    [](const ShapeInstance* a, const ShapeInstance* b) {
                        return a->oset > b->oset;
                    });
            }
            void addShape(int cx, int cy, float size, xlColor color, int oset,
                           int shape, int dir, int vel, bool randMove, bool hold,
                           int colIdx) {
                auto* s = new ShapeInstance();
                s->cx = cx; s->cy = cy;
                s->mx = 0; s->my = 0;
                s->size = size;
                s->oset = oset;
                s->shape = shape;
                if (randMove) {
                    vel = static_cast<int>(static_cast<double>(std::rand()) / RAND_MAX * 20);
                    dir = static_cast<int>(static_cast<double>(std::rand()) / RAND_MAX * 359);
                }
                s->angle = static_cast<float>(2.0 * M_PI * dir / 360.0);
                s->speed = vel;
                s->colourIndex = colIdx;
                s->holdColour = hold;
                s->color = color;
                shapes.push_back(s);
            }
        };

        // Retrieve or create cache
        ShapeCache* cache = dynamic_cast<ShapeCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new ShapeCache();
            buf.infoCache[0] = cache;
        }

        float lifetimeFrames = static_cast<float>(buf.curEffEndPer - buf.curEffStartPer) * lifetime / 100.0f;
        if (lifetimeFrames < 1.0f) lifetimeFrames = 1.0f;
        float growthPerFrame = static_cast<float>(growth) / lifetimeFrames;

        // --- Initialization on first frame ---
        if (buf.needToInit) {
            buf.needToInit = false;
            cache->deleteAll();
            cache->lastColorIdx = -1;
            cache->sinceLastTriggered = 0;

            if (!useTiming && !useMusic) {
                size_t colorcnt = buf.GetColorCount();
                for (int i = 0; i < count; ++i) {
                    int px, py;
                    if (randomLocation) {
                        px = static_cast<int>(rand01() * buf.BufferWi);
                        py = static_cast<int>(rand01() * buf.BufferHt);
                    } else {
                        px = xc; py = yc;
                    }
                    cache->lastColorIdx++;
                    if (cache->lastColorIdx >= static_cast<int>(colorcnt))
                        cache->lastColorIdx = 0;

                    int os = 0;
                    if (startRandomly)
                        os = static_cast<int>(rand01() * lifetimeFrames);

                    xlColor col;
                    buf.palette.GetColor(cache->lastColorIdx, col);
                    cache->addShape(px, py, startSize + os * growthPerFrame, col, os,
                                    shapeToDraw, direction, velocity, randomMovement,
                                    holdColour, cache->lastColorIdx);
                }
                cache->sortShapes();
            }
        }

        // --- Create new shapes to maintain count (non-timing, non-music) ---
        if (!useTiming && !useMusic) {
            size_t colorcnt = buf.GetColorCount();
            while (static_cast<int>(cache->shapes.size()) < count) {
                int px, py;
                if (randomLocation) {
                    px = static_cast<int>(rand01() * buf.BufferWi);
                    py = static_cast<int>(rand01() * buf.BufferHt);
                } else {
                    px = xc; py = yc;
                }
                cache->lastColorIdx++;
                if (cache->lastColorIdx >= static_cast<int>(colorcnt))
                    cache->lastColorIdx = 0;

                xlColor col;
                buf.palette.GetColor(cache->lastColorIdx, col);
                cache->addShape(px, py, static_cast<float>(startSize), col, 0,
                                shapeToDraw, direction, velocity, randomMovement,
                                holdColour, cache->lastColorIdx);
            }
        } else if (useMusic) {
            // Music-triggered shape spawning
            float f = 0.0f;
            // Audio not available in native path yet, but structure is ready
            float sens = static_cast<float>(sensitivity) / 100.0f;
            if (f > sens) {
                if (cache->sinceLastTriggered == 0 || cache->sinceLastTriggered > REPEATTRIGGER) {
                    int px, py;
                    if (randomLocation) {
                        px = static_cast<int>(rand01() * buf.BufferWi);
                        py = static_cast<int>(rand01() * buf.BufferHt);
                    } else {
                        px = xc; py = yc;
                    }
                    size_t colorcnt = buf.GetColorCount();
                    cache->lastColorIdx++;
                    if (cache->lastColorIdx >= static_cast<int>(colorcnt))
                        cache->lastColorIdx = 0;
                    xlColor col;
                    buf.palette.GetColor(cache->lastColorIdx, col);
                    cache->addShape(px, py, static_cast<float>(startSize), col, 0,
                                    shapeToDraw, direction, velocity, randomMovement,
                                    holdColour, cache->lastColorIdx);
                }
                cache->sinceLastTriggered++;
                if (cache->sinceLastTriggered > REPEATTRIGGER)
                    cache->sinceLastTriggered = 0;
            } else {
                cache->sinceLastTriggered = 0;
            }
        }

        // ====================================================================
        // Drawing helper lambdas — faithful ports of ShapeEffect::Draw*
        // ====================================================================

        // --- Drawcircle ---
        auto drawCircle = [&](int cxp, int cyp, double radius, xlColor color, int thick) {
            double interpolation = 0.75;
            double t = static_cast<double>(thick) - 1.0 + interpolation;
            for (double i = 0; i < t; i += interpolation) {
                if (radius < 0) break;
                for (double deg = 0.0; deg < 360.0; deg += 1.0) {
                    double rad = deg * (M_PI / 180.0);
                    int x = static_cast<int>(std::round(radius * std::cos(rad))) + cxp;
                    int y = static_cast<int>(std::round(radius * std::sin(rad))) + cyp;
                    buf.SetPixel(x, y, color);
                }
                radius -= interpolation;
            }
        };

        // --- Drawellipse ---
        auto drawEllipse = [&](int cxp, int cyp, double radius, int multiplier, xlColor color, int thick, double rot) {
            double interpolation = 0.75;
            double t = static_cast<double>(thick) - 1.0 + interpolation;
            for (double i = 0; i < t; i += interpolation) {
                if (radius < 0) break;
                for (double deg = 0.0; deg < 360.0; deg += 1.0) {
                    double rad = deg * (M_PI / 180.0);
                    double scaleMul = static_cast<double>(multiplier) / 10.0;
                    double x = radius * std::cos(rad);
                    double y = (radius * scaleMul) * std::sin(rad);
                    double radRot = rot * (M_PI / 180.0);
                    double rx = (x * std::cos(radRot)) - (y * std::sin(radRot));
                    double ry = (y * std::cos(radRot)) + (x * std::sin(radRot));
                    int xx = static_cast<int>(std::round(rx)) + cxp;
                    int yy = static_cast<int>(std::round(ry)) + cyp;
                    buf.SetPixel(xx, yy, color);
                }
                radius -= interpolation;
            }
        };

        // --- Drawpolygon ---
        auto drawPolygon = [&](int cxp, int cyp, double radius, int sides, xlColor color, int thick, double rot) {
            double interpolation = 0.05;
            double t = static_cast<double>(thick) - 1.0 + interpolation;
            double increment = 360.0 / sides;
            for (double i = 0; i < t; i += interpolation) {
                if (radius < 0) break;
                for (double deg = 0.0; deg < 361.0; deg += increment) {
                    if (deg > 360.0) deg = 360.0;
                    double rad = (rot + deg) * M_PI / 180.0;
                    int x1 = static_cast<int>(std::round(radius * std::cos(rad))) + cxp;
                    int y1 = static_cast<int>(std::round(radius * std::sin(rad))) + cyp;
                    double rad2 = (rot + deg + increment) * M_PI / 180.0;
                    int x2 = static_cast<int>(std::round(radius * std::cos(rad2))) + cxp;
                    int y2 = static_cast<int>(std::round(radius * std::sin(rad2))) + cyp;
                    buf.DrawLine(x1, y1, x2, y2, color);
                    if (deg == 360.0) deg = 361.0;
                }
                radius -= interpolation;
            }
        };

        // --- Drawstar ---
        auto drawStar = [&](int cxp, int cyp, double radius, int pts, xlColor color, int thick, double rot) {
            double interpolation = 0.6;
            double t = static_cast<double>(thick) - 1.0 + interpolation;
            double offsetangle = 0.0;
            switch (pts) {
                case 5: offsetangle = 90.0 - 360.0 / 5.0; break;
                case 6: offsetangle = 30.0; break;
                case 7: offsetangle = 90.0 - 360.0 / 7.0; break;
                default: break;
            }
            for (double i = 0; i < t; i += interpolation) {
                if (radius < 0) break;
                double innerRadius = radius / 2.618034; // golden ratio squared
                double increment = 360.0 / pts;
                for (double deg = 0.0; deg < 361.0; deg += increment) {
                    if (deg > 360.0) deg = 360.0;
                    double rad = (rot + offsetangle + deg) * (M_PI / 180.0);
                    int xouter = static_cast<int>(std::round(radius * std::cos(rad))) + cxp;
                    int youter = static_cast<int>(std::round(radius * std::sin(rad))) + cyp;

                    double rad2 = (rot + offsetangle + deg + increment / 2.0) * (M_PI / 180.0);
                    int xinner = static_cast<int>(std::round(innerRadius * std::cos(rad2))) + cxp;
                    int yinner = static_cast<int>(std::round(innerRadius * std::sin(rad2))) + cyp;
                    buf.DrawLine(xinner, yinner, xouter, youter, color);

                    double rad3 = (rot + offsetangle + deg - increment / 2.0) * (M_PI / 180.0);
                    xinner = static_cast<int>(std::round(innerRadius * std::cos(rad3))) + cxp;
                    yinner = static_cast<int>(std::round(innerRadius * std::sin(rad3))) + cyp;
                    buf.DrawLine(xinner, yinner, xouter, youter, color);

                    if (deg == 360.0) deg = 361.0;
                }
                radius -= interpolation;
            }
        };

        // --- Drawsnowflake ---
        auto drawSnowflake = [&](int cxp, int cyp, double radius, int sides, xlColor color, double rot) {
            double increment = 360.0 / (sides * 2);
            double angle = rot;
            if (radius >= 0) {
                for (int i = 0; i < sides * 2; i++) {
                    double rad = angle * M_PI / 180.0;
                    int x1 = static_cast<int>(std::round(radius * std::cos(rad))) + cxp;
                    int y1 = static_cast<int>(std::round(radius * std::sin(rad))) + cyp;
                    double rad2 = (180.0 + angle) * M_PI / 180.0;
                    int x2 = static_cast<int>(std::round(radius * std::cos(rad2))) + cxp;
                    int y2 = static_cast<int>(std::round(radius * std::sin(rad2))) + cyp;
                    buf.DrawLine(x1, y1, x2, y2, color);
                    angle += increment;
                }
            }
        };

        // --- Drawheart ---
        auto drawHeart = [&](int cxp, int cyp, double radius, xlColor color, int thick, double rot) {
            double interpolation = 0.75;
            double t = static_cast<double>(thick) - 1.0 + interpolation;
            double radRot = rot * (M_PI / 180.0);
            double xincr = 0.01;
            for (double x = -2.0; x <= 2.0; x += xincr) {
                double y1 = std::sqrt(1.0 - (std::abs(x) - 1.0) * (std::abs(x) - 1.0));
                double y2 = std::acos(1.0 - std::abs(x)) - M_PI;
                double r = radius;
                for (double i = 0.0; i < t; i += interpolation) {
                    if (r < 0.0) break;
                    double xx = (x * r) / 2.0;
                    double yy1 = (y1 * r) / 2.0;
                    double yy2 = (y2 * r) / 2.0;
                    double rx1 = (xx * std::cos(radRot)) - (yy1 * std::sin(radRot)) + cxp;
                    double ry1 = (yy1 * std::cos(radRot)) + (xx * std::sin(radRot)) + cyp;
                    double rx2 = (xx * std::cos(radRot)) - (yy2 * std::sin(radRot)) + cxp;
                    double ry2 = (yy2 * std::cos(radRot)) + (xx * std::sin(radRot)) + cyp;
                    buf.SetPixel(static_cast<int>(std::round(rx1)), static_cast<int>(std::round(ry1)), color);
                    buf.SetPixel(static_cast<int>(std::round(rx2)), static_cast<int>(std::round(ry2)), color);
                    if (x + xincr > 2.0 || x == -2.0 + xincr) {
                        if (yy1 > yy2) std::swap(yy1, yy2);
                        for (double z = yy1; z < yy2; z += 0.5) {
                            double rxz = (xx * std::cos(radRot)) - (z * std::sin(radRot)) + cxp;
                            double ryz = (z * std::cos(radRot)) + (xx * std::sin(radRot)) + cyp;
                            buf.SetPixel(static_cast<int>(std::round(rxz)), static_cast<int>(std::round(ryz)), color);
                        }
                    }
                    r -= interpolation;
                }
            }
        };

        // --- Line segment struct for tree/crucifix/present ---
        struct LineSeg { int sx, sy, ex, ey; };

        // --- Drawtree ---
        auto drawTree = [&](int cxp, int cyp, double radius, xlColor color, int thick, double rot) {
            const LineSeg segs[] = {
                {3,0, 5,0}, {5,0, 5,3}, {3,0, 3,3}, {0,3, 8,3},
                {0,3, 2,6}, {8,3, 6,6}, {1,6, 2,6}, {6,6, 7,6},
                {1,6, 3,9}, {7,6, 5,9}, {2,9, 3,9}, {5,9, 6,9},
                {6,9, 4,11}, {2,9, 4,11}
            };
            int segCount = 14;
            double interpolation = 0.75;
            double t = static_cast<double>(thick) - 1.0 + interpolation;
            for (double i = 0; i < t; i += interpolation) {
                if (radius < 0) break;
                for (int j = 0; j < segCount; ++j) {
                    int x1 = static_cast<int>(std::round((static_cast<double>(segs[j].sx) - 4.0) / 11.0 * radius));
                    int y1 = static_cast<int>(std::round((static_cast<double>(segs[j].sy) - 4.0) / 11.0 * radius));
                    int x2 = static_cast<int>(std::round((static_cast<double>(segs[j].ex) - 4.0) / 11.0 * radius));
                    int y2 = static_cast<int>(std::round((static_cast<double>(segs[j].ey) - 4.0) / 11.0 * radius));
                    double radRot = rot * (M_PI / 180.0);
                    double rx1 = (x1 * std::cos(radRot)) - (y1 * std::sin(radRot));
                    double ry1 = (y1 * std::cos(radRot)) + (x1 * std::sin(radRot));
                    double rx2 = (x2 * std::cos(radRot)) - (y2 * std::sin(radRot));
                    double ry2 = (y2 * std::cos(radRot)) + (x2 * std::sin(radRot));
                    buf.DrawLine(cxp + static_cast<int>(rx1), cyp + static_cast<int>(ry1),
                                 cxp + static_cast<int>(rx2), cyp + static_cast<int>(ry2), color);
                }
                radius -= interpolation;
            }
        };

        // --- Drawcrucifix ---
        auto drawCrucifix = [&](int cxp, int cyp, double radius, xlColor color, int thick, double rot) {
            const LineSeg segs[] = {
                {2,0, 2,6}, {2,6, 0,6}, {0,6, 0,7}, {0,7, 2,7},
                {2,7, 2,10}, {2,10, 3,10}, {3,10, 3,7}, {3,7, 5,7},
                {5,7, 5,6}, {5,6, 3,6}, {3,6, 3,0}, {3,0, 2,0}
            };
            int segCount = 12;
            double interpolation = 0.75;
            double t = static_cast<double>(thick) - 1.0 + interpolation;
            for (double i = 0; i < t; i += interpolation) {
                if (radius < 0) break;
                for (int j = 0; j < segCount; ++j) {
                    int x1 = static_cast<int>(std::round((static_cast<double>(segs[j].sx) - 2.5) / 7.0 * radius));
                    int y1 = static_cast<int>(std::round((static_cast<double>(segs[j].sy) - 6.5) / 10.0 * radius));
                    int x2 = static_cast<int>(std::round((static_cast<double>(segs[j].ex) - 2.5) / 7.0 * radius));
                    int y2 = static_cast<int>(std::round((static_cast<double>(segs[j].ey) - 6.5) / 10.0 * radius));
                    double radRot = rot * (M_PI / 180.0);
                    double rx1 = (x1 * std::cos(radRot)) - (y1 * std::sin(radRot));
                    double ry1 = (y1 * std::cos(radRot)) + (x1 * std::sin(radRot));
                    double rx2 = (x2 * std::cos(radRot)) - (y2 * std::sin(radRot));
                    double ry2 = (y2 * std::cos(radRot)) + (x2 * std::sin(radRot));
                    buf.DrawLine(cxp + static_cast<int>(rx1), cyp + static_cast<int>(ry1),
                                 cxp + static_cast<int>(rx2), cyp + static_cast<int>(ry2), color);
                }
                radius -= interpolation;
            }
        };

        // --- Drawpresent ---
        auto drawPresent = [&](int cxp, int cyp, double radius, xlColor color, int thick, double rot) {
            const LineSeg segs[] = {
                {0,0, 0,9}, {0,9, 10,9}, {10,9, 10,0}, {10,0, 0,0},
                {5,0, 5,9}, {5,9, 2,11}, {2,11, 2,9}, {5,9, 8,11}, {8,11, 8,9}
            };
            int segCount = 9;
            double interpolation = 0.75;
            double t = static_cast<double>(thick) - 1.0 + interpolation;
            for (double i = 0; i < t; i += interpolation) {
                if (radius < 0) break;
                for (int j = 0; j < segCount; ++j) {
                    int x1 = static_cast<int>(std::round((static_cast<double>(segs[j].sx) - 5.0) / 7.0 * radius));
                    int y1 = static_cast<int>(std::round((static_cast<double>(segs[j].sy) - 5.5) / 10.0 * radius));
                    int x2 = static_cast<int>(std::round((static_cast<double>(segs[j].ex) - 5.0) / 7.0 * radius));
                    int y2 = static_cast<int>(std::round((static_cast<double>(segs[j].ey) - 5.5) / 10.0 * radius));
                    double radRot = rot * (M_PI / 180.0);
                    double rx1 = (x1 * std::cos(radRot)) - (y1 * std::sin(radRot));
                    double ry1 = (y1 * std::cos(radRot)) + (x1 * std::sin(radRot));
                    double rx2 = (x2 * std::cos(radRot)) - (y2 * std::sin(radRot));
                    double ry2 = (y2 * std::cos(radRot)) + (x2 * std::sin(radRot));
                    buf.DrawLine(cxp + static_cast<int>(rx1), cyp + static_cast<int>(ry1),
                                 cxp + static_cast<int>(rx2), cyp + static_cast<int>(ry2), color);
                }
                radius -= interpolation;
            }
        };

        // --- Drawcandycane ---
        auto drawCandyCane = [&](int cxp, int cyp, double radius, xlColor color, int thick) {
            double originalRadius = radius;
            double interpolation = 0.75;
            double t = static_cast<double>(thick) - 1.0 + interpolation;
            for (double i = 0; i < t; i += interpolation) {
                if (radius < 0) break;
                // draw the stick
                int y1 = static_cast<int>(std::round(static_cast<double>(cyp) + originalRadius / 6.0));
                int y2 = static_cast<int>(std::round(static_cast<double>(cyp) - originalRadius / 2.0));
                int x = static_cast<int>(std::round(static_cast<double>(cxp) + radius / 2.0));
                buf.DrawLine(x, y1, x, y2, color);
                // draw the hook
                double r = radius / 3.0;
                for (double deg = 0.0; deg < 180.0; deg += 1.0) {
                    double rad = deg * (M_PI / 180.0);
                    int hx = static_cast<int>(std::round((r - interpolation) * std::cos(rad) + cxp + originalRadius / 6.0));
                    int hy = static_cast<int>(std::round((r - interpolation) * std::sin(rad) + y1));
                    buf.SetPixel(hx, hy, color);
                }
                radius -= interpolation;
            }
        };

        // ====================================================================
        // Render each shape instance
        // ====================================================================
        for (auto* it : cache->shapes) {
            if (!randomLocation) {
                it->setCentre(xc, yc);
            }

            xlColor color = it->getColour(buf.palette);
            if (fadeAway) {
                float brightness = (lifetimeFrames - static_cast<float>(it->oset)) / lifetimeFrames;
                if (brightness < 0.0f) brightness = 0.0f;
                if (buf.allowAlpha) {
                    color.alpha = static_cast<uint8_t>(255.0f * brightness);
                } else {
                    color.red   = static_cast<uint8_t>(color.red * brightness);
                    color.green = static_cast<uint8_t>(color.green * brightness);
                    color.blue  = static_cast<uint8_t>(color.blue * brightness);
                }
            }

            switch (it->shape) {
            case SHAPE_CIRCLE:
                drawCircle(it->cx, it->cy, it->size, color, thickness);
                break;
            case SHAPE_SQUARE:
                drawPolygon(it->cx, it->cy, it->size, 4, color, thickness, rotation + 45.0);
                break;
            case SHAPE_TRIANGLE:
                drawPolygon(it->cx, it->cy, it->size, 3, color, thickness, rotation + 90.0);
                break;
            case SHAPE_STAR:
                drawStar(it->cx, it->cy, it->size, points, color, thickness, rotation);
                break;
            case SHAPE_PENTAGON:
                drawPolygon(it->cx, it->cy, it->size, 5, color, thickness, rotation + 90.0);
                break;
            case SHAPE_HEXAGON:
                drawPolygon(it->cx, it->cy, it->size, 6, color, thickness, rotation);
                break;
            case SHAPE_OCTAGON:
                drawPolygon(it->cx, it->cy, it->size, 8, color, thickness, rotation + 22.5);
                break;
            case SHAPE_HEART:
                drawHeart(it->cx, it->cy, it->size, color, thickness, rotation);
                break;
            case SHAPE_TREE:
                drawTree(it->cx, it->cy, it->size, color, thickness, rotation);
                break;
            case SHAPE_CANDYCANE:
                drawCandyCane(it->cx, it->cy, it->size, color, thickness);
                break;
            case SHAPE_SNOWFLAKE:
                drawSnowflake(it->cx, it->cy, it->size, 3, color, rotation + 30.0);
                break;
            case SHAPE_CRUCIFIX:
                drawCrucifix(it->cx, it->cy, it->size, color, thickness, rotation);
                break;
            case SHAPE_PRESENT:
                drawPresent(it->cx, it->cy, it->size, color, thickness, rotation);
                break;
            case SHAPE_ELLIPSE:
                drawEllipse(it->cx, it->cy, it->size, points, color, thickness, rotation);
                break;
            default:
                break;
            }

            // Advance shape state after drawing (matches legacy ordering)
            it->move();
            it->oset++;
            it->size += growthPerFrame;
            if (it->size < 0) it->size = 0;
        }

        // Remove shapes that have exceeded their lifetime
        cache->removeOld(static_cast<int>(lifetimeFrames));

        return true;
    }



    if (type == "Sketch") {
        // Native Sketch effect — port of legacy SketchEffect::Render
        // Renders user-drawn paths (lines, quadratic/cubic bezier) onto the buffer.

        std::string sketchDef;
        auto it = effectInfo.settings.find("E_TEXTCTRL_SketchDef");
        if (it != effectInfo.settings.end()) sketchDef = it->second;
        if (sketchDef.empty()) {
            it = effectInfo.settings.find("E_TEXTCTRL_Sketch_SketchDef");
            if (it != effectInfo.settings.end()) sketchDef = it->second;
        }
        if (sketchDef.empty()) return true;

        int skThickness = 3;
        it = effectInfo.settings.find("E_SLIDER_Sketch_Thickness");
        if (it != effectInfo.settings.end() && !it->second.empty())
            skThickness = std::atoi(it->second.c_str());
        else {
            it = effectInfo.settings.find("E_SLIDER_Thickness");
            if (it != effectInfo.settings.end() && !it->second.empty())
                skThickness = std::atoi(it->second.c_str());
        }
        if (skThickness < 1) skThickness = 1;

        bool skMotionEnabled = false;
        it = effectInfo.settings.find("E_CHECKBOX_Sketch_DrawMode");
        if (it != effectInfo.settings.end()) skMotionEnabled = (it->second == "1");
        else {
            it = effectInfo.settings.find("E_CHECKBOX_MotionEnabled");
            if (it != effectInfo.settings.end()) skMotionEnabled = (it->second == "1");
        }

        int skMotionPctInt = 100;
        it = effectInfo.settings.find("E_SLIDER_Sketch_MotionPercentage");
        if (it != effectInfo.settings.end() && !it->second.empty())
            skMotionPctInt = std::atoi(it->second.c_str());
        else {
            it = effectInfo.settings.find("E_SLIDER_MotionPercentage");
            if (it != effectInfo.settings.end() && !it->second.empty())
                skMotionPctInt = std::atoi(it->second.c_str());
        }
        double skMotionPct = skMotionPctInt * 0.01;

        int skDrawPctInt = 40;
        it = effectInfo.settings.find("E_SLIDER_DrawPercentage");
        if (it != effectInfo.settings.end() && !it->second.empty())
            skDrawPctInt = std::atoi(it->second.c_str());
        double skDrawPct = skDrawPctInt * 0.01;

        float skProgress = buf.GetEffectTimeIntervalPosition(1.0f);
        int skW = buf.BufferWi;
        int skH = buf.BufferHt;

        // Parse sketch definition: paths separated by '|', components by ';'
        // First component = start point x,y. Segments: Lx,y Qcx,cy,x,y Ccx1,cy1,cx2,cy2,x,y c
        struct SkPt { double x, y; };
        enum class SkSegType { Line, Quad, Cubic };
        struct SkSeg { SkSegType tp; SkPt fr, to, c1, c2; };
        struct SkPath { std::vector<SkSeg> segs; bool closed = false; };

        auto skSegLen = [](const SkSeg& s) -> double {
            if (s.tp == SkSegType::Line) {
                double dx = s.to.x - s.fr.x, dy = s.to.y - s.fr.y;
                return std::sqrt(dx*dx + dy*dy);
            }
            const int N = 50;
            double len = 0.0, px = s.fr.x, py = s.fr.y;
            for (int i = 1; i <= N; ++i) {
                double t = (double)i / N, u = 1.0 - t, nx, ny;
                if (s.tp == SkSegType::Quad) {
                    nx = u*u*s.fr.x + 2*u*t*s.c1.x + t*t*s.to.x;
                    ny = u*u*s.fr.y + 2*u*t*s.c1.y + t*t*s.to.y;
                } else {
                    nx = u*u*u*s.fr.x + 3*u*u*t*s.c1.x + 3*u*t*t*s.c2.x + t*t*t*s.to.x;
                    ny = u*u*u*s.fr.y + 3*u*u*t*s.c1.y + 3*u*t*t*s.c2.y + t*t*t*s.to.y;
                }
                double dx = nx-px, dy = ny-py;
                len += std::sqrt(dx*dx + dy*dy);
                px = nx; py = ny;
            }
            return len;
        };

        auto skPathLen = [&skSegLen](const SkPath& p) -> double {
            double l = 0; for (const auto& s : p.segs) l += skSegLen(s); return l;
        };

        std::vector<SkPath> skPaths;
        {
            std::istringstream ps(sketchDef);
            std::string pstr;
            while (std::getline(ps, pstr, '|')) {
                if (pstr.empty()) continue;
                SkPath sp;
                std::vector<std::string> cps;
                {
                    std::istringstream cs(pstr);
                    std::string c;
                    while (std::getline(cs, c, ';'))
                        if (!c.empty()) cps.push_back(c);
                }
                if (cps.empty()) continue;
                SkPt prev = {0, 0};
                {
                    auto cm = cps[0].find(',');
                    if (cm != std::string::npos) {
                        try {
                            prev.x = std::stod(cps[0].substr(0, cm));
                            prev.y = std::stod(cps[0].substr(cm + 1));
                        } catch (...) {}
                    }
                }
                for (size_t ci = 1; ci < cps.size(); ++ci) {
                    const std::string& cp = cps[ci];
                    if (cp.empty()) continue;
                    char cmd = cp[0];
                    std::vector<double> vl;
                    {
                        std::istringstream vs(cp.substr(1));
                        std::string v;
                        while (std::getline(vs, v, ','))
                            if (!v.empty()) {
                                try { vl.push_back(std::stod(v)); }
                                catch (...) { vl.push_back(0); }
                            }
                    }
                    if (cmd == 'L' && vl.size() >= 2) {
                        SkSeg sg;
                        sg.tp = SkSegType::Line;
                        sg.fr = prev;
                        sg.to = {vl[0], vl[1]};
                        sp.segs.push_back(sg);
                        prev = sg.to;
                    } else if (cmd == 'Q' && vl.size() >= 4) {
                        SkSeg sg;
                        sg.tp = SkSegType::Quad;
                        sg.fr = prev;
                        sg.c1 = {vl[0], vl[1]};
                        sg.to = {vl[2], vl[3]};
                        sp.segs.push_back(sg);
                        prev = sg.to;
                    } else if (cmd == 'C' && vl.size() >= 6) {
                        SkSeg sg;
                        sg.tp = SkSegType::Cubic;
                        sg.fr = prev;
                        sg.c1 = {vl[0], vl[1]};
                        sg.c2 = {vl[2], vl[3]};
                        sg.to = {vl[4], vl[5]};
                        sp.segs.push_back(sg);
                        prev = sg.to;
                    } else if (cmd == 'c') {
                        sp.closed = true;
                    }
                }
                if (!sp.segs.empty())
                    skPaths.push_back(std::move(sp));
            }
        }
        if (skPaths.empty()) return true;

        // Draw a (partial) segment onto the buffer
        auto skDraw = [&](const SkSeg& s, double sf, double ef, const xlColor& col) {
            if (sf >= ef) return;
            if (s.tp == SkSegType::Line) {
                double x1 = s.fr.x + sf * (s.to.x - s.fr.x);
                double y1 = s.fr.y + sf * (s.to.y - s.fr.y);
                double x2 = s.fr.x + ef * (s.to.x - s.fr.x);
                double y2 = s.fr.y + ef * (s.to.y - s.fr.y);
                int px1 = (int)(x1 * (skW - 1) + 0.5);
                int py1 = (skH - 1) - (int)(y1 * (skH - 1) + 0.5);
                int px2 = (int)(x2 * (skW - 1) + 0.5);
                int py2 = (skH - 1) - (int)(y2 * (skH - 1) + 0.5);
                if (skThickness <= 1)
                    buf.DrawLine(px1, py1, px2, py2, col);
                else
                    buf.DrawThickLine(px1, py1, px2, py2, col, skThickness);
            } else {
                const int ST = 30;
                int iS = (int)(sf * ST), iE = (int)(ef * ST + 0.5);
                if (iE > ST) iE = ST;
                double pX, pY;
                {
                    double t = (double)iS / ST, u = 1.0 - t;
                    if (s.tp == SkSegType::Quad) {
                        pX = u*u*s.fr.x + 2*u*t*s.c1.x + t*t*s.to.x;
                        pY = u*u*s.fr.y + 2*u*t*s.c1.y + t*t*s.to.y;
                    } else {
                        pX = u*u*u*s.fr.x + 3*u*u*t*s.c1.x + 3*u*t*t*s.c2.x + t*t*t*s.to.x;
                        pY = u*u*u*s.fr.y + 3*u*u*t*s.c1.y + 3*u*t*t*s.c2.y + t*t*t*s.to.y;
                    }
                }
                for (int i = iS + 1; i <= iE; ++i) {
                    double t = (double)i / ST, u = 1.0 - t;
                    double nX, nY;
                    if (s.tp == SkSegType::Quad) {
                        nX = u*u*s.fr.x + 2*u*t*s.c1.x + t*t*s.to.x;
                        nY = u*u*s.fr.y + 2*u*t*s.c1.y + t*t*s.to.y;
                    } else {
                        nX = u*u*u*s.fr.x + 3*u*u*t*s.c1.x + 3*u*t*t*s.c2.x + t*t*t*s.to.x;
                        nY = u*u*u*s.fr.y + 3*u*u*t*s.c1.y + 3*u*t*t*s.c2.y + t*t*t*s.to.y;
                    }
                    int px1 = (int)(pX * (skW - 1) + 0.5);
                    int py1 = (skH - 1) - (int)(pY * (skH - 1) + 0.5);
                    int px2 = (int)(nX * (skW - 1) + 0.5);
                    int py2 = (skH - 1) - (int)(nY * (skH - 1) + 0.5);
                    if (skThickness <= 1)
                        buf.DrawLine(px1, py1, px2, py2, col);
                    else
                        buf.DrawThickLine(px1, py1, px2, py2, col, skThickness);
                    pX = nX;
                    pY = nY;
                }
            }
        };

        // Compute lengths
        double skTotalLen = 0;
        std::vector<double> skPLens;
        skPLens.reserve(skPaths.size());
        for (const auto& p : skPaths) {
            double l = skPathLen(p);
            skPLens.push_back(l);
            skTotalLen += l;
        }
        if (skTotalLen <= 0) return true;

        // Adjusted progress (legacy logic)
        double skAdj;
        if (skMotionEnabled)
            skAdj = skProgress * (1.0 + skMotionPct);
        else
            skAdj = (skDrawPct > 0) ? (skProgress / skDrawPct) : 1.0;

        // Special case: single closed path with motion wraps around
        if (skMotionEnabled && skPaths.size() == 1 && skPaths[0].closed) {
            xlColor col;
            buf.palette.GetColor(0, col);
            const auto& sp = skPaths[0];
            double pL = skPLens[0];
            double sP = skProgress, eP = skProgress + skMotionPct;
            auto skDrawPart = [&](double ff, double tf) {
                if (ff >= tf || pL <= 0) return;
                double cum = 0;
                for (const auto& sg : sp.segs) {
                    double sL = skSegLen(sg);
                    double sS = cum / pL, sE = (cum + sL) / pL;
                    if (tf > sS && ff < sE) {
                        double lS = std::max(0.0, (ff - sS) / (sE - sS));
                        double lE = std::min(1.0, (tf - sS) / (sE - sS));
                        skDraw(sg, lS, lE, col);
                    }
                    cum += sL;
                }
            };
            skDrawPart(sP, std::min(eP, 1.0));
            if (eP > 1.0)
                skDrawPart(0.0, eP - 1.0);
            return true;
        }

        // General case: iterate paths, draw based on progress
        double skCumLen = 0;
        for (size_t pi = 0; pi < skPaths.size(); ++pi) {
            const auto& sp = skPaths[pi];
            double pL = skPLens[pi];
            xlColor col;
            buf.palette.GetColor(pi % buf.GetColorCount(), col);
            double pctEnd = (skCumLen + pL) / skTotalLen;

            if (!skMotionEnabled && pctEnd <= skAdj) {
                // Draw entire path
                for (const auto& sg : sp.segs)
                    skDraw(sg, 0.0, 1.0, col);
            } else {
                double pctStart = skCumLen / skTotalLen;
                double rng = pctEnd - pctStart;
                if (rng > 0 && skAdj > pctStart) {
                    double thru = std::clamp((skAdj - pctStart) / rng, 0.0, 1.0);
                    double ds = 0.0;
                    if (skMotionEnabled) {
                        double dsProg = skAdj - skMotionPct;
                        ds = std::clamp((dsProg - pctStart) / rng, 0.0, 1.0);
                    }
                    if (pL > 0) {
                        double cumSeg = 0;
                        for (const auto& sg : sp.segs) {
                            double sL = skSegLen(sg);
                            double sSF = cumSeg / pL, sEF = (cumSeg + sL) / pL;
                            if (thru > sSF && ds < sEF) {
                                double lS = std::max(0.0, (ds - sSF) / (sEF - sSF));
                                double lE = std::min(1.0, (thru - sSF) / (sEF - sSF));
                                if (lE > lS)
                                    skDraw(sg, lS, lE, col);
                            }
                            cumSeg += sL;
                        }
                    }
                }
            }
            skCumLen += pL;
        }

        return true;
    }


    if (type == "Snowflakes") {
        // Native Snowflakes effect — port of legacy SnowflakesEffect::Render
        // Supports three modes: Driving (scrolling pattern), Falling (gravity),
        // and Falling & Accumulating (gravity with pile-up at bottom).

        // Read settings
        int Count = 5;
        int SnowflakeType = 1;
        int sSpeed = 10;
        int warmupFrames = 0;
        std::string falling = "Driving";
        bool wrapx = false;

        auto it = effectInfo.settings.find("E_SLIDER_Snowflakes_Count");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Count = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Snowflakes_Type");
        if (it != effectInfo.settings.end() && !it->second.empty())
            SnowflakeType = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Snowflakes_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            sSpeed = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Snowflakes_WarmupFrames");
        if (it != effectInfo.settings.end() && !it->second.empty())
            warmupFrames = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_CHOICE_Falling");
        if (it != effectInfo.settings.end() && !it->second.empty())
            falling = it->second;

        if (Count < 1) Count = 1;
        if (Count > 100) Count = 100;

        int BufferHt = buf.BufferHt;
        int BufferWi = buf.BufferWi;
        if (BufferHt < 1) BufferHt = 1;
        if (BufferWi < 1) BufferWi = 1;

        // Marker colors for driving mode (used in temp buffer only)
        const xlColor c1(0, 1, 0);
        const xlColor c2(0, 0, 1);

        // Palette colors
        xlColor color1, color2;
        buf.palette.GetColor(0, color1);
        if (buf.palette.ExplicitSize() > 1)
            buf.palette.GetColor(1, color2);
        else
            color2 = color1;

        // Persistent cache for snowflake state across frames
        struct SnowflakesCache : public EffectRenderCache {
            int lastCount = 0;
            int lastType = 0;
            std::string lastFalling;
            int effectState = 0;
        };

        SnowflakesCache* cache = dynamic_cast<SnowflakesCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new SnowflakesCache();
            buf.infoCache[0] = cache;
        }

        int& LastSnowflakeCount = cache->lastCount;
        int& LastSnowflakeType = cache->lastType;
        int& effectState = cache->effectState;
        std::string& LastFalling = cache->lastFalling;

        // Lambda: check possible downward moves from position (x,y)
        auto possible_downward_moves = [&](int x, int y) -> int {
            int moves = 0;
            if (y == 0) return 0;
            if (buf.GetTempPixel(x - 1 < 0 ? x - 1 + BufferWi : x - 1, y - 1) == xlBLACK)
                moves += 1;
            if (buf.GetTempPixel(x, y - 1) == xlBLACK)
                moves += 2;
            if (buf.GetTempPixel(x + 1 >= BufferWi ? x + 1 - BufferWi : x + 1, y - 1) == xlBLACK)
                moves += 4;
            return moves;
        };

        // Lambda: set pixel if not already a specific color (for multi-node flake drawing)
        auto set_pixel_if_not_color = [&](int x, int y, const xlColor& toColor,
                                          const xlColor& notColor, bool wx, bool wy) {
            int adjx = x, adjy = y;
            if (x < 0) {
                if (wx) adjx += BufferWi; else return;
            } else if (x >= BufferWi) {
                if (wx) adjx -= BufferWi; else return;
            }
            if (y < 0) {
                if (wy) adjy += BufferHt; else return;
            } else if (y >= BufferHt) {
                if (wy) adjy -= BufferHt; else return;
            }
            if (buf.GetTempPixelRGB(adjx, adjy) != notColor)
                buf.SetPixel(adjx, adjy, toColor);
        };

        // Lambda: move flakes down one step (used in Falling / Falling & Accumulating modes)
        auto moveFlakes = [&]() {
            int starty = 0;
            if (falling == "Falling & Accumulating") starty = 1;

            for (int x = 0; x < BufferWi; x++) {
                for (int y = starty; y < BufferHt; y++) {
                    xlColor color3;
                    buf.GetTempPixel(x, y, color3);
                    if (color3 != xlBLACK) {
                        int moves = possible_downward_moves(x, y);
                        if (moves > 0 || (falling == "Falling" && y == 0)) {
                            int x0;
                            switch (std::rand() % 9) {
                            case 0:
                                if (moves & 1) x0 = x - 1;
                                else if (moves & 2) x0 = x;
                                else x0 = x + 1;
                                break;
                            case 1:
                                if (moves & 4) x0 = x + 1;
                                else if (moves & 2) x0 = x;
                                else x0 = x - 1;
                                break;
                            default:
                                if (moves & 2) x0 = x;
                                else if ((moves & 5) == 4) x0 = x + 1;
                                else if ((moves & 5) == 1) x0 = x - 1;
                                else x0 = (std::rand() % 2 == 0) ? x + 1 : x - 1;
                                break;
                            }
                            if (x0 < 0) x0 += BufferWi;
                            else if (x0 >= BufferWi) x0 -= BufferWi;

                            int y0 = y - 1;
                            buf.SetTempPixel(x, y, xlBLACK);
                            if (y0 >= 0) {
                                buf.SetTempPixel(x0, y0, color3);
                                if (falling == "Falling & Accumulating") {
                                    int nextmoves = possible_downward_moves(x0, y0);
                                    if (nextmoves == 0) effectState--;
                                }
                            } else {
                                effectState--;
                            }
                        }
                    }
                }
            }

            // Add new flakes at the top
            int check = 0;
            int placedFullCount = 0;
            while (effectState < Count && check < 20) {
                int x = std::rand() % BufferWi;
                if (buf.GetTempPixel(x, BufferHt - 1) == xlBLACK) {
                    effectState++;
                    buf.SetTempPixel(x, BufferHt - 1, color1,
                                     SnowflakeType == 0 ? std::rand() % 9 : SnowflakeType - 1);
                    int nextmoves = possible_downward_moves(x, BufferHt - 1);
                    if (nextmoves == 0) placedFullCount++;
                }
                check++;
            }
            effectState -= placedFullCount;
        };

        // Initialize or re-seed when parameters change
        if (buf.needToInit ||
            (Count != LastSnowflakeCount && falling == "Driving") ||
            SnowflakeType != LastSnowflakeType ||
            falling != LastFalling) {

            buf.needToInit = false;
            LastSnowflakeCount = Count;
            LastSnowflakeType = SnowflakeType;
            LastFalling = falling;
            buf.ClearTempBuf();
            effectState = 0;

            for (int n = 0; n < Count; n++) {
                int delta_y = BufferHt / 4;
                int y0 = (n % 4) * delta_y;
                if (y0 + delta_y > BufferHt) delta_y = BufferHt - y0;
                if (delta_y < 1) delta_y = 1;

                int x = 0, y = 0;
                for (int check = 0; check < 20; check++) {
                    x = std::rand() % BufferWi;
                    y = y0 + (std::rand() % delta_y);
                    if (buf.GetTempPixel(x, y) == xlBLACK) {
                        effectState++;
                        break;
                    }
                }

                int flakeType = SnowflakeType == 0 ? std::rand() % 9 : SnowflakeType - 1;
                switch (flakeType) {
                case 0:
                    if (falling != "Driving")
                        buf.SetTempPixel(x, y, color1, 0);
                    else
                        buf.SetTempPixel(x, y, c1);
                    break;
                case 1:
                    if (x < 1) x += 1;
                    if (y < 1) y += 1;
                    if (x > BufferWi - 2) x -= 1;
                    if (y > BufferHt - 2) y -= 1;
                    if (falling != "Driving") {
                        buf.SetTempPixel(x, y, color1, 1);
                    } else {
                        buf.SetTempPixel(x, y, c1);
                        buf.SetTempPixel(x - 1, y, c2);
                        buf.SetTempPixel(x + 1, y, c2);
                        buf.SetTempPixel(x, y - 1, c2);
                        buf.SetTempPixel(x, y + 1, c2);
                    }
                    break;
                case 2:
                    if (x < 1) x += 1;
                    if (y < 1) y += 1;
                    if (x > BufferWi - 2) x -= 1;
                    if (y > BufferHt - 2) y -= 1;
                    if (falling != "Driving") {
                        buf.SetTempPixel(x, y, color1, 2);
                    } else {
                        buf.SetTempPixel(x, y, c1);
                        if (std::rand() % 100 > 50) {
                            buf.SetTempPixel(x - 1, y, c2);
                            buf.SetTempPixel(x + 1, y, c2);
                        } else {
                            buf.SetTempPixel(x, y - 1, c2);
                            buf.SetTempPixel(x, y + 1, c2);
                        }
                    }
                    break;
                case 3:
                    if (x < 2) x += 2;
                    if (y < 2) y += 2;
                    if (x > BufferWi - 3) x -= 2;
                    if (y > BufferHt - 3) y -= 2;
                    if (falling != "Driving") {
                        buf.SetTempPixel(x, y, color1, 3);
                    } else {
                        buf.SetTempPixel(x, y, c1);
                        for (int i = 1; i <= 2; i++) {
                            buf.SetTempPixel(x - i, y, c2);
                            buf.SetTempPixel(x + i, y, c2);
                            buf.SetTempPixel(x, y - i, c2);
                            buf.SetTempPixel(x, y + i, c2);
                        }
                    }
                    break;
                case 4:
                    if (x < 2) x += 2;
                    if (y < 2) y += 2;
                    if (x > BufferWi - 3) x -= 2;
                    if (y > BufferHt - 3) y -= 2;
                    if (falling != "Driving") {
                        buf.SetTempPixel(x, y, color1, 4);
                    } else {
                        buf.SetTempPixel(x, y, c1);
                        buf.SetTempPixel(x - 1, y, c2);
                        buf.SetTempPixel(x + 1, y, c2);
                        buf.SetTempPixel(x, y - 1, c2);
                        buf.SetTempPixel(x, y + 1, c2);
                        buf.SetTempPixel(x - 1, y + 2, c2);
                        buf.SetTempPixel(x + 1, y + 2, c2);
                        buf.SetTempPixel(x - 1, y - 2, c2);
                        buf.SetTempPixel(x + 1, y - 2, c2);
                        buf.SetTempPixel(x + 2, y - 1, c2);
                        buf.SetTempPixel(x + 2, y + 1, c2);
                        buf.SetTempPixel(x - 2, y - 1, c2);
                        buf.SetTempPixel(x - 2, y + 1, c2);
                    }
                    break;
                case 5:
                    if (x > BufferWi - 2) x -= 1;
                    if (y > BufferHt - 2) y -= 1;
                    if (falling != "Driving") {
                        buf.SetTempPixel(x, y, color1, 5);
                    } else {
                        buf.SetTempPixel(x, y, c1);
                        buf.SetTempPixel(x + 1, y, c1);
                        buf.SetTempPixel(x + 1, y + 1, c1);
                        buf.SetTempPixel(x, y + 1, c1);
                    }
                    break;
                case 6:
                    if (x < 1) x += 1;
                    if (y < 1) y += 1;
                    if (x > BufferWi - 2) x -= 1;
                    if (y > BufferHt - 2) y -= 1;
                    if (falling != "Driving") {
                        buf.SetTempPixel(x, y, color1, 6);
                    } else {
                        buf.SetTempPixel(x, y, c1);
                        buf.SetTempPixel(x + 1, y, c1);
                        buf.SetTempPixel(x, y + 1, c1);
                        buf.SetTempPixel(x - 1, y, c1);
                        buf.SetTempPixel(x, y - 1, c1);
                    }
                    break;
                case 7:
                    if (x < 2) x += 2;
                    if (y < 2) y += 2;
                    if (x > BufferWi - 3) x -= 2;
                    if (y > BufferHt - 3) y -= 2;
                    if (falling != "Driving") {
                        buf.SetTempPixel(x, y, color1, 7);
                    } else {
                        buf.SetTempPixel(x, y + 2, c1);
                        buf.SetTempPixel(x - 1, y + 1, c1);
                        buf.SetTempPixel(x, y + 1, c1);
                        buf.SetTempPixel(x + 1, y + 1, c1);
                        buf.SetTempPixel(x - 2, y, c1);
                        buf.SetTempPixel(x - 1, y, c1);
                        buf.SetTempPixel(x, y, c1);
                        buf.SetTempPixel(x + 1, y, c1);
                        buf.SetTempPixel(x + 2, y, c1);
                        buf.SetTempPixel(x - 1, y - 1, c1);
                        buf.SetTempPixel(x, y - 1, c1);
                        buf.SetTempPixel(x + 1, y - 1, c1);
                        buf.SetTempPixel(x, y - 2, c1);
                    }
                    break;
                case 8:
                    if (x < 1) x += 1;
                    if (y < 1) y += 1;
                    if (x > BufferWi - 2) x -= 1;
                    if (y > BufferHt - 2) y -= 1;
                    if (falling != "Driving") {
                        buf.SetTempPixel(x, y, color1, 8);
                    } else {
                        buf.SetTempPixel(x, y, c1);
                        buf.SetTempPixel(x + 1, y + 1, c1);
                        buf.SetTempPixel(x - 1, y + 1, c1);
                        buf.SetTempPixel(x - 1, y - 1, c1);
                        buf.SetTempPixel(x + 1, y - 1, c1);
                    }
                    break;
                default:
                    break;
                }
            }
        }

        // Move snowflakes
        int movement = (buf.curPeriod - buf.curEffStartPer) * sSpeed * buf.frameTimeInMs / 50;
        bool driving = (falling == "Driving");

        if (!driving && buf.curPeriod == buf.curEffStartPer) {
            // Warmup: run movement simulation for warmupFrames before first visible frame
            for (int i = 0; i < warmupFrames; ++i) {
                if ((i * (sSpeed + 1)) / 30 != ((i - 1) * (sSpeed + 1)) / 30) {
                    moveFlakes();
                }
            }
        } else if (!driving) {
            // Speed gating: only advance movement when speed threshold crossed
            if (((buf.curPeriod - buf.curEffStartPer) * (sSpeed + 1)) / 30 !=
                ((buf.curPeriod - buf.curEffStartPer - 1) * (sSpeed + 1)) / 30) {
                moveFlakes();
            }
        }

        // Render to output pixels
        if (driving) {
            // Driving mode: scroll the temp buffer pattern and map marker colors to palette
            for (int x = 0; x < BufferWi; x++) {
                int new_x = (x + movement / 20) % BufferWi;
                int new_x2 = (x - movement / 20) % BufferWi;
                if (new_x2 < 0) new_x2 += BufferWi;
                for (int y = 0; y < BufferHt; y++) {
                    int new_y = (y + movement / 10) % BufferHt;
                    int new_y2 = (new_y + BufferHt / 2) % BufferHt;
                    xlColor color3;
                    buf.GetTempPixel(new_x, new_y, color3);
                    if (color3 == xlBLACK)
                        buf.GetTempPixel(new_x2, new_y2, color3);
                    if (color3 == c1) {
                        buf.SetPixel(x, y, color1);
                    } else if (color3 == c2) {
                        buf.SetPixel(x, y, color2);
                    }
                }
            }
        } else {
            // Falling modes: paint from temp buffer using alpha channel as flake type
            for (int y = 0; y < BufferHt; y++) {
                for (int x = 0; x < BufferWi; x++) {
                    xlColor color3;
                    buf.GetTempPixel(x, y, color3);
                    if (color3 != xlBLACK) {
                        switch (color3.Alpha()) {
                        case 0:
                            buf.SetPixel(x, y, color1);
                            break;
                        case 1:
                            buf.SetPixel(x, y, color1);
                            set_pixel_if_not_color(x - 1, y, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x + 1, y, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x, y - 1, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x, y + 1, color2, color1, wrapx, false);
                            break;
                        case 2: {
                            buf.SetPixel(x, y, color1);
                            bool isAtBottom = true;
                            for (int yt = 0; yt < y - 1; yt++) {
                                if (buf.GetTempPixel(x, yt) == xlBLACK) {
                                    isAtBottom = false;
                                    break;
                                }
                            }
                            if (isAtBottom) {
                                set_pixel_if_not_color(x - 1, y, color2, color1, wrapx, false);
                                set_pixel_if_not_color(x + 1, y, color2, color1, wrapx, false);
                            } else {
                                if (std::rand() % 100 > 50) {
                                    set_pixel_if_not_color(x - 1, y, color2, color1, wrapx, false);
                                    set_pixel_if_not_color(x + 1, y, color2, color1, wrapx, false);
                                } else {
                                    set_pixel_if_not_color(x, y - 1, color2, color1, wrapx, false);
                                    set_pixel_if_not_color(x, y + 1, color2, color1, wrapx, false);
                                }
                            }
                        } break;
                        case 3:
                            buf.SetPixel(x, y, color1);
                            for (int i = 1; i <= 2; i++) {
                                set_pixel_if_not_color(x - i, y, color2, color1, wrapx, false);
                                set_pixel_if_not_color(x + i, y, color2, color1, wrapx, false);
                                set_pixel_if_not_color(x, y - i, color2, color1, wrapx, false);
                                set_pixel_if_not_color(x, y + i, color2, color1, wrapx, false);
                            }
                            break;
                        case 4:
                            buf.SetPixel(x, y, color1);
                            set_pixel_if_not_color(x - 1, y, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x + 1, y, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x, y + 1, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x, y - 1, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x - 1, y + 2, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x + 1, y + 2, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x - 1, y - 2, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x + 1, y - 2, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x + 2, y - 1, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x + 2, y + 1, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x - 2, y - 1, color2, color1, wrapx, false);
                            set_pixel_if_not_color(x - 2, y + 1, color2, color1, wrapx, false);
                            break;
                        case 5:
                            buf.SetPixel(x, y, color1);
                            buf.SetPixel(x + 1, y, color1);
                            buf.SetPixel(x + 1, y + 1, color1);
                            buf.SetPixel(x, y + 1, color1);
                            break;
                        case 6:
                            buf.SetPixel(x, y, color1);
                            buf.SetPixel(x + 1, y, color1);
                            buf.SetPixel(x, y + 1, color1);
                            buf.SetPixel(x - 1, y, color1);
                            buf.SetPixel(x, y - 1, color1);
                            break;
                        case 7:
                            buf.SetPixel(x, y + 2, color1);
                            buf.SetPixel(x - 1, y + 1, color1);
                            buf.SetPixel(x, y + 1, color1);
                            buf.SetPixel(x + 1, y + 1, color1);
                            buf.SetPixel(x - 2, y, color1);
                            buf.SetPixel(x - 1, y, color1);
                            buf.SetPixel(x, y, color1);
                            buf.SetPixel(x + 1, y, color1);
                            buf.SetPixel(x + 2, y, color1);
                            buf.SetPixel(x - 1, y - 1, color1);
                            buf.SetPixel(x, y - 1, color1);
                            buf.SetPixel(x + 1, y - 1, color1);
                            buf.SetPixel(x, y - 2, color1);
                            break;
                        case 8:
                            buf.SetPixel(x, y, color1);
                            buf.SetPixel(x + 1, y + 1, color1);
                            buf.SetPixel(x - 1, y + 1, color1);
                            buf.SetPixel(x - 1, y - 1, color1);
                            buf.SetPixel(x + 1, y - 1, color1);
                            break;
                        default:
                            break;
                        }
                    }
                }
            }
        }
        return true;
    }


    if (type == "Snowstorm") {
        // Native Snowstorm effect — port of legacy SnowstormEffect::Render
        // Simulates snow particles that wander randomly with decaying trails.
        int count = 50;
        int tailLength = 50;
        int sSpeed = 10;

        auto it = effectInfo.settings.find("E_SLIDER_Snowstorm_Count");
        if (it != effectInfo.settings.end() && !it->second.empty())
            count = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Snowstorm_Length");
        if (it != effectInfo.settings.end() && !it->second.empty())
            tailLength = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Snowstorm_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            sSpeed = std::atoi(it->second.c_str());

        if (tailLength == 0) tailLength = 1;

        HSVValue hsv0, hsv1;
        buf.palette.GetHSV(0, hsv0);
        buf.palette.GetHSV(1, hsv1);

        // Snowstorm item: a wandering particle with a trail of points
        struct SnowstormItem {
            std::vector<std::pair<int, int>> points;
            HSVValue hsv;
            int idx = 0;
            int ssDecay = 0;
        };

        struct SnowstormCache : public EffectRenderCache {
            int lastCount = -1;
            std::vector<SnowstormItem> items;
        };

        SnowstormCache* cache = dynamic_cast<SnowstormCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new SnowstormCache();
            buf.infoCache[0] = cache;
        }

        // Direction vectors for 8-connected movement (0-7)
        auto snowstormVector = [](int idx) -> std::pair<int, int> {
            switch (idx) {
                case 0: return {-1,  0};
                case 1: return {-1, -1};
                case 2: return { 0, -1};
                case 3: return { 1, -1};
                case 4: return { 1,  0};
                case 5: return { 1,  1};
                case 6: return { 0,  1};
                default: return {-1,  1};
            }
        };

        // Advance a snowstorm item by one step using weighted random direction
        auto snowstormAdvance = [&](SnowstormItem& ssItem) {
            const int cnt = 8;
            const int arr[] = { 30,20,10,5,0,5,10,20, 20,15,10,10,10,10,10,15 };
            auto adv = snowstormVector(7);
            int i0 = (ssItem.idx % 7 <= 4) ? 0 : cnt;
            int r = std::rand() % 100;
            for (int i = 0, val = 0; i < cnt; i++) {
                val += arr[i0 + i];
                if (r < val) {
                    adv = snowstormVector(i);
                    break;
                }
            }

            if (ssItem.idx % 3 == 0) {
                adv.first *= 2;
                adv.second *= 2;
            }

            auto last = ssItem.points.back();
            int nx = (last.first + adv.first) % buf.BufferWi;
            int ny = (last.second + adv.second) % buf.BufferHt;
            if (nx < 0) nx += buf.BufferWi;
            if (ny < 0) ny += buf.BufferHt;
            ssItem.points.push_back({nx, ny});
        };

        if (buf.needToInit || count != cache->lastCount) {
            buf.needToInit = false;
            cache->lastCount = count;
            cache->items.clear();
            cache->items.resize(count);

            for (int i = 0; i < count; i++) {
                auto& ssItem = cache->items[i];
                ssItem.idx = i;
                ssItem.ssDecay = 0;
                ssItem.points.clear();
                buf.SetRangeColor(hsv0, hsv1, ssItem.hsv);

                // Start each item in a random state along its lifecycle
                int r = std::rand() % (2 * tailLength);
                if (r > 0) {
                    int sx = std::rand() % buf.BufferWi;
                    int sy = std::rand() % buf.BufferHt;
                    ssItem.points.push_back({sx, sy});
                }
                if (r >= tailLength) {
                    ssItem.ssDecay = r - tailLength;
                    r = tailLength;
                }
                for (int j = 1; j < r; j++) {
                    snowstormAdvance(ssItem);
                }
            }
        } else {
            // Update colors (supports color curve changes across time)
            for (auto& ssItem : cache->items) {
                double val = ssItem.hsv.value;
                buf.SetRangeColor(hsv0, hsv1, ssItem.hsv);
                ssItem.hsv.value = val;
            }
        }

        // Simulate and render each snowstorm item
        for (auto& ssItem : cache->items) {
            if ((int)ssItem.points.size() > tailLength) {
                if (ssItem.ssDecay > tailLength) {
                    ssItem.points.clear();
                    ssItem.ssDecay = 0;
                } else if (std::rand() % 20 < sSpeed) {
                    ssItem.ssDecay++;
                }
            }

            if (ssItem.points.empty()) {
                int sx = std::rand() % buf.BufferWi;
                int sy = std::rand() % buf.BufferHt;
                ssItem.points.push_back({sx, sy});
            } else if (std::rand() % 20 < sSpeed) {
                snowstormAdvance(ssItem);
            }

            int sz = (int)ssItem.points.size();
            for (int pt = 0; pt < sz; pt++) {
                HSVValue ptHsv = ssItem.hsv;
                if (buf.allowAlpha) {
                    xlColor c(ptHsv);
                    c.alpha = (uint8_t)(255.8 * (1.0 - (double)(sz - pt + ssItem.ssDecay) / tailLength));
                    buf.SetPixel(ssItem.points[pt].first, ssItem.points[pt].second, c);
                } else {
                    ptHsv.value = 1.0 - (double)(sz - pt + ssItem.ssDecay) / tailLength;
                    if (ptHsv.value < 0.0) ptHsv.value = 0.0;
                    buf.SetPixel(ssItem.points[pt].first, ssItem.points[pt].second, ptHsv);
                }
            }
        }

        return true;
    }


    if (type == "Spirals") {
        // Native Spirals effect — port of legacy SpiralsEffect::Render
        // Settings: E_SLIDER_Spirals_Count (1-5, default 1) — palette repeat
        //           E_SLIDER_Spirals_Rotation (-500..500, default 20; divide by 10)
        //           E_SLIDER_Spirals_Thickness (0-100, default 50)
        //           E_CHOICE_Spirals_Direction ("Up"/"Down", default "Up")
        //             — legacy sequences may have E_SLIDER_Spirals_Movement instead
        //           E_CHECKBOX_Spirals_Blend (0/1, default 0)
        //           E_CHECKBOX_Spirals_3D (0/1, default 0)
        //           E_CHECKBOX_Spirals_Grow (0/1, default 0)
        //           E_CHECKBOX_Spirals_Shrink (0/1, default 0)

        int PaletteRepeat = 1;
        double Movement = 1.0;
        double Rotation = 2.0; // default 20 / 10
        int Thickness = 50;
        bool Blend = false;
        bool Show3D = false;
        bool grow = false;
        bool shrink = false;

        auto it = effectInfo.settings.find("E_SLIDER_Spirals_Count");
        if (it != effectInfo.settings.end() && !it->second.empty())
            PaletteRepeat = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Spirals_Rotation");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Rotation = std::atof(it->second.c_str()) / 10.0;

        it = effectInfo.settings.find("E_SLIDER_Spirals_Thickness");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Thickness = std::atoi(it->second.c_str());

        // Handle Movement: legacy sequences store E_SLIDER_Spirals_Movement (-200..200, divisor 10)
        // Native panel uses E_CHOICE_Spirals_Direction ("Up"/"Down") with fixed speed of 1.0
        it = effectInfo.settings.find("E_SLIDER_Spirals_Movement");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            Movement = std::atof(it->second.c_str()) / 10.0;
        } else {
            it = effectInfo.settings.find("E_CHOICE_Spirals_Direction");
            if (it != effectInfo.settings.end()) {
                if (it->second == "Down")
                    Movement = -1.0;
                else
                    Movement = 1.0;
            }
        }

        it = effectInfo.settings.find("E_CHECKBOX_Spirals_Blend");
        if (it != effectInfo.settings.end())
            Blend = (it->second == "1");

        it = effectInfo.settings.find("E_CHECKBOX_Spirals_3D");
        if (it != effectInfo.settings.end())
            Show3D = (it->second == "1");

        it = effectInfo.settings.find("E_CHECKBOX_Spirals_Grow");
        if (it != effectInfo.settings.end())
            grow = (it->second == "1");

        it = effectInfo.settings.find("E_CHECKBOX_Spirals_Shrink");
        if (it != effectInfo.settings.end())
            shrink = (it->second == "1");

        if (PaletteRepeat == 0) {
            PaletteRepeat = 1;
        }

        size_t colorcnt = buf.GetColorCount();
        int SpiralCount = static_cast<int>(colorcnt) * PaletteRepeat;
        double deltaStrands = static_cast<double>(buf.BufferWi) / SpiralCount;
        double SpiralThickness = (deltaStrands * Thickness / 100.0) + 1;
        double spiralGap = deltaStrands - SpiralThickness;

        int Direction = Movement > 0.001 ? 1 : (Movement < -0.001 ? -1 : 0);
        double position = static_cast<double>(buf.GetEffectTimeIntervalPosition(
            static_cast<float>(std::abs(Movement))));

        long ThicknessState = 0;
        if (grow && shrink) {
            ThicknessState = position <= 0.5
                ? static_cast<long>(spiralGap * (position * 2))
                : static_cast<long>(spiralGap * ((1.0 - position) * 2));
        } else if (grow) {
            ThicknessState = static_cast<long>(spiralGap * position);
        } else if (shrink) {
            ThicknessState = static_cast<long>(spiralGap * (1.0 - position));
        }
        long SpiralState = static_cast<long>(position * buf.BufferWi * 10 * Direction);

        SpiralThickness += ThicknessState;

        for (int ns = 0; ns < SpiralCount; ns++) {
            int strand_base = static_cast<int>(ns * deltaStrands);
            int ColorIdx = ns % static_cast<int>(colorcnt);
            xlColor color;
            buf.palette.GetColor(ColorIdx, color);

            int thicknessInt = static_cast<int>(SpiralThickness);
            for (int thick = 0; thick < thicknessInt; thick++) {
                int strand = (strand_base + thick) % buf.BufferWi;
                for (int y = 0; y < buf.BufferHt; y++) {
                    int x = static_cast<int>(strand + SpiralState / 10.0
                        + y * Rotation / buf.BufferHt) % buf.BufferWi;
                    if (x < 0) x += buf.BufferWi;

                    if (Blend) {
                        buf.GetMultiColorBlend(
                            static_cast<double>(buf.BufferHt - y - 1)
                                / static_cast<double>(buf.BufferHt),
                            false, color);
                    }

                    if (Show3D) {
                        double f = 1.0;
                        if (Rotation < 0) {
                            f = static_cast<double>(thick + 1) / SpiralThickness;
                        } else {
                            f = (SpiralThickness - thick) / SpiralThickness;
                        }
                        if (buf.allowAlpha) {
                            xlColor c(color);
                            c.alpha = static_cast<uint8_t>(255.0 * f);
                            buf.SetPixel(x, y, c);
                        } else {
                            HSVValue hsv;
                            buf.Color2HSV(color, hsv);
                            hsv.value *= f;
                            buf.SetPixel(x, y, hsv);
                        }
                    } else {
                        buf.SetPixel(x, y, color);
                    }
                }
            }
        }
        return true;
    }


    if (type == "Spirograph") {
        // Native Spirograph effect — port of legacy SpirographEffect::Render
        // Draws a hypotrochoid: a roulette traced by a point attached to a circle
        // of radius r rolling inside a fixed circle of radius R, where the point
        // is distance d from the center of the rolling circle.
        //
        // Parametric equations:
        //   x(t) = (R-r) * cos(t) + d * cos((R-r)/r * t)
        //   y(t) = (R-r) * sin(t) + d * sin((R-r)/r * t)
        //
        // Settings: E_SLIDER_Spirograph_R      (1-100, default 20)
        //           E_SLIDER_Spirograph_r      (1-100, default 10)
        //           E_SLIDER_Spirograph_d      (1-100, default 30)
        //           E_SLIDER_Spirograph_Animate (-50 to 50, default 0)
        //           E_SLIDER_Spirograph_Speed  (0-50, default 10)
        //           E_SLIDER_Spirograph_Length  (0-50, default 20)
        //           E_SLIDER_Spirograph_Width   (1-50, default 1)

        int int_R = 20, int_r = 10, int_d = 30;
        int Animate = 0, sspeed = 10, length = 20, width = 1;

        auto it = effectInfo.settings.find("E_SLIDER_Spirograph_R");
        if (it != effectInfo.settings.end() && !it->second.empty())
            int_R = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Spirograph_r");
        if (it != effectInfo.settings.end() && !it->second.empty())
            int_r = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Spirograph_d");
        if (it != effectInfo.settings.end() && !it->second.empty())
            int_d = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Spirograph_Animate");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Animate = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Spirograph_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            sspeed = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Spirograph_Length");
        if (it != effectInfo.settings.end() && !it->second.empty())
            length = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Spirograph_Width");
        if (it != effectInfo.settings.end() && !it->second.empty())
            width = std::atoi(it->second.c_str());

        if (width < 1) width = 1;

        size_t colorcnt = buf.GetColorCount();
        int d_mod;

        int state = (buf.curPeriod - buf.curEffStartPer) * sspeed * buf.frameTimeInMs / 50;
        double animateState = double((buf.curPeriod - buf.curEffStartPer) * Animate * buf.frameTimeInMs) / 5000.0;

        length = length * 18;

        float xc = (float)buf.BufferWi / 2.0f;
        float yc = (float)buf.BufferHt / 2.0f;
        float R = xc * (int_R / 100.0f);
        float r = xc * (int_r / 100.0f);
        if (r == 0.0f) {
            r = 0.00001f;
        }
        if (r > R) r = R;
        float d = xc * (int_d / 100.0f);

        int mod1440 = state % 1440;
        float d_orig = d;
        if (Animate) d = d_orig + (float)animateState * d_orig;

        float step = 1.0f / width;
        float stepw = 1.0f / (std::log10((float)width) + 1.0f);
        if (step == 0.0f) step = 1.0f;
        if (stepw == 0.0f) stepw = 1.0f;

        for (float i = 1.0f; i <= length; i += step) {
            float t = (i + mod1440) * (float)M_PI / 180.0f;
            float x = (R - r) * buf.cos(t) + d * buf.cos(((R - r) / r) * t) + xc;
            float y = (R - r) * buf.sin(t) + d * buf.sin(((R - r) / r) * t) + yc;

            if (colorcnt > 0) d_mod = (int)buf.BufferWi / (int)colorcnt;
            else d_mod = 1;
            if (d_mod == 0) d_mod = 1;

            double x2 = std::pow((double)(x - xc), 2.0);
            double y2 = std::pow((double)(y - yc), 2.0);
            double hyp = (std::sqrt(x2 + y2) / buf.BufferWi) * 100.0;
            int ColorIdx = (int)(hyp / d_mod);

            if (ColorIdx >= (int)colorcnt) ColorIdx = (int)colorcnt - 1;
            if (ColorIdx < 0) ColorIdx = 0;

            HSVValue hsv;
            buf.palette.GetHSV(ColorIdx, hsv);

            float tt = ((R - r) / r) * t;
            for (float w = -width / 2.0f; w <= width / 2.0f; w += stepw) {
                int xx = (int)(x + w * buf.cos(tt));
                int yy = (int)(y + w * buf.sin(tt));
                buf.SetPixel(xx, yy, hsv);
            }
        }
        return true;
    }


    if (type == "State") {
        // Native State effect stub.
        //
        // The full State effect requires:
        //   1. Model state definitions (model_info->GetStateInfo()) mapping state
        //      names to node ranges or single nodes
        //   2. Timing track sync to read labels from a timing track at the
        //      current time, which drives which states are active
        //   3. Mode logic (Default, Countdown, Time Countdown, Number, Iterate)
        //   4. SetNodePixel() which maps state names to specific node indices
        //      rather than x,y pixel coordinates
        //
        // None of this infrastructure is available in the native render pipeline
        // yet (no IModelProvider::getStateInfo, no timing track label query on
        // IEffectProvider). For now, fill with the graduated palette color so
        // the effect is visually present and the render coordinator does not
        // report it as an unknown effect.

        // Read colour mode from settings (Graduate, Cycle, Allocate)
        std::string colourMode = "Graduate";
        auto cmIt = effectInfo.settings.find("E_CHOICE_State_Color");
        if (cmIt != effectInfo.settings.end() && !cmIt->second.empty()) {
            colourMode = cmIt->second;
        }

        xlColor color;
        if (colourMode == "Graduate") {
            float pos = buf.GetEffectTimeIntervalPosition();
            buf.GetMultiColorBlend(pos, false, color);
        } else if (colourMode == "Cycle") {
            // Without interval number from timing track, use first color
            buf.palette.GetColor(0, color);
        } else {
            // "Allocate" mode - use first palette color as fallback
            buf.palette.GetColor(0, color);
        }

        buf.Fill(color);
        return true;
    }


    if (type == "Strobe") {
        // Native Strobe effect — port of legacy StrobeEffect::Render
        //
        // Settings keys (from XLEffectPanelDefinitions.mm kStrobeParameters):
        //   E_SLIDER_Strobe_Number   — number of simultaneous strobes (1..300, default 10)
        //   E_SLIDER_Strobe_Duration — how many frames each strobe stays lit (1..100, default 10)
        //   E_CHOICE_Strobe_Type     — shape type: index 0..3 maps to legacy 1..4
        //   E_CHECKBOX_Strobe_Music  — react to music (0/1)

        int Number_Strobes = 10;
        int StrobeDuration = 10;
        int Strobe_Type = 1;
        bool reactToMusic = false;

        auto it = effectInfo.settings.find("E_SLIDER_Strobe_Number");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Number_Strobes = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_SLIDER_Strobe_Duration");
        if (it != effectInfo.settings.end() && !it->second.empty())
            StrobeDuration = std::atoi(it->second.c_str());

        it = effectInfo.settings.find("E_CHOICE_Strobe_Type");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            // Native uses a choice dropdown; map choice string to legacy integer 1..4.
            // Choices: "On"=1, "Off"=1(fallback), "Strobe"=1, "Strobe 1"=1,
            //          "Strobe 2"=2, "Strobe 3"=3, "Strobe 4"=4
            // The legacy slider was 1..4 where:
            //   1 = single pixel, 2 = random cross/bar, 3 = full cross, 4 = random X/+
            const std::string& tv = it->second;
            if (tv == "Strobe 2" || tv == "2") Strobe_Type = 2;
            else if (tv == "Strobe 3" || tv == "3") Strobe_Type = 3;
            else if (tv == "Strobe 4" || tv == "4") Strobe_Type = 4;
            else Strobe_Type = 1;
        }

        it = effectInfo.settings.find("E_CHECKBOX_Strobe_Music");
        if (it != effectInfo.settings.end())
            reactToMusic = (it->second == "1");

        // React to music: scale number of strobes by audio level
        // (Audio integration not yet available in native build — stub for future)
        if (reactToMusic) {
            // In legacy code this multiplies Number_Strobes by the audio frame max.
            // Without audio access in native, we leave Number_Strobes unchanged.
            // TODO: integrate with IRenderContext audio when available
        }

        // Persistent strobe state via EffectRenderCache
        struct StrobeEntry {
            int x, y;
            int duration;
            HSVValue hsv;
            xlColor color;
        };

        struct StrobeCache : public EffectRenderCache {
            std::list<StrobeEntry> strobes;
        };

        StrobeCache* cache = dynamic_cast<StrobeCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new StrobeCache();
            buf.infoCache[0] = cache;
        }
        auto& strobes = cache->strobes;

        if (StrobeDuration < 1) StrobeDuration = 1;

        size_t colorcnt = buf.GetColorCount();
        if (colorcnt < 1) colorcnt = 1;

        // On first frame, pre-populate strobes across duration phases
        if (buf.needToInit) {
            buf.needToInit = false;
            strobes.clear();

            for (int i = 0; i < Number_Strobes * StrobeDuration; i++) {
                int colorIdx = std::rand() % colorcnt;
                HSVValue hsv;
                xlColor color;
                buf.palette.GetHSV(colorIdx, hsv);
                buf.palette.GetColor(colorIdx, color);
                StrobeEntry e;
                e.x = std::rand() % buf.BufferWi;
                e.y = std::rand() % buf.BufferHt;
                e.duration = i % StrobeDuration;
                e.hsv = hsv;
                e.color = color;
                strobes.push_back(e);
            }
        }

        // Create new strobes to maintain target count
        while (static_cast<int>(strobes.size()) < Number_Strobes * StrobeDuration) {
            int colorIdx = std::rand() % colorcnt;
            HSVValue hsv;
            xlColor color;
            buf.palette.GetHSV(colorIdx, hsv);
            buf.palette.GetColor(colorIdx, color);
            StrobeEntry e;
            e.x = std::rand() % buf.BufferWi;
            e.y = std::rand() % buf.BufferHt;
            e.duration = StrobeDuration;
            e.hsv = hsv;
            e.color = color;
            strobes.push_back(e);
        }

        // Render active strobes
        auto sit = strobes.begin();
        while (sit != strobes.end()) {
            HSVValue hsv = sit->hsv;
            xlColor color = sit->color;
            int x = sit->x;
            int y = sit->y;

            // Draw center pixel at full brightness while duration > 0
            if (sit->duration > 0) {
                buf.SetPixel(x, y, color);
            }

            // Compute dimmed color for surrounding pixels (fade as duration decreases)
            double v = 1.0;
            if (sit->duration == 1) {
                v = 0.5;
            } else if (sit->duration == 2) {
                v = 0.75;
            }

            if (buf.allowAlpha) {
                color.alpha = static_cast<uint8_t>(255.0 * v);
            } else {
                hsv.value *= v;
                color = hsv;
            }

            // Type 2: random horizontal or vertical bar (2 extra pixels)
            if (Strobe_Type == 2) {
                int r = std::rand() % 2;
                if (r == 0) {
                    buf.SetPixel(x, y - 1, color);
                    buf.SetPixel(x, y + 1, color);
                } else {
                    buf.SetPixel(x - 1, y, color);
                    buf.SetPixel(x + 1, y, color);
                }
            }

            // Type 3: full cross (4 extra pixels)
            if (Strobe_Type == 3) {
                buf.SetPixel(x, y - 1, color);
                buf.SetPixel(x, y + 1, color);
                buf.SetPixel(x - 1, y, color);
                buf.SetPixel(x + 1, y, color);
            }

            // Type 4: random cross (+) or X pattern
            if (Strobe_Type == 4) {
                int r = std::rand() % 2;
                if (r == 0) {
                    buf.SetPixel(x, y - 1, color);
                    buf.SetPixel(x, y + 1, color);
                    buf.SetPixel(x - 1, y, color);
                    buf.SetPixel(x + 1, y, color);
                } else {
                    buf.SetPixel(x + 1, y - 1, color);
                    buf.SetPixel(x + 1, y + 1, color);
                    buf.SetPixel(x - 1, y - 1, color);
                    buf.SetPixel(x - 1, y + 1, color);
                }
            }

            // Decrement duration; remove expired strobes
            sit->duration--;
            if (sit->duration <= 0) {
                sit = strobes.erase(sit);
            } else {
                ++sit;
            }
        }

        return true;
    }


    if (type == "Tree") {
        // Native Tree effect — port of legacy TreeEffect::Render
        // Settings: E_SLIDER_Tree_Branches (default 3), E_SLIDER_Tree_Speed (default 10)
        // E_CHECKBOX_Tree_ShowLights is forced to "1" by adjustSettings for all sequences
        int Branches = 3;
        int tspeed = 10;
        bool showlights = true;

        auto it = effectInfo.settings.find("E_SLIDER_Tree_Branches");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Branches = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Tree_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            tspeed = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_CHECKBOX_Tree_ShowLights");
        if (it != effectInfo.settings.end())
            showlights = (it->second == "1");

        int effectState = (buf.curPeriod - buf.curEffStartPer) * tspeed * buf.frameTimeInMs / 50;

        int number_garlands = 1;
        if (Branches < 1) Branches = 1;
        int pixels_per_branch = (int)(0.5 + (double)buf.BufferHt / Branches);
        if (pixels_per_branch < 1) pixels_per_branch = 1;

        int maxFrame = (Branches + 1) * buf.BufferWi;
        int frame;
        if (effectState > 0 && maxFrame > 0)
            frame = (effectState / 4) % maxFrame;
        else
            frame = 1;

        for (int y = 0; y < buf.BufferHt; y++) {
            for (int x = 0; x < buf.BufferWi; x++) {
                int mod;
                if (pixels_per_branch > 0)
                    mod = y % pixels_per_branch;
                else
                    mod = 0;
                if (mod == 0) mod = pixels_per_branch;
                float V = 1.0f - (1.0f * mod / pixels_per_branch) * 0.70f;

                // Background tree color from first palette entry
                xlColor color;
                buf.palette.GetColor(0, color);
                if (buf.allowAlpha) {
                    color.alpha = (uint8_t)(255.0f * V);
                } else {
                    HSVValue hsv = color.asHSV();
                    hsv.value = V;
                    color = hsv;
                }

                int branch = (int)((y - 1) / pixels_per_branch);
                int row = pixels_per_branch - mod;

                int b = (int)((effectState) / buf.BufferWi) % Branches;
                int f_mod = (effectState / 4) % buf.BufferWi;

                int m = (x % 6);
                if (m == 0) m = 6;

                int r = branch % 5;
                float H = r / 4.0f;

                int odd_even = b % 2;
                int s_odd_row = buf.BufferWi - x + 1;

                if (branch <= b && x <= frame &&
                    (((row == 3 || (number_garlands == 2 && row == 6)) && (m == 1 || m == 6))
                     ||
                     ((row == 2 || (number_garlands == 2 && row == 5)) && (m == 2 || m == 5))
                     ||
                     ((row == 1 || (number_garlands == 2 && row == 4)) && (m == 3 || m == 4))
                     ))
                {
                    if (showlights) {
                        if ((odd_even == 0 && x <= f_mod) || (odd_even == 1 && s_odd_row <= f_mod)) {
                            HSVValue hsv;
                            hsv.hue = H;
                            hsv.saturation = 1.0;
                            hsv.value = 1.0;
                            color = hsv;
                        }
                    }
                }

                buf.SetPixel(x, y, color);
            }
        }
        return true;
    }


    if (type == "Twinkle") {
        // Native Twinkle effect — port of legacy TwinkleEffect::Render
        // Uses the "New Render Method" algorithm (the native panel doesn't expose
        // the Style choice, so we always use the modern algorithm).

        // --- Parse settings ---
        int Count = 3;
        int Steps = 30;
        bool Strobe = false;
        bool reRandomize = false;

        auto it = effectInfo.settings.find("E_SLIDER_Twinkle_Count");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Count = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Twinkle_Steps");
        if (it != effectInfo.settings.end() && !it->second.empty())
            Steps = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_CHECKBOX_Twinkle_Strobe");
        if (it != effectInfo.settings.end())
            Strobe = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Twinkle_ReRandom");
        if (it != effectInfo.settings.end())
            reRandomize = (it->second == "1");

        // Check for old render method (from pre-2020.57 sequences)
        bool new_algorithm = true;
        it = effectInfo.settings.find("E_CHOICE_Twinkle_Style");
        if (it != effectInfo.settings.end() && it->second == "Old Render Method")
            new_algorithm = false;

        // Clamp
        if (Count < 2) Count = 2;
        if (Count > 100) Count = 100;
        if (Steps < 2) Steps = 2;
        if (Steps > 200) Steps = 200;

        int strobeCount = buf.BufferHt * buf.BufferWi;
        if (strobeCount < 1) strobeCount = 1;

        int lights = static_cast<int>(std::round(
            static_cast<float>(strobeCount * Count) / 100.0f));
        if (strobeCount == 1) lights = 1;
        if (lights < 1) lights = 1;

        int step = strobeCount / lights;
        if (step < 1) step = 1;

        int max_modulo = Steps;
        if (max_modulo < 2) max_modulo = 2;
        int max_modulo2 = max_modulo / 2;
        if (max_modulo2 < 1) max_modulo2 = 1;

        // --- Persistent twinkle state via EffectRenderCache ---
        struct TwinkleStrobe {
            int x = 0;
            int y = 0;
            int duration = 0;
            int colorindex = 0;
            int strobing = -1;  // -1 = inactive, 1 = active, 0 = done
        };

        struct TwinkleCache : public EffectRenderCache {
            std::vector<TwinkleStrobe> strobe;
            int num_lights = 0;
            int curNumStrobe = 0;
            int lights_to_renew = 0;
        };

        // Use effectId as cache key so multiple twinkle effects don't collide
        int cacheKey = static_cast<int>(effectInfo.effectId & 0x7FFFFFFF);
        TwinkleCache* cache = dynamic_cast<TwinkleCache*>(buf.infoCache[cacheKey]);
        if (!cache) {
            cache = new TwinkleCache();
            buf.infoCache[cacheKey] = cache;
            cache->num_lights = lights;
            cache->lights_to_renew = lights;
            cache->curNumStrobe = 0;
        }

        auto& strobe = cache->strobe;
        size_t colorcnt = buf.GetColorCount();
        if (colorcnt < 1) colorcnt = 1;

        if (new_algorithm) {
            cache->lights_to_renew += lights - cache->num_lights;
        } else {
            if (lights != cache->num_lights) {
                buf.needToInit = true;
            }
        }
        cache->num_lights = lights;

        // --- Initialization ---
        if (buf.needToInit) {
            buf.needToInit = false;
            cache->lights_to_renew = lights;
            cache->curNumStrobe = 0;

            if (new_algorithm) {
                strobe.clear();
                strobe.resize(strobeCount);
                int s = 0;
                for (int x = 0; x < buf.BufferWi; x++) {
                    for (int y = 0; y < buf.BufferHt; y++) {
                        strobe[s].x = x;
                        strobe[s].y = y;
                        strobe[s].duration = 0;
                        strobe[s].strobing = -1;
                        s++;
                    }
                }
                // Randomize positions (Fisher-Yates-ish shuffle matching legacy)
                for (int s2 = 0; s2 < static_cast<int>(strobe.size()); ++s2) {
                    int r = std::rand() % static_cast<int>(strobe.size());
                    if (r != s2) {
                        std::swap(strobe[r], strobe[s2]);
                    }
                }
            } else {
                // Old render method initialization
                strobe.clear();
                cache->curNumStrobe = 0;
                for (int y = 0; y < buf.BufferHt; y++) {
                    for (int x = 0; x < buf.BufferWi; x++) {
                        int i = y * buf.BufferWi + x + 1;
                        if (i % step == 1 || step == 1) {
                            TwinkleStrobe ts;
                            ts.x = x;
                            ts.y = y;
                            ts.duration = std::rand() % max_modulo;
                            ts.colorindex = std::rand() % colorcnt;
                            ts.strobing = 1;
                            strobe.push_back(ts);
                            cache->curNumStrobe++;
                        }
                    }
                }
            }
        }

        // --- New algorithm: compact and place twinkles ---
        if (new_algorithm) {
            if (cache->lights_to_renew > 0) {
                // Compact: move non-strobing entries to end
                while (cache->curNumStrobe > 0 &&
                       !strobe[cache->curNumStrobe - 1].strobing) {
                    cache->curNumStrobe--;
                }
                for (int x = 0; x < cache->curNumStrobe; x++) {
                    if (!strobe[x].strobing) {
                        cache->curNumStrobe--;
                        if (x != cache->curNumStrobe) {
                            std::swap(strobe[x], strobe[cache->curNumStrobe]);
                        }
                        while (cache->curNumStrobe > 0 &&
                               !strobe[cache->curNumStrobe - 1].strobing) {
                            cache->curNumStrobe--;
                        }
                    }
                }

                // Place new twinkles from the pool of inactive entries
                int toPlace = cache->lights_to_renew;
                int curIdx = cache->curNumStrobe;
                while (toPlace > 0 && curIdx < static_cast<int>(strobe.size())) {
                    int pool = static_cast<int>(strobe.size()) - curIdx;
                    int idx = (std::rand() % pool) + curIdx;
                    if (idx != curIdx) {
                        std::swap(strobe[idx], strobe[curIdx]);
                    }
                    strobe[curIdx].duration = std::rand() % max_modulo;
                    strobe[curIdx].colorindex = std::rand() % colorcnt;
                    strobe[curIdx].strobing = 1;
                    curIdx++;
                    toPlace--;
                }
                cache->curNumStrobe = curIdx;
                cache->lights_to_renew = 0;
            }
        }

        // --- Render active twinkles ---
        for (int x = 0; x < cache->curNumStrobe; x++) {
            strobe[x].duration++;

            if (new_algorithm && !strobe[x].strobing) {
                continue;
            }
            if (strobe[x].duration < 0) {
                continue;
            }
            if (strobe[x].duration == max_modulo) {
                strobe[x].duration = 0;
                if (new_algorithm) {
                    cache->lights_to_renew++;
                    strobe[x].strobing = 0;
                } else if (reRandomize) {
                    strobe[x].duration -= std::rand() % max_modulo2;
                    strobe[x].colorindex = std::rand() % colorcnt;
                }
            }

            int i7 = strobe[x].duration;
            double v;
            if (i7 <= max_modulo2) {
                v = (max_modulo2 > 0) ? (1.0 * i7) / max_modulo2 : 0.0;
            } else {
                v = (max_modulo2 > 0) ? (max_modulo - i7) * 1.0 / max_modulo2 : 0.0;
            }
            if (v < 0.0) v = 0.0;

            if (Strobe) {
                v = (i7 == max_modulo2) ? 1.0 : 0.0;
            }

            if (buf.allowAlpha) {
                xlColor color;
                buf.palette.GetColor(strobe[x].colorindex, color);
                color.alpha = static_cast<uint8_t>(255.0 * v);
                buf.SetPixel(strobe[x].x, strobe[x].y, color);
            } else {
                HSVValue hsv;
                buf.palette.GetHSV(strobe[x].colorindex, hsv);
                hsv.value = v;
                buf.SetPixel(strobe[x].x, strobe[x].y, hsv);
            }
        }

        return true;
    }


    if (type == "Wave") {
        // Native Wave effect — port of legacy WaveEffect::Render

        // Wave type constants
        constexpr int WAVETYPE_SINE = 0;
        constexpr int WAVETYPE_TRIANGLE = 1;
        constexpr int WAVETYPE_SQUARE = 2;
        constexpr int WAVETYPE_DECAYSINE = 3;
        constexpr int WAVETYPE_IVYFRACTAL = 4;

        // Parse wave type
        int waveType = WAVETYPE_SINE;
        auto it = effectInfo.settings.find("E_CHOICE_Wave_Type");
        if (it != effectInfo.settings.end()) {
            if (it->second == "Sine") waveType = WAVETYPE_SINE;
            else if (it->second == "Triangle") waveType = WAVETYPE_TRIANGLE;
            else if (it->second == "Square") waveType = WAVETYPE_SQUARE;
            else if (it->second == "Decaying Sine") waveType = WAVETYPE_DECAYSINE;
            else if (it->second == "Fractal/ivy" || it->second == "Fractal/Ivy") waveType = WAVETYPE_IVYFRACTAL;
        }

        // Parse fill color mode: 0=None/Solid, 1=Rainbow, 2=Palette
        int fillColor = 0;
        it = effectInfo.settings.find("E_CHOICE_Fill_Colors");
        if (it != effectInfo.settings.end()) {
            if (it->second == "Rainbow") fillColor = 1;
            else if (it->second == "Palette") fillColor = 2;
        }

        // Mirror wave
        bool mirrorWave = false;
        it = effectInfo.settings.find("E_CHECKBOX_Wave_Mirror");
        if (it != effectInfo.settings.end())
            mirrorWave = (it->second == "1");

        // Number of waves (legacy range 180-3600, default 900)
        int numberWaves = 900;
        it = effectInfo.settings.find("E_SLIDER_Number_Waves");
        if (it != effectInfo.settings.end() && !it->second.empty())
            numberWaves = std::atoi(it->second.c_str());
        if (numberWaves == 0) numberWaves = 1;

        // Thickness percentage (0-100, default 5)
        int thicknessWave = 5;
        it = effectInfo.settings.find("E_SLIDER_Wave_Thickness");
        if (it != effectInfo.settings.end() && !it->second.empty())
            thicknessWave = std::atoi(it->second.c_str());
        // Fall back to legacy key name
        if (thicknessWave == 5) {
            it = effectInfo.settings.find("E_SLIDER_Thickness_Percentage");
            if (it != effectInfo.settings.end() && !it->second.empty())
                thicknessWave = std::atoi(it->second.c_str());
        }

        // Wave height (0-100, default 50)
        int waveHeight = 50;
        it = effectInfo.settings.find("E_SLIDER_Wave_Height");
        if (it != effectInfo.settings.end() && !it->second.empty())
            waveHeight = std::atoi(it->second.c_str());

        // Wave speed — post-2022.06 uses E_TEXTCTRL_Wave_Speed (float string),
        // pre-2022.06 used E_SLIDER_Wave_Speed (integer, needs /100 conversion)
        float wspeed = 10.0f;
        it = effectInfo.settings.find("E_TEXTCTRL_Wave_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty()) {
            wspeed = static_cast<float>(std::atof(it->second.c_str()));
        } else {
            it = effectInfo.settings.find("E_SLIDER_Wave_Speed");
            if (it != effectInfo.settings.end() && !it->second.empty())
                wspeed = static_cast<float>(std::atoi(it->second.c_str()));
        }

        // Y offset (-250 to 250, default 0)
        int yoffset = 0;
        it = effectInfo.settings.find("E_SLIDER_Wave_YOffset");
        if (it != effectInfo.settings.end() && !it->second.empty())
            yoffset = std::atoi(it->second.c_str());

        // Wave direction
        bool waveDirection = false; // false = Right to Left (default)
        it = effectInfo.settings.find("E_CHOICE_Wave_Direction");
        if (it != effectInfo.settings.end())
            waveDirection = (it->second == "Left to Right");

        // Computed values
        double waveYOffset = (buf.BufferHt / 2.0) * (yoffset * 0.01);
        int roundedWaveYOffset = static_cast<int>(std::round(waveYOffset));

        static const double pi_180 = 0.01745329;

        HSVValue hsv0, hsv1;
        buf.palette.GetHSV(0, hsv0);
        buf.palette.GetHSV(1, hsv1);

        // Render cache for ivy/fractal wave buffer
        struct WaveCache : public EffectRenderCache {
            std::vector<int> WaveBuffer;
        };

        WaveCache* cache = dynamic_cast<WaveCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new WaveCache();
            buf.infoCache[0] = cache;
        }
        std::vector<int>& waveBuffer0 = cache->WaveBuffer;

        float state = static_cast<float>(buf.curPeriod - buf.curEffStartPer)
                      * wspeed
                      * (static_cast<float>(buf.frameTimeInMs) / 50.0f);

        double yc = buf.BufferHt / 2.0;
        double r = yc;

        if (waveType == WAVETYPE_DECAYSINE) {
            r -= state / 4.0;
            if (r < 0) r = 0;
        } else if (waveType == WAVETYPE_IVYFRACTAL) {
            if (buf.needToInit || (static_cast<int>(waveBuffer0.size()) != numberWaves * buf.BufferWi)) {
                r = 0;
                int delay = 0;
                int delta = 0;
                waveBuffer0.resize(numberWaves * buf.BufferWi);
                for (int x1 = 0; x1 < numberWaves * buf.BufferWi; ++x1) {
                    waveBuffer0[x1] = (delay-- > 0) ? waveBuffer0[x1 - 1] + delta : static_cast<int>(2 * yc);
                    if (waveBuffer0[x1] >= 2 * buf.BufferHt) {
                        delta = -2;
                        waveBuffer0[x1] = 2 * buf.BufferHt - 1;
                        if (delay > 1) delay = 1;
                    }
                    if (waveBuffer0[x1] < 0) {
                        delta = 2;
                        waveBuffer0[x1] = 0;
                        if (delay > 1) delay = 1;
                    }
                    if (delay < 1) {
                        delta = (std::rand() % 7) - 3;
                        delay = 2 + (std::rand() % 3);
                    }
                }
                buf.needToInit = false;
            }
        }

        double degree_per_x = static_cast<double>(numberWaves) / buf.BufferWi;
        HSVValue hsv;
        hsv.saturation = 1.0;
        hsv.value = 1.0;
        hsv.hue = 1.0;
        xlColor color;

        for (int x = 0; x < buf.BufferWi; x++) {
            double degree;
            if (!waveDirection)
                degree = x * degree_per_x + state;
            else
                degree = x * degree_per_x - state;
            double radian = degree * pi_180;

            double degreeMinus1;
            if (!waveDirection)
                degreeMinus1 = (x - 1) * degree_per_x + state;
            else
                degreeMinus1 = (x - 1) * degree_per_x - state;
            double radianMinus1 = degreeMinus1 * pi_180;

            double sinrad = std::sin(radian);
            double sinradMinus1 = std::sin(radianMinus1);

            int ystart;

            if (waveType == WAVETYPE_TRIANGLE) {
                double waves = (static_cast<double>(numberWaves) / 180.0) / 5.0;
                int amp = buf.BufferHt * waveHeight / 100;

                int xx = x;
                if (waveDirection) {
                    xx = buf.BufferWi - x - 1;
                }

                if (amp == 0) {
                    ystart = 0;
                } else {
                    ystart = (buf.BufferHt - amp) / 2
                             + std::abs(static_cast<int>((state / 10 + xx) * waves) % (2 * amp) - amp);
                }
                if (ystart > buf.BufferHt - 1) ystart = buf.BufferHt - 1;
            } else if (waveType == WAVETYPE_IVYFRACTAL) {
                int istate = static_cast<int>(std::round(state));
                int eff_x = (waveDirection ? x : buf.BufferWi - x - 1)
                            + buf.BufferWi * (istate / 2 / buf.BufferWi);
                if (eff_x >= numberWaves * buf.BufferWi) break;
                if (!waveDirection) eff_x = numberWaves * buf.BufferWi - eff_x - 1;
                bool ok = waveDirection
                    ? (eff_x <= istate / 2)
                    : (eff_x >= numberWaves * buf.BufferWi - istate / 2 - 1);
                if (!ok) continue;
                ystart = waveBuffer0[eff_x] / 2;
            } else {
                ystart = static_cast<int>(r * (waveHeight / 100.0) * sinrad + yc);
            }

            if (x >= 0 && x < buf.BufferWi && ystart >= 0 && ystart < buf.BufferHt) {
                int y1 = static_cast<int>(ystart - (r * (thicknessWave / 100.0)));
                int y2 = static_cast<int>(ystart + (r * (thicknessWave / 100.0)));
                if (y2 <= y1) y2 = y1 + 1;

                if (waveType == WAVETYPE_SQUARE) {
                    if (std::signbit(sinrad) != std::signbit(sinradMinus1)) {
                        y1 = static_cast<int>(yc - yc * (waveHeight / 100.0));
                        y2 = static_cast<int>(yc + yc * (waveHeight / 100.0));
                    } else if (sinrad > 0.0) {
                        y1 = static_cast<int>(yc + 1 + yc * (waveHeight / 100.0) * ((100.0 - thicknessWave) / 100.0));
                        y2 = static_cast<int>(yc + yc * (waveHeight / 100.0));
                    } else {
                        y1 = static_cast<int>(yc - yc * (waveHeight / 100.0));
                        y2 = static_cast<int>(yc - yc * (waveHeight / 100.0) * ((100.0 - thicknessWave) / 100.0));
                    }

                    if (y1 < 0) y1 = 0;
                    if (y2 < 1) y2 = 1;
                    if (y1 > buf.BufferHt - 1) y1 = buf.BufferHt - 1;
                    if (y2 > buf.BufferHt) y2 = buf.BufferHt;

                    if (y2 <= y1) {
                        y2 = y1 + 1;
                    }
                }

                int y1mirror = static_cast<int>(yc + (yc - y1));
                int y2mirror = static_cast<int>(yc + (yc - y2));
                double deltay = y2 - y1;
                if (deltay <= 0) deltay = 1;

                for (int y = y1; y <= y2; y++) {
                    int adjustedY = y + roundedWaveYOffset;
                    if (fillColor <= 0) {
                        buf.SetPixel(x, adjustedY, hsv0);
                    } else if (fillColor == 1) {
                        hsv.hue = static_cast<double>(y - y1) / deltay;
                        buf.SetPixel(x, adjustedY, hsv);
                    } else if (fillColor == 2) {
                        double blend = static_cast<double>(y - y1) / deltay;
                        buf.GetMultiColorBlend(static_cast<float>(blend), false, color);
                        buf.SetPixel(x, adjustedY, color);
                    }
                }

                if (mirrorWave) {
                    if (y1mirror < y2mirror) {
                        y1 = y1mirror;
                        y2 = y2mirror;
                    } else {
                        y2 = y1mirror;
                        y1 = y2mirror;
                    }

                    for (int y = y1; y <= y2; y++) {
                        int adjustedY = y + roundedWaveYOffset;
                        if (fillColor <= 0) {
                            buf.SetPixel(x, adjustedY, hsv0);
                        } else if (fillColor == 1) {
                            hsv.hue = static_cast<double>(y - y1) / deltay;
                            buf.SetPixel(x, adjustedY, hsv);
                        } else if (fillColor == 2) {
                            double blend = static_cast<double>(y - y1) / deltay;
                            buf.GetMultiColorBlend(static_cast<float>(blend), false, color);
                            buf.SetPixel(x, adjustedY, color);
                        }
                    }
                }
            }
        }
        return true;
    }



    // --- warp effect ---
    // TODO: Warp needs DissolveTransitonPattern data and lambda ternary fixes
#if 0
    if (type == "Warp") {
        // Native Warp effect — pixel warping transforms applied to existing buffer contents.
        // Warp operates in canvas mode: it reads the current pixels (composited from layers
        // below) and applies spatial transforms (ripple, swirl, dissolve, etc.).

        // --- Read settings ---
        std::string warpTypeStr = "water drops";
        auto it = effectInfo.settings.find("E_CHOICE_Warp_Type");
        if (it != effectInfo.settings.end() && !it->second.empty())
            warpTypeStr = it->second;

        // Treatment key: native panel uses E_CHOICE_Warp_Treatment,
        // but legacy XML stores E_CHOICE_Warp_Treatment_APPLYLAST
        std::string warpTreatment = "constant";
        it = effectInfo.settings.find("E_CHOICE_Warp_Treatment_APPLYLAST");
        if (it != effectInfo.settings.end() && !it->second.empty())
            warpTreatment = it->second;
        else {
            it = effectInfo.settings.find("E_CHOICE_Warp_Treatment");
            if (it != effectInfo.settings.end() && !it->second.empty())
                warpTreatment = it->second;
        }

        int xPct = 50, yPct = 50;
        it = effectInfo.settings.find("E_SLIDER_Warp_X");
        if (it != effectInfo.settings.end() && !it->second.empty())
            xPct = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Warp_Y");
        if (it != effectInfo.settings.end() && !it->second.empty())
            yPct = std::atoi(it->second.c_str());

        int cycleCount = 1;
        it = effectInfo.settings.find("E_SLIDER_Warp_Cycle_Count");
        if (it != effectInfo.settings.end() && !it->second.empty())
            cycleCount = std::atoi(it->second.c_str());
        if (cycleCount < 1) cycleCount = 1;

        float speed = 20.0f;
        it = effectInfo.settings.find("E_SLIDER_Warp_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            speed = static_cast<float>(std::atof(it->second.c_str()));

        float frequency = 20.0f;
        it = effectInfo.settings.find("E_SLIDER_Warp_Frequency");
        if (it != effectInfo.settings.end() && !it->second.empty())
            frequency = static_cast<float>(std::atof(it->second.c_str()));

        float progress = buf.GetEffectTimeIntervalPosition(1.0f);
        double x = 0.01 * xPct;
        double y = 0.01 * yPct;

        // --- Vec2D helper ---
        struct Vec2D {
            double x, y;
            Vec2D(double ix = 0., double iy = 0.) : x(ix), y(iy) {}
            Vec2D operator+(const Vec2D& p) const { return {x + p.x, y + p.y}; }
            Vec2D operator-(const Vec2D& p) const { return {x - p.x, y - p.y}; }
            Vec2D operator*(double k) const { return {x * k, y * k}; }
            Vec2D operator*(const Vec2D& p) const { return {x * p.x, y * p.y}; }
            Vec2D operator/(double k) const { return *this * (1.0 / k); }
            Vec2D operator-() const { return {-x, -y}; }
            double Len2() const { return x * x + y * y; }
            double Len() const { return std::sqrt(Len2()); }
            Vec2D Norm() const { return Len() > 0 ? *this / Len() : Vec2D(0, 0); }
            Vec2D Rotate(double angle) const {
                float cs = NativeRenderBuffer::cos(angle);
                float sn = NativeRenderBuffer::sin(angle);
                return {x * cs + y * sn, -x * sn + y * cs};
            }
            static Vec2D lerp(const Vec2D& a, const Vec2D& b, double t) {
                return {a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)};
            }
        };

        auto vdot = [](const Vec2D& a, const Vec2D& b) -> double {
            return a.x * b.x + a.y * b.y;
        };
        auto vscale = [](double k, const Vec2D& v) -> Vec2D {
            return {k * v.x, k * v.y};
        };
        auto vsub = [](double a, const Vec2D& b) -> Vec2D {
            return {a - b.x, a - b.y};
        };

        // --- ColorBuffer: snapshot of current pixels for read-back ---
        struct ColorBuffer {
            const xlColor* data;
            int w, h;
            xlColor GetPixel(int px, int py) const {
                return (px >= 0 && px < w && py >= 0 && py < h)
                           ? data[py * w + px]
                           : xlBLACK;
            }
        };

        // Take a copy of the current pixels as source
        xlColorVector srcPixels(buf.GetPixels(),
                                buf.GetPixels() + buf.GetPixelCount());
        ColorBuffer cb{srcPixels.data(), buf.BufferWi, buf.BufferHt};

        auto clamp01 = [](double v) -> double {
            return std::min(1.0, std::max(0.0, v));
        };

        // Texture sampling with clamped coords
        auto tex2D = [&](const ColorBuffer& c, double s, double t) -> xlColor {
            s = clamp01(s);
            t = clamp01(t);
            int px = static_cast<int>(s * (c.w - 1));
            int py = static_cast<int>(t * (c.h - 1));
            return c.GetPixel(px, py);
        };

        // Texture sampling with border color for out-of-bounds
        auto tex2DBorder = [&](const ColorBuffer& c, double s, double t,
                               const xlColor& border) -> xlColor {
            if (s < 0. || s > 1. || t < 0. || t > 1.)
                return border;
            int px = static_cast<int>(s * (c.w - 1));
            int py = static_cast<int>(t * (c.h - 1));
            return c.GetPixel(px, py);
        };

        // Dissolve pattern sampling
        auto dissolveTex = [&](double s, double t) -> xlColor {
            const unsigned char* data = DissolveTransitonPattern;
            s = clamp01(s);
            t = clamp01(t);
            int px = static_cast<int>(s * (DissolvePatternWidth - 1));
            int py = static_cast<int>(t * (DissolvePatternHeight - 1));
            const unsigned char* val = data + py * DissolvePatternWidth + px;
            return xlColor(*val, *val, *val);
        };

        // Noise helpers for wavy effect
        auto noiseVec = [&](const Vec2D& p) -> Vec2D {
            xlColor nc = dissolveTex(p.x, p.y);
            double c = nc.red / 255.0;
            return {c, c};
        };

        auto noise = [&](const Vec2D& p) -> double {
            Vec2D i, f;
            f.x = std::modf(p.x, &i.x);
            f.y = std::modf(p.y, &i.y);
            Vec2D u = f * f * (vsub(3.0, f * 2.0));

            Vec2D aa = noiseVec(i);
            Vec2D bb = f;
            Vec2D cc = noiseVec(i + Vec2D(1, 0));
            Vec2D dd = f - Vec2D(1, 0);
            Vec2D ee = noiseVec(i + Vec2D(0, 1));
            Vec2D ff = f - Vec2D(0, 1);
            Vec2D gg = noiseVec(i + Vec2D(1, 1));
            Vec2D hh = f - Vec2D(1, 1);

            double ab = vdot(aa, bb);
            double cd = vdot(cc, dd);
            double ef = vdot(ee, ff);
            double gh = vdot(gg, hh);

            auto lerp = [](double a, double b, double t) { return a + t * (b - a); };
            return lerp(lerp(ab, cd, u.x), lerp(ef, gh, u.x), u.y);
        };

        // Color lerp
        auto colorLerp = [](const xlColor& a, const xlColor& b,
                            double t) -> xlColor {
            return xlColor(
                static_cast<uint8_t>(a.red + t * (b.red - a.red)),
                static_cast<uint8_t>(a.green + t * (b.green - a.green)),
                static_cast<uint8_t>(a.blue + t * (b.blue - a.blue)));
        };

        // Linear interpolation
        auto lerp = [](double a, double b, double t) -> double {
            return a + t * (b - a);
        };

        // Warp params struct
        struct WarpParams {
            float progress;
            Vec2D xy;
            float speed;
            float frequency;
        };
        WarpParams params{progress, Vec2D(x, y), speed, frequency};

        // --- Map warp type string to enum ---
        enum WarpType {
            WT_WATER_DROPS, WT_SINGLE_WATER_DROP, WT_CIRCLE_REVEAL,
            WT_BANDED_SWIRL, WT_CIRCULAR_SWIRL, WT_DISSOLVE,
            WT_RIPPLE, WT_DROP, WT_WAVY, WT_SAMPLE_ON,
            WT_MIRROR, WT_COPY, WT_FLIP
        };

        auto mapType = [](const std::string& s) -> WarpType {
            if (s == "water drops")       return WT_WATER_DROPS;
            if (s == "single water drop") return WT_SINGLE_WATER_DROP;
            if (s == "circle reveal")     return WT_CIRCLE_REVEAL;
            if (s == "banded swirl")      return WT_BANDED_SWIRL;
            if (s == "circular swirl")    return WT_CIRCULAR_SWIRL;
            if (s == "dissolve")          return WT_DISSOLVE;
            if (s == "ripple")            return WT_RIPPLE;
            if (s == "drop")             return WT_DROP;
            if (s == "wavy")             return WT_WAVY;
            if (s == "sample on")        return WT_SAMPLE_ON;
            if (s == "mirror")           return WT_MIRROR;
            if (s == "flip")             return WT_FLIP;
            return WT_COPY;
        };
        WarpType warpType = mapType(warpTypeStr);

        // --- Pixel transform functions ---
        // Each returns the warped color for a given (s,t) in [0,1]

        auto genWave = [&](float len, float spd, float time) -> float {
            float wave = NativeRenderBuffer::sin(spd * static_cast<float>(M_PI) * len + time);
            wave = (wave + 1.0f) * 0.5f;
            wave -= 0.3f;
            wave *= wave * wave;
            return wave;
        };

        auto waterDrops = [&](double s, double t) -> xlColor {
            float time = -params.progress * 35.0f;
            Vec2D pos2 = Vec2D(s, t) - params.xy;
            Vec2D pos2n = pos2.Norm();
            double len = pos2.Len();
            float wave = genWave(static_cast<float>(len), params.speed, time);
            Vec2D uv2 = vscale(-1.0, pos2n) * (wave / (1.0 + 5.0 * len));
            return tex2D(cb, s + uv2.x, t + uv2.y);
        };

        auto rippleIn = [&](double s, double t) -> xlColor {
            const double amplitude = 0.15;
            Vec2D toUV(s - params.xy.x, t - params.xy.y);
            double dist = toUV.Len();
            Vec2D normToUV = toUV / dist;
            double wave = NativeRenderBuffer::cos(
                params.frequency * static_cast<float>(dist) -
                params.speed * params.progress);
            double offset = params.progress * wave * amplitude;
            Vec2D newUV = params.xy + normToUV * (dist + offset);
            xlColor c1 = tex2D(cb, s, t);
            xlColor c2 = tex2D(cb, newUV.x, newUV.y);
            return colorLerp(c2, c1, params.progress);
        };

        auto rippleOut = [&](double s, double t) -> xlColor {
            const double amplitude = 0.15;
            Vec2D toUV(s - params.xy.x, t - params.xy.y);
            double dist = toUV.Len();
            Vec2D normToUV = toUV / dist;
            double wave = NativeRenderBuffer::cos(
                params.frequency * static_cast<float>(dist) -
                params.speed * params.progress);
            double offset = params.progress * wave * amplitude;
            Vec2D newUV = params.xy + normToUV * (dist + offset);
            xlColor c1 = tex2D(cb, s, t);
            xlColor c2 = tex2D(cb, newUV.x, newUV.y);
            return colorLerp(c1, c2, params.progress);
        };

        auto dissolveIn = [&](double s, double t) -> xlColor {
            xlColor dc = dissolveTex(s, t);
            unsigned char byteProgress = static_cast<unsigned char>(255 * params.progress);
            return (dc.red <= byteProgress) ? tex2D(cb, s, t) : xlBLACK;
        };

        auto dissolveOut = [&](double s, double t) -> xlColor {
            xlColor dc = dissolveTex(s, t);
            unsigned char byteProgress = static_cast<unsigned char>(255 * params.progress);
            return (dc.red > byteProgress) ? tex2D(cb, s, t) : xlBLACK;
        };

        auto circleRevealIn = [&](double s, double t) -> xlColor {
            const float fuzzy = 0.04f;
            const float circleSize = 0.60f;
            float radius = -fuzzy + params.progress * (circleSize + 2.0f * fuzzy);
            float fromCenter = static_cast<float>((Vec2D(s, t) - params.xy).Len());
            float distFromCircle = fromCenter - radius;
            xlColor c = tex2D(cb, s, t);
            float p = std::min(std::max((distFromCircle + fuzzy) / (2.0f * fuzzy), 0.0f), 1.0f);
            return colorLerp(c, xlBLACK, p);
        };

        auto circleRevealOut = [&](double s, double t) -> xlColor {
            const float fuzzy = 0.04f;
            const float circleSize = 0.60f;
            float radius = -fuzzy + (1.0f - params.progress) * (circleSize + 2.0f * fuzzy);
            float fromCenter = static_cast<float>((Vec2D(s, t) - params.xy).Len());
            float distFromCircle = fromCenter - radius;
            xlColor c = tex2D(cb, s, t);
            float p = std::min(std::max((distFromCircle + fuzzy) / (2.0f * fuzzy), 0.0f), 1.0f);
            return colorLerp(c, xlBLACK, p);
        };

        auto bandedSwirlIn = [&](double s, double t) -> xlColor {
            const double twistAmount = 1.6;
            Vec2D toUV = Vec2D(s, t) - params.xy;
            double dist = toUV.Len();
            Vec2D normToUV = toUV / dist;
            float angle = std::atan2(static_cast<float>(normToUV.y),
                                     static_cast<float>(normToUV.x));
            angle += NativeRenderBuffer::sin(static_cast<float>(dist) * params.frequency) *
                     static_cast<float>(twistAmount) * (1.0f - params.progress);
            Vec2D newUV(NativeRenderBuffer::cos(angle), NativeRenderBuffer::sin(angle));
            newUV = newUV * dist + params.xy;
            xlColor c1 = tex2D(cb, s, t);
            xlColor c2 = tex2D(cb, newUV.x, newUV.y);
            return colorLerp(c1, c2, params.progress);
        };

        auto bandedSwirlOut = [&](double s, double t) -> xlColor {
            const double twistAmount = 1.6;
            Vec2D toUV = Vec2D(s, t) - params.xy;
            double dist = toUV.Len();
            Vec2D normToUV = toUV / dist;
            float angle = std::atan2(static_cast<float>(normToUV.y),
                                     static_cast<float>(normToUV.x));
            angle += NativeRenderBuffer::sin(static_cast<float>(dist) * params.frequency) *
                     static_cast<float>(twistAmount) * params.progress;
            Vec2D newUV(NativeRenderBuffer::cos(angle), NativeRenderBuffer::sin(angle));
            newUV = newUV * dist + params.xy;
            xlColor c1 = tex2D(cb, s, t);
            xlColor c2 = tex2D(cb, newUV.x, newUV.y);
            return colorLerp(c2, c1, params.progress);
        };

        auto circularSwirl = [&](double s, double t) -> xlColor {
            Vec2D uv(s, t);
            Vec2D dir = uv - params.xy;
            double len = dir.Len();
            double radius = (1.0 - params.progress) * 0.70710678;
            if (len < radius) {
                Vec2D rotated = dir.Rotate(
                    -params.speed * len * params.progress * static_cast<float>(M_PI));
                Vec2D scaled = rotated * (1.0 - params.progress) + params.xy;
                Vec2D newUV = Vec2D::lerp(params.xy, scaled, 1.0 - params.progress);
                return tex2D(cb, newUV.x, newUV.y);
            }
            return xlBLACK;
        };

        auto drop = [&](double s, double t) -> xlColor {
            const double notSoRandomY = 0.16;
            float noiseVal = dissolveTex(s, notSoRandomY).red / 255.0f;
            return tex2D(cb, s, t + noiseVal * params.progress);
        };

        auto getDropletHeight = [&](const Vec2D& uv, const Vec2D& dropPos,
                                    float time) -> float {
            const float expandSpeed = 1.5f;
            const float heightFactor = 0.3f;
            const float ripple = 60.0f;
            float decayRate = 0.5f;
            float dropletStrength = 1.0f;
            float dropletStrengthBias = 0.6f;
            float dropFraction = time / decayRate;
            float dummy;
            dropFraction = std::modf(dropFraction, &dummy);
            float ringRadius = expandSpeed * dropFraction * dropletStrength - dropletStrengthBias;
            float distToDroplet = static_cast<float>((uv - dropPos).Len());
            float dropletH = distToDroplet > ringRadius ? 0.0f : distToDroplet;
            dropletH = NativeRenderBuffer::cos(
                           static_cast<float>(M_PI) +
                           (dropletH - ringRadius) * ripple * dropletStrength) *
                           0.5f + 0.5f;
            dropletH *= 1.0f - dropFraction;
            dropletH *= distToDroplet > ringRadius ? 0.0f : distToDroplet / ringRadius;
            return (1.0f - (NativeRenderBuffer::cos(dropletH * static_cast<float>(M_PI)) + 1.0f) * 0.5f) * heightFactor;
        };

        auto singleWaterDrop = [&](double s, double t) -> xlColor {
            Vec2D uv(s, t);
            Vec2D pos2 = uv - params.xy;
            Vec2D pos2n = pos2.Norm();
            float dh = getDropletHeight(
                uv - Vec2D(0.5, 0.5), params.xy - Vec2D(0.5, 0.5), params.progress);
            Vec2D uv2 = vscale(-1.0, pos2n) * (dh / (1.0 + 3.0 * pos2.Len()));
            return tex2D(cb, uv.x + uv2.x, uv.y + uv2.y);
        };

        auto mirror = [&](double s, double t) -> xlColor {
            Vec2D pos2(s, t);
            if (s > params.xy.x)
                pos2.x = 2.0 * params.xy.x - s;
            if (t > params.xy.y)
                pos2.y = 2.0 * params.xy.y - t;
            return tex2DBorder(cb, pos2.x, pos2.y, xlBLACK);
        };

        auto copy = [&](double s, double t) -> xlColor {
            Vec2D pos2(s, t);
            if (pos2.x > params.xy.x) pos2.x -= params.xy.x;
            if (pos2.y > params.xy.y) pos2.y -= params.xy.y;
            return tex2DBorder(cb, pos2.x, pos2.y, xlBLACK);
        };

        auto flip = [&](double s, double t) -> xlColor {
            int fx = static_cast<int>(s * (cb.w - 1));
            if (s <= params.xy.x && params.xy.x != 0)
                fx = static_cast<int>((1.0 - s) * (cb.w - 1));
            int fy = static_cast<int>(t * (cb.h - 1));
            if (t <= params.xy.y && params.xy.y != 0)
                fy = static_cast<int>((1.0 - t) * (cb.h - 1));
            return cb.GetPixel(fx, fy);
        };

        auto wavy = [&](double s, double t) -> xlColor {
            Vec2D uv(s, t);
            double time = params.speed * params.progress;
            uv.x += 0.4 * noise(Vec2D(time, 0) + uv * 0.3);
            uv.y += 0.5 * noise(Vec2D(time, 0) + uv * 0.5);
            return tex2DBorder(cb, uv.x, uv.y, xlBLACK);
        };

        auto sampleOn = [&]() {
            int xx = static_cast<int>(x * (buf.BufferWi - 1));
            int yy = static_cast<int>(y * (buf.BufferHt - 1));
            xlColor c = cb.GetPixel(xx, yy);
            buf.Fill(c);
        };

        // Pixel transform function type
        using PixelXform = std::function<xlColor(double, double)>;
        auto renderTransform = [&](PixelXform xform) {
            for (int py = 0; py < buf.BufferHt; ++py) {
                double t = (buf.BufferHt > 1)
                               ? static_cast<double>(py) / (buf.BufferHt - 1)
                               : 0.0;
                for (int px = 0; px < buf.BufferWi; ++px) {
                    double s = (buf.BufferWi > 1)
                                   ? static_cast<double>(px) / (buf.BufferWi - 1)
                                   : 0.0;
                    buf.SetPixel(px, py, xform(s, t));
                }
            }
        };

        // --- Dispatch by warp type ---

        if (warpType == WT_WATER_DROPS) {
            renderTransform(waterDrops);
        } else if (warpType == WT_SAMPLE_ON) {
            sampleOn();
        } else if (warpType == WT_WAVY) {
            // Remap speed: legacy uses interpolate(speed, 0,0.5, 40,5)
            if (speed > 0.0f)
                params.speed = static_cast<float>(0.5 + (5.0 - 0.5) * (speed / 40.0));
            else
                params.speed = 0.5f;
            renderTransform(wavy);
        } else if (warpType == WT_MIRROR) {
            renderTransform(mirror);
        } else if (warpType == WT_COPY) {
            renderTransform(copy);
        } else if (warpType == WT_FLIP) {
            renderTransform(flip);
        } else if (warpType == WT_SINGLE_WATER_DROP) {
            float intervalLen = 1.0f / static_cast<float>(cycleCount);
            float scaledProgress = progress / intervalLen;
            float intervalProgress, intervalIndex;
            intervalProgress = std::modf(scaledProgress, &intervalIndex);
            // Remap: interpolate(intervalProgress, 0,0.20, 1,0.45)
            float interp = 0.20f + (0.45f - 0.20f) * intervalProgress;
            params.progress = interp;
            renderTransform(singleWaterDrop);
        } else {
            // Transition-style warps: ripple, dissolve, banded swirl,
            // circle reveal, circular swirl, drop
            PixelXform xform = nullptr;

            if (warpTreatment == "constant") {
                // Cycle between [0,1] and [1,0]
                float intervalLen = 1.0f / (2.0f * cycleCount);
                float scaledProgress = progress / intervalLen;
                float intervalProgress, intervalIndex;
                intervalProgress = std::modf(scaledProgress, &intervalIndex);
                if (static_cast<int>(intervalIndex) % 2)
                    intervalProgress = 1.0f - intervalProgress;
                params.progress = intervalProgress;

                if (warpType == WT_RIPPLE)
                    xform = rippleIn;
                else if (warpType == WT_DISSOLVE)
                    xform = dissolveIn;
                else if (warpType == WT_BANDED_SWIRL)
                    xform = bandedSwirlIn;
                else if (warpType == WT_CIRCLE_REVEAL)
                    xform = circleRevealIn;
                else if (warpType == WT_CIRCULAR_SWIRL) {
                    params.progress = 1.0f - params.progress;
                    xform = circularSwirl;
                } else if (warpType == WT_DROP) {
                    params.progress = 1.0f - params.progress;
                    xform = drop;
                }
            } else {
                // "in" or "out" treatment
                if (warpType == WT_RIPPLE)
                    xform = (warpTreatment == "in") ? rippleIn : rippleOut;
                else if (warpType == WT_DISSOLVE)
                    xform = (warpTreatment == "in") ? dissolveIn : dissolveOut;
                else if (warpType == WT_BANDED_SWIRL)
                    xform = (warpTreatment == "in") ? bandedSwirlIn : bandedSwirlOut;
                else if (warpType == WT_CIRCLE_REVEAL)
                    xform = (warpTreatment == "in") ? circleRevealIn : circleRevealOut;
                else if (warpType == WT_CIRCULAR_SWIRL)
                    xform = circularSwirl;
                else if (warpType == WT_DROP) {
                    xform = drop;
                    if (warpTreatment == "in")
                        params.progress = 1.0f - params.progress;
                }
            }

            // Circular swirl speed remap
            if (warpType == WT_CIRCULAR_SWIRL) {
                params.speed = static_cast<float>(
                    1.0 + (9.0 - 1.0) * (params.speed / 40.0));
                if (warpTreatment == "in")
                    params.progress = 1.0f - params.progress;
            }

            if (xform)
                renderTransform(xform);
        }

        return true;
    }
#endif

    if (type == "Tendril") {
        // Native Tendril effect — port of legacy TendrilEffect::Render
        //
        // Self-contained physics simulation (spring-damped node chains) with
        // line-segment rasterization to the pixel buffer. The legacy effect
        // uses wxGraphicsPath quadratic Bezier curves; here we approximate with
        // connected thick line segments through the nodes, which is visually
        // equivalent at the default node count (60).

        // --- Helper lambdas for reading settings ---
        auto getSetting = [&](const std::string& key) -> std::string {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end()) return it->second;
            return "";
        };

        auto getInt = [&](const std::string& key, int def) -> int {
            std::string v = getSetting(key);
            return v.empty() ? def : std::atoi(v.c_str());
        };

        auto getFloat = [&](const std::string& key, float def) -> float {
            std::string v = getSetting(key);
            return v.empty() ? def : static_cast<float>(std::atof(v.c_str()));
        };

        // --- Read settings ---
        std::string movementStr = "Random";
        {
            std::string v = getSetting("E_CHOICE_Tendril_Movement");
            if (!v.empty()) movementStr = v;
        }

        int tunemovement  = getInt("E_SLIDER_Tendril_TuneMovement", 10);
        int movementSpeed = getInt("E_TEXTCTRL_Tendril_Speed", 10);
        int thickness     = getInt("E_SLIDER_Tendril_Thickness", 1);
        int trails        = getInt("E_TEXTCTRL_Tendril_Trails", 1);
        int length        = getInt("E_TEXTCTRL_Tendril_Length", 60);
        int xoffset       = getInt("E_SLIDER_Tendril_XOffset", 0);
        int yoffset       = getInt("E_SLIDER_Tendril_YOffset", 0);
        int manualx       = getInt("E_SLIDER_Tendril_ManualX", 0);
        int manualy       = getInt("E_SLIDER_Tendril_ManualY", 0);

        // Convert raw UI values to physics parameters (same formulas as legacy)
        float friction  = getFloat("E_TEXTCTRL_Tendril_Friction", 10.0f) / 20.0f * 0.2f + 0.4f;
        float dampening = getFloat("E_TEXTCTRL_Tendril_Dampening", 10.0f) / 20.0f * 0.5f;
        float tension   = getFloat("E_TEXTCTRL_Tendril_Tension", 20.0f) / 39.0f * 0.039f + 0.96f;

        // Clamp physics values
        friction  = std::clamp(friction, 0.4f, 0.6f);
        dampening = std::clamp(dampening, 0.0f, 0.5f);
        tension   = std::clamp(tension, 0.96f, 0.999f);

        if (thickness < 1) thickness = 1;

        // Encode movement string to integer
        int nMovement = 1;
        if      (movementStr == "Random")               nMovement = 1;
        else if (movementStr == "Square")               nMovement = 2;
        else if (movementStr == "Circle")               nMovement = 3;
        else if (movementStr == "Horizontal Zig Zag")   nMovement = 4;
        else if (movementStr == "Vertical Zig Zag")     nMovement = 5;
        else if (movementStr == "Music Line")           nMovement = 6;
        else if (movementStr == "Music Circle")         nMovement = 7;
        else if (movementStr == "Vert. Zig Zag Return") nMovement = 8;
        else if (movementStr == "Horiz. Zig Zag Return") nMovement = 9;
        else if (movementStr == "Manual")               nMovement = 10;

        // --- Inline physics node ---
        struct TNode {
            float x, y, vx, vy;
            TNode(float x_ = 0, float y_ = 0) : x(x_), y(y_), vx(0), vy(0) {}
        };

        // --- Inline single tendril trail ---
        struct Trail {
            float friction;
            float dampening;
            float tension;
            float spring;
            int lastWidth = -1;
            int lastHeight = -1;
            std::vector<TNode> nodes;

            Trail(float fric, int size, float damp, float tens, float spr, float sx, float sy) {
                dampening = (damp >= 0) ? damp : 0.25f;
                tension = (tens >= 0) ? tens : 0.98f;
                spring = (spr >= 0) ? spr : 0.0f;
                if (fric >= 0) {
                    friction = fric + ((float)std::rand() / (float)RAND_MAX) * 0.01f - 0.005f;
                } else {
                    friction = 0.5f + ((float)std::rand() / (float)RAND_MAX) * 0.01f - 0.005f;
                }
                int sz = (size > 0) ? size : 60;
                nodes.resize(sz, TNode(sx, sy));
            }

            void update(float tx, float ty, int tunemov, int width, int height) {
                if (lastWidth == -1) lastWidth = width;
                if (lastHeight == -1) lastHeight = height;

                float sp = spring;
                TNode& head = nodes[0];

                int xSign = (width == lastWidth) ? 0 : ((width - lastWidth) > 0 ? 1 : -1);
                int ySign = (height == lastHeight) ? 0 : ((height - lastHeight) > 0 ? 1 : -1);
                if (head.vx == 0) {
                    head.vx += xSign * (float)(width - lastWidth) * 2.0f * tunemov / 20.0f;
                } else {
                    head.vx *= 1.0f + (float)(width - lastWidth) * 2.0f * tunemov / 20.0f;
                    if (head.vx == 0) head.vx = 0.01f * xSign;
                }
                if (head.vy == 0) {
                    head.vy += ySign * (float)(height - lastHeight) * 2.0f * tunemov / 20.0f;
                } else {
                    head.vy *= 1.0f + (float)(height - lastHeight) * 2.0f * tunemov / 20.0f;
                    if (head.vy == 0) head.vx = 0.01f * ySign;  // legacy uses vx here (matches original)
                }

                head.vx += (tx - head.x) * sp;
                head.vy += (ty - head.y) * sp;

                TNode* prev = nullptr;
                for (auto& node : nodes) {
                    if (prev != nullptr) {
                        node.vx += (prev->x - node.x) * sp;
                        node.vy += (prev->y - node.y) * sp;
                        node.vx += prev->vx * dampening;
                        node.vy += prev->vy * dampening;
                    }
                    node.vx *= friction;
                    node.vy *= friction;
                    node.x += node.vx;
                    node.y += node.vy;
                    node.x = std::clamp(node.x, (float)(-1 * width), (float)(2 * width));
                    node.y = std::clamp(node.y, (float)(-1 * height), (float)(2 * height));
                    prev = &node;
                    sp *= tension;
                }
                lastWidth = width;
                lastHeight = height;
            }

            void draw(NativeRenderBuffer& buf, const xlColor& colour, int thick) {
                if (nodes.size() < 3) return;

                std::vector<std::pair<int,int>> pts;
                pts.reserve(nodes.size());

                pts.push_back({(int)std::round(nodes[0].x), (int)std::round(nodes[0].y)});

                for (size_t i = 1; i + 2 < nodes.size(); i++) {
                    float mx = (nodes[i].x + nodes[i+1].x) * 0.5f;
                    float my = (nodes[i].y + nodes[i+1].y) * 0.5f;
                    pts.push_back({(int)std::round(mx), (int)std::round(my)});
                }

                size_t n = nodes.size();
                pts.push_back({(int)std::round(nodes[n-2].x), (int)std::round(nodes[n-2].y)});
                pts.push_back({(int)std::round(nodes[n-1].x), (int)std::round(nodes[n-1].y)});

                for (size_t i = 0; i + 1 < pts.size(); i++) {
                    if (thick <= 1) {
                        buf.DrawLine(pts[i].first, pts[i].second,
                                     pts[i+1].first, pts[i+1].second, colour);
                    } else {
                        buf.DrawThickLine(pts[i].first, pts[i].second,
                                          pts[i+1].first, pts[i+1].second, colour, thick);
                    }
                }
            }

            std::pair<int,int> lastLocation() const {
                if (!nodes.empty()) {
                    return {(int)std::round(nodes.back().x), (int)std::round(nodes.back().y)};
                }
                return {0, 0};
            }
        };

        // --- Inline tendril group (multiple trails) ---
        struct TendrilGroup {
            std::vector<Trail> trails;

            TendrilGroup(float fric, int numTrails, int size, float damp, float tens,
                         float springBase, float springIncr, float sx, float sy) {
                float sb = (springBase >= 0) ? springBase : 0.45f;
                float si = (springIncr >= 0) ? springIncr : 0.025f;
                int t = (numTrails > 0) ? numTrails : 10;
                trails.reserve(t);
                for (int i = 0; i < t; i++) {
                    float aspring = sb + si * ((float)i / (float)t);
                    trails.emplace_back(fric, size, damp, tens, aspring, sx, sy);
                }
            }

            void update(float tx, float ty, int tunemov, int width, int height) {
                for (auto& tr : trails) {
                    tr.update(tx, ty, tunemov, width, height);
                }
            }

            void updateRandomMove(int tunemov, int width, int height) {
                if (tunemov < 1) tunemov = 1;
                int minx = -1 * width / 4;
                int miny = -1 * height / 4;
                int maxx = width + width / 4;
                int maxy = height + height / 4;
                int minmovex = -1 * width * 2 * tunemov / 20;
                int minmovey = -1 * height * 2 * tunemov / 20;
                int maxmovex = width * 2 * tunemov / 20;
                int maxmovey = height * 2 * tunemov / 20;

                if (trails.empty()) return;
                auto [cx, cy] = trails[0].lastLocation();

                int realminmovex = minmovex;
                if (minmovex < 0) realminmovex = -1 * std::min(cx, minmovex * -1);
                int realmaxmovex = maxmovex;
                if (maxmovex > 0) realmaxmovex = std::min(maxx - cx, maxmovex);
                int realminmovey = minmovey;
                if (minmovey < 0) realminmovey = -1 * std::min(cy, minmovey * -1);
                int realmaxmovey = maxmovey;
                if (maxmovey > 0) realmaxmovey = std::min(maxy - cy, maxmovey);

                int xmove = -1 * realminmovex + realmaxmovex;
                int ymove = -1 * realminmovey + realmaxmovey;
                int dx = (xmove > 0) ? (std::rand() % xmove) + realminmovex : 0;
                int dy = (ymove > 0) ? (std::rand() % ymove) + realminmovey : 0;

                float nx = (float)std::clamp(cx + dx, minx, maxx);
                float ny = (float)std::clamp(cy + dy, miny, maxy);

                update(nx, ny, tunemov, width, height);
            }

            void draw(NativeRenderBuffer& buf, const xlColor& colour, int thick) {
                for (auto& tr : trails) {
                    tr.draw(buf, colour, thick);
                }
            }
        };

        // --- Persistent cache ---
        struct TendrilNativeCache : public EffectRenderCache {
            int mv1 = 0, mv2 = 0, mv3 = 0, mv4 = 0;
            TendrilGroup* tendril = nullptr;

            virtual ~TendrilNativeCache() {
                delete tendril;
                tendril = nullptr;
            }
        };

        TendrilNativeCache* cache = dynamic_cast<TendrilNativeCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new TendrilNativeCache();
            buf.infoCache[0] = cache;
        }

        int& _mv1 = cache->mv1;
        int& _mv2 = cache->mv2;
        int& _mv3 = cache->mv3;
        int& _mv4 = cache->mv4;
        TendrilGroup*& _tendril = cache->tendril;

        // Get blended color from palette
        float oset = buf.GetEffectTimeIntervalPosition();
        xlColor colour;
        buf.GetMultiColorBlend(oset, false, colour);

        int truexoffset = xoffset * buf.BufferWi / 100;
        int trueyoffset = yoffset * buf.BufferHt / 100;

        // --- Initialize or reinitialize tendril ---
        if (_tendril == nullptr || buf.needToInit) {
            buf.needToInit = false;

            float smx = buf.BufferWi / 2.0f + truexoffset / 2.0f;
            float smy = buf.BufferHt / 2.0f + trueyoffset / 2.0f;
            float smbx = buf.BufferWi / 2.0f + truexoffset / 2.0f;
            float smby = (float)trueyoffset;
            float sblx = (float)truexoffset;
            float sbly = (float)trueyoffset;
            float smlx = (float)truexoffset;
            float smly = buf.BufferHt / 2.0f + trueyoffset / 2.0f;

            delete _tendril;
            _tendril = nullptr;

            switch (nMovement) {
            case 1: // random
                _tendril = new TendrilGroup(friction, trails, length, dampening, tension, -1, -1, smx, smy);
                break;
            case 2: // corners
                _mv1 = 0 + truexoffset;
                _mv2 = 0 + trueyoffset;
                _mv3 = 0;
                _mv4 = tunemovement;
                if (_mv4 == 0) _mv4 = 1;
                _tendril = new TendrilGroup(friction, trails, length, dampening, tension, -1, -1, sblx, sbly);
                break;
            case 3: // circles
                _mv1 = 0;
                _mv2 = std::min(buf.BufferWi, buf.BufferHt) / 2;
                _mv3 = tunemovement * 3;
                if (_mv3 == 0) _mv3 = 1;
                _tendril = new TendrilGroup(friction, trails, length, dampening, tension, -1, -1, smx, smy);
                break;
            case 4: // horizontal zig zag
                _mv1 = 0 + trueyoffset;
                _mv2 = (int)((double)tunemovement * 1.5);
                if (_mv2 == 0) _mv2 = 1;
                _mv3 = 1;
                _tendril = new TendrilGroup(friction, trails, length, dampening, tension, -1, -1, smbx, smby);
                break;
            case 5: // vertical zig zag
                _mv1 = 0 + truexoffset;
                _mv2 = (int)((double)tunemovement * 1.5);
                _mv3 = 1;
                _tendril = new TendrilGroup(friction, trails, length, dampening, tension, -1, -1, smlx, smly);
                break;
            case 6: // music line
                _mv1 = 0 + truexoffset;
                _mv3 = tunemovement;
                if (_mv3 < 1) _mv3 = 1;
                _tendril = new TendrilGroup(friction, trails, length, dampening, tension, -1, -1, sblx, sbly);
                break;
            case 7: // music circle
                _mv1 = 0;
                _mv2 = std::min(buf.BufferWi, buf.BufferHt) / 2;
                _mv3 = tunemovement * 3;
                if (_mv3 < 1) _mv3 = 1;
                _tendril = new TendrilGroup(friction, trails, length, dampening, tension, -1, -1, smx, smy);
                break;
            case 9: // horizontal zig zag return
                _mv1 = 0;
                _mv2 = (int)((double)tunemovement * 1.5);
                if (_mv2 == 0) _mv2 = 1;
                _mv3 = 1;
                _tendril = new TendrilGroup(friction, trails, length, dampening, tension, -1, -1, smbx, smby);
                break;
            case 8: // vertical zig zag return
                _mv1 = 0;
                _mv2 = (int)((double)tunemovement * 1.5);
                _mv3 = 1;
                _tendril = new TendrilGroup(friction, trails, length, dampening, tension, -1, -1, smlx, smly);
                break;
            case 10: // manual
                _tendril = new TendrilGroup(friction, trails, length, dampening, tension, -1, -1,
                                            (float)(manualx * buf.BufferWi / 100), (float)(manualy * buf.BufferHt / 100));
                break;
            }
        }

        // Update radius for buffer-size-sensitive movements
        if (nMovement == 3 || nMovement == 7) {
            _mv2 = std::min(buf.BufferWi, buf.BufferHt) / 2;
        }

        // --- Update tendril physics based on movement type ---
        const double PI = 3.141592653589793238463;
        int speed = 10 - movementSpeed;
        if (speed <= 0 || buf.curPeriod % speed == 0) {
            switch (nMovement) {
            case 1: // random
                if (_tendril != nullptr) {
                    _tendril->updateRandomMove(tunemovement, buf.BufferWi, buf.BufferHt);
                }
                break;
            case 2: { // corners (square)
                _mv4 = tunemovement;
                switch (_mv3) {
                case 0:
                    if (_mv4 == 0) _mv4 = 1;
                    _mv1 += std::max(buf.BufferWi / _mv4, 1);
                    if (_mv1 >= buf.BufferWi + truexoffset - buf.BufferWi / _mv4) _mv3++;
                    break;
                case 1:
                    if (_mv4 == 0) _mv4 = 1;
                    _mv2 += std::max(buf.BufferHt / _mv4, 1);
                    if (_mv2 >= buf.BufferHt + trueyoffset - buf.BufferHt / _mv4) _mv3++;
                    break;
                case 2:
                    if (_mv4 == 0) _mv4 = 1;
                    _mv1 -= std::max(buf.BufferWi / _mv4, 1);
                    if (_mv1 <= truexoffset + buf.BufferWi / _mv4) _mv3++;
                    break;
                case 3:
                    if (_mv4 == 0) _mv4 = 1;
                    _mv2 -= std::max(buf.BufferHt / _mv4, 1);
                    if (_mv2 <= trueyoffset + buf.BufferHt / _mv4) _mv3 = 0;
                    break;
                }
                if (_tendril != nullptr) {
                    _tendril->update((float)_mv1, (float)_mv2, tunemovement, buf.BufferWi, buf.BufferHt);
                }
            } break;
            case 3: { // circles
                _mv3 = tunemovement * 3;
                _mv1 = _mv1 + _mv3;
                if (_mv3 > 360) _mv3 = 0;
                float x = (float)(std::sin((double)_mv1 / 360.0 * PI * 2.0) * (double)_mv2 + (double)buf.BufferWi / 2.0 + truexoffset / 2.0);
                float y = (float)(std::cos((double)_mv1 / 360.0 * PI * 2.0) * (double)_mv2 + (double)buf.BufferHt / 2.0 + trueyoffset / 2.0);
                if (_tendril != nullptr) {
                    _tendril->update(x, y, tunemovement, buf.BufferWi, buf.BufferHt);
                }
            } break;
            case 4: { // horizontal zig zag
                _mv2 = (int)((double)tunemovement * 1.5);
                if (_mv2 == 0) _mv2 = 1;
                _mv1 = _mv1 + _mv3;
                float x = (float)(truexoffset + std::sin(std::max((double)buf.BufferHt / (double)_mv2, 0.5) * PI * (double)_mv1 / (double)buf.BufferHt) * (double)buf.BufferWi / 2.0 + (double)buf.BufferWi / 2.0);
                if (_mv1 >= trueyoffset + buf.BufferHt || _mv1 <= 0 + trueyoffset) {
                    _mv3 = _mv3 * -1;
                }
                if (_mv3 < 0) {
                    x = (float)(buf.BufferWi + truexoffset + truexoffset) - x;
                }
                if (_tendril != nullptr) {
                    _tendril->update(x, (float)_mv1, tunemovement, buf.BufferWi, buf.BufferHt);
                }
            } break;
            case 5: { // vertical zig zag
                _mv2 = (int)((double)tunemovement * 1.5);
                _mv1 = _mv1 + _mv3;
                float y = (float)(trueyoffset + std::sin(std::max((double)buf.BufferWi / (double)_mv2, 0.5) * PI * (double)_mv1 / (double)buf.BufferWi) * (double)buf.BufferHt / 2.0 + (double)buf.BufferHt / 2.0);
                if (_mv1 >= truexoffset + buf.BufferWi || _mv1 <= 0 + truexoffset) {
                    _mv3 = _mv3 * -1;
                }
                if (_mv3 < 0) {
                    y = (float)(buf.BufferHt + trueyoffset + trueyoffset) - y;
                }
                if (_tendril != nullptr) {
                    _tendril->update((float)_mv1, y, tunemovement, buf.BufferWi, buf.BufferHt);
                }
            } break;
            case 6: { // music line (audio-reactive, falls back to f=0.1 without audio)
                float f = 0.1f;
                // Audio not available in native coordinator — use default amplitude
                _mv1 = _mv1 + _mv3;
                if ((_mv1 < 0 + truexoffset && _mv3 < 0) || (_mv1 > buf.BufferWi + truexoffset && _mv3 > 0)) {
                    _mv3 = _mv3 * -1;
                }
                if (_tendril != nullptr) {
                    _tendril->update((float)_mv1, (float)(trueyoffset + buf.BufferHt * f),
                                     tunemovement, buf.BufferWi, buf.BufferHt);
                }
            } break;
            case 7: { // music circle (audio-reactive, falls back to f=0.1 without audio)
                _mv3 = tunemovement * 3;
                if (_mv3 < 1) _mv3 = 1;
                float f = 0.1f;
                // Audio not available in native coordinator — use default amplitude
                _mv1 = _mv1 + _mv3;
                if (_mv3 > 360) _mv3 = 0;
                float x = (float)(std::sin((double)_mv1 / 360.0 * PI * 2.0) * (double)_mv2 * f * 2 + (double)buf.BufferWi / 2.0 + truexoffset / 2.0);
                float y = (float)(std::cos((double)_mv1 / 360.0 * PI * 2.0) * (double)_mv2 * f * 2 + (double)buf.BufferHt / 2.0 + trueyoffset / 2.0);
                if (_tendril != nullptr) {
                    _tendril->update(x, y, tunemovement, buf.BufferWi, buf.BufferHt);
                }
            } break;
            case 9: { // horiz zig zag return
                _mv2 = (int)((double)tunemovement * 1.5);
                if (_mv2 == 0) _mv2 = 1;
                _mv1 = _mv1 + _mv3;
                float x = (float)(buf.BufferWi / 2 + truexoffset / 2);
                if (_mv3 > 0) {
                    x = (float)(truexoffset + std::sin(std::max((double)buf.BufferHt / (double)_mv2, 0.5) * PI * (double)_mv1 / (double)buf.BufferHt) * (double)buf.BufferWi / 2.0 + (double)buf.BufferWi / 2.0);
                }
                if (_mv1 >= buf.BufferHt || _mv1 <= 0) {
                    _mv3 = _mv3 * -1;
                }
                if (_tendril != nullptr) {
                    _tendril->update(x, (float)(_mv1 + trueyoffset), tunemovement, buf.BufferWi, buf.BufferHt);
                }
            } break;
            case 8: { // vert zig zag return
                _mv2 = (int)((double)tunemovement * 1.5);
                _mv1 = _mv1 + _mv3;
                float y = (float)(buf.BufferHt / 2 + trueyoffset / 2);
                if (_mv3 > 0) {
                    y = (float)(trueyoffset + std::sin(std::max((double)buf.BufferWi / (double)_mv2, 0.5) * PI * (double)_mv1 / (double)buf.BufferWi) * (double)buf.BufferHt / 2.0 + (double)buf.BufferHt / 2.0);
                }
                if (_mv1 >= buf.BufferWi || _mv1 <= 0) {
                    _mv3 = _mv3 * -1;
                }
                if (_tendril != nullptr) {
                    _tendril->update((float)(_mv1 + truexoffset), y, tunemovement, buf.BufferWi, buf.BufferHt);
                }
            } break;
            case 10: { // manual
                if (_tendril != nullptr) {
                    _tendril->update((float)(manualx * buf.BufferWi / 100 + truexoffset),
                                     (float)(manualy * buf.BufferHt / 100 + trueyoffset),
                                     tunemovement, buf.BufferWi, buf.BufferHt);
                }
            } break;
            }
        }

        // --- Draw tendril to pixel buffer ---
        if (_tendril != nullptr) {
            _tendril->draw(buf, colour, thickness);
        }

        return true;
    }

    if (type == "Shader") {
        // Shader effect stub — GPU pipeline integration required.
        //
        // The Shader effect renders GLSL fragment shaders loaded from .fs files.
        // The legacy implementation uses OpenGL framebuffer objects, compiles
        // shader source at runtime, and passes uniforms for time, resolution,
        // offset, zoom, and custom parameters parsed from JSON in the .fs file.
        //
        // Full native implementation requires Metal compute shader compilation
        // or a Metal-based GLSL transpilation pipeline. Until the GPU render
        // pipeline is integrated, this effect renders as empty (black).
        //
        // Settings read (for future implementation):
        //   E_0FILEPICKERCTRL_IFS     - path to .fs shader file
        //   E_SLIDER_Shader_Speed     - time rate multiplier (-1000..1000, /100)
        //   E_SLIDER_Shader_Offset_X  - horizontal offset (-100..100)
        //   E_SLIDER_Shader_Offset_Y  - vertical offset (-100..100)
        //   E_SLIDER_Shader_Zoom      - zoom level (-100..100)
        //   TEXTCTRL_Shader_LeadIn    - lead-in frames before effect start
        //   Plus dynamic per-shader parameters (SHADERXYZZY_*) parsed from
        //   the shader file's JSON configuration block.

        // Read settings for diagnostic/logging purposes
        std::string shaderFile;
        auto it = effectInfo.settings.find("E_0FILEPICKERCTRL_IFS");
        if (it != effectInfo.settings.end())
            shaderFile = it->second;

        int speed = 100;
        it = effectInfo.settings.find("E_SLIDER_Shader_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            speed = std::atoi(it->second.c_str());

        int offsetX = 0;
        it = effectInfo.settings.find("E_SLIDER_Shader_Offset_X");
        if (it != effectInfo.settings.end() && !it->second.empty())
            offsetX = std::atoi(it->second.c_str());

        int offsetY = 0;
        it = effectInfo.settings.find("E_SLIDER_Shader_Offset_Y");
        if (it != effectInfo.settings.end() && !it->second.empty())
            offsetY = std::atoi(it->second.c_str());

        int zoom = 0;
        it = effectInfo.settings.find("E_SLIDER_Shader_Zoom");
        if (it != effectInfo.settings.end() && !it->second.empty())
            zoom = std::atoi(it->second.c_str());

        // Suppress unused variable warnings
        (void)shaderFile;
        (void)speed;
        (void)offsetX;
        (void)offsetY;
        (void)zoom;

        // Placeholder: leave buffer black (cleared state).
        // Actual rendering requires GPU pipeline integration with either:
        //   1. Metal compute shader transpilation from GLSL source, or
        //   2. MoltenVK/SPIRV-Cross pipeline for .fs shader execution
        return true;
    }

    if (type == "Text") {
        // Native Text effect — port of legacy TextEffect::Render (OS Font path)
        //
        // Renders text using NativeTextDrawingContext (CoreText/CoreGraphics).
        // Supports: text content, font selection, movement directions, speed,
        // centering, start/end position offsets, vertical text, rotation,
        // multi-color per-character/per-word, and newline support.
        //
        // Not yet implemented: countdown modes, lyric tracks, file-based text,
        // xLights custom bitmap fonts (CHOICE_Text_Font != "Use OS Fonts"),
        // wavey direction, word-flip direction.

        // --- Read settings ---
        std::string text;
        auto it = effectInfo.settings.find("E_TEXTCTRL_Text");
        if (it != effectInfo.settings.end()) text = it->second;

        // Skip xLights bitmap fonts — only handle OS fonts
        std::string xlFont = "Use OS Fonts";
        it = effectInfo.settings.find("E_CHOICE_Text_Font");
        if (it != effectInfo.settings.end() && !it->second.empty())
            xlFont = it->second;
        if (xlFont != "Use OS Fonts") {
            // xLights bitmap fonts not supported in native build
            return true;
        }

        // Replace literal \n with actual newlines
        {
            std::string::size_type pos = 0;
            while ((pos = text.find("\\n", pos)) != std::string::npos) {
                text.replace(pos, 2, "\n");
                pos += 1;
            }
        }

        if (text.empty()) return true;

        // Font string parsing: wxWidgets NativeFontInfoUserDesc format
        // macOS format: "FaceName [Bold] [Italic] Size" e.g. "Arial Bold 12"
        std::string fontString;
        it = effectInfo.settings.find("E_FONTPICKER_Text_Font");
        if (it != effectInfo.settings.end()) fontString = it->second;

        std::string fontName = "Helvetica";
        float fontSize = 12.0f;
        bool fontBold = false;
        bool fontItalic = false;

        if (!fontString.empty()) {
            // Parse the wx font description string
            // Format examples: "Arial 12", "Arial Bold 12", "Arial Bold Italic 12",
            //                  "Courier New 20", ".AppleSystemUIFont 14"
            // Strategy: last token is size, check for Bold/Italic keywords,
            // remaining tokens form the face name.
            std::vector<std::string> tokens;
            std::istringstream iss(fontString);
            std::string token;
            while (iss >> token) tokens.push_back(token);

            if (!tokens.empty()) {
                // Try to parse the last token as size
                float parsedSize = 0;
                try { parsedSize = std::stof(tokens.back()); } catch (...) {}

                if (parsedSize > 0) {
                    fontSize = parsedSize;
                    tokens.pop_back();
                }

                // Check for Bold/Italic modifiers (case-insensitive)
                auto isModifier = [](const std::string& s) -> int {
                    std::string lower = s;
                    for (auto& c : lower) c = std::tolower(c);
                    if (lower == "bold") return 1;
                    if (lower == "italic" || lower == "oblique" || lower == "slant") return 2;
                    return 0;
                };

                // Remove modifier tokens from end
                while (!tokens.empty()) {
                    int mod = isModifier(tokens.back());
                    if (mod == 1) { fontBold = true; tokens.pop_back(); }
                    else if (mod == 2) { fontItalic = true; tokens.pop_back(); }
                    else break;
                }

                // Remaining tokens form the face name
                if (!tokens.empty()) {
                    fontName.clear();
                    for (size_t i = 0; i < tokens.size(); i++) {
                        if (i > 0) fontName += " ";
                        fontName += tokens[i];
                    }
                }
            }
        }

        // Direction
        enum { DIR_LEFT, DIR_RIGHT, DIR_UP, DIR_DOWN, DIR_NONE,
               DIR_UPLEFT, DIR_DOWNLEFT, DIR_UPRIGHT, DIR_DOWNRIGHT,
               DIR_WAVEY, DIR_VECTOR, DIR_WORDFLIP, DIR_LEFTRIGHT, DIR_UPDOWN };
        int dir = DIR_NONE;
        it = effectInfo.settings.find("E_CHOICE_Text_Dir");
        if (it != effectInfo.settings.end()) {
            const std::string& d = it->second;
            if (d == "left") dir = DIR_LEFT;
            else if (d == "right") dir = DIR_RIGHT;
            else if (d == "up") dir = DIR_UP;
            else if (d == "down") dir = DIR_DOWN;
            else if (d == "up-left") dir = DIR_UPLEFT;
            else if (d == "down-left") dir = DIR_DOWNLEFT;
            else if (d == "up-right") dir = DIR_UPRIGHT;
            else if (d == "down-right") dir = DIR_DOWNRIGHT;
            else if (d == "wavey") dir = DIR_WAVEY;
            else if (d == "vector") dir = DIR_VECTOR;
            else if (d == "word-flip") dir = DIR_WORDFLIP;
            else if (d == "left-right") dir = DIR_LEFTRIGHT;
            else if (d == "up-down") dir = DIR_UPDOWN;
        }

        int tspeed = 10;
        it = effectInfo.settings.find("E_TEXTCTRL_Text_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            tspeed = std::atoi(it->second.c_str());

        bool center = false;
        it = effectInfo.settings.find("E_CHECKBOX_TextToCenter");
        if (it != effectInfo.settings.end()) center = (it->second == "1");

        bool norepeat = false;
        it = effectInfo.settings.find("E_CHECKBOX_TextNoRepeat");
        if (it != effectInfo.settings.end()) norepeat = (it->second == "1");

        bool pixelOffsets = false;
        it = effectInfo.settings.find("E_CHECKBOX_Text_PixelOffsets");
        if (it != effectInfo.settings.end()) pixelOffsets = (it->second == "1");

        bool perWord = false;
        it = effectInfo.settings.find("E_CHECKBOX_Text_Color_PerWord");
        if (it != effectInfo.settings.end()) perWord = (it->second == "1");

        int startx = 0, starty = 0, endx = 0, endy = 0;
        it = effectInfo.settings.find("E_SLIDER_Text_XStart");
        if (it != effectInfo.settings.end() && !it->second.empty()) startx = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Text_YStart");
        if (it != effectInfo.settings.end() && !it->second.empty()) starty = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Text_XEnd");
        if (it != effectInfo.settings.end() && !it->second.empty()) endx = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Text_YEnd");
        if (it != effectInfo.settings.end() && !it->second.empty()) endy = std::atoi(it->second.c_str());

        // Text effect type (normal, vert up, vert down, rotate)
        int textEffect = 0;
        it = effectInfo.settings.find("E_CHOICE_Text_Effect");
        if (it != effectInfo.settings.end()) {
            const std::string& e = it->second;
            if (e == "vert text up") textEffect = 1;
            else if (e == "vert text down") textEffect = 2;
            else if (e == "rotate up 45") textEffect = 3;
            else if (e == "rotate up 90") textEffect = 4;
            else if (e == "rotate down 45") textEffect = 5;
            else if (e == "rotate down 90") textEffect = 6;
        }

        // Apply vertical text transformation
        std::string msg = text;
        if (textEffect == 1) {
            // vertical text up: reverse characters, each on its own line
            std::string result;
            for (int i = (int)msg.size() - 1; i >= 0; i--) {
                result += msg[i];
                result += '\n';
            }
            msg = result;
        } else if (textEffect == 2) {
            // vertical text down: each character on its own line
            std::string result;
            for (size_t i = 0; i < msg.size(); i++) {
                result += msg[i];
                result += '\n';
            }
            msg = result;
        }

        // Word-flip: select one word based on position in effect
        if (dir == DIR_WORDFLIP && !msg.empty()) {
            std::vector<std::string> words;
            std::string word;
            for (char c : msg) {
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                    if (!word.empty()) { words.push_back(word); word.clear(); }
                } else {
                    word += c;
                }
            }
            if (!word.empty()) words.push_back(word);
            if (words.size() > 1 && tspeed > 0) {
                float msPerWord = ((float)(buf.curEffEndPer - buf.curEffStartPer + 1) * buf.frameTimeInMs) / (words.size() * tspeed);
                int wordIdx = 0;
                if (msPerWord > 0)
                    wordIdx = (int)(((float)(buf.curPeriod - buf.curEffStartPer) * buf.frameTimeInMs) / msPerWord);
                wordIdx = wordIdx % (int)words.size();
                msg = words[wordIdx];
            } else if (!words.empty()) {
                msg = words[0];
            }
        }

        if (msg.empty()) return true;

        // Get palette colors
        size_t numColors = buf.palette.ExplicitSize();
        if (numColors == 0) numColors = 1;
        xlColor primaryColor;
        buf.palette.GetColor(0, primaryColor);

        // Acquire a NativeTextDrawingContext from the pool
        NativeTextDrawingContext* dc = NativeTextDrawingContext::GetContext();
        if (!dc) return true;

        int w = buf.BufferWi;
        int h = buf.BufferHt;

        // Size the drawing context to match the buffer
        dc->ResetSize(w, h);
        dc->Clear();
        dc->SetFont(fontName, fontSize, fontBold, fontItalic, primaryColor);

        // Measure text (multi-line aware)
        // Split msg into lines and measure each
        std::vector<std::string> lines;
        {
            std::istringstream stream(msg);
            std::string line;
            while (std::getline(stream, line)) {
                lines.push_back(line);
            }
            if (lines.empty()) lines.push_back(msg);
        }

        int maxLineWidth = 0;
        int totalTextHeight = 0;
        int lineHeight = 0;
        std::vector<int> lineWidths;
        for (const auto& line : lines) {
            if (line.empty()) {
                // Empty line: use height of "W" as reference
                auto ext = dc->GetTextExtent("W");
                lineHeight = ext.second;
                totalTextHeight += lineHeight;
                lineWidths.push_back(0);
            } else {
                auto ext = dc->GetTextExtent(line);
                lineWidths.push_back(ext.first);
                lineHeight = ext.second;
                totalTextHeight += lineHeight;
                if (ext.first > maxLineWidth) maxLineWidth = ext.first;
            }
        }
        if (lineHeight == 0) {
            auto ext = dc->GetTextExtent("W");
            lineHeight = ext.second;
            if (lineHeight == 0) lineHeight = (int)fontSize;
        }

        // Rotation angle for rotated text effects
        double textRotation = 0.0;
        int xoffset = 0, yoffset = 0;
        auto textWidth = maxLineWidth;
        auto textHeight = totalTextHeight;
        switch (textEffect) {
            case 3: // rotate up 45
                textRotation = 45.0;
                yoffset = (int)(0.707 * textHeight);
                { int i = (int)(0.707 * (textWidth + textHeight));
                  textWidth = i; textHeight = i; }
                break;
            case 4: // rotate up 90
                textRotation = 90.0;
                std::swap(textWidth, textHeight);
                break;
            case 5: // rotate down 45
                textRotation = -45.0;
                xoffset = (int)(0.707 * textHeight);
                { int sz = (int)(0.707 * (textWidth + textHeight));
                  textWidth = sz; textHeight = sz; yoffset = sz; }
                break;
            case 6: // rotate down 90
                textRotation = -90.0;
                xoffset = textHeight;
                yoffset = textWidth;
                std::swap(textWidth, textHeight);
                break;
            default: break;
        }

        int txtwidth = textWidth;
        int totwidth = w + txtwidth;
        int totheight = h + textHeight;

        int OffsetLeft = startx * w / 100;
        int OffsetTop = -starty * h / 100;
        if (pixelOffsets) {
            OffsetLeft = startx;
            OffsetTop = -starty;
        }

        int xlimit = totwidth * 8 + 1;
        int ylimit = totheight * 8 + 1;

        int state = (buf.curPeriod - buf.curEffStartPer) * tspeed * buf.frameTimeInMs / 50;

        // Compute drawing rectangle position based on direction
        // The rect defines where the center of the text should be drawn.
        // We use the same coordinate system as legacy: rect is in buffer coords
        // with (0,0) at top-left of the buffer.
        int rectX = 0, rectY = 0;

        // Helper macros matching legacy behavior
        auto zigzag = [](int value, int range) -> int {
            if (range <= 0) return 0;
            return ((value / range) & 1) ? (value % range) : (range - value % range - 1);
        };

        bool isGoingLeft = (dir == DIR_LEFT || dir == DIR_UPLEFT || dir == DIR_DOWNLEFT);
        bool isGoingRight = (dir == DIR_RIGHT || dir == DIR_UPRIGHT || dir == DIR_DOWNRIGHT);

        int extra_left = 0, extra_right = 0;
        if (isGoingLeft) {
            // Measure trimmed text to get extra whitespace width
            std::string trimmed = msg;
            size_t start = trimmed.find_first_not_of(" \t");
            if (start != std::string::npos && start > 0) {
                std::string trimmedStr = trimmed.substr(start);
                auto ext = dc->GetTextExtent(trimmedStr);
                extra_left = maxLineWidth - ext.first;
            }
        }
        if (isGoingRight) {
            std::string trimmed = msg;
            size_t end = trimmed.find_last_not_of(" \t");
            if (end != std::string::npos && end < trimmed.size() - 1) {
                std::string trimmedStr = trimmed.substr(0, end + 1);
                auto ext = dc->GetTextExtent(trimmedStr);
                extra_right = maxLineWidth - ext.first;
            }
        }

        if (textRotation == 0.0) {
            // Non-rotated text: compute rect offset for movement directions
            rectX = 0;
            rectY = 0;

            switch (dir) {
                case DIR_VECTOR: {
                    double position = buf.GetEffectTimeIntervalPosition(1.0f);
                    double ex = endx * w / 100;
                    double ey = -endy * h / 100;
                    if (pixelOffsets) { ex = endx; ey = -endy; }
                    ex = OffsetLeft + (ex - OffsetLeft) * position;
                    ey = OffsetTop + (ey - OffsetTop) * position;
                    rectX = (int)ex;
                    rectY = (int)ey;
                } break;
                case DIR_LEFT: {
                    int state8 = state / 8;
                    if (state8 < 0) state8 += 32768;
                    if (norepeat && !center && state > xlimit) {
                        rectX = -xlimit;
                    } else {
                        rectX = center ? std::max(xlimit / 16 - state8, -extra_left / 2)
                                       : xlimit / 16 - state % xlimit / 8;
                    }
                    rectY = OffsetTop;
                } break;
                case DIR_RIGHT: {
                    if (norepeat && !center && state > xlimit) {
                        rectX = xlimit;
                    } else {
                        rectX = center ? std::min(state / 8 - xlimit / 16, extra_right / 2)
                                       : state % xlimit / 8 - xlimit / 16;
                    }
                    rectY = OffsetTop;
                } break;
                case DIR_UP: {
                    if (norepeat && !center && state > ylimit) {
                        rectY = -ylimit;
                    } else {
                        rectY = center ? std::max(ylimit / 16 - state / 8, 0)
                                       : ylimit / 16 - state % ylimit / 8;
                    }
                    rectX = OffsetLeft;
                } break;
                case DIR_DOWN: {
                    if (norepeat && !center && state > ylimit) {
                        rectY = ylimit;
                    } else {
                        rectY = center ? std::min(state / 8 - ylimit / 16, 0)
                                       : state % ylimit / 8 - ylimit / 16;
                    }
                    rectX = OffsetLeft;
                } break;
                case DIR_UPLEFT: {
                    if (norepeat && !center && (state > ylimit || state > xlimit)) {
                        rectX = -xlimit; rectY = -ylimit;
                    } else {
                        rectX = center ? std::max(xlimit / 16 - state / 8 + startx, 0)
                                       : xlimit / 16 - state % xlimit / 8 + startx;
                        rectY = center ? std::max(ylimit / 16 - state / 8 - starty, 0)
                                       : ylimit / 16 - state % ylimit / 8 - starty;
                    }
                } break;
                case DIR_DOWNLEFT: {
                    if (norepeat && !center && (state > ylimit || state > xlimit)) {
                        rectX = -xlimit; rectY = ylimit;
                    } else {
                        rectX = center ? std::max(xlimit / 16 - state / 8 + startx, 0)
                                       : xlimit / 16 - state % xlimit / 8 + startx;
                        rectY = center ? std::min(state / 8 - ylimit / 16 + starty, 0)
                                       : state % ylimit / 8 - ylimit / 16 + starty;
                    }
                } break;
                case DIR_UPRIGHT: {
                    if (norepeat && !center && (state > ylimit || state > xlimit)) {
                        rectX = xlimit; rectY = -ylimit;
                    } else {
                        rectX = center ? std::min(state / 8 - xlimit / 16 - startx, 0)
                                       : state % xlimit / 8 - xlimit / 16 - startx;
                        rectY = center ? std::max(ylimit / 16 - state / 8 - starty, 0)
                                       : ylimit / 16 - state % ylimit / 8 - starty;
                    }
                } break;
                case DIR_DOWNRIGHT: {
                    if (norepeat && !center && (state > ylimit || state > xlimit)) {
                        rectX = xlimit; rectY = ylimit;
                    } else {
                        rectX = center ? std::min(state / 8 - xlimit / 16 - startx, 0)
                                       : state % xlimit / 8 - xlimit / 16 - startx;
                        rectY = center ? std::min(state / 8 - ylimit / 16 + starty, 0)
                                       : state % ylimit / 8 - ylimit / 16 + starty;
                    }
                } break;
                case DIR_WAVEY: {
                    if (center)
                        rectX = std::min(state / 8 - xlimit / 16, extra_right / 2);
                    else
                        rectX = xlimit / 16 - state % xlimit / 8;
                    rectY = zigzag(state / 4, totheight) / 2 - totheight / 4;
                } break;
                case DIR_LEFTRIGHT: {
                    int cycle = xlimit;
                    int halfCycle = xlimit / 2;
                    if (halfCycle == 0) halfCycle = 1;
                    int normalizedState = state % cycle;
                    int offsetX;
                    if (normalizedState <= halfCycle)
                        offsetX = xlimit / 8 - (normalizedState * (xlimit / 4)) / halfCycle;
                    else
                        offsetX = -xlimit / 8 + ((normalizedState - halfCycle) * (xlimit / 4)) / halfCycle;
                    if (norepeat && state > xlimit) {
                        rectX = -xlimit;
                    } else {
                        rectX = offsetX;
                    }
                    rectY = OffsetTop;
                } break;
                case DIR_UPDOWN: {
                    int cycle = ylimit;
                    int halfCycle = ylimit / 2;
                    if (halfCycle == 0) halfCycle = 1;
                    int normalizedState = state % cycle;
                    int offsetY;
                    if (normalizedState <= halfCycle)
                        offsetY = ylimit / 16 - (normalizedState * (ylimit / 8)) / halfCycle;
                    else
                        offsetY = -(ylimit / 16) + ((normalizedState - halfCycle) * (ylimit / 8)) / halfCycle;
                    if (norepeat && state > ylimit) {
                        rectY = -ylimit;
                    } else {
                        rectY = offsetY;
                    }
                    rectX = OffsetLeft;
                } break;
                case DIR_WORDFLIP:
                case DIR_NONE:
                default:
                    rectX = OffsetLeft;
                    rectY = OffsetTop;
                    break;
            }

            // Draw text centered in the rect, with per-line horizontal centering
            // The rect offset shifts the drawing origin
            int baseY = (h - totalTextHeight) / 2 + rectY;
            int curColorPos = 0;

            for (size_t li = 0; li < lines.size(); li++) {
                const std::string& curLine = lines[li];
                if (curLine.empty()) {
                    baseY += lineHeight;
                    continue;
                }

                // Center this line horizontally within the buffer + rect offset
                int lineW = lineWidths[li];
                int drawX = (w - lineW) / 2 + rectX;
                int drawY = baseY;

                if (numColors <= 1) {
                    // Single color: draw whole line
                    dc->SetFont(fontName, fontSize, fontBold, fontItalic, primaryColor);
                    dc->DrawText(curLine, drawX, drawY);
                } else {
                    // Multi-color: draw character by character
                    auto extents = dc->GetTextExtents(curLine);
                    for (size_t ci = 0; ci < curLine.size(); ci++) {
                        char ch = curLine[ci];
                        if (ch == ' ') {
                            if (perWord && ci + 1 < curLine.size() && curLine[ci + 1] != ' ')
                                curColorPos++;
                            continue;
                        }
                        xlColor charColor;
                        buf.palette.GetColor(curColorPos % numColors, charColor);
                        dc->SetFont(fontName, fontSize, fontBold, fontItalic, charColor);

                        double charX = drawX;
                        if (ci > 0 && ci - 1 < extents.size()) {
                            charX = drawX + extents[ci - 1];
                        }
                        std::string charStr(1, ch);
                        dc->DrawText(charStr, (int)charX, drawY);

                        if (!perWord) curColorPos++;
                        else if (perWord && ch == ' ' && ci + 1 < curLine.size() && curLine[ci + 1] != ' ')
                            curColorPos++;
                    }
                }

                baseY += lineHeight;
            }
        } else {
            // Rotated text: draw with rotation at computed position
            switch (dir) {
                case DIR_LEFT:
                    rectX = w - state % xlimit / 8 + xoffset;
                    rectY = OffsetTop;
                    break;
                case DIR_RIGHT:
                    rectX = state % xlimit / 8 - txtwidth + xoffset;
                    rectY = OffsetTop;
                    break;
                case DIR_UP:
                    rectX = OffsetLeft;
                    rectY = totheight - state % ylimit / 8 - yoffset;
                    break;
                case DIR_DOWN:
                    rectX = OffsetLeft;
                    rectY = state % ylimit / 8 - yoffset;
                    break;
                case DIR_VECTOR: {
                    double position = buf.GetEffectTimeIntervalPosition(1.0f);
                    double ex = endx * w / 100;
                    double ey = -endy * h / 100;
                    if (pixelOffsets) { ex = endx; ey = -endy; }
                    ex = OffsetLeft + (ex - OffsetLeft) * position;
                    ey = OffsetTop + (ey - OffsetTop) * position;
                    rectX = w / 2 + (int)ex - txtwidth / 2 + xoffset;
                    rectY = h / 2 + (int)ey + yoffset;
                } break;
                default:
                    rectX = OffsetLeft;
                    rectY = OffsetTop;
                    break;
            }

            dc->SetFont(fontName, fontSize, fontBold, fontItalic, primaryColor);
            dc->DrawText(msg, rectX, rectY, textRotation);
        }

        // Extract rendered pixels from the drawing context into the NativeRenderBuffer.
        // NativeTextDrawingContext uses top-left origin (y=0 is top),
        // NativeRenderBuffer uses bottom-left origin (y=0 is bottom).
        auto* pixelData = dc->FlushAndGetPixels();
        if (pixelData && (int)pixelData->size() == w * h) {
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    const xlColor& c = (*pixelData)[(h - 1 - y) * w + x];
                    if (c.red != 0 || c.green != 0 || c.blue != 0 || c.alpha != 0) {
                        // Use alpha from the rendered text
                        xlColor pixel = c;
                        if (pixel.alpha == 0 && (pixel.red != 0 || pixel.green != 0 || pixel.blue != 0)) {
                            pixel.alpha = 255;
                        }
                        buf.SetPixel(x, y, pixel);
                    }
                }
            }
        }

        NativeTextDrawingContext::ReleaseContext(dc);
        return true;
    }

    if (type == "Video") {
        // Native Video effect — port of legacy VideoEffect::Render
        //
        // Loads a video file and extracts frames at the correct time offset,
        // rendering the scaled frame pixels into the buffer.
        // Uses NativeVideoReader (AVFoundation-based) for frame extraction.

        auto getStr = [&](const char* key, const char* def = "") -> std::string {
            auto it = effectInfo.settings.find(key);
            return (it != effectInfo.settings.end() && !it->second.empty()) ? it->second : def;
        };
        auto getInt = [&](const char* key, int def = 0) -> int {
            auto it = effectInfo.settings.find(key);
            return (it != effectInfo.settings.end() && !it->second.empty()) ? std::atoi(it->second.c_str()) : def;
        };
        auto getDouble = [&](const char* key, double def = 0.0) -> double {
            auto it = effectInfo.settings.find(key);
            return (it != effectInfo.settings.end() && !it->second.empty()) ? std::atof(it->second.c_str()) : def;
        };
        auto getBool = [&](const char* key, bool def = false) -> bool {
            auto it = effectInfo.settings.find(key);
            if (it == effectInfo.settings.end() || it->second.empty()) return def;
            return it->second == "1" || it->second == "true" || it->second == "yes";
        };

        std::string filename = getStr("E_FILEPICKERCTRL_Video_Filename");
        double starttime = getDouble("E_TEXTCTRL_Video_Starttime", 0.0);
        // Speed is stored as slider value / 100 (e.g., 100 = 1.0x)
        double speed = getDouble("E_SLIDER_Video_Speed", 100.0) / 100.0;
        bool aspectratio = getBool("E_CHECKBOX_Video_AspectRatio", false);
        std::string durationTreatment = getStr("E_CHOICE_Video_DurationTreatment", "Normal");
        bool transparentBlack = getBool("E_CHECKBOX_Video_TransparentBlack", false);
        int transparentBlackLevel = getInt("E_SLIDER_Video_TransparentBlackLevel", 0);

        int cropLeft = getInt("E_SLIDER_Video_CropLeft", 0);
        int cropRight = getInt("E_SLIDER_Video_CropRight", 100);
        int cropTop = getInt("E_SLIDER_Video_CropTop", 100);
        int cropBottom = getInt("E_SLIDER_Video_CropBottom", 0);

        // Normalize crop values
        if (cropLeft > cropRight) std::swap(cropLeft, cropRight);
        if (cropBottom > cropTop) std::swap(cropTop, cropBottom);
        if (cropLeft == cropRight) { if (cropLeft == 0) cropRight++; else cropLeft--; }
        if (cropBottom == cropTop) { if (cropBottom == 0) cropTop++; else cropBottom--; }

        if (filename.empty()) {
            // No filename — fill red to indicate error
            for (int y = 0; y < buf.BufferHt; y++)
                for (int x = 0; x < buf.BufferWi; x++)
                    buf.SetPixel(x, y, xlRED);
            return true;
        }

        // Video render cache
        struct VideoCache : public EffectRenderCache {
            NativeVideoReader reader;
            int loops = 0;
            int frameMS = 50;
            int nextManualMS = 0;
            double lastDecodedTime = -1.0;
        };

        VideoCache* cache = dynamic_cast<VideoCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new VideoCache();
            buf.infoCache[0] = cache;
        }

        NativeVideoReader& reader = cache->reader;

        // Open/reopen video on first frame
        if (buf.needToInit) {
            buf.needToInit = false;
            cache->loops = 0;
            cache->nextManualMS = 0;
            cache->frameMS = buf.frameTimeInMs;
            cache->lastDecodedTime = -1.0;

            reader.close();

            if (buf.BufferHt < 2) {
                // Cannot render video onto a 1 pixel high model
            } else {
                int width = buf.BufferWi * 100 / (cropRight - cropLeft);
                int height = buf.BufferHt * 100 / (cropTop - cropBottom);
                reader.open(filename, width, height, aspectratio);

                if (reader.isOpen()) {
                    if (durationTreatment == "Slow/Accelerate") {
                        int effectFrames = buf.curEffEndPer - buf.curEffStartPer + 1;
                        int videoFrames = static_cast<int>(
                            (reader.getDurationMS() - starttime * 1000) / buf.frameTimeInMs);
                        float speedFactor = static_cast<float>(videoFrames) /
                                            static_cast<float>(effectFrames);
                        cache->frameMS = static_cast<int>(buf.frameTimeInMs * speedFactor);
                    }
                }
            }
        }

        if (!reader.isOpen() || reader.getDurationMS() <= 0) {
            // Reader failed — fill red
            for (int y = 0; y < buf.BufferHt; y++)
                for (int x = 0; x < buf.BufferWi; x++)
                    buf.SetPixel(x, y, xlRED);
            return true;
        }

        // Calculate the video frame time in milliseconds
        long frameMS = 0;

        if (durationTreatment == "Manual" || durationTreatment == "Manual and Loop") {
            frameMS = static_cast<long>(starttime * 1000 + cache->nextManualMS);
            cache->nextManualMS += static_cast<int>(speed * cache->frameMS);

            if (durationTreatment == "Manual and Loop") {
                int videoLen = reader.getDurationMS();
                while (frameMS < 0) frameMS += videoLen;
                while (frameMS > videoLen) frameMS -= videoLen;
            }
        } else {
            frameMS = static_cast<long>(starttime * 1000 +
                (buf.curPeriod - buf.curEffStartPer) * cache->frameMS -
                cache->loops * (reader.getDurationMS() + cache->frameMS));
        }

        // Handle looping
        if (reader.atEnd(frameMS / 1000.0) && durationTreatment == "Loop") {
            cache->loops++;
            frameMS = static_cast<long>(starttime * 1000 +
                (buf.curPeriod - buf.curEffStartPer) * cache->frameMS -
                cache->loops * (reader.getDurationMS() + cache->frameMS));
            if (frameMS < 0) frameMS = 0;
        }

        if (frameMS < 0) {
            return true;
        }

        double frameTimeSec = frameMS / 1000.0;

        // Decode the video frame
        std::vector<uint8_t> rgbaPixels;
        if (!reader.getFrameAtTime(frameTimeSec, rgbaPixels)) {
            if (durationTreatment == "Normal") {
                // Past end of video — fill blue
                for (int y = 0; y < buf.BufferHt; y++)
                    for (int x = 0; x < buf.BufferWi; x++)
                        buf.SetPixel(x, y, xlBLUE);
            }
            return true;
        }

        // Render decoded frame pixels into the buffer.
        // The reader returns pixels at (reader.getWidth() x reader.getHeight()),
        // which accounts for aspect ratio. We need to map the cropped region
        // into the buffer.
        int imgW = reader.getWidth();
        int imgH = reader.getHeight();

        int xoffset = cropLeft * imgW / 100;
        int yoffset = cropBottom * imgH / 100;
        int croppedW = imgW * (cropRight - cropLeft) / 100;
        int croppedH = imgH * (cropTop - cropBottom) / 100;

        if (croppedW <= 0 || croppedH <= 0) return true;

        // Map buffer coords to the cropped region of the image.
        // Buffer x [0, BufferWi) maps to image x [xoffset, xoffset + croppedW)
        // Buffer y [0, BufferHt) maps to image y [ytop, ytop + croppedH)
        // Image is top-left origin; buffer is bottom-left origin.
        int ytop = (100 - cropTop) * imgH / 100;

        for (int y = 0; y < buf.BufferHt; y++) {
            for (int x = 0; x < buf.BufferWi; x++) {
                int srcX = xoffset + x * croppedW / buf.BufferWi;
                int srcY = ytop + (buf.BufferHt - 1 - y) * croppedH / buf.BufferHt;

                if (srcX < 0 || srcX >= imgW || srcY < 0 || srcY >= imgH) continue;

                size_t pixelOffset = (static_cast<size_t>(srcY) * imgW + srcX) * 4;
                if (pixelOffset + 3 >= rgbaPixels.size()) continue;

                uint8_t r = rgbaPixels[pixelOffset];
                uint8_t g = rgbaPixels[pixelOffset + 1];
                uint8_t b = rgbaPixels[pixelOffset + 2];

                if (transparentBlack) {
                    if (r <= transparentBlackLevel &&
                        g <= transparentBlackLevel &&
                        b <= transparentBlackLevel) {
                        continue;
                    }
                }

                buf.SetPixel(x, y, xlColor(r, g, b));
            }
        }

        return true;
    }

    if (type == "Liquid") {
        // Native Liquid effect — port of legacy LiquidEffect::Render
        // Uses LiquidFun (Box2D extension) for particle-based fluid simulation.
        // Physics world and particle system are cached between frames.
        // Audio-reactive flow is stubbed (audio not yet wired in native pipeline).

        static const int LIQUID_MAX_PARTICLES = 100000;
        static const double PI2 = 6.283185307;

        // --- Helper lambdas ---
        auto getStr = [&](const char* key, const char* def = "") -> std::string {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty()) return it->second;
            return def;
        };
        auto getInt = [&](const char* key, int def) -> int {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty()) return std::atoi(it->second.c_str());
            return def;
        };
        auto getBool = [&](const char* key, bool def) -> bool {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end()) return (it->second == "1");
            return def;
        };
        auto getDouble = [&](const char* key, double def) -> double {
            auto it = effectInfo.settings.find(key);
            if (it != effectInfo.settings.end() && !it->second.empty()) return std::atof(it->second.c_str());
            return def;
        };
        auto localRand01 = []() -> double {
            return static_cast<double>(std::rand()) / static_cast<double>(RAND_MAX);
        };

        // --- Read settings ---
        bool topBarrier = getBool("E_CHECKBOX_TopBarrier", false);
        bool bottomBarrier = getBool("E_CHECKBOX_BottomBarrier", true);
        bool leftBarrier = getBool("E_CHECKBOX_LeftBarrier", false);
        bool rightBarrier = getBool("E_CHECKBOX_RightBarrier", false);

        bool holdColor = getBool("E_CHECKBOX_HoldColor", true);
        bool mixColors = getBool("E_CHECKBOX_MixColors", false);

        int lifetime = getInt("E_SLIDER_LifeTime", 10000);
        int size = getInt("E_TEXTCTRL_Size", 500);
        int warmUpFrames = getInt("E_TEXTCTRL_WarmUpFrames", 0);
        int despeckle = getInt("E_TEXTCTRL_Despeckle", 0);

        std::string particleType = getStr("E_CHOICE_ParticleType", "Elastic");

        double gravity = getDouble("E_SLIDER_Liquid_Gravity", 100) / 10.0;
        int gravityAngle = getInt("E_SLIDER_Liquid_GravityAngle", 0);

        // Source 1 (always enabled)
        int x1 = getInt("E_SLIDER_X1", 50);
        int y1 = getInt("E_SLIDER_Y1", 100);
        int direction1 = getInt("E_SLIDER_Direction1", 270);
        int velocity1 = getInt("E_SLIDER_Velocity1", 100);
        int flow1 = getInt("E_SLIDER_Flow1", 100);
        int sourceSize1 = getInt("E_SLIDER_Liquid_SourceSize1", 0);
        bool flowMusic1 = getBool("E_CHECKBOX_FlowMusic1", false);

        // Source 2
        bool enabled2 = getBool("E_CHECKBOX_Enabled2", false);
        int x2 = getInt("E_SLIDER_X2", 0);
        int y2 = getInt("E_SLIDER_Y2", 50);
        int direction2 = getInt("E_SLIDER_Direction2", 0);
        int velocity2 = getInt("E_SLIDER_Velocity2", 100);
        int flow2 = getInt("E_SLIDER_Flow2", 100);
        int sourceSize2 = getInt("E_SLIDER_Liquid_SourceSize2", 0);
        bool flowMusic2 = getBool("E_CHECKBOX_FlowMusic2", false);

        // Source 3
        bool enabled3 = getBool("E_CHECKBOX_Enabled3", false);
        int x3 = getInt("E_SLIDER_X3", 50);
        int y3 = getInt("E_SLIDER_Y3", 0);
        int direction3 = getInt("E_SLIDER_Direction3", 90);
        int velocity3 = getInt("E_SLIDER_Velocity3", 100);
        int flow3 = getInt("E_SLIDER_Flow3", 100);
        int sourceSize3 = getInt("E_SLIDER_Liquid_SourceSize3", 0);
        bool flowMusic3 = getBool("E_CHECKBOX_FlowMusic3", false);

        // Source 4
        bool enabled4 = getBool("E_CHECKBOX_Enabled4", false);
        int x4 = getInt("E_SLIDER_X4", 100);
        int y4 = getInt("E_SLIDER_Y4", 50);
        int direction4 = getInt("E_SLIDER_Direction4", 180);
        int velocity4 = getInt("E_SLIDER_Velocity4", 100);
        int flow4 = getInt("E_SLIDER_Flow4", 100);
        int sourceSize4 = getInt("E_SLIDER_Liquid_SourceSize4", 0);
        bool flowMusic4 = getBool("E_CHECKBOX_FlowMusic4", false);

        bool enabled[4] = { true, enabled2, enabled3, enabled4 };

        // --- Gravity vector ---
        auto liquidToRadians = [](double degrees) -> double {
            return 2.0 * M_PI * degrees / 360.0;
        };
        float gravityX = static_cast<float>(gravity * std::cos(liquidToRadians(360.0 - (gravityAngle + 90))));
        float gravityY = static_cast<float>(gravity * std::sin(liquidToRadians(360.0 - (gravityAngle + 90))));
        b2Vec2 grav(gravityX, gravityY);

        int BufferWi = buf.BufferWi;
        int BufferHt = buf.BufferHt;

        // --- Render cache: persists the b2World across frames ---
        struct LiquidNativeCache : public EffectRenderCache {
            b2World* world = nullptr;
            ~LiquidNativeCache() override {
                if (world) { delete world; world = nullptr; }
            }
        };

        LiquidNativeCache* cache = dynamic_cast<LiquidNativeCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new LiquidNativeCache();
            buf.infoCache[0] = cache;
        }
        b2World*& world = cache->world;

        // --- Create barrier helper ---
        auto createBarrier = [](b2World* w, float bx, float by, float bwidth, float bheight) {
            b2BodyDef groundBodyDef;
            groundBodyDef.position.Set(bx, by);
            b2Body* groundBody = w->CreateBody(&groundBodyDef);
            b2PolygonShape groundBox;
            groundBox.SetAsBox(bwidth / 2.0f, bheight / 2.0f);
            groundBody->CreateFixture(static_cast<b2Shape*>(&groundBox), 0.0f);
        };

        // --- Create particle system helper ---
        auto createParticleSystem = [&](b2World* w, int lt, int sz) {
            b2ParticleSystemDef particleSystemDef;
            auto particleSys = w->CreateParticleSystem(&particleSystemDef);
            particleSys->SetRadius(static_cast<float>(sz) / 1000.0f);
            particleSys->SetMaxParticleCount(LIQUID_MAX_PARTICLES);
            if (lt > 0) {
                particleSys->SetDestructionByAge(true);
            }
        };

        // --- Particle creation helper ---
        auto createParticles = [&](b2ParticleSystem* particleSys, int px, int py, int dir, int vel,
                                   int flowCount, bool fMusic, int lt, int w, int h,
                                   const xlColor& c, const std::string& pType, bool mix,
                                   float audioLvl, int srcSize) {
            float posx = static_cast<float>(px) * static_cast<float>(w) / 100.0f;
            float posy = static_cast<float>(py) * static_cast<float>(h) / 100.0f;

            float velx = static_cast<float>(vel) * 10.0f * std::cos(static_cast<float>(PI2) * static_cast<float>(dir) / 360.0f);
            float vely = static_cast<float>(vel) * 10.0f * std::sin(static_cast<float>(PI2) * static_cast<float>(dir) / 360.0f);

            float velVariation = static_cast<float>(localRand01()) * 0.1f;
            velVariation -= velVariation / 2.0f;
            velx -= velx * velVariation;
            vely -= vely * velVariation;

            float ltSec = static_cast<float>(lt) / 100.0f;

            int count = flowCount;
            if (fMusic) {
                count = static_cast<int>(count * audioLvl);
            }

            if (particleSys->GetParticleCount() > LIQUID_MAX_PARTICLES - (2 * count)) {
                for (int i = 0; i < particleSys->GetParticleCount() - (LIQUID_MAX_PARTICLES - 2 * count); ++i) {
                    particleSys->DestroyOldestParticle(i, true);
                }
            }

            for (int i = 0; i < count && particleSys->GetParticleCount() < LIQUID_MAX_PARTICLES; ++i) {
                b2ParticleDef pd;
                if (pType == "Elastic") pd.flags = b2_elasticParticle;
                else if (pType == "Powder") pd.flags = b2_powderParticle;
                else if (pType == "Tensile") pd.flags = b2_tensileParticle;
                else if (pType == "Spring") pd.flags = b2_springParticle;
                else if (pType == "Viscous") pd.flags = b2_viscousParticle;
                else if (pType == "Static Pressure") pd.flags = b2_staticPressureParticle;
                else if (pType == "Water") pd.flags = b2_waterParticle;
                else if (pType == "Reactive") pd.flags = b2_reactiveParticle;
                else if (pType == "Repulsive") pd.flags = b2_repulsiveParticle;

                if (mix) pd.flags |= b2_colorMixingParticle;

                pd.color.Set(c.Red(), c.Green(), c.Blue(), 255);

                if (srcSize == 0) {
                    const float angle = static_cast<float>(localRand01()) * 2.0f * b2_pi;
                    const float distance = static_cast<float>(localRand01());
                    b2Vec2 posOnCircle(std::sin(angle), std::cos(angle));
                    pd.position.Set(
                        posx + posOnCircle.x * distance * 0.5f,
                        posy + posOnCircle.y * distance * 0.5f);
                } else {
                    const float distance = static_cast<float>(localRand01()) * (static_cast<float>(srcSize) - static_cast<float>(srcSize) / 2.0f);
                    float offx = distance * std::cos(static_cast<float>(PI2) * (static_cast<float>(dir) + 90.0f) / 360.0f);
                    float offy = distance * std::sin(static_cast<float>(PI2) * (static_cast<float>(dir) + 90.0f) / 360.0f);
                    pd.position.Set(posx + offx * static_cast<float>(w) / 200.0f,
                                    posy + offy * static_cast<float>(h) / 200.0f);
                }

                pd.velocity.x = velx;
                pd.velocity.y = vely;

                if (lt > 0) {
                    float randomlt = ltSec + (ltSec * 0.2f * static_cast<float>(localRand01())) - (ltSec * 0.01f);
                    pd.lifetime = randomlt;
                }
                particleSys->CreateParticle(pd);
            }
        };

        // --- Step: advance simulation and create new particles ---
        auto stepSimulation = [&](b2World* w, bool enab[], int lt,
                                  const std::string& pType, bool mix,
                                  int sx1, int sy1, int sd1, int sv1, int sf1, int ss1, bool sm1,
                                  int sx2, int sy2, int sd2, int sv2, int sf2, int ss2, bool sm2,
                                  int sx3, int sy3, int sd3, int sv3, int sf3, int ss3, bool sm3,
                                  int sx4, int sy4, int sd4, int sv4, int sf4, int ss4, bool sm4,
                                  float time) {
            float timeStep = static_cast<float>(buf.frameTimeInMs) / 1000.0f;
            int velocityIterations = 6;
            int positionIterations = 2;
            int particleIterations = 3;
            w->Step(timeStep, velocityIterations, positionIterations, particleIterations);

            b2ParticleSystem* particleSys = w->GetParticleSystemList();
            if (particleSys != nullptr) {
                // Audio not yet available in native pipeline — use fallback
                float audioLevel = 0.0001f;

                int j = 0;
                int srcX[] = { sx1, sx2, sx3, sx4 };
                int srcY[] = { sy1, sy2, sy3, sy4 };
                int srcDir[] = { sd1, sd2, sd3, sd4 };
                int srcVel[] = { sv1, sv2, sv3, sv4 };
                int srcFlow[] = { sf1, sf2, sf3, sf4 };
                int srcSSize[] = { ss1, ss2, ss3, ss4 };
                bool srcMusic[] = { sm1, sm2, sm3, sm4 };

                for (int i = 0; i < 4; ++i) {
                    if (enab[i]) {
                        xlColor color;
                        buf.palette.GetColor(j % buf.GetColorCount(), color, time);
                        createParticles(particleSys, srcX[i], srcY[i], srcDir[i], srcVel[i],
                                        srcFlow[i], srcMusic[i], lt,
                                        BufferWi, BufferHt, color, pType, mix,
                                        audioLevel, srcSSize[i]);
                        ++j;
                    }
                }
            }
        };

        // --- LostForever: check if particle has left the screen permanently ---
        auto lostForever = [](int px, int py, int w, int h, float gx, float gy) -> bool {
            if (gx < 0.0001f && gx > -0.0001f) {
                if (px < -1 || px > w + 1) return true;
            }
            if (gx < 0.0001f) {
                if (px < -1) return true;
            }
            if (gx > -0.0001f) {
                if (px > w + 1) return true;
            }
            if (gy < 0.0001f && gy > -0.0001f) {
                if (py < -1 || py > h + 1) return true;
            }
            if (gy > -0.0001f) {
                if (py < -1) return true;
            }
            if (gy < 0.0001f) {
                if (py > h + 1) return true;
            }
            return false;
        };

        // --- Despeckle helper ---
        auto getDespeckleColor = [&](int dx, int dy, int dsp) -> xlColor {
            int red = 0, green = 0, blue = 0, count = 0;
            int startx = std::max(0, dx - 1);
            int starty = std::max(0, dy - 1);
            int endx = std::min(BufferWi - 1, dx + 1);
            int endy = std::min(BufferHt - 1, dy + 1);
            int blacks = 0;
            for (int yy = starty; yy <= endy; ++yy) {
                for (int xx = startx; xx <= endx; ++xx) {
                    if (yy != dy || xx != dx) {
                        const xlColor& c = buf.GetPixel(xx, yy);
                        if (c == xlBLACK) {
                            ++blacks;
                            if (blacks >= dsp) return xlBLACK;
                        }
                        red += c.red;
                        green += c.green;
                        blue += c.blue;
                        ++count;
                    }
                }
            }
            if (count == 0) return xlBLACK;
            return xlColor(red / count, green / count, blue / count);
        };

        // --- Initialize world on first frame ---
        if (buf.needToInit) {
            buf.needToInit = false;
            if (world != nullptr) {
                delete world;
                world = nullptr;
            }

            world = new b2World(grav);

            if (bottomBarrier)
                createBarrier(world, static_cast<float>(BufferWi) / 2.0f, -1.0f, static_cast<float>(BufferWi), 0.001f);
            if (topBarrier)
                createBarrier(world, static_cast<float>(BufferWi) / 2.0f, static_cast<float>(BufferHt) + 1.0f, static_cast<float>(BufferWi), 0.001f);
            if (leftBarrier)
                createBarrier(world, -1.0f, static_cast<float>(BufferHt) / 2.0f, 0.001f, static_cast<float>(BufferHt));
            if (rightBarrier)
                createBarrier(world, static_cast<float>(BufferWi) + 1.0f, static_cast<float>(BufferHt) / 2.0f, 0.001f, static_cast<float>(BufferHt));

            createParticleSystem(world, lifetime, size);

            for (int i = 0; i < warmUpFrames; ++i) {
                stepSimulation(world, enabled, lifetime, particleType, mixColors,
                    x1, y1, direction1, velocity1, flow1, sourceSize1, flowMusic1,
                    x2, y2, direction2, velocity2, flow2, sourceSize2, flowMusic2,
                    x3, y3, direction3, velocity3, flow3, sourceSize3, flowMusic3,
                    x4, y4, direction4, velocity4, flow4, sourceSize4, flowMusic4, 0.0f);
            }
        }

        if (world == nullptr) return true;

        world->SetGravity(grav);

        // Step the simulation
        stepSimulation(world, enabled, lifetime, particleType, mixColors,
            x1, y1, direction1, velocity1, flow1, sourceSize1, flowMusic1,
            x2, y2, direction2, velocity2, flow2, sourceSize2, flowMusic2,
            x3, y3, direction3, velocity3, flow3, sourceSize3, flowMusic3,
            x4, y4, direction4, velocity4, flow4, sourceSize4, flowMusic4,
            buf.GetEffectTimeIntervalPosition());

        // --- Draw particles ---
        b2ParticleSystem* liquidPS = world->GetParticleSystemList();
        if (liquidPS != nullptr) {
            xlColor baseColor;
            buf.palette.GetColor(0, baseColor);

            int32 particleCount = liquidPS->GetParticleCount();
            if (particleCount > 0) {
                const b2Vec2* positionBuffer = liquidPS->GetPositionBuffer();
                const b2ParticleColor* colorBuffer = liquidPS->GetColorBuffer();

                for (int i = 0; i < particleCount; ++i) {
                    int px = static_cast<int>(positionBuffer[i].x);
                    int py = static_cast<int>(positionBuffer[i].y);

                    if (lostForever(px, py, BufferWi, BufferHt, gravityX, gravityY)) {
                        liquidPS->DestroyParticle(i);
                    } else {
                        if ((holdColor || mixColors) && colorBuffer) {
                            auto c = colorBuffer[i].GetColor();
                            buf.SetPixel(static_cast<int>(positionBuffer[i].x),
                                         static_cast<int>(positionBuffer[i].y),
                                         xlColor(static_cast<uint8_t>(c.r * 255),
                                                 static_cast<uint8_t>(c.g * 255),
                                                 static_cast<uint8_t>(c.b * 255)));
                        } else {
                            buf.SetPixel(static_cast<int>(positionBuffer[i].x),
                                         static_cast<int>(positionBuffer[i].y),
                                         baseColor);
                        }
                    }
                }
            }

            // Despeckle pass
            if (despeckle > 0) {
                for (int y = 0; y < BufferHt; ++y) {
                    for (int x = 0; x < BufferWi; ++x) {
                        if (buf.GetPixel(x, y) == xlBLACK) {
                            xlColor fillColor = getDespeckleColor(x, y, despeckle);
                            if (fillColor != xlBLACK) {
                                buf.SetPixel(x, y, fillColor);
                            }
                        }
                    }
                }
            }
        }

        // Clean up the world on the last frame to free memory
        if (buf.curPeriod == buf.curEffEndPer) {
            delete world;
            world = nullptr;
        }

        return true;
    }

    if (type == "Pictures") {
        // Native Pictures effect — port of legacy PicturesEffect::Render
        // Loads image files (PNG/JPEG/GIF/BMP) and displays them on the buffer
        // with support for movement directions, scaling, GIF animation, shimmer,
        // transparent black, and position offsets.

        std::string filename;
        auto it = effectInfo.settings.find("E_FILEPICKERCTRL_Pictures_Filename");
        if (it != effectInfo.settings.end()) filename = it->second;

        std::string dirStr = "none";
        it = effectInfo.settings.find("E_CHOICE_Pictures_Direction");
        if (it != effectInfo.settings.end() && !it->second.empty()) dirStr = it->second;

        float movementSpeed = 1.0f;
        it = effectInfo.settings.find("E_SLIDER_Pictures_Speed");
        if (it != effectInfo.settings.end() && !it->second.empty())
            movementSpeed = std::atof(it->second.c_str());

        float frameRateAdj = 1.0f;
        it = effectInfo.settings.find("E_SLIDER_Pictures_FrameRateAdj");
        if (it != effectInfo.settings.end() && !it->second.empty())
            frameRateAdj = std::atof(it->second.c_str()) / 10.0f;

        int xc_adj = 0, yc_adj = 0;
        it = effectInfo.settings.find("E_SLIDER_PicturesXC");
        if (it != effectInfo.settings.end() && !it->second.empty()) xc_adj = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_PicturesYC");
        if (it != effectInfo.settings.end() && !it->second.empty()) yc_adj = std::atoi(it->second.c_str());

        int xce_adj = 0, yce_adj = 0;
        it = effectInfo.settings.find("E_SLIDER_PicturesEndXC");
        if (it != effectInfo.settings.end() && !it->second.empty()) xce_adj = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_PicturesEndYC");
        if (it != effectInfo.settings.end() && !it->second.empty()) yce_adj = std::atoi(it->second.c_str());

        int startScale = 100, endScale = 100;
        it = effectInfo.settings.find("E_SLIDER_Pictures_StartScale");
        if (it != effectInfo.settings.end() && !it->second.empty()) startScale = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_SLIDER_Pictures_EndScale");
        if (it != effectInfo.settings.end() && !it->second.empty()) endScale = std::atoi(it->second.c_str());

        bool pixelOffsets = false, wrapX = false, shimmer = false;
        bool transparentBlack = false;
        int transparentBlackLevel = 0;
        it = effectInfo.settings.find("E_CHECKBOX_Pictures_PixelOffsets");
        if (it != effectInfo.settings.end()) pixelOffsets = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Pictures_WrapX");
        if (it != effectInfo.settings.end()) wrapX = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Pictures_Shimmer");
        if (it != effectInfo.settings.end()) shimmer = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Pictures_TransparentBlack");
        if (it != effectInfo.settings.end()) transparentBlack = (it->second == "1");
        it = effectInfo.settings.find("E_SLIDER_Pictures_TransparentBlackLevel");
        if (it != effectInfo.settings.end() && !it->second.empty())
            transparentBlackLevel = std::atoi(it->second.c_str());

        std::string scaleToFit = "No Scaling";
        it = effectInfo.settings.find("E_CHOICE_Scaling");
        if (it != effectInfo.settings.end() && !it->second.empty()) scaleToFit = it->second;

        bool loopGIF = false;
        it = effectInfo.settings.find("E_CHECKBOX_LoopGIF");
        if (it != effectInfo.settings.end()) loopGIF = (it->second == "1");

        // Direction constants matching legacy PicturesEffect
        enum PicDir {
            PIC_LEFT = 0, PIC_RIGHT, PIC_UP, PIC_DOWN, PIC_NONE,
            PIC_UPLEFT, PIC_DOWNLEFT, PIC_UPRIGHT, PIC_DOWNRIGHT,
            PIC_PEEKABOO_0, PIC_WIGGLE, PIC_ZOOMIN,
            PIC_PEEKABOO_90, PIC_PEEKABOO_180, PIC_PEEKABOO_270,
            PIC_VIXREMAP, PIC_FLAGWAVE,
            PIC_UPONCE, PIC_DOWNONCE, PIC_VECTOR,
            PIC_TILE_LEFT, PIC_TILE_RIGHT, PIC_TILE_DOWN, PIC_TILE_UP
        };

        int dir = PIC_NONE;
        if (dirStr == "left") dir = PIC_LEFT;
        else if (dirStr == "right") dir = PIC_RIGHT;
        else if (dirStr == "up") dir = PIC_UP;
        else if (dirStr == "down") dir = PIC_DOWN;
        else if (dirStr == "none") dir = PIC_NONE;
        else if (dirStr == "up-left") dir = PIC_UPLEFT;
        else if (dirStr == "down-left") dir = PIC_DOWNLEFT;
        else if (dirStr == "up-right") dir = PIC_UPRIGHT;
        else if (dirStr == "down-right") dir = PIC_DOWNRIGHT;
        else if (dirStr == "peekaboo") dir = PIC_PEEKABOO_0;
        else if (dirStr == "wiggle") dir = PIC_WIGGLE;
        else if (dirStr == "zoom in") dir = PIC_ZOOMIN;
        else if (dirStr == "zoom out") dir = PIC_ZOOMIN;
        else if (dirStr == "peekaboo 90") dir = PIC_PEEKABOO_90;
        else if (dirStr == "peekaboo 180") dir = PIC_PEEKABOO_180;
        else if (dirStr == "peekaboo 270") dir = PIC_PEEKABOO_270;
        else if (dirStr == "flag wave") dir = PIC_FLAGWAVE;
        else if (dirStr == "up once") dir = PIC_UPONCE;
        else if (dirStr == "down once") dir = PIC_DOWNONCE;
        else if (dirStr == "vector") dir = PIC_VECTOR;
        else if (dirStr == "tile-left") dir = PIC_TILE_LEFT;
        else if (dirStr == "tile-right") dir = PIC_TILE_RIGHT;
        else if (dirStr == "tile-down") dir = PIC_TILE_DOWN;
        else if (dirStr == "tile-up") dir = PIC_TILE_UP;

        struct PicturesCache : public EffectRenderCache {
            NativeImage image;
            NativeImage rawImage;
            std::string pictureName;
            int imageCount = 0;
        };

        PicturesCache* cache = dynamic_cast<PicturesCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new PicturesCache();
            buf.infoCache[0] = cache;
        }

        int BufferWi = buf.BufferWi;
        int BufferHt = buf.BufferHt;
        int curPeriod = buf.curPeriod;
        int curEffStartPer = buf.curEffStartPer;
        double position = buf.GetEffectTimeIntervalPosition(movementSpeed);
        bool noImageFile = false;
        bool scaleImage = false;

        if (filename.empty()) {
            noImageFile = true;
        } else {
            if (filename != cache->pictureName || buf.needToInit) {
                buf.needToInit = false;
                scaleImage = true;
                cache->pictureName = filename;
                cache->imageCount = NativeImageLoader::GetFrameCount(filename);
                if (cache->imageCount <= 0) cache->imageCount = 1;

                if (cache->imageCount > 1) {
                    cache->rawImage = NativeImageLoader::LoadFrameFromFile(filename, 0);
                } else {
                    cache->rawImage = NativeImageLoader::LoadFromFile(filename);
                }
                cache->image = cache->rawImage;
            }

            if (cache->imageCount > 1) {
                scaleImage = true;
                int frameIdx;
                if (loopGIF) {
                    int elapsed = (curPeriod - curEffStartPer) * buf.frameTimeInMs;
                    frameIdx = static_cast<int>(elapsed * frameRateAdj / buf.frameTimeInMs) % cache->imageCount;
                } else {
                    frameIdx = static_cast<int>(cache->imageCount * buf.GetEffectTimeIntervalPosition(frameRateAdj) * 0.99);
                }
                if (frameIdx < 0) frameIdx = 0;
                if (frameIdx >= cache->imageCount) frameIdx = cache->imageCount - 1;
                cache->image = NativeImageLoader::LoadFrameFromFile(filename, frameIdx);
                cache->rawImage = cache->image;
            }

            if (!cache->image.IsOk()) {
                noImageFile = true;
            }
        }

        if (noImageFile) {
            for (int x = 0; x < BufferWi; x++)
                for (int y = 0; y < BufferHt; y++)
                    buf.SetPixel(x, y, xlRED);
            return true;
        }

        NativeImage image = cache->rawImage;
        int imgwidth = image.GetWidth();
        int imght = image.GetHeight();

        if (scaleToFit == "Scale To Fit" && (BufferWi != imgwidth || BufferHt != imght)) {
            image = image.Rescale(BufferWi, BufferHt);
            imgwidth = image.GetWidth();
            imght = image.GetHeight();
        } else if (scaleToFit == "Scale Keep Aspect Ratio" || scaleToFit == "Scale Keep Aspect Ratio Crop") {
            float xr = (float)BufferWi / (float)imgwidth;
            float yr = (float)BufferHt / (float)imght;
            float sc = (scaleToFit.find("Crop") != std::string::npos) ? std::max(xr, yr) : std::min(xr, yr);
            int newW = std::max(1, (int)(imgwidth * sc));
            int newH = std::max(1, (int)(imght * sc));
            image = image.Rescale(newW, newH);
            imgwidth = image.GetWidth();
            imght = image.GetHeight();
        } else if (scaleToFit == "No Scaling" && (startScale != 100 || endScale != 100)) {
            int deltaScale = endScale - startScale;
            int currentScale = startScale + static_cast<int>(deltaScale * position);
            int newW = std::max(1, (imgwidth * currentScale) / 100);
            int newH = std::max(1, (imght * currentScale) / 100);
            image = image.Rescale(newW, newH);
            imgwidth = image.GetWidth();
            imght = image.GetHeight();
        }

        cache->image = image;

        int yoffset = (BufferHt + imght) / 2;
        int xoffset = (imgwidth - BufferWi) / 2;

        float xscale = 0, yscale = 0;
        int waveX = 0, waveW = 0, waveN = 0;

        switch (dir) {
        case PIC_ZOOMIN:
            xscale = (imgwidth > 1) ? (float)BufferWi / imgwidth : 1;
            yscale = (imght > 1) ? (float)BufferHt / imght : 1;
            xscale *= position;
            yscale *= position;
            break;
        case PIC_PEEKABOO_0:
        case PIC_PEEKABOO_180:
            yoffset = (-BufferHt) * (1.0 - position * 2.0);
            if (yoffset > 10) yoffset = -yoffset + 10;
            else if (yoffset > 0) yoffset = 0;
            break;
        case PIC_PEEKABOO_90:
        case PIC_PEEKABOO_270:
            yoffset = (imght - BufferWi) / 2;
            xoffset = (-BufferHt) * (1.0 - position * 2.0);
            if (xoffset > 10) xoffset = -xoffset + 10;
            else if (xoffset > 0) xoffset = 0;
            break;
        case PIC_UPONCE:
        case PIC_DOWNONCE:
            position = buf.GetEffectTimeIntervalPosition() * movementSpeed;
            if (position > 1.0) position = 1.0;
            break;
        case PIC_WIGGLE:
            if (position >= 0.5)
                xoffset += BufferWi * ((1.0 - position) * 2.0 - 0.5);
            else
                xoffset += BufferWi * (position * 2.0 - 0.5);
            break;
        case PIC_FLAGWAVE:
            waveW = BufferWi;
            waveX = position * 200;
            waveN = waveW > 0 ? waveX / waveW : 0;
            break;
        default:
            break;
        }

        int xoffset_adj = xc_adj;
        int yoffset_adj = yc_adj;
        if (dir == PIC_VECTOR) {
            dir = PIC_NONE;
            xoffset_adj = static_cast<int>(std::round(position * double(xce_adj - xc_adj))) + xc_adj;
            yoffset_adj = static_cast<int>(std::round(position * double(yce_adj - yc_adj))) + yc_adj;
        }
        if (!pixelOffsets) {
            xoffset_adj = static_cast<int>((xoffset_adj * BufferWi) / 100.0);
            yoffset_adj = static_cast<int>((yoffset_adj * BufferHt) / 100.0);
        }

        int calcPosWi = static_cast<int>((imgwidth + BufferWi) * position);
        int calcPosHt = static_cast<int>((imght + BufferHt) * position);

        auto setPixelTB = [&](int px, int py, const xlColor& c, bool wrap) {
            if (transparentBlack) {
                int level = c.red + c.green + c.blue;
                if (level <= transparentBlackLevel) return;
            }
            if (wrap) {
                buf.ProcessPixel(px, py, c, true);
            } else {
                buf.SetPixel(px, py, c);
            }
        };

        for (int x = 0; x < imgwidth; x++) {
            for (int y = 0; y < imght; y++) {
                xlColor c = image.GetPixel(x, y);

                bool hasAlpha = image.HasAlpha();
                if (hasAlpha && c.alpha < 10) continue;
                if (image.IsTransparent(x, y)) continue;

                if (!buf.allowAlpha && hasAlpha && c.alpha < 64) {
                    c = xlBLACK;
                }

                switch (dir) {
                case PIC_LEFT:
                    setPixelTB(x + xoffset_adj + BufferWi - calcPosWi, yoffset - y - yoffset_adj - 1, c, wrapX);
                    break;
                case PIC_RIGHT:
                    setPixelTB(x + xoffset_adj + calcPosWi - imgwidth, yoffset - y - yoffset_adj - 1, c, wrapX);
                    break;
                case PIC_UP:
                case PIC_UPONCE:
                    setPixelTB(x - xoffset + xoffset_adj, calcPosHt - y - yoffset_adj, c, wrapX);
                    break;
                case PIC_DOWN:
                case PIC_DOWNONCE:
                    setPixelTB(x - xoffset + xoffset_adj, BufferHt + imght - y - yoffset_adj - calcPosHt, c, wrapX);
                    break;
                case PIC_UPLEFT:
                    setPixelTB(x + xoffset_adj + BufferWi - calcPosWi, calcPosHt - y - yoffset_adj, c, wrapX);
                    break;
                case PIC_DOWNLEFT:
                    setPixelTB(x + xoffset_adj + BufferWi - calcPosWi, BufferHt + imght - y - yoffset_adj - calcPosHt, c, wrapX);
                    break;
                case PIC_UPRIGHT:
                    setPixelTB(x + xoffset_adj + calcPosWi - imgwidth, calcPosHt - y - yoffset_adj, c, wrapX);
                    break;
                case PIC_DOWNRIGHT:
                    setPixelTB(x + xoffset_adj + calcPosWi - imgwidth, BufferHt + imght - y - yoffset_adj - calcPosHt, c, wrapX);
                    break;
                case PIC_PEEKABOO_0:
                    setPixelTB(x - xoffset + xoffset_adj, BufferHt + yoffset - y - yoffset_adj - 1, c, wrapX);
                    break;
                case PIC_ZOOMIN:
                    setPixelTB(static_cast<int>((x + xoffset_adj) * xscale), static_cast<int>((BufferHt - 1 - y - yoffset_adj) * yscale), c, wrapX);
                    break;
                case PIC_PEEKABOO_90:
                    setPixelTB(BufferWi + xoffset - y + xoffset_adj, x - yoffset - yoffset_adj, c, wrapX);
                    break;
                case PIC_PEEKABOO_180:
                    setPixelTB(x - xoffset + xoffset_adj, y - yoffset - yoffset_adj, c, wrapX);
                    break;
                case PIC_PEEKABOO_270:
                    setPixelTB(y - xoffset + xoffset_adj, BufferHt + yoffset + yoffset_adj - x, c, wrapX);
                    break;
                case PIC_FLAGWAVE: {
                    int waveY = 0;
                    if (BufferHt < 20) {
                        waveN = waveW > 0 ? (x - waveX) / waveW : 0;
                        waveY = !x ? 0 : (waveN & 1) ? -1 : 0;
                    } else {
                        waveN = waveW > 0 ? (x - waveX) / waveW : 0;
                        waveY = !x ? 0 : (waveN & 1) ? 0 : (waveN & 2) ? -1 : +1;
                        if (waveX < 0) waveY *= -1;
                    }
                    setPixelTB(x - xoffset + xoffset_adj, yoffset - y - yoffset_adj + waveY - 1, c, wrapX);
                    break;
                }
                case PIC_TILE_LEFT: {
                    int xmult = (BufferWi + 2 * imgwidth) / std::max(imgwidth, 1);
                    int ymult = (BufferHt + 2 * imght) / std::max(imght, 1);
                    int startx = xoffset_adj - static_cast<int>(static_cast<float>(curPeriod - curEffStartPer) * movementSpeed) % std::max(imgwidth, 1);
                    int starty = yoffset_adj - imght;
                    for (int xx = 0; xx < xmult; ++xx)
                        for (int yy = 0; yy < ymult; ++yy)
                            setPixelTB(xx * imgwidth + x + startx, yy * imght + (imght - y - 1) + starty, c, false);
                    break;
                }
                case PIC_TILE_RIGHT: {
                    int xmult = (BufferWi + 2 * imgwidth) / std::max(imgwidth, 1);
                    int ymult = (BufferHt + 2 * imght) / std::max(imght, 1);
                    int startx = xoffset_adj - imgwidth + static_cast<int>(static_cast<float>(curPeriod - curEffStartPer) * movementSpeed) % std::max(imgwidth, 1);
                    int starty = yoffset_adj - imght;
                    for (int xx = 0; xx < xmult; ++xx)
                        for (int yy = 0; yy < ymult; ++yy)
                            setPixelTB(xx * imgwidth + x + startx, yy * imght + (imght - y - 1) + starty, c, false);
                    break;
                }
                case PIC_TILE_DOWN: {
                    int xmult = (BufferWi + 2 * imgwidth) / std::max(imgwidth, 1);
                    int ymult = (BufferHt + 2 * imght) / std::max(imght, 1);
                    int startx = xoffset_adj - imgwidth;
                    int starty = yoffset_adj - static_cast<int>(static_cast<float>(curPeriod - curEffStartPer) * movementSpeed) % std::max(imght, 1);
                    for (int xx = 0; xx < xmult; ++xx)
                        for (int yy = 0; yy < ymult; ++yy)
                            setPixelTB(xx * imgwidth + x + startx, yy * imght + (imght - y - 1) + starty, c, false);
                    break;
                }
                case PIC_TILE_UP: {
                    int xmult = (BufferWi + 2 * imgwidth) / std::max(imgwidth, 1);
                    int ymult = (BufferHt + 2 * imght) / std::max(imght, 1);
                    int startx = xoffset_adj - imgwidth;
                    int starty = yoffset_adj - imght + static_cast<int>(static_cast<float>(curPeriod - curEffStartPer) * movementSpeed) % std::max(imght, 1);
                    for (int xx = 0; xx < xmult; ++xx)
                        for (int yy = 0; yy < ymult; ++yy)
                            setPixelTB(xx * imgwidth + x + startx, yy * imght + (imght - y - 1) + starty, c, false);
                    break;
                }
                default:
                    setPixelTB(x - xoffset + xoffset_adj, yoffset + yoffset_adj - y - 1, c, wrapX);
                    break;
                }
            }
        }

        if (shimmer) {
            for (int x = 0; x < BufferWi; x++) {
                for (int y = 0; y < BufferHt; y++) {
                    if ((std::rand() % 100) > 50) {
                        xlColor existing;
                        buf.GetPixel(x, y, existing);
                        if (existing.red != 0 || existing.green != 0 || existing.blue != 0) {
                            buf.SetPixel(x, y, xlBLACK);
                        }
                    }
                }
            }
        }

        return true;
    }


    if (type == "Glediator") {
        // Native Glediator effect — port of legacy GlediatorEffect::Render
        // Reads binary frame data from .gled files (sequential raw RGB data)
        // or CSV files (one row per frame, comma-separated channel values).
        // Frame size for .gled = BufferWi * BufferHt * 3 bytes (RGB per pixel).

        std::string glediatorFilename;
        auto it = effectInfo.settings.find("E_FILEPICKERCTRL_Glediator_Filename");
        if (it != effectInfo.settings.end()) glediatorFilename = it->second;

        std::string durationTreatment = "Normal";
        it = effectInfo.settings.find("E_CHOICE_Glediator_DurationTreatment");
        if (it != effectInfo.settings.end() && !it->second.empty())
            durationTreatment = it->second;

        struct GlediatorCache : public EffectRenderCache {
            std::vector<uint8_t> fileData;
            std::string cachedFilename;
            size_t frameSize = 0;
            size_t frameCount = 0;
            int loops = 0;
            float frameMS = 50.0f;
            bool isCSV = false;
            std::vector<std::vector<uint8_t>> csvFrames;
        };

        GlediatorCache* cache = dynamic_cast<GlediatorCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new GlediatorCache();
            buf.infoCache[0] = cache;
        }

        int BufferWi = buf.BufferWi;
        int BufferHt = buf.BufferHt;

        auto getExtLower = [](const std::string& path) -> std::string {
            size_t dot = path.rfind('.');
            if (dot == std::string::npos) return "";
            std::string ext = path.substr(dot + 1);
            for (auto& ch : ext) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
            return ext;
        };

        if (buf.needToInit || cache->cachedFilename != glediatorFilename) {
            buf.needToInit = false;
            cache->loops = 0;
            cache->frameMS = static_cast<float>(buf.frameTimeInMs);
            cache->cachedFilename = glediatorFilename;
            cache->fileData.clear();
            cache->csvFrames.clear();
            cache->frameCount = 0;
            cache->frameSize = 0;
            cache->isCSV = false;

            if (!glediatorFilename.empty()) {
                std::string ext = getExtLower(glediatorFilename);
                cache->isCSV = (ext == "csv");

                if (cache->isCSV) {
                    std::ifstream csvFile(glediatorFilename);
                    if (csvFile.is_open()) {
                        std::string line;
                        while (std::getline(csvFile, line)) {
                            std::vector<uint8_t> frame;
                            std::istringstream ss(line);
                            std::string token;
                            while (std::getline(ss, token, ',')) {
                                if (!token.empty()) {
                                    frame.push_back(static_cast<uint8_t>(std::atoi(token.c_str())));
                                }
                            }
                            cache->csvFrames.push_back(std::move(frame));
                        }
                        cache->frameCount = cache->csvFrames.size();

                        if (durationTreatment == "Slow/Accelerate" && cache->frameCount > 0) {
                            size_t effectFrames = buf.curEffEndPer - buf.curEffStartPer + 1;
                            float speedFactor = (float)cache->frameCount / (float)effectFrames;
                            cache->frameMS = static_cast<float>(buf.frameTimeInMs) * speedFactor;
                        }
                    }
                } else {
                    cache->fileData = NativeImageLoader::LoadBinaryFile(glediatorFilename);
                    cache->frameSize = static_cast<size_t>(BufferWi) * BufferHt * 3;

                    if (cache->frameSize > 0 && !cache->fileData.empty()) {
                        cache->frameCount = cache->fileData.size() / cache->frameSize;

                        if (durationTreatment == "Slow/Accelerate" && cache->frameCount > 0) {
                            size_t effectFrames = buf.curEffEndPer - buf.curEffStartPer + 1;
                            float speedFactor = (float)cache->frameCount / (float)effectFrames;
                            cache->frameMS = static_cast<float>(buf.frameTimeInMs) * speedFactor;
                        }
                    }
                }
            }
        }

        if (cache->isCSV && !cache->csvFrames.empty()) {
            size_t frameCount = cache->csvFrames.size();
            size_t frame = static_cast<size_t>(
                static_cast<float>((buf.curPeriod - buf.curEffStartPer) - cache->loops * static_cast<int>(frameCount))
                * cache->frameMS / static_cast<float>(buf.frameTimeInMs));

            if (frame >= frameCount && durationTreatment == "Loop") {
                cache->loops++;
                frame = static_cast<size_t>(
                    static_cast<float>((buf.curPeriod - buf.curEffStartPer) - cache->loops * static_cast<int>(frameCount))
                    * cache->frameMS / static_cast<float>(buf.frameTimeInMs));
            }

            if (frame < frameCount) {
                const auto& frameData = cache->csvFrames[frame];
                size_t bufsize = static_cast<size_t>(BufferWi) * BufferHt;
                for (size_t j = 0; j < std::min(bufsize, frameData.size()); j++) {
                    uint8_t val = frameData[j];
                    xlColor color(val, val, val);
                    int x = static_cast<int>(j % BufferWi);
                    int y = (BufferHt - 1) - static_cast<int>(j / BufferWi);
                    if (x < BufferWi && y >= 0 && y < BufferHt) {
                        buf.SetPixel(x, y, color);
                    }
                }
            }
        } else if (!cache->fileData.empty() && cache->frameSize > 0 && cache->frameCount > 0) {
            size_t frame = static_cast<size_t>(
                static_cast<float>((buf.curPeriod - buf.curEffStartPer) - cache->loops * static_cast<int>(cache->frameCount))
                * cache->frameMS / static_cast<float>(buf.frameTimeInMs));

            if (frame >= cache->frameCount && durationTreatment == "Loop") {
                cache->loops++;
                frame = static_cast<size_t>(
                    static_cast<float>((buf.curPeriod - buf.curEffStartPer) - cache->loops * static_cast<int>(cache->frameCount))
                    * cache->frameMS / static_cast<float>(buf.frameTimeInMs));
            }

            if (frame >= cache->frameCount) {
                for (int y = 0; y < BufferHt; y++)
                    for (int x = 0; x < BufferWi; x++)
                        buf.SetPixel(x, y, xlBLACK);
            } else {
                size_t offset = frame * cache->frameSize;
                const uint8_t* frameData = cache->fileData.data() + offset;
                size_t bufsize = cache->frameSize;

                for (size_t j = 0; j + 2 < bufsize; j += 3) {
                    xlColor color(frameData[j], frameData[j + 1], frameData[j + 2]);
                    int x = static_cast<int>((j % (BufferWi * 3)) / 3);
                    int y = (BufferHt - 1) - static_cast<int>(j / (BufferWi * 3));
                    if (x < BufferWi && y >= 0 && y < BufferHt) {
                        buf.SetPixel(x, y, color);
                    }
                }
            }
        } else {
            for (int y = 0; y < BufferHt; y++)
                for (int x = 0; x < BufferWi; x++)
                    buf.SetPixel(x, y, xlRED);
        }

        return true;
    }

    if (type == "Music") {
        // Native Music effect — port of legacy MusicEffect::Render
        //
        // Displays audio spectrum data as animated bars. Each bar represents
        // a range of MIDI notes from the FFT analysis. Supports five display
        // modes: Morph, Bounce, Collide, Separate, and On.

        auto getStr = [&](const char* key, const char* def = "") -> std::string {
            auto it = effectInfo.settings.find(key);
            return (it != effectInfo.settings.end() && !it->second.empty()) ? it->second : def;
        };
        auto getInt = [&](const char* key, int def = 0) -> int {
            auto it = effectInfo.settings.find(key);
            return (it != effectInfo.settings.end() && !it->second.empty()) ? std::atoi(it->second.c_str()) : def;
        };
        auto getBool = [&](const char* key, bool def = false) -> bool {
            auto it = effectInfo.settings.find(key);
            if (it == effectInfo.settings.end() || it->second.empty()) return def;
            return it->second == "1" || it->second == "true" || it->second == "yes";
        };

        IAudioProvider* audio = buf.GetAudioProvider();
        if (!audio) return true;

        int bars = getInt("E_SLIDER_Music_Bars", 20);
        std::string musicType = getStr("E_CHOICE_Music_Type", "Morph");
        int sensitivity = getInt("E_SLIDER_Music_Sensitivity", 50);
        bool scale = getBool("E_CHECKBOX_Music_Scale", false);
        int offsetx = getInt("E_SLIDER_Music_Offset", 0);
        int startnote = getInt("E_SLIDER_Music_StartNote", 60);
        int endnote = getInt("E_SLIDER_Music_EndNote", 80);
        std::string colourtreatment = getStr("E_CHOICE_Music_Colour", "Distinct");
        bool fade = getBool("E_CHECKBOX_Music_Fade", false);

        if (startnote > endnote) std::swap(startnote, endnote);

        // Decode display type: 1=Morph, 2=Bounce, 3=Collide, 4=Separate, 5=On
        int nType = 1;
        if (musicType == "Morph") nType = 1;
        else if (musicType == "Bounce") nType = 2;
        else if (musicType == "Collide") nType = 3;
        else if (musicType == "Separate") nType = 4;
        else if (musicType == "On") nType = 5;

        // Decode colour treatment: 1=Distinct, 2=Blend, 3=Cycle
        int nTreatment = 1;
        if (colourtreatment == "Distinct") nTreatment = 1;
        else if (colourtreatment == "Blend") nTreatment = 2;
        else if (colourtreatment == "Cycle") nTreatment = 3;

        int actualbars = std::min(bars, std::min(endnote - startnote + 1, buf.BufferWi - offsetx));
        if (actualbars <= 0) actualbars = 1;
        int notesperbar = (endnote - startnote + 1) / actualbars;
        if (notesperbar <= 0) notesperbar = 1;
        float lightsperbar = (float)(buf.BufferWi - offsetx) / (float)actualbars;

        float per = scale ? lightsperbar : 1.0f;

        // Get current frame data
        int timeMS = buf.curPeriod * buf.frameTimeInMs;
        const AudioFrameData* frameData = audio->getFrameDataAtTime(timeMS);
        if (!frameData || frameData->vu.empty()) return true;

        float sns = (float)sensitivity / 100.0f;

        // For each bar, get the max spectrum value across its note range
        for (int b = 0; b < actualbars; b++) {
            int noteStart = startnote + b * notesperbar;
            int noteEnd = std::min(noteStart + notesperbar, (int)frameData->vu.size());

            float val = 0.0f;
            for (int n = noteStart; n < noteEnd && n < (int)frameData->vu.size(); n++) {
                val = std::max(val, frameData->vu[n]);
            }

            bool active = (val > sns);

            for (int xx = (int)((float)b * per) + offsetx;
                 xx < (int)((float)(b + 1) * per) + offsetx && xx < buf.BufferWi; xx++) {

                if (!active) continue;

                float progress = buf.GetEffectTimeIntervalPosition();

                switch (nType) {
                    case 1: // Morph - bars rise up
                    case 2: // Bounce - alternating direction
                    {
                        bool up = (b % 2 == 0) || nType == 1;
                        int length = buf.BufferHt;
                        int start = -1 * length + progress * 2 * length + 1;
                        int end = start + length;

                        for (int y = std::max(0, start); y < std::min(end, buf.BufferHt); y++) {
                            xlColor c = xlWHITE;
                            float proportion = ((float)end - (float)y) / (float)length;
                            if (nTreatment == 1) {
                                float percolour = 1.0f / (float)buf.GetColorCount();
                                for (size_t i = 0; i < buf.GetColorCount(); i++) {
                                    if (proportion <= ((float)i + 1.0f) * percolour) {
                                        buf.palette.GetColor(i, c);
                                        break;
                                    }
                                }
                            } else if (nTreatment == 2) {
                                buf.GetMultiColorBlend(proportion, false, c);
                            } else if (nTreatment == 3) {
                                buf.palette.GetColor(b % buf.GetColorCount(), c);
                            }
                            if (fade) c.alpha = (1.0f - proportion) * 255;

                            if (up) buf.SetPixel(xx, y, c);
                            else buf.SetPixel(xx, buf.BufferHt - y - 1, c);
                        }
                        break;
                    }
                    case 3: // Collide - from both edges toward center
                    {
                        int mid = buf.BufferHt / 2;
                        int length = buf.BufferHt;
                        int leftstart = 0 - mid - 1 + progress * length;
                        int leftend = leftstart + mid;
                        if (leftend > mid) leftend = mid;
                        int loopstart = std::max(0, leftstart);

                        for (int y = loopstart; y < leftend; y++) {
                            xlColor c = xlWHITE;
                            float proportion = ((float)y - (float)leftstart) / (float)mid;
                            if (nTreatment == 1) {
                                float percolour = 1.0f / (float)buf.GetColorCount();
                                for (size_t i = 0; i < buf.GetColorCount(); i++) {
                                    if (proportion <= ((float)i + 1.0f) * percolour) {
                                        buf.palette.GetColor(i, c);
                                        break;
                                    }
                                }
                            } else if (nTreatment == 2) {
                                buf.GetMultiColorBlend(proportion, false, c);
                            } else if (nTreatment == 3) {
                                buf.palette.GetColor(b % buf.GetColorCount(), c);
                            }
                            if (fade) c.alpha = progress * 255;

                            buf.SetPixel(xx, y, c);
                            buf.SetPixel(xx, mid - y + mid - 1, c);
                        }
                        break;
                    }
                    case 4: // Separate - from center outward (inverse collide)
                    {
                        float invProgress = 1.0f - progress;
                        int mid = buf.BufferHt / 2;
                        int length = buf.BufferHt;
                        int leftstart = 0 - mid - 1 + invProgress * length;
                        int leftend = leftstart + mid;
                        if (leftend > mid) leftend = mid;
                        int loopstart = std::max(0, leftstart);

                        for (int y = loopstart; y < leftend; y++) {
                            xlColor c = xlWHITE;
                            float proportion = ((float)y - (float)leftstart) / (float)mid;
                            if (nTreatment == 1) {
                                float percolour = 1.0f / (float)buf.GetColorCount();
                                for (size_t i = 0; i < buf.GetColorCount(); i++) {
                                    if (proportion <= ((float)i + 1.0f) * percolour) {
                                        buf.palette.GetColor(i, c);
                                        break;
                                    }
                                }
                            } else if (nTreatment == 2) {
                                buf.GetMultiColorBlend(proportion, false, c);
                            } else if (nTreatment == 3) {
                                buf.palette.GetColor(b % buf.GetColorCount(), c);
                            }
                            if (fade) c.alpha = invProgress * 255;

                            buf.SetPixel(xx, y, c);
                            buf.SetPixel(xx, mid - y + mid - 1, c);
                        }
                        break;
                    }
                    case 5: // On - full height when active
                    {
                        for (int y = 0; y < buf.BufferHt; y++) {
                            xlColor c = xlWHITE;
                            float proportion = (float)y / (float)buf.BufferHt;
                            if (nTreatment == 1) {
                                float percolour = 1.0f / (float)buf.GetColorCount();
                                for (size_t i = 0; i < buf.GetColorCount(); i++) {
                                    if (proportion <= ((float)i + 1.0f) * percolour) {
                                        buf.palette.GetColor(i, c);
                                        break;
                                    }
                                }
                            } else if (nTreatment == 2) {
                                buf.GetMultiColorBlend(proportion, false, c);
                            } else if (nTreatment == 3) {
                                buf.palette.GetColor(b % buf.GetColorCount(), c);
                            }
                            if (fade) c.alpha = (1.0f - progress) * 255;
                            buf.SetPixel(xx, y, c);
                        }
                        break;
                    }
                }
            }
        }

        return true;
    }

    if (type == "VU Meter") {
        // Native VU Meter effect — port of legacy VUMeterEffect::Render
        //
        // Comprehensive audio-reactive effect with many display sub-types.
        // Timing-event sub-types are NOT supported in the native pipeline
        // (they require SequenceElements/EffectLayer data not available here).
        // All audio-level and note-level sub-types are fully implemented.

        auto getStr = [&](const char* key, const char* def = "") -> std::string {
            auto it = effectInfo.settings.find(key);
            return (it != effectInfo.settings.end() && !it->second.empty()) ? it->second : def;
        };
        auto getInt = [&](const char* key, int def = 0) -> int {
            auto it = effectInfo.settings.find(key);
            return (it != effectInfo.settings.end() && !it->second.empty()) ? std::atoi(it->second.c_str()) : def;
        };
        auto getBool = [&](const char* key, bool def = false) -> bool {
            auto it = effectInfo.settings.find(key);
            if (it == effectInfo.settings.end() || it->second.empty()) return def;
            return it->second == "1" || it->second == "true" || it->second == "yes";
        };

        // ApplyGain helper — matches legacy VUMeterEffect::ApplyGain
        auto applyGain = [](float value, int gain) -> float {
            float v = (100.0f + gain) * value / 100.0f;
            if (v > 1.0f) v = 1.0f;
            return v;
        };

        IAudioProvider* audio = buf.GetAudioProvider();
        if (!audio) return true;

        int bars = getInt("E_SLIDER_VUMeter_Bars", 6);
        std::string vuType = getStr("E_CHOICE_VUMeter_Type", "Waveform");
        int sensitivity = getInt("E_SLIDER_VUMeter_Sensitivity", 70);
        std::string shape = getStr("E_CHOICE_VUMeter_Shape", "Circle");
        bool slowdownfalls = getBool("E_CHECKBOX_VUMeter_SlowDownFalls", true);
        int startnote = getInt("E_SLIDER_VUMeter_StartNote", 0);
        int endnote = getInt("E_SLIDER_VUMeter_EndNote", 127);
        int xoffset = getInt("E_SLIDER_VUMeter_XOffset", 0);
        int yoffset = getInt("E_SLIDER_VUMeter_YOffset", 0);
        int gain = getInt("E_SLIDER_VUMeter_Gain", 0);

        if (startnote > endnote) std::swap(startnote, endnote);

        int usebars = bars;
        // For most types, limit bars to buffer width
        if (vuType != "Level Jump" && vuType != "Level Jump 100") {
            if (usebars > buf.BufferWi) usebars = buf.BufferWi;
        }

        // Render cache for stateful VUMeter sub-types
        struct VUMeterCache : public EffectRenderCache {
            std::vector<float> lastvalues;
            std::vector<float> lastpeaks;
            float lastsize = 0.0f;
            int colourindex = -1;
            int lasttimingmark = -1;
            float lastbar = 0.0f;
            float lastVal = 0.0f;
        };

        VUMeterCache* cache = dynamic_cast<VUMeterCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new VUMeterCache();
            buf.infoCache[0] = cache;
        }

        if (buf.needToInit) {
            buf.needToInit = false;
            cache->lastvalues.clear();
            cache->lastpeaks.clear();
            cache->lastsize = 0.0f;
            cache->colourindex = -1;
            cache->lasttimingmark = -1;
            cache->lastbar = 0.0f;
            cache->lastVal = 0.0f;
        }

        int timeMS = buf.curPeriod * buf.frameTimeInMs;
        const AudioFrameData* frameData = audio->getFrameDataAtTime(timeMS);

        // ---------------------------------------------------------------
        // Volume Bars — historical volume level columns scrolling left
        // ---------------------------------------------------------------
        if (vuType == "Volume Bars") {
            if (usebars == 0) usebars = 1;
            int start = buf.curPeriod - usebars;
            float cols = (float)buf.BufferWi / (float)usebars;
            if (cols <= 0.0f) cols = 0.001f;
            for (int x = 0; x < buf.BufferWi; x++) {
                int i = start + (int)((float)x / cols);
                if (i > 0) {
                    float f = 0.0f;
                    const AudioFrameData* pf = audio->getFrameData(i);
                    if (pf) f = applyGain(pf->max, gain);
                    int colheight = buf.BufferHt * f;
                    for (int y = 0; y < colheight; y++) {
                        xlColor color1;
                        buf.GetMultiColorBlend((double)y / (double)buf.BufferHt, false, color1);
                        buf.SetPixel(x, y, color1);
                    }
                }
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Waveform — historical min/max envelope display
        // ---------------------------------------------------------------
        if (vuType == "Waveform") {
            int trueyoffset = yoffset * buf.BufferHt / 2 / 100;
            int start = buf.curPeriod - usebars;
            float cols = (float)buf.BufferWi / usebars;
            int x = 0;
            for (int i = 0; i < usebars; i++) {
                if (start + i >= 0) {
                    float fh = 0.0f, fl = 0.0f;
                    const AudioFrameData* pf = audio->getFrameData(start + i);
                    if (pf) {
                        fh = applyGain(pf->max, gain);
                        fl = applyGain(pf->min, gain);
                    }
                    int s = (1.0f - fl) * buf.BufferHt / 2;
                    int e = (1.0f + fh) * buf.BufferHt / 2;
                    if (e < s) e = s;
                    if (e > buf.BufferHt) e = buf.BufferHt;
                    for (int j = 0; j < (int)cols; j++) {
                        for (int y = s; y < e; y++) {
                            xlColor color1;
                            buf.GetMultiColorBlend((double)y / (double)buf.BufferHt, false, color1);
                            buf.SetPixel(x, y + trueyoffset, color1);
                        }
                        x++;
                    }
                } else {
                    x += (int)cols;
                }
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Frame Waveform — per-sample waveform within current frame
        // ---------------------------------------------------------------
        if (vuType == "Frame Waveform") {
            int trueyoffset = yoffset * buf.BufferHt / 2 / 100;
            float barms = (float)buf.frameTimeInMs / usebars;
            long rate = audio->getSampleRate();
            float startMS = buf.curPeriod * buf.frameTimeInMs;
            xlColor color = buf.palette.GetColor(0);
            int lasty = trueyoffset + buf.BufferHt / 2;
            int lastx = 0;
            float cols = (float)buf.BufferWi / usebars;
            bool up = true;
            for (int i = 0; i < usebars; i++) {
                float mn = 0.0f, mx = 0.0f;
                long startSample = (long)(rate * (startMS + (float)i * barms) / 1000.0f);
                long endSample = (long)(rate * (startMS + (float)(i + 1) * barms) / 1000.0f);
                audio->getLeftDataMinMax(startSample, endSample, mn, mx);

                int y;
                int x = (int)((float)i * cols + cols / 2.0f);
                if (up) {
                    mx = applyGain(mx, gain);
                    y = trueyoffset + buf.BufferHt / 2 + (int)(mx * ((float)buf.BufferHt / 2.0f));
                } else {
                    mn = applyGain(mn, gain);
                    y = trueyoffset + buf.BufferHt / 2 + (int)(mn * ((float)buf.BufferHt / 2.0f));
                }
                buf.DrawLine(lastx, lasty, x, y, color);
                lasty = y;
                lastx = x;
                if (i == usebars - 1) {
                    buf.DrawLine(lastx, lasty, buf.BufferWi - 1, trueyoffset + buf.BufferHt / 2, color);
                }
                up = !up;
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Spectrogram / Spectrogram Peak — frequency bars
        // ---------------------------------------------------------------
        if (vuType == "Spectrogram" || vuType == "Spectrogram Peak") {
            if (!frameData || frameData->vu.empty()) return true;

            bool peak = (vuType == "Spectrogram Peak");
            int noteRange = endnote - startnote + 1;
            if (noteRange <= 0) return true;
            if (usebars <= 0) usebars = 1;
            int notesPerBar = std::max(1, noteRange / usebars);
            int actualBars = std::min(usebars, noteRange);

            // Ensure lastvalues/lastpeaks are sized correctly
            if ((int)cache->lastvalues.size() != actualBars) {
                cache->lastvalues.resize(actualBars, 0.0f);
                cache->lastpeaks.resize(actualBars, 0.0f);
            }

            float cols = (float)buf.BufferWi / (float)actualBars;

            for (int b = 0; b < actualBars; b++) {
                int noteStart = startnote + b * notesPerBar;
                int noteEnd = std::min(noteStart + notesPerBar, (int)frameData->vu.size());

                float val = 0.0f;
                for (int n = noteStart; n < noteEnd; n++) {
                    val = std::max(val, frameData->vu[n]);
                }
                val = applyGain(val, gain);

                // Slow-down-falls for bar values
                if (slowdownfalls) {
                    if (val < cache->lastvalues[b]) {
                        cache->lastvalues[b] -= 1.0f / (float)buf.BufferHt;
                        if (cache->lastvalues[b] < val) cache->lastvalues[b] = val;
                    } else {
                        cache->lastvalues[b] = val;
                    }
                } else {
                    cache->lastvalues[b] = val;
                }

                // Peak tracking
                if (peak) {
                    if (val > cache->lastpeaks[b]) {
                        cache->lastpeaks[b] = val;
                    } else {
                        cache->lastpeaks[b] -= 1.0f / (float)(sensitivity > 0 ? sensitivity : 1);
                        if (cache->lastpeaks[b] < 0) cache->lastpeaks[b] = 0;
                    }
                }

                int colheight = (int)(cache->lastvalues[b] * buf.BufferHt);
                int startx = (int)(b * cols) + xoffset;
                int endx = (int)((b + 1) * cols) + xoffset;

                for (int x = startx; x < endx && x < buf.BufferWi; x++) {
                    if (x < 0) continue;
                    for (int y = 0; y < colheight && y < buf.BufferHt; y++) {
                        xlColor color1;
                        buf.GetMultiColorBlend((double)y / (double)buf.BufferHt, false, color1);
                        buf.SetPixel(x, y + yoffset, color1);
                    }
                    if (peak) {
                        int peaky = (int)(cache->lastpeaks[b] * buf.BufferHt) + yoffset;
                        if (peaky >= 0 && peaky < buf.BufferHt) {
                            xlColor peakColor;
                            buf.palette.GetColor(0, peakColor);
                            buf.SetPixel(x, peaky, peakColor);
                        }
                    }
                }
            }
            return true;
        }

        // ---------------------------------------------------------------
        // On — brightness modulated by audio level
        // ---------------------------------------------------------------
        if (vuType == "On") {
            float f = 0.0f;
            if (frameData) f = applyGain(frameData->max, gain);
            xlColor color1;
            buf.palette.GetColor(0, color1);
            color1.alpha = f * 255.0f;
            for (int x = 0; x < buf.BufferWi; x++)
                for (int y = 0; y < buf.BufferHt; y++)
                    buf.SetPixel(x, y, color1);
            return true;
        }

        // ---------------------------------------------------------------
        // Color On — level maps to palette blend
        // ---------------------------------------------------------------
        if (vuType == "Color On") {
            float f = 0.0f;
            if (frameData) f = applyGain(frameData->max, gain);
            xlColor color1;
            buf.GetMultiColorBlend(f, false, color1);
            for (int x = 0; x < buf.BufferWi; x++)
                for (int y = 0; y < buf.BufferHt; y++)
                    buf.SetPixel(x, y, color1);
            return true;
        }

        // ---------------------------------------------------------------
        // Intensity Wave — historical intensity blocks
        // ---------------------------------------------------------------
        if (vuType == "Intensity Wave") {
            int start = buf.curPeriod - usebars;
            int cols = buf.BufferWi / std::max(1, usebars);
            int x = 0;
            for (int i = 0; i < usebars; i++) {
                if (start + i >= 0) {
                    float f = 0.0f;
                    const AudioFrameData* pf = audio->getFrameData(start + i);
                    if (pf) f = applyGain(pf->max, gain);
                    xlColor color1;
                    if (buf.palette.Size() < 2) {
                        buf.palette.GetColor(0, color1);
                        color1.alpha = f * 255.0f;
                    } else {
                        buf.GetMultiColorBlend(1.0f - f, false, color1);
                    }
                    for (int j = 0; j < cols; j++) {
                        for (int y = 0; y < buf.BufferHt; y++)
                            buf.SetPixel(x, y, color1);
                        x++;
                    }
                } else {
                    x += cols;
                }
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Level Pulse — fading pulse on level threshold
        // ---------------------------------------------------------------
        if (vuType == "Level Pulse") {
            float f = 0.0f;
            if (frameData) f = applyGain(frameData->max, gain);
            if (f > (float)sensitivity / 100.0f) {
                cache->lasttimingmark = buf.curPeriod;
            }
            int fadeframes = usebars;
            if (fadeframes > 0 && buf.curPeriod - cache->lasttimingmark < fadeframes) {
                float ff = 1.0f - (((float)buf.curPeriod - (float)cache->lasttimingmark) / (float)fadeframes);
                if (ff < 0) ff = 0;
                if (ff > 0.0f) {
                    xlColor color1;
                    buf.palette.GetColor(0, color1);
                    color1.alpha = ff * 255.0f;
                    for (int x = 0; x < buf.BufferWi; x++)
                        for (int y = 0; y < buf.BufferHt; y++)
                            buf.SetPixel(x, y, color1);
                }
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Level Pulse Color — fading pulse with color cycling
        // ---------------------------------------------------------------
        if (vuType == "Level Pulse Color") {
            float f = 0.0f;
            if (frameData) f = applyGain(frameData->max, gain);
            if (f > (float)sensitivity / 100.0f) {
                if (cache->lasttimingmark != buf.curPeriod - 1) {
                    cache->colourindex++;
                    if (cache->colourindex >= (int)buf.GetColorCount()) cache->colourindex = 0;
                }
                cache->lasttimingmark = buf.curPeriod;
            }
            int fadeframes = usebars;
            if (fadeframes > 0 && buf.curPeriod - cache->lasttimingmark < fadeframes) {
                float ff = 1.0f - (((float)buf.curPeriod - (float)cache->lasttimingmark) / (float)fadeframes);
                if (ff < 0) ff = 0;
                if (ff > 0.0f) {
                    xlColor color1;
                    buf.palette.GetColor(std::max(0, cache->colourindex), color1);
                    color1.alpha = ff * 255.0f;
                    for (int x = 0; x < buf.BufferWi; x++)
                        for (int y = 0; y < buf.BufferHt; y++)
                            buf.SetPixel(x, y, color1);
                }
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Level Color — color cycling on threshold
        // ---------------------------------------------------------------
        if (vuType == "Level Color") {
            float f = 0.0f;
            if (frameData) f = applyGain(frameData->max, gain);
            if (f > (float)sensitivity / 100.0f) {
                if (cache->lasttimingmark != buf.curPeriod - 1) {
                    cache->colourindex++;
                    if (cache->colourindex >= (int)buf.GetColorCount()) cache->colourindex = 0;
                }
                cache->lasttimingmark = buf.curPeriod;
            }
            if (cache->colourindex >= 0) {
                xlColor color1;
                buf.palette.GetColor(cache->colourindex, color1);
                for (int x = 0; x < buf.BufferWi; x++)
                    for (int y = 0; y < buf.BufferHt; y++)
                        buf.SetPixel(x, y, color1);
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Level Jump / Level Jump 100 — jumping bar on level threshold
        // ---------------------------------------------------------------
        if (vuType == "Level Jump" || vuType == "Level Jump 100") {
            bool fullJump = (vuType == "Level Jump 100");
            float f = 0.0f;
            if (frameData) f = applyGain(frameData->max, gain);
            if (f > (float)sensitivity / 100.0f) {
                cache->lasttimingmark = buf.curPeriod;
                cache->lastVal = fullJump ? 1.0f : f;
            }
            int fadeframes = usebars;
            if (fadeframes > 0 && buf.curPeriod - cache->lasttimingmark < fadeframes) {
                float ff = cache->lastVal - (cache->lastVal * ((float)buf.curPeriod - (float)cache->lasttimingmark) / (float)fadeframes);
                if (ff < 0) ff = 0;
                if (ff > 0.0f) {
                    for (int y = 0; y < ff * (float)buf.BufferHt; y++) {
                        xlColor color1;
                        buf.GetMultiColorBlend((float)y / (float)buf.BufferHt, false, color1);
                        for (int x = 0; x < buf.BufferWi; x++)
                            buf.SetPixel(x, y, color1);
                    }
                }
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Level Bar / Level Random Bar — bar on beat
        // ---------------------------------------------------------------
        if (vuType == "Level Bar" || vuType == "Level Random Bar") {
            bool random = (vuType == "Level Random Bar");
            if (!frameData) return true;
            float level = applyGain(frameData->max, gain);
            if (level > (float)sensitivity / 100.0f) {
                cache->colourindex++;
                if (cache->colourindex >= (int)buf.GetColorCount()) cache->colourindex = 0;
                if (random && usebars > 2) {
                    int lb = (int)cache->lastbar + 1;
                    while (lb == (int)cache->lastbar + 1) {
                        cache->lastbar = 1.0f + static_cast<int>((double)std::rand() / RAND_MAX * usebars);
                    }
                    if (cache->lastbar > usebars) cache->lastbar = 1;
                } else {
                    cache->lastbar++;
                    if (cache->lastbar > usebars) cache->lastbar = 1;
                }
            }
            int bar = (int)cache->lastbar - 1;
            xlColor color1;
            buf.palette.GetColor(std::max(0, cache->colourindex), color1);
            int startx = buf.BufferWi / std::max(1, usebars) * bar;
            int endx = (int)std::ceil((float)buf.BufferWi / std::max(1, usebars)) * (bar + 1);
            if (endx > buf.BufferWi) endx = buf.BufferWi;
            if (bar >= 0) {
                for (int x = startx; x < endx; x++)
                    for (int y = 0; y < buf.BufferHt; y++)
                        buf.SetPixel(x, y, color1);
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Level Shape — shape whose size is modulated by audio level
        // ---------------------------------------------------------------
        if (vuType == "Level Shape") {
            if (!frameData) return true;
            float f = applyGain(frameData->max, gain);

            int truexoffset = xoffset * buf.BufferWi / 2 / 100;
            int trueyoffset = yoffset * buf.BufferHt / 2 / 100;
            float scaling = (float)sensitivity / 100.0f * 7.0f;

            int centerx = buf.BufferWi / 2 + truexoffset;
            int centery = buf.BufferHt / 2 + trueyoffset;

            float maxSize = std::min(buf.BufferHt / 2.0f, buf.BufferWi / 2.0f) * scaling;
            float size = maxSize * f;

            if (slowdownfalls) {
                if (size < cache->lastsize) {
                    cache->lastsize -= std::min(maxSize, (float)std::max(buf.BufferHt / 2.0f, buf.BufferWi / 2.0f)) / 20.0f;
                    if (cache->lastsize < size) cache->lastsize = size;
                } else {
                    cache->lastsize = size;
                }
            } else {
                cache->lastsize = size;
            }

            float ls = cache->lastsize;

            // Star points
            int points = std::min(99, usebars) / 25 + 4;

            if (shape == "Circle") {
                xlColor color1;
                buf.palette.GetColor(0, color1);
                color1.alpha = 64;
                buf.DrawCircle(centerx, centery, (int)(ls - 2), color1);
                buf.DrawCircle(centerx, centery, (int)(ls + 2), color1);
                color1.alpha = 128;
                buf.DrawCircle(centerx, centery, (int)(ls - 1), color1);
                buf.DrawCircle(centerx, centery, (int)(ls + 1), color1);
                color1.alpha = 255;
                buf.DrawCircle(centerx, centery, (int)ls, color1);
            } else if (shape == "Filled Circle") {
                for (int r = 0; r <= (int)ls; r++) {
                    float distance = (ls > 0) ? (float)r / ls : 0;
                    xlColor color1;
                    buf.GetMultiColorBlend(distance, false, color1);
                    buf.DrawCircle(centerx, centery, r, color1, true);
                }
            } else if (shape == "Square") {
                int sx = centerx - (int)(ls / 2.0f);
                int ex = centerx + (int)(ls / 2.0f);
                int sy = centery - (int)(ls / 2.0f);
                int ey = centery + (int)(ls / 2.0f);
                xlColor color1;
                buf.palette.GetColor(0, color1);
                color1.alpha = 64;
                buf.DrawBox(sx - 2, sy - 2, ex + 2, ey + 2, color1);
                buf.DrawBox(sx + 2, sy + 2, ex - 2, ey - 2, color1);
                color1.alpha = 128;
                buf.DrawBox(sx - 1, sy - 1, ex + 1, ey + 1, color1);
                buf.DrawBox(sx + 1, sy + 1, ex - 1, ey - 1, color1);
                color1.alpha = 255;
                buf.DrawBox(sx, sy, ex, ey, color1);
            } else if (shape == "Filled Square") {
                int sx = centerx - (int)(ls / 2.0f);
                int ex = centerx + (int)(ls / 2.0f);
                int sy = centery - (int)(ls / 2.0f);
                int ey = centery + (int)(ls / 2.0f);
                for (int r = 0; r <= (int)(ls / 2.0f); r++) {
                    float distance = (ls > 0) ? r / (ls / 2.0f) : 0;
                    xlColor color1;
                    buf.GetMultiColorBlend(distance, false, color1);
                    buf.DrawBox(sx + r, sy + r, ex - r, ey - r, color1);
                }
            } else if (shape == "Diamond") {
                xlColor color1;
                buf.palette.GetColor(0, color1);
                auto drawDiamond = [&](int cx, int cy, int sz, xlColor c) {
                    if (sz <= 0) return;
                    buf.DrawLine(cx - sz, cy, cx, cy + sz, c);
                    buf.DrawLine(cx, cy + sz, cx + sz, cy, c);
                    buf.DrawLine(cx + sz, cy, cx, cy - sz, c);
                    buf.DrawLine(cx, cy - sz, cx - sz, cy, c);
                };
                color1.alpha = 64;
                drawDiamond(centerx, centery, (int)ls - 2, color1);
                drawDiamond(centerx, centery, (int)ls + 2, color1);
                color1.alpha = 128;
                drawDiamond(centerx, centery, (int)ls - 1, color1);
                drawDiamond(centerx, centery, (int)ls + 1, color1);
                color1.alpha = 255;
                drawDiamond(centerx, centery, (int)ls, color1);
            } else if (shape == "Filled Diamond") {
                auto drawDiamond = [&](int cx, int cy, int sz, xlColor c) {
                    if (sz <= 0) return;
                    buf.DrawLine(cx - sz, cy, cx, cy + sz, c);
                    buf.DrawLine(cx, cy + sz, cx + sz, cy, c);
                    buf.DrawLine(cx + sz, cy, cx, cy - sz, c);
                    buf.DrawLine(cx, cy - sz, cx - sz, cy, c);
                };
                for (int r = 0; r <= (int)ls; r++) {
                    xlColor color1;
                    buf.GetMultiColorBlend((ls > 0) ? (float)r / ls : 0, false, color1);
                    drawDiamond(centerx, centery, r, color1);
                }
            } else if (shape == "Star" || shape == "Filled Star") {
                auto drawStar = [&](int cx, int cy, float radius, xlColor c, int pts) {
                    if (radius <= 0 || pts < 3) return;
                    float innerRadius = radius * 0.4f;
                    for (int i = 0; i < pts * 2; i++) {
                        float angle1 = (float)i * M_PI / pts - M_PI / 2.0f;
                        float angle2 = (float)(i + 1) * M_PI / pts - M_PI / 2.0f;
                        float r1 = (i % 2 == 0) ? radius : innerRadius;
                        float r2 = ((i + 1) % 2 == 0) ? radius : innerRadius;
                        int x1 = cx + (int)(r1 * std::cos(angle1));
                        int y1 = cy + (int)(r1 * std::sin(angle1));
                        int x2 = cx + (int)(r2 * std::cos(angle2));
                        int y2 = cy + (int)(r2 * std::sin(angle2));
                        buf.DrawLine(x1, y1, x2, y2, c);
                    }
                };
                if (shape == "Star") {
                    xlColor color1;
                    buf.palette.GetColor(0, color1);
                    color1.alpha = 64;
                    drawStar(centerx, centery, ls - 2, color1, points);
                    drawStar(centerx, centery, ls + 2, color1, points);
                    color1.alpha = 128;
                    drawStar(centerx, centery, ls - 1, color1, points);
                    drawStar(centerx, centery, ls + 1, color1, points);
                    color1.alpha = 255;
                    drawStar(centerx, centery, ls, color1, points);
                } else {
                    for (float r = 0; r <= ls; r += 0.5f) {
                        xlColor color1;
                        buf.GetMultiColorBlend((ls > 0) ? r / ls : 0, false, color1);
                        drawStar(centerx, centery, r, color1, points);
                    }
                }
            } else {
                // Default: filled circle for any unrecognized shape
                for (int r = 0; r <= (int)ls; r++) {
                    float distance = (ls > 0) ? (float)r / ls : 0;
                    xlColor color1;
                    buf.GetMultiColorBlend(distance, false, color1);
                    buf.DrawCircle(centerx, centery, r, color1, true);
                }
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Note On — alpha based on note activity in range
        // ---------------------------------------------------------------
        if (vuType == "Note On") {
            if (!frameData || frameData->vu.empty()) return true;
            float level = 0.0f;
            for (int i = startnote; i <= endnote && i < (int)frameData->vu.size(); i++) {
                level = std::max(level, frameData->vu[i]);
            }
            level = applyGain(level, gain);
            xlColor color1;
            buf.palette.GetColor(0, color1);
            color1.alpha = level * 255.0f;
            for (int x = 0; x < buf.BufferWi; x++)
                for (int y = 0; y < buf.BufferHt; y++)
                    buf.SetPixel(x, y, color1);
            return true;
        }

        // ---------------------------------------------------------------
        // Note Level Pulse — fading pulse triggered by note range level
        // ---------------------------------------------------------------
        if (vuType == "Note Level Pulse") {
            if (!frameData || frameData->vu.empty()) return true;
            float level = 0.0f;
            for (int i = startnote; i <= endnote && i < (int)frameData->vu.size(); i++) {
                level = std::max(level, frameData->vu[i]);
            }
            level = applyGain(level, gain);
            if (level > (float)sensitivity / 100.0f) {
                cache->lasttimingmark = buf.curPeriod;
            }
            int fadeframes = usebars;
            if (fadeframes > 0 && buf.curPeriod - cache->lasttimingmark < fadeframes) {
                float ff = 1.0f - (((float)buf.curPeriod - (float)cache->lasttimingmark) / (float)fadeframes);
                if (ff < 0) ff = 0;
                if (ff > 0.0f) {
                    xlColor color1;
                    buf.palette.GetColor(0, color1);
                    color1.alpha = ff * 255.0f;
                    for (int x = 0; x < buf.BufferWi; x++)
                        for (int y = 0; y < buf.BufferHt; y++)
                            buf.SetPixel(x, y, color1);
                }
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Note Level Jump / Note Level Jump 100
        // ---------------------------------------------------------------
        if (vuType == "Note Level Jump" || vuType == "Note Level Jump 100") {
            bool fullJump = (vuType == "Note Level Jump 100");
            if (!frameData || frameData->vu.empty()) return true;
            float level = 0.0f;
            for (int i = startnote; i <= endnote && i < (int)frameData->vu.size(); i++) {
                level = std::max(level, frameData->vu[i]);
            }
            level = applyGain(level, gain);
            if (level > (float)sensitivity / 100.0f) {
                cache->lasttimingmark = buf.curPeriod;
                cache->lastVal = fullJump ? 1.0f : level;
            }
            int fadeframes = usebars;
            if (fadeframes > 0 && buf.curPeriod - cache->lasttimingmark < fadeframes) {
                float ff = cache->lastVal - (cache->lastVal * ((float)buf.curPeriod - (float)cache->lasttimingmark) / (float)fadeframes);
                if (ff < 0) ff = 0;
                if (ff > 0.0f) {
                    for (int y = 0; y < (int)(ff * buf.BufferHt); y++) {
                        xlColor color1;
                        buf.GetMultiColorBlend((float)y / (float)buf.BufferHt, false, color1);
                        for (int x = 0; x < buf.BufferWi; x++)
                            buf.SetPixel(x, y, color1);
                    }
                }
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Note Level Bar / Note Level Random Bar
        // ---------------------------------------------------------------
        if (vuType == "Note Level Bar" || vuType == "Note Level Random Bar") {
            bool random = (vuType == "Note Level Random Bar");
            if (!frameData || frameData->vu.empty()) return true;
            float level = 0.0f;
            for (int i = startnote; i <= endnote && i < (int)frameData->vu.size(); i++) {
                level = std::max(level, frameData->vu[i]);
            }
            level = applyGain(level, gain);
            if (level > (float)sensitivity / 100.0f) {
                cache->colourindex++;
                if (cache->colourindex >= (int)buf.GetColorCount()) cache->colourindex = 0;
                if (random && usebars > 2) {
                    int lb = (int)cache->lastbar + 1;
                    while (lb == (int)cache->lastbar + 1) {
                        cache->lastbar = 1.0f + static_cast<int>((double)std::rand() / RAND_MAX * usebars);
                    }
                    if (cache->lastbar > usebars) cache->lastbar = 1;
                } else {
                    cache->lastbar++;
                    if (cache->lastbar > usebars) cache->lastbar = 1;
                }
            }
            int bar = (int)cache->lastbar - 1;
            xlColor color1;
            buf.palette.GetColor(std::max(0, cache->colourindex), color1);
            int startx = buf.BufferWi / std::max(1, usebars) * bar;
            int endx = (int)std::ceil((float)buf.BufferWi / std::max(1, usebars)) * (bar + 1);
            if (endx > buf.BufferWi) endx = buf.BufferWi;
            if (bar >= 0) {
                for (int x = startx; x < endx; x++)
                    for (int y = 0; y < buf.BufferHt; y++)
                        buf.SetPixel(x, y, color1);
            }
            return true;
        }

        // ---------------------------------------------------------------
        // Dominant Frequency Colour / Gradient
        // ---------------------------------------------------------------
        if (vuType == "Dominant Frequency Colour" || vuType == "Dominant Frequency Colour Gradient") {
            bool gradient = (vuType == "Dominant Frequency Colour Gradient");
            if (!frameData || frameData->vu.empty()) return true;
            float sns = (float)sensitivity / 100.0f;
            int note = -1;
            float maxVal = -1000.0f;
            for (int i = startnote; i <= endnote && i < (int)frameData->vu.size(); i++) {
                if (frameData->vu[i] > sns && frameData->vu[i] > maxVal) {
                    maxVal = frameData->vu[i];
                    note = i;
                }
            }
            if (note >= 0) {
                xlColor color1;
                if (gradient) {
                    buf.GetMultiColorBlend((float)(note - startnote) / (float)(endnote - startnote + 1), false, color1);
                } else {
                    int numcolours = buf.palette.Size();
                    int colour = (float)((note - startnote) * numcolours) / (float)(endnote - startnote + 1);
                    color1 = buf.palette.GetColor(colour);
                }
                for (int x = 0; x < buf.BufferWi; x++)
                    for (int y = 0; y < buf.BufferHt; y++)
                        buf.SetPixel(x, y, color1);
            }
            return true;
        }

        // Unrecognized VUMeter sub-type (likely a timing-event type not supported in native)
        return true;
    }

    if (type == "Arpeggio") {
        // Native Arpeggio effect — port of legacy ArpeggioEffect::Render
        //
        // Creates a step-sequencer-like arpeggio pattern that sweeps through
        // note positions. Supports both the native panel settings (BPM, Steps,
        // StartNote, EndNote) and legacy settings (TimingTrack, AutoSplit,
        // PropsPerStep, Order, Pattern, etc.) for backward compatibility.
        //
        // Native panel settings:
        //   E_SLIDER_Arpeggio_BPM       (1-300, default 120)
        //   E_SLIDER_Arpeggio_Steps     (1-16, default 8)
        //   E_SLIDER_Arpeggio_StartNote (0-127, default 36)
        //   E_SLIDER_Arpeggio_EndNote   (0-127, default 84)
        //
        // Legacy settings (from sequences created in wx build):
        //   E_CHOICE_Arpeggio_TimingTrack, E_TEXTCTRL_Arpeggio_Steps,
        //   E_TEXTCTRL_Arpeggio_AutoSplit, E_TEXTCTRL_Arpeggio_PropsPerStep,
        //   E_CHECKBOX_Arpeggio_Loop, E_CHOICE_Arpeggio_Order,
        //   E_CHOICE_Arpeggio_Pattern, E_CHECKBOX_Arpeggio_Shimmer,
        //   E_CHECKBOX_Arpeggio_PerPropGradient, E_TEXTCTRL_Arpeggio_FadeIn,
        //   E_TEXTCTRL_Arpeggio_FadeOut, E_TEXTCTRL_Arpeggio_Overlap,
        //   E_CHECKBOX_Arpeggio_ManualMode, E_TEXTCTRL_Arpeggio_SequencerData

        auto getStr = [&](const char* key, const char* def = "") -> std::string {
            auto it = effectInfo.settings.find(key);
            return (it != effectInfo.settings.end() && !it->second.empty()) ? it->second : def;
        };
        auto getInt = [&](const char* key, int def = 0) -> int {
            auto it = effectInfo.settings.find(key);
            return (it != effectInfo.settings.end() && !it->second.empty()) ? std::atoi(it->second.c_str()) : def;
        };
        auto getBool = [&](const char* key, bool def = false) -> bool {
            auto it = effectInfo.settings.find(key);
            if (it == effectInfo.settings.end() || it->second.empty()) return def;
            return it->second == "1" || it->second == "true" || it->second == "yes";
        };

        // Detect whether this uses native panel settings or legacy settings.
        // Native panel uses E_SLIDER_Arpeggio_BPM; legacy uses E_TEXTCTRL_Arpeggio_Steps.
        bool hasNativeSettings = (effectInfo.settings.count("E_SLIDER_Arpeggio_BPM") > 0 ||
                                  effectInfo.settings.count("E_SLIDER_Arpeggio_StartNote") > 0);
        bool hasLegacySettings = (effectInfo.settings.count("E_TEXTCTRL_Arpeggio_Steps") > 0 ||
                                  effectInfo.settings.count("E_CHOICE_Arpeggio_TimingTrack") > 0 ||
                                  effectInfo.settings.count("E_TEXTCTRL_Arpeggio_AutoSplit") > 0 ||
                                  effectInfo.settings.count("E_CHECKBOX_Arpeggio_ManualMode") > 0);

        // Current time information
        int currentMS = buf.curPeriod * buf.frameTimeInMs;
        int effectStartMS = buf.curEffStartPer * buf.frameTimeInMs;
        int effectEndMS = buf.curEffEndPer * buf.frameTimeInMs;
        int effectDurationMS = effectEndMS - effectStartMS;
        if (effectDurationMS <= 0) return true;
        int timeIntoEffectMS = currentMS - effectStartMS;

        if (hasLegacySettings && !hasNativeSettings) {
            // ================================================================
            // Legacy rendering path — faithful port of ArpeggioEffect::Render
            // ================================================================
            std::string timingTrack = getStr("E_CHOICE_Arpeggio_TimingTrack");
            int steps = getInt("E_TEXTCTRL_Arpeggio_Steps", 0);
            int autoSplit = getInt("E_TEXTCTRL_Arpeggio_AutoSplit", 8);
            int propsPerStep = getInt("E_TEXTCTRL_Arpeggio_PropsPerStep", 1);
            bool loop = getBool("E_CHECKBOX_Arpeggio_Loop", true);
            bool shimmer = getBool("E_CHECKBOX_Arpeggio_Shimmer", false);
            bool perPropGradient = getBool("E_CHECKBOX_Arpeggio_PerPropGradient", false);
            std::string orderStr = getStr("E_CHOICE_Arpeggio_Order", "Forward");
            std::string pattern = getStr("E_CHOICE_Arpeggio_Pattern", "None");
            bool manualMode = getBool("E_CHECKBOX_Arpeggio_ManualMode", false);
            std::string sequencerData = getStr("E_TEXTCTRL_Arpeggio_SequencerData");
            int fadeIn = getInt("E_TEXTCTRL_Arpeggio_FadeIn", 50);
            int fadeOut = getInt("E_TEXTCTRL_Arpeggio_FadeOut", 50);
            int overlap = getInt("E_TEXTCTRL_Arpeggio_Overlap", 0);

            if (autoSplit < 1) autoSplit = 1;
            if (propsPerStep < 1) propsPerStep = 1;

            // Determine number of steps (props)
            int numSteps = steps;
            if (numSteps <= 0) {
                numSteps = buf.BufferWi;
                if (numSteps <= 0) numSteps = 1;
            }

            // Build order mapping
            std::vector<int> orderMap;
            if (pattern != "None") {
                if (pattern == "Center Out") {
                    int mid = numSteps / 2;
                    for (int i = 0; i < numSteps; i++) {
                        int offset = (i + 1) / 2;
                        if (i % 2 == 0) {
                            int idx = mid + offset;
                            if (idx < numSteps) orderMap.push_back(idx);
                        } else {
                            int idx = mid - offset;
                            if (idx >= 0) orderMap.push_back(idx);
                        }
                    }
                } else if (pattern == "Edges In") {
                    int left = 0, right = numSteps - 1;
                    while (left < right) {
                        orderMap.push_back(left);
                        orderMap.push_back(right);
                        left++; right--;
                    }
                    if (left == right) orderMap.push_back(left);
                } else if (pattern == "Right to Left") {
                    for (int i = numSteps - 1; i >= 0; i--) orderMap.push_back(i);
                } else if (pattern == "Alternating") {
                    for (int i = 0; i < numSteps; i += 2) orderMap.push_back(i);
                    for (int i = 1; i < numSteps; i += 2) orderMap.push_back(i);
                } else if (pattern == "Split") {
                    int mid = numSteps / 2;
                    for (int i = 0; i < mid; i++) {
                        orderMap.push_back(i);
                        if (mid + i < numSteps) orderMap.push_back(mid + i);
                    }
                    if (numSteps % 2 != 0) orderMap.push_back(mid);
                } else {
                    for (int i = 0; i < numSteps; i++) orderMap.push_back(i);
                }
            } else if (orderStr == "Random") {
                unsigned int seed = static_cast<unsigned int>(effectStartMS ^ 0x12345);
                std::srand(seed);
                for (int i = 0; i < numSteps; i++) orderMap.push_back(i);
                for (int i = numSteps - 1; i > 0; i--) {
                    int j = std::rand() % (i + 1);
                    std::swap(orderMap[i], orderMap[j]);
                }
            } else if (orderStr == "Reverse") {
                for (int i = numSteps - 1; i >= 0; i--) orderMap.push_back(i);
            } else if (orderStr == "Ping-Pong") {
                int left = 0, right = numSteps - 1;
                while (left <= right) {
                    orderMap.push_back(left);
                    if (left != right) orderMap.push_back(right);
                    left++; right--;
                }
            } else if (orderStr == "Even") {
                for (int i = 1; i < numSteps; i += 2) orderMap.push_back(i);
            } else if (orderStr == "Odd") {
                for (int i = 0; i < numSteps; i += 2) orderMap.push_back(i);
            } else {
                for (int i = 0; i < numSteps; i++) orderMap.push_back(i);
            }

            // Calculate step times from timing track or auto-split
            std::vector<std::pair<int, int>> stepTimes;
            if (!timingTrack.empty()) {
                auto marks = getTimingMarks(timingTrack);
                for (const auto& mark : marks) {
                    int markStart = mark.startTimeMS;
                    int markEnd = mark.endTimeMS;
                    if (markStart < effectEndMS && markEnd > effectStartMS) {
                        markStart = std::max(markStart, effectStartMS);
                        markEnd = std::min(markEnd, effectEndMS);
                        stepTimes.push_back({markStart, markEnd});
                    }
                }
            }

            if (stepTimes.empty()) {
                int stepDuration = effectDurationMS / autoSplit;
                if (stepDuration < 1) stepDuration = 1;
                for (int i = 0; i < autoSplit; i++) {
                    int sms = effectStartMS + i * stepDuration;
                    int ems = (i == autoSplit - 1) ? effectEndMS : (sms + stepDuration);
                    stepTimes.push_back({sms, ems});
                }
            }

            // Find active step
            int activeStepIndex = -1;
            for (size_t i = 0; i < stepTimes.size(); i++) {
                int sms = stepTimes[i].first;
                int ems = stepTimes[i].second;
                int dur = ems - sms;
                int overlapMS = (dur * overlap) / 200;
                sms -= overlapMS;
                ems += overlapMS;
                if (currentMS >= sms && currentMS < ems) {
                    activeStepIndex = static_cast<int>(i);
                    break;
                }
            }

            if (activeStepIndex < 0) return true;

            int orderMapSize = static_cast<int>(orderMap.size());
            if (orderMapSize == 0) return true;

            int orderMapPosition = (activeStepIndex * propsPerStep) % orderMapSize;
            if (!manualMode && !loop && (activeStepIndex * propsPerStep) >= orderMapSize) {
                return true;
            }

            // Determine active prop indices
            std::vector<int> activePropIndices;
            if (manualMode && !sequencerData.empty()) {
                int totalStepsInData = 0;
                {
                    std::istringstream countSS(sequencerData);
                    std::string tmp;
                    while (std::getline(countSS, tmp, ':')) totalStepsInData++;
                }
                int mappedStepIndex = activeStepIndex;
                if (totalStepsInData > 0 && activeStepIndex >= totalStepsInData) {
                    if (loop) {
                        mappedStepIndex = activeStepIndex % totalStepsInData;
                    } else {
                        return true;
                    }
                }
                std::istringstream ss(sequencerData);
                std::string stepData;
                int stepIndex = 0;
                while (std::getline(ss, stepData, ':') && stepIndex < mappedStepIndex) {
                    stepIndex++;
                }
                if (stepIndex == mappedStepIndex && !stepData.empty()) {
                    std::istringstream stepSS(stepData);
                    std::string propStr;
                    while (std::getline(stepSS, propStr, '|')) {
                        if (!propStr.empty() && propStr.find_first_not_of(" \t\n\r") != std::string::npos) {
                            try {
                                int propIndex = std::stoi(propStr);
                                if (propIndex >= 0) activePropIndices.push_back(propIndex);
                            } catch (...) {}
                        }
                    }
                }
            } else {
                for (int p = 0; p < propsPerStep; p++) {
                    int idx = (orderMapPosition + p) % orderMapSize;
                    activePropIndices.push_back(orderMap[idx]);
                }
            }

            // Calculate intensity from fade
            int stepStartMS = stepTimes[activeStepIndex].first;
            int stepEndMS = stepTimes[activeStepIndex].second;
            int stepDuration = stepEndMS - stepStartMS;
            int timeIntoStep = currentMS - stepStartMS;
            int timeFromEnd = stepEndMS - currentMS;

            double intensity = 1.0;
            if (fadeIn > 0 && timeIntoStep < fadeIn)
                intensity = (double)timeIntoStep / (double)fadeIn;
            if (fadeOut > 0 && timeFromEnd < fadeOut)
                intensity = std::min(intensity, (double)timeFromEnd / (double)fadeOut);

            int cidx = 0;
            if (shimmer) {
                int tot = buf.curPeriod - buf.curEffStartPer;
                if (tot % 2) {
                    if (buf.palette.Size() <= 1) return true;
                    cidx = 1;
                }
            }

            // Render: each active prop maps to columns in the buffer
            int colsPerStep = (numSteps > 0) ? std::max(1, buf.BufferWi / numSteps) : buf.BufferWi;

            for (int propIndex : activePropIndices) {
                if (propIndex >= numSteps) continue;

                xlColor color;
                if (perPropGradient) {
                    float stepPosition = (stepDuration > 0) ? (float)timeIntoStep / (float)stepDuration : 0.0f;
                    stepPosition = std::max(0.0f, std::min(1.0f, stepPosition));
                    buf.palette.GetColor(cidx % buf.palette.Size(), color, stepPosition);
                } else {
                    int colorIndex = (propIndex + cidx) % static_cast<int>(buf.palette.Size());
                    buf.palette.GetColor(static_cast<size_t>(colorIndex), color);
                }

                HSVValue hsv = color.asHSV();
                hsv.value = hsv.value * intensity;
                color = hsv;

                int xStart = propIndex * colsPerStep;
                int xEnd = std::min(xStart + colsPerStep, buf.BufferWi);
                for (int x = xStart; x < xEnd; x++) {
                    for (int y = 0; y < buf.BufferHt; y++) {
                        buf.SetPixel(x, y, color);
                    }
                }
            }

            return true;

        } else {
            // ================================================================
            // Native rendering path — uses BPM/Steps/StartNote/EndNote
            // ================================================================
            // The arpeggio steps through note positions at BPM tempo. Each step
            // lights up a horizontal band in the buffer corresponding to the
            // current note position within the StartNote-EndNote range.

            int bpm = getInt("E_SLIDER_Arpeggio_BPM", 120);
            int steps = getInt("E_SLIDER_Arpeggio_Steps", 8);
            int startNote = getInt("E_SLIDER_Arpeggio_StartNote", 36);
            int endNote = getInt("E_SLIDER_Arpeggio_EndNote", 84);

            if (bpm < 1) bpm = 1;
            if (steps < 1) steps = 1;
            if (startNote > endNote) std::swap(startNote, endNote);
            int noteRange = endNote - startNote;
            if (noteRange < 1) noteRange = 1;

            // Calculate step duration from BPM (one beat = one step cycle)
            // At 120 BPM, one beat = 500ms. With 8 steps, each step = 62.5ms.
            double msPerBeat = 60000.0 / (double)bpm;
            double msPerStep = msPerBeat / (double)steps;
            if (msPerStep < 1.0) msPerStep = 1.0;

            // Calculate which step is active based on time into effect
            int totalStepIndex = (int)((double)timeIntoEffectMS / msPerStep);
            int currentStep = totalStepIndex % steps;

            // Map current step to a note position (linear distribution across range)
            // Step 0 -> startNote, step (steps-1) -> endNote
            float notePosition;
            if (steps == 1) {
                notePosition = (float)(startNote + endNote) / 2.0f;
            } else {
                notePosition = (float)startNote + ((float)currentStep / (float)(steps - 1)) * (float)noteRange;
            }

            // Map the note position to a vertical row in the buffer
            // startNote maps to y=0, endNote maps to y=BufferHt-1
            float normalizedNote = (notePosition - (float)startNote) / (float)noteRange;
            normalizedNote = std::max(0.0f, std::min(1.0f, normalizedNote));

            int centerY = (int)(normalizedNote * (float)(buf.BufferHt - 1));

            // Each step lights a band. The band height is proportional to buffer
            // height divided by number of steps, minimum 1 pixel.
            int bandHeight = std::max(1, buf.BufferHt / steps);
            int yStart = std::max(0, centerY - bandHeight / 2);
            int yEnd = std::min(buf.BufferHt, yStart + bandHeight);

            // Get color from palette, cycling through palette colors per step
            int colorcnt = static_cast<int>(buf.palette.Size());
            int colorIdx = currentStep % colorcnt;
            xlColor color;
            buf.palette.GetColor(static_cast<size_t>(colorIdx), color);

            // Apply a subtle fade based on position within the step
            double stepProgress = std::fmod((double)timeIntoEffectMS, msPerStep) / msPerStep;
            // Quick attack, smooth decay envelope
            double envelope = 1.0;
            if (stepProgress < 0.1) {
                envelope = stepProgress / 0.1;  // 10% attack
            } else {
                envelope = 1.0 - (stepProgress - 0.1) * 0.3;  // gentle decay
                if (envelope < 0.3) envelope = 0.3;
            }

            HSVValue hsv = color.asHSV();
            hsv.value = hsv.value * envelope;
            color = hsv;

            // Draw the active band across the full width
            for (int y = yStart; y < yEnd; y++) {
                for (int x = 0; x < buf.BufferWi; x++) {
                    buf.SetPixel(x, y, color);
                }
            }

            return true;
        }
    }

    // ===================================================================
    // Piano effect — maps MIDI note data from a timing track to a
    // visual piano keyboard rendered on the buffer.
    // ===================================================================
    if (type == "Piano") {
        auto getStr = [&](const char* key, const char* def = "") -> std::string {
            auto it = effectInfo.settings.find(key);
            return (it != effectInfo.settings.end() && !it->second.empty()) ? it->second : def;
        };
        auto getInt = [&](const char* key, int def = 0) -> int {
            auto it = effectInfo.settings.find(key);
            return (it != effectInfo.settings.end() && !it->second.empty()) ? std::atoi(it->second.c_str()) : def;
        };
        auto getBool = [&](const char* key, bool def = false) -> bool {
            auto it = effectInfo.settings.find(key);
            if (it == effectInfo.settings.end() || it->second.empty()) return def;
            return it->second == "1" || it->second == "true" || it->second == "yes";
        };

        // Read settings — support both native slider keys and legacy spinctrl keys
        int startmidi = getInt("E_SLIDER_Piano_StartMIDI",
                        getInt("E_SPINCTRL_Piano_StartMIDI", 60));
        int endmidi   = getInt("E_SLIDER_Piano_EndMIDI",
                        getInt("E_SPINCTRL_Piano_EndMIDI", 72));
        bool showSharps = getBool("E_CHECKBOX_Piano_ShowSharps", true);
        std::string pianoType = getStr("E_CHOICE_Piano_Type", "True Piano");
        int scale = getInt("E_SLIDER_Piano_Scale", 100);
        int xoffset = getInt("E_SLIDER_Piano_XOffset", 0);
        bool fadeNotes = getBool("E_CHECKBOX_Piano_FadeNotes", false);
        std::string midiTrack = getStr("E_CHOICE_Piano_MIDITrack_APPLYLAST", "");

        if (midiTrack.empty()) return true;

        // --- Local helpers (ported from PianoEffect) ---

        auto isSharp = [](int note) -> bool {
            int x = note % 12;
            return (x == 1 || x == 3 || x == 6 || x == 8 || x == 10);
        };

        // Extract note name strings from a timing mark label.
        // Labels can contain multiple notes separated by : , ; or space
        auto extractNotes = [](const std::string& label) -> std::list<std::string> {
            std::string n = label;
            std::transform(n.begin(), n.end(), n.begin(), ::toupper);
            std::list<std::string> res;
            std::string s;
            for (char ch : n) {
                if (ch == ':' || ch == ' ' || ch == ';' || ch == ',') {
                    if (!s.empty()) { res.push_back(s); s.clear(); }
                } else {
                    if ((ch >= 'A' && ch <= 'G') || ch == '#' || (ch >= '0' && ch <= '9')) {
                        s += ch;
                    }
                }
            }
            if (!s.empty()) res.push_back(s);
            return res;
        };

        // Convert a note name like "C4" or "C#4" or a raw number "60" to MIDI 0-127
        auto convertNote = [](const std::string& note) -> int {
            std::string n = note;
            std::transform(n.begin(), n.end(), n.begin(), ::toupper);
            int nletter;
            switch (n[0]) {
                case 'A': nletter = 9; break;
                case 'B': nletter = 11; break;
                case 'C': nletter = 0; break;
                case 'D': nletter = 2; break;
                case 'E': nletter = 4; break;
                case 'F': nletter = 5; break;
                case 'G': nletter = 7; break;
                default: {
                    int number = std::atoi(n.c_str());
                    return std::clamp(number, 0, 127);
                }
            }
            n = n.substr(1);
            int sharp = 0;
            if (n.find('#') != std::string::npos) sharp = 1;
            else if (n.find('B') != std::string::npos) sharp = -1;
            int octave = 4;
            if (!n.empty()) {
                if (n[0] == '#' || n[0] == 'B') n = n.substr(1);
            }
            if (!n.empty()) octave = std::atoi(n.c_str());
            int number = 12 + (octave * 12) + nletter + sharp;
            return std::clamp(number, 0, 127);
        };

        // --- Render cache: pre-built timing data ---
        struct PianoCacheNative : public EffectRenderCache {
            std::map<int, std::list<std::pair<float, float>>> timings;
            std::string cachedTrack;
        };

        int cacheId = 200;
        auto* cache = static_cast<PianoCacheNative*>(buf.infoCache[cacheId]);
        if (!cache) {
            cache = new PianoCacheNative();
            buf.infoCache[cacheId] = cache;
        }

        if (buf.needToInit || cache->cachedTrack != midiTrack) {
            buf.needToInit = false;
            cache->timings.clear();
            cache->cachedTrack = midiTrack;

            std::vector<EffectInstanceInfo> marks = getTimingMarks(midiTrack);
            int intervalMS = buf.frameTimeInMs;

            for (const auto& mark : marks) {
                std::list<std::pair<float, float>> notes;
                // Timing mark label is stored in effectType field
                std::string label = mark.effectType;
                auto labelIt = mark.settings.find("label");
                if (labelIt != mark.settings.end() && !labelIt->second.empty()) {
                    label = labelIt->second;
                }
                std::list<std::string> noteLabels = extractNotes(label);
                for (const auto& s : noteLabels) {
                    float n = (float)convertNote(s);
                    if (n >= 0) {
                        notes.push_back({n, 1.0f});
                    }
                }
                for (int t = mark.startTimeMS; t < mark.endTimeMS; t += intervalMS) {
                    cache->timings[t] = notes;
                }
            }

            // Apply note fading
            if (fadeNotes && !cache->timings.empty()) {
                struct NoteTracker { int note; int startFrame; int frames; };
                std::list<NoteTracker> tracker;
                int lastTime = 0;
                for (const auto& entry : cache->timings) {
                    lastTime = std::max(lastTime, entry.first);
                }

                auto findTracker = [](std::list<NoteTracker>& tr, int note) -> NoteTracker* {
                    for (auto& t : tr) {
                        if (t.note == note) return &t;
                    }
                    return nullptr;
                };

                for (const auto& entry : cache->timings) {
                    std::list<int> currentNotes;
                    for (auto& np : entry.second) {
                        currentNotes.push_back((int)np.first);
                        auto* t = findTracker(tracker, (int)np.first);
                        if (!t) {
                            tracker.push_back({(int)np.first, entry.first, 1});
                        } else {
                            t->frames++;
                        }
                    }
                    auto tIt = tracker.begin();
                    while (tIt != tracker.end()) {
                        if (std::find(currentNotes.begin(), currentNotes.end(), tIt->note) == currentNotes.end()) {
                            int sf = tIt->startFrame;
                            int ef = entry.first;
                            for (int f = sf; f < ef; f += intervalMS) {
                                if (cache->timings.find(f) != cache->timings.end()) {
                                    for (auto& np : cache->timings[f]) {
                                        if ((int)np.first == tIt->note) {
                                            np.second = 1.0f - (float)(f - sf) / (float)(ef - sf);
                                        }
                                    }
                                }
                            }
                            tIt = tracker.erase(tIt);
                        } else {
                            ++tIt;
                        }
                    }
                }
                for (auto& t : tracker) {
                    int sf = t.startFrame;
                    int ef = lastTime + intervalMS;
                    for (int f = sf; f < ef; f += intervalMS) {
                        if (cache->timings.find(f) != cache->timings.end()) {
                            for (auto& np : cache->timings[f]) {
                                if ((int)np.first == t.note) {
                                    np.second = 1.0f - (float)(f - sf) / (float)(ef - sf);
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- Get active notes for current frame ---
        int curTime = buf.curPeriod * buf.frameTimeInMs;
        std::list<std::pair<float, float>> noteData;
        auto tdIt = cache->timings.find(curTime);
        if (tdIt != cache->timings.end()) {
            noteData = tdIt->second;
        }

        int em = endmidi;
        if (em < startmidi) em = startmidi;
        if (em - startmidi + 1 > buf.BufferWi) em = startmidi + buf.BufferWi - 1;

        // ReduceChannels: filter sharps and clip to note range
        {
            auto ndIt = noteData.begin();
            while (ndIt != noteData.end()) {
                if (!showSharps && isSharp((int)ndIt->first)) {
                    float lowerNote = ndIt->first - 1.0f;
                    bool found = false;
                    for (const auto& c : noteData) {
                        if ((int)c.first == (int)lowerNote) { found = true; break; }
                    }
                    if (!found) {
                        noteData.push_back({lowerNote, 0.0f});
                    }
                    ndIt = noteData.erase(ndIt);
                } else if ((int)ndIt->first < startmidi || (int)ndIt->first > em) {
                    ndIt = noteData.erase(ndIt);
                } else {
                    ++ndIt;
                }
            }
        }

        auto keyDown = [](const std::list<std::pair<float, float>>& data, int ch) -> bool {
            for (const auto& p : data) {
                if ((int)p.first == ch) return true;
            }
            return false;
        };

        auto getKeyBrightness = [](const std::list<std::pair<float, float>>& data, int ch) -> float {
            for (const auto& p : data) {
                if ((int)p.first == ch) return p.second;
            }
            return 0.0f;
        };

        // Alpha-blend helper: blend foreground over background using fg.alpha
        auto alphaBlend = [](const xlColor& fg, const xlColor& bg) -> xlColor {
            float a = (float)fg.alpha / 255.0f;
            xlColor result;
            result.red = (uint8_t)(fg.red * a + bg.red * (1.0f - a));
            result.green = (uint8_t)(fg.green * a + bg.green * (1.0f - a));
            result.blue = (uint8_t)(fg.blue * a + bg.blue * (1.0f - a));
            result.alpha = 255;
            return result;
        };

        // --- True Piano rendering ---
        if (pianoType == "True Piano") {
            int truexoffset = xoffset * buf.BufferWi / 100;

            int whitestart = -1, whiteend = -1;
            for (int i = startmidi; i <= em; ++i) {
                if (!isSharp(i)) { whitestart = i; break; }
            }
            for (int i = em; i >= startmidi; --i) {
                if (!isSharp(i)) { whiteend = i; break; }
            }

            int wkcount = 0;
            if (whitestart != -1 && whiteend != -1) {
                for (int i = whitestart; i <= whiteend; ++i) {
                    if (!isSharp(i)) ++wkcount;
                }
            }
            if (wkcount == 0) wkcount = 1;

            float fwkw = (float)buf.BufferWi / (float)wkcount;
            float wkw = fwkw;
            float maxx = (float)wkcount * fwkw;
            bool border = (wkw > 3);
            if (border) wkw -= 1.0f;

            xlColor wkcolour, bkcolour, wkdcolour, bkdcolour, kbcolour;
            if (buf.GetColorCount() > 0) buf.palette.GetColor(0, wkcolour); else wkcolour = xlWHITE;
            if (buf.GetColorCount() > 1) buf.palette.GetColor(1, bkcolour); else bkcolour = xlBLACK;
            if (buf.GetColorCount() > 2) buf.palette.GetColor(2, wkdcolour); else wkdcolour = xlMAGENTA;
            if (buf.GetColorCount() > 3) buf.palette.GetColor(3, bkdcolour); else bkdcolour = xlMAGENTA;
            if (buf.GetColorCount() > 4) buf.palette.GetColor(4, kbcolour); else kbcolour = xlLIGHT_GREY;

            // Draw white keys
            float x = (float)truexoffset;
            for (int i = startmidi; i <= em; ++i) {
                if (!isSharp(i)) {
                    if (keyDown(noteData, i)) {
                        xlColor dc = wkdcolour;
                        if (fadeNotes) {
                            dc.alpha = (uint8_t)(getKeyBrightness(noteData, i) * 255.0f);
                            dc = alphaBlend(dc, wkcolour);
                        }
                        buf.DrawBox((int)x, 0, (int)(x + wkw), buf.BufferHt * scale / 100, dc, false);
                    } else {
                        buf.DrawBox((int)x, 0, (int)(x + wkw), buf.BufferHt * scale / 100, wkcolour, false);
                    }
                    x += fwkw;
                }
            }

            // Draw white key borders
            if (border) {
                x = fwkw + (float)truexoffset;
                for (int j = 0; j < wkcount; ++j) {
                    buf.DrawLine((int)x, 0, (int)x, buf.BufferHt * scale / 100, kbcolour);
                    x += fwkw;
                }
            }

            // Draw black keys
            if (showSharps) {
                if (isSharp(startmidi)) {
                    x = -1.0f * fwkw / 2.0f + (float)truexoffset;
                } else if (startmidi + 1 <= em && isSharp(startmidi + 1)) {
                    x = fwkw / 2.0f + (float)truexoffset;
                } else {
                    x = fwkw + fwkw / 2.0f + (float)truexoffset;
                }
                for (int i = startmidi; i <= em; ++i) {
                    if (isSharp(i)) {
                        int bkAdj = (int)std::round(0.3f / 2.0f * fwkw);
                        float x1 = x + (float)bkAdj;
                        float x2 = std::min(maxx, x + fwkw - (float)bkAdj);
                        if (keyDown(noteData, i)) {
                            xlColor dc = bkdcolour;
                            if (fadeNotes) {
                                dc.alpha = (uint8_t)(getKeyBrightness(noteData, i) * 255.0f);
                                dc = alphaBlend(dc, bkcolour);
                            }
                            buf.DrawBox((int)x1, buf.BufferHt * scale / 200,
                                        (int)x2, buf.BufferHt * scale / 100, dc, false);
                        } else {
                            buf.DrawBox((int)x1, buf.BufferHt * scale / 200,
                                        (int)x2, buf.BufferHt * scale / 100, bkcolour, false);
                        }
                        if (i + 1 <= 127 && !isSharp(i + 1) && i + 2 <= 127 && !isSharp(i + 2)) {
                            x += fwkw + fwkw;
                        } else {
                            x += fwkw;
                        }
                    }
                }
            }
        }
        // --- Bars rendering ---
        else if (pianoType == "Bars") {
            int truexoffset = xoffset * buf.BufferWi / 100;

            int kcount = 0;
            if (showSharps) {
                kcount = em - startmidi + 1;
            } else {
                for (int i = startmidi; i <= em; ++i) {
                    if (!isSharp(i)) ++kcount;
                }
            }
            if (kcount == 0) kcount = 1;

            float fwkw = (float)buf.BufferWi / (float)kcount;

            xlColor wkcolour, bkcolour, wkdcolour, bkdcolour;
            if (buf.GetColorCount() > 0) buf.palette.GetColor(0, wkcolour); else wkcolour = xlWHITE;
            if (buf.GetColorCount() > 1) buf.palette.GetColor(1, bkcolour); else bkcolour = xlBLACK;
            if (buf.GetColorCount() > 2) buf.palette.GetColor(2, wkdcolour); else wkdcolour = xlMAGENTA;
            if (buf.GetColorCount() > 3) buf.palette.GetColor(3, bkdcolour); else bkdcolour = xlMAGENTA;

            float x = (float)truexoffset;
            int wkh = buf.BufferHt;
            if (showSharps) {
                wkh = (int)(buf.BufferHt * 2.0f * (float)scale / 300.0f);
            }
            int bkb = (int)(buf.BufferHt * (float)scale / 300.0f);

            for (int i = startmidi; i <= em; ++i) {
                if (!isSharp(i)) {
                    if (keyDown(noteData, i)) {
                        xlColor dc = wkdcolour;
                        if (fadeNotes) {
                            dc.alpha = (uint8_t)(getKeyBrightness(noteData, i) * 255.0f);
                            dc = alphaBlend(dc, wkcolour);
                        }
                        buf.DrawBox((int)x, 0, (int)(x + fwkw - 1), wkh, dc, false);
                    } else {
                        buf.DrawBox((int)x, 0, (int)(x + fwkw - 1), wkh, wkcolour, false);
                    }
                    x += fwkw;
                } else if (showSharps) {
                    if (keyDown(noteData, i)) {
                        xlColor dc = bkdcolour;
                        if (fadeNotes) {
                            dc.alpha = (uint8_t)(getKeyBrightness(noteData, i) * 255.0f);
                            dc = alphaBlend(dc, bkcolour);
                        }
                        buf.DrawBox((int)x, bkb, (int)(x + fwkw - 1),
                                    buf.BufferHt * scale / 100, dc, false);
                    } else {
                        buf.DrawBox((int)x, bkb, (int)(x + fwkw - 1),
                                    buf.BufferHt * scale / 100, bkcolour, false);
                    }
                    x += fwkw;
                }
            }
        }

        return true;
    }

    // ===================================================================
    // Guitar effect — renders guitar strings with notes playing at fret
    // positions, driven by a timing track containing note/chord labels.
    // ===================================================================
    if (type == "Guitar") {
        // --- Read settings ---
        std::string guitarType = "Guitar";
        std::string midiTrack;
        std::string stringAppearance = "On";
        int maxFrets = 19;
        bool showStrings = false;
        bool fade = false;
        bool collapse = false;
        double stringWaveFactor = 0.0;
        double baseWaveFactor = 1.0;
        bool varyWavelengthBasedOnFret = false;

        auto it = effectInfo.settings.find("E_CHOICE_Guitar_Type");
        if (it != effectInfo.settings.end() && !it->second.empty())
            guitarType = it->second;
        it = effectInfo.settings.find("E_CHOICE_Guitar_MIDITrack_APPLYLAST");
        if (it != effectInfo.settings.end() && !it->second.empty())
            midiTrack = it->second;
        it = effectInfo.settings.find("E_CHOICE_StringAppearance");
        if (it != effectInfo.settings.end() && !it->second.empty())
            stringAppearance = it->second;
        it = effectInfo.settings.find("E_SLIDER_MaxFrets");
        if (it != effectInfo.settings.end() && !it->second.empty())
            maxFrets = std::atoi(it->second.c_str());
        it = effectInfo.settings.find("E_CHECKBOX_ShowStrings");
        if (it != effectInfo.settings.end())
            showStrings = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Fade");
        if (it != effectInfo.settings.end())
            fade = (it->second == "1");
        it = effectInfo.settings.find("E_CHECKBOX_Collapse");
        if (it != effectInfo.settings.end())
            collapse = (it->second == "1");
        it = effectInfo.settings.find("E_SLIDER_StringWaveFactor");
        if (it != effectInfo.settings.end() && !it->second.empty())
            stringWaveFactor = std::atof(it->second.c_str()) / 10.0;
        it = effectInfo.settings.find("E_SLIDER_BaseWaveFactor");
        if (it != effectInfo.settings.end() && !it->second.empty())
            baseWaveFactor = std::atof(it->second.c_str()) / 10.0;
        it = effectInfo.settings.find("E_CHECKBOX_VaryWaveLengthOnFret");
        if (it != effectInfo.settings.end())
            varyWavelengthBasedOnFret = (it->second == "1");

        if (maxFrets < 1) maxFrets = 1;

        // --- Guitar tuning data (open-string MIDI notes per instrument) ---
        struct GuitarNote { uint8_t string; uint8_t fret; uint8_t note; };

        static const std::vector<GuitarNote> guitarTuning = {
            {0,0,40}, {1,0,45}, {2,0,50}, {3,0,55}, {4,0,59}, {5,0,64}
        };
        static const std::vector<GuitarNote> bassTuning = {
            {0,0,28}, {1,0,33}, {2,0,38}, {3,0,43}
        };
        static const std::vector<GuitarNote> banjoTuning = {
            {1,0,50}, {2,0,55}, {3,0,59}, {4,0,62}, {0,0,62}
        };
        static const std::vector<GuitarNote> violinTuning = {
            {1,0,55}, {2,0,62}, {3,0,69}, {4,0,76}
        };

        const std::vector<GuitarNote>* baseTuning = &guitarTuning;
        if (guitarType == "Bass Guitar") baseTuning = &bassTuning;
        else if (guitarType == "Banjo") baseTuning = &banjoTuning;
        else if (guitarType == "Violin") baseTuning = &violinTuning;

        uint8_t strings = static_cast<uint8_t>(baseTuning->size());

        // --- Chord definitions (name, MIDI notes, fingering) ---
        struct ChordDef {
            std::string name;
            std::vector<uint8_t> notes;
            std::vector<std::pair<uint8_t,uint8_t>> fingering;
        };

        static const std::vector<ChordDef> guitarChords = {
            {"CA",{40,45,52,57,61,64},{{0,0},{1,0},{2,2},{3,2},{4,2},{5,0}}},
            {"CA#",{50,58,62,65},{{2,0},{3,3},{4,3},{5,1}}},
            {"CBB",{50,58,62,65},{{2,0},{3,3},{4,3},{5,1}}},
            {"CB",{54,59,63,66},{{2,4},{3,4},{4,4},{5,2}}},
            {"CC",{40,48,52,55,60,64},{{0,0},{1,3},{2,2},{3,0},{4,1},{5,0}}},
            {"CC#",{53,56,61,65},{{2,3},{3,1},{4,2},{5,1}}},
            {"CDB",{53,56,61,65},{{2,3},{3,1},{4,2},{5,1}}},
            {"CD",{45,50,57,62,66},{{1,0},{2,0},{3,2},{4,3},{5,2}}},
            {"CD#",{51,58,63,67},{{2,1},{3,3},{4,4},{5,3}}},
            {"CEB",{51,58,63,67},{{2,1},{3,3},{4,4},{5,3}}},
            {"CE",{40,47,52,56,59,64},{{0,0},{1,2},{2,2},{3,1},{4,0},{5,0}}},
            {"CF",{45,53,57,60,65},{{1,0},{2,3},{3,2},{4,1},{5,1}}},
            {"CF#",{54,58,61,66},{{2,4},{3,3},{4,2},{5,2}}},
            {"CGB",{54,58,61,66},{{2,4},{3,3},{4,2},{5,2}}},
            {"CG",{43,47,50,55,59,67},{{0,3},{1,2},{2,0},{3,0},{4,0},{5,3}}},
            {"CG#",{51,56,60,68},{{2,1},{3,1},{4,1},{5,4}}},
            {"CAB",{51,56,60,68},{{2,1},{3,1},{4,1},{5,4}}},
            {"CAM",{40,45,52,57,60,64},{{0,0},{1,0},{2,2},{3,2},{4,1},{5,0}}},
            {"CA#M",{53,58,61,65},{{2,3},{3,3},{4,2},{5,1}}},
            {"CBbM",{53,58,61,65},{{2,3},{3,3},{4,2},{5,1}}},
            {"CBM",{54,59,62,66},{{2,4},{3,4},{4,3},{5,2}}},
            {"CCM",{51,55,60,67},{{2,1},{3,0},{4,1},{5,3}}},
            {"CC#M",{52,56,61,64},{{2,2},{3,1},{4,2},{5,0}}},
            {"CDbM",{52,56,61,64},{{2,2},{3,1},{4,2},{5,0}}},
            {"CDM",{45,50,57,62,65},{{1,0},{2,0},{3,2},{4,3},{5,1}}},
            {"CD#M",{51,58,63,66},{{2,1},{3,3},{4,4},{5,2}}},
            {"CEBM",{51,58,63,66},{{2,1},{3,3},{4,4},{5,2}}},
            {"CEM",{40,47,52,55,59,64},{{0,0},{1,2},{2,2},{3,0},{4,0},{5,0}}},
            {"CFM",{53,56,60,65},{{2,3},{3,1},{4,1},{5,1}}},
            {"CF#M",{54,57,61,66},{{2,4},{3,2},{4,2},{5,2}}},
            {"CGBM",{54,57,61,66},{{2,4},{3,2},{4,2},{5,2}}},
            {"CGM",{50,58,62,67},{{2,0},{3,3},{4,3},{5,3}}},
            {"CG#M",{56,59,63,68},{{2,6},{3,4},{4,4},{5,4}}},
            {"CABM",{56,59,63,68},{{2,6},{3,4},{4,4},{5,4}}},
            {"CA7",{40,45,52,55,61,64},{{0,0},{1,0},{2,2},{3,0},{4,2},{5,0}}},
            {"CA#7",{53,58,62,68},{{2,3},{3,3},{4,3},{5,4}}},
            {"CBB7",{53,58,62,68},{{2,3},{3,3},{4,3},{5,4}}},
            {"CB7",{47,51,57,59,66},{{1,2},{2,1},{3,2},{4,0},{5,2}}},
            {"CC7",{40,48,52,58,60,64},{{0,0},{1,3},{2,2},{3,3},{4,1},{5,0}}},
            {"CC#7",{53,56,59,65},{{2,3},{3,1},{4,0},{5,1}}},
            {"CDB7",{53,56,59,65},{{2,3},{3,1},{4,0},{5,1}}},
            {"CD7",{45,50,57,60,66},{{1,0},{2,0},{3,2},{4,1},{5,2}}},
            {"CD#7",{51,58,61,67},{{2,1},{3,3},{4,2},{5,3}}},
            {"CEB7",{51,58,61,67},{{2,1},{3,3},{4,2},{5,3}}},
            {"CE7",{40,47,50,56,59,64},{{0,0},{1,2},{2,0},{3,1},{4,0},{5,0}}},
            {"CF7",{45,51,57,60,65},{{1,0},{2,1},{3,2},{4,1},{5,1}}},
            {"CF#7",{54,58,61,64},{{2,4},{3,3},{4,2},{5,0}}},
            {"CGB7",{54,58,61,64},{{2,4},{3,3},{4,2},{5,0}}},
            {"CG7",{43,47,50,55,59,65},{{0,3},{1,2},{2,0},{3,0},{4,0},{5,1}}},
            {"CG#7",{51,56,60,66},{{2,1},{3,1},{4,1},{5,2}}},
            {"CAB7",{51,56,60,66},{{2,1},{3,1},{4,1},{5,2}}},
        };

        static const std::vector<ChordDef> bassChords = {
            {"CA",{33,37,40,45},{{0,5},{1,4},{2,2},{3,3}}},
            {"CB",{30,35,39,47},{{0,2},{1,2},{2,1},{3,4}}},
            {"CC",{31,36,40,48},{{0,3},{1,3},{2,2},{3,5}}},
            {"CD",{30,38,39,45},{{0,2},{1,5},{2,0},{3,2}}},
            {"CE",{28,35,40,44},{{0,0},{1,2},{2,2},{3,1}}},
            {"CF",{29,36,41,45},{{0,1},{1,3},{2,3},{3,2}}},
            {"CG",{31,35,38,43},{{0,3},{1,2},{2,0},{3,0}}},
            {"CAM",{33,36,40,45},{{0,5},{1,3},{2,2},{3,3}}},
            {"CBM",{30,35,38,47},{{0,2},{1,2},{2,0},{3,4}}},
            {"CCM",{31,36,39,48},{{0,3},{1,3},{2,1},{3,5}}},
            {"CDM",{29,38,39,45},{{0,1},{1,5},{2,0},{3,2}}},
            {"CEM",{28,35,40,43},{{0,0},{1,2},{2,2},{3,0}}},
            {"CFM",{29,36,41,44},{{0,1},{1,3},{2,3},{3,1}}},
            {"CGM",{31,34,38,43},{{0,3},{1,1},{2,0},{3,0}}},
            {"CA7",{31,37,40,45},{{0,3},{1,4},{2,2},{3,3}}},
            {"CB7",{30,35,39,45},{{0,2},{1,2},{2,1},{3,2}}},
            {"CC7",{31,36,40,46},{{0,3},{1,3},{2,2},{3,3}}},
            {"CD7",{30,36,39,45},{{0,2},{1,3},{2,0},{3,2}}},
            {"CE7",{28,35,38,44},{{0,0},{1,2},{2,0},{3,1}}},
            {"CF7",{29,36,39,45},{{0,1},{1,3},{2,1},{3,2}}},
            {"CG7",{29,35,38,43},{{0,1},{1,2},{2,0},{3,0}}},
        };

        static const std::vector<ChordDef> banjoChords = {
            {"CA",{52,57,61,64},{{1,2},{2,2},{3,2},{4,2}}},
            {"CA#",{53,58,62,65},{{1,3},{2,3},{3,3},{4,3}}},
            {"CBB",{53,58,62,65},{{1,3},{2,3},{3,3},{4,3}}},
            {"CD",{50,57,62,66},{{1,0},{2,2},{3,3},{4,4}}},
            {"CE",{52,56,59,64},{{1,2},{2,1},{3,0},{4,2}}},
            {"CF",{53,57,60,65},{{1,3},{2,2},{3,1},{4,3}}},
            {"CG",{50,55,59,62},{{1,0},{2,0},{3,0},{4,0}}},
            {"CAM",{52,57,60,64},{{1,2},{2,2},{3,1},{4,2}}},
            {"CDM",{53,57,62,65},{{1,3},{2,2},{3,3},{4,3}}},
            {"CEM",{52,55,59,64},{{1,2},{2,0},{3,0},{4,2}}},
            {"CD7",{50,57,60,62},{{1,0},{2,2},{3,1},{4,0}}},
            {"CG7",{50,55,59,65},{{1,0},{2,0},{3,0},{4,3}}},
        };

        const std::vector<ChordDef>* chords = &guitarChords;
        if (guitarType == "Bass Guitar") chords = &bassChords;
        else if (guitarType == "Banjo") chords = &banjoChords;

        // --- Note conversion helpers (ported from GuitarEffect) ---

        auto convertNote = [](const std::string& note) -> int {
            std::string n = note;
            std::transform(n.begin(), n.end(), n.begin(), ::toupper);
            int nletter;
            switch (n[0]) {
                case 'S': case 'P': return -1;
                case 'A': nletter = 9; break;
                case 'B': nletter = 11; break;
                case 'C': nletter = 0; break;
                case 'D': nletter = 2; break;
                case 'E': nletter = 4; break;
                case 'F': nletter = 5; break;
                case 'G': nletter = 7; break;
                default: {
                    int number = std::atoi(n.c_str());
                    if (number < 0) number = 0;
                    if (number > 127) number = 127;
                    return number;
                }
            }
            n = n.substr(1);
            int sharp = 0;
            if (n.find('#') != std::string::npos) sharp = 1;
            else if (n.find('B') != std::string::npos) sharp = -1;
            int octave = 4;
            if (!n.empty()) {
                if (n[0] == '#' || n[0] == 'B') n = n.substr(1);
            }
            if (!n.empty()) octave = std::atoi(n.c_str());
            int number = 12 + (octave * 12) + nletter + sharp;
            if (number < 0) number = 0;
            if (number > 127) number = 127;
            return number;
        };

        auto convertStringPos = [](const std::string& note, uint8_t& outString, uint8_t& outPos) {
            outString = 0xFF;
            outPos = 0xFF;
            std::string n = note;
            std::transform(n.begin(), n.end(), n.begin(), ::toupper);
            if (n.empty() || n[0] != 'S') return;
            outString = 0;
            size_t index = 1;
            while (index < n.size() && n[index] >= '0' && n[index] <= '9') {
                outString = outString * 10 + (uint8_t)(n[index] - '0');
                ++index;
            }
            if (index >= n.size() || n[index] != 'P') { outString = 0xFF; return; }
            ++index;
            outPos = 0;
            while (index < n.size() && n[index] >= '0' && n[index] <= '9') {
                outPos = outPos * 10 + (uint8_t)(n[index] - '0');
                ++index;
            }
        };

        auto extractNotes = [](const std::string& label) -> std::list<std::string> {
            std::string n = label;
            std::transform(n.begin(), n.end(), n.begin(), ::toupper);
            std::list<std::string> res;
            std::string s;
            for (char ch : n) {
                if (ch == ':' || ch == ' ' || ch == ';' || ch == ',') {
                    if (!s.empty()) { res.push_back(s); s.clear(); }
                } else if ((ch >= 'A' && ch <= 'G') || ch == '#' || ch == 'S' ||
                           ch == 'P' || ch == 'M' || (ch >= '0' && ch <= '9')) {
                    s += ch;
                }
            }
            if (!s.empty()) res.push_back(s);
            return res;
        };

        // --- Finger position and cache structures ---
        struct FingerPos { uint8_t string; uint8_t fret; };

        struct NativeGuitarTiming {
            uint32_t startMS = 0;
            uint32_t endMS = 0;
            std::list<FingerPos> fingerPos;
        };

        struct NativeGuitarCache : public EffectRenderCache {
            std::vector<NativeGuitarTiming> timings;
            std::string cachedTrack;
        };

        NativeGuitarCache* cache = dynamic_cast<NativeGuitarCache*>(buf.infoCache[0]);
        if (!cache) {
            cache = new NativeGuitarCache();
            buf.infoCache[0] = cache;
        }

        // Rebuild timing cache when track changes or on first frame
        if (buf.needToInit || cache->cachedTrack != midiTrack) {
            buf.needToInit = false;
            cache->timings.clear();
            cache->cachedTrack = midiTrack;

            if (!midiTrack.empty()) {
                auto marks = getTimingMarks(midiTrack);

                auto getFretPos = [&](uint8_t s, uint8_t note, uint8_t mf) -> int {
                    if (s >= baseTuning->size()) return -1;
                    if (note < baseTuning->at(s).note) return -1;
                    if (note > baseTuning->at(s).note + mf) return -1;
                    return note - baseTuning->at(s).note;
                };

                for (const auto& mark : marks) {
                    NativeGuitarTiming gt;
                    gt.startMS = static_cast<uint32_t>(mark.startTimeMS);
                    gt.endMS = static_cast<uint32_t>(mark.endTimeMS);

                    std::string label = mark.effectType;
                    auto noteLabels = extractNotes(label);
                    std::list<uint8_t> noteValues;

                    for (const auto& s : noteLabels) {
                        bool isChord = false;
                        std::string upper = s;
                        std::transform(upper.begin(), upper.end(), upper.begin(), ::toupper);

                        for (const auto& c : *chords) {
                            if (upper == c.name) {
                                for (auto nn : c.notes) noteValues.push_back(nn);
                                isChord = true;
                                break;
                            }
                        }

                        if (!isChord) {
                            int noteVal = convertNote(s);
                            if (noteVal >= 0) {
                                noteValues.push_back(static_cast<uint8_t>(noteVal));
                            } else {
                                uint8_t sn, pos;
                                convertStringPos(s, sn, pos);
                                if (sn != 0xFF && sn != 0 && pos != 0xFF && pos <= maxFrets) {
                                    FingerPos fp;
                                    fp.string = static_cast<uint8_t>(strings - (sn - 1) - 1);
                                    fp.fret = pos;
                                    gt.fingerPos.push_back(fp);
                                }
                            }
                        }
                    }

                    if (!noteValues.empty()) {
                        noteValues.sort();

                        // Check against known chords first
                        bool foundChord = false;
                        for (const auto& c : *chords) {
                            if (c.notes.size() == noteValues.size()) {
                                std::list<uint8_t> cn(c.notes.begin(), c.notes.end());
                                bool match = true;
                                for (auto nv : noteValues) {
                                    if (std::find(cn.begin(), cn.end(), nv) == cn.end()) {
                                        match = false;
                                        break;
                                    }
                                }
                                if (match) {
                                    for (const auto& f : c.fingering) {
                                        gt.fingerPos.push_back({f.first, f.second});
                                    }
                                    foundChord = true;
                                    break;
                                }
                            }
                        }

                        if (!foundChord) {
                            uint8_t nextStr = 0;
                            for (auto note : noteValues) {
                                for (uint8_t si = nextStr; si < strings; ++si) {
                                    int fp = getFretPos(si, note, static_cast<uint8_t>(maxFrets));
                                    if (fp >= 0) {
                                        gt.fingerPos.push_back({si, static_cast<uint8_t>(fp)});
                                        nextStr = si + 1;
                                        break;
                                    }
                                }
                            }
                        }
                    }

                    if (!gt.fingerPos.empty()) {
                        cache->timings.push_back(std::move(gt));
                    }
                }
            }
        }

        // --- Find active timing at current time ---
        uint32_t guitarTimeMS = static_cast<uint32_t>(buf.curPeriod) * buf.frameTimeInMs;
        const NativeGuitarTiming* activeTiming = nullptr;
        for (const auto& t : cache->timings) {
            if (t.startMS <= guitarTimeMS && t.endMS > guitarTimeMS) {
                activeTiming = &t;
                break;
            }
        }

        auto flipY = [](int y, int height) -> int {
            return height - y - 1;
        };

        // --- Draw active note strings ---
        if (activeTiming != nullptr) {
            uint32_t pos = (guitarTimeMS - activeTiming->startMS) / buf.frameTimeInMs;
            uint32_t len = (activeTiming->endMS - activeTiming->startMS) / buf.frameTimeInMs;
            if (len < 1) len = 1;

            float perString = (float)buf.BufferHt / strings;

            for (const auto& fp : activeTiming->fingerPos) {
                xlColor c;
                buf.palette.GetColor(fp.string % buf.palette.Size(), c);
                xlColor stringColor = c;

                float alpha = (float)(len - pos) / (float)len;
                if (alpha < 0.0f) alpha = 0.0f;
                if (alpha > 1.0f) alpha = 1.0f;
                if (fade)
                    c.alpha = static_cast<uint8_t>(255.0f * alpha);

                if (stringAppearance == "Wave") {
                    uint32_t cycles = (((maxFrets - fp.fret) * buf.BufferWi) / maxFrets) / 10;
                    double waveMaxX = ((maxFrets - fp.fret) * buf.BufferWi) / maxFrets;

                    if (showStrings) {
                        for (int x = static_cast<int>(waveMaxX); x < buf.BufferWi; ++x) {
                            buf.SetPixel(x, flipY(static_cast<int>(perString * fp.string + perString / 2), buf.BufferHt), stringColor);
                        }
                    }

                    double diffPerFret = varyWavelengthBasedOnFret ? 0.3 : 0.0;
                    static constexpr double GUITAR_WAVE_RAMP = 3.0;

                    for (int x = 0; x < static_cast<int>(waveMaxX); ++x) {
                        double maxY = perString;
                        if (collapse) maxY *= alpha;

                        if (x < GUITAR_WAVE_RAMP) {
                            maxY *= ((double)x / GUITAR_WAVE_RAMP);
                        } else if (x >= static_cast<int>(waveMaxX - GUITAR_WAVE_RAMP - 1)) {
                            maxY *= (double)(waveMaxX - x - 1) / GUITAR_WAVE_RAMP;
                        }

                        double waveDiv = ((double)(strings - fp.string - 1) * stringWaveFactor) +
                                         baseWaveFactor + (maxFrets - fp.fret) * diffPerFret;
                        if (waveDiv < 0.001) waveDiv = 0.001;
                        int y = static_cast<int>((maxY / 2.0) *
                            std::sin((M_PI * 2.0 * cycles * (double)x / waveDiv) / waveMaxX + (pos * 2)));
                        y += static_cast<int>((perString / 2.0) + (perString * fp.string));
                        buf.SetPixel(x, flipY(y, buf.BufferHt), c);
                    }
                } else {
                    // "On" mode (default): solid rectangle for each active string
                    int onMaxX = ((maxFrets - fp.fret) * buf.BufferWi) / maxFrets;

                    if (showStrings) {
                        for (int x = onMaxX; x < buf.BufferWi; ++x) {
                            buf.SetPixel(x, flipY(static_cast<int>(perString * fp.string + perString / 2), buf.BufferHt), stringColor);
                        }
                    }

                    int centre = static_cast<int>(perString * fp.string + perString / 2);
                    int height = static_cast<int>(perString);
                    if (collapse) {
                        height = static_cast<int>(height * alpha);
                        if (height < 1) height = 1;
                    }
                    int startY = centre - height / 2;

                    for (int x = 0; x < onMaxX; ++x) {
                        for (int y = startY; y < startY + height; ++y) {
                            buf.SetPixel(x, flipY(y, buf.BufferHt), c);
                        }
                    }
                }
            }
        }

        // --- Draw inactive strings when showStrings is enabled ---
        if (showStrings) {
            float perString = (float)buf.BufferHt / strings;
            for (uint8_t s = 0; s < strings; ++s) {
                bool active = false;
                if (activeTiming) {
                    for (const auto& fp : activeTiming->fingerPos) {
                        if (fp.string == s) { active = true; break; }
                    }
                }
                if (!active) {
                    xlColor c;
                    buf.palette.GetColor(s % buf.palette.Size(), c);
                    int y = flipY(static_cast<int>(perString * s + perString / 2), buf.BufferHt);
                    for (int x = 0; x < buf.BufferWi; ++x) {
                        buf.SetPixel(x, y, c);
                    }
                }
            }
        }

        return true;
    }

    // Unknown effect type — buffer stays empty (black)
    return false;
}

void NativeRenderCoordinator::writeModelOutput(
    const ModelJob& job, int frameIndex, NativeSequenceData& output)
{
    uint8_t* frameData = output.getFrame(static_cast<uint32_t>(frameIndex));
    if (!frameData) return;

    // getColors() writes channel data at each node's actChannel offset.
    // Thread-safe: models with overlapping channels are in separate render
    // tiers and never execute concurrently (see buildRenderTiers).
    job.pixelBuffer->getColors(frameData, output.getNumChannels());
}

} // namespace xlEngine
