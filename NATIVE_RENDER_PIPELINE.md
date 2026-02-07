# Native macOS Render Pipeline

Guide to the rendering system in the xLights native macOS rebuild. Covers how effects are rendered to pixels and displayed in the Metal house preview during both live editing and pre-rendered playback.

## Architecture Overview

```
SwiftUI / AppKit UI
        |
        v
XLEngineBridge (Obj-C++)              -- Bridge between UI and C++ engine
        |
        v
RenderEngine (C++)                    -- Orchestrates all rendering
        |
        +--> NativeRenderCoordinator  -- Manages per-model render jobs
        |        |
        |        +--> ModelJob        -- Per-model render state
        |        |       |
        |        |       +--> NativePixelBuffer  -- Layer blending
        |        |               |
        |        |               +--> NativeRenderBuffer (per layer)
        |        |                       |
        |        |                       +--> Effect rendering (Fire, Bars, etc.)
        |        |
        |        +--> NativeSequenceData  -- Output buffer (batch render)
        |
        +--> FSEQFile                 -- FSEQ playback reader
        |
        v
FrameBuffer (RGBA pixels per model)
        |
        v
XLPlaybackController (Obj-C)         -- Drives frame timing
        |
        v
XLMetalPreviewView (Obj-C / Metal)   -- Renders nodes as points
```

## Key Files

| File | Purpose |
|------|---------|
| `xLights/engine/RenderEngine.h/.cpp` | Top-level render API. Three playback paths: FSEQ, pre-rendered memory, live. |
| `xLights/engine/render/NativeRenderCoordinator.h/.cpp` | Builds and runs per-model render jobs. Contains native effect implementations. |
| `xLights/engine/render/NativePixelBuffer.h/.cpp` | Multi-layer blending for a single model. Replaces legacy `PixelBufferClass`. |
| `xLights/engine/render/NativeRenderBuffer.h/.cpp` | Per-layer pixel buffer. Effects call `SetPixel()`, `GetMultiColorBlend()`, etc. |
| `xLights/engine/render/NativeSequenceData.h/.cpp` | Flat channel data buffer for batch rendering. Exports to FSEQ V2. |
| `xLights/engine/render/NativeColorBlending.h/.cpp` | 20+ mix modes (Normal, Additive, Mask, etc.) |
| `xLights/engine/render/IRenderContext.h` | Minimal interface for audio/timing (replaces xLightsFrame* dependency). |
| `xLights/engine/interfaces/IEffectProvider.h` | Interface for reading sequence elements and effects. |
| `xLights/engine/interfaces/IModelProvider.h` | Interface for model geometry and channel mapping. |
| `xLights/native-mac/XLEngineBridge.h/.mm` | Obj-C++ bridge exposing C++ engine to SwiftUI. |
| `xLights/native-mac/XLPlaybackController.m` | Drives playback timing and frame rendering. |
| `xLights/native-mac/layout/XLMetalPreviewView.m` | Metal-based house preview renderer. |

## Three Rendering Paths

`RenderEngine::renderFrame(int timeMS)` has three paths, checked in priority order:

### 1. FSEQ Playback (highest priority)
- **When**: FSEQ file loaded via `loadFSEQ()` (at sequence open time).
- **How**: Reads pre-rendered channel data from disk. Maps channels to model pixels via `_modelChannelMap`.
- **Performance**: Very fast (disk read + channel mapping, no effect computation).
- **Cleared by**: `closeFSEQ()` (called by `invalidateAllCaches()`).

### 2. Pre-Rendered Memory Playback
- **When**: After `renderAll()` completes, `_renderedData` (NativeSequenceData) holds all frames in memory.
- **How**: Same channel-to-pixel mapping as FSEQ, but reads from memory instead of disk.
- **Cleared by**: `invalidateAllCaches()` resets `_renderedData`.

### 3. Live Effect Rendering (lowest priority)
- **When**: No FSEQ loaded, no pre-rendered data. Used during editing/preview before Render All.
- **How**: Uses a **persistent** `NativeRenderCoordinator` (`_liveCoordinator`) that keeps `ModelJob` objects alive across frames.
- **Key detail**: Stateful effects (Fire, etc.) store per-frame state in `NativeRenderBuffer::infoCache`. The persistent coordinator preserves this state across calls.
- **Performance**: ~10ms/frame for 4 active models on a 25ms budget (40fps).

