/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// MetalKernels_Light.metal
//
// Metal compute kernels for light/flash-based effects.
// These effects produce flashing, pulsing, shimmering, or radiating light
// patterns. Each kernel processes one pixel (or one draw command) per thread.
//
// Effects in this file:
//   - Plasma       : Sinusoidal plasma color blending
//   - Shimmer      : Per-pixel random palette color flicker
//   - Strobe       : Point-based flash patterns (1-5 pixels per strobe)
//   - Twinkle      : Deterministic per-pixel fade-in/fade-out sparkle
//   - Ripple       : Expanding/imploding ring from center point
//   - Shockwave    : Expanding ring with palette color blend and edge fade

#include "MetalEffectTypes.h"

// =========================================================================
// Plasma Effect Kernel
// =========================================================================

kernel void effectPlasma(
    device uchar4* output [[buffer(0)]],
    constant PlasmaParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    uint px = gid % params.width;
    uint py = gid / params.width;

    float rx = (params.width > 1) ? (float(px) / float(params.width - 1)) : 0.0;
    float ry = (params.height > 1) ? (float(py) / float(params.height - 1)) : 0.0;

    float rx2 = rx * rx;
    float cx = rx + 0.5 * params.sinTime5;
    float cx2 = cx * cx;
    float sin_rx_time = sin(rx + params.time);

    // 1st equation
    float v = sin(rx * 10.0 + params.time);

    // 2nd equation
    v += sin(10.0 * (rx * params.sinTime2 + ry * params.cosTime3) + params.time);

    // 3rd equation
    float cy = ry + 0.5 * params.cosTime3;
    v += sin(sqrt(float(params.style) * 50.0 * (cx2 + cy * cy) + params.time));

    // 4th-6th equations
    v += sin_rx_time;
    v += sin((ry + params.time) / 2.0);
    v += sin((rx + ry + params.time) / 2.0);

    // 7th equation
    v += sin(sqrt(rx2 + ry * ry) + params.time);
    v = v / 2.0;

    constexpr float PI = 3.14159265358979323846;
    constexpr float pi3 = PI / 3.0;
    float vldpi = v * float(params.lineDensity) * PI;

    uchar4 pixel;

    switch (params.colorScheme) {
        case 0:
        default: {
            // Normal: use palette multi-color blend
            float blend = (sin(vldpi + 2.0 * pi3) + 1.0) * 0.5;
            float4 col = get_multi_color_blend(blend, palette, params.paletteSize,
                                                params.circularPalette != 0);
            pixel = uchar4(uint8_t(col.r * 255.0),
                           uint8_t(col.g * 255.0),
                           uint8_t(col.b * 255.0),
                           255);
            break;
        }
        case 1: {
            // Preset 1: red/green channels from sin/cos
            uint8_t r = uint8_t((sin(vldpi) + 1.0) * 255.0 / 2.0);
            uint8_t g = uint8_t((cos(vldpi) + 1.0) * 255.0 / 2.0);
            pixel = uchar4(r, g, 0, 255);
            break;
        }
        case 2: {
            // Preset 2: blue/green from sin/cos, red=1
            uint8_t b = uint8_t((sin(vldpi) + 1.0) * 255.0 / 2.0);
            uint8_t g = uint8_t((cos(vldpi) + 1.0) * 255.0 / 2.0);
            pixel = uchar4(1, g, b, 255);
            break;
        }
        case 3: {
            // Preset 3: RGB from sin with phase offsets
            uint8_t r = uint8_t((sin(vldpi) + 1.0) * 255.0 / 2.0);
            uint8_t g = uint8_t((sin(vldpi + 2.0 * pi3) + 1.0) * 255.0 / 2.0);
            uint8_t b = uint8_t((sin(vldpi + 4.0 * pi3) + 1.0) * 255.0 / 2.0);
            pixel = uchar4(r, g, b, 255);
            break;
        }
        case 4: {
            // Preset 4: grayscale from sin
            uint8_t val = uint8_t((sin(vldpi) + 1.0) * 255.0 / 2.0);
            pixel = uchar4(val, val, val, 255);
            break;
        }
    }

    output[gid] = pixel;
}

