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
 * @file FillEffect.h
 * @brief Fill effect for xlCore - fills buffer progressively.
 *
 * This effect fills the buffer from one direction to another,
 * creating a "filling" animation. Supports:
 * - Fill from Up, Down, Left, or Right
 * - Position-based fill level
 * - Band coloring with optional skip patterns
 * - Color by time or position
 * - Wrapping at edges
 */

#include "../Effect.h"

namespace xlCore {

// Parameter limits
constexpr int FILL_POSITION_MIN = 0;
constexpr int FILL_POSITION_MAX = 100;

constexpr int FILL_BANDSIZE_MIN = 0;
constexpr int FILL_BANDSIZE_MAX = 250;

constexpr int FILL_SKIPSIZE_MIN = 0;
constexpr int FILL_SKIPSIZE_MAX = 250;

constexpr int FILL_OFFSET_MIN = 0;
constexpr int FILL_OFFSET_MAX = 100;

/**
 * @brief Fill effect - progressively fills the buffer.
 *
 * Parameters:
 * - Position: Fill level as percentage (0-100, default: 100)
 * - Direction: "Up", "Down", "Left", "Right" (default: "Up")
 * - BandSize: Size of color bands (0 = solid fill)
 * - SkipSize: Size of gaps between bands
 * - Offset: Starting offset position
 * - OffsetInPixels: Whether offset is in pixels or percentage
 * - ColorByTime: Color based on time vs position
 * - Wrap: Allow wrapping at edges
 */
class FillEffect : public Effect {
public:
    FillEffect() = default;
    ~FillEffect() override = default;

    // Identity
    std::string name() const override { return "Fill"; }
    std::string description() const override {
        return "Progressively fills the model from one direction";
    }
    std::string category() const override { return "Utility"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<FillEffect>(*this);
    }

    // Capabilities
    bool canRenderPartialTimeInterval() const override { return true; }
    int colorSupportedCount() const override { return -1; } // Unlimited colors

private:
    // Direction enumeration
    enum class FillDirection {
        Up = 0,
        Down = 1,
        Left = 2,
        Right = 3
    };

    static FillDirection parseDirection(const std::string& dir);

    /**
     * @brief Get blended color at a specific position in the palette.
     */
    Color getColorFromPosition(double pos, const std::vector<Color>& colors) const;

    /**
     * @brief Update position and color index for banding.
     */
    void updateFillColor(int& position, int& bandColor, int colorCount, int colorSize, int shift) const;
};

} // namespace xlCore
