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
 * @file MusicEffect.h
 * @brief Music visualization effect with note/frequency detection.
 *
 * Provides music-reactive visualizations that respond to note detection:
 * - Morph: Notes morph from bottom to top
 * - Bounce: Notes bounce up and down
 * - Collide: Notes collide at center
 * - Separate: Notes expand from center
 * - On: Notes light up their bars
 *
 * This effect pre-analyzes the audio to detect note events, allowing
 * for smooth, predictable animations synchronized to music.
 */

#include "AudioReactiveEffect.h"

#include <vector>
#include <list>
#include <memory>

namespace xlCore {

/**
 * @brief Music effect display type.
 */
enum class MusicType {
    Morph,      // Notes morph from bottom to top
    Bounce,     // Notes bounce up then fall
    Collide,    // Notes meet at center
    Separate,   // Notes expand from center
    On          // Notes simply turn on/off
};

/**
 * @brief Music effect color treatment.
 */
enum class MusicColorTreatment {
    Distinct,   // Each note gets distinct color from palette
    Blend,      // Colors blend between notes
    Cycle       // Colors cycle through palette over time
};

/**
 * @brief Music effect note scaling mode.
 */
enum class MusicScaling {
    None,           // No scaling, raw sensitivity
    IndividualNotes, // Scale per note maximum
    AllNotes        // Scale to overall maximum
};

/**
 * @brief Represents a detected music event (note on/off).
 */
struct MusicEvent {
    int startFrame;     // Frame when note starts
    int duration;       // Duration in frames

    MusicEvent(int start, int dur) : startFrame(start), duration(dur) {}

    bool isActive(int frame) const {
        return frame >= startFrame && frame < startFrame + duration;
    }

    float offsetInDuration(int frame) const {
        if (duration <= 0 || frame >= startFrame + duration) return 1.0f;
        if (frame < startFrame) return 0.0f;
        return static_cast<float>(frame - startFrame) / duration;
    }
};

/**
 * @brief State for Music effect rendering.
 */
struct MusicState {
    // Events per bar/note column
    std::vector<std::vector<MusicEvent>> events;
    bool eventsGenerated = false;

    void reset() {
        events.clear();
        eventsGenerated = false;
    }
};

/**
 * @brief Music visualization effect.
 *
 * Analyzes audio spectrum to detect notes and visualizes them
 * with various animation styles. Notes are pre-detected at the
 * start of rendering for smooth, predictable animations.
 *
 * Parameters:
 * - Bars: Number of frequency bars/columns
 * - Type: Animation style (morph, bounce, collide, etc.)
 * - Sensitivity: Note detection threshold (0-100)
 * - Scale: Scale bars to buffer width
 * - Scaling: Note scaling mode
 * - Offset: X offset in pixels
 * - StartNote/EndNote: MIDI note range
 * - Colour: Color treatment (distinct, blend, cycle)
 * - Fade: Fade notes out
 * - LogarithmicX: Use logarithmic frequency scale
 */
class MusicEffect : public AudioReactiveEffect {
public:
    MusicEffect();
    ~MusicEffect() override = default;

    // Identity
    std::string name() const override { return "Music Effect"; }
    std::string description() const override {
        return "Music-reactive visualization with note detection";
    }
    std::string tooltip() const override {
        return "Visualize detected musical notes with various animation styles";
    }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings,
                const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<MusicEffect>(*this);
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
    MusicState m_state;

    // Event generation (done once per effect)
    void generateEvents(const AudioContext& audio, const RenderState& state,
                        int bars, int startNote, int endNote,
                        MusicScaling scaling, int sensitivity, bool logarithmic);

    // Render methods for each type
    void renderMorph(RenderContext& ctx, const EffectSettings& settings,
                     const RenderState& state, int x, int bars,
                     const std::vector<MusicEvent>& events,
                     MusicColorTreatment treatment, bool bounce, bool fade);

    void renderCollide(RenderContext& ctx, const EffectSettings& settings,
                       const RenderState& state, int x, int bars,
                       const std::vector<MusicEvent>& events,
                       MusicColorTreatment treatment, bool collide, bool fade);

    void renderOn(RenderContext& ctx, const EffectSettings& settings,
                  const RenderState& state, int x, int bars,
                  const std::vector<MusicEvent>& events,
                  MusicColorTreatment treatment, bool fade);

    // Type/color decoding
    static MusicType decodeType(const std::string& type);
    static MusicColorTreatment decodeColorTreatment(const std::string& treatment);
    static MusicScaling decodeScaling(const std::string& scaling);

    // Color helper
    Color getNoteColor(const EffectSettings& settings, int bar, int totalBars,
                       MusicColorTreatment treatment, float progress) const;
};

} // namespace xlCore
