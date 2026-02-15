/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "BackgroundRenderQueue.h"
#include "NativeRenderCoordinator.h"
#include "NativeSequenceData.h"

#include <dispatch/dispatch.h>

namespace xlEngine {

BackgroundRenderQueue::BackgroundRenderQueue(
    NativeRenderCoordinator* coordinator,
    NativeSequenceData* output)
    : _coordinator(coordinator)
    , _output(output)
{
    _bgQueue = dispatch_queue_create(
        "org.xlights.backgroundRenderQueue", DISPATCH_QUEUE_SERIAL);
}

BackgroundRenderQueue::~BackgroundRenderQueue()
{
    cancelAll();
    dispatch_release(_bgQueue);
}

void BackgroundRenderQueue::queueModel(const std::string& modelName, int debounceMS)
{
    std::lock_guard<std::mutex> lock(_mutex);

    if (_cancelled) return;

    // Increment the generation for this model. Any previously dispatched
    // block for this model will see a stale generation and skip rendering.
    auto& entry = _debounceState[modelName];
    entry.generation++;
    uint64_t capturedGeneration = entry.generation;

    // Remove from completed set since the model is being re-queued
    // (its data will be stale once the new render completes).
    _completedModels.erase(modelName);

    // Schedule the render after the debounce delay. The block captures
    // the model name and generation by value. When it fires, it checks
    // whether a newer queueModel() call has superseded this one.
    dispatch_time_t when = dispatch_time(
        DISPATCH_TIME_NOW,
        static_cast<int64_t>(debounceMS) * NSEC_PER_MSEC);

    // Capture copies for the block
    std::string capturedName = modelName;
    NativeRenderCoordinator* coordinator = _coordinator;
    NativeSequenceData* output = _output;

    dispatch_after(when, _bgQueue, ^{
        // Check if this request was superseded by a newer one, or if
        // the queue has been cancelled.
        {
            std::lock_guard<std::mutex> innerLock(this->_mutex);
            if (this->_cancelled) return;

            auto it = this->_debounceState.find(capturedName);
            if (it == this->_debounceState.end()) return;
            if (it->second.generation != capturedGeneration) return;
        }

        // Render the model. renderModels() blocks until complete.
        // Each model writes to its own channel range in NativeSequenceData,
        // so no locking is needed for the pixel data.
        std::vector<std::string> models = { capturedName };
        bool success = coordinator->renderModels(models, *output);

        // Mark the model as completed if rendering succeeded.
        {
            std::lock_guard<std::mutex> innerLock(this->_mutex);
            if (this->_cancelled) return;

            // Verify the generation is still current (no new queue call
            // arrived while we were rendering).
            auto it = this->_debounceState.find(capturedName);
            if (it != this->_debounceState.end() &&
                it->second.generation == capturedGeneration &&
                success) {
                this->_completedModels.insert(capturedName);
            }
        }
    });
}

void BackgroundRenderQueue::cancelAll()
{
    {
        std::lock_guard<std::mutex> lock(_mutex);
        _cancelled = true;

        // Bump all generations so any pending dispatch_after blocks will
        // see a stale generation and skip.
        for (auto& [name, entry] : _debounceState) {
            entry.generation++;
        }
    }

    // Wait for any in-progress render on the serial queue to finish.
    // dispatch_sync on the serial queue ensures all previously submitted
    // blocks have completed before we return.
    dispatch_sync(_bgQueue, ^{
        // no-op — just drains the queue
    });

    {
        std::lock_guard<std::mutex> lock(_mutex);
        _debounceState.clear();
        _completedModels.clear();
        _cancelled = false; // Allow reuse after cancelAll
    }
}

bool BackgroundRenderQueue::isModelReady(const std::string& modelName) const
{
    std::lock_guard<std::mutex> lock(_mutex);
    return _completedModels.count(modelName) > 0;
}

std::set<std::string> BackgroundRenderQueue::getCompletedModels() const
{
    std::lock_guard<std::mutex> lock(_mutex);
    return _completedModels;
}

void BackgroundRenderQueue::clearCompletedModel(const std::string& modelName)
{
    std::lock_guard<std::mutex> lock(_mutex);
    _completedModels.erase(modelName);
}

} // namespace xlEngine
