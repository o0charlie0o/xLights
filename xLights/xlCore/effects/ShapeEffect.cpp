/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "ShapeEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../XLMath.h"

#include <cmath>
#include <random>
#include <algorithm>

namespace xlCore {

namespace {
    // Thread-local random number generator
    thread_local std::mt19937 rng{std::random_device{}()};
    thread_local std::uniform_real_distribution<float> dist01(0.0f, 1.0f);

    float rand01() {
        return dist01(rng);
    }
}

std::vector<EffectParameter> ShapeEffect::parameters() const {
    return {
        EffectParameter::createChoice(
            "E_CHOICE_Shape_ObjectToDraw",
            "Shape",
            "Circle",
            {"Circle", "Square", "Triangle", "Star", "Pentagon", "Hexagon", "Octagon", "Heart", "Tree", "Candy Cane", "Snowflake", "Crucifix", "Present", "Ellipse"}
        ),
        EffectParameter::createInt(
            "E_SLIDER_Shape_Thickness",
            "Thickness",
            1, SHAPE_THICKNESS_MIN, SHAPE_THICKNESS_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Shape_StartSize",
            "Start Size",
            1, SHAPE_STARTSIZE_MIN, SHAPE_STARTSIZE_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Shape_CentreX",
            "Center X",
            50, SHAPE_CENTREX_MIN, SHAPE_CENTREX_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Shape_CentreY",
            "Center Y",
            50, SHAPE_CENTREY_MIN, SHAPE_CENTREY_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Shape_Points",
            "Points",
            5, 3, 10,
            false
        ),
        EffectParameter::createInt(
            "E_SLIDER_Shape_Count",
            "Count",
            5, SHAPE_COUNT_MIN, SHAPE_COUNT_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Shape_Growth",
            "Growth",
            10, SHAPE_GROWTH_MIN, SHAPE_GROWTH_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Shape_Lifetime",
            "Lifetime",
            5, SHAPE_LIFETIME_MIN, SHAPE_LIFETIME_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Shape_Rotation",
            "Rotation",
            0, SHAPE_ROTATION_MIN, SHAPE_ROTATION_MAX,
            true
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_Shape_RandomLocation",
            "Random Location",
            true
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_Shape_FadeAway",
            "Fade Away",
            true
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_Shape_RandomInitial",
            "Random Initial",
            true
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_Shape_HoldColour",
            "Hold Colour",
            true
        )
    };
}

ShapeEffect::ShapeType ShapeEffect::parseShapeType(const std::string& shape) {
    if (shape == "Circle") return ShapeType::Circle;
    if (shape == "Square") return ShapeType::Square;
    if (shape == "Triangle") return ShapeType::Triangle;
    if (shape == "Star") return ShapeType::Star;
    if (shape == "Pentagon") return ShapeType::Pentagon;
    if (shape == "Hexagon") return ShapeType::Hexagon;
    if (shape == "Octagon") return ShapeType::Octagon;
    if (shape == "Heart") return ShapeType::Heart;
    if (shape == "Tree") return ShapeType::Tree;
    if (shape == "Candy Cane") return ShapeType::CandyCane;
    if (shape == "Snowflake") return ShapeType::Snowflake;
    if (shape == "Crucifix") return ShapeType::Crucifix;
    if (shape == "Present") return ShapeType::Present;
    if (shape == "Ellipse") return ShapeType::Ellipse;
    return ShapeType::Circle;
}

void ShapeEffect::prepareForRender(const EffectSettings& settings) {
    m_shapes.clear();
    m_lastColorIdx = -1;
    m_initialized = false;
}

void ShapeEffect::cleanupAfterRender() {
    m_shapes.clear();
    m_lastColorIdx = -1;
    m_initialized = false;
}

void ShapeEffect::drawCircle(RenderContext& ctx, int xc, int yc, double radius, const Color& color, int thickness) const {
    double interpolation = 0.75;
    double t = static_cast<double>(thickness) - 1.0 + interpolation;

    for (double i = 0; i < t; i += interpolation) {
        if (radius >= 0) {
            for (double degrees = 0.0; degrees < 360.0; degrees += 1.0) {
                double radian = degrees * (math::PI / 180.0);
                int x = static_cast<int>(std::round(radius * std::cos(radian))) + xc;
                int y = static_cast<int>(std::round(radius * std::sin(radian))) + yc;
                ctx.setPixel(x, y, color);
            }
        } else {
            break;
        }
        radius -= interpolation;
    }
}

void ShapeEffect::drawPolygon(RenderContext& ctx, int xc, int yc, double radius, int sides, const Color& color, int thickness, double rotation) const {
    double interpolation = 0.05;
    double t = static_cast<double>(thickness) - 1.0 + interpolation;
    double increment = 360.0 / sides;

    for (double i = 0; i < t; i += interpolation) {
        if (radius >= 0) {
            for (double degrees = 0.0; degrees < 361.0; degrees += increment) {
                double deg = degrees > 360.0 ? 360.0 : degrees;
                double radian = (rotation + deg) * math::PI / 180.0;
                int x1 = static_cast<int>(std::round(radius * std::cos(radian))) + xc;
                int y1 = static_cast<int>(std::round(radius * std::sin(radian))) + yc;

                radian = (rotation + deg + increment) * math::PI / 180.0;
                int x2 = static_cast<int>(std::round(radius * std::cos(radian))) + xc;
                int y2 = static_cast<int>(std::round(radius * std::sin(radian))) + yc;

                ctx.drawLine(x1, y1, x2, y2, color);
            }
        } else {
            break;
        }
        radius -= interpolation;
    }
}

void ShapeEffect::drawStar(RenderContext& ctx, int xc, int yc, double radius, int points, const Color& color, int thickness, double rotation) const {
    double interpolation = 0.6;
    double t = static_cast<double>(thickness) - 1.0 + interpolation;
    double offsetangle = 0.0;

    switch (points) {
        case 5: offsetangle = 90.0 - 360.0 / 5.0; break;
        case 6: offsetangle = 30.0; break;
        case 7: offsetangle = 90.0 - 360.0 / 7.0; break;
        default: break;
    }

    for (double i = 0; i < t; i += interpolation) {
        if (radius >= 0) {
            double innerRadius = radius / 2.618034;  // Golden ratio squared
            double increment = 360.0 / points;

            for (double degrees = 0.0; degrees < 361.0; degrees += increment) {
                double deg = degrees > 360.0 ? 360.0 : degrees;
                double radian = (rotation + offsetangle + deg) * (math::PI / 180.0);
                int xouter = static_cast<int>(std::round(radius * std::cos(radian))) + xc;
                int youter = static_cast<int>(std::round(radius * std::sin(radian))) + yc;

                radian = (rotation + offsetangle + deg + increment / 2.0) * (math::PI / 180.0);
                int xinner = static_cast<int>(std::round(innerRadius * std::cos(radian))) + xc;
                int yinner = static_cast<int>(std::round(innerRadius * std::sin(radian))) + yc;

                ctx.drawLine(xinner, yinner, xouter, youter, color);

                radian = (rotation + offsetangle + deg - increment / 2.0) * (math::PI / 180.0);
                xinner = static_cast<int>(std::round(innerRadius * std::cos(radian))) + xc;
                yinner = static_cast<int>(std::round(innerRadius * std::sin(radian))) + yc;

                ctx.drawLine(xinner, yinner, xouter, youter, color);
            }
        } else {
            break;
        }
        radius -= interpolation;
    }
}

void ShapeEffect::drawHeart(RenderContext& ctx, int xc, int yc, double radius, const Color& color, int thickness, double rotation) const {
    double interpolation = 0.75;
    double t = static_cast<double>(thickness) - 1.0 + interpolation;
    double radRot = rotation * (math::PI / 180.0);

    double xincr = 0.01;
    for (double x = -2.0; x <= 2.0; x += xincr) {
        double y1 = std::sqrt(1.0 - (std::abs(x) - 1.0) * (std::abs(x) - 1.0));
        double y2 = std::acos(1.0 - std::abs(x)) - math::PI;

        double r = radius;

        for (double i = 0.0; i < t; i += interpolation) {
            if (r >= 0.0) {
                double xx = (x * r) / 2.0;
                double yy1 = (y1 * r) / 2.0;
                double yy2 = (y2 * r) / 2.0;

                // Apply rotation
                double rx1 = (xx * std::cos(radRot)) - (yy1 * std::sin(radRot)) + xc;
                double ry1 = (yy1 * std::cos(radRot)) + (xx * std::sin(radRot)) + yc;
                double rx2 = (xx * std::cos(radRot)) - (yy2 * std::sin(radRot)) + xc;
                double ry2 = (yy2 * std::cos(radRot)) + (xx * std::sin(radRot)) + yc;

                ctx.setPixel(static_cast<int>(std::round(rx1)), static_cast<int>(std::round(ry1)), color);
                ctx.setPixel(static_cast<int>(std::round(rx2)), static_cast<int>(std::round(ry2)), color);
            } else {
                break;
            }
            r -= interpolation;
        }
    }
}

void ShapeEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    std::string objectStr = settings.get("E_CHOICE_Shape_ObjectToDraw", "Circle");
    int thickness = settings.getInt("E_SLIDER_Shape_Thickness", 1);
    int points = settings.getInt("E_SLIDER_Shape_Points", 5);
    bool randomLocation = settings.getBool("E_CHECKBOX_Shape_RandomLocation", true);
    bool fadeAway = settings.getBool("E_CHECKBOX_Shape_FadeAway", true);
    bool startRandomly = settings.getBool("E_CHECKBOX_Shape_RandomInitial", true);
    bool holdColour = settings.getBool("E_CHECKBOX_Shape_HoldColour", true);
    int xc = settings.getInt("E_SLIDER_Shape_CentreX", 50) * ctx.width() / 100;
    int yc = settings.getInt("E_SLIDER_Shape_CentreY", 50) * ctx.height() / 100;
    int lifetime = settings.getInt("E_SLIDER_Shape_Lifetime", 5);
    int growth = settings.getInt("E_SLIDER_Shape_Growth", 10);
    int count = settings.getInt("E_SLIDER_Shape_Count", 5);
    int startSize = settings.getInt("E_SLIDER_Shape_StartSize", 1);
    int rotation = settings.getInt("E_SLIDER_Shape_Rotation", 0);

