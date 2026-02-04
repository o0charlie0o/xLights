/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "OnEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <cmath>

namespace xlCore {

std::vector<EffectParameter> OnEffect::parameters() const {
    return {
        EffectParameter::createInt(
            "E_TEXTCTRL_Eff_On_Start",
            "Start Brightness",
            100, 0, 100,
            false  // No value curve support for now
        ),
        EffectParameter::createInt(
            "E_TEXTCTRL_Eff_On_End",
            "End Brightness",
            100, 0, 100,
            false
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_On_Shimmer",
            "Shimmer",
            false
        ),
        EffectParameter::createDouble(
            "E_TEXTCTRL_On_Cycles",
            "Cycles",
            1.0, 0.1, 100.0, 0.1
        ),
        EffectParameter::createInt(
            "E_TEXTCTRL_On_Transparency",
            "Transparency",
            0, ON_TRANSPARENCY_MIN, ON_TRANSPARENCY_MAX,
            true  // Supports value curve
        )
    };
}

double OnEffect::getAdjustedPosition(double progress, double cycles) const {
    // Multiply progress by cycles and take fractional part
    double adjusted = progress * cycles;
    return adjusted - std::floor(adjusted);
}

void OnEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int start = settings.getInt("E_TEXTCTRL_Eff_On_Start", 100);
    int end = settings.getInt("E_TEXTCTRL_Eff_On_End", 100);
    bool shimmer = settings.getBool("E_CHECKBOX_On_Shimmer", false);
    double cycles = settings.getDouble("E_TEXTCTRL_On_Cycles", 1.0);
    int transparency = settings.getInt("E_TEXTCTRL_On_Transparency", 0);

    // Determine which color index to use
    int colorIdx = 0;
    if (shimmer) {
        // Alternate colors every frame
        if (state.frameIndex % 2 == 1) {
            colorIdx = 1;
        }
    }

    // Calculate adjusted position for cycling
    double adjust = getAdjustedPosition(state.progress, cycles);

    // Get base color from palette (we'll need palette support in RenderContext)
    // For now, use a default color approach - actual implementation would get from palette
    Color color = Color::White();  // Default - real implementation gets from palette

    // Apply brightness fade if start != end != 100
    if (start != 100 || end != 100) {
        // Interpolate brightness based on position
        double brightness = start + (end - start) * adjust;
        brightness = brightness / 100.0;

        // Apply to HSV value
        HSV hsv = color.toHSV();
        hsv.value = hsv.value * brightness;
        color.fromHSV(hsv);
    }

    // Apply transparency
    if (transparency > 0) {
        int alpha = 255 - (transparency * 255 / 100);
        color.setAlpha(static_cast<uint8_t>(alpha));
    }

    // Fill the buffer with the color
    ctx.fill(color);
}

// Register the effect
XLCORE_REGISTER_EFFECT(OnEffect)

} // namespace xlCore
