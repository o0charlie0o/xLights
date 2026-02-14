/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// MetalBlendingCompute.mm: Obj-C++ implementation of GPU-accelerated layer
// blending using Metal compute shaders.
//
// This file manages the Metal device, compute pipeline, and buffer allocation.
// The actual blending math lives in NativeLayerBlendingShaders.metal.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "MetalBlendingCompute.h"

#include <cstring>

namespace xlEngine {

// =========================================================================
// Implementation detail — holds Metal objects
// =========================================================================

struct MetalBlendingComputeImpl {
    id<MTLDevice> device = nil;
    id<MTLCommandQueue> commandQueue = nil;
    id<MTLComputePipelineState> blendPipeline = nil;
    bool available = false;

    // Reusable Metal buffers — grown as needed, never shrunk.
    // This avoids per-frame allocation overhead.
    id<MTLBuffer> paramsBuffer = nil;
    id<MTLBuffer> layerSettingsBuffer = nil;
    id<MTLBuffer> layerPixelBuffer = nil;
    id<MTLBuffer> maskBuffer = nil;
    id<MTLBuffer> outputBuffer = nil;

    size_t layerPixelBufferSize = 0;
    size_t maskBufferSize = 0;
    size_t outputBufferSize = 0;
    size_t layerSettingsBufferSize = 0;

    bool initialize() {
        @autoreleasepool {
            device = MTLCreateSystemDefaultDevice();
            if (!device) {
                NSLog(@"MetalBlendingCompute: No Metal device available");
                return false;
            }

            commandQueue = [device newCommandQueue];
            if (!commandQueue) {
                NSLog(@"MetalBlendingCompute: Failed to create command queue");
                return false;
            }

            // Load the default Metal library (compiled .metal files in the app bundle)
            NSError *error = nil;
            id<MTLLibrary> library = [device newDefaultLibrary];
            if (!library) {
                NSLog(@"MetalBlendingCompute: Failed to load default Metal library: %@", error);
                return false;
            }

            // Find the blendLayers compute function
            id<MTLFunction> blendFunction = [library newFunctionWithName:@"blendLayers"];
            if (!blendFunction) {
                NSLog(@"MetalBlendingCompute: 'blendLayers' function not found in Metal library");
                return false;
            }

            blendPipeline = [device newComputePipelineStateWithFunction:blendFunction error:&error];
            if (!blendPipeline) {
                NSLog(@"MetalBlendingCompute: Failed to create compute pipeline: %@", error);
                return false;
            }

            // Pre-allocate the small params buffer (constant size)
            paramsBuffer = [device newBufferWithLength:sizeof(GPUBlendParams)
                                              options:MTLResourceStorageModeShared];

            NSLog(@"MetalBlendingCompute: Initialized successfully on %@", [device name]);
            available = true;
            return true;
        }
    }

    void cleanup() {
        @autoreleasepool {
            blendPipeline = nil;
            paramsBuffer = nil;
            layerSettingsBuffer = nil;
            layerPixelBuffer = nil;
            maskBuffer = nil;
            outputBuffer = nil;
            commandQueue = nil;
            device = nil;
            available = false;
        }
    }

