/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "NativeRenderProvider.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#ifndef XLIGHTS_NATIVE
#include "../../models/Model.h"
#include "../../models/ModelManager.h"
#include "../../PixelBuffer.h"
#include "../../RenderBuffer.h"
#endif

#include <algorithm>

namespace xlEngine {

// MARK: - NativePixelBuffer Implementation

NativePixelBuffer::NativePixelBuffer(int width, int height)
    : _width(width)
    , _height(height)
{
    size_t size = static_cast<size_t>(_width) * _height * 4;
    _pixels.resize(size, 0);
}

NativePixelBuffer::~NativePixelBuffer()
{
}

NativePixelBuffer::NativePixelBuffer(NativePixelBuffer&& other) noexcept
    : _width(other._width)
    , _height(other._height)
    , _pixels(std::move(other._pixels))
{
    other._width = 0;
    other._height = 0;
}

NativePixelBuffer& NativePixelBuffer::operator=(NativePixelBuffer&& other) noexcept
{
    if (this != &other) {
        _width = other._width;
        _height = other._height;
        _pixels = std::move(other._pixels);
        other._width = 0;
        other._height = 0;
    }
    return *this;
}

void NativePixelBuffer::setPixel(int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    if (x < 0 || x >= _width || y < 0 || y >= _height) {
        return;
    }
    size_t idx = (static_cast<size_t>(y) * _width + x) * 4;
    _pixels[idx] = r;
    _pixels[idx + 1] = g;
    _pixels[idx + 2] = b;
    _pixels[idx + 3] = a;
}

void NativePixelBuffer::getPixel(int x, int y, uint8_t& r, uint8_t& g, uint8_t& b, uint8_t& a) const
{
    if (x < 0 || x >= _width || y < 0 || y >= _height) {
        r = g = b = a = 0;
        return;
    }
    size_t idx = (static_cast<size_t>(y) * _width + x) * 4;
    r = _pixels[idx];
    g = _pixels[idx + 1];
    b = _pixels[idx + 2];
    a = _pixels[idx + 3];
}

void NativePixelBuffer::clear()
{
    std::fill(_pixels.begin(), _pixels.end(), 0);
}

// MARK: - NativeRenderProvider Construction / Destruction

NativeRenderProvider::NativeRenderProvider()
#ifndef XLIGHTS_NATIVE
    : _externalManager(nullptr)
    , _sequenceDataSource(nullptr)
#else
    : _sequenceDataSource(nullptr)
#endif
    , _metalDevice(nil)
    , _metalCommandQueue(nil)
    , _gpuAvailable(false)
    , _gpuEnabled(true)
    , _isRendering(false)
    , _cancelRequested(false)
    , _renderProgress(0.0f)
    , _renderStartFrame(0)
    , _renderEndFrame(0)
    , _renderThreadRunning(false)
    , _renderRequested(false)
{
    _gpuAvailable = initializeMetal();
    if (_gpuAvailable) {
        NSLog(@"NativeRenderProvider: Metal GPU rendering available");
    } else {
        NSLog(@"NativeRenderProvider: Metal not available, CPU-only mode");
    }
}

#ifndef XLIGHTS_NATIVE
NativeRenderProvider::NativeRenderProvider(ModelManager& manager)
    : _externalManager(&manager)
    , _sequenceDataSource(nullptr)
    , _metalDevice(nil)
    , _metalCommandQueue(nil)
    , _gpuAvailable(false)
    , _gpuEnabled(true)
    , _isRendering(false)
    , _cancelRequested(false)
    , _renderProgress(0.0f)
    , _renderStartFrame(0)
    , _renderEndFrame(0)
    , _renderThreadRunning(false)
    , _renderRequested(false)
{
    _gpuAvailable = initializeMetal();
    if (_gpuAvailable) {
        NSLog(@"NativeRenderProvider: Metal GPU rendering available (with external manager)");
    } else {
        NSLog(@"NativeRenderProvider: Metal not available, CPU-only mode (with external manager)");
    }
}
#endif

NativeRenderProvider::~NativeRenderProvider()
{
    stopRenderThread();
    cleanupMetal();
    clearNativePixelBuffers();
}

// MARK: - Metal Infrastructure

bool NativeRenderProvider::initializeMetal()
{
    @autoreleasepool {
        // Get the default Metal device
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) {
            NSLog(@"NativeRenderProvider: No Metal device available");
            return false;
        }

        _metalDevice = device;

        // Create command queue
        id<MTLCommandQueue> queue = [device newCommandQueue];
        if (queue == nil) {
            NSLog(@"NativeRenderProvider: Failed to create Metal command queue");
            _metalDevice = nil;
            return false;
        }

        _metalCommandQueue = queue;

        NSLog(@"NativeRenderProvider: Metal initialized with device: %@", [device name]);
        return true;
    }
}

