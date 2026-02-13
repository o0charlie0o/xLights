/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "NativeAudioProvider.h"

#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>
#import <AVFoundation/AVFoundation.h>

#include <algorithm>
#include <cmath>
#include <cstring>

namespace xlEngine {

// =========================================================================
// Construction / destruction
// =========================================================================

NativeAudioProvider::NativeAudioProvider() = default;

NativeAudioProvider::~NativeAudioProvider() = default;

// =========================================================================
// Audio loading via AVFoundation
// =========================================================================

bool NativeAudioProvider::loadAudio(const std::string& filePath, int frameIntervalMS) {
    std::unique_lock<std::shared_mutex> lock(_dataMutex);

    _loaded = false;
    _frameDataReady = false;
    _leftChannel.clear();
    _rightChannel.clear();
    _frameData.clear();
    _metadata = AudioMetadata();
    _metadata.filePath = filePath;
    _metadata.frameIntervalMS = frameIntervalMS;

    @autoreleasepool {
        NSString *path = [NSString stringWithUTF8String:filePath.c_str()];
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        NSError *error = nil;

        AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:fileURL error:&error];
        if (!audioFile) {
            NSLog(@"NativeAudioProvider: Failed to open audio file '%s': %@",
                  filePath.c_str(), error.localizedDescription);
            return false;
        }

        AVAudioFormat *processingFormat = audioFile.processingFormat;
        AVAudioFrameCount frameCount = (AVAudioFrameCount)audioFile.length;
        if (frameCount == 0) {
            NSLog(@"NativeAudioProvider: Audio file has zero frames");
            return false;
        }

        // Read audio into PCM buffer
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc]
            initWithPCMFormat:processingFormat frameCapacity:frameCount];
        if (!buffer) {
            NSLog(@"NativeAudioProvider: Failed to allocate PCM buffer");
            return false;
        }

        if (![audioFile readIntoBuffer:buffer error:&error]) {
            NSLog(@"NativeAudioProvider: Failed to read audio data: %@",
                  error.localizedDescription);
            return false;
        }

        NSUInteger channelCount = processingFormat.channelCount;
        NSUInteger readFrames = buffer.frameLength;
        double sampleRate = processingFormat.sampleRate;

        _rate = static_cast<long>(sampleRate);
        _metadata.sampleRate = _rate;
        _metadata.channels = static_cast<int>(channelCount);

        // Extract metadata from the audio asset
        AVURLAsset *asset = [AVURLAsset assetWithURL:fileURL];
        for (AVMetadataItem *item in [asset metadata]) {
            NSString *key = [item commonKey];
            NSString *value = [item stringValue];
            if (key && value) {
                if ([key isEqualToString:AVMetadataCommonKeyTitle]) {
                    _metadata.title = [value UTF8String];
                } else if ([key isEqualToString:AVMetadataCommonKeyArtist]) {
                    _metadata.artist = [value UTF8String];
                } else if ([key isEqualToString:AVMetadataCommonKeyAlbumName]) {
                    _metadata.album = [value UTF8String];
                }
            }
        }

        // Reserve space for channel data
        _leftChannel.resize(readFrames);
        _rightChannel.resize(readFrames);

        if (processingFormat.isInterleaved) {
            // Interleaved format: L0 R0 L1 R1 ...
            const float *src = buffer.floatChannelData[0];
            for (NSUInteger i = 0; i < readFrames; ++i) {
                _leftChannel[i] = src[i * channelCount];
                _rightChannel[i] = (channelCount >= 2) ? src[i * channelCount + 1] : src[i * channelCount];
            }
        } else {
            // Non-interleaved (typical AVAudioFile processing format)
            const float *leftData = buffer.floatChannelData[0];
            std::memcpy(_leftChannel.data(), leftData, readFrames * sizeof(float));

            if (channelCount >= 2) {
                const float *rightData = buffer.floatChannelData[1];
                std::memcpy(_rightChannel.data(), rightData, readFrames * sizeof(float));
            } else {
                // Mono: duplicate left to right
                std::memcpy(_rightChannel.data(), leftData, readFrames * sizeof(float));
            }
        }

        _trackSize = static_cast<long>(readFrames);
        _metadata.durationMS = (_trackSize * 1000L) / _rate;

        _loaded = (_trackSize > 0);

        if (_loaded) {
            NSLog(@"NativeAudioProvider: Loaded %ld samples at %ld Hz from %s (%.2f sec)",
                  _trackSize, _rate, filePath.c_str(),
                  static_cast<double>(_metadata.durationMS) / 1000.0);
        }
    }

    return _loaded;
}

