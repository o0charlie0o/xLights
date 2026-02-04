/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLAudioLoader.h"
#import <AVFoundation/AVFoundation.h>

#pragma mark - XLAudioSampleData

@implementation XLAudioSampleData {
    float *_samples;
}

- (instancetype)initWithSamples:(float *)samples
                    sampleCount:(NSUInteger)sampleCount
                   channelCount:(NSUInteger)channelCount
                     sampleRate:(double)sampleRate
{
    self = [super init];
    if (self) {
        _samples = samples;
        _sampleCount = sampleCount;
        _channelCount = channelCount;
        _sampleRate = sampleRate;
        _duration = (sampleRate > 0) ? (double)sampleCount / sampleRate : 0;
    }
    return self;
}

- (void)dealloc {
    if (_samples) {
        free(_samples);
        _samples = NULL;
    }
}

- (float *)samples {
    return _samples;
}

@end

#pragma mark - XLAudioLoader

@implementation XLAudioLoader

+ (XLAudioSampleData *)loadAudioFile:(NSString *)path {
    if (!path || path.length == 0) {
        NSLog(@"XLAudioLoader: empty path provided");
        return nil;
    }

    NSURL *fileURL = [NSURL fileURLWithPath:path];
    NSError *error = nil;

    AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:fileURL error:&error];
    if (!audioFile) {
        NSLog(@"XLAudioLoader: failed to open audio file '%@': %@", path, error.localizedDescription);
        return nil;
    }

    // Use the file's processing format (non-interleaved Float32) - this is what AVAudioFile expects
    // Requesting interleaved format causes error -50 on some files
    AVAudioFormat *processingFormat = audioFile.processingFormat;

    AVAudioFrameCount frameCount = (AVAudioFrameCount)audioFile.length;
    if (frameCount == 0) {
        NSLog(@"XLAudioLoader: audio file has zero frames: '%@'", path);
        return nil;
    }

    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                                             frameCapacity:frameCount];
    if (!buffer) {
        NSLog(@"XLAudioLoader: failed to allocate PCM buffer for '%@'", path);
        return nil;
    }

    if (![audioFile readIntoBuffer:buffer error:&error]) {
        NSLog(@"XLAudioLoader: failed to read audio data from '%@': %@", path, error.localizedDescription);
        return nil;
    }

    NSUInteger channelCount = processingFormat.channelCount;
    NSUInteger readFrames = buffer.frameLength;
    NSUInteger totalSamples = readFrames * channelCount;

    float *samples = (float *)malloc(totalSamples * sizeof(float));
    if (!samples) {
        NSLog(@"XLAudioLoader: failed to allocate sample buffer (%lu samples)", (unsigned long)totalSamples);
        return nil;
    }

    if (processingFormat.isInterleaved) {
        // Interleaved: copy directly
        const float *src = buffer.floatChannelData[0];
        memcpy(samples, src, totalSamples * sizeof(float));
    } else {
        // Non-interleaved (typical case): convert to interleaved for our processing
        for (NSUInteger ch = 0; ch < channelCount; ch++) {
            const float *channelData = buffer.floatChannelData[ch];
            for (NSUInteger i = 0; i < readFrames; i++) {
                samples[i * channelCount + ch] = channelData[i];
            }
        }
    }

    XLAudioSampleData *audioData = [[XLAudioSampleData alloc]
        initWithSamples:samples
            sampleCount:readFrames
           channelCount:channelCount
             sampleRate:processingFormat.sampleRate];

    NSLog(@"XLAudioLoader: loaded '%@' — %lu frames, %lu channels, %.0f Hz, %.2f sec",
          path.lastPathComponent, (unsigned long)readFrames, (unsigned long)channelCount,
          processingFormat.sampleRate, audioData.duration);

    return audioData;
}

+ (NSArray<NSValue *> *)generateWaveformOverview:(XLAudioSampleData *)audioData
                                     bucketCount:(NSUInteger)bucketCount
{
    if (!audioData || audioData.sampleCount == 0 || bucketCount == 0) {
        return @[];
    }

    NSUInteger sampleCount = audioData.sampleCount;
    NSUInteger channelCount = audioData.channelCount;
    const float *samples = audioData.samples;
    double samplesPerBucket = (double)sampleCount / (double)bucketCount;

    NSMutableArray<NSValue *> *buckets = [NSMutableArray arrayWithCapacity:bucketCount];

    for (NSUInteger b = 0; b < bucketCount; b++) {
        NSUInteger startFrame = (NSUInteger)(b * samplesPerBucket);
        NSUInteger endFrame = (NSUInteger)((b + 1) * samplesPerBucket);
        if (endFrame > sampleCount) endFrame = sampleCount;
        if (startFrame >= sampleCount) startFrame = sampleCount - 1;

        float minL = 1.0f, maxL = -1.0f;
        float minR = 1.0f, maxR = -1.0f;

        for (NSUInteger i = startFrame; i < endFrame; i++) {
            float left = samples[i * channelCount];
            if (left < minL) minL = left;
            if (left > maxL) maxL = left;

            if (channelCount >= 2) {
                float right = samples[i * channelCount + 1];
                if (right < minR) minR = right;
                if (right > maxR) maxR = right;
            }
        }

        // For mono, duplicate left channel to right
        if (channelCount < 2) {
            minR = minL;
            maxR = maxL;
        }

        XLWaveformBucket bucket = { minL, maxL, minR, maxR };
        NSValue *val = [NSValue valueWithBytes:&bucket objCType:@encode(XLWaveformBucket)];
        [buckets addObject:val];
    }

    return [buckets copy];
}

@end
