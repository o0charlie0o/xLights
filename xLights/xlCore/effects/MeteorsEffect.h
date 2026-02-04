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
 * @file MeteorsEffect.h
 * @brief Meteors particle effect for xlCore.
 *
 * This effect creates meteor/trail particles that move across the buffer:
 * - Down/Up: Vertical meteor trails
 * - Left/Right: Horizontal meteor trails
 * - Implode: Meteors converging to center
 * - Explode: Meteors expanding from center
 * - Icicles: Dripping icicle effect
 *
 * Each meteor has a fading tail that creates a trail effect.
 */

#include <vector>
#include <list>
#include <random>
#include <cmath>

#include "../Effect.h"
#include "../Color.h"

namespace xlCore {

/**
 * @brief Meteor direction/mode.
 */
enum class MeteorDirection {
    Down = 0,
    Up = 1,
    Left = 2,
    Right = 3,
    Implode = 4,
    Explode = 5,
    Icicles = 6,
    IciclesBkg = 7
};

/**
 * @brief Color scheme for meteors.
 */
enum class MeteorColorScheme {
    Rainbow = 0,
    Range = 1,
    Palette = 2
};

/**
 * @brief Basic linear meteor particle.
 *
 * Used for horizontal and vertical meteor effects.
 */
struct MeteorParticle {
    int x = 0;
    int y = 0;
    float hue = 0.0f;
    float saturation = 1.0f;
    float value = 1.0f;
    int height = 0;  // For icicle effect (variable length)
};

/**
 * @brief Radial meteor particle.
 *
 * Used for implode/explode effects with angular movement.
 */
struct MeteorRadialParticle {
    float x = 0.0f;
    float y = 0.0f;
    float dx = 0.0f;  // Direction unit vector X
    float dy = 0.0f;  // Direction unit vector Y
    int count = 0;    // Frames alive
    float hue = 0.0f;
    float saturation = 1.0f;
    float value = 1.0f;
};

/**
 * @brief Meteors effect state.
 */
struct MeteorsState {
    std::list<MeteorParticle> meteors;
    std::list<MeteorRadialParticle> meteorsRadial;
    float effectState = 0.0f;
};

/**
 * @brief Meteors particle effect.
 *
 * Creates meteor/shooting star trails with configurable:
 * - Direction (up, down, left, right, implode, explode)
 * - Trail length
 * - Speed
 * - Swirl intensity
 * - Color schemes
 */
class MeteorsEffect : public Effect {
public:
    MeteorsEffect() = default;
    ~MeteorsEffect() override = default;

    // ========== Identity ==========
    std::string name() const override { return "Meteors"; }
    std::string description() const override {
        return "Meteor trails moving across the display";
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
        return std::make_unique<MeteorsEffect>(*this);
    }

private:
    mutable MeteorsState _state;

    // Speed calculation helper
    static float calcEffectStateOffset(int speed, float frameTimeMs);

    // Meteor management - Vertical
    void verticalAddMeteors(RenderContext& ctx, MeteorColorScheme colorScheme,
                            int count, std::mt19937& rng);
    void verticalMoveMeteors(int speed);
    void verticalRemoveMeteors(int height, int length);

    // Meteor management - Horizontal
    void horizontalAddMeteors(RenderContext& ctx, MeteorColorScheme colorScheme,
                              int count, std::mt19937& rng);
    void horizontalMoveMeteors(int speed);
    void horizontalRemoveMeteors(int width, int length);

    // Meteor management - Radial (Implode/Explode)
    void radialAddMeteors(RenderContext& ctx, MeteorColorScheme colorScheme,
                          int count, int length, int xOffset, int yOffset,
                          bool explode, std::mt19937& rng);
    void radialMoveMeteors(int speed, int xOffset, int yOffset,
                           int width, int height, bool fadeWithDistance, bool explode);
    void radialRemoveMeteors(int xOffset, int yOffset, int width, int height, bool explode);

    // Render methods for each direction
    void renderVertical(RenderContext& ctx, MeteorColorScheme colorScheme,
                        int count, int length, MeteorDirection direction,
                        int swirlIntensity, int speed, int warmupFrames,
                        float frameTimeMs, std::mt19937& rng);

    void renderHorizontal(RenderContext& ctx, MeteorColorScheme colorScheme,
                          int count, int length, MeteorDirection direction,
                          int swirlIntensity, int speed, int warmupFrames,
                          float frameTimeMs, std::mt19937& rng);

    void renderImplode(RenderContext& ctx, MeteorColorScheme colorScheme,
                       int count, int length, int swirlIntensity, int speed,
                       int xOffset, int yOffset, bool fadeWithDistance,
                       int warmupFrames, float frameTimeMs, std::mt19937& rng);

    void renderExplode(RenderContext& ctx, MeteorColorScheme colorScheme,
                       int count, int length, int swirlIntensity, int speed,
                       int xOffset, int yOffset, bool fadeWithDistance,
                       int warmupFrames, float frameTimeMs, std::mt19937& rng);

    void renderIcicles(RenderContext& ctx, MeteorColorScheme colorScheme,
                       int count, int length, int swirlIntensity, int speed,
                       bool showBackground, int warmupFrames,
                       float frameTimeMs, std::mt19937& rng);
};

} // namespace xlCore