// =========================================================================
// Shimmer Effect Kernel
// =========================================================================

// Simple deterministic hash for per-pixel pseudo-random color selection.
static uint shimmer_hash(uint x) {
    x = ((x >> 16u) ^ x) * 0x45d9f3bu;
    x = ((x >> 16u) ^ x) * 0x45d9f3bu;
    x = (x >> 16u) ^ x;
    return x;
}

kernel void effectShimmer(
    device uchar4* output [[buffer(0)]],
    constant ShimmerParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    float4 color;
    if (params.useAllColors) {
        // Deterministic per-pixel random color from palette
        uint h = shimmer_hash(gid + params.frameSeed * 2654435761u);
        uint idx = h % params.paletteSize;
        color = palette[idx];
    } else {
        // Uniform color for all pixels
        color = palette[params.colorIdx];
    }

    output[gid] = uchar4(uint8_t(color.r * 255.0),
                          uint8_t(color.g * 255.0),
                          uint8_t(color.b * 255.0),
                          255);
}

// =========================================================================
// Strobe Effect Kernel
// =========================================================================
//
// Each thread processes ONE strobe draw command, writing 1-5 pixels.
// The buffer must be pre-cleared to black before dispatch.
// Thread count = numDrawCommands (NOT totalPixels).

static void strobe_set_pixel(device uchar4* output, int x, int y,
                              uint width, uint height, uchar4 color) {
    if (x < 0 || x >= int(width) || y < 0 || y >= int(height)) return;
    output[uint(y) * width + uint(x)] = color;
}

kernel void effectStrobe(
    device uchar4* output [[buffer(0)]],
    constant StrobeParams& params [[buffer(1)]],
    device const StrobeDrawCmd* cmds [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.numDrawCommands) return;

    StrobeDrawCmd cmd = cmds[gid];
    int x = cmd.x;
    int y = cmd.y;

    uchar4 centerColor = uchar4(cmd.centerR, cmd.centerG, cmd.centerB, cmd.centerA);
    uchar4 surroundColor = uchar4(cmd.surroundR, cmd.surroundG, cmd.surroundB, cmd.surroundA);

    if (cmd.drawCenter) {
        strobe_set_pixel(output, x, y, params.width, params.height, centerColor);
    }

    if (params.strobeType == 1) {
        return;
    }

    if (params.strobeType == 2) {
        if (cmd.orientation == 0) {
            strobe_set_pixel(output, x, y - 1, params.width, params.height, surroundColor);
            strobe_set_pixel(output, x, y + 1, params.width, params.height, surroundColor);
        } else {
            strobe_set_pixel(output, x - 1, y, params.width, params.height, surroundColor);
            strobe_set_pixel(output, x + 1, y, params.width, params.height, surroundColor);
        }
        return;
    }

    if (params.strobeType == 3) {
        strobe_set_pixel(output, x, y - 1, params.width, params.height, surroundColor);
        strobe_set_pixel(output, x, y + 1, params.width, params.height, surroundColor);
        strobe_set_pixel(output, x - 1, y, params.width, params.height, surroundColor);
        strobe_set_pixel(output, x + 1, y, params.width, params.height, surroundColor);
        return;
    }

    if (params.strobeType == 4) {
        if (cmd.orientation == 0) {
            strobe_set_pixel(output, x, y - 1, params.width, params.height, surroundColor);
            strobe_set_pixel(output, x, y + 1, params.width, params.height, surroundColor);
            strobe_set_pixel(output, x - 1, y, params.width, params.height, surroundColor);
            strobe_set_pixel(output, x + 1, y, params.width, params.height, surroundColor);
        } else {
            strobe_set_pixel(output, x + 1, y - 1, params.width, params.height, surroundColor);
            strobe_set_pixel(output, x + 1, y + 1, params.width, params.height, surroundColor);
            strobe_set_pixel(output, x - 1, y - 1, params.width, params.height, surroundColor);
            strobe_set_pixel(output, x - 1, y + 1, params.width, params.height, surroundColor);
        }
        return;
    }
}

