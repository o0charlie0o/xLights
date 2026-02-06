#pragma once

/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// NativeColorBlending: Pure C++ color blending extracted from PixelBuffer.
// Provides all 24 mix/blend modes used by the layer system, with zero
// wxWidgets dependencies. Thread-safe (no global mutable state).
//
// Part of the native render pipeline (Component 2).

#include <string>
#include <vector>
#include <map>

#include "../../Color.h"

/**
 * Enumeration of the different techniques used in layering effects.
 * Mirrors the MixTypes enum from PixelBuffer.h but lives in a wx-free header.
 */
enum class NativeMixType {
    Mix_Normal,            /** Layered with Alpha channel considered **/
    Mix_Effect1,           /**< Effect 1 only */
    Mix_Effect2,           /**< Effect 2 only */
    Mix_Mask1,             /**< Effect 2 color shows where Effect 1 is black */
    Mix_Mask2,             /**< Effect 1 color shows where Effect 2 is black */
    Mix_Unmask1,           /**< Effect 2 color shows where Effect 1 is not black but with no fade */
    Mix_Unmask2,           /**< Effect 1 color shows where Effect 2 is not black but with no fade */
    Mix_TrueUnmask1,       /**< Effect 2 color shows where Effect 1 is not black */
    Mix_TrueUnmask2,       /**< Effect 1 color shows where Effect 2 is black */
    Mix_1_reveals_2,       /**< Effect 2 color only shows if Effect 1 is black */
    Mix_2_reveals_1,       /**< Effect 1 color only shows if Effect 2 is black */
    Mix_Layered,           /**< Effect 1 is background and shows only when effect 2 is black */
    Mix_Average,           /**< Average color value between effects per pixel */
    Mix_BottomTop,
    Mix_LeftRight,
    Mix_Shadow_1on2,       /**< Take value and saturation from Effect 1 and put them onto effect 2 */
    Mix_Shadow_2on1,       /**< Take value and saturation from Effect 2 and put them onto effect 1 */
    Mix_Additive,
    Mix_Subtractive,
    Mix_AsBrightness,
    Mix_Max,
    Mix_Min,
    Mix_Highlight,
    Mix_Highlight_Vibrant
};

/**
 * Parameters needed by mixColors beyond the two pixel colors.
 * Bundles per-layer state that the original PixelBuffer member function
 * accessed through its LayerInfo pointer.
 */
struct MixColorParams {
    NativeMixType mixType = NativeMixType::Mix_Normal;
    float effectMixThreshold = 0.0f;
    bool effectMixVaries = false;
    float fadeFactor = 1.0f;
    bool allowAlpha = false;
    int bufferWi = 0;
    int bufferHt = 0;
    bool isChromaKey = false;
    xlColor chromaKeyColour = xlBLACK;
    int chromaSensitivity = 1;
};

namespace NativeColorBlending {

// ---- Mix type name/enum mapping ----

/// Return display names for all mix types, in UI order.
std::vector<std::string> getMixTypeNames();

/// Return a map of display name -> NativeMixType for lookup.
const std::map<std::string, NativeMixType>& getMixTypeMap();

/// Parse a display name string to a NativeMixType enum value.
/// Returns Mix_Effect1 if the name is not recognized (matches legacy behavior).
NativeMixType mixTypeFromName(const std::string& name);

/// Return the display name for a given NativeMixType.
std::string mixTypeName(NativeMixType type);

/// Returns true if the mix type uses alpha channel blending.
bool mixTypeHandlesAlpha(NativeMixType mt);

// ---- Core blending ----

/// Compute the perceptual distance between two colors.
/// Used by chroma key detection.
double colourDistance(xlColor e1, xlColor e2);

/**
 * Blend a foreground color onto a background color using the specified mix mode.
 *
 * Both fg and bg may be modified. After the call, bg contains the blended
 * result that becomes the background for the next layer blend.
 *
 * @param x         Pixel x coordinate (used by BottomTop/LeftRight modes)
 * @param y         Pixel y coordinate (used by BottomTop/LeftRight modes)
 * @param fg        Foreground (top layer) color - may be modified
 * @param bg        Background (bottom layer) color - receives blended result
 * @param params    Per-layer blending parameters
 */
void mixColors(int x, int y, xlColor& fg, xlColor& bg, const MixColorParams& params);

// ---- Color adjustment utilities ----

/**
 * Adjust a color's hue, saturation, and value.
 *
 * @param color     The color to adjust (modified in place)
 * @param hueAdj    Hue adjustment as fraction of full circle (-1.0 to 1.0)
 * @param satAdj    Saturation adjustment (-1.0 to 1.0)
 * @param valAdj    Value/brightness adjustment (-1.0 to 1.0)
 */
void adjustHSV(xlColor& color, float hueAdj, float satAdj, float valAdj);

/**
 * Scale a color's brightness.
 *
 * @param color      The color to adjust (modified in place)
 * @param brightness Brightness as percentage (0-100, where 100 = unchanged)
 */
void adjustBrightness(xlColor& color, int brightness);

/**
 * Apply brightness and contrast adjustment together.
 *
 * @param color      The color to adjust (modified in place)
 * @param brightness Brightness as percentage (0-100)
 * @param contrast   Contrast as percentage (-100 to 100, 0 = no change)
 */
void adjustBrightnessContrast(xlColor& color, int brightness, int contrast);

/**
 * Blend multiple layers of colors at a single pixel coordinate.
 *
 * Iterates through the layers from back to front, applying per-layer
 * HSV adjustment, brightness/contrast, and then mixing with the
 * accumulated result.
 *
 * @param x              Pixel x coordinate
 * @param y              Pixel y coordinate
 * @param layerColors    Color from each layer (index 0 = bottom layer)
 * @param layerParams    Mix parameters for each layer
 * @param validLayers    Which layers are active/valid
 * @param hueAdj         Per-layer hue adjustment (fraction, can be empty)
 * @param satAdj         Per-layer saturation adjustment (fraction, can be empty)
 * @param valAdj         Per-layer value adjustment (fraction, can be empty)
 * @param brightness     Per-layer brightness (0-100, can be empty for default 100)
 * @param contrast       Per-layer contrast (-100 to 100, can be empty for default 0)
 * @param fadeFactors    Per-layer fade factor (0.0-1.0, can be empty for default 1.0)
 * @return               The final blended color
 */
xlColor getMixedColor(int x, int y,
                      const std::vector<xlColor>& layerColors,
                      const std::vector<MixColorParams>& layerParams,
                      const std::vector<bool>& validLayers,
                      const std::vector<float>& hueAdj = {},
                      const std::vector<float>& satAdj = {},
                      const std::vector<float>& valAdj = {},
                      const std::vector<int>& brightness = {},
                      const std::vector<int>& contrast = {},
                      const std::vector<float>& fadeFactors = {});

} // namespace NativeColorBlending
