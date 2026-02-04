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
 * @file TreeEffect.h
 * @brief Tree effect for xlCore - Christmas tree pattern.
 *
 * Creates an animated tree pattern with branches and garlands.
 * Designed for tree-shaped models where branches span horizontally.
 */

#include "../Effect.h"

namespace xlCore {

// Parameter limits
constexpr int TREE_BRANCHES_MIN = 1;
constexpr int TREE_BRANCHES_MAX = 50;
constexpr int TREE_SPEED_MIN = 0;
constexpr int TREE_SPEED_MAX = 50;

/**
 * @brief Tree effect - animated Christmas tree pattern.
 *
 * Parameters:
 * - Branches: Number of tree branches (1-50, default: 3)
 * - Speed: Animation speed (0-50, default: 10)
 * - ShowLights: Show animated lights on branches (default: true)
 *
 * The effect creates a tree-shaped gradient with optional
 * animated lights that travel along the branches.
 */
class TreeEffect : public Effect {
public:
    TreeEffect() = default;
    ~TreeEffect() override = default;

    // Identity
    std::string name() const override { return "Tree"; }
    std::string description() const override {
        return "Animated Christmas tree pattern with branches";
    }
    std::string category() const override { return "3D"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<TreeEffect>(*this);
    }

    // Capabilities
    int colorSupportedCount() const override { return 1; } // Uses first palette color for tree
};

} // namespace xlCore