// =========================================================================
// Twinkle Effect Kernel
// =========================================================================

// Deterministic hash for per-pixel twinkle state.
static uint twinkle_hash(uint a, uint b) {
    uint h = a * 2654435761u;
    h ^= b * 2246822519u;
    h ^= h >> 16;
    h *= 0x45d9f3bu;
    h ^= h >> 16;
    return h;
}

kernel void effectTwinkle(
    device uchar4* output [[buffer(0)]],
    constant TwinkleParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    uint pixelHash = twinkle_hash(gid, params.seed);
    uint activePct = pixelHash % 100u;

    if (activePct >= params.count) {
        if (params.allowAlpha) {
            output[gid] = uchar4(0, 0, 0, 0);
        } else {
            output[gid] = uchar4(0, 0, 0, 255);
        }
        return;
    }

    uint phaseOffset = twinkle_hash(gid, params.seed + 0x9E3779B9u) % params.steps;
    uint phase = (params.frameNumber + phaseOffset) % params.steps;

    uint halfSteps = params.steps / 2;
    if (halfSteps < 1) halfSteps = 1;

    float v;
    if (phase <= halfSteps) {
        v = float(phase) / float(halfSteps);
    } else {
        v = float(params.steps - phase) / float(halfSteps);
    }
    if (v < 0.0) v = 0.0;
    if (v > 1.0) v = 1.0;

    if (params.strobe) {
        v = (phase == halfSteps) ? 1.0 : 0.0;
    }

    uint colorIndex = twinkle_hash(gid, params.seed + 0x517CC1B7u) % params.paletteSize;
    float4 baseColor = palette[colorIndex];

    if (params.allowAlpha) {
        output[gid] = uchar4(uint8_t(baseColor.r * 255.0),
                              uint8_t(baseColor.g * 255.0),
                              uint8_t(baseColor.b * 255.0),
                              uint8_t(v * 255.0));
    } else {
        if (v >= 0.999) {
            output[gid] = uchar4(uint8_t(baseColor.r * 255.0),
                                  uint8_t(baseColor.g * 255.0),
                                  uint8_t(baseColor.b * 255.0),
                                  255);
        } else if (v <= 0.001) {
            output[gid] = uchar4(0, 0, 0, 255);
        } else {
            output[gid] = apply_brightness(baseColor.rgb, v);
        }
    }
}

// =========================================================================
// Ripple Effect Kernel
// =========================================================================

