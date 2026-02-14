# Native Render Pipeline Audit: Legacy vs NativeRenderCoordinator

## Executive Summary

The native render pipeline (`NativeRenderCoordinator`) was written as a simplified reimplementation rather than a close port of the legacy rendering logic. This audit identifies **23 gaps** between the two implementations, with the top 3 being:

1. **Layer settings (B_ prefix) are NEVER parsed or applied** — mix type, brightness, blur, transitions, sparkle, HSV adjust, persistent layers are all ignored
2. **No model blending (+1 blend layer)** — overlapping channel data from groups and models doesn't composite correctly
3. **Group effects render per-model, not on combined group geometry** — spatial effects like Bars will look wrong

---

## A. Layer Setup & Group Cascading

### Legacy (`PixelBuffer.cpp` + `Render.cpp`)

**Layer count**: `InitBuffer()` creates `numLayers + 1` layers. The extra layer is the **blend layer** — used for model blending when groups and models share channels. The existing channel data is loaded into this layer via `buffer->SetColors(numLayers, &seqData[frame][0])`, so model effects blend on top of whatever the group rendered.

**Group rendering**: Groups are treated as a **single combined model**. The group's `PixelBufferClass` aggregates ALL member model nodes into one render buffer. A "Bars" effect on a group renders one continuous pattern across the entire group geometry. Models that ALSO have their own effects render separately, using the blend layer to composite on top.

**Per Model buffer style**: When `B_CHOICE_BufferStyle` is `"Per Model"`, the group creates separate per-model render buffers inside each layer. The effect renders once per member buffer, then `MergeBuffersForLayer()` combines them. `"Per Model Deep"` also exists.

**Submodel/strand effects**: Submodels and strands with effects get their own `PixelBufferClass`. These render AFTER the main model with `blend=true`, overlaying their output.

**Render ordering**: `RenderTree` builds a dependency graph — models sharing channels render in order via `AggregatorRenderer`. A model waits for overlapping models to finish a frame before proceeding.

### Native (`NativeRenderCoordinator.cpp`)

**Layer count**: Creates exactly `totalLayerCount = groupLayerCount + ownLayerCount`. **No blend layer** — no +1.

**Group rendering**: Groups are **skipped** as top-level targets. Instead, for each physical model, `findParentGroupElement()` finds the parent group's effects. Group layers are prepended to the model's own layers. Each model renders the group effect independently onto its own buffer.

**Per Model buffer style**: Implemented. `B_CHOICE_BufferStyle` is parsed into `NativeLayerInfo.bufferStyle`. When a group layer has "Per Model" or "Per Model Deep" style, `renderPerModelLayer()` renders the effect per-member. Sub-styles (e.g., "Per Model Single Line") are extracted and applied via `prepareBufferStyle()`. "Per Model Deep" recursively flattens nested groups to leaf models.

**Submodel/strand effects**: Not implemented. Submodels/strands with their own effects in the timeline are ignored.

**Render ordering**: Models render in parallel with no dependency ordering.

### Gaps

| # | Feature | Impact |
|---|---------|--------|
| 1 | No blend layer (+1) for model blending | **P0** — overlapping channels produce wrong output |
| 2 | Group effects render per-model not combined | **P0** — spatial effects (Bars, etc.) look wrong on groups |
| 3 | ~~No "Per Model" / "Per Model Deep" buffer style~~ | ~~**P1**~~ **DONE** — Per Model styles now parsed and handled in renderModelAtTime() |
| 4 | No submodel/strand effect rendering | **P1** — effects on submodels/strands ignored |
| 5 | No render dependency ordering | **P1** — parallel writes to overlapping channels |

---

## B. Effect Rendering Per Layer

### Legacy (`Render.cpp`)

**Effect lookup**: `findEffectForFrame()` with `lastIdx` optimization for sequential access. Boundary: `startTimeMS <= time < endTimeMS`.

**Settings parsing**: `loadSettingsMap()` copies all E_, B_, T_ keys into `SettingsMap`. Then `buffer->SetLayerSettings(layer, settingsMap, layerEnabled)` parses dozens of layer parameters: mix type, blur, rotation, zoom, brightness, sparkle, transitions, chroma key, freeze, suppress, persistent, canvas, sub-buffer, and all their value curves.

**Buffer init per frame**: `persist` and `freeze` flags determine clearing. If NOT persistent and NOT frozen and no effect, `buffer->Clear(layer)` zeros it. If persistent, previous data survives.

**"No effect" gaps**: Layer disabled, buffer cleared (unless persistent).

**Duplicate effect**: Special effect type that mirrors another model/layer with overrides.

### Native (`NativeRenderCoordinator.cpp`)

**Effect lookup**: `_effectProvider->getEffectAtTime()`. No sequential optimization.

