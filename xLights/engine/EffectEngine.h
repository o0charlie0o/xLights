#pragma once

/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// EffectEngine: Pure C++ API for effect management, decoupled from wxWidgets.
// Part of the xlEngine abstraction layer (Phase 2: Update Engines).
//
// This API uses IEffectProvider interface to access effect data, allowing it
// to work with both the legacy wxWidgets UI (via SequenceElementsAdapter) and
// future native AppKit UI (via NativeEffectProvider).
//
// All data exchange uses std::string, std::vector, std::map, and plain structs.
// No wxWidgets types are exposed in the public API.
//
// See DECOUPLING_GUIDE.md for architectural context.

#include <string>
#include <vector>
#include <map>
#include <functional>
#include <mutex>
#include <memory>

#include "interfaces/IEffectProvider.h"

class xLightsFrame;
class EffectManager;
class SequenceElements;
class Effect;

namespace xlEngine {

// Parameter type enumeration for UI generation
enum class ParameterType {
    Int,
    Float,
    Bool,
    String,
    Color,
    Choice,
    File,
    ValueCurve,
    Font,
    ColorCurve
};

// A single parameter definition with enough metadata
// for a UI layer to auto-generate controls.
struct ParameterDefinition {
    std::string key;          // SettingsMap key (e.g. "E_SLIDER_Bars_BarCount")
    std::string displayLabel; // Human-readable label (e.g. "Palette Rep")
    ParameterType type = ParameterType::Int;
    std::string group;        // Group name for panel sections (e.g. "Basic", "Options")

    // Numeric range (for Int and Float types)
    double minValue = 0.0;
    double maxValue = 100.0;
    double defaultValue = 0.0;
    int divisor = 1;          // For scaled float values (slider value / divisor = actual value)

    // Choice list (for Choice type)
    std::vector<std::string> choices;
    int defaultChoiceIndex = 0;

    // Default string value (for String, Color, File, Font types)
    std::string defaultString;

    // Whether this parameter supports value curves
    bool supportsValueCurve = false;

    // The value curve key, if applicable (e.g. "E_VALUECURVE_Bars_BarCount")
    std::string valueCurveKey;

    // File filter (for File type, e.g. "Image files|*.png;*.jpg")
    std::string fileFilter;

    // Whether this parameter can be locked by the user
    bool lockable = true;

    // Sort order within group (lower = earlier)
    int sortOrder = 0;
};

// Metadata describing an effect type
struct EffectTypeInfo {
    int id = -1;                  // Internal effect index
    std::string name;             // Effect name (e.g. "Bars", "Fire")
    std::string tooltip;          // Tooltip/description
    bool canBeRandom = true;      // Whether this effect can be used in random generation
    bool canRenderPartialTime = false;
    bool supportsLinearColorCurves = false;
    bool supportsRadialColorCurves = false;
    int maxColorCount = -1;       // -1 = unlimited
    bool appropriateOnNodes = true;
};

// Snapshot of an effect instance's properties
struct EffectInfo {
    int id = 0;                     // Effect instance ID
    std::string effectType;         // Effect type name (e.g. "Bars")
    int effectIndex = -1;           // Effect type index
    std::string modelName;          // Owning model/element name
    int layerIndex = -1;            // Layer index within element
    int startTimeMS = 0;
    int endTimeMS = 0;
    bool isSelected = false;
    bool isProtected = false;
    bool isLocked = false;
    bool isRenderDisabled = false;

    // Current settings as key-value pairs
    std::map<std::string, std::string> settings;
    // Current palette as key-value pairs
    std::map<std::string, std::string> palette;
};

// Event types for effect change notifications
enum class EffectEventType {
    EffectCreated,
    EffectDeleted,
    EffectMoved,
    EffectSettingChanged,
    EffectPaletteChanged,
    EffectSelected,
    EffectDeselected,
    EffectTypeChanged
};

struct EffectEvent {
    EffectEventType type;
    int effectId = 0;
    std::string modelName;
    int layerIndex = -1;
    std::string paramKey;     // For SettingChanged events
    std::string paramValue;   // For SettingChanged events
};

// Callback interface for effect engine events.
// All callbacks are invoked on the thread that triggers them.
// Implementers must handle thread safety in their callback bodies.
class EffectEngineListener {
public:
    virtual ~EffectEngineListener() = default;

    virtual void onEffectCreated(const EffectEvent& event) {}
    virtual void onEffectDeleted(const EffectEvent& event) {}
    virtual void onEffectMoved(const EffectEvent& event) {}
    virtual void onEffectSettingChanged(const EffectEvent& event) {}
    virtual void onEffectPaletteChanged(const EffectEvent& event) {}
    virtual void onEffectSelected(const EffectEvent& event) {}
    virtual void onEffectTypeChanged(const EffectEvent& event) {}
    virtual void onError(const std::string& message) {}
};

// Forward declaration for extended operations adapter
class SequenceElementsAdapter;

// EffectEngine provides a pure C++ API for effect management.
//
// Thread safety: All public methods are safe to call from any thread.
// The engine uses internal locking where necessary. Callbacks may be
// invoked from any thread; callers must dispatch to their own UI
// thread if needed.
//
// This class uses IEffectProvider for effect access, allowing it to work
// with different backend implementations:
// - SequenceElementsAdapter: Wraps legacy xLightsFrame for wxWidgets UI
// - NativeEffectProvider: Native macOS implementation (future)
class EffectEngine {
public:
    /// Constructs an EffectEngine using the given effect provider.
    /// @param provider Pointer to the effect provider. The provider must
    ///                 outlive this engine. The engine does NOT take ownership.
    explicit EffectEngine(IEffectProvider* provider);

#ifndef XLIGHTS_NATIVE
    /// Legacy constructor for backward compatibility during transition.
    /// Creates an internal SequenceElementsAdapter to wrap xLightsFrame.
    /// @deprecated Use the IEffectProvider* constructor instead.
    explicit EffectEngine(xLightsFrame* frame);
#endif

