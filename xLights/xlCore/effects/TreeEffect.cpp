/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "TreeEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../Math.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

std::vector<EffectParameter> TreeEffect::parameters() const {
    return {
        EffectParameter::createInt("E_SLIDER_Tree_Branches", "Branches", 3,
            TREE_BRANCHES_MIN, TREE_BRANCHES_MAX),
        EffectParameter::createInt("E_SLIDER_Tree_Speed", "Speed", 10,
            TREE_SPEED_MIN, TREE_SPEED_MAX),
        EffectParameter::createBool("E_CHECKBOX_Tree_ShowLights", "Show Lights", true)
    };
}

void TreeEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    int branches = settings.getInt("E_SLIDER_Tree_Branches", 3);
    int tspeed = settings.getInt("E_SLIDER_Tree_Speed", 10);
    bool showLights = settings.getBool("E_CHECKBOX_Tree_ShowLights", true);

    int bufferWi = ctx.width();
    int bufferHt = ctx.height();

    // Calculate timing state
    int frameTimeMs = 50;  // Assume 50ms frame time
    int effectState = state.frameIndex * tspeed * frameTimeMs / 50;

    if (branches < 1) branches = 1;
    int pixelsPerBranch = static_cast<int>(0.5 + static_cast<double>(bufferHt) / branches);
    if (pixelsPerBranch < 1) pixelsPerBranch = 1;

    int maxFrame = (branches + 1) * bufferWi;
    int frame = 1;
    if (effectState > 0 && maxFrame > 0) {
        frame = (effectState / 4) % maxFrame;
    }

    // Default tree color (green)
    Color treeColor = Color(0, 128, 0);
    bool allowAlpha = ctx.allowAlpha();

    const int numberGarlands = 1;

    for (int y = 0; y < bufferHt; y++) {
        for (int x = 0; x < bufferWi; x++) {
            // Calculate position within branch
            int mod = (pixelsPerBranch > 0) ? (y % pixelsPerBranch) : 0;
            if (mod == 0) mod = pixelsPerBranch;

            // Calculate brightness value for tree gradient
            float V = 1.0f - (1.0f * mod / pixelsPerBranch) * 0.70f;

            Color color = treeColor;
            if (allowAlpha) {
                color = color.withAlpha(static_cast<uint8_t>(255.0f * V));
            } else {
                color = color.withValue(V);
            }

            // Calculate branch number and position within branch
            int branch = (y - 1) / pixelsPerBranch;
            int row = pixelsPerBranch - mod;

            // Current branch based on frame
            int b = (effectState / bufferWi) % branches;

            // Frame modulo for animation
            int fMod = (effectState / 4) % bufferWi;

            // Pattern position (6-strand pattern)
            int m = x % 6;
            if (m == 0) m = 6;

            // Calculate hue for lights based on branch
            int r = branch % 5;
            float H = r / 4.0f;

            int oddEven = b % 2;
            int sOddRow = bufferWi - x + 1;

            // Check if this pixel should show a light
            if (branch <= b && x <= frame &&
                (((row == 3 || (numberGarlands == 2 && row == 6)) && (m == 1 || m == 6)) ||
                 ((row == 2 || (numberGarlands == 2 && row == 5)) && (m == 2 || m == 5)) ||
                 ((row == 1 || (numberGarlands == 2 && row == 4)) && (m == 3 || m == 4)))) {

                if (showLights) {
                    if ((oddEven == 0 && x <= fMod) || (oddEven == 1 && sOddRow <= fMod)) {
                        // Create light color from hue
                        color = Color::fromHSV(H, 1.0f, 1.0f);
                    }
                }
            }

            ctx.setPixel(x, y, color);
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(TreeEffect)

} // namespace xlCore
