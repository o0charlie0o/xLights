/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// System headers first (before Math.h to avoid macOS cmath collision)
#include <cmath>
#include <algorithm>

#include "SnowflakesEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

namespace xlCore {

// ============================================================================
// Helper Functions
// ============================================================================

static SnowfallMode parseSnowfallMode(const std::string& mode) {
    if (mode == "Driving") return SnowfallMode::Driving;
    if (mode == "Falling") return SnowfallMode::Falling;
    if (mode == "Falling & Accumulating") return SnowfallMode::FallingAccumulating;
    return SnowfallMode::Driving;
}

static SnowflakeType intToSnowflakeType(int type) {
    if (type < 0 || type > 9) return SnowflakeType::Random;
    return static_cast<SnowflakeType>(type);
}

// ============================================================================
// SnowflakesEffect Implementation
// ============================================================================

std::vector<EffectParameter> SnowflakesEffect::parameters() const {
    std::vector<EffectParameter> params;

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Snowflakes_Count", "Count", 5, 1, 20, true));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Snowflakes_Type", "Type", 1, 0, 9));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Snowflakes_Speed", "Speed", 10, 1, 50, true));

    params.push_back(EffectParameter::createChoice(
        "E_CHOICE_Falling", "Falling Mode", "Driving",
        {"Driving", "Falling", "Falling & Accumulating"}));

    params.push_back(EffectParameter::createInt(
        "E_SLIDER_Snowflakes_WarmupFrames", "Warmup Frames", 0, 0, 100));

    return params;
}

void SnowflakesEffect::initializeBuffer(int width, int height) {
    if (_state.width != width || _state.height != height) {
        _state.width = width;
        _state.height = height;
        _state.tempBuffer.clear();
        _state.tempBuffer.resize(width);
        for (int x = 0; x < width; x++) {
            _state.tempBuffer[x].resize(height);
            for (int y = 0; y < height; y++) {
                _state.tempBuffer[x][y].x = -1;  // Mark as empty
            }
        }
    }
}

void SnowflakesEffect::clearBufferPixel(int x, int y) {
    if (x >= 0 && x < _state.width && y >= 0 && y < _state.height) {
        _state.tempBuffer[x][y].x = -1;  // Mark as empty
    }
}

void SnowflakesEffect::setBufferPixel(int x, int y, const SnowflakeParticle& flake) {
    if (x >= 0 && x < _state.width && y >= 0 && y < _state.height) {
        _state.tempBuffer[x][y] = flake;
        _state.tempBuffer[x][y].x = x;
        _state.tempBuffer[x][y].y = y;
    }
}

bool SnowflakesEffect::getBufferPixel(int x, int y, SnowflakeParticle& flake) const {
    if (x >= 0 && x < _state.width && y >= 0 && y < _state.height) {
        if (_state.tempBuffer[x][y].x >= 0) {
            flake = _state.tempBuffer[x][y];
            return true;
        }
    }
    return false;
}

int SnowflakesEffect::possibleDownwardMoves(int x, int y) const {
    int moves = 0;

    if (y == 0) {
        return 0;  // No moves from bottom row
    }

    // Check down-left
    int checkX = (x - 1 < 0) ? x - 1 + _state.width : x - 1;
    if (_state.tempBuffer[checkX][y - 1].x < 0) {
        moves |= 1;
    }

    // Check down
    if (_state.tempBuffer[x][y - 1].x < 0) {
        moves |= 2;
    }

    // Check down-right
    checkX = (x + 1 >= _state.width) ? x + 1 - _state.width : x + 1;
    if (_state.tempBuffer[checkX][y - 1].x < 0) {
        moves |= 4;
    }

    return moves;
}

