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
 * @file TextEffect.h
 * @brief Pure C++ text rendering effect for xlCore.
 *
 * This effect renders text with various movement and styling options.
 * Font rendering is abstracted through the FontRenderer interface to
 * allow platform-specific implementations (Core Text on macOS,
 * DirectWrite on Windows, FreeType on Linux).
 */

#include "../Effect.h"
#include "../ImageBuffer.h"

#include <string>
#include <vector>
#include <memory>
#include <optional>

namespace xlCore {

// Forward declarations
class FontRenderer;

/**
 * @brief Text movement/scroll direction.
 */
enum class TextDirection {
    None,           ///< Static text
    Left,           ///< Scroll left
    Right,          ///< Scroll right
    Up,             ///< Scroll up
    Down,           ///< Scroll down
    UpLeft,         ///< Scroll up-left
    DownLeft,       ///< Scroll down-left
    UpRight,        ///< Scroll up-right
    DownRight,      ///< Scroll down-right
    Wavey,          ///< Wavey left-to-right with up/down
    Vector,         ///< Move along vector from start to end point
    WordFlip,       ///< Flip through words
    LeftRight,      ///< Bounce left-right
    UpDown          ///< Bounce up-down
};

/**
 * @brief Text transformation effect.
 */
enum class TextTransform {
    Normal,         ///< Normal horizontal text
    VertTextUp,     ///< Vertical text (read bottom to top)
    VertTextDown,   ///< Vertical text (read top to bottom)
    RotateUp45,     ///< Rotate 45 degrees up
    RotateUp90,     ///< Rotate 90 degrees up
    RotateDown45,   ///< Rotate 45 degrees down
    RotateDown90    ///< Rotate 90 degrees down
};

/**
 * @brief Countdown display mode.
 */
enum class CountdownMode {
    None,           ///< No countdown
    Seconds,        ///< Count down seconds
    DaysHoursMinsSecs,  ///< "Xd Xh Xm Xs" format
    HoursMinsSecs,  ///< "X:X:X" format
    MinsOrSecs,     ///< Show minutes if > 5 min, else seconds
    SecsOnly,       ///< Show only seconds
    FreeFormat,     ///< Custom format string
    MinutesSecs     ///< "X:XX" format
};

/**
 * @brief Rendered text metrics.
 */
struct TextMetrics {
    int width = 0;          ///< Total width in pixels
    int height = 0;         ///< Total height in pixels
    int ascent = 0;         ///< Distance from baseline to top
    int descent = 0;        ///< Distance from baseline to bottom
    int lineHeight = 0;     ///< Height of single line
    std::vector<int> lineWidths;  ///< Width of each line
};

/**
 * @brief Abstract interface for font rendering.
 *
 * Platform-specific implementations provide actual font rasterization.
 * This allows using Core Text on macOS, DirectWrite on Windows,
 * and FreeType on Linux.
 */
class FontRenderer {
public:
    virtual ~FontRenderer() = default;

    /**
     * @brief Load a font by name and size.
     * @param fontName System font name or path to font file
     * @param size Font size in points
     * @return true if font loaded successfully
     */
    virtual bool loadFont(const std::string& fontName, int size) = 0;

    /**
     * @brief Measure text dimensions without rendering.
     * @param text Text to measure (may contain newlines)
     * @return Text metrics
     */
    virtual TextMetrics measureText(const std::string& text) = 0;

    /**
     * @brief Render text to an image buffer.
     * @param text Text to render
     * @param color Text color
     * @return ImageBuffer containing rendered text (RGBA format)
     *
     * The returned buffer should be sized exactly to fit the text.
     * Background should be transparent (alpha = 0).
     */
    virtual ImageBuffer renderText(const std::string& text, const Color& color) = 0;

    /**
     * @brief Render text with per-character colors.
     * @param text Text to render
     * @param colors Color for each character (cycles if fewer than chars)
     * @return ImageBuffer containing rendered text
     */
    virtual ImageBuffer renderTextMultiColor(const std::string& text,
                                             const std::vector<Color>& colors) = 0;

    /**
     * @brief Get the font name.
     */
    virtual std::string fontName() const = 0;

    /**
     * @brief Get the font size.
     */
    virtual int fontSize() const = 0;

    /**
     * @brief Check if font is loaded and valid.
     */
    virtual bool isValid() const = 0;
};

/**
 * @brief Font manager for discovering and caching fonts.
 */
class FontManager {
public:
    virtual ~FontManager() = default;

    /**
     * @brief Get list of available system fonts.
     */
    virtual std::vector<std::string> availableFonts() = 0;

    /**
     * @brief Find font file path by name.
     * @param fontName Font family name
     * @return Full path to font file, or empty if not found
     */
    virtual std::optional<std::string> findFont(const std::string& fontName) = 0;

    /**
     * @brief Get system font directories.
     */
    virtual std::vector<std::string> fontDirectories() = 0;

    /**
     * @brief Create a font renderer for the specified font.
     * @param fontName Font name
     * @param size Font size in points
     * @return FontRenderer instance, or nullptr if failed
     */
    virtual std::unique_ptr<FontRenderer> createRenderer(const std::string& fontName, int size) = 0;

    /**
     * @brief Get singleton instance.
     *
     * Must be set by platform layer during initialization.
     */
    static FontManager* instance();
    static void setInstance(FontManager* manager);

private:
    static FontManager* s_instance;
};

/**
 * @brief Text rendering effect.
 *
 * Renders text with configurable:
 * - Font (system fonts or xLights built-in fonts)
 * - Movement direction (static, scrolling, etc.)
 * - Text transformations (rotation, vertical text)
 * - Countdown modes
 * - Per-character or per-word coloring
 */
class TextEffect : public Effect {
public:
    TextEffect();
    ~TextEffect() override = default;

    // Identity
    std::string name() const override { return "Text"; }
    std::string description() const override { return "Render text with scrolling and styling"; }
    std::string category() const override { return "Text"; }

    // Rendering
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // Parameters
    std::vector<EffectParameter> parameters() const override;

    // Capabilities
    bool canBeRandom() const override { return false; }
    bool appropriateOnNodes() const override { return false; }

    // Cloning
    std::unique_ptr<Effect> clone() const override;

protected:
    /**
     * @brief Calculate text offset based on direction and state.
     */
    void calculateOffset(int& offsetX, int& offsetY,
                        TextDirection direction, const RenderState& state,
                        int textWidth, int textHeight,
                        int bufferWidth, int bufferHeight,
                        const EffectSettings& settings) const;

    /**
     * @brief Format countdown text.
     */
    std::string formatCountdown(CountdownMode mode, const std::string& text,
                                const RenderState& state) const;

    /**
     * @brief Replace variable placeholders in text.
     */
    std::string replaceVariables(const std::string& text,
                                 const RenderState& state) const;

    /**
     * @brief Split text into words.
     */
    std::vector<std::string> splitWords(const std::string& text) const;

    /**
     * @brief Get current word for word-flip mode.
     */
    std::string getCurrentWord(const std::vector<std::string>& words,
                               const EffectSettings& settings,
                               const RenderState& state) const;

private:
    // Cached font renderer
    mutable std::unique_ptr<FontRenderer> m_fontRenderer;
    mutable std::string m_cachedFontKey;
};

// Helper functions
TextDirection parseTextDirection(const std::string& str);
TextTransform parseTextTransform(const std::string& str);
CountdownMode parseCountdownMode(const std::string& str);

} // namespace xlCore
