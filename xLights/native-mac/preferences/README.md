# Native macOS Preferences System

This directory contains the native macOS preferences window implementation for xLights, replacing the wxWidgets preferences dialog with a native AppKit interface.

## Architecture

### Window Controller
- **XLPreferencesWindowController**: Main window controller using NSToolbar for tab switching
  - Follows the standard macOS preferences pattern (toolbar with icons and labels)
  - Each toolbar item represents a preference pane
  - Window resizes to fit the active pane's content

### View Controllers
- **XLBasePreferencesViewController**: Base class for all preference panes
  - Handles automatic loading/saving of settings in viewDidLoad/viewWillDisappear
  - Subclasses override loadSettings() and saveSettings()

### Preference Panes (10 total)

1. **Backup** (XLBackupPreferencesViewController)
   - Backup interval settings
   - Backup location configuration

2. **View** (XLViewPreferencesViewController)
   - Effect icon size
   - Model handle size
   - Effect assist window behavior
   - Play controls visibility
   - House preview auto-show
   - Timeline zooming behavior
   - Crosshair size

3. **Effects Grid** (XLEffectsGridPreferencesViewController)
   - Grid spacing
   - Effect backgrounds
   - Node values display
   - Group effect indicators
   - Snap to timing marks
   - Double-click mode
   - Waveform size
   - Transition marks
   - Color update warnings
   - Alternate timing format
   - Bell on render completion

4. **Sequences** (XLSequenceFilePreferencesViewController)
   - Render on save
   - Low definition render
   - Model blend default
   - Render cache settings
   - Auto-save interval
   - FSEQ version
   - FSEQ save on save
   - Render cache directory
   - FSEQ directory
   - Media/resource directories
   - Default view

5. **Output** (XLOutputPreferencesViewController)
   - Frame sync
   - Force local IP
   - Duplicate frames to suppress
   - xFade/xSchedule port

6. **Check Sequence** (XLCheckSequencePreferencesViewController)
   - Disable checks for duplicate universes
   - Disable non-contiguous channel checks
   - Disable preview group checks
   - Disable duplicate node checks
   - Disable transition time checking
   - Disable custom model size checking
   - Disable sketch file checking

7. **Random Effects** (XLRandomEffectsPreferencesViewController)
   - Random effect generation settings

8. **Colors** (XLColorManagerPreferencesViewController)
   - Timing track colors
   - Effect grid colors
   - Layout tab colors
   - Suppress dark mode
   - Import/export color schemes
   - Reset to defaults

9. **Other** (XLOtherPreferencesViewController)
   - Hardware video decoding
   - Shaders on background threads
   - Video export settings (codec, bitrate)
   - Packaging sequences (exclude presets/audio)
   - Batch render prompt issues
   - Purge download cache
   - Ignore vendor recommendations
   - Tip of the day settings
   - Multi-threading
   - Link advanced settings
   - Alias prompt behavior
   - Controller ping interval

10. **Services** (XLServicesPreferencesViewController) — only if ENABLE_SERVICES is defined
    - AI service configuration
    - OpenAI/Ollama/Apple Intelligence settings

## Settings Storage

All settings are stored in NSUserDefaults with keys matching the existing xLights preferences system. This ensures compatibility during the transition period when both UIs may coexist.

## Key Features

### Immediate Application
Settings take effect immediately when changed (no OK/Apply/Cancel buttons). This follows the standard macOS preferences pattern.

### Keyboard Shortcut
Cmd+, opens the preferences window from anywhere in the app.

### Toolbar Icons
Uses SF Symbols for toolbar icons:
- Backup: externaldrive
- View: eye
- Effects Grid: square.grid.3x3
- Sequences: list.bullet
- Output: lightbulb
- Check Sequence: checkmark.circle
- Random Effects: die.face.5
- Colors: paintpalette
- Other: gearshape
- Services: cloud

### Window Behavior
- Window remembers size/position between launches
- Tabs use native NSToolbar selection
- Window resizes smoothly when switching panes
- Modal-less design (can interact with main window while prefs are open)

## Integration

The preferences window is opened via:
```objc
[[XLPreferencesWindowController sharedController] showWindow:sender];
```

Or from C++:
```objc
[XLApplication showPreferences];
```

The Cmd+, shortcut is registered in XLApplication.mm.

## Implementation Status

### Completed
- Window controller with NSToolbar-based tab switching
- Base view controller with automatic load/save
- Sequence File Settings pane (fully implemented)
- Effects Grid Settings pane (fully implemented)
- Stub implementations for all other panes

### To Do
- Complete implementation of remaining 8 panes
- Wire settings to engine APIs (currently uses NSUserDefaults)
- Add media directory list/add/remove functionality to Sequences pane
- Add color picker buttons to Color Manager pane
- Integrate with existing xLights engine callbacks
- Test all settings for persistence and effect

## Future Enhancements

- Search field in toolbar to filter settings
- Export/import preference profiles
- Tooltips on all controls
- Restore defaults button per-pane
- Settings validation (e.g., path existence checks)
