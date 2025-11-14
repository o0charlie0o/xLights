# Smart Tool Feature - Design and Implementation Guide

## Overview

The Smart Tool is a DAW-style (Digital Audio Workstation) feature that allows users to quickly adjust effect properties by clicking and dragging in specific regions of an effect, similar to tools found in Pro Tools, Logic Pro X, and other professional audio/video editing software.

**Key Benefits:**
- Fast workflow for adjusting fades and brightness without opening effect panels
- Visual, intuitive editing directly on the timeline
- Works with multiple selected effects simultaneously
- Non-disruptive: Activated only when Option/Alt key is held

## User Experience

### Activation
- **Modifier Key**: Hold **Option (macOS) / Alt (Windows/Linux)** while hovering over an effect
- **Default Behavior**: When Option/Alt is NOT held, all existing behavior remains unchanged
- **Visual Feedback**: Cursor changes to indicate which property can be adjusted

### Interaction Zones

When Option/Alt is held and hovering over an unlocked effect, the effect is divided into vertical zones:

```
┌─────────────────────────────────────┐
│  TOP 15%: FADE IN  │  FADE OUT      │ ← Green/Red fade indicators
├────────────────┬────────────────────┤
│                │                    │
│   MIDDLE 70%:  │   BRIGHTNESS       │ ← Vertical drag adjusts brightness
│                │                    │
├────────────────┴────────────────────┤
│  BOTTOM 15%: Normal resize edges    │ ← Existing edge resize still works
└─────────────────────────────────────┘
    ↑          ↑          ↑
  LEFT       CENTER      RIGHT
```

#### Zone Definitions

1. **Top-Left (Fade In Zone)**: Top 15% of effect height, left half horizontally
   - **Action**: Drag up/down to increase/decrease fade in duration
   - **Cursor**: Vertical resize (↕)
   - **Range**: 0.0 to 10.0 seconds

2. **Top-Right (Fade Out Zone)**: Top 15% of effect height, right half horizontally
   - **Action**: Drag up/down to increase/decrease fade out duration
   - **Cursor**: Vertical resize (↕)
   - **Range**: 0.0 to 10.0 seconds

3. **Middle-Center (Brightness Zone)**: Middle 70% of effect height, center 80% horizontally
   - **Action**: Drag up/down to increase/decrease brightness
   - **Cursor**: Vertical resize (↕)
   - **Range**: 0 to 100%

4. **Edges (Unchanged)**: Left/right edges continue to work as normal for duration resize
   - Existing behavior preserved even when Option/Alt is held

### Drag Sensitivity

- **Fade Adjustment**: 100 pixels vertical drag = 1.0 second fade change
- **Brightness Adjustment**: 2 pixels vertical drag = 1% brightness change
- **Direction**:
  - Drag UP = increase value (more fade, brighter)
  - Drag DOWN = decrease value (less fade, darker)
- **Limits**: Values clamped to valid ranges (cannot go negative or exceed maximums)

### Multi-Effect Editing

