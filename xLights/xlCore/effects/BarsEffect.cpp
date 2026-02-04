/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "BarsEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

// Parameter keys
static const std::string KEY_BAR_COUNT = "E_SLIDER_Bars_BarCount";
static const std::string KEY_CYCLES = "E_SLIDER_Bars_Cycles";
static const std::string KEY_DIRECTION = "E_CHOICE_Bars_Direction";
static const std::string KEY_CENTER = "E_SLIDER_Bars_Center";
static const std::string KEY_HIGHLIGHT = "E_CHECKBOX_Bars_Highlight";
static const std::string KEY_3D = "E_CHECKBOX_Bars_3D";
static const std::string KEY_GRADIENT = "E_CHECKBOX_Bars_Gradient";

std::vector<EffectParameter> BarsEffect::parameters() const {
    return {
        EffectParameter::createInt(KEY_BAR_COUNT, "Bar Count", 1, 1, 100, true),
        EffectParameter::createDouble(KEY_CYCLES, "Cycles", 1.0, 0.1, 100.0, 0.1),
        EffectParameter::createChoice(KEY_DIRECTION, "Direction", "up", {
            "up", "down", "expand", "compress",
            "Left", "Right", "H-expand", "H-compress",
            "Alternate Up", "Alternate Down", "Alternate Left", "Alternate Right"
        }),
        EffectParameter::createInt(KEY_CENTER, "Center", 0, -100, 100, true),
        EffectParameter::createBool(KEY_HIGHLIGHT, "Highlight", false),
        EffectParameter::createBool(KEY_3D, "3D", false),
        EffectParameter::createBool(KEY_GRADIENT, "Gradient", false)
    };
}

BarDirection BarsEffect::parseDirection(const std::string& dirStr) const {
    if (dirStr == "up") return BarDirection::Up;
    if (dirStr == "down") return BarDirection::Down;
    if (dirStr == "expand") return BarDirection::Expand;
    if (dirStr == "compress") return BarDirection::Compress;
    if (dirStr == "Left") return BarDirection::Left;
    if (dirStr == "Right") return BarDirection::Right;
    if (dirStr == "H-expand") return BarDirection::HExpand;
    if (dirStr == "H-compress") return BarDirection::HCompress;
    if (dirStr == "Alternate Up") return BarDirection::AlternateUp;
    if (dirStr == "Alternate Down") return BarDirection::AlternateDown;
    if (dirStr == "Alternate Left") return BarDirection::AlternateLeft;
    if (dirStr == "Alternate Right") return BarDirection::AlternateRight;
    if (dirStr == "Custom Horz") return BarDirection::CustomHorz;
    if (dirStr == "Custom Vert") return BarDirection::CustomVert;
    return BarDirection::Up;
}

Color BarsEffect::blendColors(const Color& c1, const Color& c2, double pct) const {
    pct = std::clamp(pct, 0.0, 1.0);
    return Color(
        static_cast<uint8_t>(c1.red + (c2.red - c1.red) * pct),
        static_cast<uint8_t>(c1.green + (c2.green - c1.green) * pct),
        static_cast<uint8_t>(c1.blue + (c2.blue - c1.blue) * pct)
    );
}

Color BarsEffect::applyEffects(const Color& color, int barHeight, int posInBar,
                                bool highlight, bool show3D, bool allowAlpha,
                                const Color& highlightColor) const {
    Color result = color;

    if (barHeight <= 0) return result;

    // Apply highlight at bar edge
    if (highlight && posInBar == 0) {
        return highlightColor;
    }

    // Apply 3D fading
    if (show3D) {
        int numerator = barHeight - posInBar - 1;
        double fade = static_cast<double>(numerator) / barHeight;

        if (allowAlpha) {
            result = Color(color.red, color.green, color.blue,
                          static_cast<uint8_t>(255.0 * fade));
        } else {
            HSV hsv = color.toHSV();
            hsv.value *= fade;
            result = Color(hsv);
        }
    }

    return result;
}

void BarsEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int barCount = settings.getInt(KEY_BAR_COUNT, 1);
    double cycles = settings.getDouble(KEY_CYCLES, 1.0);
    std::string dirStr = settings.get(KEY_DIRECTION, "up");
    int center = settings.getInt(KEY_CENTER, 0);
    bool highlight = settings.getBool(KEY_HIGHLIGHT, false);
    bool show3D = settings.getBool(KEY_3D, false);
    bool gradient = settings.getBool(KEY_GRADIENT, false);

    BarDirection direction = parseDirection(dirStr);

    int width = ctx.width();
    int height = ctx.height();

    // Default palette (in real implementation, would come from effect settings)
    std::vector<Color> palette = {
        Color::Red(),
        Color::Green(),
        Color::Blue()
    };
    size_t colorCount = palette.size();
    if (colorCount == 0) {
        return;
    }

    Color highlightColor = Color::White();

    // Calculate total bar count
    int totalBarCount = barCount * static_cast<int>(colorCount);
    if (totalBarCount < 1) {
        totalBarCount = 1;
    }

    // Calculate position in animation
    double position = std::fmod(state.progress * cycles, 1.0);

    // Determine if this is a vertical or horizontal bar effect
    bool isVertical = (static_cast<int>(direction) <= 3 ||
                       direction == BarDirection::AlternateUp ||
                       direction == BarDirection::AlternateDown);

    int dim = isVertical ? height : width;
    int barSize = static_cast<int>(std::ceil(static_cast<float>(dim) / totalBarCount));
    if (barSize < 1) barSize = 1;

    int newCenter = isVertical ?
        height * (100 + center) / 200 :
        width * (100 + center) / 200;

    int blockSize = static_cast<int>(colorCount) * barSize;
    if (blockSize < 1) blockSize = 1;

    int offset = static_cast<int>(position * blockSize);

    // Handle alternate directions
    if (direction == BarDirection::AlternateUp || direction == BarDirection::AlternateDown) {
        offset = static_cast<int>(std::floor(position * totalBarCount)) * barSize;
        direction = (direction == BarDirection::AlternateUp) ? BarDirection::Up : BarDirection::Down;
    }
    if (direction == BarDirection::AlternateLeft || direction == BarDirection::AlternateRight) {
        offset = static_cast<int>(std::floor(position * totalBarCount)) * barSize;
        direction = (direction == BarDirection::AlternateLeft) ? BarDirection::Left : BarDirection::Right;
    }

    // Render based on direction
    if (isVertical) {
        // Vertical bars (up, down, expand, compress)
        for (int y = -2 * height; y < 2 * height; y++) {
            int n = height + y + offset;
            int colorIdx = std::abs(n % blockSize) / barSize;
            int nextColorIdx = (colorIdx + 1) % colorCount;
            double pct = static_cast<double>(std::abs(n % barSize)) / barSize;
            int posInBar = std::abs(n % barSize);

            Color color = palette[colorIdx];
            if (gradient) {
                color = blendColors(color, palette[nextColorIdx], pct);
            }

            color = applyEffects(color, barSize, posInBar, highlight, show3D,
                                ctx.allowAlpha(), highlightColor);

            switch (direction) {
                case BarDirection::Down:
                    for (int x = 0; x < width; x++) {
                        ctx.setPixel(x, y, color);
                    }
                    break;

                case BarDirection::Expand:
                    if (y <= newCenter) {
                        for (int x = 0; x < width; x++) {
                            ctx.setPixel(x, y, color);
                            ctx.setPixel(x, newCenter + (newCenter - y), color);
                        }
                    }
                    break;

                case BarDirection::Compress:
                    if (y >= newCenter) {
                        for (int x = 0; x < width; x++) {
                            ctx.setPixel(x, y, color);
                            ctx.setPixel(x, newCenter + (newCenter - y), color);
                        }
                    }
                    break;

                default: // Up
                    for (int x = 0; x < width; x++) {
                        ctx.setPixel(x, height - y - 1, color);
                    }
                    break;
            }
        }
    } else {
        // Horizontal bars (left, right, H-expand, H-compress)
        for (int x = -2 * width; x < 2 * width; x++) {
            int n = width + x + offset;
            int colorIdx = std::abs(n % blockSize) / barSize;
            int nextColorIdx = (colorIdx + 1) % colorCount;
            double pct = static_cast<double>(std::abs(n % barSize)) / barSize;
            int posInBar = std::abs(n % barSize);

            Color color = palette[colorIdx];
            if (gradient) {
                color = blendColors(color, palette[nextColorIdx], pct);
            }

            color = applyEffects(color, barSize, posInBar, highlight, show3D,
                                ctx.allowAlpha(), highlightColor);

            switch (direction) {
                case BarDirection::Right:
                    for (int y = 0; y < height; y++) {
                        ctx.setPixel(width - x - 1, y, color);
                    }
                    break;

                case BarDirection::HExpand:
                    if (x <= newCenter) {
                        for (int y = 0; y < height; y++) {
                            ctx.setPixel(x, y, color);
                            ctx.setPixel(newCenter + (newCenter - x), y, color);
                        }
                    }
                    break;

                case BarDirection::HCompress:
                    if (x >= newCenter) {
                        for (int y = 0; y < height; y++) {
                            ctx.setPixel(x, y, color);
                            ctx.setPixel(newCenter + (newCenter - x), y, color);
                        }
                    }
                    break;

                default: // Left
                    for (int y = 0; y < height; y++) {
                        ctx.setPixel(x, y, color);
                    }
                    break;
            }
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(BarsEffect)

} // namespace xlCore