    ShapeType objectType = parseShapeType(objectStr);

    // Calculate lifetime in frames
    float lifetimeFrames = static_cast<float>(state.totalFrames) * lifetime / 100.0f;
    if (lifetimeFrames < 1) lifetimeFrames = 1;
    float growthPerFrame = static_cast<float>(growth) / lifetimeFrames;

    // Default colors
    std::vector<Color> colors = { Color::White(), Color::Red(), Color::Blue(), Color::Green() };
    size_t colorCount = colors.size();

    // Initialize shapes if needed
    if (!m_initialized) {
        m_initialized = true;
        m_shapes.clear();
        m_lastColorIdx = -1;

        for (int i = 0; i < count; ++i) {
            int px, py;
            if (randomLocation) {
                px = static_cast<int>(rand01() * ctx.width());
                py = static_cast<int>(rand01() * ctx.height());
            } else {
                px = xc;
                py = yc;
            }

            m_lastColorIdx++;
            if (m_lastColorIdx >= static_cast<int>(colorCount)) {
                m_lastColorIdx = 0;
            }

            int ofs = 0;
            if (startRandomly) {
                ofs = static_cast<int>(rand01() * lifetimeFrames);
            }

            m_shapes.emplace_back(px, py, startSize + ofs * growthPerFrame, ofs, objectType, static_cast<float>(rotation), m_lastColorIdx, holdColour);
        }
    }

