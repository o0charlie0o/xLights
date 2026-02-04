/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "TextEffect.h"
#include "../RenderContext.h"
#include "../StringUtils.h"

#include <cmath>
#include <algorithm>
#include <chrono>
#include <sstream>
#include <iomanip>

namespace xlCore {

// Static instance for FontManager
FontManager* FontManager::s_instance = nullptr;

FontManager* FontManager::instance() {
    return s_instance;
}

void FontManager::setInstance(FontManager* manager) {
    s_instance = manager;
}

// ============================================================================
// Helper function implementations
// ============================================================================

TextDirection parseTextDirection(const std::string& str) {
    if (str == "left") return TextDirection::Left;
    if (str == "right") return TextDirection::Right;
    if (str == "up") return TextDirection::Up;
    if (str == "down") return TextDirection::Down;
    if (str == "none") return TextDirection::None;
    if (str == "up-left") return TextDirection::UpLeft;
    if (str == "down-left") return TextDirection::DownLeft;
    if (str == "up-right") return TextDirection::UpRight;
    if (str == "down-right") return TextDirection::DownRight;
    if (str == "wavey") return TextDirection::Wavey;
    if (str == "vector") return TextDirection::Vector;
    if (str == "word-flip") return TextDirection::WordFlip;
    if (str == "left-right") return TextDirection::LeftRight;
    if (str == "up-down") return TextDirection::UpDown;
    return TextDirection::None;
}

TextTransform parseTextTransform(const std::string& str) {
    if (str == "normal") return TextTransform::Normal;
    if (str == "vert text up") return TextTransform::VertTextUp;
    if (str == "vert text down") return TextTransform::VertTextDown;
    if (str == "rotate up 45") return TextTransform::RotateUp45;
    if (str == "rotate up 90") return TextTransform::RotateUp90;
    if (str == "rotate down 45") return TextTransform::RotateDown45;
    if (str == "rotate down 90") return TextTransform::RotateDown90;
    return TextTransform::Normal;
}

CountdownMode parseCountdownMode(const std::string& str) {
    if (str == "none") return CountdownMode::None;
    if (str == "seconds") return CountdownMode::Seconds;
    if (str == "to date 'd h m s'") return CountdownMode::DaysHoursMinsSecs;
    if (str == "to date 'h:m:s'") return CountdownMode::HoursMinsSecs;
    if (str == "to date 'm' or 's'") return CountdownMode::MinsOrSecs;
    if (str == "to date 's'") return CountdownMode::SecsOnly;
    if (str == "!to date!%fmt") return CountdownMode::FreeFormat;
    if (str == "minutes seconds") return CountdownMode::MinutesSecs;
    return CountdownMode::None;
}

// ============================================================================
// TextEffect implementation
// ============================================================================

TextEffect::TextEffect() = default;

std::vector<EffectParameter> TextEffect::parameters() const {
    std::vector<EffectParameter> params;

    // Text content
    params.push_back(EffectParameter::createChoice(
        "TEXTCTRL_Text", "Text", "",
        {}  // Text is free-form, not a fixed choice
    ));
    params.back().type = ParameterType::String;
    params.back().description = "Text to display (supports \\n for newlines)";

    // Font selection
    params.push_back(EffectParameter::createChoice(
        "FONTPICKER_Text_Font", "Font", "arial,12",
        {}  // Font list populated dynamically
    ));
    params.back().type = ParameterType::String;
    params.back().description = "Font name and size";

    // Direction
    params.push_back(EffectParameter::createChoice(
        "CHOICE_Text_Dir", "Movement", "none",
        {"none", "left", "right", "up", "down", "up-left", "down-left",
         "up-right", "down-right", "wavey", "vector", "word-flip",
         "left-right", "up-down"}
    ));

    // Speed
    params.push_back(EffectParameter::createInt(
        "TEXTCTRL_Text_Speed", "Speed", 10, 0, 50, true
    ));

    // Effect/transform
    params.push_back(EffectParameter::createChoice(
        "CHOICE_Text_Effect", "Transform", "normal",
        {"normal", "vert text up", "vert text down", "rotate up 45",
         "rotate up 90", "rotate down 45", "rotate down 90"}
    ));

    // Countdown
    params.push_back(EffectParameter::createChoice(
        "CHOICE_Text_Count", "Countdown", "none",
        {"none", "seconds", "to date 'd h m s'", "to date 'h:m:s'",
         "to date 'm' or 's'", "to date 's'", "!to date!%fmt", "minutes seconds"}
    ));

    // Position controls
    params.push_back(EffectParameter::createInt(
        "SLIDER_Text_XStart", "X Start", 0, -100, 100, true
    ));
    params.push_back(EffectParameter::createInt(
        "SLIDER_Text_YStart", "Y Start", 0, -100, 100, true
    ));
    params.push_back(EffectParameter::createInt(
        "SLIDER_Text_XEnd", "X End", 0, -100, 100, true
    ));
    params.push_back(EffectParameter::createInt(
        "SLIDER_Text_YEnd", "Y End", 0, -100, 100, true
    ));

    // Options
    params.push_back(EffectParameter::createBool(
        "CHECKBOX_TextToCenter", "Center", false
    ));
    params.push_back(EffectParameter::createBool(
        "CHECKBOX_TextNoRepeat", "No Repeat", false
    ));
    params.push_back(EffectParameter::createBool(
        "CHECKBOX_Text_PixelOffsets", "Pixel Offsets", false
    ));
    params.push_back(EffectParameter::createBool(
        "CHECKBOX_Text_Color_PerWord", "Color Per Word", false
    ));

    // File source (optional)
    params.push_back(EffectParameter::createFile(
        "FILEPICKERCTRL_Text_File", "Text File", "Text files|*.txt"
    ));

    return params;
}

void TextEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get text to render
    std::string text = settings.get("TEXTCTRL_Text", "");