    ~EffectEngine();

    EffectEngine(const EffectEngine&) = delete;
    EffectEngine& operator=(const EffectEngine&) = delete;

    // --- Listener management ---
    void addListener(EffectEngineListener* listener);
    void removeListener(EffectEngineListener* listener);

    // --- Effect type enumeration ---

    // Get metadata for all available effect types.
    std::vector<EffectTypeInfo> getEffectTypes() const;

    // Get metadata for a single effect type by name.
    // Returns false if the effect type is not found.
    bool getEffectTypeInfo(const std::string& effectType, EffectTypeInfo& outInfo) const;

    // Get parameter definitions for an effect type.
    // These provide enough metadata for a UI to auto-generate controls.
    std::vector<ParameterDefinition> getEffectParameters(const std::string& effectType) const;

    // --- Effect CRUD ---

    // Create a new effect on the specified model, layer, and time range.
    // Returns the effect ID, or -1 on failure.
    int createEffect(const std::string& modelName, int layer,
                     const std::string& effectType,
                     int startTimeMS, int endTimeMS);

    // Delete an effect by ID. Returns true on success.
    bool deleteEffect(int effectId);

    // Get a snapshot of an effect's current properties.
    // Returns false if the effect is not found.
    bool getEffect(int effectId, EffectInfo& outInfo) const;

    // --- Effect parameter access ---

    // Set a single effect parameter. Returns true on success.
    bool setEffectParameter(int effectId, const std::string& key, const std::string& value);

    // Get a single effect parameter value. Returns empty string if not found.
    std::string getEffectParameter(int effectId, const std::string& key) const;

    // Set the full settings string for an effect. Returns true on success.
    bool setEffectSettings(int effectId, const std::string& settings);

    // Get the full settings string for an effect.
    std::string getEffectSettings(int effectId) const;

    // --- Effect palette (color) access ---

    // Set the palette string for an effect. Returns true on success.
    bool setEffectPalette(int effectId, const std::string& palette);

    // Get the palette string for an effect.
    std::string getEffectPalette(int effectId) const;

    // --- Effect positioning ---

    // Move an effect to a new time range. Returns true on success.
    bool moveEffect(int effectId, int newStartTimeMS, int newEndTimeMS);

    // --- Effect queries ---

    // Get all effects on a given model (across all layers).
    std::vector<EffectInfo> getEffectsForModel(const std::string& modelName) const;

    // Get all effects active at a given time on a model.
    std::vector<EffectInfo> getEffectsAtTime(const std::string& modelName, int timeMS) const;

    // Get all effects on a specific layer of a model.
    std::vector<EffectInfo> getEffectsForLayer(const std::string& modelName, int layer) const;

    // Get the number of layers on a model element.
    int getLayerCount(const std::string& modelName) const;

    // --- Layer management ---

    // Add a new effect layer to a model element. Returns the new layer index.
    int addLayer(const std::string& modelName);

    // Insert a new effect layer at a specific index. Returns the new layer index.
    int insertLayer(const std::string& modelName, int atIndex);

    // Remove a layer from a model element. Returns true on success.
    bool removeLayer(const std::string& modelName, int layer);

    // --- Selection ---

    // Select an effect. Returns true on success.
    bool selectEffect(int effectId);

    // Deselect all effects.
    void deselectAllEffects();

    // Get IDs of all currently selected effects.
    std::vector<int> getSelectedEffectIds() const;

    // --- Effect type conversion ---

    // Convert an effect to a different type. Returns true on success.
    bool convertEffectType(int effectId, const std::string& newEffectType);

private:
    // Internal helpers
    EffectManager* getEffectManager() const;
    SequenceElements* getSequenceElements() const;

    EffectInfo buildEffectInfo(::Effect* effect, const std::string& modelName, int layerIndex) const;
    std::vector<ParameterDefinition> buildDefaultParameters(const std::string& effectType) const;

    // Find an effect by ID across all elements/layers.
    // Returns the Effect pointer and populates modelName/layerIndex if found.
    ::Effect* findEffectById(int effectId, std::string& modelName, int& layerIndex) const;

    // Returns the adapter for extended operations (internal access).
    // Returns nullptr if provider is not a SequenceElementsAdapter.
    SequenceElementsAdapter* getAdapter() const;

    // Notification helpers
    void notifyEffectCreated(int effectId, const std::string& modelName, int layerIndex);
    void notifyEffectDeleted(int effectId, const std::string& modelName, int layerIndex);
    void notifyEffectMoved(int effectId, const std::string& modelName, int layerIndex);
    void notifyEffectSettingChanged(int effectId, const std::string& key, const std::string& value);
    void notifyEffectPaletteChanged(int effectId, const std::string& modelName, int layerIndex);
    void notifyError(const std::string& message);

    IEffectProvider* _provider;

#ifndef XLIGHTS_NATIVE
    // Owned adapter when using the legacy xLightsFrame* constructor.
    // null when using the IEffectProvider* constructor directly.
    std::unique_ptr<SequenceElementsAdapter> _ownedAdapter;
#endif

    std::vector<EffectEngineListener*> _listeners;
    mutable std::mutex _listenerMutex;
    mutable std::mutex _engineMutex;
};

} // namespace xlEngine
