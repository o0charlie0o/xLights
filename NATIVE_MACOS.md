# Native macOS Rebuild — Agent Quick Start

This document gets you oriented for working on the native macOS rebuild of xLights. Read this before touching any code.

---

## What Is This?

We're rebuilding the xLights macOS UI as a native AppKit/SwiftUI app (think Logic Pro X / Final Cut Pro X) while keeping the existing C++ rendering engine. The native app lives alongside the legacy wxWidgets app — both build from the same repo using different Xcode schemes.

**Branch**: `feature/native-macos-rebuild`

---

## Build Instructions

```bash
# Native macOS app (what we're building):
xcodebuild -project macOS/xLights.xcodeproj -scheme "xLights Native" -configuration Debug build

# DO NOT use the "xLights" scheme — that's the legacy wxWidgets build
# and has pre-existing link errors unrelated to our work.
```

The native build defines `XLIGHTS_NATIVE` as a preprocessor macro. This controls `#ifdef` blocks throughout the codebase to exclude wxWidgets code and include native alternatives.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│         SwiftUI / AppKit UI Layer               │
│   Views, ViewControllers, State Management      │
├─────────────────────────────────────────────────┤
│      XLEngineBridge (Objective-C++ bridge)       │
│   NSString ↔ std::string, NSDictionary ↔ map    │
├─────────────────────────────────────────────────┤
│      Native Providers (Obj-C++ / C++)           │
│   NativeEffectProvider, NativeModelProvider...   │
│   Implement I*Provider interfaces               │
├─────────────────────────────────────────────────┤
│      xlEngine C++ API                           │
│   EffectEngine, ModelEngine, RenderEngine...     │
│   Pure C++ — no wx types cross this boundary    │
├─────────────────────────────────────────────────┤
│      Existing C++ Engine                        │
│   Effects, Models, Outputs, Render Pipeline     │
│   RenderBuffer, PixelBuffer, SequenceData       │
└─────────────────────────────────────────────────┘
```

**Key principle**: No wxWidgets types cross the engine boundary. The engine uses `std::string`, `std::vector`, etc. The Obj-C++ bridge converts to `NSString`/`NSArray` at the UI boundary.

---

## Directory Map

### `xLights/native-mac/` — Native UI Layer

This is where all new native macOS code lives. **Work here, not in the legacy codebase.**

| Path | What's There |
|------|-------------|
| `main_native.mm` | App entry point (replaces wxWidgets main) |
| `XLAppDelegate.h` | App lifecycle |
| `XLMainWindowController.h/mm` | Main window coordinator |
| `XLDocument.h/mm` | NSDocument for .xlights files |
| `XLEngineBridge.h/mm` | **The bridge** — routes all engine calls between Swift/ObjC and C++ |
| `XLMainContentView.swift` | Main SwiftUI layout, tab switching, panel visibility |
| `EffectPropertiesView.swift` | SwiftUI effect property inspector |
| `EffectPaletteGridView.swift` | Effect type grid with drag-and-drop |
| `LayerBlendingView.swift` | Layer blending controls (SwiftUI) |
| `LayerSettingsView.swift` | Buffer/Roto-Zoom settings (SwiftUI) |
| `ColorPaletteView.swift` | Color palette panel |
| `XLCommandPalette.swift` | Command palette UI |
| `XLEffectPresetsWindowController.h/m` | Effect preset save/load panel (NSOutlineView, .xlpreset plist files) |
| `XLSymbolLibraryManager.h/m` | Symbol library CRUD + link/unlink effects (.xlsymbol plist files) |
| `XLKeyBindingsWindowController.h/m` | Keyboard shortcuts viewer (searchable NSTableView) |
| `XLFPPConnectWindowController.h/m` | FPP device discovery (Bonjour) and FSEQ upload |
| `XLScriptRunnerWindowController.h/m` | Lua/Python script loader with console output |
| `xLights-Bridging-Header.h` | Swift ↔ Obj-C bridging header |

#### `native-mac/sequencer/` — Timeline & Effects Grid

| File | Purpose |
|------|---------|
| `XLEffectsGridView.h/m` | Metal-backed effects timeline grid (the hardest component) |
| `XLEffectsGridRenderer.h/m` | Grid rendering logic |
| `XLTimelineRulerView.h/m` | Time markers above the grid |
| `XLWaveformView.h/m` | Audio waveform display |
| `XLRowHeadingsView.h/m` | Track names on the left |
| `XLScrollCoordinator.h/m` | Synchronized scrolling between all sequencer views |
| `XLTransportBarView.h/m` | Play/pause/stop controls |
| `XLAudioPlayer.h/m` | AVFoundation audio playback |
| `XLAudioLoader.h/m` | Audio file loading |
| `XLEffectDragController.h/m` | Effect drag-and-drop in timeline |
| `XLUndoController.h/m` | Undo/redo for sequencer actions |
| `XLStemManager.h/m` | Audio stem data management, import, serialize |
| `XLStemData.h/m` | Per-stem data model (name, color, audio, buckets) |
| `XLStemsContainerView.h/m` | Stems panel UI (header, row headers, waveforms, resize) |
| `XLMiniWaveformView.h/m` | Individual stem waveform renderer |

#### `native-mac/layout/` — 3D Preview & Model Editor

| File | Purpose |
|------|---------|
| `XLMetalPreviewView.h/m` | Metal-rendered 3D model preview |
| `XLCameraController.h/m` | 3D camera control |
| `XLManipulationHandlesRenderer.h/m` | Model transform gizmos |
| `XLModelTreeViewController.h/m` | Model hierarchy outline view |
| `XLModelPropertiesView.h/m` | Selected model inspector |

#### `native-mac/setup/` — Controller Configuration

| File | Purpose |
|------|---------|
| `XLControllersViewController.h/m` | Controller list and management |
| `XLControllerInspectorViewController.h/m` | Controller properties |
| `XLNetworkDiscoveryController.h/m` | Network scanning |
| `XLPortConfigurationView.h/m` | Port/channel assignment |

#### `native-mac/providers/` — Native Engine Implementations

These implement the C++ engine interfaces for standalone operation (no wxWidgets):

| File | Implements |
|------|-----------|
| `NativeEffectProvider.h/mm` | `IEffectProvider` — parses XML, manages elements/layers/effects |
| `NativeModelProvider.h/mm` | `IModelProvider` — loads models from show XML |
| `NativeSequenceProvider.h/mm` | `ISequenceProvider` — sequence metadata and playback state |
| `NativeOutputProvider.h/mm` | `IOutputProvider` — controller/output management |
| `NativeRenderProvider.h/mm` | `IRenderProvider` — render buffer access |

#### `native-mac/preferences/` — Settings Panels

`XLPreferencesWindowController` with 11 preference panes (sequence files, output, effects grid, view, color manager, keyboard, services, etc.)

#### `native-mac/dialogs/` — Dialog Windows

~30 dialog controllers including:

| File | Purpose |
|------|---------|
| `XLBaseSheetController.h/m` | Base class for modal sheet dialogs |
| `XLToolsDialogs.h/m` | Cleanup, package, download, prepare audio, generator placeholders |
| `XLConvertDialogs.h/m` | Sequence format conversion |
| `XLCheckSequenceReportWindow.h/m` | Sequence validation report |
| `XLNativeDialogs.h/m` | Common alert/prompt helpers |
| Plus ~20 more | Custom model, batch render, color picker, value curves, etc. |

---

### `xLights/engine/` — C++ Engine API

Pure C++ engine layer with no wxWidgets dependencies. Uses interface-based decoupling.

| Path | Purpose |
|------|---------|
| `EffectEngine.h/cpp` | Effect CRUD, parameter management, render-to-buffer |
| `ModelEngine.h/cpp` | Model management API |
| `OutputEngine.h/cpp` | Controller/output management API |
| `SequenceEngine.h/cpp` | Sequence load/save/play/pause/seek |
| `RenderEngine.h/cpp` | Frame rendering orchestration |
| `EngineTypes.h` | Common types (`OperationResult`, etc.) |

#### `engine/interfaces/` — Provider Interfaces

Abstract C++ interfaces that decouple engine from data sources:

| Interface | Purpose |
|-----------|---------|
| `IEffectProvider.h` | Effect data access (elements, layers, effects, undo) |
| `IModelProvider.h` | Model data access (names, properties, submodels) |
| `IOutputProvider.h` | Controller/output access |
| `IRenderProvider.h` | Render buffer and frame data access |
| `ISequenceProvider.h` | Sequence state and playback |

#### `engine/render/` — Native Render Pipeline

| File | Purpose |
|------|---------|
| `NativeRenderBuffer.h/cpp` | Per-effect pixel buffer (replaces wx-based RenderBuffer) |
| `NativePixelBuffer.h/cpp` | Multi-layer blending orchestrator (replaces PixelBufferClass) |
| `NativeRenderCoordinator.h/cpp` | Parallel per-model rendering with work-stealing |
| `NativeSequenceData.h/cpp` | Raw channel output storage (frame x channel array) |
| `NativeColorBlending.h/cpp` | 25+ color blending modes |
| `NativeDrawingContext.h/mm` | Metal drawing primitives for effects |
| `IRenderContext.h` | Abstract render context interface |

#### `engine/adapters/` — Legacy Wrappers

These wrap the existing wxWidgets code to implement the same interfaces, allowing gradual migration:

| Adapter | Wraps |
|---------|-------|
| `SequenceElementsAdapter` | `xLightsFrame` → `IEffectProvider` |
| `ModelManagerAdapter` | `ModelManager` → `IModelProvider` |
| `RenderContextAdapter` | Graphics context → `IRenderProvider` |
| `SequenceStateAdapter` | Sequence state → `ISequenceProvider` |

---

## The `#ifdef XLIGHTS_NATIVE` Pattern