void NativeRenderProvider::cleanupMetal()
{
    @autoreleasepool {
        _metalCommandQueue = nil;
        _metalDevice = nil;
    }
}

id NativeRenderProvider::getMetalDevice() const
{
    return _metalDevice;
}

id NativeRenderProvider::getMetalCommandQueue() const
{
    return _metalCommandQueue;
}

// MARK: - IRenderProvider: Buffer Access

RenderBuffer* NativeRenderProvider::getRenderBuffer(const std::string& modelName)
{
    // During the transition period, RenderBuffer creation requires
    // the full wxWidgets-based pipeline. Return nullptr for now.
    // Native pixel buffers (NativePixelBuffer) are available via
    // getNativePixelBuffer() for pure native rendering.
    return nullptr;
}

PixelBufferClass* NativeRenderProvider::getPixelBuffer(const std::string& modelName)
{
    // Similar to getRenderBuffer, PixelBufferClass requires the wxWidgets
    // pipeline. Return nullptr during transition. Native code should use
    // getNativePixelBuffer() instead.
    return nullptr;
}

// MARK: - IRenderProvider: Frame Data Access

RawFrameData NativeRenderProvider::getFrameData(int frameIndex) const
{
    RawFrameData result;

    if (_sequenceDataSource && _sequenceDataSource->isValid()) {
        int frameCount = _sequenceDataSource->getFrameCount();
        if (frameIndex >= 0 && frameIndex < frameCount) {
            result.data = _sequenceDataSource->getFrameData(frameIndex);
            result.channelCount = _sequenceDataSource->getChannelCount();
            result.frameIndex = frameIndex;
        }
    }

    return result;
}

size_t NativeRenderProvider::getTotalChannels() const
{
    if (_sequenceDataSource && _sequenceDataSource->isValid()) {
        return _sequenceDataSource->getChannelCount();
    }
    return 0;
}

// MARK: - IRenderProvider: GPU / Graphics Context

void* NativeRenderProvider::getGPUContext()
{
    // Return the Metal command queue as the GPU context.
    // This can be used by the existing xlMetalGraphicsContext for rendering.
    return (__bridge void*)_metalCommandQueue;
}

bool NativeRenderProvider::isGPUAvailable() const
{
    return _gpuAvailable;
}

bool NativeRenderProvider::isGPUEnabled() const
{
    return _gpuEnabled.load();
}

// MARK: - IRenderProvider: Render Control

void NativeRenderProvider::requestRender(int startFrame, int endFrame)
{
    if (_isRendering.load()) {
        NSLog(@"NativeRenderProvider: Render already in progress, ignoring request");
        return;
    }

    {
        std::lock_guard<std::mutex> lock(_renderMutex);
        _renderStartFrame = startFrame;
        _renderEndFrame = endFrame;
        _renderRequested.store(true);
        _cancelRequested.store(false);
    }

    startRenderThread();
    _renderCondition.notify_one();

    NSLog(@"NativeRenderProvider: Render requested for frames %d to %d", startFrame, endFrame);
}

bool NativeRenderProvider::isRendering() const
{
    return _isRendering.load();
}

void NativeRenderProvider::cancelRender()
{
    _cancelRequested.store(true);
    NSLog(@"NativeRenderProvider: Render cancellation requested");
}

float NativeRenderProvider::getRenderProgress() const
{
    return _renderProgress.load();
}

// MARK: - IRenderProvider: Callbacks

