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

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstring>
#include <numeric>

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
// calcOutput — blend all layers
// =========================================================================

void NativePixelBuffer::calcOutput(int effectPeriod, const std::vector<bool>& validLayers) {
    assert(validLayers.size() == _layers.size());

    int numLayers = static_cast<int>(_layers.size());

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

    // Advance sparkle state each frame
    if (hasSparkles) {
        for (size_t i = 0; i < _sparkleState.size(); ++i) {
            _sparkleState[i]++;
        }
    }

    // Blend all layers per pixel
    int totalPixels = _bufferWi * _bufferHt;

    for (int pixIdx = 0; pixIdx < totalPixels; ++pixIdx) {
        int px = pixIdx % _bufferWi;
        int py = pixIdx / _bufferWi;

        int cnt = 0;
        xlColor result = xlBLACK;

        // Iterate from back (highest layer) to front (layer 0),
        // matching PixelBuffer::GetMixedColor iteration order.
        for (int layer = numLayers - 1; layer >= 0; --layer) {
            if (!validLayers[layer]) continue;

            auto& ls = _layers[layer];

            // Read pixel from this layer's buffer
            xlColor color;
            ls.buffer.GetPixel(px, py, color);

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

// =========================================================================
// getColors — extract blended data to output channels
// =========================================================================

void NativePixelBuffer::getColors(uint8_t* outputBuffer, uint32_t bufferSize) const {
    for (const auto& node : _nodes) {
        if (node.bufX < 0 || node.bufX >= _bufferWi ||
            node.bufY < 0 || node.bufY >= _bufferHt) {
            continue;
        }

        // When a submodel mask is active, nodes outside the mask write zero channels.
        // This ensures batch rendering (renderAll/renderRange) only writes channel data
        // for the submodel's nodes when effects come from a group with submodel refs.
        if (_hasSubmodelMask &&
            _submodelMask.find({node.bufX, node.bufY}) == _submodelMask.end()) {
            for (int ch = 0; ch < node.channelsPerNode; ++ch) {
                uint32_t destOffset = node.actChannel + ch;
                if (destOffset < bufferSize) {
                    outputBuffer[destOffset] = 0;
                }
            }
            continue;
        }

        int pixIdx = node.bufY * _bufferWi + node.bufX;
        const xlColor& color = _outputPixels[pixIdx];

        // Extract RGB(W) channels in the correct order
        uint8_t channels[4] = { color.red, color.green, color.blue, 0 };

        for (int ch = 0; ch < node.channelsPerNode; ++ch) {
            uint32_t destOffset = node.actChannel + ch;
            if (destOffset < bufferSize) {
                int srcIdx = node.colorOrder[ch];
                if (srcIdx >= 0 && srcIdx < 4) {
                    outputBuffer[destOffset] = channels[srcIdx];
                }
            }
        }
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

} // namespace xlEngine