This is the most important pattern in the codebase. Throughout the existing C++ files, you'll see:

```cpp
#ifdef XLIGHTS_NATIVE
    // Native build: use std:: types, no wx dependencies
    #include "engine/interfaces/IEffectProvider.h"
#else
    // Legacy build: uses wxWidgets
    #include "sequencer/Effect.h"
    #include "xLightsMain.h"
#endif
```

**Rules**:
- The native build (`xLights Native` scheme) defines `XLIGHTS_NATIVE`
- Code inside `#ifdef XLIGHTS_NATIVE` must have **zero wxWidgets dependencies**
- Code inside `#ifndef XLIGHTS_NATIVE` is legacy-only
- Code outside both guards is shared (must use only std:: types)

When modifying effect files or engine code, always check which `#ifdef` block you're in.

---

## Key Files You'll Touch Most Often

| When you need to... | Look at... |
|---------------------|-----------|
| Add a new engine API method | `XLEngineBridge.h/mm` + relevant `*Engine.h/cpp` |
| Change the main app layout | `XLMainContentView.swift` |
| Work on the sequencer timeline | `native-mac/sequencer/XLEffectsGridView.h/m` |
| Change effect property UI | `EffectPropertiesView.swift` |
| Fix a native build error in an effect | The effect's `.cpp` — check its `#ifdef` guards |
| Add a new provider method | The relevant `I*Provider.h` + `Native*Provider.mm` |
| Understand type mappings | `IEffectProvider.h` (`EffectInstanceInfo` ↔ `EffectInfo`) |

---

## Technology Stack

| Layer | Technology | When to use |
|-------|-----------|-------------|
| Standard UI (inspectors, settings, panels) | **Swift + SwiftUI** | Preferred for declarative UI |
| Complex views (timeline, 3D preview) | **Swift/ObjC + AppKit** | When SwiftUI lacks control fidelity |
| Bridge layer | **Objective-C++** | Interface between Swift/ObjC and C++ |
| Engine and rendering | **C++** | Existing engine, don't rewrite |
| GPU rendering | **Metal** | Preview, effects grid, waveform |

---

## Common Pitfalls

1. **Don't use the `xLights` scheme** — use `xLights Native`. The legacy scheme has pre-existing link errors (RenderEngine missing methods, unimplemented submodel methods).

2. **Forward declarations vs includes** — In the native build, many wx types are forward-declared but never included. If you get "incomplete type" errors, you probably need to include a header (like `UtilClasses.h` for `SettingsMap`).

3. **Duplicate symbols** — The native-mac providers and the engine render system both define classes in the `xlEngine` namespace. Be careful not to create name collisions.

4. **Effect `.cpp` files** — Many effect files have `#ifndef XLIGHTS_NATIVE` guards around their `Render()` method (since effects render through `NativeRenderBuffer` in native build). If you add code to an effect, make sure it's in the right `#ifdef` block.

5. **Timing mark labels** — Stored in XML `label` attribute (NOT `name`). See `SequenceElements.cpp:709-710`.

6. **Metal rendering** — For label/text rendering on the timeline, use the CALayer overlay approach (NSImage → layer.contents), NOT the bitmap→texture approach (has alpha blending issues).

7. **SwiftUI `NSViewRepresentable` weak references** — Views created by `NSViewRepresentable` can be deallocated and recreated by SwiftUI at any time (e.g., tab switches). **Never hold weak references to these views from outside SwiftUI** — they will silently become nil. Instead, store the view on `XLSwiftUIWindowHelper.shared` (a stable singleton) and look it up dynamically. This is the pattern used for `sidebarPreviewView` and `cachedSequencerViewController`.

8. **Optional chain silent assignment failure** — `obj.foo?.bar = value` silently does nothing if `foo` is nil. This caused `sidebarPreviewView` to never get wired up when `playbackController` was nil at `makeNSView` time. Always verify the full chain is non-nil, or use a singleton registry pattern instead.

9. **Metal layer-hosting view compositing** — `XLEffectsGridView` is a layer-hosting view (`self.layer = _metalLayer; self.wantsLayer = YES`). In Core Animation, layer-hosting views can composite above sibling views regardless of AppKit's subview ordering. This caused the transport bar (and any view below the grid) to be hidden behind the Metal layer. The fix requires three things working together:
   - **Clip container**: Wrap the grid in an `NSView` with `wantsLayer = YES` and `layer.masksToBounds = YES`. Constrain the container to stop at the transport bar's top anchor.
   - **Metal layer masksToBounds**: Set `_metalLayer.masksToBounds = YES` in `setFrameSize:` to prevent the drawable from rendering outside the view bounds.
   - **Explicit zPosition**: Set `_transportBar.layer.zPosition = 10` (and `_emptyStateView.layer.zPosition = 20`) in `viewDidLayout` so Core Animation composites them above the Metal layer.
   - **Do NOT manually set `_metalLayer.frame`** — AppKit manages this for layer-hosting views. Setting it to `(0, 0, w, h)` overrides the Auto Layout position and shifts the grid to the wrong location.
   - Re-apply `masksToBounds` in `viewDidLayout` since layer-backed views may replace their backing layer.

10. **Stack overflow in `loadView`** — `XLSequencerViewController.loadView` creates dozens of views, constraints, and subview hierarchies, consuming significant stack space. It then calls `reloadSequenceData` which calls further methods. Adding NSLog calls with `NSStringFromRect()` or other complex format specifiers to `reloadSequenceData` can increase the function's stack frame enough to cause `EXC_BAD_ACCESS (code=2)` — a stack overflow. If you need debug logging in this path, use `dispatch_async` to defer it off the `loadView` stack, or add it to `viewDidLayout` instead.

---

## Playback ↔ Sidebar Preview Coordination

During playback, `XLPlaybackController` renders full-sequence frames and sends pixel data to both the house preview and the sidebar model preview. The sidebar's `SidebarModelPreviewView.Coordinator` also has its own timer that loops the selected effect's animation when idle.

**Coordination mechanism**: Notification-based, NOT polling.

