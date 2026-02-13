/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "NativeImageLoader.h"

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

#include <fstream>

namespace xlEngine {

// =========================================================================
// NativeImage
// =========================================================================

NativeImage::NativeImage(int width, int height, std::vector<uint8_t>&& rgbaData)
    : _width(width)
    , _height(height)
    , _data(std::make_shared<std::vector<uint8_t>>(std::move(rgbaData)))
{
    // Scan for non-opaque alpha values
    _hasAlpha = false;
    const uint8_t* p = _data->data();
    size_t pixelCount = static_cast<size_t>(_width) * _height;
    for (size_t i = 0; i < pixelCount; ++i) {
        if (p[i * 4 + 3] != 255) {
            _hasAlpha = true;
            break;
        }
    }
}

const uint8_t* NativeImage::GetData() const {
    return _data ? _data->data() : nullptr;
}

xlColor NativeImage::GetPixel(int x, int y) const {
    if (!_data || x < 0 || x >= _width || y < 0 || y >= _height) {
        return xlBLACK;
    }
    size_t offset = (static_cast<size_t>(y) * _width + x) * 4;
    const uint8_t* p = _data->data() + offset;
    return xlColor(p[0], p[1], p[2], p[3]);
}

uint8_t NativeImage::GetRed(int x, int y) const {
    if (!_data || x < 0 || x >= _width || y < 0 || y >= _height) return 0;
    return (*_data)[(static_cast<size_t>(y) * _width + x) * 4];
}

uint8_t NativeImage::GetGreen(int x, int y) const {
    if (!_data || x < 0 || x >= _width || y < 0 || y >= _height) return 0;
    return (*_data)[(static_cast<size_t>(y) * _width + x) * 4 + 1];
}

uint8_t NativeImage::GetBlue(int x, int y) const {
    if (!_data || x < 0 || x >= _width || y < 0 || y >= _height) return 0;
    return (*_data)[(static_cast<size_t>(y) * _width + x) * 4 + 2];
}

uint8_t NativeImage::GetAlpha(int x, int y) const {
    if (!_data || x < 0 || x >= _width || y < 0 || y >= _height) return 0;
    return (*_data)[(static_cast<size_t>(y) * _width + x) * 4 + 3];
}

bool NativeImage::IsTransparent(int x, int y) const {
    return GetAlpha(x, y) == 0;
}

NativeImage NativeImage::Rescale(int newWidth, int newHeight) const {
    if (!IsOk() || newWidth <= 0 || newHeight <= 0) {
        return NativeImage();
    }

    // Create a CGBitmapContext with the target dimensions
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) return NativeImage();

    size_t bytesPerRow = static_cast<size_t>(newWidth) * 4;
    std::vector<uint8_t> destData(bytesPerRow * newHeight, 0);

    CGContextRef ctx = CGBitmapContextCreate(
        destData.data(), newWidth, newHeight,
        8, bytesPerRow, colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

    if (!ctx) {
        CGColorSpaceRelease(colorSpace);
        return NativeImage();
    }

    // Set high-quality interpolation
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);

    // Create a CGImage from the source data
    CGDataProviderRef provider = CGDataProviderCreateWithData(
        nullptr, _data->data(), _data->size(), nullptr);

    CGImageRef srcImage = CGImageCreate(
        _width, _height,
        8, 32, static_cast<size_t>(_width) * 4,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
        provider, nullptr, false, kCGRenderingIntentDefault);

    if (srcImage) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, newWidth, newHeight), srcImage);
        CGImageRelease(srcImage);
    }

    CGDataProviderRelease(provider);
    CGContextRelease(ctx);
    CGColorSpaceRelease(colorSpace);

    // Un-premultiply alpha in the destination buffer.
    // CGContext renders with premultiplied alpha, but we store
    // non-premultiplied to match the format LoadFromFile returns.
    uint8_t* dp = destData.data();
    size_t totalPixels = static_cast<size_t>(newWidth) * newHeight;
    for (size_t i = 0; i < totalPixels; ++i) {
        uint8_t a = dp[3];
        if (a > 0 && a < 255) {
            dp[0] = static_cast<uint8_t>(std::min(255, (dp[0] * 255 + a / 2) / a));
            dp[1] = static_cast<uint8_t>(std::min(255, (dp[1] * 255 + a / 2) / a));
            dp[2] = static_cast<uint8_t>(std::min(255, (dp[2] * 255 + a / 2) / a));
        }
        dp += 4;
    }

    return NativeImage(newWidth, newHeight, std::move(destData));
}

