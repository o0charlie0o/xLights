/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "FacesEffect.h"
#include "../RenderContext.h"
#include "../StringUtils.h"

#include <cmath>
#include <algorithm>
#include <random>

namespace xlCore {

// Static instances
TimingTrackProvider* TimingTrackProvider::s_instance = nullptr;
FaceDefinitionProvider* FaceDefinitionProvider::s_instance = nullptr;

TimingTrackProvider* TimingTrackProvider::instance() {
    return s_instance;
}

void TimingTrackProvider::setInstance(TimingTrackProvider* provider) {
    s_instance = provider;
}

FaceDefinitionProvider* FaceDefinitionProvider::instance() {
    return s_instance;
}

void FaceDefinitionProvider::setInstance(FaceDefinitionProvider* provider) {
    s_instance = provider;
}

// ============================================================================
// FaceDefinition methods
// ============================================================================

const FaceElement* FaceDefinition::getElement(const std::string& name) const {
    auto it = elements.find(name);
    return (it != elements.end()) ? &it->second : nullptr;
}

FaceElement* FaceDefinition::getElement(const std::string& name) {
    auto it = elements.find(name);
    return (it != elements.end()) ? &it->second : nullptr;
}

const FaceElement* FaceDefinition::getMouth(Phoneme p) const {
    std::string key = "Mouth-" + phonemeToString(p);
    return getElement(key);
}

const FaceElement* FaceDefinition::getEyes(EyeState state) const {
    std::string key = "Eyes-" + eyeStateToString(state);
    return getElement(key);
}

const FaceElement* FaceDefinition::getOutline() const {
    return getElement("FaceOutline");
}

// ============================================================================
// Helper functions
// ============================================================================

Phoneme parsePhonemeString(const std::string& str) {
    std::string s = strings::toLower(strings::trim(str));

    // Strip shimmer suffix
    if (strings::endsWith(s, "-shimmer")) {
        s = s.substr(0, s.length() - 8);
    }

    if (s == "ai" || s == "a-ai") return Phoneme::AI;
    if (s == "e" || s == "a-e") return Phoneme::E;
    if (s == "fv" || s == "a-fv") return Phoneme::FV;
    if (s == "l" || s == "a-l") return Phoneme::L;
    if (s == "mbp" || s == "a-mbp") return Phoneme::MBP;
    if (s == "o" || s == "a-o") return Phoneme::O;
    if (s == "u" || s == "a-u") return Phoneme::U;
    if (s == "wq" || s == "a-wq") return Phoneme::WQ;
    if (s == "etc" || s == "a-etc") return Phoneme::Etc;
    if (s == "rest" || s == "a-rest") return Phoneme::Rest;
    if (s == "(off)" || s == "off") return Phoneme::Off;

    return Phoneme::Rest;
}

EyeState parseEyeStateString(const std::string& str) {
    std::string s = strings::toLower(strings::trim(str));
    if (s == "auto") return EyeState::Auto;
    if (s == "open") return EyeState::Open;
    if (s == "closed") return EyeState::Closed;
    if (s == "(off)" || s == "off") return EyeState::Off;
    return EyeState::Auto;
}

BlinkFrequency parseBlinkFrequency(const std::string& str) {
    std::string s = strings::toLower(strings::trim(str));
    if (s == "slowest") return BlinkFrequency::Slowest;
    if (s == "slow") return BlinkFrequency::Slow;
    if (s == "normal") return BlinkFrequency::Normal;
    if (s == "fast") return BlinkFrequency::Fast;
    if (s == "fastest") return BlinkFrequency::Fastest;
    return BlinkFrequency::Normal;
}

BlinkDuration parseBlinkDuration(const std::string& str) {
    std::string s = strings::toLower(strings::trim(str));
    if (s == "slower") return BlinkDuration::Slower;
    if (s == "normal") return BlinkDuration::Normal;
    if (s == "long") return BlinkDuration::Long;
    if (s == "longer") return BlinkDuration::Longer;
    return BlinkDuration::Normal;
}

std::string phonemeToString(Phoneme p) {
    switch (p) {
        case Phoneme::AI: return "AI";
        case Phoneme::E: return "E";
        case Phoneme::FV: return "FV";
        case Phoneme::L: return "L";
        case Phoneme::MBP: return "MBP";
        case Phoneme::O: return "O";
        case Phoneme::U: return "U";
        case Phoneme::WQ: return "WQ";
        case Phoneme::Etc: return "etc";
        case Phoneme::Rest: return "rest";
        case Phoneme::Off: return "(off)";
    }
    return "rest";
}

std::string eyeStateToString(EyeState e) {
    switch (e) {
        case EyeState::Auto: return "Auto";
        case EyeState::Open: return "Open";
        case EyeState::Closed: return "Closed";
        case EyeState::Off: return "(off)";
    }
    return "Auto";
}

// ============================================================================
// FacesEffect implementation
// ============================================================================

FacesEffect::FacesEffect() = default;

std::vector<EffectParameter> FacesEffect::parameters() const {
    std::vector<EffectParameter> params;

    // Face definition
    params.push_back(EffectParameter::createChoice(
        "CHOICE_Faces_FaceDefinition", "Face Definition", "Default",
        {"Default", "Rendered"}  // Additional definitions populated dynamically
    ));

    // Phoneme source - timing track or manual
    params.push_back(EffectParameter::createChoice(
        "CHOICE_Faces_TimingTrack", "Timing Track", "",
        {}  // Populated dynamically from sequence timing tracks
    ));

    // Manual phoneme selection (when not using timing track)
    params.push_back(EffectParameter::createChoice(
        "CHOICE_Faces_Phoneme", "Phoneme", "AI",
        {"AI", "E", "FV", "L", "MBP", "O", "U", "WQ", "etc", "rest", "(off)"}
    ));

    // Eye settings
    params.push_back(EffectParameter::createChoice(
        "CHOICE_Faces_Eyes", "Eyes", "Auto",
        {"Auto", "Open", "Closed", "(off)"}
    ));

    params.push_back(EffectParameter::createChoice(
        "CHOICE_Faces_EyeBlinkFrequency", "Blink Frequency", "Normal",
        {"Slowest", "Slow", "Normal", "Fast", "Fastest"}
    ));

    params.push_back(EffectParameter::createChoice(
        "CHOICE_Faces_EyeBlinkDuration", "Blink Duration", "Normal",
        {"Slower", "Normal", "Long", "Longer"}
    ));

    // Face outline
    params.push_back(EffectParameter::createBool(
        "CHECKBOX_Faces_Outline", "Show Outline", false
    ));

    // State for outline
    params.push_back(EffectParameter::createChoice(
        "CHOICE_Faces_UseState", "Outline State", "",
        {}  // Populated dynamically from model states
    ));

    // Suppress when not singing
    params.push_back(EffectParameter::createBool(
        "CHECKBOX_Faces_SuppressWhenNotSinging", "Suppress When Not Singing", false
    ));

    params.push_back(EffectParameter::createBool(
        "CHECKBOX_Faces_Fade", "Fade In/Out", false
    ));

    params.push_back(EffectParameter::createInt(
        "SPINCTRL_Faces_LeadFrames", "Lead Frames", 0, 0, 100, false
    ));

    // Shimmer
    params.push_back(EffectParameter::createBool(
        "CHECKBOX_Faces_SuppressShimmer", "Suppress Shimmer", false
    ));

    // Transparent black (for image faces)
    params.push_back(EffectParameter::createBool(
        "CHECKBOX_Faces_TransparentBlack", "Transparent Black", false
    ));

    params.push_back(EffectParameter::createInt(
        "TEXTCTRL_Faces_TransparentBlack", "Transparent Level", 0, 0, 765, false
    ));

    return params;
}

void FacesEffect::prepareForRender(const EffectSettings& settings) {
    // Initialize blink timing with random offset
    std::random_device rd;
    std::mt19937 gen(rd());

    BlinkFrequency freq = parseBlinkFrequency(settings.get("CHOICE_Faces_EyeBlinkFrequency", "Normal"));
    int maxDelay = getMaxBlinkDelay(freq);

    std::uniform_int_distribution<> dis(0, maxDelay);
    m_renderState.nextBlinkTime = dis(gen);
    m_renderState.blinkEndTime = 0;
}

void FacesEffect::cleanupAfterRender() {
    m_renderState.imageCache.clear();
    m_cachedDefinition.reset();
    m_cachedDefinitionKey.clear();
}

void FacesEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Calculate current time in ms
    int currentTimeMS = static_cast<int>(state.timeSeconds * 1000);
    int frameTimeMS = 50;  // Default
    if (state.totalFrames > 1) {
        frameTimeMS = static_cast<int>((state.effectEndTime - state.effectStartTime) * 1000 / state.totalFrames);
    }

