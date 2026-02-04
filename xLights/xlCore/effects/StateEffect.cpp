/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "StateEffect.h"
#include "FacesEffect.h"  // For TimingTrackProvider
#include "../RenderContext.h"
#include "../StringUtils.h"

#include <cmath>
#include <algorithm>
#include <sstream>
#include <iomanip>

namespace xlCore {

// Static instance
StateDefinitionProvider* StateDefinitionProvider::s_instance = nullptr;

StateDefinitionProvider* StateDefinitionProvider::instance() {
    return s_instance;
}

void StateDefinitionProvider::setInstance(StateDefinitionProvider* provider) {
    s_instance = provider;
}

// ============================================================================
// StateDefinition methods
// ============================================================================

const StateElement* StateDefinition::getState(const std::string& name) const {
    // First try to find by name in nameToKey map
    auto keyIt = nameToKey.find(strings::toLower(name));
    if (keyIt != nameToKey.end()) {
        auto stateIt = states.find(keyIt->second);
        if (stateIt != states.end()) {
            return &stateIt->second;
        }
    }

    // Try direct lookup in states map
    for (const auto& [key, element] : states) {
        if (strings::toLower(element.name) == strings::toLower(name)) {
            return &element;
        }
    }

    return nullptr;
}

std::vector<std::string> StateDefinition::stateNames() const {
    std::vector<std::string> names;
    for (const auto& [key, element] : states) {
        if (!element.name.empty()) {
            names.push_back(element.name);
        }
    }
    return names;
}

// ============================================================================
// Helper functions
// ============================================================================

StateMode parseStateMode(const std::string& str) {
    std::string s = strings::toLower(strings::trim(str));
    if (s == "default") return StateMode::Default;
    if (s == "countdown") return StateMode::Countdown;
    if (s == "time countdown") return StateMode::TimeCountdown;
    if (s == "number") return StateMode::Number;
    if (s == "iterate") return StateMode::Iterate;
    return StateMode::Default;
}

StateColorMode parseStateColorMode(const std::string& str) {
    std::string s = strings::toLower(strings::trim(str));
    if (s == "graduate") return StateColorMode::Graduate;
    if (s == "cycle") return StateColorMode::Cycle;
    if (s == "allocate") return StateColorMode::Allocate;
    return StateColorMode::Graduate;
}

// ============================================================================
// StateEffect implementation
// ============================================================================

StateEffect::StateEffect() = default;

std::vector<EffectParameter> StateEffect::parameters() const {
    std::vector<EffectParameter> params;

    // State definition
    params.push_back(EffectParameter::createChoice(
        "CHOICE_State_StateDefinition", "State Definition", "",
        {}  // Populated dynamically from model
    ));

    // State selection (when not using timing track)
    params.push_back(EffectParameter::createChoice(
        "CHOICE_State_State", "State", "",
        {}  // Populated dynamically
    ));

    // Timing track
    params.push_back(EffectParameter::createChoice(
        "CHOICE_State_TimingTrack", "Timing Track", "",
        {}  // Populated dynamically from sequence
    ));

    // Display mode
    params.push_back(EffectParameter::createChoice(
        "CHOICE_State_Mode", "Mode", "Default",
        {"Default", "Countdown", "Time Countdown", "Number", "Iterate"}
    ));

    // Color mode
    params.push_back(EffectParameter::createChoice(
        "CHOICE_State_Color", "Color Mode", "Graduate",
        {"Graduate", "Cycle", "Allocate"}
    ));

    // Fade time
    params.push_back(EffectParameter::createInt(
        "SLIDER_State_Fade_Time", "Fade Time (ms)", 0, 0, 1000, false
    ));

    return params;
}

void StateEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Calculate current time in ms
    int currentTimeMS = static_cast<int>(state.timeSeconds * 1000);
    int frameTimeMS = 50;  // Default
    if (state.totalFrames > 1) {
        frameTimeMS = static_cast<int>((state.effectEndTime - state.effectStartTime) * 1000 / state.totalFrames);
    }

    // Get state definition
    std::string defName = settings.get("CHOICE_State_StateDefinition", "");
    if (defName.empty()) {
        return;
    }

