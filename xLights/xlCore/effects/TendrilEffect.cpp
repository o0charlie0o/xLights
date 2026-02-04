/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "TendrilEffect.h"
#include "../RenderContext.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

// ============================================================================
// SingleTendril Implementation
// ============================================================================

SingleTendril::SingleTendril(float friction, int size, float dampening, float tension, float spring, const Point2D& start) {
    // Default values with parameter overrides
    m_friction = (friction >= 0) ? friction : 0.5f;
    m_dampening = (dampening >= 0) ? dampening : 0.25f;
    m_tension = (tension >= 0) ? tension : 0.98f;
    m_spring = (spring >= 0) ? spring : 0.0f;

    int nodeCount = (size > 0) ? size : 60;

    // Add small random variation to friction
    static std::mt19937 rng(42);
    std::uniform_real_distribution<float> dist(-0.005f, 0.005f);
    m_friction += dist(rng);

    // Initialize all nodes at the start position
    m_nodes.reserve(nodeCount);
    for (int i = 0; i < nodeCount; ++i) {
        m_nodes.emplace_back(static_cast<float>(start.x), static_cast<float>(start.y));
    }
}

void SingleTendril::update(const Point2D& target, int tunemovement, int width, int height) {
    if (m_nodes.empty()) return;

    if (m_lastWidth == -1) m_lastWidth = width;
    if (m_lastHeight == -1) m_lastHeight = height;

    float spring = m_spring;
    TendrilNode& head = m_nodes.front();

    // Adjust for buffer size changes
    int xSign = (width == m_lastWidth) ? 0 : (width - m_lastWidth) / std::abs(width - m_lastWidth);
    int ySign = (height == m_lastHeight) ? 0 : (height - m_lastHeight) / std::abs(height - m_lastHeight);

    if (head.vx == 0.0f) {
        head.vx += xSign * static_cast<float>(width - m_lastWidth) * 2.0f * tunemovement / 20.0f;
    } else {
        head.vx *= 1.0f + static_cast<float>(width - m_lastWidth) * 2.0f * tunemovement / 20.0f;
        if (head.vx == 0.0f) head.vx = 0.01f * xSign;
    }

    if (head.vy == 0.0f) {
        head.vy += ySign * static_cast<float>(height - m_lastHeight) * 2.0f * tunemovement / 20.0f;
    } else {
        head.vy *= 1.0f + static_cast<float>(height - m_lastHeight) * 2.0f * tunemovement / 20.0f;
        if (head.vy == 0.0f) head.vy = 0.01f * ySign;
    }

    // Apply spring force towards target
    head.vx += (target.x - head.x) * spring;
    head.vy += (target.y - head.y) * spring;

    // Update each node
    TendrilNode* prev = nullptr;
    for (auto& node : m_nodes) {
        if (prev != nullptr) {
            // Spring force from previous node
            node.vx += (prev->x - node.x) * spring;
            node.vy += (prev->y - node.y) * spring;
            // Dampening from previous velocity
            node.vx += prev->vx * m_dampening;
            node.vy += prev->vy * m_dampening;
        }

        // Apply friction
        node.vx *= m_friction;
        node.vy *= m_friction;

        // Update position
        node.x += node.vx;
        node.y += node.vy;

        // Clamp to bounds (with some overflow allowed)
        node.x = std::clamp(node.x, static_cast<float>(-width), static_cast<float>(2 * width));
        node.y = std::clamp(node.y, static_cast<float>(-height), static_cast<float>(2 * height));

        prev = &node;
        spring *= m_tension;
    }

    m_lastWidth = width;
    m_lastHeight = height;
}

