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

// NativeRenderCoordinator: Parallel rendering orchestrator for the native macOS build.
//
// Unified rendering: both live preview (renderAllModelsStateful) and batch
// rendering (renderAll/renderRange) use the same per-frame-all-models approach.
// For each frame, all physical models are rendered in parallel via GCD
// dispatch_apply, then submodel/strand overlays are composited. Group effects
// cascade to member models via prepended layers (groupElementIndex/groupLayerCount).
//
// Architecture:
//   - IEffectProvider supplies sequence elements and effect data
//   - IModelProvider supplies model geometry and channel mapping
//   - IRenderContext supplies timing and audio info
//   - Persistent ModelJob objects are reused across frames (preparePersistentJobs)
//   - Per frame: dispatch_apply across models → renderModelAtTime()
//               → submodel compositing → writeModelOutput() to NativeSequenceData
//
// Thread safety: renderRange() and renderAll() block until complete.
// Multiple threads render different models in parallel. abort() is safe
// to call from any thread.

#include <atomic>
#include <cstdint>
#include <functional>
#include <list>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "NativePixelBuffer.h"
#include "../../Color.h"

class NativeSequenceData;
class NativeRenderBuffer;

namespace xlEngine {

struct EffectInstanceInfo;
class DiskRenderCache;
class IEffectProvider;
class IModelProvider;

// In-memory LRU cache for rendered effect layer output.
// Avoids redundant re-rendering when the same effect with the same
// parameters is queried at the same time (e.g., scrubbing back to a
// frame that was already rendered, or multiple preview passes).
//
// Cache key: model name + layer index + effect settings/palette hash + time.
// Stateful effects (Fire, Life, Meteors, etc.) are excluded from caching
// because their output depends on accumulated state across frames.
//
// Thread safety: NOT thread-safe. Caller must hold appropriate lock
// or ensure single-threaded access per cache instance.
class RenderFrameCache {
public:
    struct CachedLayer {
        std::vector<xlColor> pixels;
        int width = 0;
        int height = 0;
    };

    explicit RenderFrameCache(size_t maxEntries = 8192)
        : _maxEntries(maxEntries) {}

    // Look up a cached layer. Returns true and populates 'out' if found.
    bool get(const std::string& modelName, int layerIndex,
             size_t effectHash, int timeMS, CachedLayer& out) {
        uint64_t key = makeKey(modelName, layerIndex, effectHash, timeMS);
        auto mapIt = _map.find(key);
        if (mapIt == _map.end()) {
            ++_misses;
            return false;
        }
        // Move to front of LRU list
        _lru.splice(_lru.begin(), _lru, mapIt->second);
        out = mapIt->second->second;
        ++_hits;
        return true;
    }

    // Store a rendered layer in the cache.
    void put(const std::string& modelName, int layerIndex,
             size_t effectHash, int timeMS, const CachedLayer& entry) {
        uint64_t key = makeKey(modelName, layerIndex, effectHash, timeMS);
        auto mapIt = _map.find(key);
        if (mapIt != _map.end()) {
            // Update existing entry and move to front
            mapIt->second->second = entry;
            _lru.splice(_lru.begin(), _lru, mapIt->second);
            return;
        }
        // Evict oldest if at capacity
        while (_map.size() >= _maxEntries && !_lru.empty()) {
            auto last = std::prev(_lru.end());
            _map.erase(last->first);
            _lru.erase(last);
        }
        // Insert new entry at front
        _lru.emplace_front(key, entry);
        _map[key] = _lru.begin();
    }

    // Clear all entries for a specific model.
    void clearModel(const std::string& modelName) {
        auto it = _lru.begin();
        while (it != _lru.end()) {
            // The model name is embedded in the key via hash, but for
            // precise per-model invalidation we maintain a secondary index.
            auto next = std::next(it);
            if (_modelIndex.count(it->first) &&
                _modelIndex[it->first] == modelName) {
                _map.erase(it->first);
                _modelIndex.erase(it->first);
                _lru.erase(it);
            }
            it = next;
        }
    }

