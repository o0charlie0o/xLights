/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// NativeLayerBlendingShaders.metal
//
// Metal compute shaders for GPU-accelerated layer blending in the native
// macOS render pipeline. Replaces the CPU per-pixel blending loop in
// NativePixelBuffer::calcOutput().
//
// The shader processes one pixel per thread. For each pixel, it iterates
// through all layers (back-to-front), applies per-layer HSV/brightness/
// contrast adjustments, blends using the specified mix type, and writes
// the final blended color to the output buffer.
//
// This mirrors the logic in NativeColorBlending.cpp and the legacy
// LayerBlendingFunctions.metal, adapted for the native pipeline's
// consolidated single-kernel approach.

#include <metal_stdlib>
using namespace metal;

// =========================================================================
// Shared data types — must match MetalBlendingCompute.h
// =========================================================================

// Mix type enum values matching NativeMixType in NativeColorBlending.h
constant int MIX_NORMAL = 0;
constant int MIX_EFFECT1 = 1;
constant int MIX_EFFECT2 = 2;
constant int MIX_MASK1 = 3;
constant int MIX_MASK2 = 4;
constant int MIX_UNMASK1 = 5;
constant int MIX_UNMASK2 = 6;
constant int MIX_TRUEUNMASK1 = 7;
constant int MIX_TRUEUNMASK2 = 8;
constant int MIX_1_REVEALS_2 = 9;
constant int MIX_2_REVEALS_1 = 10;
constant int MIX_LAYERED = 11;
constant int MIX_AVERAGE = 12;
constant int MIX_BOTTOMTOP = 13;
constant int MIX_LEFTRIGHT = 14;
constant int MIX_SHADOW_1ON2 = 15;
constant int MIX_SHADOW_2ON1 = 16;
constant int MIX_ADDITIVE = 17;
constant int MIX_SUBTRACTIVE = 18;
constant int MIX_ASBRIGHTNESS = 19;
constant int MIX_MAX = 20;
constant int MIX_MIN = 21;
constant int MIX_HIGHLIGHT = 22;
constant int MIX_HIGHLIGHT_VIBRANT = 23;

// Per-layer settings, packed for GPU transfer.
struct GPULayerSettings {
    int mixType;
    float effectMixThreshold;
    int effectMixVary;     // bool as int
    float fadeFactor;
    int allowAlpha;        // bool as int
    float hueAdjust;
    float saturationAdjust;
    float valueAdjust;
    int brightness;
    int contrast;
    int isChromaKey;       // bool as int
    int chromaSensitivity;
    uchar4 chromaKeyColour;
    int isValid;           // bool as int — whether this layer participates in blending
    int maskOffset;        // offset into the mask buffer for this layer, -1 if no mask
    int maskSize;          // number of bytes in the mask for this layer (0 if no mask)
    int _padding0;
};

// Global parameters for the blend pass.
struct GPUBlendParams {
    int bufferWi;
    int bufferHt;
    int numLayers;
    int totalPixels;
};

// =========================================================================
// HSV conversion utilities (matching legacy LayerBlendingFunctions.metal)
// =========================================================================

float3 rgb_to_hsv(uchar4 c) {
    float r = c.r / 255.0;
    float g = c.g / 255.0;
    float b = c.b / 255.0;

    float K = 0.0;
    if (g < b) {
        float tmp = g;
        g = b;
        b = tmp;
        K = -1.0;
    }
    float min_gb = b;
    if (r < g) {
        float tmp = r;
        r = g;
        g = tmp;
        K = -2.0 / 6.0 - K;
        min_gb = min(g, b);
    }
    float chroma = r - min_gb;
    float3 v;
    v.x = abs(K + (g - b) / (6.0 * chroma + 1e-20));
    v.y = chroma / (r + 1e-20);
    v.z = r;
    return v;
}

