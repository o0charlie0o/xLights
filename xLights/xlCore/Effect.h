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
 * @file Effect.h
 * @brief Pure C++ effect base class and supporting types.
 *
 * This header provides the foundation for the modernized effect system:
 * - RenderState: Timing and context information for rendering
 * - EffectParameter: Metadata for UI auto-generation
 * - Effect: Abstract base class for all effects
 * - EffectRegistry: Factory/registry for effect types
 *
 * NOTE: EffectSettings is defined in Sequence.h and should be included
 * via that header or via xlCore.h.
 *
 * Design principles:
 * - Zero wxWidgets dependencies
 * - Thread-safe by design
 * - Modern C++17/20 idioms
 * - Separation of rendering from UI
 */

#include <string>
#include <vector>
#include <unordered_map>
#include <memory>
#include <optional>
#include <mutex>
#include <functional>

#include "Types.h"
#include "Color.h"

namespace xlCore {

// Forward declarations
class RenderContext;
class EffectSettings;  // Defined in Sequence.h

/**
 * @brief Render state passed to each render call.
 *
 * Contains all timing information and context needed for rendering.
 * Effects should use these values rather than querying external state.
 */
struct RenderState {
    // Time information
    double timeSeconds = 0.0;       ///< Current time in sequence (seconds)
    double effectStartTime = 0.0;   ///< When this effect starts (seconds)
    double effectEndTime = 0.0;     ///< When this effect ends (seconds)
    double progress = 0.0;          ///< 0.0 to 1.0 progress through effect

    // Frame information
    int frameIndex = 0;             ///< Frame number within effect (0-based)
    int totalFrames = 0;            ///< Total frames in this effect
    int sequenceFrameIndex = 0;     ///< Frame number in entire sequence

    // Buffer information
    int bufferWidth = 0;            ///< Width of render buffer
    int bufferHeight = 0;           ///< Height of render buffer

    // Random seed for reproducible effects
    uint32_t randomSeed = 0;

    // Model reference (opaque pointer for node queries during migration)
    const void* modelData = nullptr;

    /**
     * @brief Calculate progress from current time.
     */
    void updateProgress() {
        double duration = effectEndTime - effectStartTime;
        if (duration > 0.0) {
            progress = (timeSeconds - effectStartTime) / duration;
            progress = std::clamp(progress, 0.0, 1.0);
        } else {
            progress = 0.0;
        }
    }
};

/**
 * @brief Effect parameter types for UI generation.
 */
enum class ParameterType {
    Int,        ///< Integer slider/spinbox
    Double,     ///< Floating-point slider
    Bool,       ///< Checkbox
    String,     ///< Text input
    Color,      ///< Color picker
    Choice,     ///< Dropdown selection
    File,       ///< File picker
    ValueCurve, ///< Animated value curve
    ColorCurve  ///< Animated color curve
};

/**
 * @brief Metadata for a single effect parameter.
 *
 * Used by UI layer to auto-generate effect control panels.
 */
struct EffectParameter {
    std::string key;            ///< Settings key (e.g., "E_SLIDER_Bars_BarCount")
    std::string displayName;    ///< Human-readable name (e.g., "Bar Count")
    std::string description;    ///< Tooltip/help text
    ParameterType type = ParameterType::Int;

    std::string defaultValue;   ///< Default value as string

    // Numeric constraints (for Int, Double types)
    std::optional<double> minValue;
    std::optional<double> maxValue;
    std::optional<double> step;

    // Choice options (for Choice type)
    std::vector<std::string> choices;

    // File filter (for File type)
    std::string fileFilter;     ///< e.g., "Image files|*.png;*.jpg"

    // Value curve support
    bool supportsValueCurve = false;
    int valueCurveDivisor = 1;

    // UI grouping
    std::string group;          ///< Group name for organizing parameters

    /**
     * @brief Create an integer parameter.
     */
    static EffectParameter createInt(
        const std::string& key,
        const std::string& displayName,
        int defaultVal,
        int minVal,
        int maxVal,
        bool valueCurve = false);

