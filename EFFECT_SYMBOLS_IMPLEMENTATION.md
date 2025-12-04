# Effect Symbols Implementation Guide

## Overview

This document describes a new feature for xLights: **Effect Symbols** (also known as linked effects, master effects, or component effects). This feature allows users to create reusable effect definitions that can be linked to multiple effect instances throughout a sequence, with changes to the symbol automatically propagating to all linked instances.

## Problem Statement

Currently in xLights, when users want the same effect with identical settings in multiple places:
1. They must copy/paste the effect, creating independent copies
2. If they need to tweak the settings, they must manually update each copy
3. Effect presets help but are "snapshots" - applying a preset creates an independent effect
4. There's no way to maintain a live link between related effects

This is particularly painful for:
- Repeating motifs (e.g., a signature sparkle that appears throughout a song)
- Chorus sections that should stay synchronized
- Consistent effect styling across multiple models
- Large shows where a single design change requires dozens of manual updates

## Proposed Solution

### Concept: Effect Symbols

An **Effect Symbol** is a named, reusable effect definition stored at the sequence level. Effects can be **linked** to a symbol, meaning they automatically inherit all settings from that symbol. When the symbol is modified, all linked effects update automatically.

### Terminology

| Term | Definition |
|------|------------|
| **Symbol** | A master effect definition with a name, effect type, settings, and palette |
| **Linked Effect** | An effect instance that references a symbol and inherits its settings |
| **Unlinked Effect** | A normal effect with independent settings (current behavior) |
| **Symbol Library** | Collection of all symbols defined in a sequence |

## User Workflow

### Creating a Symbol

1. User creates an effect and configures it exactly as desired
2. Right-click the effect → "Create Symbol from Effect..."
3. Dialog prompts for symbol name (e.g., "Chorus Sparkle", "Verse Fire")
4. Symbol is created and added to Symbol Library
5. Original effect becomes linked to the new symbol

### Linking an Existing Effect to a Symbol

1. User has an effect (any type) on the timeline
2. Right-click the effect → "Link to Symbol..."
3. Dropdown shows available symbols (filtered to compatible effect types, or all with type conversion)
4. User selects a symbol
5. Effect converts to the symbol's effect type and inherits all settings
6. Effect is now linked and shows visual indicator

### Alternative: Link via Effects Panel

1. Select an effect on the timeline
2. In the Effect Settings panel, a new dropdown appears: "Symbol: [None]"
3. User selects a symbol from the dropdown
4. Effect becomes linked

### Editing a Symbol

**Option A: Edit from Symbol Library Panel**
1. Open Symbol Library panel (new panel, dockable)
2. Double-click a symbol or click "Edit"
3. Symbol editor opens (similar to effect settings panel)
4. Changes apply to all linked effects immediately

**Option B: Edit via Linked Effect**
1. Select a linked effect on timeline
2. Effect panel shows "Linked to: [Symbol Name]" with "Edit Symbol" button
3. Click "Edit Symbol" to modify the master
4. Changes propagate to all linked effects

### Unlinking an Effect

1. Right-click a linked effect → "Unlink from Symbol"
2. Effect becomes independent, retaining current settings
3. Future symbol changes won't affect this effect

### Copying Linked Effects

- Copy/paste a linked effect → new effect is also linked to same symbol
- This allows rapid placement of linked effects throughout sequence

## Data Model

### New Class: EffectSymbol

```cpp
// Location: xLights/sequencer/EffectSymbol.h

class EffectSymbol {
public:
    EffectSymbol();
    EffectSymbol(const std::string& id, const std::string& name);

    // Identification
    std::string GetId() const;           // UUID, immutable
    std::string GetName() const;         // User-friendly name
    void SetName(const std::string& name);

    // Effect Definition
    std::string GetEffectType() const;   // "Twinkle", "Fire", etc.
    void SetEffectType(const std::string& type);

    SettingsMap& GetSettings();          // All effect parameters
    const SettingsMap& GetSettings() const;
    void SetSettings(const SettingsMap& settings);

    std::string GetPalette() const;      // Color palette string
    void SetPalette(const std::string& palette);

    // Serialization
    wxXmlNode* ToXml() const;
    static EffectSymbol FromXml(wxXmlNode* node);

private:
    std::string _id;          // UUID
    std::string _name;        // Display name
    std::string _effectType;  // Effect type name
    SettingsMap _settings;    // Effect settings
    std::string _palette;     // Color palette
};
```

