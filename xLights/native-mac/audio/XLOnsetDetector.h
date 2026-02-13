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

/// Onset detection methods (maps to aubio onset types).
typedef NS_ENUM(NSInteger, XLOnsetMethod) {
    XLOnsetMethodDefault = 0,   // aubio "default" (HFC)
    XLOnsetMethodEnergy,        // energy-based
    XLOnsetMethodHFC,           // high-frequency content
    XLOnsetMethodComplex,       // complex domain
    XLOnsetMethodPhase,         // phase deviation
    XLOnsetMethodSpecFlux,      // spectral flux
    XLOnsetMethodKL,            // Kullback-Leibler
    XLOnsetMethodMKL,           // modified Kullback-Leibler
    XLOnsetMethodSpecDiff,      // spectral difference
};

/// Stores the detection function curve from aubio onset detection.
/// Allows fast re-thresholding without re-running FFT/onset detection.
@interface XLOnsetResult : NSObject

/// Raw detection function values (one per hop).
@property (nonatomic, readonly) const float *detectionFunction;

/// Number of values in the detection function.
@property (nonatomic, readonly) NSUInteger detectionFunctionLength;

/// Hop size in samples used during detection.
@property (nonatomic, readonly) NSUInteger hopSize;

/// Sample rate used during detection.
@property (nonatomic, readonly) double sampleRate;

/// Re-threshold the cached detection function with new parameters.
/// This is a pure array scan — microsecond performance.
/// @param threshold Threshold value (0.0 - 1.0, higher = fewer onsets)
/// @param minIntervalMS Minimum interval between onsets in milliseconds
/// @return Array of onset times in milliseconds
- (NSArray<NSNumber *> *)recomputeOnsetsWithThreshold:(double)threshold
                                        minIntervalMS:(double)minIntervalMS;

@end

/// Wrapper around aubio's onset detection with two-stage detection strategy.
/// Stage 1: Full aubio onset detection (bandpass filter + FFT + onset function) ~100ms
/// Stage 2: Fast re-thresholding of cached detection function (microseconds)
@interface XLOnsetDetector : NSObject

/// Run onset detection on mono audio samples.
/// @param samples Mono PCM float samples
/// @param sampleCount Number of samples
/// @param sampleRate Sample rate in Hz
/// @param method Onset detection method
/// @param threshold Initial threshold (0.0 - 1.0)
/// @param minIntervalMS Minimum interval between onsets in milliseconds
/// @return XLOnsetResult with detection function and initial onset list, or nil on failure
+ (XLOnsetResult * _Nullable)detectOnsetsInSamples:(const float *)samples
                                       sampleCount:(NSUInteger)sampleCount
                                        sampleRate:(double)sampleRate
                                            method:(XLOnsetMethod)method
                                         threshold:(double)threshold
                                     minIntervalMS:(double)minIntervalMS;

@end

NS_ASSUME_NONNULL_END
