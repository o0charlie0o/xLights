# Native macOS Render Pipeline Audit (Groups + Submodels)

Date: 2026-02-14  
Branch under review: `feature/native-macos-rebuild`  
Legacy baseline: `master`

## Scope

This audit focuses on parity between legacy and native rendering for:

1. House preview and model preview behavior.
2. Live playback path.
3. Render-to-buffer (`renderAll` / `renderRange`) path.
4. FSEQ playback of rendered/exported data.
5. Group effects where group members include submodel references (`ParentModel/Submodel`).

## Executive Summary

The main bug you described is real and reproducible by code inspection:

1. Submodel masking is applied to preview pixels in live/stateful rendering, but **not** to channel output during `renderAll`/`renderRange`.
2. Because FSEQ/prerender playback reads channel data, this causes the full parent model to light instead of only the intended submodel nodes.

Additional parity gaps were found:

1. FSEQ/prerender sidebar submodel buffers are not freshly generated for submodel refs, so those requests may return empty or stale data.
2. Nested groups are matched recursively, but submodel mask derivation is not recursive; nested group members can bypass masking.
3. Native effect-source selection is single-source (`model OR one group`), while legacy render tree supports layered interactions from overlapping rows/channels.

## Legacy vs Native: Key Behavioral Difference

Legacy (`master`) renders rows with channel-overlap dependency handling and explicitly processes submodel layers as part of model rendering:

1. `master:xLights/Render.cpp:259` through `master:xLights/Render.cpp:281` initializes submodel/strand buffers.
2. `master:xLights/Render.cpp:858` through `master:xLights/Render.cpp:869` processes model + submodel layers per frame.
3. `master:xLights/Render.cpp:1413` through `master:xLights/Render.cpp:1460` builds render-tree ordering/dependencies for overlapping channel ranges.
4. `master:xLights/models/ModelGroup.cpp:66` through `master:xLights/models/ModelGroup.cpp:93` recursively flattens nested groups.

Native path currently does not fully replicate these semantics in range/FSEQ playback paths.

## Findings

### 1) P0: Submodel mask is not applied when writing rendered channel data

Impact:

1. `renderAll`/`renderRange` output contains full-parent model data when effect source is a group containing only submodel refs.
2. FSEQ export and prerender playback then light the full model, not just submodel nodes.

Evidence (native):

1. Mask is computed in job setup:
   - `xLights/engine/render/NativeRenderCoordinator.cpp:527`
   - `xLights/engine/render/NativeRenderCoordinator.cpp:560`
2. Mask is applied only to RGBA preview pixels in stateful preview path:
   - `xLights/engine/render/NativeRenderCoordinator.cpp:430`
3. Channel write path ignores mask and always writes full node set:
   - `xLights/engine/render/NativeRenderCoordinator.cpp:15630`
   - `xLights/engine/render/NativeRenderCoordinator.cpp:15638`
   - `xLights/engine/render/NativePixelBuffer.cpp:573`

Why this diverges from legacy:

1. Legacy pipeline writes channel results after submodel/strand processing in the same render frame flow (`master:xLights/Render.cpp:858`, `master:xLights/Render.cpp:917`, `master:xLights/Render.cpp:919`).
2. Native mask logic currently exists only in preview pixel post-processing, not in output channel serialization.

Recommended fix:

1. Apply submodel mask during `writeModelOutput(...)` for masked jobs.
2. For masked jobs, write channels per node with mask check against `(bufX, bufY)` and write black/zero for excluded nodes.
3. Keep existing `getColors(...)` fast path for unmasked jobs.

## 2) P1: FSEQ/prerender submodel frame requests are not synthesized per submodel

Impact:

1. In playback modes (`_fseqLoaded` or `_renderedData`), `renderModelFrame("Parent/Sub", time)` routes to `renderFrame(time)` and does not generate a submodel-specific framebuffer.
2. `getFrameBuffer("Parent/Sub")` can return empty or stale sidebar cache data.

Evidence (native):

1. Playback path in `renderModelFrame` for submodel refs only calls `renderFrame(timeMS)`:
   - `xLights/engine/RenderEngine.cpp:833`
   - `xLights/engine/RenderEngine.cpp:843`
   - `xLights/engine/RenderEngine.cpp:850`
2. Model channel map is built from top-level model names only:
   - `xLights/engine/RenderEngine.cpp:419`
   - `xLights/native-mac/providers/NativeModelProvider.mm:515`
3. Sidebar preview requests submodel refs directly:
   - `xLights/native-mac/XLMainContentView.swift:1283`
   - `xLights/native-mac/XLMainContentView.swift:1284`
4. `getFrameBuffer` checks sidebar cache first, then main cache:
   - `xLights/engine/RenderEngine.cpp:1116`
   - `xLights/engine/RenderEngine.cpp:1123`
   - `xLights/engine/RenderEngine.cpp:1131`

Recommended fix:

1. Add a submodel framebuffer synthesis step in `RenderEngine::renderModelFrame` for playback/prerender modes when `modelName` contains `/`.
2. Sequence:
   - call `renderFrame(timeMS)` (already done);
   - build submodel buffer from current channel frame using parent model channels + submodel node filtering;
   - store result in `_sidebarCache[modelName]` with current `timeMS`.
3. If synthesis fails, explicitly erase stale `_sidebarCache[modelName]` so stale frames cannot persist.

## 3) P1: Nested group membership is recursive, but submodel mask derivation is not

