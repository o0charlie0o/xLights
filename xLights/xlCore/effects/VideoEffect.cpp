/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "VideoEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <algorithm>
#include <cmath>

namespace xlCore {

// ============================================================================
// Duration Treatment Parsing
// ============================================================================

VideoDurationTreatment parseVideoDurationTreatment(const std::string& treatment) {
    if (treatment == "Loop") return VideoDurationTreatment::Loop;
    if (treatment == "Slow/Accelerate") return VideoDurationTreatment::SlowAccelerate;
    if (treatment == "Manual") return VideoDurationTreatment::Manual;
    if (treatment == "Manual and Loop") return VideoDurationTreatment::ManualAndLoop;
    return VideoDurationTreatment::Normal;
}

// ============================================================================
// VideoEffect Implementation
// ============================================================================

VideoEffect::VideoEffect() = default;

std::vector<EffectParameter> VideoEffect::parameters() const {
    std::vector<EffectParameter> params;

    // File picker
    auto file = EffectParameter::createFile(
        "E_FILEPICKERCTRL_Video_Filename",
        "Video File",
        "Video files|*.mp4;*.avi;*.mov;*.mkv;*.wmv;*.webm;*.m4v");
    file.group = "Video";
    params.push_back(file);

    // Start time
    auto startTime = EffectParameter::createDouble(
        "E_TEXTCTRL_Video_Starttime", "Start Time (s)", 0.0, 0.0, 3600.0, 0.1);
    startTime.group = "Timing";
    params.push_back(startTime);

    // Duration treatment
    auto duration = EffectParameter::createChoice(
        "E_CHOICE_Video_DurationTreatment",
        "Duration Treatment",
        "Normal",
        {"Normal", "Loop", "Slow/Accelerate", "Manual", "Manual and Loop"});
    duration.group = "Timing";
    params.push_back(duration);

    // Speed (for manual modes)
    auto speed = EffectParameter::createInt(
        "E_SLIDER_Video_Speed", "Speed", 100, SPEED_MIN, SPEED_MAX, true);
    speed.valueCurveDivisor = SPEED_DIVISOR;
    speed.group = "Timing";
    params.push_back(speed);

    // Cropping
    auto cropLeft = EffectParameter::createInt(
        "E_SLIDER_Video_CropLeft", "Crop Left %", 0, CROP_MIN, CROP_MAX, true);
    cropLeft.group = "Crop";
    params.push_back(cropLeft);

    auto cropRight = EffectParameter::createInt(
        "E_SLIDER_Video_CropRight", "Crop Right %", 100, CROP_MIN, CROP_MAX, true);
    cropRight.group = "Crop";
    params.push_back(cropRight);

    auto cropTop = EffectParameter::createInt(
        "E_SLIDER_Video_CropTop", "Crop Top %", 100, CROP_MIN, CROP_MAX, true);
    cropTop.group = "Crop";
    params.push_back(cropTop);

    auto cropBottom = EffectParameter::createInt(
        "E_SLIDER_Video_CropBottom", "Crop Bottom %", 0, CROP_MIN, CROP_MAX, true);
    cropBottom.group = "Crop";
    params.push_back(cropBottom);

    // Aspect ratio
    auto aspectRatio = EffectParameter::createBool(
        "E_CHECKBOX_Video_AspectRatio", "Keep Aspect Ratio", false);
    aspectRatio.group = "Options";
    params.push_back(aspectRatio);

    // Synchronize with audio
    auto syncAudio = EffectParameter::createBool(
        "E_CHECKBOX_SynchroniseWithAudio", "Sync with Audio", false);
    syncAudio.group = "Options";
    params.push_back(syncAudio);

    // Transparent black
    auto transparentBlack = EffectParameter::createBool(
        "E_CHECKBOX_Video_TransparentBlack", "Transparent Black", false);
    transparentBlack.group = "Transparency";
    params.push_back(transparentBlack);

    auto transparentLevel = EffectParameter::createInt(
        "E_TEXTCTRL_Video_TransparentBlack", "Transparent Level", 0, 0, 765);
    transparentLevel.group = "Transparency";
    params.push_back(transparentLevel);

    // Sample spacing (for optimized rendering on large displays)
    auto sampleSpacing = EffectParameter::createInt(
        "E_TEXTCTRL_SampleSpacing", "Sample Spacing", 0, 0, 100);
    sampleSpacing.group = "Options";
    sampleSpacing.description = "Sample pixels from native resolution video (0 = scale video)";
    params.push_back(sampleSpacing);

    return params;
}

std::vector<std::string> VideoEffect::fileReferences(const EffectSettings& settings) const {
    std::vector<std::string> refs;
    std::string file = settings.get("E_FILEPICKERCTRL_Video_Filename");
    if (!file.empty()) {
        refs.push_back(file);
    }
    return refs;
}

void VideoEffect::renderFrame(RenderContext& ctx,
                              const ImageBuffer& frame,
                              int cropLeft, int cropRight,
                              int cropTop, int cropBottom,
                              bool transparentBlack,
                              int transparentBlackLevel,
                              int sampleSpacing) {
    int bufferWi = ctx.width();
    int bufferHt = ctx.height();
    int frameWi = static_cast<int>(frame.width());
    int frameHt = static_cast<int>(frame.height());

    // Calculate crop offsets
    int xOffset = cropLeft * frameWi / 100;
    int yOffset = cropBottom * frameHt / 100;
    int xTail = (100 - cropRight) * frameWi / 100;
    int yTail = (100 - cropTop) * frameHt / 100;

    int croppedWidth = frameWi - xOffset - xTail;
    int croppedHeight = frameHt - yOffset - yTail;

    // Calculate centering offset
    int startX = (bufferWi - croppedWidth) / 2;
    int startY = (bufferHt - croppedHeight) / 2;

    if (sampleSpacing > 0) {
        // Sample mode: pick pixels at intervals from native resolution
        for (int y = 0; y < bufferHt; y++) {
            for (int x = 0; x < bufferWi; x++) {
                int srcX = startX + x * sampleSpacing;
                int srcY = startY + y * sampleSpacing;

                if (srcX >= 0 && srcX < frameWi && srcY >= 0 && srcY < frameHt) {
                    Color c = frame.getPixel(srcX, srcY);

                    if (transparentBlack) {
                        int level = c.red + c.green + c.blue;
                        if (level <= transparentBlackLevel) {
                            continue;
                        }
                    }

                    ctx.setPixel(x, y, c);
                }
            }
        }
    } else {
        // Normal mode: use pre-scaled frame
        for (int y = 0; y < std::min(bufferHt, croppedHeight); y++) {
            for (int x = 0; x < std::min(bufferWi, croppedWidth); x++) {
                int srcX = x + xOffset;
                int srcY = (croppedHeight - 1 - y) + yTail; // Flip Y for xLights coordinate system

                if (srcX >= 0 && srcX < frameWi && srcY >= 0 && srcY < frameHt) {
                    Color c = frame.getPixel(srcX, srcY);

                    if (transparentBlack) {
                        int level = c.red + c.green + c.blue;
                        if (level <= transparentBlackLevel) {
                            continue;
                        }
                    }

                    int destX = x + std::max(0, startX);
                    int destY = y + std::max(0, startY);
                    if (destX < bufferWi && destY < bufferHt) {
                        ctx.setPixel(destX, destY, c);
                    }
                }
            }
        }
    }
}

void VideoEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Initialize cache if needed
    if (!m_cache) {
        m_cache = std::make_unique<VideoRenderCache>();
    }

