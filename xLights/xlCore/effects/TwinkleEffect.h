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
 * @file TwinkleEffect.h
 * @brief Twinkle effect for xlCore - random twinkling lights.
 *
 * This effect creates randomly positioned lights that fade in and out,
 * creating a twinkling star-like appearance. Each twinkle has an
 * independent lifecycle.
 */

#include "../Effect.h"
#include <vector>
#include <random>

namespace xlCore {

/**
 * @brief Twinkle effect - random twinkling lights.
 *
 * Parameters:
 * - Count: Percentage of pixels to twinkle (1-100, default: 3)
 * - Steps: Number of frames for fade cycle (1-200, default: 30)
 * - Strobe: Flash instead of fade (default: false)
 * - ReRandom: Randomize color on each cycle (default: false)
 */
class TwinkleEffect : public Effect {
public:
    TwinkleEffect() = default;
    ~TwinkleEffect() override = default;

    // Identity
    std::string name() const override { return "Twinkle"; }
    std::string description() const override {
        return "Creates random twinkling lights that fade in and out";
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
        return std::make_unique<TwinkleEffect>(*this);
    }

    // Capabilities
    bool supportsRenderCache(const EffectSettings& settings) const override {
        return false; // Random elements make caching unreliable
    }
    int colorSupportedCount() const override { return -1; }

private:
    /**
     * @brief Internal state for a single twinkle light.
     */
    struct TwinkleLight {
        int x = 0;
        int y = 0;
        int duration = 0;      // Current position in fade cycle
        int colorIndex = 0;
        bool active = false;   // Is this light currently twinkling
    };

    std::vector<TwinkleLight> m_twinkles;
    std::mt19937 m_rng;
    bool m_initialized = false;
    int m_activeCount = 0;
    int m_lightsToRenew = 0;

    /**
     * @brief Place new twinkles in the buffer.
     */
    void placeTwinkles(int count, int maxDuration, size_t colorCount);
};

} // namespace xlCore
