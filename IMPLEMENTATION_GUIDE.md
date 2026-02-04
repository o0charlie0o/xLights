# Native macOS xLights Rebuild — Implementation Guide

## Purpose

This document serves as the architectural guide for rebuilding the xLights macOS UI as a native AppKit application while preserving the existing C++ rendering engine. Any agent working on a subtask of this rebuild should read this document first to understand where their work fits in the overall plan.

---

## Goal

Rebuild the xLights macOS UI to feel like a native Mac application — think Logic Pro X or Final Cut Pro X — while keeping the underlying C++ rendering engine intact. The behavioral layout stays the same (no breaking muscle memory), but the UI layer becomes performant, native, and Mac-idiomatic.

---

## Current State Assessment

### Separability Problem

The biggest challenge is that the UI and engine are **not separated**. The `xLightsFrame` class (1,985 lines in the header alone) acts as both the wxWidgets window AND the central business logic orchestrator. Key coupling points:

- `PixelBufferClass` holds a direct pointer to `xLightsFrame`
- Effects, models, and outputs all reference the main frame
- **Separability score: 2/10** — you cannot build a new UI on top of the existing engine without first creating an engine abstraction layer

### Existing macOS-Native Infrastructure

There is already significant macOS-native code to build on:

- **Metal rendering backend** (~77KB of shader code) — mature compute pipeline for GPU-accelerated effects
- **Swift bridging** for file access and Apple Intelligence integration
- **CADisplayLink** timer integration
- **Touch Bar** support
- The `xlMetalGraphicsContext.mm` file already demonstrates the Objective-C++ bridging pattern we'll use throughout

### UI Component Inventory

| Category | Count | Notes |
|---|---|---|
| Main tabs | 3 | Setup, Layout/Preview, Sequencer |
| Dockable panels | 21 | Buffer, Color, Effects, Timing, etc. |
| Effect panels | 65 | One per effect type, wxSmith-generated |
| Dialogs | 76+ | From simple alerts to complex editors |
| wxSmith UI definitions | 189 | XML layouts that generate C++ |
| Preferences panels | 10 | Settings pages |
| xSchedule UI | 73+ | Separate app, lower priority |
| **Total UI surfaces** | **~450+** | |

### The 3 Hardest Components

1. **EffectsGrid** (sequencer timeline) — 438KB file, custom OpenGL rendering, complex mouse interactions, multi-threaded playback sync
2. **LayoutPanel** (3D preview/model editor) — 403KB, 9,331 lines, 3D manipulation, property grid integration
3. **CustomModelDialog** — 3,555 lines, 3D geometry editor

---

## Target Architecture

### What "Logic Pro X / Final Cut Pro X" Means

Those apps share common patterns that xLights would adopt:

- Dark themed, single-window app with resizable pane regions (not floating palettes)
- `NSToolbar` with customizable items (not `wxAuiToolBar`)
- `NSSplitView` hierarchy (not `wxAuiManager` docking)
- `NSOutlineView` / `NSTableView` source lists (not `wxTreeCtrl`/`wxListCtrl`)
- `CAMetalLayer`-backed views for timeline and preview (already partially there)
- NSInspector-style sidebar for properties (not `wxPropertyGrid`)
- Responsive, 120Hz ProMotion-aware rendering
- Native drag and drop, undo manager, Cocoa text system
- `NSDocument` architecture for file handling

### Layer Diagram

```
┌─────────────────────────────────────┐
│     AppKit UI Layer (new)           │
│  NSViewControllers, NSViews, etc.   │
├─────────────────────────────────────┤
│     xlEngine C++ API (new)          │
│  Pure C++ interfaces, no wx types   │
│  Callback-based, thread-safe        │
├─────────────────────────────────────┤
│     Existing C++ Engine             │
│  Effects, Models, Outputs, Render   │
│  PixelBuffer, SequenceData, etc.    │
└─────────────────────────────────────┘
```

The `xlEngine` API exposes:

- **Sequence operations**: load, save, play, pause, seek, render
- **Model management**: CRUD, properties, node coordinates
- **Effect management**: create, modify, render to buffer
- **Output management**: controller config, protocol handling
- **Render pipeline**: frame requests, buffer access, layer blending
- **Event callbacks**: progress, state changes, errors

This is an Objective-C++ bridging layer. The existing Metal rendering code already demonstrates this pattern — `xlMetalGraphicsContext.mm` wraps Metal APIs and exposes them through a C++ abstract interface (`xlGraphicsContext`).

---

## Key Technical Decisions

1. **Technology Priority Order**: Use the highest-level technology that can accomplish the task:
   1. **Swift + SwiftUI** (preferred) — Use for standard UI components, inspectors, dialogs, and anywhere SwiftUI's declarative approach works well
   2. **Swift + AppKit** — Drop down to AppKit when SwiftUI lacks the control fidelity (e.g., custom timeline views, complex drag interactions)
   3. **Objective-C / Objective-C++** — Use at the bridging layer to interface with C++ engine code
   4. **C++** — The existing rendering engine remains C++; don't rewrite it

   The original guide said "AppKit, not SwiftUI" but SwiftUI has matured significantly. Prefer SwiftUI where it works, but don't fight it for complex custom views like the timeline editor or 3D viewport where AppKit gives more control.

