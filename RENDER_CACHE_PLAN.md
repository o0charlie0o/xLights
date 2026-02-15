# Render Caching & Near-Real-Time Performance System

## Context

Render All currently takes ~5s for a 192-model, 8365-frame sequence (down from 54s after prior optimizations). However, **any** effect parameter change triggers `invalidateAllCaches()` which destroys ALL prerendered data — making a second Render All take the full 5s even if only one effect changed or nothing changed at all.

The goal is to make rendering feel near-real-time: instant re-renders when nothing changed, sub-second re-renders when a single effect changed, and pre-rendering in the background so Render All is already done before the user clicks it.

## Current Architecture

- `RenderEngine` owns `_renderedData` (`unique_ptr<NativeSequenceData>`) — flat `uint8_t` array: frames x channels
- `NativeRenderCoordinator::renderAllFrames()` renders all models per frame via GCD `dispatch_apply`
- In-memory LRU cache (`RenderFrameCache`, 8192 entries) — useful for live scrub, too small for batch
- Legacy xLights has disk-based `RenderCache` in `ShowFolder/RenderCache/` with mmap on macOS

### The Nuclear Option Problem
```
User edits slider → XLEngineBridge.setEffectParameter()
  → scheduleAutoSave() → RenderEngine::invalidateAllCaches()
    → _renderedData.reset()        // destroys ALL rendered frames
    → _liveCoordinator.reset()     // destroys ALL persistent jobs
    → _bufferCache.clear()         // destroys live preview cache
```
Every single parameter change wipes everything. Second Render All: full 5s.

---

## Phase 1: Model-Level Dirty Tracking (P0 — Critical)

**Impact**: Second Render All with no changes = instant (0ms). Single effect edit = re-render only 1 model (~26ms).

### 1.1 Add dirty tracking to RenderEngine
### 1.2 Replace nuclear invalidation in scheduleAutoSave
### 1.3 Wire up EffectEngineListener on RenderEngine
### 1.4 Incremental renderAll()

## Phase 2: Disable LRU Cache in Batch Mode (P1 — Quick Win)

**Impact**: Eliminates cache overhead during Render All (~5-10% savings).

## Phase 3: Parallel Job Preparation (P1 — Quick Win)

### 3.1 Pre-build group membership map
### 3.2 Parallelize submodel mask computation
### 3.3 Cache geometry extraction

## Phase 4: Incremental Background Rendering (P2 — Major UX)

### 4.1 BackgroundRenderQueue class
### 4.2 Integration with dirty tracking
### 4.3 Render All integration

## Phase 5: Disk-Backed Effect Cache (P3 — Persistence)

### 5.1 Pass show folder path to engine
### 5.2 DiskRenderCache class
### 5.3 Integration with renderModelAtTime
### 5.4 Cache lifecycle

## Implementation Order & Dependencies

```
Phase 1: Model-Level Dirty Tracking ─────────────────── P0 (Critical)
    │
    ├── Phase 2: Disable LRU in Batch ───────────────── P1 (Quick Win, independent)
    │
    ├── Phase 3: Parallel Job Preparation ───────────── P1 (Quick Win, independent)
    │
    ├── Phase 4: Background Rendering ───────────────── P2 (depends on Phase 1)
    │
    └── Phase 5: Disk-Backed Cache ──────────────────── P3 (depends on Phase 1)
```
