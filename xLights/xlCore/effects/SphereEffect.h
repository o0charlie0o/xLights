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
 * @file SphereEffect.h
 * @brief Sphere effect for xlCore - 3D sphere rendering.
 *
 * Renders a 3D sphere using latitude/longitude grid with rotation
 * animation. Uses 3D projection math to display on 2D buffer.
 */

#include "../Effect.h"

namespace xlCore {

// Parameter limits
constexpr int SPHERE_ROTATION_MIN = -360;
constexpr int SPHERE_ROTATION_MAX = 360;
constexpr int SPHERE_SPEED_MIN = 0;
constexpr int SPHERE_SPEED_MAX = 50;
constexpr int SPHERE_LATITUDE_MIN = 4;
constexpr int SPHERE_LATITUDE_MAX = 50;
constexpr int SPHERE_LONGITUDE_MIN = 4;
constexpr int SPHERE_LONGITUDE_MAX = 50;

/**
 * @brief Sphere effect - 3D sphere rendering with rotation.
 *
 * Parameters:
 * - RotationX: Rotation around X axis in degrees (-360 to 360, default: 0)
 * - RotationY: Rotation around Y axis in degrees (-360 to 360, default: 0)
 * - Speed: Animation speed (0-50, default: 10)
 * - LatitudeLines: Number of latitude lines (4-50, default: 20)
 * - LongitudeLines: Number of longitude lines (4-50, default: 20)
 * - Filled: Draw filled sphere vs wireframe (default: true)
 *
 * The sphere is rendered using a latitude/longitude grid
 * projected to 2D after applying rotation transforms.
 */
class SphereEffect : public Effect {
public:
    SphereEffect() = default;
    ~SphereEffect() override = default;

    // Identity
    std::string name() const override { return "Sphere"; }
    std::string description() const override {
        return "3D sphere rendering with rotation animation";
    }
    std::string category() const override { return "3D"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<SphereEffect>(*this);
    }

    // Capabilities
    int colorSupportedCount() const override { return -1; }
};

} // namespace xlCore
