/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// NativeColorBlending: Pure C++ color blending logic extracted from
// PixelBuffer.cpp. All blend math is identical to the legacy implementation
// but with wxWidgets dependencies removed (wxCoord -> int, wxASSERT -> assert).

#include "NativeColorBlending.h"

#include <algorithm>
#include <cassert>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace NativeColorBlending {

// ---- Mix type name/enum mapping ----

static const std::map<std::string, NativeMixType> sMixTypesMap = {
    { "Effect 1", NativeMixType::Mix_Effect1 },
    { "Effect 2", NativeMixType::Mix_Effect2 },
    { "1 is Mask", NativeMixType::Mix_Mask1 },
    { "2 is Mask", NativeMixType::Mix_Mask2 },
    { "1 is Unmask", NativeMixType::Mix_Unmask1 },
    { "2 is Unmask", NativeMixType::Mix_Unmask2 },
    { "1 is True Unmask", NativeMixType::Mix_TrueUnmask1 },
    { "2 is True Unmask", NativeMixType::Mix_TrueUnmask2 },
    { "1 reveals 2", NativeMixType::Mix_1_reveals_2 },
    { "2 reveals 1", NativeMixType::Mix_2_reveals_1 },
    { "Shadow 1 on 2", NativeMixType::Mix_Shadow_1on2 },
    { "Shadow 2 on 1", NativeMixType::Mix_Shadow_2on1 },
    { "Layered", NativeMixType::Mix_Layered },
    { "Normal", NativeMixType::Mix_Normal },
    { "Highlight", NativeMixType::Mix_Highlight },
    { "Highlight Vibrant", NativeMixType::Mix_Highlight_Vibrant },
    { "Additive", NativeMixType::Mix_Additive },
    { "Subtractive", NativeMixType::Mix_Subtractive },
    { "Brightness", NativeMixType::Mix_AsBrightness },
    { "Average", NativeMixType::Mix_Average },
    { "Bottom-Top", NativeMixType::Mix_BottomTop },
    { "Left-Right", NativeMixType::Mix_LeftRight },
    { "Max", NativeMixType::Mix_Max },
    { "Min", NativeMixType::Mix_Min }
};

// Reverse map built once on first use
static const std::map<NativeMixType, std::string>& getReverseMixTypeMap() {
    static std::map<NativeMixType, std::string> reverse;
    if (reverse.empty()) {
        for (const auto& it : sMixTypesMap) {
            reverse[it.second] = it.first;
        }
    }
    return reverse;
}

std::vector<std::string> getMixTypeNames() {
    std::vector<std::string> res;
    res.reserve(sMixTypesMap.size());
    for (const auto& it : sMixTypesMap) {
        res.push_back(it.first);
    }
    return res;
}

const std::map<std::string, NativeMixType>& getMixTypeMap() {
    return sMixTypesMap;
}

NativeMixType mixTypeFromName(const std::string& name) {
    auto it = sMixTypesMap.find(name);
    if (it == sMixTypesMap.end()) {
        return NativeMixType::Mix_Effect1;
    }
    return it->second;
}

std::string mixTypeName(NativeMixType type) {
    const auto& reverse = getReverseMixTypeMap();
    auto it = reverse.find(type);
    if (it == reverse.end()) {
        return "Normal";
    }
    return it->second;
}

bool mixTypeHandlesAlpha(NativeMixType mt) {
    return mt == NativeMixType::Mix_Normal;
}

// ---- Core blending ----

double colourDistance(xlColor e1, xlColor e2) {
    long rmean = ((long)e1.red + (long)e2.red) / 2;
    long r = (long)e1.red - (long)e2.red;
    long g = (long)e1.green - (long)e2.green;
    long b = (long)e1.blue - (long)e2.blue;
    return sqrt((((512 + rmean) * r * r) >> 8) + 4 * g * g + (((767 - rmean) * b * b) >> 8));
}

