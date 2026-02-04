/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "OffEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

namespace xlCore {

std::vector<EffectParameter> OffEffect::parameters() const {
    return {
        EffectParameter::createChoice(
            "E_CHOICE_Off_Style",
            "Style",
            "Black",
            {"Black", "Transparent", "Black -> Transparent", "Transparent -> Black"}
        )
    };
}

OffEffect::OffStyle OffEffect::parseStyle(const std::string& style) {
    if (style == "Transparent") {
        return OffStyle::Transparent;
    } else if (style == "Black -> Transparent") {
        return OffStyle::BlackToTransparent;
    } else if (style == "Transparent -> Black") {
        return OffStyle::TransparentToBlack;
    }
    return OffStyle::Black;
}

void OffEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    std::string styleStr = settings.get("E_CHOICE_Off_Style", "Black");
    // Also check without prefix for compatibility
    if (styleStr.empty()) {
        styleStr = settings.get("CHOICE_Off_Style", "Black");
    }

    OffStyle style = parseStyle(styleStr);

    switch (style) {
        case OffStyle::Transparent:
            // Don't change any pixels - leave buffer as is
            break;

        case OffStyle::Black:
            // Fill entire buffer with black
            ctx.fill(Color::Black());
            break;

        case OffStyle::BlackToTransparent:
            // Convert black pixels to transparent
            for (int y = 0; y < ctx.height(); ++y) {
                for (int x = 0; x < ctx.width(); ++x) {
                    Color c = ctx.getPixel(x, y);
                    if (c == Color::Black()) {
                        ctx.setPixel(x, y, Color::nil());
                    }
                }
            }
            break;

        case OffStyle::TransparentToBlack:
            // Convert transparent pixels to black
            for (int y = 0; y < ctx.height(); ++y) {
                for (int x = 0; x < ctx.width(); ++x) {
                    Color c = ctx.getPixel(x, y);
                    if (c.isNil()) {
                        ctx.setPixel(x, y, Color::Black());
                    }
                }
            }
            break;
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(OffEffect)

} // namespace xlCore
