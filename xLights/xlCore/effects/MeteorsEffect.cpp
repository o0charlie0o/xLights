/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// System headers first
#include <cmath>
#include <algorithm>

#include "MeteorsEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

namespace xlCore {

namespace {
    constexpr float PI = 3.14159265358979323846f;
}

// ============================================================================
// Helper Functions
// ============================================================================

static MeteorDirection parseMeteorDirection(const std::string& dir) {
    if (dir == "Down") return MeteorDirection::Down;
    if (dir == "Up") return MeteorDirection::Up;
    if (dir == "Left") return MeteorDirection::Left;
    if (dir == "Right") return MeteorDirection::Right;
    if (dir == "Implode") return MeteorDirection::Implode;
    if (dir == "Explode") return MeteorDirection::Explode;
    if (dir == "Icicles") return MeteorDirection::Icicles;
    if (dir == "Icicles + bkg") return MeteorDirection::IciclesBkg;
    return MeteorDirection::Down;
}

static MeteorColorScheme parseMeteorColorScheme(const std::string& color) {
    if (color == "Rainbow") return MeteorColorScheme::Rainbow;
    if (color == "Range") return MeteorColorScheme::Range;
    if (color == "Palette") return MeteorColorScheme::Palette;
    return MeteorColorScheme::Rainbow;
}

// ============================================================================
// MeteorsEffect Implementation
// ============================================================================

std::vector<EffectParameter> MeteorsEffect::parameters() const {
    std::vector<EffectParameter> params;

    params.push_back(EffectParameter::createChoice(
        "E_CHOICE_Meteors_Effect", "Direction", "Down",
        {"Down", "Up", "Left", "Right", "Implode", "Explode", "Icicles", "Icicles + bkg"}));

    params.push_back(EffectParameter::createChoice(
        "E_CHOICE_Meteors_Type", "Color Type", "Rainbow",
        {"Rainbow", "Range", "Palette"}));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Meteors_Count", "Count", 10, 1, 100, true));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Meteors_Length", "Length", 25, 1, 100, true));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Meteors_Swirl_Intensity", "Swirl", 0, 0, 20, true));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Meteors_Speed", "Speed", 10, 1, 50, true));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Meteors_XOffset", "X Offset", 0, -100, 100, true));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Meteors_YOffset", "Y Offset", 0, -100, 100, true));

    params.push_back(EffectParameter::createBool(
        "E_CHECKBOX_FadeWithDistance", "Fade With Distance", false));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Meteors_WarmupFrames", "Warmup Frames", 0, 0, 100));

    return params;
}

float MeteorsEffect::calcEffectStateOffset(int speed, float frameTimeMs) {
    if (speed == 0) {
        return 0.1f;
    }
    return (static_cast<float>(speed) * frameTimeMs) / 50.0f;
}

// ============================================================================
// Vertical Meteor Management
// ============================================================================

void MeteorsEffect::verticalAddMeteors(RenderContext& ctx, MeteorColorScheme colorScheme,
                                        int count, std::mt19937& rng) {
    std::uniform_int_distribution<int> spawnDist(0, 199);
    std::uniform_int_distribution<int> xDist(0, ctx.width() - 1);
    std::uniform_real_distribution<float> hueDist(0.0f, 1.0f);

    for (int i = 0; i < ctx.width(); i++) {
        if (spawnDist(rng) < count) {
            MeteorParticle m;
            m.x = i;
            m.y = ctx.height() - 1;

            switch (colorScheme) {
                case MeteorColorScheme::Rainbow:
                    m.hue = hueDist(rng);
                    m.saturation = 1.0f;
                    m.value = 1.0f;
                    break;
                case MeteorColorScheme::Range:
                    m.hue = hueDist(rng) * 0.3f;  // Limited hue range
                    m.saturation = 1.0f;
                    m.value = 1.0f;
                    break;
                case MeteorColorScheme::Palette:
                    m.hue = hueDist(rng);
                    m.saturation = 1.0f;
                    m.value = 1.0f;
                    break;
            }
            _state.meteors.push_back(m);
        }
    }
}

void MeteorsEffect::verticalMoveMeteors(int speed) {
    for (auto& m : _state.meteors) {
        m.y -= speed;
    }
}

void MeteorsEffect::verticalRemoveMeteors(int height, int length) {
    int tailLength = (height < 10) ? length / 10 : height * length / 100;
    if (tailLength < 1) tailLength = 1;

    _state.meteors.remove_if([tailLength](const MeteorParticle& m) {
        return m.y + tailLength < 0;
    });
}

