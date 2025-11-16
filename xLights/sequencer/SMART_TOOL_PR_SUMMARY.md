# Smart Tool Feature - Pull Request Summary

## Overview

This PR implements a DAW-style (Digital Audio Workstation) Smart Tool feature for xLights, allowing users to quickly adjust effect properties (fade in/out and brightness) directly on the timeline by holding Option (macOS) / Alt (Windows/Linux) and dragging in specific zones of an effect.

## Feature Description

The Smart Tool provides intuitive, visual editing of effect properties without needing to open effect panels:

- **Activation**: Hold Option/Alt key while hovering over an effect
- **Visual Feedback**: Cursor changes to indicate which property can be adjusted
- **Multi-Effect Support**: Adjusts all selected effects simultaneously
- **Non-Disruptive**: When Option/Alt is NOT held, all existing behavior remains unchanged
- **Undo Support**: Each Smart Tool operation creates a single undo point

### Interaction Zones

When Option/Alt is held and hovering over an unlocked effect, the effect is divided into zones:

```
┌─────────────────────────────────────┐
│  TOP 15%: FADE IN  │  FADE OUT      │ ← Horizontal drag adjusts fade duration
├────────────────┬────────────────────┤
│                │                    │
│   MIDDLE 70%:  │   BRIGHTNESS       │ ← Vertical drag adjusts brightness
│                │                    │
├────────────────┴────────────────────┤
│  BOTTOM 15%: Normal resize edges    │ ← Existing edge resize still works
└─────────────────────────────────────┘
```

### Adjustable Properties

1. **Fade In** (top-left zone)
   - Horizontal drag adjusts fade in duration (0.0 to 10.0 seconds)
   - 100 pixels = 1.0 second change
   - Drag right = increase, drag left = decrease

2. **Fade Out** (top-right zone)
   - Horizontal drag adjusts fade out duration (0.0 to 10.0 seconds)
   - 100 pixels = 1.0 second change
   - Drag right = increase, drag left = decrease

3. **Brightness** (center zone)
   - Vertical drag adjusts brightness (0 to 100%)
   - 2 pixels = 1% change
   - Drag up = increase, drag down = decrease

### Status Bar Feedback

During drag operations, the status bar displays:
- Fade adjustments: "Fade In: X.Xs" or "Fade Out: X.Xs"
- Brightness adjustments: "Brightness: XX%"

Status bar clears automatically when drag completes.

## Files Changed

### Modified Files

1. **xLights/sequencer/EffectsGrid.h** (+10 lines)
   - Added HitLocation enum values: SMART_FADE_IN, SMART_FADE_OUT, SMART_BRIGHTNESS
   - Added Smart Tool state variables (drag start positions, initial values)
   - Added custom cursor member variables (mCursorFade, mCursorBrightness)

2. **xLights/sequencer/EffectsGrid.cpp** (+140 lines, -36 lines)
   - Implemented zone detection in GetEffectAtRowAndTime()
   - Added Smart Tool drag handling in mouseDown(), Resize(), mouseReleased()
   - Implemented AdjustEffectFade() and AdjustEffectBrightness()
   - Added cursor initialization and management
   - Added EffectSettingsTimer control to prevent race conditions
   - Added status bar feedback during drag operations

### New Files

3. **include/cursor_brightness.png**
   - Custom sun icon cursor for brightness adjustment (32x32 PNG with alpha transparency)
   - Loaded using wxImage with hotspot at (16,16)
   - Falls back to wxCURSOR_SIZENS if PNG load fails

4. **include/cursor_fade.png**
   - Custom triangle ramp cursor for fade adjustments (32x32 PNG with alpha transparency)
   - Loaded using wxImage with hotspot at (16,16)
   - Falls back to wxCURSOR_SIZEWE if PNG load fails

## Implementation Details

### Zone Detection

The Smart Tool only activates when:
1. Option/Alt key is held (event.AltDown())
2. Effect is not locked
3. Mouse is within an effect boundary

Vertical zones are calculated based on effect height:
- Top 15%: Fade zones (split horizontally at midpoint)
- Middle 70%: Brightness zone (center 80% horizontally)
- Bottom 15%: Existing edge resize behavior preserved

### Timer Race Condition Fix

**Critical Fix**: The EffectSettingsTimer (fires every 25ms) reads UI controls and writes to SettingsMap, creating a race condition with Smart Tool updates.