    // Get parameters
    std::string filename = settings.get("E_FILEPICKERCTRL_Video_Filename");
    double startTime = settings.getDouble("E_TEXTCTRL_Video_Starttime", 0.0);
    std::string durationStr = settings.get("E_CHOICE_Video_DurationTreatment", "Normal");
    double speed = settings.getDouble("E_SLIDER_Video_Speed", 100.0) / SPEED_DIVISOR;

    int cropLeft = settings.getInt("E_SLIDER_Video_CropLeft", 0);
    int cropRight = settings.getInt("E_SLIDER_Video_CropRight", 100);
    int cropTop = settings.getInt("E_SLIDER_Video_CropTop", 100);
    int cropBottom = settings.getInt("E_SLIDER_Video_CropBottom", 0);

    bool aspectRatio = settings.getBool("E_CHECKBOX_Video_AspectRatio", false);
    bool syncAudio = settings.getBool("E_CHECKBOX_SynchroniseWithAudio", false);
    bool transparentBlack = settings.getBool("E_CHECKBOX_Video_TransparentBlack", false);
    int transparentBlackLevel = settings.getInt("E_TEXTCTRL_Video_TransparentBlack", 0);
    int sampleSpacing = settings.getInt("E_TEXTCTRL_SampleSpacing", 0);

    VideoDurationTreatment durationTreatment = parseVideoDurationTreatment(durationStr);

    // Normalize crop values
    if (cropLeft > cropRight) std::swap(cropLeft, cropRight);
    if (cropBottom > cropTop) std::swap(cropTop, cropBottom);
    if (cropLeft == cropRight) {
        if (cropLeft == 0) cropRight++;
        else cropLeft--;
    }
    if (cropBottom == cropTop) {
        if (cropBottom == 0) cropTop++;
        else cropBottom--;
    }

