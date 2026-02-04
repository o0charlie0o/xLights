/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// System headers first
#include <cmath>
#include <algorithm>

#include "FireworksEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

namespace xlCore {

namespace {
    constexpr float PI = 3.14159265358979323846f;
}

// ============================================================================
// Firework Implementation
// ============================================================================

void Firework::initialize(int particleCount, int x, int y, float vx, float vy,
                          int fade, bool gravity, int colorIndex, bool holdColor,
                          float velocity, int width, int height, float fps,
                          std::mt19937& rng) {
    _gravity = gravity;
    _width = width;
    _height = height;
    _cycles = 0;
    _done = false;
    _particles.clear();
    _particles.reserve(particleCount);

    std::uniform_real_distribution<float> velocityDist(-1.0f, 1.0f);
    std::uniform_real_distribution<float> angleDist(0.0f, 2.0f * PI);

    for (int i = 0; i < particleCount; i++) {
        FireworkParticle p;
        p.position = ParticleVec2(static_cast<float>(x), static_cast<float>(y));
        p.fadeFrames = fade;
        p.colorIndex = colorIndex;
        p.holdColor = holdColor;
        p.age = 0;

        // Explosion velocity with random direction
        float explosionVelocity = velocityDist(rng) * velocity;
        float angle = angleDist(rng);

        p.velocity.x = 3.0f * vx / 100.0f + explosionVelocity * std::cos(angle);
        p.velocity.y = 3.0f * -vy / 100.0f + explosionVelocity * std::sin(angle);

        _particles.push_back(p);
    }
}

void Firework::advance(float fps) {
    _cycles++;

    for (auto& p : _particles) {
        p.advance(_gravity, fps);
    }

    if (isDone()) {
        _particles.clear();
    }
}

bool Firework::allParticlesExpired() const {
    for (const auto& p : _particles) {
        if (!p.isDone(_width, _height, _gravity)) {
            return false;
        }
    }
    _done = true;
    return true;
}

bool Firework::isDone() const {
    return _done || _cycles >= MAX_CYCLES || allParticlesExpired();
}

// ============================================================================
// FireworksEffect Implementation
// ============================================================================

std::vector<EffectParameter> FireworksEffect::parameters() const {
    std::vector<EffectParameter> params;

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Fireworks_Explosions", "Number of Explosions", 16, 1, 50));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Fireworks_Count", "Particle Count", 50, 1, 100, true));

    auto velocity = EffectParameter::createDouble(
        "E_SLIDER_Fireworks_Velocity", "Velocity", 2.0, 0.1, 10.0, 0.1);
    velocity.supportsValueCurve = true;
    params.push_back(velocity);

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Fireworks_Fade", "Fade", 50, 1, 100, true));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Fireworks_XVelocity", "X Velocity", 0, -100, 100, true));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Fireworks_YVelocity", "Y Velocity", 0, -100, 100, true));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Fireworks_XLocation", "X Location", -1, -1, 100, true));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Fireworks_YLocation", "Y Location", -1, -1, 100, true));

    params.push_back(EffectParameter::createBool(
        "E_CHECKBOX_Fireworks_Gravity", "Gravity", true));

    params.push_back(EffectParameter::createBool(
        "E_CHECKBOX_Fireworks_HoldColour", "Hold Color", true));

    return params;
}

std::pair<int, int> FireworksEffect::getFireworkLocation(int width, int height,
                                                          int overrideX, int overrideY,
                                                          std::mt19937& rng) {
    int startX, startY;

    if (overrideX >= 0) {
        startX = overrideX * width / 100;
    } else {
        int x25 = static_cast<int>(0.25f * width);
        int x75 = static_cast<int>(0.75f * width);
        if ((x75 - x25) > 0) {
            std::uniform_int_distribution<int> dist(x25, x75 - 1);
            startX = dist(rng);
        } else {
            startX = 0;
        }
    }

    if (overrideY >= 0) {
        startY = overrideY * height / 100;
    } else {
        int y25 = static_cast<int>(0.25f * height);
        int y75 = static_cast<int>(0.75f * height);
        if ((y75 - y25) > 0) {
            std::uniform_int_distribution<int> dist(y25, y75 - 1);
            startY = dist(rng);
        } else {
            startY = 0;
        }
    }

    return {startX, startY};
}

