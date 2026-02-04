/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "KaleidoscopeEffect.h"
#include "../RenderContext.h"
#include "../Math.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

std::vector<EffectParameter> KaleidoscopeEffect::parameters() const {
    std::vector<EffectParameter> params;

    auto type = EffectParameter::createChoice(
        "CHOICE_Kaleidoscope_Type", "Type", "Triangle",
        {"Triangle", "Square"});
    type.group = "Pattern";
    params.push_back(type);

    auto x = EffectParameter::createInt("Kaleidoscope_X", "Center X", 50,
        KALEIDOSCOPE_X_MIN, KALEIDOSCOPE_X_MAX, true);
    x.group = "Position";
    params.push_back(x);

    auto y = EffectParameter::createInt("Kaleidoscope_Y", "Center Y", 50,
        KALEIDOSCOPE_Y_MIN, KALEIDOSCOPE_Y_MAX, true);
    y.group = "Position";
    params.push_back(y);

    auto size = EffectParameter::createInt("Kaleidoscope_Size", "Size", 5,
        KALEIDOSCOPE_SIZE_MIN, KALEIDOSCOPE_SIZE_MAX, true);
    size.group = "Pattern";
    params.push_back(size);

    auto rotation = EffectParameter::createInt("Kaleidoscope_Rotation", "Rotation", 0,
        KALEIDOSCOPE_ROTATION_MIN, KALEIDOSCOPE_ROTATION_MAX, true);
    rotation.group = "Pattern";
    params.push_back(rotation);

    return params;
}

KaleidoscopeState& KaleidoscopeEffect::getState(const void* instanceKey) const {
    auto it = m_states.find(instanceKey);
    if (it == m_states.end()) {
        it = m_states.emplace(instanceKey, KaleidoscopeState{}).first;
    }
    return it->second;
}

void KaleidoscopeEffect::cleanupAfterRender() {
    m_states.clear();
}

bool KaleidoscopeEffect::isPointAboveLine(int x, int y, int x1, int y1, int x2, int y2) {
    if (x2 == x1) {
        // Vertical line - check if point is to the right
        return x > x1;
    }
    double slope = static_cast<double>(y2 - y1) / static_cast<double>(x2 - x1);
    double yintercept = slope * -1.0 * static_cast<double>(x1) + static_cast<double>(y1);
    double ytest = slope * x + yintercept;
    return static_cast<double>(y) > ytest;
}

Point2D KaleidoscopeEffect::getPointAfterMove(int x, int y, int degrees, double d) {
    double a = math::toRadians(static_cast<float>(degrees));
    double dx = d * std::cos(a);
    double dy = d * std::sin(a);

    // Round with special handling for near-0.5 values
    int f = (dx < 0) ? -1 : 1;
    double aa = std::abs(std::abs(dx) - static_cast<int>(std::abs(dx)) - 0.5);
    if (aa < 0.0000001) {
        dx = f * (static_cast<int>(std::abs(dx)) + 0.5);
    }

    f = (dy < 0) ? -1 : 1;
    double bb = std::abs(std::abs(dy) - static_cast<int>(std::abs(dy)) - 0.5);
    if (bb < 0.0000001) {
        dy = f * (static_cast<int>(std::abs(dy)) + 0.5);
    }

    return Point2D(x + static_cast<int>(std::round(dx)), y + static_cast<int>(std::round(dy)));
}

Point2D KaleidoscopeEffect::getSourceLocation(int x, int y, const KaleidoscopeEdge& edge) {
    double x1 = edge.p1.x;
    double x2 = edge.p2.x;
    double y1 = edge.p1.y;
    double y2 = edge.p2.y;

    double dx = x2 - x1;
    double dy = y2 - y1;

    double denom = dx * dx + dy * dy;
    if (denom < 0.0001) {
        return Point2D(x, y);  // Degenerate edge
    }

    double a = (dx * dx - dy * dy) / denom;
    double b = 2.0 * dx * dy / denom;

    return Point2D(
        static_cast<int>(std::round(a * (x - x1) + b * (y - y1) + x1)),
        static_cast<int>(std::round(b * (x - x1) - a * (y - y1) + y1))
    );
}

