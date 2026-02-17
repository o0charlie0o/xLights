# Native macOS Keyboard Shortcut Implementation Status

Research conducted 2026-02-06. Covers all ~160 binding types defined in `xLights/xlCore/KeyBindings.cpp`.

---

## Architecture

### Event Flow
```
NSEvent (keyDown:)
    → [XLSequencerViewController keyDown:]
    → [XLKeyboardHandler handleKeyEvent:inScope:]
    → xlCore::KeyBindingMap::find()  (C++ lookup by key + modifiers + scope)
    → [delegate performKeyAction:effectName:effectSettings:inScope:]
    → if-else dispatch on actionType string
    → returns YES (handled) or NO (falls through to super)
```

### Key Files
| File | Purpose |
|------|---------|
| `xLights/xlCore/KeyBindings.h/cpp` | Cross-platform binding types, defaults, XML load/save |
| `native-mac/input/XLKeyboardHandler.h/mm` | NSEvent → xlCore bridge, modifier mapping |
| `native-mac/XLSequencerViewController.m:5126-5263` | `performKeyAction:` dispatch (only handler) |
| `native-mac/XLAppDelegate.m` | Menu bar IBActions for file operations |
| `native-mac/preferences/XLKeyboardPreferencesViewController.m` | UI declarations for all bindings |

### Key Design Points
- macOS **Cmd** = xLights "control" (primary modifier); macOS **Control** = xLights "rawControl"
- Only `XLSequencerViewController` implements `performKeyAction:` — no layout VC has one
- Layout-scoped shortcuts are entirely dead (no keyboard handler in layout tab)
- The layout VC *does* have underlying functionality (align, distribute, flip, lock) via preview delegates — just no keyboard wiring

---

## Implemented via Keyboard Handler (14 actions)

These are handled in `XLSequencerViewController.m` `performKeyAction:` (lines 5126-5263):

| Action | Key | Handler | Line |
|--------|-----|---------|------|
| `TOGGLE_PLAY` | Space | `[_playbackController togglePlayPause]` | 5135 |
| `PLAY` | (unbound) | `[_playbackController play]` | 5168 |
| `PAUSE` | Pause | `[_playbackController pause]` | 5172 |
| `STOP` | (unbound) | `[_playbackController stop]` | 5176 |
| `START_OF_SONG` | Home | `[self seekToStart:]` | 5158 |
| `END_OF_SONG` | End | `[self seekToEnd:]` | 5162 |
| `STEP_FORWARD` | (unbound) | `[_playbackController stepForward]` | 5182 |
| `STEP_BACKWARD` | (unbound) | `[_playbackController stepBackward]` | 5186 |
| `ZOOM_IN` | + | `[self zoomIn:]` | 5148 |
| `ZOOM_OUT` | - | `[self zoomOut:]` | 5152 |
| `UNDO` | (unbound) | `[_undoController undo]` | 5192 |
| `REDO` | (unbound) | `[_undoController redo]` | 5196 |
| `EFFECT_SETTINGS_TOGGLE` | Cmd+F1 | `[[XLSwiftUIWindowHelper shared] toggleInspector]` | 5141 |
| `EFFECT` | various (o,u,d,m,c,i,b,y,f,g,p,r,x,S,w,n,O,F) | Creates effect via engine bridge | 5202 |

---

## Implemented via Menu Bar Only (not keyboard handler)

These work through IBActions wired to menu items in `XLAppDelegate.m` and `XLToolbarExtensions.mm`, but are NOT routed through the `performKeyAction:` keyboard dispatch:

| Action | Menu Action | Location |
|--------|-------------|----------|
| `NEW_SEQUENCE` | `newSequence:` | XLAppDelegate.m:934 |
| `OPEN_SEQUENCE` | `openSequence:` | XLAppDelegate.m:1034 |
| `CLOSE_SEQUENCE` | `performClose:` (standard) | XLToolbarExtensions.mm:198 |
| `SAVE_CURRENT_TAB` | `saveDocument:` (standard) | XLToolbarExtensions.mm:199 |
| `SAVEAS_SEQUENCE` | `saveDocumentAs:` (standard) | XLToolbarExtensions.mm:200 |
| `BACKUP` | `backupShowFolder:` | XLAppDelegate.m:300 |
| `ALTERNATE_BACKUP` | `alternateBackup:` | XLAppDelegate.m:379 |
| `SELECT_SHOW_FOLDER` | `selectShowFolder:` | XLAppDelegate.m:296 |
| `FPP_CONNECT` | `fppConnect:` | XLAppDelegate.m:689 |
| `RENDER_ALL` | Menu action | XLMainWindowController.mm:476 |
| Audio speed (menu) | `setPlaybackSpeed:` | XLAppDelegate.m:515 |