uchar4 hsv_to_rgb(float3 hsv, uchar alpha) {
    float red, green, blue;

    if (0.0f == hsv.y) {
        red = hsv.z;
        green = hsv.z;
        blue = hsv.z;
    } else {
        float hue = hsv.x * 6.0;
        int i = (int)floor(hue);
        float f = hue - i;
        float p = hsv.z * (1.0 - hsv.y);

        switch (i) {
            case 0:
                red = hsv.z;
                green = hsv.z * (1.0 - hsv.y * (1.0 - f));
                blue = p;
                break;
            case 1:
                red = hsv.z * (1.0 - hsv.y * f);
                green = hsv.z;
                blue = p;
                break;
            case 2:
                red = p;
                green = hsv.z;
                blue = hsv.z * (1.0 - hsv.y * (1.0 - f));
                break;
            case 3:
                red = p;
                green = hsv.z * (1.0 - hsv.y * f);
                blue = hsv.z;
                break;
            case 4:
                red = hsv.z * (1.0 - hsv.y * (1.0 - f));
                green = p;
                blue = hsv.z;
                break;
            default:
                red = hsv.z;
                green = p;
                blue = hsv.z * (1.0 - hsv.y * f);
                break;
        }
    }
    return {(uint8_t)(red * 255.0),
            (uint8_t)(green * 255.0),
            (uint8_t)(blue * 255.0),
            alpha};
}

// =========================================================================
// Alpha blending
// =========================================================================

uchar4 alpha_blend_fg_onto(uchar4 bg, uchar4 fg) {
    if (fg.a == 0) return bg;
    if (fg.a == 255) return {fg.r, fg.g, fg.b, bg.a};

    float a = fg.a / 255.0;
    float dr = fg.r * a + bg.r * (1.0f - a);
    float dg = fg.g * a + bg.g * (1.0f - a);
    float db = fg.b * a + bg.b * (1.0f - a);
    return {(uint8_t)dr, (uint8_t)dg, (uint8_t)db, bg.a};
}

// =========================================================================
// Chroma key check
// =========================================================================

float colour_distance(uchar4 e1, uchar4 e2) {
    int rmean = (e1.r + e2.r) / 2;
    int r = e1.r - e2.r;
    int g = e1.g - e2.g;
    int b = e1.b - e2.b;
    int f1 = (((512 + rmean) * r * r) >> 8);
    int f2 = (((767 - rmean) * b * b) >> 8);
    float f3 = f1 + 4 * g * g + f2;
    return sqrt(f3);
}

bool apply_chroma(constant GPULayerSettings &layer, uchar4 c) {
    if (!layer.isChromaKey) return false;
    uchar4 adj = c;
    if (adj.a < 255) {
        adj.r = (int)(adj.r * adj.a) / 255;
        adj.g = (int)(adj.g * adj.a) / 255;
        adj.b = (int)(adj.b * adj.a) / 255;
        adj.a = 255;
    }
    if (colour_distance(adj, layer.chromaKeyColour) < (layer.chromaSensitivity * 402 / 255)) {
        return true;
    }
    return false;
}

// =========================================================================
// Per-layer color adjustments
// =========================================================================

uchar4 adjust_hsv(uchar4 color, float hueAdj, float satAdj, float valAdj) {
    if (hueAdj == 0.0f && satAdj == 0.0f && valAdj == 0.0f) {
        return color;
    }

    float3 hsv = rgb_to_hsv(color);

    if (hueAdj != 0.0f) {
        hsv.x += hueAdj;
        if (hsv.x < 0.0) hsv.x += 1.0;
        else if (hsv.x > 1.0) hsv.x -= 1.0;
    }
    if (satAdj != 0.0f) {
        hsv.y += satAdj;
        hsv.y = clamp(hsv.y, 0.0f, 1.0f);
    }
    if (valAdj != 0.0f) {
        hsv.z += valAdj;
        hsv.z = clamp(hsv.z, 0.0f, 1.0f);
    }

    return hsv_to_rgb(hsv, color.a);
}

