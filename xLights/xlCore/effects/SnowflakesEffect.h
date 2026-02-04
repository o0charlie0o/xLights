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
 * @file SnowflakesEffect.h
 * @brief Snowflakes particle effect for xlCore.
 *
 * This effect simulates falling snowflakes with various modes:
 * - Driving: Snowflakes move diagonally across screen
 * - Falling: Snowflakes fall straight down
 * - Falling & Accumulating: Snowflakes pile up at bottom
 *
 * Supports multiple snowflake shapes/types and variable speeds.
 */

#include <vector>
#include <random>
#include <cmath>

#include "../Effect.h"
#include "../Color.h"

namespace xlCore {

/**
 * @brief Snowflake falling mode.
 */
enum class SnowfallMode {
    Driving,                ///< Diagonal movement across screen
    Falling,                ///< Fall straight down, disappear at bottom
    FallingAccumulating     ///< Fall and pile up at bottom
};

/**
 * @brief Snowflake shape/type.
 *
 * Different snowflake patterns from simple dots to complex shapes.
 */
enum class SnowflakeType {
    Random = 0,         ///< Random selection of types
    SingleNode = 1,     ///< Single pixel
    Plus5 = 2,          ///< 5 nodes in + shape
    Plus3 = 3,          ///< 3 nodes in line
    Plus9 = 4,          ///< 9 nodes in + shape
    Star13 = 5,         ///< 13 node star
    Square4 = 6,        ///< 2x2 square
    Cross5 = 7,         ///< 5 node cross
    Diamond13 = 8,      ///< 13 node diamond
    X5 = 9              ///< 5 node X shape
};

/**
 * @brief Single snowflake particle.
 */
struct SnowflakeParticle {
    int x = 0;                          ///< Current X position
    int y = 0;                          ///< Current Y position
    SnowflakeType type = SnowflakeType::SingleNode;  ///< Shape type
    bool settled = false;               ///< Has settled at bottom (accumulating mode)
};

/**
 * @brief Snowflakes effect state.
 */
struct SnowflakesState {
    std::vector<std::vector<SnowflakeParticle>> tempBuffer;  ///< Pixel state buffer
    int lastCount = 0;
    int lastType = 0;
    std::string lastMode;
    int effectState = 0;
    int width = 0;
    int height = 0;
};

/**
 * @brief Snowflakes particle effect.
 *
 * Creates falling snowflake particles with configurable:
 * - Snowflake count
 * - Snowflake type/shape
 * - Falling speed
 * - Falling mode (driving, falling, accumulating)
 * - Warmup frames for pre-filling screen
 */
class SnowflakesEffect : public Effect {
public:
    SnowflakesEffect() = default;
    ~SnowflakesEffect() override = default;

    // ========== Identity ==========
    std::string name() const override { return "Snowflakes"; }
    std::string description() const override {
        return "Falling snowflakes with various shapes";
    }
    std::string category() const override { return "Particle"; }
    std::string tooltip() const override { return "Snow Flakes"; }

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
        return std::make_unique<SnowflakesEffect>(*this);
    }

private:
    mutable SnowflakesState _state;

    /**
     * @brief Initialize or resize the state buffer.
     */
    void initializeBuffer(int width, int height);

    /**
     * @brief Clear a pixel in the state buffer.
     */
    void clearBufferPixel(int x, int y);

    /**
     * @brief Set a pixel in the state buffer.
     */
    void setBufferPixel(int x, int y, const SnowflakeParticle& flake);

    /**
     * @brief Get pixel from state buffer.
     */
    bool getBufferPixel(int x, int y, SnowflakeParticle& flake) const;

    /**
     * @brief Check possible downward moves for a position.
     * @return Bitmask: 1=down-left, 2=down, 4=down-right
     */
    int possibleDownwardMoves(int x, int y) const;

    /**
     * @brief Move snowflakes for falling/accumulating modes.
     */
    void moveFlakes(RenderContext& ctx, SnowflakeType type, SnowfallMode mode,
                    int count, const Color& color1, std::mt19937& rng);

    /**
     * @brief Place initial snowflakes.
     */
    void placeInitialFlakes(RenderContext& ctx, int count, SnowflakeType type,
                            SnowfallMode mode, const Color& color1, std::mt19937& rng);

    /**
     * @brief Draw a snowflake shape at position.
     */
    void drawSnowflake(RenderContext& ctx, int x, int y, SnowflakeType type,
                       const Color& color1, const Color& color2, bool wrapX);

    /**
     * @brief Render driving mode (diagonal movement).
     */
    void renderDriving(RenderContext& ctx, int count, SnowflakeType type, int speed,
                       const Color& color1, const Color& color2, const RenderState& state);

    /**
     * @brief Render falling/accumulating modes.
     */
    void renderFalling(RenderContext& ctx, int count, SnowflakeType type, int speed,
                       SnowfallMode mode, const Color& color1, const Color& color2,
                       int warmupFrames, std::mt19937& rng, const RenderState& state);
};

} // namespace xlCore