**Settings parsing**: Settings stored in `effectInfo.settings`. **Layer settings (B_ prefix) are NEVER parsed.** `setLayerSettings()` is NEVER called.

**Buffer init per frame**: `job.pixelBuffer->clear()` then `buf.Clear()` for each layer. **Every frame starts from scratch** — no persistent option.

**Duplicate effect**: Implemented. Resolves source model/layer via `_effectProvider`, applies override flags (buffer/timing/palette/color), recursively renders.

### Gaps

| # | Feature | Impact |
|---|---------|--------|
| 6 | **Layer settings NEVER parsed (B_ prefix)** | **P0** — see Section C for full impact |
| 7 | No persistent layer (overlay background) | **P0** — breaks effects relying on persistence |
| 8 | No freeze after frame | **P2** |
| 9 | No suppress until frame | **P2** |
| 10 | ~~No Duplicate effect~~ DONE | **P2** |
| 11 | No sub-buffer / variable sub-buffer | **P1** |
| 12 | ~~No buffer style selection (always "Default")~~ | ~~**P1**~~ **DONE** — Buffer styles parsed from B_CHOICE_BufferStyle, Per Model/Deep handled |

---

## C. Layer Mixing / Blending

### Legacy (`PixelBuffer.cpp`)

**Mix types**: 23 types (Normal, Effect1/2, Mask1/2, Unmask1/2, TrueUnmask1/2, 1reveals2, 2reveals1, Layered, Average, BottomTop, LeftRight, Shadow1on2, Shadow2on1, Additive, Subtractive, AsBrightness, Max, Min, Highlight, Highlight_Vibrant).

**Mix transitions**: `effectMixThreshold` from `SLIDER_EffectLayerMix`. `effectMixVaries` (LayerMorph) makes threshold follow time position.

**Fade transitions**: 16+ transition types (Wipe, Clock, From Middle, Square/Circle Explode, Blinds, Blend, Slide, Fold, Dissolve, Circular Swirl, Bow Tie, Zoom, Doorway, Blobs, Pinwheel, Star, Swap, Shatter).

**Per-pixel blending**: `GetMixedColor()` iterates layers back-to-front. For each valid layer: reads pixel, applies HSV adjustments, brightness/contrast, then `mixColors()`.

**Sparkles**: Applied per-node in `CalcOutput()` via GPU (Metal/ISPC) or CPU fallback. Random counter per node, music sensitivity option, configurable sparkle color.

**Brightness/contrast**: Brightness 0-400%, contrast adjusts V channel. Both support value curves.

**RotoZoom**: 2D rotation, 3D X/Y rotation, zoom with quality settings, pivot points. All support value curves.

**Blur**: Gaussian approximation via 3-pass box blur. Supports value curve.

### Native (`NativePixelBuffer.cpp`)

**Mix types**: All 23 declared in `NativeColorBlending.h`, `mixColors()` implemented. **But mix type is never set from layer settings** — always defaults to `Mix_Normal`.

**Fade/transitions**: Fields exist in `NativeLayerInfo` but **never populated** from settings.

**Per-pixel blending**: `calcOutput()` has correct back-to-front iteration with HSV/brightness/contrast/sparkle. Would work correctly **if layer settings were populated**.

**RotoZoom**: Not implemented at all.

**Blur**: Not implemented.

### Gaps

| # | Feature | Impact |
|---|---------|--------|
| 13 | Mix type always Normal (never set from settings) | **P0** — part of layer settings gap |
| 14 | Fade in/out transitions non-functional | **P1** — fields exist but never populated |
| 15 | No RotoZoom (rotation, zoom, pivot) | **P1** — layer transforms missing |
| 16 | No value curves on layer params | **P1** — animated blur/brightness/HSV/zoom/rotation ignored |
| 17 | No blur | **P1** |
| 18 | No color curves on palette colors | **P1** |

---

## D. Buffer Sizing & Channel Mapping

### Legacy (`PixelBuffer.cpp`)

**Buffer dimensions**: Each layer can have DIFFERENT buffer style → different dimensions. Set in `SetLayerSettings()`.

**Channel output** (`GetColors`): Iterates nodes, applies **dimming curves** per-node, writes RGB(W) respecting node's color order and channel count.

### Native

**Buffer dimensions**: All layers share same dimensions. No per-layer buffer style.

**Channel output** (`getColors`): Iterates nodes, writes channels. **No dimming curves**. Color order **hardcoded to RGB** (never reads from model). Channels per node **hardcoded to 3** (breaks RGBW and single-channel models).

### Gaps