void NativeRenderProvider::setRenderProgressCallback(RenderProgressCallback callback)
{
    std::lock_guard<std::mutex> lock(_callbackMutex);
    _progressCallback = std::move(callback);
}

void NativeRenderProvider::setRenderCompleteCallback(RenderCompleteCallback callback)
{
    std::lock_guard<std::mutex> lock(_callbackMutex);
    _completeCallback = std::move(callback);
}

// MARK: - IRenderProvider: Sequence Information

int NativeRenderProvider::getFrameTimeMS() const
{
    if (_sequenceDataSource && _sequenceDataSource->isValid()) {
        return _sequenceDataSource->getFrameTimeMS();
    }
    return 50; // Default frame time
}

int NativeRenderProvider::getTotalFrames() const
{
    if (_sequenceDataSource && _sequenceDataSource->isValid()) {
        return _sequenceDataSource->getFrameCount();
    }
    return 0;
}

int NativeRenderProvider::getSequenceDurationMS() const
{
    if (_sequenceDataSource && _sequenceDataSource->isValid()) {
        return _sequenceDataSource->getDurationMS();
    }
    return 0;
}

// MARK: - Native Configuration

void NativeRenderProvider::setSequenceDataSource(ISequenceDataSource* source)
{
    _sequenceDataSource = source;
    if (source && source->isValid()) {
        NSLog(@"NativeRenderProvider: Sequence data source set, %d frames, %zu channels",
              source->getFrameCount(), source->getChannelCount());
    } else {
        NSLog(@"NativeRenderProvider: Sequence data source cleared or invalid");
    }
}

void NativeRenderProvider::setGPUEnabled(bool enabled)
{
    _gpuEnabled.store(enabled && _gpuAvailable);
    NSLog(@"NativeRenderProvider: GPU rendering %s",
          _gpuEnabled.load() ? "enabled" : "disabled");
}

NativePixelBuffer* NativeRenderProvider::getNativePixelBuffer(const std::string& modelName)
{
    std::lock_guard<std::mutex> lock(_bufferMutex);
    auto it = _nativePixelBuffers.find(modelName);
    if (it != _nativePixelBuffers.end()) {
        return it->second.get();
    }
    return nullptr;
}

NativePixelBuffer* NativeRenderProvider::createNativePixelBuffer(const std::string& modelName,
                                                                  int width, int height)
{
    if (width <= 0 || height <= 0) {
        NSLog(@"NativeRenderProvider: Invalid buffer dimensions for '%s': %dx%d",
              modelName.c_str(), width, height);
        return nullptr;
    }

    std::lock_guard<std::mutex> lock(_bufferMutex);

    // Remove existing buffer if any
    _nativePixelBuffers.erase(modelName);

    // Create new buffer
    auto buffer = std::make_unique<NativePixelBuffer>(width, height);
    NativePixelBuffer* ptr = buffer.get();
    _nativePixelBuffers[modelName] = std::move(buffer);

    NSLog(@"NativeRenderProvider: Created native pixel buffer for '%s': %dx%d",
          modelName.c_str(), width, height);

    return ptr;
}

void NativeRenderProvider::removeNativePixelBuffer(const std::string& modelName)
{
    std::lock_guard<std::mutex> lock(_bufferMutex);
    auto it = _nativePixelBuffers.find(modelName);
    if (it != _nativePixelBuffers.end()) {
        _nativePixelBuffers.erase(it);
        NSLog(@"NativeRenderProvider: Removed native pixel buffer for '%s'", modelName.c_str());
    }
}

void NativeRenderProvider::clearNativePixelBuffers()
{
    std::lock_guard<std::mutex> lock(_bufferMutex);
    _nativePixelBuffers.clear();
    NSLog(@"NativeRenderProvider: Cleared all native pixel buffers");
}

// MARK: - Background Render Thread

void NativeRenderProvider::startRenderThread()
{
    if (_renderThreadRunning.load()) {
        return;
    }

    _renderThreadRunning.store(true);
    _renderThread = std::thread(&NativeRenderProvider::renderThreadFunc, this);

    NSLog(@"NativeRenderProvider: Render thread started");
}

