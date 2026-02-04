/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "EffectManager.h"
#include "RenderContext.h"

#include <algorithm>
#include <random>
#include <chrono>

namespace xlCore {

// Thread-local effect pool
thread_local std::unique_ptr<EffectPool> EffectManager::s_threadPool;

// ============================================================================
// EffectInstance Implementation
// ============================================================================

EffectInstance::EffectInstance(std::unique_ptr<Effect> effect, const EffectSettings& settings)
    : m_effect(std::move(effect))
    , m_settings(settings)
{
}

void EffectInstance::render(RenderContext& ctx, const RenderState& state) {
    if (!m_effect) return;

    if (!m_prepared) {
        prepareForRender();
    }

    m_effect->render(ctx, m_settings, state);
}

void EffectInstance::prepareForRender() {
    if (!m_effect || m_prepared) return;

    m_effect->prepareForRender(m_settings);
    m_prepared = true;
}

void EffectInstance::cleanupAfterRender() {
    if (!m_effect || !m_prepared) return;

    m_effect->cleanupAfterRender();
    m_prepared = false;
}

bool EffectInstance::supportsRenderCache() const {
    return m_effect ? m_effect->supportsRenderCache(m_settings) : false;
}

// ============================================================================
// EffectPool Implementation
// ============================================================================

EffectInstance* EffectPool::getInstance(const std::string& effectName, const EffectSettings& settings) {
    auto it = m_instances.find(effectName);
    if (it != m_instances.end()) {
        // Update settings and return existing instance
        it->second->setSettings(settings);
        return it->second.get();
    }

    // Create new instance
    auto effect = EffectRegistry::instance().createEffect(effectName);
    if (!effect) {
        return nullptr;
    }

    auto instance = std::make_unique<EffectInstance>(std::move(effect), settings);
    auto* ptr = instance.get();
    m_instances[effectName] = std::move(instance);

    return ptr;
}

void EffectPool::releaseAll() {
    for (auto& [name, instance] : m_instances) {
        if (instance) {
            instance->cleanupAfterRender();
        }
    }
}

void EffectPool::clear() {
    releaseAll();
    m_instances.clear();
}

// ============================================================================
// EffectManager Implementation
// ============================================================================

EffectManager& EffectManager::instance() {
    static EffectManager manager;
    return manager;
}

void EffectManager::initialize() {
    if (m_initialized) return;

    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_initialized) return;

    // Effects auto-register via XLCORE_REGISTER_EFFECT macro
    // Build the category cache from registered effects
    buildCategoryCache();

    m_initialized = true;
}

void EffectManager::buildCategoryCache() {
    m_categories.clear();

    auto& registry = EffectRegistry::instance();
    auto names = registry.effectNames();

    for (const auto& name : names) {
        const Effect* effect = registry.getEffect(name);
        if (!effect) continue;

        std::string category = effect->category();
        auto& catInfo = m_categories[category];
        catInfo.name = category;
        catInfo.effects.push_back(name);
    }

    // Sort effects within each category
    for (auto& [catName, catInfo] : m_categories) {
        std::sort(catInfo.effects.begin(), catInfo.effects.end());
    }
}

std::vector<std::string> EffectManager::effectNames() const {
    return EffectRegistry::instance().effectNames();
}

std::optional<EffectInfo> EffectManager::getEffectInfo(const std::string& name) const {
    const Effect* effect = EffectRegistry::instance().getEffect(name);
    if (!effect) {
        return std::nullopt;
    }

    EffectInfo info;
    info.name = effect->name();
    info.description = effect->description();
    info.category = effect->category();
    info.tooltip = effect->tooltip();
    info.canBeRandom = effect->canBeRandom();
    info.supportsRenderCache = effect->supportsRenderCache(EffectSettings());
    info.canRenderOnBackgroundThread = effect->canRenderOnBackgroundThread();
    info.colorCount = effect->colorSupportedCount();
    info.parameters = effect->parameters();

    return info;
}

bool EffectManager::hasEffect(const std::string& name) const {
    return EffectRegistry::instance().hasEffect(name);
}

std::vector<EffectParameter> EffectManager::getParameters(const std::string& name) const {
    const Effect* effect = EffectRegistry::instance().getEffect(name);
    if (!effect) {
        return {};
    }
    return effect->parameters();
}

EffectSettings EffectManager::getDefaultSettings(const std::string& name) const {
    const Effect* effect = EffectRegistry::instance().getEffect(name);
    if (!effect) {
        return {};
    }
    return effect->defaultSettings();
}

