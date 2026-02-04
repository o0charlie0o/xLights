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
 * @file DMXEffect.h
 * @brief DMX effect for xlCore - direct DMX channel control.
 *
 * This effect provides direct control over DMX channels,
 * supporting up to 48 channels with independent values and inversion.
 */

#include "../Effect.h"

namespace xlCore {

// Parameter limits
constexpr int DMX_MIN = 0;
constexpr int DMX_MAX = 255;
constexpr int DMX_CHANNELS = 48;

/**
 * @brief DMX effect - direct DMX channel control.
 *
 * This effect outputs DMX values directly to channels.
 * Each of the 48 channels can have:
 * - A value (0-255) with optional value curve
 * - An invert checkbox to flip the value
 *
 * For single-color models, each channel maps to one pixel.
 * For RGB models, channels are grouped in sets of 3 (RGB order).
 */
class DMXEffect : public Effect {
public:
    DMXEffect() = default;
    ~DMXEffect() override = default;

    // Identity
    std::string name() const override { return "DMX"; }
    std::string description() const override {
        return "Direct DMX channel control";
    }
    std::string category() const override { return "Utility"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<DMXEffect>(*this);
    }

    // Capabilities
    bool canBeRandom() const override { return false; }
    bool canRenderPartialTimeInterval() const override { return true; }
    int colorSupportedCount() const override { return 0; }

private:
    // Helper to get DMX value for a channel
    int getDMXValue(const EffectSettings& settings, int channel) const;
};

} // namespace xlCore
