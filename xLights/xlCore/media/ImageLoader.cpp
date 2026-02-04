/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "ImageLoader.h"

namespace xlCore {

// Static member initialization
std::unique_ptr<ImageLoader> ImageLoader::s_instance = nullptr;
AnimatedImageDecoder::Factory AnimatedImageDecoder::s_factory = nullptr;

void ImageLoader::setImplementation(std::unique_ptr<ImageLoader> impl) {
    s_instance = std::move(impl);
}

ImageLoader* ImageLoader::instance() {
    return s_instance.get();
}

void AnimatedImageDecoder::setFactory(Factory factory) {
    s_factory = std::move(factory);
}

std::unique_ptr<AnimatedImageDecoder> AnimatedImageDecoder::create() {
    if (s_factory) {
        return s_factory();
    }
    return nullptr;
}

ExifOrientation getExifOrientation(const std::string& path) {
    // This is a stub implementation. The platform layer should override
    // ImageLoader with proper EXIF reading capability.
    // For now, return Normal (no rotation).
    return ExifOrientation::Normal;
}

ImageBuffer applyExifOrientation(const ImageBuffer& image, ExifOrientation orientation) {
    auto* loader = ImageLoader::instance();
    if (!loader) {
        return image; // No loader, return unchanged
    }

    switch (orientation) {
        case ExifOrientation::Normal:
            return image;

        case ExifOrientation::FlipHorizontal:
            return loader->flip(image, true);

        case ExifOrientation::Rotate180:
            return loader->rotate(image, 180);

        case ExifOrientation::FlipVertical:
            return loader->flip(image, false);

        case ExifOrientation::Transpose: {
            // Rotate 90 CW + flip horizontal
            auto rotated = loader->rotate(image, 90);
            return loader->flip(rotated, true);
        }

        case ExifOrientation::Rotate90CW:
            return loader->rotate(image, 90);

        case ExifOrientation::Transverse: {
            // Rotate 90 CCW + flip horizontal
            auto rotated = loader->rotate(image, 270);
            return loader->flip(rotated, true);
        }

        case ExifOrientation::Rotate90CCW:
            return loader->rotate(image, 270);

        default:
            return image;
    }
}

} // namespace xlCore
