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

// BackgroundRenderQueue: Debounced background rendering of dirty models.
//
// When a model is marked dirty (e.g., effect edited), it can be queued here
// for background pre-rendering. The queue debounces rapid changes: if the
// same model is queued again within the debounce window, the previous timer
// is cancelled and restarted. After the debounce expires, the model is
// rendered via NativeRenderCoordinator::renderModels() on a serial GCD
// queue, writing results into the shared NativeSequenceData buffer.
//
// Thread safety:
//   - queueModel() and cancelAll() may be called from any thread (main or bg).
//   - isModelReady(), getCompletedModels(), clearCompletedModel() are thread-safe.
//   - Actual rendering runs on a private serial GCD queue.
//   - Each model writes to its own channel range in NativeSequenceData, so
//     no locking is needed for the pixel data itself.

#include <atomic>
#include <cstdint>
#include <functional>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <vector>

#include <dispatch/dispatch.h>

class NativeSequenceData;

namespace xlEngine {

class NativeRenderCoordinator;

class BackgroundRenderQueue {
public:
    // Construct with the coordinator used for rendering and the shared
    // output buffer that receives rendered channel data. Both must outlive
    // this queue.
    BackgroundRenderQueue(NativeRenderCoordinator* coordinator,
                          NativeSequenceData* output);
    ~BackgroundRenderQueue();

    BackgroundRenderQueue(const BackgroundRenderQueue&) = delete;
    BackgroundRenderQueue& operator=(const BackgroundRenderQueue&) = delete;

    // Queue a model for background rendering. If the model is already
    // pending (within the debounce window), the previous timer is cancelled
    // and a new debounce period starts. After debounceMS elapses without
    // another queue call for this model, rendering begins.
    void queueModel(const std::string& modelName, int debounceMS = 500);

    // Queue multiple models for a single batched background render.
    // All models are rendered in one renderModels() call (parallel per-frame).
    // If called again within the debounce window, the new models are merged
    // into the pending batch and the timer restarts.
    void queueBatch(const std::vector<std::string>& modelNames, int debounceMS = 500);

    // Cancel all pending debounce timers and wait for any in-progress
    // render to finish. After this returns, no background work is active.
    void cancelAll();

    // Check if a batch render is currently in progress.
    bool isBatchRendering() const;

    // Check if a background render has completed for the given model.
    bool isModelReady(const std::string& modelName) const;

    // Return the set of model names whose background render has completed.
    std::set<std::string> getCompletedModels() const;

    // Remove a model from the completed set (after its data has been consumed).
    void clearCompletedModel(const std::string& modelName);

    // Completion callback type: called on the bg queue after each model completes.
    using CompletionCallback = std::function<void(const std::string& modelName)>;

    // Set a callback invoked after each model finishes background rendering.
    // The callback fires on the private serial GCD queue — callers must dispatch
    // to their own thread if needed.
    void setCompletionCallback(CompletionCallback cb);

private:
    // Per-model debounce state. Each queueModel() call increments the
    // generation counter. The dispatched block checks whether its captured
    // generation still matches; if not, a newer request superseded it.
    struct DebounceEntry {
        uint64_t generation = 0;
    };

    NativeRenderCoordinator* _coordinator;
    NativeSequenceData* _output;

    // Serial GCD queue for background render work. Ensures only one model
    // renders at a time, preventing contention on coordinator state.
    dispatch_queue_t _bgQueue;

    // Protects _debounceState and _completedModels.
    mutable std::mutex _mutex;

    // Debounce generation counters per model name.
    std::map<std::string, DebounceEntry> _debounceState;

    // Models whose background render has completed successfully.
    std::set<std::string> _completedModels;

    // Set to true in destructor / cancelAll() to reject new work.
    bool _cancelled = false;

    // Optional callback invoked after each model render completes.
    CompletionCallback _completionCallback;

    // Batch rendering state. queueBatch() adds models here and schedules
    // a single dispatch_after. When the timer fires, all pending models
    // are rendered in one renderModels() call.
    uint64_t _batchGeneration = 0;
    std::set<std::string> _pendingBatchModels;
    std::atomic<bool> _batchRendering{false};

public:
    // Live rendering guard: set by the render engine before calling
    // liveRenderDirtyModels() and cleared after. The bg batch block
    // spins briefly if this is set to avoid concurrent effectProvider access.
    std::atomic<bool> liveRendering{false};
};

} // namespace xlEngine