    // Calculate alpha for suppress-when-not-singing
    uint8_t alpha = 255;
    if (settings.getBool("CHECKBOX_Faces_SuppressWhenNotSinging", false)) {
        std::string trackName = settings.get("CHOICE_Faces_TimingTrack", "");
        if (!trackName.empty()) {
            int leadFrames = settings.getInt("SPINCTRL_Faces_LeadFrames", 0);
            bool fade = settings.getBool("CHECKBOX_Faces_Fade", false);
            alpha = calculateAlpha(trackName, currentTimeMS, leadFrames, fade, frameTimeMS);
        }
    }

    if (alpha == 0) {
        return;  // Nothing to render
    }

    // Get phoneme
    Phoneme phoneme = Phoneme::Rest;
    std::string phonemeStr = settings.get("CHOICE_Faces_Phoneme", "");
    std::string trackName = settings.get("CHOICE_Faces_TimingTrack", "");

    if (!trackName.empty()) {
        phoneme = getCurrentPhoneme(trackName, currentTimeMS);
    } else if (!phonemeStr.empty()) {
        phoneme = parsePhonemeString(phonemeStr);
    }

    // Check for shimmer
    bool suppressShimmer = settings.getBool("CHECKBOX_Faces_SuppressShimmer", false);
    bool shimmer = !suppressShimmer &&
                   strings::endsWith(strings::toLower(phonemeStr), "-shimmer");

