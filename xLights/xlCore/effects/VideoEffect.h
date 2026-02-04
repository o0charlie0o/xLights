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
 * @file VideoEffect.h
 * @brief Video playback effect for xlCore.
 *
 * This effect displays video content on the model with various
 * playback options including cropping, scaling, and duration treatment.
 *
 * Features:
 * - Video playback with FFmpeg backend (via VideoDecoder interface)
 * - Cropping from all edges
 * - Aspect ratio preservation
 * - Looping and speed control
 * - Transparent black for green screen removal
 * - Sample spacing for optimized rendering
 */

#include "../Effect.h"
#include "../media/VideoDecoder.h"

#include <memory>
#include <string>

namespace xlCore {

/**
 * @brief Duration treatment options for video effects.
 */
enum class VideoDurationTreatment {
    Normal,         // Play at normal speed, stop at end
    Loop,           // Loop when video ends
    SlowAccelerate, // Adjust speed to match effect duration
    Manual,         // Manual speed control
    ManualAndLoop   // Manual speed control with looping
};

/**
 * @brief Parse duration treatment string.
 */
VideoDurationTreatment parseVideoDurationTreatment(const std::string& treatment);

/**
 * @brief Render cache for Video effect.
 */
class VideoRenderCache {
public:
    VideoRenderCache() = default;
    ~VideoRenderCache() = default;

    std::unique_ptr<VideoDecoder> decoder;
    std::string currentFile;
    int loops = 0;
    int frameMs = 50;       // Frame duration for timing calculations
    int nextManualMs = 0;   // For manual mode tracking

    void reset() {
        decoder.reset();
        currentFile.clear();
        loops = 0;
        frameMs = 50;
        nextManualMs = 0;
    }
};

/**
 * @brief Video playback effect.
 */
class VideoEffect : public Effect {
public:
    VideoEffect();
    ~VideoEffect() override = default;

    // ========== Identity ==========
    std::string name() const override { return "Video"; }
    std::string description() const override { return "Play video content on model"; }
    std::string category() const override { return "Media"; }

    // ========== Rendering ==========
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // ========== Capabilities ==========
    bool canBeRandom() const override { return false; }
    bool appropriateOnNodes() const override { return false; }
    bool supportsRenderCache(const EffectSettings& settings) const override { return true; }

    // ========== Parameters ==========
    std::vector<EffectParameter> parameters() const override;

    // ========== File References ==========
    std::vector<std::string> fileReferences(const EffectSettings& settings) const override;

    // ========== Cloning ==========
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<VideoEffect>(*this);
    }

    // ========== Constants ==========
    static constexpr int SPEED_MIN = -1000;
    static constexpr int SPEED_MAX = 1000;
    static constexpr int SPEED_DIVISOR = 100;
    static constexpr int CROP_MIN = 0;
    static constexpr int CROP_MAX = 100;

private:
    /**
     * @brief Render video frame to context.
     */
    void renderFrame(RenderContext& ctx,
                     const ImageBuffer& frame,
                     int cropLeft, int cropRight,
                     int cropTop, int cropBottom,
                     bool transparentBlack,
                     int transparentBlackLevel,
                     int sampleSpacing);

    mutable std::unique_ptr<VideoRenderCache> m_cache;
};

} // namespace xlCore
