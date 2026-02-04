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
 * @file FacesEffect.h
 * @brief Pure C++ face/lip-sync effect for xlCore.
 *
 * This effect renders mouth shapes synchronized to phonemes from
 * timing tracks, enabling lip-sync animation for singing faces.
 * Supports multiple face definition types:
 * - Rendered: Simple geometric shapes
 * - SingleNode/Coro: Single nodes per face element
 * - NodeRange: Range of nodes per face element
 * - Matrix: Image-based face rendering
 */

#include "../Effect.h"
#include "../ImageBuffer.h"

#include <string>
#include <vector>
#include <map>
#include <memory>
#include <optional>

namespace xlCore {

/**
 * @brief Standard phonemes supported by xLights.
 */
enum class Phoneme {
    AI,     ///< As in "eye"
    E,      ///< As in "bee"
    FV,     ///< F and V sounds
    L,      ///< L sound
    MBP,    ///< M, B, P sounds (lips together)
    O,      ///< As in "go"
    U,      ///< As in "blue"
    WQ,     ///< W and Q sounds
    Etc,    ///< Other sounds
    Rest,   ///< Mouth closed/rest position
    Off     ///< Face off (nothing displayed)
};

/**
 * @brief Eye state for face rendering.
 */
enum class EyeState {
    Auto,       ///< Automatic blinking
    Open,       ///< Eyes open
    Closed,     ///< Eyes closed
    Off         ///< Eyes not rendered
};

/**
 * @brief Eye blink frequency setting.
 */
enum class BlinkFrequency {
    Slowest,    ///< ~9 second max delay
    Slow,       ///< ~7 second max delay
    Normal,     ///< ~5.5 second max delay
    Fast,       ///< ~3.75 second max delay
    Fastest     ///< ~2 second max delay
};

/**
 * @brief Eye blink duration setting.
 */
enum class BlinkDuration {
    Slower,     ///< 50ms blink
    Normal,     ///< 100ms blink
    Long,       ///< 200ms blink
    Longer      ///< 400ms blink
};

/**
 * @brief Face definition type.
 */
enum class FaceType {
    Rendered,       ///< Simple geometric face
    SingleNode,     ///< Single node per element (Coro)
    NodeRange,      ///< Node range per element
    Matrix          ///< Image-based face
};

/**
 * @brief Single face element (mouth shape, eye state, etc.).
 *
 * Maps a phoneme or eye state to node indices or image.
 */
struct FaceElement {
    std::string name;               ///< Element name ("Mouth-AI", "Eyes-Open")
    std::vector<int> nodeIndices;   ///< Node indices for this element
    std::string imagePath;          ///< Image path for Matrix type
    Color color;                    ///< Custom color for this element
    bool hasCustomColor = false;    ///< Whether custom color is set

    FaceElement() = default;
    FaceElement(const std::string& n) : name(n) {}
};

/**
 * @brief Complete face definition.
 *
 * Contains all mouth shapes, eye states, and outline elements
 * for a face definition.
 */
struct FaceDefinition {
    std::string name;               ///< Definition name
    FaceType type = FaceType::Rendered;
    bool customColors = false;      ///< Using custom colors per element
    std::string imagePlacement;     ///< "Scale To Fit", "Centered", etc.

    // Face elements mapped by name
    std::map<std::string, FaceElement> elements;

    FaceDefinition() = default;
    FaceDefinition(const std::string& n, FaceType t) : name(n), type(t) {}

    // Helper to get element by name
    const FaceElement* getElement(const std::string& name) const;
    FaceElement* getElement(const std::string& name);

    // Get mouth element for phoneme
    const FaceElement* getMouth(Phoneme p) const;

    // Get eye element for state
    const FaceElement* getEyes(EyeState state) const;

    // Get face outline
    const FaceElement* getOutline() const;
};

/**
 * @brief Timing mark from timing track.
 *
 * Represents a single phoneme or text mark from a timing track.
 */
struct TimingMark {
    int startTimeMS = 0;
    int endTimeMS = 0;
    std::string label;              ///< Phoneme name or text
    int layerIndex = 0;             ///< Which layer of timing track
};

/**
 * @brief Interface for timing track access.
 *
 * Platform layer provides implementation to query timing marks.
 */
class TimingTrackProvider {
public:
    virtual ~TimingTrackProvider() = default;

    /**
     * @brief Get timing mark at specified time.
     * @param trackName Name of timing track
     * @param timeMS Time in milliseconds
     * @param layerIndex Which layer (0=phrases, 1=words, 2=phonemes)
     * @return TimingMark if found, empty optional otherwise
     */
    virtual std::optional<TimingMark> getTimingMark(const std::string& trackName,
                                                     int timeMS,
                                                     int layerIndex = 2) = 0;

    /**
     * @brief Get all timing marks in time range.
     */
    virtual std::vector<TimingMark> getTimingMarks(const std::string& trackName,
                                                    int startMS, int endMS,
                                                    int layerIndex = 2) = 0;

    /**
     * @brief Get list of available timing tracks.
     */
    virtual std::vector<std::string> availableTracks() = 0;

    /**
     * @brief Get singleton instance.
     */
    static TimingTrackProvider* instance();
    static void setInstance(TimingTrackProvider* provider);

private:
    static TimingTrackProvider* s_instance;
};

/**
 * @brief Interface for face definition access.
 *
 * Platform layer provides implementation to access model face definitions.
 */
class FaceDefinitionProvider {
public:
    virtual ~FaceDefinitionProvider() = default;

