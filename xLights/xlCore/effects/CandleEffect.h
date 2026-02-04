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
 * @file CandleEffect.h
 * @brief Candle effect for xlCore - simulates flickering candle flames.
 *
 * This effect creates realistic candle flame animations using a
 * wind/flame physics model. Each pixel can optionally have its
 * own independent flame state.
 */

#include "../Effect.h"

#include <vector>
#include <cstdint>

namespace xlCore {

// Parameter limits
constexpr int CANDLE_AGILITY_MIN = 1;
constexpr int CANDLE_AGILITY_MAX = 10;

constexpr int CANDLE_WINDBASELINE_MIN = 0;
constexpr int CANDLE_WINDBASELINE_MAX = 255;

constexpr int CANDLE_WINDVARIABILITY_MIN = 0;
constexpr int CANDLE_WINDVARIABILITY_MAX = 10;

constexpr int CANDLE_WINDCALMNESS_MIN = 0;
constexpr int CANDLE_WINDCALMNESS_MAX = 10;

/**
 * @brief Candle effect - simulates flickering candle flames.
 *
 * Parameters:
 * - FlameAgility: How quickly flame responds (1-10, default: 2)
 * - WindBaseline: Base wind level (0-255, default: 30)
 * - WindVariability: Gust frequency (0-10, default: 5)
 * - WindCalmness: Wind reduction factor (0-10, default: 2)
 * - PerNode: Independent flame per pixel (default: false)
 * - UsePalette: Use palette colors instead of flame colors (default: false)
 */
class CandleEffect : public Effect {
public:
    CandleEffect() = default;
    ~CandleEffect() override = default;

    // Identity
    std::string name() const override { return "Candle"; }
    std::string description() const override {
        return "Simulates flickering candle flame animation";
    }
    std::string category() const override { return "Utility"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Lifecycle
    void prepareForRender(const EffectSettings& settings) override;
    void cleanupAfterRender() override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<CandleEffect>(*this);
    }

    // Capabilities
    int colorSupportedCount() const override { return 2; } // Two colors for palette mode

private:
    /**
     * @brief State for a single candle flame.
     */
    struct CandleState {
        uint8_t flameprimer = 0;  ///< Low-pass filtered flame red
        uint8_t flamer = 0;       ///< Raw flame red value
        uint8_t wind = 0;         ///< Current wind level
        uint8_t flameprimeg = 0;  ///< Low-pass filtered flame green
        uint8_t flameg = 0;       ///< Raw flame green value

        void init();
    };

    /**
     * @brief Update flame state based on wind and parameters.
     */
    void updateFlame(uint8_t& flameprime, uint8_t& flame, uint8_t& wind,
                     int windVariability, int flameAgility,
                     int windCalmness, int windBaseline) const;

    // Render state
    std::vector<CandleState> m_states;
    bool m_initialized = false;
};

} // namespace xlCore
