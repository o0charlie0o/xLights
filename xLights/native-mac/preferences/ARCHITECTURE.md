# Native macOS Preferences Architecture

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        XLApplication                             │
│                 (App Delegate Integration)                       │
│                                                                   │
│  + showPreferences()                                             │
│  + setupMenus()              Cmd+,                              │
│  + showPreferencesMenu:      ─────┐                             │
└─────────────────────────────────────┼───────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────┐
│           XLPreferencesWindowController (Singleton)              │
│                                                                   │
│  + sharedController                                              │
│  + showWindow:                                                   │
│  - setupToolbar                                                  │
│  - selectPaneWithIdentifier:                                     │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                      NSToolbar                             │ │
│  │  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ...                  │ │
│  │  │🗄️ │ │👁️ │ │📊│ │📝│ │💡│                          │ │
│  │  └────┘ └────┘ └────┘ └────┘ └────┘                       │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │              Content Container View                        │ │
│  │  ┌─────────────────────────────────────────────────────┐  │ │
│  │  │     Current Pane View Controller                    │  │ │
│  │  │     (swapped on toolbar selection)                  │  │ │
│  │  └─────────────────────────────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                      │
        ┌─────────────────────────────┴─────────────────────────────┐
        │                                                             │
        ▼                                                             ▼
┌──────────────────────┐                                  ┌──────────────────────┐
│ XLBasePreferences    │                                  │   View Controllers   │
│    ViewController    │                                  │   Dictionary         │
│                      │                                  │                      │
│ - loadSettings       │◄─────────────────────────────────│ viewControllers[@""] │
│ - saveSettings       │                                  │                      │
│ - viewDidLoad        │                                  │ • backup             │
│ - viewWillDisappear  │                                  │ • view               │
└──────────────────────┘                                  │ • effectsGrid        │
           ▲                                              │ • sequences          │
           │                                              │ • output             │
           │ inherits                                     │ • checkSequence      │
           │                                              │ • randomEffects      │
    ┌──────┴──────────────────────────────┐              │ • colorManager       │
    │                                      │              │ • other              │
    │                                      │              │ • services           │
    ▼                                      ▼              └──────────────────────┘
┌─────────────────────┐      ┌─────────────────────┐
│ XLSequenceFile      │      │ XLEffectsGrid       │
│ PreferencesView     │      │ PreferencesView     │
│ Controller          │      │ Controller          │
│                     │      │                     │
│ Fully Implemented   │      │ Fully Implemented   │
│                     │      │                     │
│ • Checkboxes        │      │ • Checkboxes        │
│ • PopUpButtons      │      │ • PopUpButtons      │
│ • NSPathControls    │      │ • Spacing popup     │
│ • NSBox sections    │      │ • Behavior flags    │
└─────────────────────┘      └─────────────────────┘
           │                            │
           └─────────┬──────────────────┘
                     │
                     ▼
           ┌───────────────────┐
           │   NSUserDefaults  │
           │                   │
           │  Settings Store   │
           │                   │
           │  • Keys mirror    │
           │    existing prefs │
           │  • Cross-launch   │
           │    persistence    │
           └───────────────────┘
```

## Data Flow

### Opening Preferences
```
User presses Cmd+,
    │
    ▼
XLApplication.showPreferencesMenu:
    │
    ▼
XLPreferencesWindowController.sharedController
    │
    ▼
showWindow:
    │
    ├──► Window becomes visible
    ├──► Toolbar displays with 10 items
    └──► First pane ("sequences") loads
```

### Switching Panes
```
User clicks toolbar item
    │
    ▼
toolbarItemSelected:
    │
    ▼
selectPaneWithIdentifier:
    │
    ├──► Current pane's viewWillDisappear called
    │    └──► saveSettings (writes to NSUserDefaults)
    │
    ├──► New pane retrieved from viewControllers dictionary
    │
    ├──► New pane's view added to contentContainerView
    │
    ├──► New pane's viewDidLoad called
    │    └──► loadSettings (reads from NSUserDefaults)
    │
    └──► Window resizes to fit new pane
```

### Settings Persistence
```
User changes setting (checkbox, popup, etc.)
    │
    ▼