    // Create missing shapes
    while (static_cast<int>(m_shapes.size()) < count) {
        int px, py;
        if (randomLocation) {
            px = static_cast<int>(rand01() * ctx.width());
            py = static_cast<int>(rand01() * ctx.height());
        } else {
            px = xc;
            py = yc;
        }

        m_lastColorIdx++;
        if (m_lastColorIdx >= static_cast<int>(colorCount)) {
            m_lastColorIdx = 0;
        }

        m_shapes.emplace_back(px, py, static_cast<float>(startSize), 0, objectType, static_cast<float>(rotation), m_lastColorIdx, holdColour);
    }

    // Render all shapes
    for (auto& shape : m_shapes) {
        // Update location if not random
        if (!randomLocation) {
            shape.centerX = xc;
            shape.centerY = yc;
        }

        Color color = colors[shape.colorIndex % colorCount];

        // Apply fade
        if (fadeAway) {
            float brightness = (lifetimeFrames - shape.offsetFrame) / lifetimeFrames;
            brightness = std::max(0.0f, std::min(1.0f, brightness));

            if (ctx.allowAlpha()) {
                color.setAlpha(static_cast<uint8_t>(255.0f * brightness));
            } else {
                color = Color(
                    static_cast<uint8_t>(color.red * brightness),
                    static_cast<uint8_t>(color.green * brightness),
                    static_cast<uint8_t>(color.blue * brightness)
                );
            }
        }

        // Draw shape
        switch (shape.type) {
            case ShapeType::Circle:
                drawCircle(ctx, shape.centerX, shape.centerY, shape.size, color, thickness);
                break;
            case ShapeType::Square:
                drawPolygon(ctx, shape.centerX, shape.centerY, shape.size, 4, color, thickness, rotation + 45.0);
                break;
            case ShapeType::Triangle:
                drawPolygon(ctx, shape.centerX, shape.centerY, shape.size, 3, color, thickness, rotation + 90.0);
                break;
            case ShapeType::Star:
                drawStar(ctx, shape.centerX, shape.centerY, shape.size, points, color, thickness, rotation);
                break;
            case ShapeType::Pentagon:
                drawPolygon(ctx, shape.centerX, shape.centerY, shape.size, 5, color, thickness, rotation + 90.0);
                break;
            case ShapeType::Hexagon:
                drawPolygon(ctx, shape.centerX, shape.centerY, shape.size, 6, color, thickness, rotation);
                break;
            case ShapeType::Octagon:
                drawPolygon(ctx, shape.centerX, shape.centerY, shape.size, 8, color, thickness, rotation + 22.5);
                break;
            case ShapeType::Heart:
                drawHeart(ctx, shape.centerX, shape.centerY, shape.size, color, thickness, rotation);
                break;
            default:
                // For other shapes, fall back to circle
                drawCircle(ctx, shape.centerX, shape.centerY, shape.size, color, thickness);
                break;
        }

        // Update shape for next frame
        shape.offsetFrame++;
        shape.size += growthPerFrame;
        if (shape.size < 0) shape.size = 0;
    }

    // Remove old shapes
    m_shapes.remove_if([lifetimeFrames](const ShapeData& s) {
        return s.offsetFrame > lifetimeFrames;
    });
}

// Register the effect
XLCORE_REGISTER_EFFECT(ShapeEffect)

} // namespace xlCore
