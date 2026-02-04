/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "PlasmaEffect.h"
#include "../RenderContext.h"
#include "../XLMath.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

std::vector<EffectParameter> PlasmaEffect::parameters() const {
    std::vector<EffectParameter> params;

    auto style = EffectParameter::createInt("Plasma_Style", "Style", 1, PLASMA_STYLE_MIN, PLASMA_STYLE_MAX);
    style.group = "Pattern";
    params.push_back(style);

    auto density = EffectParameter::createInt("Plasma_Line_Density", "Line Density", 1, PLASMA_LINE_DENSITY_MIN, PLASMA_LINE_DENSITY_MAX);
    density.group = "Pattern";
    params.push_back(density);

    auto speed = EffectParameter::createInt("Plasma_Speed", "Speed", 10, PLASMA_SPEED_MIN, PLASMA_SPEED_MAX, true);
    speed.group = "Animation";
    params.push_back(speed);

    auto color = EffectParameter::createChoice("CHOICE_Plasma_Color", "Color Scheme", "Normal",
        {"Normal", "Preset Colors 1", "Preset Colors 2", "Preset Colors 3", "Preset Colors 4"});
    color.group = "Color";
    params.push_back(color);

    return params;
}

PlasmaColorScheme PlasmaEffect::getColorScheme(const std::string& colorSchemeStr) {
    if (colorSchemeStr == "Preset Colors 1") return PlasmaColorScheme::Preset1;
    if (colorSchemeStr == "Preset Colors 2") return PlasmaColorScheme::Preset2;
    if (colorSchemeStr == "Preset Colors 3") return PlasmaColorScheme::Preset3;
    if (colorSchemeStr == "Preset Colors 4") return PlasmaColorScheme::Preset4;
    return PlasmaColorScheme::Normal;
}

double PlasmaEffect::calculatePlasmaValue(int x, int y, int width, int height,
                                         int style, int lineDensity, double time,
                                         double sinTime5, double cosTime3, double sinTime2) {
    double rx = static_cast<double>(x) / width;
    double ry = static_cast<double>(y) / height;

    double v = 0.0;

    // Different plasma styles using combinations of sine waves
    switch (style) {
        case 1:
        default: {
            // Basic plasma
            v = std::sin(rx * lineDensity * math::PI + time);
            v += std::sin(ry * lineDensity * math::PI + time);
            v += std::sin((rx + ry) * lineDensity * math::PI + time);
            double cx = rx + 0.5 * sinTime5;
            double cy = ry + 0.5 * cosTime3;
            v += std::sin(std::sqrt(cx * cx + cy * cy + 1.0) * lineDensity * math::PI);
        } break;

        case 2: {
            // More complex pattern
            v = std::sin(rx * lineDensity * 10.0 + time);
            v += std::sin(ry * lineDensity * 10.0 + time);
            v += std::sin((rx + ry) * lineDensity * 10.0 + sinTime2);
            v += std::sin(std::sqrt(rx * rx + ry * ry + 0.5) * lineDensity * 10.0 + cosTime3);
        } break;

        case 3: {
            // Spiral pattern
            double cx = rx - 0.5;
            double cy = ry - 0.5;
            double r = std::sqrt(cx * cx + cy * cy);
            double theta = std::atan2(cy, cx);
            v = std::sin(r * lineDensity * 20.0 - theta * 3.0 + time * 2.0);
            v += std::sin(theta * lineDensity + time);
        } break;

        case 4: {
            // Circular waves
            double cx1 = rx - 0.25 - 0.25 * sinTime5;
            double cy1 = ry - 0.5;
            double cx2 = rx - 0.75 + 0.25 * cosTime3;
            double cy2 = ry - 0.5;
            v = std::sin(std::sqrt(cx1 * cx1 + cy1 * cy1) * lineDensity * 15.0 + time);
            v += std::sin(std::sqrt(cx2 * cx2 + cy2 * cy2) * lineDensity * 15.0 + time);
        } break;

        case 5: {
            // Horizontal bands
            v = std::sin(ry * lineDensity * 15.0 + time);
            v += 0.5 * std::sin(ry * lineDensity * 30.0 + rx * 5.0 + time * 1.5);
            v += 0.25 * std::sin((rx + sinTime2 * 0.1) * lineDensity * 10.0);
        } break;

        case 6: {
            // Vertical bands
            v = std::sin(rx * lineDensity * 15.0 + time);
            v += 0.5 * std::sin(rx * lineDensity * 30.0 + ry * 5.0 + time * 1.5);
            v += 0.25 * std::sin((ry + cosTime3 * 0.1) * lineDensity * 10.0);
        } break;

        case 7: {
            // Diamond pattern
            double dx = std::abs(rx - 0.5);
            double dy = std::abs(ry - 0.5);
            v = std::sin((dx + dy) * lineDensity * 20.0 + time);
            v += std::sin(std::max(dx, dy) * lineDensity * 15.0 - time);
        } break;

        case 8: {
            // Interference pattern
            double r1 = std::sqrt((rx - 0.3) * (rx - 0.3) + (ry - 0.3) * (ry - 0.3));
            double r2 = std::sqrt((rx - 0.7) * (rx - 0.7) + (ry - 0.7) * (ry - 0.7));
            v = std::sin(r1 * lineDensity * 30.0 - time);
            v += std::sin(r2 * lineDensity * 30.0 + time);
        } break;

        case 9: {
            // Checkerboard dissolve
            int gridX = static_cast<int>(rx * lineDensity * 4.0);
            int gridY = static_cast<int>(ry * lineDensity * 4.0);
            double phase = ((gridX + gridY) % 2) * math::PI;
            v = std::sin(rx * lineDensity * 10.0 + time + phase);
            v += std::sin(ry * lineDensity * 10.0 + time + phase);
        } break;

        case 10: {
            // Turbulent
            v = std::sin(rx * lineDensity * 8.0 + sinTime5 * 3.0);
            v += std::sin(ry * lineDensity * 8.0 + cosTime3 * 3.0);
            v += std::sin((rx + ry) * lineDensity * 8.0 + sinTime2 * 3.0);
            v += std::sin(std::sqrt(rx * rx + ry * ry) * lineDensity * 12.0 + time);
            v *= 0.5;
        } break;
    }

    // Normalize to 0-1 range
    v = (v + 4.0) / 8.0;  // Assuming max sum is around 4
    return std::clamp(v, 0.0, 1.0);
}