    // Clear all cached entries.
    void clear() {
        _lru.clear();
        _map.clear();
        _modelIndex.clear();
        _hits = 0;
        _misses = 0;
    }

    size_t size() const { return _map.size(); }
    size_t hits() const { return _hits; }
    size_t misses() const { return _misses; }

    // Returns true if the given effect type is safe to cache.
    // Stateful effects that accumulate across frames are excluded.
    static bool isEffectCacheable(const std::string& effectType) {
        // Effects that use EffectRenderCache (infoCache) for persistent
        // state across frames. These produce different output depending
        // on the history of previous frames, so caching by time alone
        // would produce incorrect results.
        static const std::set<std::string> statefulEffects = {
            "Fire", "Candle", "Circles", "Curtain", "Fireworks",
            "Life", "Lines", "Meteors", "Shape", "Snowflakes",
            "Snowstorm", "Strobe", "Twinkle", "Balls"
        };
        return statefulEffects.find(effectType) == statefulEffects.end();
    }

    // Compute a hash of effect settings and palette for cache keying.
    static size_t hashEffect(const std::string& effectType,
                             const std::map<std::string, std::string>& settings,
                             const std::map<std::string, std::string>& palette) {
        size_t h = std::hash<std::string>{}(effectType);
        for (const auto& [k, v] : settings) {
            h ^= std::hash<std::string>{}(k) * 31 + std::hash<std::string>{}(v);
        }
        for (const auto& [k, v] : palette) {
            h ^= std::hash<std::string>{}(k) * 37 + std::hash<std::string>{}(v);
        }
        return h;
    }

private:
    using Entry = std::pair<uint64_t, CachedLayer>;
    using LRUList = std::list<Entry>;
    using LRUIterator = LRUList::iterator;

    uint64_t makeKey(const std::string& modelName, int layerIndex,
                     size_t effectHash, int timeMS) {
        // Combine into a single 64-bit key via FNV-like mixing.
        // Collisions are rare enough for an in-memory cache.
        size_t h = std::hash<std::string>{}(modelName);
        h ^= std::hash<int>{}(layerIndex) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= effectHash + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>{}(timeMS) + 0x9e3779b9 + (h << 6) + (h >> 2);
        uint64_t key = static_cast<uint64_t>(h);

        // Store model name mapping for per-model invalidation
        _modelIndex[key] = modelName;

        return key;
    }

    size_t _maxEntries;
    LRUList _lru;
    std::unordered_map<uint64_t, LRUIterator> _map;
    std::unordered_map<uint64_t, std::string> _modelIndex;
    size_t _hits = 0;
    size_t _misses = 0;
};

// Callback interface for render progress and completion events.
class RenderCoordinatorListener {
public:
    virtual ~RenderCoordinatorListener() = default;
    virtual void onModelFrameRendered(const std::string& modelName, int timeMS) {}
    virtual void onFrameRendered(int timeMS) {}
    virtual void onRenderComplete(bool wasCancelled) {}
    virtual void onRenderProgress(float percent, int modelsComplete, int modelsTotal) {}
    virtual void onRenderError(const std::string& modelName, const std::string& message) {}
};

// A rendered frame snapshot for a single model (pixel data as RGBA).
struct RenderedFrame {
    std::string modelName;
    int width = 0;
    int height = 0;
    int timeMS = 0;
    std::vector<uint8_t> pixels; // RGBA, width * height * 4 bytes

    bool isValid() const { return !pixels.empty() && width > 0 && height > 0; }
};

// Model geometry info extracted for rendering.
struct ModelGeometry {
    std::string name;
    int bufferWi = 1;
    int bufferHt = 1;
    uint32_t nodeCount = 0;
    uint32_t channelCount = 0;
    uint32_t startChannel = 0; // 0-based absolute start channel
    std::vector<NativeNodeInfo> nodes;
};

class NativeRenderCoordinator {
public:
    NativeRenderCoordinator(IEffectProvider* effectProvider,
                            IModelProvider* modelProvider,
                            IRenderContext* context);
    ~NativeRenderCoordinator();

