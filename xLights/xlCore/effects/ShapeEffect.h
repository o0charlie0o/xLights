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
 * @file ShapeEffect.h
 * @brief Shape effect for xlCore - draws geometric shapes.
 *
 * This effect draws various geometric shapes that can grow, move,
 * and fade over their lifetime. Supports circles, squares, stars,
 * hearts, and other shapes.
 */

#include "../Effect.h"

#include <vector>
#include <list>

namespace xlCore {

// Parameter limits
constexpr int SHAPE_THICKNESS_MIN = 1;
constexpr int SHAPE_THICKNESS_MAX = 100;

constexpr int SHAPE_STARTSIZE_MIN = 0;
constexpr int SHAPE_STARTSIZE_MAX = 100;

constexpr int SHAPE_CENTREX_MIN = 0;
constexpr int SHAPE_CENTREX_MAX = 100;

constexpr int SHAPE_CENTREY_MIN = 0;
constexpr int SHAPE_CENTREY_MAX = 100;

constexpr int SHAPE_LIFETIME_MIN = 1;
constexpr int SHAPE_LIFETIME_MAX = 100;

constexpr int SHAPE_GROWTH_MIN = -100;
constexpr int SHAPE_GROWTH_MAX = 100;

constexpr int SHAPE_COUNT_MIN = 1;
constexpr int SHAPE_COUNT_MAX = 100;

constexpr int SHAPE_ROTATION_MIN = 0;
constexpr int SHAPE_ROTATION_MAX = 360;

/**
 * @brief Shape effect - draws geometric shapes.
 *
 * Parameters:
 * - ObjectToDraw: Shape type (Circle, Square, Star, etc.)
 * - Thickness: Line thickness (1-100)
 * - StartSize: Initial size (0-100)
 * - CentreX/Y: Center position (0-100 percentage)
 * - Lifetime: How long shapes live (1-100)
 * - Growth: Size change rate (-100 to 100)
 * - Count: Number of shapes
 * - Rotation: Rotation angle (0-360)
 * - RandomLocation: Randomize positions
 * - FadeAway: Fade out over lifetime
 */
class ShapeEffect : public Effect {
public:
    ShapeEffect() = default;
    ~ShapeEffect() override = default;

    // Identity
    std::string name() const override { return "Shape"; }
    std::string description() const override {
        return "Draws geometric shapes with animation";
    }
    std::string category() const override { return "Utility"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Lifecycle
    void prepareForRender(const EffectSettings& settings) override;
    void cleanupAfterRender() override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<ShapeEffect>(*this);
    }

    // Capabilities
    bool appropriateOnNodes() const override { return false; }
    bool supportsRenderCache(const EffectSettings& settings) const override { return true; }
    int colorSupportedCount() const override { return -1; }

private:
    // Shape type enumeration
    enum class ShapeType {
        Circle = 0,
        Square,
        Triangle,
        Star,
        Pentagon,
        Hexagon,
        Octagon,
        Heart,
        Tree,
        CandyCane,
        Snowflake,
        Crucifix,
        Present,
        Ellipse
    };

    // Internal shape data
    struct ShapeData {
        int centerX;
        int centerY;
        float size;
        int offsetFrame;
        ShapeType type;
        float rotation;
        int colorIndex;
        bool holdColor;

        ShapeData(int cx, int cy, float sz, int ofs, ShapeType t, float rot, int ci, bool hc)
            : centerX(cx), centerY(cy), size(sz), offsetFrame(ofs),
              type(t), rotation(rot), colorIndex(ci), holdColor(hc) {}
    };

    static ShapeType parseShapeType(const std::string& shape);

    // Drawing helpers
    void drawCircle(RenderContext& ctx, int xc, int yc, double radius, const Color& color, int thickness) const;
    void drawPolygon(RenderContext& ctx, int xc, int yc, double radius, int sides, const Color& color, int thickness, double rotation) const;
    void drawStar(RenderContext& ctx, int xc, int yc, double radius, int points, const Color& color, int thickness, double rotation) const;
    void drawHeart(RenderContext& ctx, int xc, int yc, double radius, const Color& color, int thickness, double rotation) const;

    // Render state
    std::list<ShapeData> m_shapes;
    int m_lastColorIdx = -1;
    bool m_initialized = false;
};

} // namespace xlCore
