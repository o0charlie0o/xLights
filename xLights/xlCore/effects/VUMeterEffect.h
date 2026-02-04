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
 * @file VUMeterEffect.h
 * @brief Audio level visualization effect.
 *
 * Provides multiple visualization styles for audio levels:
 * - Volume Bars: Traditional VU meter bars showing volume history
 * - Spectrogram: Frequency spectrum visualization
 * - Waveform: Audio waveform display
 * - Level shapes: Shapes that scale with audio level
 * - On/Color: Fill with color based on audio level
 *
 * This is the xlCore implementation, replacing the wx-dependent version.
 */

#include "AudioReactiveEffect.h"
#include "../XLMath.h"

#include <vector>
#include <list>
#include <memory>

namespace xlCore {

/**
 * @brief VU meter visualization type.
 */
enum class VUMeterType {
    Spectrogram,
    VolumeBars,
    Waveform,
    On,
    IntensityWave,
    LevelPulse,
    LevelShape,
    ColorOn,
    LevelBar,
    LevelColor,
    DominantFrequencyColour,
    SpectrogramPeak,
    SpectrogramLine,
    FrameWaveform
};

/**
 * @brief Shape type for level shape visualization.
 */
enum class VUMeterShape {
    Circle,
    FilledCircle,
    Square,
    FilledSquare,
    Diamond,
    FilledDiamond,
    Star,
    FilledStar,
    Heart,
    FilledHeart
};

/**
 * @brief Render state for VU Meter effect.
 */
struct VUMeterState {
    std::vector<float> lastValues;      // Previous bar/band values (for smoothing)
    std::vector<float> lastPeaks;       // Peak hold values
    std::vector<int> peakHoldCounters;  // Frames until peak drops
    float lastSize = 0.0f;              // For level shape
    int colorIndex = 0;                 // For color cycling
    std::list<std::vector<Point2D>> lineHistory;  // For spectrogram trails

    void reset() {
        lastValues.clear();
        lastPeaks.clear();
        peakHoldCounters.clear();
        lastSize = 0.0f;
        colorIndex = 0;
        lineHistory.clear();
    }
};

/**
 * @brief VU Meter audio visualization effect.
 *
 * A comprehensive audio visualization effect that provides multiple
 * display modes for visualizing audio levels and spectrum data.
 *
 * Parameters:
 * - Type: Visualization style (spectrogram, bars, waveform, etc.)
 * - Bars: Number of bars/bands to display
 * - Sensitivity: Threshold for triggering (0-100)
 * - Gain: Volume adjustment in dB (-20 to +20)
 * - SlowDownFalls: Enable gradual fall of levels
 * - StartNote/EndNote: MIDI note range for spectrum
 * - XOffset/YOffset: Position adjustment
 * - Shape: Shape for level shape mode
 * - LogarithmicX: Use logarithmic frequency scale
 */
class VUMeterEffect : public AudioReactiveEffect {
public:
    VUMeterEffect();
    ~VUMeterEffect() override = default;

    // Identity
    std::string name() const override { return "VU Meter"; }
    std::string description() const override {
        return "Audio level visualization with multiple display styles";
    }
    std::string tooltip() const override {
        return "Visualize audio levels as bars, spectrum, waveform, or shapes";
    }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings,
                const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<VUMeterEffect>(*this);
    }

    // Lifecycle
    void prepareForRender(const EffectSettings& settings) override;
    void cleanupAfterRender() override;

    // Capabilities
    bool supportsRenderCache(const EffectSettings& settings) const override {
        return false;  // Audio-reactive effects are not cacheable
    }

    bool canBeRandom() const override {
        return false;  // Requires audio to be meaningful
    }

private:
    // State (per-instance for thread safety)
    VUMeterState m_state;

    // Render type dispatch
    void renderSpectrogram(RenderContext& ctx, const AudioContext& audio,
                           const EffectSettings& settings, int bars, int startNote,
                           int endNote, int xOffset, int yOffset, int gain,
                           bool slowDownFalls, bool logarithmic, bool showPeaks,
                           int peakHold, bool lineMode, bool circleMode, int sensitivity);

    void renderVolumeBars(RenderContext& ctx, const AudioContext& audio,
                          const EffectSettings& settings, int bars, int gain);

    void renderWaveform(RenderContext& ctx, const AudioContext& audio,
                        const EffectSettings& settings, int bars, int yOffset,
                        int gain, bool frameDetail);

    void renderOn(RenderContext& ctx, const AudioContext& audio,
                  const EffectSettings& settings, int gain);

    void renderColorOn(RenderContext& ctx, const AudioContext& audio,
                       const EffectSettings& settings, int gain);

    void renderIntensityWave(RenderContext& ctx, const AudioContext& audio,
                             const EffectSettings& settings, int bars, int gain);

    void renderLevelPulse(RenderContext& ctx, const AudioContext& audio,
                          const EffectSettings& settings, int bars, int sensitivity,
                          int gain);

    void renderLevelShape(RenderContext& ctx, const AudioContext& audio,
                          const EffectSettings& settings, VUMeterShape shape,
                          int sensitivity, bool slowDownFalls, int xOffset,
                          int yOffset, int bars, int gain);

    void renderLevelBar(RenderContext& ctx, const AudioContext& audio,
                        const EffectSettings& settings, int bars, int sensitivity,
                        int gain, bool random);

    void renderLevelColor(RenderContext& ctx, const AudioContext& audio,
                          const EffectSettings& settings, int sensitivity, int gain);

    void renderDominantFrequencyColour(RenderContext& ctx, const AudioContext& audio,
                                       const EffectSettings& settings, int sensitivity,
                                       int startNote, int endNote, bool gradient);

    // Helper methods
    static VUMeterType decodeType(const std::string& type);
    static VUMeterShape decodeShape(const std::string& shape);

    void drawShape(RenderContext& ctx, VUMeterShape shape, int cx, int cy,
                   int size, const Color& color, bool filled);

    void updatePeaks(std::vector<float>& peaks, const std::vector<float>& current,
                     std::vector<int>& holdCounters, int holdFrames, float fallRate);
};

} // namespace xlCore
