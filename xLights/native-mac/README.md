# native-mac: Native macOS (AppKit) UI for xLights

This directory contains the native macOS UI implementation for xLights,
separate from the existing wxWidgets codebase. Both UIs can coexist
during the transition period.

## Documentation

| Document | Audience | Description |
|----------|----------|-------------|
| [USER_GUIDE.md](USER_GUIDE.md) | End Users | How to enable and use the native UI |
| [ENGINE_API.md](ENGINE_API.md) | Developers | Complete XLEngineBridge API reference |
| [dialogs/README.md](dialogs/README.md) | Developers | Dialog migration patterns and wxWidgets replacement guide |
| [IMPLEMENTATION_GUIDE.md](../IMPLEMENTATION_GUIDE.md) | Developers | Full rebuild plan and architecture |

## File Conventions

- **`.h`** - Objective-C headers (pure AppKit, no C++)
- **`.m`** - Objective-C implementation (pure AppKit)
- **`.mm`** - Objective-C++ (bridges to C++ engine APIs)
- **`XL` prefix** - All classes use the XL prefix

## Architecture

```
XLAppDelegate
  -> XLDocumentController (custom NSDocumentController)
  -> XLMenuBuilder (builds full menu bar)

XLDocument (NSDocument)
  -> XLMainWindowController (NSSplitView layout)
       -> XLSetupViewController      (tab 0)
       -> XLLayoutViewController     (tab 1)
       -> XLSequencerViewController  (tab 2)
       -> XLInspectorViewController  (right sidebar)
       -> XLEngineBridge             (C++ engine access)

XLPreferencesWindowController (toolbar-based pane switching)
  -> 10 preference panes (XL*PreferencesViewController)
```

### Engine Bridge Pattern

AppKit code calls C++ engines through `XLEngineBridge` (.mm):

```objc
// XLEngineBridge wraps the 5 C++ engine APIs
[self.engineBridge play];                    // -> SequenceEngine
[self.engineBridge getModelNames];           // -> ModelEngine
[self.engineBridge startOutput];             // -> OutputEngine
[self.engineBridge renderAll];               // -> RenderEngine
[self.engineBridge getEffectTypes];          // -> EffectEngine
```

For C++ -> AppKit direction, `XLDocumentBridge` provides static methods:

```cpp
XLDocumentBridge::updateDocumentDirtyState(frame, true);
XLDocumentBridge::notifySequenceSaved(frame, path);
```

## File Inventory

### Application Shell
| File | Description |
|------|-------------|
| `XLAppDelegate.h/m` | NSApplicationDelegate: document controller, menu bar, preferences |
| `XLMainWindowController.h/mm` | Main window with Logic Pro-style NSSplitView layout |
| `XLEngineBridge.h/mm` | Objective-C++ bridge to all 5 C++ engine APIs |
| `XLToolbarExtensions.h/mm` | XLToolbarBuilder + XLMenuBuilder factory classes |

### Document Handling
| File | Description |
|------|-------------|
| `XLDocument.h/mm` | NSDocument for .xlights, .fseq, and show folders |
| `XLDocumentController.h/m` | Custom open panel, show folder support, recent files |
| `XLDocumentBridge.h/mm` | C++ bridge for xLightsFrame <-> NSDocument |
| `Info.plist.snippet` | Document type + UTI declarations for Info.plist |

### Tab View Controllers
| File | Description |
|------|-------------|
| `XLSetupViewController.h/m` | Setup tab (controllers, ports, discovery) |
| `XLLayoutViewController.h/m` | Layout tab (model preview, tree, inspector) |
| `XLSequencerViewController.h/m` | Sequencer tab (effects grid, timeline, waveform) |
| `XLInspectorViewController.h/m` | Right sidebar inspector (context-sensitive) |

### Preferences (`preferences/`)
| File | Description |
|------|-------------|
| `XLPreferencesWindowController.h/mm` | NSToolbar-based pane switching, singleton |
| `XLBasePreferencesViewController.h/m` | Base class with load/save settings pattern |
| `XLSequenceFilePreferencesViewController.h/m` | Sequence file settings (fully implemented) |
| `XLEffectsGridPreferencesViewController.h/m` | Effects grid settings (fully implemented) |
| `XLBackupPreferencesViewController.h/m` | Backup settings (stub) |
| `XLViewPreferencesViewController.h/m` | View/appearance settings (stub) |
| `XLOutputPreferencesViewController.h/m` | Output settings (stub) |
| `XLCheckSequencePreferencesViewController.h/m` | Check sequence settings (stub) |
| `XLRandomEffectsPreferencesViewController.h/m` | Random effects settings (stub) |
| `XLColorManagerPreferencesViewController.h/m` | Color manager settings (stub) |
| `XLOtherPreferencesViewController.h/m` | Other settings (stub) |
| `XLServicesPreferencesViewController.h/m` | AI/services settings (stub) |

## Supported Document Types

| Type | Extensions | UTI |
|------|-----------|-----|
| xLights Sequence | `.xlights`, `.xsq`, `.xml` | `org.xlights.sequence` |
| FSEQ Sequence | `.fseq` | `org.xlights.fseq` |
| Show Folder | directory | `org.xlights.showfolder` |

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Play/Pause | Space |
| Stop | Cmd+. |
| Seek Start/End | [ / ] |
| Render All | Cmd+R |
| Render Selected | Cmd+Shift+R |
| Toggle Inspector | Cmd+I |
| Toggle Bottom Panel | Cmd+B |
| Toggle Preview | Cmd+Shift+P |
| Zoom In/Out/Fit | Cmd+/Cmd-/Cmd+0 |
| Full Screen | Ctrl+Cmd+F |
| Preferences | Cmd+, |
| Find | Cmd+F |

## Coding Standards

1. **ARC** - All Objective-C code uses Automatic Reference Counting
2. **No wx types** - Pure AppKit/Foundation at this layer
3. **C++ bridge** - Use `.mm` only at the boundary (XLEngineBridge, XLDocumentBridge)
4. **Thread safety** - UI on main thread; engine callbacks dispatch to main queue
5. **Error handling** - Use NSError** pattern for file I/O
6. **Layout** - NSLayoutConstraint, not autoresizing masks
7. **Settings** - NSUserDefaults for preferences storage

## Build Integration

To add to Xcode project:
1. Add all `.h`, `.m`, `.mm` files to the xLights target
2. Merge `Info.plist.snippet` into `macOS/Info.plist`
3. Ensure ARC is enabled (`-fobjc-arc`)
4. Add `native-mac/` to header search paths

## Engine APIs (in `../engine/`)

| API | Purpose |
|-----|---------|
| `SequenceEngine.h` | Sequence load/save, playback, timing |
| `ModelEngine.h` | Model CRUD, properties, nodes |
| `OutputEngine.h` | Controller management, output control |
| `RenderEngine.h` | Frame rendering, buffer access |
| `EffectEngine.h` | Effect types, parameters, CRUD |
