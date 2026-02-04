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
 * @file BarsEffect.h
 * @brief Bars effect for xlCore - moving color bars.
 *
 * This effect creates colored bars that move across the model
 * in various directions. Supports multiple bar count, gradient
 * between colors, 3D fading, and highlight lines.
 */

#include "../Effect.h"

namespace xlCore {

/**
 * @brief Direction for bar movement.
 */
enum class BarDirection {
    Up = 0,
    Down = 1,
    Expand = 2,
    Compress = 3,
    Left = 4,
    Right = 5,
    HExpand = 6,
    HCompress = 7,
    AlternateUp = 8,
    AlternateDown = 9,
    AlternateLeft = 10,
    AlternateRight = 11,
    CustomHorz = 12,
    CustomVert = 13
};

/**
 * @brief Bars effect - moving color bars.
 *
 * Parameters:
 * - BarCount: Number of bar repetitions (1-100, default: 1)
 * - Cycles: Number of animation cycles (0.1-100, default: 1.0)
 * - Direction: Direction of bar movement (default: Up)
 * - Center: Center offset for expand/compress (-100 to 100, default: 0)
 * - Highlight: Show highlight line at bar edge (default: false)
 * - 3D: Enable 3D fading effect (default: false)
 * - Gradient: Blend between colors (default: false)
 */
class BarsEffect : public Effect {
public:
    BarsEffect() = default;
    ~BarsEffect() override = default;

    // Identity
    std::string name() const override { return "Bars"; }
    std::string description() const override {
        return "Creates moving color bars";
    }
    std::string category() const override { return "Patterns"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<BarsEffect>(*this);
    }

    // Capabilities
    bool supportsLinearColorCurves(const EffectSettings& settings) const override { return true; }
    int colorSupportedCount() const override { return -1; } // Unlimited colors

private:
    /**
     * @brief Parse direction string to enum.
     */
    BarDirection parseDirection(const std::string& dirStr) const;

    /**
     * @brief Blend two colors based on percentage.
     */
    Color blendColors(const Color& c1, const Color& c2, double pct) const;

    /**
     * @brief Apply 3D fade and highlight effects to a color.
     */
    Color applyEffects(const Color& color, int barHeight, int posInBar,
                       bool highlight, bool show3D, bool allowAlpha,
                       const Color& highlightColor) const;
};

} // namespace xlCore