void SnowflakesEffect::moveFlakes(RenderContext& ctx, SnowflakeType type,
                                   SnowfallMode mode, int count,
                                   const Color& color1, std::mt19937& rng) {
    int starty = (mode == SnowfallMode::FallingAccumulating) ? 1 : 0;

    // Move flakes downward
    for (int x = 0; x < _state.width; x++) {
        for (int y = starty; y < _state.height; y++) {
            SnowflakeParticle flake;
            if (getBufferPixel(x, y, flake)) {
                int moves = possibleDownwardMoves(x, y);

                if (moves > 0 || (mode == SnowfallMode::Falling && y == 0)) {
                    int x0;
                    std::uniform_int_distribution<int> moveDist(0, 8);
                    int moveChoice = moveDist(rng);

                    switch (moveChoice) {
                        case 0:
                            if (moves & 1) x0 = x - 1;
                            else if (moves & 2) x0 = x;
                            else x0 = x + 1;
                            break;
                        case 1:
                            if (moves & 4) x0 = x + 1;
                            else if (moves & 2) x0 = x;
                            else x0 = x - 1;
                            break;
                        default:
                            if (moves & 2) x0 = x;
                            else if ((moves & 5) == 4) x0 = x + 1;
                            else if ((moves & 5) == 1) x0 = x - 1;
                            else {
                                std::uniform_int_distribution<int> coinFlip(0, 1);
                                x0 = coinFlip(rng) ? x + 1 : x - 1;
                            }
                            break;
                    }

                    // Wrap X coordinate
                    if (x0 < 0) x0 += _state.width;
                    else if (x0 >= _state.width) x0 -= _state.width;

                    int y0 = y - 1;

                    // Clear old position
                    clearBufferPixel(x, y);

                    if (y0 >= 0) {
                        // Move flake down
                        setBufferPixel(x0, y0, flake);

                        if (mode == SnowfallMode::FallingAccumulating) {
                            int nextMoves = possibleDownwardMoves(x0, y0);
                            if (nextMoves == 0) {
                                _state.effectState--;
                            }
                        }
                    } else {
                        _state.effectState--;
                    }
                }
            }
        }
    }

    // Add new flakes at top
    int check = 0;
    int placedFullCount = 0;
    std::uniform_int_distribution<int> xDist(0, _state.width - 1);
    std::uniform_int_distribution<int> typeDist(0, 8);

    while (_state.effectState < count && check < 20) {
        int x = xDist(rng);
        SnowflakeParticle existingFlake;
        if (!getBufferPixel(x, _state.height - 1, existingFlake)) {
            _state.effectState++;

            SnowflakeParticle newFlake;
            newFlake.x = x;
            newFlake.y = _state.height - 1;
            newFlake.type = (type == SnowflakeType::Random)
                ? intToSnowflakeType(typeDist(rng) + 1)
                : type;
            setBufferPixel(x, _state.height - 1, newFlake);

            int nextMoves = possibleDownwardMoves(x, _state.height - 1);
            if (nextMoves == 0) {
                placedFullCount++;
            }
        }
        check++;
    }
    _state.effectState -= placedFullCount;
}

void SnowflakesEffect::placeInitialFlakes(RenderContext& ctx, int count,
                                           SnowflakeType type, SnowfallMode mode,
                                           const Color& color1, std::mt19937& rng) {
    std::uniform_int_distribution<int> xDist(0, _state.width - 1);
    std::uniform_int_distribution<int> typeDist(0, 8);

    for (int n = 0; n < count; n++) {
        int deltaY = _state.height / 4;
        int y0 = (n % 4) * deltaY;

        if (y0 + deltaY > _state.height) deltaY = _state.height - y0;
        if (deltaY < 1) deltaY = 1;

        int x = 0;
        int y = 0;

        // Find unused space
        for (int check = 0; check < 20; check++) {
            x = xDist(rng);
            std::uniform_int_distribution<int> yDist(y0, y0 + deltaY - 1);
            y = yDist(rng);

            SnowflakeParticle existingFlake;
            if (!getBufferPixel(x, y, existingFlake)) {
                _state.effectState++;
                break;
            }
        }

        SnowflakeParticle newFlake;
        newFlake.x = x;
        newFlake.y = y;
        newFlake.type = (type == SnowflakeType::Random)
            ? intToSnowflakeType(typeDist(rng) + 1)
            : type;
        setBufferPixel(x, y, newFlake);
    }
}

