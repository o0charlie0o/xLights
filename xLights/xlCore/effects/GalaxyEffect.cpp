/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "GalaxyEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../Math.h"

#include <cmath>
#include <algorithm>
#include <vector>

namespace xlCore {

// Parameter range constants
constexpr int GALAXY_CENTREX_MIN = 0;
constexpr int GALAXY_CENTREX_MAX = 100;
constexpr int GALAXY_CENTREY_MIN = 0;
constexpr int GALAXY_CENTREY_MAX = 100;
constexpr int GALAXY_STARTRADIUS_MIN = 1;
constexpr int GALAXY_STARTRADIUS_MAX = 250;
constexpr int GALAXY_ENDRADIUS_MIN = 1;
constexpr int GALAXY_ENDRADIUS_MAX = 250;
constexpr int GALAXY_STARTANGLE_MIN = 0;
constexpr int GALAXY_STARTANGLE_MAX = 360;
constexpr int GALAXY_REVOLUTIONS_MIN = 0;
constexpr int GALAXY_REVOLUTIONS_MAX = 3600;
constexpr int GALAXY_STARTWIDTH_MIN = 1;
constexpr int GALAXY_STARTWIDTH_MAX = 255;
constexpr int GALAXY_ENDWIDTH_MIN = 1;
constexpr int GALAXY_ENDWIDTH_MAX = 255;
constexpr int GALAXY_DURATION_MIN = 0;
constexpr int GALAXY_DURATION_MAX = 100;
constexpr int GALAXY_ACCEL_MIN = -10;
constexpr int GALAXY_ACCEL_MAX = 10;

std::vector<EffectParameter> GalaxyEffect::parameters() const {
    return {
        EffectParameter::createInt("E_SLIDER_Galaxy_CenterX", "Center X", 50, GALAXY_CENTREX_MIN, GALAXY_CENTREX_MAX, true),
        EffectParameter::createInt("E_SLIDER_Galaxy_CenterY", "Center Y", 50, GALAXY_CENTREY_MIN, GALAXY_CENTREY_MAX, true),
        EffectParameter::createInt("E_SLIDER_Galaxy_Start_Radius", "Start Radius", 1, GALAXY_STARTRADIUS_MIN, GALAXY_STARTRADIUS_MAX, true),
        EffectParameter::createInt("E_SLIDER_Galaxy_End_Radius", "End Radius", 10, GALAXY_ENDRADIUS_MIN, GALAXY_ENDRADIUS_MAX, true),
        EffectParameter::createInt("E_SLIDER_Galaxy_Start_Angle", "Start Angle", 0, GALAXY_STARTANGLE_MIN, GALAXY_STARTANGLE_MAX, true),
        EffectParameter::createInt("E_SLIDER_Galaxy_Revolutions", "Revolutions", 1440, GALAXY_REVOLUTIONS_MIN, GALAXY_REVOLUTIONS_MAX, true),
        EffectParameter::createInt("E_SLIDER_Galaxy_Start_Width", "Start Width", 5, GALAXY_STARTWIDTH_MIN, GALAXY_STARTWIDTH_MAX, true),
        EffectParameter::createInt("E_SLIDER_Galaxy_End_Width", "End Width", 5, GALAXY_ENDWIDTH_MIN, GALAXY_ENDWIDTH_MAX, true),
        EffectParameter::createInt("E_SLIDER_Galaxy_Duration", "Duration", 20, GALAXY_DURATION_MIN, GALAXY_DURATION_MAX, true),
        EffectParameter::createInt("E_SLIDER_Galaxy_Accel", "Acceleration", 0, GALAXY_ACCEL_MIN, GALAXY_ACCEL_MAX, true),
        EffectParameter::createBool("E_CHECKBOX_Galaxy_Blend_Edges", "Blend Edges", true),
        EffectParameter::createBool("E_CHECKBOX_Galaxy_Reverse", "Reverse", false),
        EffectParameter::createBool("E_CHECKBOX_Galaxy_Inward", "Inward", false),
        EffectParameter::createBool("E_CHECKBOX_Galaxy_Scale", "Scale to Buffer", true)
    };
}

double GalaxyEffect::getStep(double radius) {
    if (radius < 5) {
        return 0.1;
    }
    return (0.5 * 360.0 / (2.0 * math::PI * radius));
}

Color GalaxyEffect::get2ColorBlend(const std::vector<Color>& palette, int c1, int c2, double ratio) const {
    if (palette.empty()) return Color::Black();
    if (c1 >= static_cast<int>(palette.size())) c1 = static_cast<int>(palette.size()) - 1;
    if (c2 >= static_cast<int>(palette.size())) c2 = static_cast<int>(palette.size()) - 1;
    if (c1 < 0) c1 = 0;
    if (c2 < 0) c2 = 0;

    ratio = std::clamp(ratio, 0.0, 1.0);

    const Color& color1 = palette[c1];
    const Color& color2 = palette[c2];

    return Color(
        static_cast<uint8_t>(color1.red + (color2.red - color1.red) * ratio),
        static_cast<uint8_t>(color1.green + (color2.green - color1.green) * ratio),
        static_cast<uint8_t>(color1.blue + (color2.blue - color1.blue) * ratio)
    );
}

Color GalaxyEffect::calcEndpointColor(double endAngle, double startAngle,
                                      double headEndOfTail, double colorLength,
                                      int numColors, const std::vector<Color>& palette) const {
    double cv = (headEndOfTail - endAngle) / colorLength;
    int ci = static_cast<int>(cv);
    double cp = cv - static_cast<double>(ci);
    int c2 = std::min(ci + 1, numColors - 1);

    if (ci < c2) {
        return get2ColorBlend(palette, ci, c2, std::min(cp, 1.0));
    } else {
        if (c2 >= 0 && c2 < static_cast<int>(palette.size())) {
            return palette[c2];
        }
        return Color::Black();
    }
}

void GalaxyEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int center_x = settings.getInt("E_SLIDER_Galaxy_CenterX", 50);
    int center_y = settings.getInt("E_SLIDER_Galaxy_CenterY", 50);
    int start_radius = settings.getInt("E_SLIDER_Galaxy_Start_Radius", 1);
    int end_radius = settings.getInt("E_SLIDER_Galaxy_End_Radius", 10);
    int start_angle = settings.getInt("E_SLIDER_Galaxy_Start_Angle", 0);
    int revolutions = settings.getInt("E_SLIDER_Galaxy_Revolutions", 1440);
    int start_width = settings.getInt("E_SLIDER_Galaxy_Start_Width", 5);
    int end_width = settings.getInt("E_SLIDER_Galaxy_End_Width", 5);
    int duration = settings.getInt("E_SLIDER_Galaxy_Duration", 20);
    int acceleration = settings.getInt("E_SLIDER_Galaxy_Accel", 0);
    bool reverse_dir = settings.getBool("E_CHECKBOX_Galaxy_Reverse", false);
    bool blend_edges = settings.getBool("E_CHECKBOX_Galaxy_Blend_Edges", true);
    bool inward = settings.getBool("E_CHECKBOX_Galaxy_Inward", false);
    bool scale = settings.getBool("E_CHECKBOX_Galaxy_Scale", true);