---

## NOT Implemented (~140+ actions)

### Timing & Phonemes (19 actions, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `TIMING_ADD` | t | Add timing mark at cursor |
| `TIMING_SPLIT` | s | Split timing mark at cursor |
| `TIMING_DIVIDE_2` | (unbound) | Divide selected timing mark in 2 |
| `TIMING_DIVIDE_3` | (unbound) | Divide in 3 |
| `TIMING_DIVIDE_4` | (unbound) | Divide in 4 |
| `TIMING_DIVIDE_6` | (unbound) | Divide in 6 |
| `TIMING_DIVIDE_8` | (unbound) | Divide in 8 |
| `TIMING_DIVIDE_12` | (unbound) | Divide in 12 |
| `TIMING_DIVIDE_16` | (unbound) | Divide in 16 |
| `PHONEME_ETC` | (unbound) | Set phoneme to etc |
| `PHONEME_AI` | (unbound) | Set phoneme to AI |
| `PHONEME_E` | (unbound) | Set phoneme to E |
| `PHONEME_O` | (unbound) | Set phoneme to O |
| `PHONEME_WQ` | (unbound) | Set phoneme to WQ |
| `PHONEME_FV` | (unbound) | Set phoneme to FV |
| `PHONEME_MBP` | (unbound) | Set phoneme to MBP |
| `PHONEME_REST` | (unbound) | Set phoneme to rest |
| `PHONEME_L` | (unbound) | Set phoneme to L |
| `AUTO_ETC_PHONEME` | (unbound) | Split phoneme, set first half to etc |

### Effect Operations (13 actions, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `DUPLICATE_RIGHT` | Shift+Alt+Right | Duplicate selected effects right |
| `DUPLICATE_LEFT` | Shift+Alt+Left | Duplicate selected effects left |
| `DUPLICATE_UP` | Shift+Alt+Up | Duplicate selected effects up |
| `DUPLICATE_DOWN` | Shift+Alt+Down | Duplicate selected effects down |
| `LOCK_EFFECT` | Cmd+L | Lock selected effects |
| `UNLOCK_EFFECT` | Cmd+U | Unlock selected effects |
| `EFFECT_ALIGN_START` | (unbound) | Align effect start times |
| `EFFECT_ALIGN_END` | (unbound) | Align effect end times |
| `EFFECT_ALIGN_BOTH` | (unbound) | Align both start and end |
| `EFFECT_DESCRIPTION` | (unbound) | Open effect description dialog |
| `EFFECT_UPDATE` | F5 | Apply current settings to selected effects |
| `RANDOM` | Shift+R | Insert random effects |
| `EFFECTS_TO_TIMING` | (unbound) | Convert selected effects to timing marks |

### Selection (14 actions, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `SELECT_ALL` | Cmd+A | Select all effects and timing marks |
| `SELECT_ALL_NO_TIMING` | Cmd+A (no alt) | Select all effects only |
| `TOGGLE_ELEMENT_EXPAND` | Cmd+Shift+X | Expand/collapse current element |
| `SELECT_TIMING_1` | (unbound) | Select first timing track |
| `SELECT_TIMING_2` | (unbound) | Select second timing track |
| `SELECT_TIMING_3` | (unbound) | Select third timing track |
| `SELECT_TIMING_4` | (unbound) | Select fourth timing track |
| `SELECT_TIMING_5` | (unbound) | Select fifth timing track |
| `SELECT_TIMING_6` | (unbound) | Select sixth timing track |
| `SELECT_TIMING_7` | (unbound) | Select seventh timing track |
| `SELECT_TIMING_8` | (unbound) | Select eighth timing track |
| `SELECT_TIMING_9` | (unbound) | Select ninth timing track |
| `SELECT_NO_TIMING` | (unbound) | Deselect all timing tracks |

### Model/Effect Toggle (7 actions, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `MODEL_TOGGLE` | (unbound) | Toggle render enable for model |
| `MODEL_DISABLE` | (unbound) | Disable model rendering |
| `MODEL_ENABLE` | (unbound) | Enable model rendering |
| `EFFECT_TOGGLE` | (unbound) | Toggle render enable for effects |
| `EFFECT_DISABLE` | (unbound) | Disable effect rendering |
| `EFFECT_ENABLE` | (unbound) | Enable effect rendering |
| `MODEL_EFFECT_TOGGLE` | (unbound) | Toggle model or effects rendering |

