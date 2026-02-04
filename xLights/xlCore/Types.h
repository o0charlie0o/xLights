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
 * @file Types.h
 * @brief Core type definitions for the xlCore library.
 *
 * This header provides forward declarations and common type definitions
 * used throughout the xlCore library. All types are designed to be:
 * - Thread-safe
 * - Zero wxWidgets dependency
 * - Modern C++17/20 compatible
 */

#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>

namespace xlCore {

// Forward declarations
class Color;
struct Vec2;
struct Vec3;
struct Point2D;
struct Rect;
class ImageBuffer;
class RenderContext;

// Common type aliases
using ColorVector = std::vector<Color>;
using StringVector = std::vector<std::string>;

// Channel data type (matches existing xLights convention)
using ChannelValue = uint8_t;

// Time representation in milliseconds
using TimeMS = int64_t;

// Period/frame index
using FrameIndex = int32_t;

// Node/pixel index
using NodeIndex = uint32_t;

// Channel index
using ChannelIndex = uint32_t;

} // namespace xlCore