// =========================================================================
// FFT Spectrum Analysis (using Accelerate vDSP)
// =========================================================================

void NativeAudioProvider::calculateSpectrumAnalysis(
    const float* samples, int sampleCount,
    float& outMax, std::vector<float>& outSpectrum) const
{
    outSpectrum.clear();
    outSpectrum.reserve(127);

    if (sampleCount <= 0 || !samples) {
        outSpectrum.resize(127, 0.0f);
        return;
    }

    // Find the next power of 2 for the FFT size
    int log2n = static_cast<int>(std::ceil(std::log2(static_cast<double>(sampleCount))));
    if (log2n < 4) log2n = 4; // minimum 16 samples
    vDSP_Length fftSize = 1 << log2n;

    FFTSetup fftSetup = vDSP_create_fftsetup(static_cast<vDSP_Length>(log2n), kFFTRadix2);
    if (!fftSetup) {
        outSpectrum.resize(127, 0.0f);
        return;
    }

    // Prepare input: copy and zero-pad if needed
    std::vector<float> paddedInput(fftSize, 0.0f);
    size_t copyCount = std::min(static_cast<size_t>(sampleCount), static_cast<size_t>(fftSize));
    std::memcpy(paddedInput.data(), samples, copyCount * sizeof(float));

    // Split complex format for vDSP
    size_t halfN = fftSize / 2;
    std::vector<float> realPart(halfN);
    std::vector<float> imagPart(halfN);
    DSPSplitComplex splitComplex;
    splitComplex.realp = realPart.data();
    splitComplex.imagp = imagPart.data();

    // Convert interleaved real data to split complex
    vDSP_ctoz(reinterpret_cast<const DSPComplex*>(paddedInput.data()),
              2, &splitComplex, 1, halfN);

    // Perform forward FFT
    vDSP_fft_zrip(fftSetup, &splitComplex, 1,
                  static_cast<vDSP_Length>(log2n), kFFTDirection_Forward);

    // Scale by 1/(2*N) to match standard FFT normalisation
    float scale = 1.0f / (2.0f * static_cast<float>(fftSize));
    vDSP_vsmul(splitComplex.realp, 1, &scale, splitComplex.realp, 1, halfN);
    vDSP_vsmul(splitComplex.imagp, 1, &scale, splitComplex.imagp, 1, halfN);

    // Compute squared magnitudes then square root for actual magnitudes
    std::vector<float> magnitudes(halfN);
    vDSP_zvmags(&splitComplex, 1, magnitudes.data(), 1, halfN);

    int halfNInt = static_cast<int>(halfN);
    vvsqrtf(magnitudes.data(), magnitudes.data(), &halfNInt);

    // Map FFT bins to 127 MIDI notes (matching legacy CalculateSpectrumAnalysis)
    for (int j = 0; j < 127; ++j) {
        double freq = 440.0 * std::pow(2.0, (static_cast<double>(j) - 69.0) / 12.0);
        int startBin = static_cast<int>(freq * static_cast<double>(fftSize) / static_cast<double>(_rate));
        double freqNext = 440.0 * std::pow(2.0, (static_cast<double>(j + 1) - 69.0) / 12.0);
        int endBin = static_cast<int>(freqNext * static_cast<double>(fftSize) / static_cast<double>(_rate));

        float val = 0.0f;
        if (endBin < static_cast<int>(halfN) - 1) {
            for (int k = startBin; k <= endBin && k < static_cast<int>(halfN); ++k) {
                val = std::max(val, magnitudes[static_cast<size_t>(k)]);
            }
        }

        float db = std::log10(val + 1e-10f); // avoid log(0)
        if (db < 0.0f) db = 0.0f;

        outSpectrum.push_back(db);
        if (db > outMax) outMax = db;
    }

    vDSP_destroy_fftsetup(fftSetup);
}

