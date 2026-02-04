# Native macOS Decoupling Guide

## Purpose

This document provides context for agents working on decoupling the native macOS UI from the wxWidgets legacy codebase. The goal is to create a fully native macOS application that doesn't rely on wxWidgets at runtime.

**Related Documents:**
- `IMPLEMENTATION_GUIDE.md` - Overall native macOS rebuild architecture
- `CLAUDE.md` - Codebase architecture and contribution guidelines

---

## Goal

Create a fully native macOS xLights application that:
- Does **not** depend on wxWidgets at runtime
- Provides the same functionality as the legacy app
- Delivers better macOS-native experiences (Shortcuts, Continuity, iCloud, etc.)
- Achieves better performance by removing cross-platform abstraction layers

---

## Current Architecture (Before Decoupling)

```
main() → wxEntry() → xLightsApp::OnInit() → xLightsFrame (wxWidgets)
                                                    │
                                                    ├── ModelManager (owned)
                                                    ├── OutputManager (owned)
                                                    ├── SequenceElements (owned)
                                                    ├── EffectManager (owned)
                                                    └── ... (hundreds of other members)
                                                    │
                                          XLTryLaunchNativeWindow()
                                                    │
                                          XLEngineBridge.mm
                                                    │
                                    calls xLightsApp::GetFrame() ──► TIGHT COUPLING
                                                    │
                                          Native AppKit/SwiftUI UI
```

**Problem**: The native UI cannot run without wxWidgets because:
1. `XLEngineBridge` calls `xLightsApp::GetFrame()` to get the frame pointer
2. All engines (`SequenceEngine`, `ModelEngine`, etc.) take `xLightsFrame*` in constructors
3. Managers are owned by and embedded in `xLightsFrame`
4. `main()` calls `wxEntry()` which starts the wxWidgets event loop

---

## Target Architecture (After Decoupling)

```
main_native()
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│                 Native Initialization                        │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Standalone Manager Instances                        │    │
│  │  ┌─────────────┐ ┌─────────────┐ ┌───────────────┐  │    │
│  │  │ModelManager │ │OutputManager│ │SequenceState  │  │    │
│  │  │ (standalone)│ │ (standalone)│ │  (standalone) │  │    │
│  │  └──────┬──────┘ └──────┬──────┘ └───────┬───────┘  │    │
│  │         │               │                │          │    │
│  │         ▼               ▼                ▼          │    │
│  │  ┌─────────────────────────────────────────────┐   │    │
│  │  │         Abstract Interfaces                  │   │    │
│  │  │  IModelProvider, IOutputProvider,            │   │    │
│  │  │  ISequenceProvider, IRenderProvider          │   │    │
│  │  └─────────────────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    xlEngine Layer                            │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌──────────┐  │
│  │ Sequence   │ │  Model     │ │  Output    │ │  Render  │  │
│  │  Engine    │ │  Engine    │ │  Engine    │ │  Engine  │  │
│  │            │ │            │ │            │ │          │  │
│  │ Uses:      │ │ Uses:      │ │ Uses:      │ │ Uses:    │  │
│  │ ISequence  │ │ IModel     │ │ IOutput    │ │ IRender  │  │
│  │ Provider   │ │ Provider   │ │ Provider   │ │ Provider │  │
│  └────────────┘ └────────────┘ └────────────┘ └──────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   XLEngineBridge.mm                          │
│         (No longer calls xLightsApp::GetFrame())            │
│         (Owns manager instances directly)                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                Native AppKit/SwiftUI UI                      │
│              (Runs without wxWidgets)                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Decoupling Strategy

### Phase 1: Create Abstract Interfaces

Create pure C++ interfaces that define what each engine needs, without any wxWidgets types:

```cpp
// xLights/engine/interfaces/IModelProvider.h
namespace xlEngine {
    class IModelProvider {
    public:
        virtual ~IModelProvider() = default;

