# Toolbar and Menu Bar Integration Guide (Phase 1B)

Step-by-step instructions for integrating the NSToolbar and menu bar implementation into the xLights Xcode project.

## Overview

This guide covers integration of:
- Enhanced NSToolbar with transport controls, tool mode selector, zoom controls, and search field
- Complete native macOS menu bar with all 9 menus
- Keyboard shortcut wiring following macOS conventions
- Toolbar customization support

## Prerequisites

- Phase 1A completed (XLMainWindowController basic implementation)
- Engine APIs from Phase 0 in place
- XLEngineBridge implemented

## Files to Add

Add these files to the Xcode project under the `native-mac` group:

```
xLights/native-mac/
├── XLToolbarExtensions.h         (toolbar builder declarations)
└── XLToolbarExtensions.mm        (toolbar + menu builders)
```

Optional documentation:
```
xLights/native-mac/
└── KEYBOARD_SHORTCUTS.md         (keyboard shortcut reference)
```

## Step 1: Add Files to Xcode Project

1. Open `xLights.xcodeproj` in Xcode
2. Right-click the `native-mac` group in Project Navigator
3. Select "Add Files to xLights..."
4. Navigate to `xLights/native-mac/`
5. Select:
   - `XLToolbarExtensions.h`
   - `XLToolbarExtensions.mm`
   - `KEYBOARD_SHORTCUTS.md` (optional)
6. Ensure "Copy items if needed" is **unchecked**
7. Ensure "Create groups" is selected
8. Ensure "xLights" target is checked
9. Click "Add"

## Step 2: Import Header in XLMainWindowController.mm

Add import at the top of `XLMainWindowController.mm`:

```objc
#import "XLToolbarExtensions.h"
```

## Step 3: Enhance setupToolbar Method

Replace the existing `setupToolbar` method in `XLMainWindowController.mm`:

```objc
- (void)setupToolbar {
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"XLMainToolbar"];
    toolbar.delegate = self;
    toolbar.allowsUserCustomization = YES;
    toolbar.autosavesConfiguration = YES;
    toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    self.window.toolbar = toolbar;
}
```

## Step 4: Update Toolbar Delegate Methods

### Update toolbarDefaultItemIdentifiers:

```objc
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[
        @"TabSelector",
        NSToolbarFlexibleSpaceItemIdentifier,
        XLToolbarItemTransportGroup,
        NSToolbarFlexibleSpaceItemIdentifier,
        XLToolbarItemToolMode,
        NSToolbarSpaceItemIdentifier,
        XLToolbarItemZoom,
        NSToolbarFlexibleSpaceItemIdentifier,
        @"ToggleInspector",
        @"ToggleBottomPanel",
        XLToolbarItemPreview,
        NSToolbarSpaceItemIdentifier,
        XLToolbarItemSearch
    ];
}
```

### Update toolbarAllowedItemIdentifiers:

```objc
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[
        @"TabSelector",
        @"Play",
        @"Pause",
        @"Stop",
        @"Render",
        @"ToggleInspector",
        @"ToggleBottomPanel",
        XLToolbarItemTransportGroup,
        XLToolbarItemSeekStart,
        XLToolbarItemSeekEnd,
        XLToolbarItemToolMode,
        XLToolbarItemZoom,
        XLToolbarItemSearch,
        XLToolbarItemPreview,
        NSToolbarFlexibleSpaceItemIdentifier,
        NSToolbarSpaceItemIdentifier
    ];
}
```

### Enhance toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:

Add these cases to the existing method:

