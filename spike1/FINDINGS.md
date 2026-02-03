# Spike 1 Findings: Engine Coupling Analysis

## Executive Summary

The xLights rendering engine CAN be driven programmatically without GUI
windows. However, it CANNOT be fully separated from wxWidgets at this
time -- the wx dependency is structural, not just at the UI boundary.

The good news: an `xlEngine` namespace with pure-C++ API wrappers already
exists in `xLights/engine/`. These provide the wx-free interface layer
that the native macOS UI would talk to. The Phase 0 work is already
substantially underway.

## Discovery: Existing xlEngine API Layer

The following engine abstraction classes already exist in `xLights/engine/`:

| File | Class | Status |
|------|-------|--------|
| `SequenceEngine.h/cpp` | `xlEngine::SequenceEngine` | Implemented |
| `ModelEngine.h/cpp` | `xlEngine::ModelEngine` | Implemented |
| `RenderEngine.h` | `xlEngine::RenderEngine` | Header only, impl TBD |
| `EffectEngine.h` | `xlEngine::EffectEngine` | Header only, impl TBD |
| `OutputEngine.h/cpp` | `xlEngine::OutputEngine` | Implemented |

These wrap `xLightsFrame` and expose pure C++ interfaces using
`std::string`, `std::vector`, and plain structs. No wxWidgets types
cross the API boundary. This is exactly the pattern described in
IMPLEMENTATION_GUIDE.md.

## wxWidgets Coupling Map

Every core engine class has wx dependencies. Here is the complete map:

### Critical Coupling Points (must be addressed for Phase 0)

1. **xLightsFrame** (`xLightsMain.h`)
   - Inherits from `wxFrame`
   - Acts as the engine hub: owns ModelManager, EffectManager,
     OutputManager, SequenceElements, SequenceData
   - ~1,985 lines in header alone
   - Phase 0 strategy: The xlEngine wrappers delegate to this class
     during the transition. Eventually, the engine state moves into
     standalone classes that xLightsFrame simply wraps.

2. **xLightsXmlFile** (`xLightsXmlFile.h`)
   - Inherits from `wxFileName`
   - Uses `wxXmlDocument` for sequence parsing
   - Takes `xLightsFrame*` for many operations
   - Phase 0 strategy: Wrap with `SequenceEngine::loadSequence()` which
     takes `std::string` path and returns `SequenceInfo` struct.

3. **SequenceElements** (`sequencer/SequenceElements.h`)
   - Constructor takes `xLightsFrame*`
   - Uses `wxXmlNode*` for element loading
   - References `TimeLine*` (a wx widget)
   - Phase 0 strategy: Already wrapped by `SequenceEngine`. New UI
     accesses elements through the engine API.

4. **RenderBuffer** (`RenderBuffer.h`)
   - Constructor takes `xLightsFrame*`, `PixelBufferClass*`, `const Model*`
   - Uses `wxImage`, `wxMemoryDC`, `wxGraphicsContext` for drawing contexts
   - `GetMedia()` accesses `xLightsFrame::CurrentSeqXmlFile` (static)
   - Phase 0 strategy: The `frame` pointer is used primarily for model
     lookup and media access. These can be passed as constructor
     parameters or through a lightweight context object.

5. **PixelBufferClass** (`PixelBuffer.h`)
   - Constructor takes `xLightsFrame*`
   - Stores `frame` pointer for model lookup
   - Phase 0 strategy: Wrapped by `RenderEngine`. The frame dependency
     can be replaced with a model-provider interface.

6. **Model** (`models/Model.h`)
   - Uses `wxXmlNode*` for persistence
   - Uses `wxPropertyGridInterface` for UI
   - Uses `wxArrayString`, `wxString` throughout
   - Phase 0 strategy: Wrapped by `ModelEngine`. Properties accessed
     through string-based API.

7. **Color.h**
   - Includes `<wx/colour.h>`
   - `xlColor` has constructors taking `wxColor`
   - Has operator `wxString()` and `wxColor()` conversions
   - Phase 0 strategy: The core `xlColor` struct is almost wx-free.
     The wx conversions are convenience methods that could be moved to
     a bridge file.

### Medium Coupling Points

8. **SettingsMap / UtilClasses.h**
   - `SettingsMap` inherits from `MapStringString` (pure C++)
   - BUT `UtilClasses.h` includes `<wx/filepicker.h>` for
     `ImageFilePickerCtrl` (a UI class in a utility header)
   - Phase 0 strategy: Move `ImageFilePickerCtrl` to a UI-specific file.

