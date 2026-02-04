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
 * @file OffEffect.h
 * @brief Off effect for xlCore - turns off or makes pixels transparent.
 *
 * This is a utility effect that either:
 * - Sets all pixels to black (default)
 * - Makes all pixels transparent
 * - Converts black pixels to transparent
 * - Converts transparent pixels to black
 */

#include "../Effect.h"

namespace xlCore {

/**
 * @brief Off effect - turns pixels off or makes them transparent.
 *
 * Parameters:
 * - Style: "Black", "Transparent", "Black -> Transparent", "Transparent -> Black"
 */
class OffEffect : public Effect {
public:
    OffEffect() = default;
    ~OffEffect() override = default;

    // Identity
    std::string name() const override { return "Off"; }
    std::string description() const override {
        return "Turns off pixels or makes them transparent";
    }
    std::string category() const override { return "Utility"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<OffEffect>(*this);
    }

    // Capabilities
    bool canBeRandom() const override { return false; }
    bool canRenderPartialTimeInterval() const override { return true; }
    int colorSupportedCount() const override { return 0; } // No colors needed

private:
    // Style enumeration
    enum class OffStyle {
        Black,
        Transparent,
        BlackToTransparent,
        TransparentToBlack
    };

    static OffStyle parseStyle(const std::string& style);
};

} // namespace xlCore
