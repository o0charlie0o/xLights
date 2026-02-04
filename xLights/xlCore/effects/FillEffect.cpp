/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "FillEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <algorithm>
#include <cmath>

namespace xlCore {

std::vector<EffectParameter> FillEffect::parameters() const {
    return {
        EffectParameter::createInt(
            "E_SLIDER_Fill_Position",
            "Position",
            100, FILL_POSITION_MIN, FILL_POSITION_MAX,
            true  // Supports value curve
        ),
        EffectParameter::createChoice(
            "E_CHOICE_Fill_Direction",
            "Direction",
            "Up",
            {"Up", "Down", "Left", "Right"}
        ),
        EffectParameter::createInt(
            "E_SLIDER_Fill_Band_Size",
            "Band Size",
            0, FILL_BANDSIZE_MIN, FILL_BANDSIZE_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Fill_Skip_Size",
            "Skip Size",
            0, FILL_SKIPSIZE_MIN, FILL_SKIPSIZE_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Fill_Offset",
            "Offset",
            0, FILL_OFFSET_MIN, FILL_OFFSET_MAX,
            true
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_Fill_Offset_In_Pixels",
            "Offset in Pixels",
            true
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_Fill_Color_Time",
            "Color by Time",
            false
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_Fill_Wrap",
            "Wrap",
            true
        )
    };
}

FillEffect::FillDirection FillEffect::parseDirection(const std::string& dir) {
    if (dir == "Down") return FillDirection::Down;
    if (dir == "Left") return FillDirection::Left;
    if (dir == "Right") return FillDirection::Right;
    return FillDirection::Up;
}

Color FillEffect::getColorFromPosition(double pos, const std::vector<Color>& colors) const {
    if (colors.empty()) return Color::White();
    if (colors.size() == 1) return colors[0];

    double colorVal = pos * (colors.size() - 1);
    int colorInt = static_cast<int>(colorVal);
    double colorPct = colorVal - static_cast<double>(colorInt);
    int color2 = std::min(colorInt + 1, static_cast<int>(colors.size()) - 1);

    if (colorInt < color2) {
        // Blend between two colors
        const Color& c1 = colors[colorInt];
        const Color& c2 = colors[color2];
        return Color(
            static_cast<uint8_t>(c1.red + (c2.red - c1.red) * colorPct),
            static_cast<uint8_t>(c1.green + (c2.green - c1.green) * colorPct),
            static_cast<uint8_t>(c1.blue + (c2.blue - c1.blue) * colorPct)
        );
    } else {
        return colors[color2];
    }
}

void FillEffect::updateFillColor(int& position, int& bandColor, int colorCount, int colorSize, int shift) const {
    if (shift == 0) return;

    if (shift > 0) {
        int index = 0;
        while (index < shift) {
            position++;
            if (position >= colorSize) {
                bandColor++;
                bandColor %= colorCount;
                position = 0;
            }
            index++;
        }
    } else {
        int index = 0;
        while (index > shift) {
            position--;
            if (position < 0) {
                bandColor++;
                bandColor %= colorCount;
                position = colorSize - 1;
            }
            index--;
        }
    }
}

void FillEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int position = settings.getInt("E_SLIDER_Fill_Position", 100);
    std::string directionStr = settings.get("E_CHOICE_Fill_Direction", "Up");
    int bandSize = settings.getInt("E_SLIDER_Fill_Band_Size", 0);
    int skipSize = settings.getInt("E_SLIDER_Fill_Skip_Size", 0);
    int offset = settings.getInt("E_SLIDER_Fill_Offset", 0);
    bool offsetInPixels = settings.getBool("E_CHECKBOX_Fill_Offset_In_Pixels", true);
    bool colorByTime = settings.getBool("E_CHECKBOX_Fill_Color_Time", false);
    bool wrap = settings.getBool("E_CHECKBOX_Fill_Wrap", true);

    FillDirection direction = parseDirection(directionStr);
    double posPct = static_cast<double>(position) / 100.0;

    // Default color palette (real implementation would get from effect palette)
    std::vector<Color> colors = { Color::White() };
    size_t colorCount = colors.size();

    // Adjust offset based on direction and units
    switch (direction) {
        case FillDirection::Up:
        case FillDirection::Down:
            if (!offsetInPixels) {
                offset = ((ctx.height() - 1) * offset) / 100;
            } else {
                offset %= ctx.height();
            }
            break;
        case FillDirection::Left:
        case FillDirection::Right:
            if (!offsetInPixels) {
                offset = ((ctx.width() - 1) * offset) / 100;
            } else {
                offset %= ctx.width();
            }
            break;
    }

    int colorSize = bandSize + skipSize;
    int currentColor = 0;
    int currentPos = 0;
    int target;