    if (revolutions == 0) return;

    int bufferWi = ctx.width();
    int bufferHt = ctx.height();

    // Build a simple palette from the state's palette data (simplified for now)
    std::vector<Color> palette;
    palette.push_back(Color(255, 0, 0));    // Red
    palette.push_back(Color(0, 255, 0));    // Green
    palette.push_back(Color(0, 0, 255));    // Blue
    palette.push_back(Color(255, 255, 0));  // Yellow

    int num_colors = static_cast<int>(palette.size());

    // Temp buffer for blending
    std::vector<std::vector<double>> temp_colors_pct(bufferWi, std::vector<double>(bufferHt, 0.0));
    std::vector<std::vector<double>> pixel_age(bufferWi, std::vector<double>(bufferHt, 0.0));
    std::vector<std::vector<Color>> temp_buffer(bufferWi, std::vector<Color>(bufferHt, Color::Black()));

    double eff_pos = state.progress;
    double eff_pos_adj = math::calcAccel(eff_pos, acceleration);
    double revs = static_cast<double>(revolutions);

    double pos_x = bufferWi * center_x / 100.0;
    double pos_y = bufferHt * center_y / 100.0;

    double head_duration = duration / 100.0;
    double tail_length = revs * (1.0 - head_duration);
    double color_length = tail_length / num_colors;
    if (color_length < 1.0) color_length = 1.0;

