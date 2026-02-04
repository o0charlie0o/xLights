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
 * @file StrobeEffect.h
 * @brief Strobe effect for xlCore - random flashing lights.
 *
 * This effect creates random strobe lights at random positions.
 * Each strobe has a duration and fades out over time.
 */

#include "../Effect.h"
#include <vector>
#include <random>

namespace xlCore {

/**
 * @brief Strobe effect - random flashing lights.
 *
 * Parameters:
 * - Number_Strobes: Number of simultaneous strobes (1-300, default: 3)
 * - Strobe_Duration: How long each strobe stays on in frames (1-100, default: 10)
 * - Strobe_Type: Shape of the strobe (1-4, default: 1)
 *   1 = Single pixel
 *   2 = Random 3-pixel line (horizontal or vertical)
 *   3 = Cross shape (5 pixels)
 *   4 = Random cross or X shape (5 pixels)
 */
class StrobeEffect : public Effect {
public:
    StrobeEffect() = default;
    ~StrobeEffect() override = default;

    // Identity
    std::string name() const override { return "Strobe"; }
    std::string description() const override {
        return "Creates random flashing strobe lights";
    }
    std::string category() const override { return "Patterns"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Lifecycle
    void prepareForRender(const EffectSettings& settings) override;
    void cleanupAfterRender() override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<StrobeEffect>(*this);
    }

    // Capabilities
    bool supportsRenderCache(const EffectSettings& settings) const override {
        return false; // Random elements make caching unreliable
    }
    int colorSupportedCount() const override { return -1; }

private:
    /**
     * @brief Internal state for a single strobe light.
     */
    struct StrobeLight {
        int x = 0;
        int y = 0;
        int duration = 0;      // Frames remaining
        int colorIndex = 0;
        Color color;
    };

    std::vector<StrobeLight> m_strobes;
    std::mt19937 m_rng;
    bool m_initialized = false;
};

} // namespace xlCore
