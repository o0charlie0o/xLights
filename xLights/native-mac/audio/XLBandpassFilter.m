/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLBandpassFilter.h"
#import <Accelerate/Accelerate.h>
#import <math.h>

@implementation XLBandpassFilter

+ (float *)mixToMono:(const float *)interleavedSamples
         sampleCount:(NSUInteger)sampleCount
        channelCount:(NSUInteger)channelCount {
    if (!interleavedSamples || sampleCount == 0 || channelCount == 0) return NULL;

    float *mono = (float *)calloc(sampleCount, sizeof(float));
    if (!mono) return NULL;

    if (channelCount == 1) {
        memcpy(mono, interleavedSamples, sampleCount * sizeof(float));
        return mono;
    }

    // Average all channels
    float scale = 1.0f / (float)channelCount;
    for (NSUInteger i = 0; i < sampleCount; i++) {
        float sum = 0;
        for (NSUInteger ch = 0; ch < channelCount; ch++) {
            sum += interleavedSamples[i * channelCount + ch];
        }
        mono[i] = sum * scale;
    }

    return mono;
}

/// Compute 2nd-order Butterworth highpass biquad coefficients.
/// Transfer function coefficients for b0,b1,b2,a1,a2 (a0 normalized to 1).
static void butterworthHighpass(double sampleRate, double cutoffHz,
                                double *b0, double *b1, double *b2,
                                double *a1, double *a2) {
    double w0 = 2.0 * M_PI * cutoffHz / sampleRate;
    double cosw0 = cos(w0);
    double sinw0 = sin(w0);
    double alpha = sinw0 / (2.0 * M_SQRT2); // Q = sqrt(2)/2 for Butterworth

    double a0_raw = 1.0 + alpha;
    *b0 = ((1.0 + cosw0) / 2.0) / a0_raw;
    *b1 = (-(1.0 + cosw0)) / a0_raw;
    *b2 = ((1.0 + cosw0) / 2.0) / a0_raw;
    *a1 = (-2.0 * cosw0) / a0_raw;
    *a2 = (1.0 - alpha) / a0_raw;
}

/// Compute 2nd-order Butterworth lowpass biquad coefficients.
static void butterworthLowpass(double sampleRate, double cutoffHz,
                               double *b0, double *b1, double *b2,
                               double *a1, double *a2) {
    double w0 = 2.0 * M_PI * cutoffHz / sampleRate;
    double cosw0 = cos(w0);
    double sinw0 = sin(w0);
    double alpha = sinw0 / (2.0 * M_SQRT2);

    double a0_raw = 1.0 + alpha;
    *b0 = ((1.0 - cosw0) / 2.0) / a0_raw;
    *b1 = (1.0 - cosw0) / a0_raw;
    *b2 = ((1.0 - cosw0) / 2.0) / a0_raw;
    *a1 = (-2.0 * cosw0) / a0_raw;
    *a2 = (1.0 - alpha) / a0_raw;
}

+ (float *)applyBandpassToSamples:(const float *)monoSamples
                      sampleCount:(NSUInteger)sampleCount
                       sampleRate:(double)sampleRate
                      lowCutoffHz:(double)lowCutoffHz
                     highCutoffHz:(double)highCutoffHz {
    if (!monoSamples || sampleCount == 0 || sampleRate <= 0) return NULL;

    double nyquist = sampleRate / 2.0;
    lowCutoffHz = fmax(1.0, fmin(lowCutoffHz, nyquist - 1.0));
    highCutoffHz = fmax(lowCutoffHz + 1.0, fmin(highCutoffHz, nyquist - 1.0));

    // Compute biquad coefficients for 2-section cascade:
    // Section 0: highpass at lowCutoffHz
    // Section 1: lowpass at highCutoffHz
    // vDSP_biquad expects coefficients as: [b0,b1,b2,a1,a2] per section
    double coeffs[10];
    butterworthHighpass(sampleRate, lowCutoffHz,
                        &coeffs[0], &coeffs[1], &coeffs[2],
                        &coeffs[3], &coeffs[4]);
    butterworthLowpass(sampleRate, highCutoffHz,
                       &coeffs[5], &coeffs[6], &coeffs[7],
                       &coeffs[8], &coeffs[9]);

    // Create biquad setup for 2 sections
    vDSP_biquad_Setup setup = vDSP_biquad_CreateSetup(coeffs, 2);
    if (!setup) return NULL;

    float *output = (float *)calloc(sampleCount, sizeof(float));
    if (!output) {
        vDSP_biquad_DestroySetup(setup);
        return NULL;
    }

    // Delay state: 2 sections * 2 delays + 2 = 4+2 entries (initialized to 0)
    float delays[4 + 2];
    memset(delays, 0, sizeof(delays));

    vDSP_biquad(setup, delays, monoSamples, 1, output, 1, (vDSP_Length)sampleCount);

    vDSP_biquad_DestroySetup(setup);
    return output;
}

@end
