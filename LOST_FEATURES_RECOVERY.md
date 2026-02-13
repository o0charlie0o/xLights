# Lost Features Recovery Guide

## What Happened

Between Feb 2-9, 2026, numerous features were implemented in the native macOS rebuild across ~30 coding sessions. Many of these features were **never committed to git**. When later sessions (Feb 10-12) modified the same files for stems, song structure, and other work, they started from committed versions, effectively overwriting the uncommitted changes.

## Conversation History Location

All conversation transcripts are at:
```
/Users/charlie/.claude/projects/-Users-charlie-Documents-Charlie-xLights/*.jsonl
```

Key sessions containing the lost work (search these for implementation details):

| Session UUID | Date | Key Work |
|-------------|------|----------|
| `8801eba1` | Feb 7 | Value curve window, parameter scaling, live preview |
| `1f29e54e` | Feb 7 | Value curve continuation |
| `bb67efb4` | Feb 7 | Effect panel builder, value curve integration |
| `5c16d10a` | Feb 7 | White pixel selection, submodel node indices |
| `deb54c35` | Feb 7 | Pixel rendering refinements, effect colors |
| `65c47e39` | Feb 7 | Layout preview fix, model pixel rendering |
| `7dcb880a` | Feb 7 | Controller dialog, dimming curves |
| `c726e70e` | Feb 8 | Effect collision, snap-to-grid, toggle buttons |
| `d74cac8b` | Feb 8 | Show folder research and planning |
| `3454320b` | Feb 8 | Show folder implementation |
| `4f71870c` | Feb 9 | Key bindings implementation |
| `57d90123` | Feb 9 | Sidebar model preview, toolbar tabs, toggle styles |
| `b38461f4` | Feb 9 | Editable key bindings window |
| `7e7088f8` | Feb 9 | Timing track improvements |
| `04a04d4f` | Feb 5 | House preview, FSEQ playback, model rendering |
| `e5d1cc23` | Feb 6 | House preview debugging (76MB session) |

## Build Command

```bash
xcodebuild -project macOS/xLights.xcodeproj -scheme "xLights Native" -configuration Debug build
```

Use `xLights Native` scheme (NOT `xLights`).

## Architecture Reference

- `CLAUDE.md` - Full codebase architecture guide
- `NATIVE_MACOS.md` - Native rebuild reference (in repo root)
- Memory notes at `/Users/charlie/.claude/projects/-Users-charlie-Documents-Charlie-xLights/memory/MEMORY.md`

## Key Architecture Patterns

- **Native build**: Uses `#ifdef XLIGHTS_NATIVE` / `#else` blocks in shared C++ files
- **Bridge pattern**: Swift/SwiftUI → `XLEngineBridge` (Obj-C++) → C++ engines
- **Provider interfaces**: `IEffectProvider`, `IModelProvider`, `IOutputProvider`
- **Language priority**: Swift/SwiftUI > AppKit (Swift) > Objective-C > C++

## Already Recovered (committed in this session)

1. **Toolbar tab buttons** (Setup/Layout/Sequencer) with `TabToolbarButtonStyle` blue accent
2. **ToolbarToggleButtonStyle** for panel toggles (Palettes, Snap, Preview, Song Regions, Inspector)
3. **Sidebar model preview** via `XLSidebarModelPreview` NSViewRepresentable
4. **Show folder UI** in Setup tab with permanent/temporary switching and MRU
5. **Song region grid overlay** rendering behind effects
6. **Selection vertex rebuild** fix (`_modelVerticesDirty` checked in render loop)

---

## Features Still Missing / Needing Recovery

### 1. Value Curve Parameter Scaling (CRITICAL - affects all effect rendering)

**Status**: `paramNeedsRealScale:forType:` was NEVER COMMITTED. The scaling logic is documented in NATIVE_MACOS.md but not in the code.

**What it does**: MINVOID/MAXVOID parameters must be serialized on the real `_min/_max` scale (NOT 0-100). Without this, `Normalise()` produces tiny values → `Safe01()` clamps to 0 → all curve points are zero.

**Key reference**: Session `8801eba1` (Feb 7) - search for "paramNeedsRealScale"

**Files to modify**:
- `xLights/native-mac/dialogs/XLValueCurveWindow.m` - Add `paramNeedsRealScale:forType:`, update `curveDataString` and `parseKeyValueCurveData:`

**Scaling table** (from `ValueCurve.cpp` `GetRangeParm{N}()`):

| Curve Type | P1 | P2 | P3 | P4 |
|---|---|---|---|---|
| Flat | MINVOID | - | - | - |
| Ramp/RampUp/RampDown | MINVOID | MINVOID | - | - |
| RampUpHold/RampDownHold | MINVOID | MINVOID | - | - |
| Saw Tooth | MINVOID | MINVOID | - | - |
| Square | MINVOID | MINVOID | - | - |
| Random | MINVOID | MINVOID | - | - |
| Sine/Abs Sine | fixed | MINVOID | fixed | MINVOID |
| Parabolic Up/Down | fixed | MINVOID | - | - |
| Logarithmic Up/Down | fixed | MINVOID | - | - |
| Exponential Up/Down | fixed | MINVOID | - | - |
| Custom | - | - | - | - |

