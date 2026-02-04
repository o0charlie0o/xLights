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
 * @file Color.h
 * @brief Color class with RGB, HSV, and HSL conversions.
 *
 * This is a pure C++17/20 replacement for wxColour and xlColor,
 * designed for the xlCore engine library. It maintains behavioral
 * compatibility with the existing xlColor class while removing
 * all wxWidgets dependencies.
 */

#include <cstdint>
#include <cmath>
#include <algorithm>
#include <string>
#include <array>
#include <vector>

namespace xlCore {

/**
 * @brief HSV (Hue, Saturation, Value) color representation.
 *
 * All components are normalized to [0.0, 1.0] range.
 * Hue: 0.0 = red, 0.333 = green, 0.667 = blue
 */
struct HSV {
    double hue = 0.0;
    double saturation = 0.0;
    double value = 0.0;

    constexpr HSV() = default;
    constexpr HSV(double h, double s, double v)
        : hue(h), saturation(s), value(v) {}
};

/**
 * @brief HSL (Hue, Saturation, Lightness) color representation.
 *
 * All components are normalized to [0.0, 1.0] range.
 */
struct HSL {
    double hue = 0.0;
    double saturation = 0.0;
    double lightness = 0.0;

    constexpr HSL() = default;
    constexpr HSL(double h, double s, double l)
        : hue(h), saturation(s), lightness(l) {}
};

/**
 * @brief RGBA color class with HSV/HSL conversion support.
 *
 * Thread-safe, constexpr-friendly color class that provides:
 * - Direct RGBA component access
 * - HSV/HSL conversion (compatible with xlColor algorithms)
 * - Alpha blending operations
 * - String serialization (#RRGGBB format)
 */
class Color {
public:
    uint8_t red = 0;
    uint8_t green = 0;
    uint8_t blue = 0;
    uint8_t alpha = 255;

    // Constructors
    constexpr Color() = default;

    constexpr Color(uint8_t r, uint8_t g, uint8_t b)
        : red(r), green(g), blue(b), alpha(255) {}

    constexpr Color(uint8_t r, uint8_t g, uint8_t b, uint8_t a)
        : red(r), green(g), blue(b), alpha(a) {}

    /**
     * @brief Construct from packed RGB value.
     * @param rgb Packed RGB value
     * @param BBGGRR If true, interpret as BBGGRR order; otherwise RRGGBB
     */
    constexpr explicit Color(uint32_t rgb, bool BBGGRR = false) : alpha(255) {
        if (BBGGRR) {
            red = rgb & 0xff;
            green = (rgb >> 8) & 0xff;
            blue = (rgb >> 16) & 0xff;
        } else {
            blue = rgb & 0xff;
            green = (rgb >> 8) & 0xff;
            red = (rgb >> 16) & 0xff;
        }
    }

    /**
     * @brief Construct from HSV values.
     */
    explicit Color(const HSV& hsv) {
        fromHSV(hsv);
    }

    /**
     * @brief Construct from HSL values.
     */
    explicit Color(const HSL& hsl) {
        fromHSL(hsl);
    }

    /**
     * @brief Construct from string (e.g., "#RRGGBB", "#AARRGGBB", "rgb(r,g,b)").
     */
    explicit Color(const std::string& str) {
        setFromString(str);
    }

    // Accessors - use lowercase r(), g(), b(), a() to avoid conflicts with static factories
    constexpr uint8_t r() const { return red; }
    constexpr uint8_t g() const { return green; }
    constexpr uint8_t b() const { return blue; }
    constexpr uint8_t a() const { return alpha; }

    // Setters
    constexpr void set(uint8_t r, uint8_t g, uint8_t b) {
        red = r;
        green = g;
        blue = b;
        alpha = 255;
    }

    constexpr void set(uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
        red = r;
        green = g;
        blue = b;
        alpha = a;
    }

    constexpr void setAlpha(uint8_t a) {
        alpha = a;
    }

    /**
     * @brief Check if color is fully transparent black (nil color).
     */
    constexpr bool isNil() const {
        return red == 0 && green == 0 && blue == 0 && alpha == 0;
    }

    // Comparison operators (alpha not compared for compatibility with xlColor)
    constexpr bool operator==(const Color& other) const {
        return red == other.red && green == other.green && blue == other.blue;
    }

    constexpr bool operator!=(const Color& other) const {
        return !(*this == other);
    }

    // Packed RGB getters
    constexpr uint32_t getRGB(bool BBGGRR = true) const {
        if (BBGGRR) {
            return red | (static_cast<uint32_t>(green) << 8) | (static_cast<uint32_t>(blue) << 16);
        } else {
            return blue | (static_cast<uint32_t>(green) << 8) | (static_cast<uint32_t>(red) << 16);
        }
    }

    constexpr uint32_t getRGBA(bool BBGGRR = true) const {
        if (BBGGRR) {
            return red | (static_cast<uint32_t>(green) << 8) |
                   (static_cast<uint32_t>(blue) << 16) | (static_cast<uint32_t>(alpha) << 24);
        } else {
            return blue | (static_cast<uint32_t>(green) << 8) |
                   (static_cast<uint32_t>(red) << 16) | (static_cast<uint32_t>(alpha) << 24);
        }
    }

    // HSV conversion
    HSV toHSV() const;
    void toHSV(HSV& hsv) const;
    void fromHSV(const HSV& hsv);

    Color& operator=(const HSV& hsv) {
        fromHSV(hsv);
        return *this;
    }

    // HSL conversion
    HSL toHSL() const;
    void toHSL(HSL& hsl) const;
    void fromHSL(const HSL& hsl);

    Color& operator=(const HSL& hsl) {
        fromHSL(hsl);
        return *this;
    }