    // Get definition from provider
    std::string modelName;  // TODO: Get from render state
    std::string cacheKey = modelName + "|" + defName;

    if (m_cachedDefinitionKey != cacheKey) {
        if (StateDefinitionProvider::instance()) {
            m_cachedDefinition = StateDefinitionProvider::instance()->getStateDefinition(modelName, defName);
        } else {
            m_cachedDefinition.reset();
        }
        m_cachedDefinitionKey = cacheKey;
    }

    if (!m_cachedDefinition) {
        return;
    }

    const StateDefinition& def = *m_cachedDefinition;

    // Get timing track info
    std::string trackName = settings.get("CHOICE_State_TimingTrack", "");
    std::string stateStr = settings.get("CHOICE_State_State", "");
    StateMode mode = parseStateMode(settings.get("CHOICE_State_Mode", "Default"));
    StateColorMode colorMode = parseStateColorMode(settings.get("CHOICE_State_Color", "Graduate"));
    int fadeTime = settings.getInt("SLIDER_State_Fade_Time", 0);

    // Get states to display
    std::vector<std::string> statesToDisplay;
    int intervalStartMS = -1;
    int intervalEndMS = -1;
    int intervalNumber = 0;

    if (!stateStr.empty()) {
        // Manual state selection
        statesToDisplay = getStatesToDisplay(stateStr, mode, &def, currentTimeMS, -1, -1);
    } else if (!trackName.empty() && TimingTrackProvider::instance()) {
        // Get from timing track
        auto mark = TimingTrackProvider::instance()->getTimingMark(trackName, currentTimeMS, 0);
        if (mark) {
            intervalStartMS = mark->startTimeMS;
            intervalEndMS = mark->endTimeMS;
            statesToDisplay = getStatesToDisplay(mark->label, mode, &def, currentTimeMS,
                                                 intervalStartMS, intervalEndMS);

            // Count interval number
            int effectStartMS = static_cast<int>(state.effectStartTime * 1000);
            auto marks = TimingTrackProvider::instance()->getTimingMarks(
                trackName, effectStartMS, currentTimeMS, 0);
            intervalNumber = marks.size();
        }
    }

    if (statesToDisplay.empty()) {
        return;
    }

    // Calculate alpha for fade
    uint8_t alpha = calculateAlpha(fadeTime, currentTimeMS, intervalStartMS, intervalEndMS, frameTimeMS);

    if (alpha == 0) {
        return;
    }

    // TODO: Get palette from render context
    ColorPalette palette;
    palette.colors.push_back(Color::White());
    palette.active.push_back(true);

    // Render states
    renderStates(ctx, def, statesToDisplay, colorMode, palette, state.progress, intervalNumber, alpha);
}

std::vector<std::string> StateEffect::getStatesToDisplay(
    const std::string& label,
    StateMode mode,
    const StateDefinition* def,
    int positionMS,
    int intervalStartMS,
    int intervalEndMS) {

    std::vector<std::string> states;

    switch (mode) {
        case StateMode::Default: {
            // Parse comma/space/semicolon separated state names
            std::vector<std::string> parts;
            std::string current;
            for (char c : label) {
                if (c == ' ' || c == ',' || c == ';' || c == ':') {
                    if (!current.empty()) {
                        parts.push_back(current);
                        current.clear();
                    }
                } else {
                    current += c;
                }
            }
            if (!current.empty()) {
                parts.push_back(current);
            }

            for (const auto& part : parts) {
                std::string lower = strings::toLower(part);
                if (lower == "*" || lower == "<all>") {
                    // Add all states
                    if (def) {
                        for (const auto& name : def->stateNames()) {
                            states.push_back(strings::toLower(name));
                        }
                    }
                } else {
                    states.push_back(lower);
                }
            }
            break;
        }

        case StateMode::Countdown: {
            int val = strings::parseInt(label, 0) * 1000;
            if (intervalStartMS >= 0) {
                int elapsed = positionMS - intervalStartMS;
                val = std::max(0, val - elapsed);
            }
            val = val / 1000;  // Convert back to seconds
            states = parseCountdownStates(val);
            break;
        }

        case StateMode::TimeCountdown: {
            int elapsedMS = 0;
            if (intervalStartMS >= 0) {
                elapsedMS = positionMS - intervalStartMS;
            }
            states = parseTimeCountdownStates(label, elapsedMS);
            break;
        }

        case StateMode::Number: {
            double num = strings::parseDouble(label, 0.0);
            states = parseNumberStates(num);
            break;
        }

        case StateMode::Iterate: {
            double progress = 0.0;
            if (intervalStartMS >= 0 && intervalEndMS > intervalStartMS) {
                progress = static_cast<double>(positionMS - intervalStartMS) /
                          (intervalEndMS - intervalStartMS);
                progress = std::clamp(progress, 0.0, 1.0);
            }
            states = getIterateStates(label, def, progress);
            break;
        }
    }

    return states;
}