// ============================================================================
// Horizontal Meteor Management
// ============================================================================

void MeteorsEffect::horizontalAddMeteors(RenderContext& ctx, MeteorColorScheme colorScheme,
                                          int count, std::mt19937& rng) {
    std::uniform_int_distribution<int> spawnDist(0, 199);
    std::uniform_real_distribution<float> hueDist(0.0f, 1.0f);

    for (int i = 0; i < ctx.height(); i++) {
        if (spawnDist(rng) < count) {
            MeteorParticle m;
            m.x = ctx.width() - 1;
            m.y = i;

            switch (colorScheme) {
                case MeteorColorScheme::Rainbow:
                    m.hue = hueDist(rng);
                    break;
                case MeteorColorScheme::Range:
                    m.hue = hueDist(rng) * 0.3f;
                    break;
                case MeteorColorScheme::Palette:
                    m.hue = hueDist(rng);
                    break;
            }
            m.saturation = 1.0f;
            m.value = 1.0f;
            _state.meteors.push_back(m);
        }
    }
}

void MeteorsEffect::horizontalMoveMeteors(int speed) {
    for (auto& m : _state.meteors) {
        m.x -= speed;
    }
}

void MeteorsEffect::horizontalRemoveMeteors(int width, int length) {
    int tailLength = (width < 10) ? length / 10 : width * length / 100;
    if (tailLength < 1) tailLength = 1;

    _state.meteors.remove_if([tailLength](const MeteorParticle& m) {
        return m.x + tailLength < 0;
    });
}

// ============================================================================
// Radial Meteor Management (Implode/Explode)
// ============================================================================

void MeteorsEffect::radialAddMeteors(RenderContext& ctx, MeteorColorScheme colorScheme,
                                      int count, int length, int xOffset, int yOffset,
                                      bool explode, std::mt19937& rng) {
    int trueXOffset = xOffset * ctx.width() / 2 / 100;
    int trueYOffset = yOffset * ctx.height() / 2 / 100;
    int centerX = ctx.width() / 2 + trueXOffset;
    int centerY = ctx.height() / 2 + trueYOffset;

    // Calculate max diagonal distance
    auto calcDist = [](int cx, int cy, int px, int py) {
        return std::sqrt(static_cast<float>((px - cx) * (px - cx) + (py - cy) * (py - cy)));
    };
    float maxDiag = std::max({
        calcDist(centerX, centerY, 0, 0),
        calcDist(centerX, centerY, 0, ctx.height()),
        calcDist(centerX, centerY, ctx.width(), 0),
        calcDist(centerX, centerY, ctx.width(), ctx.height())
    });

    int tailLength = (static_cast<int>(maxDiag) < 10) ? length / 10
                                                       : static_cast<int>(maxDiag * length / 100);
    if (tailLength < 1) tailLength = 1;

    std::uniform_int_distribution<int> spawnDist(0, 199);
    std::uniform_real_distribution<float> angleDist(0.0f, 2.0f * PI);
    std::uniform_real_distribution<float> hueDist(0.0f, 1.0f);

    int minDim = std::min(ctx.width(), ctx.height());
    for (int i = 0; i < minDim; i++) {
        if (spawnDist(rng) < count) {
            MeteorRadialParticle m;
            float angle = angleDist(rng);
            m.dx = std::cos(angle);
            m.dy = std::sin(angle);

            if (explode) {
                m.x = static_cast<float>(centerX);
                m.y = static_cast<float>(centerY);
            } else {
                m.x = centerX + (maxDiag + tailLength) * m.dx;
                m.y = centerY + (maxDiag + tailLength) * m.dy;
            }
            m.count = 1;

            switch (colorScheme) {
                case MeteorColorScheme::Rainbow:
                    m.hue = hueDist(rng);
                    break;
                case MeteorColorScheme::Range:
                    m.hue = hueDist(rng) * 0.3f;
                    break;
                case MeteorColorScheme::Palette:
                    m.hue = hueDist(rng);
                    break;
            }
            m.saturation = 1.0f;
            m.value = 1.0f;

            _state.meteorsRadial.push_back(m);
        }
    }
}

