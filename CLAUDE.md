# xLights Codebase Architecture Guide

## Overview

xLights is a comprehensive open-source lighting control and sequencing software designed for programmable LED displays and Christmas lights. It's written in C++20 with wxWidgets GUI framework and uses OpenGL/Metal for graphics rendering.

### Key Statistics
- **Main codebase**: ~167,350 lines of C++ across 189 main source files and 190 headers
- **Total repository**: Multi-application framework with 5+ companion applications
- **Build systems**: Code::Blocks (.cbp), Visual Studio (.vcxproj), Xcode, CMake
- **Dependencies**: wxWidgets 3.3+, FFmpeg, OpenGL, SDL2, Lua, Python, LiquidFun physics engine

---

## 1. Overall Architecture: Main Applications & Components

### Primary Applications

#### **xLights** (Main Application)
- **Location**: `/Users/charlie/Documents/Charlie/xLights/xLights/`
- **Purpose**: Full-featured lighting sequencer and controller management interface
- **Key responsibilities**:
  - Effect design and sequencing
  - Model management (layout, properties, types)
  - Output/controller configuration and management
  - Real-time preview and playback
  - Batch rendering
  - Audio/video integration

#### **xSchedule** (Scheduling System)
- **Location**: `/Users/charlie/Documents/Charlie/xLights/xSchedule/`
- **Purpose**: Automated playback scheduling, event management, remote control
- **Subdirectories**:
  - `PlayList/` - Playlist management
  - `events/` - Event system (54 different event types)
  - `RemoteFalcon/` - Mobile app integration
  - `xSMSDaemon/` - SMS-based control
  - `wxHTTPServer/` - Web server and REST API

#### **xCapture** (Capture & Analysis Tool)
- **Location**: `/Users/charlie/Documents/Charlie/xLights/xCapture/`
- **Purpose**: Capture live DMX/E1.31 data from networks for analysis and learning
- **Components**:
  - Universe entry dialog
  - Real-time data visualization
  - Network packet analysis

#### **xFade** (DMX Fader Controller)
- **Location**: `/Users/charlie/Documents/Charlie/xLights/xFade/`
- **Purpose**: Real-time DMX/ArtNet/E1.31 fader control
- **Features**:
  - MIDI support for integration with DJ equipment
  - Multiple protocol receivers (E1.31, ArtNet)
  - Universe management

#### **xScanner** (Network Discovery Tool)
- **Location**: `/Users/charlie/Documents/Charlie/xLights/xScanner/`
- **Purpose**: Scan networks to find and identify lighting controllers
- **Features**:
  - MAC address lookup database (MacLookup.txt)
  - Controller auto-discovery
  - Vendor identification

#### **xlDo** (Command-Line Automation)
- **Location**: `/Users/charlie/Documents/Charlie/xLights/xlDo/`
- **Purpose**: Command-line interface for automation and scripting
- **Integration**: Used by xSchedule and Lua/Python scripts

### Supporting Libraries

#### **common/** (Shared Base Classes)
- `xlBaseApp.h/cpp` - Base application class with crash handling and stack walking
- Cross-platform initialization and error handling

#### **dependencies/** (Third-Party Libraries)
- `libxlsxwriter/` - Excel file generation
- `liquidfun/` - Physics simulation library (used in advanced effects)
- `FFmpeg/` - Video/audio processing
- `lua/` - Scripting engine
- `midifile/` - MIDI file parsing
- `nanosvg/` - SVG rendering
- `pybind11/` - Python C++ bindings

---

## 2. Codebase Organization: Directory Structure

### **xLights Main Directory** (/xLights/xLights/)

