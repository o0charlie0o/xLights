/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLOnsetDetector.h"

// aubio C API - include only the specific headers we need
#include "types.h"
#include "fvec.h"
#include "cvec.h"
#include "spectral/phasevoc.h"
#include "spectral/specdesc.h"

#pragma mark - XLOnsetResult

@interface XLOnsetResult ()
@property (nonatomic, assign) float *detectionFunctionBuffer;
@property (nonatomic, readwrite) NSUInteger detectionFunctionLength;
@property (nonatomic, readwrite) NSUInteger hopSize;
@property (nonatomic, readwrite) double sampleRate;
@end

@implementation XLOnsetResult

- (void)dealloc {
    free(_detectionFunctionBuffer);
}

- (const float *)detectionFunction {
    return _detectionFunctionBuffer;
}

- (NSArray<NSNumber *> *)recomputeOnsetsWithThreshold:(double)threshold
                                        minIntervalMS:(double)minIntervalMS {
    if (!_detectionFunctionBuffer || _detectionFunctionLength == 0) {
        return @[];
    }

    // Find the maximum value in the detection function for normalization
    float maxVal = 0;
    for (NSUInteger i = 0; i < _detectionFunctionLength; i++) {
        float v = fabsf(_detectionFunctionBuffer[i]);
        if (v > maxVal) maxVal = v;
    }
    if (maxVal < 1e-10f) return @[];

    // Threshold is relative to max (0.0 = all, 1.0 = none)
    float absThreshold = (float)(threshold * maxVal);

    double minIntervalSamples = (minIntervalMS / 1000.0) * _sampleRate;
    NSUInteger minIntervalHops = (NSUInteger)(minIntervalSamples / (double)_hopSize);
    if (minIntervalHops < 1) minIntervalHops = 1;

    NSMutableArray<NSNumber *> *onsets = [NSMutableArray array];
    NSUInteger lastOnsetHop = 0;
    BOOL hadFirstOnset = NO;

    for (NSUInteger i = 1; i + 1 < _detectionFunctionLength; i++) {
        float val = _detectionFunctionBuffer[i];

        // Must exceed absolute threshold
        if (val < absThreshold) continue;

        // Must be a local peak
        if (val <= _detectionFunctionBuffer[i - 1]) continue;
        if (val <= _detectionFunctionBuffer[i + 1]) continue;

        // Minimum interval check
        if (hadFirstOnset && (i - lastOnsetHop) < minIntervalHops) continue;

        double timeMS = ((double)i * (double)_hopSize / _sampleRate) * 1000.0;
        [onsets addObject:@(timeMS)];
        lastOnsetHop = i;
        hadFirstOnset = YES;
    }

    return [onsets copy];
}

@end

#pragma mark - XLOnsetDetector

@implementation XLOnsetDetector

+ (const char *)aubioMethodString:(XLOnsetMethod)method {
    switch (method) {
        case XLOnsetMethodDefault:  return "default";
        case XLOnsetMethodEnergy:   return "energy";
        case XLOnsetMethodHFC:      return "hfc";
        case XLOnsetMethodComplex:  return "complex";
        case XLOnsetMethodPhase:    return "phase";
        case XLOnsetMethodSpecFlux: return "specflux";
        case XLOnsetMethodKL:       return "kl";
        case XLOnsetMethodMKL:      return "mkl";
        case XLOnsetMethodSpecDiff: return "specdiff";
    }
    return "default";
}

+ (XLOnsetResult *)detectOnsetsInSamples:(const float *)samples
                             sampleCount:(NSUInteger)sampleCount
                              sampleRate:(double)sampleRate
                                  method:(XLOnsetMethod)method
                               threshold:(double)threshold
                           minIntervalMS:(double)minIntervalMS {
    if (!samples || sampleCount == 0 || sampleRate <= 0) return nil;

    uint_t winSize = 1024;
    uint_t hopSize = 512;

    if (sampleRate > 48000) {
        winSize = 2048;
        hopSize = 1024;
    }

    // Create phase vocoder and spectral descriptor
    aubio_pvoc_t *pv = new_aubio_pvoc(winSize, hopSize);
    if (!pv) return nil;

    const char *methodStr = [self aubioMethodString:method];
    aubio_specdesc_t *sd = new_aubio_specdesc(methodStr, winSize);
    if (!sd) {
        del_aubio_pvoc(pv);
        return nil;
    }

    fvec_t *inputBuf = new_fvec(hopSize);
    cvec_t *fftgrain = new_cvec(winSize);
    fvec_t *descOut = new_fvec(1);

    NSUInteger numHops = (sampleCount + hopSize - 1) / hopSize;
    float *detFunc = (float *)calloc(numHops, sizeof(float));
    if (!detFunc) {
        del_aubio_specdesc(sd);
        del_aubio_pvoc(pv);
        del_fvec(inputBuf);
        del_cvec(fftgrain);
        del_fvec(descOut);
        return nil;
    }

    NSUInteger hopIdx = 0;
    for (NSUInteger pos = 0; pos + hopSize <= sampleCount; pos += hopSize) {
        // Copy hop into input buffer
        memcpy(inputBuf->data, samples + pos, hopSize * sizeof(float));

        // Phase vocoder: time domain -> spectral domain
        aubio_pvoc_do(pv, inputBuf, fftgrain);

        // Compute spectral descriptor (the detection function for this frame)
        aubio_specdesc_do(sd, fftgrain, descOut);

        detFunc[hopIdx] = descOut->data[0];
        hopIdx++;
    }

    // Handle remaining samples (partial last hop)
    NSUInteger remaining = sampleCount % hopSize;
    if (remaining > 0 && hopIdx < numHops) {
        NSUInteger pos = sampleCount - remaining;
        memcpy(inputBuf->data, samples + pos, remaining * sizeof(float));
        memset(inputBuf->data + remaining, 0, (hopSize - remaining) * sizeof(float));
        aubio_pvoc_do(pv, inputBuf, fftgrain);
        aubio_specdesc_do(sd, fftgrain, descOut);
        detFunc[hopIdx] = descOut->data[0];
        hopIdx++;
    }

    del_aubio_specdesc(sd);
    del_aubio_pvoc(pv);
    del_fvec(inputBuf);
    del_cvec(fftgrain);
    del_fvec(descOut);

    XLOnsetResult *result = [[XLOnsetResult alloc] init];
    result.detectionFunctionBuffer = detFunc;
    result.detectionFunctionLength = hopIdx;
    result.hopSize = hopSize;
    result.sampleRate = sampleRate;

    return result;
}

@end
