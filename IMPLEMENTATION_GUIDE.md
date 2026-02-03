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

1. **AppKit, not SwiftUI**: SwiftUI doesn't have the control fidelity needed for a timeline editor or 3D viewport. Use AppKit with Swift where possible, Objective-C++ at the bridging layer.

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
