/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// MetalKernels_Pattern.metal
//
// Metal compute kernels for pattern and grid-based effects.
// These effects produce repeating geometric patterns, chase sequences,
// and perimeter-based animations across the pixel buffer.
//
// Effects in this file:
//   - On:           Simple fill with intensity ramp and shimmer
//   - ColorWash:    Palette gradient with optional fades
//   - Bars:         Colored bar patterns with gradient, 3D, and highlight options
//   - Butterfly:    Mathematical butterfly and plasma patterns
//   - Curtain:      Opening/closing curtain reveals with swag curves
//   - Garlands:     Draped garland/swag patterns across the buffer
//   - Marquee:      Perimeter chase lights around rectangular borders
//   - SingleStrand: Skip and chase patterns for single-strand pixel layouts

#include "MetalEffectTypes.h"

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

// =========================================================================
// Bars Effect Kernel
// =========================================================================

// Compute the bar "n" value for a given output coordinate.
// Returns the effective scan-axis coordinate used to derive color.
// For vertical directions, the scan axis is y; for horizontal, x.
static int bars_compute_n(uint px, uint py, constant BarsParams& p) {
    uint dir = p.direction;

    if (dir < 4 || dir == 8 || dir == 9) {
        // Vertical directions
        int effectiveY;
        int dirLocal = dir > 4 ? int(dir) - 8 : int(dir);

        switch (dirLocal) {
            case 0: // up
                effectiveY = int(p.height) - int(py) - 1;
                break;
            case 1: // down
                effectiveY = int(py);
                break;
            case 2: // expand
                effectiveY = int(p.newCenter) - abs(int(py) - int(p.newCenter));
                break;
            case 3: // compress
                effectiveY = int(p.newCenter) + abs(int(py) - int(p.newCenter));
                break;
            default:
                effectiveY = int(p.height) - int(py) - 1;
                break;
        }
        return int(p.height) + effectiveY + p.fOffset;

    } else if (dir == 12 || dir == 13) {
        // Custom Horz / Custom Vert
        int coord = (dir == 12) ? int(px) : int(py);
        int width = (dir == 12) ? int(p.width) : int(p.height);
        int scanX = width - 1 + p.newCenter - coord;
        return width + scanX;

    } else {
        // Horizontal directions: 4=left, 5=right, 6=H-expand, 7=H-compress, 10=altLeft, 11=altRight
        int effectiveX;
        int dirLocal = dir > 9 ? int(dir) - 6 : int(dir);

        switch (dirLocal) {
            case 4: // left
                effectiveX = int(px);
                break;
            case 5: // right
                effectiveX = int(p.width) - int(px) - 1;
                break;
            case 6: // H-expand
                effectiveX = int(p.newCenter) - abs(int(px) - int(p.newCenter));
                break;
            case 7: // H-compress
                effectiveX = int(p.newCenter) + abs(int(px) - int(p.newCenter));
                break;
            default:
                effectiveX = int(px);
                break;
        }
        return int(p.width) + effectiveX + p.fOffset;
    }
}

kernel void effectBars(
    device uchar4* output [[buffer(0)]],
    constant BarsParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    uint px = gid % params.width;
    uint py = gid / params.width;

    int n = bars_compute_n(px, py, params);

    int barDim = int(params.barDim);
    int blockDim = int(params.blockDim);
    int colorcnt = int(params.colorcnt);

    if (barDim < 1) barDim = 1;
    if (blockDim < 1) blockDim = 1;

    // Compute color index and gradient pct
    int nModBlock = n % blockDim;
    if (nModBlock < 0) nModBlock += blockDim;
    int colorIdx = nModBlock / barDim;

    if (params.useFirstColorForHighlight) {
        colorIdx += 1;
    }

    int colorIdx2 = (colorIdx + 1) % colorcnt;
    int nModBar = n % barDim;
    if (nModBar < 0) nModBar += barDim;
    float pct = float(nModBar) / float(barDim);

    // Get base color from palette (clamp index to valid range)
    int palIdx1 = colorIdx % int(params.paletteSize);
    if (palIdx1 < 0) palIdx1 += int(params.paletteSize);
    int palIdx2 = colorIdx2 % int(params.paletteSize);
    if (palIdx2 < 0) palIdx2 += int(params.paletteSize);

    float4 color = palette[palIdx1];

    // Gradient: blend between adjacent palette colors
    if (params.gradient) {
        color = blend_colors(palette[palIdx1], palette[palIdx2], pct);
    }

    // Highlight: white (or first palette color) on bar boundaries
    if (params.highlight && nModBar == 0) {
        if (params.useFirstColorForHighlight) {
            color = palette[0];
        } else {
            color = float4(1.0, 1.0, 1.0, 1.0);  // xlWHITE
        }
    }

    // 3D effect: darken based on position within bar
    float brightness = 1.0;
    if (params.show3D) {
        int numerator = barDim - nModBar - 1;
        brightness = float(numerator) / float(barDim);
    }

    // Apply brightness via HSV value channel
    if (brightness >= 0.999 && !params.show3D) {
        output[gid] = uchar4(uint8_t(color.r * 255.0),
                              uint8_t(color.g * 255.0),
                              uint8_t(color.b * 255.0),
                              255);
    } else {
        output[gid] = apply_brightness(color.rgb, brightness);
    }
}

