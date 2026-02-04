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
 * @file CubeEffect.h
 * @brief Cube effect for xlCore - 3D cube rendering.
 *
 * Renders a 3D cube with rotation animation. Uses Mat4 transformation
 * matrices to rotate and project the cube onto the 2D buffer.
 */

#include "../Effect.h"

namespace xlCore {

// Parameter limits
constexpr int CUBE_ROTATION_MIN = -360;
constexpr int CUBE_ROTATION_MAX = 360;
constexpr int CUBE_SPEED_MIN = 0;
constexpr int CUBE_SPEED_MAX = 50;
constexpr int CUBE_SIZE_MIN = 10;
constexpr int CUBE_SIZE_MAX = 100;

/**
 * @brief Cube effect - 3D cube rendering with rotation.
 *
 * Parameters:
 * - RotationX: Rotation around X axis in degrees (-360 to 360, default: 30)
 * - RotationY: Rotation around Y axis in degrees (-360 to 360, default: 30)
 * - RotationZ: Rotation around Z axis in degrees (-360 to 360, default: 0)
 * - Speed: Animation speed (0-50, default: 10)
 * - Size: Cube size as percentage of buffer (10-100, default: 70)
 * - Filled: Draw filled faces vs wireframe (default: false)
 *
 * The cube is rendered using 8 vertices and 12 edges (wireframe) or
 * 6 faces (filled), projected to 2D after applying rotation transforms.
 */
class CubeEffect : public Effect {
public:
    CubeEffect() = default;
    ~CubeEffect() override = default;

    // Identity
    std::string name() const override { return "Cube"; }
    std::string description() const override {
        return "3D cube rendering with rotation animation";
    }
    std::string category() const override { return "3D"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<CubeEffect>(*this);
    }

    // Capabilities
    int colorSupportedCount() const override { return -1; }
};

} // namespace xlCore
