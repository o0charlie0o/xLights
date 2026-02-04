/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "CandleEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../Math.h"

#include <cstdlib>
#include <algorithm>
#include <random>

namespace xlCore {

namespace {
    // Thread-local random number generator for rand01()
    thread_local std::mt19937 rng{std::random_device{}()};
    thread_local std::uniform_real_distribution<float> dist01(0.0f, 1.0f);

    float rand01() {
        return dist01(rng);
    }
}

std::vector<EffectParameter> CandleEffect::parameters() const {
    return {
        EffectParameter::createInt(
            "E_SLIDER_Candle_FlameAgility",
            "Flame Agility",
            2, CANDLE_AGILITY_MIN, CANDLE_AGILITY_MAX,
            true  // Supports value curve
        ),
        EffectParameter::createInt(
            "E_SLIDER_Candle_WindBaseline",
            "Wind Baseline",
            30, CANDLE_WINDBASELINE_MIN, CANDLE_WINDBASELINE_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Candle_WindVariability",
            "Wind Variability",
            5, CANDLE_WINDVARIABILITY_MIN, CANDLE_WINDVARIABILITY_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Candle_WindCalmness",
            "Wind Calmness",
            2, CANDLE_WINDCALMNESS_MIN, CANDLE_WINDCALMNESS_MAX,
            true
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_PerNode",
            "Per Node",
            false
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_UsePalette",
            "Use Palette",
            false
        )
    };
}

void CandleEffect::CandleState::init() {
    // Initialize with random values
    flamer = static_cast<uint8_t>(rand01() * 255);
    flameprimer = static_cast<uint8_t>(rand01() * 255);
    flameg = static_cast<uint8_t>(rand01() * flamer);
    flameprimeg = static_cast<uint8_t>(rand01() * flameprimer);
    wind = static_cast<uint8_t>(rand01() * 255);
}

void CandleEffect::prepareForRender(const EffectSettings& settings) {
    m_states.clear();
    m_initialized = false;
}

void CandleEffect::cleanupAfterRender() {
    m_states.clear();
    m_initialized = false;
}

void CandleEffect::updateFlame(uint8_t& flameprime, uint8_t& flame, uint8_t& wind,
                               int windVariability, int flameAgility,
                               int windCalmness, int windBaseline) const {
    // We simulate a gust of wind by setting the wind var to a random value
    if (static_cast<uint8_t>(rand01() * 255.0) < windVariability) {
        wind = static_cast<uint8_t>(rand01() * 255.0);
    }

    // The wind constantly settles towards its baseline value
    if (wind > windBaseline) {
        wind--;
    }

    // The flame constantly gets brighter till the wind knocks it down
    if (flame < 255) {
        flame++;
    }

    // Depending on the wind strength and the calmness modifier we calculate the odds
    // of the wind knocking down the flame by setting it to random values
    if (static_cast<uint8_t>(rand01() * 255) < (wind >> windCalmness)) {
        flame = static_cast<uint8_t>(rand01() * 255);
    }

    // Real flames look like they have inertia so we use this constant-approach-rate filter
    // To lowpass the flame height
    if (flame > flameprime) {
        if (flameprime < (255 - flameAgility)) {
            flameprime += flameAgility;
        }
    } else {
        if (flameprime > flameAgility) {
            flameprime -= flameAgility;
        }
    }

    // How do we prevent jittering when the two are equal?
    // We don't. It adds to the realism.
}

void CandleEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int flameAgility = settings.getInt("E_SLIDER_Candle_FlameAgility", 2);
    int windCalmness = settings.getInt("E_SLIDER_Candle_WindCalmness", 2);
    int windVariability = settings.getInt("E_SLIDER_Candle_WindVariability", 5);
    int windBaseline = settings.getInt("E_SLIDER_Candle_WindBaseline", 30);
    bool perNode = settings.getBool("E_CHECKBOX_PerNode", false);
    bool usePalette = settings.getBool("E_CHECKBOX_UsePalette", false);

    // Default palette colors
    Color c1 = Color::White();
    Color c2 = Color::Black();

    // Initialize states if needed
    if (!m_initialized) {
        m_initialized = true;

        int numStates = 1;
        if (perNode) {
            numStates = ctx.width() * ctx.height();
        }

        m_states.resize(numStates);
        for (int i = 0; i < numStates; i++) {
            m_states[i].init();
        }
    }

    if (perNode) {
        // Each pixel has its own flame
        for (int y = 0; y < ctx.height(); y++) {
            for (int x = 0; x < ctx.width(); x++) {
                size_t index = y * ctx.width() + x;
                if (index >= m_states.size()) continue;

                CandleState& candleState = m_states[index];

                // Update red and green flames
                updateFlame(candleState.flameprimer, candleState.flamer, candleState.wind,
                           windVariability, flameAgility, windCalmness, windBaseline);
                updateFlame(candleState.flameprimeg, candleState.flameg, candleState.wind,
                           windVariability, flameAgility, windCalmness, windBaseline);

                // Green shouldn't exceed red for flame colors
                if (candleState.flameprimeg > candleState.flameprimer) {
                    candleState.flameprimeg = candleState.flameprimer;
                }
                if (candleState.flameg > candleState.flamer) {
                    candleState.flameprimeg = candleState.flameprimer;
                }

                Color c;
                if (usePalette) {
                    // Blend between palette colors based on flame intensity
                    float t = static_cast<float>(candleState.flameprimer) / 255.0f;
                    c = Color(
                        static_cast<uint8_t>(c1.red * (1.0f - t) + c2.red * t),
                        static_cast<uint8_t>(c1.green * (1.0f - t) + c2.green * t),
                        static_cast<uint8_t>(c1.blue * (1.0f - t) + c2.blue * t)
                    );
                } else {
                    // Default flame color: red with half green (orange/yellow flame)
                    c = Color(candleState.flameprimer, candleState.flameprimeg / 2, 0);
                }

                ctx.setPixel(x, y, c);
            }
        }
    } else {
        // Single flame for entire buffer
        CandleState& candleState = m_states[0];

        // Update red and green flames
        updateFlame(candleState.flameprimer, candleState.flamer, candleState.wind,
                   windVariability, flameAgility, windCalmness, windBaseline);
        updateFlame(candleState.flameprimeg, candleState.flameg, candleState.wind,
                   windVariability, flameAgility, windCalmness, windBaseline);

        // Green shouldn't exceed red for flame colors
        if (candleState.flameprimeg > candleState.flameprimer) {
            candleState.flameprimeg = candleState.flameprimer;
        }
        if (candleState.flameg > candleState.flamer) {
            candleState.flameprimeg = candleState.flameprimer;
        }

        Color c;
        if (usePalette) {
            // Blend between palette colors based on flame intensity
            float t = static_cast<float>(candleState.flameprimer) / 255.0f;
            c = Color(
                static_cast<uint8_t>(c1.red * (1.0f - t) + c2.red * t),
                static_cast<uint8_t>(c1.green * (1.0f - t) + c2.green * t),
                static_cast<uint8_t>(c1.blue * (1.0f - t) + c2.blue * t)
            );
        } else {
            // Default flame color: red with half green (orange/yellow flame)
            c = Color(candleState.flameprimer, candleState.flameprimeg / 2, 0);
        }

        ctx.fill(c);
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(CandleEffect)

} // namespace xlCore