    NativeRenderCoordinator(const NativeRenderCoordinator&) = delete;
    NativeRenderCoordinator& operator=(const NativeRenderCoordinator&) = delete;

    void setListener(RenderCoordinatorListener* listener);

    // Set pre-resolved start channels for all models (0-based absolute channels).
    // Must be called before renderAll()/renderRange() for correct channel mapping.
    // Without this, extractGeometry() falls back to atoi() which only handles plain numbers.
    void setResolvedStartChannels(const std::unordered_map<std::string, uint32_t>& channels);

    // Render all models for the full sequence duration.
    // Returns true if completed, false if aborted.
    bool renderAll(NativeSequenceData& output);

    // Render all models for a time range.
    // Returns true if completed, false if aborted.
    bool renderRange(int startMS, int endMS, NativeSequenceData& output);

    // Render only specific models for the full sequence duration.
    // Used for incremental re-rendering when only some models are dirty.
    // The caller must zero the dirty models' channel ranges in the output
    // buffer before calling this method.
    // Returns true if completed, false if aborted.
    bool renderModels(const std::vector<std::string>& modelNames, NativeSequenceData& output);

    // Render a single model at a single time for preview.
    RenderedFrame renderModelFrame(const std::string& modelName, int timeMS);

    // Render a single model at a single time using persistent state.
    // Unlike renderModelFrame(), this reuses ModelJob objects across calls
    // so stateful effects (Fire, etc.) accumulate properly across frames.
    RenderedFrame renderModelFrameStateful(const std::string& modelName, int timeMS);

    // Render all models in parallel using persistent state.
    // Creates/looks up all ModelJobs under a single lock, then dispatches
    // rendering across multiple threads via GCD dispatch_apply.
    // Returns a vector of RenderedFrames (one per model, may be invalid if
    // the model has no effects).
    std::vector<RenderedFrame> renderAllModelsStateful(
        const std::vector<std::string>& modelNames, int timeMS);

    // Reset all persistent model state (call on backward scrub or effect edit).
    void resetPersistentState();

    // Reset persistent state for a single model.
    void resetPersistentState(const std::string& modelName);

    // Clear the in-memory render cache for all models.
    void invalidateAllCaches();

    // Clear the in-memory render cache for a specific model.
    void invalidateCache(const std::string& modelName);

    // Abort the current render. Thread-safe.
    void abort();

    // Check if rendering is active.
    bool isRendering() const;

    // Get current render progress (0.0 to 1.0).
    float getProgress() const;

private:
    // Per-model render job
    struct ModelJob {
        ModelGeometry geometry;
        size_t elementIndex = 0;
        size_t layerCount = 0;
        std::unique_ptr<NativePixelBuffer> pixelBuffer;

        // Group effect cascading: when a model has its own effects AND belongs
        // to a group with effects, both need to be rendered. Group layers come
        // first (indices 0..groupLayerCount-1), model layers follow after.
        size_t groupElementIndex = SIZE_MAX; // SIZE_MAX = no group effects
        size_t groupLayerCount = 0;

        // True when this job renders a group as a combined model (aggregated
        // member nodes into a single buffer). Group jobs render group effects
        // onto the combined geometry and distribute output to all member channels.
        bool isGroupJob = false;

        // Blend layer: when a model has BOTH its own effects AND a parent group
        // with effects, an extra layer (the last one) is allocated. Before
        // rendering the model's own effects, existing channel data from the
        // output buffer is loaded into this blend layer. This allows model
        // effects to composite on top of the group render output.
        // Matches legacy PixelBuffer behavior of numLayers + 1.
        bool hasBlendLayer = false;

        // Submodel mask: when a physical model matches a group through
        // submodel refs (e.g. group has "SingingTree/Outline" not "SingingTree"),
        // only these (bufX, bufY) positions should be kept non-black.
        bool hasSubmodelMask = false;
        std::set<std::pair<int,int>> submodelMaskPositions;