2. **Fixed split regions, not docking**: Use the Logic Pro approach — fixed split regions with collapsible inspectors. `NSToolbar` controls visibility. This is simpler to build, more native-feeling, and avoids reinventing `wxAuiManager`.

3. **`wxString` elimination**: The engine abstraction uses `std::string` exclusively. The Objective-C++ bridge converts to `NSString` at the boundary.

4. **`wxPropertyGrid` replacement**: Build a reusable inspector view using `NSStackView` with disclosure groups. This is how Xcode and Logic do it.

5. **Effect panel generation**: Instead of porting 189 wxSmith XML files, create a metadata-driven panel builder. Each effect already stores its parameters in `SettingsMap` — generate UI from that.

---

## Phased Implementation Plan

### Phase 0: Engine Abstraction Layer

> **This must come first. Everything else is blocked on it.**

Before any UI work, extract a clean C++ engine API that the AppKit UI talks to. This is the critical path.

#### Tickets

| ID | Task | Description |
|---|---|---|
| 0A | Extract SequenceEngine API | Sequence load/save/play/pause/seek operations decoupled from `xLightsFrame` |
| 0B | Extract ModelEngine API | Model CRUD, properties, node coordinates, submodels — no wx types |
| 0C | Extract OutputEngine API | Controller config, protocol handling, output management |
| 0D | Extract RenderEngine API | Frame rendering, buffer access, layer blending, GPU pipeline |
| 0E | Extract EffectEngine API | Effect creation, parameter management, render-to-buffer |

#### Key Constraints

- All APIs must be **pure C++** — no wxWidgets types cross the boundary
- Must be **thread-safe** — AppKit main thread will call into these from a different thread than the render pipeline
- Must use **callbacks/delegates** for async events (progress, state changes, errors)
- Must not break the existing wxWidgets UI — both UIs should be buildable from the same engine during transition

#### Architecture Notes

The current god-object `xLightsFrame` serves as the hub. Each sub-API needs to identify which `xLightsFrame` methods and member variables it depends on, wrap them in a clean interface, and route calls through that interface. The existing wxWidgets UI can be refactored to use the same API, ensuring it stays functional during the transition.

---

### Phase 1: App Shell & Core Navigation

> **Blocked on**: Phase 0 (all sub-tasks)

Build the main window, toolbar, split views, and tab switching. Get a native app running that opens show folders and displays the three main views (even if mostly empty).

| ID | Task | Parallel? | Description |
|---|---|---|---|
| 1A | Main window + NSSplitView | — | Core window with the three-region split layout |
| 1B | NSToolbar + menus | Yes (with 1A) | Play controls, tool mode selectors, view toggles |
| 1C | NSDocument integration | Yes (with 1A) | `.xlights` file opening, recent files, dirty state tracking |
| 1D | Preferences window | Yes (with 1A) | `NSPreferencesWindow` with 10 settings panes |

---

### Phase 2: Setup Tab (Controllers)

> **Blocked on**: 1A, 0C

The simplest of the three main tabs — mostly table views and forms.

| ID | Task | Parallel? | Description |
|---|---|---|---|
| 2A | Controller list view | — | `NSTableView` showing all controllers |
| 2B | Controller detail inspector | Yes | Properties sidebar for selected controller |
| 2C | Port config grid | Yes | Port assignment and configuration |
| 2D | Network discovery | Yes | Async controller discovery using GCD |

---

### Phase 3: Layout/Preview Tab

> **Blocked on**: 1A, 0B, 0D

The 3D preview already uses Metal. The main work is replacing the wxWidgets wrapper with a native `NSView`-based Metal view, and rebuilding the model tree, property inspector, and manipulation handles.

| ID | Task | Parallel? | Description |
|---|---|---|---|
| 3A | Metal preview NSView | — | Replace `wxMetalCanvas` with native Metal `NSView` |
| 3B | Model tree | Yes (with 3A) | `NSOutlineView` with drag/drop for model hierarchy |
| 3C | Property inspector | Yes (with 3A) | `NSStackView`-based inspector sidebar |
| 3D | Manipulation handles | Blocked on 3A | 2D/3D model manipulation in the preview |
| 3E | Model dialogs | Yes (with 3A) | Import, creation, and configuration dialogs |

---

### Phase 4: Sequencer Tab (The Hard One)

> **Blocked on**: 1A, 0A, 0D, 0E

This is the Logic Pro X moment. The effects grid, timeline, waveform, row headings, and playback controls all need to be rebuilt as high-performance Metal/CoreAnimation-backed views.

| ID | Task | Parallel? | Description |
|---|---|---|---|
| 4A | Timeline ruler view | — | `CALayer`-backed time ruler with zoom/scroll |
| 4B | Effects grid | Yes (with 4A) | Metal-rendered `NSView` — the single hardest component |
| 4C | Waveform view | Yes | CoreAudio + Metal audio waveform display |
| 4D | Row headings | Yes | Element/model list (NSOutlineView or custom) |
| 4E | Transport controls | Yes | Play/pause/stop/record, tempo, loop controls |
| 4F | Interactions | Blocked on 4B | Effect drag/drop, resize, multi-select, copy/paste |
| 4G | Scroll sync | Blocked on 4A, 4B, 4D | Horizontal/vertical scroll synchronization across views |
| 4H | Undo/redo | Blocked on 4F | `NSUndoManager` integration for all sequencer actions |

