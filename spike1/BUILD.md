# Building Spike 1

## Prerequisites

- macOS 14+ with Xcode 15+ command-line tools
- wxWidgets 3.3+ (same version used by the main xLights project)
- The xLights source tree (this spike lives within it)

## Why wxWidgets is Required

The spike program cannot be built without wxWidgets. Every core engine class
(xLightsFrame, Model, RenderBuffer, PixelBuffer, SequenceElements, etc.)
includes wx headers. The `xlEngine::` API layer presents a wx-free *interface*
but the implementation still links against wx.

This is a key finding of the spike: true wx-free operation will require
completing the engine decoupling described in IMPLEMENTATION_GUIDE.md.

## Build Approach

This spike is designed to be compiled as part of the existing xLights Xcode
project, or as a standalone target that links against the same xLights object
files and libraries.

### Option A: Add as Xcode Target

1. Open `macOS/xLights.xcodeproj` in Xcode
2. Add a new "Command Line Tool" target named `spike1_engine_test`
3. Add `spike1/spike1_engine_test.cpp` to the target
4. Add all xLights source files that the main xLights target uses
   (or link against the same compiled objects)
5. Set the same include paths, preprocessor definitions, and linked
   frameworks/libraries as the main xLights target
6. Build and run

### Option B: Manual Compilation (conceptual)

```bash
# This is a rough guide -- exact flags depend on your wx-config output
WX_FLAGS=$(wx-config --cxxflags)
WX_LIBS=$(wx-config --libs std,xml,media,gl,aui,propgrid)

clang++ -std=gnu++20 \
    $WX_FLAGS \
    -I../xLights \
    -I../include \
    -I../dependencies \
    spike1_engine_test.cpp \
    ../xLights/*.cpp \
    ../xLights/engine/*.cpp \
    ../xLights/models/*.cpp \
    ../xLights/effects/*.cpp \
    ../xLights/sequencer/*.cpp \
    ../xLights/outputs/*.cpp \
    $WX_LIBS \
    -framework OpenGL \
    -framework Metal \
    -framework CoreGraphics \
    -framework AVFoundation \
    -lcurl -lz -lzstd \
    -o spike1_engine_test
```

In practice, Option A is strongly recommended because the xLights build has
many interdependencies and compiler flags that are managed by the Xcode project.

## Running

```bash
# List models only (no sequence)
./spike1_engine_test /path/to/show/directory

# Full test with sequence rendering
./spike1_engine_test /path/to/show/directory /path/to/sequence.xsq
```

The show directory must contain `xlights_rgbeffects.xml`. The sequence file
should be a `.xsq` or `.xml` sequence from the same show.

## Expected Output

```
================================================================
  Spike 1: xLights Engine API Vertical Slice
================================================================

Show directory: /path/to/show
Sequence file:  /path/to/sequence.xsq

--- Step 1: Verify show directory ---
  Found xlights_rgbeffects.xml
  Found xlights_networks.xml

--- Step 2: Initialize xLights engine ---
  xLightsFrame created (render-only mode)
  EffectManager: 55 effects registered

--- Step 3: Load show directory ---
  Show directory loaded: /path/to/show

--- Step 4: Test xlEngine::ModelEngine API ---
  Total models (via ModelEngine API): 42
  Non-group models: 35
  Model groups: 7
  ...

--- Step 5: Test xlEngine::SequenceEngine API ---
  Sequence: MySequence.xsq
  Duration: 180000 ms
  ...

--- Step 6: Test xlEngine::EffectEngine API ---
  Available effect types: 55
  ...

--- Step 7: Direct render pipeline test ---
  Rendering model: SomeModel at time 1000 ms
  ...
  Pixel(0,0): R=255 G=  0 B=  0
  ...

================================================================
  Spike 1 Complete
================================================================

VALIDATED:
  [1] xLights engine initializes without GUI (render-only mode)
  [2] Show directory loads programmatically (models, networks)
  [3] xlEngine::ModelEngine enumerates models without wx types
  [4] xlEngine::SequenceEngine loads sequences programmatically
  [5] xlEngine::EffectEngine enumerates effects without wx types
  [6] Render pipeline can be invoked and pixel data read back

CONCLUSION: The engine decoupling approach IS feasible.
```
