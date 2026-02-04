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
 * @file KaleidoscopeEffect.h
 * @brief Kaleidoscope effect for xlCore - mirror/reflection patterns.
 *
 * Creates kaleidoscope mirror patterns by reflecting a source region
 * across multiple axes. Works on canvas mode where underlying effects
 * provide the source imagery.
 *
 * Supports two reflection modes:
 * - Triangle: Hexagonal symmetry using triangular tiles
 * - Square: Rectangular symmetry using square tiles
 */

#include "../Effect.h"
#include "../Math.h"
#include <vector>
#include <list>
#include <unordered_map>

namespace xlCore {

// Parameter limits
constexpr int KALEIDOSCOPE_X_MIN = 0;
constexpr int KALEIDOSCOPE_X_MAX = 100;
constexpr int KALEIDOSCOPE_Y_MIN = 0;
constexpr int KALEIDOSCOPE_Y_MAX = 100;
constexpr int KALEIDOSCOPE_SIZE_MIN = 2;
constexpr int KALEIDOSCOPE_SIZE_MAX = 100;
constexpr int KALEIDOSCOPE_ROTATION_MIN = 0;
constexpr int KALEIDOSCOPE_ROTATION_MAX = 359;

/**
 * @brief Edge for kaleidoscope reflection.
 */
struct KaleidoscopeEdge {
    Point2D p1;
    Point2D p2;

    KaleidoscopeEdge(const Point2D& pt1, const Point2D& pt2) : p1(pt1), p2(pt2) {}
};

/**
 * @brief Cached state for kaleidoscope rendering.
 */
struct KaleidoscopeState {
    int size = -1;
    int rotation = -1;
    int x = -1;
    int y = -1;
    int width = -1;
    int height = -1;

    std::vector<std::vector<bool>> startUsed;
    std::vector<KaleidoscopeEdge> edges;

    bool needsReinit(int newSize, int newRotation, int newX, int newY,
                    int newWidth, int newHeight) const {
        return size != newSize || rotation != newRotation ||
               x != newX || y != newY ||
               width != newWidth || height != newHeight;
    }
};

/**
 * @brief Kaleidoscope effect - creates mirror/reflection patterns.
 *
 * Parameters:
 * - Type: Pattern type (Triangle, Square)
 * - X: Center X position (0-100%)
 * - Y: Center Y position (0-100%)
 * - Size: Size of reflection tile (2-100)
 * - Rotation: Rotation angle in degrees (0-359)
 *
 * NOTE: This effect is designed to work in canvas mode where it
 * reflects/mirrors the underlying effect layers.
 */
class KaleidoscopeEffect : public Effect {
public:
    KaleidoscopeEffect() = default;
    ~KaleidoscopeEffect() override = default;

    // Identity
    std::string name() const override { return "Kaleidoscope"; }
    std::string description() const override {
        return "Creates kaleidoscope mirror patterns from underlying effects";
    }
    std::string category() const override { return "Patterns"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<KaleidoscopeEffect>(*this);
    }

    // Capabilities
    bool canBeRandom() const override { return false; }
    bool supportsLinearColorCurves(const EffectSettings& settings) const override { return false; }
    int colorSupportedCount() const override { return 0; }

    // Lifecycle
    void cleanupAfterRender() override;

private:
    /**
     * @brief Get or create state for an effect instance.
     */
    KaleidoscopeState& getState(const void* instanceKey) const;

    /**
     * @brief Initialize state for square reflection pattern.
     */
    void initializeSquare(KaleidoscopeState& state, int size, int rotation,
                         int x, int y, int width, int height) const;

    /**
     * @brief Initialize state for triangle reflection pattern.
     */
    void initializeTriangle(KaleidoscopeState& state, int size, int rotation,
                           int x, int y, int width, int height) const;

    /**
     * @brief Create a reflection edge if it intersects the buffer.
     */
    bool createEdge(KaleidoscopeState& state, int x1, int y1, int x2, int y2) const;

    /**
     * @brief Check if a point is above a line through two points.
     */
    static bool isPointAboveLine(int x, int y, int x1, int y1, int x2, int y2);

    /**
     * @brief Get a point after moving at an angle and distance.
     */
    static Point2D getPointAfterMove(int x, int y, int degrees, double distance);

    /**
     * @brief Get the source location after reflection across an edge.
     */
    static Point2D getSourceLocation(int x, int y, const KaleidoscopeEdge& edge);

    /**
     * @brief Check if all pixels have been filled.
     */
    static bool isDone(const std::vector<std::vector<bool>>& used);

    // Mutable state storage (keyed by effect instance pointer)
    mutable std::unordered_map<const void*, KaleidoscopeState> m_states;
};

} // namespace xlCore