---

### Phase 5: Effect Panels

> **Blocked on**: 0E, 4B

65 panels, but they follow a consistent pattern: sliders, color pickers, dropdowns, checkboxes. Build a declarative panel system that generates AppKit controls from effect parameter definitions, rather than hand-coding 65 panels.

| ID | Task | Parallel? | Description |
|---|---|---|---|
| 5A | Panel builder system | — | Declarative system that reads effect parameter metadata and generates `NSView` hierarchies |
| 5B | 65 panel definitions | Blocked on 5A, highly parallel | One definition per effect, feeding into the panel builder |

Each effect already stores its parameters in `SettingsMap`. The panel builder reads the parameter schema (types, ranges, defaults) and generates appropriate AppKit controls:

- `SettingsMap` int range → `NSSlider` + `NSTextField`
- `SettingsMap` bool → `NSSwitch`
- `SettingsMap` choice → `NSPopUpButton`
- `SettingsMap` color → `NSColorWell`
- `SettingsMap` file → path picker
- `SettingsMap` value curve → custom curve editor view

---

### Phase 6: Remaining Dialogs & Polish

> **Blocked on**: Phase 1; can overlap with Phases 2–5

Convert the ~76 dialogs. Many are simple (`NSAlert` replacements). The complex ones get individual attention.

| ID | Task | Count | Parallel? | Description |
|---|---|---|---|---|
| 6A | Simple dialogs | 30–40 | Massively parallel | `NSAlert`, `NSOpenPanel`, `NSSavePanel` wrappers |
| 6B | Medium dialogs | 25–30 | Parallel | Standard `NSViewController` forms |
| 6C | Complex dialogs | 5–10 | Parallel | `CustomModelDialog`, `ControllerModelDialog`, `ValueCurveDialog`, etc. |

---

## Dependency Graph

```
Phase 0: Engine Abstraction
    ├── 0A: Extract SequenceEngine API ──────────────┐
    ├── 0B: Extract ModelEngine API ─────────────────┤
    ├── 0C: Extract OutputEngine API ────────────────┤
    ├── 0D: Extract RenderEngine API ────────────────┤
    └── 0E: Extract EffectEngine API ────────────────┤
                                                      │
Phase 1: App Shell (blocked on 0A–0E)                │
    ├── 1A: Main window + NSSplitView ◄──────────────┘
    ├── 1B: NSToolbar + menus (parallel with 1A)
    ├── 1C: NSDocument integration (parallel with 1A)
    └── 1D: Preferences window (parallel with 1A)

Phase 2: Setup Tab (blocked on 1A, 0C)
    ├── 2A: Controller list view
    ├── 2B: Controller detail inspector (parallel)
    ├── 2C: Port config grid (parallel)
    └── 2D: Network discovery (parallel)

Phase 3: Layout Tab (blocked on 1A, 0B, 0D)
    ├── 3A: Metal preview view
    ├── 3B: Model tree (parallel with 3A)
    ├── 3C: Property inspector (parallel)
    ├── 3D: Manipulation handles (blocked on 3A)
    └── 3E: Model dialogs (parallel with 3A)

Phase 4: Sequencer (blocked on 1A, 0A, 0D, 0E)
    ├── 4A: Timeline ruler
    ├── 4B: Effects grid (parallel with 4A)
    ├── 4C: Waveform view (parallel)
    ├── 4D: Row headings (parallel)
    ├── 4E: Transport controls (parallel)
    └── 4F: Interactions (blocked on 4B)

Phase 5: Effect Panels (blocked on 0E, 4B)
    ├── 5A: Panel builder system
    └── 5B: 65 panel definitions (blocked on 5A, highly parallel)

Phase 6: Dialogs (blocked on Phase 1, can overlap with 2–5)
    ├── 6A: Simple dialogs (30–40, massively parallel)
    ├── 6B: Medium dialogs (25–30, parallel)
    └── 6C: Complex dialogs (5–10, parallel)
```

### Parallelism Summary

- **Phase 0**: Up to 5 agents (but architecturally sensitive — requires coordination)
- **Phase 1**: Up to 4 agents
- **Phases 2–4**: Can overlap once their dependencies are met (3–5 concurrent workstreams)
- **Phase 5B**: Up to 65-way parallel once the builder system (5A) is done
- **Phase 6**: Massively parallel (30–40 simple dialogs at once)

---

## Validation Spikes (Recommended Before Full Commit)

Before committing to the full rebuild, three spikes can validate the approach:

### Spike 1: Engine API Vertical Slice

Extract just enough API to load a sequence, render one model's effects to a buffer, and read back pixel data. No UI. **Proves the decoupling is possible.**

### Spike 2: Metal Timeline View

Build a standalone Metal-rendered `NSView` that can display a hardcoded timeline with effects. **Proves the FCP-style timeline rendering is achievable.**

### Spike 3: AppKit Inspector

Build the property inspector pattern once, test it with model properties. **Proves the `wxPropertyGrid` replacement works.**