bool KaleidoscopeEffect::createEdge(KaleidoscopeState& state, int x1, int y1, int x2, int y2) const {
    // Check if edge is completely outside buffer
    if (x1 < 0 && x2 < 0) return false;
    if (x1 > state.width && x2 > state.width) return false;
    if (y1 < 0 && y2 < 0) return false;
    if (y1 > state.height && y2 > state.height) return false;

    // For non-axis-aligned lines, check if all corners are on the same side
    if (x1 != x2 && y1 != y2) {
        bool bl = isPointAboveLine(0, 0, x1, y1, x2, y2);
        bool tl = isPointAboveLine(0, state.height - 1, x1, y1, x2, y2);
        bool tr = isPointAboveLine(state.width - 1, state.height - 1, x1, y1, x2, y2);
        bool br = isPointAboveLine(state.width - 1, 0, x1, y1, x2, y2);

        // If all corners are on the same side, this edge doesn't help
        if (bl == tl && bl == tr && bl == br) return false;
    }

    state.edges.emplace_back(Point2D(x1, y1), Point2D(x2, y2));
    return true;
}

bool KaleidoscopeEffect::isDone(const std::vector<std::vector<bool>>& used) {
    for (const auto& column : used) {
        for (bool val : column) {
            if (!val) return false;
        }
    }
    return true;
}

void KaleidoscopeEffect::initializeSquare(KaleidoscopeState& state, int size, int rotation,
                                         int x, int y, int width, int height) const {
    // Mark initial square region as used
    for (int xx = std::max(0, x - size / 2); xx <= std::min(x + size / 2, width - 1); xx++) {
        for (int yy = std::max(0, y - size / 2); yy <= std::min(y + size / 2, height - 1); yy++) {
            if (xx >= 0 && xx < width && yy >= 0 && yy < height) {
                state.startUsed[xx][yy] = true;
            }
        }
    }

    // Create concentric square edges
    double cornerDistance = std::sqrt(2.0 * size * size) / 2.0;
    int iterations = 0;
    int added;

    do {
        added = 0;
        auto p1 = getPointAfterMove(x, y, rotation + 45, (2 * iterations + 1) * cornerDistance);
        auto p2 = getPointAfterMove(x, y, rotation + 45 + 90, (2 * iterations + 1) * cornerDistance);
        auto p3 = getPointAfterMove(x, y, rotation + 45 + 180, (2 * iterations + 1) * cornerDistance);
        auto p4 = getPointAfterMove(x, y, rotation + 45 + 270, (2 * iterations + 1) * cornerDistance);

        if (createEdge(state, p1.x, p1.y, p2.x, p2.y)) added++;
        if (createEdge(state, p2.x, p2.y, p3.x, p3.y)) added++;
        if (createEdge(state, p3.x, p3.y, p4.x, p4.y)) added++;
        if (createEdge(state, p4.x, p4.y, p1.x, p1.y)) added++;

        iterations++;
    } while (added > 0);
}

