/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// MetalKernels_Motion.metal
//
// Metal compute kernels for motion and rotation-based effects.
// These effects share a common pattern of polar/angular coordinate
// transformations to produce spinning, sweeping, or oscillating visuals.
//
// Effects in this file:
//   - Wave        : Sine/triangle/square/decay wave with optional mirror
//   - Pinwheel    : Rotating arms with twist and 3D shading
//   - Spirals     : Rotating spiral strands with 3D depth
//   - Spirograph  : Parametric curve drawing (hypotrochoid)
//   - Fan         : Radial fan blades with element segmentation

#include "MetalEffectTypes.h"

// =========================================================================
// Wave Effect Kernel
// =========================================================================
//
// Each thread processes one column (x coordinate). The kernel computes
// the wave shape for that column and fills the appropriate y-range of pixels.
// Threads for x >= width are no-ops.
// We dispatch width threads (one per column), not totalPixels.

kernel void effectWave(
    device uchar4* output [[buffer(0)]],
    constant WaveParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.width) return;

    int x = int(gid);
    int bufWi = int(params.width);
    int bufHt = int(params.height);
    float yc = params.yc;
    float r = params.r;
    float state = params.state;
    int roundedWaveYOffset = params.roundedWaveYOffset;

    constexpr float pi_180 = 0.01745329;

    float degree_per_x = float(params.numberWaves) / float(bufWi);

    // Compute degree and radian for this column
    float degree;
    if (params.waveDirection == 0)
        degree = float(x) * degree_per_x + state;
    else
        degree = float(x) * degree_per_x - state;
    float radian = degree * pi_180;

    // Compute degree/radian for previous column (needed for Square wave)
    float degreeMinus1;
    if (params.waveDirection == 0)
        degreeMinus1 = float(x - 1) * degree_per_x + state;
    else
        degreeMinus1 = float(x - 1) * degree_per_x - state;
    float radianMinus1 = degreeMinus1 * pi_180;

    float sinrad = sin(radian);
    float sinradMinus1 = sin(radianMinus1);

    int ystart;

    if (params.waveType == 1) {
        // Triangle wave
        float waves = (float(params.numberWaves) / 180.0) / 5.0;
        int amp = bufHt * int(params.waveHeight) / 100;

        int xx = x;
        if (params.waveDirection != 0) {
            xx = bufWi - x - 1;
        }

        if (amp == 0) {
            ystart = 0;
        } else {
            int raw = int((state / 10.0 + float(xx)) * waves);
            int mod_val = raw % (2 * amp);
            if (mod_val < 0) mod_val += (2 * amp);
            ystart = (bufHt - amp) / 2 + abs(mod_val - amp);
        }
        if (ystart > bufHt - 1) ystart = bufHt - 1;
    } else {
        // Sine, Square, DecaySine all use sine-based ystart
        ystart = int(r * (float(params.waveHeight) / 100.0) * sinrad + yc);
    }

    // Bounds check
    if (x < 0 || x >= bufWi || ystart < 0 || ystart >= bufHt) return;

    // Compute y range for thickness
    int y1 = int(float(ystart) - (r * (float(params.thicknessWave) / 100.0)));
    int y2 = int(float(ystart) + (r * (float(params.thicknessWave) / 100.0)));
    if (y2 <= y1) y2 = y1 + 1;

    if (params.waveType == 2) {
        // Square wave: override y1/y2 based on sign changes
        bool signCurr = signbit(sinrad);
        bool signPrev = signbit(sinradMinus1);
        if (signCurr != signPrev) {
            y1 = int(yc - yc * (float(params.waveHeight) / 100.0));
            y2 = int(yc + yc * (float(params.waveHeight) / 100.0));
        } else if (sinrad > 0.0) {
            y1 = int(yc + 1.0 + yc * (float(params.waveHeight) / 100.0) * ((100.0 - float(params.thicknessWave)) / 100.0));
            y2 = int(yc + yc * (float(params.waveHeight) / 100.0));
        } else {
            y1 = int(yc - yc * (float(params.waveHeight) / 100.0));
            y2 = int(yc - yc * (float(params.waveHeight) / 100.0) * ((100.0 - float(params.thicknessWave)) / 100.0));
        }

        if (y1 < 0) y1 = 0;
        if (y2 < 1) y2 = 1;
        if (y1 > bufHt - 1) y1 = bufHt - 1;
        if (y2 > bufHt) y2 = bufHt;

        if (y2 <= y1) {
            y2 = y1 + 1;
        }
    }

    int y1mirror = int(yc + (yc - float(y1)));
    int y2mirror = int(yc + (yc - float(y2)));
    float deltay = float(y2 - y1);
    if (deltay <= 0.0) deltay = 1.0;

    // Fill the wave band for this column
    for (int y = y1; y <= y2; y++) {
        int adjustedY = y + roundedWaveYOffset;
        if (adjustedY < 0 || adjustedY >= bufHt) continue;

        uint pixIdx = uint(adjustedY) * params.width + uint(x);

        if (params.fillColor == 0) {
            // Solid: use HSV color 0
            float3 rgb = hsv_to_rgb(float3(params.hsv0_h, params.hsv0_s, params.hsv0_v));
            output[pixIdx] = uchar4(uint8_t(rgb.r * 255.0),
                                     uint8_t(rgb.g * 255.0),
                                     uint8_t(rgb.b * 255.0),
                                     255);
        } else if (params.fillColor == 1) {
            // Rainbow: hue varies across thickness
            float hue = float(y - y1) / deltay;
            float3 rgb = hsv_to_rgb(float3(hue, 1.0, 1.0));
            output[pixIdx] = uchar4(uint8_t(rgb.r * 255.0),
                                     uint8_t(rgb.g * 255.0),
                                     uint8_t(rgb.b * 255.0),
                                     255);
        } else {
            // Palette blend across thickness
            float blend = float(y - y1) / deltay;
            float4 color = get_multi_color_blend(blend, palette,
                                                  params.paletteSize,
                                                  params.circularPalette != 0);
            output[pixIdx] = uchar4(uint8_t(color.r * 255.0),
                                     uint8_t(color.g * 255.0),
                                     uint8_t(color.b * 255.0),
                                     255);
        }
    }

    // Mirror wave
    if (params.mirrorWave) {
        int my1, my2;
        if (y1mirror < y2mirror) {
            my1 = y1mirror;
            my2 = y2mirror;
        } else {
            my2 = y1mirror;
            my1 = y2mirror;
        }

        for (int y = my1; y <= my2; y++) {
            int adjustedY = y + roundedWaveYOffset;
            if (adjustedY < 0 || adjustedY >= bufHt) continue;

            uint pixIdx = uint(adjustedY) * params.width + uint(x);

            if (params.fillColor == 0) {
                float3 rgb = hsv_to_rgb(float3(params.hsv0_h, params.hsv0_s, params.hsv0_v));
                output[pixIdx] = uchar4(uint8_t(rgb.r * 255.0),
                                         uint8_t(rgb.g * 255.0),
                                         uint8_t(rgb.b * 255.0),
                                         255);
            } else if (params.fillColor == 1) {
                float hue = float(y - my1) / deltay;
                float3 rgb = hsv_to_rgb(float3(hue, 1.0, 1.0));
                output[pixIdx] = uchar4(uint8_t(rgb.r * 255.0),
                                         uint8_t(rgb.g * 255.0),
                                         uint8_t(rgb.b * 255.0),
                                         255);
            } else {
                float blend = float(y - my1) / deltay;
                float4 color = get_multi_color_blend(blend, palette,
                                                      params.paletteSize,
                                                      params.circularPalette != 0);
                output[pixIdx] = uchar4(uint8_t(color.r * 255.0),
                                         uint8_t(color.g * 255.0),
                                         uint8_t(color.b * 255.0),
                                         255);
            }
        }
    }
}