void MeteorsEffect::radialMoveMeteors(int speed, int xOffset, int yOffset,
                                       int width, int height, bool fadeWithDistance, bool explode) {
    int trueXOffset = xOffset * width / 2 / 100;
    int trueYOffset = yOffset * height / 2 / 100;
    int centerX = width / 2 + trueXOffset;
    int centerY = height / 2 + trueYOffset;

    auto calcDist = [](int cx, int cy, int px, int py) {
        return std::sqrt(static_cast<float>((px - cx) * (px - cx) + (py - cy) * (py - cy)));
    };
    float maxDiag = std::max({
        calcDist(centerX, centerY, 0, 0),
        calcDist(centerX, centerY, 0, height),
        calcDist(centerX, centerY, width, 0),
        calcDist(centerX, centerY, width, height)
    });

    for (auto& m : _state.meteorsRadial) {
        float hdistance = 1.0f;
        if (fadeWithDistance) {
            hdistance = std::max(0.1f,
                std::sqrt((m.x - centerX) * (m.x - centerX) +
                          (m.y - centerY) * (m.y - centerY)) / maxDiag);
        }

        if (explode) {
            m.x += m.dx * speed * hdistance;
            m.y += m.dy * speed * hdistance;
        } else {
            m.x -= m.dx * speed * hdistance;
            m.y -= m.dy * speed * hdistance;
        }
        m.count++;
    }
}

void MeteorsEffect::radialRemoveMeteors(int xOffset, int yOffset, int width, int height, bool explode) {
    int trueXOffset = xOffset * width / 2 / 100;
    int trueYOffset = yOffset * height / 2 / 100;
    int centerX = width / 2 + trueXOffset;
    int centerY = height / 2 + trueYOffset;

    if (explode) {
        _state.meteorsRadial.remove_if([width, height](const MeteorRadialParticle& m) {
            return m.y < 0 || m.x < 0 || m.y > height || m.x > width;
        });
    } else {
        _state.meteorsRadial.remove_if([centerX, centerY](const MeteorRadialParticle& m) {
            return (std::abs(m.y - centerY) < 2) && (std::abs(m.x - centerX) < 2);
        });
    }
}

// ============================================================================
// Render Methods
// ============================================================================

void MeteorsEffect::renderVertical(RenderContext& ctx, MeteorColorScheme colorScheme,
                                    int count, int length, MeteorDirection direction,
                                    int swirlIntensity, int speed, int warmupFrames,
                                    float frameTimeMs, std::mt19937& rng) {
    int width = ctx.width();
    int height = ctx.height();

    // Warmup frames
    if (_state.effectState == 0.0f) {
        for (int i = 0; i < warmupFrames; i++) {
            _state.effectState += calcEffectStateOffset(speed, frameTimeMs);
            int moveSpeed = static_cast<int>(_state.effectState / 4);
            _state.effectState -= moveSpeed * 4;

            verticalAddMeteors(ctx, colorScheme, count, rng);
            verticalMoveMeteors(moveSpeed);
            verticalRemoveMeteors(height, length);
        }
    }

    _state.effectState += calcEffectStateOffset(speed, frameTimeMs);
    int moveSpeed = static_cast<int>(_state.effectState / 4);
    _state.effectState -= moveSpeed * 4;

    int tailLength = (height < 10) ? length / 10 : height * length / 100;
    if (tailLength < 1) tailLength = 1;

    // Add new meteors
    verticalAddMeteors(ctx, colorScheme, count, rng);

    // Render meteors
    for (const auto& m : _state.meteors) {
        for (int ph = 0; ph <= tailLength; ph++) {
            float hue = m.hue;
            if (colorScheme == MeteorColorScheme::Rainbow) {
                std::uniform_real_distribution<float> hueDist(0.0f, 1.0f);
                hue = hueDist(rng);
            }

            float swirlPhase = static_cast<float>(m.y) / 5.0f;
            int dx = static_cast<int>(swirlIntensity * width / 80.0f * std::sin(swirlPhase));
            int x = m.x + dx;
            int y = m.y + ph;

            if (direction == MeteorDirection::Up) {
                y = height - y;
            }

            float fadeValue = 1.0f - static_cast<float>(ph) / tailLength;
            Color c = Color::fromHSV(hue, m.saturation, m.value * fadeValue);

            if (ctx.allowAlpha()) {
                c.alpha = static_cast<uint8_t>(255.0f * fadeValue);
            }
            ctx.setPixel(x, y, c);
        }
    }

    // Move and cleanup
    verticalMoveMeteors(moveSpeed);
    verticalRemoveMeteors(height, length);
}