    /**
     * @brief Get face definition for model.
     * @param modelName Model name
     * @param definitionName Face definition name (empty for default)
     * @return FaceDefinition if found
     */
    virtual std::optional<FaceDefinition> getFaceDefinition(
        const std::string& modelName,
        const std::string& definitionName = "") = 0;

    /**
     * @brief Get available face definition names for model.
     */
    virtual std::vector<std::string> availableDefinitions(const std::string& modelName) = 0;

    /**
     * @brief Get singleton instance.
     */
    static FaceDefinitionProvider* instance();
    static void setInstance(FaceDefinitionProvider* provider);

private:
    static FaceDefinitionProvider* s_instance;
};

/**
 * @brief Faces effect render cache.
 *
 * Caches blink timing and other per-effect state.
 */
struct FacesRenderState {
    int nextBlinkTime = 0;      ///< Next blink start time in ms
    int blinkEndTime = 0;       ///< Current blink end time in ms
    std::map<std::string, ImageBuffer> imageCache;  ///< Cached face images
};

/**
 * @brief Faces effect for lip-sync animation.
 *
 * Renders mouth shapes synchronized to phonemes from timing tracks,
 * with configurable:
 * - Face definition (geometric, node-based, or image)
 * - Eye state and blinking
 * - Face outline
 * - Alpha/transparency
 * - Shimmer effect
 */
class FacesEffect : public Effect {
public:
    FacesEffect();
    ~FacesEffect() override = default;

    // Identity
    std::string name() const override { return "Faces"; }
    std::string description() const override { return "Lip-sync mouth shapes"; }
    std::string category() const override { return "Text"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Lifecycle
    void prepareForRender(const EffectSettings& settings) override;
    void cleanupAfterRender() override;

    // Capabilities
    bool canBeRandom() const override { return false; }
    bool appropriateOnNodes() const override { return false; }

    // Cloning
    std::unique_ptr<Effect> clone() const override;

protected:
    /**
     * @brief Render simple geometric face.
     */
    void renderGeometricFace(RenderContext& ctx, Phoneme phoneme, EyeState eyes,
                             bool outline, uint8_t alpha, bool shimmer);

    /**
     * @brief Render node-based face (Coro/NodeRange).
     */
    void renderNodeFace(RenderContext& ctx, const FaceDefinition& def,
                        Phoneme phoneme, EyeState eyes, bool outline,
                        const ColorPalette& palette, uint8_t alpha, bool shimmer);

    /**
     * @brief Render image-based face (Matrix).
     */
    void renderMatrixFace(RenderContext& ctx, const FaceDefinition& def,
                          Phoneme phoneme, EyeState eyes,
                          bool transparentBlack, int transparentLevel,
                          uint8_t alpha, bool shimmer);

    /**
     * @brief Get current phoneme from timing track.
     */
    Phoneme getCurrentPhoneme(const std::string& trackName, int timeMS);

    /**
     * @brief Parse phoneme string to enum.
     */
    Phoneme parsePhoneme(const std::string& str);

    /**
     * @brief Get eye state, handling auto-blink.
     */
    EyeState getEyeState(const std::string& eyeSetting, Phoneme phoneme,
                         int currentTimeMS);

    /**
     * @brief Calculate alpha for suppress-when-not-singing.
     */
    uint8_t calculateAlpha(const std::string& trackName, int currentTimeMS,
                           int leadFrames, bool fade, int frameTimeMS);

    /**
     * @brief Check if shimmer should show this frame.
     */
    bool shimmerState(const RenderState& state) const;

    /**
     * @brief Get max delay for blink frequency.
     */
    int getMaxBlinkDelay(BlinkFrequency freq) const;

    /**
     * @brief Get blink duration in ms.
     */
    int getBlinkDuration(BlinkDuration dur) const;

    /**
     * @brief Draw geometric mouth shape.
     */
    void drawMouth(RenderContext& ctx, Phoneme phoneme, const Color& color,
                   int height, int width);

    /**
     * @brief Draw geometric eyes.
     */
    void drawEyes(RenderContext& ctx, EyeState state, const Color& color,
                  int height, int width);

    /**
     * @brief Draw geometric face outline.
     */
    void drawOutline(RenderContext& ctx, const Color& color, int height, int width);

    /**
     * @brief Draw filled circle.
     */
    void drawFilledCircle(RenderContext& ctx, int cx, int cy, double radius,
                          const Color& color);

    /**
     * @brief Draw arc.
     */
    void drawArc(RenderContext& ctx, int cx, int cy, double radius,
                 int startDegrees, int endDegrees, const Color& color);

private:
    mutable FacesRenderState m_renderState;
    mutable std::string m_cachedDefinitionKey;
    mutable std::optional<FaceDefinition> m_cachedDefinition;
};

// Helper functions
Phoneme parsePhonemeString(const std::string& str);
EyeState parseEyeStateString(const std::string& str);
BlinkFrequency parseBlinkFrequency(const std::string& str);
BlinkDuration parseBlinkDuration(const std::string& str);
std::string phonemeToString(Phoneme p);
std::string eyeStateToString(EyeState e);

} // namespace xlCore