// =========================================================================
// Pinwheel Effect Kernel (New Render Method — per-pixel polar approach)
// =========================================================================

kernel void effectPinwheel(
    device uchar4* output [[buffer(0)]],
    constant PinwheelParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    if (params.max_radius <= 0.0) {
        output[gid] = uchar4(0, 0, 0, 0);
        return;
    }

    uint x = gid % params.width;
    uint y = gid / params.width;

    float x1 = float(x) - params.xc_adj_px - params.halfW;
    float y1 = float(y) - params.yc_adj_px - params.halfH;
    float r = sqrt(x1 * x1 + y1 * y1);

    if (r > params.max_radius || r <= 0.0) {
        output[gid] = uchar4(0, 0, 0, 0);
        return;
    }

    float degrees_twist_r = (r / params.max_radius) * params.pinwheel_twist;
    float theta = (atan2(x1, y1) * 180.0 / M_PI_F) + degrees_twist_r;
    if (isnan(theta)) theta = 0.0;

    if (params.pinwheel_rotation != 0) {
        theta = params.pos + theta + (params.tmax / 2.0) + params.poffset;
    } else {
        theta = params.pos - theta + (params.tmax / 2.0) + params.poffset;
    }

    theta = theta + 540.0;
    int t2 = int(theta) % int(params.degrees_per_arm);

    if (t2 > int(params.tmax)) {
        output[gid] = uchar4(0, 0, 0, 0);
        return;
    }

    int colorIdx = int(theta / float(params.degrees_per_arm)) % int(params.pinwheel_arms);
    float4 baseColor = palette[colorIdx % params.paletteSize];

    float round_val = float(t2) / params.tmax;

    if (params.pw3dType == 0) {
        output[gid] = uchar4(uint8_t(baseColor.r * 255.0),
                              uint8_t(baseColor.g * 255.0),
                              uint8_t(baseColor.b * 255.0),
                              255);
    } else if (params.pw3dType == 1) {
        if (params.allowAlpha != 0) {
            float alpha = 255.0 - 255.0 * abs(round_val - 0.5) / 0.5;
            output[gid] = uchar4(uint8_t(baseColor.r * 255.0),
                                  uint8_t(baseColor.g * 255.0),
                                  uint8_t(baseColor.b * 255.0),
                                  uint8_t(alpha));
        } else {
            float3 hsv = rgb_to_hsv(baseColor.rgb);
            hsv.z = 1.0 - hsv.z * abs(round_val - 0.5) / 0.5;
            float3 rgb = hsv_to_rgb(hsv);
            output[gid] = uchar4(uint8_t(rgb.r * 255.0),
                                  uint8_t(rgb.g * 255.0),
                                  uint8_t(rgb.b * 255.0),
                                  255);
        }
    } else if (params.pw3dType == 2) {
        if (params.allowAlpha != 0) {
            float alpha = 255.0 * abs(round_val - 0.5) / 0.5;
            output[gid] = uchar4(uint8_t(baseColor.r * 255.0),
                                  uint8_t(baseColor.g * 255.0),
                                  uint8_t(baseColor.b * 255.0),
                                  uint8_t(alpha));
        } else {
            float3 hsv = rgb_to_hsv(baseColor.rgb);
            hsv.z = hsv.z * abs(round_val - 0.5) / 0.5;
            float3 rgb = hsv_to_rgb(hsv);
            output[gid] = uchar4(uint8_t(rgb.r * 255.0),
                                  uint8_t(rgb.g * 255.0),
                                  uint8_t(rgb.b * 255.0),
                                  255);
        }
    } else {
        if (params.allowAlpha != 0) {
            float alpha = 255.0 * round_val;
            output[gid] = uchar4(uint8_t(baseColor.r * 255.0),
                                  uint8_t(baseColor.g * 255.0),
                                  uint8_t(baseColor.b * 255.0),
                                  uint8_t(alpha));
        } else {
            float3 hsv = rgb_to_hsv(baseColor.rgb);
            hsv.z = hsv.z * round_val;
            float3 rgb = hsv_to_rgb(hsv);
            output[gid] = uchar4(uint8_t(rgb.r * 255.0),
                                  uint8_t(rgb.g * 255.0),
                                  uint8_t(rgb.b * 255.0),
                                  255);
        }
    }
}