std::vector<std::string> StateEffect::parseCountdownStates(int seconds) {
    std::vector<std::string> states;

    int v = seconds;
    bool force = false;

    // Thousands
    if ((v / 1000) * 1000 > 0) {
        states.push_back(std::to_string((v / 1000) * 1000));
        force = true;
    }
    v = v - (v / 1000) * 1000;

    // Hundreds
    if ((v / 100) * 100 > 0) {
        states.push_back(std::to_string((v / 100) * 100));
        force = true;
    } else if (force) {
        states.push_back("000");
    }
    v = v - (v / 100) * 100;

    // Tens
    if ((v / 10) * 10 > 0) {
        states.push_back(std::to_string((v / 10) * 10));
    } else if (force) {
        states.push_back("00");
    }
    v = v - (v / 10) * 10;

    // Ones
    states.push_back(std::to_string(v));

    return states;
}

std::vector<std::string> StateEffect::parseTimeCountdownStates(const std::string& timeStr, int elapsedMS) {
    std::vector<std::string> states;

    // Parse time string (HH:MM:SS or MM:SS)
    int hours = 0, minutes = 0, seconds = 0;

    auto parts = strings::split(timeStr, ':');
    if (parts.size() >= 3) {
        hours = strings::parseInt(parts[0], 0);
        minutes = strings::parseInt(parts[1], 0);
        seconds = strings::parseInt(parts[2], 0);
    } else if (parts.size() >= 2) {
        minutes = strings::parseInt(parts[0], 0);
        seconds = strings::parseInt(parts[1], 0);
    } else {
        seconds = strings::parseInt(timeStr, 0);
    }

    // Convert to total seconds and subtract elapsed
    int totalSeconds = hours * 3600 + minutes * 60 + seconds;
    totalSeconds = std::max(0, totalSeconds - (elapsedMS / 1000));

    // Convert back to M:SS format
    int m = totalSeconds / 60;
    int s = totalSeconds % 60;

    // Minute tens
    if ((m / 10) > 0) {
        states.push_back(std::to_string((m / 10) * 1000));
    } else {
        states.push_back("0000");
    }

    // Minute ones
    states.push_back(std::to_string((m % 10) * 100));

    // Second tens
    states.push_back(std::to_string((s / 10) * 10));

    // Second ones
    states.push_back(std::to_string(s % 10));

    // Colon
    states.push_back("colon");

    return states;
}

std::vector<std::string> StateEffect::parseNumberStates(double number) {
    std::vector<std::string> states;

    // For FM frequency display (e.g., 98.7)
    states.push_back("dot");

    // Decimal part
    double frac = number - static_cast<int>(number);
    int decimal = static_cast<int>(frac * 10 + 0.5);
    states.push_back(std::to_string(decimal));

    // Integer part
    int v = static_cast<int>(number);
    bool force = false;

    if ((v / 100) > 0) {
        states.push_back(std::to_string((v / 100) * 1000));
        force = true;
    }
    v = v % 100;

    if ((v / 10) > 0) {
        states.push_back(std::to_string((v / 10) * 100));
    } else if (force) {
        states.push_back("000");
    }
    v = v % 10;

    if (v > 0) {
        states.push_back(std::to_string(v * 10));
    } else {
        states.push_back("00");
    }

    return states;
}

