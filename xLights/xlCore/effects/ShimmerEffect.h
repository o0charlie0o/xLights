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
 * @file ShimmerEffect.h
 * @brief Shimmer effect for xlCore - cycles colors with on/off periods.
 *
 * This effect fills the buffer with palette colors that cycle
 * on and off based on the duty factor. The shimmer creates a
 * flashing/pulsing appearance.
 */

#include "../Effect.h"

namespace xlCore {

/**
 * @brief Shimmer effect - cycles palette colors with duty factor.
 *
 * Parameters:
 * - Duty_Factor: Percentage of time the effect is "on" (1-100, default: 50)
 * - Cycles: Number of on/off cycles during the effect (default: 1.0)
 * - Use_All_Colors: Randomly assign colors to each pixel (default: false)
 */
class ShimmerEffect : public Effect {
public:
    ShimmerEffect() = default;
    ~ShimmerEffect() override = default;

    // Identity
    std::string name() const override { return "Shimmer"; }
    std::string description() const override {
        return "Cycles palette colors on and off with a duty factor";
    }
    std::string category() const override { return "Patterns"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<ShimmerEffect>(*this);
    }

    // Capabilities
    int colorSupportedCount() const override { return -1; } // Unlimited colors
};

} // namespace xlCore
