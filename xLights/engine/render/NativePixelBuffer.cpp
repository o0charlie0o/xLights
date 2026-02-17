/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// NativePixelBuffer: Layer blending orchestrator for the native macOS render
// pipeline. Blends multiple effect layers per model, applying per-layer
// adjustments (blur, sparkle, HSV, brightness/contrast) and producing final
// output channel data.
//
// The blending logic mirrors PixelBuffer.cpp CalcOutput() / GetMixedColor()
// from the legacy build, but uses NativeColorBlending for all mix operations
// and has zero wxWidgets dependencies.

#include "NativePixelBuffer.h"
#include "../../DissolveTransitionPattern.h"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstring>
#include <numeric>
#include <random>

namespace xlEngine {

// =========================================================================
// Anonymous helpers — Gaussian blur (ported from PixelBuffer.cpp)
// =========================================================================

namespace {

// Box sizes for Gaussian blur approximation.
// http://blog.ivank.net/fastest-gaussian-blur.html
static void boxesForGauss(int d, std::vector<float>& boxes) {
    switch (d) {
    case 2: case 3:
        boxes.push_back(1.0f); break;
    case 4: case 5: case 6:
        boxes.push_back(3.0f); break;
    case 7: case 8: case 9:
        boxes.push_back(5.0f); break;
    case 10: case 11: case 12:
        boxes.push_back(7.0f); break;
    case 13: case 14: case 15:
        boxes.push_back(9.0f); break;
    default:
        break;
    }
    float b = boxes.back();
    switch (d) {
    case 2: case 4: case 5: case 7: case 8: case 10: case 11: case 13: case 14:
        boxes.push_back(b); break;
    default:
        boxes.push_back(b + 2.0f); break;
    }
    switch (d) {
    case 4: case 7: case 10: case 13:
        boxes.push_back(b); break;
    default:
        boxes.push_back(b + 2.0f);
    }
}

#define RED(a, b)   a[(b) * 4]
#define GREEN(a, b) a[(b) * 4 + 1]
#define BLUE(a, b)  a[(b) * 4 + 2]
#define ALPHA(a, b) a[(b) * 4 + 3]

static inline void SET(std::vector<float>& ar, int idx, float r, float g, float b, float a) {
    idx *= 4;
    ar[idx]     = r;
    ar[idx + 1] = g;
    ar[idx + 2] = b;
    ar[idx + 3] = a;
}

static void boxBlurH_4(const std::vector<float>& scl, std::vector<float>& tcl, int w, int h, float r) {
    float iarr = 1.0f / (r + r + 1.0f);
    for (int i = 0; i < h; i++) {
        int ti = i * w;
        int li = ti;
        int ri = ti + (int)r;
        int maxri = ti + w - 1;
        int fvIdx = ti;
        int lvIdx = ti + w - 1;

        float valr = (r + 1.0f) * RED(scl, fvIdx);
        float valg = (r + 1.0f) * GREEN(scl, fvIdx);
        float valb = (r + 1.0f) * BLUE(scl, fvIdx);
        float vala = (r + 1.0f) * ALPHA(scl, fvIdx);

        float fvRed = RED(scl, fvIdx);
        float fvGreen = GREEN(scl, fvIdx);
        float fvBlue = BLUE(scl, fvIdx);
        float fvAlpha = ALPHA(scl, fvIdx);
        float lvRed = RED(scl, lvIdx);
        float lvGreen = GREEN(scl, lvIdx);
        float lvBlue = BLUE(scl, lvIdx);
        float lvAlpha = ALPHA(scl, lvIdx);

        for (int j = 0; j < (int)r; j++) {
            int idx = j < w ? ti + j : lvIdx;
            valr += RED(scl, idx);
            valg += GREEN(scl, idx);
            valb += BLUE(scl, idx);
            vala += ALPHA(scl, idx);
        }
        for (int j = 0; j <= (int)r; j++) {
            int idx = ri <= maxri ? ri++ : lvIdx;
            valr += RED(scl, idx) - fvRed;
            valg += GREEN(scl, idx) - fvGreen;
            valb += BLUE(scl, idx) - fvBlue;
            vala += ALPHA(scl, idx) - fvAlpha;
            if (ti <= maxri) {
                SET(tcl, ti, valr * iarr, valg * iarr, valb * iarr, vala * iarr);
                ti++;
            }
        }
        for (int j = (int)r + 1; j < w - (int)r; j++) {
            int c = ri <= maxri ? ri++ : lvIdx;
            int c2 = li <= maxri ? li++ : lvIdx;
            valr += RED(scl, c) - RED(scl, c2);
            valg += GREEN(scl, c) - GREEN(scl, c2);
            valb += BLUE(scl, c) - BLUE(scl, c2);
            vala += ALPHA(scl, c) - ALPHA(scl, c2);
            if (ti <= maxri) {
                SET(tcl, ti, valr * iarr, valg * iarr, valb * iarr, vala * iarr);
                ti++;
            }
        }
        for (int j = w - (int)r; j < w; j++) {
            int c2 = li <= maxri ? li++ : lvIdx;
            valr += lvRed - RED(scl, c2);
            valg += lvGreen - GREEN(scl, c2);
            valb += lvBlue - BLUE(scl, c2);
            vala += lvAlpha - ALPHA(scl, c2);
            if (ti <= maxri) {
                SET(tcl, ti, valr * iarr, valg * iarr, valb * iarr, vala * iarr);
                ti++;
            }
        }
    }
}

static void boxBlurT_4(const std::vector<float>& scl, std::vector<float>& tcl, int w, int h, float r) {
    float iarr = 1.0f / (r + r + 1.0f);
    for (int i = 0; i < w; i++) {
        int ti = i;
        int li = ti;
        int ri = ti + (int)r * w;
        int maxri = ti + w * (h - 1);
        int fvIdx = ti;
        int lvIdx = ti + w * (h - 1);

        float fvRed = RED(scl, fvIdx);
        float fvGreen = GREEN(scl, fvIdx);
        float fvBlue = BLUE(scl, fvIdx);
        float fvAlpha = ALPHA(scl, fvIdx);
        float lvRed = RED(scl, lvIdx);
        float lvGreen = GREEN(scl, lvIdx);
        float lvBlue = BLUE(scl, lvIdx);
        float lvAlpha = ALPHA(scl, lvIdx);

        float valr = (r + 1) * fvRed;
        float valg = (r + 1) * fvGreen;
        float valb = (r + 1) * fvBlue;
        float vala = (r + 1) * fvAlpha;

        for (int j = 0; j < (int)r; j++) {
            int idx = j < w ? ti + j * w : lvIdx;
            valr += RED(scl, idx);
            valg += GREEN(scl, idx);
            valb += BLUE(scl, idx);
            vala += ALPHA(scl, idx);
        }
        for (int j = 0; j <= (int)r; j++) {
            int idx = ri <= maxri ? ri : lvIdx;
            valr += RED(scl, idx) - fvRed;
            valg += GREEN(scl, idx) - fvGreen;
            valb += BLUE(scl, idx) - fvBlue;
            vala += ALPHA(scl, idx) - fvAlpha;
            if (ti <= maxri) {
                SET(tcl, ti, valr * iarr, valg * iarr, valb * iarr, vala * iarr);
            }
            ri += w;
            ti += w;
        }
        for (int j = (int)r + 1; j < h - (int)r; j++) {
            int c = ri <= maxri ? ri : lvIdx;
            int c2 = li <= maxri ? li : lvIdx;
            valr += RED(scl, c) - RED(scl, c2);
            valg += GREEN(scl, c) - GREEN(scl, c2);
            valb += BLUE(scl, c) - BLUE(scl, c2);
            vala += ALPHA(scl, c) - ALPHA(scl, c2);
            if (ti <= maxri) {
                SET(tcl, ti, valr * iarr, valg * iarr, valb * iarr, vala * iarr);
            }
            li += w;
            ri += w;
            ti += w;
        }
        for (int j = h - (int)r; j < h; j++) {
            int c2 = li <= maxri ? li : lvIdx;
            valr += lvRed - RED(scl, c2);
            valg += lvGreen - GREEN(scl, c2);
            valb += lvBlue - BLUE(scl, c2);
            vala += lvAlpha - ALPHA(scl, c2);
            if (ti <= maxri) {
                SET(tcl, ti, valr * iarr, valg * iarr, valb * iarr, vala * iarr);
            }
            li += w;
            ti += w;
        }
    }
}

static void boxBlur_4(std::vector<float>& scl, std::vector<float>& tcl, int w, int h, float r, int /*size*/) {
    tcl = scl;
    boxBlurH_4(tcl, scl, w, h, r);
    boxBlurT_4(scl, tcl, w, h, r);
}

static void gaussBlur_4(std::vector<float>& scl, std::vector<float>& tcl, int w, int h, int r, int size) {
    std::vector<float> bxs;
    boxesForGauss(r - 1, bxs);
    boxBlur_4(scl, tcl, w, h, (bxs[0] - 1) / 2, size);
    boxBlur_4(tcl, scl, w, h, (bxs[1] - 1) / 2, size);
    boxBlur_4(scl, tcl, w, h, (bxs[2] - 1) / 2, size);
}

static inline int roundInt(float r) {
    int tmp = static_cast<int>(r);
    tmp += (r - tmp >= .5f) - (r - tmp <= -.5f);
    return tmp;
}

} // anonymous namespace

#undef RED
#undef GREEN
#undef BLUE
#undef ALPHA

// =========================================================================
// Construction / Destruction
// =========================================================================

NativePixelBuffer::NativePixelBuffer(IRenderContext* context, int bufferWi, int bufferHt,
                                     int numLayers, const std::vector<NativeNodeInfo>& nodes)
    : _context(context)
    , _bufferWi(bufferWi)
    , _bufferHt(bufferHt)
    , _nodes(nodes)
{
    assert(numLayers > 0);
    assert(bufferWi > 0 && bufferHt > 0);

    _layers.reserve(numLayers);
    for (int i = 0; i < numLayers; ++i) {
        _layers.emplace_back(context, bufferWi, bufferHt);
    }

    _outputPixels.resize(static_cast<size_t>(bufferWi) * bufferHt, xlBLACK);

    // Build sorted unique pixel indices for node positions.
    // Used by calcOutput() in batch mode to skip non-node pixels.
    {
        std::set<int> uniqueIndices;
        for (const auto& node : _nodes) {
            if (node.bufX >= 0 && node.bufX < bufferWi &&
                node.bufY >= 0 && node.bufY < bufferHt) {
                uniqueIndices.insert(node.bufY * bufferWi + node.bufX);
            }
        }
        _nodePixelIndices.assign(uniqueIndices.begin(), uniqueIndices.end());
    }
}

NativePixelBuffer::~NativePixelBuffer() = default;

// =========================================================================
// Layer access
// =========================================================================

NativeRenderBuffer& NativePixelBuffer::getLayerBuffer(int layer) {
    assert(layer >= 0 && layer < static_cast<int>(_layers.size()));
    return _layers[layer].buffer;
}

const NativeRenderBuffer& NativePixelBuffer::getLayerBuffer(int layer) const {
    assert(layer >= 0 && layer < static_cast<int>(_layers.size()));
    return _layers[layer].buffer;
}

int NativePixelBuffer::getLayerCount() const {
    return static_cast<int>(_layers.size());
}

// =========================================================================
// Layer settings
// =========================================================================

void NativePixelBuffer::setLayerSettings(int layer, const NativeLayerInfo& settings) {
    assert(layer >= 0 && layer < static_cast<int>(_layers.size()));
    _layers[layer].settings = settings;
}

void NativePixelBuffer::setMixType(int layer, NativeMixType type) {
    assert(layer >= 0 && layer < static_cast<int>(_layers.size()));
    _layers[layer].settings.mixType = type;
}

bool NativePixelBuffer::isCanvasMix(int layer) const {
    assert(layer >= 0 && layer < static_cast<int>(_layers.size()));
    return _layers[layer].settings.canvas;
}

// =========================================================================
// Blur
// =========================================================================

void NativePixelBuffer::applyBlur(LayerState& layer) {
    int b = layer.settings.blur;
    if (b < 2) return;
    if (_bufferWi == 1 && _bufferHt == 1) return;

    if (b > 2 && _bufferWi > 6 && _bufferHt > 6) {
        // Large blur: use Gaussian approximation (3-pass box blur)
        int pixCount = _bufferWi * _bufferHt;
        std::vector<float> input(pixCount * 4);
        std::vector<float> tmp(pixCount * 4);

        const xlColor* pixels = layer.buffer.GetPixels();
        for (int x = 0; x < pixCount; x++) {
            const xlColor& c = pixels[x];
            input[x * 4]     = c.red;
            input[x * 4 + 1] = c.green;
            input[x * 4 + 2] = c.blue;
            input[x * 4 + 3] = c.alpha;
        }
        gaussBlur_4(input, tmp, _bufferWi, _bufferHt, b, pixCount);

        xlColor* outPixels = layer.buffer.GetPixels();
        for (int x = 0; x < pixCount; x++) {
            outPixels[x].Set(
                roundInt(tmp[x * 4]),
                roundInt(tmp[x * 4 + 1]),
                roundInt(tmp[x * 4 + 2]),
                roundInt(tmp[x * 4 + 3]));
        }
    } else {
        // Small blur: simple box blur
        int d, u;
        if (b % 2 == 0) {
            d = b / 2;
            u = (b - 1) / 2;
        } else {
            d = (b - 1) / 2;
            u = (b - 1) / 2;
        }

        // Make a snapshot of the current buffer
        NativeRenderBuffer orig(layer.buffer);

        for (int x = 0; x < _bufferWi; x++) {
            for (int y = 0; y < _bufferHt; y++) {
                int r = 0, g = 0, b2 = 0, a = 0;
                int sm = 0;
                for (int i = x - d; i <= x + u; i++) {
                    if (i >= 0 && i < _bufferWi) {
                        for (int j = y - d; j <= y + u; j++) {
                            if (j >= 0 && j < _bufferHt) {
                                const xlColor& c = orig.GetPixel(i, j);
                                r += c.red;
                                g += c.green;
                                b2 += c.blue;
                                a += c.alpha;
                                ++sm;
                            }
                        }
                    }
                }
                if (sm == 0) sm = 1;
                layer.buffer.SetPixel(x, y, xlColor(r / sm, g / sm, b2 / sm, a / sm));
            }
        }
    }
}

// =========================================================================
// Sparkle
// =========================================================================

void NativePixelBuffer::applySparkle(xlColor& color, int nodeIndex, int sparkleCount,
                                     const xlColor& sparkleColour) const {
    if (sparkleCount <= 0) return;
    if (color == xlBLACK) return;

    // Use sparkle state for this node to decide whether to sparkle
    if (nodeIndex >= 0 && nodeIndex < static_cast<int>(_sparkleState.size())) {
        // Sparkle probability: sparkleCount out of 200 frames show a sparkle
        if ((_sparkleState[nodeIndex] % 200) < static_cast<uint16_t>(sparkleCount)) {
            color = sparkleColour;
        }
    }
}

// =========================================================================
// Transition mask generation (ported from PixelBuffer.cpp)
// =========================================================================

static bool isLeftOf(int ax, int ay, int bx, int by, int tx, int ty) {
    return ((bx - ax) * (ty - ay) - (by - ay) * (tx - ax)) > 0;
}

static bool isMaskBasedTransition(NativeTransitionType t) {
    switch (t) {
    case NativeTransitionType::Wipe:
    case NativeTransitionType::Clock:
    case NativeTransitionType::FromMiddle:
    case NativeTransitionType::SquareExplode:
    case NativeTransitionType::CircleExplode:
    case NativeTransitionType::Blinds:
    case NativeTransitionType::Blend:
    case NativeTransitionType::SlideChecks:
    case NativeTransitionType::SlideBars:
        return true;
    default:
        return false;
    }
}

void NativePixelBuffer::applyTransitions(LayerState& layer) {
    const NativeLayerInfo& s = layer.settings;

    bool hasInNonFade = (s.inMaskFactor < 1.0f &&
                         s.inTransitionType != NativeTransitionType::Fade);
    bool hasOutNonFade = (s.outMaskFactor < 1.0f &&
                          s.outTransitionType != NativeTransitionType::Fade);

    if (!hasInNonFade && !hasOutNonFade) {
        layer.maskSize = 0;
        return;
    }

    int bufW = _bufferWi;
    int bufH = _bufferHt;

    // Dissolve: modify buffer pixels directly using the dissolve pattern texture
    if (hasInNonFade && s.inTransitionType == NativeTransitionType::Dissolve) {
        float progress = s.inMaskFactor;
        auto byteProgress = static_cast<uint8_t>(255.0f * progress);
        for (int y = 0; y < bufH; ++y) {
            float t = (bufH > 1) ? static_cast<float>(y) / (bufH - 1) : 0.0f;
            for (int x = 0; x < bufW; ++x) {
                float sv = (bufW > 1) ? static_cast<float>(x) / (bufW - 1) : 0.0f;
                int px = static_cast<int>(sv * (DissolvePatternWidth - 1));
                int py = static_cast<int>(t * (DissolvePatternHeight - 1));
                uint8_t dv = DissolveTransitonPattern[py * DissolvePatternWidth + px];
                if (dv > byteProgress) {
                    layer.buffer.SetPixel(x, y, xlBLACK);
                }
            }
        }
    }
    if (hasOutNonFade && s.outTransitionType == NativeTransitionType::Dissolve) {
        float progress = 1.0f - s.outMaskFactor;
        auto byteProgress = static_cast<uint8_t>(255.0f * progress);
        for (int y = 0; y < bufH; ++y) {
            float t = (bufH > 1) ? static_cast<float>(y) / (bufH - 1) : 0.0f;
            for (int x = 0; x < bufW; ++x) {
                float sv = (bufW > 1) ? static_cast<float>(x) / (bufW - 1) : 0.0f;
                int px = static_cast<int>(sv * (DissolvePatternWidth - 1));
                int py = static_cast<int>(t * (DissolvePatternHeight - 1));
                uint8_t dv = DissolveTransitonPattern[py * DissolvePatternWidth + px];
                if (dv > byteProgress) {
                    layer.buffer.SetPixel(x, y, xlBLACK);
                }
            }
        }
    }

    // Mask-based transitions
    bool needInMask = hasInNonFade && isMaskBasedTransition(s.inTransitionType);
    bool needOutMask = hasOutNonFade && isMaskBasedTransition(s.outTransitionType);

    if (!needInMask && !needOutMask) {
        layer.maskSize = 0;
        return;
    }

    int maskRequired = bufW * bufH;
    if (static_cast<int>(layer.transitionMask.size()) < maskRequired) {
        layer.transitionMask.resize(maskRequired);
    }
    layer.maskSize = maskRequired;
    std::memset(layer.transitionMask.data(), 0, maskRequired);

    auto buildMask = [&](bool out) {
        NativeTransitionType type = out ? s.outTransitionType : s.inTransitionType;
        float factor = out ? s.outMaskFactor : s.inMaskFactor;
        int adjust = static_cast<int>(out ? s.outTransitionAdjust : s.inTransitionAdjust);
        bool reverse = out ? s.outTransitionReverse : s.inTransitionReverse;

        if (!isMaskBasedTransition(type)) return;

        uint8_t* mask = layer.transitionMask.data();

        switch (type) {
        case NativeTransitionType::Wipe: {
            if (reverse) {
                adjust += 50;
                if (adjust >= 100) adjust -= 100;
            }
            float angle = 2.0f * static_cast<float>(M_PI) * adjust / 100.0f;
            float slope = std::tan(angle);
            uint8_t m1 = 255, m2 = 0;
            float curx = std::round(factor * (static_cast<float>(bufW) - 1.0f));
            float cury = std::round(factor * (static_cast<float>(bufH) - 1.0f));
            if (angle >= 0 && angle < static_cast<float>(M_PI_2)) {
                curx = bufW - curx - 1; std::swap(m1, m2);
            } else if (angle >= static_cast<float>(M_PI_2) && angle < static_cast<float>(M_PI)) {
                curx = bufW - curx - 1; cury = bufH - cury - 1;
            } else if (angle >= static_cast<float>(M_PI) && angle < static_cast<float>(M_PI + M_PI_2)) {
                cury = bufH - cury - 1;
            } else {
                std::swap(m1, m2);
            }
            float endx = (curx == -1) ? -5.0f : -1.0f;
            float endy = slope * (endx - curx) + cury;
            if (slope > 999.0f) { endx = curx; endy = cury - 10; }
            else if (slope < -999.0f) { endx = curx; endy = cury + 10; }
            int sx = static_cast<int>(curx), sy = static_cast<int>(cury);
            int ex = static_cast<int>(endx), ey = static_cast<int>(endy);
            for (int x = 0; x < bufW; ++x)
                for (int y = 0; y < bufH; ++y)
                    mask[x * bufH + y] = std::max(mask[x * bufH + y],
                        isLeftOf(sx, sy, ex, ey, x, y) ? m1 : m2);
            break;
        }
        case NativeTransitionType::Clock: {
            float sr = 2.0f * static_cast<float>(M_PI) * adjust / 100.0f;
            float cr = 2.0f * static_cast<float>(M_PI) * factor;
            if (reverse) {
                float tmp = sr; sr = sr - cr; cr = tmp;
                if (sr < 0) { sr += 2.0f * static_cast<float>(M_PI); cr += 2.0f * static_cast<float>(M_PI); }
            } else { cr = sr + cr; }
            for (int x = 0; x < bufW; ++x) {
                for (int y = 0; y < bufH; ++y) {
                    float rpx = (x - bufW/2 == 0 && y - bufH/2 == 0) ? 0.0f
                        : std::atan2(static_cast<float>(x - bufW/2), static_cast<float>(y - bufH/2));
                    if (rpx < 0) rpx += 2.0f * static_cast<float>(M_PI);
                    if (cr > 2.0f * static_cast<float>(M_PI) && rpx < sr) rpx += 2.0f * static_cast<float>(M_PI);
                    uint8_t val = (rpx > sr && rpx < cr) ? uint8_t(0) : uint8_t(255);
                    mask[x * bufH + y] = std::max(mask[x * bufH + y], val);
                }
            }
            break;
        }
        case NativeTransitionType::FromMiddle: {
            uint8_t m1 = 255, m2 = 0; float f = factor;
            if (reverse) { f = 1.0f - f; m1 = 0; m2 = 255; }
            double w2 = 0.5 * bufW, h2 = 0.5 * bufH;
            double a2 = (0.01 * adjust) * M_PI - M_PI_2;
            double cosA = std::cos(a2), sinA = std::sin(a2);
            double p1x = w2 + (-h2)*sinA, p1y = h2 + h2*cosA;
            double p2x = w2 + (500.0-h2)*sinA, p2y = h2 + (h2-500.0)*cosA;
            double plen = std::sqrt((p2x-p1x)*(p2x-p1x) + (p2y-p1y)*(p2y-p1y));
            if (plen < 0.001) plen = 0.001;
            double dy = p2y-p1y, dx = p2x-p1x, off = p2x*p1y - p2y*p1x;
            double dBR = std::abs(dy*(bufW-1)+off)/plen;
            double dUR = std::abs(dy*(bufW-1)-dx*(bufH-1)+off)/plen;
            double dBL = std::abs(off)/plen;
            double dUL = std::abs(-dx*(bufH-1)+off)/plen;
            double len = std::max({dBR,dUR,dBL,dUL}), step = len*f;
            for (int x = 0; x < bufW; ++x)
                for (int y = 0; y < bufH; ++y) {
                    double d = std::abs(dy*x - dx*y + off)/plen;
                    mask[x*bufH+y] = std::max(mask[x*bufH+y], uint8_t((d > step) ? m1 : m2));
                }
            break;
        }
        case NativeTransitionType::SquareExplode: {
            uint8_t m1 = 255, m2 = 0; float f = factor;
            bool dr = out ? !reverse : reverse;
            if (dr) { f = 1.0f - factor; m1 = 0; m2 = 255; }
            float xs = (bufW/2.0f)*f, ys = (bufH/2.0f)*f;
            int x1 = int(bufW/2-xs), x2 = int(bufW/2+xs), y1 = int(bufH/2-ys), y2 = int(bufH/2+ys);
            for (int x = 0; x < bufW; ++x)
                for (int y = 0; y < bufH; ++y)
                    mask[x*bufH+y] = std::max(mask[x*bufH+y],
                        uint8_t((x<x1||x>x2||y<y1||y>y2) ? m1 : m2));
            break;
        }
        case NativeTransitionType::CircleExplode: {
            float mr = std::sqrt(float((bufW/2)*(bufW/2)+(bufH/2)*(bufH/2)));
            uint8_t m1 = 255, m2 = 0; float f = factor;
            bool dr = out ? !reverse : reverse;
            if (dr) { f = 1.0f - factor; m1 = 0; m2 = 255; }
            float rad = mr * f;
            for (int x = 0; x < bufW; ++x)
                for (int y = 0; y < bufH; ++y) {
                    float r = std::sqrt(float((x-bufW/2)*(x-bufW/2)+(y-bufH/2)*(y-bufH/2)));
                    mask[x*bufH+y] = std::max(mask[x*bufH+y], uint8_t((r<rad)?m2:m1));
                }
            break;
        }
        case NativeTransitionType::Blinds: {
            int adj = adjust; if (adj == 0) adj = 1;
            adj = (bufW/2)*adj/100; if (adj == 0) adj = 1;
            int per = bufW/adj; if (per < 1) per = 1;
            float st = float(bufH)*factor;
            for (int x = 0; x < bufW; ++x) {
                int bl = x/per;
                for (int y = 0; y < bufH; ++y) {
                    int yp = ((bl%2==1)==out) ? bufH-y-1 : y;
                    uint8_t c = (y <= int(st)) ? uint8_t(0) : uint8_t(255);
                    mask[x*bufH+yp] = std::max(mask[x*bufH+yp], c);
                }
            }
            break;
        }
        case NativeTransitionType::Blend: {
            std::minstd_rand rng(1234);
            int pix = bufW*bufH, adj2 = 10*adjust/100;
            if (adj2 == 0) adj2 = 1;
            int ap = pix/(adj2*adj2); if (ap == 0) ap = 1;
            float st = (float(pix)/(adj2*adj2))*factor;
            int xp = bufW/adj2; while(xp*adj2<bufW) xp++;
            int yp = bufH/adj2; while(yp*adj2<bufH) yp++;
            for (int x = 0; x < bufW; ++x)
                for (int y = 0; y < bufH; ++y)
                    mask[x*bufH+y] = std::max(mask[x*bufH+y], uint8_t(255));
            for (int i = 0; i < int(st); ++i) {
                int jy = rng()%ap, jx = rng()%ap;
                int bx = (jx%xp)*adj2, by = (jy%yp)*adj2;
                for (int xx=bx; xx<bx+adj2 && xx<bufW; ++xx)
                    for (int yy=by; yy<by+adj2 && yy<bufH; ++yy)
                        mask[xx*bufH+yy] = 0;
            }
            break;
        }
        case NativeTransitionType::SlideChecks:
        case NativeTransitionType::SlideBars: {
            int adj2 = adjust; if (adj2 == 0) adj2 = 1;
            adj2 = (bufH/2)*adj2/100; if (adj2 == 0) adj2 = 1;
            int per = bufH/adj2; if (per < 1) per = 1;
            float st = float(bufW)*factor;
            for (int y = 0; y < bufH; ++y) {
                int bl = y/per;
                for (int x = 0; x < bufW; ++x) {
                    int xp = ((bl%2==1)==out) ? bufW-x-1 : x;
                    uint8_t c = (x <= int(st)) ? uint8_t(0) : uint8_t(255);
                    mask[xp*bufH+y] = std::max(mask[xp*bufH+y], c);
                }
            }
            break;
        }
        default: break;
        }
    };

    if (needInMask) buildMask(false);
    if (needOutMask) buildMask(true);
}

// =========================================================================
// RotoZoom — 2D/3D rotation and zoom (ported from PixelBuffer.cpp)
// =========================================================================

void NativePixelBuffer::applyRotoZoom(LayerState& layer, float /*offset*/) {
    const NativeLayerInfo& s = layer.settings;

    // All RotoZoom parameters are already resolved (including value curves)
    // by parseLayerSettings() in NativeRenderCoordinator.cpp before calcOutput().
    // rotation slider is 0-100, maps to 0.0-1.0 turns for Z rotation.
    float zRotation = static_cast<float>(s.rotation) / 100.0f;

    float xRotation = static_cast<float>(s.xRotation);
    float yRotation = static_cast<float>(s.yRotation);
    float zoom = s.zoom;
    int zoomQuality = s.zoomQuality;
    if (zoomQuality < 1) zoomQuality = 1;
    int pivotX = s.pivotPointX;
    int pivotY = s.pivotPointY;
    int xPivot = s.xPivot;
    int yPivot = s.yPivot;

    bool willDoRZ = (xRotation != 0.0f && xRotation != 360.0f);
    willDoRZ |= (yRotation != 0.0f && yRotation != 360.0f);
    willDoRZ |= (zRotation != 0.0f || zoom != 1.0f);

    if (!willDoRZ) return;

    int bufW = layer.buffer.BufferWi;
    int bufH = layer.buffer.BufferHt;
    if (bufW <= 0 || bufH <= 0) return;

    // Process rotation axes in the specified order (legacy rotationorder)
    for (char ch : s.rotationOrder) {
        if (ch == '-' || ch == ' ') continue;

        if (ch == 'X' && xRotation != 0.0f && xRotation != 360.0f) {
            // 3D X-axis rotation: compress columns around pivot
            NativeRenderBuffer orig(layer.buffer);
            layer.buffer.Clear();

            float sine = std::sin((xRotation + 90.0f) * static_cast<float>(M_PI) / 180.0f);
            float pivot = static_cast<float>(xPivot) * bufW / 100.0f;

            for (int x = static_cast<int>(pivot); x < bufW; ++x) {
                float tox = sine * (x - pivot) + pivot;
                for (int y = 0; y < bufH; ++y) {
                    xlColor px;
                    orig.GetPixel(x, y, px);
                    layer.buffer.SetPixel(static_cast<int>(tox), y, px);
                }
            }
            for (int x = static_cast<int>(pivot) - 1; x >= 0; --x) {
                float tox = -1.0f * sine * (pivot - x) + pivot;
                for (int y = 0; y < bufH; ++y) {
                    xlColor px;
                    orig.GetPixel(x, y, px);
                    layer.buffer.SetPixel(static_cast<int>(tox), y, px);
                }
            }
        }

        if (ch == 'Y' && yRotation != 0.0f && yRotation != 360.0f) {
            // 3D Y-axis rotation: compress rows around pivot
            NativeRenderBuffer orig(layer.buffer);
            layer.buffer.Clear();

            float sine = std::sin((yRotation + 90.0f) * static_cast<float>(M_PI) / 180.0f);
            float pivot = static_cast<float>(yPivot) * bufH / 100.0f;

            for (int y = static_cast<int>(pivot); y < bufH; ++y) {
                float toy = sine * (y - pivot) + pivot;
                for (int x = 0; x < bufW; ++x) {
                    xlColor px;
                    orig.GetPixel(x, y, px);
                    layer.buffer.SetPixel(x, static_cast<int>(toy), px);
                }
            }
            for (int y = static_cast<int>(pivot) - 1; y >= 0; --y) {
                float toy = -1.0f * sine * (pivot - y) + pivot;
                for (int x = 0; x < bufW; ++x) {
                    xlColor px;
                    orig.GetPixel(x, y, px);
                    layer.buffer.SetPixel(x, static_cast<int>(toy), px);
                }
            }
        }

        if (ch == 'Z' && (zRotation != 0.0f || zoom != 1.0f)) {
            // 2D Z-axis rotation and zoom
            static const float PI_2 = 6.283185307f;
            NativeRenderBuffer orig(layer.buffer);
            int q = zoomQuality;
            float inc = 1.0f / static_cast<float>(q);

            float angle = PI_2 * -zRotation;
            float xoff = (pivotX * bufW) / 100.0f;
            float yoff = (pivotY * bufH) / 100.0f;
            float anglecos = std::cos(-angle);
            float anglesin = std::sin(-angle);

            layer.buffer.Clear();
            for (int x = 0; x < bufW; ++x) {
                for (int i = 0; i < q; ++i) {
                    for (int y = 0; y < bufH; ++y) {
                        xlColor px;
                        orig.GetPixel(x, y, px);
                        for (int j = 0; j < q; ++j) {
                            float xx = static_cast<float>(x) + (static_cast<float>(i) * inc) - xoff;
                            float yy = static_cast<float>(y) + (static_cast<float>(j) * inc) - yoff;
                            float u = xoff + anglecos * xx * zoom + anglesin * yy * zoom;
                            if (u >= 0 && u < bufW) {
                                float v = yoff + -anglesin * xx * zoom + anglecos * yy * zoom;
                                if (v >= 0 && v < bufH) {
                                    layer.buffer.SetPixel(static_cast<int>(u), static_cast<int>(v), px);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// =========================================================================
// calcOutput — blend all layers
// =========================================================================

void NativePixelBuffer::calcOutput(int effectPeriod, const std::vector<bool>& validLayers) {
    assert(validLayers.size() == _layers.size());

    int numLayers = static_cast<int>(_layers.size());

    // Fast path: if no layers are valid, output is all black.
    // Skip blur/RotoZoom/transitions/blending entirely.
    {
        bool anyValid = false;
        for (int i = 0; i < numLayers; ++i) {
            if (validLayers[i]) { anyValid = true; break; }
        }
        if (!anyValid) {
            std::memset(_outputPixels.data(), 0, _outputPixels.size() * sizeof(xlColor));
            return;
        }
    }

    // Initialize sparkle state if any layer has sparkles
    bool hasSparkles = false;
    for (int i = 0; i < numLayers; ++i) {
        if (!validLayers[i]) continue;
        auto& ls = _layers[i];
        if (ls.settings.sparkle_count > 0 || ls.settings.use_music_sparkle_count) {
            hasSparkles = true;
            break;
        }
    }

    if (hasSparkles && _sparkleState.size() < _nodes.size()) {
        size_t oldSize = _sparkleState.size();
        _sparkleState.resize(_nodes.size());
        for (size_t i = oldSize; i < _nodes.size(); ++i) {
            _sparkleState[i] = static_cast<uint16_t>(std::rand() % 10000);
        }
    }

    // Pre-compute per-layer output parameters (matches legacy calculateNodeOutputParams)
    for (int i = 0; i < numLayers; ++i) {
        if (!validLayers[i]) continue;
        auto& ls = _layers[i];

        ls.outputHueAdjust = ls.settings.hueAdjust / 100.0f;
        ls.outputSaturationAdjust = ls.settings.saturationAdjust / 100.0f;
        ls.outputValueAdjust = ls.settings.valueAdjust / 100.0f;
        ls.outputBrightness = static_cast<int>(ls.settings.brightness);
        ls.outputSparkleCount = ls.settings.sparkle_count;

        ls.outputEffectMixThreshold = ls.settings.mixThreshold;
        if (ls.settings.effectMixVary) {
            // Vary mix threshold based on effect time position
            ls.outputEffectMixThreshold = ls.buffer.GetEffectTimeIntervalPosition();
        }
        if (ls.outputEffectMixThreshold < 0) {
            ls.outputEffectMixThreshold = 0;
        }
    }

    // Apply per-layer blur before blending
    for (int i = 0; i < numLayers; ++i) {
        if (!validLayers[i]) continue;
        if (_layers[i].settings.blur > 1) {
            applyBlur(_layers[i]);
        }
    }

    // Apply per-layer RotoZoom (2D/3D rotation, zoom) after blur.
    // Matches legacy order: blur -> RotoZoom -> transitions -> blend.
    for (int i = 0; i < numLayers; ++i) {
        if (!validLayers[i]) continue;
        applyRotoZoom(_layers[i], 0.0f);
    }

    // Apply per-layer transitions (masks and/or buffer modifications).
    // Must happen after blur but before the per-pixel blend loop.
    for (int i = 0; i < numLayers; ++i) {
        if (!validLayers[i]) continue;
        applyTransitions(_layers[i]);
    }

    // Advance sparkle state each frame
    if (hasSparkles) {
        for (size_t i = 0; i < _sparkleState.size(); ++i) {
            _sparkleState[i]++;
        }
    }

    // Try GPU-accelerated blending first (skip in batch mode — sparse CPU is faster).
    if (!_batchMode && calcOutputGPU(validLayers)) {
        // GPU path succeeded — sparkle is applied as CPU post-pass below
        goto sparkle_pass;
    }

    // CPU blending: in batch mode, only blend at node pixel positions (sparse).
    // In live mode (or GPU fallback), blend all pixels for full preview texture.
    {
    const bool sparse = _batchMode && !_nodePixelIndices.empty();
    const int totalPixels = sparse ? static_cast<int>(_nodePixelIndices.size())
                                   : _bufferWi * _bufferHt;

    for (int i = 0; i < totalPixels; ++i) {
        int pixIdx = sparse ? _nodePixelIndices[i] : i;
        int px = pixIdx % _bufferWi;
        int py = pixIdx / _bufferWi;

        int cnt = 0;
        xlColor result = xlBLACK;

        // Iterate from back (highest layer) to front (layer 0),
        // matching PixelBuffer::GetMixedColor iteration order.
        for (int layer = numLayers - 1; layer >= 0; --layer) {
            if (!validLayers[layer]) continue;

            auto& ls = _layers[layer];

            // Read pixel from this layer's buffer.
            // If a transition mask is active and this pixel is masked,
            // treat it as transparent (matching legacy isMasked() behavior).
            xlColor color;
            if (ls.maskSize > 0) {
                int maskIdx = px * _bufferHt + py;
                if (maskIdx < ls.maskSize && ls.transitionMask[maskIdx] > 0) {
                    color.Set(0, 0, 0, 0);
                } else {
                    ls.buffer.GetPixel(px, py, color);
                }
            } else {
                ls.buffer.GetPixel(px, py, color);
            }

            // Apply HSV adjustments
            float ha = ls.outputHueAdjust;
            float sa = ls.outputSaturationAdjust;
            float va = ls.outputValueAdjust;
            if (ha != 0.0f || sa != 0.0f || va != 0.0f) {
                NativeColorBlending::adjustHSV(color, ha, sa, va);
            }

            // Apply brightness and contrast
            int brightness = ls.outputBrightness;
            int contrast = ls.settings.contrast;
            if (contrast != 0 || brightness != 100) {
                NativeColorBlending::adjustBrightnessContrast(color, brightness, contrast);
            }

            // Blend with accumulated result
            if (cnt > 0) {
                // Build blend parameters for this layer
                MixColorParams params;
                params.mixType = ls.settings.mixType;
                params.effectMixThreshold = ls.outputEffectMixThreshold;
                params.effectMixVaries = ls.settings.effectMixVary;
                params.fadeFactor = ls.settings.fadeFactor;
                params.allowAlpha = ls.buffer.allowAlpha;
                params.bufferWi = _bufferWi;
                params.bufferHt = _bufferHt;
                params.isChromaKey = ls.settings.isChromaKey;
                params.chromaKeyColour = ls.settings.chromaKeyColour;
                params.chromaSensitivity = ls.settings.chromaSensitivity;

                NativeColorBlending::mixColors(px, py, color, result, params);
            } else if (ls.settings.fadeFactor != 1.0f) {
                // First valid layer but needs fade
                HSVValue hsv = color.asHSV();
                hsv.value *= ls.settings.fadeFactor;
                if (color.alpha != 255) {
                    hsv.value *= color.alpha;
                    hsv.value /= 255.0f;
                }
                result = hsv;
            } else {
                // First valid layer, no fade — alpha blend onto black
                result.AlphaBlendForgroundOnto(color);
            }

            cnt++;
        }

        _outputPixels[pixIdx] = result;
    }
    } // end CPU blending block

sparkle_pass:
    // Apply per-node sparkle as a post-pass on the output pixels.
    // This matches the legacy behavior where sparkle is applied to the
    // blended result at each node's buffer position.
    if (hasSparkles) {
        for (size_t nodeIdx = 0; nodeIdx < _nodes.size(); ++nodeIdx) {
            const auto& node = _nodes[nodeIdx];
            if (node.bufX < 0 || node.bufX >= _bufferWi ||
                node.bufY < 0 || node.bufY >= _bufferHt) {
                continue;
            }

            // Find the highest valid layer with sparkle count > 0
            int sparkleCount = 0;
            xlColor sparkleColour = xlWHITE;
            for (int layer = numLayers - 1; layer >= 0; --layer) {
                if (!validLayers[layer]) continue;
                auto& ls = _layers[layer];
                if (ls.outputSparkleCount > 0) {
                    sparkleCount = ls.outputSparkleCount;
                    sparkleColour = ls.settings.sparklesColour;
                    break;
                }
            }

            if (sparkleCount > 0) {
                int pixIdx = node.bufY * _bufferWi + node.bufX;
                applySparkle(_outputPixels[pixIdx],
                            static_cast<int>(nodeIdx),
                            sparkleCount, sparkleColour);
            }
        }
    }
}

// =========================================================================
// Submodel mask
// =========================================================================

void NativePixelBuffer::setSubmodelMask(const std::set<std::pair<int,int>>& mask) {
    _submodelMask = mask;
    _hasSubmodelMask = !mask.empty();
}

void NativePixelBuffer::clearSubmodelMask() {
    _submodelMask.clear();
    _hasSubmodelMask = false;
}

void NativePixelBuffer::setDimmingCurve(const NativeDimmingCurve& curve) {
    _dimmingCurve = curve;
}

void NativePixelBuffer::setGroupSpatialLayout(int combinedW, int combinedH,
                                               const std::vector<std::pair<int,int>>& spatialPositions,
                                               size_t groupLayerCount) {
    _spatialBufW = combinedW;
    _spatialBufH = combinedH;
    _spatialNodePositions = spatialPositions;
    _spatialGroupLayerCount = groupLayerCount;
}

// =========================================================================
// getColors — extract blended data to output channels
// =========================================================================

void NativePixelBuffer::getColors(uint8_t* outputBuffer, uint32_t bufferSize) const {
    const bool hasMask = _hasSubmodelMask;
    const bool hasDimming = _dimmingCurve.active;

    for (const auto& node : _nodes) {
        if (node.bufX < 0 || node.bufX >= _bufferWi ||
            node.bufY < 0 || node.bufY >= _bufferHt) {
            continue;
        }

        // Hoisted bounds check: verify all channels fit in one test
        uint32_t endOffset = node.actChannel + node.channelsPerNode;
        if (endOffset > bufferSize) continue;

        // When a submodel mask is active, nodes outside the mask write zero channels.
        if (hasMask &&
            _submodelMask.find({node.bufX, node.bufY}) == _submodelMask.end()) {
            std::memset(outputBuffer + node.actChannel, 0, node.channelsPerNode);
            continue;
        }

        int pixIdx = node.bufY * _bufferWi + node.bufX;
        xlColor color = _outputPixels[pixIdx];

        // Apply dimming curve (gamma/brightness correction)
        if (hasDimming) {
            if (node.channelsPerNode == 1) {
                color.red = _dimmingCurve.red[color.red];
            } else {
                _dimmingCurve.apply(color);
            }
        }

        // Extract RGB(W) channels in the correct order.
        uint8_t wChannel = 0;
        if (node.channelsPerNode == 4) {
            wChannel = std::min({color.red, color.green, color.blue});
        }
        uint8_t channels[4] = { color.red, color.green, color.blue, wChannel };

        // Write channels — bounds already verified above
        uint8_t* dest = outputBuffer + node.actChannel;
        for (int ch = 0; ch < node.channelsPerNode; ++ch) {
            dest[ch] = channels[node.colorOrder[ch]];
        }
    }
}

// =========================================================================
// loadChannelData — reverse of getColors()
// =========================================================================

void NativePixelBuffer::loadChannelData(int layer, const uint8_t* outputBuffer, uint32_t bufferSize) {
    assert(layer >= 0 && layer < static_cast<int>(_layers.size()));
    if (!outputBuffer || bufferSize == 0) return;

    NativeRenderBuffer& buf = _layers[layer].buffer;
    buf.Clear();

    // Build reverse color order mapping: for each source component (R=0, G=1, B=2, W=3),
    // find which output channel index it maps to. This reverses the getColors() mapping.
    // In getColors(): outputBuffer[actChannel + ch] = channels[colorOrder[ch]]
    // So to reverse: source[colorOrder[ch]] was written to outputBuffer[actChannel + ch]
    // We need: source[component] = outputBuffer[actChannel + reverseOrder[component]]

    for (const auto& node : _nodes) {
        if (node.bufX < 0 || node.bufX >= _bufferWi ||
            node.bufY < 0 || node.bufY >= _bufferHt) {
            continue;
        }

        // Build reverse mapping: for source component i, which channel offset has it?
        int reverseOrder[4] = {0, 1, 2, 3};
        for (int ch = 0; ch < node.channelsPerNode; ++ch) {
            int srcIdx = node.colorOrder[ch];
            if (srcIdx >= 0 && srcIdx < 4) {
                reverseOrder[srcIdx] = ch;
            }
        }

        // Read RGB channels from output buffer using reverse color order
        uint8_t r = 0, g = 0, b = 0;
        if (node.channelsPerNode == 1) {
            // Single channel: read the one channel as grayscale
            uint32_t offset = node.actChannel;
            if (offset < bufferSize) {
                r = g = b = outputBuffer[offset];
            }
        } else {
            // RGB or RGBW: read each component from its mapped channel position
            uint32_t rOffset = node.actChannel + reverseOrder[0];
            uint32_t gOffset = node.actChannel + reverseOrder[1];
            uint32_t bOffset = node.actChannel + reverseOrder[2];
            if (rOffset < bufferSize) r = outputBuffer[rOffset];
            if (gOffset < bufferSize) g = outputBuffer[gOffset];
            if (bOffset < bufferSize) b = outputBuffer[bOffset];
        }

        // Reverse dimming curve to get back to linear render space.
        // The output buffer has dimmed values; we need un-dimmed values for rendering.
        if (_dimmingCurve.active) {
            // Build reverse LUT by finding the closest input value for each output
            // This is an approximation but sufficient for blending purposes.
            // For monotonic gamma curves, we can do a simple reverse lookup.
            auto reverseLUT = [](const std::array<uint8_t, 256>& lut, uint8_t val) -> uint8_t {
                // Find the input value whose LUT output is closest to val
                uint8_t best = val;
                int bestDist = 256;
                for (int i = 0; i < 256; ++i) {
                    int dist = std::abs(static_cast<int>(lut[i]) - static_cast<int>(val));
                    if (dist < bestDist) {
                        bestDist = dist;
                        best = static_cast<uint8_t>(i);
                        if (dist == 0) break;
                    }
                }
                return best;
            };
            r = reverseLUT(_dimmingCurve.red, r);
            g = reverseLUT(_dimmingCurve.green, g);
            b = reverseLUT(_dimmingCurve.blue, b);
        }

        buf.SetPixel(node.bufX, node.bufY, xlColor(r, g, b));
    }
}

// =========================================================================
// getBlendedPixel
// =========================================================================

xlColor NativePixelBuffer::getBlendedPixel(int x, int y) const {
    if (x < 0 || x >= _bufferWi || y < 0 || y >= _bufferHt) {
        return xlBLACK;
    }
    return _outputPixels[y * _bufferWi + x];
}

const uint8_t* NativePixelBuffer::getBlendedPixelData() const {
    if (_outputPixels.empty()) return nullptr;
    return reinterpret_cast<const uint8_t*>(_outputPixels.data());
}

size_t NativePixelBuffer::getBlendedPixelDataSize() const {
    return _outputPixels.size() * sizeof(xlColor);
}

// =========================================================================
// Clear
// =========================================================================

void NativePixelBuffer::clear() {
    for (auto& ls : _layers) {
        ls.buffer.Clear();
    }
    std::fill(_outputPixels.begin(), _outputPixels.end(), xlBLACK);
}

void NativePixelBuffer::clearLayer(int layer) {
    assert(layer >= 0 && layer < static_cast<int>(_layers.size()));
    _layers[layer].buffer.Clear();
}

void NativePixelBuffer::resetEffectState() {
    for (auto& ls : _layers) {
        ls.buffer.Clear();
        ls.buffer.ClearEffectCache();
    }
    std::fill(_outputPixels.begin(), _outputPixels.end(), xlBLACK);
}

// =========================================================================
// Sub-buffer support
// =========================================================================

void NativePixelBuffer::prepareSubBuffer(int layer) {
    assert(layer >= 0 && layer < static_cast<int>(_layers.size()));
    auto& ls = _layers[layer];
    if (!ls.settings.hasSubBuffer) { ls.subBufferActive = false; return; }

    int subW = ls.settings.subBufX2 - ls.settings.subBufX1;
    int subH = ls.settings.subBufY2 - ls.settings.subBufY1;
    if (subW < 1) subW = 1;
    if (subH < 1) subH = 1;

    ls.subBufOrigW = _bufferWi;
    ls.subBufOrigH = _bufferHt;
    ls.subBufferActive = true;
    ls.buffer.Resize(subH, subW);
    ls.buffer.Clear();
}

void NativePixelBuffer::expandSubBuffer(int layer) {
    assert(layer >= 0 && layer < static_cast<int>(_layers.size()));
    auto& ls = _layers[layer];
    if (!ls.subBufferActive) return;

    int x1 = ls.settings.subBufX1;
    int y1 = ls.settings.subBufY1;
    int subW = ls.buffer.BufferWi;
    int subH = ls.buffer.BufferHt;
    int fullW = ls.subBufOrigW;
    int fullH = ls.subBufOrigH;

    std::vector<xlColor> subPixels(static_cast<size_t>(subW) * subH);
    for (int y = 0; y < subH; ++y)
        for (int x = 0; x < subW; ++x)
            ls.buffer.GetPixel(x, y, subPixels[y * subW + x]);

    ls.buffer.Resize(fullH, fullW);
    ls.buffer.Clear();
    for (int y = 0; y < subH; ++y) {
        int destY = y + y1;
        if (destY < 0 || destY >= fullH) continue;
        for (int x = 0; x < subW; ++x) {
            int destX = x + x1;
            if (destX < 0 || destX >= fullW) continue;
            ls.buffer.SetPixel(destX, destY, subPixels[y * subW + x]);
        }
    }
    ls.subBufferActive = false;
}

// =========================================================================
// Buffer style support
// =========================================================================

void NativePixelBuffer::prepareBufferStyle(int layer) {
    assert(layer >= 0 && layer < static_cast<int>(_layers.size()));
    auto& ls = _layers[layer];
    std::string style = ls.settings.bufferStyle;
    if (style == "Default" || style.empty()) { ls.bufferStyleActive = false; return; }

    // "Per Model" / "Per Model Deep" buffer styles: the effect renders
    // independently per member model within a group layer. Since the native
    // pipeline already renders group effects per-model (each physical model
    // gets its own render job with group layers cascaded), the "Per Model"
    // behavior is inherent. Extract the sub-style (e.g., "Per Model Single
    // Line" → "Single Line") and apply it as a normal buffer style reshape.
    // "Per Model Deep" flattens nested groups to leaf models, which is also
    // the default behavior since buildModelJobs() creates leaf-model jobs.
    if (style.compare(0, 9, "Per Model") == 0) {
        // Extract sub-style: "Per Model <sub-style>" or "Per Model <sub-style> Deep"
        std::string subStyle;
        if (style.size() > 10) {
            subStyle = style.substr(10); // skip "Per Model "
        }
        // Remove trailing " Deep" suffix if present
        if (subStyle.size() >= 5 &&
            subStyle.compare(subStyle.size() - 5, 5, " Deep") == 0) {
            subStyle = subStyle.substr(0, subStyle.size() - 5);
        }
        // "Default" or empty sub-style means no reshape needed
        if (subStyle.empty() || subStyle == "Default") {
            ls.bufferStyleActive = false;
            return;
        }
        // Otherwise, apply the sub-style (e.g., "Single Line", "As Pixel")
        style = subStyle;
    }

    int nodeCount = std::max(1, static_cast<int>(_nodes.size()));
    ls.styleOrigW = _bufferWi;
    ls.styleOrigH = _bufferHt;

    if (style == "Single Line" || style == "As Pixel") {
        ls.bufferStyleActive = true;
        // Use Resize + Clear instead of InitBuffer to avoid clearing tempbuf.
        // The buffer dimensions alternate between styled and full every frame
        // but the vector capacity is retained, so Resize never allocates.
        ls.buffer.Resize(1, nodeCount);
        ls.buffer.Clear();
    } else if (_spatialBufW > 0 && _spatialBufH > 0 &&
               !_spatialNodePositions.empty() &&
               static_cast<size_t>(layer) < _spatialGroupLayerCount &&
               style != "Default" && !style.empty()) {
        ls.bufferStyleActive = true;
        ls.buffer.Resize(_spatialBufH, _spatialBufW);
        ls.buffer.Clear();
    } else {
        ls.bufferStyleActive = false;
    }
}

void NativePixelBuffer::expandBufferStyle(int layer) {
    assert(layer >= 0 && layer < static_cast<int>(_layers.size()));
    auto& ls = _layers[layer];
    if (!ls.bufferStyleActive) return;

    int styleW = ls.buffer.BufferWi;
    int styleH = ls.buffer.BufferHt;
    int fullW = ls.styleOrigW;
    int fullH = ls.styleOrigH;
    int nodeCount = static_cast<int>(_nodes.size());

    // Check if this is a spatial expand (combined group geometry) or
    // a simple 1D expand (Single Line / As Pixel).
    bool isSpatialExpand = _spatialBufW > 0 && _spatialBufH > 0
                           && !_spatialNodePositions.empty()
                           && styleW == _spatialBufW && styleH == _spatialBufH;

    if (isSpatialExpand) {
        // Spatial expand: read each node's pixel from its spatial position
        // in the rendered combined buffer, then write to local (bufX, bufY).
        // Only read the pixels we need (at spatial node positions) rather
        // than the full W×H buffer, since the spatial buffer can be large.
        size_t spatialCount = _spatialNodePositions.size();
        std::vector<xlColor> nodeColors(static_cast<size_t>(nodeCount));
        for (int i = 0; i < nodeCount; ++i) {
            if (static_cast<size_t>(i) >= spatialCount) break;
            int sx = _spatialNodePositions[i].first;
            int sy = _spatialNodePositions[i].second;
            if (sx >= 0 && sx < styleW && sy >= 0 && sy < styleH) {
                ls.buffer.GetPixel(sx, sy, nodeColors[i]);
            }
        }

        // Resize to model's local buffer dimensions and clear pixels only
        // (no tempbuf clear — saves ~50% of the expand cost).
        ls.buffer.Resize(fullH, fullW);
        ls.buffer.Clear();

        // Map each node's spatial pixel to its local position
        for (int i = 0; i < nodeCount; ++i) {
            const xlColor& c = nodeColors[i];
            if (c == xlBLACK) continue;
            const auto& node = _nodes[i];
            if (node.bufX >= 0 && node.bufX < fullW && node.bufY >= 0 && node.bufY < fullH)
                ls.buffer.SetPixel(node.bufX, node.bufY, c);
        }
    } else {
        // 1D expand (Single Line / As Pixel)
        std::vector<xlColor> stylePixels(static_cast<size_t>(styleW));
        for (int x = 0; x < styleW; ++x)
            ls.buffer.GetPixel(x, 0, stylePixels[x]);

        ls.buffer.Resize(fullH, fullW);
        ls.buffer.Clear();
        for (int i = 0; i < nodeCount && i < styleW; ++i) {
            const xlColor& c = stylePixels[i];
            if (c == xlBLACK) continue;
            const auto& node = _nodes[i];
            if (node.bufX >= 0 && node.bufX < fullW && node.bufY >= 0 && node.bufY < fullH)
                ls.buffer.SetPixel(node.bufX, node.bufY, c);
        }
    }
    ls.bufferStyleActive = false;
}

// =========================================================================
// GPU-accelerated blending via Metal compute
// =========================================================================

bool NativePixelBuffer::calcOutputGPU(const std::vector<bool>& validLayers) {
#ifdef __APPLE__
    // Lazy-initialize Metal compute on first use
    if (!_metalComputeInitialized) {
        _metalComputeInitialized = true;
        _metalCompute = std::make_unique<MetalBlendingCompute>();
        if (!_metalCompute->isAvailable()) {
            _metalCompute.reset();
        }
    }

    if (!_metalCompute) return false;

    int numLayers = static_cast<int>(_layers.size());
    int totalPixels = _bufferWi * _bufferHt;

    // Skip GPU path for small/medium buffers. The synchronous GPU dispatch
    // overhead (command buffer create + encode + commit + waitUntilCompleted +
    // readback) far exceeds the CPU cost for buffers under ~10K pixels.
    // For live preview with hundreds of small models, this is catastrophic.
    // Only use GPU for large matrices/groups in batch rendering.
    if (totalPixels < 10000) return false;

    // Build GPU blend params
    GPUBlendParams params;
    params.bufferWi = _bufferWi;
    params.bufferHt = _bufferHt;
    params.numLayers = numLayers;
    params.totalPixels = totalPixels;

    // Build per-layer GPU settings and collect mask data
    std::vector<GPULayerSettings> gpuSettings(numLayers);
    std::vector<uint8_t> maskData;
    size_t pixelsPerLayer = static_cast<size_t>(totalPixels);

    for (int i = 0; i < numLayers; ++i) {
        auto& gs = gpuSettings[i];
        auto& ls = _layers[i];

        gs.isValid = validLayers[i] ? 1 : 0;
        if (!validLayers[i]) {
            gs.maskOffset = -1;
            gs.maskSize = 0;
            continue;
        }

        gs.mixType = static_cast<int32_t>(ls.settings.mixType);
        gs.effectMixThreshold = ls.outputEffectMixThreshold;
        gs.effectMixVary = ls.settings.effectMixVary ? 1 : 0;
        gs.fadeFactor = ls.settings.fadeFactor;
        gs.allowAlpha = ls.buffer.allowAlpha ? 1 : 0;
        gs.hueAdjust = ls.outputHueAdjust;
        gs.saturationAdjust = ls.outputSaturationAdjust;
        gs.valueAdjust = ls.outputValueAdjust;
        gs.brightness = ls.outputBrightness;
        gs.contrast = ls.settings.contrast;
        gs.isChromaKey = ls.settings.isChromaKey ? 1 : 0;
        gs.chromaSensitivity = ls.settings.chromaSensitivity;
        gs.chromaKeyColour[0] = ls.settings.chromaKeyColour.red;
        gs.chromaKeyColour[1] = ls.settings.chromaKeyColour.green;
        gs.chromaKeyColour[2] = ls.settings.chromaKeyColour.blue;
        gs.chromaKeyColour[3] = ls.settings.chromaKeyColour.alpha;
        gs._padding0 = 0;

        // Copy transition mask data
        if (ls.maskSize > 0 && !ls.transitionMask.empty()) {
            gs.maskOffset = static_cast<int32_t>(maskData.size());
            gs.maskSize = ls.maskSize;
            maskData.insert(maskData.end(),
                            ls.transitionMask.begin(),
                            ls.transitionMask.begin() + ls.maskSize);
        } else {
            gs.maskOffset = -1;
            gs.maskSize = 0;
        }
    }

    // Build flattened layer pixel data: all layers concatenated as RGBA bytes.
    // xlColor is [red, green, blue, alpha] which is 4 bytes, same layout as uchar4.
    size_t layerDataSize = static_cast<size_t>(numLayers) * pixelsPerLayer * 4;
    std::vector<uint8_t> layerPixelData(layerDataSize);

    for (int i = 0; i < numLayers; ++i) {
        if (!validLayers[i]) {
            // Zero out invalid layers
            std::memset(layerPixelData.data() + i * pixelsPerLayer * 4, 0, pixelsPerLayer * 4);
            continue;
        }
        const xlColor* pixels = _layers[i].buffer.GetPixels();
        std::memcpy(layerPixelData.data() + i * pixelsPerLayer * 4,
                     pixels, pixelsPerLayer * 4);
    }

    // Dispatch to GPU
    bool success = _metalCompute->blendLayers(
        params,
        gpuSettings,
        layerPixelData.data(),
        layerDataSize,
        maskData.empty() ? nullptr : maskData.data(),
        maskData.size(),
        _outputPixels.data());

    return success;
#else
    (void)validLayers;
    return false;
#endif
}

} // namespace xlEngine
