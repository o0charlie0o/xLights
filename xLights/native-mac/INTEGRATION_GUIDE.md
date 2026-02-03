# NSDocument Integration Guide

## Overview

This guide explains how to integrate the NSDocument-based file handling (Phase 1C) into the xLights Xcode project.

## Files to Add to Xcode Project

All files are in `/xLights/native-mac/`:

### Document Handling (Phase 1C)
- [x] `XLDocument.h`
- [x] `XLDocument.mm`
- [x] `XLDocumentController.h`
- [x] `XLDocumentController.m`
- [x] `XLDocumentBridge.h`
- [x] `XLDocumentBridge.mm`
- [x] `XLAppDelegate.h`
- [x] `XLAppDelegate.m`

### Main Window (Phase 1A - Already Done)
- [x] `XLMainWindowController.h`
- [x] `XLMainWindowController.mm`
- [x] `XLEngineBridge.h`
- [x] `XLEngineBridge.mm`
- [x] `XLSetupViewController.h/.m`
- [x] `XLLayoutViewController.h/.m`
- [x] `XLSequencerViewController.h/.m`
- [x] `XLInspectorViewController.h/.m`

### Toolbars (Phase 1B - In Progress)
- [x] `XLToolbarExtensions.h`
- [x] `XLToolbarExtensions.mm`

## Xcode Project Setup

### 1. Add Files to Target

In Xcode project navigator:
1. Right-click on xLights target
2. Add Files to "xLights"...
3. Select all `.h`, `.m`, and `.mm` files from `native-mac/`
4. Ensure "Copy items if needed" is **unchecked** (files are already in repo)
5. Ensure "Create groups" is selected
6. Ensure "xLights" target is checked

### 2. Update Info.plist

Open `macOS/Info.plist` and merge the following from `Info.plist.snippet`:

#### CFBundleDocumentTypes
Add three document type entries:
- xLights Sequence (.xlights, .xsq, .xml)
- FSEQ Sequence (.fseq)
- Show Folder (directory)

#### UTExportedTypeDeclarations
Add three UTI declarations:
- org.xlights.sequence
- org.xlights.fseq
- org.xlights.showfolder

#### NSDocumentController
Set custom document controller:
```xml
<key>NSDocumentController</key>
<string>XLDocumentController</string>
```

#### NSPrincipalClass
Ensure NSApplication is set:
```xml
<key>NSPrincipalClass</key>
<string>NSApplication</string>
```

See `Info.plist.snippet` for complete XML.

### 3. Update main.mm

Replace the existing `main.mm` (or create if missing):

```objc
#import <Cocoa/Cocoa.h>
#import "XLAppDelegate.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Initialize application
        NSApplication *app = [NSApplication sharedApplication];

        // Set custom app delegate
        XLAppDelegate *delegate = [[XLAppDelegate alloc] init];
        [app setDelegate:delegate];

        // Run app
        return NSApplicationMain(argc, argv);
    }
}
```

### 4. Build Settings

#### Header Search Paths
Add to xLights target:
- `$(SRCROOT)/xLights/native-mac`
- `$(SRCROOT)/xLights/engine`

#### Compiler Flags
For all Objective-C files:
- Enable ARC: `-fobjc-arc`
- Objective-C++ standard: `-std=gnu++20`

#### Frameworks
Link against:
- Cocoa.framework (should already be linked)
- Metal.framework (for future Metal views)
- MetalKit.framework (for future Metal views)

### 5. Document Icons (Optional)

Create `.icns` files for document types:
- `xlights_document.icns` - xLights sequence icon
- `fseq_document.icns` - FSEQ sequence icon
- `showfolder.icns` - Show folder icon

Add to Resources folder and reference in Info.plist.

## Testing the Integration

### Basic File Opening

1. **Build and run** the app
2. **Test opening files**:
   - File → Open → select .xlights file
   - File → Open → select .fseq file
   - File → Open → select show folder
   - Drag .xlights file onto dock icon
   - Double-click .xlights file in Finder

3. **Verify Recent Files**:
   - File → Open Recent → should show recently opened files
   - Recent items persist across app restarts

4. **Verify Dirty State**:
   - Open a sequence
   - Modify it (when edit UI is implemented)
   - Check close button has unsaved changes dot
   - Cmd+S to save
   - Dot disappears