    // Ensure a buffer is at least the requested size. Returns the buffer.
    id<MTLBuffer> ensureBuffer(id<MTLBuffer> __strong &buf, size_t &currentSize, size_t requiredSize) {
        if (buf && currentSize >= requiredSize) {
            return buf;
        }
        // Grow with some headroom to avoid frequent reallocations
        size_t allocSize = requiredSize + (requiredSize / 4);
        // Minimum 256 bytes for Metal alignment
        if (allocSize < 256) allocSize = 256;
        buf = [device newBufferWithLength:allocSize
                                  options:MTLResourceStorageModeShared];
        currentSize = allocSize;
        return buf;
    }
};

// =========================================================================
// MetalBlendingCompute public interface
// =========================================================================

MetalBlendingCompute::MetalBlendingCompute()
    : _impl(new MetalBlendingComputeImpl())
{
    _impl->initialize();
}

MetalBlendingCompute::~MetalBlendingCompute() {
    if (_impl) {
        _impl->cleanup();
        delete _impl;
    }
}

MetalBlendingCompute::MetalBlendingCompute(MetalBlendingCompute&& other) noexcept
    : _impl(other._impl)
{
    other._impl = nullptr;
}

MetalBlendingCompute& MetalBlendingCompute::operator=(MetalBlendingCompute&& other) noexcept {
    if (this != &other) {
        if (_impl) {
            _impl->cleanup();
            delete _impl;
        }
        _impl = other._impl;
        other._impl = nullptr;
    }
    return *this;
}

bool MetalBlendingCompute::isAvailable() const {
    return _impl && _impl->available;
}

bool MetalBlendingCompute::blendLayers(
    const GPUBlendParams& params,
    const std::vector<GPULayerSettings>& layerSettings,
    const uint8_t* layerPixelData,
    size_t layerPixelDataSize,
    const uint8_t* maskData,
    size_t maskDataSize,
    xlColor* outputPixels)
{
    if (!_impl || !_impl->available) return false;
    if (params.totalPixels <= 0 || params.numLayers <= 0) return false;

    @autoreleasepool {
        // ---- Prepare buffers ----

        // Params buffer (small, constant size)
        std::memcpy(_impl->paramsBuffer.contents, &params, sizeof(GPUBlendParams));

        // Layer settings buffer
        size_t settingsSize = layerSettings.size() * sizeof(GPULayerSettings);
        _impl->ensureBuffer(_impl->layerSettingsBuffer, _impl->layerSettingsBufferSize, settingsSize);
        if (!_impl->layerSettingsBuffer) return false;
        std::memcpy(_impl->layerSettingsBuffer.contents, layerSettings.data(), settingsSize);

        // Layer pixel data buffer
        _impl->ensureBuffer(_impl->layerPixelBuffer, _impl->layerPixelBufferSize, layerPixelDataSize);
        if (!_impl->layerPixelBuffer) return false;
        std::memcpy(_impl->layerPixelBuffer.contents, layerPixelData, layerPixelDataSize);

        // Mask data buffer (may be empty)
        size_t maskSizeToUse = maskDataSize > 0 ? maskDataSize : 256;
        _impl->ensureBuffer(_impl->maskBuffer, _impl->maskBufferSize, maskSizeToUse);
        if (!_impl->maskBuffer) return false;
        if (maskData && maskDataSize > 0) {
            std::memcpy(_impl->maskBuffer.contents, maskData, maskDataSize);
        }

        // Output buffer
        size_t outputSize = static_cast<size_t>(params.totalPixels) * 4;
        _impl->ensureBuffer(_impl->outputBuffer, _impl->outputBufferSize, outputSize);
        if (!_impl->outputBuffer) return false;

        // ---- Create command buffer and encoder ----

        id<MTLCommandBuffer> commandBuffer = [_impl->commandQueue commandBuffer];
        if (!commandBuffer) return false;

        id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
        if (!encoder) return false;

        [encoder setComputePipelineState:_impl->blendPipeline];
        [encoder setBuffer:_impl->paramsBuffer         offset:0 atIndex:0];
        [encoder setBuffer:_impl->layerSettingsBuffer  offset:0 atIndex:1];
        [encoder setBuffer:_impl->layerPixelBuffer     offset:0 atIndex:2];
        [encoder setBuffer:_impl->maskBuffer           offset:0 atIndex:3];
        [encoder setBuffer:_impl->outputBuffer         offset:0 atIndex:4];

        // ---- Dispatch ----

        NSUInteger threadCount = static_cast<NSUInteger>(params.totalPixels);
        NSUInteger threadgroupSize = _impl->blendPipeline.maxTotalThreadsPerThreadgroup;
        if (threadgroupSize > 256) threadgroupSize = 256;
        if (threadgroupSize > threadCount) threadgroupSize = threadCount;

        MTLSize gridSize = MTLSizeMake(threadCount, 1, 1);
        MTLSize groupSize = MTLSizeMake(threadgroupSize, 1, 1);

        [encoder dispatchThreads:gridSize threadsPerThreadgroup:groupSize];
        [encoder endEncoding];

        // ---- Execute and wait ----

        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];

        // Check for errors
        if (commandBuffer.status == MTLCommandBufferStatusError) {
            NSLog(@"MetalBlendingCompute: Command buffer error: %@", commandBuffer.error);
            return false;
        }

        // ---- Copy result back ----

        std::memcpy(outputPixels, _impl->outputBuffer.contents, outputSize);
        return true;
    }
}

} // namespace xlEngine