| # | Feature | Impact |
|---|---------|--------|
| 19 | No dimming curves | **P1** — brightness/gamma correction missing |
| 20 | Color order hardcoded to RGB | **P0** — GRB, BGR models will show wrong colors |
| 21 | Channels per node hardcoded to 3 | **P0** — RGBW (4ch) and single-color (1ch) models break |

---

## E. Stateful Effects & Optimization

### Legacy
- Effect state via `infoCache` (map<string, void*>) on RenderBuffer
- Persistent layer: buffer NOT cleared when `CHECKBOX_OverlayBkg` is true
- Dirty range tracking for incremental re-render
- Render cache (disk) for effects supporting it
- GPU-accelerated blending (Metal compute / ISPC)
- Intra-effect parallelism (`parallel_for`)

### Native
- Effect state via `infoCache` on NativeRenderBuffer — **parity**
- Persistent layer: **not implemented** (always cleared)
- No dirty range tracking
- No render cache
- No GPU-accelerated blending
- No intra-effect parallelism

### Gaps

| # | Feature | Impact |
|---|---------|--------|
| 22 | No render cache | **P2** — performance only |
| 23 | No GPU-accelerated blending | **P2** — performance only |

---

## F. Timing & Frame Calculation

Frame time calculation and effect boundary semantics appear to be at **parity**. Both use `startTimeMS <= time < endTimeMS`.

---

## Priority Summary

### P0 — Will cause visibly incorrect rendering for common sequences