### New Class: EffectSymbolManager

```cpp
// Location: xLights/sequencer/EffectSymbolManager.h

class EffectSymbolManager {
public:
    EffectSymbolManager();

    // Symbol Management
    EffectSymbol* CreateSymbol(const std::string& name, const Effect* sourceEffect);
    EffectSymbol* GetSymbol(const std::string& id) const;
    EffectSymbol* GetSymbolByName(const std::string& name) const;
    std::vector<EffectSymbol*> GetAllSymbols() const;
    void DeleteSymbol(const std::string& id);
    void RenameSymbol(const std::string& id, const std::string& newName);

    // Linked Effect Tracking
    void RegisterLinkedEffect(Effect* effect, const std::string& symbolId);
    void UnregisterLinkedEffect(Effect* effect);
    std::vector<Effect*> GetLinkedEffects(const std::string& symbolId) const;

    // Symbol Updates (propagates to all linked effects)
    void UpdateSymbol(const std::string& id, const SettingsMap& settings, const std::string& palette);

    // Serialization
    void LoadFromXml(wxXmlNode* symbolsNode);
    wxXmlNode* SaveToXml() const;

    // Notifications
    void AddListener(IEffectSymbolListener* listener);
    void RemoveListener(IEffectSymbolListener* listener);

private:
    std::map<std::string, std::unique_ptr<EffectSymbol>> _symbols;
    std::multimap<std::string, Effect*> _linkedEffects;  // symbolId -> effects
    std::vector<IEffectSymbolListener*> _listeners;

    void NotifySymbolChanged(const std::string& symbolId);
    std::string GenerateUniqueId();
};
```

### Modifications to Effect Class

```cpp
// Location: xLights/sequencer/Effect.h

class Effect {
public:
    // ... existing members ...

    // NEW: Symbol linking
    bool IsLinkedToSymbol() const;
    std::string GetLinkedSymbolId() const;
    void LinkToSymbol(const std::string& symbolId);
    void UnlinkFromSymbol();

    // When linked, settings come from symbol
    // GetSettings() should return symbol settings if linked

private:
    // ... existing members ...

    // NEW
    std::string _linkedSymbolId;  // Empty if not linked
};
```

### Listener Interface

```cpp
// Location: xLights/sequencer/EffectSymbolManager.h

class IEffectSymbolListener {
public:
    virtual ~IEffectSymbolListener() = default;
    virtual void OnSymbolChanged(const std::string& symbolId) = 0;
    virtual void OnSymbolDeleted(const std::string& symbolId) = 0;
    virtual void OnSymbolCreated(const std::string& symbolId) = 0;
};
```

## XML Serialization

### Sequence File Format Changes

Symbols are stored in a new `<EffectSymbols>` section within the sequence file:

```xml
<xsequence>
    <!-- Existing sequence data -->

    <EffectSymbols>
        <Symbol id="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
                name="Chorus Sparkle"
                effectType="Twinkle">
            <Settings>
                E_SLIDER_Twinkle_Count=50,E_SLIDER_Twinkle_Steps=20,...
            </Settings>
            <Palette>
                C_BUTTON_Palette1=#FFFFFF,C_BUTTON_Palette2=#0000FF,...
            </Palette>
        </Symbol>
        <Symbol id="..." name="Verse Fire" effectType="Fire">
            ...
        </Symbol>
    </EffectSymbols>

    <!-- Effects reference symbols by ID -->
    <Element name="Model1">
        <EffectLayer>
            <Effect type="Twinkle" startTime="1000" endTime="2000"
                    linkedSymbol="a1b2c3d4-e5f6-7890-abcd-ef1234567890"/>
        </EffectLayer>
    </Element>
</xsequence>
```

### Backward Compatibility

- Older xLights versions will ignore the `<EffectSymbols>` section
- Linked effects will appear as normal effects with settings embedded
- To support this, effects should serialize their resolved settings (from symbol) as fallback
- Add a version indicator to warn users if opening in older xLights

## UI Components

### 1. Symbol Library Panel

New dockable panel showing all symbols in the sequence.