### Path Switching
When effects are edited, `XLEngineBridge::scheduleAutoSave` calls `invalidateAllCaches()` which:
1. Calls `closeFSEQ()` to clear the FSEQ path
2. Resets `_renderedData` to clear the pre-rendered path
3. Resets `_liveCoordinator` to clear persistent effect state
4. This forces the next `renderFrame()` to use live rendering

## Live Rendering Flow (Step by Step)

```
1. Timer fires (GCD dispatch_source or audio player callback)
      |
2. XLPlaybackController::playbackTimerFired
   - Calculates wall-clock position
   - Snaps to frame boundary
   - Calls renderFrameAtTime: (drops frame if _renderInProgress)
      |
3. Dispatches to serial _renderQueue (background thread)
      |
4. [bridge renderFrame:timeMS] --> RenderEngine::renderFrame()
   - Creates _liveCoordinator on first call
   - Detects backward scrub --> resets persistent state
   - Iterates all model names from _modelProvider
      |
5. For each model: _liveCoordinator->renderModelFrameStateful(name, timeMS)
   - Checks _skippedModels cache (fast reject for inactive models)
   - Looks up or creates persistent ModelJob in _persistentJobs map
   - Calls renderModelAtTime(job, timeMS) --> runs effect for each layer
   - Calls NativePixelBuffer::calcOutput() to blend layers
   - Extracts RGBA pixels via getBlendedPixel()
   - Returns RenderedFrame --> stored in _bufferCache
      |
6. [bridge getAllFrameBuffers] --> single-lock bulk read of _bufferCache
      |
7. Dispatch to main thread --> XLMetalPreviewView updates
   - setRenderedPixels:forModel: stores pixel data per model
   - Increments _pixelDataGeneration
   - updatePreviewForTime: rebuilds vertex buffer if generation changed
   - buildModelVerticesWithEffectColors: maps pixel data to node colors
   - Models without pixel data show as black (off) during playback
```

## Batch Rendering Flow (Render All)

```
1. XLEngineBridge::renderAll dispatches to background queue
      |
2. RenderEngine::renderAll(callback)
   - Creates NativeSequenceData (numChannels * numFrames bytes)
   - Creates NativeRenderCoordinator (one-shot, not persistent)
   - Calls coordinator->renderAll(output)
      |
3. NativeRenderCoordinator::renderAll()
   - Builds ModelJobs from IEffectProvider elements
   - For each model, renders all frames sequentially
   - NativePixelBuffer::getColors() writes channel data to NativeSequenceData
      |
4. Post-completion in RenderEngine::renderAll():
   - Builds _modelChannelMap for playback path
   - Stores _renderedData for in-memory playback
      |
5. XLEngineBridge exports FSEQ file:
   - NativeSequenceData::exportToFSEQ() writes V2 format with zstd compression
```

## Key Classes in Detail

### RenderEngine
Top-level API. Owns:
- `_fseqFile` -- loaded FSEQ for playback
- `_renderedData` -- NativeSequenceData from last renderAll()
- `_liveCoordinator` -- persistent coordinator for live preview
- `_bufferCache` -- map of model name to FrameBuffer (RGBA pixels)
- `_modelChannelMap` -- maps model names to channel offsets for FSEQ/pre-rendered paths

Thread safety: `_bufferCacheMutex` protects `_bufferCache`. All public methods are thread-safe.

### NativeRenderCoordinator
Manages per-model render jobs. Two modes of operation:

**Batch mode** (`renderAll`/`renderRange`): Creates ModelJobs, renders all frames, writes to NativeSequenceData. Jobs are discarded after completion.

**Live mode** (`renderModelFrameStateful`): Persistent ModelJobs stored in `_persistentJobs` map. Effect state (infoCache) survives across frames. `_skippedModels` set caches models with no effects for instant rejection.

### ModelJob (internal struct)
```cpp
struct ModelJob {
    ModelGeometry geometry;          // buffer dimensions, node positions
    size_t elementIndex;             // index into IEffectProvider
    size_t layerCount;               // number of effect layers
    unique_ptr<NativePixelBuffer> pixelBuffer;  // owns all layer buffers
};
```

