/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "ShimmerEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <cmath>
#include <random>

namespace xlCore {

// Parameter keys
static const std::string KEY_DUTY_FACTOR = "E_SLIDER_Shimmer_Duty_Factor";
static const std::string KEY_CYCLES = "E_SLIDER_Shimmer_Cycles";
static const std::string KEY_USE_ALL_COLORS = "E_CHECKBOX_Shimmer_Use_All_Colors";

std::vector<EffectParameter> ShimmerEffect::parameters() const {
    return {
        EffectParameter::createInt(KEY_DUTY_FACTOR, "Duty Factor", 50, 1, 100, true),
        EffectParameter::createDouble(KEY_CYCLES, "Cycles", 1.0, 0.1, 100.0, 0.1),
        EffectParameter::createBool(KEY_USE_ALL_COLORS, "Use All Colors", false)
    };
}

void ShimmerEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int dutyFactor = settings.getInt(KEY_DUTY_FACTOR, 50);
    double cycles = settings.getDouble(KEY_CYCLES, 1.0);
    bool useAllColors = settings.getBool(KEY_USE_ALL_COLORS, false);

    int width = ctx.width();
    int height = ctx.height();

    // Default palette (in real implementation, would come from effect settings)
    std::vector<Color> palette = {
        Color::Red(),
        Color::Green(),
        Color::Blue(),
        Color::Yellow()
    };
    size_t colorCount = palette.size();
    if (colorCount == 0) {
        return;
    }

    // Calculate position within cycle
    double position = std::fmod(state.progress * cycles, 1.0);

    // If beyond duty factor, leave black
    if (position >= static_cast<double>(dutyFactor) / 100.0) {
        return;
    }

    // Calculate which color index we're on
    int totalFrames = state.totalFrames > 0 ? state.totalFrames : 1;
    int cycle = static_cast<int>((state.frameIndex * cycles) / totalFrames);
    int colorIdx = cycle % colorCount;

    Color color = palette[colorIdx];

    // Random number generator for "use all colors" mode
    std::mt19937 rng(state.randomSeed + state.frameIndex);
    std::uniform_int_distribution<int> colorDist(0, colorCount - 1);

    // Fill buffer
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            Color pixelColor = color;

            if (useAllColors) {
                // Randomly assign color to each pixel
                int randomIdx = colorDist(rng);
                pixelColor = palette[randomIdx];
            }

            ctx.setPixel(x, y, pixelColor);
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(ShimmerEffect)

} // namespace xlCore