If all three spikes succeed, proceed with full implementation.

---

## Key Source Files Reference

Agents working on specific phases should familiarize themselves with these files:

### Engine Core (Phase 0)
- `xLights/xLightsMain.h` — The god-object, 1,985-line header. Central to everything.
- `xLights/PixelBuffer.h/cpp` — Rendering orchestrator (~3,657 lines)
- `xLights/RenderBuffer.h/cpp` — Effect output target
- `xLights/outputs/OutputManager.h/cpp` — Output coordination
- `xLights/models/ModelManager.h/cpp` — Model management
- `xLights/effects/RenderableEffect.h` — Effect base class
- `xLights/sequencer/SequenceElements.h/cpp` — Sequence data structure

### Existing macOS/Metal Code (Reference Pattern)
- `xLights/graphics/metal/` — Metal rendering backend (6 files, ~77KB shaders)
- `xLights/graphics/xlGraphicsBase.h` — Abstract graphics interface
- `xLights/graphics/xlGraphicsContext.h` — Graphics context abstraction
- Files matching `*.mm` — Existing Objective-C++ bridging examples

### UI Components Being Replaced
- `xLights/sequencer/EffectsGrid.h/cpp` — 438KB, the timeline grid
- `xLights/LayoutPanel.h/cpp` — 403KB, the layout/preview editor
- `xLights/TabSetup.cpp` — 3,090 lines, setup tab
- `xLights/sequencer/MainSequencer.h/cpp` — 85KB, sequencer orchestration
- `xLights/CustomModelDialog.h/cpp` — 3,555 lines, model editor
- `xLights/wxsmith/` — 189 `.wxs` files defining current UI layouts

### Configuration & Data Flow
- `xLights/xLightsXmlFile.h/cpp` — Sequence file format
- `xLights/FSEQFile.cpp` — Binary sequence format
- `xLights/SequenceData.h/cpp` — Raw channel data
- `xLights/ValueCurve.h/cpp` — Animation curves
- `xLights/Color.h/cpp` — Color system

---

## Notes for Agents

1. **Don't break the existing UI.** Both the wxWidgets UI and the new AppKit UI must be buildable during the transition. The engine abstraction layer is the key — it gives both UIs the same API to talk to.

2. **No wx types cross the engine boundary.** Use `std::string`, not `wxString`. Use `std::vector`, not `wxArrayString`. The Objective-C++ bridge converts to `NSString`/`NSArray` at the AppKit boundary.

3. **Follow existing patterns.** The Metal rendering code in `xLights/graphics/metal/` already demonstrates the Objective-C++ bridging pattern. Study `xlMetalGraphicsContext.mm` before writing new bridge code.

4. **Thread safety matters.** The AppKit main thread and the render pipeline run on different threads. The engine API must be safe to call from both. Use callbacks/delegates for async operations, not polling.

5. **Match the surrounding code style.** See `CLAUDE.md` section 16 for contribution guidelines. Keep commits concise, don't add unnecessary comments, match the style of nearby code.

6. **Test with real sequences.** The engine abstraction must handle real `.xlights` files, not just toy examples. Test with sequences that have multiple models, layered effects, and audio sync.

---

## Current UI Layout Decisions

> **Important**: These decisions reflect the current implementation. Do not revert these without explicit user approval.

### Sequencer Tab Layout

The Sequencer tab uses a split layout optimized for timeline editing:

```
┌─────────────────────────────────────────────────────────────┐
│ Toolbar (playback controls, render, [Palettes] [Inspector]) │
├─────────────────────────────────────────────────────────────┤
│            [Effects] [Colors] [Blending] [Settings]         │  ← Multi-select toggles (centered)
├─────────────────────────────────────────────────────────────┤
│   Visible Panels Side-by-Side (width shared equally)        │
│   ┌─────────────────┬─────────────────┬─────────────────┐   │
│   │ Effects Grid    │ Colors Panel    │ Blending Panel  │   │  ← Example: 3 panels visible
│   └─────────────────┴─────────────────┴─────────────────┘   │
├────────────────┬────────────────────────────────────────────┤
│ Track Height   │    Timeline Ruler                          │
│ Slider [─●──]  │    0s    5s    10s   15s   20s   ...       │
├────────────────┼────────────────────────────┬───────────────┤
│                │    Waveform                │               │
│                │    ▁▂▃▅▆▇█▇▆▅▃▂▁▂▃▅▆▇█▇▆▅▃ │               │
├────────────────┼────────────────────────────┤   Inspector   │
│                │                            │   (Right)     │
│  Row Headings  │   Sequencer Timeline       │               │
│  (Track names) │   (Effects Grid)           │  Effect Props │
│                │                            │  when effect  │
│                │                            │  selected     │
├────────────────┴────────────────────────────┤               │
│               Transport Bar                 │               │
└─────────────────────────────────────────────┴───────────────┘
```

#### Key Layout Decisions

1. **Top Panel with Multi-Select Toggles**: The top panel uses a **multi-select toggle bar** (centered) where multiple panels can be visible simultaneously:
   - **Effects**: Horizontal grid of effect types for drag-and-drop to timeline
   - **Colors**: Color palettes and color picker (to be implemented)
   - **Blending**: Blend modes, opacity, mask settings (to be implemented)
   - **Settings**: Buffer settings, rotation, zoom (to be implemented)
   - Visible panels are displayed **side-by-side**, sharing the available width equally
   - Clicking a toggle shows/hides that panel without affecting others

