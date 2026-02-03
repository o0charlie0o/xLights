# Integration Guide for Native macOS Preferences

This guide shows how to integrate the native macOS preferences window into the xLights Xcode project.

## Xcode Project Integration

### Step 1: Add Files to Project

Add all files in `xLights/native-mac/` to the Xcode project:

```
xLights/native-mac/
├── XLApplication.h
├── XLApplication.mm
└── preferences/
    ├── XLPreferencesWindowController.h
    ├── XLPreferencesWindowController.mm
    ├── XLBasePreferencesViewController.h
    ├── XLBasePreferencesViewController.m
    └── XL*PreferencesViewController.h/m (10 pairs)
```

**In Xcode:**
1. Right-click on the xLights project in the navigator
2. Select "Add Files to xLights..."
3. Navigate to `xLights/native-mac/`
4. Check "Create groups"
5. Ensure target membership includes "xLights"
6. Click "Add"

### Step 2: Update Build Settings

No special build settings required. The files use:
- Standard Objective-C (.m files)
- Objective-C++ (.mm files for bridge code)
- ARC (Automatic Reference Counting) enabled by default

### Step 3: Update Info.plist (Optional)

Add keyboard shortcut to Info.plist:

```xml
<key>NSUserKeyEquivalents</key>
<dict>
    <key>Preferences...</key>
    <string>@,</string>
</dict>
```

This ensures Cmd+, is system-wide registered.

## App Initialization

### Option A: From AppDelegate (Recommended)

In your app delegate's `applicationDidFinishLaunching:`:

```objc
#import "native-mac/XLApplication.h"

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Other initialization...

    // Set up preferences menu and keyboard shortcut
    XLApplication *xlApp = [[XLApplication alloc] init];
    [xlApp applicationDidFinishLaunching:notification];
}
```

### Option B: Manual Menu Integration

If you have an existing menu setup:

```objc
#import "native-mac/preferences/XLPreferencesWindowController.h"

- (void)setupMenus {
    NSMenu *appMenu = [[[NSApplication sharedApplication] mainMenu] itemAtIndex:0].submenu;

    NSMenuItem *prefsItem = [[NSMenuItem alloc] initWithTitle:@"Preferences..."
                                                       action:@selector(showPreferences:)
                                                keyEquivalent:@","];
    prefsItem.target = self;

    [appMenu insertItem:prefsItem atIndex:2]; // After "About"
    [appMenu insertItem:[NSMenuItem separatorItem] atIndex:3];
}

- (void)showPreferences:(id)sender {
    [[XLPreferencesWindowController sharedController] showWindow:sender];
}
```

## Calling from C++ Code

If you need to open preferences from C++ code:

### Create a C++ Bridge Header

```cpp
// PreferencesBridge.h
#pragma once

namespace xlights {
    void showPreferences();
}
```

### Implement in Objective-C++

```objc
// PreferencesBridge.mm
#import "PreferencesBridge.h"
#import "native-mac/XLApplication.h"

namespace xlights {
    void showPreferences() {
        [XLApplication showPreferences];
    }
}
```

### Call from C++

```cpp
#include "PreferencesBridge.h"

void someFunction() {
    xlights::showPreferences();
}
```

## Testing

### Test Checklist

- [ ] Cmd+, opens preferences window
- [ ] Window has toolbar with 10 items
- [ ] All toolbar items are selectable
- [ ] Clicking toolbar items switches panes
- [ ] Window resizes when switching panes
- [ ] Settings persist across app launches
- [ ] Settings apply immediately when changed
- [ ] Window can be reopened after closing
- [ ] Only one preferences window instance exists

### Manual Testing

1. **Launch the app**
2. **Press Cmd+,** → Preferences window should open
3. **Click each toolbar item** → Corresponding pane should display
4. **Change some settings** → Should save immediately
5. **Close and reopen preferences** → Settings should be restored
6. **Quit and relaunch app** → Settings should persist

### Debugging

If preferences don't appear:

1. **Check console for errors:**
   ```
   Product > Scheme > Edit Scheme > Run > Arguments
   Add: -NSShowNonLocalizedStrings YES
   ```

2. **Verify files are included in target:**
   - Select each .h/.m/.mm file
   - Check "Target Membership" in File Inspector
   - Ensure "xLights" is checked

3. **Verify menu setup:**
   - Set breakpoint in `XLApplication.setupMenus`
   - Verify it's being called
   - Check menu item is added

4. **Verify singleton:**
   ```objc
   NSLog(@"Prefs controller: %@", [XLPreferencesWindowController sharedController]);
   ```

## Settings Migration

If migrating from wxWidgets preferences:

### Read Existing Settings

```objc
- (void)migrateFromWxPreferences {
    // Example: Read from wxWidgets config file
    NSString *wxConfigPath = [@"~/xlights.config" stringByExpandingTildeInPath];

    if ([[NSFileManager defaultManager] fileExistsAtPath:wxConfigPath]) {
        // Parse wx config...
        // Write to NSUserDefaults...
        [[NSUserDefaults standardUserDefaults] setBool:renderOnSave forKey:@"RenderOnSave"];
        // etc.
    }
}
```

### Call on First Launch

```objc
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"PreferencesMigrated"]) {
        [self migrateFromWxPreferences];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"PreferencesMigrated"];
    }
}
```

## Engine Integration

### Wire Settings to Engine APIs

Example for SequenceEngine:

