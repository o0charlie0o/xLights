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
 * @file AudioReactiveEffect.h
 * @brief Base class for audio-reactive effects.
 *
 * Provides a common foundation for effects that respond to audio data.
 * Includes helpers for accessing audio analyzer data and common audio
 * processing functions like smoothing and band extraction.
 */

#include "../Effect.h"
#include "../Audio.h"

#include <memory>
#include <vector>
#include <cmath>

namespace xlCore {

/**
 * @brief Audio context passed to audio-reactive effects.
 *
 * Contains an AudioAnalyzer reference and caches common audio data
 * to avoid repeated calculations within a single frame.
 */
struct AudioContext {
    const AudioAnalyzer* analyzer = nullptr;
    double currentTimeSeconds = 0.0;

    // Cached audio data (computed on demand)
    mutable float cachedRMSLevel = -1.0f;
    mutable float cachedPeakLevel = -1.0f;
    mutable std::vector<float> cachedSpectrum;

    AudioContext() = default;
    AudioContext(const AudioAnalyzer* a, double time)
        : analyzer(a), currentTimeSeconds(time) {}

    /**
     * @brief Get RMS level at current time.
     * @param windowSeconds Analysis window size (default 50ms)
     */
    float getRMSLevel(double windowSeconds = 0.05) const {
        if (cachedRMSLevel < 0.0f && analyzer) {
            cachedRMSLevel = analyzer->getRMSLevel(currentTimeSeconds, windowSeconds);
        }
        return cachedRMSLevel >= 0.0f ? cachedRMSLevel : 0.0f;
    }

    /**
     * @brief Get peak level at current time.
     * @param windowSeconds Analysis window size (default 50ms)
     */
    float getPeakLevel(double windowSeconds = 0.05) const {
        if (cachedPeakLevel < 0.0f && analyzer) {
            cachedPeakLevel = analyzer->getPeakLevel(currentTimeSeconds, windowSeconds);
        }
        return cachedPeakLevel >= 0.0f ? cachedPeakLevel : 0.0f;
    }

    /**
     * @brief Get spectrum data at current time.
     * @param numBands Number of frequency bands
     */
    const std::vector<float>& getSpectrum(size_t numBands = 512) const {
        if (cachedSpectrum.empty() && analyzer) {
            cachedSpectrum = analyzer->getSpectrum(currentTimeSeconds, numBands);
        }
        return cachedSpectrum;
    }

    /**
     * @brief Check if audio is available.
     */
    bool hasAudio() const { return analyzer != nullptr && analyzer->isLoaded(); }

    /**
     * @brief Clear cached values (call if time changes).
     */
    void clearCache() const {
        cachedRMSLevel = -1.0f;
        cachedPeakLevel = -1.0f;
        cachedSpectrum.clear();
    }
};

/**
 * @brief Standard frequency band definitions for audio visualization.
 */
struct FrequencyBands {
    // Band boundaries in Hz
    static constexpr float SubBass_Low = 20.0f;
    static constexpr float SubBass_High = 60.0f;
    static constexpr float Bass_Low = 60.0f;
    static constexpr float Bass_High = 250.0f;
    static constexpr float LowMid_Low = 250.0f;
    static constexpr float LowMid_High = 500.0f;
    static constexpr float Mid_Low = 500.0f;
    static constexpr float Mid_High = 2000.0f;
    static constexpr float HighMid_Low = 2000.0f;
    static constexpr float HighMid_High = 4000.0f;
    static constexpr float Presence_Low = 4000.0f;
    static constexpr float Presence_High = 6000.0f;
    static constexpr float Brilliance_Low = 6000.0f;
    static constexpr float Brilliance_High = 20000.0f;

    /**
     * @brief MIDI note to frequency conversion.
     * A4 (MIDI note 69) = 440 Hz
     */
    static float midiNoteToFrequency(int note) {
        return 440.0f * std::pow(2.0f, (note - 69) / 12.0f);
    }

    /**
     * @brief Frequency to MIDI note conversion.
     */
    static int frequencyToMidiNote(float freq) {
        return static_cast<int>(69.0f + 12.0f * std::log2(freq / 440.0f));
    }

    /**
     * @brief Get frequency bin index for a given frequency.
     * @param freq Frequency in Hz
     * @param sampleRate Audio sample rate
     * @param fftSize FFT size (number of bins * 2)
     */
    static int frequencyToBin(float freq, int sampleRate, int fftSize) {
        return static_cast<int>(freq * fftSize / sampleRate);
    }

