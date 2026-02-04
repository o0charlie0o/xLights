/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "MorphEffect.h"
#include "../RenderContext.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

// Auto-register this effect
XLCORE_REGISTER_EFFECT(MorphEffect)

MorphEffect::MorphEffect() = default;

std::vector<EffectParameter> MorphEffect::parameters() const {
    return {
        // Start position (line 1)
        {"E_SLIDER_Morph_Start_X1", EffectParameterType::Integer, 0, "Start X1", 0, 100},
        {"E_SLIDER_Morph_Start_Y1", EffectParameterType::Integer, 0, "Start Y1", 0, 100},
        {"E_SLIDER_Morph_Start_X2", EffectParameterType::Integer, 100, "Start X2", 0, 100},
        {"E_SLIDER_Morph_Start_Y2", EffectParameterType::Integer, 100, "Start Y2", 0, 100},

        // End position (line 2)
        {"E_SLIDER_Morph_End_X1", EffectParameterType::Integer, 100, "End X1", 0, 100},
        {"E_SLIDER_Morph_End_Y1", EffectParameterType::Integer, 0, "End Y1", 0, 100},
        {"E_SLIDER_Morph_End_X2", EffectParameterType::Integer, 0, "End X2", 0, 100},
        {"E_SLIDER_Morph_End_Y2", EffectParameterType::Integer, 100, "End Y2", 0, 100},

        // Timing
        {"E_SLIDER_MorphDuration", EffectParameterType::Integer, 20, "Head Duration %", 0, 100},
        {"E_SLIDER_MorphAccel", EffectParameterType::Integer, 0, "Acceleration", -10, 10},

        // Repeat/stagger for fill effects
        {"E_CHECKBOX_Morph_Repeat", EffectParameterType::Boolean, false, "Repeat"},
        {"E_SLIDER_Morph_Repeat_Count", EffectParameterType::Integer, 1, "Repeat Count", 1, 100},
        {"E_SLIDER_Morph_Repeat_Skip", EffectParameterType::Integer, 1, "Repeat Skip", 1, 100},
        {"E_SLIDER_Morph_Stagger", EffectParameterType::Integer, 0, "Stagger %", -100, 100},

        // Options
        {"E_CHECKBOX_ShowHeadAtStart", EffectParameterType::Boolean, false, "Show Head at Start"},
        {"E_CHECKBOX_Morph_Start_Link", EffectParameterType::Boolean, false, "Link Start Points"},
        {"E_CHECKBOX_Morph_End_Link", EffectParameterType::Boolean, false, "Link End Points"},

        // Quick set presets
        {"E_CHOICE_Morph_QuickSet", EffectParameterType::Choice, "None", "Quick Set",
         {"None", "Wipe Left", "Wipe Right", "Wipe Up", "Wipe Down",
          "Diagonal Wipe TL-BR", "Diagonal Wipe TR-BL",
          "Curtain Open", "Curtain Close", "Bow Tie",
          "Diamond", "Stacked Wipe Left", "Stacked Wipe Right"}}
    };
}

std::unique_ptr<Effect> MorphEffect::clone() const {
    return std::make_unique<MorphEffect>();
}

void MorphEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    int bufferWi = ctx.bufferWidth();
    int bufferHt = ctx.bufferHeight();

    if (bufferWi == 0 || bufferHt == 0) return;

    // Get start line coordinates (percentages)
    int startX1 = settings.getInt("E_SLIDER_Morph_Start_X1", 0);
    int startY1 = settings.getInt("E_SLIDER_Morph_Start_Y1", 0);
    int startX2 = settings.getInt("E_SLIDER_Morph_Start_X2", 100);
    int startY2 = settings.getInt("E_SLIDER_Morph_Start_Y2", 100);

    // Get end line coordinates (percentages)
    int endX1 = settings.getInt("E_SLIDER_Morph_End_X1", 100);
    int endY1 = settings.getInt("E_SLIDER_Morph_End_Y1", 0);
    int endX2 = settings.getInt("E_SLIDER_Morph_End_X2", 0);
    int endY2 = settings.getInt("E_SLIDER_Morph_End_Y2", 100);

    // Handle linked points
    if (settings.getBool("E_CHECKBOX_Morph_Start_Link", false)) {
        startX2 = startX1;
        startY2 = startY1;
    }
    if (settings.getBool("E_CHECKBOX_Morph_End_Link", false)) {
        endX2 = endX1;
        endY2 = endY1;
    }

    // Timing parameters
    int headDuration = settings.getInt("E_SLIDER_MorphDuration", 20);
    int acceleration = settings.getInt("E_SLIDER_MorphAccel", 0);
    bool showHeadAtStart = settings.getBool("E_CHECKBOX_ShowHeadAtStart", false);

    // Repeat parameters
    bool repeat = settings.getBool("E_CHECKBOX_Morph_Repeat", false);
    int repeatCount = settings.getInt("E_SLIDER_Morph_Repeat_Count", 1);
    int repeatSkip = settings.getInt("E_SLIDER_Morph_Repeat_Skip", 1);
    int stagger = settings.getInt("E_SLIDER_Morph_Stagger", 0);

    // Get colors from palette
    Color headColor = state.palette.getColor(0);
    Color tailColor = state.palette.size() > 1 ? state.palette.getColor(1) : headColor;

    // Calculate head and tail durations
    double headDurationRatio = headDuration / 100.0;
    double tailDurationRatio = 1.0 - headDurationRatio;

    // Calculate progress (0.0 to 1.0)
    double baseProgress = state.progress;

    // Apply acceleration
    double progress = applyAcceleration(baseProgress, acceleration);

    // Calculate head and tail progress
    // Head leads, tail follows
    double headProgress, tailProgress;

    if (showHeadAtStart) {
        // Head visible from start
        headProgress = progress;
        tailProgress = std::max(0.0, (progress - headDurationRatio) / tailDurationRatio);
    } else {
        // Head progresses through full range
        headProgress = std::min(1.0, progress / headDurationRatio);
        tailProgress = std::max(0.0, (progress - headDurationRatio) / tailDurationRatio);
    }

    // Clamp values
    headProgress = std::clamp(headProgress, 0.0, 1.0);
    tailProgress = std::clamp(tailProgress, 0.0, 1.0);

    // Convert percentage coordinates to buffer coordinates
    auto toBufferCoord = [&](int pctX, int pctY, int& bufX, int& bufY) {
        bufX = calcPosition(pctX, bufferWi);
        bufY = calcPosition(pctY, bufferHt);
    };

    // Render morphs (possibly repeated)
    int numMorphs = repeat ? repeatCount : 1;

    for (int morphIdx = 0; morphIdx < numMorphs; morphIdx++) {
        // Calculate stagger offset for this morph
        double staggerOffset = 0.0;
        if (repeat && stagger != 0 && numMorphs > 1) {
            staggerOffset = (stagger / 100.0) * morphIdx / (numMorphs - 1);
        }

        // Adjust progress for stagger
        double morphHeadProgress = std::clamp(headProgress - staggerOffset, 0.0, 1.0);
        double morphTailProgress = std::clamp(tailProgress - staggerOffset, 0.0, 1.0);

        // Calculate skip offset for repeated morphs
        int skipOffset = morphIdx * repeatSkip;

        // Calculate current head line position (interpolated between start and end)
        int headX1 = static_cast<int>(startX1 + (endX1 - startX1) * morphHeadProgress);
        int headY1 = static_cast<int>(startY1 + (endY1 - startY1) * morphHeadProgress);
        int headX2 = static_cast<int>(startX2 + (endX2 - startX2) * morphHeadProgress);
        int headY2 = static_cast<int>(startY2 + (endY2 - startY2) * morphHeadProgress);

        // Calculate current tail line position
        int tailX1 = static_cast<int>(startX1 + (endX1 - startX1) * morphTailProgress);
        int tailY1 = static_cast<int>(startY1 + (endY1 - startY1) * morphTailProgress);
        int tailX2 = static_cast<int>(startX2 + (endX2 - startX2) * morphTailProgress);
        int tailY2 = static_cast<int>(startY2 + (endY2 - startY2) * morphTailProgress);

        // Convert to buffer coordinates
        int bufHeadX1, bufHeadY1, bufHeadX2, bufHeadY2;
        int bufTailX1, bufTailY1, bufTailX2, bufTailY2;

        toBufferCoord(headX1, headY1, bufHeadX1, bufHeadY1);
        toBufferCoord(headX2, headY2, bufHeadX2, bufHeadY2);
        toBufferCoord(tailX1, tailY1, bufTailX1, bufTailY1);
        toBufferCoord(tailX2, tailY2, bufTailX2, bufTailY2);

        // Apply skip offset for vertical positioning in repeated morphs
        if (repeat && skipOffset > 0) {
            bufHeadY1 += skipOffset;
            bufHeadY2 += skipOffset;
            bufTailY1 += skipOffset;
            bufTailY2 += skipOffset;
        }

        // Get points along head and tail lines using Bresenham
        std::vector<int> headVx, headVy;
        std::vector<int> tailVx, tailVy;

        storeLine(bufHeadX1, bufHeadY1, bufHeadX2, bufHeadY2, headVx, headVy);
        storeLine(bufTailX1, bufTailY1, bufTailX2, bufTailY2, tailVx, tailVy);

        // Ensure both lines have same number of points for interpolation
        size_t numPoints = std::max(headVx.size(), tailVx.size());
        if (numPoints == 0) continue;

        // Draw filled region between tail and head
        for (size_t i = 0; i < numPoints; i++) {
            // Interpolate along both lines
            size_t headIdx = std::min(i, headVx.size() - 1);
            size_t tailIdx = std::min(i, tailVx.size() - 1);

            int hx = headVx[headIdx];
            int hy = headVy[headIdx];
            int tx = tailVx[tailIdx];
            int ty = tailVy[tailIdx];

            // Draw line from tail point to head point
            std::vector<int> lineVx, lineVy;
            storeLine(tx, ty, hx, hy, lineVx, lineVy);

            for (size_t j = 0; j < lineVx.size(); j++) {
                int x = lineVx[j];
                int y = lineVy[j];

                // Check bounds
                if (x < 0 || x >= bufferWi || y < 0 || y >= bufferHt) continue;

                // Calculate color blend based on position along the morph
                double blendRatio = lineVx.size() > 1 ? static_cast<double>(j) / (lineVx.size() - 1) : 0.5;
                Color pixelColor = blendColors(tailColor, headColor, blendRatio);

                ctx.setPixel(x, y, pixelColor);
            }
        }
    }
}