void SingleTendril::draw(RenderContext& ctx, const Color& color, int thickness) const {
    if (m_nodes.size() < 3) return;

    // Draw quadratic bezier curves through the nodes
    // Start at first node
    auto it = m_nodes.begin();
    Vec2 prev(it->x, it->y);
    ++it;

    // Skip to second-to-last
    auto secondLast = m_nodes.end();
    --secondLast;
    --secondLast;

    // Draw curves through middle nodes
    for (; it != secondLast; ++it) {
        const TendrilNode& a = *it;
        auto nextIt = it;
        ++nextIt;
        const TendrilNode& b = *nextIt;

        // Midpoint for smooth curve
        float midX = (a.x + b.x) * 0.5f;
        float midY = (a.y + b.y) * 0.5f;

        // Draw line segments approximating the quadratic curve
        // Simple linear approximation for now
        ctx.drawThickLine(
            static_cast<int>(prev.x), static_cast<int>(prev.y),
            static_cast<int>(a.x), static_cast<int>(a.y),
            color, thickness, false
        );

        prev = Vec2(a.x, a.y);
    }

    // Draw final segment to the last two nodes
    const TendrilNode& a = *it;
    ++it;
    const TendrilNode& b = *it;

    ctx.drawThickLine(
        static_cast<int>(prev.x), static_cast<int>(prev.y),
        static_cast<int>(a.x), static_cast<int>(a.y),
        color, thickness, false
    );
    ctx.drawThickLine(
        static_cast<int>(a.x), static_cast<int>(a.y),
        static_cast<int>(b.x), static_cast<int>(b.y),
        color, thickness, false
    );
}

Point2D SingleTendril::lastLocation() const {
    if (m_nodes.empty()) {
        return Point2D(0, 0);
    }
    return m_nodes.back().toPoint();
}

// ============================================================================
// TendrilGroup Implementation
// ============================================================================

TendrilGroup::TendrilGroup(float friction, int trails, int size, float dampening,
                           float tension, float springbase, float springincr, const Point2D& start) {
    float sb = (springbase >= 0) ? springbase : 0.45f;
    float si = (springincr >= 0) ? springincr : 0.025f;
    int t = (trails > 0) ? trails : 10;

    m_tendrils.reserve(t);
    for (int i = 0; i < t; ++i) {
        float aspring = sb + si * (static_cast<float>(i) / static_cast<float>(t));
        m_tendrils.emplace_back(friction, size, dampening, tension, aspring, start);
    }
}

void TendrilGroup::updateRandomMove(int tunemovement, int width, int height, std::mt19937& rng) {
    if (tunemovement < 1) tunemovement = 1;

    int minx = -width / 4;
    int miny = -height / 4;
    int maxx = width + width / 4;
    int maxy = height + height / 4;
    int minmovex = -width * 2 * tunemovement / 20;
    int minmovey = -height * 2 * tunemovement / 20;
    int maxmovex = width * 2 * tunemovement / 20;
    int maxmovey = height * 2 * tunemovement / 20;

    if (m_tendrils.empty()) return;

    Point2D current = m_tendrils.front().lastLocation();

    // Calculate constrained movement range
    int realminmovex = minmovex;
    if (minmovex < 0) {
        realminmovex = -std::min(current.x, -minmovex);
    }
    int realmaxmovex = maxmovex;
    if (maxmovex > 0) {
        realmaxmovex = std::min(maxx - current.x, maxmovex);
    }
    int realminmovey = minmovey;
    if (minmovey < 0) {
        realminmovey = -std::min(current.y, -minmovey);
    }
    int realmaxmovey = maxmovey;
    if (maxmovey > 0) {
        realmaxmovey = std::min(maxy - current.y, maxmovey);
    }

    int xmove = -realminmovex + realmaxmovex;
    int ymove = -realminmovey + realmaxmovey;

    int x = 0, y = 0;
    if (xmove > 0) {
        std::uniform_int_distribution<int> distX(0, xmove - 1);
        x = distX(rng) + realminmovex;
    }
    if (ymove > 0) {
        std::uniform_int_distribution<int> distY(0, ymove - 1);
        y = distY(rng) + realminmovey;
    }

    current.x = std::clamp(current.x + x, minx, maxx);
    current.y = std::clamp(current.y + y, miny, maxy);

    update(current, tunemovement, width, height);
}

void TendrilGroup::update(const Point2D& target, int tunemovement, int width, int height) {
    for (auto& tendril : m_tendrils) {
        tendril.update(target, tunemovement, width, height);
    }
}