9. **Effect** (`sequencer/Effect.h`)
   - Includes `"wx/wx.h"` via EffectLayer.h
   - Uses `wxLongLong` for timestamps
   - `SettingsMap` is pure C++ but parsed from wx XML
   - Phase 0 strategy: Effect settings are already string-based
     (`SettingsMap`). The xlEngine::EffectEngine wraps this cleanly.

10. **EffectManager** (`effects/EffectManager.h`)
    - Relatively clean -- just stores `RenderableEffect*` vector
    - But `RenderableEffect` includes wx headers for panel management
    - Phase 0 strategy: Effect rendering (the `Render()` method) has
      minimal wx dependency. Panel creation is a separate concern.

### Low Coupling Points (UI-only, not blocking Phase 0)

11. **DrawingContext classes** (in `RenderBuffer.h`)
    - `PathDrawingContext`, `TextDrawingContext` use wx graphics
    - Only used by a few effects (Text, Shape)
    - Phase 0 strategy: These are render-time utilities that could
      be replaced with CoreGraphics on macOS, but this is optional
      and doesn't block the API extraction.

12. **AudioManager** - uses FFmpeg, has some wx types for events
13. **OutputManager** - wrapped by `xlEngine::OutputEngine`
14. **Various dialogs and panels** - pure UI, not part of engine

## What "Render-Only Mode" Gives Us

`xLightsFrame(nullptr, 0, -1, true)` creates the frame in render-only
mode. In this mode:

- No visible window is created
- ModelManager, EffectManager, OutputManager are initialized
- SequenceElements container is created
- `SetDir()` loads models from xlights_rgbeffects.xml
- `OpenSequence()` loads sequence data
- The rendering pipeline works: PixelBuffer, RenderBuffer, effects

This is already the mode used by the command-line batch render feature
(`-r` flag). The spike validates that this same path works for
programmatic driving.

## Architecture Diagram: Current vs Target

### Current (wx-coupled)
```
xLightsFrame (wxFrame)
  |-- AllModels (ModelManager)
  |     |-- Model* (uses wxXmlNode)
  |-- effectManager (EffectManager)
  |     |-- RenderableEffect* (uses wxPanel)
  |-- _sequenceElements (SequenceElements)
  |     |-- Element*/Effect* (uses wx events)
  |-- _seqData (SequenceData)
  |-- CurrentSeqXmlFile (xLightsXmlFile : wxFileName)
  |-- outputManager (OutputManager)
```

### Target (via xlEngine wrappers)
```
AppKit UI (native macOS)
  |
  v
xlEngine::SequenceEngine  --> wraps xLightsFrame sequence ops
xlEngine::ModelEngine      --> wraps ModelManager
xlEngine::RenderEngine     --> wraps PixelBuffer/RenderBuffer
xlEngine::EffectEngine     --> wraps EffectManager + effects
xlEngine::OutputEngine     --> wraps OutputManager
  |
  v
xLightsFrame (unchanged during transition)
```

## Recommendations for Phase 0

1. **Complete RenderEngine implementation** (`engine/RenderEngine.cpp`).
   The header is defined; the implementation needs to wrap the
   PixelBuffer/RenderBuffer pipeline behind the `FrameBuffer` struct.

2. **Complete EffectEngine implementation** (`engine/EffectEngine.cpp`).
   The header is defined; the implementation needs to wrap
   EffectManager and provide effect CRUD through string-based APIs.

3. **Add an engine context object** that replaces the `xLightsFrame*`
   parameter throughout the rendering pipeline. This context would
   provide: model lookup, media access, effect lookup, sequence data.
   During transition, it delegates to xLightsFrame.

4. **Move UI types out of engine headers**. Specifically:
   - `ImageFilePickerCtrl` out of `UtilClasses.h`
   - `wxPropertyGrid` includes out of `Model.h`
   - Drawing context wx types could stay (they're render utilities)

5. **Test with real sequences**. This spike program should be run
   against real show directories to validate the full pipeline.

## Conclusion

The engine decoupling IS feasible. The existing `xlEngine` namespace
provides the correct architecture. The remaining work is:
- Completing the RenderEngine and EffectEngine implementations
- Gradually reducing wx coupling in the engine core (optional, can
  be done incrementally)
- Building the AppKit UI against the xlEngine APIs