uchar4 adjust_brightness_contrast(uchar4 color, int brightness, int contrast) {
    if (contrast != 0) {
        float b = (float)brightness;
        float c = (float)contrast;
        float3 hsv = rgb_to_hsv(color);
        hsv.z = hsv.z * (b / 100.0);
        if (hsv.z < 0.5) {
            hsv.z = hsv.z - (hsv.z * (c / 100.0));
        } else {
            hsv.z = hsv.z + (hsv.z * (c / 100.0));
        }
        hsv.z = clamp(hsv.z, 0.0f, 1.0f);
        uchar alpha = color.a;
        color = hsv_to_rgb(hsv, alpha);
    } else if (brightness != 100) {
        float ba = brightness / 100.0f;
        color.r = (uchar)min((int)(color.r * ba), 255);
        color.g = (uchar)min((int)(color.g * ba), 255);
        color.b = (uchar)min((int)(color.b * ba), 255);
    }
    return color;
}

// =========================================================================
// Mix colors — single function implementing all 24 mix types
// =========================================================================

uchar4 mix_colors(int x, int y, uchar4 fg, uchar4 bg,
                   constant GPULayerSettings &layer,
                   int bufferWi, int bufferHt) {
    // Apply non-alpha fade
    if (!layer.allowAlpha && layer.fadeFactor != 1.0f) {
        float3 hsv = rgb_to_hsv(fg);
        hsv.z *= layer.fadeFactor;
        fg = hsv_to_rgb(hsv, fg.a);
    }

    // Chroma key check
    if (apply_chroma(layer, fg)) {
        return bg;
    }

    float emt = layer.effectMixThreshold;
    int mt = layer.mixType;

    if (mt == MIX_NORMAL) {
        fg.a = (uchar)(fg.a * layer.fadeFactor * (1.0 - emt));
        return alpha_blend_fg_onto(bg, fg);
    }
    if (mt == MIX_EFFECT1 || mt == MIX_EFFECT2) {
        float emtVal, emtNot;
        if (!layer.effectMixVary) {
            emtVal = emt;
            if ((emtVal > 0.000001) && (emtVal < 0.99999)) {
                emtNot = 1.0 - emt;
                emtVal = cos((M_PI_F / 4.0) * (pow(2.0 * emtVal - 1.0, 1.0) + 1.0));
                emtNot = cos((M_PI_F / 4.0) * (pow(2.0 * emtNot - 1.0, 1.0) + 1.0));
            } else {
                emtNot = emt;
                emtVal = 1.0 - emt;
            }
        } else {
            emtVal = emt;
            emtNot = 1.0 - emt;
        }
        if (mt == MIX_EFFECT2) {
            fg = {(uchar)(fg.r * emtNot), (uchar)(fg.g * emtNot), (uchar)(fg.b * emtNot), fg.a};
            bg = {(uchar)(bg.r * emtVal), (uchar)(bg.g * emtVal), (uchar)(bg.b * emtVal), bg.a};
        } else {
            fg = {(uchar)(fg.r * emtVal), (uchar)(fg.g * emtVal), (uchar)(fg.b * emtVal), fg.a};
            bg = {(uchar)(bg.r * emtNot), (uchar)(bg.g * emtNot), (uchar)(bg.b * emtNot), bg.a};
        }
        return {(uchar)(fg.r + bg.r), (uchar)(fg.g + bg.g), (uchar)(fg.b + bg.b), 255};
    }
    if (mt == MIX_MASK1) {
        float3 hsv0 = rgb_to_hsv(fg);
        if (hsv0.z > emt) {
            return {0, 0, 0, 255};
        }
        return bg;
    }
    if (mt == MIX_MASK2) {
        float3 hsv1 = rgb_to_hsv(bg);
        if (hsv1.z <= emt) {
            return fg;
        }
        return {0, 0, 0, 255};
    }
    if (mt == MIX_UNMASK1) {
        float3 hsv0 = rgb_to_hsv(fg);
        if (hsv0.z > emt) {
            float3 hsv1 = rgb_to_hsv(bg);
            hsv1.z = hsv0.z;
            return hsv_to_rgb(hsv1, 255);
        }
        return {0, 0, 0, 255};
    }
    if (mt == MIX_UNMASK2) {
        float3 hsv1 = rgb_to_hsv(bg);
        if (hsv1.z > emt) {
            float3 hsv0 = rgb_to_hsv(fg);
            hsv0.z = hsv1.z;
            return hsv_to_rgb(hsv0, 255);
        }
        return {0, 0, 0, 255};
    }
    if (mt == MIX_TRUEUNMASK1) {
        float3 hsv0 = rgb_to_hsv(fg);
        if (hsv0.z <= emt) {
            return {0, 0, 0, 255};
        }
        return bg;
    }
    if (mt == MIX_TRUEUNMASK2) {
        float3 hsv1 = rgb_to_hsv(bg);
        if (hsv1.z > emt) {
            return fg;
        }
        return {0, 0, 0, 255};
    }
    if (mt == MIX_1_REVEALS_2) {
        float3 hsv0 = rgb_to_hsv(fg);
        return hsv0.z > emt ? fg : bg;
    }
    if (mt == MIX_2_REVEALS_1) {
        float3 hsv1 = rgb_to_hsv(bg);
        return hsv1.z > emt ? bg : fg;
    }
    if (mt == MIX_LAYERED) {
        float3 hsv1 = rgb_to_hsv(bg);
        if (hsv1.z <= emt) {
            return fg;
        }
        return bg;
    }
    if (mt == MIX_AVERAGE) {
        uchar3 BLACK = {0, 0, 0};
        bool bgIsBlack = (bg.r == BLACK.x && bg.g == BLACK.y && bg.b == BLACK.z) || bg.a == 0;
        bool fgIsBlack = (fg.r == BLACK.x && fg.g == BLACK.y && fg.b == BLACK.z) || fg.a == 0;
        if (bgIsBlack) {
            return fg;
        } else if (!fgIsBlack) {
            return {(uchar)((fg.r + bg.r) / 2), (uchar)((fg.g + bg.g) / 2),
                    (uchar)((fg.b + bg.b) / 2), (uchar)((fg.a + bg.a) / 2)};
        }
        return bg;
    }
    if (mt == MIX_BOTTOMTOP) {
        return y < bufferHt / 2 ? fg : bg;
    }
    if (mt == MIX_LEFTRIGHT) {
        return x < bufferWi / 2 ? fg : bg;
    }
    if (mt == MIX_SHADOW_1ON2) {
        float3 hsv0 = rgb_to_hsv(fg);
        float3 hsv1 = rgb_to_hsv(bg);
        if (hsv0.z > 0.0) {
            hsv1.x = hsv1.x + (hsv0.z * (hsv1.x - hsv0.x)) / 5.0;
        }
        return hsv_to_rgb(hsv1, 255);
    }
    if (mt == MIX_SHADOW_2ON1) {
        float3 hsv0 = rgb_to_hsv(fg);
        float3 hsv1 = rgb_to_hsv(bg);
        if (hsv1.z > 0.0) {
            hsv0.x = hsv0.x + (hsv1.z * (hsv0.x - hsv1.x)) / 2.0;
        }
        return hsv_to_rgb(hsv0, 255);
    }
    if (mt == MIX_ADDITIVE) {
        int r = fg.r + bg.r;
        int g = fg.g + bg.g;
        int b = fg.b + bg.b;
        return {(uchar)min(r, 255), (uchar)min(g, 255), (uchar)min(b, 255), 255};
    }
    if (mt == MIX_SUBTRACTIVE) {
        int r = bg.r - fg.r;
        int g = bg.g - fg.g;
        int b = bg.b - fg.b;
        return {(uchar)max(r, 0), (uchar)max(g, 0), (uchar)max(b, 0), 255};
    }
    if (mt == MIX_ASBRIGHTNESS) {
        float alpha = (float)fg.a / 255.0;
        int r = fg.r * bg.r / 255 * alpha;
        int g = fg.g * bg.g / 255 * alpha;
        int b = fg.b * bg.b / 255 * alpha;
        return {(uchar)r, (uchar)g, (uchar)b, 255};
    }
    if (mt == MIX_MAX) {
        float alpha = (float)fg.a / 255.0;
        int r = max(fg.r, bg.r) * alpha;
        int g = max(fg.g, bg.g) * alpha;
        int b = max(fg.b, bg.b) * alpha;
        return {(uchar)r, (uchar)g, (uchar)b, 255};
    }
    if (mt == MIX_MIN) {
        float alpha = (float)fg.a / 255.0;
        int r = min(fg.r, bg.r) * alpha;
        int g = min(fg.g, bg.g) * alpha;
        int b = min(fg.b, bg.b) * alpha;
        return {(uchar)r, (uchar)g, (uchar)b, 255};
    }
    if (mt == MIX_HIGHLIGHT) {
        bool effect1HasColor = (fg.r > 0 || fg.g > 0 || fg.b > 0);
        bool effect2HasColor = (bg.r > 0 || bg.g > 0 || bg.b > 0);
        float3 hsv1 = rgb_to_hsv(bg);
        if (effect1HasColor && (effect2HasColor || hsv1.z > emt)) {
            return fg;
        }
        return bg;
    }
    if (mt == MIX_HIGHLIGHT_VIBRANT) {
        float3 hsv1 = rgb_to_hsv(bg);
        if (hsv1.z > emt) {
            int r = fg.r + bg.r;
            int g = fg.g + bg.g;
            int b = fg.b + bg.b;
            return {(uchar)min(r, 255), (uchar)min(g, 255), (uchar)min(b, 255), 255};
        }
        return bg;
    }

    // Fallback: return background unchanged
    return bg;
}