void SnowflakesEffect::drawSnowflake(RenderContext& ctx, int x, int y,
                                      SnowflakeType type, const Color& color1,
                                      const Color& color2, bool wrapX) {
    auto setPixelSafe = [&](int px, int py, const Color& c) {
        int adjX = px;
        if (wrapX) {
            if (adjX < 0) adjX += ctx.width();
            else if (adjX >= ctx.width()) adjX -= ctx.width();
        }
        if (adjX >= 0 && adjX < ctx.width() && py >= 0 && py < ctx.height()) {
            ctx.setPixel(adjX, py, c);
        }
    };

    switch (type) {
        case SnowflakeType::SingleNode:
            setPixelSafe(x, y, color1);
            break;

        case SnowflakeType::Plus5:
            setPixelSafe(x, y, color1);
            setPixelSafe(x - 1, y, color2);
            setPixelSafe(x + 1, y, color2);
            setPixelSafe(x, y - 1, color2);
            setPixelSafe(x, y + 1, color2);
            break;

        case SnowflakeType::Plus3:
            setPixelSafe(x, y, color1);
            setPixelSafe(x - 1, y, color2);
            setPixelSafe(x + 1, y, color2);
            break;

        case SnowflakeType::Plus9:
            setPixelSafe(x, y, color1);
            for (int i = 1; i <= 2; i++) {
                setPixelSafe(x - i, y, color2);
                setPixelSafe(x + i, y, color2);
                setPixelSafe(x, y - i, color2);
                setPixelSafe(x, y + i, color2);
            }
            break;

        case SnowflakeType::Star13:
            setPixelSafe(x, y, color1);
            setPixelSafe(x - 1, y, color2);
            setPixelSafe(x + 1, y, color2);
            setPixelSafe(x, y - 1, color2);
            setPixelSafe(x, y + 1, color2);
            setPixelSafe(x - 1, y + 2, color2);
            setPixelSafe(x + 1, y + 2, color2);
            setPixelSafe(x - 1, y - 2, color2);
            setPixelSafe(x + 1, y - 2, color2);
            setPixelSafe(x + 2, y - 1, color2);
            setPixelSafe(x + 2, y + 1, color2);
            setPixelSafe(x - 2, y - 1, color2);
            setPixelSafe(x - 2, y + 1, color2);
            break;

        case SnowflakeType::Square4:
            setPixelSafe(x, y, color1);
            setPixelSafe(x + 1, y, color1);
            setPixelSafe(x + 1, y + 1, color1);
            setPixelSafe(x, y + 1, color1);
            break;

        case SnowflakeType::Cross5:
            setPixelSafe(x, y, color1);
            setPixelSafe(x + 1, y, color1);
            setPixelSafe(x, y + 1, color1);
            setPixelSafe(x - 1, y, color1);
            setPixelSafe(x, y - 1, color1);
            break;

        case SnowflakeType::Diamond13:
            setPixelSafe(x, y + 2, color1);
            setPixelSafe(x - 1, y + 1, color1);
            setPixelSafe(x, y + 1, color1);
            setPixelSafe(x + 1, y + 1, color1);
            setPixelSafe(x - 2, y, color1);
            setPixelSafe(x - 1, y, color1);
            setPixelSafe(x, y, color1);
            setPixelSafe(x + 1, y, color1);
            setPixelSafe(x + 2, y, color1);
            setPixelSafe(x - 1, y - 1, color1);
            setPixelSafe(x, y - 1, color1);
            setPixelSafe(x + 1, y - 1, color1);
            setPixelSafe(x, y - 2, color1);
            break;

        case SnowflakeType::X5:
            setPixelSafe(x, y, color1);
            setPixelSafe(x + 1, y + 1, color1);
            setPixelSafe(x - 1, y + 1, color1);
            setPixelSafe(x - 1, y - 1, color1);
            setPixelSafe(x + 1, y - 1, color1);
            break;

        default:
            setPixelSafe(x, y, color1);
            break;
    }
}

void SnowflakesEffect::renderDriving(RenderContext& ctx, int count, SnowflakeType type,
                                      int speed, const Color& color1, const Color& color2,
                                      const RenderState& state) {
    // For driving mode, we use direct rendering based on movement calculation
    int movement = state.frameIndex * speed * 50 / 50;  // Simplified timing

    std::mt19937 rng(state.randomSeed);

    // Use a persistent pattern based on position
    for (int x = 0; x < ctx.width(); x++) {
        int newX = (x + movement / 20) % ctx.width();
        int newX2 = (x - movement / 20);
        if (newX2 < 0) newX2 += ctx.width();
        newX2 = newX2 % ctx.width();

        for (int y = 0; y < ctx.height(); y++) {
            int newY = (y + movement / 10) % ctx.height();
            int newY2 = (newY + ctx.height() / 2) % ctx.height();

            // Check temp buffer for flake at transformed position
            SnowflakeParticle flake;
            bool hasFlake = false;

            if (getBufferPixel(newX, newY, flake)) {
                hasFlake = true;
            } else if (getBufferPixel(newX2, newY2, flake)) {
                hasFlake = true;
            }

            if (hasFlake) {
                drawSnowflake(ctx, x, y, flake.type, color1, color2, false);
            }
        }
    }
}

