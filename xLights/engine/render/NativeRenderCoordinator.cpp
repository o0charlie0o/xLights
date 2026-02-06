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
#include "IRenderContext.h"
#include "../interfaces/IEffectProvider.h"
#include "../interfaces/IModelProvider.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <thread>

namespace xlEngine {

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

    int frameTimeMS = _context->getFrameTimeMS();
    if (frameTimeMS <= 0) frameTimeMS = 50;

    auto jobs = buildModelJobs();
    if (jobs.empty()) {
        _rendering.store(false);
        std::lock_guard<std::mutex> lock(_listenerMutex);
        if (_listener) _listener->onRenderComplete(false);
        return true;
    }

    int totalModels = static_cast<int>(jobs.size());
    std::atomic<int> modelsComplete{0};

    // Work-stealing parallel dispatch: each thread grabs the next job atomically
    unsigned int numThreads = std::min(
        static_cast<unsigned int>(jobs.size()),
        std::max(1u, std::thread::hardware_concurrency()));

    std::atomic<size_t> nextJobIdx{0};
    std::vector<std::thread> threads;
    threads.reserve(numThreads);

    for (unsigned int t = 0; t < numThreads; ++t) {
        threads.emplace_back([&]() {
            size_t idx;
            while ((idx = nextJobIdx.fetch_add(1)) < jobs.size()) {
                if (_abort.load()) return;

                renderModel(jobs[idx], startMS, endMS, output);

                int completed = modelsComplete.fetch_add(1) + 1;
                std::lock_guard<std::mutex> lock(_listenerMutex);
                if (_listener) {
                    float pct = static_cast<float>(completed) /
                                static_cast<float>(totalModels) * 100.0f;
                    _listener->onRenderProgress(pct, completed, totalModels);
                }
            }
        });
    }

    for (auto& t : threads) t.join();

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

    size_t elemIdx = _effectProvider->getElementIndex(modelName);
    if (elemIdx == SIZE_MAX) return result;

    size_t layerCount = _effectProvider->getEffectLayerCount(elemIdx);
    if (layerCount == 0) layerCount = 1;

    int w = geom.bufferWi;
    int h = geom.bufferHt;

    ModelJob job;
    job.elementIndex = elemIdx;
    job.layerCount = layerCount;
    job.pixelBuffer = std::make_unique<NativePixelBuffer>(
        _context, w, h, static_cast<int>(layerCount), geom.nodes);
    job.geometry = std::move(geom);

    renderModelAtTime(job, timeMS);

    // Extract RGBA pixel data from the blended output
    result.width = w;
    result.height = h;
    result.pixels.resize(static_cast<size_t>(w) * h * 4);

    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            xlColor c = job.pixelBuffer->getBlendedPixel(x, y);
            size_t i = (static_cast<size_t>(y) * w + x) * 4;
            result.pixels[i]     = c.red;
            result.pixels[i + 1] = c.green;
            result.pixels[i + 2] = c.blue;
            result.pixels[i + 3] = c.alpha;
        }
    }

    return result;
}

void NativeRenderCoordinator::abort() {
    _abort.store(true);
}

