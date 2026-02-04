/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "SingleStrandEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../XLMath.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

std::vector<EffectParameter> SingleStrandEffect::parameters() const {
    return {
        EffectParameter::createChoice(
            "E_NOTEBOOK_SSEFFECT_TYPE",
            "Effect Type",
            "Chase",
            {"Chase", "Skips"}
        ),
        // Chase parameters
        EffectParameter::createInt(
            "E_SLIDER_Number_Chases",
            "Number of Chases",
            1, SINGLESTRAND_CHASES_MIN, SINGLESTRAND_CHASES_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Color_Mix1",
            "Chase Size",
            10, SINGLESTRAND_COLOURMIX_MIN, SINGLESTRAND_COLOURMIX_MAX,
            true
        ),
        EffectParameter::createChoice(
            "E_CHOICE_Chase_Type1",
            "Chase Type",
            "Left-Right",
            {"Left-Right", "Right-Left", "Bounce from Left", "Bounce from Right",
             "Dual Chase", "From Middle", "To Middle", "Bounce to Middle", "Bounce from Middle"}
        ),
        EffectParameter::createFloat(
            "E_SLIDER_Chase_Rotations",
            "Rotations",
            1.0f, 0.1f, 50.0f,
            true
        ),
        EffectParameter::createFloat(
            "E_SLIDER_Chase_Offset",
            "Offset",
            0.0f, -500.0f, 500.0f,
            true
        ),
        EffectParameter::createChoice(
            "E_CHOICE_Fade_Type",
            "Fade Type",
            "None",
            {"None", "From Head", "From Tail", "Head and Tail", "Middle"}
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_Chase_Group_All",
            "Group All",
            false
        ),
        // Skips parameters
        EffectParameter::createInt(
            "E_SLIDER_Skips_BandSize",
            "Band Size",
            1, SINGLESTRAND_BANDSIZE_MIN, SINGLESTRAND_BANDSIZE_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Skips_SkipSize",
            "Skip Size",
            1, SINGLESTRAND_SKIPSIZE_MIN, SINGLESTRAND_SKIPSIZE_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Skips_StartPos",
            "Start Position",
            1, 1, 100,
            true
        ),
        EffectParameter::createChoice(
            "E_CHOICE_Skips_Direction",
            "Direction",
            "Left",
            {"Left", "Right", "From Middle", "To Middle"}
        ),
        EffectParameter::createInt(
            "E_SLIDER_Skips_Advance",
            "Advance",
            0, 0, 100,
            true
        )
    };
}

SingleStrandEffect::ChaseType SingleStrandEffect::parseChaseType(const std::string& type) {
    if (type == "Left-Right") return ChaseType::LeftRight;
    if (type == "Right-Left") return ChaseType::RightLeft;
    if (type == "Bounce from Left") return ChaseType::BounceFromLeft;
    if (type == "Bounce from Right") return ChaseType::BounceFromRight;
    if (type == "Dual Chase") return ChaseType::DualChase;
    if (type == "From Middle") return ChaseType::FromMiddle;
    if (type == "To Middle") return ChaseType::ToMiddle;
    if (type == "Bounce to Middle") return ChaseType::BounceToMiddle;
    if (type == "Bounce from Middle") return ChaseType::BounceFromMiddle;
    return ChaseType::LeftRight;
}

void SingleStrandEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    std::string effectType = settings.getString("E_NOTEBOOK_SSEFFECT_TYPE", "Chase");

    if (effectType == "Skips") {
        renderSkips(ctx, settings, state);
    } else {
        renderChase(ctx, settings, state);
    }
}