settingChanged: action
    │
    ▼
saveSettings
    │
    ▼
NSUserDefaults setObject:forKey: / setBool:forKey: / setInteger:forKey:
    │
    ▼
[defaults synchronize]
    │
    └──► Setting persisted to disk
```

### Settings Restoration
```
Pane becomes visible
    │
    ▼
viewDidLoad
    │
    ▼
loadSettings
    │
    ▼
NSUserDefaults objectForKey: / boolForKey: / integerForKey:
    │
    ├──► Checkboxes set to saved state
    ├──► PopUpButtons select saved item
    └──► PathControls set to saved URLs
```

## Class Hierarchy

```
NSObject
    │
    ├── NSWindowController
    │       │
    │       └── XLPreferencesWindowController
    │
    ├── NSViewController
    │       │
    │       └── XLBasePreferencesViewController
    │               │
    │               ├── XLBackupPreferencesViewController
    │               ├── XLViewPreferencesViewController
    │               ├── XLEffectsGridPreferencesViewController
    │               ├── XLSequenceFilePreferencesViewController
    │               ├── XLOutputPreferencesViewController
    │               ├── XLCheckSequencePreferencesViewController
    │               ├── XLRandomEffectsPreferencesViewController
    │               ├── XLColorManagerPreferencesViewController
    │               ├── XLOtherPreferencesViewController
    │               └── XLServicesPreferencesViewController
    │
    └── NSApplicationDelegate (protocol)
            │
            └── XLApplication
```

## File Organization

```
xLights/native-mac/
│
├── XLApplication.h/mm
│   └── App delegate, Cmd+, shortcut handler
│
└── preferences/
    │
    ├── XLPreferencesWindowController.h/mm
    │   └── Singleton window controller, NSToolbar management
    │
    ├── XLBasePreferencesViewController.h/m
    │   └── Base class for all panes
    │
    ├── XL*PreferencesViewController.h/m (10 pairs)
    │   ├── XLBackupPreferencesViewController
    │   ├── XLViewPreferencesViewController
    │   ├── XLEffectsGridPreferencesViewController
    │   ├── XLSequenceFilePreferencesViewController
    │   ├── XLOutputPreferencesViewController
    │   ├── XLCheckSequencePreferencesViewController
    │   ├── XLRandomEffectsPreferencesViewController
    │   ├── XLColorManagerPreferencesViewController
    │   ├── XLOtherPreferencesViewController
    │   └── XLServicesPreferencesViewController
    │
    ├── README.md
    │   └── Comprehensive documentation
    │
    └── ARCHITECTURE.md (this file)
        └── Architecture diagrams and data flow