    if (shimmer && !shimmerState(state)) {
        phoneme = Phoneme::Rest;
    }

    // Get eye state
    std::string eyeSetting = settings.get("CHOICE_Faces_Eyes", "Auto");
    EyeState eyes = getEyeState(eyeSetting, phoneme, currentTimeMS);

    // Get face definition
    std::string faceDef = settings.get("CHOICE_Faces_FaceDefinition", "Default");
    bool outline = settings.getBool("CHECKBOX_Faces_Outline", false);

    // Check for definition type
    if (faceDef == "Rendered" || faceDef == "Default") {
        // Use geometric face rendering
        renderGeometricFace(ctx, phoneme, eyes, outline, alpha, shimmer);
    } else {
        // Try to get face definition from provider
        if (FaceDefinitionProvider::instance()) {
            // Build cache key
            std::string modelName;  // TODO: Get from render state
            std::string cacheKey = modelName + "|" + faceDef;

            if (m_cachedDefinitionKey != cacheKey) {
                m_cachedDefinition = FaceDefinitionProvider::instance()->getFaceDefinition(modelName, faceDef);
                m_cachedDefinitionKey = cacheKey;
            }

            if (m_cachedDefinition) {
                const FaceDefinition& def = *m_cachedDefinition;

                if (def.type == FaceType::Matrix) {
                    bool transparentBlack = settings.getBool("CHECKBOX_Faces_TransparentBlack", false);
                    int transparentLevel = settings.getInt("TEXTCTRL_Faces_TransparentBlack", 0);
                    renderMatrixFace(ctx, def, phoneme, eyes, transparentBlack, transparentLevel, alpha, shimmer);
                } else {
                    // TODO: Get palette from render context
                    ColorPalette palette;
                    renderNodeFace(ctx, def, phoneme, eyes, outline, palette, alpha, shimmer);
                }
            } else {
                // Fall back to geometric
                renderGeometricFace(ctx, phoneme, eyes, outline, alpha, shimmer);
            }
        } else {
            // No provider - use geometric
            renderGeometricFace(ctx, phoneme, eyes, outline, alpha, shimmer);
        }
    }
}

void FacesEffect::renderGeometricFace(RenderContext& ctx, Phoneme phoneme, EyeState eyes,
                                       bool outline, uint8_t alpha, bool shimmer) {
    int height = ctx.height();
    int width = ctx.width();

    // Default colors (white)
    Color mouthColor = Color::White();
    Color eyeColor = Color::White();
    Color outlineColor = Color::White();

    // Apply alpha
    mouthColor.alpha = alpha;
    eyeColor.alpha = alpha;
    outlineColor.alpha = alpha;

    // Draw face outline if enabled
    if (outline) {
        drawOutline(ctx, outlineColor, height, width);
    }

    // Draw eyes (unless off)
    if (eyes != EyeState::Off) {
        drawEyes(ctx, eyes, eyeColor, height, width);
    }

    // Draw mouth (unless off)
    if (phoneme != Phoneme::Off) {
        drawMouth(ctx, phoneme, mouthColor, height, width);
    }
}

