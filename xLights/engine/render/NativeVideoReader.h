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

// NativeVideoReader: wx-free video frame extraction for the native macOS
// render pipeline.
//
// Uses AVFoundation (AVAssetImageGenerator) to decode video frames at
// arbitrary timestamps. Replaces the legacy FFmpeg-based VideoReader for
// the native build, providing the same frame-at-time access pattern that
// the Video effect requires.
//
// Thread safety:
//   - Individual NativeVideoReader instances are NOT thread-safe. Each
//     render thread should have its own instance (typically stored in the
//     effect render cache).
//   - Multiple instances may operate concurrently on different threads.
//
// Pixel format: RGBA, 8 bits per component, non-premultiplied alpha.
// Origin: top-left (row 0 is the top of the image).

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace xlEngine {

class NativeVideoReader {
public:
    NativeVideoReader();
    ~NativeVideoReader();

    // Open a video file and prepare for frame extraction.
    // targetWidth/targetHeight specify the desired output dimensions.
    // If keepAspectRatio is true, the output will be scaled to fit within
    // the target dimensions while preserving the source aspect ratio.
    // Returns true on success.
    bool open(const std::string& path, int targetWidth, int targetHeight,
              bool keepAspectRatio = false);

    // Close the video and release all resources.
    void close();

    // Check if a video is currently open and valid.
    bool isOpen() const;

    // Get a video frame at the specified time (in seconds).
    // The RGBA pixel data is written into rgbaPixels (resized as needed).
    // Pixels are in row-major order, top-left origin.
    // Returns true if a frame was successfully decoded.
    bool getFrameAtTime(double timeSeconds, std::vector<uint8_t>& rgbaPixels);

    // Get the total duration of the video in seconds.
    double getDuration() const;

    // Get the total duration of the video in milliseconds.
    int getDurationMS() const;

    // Get the output width (after scaling/aspect ratio adjustment).
    int getWidth() const;

    // Get the output height (after scaling/aspect ratio adjustment).
    int getHeight() const;

    // Check if the requested time is at or past the end of the video.
    bool atEnd(double timeSeconds) const;

private:
    struct Impl;
    std::unique_ptr<Impl> _impl;
};

} // namespace xlEngine
