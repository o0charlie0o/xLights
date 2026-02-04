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

/**
 * @file VideoDecoder.h
 * @brief Abstract video decoding interface for xlCore effects.
 *
 * This header defines the platform-independent interface for video decoding.
 * The actual implementation is provided by the platform layer (typically FFmpeg).
 *
 * Design goals:
 * - Zero wxWidgets dependencies
 * - Efficient seeking and frame extraction
 * - Support for common video formats
 * - Thread-safe for different decoder instances
 */

#include <string>
#include <vector>
#include <memory>
#include <optional>
#include <functional>
#include <cstdint>

#include "../ImageBuffer.h"

namespace xlCore {

/**
 * @brief Information about a video file.
 */
struct VideoInfo {
    int width = 0;
    int height = 0;
    double duration = 0.0;      // Duration in seconds
    double frameRate = 0.0;     // Frames per second
    int frameCount = 0;         // Total frames (estimated)
    int bitRate = 0;            // Bit rate in bits/second
    std::string codec;          // Video codec name
    std::string format;         // Container format
    bool hasAudio = false;      // Has audio track
};

/**
 * @brief Abstract interface for video decoding.
 *
 * This class defines the interface that platform-specific video decoders
 * must implement. Each instance handles one video file.
 *
 * Thread safety: Individual instances are NOT thread-safe.
 * Different instances can be used from different threads.
 *
 * Usage:
 *   auto decoder = VideoDecoder::create();
 *   if (decoder->open("path/to/video.mp4", 1920, 1080, true)) {
 *       // Seek to position
 *       decoder->seekTo(5.0); // 5 seconds
 *
 *       // Get frames
 *       while (auto frame = decoder->decodeFrame()) {
 *           // Process frame
 *       }
 *   }
 */
class VideoDecoder {
public:
    virtual ~VideoDecoder() = default;

    // ========== File Operations ==========

    /**
     * @brief Open a video file.
     *
     * @param path Path to the video file
     * @param targetWidth Target width for decoded frames (0 = native)
     * @param targetHeight Target height for decoded frames (0 = native)
     * @param keepAspectRatio If true, maintain aspect ratio during scaling
     * @param useNativeResolution If true, ignore target dimensions and use native
     * @return true if file was opened successfully
     */
    virtual bool open(const std::string& path,
                      int targetWidth = 0,
                      int targetHeight = 0,
                      bool keepAspectRatio = true,
                      bool useNativeResolution = false) = 0;

    /**
     * @brief Close the current video file.
     */
    virtual void close() = 0;

    /**
     * @brief Check if a video file is open.
     */
    virtual bool isOpen() const = 0;

    /**
     * @brief Get the path of the currently open file.
     */
    virtual std::string path() const = 0;

    // ========== Video Properties ==========

    /**
     * @brief Get video information.
     *
     * @return VideoInfo structure
     */
    virtual VideoInfo info() const = 0;

    /**
     * @brief Get native video width.
     */
    virtual int nativeWidth() const = 0;

    /**
     * @brief Get native video height.
     */
    virtual int nativeHeight() const = 0;

    /**
     * @brief Get output frame width (after scaling).
     */
    virtual int width() const = 0;

    /**
     * @brief Get output frame height (after scaling).
     */
    virtual int height() const = 0;

    /**
     * @brief Get video duration in seconds.
     */
    virtual double duration() const = 0;

    /**
     * @brief Get video duration in milliseconds.
     */
    virtual int durationMs() const = 0;

    /**
     * @brief Get video frame rate.
     */
    virtual double frameRate() const = 0;

    /**
     * @brief Get number of pixel channels (3 for RGB, 4 for RGBA).
     */
    virtual int pixelChannels() const = 0;

    // ========== Seeking and Decoding ==========

    /**
     * @brief Seek to a position in the video.
     *
     * @param timeSeconds Position in seconds
     * @return true if seek was successful
     */
    virtual bool seekTo(double timeSeconds) = 0;