- `XLSequencerViewController` posts `XLPlaybackDidStartNotification` and `XLPlaybackDidStopNotification` from its playback delegate callbacks.
- The Coordinator observes these notifications:
  - On start → sets `playbackActive = true`, stops its own preview timer
  - On stop → sets `playbackActive = false`, restarts the effect loop timer
- `previewLoopTick()` has `guard !playbackActive` as a safety check.

**Sidebar view lookup**: `XLPlaybackController.sidebarPreviewView` is a `readonly` property with a `@dynamic` getter that reads from `XLSwiftUIWindowHelper.shared.sidebarPreviewView`. This ensures the playback controller always finds the current view, even if SwiftUI recreated it.

**Key files**:
| File | Role |
|------|------|
| `XLSequencerViewController.m` | Posts playback start/stop notifications |
| `XLMainContentView.swift` | Coordinator observes notifications, manages preview timer |
| `XLPlaybackController.h/m` | Dynamic getter for `sidebarPreviewView` via singleton |
| `XLSwiftWindowLauncher.swift` | `XLSwiftUIWindowHelper.sidebarPreviewView` storage |

---

## Inspector Layout Troubleshooting (Setup Tab)

If Setup inspector content is not full width, is centered, pins to bottom, or sections stretch when others collapse, use this pattern (mirrors Layout inspector behavior):

1. **Use a flipped stack as `NSScrollView.documentView` and size it manually**  
   In `xLights/native-mac/setup/XLControllerInspectorViewController.m`, use a flipped `NSStackView` document view and in `viewDidLayout` call `updateDocumentLayout`.

2. **Document sizing rule**  
   `updateDocumentLayout` should set:
   - width = `scrollView.contentView.bounds.width`
   - height = intrinsic content height only (sum of visible arranged subviews), **not** viewport height  
   This prevents collapsed sections from forcing other sections to expand vertically.

3. **Stack/row constraints and priorities**  
   - Keep stack distribution as `NSStackViewDistributionFill`
   - Set `detachesHiddenViews = YES` on the main stack and section content stacks
   - Set required vertical hugging/compression on section rows/content stacks so rows keep intrinsic heights
   - Constrain section content and rows leading/trailing to their parent stack for full-width behavior

4. **Disclosure toggle relayout signal**  
   In `xLights/native-mac/XLPropertyInspectorComponents.m`, `XLPropertySectionHeader` should post a notification (currently `XLPropertySectionDisclosureDidChange`) when sections expand/collapse.  
   In `XLControllerInspectorViewController`, observe that notification and call `updateDocumentLayout` on the next runloop (`dispatch_async(dispatch_get_main_queue(), ...)`).

5. **Do not pin content height to fill the viewport**  
   Avoid bottom constraints or sizing logic that makes document height track clip-view height. That causes “collapsed section -> other sections stretch” regressions.

---

## Delegate Wiring Pattern

The sequencer uses Cocoa delegation to connect UI events to business logic. This is the most common pattern you'll work with when adding new operations.

**Flow**: `XLEffectsGridView` (or `XLRowHeadingsView`) → delegate protocol → `XLSequencerViewController`

```
┌──────────────────────┐    delegate call    ┌────────────────────────────┐
│  XLEffectsGridView   │ ─────────────────→  │ XLSequencerViewController  │
│  (renders grid,      │                     │  (implements delegate,     │
│   handles mouse)     │                     │   calls engine bridge)     │
└──────────────────────┘                     └─────────┬──────────────────┘
                                                       │
                                               bridge call
                                                       ▼
                                             ┌──────────────────┐
                                             │  XLEngineBridge   │
                                             │  (Obj-C++ → C++) │
                                             └──────────────────┘
```

**Key delegate protocols**:
- `XLEffectsGridDelegate` — effect operations, timing ops, alignment, symbols (defined in `XLEffectsGridView.h`)
- `XLEffectsGridDataSource` — provides row/effect data for rendering
- `XLRowHeadingsDelegate` — row header interactions (layer management, track operations)

**Pragma mark sections in `XLSequencerViewController.m`**:
```
#pragma mark - XLEffectsGridDelegate                    (line ~1915)
#pragma mark - XLEffectsGridDelegate (Effect Operations) (line ~2185)
#pragma mark - XLEffectsGridDelegate (Timing Track Operations) (line ~2463)
#pragma mark - XLEffectsGridDelegate (Alignment Operations)    (line ~3122)
#pragma mark - XLEffectsGridDelegate (Symbol Library Operations) (line ~3503)
#pragma mark - XLRowHeadingsDelegate                    (line ~3647)
```

**Render index → effect ID mapping**: The grid view uses a flat C array of `XLEffectRenderInfo` structs for rendering. Delegate callbacks pass indices into this array. Use `[gridView effectIdAtRenderIndex:idx]` to get the real engine effect ID before calling bridge methods.

---

## Undo System

The native undo system uses `XLUndoController` (wraps `NSUndoManager`).

**Pattern for undoable operations**:
```objc
[_undoController beginUndoGroupingWithActionName:@"Move Effects"];

for (/* each effect */) {
    XLEffectSnapshot snapshot;
    snapshot.effectID = effectId;
    snapshot.startTimeMS = origStart;
    snapshot.endTimeMS = origEnd;
    // ... fill other fields
    [_undoController captureEffectToBeMoved:snapshot actionName:@"Move Effects"];

    [_engineBridge moveEffect:effectId startTimeMS:newStart endTimeMS:newEnd];
}

[_undoController endUndoGrouping];
```

Key types:
- `XLEffectSnapshot` — plain C struct (no ObjC pointers) capturing effect state for undo
- `XLUndoActionType` — enum matching legacy `UNDO_ACTIONS`

---

## Sequencer Data Model

The sequencer uses C-array structures for performance:

```objc
// XLSequencerViewController.m
XLRowEntry* _rowData;       // Array of track metadata
XLEffectEntry* _effectData; // Array of all effects
```

- Effects are linked to rows via `elementIndex` (stable across reordering)
- Timing tracks always sort to the top
- Elements with multiple layers can expand to show individual layer rows
- When collapsed, all layers' effects are shown overlaid

---

## Timing Mark Bridge API

Timing marks are effects on timing track elements. The bridge provides these key methods:

```objc
// Read marks on a specific layer (0=phrases, 1=words, 2=phonemes for lyric tracks)
NSArray<NSDictionary *> *marks = [bridge getTimingMarks:@"Timing 1" layer:0];
// Each dict: { @"id": effectId, @"startTimeMS": ms, @"endTimeMS": ms, @"label": text }

// Get all timing mark positions for snap-to-grid (active track only)
NSArray<NSNumber *> *snapTimes = [bridge getActiveTimingMarkTimes];

// CRUD operations
[bridge createTimingMark:@"Timing 1" layer:0 startTimeMS:1000 endTimeMS:2000 label:@"hello"];
[bridge setTimingMarkLabel:markId label:@"new label"];
[bridge moveTimingMark:markId startTimeMS:1000 endTimeMS:1500];
[bridge deleteTimingMark:markId];

// Track-level operations
[bridge createTimingTrack:@"New Track"];
[bridge deleteTimingTrack:@"Old Track"];
[bridge importTimingTrack:@"Imported" fromSequence:@"/path/to/file.xml" asTrackName:@"Imported"];

// Phoneme dictionary lookup (for word→phoneme breakdown)
NSArray<NSString *> *phonemes = [bridge getPhonemesForWord:@"hello"];
```

---

## State Management

- **Swift**: `@Observable` classes (`EffectSelectionState`, `XLAppState`, `LayerBlendingState`)
- **Cross-subsystem**: `NSNotification` (`XLEffectSelectionDidChangeNotification`, etc.)
- **C++ engine**: Callback/listener interfaces (`EffectEngineListener`, `RenderCoordinatorListener`)

---

## Adding New Effect Properties to the Renderer

When you need to surface a new effect setting as a visual indicator on the grid (e.g., fade ramps, layer mode badges), follow this data pipeline:

```
XML settings (key=value strings in EffectDB)
    → NativeEffectProvider::buildEffectInfo() copies to EffectInstanceInfo.settings map
    → XLEngineBridge::getEffectsForElementAtIndex:layer: extracts and converts to NSDictionary
    → XLSequencerViewController stores in XLEffectEntry (plain C struct)
    → effectInfoForRow:atIndex: copies to XLEffectRenderInfo (plain C struct)
    → XLEffectsGridRenderer draws using Metal
```

**Steps to add a new property**:
1. Add field(s) to `XLEffectRenderInfo` in `XLEffectsGridRenderer.h` (plain C types only)
2. Add matching field(s) to `XLEffectEntry` in `XLSequencerViewController.m`
3. Extract value from `eff.settings` in `XLEngineBridge.mm` `getEffectsForElementAtIndex:layer:` and include in returned dictionary
4. Read from dictionary and store in `XLEffectEntry` during data loading in `XLSequencerViewController.m`
5. Copy from `XLEffectEntry` to `XLEffectRenderInfo` in `effectInfoForRow:atIndex:`
6. Use the value in `XLEffectsGridRenderer.m` drawing methods

**Effect settings key conventions**: Keys like `T_TEXTCTRL_Fadein` follow wxWidgets naming — `T_` = transition setting, `TEXTCTRL` = text control, `CHOICE_` = dropdown. Values are strings (e.g., fade values are seconds as floats like `"0.50"`). The settings map is `std::map<std::string, std::string>`.

---

## Metal Renderer Architecture

The effects grid renderer (`XLEffectsGridRenderer.m`) uses these patterns:

**Triple-buffered vertex data**: Grid lines, effect blocks, outlines, and icons use pre-allocated Metal buffers rotated across 3 frames. This prevents CPU/GPU race conditions during scrolling — while the GPU renders frame N, the CPU writes to frame N+1.

**Pipeline types**:
- `_linePipeline` — Simple colored vertices (`SimpleVertex`). Used for grid lines, playback indicator, fade overlays, rubber band.
- `_effectBlockPipeline` — SDF rounded rectangles (`RoundedRectVertex`). Used for effect block fills with smooth corners.
- `_outlinePipeline` — Same vertex format as effect blocks but with outline-only fragment shader. Used for selection highlights.
- `_iconPipeline` — Textured quads (`TexturedVertex`). Used for effect type icons from a pre-built texture atlas.

**Adding new overlays**: For occasional/sparse overlays (like fade ramp triangles), use per-frame allocated buffers with `_linePipeline` rather than adding to the triple-buffered pools. Draw after effect blocks but before selection outlines.

**Plain C struct rule**: `XLEffectRenderInfo` must NOT contain ObjC object pointers (`NSColor *`, `NSString *`, etc.) because it's stored via `valueWithBytes:objCType:` which bypasses ARC. Use `char[]` arrays, `uint32_t` for colors, and `CGFloat` for values.

**Frustum culling**: All draw methods skip effects outside the visible region (time range + row range). Always include this check when adding new drawing passes.

---

## Toolbar Architecture

**The toolbar is SwiftUI, NOT NSToolbar.** The visible toolbar is defined in `XLMainContentView.swift` inside the `toolbarContent` computed property using SwiftUI's `.toolbar { }` modifier. `XLMainWindowController.mm` also creates an NSToolbar with similar items, but **the SwiftUI toolbar takes precedence** and is what the user actually sees.

**Layout** (left to right):

| Placement | Items |
|-----------|-------|
| `.principal` (center) | Go to Beginning, Play, Pause, Stop, Render (progress ring) |
| `.primaryAction` (right) | Command Palette, Palettes (top panel toggle), House Preview, Inspector |

**Render button**: Uses `RenderProgressRing` (SwiftUI view in same file) — shows a palette icon (`paintpalette.fill`) when idle, an animated spinning ring during indeterminate render, or a filling arc for determinate progress. Progress is polled at 100ms intervals via `RenderProgressPoller` modifier which reads `engineBridge.isRendering()` and `engineBridge.getRenderProgress()` into `XLAppState.isRendering` / `.renderProgress`.

**To modify toolbar items**: Edit the `toolbarContent` property in `XLMainContentView.swift` (~line 425). Do NOT edit the NSToolbar setup in `XLMainWindowController.mm` — those items are not displayed.

### Toolbar Toggle Buttons with Active/Inactive Color

Toolbar buttons that represent toggleable state (snap on/off, inspector visible/hidden, etc.) use `ToolbarToggleButtonStyle` to show blue when active and gray when inactive.

**Gotcha — `.tint()` does NOT work on macOS toolbar buttons.** SwiftUI's `.tint(.accentColor)` modifier has no effect on toolbar button icons on macOS. Neither does wrapping in a `Toggle` — the icon color doesn't change. The only reliable approach is a custom `ButtonStyle` that sets `.foregroundColor()` on `configuration.label`.

**The pattern** (defined in `XLMainContentView.swift`):

```swift
struct ToolbarToggleButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isActive ? .accentColor : .secondary)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}
```

This mirrors `TabToolbarButtonStyle` (used for the tab bar buttons on the left side of the toolbar) which uses the same `.foregroundColor(isSelected ? .accentColor : .secondary)` approach.

**Usage** — use a `Button` (NOT `Toggle`) with this style:

```swift
Button {
    appState.toggleSnap()
} label: {
    Label("Snap", systemImage: "dot.scope")
}
.buttonStyle(ToolbarToggleButtonStyle(isActive: appState.snapEnabled))
.help("Snap to Grid/Timing Marks (K)")
```

**Adding a new toggle button**:
1. Add a `Bool` property to `XLAppState` in `XLMainContentView.swift`
2. Add persistence in `loadState()` / `saveState()` if needed
3. Add the `Button` in the `toolbarContent` property with `ToolbarToggleButtonStyle`
4. If the state needs to be accessible from ObjC, add a bridge method in `XLSwiftUIWindowHelper` (`XLSwiftWindowLauncher.swift`)

### Global Keyboard Shortcuts (Without Grid Focus)

Menu items with key equivalents only trigger their action if the action's handler is somewhere in the **responder chain**. If a handler only exists on `XLSequencerViewController`, the shortcut only works when focus is inside the sequencer hierarchy.

**The fix**: Place the action handler on `XLAppDelegate`, which is always in the responder chain regardless of which view has focus.

**Pattern** (in `XLAppDelegate.m`):

```objc
- (IBAction)toggleSnapToGrid:(id)sender {
    // Forward to the sequencer VC via the shared helper reference
    XLSequencerViewController *vc = [XLSwiftUIWindowHelper shared].sequencerViewController;
    if (vc) {
        [vc toggleSnapToGrid:sender];
        return;
    }
    // Fallback: find sequencer VC through window controllers
    for (NSWindow *window in [NSApp windows]) {
        NSWindowController *wc = window.windowController;
        if ([wc isKindOfClass:[XLMainWindowController class]]) {
            XLMainWindowController *mainController = (XLMainWindowController *)wc;
            [mainController.sequencerViewController toggleSnapToGrid:sender];
            return;
        }
    }
}
```

**For menu item checkmarks** — implement `validateMenuItem:` on `XLAppDelegate` too:

```objc
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(toggleSnapToGrid:)) {
        BOOL snapOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"SnapToTiming"];
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"SnapToTiming"] == nil) {
            snapOn = YES; // Default to on if key never set
        }
        menuItem.state = snapOn ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    return YES;
}
```

**Menu item setup** (in `XLToolbarExtensions.mm`) — use `keyEquivalentModifierMask = 0` for plain key shortcuts without Cmd:

```objc
NSMenuItem *snapItem = [viewMenu addItemWithTitle:@"Snap to Grid"
                                           action:@selector(toggleSnapToGrid:)
                                    keyEquivalent:@"k"];
snapItem.keyEquivalentModifierMask = 0; // Plain "K" key, no Cmd modifier
```