void mixColors(int x, int y, xlColor& fg, xlColor& bg, const MixColorParams& params) {
    static const int n = 0; // increase to change the curve of the crossfade

    if (!params.allowAlpha && params.fadeFactor != 1.0f) {
        HSVValue hsv0 = fg.asHSV();
        hsv0.value *= params.fadeFactor;
        fg = hsv0;
    }

    // Apply ChromaKey if it is enabled
    if (params.isChromaKey) {
        xlColor c(fg);
        if (c.alpha < 255) {
            c.red = (int)(c.red * c.alpha) / 255;
            c.green = (int)(c.green * c.alpha) / 255;
            c.blue = (int)(c.blue * c.alpha) / 255;
            c.alpha = 255;
        }
        if (colourDistance(c, params.chromaKeyColour) < params.chromaSensitivity * 402 / 255) {
            return;
        }
    }

    float effectMixThreshold = params.effectMixThreshold;
    switch (params.mixType) {
    case NativeMixType::Mix_Normal:
        fg.alpha = fg.alpha * params.fadeFactor * (1.0 - effectMixThreshold);
        bg.AlphaBlendForgroundOnto(fg);
        break;
    case NativeMixType::Mix_Effect1:
    case NativeMixType::Mix_Effect2: {
        double emt, emtNot;
        if (!params.effectMixVaries) {
            emt = effectMixThreshold;
            if ((emt > 0.000001) && (emt < 0.99999)) {
                emtNot = 1 - effectMixThreshold;
                // make cross-fade linear
                emt = cos((M_PI / 4) * (pow(2 * emt - 1, 2 * n + 1) + 1));
                emtNot = cos((M_PI / 4) * (pow(2 * emtNot - 1, 2 * n + 1) + 1));
            } else {
                emtNot = effectMixThreshold;
                emt = 1 - effectMixThreshold;
            }
        } else {
            emt = effectMixThreshold;
            emtNot = 1 - effectMixThreshold;
        }

        if (params.mixType == NativeMixType::Mix_Effect2) {
            fg.Set(fg.Red() * (emtNot), fg.Green() * (emtNot), fg.Blue() * (emtNot));
            bg.Set(bg.Red() * (emt), bg.Green() * (emt), bg.Blue() * (emt));
        } else {
            fg.Set(fg.Red() * (emt), fg.Green() * (emt), fg.Blue() * (emt));
            bg.Set(bg.Red() * (emtNot), bg.Green() * (emtNot), bg.Blue() * (emtNot));
        }
        bg.Set(fg.Red() + bg.Red(), fg.Green() + bg.Green(), fg.Blue() + bg.Blue());
        break;
    }
    case NativeMixType::Mix_Mask1: {
        // first masks second
        HSVValue hsv0 = fg.asHSV();
        if (hsv0.value > effectMixThreshold) {
            bg.Set(0, 0, 0);
        }
        break;
    }
    case NativeMixType::Mix_Mask2: {
        // second masks first
        HSVValue hsv1 = bg.asHSV();
        if (hsv1.value <= effectMixThreshold) {
            bg = fg;
        } else {
            bg.Set(0, 0, 0);
        }
        break;
    }
    case NativeMixType::Mix_Unmask1: {
        // first unmasks second
        HSVValue hsv0 = fg.asHSV();
        if (hsv0.value > effectMixThreshold) {
            HSVValue hsv1 = bg.asHSV();
            hsv1.value = hsv0.value;
            bg = hsv1;
        } else {
            bg.Set(0, 0, 0);
        }
        break;
    }
    case NativeMixType::Mix_TrueUnmask1: {
        // first unmasks second
        HSVValue hsv0 = fg.asHSV();
        if (hsv0.value <= effectMixThreshold) {
            bg.Set(0, 0, 0);
        }
        break;
    }
    case NativeMixType::Mix_Unmask2: {
        // second unmasks first
        HSVValue hsv1 = bg.asHSV();
        if (hsv1.value > effectMixThreshold) {
            HSVValue hsv0 = fg.asHSV();
            // if effect 2 is non black
            hsv0.value = hsv1.value;
            bg = hsv0;
        } else {
            bg.Set(0, 0, 0);
        }
        break;
    }
    case NativeMixType::Mix_TrueUnmask2: {
        // second unmasks first
        HSVValue hsv1 = bg.asHSV();
        if (hsv1.value > effectMixThreshold) {
            // if effect 2 is non black
            bg = fg;
        } else {
            bg.Set(0, 0, 0);
        }
        break;
    }
    case NativeMixType::Mix_Shadow_1on2: {
        // Effect 1 shadows onto effect 2
        HSVValue hsv0 = fg.asHSV();
        HSVValue hsv1 = bg.asHSV();
        if (hsv0.value > 0.0)
            hsv1.hue = hsv1.hue + (hsv0.value * (hsv1.hue - hsv0.hue)) / 5.0;
        bg = hsv1;
        break;
    }
    case NativeMixType::Mix_Shadow_2on1: {
        // Effect 2 shadows onto effect 1
        HSVValue hsv0 = fg.asHSV();
        HSVValue hsv1 = bg.asHSV();
        if (hsv1.value > 0.0) {
            hsv0.hue = hsv0.hue + (hsv1.value * (hsv0.hue - hsv1.hue)) / 2.0;
        }
        bg = hsv0;
        break;
    }
    case NativeMixType::Mix_Layered: {
        HSVValue hsv1 = bg.asHSV();
        if (hsv1.value <= effectMixThreshold) {
            bg = fg;
        }
        break;
    }
    case NativeMixType::Mix_Average:
        // only average when both colors are non-black
        if (bg == xlBLACK || bg.alpha == 0) {
            bg = fg;
        } else if (fg != xlBLACK && fg.alpha != 0) {
            bg.Set((fg.Red() + bg.Red()) / 2, (fg.Green() + bg.Green()) / 2, (fg.Blue() + bg.Blue()) / 2, (fg.alpha + bg.alpha) / 2);
        }
        break;
    case NativeMixType::Mix_BottomTop:
        bg = y < params.bufferHt / 2 ? fg : bg;
        break;
    case NativeMixType::Mix_LeftRight:
        bg = x < params.bufferWi / 2 ? fg : bg;
        break;
    case NativeMixType::Mix_1_reveals_2: {
        HSVValue hsv0 = fg.asHSV();
        bg = hsv0.value > effectMixThreshold ? fg : bg; // if effect 1 is non black
        break;
    }
    case NativeMixType::Mix_2_reveals_1: {
        HSVValue hsv1 = bg.asHSV();
        bg = hsv1.value > effectMixThreshold ? bg : fg; // if effect 2 is non black
        break;
    }
    case NativeMixType::Mix_Highlight: {
        bool effect1HasColor = (fg.red > 0 || fg.green > 0 || fg.blue > 0);
        bool effect2HasColor = (bg.red > 0 || bg.green > 0 || bg.blue > 0);
        HSVValue hsv1 = bg.asHSV();

        if (effect1HasColor && (effect2HasColor || hsv1.value > effectMixThreshold)) {
            bg = fg;
        }
    } break;
    case NativeMixType::Mix_Highlight_Vibrant: {
        HSVValue hsv1 = bg.asHSV();
        if (hsv1.value > effectMixThreshold) {
            int r = fg.red + bg.red;
            int g = fg.green + bg.green;
            int b = fg.blue + bg.blue;

            if (r > 255)
                r = 255;
            if (g > 255)
                g = 255;
            if (b > 255)
                b = 255;

            bg.Set(r, g, b);
        }
    } break;
    case NativeMixType::Mix_Additive: {
        int r = fg.red + bg.red;
        int g = fg.green + bg.green;
        int b = fg.blue + bg.blue;
        if (r > 255)
            r = 255;
        if (g > 255)
            g = 255;
        if (b > 255)
            b = 255;
        bg.Set(r, g, b);
    } break;
    case NativeMixType::Mix_Subtractive: {
        int r = bg.red - fg.red;
        int g = bg.green - fg.green;
        int b = bg.blue - fg.blue;
        if (r < 0)
            r = 0;
        if (g < 0)
            g = 0;
        if (b < 0)
            b = 0;
        bg.Set(r, g, b);
    } break;
    case NativeMixType::Mix_Min: {
        float alpha = (float)fg.alpha / 255.0;
        int r = std::min(fg.red, bg.red) * alpha;
        int g = std::min(fg.green, bg.green) * alpha;
        int b = std::min(fg.blue, bg.blue) * alpha;
        bg.Set(r, g, b);
    } break;
    case NativeMixType::Mix_Max: {
        float alpha = (float)fg.alpha / 255.0;
        int r = std::max(fg.red, bg.red) * alpha;
        int g = std::max(fg.green, bg.green) * alpha;
        int b = std::max(fg.blue, bg.blue) * alpha;
        bg.Set(r, g, b);
    } break;
    case NativeMixType::Mix_AsBrightness: {
        float alpha = (float)fg.alpha / 255.0;
        int r = fg.red * bg.red / 255 * alpha;
        int g = fg.green * bg.green / 255 * alpha;
        int b = fg.blue * bg.blue / 255 * alpha;
        bg.Set(r, g, b);
    } break;
    }
}

