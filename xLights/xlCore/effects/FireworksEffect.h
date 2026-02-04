/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

/**
 * @file FireworksEffect.h
 * @brief Fireworks particle effect for xlCore.
 *
 * This effect simulates fireworks explosions with particles that:
 * - Launch from random or specified locations
 * - Explode into multiple particles with varying velocities
 * - Apply gravity to particles over time
 * - Fade out based on age
 *
 * Supports deterministic rendering via seeded RNG.
 */

#include <vector>
#include <list>
#include <random>
#include <cmath>
#include <algorithm>

#include "../Effect.h"
#include "../Color.h"

namespace xlCore {

/**
 * @brief Simple 2D vector for particle physics.
 */
struct ParticleVec2 {
    float x = 0.0f;
    float y = 0.0f;

    ParticleVec2() = default;
    ParticleVec2(float x_, float y_) : x(x_), y(y_) {}

    ParticleVec2 operator+(const ParticleVec2& other) const {
        return {x + other.x, y + other.y};
    }

    ParticleVec2& operator+=(const ParticleVec2& other) {
        x += other.x;
        y += other.y;
        return *this;
    }
};

/**
 * @brief Individual firework particle.
 *
 * Represents a single particle in a firework explosion.
 * Tracks position, velocity, color, and age for fade effects.
 */
struct FireworkParticle {
    ParticleVec2 position;     ///< Current position
    ParticleVec2 velocity;     ///< Current velocity
    int colorIndex = 0;        ///< Palette color index
    float hue = 0.0f;          ///< HSV hue for color (if holdColor)
    float saturation = 1.0f;   ///< HSV saturation
    int age = 0;               ///< Frames since creation
    int fadeFrames = 50;       ///< Frames until fully faded
    bool holdColor = true;     ///< Whether to maintain initial color

    /**
     * @brief Check if particle has expired.
     */
    bool isDone(int width, int height, bool gravity) const {
        return (age * 2 > fadeFrames) ||
               position.x < 0 || position.y < 0 ||
               position.x > width ||
               (!gravity && position.y > height);
    }

    /**
     * @brief Calculate fade value (0.0 to 1.0).
     */
    float fadeValue() const {
        float v = (10.0f * fadeFrames - age * 20.0f) / (10.0f * fadeFrames);
        return std::max(0.0f, v);
    }

    /**
     * @brief Advance particle by one frame.
     * @param gravity If true, apply gravitational acceleration
     * @param fps Frames per second for gravity calculation
     */
    void advance(bool gravity, float fps) {
        position += velocity;
        if (gravity) {
            velocity.y += 0.98f / fps;
        }
        age++;
    }
};

/**
 * @brief A single firework explosion.
 *
 * Contains multiple particles that explode from a single point.
 */
class Firework {
public:
    static constexpr int MAX_CYCLES = 500;

    Firework() = default;

    /**
     * @brief Create a firework explosion.
     * @param particleCount Number of particles in explosion
     * @param x Starting X position
     * @param y Starting Y position
     * @param vx X velocity bias
     * @param vy Y velocity bias
     * @param fade Fade duration
     * @param gravity Whether to apply gravity
     * @param colorIndex Palette color index
     * @param holdColor Whether particles hold initial color
     * @param velocity Explosion velocity magnitude
     * @param width Buffer width
     * @param height Buffer height
     * @param fps Frames per second
     * @param rng Random number generator
     */
    void initialize(int particleCount, int x, int y, float vx, float vy,
                    int fade, bool gravity, int colorIndex, bool holdColor,
                    float velocity, int width, int height, float fps,
                    std::mt19937& rng);

    /**
     * @brief Advance all particles by one frame.
     */
    void advance(float fps);

    /**
     * @brief Check if firework has finished.
     */
    bool isDone() const;

    /**
     * @brief Get all particles.
     */
    const std::vector<FireworkParticle>& particles() const { return _particles; }

    /**
     * @brief Check if gravity is enabled.
     */
    bool hasGravity() const { return _gravity; }

private:
    std::vector<FireworkParticle> _particles;
    int _cycles = 0;
    bool _gravity = true;
    int _width = 0;
    int _height = 0;
    mutable bool _done = false;

    bool allParticlesExpired() const;
};

/**
 * @brief Fireworks effect state.
 *
 * Maintains state between frames for the fireworks effect.
 */
struct FireworksState {
    std::list<Firework> fireworks;
    std::vector<int> firePeriods;    ///< Pre-scheduled explosion frames
    int sinceLastTriggered = 0;
    uint32_t lastRandomSeed = 0;
};

/**
 * @brief Fireworks particle effect.
 *
 * Creates firework explosions with configurable:
 * - Number of explosions
 * - Particle count per explosion
 * - Explosion velocity
 * - Gravity effects
 * - Color fading
 * - Launch position control
 */
class FireworksEffect : public Effect {
public:
    FireworksEffect() = default;
    ~FireworksEffect() override = default;

    // ========== Identity ==========
    std::string name() const override { return "Fireworks"; }
    std::string description() const override {
        return "Firework explosions with particles affected by gravity";
    }
    std::string category() const override { return "Particle"; }

    // ========== Rendering ==========
    void render(RenderContext& ctx, const EffectSettings& settings,
                const RenderState& state) override;

    // ========== Threading ==========
    bool supportsRenderCache(const EffectSettings& settings) const override {
        return false;  // Particle state makes caching complex
    }

    // ========== Parameters ==========
    std::vector<EffectParameter> parameters() const override;

    // ========== Cloning ==========
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<FireworksEffect>(*this);
    }

private:
    // Per-instance state (managed externally in real usage)
    mutable FireworksState _state;

    /**
     * @brief Get random firework location.
     */
    static std::pair<int, int> getFireworkLocation(int width, int height,
                                                    int overrideX, int overrideY,
                                                    std::mt19937& rng);

    /**
     * @brief Create a new firework explosion.
     */
    void createFirework(const EffectSettings& settings, const RenderState& state,
                        std::mt19937& rng, int width, int height,
                        float fps, int colorCount);
};

} // namespace xlCore