void FacesEffect::renderNodeFace(RenderContext& ctx, const FaceDefinition& def,
                                  Phoneme phoneme, EyeState eyes, bool outline,
                                  const ColorPalette& palette, uint8_t alpha, bool shimmer) {
    // Node-based rendering requires model data access
    // This is handled through the render state's modelData pointer

    // For now, fall back to geometric rendering
    // Full implementation would iterate through def.elements and
    // set nodes based on nodeIndices lists

    renderGeometricFace(ctx, phoneme, eyes, outline, alpha, shimmer);
}

void FacesEffect::renderMatrixFace(RenderContext& ctx, const FaceDefinition& def,
                                    Phoneme phoneme, EyeState eyes,
                                    bool transparentBlack, int transparentLevel,
                                    uint8_t alpha, bool shimmer) {
    // Build image key
    std::string eyeStr = (eyes == EyeState::Closed) ? "Closed" : "Open";
    std::string key = "Mouth-" + phonemeToString(phoneme) + "-Eyes" + eyeStr;

    const FaceElement* element = def.getElement(key);
    if (!element || element->imagePath.empty()) {
        // Try without eye state
        key = "Mouth-" + phonemeToString(phoneme);
        element = def.getElement(key);
    }

    if (!element || element->imagePath.empty()) {
        // Fall back to geometric
        renderGeometricFace(ctx, phoneme, eyes, false, alpha, shimmer);
        return;
    }

    // Check image cache
    auto cacheIt = m_renderState.imageCache.find(element->imagePath);
    if (cacheIt == m_renderState.imageCache.end()) {
        // Load image - would need platform-specific image loading
        // For now, fall back to geometric
        renderGeometricFace(ctx, phoneme, eyes, false, alpha, shimmer);
        return;
    }

    const ImageBuffer& img = cacheIt->second;

    // Blit image to context with alpha and transparency handling
    for (size_t y = 0; y < img.height() && y < static_cast<size_t>(ctx.height()); y++) {
        for (size_t x = 0; x < img.width() && x < static_cast<size_t>(ctx.width()); x++) {
            Color pixel = img.getPixel(x, y);

            // Apply transparent black filter
            if (transparentBlack) {
                int level = pixel.red + pixel.green + pixel.blue;
                if (level <= transparentLevel) {
                    continue;
                }
            }

            // Apply alpha
            pixel.alpha = static_cast<uint8_t>((static_cast<int>(pixel.alpha) * alpha) / 255);

            if (pixel.alpha > 0) {
                ctx.setPixelBlended(x, y, pixel);
            }
        }
    }
}

Phoneme FacesEffect::getCurrentPhoneme(const std::string& trackName, int timeMS) {
    if (!TimingTrackProvider::instance()) {
        return Phoneme::Rest;
    }

    auto mark = TimingTrackProvider::instance()->getTimingMark(trackName, timeMS, 2);
    if (mark) {
        return parsePhonemeString(mark->label);
    }

    return Phoneme::Rest;
}

Phoneme FacesEffect::parsePhoneme(const std::string& str) {
    return parsePhonemeString(str);
}

EyeState FacesEffect::getEyeState(const std::string& eyeSetting, Phoneme phoneme,
                                   int currentTimeMS) {
    EyeState state = parseEyeStateString(eyeSetting);

    if (state != EyeState::Auto) {
        return state;
    }

    // Auto blink logic - only blink during rest
    if (phoneme == Phoneme::Rest || phoneme == Phoneme::Off) {
        if (currentTimeMS >= m_renderState.nextBlinkTime) {
            // Start a new blink
            BlinkFrequency freq = BlinkFrequency::Normal;  // Would get from settings
            BlinkDuration dur = BlinkDuration::Normal;

            int maxDelay = getMaxBlinkDelay(freq);
            int blinkDur = getBlinkDuration(dur);

            // Random next blink time
            std::random_device rd;
            std::mt19937 gen(rd());
            std::uniform_int_distribution<> dis(maxDelay - 1000, maxDelay);

            m_renderState.blinkEndTime = currentTimeMS + blinkDur;
            m_renderState.nextBlinkTime += dis(gen);

            return EyeState::Closed;
        } else if (currentTimeMS < m_renderState.blinkEndTime) {
            return EyeState::Closed;
        }
    }

    return EyeState::Open;
}