void FireworksEffect::createFirework(const EffectSettings& settings,
                                      const RenderState& state,
                                      std::mt19937& rng, int width, int height,
                                      float fps, int colorCount) {
    int particleCount = settings.getInt("E_SLIDER_Fireworks_Count", 50);
    float velocity = static_cast<float>(settings.getDouble("E_SLIDER_Fireworks_Velocity", 2.0));
    int fade = settings.getInt("E_SLIDER_Fireworks_Fade", 50);
    int xVelocity = settings.getInt("E_SLIDER_Fireworks_XVelocity", 0);
    int yVelocity = settings.getInt("E_SLIDER_Fireworks_YVelocity", 0);
    int xLocation = settings.getInt("E_SLIDER_Fireworks_XLocation", -1);
    int yLocation = settings.getInt("E_SLIDER_Fireworks_YLocation", -1);
    bool gravity = settings.getBool("E_CHECKBOX_Fireworks_Gravity", true);
    bool holdColor = settings.getBool("E_CHECKBOX_Fireworks_HoldColour", true);

    auto location = getFireworkLocation(width, height, xLocation, yLocation, rng);

    std::uniform_int_distribution<int> colorDist(0, std::max(0, colorCount - 1));
    int colorIndex = colorDist(rng);

    Firework fw;
    fw.initialize(particleCount, location.first, location.second,
                  static_cast<float>(xVelocity), static_cast<float>(yVelocity),
                  fade, gravity, colorIndex, holdColor,
                  velocity, width, height, fps, rng);

    _state.fireworks.push_back(fw);
}

void FireworksEffect::render(RenderContext& ctx, const EffectSettings& settings,
                              const RenderState& state) {
    int width = ctx.width();
    int height = ctx.height();

    // Get effect parameters
    int numberOfExplosions = settings.getInt("E_SLIDER_Fireworks_Explosions", 16);
    bool gravity = settings.getBool("E_CHECKBOX_Fireworks_Gravity", true);
    bool holdColor = settings.getBool("E_CHECKBOX_Fireworks_HoldColour", true);

    // Frame timing
    float frameTimeMs = 1000.0f / 20.0f;  // Default 20fps, would come from state
    if (state.totalFrames > 0) {
        double duration = state.effectEndTime - state.effectStartTime;
        if (duration > 0) {
            frameTimeMs = static_cast<float>(duration * 1000.0 / state.totalFrames);
        }
    }
    float fps = 1000.0f / frameTimeMs;

    // Create deterministic RNG from state
    std::mt19937 rng(state.randomSeed + static_cast<uint32_t>(state.frameIndex));

    // Initialize on first frame
    if (state.frameIndex == 0) {
        _state.fireworks.clear();
        _state.firePeriods.clear();
        _state.sinceLastTriggered = 0;

        // Pre-schedule explosion times
        std::uniform_real_distribution<double> timeDist(0.0, 1.0);
        for (int i = 0; i < numberOfExplosions; i++) {
            int period = static_cast<int>(timeDist(rng) * state.totalFrames);
            _state.firePeriods.push_back(period);
        }
        // Sort for deterministic order
        std::sort(_state.firePeriods.begin(), _state.firePeriods.end());
    }

    // Color count (default to 6 colors if not available)
    int colorCount = 6;

    // Check if we should create new fireworks
    for (int firePeriod : _state.firePeriods) {
        if (firePeriod == state.frameIndex) {
            createFirework(settings, state, rng, width, height, fps, colorCount);
        }
    }

    // Render and advance all fireworks
    for (auto& fw : _state.fireworks) {
        if (!fw.isDone()) {
            // Render particles
            for (const auto& p : fw.particles()) {
                int x = static_cast<int>(p.position.x);
                int y = static_cast<int>(p.position.y);

                if (x >= 0 && x < width && y >= 0 && y < height) {
                    float fade = p.fadeValue();

                    // Create color based on particle settings
                    // In real usage, would use palette colors
                    float hue = static_cast<float>(p.colorIndex) / colorCount;
                    Color c = Color::fromHSV(hue, p.saturation, fade);

                    if (ctx.allowAlpha()) {
                        c.alpha = static_cast<uint8_t>(255.0f * fade);
                        ctx.setPixel(x, y, c);
                    } else {
                        ctx.setPixel(x, y, c);
                    }
                }
            }

            // Advance firework
            const_cast<Firework&>(fw).advance(fps);
        }
    }

    // Remove finished fireworks
    _state.fireworks.remove_if([](const Firework& fw) { return fw.isDone(); });
}

// Register effect with registry
XLCORE_REGISTER_EFFECT(FireworksEffect)

} // namespace xlCore