- When multiple effects are selected, Smart Tool adjusts ALL selected effects simultaneously
- Same delta applied to each effect (relative adjustment)
- Respects individual effect limits (won't exceed 100% brightness even if others can increase more)

### Undo Support

- Each Smart Tool drag operation creates ONE undo step (on mouseDown)
- Dragging continuously modifies effects but only creates single undo point
- Undo restores all effects to pre-drag state

## Technical Architecture

### File Structure

**Primary Files:**
- `xLights/sequencer/EffectsGrid.h` - Header with new enums, constants, and function declarations
- `xLights/sequencer/EffectsGrid.cpp` - Implementation of all Smart Tool logic

**Modified Functions:**
- `GetEffectAtRowAndTime()` - Extended to detect vertical zones when Option/Alt held
- `RunMouseOverHitTests()` - Updated to set cursor for new Smart Tool zones
- `mouseMoved()` - Modified to pass mouse Y position and detect Option/Alt state
- `mouseDown()` - Extended to initialize Smart Tool drag operations
- `Resize()` - Updated to handle Smart Tool adjustment modes

**New Functions:**
- `AdjustEffectFade()` - Handles fade in/out adjustment during drag
- `AdjustEffectBrightness()` - Handles brightness adjustment during drag
- `GetSmartToolZone()` - Helper to determine which zone mouse is in
- `DrawSmartToolHints()` - Visual feedback for Smart Tool zones (optional enhancement)

### Data Structures

#### New HitLocation Enum Values
```cpp
enum class HitLocation {
    NONE,
    LEFT_EDGE,
    LEFT_EDGE_DISCONNECT,
    LEFT,
    CENTER,
    RIGHT,
    RIGHT_EDGE_DISCONNECT,
    RIGHT_EDGE,
    // Smart Tool zones (only detected when Option/Alt held)
    SMART_FADE_IN,
    SMART_FADE_OUT,
    SMART_BRIGHTNESS
};
```

#### New Resize Mode Constants
```cpp
#define EFFECT_RESIZE_SMART_FADE 6
#define EFFECT_RESIZE_SMART_BRIGHTNESS 7
```

#### New Member Variables (EffectsGrid.h)
```cpp
private:
    int mSmartToolDragStartY;           // Initial Y position when Smart Tool drag starts
    float mSmartToolInitialValue;       // Initial fade/brightness value before drag
    HitLocation mSmartToolInitialZone;  // Which zone was clicked (fade in/out/brightness)
```

### Effect Settings Mapping

The Smart Tool modifies these SettingsMap keys:

**Fade In/Out:**
- `T_TEXTCTRL_Fadein` - Fade in duration (float, seconds)
- `T_TEXTCTRL_Fadeout` - Fade out duration (float, seconds)

**Brightness:**
- Priority 1: `E_TEXTCTRL_Eff_On_Start` and `E_TEXTCTRL_Eff_On_End` (On effect brightness, 0-100)
  - If these exist, adjust both by same delta to maintain ramp
- Priority 2: `C_SLIDER_Brightness` (General brightness slider, 0-100)
  - Used if On effect brightness not present
- Not supported: `C_VALUECURVE_Brightness` (Value curves too complex for simple drag)
  - Smart Tool brightness disabled if value curve is active

### Implementation Flow

#### 1. Mouse Hover Detection
```
mouseMoved()
  ↓
Check if Option/Alt key held (event.AltDown())
  ↓
If YES:
  Call GetEffectAtRowAndTime() with yPos parameter
    ↓
  GetEffectAtRowAndTime() calculates vertical zones
    ↓
  Returns SMART_FADE_IN, SMART_FADE_OUT, or SMART_BRIGHTNESS
    ↓
  RunMouseOverHitTests() sets wxCURSOR_SIZENS

If NO:
  Existing behavior (horizontal zones only)
```

#### 2. Mouse Down (Start Drag)
```
mouseDown()
  ↓
Check if mResizingMode is SMART_FADE or SMART_BRIGHTNESS
  ↓
If YES:
  Create undo step
  Store mSmartToolDragStartY = event.GetY()
  Store mSmartToolInitialZone = current HitLocation
  Store mSmartToolInitialValue = current effect's fade/brightness
  Set mResizing = true
  CaptureMouse()
```

#### 3. Mouse Drag (Adjust Values)
```
mouseMoved() [while mResizing == true]
  ↓
Resize()
  ↓
Check mResizingMode:

If EFFECT_RESIZE_SMART_FADE:
  Call AdjustEffectFade(currentYPos)
    ↓
  Calculate: dragDelta = currentYPos - mSmartToolDragStartY
  Calculate: fadeDelta = dragDelta / -100.0  (negative: up = increase)
  Calculate: newFade = mSmartToolInitialValue + fadeDelta
  Clamp: newFade to [0.0, 10.0]
  Apply to all selected effects
  Trigger render

If EFFECT_RESIZE_SMART_BRIGHTNESS:
  Call AdjustEffectBrightness(currentYPos)
    ↓
  Calculate: dragDelta = currentYPos - mSmartToolDragStartY
  Calculate: brightnessDelta = dragDelta / -2.0  (negative: up = increase)
  Calculate: newBrightness = mSmartToolInitialValue + brightnessDelta
  Clamp: newBrightness to [0, 100]
  Apply to all selected effects
  Trigger render
```

#### 4. Mouse Up (Finish Drag)
```
mouseReleased()
  ↓
Release mouse capture
Reset mResizing = false
Reset Smart Tool state variables
Trigger final render
```

### Zone Detection Algorithm

**GetEffectAtRowAndTime() - Vertical Zone Detection:**

```cpp
// Only applies when Option/Alt is held and effect is not locked

// Calculate effect boundaries on screen
int effectRow = row;
int y1 = effectRow * DEFAULT_ROW_HEADING_HEIGHT;
int y2 = (effectRow + 1) * DEFAULT_ROW_HEADING_HEIGHT;
int effectHeight = y2 - y1;

// Define zone boundaries
int topZoneBottom = y1 + (effectHeight * 0.15);    // Top 15%
int bottomZoneTop = y2 - (effectHeight * 0.15);    // Bottom 15%

// Get horizontal position info
int startPos = GetClippedPositionFromTimeMS(effect->GetStartTimeMS());
int endPos = GetClippedPositionFromTimeMS(effect->GetEndTimeMS());
int mid = (startPos + endPos) / 2;
int leftBoundary = startPos + (endPos - startPos) * 0.1;   // 10% from left
int rightBoundary = startPos + (endPos - startPos) * 0.9;  // 10% from right

// Vertical zone check
if (yPos < topZoneBottom) {
    // TOP ZONE - Fades
    if (xPos < mid) {
        return HitLocation::SMART_FADE_IN;
    } else {
        return HitLocation::SMART_FADE_OUT;
    }
} else if (yPos > topZoneBottom && yPos < bottomZoneTop) {
    // MIDDLE ZONE - Brightness
    if (xPos > leftBoundary && xPos < rightBoundary) {
        return HitLocation::SMART_BRIGHTNESS;
    } else {
        // Fall back to existing CENTER/LEFT/RIGHT logic
        // (allows edges to still work for resize)
    }
} else {
    // BOTTOM ZONE - Fall back to existing edge resize logic
}
```

### Cursor Mappings

**RunMouseOverHitTests() additions:**

```cpp
case HitLocation::SMART_FADE_IN:
case HitLocation::SMART_FADE_OUT:
case HitLocation::SMART_BRIGHTNESS:
    SetCursor(wxCURSOR_SIZENS);  // Vertical resize arrows
    if (zone == SMART_FADE_IN || zone == SMART_FADE_OUT) {
        mResizingMode = EFFECT_RESIZE_SMART_FADE;
    } else {
        mResizingMode = EFFECT_RESIZE_SMART_BRIGHTNESS;
    }
    break;
```

## Implementation Checklist

### Phase 1: Foundation (Header Changes)
- [ ] Add new HitLocation enum values to EffectsGrid.h
- [ ] Add EFFECT_RESIZE_SMART_FADE and EFFECT_RESIZE_SMART_BRIGHTNESS constants
- [ ] Add member variables: mSmartToolDragStartY, mSmartToolInitialValue, mSmartToolInitialZone
- [ ] Add function declarations: AdjustEffectFade(), AdjustEffectBrightness()

### Phase 2: Core Detection Logic
- [ ] Modify GetEffectAtRowAndTime() signature to accept yPos parameter
- [ ] Implement vertical zone detection in GetEffectAtRowAndTime()
- [ ] Update all callers of GetEffectAtRowAndTime() to pass yPos
- [ ] Ensure Option/Alt key state is checked before activating Smart Tool zones

### Phase 3: Cursor and Visual Feedback
- [ ] Update RunMouseOverHitTests() to handle new HitLocation values
- [ ] Set wxCURSOR_SIZENS for Smart Tool zones
- [ ] Set appropriate mResizingMode values

### Phase 4: Drag Handling
- [ ] Extend mouseDown() to initialize Smart Tool drag state
- [ ] Modify Resize() to route to Smart Tool adjustment functions
- [ ] Implement AdjustEffectFade()
- [ ] Implement AdjustEffectBrightness()
- [ ] Ensure undo step created on mouseDown

### Phase 5: Multi-Effect Support
- [ ] Test Smart Tool with multiple selected effects
- [ ] Ensure all selected effects adjust simultaneously
- [ ] Verify relative adjustments work correctly

### Phase 6: Edge Cases and Polish
- [ ] Handle value curve brightness (disable Smart Tool or show warning)
- [ ] Ensure locked effects don't respond to Smart Tool
- [ ] Test with very small effects (< 100px wide)
- [ ] Test with effects at sequence boundaries
- [ ] Verify existing edge resize still works in bottom 15%

### Phase 7: Testing
- [ ] Test fade in adjustment (top-left drag)
- [ ] Test fade out adjustment (top-right drag)
- [ ] Test brightness adjustment (center drag)
- [ ] Test multi-effect selection with Smart Tool
- [ ] Test undo/redo with Smart Tool changes
- [ ] Test that existing resize/move still works when Option/Alt NOT held
- [ ] Cross-platform testing (macOS Option, Windows/Linux Alt)

## Visual Feedback Enhancements (Future)

Optional improvements for better UX:

### Hover State Indicators
- Semi-transparent overlay highlighting the active zone when Option/Alt held
- Show current fade/brightness value as tooltip during hover

### Drag State Feedback
- Real-time value display near cursor during drag
- Fade duration shown as "Fade In: 2.5s" or "Fade Out: 1.2s"
- Brightness shown as "Brightness: 75%"

### Zone Divider Lines
- When Option/Alt held, draw subtle horizontal lines at 15% and 85% height
- Use semi-transparent color (gray, alpha 0.3)
- Only show for effects wider than 50px (avoid clutter on tiny effects)

### Enhanced Fade Hints
- Extend existing DrawFadeHints() to highlight when hovering in fade zone
- Make fade indicator line thicker or brighter during Smart Tool hover

## Known Limitations

1. **Value Curves**: Smart Tool brightness adjustment does not work with effects using brightness value curves (`C_VALUECURVE_Brightness`). These require curve editor.

2. **Timing Layer Effects**: Smart Tool is disabled for timing layer effects (they don't have brightness/fades)

3. **Locked Effects**: Locked effects do not respond to Smart Tool (consistent with existing behavior)

4. **Very Small Effects**: For effects narrower than ~50px, zones may be difficult to target precisely. Consider minimum width threshold.

5. **Touch Input**: Smart Tool designed for mouse/trackpad. Touch input may need different UX (no Option key equivalent)

## Configuration and Preferences

Currently no user preferences needed - Smart Tool is always available via Option/Alt key.

**Future Enhancement:** Could add preferences for:
- Drag sensitivity multipliers (faster/slower adjustment)
- Custom key binding (use different modifier instead of Option/Alt)
- Enable/disable Smart Tool entirely
- Show/hide zone indicators

## Performance Considerations

- Zone detection adds minimal overhead (simple arithmetic)
- Only active when Option/Alt held (doesn't impact normal operations)
- Drag updates trigger render events (existing behavior, not new overhead)
- Multi-effect updates batched in single render call

## Code Style and Standards

- Follow existing xLights C++ style (match surrounding code)
- Use `static log4cpp::Category& logger_base` for debug logging
- Use `std::max()` / `std::min()` for clamping (not manual if/else)
- Comment complex calculations (especially zone boundary math)
- Use const references where possible to avoid copies
- Prefer early returns to reduce nesting

## Testing Strategy

### Unit Tests
- Zone detection algorithm with various Y positions
- Fade delta calculation with different drag distances
- Brightness delta calculation with different drag distances
- Value clamping at boundaries (0%, 100%, 0s, 10s)

### Integration Tests
- Smart Tool with single effect
- Smart Tool with multiple selected effects
- Smart Tool with locked/unlocked effects
- Undo/redo after Smart Tool adjustments
- Interaction with existing resize modes

### Manual Testing Scenarios
1. Create effect, hold Option, drag top-left up → fade in increases
2. Create effect, hold Option, drag top-left down → fade in decreases
3. Create effect, hold Option, drag top-right up → fade out increases
4. Create effect, hold Option, drag center up → brightness increases
5. Select multiple effects, Smart Tool adjust → all effects change
6. Adjust with Smart Tool, undo → effects revert
7. Don't hold Option → existing behavior (no Smart Tool zones)

## Future Enhancements

1. **More Properties**: Extend Smart Tool to adjust other properties:
   - Blur amount
   - Sparkles density
   - Speed/acceleration
   - Effect-specific parameters

2. **Horizontal Drag**: Could map horizontal drag to different properties:
   - Left-right drag on edges = color hue adjustment
   - Left-right drag in center = effect speed

3. **Smart Tool Palette**: Toolbar button to enable/disable Smart Tool without holding key

4. **Context-Sensitive Zones**: Different zone layouts for different effect types

5. **Visual Curve Editor**: Double-click Smart Tool zone to open mini curve editor

## References

- Existing code: `EffectsGrid.cpp` lines 2042-2087 (GetEffectAtRowAndTime)
- Existing code: `EffectsGrid.cpp` lines 6250-6299 (RunMouseOverHitTests)
- Existing code: `EffectsGrid.cpp` lines 4018-4118 (Resize)
- Existing code: `EffectsGrid.cpp` lines 7045-7079 (DrawFadeHints)
- Effect settings: `Effect.h` lines 122-130 (GetSettings/SetSettings)

## Version History

- **v1.0** (2025-01-13): Initial design document
  - Smart Tool zones defined
  - Option/Alt key activation
  - Fade and brightness adjustment
  - Multi-effect support