void TendrilGroup::update(int x, int y, int tunemovement, int width, int height) {
    update(Point2D(x, y), tunemovement, width, height);
}

void TendrilGroup::draw(RenderContext& ctx, const Color& color, int thickness) const {
    for (const auto& tendril : m_tendrils) {
        tendril.draw(ctx, color, thickness);
    }
}

// ============================================================================
// TendrilEffect Implementation
// ============================================================================

std::vector<EffectParameter> TendrilEffect::parameters() const {
    std::vector<EffectParameter> params;

    auto movement = EffectParameter::createChoice(
        "CHOICE_Tendril_Movement", "Movement", "Random",
        {"Random", "Square", "Circle", "Horizontal Zig Zag", "Vertical Zig Zag",
         "Music Line", "Music Circle", "Vert. Zig Zag Return", "Horiz. Zig Zag Return", "Manual"});
    movement.group = "Movement";
    params.push_back(movement);

    auto tune = EffectParameter::createInt("Tendril_TuneMovement", "Tune Movement", 10, TENDRIL_MOVEMENT_MIN, TENDRIL_MOVEMENT_MAX, true);
    tune.group = "Movement";
    params.push_back(tune);

    auto speed = EffectParameter::createInt("Tendril_Speed", "Speed", 10, 1, 10);
    speed.group = "Movement";
    params.push_back(speed);

    auto thickness = EffectParameter::createInt("Tendril_Thickness", "Thickness", 1, TENDRIL_THICKNESS_MIN, TENDRIL_THICKNESS_MAX, true);
    thickness.group = "Appearance";
    params.push_back(thickness);

    auto friction = EffectParameter::createInt("Tendril_Friction", "Friction", 10, 0, 20);
    friction.group = "Physics";
    params.push_back(friction);

    auto dampening = EffectParameter::createInt("Tendril_Dampening", "Dampening", 10, 0, 20);
    dampening.group = "Physics";
    params.push_back(dampening);

    auto tension = EffectParameter::createInt("Tendril_Tension", "Tension", 20, 0, 39);
    tension.group = "Physics";
    params.push_back(tension);

    auto trails = EffectParameter::createInt("Tendril_Trails", "Trails", 1, 1, 10);
    trails.group = "Appearance";
    params.push_back(trails);

    auto length = EffectParameter::createInt("Tendril_Length", "Length", 60, 10, 100);
    length.group = "Appearance";
    params.push_back(length);

    auto xoffset = EffectParameter::createInt("Tendril_XOffset", "X Offset", 0, TENDRIL_OFFSETX_MIN, TENDRIL_OFFSETX_MAX, true);
    xoffset.group = "Position";
    params.push_back(xoffset);

    auto yoffset = EffectParameter::createInt("Tendril_YOffset", "Y Offset", 0, TENDRIL_OFFSETY_MIN, TENDRIL_OFFSETY_MAX, true);
    yoffset.group = "Position";
    params.push_back(yoffset);

    auto manualX = EffectParameter::createInt("Tendril_ManualX", "Manual X", 0, TENDRIL_MANUALX_MIN, TENDRIL_MANUALX_MAX, true);
    manualX.group = "Manual";
    params.push_back(manualX);

    auto manualY = EffectParameter::createInt("Tendril_ManualY", "Manual Y", 0, TENDRIL_MANUALY_MIN, TENDRIL_MANUALY_MAX, true);
    manualY.group = "Manual";
    params.push_back(manualY);

    return params;
}

TendrilMovement TendrilEffect::encodeMovement(const std::string& movement) {
    if (movement == "Random") return TendrilMovement::Random;
    if (movement == "Square") return TendrilMovement::Square;
    if (movement == "Circle") return TendrilMovement::Circle;
    if (movement == "Horizontal Zig Zag") return TendrilMovement::HorizontalZigZag;
    if (movement == "Vertical Zig Zag") return TendrilMovement::VerticalZigZag;
    if (movement == "Music Line") return TendrilMovement::MusicLine;
    if (movement == "Music Circle") return TendrilMovement::MusicCircle;
    if (movement == "Vert. Zig Zag Return") return TendrilMovement::VertZigZagReturn;
    if (movement == "Horiz. Zig Zag Return") return TendrilMovement::HorizZigZagReturn;
    if (movement == "Manual") return TendrilMovement::Manual;
    return TendrilMovement::Random;
}