void MeteorsEffect::renderHorizontal(RenderContext& ctx, MeteorColorScheme colorScheme,
                                      int count, int length, MeteorDirection direction,
                                      int swirlIntensity, int speed, int warmupFrames,
                                      float frameTimeMs, std::mt19937& rng) {
    int width = ctx.width();
    int height = ctx.height();

    // Similar to vertical but along X axis
    if (_state.effectState == 0.0f) {
        for (int i = 0; i < warmupFrames; i++) {
            _state.effectState += calcEffectStateOffset(speed, frameTimeMs);
            int moveSpeed = static_cast<int>(_state.effectState / 4);
            _state.effectState -= moveSpeed * 4;

            horizontalAddMeteors(ctx, colorScheme, count, rng);
            horizontalMoveMeteors(moveSpeed);
            horizontalRemoveMeteors(width, length);
        }
    }

    _state.effectState += calcEffectStateOffset(speed, frameTimeMs);
    int moveSpeed = static_cast<int>(_state.effectState / 4);
    _state.effectState -= moveSpeed * 4;

    int tailLength = (width < 10) ? length / 10 : width * length / 100;
    if (tailLength < 1) tailLength = 1;

    horizontalAddMeteors(ctx, colorScheme, count, rng);

    for (const auto& m : _state.meteors) {
        for (int ph = 0; ph <= tailLength; ph++) {
            float hue = m.hue;
            if (colorScheme == MeteorColorScheme::Rainbow) {
                std::uniform_real_distribution<float> hueDist(0.0f, 1.0f);
                hue = hueDist(rng);
            }

            float swirlPhase = static_cast<float>(m.x) / 5.0f;
            int dy = static_cast<int>(swirlIntensity * height / 80.0f * std::sin(swirlPhase));
            int x = m.x + ph;
            int y = m.y + dy;

            if (direction == MeteorDirection::Right) {
                x = width - x;
            }

            float fadeValue = 1.0f - static_cast<float>(ph) / tailLength;
            Color c = Color::fromHSV(hue, m.saturation, m.value * fadeValue);

            if (ctx.allowAlpha()) {
                c.alpha = static_cast<uint8_t>(255.0f * fadeValue);
            }
            ctx.setPixel(x, y, c);
        }
    }

    horizontalMoveMeteors(moveSpeed);
    horizontalRemoveMeteors(width, length);
}

void MeteorsEffect::renderImplode(RenderContext& ctx, MeteorColorScheme colorScheme,
                                   int count, int length, int swirlIntensity, int speed,
                                   int xOffset, int yOffset, bool fadeWithDistance,
                                   int warmupFrames, float frameTimeMs, std::mt19937& rng) {
    int width = ctx.width();
    int height = ctx.height();

    if (_state.effectState == 0.0f) {
        for (int i = 0; i < warmupFrames; i++) {
            _state.effectState += calcEffectStateOffset(speed, frameTimeMs);
            int moveSpeed = static_cast<int>(_state.effectState / 4);
            _state.effectState -= moveSpeed * 4;

            radialAddMeteors(ctx, colorScheme, count, length, xOffset, yOffset, false, rng);
            radialMoveMeteors(moveSpeed, xOffset, yOffset, width, height, fadeWithDistance, false);
            radialRemoveMeteors(xOffset, yOffset, width, height, false);
        }
    }

    _state.effectState += calcEffectStateOffset(speed, frameTimeMs);
    int moveSpeed = static_cast<int>(_state.effectState / 4);
    _state.effectState -= moveSpeed * 4;

    int trueXOffset = xOffset * width / 2 / 100;
    int trueYOffset = yOffset * height / 2 / 100;
    int centerX = width / 2 + trueXOffset;
    int centerY = height / 2 + trueYOffset;

    auto calcDist = [](int cx, int cy, int px, int py) {
        return std::sqrt(static_cast<float>((px - cx) * (px - cx) + (py - cy) * (py - cy)));
    };
    float maxDiag = std::max({
        calcDist(centerX, centerY, 0, 0),
        calcDist(centerX, centerY, 0, height),
        calcDist(centerX, centerY, width, 0),
        calcDist(centerX, centerY, width, height)
    });

    int tailLength = (static_cast<int>(maxDiag) < 10) ? length / 10
                                                       : static_cast<int>(maxDiag * length / 100);
    if (tailLength < 1) tailLength = 1;

    radialAddMeteors(ctx, colorScheme, count, length, xOffset, yOffset, false, rng);

    for (const auto& m : _state.meteorsRadial) {
        for (int ph = 0; ph <= tailLength; ph++) {
            float hue = m.hue;
            if (colorScheme == MeteorColorScheme::Rainbow) {
                std::uniform_real_distribution<float> hueDist(0.0f, 1.0f);
                hue = hueDist(rng);
            }

            int x = static_cast<int>(m.x - m.dx * ph);
            int y = static_cast<int>(m.y - m.dy * ph);

            if ((std::abs(y - centerY) < 2) && (std::abs(x - centerX) < 2)) {
                break;
            }

            float fadeValue = static_cast<float>(ph) / tailLength;
            if (fadeWithDistance) {
                float distance = std::sqrt(static_cast<float>((x - centerX) * (x - centerX) +
                                                               (y - centerY) * (y - centerY)));
                if (distance < 10) distance = 10;
                fadeValue *= distance / maxDiag;
            }

            Color c = Color::fromHSV(hue, m.saturation, m.value * fadeValue);
            if (ctx.allowAlpha()) {
                c.alpha = static_cast<uint8_t>(255.0f * fadeValue);
            }
            ctx.setPixel(x, y, c);
        }
    }

    radialMoveMeteors(moveSpeed, xOffset, yOffset, width, height, fadeWithDistance, false);
    radialRemoveMeteors(xOffset, yOffset, width, height, false);
}