**Serialization format**: `Active=TRUE|Id=ValueCurve|Type=Sine|Min=0.00|Max=500.00|P2=500.00|...`
- `Id=ValueCurve` MUST be present or `IsOk()` returns false (silent failure)
- `RV=TRUE` indicates real values mode

### 2. Sidebar Model Preview - Timer Loop & Effect Assist

**Status**: Basic `XLSidebarModelPreview` NSViewRepresentable exists but lacks the timer-based effect loop.

**What the original did** (session `57d90123`):
- Timer looped the selected effect's time range in the sidebar preview
- Showed only the currently selected model's pixels
- Auto-zoomed to fit the model (with padding for wide models)
- Effect Assist panel below the model preview

**Files**: `XLMainContentView.swift`, `XLPlaybackController.m`

### 3. Gradient Color Support in Color Palette

**Status**: Plan exists at `/Users/charlie/.claude/plans/snoopy-wibbling-marshmallow.md` but was never implemented.

**What it does**: Allows switching palette color slots between solid and gradient mode. Legacy format: `Active=TRUE|Id=ID_BUTTON_Palette1|Values=x=0.000^c=#ff0000;x=1.000^c=#0000ff|`

**Files**: `xLights/native-mac/ColorPaletteView.swift`

### 4. Cascading Nudge for Timing Mark Moves

**Status**: Plan exists at `/Users/charlie/.claude/plans/radiant-hugging-beaver.md` but was never implemented.

**What it does**: When dragging a timing mark into an adjacent one, the adjacent mark cascades/pushes rather than overlapping.

**Files**: `xLights/native-mac/sequencer/XLEffectsGridView.m`

### 5. White Pixel Selection with Submodel Support

**Status**: The `baseGray = 1.0f` approach works for whole-model selection. The more sophisticated `nodeIsWhite` / `selectedSubmodelNodeIndices` approach (which highlights only the submodel's nodes as white) was never committed.

**Reference**: Session `5c16d10a` (Feb 7) - search for "nodeIsWhite"

**Files**: `xLights/native-mac/layout/XLMetalPreviewView.m`

### 6. Editable Key Bindings Window

**Status**: The key bindings window can display bindings but lacks the ability to edit them.

**Reference**: Session `b38461f4` (Feb 9)

**Files**: `xLights/native-mac/preferences/XLKeyBindingsWindowController.m`

### 7. Timing Track Import Sources

**Status**: Beads ticket `xlmac-zw46` exists. Multiple timing track import sources (from audio, from file, etc.) are not implemented.

### 8. Effect Collision Prevention During Multi-Drag

**Status**: Basic collision works for single effect drag. Multi-selection drag has edge cases where effects can overlap.

**Reference**: Sessions `c726e70e` (Feb 8), user messages 176-181

**Files**: `xLights/native-mac/sequencer/XLEffectsGridView.m`

### 9. Timing Mark Label Editing (Lyric Tracks)

**Status**: Timing marks with lyrics/phonemes need label editing support. The rendering exists but editing was being refined.

**Reference**: Session `7e7088f8` (Feb 9)

### 10. Command Palette Effect Adding

**Status**: The command palette exists but doesn't support adding effects to selected cells.

**Reference**: Session from user message 143: "I want to put every single effect in the command palette"

**Files**: `xLights/native-mac/XLCommandPalette.swift`

### 11. Double-Click Effect Panel to Add Effect

**Status**: User requested that double-clicking an effect in the effects panel adds it to the selected cell.

**Reference**: User message 144

### 12. Key Bindings XML Read/Write

**Status**: Beads ticket `xlmac-71gv` exists. The key bindings window should read from and write to `key_bindings.xml`.

### 13. xlCore TIMING_ADD Default Fallback

**Status**: Beads ticket `xlmac-0o7f` exists (P1 bug). Missing default fallback for TIMING_ADD action.

---

## How to Search Conversation History

To find implementation details for any feature:

```bash
# Search for a specific feature across all transcripts
grep -l "paramNeedsRealScale" /Users/charlie/.claude/projects/-Users-charlie-Documents-Charlie-xLights/*.jsonl

# Search within a specific session for user messages
grep '"role":"human"' /Users/charlie/.claude/projects/-Users-charlie-Documents-Charlie-xLights/8801eba1-*.jsonl | head -20

# Search for Edit/Write tool calls on a specific file
grep "XLValueCurveWindow" /Users/charlie/.claude/projects/-Users-charlie-Documents-Charlie-xLights/8801eba1-*.jsonl | grep -c "Edit\|Write"
```

## Pre-existing Build Errors (NOT our issue)

- `XLEngineBridge.mm`: RenderEngine missing `setModelProvider`, `setOutputProvider`, `closeFSEQ`, `loadFSEQ`
- Several unimplemented submodel methods in XLEngineBridge
- These are pre-existing in the `xLights` scheme (use `xLights Native` scheme instead)
