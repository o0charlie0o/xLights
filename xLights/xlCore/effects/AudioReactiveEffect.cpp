/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "AudioReactiveEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <algorithm>
#include <cmath>

namespace xlCore {

std::vector<float> AudioReactiveEffect::extractBandLevels(
    const std::vector<float>& spectrum,
    int numBands,
    int startNote,
    int endNote,
    int sampleRate,
    bool logarithmic)
{
    std::vector<float> levels(numBands, 0.0f);

    if (spectrum.empty() || numBands <= 0) {
        return levels;
    }

    // FFT size is typically 2x the spectrum size (positive frequencies only)
    int fftSize = static_cast<int>(spectrum.size()) * 2;

    // Convert MIDI notes to frequency bins
    float startFreq = FrequencyBands::midiNoteToFrequency(startNote);
    float endFreq = FrequencyBands::midiNoteToFrequency(endNote);

    int startBin = FrequencyBands::frequencyToBin(startFreq, sampleRate, fftSize);
    int endBin = FrequencyBands::frequencyToBin(endFreq, sampleRate, fftSize);

    // Clamp to valid range
    startBin = std::clamp(startBin, 0, static_cast<int>(spectrum.size()) - 1);
    endBin = std::clamp(endBin, startBin + 1, static_cast<int>(spectrum.size()));

    int totalBins = endBin - startBin;
    if (totalBins <= 0) {
        return levels;
    }

    if (logarithmic) {
        // Logarithmic distribution - more bins for lower frequencies
        auto mapping = LogarithmicScale::computeMapping(numBands, totalBins);
        int binOffset = startBin;

        for (int band = 0; band < numBands; ++band) {
            int binsForBand = mapping[band];
            float maxLevel = 0.0f;

            for (int i = 0; i < binsForBand && binOffset < endBin; ++i, ++binOffset) {
                if (binOffset < static_cast<int>(spectrum.size())) {
                    maxLevel = std::max(maxLevel, spectrum[binOffset]);
                }
            }

            levels[band] = maxLevel;
        }
    } else {
        // Linear distribution - equal number of bins per band
        float binsPerBand = static_cast<float>(totalBins) / numBands;

        for (int band = 0; band < numBands; ++band) {
            int binStart = startBin + static_cast<int>(band * binsPerBand);
            int binEnd = startBin + static_cast<int>((band + 1) * binsPerBand);
            binEnd = std::min(binEnd, endBin);

            float maxLevel = 0.0f;
            for (int bin = binStart; bin < binEnd && bin < static_cast<int>(spectrum.size()); ++bin) {
                maxLevel = std::max(maxLevel, spectrum[bin]);
            }

            levels[band] = maxLevel;
        }
    }

    return levels;
}

float AudioReactiveEffect::getDominantFrequency(
    const std::vector<float>& spectrum,
    int sampleRate,
    int startNote,
    int endNote)
{
    if (spectrum.empty()) {
        return 0.0f;
    }

    int fftSize = static_cast<int>(spectrum.size()) * 2;

    float startFreq = FrequencyBands::midiNoteToFrequency(startNote);
    float endFreq = FrequencyBands::midiNoteToFrequency(endNote);

    int startBin = FrequencyBands::frequencyToBin(startFreq, sampleRate, fftSize);
    int endBin = FrequencyBands::frequencyToBin(endFreq, sampleRate, fftSize);

    startBin = std::clamp(startBin, 0, static_cast<int>(spectrum.size()) - 1);
    endBin = std::clamp(endBin, startBin + 1, static_cast<int>(spectrum.size()));

    // Find bin with maximum energy
    int maxBin = startBin;
    float maxLevel = 0.0f;

    for (int bin = startBin; bin < endBin; ++bin) {
        if (spectrum[bin] > maxLevel) {
            maxLevel = spectrum[bin];
            maxBin = bin;
        }
    }

    // Convert bin back to frequency
    return FrequencyBands::binToFrequency(maxBin, sampleRate, fftSize);
}

Color AudioReactiveEffect::getColorFromPalette(
    const RenderContext& ctx,
    const EffectSettings& settings,
    float value,
    float peak) const
{
    // This would typically read from the color palette in settings
    // For now, return a simple gradient based on value
    // TODO: Integrate with actual palette system

    // Clamp value to valid range
    value = std::clamp(value, 0.0f, 1.0f);

    // Simple green-yellow-red gradient for level indication
    if (value < 0.5f) {
        // Green to yellow
        float t = value * 2.0f;
        return Color(
            static_cast<uint8_t>(t * 255),      // R: 0 -> 255
            255,                                 // G: 255
            0,                                   // B: 0
            255
        );
    } else {
        // Yellow to red
        float t = (value - 0.5f) * 2.0f;
        return Color(
            255,                                 // R: 255
            static_cast<uint8_t>((1.0f - t) * 255), // G: 255 -> 0
            0,                                   // B: 0
            255
        );
    }
}

// ============================================================================
// LogarithmicScale implementation
// ============================================================================

int LogarithmicScale::getBinsForBar(int bar, int totalBars, int totalBins) {
    if (bar < 0 || totalBars <= 0 || totalBins <= 0) {
        return 0;
    }

    // Use log scale: lower bars get more bins
    double logBase = std::log(static_cast<double>(totalBins + 1));
    int cumulative0 = (bar == 0) ? 0 :
        static_cast<int>(std::exp(logBase * bar / totalBars) - 1);
    int cumulative1 = static_cast<int>(std::exp(logBase * (bar + 1) / totalBars) - 1);

    return std::max(1, cumulative1 - cumulative0);
}

int LogarithmicScale::getLogSum(int bar) {
    if (bar <= 0) return 0;

    // Pre-computed logarithmic sums for common bar counts
    // This matches the legacy xLights implementation
    static const int logSums[] = {
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
        11, 12, 14, 16, 18, 20, 22, 25, 28, 31,
        35, 39, 43, 48, 53, 59, 65, 72, 80, 88,
        97, 107, 118, 130, 143, 157, 173, 190, 209, 230,
        253, 278, 306, 337, 370, 407, 448, 493, 542, 596
    };

    if (bar < static_cast<int>(sizeof(logSums) / sizeof(logSums[0]))) {
        return logSums[bar];
    }

    // Compute for larger values
    return static_cast<int>(std::exp(std::log(128.0) * bar / 50.0));
}

std::vector<int> LogarithmicScale::computeMapping(int totalBars, int totalBins) {
    std::vector<int> mapping(totalBars, 1);

    if (totalBars <= 0 || totalBins <= 0) {
        return mapping;
    }

    // Compute logarithmic bin distribution
    double logBase = std::log(static_cast<double>(totalBins + 1));
    int assignedBins = 0;

    for (int bar = 0; bar < totalBars; ++bar) {
        int cumulative = static_cast<int>(std::exp(logBase * (bar + 1) / totalBars) - 1);
        int binsForBar = std::max(1, cumulative - assignedBins);

        // Don't exceed total bins
        if (assignedBins + binsForBar > totalBins) {
            binsForBar = totalBins - assignedBins;
        }

        mapping[bar] = binsForBar;
        assignedBins += binsForBar;
    }

    return mapping;
}

} // namespace xlCore