std::vector<std::string> StateEffect::getIterateStates(
    const std::string& stateList,
    const StateDefinition* def,
    double progress) {

    // Parse state list
    std::vector<std::string> allStates;
    std::string current;

    for (char c : stateList) {
        if (c == ' ' || c == ',' || c == ';' || c == ':') {
            if (!current.empty()) {
                std::string lower = strings::toLower(current);
                if (lower == "*" || lower == "<all>") {
                    if (def) {
                        for (const auto& name : def->stateNames()) {
                            allStates.push_back(strings::toLower(name));
                        }
                    }
                } else {
                    allStates.push_back(lower);
                }
                current.clear();
            }
        } else {
            current += c;
        }
    }
    if (!current.empty()) {
        std::string lower = strings::toLower(current);
        if (lower == "*" || lower == "<all>") {
            if (def) {
                for (const auto& name : def->stateNames()) {
                    allStates.push_back(strings::toLower(name));
                }
            }
        } else {
            allStates.push_back(lower);
        }
    }

    if (allStates.empty()) {
        return {};
    }

    // Select state based on progress
    size_t index = static_cast<size_t>(progress * allStates.size());
    if (index >= allStates.size()) {
        index = allStates.size() - 1;
    }

    return {allStates[index]};
}

uint8_t StateEffect::calculateAlpha(int fadeTime, int currentTimeMS,
                                    int startTimeMS, int endTimeMS,
                                    int frameTimeMS) {
    if (fadeTime <= 0 || startTimeMS < 0 || endTimeMS < 0) {
        return 255;
    }

    uint8_t beforeAlpha = 0;
    uint8_t afterAlpha = 0;

    // Fade out near end
    if (endTimeMS - currentTimeMS < fadeTime) {
        beforeAlpha = static_cast<uint8_t>((endTimeMS - currentTimeMS) * 255 / fadeTime);
    }
    // Fade in near start
    else if (currentTimeMS + frameTimeMS - startTimeMS < fadeTime) {
        afterAlpha = static_cast<uint8_t>((currentTimeMS + frameTimeMS - startTimeMS) * 255 / fadeTime);
    } else {
        return 255;
    }

    return std::max(beforeAlpha, afterAlpha);
}

void StateEffect::renderStates(RenderContext& ctx,
                               const StateDefinition& def,
                               const std::vector<std::string>& states,
                               StateColorMode colorMode,
                               const ColorPalette& palette,
                               double progress,
                               int intervalNumber,
                               uint8_t alpha) {
    // For node-based rendering, we need access to model node data
    // This would be done through the RenderState's modelData pointer

    // For now, this is a placeholder that shows the concept
    // Full implementation requires integration with model node system

    for (size_t i = 0; i < states.size(); i++) {
        const StateElement* element = def.getState(states[i]);
        if (!element) {
            continue;
        }

        // Determine color
        Color color;
        if (element->hasCustomColor) {
            color = element->customColor;
        } else {
            switch (colorMode) {
                case StateColorMode::Graduate:
                    // Blend through palette based on progress
                    if (!palette.colors.empty()) {
                        size_t idx = static_cast<size_t>(progress * palette.colors.size());
                        idx = std::min(idx, palette.colors.size() - 1);
                        color = palette.colors[idx];
                    }
                    break;

                case StateColorMode::Cycle:
                    // Cycle through palette based on interval
                    if (!palette.colors.empty()) {
                        color = palette.colors[(intervalNumber - 1) % palette.colors.size()];
                    }
                    break;

                case StateColorMode::Allocate:
                    // Assign based on state index
                    if (!palette.colors.empty()) {
                        color = palette.colors[i % palette.colors.size()];
                    }
                    break;
            }
        }

        // Apply alpha
        color.alpha = static_cast<uint8_t>((static_cast<int>(color.alpha) * alpha) / 255);

        // TODO: Set node pixels through model interface
        // This requires access to the model's node system through RenderState
        // For each node index in element->nodeIndices, we would call
        // something like: ctx.setNodePixel(nodeIndex, color);
    }
}

std::unique_ptr<Effect> StateEffect::clone() const {
    return std::make_unique<StateEffect>();
}

// Register the effect
XLCORE_REGISTER_EFFECT(StateEffect)

} // namespace xlCore