    /**
     * @brief Seek to a position in milliseconds.
     *
     * @param timeMs Position in milliseconds
     * @return true if seek was successful
     */
    virtual bool seekToMs(int timeMs) = 0;

    /**
     * @brief Decode and return the next frame.
     *
     * @return Frame image buffer, or empty if no more frames
     */
    virtual std::optional<ImageBuffer> decodeFrame() = 0;

    /**
     * @brief Get frame at a specific time.
     *
     * This combines seeking and decoding for convenience.
     *
     * @param timeMs Time in milliseconds
     * @return Frame image buffer, or empty if failed
     */
    virtual std::optional<ImageBuffer> getFrameAt(int timeMs) = 0;

    /**
     * @brief Get current playback position in milliseconds.
     */
    virtual int currentPositionMs() const = 0;

    /**
     * @brief Check if we've reached the end of the video.
     */
    virtual bool atEnd() const = 0;

    // ========== Advanced Operations ==========

    /**
     * @brief Set target output dimensions.
     *
     * This allows changing the output size without reopening the file.
     *
     * @param width Target width
     * @param height Target height
     * @param keepAspectRatio If true, maintain aspect ratio
     */
    virtual void setTargetSize(int width, int height, bool keepAspectRatio = true) = 0;

    /**
     * @brief Get raw frame data pointer.
     *
     * For performance-critical code, this returns a pointer to the internal
     * frame buffer. The pointer is valid until the next decode operation.
     *
     * @return Pointer to raw frame data, or nullptr if no frame available
     */
    virtual const uint8_t* rawFrameData() const = 0;

    /**
     * @brief Get raw frame data size in bytes.
     */
    virtual size_t rawFrameDataSize() const = 0;

    // ========== Factory ==========

    /**
     * @brief Create a video decoder.
     *
     * The factory function is set by the platform layer.
     */
    using Factory = std::function<std::unique_ptr<VideoDecoder>()>;

    static void setFactory(Factory factory);
    static std::unique_ptr<VideoDecoder> create();

    // ========== Utility Functions ==========

    /**
     * @brief Check if a file is a supported video format.
     *
     * @param path Path to check
     * @return true if the file extension is a supported video format
     */
    static bool isVideoFile(const std::string& path);

    /**
     * @brief Get list of supported video file extensions.
     *
     * @return Vector of extensions (without leading dot, lowercase)
     */
    static std::vector<std::string> supportedExtensions();

protected:
    VideoDecoder() = default;

private:
    static Factory s_factory;
};

/**
 * @brief Render cache for video effects.
 *
 * This class provides caching for video frames to avoid redundant decoding
 * when the same frame is rendered multiple times.
 */
class VideoFrameCache {
public:
    VideoFrameCache(size_t maxFrames = 10);
    ~VideoFrameCache() = default;

    /**
     * @brief Get a cached frame, or nullptr if not cached.
     *
     * @param timeMs Frame time in milliseconds
     * @param tolerance Time tolerance for cache hit (default 0)
     * @return Cached frame, or nullptr if not found
     */
    const ImageBuffer* get(int timeMs, int tolerance = 0) const;

    /**
     * @brief Add a frame to the cache.
     *
     * @param timeMs Frame time in milliseconds
     * @param frame Frame image buffer
     */
    void put(int timeMs, ImageBuffer frame);

    /**
     * @brief Clear all cached frames.
     */
    void clear();

    /**
     * @brief Set maximum number of cached frames.
     */
    void setMaxFrames(size_t maxFrames);

    /**
     * @brief Get current number of cached frames.
     */
    size_t size() const { return m_frames.size(); }

private:
    struct CachedFrame {
        int timeMs;
        ImageBuffer frame;
    };

    std::vector<CachedFrame> m_frames;
    size_t m_maxFrames;
};

} // namespace xlCore
