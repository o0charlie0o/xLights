# Native macOS xLights User Guide

This guide covers the native macOS user interface for xLights, an experimental feature that provides a more Mac-native experience.

## Enabling the Native UI

### Option 1: Preferences Setting (Persistent)
1. Open xLights (standard wxWidgets version)
2. Go to **Edit > Preferences > Other**
3. Check **Enable native macOS UI (requires restart)**
4. Quit and relaunch xLights

### Option 2: Command Line (Temporary)
Launch xLights with the `-nativeUI` flag:
```bash
/Applications/xLights.app/Contents/MacOS/xLights -nativeUI
```
This enables the native UI for that session only without changing your preferences.

## User Interface Overview

The native macOS UI follows Apple design patterns similar to Logic Pro X and Final Cut Pro X:

```
+------------------------------------------+
|  Toolbar (transport, tools, tabs)        |
+--------+-----------------------+---------+
|        |                       |         |
| Model  |    Main Canvas        | Inspec- |
| Tree   |  (Preview/Sequencer)  |  tor    |
|        |                       |         |
+--------+-----------------------+---------+
|        Bottom Panel (optional)           |
+------------------------------------------+
```

### Main Tabs

| Tab | Description |
|-----|-------------|
| **Setup** | Configure controllers, ports, and network settings |
| **Layout** | Design your model layout with 3D preview |
| **Sequencer** | Create and edit effects on the timeline |

### Key Differences from Standard xLights

| Feature | Standard (wxWidgets) | Native macOS |
|---------|---------------------|--------------|
| Window Style | Traditional MDI with docking | Single window with split panes |
| Menus | Custom wxWidgets menus | Native macOS menu bar |
| Keyboard Shortcuts | Custom key bindings | Standard macOS shortcuts |
| File Handling | wxWidgets dialogs | Native NSDocument architecture |
| Color Picker | wxColourDialog | Native NSColorPanel |
| Font Rendering | wxWidgets fonts | Native Core Text |
| Scrolling | Manual scroll handling | Native momentum scrolling |
| Undo/Redo | Custom implementation | Native NSUndoManager |

## Keyboard Shortcuts

### Playback

| Action | Shortcut |
|--------|----------|
| Play/Pause | Space |
| Stop | Cmd+. |
| Seek to Start | [ |
| Seek to End | ] |
| Step Forward | Right Arrow |
| Step Backward | Left Arrow |

### Editing

| Action | Shortcut |
|--------|----------|
| Undo | Cmd+Z |
| Redo | Cmd+Shift+Z |
| Cut | Cmd+X |
| Copy | Cmd+C |
| Paste | Cmd+V |
| Delete | Delete or Backspace |
| Select All | Cmd+A |

### Rendering

| Action | Shortcut |
|--------|----------|
| Render All | Cmd+R |
| Render Selected | Cmd+Shift+R |

### View

| Action | Shortcut |
|--------|----------|
| Toggle Inspector | Cmd+I |
| Toggle Bottom Panel | Cmd+B |
| Toggle Preview | Cmd+Shift+P |
| Zoom In | Cmd++ |
| Zoom Out | Cmd+- |
| Zoom to Fit | Cmd+0 |
| Full Screen | Ctrl+Cmd+F |

### Navigation

| Action | Shortcut |
|--------|----------|
| Preferences | Cmd+, |
| Find | Cmd+F |
| Close Window | Cmd+W |
| Quit | Cmd+Q |

## Opening Files

The native UI supports these file types:

| Type | Extensions | Description |
|------|------------|-------------|
| xLights Sequence | `.xlights`, `.xsq`, `.xml` | Full sequence files |
| FSEQ Sequence | `.fseq` | Binary sequence files |
| Show Folder | (directory) | Complete show folders |

### Opening a Show Folder

1. **File > Open** (Cmd+O)
2. Navigate to your show folder
3. The folder should contain `.xlights` files
4. Select the folder and click **Open**

### Recent Files

Access recently opened files via **File > Open Recent**.

## Sequencer

The native sequencer uses Metal-accelerated rendering for smooth 120Hz ProMotion display support.

### Effects Grid Navigation

- **Scroll**: Two-finger swipe or scroll wheel
- **Zoom**: Pinch gesture or Cmd+/- keys
- **Pan**: Shift + scroll or middle mouse button

### Adding Effects

1. Select a model in the row headings
2. Click and drag on the effects grid to create a time range
3. Choose an effect from the effects panel or right-click menu

### Effect Properties

Click an effect to select it, then modify properties in the Inspector panel on the right.

## Layout Tab

### Model Manipulation

- **Select**: Click on a model
- **Move**: Drag the selected model
- **Resize**: Drag corner handles
- **Rotate**: Drag rotation handle (3D models)

### Model Tree

The left sidebar shows your model hierarchy:
- Drag models to reorder
- Right-click for context menu (rename, delete, duplicate)
- Double-click to edit model properties

## Setup Tab

### Controller List

Shows all configured controllers with their status.

### Network Discovery

Click **Discover** to scan your network for compatible controllers.

### Port Configuration

Select a controller to view and configure its ports in the detail panel.

## Preferences

Access via **xLights > Preferences** (Cmd+,).

### Preference Panes

| Pane | Settings |
|------|----------|
| Sequence Files | Default paths, auto-save, backup |
| Effects Grid | Grid appearance, snap settings |
| Backup | Backup frequency, location |
| View | Theme, layout preferences |
| Output | Default protocols, timing |
| Check Sequence | Validation rules |
| Random Effects | Random generation settings |
| Color Manager | Color presets, palettes |
| Services | AI service configuration |
| Other | Native UI toggle, misc settings |

## Performance Notes

The native macOS UI is optimized for:

- **ProMotion displays**: 120Hz refresh on supported MacBooks/monitors
- **Apple Silicon**: Metal compute shaders for GPU-accelerated effects
- **Memory efficiency**: Better memory management with ARC

## Known Limitations

As an experimental feature, some capabilities may be incomplete:

- Some complex dialogs may fall back to the standard interface
- Certain advanced customization options may not yet be available
- Third-party plugins designed for wxWidgets may not work in native mode

## Troubleshooting

### Native UI Does Not Appear

1. Ensure you restarted xLights after enabling the preference
2. Try the `-nativeUI` command line flag
3. Check Console.app for error messages with "NativeUI" filter

### Performance Issues

1. Ensure your macOS is up to date
2. Check that Metal is available (System Information > Graphics/Displays)
3. Close other GPU-intensive applications

### Crashes or Errors

1. Check Console.app for crash logs
2. Try disabling the native UI via preferences
3. Report issues at https://github.com/xLightsSequencer/xLights/issues

## Reverting to Standard UI

To disable the native UI:

### If You Can Access Preferences
1. Go to **Edit > Preferences > Other**
2. Uncheck **Enable native macOS UI**
3. Restart xLights

### If xLights Won't Start
Reset the preference from Terminal:
```bash
defaults delete org.xlights.xLights XLNativeUIEnabled
```

## Feedback

This is an experimental feature under active development. Feedback is welcome:

- GitHub Issues: https://github.com/xLightsSequencer/xLights/issues
- xLights Forums: https://xlights.org/forums/