**Adding a new global shortcut**:
1. Add the menu item in `XLToolbarExtensions.mm` with `keyEquivalent` and `keyEquivalentModifierMask`
2. Add the `IBAction` handler on `XLAppDelegate.m` (forwards to the appropriate VC)
3. Add `validateMenuItem:` handling on `XLAppDelegate.m` for checkmark state
4. Add a keyboard binding in `preferences/XLKeyboardPreferencesViewController.m`
5. The actual logic lives on the VC (e.g., `XLSequencerViewController`) — the app delegate just forwards

### Tracking Window Visibility for Toolbar Button State

When a toolbar button opens/closes a separate window (like House Preview), the button state must update even if the user closes the window manually via the title bar X button.

**Problem**: Programmatic close (`orderOut:`) goes through your toggle method, but the user clicking the window's close button does not. The toolbar button stays in the "active" state even though the window is gone.

**The fix**: Observe `NSWindowWillCloseNotification` on the window and update the toolbar state in the observer.

**Pattern** (in `XLSequencerViewController.m`):

```objc
// When creating/showing the window for the first time, register for close notification:
[[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(handleHousePreviewWindowDidClose:)
                                             name:NSWindowWillCloseNotification
                                           object:_housePreviewController.window];

// Observer method:
- (void)handleHousePreviewWindowDidClose:(NSNotification *)note {
    [[XLSwiftUIWindowHelper shared] setHousePreviewVisible:NO];
}
```

The bridge method `setHousePreviewVisible:` updates `XLAppState.housePreviewVisible`, which drives the `ToolbarToggleButtonStyle` color.

**Adding a new window-tracking toggle button**:
1. Add a `Bool` property to `XLAppState` (e.g., `housePreviewVisible`)
2. Add a bridge method to `XLSwiftUIWindowHelper` (e.g., `setHousePreviewVisible:`)
3. In the toggle method that shows/hides the window, call the bridge method for both states
4. Register `NSWindowWillCloseNotification` observer on the window after first creation
5. In the observer callback, call the bridge method to set state to `NO`

**Gotcha — `boolForKey:` returns NO for missing keys**: If your toggle defaults to YES (like snap), `boolForKey:` returns NO for a key that was never set. Check with `objectForKey:` first:

```objc
if ([[NSUserDefaults standardUserDefaults] objectForKey:@"SnapToTiming"] != nil) {
    _gridView.snapToTimingMarks = [[NSUserDefaults standardUserDefaults] boolForKey:@"SnapToTiming"];
} else {
    _gridView.snapToTimingMarks = YES; // Default
}
```

---

## What's Working vs TODO

**Working**:
- App shell, tab navigation, main menu bar with all items wired
- Sequencer timeline with Metal rendering, effects grid with drag-drop
- Row headings with full context menus (layer management, track operations)
- Waveform view, timing marks, effect selection
- Effect properties inspector, layer blending UI, color palette
- Transport controls, audio playback with volume/speed control
- Context menus: effects grid, row headings, layout preview, waveform, timeline ruler
- Effect operations: lock/unlock, render-disable, reset-to-defaults, clipboard (copy/cut/paste/delete)
- All 9 alignment operations (start/end/both/center/duration/shift/timing-mark/close-gap)
- Timing mark operations: breakdown phrase→words→phonemes, divide, auto-label, shimmer, alternating phonemes, find/replace
- Effect presets panel (save/load .xlpreset files)
- Symbol library (create/link/unlink symbols)
- Key bindings viewer, FPP connect, script runner
- Audio stems panel (import, reorder, rename/color, height slider, collapse/expand, cursor sync, click-to-seek, persistence)
- Tools dialogs (cleanup, package, download, prepare audio)
- Settings/preferences, batch render, check sequence, file operations

**Major TODOs**:
- Wiring SwiftUI panel state to C++ engine (blending, buffer settings panels are UI-only)
- Submodel/strand expand-collapse
- Full render pipeline integration (NativePixelBuffer, NativeRenderBuffer)
- Controller setup tab
- 3D layout preview improvements
- Guard wx includes in Color.h and ValueCurve for native build
- Replace wx file utilities with native equivalents
- Audit and clean wx dependencies from Model and Effect classes

---

## Layout Preview: Model/Group Selection & Pixel Highlighting

### How Selection Works

When a model is selected in the layout tab (either from the tree or by clicking in the preview), its pixels render as **pure white** in the Metal preview. This matches the legacy wxWidgets behavior (which uses yellow, but white works better on the dark Metal background).

**Selection flow**: Tree click or preview click → `XLLayoutViewController` coordinates → `XLMetalPreviewView.selectModel:` or `selectModels:` → sets `_modelVerticesDirty = YES` → render loop rebuilds vertex buffer with white colors for selected nodes.

**Key detail**: Setting `_modelVerticesDirty` alone does nothing — the render loop in the `renderFrame` method must check this flag and call `buildModelVertices` before drawing. Without this check, the vertex buffer retains stale colors.

**Gotcha — always use `selectModel:`, never set `selectedModelName` directly**: `XLMetalPreviewView.selectModel:` updates `_selectedModelNamesSet`, `_selectedSubmodelNodeIndices`, and sets `_modelVerticesDirty`. Setting `_previewView.selectedModelName = ...` directly bypasses all of this — the selection set won't update, vertices won't rebuild, and pixels won't turn white. Similarly, `clearModelSelection` must set `_modelVerticesDirty = YES` or old white pixels persist after deselection.

### Group Selection

Clicking a group in the model tree selects all member models in the preview and shows group properties in the inspector.

**Data flow**: `XLModelTreeViewController` detects group click via `selectedItemIsGroup` → `XLLayoutViewController.selectGroup:` → builds group lookup from `getModelGroups` → recursively resolves members → passes individual model names to `XLMetalPreviewView.selectModels:`.

**Recursive group resolution**: Groups can contain other groups (e.g., "All" contains "Yard Props" which contains individual models). `resolveGroupMembers:lookup:into:` in `XLLayoutViewController.m` recursively expands nested groups into individual model names.

**Gotcha — `getModelGroup:` (singular) is broken**: The singular lookup method returns nil because `NativeModelProvider` didn't originally store group XML attributes. The workaround uses `getModelGroups` (plural) which returns all groups with their attributes, then filters by name. The root cause was fixed in `NativeModelProvider.mm` — the XML parser now stores ALL `<modelGroup>` attributes (including the `models` member list) into `_groupAttributes`.

### Submodel Selection

Groups can contain submodel references like `"SingingFace/Mouth"`. When selected:
- The **base model** ("SingingFace") gets added to the selection set for bounding box rendering
- The submodel's **specific node indices** are resolved from its strand range definitions
- Only those nodes render white — the rest of the parent model stays at its normal color

**Node index resolution**: `XLEngineBridge.getSubmodelNodeIndices:submodelName:` calls `getSubmodelDefinition:` to get strand ranges (e.g., `["1-10,15,20-25"]`), parses the comma-separated ranges, and converts from 1-based to 0-based indices, returning an `NSIndexSet`.

**In the vertex builder** (`buildModelVerticesWithEffectColors:`):
- `_selectedSubmodelNodeIndices` maps base model name → `NSIndexSet` of selected node indices
- If a model has submodel indices, only those specific nodes get white; otherwise all nodes get white
- This dictionary is populated in `selectModels:` when it encounters names containing "/"

### Re-entrant Selection Prevention

Selecting models in the preview triggers delegate callbacks (`previewView:didSelectModels:`) which would try to sync the tree and post notifications, causing loops. The `_suppressPreviewDelegate` flag in `XLLayoutViewController` prevents this during programmatic selection (e.g., when `selectGroup:` calls `selectModels:` on the preview).

### Tree ↔ Preview Sync

`selectModel:syncTree:` has a `syncTree` parameter. When selection originates from the tree, pass `NO` to avoid scrolling the tree to the first occurrence of the model inside a group (which would be confusing if the user clicked the model at the root level).

