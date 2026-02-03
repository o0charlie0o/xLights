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

#import <Foundation/Foundation.h>

/// Pre-computed min/max amplitude bucket for waveform overview rendering.
typedef struct {
    float minL;
    float maxL;
    float minR;
    float maxR;
} XLWaveformBucket;

/// Holds decoded PCM audio sample data loaded from an audio file.
@interface XLAudioSampleData : NSObject

/// Interleaved L/R PCM float data (mono: single channel, stereo: L0 R0 L1 R1 ...).
@property (nonatomic, readonly) float *samples;

/// Total number of sample frames (each frame = one sample per channel).
@property (nonatomic, readonly) NSUInteger sampleCount;

/// Number of audio channels (1 = mono, 2 = stereo).
@property (nonatomic, readonly) NSUInteger channelCount;

/// Sample rate in Hz (e.g. 44100).
@property (nonatomic, readonly) double sampleRate;

/// Total duration in seconds.
@property (nonatomic, readonly) NSTimeInterval duration;

/// Designated initializer (takes ownership of the samples buffer).
- (instancetype)initWithSamples:(float *)samples
                    sampleCount:(NSUInteger)sampleCount
                   channelCount:(NSUInteger)channelCount
                     sampleRate:(double)sampleRate;

@end

/// Loads audio files and generates waveform overview data for display.
@interface XLAudioLoader : NSObject

/// Load an audio file and extract PCM sample data using AVFoundation.
/// Supports MP3, WAV, AAC, M4A, AIFF, and other formats supported by AVAudioFile.
/// Returns nil on failure (error is logged to console).
+ (XLAudioSampleData *)loadAudioFile:(NSString *)path;

/// Generate a pre-computed waveform overview at reduced resolution.
/// Returns an array of NSValue-wrapped XLWaveformBucket structs,
/// one per time bucket. Each bucket contains the min/max amplitude
/// for left and right channels over that time slice.
///
/// @param audioData The decoded audio sample data.
/// @param bucketCount Number of time buckets to divide the audio into.
/// @return Array of NSValue containing XLWaveformBucket structs.
+ (NSArray<NSValue *> *)generateWaveformOverview:(XLAudioSampleData *)audioData
                                     bucketCount:(NSUInteger)bucketCount;

@end