bool NativeRenderCoordinator::isRendering() const {
    return _rendering.load();
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

        // Only render top-level Model elements for now.
        // Submodels, strands, and timing elements are skipped.
        // Model groups will be handled via dependency graph in a future pass.
        if (info.type != SequenceElementType::Model) continue;
        if (info.renderDisabled) continue;

        ModelGeometry geom = extractGeometry(info.name);
        if (geom.bufferWi <= 0 || geom.bufferHt <= 0) continue;

        size_t layerCount = info.effectLayerCount;
        if (layerCount == 0) layerCount = 1;

        ModelJob job;
        job.elementIndex = i;
        job.layerCount = layerCount;
        job.pixelBuffer = std::make_unique<NativePixelBuffer>(
            _context, geom.bufferWi, geom.bufferHt,
            static_cast<int>(layerCount), geom.nodes);
        job.geometry = std::move(geom);

        jobs.push_back(std::move(job));
    }

    return jobs;
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

    // Buffer dimensions — prefer explicit BufferWi/Ht, fall back to parm1/parm2
    auto it = attrs.find("BufferWi");
    if (it != attrs.end() && !it->second.empty()) {
        geom.bufferWi = std::max(1, std::atoi(it->second.c_str()));
    } else {
        it = attrs.find("parm1");
        if (it != attrs.end() && !it->second.empty())
            geom.bufferWi = std::max(1, std::atoi(it->second.c_str()));
    }

    it = attrs.find("BufferHt");
    if (it != attrs.end() && !it->second.empty()) {
        geom.bufferHt = std::max(1, std::atoi(it->second.c_str()));
    } else {
        it = attrs.find("parm2");
        if (it != attrs.end() && !it->second.empty())
            geom.bufferHt = std::max(1, std::atoi(it->second.c_str()));
    }

    // Start channel (convert 1-based XML to 0-based internal)
    it = attrs.find("StartChannel");
    if (it != attrs.end() && !it->second.empty()) {
        // Note: StartChannel may be a complex expression (">ModelName:offset").
        // Simple numeric parse covers the common case; complex resolution
        // will be added when the full channel resolver is integrated.
        int sc = std::atoi(it->second.c_str());
        if (sc > 0) geom.startChannel = static_cast<uint32_t>(sc - 1);
    }

    // Derive node count from buffer dimensions (simple grid mapping)
    geom.nodeCount = static_cast<uint32_t>(geom.bufferWi) * geom.bufferHt;
    geom.channelCount = geom.nodeCount * 3; // assume RGB

    // Build simple node-to-channel mapping: each buffer pixel is one node.
    // This is correct for simple models (lines, matrices). Custom models
    // with non-trivial node layouts will need ModelEngine integration.
    geom.nodes.resize(geom.nodeCount);
    for (uint32_t n = 0; n < geom.nodeCount; ++n) {
        NativeNodeInfo& node = geom.nodes[n];
        node.bufX = static_cast<int>(n % geom.bufferWi);
        node.bufY = static_cast<int>(n / geom.bufferWi);
        node.actChannel = geom.startChannel + n * 3;
        node.channelsPerNode = 3;
        node.colorOrder[0] = 0; // R
        node.colorOrder[1] = 1; // G
        node.colorOrder[2] = 2; // B
        node.colorOrder[3] = 3;
    }

    return geom;
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

    job.pixelBuffer->clear();

    std::vector<bool> validLayers(job.layerCount, false);

    for (size_t layer = 0; layer < job.layerCount; ++layer) {
        NativeRenderBuffer& buf = job.pixelBuffer->getLayerBuffer(
            static_cast<int>(layer));
        buf.Clear();

        EffectInstanceInfo effectInfo;
        if (!_effectProvider->getEffectAtTime(
                job.elementIndex, layer, timeMS, effectInfo)) {
            continue;
        }

        // Configure render buffer timing state
        buf.SetFrameTimeInMs(frameTimeMS);
        buf.SetEffectDuration(effectInfo.startTimeMS, effectInfo.endTimeMS);
        buf.SetState(period, period == effectInfo.startTimeMS / frameTimeMS);
        buf.cur_model = job.geometry.name;

        // Set palette colors from the effect's palette map.
        // Palette entries use keys like "C_BUTTON_Palette1" through "C_BUTTON_Palette8".
        // Each value is a hex color string "#RRGGBB".
        xlColorVector colors;
        for (int ci = 1; ci <= 8; ++ci) {
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

        // TODO: Call Effect::Render() here once effects are unguarded for native build.
        //
        // Currently all effect Render methods are wrapped in #ifndef XLIGHTS_NATIVE,
        // so this is a no-op. The pixel buffer will contain black/empty pixels.
        //
        // Integration point (xlmac-6sd):
        //   SettingsMap settings = convertToSettingsMap(effectInfo.settings);
        //   RenderableEffect* eff = effectManager->GetEffect(effectInfo.effectTypeIndex);
        //   Effect effectObj;  // lightweight effect instance
        //   if (eff) eff->Render(&effectObj, settings, buf);

        validLayers[layer] = true;
    }

    job.pixelBuffer->calcOutput(period, validLayers);
}

void NativeRenderCoordinator::writeModelOutput(
    const ModelJob& job, int frameIndex, NativeSequenceData& output)
{
    uint8_t* frameData = output.getFrame(static_cast<uint32_t>(frameIndex));
    if (!frameData) return;

    // getColors() writes channel data at each node's actChannel offset.
    // Thread-safe as long as models don't share channel ranges.
    job.pixelBuffer->getColors(frameData, output.getNumChannels());
}

} // namespace xlEngine
