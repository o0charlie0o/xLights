/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "StrobeEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

// Parameter keys
static const std::string KEY_NUM_STROBES = "E_SLIDER_Number_Strobes";
static const std::string KEY_DURATION = "E_SLIDER_Strobe_Duration";
static const std::string KEY_TYPE = "E_SLIDER_Strobe_Type";

std::vector<EffectParameter> StrobeEffect::parameters() const {
    return {
        EffectParameter::createInt(KEY_NUM_STROBES, "Number of Strobes", 3, 1, 300, true),
        EffectParameter::createInt(KEY_DURATION, "Strobe Duration", 10, 1, 100, true),
        EffectParameter::createInt(KEY_TYPE, "Strobe Type", 1, 1, 4, false)
    };
}

void StrobeEffect::prepareForRender(const EffectSettings& settings) {
    m_strobes.clear();
    m_initialized = false;
}

void StrobeEffect::cleanupAfterRender() {
    m_strobes.clear();
    m_initialized = false;
}

void StrobeEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int numStrobes = settings.getInt(KEY_NUM_STROBES, 3);
    int strobeDuration = settings.getInt(KEY_DURATION, 10);
    int strobeType = settings.getInt(KEY_TYPE, 1);

    int width = ctx.width();
    int height = ctx.height();

    if (strobeDuration < 1) {
        strobeDuration = 1;
    }

    // Default palette (in real implementation, would come from effect settings)
    std::vector<Color> palette = {
        Color::White(),
        Color::Red(),
        Color::Blue(),
        Color::Green()
    };
    size_t colorCount = palette.size();

    // Initialize RNG with seed for reproducibility
    if (!m_initialized) {
        m_rng.seed(state.randomSeed);
        m_initialized = true;

        // Pre-populate strobes for first frame
        m_strobes.clear();
        std::uniform_int_distribution<int> xDist(0, std::max(0, width - 1));
        std::uniform_int_distribution<int> yDist(0, std::max(0, height - 1));
        std::uniform_int_distribution<int> colorDist(0, colorCount - 1);
        std::uniform_int_distribution<int> durationDist(0, strobeDuration - 1);

        for (int i = 0; i < numStrobes * strobeDuration; i++) {
            StrobeLight strobe;
            strobe.x = xDist(m_rng);
            strobe.y = yDist(m_rng);
            strobe.colorIndex = colorDist(m_rng);
            strobe.color = palette[strobe.colorIndex];
            strobe.duration = i % strobeDuration;
            m_strobes.push_back(strobe);
        }
    }

    // Distributions for adding new strobes
    std::uniform_int_distribution<int> xDist(0, std::max(0, width - 1));
    std::uniform_int_distribution<int> yDist(0, std::max(0, height - 1));
    std::uniform_int_distribution<int> colorDist(0, colorCount - 1);

    // Add new strobes if needed
    while (m_strobes.size() < static_cast<size_t>(numStrobes * strobeDuration)) {
        StrobeLight strobe;
        strobe.x = xDist(m_rng);
        strobe.y = yDist(m_rng);
        strobe.colorIndex = colorDist(m_rng);
        strobe.color = palette[strobe.colorIndex];
        strobe.duration = strobeDuration;
        m_strobes.push_back(strobe);
    }

    // Render each strobe
    for (auto it = m_strobes.begin(); it != m_strobes.end(); ) {
        int x = it->x;
        int y = it->y;
        Color color = it->color;

        if (it->duration > 0) {
            // Calculate brightness based on duration
            double v = 1.0;
            if (it->duration == 1) {
                v = 0.5;
            } else if (it->duration == 2) {
                v = 0.75;
            }

            Color dimColor = color;
            if (ctx.allowAlpha()) {
                dimColor = Color(color.red, color.green, color.blue,
                                static_cast<uint8_t>(255 * v));
            } else {
                dimColor = Color(
                    static_cast<uint8_t>(color.red * v),
                    static_cast<uint8_t>(color.green * v),
                    static_cast<uint8_t>(color.blue * v)
                );
            }

            // Draw the strobe at full brightness
            ctx.setPixel(x, y, color);

            // Draw additional pixels based on strobe type
            std::uniform_int_distribution<int> twoChoice(0, 1);

            if (strobeType == 2) {
                // Random 3-pixel line
                int r = twoChoice(m_rng);
                if (r == 0) {
                    ctx.setPixel(x, y - 1, dimColor);
                    ctx.setPixel(x, y + 1, dimColor);
                } else {
                    ctx.setPixel(x - 1, y, dimColor);
                    ctx.setPixel(x + 1, y, dimColor);
                }
            } else if (strobeType == 3) {
                // Cross shape
                ctx.setPixel(x, y - 1, dimColor);
                ctx.setPixel(x, y + 1, dimColor);
                ctx.setPixel(x - 1, y, dimColor);
                ctx.setPixel(x + 1, y, dimColor);
            } else if (strobeType == 4) {
                // Random cross or X
                int r = twoChoice(m_rng);
                if (r == 0) {
                    ctx.setPixel(x, y - 1, dimColor);
                    ctx.setPixel(x, y + 1, dimColor);
                    ctx.setPixel(x - 1, y, dimColor);
                    ctx.setPixel(x + 1, y, dimColor);
                } else {
                    ctx.setPixel(x + 1, y - 1, dimColor);
                    ctx.setPixel(x + 1, y + 1, dimColor);
                    ctx.setPixel(x - 1, y - 1, dimColor);
                    ctx.setPixel(x - 1, y + 1, dimColor);
                }
            }
        }

        // Decrement duration and remove expired strobes
        it->duration--;
        if (it->duration <= 0) {
            it = m_strobes.erase(it);
        } else {
            ++it;
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(StrobeEffect)

} // namespace xlCore
