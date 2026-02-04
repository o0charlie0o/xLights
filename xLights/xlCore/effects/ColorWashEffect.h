/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

/**
 * @file ColorWashEffect.h
 * @brief Color Wash effect for xlCore - fills model with color palette.
 *
 * This effect fills the entire buffer with colors from the palette,
 * transitioning smoothly between them over time. Supports:
 * - Horizontal fade (brightness fades from center outward)
 * - Vertical fade (brightness fades from center outward)
 * - Reverse fades (brightness fades toward center)
 * - Shimmer (alternates on/off)
 * - Circular palette (loops back to first color)
 */

#include "../Effect.h"

namespace xlCore {

/**
 * @brief Color Wash effect - fills buffer with blended palette colors.
 *
 * Parameters:
 * - Cycles: Number of times to cycle through the palette (default: 1.0)
 * - HFade: Enable horizontal fade from center (default: false)
 * - VFade: Enable vertical fade from center (default: false)
 * - ReverseFades: Reverse the fade direction (default: false)
 * - Shimmer: Alternate between on and black (default: false)
 * - CircularPalette: Loop palette back to first color (default: false)
 */
class ColorWashEffect : public Effect {
public:
    ColorWashEffect() = default;
    ~ColorWashEffect() override = default;

    // Identity
    std::string name() const override { return "Color Wash"; }
    std::string description() const override {
        return "Fills the model with blended colors from the palette";
    }
    std::string category() const override { return "Patterns"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<ColorWashEffect>(*this);
    }

    // Capabilities
    bool supportsLinearColorCurves(const EffectSettings& settings) const override { return true; }
    int colorSupportedCount() const override { return -1; } // Unlimited colors

private:
    /**
     * @brief Get blended color at a specific position in the palette.
     *
     * @param palette Color palette to blend from
     * @param position Position in range [0, 1]
     * @param circular If true, wrap around to first color
     * @return Blended color
     */
    Color getMultiColorBlend(const std::vector<Color>& palette, double position, bool circular) const;
};

} // namespace xlCore