// =========================================================================
// Spirals Effect Kernel
// =========================================================================

kernel void effectSpirals(
    device uchar4* output [[buffer(0)]],
    constant SpiralsParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    uint px = gid % params.width;
    uint py = gid / params.width;

    float yOffset = float(py) * params.rotation / float(params.height);
    float unwound = float(px) - params.spiralState - yOffset;

    float fWidth = float(params.width);
    unwound = unwound - floor(unwound / fWidth) * fWidth;

    bool hit = false;
    int hitSpiralIdx = 0;
    int hitThick = 0;
    int thicknessInt = int(params.spiralThickness);

    for (int ns = 0; ns < int(params.spiralCount); ns++) {
        float strand_base = float(ns) * params.deltaStrands;

        float localPos = unwound - strand_base;
        localPos = localPos - floor(localPos / fWidth) * fWidth;

        if (localPos < params.spiralThickness && localPos < float(thicknessInt)) {
            hit = true;
            hitSpiralIdx = ns;
            hitThick = int(localPos);
            break;
        }
    }

    if (!hit) {
        output[gid] = uchar4(0, 0, 0, 0);
        return;
    }

    int colorIdx = hitSpiralIdx % int(params.colorcnt);
    float4 color = palette[colorIdx];

    if (params.blend) {
        float blendPos = float(params.height - py - 1) / float(params.height);
        color = get_multi_color_blend(blendPos, palette, params.paletteSize, false);
    }

    if (params.show3D) {
        float f = 1.0;
        if (params.rotationRaw < 0.0) {
            f = float(hitThick + 1) / params.spiralThickness;
        } else {
            f = (params.spiralThickness - float(hitThick)) / params.spiralThickness;
        }

        if (params.allowAlpha) {
            output[gid] = uchar4(uint8_t(color.r * 255.0),
                                  uint8_t(color.g * 255.0),
                                  uint8_t(color.b * 255.0),
                                  uint8_t(255.0 * f));
        } else {
            output[gid] = apply_brightness(color.rgb, f);
        }
    } else {
        output[gid] = uchar4(uint8_t(color.r * 255.0),
                              uint8_t(color.g * 255.0),
                              uint8_t(color.b * 255.0),
                              255);
    }
}

