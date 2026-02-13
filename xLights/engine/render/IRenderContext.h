#pragma once

/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// IRenderContext: Lightweight interface replacing xLightsFrame* dependency
// for NativeRenderBuffer and NativePixelBuffer.
//
// The legacy RenderBuffer takes xLightsFrame* in its constructor and uses it
// to access the audio manager, sequence metadata, and model manager. This
// interface extracts only the subset of functionality that the render pipeline
// actually needs, enabling wx-free rendering in the native macOS build.
//
// Design principles:
// - Use ONLY std:: types and forward declarations (no wxWidgets types)
// - Minimal surface area: only what rendering actually needs
// - Thread-safe: implementations must handle concurrent access
// - Pointer returned by getAudioManager() is opaque to avoid pulling in
//   AudioManager.h; callers that need AudioManager cast the void* themselves.
// - getAudioProvider() returns the native audio pipeline interface for
//   wx-free audio data access during effect rendering.

#include <string>
#include <cstdint>

namespace xlEngine {

class IAudioProvider;

struct IRenderContext {
    virtual ~IRenderContext() = default;

    // Returns a pointer to the AudioManager for audio-reactive effects.
    // Returns nullptr if no audio is loaded.
    // The return type is void* to avoid pulling AudioManager.h into this header;
    // callers cast to AudioManager* as needed.
    // DEPRECATED: Prefer getAudioProvider() for native builds.
    virtual void* getAudioManager() = 0;

    // Returns the native audio provider for audio-reactive effects.
    // Returns nullptr if no audio is loaded or audio provider is not set.
    // This is the preferred audio access method for the native macOS build,
    // replacing the opaque void* getAudioManager() pattern.
    virtual IAudioProvider* getAudioProvider() { return nullptr; }

    // Returns the total sequence duration in seconds.
    virtual double getSequenceDuration() = 0;

    // Returns the frame time in milliseconds (e.g. 50 for 20fps, 25 for 40fps).
    virtual int getFrameTimeMS() = 0;
};

} // namespace xlEngine