```objc
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];

    // ... keep existing cases for TabSelector, Play, Pause, Stop, Render, etc. ...

    // Add new toolbar item cases:
    if ([itemIdentifier isEqualToString:XLToolbarItemTransportGroup]) {
        return [XLToolbarBuilder createTransportGroupWithTarget:self];
    }
    else if ([itemIdentifier isEqualToString:XLToolbarItemToolMode]) {
        return [XLToolbarBuilder createToolModeControlWithTarget:self];
    }
    else if ([itemIdentifier isEqualToString:XLToolbarItemZoom]) {
        return [XLToolbarBuilder createZoomControlWithTarget:self];
    }
    else if ([itemIdentifier isEqualToString:XLToolbarItemSearch]) {
        return [XLToolbarBuilder createSearchFieldWithTarget:self delegate:self];
    }
    else if ([itemIdentifier isEqualToString:XLToolbarItemPreview]) {
        return [XLToolbarBuilder createPreviewToggleWithTarget:self];
    }
    else if ([itemIdentifier isEqualToString:XLToolbarItemSeekStart]) {
        item.label = @"Start";
        item.paletteLabel = @"Seek to Start";
        item.toolTip = @"Seek to start (⌘[)";
        item.image = [NSImage imageWithSystemSymbolName:@"backward.end.fill" accessibilityDescription:@"Seek to Start"];
        item.action = @selector(seekToStart:);
        item.target = self;
    }
    else if ([itemIdentifier isEqualToString:XLToolbarItemSeekEnd]) {
        item.label = @"End";
        item.paletteLabel = @"Seek to End";
        item.toolTip = @"Seek to end (⌘])";
        item.image = [NSImage imageWithSystemSymbolName:@"forward.end.fill" accessibilityDescription:@"Seek to End"];
        item.action = @selector(seekToEnd:);
        item.target = self;
    }

    return item;
}
```

## Step 5: Add Menu Bar Setup

In the `windowDidLoad` method, add menu bar setup before toolbar setup:

```objc
- (void)windowDidLoad {
    [super windowDidLoad];

    // Configure window (existing code)
    // ...

    // Add menu bar (NEW)
    [XLMenuBuilder buildMenuBarForApplication:NSApp target:self];

    // Setup toolbar (existing code)
    [self setupToolbar];

    // Rest of existing setup...
}
```

## Step 6: Add NSSearchFieldDelegate Conformance

Update XLMainWindowController.h interface declaration:

```objc
@interface XLMainWindowController : NSWindowController <NSSplitViewDelegate, NSToolbarDelegate, NSSearchFieldDelegate>
```

## Step 7: Implement Action Methods

Add these action method implementations to `XLMainWindowController.mm`:

### Transport Actions

```objc
#pragma mark - Additional Transport Actions

- (void)seekToStart:(id)sender {
    [_engineBridge seek:0];
}

- (void)seekToEnd:(id)sender {
    // TODO: Requires SequenceEngine::getDuration()
    // For now, just log
    NSLog(@"Seek to end requested");
}
```

### Tool Mode Actions

```objc
#pragma mark - Tool Mode Actions

- (void)toolModeChanged:(NSSegmentedControl *)sender {
    NSInteger mode = sender.selectedSegment;

    // Forward to active view controller
    NSViewController *currentVC = nil;
    if (_currentTab == 0) currentVC = _setupViewController;
    else if (_currentTab == 1) currentVC = _layoutViewController;
    else if (_currentTab == 2) currentVC = _sequencerViewController;

    if ([currentVC respondsToSelector:@selector(setToolMode:)]) {
        [currentVC performSelector:@selector(setToolMode:) withObject:@(mode)];
    }
}
```

### Zoom Actions

```objc
#pragma mark - Zoom Actions

- (void)zoomControlChanged:(NSSegmentedControl *)sender {
    NSInteger segment = sender.selectedSegment;

    if (segment == 0) [self zoomOut:sender];
    else if (segment == 1) [self zoomIn:sender];
    else if (segment == 2) [self zoomToFit:sender];
}

- (void)zoomIn:(id)sender {
    [self forwardZoomActionToCurrentViewController:@selector(zoomIn:) sender:sender];
}

- (void)zoomOut:(id)sender {
    [self forwardZoomActionToCurrentViewController:@selector(zoomOut:) sender:sender];
}

- (void)zoomToFit:(id)sender {
    [self forwardZoomActionToCurrentViewController:@selector(zoomToFit:) sender:sender];
}

- (void)forwardZoomActionToCurrentViewController:(SEL)action sender:(id)sender {
    NSViewController *currentVC = nil;
    if (_currentTab == 0) currentVC = _setupViewController;
    else if (_currentTab == 1) currentVC = _layoutViewController;
    else if (_currentTab == 2) currentVC = _sequencerViewController;

    if ([currentVC respondsToSelector:action]) {
        [currentVC performSelector:action withObject:sender];
    }
}
```