    // Replace \n with actual newlines
    size_t pos = 0;
    while ((pos = text.find("\\n", pos)) != std::string::npos) {
        text.replace(pos, 2, "\n");
        pos++;
    }

    // Apply variable replacements
    text = replaceVariables(text, state);

    // Check for word-flip mode
    TextDirection direction = parseTextDirection(settings.get("CHOICE_Text_Dir", "none"));
    if (direction == TextDirection::WordFlip) {
        auto words = splitWords(text);
        if (!words.empty()) {
            text = getCurrentWord(words, settings, state);
        }
    }

    // Get countdown mode and format if needed
    CountdownMode countdown = parseCountdownMode(settings.get("CHOICE_Text_Count", "none"));
    if (countdown != CountdownMode::None) {
        text = formatCountdown(countdown, text, state);
    }

    // Empty text - nothing to render
    if (text.empty()) {
        return;
    }

    // Get font settings
    std::string fontString = settings.get("FONTPICKER_Text_Font", "arial,12");

    // Check if we need to create/update font renderer
    if (!m_fontRenderer || m_cachedFontKey != fontString) {
        // Parse font string (format: "fontname,size" or "fontname size pointSize")
        std::string fontName = "Arial";
        int fontSize = 12;

        auto parts = strings::split(fontString, ',');
        if (parts.size() >= 2) {
            fontName = strings::trim(parts[0]);
            fontSize = strings::parseInt(parts[1], 12);
        } else {
            // Try space-separated format
            auto spaceParts = strings::split(fontString, ' ');
            if (!spaceParts.empty()) {
                fontName = spaceParts[0];
                // Look for numeric size
                for (const auto& part : spaceParts) {
                    int val = strings::parseInt(part, 0);
                    if (val > 0 && val < 500) {
                        fontSize = val;
                    }
                }
            }
        }

        // Create font renderer if manager available
        if (FontManager::instance()) {
            m_fontRenderer = FontManager::instance()->createRenderer(fontName, fontSize);
            m_cachedFontKey = fontString;
        }
    }

