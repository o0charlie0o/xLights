# Spike 1: Engine API Vertical Slice

## Purpose

This spike validates that the xLights C++ rendering engine can be driven
programmatically without the full GUI, as a prerequisite for the native
macOS rebuild described in IMPLEMENTATION_GUIDE.md.

## Key Finding

The xLights engine **cannot** be used without wxWidgets at this time.
Every core class has deep wx dependencies. However, the engine CAN be
driven without creating any GUI windows, using wxWidgets in console mode.

See FINDINGS.md for the full analysis.

## Building

This spike is designed to be built with the existing xLights Xcode project
infrastructure. It requires wxWidgets 3.3+ headers and libraries.

See BUILD.md for instructions.

## What This Proves

1. The C++ engine can be initialized without any GUI windows
2. Sequence XML files can be loaded and parsed programmatically
3. Models can be enumerated from the rgbeffects configuration
4. The rendering pipeline can be invoked on a specific model at a specific time
5. Pixel data can be read back from the render buffer

## What This Documents (for Phase 0)

See FINDINGS.md for the complete coupling analysis and decoupling strategy.
