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
 * @file PlasmaEffect.h
 * @brief Plasma effect for xlCore - classic plasma animation.
 *
 * Creates a classic plasma effect using combinations of sine waves
 * to produce colorful, animated patterns. Supports multiple color
 * schemes including palette-based and preset color modes.
 *
 * The plasma algorithm combines multiple sine wave functions:
 * - Horizontal wave
 * - Vertical wave
 * - Diagonal wave
 * - Radial wave
 */

#include "../Effect.h"

namespace xlCore {

// Parameter limits
constexpr int PLASMA_SPEED_MIN = 1;
constexpr int PLASMA_SPEED_MAX = 100;
constexpr int PLASMA_STYLE_MIN = 1;
constexpr int PLASMA_STYLE_MAX = 10;
constexpr int PLASMA_LINE_DENSITY_MIN = 1;
constexpr int PLASMA_LINE_DENSITY_MAX = 10;

/**
 * @brief Color scheme types for plasma effect.
 */
enum class PlasmaColorScheme {
    Normal = 0,     // Use palette colors
    Preset1 = 1,    // Red/Blue preset
    Preset2 = 2,    // Green/Pink preset
    Preset3 = 3,    // Rainbow preset
    Preset4 = 4     // Fire preset
};

/**
 * @brief Plasma effect - classic plasma animation.
 *
 * Parameters:
 * - Style: Pattern style (1-10)
 * - Line_Density: Density of the plasma lines (1-10)
 * - Speed: Animation speed (1-100)
 * - Color: Color scheme (Normal, Preset1-4)
 */
class PlasmaEffect : public Effect {
public:
    PlasmaEffect() = default;
    ~PlasmaEffect() override = default;

    // Identity
    std::string name() const override { return "Plasma"; }
    std::string description() const override {
        return "Classic plasma animation using sine wave combinations";
    }
    std::string category() const override { return "Patterns"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Cloning
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<PlasmaEffect>(*this);
    }

    // Capabilities
    int colorSupportedCount() const override { return -1; } // Unlimited colors

private:
    /**
     * @brief Get color scheme from string.
     */
    static PlasmaColorScheme getColorScheme(const std::string& colorSchemeStr);

    /**
     * @brief Render plasma with normal (palette) colors.
     */
    void renderStyle0(RenderContext& ctx, const std::vector<Color>& palette,
                     int style, int lineDensity, double time,
                     double sinTime5, double cosTime3, double sinTime2) const;

    /**
     * @brief Render plasma with preset color scheme 1.
     */
    void renderStyle1(RenderContext& ctx, int style, int lineDensity, double time,
                     double sinTime5, double cosTime3, double sinTime2) const;

    /**
     * @brief Render plasma with preset color scheme 2.
     */
    void renderStyle2(RenderContext& ctx, int style, int lineDensity, double time,
                     double sinTime5, double cosTime3, double sinTime2) const;

    /**
     * @brief Render plasma with preset color scheme 3.
     */
    void renderStyle3(RenderContext& ctx, int style, int lineDensity, double time,
                     double sinTime5, double cosTime3, double sinTime2) const;

    /**
     * @brief Render plasma with preset color scheme 4.
     */
    void renderStyle4(RenderContext& ctx, int style, int lineDensity, double time,
                     double sinTime5, double cosTime3, double sinTime2) const;

    /**
     * @brief Calculate plasma value at a pixel.
     */
    static double calculatePlasmaValue(int x, int y, int width, int height,
                                      int style, int lineDensity, double time,
                                      double sinTime5, double cosTime3, double sinTime2);
};

} // namespace xlCore
