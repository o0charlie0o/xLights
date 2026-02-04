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
 * @file WaveEffect.h
 * @brief Wave effect for xlCore.
 *
 * Creates animated wave patterns with configurable:
 * - Wave type (sine, triangle, square, decaying sine, fractal)
 * - Fill colors (none, rainbow, palette)
 * - Speed and direction
 * - Mirror mode
 */

#include "../Effect.h"
#include <vector>

namespace xlCore {

/**
 * @brief Wave effect - creates animated wave patterns.
 *
 * Parameters:
 * - Type: Wave type (Sine, Triangle, Square, Decaying Sine, Fractal/ivy)
 * - FillColors: Fill mode (None, Rainbow, Palette)
 * - NumberWaves: Number of waves across buffer (1-3600, default: 900)
 * - Thickness: Wave thickness percentage (1-100, default: 5)
 * - Height: Wave height percentage (0-100, default: 50)
 * - Speed: Animation speed (0-5000, default: 1000)
 * - YOffset: Vertical offset (-100 to 100, default: 0)
 * - Direction: Wave direction (Left to Right, Right to Left)
 * - Mirror: Mirror the wave (default: false)
 */
class WaveEffect : public Effect {
public:
    enum class WaveType {
        Sine,
        Triangle,
        Square,
        DecaySine,
        IvyFractal
    };

    enum class FillColorType {
        None,
        Rainbow,
        Palette
    };

    WaveEffect() = default;
    ~WaveEffect() override = default;

    // Identity
    std::string name() const override { return "Wave"; }
    std::string description() const override {
        return "Creates animated wave patterns";
    }
    std::string category() const override { return "3D"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Lifecycle
    void prepareForRender(const EffectSettings& settings) override;
    void cleanupAfterRender() override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<WaveEffect>(*this);
    }

    // Capabilities
    int colorSupportedCount() const override { return -1; }

private:
    static WaveType parseWaveType(const std::string& str);
    static FillColorType parseFillColor(const std::string& str);

    // Cache for fractal/ivy wave pattern
    std::vector<int> m_waveBuffer;
    int m_lastNumWaves = 0;
    int m_lastWidth = 0;
};

} // namespace xlCore
