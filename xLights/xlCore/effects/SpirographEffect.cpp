/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "SpirographEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../XLMath.h"

#include <cmath>
#include <random>

namespace xlCore {

std::vector<EffectParameter> SpirographEffect::parameters() const {
    return {
        EffectParameter::createInt(
            "E_SLIDER_Spirograph_R",
            "R (Large Circle)",
            20, SPIROGRAPH_R_MIN, SPIROGRAPH_R_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Spirograph_r",
            "r (Small Circle)",
            10, SPIROGRAPH_r_MIN, SPIROGRAPH_r_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Spirograph_d",
            "d (Distance)",
            30, SPIROGRAPH_d_MIN, SPIROGRAPH_d_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Spirograph_Animate",
            "Animate",
            0, SPIROGRAPH_ANIMATE_MIN, SPIROGRAPH_ANIMATE_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Spirograph_Speed",
            "Speed",
            10, SPIROGRAPH_SPEED_MIN, SPIROGRAPH_SPEED_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Spirograph_Length",
            "Length",
            20, SPIROGRAPH_LENGTH_MIN, SPIROGRAPH_LENGTH_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Spirograph_Width",
            "Width",
            1, SPIROGRAPH_WIDTH_MIN, SPIROGRAPH_WIDTH_MAX,
            true
        )
    };
}

void SpirographEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int intR = settings.getInt("E_SLIDER_Spirograph_R", 20);
    int intr = settings.getInt("E_SLIDER_Spirograph_r", 10);
    int intd = settings.getInt("E_SLIDER_Spirograph_d", 30);
    int animate = settings.getInt("E_SLIDER_Spirograph_Animate", 0);
    int speed = settings.getInt("E_SLIDER_Spirograph_Speed", 10);
    int length = settings.getInt("E_SLIDER_Spirograph_Length", 20);
    int width = settings.getInt("E_SLIDER_Spirograph_Width", 1);

    // Default colors
    std::vector<Color> colors = { Color::White(), Color::Red(), Color::Blue() };
    size_t colorCount = colors.size();

    // Calculate state based on time
    int frameTimeMs = 50;  // Default frame time
    int curPeriod = state.frameIndex;
    int frameCount = state.totalFrames;

    int animationState = curPeriod * speed * frameTimeMs / 50;
    double animateState = static_cast<double>(curPeriod * animate * frameTimeMs) / 5000.0;

    length = length * 18;

    float xc = static_cast<float>(ctx.width()) / 2.0f;
    float yc = static_cast<float>(ctx.height()) / 2.0f;
    float R = xc * (intR / 100.0f);
    float r = xc * (intr / 100.0f);

    // Small r cannot be 0 to avoid divide by zero
    if (r == 0) {
        r = 0.00001f;
    }
    if (r > R) r = R;

    float d = xc * (intd / 100.0f);

    // Hypotrochoid equations:
    // x(t) = (R-r) * cos(t) + d * cos((R-r)/r * t)
    // y(t) = (R-r) * sin(t) + d * sin((R-r)/r * t)

    int mod1440 = animationState % 1440;
    float dOrig = d;
    if (animate != 0) {
        d = dOrig + static_cast<float>(animateState) * dOrig;
    }

    float step = 1.0f / width;
    float stepw = 1.0f / (std::log10(static_cast<float>(width)) + 1.0f);
    if (step == 0) step = 1.0f;
    if (stepw == 0) stepw = 1.0f;

    int dMod = (colorCount > 0) ? ctx.width() / static_cast<int>(colorCount) : 1;
    if (dMod == 0) dMod = 1;

    for (float i = 1.0f; i <= length; i += step) {
        float t = (i + mod1440) * math::PI / 180.0f;
        float x = (R - r) * std::cos(t) + d * std::cos(((R - r) / r) * t) + xc;
        float y = (R - r) * std::sin(t) + d * std::sin(((R - r) / r) * t) + yc;

        // Calculate color based on distance from center
        double x2 = std::pow(x - xc, 2.0);
        double y2 = std::pow(y - yc, 2.0);
        double hyp = (std::sqrt(x2 + y2) / ctx.width()) * 100.0;
        int colorIdx = static_cast<int>(hyp / dMod);

        if (colorIdx >= static_cast<int>(colorCount)) {
            colorIdx = static_cast<int>(colorCount) - 1;
        }
        if (colorIdx < 0) colorIdx = 0;

        Color color = colors[colorIdx];

        // Draw with width using the normal to the curve
        float tt = ((R - r) / r) * t;
        for (float w = -width / 2.0f; w <= width / 2.0f; w += stepw) {
            int xx = static_cast<int>(x + w * std::cos(tt));
            int yy = static_cast<int>(y + w * std::sin(tt));
            ctx.setPixel(xx, yy, color);
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(SpirographEffect)

} // namespace xlCore