    // If no font renderer, we cannot render text
    if (!m_fontRenderer || !m_fontRenderer->isValid()) {
        return;
    }

    // Get text transform
    TextTransform transform = parseTextTransform(settings.get("CHOICE_Text_Effect", "normal"));

    // Apply vertical text transform (turns text into one char per line)
    if (transform == TextTransform::VertTextUp || transform == TextTransform::VertTextDown) {
        std::string vertText;
        for (size_t i = 0; i < text.length(); i++) {
            size_t idx = (transform == TextTransform::VertTextUp) ? (text.length() - i - 1) : i;
            vertText += text[idx];
            if (i < text.length() - 1) {
                vertText += '\n';
            }
        }
        text = vertText;
    }

    // Get colors for rendering
    bool perWord = settings.getBool("CHECKBOX_Text_Color_PerWord", false);
    std::vector<Color> colors;

    // TODO: Get colors from palette when palette support is added to RenderContext
    // For now, use white as default
    colors.push_back(Color::White());

    // Render text to image
    ImageBuffer textImage;
    if (colors.size() > 1 || perWord) {
        textImage = m_fontRenderer->renderTextMultiColor(text, colors);
    } else {
        textImage = m_fontRenderer->renderText(text, colors.empty() ? Color::White() : colors[0]);
    }

    if (textImage.isEmpty()) {
        return;
    }

    // Calculate position
    int offsetX = 0;
    int offsetY = 0;

    calculateOffset(offsetX, offsetY, direction, state,
                   textImage.width(), textImage.height(),
                   ctx.width(), ctx.height(), settings);

    // Apply text transform rotations
    // TODO: Implement rotation transforms (requires rotating the image buffer)

    // Blit text image to render context
    int textW = textImage.width();
    int textH = textImage.height();

    for (int y = 0; y < textH; y++) {
        for (int x = 0; x < textW; x++) {
            Color pixel = textImage.getPixel(x, y);
            if (pixel.alpha > 0) {
                int destX = x + offsetX;
                int destY = (textH - 1 - y) + offsetY;  // Flip Y for xLights coordinate system

                if (destX >= 0 && destX < ctx.width() &&
                    destY >= 0 && destY < ctx.height()) {
                    ctx.setPixelBlended(destX, destY, pixel);
                }
            }
        }
    }
}