std::vector<std::string> EffectManager::categories() const {
    std::lock_guard<std::mutex> lock(m_mutex);

    std::vector<std::string> result;
    result.reserve(m_categories.size());

    for (const auto& [name, info] : m_categories) {
        result.push_back(name);
    }

    std::sort(result.begin(), result.end());
    return result;
}

std::optional<CategoryInfo> EffectManager::getCategoryInfo(const std::string& category) const {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto it = m_categories.find(category);
    if (it == m_categories.end()) {
        return std::nullopt;
    }
    return it->second;
}

std::vector<std::string> EffectManager::effectsInCategory(const std::string& category) const {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto it = m_categories.find(category);
    if (it == m_categories.end()) {
        return {};
    }
    return it->second.effects;
}

std::unique_ptr<Effect> EffectManager::createEffect(const std::string& name) const {
    return EffectRegistry::instance().createEffect(name);
}

std::unique_ptr<EffectInstance> EffectManager::createInstance(
    const std::string& name,
    const EffectSettings& settings) const {

    auto effect = createEffect(name);
    if (!effect) {
        return nullptr;
    }

    // Apply defaults for any missing settings
    EffectSettings fullSettings = applyDefaults(name, settings);

    return std::make_unique<EffectInstance>(std::move(effect), fullSettings);
}

EffectPool& EffectManager::getThreadPool() {
    if (!s_threadPool) {
        s_threadPool = std::make_unique<EffectPool>();
    }
    return *s_threadPool;
}

void EffectManager::clearAllPools() {
    // Note: This only clears the current thread's pool.
    // In a full implementation, we'd need a way to signal all threads
    // to clear their pools (e.g., atomic flag checked in getThreadPool).
    if (s_threadPool) {
        s_threadPool->clear();
    }
}

std::string EffectManager::validateSettings(
    const std::string& effectName,
    const EffectSettings& settings) const {

    const Effect* effect = EffectRegistry::instance().getEffect(effectName);
    if (!effect) {
        return "Unknown effect: " + effectName;
    }

    auto params = effect->parameters();
    for (const auto& param : params) {
        if (!settings.contains(param.key)) {
            // Missing setting - this is OK, we'll use defaults
            continue;
        }

        std::string value = settings.get(param.key);

        // Type-specific validation
        switch (param.type) {
            case ParameterType::Int:
            case ParameterType::Double:
                if (param.minValue.has_value() && param.maxValue.has_value()) {
                    try {
                        double numVal = std::stod(value);
                        if (numVal < *param.minValue || numVal > *param.maxValue) {
                            return "Parameter '" + param.displayName + "' out of range [" +
                                   std::to_string(*param.minValue) + ", " +
                                   std::to_string(*param.maxValue) + "]";
                        }
                    } catch (...) {
                        return "Parameter '" + param.displayName + "' is not a valid number";
                    }
                }
                break;

            case ParameterType::Choice:
                if (!param.choices.empty()) {
                    auto it = std::find(param.choices.begin(), param.choices.end(), value);
                    if (it == param.choices.end()) {
                        return "Parameter '" + param.displayName + "' has invalid choice: " + value;
                    }
                }
                break;

            default:
                break;
        }
    }

    return ""; // Valid
}

EffectSettings EffectManager::applyDefaults(
    const std::string& effectName,
    const EffectSettings& settings) const {

    const Effect* effect = EffectRegistry::instance().getEffect(effectName);
    if (!effect) {
        return settings;
    }

    // Start with the defaults
    EffectSettings result = effect->defaultSettings();

    // Overlay provided settings
    result.merge(settings, true);

    return result;
}

std::vector<std::string> EffectManager::randomizableEffects() const {
    std::vector<std::string> result;

    auto names = effectNames();
    for (const auto& name : names) {
        const Effect* effect = EffectRegistry::instance().getEffect(name);
        if (effect && effect->canBeRandom()) {
            result.push_back(name);
        }
    }

    return result;
}

std::string EffectManager::selectRandomEffect(const std::string& category) const {
    std::vector<std::string> candidates;

    if (category.empty()) {
        candidates = randomizableEffects();
    } else {
        auto categoryEffects = effectsInCategory(category);
        for (const auto& name : categoryEffects) {
            const Effect* effect = EffectRegistry::instance().getEffect(name);
            if (effect && effect->canBeRandom()) {
                candidates.push_back(name);
            }
        }
    }

    if (candidates.empty()) {
        return "";
    }

    // Use a random device and mersenne twister for good randomness
    static thread_local std::mt19937 gen(
        static_cast<unsigned>(std::chrono::steady_clock::now().time_since_epoch().count()));

    std::uniform_int_distribution<size_t> dist(0, candidates.size() - 1);
    return candidates[dist(gen)];
}

} // namespace xlCore
