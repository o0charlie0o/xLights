# Render Engine Audit — Post-Edit Playback Glitches

**Date**: 2026-02-15
**Branch**: `feature/native-macos-rebuild`
**Symptom**: Playback works correctly on initial sequence load. After any edit, playback becomes glitchy and incorrect. Restarting the app and reloading the same sequence fixes it.

---

## Root Cause Summary

The bug is a cascade of 3 interacting problems:

1. **`renderAll` bails when `totalChannels == 0`** — the smoking gun
2. **`forceRenderAll` destroys all render state before proving re-render success** — makes the bail permanent
3. **Live rendering fallback has stale caches** — produces incorrect pixel data

### The Full Cascade

1. **Open sequence** → `loadFSEQForSequence` loads FSEQ → `_fseqLoaded = true` → playback reads pre-rendered FSEQ → works perfectly
2. **Edit any effect** → `onEffectSettingChanged` → `invalidateModelAndGroup` → dispatches `forceRenderAll` on background thread
3. **`forceRenderAll` destroys everything** (RenderEngine.cpp:1484-1491): `_renderedData.reset()`, `_fseqFile.reset()`, `_fseqLoaded = false`, `_modelChannelMap.clear()`
4. **`renderAll` bails immediately** (RenderEngine.cpp:1633): `totalChannels == 0` from `_outputProvider->getTotalChannels()` → early return, no new `_renderedData` produced
5. **`renderFrame` path selection** — FSEQ gone, pre-rendered data gone, falls to live path (path 3)
6. **Live path is slow** — renders ALL models per frame, can't keep up with frame budget → frame drops = "glitchy"
7. **Live path has stale coordinator caches** — `_groupMapBuilt` not reset, submodel jobs leak → incorrect pixel data
8. **Restart** → FSEQ file still on disk → `loadFSEQForSequence` loads it fresh → works again

---

## Issue 1: `renderAll` Bails on Zero Output Channels (CRITICAL)

**Location**: `RenderEngine.cpp:1631-1639`

```cpp
int32_t totalChannels = _outputProvider ? _outputProvider->getTotalChannels() : 0;

if (numFrames <= 0 || totalChannels <= 0) {
    // BAILS — never reaches computeRequiredChannels() at line 1643
    _renderInProgress.store(false, std::memory_order_release);
    return;
}

// This would fix it but is unreachable:
int32_t requiredChannels = computeRequiredChannels();  // line 1643
if (requiredChannels > totalChannels) {
    totalChannels = requiredChannels;
}
```

`NativeOutputProvider::getTotalChannels()` (NativeOutputProvider.mm:1069-1083) sums `config.channels` from active controllers. Since the Setup tab is largely a TODO, there are zero configured controllers → returns 0.

`computeRequiredChannels()` derives channel count from model start channel attributes and would produce a valid number, but it's unreachable because the bail happens first.

**Fix**: Move `computeRequiredChannels()` before the bail check, or use `max(totalChannels, computeRequiredChannels())` for the check.

---

## Issue 2: `forceRenderAll` Destroys State Before Proving Re-render (CRITICAL)

**Location**: `RenderEngine.cpp:1464-1528`

Every effect edit dispatches `forceRenderAll` via `invalidateModelAndGroup` (line 2292):
```cpp
dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    this->forceRenderAll(nullptr);
});
```

`forceRenderAll` unconditionally destroys all render state BEFORE calling `renderAll`:
- Line 1484: `_bgRenderQueue.reset()`
- Line 1489: `_renderedData.reset()`
- Line 1490: `_fseqFile.reset()`
- Line 1491: `_fseqLoaded = false`
- Line 1496: `_modelChannelMap.clear()`
- Line 1499: `_liveCoordinator.reset()`

If `renderAll` then fails (e.g., totalChannels == 0), there's no fallback — all pre-rendered data is gone.

**Fix**: Don't destroy old state until the new render succeeds. Or: don't use the nuclear `forceRenderAll` on every edit — use incremental dirty tracking instead.

---

## Issue 3: Dirty State TOCTOU — Edits During Render Silently Lost (CRITICAL)

**Location**: `RenderEngine.cpp:1849-1854`