### Metal Buffer Limit

When many models are selected (17+), the multi-selection bounding box vertex data can exceed Metal's 4096-byte `setVertexBytes:` limit. `renderMultiSelectionBoundsWithEncoder:` checks the data size and uses `newBufferWithBytes:` for larger payloads.

### Key Files

| File | Role |
|------|------|
| `XLLayoutViewController.m` | Coordinates tree ↔ preview ↔ inspector, group selection logic |
| `XLMetalPreviewView.m` | Metal rendering, white pixel selection, submodel node tracking |
| `XLModelTreeViewController.m` | Tree view, group/submodel node hierarchy |
| `XLInspectorViewController.m` | Shows group properties when group selected |
| `NativeModelProvider.mm` | Parses group XML attributes (including `models` member list) |
| `XLEngineBridge.h/mm` | `getSubmodelNodeIndices:submodelName:` for submodel node resolution |

---

## Value Curves: Parameter Scaling (MINVOID/MAXVOID)

Value curves animate effect parameters over time. The C++ `ValueCurve` class uses a `Normalise()` function that converts raw parameter values to a 0-100 internal scale before generating curve points. **The conversion depends on `GetRangeParm{N}()` for each curve type.**

### The Two Parameter Ranges

Each curve type's parameters have defined ranges via `GetRangeParm1()` through `GetRangeParm4()` in `ValueCurve.cpp`:

- **Fixed range (0-100)**: Parameters where `GetRangeParm` has no special case for the curve type. `Normalise()` is a no-op — the raw value IS the 0-100 value.
- **MINVOID/MAXVOID range**: Parameters where `GetRangeParm` returns `MINVOID`/`MAXVOID`. `Normalise()` uses the curve's `_min`/`_max` (the effect parameter's actual range, e.g., 0-500 for Bars_Cycles) to scale: `normalized = (value - _min) * 100 / (_max - _min)`.

### The Native UI Scaling Problem

The native UI (`XLValueCurveWindow.m`) stores all parameters internally on a 0-1 scale (slider position), displayed as 0-100. **But for MINVOID/MAXVOID parameters, the C++ expects values on the real `_min/_max` scale** (e.g., 0-500), not 0-100.

If you serialize a MINVOID parameter as `P2=100.00` when _min=0, _max=500, the C++ `Normalise()` computes `(100-0)*100/500 = 20` — a tiny normalized value instead of the intended 100. This causes curve points to clamp to 0 via `Safe01()`.

### The Fix: Bidirectional Scaling in XLValueCurveWindow.m

`paramNeedsRealScale:forType:` identifies which parameters need scaling per curve type. Example: Sine P2 (amplitude) and P4 (center) need scaling; P1 (phase) and P3 (cycles) don't.

- **Output** (`curveDataString`): Before serialization, scale MINVOID params from 0-100 to real range: `p = p * range / 100 + min`
- **Input** (`parseKeyValueCurveData:`): After parsing, reverse-scale MINVOID params back to 0-100: `p = (p - min) * 100 / range`

### Serialization Format

Value curve strings look like: `Active=TRUE|Id=ValueCurve|Type=Sine|Min=0.00|Max=500.00|P2=500.00|P3=27.86|P4=125.00|RV=TRUE|`

Critical fields:
- `Id=ValueCurve` — **must be present** or `IsOk()` returns false and the curve is silently ignored
- `Active=TRUE` — required for `IsActive()` to return true
- `Min`/`Max` — the effect parameter's range (e.g., 0-500 for Bars_Cycles)
- `RV=TRUE` — indicates "real values" mode (parameters stored on _min/_max scale for MINVOID params)
- `P1`-`P4` — parameter values (MINVOID params on real scale, fixed params on 0-100 scale)

### Reference: Which Parameters Need Scaling

From `GetRangeParm{N}()` in `ValueCurve.cpp` — parameters returning MINVOID/MAXVOID:

| Curve Type | P1 | P2 | P3 | P4 |
|------------|----|----|----|----|
| Flat | MINVOID | - | - | - |
| Ramp | MINVOID | MINVOID | - | - |
| Ramp Up/Down | MINVOID | MINVOID | - | - |
| Ramp Up/Down Hold | MINVOID | MINVOID | - | - |
| Saw Tooth | MINVOID | MINVOID | - | - |
| Square | MINVOID | MINVOID | - | - |
| Random | MINVOID | MINVOID | - | - |
| Sine | fixed | MINVOID | fixed | MINVOID |
| Abs Sine | fixed | MINVOID | fixed | MINVOID |
| Parabolic Up/Down | fixed | MINVOID | - | - |
| Logarithmic Up/Down | fixed | MINVOID | - | - |
| Exponential Up/Down | fixed | MINVOID | - | - |
| Custom | - | - | - | - |

### Key Files

| File | Role |
|------|------|
| `ValueCurve.cpp` | `Normalise()`, `GetRangeParm{1-4}()`, `RenderType()`, `Deserialise()` |
| `XLValueCurveWindow.m` | `paramNeedsRealScale:forType:`, `curveDataString`, `parseKeyValueCurveData:` |
| `NativeRenderCoordinator.cpp` | `getIntWithVC()`, `getDoubleWithVC()` — evaluate VCs during rendering |

---

## Audio Stems Panel

The stems panel displays separated audio tracks (vocals, drums, bass, etc.) as individual waveforms below the main waveform view. It supports import, reorder, rename, color customization, and persists with the sequence.

### Architecture

```
XLSequencerViewController
  ├── _stemManager (XLStemManager)     — data model, import, serialize
  └── _stemsContainerView              — UI container
        ├── Header bar (collapse/expand, title, height slider, import button)
        ├── Row headers (XLStemRowHeaderView) — drag-reorder, double-click edit
        ├── Scroll view with XLMiniWaveformView per stem
        └── Resize handle (2pt bar, blue on hover)
```

**Scroll/zoom sync**: The stems container is wired into `XLScrollCoordinator` like all other sequencer views. The coordinator calls `setScrollOffsetX:` and `setZoomLevel:` on the container, which forwards to all mini waveforms.

**Cursor sync**: Mouse hover cursor position is synchronized across all sequencer views:
- Grid cursor → waveform + stems (via `effectsGrid:didMoveCursorToTimeMS:`)
- Waveform cursor → stems (via `waveformView:didMoveCursorToTimeMS:`)
- Stems cursor → waveform (via `stemsContainer:didMoveCursorToTimeMS:`)

**Click-to-seek**: Clicking anywhere in the stems waveform area seeks the playhead, same as clicking the main waveform. Uses the same delegate pattern: `stemsContainer:didSeekToTimeMS:` → `XLSequencerViewController` → `playbackController seekToPositionMS:`.

### Data Model

`XLStemData` holds per-stem state: name, file path (absolute + relative), waveform color, loaded PCM audio data, pre-computed overview buckets, duration.

`XLStemManager` manages the stem array:
- **Import**: `importStemFiles:completion:` / `importStemsFromFolder:completion:` — loads audio on background queue, generates waveform buckets
- **Reorder**: `moveStemAtIndex:toIndex:`
- **Edit**: `updateStemAtIndex:name:color:`
- **Serialize**: `serializeToDicts` / `restoreFromDicts:` — array of `{name, relativePath, color}` dictionaries
- Posts `XLStemManagerDidChangeNotification` on any change → container calls `reloadStems`

**Persistence**: Stems are saved as an array of dictionaries in the sequence XML via `XLEngineBridge`. On sequence load, `XLSequencerViewController` calls `restoreFromDicts:` which resolves relative paths against the show folder and loads audio in the background.

### UI Details

**Header bar** (`kStemsHeaderHeight = 22pt`):
- Chevron button toggles collapse/expand
- Click on header text/empty space also toggles (NSClickGestureRecognizer)
- Height slider (16–80pt range) controls individual stem row height
- Plus button imports stems (shows border on hover via `showsBorderOnlyWhileMouseInside`)