#### Core Effect System
- **effects/** (242 subdirectories, ~60+ effect types)
  - **Pattern**: Each effect has three files:
    - `*Effect.h/cpp` - Core effect logic
    - `*Panel.h/cpp` - UI control panel
    - **Base class**: `RenderableEffect` (base for all effects)
  - **Example effects**: 
    - Pixel effects: Bars, Butterfly, Candle, Circles, Fire, Fireworks, etc.
    - Pattern effects: Glediator, Galaxy, Garlands, Kaleidoscope
    - Specialized: DMX, Faces, Text, Pictures, Models (3D)
  - **assist/** - Auto-effect suggestion system

#### Model System
- **models/** (88 subdirectories)
  - **Pattern**: Various model types for different hardware layouts
  - **Core classes**:
    - `Model.h/cpp` - Base model class (~300+ lines header)
    - `ModelManager.h/cpp` - Manages all models in show
    - `Node.h/cpp` - Individual pixel/node representation
  - **Specific models**:
    - `SingleLineModel.cpp` - Linear strip layouts
    - `MatrixModel.cpp` - Grid-based layouts
    - `ArchesModel.cpp` - Arch/dome layouts
    - `CustomModel.cpp` - User-defined layouts
    - `ImageModel.cpp` - Image-based mapping
    - `SphereModel.cpp`, `CubeModel.cpp` - 3D shapes
    - `DimmingCurve.cpp` - Brightness/gamma curves
  - **Screen location system**: Various screen location classes for 2D/3D positioning
    - `ModelScreenLocation.h`
    - `MultiPointScreenLocation.h`
    - `PolyPointScreenLocation.h`

#### Output/Controller System
- **outputs/** (69 subdirectories + 45+ protocol implementations)
  - **Core classes**:
    - `Output.h/cpp` - Base output class (protocol abstraction)
    - `Controller.h/cpp` - Controller management (IP/Serial hardware)
    - `OutputManager.h/cpp` - Manages all outputs globally
  - **Protocol implementations**:
    - Ethernet: E131Output, ArtNetOutput, KinetOutput, DDPOutput, OPCOutput, PixelNetOutput
    - Serial: LOROutput, DMXOutput, RenardOutput, GenericSerialOutput
    - Specialized: TwinklyOutput (cloud-based), TestPreset (testing)
  - **Controller types** (24 vendor definitions in `/controllers/`):
    - ESPixelStick, FalconPi, Kulp, Sandevices, Scott, Hanson, etc.
    - Each as XML config file (`.xcontroller`)

#### Sequencer System
- **sequencer/** (28 files, core timing & playback)
  - **Core classes**:
    - `EffectsGrid.h/cpp` - Main effect timeline grid UI (~349KB)
    - `MainSequencer.h/cpp` - Sequencer orchestration (~85KB)
    - `SequenceElements.h/cpp` - Manages all sequence data (~82KB)
    - `tabSequencer.cpp` - UI tab implementation (~166KB)
  - **Supporting**:
    - `Effect.h/cpp` - Individual effect instance
    - `EffectLayer.h/cpp` - Effect layer within element
    - `Element.h/cpp` - Model element (groups effects)
    - `TimeLine.h/cpp` - Timeline display
    - `Waveform.h/cpp` - Audio waveform visualization
    - `UndoManager.h/cpp` - Undo/redo system

#### Graphics System
- **graphics/** (14 subdirectories)
  - **Renderers**:
    - `opengl/` - OpenGL implementation (9 files)
    - `metal/` - Metal implementation for macOS (6 files)
    - `mapbox/` - Mapbox GL integration (4 files)
  - **Core**:
    - `xlGraphicsBase.h` - Abstract graphics interface
    - `xlGraphicsAccumulators.h/cpp` - Vertex/color accumulators
    - `xlGraphicsContext.h` - Graphics context abstraction
    - `xlFontInfo.h/cpp` - Font management
    - `tiny_obj_loader.h` - 3D model loading

#### Rendering Pipeline
- **Core rendering classes**:
  - `RenderBuffer.h/cpp` - Effect rendering target (buffers pixels)
  - `PixelBuffer.h/cpp` - Complete layer/channel management (~3,657 lines)
  - `RenderUtils.cpp` - Common rendering utilities
  - `GPURenderUtils.cpp` - GPU-accelerated rendering

#### Preferences & Configuration
- **preferences/** (23 files)
  - `xLightsPreferences.cpp` - Master preferences dialog
  - **Settings panels**:
    - `SequenceFileSettingsPanel.cpp` - File handling
    - `EffectsGridSettingsPanel.cpp` - Grid behavior
    - `OutputSettingsPanel.cpp` - Output configuration
    - `ViewSettingsPanel.cpp` - UI appearance
    - `OtherSettingsPanel.cpp` - Miscellaneous
    - `ColorManagerSettingsPanel.cpp` - Color management
    - `CheckSequenceSettingsPanel.cpp` - Validation options

#### AI & Automation
- **ai/** (16 files) - AI service integration
  - `chatGPT.h/cpp` - OpenAI integration
  - `ollama.h/cpp` - Local LLM support
  - `AppleIntelligence.h/cpp` + `AppleIntelligenceUtils.swift`
  - `ServiceManager.h/cpp` - AI service routing
  - `AIColorPaletteDialog.cpp` - AI-assisted color selection

- **automation/** (9 files) - Script automation
  - `xLightsAutomations.cpp` - Automation system
  - `LuaRunner.h/cpp` - Lua script execution
  - `PythonRunner.h/cpp` - Python script execution
  - `automation.h/cpp` - Base automation framework

#### Utilities
- **utils/** (10 files)
  - `Curl.h/cpp`, `CurlManager.h/cpp` - HTTP/download utilities
  - `ip_utils.h/cpp` - IP address parsing
  - `string_utils.h/cpp` - String manipulation
  - `VectorMath.h/cpp` - 3D vector mathematics
  - `EzGrid.h/cpp` - Grid UI helper

- **support/** (10 files)
  - `FastComboEditor.h/cpp` - High-performance combo box
  - `GridCellChoiceRenderer.h/cpp` - Grid cell rendering
  - `EzGrid.h/cpp` - Grid widget

#### Supporting Systems
- **MIDI/** (15 files) - MIDI input handling
  - `xlMIDIProcessor.h/cpp`
  - VAMP plugin host SDK integration

- **Box2D/** (8 files) - Physics engine (used by some effects)

- **cad/** (15 files) - CAD/3D model support

- **webp/** (7 files) - WebP image format support

### **Main xLights Files** (root of /xLights/ directory)

#### Core Application
- `xLightsApp.h/cpp` - App initialization
- `xLightsMain.h/cpp` - Main frame window (~10,700 lines!)
- `xLightsFrame` reference throughout code

#### Major Dialogs/Panels (representative selection)
- `TabSetup.cpp` - Setup/configuration tab (~3,090 lines)
- `TabSequence.cpp` - Sequence editor tab (~1,777 lines)
- `LayoutPanel.cpp` - Model layout editor (~9,331 lines)
- `CustomModelDialog.cpp` - Custom model designer (~3,555 lines)
- `ControllerModelDialog.cpp` - Controller configuration (~4,744 lines)
- `BufferPanel.cpp` - Buffer/layer management (~58KB)

#### File Formats
- `xLightsXmlFile.h/cpp` - .xlights XML sequence format (master file handler)
- `FSEQFile.cpp` - FSEQ binary format handling (~1,950 lines)
- `FileConverter.cpp` - Format conversion utilities (~1,765 lines)
- `SeqFileUtilities.cpp` - Sequence utilities (~6,047 lines)
- `Vixen3.cpp` - Vixen 3 format support

#### Color Management
- `Color.h/cpp` - Color class (HSV, RGB, HSL conversions)
- `ColorCurve.h/cpp` - Color curve editing (~19KB)
- `ColorManager.h/cpp` - Global color palette management
- `ColorPanel.cpp` - Color selection UI (~71KB)
- `DimmingCurve.h/cpp` - Brightness adjustments

#### Value Curves (Complex Parameter Animation)
- `ValueCurve.h/cpp` - Keyframe/curve animation system (~2,264 lines)
- `ValueCurvesPanel.h/cpp` - UI for value curve editing

#### Audio Integration
- `AudioManager.h/cpp` - Audio playback & analysis (~134KB, ~3,999 lines)
- Libraries: FFmpeg, libavformat, libavcodec, libswresample, GStreamer

#### Effects & Rendering Core
- `EffectManager.h/cpp` - Loads and manages all effect types
- `EffectPanelUtils.h/cpp` - UI utilities for effect panels
- `EffectsPanel.h/cpp` - Effect selection UI
- `EffectAssist.h/cpp` - Auto-effect suggestion

#### Data Structures
- `SequenceData.h/cpp` - Raw channel data storage
- `DataLayer.h/cpp` - Data layer abstractions
- `PixelTestDialog.cpp` - Testing individual pixels/channels
- `SequencePackage.h/cpp` - Sequence file packaging

#### Testing & Validation
- `CheckSequenceReport.cpp` - Validate sequences for errors (~122KB)
- Quality assurance and diagnostics

#### Discovery & Networking
- `Discovery.h/cpp` - Network device discovery
- `ZCPP.h/cpp` - ZCPP protocol implementation

#### Dialogs (Representative)
- `ConvertDialog.cpp` - Format conversion UI
- `SubModelsDialog.cpp` - Submodel management
- `ModelFaceDialog.cpp` - Face/mouth animation setup
- `ModelStateDialog.cpp` - Model state definitions

#### Utilities
- `UtilFunctions.h/cpp` - Common utility functions
- `FileDownloader.cpp` - Update/resource downloading
- `CachedFileDownloader.h/cpp` - Caching support

#### Preferences
- `xLightsXmlFile.h/cpp` - Settings file persistence

---

## 3. Technology Stack

### GUI Framework
- **wxWidgets 3.3+** - Cross-platform GUI
  - `wxAuiManager` - Dockable panels
  - `wxPropertyGrid` - Property editing
  - `wxGLCanvas` - OpenGL integration
  - `wxSocket` - Networking

### Graphics Rendering
- **OpenGL** - Primary 3D rendering
  - GLSL shaders for effects
  - Vertex/Fragment shader programs
  - Accumulator pattern for deferred rendering
- **Metal** - macOS GPU acceleration
  - Metal shaders (`*.metal`)
  - Metal compute kernels
- **SDL2** - Low-level graphics API abstraction

### Core Libraries
- **FFmpeg/libavformat** - Video file support, audio processing
- **libswresample** - Audio resampling
- **libswscale** - Video scaling/color conversion
- **GStreamer 1.0** - Media streaming

### Scripting
- **Lua 5.3** - Lightweight scripting, automation
- **Python 3.x** - Extended automation (via pybind11)

### Physics & Simulation
- **LiquidFun** - 2D physics engine (particle systems in effects)

### Serialization & Data
- **libxlsxwriter** - Excel export for sequences
- **wxXml** - XML file format parsing
- **expat** - XML parsing backend
- **nanosvg** - SVG rendering

### Networking
- **CURL** - HTTP/HTTPS requests
- **libwebp** - WebP image format
- **zstd** - Compression library
- **log4cpp** - Logging framework

### Platform-Specific
- **Windows**: Native Win32 API integration
- **Linux**: X11, PulseAudio
- **macOS**: Cocoa integration, Metal GPU rendering

### Build Tools
- **Code::Blocks** (.cbp project files) - Primary IDE
- **Visual Studio 2022** (.vcxproj) - Windows builds
- **Xcode** - macOS builds (symlinked: `xLights.xcodeproj -> macOS/xLights.xcodeproj`)
- **CMake** - Some components (xScanner, xlDo, fseq_convert)

### Code Standards
- **C++20** - Modern C++ features
  - Smart pointers (unique_ptr, shared_ptr)
  - Range-based for loops
  - Lambda functions
  - Move semantics
- **GNU C++ extensions** where needed (gnu++20)

---

## 4. Key Patterns & Architectural Decisions

### Effect Architecture

**Plugin Pattern**:
All effects inherit from `RenderableEffect` base class and implement:
```
virtual void Render(Effect* effect, const SettingsMap& settings, RenderBuffer& buffer) = 0;
```

**Effect Lifecycle**:
1. Effect created with parameters stored in `SettingsMap` (key-value pairs)
2. `EffectManager` loads and caches effect type definitions
3. During playback, for each time slice:
   - `Render()` called with settings
   - Draws to `RenderBuffer` (pixel array)
   - Settings can vary by frame using `ValueCurve`
4. Layer mixing happens in `PixelBuffer` class using `MixTypes` enum

**Effect Panel System**:
- Each effect has optional UI panel (`*Panel.h/cpp`)
- Generated by wxsmith (visual designer)
- Auto-generates from template with controls for each parameter
- Allows real-time parameter preview

**Settings Map**:
- Effects store parameters as string key-value pairs
- Allows flexible versioning and backward compatibility
- Serialized to/from XML in sequence files
- Accessed via: `settings.GetString("paramName", defaultValue)`

### Model Architecture

**Model Base Class**:
The `Model` class is foundation for all model types:
- Contains node list (pixels) with 3D coordinates
- Manages screen location (2D projection onto layout)
- Handles controller assignments and channel mapping
- Stores metadata: name, color order, dimmers, brightness curves
- Supports submodels (group of nodes within a model)

**Screen Location System**:
- `ModelScreenLocation` - 2D position and size
- `MultiPointScreenLocation` - Multi-point positioning (arches, polygons)
- `PolyPointScreenLocation` - Complex polygonal layouts
- `BoxedScreenLocation` - Simple rectangular models
- Supports 3D rotation, scaling, pivot points

**Model Types Hierarchy**:
- `SingleLineModel` - Linear strips
- `MatrixModel` - 2D grids (strings of strings)
- `MultiPointModel` - Arc/multi-point models
- `CustomModel` - User-defined node layouts
- `ImageModel` - Pixel mapping from image file
- Specialty: Sphere, Cube, Arch, Candle, Icicles, etc.

**Node Structure**:
Each model contains `Node` objects:
- 3D coordinates (x, y, z)
- Screen location (2D projection)
- Channel number on controller
- Brightness curve reference
- Can have multiple strands/submodels

### Rendering Pipeline

**Multi-Layer Effect Mixing**:
1. **Effect Rendering**: Each effect renders to temporary `RenderBuffer`
2. **Layer Stacking**: Multiple effects on same model handled by `PixelBuffer`
3. **Mix Modes**: 25+ blending modes (Normal, Additive, Mask, Shadow, etc.)
   - Defined in `PixelBufferClass::MixTypes` enum
4. **Transforms**: Rotation, scaling, zoom applied per layer
5. **Final Output**: Converted to controller data and sent to hardware

**RenderBuffer Design**:
- Per-model pixel array
- Can be GPU or CPU rendered
- Supports partial-interval rendering (some effects only render subset of time)
- Cache system for expensive effect chains
- Multiple drawing contexts: Path, OpenGL, Direct3D

**PixelBuffer (Large class, ~3,657 lines)**:
Manages complete rendering for a model:
- Maintains layer stack
- Applies color curves, dimmers, gamma correction
- Handles alpha blending between layers
- Supports GPU acceleration via metal/opengl
- Rotation, scaling transformations
- Blur and special effects

### Output/Controller Architecture

**Abstraction Layers**:
1. `Output` - Protocol handler (E131, ArtNet, DMX, etc.)
2. `Controller` - Hardware device (IP or serial address)
3. `OutputManager` - Global coordinator
4. `OutputModelManager` - Maps models to controller ports

**Controller Management**:
- Identified by unique ID and name
- Can be auto-sized (flex to model count) or fixed
- Supports auto-upload (upload to hardware when sequence modified)
- Can be temporarily disabled
- Stores vendor/model/variant info for capabilities lookup

**Output Types** (~45 implementations):
- **Ethernet**: E1.31 (DMX over Ethernet), ArtNet, Kinet, DDP, OPC
- **Serial**: DMX, LOR, Renard, Generic serial
- **Specialized**: Twinkly (cloud), Test/Null (testing)
- Each implements protocol-specific framing and timing

**Start Channel System**:
- Models assigned to controller ports
- Each port has start channel (1-indexed)
- Model channels map to output channels
- Supports non-contiguous mappings and splitting across ports

### Sequence File Format

**XLIGHTS XML Format**:
Root structure:
```xml
<xLights>
  <timing>   <!-- Timing definitions -->
  <animation>  <!-- All models and effects -->
  <element name="Model1">
    <effect ...>  <!-- Effect instances -->
  </element>
  <element name="Group1">  <!-- Can be model groups -->
    <element ref="Model1"/>
  </element>
</xLights>
```

**Serialization**:
- Written by `xLightsXmlFile::Save(SequenceElements&)`
- Read by `xLightsXmlFile::Open()`
- Supports metadata: author, song, artist, album, etc.
- Version tracking for backward compatibility

**FSEQ Binary Format**:
- Optimized for playback (less CPU intensive)
- Channels × frames format
- Minimal metadata
- Compression support (zstd)

### Event-Driven Architecture

**Threading Model**:
- `JobPool` - Thread pool for background rendering
- Background threads render effects while UI remains responsive
- `RenderCache` - Prevents redundant re-rendering
- Atomic flags for synchronization

**Update Mechanisms**:
- `wxNotifyEvent` - Custom event system
- Property grid change handlers
- Timer-based UI updates
- Undo/redo stack (UndoManager)

**Timing Control**:
- `xLightsTimer` - High-resolution timing
- Sequence framerate independent (can be 20-50ms per frame)
- Audio sync via AudioManager waveform analysis

### Data Flow

**Sequence Editing**:
```
User Input → GUI Control → Model/Effect updated → RenderCache invalidated
  → Background render job queued → Effect rendered to RenderBuffer
  → PixelBuffer applies layers → OutputManager transmits to hardware
```

**Playback**:
```
Sequence file loaded → xLightsXmlFile parsed → SequenceElements built
  → MainSequencer timeline advanced → Current time queries effects
  → Render pipeline executes → Output data sent to controllers
```

**Model Configuration**:
```
Model imported/created → ModelManager tracks → Screen location set
  → Nodes generated with 3D coords → Controller assignment → Start channel
```

---

## 5. Build System

### Project Organization

#### Code::Blocks Primary Files
- **xLights/xLights.cbp** - Main xLights build definition
- **xSchedule/xSchedule.cbp** - Scheduler application
- **xCapture/xCapture.cbp** - Capture tool
- **xFade/xFade.cbp** - Fader controller
- **xScanner/xScanner.cbp** - Network discovery

#### Build Targets
Each `.cbp` file typically has multiple build targets:
1. **Linux_Debug** - Debug build for Linux
2. **Linux_Release** - Optimized Linux build
3. **Windows_Debug** / **Windows_Release** (if present)
4. **macOS_Debug** / **macOS_Release** (if present)

#### Compiler Flags (Example from xLights.cbp)
```
Linux Debug:
  -Wall -g -std=gnu++20
  -D__WXDEBUG__
  -DWX_PRECOMP (precompiled headers)
  -DLINUX

Linux Release:
  -O2 -Wall -std=gnu++20
  -DNDEBUG
  -DWX_PRECOMP
  -DLINUX
```

#### Include Directories (Typical Configuration)
```
./include              (local headers)
./sequencer            (sequence system)
../xLights             (cross-project includes)
./effects              (effect definitions)
./models               (model definitions)
./support              (support utilities)
./outputs              (output system)
../include             (global includes)
../dependencies/libxlsxwriter/include
../include/sol2-3.5.0  (Lua bindings)
../dependencies        (third-party headers)
```

#### Linker Libraries (Linux)
```
-lGL -lGLU -lglut      (OpenGL)
-ldl -lX11 -lcurl      (System)
-lz -lzstd             (Compression)
-lwebp -lwebpdemux     (WebP)
wx-config --libs std,media,gl,aui,propgrid (wxWidgets)
pkg-config for: libavformat libavcodec libavutil libswresample libswscale
                gstreamer-1.0 gstreamer-video-1.0 log4cpp lua53
-rdynamic -lstdc++fs   (Runtime and filesystem)
../lib/linux/libliquidfun.a (Physics engine)
../dependencies/libxlsxwriter/lib/libxlsxwriter.a
```

### Visual Studio Build (Windows)

- **xLights/xLights.vcxproj** - Main project
- **xSchedule/xSchedule.vcxproj** - Scheduler
- **xCapture/xCapture.cbp** - Capture (converted from Code::Blocks)
- **xFade/xFade.vcxproj** - Fader
- **xScanner/xScanner.vcxproj** - Scanner
- **xLights-Test/Xlights-Test.vcxproj** - Unit tests
- Build configurations:
  - Debug x64
  - Release x64
  - Debug x86
  - Release x86

#### Build Scripts
- **build_scripts/msw/** - Windows-specific scripts
  - `build_VS_x64.cmd` - Visual Studio 64-bit build
  - `build_GCC_x64.cmd` - MinGW GCC build
  - `PackageWindowsRelease_VS.cmd` - Installer generation
  - Inno Setup scripts (`.iss`) for installer creation

### Xcode Build (macOS)

- **macOS/xLights.xcodeproj/** - Xcode project (symlinked as xLights.xcodeproj)
- Primary build target
- Code signing and app bundling

### CMake (Partial - Newer Components)

- **xScanner/CMakeLists.txt** - CMake build for scanner
- **xlDo/CMakeLists.txt** - Command-line tool
- **fseq_convert/CMakeLists.txt** - Format converter
- Allows cross-platform compatibility

### Precompiled Headers

- Strategy: Reduce build time by precompiling common headers
- Option `-Winvalid-pch` warns if PCH not used correctly
- `-DWX_PRECOMP` enables wxWidgets precompiled headers

### Pre-Build Steps (from build scripts)
- Dependency cloning (FFmpeg, wxWidgets)
- Version string generation
- Resource file compilation
- Installer packaging post-build

---

## 6. Testing Infrastructure

### Test Framework

#### Test Organization
- **xLights-Test/** - Test project directory
  - **tests/** - Test source files
  - Visual Studio project: `Xlights-Test.vcxproj`

#### Test Types
- Unit tests for core functionality
- Limited but growing test coverage
- Focus areas likely include:
  - Color conversions
  - Effect parameter handling
  - File I/O (FSEQ, XML)
  - Model coordinate transformations
  - Output protocol generation

### Quality Assurance Tools

#### Sequence Validation
- **CheckSequenceReport.cpp** (~122KB, ~3,060 lines)
- Comprehensive sequence checking:
  - Model reference validation
  - Effect parameter validation
  - Audio sync checking
  - Controller assignment validation
  - Orphaned effect detection
  - Duration consistency checking

#### Continuous Integration
- **.github/** - GitHub CI configuration
  - Issue templates
  - PR templates
  - Action workflows (likely includes builds for multiple platforms)

### Debugging Tools

- **StackWalker** (common/xlStackWalker.h) - Crash dump generation
- Memory leak detection (MSVC only, commented out by default)
- wxDEBUG_LEVEL macros for assertion support
- Console logging via log4cpp

---

## 7. Key Classes & Core Data Structures

### Model System
- **Model** - Base class, ~300+ lines header
  - Stores node list, controller assignment, screen location
  - Methods: GetNodeCount(), GetChannelCount(), Init(), Validate()
  - Properties: Name, vendor/model, color order, brightness curve
  
- **ModelManager** - Singleton managing all models
  - Load/save from XML
  - Model lookup by name
  - GetRenderBuffer() for effect rendering
  
- **Node** - Individual pixel representation
  - 3D coordinates (x, y, z)
  - Channel number (output location)
  - Strand/submodel grouping

### Effect System
- **RenderableEffect** - Abstract base for all effects
  - Render() - Pure virtual, must implement
  - GetPanel() - Optional UI
  - GetFileReferences() - Media file tracking
  - SupportsRenderCache() - Performance hint
  
- **Effect** (sequencer/Effect.h) - Instance of effect in timeline
  - Stores SettingsMap with effect parameters
  - Timing info (start/end ms)
  - Links to model and layer
  
- **EffectManager** - Factory for all effects
  - 60+ built-in effect types
  - Parameter definitions per effect
  - Icon/tooltip management

### Rendering System
- **RenderBuffer** - Effect output target
  - CPU: wxImage-based
  - GPU: OpenGL/Metal framebuffer
  - Pixel access: GetPixel(x, y), SetPixel(x, y, color)
  
- **PixelBuffer** - Model-level rendering orchestrator
  - Layer stacking and blending
  - Color curve application
  - Gamma and brightness adjustment
  - 3D transform support
  
- **OutputManager** - Singleton managing all outputs
  - Controller list
  - Output list (ports on controllers)
  - Frame transmission coordination

### Sequence Data
- **SequenceElements** - Root sequence structure
  - Timing definitions
  - Element tree (models, groups, ranges)
  - Effect layers per element
  
- **SequenceData** - Raw channel data
  - 2D array: channels × frames
  - Direct channel access for playback
  
- **DataLayer** - Logical layer of data
  - Can be effect-generated or imported

### Configuration
- **xLightsXmlFile** - Sequence file handler
  - Load/save `.xlights` files
  - Duration, timing, media info
  - Version compatibility
  
- **SettingsMap** - Effect parameter storage
  - Key-value pair (std::map<string, string>)
  - Type conversion helpers
  - Used throughout effects

### UI Components
- **xLightsFrame** - Main application window
  - Dockable panels (wxAuiManager)
  - Menu bar and toolbars
  - Central effects grid
  
- **MainSequencer** - Sequence editor view
  - EffectsGrid - Timeline display
  - TimeLine - Playback position
  - Element/Layer editing

### Manager Classes (Singletons)
- **OutputManager** - All output coordination
- **ModelManager** - All model management
- **EffectManager** - All effect definitions
- **ColorManager** - Global color palettes
- **AudioManager** - Audio playback
- **ViewpointMgr** - Viewport/camera control

---

## 8. Important Code Patterns & Idioms

### Settings Map Pattern
```cpp
SettingsMap settings;
settings["Parameter1"] = "value";
int val = wxAtoi(settings.GetString("Parameter1", "0"));
bool flag = settings.GetBool("BoolParam", false);
xlColor col = xlColor(settings.GetString("Color", "0"));
```

### Effect Rendering Pattern
```cpp
class MyEffect : public RenderableEffect {
    virtual void Render(Effect* effect, const SettingsMap& settings, RenderBuffer& buffer) {
        // Get parameters
        int intensity = wxAtoi(settings.GetString("Intensity", "100"));
        
        // Iterate model nodes
        for (int node = 0; node < buffer.BufferHt; node++) {
            for (int chan = 0; chan < buffer.BufferWi; chan++) {
                // Calculate pixel value
                xlColor color = ...;
                buffer.SetPixel(chan, node, color);
            }
        }
    }
};
```

### Model Type Pattern
```cpp
class CustomModel : public Model {
    CustomModel(const ModelManager& manager) : Model(manager) { }
    
    virtual void InitModel() override { 
        // Create nodes and set coordinates
    }
    
    virtual void GetNodeScreenLocation(int n, int& x, int& y) const override {
        // Calculate screen position for node n
    }
};
```

### Output Implementation Pattern
```cpp
class MyOutput : public Output {
    virtual bool Open() override { /* Connect */ }
    virtual bool SendDMX(const unsigned char* data, size_t size) override { /* Send */ }
    virtual void Close() override { /* Cleanup */ }
};
```

### Value Curve Usage
```cpp
ValueCurve vc("0=100, 0.5=50, 1=100");  // Ramp effects
int val = vc.GetIntValue(0.5);  // Get interpolated value
```

### Color Conversions
```cpp
xlColor c(255, 0, 0);  // RGB constructor
c.SetHSV(0, 255, 255);  // HSV setter
unsigned char r, g, b;
c.getRGB(r, g, b);  // Extract components
```

---

## 9. Common Development Tasks

### Adding a New Effect

1. **Create Effect Class**: `MyNewEffect.h/cpp` inheriting from `RenderableEffect`
2. **Implement Render()**: Core algorithm
3. **Create Panel**: `MyNewPanel.h/cpp` for parameters (wxsmith)
4. **Register**: Add to `EffectManager.cpp` in effect list
5. **Add Icon**: XPM bitmap (includes/adjust-16.xpm example)

### Adding a New Output Protocol

1. **Create Output Class**: Inherit from `Output`
2. **Implement Methods**: `Open()`, `SendDMX()`, `Close()`, `IsOk()`
3. **Register**: Add to `OutputManager.cpp`
4. **Test**: Use xCapture for validation

### Adding a New Model Type

1. **Create Model Class**: Inherit from `Model`
2. **Implement Initialization**: `InitModel()` creates nodes
3. **Screen Location**: `GetNodeScreenLocation()` for 2D projection
4. **Register**: Add to `ModelManager.cpp`

### Modifying Effect Parameters

1. **In SettingsMap**: Easy - just read different key
2. **In XML Format**: May need version upgrade logic in `adjustSettings()`
3. **Backward Compatibility**: Old sequences should still work

### Accessing Global State

```cpp
xLightsFrame* frame = xLightsApp::GetFrame();
ModelManager& mgr = frame->GetModelManager();
OutputManager* om = frame->GetOutputManager();
EffectManager& em = frame->GetEffectManager();
AudioManager* audio = frame->GetMedia();
```

---

## 10. Performance Considerations

### Rendering Optimization

**Render Cache**:
- `RenderCache.h/cpp` - Caches expensive effect renders
- Invalidated when:
  - Effect parameters change
  - Effect timing changes
  - Model changes
  - Output device changes

**GPU Acceleration**:
- OpenGL for 3D rendering
- Metal compute shaders for GPU acceleration
- GPU accumulator patterns for deferred rendering

**Multithreading**:
- `JobPool` - Background rendering threads
- Effects can be marked `CanRenderOnBackgroundThread()`
- UI thread never blocks on renders

### Memory Management

**Smart Pointers**:
- `std::unique_ptr` - Exclusive ownership
- `std::shared_ptr` - Shared ownership
- Automatic cleanup prevents leaks

**Pixel Data**:
- Buffers dynamically allocated based on model size
- Multi-layer support with efficient blending
- Compression (zstd) for large sequence files

---

## 11. Key Macros & Constants

### Defines in CBP Files
```cpp
-DWX_PRECOMP         // wxWidgets precompiled headers
-DLINUX / -DWINDOWS  // Platform identification
-D__WXDEBUG__        // Debug assertions
-DNDEBUG             // Release - disable asserts
-DENABLE_SERVICES    // AI/service integration
```

### Common Constants
```cpp
#define NO_CONTROLLER "No Controller"
#define USE_START_CHANNEL "Use Start Channel"
#define OUTPUT_E131 "E131"
#define OUTPUT_ARTNET "ArtNet"
#define OUTPUT_DMX "DMX"
#define OUTPUT_NULL "NULL"
```

---

## 12. Entry Points & Main Flows

### Application Startup (xLightsApp::OnInit())
1. Parse command-line arguments
2. Load last known show folder
3. Initialize OutputManager (loads controllers)
4. Initialize ModelManager (loads models)
5. Initialize EffectManager (registers effects)
6. Create main frame (xLightsFrame)
7. Restore window state and open last sequence file

### Sequence Load Flow
1. User opens `.xlights` file
2. `xLightsXmlFile::Open()` parses XML
3. Audio file loaded (if present)
4. `SequenceElements` built from XML
5. Models rendered in preview
6. Timeline populated with effects

### Playback Flow
1. Play button clicked
2. `MainSequencer::Play()` starts timer
3. Timer callback advances playback position
4. For each frame:
   - Query active effects at current time
   - Call `Render()` on each effect
   - Blend layers in `PixelBuffer`
   - `OutputManager` sends frame to hardware
5. Stop button stops timer

---

## 13. Important Files to Review

### Entry Points
- `/xLights/xLights/xLightsApp.h` - App initialization
- `/xLights/xLights/xLightsMain.h` - Main frame
- `/xLights/xLights/sequencer/MainSequencer.h` - Sequencer core

### Architecture
- `/xLights/xLights/effects/RenderableEffect.h` - Effect base
- `/xLights/xLights/models/Model.h` - Model base
- `/xLights/xLights/outputs/Output.h` - Output base
- `/xLights/xLights/outputs/Controller.h` - Controller management
- `/xLights/xLights/PixelBuffer.h` - Rendering orchestration

### Sequencer
- `/xLights/xLights/sequencer/EffectsGrid.h` - Timeline UI
- `/xLights/xLights/sequencer/SequenceElements.h` - Sequence data
- `/xLights/xLights/xLightsXmlFile.h` - File format

### Critical Utilities
- `/xLights/xLights/RenderBuffer.h` - Effect output
- `/xLights/xLights/ValueCurve.h` - Animation curves
- `/xLights/xLights/Color.h` - Color class
- `/xLights/xLights/UtilFunctions.h` - Common utilities

---

## 14. Useful Resources

### Documentation
- `/xLights/documentation/Lua Scripting.md` - Lua API reference
- `/xLights/CONTRIBUTING.md` - Contribution guidelines
- Issue tracker on GitHub

### Source Code Comments
- Most core classes have comments explaining the architecture
- wxsmith-generated files are auto-generated - edit sources, not generated code

### External Links
- **xLights Website**: https://www.xlights.org
- **GitHub**: https://github.com/xLightsSequencer/xLights
- **License**: Check License.txt (GPL-based)

---

## 15. Development Workflow Tips

### Code Organization
- Effects: Each new effect in `effects/` folder
- Models: Each model type in `models/` folder  
- Outputs: Each protocol in `outputs/` folder
- Dialogs: Root of xLights directory
- Utilities: `utils/` or `support/` depending on type

### Building
1. Open `.cbp` in Code::Blocks
2. Select build target (Linux_Debug, Linux_Release, etc.)
3. Build → Build or F9
4. Output binary in `../bin/` or `../bin64/`

### Debugging
- Set breakpoints in Code::Blocks
- Run → Debug or Ctrl+F8
- Use memory tools for leak detection (MSVC)
- Stack walker catches crashes and dumps info

### Version Control
- Main branch: `master`
- Follow existing code style
- Include proper commit messages
- Reference issues in PRs

---

## 16. Code Style & Contribution Guidelines

### Commit Message Style

When contributing to xLights, keep commit messages **concise and focused**:

**Good commit message format:**
```
Add confirmation dialog for viewpoint deletion

