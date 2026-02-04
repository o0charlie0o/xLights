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
 * @file GalaxyEffect.h
 * @brief Galaxy spiral effect for xlCore.
 *
 * Creates an animated spiral galaxy pattern with configurable:
 * - Center position
 * - Start/end radius
 * - Start/end width
 * - Number of revolutions
 * - Rotation direction
 * - Edge blending
 */

#include "../Effect.h"

namespace xlCore {

/**
 * @brief Galaxy spiral effect - creates animated spiral patterns.
 *
 * Parameters:
 * - CenterX: Horizontal center position (0-100, default: 50)
 * - CenterY: Vertical center position (0-100, default: 50)
 * - StartRadius: Inner spiral radius (1-250, default: 1)
 * - EndRadius: Outer spiral radius (1-250, default: 10)
 * - StartAngle: Starting angle in degrees (0-360, default: 0)
 * - Revolutions: Number of spiral turns (0-3600, default: 1440)
 * - StartWidth: Width at start of spiral (1-255, default: 5)
 * - EndWidth: Width at end of spiral (1-255, default: 5)
 * - Duration: Head duration percentage (0-100, default: 20)
 * - Accel: Acceleration (-10 to 10, default: 0)
 * - BlendEdges: Enable edge blending (default: true)
 * - Reverse: Reverse rotation direction (default: false)
 * - Inward: Draw spiral inward (default: false)
 * - Scale: Scale radius to buffer size (default: true)
 */
class GalaxyEffect : public Effect {
public:
    GalaxyEffect() = default;
    ~GalaxyEffect() override = default;

    // Identity
    std::string name() const override { return "Galaxy"; }
    std::string description() const override {
        return "Creates an animated spiral galaxy pattern";
    }
    std::string category() const override { return "3D"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<GalaxyEffect>(*this);
    }

    // Capabilities
    bool supportsLinearColorCurves(const EffectSettings& settings) const override { return true; }
    int colorSupportedCount() const override { return -1; } // Unlimited colors

private:
    // Calculate step size based on radius
    static double getStep(double radius);

    // Calculate endpoint color for blending
    Color calcEndpointColor(double endAngle, double startAngle,
                           double headEndOfTail, double colorLength,
                           int numColors, const std::vector<Color>& palette) const;

    // Get blended color from palette
    Color get2ColorBlend(const std::vector<Color>& palette, int c1, int c2, double ratio) const;
};

} // namespace xlCore