Color TendrilEffect::getBlendedColor(const std::vector<Color>& palette, double progress) {
    if (palette.empty()) return Color::White();
    if (palette.size() == 1) return palette[0];

    // Clamp progress
    progress = std::clamp(progress, 0.0, 1.0);

    // Calculate position in palette
    double pos = progress * (palette.size() - 1);
    int idx = static_cast<int>(pos);
    double frac = pos - idx;

    if (idx >= static_cast<int>(palette.size()) - 1) {
        return palette.back();
    }

    const Color& c1 = palette[idx];
    const Color& c2 = palette[idx + 1];

    return Color(
        static_cast<uint8_t>(c1.red + (c2.red - c1.red) * frac),
        static_cast<uint8_t>(c1.green + (c2.green - c1.green) * frac),
        static_cast<uint8_t>(c1.blue + (c2.blue - c1.blue) * frac)
    );
}

TendrilState& TendrilEffect::getState(const void* instanceKey) const {
    auto it = m_states.find(instanceKey);
    if (it == m_states.end()) {
        it = m_states.emplace(instanceKey, TendrilState{}).first;
    }
    return it->second;
}

void TendrilEffect::cleanupAfterRender() {
    m_states.clear();
}

void TendrilEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    std::string movementStr = settings.get("CHOICE_Tendril_Movement", "Random");
    int tunemovement = settings.getInt("Tendril_TuneMovement", 10);
    int speed = settings.getInt("Tendril_Speed", 10);
    int thickness = settings.getInt("Tendril_Thickness", 1);

    // Convert UI values to physics parameters
    float friction = settings.getInt("Tendril_Friction", 10) / 20.0f * 0.2f + 0.4f;  // 0.4-0.6
    float dampening = settings.getInt("Tendril_Dampening", 10) / 20.0f * 0.5f;       // 0.0-0.5
    float tension = settings.getInt("Tendril_Tension", 20) / 39.0f * 0.039f + 0.96f; // 0.96-0.999

    int trails = settings.getInt("Tendril_Trails", 1);
    int length = settings.getInt("Tendril_Length", 60);
    int xoffset = settings.getInt("Tendril_XOffset", 0);
    int yoffset = settings.getInt("Tendril_YOffset", 0);
    int manualx = settings.getInt("Tendril_ManualX", 0);
    int manualy = settings.getInt("Tendril_ManualY", 0);

    // Clamp physics parameters
    friction = std::clamp(friction, 0.4f, 0.6f);
    dampening = std::clamp(dampening, 0.0f, 0.5f);
    tension = std::clamp(tension, 0.96f, 0.999f);

    // Get or create state
    TendrilState& tendrilState = getState(state.modelData);

    int width = ctx.width();
    int height = ctx.height();

    int truexoffset = xoffset * width / 100;
    int trueyoffset = yoffset * height / 100;

    TendrilMovement movement = encodeMovement(movementStr);

    // Initialize tendril if needed
    if (!tendrilState.initialized || state.frameIndex == 0) {
        tendrilState.initialized = true;
        tendrilState.rng.seed(static_cast<unsigned int>(state.randomSeed));

        Point2D startmiddle(width / 2 + truexoffset / 2, height / 2 + trueyoffset / 2);
        Point2D startmiddlebottom(width / 2 + truexoffset / 2, trueyoffset);
        Point2D startbottomleft(truexoffset, trueyoffset);
        Point2D startmiddleleft(truexoffset, height / 2 + trueyoffset / 2);

        tendrilState.mv1 = 0;
        tendrilState.mv2 = 0;
        tendrilState.mv3 = 0;
        tendrilState.mv4 = 0;

        switch (movement) {
            case TendrilMovement::Random:
                tendrilState.tendril = std::make_unique<TendrilGroup>(friction, trails, length, dampening, tension, -1, -1, startmiddle);
                break;
            case TendrilMovement::Square:
                tendrilState.mv1 = truexoffset;
                tendrilState.mv2 = trueyoffset;
                tendrilState.mv3 = 0;
                tendrilState.mv4 = tunemovement;
                if (tendrilState.mv4 == 0) tendrilState.mv4 = 1;
                tendrilState.tendril = std::make_unique<TendrilGroup>(friction, trails, length, dampening, tension, -1, -1, startbottomleft);
                break;
            case TendrilMovement::Circle:
                tendrilState.mv1 = 0;
                tendrilState.mv2 = std::min(width, height) / 2;
                tendrilState.mv3 = tunemovement * 3;
                if (tendrilState.mv3 == 0) tendrilState.mv3 = 1;
                tendrilState.tendril = std::make_unique<TendrilGroup>(friction, trails, length, dampening, tension, -1, -1, startmiddle);
                break;
            case TendrilMovement::HorizontalZigZag:
                tendrilState.mv1 = trueyoffset;
                tendrilState.mv2 = static_cast<int>(tunemovement * 1.5);
                if (tendrilState.mv2 == 0) tendrilState.mv2 = 1;
                tendrilState.mv3 = 1;
                tendrilState.tendril = std::make_unique<TendrilGroup>(friction, trails, length, dampening, tension, -1, -1, startmiddlebottom);
                break;
            case TendrilMovement::VerticalZigZag:
                tendrilState.mv1 = truexoffset;
                tendrilState.mv2 = static_cast<int>(tunemovement * 1.5);
                tendrilState.mv3 = 1;
                tendrilState.tendril = std::make_unique<TendrilGroup>(friction, trails, length, dampening, tension, -1, -1, startmiddleleft);
                break;
            case TendrilMovement::MusicLine:
                tendrilState.mv1 = truexoffset;
                tendrilState.mv3 = tunemovement;
                if (tendrilState.mv3 < 1) tendrilState.mv3 = 1;
                tendrilState.tendril = std::make_unique<TendrilGroup>(friction, trails, length, dampening, tension, -1, -1, startbottomleft);
                break;
            case TendrilMovement::MusicCircle:
                tendrilState.mv1 = 0;
                tendrilState.mv2 = std::min(width, height) / 2;
                tendrilState.mv3 = tunemovement * 3;
                if (tendrilState.mv3 < 1) tendrilState.mv3 = 1;
                tendrilState.tendril = std::make_unique<TendrilGroup>(friction, trails, length, dampening, tension, -1, -1, startmiddle);
                break;
            case TendrilMovement::HorizZigZagReturn:
                tendrilState.mv1 = 0;
                tendrilState.mv2 = static_cast<int>(tunemovement * 1.5);
                if (tendrilState.mv2 == 0) tendrilState.mv2 = 1;
                tendrilState.mv3 = 1;
                tendrilState.tendril = std::make_unique<TendrilGroup>(friction, trails, length, dampening, tension, -1, -1, startmiddlebottom);
                break;
            case TendrilMovement::VertZigZagReturn:
                tendrilState.mv1 = 0;
                tendrilState.mv2 = static_cast<int>(tunemovement * 1.5);
                tendrilState.mv3 = 1;
                tendrilState.tendril = std::make_unique<TendrilGroup>(friction, trails, length, dampening, tension, -1, -1, startmiddleleft);
                break;
            case TendrilMovement::Manual:
                tendrilState.tendril = std::make_unique<TendrilGroup>(friction, trails, length, dampening, tension, -1, -1,
                    Point2D(manualx * width / 100, manualy * height / 100));
                break;
        }
    }

    // Update radius for circle-based movements
    switch (movement) {
        case TendrilMovement::Circle:
        case TendrilMovement::MusicCircle:
            tendrilState.mv2 = std::min(width, height) / 2;
            break;
        default:
            break;
    }

    const double PI = 3.141592653589793238463;
    int speedThrottle = 10 - speed;

    // Only update on certain frames based on speed
    bool shouldUpdate = (speedThrottle <= 0 || state.frameIndex % speedThrottle == 0);

    if (shouldUpdate && tendrilState.tendril) {
        switch (movement) {
            case TendrilMovement::Random:
                tendrilState.tendril->updateRandomMove(tunemovement, width, height, tendrilState.rng);
                break;

            case TendrilMovement::Square: {
                tendrilState.mv4 = tunemovement;
                switch (tendrilState.mv3) {
                    case 0:
                        if (tendrilState.mv4 == 0) tendrilState.mv4 = 1;
                        tendrilState.mv1 += std::max(width / tendrilState.mv4, 1);
                        if (tendrilState.mv1 >= width + truexoffset - width / tendrilState.mv4) {
                            tendrilState.mv3++;
                        }
                        break;
                    case 1:
                        if (tendrilState.mv4 == 0) tendrilState.mv4 = 1;
                        tendrilState.mv2 += std::max(height / tendrilState.mv4, 1);
                        if (tendrilState.mv2 >= height + trueyoffset - height / tendrilState.mv4) {
                            tendrilState.mv3++;
                        }
                        break;
                    case 2:
                        if (tendrilState.mv4 == 0) tendrilState.mv4 = 1;
                        tendrilState.mv1 -= std::max(width / tendrilState.mv4, 1);
                        if (tendrilState.mv1 <= truexoffset + width / tendrilState.mv4) {
                            tendrilState.mv3++;
                        }
                        break;
                    case 3:
                        if (tendrilState.mv4 == 0) tendrilState.mv4 = 1;
                        tendrilState.mv2 -= std::max(height / tendrilState.mv4, 1);
                        if (tendrilState.mv2 <= trueyoffset + height / tendrilState.mv4) {
                            tendrilState.mv3 = 0;
                        }
                        break;
                }
                tendrilState.tendril->update(tendrilState.mv1, tendrilState.mv2, tunemovement, width, height);
            } break;

            case TendrilMovement::Circle: {
                tendrilState.mv3 = tunemovement * 3;
                tendrilState.mv1 = tendrilState.mv1 + tendrilState.mv3;
                if (tendrilState.mv1 > 360) tendrilState.mv1 = 0;
                int x = static_cast<int>(std::sin(tendrilState.mv1 / 360.0 * PI * 2.0) * tendrilState.mv2 + width / 2.0 + truexoffset / 2);
                int y = static_cast<int>(std::cos(tendrilState.mv1 / 360.0 * PI * 2.0) * tendrilState.mv2 + height / 2.0 + trueyoffset / 2);
                tendrilState.tendril->update(x, y, tunemovement, width, height);
            } break;

            case TendrilMovement::HorizontalZigZag: {
                tendrilState.mv2 = static_cast<int>(tunemovement * 1.5);
                if (tendrilState.mv2 == 0) tendrilState.mv2 = 1;
                tendrilState.mv1 = tendrilState.mv1 + tendrilState.mv3;
                int x = truexoffset + static_cast<int>(std::sin(std::max(static_cast<double>(height) / tendrilState.mv2, 0.5) * PI * tendrilState.mv1 / height) * width / 2.0 + width / 2.0);
                if (tendrilState.mv1 >= trueyoffset + height || tendrilState.mv1 <= trueyoffset) {
                    tendrilState.mv3 = tendrilState.mv3 * -1;
                }
                if (tendrilState.mv3 < 0) {
                    x = width + truexoffset + truexoffset - x;
                }
                tendrilState.tendril->update(x, tendrilState.mv1, tunemovement, width, height);
            } break;

            case TendrilMovement::VerticalZigZag: {
                tendrilState.mv2 = static_cast<int>(tunemovement * 1.5);
                tendrilState.mv1 = tendrilState.mv1 + tendrilState.mv3;
                int y = trueyoffset + static_cast<int>(std::sin(std::max(static_cast<double>(width) / tendrilState.mv2, 0.5) * PI * tendrilState.mv1 / width) * height / 2.0 + height / 2.0);
                if (tendrilState.mv1 >= truexoffset + width || tendrilState.mv1 <= truexoffset) {
                    tendrilState.mv3 = tendrilState.mv3 * -1;
                }
                if (tendrilState.mv3 < 0) {
                    y = height + trueyoffset + trueyoffset - y;
                }
                tendrilState.tendril->update(tendrilState.mv1, y, tunemovement, width, height);
            } break;

            case TendrilMovement::MusicLine: {
                // Music reactive - use a fixed value for now (no audio data)
                float f = 0.5f;  // Would come from audio
                tendrilState.mv1 = tendrilState.mv1 + tendrilState.mv3;
                if ((tendrilState.mv1 < truexoffset && tendrilState.mv3 < 0) || (tendrilState.mv1 > width + truexoffset && tendrilState.mv3 > 0)) {
                    tendrilState.mv3 = tendrilState.mv3 * -1;
                }
                tendrilState.tendril->update(tendrilState.mv1, trueyoffset + static_cast<int>(height * f), tunemovement, width, height);
            } break;

            case TendrilMovement::MusicCircle: {
                tendrilState.mv3 = tunemovement * 3;
                if (tendrilState.mv3 < 1) tendrilState.mv3 = 1;
                float f = 0.5f;  // Would come from audio
                tendrilState.mv1 = tendrilState.mv1 + tendrilState.mv3;
                if (tendrilState.mv1 > 360) tendrilState.mv1 = 0;
                int x = static_cast<int>(std::sin(tendrilState.mv1 / 360.0 * PI * 2.0) * tendrilState.mv2 * f * 2 + width / 2.0 + truexoffset / 2);
                int y = static_cast<int>(std::cos(tendrilState.mv1 / 360.0 * PI * 2.0) * tendrilState.mv2 * f * 2 + height / 2.0 + trueyoffset / 2);
                tendrilState.tendril->update(x, y, tunemovement, width, height);
            } break;

            case TendrilMovement::HorizZigZagReturn: {
                tendrilState.mv2 = static_cast<int>(tunemovement * 1.5);
                if (tendrilState.mv2 == 0) tendrilState.mv2 = 1;
                tendrilState.mv1 = tendrilState.mv1 + tendrilState.mv3;
                int x = width / 2 + truexoffset / 2;
                if (tendrilState.mv3 > 0) {
                    x = truexoffset + static_cast<int>(std::sin(std::max(static_cast<double>(height) / tendrilState.mv2, 0.5) * PI * tendrilState.mv1 / height) * width / 2.0 + width / 2.0);
                }
                if (tendrilState.mv1 >= height || tendrilState.mv1 <= 0) {
                    tendrilState.mv3 = tendrilState.mv3 * -1;
                }
                tendrilState.tendril->update(x, tendrilState.mv1 + trueyoffset, tunemovement, width, height);
            } break;

            case TendrilMovement::VertZigZagReturn: {
                tendrilState.mv2 = static_cast<int>(tunemovement * 1.5);
                tendrilState.mv1 = tendrilState.mv1 + tendrilState.mv3;
                int y = height / 2 + trueyoffset / 2;
                if (tendrilState.mv3 > 0) {
                    y = trueyoffset + static_cast<int>(std::sin(std::max(static_cast<double>(width) / tendrilState.mv2, 0.5) * PI * tendrilState.mv1 / width) * height / 2.0 + height / 2.0);
                }
                if (tendrilState.mv1 >= width || tendrilState.mv1 <= 0) {
                    tendrilState.mv3 = tendrilState.mv3 * -1;
                }
                tendrilState.tendril->update(tendrilState.mv1 + truexoffset, y, tunemovement, width, height);
            } break;

            case TendrilMovement::Manual: {
                tendrilState.tendril->update(manualx * width / 100 + truexoffset, manualy * height / 100 + trueyoffset, tunemovement, width, height);
            } break;
        }
    }

    // Get color from palette (simple blend based on progress)
    Color color = Color::White();
    // For now, use white. In a full implementation, we'd get palette from settings.

    // Draw the tendril
    if (tendrilState.tendril) {
        ctx.clear();  // Tendril effect typically clears first
        tendrilState.tendril->draw(ctx, color, thickness);
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(TendrilEffect)

} // namespace xlCore
