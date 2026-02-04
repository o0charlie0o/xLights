/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "MusicEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <algorithm>
#include <cmath>
#include <map>

namespace xlCore {

// Minimum event length in frames to avoid flicker
constexpr int MINIMUM_EVENT_LENGTH = 5;

MusicEffect::MusicEffect() {
    m_state.reset();
}

void MusicEffect::prepareForRender(const EffectSettings& settings) {
    m_state.reset();
}

void MusicEffect::cleanupAfterRender() {
    m_state.reset();
}

std::vector<EffectParameter> MusicEffect::parameters() const {
    return {
        EffectParameter::createInt("SLIDER_Music_Bars", "Bars", 20, 1, 100, true),
        EffectParameter::createChoice("CHOICE_Music_Type", "Type", "Morph",
            {"Morph", "Bounce", "Collide", "Separate", "On"}),
        EffectParameter::createInt("SLIDER_Music_Sensitivity", "Sensitivity", 50, 0, 100),
        EffectParameter::createBool("CHECKBOX_Music_Scale", "Scale to Width", false),
        EffectParameter::createChoice("CHOICE_Music_Scaling", "Scaling", "None",
            {"None", "Individual Notes", "All Notes"}),
        EffectParameter::createInt("SLIDER_Music_Offset", "X Offset", 0, -100, 100, true),
        EffectParameter::createInt("SLIDER_Music_StartNote", "Start Note", 60, 0, 127),
        EffectParameter::createInt("SLIDER_Music_EndNote", "End Note", 80, 0, 127),
        EffectParameter::createChoice("CHOICE_Music_Colour", "Colour", "Distinct",
            {"Distinct", "Blend", "Cycle"}),
        EffectParameter::createBool("CHECKBOX_Music_Fade", "Fade", false),
        EffectParameter::createBool("CHECKBOX_Music_LogarithmicX", "Logarithmic X", false)
    };
}

void MusicEffect::render(RenderContext& ctx, const EffectSettings& settings,
                         const RenderState& state) {
    // Audio context
    AudioContext audio(nullptr, state.timeSeconds);
    // TODO: AudioAnalyzer will be passed via RenderState services

    if (!audio.hasAudio()) {
        return;
    }

    // Get parameters
    int bars = settings.getInt("SLIDER_Music_Bars", 20);
    std::string typeStr = settings.get("CHOICE_Music_Type", "Morph");
    MusicType type = decodeType(typeStr);
    int sensitivity = settings.getInt("SLIDER_Music_Sensitivity", 50);
    bool scale = settings.getBool("CHECKBOX_Music_Scale", false);
    std::string scalingStr = settings.get("CHOICE_Music_Scaling", "None");
    MusicScaling scaling = decodeScaling(scalingStr);
    int offset = settings.getInt("SLIDER_Music_Offset", 0);
    int startNote = settings.getInt("SLIDER_Music_StartNote", 60);
    int endNote = settings.getInt("SLIDER_Music_EndNote", 80);
    std::string colourStr = settings.get("CHOICE_Music_Colour", "Distinct");
    MusicColorTreatment treatment = decodeColorTreatment(colourStr);
    bool fade = settings.getBool("CHECKBOX_Music_Fade", false);
    bool logarithmic = settings.getBool("CHECKBOX_Music_LogarithmicX", false);

    // Ensure startNote <= endNote
    if (startNote > endNote) {
        std::swap(startNote, endNote);
    }

    // Calculate actual bars and notes per bar
    int actualBars = std::min(bars, std::min(endNote - startNote + 1, ctx.width() - offset));
    if (actualBars <= 0) actualBars = 1;

    float lightsPerBar = scale ? static_cast<float>(ctx.width() - offset) / actualBars : 1.0f;

    // Generate events on first frame
    if (!m_state.eventsGenerated) {
        generateEvents(audio, state, actualBars, startNote, endNote, scaling,
                       sensitivity, logarithmic);
        m_state.eventsGenerated = true;
    }

    // Calculate current frame within effect
    int currentFrame = state.frameIndex;

    // Render each bar
    for (size_t barIdx = 0; barIdx < m_state.events.size(); ++barIdx) {
        const auto& events = m_state.events[barIdx];

        // Calculate x position range for this bar
        int xStart = offset + static_cast<int>(barIdx * lightsPerBar);
        int xEnd = offset + static_cast<int>((barIdx + 1) * lightsPerBar);

        // Render to each x position in range
        for (int x = xStart; x < xEnd && x < ctx.width(); ++x) {
            switch (type) {
                case MusicType::Morph:
                    renderMorph(ctx, settings, state, x, actualBars, events, treatment, false, fade);
                    break;
                case MusicType::Bounce:
                    renderMorph(ctx, settings, state, x, actualBars, events, treatment, true, fade);
                    break;
                case MusicType::Collide:
                    renderCollide(ctx, settings, state, x, actualBars, events, treatment, true, fade);
                    break;
                case MusicType::Separate:
                    renderCollide(ctx, settings, state, x, actualBars, events, treatment, false, fade);
                    break;
                case MusicType::On:
                    renderOn(ctx, settings, state, x, actualBars, events, treatment, fade);
                    break;
            }
        }
    }
}

// ============================================================================
// Event generation
// ============================================================================

void MusicEffect::generateEvents(const AudioContext& audio, const RenderState& state,
                                  int bars, int startNote, int endNote,
                                  MusicScaling scaling, int sensitivity, bool logarithmic) {
    // This would analyze the full effect duration to find note events
    // For now, create placeholder events based on simple threshold detection
    // In full integration, this would use AudioAnalyzer::getSpectrum across time

    m_state.events.clear();
    m_state.events.resize(bars);

    // Calculate notes per bar
    float notesPerBar = static_cast<float>(endNote - startNote + 1) / bars;

    // Per-bar maximum tracking for scaling
    std::vector<float> barMax(bars, 0.0f);
    float overallMax = 0.0f;

    // For demonstration, generate some placeholder events
    // Real implementation would iterate through frames and detect note onsets
    int totalFrames = state.totalFrames;
    float sensitivityThreshold = sensitivity / 100.0f;

    // Simulate event detection by creating events at regular intervals
    // In real implementation, this would analyze spectrum data
    for (int bar = 0; bar < bars; ++bar) {
        // Create some demo events (in real code, detect from audio)
        int eventSpacing = totalFrames / (bars * 2);
        if (eventSpacing < MINIMUM_EVENT_LENGTH) {
            eventSpacing = MINIMUM_EVENT_LENGTH;
        }

        for (int frame = bar * eventSpacing / bars; frame < totalFrames;
             frame += eventSpacing + (bar % 3) * 5) {
            // Create an event of varying length
            int duration = MINIMUM_EVENT_LENGTH + (frame % 10);
            if (frame + duration <= totalFrames) {
                m_state.events[bar].push_back(MusicEvent(frame, duration));
            }
        }
    }
}

// ============================================================================
// Render methods
// ============================================================================

void MusicEffect::renderMorph(RenderContext& ctx, const EffectSettings& settings,
                               const RenderState& state, int x, int bars,
                               const std::vector<MusicEvent>& events,
                               MusicColorTreatment treatment, bool bounce, bool fade) {
    int currentFrame = state.frameIndex;

    for (const auto& event : events) {
        if (!event.isActive(currentFrame)) continue;

        float progress = event.offsetInDuration(currentFrame);

        // Calculate y position based on progress
        int yMax = ctx.height() - 1;
        int y;

        if (bounce) {
            // Bounce: up then down
            if (progress < 0.5f) {
                y = static_cast<int>(progress * 2 * yMax);
            } else {
                y = static_cast<int>((1.0f - progress) * 2 * yMax);
            }
        } else {
            // Morph: bottom to top
            y = static_cast<int>(progress * yMax);
        }

        // Get color
        Color color = getNoteColor(settings, x, ctx.width(), treatment, progress);

        // Apply fade
        if (fade) {
            uint8_t alpha = static_cast<uint8_t>((1.0f - progress) * 255);
            color.alpha = alpha;
        }

        // Draw the note
        ctx.setPixel(x, y, color);
    }
}

void MusicEffect::renderCollide(RenderContext& ctx, const EffectSettings& settings,
                                 const RenderState& state, int x, int bars,
                                 const std::vector<MusicEvent>& events,
                                 MusicColorTreatment treatment, bool collide, bool fade) {
    int currentFrame = state.frameIndex;
    int midY = ctx.height() / 2;

    for (const auto& event : events) {
        if (!event.isActive(currentFrame)) continue;

        float progress = event.offsetInDuration(currentFrame);

        // Get color
        Color color = getNoteColor(settings, x, ctx.width(), treatment, progress);

        if (fade) {
            uint8_t alpha = static_cast<uint8_t>((1.0f - progress) * 255);
            color.alpha = alpha;
        }

        if (collide) {
            // Notes come from edges and meet at center
            int yTop = static_cast<int>((1.0f - progress) * midY) + midY;
            int yBottom = midY - static_cast<int>((1.0f - progress) * midY);

            ctx.setPixel(x, yTop, color);
            ctx.setPixel(x, yBottom, color);
        } else {
            // Notes start at center and expand outward
            int yTop = midY + static_cast<int>(progress * midY);
            int yBottom = midY - static_cast<int>(progress * midY);

            ctx.setPixel(x, yTop, color);
            ctx.setPixel(x, yBottom, color);
        }
    }
}

void MusicEffect::renderOn(RenderContext& ctx, const EffectSettings& settings,
                           const RenderState& state, int x, int bars,
                           const std::vector<MusicEvent>& events,
                           MusicColorTreatment treatment, bool fade) {
    int currentFrame = state.frameIndex;

    for (const auto& event : events) {
        if (!event.isActive(currentFrame)) continue;

        float progress = event.offsetInDuration(currentFrame);

        Color color = getNoteColor(settings, x, ctx.width(), treatment, progress);

        if (fade) {
            uint8_t alpha = static_cast<uint8_t>((1.0f - progress) * 255);
            color.alpha = alpha;
        }

        // Fill the entire column
        for (int y = 0; y < ctx.height(); ++y) {
            ctx.setPixel(x, y, color);
        }

        break;  // Only process first active event per column
    }
}

// ============================================================================
// Type decoding
// ============================================================================

MusicType MusicEffect::decodeType(const std::string& type) {
    if (type == "Morph") return MusicType::Morph;
    if (type == "Bounce") return MusicType::Bounce;
    if (type == "Collide") return MusicType::Collide;
    if (type == "Separate") return MusicType::Separate;
    if (type == "On") return MusicType::On;
    return MusicType::Morph;
}

MusicColorTreatment MusicEffect::decodeColorTreatment(const std::string& treatment) {
    if (treatment == "Distinct") return MusicColorTreatment::Distinct;
    if (treatment == "Blend") return MusicColorTreatment::Blend;
    if (treatment == "Cycle") return MusicColorTreatment::Cycle;
    return MusicColorTreatment::Distinct;
}

MusicScaling MusicEffect::decodeScaling(const std::string& scaling) {
    if (scaling == "None") return MusicScaling::None;
    if (scaling == "Individual Notes") return MusicScaling::IndividualNotes;
    if (scaling == "All Notes") return MusicScaling::AllNotes;
    return MusicScaling::None;
}

Color MusicEffect::getNoteColor(const EffectSettings& settings, int bar, int totalBars,
                                 MusicColorTreatment treatment, float progress) const {
    // Simple color generation based on position
    // TODO: Integrate with actual color palette from settings

    float colorPos = 0.0f;

    switch (treatment) {
        case MusicColorTreatment::Distinct:
            colorPos = static_cast<float>(bar) / totalBars;
            break;
        case MusicColorTreatment::Blend:
            colorPos = progress;
            break;
        case MusicColorTreatment::Cycle:
            colorPos = std::fmod(static_cast<float>(bar) / totalBars + progress, 1.0f);
            break;
    }

    // Generate rainbow color
    // Hue is 0.0-1.0 in xlCore, so normalize
    float hue = colorPos;
    return Color::fromHSV(hue, 1.0f, 1.0f);
}

// Register effect
XLCORE_REGISTER_EFFECT(MusicEffect)

} // namespace xlCore
