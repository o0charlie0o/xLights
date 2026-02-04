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
 * @file TendrilEffect.h
 * @brief Tendril effect for xlCore - organic flowing tendril animation.
 *
 * This effect simulates organic tendrils that flow and follow a target point.
 * The tendrils use a physics-based spring simulation for natural movement.
 *
 * Supports multiple movement patterns:
 * - Random: Target moves randomly
 * - Square: Target traces a square path
 * - Circle: Target traces a circular path
 * - Horizontal/Vertical Zig Zag: Target zigzags across the buffer
 * - Manual: User-controlled target position
 * - Music reactive: Target responds to audio (placeholder)
 */

#include "../Effect.h"
#include "../Math.h"
#include <list>
#include <vector>
#include <random>
#include <unordered_map>

namespace xlCore {

// Parameter limits
constexpr int TENDRIL_MOVEMENT_MIN = 0;
constexpr int TENDRIL_MOVEMENT_MAX = 20;
constexpr int TENDRIL_THICKNESS_MIN = 1;
constexpr int TENDRIL_THICKNESS_MAX = 20;
constexpr int TENDRIL_MANUALX_MIN = 0;
constexpr int TENDRIL_MANUALX_MAX = 100;
constexpr int TENDRIL_MANUALY_MIN = 0;
constexpr int TENDRIL_MANUALY_MAX = 100;
constexpr int TENDRIL_OFFSETX_MIN = -100;
constexpr int TENDRIL_OFFSETX_MAX = 100;
constexpr int TENDRIL_OFFSETY_MIN = -100;
constexpr int TENDRIL_OFFSETY_MAX = 100;

/**
 * @brief Movement pattern types for tendril animation.
 */
enum class TendrilMovement {
    Random = 1,
    Square = 2,
    Circle = 3,
    HorizontalZigZag = 4,
    VerticalZigZag = 5,
    MusicLine = 6,
    MusicCircle = 7,
    VertZigZagReturn = 8,
    HorizZigZagReturn = 9,
    Manual = 10
};

/**
 * @brief A single node in a tendril chain.
 *
 * Each node has position and velocity, connected by springs.
 */
struct TendrilNode {
    float x = 0.0f;
    float y = 0.0f;
    float vx = 0.0f;
    float vy = 0.0f;

    TendrilNode() = default;
    TendrilNode(float x_, float y_) : x(x_), y(y_), vx(0), vy(0) {}

    Point2D toPoint() const {
        return Point2D(static_cast<int>(std::round(x)), static_cast<int>(std::round(y)));
    }
};

/**
 * @brief A single tendril - chain of nodes connected by springs.
 */
class SingleTendril {
public:
    SingleTendril(float friction, int size, float dampening, float tension, float spring, const Point2D& start);
    ~SingleTendril() = default;

    /**
     * @brief Update tendril physics towards target point.
     */
    void update(const Point2D& target, int tunemovement, int width, int height);

    /**
     * @brief Draw the tendril to the render context using quadratic curves.
     */
    void draw(RenderContext& ctx, const Color& color, int thickness) const;

    /**
     * @brief Get the position of the last node (tail).
     */
    Point2D lastLocation() const;

private:
    std::vector<TendrilNode> m_nodes;
    float m_friction;
    float m_dampening;
    float m_tension;
    float m_spring;
    int m_lastWidth = -1;
    int m_lastHeight = -1;
};

/**
 * @brief A collection of tendrils with varying spring constants.
 */
class TendrilGroup {
public:
    TendrilGroup(float friction, int trails, int size, float dampening,
                 float tension, float springbase, float springincr, const Point2D& start);
    ~TendrilGroup() = default;

    /**
     * @brief Update all tendrils with random movement.
     */
    void updateRandomMove(int tunemovement, int width, int height, std::mt19937& rng);

    /**
     * @brief Update all tendrils towards a target.
     */
    void update(const Point2D& target, int tunemovement, int width, int height);
    void update(int x, int y, int tunemovement, int width, int height);

    /**
     * @brief Draw all tendrils to the render context.
     */
    void draw(RenderContext& ctx, const Color& color, int thickness) const;

private:
    std::vector<SingleTendril> m_tendrils;
};

/**
 * @brief Persistent state for a tendril effect instance.
 */
struct TendrilState {
    std::unique_ptr<TendrilGroup> tendril;
    int mv1 = 0;  // Movement state variable 1
    int mv2 = 0;  // Movement state variable 2
    int mv3 = 0;  // Movement state variable 3
    int mv4 = 0;  // Movement state variable 4
    std::mt19937 rng;
    bool initialized = false;
};

/**
 * @brief Tendril effect - organic flowing tendrils.
 *
 * Parameters:
 * - Movement: Movement pattern (Random, Square, Circle, etc.)
 * - TuneMovement: Movement speed/amount (0-20)
 * - Speed: Animation speed (1-10)
 * - Thickness: Line thickness (1-20)
 * - Friction: Physics friction (0.4-0.6)
 * - Dampening: Spring dampening (0.0-0.5)
 * - Tension: Spring tension (0.96-0.999)
 * - Trails: Number of trail tendrils (1-10)
 * - Length: Tendril length in nodes (10-100)
 * - XOffset, YOffset: Position offset (-100 to 100)
 * - ManualX, ManualY: Manual target position (0-100)
 */
class TendrilEffect : public Effect {
public:
    TendrilEffect() = default;
    ~TendrilEffect() override = default;

    // Identity
    std::string name() const override { return "Tendril"; }
    std::string description() const override {
        return "Organic flowing tendrils that follow movement patterns";
    }
    std::string category() const override { return "Organic"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<TendrilEffect>(*this);
    }

    // Capabilities
    bool appropriateOnNodes() const override { return false; }
    bool supportsRenderCache(const EffectSettings& settings) const override { return true; }
    int colorSupportedCount() const override { return 1; }

    // Lifecycle
    void cleanupAfterRender() override;

private:
    /**
     * @brief Get or create state for an effect instance.
     */
    TendrilState& getState(const void* instanceKey) const;

    /**
     * @brief Encode movement string to enum value.
     */
    static TendrilMovement encodeMovement(const std::string& movement);

    /**
     * @brief Get color blended from palette based on progress.
     */
    static Color getBlendedColor(const std::vector<Color>& palette, double progress);

    // Mutable state storage (keyed by effect instance pointer)
    mutable std::unordered_map<const void*, TendrilState> m_states;
};

} // namespace xlCore