void KaleidoscopeEffect::initializeTriangle(KaleidoscopeState& state, int size, int rotation,
                                           int x, int y, int width, int height) const {
    constexpr double radiusFactor = 0.28867513459; // tan(30 degrees) / 2
    double radius = size * radiusFactor;

    // Calculate triangle corners
    auto pTop = getPointAfterMove(x, y, rotation + 90, static_cast<int>(radius));
    auto pBL = getPointAfterMove(x, y, rotation + 240, static_cast<int>(radius));
    auto pBR = getPointAfterMove(x, y, rotation + 300, static_cast<int>(radius));

    int minx = pBL.x;
    int miny = pBL.y;
    int maxx = pBR.x;
    int maxy = pTop.y;
    int midx = (maxx + minx) / 2;

    // Mark initial triangle region as used
    for (int xx = std::max(0, minx); xx < std::min(midx, width - 1); xx++) {
        for (int yy = std::max(0, miny); yy <= std::min(maxy, height - 1); yy++) {
            if (!isPointAboveLine(xx, yy, minx, miny, midx, maxy)) {
                state.startUsed[xx][yy] = true;
            }
        }
    }
    for (int xx = std::max(0, midx); xx <= std::min(maxx, width - 1); xx++) {
        for (int yy = std::max(0, miny); yy <= std::min(maxy, height - 1); yy++) {
            if (!isPointAboveLine(xx, yy, midx, maxy, maxx, miny)) {
                state.startUsed[xx][yy] = true;
            }
        }
    }

    // Adjust radius for edges
    if (radius > 10) {
        radius -= 1;
    } else if (radius > 5) {
        radius -= 0.5;
    } else {
        radius -= 0.1;
    }

    // Create concentric triangle edges
    double s = size;
    double gap = std::sqrt(s * s - s / 2.0 * s / 2.0);
    int iterations = 0;
    int added;

    do {
        added = 0;
        double currentRadius = (iterations == 0) ? radius : (iterations * gap + radius);

        auto p1 = getPointAfterMove(x, y, rotation + 90, static_cast<int>(currentRadius));
        auto p2 = getPointAfterMove(x, y, rotation + 240, static_cast<int>(currentRadius));
        auto p3 = getPointAfterMove(x, y, rotation + 300, static_cast<int>(currentRadius));

        if (createEdge(state, p1.x, p1.y, p2.x, p2.y)) added++;
        if (createEdge(state, p2.x, p2.y, p3.x, p3.y)) added++;
        if (createEdge(state, p3.x, p3.y, p1.x, p1.y)) added++;

        iterations++;
    } while (added > 0);
}

void KaleidoscopeEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    std::string type = settings.get("CHOICE_Kaleidoscope_Type", "Triangle");
    int xCentre = settings.getInt("Kaleidoscope_X", 50) * ctx.width() / 100;
    int yCentre = settings.getInt("Kaleidoscope_Y", 50) * ctx.height() / 100;
    int size = settings.getInt("Kaleidoscope_Size", 5);
    int rotation = settings.getInt("Kaleidoscope_Rotation", 0);

    int width = ctx.width();
    int height = ctx.height();

    // Get or create cached state
    KaleidoscopeState& kstate = getState(state.modelData);

    // Initialize or reinitialize state if parameters changed
    bool needsInit = state.frameIndex == 0 ||
                     kstate.needsReinit(size, rotation, xCentre, yCentre, width, height);

    if (needsInit) {
        kstate.size = size;
        kstate.rotation = rotation;
        kstate.x = xCentre;
        kstate.y = yCentre;
        kstate.width = width;
        kstate.height = height;

        // Clear and resize used array
        kstate.startUsed.assign(width, std::vector<bool>(height, false));
        kstate.edges.clear();

        // Initialize based on type
        if (type == "Square") {
            initializeSquare(kstate, size, rotation, xCentre, yCentre, width, height);
        } else {
            initializeTriangle(kstate, size, rotation, xCentre, yCentre, width, height);
        }
    }

    // Create working copy of used array
    auto currentUsed = kstate.startUsed;
    const auto& edges = kstate.edges;

    if (edges.empty()) return;

    // Iteratively fill pixels by reflecting across edges
    auto edgeIt = edges.begin();
    int setSinceBegin = 0;

    while (!isDone(currentUsed)) {
        int setThisPass = 0;

        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                if (!currentUsed[x][y]) {
                    // This pixel needs to be set via reflection
                    Point2D source = getSourceLocation(x, y, *edgeIt);

                    if (source.x >= 0 && source.x < width &&
                        source.y >= 0 && source.y < height) {
                        if (currentUsed[source.x][source.y]) {
                            ctx.setPixel(x, y, ctx.getPixel(source.x, source.y));
                            currentUsed[x][y] = true;
                            setThisPass++;
                            setSinceBegin++;
                        }
                    }
                }
            }
        }

        ++edgeIt;
        if (edgeIt == edges.end()) {
            if (setSinceBegin == 0) {
                break;  // No progress, avoid infinite loop
            }
            setSinceBegin = 0;
            edgeIt = edges.begin();
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(KaleidoscopeEffect)

} // namespace xlCore
