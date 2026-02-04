/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "WaveformEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <algorithm>
#include <cmath>

namespace xlCore {

WaveformEffect::WaveformEffect() {
    m_state.reset();
}

void WaveformEffect::prepareForRender(const EffectSettings& settings) {
    m_state.reset();
}

void WaveformEffect::cleanupAfterRender() {
    m_state.reset();
}

std::vector<EffectParameter> WaveformEffect::parameters() const {
    return {
        EffectParameter::createChoice("CHOICE_Waveform_Style", "Style", "Line",
            {"Line", "Filled", "Bars", "Dots"}),
        EffectParameter::createChoice("CHOICE_Waveform_Source", "Source", "History",
            {"Real Time", "History"}),
        EffectParameter::createInt("SLIDER_Waveform_Resolution", "Resolution", 50, 10, 200),
        EffectParameter::createInt("SLIDER_Waveform_YOffset", "Y Offset", 0, -100, 100, true),
        EffectParameter::createInt("SLIDER_Waveform_Gain", "Gain", 0, -20, 20, true),
        EffectParameter::createInt("SLIDER_Waveform_Smoothing", "Smoothing", 0, 0, 100)
    };
}

void WaveformEffect::render(RenderContext& ctx, const EffectSettings& settings,
                            const RenderState& state) {
    // Audio context
    AudioContext audio(nullptr, state.timeSeconds);
    // TODO: AudioAnalyzer will be passed via RenderState services

    if (!audio.hasAudio()) {
        return;
    }

    // Get parameters
    std::string styleStr = settings.get("CHOICE_Waveform_Style", "Line");
    WaveformStyle style = decodeStyle(styleStr);
    std::string sourceStr = settings.get("CHOICE_Waveform_Source", "History");
    WaveformSource source = decodeSource(sourceStr);
    int resolution = settings.getInt("SLIDER_Waveform_Resolution", 50);
    int yOffset = settings.getInt("SLIDER_Waveform_YOffset", 0);
    int gain = settings.getInt("SLIDER_Waveform_Gain", 0);
    int smoothing = settings.getInt("SLIDER_Waveform_Smoothing", 0);

    // Convert Y offset from percentage to pixels
    int trueYOffset = yOffset * ctx.height() / 2 / 100;

    // Get waveform data based on source
    std::vector<float> samples;

    if (source == WaveformSource::RealTime && audio.analyzer) {
        // Get actual waveform samples from analyzer
        samples = audio.analyzer->getWaveform(
            state.timeSeconds - 0.02,  // 20ms window
            state.timeSeconds + 0.02,
            resolution);
    } else {
        // Use history of RMS levels
        float level = audio.getRMSLevel();
        level = applyGain(level, gain);

        // Add to history
        m_state.levelHistory.push_back(level);

        // Keep only as many samples as resolution
        while (static_cast<int>(m_state.levelHistory.size()) > resolution) {
            m_state.levelHistory.pop_front();
        }

        // Convert to samples vector (bipolar for waveform display)
        samples.resize(resolution);
        size_t historyStart = m_state.levelHistory.size() > static_cast<size_t>(resolution) ?
            m_state.levelHistory.size() - resolution : 0;

        for (int i = 0; i < resolution; ++i) {
            if (historyStart + i < m_state.levelHistory.size()) {
                // Convert unipolar level to bipolar waveform-like data
                float lvl = m_state.levelHistory[historyStart + i];
                // Create a simple oscillating pattern scaled by level
                float phase = static_cast<float>(i) / resolution * 4.0f * M_PI;
                samples[i] = lvl * std::sin(phase + state.timeSeconds * 10.0f);
            } else {
                samples[i] = 0.0f;
            }
        }
    }

    // Apply gain if using realtime source
    if (source == WaveformSource::RealTime) {
        for (auto& sample : samples) {
            sample = applyGain(std::abs(sample), gain) * (sample >= 0 ? 1.0f : -1.0f);
            sample = std::clamp(sample, -1.0f, 1.0f);
        }
    }

    // Apply smoothing
    if (smoothing > 0 && !m_state.lastWaveform.empty()) {
        float smoothFactor = smoothing / 100.0f;
        for (size_t i = 0; i < samples.size() && i < m_state.lastWaveform.size(); ++i) {
            samples[i] = m_state.lastWaveform[i] * smoothFactor +
                         samples[i] * (1.0f - smoothFactor);
        }
    }
    m_state.lastWaveform = samples;

    // Render based on style
    switch (style) {
        case WaveformStyle::Line:
            renderLine(ctx, settings, samples, trueYOffset, false);
            break;

        case WaveformStyle::Filled:
            renderLine(ctx, settings, samples, trueYOffset, true);
            break;

        case WaveformStyle::Bars:
            renderBars(ctx, settings, samples, trueYOffset);
            break;

        case WaveformStyle::Dots:
            renderDots(ctx, settings, samples, trueYOffset);
            break;
    }
}

// ============================================================================
// Style decoding
// ============================================================================

WaveformStyle WaveformEffect::decodeStyle(const std::string& style) {
    if (style == "Line") return WaveformStyle::Line;
    if (style == "Filled") return WaveformStyle::Filled;
    if (style == "Bars") return WaveformStyle::Bars;
    if (style == "Dots") return WaveformStyle::Dots;
    return WaveformStyle::Line;
}

WaveformSource WaveformEffect::decodeSource(const std::string& source) {
    if (source == "Real Time") return WaveformSource::RealTime;
    if (source == "History") return WaveformSource::History;
    return WaveformSource::History;
}

// ============================================================================
// Render methods
// ============================================================================

void WaveformEffect::renderLine(RenderContext& ctx, const EffectSettings& settings,
                                 const std::vector<float>& samples, int yOffset, bool filled) {
    if (samples.empty()) return;

    int midY = ctx.height() / 2 + yOffset;
    int halfHeight = ctx.height() / 2;

    float xStep = static_cast<float>(ctx.width()) / samples.size();
    int lastX = -1;
    int lastY = -1;

    Color color = getWaveformColor(settings, 0.5f);

    for (size_t i = 0; i < samples.size(); ++i) {
        int x = static_cast<int>(i * xStep);
        int y = midY + static_cast<int>(samples[i] * halfHeight);
        y = std::clamp(y, 0, ctx.height() - 1);

        if (filled) {
            // Draw vertical line from center to sample
            int y1 = std::min(midY, y);
            int y2 = std::max(midY, y);
            for (int fy = y1; fy <= y2; ++fy) {
                ctx.setPixel(x, fy, color);
            }
        }

        if (lastX >= 0) {
            ctx.drawLine(lastX, lastY, x, y, color);
        }

        lastX = x;
        lastY = y;
    }
}

void WaveformEffect::renderBars(RenderContext& ctx, const EffectSettings& settings,
                                 const std::vector<float>& samples, int yOffset) {
    if (samples.empty()) return;

    int midY = ctx.height() / 2 + yOffset;
    int halfHeight = ctx.height() / 2;

    float barWidth = static_cast<float>(ctx.width()) / samples.size();
    if (barWidth < 1.0f) barWidth = 1.0f;

    for (size_t i = 0; i < samples.size(); ++i) {
        float sample = samples[i];
        int barHeight = static_cast<int>(std::abs(sample) * halfHeight);

        int x1 = static_cast<int>(i * barWidth);
        int x2 = static_cast<int>((i + 1) * barWidth);

        Color color = getWaveformColor(settings, std::abs(sample));

        for (int x = x1; x < x2 && x < ctx.width(); ++x) {
            if (sample >= 0) {
                // Draw upward from center
                for (int y = midY; y < midY + barHeight && y < ctx.height(); ++y) {
                    ctx.setPixel(x, y, color);
                }
            } else {
                // Draw downward from center
                for (int y = midY - 1; y >= midY - barHeight && y >= 0; --y) {
                    ctx.setPixel(x, y, color);
                }
            }
        }
    }
}

void WaveformEffect::renderDots(RenderContext& ctx, const EffectSettings& settings,
                                 const std::vector<float>& samples, int yOffset) {
    if (samples.empty()) return;

    int midY = ctx.height() / 2 + yOffset;
    int halfHeight = ctx.height() / 2;

    float xStep = static_cast<float>(ctx.width()) / samples.size();

    Color color = getWaveformColor(settings, 0.5f);

    for (size_t i = 0; i < samples.size(); ++i) {
        int x = static_cast<int>(i * xStep);
        int y = midY + static_cast<int>(samples[i] * halfHeight);
        y = std::clamp(y, 0, ctx.height() - 1);

        // Draw a small dot (3x3 pixels)
        for (int dx = -1; dx <= 1; ++dx) {
            for (int dy = -1; dy <= 1; ++dy) {
                int px = x + dx;
                int py = y + dy;
                if (px >= 0 && px < ctx.width() && py >= 0 && py < ctx.height()) {
                    ctx.setPixel(px, py, color);
                }
            }
        }
    }
}

// ============================================================================
// Color helper
// ============================================================================

Color WaveformEffect::getWaveformColor(const EffectSettings& settings, float amplitude) const {
    // TODO: Use actual palette from settings
    // For now, use a cyan-based color
    float hue = 180.0f + amplitude * 60.0f;  // Cyan to blue-green
    // Hue is 0.0-1.0 in xlCore (not 0-360), so normalize
    return Color::fromHSV(hue / 360.0f, 0.8f, 1.0f);
}

// Register effect
XLCORE_REGISTER_EFFECT(WaveformEffect)

} // namespace xlCore