    /**
     * @brief Get frequency for a given bin index.
     */
    static float binToFrequency(int bin, int sampleRate, int fftSize) {
        return static_cast<float>(bin) * sampleRate / fftSize;
    }
};

/**
 * @brief Base class for audio-reactive effects.
 *
 * Provides common functionality for effects that respond to audio:
 * - Access to audio analyzer
 * - Gain application
 * - Level smoothing (attack/release)
 * - Frequency band extraction
 *
 * Subclasses implement specific visualization algorithms.
 */
class AudioReactiveEffect : public Effect {
public:
    ~AudioReactiveEffect() override = default;

    /**
     * @brief Audio-reactive effects belong to the "Audio" category.
     */
    std::string category() const override { return "Audio"; }

protected:
    AudioReactiveEffect() = default;

    /**
     * @brief Apply gain to a level value.
     * @param level Input level (0.0 to 1.0)
     * @param gain Gain in dB (-20 to +20 typical)
     * @return Adjusted level, clamped to 0.0-1.0
     */
    static float applyGain(float level, int gainDB) {
        if (gainDB == 0) return level;

        // Convert dB to linear multiplier: 10^(dB/20)
        float multiplier = std::pow(10.0f, gainDB / 20.0f);
        float result = level * multiplier;

        // Clamp to valid range
        return std::clamp(result, 0.0f, 1.0f);
    }

    /**
     * @brief Apply smoothing to a level change (attack/release envelope).
     * @param currentLevel Current level
     * @param targetLevel Target level
     * @param attackRate Attack rate (0.0 to 1.0, higher = faster rise)
     * @param releaseRate Release rate (0.0 to 1.0, higher = faster fall)
     * @return Smoothed level
     */
    static float smoothLevel(float currentLevel, float targetLevel,
                             float attackRate = 0.3f, float releaseRate = 0.1f) {
        if (targetLevel > currentLevel) {
            // Attack
            return currentLevel + (targetLevel - currentLevel) * attackRate;
        } else {
            // Release
            return currentLevel + (targetLevel - currentLevel) * releaseRate;
        }
    }

    /**
     * @brief Extract levels for frequency bands from spectrum data.
     * @param spectrum Full spectrum data
     * @param numBands Number of output bands
     * @param startNote Starting MIDI note
     * @param endNote Ending MIDI note
     * @param sampleRate Audio sample rate
     * @param logarithmic Use logarithmic frequency scaling
     * @return Vector of band levels (0.0 to 1.0)
     */
    static std::vector<float> extractBandLevels(
        const std::vector<float>& spectrum,
        int numBands,
        int startNote,
        int endNote,
        int sampleRate = 44100,
        bool logarithmic = false);

    /**
     * @brief Get dominant frequency from spectrum.
     * @param spectrum Spectrum data
     * @param sampleRate Audio sample rate
     * @param startNote Starting MIDI note for search
     * @param endNote Ending MIDI note for search
     * @return Dominant frequency in Hz, or 0 if not found
     */
    static float getDominantFrequency(
        const std::vector<float>& spectrum,
        int sampleRate = 44100,
        int startNote = 0,
        int endNote = 127);

    /**
     * @brief Map a color from palette based on value.
     * @param ctx Render context
     * @param settings Effect settings (contains palette)
     * @param value Value to map (0.0 to 1.0)
     * @param peak Optional peak value for multi-color effects
     * @return Interpolated color from palette
     */
    Color getColorFromPalette(
        const RenderContext& ctx,
        const EffectSettings& settings,
        float value,
        float peak = -1.0f) const;
};

/**
 * @brief Logarithmic scale helper for frequency visualization.
 *
 * Human hearing perceives frequency logarithmically, so this helper
 * provides proper scaling for spectrograms and VU meters.
 */
class LogarithmicScale {
public:
    /**
     * @brief Get number of linear bins to sum for a logarithmic bar.
     * @param bar Bar index (0-based)
     * @param totalBars Total number of output bars
     * @param totalBins Total number of input FFT bins
     * @return Number of bins for this bar
     */
    static int getBinsForBar(int bar, int totalBars, int totalBins);

    /**
     * @brief Get cumulative bin count up to bar index.
     * @param bar Bar index (1-based, 0 returns 0)
     * @return Total bins from bar 0 to bar-1
     */
    static int getLogSum(int bar);

    /**
     * @brief Pre-compute logarithmic mapping for efficiency.
     * @param totalBars Number of output bars
     * @param totalBins Number of input FFT bins
     * @return Vector of bin counts per bar
     */
    static std::vector<int> computeMapping(int totalBars, int totalBins);
};

} // namespace xlCore