### Panel Toggles (15 actions, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `EFFECT_ASSIST_TOGGLE` | Cmd+F8 | Effect assist panel |
| `COLOR_TOGGLE` | Cmd+F2 | Color panel |
| `LAYER_SETTING_TOGGLE` | Cmd+F3 | Layer settings panel |
| `LAYER_BLENDING_TOGGLE` | Cmd+F4 | Layer blending panel |
| `MODEL_PREVIEW_TOGGLE` | Cmd+F5 | Model preview panel |
| `HOUSE_PREVIEW_TOGGLE` | Cmd+F6 | House preview (partial — menu exists, no keyboard handler) |
| `EFFECTS_TOGGLE` | Cmd+F9 | Effect dropper panel |
| `DISPLAY_ELEMENTS_TOGGLE` | Cmd+F7 | Display elements panel |
| `JUKEBOX_TOGGLE` | Cmd+Alt+F8 | Jukebox panel |
| `SEARCH_TOGGLE` | Cmd+F11 | Effect search panel |
| `PERSPECTIVES_TOGGLE` | Cmd+F12 | Perspectives panel |
| `PRESETS_TOGGLE` | Cmd+F10 | Presets panel |
| `VALUECURVES_TOGGLE` | Alt+F12 | Value curves dropper |
| `COLOR_DROPPER_TOGGLE` | Alt+F11 | Color dropper panel |
| `FOCUS_SEQUENCER` | F12 | Force focus to effects grid |

### Preset/Apply Operations (4 actions, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `SHOW_PRESETS` | (unbound) | Show presets panel |
| `APPLY_SELECTED_PRESET` | (unbound) | Apply currently selected preset |
| `PRESET` | (various) | Insert preset by name |
| `APPLYSETTING` | (various) | Apply settings to selected effects |

### Color Operations (9 actions, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `SET_COLOR_1` | Cmd+1 | Set to white |
| `SET_COLOR_2` | Cmd+2 | Set to red |
| `SET_COLOR_3` | Cmd+3 | Set to green |
| `SET_COLOR_4` | Cmd+4 | Set to blue |
| `SET_COLOR_5` | Cmd+5 | Set to yellow |
| `SET_COLOR_6` | Cmd+6 | Set to black |
| `SET_COLOR_7` | Cmd+7 | Set to cyan |
| `SET_COLOR_8` | Cmd+8 | Set to magenta |
| `COLOR_UPDATE` | Shift+F5 | Apply current colors to selected effects |

### Layer Operations (3 actions, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `INSERT_LAYER_ABOVE` | Cmd+Shift+I | Insert layer above current |
| `INSERT_LAYER_BELOW` | Cmd+Shift+A | Insert layer below current |

### Audio & Speed (14 actions, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `PLAY_LOOP` | (unbound) | Loop selected region |
| `AUDIO_FULL_SPEED` | (unbound) | 1x playback speed |
| `AUDIO_F_1_5_SPEED` | (unbound) | 1.5x speed |
| `AUDIO_F_2_SPEED` | (unbound) | 2x speed |
| `AUDIO_F_3_SPEED` | (unbound) | 3x speed |
| `AUDIO_F_4_SPEED` | (unbound) | 4x speed |
| `AUDIO_S_3_4_SPEED` | (unbound) | 0.75x speed |
| `AUDIO_S_1_2_SPEED` | (unbound) | 0.5x speed |
| `AUDIO_S_1_4_SPEED` | (unbound) | 0.25x speed |
| `PRIOR_TAG` | (unbound) | Jump to prior audio tag |
| `NEXT_TAG` | (unbound) | Jump to next audio tag |
| `PLAY_PRIOR_TAG` | (unbound) | Play from prior tag |
| `PLAY_NEXT_TAG` | (unbound) | Play from next tag |
| `INCREASE_SPEED` | (unbound) | Increase playback speed |
| `DECREASE_SPEED` | (unbound) | Decrease playback speed |

### Navigation (2 actions, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `MARK_SPOT` | Cmd+. or Ctrl+. | Mark current position |
| `RETURN_TO_SPOT` | Cmd+/ or Ctrl+/ | Return to marked position |

### Zoom (1 action, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `ZOOM_SEL` | (unbound) | Zoom to selection |

### Render (2 actions, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `CANCEL_RENDER` | Escape | Cancel current rendering |
| `TOGGLE_RENDER` | (unbound) | Toggle background rendering |

### Clipboard (2 actions, All scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `PASTE_BY_CELL` | (unbound) | Paste mode: by cell |
| `PASTE_BY_TIME` | (unbound) | Paste mode: by time |

### Jukebox (5 actions, Sequence scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `JUKEBOX_BTN_1` | (unbound) | Jukebox button 1 |
| `JUKEBOX_BTN_2` | (unbound) | Jukebox button 2 |
| `JUKEBOX_BTN_3` | (unbound) | Jukebox button 3 |
| `JUKEBOX_BTN_4` | (unbound) | Jukebox button 4 |
| `JUKEBOX_BTN_5` | (unbound) | Jukebox button 5 |

