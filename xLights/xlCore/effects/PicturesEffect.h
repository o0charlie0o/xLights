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
 * @file PicturesEffect.h
 * @brief Picture/image display effect for xlCore.
 *
 * This effect displays images on the model with various movement and
 * scaling options. It supports static images, animated GIFs, and
 * image sequences.
 *
 * Features:
 * - Multiple movement directions (left, right, up, down, diagonal, etc.)
 * - Peekaboo and wiggle animations
 * - Scaling and aspect ratio control
 * - Tiling modes
 * - GIF animation with loop control
 * - Transparent black for background removal
 */

#include "../Effect.h"
#include "../ImageBuffer.h"
#include "../media/ImageLoader.h"

#include <memory>
#include <string>
#include <vector>

namespace xlCore {

/**
 * @brief Movement direction enumeration for pictures effect.
 */
enum class PictureDirection {
    Left = 0,
    Right = 1,
    Up = 2,
    Down = 3,
    None = 4,
    UpLeft = 5,
    DownLeft = 6,
    UpRight = 7,
    DownRight = 8,
    Peekaboo0 = 9,      // From bottom
    Wiggle = 10,
    ZoomIn = 11,
    Peekaboo90 = 12,    // From left
    Peekaboo180 = 13,   // From top
    Peekaboo270 = 14,   // From right
    VixRemap = 15,      // Vixen 2.x channel remap
    FlagWave = 16,
    UpOnce = 17,
    DownOnce = 18,
    Vector = 19,        // Vector movement from start to end position
    TileLeft = 20,
    TileRight = 21,
    TileDown = 22,
    TileUp = 23
};

/**
 * @brief Scaling mode enumeration.
 */
enum class PictureScaling {
    NoScaling,
    ScaleToFit,
    ScaleKeepAspectRatio,
    ScaleKeepAspectRatioCrop
};

/**
 * @brief Convert direction string to enum.
 */
PictureDirection parsePictureDirection(const std::string& dir);

/**
 * @brief Convert scaling string to enum.
 */
PictureScaling parsePictureScaling(const std::string& scaling);

/**
 * @brief Render cache for Pictures effect.
 *
 * Stores loaded images and animation state between frames.
 */
class PicturesRenderCache {
public:
    PicturesRenderCache() = default;
    ~PicturesRenderCache() = default;

    // Current image state
    ImageBuffer image;
    ImageBuffer rawImage;       // Original unscaled image
    std::string currentFile;    // Currently loaded file path

    // Animation state for GIFs
    std::unique_ptr<AnimatedImageDecoder> gifDecoder;
    int frameCount = 0;
    int currentFrame = 0;

    // Movie file sequence state (for -1.jpg style files)
    int maxMovieFrames = 0;
    int movieFrame = 1;

    // EXIF orientation
    ExifOrientation orientation = ExifOrientation::Normal;

    // Vixen remap data (for VixRemap direction)
    struct PixelData {
        int x, y;
        Color color;
    };
    std::vector<std::vector<PixelData>> pixelsByFrame;

    /**
     * @brief Reset cache state.
     */
    void reset() {
        image = ImageBuffer();
        rawImage = ImageBuffer();
        currentFile.clear();
        gifDecoder.reset();
        frameCount = 0;
        currentFrame = 0;
        maxMovieFrames = 0;
        movieFrame = 1;
        orientation = ExifOrientation::Normal;
        pixelsByFrame.clear();
    }
};

/**
 * @brief Pictures/image display effect.
 *
 * This effect displays images with various movement and animation options.
 */
class PicturesEffect : public Effect {
public:
    PicturesEffect();
    ~PicturesEffect() override = default;

    // ========== Identity ==========
    std::string name() const override { return "Pictures"; }
    std::string description() const override { return "Display images with movement and animation"; }
    std::string category() const override { return "Media"; }

    // ========== Rendering ==========
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // ========== Capabilities ==========
    bool canBeRandom() const override { return false; }
    bool supportsRenderCache(const EffectSettings& settings) const override { return true; }

    // ========== Parameters ==========
    std::vector<EffectParameter> parameters() const override;

    // ========== File References ==========
    std::vector<std::string> fileReferences(const EffectSettings& settings) const override;

    // ========== Cloning ==========
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<PicturesEffect>(*this);
    }

    // ========== Static Utilities ==========

    /**
     * @brief Check if a file is a supported picture format.
     */
    static bool isPictureFile(const std::string& path);

private:
    /**
     * @brief Load an image or get from cache.
     */
    bool loadImage(PicturesRenderCache& cache,
                   const std::string& filename,
                   const RenderState& state,
                   float frameRateAdj,
                   bool loopGIF,
                   bool suppressGIFBackground);

    /**
     * @brief Load pixels from a Vixen text file.
     */
    void loadPixelsFromTextFile(PicturesRenderCache& cache,
                                const std::string& filename,
                                int bufferWidth,
                                int bufferHeight);

    /**
     * @brief Render a single pixel with transparent black handling.
     */
    void setTransparentBlackPixel(RenderContext& ctx,
                                  int x, int y,
                                  const Color& c,
                                  bool wrap,
                                  bool transparentBlack,
                                  int transparentBlackLevel);

    /**
     * @brief Scale image according to scaling mode.
     */
    ImageBuffer scaleImage(const ImageBuffer& source,
                           int targetWidth,
                           int targetHeight,
                           PictureScaling scaling);

    // Cache for render state (one per effect instance)
    mutable std::unique_ptr<PicturesRenderCache> m_cache;
};

} // namespace xlCore