    Color color;
    if (bandSize == 0) {
        color = getColorFromPosition(state.progress, colors);
    }

    switch (direction) {
        case FillDirection::Up: {
            offset %= ctx.height();
            if (wrap) {
                target = static_cast<int>(ctx.height() * posPct + offset);
            } else {
                target = offset + static_cast<int>((ctx.height() - offset) * posPct);
            }
            for (int y = offset; y < target; y++) {
                if (bandSize > 0) {
                    color = Color::Black();
                    if (currentPos < bandSize) {
                        color = colors[currentColor % colorCount];
                    }
                }
                int yPos = y;
                if (yPos >= ctx.height()) yPos -= ctx.height();
                if (!colorByTime) {
                    double pos = 0;
                    if (ctx.height() + offset - 1 != 0) {
                        pos = static_cast<double>(y) / static_cast<double>(ctx.height() + offset - 1);
                    }
                    color = getColorFromPosition(pos, colors);
                }
                for (int x = 0; x < ctx.width(); x++) {
                    ctx.setPixel(x, yPos, color);
                }
                if (bandSize > 0) {
                    updateFillColor(currentPos, currentColor, colorCount, colorSize, 1);
                }
            }
            break;
        }

        case FillDirection::Down: {
            offset %= ctx.height();
            if (wrap) {
                target = static_cast<int>(ctx.height() * (1.0 - posPct) - offset);
            } else {
                target = static_cast<int>((ctx.height() - offset) * (1.0 - posPct));
            }
            for (int y = ctx.height() - 1 - offset; y >= target; y--) {
                if (bandSize > 0) {
                    color = Color::Black();
                    if (currentPos < bandSize) {
                        color = colors[currentColor % colorCount];
                    }
                }
                int yPos = y;
                if (yPos < 0) yPos += ctx.height();
                if (!colorByTime) {
                    double pos = 1.0;
                    if (ctx.height() + offset - 1 != 0) {
                        pos = 1.0 - static_cast<double>(y) / static_cast<double>(ctx.height() + offset - 1);
                    }
                    color = getColorFromPosition(pos, colors);
                }
                for (int x = 0; x < ctx.width(); x++) {
                    ctx.setPixel(x, yPos, color);
                }
                if (bandSize > 0) {
                    updateFillColor(currentPos, currentColor, colorCount, colorSize, 1);
                }
            }
            break;
        }

        case FillDirection::Left: {
            offset %= ctx.width();
            if (wrap) {
                target = static_cast<int>(ctx.width() * (1.0 - posPct) - offset);
            } else {
                target = static_cast<int>((ctx.width() - offset) * (1.0 - posPct));
            }
            for (int x = ctx.width() - 1 - offset; x >= target; x--) {
                if (bandSize > 0) {
                    color = Color::Black();
                    if (currentPos < bandSize) {
                        color = colors[currentColor % colorCount];
                    }
                }
                int xPos = x;
                if (xPos < 0) xPos += ctx.width();
                if (!colorByTime) {
                    double pos = 1.0;
                    if (ctx.width() + offset - 1 != 0) {
                        pos = 1.0 - static_cast<double>(x) / static_cast<double>(ctx.width() + offset - 1);
                    }
                    color = getColorFromPosition(pos, colors);
                }
                for (int y = 0; y < ctx.height(); y++) {
                    ctx.setPixel(xPos, y, color);
                }
                if (bandSize > 0) {
                    updateFillColor(currentPos, currentColor, colorCount, colorSize, 1);
                }
            }
            break;
        }

        case FillDirection::Right: {
            offset %= ctx.width();
            if (wrap) {
                target = static_cast<int>(ctx.width() * posPct + offset);
            } else {
                target = offset + static_cast<int>((ctx.width() - offset) * posPct);
            }
            for (int x = offset; x < target; x++) {
                if (bandSize > 0) {
                    color = Color::Black();
                    if (currentPos < bandSize) {
                        color = colors[currentColor % colorCount];
                    }
                }
                int xPos = x;
                if (xPos >= ctx.width()) xPos -= ctx.width();
                if (!colorByTime) {
                    double pos = 0;
                    if (ctx.width() + offset - 1 != 0) {
                        pos = static_cast<double>(x) / static_cast<double>(ctx.width() + offset - 1);
                    }
                    color = getColorFromPosition(pos, colors);
                }
                for (int y = 0; y < ctx.height(); y++) {
                    ctx.setPixel(xPos, y, color);
                }
                if (bandSize > 0) {
                    updateFillColor(currentPos, currentColor, colorCount, colorSize, 1);
                }
            }
            break;
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(FillEffect)

} // namespace xlCore
