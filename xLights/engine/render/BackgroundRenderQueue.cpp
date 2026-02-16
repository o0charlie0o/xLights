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

#include <chrono>
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
        printf("[RDBG] BackgroundRenderQueue: rendering model '%s' (gen=%llu)\n",
               capturedName.c_str(), capturedGeneration);
        std::vector<std::string> models = { capturedName };
        bool success = coordinator->renderModels(models, *output);

        printf("[RDBG] BackgroundRenderQueue: model '%s' render %s (gen=%llu)\n",
               capturedName.c_str(), success ? "SUCCEEDED" : "FAILED", capturedGeneration);

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
                printf("[RDBG] BackgroundRenderQueue: model '%s' marked COMPLETED\n",
                       capturedName.c_str());
            }
        }

        // Invoke completion callback outside the lock
        if (success) {
            CompletionCallback cb;
            {
                std::lock_guard<std::mutex> innerLock(this->_mutex);
                cb = this->_completionCallback;
            }
            if (cb) cb(capturedName);
        }
    });
}

void BackgroundRenderQueue::queueBatch(const std::vector<std::string>& modelNames, int debounceMS)
{
    if (modelNames.empty()) return;

    std::lock_guard<std::mutex> lock(_mutex);
    if (_cancelled) return;

    // Merge new models into the pending batch set
    for (const auto& name : modelNames) {
        _pendingBatchModels.insert(name);
        _completedModels.erase(name);
    }

    // Bump batch generation — any previously scheduled batch block will see
    // a stale generation and skip.
    _batchGeneration++;
    uint64_t capturedGeneration = _batchGeneration;

    dispatch_time_t when = dispatch_time(
        DISPATCH_TIME_NOW,
        static_cast<int64_t>(debounceMS) * NSEC_PER_MSEC);

    NativeRenderCoordinator* coordinator = _coordinator;
    NativeSequenceData* output = _output;

    dispatch_after(when, _bgQueue, ^{
        // Snapshot the pending batch under lock, checking generation
        std::vector<std::string> batch;
        {
            std::lock_guard<std::mutex> innerLock(this->_mutex);
            if (this->_cancelled) return;
            if (this->_batchGeneration != capturedGeneration) return;

            batch.assign(this->_pendingBatchModels.begin(),
                         this->_pendingBatchModels.end());
            this->_pendingBatchModels.clear();
        }

        if (batch.empty()) return;

        this->_batchRendering.store(true);

        printf("[RDBG] BackgroundRenderQueue: batch rendering %zu models (gen=%llu)\n",
               batch.size(), capturedGeneration);

        auto t0 = std::chrono::steady_clock::now();
        bool success = coordinator->renderModels(batch, *output);
        auto t1 = std::chrono::steady_clock::now();
        double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

        this->_batchRendering.store(false);

        printf("[RDBG] BackgroundRenderQueue: batch render %s (%zu models, %.1fms)\n",
               success ? "SUCCEEDED" : "FAILED", batch.size(), ms);

        if (!success) return;

        // Mark all models as completed and fire per-model callbacks
        CompletionCallback cb;
        {
            std::lock_guard<std::mutex> innerLock(this->_mutex);
            if (this->_cancelled) return;
            cb = this->_completionCallback;
            for (const auto& name : batch) {
                this->_completedModels.insert(name);
            }
        }

        // Fire completion callback for each model so RenderEngine can
        // update cache entries individually
        if (cb) {
            for (const auto& name : batch) {
                cb(name);
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
        _batchGeneration++;
        _pendingBatchModels.clear();
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

bool BackgroundRenderQueue::isBatchRendering() const
{
    return _batchRendering.load();
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

void BackgroundRenderQueue::setCompletionCallback(CompletionCallback cb)
{
    std::lock_guard<std::mutex> lock(_mutex);
    _completionCallback = std::move(cb);
}

} // namespace xlEngine