void NativeRenderProvider::stopRenderThread()
{
    if (!_renderThreadRunning.load()) {
        return;
    }

    _renderThreadRunning.store(false);
    _cancelRequested.store(true);
    _renderCondition.notify_one();

    if (_renderThread.joinable()) {
        _renderThread.join();
    }

    NSLog(@"NativeRenderProvider: Render thread stopped");
}

void NativeRenderProvider::renderThreadFunc()
{
    NSLog(@"NativeRenderProvider: Render thread running");

    while (_renderThreadRunning.load()) {
        int startFrame = 0;
        int endFrame = 0;
        bool hasWork = false;

        {
            std::unique_lock<std::mutex> lock(_renderMutex);

            // Wait for work or shutdown
            _renderCondition.wait(lock, [this] {
                return _renderRequested.load() || !_renderThreadRunning.load();
            });

            if (!_renderThreadRunning.load()) {
                break;
            }

            if (_renderRequested.load()) {
                hasWork = true;
                startFrame = _renderStartFrame;
                endFrame = _renderEndFrame;
                _renderRequested.store(false);
            }
        }

        if (hasWork) {
            _isRendering.store(true);
            _renderProgress.store(0.0f);

            int totalFrames = endFrame - startFrame + 1;
            bool wasCancelled = false;

            NSLog(@"NativeRenderProvider: Starting render of %d frames", totalFrames);

            for (int frame = startFrame; frame <= endFrame && !_cancelRequested.load(); ++frame) {
                renderFrame(frame);

                int completed = frame - startFrame + 1;
                float progress = static_cast<float>(completed) / totalFrames;
                _renderProgress.store(progress);
                notifyProgress(progress);
            }

            wasCancelled = _cancelRequested.load();
            _cancelRequested.store(false);
            _isRendering.store(false);
            _renderProgress.store(wasCancelled ? _renderProgress.load() : 1.0f);

            NSLog(@"NativeRenderProvider: Render %s", wasCancelled ? "cancelled" : "complete");

            notifyComplete(wasCancelled);
        }
    }

    NSLog(@"NativeRenderProvider: Render thread exiting");
}

void NativeRenderProvider::renderFrame(int frameIndex)
{
    // Frame rendering implementation.
    // During the transition period, this uses the external ModelManager
    // if available, otherwise works with native pixel buffers.
    //
    // Full effect rendering requires integration with the effect system,
    // which will be completed when the Effect classes are decoupled from
    // wxWidgets. For now, this provides the infrastructure for frame-by-frame
    // rendering with callback support.

#ifndef XLIGHTS_NATIVE
    if (_externalManager) {
        // When using external ModelManager, iterate through models and
        // create native pixel buffers for each if not already present.
        std::lock_guard<std::mutex> lock(_bufferMutex);

        for (auto it = _externalManager->begin(); it != _externalManager->end(); ++it) {
            const std::string& modelName = it->first;
            Model* model = it->second;

            if (!model) continue;

            // Check if we have a buffer for this model
            auto bufIt = _nativePixelBuffers.find(modelName);
            if (bufIt == _nativePixelBuffers.end()) {
                int width = model->GetDefaultBufferWi();
                int height = model->GetDefaultBufferHt();
                if (width > 0 && height > 0) {
                    _nativePixelBuffers[modelName] =
                        std::make_unique<NativePixelBuffer>(width, height);
                }
            }
        }
    }
#endif

    // Note: Actual effect rendering will be added when the effect system
    // is decoupled from wxWidgets. The infrastructure for GPU rendering
    // via Metal is available through _metalDevice and _metalCommandQueue.
}

void NativeRenderProvider::notifyProgress(float progress)
{
    RenderProgressCallback callback;
    {
        std::lock_guard<std::mutex> lock(_callbackMutex);
        callback = _progressCallback;
    }
    if (callback) {
        callback(progress);
    }
}

void NativeRenderProvider::notifyComplete(bool wasCancelled)
{
    RenderCompleteCallback callback;
    {
        std::lock_guard<std::mutex> lock(_callbackMutex);
        callback = _completeCallback;
    }
    if (callback) {
        callback(wasCancelled);
    }
}

} // namespace xlEngine