    // Brightness
    int brightness() const {
        return std::max({static_cast<int>(red), static_cast<int>(green), static_cast<int>(blue)}) *
               static_cast<int>(alpha) / 255;
    }

    /**
     * @brief Apply brightness multiplier (0.0 to 1.0).
     */
    Color applyBrightness(float b) const {
        return Color(
            static_cast<uint8_t>(b * red),
            static_cast<uint8_t>(b * green),
            static_cast<uint8_t>(b * blue),
            alpha
        );
    }

    /**
     * @brief Alpha blend this color onto a background color.
     */
    Color alphaBlend(const Color& background) const {
        if (alpha == 0) return background;
        if (alpha == 255) return *this;

        float a = alpha / 255.0f;
        float dr = red * a + background.red * (1.0f - a);
        float dg = green * a + background.green * (1.0f - a);
        float db = blue * a + background.blue * (1.0f - a);

        return Color(
            static_cast<uint8_t>(dr),
            static_cast<uint8_t>(dg),
            static_cast<uint8_t>(db)
        );
    }

    /**
     * @brief Simple 50/50 blend of two colors.
     */
    Color blend(const Color& other) const {
        return Color(
            static_cast<uint8_t>((red + other.red) / 2),
            static_cast<uint8_t>((green + other.green) / 2),
            static_cast<uint8_t>((blue + other.blue) / 2)
        );
    }

    /**
     * @brief Return color with max of each channel.
     */
    Color channelMax(const Color& other) const {
        return Color(
            std::max(red, other.red),
            std::max(green, other.green),
            std::max(blue, other.blue)
        );
    }

    /**
     * @brief Return copy with specified alpha value.
     */
    Color withAlpha(uint8_t a) const {
        return Color(red, green, blue, a);
    }

    /**
     * @brief Return copy with specified HSV value (brightness).
     */
    Color withValue(double v) const {
        HSV hsv = toHSV();
        hsv.value = std::clamp(v, 0.0, 1.0);
        return Color(hsv);
    }

    /**
     * @brief Get HSV value (brightness) component.
     */
    double value() const {
        return toHSV().value;
    }

    /**
     * @brief Alpha blend foreground onto this color (modifies in place).
     */
    void alphaBlendForegroundOnto(const Color& fg) {
        if (fg.alpha == 0) return;
        if (fg.alpha == 255) {
            red = fg.red;
            green = fg.green;
            blue = fg.blue;
            alpha = 255;
            return;
        }

        float a = fg.alpha / 255.0f;
        red = static_cast<uint8_t>(fg.red * a + red * (1.0f - a));
        green = static_cast<uint8_t>(fg.green * a + green * (1.0f - a));
        blue = static_cast<uint8_t>(fg.blue * a + blue * (1.0f - a));
    }

    /**
     * @brief Check if color has sufficient contrast against background (WCAG 4.5:1).
     */
    bool hasSufficientContrast(const Color& background) const;

    /**
     * @brief Return a contrasting color (not black).
     */
    Color contrastColorNotBlack() const;

    // String conversion
    void setFromString(const std::string& str);
    std::string toString() const;

    operator std::string() const {
        return toString();
    }

    // Static factory methods
    static constexpr Color nil() {
        return Color(0, 0, 0, 0);
    }

    /**
     * @brief Create color from HSV values.
     * @param h Hue (0.0-1.0)
     * @param s Saturation (0.0-1.0)
     * @param v Value/brightness (0.0-1.0)
     */
    static Color fromHSV(float h, float s, float v) {
        Color c;
        c.fromHSV(HSV(static_cast<double>(h), static_cast<double>(s), static_cast<double>(v)));
        return c;
    }

    /**
     * @brief Create color from HSL values.
     * @param h Hue (0.0-1.0)
     * @param s Saturation (0.0-1.0)
     * @param l Lightness (0.0-1.0)
     */
    static Color fromHSL(float h, float s, float l) {
        Color c;
        c.fromHSL(HSL(static_cast<double>(h), static_cast<double>(s), static_cast<double>(l)));
        return c;
    }

    // Predefined colors (named with Color suffix to avoid conflict with member variables)
    static constexpr Color Black() { return Color(0, 0, 0); }
    static constexpr Color White() { return Color(255, 255, 255); }
    static constexpr Color Red() { return Color(255, 0, 0); }
    static constexpr Color Green() { return Color(0, 255, 0); }
    static constexpr Color Blue() { return Color(0, 0, 255); }
    static constexpr Color Yellow() { return Color(255, 255, 0); }
    static constexpr Color Cyan() { return Color(0, 255, 255); }
    static constexpr Color Magenta() { return Color(255, 0, 255); }
    static constexpr Color Orange() { return Color(255, 128, 0); }
    static constexpr Color LightGrey() { return Color(211, 211, 211); }
    static constexpr Color DarkGrey() { return Color(96, 96, 96); }

    // Translucent variants
    static constexpr Color RedTranslucent() { return Color(255, 0, 0, 150); }
    static constexpr Color GreenTranslucent() { return Color(0, 255, 0, 150); }
    static constexpr Color BlueTranslucent() { return Color(0, 0, 255, 180); }
    static constexpr Color WhiteTranslucent() { return Color(255, 255, 255, 150); }
    static constexpr Color YellowTranslucent() { return Color(255, 255, 0, 150); }
    static constexpr Color CyanTranslucent() { return Color(0, 255, 255, 150); }
    static constexpr Color MagentaTranslucent() { return Color(255, 0, 255, 150); }
    static constexpr Color OrangeTranslucent() { return Color(255, 128, 0, 150); }
};

// Type alias for compatibility
using ColorVector = std::vector<Color>;
using HSVVector = std::vector<HSV>;

} // namespace xlCore
