/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "VUMeterEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <algorithm>
#include <cmath>

namespace xlCore {

VUMeterEffect::VUMeterEffect() {
    m_state.reset();
}

void VUMeterEffect::prepareForRender(const EffectSettings& settings) {
    m_state.reset();
}

void VUMeterEffect::cleanupAfterRender() {
    m_state.reset();
}

std::vector<EffectParameter> VUMeterEffect::parameters() const {
    return {
        EffectParameter::createChoice("CHOICE_VUMeter_Type", "Type", "Waveform",
            {"Spectrogram", "Spectrogram Peak", "Spectrogram Line", "Volume Bars",
             "Waveform", "Frame Waveform", "On", "Color On", "Intensity Wave",
             "Level Pulse", "Level Shape", "Level Bar", "Level Random Bar",
             "Level Color", "Dominant Frequency Colour", "Dominant Frequency Colour Gradient"}),
        EffectParameter::createInt("SLIDER_VUMeter_Bars", "Bars", 6, 1, 100, true),
        EffectParameter::createInt("SLIDER_VUMeter_Sensitivity", "Sensitivity", 70, 0, 100),
        EffectParameter::createChoice("CHOICE_VUMeter_Shape", "Shape", "Circle",
            {"Circle", "Filled Circle", "Square", "Filled Square", "Diamond",
             "Filled Diamond", "Star", "Filled Star", "Heart", "Filled Heart"}),
        EffectParameter::createBool("CHECKBOX_VUMeter_SlowDownFalls", "Slow Down Falls", true),
        EffectParameter::createBool("CHECKBOX_VUMeter_LogarithmicX", "Logarithmic X", false),
        EffectParameter::createInt("SLIDER_VUMeter_StartNote", "Start Note", 36, 0, 127),
        EffectParameter::createInt("SLIDER_VUMeter_EndNote", "End Note", 84, 0, 127),
        EffectParameter::createInt("SLIDER_VUMeter_XOffset", "X Offset", 0, -100, 100),
        EffectParameter::createInt("SLIDER_VUMeter_YOffset", "Y Offset", 0, -100, 100, true),
        EffectParameter::createInt("SLIDER_VUMeter_Gain", "Gain", 0, -20, 20, true)
    };
}

void VUMeterEffect::render(RenderContext& ctx, const EffectSettings& settings,
                           const RenderState& state) {
    // Get audio context - without audio, render silent
    AudioContext audio(nullptr, state.timeSeconds);
    // TODO: In integration, AudioAnalyzer will be passed via RenderState services

    if (!audio.hasAudio()) {
        // No audio available - render silent state (optional visualization)
        return;
    }

    // Get parameters
    std::string typeStr = settings.get("CHOICE_VUMeter_Type", "Waveform");
    VUMeterType type = decodeType(typeStr);
    int bars = settings.getInt("SLIDER_VUMeter_Bars", 6);
    int sensitivity = settings.getInt("SLIDER_VUMeter_Sensitivity", 70);
    std::string shapeStr = settings.get("CHOICE_VUMeter_Shape", "Circle");
    VUMeterShape shape = decodeShape(shapeStr);
    bool slowDownFalls = settings.getBool("CHECKBOX_VUMeter_SlowDownFalls", true);
    bool logarithmic = settings.getBool("CHECKBOX_VUMeter_LogarithmicX", false);
    int startNote = settings.getInt("SLIDER_VUMeter_StartNote", 36);
    int endNote = settings.getInt("SLIDER_VUMeter_EndNote", 84);
    int xOffset = settings.getInt("SLIDER_VUMeter_XOffset", 0);
    int yOffset = settings.getInt("SLIDER_VUMeter_YOffset", 0);
    int gain = settings.getInt("SLIDER_VUMeter_Gain", 0);

    // Ensure startNote <= endNote
    if (startNote > endNote) {
        std::swap(startNote, endNote);
    }

    // Limit bars to buffer width for applicable types
    int useBars = std::min(bars, ctx.width());
    if (useBars <= 0) useBars = 1;

    // Dispatch to specific render method
    switch (type) {
        case VUMeterType::Spectrogram:
            renderSpectrogram(ctx, audio, settings, useBars, startNote, endNote,
                              xOffset, yOffset, gain, slowDownFalls, logarithmic,
                              false, 0, false, false, sensitivity);
            break;

        case VUMeterType::SpectrogramPeak:
            renderSpectrogram(ctx, audio, settings, useBars, startNote, endNote,
                              xOffset, yOffset, gain, slowDownFalls, logarithmic,
                              true, sensitivity, false, false, sensitivity);
            break;

        case VUMeterType::SpectrogramLine:
            renderSpectrogram(ctx, audio, settings, useBars, startNote, endNote,
                              xOffset, yOffset, gain, slowDownFalls, logarithmic,
                              true, sensitivity, true, false, sensitivity);
            break;

        case VUMeterType::VolumeBars:
            renderVolumeBars(ctx, audio, settings, useBars, gain);
            break;

        case VUMeterType::Waveform:
            renderWaveform(ctx, audio, settings, useBars, yOffset, gain, false);
            break;

        case VUMeterType::FrameWaveform:
            renderWaveform(ctx, audio, settings, useBars, yOffset, gain, true);
            break;

        case VUMeterType::On:
            renderOn(ctx, audio, settings, gain);
            break;

        case VUMeterType::ColorOn:
            renderColorOn(ctx, audio, settings, gain);
            break;

        case VUMeterType::IntensityWave:
            renderIntensityWave(ctx, audio, settings, useBars, gain);
            break;

        case VUMeterType::LevelPulse:
            renderLevelPulse(ctx, audio, settings, useBars, sensitivity, gain);
            break;

        case VUMeterType::LevelShape:
            renderLevelShape(ctx, audio, settings, shape, sensitivity, slowDownFalls,
                             xOffset, yOffset, useBars, gain);
            break;

        case VUMeterType::LevelBar:
            renderLevelBar(ctx, audio, settings, useBars, sensitivity, gain, false);
            break;

        case VUMeterType::LevelColor:
            renderLevelColor(ctx, audio, settings, sensitivity, gain);
            break;

        case VUMeterType::DominantFrequencyColour:
            renderDominantFrequencyColour(ctx, audio, settings, sensitivity,
                                          startNote, endNote, false);
            break;

        default:
            break;
    }
}

// ============================================================================
// Type/Shape decoding
// ============================================================================

VUMeterType VUMeterEffect::decodeType(const std::string& type) {
    if (type == "Spectrogram") return VUMeterType::Spectrogram;
    if (type == "Spectrogram Peak") return VUMeterType::SpectrogramPeak;
    if (type == "Spectrogram Line") return VUMeterType::SpectrogramLine;
    if (type == "Volume Bars") return VUMeterType::VolumeBars;
    if (type == "Waveform") return VUMeterType::Waveform;
    if (type == "Frame Waveform") return VUMeterType::FrameWaveform;
    if (type == "On") return VUMeterType::On;
    if (type == "Color On") return VUMeterType::ColorOn;
    if (type == "Intensity Wave") return VUMeterType::IntensityWave;
    if (type == "Level Pulse") return VUMeterType::LevelPulse;
    if (type == "Level Shape") return VUMeterType::LevelShape;
    if (type == "Level Bar") return VUMeterType::LevelBar;
    if (type == "Level Random Bar") return VUMeterType::LevelBar;
    if (type == "Level Color") return VUMeterType::LevelColor;
    if (type == "Dominant Frequency Colour") return VUMeterType::DominantFrequencyColour;
    if (type == "Dominant Frequency Colour Gradient") return VUMeterType::DominantFrequencyColour;
    return VUMeterType::Waveform;
}

VUMeterShape VUMeterEffect::decodeShape(const std::string& shape) {
    if (shape == "Circle") return VUMeterShape::Circle;
    if (shape == "Filled Circle") return VUMeterShape::FilledCircle;
    if (shape == "Square") return VUMeterShape::Square;
    if (shape == "Filled Square") return VUMeterShape::FilledSquare;
    if (shape == "Diamond") return VUMeterShape::Diamond;
    if (shape == "Filled Diamond") return VUMeterShape::FilledDiamond;
    if (shape == "Star") return VUMeterShape::Star;
    if (shape == "Filled Star") return VUMeterShape::FilledStar;
    if (shape == "Heart") return VUMeterShape::Heart;
    if (shape == "Filled Heart") return VUMeterShape::FilledHeart;
    return VUMeterShape::Circle;
}

// ============================================================================
// Render methods
// ============================================================================

void VUMeterEffect::renderSpectrogram(RenderContext& ctx, const AudioContext& audio,
                                       const EffectSettings& settings, int bars,
                                       int startNote, int endNote, int xOffset,
                                       int yOffset, int gain, bool slowDownFalls,
                                       bool logarithmic, bool showPeaks, int peakHold,
                                       bool lineMode, bool circleMode, int sensitivity) {
    // Get spectrum data
    const auto& spectrum = audio.getSpectrum(512);
    if (spectrum.empty()) return;

    // Convert offsets from percentage to pixels
    int trueXOffset = xOffset * ctx.width() / 100;
    int trueYOffset = yOffset * ctx.height() / 100;

    // Extract band levels
    std::vector<float> bandLevels = extractBandLevels(spectrum, bars, startNote,
                                                       endNote, 44100, logarithmic);

    // Apply gain
    for (auto& level : bandLevels) {
        level = applyGain(level, gain);
    }

    // Initialize state if needed
    if (m_state.lastValues.size() != static_cast<size_t>(bars)) {
        m_state.lastValues = bandLevels;
        m_state.lastPeaks = bandLevels;
        m_state.peakHoldCounters.resize(bars, 0);
    }

    // Apply slow down falls
    if (slowDownFalls) {
        for (size_t i = 0; i < bandLevels.size() && i < m_state.lastValues.size(); ++i) {
            if (bandLevels[i] < m_state.lastValues[i]) {
                m_state.lastValues[i] -= 0.05f;
                if (m_state.lastValues[i] < bandLevels[i]) {
                    m_state.lastValues[i] = bandLevels[i];
                }
            } else {
                m_state.lastValues[i] = bandLevels[i];
            }
        }
    } else {
        m_state.lastValues = bandLevels;
    }

    // Update peaks if enabled
    if (showPeaks) {
        updatePeaks(m_state.lastPeaks, m_state.lastValues,
                    m_state.peakHoldCounters, peakHold, 0.05f);
    }

    // Calculate column width
    float colWidth = static_cast<float>(ctx.width()) / bars;
    if (colWidth < 1.0f) colWidth = 1.0f;

    // Render based on mode
    if (lineMode) {
        // Line mode - connect bar tops with lines
        int lastX = -1;
        int lastY = -1;
        Color lineColor = getColorFromPalette(ctx, settings, 0.5f);

        for (int bar = 0; bar < bars; ++bar) {
            int colHeight = static_cast<int>(ctx.height() * m_state.lastValues[bar]);
            int x = trueXOffset + static_cast<int>(bar * colWidth + colWidth / 2);
            int y = colHeight + trueYOffset;

            if (lastX >= 0) {
                ctx.drawLine(lastX, lastY, x, y, lineColor);
            }
            lastX = x;
            lastY = y;
        }
    } else {
        // Bar mode - draw filled bars
        for (int bar = 0; bar < bars; ++bar) {
            float level = m_state.lastValues[bar];
            int colHeight = static_cast<int>(ctx.height() * level);

            int x1 = trueXOffset + static_cast<int>(bar * colWidth);
            int x2 = trueXOffset + static_cast<int>((bar + 1) * colWidth);

            // Draw bar with gradient color
            for (int x = x1; x < x2 && x < ctx.width(); ++x) {
                for (int y = 0; y < colHeight && y < ctx.height(); ++y) {
                    Color color = getColorFromPalette(ctx, settings,
                        static_cast<float>(y) / ctx.height());
                    ctx.setPixel(x, y + trueYOffset, color);
                }

                // Draw peak if enabled
                if (showPeaks && bar < static_cast<int>(m_state.lastPeaks.size())) {
                    int peakY = static_cast<int>(ctx.height() * m_state.lastPeaks[bar]);
                    if (peakY >= 0 && peakY < ctx.height()) {
                        Color peakColor = getColorFromPalette(ctx, settings, 1.0f);
                        ctx.setPixel(x, peakY + trueYOffset, peakColor);
                    }
                }
            }
        }
    }
}

void VUMeterEffect::renderVolumeBars(RenderContext& ctx, const AudioContext& audio,
                                      const EffectSettings& settings, int bars, int gain) {
    float level = audio.getRMSLevel();
    level = applyGain(level, gain);

    // Volume bars shows a history of levels
    // Initialize history if needed
    if (m_state.lastValues.size() != static_cast<size_t>(bars)) {
        m_state.lastValues.resize(bars, 0.0f);
    }

    // Shift history left
    for (int i = 0; i < bars - 1; ++i) {
        m_state.lastValues[i] = m_state.lastValues[i + 1];
    }
    m_state.lastValues[bars - 1] = level;

    // Draw bars
    float colWidth = static_cast<float>(ctx.width()) / bars;

    for (int bar = 0; bar < bars; ++bar) {
        float barLevel = m_state.lastValues[bar];
        int colHeight = static_cast<int>(ctx.height() * barLevel);

        int x1 = static_cast<int>(bar * colWidth);
        int x2 = static_cast<int>((bar + 1) * colWidth);

        for (int x = x1; x < x2 && x < ctx.width(); ++x) {
            for (int y = 0; y < colHeight && y < ctx.height(); ++y) {
                Color color = getColorFromPalette(ctx, settings,
                    static_cast<float>(y) / ctx.height());
                ctx.setPixel(x, y, color);
            }
        }
    }
}

void VUMeterEffect::renderWaveform(RenderContext& ctx, const AudioContext& audio,
                                    const EffectSettings& settings, int bars,
                                    int yOffset, int gain, bool frameDetail) {
    int trueYOffset = yOffset * ctx.height() / 2 / 100;
    float midY = ctx.height() / 2.0f + trueYOffset;

    // Get waveform data from analyzer
    if (!audio.analyzer) return;

    // Simple waveform using RMS level for now
    // TODO: Use actual waveform samples when available
    float level = audio.getRMSLevel();
    level = applyGain(level, gain);

    Color color = getColorFromPalette(ctx, settings, 0.5f);

    // Draw waveform as symmetric bars from center
    float colWidth = static_cast<float>(ctx.width()) / bars;

    for (int bar = 0; bar < bars; ++bar) {
        // Simulate waveform using varying levels
        float barLevel = level * (0.5f + 0.5f * std::sin(bar * 0.5f + audio.currentTimeSeconds * 10.0f));
        int amplitude = static_cast<int>(ctx.height() / 2 * barLevel);

        int x1 = static_cast<int>(bar * colWidth);
        int x2 = static_cast<int>((bar + 1) * colWidth);

        for (int x = x1; x < x2 && x < ctx.width(); ++x) {
            int yLow = static_cast<int>(midY) - amplitude;
            int yHigh = static_cast<int>(midY) + amplitude;

            for (int y = yLow; y <= yHigh && y < ctx.height() && y >= 0; ++y) {
                ctx.setPixel(x, y, color);
            }
        }
    }
}

void VUMeterEffect::renderOn(RenderContext& ctx, const AudioContext& audio,
                              const EffectSettings& settings, int gain) {
    float level = audio.getRMSLevel();
    level = applyGain(level, gain);

    // Fill buffer based on level
    uint8_t intensity = static_cast<uint8_t>(level * 255);
    Color color(intensity, intensity, intensity, 255);

    ctx.fill(color);
}

void VUMeterEffect::renderColorOn(RenderContext& ctx, const AudioContext& audio,
                                   const EffectSettings& settings, int gain) {
    float level = audio.getRMSLevel();
    level = applyGain(level, gain);

    // Get color from palette based on level
    Color color = getColorFromPalette(ctx, settings, level);

    ctx.fill(color);
}

void VUMeterEffect::renderIntensityWave(RenderContext& ctx, const AudioContext& audio,
                                         const EffectSettings& settings, int bars, int gain) {
    float level = audio.getRMSLevel();
    level = applyGain(level, gain);

    float colWidth = static_cast<float>(ctx.width()) / bars;

    for (int bar = 0; bar < bars; ++bar) {
        // Wave pattern with audio-driven intensity
        float wavePos = static_cast<float>(bar) / bars;
        float intensity = level * std::abs(std::sin(wavePos * M_PI));

        Color color = getColorFromPalette(ctx, settings, intensity);

        int x1 = static_cast<int>(bar * colWidth);
        int x2 = static_cast<int>((bar + 1) * colWidth);

        for (int x = x1; x < x2 && x < ctx.width(); ++x) {
            for (int y = 0; y < ctx.height(); ++y) {
                ctx.setPixel(x, y, color);
            }
        }
    }
}

void VUMeterEffect::renderLevelPulse(RenderContext& ctx, const AudioContext& audio,
                                      const EffectSettings& settings, int bars,
                                      int sensitivity, int gain) {
    float level = audio.getRMSLevel();
    level = applyGain(level, gain);

    float threshold = sensitivity / 100.0f;

    if (level >= threshold) {
        // Pulse on
        m_state.lastSize = 1.0f;
        m_state.colorIndex++;
    } else {
        // Decay
        m_state.lastSize *= 0.9f;
    }

    if (m_state.lastSize > 0.01f) {
        Color color = getColorFromPalette(ctx, settings, m_state.lastSize);
        uint8_t intensity = static_cast<uint8_t>(m_state.lastSize * color.alpha);
        color.alpha = intensity;

        ctx.fill(color);
    }
}

void VUMeterEffect::renderLevelShape(RenderContext& ctx, const AudioContext& audio,
                                      const EffectSettings& settings, VUMeterShape shape,
                                      int sensitivity, bool slowDownFalls, int xOffset,
                                      int yOffset, int bars, int gain) {
    float level = audio.getRMSLevel();
    level = applyGain(level, gain);

    float threshold = sensitivity / 100.0f;
    float targetSize = level / threshold;
    targetSize = std::clamp(targetSize, 0.0f, 1.0f);

    // Apply smoothing
    if (slowDownFalls) {
        if (targetSize < m_state.lastSize) {
            m_state.lastSize -= 0.05f;
            if (m_state.lastSize < targetSize) {
                m_state.lastSize = targetSize;
            }
        } else {
            m_state.lastSize = targetSize;
        }
    } else {
        m_state.lastSize = targetSize;
    }

    // Calculate center and size
    int cx = ctx.width() / 2 + (xOffset * ctx.width() / 100);
    int cy = ctx.height() / 2 + (yOffset * ctx.height() / 100);
    int maxSize = std::min(ctx.width(), ctx.height()) / 2;
    int size = static_cast<int>(maxSize * m_state.lastSize);

    Color color = getColorFromPalette(ctx, settings, m_state.lastSize);

    bool filled = (shape == VUMeterShape::FilledCircle ||
                   shape == VUMeterShape::FilledSquare ||
                   shape == VUMeterShape::FilledDiamond ||
                   shape == VUMeterShape::FilledStar ||
                   shape == VUMeterShape::FilledHeart);

    drawShape(ctx, shape, cx, cy, size, color, filled);
}

void VUMeterEffect::renderLevelBar(RenderContext& ctx, const AudioContext& audio,
                                    const EffectSettings& settings, int bars,
                                    int sensitivity, int gain, bool random) {
    float level = audio.getRMSLevel();
    level = applyGain(level, gain);

    float threshold = sensitivity / 100.0f;

    if (level >= threshold) {
        m_state.lastSize = 1.0f;
        if (random) {
            m_state.colorIndex = rand() % ctx.width();
        } else {
            m_state.colorIndex++;
            if (m_state.colorIndex >= ctx.width()) {
                m_state.colorIndex = 0;
            }
        }
    } else {
        m_state.lastSize *= 0.95f;
    }

    if (m_state.lastSize > 0.01f) {
        int x = m_state.colorIndex % ctx.width();
        int barWidth = std::max(1, ctx.width() / bars);

        Color color = getColorFromPalette(ctx, settings, m_state.lastSize);

        for (int dx = 0; dx < barWidth && (x + dx) < ctx.width(); ++dx) {
            for (int y = 0; y < ctx.height(); ++y) {
                ctx.setPixel(x + dx, y, color);
            }
        }
    }
}

void VUMeterEffect::renderLevelColor(RenderContext& ctx, const AudioContext& audio,
                                      const EffectSettings& settings, int sensitivity,
                                      int gain) {
    float level = audio.getRMSLevel();
    level = applyGain(level, gain);

    float threshold = sensitivity / 100.0f;

    if (level >= threshold) {
        m_state.colorIndex++;
    }

    // Cycle through colors
    float colorPos = static_cast<float>(m_state.colorIndex % 100) / 100.0f;
    Color color = getColorFromPalette(ctx, settings, colorPos);

    // Apply level as brightness
    color.red = static_cast<uint8_t>(color.red * level);
    color.green = static_cast<uint8_t>(color.green * level);
    color.blue = static_cast<uint8_t>(color.blue * level);

    ctx.fill(color);
}

void VUMeterEffect::renderDominantFrequencyColour(RenderContext& ctx,
                                                   const AudioContext& audio,
                                                   const EffectSettings& settings,
                                                   int sensitivity, int startNote,
                                                   int endNote, bool gradient) {
    const auto& spectrum = audio.getSpectrum(512);
    if (spectrum.empty()) return;

    float dominantFreq = getDominantFrequency(spectrum, 44100, startNote, endNote);

    // Map frequency to color position (0-1)
    float minFreq = FrequencyBands::midiNoteToFrequency(startNote);
    float maxFreq = FrequencyBands::midiNoteToFrequency(endNote);
    float freqRange = maxFreq - minFreq;

    float colorPos = (dominantFreq - minFreq) / freqRange;
    colorPos = std::clamp(colorPos, 0.0f, 1.0f);

    Color color = getColorFromPalette(ctx, settings, colorPos);

    // Apply level-based intensity
    float level = audio.getRMSLevel();
    float threshold = sensitivity / 100.0f;

    if (level < threshold) {
        float brightness = level / threshold;
        color.red = static_cast<uint8_t>(color.red * brightness);
        color.green = static_cast<uint8_t>(color.green * brightness);
        color.blue = static_cast<uint8_t>(color.blue * brightness);
    }

    ctx.fill(color);
}

// ============================================================================
// Helper methods
// ============================================================================

void VUMeterEffect::drawShape(RenderContext& ctx, VUMeterShape shape, int cx, int cy,
                               int size, const Color& color, bool filled) {
    if (size <= 0) return;

    switch (shape) {
        case VUMeterShape::Circle:
        case VUMeterShape::FilledCircle:
            ctx.drawCircle(cx, cy, size, color, filled);
            break;

        case VUMeterShape::Square:
        case VUMeterShape::FilledSquare:
            ctx.drawRect(cx - size, cy - size, cx + size, cy + size, color, filled);
            break;

        case VUMeterShape::Diamond:
        case VUMeterShape::FilledDiamond: {
            // Draw diamond using lines
            std::vector<Point2D> points = {
                {cx, cy + size},      // top
                {cx + size, cy},      // right
                {cx, cy - size},      // bottom
                {cx - size, cy}       // left
            };
            if (filled) {
                ctx.fillConvexPoly(points, color);
            } else {
                for (size_t i = 0; i < points.size(); ++i) {
                    size_t next = (i + 1) % points.size();
                    ctx.drawLine(points[i].x, points[i].y, points[next].x, points[next].y, color);
                }
            }
            break;
        }

        case VUMeterShape::Star:
        case VUMeterShape::FilledStar: {
            // 5-point star
            int innerSize = size / 2;
            std::vector<Point2D> points;
            for (int i = 0; i < 10; ++i) {
                float angle = i * M_PI / 5 - M_PI / 2;
                int radius = (i % 2 == 0) ? size : innerSize;
                points.push_back({
                    cx + static_cast<int>(radius * std::cos(angle)),
                    cy + static_cast<int>(radius * std::sin(angle))
                });
            }
            if (filled) {
                // Simplified - just draw center
                ctx.drawCircle(cx, cy, innerSize, color, true);
            }
            // Draw outline
            for (size_t i = 0; i < points.size(); ++i) {
                size_t next = (i + 1) % points.size();
                ctx.drawLine(points[i].x, points[i].y, points[next].x, points[next].y, color);
            }
            break;
        }

        case VUMeterShape::Heart:
        case VUMeterShape::FilledHeart: {
            // Simplified heart shape using circles and triangle
            int halfSize = size / 2;
            ctx.drawCircle(cx - halfSize/2, cy + halfSize/2, halfSize/2, color, filled);
            ctx.drawCircle(cx + halfSize/2, cy + halfSize/2, halfSize/2, color, filled);
            std::vector<Point2D> triangle = {
                {cx - size, cy},
                {cx + size, cy},
                {cx, cy - size}
            };
            ctx.fillConvexPoly(triangle, color);
            break;
        }

        default:
            ctx.drawCircle(cx, cy, size, color, filled);
            break;
    }
}

void VUMeterEffect::updatePeaks(std::vector<float>& peaks, const std::vector<float>& current,
                                 std::vector<int>& holdCounters, int holdFrames, float fallRate) {
    if (peaks.size() != current.size()) {
        peaks = current;
        holdCounters.resize(current.size(), 0);
        return;
    }

    for (size_t i = 0; i < current.size(); ++i) {
        if (current[i] >= peaks[i]) {
            peaks[i] = current[i];
            holdCounters[i] = holdFrames;
        } else {
            if (holdCounters[i] > 0) {
                holdCounters[i]--;
            } else {
                peaks[i] -= fallRate;
                if (peaks[i] < current[i]) {
                    peaks[i] = current[i];
                }
            }
        }
    }
}

// Register effect
XLCORE_REGISTER_EFFECT(VUMeterEffect)

} // namespace xlCore
