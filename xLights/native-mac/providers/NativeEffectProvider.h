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

// NativeEffectProvider: Standalone implementation of IEffectProvider for native macOS.
//
// This provider manages sequence elements and effects natively without wxWidgets
// dependencies. It can load effect data from sequence XML and provides all
// effect CRUD operations needed by the native UI.
//
// Part of the native macOS decoupling effort (Phase 3: Create Native Provider
// Implementations). See DECOUPLING_GUIDE.md for architectural context.
//
// Key Features:
// - Parses effect data from sequence XML files
// - Maintains element/layer/effect hierarchy in native data structures
// - Provides thread-safe read operations
// - Supports undo/redo for modifications
// - No wxWidgets dependencies
//
// Usage:
// - Create NativeEffectProvider
// - Call loadFromSequenceXML() to parse sequence data
// - Use IEffectProvider methods for all effect operations
// - Changes can be saved back with saveToSequenceXML()

#include "../../engine/interfaces/IEffectProvider.h"
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace xlEngine {

// Forward declarations for internal types
struct NativeEffect;
struct NativeEffectLayer;
struct NativeElement;
struct UndoAction;

/// NativeEffectProvider: Standalone IEffectProvider implementation for native macOS.
///
/// This class provides a complete implementation of the IEffectProvider interface
/// using native C++ data structures. It can work without any wxWidgets code being
/// initialized, making it suitable for standalone native macOS operation.
///
/// Thread Safety:
/// - All read operations are thread-safe and can be called from any thread
/// - Write operations (create/delete/update) should be called from the main thread
/// - Internal mutex protects the data structures
class NativeEffectProvider : public IEffectProvider {
public:
    /// Available effect types (populated during initialization or from effect definitions)
    struct EffectTypeInfo {
        std::string name;
        int index;
    };

    NativeEffectProvider();
    ~NativeEffectProvider() override;

    // Non-copyable
    NativeEffectProvider(const NativeEffectProvider&) = delete;
    NativeEffectProvider& operator=(const NativeEffectProvider&) = delete;

    // --- Initialization and Serialization ---

    /// Load effect data from an xLights sequence XML string.
    /// @param xmlContent The XML content of the sequence file
    /// @return true if loading succeeded, false otherwise
    bool loadFromSequenceXML(const std::string& xmlContent);

    /// Load effect data from an xLights sequence XML file.
    /// @param filePath Path to the sequence file
    /// @return true if loading succeeded, false otherwise
    bool loadFromSequenceFile(const std::string& filePath);

    /// Sequence metadata for saving to XML (written into <head> section).
    struct SequenceMetadata {
        double durationSeconds;
        int frameMS;
        std::string sequenceType;  // "Animation" or "Media"
        std::string mediaFile;     // relative or absolute path to audio/media
        std::string author;
        SequenceMetadata() : durationSeconds(0.0), frameMS(50) {}
    };

    /// Export effect data to xLights sequence XML format.
    /// @param metadata Sequence metadata to include in the <head> section
    /// @return XML string representation of the sequence data
    std::string exportToSequenceXML(const SequenceMetadata& metadata) const;

    /// Export without metadata (uses internal sequence length only).
    std::string exportToSequenceXML() const;

    /// Save effect data to an xLights sequence XML file.
    /// @param filePath Path to save the sequence file
    /// @param metadata Sequence metadata to include in the <head> section
    /// @return true if saving succeeded, false otherwise
    bool saveToSequenceFile(const std::string& filePath, const SequenceMetadata& metadata) const;

    /// Save without metadata (uses internal sequence length only).
    bool saveToSequenceFile(const std::string& filePath) const;

    /// Clear all effect data.
    void clear();

    /// Set the available effect types.
    /// @param types List of effect type names
    void setEffectTypes(const std::vector<std::string>& types);

    /// Check if sequence data is loaded.
    /// @return true if data is loaded
    bool isLoaded() const;

    /// Get the sequence length in milliseconds.
    /// @return Sequence length, or 0 if no sequence loaded
    int getSequenceLengthMS() const;

    /// Set the sequence length in milliseconds.
    /// @param lengthMS Sequence length
    void setSequenceLengthMS(int lengthMS);

    // --- IEffectProvider Implementation: Element Access ---

    size_t getElementCount() const override;
    bool getElement(size_t index, ElementInfo& outInfo) const override;
    bool getElementByName(const std::string& name, ElementInfo& outInfo) const override;
    size_t getElementIndex(const std::string& name) const override;

    // --- IEffectProvider Implementation: Effect Layer Access ---

    size_t getEffectLayerCount(size_t elementIndex) const override;
    size_t getEffectCount(size_t elementIndex, size_t layerIndex) const override;
    size_t getTotalEffectCount(size_t elementIndex) const override;

    // --- IEffectProvider Implementation: Effect Queries ---

    std::vector<EffectInstanceInfo> getEffectsInRange(
        size_t elementIndex,
        size_t layerIndex,
        int startTimeMS,
        int endTimeMS) const override;

    std::vector<EffectInstanceInfo> getEffectsOnLayer(
        size_t elementIndex,
        size_t layerIndex) const override;

    std::vector<EffectInstanceInfo> getAllEffects(size_t elementIndex) const override;

    bool getEffect(int64_t effectId, EffectInstanceInfo& outInfo) const override;

    bool getEffectAtTime(
        size_t elementIndex,
        size_t layerIndex,
        int timeMS,
        EffectInstanceInfo& outInfo) const override;

    // --- IEffectProvider Implementation: Effect Type Information ---

    std::vector<std::string> getEffectTypes() const override;
    size_t getEffectTypeCount() const override;
    std::string getEffectTypeName(size_t typeIndex) const override;

    // --- IEffectProvider Implementation: Effect Settings Access ---

    std::map<std::string, std::string> getEffectSettings(int64_t effectId) const override;
    std::string getEffectSetting(
        int64_t effectId,
        const std::string& key,
        const std::string& defaultValue = "") const override;
    std::map<std::string, std::string> getEffectPalette(int64_t effectId) const override;

    // --- IEffectProvider Implementation: Effect Modification - Create ---

    EffectOperationResult createEffect(
        size_t elementIndex,
        size_t layerIndex,
        const std::string& effectType,
        int startTimeMS,
        int endTimeMS) override;

    EffectOperationResult createEffectWithSettings(
        size_t elementIndex,
        size_t layerIndex,
        const std::string& effectType,
        int startTimeMS,
        int endTimeMS,
        const std::map<std::string, std::string>& settings,
        const std::map<std::string, std::string>& palette) override;

    // --- IEffectProvider Implementation: Effect Modification - Delete ---

    EffectOperationResult deleteEffect(int64_t effectId) override;
    EffectOperationResult deleteEffects(const std::vector<int64_t>& effectIds) override;

    // --- IEffectProvider Implementation: Effect Property Modification ---

    EffectOperationResult setEffectLocked(int64_t effectId, bool locked) override;
    EffectOperationResult setEffectRenderDisabled(int64_t effectId, bool disabled) override;
    EffectOperationResult resetEffectToDefaults(int64_t effectId) override;

    // --- IEffectProvider Implementation: Effect Modification - Update ---

    EffectOperationResult updateEffectTiming(
        int64_t effectId,
        int newStartTimeMS,
        int newEndTimeMS) override;

    EffectOperationResult updateEffectSettings(
        int64_t effectId,
        const std::map<std::string, std::string>& settings) override;

    EffectOperationResult updateEffectSetting(
        int64_t effectId,
        const std::string& key,
        const std::string& value) override;

    EffectOperationResult updateEffectPalette(
        int64_t effectId,
        const std::map<std::string, std::string>& palette) override;

    EffectOperationResult updateEffectType(
        int64_t effectId,
        const std::string& newEffectType) override;

    EffectOperationResult moveEffectToLayer(
        int64_t effectId,
        size_t newLayerIndex) override;

    // --- IEffectProvider Implementation: Layer Management ---

    size_t addEffectLayer(size_t elementIndex) override;
    EffectOperationResult removeEffectLayer(size_t elementIndex, size_t layerIndex) override;
    size_t insertEffectLayer(size_t elementIndex, size_t atIndex) override;

    // --- IEffectProvider Implementation: Selection Management ---

    bool selectEffect(int64_t effectId, bool addToSelection = false) override;
    bool deselectEffect(int64_t effectId) override;
    void deselectAllEffects() override;
    std::vector<int64_t> getSelectedEffectIds() const override;

    // --- IEffectProvider Implementation: Undo/Redo Integration ---

    void beginUndoGroup(const std::string& description) override;
    void endUndoGroup() override;
    void cancelUndoGroup() override;
    bool canUndo() const override;
    bool canRedo() const override;
    bool undo() override;
    bool redo() override;
    std::string getUndoDescription() const override;
    std::string getRedoDescription() const override;

    // --- IEffectProvider Implementation: Clipboard Operations ---

    bool copySelectedEffects() override;
    bool cutSelectedEffects() override;
    std::vector<int64_t> pasteEffects(
        size_t elementIndex,
        size_t layerIndex,
        int startTimeMS) override;
    bool canPaste() const override;

    // --- Extended Operations for Native Use ---

    /// Add a new element to the sequence.
    /// @param name Element name
    /// @param type Element type
    /// @return Index of the new element, or SIZE_MAX on failure
    size_t addElement(const std::string& name, SequenceElementType type);

    /// Remove an element from the sequence.
    /// @param elementIndex Index of element to remove
    /// @return true if successful
    bool removeElement(size_t elementIndex);

    /// Set a timing track's active state by name.
    /// Deactivates all other timing tracks first, then activates the named one.
    /// @param name Name of the timing track to activate
    /// @return true if the timing track was found and activated
    bool setTimingTrackActive(const std::string& name);

    /// Deactivate all timing tracks.
    void deactivateAllTimingTracks();

    /// Mark the sequence as modified.
    void setModified(bool modified);

    /// Check if the sequence has unsaved modifications.
    /// @return true if modified
    bool isModified() const;

    /// Get the change count for tracking modifications.
    /// @return Number of modifications since last save
    int getChangeCount() const;

private:
    // Internal helpers
    NativeElement* getElementPtr(size_t index) const;
    NativeEffect* findEffectById(int64_t effectId) const;
    NativeEffect* findEffectById(int64_t effectId, size_t& outElementIndex, size_t& outLayerIndex) const;
    EffectInstanceInfo buildEffectInfo(const NativeEffect* effect, size_t elementIndex, size_t layerIndex) const;
    bool isRangeClear(size_t elementIndex, size_t layerIndex, int startTimeMS, int endTimeMS, int64_t excludeEffectId = -1) const;
    int64_t generateEffectId();
    void recordUndoAction(std::unique_ptr<UndoAction> action);
    void clearRedoStack();
    void incrementChangeCount();

    // Data structures
    std::vector<std::unique_ptr<NativeElement>> _elements;
    std::unordered_map<int64_t, NativeEffect*> _effectsById;  // Quick lookup by ID
    std::unordered_map<std::string, size_t> _elementsByName;  // Quick lookup by name
    std::vector<EffectTypeInfo> _effectTypes;
    std::vector<int64_t> _selectedEffects;

    // Clipboard
    struct ClipboardEffect {
        std::string effectType;
        int durationMS;
        std::map<std::string, std::string> settings;
        std::map<std::string, std::string> palette;
        size_t relativeLayerIndex;
        int relativeStartTimeMS;
    };
    std::vector<ClipboardEffect> _clipboard;

    // Undo/Redo
    struct UndoGroup {
        std::string description;
        std::vector<std::unique_ptr<UndoAction>> actions;
    };
    std::deque<std::unique_ptr<UndoGroup>> _undoStack;
    std::deque<std::unique_ptr<UndoGroup>> _redoStack;
    std::unique_ptr<UndoGroup> _currentUndoGroup;
    static constexpr size_t kMaxUndoLevels = 100;

    // State
    int64_t _nextEffectId = 1;
    int _sequenceLengthMS = 0;
    bool _isLoaded = false;
    bool _isModified = false;
    int _changeCount = 0;

    // Thread safety
    mutable std::recursive_mutex _mutex;
};

} // namespace xlEngine