### Global/Other (4 actions, All scope)
| Action | Default Key | Notes |
|--------|-------------|-------|
| `LIGHTS_TOGGLE` | (unbound) | Toggle output to lights |
| `SEQUENCE_SETTINGS` | (unbound) | Show sequence settings (stub exists in AppDelegate) |
| `SAVE_SEQUENCE` | (unbound) | Save via keyboard handler (menu works) |

### Layout/Model Operations (28 actions, Layout scope — ENTIRE SCOPE UNIMPLEMENTED)

No `performKeyAction:` handler exists in the layout tab. The `XLLayoutViewController` has underlying functionality via preview view delegates but zero keyboard wiring.

| Action | Default Key | Notes | Underlying Function Exists? |
|--------|-------------|-------|-----------------------------|
| `LOCK_MODEL` | Cmd+L | Lock selected models | Yes — `didRequestLockModel:lock:` |
| `UNLOCK_MODEL` | Cmd+U | Unlock selected models | Yes — `didRequestLockModel:lock:` |
| `GROUP_MODELS` | Cmd+G | Group selected models | No |
| `WIRING_VIEW` | (unbound) | Show wiring view | No |
| `EXPORT_MODEL_CAD` | (unbound) | Export model as DXF/STL | No |
| `EXPORT_LAYOUT_DXF` | (unbound) | Export layout as DXF | No |
| `NODE_LAYOUT` | (unbound) | Show node layout | No |
| `SAVE_LAYOUT` | (unbound) | Save layout tab | No |
| `SELECT_ALL_MODELS` | Cmd+A | Select all models | No |
| `MODEL_ALIGN_TOP` | (unbound) | Align to top | Yes — `didRequestAlignModels:` |
| `MODEL_ALIGN_BOTTOM` | (unbound) | Align to bottom | Yes |
| `MODEL_ALIGN_LEFT` | (unbound) | Align to left | Yes |
| `MODEL_ALIGN_RIGHT` | (unbound) | Align to right | Yes |
| `MODEL_ALIGN_CENTER_VERT` | (unbound) | Align vertical center | Yes |
| `MODEL_ALIGN_CENTER_HORIZ` | (unbound) | Align horizontal center | Yes |
| `MODEL_ALIGN_BACKS` | (unbound) | Align to back | No |
| `MODEL_ALIGN_FRONTS` | (unbound) | Align to front | No |
| `MODEL_ALIGN_GROUND` | (unbound) | Align to ground | No |
| `MODEL_DISTRIBUTE_HORIZ` | (unbound) | Distribute horizontally | Yes — `didRequestDistributeModels:` |
| `MODEL_DISTRIBUTE_VERT` | (unbound) | Distribute vertically | Yes |
| `MODEL_FLIP_HORIZ` | (unbound) | Flip horizontally | Yes — `didRequestFlipModel:horizontal:` |
| `MODEL_FLIP_VERT` | (unbound) | Flip vertically | Yes |
| `MODEL_SUBMODELS` | (unbound) | Edit submodels | No |
| `MODEL_FACES` | (unbound) | Edit faces | No |
| `MODEL_STATES` | (unbound) | Edit states | No |
| `MODEL_MODELDATA` | (unbound) | Edit custom model data | No |

---

## Summary Statistics

| Category | Total | Keyboard Handler | Menu Only | Not Implemented |
|----------|-------|-------------------|-----------|-----------------|
| Playback/Transport | 8 | 6 | 0 | 2 |
| Zoom/Navigation | 5 | 2 | 0 | 3 |
| Undo/Redo | 2 | 2 | 0 | 0 |
| Effect Insertion | 1 | 1 | 0 | 0 |
| Panel Toggles | 16 | 1 | 0 | 15 |
| File Operations | 11 | 0 | 9 | 2 |
| Timing/Phonemes | 19 | 0 | 0 | 19 |
| Effect Operations | 13 | 0 | 0 | 13 |
| Selection | 14 | 0 | 0 | 14 |
| Model/Effect Toggle | 7 | 0 | 0 | 7 |
| Colors | 9 | 0 | 0 | 9 |
| Audio/Speed | 15 | 0 | 1 (menu) | 14 |
| Layout/Model | 28 | 0 | 0 | 28 |
| Preset/Apply | 4 | 0 | 0 | 4 |
| Layers | 2 | 0 | 0 | 2 |
| Render | 2 | 0 | 1 (menu) | 1 |
| Clipboard | 2 | 0 | 0 | 2 |
| Jukebox | 5 | 0 | 0 | 5 |
| Other/Global | 4 | 0 | 0 | 4 |
| **TOTAL** | **~167** | **14** | **~11** | **~142** |

**~9% of binding types are handled via keyboard dispatch. ~16% work counting menu bar actions.**