// =========================================================================
// Spirograph Effect Kernel
// =========================================================================
//
// Each thread corresponds to one (curveSample, widthSample) pair.
// The thread computes the parametric curve position and writes a colored
// pixel to the output buffer. Non-hit pixels remain black (pre-cleared).

kernel void effectSpirograph(
    device uchar4* output [[buffer(0)]],
    constant SpirographParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    uint curveSampleIdx = gid / params.numWidthSamples;
    uint widthSampleIdx = gid % params.numWidthSamples;

    if (curveSampleIdx >= params.numCurveSamples) return;

    float i = 1.0f + float(curveSampleIdx) * params.stepCurve;
    if (i > params.lengthScaled) return;

    float t = (i + float(params.mod1440)) * M_PI_F / 180.0f;

    float R_minus_r = params.R - params.r;
    float ratio = R_minus_r / params.r;
    float x = R_minus_r * cos(t) + params.d * cos(ratio * t) + params.xc;
    float y = R_minus_r * sin(t) + params.d * sin(ratio * t) + params.yc;

    float dx = x - params.xc;
    float dy = y - params.yc;
    float hyp = (sqrt(dx * dx + dy * dy) / float(params.width)) * 100.0f;
    int colorIdx = int(hyp) / params.d_mod;
    if (colorIdx >= int(params.paletteSize)) colorIdx = int(params.paletteSize) - 1;
    if (colorIdx < 0) colorIdx = 0;

    float4 color = palette[colorIdx];

    float tt = ratio * t;
    float w = -params.halfWidth + float(widthSampleIdx) * params.stepWidth;

    int xx = int(x + w * cos(tt));
    int yy = int(y + w * sin(tt));

    if (xx >= 0 && xx < int(params.width) && yy >= 0 && yy < int(params.height)) {
        uint pixelIdx = uint(yy) * params.width + uint(xx);
        output[pixelIdx] = uchar4(uint8_t(color.r * 255.0f),
                                   uint8_t(color.g * 255.0f),
                                   uint8_t(color.b * 255.0f),
                                   255);
    }
}

// =========================================================================
// Fan Effect Kernel
// =========================================================================

kernel void effectFan(
    device uchar4* output [[buffer(0)]],
    constant FanParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    uint px = gid % params.width;
    uint py = gid / params.width;

    float x1 = float(px) - params.centerX;
    float y1 = float(py) - params.centerY;

    float r = sqrt(x1 * x1 + y1 * y1);

    if (r < params.radius1 || r > params.radius2) {
        output[gid] = uchar4(0, 0, 0, 0);
        return;
    }

    float degrees_twist = (r / params.maxRadius) * params.bladeAngle;

    float theta = (atan2(x1, y1) * 180.0 / M_PI_F) + degrees_twist + params.startAngle;

    if (params.reverseDir) {
        theta = params.angleOffset - theta + 180.0;
    } else {
        theta = theta + 180.0 + params.angleOffset;
    }

    theta = fmod(theta, 360.0);
    if (theta < 0.0) {
        theta += 360.0;
    }

    float current_blade_angle = fmod(theta, params.bladeDivAngle);

    if (current_blade_angle > params.bladeWidthAngle) {
        output[gid] = uchar4(0, 0, 0, 0);
        return;
    }

    float current_element_angle = fmod(current_blade_angle, params.elementAngle);

    if (current_element_angle > params.elementSize) {
        output[gid] = uchar4(0, 0, 0, 0);
        return;
    }

    int color_index = int(current_blade_angle / params.colorAngle);
    if (color_index >= int(params.numColors)) color_index = int(params.numColors) - 1;
    float4 color = palette[color_index];

    float color_pct = 1.0 - ((abs(current_element_angle - (params.elementSize / 2.0)) * 2.0) / params.elementSize);

    if (params.blendEdges) {
        if (params.allowAlpha) {
            uint8_t a = uint8_t(255.0 * color_pct);
            output[gid] = uchar4(uint8_t(color.r * 255.0),
                                  uint8_t(color.g * 255.0),
                                  uint8_t(color.b * 255.0),
                                  a);
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
