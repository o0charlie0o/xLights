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
    id<MTLComputePipelineState> barsPipeline = nil;
    id<MTLComputePipelineState> butterflyPipeline = nil;
    id<MTLComputePipelineState> plasmaPipeline = nil;
    id<MTLComputePipelineState> shimmerPipeline = nil;
    id<MTLComputePipelineState> wavePipeline = nil;
    id<MTLComputePipelineState> curtainPipeline = nil;
    id<MTLComputePipelineState> pinwheelPipeline = nil;
    id<MTLComputePipelineState> spiralsPipeline = nil;
    id<MTLComputePipelineState> spirographPipeline = nil;
    id<MTLComputePipelineState> strobePipeline = nil;
    id<MTLComputePipelineState> twinklePipeline = nil;
    id<MTLComputePipelineState> singleStrandPipeline = nil;
    id<MTLComputePipelineState> garlandsPipeline = nil;
    id<MTLComputePipelineState> ripplePipeline = nil;
    id<MTLComputePipelineState> shockwavePipeline = nil;
    id<MTLComputePipelineState> fanPipeline = nil;
    id<MTLComputePipelineState> marqueePipeline = nil;
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

            id<MTLFunction> barsFunc = [library newFunctionWithName:@"effectBars"];
            if (barsFunc) {
                barsPipeline = [device newComputePipelineStateWithFunction:barsFunc error:&error];
                if (!barsPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Bars pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectBars' function not found");
            }

            id<MTLFunction> bfFunc = [library newFunctionWithName:@"effectButterfly"];
            if (bfFunc) {
                butterflyPipeline = [device newComputePipelineStateWithFunction:bfFunc error:&error];
                if (!butterflyPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Butterfly pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectButterfly' function not found");
            }

            id<MTLFunction> plasmaFunc = [library newFunctionWithName:@"effectPlasma"];
            if (plasmaFunc) {
                plasmaPipeline = [device newComputePipelineStateWithFunction:plasmaFunc error:&error];
                if (!plasmaPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Plasma pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectPlasma' function not found");
            }

            id<MTLFunction> shimmerFunc = [library newFunctionWithName:@"effectShimmer"];
            if (shimmerFunc) {
                shimmerPipeline = [device newComputePipelineStateWithFunction:shimmerFunc error:&error];
                if (!shimmerPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Shimmer pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectShimmer' function not found");
            }

            id<MTLFunction> waveFunc = [library newFunctionWithName:@"effectWave"];
            if (waveFunc) {
                wavePipeline = [device newComputePipelineStateWithFunction:waveFunc error:&error];
                if (!wavePipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Wave pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectWave' function not found");
            }

            id<MTLFunction> curtainFunc = [library newFunctionWithName:@"effectCurtain"];
            if (curtainFunc) {
                curtainPipeline = [device newComputePipelineStateWithFunction:curtainFunc error:&error];
                if (!curtainPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Curtain pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectCurtain' function not found");
            }

            id<MTLFunction> pwFunc = [library newFunctionWithName:@"effectPinwheel"];
            if (pwFunc) {
                pinwheelPipeline = [device newComputePipelineStateWithFunction:pwFunc error:&error];
                if (!pinwheelPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Pinwheel pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectPinwheel' function not found");
            }

            id<MTLFunction> spiralsFunc = [library newFunctionWithName:@"effectSpirals"];
            if (spiralsFunc) {
                spiralsPipeline = [device newComputePipelineStateWithFunction:spiralsFunc error:&error];
                if (!spiralsPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Spirals pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectSpirals' function not found");
            }

            id<MTLFunction> spiroFunc = [library newFunctionWithName:@"effectSpirograph"];
            if (spiroFunc) {
                spirographPipeline = [device newComputePipelineStateWithFunction:spiroFunc error:&error];
                if (!spirographPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Spirograph pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectSpirograph' function not found");
            }

            id<MTLFunction> strobeFunc = [library newFunctionWithName:@"effectStrobe"];
            if (strobeFunc) {
                strobePipeline = [device newComputePipelineStateWithFunction:strobeFunc error:&error];
                if (!strobePipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Strobe pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectStrobe' function not found");
            }

            id<MTLFunction> twinkleFunc = [library newFunctionWithName:@"effectTwinkle"];
            if (twinkleFunc) {
                twinklePipeline = [device newComputePipelineStateWithFunction:twinkleFunc error:&error];
                if (!twinklePipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Twinkle pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectTwinkle' function not found");
            }

            id<MTLFunction> ssFunc = [library newFunctionWithName:@"effectSingleStrand"];
            if (ssFunc) {
                singleStrandPipeline = [device newComputePipelineStateWithFunction:ssFunc error:&error];
                if (!singleStrandPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create SingleStrand pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectSingleStrand' function not found");
            }

            id<MTLFunction> garlandsFunc = [library newFunctionWithName:@"effectGarlands"];
            if (garlandsFunc) {
                garlandsPipeline = [device newComputePipelineStateWithFunction:garlandsFunc error:&error];
                if (!garlandsPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Garlands pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectGarlands' function not found");
            }

            id<MTLFunction> rippleFunc = [library newFunctionWithName:@"effectRipple"];
            if (rippleFunc) {
                ripplePipeline = [device newComputePipelineStateWithFunction:rippleFunc error:&error];
                if (!ripplePipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Ripple pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectRipple' function not found");
            }

            id<MTLFunction> swFunc = [library newFunctionWithName:@"effectShockwave"];
            if (swFunc) {
                shockwavePipeline = [device newComputePipelineStateWithFunction:swFunc error:&error];
                if (!shockwavePipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Shockwave pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectShockwave' function not found");
            }

            id<MTLFunction> fanFunc = [library newFunctionWithName:@"effectFan"];
            if (fanFunc) {
                fanPipeline = [device newComputePipelineStateWithFunction:fanFunc error:&error];
                if (!fanPipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Fan pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectFan' function not found");
            }

            id<MTLFunction> marqueeFunc = [library newFunctionWithName:@"effectMarquee"];
            if (marqueeFunc) {
                marqueePipeline = [device newComputePipelineStateWithFunction:marqueeFunc error:&error];
                if (!marqueePipeline) {
                    NSLog(@"MetalEffectCompute: Failed to create Marquee pipeline: %@", error);
                }
            } else {
                NSLog(@"MetalEffectCompute: 'effectMarquee' function not found");
            }

            available = (onPipeline != nil) || (colorWashPipeline != nil)
                || (barsPipeline != nil) || (butterflyPipeline != nil)
                || (plasmaPipeline != nil) || (shimmerPipeline != nil)
                || (wavePipeline != nil) || (curtainPipeline != nil)
                || (pinwheelPipeline != nil) || (spiralsPipeline != nil)
                || (spirographPipeline != nil) || (strobePipeline != nil)
                || (twinklePipeline != nil) || (singleStrandPipeline != nil)
                || (garlandsPipeline != nil) || (ripplePipeline != nil)
                || (shockwavePipeline != nil) || (fanPipeline != nil)
                || (marqueePipeline != nil);
            if (available) {
                NSLog(@"MetalEffectCompute: Initialized on %@ (On=%s, ColorWash=%s, Bars=%s, Butterfly=%s, Plasma=%s, Shimmer=%s, Wave=%s, Curtain=%s, Pinwheel=%s, Spirals=%s, Spirograph=%s, Strobe=%s, Twinkle=%s, SingleStrand=%s, Garlands=%s, Ripple=%s, Shockwave=%s, Fan=%s, Marquee=%s)",
                      [device name],
                      onPipeline ? "yes" : "no",
                      colorWashPipeline ? "yes" : "no",
                      barsPipeline ? "yes" : "no",
                      butterflyPipeline ? "yes" : "no",
                      plasmaPipeline ? "yes" : "no",
                      shimmerPipeline ? "yes" : "no",
                      wavePipeline ? "yes" : "no",
                      curtainPipeline ? "yes" : "no",
                      pinwheelPipeline ? "yes" : "no",
                      spiralsPipeline ? "yes" : "no",
                      spirographPipeline ? "yes" : "no",
                      strobePipeline ? "yes" : "no",
                      twinklePipeline ? "yes" : "no",
                      singleStrandPipeline ? "yes" : "no",
                      garlandsPipeline ? "yes" : "no",
                      ripplePipeline ? "yes" : "no",
                      shockwavePipeline ? "yes" : "no",
                      fanPipeline ? "yes" : "no",
                      marqueePipeline ? "yes" : "no");
            }
            return available;
        }
    }

    void cleanup() {
        @autoreleasepool {
            onPipeline = nil;
            colorWashPipeline = nil;
            barsPipeline = nil;
            butterflyPipeline = nil;
            plasmaPipeline = nil;
            shimmerPipeline = nil;
            wavePipeline = nil;
            curtainPipeline = nil;
            pinwheelPipeline = nil;
            spiralsPipeline = nil;
            spirographPipeline = nil;
            strobePipeline = nil;
            twinklePipeline = nil;
            singleStrandPipeline = nil;
            garlandsPipeline = nil;
            ripplePipeline = nil;
            shockwavePipeline = nil;
            fanPipeline = nil;
            marqueePipeline = nil;
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

bool MetalEffectCompute::renderBars(xlColor* outputPixels, int width, int height,
                                     const GPUBarsParams& params,
                                     const std::vector<float>& palette)
{
    if (!_impl || !_impl->barsPipeline) return false;
    return _impl->dispatch(_impl->barsPipeline,
                           &params, sizeof(GPUBarsParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

bool MetalEffectCompute::renderButterfly(xlColor* outputPixels, int width, int height,
                                          const GPUButterflyParams& params,
                                          const std::vector<float>& palette)
{
    if (!_impl || !_impl->butterflyPipeline) return false;
    return _impl->dispatch(_impl->butterflyPipeline,
                           &params, sizeof(GPUButterflyParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

bool MetalEffectCompute::renderPlasma(xlColor* outputPixels, int width, int height,
                                       const GPUPlasmaParams& params,
                                       const std::vector<float>& palette)
{
    if (!_impl || !_impl->plasmaPipeline) return false;
    return _impl->dispatch(_impl->plasmaPipeline,
                           &params, sizeof(GPUPlasmaParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

bool MetalEffectCompute::renderShimmer(xlColor* outputPixels, int width, int height,
                                        const GPUShimmerParams& params,
                                        const std::vector<float>& palette)
{
    if (!_impl || !_impl->shimmerPipeline) return false;
    return _impl->dispatch(_impl->shimmerPipeline,
                           &params, sizeof(GPUShimmerParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

bool MetalEffectCompute::renderWave(xlColor* outputPixels, int width, int height,
                                     const GPUWaveParams& params,
                                     const std::vector<float>& palette)
{
    if (!_impl || !_impl->wavePipeline) return false;

    // Wave dispatches one thread per column (width), not per pixel.
    // We need custom dispatch since the output buffer is width*height but
    // the thread count is just width (one thread per column).

    if (!_impl->available || !_impl->wavePipeline) return false;

    @autoreleasepool {
        uint32_t totalPixels = static_cast<uint32_t>(width * height);
        size_t outputSize = static_cast<size_t>(totalPixels) * 4;

        // Zero-initialize output buffer (wave only writes wave pixels, rest stays black)
        std::memset(outputPixels, 0, outputSize);

        id<MTLBuffer> outputBuf = [_impl->device newBufferWithLength:outputSize
                                                             options:MTLResourceStorageModeShared];
        // Zero the Metal output buffer too
        std::memset(outputBuf.contents, 0, outputSize);

        id<MTLBuffer> paramsBuf = [_impl->device newBufferWithBytes:&params
                                                             length:sizeof(GPUWaveParams)
                                                            options:MTLResourceStorageModeShared];
        id<MTLBuffer> paletteBuf = [_impl->device newBufferWithBytes:palette.data()
                                                              length:palette.size() * sizeof(float)
                                                             options:MTLResourceStorageModeShared];

        if (!outputBuf || !paramsBuf || !paletteBuf) return false;

        id<MTLCommandBuffer> cmdBuf = [_impl->commandQueue commandBuffer];
        if (!cmdBuf) return false;

        id<MTLComputeCommandEncoder> encoder = [cmdBuf computeCommandEncoder];
        if (!encoder) return false;

        [encoder setComputePipelineState:_impl->wavePipeline];
        [encoder setBuffer:outputBuf   offset:0 atIndex:0];
        [encoder setBuffer:paramsBuf   offset:0 atIndex:1];
        [encoder setBuffer:paletteBuf  offset:0 atIndex:2];

        // Dispatch one thread per column (width threads)
        NSUInteger threadCount = static_cast<NSUInteger>(width);
        NSUInteger threadgroupSize = _impl->wavePipeline.maxTotalThreadsPerThreadgroup;
        if (threadgroupSize > 256) threadgroupSize = 256;
        if (threadgroupSize > threadCount) threadgroupSize = threadCount;

        [encoder dispatchThreads:MTLSizeMake(threadCount, 1, 1)
           threadsPerThreadgroup:MTLSizeMake(threadgroupSize, 1, 1)];
        [encoder endEncoding];

        [cmdBuf commit];
        [cmdBuf waitUntilCompleted];

        if (cmdBuf.status == MTLCommandBufferStatusError) {
            NSLog(@"MetalEffectCompute: Wave command buffer error: %@", cmdBuf.error);
            return false;
        }

        std::memcpy(outputPixels, outputBuf.contents, outputSize);
        return true;
    }
}

bool MetalEffectCompute::renderCurtain(xlColor* outputPixels, int width, int height,
                                        const GPUCurtainParams& params,
                                        const std::vector<float>& palette,
                                        const std::vector<int32_t>& swagArray)
{
    if (!_impl || !_impl->curtainPipeline) return false;

    // Curtain needs a 4th buffer for the swag array — use custom dispatch
    @autoreleasepool {
        uint32_t totalPixels = params.totalPixels;
        size_t outputSize = static_cast<size_t>(totalPixels) * 4;

        id<MTLBuffer> outputBuf = [_impl->device newBufferWithLength:outputSize
                                                             options:MTLResourceStorageModeShared];
        id<MTLBuffer> paramsBuf = [_impl->device newBufferWithBytes:&params
                                                             length:sizeof(GPUCurtainParams)
                                                            options:MTLResourceStorageModeShared];
        id<MTLBuffer> paletteBuf = [_impl->device newBufferWithBytes:palette.data()
                                                              length:palette.size() * sizeof(float)
                                                             options:MTLResourceStorageModeShared];

        // Swag array buffer — pass at least 1 element even if empty (Metal needs valid buffer)
        int32_t dummySwag = 0;
        const void* swagData = swagArray.empty() ? &dummySwag : swagArray.data();
        size_t swagSize = swagArray.empty() ? sizeof(int32_t) : swagArray.size() * sizeof(int32_t);
        id<MTLBuffer> swagBuf = [_impl->device newBufferWithBytes:swagData
                                                           length:swagSize
                                                          options:MTLResourceStorageModeShared];

        if (!outputBuf || !paramsBuf || !paletteBuf || !swagBuf) return false;

        id<MTLCommandBuffer> cmdBuf = [_impl->commandQueue commandBuffer];
        if (!cmdBuf) return false;

        id<MTLComputeCommandEncoder> encoder = [cmdBuf computeCommandEncoder];
        if (!encoder) return false;

        [encoder setComputePipelineState:_impl->curtainPipeline];
        [encoder setBuffer:outputBuf   offset:0 atIndex:0];
        [encoder setBuffer:paramsBuf   offset:0 atIndex:1];
        [encoder setBuffer:paletteBuf  offset:0 atIndex:2];
        [encoder setBuffer:swagBuf     offset:0 atIndex:3];

        NSUInteger threadCount = static_cast<NSUInteger>(totalPixels);
        NSUInteger threadgroupSize = _impl->curtainPipeline.maxTotalThreadsPerThreadgroup;
        if (threadgroupSize > 256) threadgroupSize = 256;
        if (threadgroupSize > threadCount) threadgroupSize = threadCount;

        [encoder dispatchThreads:MTLSizeMake(threadCount, 1, 1)
           threadsPerThreadgroup:MTLSizeMake(threadgroupSize, 1, 1)];
        [encoder endEncoding];

        [cmdBuf commit];
        [cmdBuf waitUntilCompleted];

        if (cmdBuf.status == MTLCommandBufferStatusError) {
            NSLog(@"MetalEffectCompute: Curtain command buffer error: %@", cmdBuf.error);
            return false;
        }

        std::memcpy(outputPixels, outputBuf.contents, outputSize);
        return true;
    }
}

bool MetalEffectCompute::renderPinwheel(xlColor* outputPixels, int width, int height,
                                         const GPUPinwheelParams& params,
                                         const std::vector<float>& palette)
{
    if (!_impl || !_impl->pinwheelPipeline) return false;
    return _impl->dispatch(_impl->pinwheelPipeline,
                           &params, sizeof(GPUPinwheelParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

bool MetalEffectCompute::renderSpirals(xlColor* outputPixels, int width, int height,
                                        const GPUSpiralsParams& params,
                                        const std::vector<float>& palette)
{
    if (!_impl || !_impl->spiralsPipeline) return false;
    return _impl->dispatch(_impl->spiralsPipeline,
                           &params, sizeof(GPUSpiralsParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

bool MetalEffectCompute::renderSpirograph(xlColor* outputPixels, int width, int height,
                                           const GPUSpirographParams& params,
                                           const std::vector<float>& palette)
{
    if (!_impl || !_impl->spirographPipeline) return false;

    // Clear output to black — the kernel only writes curve pixels
    std::memset(outputPixels, 0, static_cast<size_t>(width) * height * sizeof(xlColor));

    uint32_t totalThreads = params.numCurveSamples * params.numWidthSamples;
    if (totalThreads == 0) return true;

    // We need the output buffer sized to width*height, but dispatch totalThreads.
    // Use a custom dispatch that separates output size from thread count.
    @autoreleasepool {
        uint32_t outputPixelCount = static_cast<uint32_t>(width * height);
        size_t outputSize = static_cast<size_t>(outputPixelCount) * 4;

        id<MTLBuffer> outputBuf = [_impl->device newBufferWithLength:outputSize
                                                             options:MTLResourceStorageModeShared];
        // Clear the GPU buffer to zero as well
        std::memset(outputBuf.contents, 0, outputSize);

        id<MTLBuffer> paramsBuf = [_impl->device newBufferWithBytes:&params
                                                             length:sizeof(GPUSpirographParams)
                                                            options:MTLResourceStorageModeShared];
        id<MTLBuffer> paletteBuf = [_impl->device newBufferWithBytes:palette.data()
                                                              length:palette.size() * sizeof(float)
                                                             options:MTLResourceStorageModeShared];

        if (!outputBuf || !paramsBuf || !paletteBuf) return false;

        id<MTLCommandBuffer> cmdBuf = [_impl->commandQueue commandBuffer];
        if (!cmdBuf) return false;

        id<MTLComputeCommandEncoder> encoder = [cmdBuf computeCommandEncoder];
        if (!encoder) return false;

        [encoder setComputePipelineState:_impl->spirographPipeline];
        [encoder setBuffer:outputBuf   offset:0 atIndex:0];
        [encoder setBuffer:paramsBuf   offset:0 atIndex:1];
        [encoder setBuffer:paletteBuf  offset:0 atIndex:2];

        NSUInteger threadCount = static_cast<NSUInteger>(totalThreads);
        NSUInteger threadgroupSize = _impl->spirographPipeline.maxTotalThreadsPerThreadgroup;
        if (threadgroupSize > 256) threadgroupSize = 256;
        if (threadgroupSize > threadCount) threadgroupSize = threadCount;

        [encoder dispatchThreads:MTLSizeMake(threadCount, 1, 1)
           threadsPerThreadgroup:MTLSizeMake(threadgroupSize, 1, 1)];
        [encoder endEncoding];

        [cmdBuf commit];
        [cmdBuf waitUntilCompleted];

        if (cmdBuf.status == MTLCommandBufferStatusError) {
            NSLog(@"MetalEffectCompute: Spirograph command buffer error: %@", cmdBuf.error);
            return false;
        }

        std::memcpy(outputPixels, outputBuf.contents, outputSize);
        return true;
    }
}

bool MetalEffectCompute::renderStrobe(xlColor* outputPixels, int width, int height,
                                       const GPUStrobeParams& params,
                                       const std::vector<GPUStrobeDrawCmd>& drawCmds)
{
    if (!_impl || !_impl->strobePipeline) return false;

    uint32_t totalPixels = static_cast<uint32_t>(width * height);

    if (drawCmds.empty()) {
        // No active strobes — clear output to black
        std::memset(outputPixels, 0, static_cast<size_t>(totalPixels) * 4);
        return true;
    }

    @autoreleasepool {
        auto* impl = _impl;
        size_t outputSize = static_cast<size_t>(totalPixels) * 4;

        // Create output buffer pre-cleared to zero
        id<MTLBuffer> outputBuf = [impl->device newBufferWithLength:outputSize
                                                            options:MTLResourceStorageModeShared];
        // Zero the output buffer (strobe draws on black background)
        std::memset(outputBuf.contents, 0, outputSize);

        id<MTLBuffer> paramsBuf = [impl->device newBufferWithBytes:&params
                                                            length:sizeof(GPUStrobeParams)
                                                           options:MTLResourceStorageModeShared];
        id<MTLBuffer> cmdsBuf = [impl->device newBufferWithBytes:drawCmds.data()
                                                          length:drawCmds.size() * sizeof(GPUStrobeDrawCmd)
                                                         options:MTLResourceStorageModeShared];

        if (!outputBuf || !paramsBuf || !cmdsBuf) return false;

        id<MTLCommandBuffer> cmdBuf = [impl->commandQueue commandBuffer];
        if (!cmdBuf) return false;

        id<MTLComputeCommandEncoder> encoder = [cmdBuf computeCommandEncoder];
        if (!encoder) return false;

        [encoder setComputePipelineState:impl->strobePipeline];
        [encoder setBuffer:outputBuf  offset:0 atIndex:0];
        [encoder setBuffer:paramsBuf  offset:0 atIndex:1];
        [encoder setBuffer:cmdsBuf    offset:0 atIndex:2];

        // Thread count = number of draw commands (NOT totalPixels)
        NSUInteger threadCount = static_cast<NSUInteger>(drawCmds.size());
        NSUInteger threadgroupSize = impl->strobePipeline.maxTotalThreadsPerThreadgroup;
        if (threadgroupSize > 256) threadgroupSize = 256;
        if (threadgroupSize > threadCount) threadgroupSize = threadCount;

        [encoder dispatchThreads:MTLSizeMake(threadCount, 1, 1)
           threadsPerThreadgroup:MTLSizeMake(threadgroupSize, 1, 1)];
        [encoder endEncoding];

        [cmdBuf commit];
        [cmdBuf waitUntilCompleted];

        if (cmdBuf.status == MTLCommandBufferStatusError) {
            NSLog(@"MetalEffectCompute: Strobe command buffer error: %@", cmdBuf.error);
            return false;
        }

        std::memcpy(outputPixels, outputBuf.contents, outputSize);
        return true;
    }
}

bool MetalEffectCompute::renderTwinkle(xlColor* outputPixels, int width, int height,
                                        const GPUTwinkleParams& params,
                                        const std::vector<float>& palette)
{
    if (!_impl || !_impl->twinklePipeline) return false;
    return _impl->dispatch(_impl->twinklePipeline,
                           &params, sizeof(GPUTwinkleParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

bool MetalEffectCompute::renderSingleStrand(xlColor* outputPixels, int width, int height,
                                             const GPUSingleStrandParams& params,
                                             const std::vector<float>& palette)
{
    if (!_impl || !_impl->singleStrandPipeline) return false;
    return _impl->dispatch(_impl->singleStrandPipeline,
                           &params, sizeof(GPUSingleStrandParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

bool MetalEffectCompute::renderGarlands(xlColor* outputPixels, int width, int height,
                                         const GPUGarlandsParams& params,
                                         const std::vector<float>& palette)
{
    if (!_impl || !_impl->garlandsPipeline) return false;

    // Clear output buffer first — Garlands only writes to specific pixels,
    // leaving the rest black (unlike On/ColorWash which write every pixel).
    std::memset(outputPixels, 0, static_cast<size_t>(width) * height * 4);

    // Total work items = buffMax * garlandWid (one thread per ring x pair)
    uint32_t totalWork = params.buffMax * params.garlandWid;

    return _impl->dispatch(_impl->garlandsPipeline,
                           &params, sizeof(GPUGarlandsParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, totalWork);
}

bool MetalEffectCompute::renderRipple(xlColor* outputPixels, int width, int height,
                                       const GPURippleParams& params)
{
    if (!_impl || !_impl->ripplePipeline) return false;

    // Ripple does not use palette buffer in the shader — color is baked into params.
    // We still need a dummy palette buffer for the dispatch signature.
    float dummyPalette[4] = {0.0f, 0.0f, 0.0f, 1.0f};

    return _impl->dispatch(_impl->ripplePipeline,
                           &params, sizeof(GPURippleParams),
                           dummyPalette, sizeof(dummyPalette),
                           outputPixels, params.totalPixels);
}

bool MetalEffectCompute::renderShockwave(xlColor* outputPixels, int width, int height,
                                          const GPUShockwaveParams& params,
                                          const std::vector<float>& palette)
{
    if (!_impl || !_impl->shockwavePipeline) return false;
    return _impl->dispatch(_impl->shockwavePipeline,
                           &params, sizeof(GPUShockwaveParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

bool MetalEffectCompute::renderFan(xlColor* outputPixels, int width, int height,
                                    const GPUFanParams& params,
                                    const std::vector<float>& palette)
{
    if (!_impl || !_impl->fanPipeline) return false;
    return _impl->dispatch(_impl->fanPipeline,
                           &params, sizeof(GPUFanParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

bool MetalEffectCompute::renderMarquee(xlColor* outputPixels, int width, int height,
                                        const GPUMarqueeParams& params,
                                        const std::vector<float>& palette)
{
    if (!_impl || !_impl->marqueePipeline) return false;
    return _impl->dispatch(_impl->marqueePipeline,
                           &params, sizeof(GPUMarqueeParams),
                           palette.data(), palette.size() * sizeof(float),
                           outputPixels, params.totalPixels);
}

} // namespace xlEngine
