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
 * @file SpirographEffect.h
 * @brief Spirograph effect for xlCore - draws hypotrochoid patterns.
 *
 * A hypotrochoid is a roulette traced by a point attached to a circle
 * of radius r rolling around the inside of a fixed circle of radius R,
 * where the point is a distance d from the center of the interior circle.
 */

#include "../Effect.h"

namespace xlCore {

// Parameter limits
constexpr int SPIROGRAPH_ANIMATE_MIN = -50;
constexpr int SPIROGRAPH_ANIMATE_MAX = 50;

constexpr int SPIROGRAPH_LENGTH_MIN = 0;
constexpr int SPIROGRAPH_LENGTH_MAX = 50;

constexpr int SPIROGRAPH_WIDTH_MIN = 1;
constexpr int SPIROGRAPH_WIDTH_MAX = 50;

constexpr int SPIROGRAPH_R_MIN = 1;
constexpr int SPIROGRAPH_R_MAX = 100;

constexpr int SPIROGRAPH_r_MIN = 1;
constexpr int SPIROGRAPH_r_MAX = 100;

constexpr int SPIROGRAPH_SPEED_MIN = 0;
constexpr int SPIROGRAPH_SPEED_MAX = 50;

constexpr int SPIROGRAPH_d_MIN = 1;
constexpr int SPIROGRAPH_d_MAX = 100;

/**
 * @brief Spirograph effect - draws hypotrochoid patterns.
 *
 * Parameters:
 * - R: Radius of large circle (1-100, default: 20)
 * - r: Radius of small circle (1-100, default: 10)
 * - d: Distance from center (1-100, default: 30)
 * - Animate: Animation factor (-50 to 50, default: 0)
 * - Speed: Animation speed (0-50, default: 10)
 * - Length: Pattern length (0-50, default: 20)
 * - Width: Line width (1-50, default: 1)
 */
class SpirographEffect : public Effect {
public:
    SpirographEffect() = default;
    ~SpirographEffect() override = default;

    // Identity
    std::string name() const override { return "Spirograph"; }
    std::string description() const override {
        return "Draws hypotrochoid (spirograph) patterns";
    }
    std::string category() const override { return "Utility"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<SpirographEffect>(*this);
    }

    // Capabilities
    bool appropriateOnNodes() const override { return false; }
    bool canRenderPartialTimeInterval() const override { return true; }
    int colorSupportedCount() const override { return -1; }
};

} // namespace xlCore