```

## Toolbar Item Mapping

| Identifier | Label | Icon | View Controller |
|------------|-------|------|----------------|
| backup | Backup | 🗄️ externaldrive | XLBackupPreferencesViewController |
| view | View | 👁️ eye | XLViewPreferencesViewController |
| effectsGrid | Effects Grid | 📊 square.grid.3x3 | XLEffectsGridPreferencesViewController |
| sequences | Sequences | 📝 list.bullet | XLSequenceFilePreferencesViewController |
| output | Output | 💡 lightbulb | XLOutputPreferencesViewController |
| checkSequence | Check Sequence | ✅ checkmark.circle | XLCheckSequencePreferencesViewController |
| randomEffects | Random Effects | 🎲 die.face.5 | XLRandomEffectsPreferencesViewController |
| colorManager | Colors | 🎨 paintpalette | XLColorManagerPreferencesViewController |
| other | Other | ⚙️ gearshape | XLOtherPreferencesViewController |
| services | Services | ☁️ cloud | XLServicesPreferencesViewController |

## NSUserDefaults Keys

### Sequence File Settings
- RenderOnSave (BOOL)
- LowDefinitionRender (BOOL)
- SaveFSEQOnSave (BOOL)
- ModelBlendDefault (NSInteger)
- RenderCache (NSInteger)
- AutoSaveInterval (NSInteger)
- FSEQVersion (NSInteger)
- RenderCacheUseShowFolder (BOOL)
- FSEQUseShowFolder (BOOL)
- RenderCachePath (NSString)
- FSEQPath (NSString)
- MaxRenderCacheSize (NSInteger)
- DefaultView (NSInteger)

### Effects Grid Settings
- GridSpacing (NSInteger)
- EffectBackgrounds (BOOL)
- NodeValues (BOOL)
- GroupEffectIndicator (BOOL)
- SnapToTiming (BOOL)
- DoubleClickMode (NSInteger)
- SmallWaveform (BOOL)
- TransitionMarks (BOOL)
- HideColorUpdateWarning (BOOL)
- AlternateTimingFormat (BOOL)
- BellOnRender (BOOL)

### Output Settings
- UseFrameSync (BOOL)
- ForceLocalIP (NSString)
- DuplicateFramesToSuppress (NSInteger)
- xFadePort (NSInteger)

### View Settings
- EffectIconSize (NSInteger)
- ModelHandleSize (NSInteger)
- EffectAssistMode (NSInteger)
- ShowPlayControls (BOOL)
- AutoShowHousePreview (BOOL)
- DisableKeyAcceleration (BOOL)
- EnableBaseShowFolder (BOOL)
- TimelineZooming (NSInteger)
- HidePresetPreviews (BOOL)
- ZoomToCursor (BOOL)
- CrosshairSize (NSInteger)

### Color Manager Settings
- SuppressDarkMode (BOOL)
- TimingTrackColors (NSDictionary)
- EffectGridColors (NSDictionary)
- LayoutTabColors (NSDictionary)

### Check Sequence Settings
- DisableDuplicateUniverseCheck (BOOL)
- DisableNonContiguousChannelCheck (BOOL)
- DisablePreviewGroupCheck (BOOL)
- DisableDuplicateNodeCheck (BOOL)
- DisableTransitionTimeCheck (BOOL)
- DisableCustomSizeCheck (BOOL)
- DisableSketchImageCheck (BOOL)

### Backup Settings
- BackupInterval (NSInteger)
- BackupLocation (NSString)
- BackupPurge (BOOL)
- BackupCount (NSInteger)

### Random Effects Settings
- RandomEffectDensity (NSInteger)
- RandomEffectTypes (NSArray)

### Other Settings
- HardwareVideoDecoding (BOOL)
- VideoRenderMethod (NSInteger)
- ShadersOnBackgroundThreads (BOOL)
- VideoCodec (NSInteger)
- VideoBitrate (double)
- ExcludePresets (BOOL)
- ExcludeAudio (BOOL)
- BatchRenderPromptIssues (BOOL)
- PurgeDownloadCache (BOOL)
- IgnoreVendorRecommendations (BOOL)
- MinimumTipLevel (NSInteger)
- MultiThreading (NSInteger)
- LinkAdvancedSettings (BOOL)
- AliasPrompt (NSInteger)
- ControllerPingInterval (NSInteger)

### Services Settings (if ENABLE_SERVICES)
- EnableServices (BOOL)
- OpenAIKey (NSString)
- OllamaURL (NSString)
- UseAppleIntelligence (BOOL)

## Thread Safety

All settings operations happen on the main thread:
- viewDidLoad called on main thread
- viewWillDisappear called on main thread
- All UI actions (checkbox clicks, popup changes) on main thread
- NSUserDefaults operations on main thread

No explicit locking needed — AppKit guarantees main thread execution for view lifecycle methods.

## Memory Management

- **XLPreferencesWindowController**: Singleton, lives for app lifetime
- **View Controllers**: Created once, cached in dictionary, live for window lifetime
- **Views**: Loaded lazily on first pane display, cached thereafter
- **No manual retain/release**: ARC handles all memory management

## Future Integration Points

### Engine API Wiring
When integrating with engine APIs, settings will be read from NSUserDefaults and applied to:
- SequenceEngine (render on save, auto-save interval)
- ModelEngine (model blend default)
- OutputEngine (frame sync, force local IP)
- RenderEngine (render cache, GPU settings)
- EffectEngine (grid spacing, effect backgrounds)

### Bidirectional Sync
Changes from the engine side will need to update NSUserDefaults and refresh the UI if the preferences window is open.

### Validation
Settings validation will be added:
- Path existence checks for directory paths
- IP address format validation
- Range validation for numeric inputs
