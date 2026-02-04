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
 * @file ImageLoader.h
 * @brief Abstract image loading interface for xlCore effects.
 *
 * This header defines the platform-independent interface for loading images.
 * The actual implementation is provided by the platform layer (using stb_image,
 * wxImage, CoreGraphics, etc.)
 *
 * Design goals:
 * - Zero wxWidgets dependencies
 * - Support for common image formats (PNG, JPEG, GIF, BMP, WebP)
 * - Support for animated images (GIF)
 * - Thread-safe loading
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
 * @brief Information about an image file.
 */
struct ImageInfo {
    int width = 0;
    int height = 0;
    int channels = 0;       // 1=grayscale, 3=RGB, 4=RGBA
    int frameCount = 1;     // Number of frames (> 1 for animated GIFs)
    bool hasAlpha = false;
    std::string format;     // "png", "jpeg", "gif", "bmp", "webp", etc.
};

/**
 * @brief Information about a single frame in an animated image.
 */
struct AnimatedFrameInfo {
    int index = 0;
    int delayMs = 100;      // Delay before showing next frame
    int disposalMethod = 0; // GIF disposal method
    bool hasLocalPalette = false;
};

/**
 * @brief Abstract interface for loading images.
 *
 * This class defines the interface that platform-specific image loaders must
 * implement. The xlCore effects use this interface to load images without
 * depending on any specific image loading library.
 *
 * Thread safety: All static methods are thread-safe for different files.
 * Loading the same file from multiple threads requires external synchronization.
 *
 * Usage:
 *   // Set the implementation once at startup
 *   ImageLoader::setImplementation(std::make_unique<MyImageLoader>());
 *
 *   // Load an image
 *   auto image = ImageLoader::load("path/to/image.png");
 *   if (image) {
 *       // Use the image
 *   }
 */
class ImageLoader {
public:
    virtual ~ImageLoader() = default;

    // ========== Image Loading ==========

    /**
     * @brief Load an image from file.
     *
     * @param path Path to the image file
     * @return ImageBuffer containing the image data, or empty if load failed
     */
    virtual std::optional<ImageBuffer> load(const std::string& path) = 0;

    /**
     * @brief Load a specific frame from an animated image.
     *
     * @param path Path to the image file
     * @param frameIndex Frame index (0-based)
     * @return ImageBuffer containing the frame, or empty if load failed
     */
    virtual std::optional<ImageBuffer> loadFrame(const std::string& path, int frameIndex) = 0;

    /**
     * @brief Get information about an image without loading it.
     *
     * @param path Path to the image file
     * @return ImageInfo structure, or nullopt if file cannot be read
     */
    virtual std::optional<ImageInfo> getInfo(const std::string& path) = 0;

    /**
     * @brief Get frame count for an image (1 for static, > 1 for animated).
     *
     * @param path Path to the image file
     * @return Number of frames, or 0 if file cannot be read
     */
    virtual int frameCount(const std::string& path) = 0;

    /**
     * @brief Get frame delay in milliseconds for animated images.
     *
     * @param path Path to the image file
     * @param frameIndex Frame index (0-based)
     * @return Delay in milliseconds, or -1 if not applicable
     */
    virtual int frameDelay(const std::string& path, int frameIndex) = 0;

    // ========== Image Manipulation ==========

    /**
     * @brief Scale an image to new dimensions.
     *
     * @param image Source image buffer
     * @param newWidth Target width
     * @param newHeight Target height
     * @return Scaled image buffer
     */
    virtual ImageBuffer scale(const ImageBuffer& image, int newWidth, int newHeight) = 0;

    /**
     * @brief Scale an image maintaining aspect ratio.
     *
     * @param image Source image buffer
     * @param maxWidth Maximum width
     * @param maxHeight Maximum height
     * @return Scaled image buffer (may be smaller than max dimensions)
     */
    virtual ImageBuffer scaleKeepAspect(const ImageBuffer& image, int maxWidth, int maxHeight) = 0;

    /**
     * @brief Rotate an image by a multiple of 90 degrees.
     *
     * @param image Source image buffer
     * @param degrees Rotation in degrees (must be 0, 90, 180, or 270)
     * @return Rotated image buffer
     */
    virtual ImageBuffer rotate(const ImageBuffer& image, int degrees) = 0;

    /**
     * @brief Flip an image horizontally or vertically.
     *
     * @param image Source image buffer
     * @param horizontal If true, flip horizontally; otherwise flip vertically
     * @return Flipped image buffer
     */
    virtual ImageBuffer flip(const ImageBuffer& image, bool horizontal) = 0;

    // ========== Utility Functions ==========

    /**
     * @brief Check if a file is a supported image format.
     *
     * @param path Path to check
     * @return true if the file extension is a supported image format
     */
    virtual bool isImageFile(const std::string& path) const = 0;