Prevents accidental deletion of 3D and 2D viewpoints by requiring
user confirmation before deletion.
```

**Principles:**
- **Short title** (50-72 characters) describing what was done
- **Brief description** (1-3 sentences) explaining why/what problem it solves
- **No excessive detail** - code changes speak for themselves
- **No attribution footers** - Git already tracks authorship
- Avoid long bullet-point lists in commit messages

**Bad practices to avoid:**
```
Add confirmation dialog for viewpoint deletion

Prevents accidental deletion of 3D and 2D viewpoints by requiring
user confirmation before deletion. Addresses user feedback about
accidentally clicking "Delete Viewpoint" when intending to click
"Load Viewpoint".

Changes:
- Added wxMessageBox confirmation dialog before deleting 3D viewpoints
- Added wxMessageBox confirmation dialog before deleting 2D viewpoints
- Dialog shows viewpoint name and warns action cannot be undone
- Uses wxYES_NO with wxNO_DEFAULT to prevent accidental confirmation
- Displays appropriate icon (wxICON_QUESTION) for confirmation prompt

Location: xLights/LayoutPanel.cpp
- Line 5158-5165: 3D viewpoint deletion confirmation
- Line 5175-5182: 2D viewpoint deletion confirmation

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Code Comment Guidelines

**When NOT to add comments:**
- Avoid obvious comments that just restate what the code does
- Don't add comments explaining simple, self-evident operations
- The xLights codebase generally has minimal inline comments for straightforward code