    int bufferWi = state.bufferWidth;
    int bufferHt = state.bufferHeight;

    // Handle empty filename
    if (filename.empty()) {
        ctx.fill(Color::Red());
        return;
    }

    // Handle sync with audio mode
    if (syncAudio) {
        startTime = 0;
        durationTreatment = VideoDurationTreatment::Normal;
        // Note: In actual implementation, the platform layer would need to
        // provide the audio filename through some mechanism
    }

    // Initialize or reinitialize decoder on first frame
    if (state.frameIndex == 0) {
        m_cache->reset();

        if (bufferHt <= 1) {
            // Cannot render video on 1-pixel high model
            ctx.fill(Color::Red());
            return;
        }

        auto decoder = VideoDecoder::create();
        if (decoder) {
            int width = bufferWi * 100 / (cropRight - cropLeft);
            int height = bufferHt * 100 / (cropTop - cropBottom);
            bool useNative = (sampleSpacing > 0);

            if (decoder->open(filename, width, height, aspectRatio, useNative)) {
                m_cache->decoder = std::move(decoder);
                m_cache->currentFile = filename;

                // Calculate frame timing based on duration treatment
                double effectDurationMs = (state.effectEndTime - state.effectStartTime) * 1000.0;
                int effectFrames = static_cast<int>(effectDurationMs / 50.0); // Assume 20fps

                if (durationTreatment == VideoDurationTreatment::SlowAccelerate) {
                    int videoMs = m_cache->decoder->durationMs() - static_cast<int>(startTime * 1000);
                    int videoFrames = videoMs / 50; // Assume 50ms per frame
                    float speedFactor = static_cast<float>(videoFrames) / effectFrames;
                    m_cache->frameMs = static_cast<int>(50 * speedFactor);
                } else {
                    m_cache->frameMs = 50;
                }

                // Seek to start position
                if (startTime > 0) {
                    m_cache->decoder->seekTo(startTime);
                }
            }
        }
    }

    // Check if decoder is ready
    if (!m_cache->decoder || m_cache->decoder->durationMs() == 0) {
        ctx.fill(Color::Red());
        return;
    }

    // Calculate target frame time
    int frameTimeMs = 0;

    switch (durationTreatment) {
        case VideoDurationTreatment::Manual:
            frameTimeMs = static_cast<int>(startTime * 1000) + m_cache->nextManualMs;
            m_cache->nextManualMs += static_cast<int>(speed * m_cache->frameMs);
            break;

        case VideoDurationTreatment::ManualAndLoop: {
            frameTimeMs = static_cast<int>(startTime * 1000) + m_cache->nextManualMs;
            int videoLen = m_cache->decoder->durationMs();

            while (frameTimeMs < 0) frameTimeMs += videoLen;
            while (frameTimeMs > videoLen) frameTimeMs -= videoLen;

            m_cache->nextManualMs += static_cast<int>(speed * m_cache->frameMs);
            break;
        }

        default:
            frameTimeMs = static_cast<int>(startTime * 1000) +
                          (state.frameIndex * m_cache->frameMs) -
                          (m_cache->loops * (m_cache->decoder->durationMs() + m_cache->frameMs));
            break;
    }

    // Get video frame
    auto frame = m_cache->decoder->getFrameAt(frameTimeMs);

    // Handle end of video / looping
    if (!frame || m_cache->decoder->atEnd()) {
        if (durationTreatment == VideoDurationTreatment::Loop) {
            m_cache->loops++;
            frameTimeMs = static_cast<int>(startTime * 1000) +
                          (state.frameIndex * m_cache->frameMs) -
                          (m_cache->loops * (m_cache->decoder->durationMs() + m_cache->frameMs));

            if (frameTimeMs < 0) frameTimeMs = 0;

            m_cache->decoder->seekTo(0);
            frame = m_cache->decoder->getFrameAt(frameTimeMs);
        }
    }

    // Render frame or show indicator
    if (frame && frameTimeMs >= 0) {
        renderFrame(ctx, *frame, cropLeft, cropRight, cropTop, cropBottom,
                    transparentBlack, transparentBlackLevel, sampleSpacing);
    } else if (durationTreatment == VideoDurationTreatment::Normal) {
        // Past end of video - show blue
        ctx.fill(Color::Blue());
    }
    // For loop/manual modes, keep showing last frame when at end
}

// Register the effect
XLCORE_REGISTER_EFFECT(VideoEffect)

} // namespace xlCore