void PlasmaEffect::renderStyle0(RenderContext& ctx, const std::vector<Color>& palette,
                               int style, int lineDensity, double time,
                               double sinTime5, double cosTime3, double sinTime2) const {
    int width = ctx.width();
    int height = ctx.height();
    int numColors = static_cast<int>(palette.size());

    if (numColors == 0) {
        ctx.fill(Color::Black());
        return;
    }

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            double v = calculatePlasmaValue(x, y, width, height, style, lineDensity, time, sinTime5, cosTime3, sinTime2);

            // Map to palette
            double colorPos = v * (numColors - 1);
            int colorIdx = static_cast<int>(colorPos);
            double frac = colorPos - colorIdx;

            if (colorIdx >= numColors - 1) {
                ctx.setPixelUnchecked(x, y, palette[numColors - 1]);
            } else {
                const Color& c1 = palette[colorIdx];
                const Color& c2 = palette[colorIdx + 1];
                Color blended(
                    static_cast<uint8_t>(c1.red + (c2.red - c1.red) * frac),
                    static_cast<uint8_t>(c1.green + (c2.green - c1.green) * frac),
                    static_cast<uint8_t>(c1.blue + (c2.blue - c1.blue) * frac)
                );
                ctx.setPixelUnchecked(x, y, blended);
            }
        }
    }
}

void PlasmaEffect::renderStyle1(RenderContext& ctx, int style, int lineDensity, double time,
                               double sinTime5, double cosTime3, double sinTime2) const {
    // Preset 1: Red/Blue
    int width = ctx.width();
    int height = ctx.height();

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            double v = calculatePlasmaValue(x, y, width, height, style, lineDensity, time, sinTime5, cosTime3, sinTime2);

            uint8_t r = static_cast<uint8_t>(255.0 * std::sin(v * math::PI));
            uint8_t g = static_cast<uint8_t>(255.0 * std::sin(v * math::PI * 2.0 + math::PI / 3.0));
            uint8_t b = static_cast<uint8_t>(255.0 * std::sin(v * math::PI * 2.0 + math::PI * 2.0 / 3.0));

            ctx.setPixelUnchecked(x, y, Color(r, g, b));
        }
    }
}

