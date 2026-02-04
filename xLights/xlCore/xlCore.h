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
 * @file xlCore.h
 * @brief Main header for the xlCore library.
 *
 * Include this header to get access to all xlCore types and utilities.
 * The xlCore library provides pure C++17/20 types that replace wxWidgets
 * equivalents for use in the rendering engine.
 *
 * Key components:
 * - Color: RGBA color with HSV/HSL conversions (replaces wxColour/xlColor)
 * - Vec2, Vec3: 2D/3D floating-point vectors
 * - Point2D: 2D integer point (replaces wxPoint)
 * - Rect, RectF: 2D rectangles (replaces wxRect)
 * - ImageBuffer: Raw pixel buffer (replaces wxImage in rendering)
 * - RenderContext: Effect rendering context (replaces RenderBuffer)
 * - StringUtils: String manipulation utilities (replaces wxString operations)
 * - Model: Abstract model class for lighting fixtures/props
 * - AudioPlayer: Platform-abstracted audio playback (replaces SDL/wx audio)
 * - AudioAnalyzer: Waveform and spectrum analysis
 * - OutputProtocol: Base class for output protocols (E1.31, ArtNet, DDP, DMX)
 * - OutputManager: Manages multiple outputs for coordinated frame transmission
 * - Sequence: Sequence data structures and serialization
 * - SequenceSerializer: Load/save .xLights and .fseq files
 * - Effect: Abstract base class for all effects
 * - EffectSettings: Thread-safe key-value store for effect parameters
 * - EffectRegistry: Factory/registry for effect types
 *
 * Design principles:
 * - Zero wxWidgets dependencies
 * - Thread-safe (individual instances, not shared)
 * - constexpr where practical
 * - Modern C++17/20 idioms
 */

#include "Types.h"
#include "Color.h"
#include "XLMath.h"
#include "ImageBuffer.h"
#include "RenderContext.h"
#include "StringUtils.h"
#include "Model.h"
#include "Audio.h"
#include "Output.h"
#include "Sequence.h"
#include "Effect.h"

// Media interfaces
#include "media/ImageLoader.h"
#include "media/VideoDecoder.h"

// Effects
#include "effects/PicturesEffect.h"
#include "effects/VideoEffect.h"
#include "effects/GlediatorEffect.h"
#include "effects/ShaderEffect.h"

namespace xlCore {

/**
 * @brief Library version information.
 */
constexpr int VERSION_MAJOR = 1;
constexpr int VERSION_MINOR = 0;
constexpr int VERSION_PATCH = 0;

/**
 * @brief Get library version string.
 */
inline std::string version() {
    return std::to_string(VERSION_MAJOR) + "." +
           std::to_string(VERSION_MINOR) + "." +
           std::to_string(VERSION_PATCH);
}

} // namespace xlCore