// ---- Color adjustment utilities ----

void adjustHSV(xlColor& color, float hueAdj, float satAdj, float valAdj) {
    if (hueAdj == 0.0f && satAdj == 0.0f && valAdj == 0.0f) {
        return;
    }

    HSVValue hsv = color.asHSV();

    if (hueAdj != 0.0f) {
        hsv.hue += hueAdj;
        if (hsv.hue < 0.0) {
            hsv.hue += 1.0;
        } else if (hsv.hue > 1.0) {
            hsv.hue -= 1.0;
        }
    }

    if (satAdj != 0.0f) {
        hsv.saturation += satAdj;
        if (hsv.saturation < 0.0) {
            hsv.saturation = 0.0;
        } else if (hsv.saturation > 1.0) {
            hsv.saturation = 1.0;
        }
    }

    if (valAdj != 0.0f) {
        hsv.value += valAdj;
        if (hsv.value < 0.0) {
            hsv.value = 0.0;
        } else if (hsv.value > 1.0) {
            hsv.value = 1.0;
        }
    }

    unsigned char alpha = color.Alpha();
    color = hsv;
    color.alpha = alpha;
}

void adjustBrightness(xlColor& color, int brightness) {
    if (brightness == 100) {
        return;
    }
    float ba = brightness / 100.0f;
    float f = color.red * ba;
    color.red = std::min((int)f, 255);
    f = color.green * ba;
    color.green = std::min((int)f, 255);
    f = color.blue * ba;
    color.blue = std::min((int)f, 255);
}