void TextEffect::calculateOffset(int& offsetX, int& offsetY,
                                 TextDirection direction, const RenderState& state,
                                 int textWidth, int textHeight,
                                 int bufferWidth, int bufferHeight,
                                 const EffectSettings& settings) const {
    int speed = settings.getInt("TEXTCTRL_Text_Speed", 10);
    int startX = settings.getInt("SLIDER_Text_XStart", 0);
    int startY = settings.getInt("SLIDER_Text_YStart", 0);
    int endX = settings.getInt("SLIDER_Text_XEnd", 0);
    int endY = settings.getInt("SLIDER_Text_YEnd", 0);
    bool pixelOffsets = settings.getBool("CHECKBOX_Text_PixelOffsets", false);
    bool center = settings.getBool("CHECKBOX_TextToCenter", false);
    bool noRepeat = settings.getBool("CHECKBOX_TextNoRepeat", false);

    // Convert percentage to pixel offsets if needed
    int baseOffsetX = pixelOffsets ? startX : (startX * bufferWidth / 100);
    int baseOffsetY = pixelOffsets ? -startY : (-startY * bufferHeight / 100);

    // Calculate movement state
    int frameTimeMs = 50;  // Default frame time
    if (state.totalFrames > 0) {
        frameTimeMs = static_cast<int>((state.effectEndTime - state.effectStartTime) * 1000 / state.totalFrames);
    }
    int animState = state.frameIndex * speed * frameTimeMs / 50;

    // Calculate total travel distances
    int totalWidth = bufferWidth + textWidth;
    int totalHeight = bufferHeight + textHeight;
    int xlimit = totalWidth * 8 + 1;
    int ylimit = totalHeight * 8 + 1;

    // Zigzag helper for bounce effects
    auto zigzag = [](int value, int range) -> int {
        if (range == 0) return 0;
        return ((value / range) & 1) ?
               (value % range) :
               (range - value % range - 1);
    };

    switch (direction) {
        case TextDirection::None:
        case TextDirection::WordFlip:
            offsetX = baseOffsetX + (bufferWidth - textWidth) / 2;
            offsetY = baseOffsetY + (bufferHeight - textHeight) / 2;
            break;

        case TextDirection::Left:
            if (noRepeat && !center && animState > xlimit) {
                offsetX = -xlimit;
            } else if (center) {
                offsetX = std::max(xlimit / 16 - animState / 8, -textWidth / 2);
            } else {
                offsetX = xlimit / 16 - (animState % xlimit) / 8;
            }
            offsetY = baseOffsetY + (bufferHeight - textHeight) / 2;
            break;

        case TextDirection::Right:
            if (noRepeat && !center && animState > xlimit) {
                offsetX = xlimit;
            } else if (center) {
                offsetX = std::min(animState / 8 - xlimit / 16, textWidth / 2);
            } else {
                offsetX = (animState % xlimit) / 8 - xlimit / 16;
            }
            offsetY = baseOffsetY + (bufferHeight - textHeight) / 2;
            break;

        case TextDirection::Up:
            offsetX = baseOffsetX + (bufferWidth - textWidth) / 2;
            if (noRepeat && !center && animState > ylimit) {
                offsetY = -ylimit;
            } else if (center) {
                offsetY = std::max(ylimit / 16 - animState / 8, 0);
            } else {
                offsetY = ylimit / 16 - (animState % ylimit) / 8;
            }
            break;

        case TextDirection::Down:
            offsetX = baseOffsetX + (bufferWidth - textWidth) / 2;
            if (noRepeat && !center && animState > ylimit) {
                offsetY = ylimit;
            } else if (center) {
                offsetY = std::min(animState / 8 - ylimit / 16, 0);
            } else {
                offsetY = (animState % ylimit) / 8 - ylimit / 16;
            }
            break;

        case TextDirection::Vector: {
            double position = state.progress;
            double ex = pixelOffsets ? endX : (endX * bufferWidth / 100);
            double ey = pixelOffsets ? -endY : (-endY * bufferHeight / 100);

            offsetX = static_cast<int>(baseOffsetX + (ex - baseOffsetX) * position);
            offsetY = static_cast<int>(baseOffsetY + (ey - baseOffsetY) * position);

            // Center the text
            offsetX += (bufferWidth - textWidth) / 2;
            offsetY += (bufferHeight - textHeight) / 2;
            break;
        }

        case TextDirection::LeftRight: {
            int cycle = xlimit;
            int halfCycle = xlimit / 2;
            int normalizedState = animState % cycle;

            if (normalizedState <= halfCycle) {
                offsetX = xlimit / 8 - (normalizedState * (xlimit / 4)) / halfCycle;
            } else {
                offsetX = -xlimit / 8 + ((normalizedState - halfCycle) * (xlimit / 4)) / halfCycle;
            }
            offsetY = baseOffsetY + (bufferHeight - textHeight) / 2;
            break;
        }

        case TextDirection::UpDown: {
            int cycle = ylimit;
            int halfCycle = ylimit / 2;
            int normalizedState = animState % cycle;

            offsetX = baseOffsetX + (bufferWidth - textWidth) / 2;
            if (normalizedState <= halfCycle) {
                offsetY = ylimit / 16 - (normalizedState * (ylimit / 8)) / halfCycle;
            } else {
                offsetY = -ylimit / 16 + ((normalizedState - halfCycle) * (ylimit / 8)) / halfCycle;
            }
            break;
        }

        case TextDirection::Wavey:
            offsetX = xlimit / 16 - (animState % xlimit) / 8;
            offsetY = zigzag(animState / 4, totalHeight) / 2 - totalHeight / 4;
            break;

        case TextDirection::UpLeft:
            offsetX = center ? std::max(xlimit / 16 - animState / 8, 0) : xlimit / 16 - (animState % xlimit) / 8;
            offsetY = center ? std::max(ylimit / 16 - animState / 8, 0) : ylimit / 16 - (animState % ylimit) / 8;
            break;

        case TextDirection::DownLeft:
            offsetX = center ? std::max(xlimit / 16 - animState / 8, 0) : xlimit / 16 - (animState % xlimit) / 8;
            offsetY = center ? std::min(animState / 8 - ylimit / 16, 0) : (animState % ylimit) / 8 - ylimit / 16;
            break;

        case TextDirection::UpRight:
            offsetX = center ? std::min(animState / 8 - xlimit / 16, 0) : (animState % xlimit) / 8 - xlimit / 16;
            offsetY = center ? std::max(ylimit / 16 - animState / 8, 0) : ylimit / 16 - (animState % ylimit) / 8;
            break;

        case TextDirection::DownRight:
            offsetX = center ? std::min(animState / 8 - xlimit / 16, 0) : (animState % xlimit) / 8 - xlimit / 16;
            offsetY = center ? std::min(animState / 8 - ylimit / 16, 0) : (animState % ylimit) / 8 - ylimit / 16;
            break;
    }
}