        // Submodel/strand overlay: when this job renders a submodel or strand
        // element that has its own effects in the timeline, it renders AFTER
        // the parent model and overlays its output onto parent channels.
        bool isSubmodelJob = false;
        std::string parentModelName;   // parent model name for channel overlay
        int strandIndex = -1;          // strand index (-1 = submodel, not strand)

        // Per Model buffer style: cached member model geometries for group layers.
        // When a group layer has "Per Model" or "Per Model Deep" buffer style,
        // the effect renders separately into each member's own buffer, then
        // merges back into the combined layer buffer. This vector caches the
        // member geometries to avoid re-extracting them every frame.
        //
        // perModelMembers: per-member geometry (buffer dims + node mapping).
        // perModelNodeOffset: maps member index → starting node offset in the
        //   combined group node list. Used by the merge step to copy each
        //   member's rendered pixels to the correct combined buffer positions.
        struct PerModelMember {
            std::string name;
            int bufferWi = 1;
            int bufferHt = 1;
            std::vector<NativeNodeInfo> nodes;  // Member's own node mapping
        };
        std::vector<PerModelMember> perModelMembers;
        std::vector<size_t> perModelNodeOffsets;  // Start offset per member in combined nodes
        bool perModelInfoCached = false;          // True after first extraction
    };

    // Prepared model info for rendering — points into _persistentJobs.
    struct PreparedModel {
        size_t index;           // index into modelNames / results
        ModelJob* job;          // pointer into _persistentJobs
        bool hasSubmodels;      // needs submodel compositing after render
    };

    // Prepare persistent jobs for a set of model names. Creates or looks up
    // ModelJob entries in _persistentJobs, handles group layer cascading and
    // submodel mask computation. Must be called under _stateMutex.
    // Populates physicalJobs (physical models to render) and submodelNames
    // (submodel/strand elements that need overlay compositing).
    void preparePersistentJobs(
        const std::vector<std::string>& modelNames,
        std::vector<PreparedModel>& physicalJobs,
        std::vector<std::string>& submodelNames);

    // Render all models for a time range using the unified per-frame approach.
    // For each frame: renders all models in parallel, composites submodels,
    // then writes channel data to output. Same approach as live preview.
    bool renderAllFrames(int startMS, int endMS, NativeSequenceData& output);

    // Write submodel/strand rendered pixels to NativeSequenceData channel output.
    // Maps submodel nodes to parent nodes by actChannel, skips black pixels.
    void writeSubmodelChannelOutput(
        const ModelJob& subJob, const ModelJob& parentJob,
        int frameIndex, NativeSequenceData& output);

    ModelGeometry extractGeometry(const std::string& modelName);
    ModelGeometry extractGroupGeometry(const std::string& groupName);
    size_t findParentGroupElement(const std::string& modelName);

    void renderModelAtTime(ModelJob& job, int timeMS,
                           NativeSequenceData* output = nullptr,
                           int frameIndex = -1);
    bool renderNativeEffect(const EffectInstanceInfo& effectInfo, NativeRenderBuffer& buf);
    void writeModelOutput(const ModelJob& job, int frameIndex,
                          NativeSequenceData& output);

    // Populate per-model member info on a group job for "Per Model" rendering.
    // Extracts geometry for each group member and caches it on the job.
    // @param job        The model job (must have groupElementIndex set)
    // @param deep       If true, recursively flatten nested groups (Per Model Deep)
    void populatePerModelMembers(ModelJob& job, bool deep);

    // Render a group layer using "Per Model" buffer style: creates temporary
    // per-member render buffers, renders the effect into each, then merges
    // the results back into the job's combined layer buffer.
    // @param job         The model job
    // @param layer       Layer index (must be a group layer)
    // @param effectInfo  The effect to render
    // @param layerInfo   Parsed layer settings
    // @param timeMS      Current time in milliseconds
    // @param period      Current frame period
    // @param frameTimeMS Frame time in milliseconds
    // @return true if any member rendered successfully
    bool renderPerModelLayer(ModelJob& job, size_t layer,
                             const EffectInstanceInfo& effectInfo,
                             const NativeLayerInfo& layerInfo,
                             int timeMS, int period, int frameTimeMS);

