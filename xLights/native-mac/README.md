# native-mac Directory

This directory contains the native macOS (AppKit) UI implementation for xLights. All new native macOS code goes here, separate from the existing wxWidgets codebase.

## Code Organization

### File Naming Convention

- **`.h` files** - Objective-C headers (pure AppKit, no C++)
- **`.m` files** - Objective-C implementation (pure AppKit, no C++)
- **`.mm` files** - Objective-C++ implementation (bridges to C++ engine APIs)

### Current Implementation

#### NSDocument Integration (Phase 1, Ticket 1C)

**Files:**
- `XLDocument.h/.mm` - NSDocument subclass for .xlights/.fseq files and show folders
- `XLDocumentController.h/.m` - Custom document controller for open/recent files
- `XLDocumentBridge.h/.mm` - C++ bridge for integration with xLightsFrame
- `Info.plist.snippet` - Document type declarations to merge into main Info.plist

**Supported Document Types:**
1. **xLights Sequence** (`.xlights`, `.xsq`, `.xml`)
   - XML-based sequence files
   - UTI: `org.xlights.sequence`

2. **FSEQ Sequence** (`.fseq`)
   - Binary sequence files
   - UTI: `org.xlights.fseq`

3. **Show Folder** (directory)
   - Directory containing `xlights_rgbeffects.xml`
   - Contains models, controllers, and sequences
   - UTI: `org.xlights.showfolder`

**Features Implemented:**
- ✅ NSDocument-based file handling
- ✅ Recent Files menu (automatic via NSDocument)
- ✅ Dirty state tracking (unsaved changes dot)
- ✅ Auto-save support
- ✅ Version support (Time Machine integration)
- ✅ Show folder concept (directory-based document)
- ✅ File → Open for both sequences and show folders
- ✅ Drag-and-drop onto dock icon and app window

## Integration with Existing Codebase

### SequenceEngine Bridge

`XLDocument` calls into `SequenceEngine` (from Phase 0) for all sequence operations:

```objc
// Loading a sequence
std::string path = url.path.UTF8String;
BOOL success = _sequenceEngine->loadSequence(path);

// Saving a sequence
success = _sequenceEngine->saveSequence(path);
```

### xLightsFrame Integration

The `XLDocumentBridge` class provides a C++ API for the existing wxWidgets code:

```cpp
// From xLightsFrame, notify document of changes
XLDocumentBridge::updateDocumentDirtyState(this, true);

// Notify document of save
XLDocumentBridge::notifySequenceSaved(this, sequencePath);
```

This allows both UIs (wxWidgets and AppKit) to work during the transition.

## Build Integration

### Xcode Project Setup

When integrating into the Xcode project:

1. Add all `.h`, `.m`, and `.mm` files to the xLights target
2. Merge `Info.plist.snippet` into the main `Info.plist`
3. Ensure `-fobjc-arc` is enabled for Objective-C files (ARC)
4. Add `native-mac/` to header search paths

### Info.plist Integration

The `Info.plist.snippet` file contains:
- `CFBundleDocumentTypes` - Registered document types
- `UTExportedTypeDeclarations` - UTI definitions
- `NSDocumentController` - Custom document controller class

These should be merged into `macOS/Info.plist` during integration.

## Testing Checklist

- [ ] Opening `.xlights` files launches the app and loads the sequence
- [ ] Opening `.fseq` files loads binary sequences
- [ ] Opening show folders loads the entire show
- [ ] Save/Save As work correctly
- [ ] Recent Files menu populates and opens files
- [ ] Dirty state indicator works (dot on close button when modified)
- [ ] Unsaved changes prompt appears on close
- [ ] Auto-save creates versions
- [ ] Drag-and-drop onto dock icon opens files
- [ ] Drag-and-drop onto app window opens files
- [ ] Double-clicking files in Finder opens them in xLights

## Phase 1A: Main Window + NSSplitView — COMPLETE ✅

**Files:**
- `XLMainWindowController.h/.mm` - Main window with Logic Pro-style split views
- `XLSetupViewController.h/.m` - Setup tab placeholder
- `XLLayoutViewController.h/.m` - Layout tab placeholder
- `XLSequencerViewController.h/.m` - Sequencer tab placeholder
- `XLInspectorViewController.h/.m` - Inspector sidebar
- `XLEngineBridge.h/.mm` - Objective-C++ bridge to C++ engine APIs
- `XLAppDelegate.h/.m` - App delegate for standalone testing
- `main.m` - Standalone test entry point
- `Makefile` - Standalone build system

**Features Implemented:**
- ✅ NSWindowController with three-region split layout
- ✅ Tab switching (Setup, Layout, Sequencer)
- ✅ Collapsible inspector sidebar (Logic Pro-style)
- ✅ Collapsible bottom panel (properties/color picker)
- ✅ NSToolbar with play controls and view toggles
- ✅ Window state persistence (frame, splits, panel visibility)
- ✅ Dark appearance by default
- ✅ Objective-C++ bridge to all engine APIs (stub implementation)
- ✅ Standalone test app (make run)

**Total Code:** ~2,570 lines across 15 files

See `.beads/notes/xlmac-osm-done.md` for full implementation details.

## Next Steps

**Phase 1B** - NSToolbar + Menus
- ✅ Toolbar already implemented in Phase 1A
- ✅ Menus already implemented in Phase 1A
- ⏳ Wire up undo/redo, copy/paste actions

**Phase 1C** - NSDocument Integration
- ✅ Already complete (XLDocument.h/.mm exist)
- ⏳ Connect XLDocument to XLMainWindowController
- ⏳ Display document content in window

**Phase 1D** - Preferences Window
- ⏳ Implement NSPreferencesWindow
- ⏳ Migrate 10 settings panes from wxWidgets

## References

### Spike Prototypes
- `spikes/AppKitInspector/` - Inspector pattern for property editing
- `spikes/MetalTimeline/` - Metal NSView pattern for timeline

### Engine APIs
- `engine/SequenceEngine.h` - Sequence operations
- `engine/ModelEngine.h` - Model management
- `engine/OutputEngine.h` - Controller/output management
- `engine/RenderEngine.h` - Frame rendering
- `engine/EffectEngine.h` - Effect management

### Existing File Handlers
- `xLightsXmlFile.h/cpp` - XML sequence format
- `FSEQFile.h/cpp` - Binary sequence format
- `SeqFileUtilities.cpp` - File utilities

## Coding Standards

Follow the patterns from the spike prototypes:

1. **Use ARC** - All Objective-C code uses Automatic Reference Counting
2. **No wx types** - NSDocument code is pure AppKit/Foundation
3. **C++ bridge** - Use Objective-C++ (`.mm`) only at the boundary
4. **Thread safety** - NSDocument methods run on main thread, engine uses internal locking
5. **Error handling** - Use NSError** pattern for file I/O
6. **Modern APIs** - Use NSLayoutConstraint, not autoresizing masks

## Notes

- Do NOT modify existing xLights source files (xLightsMain.h, etc.)
- This is parallel implementation - both UIs work during transition
- SequenceEngine is the source of truth for sequence data
- XLDocument is a thin wrapper around SequenceEngine