**Example - Unnecessary comment:**
```cpp
} else if (event.GetId() == xlights->viewpoint_mgr.GetCamera3D(i)->GetDeleteMenuId()) {
    // Confirm deletion to prevent accidental deletion  ❌ DON'T DO THIS
    std::string viewpointName = xlights->viewpoint_mgr.GetCamera3D(i)->GetName();
```

**Better - Let the code speak:**
```cpp
} else if (event.GetId() == xlights->viewpoint_mgr.GetCamera3D(i)->GetDeleteMenuId()) {
    std::string viewpointName = xlights->viewpoint_mgr.GetCamera3D(i)->GetName();
    wxString message = wxString::Format("Are you sure you want to delete the 3D viewpoint '%s'?\n\nThis action cannot be undone.", viewpointName);
    if (wxMessageBox(message, "Confirm Delete Viewpoint", wxYES_NO | wxNO_DEFAULT | wxICON_QUESTION, this) == wxYES) {
        xlights->viewpoint_mgr.DeleteCamera3D(i);
    }
}
```

**When TO add comments:**
- Complex algorithms or non-obvious logic
- Workarounds for platform-specific bugs
- Performance-critical sections explaining optimization choices
- Public API documentation (class/method headers)

### Code Consistency

From CONTRIBUTING.md:
> "Our code is not spectacularly consistent in structure or format ... do your best to be consistent with the code nearby your change."

