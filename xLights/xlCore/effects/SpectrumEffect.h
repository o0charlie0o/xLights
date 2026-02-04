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
 * @file SpectrumEffect.h
 * @brief Audio spectrum analyzer visualization effect.
 *
 * Provides a dedicated spectrum analyzer display that visualizes
 * audio frequency content in real-time. Simpler and more focused
 * than VUMeter's spectrogram mode.
 *
 * Features:
 * - Multiple display styles (bars, lines, filled)
 * - Peak hold with configurable decay
 * - Logarithmic or linear frequency scaling
 * - Configurable frequency range (MIDI note-based)
 * - Gradient coloring based on frequency or amplitude
 */

#include "AudioReactiveEffect.h"

#include <vector>
#include <memory>

namespace xlCore {

/**
 * @brief Spectrum display style.
 */
enum class SpectrumStyle {
    Bars,           // Traditional vertical bars
    Lines,          // Connected line graph
    FilledLines,    // Line graph with fill below
    Mirror,         // Bars mirrored top/bottom
    Radial          // Circular display
};

/**
 * @brief Spectrum color mode.
 */
enum class SpectrumColorMode {
    Amplitude,      // Color based on amplitude
    Frequency,      // Color based on frequency band
    Gradient,       // Fixed gradient across bands
    Rainbow         // Rainbow spectrum
};

/**
 * @brief State for Spectrum effect.
 */
struct SpectrumState {
    std::vector<float> lastLevels;      // Previous frame levels (for smoothing)
    std::vector<float> peakLevels;      // Peak hold levels
    std::vector<int> peakHoldFrames;    // Frames until peak decays

    void reset() {
        lastLevels.clear();
        peakLevels.clear();
        peakHoldFrames.clear();
    }
};

/**
 * @brief Audio spectrum analyzer effect.
 *
 * A focused spectrum analyzer visualization that displays audio
 * frequency content with various styling options.
 *
 * Parameters:
 * - Bars: Number of frequency bars
 * - Style: Display style (bars, lines, filled, etc.)
 * - ColorMode: How colors are assigned
 * - StartNote/EndNote: Frequency range as MIDI notes
 * - Logarithmic: Use logarithmic frequency scale
 * - PeakHold: Show peak levels
 * - PeakDecay: Peak decay speed
 * - Smoothing: Level smoothing amount
 * - Gain: Audio gain adjustment
 */
class SpectrumEffect : public AudioReactiveEffect {
public:
    SpectrumEffect();
    ~SpectrumEffect() override = default;

    // Identity
    std::string name() const override { return "Spectrum"; }
    std::string description() const override {
        return "Audio spectrum analyzer visualization";
    }
    std::string tooltip() const override {
        return "Real-time audio spectrum display with multiple styles";
    }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings,
                const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<SpectrumEffect>(*this);
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
    SpectrumState m_state;

    // Render methods for each style
    void renderBars(RenderContext& ctx, const EffectSettings& settings,
                    const std::vector<float>& levels, const std::vector<float>& peaks,
                    SpectrumColorMode colorMode, bool showPeaks);

    void renderLines(RenderContext& ctx, const EffectSettings& settings,
                     const std::vector<float>& levels, SpectrumColorMode colorMode,
                     bool filled);

    void renderMirror(RenderContext& ctx, const EffectSettings& settings,
                      const std::vector<float>& levels, const std::vector<float>& peaks,
                      SpectrumColorMode colorMode, bool showPeaks);

    void renderRadial(RenderContext& ctx, const EffectSettings& settings,
                      const std::vector<float>& levels, SpectrumColorMode colorMode);

    // Helpers
    static SpectrumStyle decodeStyle(const std::string& style);
    static SpectrumColorMode decodeColorMode(const std::string& mode);

    Color getBarColor(int bar, int totalBars, float level, SpectrumColorMode mode) const;
};

} // namespace xlCore