void SingleStrandEffect::renderChase(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int numChases = settings.getInt("E_SLIDER_Number_Chases", 1);
    int chaseSize = settings.getInt("E_SLIDER_Color_Mix1", 10);
    std::string chaseTypeStr = settings.getString("E_CHOICE_Chase_Type1", "Left-Right");
    float rotations = settings.getFloat("E_SLIDER_Chase_Rotations", 1.0f);
    float offset = settings.getFloat("E_SLIDER_Chase_Offset", 0.0f);
    std::string fadeType = settings.getString("E_CHOICE_Fade_Type", "None");
    bool groupAll = settings.getBool("E_CHECKBOX_Chase_Group_All", false);

    ChaseType chaseType = parseChaseType(chaseTypeStr);

    // Default colors
    std::vector<Color> colors = { Color::Red(), Color::Green(), Color::Blue() };
    size_t colorCount = colors.size();

    int width = groupAll ? (ctx.width() * ctx.height()) : ctx.width();

    bool mirror = (chaseType == ChaseType::FromMiddle || chaseType == ChaseType::ToMiddle);
    bool autoReverse = (chaseType == ChaseType::BounceFromLeft || chaseType == ChaseType::BounceFromRight ||
                        chaseType == ChaseType::BounceToMiddle || chaseType == ChaseType::BounceFromMiddle);
    bool dualChase = (chaseType == ChaseType::DualChase || chaseType == ChaseType::BounceToMiddle ||
                      chaseType == ChaseType::BounceFromMiddle);
    bool reverseDir = (chaseType == ChaseType::RightLeft || chaseType == ChaseType::BounceFromRight ||
                       chaseType == ChaseType::FromMiddle);

    if (mirror) {
        width = (width + 1) / 2;
    }
    if (width == 0) width = 1;

    // Calculate scaled chase width
    int scaledChaseWidth = static_cast<int>(width * chaseSize / 100.0f);
    if (scaledChaseWidth < 1) scaledChaseWidth = 1;

    // Calculate position based on time
    float progress = state.progress();
    float rtval = progress * rotations + (offset / 100.0f);

    // Normalize to 0-1 range
    while (rtval > 1.0f) rtval -= 1.0f;
    while (rtval < 0.0f) rtval += 1.0f;

    if (autoReverse) {
        rtval *= 2.0f;
    }

    // Calculate chase spacing
    if (numChases < 1) numChases = 1;
    float dx = static_cast<float>(width) / static_cast<float>(numChases);
    if (dx < 1.0f) dx = 1.0f;

    // Calculate starting position
    int startState;
    if (numChases > 1) {
        startState = static_cast<int>(width * rtval + 1);
    } else {
        startState = static_cast<int>((width + scaledChaseWidth - 1) * rtval + 1);
    }

    // Draw each chase
    for (int chase = 0; chase < numChases; chase++) {
        int x;
        if (autoReverse) {
            x = static_cast<int>(chase * dx + width * rtval - scaledChaseWidth / 2.0f);
        } else {
            x = static_cast<int>(chase * dx + startState - scaledChaseWidth);
        }

        drawChase(ctx, x, width, scaledChaseWidth, fadeType, reverseDir, mirror, colors);

        if (dualChase) {
            drawChase(ctx, x, width, scaledChaseWidth, fadeType, !reverseDir, mirror, colors);
        }
    }
}

