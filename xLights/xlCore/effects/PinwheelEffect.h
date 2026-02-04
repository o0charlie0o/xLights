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
 * @file PinwheelEffect.h
 * @brief Pinwheel effect for xlCore.
 *
 * Creates rotating pinwheel/spiral arm patterns with configurable:
 * - Number of arms
 * - Rotation speed and direction
 * - Twist amount
 * - 3D shading modes
 * - Center position
 */

#include "../Effect.h"

namespace xlCore {

/**
 * @brief Pinwheel effect - creates rotating spiral arm patterns.
 *
 * Parameters:
 * - Arms: Number of pinwheel arms (1-20, default: 3)
 * - Twist: Amount of twist per arm (0-360, default: 0)
 * - Thickness: Arm thickness percentage (0-100, default: 0)
 * - Rotation: Clockwise rotation (default: true)
 * - Speed: Rotation speed (0-50, default: 10)
 * - CenterX: Horizontal center offset (-100 to 100, default: 0)
 * - CenterY: Vertical center offset (-100 to 100, default: 0)
 * - ArmSize: Arm length percentage (0-400, default: 100)
 * - Offset: Starting angle offset (0-360, default: 0)
 * - 3D: 3D shading mode (none, 3D, 3D Inverted, Sweep)
 */
class PinwheelEffect : public Effect {
public:
    enum class Pinwheel3DType {
        None,
        ThreeD,
        ThreeDInverted,
        Sweep
    };

    PinwheelEffect() = default;
    ~PinwheelEffect() override = default;

    // Identity
    std::string name() const override { return "Pinwheel"; }
    std::string description() const override {
        return "Creates rotating pinwheel/spiral arm patterns";
    }
    std::string category() const override { return "3D"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<PinwheelEffect>(*this);
    }

    // Capabilities
    int colorSupportedCount() const override { return -1; } // Unlimited colors

private:
    // Parse 3D type from string
    static Pinwheel3DType to3DType(const std::string& str);

    // Adjust color for 3D effect
    void adjustColor(Pinwheel3DType type, Color& color, bool allowAlpha, float round) const;

    // Draw a single arm
    void drawArm(RenderContext& ctx, int baseDegrees, int maxRadius, int twist,
                int xcAdj, int ycAdj, const Color& color, Pinwheel3DType type,
                float round, bool allowAlpha) const;
};

} // namespace xlCore
