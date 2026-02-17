# Native Model Sizing Reference

This document tracks the model node generation logic in the native macOS build (`ModelEngine.cpp`, `#ifdef XLIGHTS_NATIVE` section) and how it maps to the legacy wxWidgets model classes.

## Overview

The native build generates node positions directly in world coordinates from XML attributes, bypassing the legacy `Model` class hierarchy and `BoxedScreenLocation` transform. The function `generateNodesFromAttributes()` in `ModelEngine.cpp` handles all model types.

In the legacy code, models generate coordinates in "model space" and then `BoxedScreenLocation` transforms them to world space using `ScaleX`/`ScaleY`. In the native code, `ScaleX`/`ScaleY` are applied directly during node generation.

## Model-Specific Sizing

### Circle / Wreath

**Legacy class**: `CircleModel::SetCircleCoord()` (models/CircleModel.cpp)

**Key formula**:
- `maxLights = maxSize()` — returns the max node count across all layers
- `maxRadius = maxLights / 2.0`
- `minRadius = (parm3 / 100.0) * maxRadius` — parm3 is center hole percentage
- Ring radii interpolate linearly from `maxRadius` (outer) to `minRadius` (inner)

**Native implementation**:
- Uses `maxLayerSize / 2` for outer radius (not `totalNodes / 2`)
- `centerPct = parm3 / 100` for inner radius
- Coordinates: `wx + radius * cos(angle) * scaleX`

**Example** (Wreath with LayerSizes="50,50,50", parm3=50):
- maxLayerSize = 50, maxRadius = 25, minRadius = 12.5
- Ring radii: 25, 18.75, 12.5

**Known issue**: The legacy `BoxedScreenLocation` transform may apply an additional scaling factor (`scalex / (RenderWi/2)`) that we don't replicate. For the wreaths with ScaleX=1.0 this doesn't matter, but models with non-unit ScaleX may be slightly off.

### Tree (Tree 180, Tree 360, Tree Flat)

**Legacy class**: `TreeModel::SetTreeCoord()` (models/TreeModel.cpp)

**Key formula**:
- `RenderHt = BufferHt * 3` (BufferHt = pixelsPerStrand)
- `RenderWi = RenderHt / 1.8`
- `baseRadius = RenderWi / 2`
- `topRadius = baseRadius / TreeBottomTopRatio` (default 6.0)
- Y coordinates span `-RenderHt/2` to `+RenderHt/2`

**Native implementation**:
- Uses the same `* 3` height multiplier and `/1.8` width ratio
- Cone interpolates from baseRadius (bottom) to topRadius (top)
- `scaleX` applied to X, `scaleY` applied to Y

**Example** (Mega Tree: parm1=16, parm2=50, parm3=1, ScaleX=1.6741, ScaleY=2.1231):
- renderHt = 150, renderWi = 83.3, baseRadius = 41.7, topRadius = 6.9
- World height: 150 * 2.1231 = 318 units
- World base width: 2 * 41.7 * 1.6741 = 140 units

### Star

**Legacy class**: `StarModel::SetStarCoord()` (models/StarModel.cpp)

**Key formula**:
- Buffer size uses inflation: `maxLightsOnLayer = max(1 + layerSize * (1 + layersOutside/totalLayers))`
- `outerRadius = maxLightsOnLayer / 2`
- `innerPercent` defaults to `100 / layerCount` when not set (-1)
- `layerRadiusDelta = (outerRadius * (100 - innerPercent)) / (100 * (layerCount - 1))`
- Each layer's inner radius = outer / starRatio (default 2.618034)

**Native implementation**:
- Uses the same inflation formula for buffer size
- `starInnerPercent` attribute default is -1 (auto-calculate)
- Nodes distributed along star perimeter segments

**Example** (Small Star: LayerSizes="20,30", parm3=5):
- Inflation: layer 0 = 1+20*(1+0.5)=31, layer 1 = 1+30*(1+0)=31
- outerR = 15.5, innerPercent = 50, layerRadiusDelta = 7.75
- Layer 0: outerR=15.5, Layer 1: outerR=7.75

**Known issue**: The star sizing is close but not pixel-perfect compared to legacy. The legacy code's buffer size inflation formula accounts for circumferential node spreading in a way that may not translate perfectly to our direct world-coordinate approach. May need further refinement.

## BoxedScreenLocation Transform

The legacy `BoxedScreenLocation` maps model-space coordinates to world coordinates. Our native code skips this transform and applies `ScaleX`/`ScaleY` directly. The relationship between the two approaches:

- **Matrix**: `ScaleX` acts as per-node spacing. `worldX = wx + (col - center) * ScaleX`. This works correctly.
- **Circle/Star**: `ScaleX` multiplies the model-space radius. For ScaleX=1.0, model coords are used directly.
- **Tree**: `ScaleX` scales the X axis, `ScaleY` scales Y. The 3x height multiplier matches the legacy `RenderHt = BufferHt * 3`.

The exact legacy transform is: `worldCoord = center + modelCoord * scale_factor` where `scale_factor` may involve `ScaleX / (RenderWi / 2)` or just `ScaleX` depending on the model type. This mapping needs further investigation for models where ScaleX != 1.0 and the model has a non-trivial RenderWi.

## XML Attributes Reference

| Attribute | Used By | Meaning |
|-----------|---------|---------|
| `DisplayAs` | All | Model type identifier |
| `parm1` | All | Strings/strands/rings count |
| `parm2` | All | Nodes per string |
| `parm3` | Circle: center %, Star: points, Tree: strands per string |
| `LayerSizes` | Circle, Star | Comma-separated nodes per concentric layer |
| `ScaleX/ScaleY` | All BoxedScreenLocation models | Size/spacing multiplier |
| `WorldPosX/Y/Z` | All | Center position in world coordinates |
| `TreeBottomTopRatio` | Tree | Bottom-to-top radius ratio (default 6.0) |
| `starRatio` | Star | Outer-to-inner point ratio (default 2.618034) |
| `starInnerPercent` | Star | Inner layer size percentage (default -1 = auto) |
| `StarStartLocation` | Star | Starting point orientation |

## Files

- **Native node generation**: `xLights/engine/ModelEngine.cpp` — `generateNodesFromAttributes()`
- **Legacy Circle**: `xLights/models/CircleModel.cpp` — `SetCircleCoord()`
- **Legacy Tree**: `xLights/models/TreeModel.cpp` — `SetTreeCoord()`
- **Legacy Star**: `xLights/models/StarModel.cpp` — `SetStarCoord()`
- **Legacy screen location**: `xLights/models/ModelScreenLocation.h` — `BoxedScreenLocation`
