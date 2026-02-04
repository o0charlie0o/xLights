/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "CubeEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../XLMath.h"

#include <cmath>
#include <algorithm>
#include <array>

namespace xlCore {

std::vector<EffectParameter> CubeEffect::parameters() const {
    return {
        EffectParameter::createInt(
            "E_SLIDER_Cube_RotationX",
            "Rotation X",
            30, CUBE_ROTATION_MIN, CUBE_ROTATION_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Cube_RotationY",
            "Rotation Y",
            30, CUBE_ROTATION_MIN, CUBE_ROTATION_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Cube_RotationZ",
            "Rotation Z",
            0, CUBE_ROTATION_MIN, CUBE_ROTATION_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Cube_Speed",
            "Speed",
            10, CUBE_SPEED_MIN, CUBE_SPEED_MAX,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Cube_Size",
            "Size",
            70, CUBE_SIZE_MIN, CUBE_SIZE_MAX,
            true
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_Cube_Filled",
            "Filled",
            false
        )
    };
}

void CubeEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int rotationX = settings.getInt("E_SLIDER_Cube_RotationX", 30);
    int rotationY = settings.getInt("E_SLIDER_Cube_RotationY", 30);
    int rotationZ = settings.getInt("E_SLIDER_Cube_RotationZ", 0);
    int speed = settings.getInt("E_SLIDER_Cube_Speed", 10);
    int sizePercent = settings.getInt("E_SLIDER_Cube_Size", 70);
    bool filled = settings.getBool("E_CHECKBOX_Cube_Filled", false);

    int bufferWi = ctx.width();
    int bufferHt = ctx.height();

    // Calculate center and size
    float xc = static_cast<float>(bufferWi) / 2.0f;
    float yc = static_cast<float>(bufferHt) / 2.0f;
    float halfSize = std::min(xc, yc) * (static_cast<float>(sizePercent) / 100.0f) * 0.5f;

    // Calculate animation state
    int frameTimeMs = 50;
    float animationAngle = static_cast<float>(state.frameIndex * speed * frameTimeMs) / 5000.0f;

    // Convert rotations to radians and add animation
    float rotX = math::toRadians(static_cast<float>(rotationX)) + animationAngle;
    float rotY = math::toRadians(static_cast<float>(rotationY)) + animationAngle * 0.7f;
    float rotZ = math::toRadians(static_cast<float>(rotationZ)) + animationAngle * 0.3f;

    // Build rotation matrix
    Mat4 rotationMat = Mat4::rotateX(rotX) * Mat4::rotateY(rotY) * Mat4::rotateZ(rotZ);

    // Define cube vertices (unit cube centered at origin)
    std::array<Vec3, 8> vertices = {{
        {-1, -1, -1},
        { 1, -1, -1},
        { 1,  1, -1},
        {-1,  1, -1},
        {-1, -1,  1},
        { 1, -1,  1},
        { 1,  1,  1},
        {-1,  1,  1}
    }};

    // Transform all vertices
    std::array<Vec3, 8> transformed;
    std::array<Point2D, 8> projected;

    for (int i = 0; i < 8; i++) {
        Vec3 v = vertices[i] * halfSize;
        transformed[i] = rotationMat.transformPoint(v);
        projected[i] = Point2D(
            static_cast<int>(transformed[i].x + xc),
            static_cast<int>(transformed[i].y + yc)
        );
    }

    // Define cube edges (pairs of vertex indices)
    std::array<std::pair<int, int>, 12> edges = {{
        {0, 1}, {1, 2}, {2, 3}, {3, 0},  // Back face
        {4, 5}, {5, 6}, {6, 7}, {7, 4},  // Front face
        {0, 4}, {1, 5}, {2, 6}, {3, 7}   // Connecting edges
    }};

    // Face definitions (indices of 4 vertices per face)
    struct Face {
        int v[4];
        Color color;
    };

    std::array<Face, 6> faces = {{
        {{0, 1, 2, 3}, Color(255, 0, 0)},      // Back (red)
        {{4, 5, 6, 7}, Color(0, 255, 0)},      // Front (green)
        {{0, 1, 5, 4}, Color(0, 0, 255)},      // Bottom (blue)
        {{2, 3, 7, 6}, Color(255, 255, 0)},    // Top (yellow)
        {{0, 3, 7, 4}, Color(255, 0, 255)},    // Left (magenta)
        {{1, 2, 6, 5}, Color(0, 255, 255)}     // Right (cyan)
    }};

    if (filled) {
        // Calculate face normals and sort by depth (painter's algorithm)
        struct FaceDepth {
            int index;
            float depth;
            bool visible;
        };

        std::array<FaceDepth, 6> faceDepths;

        for (int i = 0; i < 6; i++) {
            // Calculate face center
            Vec3 center(0, 0, 0);
            for (int j = 0; j < 4; j++) {
                center = center + transformed[faces[i].v[j]];
            }
            center = center / 4.0f;

            // Calculate face normal using cross product
            Vec3 v0 = transformed[faces[i].v[0]];
            Vec3 v1 = transformed[faces[i].v[1]];
            Vec3 v2 = transformed[faces[i].v[2]];
            Vec3 edge1 = v1 - v0;
            Vec3 edge2 = v2 - v0;
            Vec3 normal = edge1.cross(edge2).normalized();

            // Face is visible if normal points toward viewer (z > 0)
            faceDepths[i].index = i;
            faceDepths[i].depth = center.z;
            faceDepths[i].visible = normal.z > 0;
        }

        // Sort faces by depth (back to front)
        std::sort(faceDepths.begin(), faceDepths.end(),
            [](const FaceDepth& a, const FaceDepth& b) {
                return a.depth < b.depth;
            });

        // Draw visible faces
        for (const auto& fd : faceDepths) {
            if (!fd.visible) continue;

            const Face& face = faces[fd.index];

            // Create polygon points
            std::vector<Point2D> poly;
            for (int j = 0; j < 4; j++) {
                poly.push_back(projected[face.v[j]]);
            }

            // Calculate lighting based on normal z-component
            Vec3 v0 = transformed[face.v[0]];
            Vec3 v1 = transformed[face.v[1]];
            Vec3 v2 = transformed[face.v[2]];
            Vec3 edge1 = v1 - v0;
            Vec3 edge2 = v2 - v0;
            Vec3 normal = edge1.cross(edge2).normalized();
            float lighting = std::max(0.3f, normal.z);

            // Apply lighting to face color
            Color litColor(
                static_cast<uint8_t>(face.color.red * lighting),
                static_cast<uint8_t>(face.color.green * lighting),
                static_cast<uint8_t>(face.color.blue * lighting)
            );

            // Fill the face using scanline
            ctx.fillConvexPoly(poly, litColor);
        }
    }

    // Draw edges (always for wireframe, on top for filled)
    Color edgeColor = filled ? Color::White() : Color(200, 200, 200);

    for (const auto& edge : edges) {
        int i1 = edge.first;
        int i2 = edge.second;

        // For wireframe mode, vary edge color by position
        if (!filled) {
            float avgZ = (transformed[i1].z + transformed[i2].z) / 2.0f;
            float brightness = (avgZ / halfSize + 1.0f) / 2.0f;
            brightness = std::max(0.3f, brightness);
            edgeColor = Color(
                static_cast<uint8_t>(255 * brightness),
                static_cast<uint8_t>(200 * brightness),
                static_cast<uint8_t>(255 * brightness)
            );
        }

        ctx.drawLine(
            projected[i1].x, projected[i1].y,
            projected[i2].x, projected[i2].y,
            edgeColor
        );
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(CubeEffect)

} // namespace xlCore