// =========================================================================
// Frame Data Preparation
// =========================================================================

bool NativeAudioProvider::prepareFrameData() {
    std::unique_lock<std::shared_mutex> lock(_dataMutex);

    if (!_loaded || _trackSize == 0) return false;

    _frameDataReady = false;
    _frameData.clear();

    int samplesPerFrame = static_cast<int>(_rate * _metadata.frameIntervalMS / 1000);
    int frames = static_cast<int>(_metadata.durationMS / _metadata.frameIntervalMS);
    while (frames * _metadata.frameIntervalMS < _metadata.durationMS) {
        frames++;
    }
    long totalSamples = static_cast<long>(frames) * samplesPerFrame;

    _bigMax = -1.0f;
    _bigMin = 1.0f;
    _bigSpread = -1.0f;
    _bigSpectrogramMax = -1.0f;

    size_t step = 2048;
    _frameData.resize(static_cast<size_t>(frames));

    long pos = 0;
    std::vector<float> spectrogram;
    std::vector<float> subSpectrogram;

    for (int i = 0; i < frames; ++i) {
        float max = -100.0f;
        float min = 100.0f;
        float spread = -100.0f;

        // Clear spectrogram if we are about to compute new data
        long frameStart = static_cast<long>(i) * samplesPerFrame;
        long frameEnd = frameStart + samplesPerFrame;
        if (pos < frameEnd && pos + static_cast<long>(step) < totalSamples) {
            spectrogram.clear();
        }

        // Compute FFT for overlapping windows within this frame
        while (pos < frameEnd && pos + static_cast<long>(step) < totalSamples) {
            const float* pdata = getLeftSamplePtrInternal(pos);
            float max2 = 0.0f;

            if (pdata) {
                long remaining = _trackSize - pos;
                int count = static_cast<int>(std::min(static_cast<long>(step), remaining));
                calculateSpectrumAnalysis(pdata, count, max2, subSpectrogram);
            } else {
                subSpectrogram.clear();
            }

            if (max2 > _bigSpectrogramMax) {
                _bigSpectrogramMax = max2;
            }
            pos += static_cast<long>(step);

            // Merge: take maximum of each bin
            if (spectrogram.empty()) {
                spectrogram = subSpectrogram;
            } else if (!subSpectrogram.empty()) {
                for (size_t k = 0; k < spectrogram.size() && k < subSpectrogram.size(); ++k) {
                    spectrogram[k] = std::max(spectrogram[k], subSpectrogram[k]);
                }
            }
        }

        // Compute raw waveform statistics for this frame
        for (int j = 0; j < samplesPerFrame; ++j) {
            long offset = frameStart + j;
            float data = (offset < _trackSize) ? _leftChannel[static_cast<size_t>(offset)] : 0.0f;

            if (data > max) max = data;
            if (data < min) min = data;
            if (max - min > spread) spread = max - min;
        }

        if (max > _bigMax) _bigMax = max;
        if (min < _bigMin) _bigMin = min;
        if (spread > _bigSpread) _bigSpread = spread;

        _frameData[static_cast<size_t>(i)].min = min;
        _frameData[static_cast<size_t>(i)].max = max;
        _frameData[static_cast<size_t>(i)].spread = spread;
        _frameData[static_cast<size_t>(i)].vu = spectrogram;
    }

    // Normalise data so the maximum value across the track maps to 1.0
    float bigMaxScale = (_bigMax > 0.0f) ? (1.0f / _bigMax) : 1.0f;
    float bigMinScale = (_bigMin < 0.0f) ? (1.0f / _bigMin) : 1.0f;
    float bigSpreadScale = (_bigSpread > 0.0f) ? (1.0f / _bigSpread) : 1.0f;
    float bigSpectrogramScale = (_bigSpectrogramMax > 0.0f) ? (1.0f / _bigSpectrogramMax) : 1.0f;

    for (auto& fr : _frameData) {
        fr.max *= bigMaxScale;
        fr.min *= bigMinScale;
        fr.spread *= bigSpreadScale;

        for (auto& v : fr.vu) {
            v *= bigSpectrogramScale;
        }
    }

    _frameDataReady = true;
    NSLog(@"NativeAudioProvider: Frame data prepared. %d frames at %dms intervals",
          frames, _metadata.frameIntervalMS);

    return true;
}