2. **Effect Properties Location**: Effect properties appear in the **right inspector panel** when an effect is selected on the sequencer tab. The inspector is context-sensitive—it shows effect properties on the Sequencer tab and general model/sequence info on other tabs.

3. **Timeline Full Width**: The sequencer timeline and effects grid extend to **full width** (minus the toggleable inspector). The top panel does not take horizontal space from the timeline.

4. **Effect Palette Grid Design**:
   - Two-row horizontal LazyHGrid layout
   - Effects sorted alphabetically ascending (A-Z)
   - Each cell shows effect icon (colored square with first letter) and name
   - Supports drag-and-drop to timeline via `NSDraggingSource` protocol
   - Uses custom `XLEffectTypePasteboardType` pasteboard type

5. **Top Panel Resizable**: The top panel (Effects/Colors/Blending/Settings area) can be resized:
   - **Vertical resize**: Drag the handle at the bottom of the panel (just above the timeline ruler)
     - Height constrained between 100px and 500px
     - Height persisted in UserDefaults (`XLTopPanelHeight`)
   - **Horizontal resize**: When multiple panels are visible, drag the dividers between them
     - Each panel has a minimum width (10% of available space)
     - Panel width proportions persisted in UserDefaults (`XLPanelWidthProportions`)
     - Uses native AppKit NSView for smooth, low-latency dragging
   - Both handles highlight on hover and during drag
   - Cursor changes to appropriate resize cursor (up/down or left/right)

6. **Panel Visibility Toggles** (toolbar button order, left to right):
   - Palettes: Toggled via toolbar button (rectangle.split.1x2 icon) — shows/hides entire top panel area
   - Inspector: Toggled via toolbar button (sidebar.right icon) — **far right**
   - Individual top panels toggled via the multi-select buttons in the top panel header
   - All visibility states persisted in UserDefaults (using bitmask for top panels)

7. **Track Height Slider** (Logic Pro X style):
   - Located in the **top-left corner** (above track labels, left of timeline ruler)
   - Fills the empty space at coordinates (0,0) to (rowHeaderWidth, timelineRulerHeight)
   - Slider adjusts all track heights uniformly (16px to 80px)
   - Small/large track icons on either side of the slider
   - Persisted in UserDefaults (`XLSequencerRowHeight`)
   - Syncs row height between row headings and effects grid views

8. **Waveform Position**:
   - Located **above the timeline** (below the top panel area, above the effects grid)
   - Aligned with the timeline ruler (starts at row header width, extends to right edge)
   - Height: 60px fixed
   - Synchronized scrolling and zoom with timeline ruler and effects grid
   - Shows audio waveform when sequence has media file loaded

### SwiftUI vs AppKit Components

| Component | Technology | Reason |
|-----------|------------|--------|
| Top Panel Toggle Bar | SwiftUI (custom ButtonStyle) | Multi-select toggle buttons, centered layout |
| Effect Palette Grid | SwiftUI + NSViewRepresentable | SwiftUI for layout, AppKit drag source for proper pasteboard support |
| Color Palette Panel | SwiftUI (placeholder) | To be implemented |
| Layer Blending Panel | SwiftUI | Comprehensive layer mixing, color adjustments, transitions, roto-zoom |
| Layer Settings Panel | SwiftUI | Buffer/Roto-Zoom controls with tabbed interface |
| Effect Properties Panel | SwiftUI | Declarative property display, metadata-driven controls |
| Top Panel Resize Handle (Vertical) | NSViewRepresentable + AppKit | Smooth vertical panel height adjustment |
| Panel Resize Handle (Horizontal) | NSViewRepresentable + AppKit | Smooth horizontal panel width adjustment between visible panels |
| Sequencer Timeline | AppKit (Objective-C) | Complex interactions, Metal rendering |
| Waveform View | AppKit (Objective-C) | Audio visualization, synchronized scroll/zoom |
| Row Headings | AppKit (Objective-C) | Track labels, expand/collapse |
| Track Height Slider | AppKit (Objective-C) | Part of sequencer view controller |
| Inspector Container | SwiftUI | NavigationSplitView for panel management |

### Effect Drag-and-Drop Implementation

The effect palette uses a hybrid SwiftUI/AppKit approach:

1. **SwiftUI `LazyHGrid`** handles layout and scrolling
2. **`NSViewRepresentable`** wraps each effect cell
3. **Custom `EffectDragSourceView`** (NSView subclass) implements `NSDraggingSource`
4. **Pasteboard type**: `XLEffectTypePasteboardType` ("com.xlights.effectType")

This approach is necessary because SwiftUI's native drag-and-drop doesn't properly support custom pasteboard types needed for the Objective-C timeline drop target.

### Key Files