**Solution**:
1. Stop EffectSettingsTimer in mouseDown() when brightness drag starts
2. Initialize brightness in SettingsMap if empty (most effects don't have it)
3. Update both SettingsMap AND UI controls during drag to maintain synchronization
4. Restart EffectSettingsTimer in mouseReleased() after drag completes

### Brightness Settings Mapping

The Smart Tool modifies these SettingsMap keys for brightness:

- **Priority 1**: `E_TEXTCTRL_Eff_On_Start` and `E_TEXTCTRL_Eff_On_End` (On effect brightness, 0-100)
  - If these exist, adjust both by same delta to maintain ramp
- **Priority 2**: `C_SLIDER_Brightness` (General brightness slider, 0-100)
  - Used if On effect brightness not present
- **Not supported**: `C_VALUECURVE_Brightness` (Value curves too complex for simple drag)

### UI Synchronization

During Smart Tool brightness drag, the code updates:
1. SettingsMap values (C_SLIDER_Brightness or E_TEXTCTRL_Eff_On_Start/End)
2. ColorPanel UI controls (Slider_Brightness, txtCtlBrightness)
3. Status bar display
4. Triggers render update

This prevents the common issue where UI and SettingsMap diverge, causing values to reset.

## Testing Performed

### Manual Testing

- ✅ Fade in adjustment (top-left horizontal drag)
- ✅ Fade out adjustment (top-right horizontal drag)
- ✅ Brightness adjustment (center vertical drag)
- ✅ Multi-effect selection with Smart Tool
- ✅ Brightness persistence across multiple adjustments
- ✅ Brightness persistence when switching between effects
- ✅ Status bar display during drag
- ✅ Status bar clearing after mouse release
- ✅ Existing resize/move still works when Option/Alt NOT held
- ✅ Locked effects don't respond to Smart Tool

### Build Testing

- ✅ macOS Debug build successful (x86_64 and arm64)
- ✅ No errors, only expected warnings about unhandled enum values in existing switch statements

## Custom Cursor Implementation

The Smart Tool uses PNG-based custom cursors loaded via wxImage with proper hotspot configuration:

- **PNG Format**: 32x32 PNG images with alpha transparency
- **Hotspot**: Configured using `wxIMAGE_OPTION_CUR_HOTSPOT_X/Y` at (16,16)
- **Loading**: Uses `wxStandardPaths::GetResourcesDir()` to locate cursor files
- **Fallback**: Gracefully falls back to stock cursors if PNG files not found
- **Cross-Platform**: This approach works on macOS Cocoa, Windows, and Linux

The PNG approach provides:
- Full alpha transparency support
- Custom hotspot positioning
- Better platform compatibility than XPM
- Native appearance on macOS

## Known Limitations

1. **Value Curves**: Smart Tool brightness adjustment does not work with effects using brightness value curves (`C_VALUECURVE_Brightness`). These require the curve editor.

2. **Timing Layer Effects**: Smart Tool is disabled for timing layer effects (they don't have brightness/fades).

3. **Locked Effects**: Locked effects do not respond to Smart Tool (consistent with existing behavior).

4. **Very Small Effects**: For effects narrower than ~50px, zones may be difficult to target precisely.

5. **Cursor Resources**: PNG cursor files must be present in the application's Resources directory. The build system should ensure these are copied to the bundle/installation.

## Design Documentation

Full design documentation is available in:
- `xLights/sequencer/SMART_TOOL_DESIGN.md` - Complete implementation guide with zone diagrams, flow charts, and technical specifications

## Backward Compatibility

- ✅ No changes to file formats
- ✅ No changes to existing behavior when Option/Alt is not held
- ✅ Existing edge resize and effect drag operations unchanged
- ✅ All existing keyboard shortcuts and mouse interactions preserved

## Future Enhancements

Potential future improvements:
1. Additional properties (blur, sparkles, speed, rotation)
2. Horizontal drag for color hue or other parameters
3. Visual zone indicators when Option/Alt held (semi-transparent overlays)
4. User preferences for drag sensitivity and key binding
5. Real-time value tooltips near cursor during drag
6. Support for adjusting value curves with Smart Tool

## Code Quality

- All debug logging removed for production
- Follows existing xLights C++ coding style
- Commented complex calculations (zone boundary math, timer management)
- Uses const references where appropriate
- Early returns to reduce nesting
- Comprehensive inline documentation

## Migration Notes

No migration required. This is a new feature that does not affect existing sequences or workflows.
