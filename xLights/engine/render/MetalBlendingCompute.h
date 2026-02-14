/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

// MetalBlendingCompute: GPU-accelerated layer blending using Metal compute
// shaders. This class encapsulates all Metal resource management and provides
// a simple C++ interface for NativePixelBuffer::calcOutput() to dispatch
// blending work to the GPU.
//
// Usage:
//   1. Call isAvailable() to check if Metal compute is usable
//   2. Prepare layer data (pixel buffers, settings, masks)
//   3. Call blendLayers() to dispatch the compute shader
//   4. Results are written directly into the output pixel array
//
// Thread safety:
//   Each NativePixelBuffer instance should have its own MetalBlendingCompute
//   instance, or serialise access externally. The Metal command queue is
//   shared but thread-safe.

#include <cstdint>
#include <vector>
#include "../../Color.h"
#include "NativeColorBlending.h"

namespace xlEngine {

struct NativeLayerInfo;

// GPU-side per-layer settings. Must match the Metal shader struct exactly.
// Packed with explicit layout to avoid alignment surprises.
struct GPULayerSettings {
    int32_t mixType;
    float effectMixThreshold;
    int32_t effectMixVary;       // bool as int
    float fadeFactor;
    int32_t allowAlpha;          // bool as int
    float hueAdjust;
    float saturationAdjust;
    float valueAdjust;
    int32_t brightness;
    int32_t contrast;
    int32_t isChromaKey;         // bool as int
    int32_t chromaSensitivity;
    uint8_t chromaKeyColour[4];  // RGBA packed
    int32_t isValid;             // bool as int
    int32_t maskOffset;          // offset into mask buffer, -1 if none
    int32_t maskSize;            // mask byte count for this layer
    int32_t _padding0;
};

struct GPUBlendParams {
    int32_t bufferWi;
    int32_t bufferHt;
    int32_t numLayers;
    int32_t totalPixels;
};

// Opaque pointer to the Obj-C implementation.
// The actual Metal objects (device, pipeline, command queue) are held
// by the implementation class to avoid exposing Obj-C types in this header.
struct MetalBlendingComputeImpl;

class MetalBlendingCompute {
public:
    MetalBlendingCompute();
    ~MetalBlendingCompute();

    // Non-copyable, movable
    MetalBlendingCompute(const MetalBlendingCompute&) = delete;
    MetalBlendingCompute& operator=(const MetalBlendingCompute&) = delete;
    MetalBlendingCompute(MetalBlendingCompute&&) noexcept;
    MetalBlendingCompute& operator=(MetalBlendingCompute&&) noexcept;

    // Returns true if Metal compute is available and the pipeline was
    // created successfully. If false, fall back to CPU blending.
    bool isAvailable() const;

    // Perform GPU-accelerated layer blending.
    //
    // @param params         Global blend parameters (buffer dimensions, layer count)
    // @param layerSettings  Per-layer GPU settings array (numLayers entries)
    // @param layerPixelData Flattened layer pixel data: layer0[totalPixels] ++ layer1[totalPixels] ++ ...
    //                       Each pixel is 4 bytes (RGBA), same layout as xlColor.
    // @param layerPixelDataSize Total bytes in layerPixelData
    // @param maskData       Concatenated transition mask bytes for all layers
    // @param maskDataSize   Total bytes in maskData
    // @param outputPixels   Output buffer for blended pixels (totalPixels * 4 bytes)
    //
    // @return true if GPU blending succeeded, false if fallback to CPU is needed.
    bool blendLayers(const GPUBlendParams& params,
                     const std::vector<GPULayerSettings>& layerSettings,
                     const uint8_t* layerPixelData,
                     size_t layerPixelDataSize,
                     const uint8_t* maskData,
                     size_t maskDataSize,
                     xlColor* outputPixels);

private:
    MetalBlendingComputeImpl* _impl;
};

} // namespace xlEngine