    /**
     * @brief Create a double parameter.
     */
    static EffectParameter createDouble(
        const std::string& key,
        const std::string& displayName,
        double defaultVal,
        double minVal,
        double maxVal,
        double step = 0.1);

    /**
     * @brief Create a boolean parameter.
     */
    static EffectParameter createBool(
        const std::string& key,
        const std::string& displayName,
        bool defaultVal);

    /**
     * @brief Create a choice/dropdown parameter.
     */
    static EffectParameter createChoice(
        const std::string& key,
        const std::string& displayName,
        const std::string& defaultVal,
        const std::vector<std::string>& choices);

    /**
     * @brief Create a color parameter.
     */
    static EffectParameter createColor(
        const std::string& key,
        const std::string& displayName,
        const Color& defaultVal);

    /**
     * @brief Create a file picker parameter.
     */
    static EffectParameter createFile(
        const std::string& key,
        const std::string& displayName,
        const std::string& filter);
};

/**
 * @brief Abstract base class for all effects.
 *
 * This replaces the wxWidgets-dependent RenderableEffect class.
 * Effects inherit from this class and implement the render() method.
 *
 * Thread safety:
 * - Individual Effect instances are NOT thread-safe.
 * - Each rendering thread should have its own Effect instance.
 * - The EffectRegistry is thread-safe for lookups.
 *
 * Lifecycle:
 * 1. Create effect instance (or get from registry)
 * 2. Call prepareForRender() before rendering sequence
 * 3. Call render() for each frame
 * 4. Call cleanupAfterRender() when done
 */
class Effect {
public:
    virtual ~Effect() = default;

    // ========== Identity ==========

    /**
     * @brief Get effect name (unique identifier).
     *
     * This should match the legacy effect name for migration compatibility.
     * Examples: "Bars", "Fire", "Butterfly"
     */
    virtual std::string name() const = 0;

    /**
     * @brief Get human-readable description.
     */
    virtual std::string description() const { return ""; }

    /**
     * @brief Get effect category for UI grouping.
     *
     * Standard categories: "Patterns", "Particle", "Text", "3D", "Utility"
     */
    virtual std::string category() const { return "Misc"; }

    /**
     * @brief Get tooltip text for UI.
     */
    virtual std::string tooltip() const { return description(); }

    // ========== Rendering ==========

    /**
     * @brief Render one frame of the effect.
     *
     * This is the core method that all effects must implement.
     *
     * @param ctx The rendering context to draw to
     * @param settings Effect parameters for this instance
     * @param state Timing and context information
     *
     * Thread safety: Not thread-safe. Each thread needs its own Effect instance.
     */
    virtual void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) = 0;

    // ========== Threading ==========

    /**
     * @brief Check if effect can safely render on background thread.
     *
     * Most effects can, but some that access shared resources cannot.
     */
    virtual bool canRenderOnBackgroundThread() const { return true; }

    /**
     * @brief Check if effect supports render caching.
     *
     * Effects with random or time-varying elements may not be cacheable.
     */
    virtual bool supportsRenderCache(const EffectSettings& settings) const { return true; }

    // ========== Parameters ==========

    /**
     * @brief Get parameter metadata for UI generation.
     *
     * Returns a list of all parameters this effect supports.
     * UI can use this to auto-generate control panels.
     */
    virtual std::vector<EffectParameter> parameters() const = 0;

    /**
     * @brief Get default settings for this effect.
     *
     * Default implementation builds from parameters().
     */
    virtual EffectSettings defaultSettings() const;

    // ========== Lifecycle ==========

    /**
     * @brief Prepare for rendering a sequence.
     *
     * Called once before render loop begins. Use for expensive setup.
     */
    virtual void prepareForRender(const EffectSettings& settings) {}

    /**
     * @brief Cleanup after rendering.
     *
     * Called when rendering is complete or effect is removed.
     */
    virtual void cleanupAfterRender() {}