```objc
- (void)saveSettings {
    // Save to NSUserDefaults
    [[NSUserDefaults standardUserDefaults] setBool:self.renderOnSaveCheckbox.state forKey:@"RenderOnSave"];

    // Apply to engine (if available)
    if (self.sequenceEngine) {
        // Apply setting to engine
        // self.sequenceEngine->setRenderOnSave(self.renderOnSaveCheckbox.state);
    }
}
```

### Create Engine Properties

Add to view controller:

```objc
@property (nonatomic, assign) xlEngine::SequenceEngine* sequenceEngine;
```

Set when creating pane:

```objc
XLSequenceFilePreferencesViewController *vc = [[XLSequenceFilePreferencesViewController alloc] init];
vc.sequenceEngine = &engineInstance;
```

## Customization

### Add New Preference Pane

1. **Create view controller:**
   ```objc
   // XLMyNewPreferencesViewController.h
   #import "XLBasePreferencesViewController.h"

   @interface XLMyNewPreferencesViewController : XLBasePreferencesViewController
   @end
   ```

2. **Implement loadView:**
   ```objc
   // XLMyNewPreferencesViewController.m
   - (void)loadView {
       self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
       // Add controls...
   }
   ```

3. **Register in window controller:**
   ```objc
   // XLPreferencesWindowController.mm
   - (void)setupViewControllers {
       // ... existing panes ...
       self.viewControllers[@"myNewPane"] = [[XLMyNewPreferencesViewController alloc] init];
   }
   ```

4. **Add toolbar item:**
   ```objc
   - (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier ... {
       // ... existing items ...
       else if ([itemIdentifier isEqualToString:@"myNewPane"]) {
           item.label = @"My New Pane";
           item.image = [NSImage imageWithSystemSymbolName:@"star" accessibilityDescription:@"My New Pane"];
       }
       // ...
   }
   ```

### Change Toolbar Icons

Replace SF Symbol names in `toolbar:itemForItemIdentifier:`:

```objc
item.image = [NSImage imageWithSystemSymbolName:@"new-symbol-name"
                          accessibilityDescription:@"Description"];
```

Available SF Symbols: https://developer.apple.com/sf-symbols/

### Change Settings Storage

To use a different storage mechanism:

1. **Create protocol:**
   ```objc
   @protocol XLSettingsStore <NSObject>
   - (id)objectForKey:(NSString *)key;
   - (void)setObject:(id)object forKey:(NSString *)key;
   @end
   ```

2. **Update base class:**
   ```objc
   @property (nonatomic, strong) id<XLSettingsStore> settingsStore;
   ```

3. **Implement for your storage:**
   ```objc
   @interface MyCustomStore : NSObject <XLSettingsStore>
   @end

   @implementation MyCustomStore
   - (id)objectForKey:(NSString *)key {
       // Read from your storage
   }
   - (void)setObject:(id)object forKey:(NSString *)key {
       // Write to your storage
   }
   @end
   ```

## Troubleshooting

### Preferences Window Doesn't Open

**Symptoms:** Cmd+, does nothing, menu item disabled

**Solutions:**
1. Verify XLApplication is initialized
2. Check menu item target/action are set
3. Ensure files are compiled (check Build Phases)
4. Look for exceptions in console

### Settings Don't Persist

**Symptoms:** Settings reset on app relaunch

**Solutions:**
1. Verify NSUserDefaults synchronize is called
2. Check sandboxing entitlements (if sandboxed)
3. Verify keys are consistent
4. Check console for write permissions errors

### Window Resizing Issues

**Symptoms:** Window too large/small, doesn't resize

**Solutions:**
1. Verify view controller's view.fittingSize is correct
2. Check autoresizing masks are set
3. Ensure constraints are properly configured
4. Set minimum/maximum window sizes if needed

### Panes Don't Switch

**Symptoms:** Clicking toolbar items doesn't change content

**Solutions:**
1. Verify viewControllers dictionary is populated
2. Check toolbar item identifiers match dictionary keys
3. Ensure toolbarItemSelected: is called
4. Verify view hierarchy in Xcode View Debugger

## Performance Considerations

### Lazy Loading

View controllers are created once and cached:
```objc
// First access
XLSequenceFilePreferencesViewController *vc = self.viewControllers[@"sequences"];
// View is loaded on first display
// Subsequent accesses use cached instance
```

### Memory Management

All view controllers live for the window's lifetime (singleton pattern). This is intentional:
- Avoids repeated view creation
- Preserves user's position in settings
- Follows macOS preferences pattern

If memory is a concern, implement cache eviction:
```objc
- (void)didReceiveMemoryWarning {
    for (NSString *key in self.viewControllers) {
        if (![key isEqualToString:self.toolbar.selectedItemIdentifier]) {
            NSViewController *vc = self.viewControllers[key];
            if (vc.isViewLoaded) {
                [vc.view removeFromSuperview];
                // View will be recreated on next access
            }
        }
    }
}
```

## Next Steps

1. Complete stub implementations for remaining 8 panes
2. Wire all settings to engine APIs
3. Add tooltips to all controls
4. Implement validation for paths, IP addresses, etc.
5. Add restore defaults button to each pane
6. Implement search/filter functionality
7. Add export/import for preference profiles
8. Write unit tests for settings persistence

## Support

For questions or issues:
1. Check ARCHITECTURE.md for component details
2. Review README.md for feature documentation
3. Examine spike prototypes for patterns
4. Refer to existing implementations (Sequences, Effects Grid panes)