**Layout:**
```
+------------------------------------------+
| Symbol Library                      [+][-]|
+------------------------------------------+
| [Search: ____________]                    |
+------------------------------------------+
| Name           | Type     | Used | Actions|
+------------------------------------------+
| Chorus Sparkle | Twinkle  |  12  | [E][D] |
| Verse Fire     | Fire     |   4  | [E][D] |
| Bridge Bars    | Bars     |   8  | [E][D] |
+------------------------------------------+
| [Create New Symbol]                       |
+------------------------------------------+
```

**Features:**
- List view of all symbols
- Shows effect type and usage count (linked effects)
- Edit (E) and Delete (D) buttons
- Double-click to edit
- Search/filter
- Create new symbol button
- Drag symbol to timeline to create linked effect

**Files to create:**
- `xLights/SymbolLibraryPanel.h`
- `xLights/SymbolLibraryPanel.cpp`
- `xLights/wxsmith/SymbolLibraryPanel.wxs` (optional, could be code-only)

### 2. Context Menu Additions

**Effect right-click menu additions:**

For unlinked effects:
```
---
Create Symbol from Effect...
Link to Symbol >
    [Symbol 1]
    [Symbol 2]
    ...
---
```

For linked effects:
```
---
Edit Symbol "[Symbol Name]"...
Unlink from Symbol
---
```

**Files to modify:**
- `xLights/sequencer/EffectsGrid.cpp` (context menu handling)

### 3. Effect Settings Panel Modifications

When a linked effect is selected:

```
+------------------------------------------+
| Effect: Twinkle                          |
| Symbol: [Chorus Sparkle    v] [Edit] [X] |
+------------------------------------------+
| (Settings displayed but grayed out)      |
| Count: [====50====]                       |
| Steps: [====20====]                       |
| ...                                       |
+------------------------------------------+
```

- Dropdown shows "None" (unlinked) or symbol name
- "Edit" button opens symbol editor
- "X" button unlinks
- Settings are visible but not editable (or editable with warning)

**Files to modify:**
- `xLights/EffectsPanel.cpp`
- `xLights/EffectsPanel.h`

### 4. Symbol Editor Dialog

Dialog for editing a symbol's settings.

```
+------------------------------------------+
| Edit Symbol: Chorus Sparkle         [X]  |
+------------------------------------------+
| Name: [Chorus Sparkle____________]       |
| Effect Type: Twinkle (read-only)         |
+------------------------------------------+
| [Standard effect settings panel]         |
| Count: [====50====]                       |
| Steps: [====20====]                       |
| ...                                       |
+------------------------------------------+
| Colors: [Color palette controls]         |
+------------------------------------------+
| Linked Effects: 12                       |
| [Preview] [OK] [Cancel] [Apply]          |
+------------------------------------------+
```

**Files to create:**
- `xLights/SymbolEditorDialog.h`
- `xLights/SymbolEditorDialog.cpp`

### 5. Visual Indicator for Linked Effects

Linked effects on the timeline should be visually distinct:

Options (pick one or combine):
- Small icon overlay (chain link icon) in corner of effect
- Colored border (e.g., cyan border for linked effects)
- Different background pattern
- Symbol name shown in small text

**Files to modify:**
- `xLights/sequencer/EffectsGrid.cpp` (effect rendering)

## Implementation Phases

### Phase 1: Core Data Model
1. Create `EffectSymbol` class
2. Create `EffectSymbolManager` class
3. Add `_linkedSymbolId` to `Effect` class
4. Implement XML serialization for symbols
5. Integrate `EffectSymbolManager` into `SequenceElements`

### Phase 2: Basic Linking
1. Implement `Effect::LinkToSymbol()` and `UnlinkFromSymbol()`
2. Modify `Effect::GetSettings()` to return symbol settings when linked
3. Implement symbol change propagation
4. Add context menu items for "Create Symbol" and "Link to Symbol"

### Phase 3: Symbol Library Panel
1. Create `SymbolLibraryPanel` class
2. Add panel to xLights frame
3. Implement symbol list view
4. Implement create/edit/delete operations

### Phase 4: Symbol Editor
1. Create `SymbolEditorDialog`
2. Implement settings editing
3. Implement live preview
4. Handle "Apply" to update all linked effects

### Phase 5: UI Polish
1. Add visual indicators for linked effects
2. Modify effect settings panel for linked effects
3. Add keyboard shortcuts
4. Add undo/redo support for symbol operations

### Phase 6: Testing & Edge Cases
1. Test copy/paste of linked effects
2. Test delete symbol (warn about orphaned effects)
3. Test undo/redo
4. Test sequence save/load
5. Test backward compatibility
6. Test performance with many linked effects