// =========================================================================
// NativeImageLoader — static helpers
// =========================================================================

// Internal helper: create a CGImageSource from a file path.
static CGImageSourceRef CreateImageSourceFromPath(const std::string& filePath) {
    @autoreleasepool {
        NSString* nsPath = [NSString stringWithUTF8String:filePath.c_str()];
        if (!nsPath) return nullptr;

        NSURL* url = [NSURL fileURLWithPath:nsPath];
        if (!url) return nullptr;

        return CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
    }
}

// Internal helper: render a CGImage into an RGBA buffer (non-premultiplied).
static NativeImage RenderCGImageToNativeImage(CGImageRef cgImage) {
    if (!cgImage) return NativeImage();

    int width = static_cast<int>(CGImageGetWidth(cgImage));
    int height = static_cast<int>(CGImageGetHeight(cgImage));
    if (width <= 0 || height <= 0) return NativeImage();

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) return NativeImage();

    size_t bytesPerRow = static_cast<size_t>(width) * 4;
    std::vector<uint8_t> pixelData(bytesPerRow * height, 0);

    // Render into a bitmap context with premultiplied alpha (required by CG).
    CGContextRef ctx = CGBitmapContextCreate(
        pixelData.data(), width, height,
        8, bytesPerRow, colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

    if (!ctx) {
        CGColorSpaceRelease(colorSpace);
        return NativeImage();
    }

    // Clear to transparent black before drawing
    CGContextClearRect(ctx, CGRectMake(0, 0, width, height));
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cgImage);

    CGContextRelease(ctx);
    CGColorSpaceRelease(colorSpace);

    // Un-premultiply alpha so callers get straight (non-premultiplied) RGBA.
    // This matches what wxImage provides.
    uint8_t* p = pixelData.data();
    size_t totalPixels = static_cast<size_t>(width) * height;
    for (size_t i = 0; i < totalPixels; ++i) {
        uint8_t a = p[3];
        if (a > 0 && a < 255) {
            p[0] = static_cast<uint8_t>(std::min(255, (p[0] * 255 + a / 2) / a));
            p[1] = static_cast<uint8_t>(std::min(255, (p[1] * 255 + a / 2) / a));
            p[2] = static_cast<uint8_t>(std::min(255, (p[2] * 255 + a / 2) / a));
        }
        p += 4;
    }

    return NativeImage(width, height, std::move(pixelData));
}

// =========================================================================
// NativeImageLoader — public API
// =========================================================================

NativeImage NativeImageLoader::LoadFromFile(const std::string& filePath) {
    return LoadFrameFromFile(filePath, 0);
}

NativeImage NativeImageLoader::LoadFrameFromFile(const std::string& filePath, int frameIndex) {
    @autoreleasepool {
        CGImageSourceRef source = CreateImageSourceFromPath(filePath);
        if (!source) return NativeImage();

        size_t count = CGImageSourceGetCount(source);
        if (frameIndex < 0 || static_cast<size_t>(frameIndex) >= count) {
            CFRelease(source);
            return NativeImage();
        }

        CGImageRef cgImage = CGImageSourceCreateImageAtIndex(
            source, static_cast<size_t>(frameIndex), nullptr);
        CFRelease(source);

        if (!cgImage) return NativeImage();

        NativeImage result = RenderCGImageToNativeImage(cgImage);
        CGImageRelease(cgImage);
        return result;
    }
}

int NativeImageLoader::GetFrameCount(const std::string& filePath) {
    @autoreleasepool {
        CGImageSourceRef source = CreateImageSourceFromPath(filePath);
        if (!source) return 0;

        size_t count = CGImageSourceGetCount(source);
        CFRelease(source);
        return static_cast<int>(count);
    }
}

std::vector<uint8_t> NativeImageLoader::LoadBinaryFile(const std::string& filePath) {
    return LoadBinaryFile(filePath, 0);
}

std::vector<uint8_t> NativeImageLoader::LoadBinaryFile(const std::string& filePath, size_t maxBytes) {
    std::ifstream file(filePath, std::ios::binary | std::ios::ate);
    if (!file.is_open()) return {};

    std::streamsize fileSize = file.tellg();
    if (fileSize <= 0) return {};

    if (maxBytes > 0 && static_cast<size_t>(fileSize) > maxBytes) {
        return {};
    }

    file.seekg(0, std::ios::beg);
    std::vector<uint8_t> data(static_cast<size_t>(fileSize));

    if (!file.read(reinterpret_cast<char*>(data.data()), fileSize)) {
        return {};
    }

    return data;
}

} // namespace xlEngine
