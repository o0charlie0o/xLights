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

// IEffectProvider: Pure C++ interface for effect data access.
// Part of the engine abstraction layer for decoupling from wxWidgets.
//
// This interface allows the native macOS UI (or any other frontend)
// to access effect data without depending on xLightsFrame or wxWidgets.
// All types are standard C++ - no wx types cross this boundary.
//
// Thread safety: Implementations must be thread-safe for read operations.
// Write operations (create/delete/update) may require main thread execution
// depending on the implementation.

#include <cstddef>
#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace xlEngine {

// Element type enumeration matching the existing ElementType enum
// but using std:: naming conventions for the interface layer.
enum class SequenceElementType {
    Model,
    Submodel,
    Strand,
    Timing
};

// Information about a sequence element (model, timing track, etc.)
struct ElementInfo {
    size_t index = 0;                    // Index in the element list
    std::string name;                    // Element name
    std::string fullName;                // Full name including parent (for submodels)
    std::string modelName;               // Model name (may differ from name for submodels)
    SequenceElementType type = SequenceElementType::Model;
    bool visible = true;
    bool collapsed = false;
    bool renderDisabled = false;
    size_t effectLayerCount = 0;         // Number of effect layers
    size_t effectCount = 0;              // Total effects across all layers

    // For timing elements
    int fixedTiming = 0;                 // 0 = not fixed, >0 = fixed interval in ms
    bool isActive = true;                // Whether timing track is active

    // For submodels/strands
    std::string parentElementName;       // Parent element name if this is a submodel/strand
    int strandIndex = -1;                // For strand elements: 0-based strand index (-1 = not a strand)
};

// Information about a single effect instance
struct EffectInstanceInfo {
    int64_t effectId = 0;                // Unique effect identifier
    size_t elementIndex = 0;             // Index of owning element
    size_t layerIndex = 0;               // Layer index within element
    std::string effectType;              // Effect type name (e.g., "Bars", "Fire")
    int effectTypeIndex = -1;            // Effect type index for quick lookup
    int startTimeMS = 0;                 // Start time in milliseconds
    int endTimeMS = 0;                   // End time in milliseconds
    bool selected = false;
    bool protected_ = false;             // 'protected' is a C++ keyword
    bool locked = false;
    bool renderDisabled = false;

    // Current settings as key-value pairs (std:: types only)
    std::map<std::string, std::string> settings;

    // Current palette/color settings as key-value pairs
    std::map<std::string, std::string> palette;
};

// Result of an effect modification operation
struct EffectOperationResult {
    bool success = false;
    std::string errorMessage;
    int64_t effectId = -1;               // Set for create operations on success
};

// Undo context for grouping multiple operations
struct UndoContext {
    std::string description;             // Human-readable description for undo menu
    bool isOpen = false;                 // Whether an undo group is currently open
};

// IEffectProvider: Abstract interface for accessing and modifying effect data.
//
// This interface abstracts the effect data layer, allowing the native UI
// to work with effects without direct access to SequenceElements or xLightsFrame.
//
// Implementations should:
// - Use only std:: types in the interface (no wx types)
// - Support thread-safe read operations
// - Integrate with the undo/redo system for modifications
// - Notify listeners of changes (through the EffectEngineListener pattern)
class IEffectProvider {
public:
    virtual ~IEffectProvider() = default;

    // =========================================================================
    // Element Access
    // =========================================================================

    // Get the total number of elements in the sequence
    virtual size_t getElementCount() const = 0;

    // Get information about an element by index
    // Returns false if index is out of range
    virtual bool getElement(size_t index, ElementInfo& outInfo) const = 0;

    // Get element information by name
    // Returns false if element not found
    virtual bool getElementByName(const std::string& name, ElementInfo& outInfo) const = 0;

    // Get the index of an element by name
    // Returns SIZE_MAX if not found
    virtual size_t getElementIndex(const std::string& name) const = 0;

    // =========================================================================
    // Effect Layer Access
    // =========================================================================

    // Get the number of effect layers for an element
    virtual size_t getEffectLayerCount(size_t elementIndex) const = 0;

    // Get the number of effects on a specific layer
    virtual size_t getEffectCount(size_t elementIndex, size_t layerIndex) const = 0;

    // Get total effect count across all layers for an element
    virtual size_t getTotalEffectCount(size_t elementIndex) const = 0;

    // =========================================================================
    // Effect Queries
    // =========================================================================

    // Get effects within a time range on a specific layer
    virtual std::vector<EffectInstanceInfo> getEffectsInRange(
        size_t elementIndex,
        size_t layerIndex,
        int startTimeMS,
        int endTimeMS) const = 0;

    // Get all effects on a specific layer
    virtual std::vector<EffectInstanceInfo> getEffectsOnLayer(
        size_t elementIndex,
        size_t layerIndex) const = 0;

    // Get all effects for an element across all layers
    virtual std::vector<EffectInstanceInfo> getAllEffects(size_t elementIndex) const = 0;

    // Get effect by ID
    // Returns false if effect not found
    virtual bool getEffect(int64_t effectId, EffectInstanceInfo& outInfo) const = 0;

    // Get effect at a specific time on a layer
    // Returns false if no effect at that time
    virtual bool getEffectAtTime(
        size_t elementIndex,
        size_t layerIndex,
        int timeMS,
        EffectInstanceInfo& outInfo) const = 0;

    // =========================================================================
    // Effect Type Information
    // =========================================================================

    // Get list of all available effect type names
    virtual std::vector<std::string> getEffectTypes() const = 0;

    // Get the number of available effect types
    virtual size_t getEffectTypeCount() const = 0;

