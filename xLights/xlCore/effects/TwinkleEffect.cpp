/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "TwinkleEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

// Parameter keys
static const std::string KEY_COUNT = "E_SLIDER_Twinkle_Count";
static const std::string KEY_STEPS = "E_SLIDER_Twinkle_Steps";
static const std::string KEY_STROBE = "E_CHECKBOX_Twinkle_Strobe";
static const std::string KEY_RERANDOM = "E_CHECKBOX_Twinkle_ReRandom";

std::vector<EffectParameter> TwinkleEffect::parameters() const {
    return {
        EffectParameter::createInt(KEY_COUNT, "Count", 3, 1, 100, true),
        EffectParameter::createInt(KEY_STEPS, "Steps", 30, 1, 200, true),
        EffectParameter::createBool(KEY_STROBE, "Strobe", false),
        EffectParameter::createBool(KEY_RERANDOM, "Re-Randomize", false)
    };
}

void TwinkleEffect::prepareForRender(const EffectSettings& settings) {
    m_twinkles.clear();
    m_initialized = false;
    m_activeCount = 0;
    m_lightsToRenew = 0;
}

void TwinkleEffect::cleanupAfterRender() {
    m_twinkles.clear();
    m_initialized = false;
    m_activeCount = 0;
    m_lightsToRenew = 0;
}

void TwinkleEffect::placeTwinkles(int count, int maxDuration, size_t colorCount) {
    std::uniform_int_distribution<int> durationDist(0, maxDuration - 1);
    std::uniform_int_distribution<int> colorDist(0, static_cast<int>(colorCount) - 1);

    int placed = 0;
    for (size_t i = m_activeCount; i < m_twinkles.size() && placed < count; i++) {
        if (!m_twinkles[i].active) {
            // Swap with next active position
            if (static_cast<int>(i) != m_activeCount) {
                std::swap(m_twinkles[i], m_twinkles[m_activeCount]);
            }
            m_twinkles[m_activeCount].duration = durationDist(m_rng);
            m_twinkles[m_activeCount].colorIndex = colorDist(m_rng);
            m_twinkles[m_activeCount].active = true;
            m_activeCount++;
            placed++;
        }
    }
}

void TwinkleEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int count = settings.getInt(KEY_COUNT, 3);
    int steps = settings.getInt(KEY_STEPS, 30);
    bool strobe = settings.getBool(KEY_STROBE, false);
    bool reRandomize = settings.getBool(KEY_RERANDOM, false);

    int width = ctx.width();
    int height = ctx.height();
    int totalPixels = width * height;

    // Default palette (in real implementation, would come from effect settings)
    std::vector<Color> palette = {
        Color::White(),
        Color::Red(),
        Color::Blue(),
        Color::Green()
    };
    size_t colorCount = palette.size();

    // Calculate number of lights based on percentage
    int numLights = static_cast<int>(std::round((totalPixels * count) / 100.0));
    if (totalPixels == 1) {
        numLights = 1;
    }
    if (numLights < 1) {
        numLights = 1;
    }

    int maxModulo = steps;
    if (maxModulo < 2) {
        maxModulo = 2;
    }
    int maxModulo2 = maxModulo / 2;
    if (maxModulo2 < 1) {
        maxModulo2 = 1;
    }

    // Initialize on first frame
    if (!m_initialized) {
        m_rng.seed(state.randomSeed);
        m_initialized = true;
        m_activeCount = 0;
        m_lightsToRenew = numLights;

        // Create all possible twinkle positions
        m_twinkles.clear();
        m_twinkles.resize(totalPixels);

        int idx = 0;
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                m_twinkles[idx].x = x;
                m_twinkles[idx].y = y;
                m_twinkles[idx].duration = 0;
                m_twinkles[idx].active = false;
                idx++;
            }
        }

        // Randomize positions
        for (size_t i = 0; i < m_twinkles.size(); i++) {
            size_t r = m_rng() % m_twinkles.size();
            if (r != i) {
                std::swap(m_twinkles[r], m_twinkles[i]);
            }
        }
    }

    // Handle changing light count
    m_lightsToRenew += numLights - static_cast<int>(m_activeCount);
    if (m_lightsToRenew < 0) {
        m_lightsToRenew = 0;
    }

    // Clean up finished twinkles and compact active list
    if (m_lightsToRenew > 0) {
        // Remove inactive lights from the active portion
        while (m_activeCount > 0 && !m_twinkles[m_activeCount - 1].active) {
            m_activeCount--;
        }
        for (int i = 0; i < m_activeCount; i++) {
            if (!m_twinkles[i].active) {
                m_activeCount--;
                if (i != m_activeCount) {
                    std::swap(m_twinkles[i], m_twinkles[m_activeCount]);
                }
                while (m_activeCount > 0 && !m_twinkles[m_activeCount - 1].active) {
                    m_activeCount--;
                }
            }
        }

        // Place new twinkles
        placeTwinkles(m_lightsToRenew, maxModulo, colorCount);
        m_lightsToRenew = 0;
    }

    std::uniform_int_distribution<int> colorDist(0, static_cast<int>(colorCount) - 1);

    // Render active twinkles
    for (int i = 0; i < m_activeCount; i++) {
        TwinkleLight& twinkle = m_twinkles[i];

        if (!twinkle.active) {
            continue;
        }

        // Advance duration
        twinkle.duration++;

        // Check if twinkle cycle is complete
        if (twinkle.duration >= maxModulo) {
            twinkle.duration = 0;
            m_lightsToRenew++;
            twinkle.active = false;

            if (reRandomize) {
                twinkle.colorIndex = colorDist(m_rng);
            }
            continue;
        }

        // Calculate brightness based on position in cycle
        // Fades up to middle, then fades down
        double brightness;
        if (twinkle.duration <= maxModulo2) {
            brightness = static_cast<double>(twinkle.duration) / maxModulo2;
        } else {
            brightness = static_cast<double>(maxModulo - twinkle.duration) / maxModulo2;
        }
        brightness = std::clamp(brightness, 0.0, 1.0);

        // Strobe mode: only show at peak
        if (strobe) {
            if (twinkle.duration == maxModulo2) {
                brightness = 1.0;
            } else {
                brightness = 0.0;
            }
        }

        // Skip if too dim
        if (brightness < 0.01) {
            continue;
        }

        // Get color
        Color color = palette[twinkle.colorIndex % colorCount];

        if (ctx.allowAlpha()) {
            color = Color(color.red, color.green, color.blue,
                         static_cast<uint8_t>(255 * brightness));
        } else {
            HSV hsv = color.toHSV();
            hsv.value *= brightness;
            color = Color(hsv);
        }

        ctx.setPixel(twinkle.x, twinkle.y, color);
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(TwinkleEffect)

} // namespace xlCore