**Stem row headers** (`XLStemRowHeaderView`):
- Color indicator bar on left edge
- Truncated stem name label in stem's color
- Drag-to-reorder: mouseDown records start, mouseDragged shows blue insertion indicator, mouseUp commits reorder
- Double-click opens edit dialog (NSAlert with NSTextField + NSColorWell)

**Mini waveforms** (`XLMiniWaveformView`):
- Cached bitmap rendering at Retina resolution (same approach as main waveform)
- Multi-resolution: raw PCM samples at high zoom, overview buckets at low zoom
- Draws cursor line (white, 60% alpha), then playhead (red)
- No direct mouse handling — the container handles tracking and forwards cursor/seek

**Resize handle** (`XLStemsResizeHandle`):
- 2pt height, matches panel dividers elsewhere in the app
- Uses `resetCursorRects` for resize cursor (reliable, window-managed)
- Tracking area for blue highlight on hover (`controlAccentColor` at 50% alpha)
- Delta-based drag: each `mouseDragged:` computes incremental delta from `_lastY`, avoiding the snap-back bug that occurs with absolute-position tracking when `currentHeight` returns a stale cached value

**Scroll views**: The stems area uses two synchronized scroll views — `XLVerticalOnlyScrollView` for waveforms (right side) and a plain NSScrollView for row headers (left side). Vertical scroll syncs between them via `NSViewBoundsDidChangeNotification`. Horizontal scroll and zoom are forwarded to the scroll coordinator (not handled by the scroll views).

### Key Files

| File | Role |
|------|------|
| `sequencer/XLStemData.h/m` | Per-stem data model |
| `sequencer/XLStemManager.h/m` | Stem collection management, import, serialize |
| `sequencer/XLStemsContainerView.h/m` | Container UI: header, row headers, waveforms, resize handle, mouse tracking |
| `sequencer/XLMiniWaveformView.h/m` | Individual stem waveform renderer (cached bitmap, cursor/playhead overlay) |
| `XLSequencerViewController.m` | Wires stems to scroll coordinator, playback, and persistence |

### Common Pitfalls

1. **Resize handle snap-back**: The resize handle must use delta-based dragging (track `_lastY`, compute per-frame delta) and call `setExpandedHeight:` on the container to keep `_savedExpandedHeight` in sync. Using absolute-position tracking (`startHeight + totalDelta`) breaks because `currentHeight` returns the stale saved value on re-grab.

2. **Cursor stuck as resize cursor**: Don't use `NSCursor.push()`/`pop()` for resize cursor — if `mouseExited` doesn't fire (common when moving between sibling views), the cursor gets stuck. Use `resetCursorRects` instead (window-managed, automatic cleanup).

---

## Song Structure Regions

The song structure regions feature lets users divide a sequence into named, colored sections (e.g., "Intro", "Verse 1", "Chorus") displayed as semi-transparent colored bands in the timeline ruler. This is a boundary-based model: users add boundaries that split the timeline into regions, rather than creating regions directly.

### Architecture

