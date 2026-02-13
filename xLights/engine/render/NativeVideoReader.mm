/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "NativeVideoReader.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <cmath>

namespace xlEngine {

struct NativeVideoReader::Impl {
    AVAsset* asset = nil;
    AVAssetImageGenerator* imageGenerator = nil;
    double durationSeconds = 0.0;
    int outputWidth = 0;
    int outputHeight = 0;
    int sourceWidth = 0;
    int sourceHeight = 0;
    bool keepAspectRatio = false;
    std::string filePath;

    // Frame cache to avoid re-decoding the same time
    double lastRequestedTime = -1.0;
    std::vector<uint8_t> lastFrame;
};

NativeVideoReader::NativeVideoReader()
    : _impl(std::make_unique<Impl>())
{
}

NativeVideoReader::~NativeVideoReader() {
    close();
}

bool NativeVideoReader::open(const std::string& path, int targetWidth, int targetHeight,
                             bool keepAspectRatio)
{
    @autoreleasepool {
        close();

        if (path.empty() || targetWidth <= 0 || targetHeight <= 0)
            return false;

        NSString* nsPath = [NSString stringWithUTF8String:path.c_str()];
        if (!nsPath) return false;

        NSURL* url = [NSURL fileURLWithPath:nsPath];
        if (!url) return false;

        AVAsset* asset = [AVAsset assetWithURL:url];
        if (!asset) return false;

        // Load tracks synchronously (legacy-style for render pipeline)
        NSArray<AVAssetTrack*>* videoTracks =
            [asset tracksWithMediaType:AVMediaTypeVideo];
        if (videoTracks.count == 0) return false;

        AVAssetTrack* track = videoTracks.firstObject;
        CGSize naturalSize = track.naturalSize;

        if (naturalSize.width <= 0 || naturalSize.height <= 0)
            return false;

        _impl->sourceWidth = static_cast<int>(naturalSize.width);
        _impl->sourceHeight = static_cast<int>(naturalSize.height);
        _impl->keepAspectRatio = keepAspectRatio;

        // Compute output dimensions
        if (keepAspectRatio) {
            double srcAspect = naturalSize.width / naturalSize.height;
            double dstAspect = static_cast<double>(targetWidth) / targetHeight;
            if (srcAspect > dstAspect) {
                _impl->outputWidth = targetWidth;
                _impl->outputHeight = std::max(1, static_cast<int>(targetWidth / srcAspect));
            } else {
                _impl->outputHeight = targetHeight;
                _impl->outputWidth = std::max(1, static_cast<int>(targetHeight * srcAspect));
            }
        } else {
            _impl->outputWidth = targetWidth;
            _impl->outputHeight = targetHeight;
        }

        // Get duration
        CMTime duration = asset.duration;
        if (CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration)) {
            _impl->durationSeconds = CMTimeGetSeconds(duration);
        } else {
            _impl->durationSeconds = 0.0;
        }

        if (_impl->durationSeconds <= 0.0) {
            return false;
        }

        // Create image generator
        AVAssetImageGenerator* generator =
            [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        if (!generator) return false;

        generator.appliesPreferredTrackTransform = YES;
        generator.requestedTimeToleranceBefore = CMTimeMake(1, 30);
        generator.requestedTimeToleranceAfter = CMTimeMake(1, 30);

        // Set maximum output size
        generator.maximumSize = CGSizeMake(_impl->outputWidth, _impl->outputHeight);

        _impl->asset = asset;
        _impl->imageGenerator = generator;
        _impl->filePath = path;
        _impl->lastRequestedTime = -1.0;
        _impl->lastFrame.clear();

        return true;
    }
}

void NativeVideoReader::close() {
    @autoreleasepool {
        _impl->imageGenerator = nil;
        _impl->asset = nil;
        _impl->durationSeconds = 0.0;
        _impl->outputWidth = 0;
        _impl->outputHeight = 0;
        _impl->sourceWidth = 0;
        _impl->sourceHeight = 0;
        _impl->lastRequestedTime = -1.0;
        _impl->lastFrame.clear();
        _impl->filePath.clear();
    }
}

bool NativeVideoReader::isOpen() const {
    return _impl->imageGenerator != nil && _impl->durationSeconds > 0.0;
}

bool NativeVideoReader::getFrameAtTime(double timeSeconds, std::vector<uint8_t>& rgbaPixels) {
    @autoreleasepool {
        if (!isOpen()) return false;

        // Clamp time to valid range
        if (timeSeconds < 0.0) timeSeconds = 0.0;
        if (timeSeconds > _impl->durationSeconds)
            timeSeconds = _impl->durationSeconds;

        // Return cached frame if the time hasn't changed significantly
        // (within half a frame at 60fps ~= 8ms)
        if (_impl->lastRequestedTime >= 0.0 &&
            std::fabs(timeSeconds - _impl->lastRequestedTime) < 0.008 &&
            !_impl->lastFrame.empty()) {
            rgbaPixels = _impl->lastFrame;
            return true;
        }

        CMTime requestTime = CMTimeMakeWithSeconds(timeSeconds, 600);

        // Use the modern async API with a semaphore for synchronous access
        // in the render pipeline (copyCGImageAtTime:actualTime:error: is
        // deprecated in macOS 15+).
        __block CGImageRef cgImage = nullptr;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        [_impl->imageGenerator generateCGImageAsynchronouslyForTime:requestTime
            completionHandler:^(CGImageRef image, CMTime actualTime, NSError* error) {
                if (image) {
                    cgImage = CGImageRetain(image);
                }
                dispatch_semaphore_signal(sem);
            }];

        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

        if (!cgImage) return false;

        int imgWidth = static_cast<int>(CGImageGetWidth(cgImage));
        int imgHeight = static_cast<int>(CGImageGetHeight(cgImage));

        if (imgWidth <= 0 || imgHeight <= 0) {
            CGImageRelease(cgImage);
            return false;
        }

        // Render CGImage into RGBA buffer at the desired output size
        int outW = _impl->outputWidth;
        int outH = _impl->outputHeight;
        size_t bytesPerRow = static_cast<size_t>(outW) * 4;

        rgbaPixels.resize(bytesPerRow * outH);
        std::fill(rgbaPixels.begin(), rgbaPixels.end(), 0);

        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        if (!colorSpace) {
            CGImageRelease(cgImage);
            return false;
        }

        CGContextRef ctx = CGBitmapContextCreate(
            rgbaPixels.data(), outW, outH,
            8, bytesPerRow, colorSpace,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

        if (!ctx) {
            CGColorSpaceRelease(colorSpace);
            CGImageRelease(cgImage);
            return false;
        }

        CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
        CGContextDrawImage(ctx, CGRectMake(0, 0, outW, outH), cgImage);

        CGContextRelease(ctx);
        CGColorSpaceRelease(colorSpace);
        CGImageRelease(cgImage);

        // Un-premultiply alpha
        uint8_t* p = rgbaPixels.data();
        size_t totalPixels = static_cast<size_t>(outW) * outH;
        for (size_t i = 0; i < totalPixels; ++i) {
            uint8_t a = p[3];
            if (a > 0 && a < 255) {
                p[0] = static_cast<uint8_t>(std::min(255, (p[0] * 255 + a / 2) / a));
                p[1] = static_cast<uint8_t>(std::min(255, (p[1] * 255 + a / 2) / a));
                p[2] = static_cast<uint8_t>(std::min(255, (p[2] * 255 + a / 2) / a));
            }
            p += 4;
        }

        // Cache the frame
        _impl->lastRequestedTime = timeSeconds;
        _impl->lastFrame = rgbaPixels;

        return true;
    }
}

double NativeVideoReader::getDuration() const {
    return _impl->durationSeconds;
}

int NativeVideoReader::getDurationMS() const {
    return static_cast<int>(_impl->durationSeconds * 1000.0);
}

int NativeVideoReader::getWidth() const {
    return _impl->outputWidth;
}

int NativeVideoReader::getHeight() const {
    return _impl->outputHeight;
}

bool NativeVideoReader::atEnd(double timeSeconds) const {
    return timeSeconds >= _impl->durationSeconds;
}

} // namespace xlEngine