void MeteorsEffect::renderExplode(RenderContext& ctx, MeteorColorScheme colorScheme,
                                   int count, int length, int swirlIntensity, int speed,
                                   int xOffset, int yOffset, bool fadeWithDistance,
                                   int warmupFrames, float frameTimeMs, std::mt19937& rng) {
    int width = ctx.width();
    int height = ctx.height();

    if (_state.effectState == 0.0f) {
        for (int i = 0; i < warmupFrames; i++) {
            _state.effectState += calcEffectStateOffset(speed, frameTimeMs);
            int moveSpeed = static_cast<int>(_state.effectState / 4);
            _state.effectState -= moveSpeed * 4;

            radialAddMeteors(ctx, colorScheme, count, length, xOffset, yOffset, true, rng);
            radialMoveMeteors(moveSpeed, xOffset, yOffset, width, height, fadeWithDistance, true);
            radialRemoveMeteors(xOffset, yOffset, width, height, true);
        }
    }

    _state.effectState += calcEffectStateOffset(speed, frameTimeMs);
    int moveSpeed = static_cast<int>(_state.effectState / 4);
    _state.effectState -= moveSpeed * 4;

    int trueXOffset = xOffset * width / 2 / 100;
    int trueYOffset = yOffset * height / 2 / 100;
    int centerX = width / 2 + trueXOffset;
    int centerY = height / 2 + trueYOffset;

    auto calcDist = [](int cx, int cy, int px, int py) {
        return std::sqrt(static_cast<float>((px - cx) * (px - cx) + (py - cy) * (py - cy)));
    };
    float maxDiag = std::max({
        calcDist(centerX, centerY, 0, 0),
        calcDist(centerX, centerY, 0, height),
        calcDist(centerX, centerY, width, 0),
        calcDist(centerX, centerY, width, height)
    });

    int tailLength = (static_cast<int>(maxDiag) < 10) ? length / 10
                                                       : static_cast<int>(maxDiag * length / 100);
    if (tailLength < 1) tailLength = 1;

    radialAddMeteors(ctx, colorScheme, count, length, xOffset, yOffset, true, rng);

    for (const auto& m : _state.meteorsRadial) {
        for (int ph = 0; ph <= tailLength; ph++) {
            float hue = m.hue;
            if (colorScheme == MeteorColorScheme::Rainbow) {
                std::uniform_real_distribution<float> hueDist(0.0f, 1.0f);
                hue = hueDist(rng);
            }

            int x = static_cast<int>(m.x + m.dx * ph);
            int y = static_cast<int>(m.y + m.dy * ph);

            float fadeValue = static_cast<float>(ph) / tailLength;
            if (fadeWithDistance) {
                float distance = std::sqrt(static_cast<float>((x - centerX) * (x - centerX) +
                                                               (y - centerY) * (y - centerY)));
                if (distance < 10) distance = 10;
                fadeValue *= distance / maxDiag;
            }

            Color c = Color::fromHSV(hue, m.saturation, m.value * fadeValue);
            if (ctx.allowAlpha()) {
                c.alpha = static_cast<uint8_t>(255.0f * fadeValue);
            }
            ctx.setPixel(x, y, c);
        }
    }

    radialMoveMeteors(moveSpeed, xOffset, yOffset, width, height, fadeWithDistance, true);
    radialRemoveMeteors(xOffset, yOffset, width, height, true);
}