void SnowflakesEffect::renderFalling(RenderContext& ctx, int count, SnowflakeType type,
                                      int speed, SnowfallMode mode, const Color& color1,
                                      const Color& color2, int warmupFrames,
                                      std::mt19937& rng, const RenderState& state) {
    bool wrapX = false;  // Could be made configurable

    // Run warmup frames on first render
    if (state.frameIndex == 0 && warmupFrames > 0) {
        for (int i = 0; i < warmupFrames; i++) {
            if ((i * (speed + 1)) / 30 != ((i - 1) * (speed + 1)) / 30) {
                moveFlakes(ctx, type, mode, count, color1, rng);
            }
        }
    } else if (state.frameIndex > 0) {
        // Speed control - skip movement on some frames when slow
        if ((state.frameIndex * (speed + 1)) / 30 !=
            ((state.frameIndex - 1) * (speed + 1)) / 30) {
            moveFlakes(ctx, type, mode, count, color1, rng);
        }
    }

    // Render current state
    for (int x = 0; x < _state.width; x++) {
        for (int y = 0; y < _state.height; y++) {
            SnowflakeParticle flake;
            if (getBufferPixel(x, y, flake)) {
                drawSnowflake(ctx, x, y, flake.type, color1, color2, wrapX);
            }
        }
    }
}

void SnowflakesEffect::render(RenderContext& ctx, const EffectSettings& settings,
                               const RenderState& state) {
    // Get parameters
    int count = settings.getInt("E_SLIDER_Snowflakes_Count", 5);
    int typeInt = settings.getInt("E_SLIDER_Snowflakes_Type", 1);
    int speed = settings.getInt("E_SLIDER_Snowflakes_Speed", 10);
    int warmupFrames = settings.getInt("E_SLIDER_Snowflakes_WarmupFrames", 0);
    SnowfallMode mode = parseSnowfallMode(settings.get("E_CHOICE_Falling", "Driving"));
    SnowflakeType type = intToSnowflakeType(typeInt);

    // Get colors (use defaults if palette not available)
    Color color1(255, 255, 255);  // White
    Color color2(200, 200, 255);  // Light blue

    // Create deterministic RNG
    std::mt19937 rng(state.randomSeed + static_cast<uint32_t>(state.frameIndex));

    // Initialize buffer on first frame or parameter change
    bool needsInit = (state.frameIndex == 0) ||
                     (_state.width != ctx.width()) ||
                     (_state.height != ctx.height()) ||
                     (count != _state.lastCount && mode == SnowfallMode::Driving) ||
                     (typeInt != _state.lastType) ||
                     (settings.get("E_CHOICE_Falling", "Driving") != _state.lastMode);

    if (needsInit) {
        initializeBuffer(ctx.width(), ctx.height());
        _state.lastCount = count;
        _state.lastType = typeInt;
        _state.lastMode = settings.get("E_CHOICE_Falling", "Driving");
        _state.effectState = 0;

        // Clear buffer
        for (int x = 0; x < _state.width; x++) {
            for (int y = 0; y < _state.height; y++) {
                _state.tempBuffer[x][y].x = -1;
            }
        }

        // Place initial snowflakes
        placeInitialFlakes(ctx, count, type, mode, color1, rng);
    }

    // Render based on mode
    if (mode == SnowfallMode::Driving) {
        renderDriving(ctx, count, type, speed, color1, color2, state);
    } else {
        renderFalling(ctx, count, type, speed, mode, color1, color2, warmupFrames, rng, state);
    }
}

// Register effect with registry
XLCORE_REGISTER_EFFECT(SnowflakesEffect)

} // namespace xlCore