std::string TextEffect::formatCountdown(CountdownMode mode, const std::string& text,
                                        const RenderState& state) const {
    if (mode == CountdownMode::None) {
        return text;
    }

    // Calculate frame rate
    int framesPerSec = 20;  // Default
    if (state.totalFrames > 0) {
        double duration = state.effectEndTime - state.effectStartTime;
        if (duration > 0) {
            framesPerSec = static_cast<int>(state.totalFrames / duration);
        }
    }

    std::stringstream result;

    switch (mode) {
        case CountdownMode::Seconds: {
            // text should contain the starting number of seconds
            int startSeconds = strings::parseInt(text, 0);
            int elapsed = state.frameIndex / framesPerSec;
            int remaining = std::max(0, startSeconds - elapsed);
            result << remaining;
            break;
        }

        case CountdownMode::MinutesSecs: {
            // Parse "M:SS" or just seconds
            int startSeconds = 0;
            auto parts = strings::split(text, ':');
            if (parts.size() >= 2) {
                startSeconds = strings::parseInt(parts[0], 0) * 60 + strings::parseInt(parts[1], 0);
            } else {
                startSeconds = strings::parseInt(text, 0);
            }

            int elapsed = state.frameIndex / framesPerSec;
            int remaining = std::max(0, startSeconds - elapsed);
            int mins = remaining / 60;
            int secs = remaining % 60;

            result << mins << " : " << std::setw(2) << std::setfill('0') << secs;
            break;
        }

        case CountdownMode::DaysHoursMinsSecs: {
            // Parse target date and calculate remaining time
            // This would require actual date parsing - simplified for now
            int totalSeconds = strings::parseInt(text, 0);
            int elapsed = state.frameIndex / framesPerSec;
            totalSeconds = std::max(0, totalSeconds - elapsed);

            int days = totalSeconds / 86400;
            int hours = (totalSeconds % 86400) / 3600;
            int mins = (totalSeconds % 3600) / 60;
            int secs = totalSeconds % 60;

            result << days << "d " << hours << "h " << mins << "m " << secs << "s";
            break;
        }

        case CountdownMode::HoursMinsSecs: {
            int totalSeconds = strings::parseInt(text, 0);
            int elapsed = state.frameIndex / framesPerSec;
            totalSeconds = std::max(0, totalSeconds - elapsed);

            int hours = totalSeconds / 3600;
            int mins = (totalSeconds % 3600) / 60;
            int secs = totalSeconds % 60;

            result << hours << " : " << mins << " : " << secs;
            break;
        }

        case CountdownMode::MinsOrSecs: {
            int totalSeconds = strings::parseInt(text, 0);
            int elapsed = state.frameIndex / framesPerSec;
            totalSeconds = std::max(0, totalSeconds - elapsed);

            if (totalSeconds >= 300) {  // 5 minutes
                result << (totalSeconds / 60) << " m";
            } else {
                result << totalSeconds;
            }
            break;
        }

        case CountdownMode::SecsOnly: {
            int totalSeconds = strings::parseInt(text, 0);
            int elapsed = state.frameIndex / framesPerSec;
            result << std::max(0, totalSeconds - elapsed);
            break;
        }

        case CountdownMode::FreeFormat:
            // Free format requires parsing format string - return text as-is for now
            result << text;
            break;

        default:
            result << text;
            break;
    }

    return result.str();
}