**Boundary model** (in `NativeEffectProvider`): The C++ layer stores a list of `SongStructureRegion` structs. Adding a boundary splits the containing region in two. Deleting a boundary merges the two adjacent regions (keeping the left region's name/color). If only one region remains after a delete, the song structure is cleared entirely.

**Data flow**: `NativeEffectProvider` (C++ data) → `XLEngineBridge` (Obj-C++ bridge) → `XLSequencerViewController` (delegate) → `XLTimelineRulerView` (rendering).

**Struct types**:
- C++ side: `SongStructureRegion` — `int64_t regionId`, `int startTimeMS`, `int endTimeMS`, `std::string name`, `uint32_t colorARGB`
- Ruler side: `XLSongRegion` (plain C struct) — `NSInteger regionId`, `NSInteger startTimeMS/endTimeMS`, `CGFloat colorR/G/B/A`, `char name[128]`. Plain C for Metal/CALayer compatibility.
- Conversion happens in `XLSequencerViewController.reloadSongRegionsForRuler` which fetches NSDictionary arrays from the bridge and packs them into the C struct array.

### Interaction

- **Add boundary**: Context menu → "Add Boundary Here", or Option+click on ruler. Delegate calls `addSongStructureBoundaryAtTimeMS:` on the bridge, which splits the region at that time. First boundary ever added creates two regions spanning the full sequence.
- **Drag boundary**: 6pt hit-testing handle on each boundary line. Drag calls `moveSongStructureBoundary:toTimeMS:` on the bridge.
- **Delete boundary**: Context menu → "Delete Boundary" or Delete key when a boundary is selected. Calls `deleteSongStructureBoundary:`.
- **Edit region**: Context menu → "Edit Region..." shows `XLSongRegionEditPopover` (transient NSPopover with name text field + NSColorWell). On confirm, calls `setSongStructureRegion:name:colorARGB:`.
- **Clear all**: Context menu → "Clear Song Structure" calls `clearSongStructure`.
- **Select region**: Click on a region band calls `didSelectSongRegionId:`.

### Rendering

Song regions are drawn on a dedicated `CALayer` (zPosition 50) inside the ruler view. Each region renders as a semi-transparent color band behind the tick marks and timing marks. Region names are drawn as centered white text labels. Boundary lines render as thin vertical lines between regions.

### Color Palette

When a boundary creates a new region, the engine assigns colors from an 8-color palette (all at `0x40` alpha for semi-transparency): blue, green, orange, purple, teal, red, slate, amber. Colors cycle through the palette based on region count.

### Persistence

Song structure is saved in the sequence XML as:
```xml
<SongStructure>
  <Region startTimeMS="0" endTimeMS="15000" name="Intro" color="402196F3"/>
  <Region startTimeMS="15000" endTimeMS="45000" name="Verse 1" color="404CAF50"/>
</SongStructure>
```

The `color` attribute is ARGB hex (alpha first). Loaded/saved via `NativeEffectProvider` methods `loadSongStructure` / `saveSongStructure` called during sequence open/save.

### Key Files

| File | Role |
|------|------|
| `sequencer/XLTimelineRulerView.h/m` | Rendering (CALayer), hit testing, boundary drag, context menu |
| `XLSongRegionEditPopover.h/m` | NSPopover for editing region name and color |
| `XLSequencerViewController.m` | Delegate wiring, `reloadSongRegionsForRuler` conversion |
| `XLEngineBridge.h/mm` | Bridge API: `getSongStructureRegions`, `addSongStructureBoundaryAtTimeMS:`, `moveSongStructureBoundary:toTimeMS:`, `deleteSongStructureBoundary:`, `setSongStructureRegion:name:colorARGB:`, `clearSongStructure` |
| `providers/NativeEffectProvider.h/mm` | C++ data model, boundary split/merge logic, XML persistence |

3. **Mouse tracking ownership**: The tracking area on the stems scroll view has `owner:self` (the container), so `mouseMoved:`/`mouseExited:` go to the container, which forwards cursor position to all mini waveforms. The mini waveforms themselves have no mouse handling.

---

## Audio Playback System

### Architecture

The audio system uses **AVAudioEngine + AVAudioPlayerNode** (Apple's professional audio framework). There is no need for AudioKit — it's just a Swift wrapper around the same AVAudioEngine we already use. The issues we've hit are in the orchestration layer, not the audio framework.

```
XLPlaybackController          — Single source of truth for play/stop/pause/seek
  ├── XLAudioPlayer            — AVAudioEngine + AVAudioPlayerNode wrapper
  │     ├── _audioEngine        — AVAudioEngine
  │     ├── _playerNode         — AVAudioPlayerNode (schedules PCM buffers)
  │     └── _audioBuffer        — Full PCM data loaded from file
  └── XLEngineBridge           — C++ engine play/stop/seek (effects rendering)
```

### Critical Rule: XLPlaybackController Is the Single Source of Truth

There are **three code paths** that trigger play/stop:

| Trigger | Path |
|---------|------|
| Spacebar / menu items | `XLMainWindowController.playSequence:` → `[_playbackController play]` |
| Transport bar buttons | `transportBarView:didClickPlayPause:` → `[_playbackController togglePlayPause]` |
| SwiftUI toolbar buttons | `seqVC.play()` / `seqVC.stop()` → `[_playbackController play/stop]` |

**All paths MUST delegate to `XLPlaybackController`**. Never call `[_engineBridge play/stop/seek:]` directly from view controllers — that creates conflicting state between the audio player and the engine.

### Spacebar = Toggle (Pause), Not Stop

The keyboard handler maps spacebar to `TOGGLE_PLAY` action, which calls `[_playbackController togglePlayPause]`. This **pauses** (not stops) the playback. The period key (`.`) maps to `stopSequence:` which actually stops. This distinction matters because paused vs stopped state affects buffer queue behavior.

### AVAudioPlayerNode Buffer Queue Gotcha

**Buffers are APPENDED, not replaced.** When you call `scheduleBuffer:atTime:options:0`, the buffer goes into a FIFO queue. If you schedule a new buffer without stopping the node first, the old buffer remains queued ahead of it.

**`playerTime.sampleTime` is CUMULATIVE** across all queued buffers. The position calculation `_scheduledStartFrame + playerTime.sampleTime` breaks if stale buffers remain, because `sampleTime` includes samples from old buffers but `_scheduledStartFrame` only references the new one.

**Fix**: `seekToPosition:` must call `[_playerNode stop]` to clear the buffer queue before scheduling new playback — **even when paused**, not just when playing:

```objc
- (void)seekToPosition:(CGFloat)positionMS {
    // Always stop the player node when seeking — whether playing or paused.
    // This clears stale buffers from the queue. Without this, paused buffers
    // remain queued and playerTime.sampleTime becomes cumulative across old
    // and new buffers, causing position calculation drift.
    if (wasPlaying || _playbackState == XLAudioPlaybackStatePaused) {
        _scheduleGeneration++;
        [_playerNode stop];
    }
    // ...
}
```

### `_scheduleGeneration` Counter

Completion handlers from `scheduleBuffer:completionHandler:` can fire after the player is stopped and re-started. The `_scheduleGeneration` counter invalidates stale handlers — each seek/stop increments it, and the completion handler checks if its captured generation still matches.

### Key Files

| File | Role |
|------|------|
| `sequencer/XLAudioPlayer.h/m` | AVAudioEngine wrapper: load, play, pause, stop, seek, position tracking |
| `XLPlaybackController.h/m` | Orchestrates audio player + engine bridge; single source of truth |
| `XLSequencerViewController.m` | Delegates play/stop/pause to playback controller (never calls engine directly) |
| `XLMainWindowController.mm` | Creates playback controller; menu item handlers |
| `sequencer/XLWaveformView.m` | Click-to-seek fires `waveformView:didSeekToTimeMS:` regardless of playback state |

---

## Rendering Bug: Sidebar Preview Overwrites Playback Buffers

### The Symptom

After editing effects and running Render All, playback shows effects at the wrong times — regardless of where in the sequence the user starts playing. The pattern of effects displayed corresponds to the selected effect's time region (the first effects in the sequence), not the current playback position. Restarting the app and reloading the same sequence fixes it temporarily.

### Root Cause: Shared Buffer Corruption

The sidebar model preview (`XLMainContentView.swift`) has its own timer loop that, when playback is not active, cycles through `effectStartMS..effectEndMS` to animate the selected effect:

```swift
if playbackActive {
    timeMS = Int(bridge.getPosition())
} else {
    timeMS = loopPositionMS
    loopPositionMS += frameTimeMS
    if loopPositionMS >= effectEndMS { loopPositionMS = effectStartMS }
}
bridge.renderModelFrame(name, timeMS: Int(timeMS))
```

Before the fix, `renderModelFrame` called the shared `renderFrame(timeMS)` for FSEQ and PRERENDERED paths. This overwrote `_bufferCache`, `_currentFrameData`, and `_currentFrameIndex` — the same shared state that `XLPlaybackController` reads on the playback render queue.

**Timeline of corruption during playback**:
1. Playback controller calls `renderFrame(playbackTimeMS)` → writes correct data to `_bufferCache`
2. Between `renderFrame` and `enumerateFrameBuffersWithBlock`, the sidebar timer fires
3. Sidebar calls `renderModelFrame` → calls `renderFrame(effectRegionTimeMS)` → overwrites `_bufferCache` with effect-region data
4. Playback controller reads `_bufferCache` → gets the sidebar's effect-region data instead of playback data
5. Display shows effects at the wrong times

### Three Interacting Bugs

The full issue was a cascade of three bugs:

| Bug | Location | Impact |
|-----|----------|--------|
| **FSEQ `shared_ptr` use-after-free** | `RenderEngine.cpp` | `forceRenderAll` destroyed `_fseqFile` (unique_ptr) while `renderFrame` could be mid-read on the FSEQ path → crash or corruption |
| **Edit stuck on stale FSEQ** | `invalidateModelAndGroup` | After editing, stale FSEQ data remained loaded. The FSEQ path kept serving pre-edit pixel data until the next full Render All |
| **Sidebar overwrites playback buffers** | `renderModelFrame` | The smoking gun — sidebar preview called shared `renderFrame()`, corrupting playback state (described above) |

### The Fixes

**1. FSEQ thread safety**: Changed `_fseqFile` from `unique_ptr` to `shared_ptr`. All access sites grab a local copy under `_fseqMutex`. The FSEQ path in `renderFrame` grabs a local `shared_ptr` copy, then reads without holding the lock:

```cpp
std::shared_ptr<FSEQFile> localFseq;
{
    std::lock_guard<std::mutex> lock(_fseqMutex);
    localFseq = _fseqFile;
}
// Use localFseq safely — even if forceRenderAll destroys _fseqFile
```

**2. Edit clears stale data**: `invalidateModelAndGroup` now clears both FSEQ and renderedData so edits immediately fall to the LIVE rendering path instead of serving stale pre-edit data.

**3. Sidebar isolation** (the key fix): `renderModelFrame` no longer calls the shared `renderFrame()` for FSEQ/PRERENDERED paths. Instead, it reads frame data directly into a local buffer and writes to `_sidebarCache` (a separate buffer that doesn't interfere with playback):

```cpp
if (haveFseq || (_renderedData && _renderedData->isValid() && !_modelChannelMap.empty())) {
    // Build ONLY the requested model's FrameBuffer into _sidebarCache.
    // Do NOT call renderFrame() — that would overwrite _bufferCache
    auto chIt = _modelChannelMap.find(physicalModel);
    // ... reads frame data into localFrameData
    // ... builds FrameBuffer from model's channel range
    // ... writes to _sidebarCache (NOT _bufferCache)
}
```

### The Rule

**`renderModelFrame` must NEVER call shared `renderFrame()` for FSEQ or PRERENDERED paths.** The sidebar has its own timer loop with different time values. If it writes to `_bufferCache`, it corrupts playback data. The sidebar must always use its own isolated buffer (`_sidebarCache`).

For the LIVE rendering path, calling `renderFrame()` from the sidebar is acceptable because live rendering doesn't cache frame data in `_bufferCache` the same way.

### Key Files

| File | Role |
|------|------|
| `xLights/engine/RenderEngine.cpp` | `renderModelFrame` sidebar isolation, `renderFrame` FSEQ mutex, `invalidateModelAndGroup` stale data clearing |
| `xLights/engine/RenderEngine.h` | `shared_ptr<FSEQFile> _fseqFile`, `_fseqMutex`, `_sidebarCache` |
| `xLights/native-mac/XLMainContentView.swift` | Sidebar preview timer loop that calls `renderModelFrame` |
| `xLights/native-mac/XLPlaybackController.m` | Playback render loop that reads `_bufferCache` |
