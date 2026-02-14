/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// NativeEffectShaders.metal
//
// Metal compute shaders for GPU-accelerated effect rendering.
// Each effect gets its own kernel function that processes one pixel per thread.
// The CPU side (MetalEffectCompute) sets up parameters and dispatches.
//
// Effects implemented here are chosen for:
//   1. High pixel count (large buffers benefit from GPU parallelism)
//   2. Per-pixel computation (not just uniform fills)
//   3. No persistent frame state (stateless per-frame)

#include <metal_stdlib>
using namespace metal;

// =========================================================================
// Shared data types — must match MetalEffectCompute.h
// =========================================================================

struct OnParams {
    uint width;
    uint height;
    uint totalPixels;
    float startIntensity;   // 0.0-1.0
    float endIntensity;     // 0.0-1.0
    float effectPosition;   // 0.0-1.0 (position within effect duration)
    uint shimmer;           // 0 or 1
    uint isShimmerOdd;      // 0 or 1 (true on odd frames)
};

struct ColorWashParams {
    uint width;
    uint height;
    uint totalPixels;
    float effectPosition;   // 0.0-1.0 with cycles applied
    uint horizFade;         // 0 or 1
    uint vertFade;          // 0 or 1
    uint reverseFades;      // 0 or 1
    uint shimmerBlack;      // 0 or 1 (true on shimmer odd frames)
    uint paletteSize;
    uint circularPalette;   // 0 or 1
};

// =========================================================================
// HSV ↔ RGB conversion — matches xLights Color.cpp exactly
// =========================================================================

// Optimized RGB→HSV from http://lolengine.net/blog/2013/01/13/fast-rgb-to-hsv
static float3 rgb_to_hsv(float3 rgb) {
    float r = rgb.r;
    float g = rgb.g;
    float b = rgb.b;

    float K = 0.0;
    if (g < b) {
        float tmp = g; g = b; b = tmp;
        K = -1.0;
    }
    float min_gb = b;
    if (r < g) {
        float tmp = r; r = g; g = tmp;
        K = -2.0 / 6.0 - K;
        min_gb = min(g, b);
    }
    float chroma = r - min_gb;
    float hue = abs(K + (g - b) / (6.0 * chroma + 1e-20));
    float saturation = chroma / (r + 1e-20);
    float value = r;
    return float3(hue, saturation, value);
}

// HSV→RGB matching xLights fromHSV() in Color.cpp
static float3 hsv_to_rgb(float3 hsv) {
    float h = clamp(hsv.x, 0.0, 1.0);
    float s = clamp(hsv.y, 0.0, 1.0);
    float v = clamp(hsv.z, 0.0, 1.0);

    if (s == 0.0) {
        return float3(v, v, v);
    }

    float hue6 = h * 6.0;
    int i = int(floor(hue6));
    float f = hue6 - float(i);
    float p = v * (1.0 - s);

    float r, g, b;
    switch (i) {
        case 6:
        case 0:
            r = v;
            g = v * (1.0 - s * (1.0 - f));
            b = p;
            break;
        case 1:
            r = v * (1.0 - s * f);
            g = v;
            b = p;
            break;
        case 2:
            r = p;
            g = v;
            b = v * (1.0 - s * (1.0 - f));
            break;
        case 3:
            r = p;
            g = v * (1.0 - s * f);
            b = v;
            break;
        case 4:
            r = v * (1.0 - s * (1.0 - f));
            g = p;
            b = v;
            break;
        default: // case 5
            r = v;
            g = p;
            b = v * (1.0 - s * f);
            break;
    }
    return float3(r, g, b);
}

// Apply brightness multiplier via HSV value channel
static uchar4 apply_brightness(float3 rgb, float brightness) {
    float3 hsv = rgb_to_hsv(rgb);
    hsv.z *= brightness;
    float3 result = hsv_to_rgb(hsv);
    return uchar4(uint8_t(result.r * 255.0),
                  uint8_t(result.g * 255.0),
                  uint8_t(result.b * 255.0),
                  255);
}

// =========================================================================
// Palette blending — matches NativeRenderBuffer::GetMultiColorBlend()
// =========================================================================

// Blend between two colors by ratio (0.0 = c1, 1.0 = c2)
static float4 blend_colors(float4 c1, float4 c2, float ratio) {
    return float4(c1.r + (c2.r - c1.r) * ratio,
                  c1.g + (c2.g - c1.g) * ratio,
                  c1.b + (c2.b - c1.b) * ratio,
                  1.0);
}

static float4 get_multi_color_blend(float n, device const float4* palette,
                                     uint paletteSize, bool circular) {
    if (paletteSize <= 1) {
        return palette[0];
    }

    n = clamp(n, 0.0f, 0.99999f);
    float realidx = circular ? n * float(paletteSize) : n * float(paletteSize - 1);
    int coloridx1 = int(floor(realidx));
    int coloridx2 = (coloridx1 + 1) % int(paletteSize);
    float ratio = realidx - float(coloridx1);
    return blend_colors(palette[coloridx1], palette[coloridx2], ratio);
}

// =========================================================================
// On Effect Kernel
// =========================================================================

kernel void effectOn(
    device uchar4* output [[buffer(0)]],
    constant OnParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    // Shimmer: odd frames use palette[1], even frames use palette[0]
    float4 baseColor;
    if (params.shimmer && params.isShimmerOdd) {
        baseColor = palette[1];
    } else {
        baseColor = palette[0];
    }

    // Apply intensity ramp via HSV brightness
    float intensity = params.startIntensity +
        (params.endIntensity - params.startIntensity) * params.effectPosition;

    if (intensity >= 0.999) {
        // Full intensity — skip HSV conversion
        output[gid] = uchar4(uint8_t(baseColor.r * 255.0),
                              uint8_t(baseColor.g * 255.0),
                              uint8_t(baseColor.b * 255.0),
                              255);
    } else {
        output[gid] = apply_brightness(baseColor.rgb, intensity);
    }
}

// =========================================================================
// ColorWash Effect Kernel
// =========================================================================

kernel void effectColorWash(
    device uchar4* output [[buffer(0)]],
    constant ColorWashParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    // Shimmer odd frame: black
    if (params.shimmerBlack) {
        output[gid] = uchar4(0, 0, 0, 0);
        return;
    }

    // Get blended palette color at effect position
    float4 color = get_multi_color_blend(params.effectPosition, palette,
                                          params.paletteSize,
                                          params.circularPalette != 0);

    // Calculate fade multipliers based on pixel position
    uint x = gid % params.width;
    uint y = gid / params.width;

    float brightness = 1.0;

    if (params.horizFade) {
        float halfWi = float(params.width - 1) / 2.0;
        if (halfWi > 0.0) {
            float hMult = abs(halfWi - float(x)) / halfWi;
            if (!params.reverseFades) hMult = 1.0 - hMult;
            brightness *= hMult;
        }
    }

    if (params.vertFade) {
        float halfHt = float(params.height - 1) / 2.0;
        if (halfHt > 0.0) {
            float vMult = abs(halfHt - float(y)) / halfHt;
            if (!params.reverseFades) vMult = 1.0 - vMult;
            brightness *= vMult;
        }
    }

    if (brightness >= 0.999 && !params.horizFade && !params.vertFade) {
        // No fades — direct color output
        output[gid] = uchar4(uint8_t(color.r * 255.0),
                              uint8_t(color.g * 255.0),
                              uint8_t(color.b * 255.0),
                              255);
    } else {
        output[gid] = apply_brightness(color.rgb, brightness);
    }
}