// =========================================================================
// Main compute kernel: blend all layers per pixel
// =========================================================================

kernel void blendLayers(
    constant GPUBlendParams &params       [[buffer(0)]],
    constant GPULayerSettings *layers     [[buffer(1)]],
    const device uchar4 *layerPixels     [[buffer(2)]],  // flattened: layer0 pixels, layer1 pixels, ...
    const device uchar *masks            [[buffer(3)]],  // concatenated transition masks
    device uchar4 *output                [[buffer(4)]],
    uint index [[thread_position_in_grid]])
{
    if (index >= (uint)params.totalPixels) return;

    int px = index % params.bufferWi;
    int py = index / params.bufferWi;

    int cnt = 0;
    uchar4 result = {0, 0, 0, 255};

    int pixelsPerLayer = params.totalPixels;

    // Iterate from back (highest layer) to front (layer 0)
    for (int layer = params.numLayers - 1; layer >= 0; --layer) {
        constant GPULayerSettings &ls = layers[layer];
        if (!ls.isValid) continue;

        // Read pixel from this layer's region in the flattened buffer
        uchar4 color = layerPixels[layer * pixelsPerLayer + index];

        // Apply transition mask if present
        if (ls.maskOffset >= 0 && ls.maskSize > 0) {
            int maskIdx = px * params.bufferHt + py;
            if (maskIdx < ls.maskSize) {
                if (masks[ls.maskOffset + maskIdx] > 0) {
                    color = {0, 0, 0, 0};
                }
            }
        }

        // Apply HSV adjustments
        color = adjust_hsv(color, ls.hueAdjust, ls.saturationAdjust, ls.valueAdjust);

        // Apply brightness/contrast
        color = adjust_brightness_contrast(color, ls.brightness, ls.contrast);

        // Blend with accumulated result
        if (cnt > 0) {
            result = mix_colors(px, py, color, result, ls, params.bufferWi, params.bufferHt);
        } else if (ls.fadeFactor != 1.0f) {
            // First valid layer but needs fade
            float3 hsv = rgb_to_hsv(color);
            hsv.z *= ls.fadeFactor;
            if (color.a != 255) {
                hsv.z *= color.a;
                hsv.z /= 255.0f;
            }
            result = hsv_to_rgb(hsv, 255);
        } else {
            // First valid layer, no fade -- alpha blend onto black
            result = alpha_blend_fg_onto(result, color);
        }
        cnt++;
    }

    output[index] = result;
}