kernel void effectRipple(
    device uchar4* output [[buffer(0)]],
    constant RippleParams& params [[buffer(1)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    int x = int(gid % params.width);
    int y = int(gid / params.width);

    float dx = float(x) - float(params.xc);
    float dy = float(y) - float(params.yc);

    float dist;

    if (params.objectType == 0) {
        dist = sqrt(dx * dx + dy * dy);
    } else {
        float maxRadiusX = max(float(params.xc), float(params.width) - float(params.xc));
        float maxRadiusY = max(float(params.yc), float(params.height) - float(params.yc));

        float scaleX = (maxRadiusX > 0.0) ? maxRadiusX : 1.0;
        float scaleY = (maxRadiusY > 0.0) ? maxRadiusY : 1.0;

        float normDx = abs(dx) / scaleX;
        float normDy = abs(dy) / scaleY;
        float chebyshev = max(normDx, normDy);
        dist = chebyshev * params.maxRadius;
    }

    float ringStart, ringEnd;
    float thk = float(params.thickness);

    if (params.movement == 0) {
        ringStart = params.radius;
        ringEnd = params.radius + thk;
    } else {
        ringStart = params.radius - thk;
        ringEnd = params.radius;
    }

    if (dist < ringStart - 0.5 || dist > ringEnd + 0.5 || ringEnd < 0.0) {
        output[gid] = uchar4(0, 0, 0, 0);
        return;
    }

    float i;
    if (params.movement == 0) {
        i = dist - params.radius;
    } else {
        i = params.radius - dist;
    }

    i = clamp(i, 0.0f, thk);

    float alpha = 1.0;
    float valueMult = 1.0;

    if (params.is3D) {
        float fadeFactor;
        if (params.objectType == 0) {
            fadeFactor = i / thk;
        } else {
            fadeFactor = (i / 2.0) / thk;
        }
        fadeFactor = clamp(fadeFactor, 0.0f, 1.0f);

        if (params.allowAlpha) {
            alpha = 1.0 - fadeFactor;
        } else {
            valueMult = 1.0 - fadeFactor;
        }
    }

    float h = params.baseH;
    float s = params.baseS;
    float v = params.baseV * valueMult;

    float3 rgb = hsv_to_rgb(float3(h, s, v));

    uint8_t outR = uint8_t(clamp(rgb.r * 255.0, 0.0, 255.0));
    uint8_t outG = uint8_t(clamp(rgb.g * 255.0, 0.0, 255.0));
    uint8_t outB = uint8_t(clamp(rgb.b * 255.0, 0.0, 255.0));
    uint8_t outA = uint8_t(clamp(alpha * 255.0, 0.0, 255.0));

    output[gid] = uchar4(outR, outG, outB, outA);
}

// =========================================================================
// Shockwave Effect Kernel
// =========================================================================

// 2-color blend matching NativeRenderBuffer::Get2ColorBlend / ChannelBlend
static float4 blend_2_colors(float4 c1, float4 c2, float ratio) {
    return float4(c1.r + floor(ratio * (c2.r - c1.r) * 255.0 + 0.5) / 255.0,
                  c1.g + floor(ratio * (c2.g - c1.g) * 255.0 + 0.5) / 255.0,
                  c1.b + floor(ratio * (c2.b - c1.b) * 255.0 + 0.5) / 255.0,
                  1.0);
}

static float4 shockwave_palette_color(float effPosAdj,
                                       device const float4* palette,
                                       uint paletteSize)
{
    if (paletteSize <= 1) {
        return palette[0];
    }
    float blend_pct = 1.0 / float(paletteSize - 1);
    float color_pct1 = effPosAdj / blend_pct;
    int color_index = int(color_pct1);
    float color_blend = color_pct1 - float(color_index);

    int idx1 = min(color_index, int(paletteSize) - 1);
    int idx2 = min(color_index + 1, int(paletteSize) - 1);
    float blend_ratio = min(color_blend, 1.0f);

    return blend_2_colors(palette[idx1], palette[idx2], blend_ratio);
}

kernel void effectShockwave(
    device uchar4* output [[buffer(0)]],
    constant ShockwaveParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    uint x = gid % params.width;
    uint y = gid / params.width;

    float dx = float(x) - params.centerX;
    float dy = float(y) - params.centerY;
    float r = sqrt(dx * dx + dy * dy);

    if (r < params.radius1 || r > params.radius2) {
        output[gid] = uchar4(0, 0, 0, 0);
        return;
    }

    float4 color = shockwave_palette_color(params.effPosAdj, palette, params.paletteSize);

    if (params.blendEdges) {
        float color_pct = 1.0 - abs(r - params.radiusCenter) / params.halfWidth;
        color_pct = clamp(color_pct, 0.0f, 1.0f);

        if (params.allowAlpha) {
            output[gid] = uchar4(uint8_t(color.r * 255.0),
                                  uint8_t(color.g * 255.0),
                                  uint8_t(color.b * 255.0),
                                  uint8_t(255.0 * color_pct));
        } else {
            output[gid] = apply_brightness(color.rgb, color_pct);
        }
    } else {
        output[gid] = uchar4(uint8_t(color.r * 255.0),
                              uint8_t(color.g * 255.0),
                              uint8_t(color.b * 255.0),
                              255);
    }
}