### NativePixelBuffer
Per-model layer orchestrator. Owns N `NativeRenderBuffer` instances (one per layer). After effects render into each layer buffer:
1. `calcOutput()` blends all layers back-to-front using NativeColorBlending
2. Applies per-layer: blur, sparkle, HSV adjust, brightness, contrast
3. Stores blended result in `_outputPixels`

For batch rendering: `getColors()` maps blended pixels to channel data via node info.
For live rendering: `getBlendedPixel(x, y)` reads individual pixels for RGBA extraction.

### NativeRenderBuffer
The buffer that effects render into. Provides the same API as legacy `RenderBuffer`:
- `SetPixel(x, y, color)` / `GetPixel(x, y)`
- `DrawLine()`, `DrawCircle()`, `Fill()`
- `GetMultiColorBlend()`, `GetEffectTimeIntervalPosition()`
- `palette` (PaletteClass), `infoCache` (per-effect state), `needToInit`
- `BufferWi`, `BufferHt`, `curPeriod`, `curEffStartPer`, `curEffEndPer`

### NativeSequenceData
Flat byte array: `numFrames * numChannels`. Used by batch rendering to accumulate all channel data, then exported to FSEQ V2 with zstd compression.

## Native Effect Rendering

Effects are implemented in `NativeRenderCoordinator::renderNativeEffect()` (in NativeRenderCoordinator.cpp). Currently 45+ effects are implemented as inline blocks. The pattern:

```cpp
bool NativeRenderCoordinator::renderNativeEffect(
    const EffectInstanceInfo& effectInfo, NativeRenderBuffer& buf)
{
    if (type == "Fire") {
        // 1. Read settings from effectInfo.settings map
        // 2. Read/create persistent state from buf.infoCache[0]
        // 3. Render pixels via buf.SetPixel(x, y, color)
        return true;
    }
    // ... more effects
    return false; // unrecognized effect
}
```

Effect settings come from `EffectInstanceInfo::settings` (string key-value map with keys like `E_SLIDER_Fire_Height`). Palette colors come from `EffectInstanceInfo::palette`, parsed into `buf.palette` before the effect runs.

### Stateful Effects
Some effects (Fire, etc.) store per-frame state in `buf.infoCache[N]`:
```cpp
struct FireCache : public EffectRenderCache {
    std::vector<int> fireBuffer;
    int maxWi, maxHt;
};
FireCache* cache = dynamic_cast<FireCache*>(buf.infoCache[0]);
if (!cache) {
    cache = new FireCache();
    buf.infoCache[0] = cache;
}
```
This state persists across frames in live preview mode because ModelJobs are persistent in `_persistentJobs`. The `buf.needToInit` flag tells the effect when to reinitialize (first frame only).

## Performance Architecture

### Skip Cache Optimization
With 200 models but only ~4 having effects, the skip cache (`_skippedModels` set in NativeRenderCoordinator) avoids expensive geometry extraction + element lookup for inactive models. Without it, iterating 200 models cost ~90ms/frame; with it, ~10ms/frame.

Key invariant: `_skippedModels` is cleared whenever `resetPersistentState()` is called (on effect edits, backward scrub, or cache invalidation).

### Frame Drop Protection
`XLPlaybackController` uses a `_renderInProgress` flag to drop frames when the render queue is backed up. This prevents queue growth at the cost of visual smoothness. Diagnostics log drop rates via `[FrameDrop]` messages.

### Bulk Buffer Collection
`getAllFrameBuffers()` on RenderEngine returns all valid FrameBuffers in a single mutex lock. The bridge method `[XLEngineBridge getAllFrameBuffers]` converts these to NSDictionary arrays for the preview. This replaces per-model `getFrameBuffer()` calls that each required their own lock/unlock cycle.

### Metal Preview Vertex Rebuild
`XLMetalPreviewView::buildModelVerticesWithEffectColors:` rebuilds the vertex buffer for ALL models whenever pixel data changes (tracked by a generation counter). During playback:
- Models WITH pixel data get their rendered colors
- Models WITHOUT pixel data are drawn as black (off)
- In non-playback mode, models use layout colors

This is a potential future optimization target: only update vertices for models whose pixels actually changed.

