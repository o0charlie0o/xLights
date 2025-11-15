# Retina Cursor Implementation Plan

## Overview

This document provides a complete implementation plan for adding Retina display support to the Smart Tool custom cursors in xLights. Currently, the 32×32 PNG cursors appear blurry on Retina displays because macOS scales them to 64×64 pixels. This plan uses the **wxBitmapBundle** approach for automatic multi-resolution cursor support.

## Problem Statement

**Current Behavior:**
- Custom cursors are loaded from 32×32 PNG files (`cursor_fade.png`, `cursor_brightness.png`)
- On Retina displays, macOS scales these to 64×64, resulting in blurry cursors
- Hotspot coordinates (16,16) also need to scale to (32,32) on Retina

**Desired Behavior:**
- Sharp, crisp cursors on both standard and Retina displays
- Automatic resolution selection based on display DPI
- Future-proof solution that works across all display types

## Solution: wxBitmapBundle Approach

**Why wxBitmapBundle?**
- Available in wxWidgets 3.1.6+ (xLights uses 3.3 ✓)
- Automatically selects appropriate resolution based on display DPI
- Handles non-Retina displays gracefully (uses 1× assets)
- Scales hotspot coordinates automatically
- Future-proof for even higher DPI displays

**How it Works:**
1. Create bundle with both 1× (32×32) and 2× (64×64) versions of each cursor
2. wxWidgets automatically selects correct image based on display scale factor
3. Hotspot coordinates scale automatically (16,16 → 32,32 on Retina)

---

## Implementation Steps

### Step 1: Create 2× Cursor Assets

**File Naming Convention:**
- Keep existing: `cursor_fade.png` (32×32) and `cursor_brightness.png` (32×32)
- Create Retina: `cursor_fade@2x.png` (64×64) and `cursor_brightness@2x.png` (64×64)