// =========================================================================
// State queries
// =========================================================================

bool NativeAudioProvider::isLoaded() const {
    return _loaded;
}

bool NativeAudioProvider::isFrameDataReady() const {
    return _frameDataReady;
}

// =========================================================================
// Metadata
// =========================================================================

AudioMetadata NativeAudioProvider::getMetadata() const {
    return _metadata;
}

long NativeAudioProvider::getDurationMS() const {
    return _metadata.durationMS;
}

long NativeAudioProvider::getSampleRate() const {
    return _rate;
}

int NativeAudioProvider::getFrameIntervalMS() const {
    return _metadata.frameIntervalMS;
}

int NativeAudioProvider::getFrameCount() const {
    std::shared_lock<std::shared_mutex> lock(_dataMutex);
    return static_cast<int>(_frameData.size());
}

// =========================================================================
// Frame data access (thread-safe read)
// =========================================================================

const AudioFrameData* NativeAudioProvider::getFrameData(int frameIndex) const {
    std::shared_lock<std::shared_mutex> lock(_dataMutex);

    if (!_frameDataReady) return nullptr;
    if (frameIndex < 0 || frameIndex >= static_cast<int>(_frameData.size())) return nullptr;

    return &_frameData[static_cast<size_t>(frameIndex)];
}

const AudioFrameData* NativeAudioProvider::getFrameDataAtTime(int timeMS) const {
    if (_metadata.frameIntervalMS <= 0) return nullptr;
    int frame = timeMS / _metadata.frameIntervalMS;
    return getFrameData(frame);
}

// =========================================================================
// Raw waveform access (thread-safe read)
// =========================================================================

float NativeAudioProvider::getLeftSample(long sampleOffset) const {
    std::shared_lock<std::shared_mutex> lock(_dataMutex);
    if (sampleOffset < 0 || sampleOffset >= _trackSize) return 0.0f;
    return _leftChannel[static_cast<size_t>(sampleOffset)];
}

float NativeAudioProvider::getRightSample(long sampleOffset) const {
    std::shared_lock<std::shared_mutex> lock(_dataMutex);
    if (sampleOffset < 0 || sampleOffset >= _trackSize) return 0.0f;
    return _rightChannel[static_cast<size_t>(sampleOffset)];
}

const float* NativeAudioProvider::getLeftSamplePtr(long sampleOffset) const {
    std::shared_lock<std::shared_mutex> lock(_dataMutex);
    return getLeftSamplePtrInternal(sampleOffset);
}

const float* NativeAudioProvider::getRightSamplePtr(long sampleOffset) const {
    std::shared_lock<std::shared_mutex> lock(_dataMutex);
    if (sampleOffset < 0 || sampleOffset >= _trackSize) return nullptr;
    return _rightChannel.data() + sampleOffset;
}

long NativeAudioProvider::getTotalSamples() const {
    return _trackSize;
}

void NativeAudioProvider::getLeftDataMinMax(long startSample, long endSample,
                                             float& outMin, float& outMax) const {
    std::shared_lock<std::shared_mutex> lock(_dataMutex);

    outMin = 0.0f;
    outMax = 0.0f;

    if (!_loaded || startSample >= _trackSize) return;

    if (startSample < 0) startSample = 0;
    if (endSample > _trackSize) endSample = _trackSize;
    if (startSample >= endSample) return;

    outMin = _leftChannel[static_cast<size_t>(startSample)];
    outMax = outMin;

    for (long i = startSample + 1; i < endSample; ++i) {
        float v = _leftChannel[static_cast<size_t>(i)];
        if (v < outMin) outMin = v;
        if (v > outMax) outMax = v;
    }
}

// =========================================================================
// Internal helpers (no locking - caller must hold lock)
// =========================================================================

const float* NativeAudioProvider::getLeftSamplePtrInternal(long sampleOffset) const {
    if (sampleOffset < 0 || sampleOffset >= _trackSize) return nullptr;
    return _leftChannel.data() + sampleOffset;
}

} // namespace xlEngine
