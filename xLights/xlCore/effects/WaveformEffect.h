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
 * @file WaveformEffect.h
 * @brief Audio waveform visualization effect.
 *
 * Displays the audio waveform in various styles. Can show either
 * real-time waveform data from the audio analyzer or a scrolling
 * history of audio levels.
 *
 * Features:
 * - Real-time sample display
 * - Scrolling waveform history
 * - Multiple display styles
 * - Vertical centering and offset
 * - Configurable resolution
 */

#include "AudioReactiveEffect.h"

#include <vector>
#include <deque>
#include <memory>

namespace xlCore {

/**
 * @brief Waveform display style.
 */
enum class WaveformStyle {
    Line,           // Connected line graph
    Filled,         // Filled area from center
    Bars,           // Vertical bars from center
    Dots            // Individual sample points
};

/**
 * @brief Waveform data source.
 */
enum class WaveformSource {
    RealTime,       // Real-time audio samples for current frame
    History         // Scrolling history of RMS levels
};

/**
 * @brief State for Waveform effect.
 */
struct WaveformState {
    std::deque<float> levelHistory;     // History of audio levels
    std::vector<float> lastWaveform;    // Last waveform data

    void reset() {
        levelHistory.clear();
        lastWaveform.clear();
    }
};

/**
 * @brief Audio waveform visualization effect.
 *
 * Displays audio waveform data in various visual styles.
 *
 * Parameters:
 * - Style: Display style (line, filled, bars, dots)
 * - Source: Data source (realtime, history)
 * - Resolution: Number of samples/bars to display
 * - YOffset: Vertical offset (-100 to 100)
 * - Gain: Audio gain adjustment (-20 to 20 dB)
 * - Smoothing: Level smoothing amount
 */
class WaveformEffect : public AudioReactiveEffect {
public:
    WaveformEffect();
    ~WaveformEffect() override = default;

    // Identity
    std::string name() const override { return "Waveform"; }
    std::string description() const override {
        return "Audio waveform visualization";
    }
    std::string tooltip() const override {
        return "Display audio waveform as a scrolling or real-time visualization";
    }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings,
                const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<WaveformEffect>(*this);
    }

    // Lifecycle
    void prepareForRender(const EffectSettings& settings) override;
    void cleanupAfterRender() override;

    // Capabilities
    bool supportsRenderCache(const EffectSettings& settings) const override {
        return false;  // Audio-reactive
    }

    bool canBeRandom() const override {
        return false;  // Requires audio
    }

private:
    WaveformState m_state;

    // Render methods for each style
    void renderLine(RenderContext& ctx, const EffectSettings& settings,
                    const std::vector<float>& samples, int yOffset, bool filled);

    void renderBars(RenderContext& ctx, const EffectSettings& settings,
                    const std::vector<float>& samples, int yOffset);

    void renderDots(RenderContext& ctx, const EffectSettings& settings,
                    const std::vector<float>& samples, int yOffset);

    // Helpers
    static WaveformStyle decodeStyle(const std::string& style);
    static WaveformSource decodeSource(const std::string& source);

    Color getWaveformColor(const EffectSettings& settings, float amplitude) const;
};

} // namespace xlCore