void MeteorsEffect::renderIcicles(RenderContext& ctx, MeteorColorScheme colorScheme,
                                   int count, int length, int swirlIntensity, int speed,
                                   bool showBackground, int warmupFrames,
                                   float frameTimeMs, std::mt19937& rng) {
    int width = ctx.width();
    int height = ctx.height();

    // Draw background icicles if requested
    if (showBackground) {
        Color bgColor(100, 50, 255);  // Light blue
        int ystaggered[] = {0, 5, 1, 2, 4};
        for (int x = 0; x < width; x += 3) {
            for (int y = 0; y < height; y += 3) {
                int yOffset = ystaggered[(x / 3) % 5];
                ctx.setPixel(x, y + yOffset, bgColor);
            }
        }
    }

    // Use vertical rendering with variable length icicles
    renderVertical(ctx, colorScheme, count, length, MeteorDirection::Down,
                   swirlIntensity, speed, warmupFrames, frameTimeMs, rng);
}

// ============================================================================
// Main Render Method
// ============================================================================

void MeteorsEffect::render(RenderContext& ctx, const EffectSettings& settings,
                            const RenderState& state) {
    // Get parameters
    MeteorDirection direction = parseMeteorDirection(
        settings.get("E_CHOICE_Meteors_Effect", "Down"));
    MeteorColorScheme colorScheme = parseMeteorColorScheme(
        settings.get("E_CHOICE_Meteors_Type", "Rainbow"));

    int count = settings.getInt("E_SLIDER_Meteors_Count", 10);
    int length = settings.getInt("E_SLIDER_Meteors_Length", 25);
    int swirlIntensity = settings.getInt("E_SLIDER_Meteors_Swirl_Intensity", 0);
    int speed = settings.getInt("E_SLIDER_Meteors_Speed", 10);
    int xOffset = settings.getInt("E_SLIDER_Meteors_XOffset", 0);
    int yOffset = settings.getInt("E_SLIDER_Meteors_YOffset", 0);
    bool fadeWithDistance = settings.getBool("E_CHECKBOX_FadeWithDistance", false);
    int warmupFrames = settings.getInt("E_SLIDER_Meteors_WarmupFrames", 0);

    // Frame timing
    float frameTimeMs = 50.0f;  // Default
    if (state.totalFrames > 0) {
        double duration = state.effectEndTime - state.effectStartTime;
        if (duration > 0) {
            frameTimeMs = static_cast<float>(duration * 1000.0 / state.totalFrames);
        }
    }

    // Create deterministic RNG
    std::mt19937 rng(state.randomSeed + static_cast<uint32_t>(state.frameIndex));

    // Initialize on first frame
    if (state.frameIndex == 0) {
        _state.meteors.clear();
        _state.meteorsRadial.clear();
        _state.effectState = 0.0f;
    }

    // Render based on direction
    switch (direction) {
        case MeteorDirection::Down:
        case MeteorDirection::Up:
            renderVertical(ctx, colorScheme, count, length, direction,
                           swirlIntensity, speed, warmupFrames, frameTimeMs, rng);
            break;

        case MeteorDirection::Left:
        case MeteorDirection::Right:
            renderHorizontal(ctx, colorScheme, count, length, direction,
                             swirlIntensity, speed, warmupFrames, frameTimeMs, rng);
            break;

        case MeteorDirection::Implode:
            renderImplode(ctx, colorScheme, count, length, swirlIntensity, speed,
                          xOffset, yOffset, fadeWithDistance, warmupFrames, frameTimeMs, rng);
            break;

        case MeteorDirection::Explode:
            renderExplode(ctx, colorScheme, count, length, swirlIntensity, speed,
                          xOffset, yOffset, fadeWithDistance, warmupFrames, frameTimeMs, rng);
            break;

        case MeteorDirection::Icicles:
            renderIcicles(ctx, colorScheme, count, length, swirlIntensity, speed,
                          false, warmupFrames, frameTimeMs, rng);
            break;

        case MeteorDirection::IciclesBkg:
            renderIcicles(ctx, colorScheme, count, length, swirlIntensity, speed,
                          true, warmupFrames, frameTimeMs, rng);
            break;
    }
}

// Register effect with registry
XLCORE_REGISTER_EFFECT(MeteorsEffect)

} // namespace xlCore