void PlasmaEffect::renderStyle2(RenderContext& ctx, int style, int lineDensity, double time,
                               double sinTime5, double cosTime3, double sinTime2) const {
    // Preset 2: Green/Pink
    int width = ctx.width();
    int height = ctx.height();

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            double v = calculatePlasmaValue(x, y, width, height, style, lineDensity, time, sinTime5, cosTime3, sinTime2);

            uint8_t r = static_cast<uint8_t>(255.0 * (0.5 + 0.5 * std::sin(v * math::TWO_PI)));
            uint8_t g = static_cast<uint8_t>(255.0 * (0.5 + 0.5 * std::sin(v * math::TWO_PI + math::PI / 2.0)));
            uint8_t b = static_cast<uint8_t>(255.0 * (0.5 + 0.5 * std::sin(v * math::TWO_PI + math::PI)));

            ctx.setPixelUnchecked(x, y, Color(r, g, b));
        }
    }
}

void PlasmaEffect::renderStyle3(RenderContext& ctx, int style, int lineDensity, double time,
                               double sinTime5, double cosTime3, double sinTime2) const {
    // Preset 3: Rainbow
    int width = ctx.width();
    int height = ctx.height();

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            double v = calculatePlasmaValue(x, y, width, height, style, lineDensity, time, sinTime5, cosTime3, sinTime2);

            // Convert to HSV with full saturation and value
            HSV hsv(v, 1.0, 1.0);
            Color c(hsv);
            ctx.setPixelUnchecked(x, y, c);
        }
    }
}

void PlasmaEffect::renderStyle4(RenderContext& ctx, int style, int lineDensity, double time,
                               double sinTime5, double cosTime3, double sinTime2) const {
    // Preset 4: Fire
    int width = ctx.width();
    int height = ctx.height();

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            double v = calculatePlasmaValue(x, y, width, height, style, lineDensity, time, sinTime5, cosTime3, sinTime2);

            // Fire colors: black -> red -> orange -> yellow -> white
            uint8_t r, g, b;
            if (v < 0.33) {
                // Black to red
                double t = v / 0.33;
                r = static_cast<uint8_t>(255.0 * t);
                g = 0;
                b = 0;
            } else if (v < 0.66) {
                // Red to orange/yellow
                double t = (v - 0.33) / 0.33;
                r = 255;
                g = static_cast<uint8_t>(200.0 * t);
                b = 0;
            } else {
                // Orange to yellow/white
                double t = (v - 0.66) / 0.34;
                r = 255;
                g = static_cast<uint8_t>(200.0 + 55.0 * t);
                b = static_cast<uint8_t>(255.0 * t * t);
            }

            ctx.setPixelUnchecked(x, y, Color(r, g, b));
        }
    }
}

void PlasmaEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    int style = settings.getInt("Plasma_Style", 1);
    int lineDensity = settings.getInt("Plasma_Line_Density", 1);
    int plasmaSpeed = settings.getInt("Plasma_Speed", 10);
    std::string colorSchemeStr = settings.get("CHOICE_Plasma_Color", "Normal");

    PlasmaColorScheme colorScheme = getColorScheme(colorSchemeStr);

    // Calculate time-based values
    double speedPlasma = (101.0 - plasmaSpeed) * 3.0;
    double time = (state.frameIndex + 1.0) / speedPlasma;

    double sinTime5 = std::sin(time / 5.0);
    double cosTime3 = std::cos(time / 3.0);
    double sinTime2 = std::sin(time / 2.0);

    // For now, create a simple palette (in full implementation, get from settings)
    std::vector<Color> palette = {
        Color::Red(), Color::Green(), Color::Blue(), Color::Yellow(), Color::Cyan(), Color::Magenta()
    };

    switch (colorScheme) {
        case PlasmaColorScheme::Normal:
            renderStyle0(ctx, palette, style, lineDensity, time, sinTime5, cosTime3, sinTime2);
            break;
        case PlasmaColorScheme::Preset1:
            renderStyle1(ctx, style, lineDensity, time, sinTime5, cosTime3, sinTime2);
            break;
        case PlasmaColorScheme::Preset2:
            renderStyle2(ctx, style, lineDensity, time, sinTime5, cosTime3, sinTime2);
            break;
        case PlasmaColorScheme::Preset3:
            renderStyle3(ctx, style, lineDensity, time, sinTime5, cosTime3, sinTime2);
            break;
        case PlasmaColorScheme::Preset4:
            renderStyle4(ctx, style, lineDensity, time, sinTime5, cosTime3, sinTime2);
            break;
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(PlasmaEffect)

} // namespace xlCore
