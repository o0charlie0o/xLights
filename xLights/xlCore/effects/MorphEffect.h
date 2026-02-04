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
 * @file MorphEffect.h
 * @brief Pure C++ morph/line animation effect for xlCore.
 *
 * This effect creates animated morphing lines that transition from
 * one position/shape to another. Commonly used for wipe transitions
 * and shape morphing animations.
 *
 * Features:
 * - Start and end line positions (two endpoints each)
 * - Head (leading edge) and tail (trailing edge) with different colors
 * - Configurable duration/timing for head vs tail
 * - Repeat/stagger for filling effects
 * - Acceleration for easing
 */

#include "../Effect.h"

#include <string>
#include <vector>
#include <memory>

namespace xlCore {

/**
 * @brief Morph effect for animated line transitions.
 *
 * Renders a line that morphs from one position to another,
 * with separate head and tail colors/timing.
 */
class MorphEffect : public Effect {
public:
    MorphEffect();
    ~MorphEffect() override = default;

    // Identity
    std::string name() const override { return "Morph"; }
    std::string description() const override { return "Animated morphing line transition"; }
    std::string category() const override { return "Patterns"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Capabilities
    bool canRenderPartialTimeInterval() const override { return true; }

    // Cloning
    std::unique_ptr<Effect> clone() const override;

protected:
    /**
     * @brief Store points along a line using Bresenham's algorithm.
     */
    void storeLine(int x0, int y0, int x1, int y1,
                   std::vector<int>& vx, std::vector<int>& vy) const;

    /**
     * @brief Calculate position on grid from percentage.
     */
    int calcPosition(int value, int base) const;

    /**
     * @brief Apply acceleration curve to progress.
     */
    double applyAcceleration(double progress, int acceleration) const;

    /**
     * @brief Blend between two colors.
     */
    Color blendColors(const Color& c1, const Color& c2, double ratio) const;
};

} // namespace xlCore