// =========================================================================
// Butterfly Effect Kernel
// =========================================================================

// HSV hue-only to RGB (s=1, v=1) — matches CPU h2rgb lambda
static uchar4 h2rgb(float h) {
    h = clamp(h, 0.0f, 1.0f);
    float hue = h * 6.0f;
    int i = int(floor(hue));
    float f = hue - float(i);
    float r, g, b;
    switch (i) {
        case 6:
        case 0:  r = 1.0f; g = f;        b = 0.0f;      break;
        case 1:  r = 1.0f - f; g = 1.0f; b = 0.0f;      break;
        case 2:  r = 0.0f; g = 1.0f;     b = f;          break;
        case 3:  r = 0.0f; g = 1.0f - f; b = 1.0f;      break;
        case 4:  r = f;    g = 0.0f;     b = 1.0f;      break;
        default: r = 1.0f; g = 0.0f;     b = 1.0f - f;  break;
    }
    return uchar4(uint8_t(r * 255.0f), uint8_t(g * 255.0f), uint8_t(b * 255.0f), 255);
}

kernel void effectButterfly(
    device uchar4* output [[buffer(0)]],
    constant ButterflyParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    uint x = gid % params.width;
    uint y = gid / params.width;
    float fx = float(x);
    float fy = float(y);
    int width = int(params.width);
    int height = int(params.height);

    const float pi = 3.14159f;
    const float pi2 = pi * 2.0f;

    if (params.style <= 5) {
        // Styles 1-5: mathematical butterfly patterns
        float h = 0.0f;

        switch (params.style) {
            case 1: {
                float sz = float(height + width);
                float rsz = pi2 / sz;
                float x2 = fx * fx;
                float y2 = fy * fy;
                float n = abs((x2 - y2) * sin(params.offset + (fx + fy) * rsz));
                float d = x2 + y2;
                h = d > 0.001f ? min(n / d, 1.0f) : 0.0f;
                break;
            }
            case 2: {
                int maxframe = height * 2;
                int frame = (height * params.curState / 200) % maxframe;
                if (frame < 0) frame += maxframe;
                float f = (frame < height) ? float(frame + 1) : float(maxframe - frame);
                float x1 = (fx - float(width) / 2.0f) / f;
                float y1 = (fy - float(height) / 2.0f) / f;
                h = sqrt(x1 * x1 + y1 * y1);
                break;
            }
            case 3: {
                int maxframe = height * 2;
                int frame = (height * params.curState / 200) % maxframe;
                if (frame < 0) frame += maxframe;
                float f = (frame < maxframe / 2) ? float(frame + 1) : float(maxframe - frame);
                f = f * 0.1f + float(height) / 60.0f;
                float x1 = (fx - float(width) / 2.0f) / f;
                float y1 = (fy - float(height) / 2.0f) / f;
                h = sin(x1) * cos(y1);
                break;
            }
            case 4: {
                float sz = float(height + width);
                float rsz = pi2 / sz;
                float n = (fx * fx - fy * fy) * sin(params.offset + (fx + fy) * rsz);
                float d = fx * fx + fy * fy;
                h = d > 0.001f ? n / d : 0.0f;
                float intpart = floor(h);
                h = h - intpart;
                if (h < 0.0f) h = 1.0f + h;
                break;
            }
            case 5: {
                float ax = fx, ay = fy;
                if (x == 0 && y == 1) ay += 1.0f;
                if (x == 1 && y == 0) ax += 1.0f;
                float n = abs((ax * ax - ay * ay) *
                    sin(params.offset + (ax + ay) * pi2 / float(height * width)));
                float d = ax * ax + ay * ay;
                h = d > 0.001f ? n / d : 0.0f;
                break;
            }
            default:
                break;
        }

        // Skip check: if chunks > 1 and this chunk should be skipped, leave pixel black
        if (params.chunks > 1 && (int(h * float(params.chunks)) % int(params.skip)) == 0) {
            output[gid] = uchar4(0, 0, 0, 0);
            return;
        }

        if (params.colorScheme == 0) {
            // Rainbow
            output[gid] = h2rgb(h);
        } else {
            // Palette blend
            float4 color = get_multi_color_blend(h, palette, params.paletteSize, false);
            output[gid] = uchar4(uint8_t(color.r * 255.0f),
                                  uint8_t(color.g * 255.0f),
                                  uint8_t(color.b * 255.0f),
                                  255);
        }
    } else {
        // Styles 6-10: plasma patterns
        float invh = 1.0f / float(height);
        float invw = 1.0f / float(width);
        float time = params.plasmaTime;
        float halfTime = time / 2.0f;
        float thirdTime = time / 3.0f;
        float fifthTime = time / 5.0f;
        float oneThird = 1.0f / 3.0f;
        float fchunks = float(params.chunks);

        float rx = fx * invw - 0.5f;
        float ry = fy * invh - 0.5f;

        // 1st equation
        float v = sin(rx * 10.0f + time);

        // 2nd equation
        v += sin(10.0f * (rx * sin(halfTime) + ry * cos(thirdTime)) + time);

        // 3rd equation
        float cx = rx + 0.5f * sin(fifthTime);
        float cy = ry + 0.5f * cos(thirdTime);
        v += sin(sqrt(100.0f * (cx * cx + cy * cy) + 1.0f + time));

        v += sin(rx + time);
        v += sin((ry + time) * 0.5f);
        v += sin((rx + ry + time) * 0.5f);

        v += sin(sqrt(rx * rx + ry * ry + 1.0f) + time);
        v = v * 0.5f;

        uchar4 color;
        switch (params.style) {
            case 6:
                color = uchar4(
                    uint8_t((sin(v * fchunks * pi) + 1.0f) * 128.0f),
                    uint8_t((cos(v * fchunks * pi) + 1.0f) * 128.0f),
                    0, 255);
                break;
            case 7:
                color = uchar4(
                    1,
                    uint8_t((cos(v * fchunks * pi) + 1.0f) * 128.0f),
                    uint8_t((sin(v * fchunks * pi) + 1.0f) * 128.0f),
                    255);
                break;
            case 8:
                color = uchar4(
                    uint8_t((sin(v * fchunks * pi) + 1.0f) * 128.0f),
                    uint8_t((sin(v * fchunks * pi + 2.0f * pi * oneThird) + 1.0f) * 128.0f),
                    uint8_t((sin(v * fchunks * pi + 4.0f * pi * oneThird) + 1.0f) * 128.0f),
                    255);
                break;
            case 9: {
                uint8_t gray = uint8_t((sin(v * fchunks * pi) + 1.0f) * 128.0f);
                color = uchar4(gray, gray, gray, 255);
                break;
            }
            case 10:
                if (params.paletteSize >= 2) {
                    float h = sin(v * fchunks * pi + 2.0f * pi * oneThird) + 0.5f;
                    float4 blended = get_multi_color_blend(h, palette, params.paletteSize, false);
                    color = uchar4(uint8_t(blended.r * 255.0f),
                                    uint8_t(blended.g * 255.0f),
                                    uint8_t(blended.b * 255.0f),
                                    255);
                } else {
                    color = uchar4(0, 0, 0, 255);
                }
                break;
            default:
                color = uchar4(0, 0, 0, 255);
                break;
        }
        output[gid] = color;
    }
}