void MorphEffect::storeLine(int x0, int y0, int x1, int y1,
                            std::vector<int>& vx, std::vector<int>& vy) const {
    // Bresenham's line algorithm
    vx.clear();
    vy.clear();

    int dx = std::abs(x1 - x0);
    int dy = std::abs(y1 - y0);
    int sx = (x0 < x1) ? 1 : -1;
    int sy = (y0 < y1) ? 1 : -1;
    int err = dx - dy;

    int x = x0;
    int y = y0;

    while (true) {
        vx.push_back(x);
        vy.push_back(y);

        if (x == x1 && y == y1) break;

        int e2 = 2 * err;
        if (e2 > -dy) {
            err -= dy;
            x += sx;
        }
        if (e2 < dx) {
            err += dx;
            y += sy;
        }
    }
}

int MorphEffect::calcPosition(int value, int base) const {
    // Convert percentage (0-100) to buffer coordinate (0 to base-1)
    return static_cast<int>((value / 100.0) * (base - 1));
}

double MorphEffect::applyAcceleration(double progress, int acceleration) const {
    if (acceleration == 0) {
        return progress;
    }

    // acceleration ranges from -10 to 10
    // negative: ease in (slow start, fast end)
    // positive: ease out (fast start, slow end)

    double factor = 1.0 + std::abs(acceleration) / 5.0;

    if (acceleration > 0) {
        // Ease out: fast start, slow end
        return 1.0 - std::pow(1.0 - progress, factor);
    } else {
        // Ease in: slow start, fast end
        return std::pow(progress, factor);
    }
}

Color MorphEffect::blendColors(const Color& c1, const Color& c2, double ratio) const {
    // Linear interpolation between two colors
    ratio = std::clamp(ratio, 0.0, 1.0);

    uint8_t r = static_cast<uint8_t>(c1.red() + (c2.red() - c1.red()) * ratio);
    uint8_t g = static_cast<uint8_t>(c1.green() + (c2.green() - c1.green()) * ratio);
    uint8_t b = static_cast<uint8_t>(c1.blue() + (c2.blue() - c1.blue()) * ratio);

    return Color(r, g, b);
}

} // namespace xlCore
