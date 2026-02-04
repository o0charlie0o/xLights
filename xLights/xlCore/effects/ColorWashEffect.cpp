/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "ColorWashEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

// Parameter keys
static const std::string KEY_CYCLES = "E_TEXTCTRL_ColorWash_Cycles";
static const std::string KEY_HFADE = "E_CHECKBOX_ColorWash_HFade";
static const std::string KEY_VFADE = "E_CHECKBOX_ColorWash_VFade";
static const std::string KEY_REVERSE_FADES = "E_CHECKBOX_ColorWash_ReverseFades";
static const std::string KEY_SHIMMER = "E_CHECKBOX_ColorWash_Shimmer";
static const std::string KEY_CIRCULAR = "E_CHECKBOX_ColorWash_CircularPalette";

std::vector<EffectParameter> ColorWashEffect::parameters() const {
    return {
        EffectParameter::createDouble(KEY_CYCLES, "Cycles", 1.0, 0.1, 10.0, 0.1),
        EffectParameter::createBool(KEY_HFADE, "Horizontal Fade", false),
        EffectParameter::createBool(KEY_VFADE, "Vertical Fade", false),
        EffectParameter::createBool(KEY_REVERSE_FADES, "Reverse Fades", false),
        EffectParameter::createBool(KEY_SHIMMER, "Shimmer", false),
        EffectParameter::createBool(KEY_CIRCULAR, "Circular Palette", false)
    };
}

Color ColorWashEffect::getMultiColorBlend(const std::vector<Color>& palette, double position, bool circular) const {
    if (palette.empty()) {
        return Color::Black();
    }
    if (palette.size() == 1) {
        return palette[0];
    }

    // For circular, we add the first color at the end for smooth looping
    size_t numColors = circular ? palette.size() + 1 : palette.size();
    double scaledPos = position * (numColors - 1);

    size_t colorIdx1 = static_cast<size_t>(scaledPos);
    size_t colorIdx2 = colorIdx1 + 1;
    double fraction = scaledPos - colorIdx1;

    // Handle wrapping for circular mode
    if (circular) {
        colorIdx1 = colorIdx1 % palette.size();
        colorIdx2 = colorIdx2 % palette.size();
    } else {
        colorIdx1 = std::min(colorIdx1, palette.size() - 1);
        colorIdx2 = std::min(colorIdx2, palette.size() - 1);
    }

    const Color& c1 = palette[colorIdx1];
    const Color& c2 = palette[colorIdx2];

    // Linear interpolation between colors
    uint8_t r = static_cast<uint8_t>(c1.red + (c2.red - c1.red) * fraction);
    uint8_t g = static_cast<uint8_t>(c1.green + (c2.green - c1.green) * fraction);
    uint8_t b = static_cast<uint8_t>(c1.blue + (c2.blue - c1.blue) * fraction);

    return Color(r, g, b);
}

void ColorWashEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    double cycles = settings.getDouble(KEY_CYCLES, 1.0);
    bool horizFade = settings.getBool(KEY_HFADE, false);
    bool vertFade = settings.getBool(KEY_VFADE, false);
    bool reverseFades = settings.getBool(KEY_REVERSE_FADES, false);
    bool shimmer = settings.getBool(KEY_SHIMMER, false);
    bool circularPalette = settings.getBool(KEY_CIRCULAR, false);

    int width = ctx.width();
    int height = ctx.height();

    // Shimmer: skip every other frame
    if (shimmer && (state.frameIndex % 2) == 1) {
        // Leave buffer black
        return;
    }

    // Build a simple default palette if none provided
    // In a real implementation, this would come from the effect instance
    std::vector<Color> palette = {
        Color::Red(),
        Color::Green(),
        Color::Blue()
    };

    // Calculate position in palette based on time and cycles
    double position = std::fmod(state.progress * cycles, 1.0);

    // Get the blended color at this position
    Color baseColor = getMultiColorBlend(palette, position, circularPalette);

    // Calculate fade parameters
    double halfWidth = static_cast<double>(width - 1) / 2.0;
    double halfHeight = static_cast<double>(height - 1) / 2.0;

    HSV baseHSV = baseColor.toHSV();

    for (int x = 0; x < width; x++) {
        Color rowColor = baseColor;
        HSV hsv = baseHSV;
        double hMult = 1.0;

        // Apply horizontal fade
        if (horizFade && halfWidth > 0) {
            double distFromCenter = std::abs(halfWidth - x);
            if (reverseFades) {
                hMult = distFromCenter / halfWidth;
            } else {
                hMult = 1.0 - (distFromCenter / halfWidth);
            }

            if (ctx.allowAlpha()) {
                rowColor = Color(baseColor.red, baseColor.green, baseColor.blue,
                                static_cast<uint8_t>(255 * hMult));
            } else {
                hsv.value = baseHSV.value * hMult;
                rowColor = Color(hsv);
            }
        }

        for (int y = 0; y < height; y++) {
            Color pixelColor = rowColor;

            // Apply vertical fade
            if (vertFade && halfHeight > 0) {
                double distFromCenter = std::abs(halfHeight - y);
                double vMult;
                if (reverseFades) {
                    vMult = distFromCenter / halfHeight;
                } else {
                    vMult = 1.0 - (distFromCenter / halfHeight);
                }

                if (ctx.allowAlpha()) {
                    // Combine with existing alpha from horizontal fade
                    double combinedAlpha = (static_cast<double>(rowColor.alpha) / 255.0) * vMult;
                    pixelColor = Color(baseColor.red, baseColor.green, baseColor.blue,
                                      static_cast<uint8_t>(255 * combinedAlpha));
                } else {
                    HSV pixelHSV = hsv;
                    pixelHSV.value *= vMult;
                    pixelColor = Color(pixelHSV);
                }
            }

            ctx.setPixel(x, y, pixelColor);
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(ColorWashEffect)

} // namespace xlCore