## Cache Invalidation Flow

```
Effect edited in UI
    |
    v
XLEngineBridge::scheduleAutoSave
    |
    v
RenderEngine::invalidateAllCaches()
    |
    +--> closeFSEQ()              -- clears FSEQ path
    +--> _renderedData.reset()    -- clears pre-rendered path
    +--> _liveCoordinator.reset() -- clears persistent live state + skip cache
    +--> _bufferCache.clear()     -- clears cached frame buffers
    |
    v
Next renderFrame() creates fresh _liveCoordinator
    --> Models re-evaluated for effects
    --> _skippedModels rebuilt on first frame
```

## Diagnostic Logging

The pipeline includes diagnostic logging (controlled by thresholds, not feature flags):

| Log Tag | Source | What It Shows |
|---------|--------|---------------|
| `[LiveRender] Model '...'` | RenderEngine.cpp | Per-model render time (>2ms threshold) |
| `[LiveRender] Frame @...` | RenderEngine.cpp | Total frame render time, model count, budget |
| `[FrameDrop]` | XLPlaybackController.m | Dropped frame count and percentage |
| `[RenderPipeline]` | XLPlaybackController.m | Render vs collect time breakdown (>40ms threshold) |

## Common Tasks

### Adding a New Native Effect
1. Add an `if (type == "YourEffect")` block in `NativeRenderCoordinator::renderNativeEffect()`
2. Read settings from `effectInfo.settings` (keys match `E_SLIDER_*`, `E_CHECKBOX_*`, `E_CHOICE_*`, etc.)
3. Read palette via `buf.palette.GetColor(idx, color)`
4. Render pixels via `buf.SetPixel(x, y, color)`
5. For stateful effects, use `buf.infoCache[0]` with a struct inheriting from `EffectRenderCache`
6. Return `true` if the effect was handled

### Debugging Render Issues
1. Check console for `[LiveRender]` logs to see per-frame timing
2. Check for `[FrameDrop]` logs to detect frame budget overruns
3. Verify `invalidateAllCaches()` is called when effects change (scheduleAutoSave is the hook)
4. Check playback path priority: FSEQ > pre-rendered > live
5. For stateful effects: verify `buf.infoCache` persists (ModelJob must be in `_persistentJobs`)
6. For "still playing old data after edit": check that `closeFSEQ()` runs in `invalidateAllCaches()`

### Build and Test
```bash
# Build native scheme (NOT the wxWidgets "xLights" scheme)
xcodebuild -project macOS/xLights.xcodeproj -scheme "xLights Native" -configuration Debug build
```

## Known Limitations
- Live rendering is single-threaded across models (batch rendering uses parallel dispatch)
- No ValueCurve support in native effects (settings are static per-effect, not animated over time)
- No GrowWithMusic / audio-reactive parameters in native effects
- Metal preview rebuilds all vertices on any pixel change (not incremental per-model)
- `getAllFrameBuffers()` copies pixel data; a future optimization could use shared memory

## Comparison with Legacy xLights

| Aspect | Legacy (wxWidgets) | Native (AppKit/Metal) |
|--------|-------------------|----------------------|
| Effect rendering | `RenderableEffect::Render()` via `EffectManager` | `renderNativeEffect()` inline in coordinator |
| Pixel buffer | `PixelBufferClass` (wx-dependent) | `NativePixelBuffer` (pure C++) |
| Render buffer | `RenderBuffer` (uses wxImage internally) | `NativeRenderBuffer` (std::vector<xlColor>) |
| Layer blending | `PixelBuffer::MixLayers()` | `NativePixelBuffer::calcOutput()` |
| Live preview | Multi-threaded via `JobPool` | Single-threaded sequential (persistent coordinator) |
| Batch render | Multi-threaded via `JobPool` | Multi-threaded via `dispatch_apply` |
| Output format | FSEQ V2 via `FSEQFile` | Same FSEQ V2 via `FSEQFile` |
| Preview display | OpenGL (wxGLCanvas) | Metal (XLMetalPreviewView) |
| Effect state | `buffer.infoCache[]` on `RenderBuffer` | Same pattern on `NativeRenderBuffer` |
| Cache invalidation | Per-model via render cache system | `invalidateAllCaches()` clears all paths |