## Key Files to Modify

### New Files
- `xLights/sequencer/EffectSymbol.h`
- `xLights/sequencer/EffectSymbol.cpp`
- `xLights/sequencer/EffectSymbolManager.h`
- `xLights/sequencer/EffectSymbolManager.cpp`
- `xLights/SymbolLibraryPanel.h`
- `xLights/SymbolLibraryPanel.cpp`
- `xLights/SymbolEditorDialog.h`
- `xLights/SymbolEditorDialog.cpp`

### Modified Files
- `xLights/sequencer/Effect.h` - Add symbol linking
- `xLights/sequencer/Effect.cpp` - Implement linking methods
- `xLights/sequencer/SequenceElements.h` - Add EffectSymbolManager
- `xLights/sequencer/SequenceElements.cpp` - Manage symbol lifecycle
- `xLights/sequencer/EffectsGrid.cpp` - Context menus, visual indicators
- `xLights/xLightsXmlFile.cpp` - Serialize symbols in sequence file
- `xLights/EffectsPanel.cpp` - Show symbol dropdown for linked effects
- `xLights/xLightsMain.h` - Add Symbol Library panel
- `xLights/xLightsMain.cpp` - Initialize panel, menu items
- Build files: `xLights.cbp`, `xLights.vcxproj` - Add new source files

## Edge Cases & Considerations

### Deleting a Symbol
- Warn user: "This symbol is linked to X effects. Delete anyway?"
- Options:
  - Unlink all effects (they keep current settings but become independent)
  - Cancel

### Changing Symbol Effect Type
- Should be allowed but rare
- All linked effects change type
- Warn if linked effects exist: "This will change X effects to [new type]. Continue?"

### Copy/Paste Across Sequences
- Paste effect from sequence A to sequence B
- If effect is linked to symbol that doesn't exist in B:
  - Option 1: Create symbol in B (copy definition)
  - Option 2: Paste as unlinked effect
  - Prompt user to choose

### Undo/Redo
- Symbol creation/deletion should be undoable
- Symbol edits should be undoable
- Linking/unlinking should be undoable
- Leverage existing `UndoManager` system

### Performance
- Symbol lookup should be O(1) via hash map
- Symbol change propagation is O(n) where n = linked effects
- Consider batching UI updates when many effects change

### Model Group Considerations
- Linked effects on model groups work same as regular effects
- Symbol doesn't care about target model

## Future Enhancements

### Symbol Categories/Folders
- Organize symbols into folders: "Chorus", "Verse", "Bridge"
- Tree view in Symbol Library

### Symbol Import/Export
- Export symbols to file for sharing
- Import symbols from file or another sequence

### Symbol Preview
- Thumbnail preview of symbol in library
- Live preview when hovering over symbol

### Symbol Variants
- Allow linked effects to override specific settings
- "Use symbol but change color to red"
- More complex but powerful

### Symbol Triggers
- Integrate with timing marks
- "Apply this symbol at every beat"

## Questions to Resolve

1. **Should linked effects allow ANY local overrides?**
   - Pure link: No overrides, symbol is single source of truth
   - Partial link: Allow color override but not settings
   - Full override: Allow any override (complex UI)
   - Recommendation: Start with pure link, add overrides later

2. **What happens to effect timing when linking?**
   - Keep original timing (start/end time)
   - Symbol only defines settings and palette, not timing
   - This seems correct

3. **Should symbols be sequence-level or show-level?**
   - Sequence-level: Symbols stored in each sequence file
   - Show-level: Symbols stored in show folder, shared across sequences
   - Recommendation: Start with sequence-level, simpler

4. **How to handle symbol naming conflicts?**
   - Allow duplicate names? (Differentiate by ID internally)
   - Enforce unique names?
   - Recommendation: Enforce unique names for user clarity

## References

### Similar Features in Other Software
- Adobe Animate/Flash: Symbols and instances
- Figma: Components and instances
- Blender: Linked duplicates
- After Effects: Essential Graphics / Motion Graphics templates

### xLights Existing Code to Study
- `DuplicateEffect` - Only existing effect reference system
- `EffectManager` - How effects are managed
- `Presets` - How effect configurations are saved/loaded
- `SequenceElements` - How sequence data is organized

---

*Document created: December 2024*
*Feature branch: `feature/effect-symbols`*