    // ========== File References ==========

    /**
     * @brief Get list of external file references.
     *
     * Used for media effects (pictures, videos) to track dependencies.
     */
    virtual std::vector<std::string> fileReferences(const EffectSettings& settings) const {
        return {};
    }

    // ========== Capabilities ==========

    /**
     * @brief Check if effect can render partial time intervals.
     *
     * Some effects can optimize by only rendering changed portions.
     */
    virtual bool canRenderPartialTimeInterval() const { return false; }

    /**
     * @brief Check if effect is appropriate for node-level rendering.
     *
     * Most effects work on the full buffer, but some are node-specific.
     */
    virtual bool appropriateOnNodes() const { return true; }

    /**
     * @brief Check if effect can be randomly selected.
     *
     * Used by auto-generation features.
     */
    virtual bool canBeRandom() const { return true; }

    /**
     * @brief Get supported color count (-1 for unlimited).
     */
    virtual int colorSupportedCount() const { return -1; }

    /**
     * @brief Check if effect supports linear color curves.
     */
    virtual bool supportsLinearColorCurves(const EffectSettings& settings) const { return false; }

    /**
     * @brief Check if effect supports radial color curves.
     */
    virtual bool supportsRadialColorCurves(const EffectSettings& settings) const { return false; }

    // ========== Cloning ==========

    /**
     * @brief Create a clone of this effect.
     *
     * Used to create per-thread instances for parallel rendering.
     */
    virtual std::unique_ptr<Effect> clone() const = 0;

protected:
    Effect() = default;
    Effect(const Effect&) = default;
    Effect& operator=(const Effect&) = default;
    Effect(Effect&&) = default;
    Effect& operator=(Effect&&) = default;
};

/**
 * @brief Thread-safe registry for effect types.
 *
 * Effects register themselves with the registry. Rendering code
 * looks up effects by name and clones them for use.
 */
class EffectRegistry {
public:
    /**
     * @brief Get the singleton instance.
     */
    static EffectRegistry& instance();

    /**
     * @brief Register an effect type.
     *
     * The effect pointer becomes the prototype for cloning.
     */
    void registerEffect(std::unique_ptr<Effect> effect);

    /**
     * @brief Get an effect by name.
     *
     * Returns nullptr if not found.
     * Note: Returns the prototype, not a clone. Use clone() if you need
     * a mutable instance.
     */
    const Effect* getEffect(const std::string& name) const;

    /**
     * @brief Create a new instance of an effect by name.
     *
     * Returns nullptr if effect not found.
     */
    std::unique_ptr<Effect> createEffect(const std::string& name) const;

    /**
     * @brief Get all registered effect names.
     */
    std::vector<std::string> effectNames() const;

    /**
     * @brief Get effects in a specific category.
     */
    std::vector<std::string> effectsInCategory(const std::string& category) const;

    /**
     * @brief Get all categories.
     */
    std::vector<std::string> categories() const;

    /**
     * @brief Check if an effect is registered.
     */
    bool hasEffect(const std::string& name) const;

private:
    EffectRegistry() = default;
    ~EffectRegistry() = default;

    // Non-copyable
    EffectRegistry(const EffectRegistry&) = delete;
    EffectRegistry& operator=(const EffectRegistry&) = delete;

    std::unordered_map<std::string, std::unique_ptr<Effect>> m_effects;
    mutable std::mutex m_mutex;
};

/**
 * @brief Helper macro for registering effects.
 *
 * Usage:
 *   XLCORE_REGISTER_EFFECT(BarsEffect)
 *
 * Place in .cpp file at global scope.
 */
#define XLCORE_REGISTER_EFFECT(EffectClass) \
    namespace { \
        static bool _registered_##EffectClass = []() { \
            xlCore::EffectRegistry::instance().registerEffect( \
                std::make_unique<EffectClass>()); \
            return true; \
        }(); \
    }

} // namespace xlCore
