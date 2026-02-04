/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "SphereEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../XLMath.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

std::vector<EffectParameter> SphereEffect::parameters() const {
    return {
        EffectParameter::createInt(
            "E_SLIDER_Sphere_RotationX",
            "Rotation X",
            0, SPHERE_ROTATION_MIN, SPHERE_ROTATION_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Sphere_RotationY",
            "Rotation Y",
            0, SPHERE_ROTATION_MIN, SPHERE_ROTATION_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Sphere_Speed",
            "Speed",
            10, SPHERE_SPEED_MIN, SPHERE_SPEED_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Sphere_Latitude",
            "Latitude Lines",
            20, SPHERE_LATITUDE_MIN, SPHERE_LATITUDE_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Sphere_Longitude",
            "Longitude Lines",
            20, SPHERE_LONGITUDE_MIN, SPHERE_LONGITUDE_MAX,
            true
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_Sphere_Filled",
            "Filled",
            true
        )
    };
}

void SphereEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int rotationX = settings.getInt("E_SLIDER_Sphere_RotationX", 0);
    int rotationY = settings.getInt("E_SLIDER_Sphere_RotationY", 0);
    int speed = settings.getInt("E_SLIDER_Sphere_Speed", 10);
    int latLines = settings.getInt("E_SLIDER_Sphere_Latitude", 20);
    int lonLines = settings.getInt("E_SLIDER_Sphere_Longitude", 20);
    bool filled = settings.getBool("E_CHECKBOX_Sphere_Filled", true);

    int bufferWi = ctx.width();
    int bufferHt = ctx.height();

    // Calculate center and radius
    float xc = static_cast<float>(bufferWi) / 2.0f;
    float yc = static_cast<float>(bufferHt) / 2.0f;
    float radius = std::min(xc, yc) * 0.9f;

    // Calculate animation state
    int frameTimeMs = 50;  // Assume 50ms frame time
    float animationAngle = static_cast<float>(state.frameIndex * speed * frameTimeMs) / 5000.0f;

    // Convert rotations to radians and add animation
    float rotX = math::toRadians(static_cast<float>(rotationX)) + animationAngle;
    float rotY = math::toRadians(static_cast<float>(rotationY)) + animationAngle * 0.7f;

    // Build rotation matrices
    Mat4 rotationMat = Mat4::rotateX(rotX) * Mat4::rotateY(rotY);

    // Default sphere color (white gradient based on depth)
    Color baseColor = Color::White();

    // Render the sphere using latitude/longitude grid
    for (int lat = 0; lat <= latLines; lat++) {
        float theta = static_cast<float>(lat) * math::PI / static_cast<float>(latLines);
        float sinTheta = std::sin(theta);
        float cosTheta = std::cos(theta);

        for (int lon = 0; lon <= lonLines; lon++) {
            float phi = static_cast<float>(lon) * math::TWO_PI / static_cast<float>(lonLines);
            float sinPhi = std::sin(phi);
            float cosPhi = std::cos(phi);

            // Calculate 3D point on unit sphere
            Vec3 point(
                sinTheta * cosPhi,
                cosTheta,
                sinTheta * sinPhi
            );

            // Apply rotation
            Vec3 rotated = rotationMat.transformPoint(point);

            // Scale by radius and translate to center
            float x = rotated.x * radius + xc;
            float y = rotated.y * radius + yc;
            float z = rotated.z;  // Used for depth shading

            // Only draw if on the front face (z > 0 after rotation)
            if (z > -0.1f || filled) {
                // Calculate color based on depth (z coordinate)
                float brightness = filled ? (z + 1.0f) / 2.0f : 1.0f;
                brightness = std::max(0.2f, brightness);

                // Use hue based on longitude for color variation
                float hue = static_cast<float>(lon) / static_cast<float>(lonLines);
                Color color = Color::fromHSV(hue, 0.7f, brightness);

                int px = static_cast<int>(x);
                int py = static_cast<int>(y);

                if (px >= 0 && px < bufferWi && py >= 0 && py < bufferHt) {
                    ctx.setPixel(px, py, color);
                }
            }
        }
    }

    // Draw longitude lines (meridians) if not filled
    if (!filled) {
        for (int lon = 0; lon < lonLines; lon++) {
            float phi = static_cast<float>(lon) * math::TWO_PI / static_cast<float>(lonLines);
            float sinPhi = std::sin(phi);
            float cosPhi = std::cos(phi);

            int prevX = -1, prevY = -1;
            bool prevVisible = false;

            for (int lat = 0; lat <= latLines * 2; lat++) {
                float theta = static_cast<float>(lat) * math::PI / static_cast<float>(latLines * 2);
                float sinTheta = std::sin(theta);
                float cosTheta = std::cos(theta);

                Vec3 point(sinTheta * cosPhi, cosTheta, sinTheta * sinPhi);
                Vec3 rotated = rotationMat.transformPoint(point);

                float x = rotated.x * radius + xc;
                float y = rotated.y * radius + yc;
                bool visible = rotated.z > 0.0f;

                int px = static_cast<int>(x);
                int py = static_cast<int>(y);

                if (visible && prevVisible && prevX >= 0) {
                    float hue = static_cast<float>(lon) / static_cast<float>(lonLines);
                    Color color = Color::fromHSV(hue, 0.8f, 1.0f);
                    ctx.drawLine(prevX, prevY, px, py, color);
                }

                prevX = px;
                prevY = py;
                prevVisible = visible;
            }
        }

        // Draw latitude lines (parallels)
        for (int lat = 1; lat < latLines; lat++) {
            float theta = static_cast<float>(lat) * math::PI / static_cast<float>(latLines);
            float sinTheta = std::sin(theta);
            float cosTheta = std::cos(theta);

            int prevX = -1, prevY = -1;
            bool prevVisible = false;

            for (int lon = 0; lon <= lonLines * 2; lon++) {
                float phi = static_cast<float>(lon) * math::TWO_PI / static_cast<float>(lonLines * 2);
                float sinPhi = std::sin(phi);
                float cosPhi = std::cos(phi);

                Vec3 point(sinTheta * cosPhi, cosTheta, sinTheta * sinPhi);
                Vec3 rotated = rotationMat.transformPoint(point);

                float x = rotated.x * radius + xc;
                float y = rotated.y * radius + yc;
                bool visible = rotated.z > 0.0f;

                int px = static_cast<int>(x);
                int py = static_cast<int>(y);

                if (visible && prevVisible && prevX >= 0) {
                    float brightness = (rotated.z + 1.0f) / 2.0f;
                    Color color = Color::fromHSV(0.0f, 0.0f, brightness);
                    ctx.drawLine(prevX, prevY, px, py, color);
                }

                prevX = px;
                prevY = py;
                prevVisible = visible;
            }
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(SphereEffect)

} // namespace xlCore