uint8_t FacesEffect::calculateAlpha(const std::string& trackName, int currentTimeMS,
                                    int leadFrames, bool fade, int frameTimeMS) {
    if (!TimingTrackProvider::instance()) {
        return 255;
    }

    // Check if currently singing
    auto mark = TimingTrackProvider::instance()->getTimingMark(trackName, currentTimeMS, 2);
    if (mark) {
        return 255;  // Currently singing - full alpha
    }

    if (leadFrames == 0) {
        return 0;  // No lead frames and not singing - hide
    }

    int leadMS = leadFrames * frameTimeMS;

    // Check for upcoming phrase within lead time
    auto marks = TimingTrackProvider::instance()->getTimingMarks(
        trackName, currentTimeMS, currentTimeMS + leadMS, 2);

    uint8_t beforeAlpha = 0;
    if (!marks.empty()) {
        int timeToNext = marks[0].startTimeMS - currentTimeMS;
        if (timeToNext < leadMS) {
            if (fade) {
                beforeAlpha = static_cast<uint8_t>(255 - (timeToNext * 255) / leadMS);
            } else {
                beforeAlpha = 255;
            }
        }
    }

    // Check for recent phrase within lead time
    auto recentMarks = TimingTrackProvider::instance()->getTimingMarks(
        trackName, currentTimeMS - leadMS, currentTimeMS, 2);

    uint8_t afterAlpha = 0;
    if (!recentMarks.empty()) {
        int timeSinceLast = currentTimeMS - recentMarks.back().endTimeMS;
        if (timeSinceLast < leadMS) {
            if (fade) {
                afterAlpha = static_cast<uint8_t>(255 - (timeSinceLast * 255) / leadMS);
            } else {
                afterAlpha = 255;
            }
        }
    }

    return std::max(beforeAlpha, afterAlpha);
}

bool FacesEffect::shimmerState(const RenderState& state) const {
    // Shimmer on/off every ~150ms at 20fps
    int frameTimeMS = 50;
    if (state.totalFrames > 1) {
        frameTimeMS = static_cast<int>((state.effectEndTime - state.effectStartTime) * 1000 / state.totalFrames);
    }

    int periodMS = state.frameIndex * frameTimeMS;
    return (periodMS % 200) < 150;
}

int FacesEffect::getMaxBlinkDelay(BlinkFrequency freq) const {
    switch (freq) {
        case BlinkFrequency::Slowest: return 9000;
        case BlinkFrequency::Slow: return 7250;
        case BlinkFrequency::Normal: return 5500;
        case BlinkFrequency::Fast: return 3750;
        case BlinkFrequency::Fastest: return 2000;
    }
    return 5500;
}

int FacesEffect::getBlinkDuration(BlinkDuration dur) const {
    switch (dur) {
        case BlinkDuration::Slower: return 50;
        case BlinkDuration::Normal: return 100;
        case BlinkDuration::Long: return 200;
        case BlinkDuration::Longer: return 400;
    }
    return 100;
}

void FacesEffect::drawMouth(RenderContext& ctx, Phoneme phoneme, const Color& color,
                            int height, int width) {
    int h = height - 1;
    int w = width - 1;

    // Mouth position calculations (based on legacy effect)
    int x1 = static_cast<int>(w * 0.25);
    int x2 = static_cast<int>(w * 0.75);
    int x3 = static_cast<int>(w * 0.30);
    int x4 = static_cast<int>(w * 0.70);

    int y1 = static_cast<int>(h * 0.48);
    int y2 = static_cast<int>(h * 0.40);
    int y3 = static_cast<int>(h * 0.25);
    int y4 = static_cast<int>(h * 0.20);
    int y5 = static_cast<int>(h * 0.30);

    switch (phoneme) {
        case Phoneme::AI:
            // Wide open mouth
            ctx.drawHLine(y2, x1, x2, color);
            ctx.drawVLine(x1, y2, y1, color);
            ctx.drawVLine(x2, y2, y1, color);
            ctx.drawHLine(y4, x1, x2, color);
            break;

        case Phoneme::E:
        case Phoneme::L:
            // Medium open
            ctx.drawHLine(y2, x1, x2, color);
            ctx.drawVLine(x1, y2, y1, color);
            ctx.drawVLine(x2, y2, y1, color);
            ctx.drawHLine(y3, x1, x2, color);
            break;

        case Phoneme::FV:
            // Teeth on lip
            ctx.drawHLine(y2, x1, x2, color);
            ctx.drawVLine(x1, y2, y1, color);
            ctx.drawVLine(x2, y2, y1, color);
            ctx.drawHLine(y2 - 1, x1, x2, color);
            break;

        case Phoneme::MBP:
        case Phoneme::Rest:
            // Closed mouth - single horizontal line
            ctx.drawHLine(y2, x1, x2, color);
            break;

        case Phoneme::O: {
            // Round "O" mouth
            int xc = w / 2;
            int yc = (y2 + y5) / 2;
            double radius = std::min(w, h) * 0.15;
            ctx.drawCircle(xc, yc, static_cast<int>(radius), color);
            break;
        }

        case Phoneme::U: {
            // Smaller "U" mouth
            int xc = w / 2;
            int yc = (y2 + y5) / 2;
            double radius = std::min(w, h) * 0.10;
            ctx.drawCircle(xc, yc, static_cast<int>(radius), color);
            break;
        }

        case Phoneme::WQ: {
            // Tiny "W/Q" mouth
            int xc = w / 2;
            int yc = (y2 + y5) / 2;
            double radius = std::min(w, h) * 0.05;
            ctx.drawCircle(xc, yc, static_cast<int>(radius), color);
            break;
        }

        case Phoneme::Etc:
            // Rectangle mouth
            ctx.drawVLine(x3, y5, y2, color);
            ctx.drawVLine(x4, y5, y2, color);
            ctx.drawHLine(y5, x3, x4, color);
            ctx.drawHLine(y2, x3, x4, color);
            break;

        case Phoneme::Off:
            // Nothing
            break;
    }
}