    /**
     * @brief Get list of supported file extensions.
     *
     * @return Vector of extensions (without leading dot, lowercase)
     */
    virtual std::vector<std::string> supportedExtensions() const = 0;

    // ========== Singleton Access ==========

    /**
     * @brief Set the global image loader implementation.
     *
     * This must be called once at application startup before any image
     * loading operations are performed.
     */
    static void setImplementation(std::unique_ptr<ImageLoader> impl);

    /**
     * @brief Get the current image loader implementation.
     *
     * @return Pointer to the implementation, or nullptr if not set
     */
    static ImageLoader* instance();

    // ========== Convenience Static Methods ==========

    /**
     * @brief Load an image using the global implementation.
     */
    static std::optional<ImageBuffer> loadImage(const std::string& path) {
        auto* loader = instance();
        return loader ? loader->load(path) : std::nullopt;
    }

    /**
     * @brief Get image info using the global implementation.
     */
    static std::optional<ImageInfo> getImageInfo(const std::string& path) {
        auto* loader = instance();
        return loader ? loader->getInfo(path) : std::nullopt;
    }

    /**
     * @brief Check if file is an image using the global implementation.
     */
    static bool isImage(const std::string& path) {
        auto* loader = instance();
        return loader ? loader->isImageFile(path) : false;
    }

protected:
    ImageLoader() = default;

private:
    static std::unique_ptr<ImageLoader> s_instance;
};

/**
 * @brief Interface for animated image decoding.
 *
 * This interface is used for more efficient handling of animated GIFs
 * where we need to render frames with proper disposal and compositing.
 */
class AnimatedImageDecoder {
public:
    virtual ~AnimatedImageDecoder() = default;

    /**
     * @brief Open an animated image file.
     *
     * @param path Path to the image file
     * @return true if file was opened successfully
     */
    virtual bool open(const std::string& path) = 0;

    /**
     * @brief Close the current file.
     */
    virtual void close() = 0;

    /**
     * @brief Check if a file is open.
     */
    virtual bool isOpen() const = 0;

    /**
     * @brief Get the file path.
     */
    virtual std::string path() const = 0;

    /**
     * @brief Get total frame count.
     */
    virtual int frameCount() const = 0;

    /**
     * @brief Get image width.
     */
    virtual int width() const = 0;

    /**
     * @brief Get image height.
     */
    virtual int height() const = 0;

    /**
     * @brief Get a specific frame.
     *
     * This returns the fully composited frame, handling GIF disposal
     * methods correctly.
     *
     * @param frameIndex Frame index (0-based)
     * @return Frame image buffer, or empty if failed
     */
    virtual std::optional<ImageBuffer> getFrame(int frameIndex) = 0;

    /**
     * @brief Get frame for a specific time in milliseconds.
     *
     * This calculates which frame should be displayed at the given time,
     * based on frame delays.
     *
     * @param timeMs Time in milliseconds from start
     * @param loop If true, loop the animation; otherwise clamp to last frame
     * @return Frame image buffer, or empty if failed
     */
    virtual std::optional<ImageBuffer> getFrameForTime(int timeMs, bool loop = true) = 0;

    /**
     * @brief Get information about a specific frame.
     */
    virtual AnimatedFrameInfo getFrameInfo(int frameIndex) const = 0;

    /**
     * @brief Get total animation duration in milliseconds.
     */
    virtual int totalDuration() const = 0;

    /**
     * @brief Set whether to suppress background color.
     *
     * Some GIFs have a background color that should be made transparent.
     */
    virtual void setSuppressBackground(bool suppress) = 0;

    /**
     * @brief Check if background suppression is enabled.
     */
    virtual bool suppressBackground() const = 0;

    // ========== Factory ==========

    /**
     * @brief Create an animated image decoder.
     *
     * The factory function is set by the platform layer.
     */
    using Factory = std::function<std::unique_ptr<AnimatedImageDecoder>()>;

    static void setFactory(Factory factory);
    static std::unique_ptr<AnimatedImageDecoder> create();

private:
    static Factory s_factory;
};

/**
 * @brief EXIF orientation values.
 */
enum class ExifOrientation {
    Normal = 1,
    FlipHorizontal = 2,
    Rotate180 = 3,
    FlipVertical = 4,
    Transpose = 5,    // Rotate 90 CW + flip horizontal
    Rotate90CW = 6,
    Transverse = 7,   // Rotate 90 CCW + flip horizontal
    Rotate90CCW = 8
};

/**
 * @brief Get EXIF orientation from an image file.
 *
 * @param path Path to the image file
 * @return Orientation value, or Normal if not found
 */
ExifOrientation getExifOrientation(const std::string& path);

/**
 * @brief Apply EXIF orientation to an image.
 *
 * @param image Source image buffer
 * @param orientation Orientation to apply
 * @return Corrected image buffer
 */
ImageBuffer applyExifOrientation(const ImageBuffer& image, ExifOrientation orientation);

} // namespace xlCore