`renderAll()` clears ALL dirty models at the end, even ones dirtied DURING the render:

```cpp
{
    std::lock_guard<std::mutex> lock(_dirtyMutex);
    _allDirty.store(false);
    _dirtyModels.clear();  // ← Wipes models dirtied AFTER render started
}
```

**Scenario**: Edit A → `forceRenderAll` starts (takes seconds). During render, edit B → `invalidateModel("B")` adds B to `_dirtyModels`. Render may have already processed B with OLD parameters. When render finishes, it clears `_dirtyModels` — B is "clean" with stale data.

Same issue on the incremental path (line 1694-1698).

**Fix**: Only clear models that were actually rendered, not all dirty models. Snapshot the dirty set at render start, clear only those at end.

---

## Issue 4: Thread Safety Gaps Between `renderFrame` and `forceRenderAll` (HIGH)

**Location**: `RenderEngine.cpp:740-1122` vs `1464-1528`

`renderFrame()` runs on the playback render queue. `forceRenderAll()` runs on `dispatch_get_global_queue()`. Between `invalidateModel` (which sets `_currentFrameIndex = -1`) and `forceRenderAll` starting (which sets `_renderInProgress = true`), there's a window where:

- `_renderInProgress` is still false → `renderFrame` runs
- `_fseqLoaded` may still be true → reads stale FSEQ data
- `_currentFrameIndex = -1` → forces re-read of stale frame

Additionally, `forceRenderAll` destroys `_fseqFile` (line 1490) without holding `_bufferCacheMutex` — if `renderFrame` is mid-read on the FSEQ path, it's a use-after-free risk.

**Fix**: Either serialize access with a mutex, or use the `_renderInProgress` flag more carefully (set it in `invalidateModelAndGroup` before dispatching, not inside `forceRenderAll`).

---

## Issue 5: NativeRenderCoordinator Stale Caches (MEDIUM)

**Location**: `NativeRenderCoordinator.cpp`

When `resetPersistentState(modelName)` is called:

### 5a: `_groupMapBuilt` flag never reset (line ~1131)

`preparePersistentJobs()` skips `buildGroupMembershipMap()` when `_groupMapBuilt == true`. But `resetPersistentState` doesn't set `_groupMapBuilt = false`. After edits, the group membership map is stale → group effects don't cascade correctly.

**Fix**: Set `_groupMapBuilt = false` in `resetPersistentState()`.

### 5b: Submodel persistent jobs leak (line ~1883-1892)

`resetPersistentState("ModelA")` erases `_persistentJobs["ModelA"]` but NOT `_persistentJobs["ModelA/Outline"]`, `_persistentJobs["ModelA/Trunk"]`, etc. Stale submodel pixel data persists.

**Fix**: Iterate and erase all entries with prefix `modelName + "/"`.

### 5c: `_skippedModels` cache wrong after edits

A model marked "no effects" stays in `_skippedModels` even after effects are added to it via editing. `resetPersistentState` does erase the entry, but if a different model's group membership changes, the cache can be wrong.

### 5d: `_geometryCache` doesn't cascade to submodels

`resetPersistentState` erases `_geometryCache[modelName]` but not submodel entries.

**Fix**: Same prefix-based cascade as 5b.

---

## Issue 6: Duplicate Parameter Writes Amplify Render Churn (MEDIUM)

**Location**: `XLEffectPanelView.m:768` and `XLEffectPropertiesViewController.m:163`

Inspector parameter edits are written twice — once directly by `XLEffectPanelView` and again by the delegate path through `XLEffectPropertiesViewController`. Sliders are continuous (`XLEffectPanelView.m:434`), so rapid slider drags produce many duplicate `invalidateModelAndGroup` calls, each dispatching `forceRenderAll`.

**Fix**: Remove the duplicate write path. Use coalescing/debouncing for continuous slider updates.

---

## Issue 7: `_modelChannelMap` Not Rebuilt on Incremental Path (MEDIUM)

**Location**: `RenderEngine.cpp:1694-1711`

The incremental render path (when only some models are dirty) does NOT rebuild `_modelChannelMap` after completing. The full render path does (line 1827-1830). If the map was cleared for any reason, the PRERENDERED path's condition check fails:

```cpp
} else if (_renderedData && _renderedData->isValid() && !_modelChannelMap.empty()) path = 2;
//                                                        ^^^^^^^^^^^^^^^^^^^^^^^^ fails!
```

Falls to live path silently.

**Fix**: Ensure incremental path preserves or rebuilds `_modelChannelMap`.

---

## Issue 8: Background Auto-Render Toggle Not Wired (LOW)

**Location**: `XLSequencerViewController.m:8653`

There's a TODO for a "background auto-render" toggle. Currently the expensive edit-time rerender path cannot be disabled by the user.

---

## Fix Priority Order

| Priority | Issue | Impact | Effort |
|----------|-------|--------|--------|
| P0 | Move `computeRequiredChannels()` before bail check | Fixes the smoking gun — renderAll actually produces data | Small |
| P0 | Stop dispatching `forceRenderAll` on every edit | Eliminates nuclear option, prevents state destruction | Medium |
| P1 | Fix dirty state TOCTOU (snapshot dirty set) | Prevents silent data loss during concurrent edits | Small |
| P1 | Reset `_groupMapBuilt` in `resetPersistentState()` | Fixes incorrect group rendering on live path | Tiny |
| P1 | Cascade submodel cleanup in `resetPersistentState()` | Fixes stale submodel pixels on live path | Small |
| P2 | Thread safety for `_fseqFile` destruction | Prevents potential crash/corruption | Medium |
| P2 | Deduplicate inspector parameter writes | Reduces render churn from sliders | Small |
| P2 | Rebuild `_modelChannelMap` on incremental path | Prevents silent fallback to live path | Small |
| P3 | Wire background auto-render toggle | User control over edit-time rendering | Small |

---

## Key Files

| File | Role |
|------|------|
| `xLights/engine/RenderEngine.cpp` | Core render pipeline — `renderAll`, `forceRenderAll`, `renderFrame`, `invalidateModel` |
| `xLights/engine/RenderEngine.h` | RenderEngine class definition, member variables |
| `xLights/engine/render/NativeRenderCoordinator.cpp` | Per-model rendering, persistent state, group maps, caches |
| `xLights/engine/render/NativeRenderCoordinator.h` | Coordinator class definition |
| `xLights/native-mac/XLPlaybackController.m` | Playback render loop, frame collection |
| `xLights/native-mac/XLEngineBridge.mm` | Bridge — FSEQ loading, effect edit methods, `scheduleAutoSave` |
| `xLights/native-mac/providers/NativeOutputProvider.mm` | `getTotalChannels()` — returns 0 when no controllers configured |
| `xLights/native-mac/sequencer/XLSequencerViewController.m` | Grid event handlers for effect move/resize |
| `xLights/native-mac/effects/XLEffectPanelView.m` | Inspector parameter editing (duplicate writes) |
| `xLights/native-mac/XLEffectPropertiesViewController.m` | Delegate parameter writes (duplicate) |

---

## Relevant Commit History

| Commit | Message | Notes |
|--------|---------|-------|
| `d47256754` | Fix UI lockup and nested group expansion on effect edit | Most recent — fixed lockup but not glitches |
| `e2af36e76` | Fix group model detection: add DisplayAs attr when loading from XML | |
| `5ed5019f8` | Fix group model invalidation and avoid wasteful 1GB overlay allocation | |
| `ab3aca38b` | Implement FSEQ overlay for incremental effect re-rendering | Added overlay system |
| `7946e3126` | Fix glitchy playback after effect changes by clearing stale FSEQ path | Tried to fix by clearing `_fseqLoaded` |
| `8c118d423` | Fix glitchy playback after Render All with thread safety guards | |
| `69ed905d9` | Fix glitchy playback and missing progress indicator for Render All | |
| `7f3f5c4de` | Close stale FSEQ after Render All so preview uses fresh rendered data | |
| `1686c0f0c` | Fix stale preview: zero dirty model channels instead of live path fallback | |
| `8801a8701` | Fix stale preview after effect edits by checking dirty models | |

Pattern: Multiple attempts to fix the same glitchy playback issue, each addressing a symptom rather than the root cause (renderAll bailing on 0 channels).
