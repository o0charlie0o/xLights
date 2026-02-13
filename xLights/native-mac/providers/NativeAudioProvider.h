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

// NativeAudioProvider: macOS native implementation of IAudioProvider.
//
// Decodes audio using FFmpeg (libavformat/libavcodec) for format compatibility,
// then uses Apple Accelerate.framework (vDSP) for FFT spectrum analysis.
// This provides the same data that AudioManager::GetFrameData() does, but
// without any wxWidgets dependencies.
//
// Audio pipeline:
//   1. FFmpeg decodes audio file to interleaved float samples
//   2. Samples are split into left/right channels and normalised
//   3. prepareFrameData() runs vDSP FFT across all frames, producing
//      127-bin MIDI-note-mapped spectrum data per frame
//   4. Effects access pre-computed AudioFrameData during rendering
//
// Thread safety:
//   - loadAudio() and prepareFrameData() are NOT thread-safe (call from one thread)
//   - All read methods (getFrameData, getSample, etc.) are thread-safe for
//     concurrent access from multiple render threads once data is prepared

#include "../../engine/interfaces/IAudioProvider.h"

#include <memory>
#include <mutex>
#include <shared_mutex>
#include <vector>

namespace xlEngine {

class NativeAudioProvider : public IAudioProvider {
public:
    NativeAudioProvider();
    ~NativeAudioProvider() override;

    // Non-copyable
    NativeAudioProvider(const NativeAudioProvider&) = delete;
    NativeAudioProvider& operator=(const NativeAudioProvider&) = delete;

    // =========================================================================
    // IAudioProvider implementation
    // =========================================================================

    bool loadAudio(const std::string& filePath, int frameIntervalMS = 50) override;
    bool prepareFrameData() override;

    bool isLoaded() const override;
    bool isFrameDataReady() const override;

    AudioMetadata getMetadata() const override;
    long getDurationMS() const override;
    long getSampleRate() const override;
    int getFrameIntervalMS() const override;
    int getFrameCount() const override;

    const AudioFrameData* getFrameData(int frameIndex) const override;
    const AudioFrameData* getFrameDataAtTime(int timeMS) const override;

    float getLeftSample(long sampleOffset) const override;
    float getRightSample(long sampleOffset) const override;
    const float* getLeftSamplePtr(long sampleOffset) const override;
    const float* getRightSamplePtr(long sampleOffset) const override;
    long getTotalSamples() const override;

    void getLeftDataMinMax(long startSample, long endSample,
                           float& outMin, float& outMax) const override;

private:
    // FFT spectrum analysis for a block of samples.
    // Produces 127 bins mapped to MIDI notes 0-126.
    void calculateSpectrumAnalysis(const float* samples, int sampleCount,
                                   float& outMax, std::vector<float>& outSpectrum) const;

    // Internal sample pointer access (caller must hold _dataMutex)
    const float* getLeftSamplePtrInternal(long sampleOffset) const;

    // Audio data (set during loadAudio)
    std::vector<float> _leftChannel;     // Normalised left channel samples [-1, 1]
    std::vector<float> _rightChannel;    // Normalised right channel samples [-1, 1]

    // Pre-computed frame analysis data (set during prepareFrameData)
    std::vector<AudioFrameData> _frameData;

    // Metadata
    AudioMetadata _metadata;
    long _trackSize = 0;                 // Total samples per channel
    long _rate = 44100;                  // Internal processing rate

    // Normalisation values (computed during prepareFrameData)
    float _bigMax = -1.0f;
    float _bigMin = 1.0f;
    float _bigSpread = -1.0f;
    float _bigSpectrogramMax = -1.0f;

    // State flags
    bool _loaded = false;
    bool _frameDataReady = false;

    // Thread safety for frame data preparation
    mutable std::shared_mutex _dataMutex;
};

} // namespace xlEngine
