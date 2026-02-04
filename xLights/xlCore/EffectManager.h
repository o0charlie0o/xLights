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
 * @file EffectManager.h
 * @brief Effect factory, registration, and management for xlCore.
 *
 * The EffectManager provides a high-level interface for:
 * - Instantiating effects by name
 * - Getting effect metadata for UI generation
 * - Managing effect instances for rendering
 * - Thread-safe effect pool for parallel rendering
 *
 * This builds on top of EffectRegistry to provide additional
 * functionality needed by the render pipeline.
 */

#include <string>
#include <vector>
#include <unordered_map>
#include <memory>
#include <mutex>
#include <functional>
#include <optional>

#include "Effect.h"
#include "Sequence.h"

namespace xlCore {

// Forward declarations
class RenderContext;

/**
 * @brief Effect metadata for UI display.
 *
 * Contains all information needed to display an effect in the
 * effect palette and generate its control panel.
 */
struct EffectInfo {
    std::string name;           ///< Effect identifier (e.g., "Bars")
    std::string description;    ///< Human-readable description
    std::string category;       ///< Category for grouping (e.g., "Patterns")
    std::string tooltip;        ///< Tooltip text for UI

    bool canBeRandom = true;    ///< Can be selected randomly
    bool supportsRenderCache = true; ///< Supports caching
    bool canRenderOnBackgroundThread = true; ///< Thread-safe rendering
    int colorCount = -1;        ///< Number of colors supported (-1 = unlimited)

    std::vector<EffectParameter> parameters; ///< Effect parameters
};

/**
 * @brief Category info for effect organization.
 */
struct CategoryInfo {
    std::string name;           ///< Category name
    std::string description;    ///< Category description
    std::vector<std::string> effects; ///< Effect names in this category
};

/**
 * @brief Effect instance for rendering.
 *
 * Wraps an Effect with its current settings and state.
 * Used by the render pipeline for per-layer effect instances.
 */
class EffectInstance {
public:
    EffectInstance(std::unique_ptr<Effect> effect, const EffectSettings& settings);
    ~EffectInstance() = default;

    // Non-copyable but movable
    EffectInstance(const EffectInstance&) = delete;
    EffectInstance& operator=(const EffectInstance&) = delete;
    EffectInstance(EffectInstance&&) = default;
    EffectInstance& operator=(EffectInstance&&) = default;

    /**
     * @brief Get the effect name.
     */
    std::string name() const { return m_effect ? m_effect->name() : ""; }

    /**
     * @brief Get the underlying effect.
     */
    Effect* effect() { return m_effect.get(); }
    const Effect* effect() const { return m_effect.get(); }

    /**
     * @brief Get/set effect settings.
     */
    const EffectSettings& settings() const { return m_settings; }
    void setSettings(const EffectSettings& settings) { m_settings = settings; }

    /**
     * @brief Update a single setting.
     */
    void setSetting(const std::string& key, const std::string& value) {
        m_settings.set(key, value);
    }

    /**
     * @brief Render the effect.
     */
    void render(RenderContext& ctx, const RenderState& state);

    /**
     * @brief Prepare for rendering.
     */
    void prepareForRender();

    /**
     * @brief Cleanup after rendering.
     */
    void cleanupAfterRender();

    /**
     * @brief Check if render cache is supported.
     */
    bool supportsRenderCache() const;

private:
    std::unique_ptr<Effect> m_effect;
    EffectSettings m_settings;
    bool m_prepared = false;
};

/**
 * @brief Thread-local effect pool for parallel rendering.
 *
 * Each rendering thread gets its own pool of effect instances
 * to avoid contention and ensure thread safety.
 */
class EffectPool {
public:
    EffectPool() = default;
    ~EffectPool() = default;

    /**
     * @brief Get or create an effect instance for the given effect name.
     *
     * Returns a cached instance if available, otherwise creates a new one.
     */
    EffectInstance* getInstance(const std::string& effectName, const EffectSettings& settings);

    /**
     * @brief Release all instances back to the pool.
     */
    void releaseAll();