| File | Purpose |
|------|---------|
| `native-mac/XLMainContentView.swift` | Main layout, panel visibility, tab switching, top panel toggles |
| `native-mac/LayerSettingsView.swift` | Buffer/Roto-Zoom settings panel (SwiftUI) |
| `native-mac/LayerBlendingView.swift` | Layer blending/mix mode panel (SwiftUI) |
| `native-mac/EffectPaletteGridView.swift` | Effect palette horizontal grid with drag source |
| `native-mac/EffectPropertiesView.swift` | Effect properties inspector panel |
| `native-mac/EffectSelectionState.swift` | Shared state for effect selection across views |
| `native-mac/XLSequencerViewController.m` | Sequencer layout, track height slider, view coordination |
| `native-mac/sequencer/XLRowHeadingsView.h/m` | Row headings (track names, expand/collapse) |
| `native-mac/sequencer/XLEffectsGridView.h/m` | Metal-backed effects timeline grid |
| `native-mac/sequencer/XLWaveformView.h/m` | Audio waveform display (above timeline) |
| `native-mac/sequencer/XLTimelineRulerView.h/m` | Timeline ruler with time markers |
| `native-mac/sequencer/XLScrollCoordinator.h/m` | Synchronized scrolling between views |

---

## Sequencer Data Structures & Implementation Notes

### Row and Effect Data Model

The sequencer uses C-array structures for performance and direct integration with the C++ engine:

```objc
// XLSequencerViewController.m
XLRowEntry* _rowData;       // Array of row metadata (track name, type, visibility)
XLEffectEntry* _effectData; // Array of all effects across all tracks
NSUInteger _rowCount;       // Number of tracks
NSUInteger _effectCount;    // Total effect count
```

#### XLRowEntry Structure

```objc
typedef struct {
    NSString* __unsafe_unretained name;  // Track/element name
    XLElementType type;                   // Model, ModelGroup, Timing, etc.
    BOOL visible;                         // Track visibility
    BOOL expandable;                      // Has children (submodels, strands, group members)
    BOOL expanded;                        // Currently showing children
    NSInteger elementIndex;               // Stable index for effect association
} XLRowEntry;
```

#### XLEffectEntry Structure

```objc
typedef struct {
    NSInteger elementIndex;   // Links to XLRowEntry.elementIndex (stable reference)
    CGFloat startTime;        // Effect start in seconds
    CGFloat endTime;          // Effect end in seconds
    NSString* __unsafe_unretained effectType;  // Effect type name
    NSInteger layerIndex;     // Layer within element
} XLEffectEntry;
```

### Effect-to-Row Association

**Critical Design Decision**: Effects are associated with rows via `elementIndex`, not row position.

When rows are reordered (drag-and-drop), the `_rowData` array is shuffled but `elementIndex` values remain stable. Effect lookup iterates through `_effectData` and matches by `elementIndex`:

```objc
- (NSInteger)effectsGrid:(XLEffectsGridView *)gridView numberOfEffectsInRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData || !_effectData) return 0;
    NSInteger elementIndex = _rowData[row].elementIndex;
    NSInteger count = 0;
    for (NSUInteger i = 0; i < _effectCount; i++) {
        if (_effectData[i].elementIndex == elementIndex) {
            count++;
        }
    }
    return count;
}
```

This ensures effects move with their tracks during reordering rather than staying at their visual row position.

### Element Type Detection

The engine bridge (`XLEngineBridge.mm`) determines element types by querying the underlying C++ model:

```objc
// XLEngineBridge.mm - getSequenceElementAtIndex:
Model* model = frame->AllModels[elem->GetName()];
if (model && model->GetDisplayAs() == "ModelGroup") {
    typeString = @"group";
    isGroup = YES;
}
```

The bridge returns additional metadata for UI display:
- `isGroup` - Whether element is a model group
- `hasSubmodels` - Element has submodel children
- `hasStrands` - Element has strand children
- `submodelCount` / `strandCount` - Number of children

### Track Type Icons

Row headings display SF Symbol icons based on element type:

| Element Type | SF Symbol | Description |
|--------------|-----------|-------------|
| `XLElementTypeModel` | `lightbulb` | Individual prop/model |
| `XLElementTypeModelGroup` | `square.grid.2x2` | Group of models |
| `XLElementTypeTiming` | `metronome` | Timing track |
| `XLElementTypeSubmodel` | `rectangle.split.3x1` | Submodel of a model |
| `XLElementTypeStrand` | `point.3.connected.trianglepath.dotted` | Strand/string |

### Timing Track Ordering

Timing tracks are always displayed at the top of the sequencer, regardless of the order they are returned by the engine. After loading sequence data, `sortRowsWithTimingFirst` performs a stable partition:

1. Timing tracks (`XLElementTypeTiming`) are collected first
2. All other tracks (models, groups, etc.) follow
3. Relative order within each group is preserved

```objc
// XLSequencerViewController.m - sortRowsWithTimingFirst
// Partitions _rowData so timing tracks appear first while preserving relative order
```

This matches the standard xLights behavior where timing tracks are always visible at the top of the sequencer for easy access.

**TODO**: Timing tracks have special functionality - they can be toggled to display grid lines at timing segments on the effects grid. This needs to be implemented.

### Layer Expansion

Elements with multiple effect layers can be expanded to show individual layer rows:

**XLRowEntry Layer Fields:**
```objc
NSInteger layerIndex;    // -1 for main element row, 0+ for specific layer rows
BOOL isLayerRow;         // YES if this is a layer sub-row (not the main element)
```