void adjustBrightnessContrast(xlColor& color, int brightness, int contrast) {
    if (contrast != 0) {
        HSVValue hsv = color.asHSV();
        hsv.value = hsv.value * ((double)brightness / 100.0);

        // Apply Contrast
        if (hsv.value < 0.5) {
            // reduce brightness when below 0.5 in the V value or increase if > 0.5
            hsv.value = hsv.value - (hsv.value * ((double)contrast / 100.0));
        } else {
            hsv.value = hsv.value + (hsv.value * ((double)contrast / 100.0));
        }

        if (hsv.value < 0.0)
            hsv.value = 0.0;
        if (hsv.value > 1.0)
            hsv.value = 1.0;
        unsigned char alpha = color.Alpha();
        color = hsv;
        color.alpha = alpha;
    } else {
        adjustBrightness(color, brightness);
    }
}

xlColor getMixedColor(int x, int y,
                      const std::vector<xlColor>& layerColors,
                      const std::vector<MixColorParams>& layerParams,
                      const std::vector<bool>& validLayers,
                      const std::vector<float>& hueAdj,
                      const std::vector<float>& satAdj,
                      const std::vector<float>& valAdj,
                      const std::vector<int>& brightness,
                      const std::vector<int>& contrast,
                      const std::vector<float>& fadeFactors) {
    assert(layerColors.size() == layerParams.size());
    assert(layerColors.size() == validLayers.size());

    int numLayers = (int)layerColors.size();
    int cnt = 0;
    xlColor result = xlBLACK;

    // Iterate from back (highest layer index) to front (layer 0),
    // matching PixelBuffer::GetMixedColor iteration order.
    for (int layer = numLayers - 1; layer >= 0; layer--) {
        if (!validLayers[layer]) {
            continue;
        }

        xlColor color = layerColors[layer];

        // Apply per-layer HSV adjustments
        float ha = (layer < (int)hueAdj.size()) ? hueAdj[layer] : 0.0f;
        float sa = (layer < (int)satAdj.size()) ? satAdj[layer] : 0.0f;
        float va = (layer < (int)valAdj.size()) ? valAdj[layer] : 0.0f;
        adjustHSV(color, ha, sa, va);

        // Apply per-layer brightness/contrast
        int b = (layer < (int)brightness.size()) ? brightness[layer] : 100;
        int c = (layer < (int)contrast.size()) ? contrast[layer] : 0;
        adjustBrightnessContrast(color, b, c);

        if (cnt > 0) {
            // Build a MixColorParams with the current layer's fade factor merged in
            MixColorParams p = layerParams[layer];
            if (layer < (int)fadeFactors.size()) {
                p.fadeFactor = fadeFactors[layer];
            }
            mixColors(x, y, color, result, p);
        } else {
            float fade = (layer < (int)fadeFactors.size()) ? fadeFactors[layer] : 1.0f;
            if (fade != 1.0f) {
                HSVValue hsv = color.asHSV();
                hsv.value *= fade;
                if (color.alpha != 255) {
                    hsv.value *= color.alpha;
                    hsv.value /= 255.0f;
                }
                result = hsv;
            } else {
                result.AlphaBlendForgroundOnto(color);
            }
        }

        cnt++;
    }

    return result;
}

} // namespace NativeColorBlending