**Asset Creation in Photoshop:**
1. Open existing 32×32 cursor PNG in Photoshop
2. Image → Image Size → Set to 64×64 pixels
3. Use "Nearest Neighbor" for pixel art cursors, or "Bicubic Smoother" for detailed cursors
4. **IMPORTANT**: Redraw cursor at 64×64 for best quality (don't just scale up)
5. Save as `cursor_fade@2x.png` or `cursor_brightness@2x.png`
6. Export with transparency enabled

**Quality Guidelines:**
- Design cursors at 64×64 first, then scale down to 32×32 for best results
- Ensure icon is centered with hotspot at (32,32) for @2x and (16,16) for 1×
- Test both versions visually before integration

**After Saving in Photoshop:**
```bash
# Run the update_cursors.sh script to strip extended attributes
./update_cursors.sh
```

Or manually:
```bash
xattr -c include/cursor_fade.png
xattr -c include/cursor_fade@2x.png
xattr -c include/cursor_brightness.png
xattr -c include/cursor_brightness@2x.png
```

---

### Step 2: Update Build System (Xcode)

**Add @2x Files to Bundle Resources:**

1. In Xcode, select the xLights project in the navigator
2. Select the xLights target
3. Go to "Build Phases" tab
4. Expand "Copy Bundle Resources"
5. Click the "+" button
6. Add both new files:
   - `include/cursor_fade@2x.png`
   - `include/cursor_brightness@2x.png`
7. Verify they appear in the list alongside the existing 1× versions

**Verify File Structure:**
After building, the app bundle should contain:
```
xLights.app/Contents/Resources/
├── cursor_fade.png
├── cursor_fade@2x.png
├── cursor_brightness.png
└── cursor_brightness@2x.png
```

---

### Step 3: Update Code (EffectsGrid.cpp)

**Location:** `/Users/charlie/Documents/Charlie/xLights/xLights/sequencer/EffectsGrid.cpp`

**Current Implementation (lines 229-257):**
```cpp
// Initialize Smart Tool custom cursors from PNG files
wxString resourcesDir = wxStandardPaths::Get().GetResourcesDir();

// Try to load fade cursor from PNG
wxImage fadeCursorImg;
if (fadeCursorImg.LoadFile(resourcesDir + "/cursor_fade.png", wxBITMAP_TYPE_PNG)) {
    fadeCursorImg.SetOption(wxIMAGE_OPTION_CUR_HOTSPOT_X, 16);
    fadeCursorImg.SetOption(wxIMAGE_OPTION_CUR_HOTSPOT_Y, 16);
    mCursorFade = wxCursor(fadeCursorImg);
}

if (!mCursorFade.IsOk()) {
    mCursorFade = wxCursor(wxCURSOR_SIZEWE);
}

// Try to load brightness cursor from PNG
wxImage brightnessCursorImg;
if (brightnessCursorImg.LoadFile(resourcesDir + "/cursor_brightness.png", wxBITMAP_TYPE_PNG)) {
    brightnessCursorImg.SetOption(wxIMAGE_OPTION_CUR_HOTSPOT_X, 16);
    brightnessCursorImg.SetOption(wxIMAGE_OPTION_CUR_HOTSPOT_Y, 16);
    mCursorBrightness = wxCursor(brightnessCursorImg);
}

if (!mCursorBrightness.IsOk()) {
    mCursorBrightness = wxCursor(wxCURSOR_SIZENS);
}
```

**Updated Implementation (Retina Support with wxBitmapBundle):**

**Add Include at Top of File (after line 51):**
```cpp
#include <wx/bmpbndl.h>
```

**Replace Cursor Initialization (lines 229-257):**
```cpp
// Initialize Smart Tool custom cursors with Retina support using wxBitmapBundle
wxString resourcesDir = wxStandardPaths::Get().GetResourcesDir();

// Create fade cursor bundle with 1× and 2× versions
wxVector<wxBitmap> fadeBitmaps;
wxImage fadeCursor1x, fadeCursor2x;

// Load 1× version (32×32)
if (fadeCursor1x.LoadFile(resourcesDir + "/cursor_fade.png", wxBITMAP_TYPE_PNG)) {
    fadeBitmaps.push_back(wxBitmap(fadeCursor1x));
}

// Load 2× version (64×64) for Retina displays
if (fadeCursor2x.LoadFile(resourcesDir + "/cursor_fade@2x.png", wxBITMAP_TYPE_PNG)) {
    fadeBitmaps.push_back(wxBitmap(fadeCursor2x));
}

// Create bundle and cursor
if (!fadeBitmaps.empty()) {
    wxBitmapBundle fadeBundle = wxBitmapBundle::FromBitmaps(fadeBitmaps);
    wxImage fadeCursorImg = fadeBundle.GetBitmap(fadeBundle.GetDefaultSize()).ConvertToImage();

    // Set hotspot (will automatically scale: 16,16 for 1× or 32,32 for 2×)
    int hotspotX = fadeCursorImg.GetWidth() / 2;
    int hotspotY = fadeCursorImg.GetHeight() / 2;
    fadeCursorImg.SetOption(wxIMAGE_OPTION_CUR_HOTSPOT_X, hotspotX);
    fadeCursorImg.SetOption(wxIMAGE_OPTION_CUR_HOTSPOT_Y, hotspotY);

    mCursorFade = wxCursor(fadeCursorImg);
}

// Fall back to stock cursor if bundle creation failed
if (!mCursorFade.IsOk()) {
    mCursorFade = wxCursor(wxCURSOR_SIZEWE);
}

// Create brightness cursor bundle with 1× and 2× versions
wxVector<wxBitmap> brightnessBitmaps;
wxImage brightnessCursor1x, brightnessCursor2x;

// Load 1× version (32×32)
if (brightnessCursor1x.LoadFile(resourcesDir + "/cursor_brightness.png", wxBITMAP_TYPE_PNG)) {
    brightnessBitmaps.push_back(wxBitmap(brightnessCursor1x));
}

// Load 2× version (64×64) for Retina displays
if (brightnessCursor2x.LoadFile(resourcesDir + "/cursor_brightness@2x.png", wxBITMAP_TYPE_PNG)) {
    brightnessBitmaps.push_back(wxBitmap(brightnessCursor2x));
}

// Create bundle and cursor
if (!brightnessBitmaps.empty()) {
    wxBitmapBundle brightnessBundle = wxBitmapBundle::FromBitmaps(brightnessBitmaps);
    wxImage brightnessCursorImg = brightnessBundle.GetBitmap(brightnessBundle.GetDefaultSize()).ConvertToImage();

    // Set hotspot (will automatically scale: 16,16 for 1× or 32,32 for 2×)
    int hotspotX = brightnessCursorImg.GetWidth() / 2;
    int hotspotY = brightnessCursorImg.GetHeight() / 2;
    brightnessCursorImg.SetOption(wxIMAGE_OPTION_CUR_HOTSPOT_X, hotspotX);
    brightnessCursorImg.SetOption(wxIMAGE_OPTION_CUR_HOTSPOT_Y, hotspotY);

    mCursorBrightness = wxCursor(brightnessCursorImg);
}

// Fall back to stock cursor if bundle creation failed
if (!mCursorBrightness.IsOk()) {
    mCursorBrightness = wxCursor(wxCURSOR_SIZENS);
}
```

**Code Explanation:**
1. **wxVector<wxBitmap>**: Container for multiple bitmap resolutions
2. **Load both versions**: 1× (32×32) and 2× (64×64) into vector
3. **wxBitmapBundle::FromBitmaps()**: Creates bundle from vector
4. **GetBitmap(GetDefaultSize())**: wxWidgets automatically selects correct resolution based on display DPI
5. **Hotspot calculation**: `width / 2` and `height / 2` ensures center hotspot for both resolutions
6. **Fallback**: If bundle creation fails, falls back to stock wxCursor

---

### Step 4: Update Helper Script

**Update `update_cursors.sh`:**

```bash
#!/bin/bash
# Helper script to clean cursor PNG files after editing

echo "Removing extended attributes from cursor files..."
xattr -c include/cursor_brightness.png 2>/dev/null
xattr -c include/cursor_brightness@2x.png 2>/dev/null
xattr -c include/cursor_fade.png 2>/dev/null
xattr -c include/cursor_fade@2x.png 2>/dev/null

echo "Cursor files cleaned successfully!"
echo "You can now rebuild in Xcode."
```

---

## Testing

### Visual Testing

**Test on Standard (Non-Retina) Display:**
1. Build and run xLights on a non-Retina Mac or external non-Retina display
2. Open a sequence and hold Option/Alt over an effect
3. Verify cursors appear sharp (should use 32×32 versions)
4. Check hotspot is centered when clicking

**Test on Retina Display:**
1. Build and run xLights on a Retina MacBook or iMac
2. Open a sequence and hold Option/Alt over an effect
3. Verify cursors appear sharp and crisp (should use 64×64 versions)
4. Check hotspot is centered when clicking
5. Compare to old implementation - should be noticeably sharper

### Debugging

**Verify Bundle Loading:**
Add temporary debug logging to confirm which resolution is being used:

```cpp
// After creating bundle
wxSize selectedSize = fadeBundle.GetDefaultSize();
wxLogDebug("Fade cursor selected size: %dx%d", selectedSize.GetWidth(), selectedSize.GetHeight());
// Should log "32x32" on non-Retina, "64x64" on Retina
```

**Check File Presence:**
```bash
# Verify files are in bundle
ls -la xLights.app/Contents/Resources/cursor_*
```

**Check Extended Attributes:**
```bash
# Ensure no extended attributes (should show nothing)
xattr include/cursor_*.png
```

---

## Workflow for Future Cursor Updates

### When Editing Cursors in Photoshop:

1. **Edit 64×64 version first** (cursor_fade@2x.png or cursor_brightness@2x.png)
   - This is the highest quality source
   - Design at full Retina resolution

2. **Scale down to 32×32** for 1× version
   - Image → Image Size → 32×32 pixels
   - Use "Bicubic Sharper" for reduction
   - Save as cursor_fade.png or cursor_brightness.png

3. **Strip extended attributes:**
   ```bash
   ./update_cursors.sh
   ```

4. **Clean build folder in Xcode:**
   - Product → Clean Build Folder (Cmd+Shift+K)

5. **Rebuild:**
   - Product → Build (Cmd+B)

6. **Test on both display types** (if possible)

---

## File Organization

**Recommended Structure:**

```
/Users/charlie/Documents/Charlie/xLights/
├── include/
│   ├── cursor_fade.png           (32×32, 1× resolution)
│   ├── cursor_fade@2x.png        (64×64, 2× resolution)
│   ├── cursor_brightness.png     (32×32, 1× resolution)
│   └── cursor_brightness@2x.png  (64×64, 2× resolution)
├── update_cursors.sh              (Extended attribute cleanup script)
└── RETINA_CURSOR_IMPLEMENTATION.md (This document)
```

**Xcode Project Structure:**
- Keep cursor files in the include/ folder (already there)
- They'll appear in the project navigator under the include group
- All four files should be in "Copy Bundle Resources" build phase

---

## Benefits of This Approach

1. **Automatic DPI Selection**: wxBitmapBundle handles all display scaling automatically
2. **Future-Proof**: Works with any DPI scaling factor (1×, 2×, future 3×, etc.)
3. **Graceful Degradation**: Falls back to 1× on older displays, stock cursors if load fails
4. **Platform Compatible**: Works on wxWidgets 3.3 (xLights' current version)
5. **Minimal Code Changes**: Localized to EffectsGrid.cpp initialization
6. **No Runtime Overhead**: Selection happens once at startup
7. **Standard Naming**: Uses macOS/iOS @2x convention

---

## Alternative Approach (Not Recommended)

**Direct 64×64 PNG Approach:**
- Load 64×64 PNG directly for all displays
- Set hotspot to (32,32)
- **Drawback**: Wastes memory on non-Retina displays and may look overly large

**Why wxBitmapBundle is Better:**
- Uses appropriate resolution for each display type
- More efficient memory usage
- Aligns with wxWidgets best practices
- Future-proof for higher DPI displays

---

## Troubleshooting

### Cursors Still Appear Blurry on Retina
- Verify @2x files are in app bundle: `ls xLights.app/Contents/Resources/cursor_*@2x.png`
- Check that @2x files are actually 64×64: `file include/cursor_fade@2x.png`
- Ensure extended attributes are removed: `xattr include/cursor_fade@2x.png` (should show nothing)
- Clean build folder and derived data completely

### Cursors Don't Appear at All
- Check fallback to stock cursors is working (wxCURSOR_SIZEWE / wxCURSOR_SIZENS)
- Verify wxBitmapBundle compiled in (wxWidgets 3.3 supports it)
- Check wxLogDebug output for file loading errors

### Wrong Hotspot Location
- Verify hotspot calculation: should be `width / 2, height / 2`
- For 32×32: hotspot = (16,16)
- For 64×64: hotspot = (32,32)
- Check cursor design - hotspot should be at visual center of cursor

### Build Errors
- Ensure `#include <wx/bmpbndl.h>` is present
- Verify wxWidgets version is 3.1.6+ (xLights uses 3.3, so this is OK)
- Check for typos in file paths

---

## Summary

This implementation plan provides a complete, production-ready solution for Retina cursor support using wxBitmapBundle. The approach is:

- **Simple**: Minimal code changes, standard wxWidgets API
- **Robust**: Graceful fallbacks at every step
- **Future-proof**: Works with any DPI scaling factor
- **Maintainable**: Clear workflow for cursor updates

When ready to implement, follow the steps in order, test thoroughly on both display types, and update the Smart Tool PR documentation to reflect Retina support.
