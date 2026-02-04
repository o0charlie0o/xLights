/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "Color.h"
#include <sstream>
#include <iomanip>
#include <cstdlib>
#include <unordered_map>

namespace xlCore {

// Named color map for string parsing
static const std::unordered_map<std::string, Color> NAME_MAP = {
    {"White", Color::White()},
    {"WHITE", Color::White()},
    {"Black", Color::Black()},
    {"BLACK", Color::Black()},
    {"Blue", Color::Blue()},
    {"BLUE", Color::Blue()},
    {"Cyan", Color::Cyan()},
    {"CYAN", Color::Cyan()},
    {"Green", Color::Green()},
    {"GREEN", Color::Green()},
    {"MAGENTA", Color::Magenta()},
    {"Magenta", Color::Magenta()},
    {"RED", Color::Red()},
    {"Red", Color::Red()},
    {"YELLOW", Color::Yellow()},
    {"Yellow", Color::Yellow()},
    {"ORANGE", Color::Orange()},
    {"Orange", Color::Orange()},
    {"AQUAMARINE", Color(112, 219, 147)},
    {"BLUE VIOLET", Color(159, 95, 159)},
    {"BROWN", Color(165, 42, 42)},
    {"CADET BLUE", Color(95, 159, 159)},
    {"CORAL", Color(255, 127, 0)},
    {"CORNFLOWER BLUE", Color(66, 66, 111)},
    {"DARK GREY", Color(47, 47, 47)},
    {"DARK GREEN", Color(47, 79, 47)},
    {"DARK OLIVE GREEN", Color(79, 79, 47)},
    {"DARK ORCHID", Color(153, 50, 204)},
    {"DARK SLATE BLUE", Color(107, 35, 142)},
    {"DARK SLATE GREY", Color(47, 79, 79)},
    {"DARK TURQUOISE", Color(112, 147, 219)},
    {"DIM GREY", Color(84, 84, 84)},
    {"FIREBRICK", Color(142, 35, 35)},
    {"FOREST GREEN", Color(35, 142, 35)},
    {"GOLD", Color(204, 127, 50)},
    {"GOLDENROD", Color(219, 219, 112)},
    {"GREEN YELLOW", Color(147, 219, 112)},
    {"GREY", Color(128, 128, 128)},
    {"INDIAN RED", Color(79, 47, 47)},
    {"KHAKI", Color(159, 159, 95)},
    {"LIGHT BLUE", Color(191, 216, 216)},
    {"LIGHT GREY", Color(192, 192, 192)},
    {"LIGHT STEEL BLUE", Color(143, 143, 188)},
    {"LIME GREEN", Color(50, 204, 50)},
    {"LIGHT MAGENTA", Color(255, 119, 255)},
    {"MAROON", Color(142, 35, 107)},
    {"MEDIUM AQUAMARINE", Color(50, 204, 153)},
    {"MEDIUM GREY", Color(100, 100, 100)},
    {"MEDIUM BLUE", Color(50, 50, 204)},
    {"MEDIUM FOREST GREEN", Color(107, 142, 35)},
    {"MEDIUM GOLDENROD", Color(234, 234, 173)},
    {"MEDIUM ORCHID", Color(147, 112, 219)},
    {"MEDIUM SEA GREEN", Color(66, 111, 66)},
    {"MEDIUM SLATE BLUE", Color(127, 0, 255)},
    {"MEDIUM SPRING GREEN", Color(127, 255, 0)},
    {"MEDIUM TURQUOISE", Color(112, 219, 219)},
    {"MEDIUM VIOLET RED", Color(219, 112, 147)},
    {"MIDNIGHT BLUE", Color(47, 47, 79)},
    {"NAVY", Color(35, 35, 142)},
    {"ORANGE RED", Color(255, 0, 127)},
    {"ORCHID", Color(219, 112, 219)},
    {"PALE GREEN", Color(143, 188, 143)},
    {"PINK", Color(255, 192, 203)},
    {"PLUM", Color(234, 173, 234)},
    {"PURPLE", Color(176, 0, 255)},
    {"SALMON", Color(111, 66, 66)},
    {"SEA GREEN", Color(35, 142, 107)},
    {"SIENNA", Color(142, 107, 35)},
    {"SKY BLUE", Color(50, 153, 204)},
    {"SLATE BLUE", Color(0, 127, 255)},
    {"SPRING GREEN", Color(0, 255, 127)},
    {"STEEL BLUE", Color(35, 107, 142)},
    {"TAN", Color(219, 147, 112)},
    {"THISTLE", Color(216, 191, 216)},
    {"TURQUOISE", Color(173, 234, 234)},
    {"VIOLET", Color(79, 47, 79)},
    {"VIOLET RED", Color(204, 50, 153)},
    {"WHEAT", Color(216, 216, 191)},
    {"YELLOW GREEN", Color(153, 204, 50)}
};

std::string Color::toString() const {
    std::ostringstream stream;
    stream << "#"
           << std::setfill('0') << std::setw(6)
           << std::hex << getRGB(false);
    return stream.str();
}

void Color::setFromString(const std::string& str) {
    alpha = 255;
    if (str.empty()) {
        red = green = blue = 0;
        return;
    }

    // #RRGGBB format
    if (str[0] == '#' && str.size() == 7) {
        unsigned long tmp = std::strtoul(&str[1], nullptr, 16);
        set(static_cast<uint8_t>(tmp >> 16),
            static_cast<uint8_t>(tmp >> 8),
            static_cast<uint8_t>(tmp));
        return;
    }

    // #AARRGGBB format
    if (str[0] == '#' && str.size() == 9) {
        unsigned long tmp = std::strtoul(&str[1], nullptr, 16);
        set(static_cast<uint8_t>(tmp >> 16),
            static_cast<uint8_t>(tmp >> 8),
            static_cast<uint8_t>(tmp),
            static_cast<uint8_t>(tmp >> 24));
        return;
    }

    // 0xRRGGBB format
    if (str.size() >= 8 && str[0] == '0' && str[1] == 'x') {
        unsigned long tmp = std::strtoul(&str[2], nullptr, 16);
        if (str.size() == 8) {
            set(static_cast<uint8_t>(tmp >> 16),
                static_cast<uint8_t>(tmp >> 8),
                static_cast<uint8_t>(tmp));
        } else if (str.size() == 10) {
            set(static_cast<uint8_t>(tmp >> 16),
                static_cast<uint8_t>(tmp >> 8),
                static_cast<uint8_t>(tmp),
                static_cast<uint8_t>(tmp >> 24));
        }
        return;
    }

    // rgb(r,g,b) or rgba(r,g,b,a) format
    if (str.size() > 5 && str[0] == 'r' && str[1] == 'g' && str[2] == 'b') {
        bool hasAlpha = (str[3] == 'a');
        size_t start = hasAlpha ? 5 : 4;

        std::string val = str.substr(start);
        std::string::size_type sz;

        red = static_cast<uint8_t>(std::stoi(val, &sz));
        val = val.substr(sz + 1);

        green = static_cast<uint8_t>(std::stoi(val, &sz));
        val = val.substr(sz + 1);

        blue = static_cast<uint8_t>(std::stoi(val, &sz));

        if (hasAlpha) {
            val = val.substr(sz + 1);
            float a = std::stof(val) * 255.0f;
            alpha = static_cast<uint8_t>(a);
        }
        return;
    }

    // Try named color
    auto it = NAME_MAP.find(str);
    if (it != NAME_MAP.end()) {
        *this = it->second;
        return;
    }

    // Default to black
    red = green = blue = 0;
}

// HSV to RGB conversion (matches xlColor algorithm)
void Color::fromHSV(const HSV& hsv) {
    double r, g, b;
    double value = std::clamp(hsv.value, 0.0, 1.0);
    double saturation = std::clamp(hsv.saturation, 0.0, 1.0);

    if (saturation == 0.0) {
        // Grey
        r = g = b = value;
    } else {
        double hue = std::clamp(hsv.hue, 0.0, 1.0) * 6.0;  // sector 0 to 5
        int i = static_cast<int>(std::floor(hue));
        double f = hue - i;  // fractional part
        double p = value * (1.0 - saturation);

        switch (i) {
            case 6:
            case 0:
                r = value;
                g = value * (1.0 - saturation * (1.0 - f));
                b = p;
                break;
            case 1:
                r = value * (1.0 - saturation * f);
                g = value;
                b = p;
                break;
            case 2:
                r = p;
                g = value;
                b = value * (1.0 - saturation * (1.0 - f));
                break;
            case 3:
                r = p;
                g = value * (1.0 - saturation * f);
                b = value;
                break;
            case 4:
                r = value * (1.0 - saturation * (1.0 - f));
                g = p;
                b = value;
                break;
            default:  // case 5
                r = value;
                g = p;
                b = value * (1.0 - saturation * f);
                break;
        }
    }

    set(static_cast<uint8_t>(r * 255.0),
        static_cast<uint8_t>(g * 255.0),
        static_cast<uint8_t>(b * 255.0));
}

// RGB to HSV conversion (optimized algorithm from lolengine.net)
void Color::toHSV(HSV& v) const {
    double r = red / 255.0;
    double g = green / 255.0;
    double b = blue / 255.0;

    double K = 0.0;
    if (g < b) {
        std::swap(g, b);
        K = -1.0;
    }

    double min_gb = b;
    if (r < g) {
        std::swap(r, g);
        K = -2.0 / 6.0 - K;
        min_gb = std::min(g, b);
    }

    double chroma = r - min_gb;
    v.hue = std::abs(K + (g - b) / (6.0 * chroma + 1e-20));
    v.saturation = chroma / (r + 1e-20);
    v.value = r;
}

HSV Color::toHSV() const {
    HSV v;
    toHSV(v);
    return v;
}

// Helper for HSL conversion
static double hue2RGB(double v1, double v2, double H) {
    if (H < 0.0) H += 1.0;
    if (H > 1.0) H -= 1.0;
    if ((6.0 * H) < 1.0) return (v1 + (v2 - v1) * 6.0 * H);
    if ((2.0 * H) < 1.0) return v2;
    if ((3.0 * H) < 2.0) return (v1 + (v2 - v1) * ((2.0 / 3.0) - H) * 6.0);
    return v1;
}

void Color::fromHSL(const HSL& hsl) {
    if (hsl.saturation == 0) {
        uint8_t l = static_cast<uint8_t>(hsl.lightness * 255.0);
        red = green = blue = l;
        return;
    }

    double v2;
    if (hsl.lightness < 0.5) {
        v2 = hsl.lightness * (1.0 + hsl.saturation);
    } else {
        v2 = (hsl.lightness + hsl.saturation) - (hsl.saturation * hsl.lightness);
    }

    double v1 = 2.0 * hsl.lightness - v2;

    red = static_cast<uint8_t>(255.0 * hue2RGB(v1, v2, hsl.hue + (1.0 / 3.0)) + 0.5);
    green = static_cast<uint8_t>(255.0 * hue2RGB(v1, v2, hsl.hue) + 0.5);
    blue = static_cast<uint8_t>(255.0 * hue2RGB(v1, v2, hsl.hue - (1.0 / 3.0)) + 0.5);
}

void Color::toHSL(HSL& hsl) const {
    double rgb[3];
    rgb[0] = red / 255.0;
    rgb[1] = green / 255.0;
    rgb[2] = blue / 255.0;

    double minVal = std::min({rgb[0], rgb[1], rgb[2]});
    double maxVal = std::max({rgb[0], rgb[1], rgb[2]});
    double delta = maxVal - minVal;

    hsl.lightness = (maxVal + minVal) / 2.0;

    if (delta == 0) {
        // Grey
        hsl.hue = -1.0;
        hsl.saturation = 0;
        return;
    }

    if (hsl.lightness <= 0.5) {
        hsl.saturation = delta / (maxVal + minVal);
    } else {
        hsl.saturation = delta / (2.0 - maxVal - minVal);
    }

    double dr = (((maxVal - rgb[0]) / 6.0) + (delta / 2.0)) / delta;
    double dg = (((maxVal - rgb[1]) / 6.0) + (delta / 2.0)) / delta;
    double db = (((maxVal - rgb[2]) / 6.0) + (delta / 2.0)) / delta;

    if (rgb[0] == maxVal) {
        hsl.hue = db - dg;
    } else if (rgb[1] == maxVal) {
        hsl.hue = (1.0 / 3.0) + dr - db;
    } else {
        hsl.hue = (2.0 / 3.0) + dg - dr;
    }

    if (hsl.hue < 0.0) hsl.hue += 1.0;
    if (hsl.hue > 1.0) hsl.hue -= 1.0;
}

HSL Color::toHSL() const {
    HSL hsl;
    toHSL(hsl);
    return hsl;
}

// sRGB helper for contrast calculation
static float getSRGB(float r) {
    r /= 255.0f;
    return r <= 0.03928f ? r / 12.92f : std::pow((r + 0.055f) / 1.055f, 2.4f);
}

static float getRelativeLuminance(const Color& c) {
    return 0.2126f * getSRGB(c.red) +
           0.7152f * getSRGB(c.green) +
           0.0722f * getSRGB(c.blue);
}

static float getColourContrast(const Color& c1, const Color& c2) {
    float L1 = getRelativeLuminance(c1);
    float L2 = getRelativeLuminance(c2);
    return L1 > L2 ? (L1 + 0.05f) / (L2 + 0.05f) : (L2 + 0.05f) / (L1 + 0.05f);
}

bool Color::hasSufficientContrast(const Color& background) const {
    return getColourContrast(background, *this) >= 4.5f;
}

Color Color::contrastColorNotBlack() const {
    HSL hsl = toHSL();
    hsl.hue += 0.5;
    if (hsl.hue > 1.0) hsl.hue -= 1.0;

    if (hsl.lightness > 0.8 || hsl.lightness < 0.2) {
        hsl.lightness = 0.5;
    }

    Color c;
    c.fromHSL(hsl);
    return c;
}

} // namespace xlCore
