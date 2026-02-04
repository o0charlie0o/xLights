/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "Effect.h"
#include "Sequence.h"  // For EffectSettings

#include <algorithm>
#include <sstream>
#include <cctype>
#include <stdexcept>

namespace xlCore {

// ============================================================================
// EffectParameter Implementation
// ============================================================================

EffectParameter EffectParameter::createInt(
    const std::string& key,
    const std::string& displayName,
    int defaultVal,
    int minVal,
    int maxVal,
    bool valueCurve) {

    EffectParameter p;
    p.key = key;
    p.displayName = displayName;
    p.type = ParameterType::Int;
    p.defaultValue = std::to_string(defaultVal);
    p.minValue = static_cast<double>(minVal);
    p.maxValue = static_cast<double>(maxVal);
    p.supportsValueCurve = valueCurve;
    return p;
}

EffectParameter EffectParameter::createDouble(
    const std::string& key,
    const std::string& displayName,
    double defaultVal,
    double minVal,
    double maxVal,
    double step) {

    EffectParameter p;
    p.key = key;
    p.displayName = displayName;
    p.type = ParameterType::Double;
    p.defaultValue = std::to_string(defaultVal);
    p.minValue = minVal;
    p.maxValue = maxVal;
    p.step = step;
    return p;
}

EffectParameter EffectParameter::createBool(
    const std::string& key,
    const std::string& displayName,
    bool defaultVal) {

    EffectParameter p;
    p.key = key;
    p.displayName = displayName;
    p.type = ParameterType::Bool;
    p.defaultValue = defaultVal ? "1" : "0";
    return p;
}

EffectParameter EffectParameter::createChoice(
    const std::string& key,
    const std::string& displayName,
    const std::string& defaultVal,
    const std::vector<std::string>& choices) {

    EffectParameter p;
    p.key = key;
    p.displayName = displayName;
    p.type = ParameterType::Choice;
    p.defaultValue = defaultVal;
    p.choices = choices;
    return p;
}

EffectParameter EffectParameter::createColor(
    const std::string& key,
    const std::string& displayName,
    const Color& defaultVal) {

    EffectParameter p;
    p.key = key;
    p.displayName = displayName;
    p.type = ParameterType::Color;
    p.defaultValue = defaultVal.toString();
    return p;
}

EffectParameter EffectParameter::createFile(
    const std::string& key,
    const std::string& displayName,
    const std::string& filter) {

    EffectParameter p;
    p.key = key;
    p.displayName = displayName;
    p.type = ParameterType::File;
    p.fileFilter = filter;
    return p;
}

// ============================================================================
// Effect Implementation
// ============================================================================

EffectSettings Effect::defaultSettings() const {
    EffectSettings settings;
    for (const auto& param : parameters()) {
        settings.set(param.key, param.defaultValue);
    }
    return settings;
}

// ============================================================================
// EffectRegistry Implementation
// ============================================================================

EffectRegistry& EffectRegistry::instance() {
    static EffectRegistry registry;
    return registry;
}

void EffectRegistry::registerEffect(std::unique_ptr<Effect> effect) {
    if (!effect) return;

    std::lock_guard<std::mutex> lock(m_mutex);
    std::string effectName = effect->name();
    m_effects[effectName] = std::move(effect);
}

const Effect* EffectRegistry::getEffect(const std::string& name) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_effects.find(name);
    return (it != m_effects.end()) ? it->second.get() : nullptr;
}

std::unique_ptr<Effect> EffectRegistry::createEffect(const std::string& name) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto it = m_effects.find(name);
    if (it != m_effects.end()) {
        return it->second->clone();
    }
    return nullptr;
}

std::vector<std::string> EffectRegistry::effectNames() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::vector<std::string> names;
    names.reserve(m_effects.size());
    for (const auto& [name, effect] : m_effects) {
        names.push_back(name);
    }
    std::sort(names.begin(), names.end());
    return names;
}

std::vector<std::string> EffectRegistry::effectsInCategory(const std::string& category) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::vector<std::string> names;
    for (const auto& [name, effect] : m_effects) {
        if (effect->category() == category) {
            names.push_back(name);
        }
    }
    std::sort(names.begin(), names.end());
    return names;
}

std::vector<std::string> EffectRegistry::categories() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::vector<std::string> cats;
    for (const auto& [name, effect] : m_effects) {
        std::string cat = effect->category();
        if (std::find(cats.begin(), cats.end(), cat) == cats.end()) {
            cats.push_back(cat);
        }
    }
    std::sort(cats.begin(), cats.end());
    return cats;
}

bool EffectRegistry::hasEffect(const std::string& name) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_effects.find(name) != m_effects.end();
}

} // namespace xlCore