### Search Actions

```objc
#pragma mark - Search Actions

- (void)searchFieldChanged:(NSSearchField *)sender {
    NSString *query = sender.stringValue;
    NSLog(@"Search query: %@", query);
    // TODO: Implement search filtering across effects and models
}

#pragma mark - NSSearchFieldDelegate

- (void)controlTextDidChange:(NSNotification *)notification {
    if ([notification.object isKindOfClass:[NSSearchField class]]) {
        NSSearchField *searchField = notification.object;
        [self searchFieldChanged:searchField];
    }
}
```

### View Toggle Actions

```objc
#pragma mark - View Toggle Actions

- (void)togglePreview:(id)sender {
    // TODO: Implement preview window management
    NSLog(@"Toggle preview requested");
}
```

### Menu Action Stubs

```objc
#pragma mark - Menu Action Stubs

- (void)newSequence:(id)sender {
    NSLog(@"New sequence requested");
}

- (void)openSequence:(id)sender {
    NSLog(@"Open sequence requested");
}

- (void)saveDocument:(id)sender {
    if (_engineBridge.isSequenceLoaded) {
        [_engineBridge saveSequence:nil];
    }
}

- (void)saveDocumentAs:(id)sender {
    NSLog(@"Save as requested");
}

- (void)showPreferences:(id)sender {
    NSLog(@"Show preferences requested");
}

- (void)addModel:(id)sender {
    NSLog(@"Add model requested");
}

- (void)addModelGroup:(id)sender {
    NSLog(@"Add model group requested");
}

- (void)applyEffect:(id)sender {
    NSLog(@"Apply effect requested");
}

- (void)showHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://xlights.org/docs"]];
}

- (void)visitWebsite:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://xlights.org"]];
}

- (void)checkForUpdates:(id)sender {
    NSLog(@"Check for updates requested");
}

- (void)showReleaseNotes:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/xLightsSequencer/xLights/releases"]];
}

// Additional stubs (placeholder implementations)
- (void)importEffects:(id)sender {}
- (void)importModels:(id)sender {}
- (void)importControllers:(id)sender {}
- (void)exportEffects:(id)sender {}
- (void)exportModels:(id)sender {}
- (void)exportVideo:(id)sender {}
- (void)addTimingTrack:(id)sender {}
- (void)importTiming:(id)sender {}
- (void)generateTiming:(id)sender {}
- (void)showSequenceProperties:(id)sender {}
- (void)cloneModel:(id)sender {}
- (void)deleteModel:(id)sender {}
- (void)showModelProperties:(id)sender {}
- (void)editSubmodels:(id)sender {}
- (void)editModelStates:(id)sender {}
- (void)alignModels:(id)sender {}
- (void)distributeModels:(id)sender {}
- (void)copyEffect:(id)sender {}
- (void)pasteEffect:(id)sender {}
- (void)deleteEffect:(id)sender {}
- (void)convertEffectType:(id)sender {}
- (void)duplicateEffect:(id)sender {}
- (void)showEffectPresets:(id)sender {}
- (void)renderSelected:(id)sender {}
```

## Step 8: Build and Test

1. Build the project: **⌘B**
2. Run the app: **⌘R**
3. Verify toolbar displays correctly
4. Verify all menu items are present
5. Test keyboard shortcuts
6. Test toolbar customization (right-click toolbar → "Customize Toolbar...")

## Verification Checklist

After integration, verify these features work:

### Toolbar
- [ ] Transport group displays with 5 buttons (seek start, play, pause, stop, seek end)
- [ ] Tool mode selector displays with 4 segments (Select, Effects Paint, Draw, Timing)
- [ ] Zoom control displays with 3 buttons (zoom in, out, fit)
- [ ] Search field displays and accepts input
- [ ] Preview toggle button displays
- [ ] Inspector toggle button displays
- [ ] Bottom panel toggle button displays
- [ ] Tab selector displays (from Phase 1A)