    // Timing track helpers for effects like Piano, Guitar, Arpeggio
    // Returns the element index for a named timing track, or SIZE_MAX if not found.
    size_t findTimingTrackElement(const std::string& trackName);
    // Returns all timing mark effects on the first layer of a timing track.
    std::vector<EffectInstanceInfo> getTimingMarks(const std::string& trackName);
    // Returns the timing mark active at the given time on the named track.
    bool getTimingMarkAtTime(const std::string& trackName, int timeMS, EffectInstanceInfo& outMark);

    IEffectProvider* _effectProvider;
    IModelProvider* _modelProvider;
    IRenderContext* _context;
    RenderCoordinatorListener* _listener = nullptr;

    std::atomic<bool> _abort{false};
    std::atomic<bool> _rendering{false};
    std::atomic<float> _progress{0.0f};
    mutable std::mutex _listenerMutex;

    // Persistent per-model render state for stateful live preview.
    // Keyed by model name, reused across renderModelFrameStateful() calls.
    // Protected by _stateMutex (accessed from render queue + main thread).
    std::map<std::string, ModelJob> _persistentJobs;

    // Models confirmed to have no effects (and no parent group with effects).
    // Cached to avoid repeating expensive geometry extraction + element lookup.
    std::set<std::string> _skippedModels;

    // Guards _persistentJobs and _skippedModels against concurrent access
    // from the render queue (renderModelFrameStateful) and main thread
    // (resetPersistentState called via invalidateCache).
    mutable std::recursive_mutex _stateMutex;

    // Pre-resolved start channels (0-based) keyed by model name.
    // Set by RenderEngine before renderAll() for correct channel mapping
    // with complex start channel formats (#IP:univ:ch, !Controller:ch, >Model:offset).
    std::unordered_map<std::string, uint32_t> _resolvedStartChannels;

    // Cached model geometry to avoid re-extracting from provider on every preparePersistentJobs() call.
    // Invalidated on model layout changes (resetPersistentState), NOT on effect changes.
    std::unordered_map<std::string, ModelGeometry> _geometryCache;

    // Pre-built map: model name -> group element index (from preparePersistentJobs).
    // Built once per render pass to avoid repeated O(elements) scans in findParentGroupElement.
    std::unordered_map<std::string, size_t> _modelToGroupIdx;
    bool _groupMapBuilt = false;

    // Build _modelToGroupIdx by scanning all group elements once.
    void buildGroupMembershipMap();

    // True during batch rendering (renderAllFrames). Disables LRU cache
    // lookups/stores since each frame is rendered once sequentially and
    // never revisited, making cache overhead pure waste.
    bool _batchMode = false;

    // In-memory LRU cache for rendered effect layers. Avoids redundant
    // re-rendering when scrubbing or re-visiting frames with unchanged effects.
    // Protected by _renderCacheMutex for thread-safe access during parallel rendering.
    // Disabled during batch rendering (_batchMode == true).
    RenderFrameCache _renderCache;
    mutable std::mutex _renderCacheMutex;

    // Disk-backed render cache for persistence across sessions.
    // Owned by RenderEngine, set via setDiskCache(). Null if not configured.
    DiskRenderCache* _diskCache = nullptr;

    // Hashes of effects for which beginWriteSession has been called during
    // the current batch render. Used to avoid calling beginWriteSession twice
    // for the same effect.
    std::unordered_set<uint64_t> _diskWriteSessions;

public:
    // Set the disk cache instance (owned by RenderEngine). Pass nullptr to disable.
    void setDiskCache(DiskRenderCache* cache) { _diskCache = cache; }
};

} // namespace xlEngine