std::string TextEffect::replaceVariables(const std::string& text,
                                         const RenderState& state) const {
    std::string result = text;

    // Replace common variables
    // Note: In full implementation, these would be pulled from sequence metadata
    auto replace = [&result](const std::string& var, const std::string& value) {
        size_t pos = 0;
        while ((pos = result.find(var, pos)) != std::string::npos) {
            result.replace(pos, var.length(), value);
            pos += value.length();
        }
    };

    // Standard variables (placeholders for now)
    replace("${TITLE}", "");
    replace("${SONG}", "");
    replace("${ARTIST}", "");
    replace("${ALBUM}", "");
    replace("${FILENAME}", "");
    replace("${AUTHOR}", "");
    replace("${AUTHOREMAIL}", "");
    replace("${COMMENT}", "");
    replace("${URL}", "");
    replace("${WEBSITE}", "");

    // Case transformations
    if (result.find("${UPPER}") != std::string::npos) {
        replace("${UPPER}", "");
        std::transform(result.begin(), result.end(), result.begin(), ::toupper);
    }
    if (result.find("${LOWER}") != std::string::npos) {
        replace("${LOWER}", "");
        std::transform(result.begin(), result.end(), result.begin(), ::tolower);
    }

    return result;
}

std::vector<std::string> TextEffect::splitWords(const std::string& text) const {
    std::vector<std::string> words;
    std::string word;

    for (char c : text) {
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            if (!word.empty()) {
                words.push_back(word);
                word.clear();
            }
        } else {
            word += c;
        }
    }

    if (!word.empty()) {
        words.push_back(word);
    }

    return words;
}

std::string TextEffect::getCurrentWord(const std::vector<std::string>& words,
                                       const EffectSettings& settings,
                                       const RenderState& state) const {
    if (words.empty()) {
        return "";
    }

    int speed = settings.getInt("TEXTCTRL_Text_Speed", 10);

    // Speed of 0 means just show first word
    if (speed == 0) {
        return words[0];
    }

    // Calculate ms per word
    double effectDuration = (state.effectEndTime - state.effectStartTime) * 1000;
    double msPerWord = effectDuration / (words.size() * speed);

    size_t wordIndex = 0;
    if (msPerWord > 0) {
        double currentTimeMs = state.progress * effectDuration;
        wordIndex = static_cast<size_t>(currentTimeMs / msPerWord);
    }

    wordIndex = wordIndex % words.size();
    return words[wordIndex];
}

std::unique_ptr<Effect> TextEffect::clone() const {
    return std::make_unique<TextEffect>();
}

// Register the effect
XLCORE_REGISTER_EFFECT(TextEffect)

} // namespace xlCore