    /**
     * @brief Clear the pool (destroy all instances).
     */
    void clear();

private:
    std::unordered_map<std::string, std::unique_ptr<EffectInstance>> m_instances;
};

/**
 * @brief High-level effect management interface.
 *
 * The EffectManager provides:
 * - Effect lookup and instantiation
 * - Metadata queries for UI
 * - Thread-safe effect pools for rendering
 * - Effect registration initialization
 *
 * Thread safety:
 * - All methods are thread-safe unless otherwise noted.
 * - Effect pools are thread-local and do not require synchronization.
 */
class EffectManager {
public:
    /**
     * @brief Get the singleton instance.
     */
    static EffectManager& instance();

    /**
     * @brief Initialize the effect manager.
     *
     * This triggers auto-registration of all effects. Call this
     * early in application startup.
     */
    void initialize();

    /**
     * @brief Check if manager is initialized.
     */
    bool isInitialized() const { return m_initialized; }

    // ========== Effect Information ==========

    /**
     * @brief Get all registered effect names.
     */
    std::vector<std::string> effectNames() const;

    /**
     * @brief Get effect info by name.
     */
    std::optional<EffectInfo> getEffectInfo(const std::string& name) const;

    /**
     * @brief Check if an effect is registered.
     */
    bool hasEffect(const std::string& name) const;

    /**
     * @brief Get effect parameter definitions.
     */
    std::vector<EffectParameter> getParameters(const std::string& name) const;

    /**
     * @brief Get default settings for an effect.
     */
    EffectSettings getDefaultSettings(const std::string& name) const;

    // ========== Categories ==========

    /**
     * @brief Get all category names.
     */
    std::vector<std::string> categories() const;

    /**
     * @brief Get category info by name.
     */
    std::optional<CategoryInfo> getCategoryInfo(const std::string& category) const;

    /**
     * @brief Get effects in a specific category.
     */
    std::vector<std::string> effectsInCategory(const std::string& category) const;

    // ========== Effect Instantiation ==========

    /**
     * @brief Create a new effect instance.
     *
     * The caller owns the returned pointer.
     */
    std::unique_ptr<Effect> createEffect(const std::string& name) const;

    /**
     * @brief Create an effect instance with settings.
     */
    std::unique_ptr<EffectInstance> createInstance(
        const std::string& name,
        const EffectSettings& settings) const;

    // ========== Thread-Local Pools ==========

    /**
     * @brief Get the thread-local effect pool.
     *
     * Each thread has its own pool for efficient effect reuse.
     */
    EffectPool& getThreadPool();

    /**
     * @brief Clear all thread-local pools.
     *
     * Call this when major state changes occur (e.g., sequence close).
     */
    void clearAllPools();

    // ========== Effect Validation ==========

    /**
     * @brief Validate effect settings.
     *
     * Checks that all required parameters are present and within bounds.
     * Returns empty string if valid, error message otherwise.
     */
    std::string validateSettings(
        const std::string& effectName,
        const EffectSettings& settings) const;

    /**
     * @brief Apply default values for missing parameters.
     */
    EffectSettings applyDefaults(
        const std::string& effectName,
        const EffectSettings& settings) const;

    // ========== Random Effect Selection ==========

    /**
     * @brief Get list of effects that can be randomly selected.
     */
    std::vector<std::string> randomizableEffects() const;

    /**
     * @brief Select a random effect name.
     *
     * Optionally filter by category.
     */
    std::string selectRandomEffect(const std::string& category = "") const;

    // ========== Callbacks ==========

    /**
     * @brief Callback type for effect registration notification.
     */
    using EffectRegisteredCallback = std::function<void(const std::string& name)>;

    /**
     * @brief Set callback for effect registration.
     *
     * Called when new effects are registered (e.g., from plugins).
     */
    void setRegistrationCallback(EffectRegisteredCallback callback) {
        m_registrationCallback = callback;
    }

private:
    EffectManager() = default;
    ~EffectManager() = default;

    // Non-copyable
    EffectManager(const EffectManager&) = delete;
    EffectManager& operator=(const EffectManager&) = delete;

    /**
     * @brief Build category cache from registered effects.
     */
    void buildCategoryCache();

    bool m_initialized = false;
    std::unordered_map<std::string, CategoryInfo> m_categories;
    mutable std::mutex m_mutex;

    EffectRegisteredCallback m_registrationCallback;

    // Thread-local storage for effect pools
    static thread_local std::unique_ptr<EffectPool> s_threadPool;
};

} // namespace xlCore
