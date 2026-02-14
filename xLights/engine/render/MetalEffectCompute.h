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

// MetalEffectCompute: GPU-accelerated effect rendering via Metal compute shaders.
//
// This class provides a GPU rendering path for effects that are
// embarrassingly parallel (per-pixel computation with no frame state).
// The CPU effect code remains the fallback for small buffers, unsupported
// effects, or systems without Metal.
//
// Thread safety: Thread-safe for concurrent calls from different threads.
// Each call creates its own command buffer (lightweight). Pipeline state
// objects are immutable and shared safely.
//
// Usage:
//   auto& gpu = MetalEffectCompute::shared();
//   if (gpu.isAvailable() && totalPixels >= gpu.minPixelThreshold()) {
//       gpu.renderOn(outputPixels, width, height, params, palette);
//   }

#include <cstdint>
#include <cstddef>
#include <vector>
#include "../../Color.h"

namespace xlEngine {

// Parameter structs — must match NativeEffectShaders.metal layout exactly.
// Packed as plain uint/float for Metal buffer compatibility.

struct GPUOnParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    float startIntensity;   // 0.0-1.0
    float endIntensity;     // 0.0-1.0
    float effectPosition;   // 0.0-1.0
    uint32_t shimmer;       // 0 or 1
    uint32_t isShimmerOdd;  // 0 or 1
};

struct GPUColorWashParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    float effectPosition;   // 0.0-1.0 with cycles applied
    uint32_t horizFade;     // 0 or 1
    uint32_t vertFade;      // 0 or 1
    uint32_t reverseFades;  // 0 or 1
    uint32_t shimmerBlack;  // 0 or 1
    uint32_t paletteSize;
    uint32_t circularPalette; // 0 or 1
};

struct MetalEffectComputeImpl;

class MetalEffectCompute {
public:
    // Access the shared singleton instance.
    // Lazily initializes Metal on first call.
    static MetalEffectCompute& shared();

    ~MetalEffectCompute();

    MetalEffectCompute(const MetalEffectCompute&) = delete;
    MetalEffectCompute& operator=(const MetalEffectCompute&) = delete;

    // Returns true if Metal compute is available on this system.
    bool isAvailable() const;

    // Minimum pixel count for GPU rendering to be worthwhile.
    // Below this threshold, CPU rendering is faster due to dispatch overhead.
    static constexpr int minPixelThreshold() { return 5000; }

    // Render the On effect directly into the output pixel buffer.
    // outputPixels must be at least width * height * 4 bytes (RGBA).
    // palette is an array of {r,g,b,a} float4 colors (0.0-1.0 range).
    // Returns true if GPU rendering succeeded.
    bool renderOn(xlColor* outputPixels, int width, int height,
                  const GPUOnParams& params,
                  const std::vector<float>& palette);

    // Render the ColorWash effect directly into the output pixel buffer.
    bool renderColorWash(xlColor* outputPixels, int width, int height,
                         const GPUColorWashParams& params,
                         const std::vector<float>& palette);

private:
    MetalEffectCompute();
    MetalEffectComputeImpl* _impl;
};

} // namespace xlEngine
