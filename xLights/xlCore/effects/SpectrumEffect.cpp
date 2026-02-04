/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "SpectrumEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <algorithm>
#include <cmath>

namespace xlCore {

SpectrumEffect::SpectrumEffect() {
    m_state.reset();
}

void SpectrumEffect::prepareForRender(const EffectSettings& settings) {
    m_state.reset();
}

void SpectrumEffect::cleanupAfterRender() {
    m_state.reset();
}

std::vector<EffectParameter> SpectrumEffect::parameters() const {
    return {
        EffectParameter::createInt("SLIDER_Spectrum_Bars", "Bars", 16, 4, 128, true),
        EffectParameter::createChoice("CHOICE_Spectrum_Style", "Style", "Bars",
            {"Bars", "Lines", "Filled Lines", "Mirror", "Radial"}),
        EffectParameter::createChoice("CHOICE_Spectrum_ColorMode", "Color Mode", "Amplitude",
            {"Amplitude", "Frequency", "Gradient", "Rainbow"}),
        EffectParameter::createInt("SLIDER_Spectrum_StartNote", "Start Note", 24, 0, 127),
        EffectParameter::createInt("SLIDER_Spectrum_EndNote", "End Note", 108, 0, 127),
        EffectParameter::createBool("CHECKBOX_Spectrum_Logarithmic", "Logarithmic Scale", true),
        EffectParameter::createBool("CHECKBOX_Spectrum_PeakHold", "Show Peaks", true),
        EffectParameter::createInt("SLIDER_Spectrum_PeakDecay", "Peak Decay", 20, 1, 100),
        EffectParameter::createInt("SLIDER_Spectrum_Smoothing", "Smoothing", 30, 0, 100),
        EffectParameter::createInt("SLIDER_Spectrum_Gain", "Gain", 0, -20, 20, true)
    };
}

void SpectrumEffect::render(RenderContext& ctx, const EffectSettings& settings,
                            const RenderState& state) {
    // Audio context
    AudioContext audio(nullptr, state.timeSeconds);
    // TODO: AudioAnalyzer will be passed via RenderState services

    if (!audio.hasAudio()) {
        return;
    }

    // Get parameters
    int bars = settings.getInt("SLIDER_Spectrum_Bars", 16);
    std::string styleStr = settings.get("CHOICE_Spectrum_Style", "Bars");
    SpectrumStyle style = decodeStyle(styleStr);
    std::string colorModeStr = settings.get("CHOICE_Spectrum_ColorMode", "Amplitude");
    SpectrumColorMode colorMode = decodeColorMode(colorModeStr);
    int startNote = settings.getInt("SLIDER_Spectrum_StartNote", 24);
    int endNote = settings.getInt("SLIDER_Spectrum_EndNote", 108);
    bool logarithmic = settings.getBool("CHECKBOX_Spectrum_Logarithmic", true);
    bool showPeaks = settings.getBool("CHECKBOX_Spectrum_PeakHold", true);
    int peakDecay = settings.getInt("SLIDER_Spectrum_PeakDecay", 20);
    int smoothing = settings.getInt("SLIDER_Spectrum_Smoothing", 30);
    int gain = settings.getInt("SLIDER_Spectrum_Gain", 0);

    // Ensure startNote <= endNote
    if (startNote > endNote) {
        std::swap(startNote, endNote);
    }

    // Limit bars to reasonable range
    bars = std::clamp(bars, 1, ctx.width());

    // Get spectrum and extract band levels
    const auto& spectrum = audio.getSpectrum(512);
    std::vector<float> levels = extractBandLevels(spectrum, bars, startNote, endNote,
                                                   44100, logarithmic);

    // Apply gain
    for (auto& level : levels) {
        level = applyGain(level, gain);
    }

    // Initialize state if needed
    if (m_state.lastLevels.size() != static_cast<size_t>(bars)) {
        m_state.lastLevels = levels;
        m_state.peakLevels = levels;
        m_state.peakHoldFrames.resize(bars, 0);
    }

    // Apply smoothing
    float smoothFactor = smoothing / 100.0f;
    for (size_t i = 0; i < levels.size() && i < m_state.lastLevels.size(); ++i) {
        m_state.lastLevels[i] = m_state.lastLevels[i] * smoothFactor +
                                levels[i] * (1.0f - smoothFactor);
    }

    // Update peaks
    float decayRate = peakDecay / 1000.0f;  // Slower decay
    for (size_t i = 0; i < levels.size() && i < m_state.peakLevels.size(); ++i) {
        if (levels[i] >= m_state.peakLevels[i]) {
            m_state.peakLevels[i] = levels[i];
            m_state.peakHoldFrames[i] = 10;  // Hold for 10 frames
        } else if (m_state.peakHoldFrames[i] > 0) {
            m_state.peakHoldFrames[i]--;
        } else {
            m_state.peakLevels[i] -= decayRate;
            if (m_state.peakLevels[i] < levels[i]) {
                m_state.peakLevels[i] = levels[i];
            }
        }
    }

    // Render based on style
    switch (style) {
        case SpectrumStyle::Bars:
            renderBars(ctx, settings, m_state.lastLevels, m_state.peakLevels,
                       colorMode, showPeaks);
            break;

        case SpectrumStyle::Lines:
            renderLines(ctx, settings, m_state.lastLevels, colorMode, false);
            break;

        case SpectrumStyle::FilledLines:
            renderLines(ctx, settings, m_state.lastLevels, colorMode, true);
            break;

        case SpectrumStyle::Mirror:
            renderMirror(ctx, settings, m_state.lastLevels, m_state.peakLevels,
                         colorMode, showPeaks);
            break;

        case SpectrumStyle::Radial:
            renderRadial(ctx, settings, m_state.lastLevels, colorMode);
            break;
    }
}

// ============================================================================
// Style/Color mode decoding
// ============================================================================

SpectrumStyle SpectrumEffect::decodeStyle(const std::string& style) {
    if (style == "Bars") return SpectrumStyle::Bars;
    if (style == "Lines") return SpectrumStyle::Lines;
    if (style == "Filled Lines") return SpectrumStyle::FilledLines;
    if (style == "Mirror") return SpectrumStyle::Mirror;
    if (style == "Radial") return SpectrumStyle::Radial;
    return SpectrumStyle::Bars;
}

SpectrumColorMode SpectrumEffect::decodeColorMode(const std::string& mode) {
    if (mode == "Amplitude") return SpectrumColorMode::Amplitude;
    if (mode == "Frequency") return SpectrumColorMode::Frequency;
    if (mode == "Gradient") return SpectrumColorMode::Gradient;
    if (mode == "Rainbow") return SpectrumColorMode::Rainbow;
    return SpectrumColorMode::Amplitude;
}

// ============================================================================
// Render methods
// ============================================================================

void SpectrumEffect::renderBars(RenderContext& ctx, const EffectSettings& settings,
                                 const std::vector<float>& levels,
                                 const std::vector<float>& peaks,
                                 SpectrumColorMode colorMode, bool showPeaks) {
    int bars = static_cast<int>(levels.size());
    if (bars == 0) return;

    float barWidth = static_cast<float>(ctx.width()) / bars;

    for (int bar = 0; bar < bars; ++bar) {
        float level = levels[bar];
        int height = static_cast<int>(level * ctx.height());

        int x1 = static_cast<int>(bar * barWidth);
        int x2 = static_cast<int>((bar + 1) * barWidth);

        // Draw bar
        for (int x = x1; x < x2 && x < ctx.width(); ++x) {
            for (int y = 0; y < height && y < ctx.height(); ++y) {
                Color color = getBarColor(bar, bars,
                    static_cast<float>(y) / ctx.height(), colorMode);
                ctx.setPixel(x, y, color);
            }

            // Draw peak
            if (showPeaks && bar < static_cast<int>(peaks.size())) {
                int peakY = static_cast<int>(peaks[bar] * ctx.height());
                if (peakY >= 0 && peakY < ctx.height()) {
                    ctx.setPixel(x, peakY, Color::White());
                }
            }
        }
    }
}

void SpectrumEffect::renderLines(RenderContext& ctx, const EffectSettings& settings,
                                  const std::vector<float>& levels,
                                  SpectrumColorMode colorMode, bool filled) {
    int bars = static_cast<int>(levels.size());
    if (bars == 0) return;

    float barWidth = static_cast<float>(ctx.width()) / bars;
    int lastX = -1;
    int lastY = -1;

    for (int bar = 0; bar < bars; ++bar) {
        float level = levels[bar];
        int height = static_cast<int>(level * ctx.height());

        int x = static_cast<int>(bar * barWidth + barWidth / 2);
        int y = height;

        Color color = getBarColor(bar, bars, level, colorMode);

        if (lastX >= 0) {
            ctx.drawLine(lastX, lastY, x, y, color);

            if (filled) {
                // Fill below the line
                int minX = std::min(lastX, x);
                int maxX = std::max(lastX, x);
                for (int fx = minX; fx <= maxX && fx < ctx.width(); ++fx) {
                    float t = (maxX == minX) ? 0.5f :
                        static_cast<float>(fx - minX) / (maxX - minX);
                    int fy = static_cast<int>(lastY + (y - lastY) * t);
                    for (int fill = 0; fill < fy && fill < ctx.height(); ++fill) {
                        Color fillColor = getBarColor(bar, bars,
                            static_cast<float>(fill) / ctx.height(), colorMode);
                        fillColor.alpha = 128;  // Semi-transparent fill
                        ctx.setPixel(fx, fill, fillColor);
                    }
                }
            }
        }

        lastX = x;
        lastY = y;
    }
}

void SpectrumEffect::renderMirror(RenderContext& ctx, const EffectSettings& settings,
                                   const std::vector<float>& levels,
                                   const std::vector<float>& peaks,
                                   SpectrumColorMode colorMode, bool showPeaks) {
    int bars = static_cast<int>(levels.size());
    if (bars == 0) return;

    float barWidth = static_cast<float>(ctx.width()) / bars;
    int midY = ctx.height() / 2;

    for (int bar = 0; bar < bars; ++bar) {
        float level = levels[bar];
        int height = static_cast<int>(level * midY);

        int x1 = static_cast<int>(bar * barWidth);
        int x2 = static_cast<int>((bar + 1) * barWidth);

        for (int x = x1; x < x2 && x < ctx.width(); ++x) {
            // Draw upward from center
            for (int y = midY; y < midY + height && y < ctx.height(); ++y) {
                Color color = getBarColor(bar, bars,
                    static_cast<float>(y - midY) / midY, colorMode);
                ctx.setPixel(x, y, color);
            }

            // Draw downward from center (mirror)
            for (int y = midY - 1; y >= midY - height && y >= 0; --y) {
                Color color = getBarColor(bar, bars,
                    static_cast<float>(midY - y) / midY, colorMode);
                ctx.setPixel(x, y, color);
            }

            // Draw peaks
            if (showPeaks && bar < static_cast<int>(peaks.size())) {
                int peakOffset = static_cast<int>(peaks[bar] * midY);
                int peakTop = midY + peakOffset;
                int peakBottom = midY - peakOffset;
                if (peakTop < ctx.height()) {
                    ctx.setPixel(x, peakTop, Color::White());
                }
                if (peakBottom >= 0) {
                    ctx.setPixel(x, peakBottom, Color::White());
                }
            }
        }
    }
}

void SpectrumEffect::renderRadial(RenderContext& ctx, const EffectSettings& settings,
                                   const std::vector<float>& levels,
                                   SpectrumColorMode colorMode) {
    int bars = static_cast<int>(levels.size());
    if (bars == 0) return;

    int cx = ctx.width() / 2;
    int cy = ctx.height() / 2;
    int maxRadius = std::min(cx, cy);

    float angleStep = 2.0f * M_PI / bars;

    for (int bar = 0; bar < bars; ++bar) {
        float level = levels[bar];
        int radius = static_cast<int>(level * maxRadius);

        float angle = bar * angleStep - M_PI / 2;  // Start at top
        float nextAngle = (bar + 1) * angleStep - M_PI / 2;

        Color color = getBarColor(bar, bars, level, colorMode);

        // Draw radial segment as line from center outward
        int x1 = cx;
        int y1 = cy;
        int x2 = cx + static_cast<int>(radius * std::cos(angle));
        int y2 = cy + static_cast<int>(radius * std::sin(angle));

        ctx.drawLine(x1, y1, x2, y2, color);

        // Connect adjacent bar endpoints
        if (bar > 0) {
            float prevAngle = (bar - 1) * angleStep - M_PI / 2;
            float prevLevel = levels[bar - 1];
            int prevRadius = static_cast<int>(prevLevel * maxRadius);

            int px = cx + static_cast<int>(prevRadius * std::cos(prevAngle));
            int py = cy + static_cast<int>(prevRadius * std::sin(prevAngle));

            ctx.drawLine(px, py, x2, y2, color);
        }
    }

    // Close the circle
    if (bars > 1) {
        float firstAngle = -M_PI / 2;
        float lastAngle = (bars - 1) * angleStep - M_PI / 2;
        int firstRadius = static_cast<int>(levels[0] * maxRadius);
        int lastRadius = static_cast<int>(levels[bars - 1] * maxRadius);

        int fx = cx + static_cast<int>(firstRadius * std::cos(firstAngle));
        int fy = cy + static_cast<int>(firstRadius * std::sin(firstAngle));
        int lx = cx + static_cast<int>(lastRadius * std::cos(lastAngle));
        int ly = cy + static_cast<int>(lastRadius * std::sin(lastAngle));

        Color color = getBarColor(0, bars, levels[0], colorMode);
        ctx.drawLine(lx, ly, fx, fy, color);
    }
}

// ============================================================================
// Color helper
// ============================================================================

Color SpectrumEffect::getBarColor(int bar, int totalBars, float level,
                                   SpectrumColorMode mode) const {
    float hue = 0.0f;

    switch (mode) {
        case SpectrumColorMode::Amplitude:
            // Green to red based on amplitude
            hue = (1.0f - level) * 120.0f;  // 120 = green, 0 = red
            break;

        case SpectrumColorMode::Frequency:
            // Color based on frequency band position
            hue = static_cast<float>(bar) / totalBars * 300.0f;  // Blue to red
            break;

        case SpectrumColorMode::Gradient:
            // Fixed gradient based on y position (level acts as position)
            hue = level * 240.0f;  // Blue to purple
            break;

        case SpectrumColorMode::Rainbow:
            // Full rainbow based on bar position
            hue = static_cast<float>(bar) / totalBars * 360.0f;
            break;
    }

    // Hue is 0.0-1.0 in xlCore (not 0-360), so normalize
    return Color::fromHSV(hue / 360.0f, 1.0f, 1.0f);
}

// Register effect
XLCORE_REGISTER_EFFECT(SpectrumEffect)

} // namespace xlCore
