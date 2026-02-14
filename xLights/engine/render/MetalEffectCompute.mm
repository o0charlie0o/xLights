/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// MetalEffectCompute.mm: Singleton GPU effect renderer using Metal compute shaders.
//
// Thread-safe: each renderXxx() call creates its own MTLCommandBuffer.
// Pipeline state objects and the command queue are immutable/thread-safe.
// The output buffer is allocated per-call and results are copied back.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "MetalEffectCompute.h"
#include <cstring>

namespace xlEngine {

// =========================================================================
// Implementation detail — holds Metal objects
// =========================================================================

struct MetalEffectComputeImpl {
    id<MTLDevice> device = nil;
    id<MTLCommandQueue> commandQueue = nil;
    id<MTLComputePipelineState> onPipeline = nil;
    id<MTLComputePipelineState> colorWashPipeline = nil;
    bool available = false;

    bool initialize() {
        @autoreleasepool {
            device = MTLCreateSystemDefaultDevice();
            if (!device) {
                NSLog(@"MetalEffectCompute: No Metal device available");
                return false;
            }

            commandQueue = [device newCommandQueue];
            if (!commandQueue) {
                NSLog(@"MetalEffectCompute: Failed to create command queue");
                return false;
            }

            NSError *error = nil;
            id<MTLLibrary> library = [device newDefaultLibrary];
            if (!library) {
                NSLog(@"MetalEffectCompute: Failed to load default Metal library: %@", error);
                return false;
            }

            // Load effect kernels
            id<MTLFunction> onFunc = [library newFunctionWithName:@"effectOn"];
            if (onFunc) {
                onPipeline = [device newComputePipelineStateWithFunction:onFunc error:&error];
                if (!onPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create On pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectOn' function not found");
            }

            id<MTLFunction> cwFunc = [library newFunctionWithName:@"effectColorWash"];
            if (cwFunc) {
                colorWashPipeline = [device newComputePipelineStateWithFunction:cwFunc error:&error];
                if (!colorWashPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create ColorWash pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectColorWash' function not found");
            }

            available = (onPipeline != nil) || (colorWashPipeline != nil);
            if (available) {
                NSLog(@"MetalEffectCompute: Initialized on %@ (On=%s, ColorWash=%s)",
                      [device name],
                      onPipeline ? "yes" : "no",
                      colorWashPipeline ? "yes" : "no");
            }
            return available;
        }
    }

    void cleanup() {
        @autoreleasepool {
            onPipeline = nil;
            colorWashPipeline = nil;
            commandQueue = nil;
            device = nil;
            available = false;
        }
    }

    // Dispatch a compute kernel with the given pipeline, params, and palette.
    // Writes results into outputPixels (must be width*height xlColors).
    bool dispatch(id<MTLComputePipelineState> pipeline,
                  const void* params, size_t paramsSize,
                  const float* paletteData, size_t paletteBytes,
                  xlColor* outputPixels, uint32_t totalPixels)
    {
        if (!available || !pipeline) return false;

        @autoreleasepool {
            size_t outputSize = static_cast<size_t>(totalPixels) * 4;

            // Create buffers
            id<MTLBuffer> outputBuf = [device newBufferWithLength:outputSize
                                                         options:MTLResourceStorageModeShared];
            id<MTLBuffer> paramsBuf = [device newBufferWithBytes:params
                                                         length:paramsSize
                                                        options:MTLResourceStorageModeShared];
            id<MTLBuffer> paletteBuf = [device newBufferWithBytes:paletteData
                                                          length:paletteBytes
                                                         options:MTLResourceStorageModeShared];

            if (!outputBuf || !paramsBuf || !paletteBuf) return false;

            // Create command buffer and encoder
            id<MTLCommandBuffer> cmdBuf = [commandQueue commandBuffer];
            if (!cmdBuf) return false;

            id<MTLComputeCommandEncoder> encoder = [cmdBuf computeCommandEncoder];
            if (!encoder) return false;

            [encoder setComputePipelineState:pipeline];
            [encoder setBuffer:outputBuf   offset:0 atIndex:0];
            [encoder setBuffer:paramsBuf   offset:0 atIndex:1];
            [encoder setBuffer:paletteBuf  offset:0 atIndex:2];

            // Dispatch
            NSUInteger threadCount = static_cast<NSUInteger>(totalPixels);
            NSUInteger threadgroupSize = pipeline.maxTotalThreadsPerThreadgroup;
            if (threadgroupSize > 256) threadgroupSize = 256;
            if (threadgroupSize > threadCount) threadgroupSize = threadCount;

            [encoder dispatchThreads:MTLSizeMake(threadCount, 1, 1)
               threadsPerThreadgroup:MTLSizeMake(threadgroupSize, 1, 1)];
            [encoder endEncoding];

            [cmdBuf commit];
            [cmdBuf waitUntilCompleted];

            if (cmdBuf.status == MTLCommandBufferStatusError) {
                NSLog(@"MetalEffectCompute: Command buffer error: %@", cmdBuf.error);
                return false;
            }

            // Copy result back to CPU buffer
            std::memcpy(outputPixels, outputBuf.contents, outputSize);
            return true;
        }
    }
};

// =========================================================================
// MetalEffectCompute public interface
// =========================================================================

MetalEffectCompute& MetalEffectCompute::shared() {
    static MetalEffectCompute instance;
    return instance;
}

MetalEffectCompute::MetalEffectCompute()
    : _impl(new MetalEffectComputeImpl())
{
    _impl->initialize();
}

MetalEffectCompute::~MetalEffectCompute() {
    if (_impl) {
        _impl->cleanup();
        delete _impl;
    }
}

bool MetalEffectCompute::isAvailable() const {
    return _impl && _impl->available;
}

bool MetalEffectCompute::renderOn(xlColor* outputPixels, int width, int height,
                                   const GPUOnParams& params,
                                   const std::vector<float>& palette)
{
    if (!_impl || !_impl->onPipeline) return false;
    return _impl->dispatch(_impl->onPipeline,
                           &params, sizeof(GPUOnParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

bool MetalEffectCompute::renderColorWash(xlColor* outputPixels, int width, int height,
                                          const GPUColorWashParams& params,
                                          const std::vector<float>& palette)
{
    if (!_impl || !_impl->colorWashPipeline) return false;
    return _impl->dispatch(_impl->colorWashPipeline,
                           &params, sizeof(GPUColorWashParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

} // namespace xlEngine
