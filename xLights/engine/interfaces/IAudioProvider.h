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

// IAudioProvider: Pure C++ interface for audio data access.
//
// This interface provides audio analysis data (FFT spectrum, waveform samples,
// peak levels) to the native render pipeline without depending on wxWidgets
// AudioManager. Effects like VUMeter, Music, Piano, Guitar, Liquid, Arpeggio,
// Fire, Fireworks, Meteors, Shape, Strobe, and Tendril all consume audio data
// during rendering.
//
// The interface mirrors the data that legacy AudioManager::GetFrameData()
// provides via FrameData (max, min, spread, vu spectrum, notes), plus raw
// waveform sample access for effects that need it (e.g., VUMeter waveform
// mode).
//
// Thread safety: Implementations must be safe for concurrent read access
// from multiple render threads. Frame data is pre-computed and read-only
// during rendering.
//
// Design principles:
// - Use ONLY std:: types (no wxWidgets types cross this boundary)
// - Pre-compute expensive FFT data once, serve it cheaply per frame
// - Match the data format that effects already expect from FrameData

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace xlEngine {

// Pre-computed audio analysis data for a single frame.
// Mirrors the legacy FrameData struct from AudioManager.h.
// All values are normalised to [0, 1] range unless noted otherwise.
struct AudioFrameData {
    float max = 0.0f;              // Peak positive sample value (normalised)
    float min = 0.0f;              // Peak negative sample value (normalised)
    float spread = 0.0f;           // max - min spread (normalised)

    // FFT spectrum data: 127 bins mapped to MIDI notes 0-126.
    // Each value is the log10 magnitude for that note's frequency band,
    // normalised so the loudest bin across the entire track is 1.0.
    // This matches the legacy FrameData::vu vector.
    std::vector<float> vu;

    // Polyphonic transcription note data (optional, computed on demand).
    // Each entry is a MIDI note number detected as active in this frame.
    // Empty if polyphonic transcription has not been performed.
    std::vector<float> notes;

    bool isValid() const { return !vu.empty(); }
};

// Audio metadata for the loaded audio file.
struct AudioMetadata {
    std::string filePath;          // Full path to the audio file
    std::string title;             // ID3/metadata title
    std::string artist;            // ID3/metadata artist
    std::string album;             // ID3/metadata album

    long durationMS = 0;           // Total duration in milliseconds
    long sampleRate = 44100;       // Sample rate in Hz
    int channels = 0;              // Number of audio channels
    int bits = 0;                  // Bits per sample
    long bitRate = 0;              // Bit rate in bps
    int frameIntervalMS = 50;      // Frame interval used for analysis
};

// IAudioProvider: Abstract interface for audio data access.
//
// The provider pre-computes FFT spectrum and level data for the entire
// audio file, then serves it per-frame during rendering. This matches
// the AudioManager pattern where PrepareFrameData() runs once and
// GetFrameData() returns cached results.
//
// Implementations:
// - NativeAudioProvider: macOS native implementation using Accelerate.framework
// - Future: AudioManagerAdapter wrapping legacy AudioManager for hybrid builds
class IAudioProvider {
public:
    virtual ~IAudioProvider() = default;

    // =========================================================================
    // Lifecycle
    // =========================================================================

    // Load audio from a file path. Returns true on success.
    // This decodes the audio and prepares raw sample data but does NOT
    // compute frame analysis data (call prepareFrameData() for that).
    virtual bool loadAudio(const std::string& filePath, int frameIntervalMS = 50) = 0;

    // Pre-compute FFT spectrum and level data for all frames.
    // This is the expensive operation (FFT across entire file).
    // Must be called before getFrameData() will return valid results.
    // Returns true on success.
    virtual bool prepareFrameData() = 0;

    // Check if audio has been loaded successfully.
    virtual bool isLoaded() const = 0;

    // Check if frame data has been prepared (FFT analysis complete).
    virtual bool isFrameDataReady() const = 0;

    // =========================================================================
    // Audio Metadata
    // =========================================================================

    // Get metadata about the loaded audio file.
    virtual AudioMetadata getMetadata() const = 0;

    // Get the total duration in milliseconds.
    virtual long getDurationMS() const = 0;

    // Get the sample rate in Hz.
    virtual long getSampleRate() const = 0;

    // Get the frame interval used for analysis (in milliseconds).
    virtual int getFrameIntervalMS() const = 0;

    // Get the total number of analysis frames.
    virtual int getFrameCount() const = 0;

    // =========================================================================
    // Frame Data Access (pre-computed)
    // =========================================================================

    // Get pre-computed audio analysis data for a specific frame index.
    // Returns nullptr if frame is out of range or data is not ready.
    // The returned pointer is valid until the provider is destroyed or
    // prepareFrameData() is called again.
    // Thread-safe for concurrent read access.
    virtual const AudioFrameData* getFrameData(int frameIndex) const = 0;

    // Get frame data for a specific time in milliseconds.
    // Convenience wrapper: converts ms to frame index using frameIntervalMS.
    virtual const AudioFrameData* getFrameDataAtTime(int timeMS) const = 0;

    // =========================================================================
    // Raw Waveform Access
    // =========================================================================

    // Get raw left channel sample data at a sample offset.
    // Returns 0.0 if offset is out of range or no audio loaded.
    // Sample values are normalised to [-1.0, 1.0].
    virtual float getLeftSample(long sampleOffset) const = 0;

    // Get raw right channel sample data at a sample offset.
    // Returns 0.0 if offset is out of range or no audio loaded.
    virtual float getRightSample(long sampleOffset) const = 0;

    // Get a pointer to a contiguous block of left channel samples
    // starting at the given offset. Returns nullptr if out of range.
    // The pointer is valid until the provider is destroyed.
    virtual const float* getLeftSamplePtr(long sampleOffset) const = 0;

    // Get a pointer to a contiguous block of right channel samples
    // starting at the given offset. Returns nullptr if out of range.
    virtual const float* getRightSamplePtr(long sampleOffset) const = 0;

    // Get the total number of samples per channel.
    virtual long getTotalSamples() const = 0;

    // =========================================================================
    // Waveform Min/Max for Range (used by VUMeter waveform mode)
    // =========================================================================

    // Get the min and max sample values for a range of left channel samples.
    // Used by effects that need waveform envelope data.
    virtual void getLeftDataMinMax(long startSample, long endSample,
                                   float& outMin, float& outMax) const = 0;

    // =========================================================================
    // MIDI Note Utilities
    // =========================================================================

    // Convert a MIDI note number to frequency in Hz.
    static double midiToFrequency(int midiNote) {
        return 440.0 * std::pow(2.0, (midiNote - 69.0) / 12.0);
    }
};

} // namespace xlEngine