void SingleStrandEffect::drawChase(RenderContext& ctx, int x, int width, int chaseWidth,
                                    const std::string& fadeType, bool reverse, bool mirror,
                                    const std::vector<Color>& colors) {
    size_t colorCount = colors.size();
    if (colorCount == 0) return;

    for (int i = 0; i < chaseWidth; i++) {
        int newX = x + i;

        // Handle wrapping for multiple chases
        while (newX < 0) newX += width;
        while (newX >= width) newX -= width;

        if (reverse) {
            newX = width - newX - 1;
        }

        // Get color for this position
        int colorIdx = static_cast<int>((chaseWidth - i) * colorCount / chaseWidth);
        if (colorIdx >= static_cast<int>(colorCount)) colorIdx = static_cast<int>(colorCount) - 1;
        if (colorIdx < 0) colorIdx = 0;
        Color color = colors[colorIdx];

        // Apply fade
        float fade = 1.0f;
        if (fadeType == "From Head") {
            fade = static_cast<float>(i + 1) / static_cast<float>(chaseWidth);
        } else if (fadeType == "From Tail") {
            fade = static_cast<float>(chaseWidth - i) / static_cast<float>(chaseWidth);
        } else if (fadeType == "Head and Tail" || fadeType == "Middle") {
            int middle = chaseWidth / 2;
            if (fadeType == "Head and Tail") {
                if (i <= middle) {
                    fade = 1.0f - static_cast<float>(i) / static_cast<float>(middle);
                } else {
                    fade = static_cast<float>(i - middle) / static_cast<float>(chaseWidth - middle);
                }
            } else {
                if (i <= middle) {
                    fade = static_cast<float>(i) / static_cast<float>(middle);
                } else {
                    fade = 1.0f - static_cast<float>(i - middle) / static_cast<float>(chaseWidth - middle);
                }
            }
        }

        // Apply fade to color
        color = Color(
            static_cast<uint8_t>(color.red * fade),
            static_cast<uint8_t>(color.green * fade),
            static_cast<uint8_t>(color.blue * fade)
        );

        // Draw the pixel
        if (newX >= 0 && newX < ctx.width()) {
            for (int y = 0; y < ctx.height(); y++) {
                ctx.setPixel(newX, y, color);
            }
            if (mirror && (ctx.width() - newX - 1) >= 0) {
                for (int y = 0; y < ctx.height(); y++) {
                    ctx.setPixel(ctx.width() - newX - 1, y, color);
                }
            }
        }
    }
}

void SingleStrandEffect::renderSkips(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int bandSize = settings.getInt("E_SLIDER_Skips_BandSize", 1);
    int skipSize = settings.getInt("E_SLIDER_Skips_SkipSize", 1);
    int startPos = settings.getInt("E_SLIDER_Skips_StartPos", 1);
    std::string direction = settings.getString("E_CHOICE_Skips_Direction", "Left");
    int advance = settings.getInt("E_SLIDER_Skips_Advance", 0);

    // Default colors
    std::vector<Color> colors = { Color::Red(), Color::Green(), Color::Blue() };
    size_t colorCount = colors.size();
    if (colorCount == 0) return;

    // Map direction
    int dir = 0;
    if (direction == "Left") dir = 1;
    else if (direction == "Right") dir = 0;
    else if (direction == "From Middle") dir = 2;
    else if (direction == "To Middle") dir = 3;

    int max = ctx.width();
    if (dir > 1) {
        max = (max + 1) / 2;
    }

    // Calculate animation position
    float progress = state.progress();
    int animOffset = static_cast<int>(progress * (advance + 1.0f) * 0.99f) * bandSize;

    int x = startPos - 1 + animOffset;
    while (x > max) {
        x -= (bandSize + skipSize) * static_cast<int>(colorCount);
    }

    int colorIdx = 0;

    // Draw forward from start
    while (x < max) {
        Color color = colors[colorIdx];
        colorIdx = (colorIdx + 1) % colorCount;

        for (int cnt = 0; cnt < bandSize && x < max; cnt++) {
            int drawX = x;
            int mirrorX = -1;

            // Map X based on direction
            if (dir == 1) {
                drawX = max - x - 1;
            } else if (dir == 2) {
                mirrorX = max + x;
                drawX = max - x - 1;
            } else if (dir == 3) {
                mirrorX = max * 2 - x - 1;
            }

            if (drawX >= 0 && drawX < ctx.width()) {
                for (int y = 0; y < ctx.height(); y++) {
                    ctx.setPixel(drawX, y, color);
                }
            }
            if (mirrorX >= 0 && mirrorX < ctx.width()) {
                for (int y = 0; y < ctx.height(); y++) {
                    ctx.setPixel(mirrorX, y, color);
                }
            }
            x++;
        }
        x += skipSize;
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(SingleStrandEffect)

} // namespace xlCore