// =========================================================================
// Curtain Effect Kernel
// =========================================================================

// Helper: determine if pixel (x, y) should be lit for a horizontal curtain draw.
static bool curtain_horiz_pixel(int px, int py, bool leftEdge, int lim,
                                int bufferWi, int bufferHt,
                                device const int* swagArray, uint swagLen,
                                thread float& colorPos) {
    for (int i = 0; i < lim; i++) {
        int x = leftEdge ? (bufferWi - i - 1) : i;
        if (px == x) {
            colorPos = float(i) / float(bufferWi);
            return true;
        }
    }

    for (uint i = 0; i < swagLen; i++) {
        int colIdx = lim + int(i);
        int x = leftEdge ? (bufferWi - colIdx - 1) : colIdx;
        if (px == x) {
            colorPos = float(colIdx) / float(bufferWi);
            return (py > swagArray[i]);
        }
    }
    return false;
}

// Helper: determine if pixel (x, y) should be lit for a vertical curtain draw.
static bool curtain_vert_pixel(int px, int py, bool topEdge, int lim,
                               int bufferWi, int bufferHt,
                               device const int* swagArray, uint swagLen,
                               thread float& colorPos) {
    for (int i = 0; i < lim; i++) {
        int y = topEdge ? (bufferHt - i - 1) : i;
        if (py == y) {
            colorPos = float(i) / float(bufferHt);
            return true;
        }
    }

    for (uint i = 0; i < swagLen; i++) {
        int rowIdx = lim + int(i);
        int y = topEdge ? (bufferHt - rowIdx - 1) : rowIdx;
        if (py == y) {
            colorPos = float(rowIdx) / float(bufferHt);
            return (px > swagArray[i]);
        }
    }
    return false;
}