1. **Layer settings (B_ prefix) never parsed** (#6, #13) — This is the single biggest fix. Implementing `setLayerSettings()` or populating `NativeLayerInfo` from effect settings would unlock correct mix types, brightness, contrast, sparkle, HSV adjust, and fade transitions.

2. **Color order hardcoded to RGB** (#20) — Models using GRB (WS2812B common), BGR, etc. will display incorrect colors in batch render output.

3. **Channels per node hardcoded to 3** (#21) — RGBW and single-channel models will produce corrupt output.

4. **No blend layer for model blending** (#1) — When groups and models overlap channels, the last writer wins instead of proper compositing.

5. **Group effects render per-model not combined** (#2) — Spatial effects on groups will look fundamentally different.

6. **No persistent layer** (#7) — Effects that depend on previous frame data (overlay background) will be wrong.

### P1 — Will cause incorrect rendering for sequences using these features

7. Buffer transforms — flip, rotate, sub-buffer (#11, #12, #15)
8. Submodel/strand effects (#4)
9. Fade/transitions (#14)
10. Value curves on layer params (#16)
11. Blur (#17)
12. Dimming curves (#19)
13. ~~Per Model buffer style (#3)~~ **DONE**
14. Color curves (#18)
15. Render dependency ordering (#5)

### P2 — Missing features, performance

16. Freeze/suppress (#8, #9)
17. Duplicate effect (#10)
18. Render cache (#22)
19. GPU blending (#23)

---

## Recommended Fix Order

### Phase 1: Parse layer settings (fixes 8 gaps at once)

Add a function that extracts B_ prefix settings from `effectInfo.settings` and populates `NativeLayerInfo`. This immediately fixes:
- Mix type selection
- Brightness/contrast
- Sparkle
- HSV adjustments
- Fade in/out (basic)
- Persistent layer flag
- Layer morph (varying mix threshold)
- Layer enabled/disabled

**Estimated scope**: ~200 lines of parsing code + ~20 lines to call it in `renderModelAtTime()`.

### Phase 2: Fix channel output

- Read color order from model attributes → fix #20
- Read channels-per-node from model attributes → fix #21
- Apply dimming curves → fix #19

### Phase 3: Group rendering architecture

Either:
- (A) Render groups onto combined buffers (matching legacy exactly), or
- (B) Accept per-model rendering with documented limitations

Option A is significantly more work but produces correct output. Option B is pragmatic — most group effects still look reasonable per-model.

### Phase 4: Model blending

Add the +1 blend layer that loads existing channel data before rendering model-specific effects.

---

# Metal GPU Rendering Pipeline Optimization

## Current Data Flow (End-to-End)

The complete path from effect render to Metal vertex color update involves **5 copies**, **4 mutex acquisitions**, and heavy Obj-C overhead per frame:

```
[Render Queue - C++]
  NativePixelBuffer::calcOutput() → _outputPixels (vector<xlColor>)
    ↓ COPY #1: memcpy into RenderedFrame::pixels
  RenderEngine::_bufferCache stores FrameBuffer
    ↓ COPY #2: getAllFrameBuffers() deep-copies every FrameBuffer (under mutex)

[Bridge - Obj-C++]
  XLEngineBridge wraps each FrameBuffer in NSDictionary + NSData
    ↓ COPY #3: [NSData dataWithBytes:] copies pixel vectors

[Main Queue - Obj-C]
  dispatch_async to main queue (0-16ms latency)
  setRenderedPixels: stores NSData in NSDictionary (under NSLock)
    ↓ COPY #4: buildModelVerticesWithEffectColors rebuilds entire vertex buffer
    Per node: 5 NSNumber→float unboxings for position (x, y, z, bufX, bufY)
    Per node: NSData byte access for pixel colors
    Per node: write XLGridVertex (position float3 + color float4 = 28 bytes)
```

**Current cost: ~40-108ms per frame** (dominated by vertex rebuild on main queue)

## Bottleneck Analysis

| Operation | Location | Cost | Queue |
|-----------|----------|------|-------|
| `buildModelVerticesWithEffectColors` | XLMetalPreviewView.m | **20-80ms** | Main |
| `getAllFrameBuffers()` deep copy | RenderEngine.cpp | 1-5ms | Render |
| NSDictionary/NSData bridge | XLEngineBridge.mm | 1-3ms | Render |
| dispatch_async latency | XLPlaybackController.m | 0-16ms | Cross-queue |
| Mutex contention | Multiple | 0-2ms | Various |

The single biggest cost is **NSDictionary/NSNumber unboxing per node per frame**. For 10,000 nodes: ~50,000 Obj-C message sends just for position data that NEVER CHANGES between frames.

## Proposed Architecture: Target ~2-5ms per frame

### 1. Zero-Copy Buffer Access in RenderEngine

Add visitor pattern that invokes callback under lock:

```cpp
// New API in RenderEngine.h
using FrameBufferVisitor = std::function<void(
    const std::string& name, const uint8_t* pixels, int w, int h)>;
void visitFrameBuffers(const FrameBufferVisitor& visitor) const;
```

Eliminates `getAllFrameBuffers()` deep copy entirely. The callback reads raw pixel pointers while the lock is held.

### 2. Pre-Flattened Node Data (compute once, use every frame)

Replace NSDictionary node iteration with C struct arrays built once on `reloadModels`:

```objc
typedef struct {
    simd_float3 position;    // 12 bytes — immutable
    int16_t bufX, bufY;      // 4 bytes — immutable
    uint16_t modelIndex;     // 2 bytes — for selection
    uint16_t flags;          // 2 bytes — selection state
} XLFlatNode;                // 20 bytes, well-aligned

typedef struct {
    NSUInteger nodeStart;    // Index into flat array
    NSUInteger nodeCount;
    uint16_t pixelWidth, pixelHeight;
    const char *name;        // Weak ref
} XLModelLookup;
```

**Current**: 50,000 Obj-C message sends per frame for 10K nodes
**Proposed**: 0 Obj-C message sends — pure C array traversal

### 3. Split Position/Color Metal Buffers

Current: Interleaved `{float3 position, float4 color}` = 28 bytes per vertex, rebuilt entirely every frame.

Proposed:
- **Static position buffer**: Written once on model load (12 bytes/node)
- **Dynamic color buffer**: Written per frame (16 bytes/node, or 4 bytes with uint8 RGBA)

Per-frame write bandwidth drops from 28 → 4-16 bytes per node.

### 4. Render Queue Direct Color Building

Move vertex color writing off the main queue entirely:

```
[Render Queue]
  1. renderFrame() produces pixel data (already here)
  2. NEW: Write vertex colors into Metal buffer
     — Iterate pre-flattened C array
     — Look up pixel color from render output
     — Write to triple-buffered color ring

[Main Queue]
  1. Swap buffer pointer (one assignment)
  2. Issue draw command
```

### Expected Performance

| Operation | Current | Proposed |
|-----------|---------|----------|
| getAllFrameBuffers() copy | 1-5ms | **0ms** (zero-copy visitor) |
| NSDictionary/NSData bridge | 1-3ms | **0ms** (raw pointers) |
| setRenderedPixels per model | 0.5-1ms | **0ms** (eliminated) |
| buildModelVerticesWithEffectColors | 20-80ms main queue | **0ms** main queue |
| Render queue color building | N/A | **1-3ms** (C array) |
| Main queue buffer swap | N/A | **~0.01ms** |
| **Total per frame** | **~25-108ms** | **~1-3ms** |

### Files Requiring Changes

1. `RenderEngine.h/cpp` — Add `visitFrameBuffers()` zero-copy API
2. `NativeRenderCoordinator.cpp` — Optional: avoid memcpy by exposing persistent pixel buffer pointers
3. `XLEngineBridge.mm` — Replace NSDictionary approach with direct C pointer passing
4. `XLPlaybackController.m` — Build vertex colors on render queue, dispatch only buffer swap to main
5. `XLMetalPreviewView.m` — Pre-flattened node arrays, split position/color buffers, render queue color update
6. `XLPreviewShaders.metal` — Split vertex input into separate position and color buffers
