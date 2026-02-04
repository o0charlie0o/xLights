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
 * @file ServoEffect.h
 * @brief Servo effect for xlCore - controls DMX servo positions.
 *
 * This effect outputs DMX values for servo control. It supports
 * both 8-bit and 16-bit servo channels with position ramping.
 */

#include "../Effect.h"

namespace xlCore {

// Parameter limits
constexpr int SERVO_MIN = 0;
constexpr int SERVO_MAX = 1000;
constexpr int SERVO_DIVISOR = 10;

/**
 * @brief Servo effect - controls DMX servo positions.
 *
 * Parameters:
 * - Position: Servo position (0-100%)
 * - EndPosition: End position for ramping (0-100%)
 * - Channel: Target channel number (1-based)
 * - Is16Bit: Whether to use 16-bit output
 */
class ServoEffect : public Effect {
public:
    ServoEffect() = default;
    ~ServoEffect() override = default;

    // Identity
    std::string name() const override { return "Servo"; }
    std::string description() const override {
        return "Controls DMX servo positions";
    }
    std::string category() const override { return "Utility"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<ServoEffect>(*this);
    }

    // Capabilities
    bool canBeRandom() const override { return false; }
    bool canRenderPartialTimeInterval() const override { return true; }
    int colorSupportedCount() const override { return 0; }
};

} // namespace xlCore