### Show Folder Detection

Test show folder opening:
```bash
# Create test show folder
mkdir -p ~/TestShow
touch ~/TestShow/xlights_rgbeffects.xml
touch ~/TestShow/test.xlights

# Open in xLights
open -a xLights ~/TestShow
```

Should detect as show folder and open.

### URL Handler (Future)

Once implemented, test URL scheme:
```bash
open "xlights://show/path/to/show/folder"
```

## Troubleshooting

### Problem: Files don't open in xLights when double-clicked

**Solution**: Check Info.plist UTI registration
- Ensure `CFBundleDocumentTypes` is correct
- Ensure `UTExportedTypeDeclarations` is correct
- Run `lsregister -f /path/to/xLights.app` to re-register

### Problem: Recent Files menu is empty

**Solution**: NSDocument handles this automatically
- Ensure XLDocumentController is registered in Info.plist
- Check that files are being opened via NSDocumentController
- Verify NSDocumentController.noteNewRecentDocumentURL is called

### Problem: Dirty state doesn't update

**Solution**: Check XLDocumentBridge integration
- Ensure XLDocumentBridge::updateDocumentDirtyState is called
- Verify it's called from xLightsFrame when sequence is modified
- Check that document is associated with frame via setCurrentDocument

### Problem: App crashes on launch

**Solution**: Check main.mm
- Ensure XLAppDelegate is properly initialized
- Verify all Objective-C code compiles with ARC enabled
- Check for missing framework links

### Problem: "Unknown document type" error

**Solution**: Type registration mismatch
- Check XLDocumentController.typeForContentsOfURL
- Verify file extension is in UTI tag specification
- Ensure document class is registered for type

## Runtime Architecture

### Startup Flow

1. `main()` creates NSApplication
2. `XLAppDelegate.applicationWillFinishLaunching:` creates `XLDocumentController`
3. NSDocumentController registered as shared instance
4. User opens file → `XLDocumentController.openDocumentWithContentsOfURL:`
5. Creates `XLDocument` instance
6. `XLDocument.readFromURL:` calls `SequenceEngine::loadSequence()`
7. `XLDocument.makeWindowControllers` creates `XLMainWindowController`
8. Window displays with loaded sequence

### Save Flow

1. User presses Cmd+S or File → Save
2. `XLDocument.writeToURL:` called by NSDocument
3. Calls `SequenceEngine::saveSequence(path)`
4. On success, dirty state cleared
5. Recent Files updated

### Dirty State Flow

1. User modifies sequence in UI
2. UI code calls `XLDocumentBridge::updateDocumentDirtyState(frame, true)`
3. Bridge finds associated XLDocument
4. Calls `[document updateChangeCount:NSChangeDone]`
5. macOS displays dot in close button

### Show Folder Flow

1. User opens directory via File → Open
2. `XLDocumentController.typeForContentsOfURL:` detects show folder
3. Returns "Show Folder" type
4. `XLDocument.readShowFolder:` loads xlights_rgbeffects.xml
5. Sets `showFolderURL` property
6. Window displays show folder contents

## Next Steps

### Immediate
- [ ] Test file opening in Xcode simulator
- [ ] Test Recent Files menu
- [ ] Test dirty state tracking
- [ ] Test drag-and-drop

### Phase 1B (Menus & Toolbar)
- [ ] Implement File menu actions (New, Open, Save, Close)
- [ ] Wire up to XLDocument actions
- [ ] Implement Edit menu (Undo, Redo)
- [ ] Add NSUndoManager integration

### Phase 1D (Preferences)
- [ ] Implement preferences window
- [ ] Wire up XLAppDelegate.showPreferences

### Future Integration
- [ ] Wire SequenceEngine to XLDocument (requires xLightsFrame bridge)
- [ ] Implement ModelEngine for show folder model loading
- [ ] Implement OutputEngine for controller loading

## Reference Files

- **Implementation Guide**: `/IMPLEMENTATION_GUIDE.md`
- **Phase 1C Done**: `/.beads/notes/xlmac-chg-done.md`
- **Engine APIs**: `/xLights/engine/*.h`
- **Spike Prototypes**:
  - `/xLights/spikes/AppKitInspector/`
  - `/xLights/spikes/MetalTimeline/`