kernel void effectCurtain(
    device uchar4* output [[buffer(0)]],
    constant CurtainParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    device const int* swagArray [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    int px = int(gid % params.width);
    int py = int(gid / params.width);
    int bufW = int(params.width);
    int bufH = int(params.height);

    bool lit = false;
    float colorPos = 0.0;

    switch (params.edge) {
        case 0: {
            lit = curtain_horiz_pixel(px, py, true, params.xlimit,
                                      bufW, bufH, swagArray, params.swagLen, colorPos);
            break;
        }
        case 1: {
            int middle = (params.xlimit + 1) / 2;
            lit = curtain_horiz_pixel(px, py, true, middle,
                                      bufW, bufH, swagArray, params.swagLen, colorPos);
            if (!lit) {
                lit = curtain_horiz_pixel(px, py, false, middle,
                                          bufW, bufH, swagArray, params.swagLen, colorPos);
            }
            break;
        }
        case 2: {
            lit = curtain_horiz_pixel(px, py, false, params.xlimit,
                                      bufW, bufH, swagArray, params.swagLen, colorPos);
            break;
        }
        case 3: {
            lit = curtain_vert_pixel(px, py, true, params.ylimit,
                                     bufW, bufH, swagArray, params.swagLen, colorPos);
            break;
        }
        case 4: {
            int middle = (params.ylimit + 1) / 2;
            lit = curtain_vert_pixel(px, py, true, middle,
                                     bufW, bufH, swagArray, params.swagLen, colorPos);
            if (!lit) {
                lit = curtain_vert_pixel(px, py, false, middle,
                                          bufW, bufH, swagArray, params.swagLen, colorPos);
            }
            break;
        }
        case 5: {
            lit = curtain_vert_pixel(px, py, false, params.ylimit,
                                     bufW, bufH, swagArray, params.swagLen, colorPos);
            break;
        }
        default:
            break;
    }

    if (lit) {
        float4 color = get_multi_color_blend(colorPos, palette,
                                              params.paletteSize,
                                              params.circularPalette != 0);
        output[gid] = uchar4(uint8_t(color.r * 255.0),
                              uint8_t(color.g * 255.0),
                              uint8_t(color.b * 255.0),
                              255);
    } else {
        output[gid] = uchar4(0, 0, 0, 0);
    }
}

// =========================================================================
// Garlands Effect Kernel
// =========================================================================
// Each thread processes one (ring, x) pair from the garland loop.
// gid = ring * garlandWid + x

kernel void effectGarlands(
    device uchar4* output [[buffer(0)]],
    constant GarlandsParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    uint totalWork = params.buffMax * params.garlandWid;
    if (gid >= totalWork) return;

    uint ring = gid / params.garlandWid;
    uint x = gid % params.garlandWid;

    float ratio = float(params.buffMax - ring - 1) / float(params.buffMax);
    float4 color = get_multi_color_blend(ratio, palette, params.paletteSize,
                                          params.circularPalette != 0);

    int y = int(1.0 + float(ring) * params.pixelSpacing - params.positionOffset);

    int yadj = y;
    switch (params.garlandType) {
        case 1:
            switch (x % 5) {
                case 2: yadj -= 2; break;
                case 1:
                case 3: yadj -= 1; break;
            }
            break;
        case 2:
            switch (x % 5) {
                case 2: yadj -= 4; break;
                case 1:
                case 3: yadj -= 2; break;
            }
            break;
        case 3:
            switch (x % 6) {
                case 3: yadj -= 6; break;
                case 2:
                case 4: yadj -= 4; break;
                case 1:
                case 5: yadj -= 2; break;
            }
            break;
        case 4:
            switch (x % 5) {
                case 1:
                case 3: yadj -= 2; break;
            }
            break;
    }

    int ylimit = int(ring);
    if (yadj < ylimit) yadj = ylimit;
    if (yadj >= int(params.buffMax)) return;

    if (params.dir == 1 || params.dir == 2) {
        yadj = int(params.buffMax) - yadj - 1;
    }

    uint px, py;
    if (params.dir > 1) {
        px = uint(yadj);
        py = x;
    } else {
        px = x;
        py = uint(yadj);
    }

    if (px >= params.width || py >= params.height) return;

    uint idx = py * params.width + px;
    output[idx] = uchar4(uint8_t(color.r * 255.0),
                          uint8_t(color.g * 255.0),
                          uint8_t(color.b * 255.0),
                          255);
}

// =========================================================================
// Marquee Effect Kernel
// =========================================================================

kernel void effectMarquee(
    device uchar4* output [[buffer(0)]],
    constant MarqueeParams& p [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= p.totalPixels) return;

    int px = int(gid % p.width);
    int py = int(gid / p.width);

    int mx = px - p.xoffset_adj;
    int my = py - p.yoffset_adj;

    int colorSize = p.bandSize + p.skipSize;
    int repeatSize = colorSize * int(p.paletteSize);

    output[gid] = uchar4(0, 0, 0, 0);

    for (int thick = 0; thick < p.thickness; thick++) {
        int cx1 = p.corner_x1 + thick;
        int cy1 = p.corner_y1 + thick;
        int cx2 = p.corner_x2 - thick;
        int cy2 = p.corner_y2 - thick;

        if (cx1 > cx2 || cy1 > cy2) continue;

        int perimPos = -1;
        bool isOnRing = false;

        int topLen = cx2 - cx1 + 1;
        int rightLen = cy2 - cy1 + 1;
        int bottomLen = cx2 - cx1 + 1;
        if (cy2 != cy1) {
            if (my == cy2 && mx >= cx1 && mx <= cx2) {
                perimPos = mx - cx1;
                isOnRing = true;
            }
            else if (mx == cx2 && my >= cy1 && my <= cy2) {
                perimPos = topLen + (cy2 - my);
                isOnRing = true;
            }
            else if (my == cy1 && mx >= cx1 && mx <= cx2) {
                perimPos = topLen + rightLen + (cx2 - mx);
                isOnRing = true;
            }
            else if (mx == cx1 && my >= cy1 && my <= cy2 - 1) {
                perimPos = topLen + rightLen + bottomLen + (my - cy1);
                isOnRing = true;
            }
        } else {
            if (my == cy1 && mx >= cx1 && mx <= cx2) {
                perimPos = cx2 - mx;
                isOnRing = true;
            }
        }

        if (!isOnRing) continue;

        int baseAdvance = p.effPos + p.startOffset;

        int edgeOffset = 0;
        int posInEdge = 0;

        if (cy2 != cy1) {
            if (my == cy2 && mx >= cx1 && mx <= cx2) {
                edgeOffset = thick * (p.stagger + 1) * p.sign;
                posInEdge = (mx - cx1) * p.sign;
            } else if (mx == cx2 && my >= cy1 && my <= cy2) {
                edgeOffset = thick * (p.stagger + 1) * p.sign
                           + topLen * p.sign
                           + thick * 2 * p.sign;
                posInEdge = (cy2 - my) * p.sign;
            } else if (my == cy1 && mx >= cx1 && mx <= cx2) {
                edgeOffset = thick * (p.stagger + 1) * p.sign
                           + topLen * p.sign
                           + thick * 2 * p.sign
                           + rightLen * p.sign
                           + thick * 2 * p.sign;
                posInEdge = (cx2 - mx) * p.sign;
            } else if (mx == cx1 && my >= cy1 && my <= cy2 - 1) {
                edgeOffset = thick * (p.stagger + 1) * p.sign
                           + topLen * p.sign
                           + thick * 2 * p.sign
                           + rightLen * p.sign
                           + thick * 2 * p.sign
                           + bottomLen * p.sign
                           + thick * 2 * p.sign;
                posInEdge = (my - cy1) * p.sign;
            }
        } else {
            edgeOffset = thick * 2 * p.sign;
            posInEdge = (cx2 - mx) * p.sign;
        }

        int totalAdvance = baseAdvance + edgeOffset + posInEdge;

        if (repeatSize <= 0) continue;

        int normAdv = totalAdvance % repeatSize;
        if (normAdv < 0) normAdv += repeatSize;

        int currentColor = normAdv / colorSize;
        int currentPos = normAdv % colorSize;

        if (p.sign < 0) {
            int baseNorm = (p.effPos + p.startOffset) % repeatSize;
            if (baseNorm < 0) baseNorm += repeatSize;
            int baseColor = baseNorm / colorSize;
            int basePos = baseNorm % colorSize;

            baseColor = int(p.paletteSize) - 1 - baseColor;

            int steps = edgeOffset + posInEdge;

            if (steps >= 0) {
                basePos += steps;
                baseColor += basePos / colorSize;
                basePos = basePos % colorSize;
                baseColor = baseColor % int(p.paletteSize);
            } else {
                int absSteps = -steps;
                for (int s = 0; s < absSteps && s < 10000; s++) {
                    basePos--;
                    if (basePos < 0) {
                        baseColor++;
                        baseColor %= int(p.paletteSize);
                        basePos = colorSize - 1;
                    }
                }
            }
            if (baseColor < 0) baseColor += int(p.paletteSize);
            currentColor = baseColor % int(p.paletteSize);
            currentPos = basePos;
        }

        if (currentPos >= p.bandSize) {
            continue;
        }

        if (currentColor < 0) currentColor += int(p.paletteSize);
        currentColor = currentColor % int(p.paletteSize);

        float4 color = palette[currentColor];
        output[gid] = uchar4(uint8_t(color.r * 255.0),
                              uint8_t(color.g * 255.0),
                              uint8_t(color.b * 255.0),
                              255);
        return;
    }
}

// =========================================================================
// SingleStrand Effect Kernel
// =========================================================================

// Compute chase color for pixel index i within a chase of max_chase_width pixels.
static float4 compute_chase_pixel(int i, int max_chase_width, int pixels_per_chase,
                                  uint colorScheme, uint fadeType,
                                  float origV, uint paletteSize,
                                  device const float4* palette) {
    if (i < 0 || i >= max_chase_width || i >= pixels_per_chase) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    float4 color;
    if (colorScheme == 0) {
        float hue = 1.0 - (float(i) / float(max(max_chase_width, 1)));
        float3 rgb = hsv_to_rgb(float3(hue, 1.0, origV));
        color = float4(rgb, 1.0);
    } else {
        int cidx;
        if (paletteSize <= 1) {
            cidx = 0;
        } else {
            cidx = int(ceil(float((max_chase_width - i) * int(paletteSize)) /
                            float(max_chase_width))) - 1;
        }
        if (cidx >= int(paletteSize)) cidx = int(paletteSize) - 1;
        if (cidx < 0) cidx = 0;
        color = palette[cidx];
    }

    int middle_chase_index = (max_chase_width % 2 == 0) ?
                             (max_chase_width / 2 - 1) : (max_chase_width / 2);

    if (fadeType == 1) {
        float3 hsv = rgb_to_hsv(color.rgb);
        hsv.z = origV - ((float(max_chase_width) - float(i + 1)) / float(max_chase_width));
        hsv.z = max(hsv.z, 0.0f);
        color = float4(hsv_to_rgb(hsv), 1.0);
    } else if (fadeType == 2) {
        float3 hsv = rgb_to_hsv(color.rgb);
        hsv.z = (float(max_chase_width) - float(i + 1)) / float(max_chase_width);
        hsv.z = max(hsv.z, 0.0f);
        color = float4(hsv_to_rgb(hsv), 1.0);
    } else if (fadeType == 3) {
        float3 hsv = rgb_to_hsv(color.rgb);
        if (i <= middle_chase_index) {
            hsv.z = origV * (1.0 - (2.0 * float(i)) / float(max_chase_width));
        } else {
            hsv.z = origV * ((2.0 * float(i - middle_chase_index)) / float(max_chase_width));
        }
        hsv.z = clamp(hsv.z, 0.0f, origV);
        color = float4(hsv_to_rgb(hsv), 1.0);
    } else if (fadeType == 4) {
        float3 hsv = rgb_to_hsv(color.rgb);
        if (i > middle_chase_index) {
            hsv.z = (float(max_chase_width) - float(i + 1)) / (0.5 * float(max_chase_width));
        } else {
            hsv.z = origV - ((float(max_chase_width) - (2.0 * float(i) + 1.0)) / float(max_chase_width));
        }
        hsv.z = max(hsv.z, 0.0f);
        color = float4(hsv_to_rgb(hsv), 1.0);
    }

    return color;
}

kernel void effectSingleStrand(
    device uchar4* output [[buffer(0)]],
    constant SingleStrandParams& params [[buffer(1)]],
    device const float4* palette [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= params.totalPixels) return;

    uint px = gid % params.bufferWi;
    uint py = gid / params.bufferWi;

    if (params.subType == 0) {
        // =================================================================
        // Skips sub-effect
        // =================================================================
        int max = int(params.bufferWi);
        int dir = int(params.direction);
        if (dir > 1) {
            max = (max + 1) / 2;
        }

        int colorcnt = int(params.paletteSize);
        int groupSize = (params.bandSize + params.skipSize) * colorcnt;
        if (groupSize < 1) groupSize = 1;

        int baseX = params.startPos - 1 + int(params.skipsPosition) * params.bandSize;
        while (baseX > max) {
            baseX -= groupSize;
        }

        int physX = int(px);
        int logicalX = -1;

        if (dir == 0) {
            logicalX = physX;
        } else if (dir == 1) {
            logicalX = max - physX - 1;
        } else if (dir == 2) {
            if (physX < max) {
                logicalX = max - physX - 1;
            } else {
                logicalX = physX - max;
            }
        } else if (dir == 3) {
            if (physX < max) {
                logicalX = physX;
            } else {
                logicalX = max * 2 - physX - 1;
            }
        }

        float4 pixelColor = float4(0.0, 0.0, 0.0, 0.0);
        bool found = false;

        if (logicalX >= 0 && logicalX < max) {
            int bandUnit = params.bandSize + params.skipSize;
            if (bandUnit < 1) bandUnit = 1;

            int rel = logicalX - baseX;

            if (rel >= 0) {
                int unitIdx = rel / bandUnit;
                int posInUnit = rel % bandUnit;
                if (posInUnit < params.bandSize) {
                    int colorIdx = unitIdx % colorcnt;
                    pixelColor = palette[colorIdx];
                    found = true;
                }
            } else {
                int absRel = -rel - 1;
                int unitIdx = absRel / bandUnit;
                int posInUnit = absRel % bandUnit;
                if (posInUnit >= params.skipSize) {
                    int colorIdx = (colorcnt - 1) - (unitIdx % colorcnt);
                    if (colorIdx < 0) colorIdx += colorcnt;
                    pixelColor = palette[colorIdx];
                    found = true;
                }
            }
        }

        if (found) {
            output[gid] = uchar4(uint8_t(pixelColor.r * 255.0),
                                  uint8_t(pixelColor.g * 255.0),
                                  uint8_t(pixelColor.b * 255.0),
                                  255);
        } else {
            output[gid] = uchar4(0, 0, 0, 0);
        }

    } else if (params.subType == 1) {
        // =================================================================
        // Chase sub-effect
        // =================================================================
        int chaseW = params.chaseWidth;
        int mcw = params.scaledChaseWidth;
        if (mcw < 1) mcw = 1;
        int numChases = params.numberChases;
        if (numChases < 1) numChases = 1;
        int ppChase = chaseW / numChases;
        if (ppChase < 1) ppChase = 1;

        int pixelIdx;
        if (params.groupAll != 0) {
            pixelIdx = int(py) * int(params.bufferWi) + int(px);
        } else {
            pixelIdx = int(px);
        }

        float4 bestColor = float4(0.0, 0.0, 0.0, 0.0);

        for (int chase = 0; chase < numChases; chase++) {
            int x_arg;
            if (params.autoReverse != 0) {
                x_arg = int(float(chase) * params.dx + float(chaseW) * params.rtval - float(mcw) / 2.0);
            } else {
                x_arg = int(float(chase) * params.dx + float(params.startState) - float(mcw));
            }

            for (int dualPass = 0; dualPass < (params.dualChases != 0 ? 2 : 1); dualPass++) {
                int cur_x_arg;
                int curChaseDir;

                if (dualPass == 0) {
                    cur_x_arg = (params.doubleEnd != 0) ?
                        chaseW - x_arg - 1 * mcw : x_arg;
                    curChaseDir = (int(params.chaseDirection) != int(params.doubleEnd)) ? 1 : 0;
                } else {
                    cur_x_arg = (params.doubleEnd != 0) ?
                        x_arg - 1 * mcw : x_arg;
                    curChaseDir = (int(params.chaseDirection) == int(params.doubleEnd)) ? 1 : 0;
                }

                int firstX = cur_x_arg;
                int drawDirection = 1;

                if (params.autoReverse != 0) {
                    if (firstX < 0 && firstX > -mcw) {
                        firstX = -firstX - 1;
                        drawDirection = -1;
                    }
                    if (firstX < 0 || firstX >= chaseW) {
                        int dif;
                        if (firstX < 0) {
                            firstX = -firstX - 1;
                            drawDirection = -1;
                            dif = 0;
                        } else {
                            dif = firstX - chaseW + 1;
                            firstX = chaseW;
                            drawDirection = -1;
                        }
                        while (dif > 0) {
                            dif--;
                            firstX += drawDirection;
                            if (firstX == chaseW - 1) drawDirection = -1;
                            if (firstX == 0) drawDirection = 1;
                        }
                    }
                }

                int walkX = firstX;
                for (int i = 0; i < mcw; i++) {
                    int new_x;
                    if (params.autoReverse != 0) {
                        new_x = walkX + drawDirection;
                        while (new_x < 0) { drawDirection = 1; new_x = 0; }
                        while (new_x >= chaseW) { drawDirection = -1; new_x = chaseW - 1; }
                        walkX = new_x;
                    } else if (numChases > 1) {
                        new_x = cur_x_arg + i;
                        while (new_x < 0) new_x += chaseW;
                        while (new_x >= chaseW) new_x -= chaseW;
                    } else {
                        new_x = cur_x_arg + i;
                    }

                    if (i >= ppChase) continue;

                    if (curChaseDir == 0) {
                        new_x = chaseW - new_x - 1;
                    }

                    if (new_x < 0 || new_x > chaseW) continue;

                    bool matches = false;
                    bool mirrorMatches = false;

                    if (params.groupAll != 0) {
                        if (new_x == pixelIdx) matches = true;
                        int mirrorIdx = int(params.bufferWi) * int(params.bufferHt) - new_x - 1;
                        if (params.mirror != 0 && mirrorIdx == pixelIdx) mirrorMatches = true;
                    } else {
                        if (new_x == pixelIdx) matches = true;
                        int mirrorNewX = int(params.bufferWi) - new_x - 1;
                        if (params.mirror != 0 && mirrorNewX == pixelIdx) mirrorMatches = true;
                    }

                    if (matches || mirrorMatches) {
                        float4 chaseColor = compute_chase_pixel(
                            i, mcw, ppChase,
                            params.colorScheme, params.fadeType,
                            params.origV, params.paletteSize, palette);

                        if (params.fadeType != 0) {
                            bestColor = max(bestColor, chaseColor);
                        } else {
                            bestColor = chaseColor;
                        }
                    }
                }
            }
        }

        output[gid] = uchar4(uint8_t(bestColor.r * 255.0),
                              uint8_t(bestColor.g * 255.0),
                              uint8_t(bestColor.b * 255.0),
                              bestColor.r + bestColor.g + bestColor.b > 0.0 ? 255 : 0);
    }
}
