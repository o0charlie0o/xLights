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
 * @file StateEffect.h
 * @brief Pure C++ state machine effect for xlCore.
 *
 * This effect displays model states based on timing track labels,
 * enabling displays like countdown digits, FM frequencies, or
 * arbitrary state-based patterns.
 *
 * Modes:
 * - Default: Display states matching labels in timing track
 * - Countdown: Treat label as seconds and display countdown digits
 * - Time Countdown: Parse label as HH:MM:SS time and count down
 * - Number: Parse label as FM frequency (e.g., 98.7)
 * - Iterate: Cycle through listed states during each timing interval
 */

#include "../Effect.h"
#include "../Sequence.h"

#include <string>
#include <vector>
#include <map>
#include <memory>
#include <optional>

namespace xlCore {

// Forward declarations
class TimingTrackProvider;  // Defined in FacesEffect.h

/**
 * @brief State display mode.
 */
enum class StateMode {
    Default,        ///< Display matching states
    Countdown,      ///< Countdown from number
    TimeCountdown,  ///< Countdown from time string
    Number,         ///< Display as FM frequency digits
    Iterate         ///< Cycle through states in interval
};

/**
 * @brief Color assignment mode for states.
 */
enum class StateColorMode {
    Graduate,   ///< Color gradient through effect
    Cycle,      ///< Cycle through palette colors
    Allocate    ///< Assign colors based on state number
};

/**
 * @brief State definition element.
 *
 * Maps a state name to node indices.
 */
struct StateElement {
    std::string name;               ///< State name ("1", "colon", etc.)
    std::vector<int> nodeIndices;   ///< Node indices for this state
    Color customColor;              ///< Custom color if enabled
    bool hasCustomColor = false;

    StateElement() = default;
    StateElement(const std::string& n) : name(n) {}
};

/**
 * @brief State type enumeration.
 */
enum class StateType {
    SingleNode,     ///< Single node per state
    NodeRange       ///< Node range per state
};

/**
 * @brief Complete state definition.
 *
 * Contains all states for a model state definition.
 */
struct StateDefinition {
    std::string name;               ///< Definition name
    StateType type = StateType::NodeRange;
    bool customColors = false;

    // States mapped by state key (s001, s002, etc.)
    std::map<std::string, StateElement> states;

    // Map state name to key
    std::map<std::string, std::string> nameToKey;

    StateDefinition() = default;
    StateDefinition(const std::string& n, StateType t) : name(n), type(t) {}

    // Get state by name
    const StateElement* getState(const std::string& name) const;

    // Get all available state names
    std::vector<std::string> stateNames() const;
};

/**
 * @brief Interface for state definition access.
 *
 * Platform layer provides implementation to access model state definitions.
 */
class StateDefinitionProvider {
public:
    virtual ~StateDefinitionProvider() = default;

    /**
     * @brief Get state definition for model.
     * @param modelName Model name
     * @param definitionName State definition name
     * @return StateDefinition if found
     */
    virtual std::optional<StateDefinition> getStateDefinition(
        const std::string& modelName,
        const std::string& definitionName) = 0;

    /**
     * @brief Get available state definition names for model.
     */
    virtual std::vector<std::string> availableDefinitions(const std::string& modelName) = 0;

    /**
     * @brief Get available state names within a definition.
     */
    virtual std::vector<std::string> availableStates(
        const std::string& modelName,
        const std::string& definitionName) = 0;

    /**
     * @brief Get singleton instance.
     */
    static StateDefinitionProvider* instance();
    static void setInstance(StateDefinitionProvider* provider);

private:
    static StateDefinitionProvider* s_instance;
};

/**
 * @brief State effect for model state display.
 *
 * Displays model states based on timing track labels:
 * - States are defined in model configuration
 * - Timing track labels select which states to display
 * - Supports multiple display modes (countdown, number, etc.)
 * - Color can be graduated, cycled, or allocated by state
 */
class StateEffect : public Effect {
public:
    StateEffect();
    ~StateEffect() override = default;

    // Identity
    std::string name() const override { return "State"; }
    std::string description() const override { return "Display model states from timing track"; }
    std::string category() const override { return "Text"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Capabilities
    bool canBeRandom() const override { return false; }
    bool canRenderPartialTimeInterval() const override { return true; }

    // Cloning
    std::unique_ptr<Effect> clone() const override;

protected:
    /**
     * @brief Get states to display for current frame.
     *
     * Based on timing track label and display mode.
     */
    std::vector<std::string> getStatesToDisplay(
        const std::string& label,
        StateMode mode,
        const StateDefinition* def,
        int positionMS,
        int intervalStartMS,
        int intervalEndMS);

    /**
     * @brief Parse countdown states from number.
     */
    std::vector<std::string> parseCountdownStates(int seconds);

    /**
     * @brief Parse time countdown states.
     */
    std::vector<std::string> parseTimeCountdownStates(const std::string& timeStr, int elapsedMS);

    /**
     * @brief Parse FM number states.
     */
    std::vector<std::string> parseNumberStates(double number);

    /**
     * @brief Get states for iterate mode.
     */
    std::vector<std::string> getIterateStates(
        const std::string& stateList,
        const StateDefinition* def,
        double progress);

    /**
     * @brief Calculate alpha for fade time.
     */
    uint8_t calculateAlpha(int fadeTime, int currentTimeMS,
                           int startTimeMS, int endTimeMS,
                           int frameTimeMS);

    /**
     * @brief Render states to context.
     */
    void renderStates(RenderContext& ctx,
                      const StateDefinition& def,
                      const std::vector<std::string>& states,
                      StateColorMode colorMode,
                      const ColorPalette& palette,
                      double progress,
                      int intervalNumber,
                      uint8_t alpha);

private:
    mutable std::string m_cachedDefinitionKey;
    mutable std::optional<StateDefinition> m_cachedDefinition;
};

// Helper functions
StateMode parseStateMode(const std::string& str);
StateColorMode parseStateColorMode(const std::string& str);

} // namespace xlCore
