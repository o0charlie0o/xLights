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
 * @file SingleStrandEffect.h
 * @brief Single Strand effect for xlCore - chase and skip patterns.
 *
 * This effect provides chase patterns, skip patterns, and other
 * single-strand animations commonly used in lighting displays.
 */

#include "../Effect.h"

namespace xlCore {

// Parameter limits
constexpr int SINGLESTRAND_ROTATIONS_MIN = 1;
constexpr int SINGLESTRAND_ROTATIONS_MAX = 500;
constexpr int SINGLESTRAND_ROTATIONS_DIVISOR = 10;

constexpr int SINGLESTRAND_CHASES_MIN = 1;
constexpr int SINGLESTRAND_CHASES_MAX = 20;

constexpr int SINGLESTRAND_COLOURMIX_MIN = 1;
constexpr int SINGLESTRAND_COLOURMIX_MAX = 100;

constexpr int SINGLESTRAND_OFFSET_MIN = -5000;
constexpr int SINGLESTRAND_OFFSET_MAX = 5000;
constexpr int SINGLESTRAND_OFFSET_DIVISOR = 10;

constexpr int SINGLESTRAND_BANDSIZE_MIN = 1;
constexpr int SINGLESTRAND_BANDSIZE_MAX = 100;

constexpr int SINGLESTRAND_SKIPSIZE_MIN = 1;
constexpr int SINGLESTRAND_SKIPSIZE_MAX = 100;

/**
 * @brief Single Strand effect - chase and skip patterns.
 *
 * Effect Types:
 * - Chase: Moving light patterns along the strand
 * - Skips: Alternating colored bands
 *
 * Parameters:
 * - EffectType: "Chase" or "Skips"
 * - NumberChases: Number of simultaneous chases (1-20)
 * - ChaseSize: Width of chase in percentage (1-100)
 * - ChaseType: Direction and style of chase
 * - Rotations: Speed/number of complete cycles (0.1-50)
 * - BandSize: Width of color bands for skips (1-100)
 * - SkipSize: Width of skip gaps (1-100)
 */
class SingleStrandEffect : public Effect {
public:
    SingleStrandEffect() = default;
    ~SingleStrandEffect() override = default;

    // Identity
    std::string name() const override { return "Single Strand"; }
    std::string description() const override {
        return "Chase and skip patterns for single strands";
    }
    std::string category() const override { return "Utility"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<SingleStrandEffect>(*this);
    }

    // Capabilities
    bool supportsLinearColorCurves() const override { return true; }
    bool canRenderPartialTimeInterval() const override { return true; }
    int colorSupportedCount() const override { return -1; }

private:
    // Chase type enumeration
    enum class ChaseType {
        LeftRight = 0,
        RightLeft,
        BounceFromLeft,
        BounceFromRight,
        DualChase,
        FromMiddle,
        ToMiddle,
        BounceToMiddle,
        BounceFromMiddle
    };

    // Rendering helpers
    void renderChase(RenderContext& ctx, const EffectSettings& settings, const RenderState& state);
    void renderSkips(RenderContext& ctx, const EffectSettings& settings, const RenderState& state);

    void drawChase(RenderContext& ctx, int x, int width, int chaseWidth,
                   const std::string& fadeType, bool reverse, bool mirror,
                   const std::vector<Color>& colors);

    static ChaseType parseChaseType(const std::string& type);
};

} // namespace xlCore