### Menu Bar
- [ ] Application menu (xLights) displays
- [ ] File menu displays with all items
- [ ] Edit menu displays with all items
- [ ] View menu displays with all items
- [ ] Sequence menu displays with all items
- [ ] Model menu displays with all items
- [ ] Effect menu displays with all items
- [ ] Window menu displays with all items
- [ ] Help menu displays with all items

### Keyboard Shortcuts
- [ ] Space plays/pauses sequence
- [ ] ⌘. stops playback
- [ ] ⌘[ seeks to start
- [ ] ⌘] seeks to end
- [ ] ⌘S saves document
- [ ] ⌘I toggles inspector
- [ ] ⌘B toggles bottom panel
- [ ] ⌘+/⌘-/⌘0 zoom actions
- [ ] ⌘F focuses search field
- [ ] All other shortcuts (see KEYBOARD_SHORTCUTS.md)

### Toolbar Customization
- [ ] Right-click toolbar shows "Customize Toolbar..." option
- [ ] Customization palette displays all available items
- [ ] Items can be dragged to/from toolbar
- [ ] Changes persist across app restarts

## Troubleshooting

### Toolbar items don't appear

**Check**: `toolbarDefaultItemIdentifiers:` returns correct array
**Check**: Toolbar delegate is set: `toolbar.delegate = self`
**Check**: `toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:` returns non-nil for each identifier

### Menu bar doesn't appear

**Check**: `buildMenuBarForApplication:` is called in `windowDidLoad`
**Check**: Call happens before window displays
**Check**: NSApp (not nil) is passed to builder

### Keyboard shortcuts don't work

**Check**: Menu items have correct `keyEquivalent`
**Check**: Window is key and accepts keyboard input
**Check**: No conflicting shortcuts from system or other apps

### Search field doesn't accept input

**Check**: `NSSearchFieldDelegate` is declared in interface
**Check**: Delegate is set when creating search field
**Check**: `controlTextDidChange:` is implemented

### SF Symbols don't display

**Check**: Deployment target is macOS 11.0+
**Check**: Symbol names are correct (e.g., `play.fill`, not `play`)
**Check**: Provide fallback images for older macOS if needed

## Optional Enhancements

### Add Menu Validation

Implement `validateMenuItem:` to enable/disable menu items based on state:

```objc
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;

    if (action == @selector(saveDocument:)) {
        return _engineBridge.isSequenceLoaded;
    }
    else if (action == @selector(renderAll:)) {
        return _engineBridge.isSequenceLoaded;
    }
    else if (action == @selector(playSequence:)) {
        return _engineBridge.isSequenceLoaded;
    }

    return YES; // Enable by default
}
```

### Add Touch Bar Support

Create Touch Bar items for transport controls (requires macOS 10.12.2+):

```objc
- (NSTouchBar *)makeTouchBar {
    NSTouchBar *touchBar = [[NSTouchBar alloc] init];
    touchBar.defaultItemIdentifiers = @[
        @"PlayButton",
        @"PauseButton",
        @"StopButton"
    ];
    return touchBar;
}
```

## Next Steps

After successful integration:

1. **Wire up Document Integration (Phase 1C)**
   - Connect File menu to NSDocument actions
   - Implement recent files tracking

2. **Implement Preferences Window (Phase 1D)**
   - Create preferences window controller
   - Wire up Preferences… menu item

3. **Begin Phase 2 (Setup Tab)**
   - Implement controller table view
   - Add controller detail inspector

## References

- **Keyboard Shortcuts**: `xLights/native-mac/KEYBOARD_SHORTCUTS.md`
- **Completion Summary**: `.beads/notes/xlmac-xes-done.md`
- **Implementation Guide**: `IMPLEMENTATION_GUIDE.md` (Phase 1A/1C)
- **Apple Documentation**:
  - [NSToolbar](https://developer.apple.com/documentation/appkit/nstoolbar)
  - [NSMenu](https://developer.apple.com/documentation/appkit/nsmenu)
  - [NSToolbarItemGroup](https://developer.apple.com/documentation/appkit/nstoolbaritemgroup)
- **Spike Prototypes**:
  - `xLights/spikes/AppKitInspector/`
  - `xLights/spikes/MetalTimeline/`
