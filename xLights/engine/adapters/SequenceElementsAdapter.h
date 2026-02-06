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

// SequenceElementsAdapter: Implements IEffectProvider by wrapping xLightsFrame.
//
// This adapter allows EffectEngine (and other engines) to use the IEffectProvider
// interface while still having access to the underlying SequenceElements for
// operations during the transition period.
//
// Part of the xlEngine abstraction layer (Phase 2: Update Engines).
// See DECOUPLING_GUIDE.md for architectural context.
//
// Usage:
// - Legacy wxWidgets code has xLightsFrame with SequenceElements
// - Creates SequenceElementsAdapter wrapping the xLightsFrame
// - Passes adapter to EffectEngine as IEffectProvider*
// - EffectEngine uses interface for all operations

#include "../interfaces/IEffectProvider.h"
#include <string>
#include <memory>

class xLightsFrame;
class SequenceElements;
class EffectManager;
class Effect;
class Element;

namespace xlEngine {

/// Adapter that wraps xLightsFrame/SequenceElements to implement IEffectProvider.
///
/// This class provides backward compatibility during the transition from
/// direct xLightsFrame usage to interface-based design. It implements the
/// IEffectProvider interface by delegating to the existing SequenceElements
/// and EffectManager classes.
///
/// Thread Safety:
/// All methods delegate to SequenceElements/EffectManager which have their
/// own synchronization mechanisms.
class SequenceElementsAdapter : public IEffectProvider {
public:
    /// Constructs an adapter wrapping the given xLightsFrame.
    /// @param frame Pointer to the xLightsFrame to wrap. The frame must
    ///              outlive this adapter.
    explicit SequenceElementsAdapter(xLightsFrame* frame);

    ~SequenceElementsAdapter() override = default;

    // Non-copyable
    SequenceElementsAdapter(const SequenceElementsAdapter&) = delete;
    SequenceElementsAdapter& operator=(const SequenceElementsAdapter&) = delete;

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

    // --- Extended Operations for EffectEngine ---
    //
    // These methods are not part of IEffectProvider but are needed by EffectEngine
    // for access to internal objects during the transition period.

    /// Provides direct access to the underlying xLightsFrame.
    /// @note This is provided for legacy code that still needs direct access.
    ///       New code should use interface methods instead.
    xLightsFrame* getFrame() { return _frame; }
    const xLightsFrame* getFrame() const { return _frame; }

    /// Provides direct access to SequenceElements.
    SequenceElements* getSequenceElements() const;

    /// Provides direct access to EffectManager.
    EffectManager* getEffectManager() const;

private:
    // Helper to build EffectInstanceInfo from an Effect pointer
    EffectInstanceInfo buildEffectInfo(::Effect* effect, size_t elementIndex, size_t layerIndex) const;

    // Helper to find an effect by ID
    ::Effect* findEffectById(int64_t effectId, size_t& outElementIndex, size_t& outLayerIndex) const;

    // Helper to get Element by index
    ::Element* getElementByIndex(size_t index) const;

    xLightsFrame* _frame;
};

} // namespace xlEngine
