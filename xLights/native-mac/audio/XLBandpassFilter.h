/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bandpass filter using Apple vDSP biquad operations.
/// Performs stereo→mono mixing and Butterworth highpass+lowpass cascade.
@interface XLBandpassFilter : NSObject

/// Mix interleaved multi-channel audio to mono by averaging channels.
/// @param interleavedSamples Interleaved PCM float samples
/// @param sampleCount Number of frames (not total samples)
/// @param channelCount Number of channels (1=mono, 2=stereo, etc.)
/// @return Newly allocated mono float buffer (caller must free). NULL on failure.
+ (float * _Nullable)mixToMono:(const float *)interleavedSamples
                   sampleCount:(NSUInteger)sampleCount
                  channelCount:(NSUInteger)channelCount;

/// Apply a bandpass filter (highpass at lowCutoffHz + lowpass at highCutoffHz).
/// Uses cascaded 2nd-order Butterworth biquad sections via vDSP_biquad.
/// @param monoSamples Mono PCM float samples
/// @param sampleCount Number of samples
/// @param sampleRate Sample rate in Hz
/// @param lowCutoffHz Lower frequency cutoff (highpass)
/// @param highCutoffHz Upper frequency cutoff (lowpass)
/// @return Newly allocated filtered float buffer (caller must free). NULL on failure.
+ (float * _Nullable)applyBandpassToSamples:(const float *)monoSamples
                                sampleCount:(NSUInteger)sampleCount
                                 sampleRate:(double)sampleRate
                                lowCutoffHz:(double)lowCutoffHz
                               highCutoffHz:(double)highCutoffHz;

@end

NS_ASSUME_NONNULL_END