Impact:

1. A model can be matched to a parent group via nested membership.
2. Mask derivation then reads only direct member list of the matched group and may miss nested submodel refs.
3. Result: full model lights when nested group should constrain to submodel nodes.

Evidence (native):

1. Recursive membership check:
   - `xLights/engine/render/NativeRenderCoordinator.cpp:680`
   - `xLights/engine/render/NativeRenderCoordinator.cpp:733`
2. Non-recursive mask member scan uses only direct `models` string:
   - `xLights/engine/render/NativeRenderCoordinator.cpp:367`
   - `xLights/engine/render/NativeRenderCoordinator.cpp:532`

Recommended fix:

1. Introduce one shared helper in `NativeRenderCoordinator` to recursively resolve group leaf members (same idea as `ModelEngine` helper).
2. Use that helper in both:
   - `findParentGroupElement` membership logic;
   - submodel mask derivation logic.
3. Keep visited-set cycle protection, not just depth cap.

## 4) P2: Single-source effect selection (`model OR one group`) differs from legacy layering semantics

Impact:

1. Current native job selection chooses one effect source:
   - model effects if present, else one parent group.
2. Legacy rendering can combine influences across rows based on overlapping channel dependencies.
3. Edge cases with both model-level and group-level effects may not match legacy behavior.

Evidence:

1. Single-source selection in native:
   - `xLights/engine/render/NativeRenderCoordinator.cpp:497`
   - `xLights/engine/render/NativeRenderCoordinator.cpp:505`
2. Legacy render-tree dependency model:
   - `master:xLights/Render.cpp:1413` through `master:xLights/Render.cpp:1553`

Recommended improvement:

1. Short-term: document current precedence and add deterministic group selection ordering.
2. Mid-term: support layered composition from model + applicable groups in one model job (or equivalent dependency-aware pass).

## 5) P2: Cache hygiene risk when switching modes

Impact:

1. `closeFSEQ()` clears `_bufferCache` but not `_sidebarCache`.
2. Submodel sidebar entries can survive mode transitions and appear stale.

Evidence:

1. `xLights/engine/RenderEngine.cpp:156` through `xLights/engine/RenderEngine.cpp:167`
2. Full cache clear occurs only in `invalidateAllCaches()`:
   - `xLights/engine/RenderEngine.cpp:1236`
   - `xLights/engine/RenderEngine.cpp:1256`

Recommended fix:

1. Clear sidebar cache/coordinator on playback mode transitions where source data changes (`loadFSEQ`, `closeFSEQ`, and/or when entering prerender playback).
2. At minimum, clear per-request stale submodel entries when synthesis is not possible.

## Implementation Blueprint (Recommended Order)

1. **Fix output-mask correctness first (P0).**
   - File: `xLights/engine/render/NativeRenderCoordinator.cpp`
   - Change `writeModelOutput(...)` to branch:
     - unmasked -> existing `getColors(...)`
     - masked -> explicit per-node write with mask check

2. **Unify recursive group member resolution (P1).**
   - File: `xLights/engine/render/NativeRenderCoordinator.cpp`
   - Add helper returning flattened leaf members with recursion + visited-set.
   - Replace ad-hoc direct `parseMemberList(...)` mask scans.

3. **Add playback submodel framebuffer synthesis (P1).**
   - File: `xLights/engine/RenderEngine.cpp`
   - In `renderModelFrame(...)`, when in FSEQ/prerender path and `isSubRef`:
     - call `renderFrame(timeMS)`
     - synthesize `FrameBuffer` from `_currentFrameData` and parent/submodel geometry
     - save to `_sidebarCache[modelName]`

4. **Cache hygiene hardening (P2).**
   - File: `xLights/engine/RenderEngine.cpp`
   - Ensure mode transitions clear stale sidebar cache entries.

5. **Legacy parity enhancement for model+group layering (P2/P3).**
   - File: `xLights/engine/render/NativeRenderCoordinator.cpp`
   - Expand effect source logic beyond single-source fallback.

## Validation Matrix

Run these tests in both live and prerender/FSEQ playback modes.

1. Group contains only `Parent/SubA` and `Parent/SubB` refs, no direct `Parent` member.
   - Expected: only SubA+SubB nodes light, never full parent.

2. Same as #1 but nested groups (`OuterGroup -> InnerGroup -> Parent/SubA`).
   - Expected: same masked output as direct membership.

3. Parent model has direct effects and also belongs to effect-bearing group.
   - Record expected legacy behavior on `master`, compare native output frame-by-frame.

4. Sidebar preview selected model is a group containing submodel refs during playback.
   - Expected: per-submodel framebuffers are fresh and time-synchronous.

5. Render All -> export FSEQ -> load FSEQ -> playback.
   - Expected: identical mask behavior to live rendering for group/submodel cases.

6. Scrub backward and forward in playback after live preview interactions.
   - Expected: no stale sidebar submodel frame reuse from previous mode/time.

## Notes for the Implementing Agent

1. Prioritize correctness in channel output first; preview-only fixes do not solve FSEQ behavior.
2. Keep fast paths for unmasked models to avoid regressions in bulk render performance.
3. Reuse existing shared utilities where possible:
   - `generateNodesFromAttributes(...)` and `filterNodesToSubmodel(...)` from `xLights/engine/ModelEngine.h`.
4. Preserve current thread-safety assumptions around `_bufferCacheMutex` and `_sidebarCacheMutex`.