**Behavior:**
- Elements with `effectLayerCount > 1` show as expandable (except timing tracks)
- Main row displays layer count in name: `"Mega Tree [3]"`
- When **collapsed**: Main row shows ALL effects from all layers overlaid
- When **expanded**: Main row shows layer 0 effects, sub-rows show layers 1, 2, etc.
- Layer sub-rows display as `"   [Layer 2]"` with indent

**Data Source Logic:**
```objc
// numberOfEffectsInRow:
if (rowEntry->isLayerRow) {
    // Show only effects for this specific layer
} else if (rowEntry->expanded) {
    // Main row expanded: show only layer 0
} else {
    // Main row collapsed: show ALL effects from all layers
}
```

**Expand/Collapse Toggle (`didToggleExpandAtRow:`):**
- Expanding: Inserts `(layerCount - 1)` layer sub-rows after the main row
- Collapsing: Removes consecutive layer sub-rows belonging to that element

### Expand/Collapse State (Submodels/Strands)

**Current Status**: Expand/collapse for submodels and strands is **disabled** pending child element loading implementation.

```objc
// XLSequencerViewController.m - updateSequencerData
row->expandable = NO;  // TODO: Enable when child loading implemented
row->expanded = NO;
```

When enabled, expandable tracks will show disclosure arrows. Expanding a track will:
1. Query engine bridge for child elements (submodels, strands, or group members)
2. Insert child rows below parent in `_rowData`
3. Refresh effects grid to show child effects

**TODO**: Implement `getChildElementsForElement:` in `XLEngineBridge.mm` to return submodel/strand/group member data.

---

## Top Panel Implementations

### Layer Settings Panel (`LayerSettingsView.swift`)

The Layer Settings panel provides controls for buffer rendering and roto-zoom transformations. It uses a tabbed interface implemented in SwiftUI.

**File**: `native-mac/LayerSettingsView.swift`

#### Tab Structure

```
┌──────────────────────────────────────────┐
│    [Buffer]  [Roto-Zoom]                 │  ← Segmented picker
├──────────────────────────────────────────┤
│  (Tab-specific content)                  │
└──────────────────────────────────────────┘
```

#### Buffer Tab Controls

| Control | Type | Range/Options | Description |
|---------|------|---------------|-------------|
| Render Style | Picker | Default, Per Preview, Per Model Default, Per Model Per Preview, Single Line, As Pixels | How the effect renders to the buffer |
| Buffer Stagger | Stepper + TextField | -100 to 100 | Offset timing between strands |
| Camera | Picker | 2D, 3D | Camera mode for rendering |
| Transformation | Picker | None, Rotate CC/CW 90°, Rotate 180°, Flip V/H, etc. | Buffer transformation |
| Blur | Slider | 1-15 | Blur intensity |
| Overlay Background | Toggle | On/Off | Whether to overlay effect on background |

#### Roto-Zoom Tab Controls

| Control | Type | Range | Description |
|---------|------|-------|-------------|
| Preset | Picker | None, Rotate Left/Right, Zoom In/Out, Rotate & Zoom | Quick presets |
| **2D Rotation Section** |
| Rotation | Slider | 0-100% | Rotation percentage |
| Rotations | Slider | 0-20x (0.1 step) | Number of full rotations |
| Pivot X | Slider | 0-100% | Horizontal pivot point |
| Pivot Y | Slider | 0-100% | Vertical pivot point |
| **Zoom Section** |
| Zoom | Slider | 0-3x (0.1 step) | Zoom multiplier |
| Quality | Slider | 1-10 | Zoom quality level |
| **3D Rotation Section** |
| X Rotation | Slider | 0-360° | X-axis rotation |
| X Pivot | Slider | 0-100% | X-axis pivot point |
| Y Rotation | Slider | 0-360° | Y-axis rotation |
| Y Pivot | Slider | 0-100% | Y-axis pivot point |
| Rotation Order | Picker | X-Y-Z, X-Z-Y, Y-X-Z, Y-Z-X, Z-X-Y, Z-Y-X | Order of rotation transforms |

#### Implementation Details

**Enums**:
- `LayerSettingsTab` - Buffer, RotoZoom tab selection
- `RenderStyle` - Buffer rendering style options
- `BufferTransformation` - Buffer transformation options
- `RotoZoomPreset` - Preset rotation/zoom configurations
- `RotationOrder` - 3D rotation order options

**Helper Views**:
- `SettingsRow<Content>` - Label + content row with consistent spacing
- `SliderRow` - Slider with label and formatted value display

**Preset Application**:
The Roto-Zoom tab includes preset buttons that automatically configure multiple values:
```swift
// Example: applyPreset(.rotateAndZoom)
rotation = 50
rotations = 1
zoom = 1.5
pivotPointX = 50
pivotPointY = 50
```

**TODO**: Wire Layer Settings panel state to engine bridge to affect actual rendering. Currently the controls are functional but not connected to the C++ effect rendering pipeline.

### Layer Blending Panel (`LayerBlendingView.swift`)

The Layer Blending panel provides comprehensive controls for layer mixing, color adjustments, transitions, and special effects. It uses collapsible disclosure sections implemented in SwiftUI.

