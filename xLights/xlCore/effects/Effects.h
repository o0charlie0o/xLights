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
 * @file Effects.h
 * @brief Includes all xlCore effect headers.
 *
 * Include this header to access all ported effect types.
 * Effects are automatically registered via the XLCORE_REGISTER_EFFECT
 * macro when their .cpp files are linked.
 *
 * Utility Effects:
 * - OnEffect: Solid color fill
 * - OffEffect: Turn off or make transparent
 * - StateEffect: State machine for model states
 *
 * Pattern Effects:
 * - BarsEffect: Moving color bars
 * - ColorWashEffect: Blended palette fill
 * - FillEffect: Fill with direction
 * - GalaxyEffect: Spiral galaxy pattern
 * - KaleidoscopeEffect: Kaleidoscope mirror pattern
 * - PinwheelEffect: Rotating pinwheel
 * - PlasmaEffect: Plasma wave pattern
 * - ShimmerEffect: Cyclic color with duty factor
 * - SpirographEffect: Spirograph patterns
 * - StrobeEffect: Random flashing lights
 * - TwinkleEffect: Random twinkling lights
 * - WaveEffect: Moving wave pattern
 *
 * Particle/Physics Effects:
 * - CandleEffect: Flickering candle simulation
 * - FireworksEffect: Fireworks explosions
 * - MeteorsEffect: Falling meteor trails
 * - SnowflakesEffect: Falling snowflakes
 * - TendrilEffect: Organic tendrils
 *
 * Media/Audio Effects:
 * - AudioReactiveEffect: Base class for audio-reactive effects
 * - MusicEffect: General music reactive effect
 * - VideoEffect: Video playback
 * - VUMeterEffect: VU meter display
 *
 * Advanced Effects:
 * - FacesEffect: Lip sync and face mapping
 * - PicturesEffect: Image display and animation
 * - ShapeEffect: Geometric shapes
 * - TextEffect: Scrolling text
 */

// Utility effects
#include "OnEffect.h"
#include "OffEffect.h"
#include "StateEffect.h"

// Pattern effects
#include "BarsEffect.h"
#include "ColorWashEffect.h"
#include "FillEffect.h"
#include "GalaxyEffect.h"
#include "KaleidoscopeEffect.h"
#include "PinwheelEffect.h"
#include "PlasmaEffect.h"
#include "ShimmerEffect.h"
#include "SpirographEffect.h"
#include "StrobeEffect.h"
#include "TwinkleEffect.h"
#include "WaveEffect.h"

// Particle/Physics effects
#include "CandleEffect.h"
#include "FireworksEffect.h"
#include "MeteorsEffect.h"
#include "SnowflakesEffect.h"
#include "TendrilEffect.h"

// Media/Audio effects
#include "AudioReactiveEffect.h"
#include "MusicEffect.h"
#include "SpectrumEffect.h"
#include "VideoEffect.h"
#include "VUMeterEffect.h"
#include "WaveformEffect.h"

// Advanced effects
#include "FacesEffect.h"
#include "PicturesEffect.h"
#include "ShapeEffect.h"
#include "TextEffect.h"
