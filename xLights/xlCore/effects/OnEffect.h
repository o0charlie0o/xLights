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
 * @file OnEffect.h
 * @brief On effect for xlCore - fills model with a single color.
 *
 * This is a basic utility effect that fills the entire buffer with
 * the first palette color. Supports:
 * - Start/End brightness values for fading
 * - Shimmer (alternates between palette colors)
 * - Transparency
 * - Color cycling
 */

#include "../Effect.h"

namespace xlCore {

// Parameter limits
constexpr int ON_TRANSPARENCY_MIN = 0;
constexpr int ON_TRANSPARENCY_MAX = 100;

/**
 * @brief On effect - fills buffer with a solid color.
 *
 * Parameters:
 * - Start: Starting brightness percentage (0-100, default: 100)
 * - End: Ending brightness percentage (0-100, default: 100)
 * - Shimmer: Alternate between first two palette colors (default: false)
 * - Cycles: Number of cycles through the fade (default: 1.0)
 * - Transparency: Effect transparency (0-100, default: 0)
 */
class OnEffect : public Effect {
public:
    OnEffect() = default;
    ~OnEffect() override = default;

    // Identity
    std::string name() const override { return "On"; }
    std::string description() const override {
        return "Fills the model with a solid color from the palette";
    }
    std::string category() const override { return "Utility"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<OnEffect>(*this);
    }

    // Capabilities
    bool canBeRandom() const override { return false; }
    bool canRenderPartialTimeInterval() const override { return true; }
    bool supportsLinearColorCurves(const EffectSettings& settings) const override { return true; }
    bool supportsRadialColorCurves(const EffectSettings& settings) const override { return true; }
    int colorSupportedCount() const override { return -1; } // Unlimited

private:
    /**
     * @brief Get interpolation position considering cycles.
     */
    double getAdjustedPosition(double progress, double cycles) const;
};

} // namespace xlCore