**File**: `native-mac/LayerBlendingView.swift`

#### Section Structure

```
┌──────────────────────────────────────────┐
│ ▼ Layer Blending                         │  ← Collapsible section
│   Mix Type, Threshold, Morph, Canvas     │
├──────────────────────────────────────────┤
│ ▼ Color Adjustments                      │
│   Brightness, Hue, Saturation, etc.      │
├──────────────────────────────────────────┤
│ ▶ Transitions (collapsed by default)     │
├──────────────────────────────────────────┤
│ ▶ Buffer                                 │
├──────────────────────────────────────────┤
│ ▶ Roto-Zoom                              │
├──────────────────────────────────────────┤
│ ▶ Special Effects                        │
└──────────────────────────────────────────┘
```

#### Section Controls

**Layer Blending Section**:
| Control | Type | Options/Range | Description |
|---------|------|---------------|-------------|
| Mix Type | Picker | 24+ mix modes | Blending mode (Normal, Layered, Mask, Additive, etc.) |
| Mix Threshold | Slider | 0-100% | Effect mix threshold |
| Layer Morph | Toggle | On/Off | Enable layer morphing |
| Canvas | Toggle | On/Off | Canvas mode |

**Color Adjustments Section**:
| Control | Type | Range | Description |
|---------|------|-------|-------------|
| Brightness | Slider | 0-400% | Overall brightness |
| Hue Adjust | Slider | -100 to 100 | Hue shift |
| Saturation | Slider | -100 to 100 | Saturation adjustment |
| Value | Slider | -100 to 100 | Value adjustment |
| Contrast | Slider | -100 to 100 | Contrast adjustment |
| Brightness as Level | Toggle | On/Off | Use brightness as level |

**Transitions Section**:
| Control | Type | Options/Range | Description |
|---------|------|---------------|-------------|
| Fade In/Out | TextField | Seconds | Fade duration |
| In/Out Transition Type | Picker | 22 transition types | Fade, Wipe, Clock, etc. |
| In/Out Adjust | Slider | 0-100 | Transition adjustment |
| In/Out Reverse | Toggle | On/Off | Reverse transition direction |

**Buffer Section**:
| Control | Type | Options/Range | Description |
|---------|------|---------------|-------------|
| Transform | Picker | 8 options | Buffer transformation |
| Blur | Slider | 1-15 px | Blur amount |
| Stagger | Stepper | -100 to 100 | Buffer stagger |
| Persistent | Toggle | On/Off | Persistent buffer |

**Roto-Zoom Section**:
| Control | Type | Range | Description |
|---------|------|-------|-------------|
| Rotation Order | Picker | 6 orders | X-Y-Z, Y-X-Z, etc. |
| Z Rotation/Rotations | Sliders | 0-100, 0-20x | Roll rotation |
| Pivot X/Y | Sliders | 0-100% | Pivot points |
| X/Y Rotation | Sliders | 0-360° | Pitch/Yaw rotation |
| X/Y Pivot | Sliders | 0-100% | Per-axis pivot |
| Zoom | Slider | 0-3x | Zoom multiplier |
| Quality | Stepper | 1-10 | Zoom quality |

**Special Effects Section**:
| Control | Type | Range | Description |
|---------|------|-------|-------------|
| Sparkle Frequency | Stepper | 0-200 | Sparkle frequency |
| Music Sparkles | Toggle | On/Off | Audio-reactive sparkles |
| Chroma Key Enable | Toggle | On/Off | Enable chroma keying |
| Chroma Sensitivity | Slider | 1-255 | Key sensitivity |
| Chroma Color | ColorWell | Color | Key color |
| Freeze at Frame | Stepper | 0-99999 | Frame to freeze at |
| Suppress Until | Stepper | 0-99999 | Frame to suppress until |

#### Implementation Details

**State Management**:
- `LayerBlendingState` - Observable class holding all blending settings
- Listens for `XLEffectSelectionDidChangeNotification` to sync with effect selection
- Uses Combine for notification observation

**Mix Types** (`MixType` enum): 24 blend modes including Normal, Effect 1/2, Mask 1/2, Unmask 1/2, True Unmask 1/2, Reveals, Layered, Average, Bottom-Top, Left-Right, Shadow, Additive, Subtractive, As Brightness, Max, Min, Highlight, Highlight Vibrant

**Transition Types** (`TransitionType` enum): 22 transitions including Fade, Wipe, Clock, From Middle, Square, Circle Explode/Implode, Blinds, Blend, Slide Checks, Fold, Dissolve, Circular Swirl, Bow Tie, Zoom, Doorway, Blobs, Pinwheel, Star, Shatter

**Reusable Components**:
- `DisclosureSection` - Collapsible section with icon and title
- `LabeledSlider` - Slider with label and formatted value
- `LabeledPicker` - Dropdown picker with label
- `LabeledTextField` - Text field with label
- `LabeledStepper` - Stepper with label and value display
- `LabeledColorWell` - Color picker with label
- `ColorWellView` - NSViewRepresentable wrapper for NSColorWell

**TODO**: Wire Layer Blending panel state to engine bridge to affect actual rendering. Currently the controls are functional but not connected to the C++ effect rendering pipeline.