void FacesEffect::drawEyes(RenderContext& ctx, EyeState state, const Color& color,
                           int height, int width) {
    int h = height - 1;
    int w = width - 1;

    int xLeft = static_cast<int>(w * 0.33);
    int xRight = static_cast<int>(w * 0.66);
    int yc = static_cast<int>(h * 0.75);
    double radius = w * 0.08;

    int startDeg = (state == EyeState::Closed) ? 180 : 0;
    int endDeg = 360;

    // Draw left eye
    for (int deg = startDeg; deg < endDeg; deg++) {
        double rad = deg * 3.14159 / 180.0;
        int x = static_cast<int>(xLeft + radius * std::cos(rad));
        int y = static_cast<int>(yc + radius * std::sin(rad));
        if (x >= 0 && x < ctx.width() && y >= 0 && y < ctx.height()) {
            ctx.setPixel(x, y, color);
        }
    }

    // Draw right eye
    for (int deg = startDeg; deg < endDeg; deg++) {
        double rad = deg * 3.14159 / 180.0;
        int x = static_cast<int>(xRight + radius * std::cos(rad));
        int y = static_cast<int>(yc + radius * std::sin(rad));
        if (x >= 0 && x < ctx.width() && y >= 0 && y < ctx.height()) {
            ctx.setPixel(x, y, color);
        }
    }
}

void FacesEffect::drawOutline(RenderContext& ctx, const Color& color, int height, int width) {
    // Draw face outline (rounded rectangle)
    int h = height;
    int w = width;

    // Vertical sides
    for (int y = 3; y < h - 3; y++) {
        ctx.setPixel(0, y, color);
        ctx.setPixel(w - 1, y, color);
    }

    // Horizontal sides
    for (int x = 3; x < w - 3; x++) {
        ctx.setPixel(x, 0, color);
        ctx.setPixel(x, h - 1, color);
    }

    // Corners
    ctx.setPixel(2, 1, color);
    ctx.setPixel(1, 2, color);
    ctx.setPixel(w - 3, 1, color);
    ctx.setPixel(w - 2, 2, color);
    ctx.setPixel(w - 3, h - 2, color);
    ctx.setPixel(w - 2, h - 3, color);
    ctx.setPixel(2, h - 2, color);
    ctx.setPixel(1, h - 3, color);
}

void FacesEffect::drawFilledCircle(RenderContext& ctx, int cx, int cy, double radius,
                                   const Color& color) {
    ctx.drawCircle(cx, cy, static_cast<int>(radius), color, true);
}

void FacesEffect::drawArc(RenderContext& ctx, int cx, int cy, double radius,
                          int startDegrees, int endDegrees, const Color& color) {
    for (int deg = startDegrees; deg < endDegrees; deg++) {
        double rad = deg * 3.14159 / 180.0;
        int x = static_cast<int>(cx + radius * std::cos(rad));
        int y = static_cast<int>(cy + radius * std::sin(rad));
        if (x >= 0 && x < ctx.width() && y >= 0 && y < ctx.height()) {
            ctx.setPixel(x, y, color);
        }
    }
}

std::unique_ptr<Effect> FacesEffect::clone() const {
    return std::make_unique<FacesEffect>();
}

// Register the effect
XLCORE_REGISTER_EFFECT(FacesEffect)

} // namespace xlCore