    double tail_end_of_tail = ((revs + tail_length) * eff_pos_adj) - tail_length;
    double head_end_of_tail = tail_end_of_tail + tail_length;

    double radius1 = start_radius;
    double radius2 = end_radius;
    double width1 = start_width;
    double width2 = end_width;

    if (scale) {
        double bufferMax = std::max(bufferHt, bufferWi);
        radius1 = radius1 * (bufferMax / 200.0);
        radius2 = radius2 * (bufferMax / 200.0);
        width1 = width1 * (bufferMax / 100.0);
        width2 = width2 * (bufferMax / 100.0);
    }

    double half_width = 1;
    double last_check = (inward ? std::min(head_end_of_tail, revs) : std::max(0.0, tail_end_of_tail)) + static_cast<double>(start_angle);

    // Draw endpoint (head or tail depending on direction)
    double adj_angle;
    double end_angle = (inward ? std::min(head_end_of_tail, revs) : std::max(0.0, tail_end_of_tail));
    Color color = calcEndpointColor(end_angle, start_angle, head_end_of_tail, color_length, num_colors, palette);
    double pct1 = end_angle / revs;
    double current_radius = radius2 * pct1 + radius1 * (1.0 - pct1);
    double current_width = width2 * pct1 + width1 * (1.0 - pct1);
    double current_delta = 0.0;
    double current_distance = 0.0;
    half_width = current_width / 2.0;
    double step = getStep(current_radius + half_width);

    // Draw the rounded endpoint
    if (current_radius >= half_width && half_width > 0.0) {
        for (double i = end_angle; current_distance <= half_width; (inward ? i += step : i -= step)) {
            adj_angle = i + static_cast<double>(start_angle);
            if (reverse_dir) {
                adj_angle *= -1.0;
            }
            current_delta = std::abs(end_angle - i);
            current_distance = (2.0 * math::PI * current_radius * current_delta) / 360.0;

            if (half_width > current_distance) {
                double cw = std::sqrt(half_width * half_width - current_distance * current_distance);
                double inside_radius = std::max(0.0, current_radius - cw);

                for (double r = inside_radius;; r += 0.5) {
                    if (r > current_radius) r = current_radius;

                    double rad = math::toRadians(adj_angle);
                    double x1 = std::sin(rad) * r + pos_x;
                    double y1 = std::cos(rad) * r + pos_y;
                    double outside_radius = current_radius + (current_radius - r);
                    double x2 = std::sin(rad) * outside_radius + pos_x;
                    double y2 = std::cos(rad) * outside_radius + pos_y;

                    double head_fade_pct = 1.0 - (current_distance / half_width);
                    head_fade_pct = std::clamp(head_fade_pct, 0.0, 1.0);
                    double color_pct2 = ((r - inside_radius) / (current_radius - inside_radius)) * head_fade_pct;

                    if (!blend_edges) {
                        Color c = color;
                        c = c.withValue(color.value() * color_pct2);
                        ctx.setPixel(static_cast<int>(x1), static_cast<int>(y1), c);
                        ctx.setPixel(static_cast<int>(x2), static_cast<int>(y2), c);
                    } else {
                        int ix1 = static_cast<int>(x1);
                        int iy1 = static_cast<int>(y1);
                        int ix2 = static_cast<int>(x2);
                        int iy2 = static_cast<int>(y2);
                        if (ix1 >= 0 && ix1 < bufferWi && iy1 >= 0 && iy1 < bufferHt) {
                            temp_buffer[ix1][iy1] = color;
                            temp_colors_pct[ix1][iy1] = color_pct2;
                        }
                        if (ix2 >= 0 && ix2 < bufferWi && iy2 >= 0 && iy2 < bufferHt) {
                            temp_buffer[ix2][iy2] = color;
                            temp_colors_pct[ix2][iy2] = color_pct2;
                        }
                    }
                    if (r >= current_radius) break;
                }
            }
            step = getStep(current_radius + half_width);
        }
    }