        virtual size_t getModelCount() const = 0;
        virtual std::string getModelName(size_t index) const = 0;
        virtual Model* getModel(const std::string& name) = 0;
        virtual std::vector<std::string> getModelNames() const = 0;
        // ... other methods engines actually need
    };
}
```

**Key principle**: Interfaces use only standard C++ types (`std::string`, `std::vector`, etc.) - never wx types.

### Phase 2: Extract Managers from xLightsFrame

Currently, managers are created and owned by `xLightsFrame`:

```cpp
// Current (in xLightsMain.h)
class xLightsFrame : public wxFrame {
    ModelManager AllModels;  // Embedded member
    OutputManager* _outputManager;  // Owned pointer
    // ...
};
```

Extract them to be standalone:

```cpp
// New (standalone creation)
auto modelManager = std::make_unique<ModelManager>();
auto outputManager = std::make_unique<OutputManager>();
// Pass to engines via interfaces
```

### Phase 3: Update Engines to Use Interfaces

Change engine constructors from:

```cpp
// Current
SequenceEngine::SequenceEngine(xLightsFrame* frame) : _frame(frame) {}
```

To:

```cpp
// New
SequenceEngine::SequenceEngine(ISequenceProvider* provider) : _provider(provider) {}
```

### Phase 4: Update XLEngineBridge

Change from:

```cpp
// Current
xLightsFrame* frame = xLightsApp::GetFrame();
_sequenceEngine = std::make_unique<xlEngine::SequenceEngine>(frame);
```

To:

```cpp
// New
_modelManager = std::make_unique<ModelManager>();
_modelProvider = std::make_unique<ModelProviderImpl>(_modelManager.get());
_modelEngine = std::make_unique<xlEngine::ModelEngine>(_modelProvider.get());
```

### Phase 5: Create Native Entry Point

Create `main_native.mm` that:
1. Initializes managers directly (no wxWidgets)
2. Sets up the native AppKit application
3. Creates and shows the native window
4. Runs the native event loop

### Phase 6: Create Native-Only Xcode Target

New Xcode target that:
- Excludes wxWidgets source files
- Excludes `xLightsApp.cpp`, `xLightsMain.cpp`
- Includes native-mac sources
- Links against native frameworks only (no wx libraries)

---

## Key Files to Modify

| File | Change Required |
|------|-----------------|
| `xLights/engine/SequenceEngine.h/cpp` | Use `ISequenceProvider*` instead of `xLightsFrame*` |
| `xLights/engine/ModelEngine.h/cpp` | Use `IModelProvider*` instead of `ModelManager&` |
| `xLights/engine/OutputEngine.h/cpp` | Use `IOutputProvider*` instead of `OutputManager*` |
| `xLights/engine/EffectEngine.h/cpp` | Use `IEffectProvider*` instead of `xLightsFrame*` |
| `xLights/engine/RenderEngine.h/cpp` | Use `IRenderProvider*` instead of `xLightsFrame*` |
| `xLights/native-mac/XLEngineBridge.mm` | Own managers directly, remove `GetFrame()` call |
| `macOS/xLights.xcodeproj` | Add native-only target |

## New Files to Create

| File | Purpose |
|------|---------|
| `xLights/engine/interfaces/IModelProvider.h` | Model access interface |
| `xLights/engine/interfaces/IOutputProvider.h` | Output access interface |
| `xLights/engine/interfaces/ISequenceProvider.h` | Sequence access interface |
| `xLights/engine/interfaces/IEffectProvider.h` | Effect access interface |
| `xLights/engine/interfaces/IRenderProvider.h` | Render access interface |
| `xLights/native-mac/providers/NativeModelProvider.h/mm` | Native implementation |
| `xLights/native-mac/providers/NativeOutputProvider.h/mm` | Native implementation |
| `xLights/native-mac/providers/NativeSequenceProvider.h/mm` | Native implementation |
| `xLights/native-mac/main_native.mm` | Native entry point |

---

## Dependencies Between Work Items

```
┌─────────────────────────────────────────────────────────────┐
│  1. Create Abstract Interfaces                               │
│     (IModelProvider, IOutputProvider, ISequenceProvider,     │
│      IEffectProvider, IRenderProvider)                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  2. Update Engines to Use Interfaces (can be parallel)       │
│     ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│     │Sequence  │ │ Model    │ │ Output   │ │ Effect   │     │
│     │Engine    │ │ Engine   │ │ Engine   │ │ Engine   │     │
│     └──────────┘ └──────────┘ └──────────┘ └──────────┘     │
│                       ┌──────────┐                           │
│                       │ Render   │                           │
│                       │ Engine   │                           │
│                       └──────────┘                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Create Native Provider Implementations (can be parallel) │
│     ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│     │Native    │ │Native    │ │Native    │ │Native    │     │
│     │Model     │ │Output    │ │Sequence  │ │Effect    │     │
│     │Provider  │ │Provider  │ │Provider  │ │Provider  │     │
│     └──────────┘ └──────────┘ └──────────┘ └──────────┘     │
│                       ┌──────────┐                           │
│                       │Native    │                           │
│                       │Render    │                           │
│                       │Provider  │                           │
│                       └──────────┘                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  4. Update XLEngineBridge (blocked on 2 & 3)                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  5. Create Native Entry Point & Xcode Target (blocked on 4)  │
└─────────────────────────────────────────────────────────────┘
```

---

## Testing Strategy

1. **Unit Tests**: Each interface implementation should have unit tests
2. **Integration Tests**: Test engines with native providers
3. **Comparison Tests**: Compare native app behavior with legacy app
4. **Regression Tests**: Ensure legacy app still works (both UIs buildable during transition)

---

## Important Constraints

1. **Don't Break Legacy**: The wxWidgets UI must continue to work during transition
2. **No wx Types in Interfaces**: Interfaces use only `std::` types
3. **Thread Safety**: Native UI runs on main thread, rendering on background threads
4. **Memory Management**: Use RAII, smart pointers, ARC (Objective-C)

---

## Reference: What Each Engine Currently Needs from xLightsFrame

### SequenceEngine
- Sequence file path
- Playback state (play/pause/stop)
- Current position
- Audio manager
- Sequence duration

### ModelEngine
- `AllModels` (ModelManager)
- Model list iteration
- Model property access
- Submodel/group hierarchy

### OutputEngine
- `GetOutputManager()`
- Controller list
- Port configurations
- Network settings

### EffectEngine
- `_sequenceElements`
- Effect definitions
- Effect layer management
- Timeline data

### RenderEngine
- Pixel buffers
- GPU context (Metal)
- Frame rendering coordination
- Layer blending

---

## Success Criteria

The decoupling is complete when:

1. ✅ Native app launches without wxWidgets initialization
2. ✅ Can load and display a sequence
3. ✅ Can play back with audio sync
4. ✅ Can edit effects on timeline
5. ✅ Can output to controllers
6. ✅ Legacy wxWidgets app still builds and works
7. ✅ No wx types in engine layer