    // Get effect type name by index
    virtual std::string getEffectTypeName(size_t typeIndex) const = 0;

    // =========================================================================
    // Effect Settings Access
    // =========================================================================

    // Get the current settings for an effect
    virtual std::map<std::string, std::string> getEffectSettings(int64_t effectId) const = 0;

    // Get a single setting value
    virtual std::string getEffectSetting(
        int64_t effectId,
        const std::string& key,
        const std::string& defaultValue = "") const = 0;

    // Get the palette/color settings for an effect
    virtual std::map<std::string, std::string> getEffectPalette(int64_t effectId) const = 0;

    // =========================================================================
    // Effect Modification - Create
    // =========================================================================

    // Create a new effect on the specified element, layer, and time range
    // Returns the effect ID on success, or a result with success=false on failure
    virtual EffectOperationResult createEffect(
        size_t elementIndex,
        size_t layerIndex,
        const std::string& effectType,
        int startTimeMS,
        int endTimeMS) = 0;

    // Create an effect with initial settings
    virtual EffectOperationResult createEffectWithSettings(
        size_t elementIndex,
        size_t layerIndex,
        const std::string& effectType,
        int startTimeMS,
        int endTimeMS,
        const std::map<std::string, std::string>& settings,
        const std::map<std::string, std::string>& palette) = 0;

    // =========================================================================
    // Effect Modification - Delete
    // =========================================================================

    // Delete an effect by ID
    virtual EffectOperationResult deleteEffect(int64_t effectId) = 0;

    // Delete multiple effects
    virtual EffectOperationResult deleteEffects(const std::vector<int64_t>& effectIds) = 0;

    // =========================================================================
    // Effect Property Modification
    // =========================================================================

    // Set whether an effect is locked (prevents editing)
    virtual EffectOperationResult setEffectLocked(int64_t effectId, bool locked) = 0;

    // Set whether an effect's rendering is disabled
    virtual EffectOperationResult setEffectRenderDisabled(int64_t effectId, bool disabled) = 0;

    // Reset an effect to its default settings (clears all settings and palette)
    virtual EffectOperationResult resetEffectToDefaults(int64_t effectId) = 0;

    // =========================================================================
    // Effect Modification - Update
    // =========================================================================

    // Update effect timing (move/resize)
    virtual EffectOperationResult updateEffectTiming(
        int64_t effectId,
        int newStartTimeMS,
        int newEndTimeMS) = 0;

    // Update all effect settings
    virtual EffectOperationResult updateEffectSettings(
        int64_t effectId,
        const std::map<std::string, std::string>& settings) = 0;

    // Update a single effect setting
    virtual EffectOperationResult updateEffectSetting(
        int64_t effectId,
        const std::string& key,
        const std::string& value) = 0;

    // Update effect palette/colors
    virtual EffectOperationResult updateEffectPalette(
        int64_t effectId,
        const std::map<std::string, std::string>& palette) = 0;

    // Change the effect type (convert effect)
    virtual EffectOperationResult updateEffectType(
        int64_t effectId,
        const std::string& newEffectType) = 0;

    // Move effect to a different layer
    virtual EffectOperationResult moveEffectToLayer(
        int64_t effectId,
        size_t newLayerIndex) = 0;

    // =========================================================================
    // Layer Management
    // =========================================================================

    // Add a new effect layer to an element
    // Returns the index of the new layer
    virtual size_t addEffectLayer(size_t elementIndex) = 0;

    // Remove an effect layer from an element
    virtual EffectOperationResult removeEffectLayer(size_t elementIndex, size_t layerIndex) = 0;

    // Insert an effect layer at a specific position
    virtual size_t insertEffectLayer(size_t elementIndex, size_t atIndex) = 0;

    // =========================================================================
    // Selection Management
    // =========================================================================

    // Select an effect
    virtual bool selectEffect(int64_t effectId, bool addToSelection = false) = 0;

    // Deselect an effect
    virtual bool deselectEffect(int64_t effectId) = 0;

    // Deselect all effects
    virtual void deselectAllEffects() = 0;

    // Get all currently selected effect IDs
    virtual std::vector<int64_t> getSelectedEffectIds() const = 0;

    // =========================================================================
    // Undo/Redo Integration
    // =========================================================================

    // Begin an undo group - all modifications until endUndoGroup are
    // grouped into a single undoable operation
    virtual void beginUndoGroup(const std::string& description) = 0;

    // End the current undo group
    virtual void endUndoGroup() = 0;

    // Cancel the current undo group (discard all modifications in the group)
    virtual void cancelUndoGroup() = 0;

    // Check if we can undo
    virtual bool canUndo() const = 0;

    // Check if we can redo
    virtual bool canRedo() const = 0;

    // Perform undo
    virtual bool undo() = 0;

    // Perform redo
    virtual bool redo() = 0;

    // Get description of the next undo operation
    virtual std::string getUndoDescription() const = 0;

    // Get description of the next redo operation
    virtual std::string getRedoDescription() const = 0;

    // =========================================================================
    // Clipboard Operations
    // =========================================================================

    // Copy selected effects to internal clipboard
    virtual bool copySelectedEffects() = 0;

    // Cut selected effects to internal clipboard
    virtual bool cutSelectedEffects() = 0;

    // Paste effects from internal clipboard
    // Returns IDs of pasted effects
    virtual std::vector<int64_t> pasteEffects(
        size_t elementIndex,
        size_t layerIndex,
        int startTimeMS) = 0;

    // Check if clipboard has effects to paste
    virtual bool canPaste() const = 0;
};

} // namespace xlEngine