    // Draw the main spiral
    for (double i = (inward ? std::min(head_end_of_tail, revs) : std::max(0.0, tail_end_of_tail));
         (inward ? i >= std::max(0.0, tail_end_of_tail) : i <= std::min(head_end_of_tail, revs));
         (inward ? i -= step : i += step)) {

        double adj_angle = i + static_cast<double>(start_angle);
        if (reverse_dir) {
            adj_angle *= -1.0;
        }

        double color_val = (head_end_of_tail - i) / color_length;
        int color_int = static_cast<int>(color_val);
        double color_pct = color_val - static_cast<double>(color_int);
        int color2 = std::min(color_int + 1, num_colors - 1);

        Color currentColor;
        if (color_int < color2) {
            currentColor = get2ColorBlend(palette, color_int, color2, std::min(color_pct, 1.0));
        } else {
            if (color2 >= 0 && color2 < num_colors) {
                currentColor = palette[color2];
            } else {
                currentColor = Color::Black();
            }
        }

        double pct = i / revs;
        current_radius = radius2 * pct + radius1 * (1.0 - pct);
        current_width = width2 * pct + width1 * (1.0 - pct);
        half_width = current_width / 2.0;
        double inside_radius = current_radius - half_width;

        for (double r = inside_radius;; r += 0.5) {
            if (r > current_radius) r = current_radius;

            double rad = math::toRadians(adj_angle);
            double x1 = std::sin(rad) * r + pos_x;
            double y1 = std::cos(rad) * r + pos_y;
            double outside_radius = current_radius + (current_radius - r);
            double x2 = std::sin(rad) * outside_radius + pos_x;
            double y2 = std::cos(rad) * outside_radius + pos_y;

            double color_pct2 = (r - inside_radius) / (current_radius - inside_radius);

            if (!blend_edges) {
                Color c = currentColor.withValue(currentColor.value() * color_pct2);
                ctx.setPixel(static_cast<int>(x1), static_cast<int>(y1), c);
                ctx.setPixel(static_cast<int>(x2), static_cast<int>(y2), c);
            } else {
                int ix1 = static_cast<int>(x1);
                int iy1 = static_cast<int>(y1);
                int ix2 = static_cast<int>(x2);
                int iy2 = static_cast<int>(y2);
                if (ix1 >= 0 && ix1 < bufferWi && iy1 >= 0 && iy1 < bufferHt) {
                    temp_buffer[ix1][iy1] = currentColor;
                    temp_colors_pct[ix1][iy1] = color_pct2;
                    pixel_age[ix1][iy1] = std::abs(adj_angle);
                }
                if (ix2 >= 0 && ix2 < bufferWi && iy2 >= 0 && iy2 < bufferHt) {
                    temp_buffer[ix2][iy2] = currentColor;
                    temp_colors_pct[ix2][iy2] = color_pct2;
                    pixel_age[ix2][iy2] = std::abs(adj_angle);
                }
            }
            if (r >= current_radius) break;
        }

        // Blend old data periodically
        if (blend_edges && ((inward ? (last_check - std::abs(adj_angle)) : (std::abs(adj_angle) - last_check)) >= 90.0)) {
            for (int x = 0; x < bufferWi; x++) {
                for (int y = 0; y < bufferHt; y++) {
                    if (temp_colors_pct[x][y] > 0.0 &&
                        ((inward ? (pixel_age[x][y] - std::abs(adj_angle)) : (std::abs(adj_angle) - pixel_age[x][y])) >= 180.0)) {
                        Color c_new = temp_buffer[x][y];
                        Color c_old = ctx.getPixel(x, y);
                        Color blended = c_old.alphaBlend(c_new.withAlpha(static_cast<uint8_t>(temp_colors_pct[x][y] * 255)));
                        ctx.setPixel(x, y, blended);
                        temp_colors_pct[x][y] = 0.0;
                        pixel_age[x][y] = 0.0;
                    }
                }
            }
            last_check = std::abs(adj_angle);
        }
        step = getStep(current_radius + half_width);
    }

    // Final blend of remaining temp pixels
    if (blend_edges) {
        for (int x = 0; x < bufferWi; x++) {
            for (int y = 0; y < bufferHt; y++) {
                if (temp_colors_pct[x][y] > 0.0) {
                    Color c_new = temp_buffer[x][y];
                    Color c_old = ctx.getPixel(x, y);
                    Color blended = c_old.alphaBlend(c_new.withAlpha(static_cast<uint8_t>(temp_colors_pct[x][y] * 255)));
                    ctx.setPixel(x, y, blended);
                }
            }
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(GalaxyEffect)

} // namespace xlCore
