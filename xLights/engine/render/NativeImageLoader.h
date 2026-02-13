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

// NativeImageLoader: wx-free image loading for the native macOS render pipeline.
//
// Uses macOS ImageIO/CoreGraphics to load images from file paths and return
// raw RGBA pixel data. Replaces wxImage::LoadFile() and wxImage::GetRed/Green/
// Blue/Alpha() for effects that display images (Pictures, Video, Glediator,
// Sketch, etc.).
//
// Thread safety:
//   - NativeImage instances are NOT thread-safe. Each render thread should
//     have its own NativeImage (typically stored in the effect render cache).
//   - The static load methods are thread-safe (they create independent objects).
//
// Supported formats: PNG, JPEG, GIF, BMP, TIFF, HEIC, WebP (all formats
// supported by macOS ImageIO).
//
// Pixel format: RGBA, 8 bits per component, non-premultiplied alpha.
// Origin: top-left (row 0 is the top of the image).
//
// Usage example:
//   auto img = NativeImageLoader::LoadFromFile("/path/to/image.png");
//   if (img.IsOk()) {
//       int w = img.GetWidth();
//       int h = img.GetHeight();
//       xlColor pixel = img.GetPixel(x, y);
//       // Or get raw data for bulk processing:
//       const uint8_t* rgba = img.GetData();
//   }

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "../../Color.h"

namespace xlEngine {

// A loaded image with RGBA pixel data.
// Lightweight value type (data is shared via shared_ptr to allow cheap copies).
class NativeImage {
public:
    NativeImage() = default;

    // Construct with pixel data (takes ownership of the vector).
    NativeImage(int width, int height, std::vector<uint8_t>&& rgbaData);

    // Copy/move semantics (cheap due to shared_ptr).
    NativeImage(const NativeImage&) = default;
    NativeImage(NativeImage&&) noexcept = default;
    NativeImage& operator=(const NativeImage&) = default;
    NativeImage& operator=(NativeImage&&) noexcept = default;

    // Check if the image was loaded successfully.
    bool IsOk() const { return _data && _width > 0 && _height > 0; }

    // Image dimensions.
    int GetWidth() const { return _width; }
    int GetHeight() const { return _height; }

    // Raw RGBA pixel data (width * height * 4 bytes, row-major, top-left origin).
    // Returns nullptr if the image is not valid.
    const uint8_t* GetData() const;

    // Access a single pixel as xlColor. Returns xlBLACK if out of bounds.
    xlColor GetPixel(int x, int y) const;

    // Access individual color components (matching wxImage API surface).
    // Returns 0 if out of bounds.
    uint8_t GetRed(int x, int y) const;
    uint8_t GetGreen(int x, int y) const;
    uint8_t GetBlue(int x, int y) const;
    uint8_t GetAlpha(int x, int y) const;

    // Check if the pixel at (x, y) is fully transparent (alpha == 0).
    bool IsTransparent(int x, int y) const;

    // Check if the image has any non-opaque alpha values.
    bool HasAlpha() const { return _hasAlpha; }

    // Create a scaled copy of this image. Uses high-quality interpolation.
    // Returns an invalid NativeImage if this image is not valid.
    NativeImage Rescale(int newWidth, int newHeight) const;

private:
    int _width = 0;
    int _height = 0;
    bool _hasAlpha = false;
    std::shared_ptr<std::vector<uint8_t>> _data;
};

// Static image loading utilities.
class NativeImageLoader {
public:
    // Load an image from a file path.
    // Supports PNG, JPEG, GIF (first frame only), BMP, TIFF, HEIC, WebP.
    // Returns an invalid NativeImage (IsOk() == false) on failure.
    static NativeImage LoadFromFile(const std::string& filePath);

    // Load a specific frame from an animated image (GIF).
    // frameIndex is 0-based. Returns invalid NativeImage on failure.
    static NativeImage LoadFrameFromFile(const std::string& filePath, int frameIndex);

    // Get the number of frames in an image file (1 for static images, >1 for GIFs).
    // Returns 0 on failure.
    static int GetFrameCount(const std::string& filePath);

    // Load raw binary data from a file (for Glediator .gled files, etc.).
    // Returns an empty vector on failure.
    static std::vector<uint8_t> LoadBinaryFile(const std::string& filePath);

    // Load binary data from a file with a maximum size limit.
    // Returns an empty vector on failure or if the file exceeds maxBytes.
    static std::vector<uint8_t> LoadBinaryFile(const std::string& filePath, size_t maxBytes);

private:
    NativeImageLoader() = delete;
};

} // namespace xlEngine