**Key principles:**
1. **Match surrounding style** - Look at the file you're editing and follow its patterns
2. **Keep changes focused** - Don't reformat or refactor unrelated code
3. **No cosmetic-only PRs** - Don't submit PRs that only fix whitespace or formatting
4. **Indent consistently** - Match tabs vs spaces with the existing file

### Pull Request Guidelines

Before submitting a PR:

1. **Test your changes** - Verify functionality works as expected
2. **Clear problem statement** - Explain what issue you're solving
3. **Concise solution description** - Describe how your change fixes it
4. **Reference issues** - Link to GitHub issue if applicable
5. **Community value** - Ensure feature benefits broader community, not just personal use
6. **Avoid complexity** - Don't add UI complexity for niche features

**PR Description Format:**
```markdown
## Problem
Users accidentally delete viewpoints when clicking near "Load Viewpoint" button.

## Solution
Added confirmation dialog before deleting 3D/2D viewpoints.

## Testing
- Verified confirmation appears for both 3D and 2D viewpoint deletion
- Verified "No" cancels deletion
- Verified "Yes" proceeds with deletion
```

### Before Opening PRs

1. Ask for feedback on significant features before implementing
2. Listen to developer warnings about complex areas of code
3. Understand that some areas are off-limits until you're more familiar with codebase
4. Be prepared to discuss design decisions

---

## Summary

xLights is a sophisticated multi-application suite with a well-architected separation between:
- **Model System** (what you're controlling)
- **Effect System** (what you're displaying)
- **Output System** (how you're controlling it)
- **UI System** (how users interact with it)

The codebase follows object-oriented principles with clear interfaces for extending functionality. The effect and model systems use plugin patterns that make adding new effects and model types straightforward. The rendering pipeline efficiently handles complex multi-layer compositions with support for both CPU and GPU acceleration.

Understanding this architecture is key to making productive contributions to the xLights project. Start by examining one area deeply (e.g., adding an effect), then expand your knowledge to other systems.
