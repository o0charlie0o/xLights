# Timing Track Color Mismatch — Debug Handoff

## Problem
The timing track row headers (drawn via CoreGraphics in `XLRowHeadingsView.m`) show the correct color for each timing track, but the grid extension lines (vertical lines drawn via Metal in `XLEffectsGridRenderer.m`) show the WRONG color. Specifically:

- **Beats** (colorIndex=2, should be Yellow `1.0, 0.95, 0.15`) → row header shows Yellow, grid lines show **BLUE**
- **Beats Divided** (colorIndex=3, should be Cyan `0.2, 0.9, 1.0`) → row header shows Cyan, grid lines show **nearly BLACK**

## What Has Been Verified

1. **Color palette is unified** — Single `XLTimingTrackColor()` function in `XLEffectsGridRenderer.h` used by all 3 consumers (tick marks, grid extension lines, row headers). No duplicate palette definitions.

2. **Color indices are correct** — Extensive logging confirms `activeTimingColorIndex` matches between the VC, grid view property, and renderer parameter. Beats=2, Beats Divided=3, consistent everywhere.

3. **Renderer receives correct RGBA values** — Logged output: `RGBA(1.00, 0.95, 0.15, 0.35)` for Beats (Yellow). The code is computing the right color.

4. **Grid extension code IS executing** — Diagnostic log shows: `timingMarkCount=902, timingGridTop=352.0, vertexCountBefore=90, maxVtx=8192, viewH=1044`. Plenty of buffer space, correct Y positioning.

5. **Forced color test results (critical clue)**:
   - Forced RED `(1.0, 0.0, 0.0, 0.9)` → grid extension lines became **INVISIBLE**
   - Forced GREEN `(0.0, 1.0, 0.0, 0.9)` → timing tick marks became **BLACK**
   - These results are NOT consistent with correct color passthrough

## Likely Root Cause: `simd_float4` Alignment Padding in `SimpleVertex`

The Metal vertex struct has an alignment bug:

```c
typedef struct {
    simd_float2 position;  // 8 bytes, 8-byte aligned
    simd_float4 color;     // 16 bytes, BUT 16-byte aligned → offset is 16, not 8!
} SimpleVertex;
```

`simd_float4` requires 16-byte alignment. The compiler inserts 8 bytes of padding after `position`, making `color` start at offset 16. But the vertex descriptor says:

```objc
vertexDesc.attributes[1].offset = sizeof(simd_float2);  // = 8, WRONG!
```

The actual offset is 16 (`offsetof(SimpleVertex, color)`), not 8. This means:
- `sizeof(SimpleVertex)` is likely **32** (not 24)
- The GPU reads bytes 8-23 as color, but the actual color data is at bytes 16-31
- The GPU sees: `[padding(0), padding(0), actual_R, actual_G]` as the float4 color

This perfectly explains ALL observations:
- Yellow `(1.0, 0.95, 0.15, 1.0)` → GPU reads `(0, 0, 1.0, 0.95)` = **BLUE at 95% alpha** ✓
- Cyan `(0.2, 0.9, 1.0, 1.0)` → GPU reads `(0, 0, 0.2, 0.9)` = **nearly BLACK** ✓
- Forced RED `(1.0, 0.0, 0.0, 0.9)` → GPU reads `(0, 0, 1.0, 0.0)` = alpha 0 = **INVISIBLE** ✓
- Forced GREEN `(0.0, 1.0, 0.0, 0.9)` → GPU reads `(0, 0, 0.0, 1.0)` = **BLACK** ✓

## Proposed Fix

Replace `simd_float2`/`simd_float4` in vertex structs with packed types that don't require alignment:

```c
typedef struct {
    float position[2];   // or simd_packed_float2
    float color[4];      // or simd_packed_float4
} SimpleVertex;          // 24 bytes, no padding
```

And use `offsetof()` for vertex descriptor offsets:

```objc
vertexDesc.attributes[1].offset = offsetof(SimpleVertex, color);
vertexDesc.layouts[0].stride = sizeof(SimpleVertex);
```

**Same fix needed for all vertex structs**: `SimpleVertex`, `RoundedRectVertex`, `TexturedVertex`, etc.

## Verification Step

Add this log to confirm the theory before fixing:

```objc
NSLog(@"SimpleVertex: sizeof=%lu, offsetof(color)=%lu, sizeof(simd_float2)=%lu",
      sizeof(SimpleVertex), offsetof(SimpleVertex, color), sizeof(simd_float2));
```

If output shows `sizeof=32, offsetof(color)=16, sizeof(simd_float2)=8`, the theory is confirmed.

## Key Files

| File | Role |
|------|------|
| `xLights/native-mac/sequencer/XLEffectsGridRenderer.h` | Shared `XLTimingTrackColor()` palette + `XLEffectRenderInfo` struct |
| `xLights/native-mac/sequencer/XLEffectsGridRenderer.m` | Metal renderer — `SimpleVertex` struct (line 24-27), vertex descriptor (line 374-381), grid extension lines (~line 700), timing tick marks (~line 768) |
| `xLights/native-mac/sequencer/XLEffectsGridShaders.metal` | Metal shaders — vertex/fragment shaders |
| `xLights/native-mac/sequencer/XLRowHeadingsView.m` | Row header drawing (CoreGraphics, NOT Metal — works correctly) |
| `xLights/native-mac/XLSequencerViewController.m` | Data source — assigns `timingColorIndex`, manages `activeTimingColorIndex` |
| `xLights/native-mac/sequencer/XLEffectsGridView.h` | `activeTimingColorIndex` property |
| `xLights/native-mac/sequencer/XLEffectsGridView.m` | Passes data to renderer, CALayer label overlay |

## Build

```bash
xcodebuild -project macOS/xLights.xcodeproj -scheme "xLights Native" -configuration Debug build
```

Use `xLights Native` scheme (NOT `xLights`).

## Current State

- All debug logging can be removed (the `updateActiveTimingColorIndex` NSLogs, etc.)
- The grid extension line color is currently set to full brightness alpha 1.0 (for debugging)
- The row header colors use alpha blending: 0.7 selected, 0.45 unselected
- Once the vertex alignment bug is fixed, tune the grid extension line alpha to visually complement the row headers (probably 0.3-0.5 range)
