/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// Effect Panel Definitions for Native macOS UI
// This file contains parameter definitions for all 65 xLights effects.
// Parameters are extracted from xLights/wxsmith/*Panel.wxs files.

#import "XLEffectPanelDefinitions.h"
#import <Foundation/Foundation.h>

// ============================================================================
// MARK: - Choice Lists (Constant String Arrays)
// ============================================================================

// Bars Direction choices
static const char * const kBarsDirectionChoices[] = {
    "up", "down", "expand", "compress", "Left", "Right",
    "H-expand", "H-compress", "Alternate Up", "Alternate Down",
    "Alternate Left", "Alternate Right", "Custom Horz", "Custom Vert", NULL
};

// Butterfly Colors choices
static const char * const kButterflyColorsChoices[] = {
    "Rainbow", "Palette", NULL
};

// Butterfly Direction choices
static const char * const kButterflyDirectionChoices[] = {
    "Normal", "Reverse", NULL
};

// Fire Location choices
static const char * const kFireLocationChoices[] = {
    "Bottom", "Top", "Left", "Right", NULL
};

// Circles Type choices
static const char * const kCirclesTypeChoices[] = {
    "Radial", "Radial 3D", "Concentric", "Concentric Plasma", NULL
};

// Curtain Edge choices
static const char * const kCurtainEdgeChoices[] = {
    "left", "center", "right", "bottom", "middle", "top", NULL
};

// Curtain Effect choices
static const char * const kCurtainEffectChoices[] = {
    "open", "close", "open then close", "close then open", NULL
};

// Fan Direction choices
static const char * const kFanDirectionChoices[] = {
    "Normal", "Reverse", NULL
};

// Fireworks Type choices
static const char * const kFireworksTypeChoices[] = {
    "Standard", "Spiral", "Bloom", "Exploding", NULL
};

// Fireworks Gravity choices
static const char * const kFireworksGravityChoices[] = {
    "Normal", "Down", "Up", "Left", "Right", NULL
};

// Galaxy Direction choices
static const char * const kGalaxyDirectionChoices[] = {
    "CW", "CCW", "Radial in", "Radial out", NULL
};

// Kaleidoscope Type choices
static const char * const kKaleidoscopeTypeChoices[] = {
    "2 Way Vertical", "2 Way Horizontal", "4 Way", "Diagonal", "8 Way", NULL
};

// Lightning Direction choices
static const char * const kLightningDirectionChoices[] = {
    "Down", "Up", "Left", "Right", NULL
};

// Liquid Effect choices
static const char * const kLiquidEffectChoices[] = {
    "Liquid Color", "Liquid Particles", "Grid Particles", NULL
};

// Liquid Direction choices
static const char * const kLiquidDirectionChoices[] = {
    "Off", "Right", "Left", "Up", "Down", NULL
};

// Marquee Direction choices
static const char * const kMarqueeDirectionChoices[] = {
    "Right", "Left", "Up", "Down", NULL
};

// Meteors Type choices
static const char * const kMeteorsTypeChoices[] = {
    "Falling", "Falling2", "Icicles", "Icicles Bkg", "Rain", "Explode", NULL
};

// Meteors Direction choices
static const char * const kMeteorsDirectionChoices[] = {
    "Down", "Up", "Left", "Right", NULL
};

// Morph Effect choices
static const char * const kMorphEffectChoices[] = {
    "Morph", "Wipe", "Dissolve", NULL
};

// Music Type choices
static const char * const kMusicTypeChoices[] = {
    "Morph", "Bounce", "Collide", "Separate", "On", "VU Meter", "VU Meter Inverse",
    "Level", "Level Pulse", "Level Shape", "Level Jump", "Level Bar", "Note On", NULL
};

// Music Scaling choices
static const char * const kMusicScalingChoices[] = {
    "None", "From Middle", "Individual", NULL
};

// Music Color choices
static const char * const kMusicColorChoices[] = {
    "Distinct", "Blend", "Gradient", "Notes", NULL
};

// Pictures Direction choices
static const char * const kPicturesDirectionChoices[] = {
    "none", "left", "right", "up", "down", "up-left", "down-left",
    "up-right", "down-right", "peekaboo", "peekaboo 180",
    "wiggle", "zoom in", "zoom out", NULL
};

// Pinwheel Style choices
static const char * const kPinwheelStyleChoices[] = {
    "New Render Method", "3D", "3D Inverted", "Pinwheel", "Star", "Fan", NULL
};

// Pinwheel Rotation choices
static const char * const kPinwheelRotationChoices[] = {
    "CW", "CCW", NULL
};

// Plasma Color choices
static const char * const kPlasmaColorChoices[] = {
    "Normal", "Preset 1", "Preset 2", "Preset 3", "Preset 4", NULL
};

// Plasma Algorithm choices
static const char * const kPlasmaAlgorithmChoices[] = {
    "Plasma 1", "Plasma 2", "Plasma 3", "Plasma 4", "Plasma 5", "Plasma 6", NULL
};

// Ripple Movement choices
static const char * const kRippleMovementChoices[] = {
    "None", "Explode", "Implode", "Explode and Implode", NULL
};

// Ripple Object choices
static const char * const kRippleObjectChoices[] = {
    "Circle", "Square", "Triangle", "Star", "Polygon", "Heart", "Tree", "Candy Cane",
    "Snowflake", "Crucifix", "Present", NULL
};

// Shape Object choices
static const char * const kShapeObjectChoices[] = {
    "Circle", "Square", "Triangle", "Star", "Pentagon", "Hexagon", "Octagon",
    "Heart", "Tree", "Candy Cane", "Snowflake", "Crucifix", "Present",
    "Emoji", "SVG", NULL
};

// Shimmer Cycle choices
static const char * const kShimmerCycleChoices[] = {
    "Collide", "On", "Off", "Bounce", NULL
};

// Shockwave Direction choices
static const char * const kShockwaveDirectionChoices[] = {
    "In", "Out", "Both", NULL
};

// SingleStrand Type choices
static const char * const kSingleStrandTypeChoices[] = {
    "Chase", "Skips", NULL
};

// SingleStrand Chase choices
static const char * const kSingleStrandChaseChoices[] = {
    "Left to Right", "Right to Left", "Bounce Left", "Bounce Right",
    "Dual Bounce", "From Middle", "To Middle", "Oscillate", NULL
};

// Snowflakes Type choices
static const char * const kSnowflakesTypeChoices[] = {
    "0", "1", "2", "3", "4", "5", "6", "7", "8", NULL
};

// Snowflakes Direction choices
static const char * const kSnowflakesDirectionChoices[] = {
    "Down", "Up", "Left", "Right", NULL
};

// Spirals Direction choices
static const char * const kSpiralsDirectionChoices[] = {
    "Up", "Down", NULL
};

// Spirograph Speed choices
static const char * const kSpirographAnimateChoices[] = {
    "None", "R", "r", "d", "D", NULL
};

// Strobe Type choices
static const char * const kStrobeTypeChoices[] = {
    "On", "Off", "Strobe", "Strobe 1", "Strobe 2", "Strobe 3", NULL
};

// Tendril Movement choices
static const char * const kTendrilMovementChoices[] = {
    "Random", "Vert", "Horiz", NULL
};

// Text Direction choices
static const char * const kTextDirectionChoices[] = {
    "none", "left", "right", "up", "down", "vector", "up-left", "down-left",
    "up-right", "down-right", "wavey", "word-flip", "left-right", "up-down", NULL
};

// Text Effect choices
static const char * const kTextEffectChoices[] = {
    "normal", "vert text down", "vert text up", "rotate down 45",
    "rotate down 90", "rotate up 45", "rotate up 90", NULL
};

// Text Count choices
static const char * const kTextCountChoices[] = {
    "none", "countdown", "stopwatch", "seconds", "to date/time", NULL
};

// Tree Type choices
static const char * const kTreeTypeChoices[] = {
    "Spiral", "Straight Down", "Left", "Right", "Alternate", NULL
};

// Twinkle Count choices
static const char * const kTwinkleCountChoices[] = {
    "2", "3", "5", "7", "10", "25", "50", "75", "100", "150", NULL
};

// Video Start choices
static const char * const kVideoStartChoices[] = {
    "normal", "offset", NULL
};

// Video Scaling choices
static const char * const kVideoScalingChoices[] = {
    "None", "Auto", "Exact", "Fit", "Scaled", "Centered", NULL
};

// VUMeter Type choices
static const char * const kVUMeterTypeChoices[] = {
    "Spectrogram", "Volume Bars", "Waveform", "Timing Events - Peak",
    "Timing Events - Jump", "Timing Events - Pulse", "Timing Events - Sweep",
    "On", "Pulse", "Intensity Wave", "Unused", "Level Bar", "Note Level Bar",
    "Note Level Pulse", "Level Pulse", "Level Shape", "Level Jump", "Level Color",
    "Level Random", "Level Note", "Level Note On", "Note On",
    "Dominant Freq", "Dominant Freq Color", "Spectrogram Peak",
    "Spectrogram Circle Line", "Spectrogram Line", NULL
};

// VUMeter Shape choices
static const char * const kVUMeterShapeChoices[] = {
    "Circle", "Diamond", "Square", "Star", "Tree", "Crucifix", "Present",
    "Candy Cane", "Snowflake", "Heart", "Emoji", NULL
};

// Warp Effect choices
static const char * const kWarpEffectChoices[] = {
    "water drops", "dissolve", "circle reveal", "banded swirl", "ripple",
    "sample on", "mirror", "copy", "wavy", "single water drop", "circular swirl", NULL
};

// Warp Treatment choices
static const char * const kWarpTreatmentChoices[] = {
    "constant", "in", "out", "in-out", "out-in", NULL
};

// Wave Type choices
static const char * const kWaveTypeChoices[] = {
    "Sine", "Triangle", "Square", "Circle", "Decaying Sine", "Fractal/Ivy", NULL
};

// Wave Direction choices
static const char * const kWaveDirectionChoices[] = {
    "Right to Left", "Left to Right", NULL
};

// Wave Fill choices
static const char * const kWaveFillChoices[] = {
    "Solid", "Outline", NULL
};


// ============================================================================
// MARK: - Effect Parameter Definitions
// ============================================================================

// --------------------------------------------------------------------------
// Off Effect (no parameters)
// --------------------------------------------------------------------------
static const XLParameterDef kOffParameters[] = {
    XL_PARAM_END
};

static const char * const kOffGroups[] = { NULL };

// --------------------------------------------------------------------------
// On Effect
// --------------------------------------------------------------------------
static const XLParameterDef kOnParameters[] = {
    XL_PARAM_INT_VC("E_TEXTCTRL_Eff_On_Start", "Start Intensity", "Intensity",
                    0, 255, 255, "E_VALUECURVE_Eff_On_Start"),
    XL_PARAM_INT_VC("E_TEXTCTRL_Eff_On_End", "End Intensity", "Intensity",
                    0, 255, 255, "E_VALUECURVE_Eff_On_End"),
    XL_PARAM_BOOL("E_CHECKBOX_On_Shimmer", "Shimmer", "Options", 0),
    XL_PARAM_INT_VC("E_TEXTCTRL_On_Cycles", "Cycles", "Options",
                    0, 100, 1, "E_VALUECURVE_On_Cycles"),
    XL_PARAM_END
};

static const char * const kOnGroups[] = { "Intensity", "Options", NULL };

// --------------------------------------------------------------------------
// Adjust Effect
// --------------------------------------------------------------------------
static const XLParameterDef kAdjustParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Adjust_Brightness", "Brightness", "Adjustments",
                    0, 400, 100, "E_VALUECURVE_Adjust_Brightness"),
    XL_PARAM_INT_VC("E_SLIDER_Adjust_Contrast", "Contrast", "Adjustments",
                    -100, 100, 0, "E_VALUECURVE_Adjust_Contrast"),
    XL_PARAM_INT_VC("E_SLIDER_Adjust_Saturation", "Saturation", "Adjustments",
                    0, 200, 100, "E_VALUECURVE_Adjust_Saturation"),
    XL_PARAM_INT_VC("E_SLIDER_Adjust_Hue", "Hue", "Adjustments",
                    -100, 100, 0, "E_VALUECURVE_Adjust_Hue"),
    XL_PARAM_INT_VC("E_SLIDER_Adjust_Value", "Value", "Adjustments",
                    0, 200, 100, "E_VALUECURVE_Adjust_Value"),
    XL_PARAM_END
};

static const char * const kAdjustGroups[] = { "Adjustments", NULL };

// --------------------------------------------------------------------------
// Bars Effect
// --------------------------------------------------------------------------
static const XLParameterDef kBarsParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Bars_BarCount", "Palette Rep", "Basic",
                    1, 50, 1, "E_VALUECURVE_Bars_BarCount"),
    XL_PARAM_FLOAT_VC("E_SLIDER_Bars_Cycles", "Cycles", "Basic",
                      0, 500, 10, 10, "E_VALUECURVE_Bars_Cycles"),
    XL_PARAM_CHOICE("E_CHOICE_Bars_Direction", "Direction", "Basic",
                    kBarsDirectionChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Bars_Center", "Center Point", "Basic",
                    -100, 100, 0, "E_VALUECURVE_Bars_Center"),
    XL_PARAM_BOOL("E_CHECKBOX_Bars_Highlight", "Highlight", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Bars_UseFirstColorForHighlight", "Use First Color for Highlight", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Bars_3D", "3D", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Bars_Gradient", "Gradient", "Options", 0),
    XL_PARAM_END
};

static const char * const kBarsGroups[] = { "Basic", "Options", NULL };

// --------------------------------------------------------------------------
// Butterfly Effect
// --------------------------------------------------------------------------
static const XLParameterDef kButterflyParameters[] = {
    XL_PARAM_CHOICE("E_CHOICE_Butterfly_Colors", "Colors", "Basic",
                    kButterflyColorsChoices, 0),
    XL_PARAM_INT("E_SLIDER_Butterfly_Style", "Style", "Basic", 1, 10, 1),
    XL_PARAM_INT_VC("E_SLIDER_Butterfly_Chunks", "Bkgrd Chunks", "Basic",
                    1, 10, 1, "E_VALUECURVE_Butterfly_Chunks"),
    XL_PARAM_INT_VC("E_SLIDER_Butterfly_Skip", "Bkgrd Skip", "Basic",
                    2, 10, 2, "E_VALUECURVE_Butterfly_Skip"),
    XL_PARAM_INT_VC("E_SLIDER_Butterfly_Speed", "Speed", "Basic",
                    0, 100, 10, "E_VALUECURVE_Butterfly_Speed"),
    XL_PARAM_CHOICE("E_CHOICE_Butterfly_Direction", "Direction", "Basic",
                    kButterflyDirectionChoices, 0),
    XL_PARAM_END
};

static const char * const kButterflyGroups[] = { "Basic", NULL };

// --------------------------------------------------------------------------
// Candle Effect
// --------------------------------------------------------------------------
static const XLParameterDef kCandleParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Candle_FlameAgility", "Flame Agility", "Basic",
                    1, 10, 2, "E_VALUECURVE_Candle_FlameAgility"),
    XL_PARAM_INT_VC("E_SLIDER_Candle_WindBaseline", "Wind Baseline", "Wind",
                    0, 255, 30, "E_VALUECURVE_Candle_WindBaseline"),
    XL_PARAM_INT_VC("E_SLIDER_Candle_WindVariability", "Wind Variability", "Wind",
                    0, 10, 5, "E_VALUECURVE_Candle_WindVariability"),
    XL_PARAM_INT_VC("E_SLIDER_Candle_WindCalmness", "Wind Calmness", "Wind",
                    0, 10, 2, "E_VALUECURVE_Candle_WindCalmness"),
    XL_PARAM_BOOL("E_CHECKBOX_PerNode", "Per Node", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_UsePalette", "Use Palette", "Options", 0),
    XL_PARAM_END
};

static const char * const kCandleGroups[] = { "Basic", "Wind", "Options", NULL };

// --------------------------------------------------------------------------
// Circles Effect
// --------------------------------------------------------------------------
static const XLParameterDef kCirclesParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Circles_Count", "Number of Circles", "Basic",
                    1, 10, 3, "E_VALUECURVE_Circles_Count"),
    XL_PARAM_INT_VC("E_SLIDER_Circles_Size", "Size", "Basic",
                    1, 100, 5, "E_VALUECURVE_Circles_Size"),
    XL_PARAM_INT_VC("E_SLIDER_Circles_Speed", "Speed", "Basic",
                    1, 100, 10, "E_VALUECURVE_Circles_Speed"),
    XL_PARAM_CHOICE("E_CHOICE_Circles_Type", "Type", "Basic",
                    kCirclesTypeChoices, 0),
    XL_PARAM_BOOL("E_CHECKBOX_Circles_Bounce", "Bounce", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Circles_Collide", "Collide", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Circles_Random_Motion", "Random Motion", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Circles_Radial", "Radial", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Circles_Plasma", "Plasma", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Circles_Bubbles", "Bubbles", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Circles_Linear_Fade", "Linear Fade", "Options", 0),
    XL_PARAM_END
};

static const char * const kCirclesGroups[] = { "Basic", "Options", NULL };

// --------------------------------------------------------------------------
// ColorWash Effect
// --------------------------------------------------------------------------
static const XLParameterDef kColorWashParameters[] = {
    XL_PARAM_FLOAT_VC("E_SLIDER_ColorWash_Cycles", "Count", "Basic",
                      1, 200, 10, 10, "E_VALUECURVE_ColorWash_Cycles"),
    XL_PARAM_BOOL("E_CHECKBOX_ColorWash_VFade", "Vertical Fade", "Fades", 0),
    XL_PARAM_BOOL("E_CHECKBOX_ColorWash_HFade", "Horizontal Fade", "Fades", 0),
    XL_PARAM_BOOL("E_CHECKBOX_ColorWash_ReverseFades", "Reverse Fades", "Fades", 0),
    XL_PARAM_BOOL("E_CHECKBOX_ColorWash_Shimmer", "Shimmer", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_ColorWash_CircularPalette", "Circular Palette", "Options", 0),
    XL_PARAM_END
};

static const char * const kColorWashGroups[] = { "Basic", "Fades", "Options", NULL };

// --------------------------------------------------------------------------
// Curtain Effect
// --------------------------------------------------------------------------
static const XLParameterDef kCurtainParameters[] = {
    XL_PARAM_CHOICE("E_CHOICE_Curtain_Edge", "Edge", "Basic",
                    kCurtainEdgeChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Curtain_Effect", "Effect", "Basic",
                    kCurtainEffectChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Curtain_Swag", "Swag", "Basic",
                    0, 10, 3, "E_VALUECURVE_Curtain_Swag"),
    XL_PARAM_FLOAT_VC("E_SLIDER_Curtain_Speed", "Speed", "Basic",
                      0, 100, 10, 10, "E_VALUECURVE_Curtain_Speed"),
    XL_PARAM_BOOL("E_CHECKBOX_Curtain_Repeat", "Repeat", "Options", 0),
    XL_PARAM_END
};

static const char * const kCurtainGroups[] = { "Basic", "Options", NULL };

// --------------------------------------------------------------------------
// DMX Effect (Complex - needs custom panel)
// --------------------------------------------------------------------------
static const XLParameterDef kDMXParameters[] = {
    // DMX has 36 channel sliders (DMX1-DMX36) with value curves and invert checkboxes
    // This is handled specially due to the number of controls
    XL_PARAM_INT_VC("E_SLIDER_DMX1", "Channel 1", "Channels 1-12", 0, 255, 0, "E_VALUECURVE_DMX1"),
    XL_PARAM_BOOL("E_CHECKBOX_INVDMX1", "Invert 1", "Channels 1-12", 0),
    XL_PARAM_INT_VC("E_SLIDER_DMX2", "Channel 2", "Channels 1-12", 0, 255, 0, "E_VALUECURVE_DMX2"),
    XL_PARAM_BOOL("E_CHECKBOX_INVDMX2", "Invert 2", "Channels 1-12", 0),
    XL_PARAM_INT_VC("E_SLIDER_DMX3", "Channel 3", "Channels 1-12", 0, 255, 0, "E_VALUECURVE_DMX3"),
    XL_PARAM_BOOL("E_CHECKBOX_INVDMX3", "Invert 3", "Channels 1-12", 0),
    XL_PARAM_INT_VC("E_SLIDER_DMX4", "Channel 4", "Channels 1-12", 0, 255, 0, "E_VALUECURVE_DMX4"),
    XL_PARAM_BOOL("E_CHECKBOX_INVDMX4", "Invert 4", "Channels 1-12", 0),
    XL_PARAM_INT_VC("E_SLIDER_DMX5", "Channel 5", "Channels 1-12", 0, 255, 0, "E_VALUECURVE_DMX5"),
    XL_PARAM_BOOL("E_CHECKBOX_INVDMX5", "Invert 5", "Channels 1-12", 0),
    XL_PARAM_INT_VC("E_SLIDER_DMX6", "Channel 6", "Channels 1-12", 0, 255, 0, "E_VALUECURVE_DMX6"),
    XL_PARAM_BOOL("E_CHECKBOX_INVDMX6", "Invert 6", "Channels 1-12", 0),
    XL_PARAM_INT_VC("E_SLIDER_DMX7", "Channel 7", "Channels 1-12", 0, 255, 0, "E_VALUECURVE_DMX7"),
    XL_PARAM_BOOL("E_CHECKBOX_INVDMX7", "Invert 7", "Channels 1-12", 0),
    XL_PARAM_INT_VC("E_SLIDER_DMX8", "Channel 8", "Channels 1-12", 0, 255, 0, "E_VALUECURVE_DMX8"),
    XL_PARAM_BOOL("E_CHECKBOX_INVDMX8", "Invert 8", "Channels 1-12", 0),
    XL_PARAM_INT_VC("E_SLIDER_DMX9", "Channel 9", "Channels 1-12", 0, 255, 0, "E_VALUECURVE_DMX9"),
    XL_PARAM_BOOL("E_CHECKBOX_INVDMX9", "Invert 9", "Channels 1-12", 0),
    XL_PARAM_INT_VC("E_SLIDER_DMX10", "Channel 10", "Channels 1-12", 0, 255, 0, "E_VALUECURVE_DMX10"),
    XL_PARAM_BOOL("E_CHECKBOX_INVDMX10", "Invert 10", "Channels 1-12", 0),
    XL_PARAM_INT_VC("E_SLIDER_DMX11", "Channel 11", "Channels 1-12", 0, 255, 0, "E_VALUECURVE_DMX11"),
    XL_PARAM_BOOL("E_CHECKBOX_INVDMX11", "Invert 11", "Channels 1-12", 0),
    XL_PARAM_INT_VC("E_SLIDER_DMX12", "Channel 12", "Channels 1-12", 0, 255, 0, "E_VALUECURVE_DMX12"),
    XL_PARAM_BOOL("E_CHECKBOX_INVDMX12", "Invert 12", "Channels 1-12", 0),
    // Additional channels 13-36 would be in separate groups
    XL_PARAM_END
};

static const char * const kDMXGroups[] = { "Channels 1-12", "Channels 13-24", "Channels 25-36", NULL };

// --------------------------------------------------------------------------
// Faces Effect (Complex - needs custom panel for phoneme mapping)
// --------------------------------------------------------------------------
static const XLParameterDef kFacesParameters[] = {
    XL_PARAM_STRING("E_TEXTCTRL_Faces_Phoneme", "Phoneme", "Mapping", ""),
    XL_PARAM_STRING("E_CHOICE_Faces_FaceDefinition", "Face Definition", "Mapping", ""),
    XL_PARAM_BOOL("E_CHECKBOX_Faces_Outline", "Outline", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Faces_SuppressShimmer", "Suppress Shimmer When Talking", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Faces_TransparentBlack", "Transparent Black", "Options", 0),
    XL_PARAM_INT_VC("E_SLIDER_Faces_TransparentBlackLevel", "Transparency Level", "Options",
                    0, 255, 0, "E_VALUECURVE_Faces_TransparentBlackLevel"),
    XL_PARAM_END
};

static const char * const kFacesGroups[] = { "Mapping", "Options", NULL };

// --------------------------------------------------------------------------
// Fan Effect
// --------------------------------------------------------------------------
static const XLParameterDef kFanParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Fan_Start_Angle", "Start Angle", "Angles",
                    0, 360, 0, "E_VALUECURVE_Fan_Start_Angle"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_End_Angle", "End Angle", "Angles",
                    0, 360, 360, "E_VALUECURVE_Fan_End_Angle"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_CenterX", "Center X", "Position",
                    -100, 200, 50, "E_VALUECURVE_Fan_CenterX"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_CenterY", "Center Y", "Position",
                    -100, 200, 50, "E_VALUECURVE_Fan_CenterY"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_Start_Radius", "Start Radius", "Radius",
                    0, 500, 1, "E_VALUECURVE_Fan_Start_Radius"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_End_Radius", "End Radius", "Radius",
                    0, 500, 100, "E_VALUECURVE_Fan_End_Radius"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_Revolutions", "Revolutions", "Motion",
                    0, 3600, 720, "E_VALUECURVE_Fan_Revolutions"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_Num_Blades", "Num Blades", "Blades",
                    1, 16, 3, "E_VALUECURVE_Fan_Num_Blades"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_Blade_Width", "Blade Width", "Blades",
                    5, 100, 50, "E_VALUECURVE_Fan_Blade_Width"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_Blade_Angle", "Blade Angle", "Blades",
                    -360, 360, 90, "E_VALUECURVE_Fan_Blade_Angle"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_Num_Elements", "Num Elements", "Elements",
                    1, 4, 1, "E_VALUECURVE_Fan_Num_Elements"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_Element_Width", "Element Width", "Elements",
                    5, 100, 100, "E_VALUECURVE_Fan_Element_Width"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_Duration", "Duration", "Timing",
                    0, 100, 80, "E_VALUECURVE_Fan_Duration"),
    XL_PARAM_INT_VC("E_SLIDER_Fan_Accel", "Acceleration", "Timing",
                    -10, 10, 0, "E_VALUECURVE_Fan_Accel"),
    XL_PARAM_BOOL("E_CHECKBOX_Fan_Reverse", "Reverse", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Fan_Blend_Edges", "Blend Edges", "Options", 0),
    XL_PARAM_END
};

static const char * const kFanGroups[] = { "Angles", "Position", "Radius", "Motion", "Blades", "Elements", "Timing", "Options", NULL };

// --------------------------------------------------------------------------
// Fill Effect
// --------------------------------------------------------------------------
static const XLParameterDef kFillParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Fill_Position", "Position", "Basic",
                    0, 100, 100, "E_VALUECURVE_Fill_Position"),
    XL_PARAM_INT_VC("E_SLIDER_Fill_Band_Size", "Band Size", "Basic",
                    0, 250, 0, "E_VALUECURVE_Fill_Band_Size"),
    XL_PARAM_INT_VC("E_SLIDER_Fill_Offset", "Offset", "Basic",
                    0, 100, 0, "E_VALUECURVE_Fill_Offset"),
    XL_PARAM_BOOL("E_CHECKBOX_Fill_Wrap", "Wrap", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Fill_Color_Time", "Color Changes Over Time", "Options", 0),
    XL_PARAM_END
};

static const char * const kFillGroups[] = { "Basic", "Options", NULL };

// --------------------------------------------------------------------------
// Fire Effect
// --------------------------------------------------------------------------
static const XLParameterDef kFireParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Fire_Height", "Height", "Basic",
                    1, 100, 50, "E_VALUECURVE_Fire_Height"),
    XL_PARAM_INT_VC("E_SLIDER_Fire_HueShift", "Hue Shift", "Basic",
                    0, 100, 0, "E_VALUECURVE_Fire_HueShift"),
    XL_PARAM_FLOAT_VC("E_SLIDER_Fire_GrowthCycles", "Growth Cycles", "Basic",
                      0, 200, 0, 10, "E_VALUECURVE_Fire_GrowthCycles"),
    XL_PARAM_BOOL("E_CHECKBOX_Fire_GrowWithMusic", "Grow with Music", "Music", 0),
    XL_PARAM_CHOICE("E_CHOICE_Fire_Location", "Location", "Position",
                    kFireLocationChoices, 0),
    XL_PARAM_END
};

static const char * const kFireGroups[] = { "Basic", "Music", "Position", NULL };

// --------------------------------------------------------------------------
// Fireworks Effect
// --------------------------------------------------------------------------
static const XLParameterDef kFireworksParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Fireworks_Count", "Number of Explosions", "Basic",
                    1, 100, 10, "E_VALUECURVE_Fireworks_Count"),
    XL_PARAM_INT_VC("E_SLIDER_Fireworks_Velocity", "Velocity", "Basic",
                    1, 10, 2, "E_VALUECURVE_Fireworks_Velocity"),
    XL_PARAM_INT_VC("E_SLIDER_Fireworks_Particles", "Number of Particles", "Basic",
                    1, 100, 25, "E_VALUECURVE_Fireworks_Particles"),
    XL_PARAM_INT_VC("E_SLIDER_Fireworks_Fade", "Fade", "Basic",
                    1, 100, 50, "E_VALUECURVE_Fireworks_Fade"),
    XL_PARAM_CHOICE("E_CHOICE_Fireworks_Type", "Type", "Basic",
                    kFireworksTypeChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Fireworks_XLocation", "X Location", "Position",
                    -100, 100, 0, "E_VALUECURVE_Fireworks_XLocation"),
    XL_PARAM_INT_VC("E_SLIDER_Fireworks_YLocation", "Y Location", "Position",
                    -100, 100, 0, "E_VALUECURVE_Fireworks_YLocation"),
    XL_PARAM_BOOL("E_CHECKBOX_Fireworks_UseMusic", "Fire with Music", "Music", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Fireworks_Fade", "Gravity", "Options", 1),
    XL_PARAM_BOOL("E_CHECKBOX_Fireworks_HoldColour", "Hold Color", "Options", 1),
    XL_PARAM_END
};

static const char * const kFireworksGroups[] = { "Basic", "Position", "Music", "Options", NULL };

// --------------------------------------------------------------------------
// Galaxy Effect
// --------------------------------------------------------------------------
static const XLParameterDef kGalaxyParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Galaxy_CenterX", "Center X", "Position",
                    0, 100, 50, "E_VALUECURVE_Galaxy_CenterX"),
    XL_PARAM_INT_VC("E_SLIDER_Galaxy_CenterY", "Center Y", "Position",
                    0, 100, 50, "E_VALUECURVE_Galaxy_CenterY"),
    XL_PARAM_INT_VC("E_SLIDER_Galaxy_Start_Radius", "Start Radius", "Radius",
                    0, 250, 1, "E_VALUECURVE_Galaxy_Start_Radius"),
    XL_PARAM_INT_VC("E_SLIDER_Galaxy_End_Radius", "End Radius", "Radius",
                    0, 250, 10, "E_VALUECURVE_Galaxy_End_Radius"),
    XL_PARAM_INT_VC("E_SLIDER_Galaxy_Start_Width", "Start Width", "Width",
                    0, 255, 5, "E_VALUECURVE_Galaxy_Start_Width"),
    XL_PARAM_INT_VC("E_SLIDER_Galaxy_End_Width", "End Width", "Width",
                    0, 255, 5, "E_VALUECURVE_Galaxy_End_Width"),
    XL_PARAM_INT_VC("E_SLIDER_Galaxy_Start_Angle", "Start Angle", "Angles",
                    0, 360, 0, "E_VALUECURVE_Galaxy_Start_Angle"),
    XL_PARAM_INT_VC("E_SLIDER_Galaxy_Revolutions", "Revolutions", "Motion",
                    0, 3600, 720, "E_VALUECURVE_Galaxy_Revolutions"),
    XL_PARAM_INT_VC("E_SLIDER_Galaxy_Num_Arms", "Num Arms", "Arms",
                    1, 5, 1, "E_VALUECURVE_Galaxy_Num_Arms"),
    XL_PARAM_INT_VC("E_SLIDER_Galaxy_Duration", "Duration", "Timing",
                    0, 100, 20, "E_VALUECURVE_Galaxy_Duration"),
    XL_PARAM_INT_VC("E_SLIDER_Galaxy_Accel", "Acceleration", "Timing",
                    -10, 10, 0, "E_VALUECURVE_Galaxy_Accel"),
    XL_PARAM_CHOICE("E_CHOICE_Galaxy_Direction", "Direction", "Motion",
                    kGalaxyDirectionChoices, 0),
    XL_PARAM_BOOL("E_CHECKBOX_Galaxy_Blend_Edges", "Blend Edges", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Galaxy_Reverse", "Reverse", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Galaxy_Inward", "Inward", "Options", 0),
    XL_PARAM_END
};

static const char * const kGalaxyGroups[] = { "Position", "Radius", "Width", "Angles", "Motion", "Arms", "Timing", "Options", NULL };

// --------------------------------------------------------------------------
// Garlands Effect
// --------------------------------------------------------------------------
static const XLParameterDef kGarlandsParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Garlands_Type", "Type", "Basic",
                    0, 4, 0, "E_VALUECURVE_Garlands_Type"),
    XL_PARAM_INT_VC("E_SLIDER_Garlands_Spacing", "Spacing", "Basic",
                    1, 100, 10, "E_VALUECURVE_Garlands_Spacing"),
    XL_PARAM_FLOAT_VC("E_SLIDER_Garlands_Cycles", "Cycles", "Basic",
                      0, 200, 10, 10, "E_VALUECURVE_Garlands_Cycles"),
    XL_PARAM_CHOICE("E_CHOICE_Garlands_Direction", "Direction", "Basic",
                    kSpiralsDirectionChoices, 0),
    XL_PARAM_END
};

static const char * const kGarlandsGroups[] = { "Basic", NULL };

// --------------------------------------------------------------------------
// Glediator Effect
// --------------------------------------------------------------------------
static const XLParameterDef kGlediatorParameters[] = {
    XL_PARAM_FILE("E_FILEPICKERCTRL_Glediator_Filename", "Filename", "Basic", "gled"),
    XL_PARAM_END
};

static const char * const kGlediatorGroups[] = { "Basic", NULL };

// --------------------------------------------------------------------------
// Kaleidoscope Effect
// --------------------------------------------------------------------------
static const XLParameterDef kKaleidoscopeParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Kaleidoscope_X", "X", "Position",
                    0, 100, 50, "E_VALUECURVE_Kaleidoscope_X"),
    XL_PARAM_INT_VC("E_SLIDER_Kaleidoscope_Y", "Y", "Position",
                    0, 100, 50, "E_VALUECURVE_Kaleidoscope_Y"),
    XL_PARAM_INT_VC("E_SLIDER_Kaleidoscope_Size", "Size", "Basic",
                    0, 100, 50, "E_VALUECURVE_Kaleidoscope_Size"),
    XL_PARAM_INT_VC("E_SLIDER_Kaleidoscope_Rotation", "Rotation", "Basic",
                    0, 359, 0, "E_VALUECURVE_Kaleidoscope_Rotation"),
    XL_PARAM_CHOICE("E_CHOICE_Kaleidoscope_Type", "Type", "Basic",
                    kKaleidoscopeTypeChoices, 0),
    XL_PARAM_END
};

static const char * const kKaleidoscopeGroups[] = { "Position", "Basic", NULL };

// --------------------------------------------------------------------------
// Life Effect
// --------------------------------------------------------------------------
static const XLParameterDef kLifeParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Life_Count", "Cells to Start", "Basic",
                    0, 100, 50, "E_VALUECURVE_Life_Count"),
    XL_PARAM_INT_VC("E_SLIDER_Life_Seed", "Seed", "Basic",
                    0, 100, 0, "E_VALUECURVE_Life_Seed"),
    XL_PARAM_INT_VC("E_SLIDER_Life_Speed", "Speed", "Basic",
                    1, 30, 10, "E_VALUECURVE_Life_Speed"),
    XL_PARAM_END
};

static const char * const kLifeGroups[] = { "Basic", NULL };

// --------------------------------------------------------------------------
// Lightning Effect
// --------------------------------------------------------------------------
static const XLParameterDef kLightningParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Lightning_Number_Bolts", "Number of Bolts", "Basic",
                    1, 50, 10, "E_VALUECURVE_Lightning_Number_Bolts"),
    XL_PARAM_INT_VC("E_SLIDER_Lightning_Number_Segments", "Number of Segments", "Basic",
                    1, 20, 5, "E_VALUECURVE_Lightning_Number_Segments"),
    XL_PARAM_INT_VC("E_SLIDER_Lightning_TopX", "Top X", "Position",
                    0, 100, 0, "E_VALUECURVE_Lightning_TopX"),
    XL_PARAM_INT_VC("E_SLIDER_Lightning_TopY", "Top Y", "Position",
                    0, 100, 100, "E_VALUECURVE_Lightning_TopY"),
    XL_PARAM_INT_VC("E_SLIDER_Lightning_BOTX", "Bot X", "Position",
                    0, 100, 100, "E_VALUECURVE_Lightning_BOTX"),
    XL_PARAM_INT_VC("E_SLIDER_Lightning_BOTY", "Bot Y", "Position",
                    0, 100, 0, "E_VALUECURVE_Lightning_BOTY"),
    XL_PARAM_CHOICE("E_CHOICE_Lightning_Direction", "Direction", "Basic",
                    kLightningDirectionChoices, 0),
    XL_PARAM_BOOL("E_CHECKBOX_Lightning_UseMusic", "Trigger with Music", "Music", 0),
    XL_PARAM_END
};

static const char * const kLightningGroups[] = { "Basic", "Position", "Music", NULL };

// --------------------------------------------------------------------------
// Lines Effect
// --------------------------------------------------------------------------
static const XLParameterDef kLinesParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Lines_Thickness", "Thickness", "Basic",
                    1, 10, 1, "E_VALUECURVE_Lines_Thickness"),
    XL_PARAM_INT_VC("E_SLIDER_Lines_Speed", "Speed", "Basic",
                    1, 100, 10, "E_VALUECURVE_Lines_Speed"),
    XL_PARAM_BOOL("E_CHECKBOX_Lines_Trail", "Trail", "Options", 0),
    XL_PARAM_END
};

static const char * const kLinesGroups[] = { "Basic", "Options", NULL };

// --------------------------------------------------------------------------
// Liquid Effect
// --------------------------------------------------------------------------
static const XLParameterDef kLiquidParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Liquid_TopBarrier", "Top Barrier", "Barriers",
                    0, 100, 0, "E_VALUECURVE_Liquid_TopBarrier"),
    XL_PARAM_INT_VC("E_SLIDER_Liquid_BottomBarrier", "Bottom Barrier", "Barriers",
                    0, 100, 0, "E_VALUECURVE_Liquid_BottomBarrier"),
    XL_PARAM_INT_VC("E_SLIDER_Liquid_LeftBarrier", "Left Barrier", "Barriers",
                    0, 100, 0, "E_VALUECURVE_Liquid_LeftBarrier"),
    XL_PARAM_INT_VC("E_SLIDER_Liquid_RightBarrier", "Right Barrier", "Barriers",
                    0, 100, 0, "E_VALUECURVE_Liquid_RightBarrier"),
    XL_PARAM_CHOICE("E_CHOICE_Liquid_Effect", "Effect", "Basic",
                    kLiquidEffectChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Liquid_X1", "X1", "Position 1",
                    0, 100, 50, "E_VALUECURVE_Liquid_X1"),
    XL_PARAM_INT_VC("E_SLIDER_Liquid_Y1", "Y1", "Position 1",
                    0, 100, 90, "E_VALUECURVE_Liquid_Y1"),
    XL_PARAM_CHOICE("E_CHOICE_Liquid_Direction1", "Direction 1", "Position 1",
                    kLiquidDirectionChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Liquid_Lifetime", "Lifetime", "Particles",
                    1, 100, 100, "E_VALUECURVE_Liquid_Lifetime"),
    XL_PARAM_INT_VC("E_SLIDER_Liquid_Size", "Size", "Particles",
                    1, 100, 25, "E_VALUECURVE_Liquid_Size"),
    XL_PARAM_INT_VC("E_SLIDER_Liquid_WarmUpFrames", "Warm Up Frames", "Particles",
                    0, 500, 0, "E_VALUECURVE_Liquid_WarmUpFrames"),
    XL_PARAM_INT_VC("E_SLIDER_Liquid_Despeckle", "Despeckle", "Particles",
                    0, 8, 0, "E_VALUECURVE_Liquid_Despeckle"),
    XL_PARAM_END
};

static const char * const kLiquidGroups[] = { "Basic", "Barriers", "Position 1", "Particles", NULL };

// --------------------------------------------------------------------------
// Marquee Effect
// --------------------------------------------------------------------------
static const XLParameterDef kMarqueeParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Marquee_Band_Size", "Band Size", "Basic",
                    1, 100, 3, "E_VALUECURVE_Marquee_Band_Size"),
    XL_PARAM_INT_VC("E_SLIDER_Marquee_Skip_Size", "Skip Size", "Basic",
                    0, 100, 0, "E_VALUECURVE_Marquee_Skip_Size"),
    XL_PARAM_INT_VC("E_SLIDER_Marquee_Thickness", "Thickness", "Basic",
                    1, 100, 1, "E_VALUECURVE_Marquee_Thickness"),
    XL_PARAM_INT_VC("E_SLIDER_Marquee_Stagger", "Stagger", "Basic",
                    0, 100, 0, "E_VALUECURVE_Marquee_Stagger"),
    XL_PARAM_INT_VC("E_SLIDER_Marquee_Speed", "Speed", "Basic",
                    0, 50, 3, "E_VALUECURVE_Marquee_Speed"),
    XL_PARAM_INT_VC("E_SLIDER_Marquee_Start", "Start Position", "Basic",
                    0, 100, 0, "E_VALUECURVE_Marquee_Start"),
    XL_PARAM_INT_VC("E_SLIDER_Marquee_ScaleX", "Scale X", "Scale",
                    1, 100, 100, "E_VALUECURVE_Marquee_ScaleX"),
    XL_PARAM_INT_VC("E_SLIDER_Marquee_ScaleY", "Scale Y", "Scale",
                    1, 100, 100, "E_VALUECURVE_Marquee_ScaleY"),
    XL_PARAM_BOOL("E_CHECKBOX_Marquee_Reverse", "Reverse", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Marquee_WrapX", "Wrap X", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Marquee_PixelOffsets", "Pixel Offsets", "Options", 0),
    XL_PARAM_END
};

static const char * const kMarqueeGroups[] = { "Basic", "Scale", "Options", NULL };

// --------------------------------------------------------------------------
// Meteors Effect
// --------------------------------------------------------------------------
static const XLParameterDef kMeteorsParameters[] = {
    XL_PARAM_CHOICE("E_CHOICE_Meteors_Type", "Type", "Basic",
                    kMeteorsTypeChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Meteors_Direction", "Direction", "Basic",
                    kMeteorsDirectionChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Meteors_Count", "Count", "Basic",
                    1, 100, 10, "E_VALUECURVE_Meteors_Count"),
    XL_PARAM_INT_VC("E_SLIDER_Meteors_Length", "Length", "Basic",
                    1, 100, 25, "E_VALUECURVE_Meteors_Length"),
    XL_PARAM_INT_VC("E_SLIDER_Meteors_Speed", "Speed", "Basic",
                    1, 50, 10, "E_VALUECURVE_Meteors_Speed"),
    XL_PARAM_INT_VC("E_SLIDER_Meteors_Swirl_Intensity", "Swirl", "Basic",
                    0, 20, 0, "E_VALUECURVE_Meteors_Swirl_Intensity"),
    XL_PARAM_INT_VC("E_SLIDER_Meteors_XOffset", "X Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_Meteors_XOffset"),
    XL_PARAM_INT_VC("E_SLIDER_Meteors_YOffset", "Y Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_Meteors_YOffset"),
    XL_PARAM_BOOL("E_CHECKBOX_Meteors_UseMusic", "Fire with Music", "Music", 0),
    XL_PARAM_END
};

static const char * const kMeteorsGroups[] = { "Basic", "Position", "Music", NULL };

// --------------------------------------------------------------------------
// Morph Effect
// --------------------------------------------------------------------------
static const XLParameterDef kMorphParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Morph_Start_X1", "Start X1", "Start Position 1",
                    0, 100, 0, "E_VALUECURVE_Morph_Start_X1"),
    XL_PARAM_INT_VC("E_SLIDER_Morph_Start_Y1", "Start Y1", "Start Position 1",
                    0, 100, 0, "E_VALUECURVE_Morph_Start_Y1"),
    XL_PARAM_INT_VC("E_SLIDER_Morph_Start_X2", "Start X2", "Start Position 2",
                    0, 100, 100, "E_VALUECURVE_Morph_Start_X2"),
    XL_PARAM_INT_VC("E_SLIDER_Morph_Start_Y2", "Start Y2", "Start Position 2",
                    0, 100, 0, "E_VALUECURVE_Morph_Start_Y2"),
    XL_PARAM_INT_VC("E_SLIDER_Morph_End_X1", "End X1", "End Position 1",
                    0, 100, 0, "E_VALUECURVE_Morph_End_X1"),
    XL_PARAM_INT_VC("E_SLIDER_Morph_End_Y1", "End Y1", "End Position 1",
                    0, 100, 100, "E_VALUECURVE_Morph_End_Y1"),
    XL_PARAM_INT_VC("E_SLIDER_Morph_End_X2", "End X2", "End Position 2",
                    0, 100, 100, "E_VALUECURVE_Morph_End_X2"),
    XL_PARAM_INT_VC("E_SLIDER_Morph_End_Y2", "End Y2", "End Position 2",
                    0, 100, 100, "E_VALUECURVE_Morph_End_Y2"),
    XL_PARAM_INT_VC("E_SLIDER_MorphStartLength", "Start Length", "Length",
                    0, 100, 1, "E_VALUECURVE_MorphStartLength"),
    XL_PARAM_INT_VC("E_SLIDER_MorphEndLength", "End Length", "Length",
                    0, 100, 1, "E_VALUECURVE_MorphEndLength"),
    XL_PARAM_INT_VC("E_SLIDER_MorphDuration", "Head Duration", "Timing",
                    0, 100, 20, "E_VALUECURVE_MorphDuration"),
    XL_PARAM_INT_VC("E_SLIDER_MorphAccel", "Acceleration", "Timing",
                    -10, 10, 0, "E_VALUECURVE_MorphAccel"),
    XL_PARAM_INT_VC("E_SLIDER_Morph_Repeat_Count", "Repeat Count", "Repeats",
                    1, 250, 1, "E_VALUECURVE_Morph_Repeat_Count"),
    XL_PARAM_INT_VC("E_SLIDER_Morph_Repeat_Skip", "Repeat Skip", "Repeats",
                    1, 100, 1, "E_VALUECURVE_Morph_Repeat_Skip"),
    XL_PARAM_INT_VC("E_SLIDER_Morph_Stagger", "Stagger", "Repeats",
                    0, 100, 0, "E_VALUECURVE_Morph_Stagger"),
    XL_PARAM_BOOL("E_CHECKBOX_ShowHeadAtStart", "Show Head at Start", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Morph_AutoReverse", "Auto Reverse", "Options", 0),
    XL_PARAM_END
};

static const char * const kMorphGroups[] = { "Start Position 1", "Start Position 2", "End Position 1", "End Position 2", "Length", "Timing", "Repeats", "Options", NULL };

// --------------------------------------------------------------------------
// Music Effect
// --------------------------------------------------------------------------
static const XLParameterDef kMusicParameters[] = {
    XL_PARAM_CHOICE("E_CHOICE_Music_Type", "Type", "Basic",
                    kMusicTypeChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Music_Scaling", "Scaling", "Basic",
                    kMusicScalingChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Music_Color", "Color", "Basic",
                    kMusicColorChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Music_Bars", "Bars", "Basic",
                    1, 100, 20, "E_VALUECURVE_Music_Bars"),
    XL_PARAM_INT_VC("E_SLIDER_Music_StartNote", "Start Note", "Range",
                    0, 127, 0, "E_VALUECURVE_Music_StartNote"),
    XL_PARAM_INT_VC("E_SLIDER_Music_EndNote", "End Note", "Range",
                    0, 127, 127, "E_VALUECURVE_Music_EndNote"),
    XL_PARAM_INT_VC("E_SLIDER_Music_Offset", "Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_Music_Offset"),
    XL_PARAM_INT_VC("E_SLIDER_Music_Sensitivity", "Sensitivity", "Basic",
                    0, 100, 50, "E_VALUECURVE_Music_Sensitivity"),
    XL_PARAM_BOOL("E_CHECKBOX_Music_Fade", "Fade", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Music_LogarithmicX", "Logarithmic X", "Options", 0),
    XL_PARAM_END
};

static const char * const kMusicGroups[] = { "Basic", "Range", "Position", "Options", NULL };

// --------------------------------------------------------------------------
// Pictures Effect (needs custom panel for file preview)
// --------------------------------------------------------------------------
static const XLParameterDef kPicturesParameters[] = {
    XL_PARAM_FILE("E_FILEPICKERCTRL_Pictures_Filename", "Filename", "Basic", "png,jpg,gif,bmp"),
    XL_PARAM_CHOICE("E_CHOICE_Pictures_Direction", "Direction", "Basic",
                    kPicturesDirectionChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Pictures_Speed", "Speed", "Basic",
                    1, 100, 10, "E_VALUECURVE_Pictures_Speed"),
    XL_PARAM_INT_VC("E_SLIDER_Pictures_FrameRateAdj", "Frame Rate Adj", "Basic",
                    0, 100, 100, "E_VALUECURVE_Pictures_FrameRateAdj"),
    XL_PARAM_INT_VC("E_SLIDER_PicturesXC", "X Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_PicturesXC"),
    XL_PARAM_INT_VC("E_SLIDER_PicturesYC", "Y Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_PicturesYC"),
    XL_PARAM_INT_VC("E_SLIDER_PicturesEndXC", "End X Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_PicturesEndXC"),
    XL_PARAM_INT_VC("E_SLIDER_PicturesEndYC", "End Y Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_PicturesEndYC"),
    XL_PARAM_INT_VC("E_SLIDER_Pictures_StartScale", "Start Scale", "Scale",
                    0, 1000, 100, "E_VALUECURVE_Pictures_StartScale"),
    XL_PARAM_INT_VC("E_SLIDER_Pictures_EndScale", "End Scale", "Scale",
                    0, 1000, 100, "E_VALUECURVE_Pictures_EndScale"),
    XL_PARAM_BOOL("E_CHECKBOX_Pictures_PixelOffsets", "Pixel Offsets", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Pictures_WrapX", "Wrap X", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Pictures_Shimmer", "Shimmer", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Pictures_TransparentBlack", "Transparent Black", "Options", 0),
    XL_PARAM_INT_VC("E_SLIDER_Pictures_TransparentBlackLevel", "Transparency Level", "Options",
                    0, 255, 0, "E_VALUECURVE_Pictures_TransparentBlackLevel"),
    XL_PARAM_END
};

static const char * const kPicturesGroups[] = { "Basic", "Position", "Scale", "Options", NULL };

// --------------------------------------------------------------------------
// Pinwheel Effect
// --------------------------------------------------------------------------
static const XLParameterDef kPinwheelParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Pinwheel_Arms", "Arms", "Basic",
                    1, 10, 3, "E_VALUECURVE_Pinwheel_Arms"),
    XL_PARAM_INT_VC("E_SLIDER_Pinwheel_Thickness", "Arm Size", "Basic",
                    0, 100, 100, "E_VALUECURVE_Pinwheel_Thickness"),
    XL_PARAM_INT_VC("E_SLIDER_Pinwheel_Twist", "Twist", "Basic",
                    -300, 300, 0, "E_VALUECURVE_Pinwheel_Twist"),
    XL_PARAM_INT_VC("E_SLIDER_Pinwheel_Speed", "Speed", "Motion",
                    0, 50, 10, "E_VALUECURVE_Pinwheel_Speed"),
    XL_PARAM_INT_VC("E_SLIDER_Pinwheel_Offset", "Offset", "Motion",
                    0, 360, 0, "E_VALUECURVE_Pinwheel_Offset"),
    XL_PARAM_INT_VC("E_SLIDER_PinwheelXC", "X Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_PinwheelXC"),
    XL_PARAM_INT_VC("E_SLIDER_PinwheelYC", "Y Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_PinwheelYC"),
    XL_PARAM_CHOICE("E_CHOICE_Pinwheel_Style", "Style", "Basic",
                    kPinwheelStyleChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Pinwheel_Rotation", "Rotation", "Motion",
                    kPinwheelRotationChoices, 0),
    XL_PARAM_END
};

static const char * const kPinwheelGroups[] = { "Basic", "Motion", "Position", NULL };

// --------------------------------------------------------------------------
// Plasma Effect
// --------------------------------------------------------------------------
static const XLParameterDef kPlasmaParameters[] = {
    XL_PARAM_CHOICE("E_CHOICE_Plasma_Color", "Color Choice", "Basic",
                    kPlasmaColorChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Plasma_Algorithm", "Style", "Basic",
                    kPlasmaAlgorithmChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Plasma_Speed", "Speed", "Basic",
                    0, 100, 10, "E_VALUECURVE_Plasma_Speed"),
    XL_PARAM_INT_VC("E_SLIDER_Plasma_Line_Density", "Line Density", "Basic",
                    1, 10, 1, "E_VALUECURVE_Plasma_Line_Density"),
    XL_PARAM_END
};

static const char * const kPlasmaGroups[] = { "Basic", NULL };

// --------------------------------------------------------------------------
// Ripple Effect
// --------------------------------------------------------------------------
static const XLParameterDef kRippleParameters[] = {
    XL_PARAM_CHOICE("E_CHOICE_Ripple_Movement", "Movement", "Basic",
                    kRippleMovementChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Ripple_Object_To_Draw", "Object", "Basic",
                    kRippleObjectChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Ripple_Thickness", "Thickness", "Basic",
                    1, 100, 3, "E_VALUECURVE_Ripple_Thickness"),
    XL_PARAM_INT_VC("E_SLIDER_Ripple_Cycles", "Cycles", "Basic",
                    0, 500, 100, "E_VALUECURVE_Ripple_Cycles"),
    XL_PARAM_INT_VC("E_SLIDER_Ripple_Points", "Points", "Shape",
                    4, 7, 5, "E_VALUECURVE_Ripple_Points"),
    XL_PARAM_INT_VC("E_SLIDER_Ripple_Rotation", "Rotation", "Shape",
                    0, 359, 0, "E_VALUECURVE_Ripple_Rotation"),
    XL_PARAM_INT_VC("E_SLIDER_RIPPLE_SPARKLE", "Sparkle", "Effects",
                    0, 100, 0, "E_VALUECURVE_RIPPLE_SPARKLE"),
    XL_PARAM_BOOL("E_CHECKBOX_Ripple_3D", "3D", "Options", 0),
    XL_PARAM_END
};

static const char * const kRippleGroups[] = { "Basic", "Shape", "Effects", "Options", NULL };

// --------------------------------------------------------------------------
// Servo Effect
// --------------------------------------------------------------------------
static const XLParameterDef kServoParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Servo_Channel", "Servo Channel", "Basic",
                    1, 24, 1, "E_VALUECURVE_Servo_Channel"),
    XL_PARAM_INT_VC("E_SLIDER_Servo_Value", "Servo Value", "Basic",
                    0, 1000, 0, "E_VALUECURVE_Servo_Value"),
    XL_PARAM_BOOL("E_CHECKBOX_Servo_16bit", "16 Bit", "Options", 0),
    XL_PARAM_END
};

static const char * const kServoGroups[] = { "Basic", "Options", NULL };

// --------------------------------------------------------------------------
// Shader Effect (needs custom panel for shader code editor)
// --------------------------------------------------------------------------
static const XLParameterDef kShaderParameters[] = {
    XL_PARAM_FILE("E_FILEPICKERCTRL_Shader_Filename", "Shader File", "Basic", "fs"),
    XL_PARAM_FLOAT_VC("E_SLIDER_Shader_Speed", "Speed", "Basic",
                      -1000, 1000, 100, 100, "E_VALUECURVE_Shader_Speed"),
    XL_PARAM_INT_VC("E_SLIDER_Shader_Offset_X", "X Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_Shader_Offset_X"),
    XL_PARAM_INT_VC("E_SLIDER_Shader_Offset_Y", "Y Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_Shader_Offset_Y"),
    XL_PARAM_INT_VC("E_SLIDER_Shader_Zoom", "Zoom", "Scale",
                    0, 200, 100, "E_VALUECURVE_Shader_Zoom"),
    XL_PARAM_END
};

static const char * const kShaderGroups[] = { "Basic", "Position", "Scale", NULL };

// --------------------------------------------------------------------------
// Shape Effect
// --------------------------------------------------------------------------
static const XLParameterDef kShapeParameters[] = {
    XL_PARAM_CHOICE("E_CHOICE_Shape_ObjectToDraw", "Object", "Basic",
                    kShapeObjectChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Shape_Thickness", "Thickness", "Basic",
                    1, 100, 1, "E_VALUECURVE_Shape_Thickness"),
    XL_PARAM_INT_VC("E_SLIDER_Shape_Count", "Count", "Basic",
                    1, 100, 5, "E_VALUECURVE_Shape_Count"),
    XL_PARAM_INT_VC("E_SLIDER_Shape_Growth", "Growth", "Growth",
                    -100, 100, 10, "E_VALUECURVE_Shape_Growth"),
    XL_PARAM_INT_VC("E_SLIDER_Shape_StartSize", "Start Size", "Growth",
                    0, 100, 5, "E_VALUECURVE_Shape_StartSize"),
    XL_PARAM_INT_VC("E_SLIDER_Shape_Lifetime", "Lifetime", "Timing",
                    1, 100, 5, "E_VALUECURVE_Shape_Lifetime"),
    XL_PARAM_INT_VC("E_SLIDER_Shape_CenterX", "Center X", "Position",
                    0, 100, 50, "E_VALUECURVE_Shape_CenterX"),
    XL_PARAM_INT_VC("E_SLIDER_Shape_CenterY", "Center Y", "Position",
                    0, 100, 50, "E_VALUECURVE_Shape_CenterY"),
    XL_PARAM_INT_VC("E_SLIDER_Shape_Points", "Points", "Shape",
                    4, 7, 5, "E_VALUECURVE_Shape_Points"),
    XL_PARAM_INT_VC("E_SLIDER_Shape_Rotation", "Rotation", "Shape",
                    0, 359, 0, "E_VALUECURVE_Shape_Rotation"),
    XL_PARAM_BOOL("E_CHECKBOX_Shape_RandomLocation", "Random Location", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Shape_RandomInitial", "Random Initial", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Shape_FadeAway", "Fade Away", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Shape_UseMusic", "Fire with Music", "Music", 0),
    XL_PARAM_END
};

static const char * const kShapeGroups[] = { "Basic", "Growth", "Timing", "Position", "Shape", "Options", "Music", NULL };

// --------------------------------------------------------------------------
// Shimmer Effect
// --------------------------------------------------------------------------
static const XLParameterDef kShimmerParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Shimmer_Duty_Factor", "Duty Factor", "Basic",
                    1, 100, 50, "E_VALUECURVE_Shimmer_Duty_Factor"),
    XL_PARAM_FLOAT_VC("E_SLIDER_Shimmer_Cycles", "Cycles", "Basic",
                      0, 6000, 10, 10, "E_VALUECURVE_Shimmer_Cycles"),
    XL_PARAM_CHOICE("E_CHOICE_Shimmer_Cycle_Type", "Cycle Type", "Basic",
                    kShimmerCycleChoices, 0),
    XL_PARAM_BOOL("E_CHECKBOX_Shimmer_Use_All_Colors", "Use All Colors", "Options", 0),
    XL_PARAM_END
};

static const char * const kShimmerGroups[] = { "Basic", "Options", NULL };

// --------------------------------------------------------------------------
// Shockwave Effect
// --------------------------------------------------------------------------
static const XLParameterDef kShockwaveParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Shockwave_CenterX", "Center X", "Position",
                    0, 100, 50, "E_VALUECURVE_Shockwave_CenterX"),
    XL_PARAM_INT_VC("E_SLIDER_Shockwave_CenterY", "Center Y", "Position",
                    0, 100, 50, "E_VALUECURVE_Shockwave_CenterY"),
    XL_PARAM_INT_VC("E_SLIDER_Shockwave_Start_Radius", "Start Radius", "Radius",
                    0, 250, 1, "E_VALUECURVE_Shockwave_Start_Radius"),
    XL_PARAM_INT_VC("E_SLIDER_Shockwave_End_Radius", "End Radius", "Radius",
                    0, 250, 10, "E_VALUECURVE_Shockwave_End_Radius"),
    XL_PARAM_INT_VC("E_SLIDER_Shockwave_Start_Width", "Start Width", "Width",
                    0, 255, 5, "E_VALUECURVE_Shockwave_Start_Width"),
    XL_PARAM_INT_VC("E_SLIDER_Shockwave_End_Width", "End Width", "Width",
                    0, 255, 10, "E_VALUECURVE_Shockwave_End_Width"),
    XL_PARAM_INT_VC("E_SLIDER_Shockwave_Accel", "Acceleration", "Motion",
                    -10, 10, 0, "E_VALUECURVE_Shockwave_Accel"),
    XL_PARAM_CHOICE("E_CHOICE_Shockwave_Direction", "Direction", "Motion",
                    kShockwaveDirectionChoices, 0),
    XL_PARAM_BOOL("E_CHECKBOX_Shockwave_Blend_Edges", "Blend Edges", "Options", 0),
    XL_PARAM_END
};

static const char * const kShockwaveGroups[] = { "Position", "Radius", "Width", "Motion", "Options", NULL };

// --------------------------------------------------------------------------
// SingleStrand Effect
// --------------------------------------------------------------------------
static const XLParameterDef kSingleStrandParameters[] = {
    XL_PARAM_CHOICE("E_CHOICE_SingleStrand_Type", "Type", "Basic",
                    kSingleStrandTypeChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Chase_Type1", "Chase", "Chase",
                    kSingleStrandChaseChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Number_Chases", "Number Chases", "Chase",
                    1, 20, 1, "E_VALUECURVE_Number_Chases"),
    XL_PARAM_INT_VC("E_SLIDER_Color_Mix1", "Color Mix", "Chase",
                    1, 10, 1, "E_VALUECURVE_Color_Mix1"),
    XL_PARAM_INT_VC("E_SLIDER_Chase_Rotations", "Rotations", "Chase",
                    1, 150, 10, "E_VALUECURVE_Chase_Rotations"),
    XL_PARAM_BOOL("E_CHECKBOX_Chase_3dFade1", "3D Fade", "Chase", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Chase_Group_All", "Group All", "Chase", 0),
    XL_PARAM_INT_VC("E_SLIDER_Skips_BandSize", "Band Size", "Skips",
                    1, 100, 1, "E_VALUECURVE_Skips_BandSize"),
    XL_PARAM_INT_VC("E_SLIDER_Skips_SkipSize", "Skip Size", "Skips",
                    1, 100, 1, "E_VALUECURVE_Skips_SkipSize"),
    XL_PARAM_INT_VC("E_SLIDER_Skips_StartPos", "Start Position", "Skips",
                    1, 100, 1, "E_VALUECURVE_Skips_StartPos"),
    XL_PARAM_INT_VC("E_SLIDER_Skips_Advance", "Advance", "Skips",
                    0, 100, 0, "E_VALUECURVE_Skips_Advance"),
    XL_PARAM_CHOICE("E_CHOICE_Skips_Direction", "Direction", "Skips",
                    kSpiralsDirectionChoices, 0),
    XL_PARAM_END
};

static const char * const kSingleStrandGroups[] = { "Basic", "Chase", "Skips", NULL };

// --------------------------------------------------------------------------
// Snowflakes Effect
// --------------------------------------------------------------------------
static const XLParameterDef kSnowflakesParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Snowflakes_Count", "Max Snowflakes", "Basic",
                    1, 100, 5, "E_VALUECURVE_Snowflakes_Count"),
    XL_PARAM_CHOICE("E_CHOICE_Snowflakes_Type", "Type", "Basic",
                    kSnowflakesTypeChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Snowflakes_Speed", "Speed", "Basic",
                    1, 50, 10, "E_VALUECURVE_Snowflakes_Speed"),
    XL_PARAM_CHOICE("E_CHOICE_Snowflakes_Direction", "Direction", "Basic",
                    kSnowflakesDirectionChoices, 0),
    XL_PARAM_BOOL("E_CHECKBOX_Snowflakes_Accumulate", "Accumulate", "Options", 0),
    XL_PARAM_END
};

static const char * const kSnowflakesGroups[] = { "Basic", "Options", NULL };

// --------------------------------------------------------------------------
// Snowstorm Effect
// --------------------------------------------------------------------------
static const XLParameterDef kSnowstormParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Snowstorm_Count", "Max Snowflakes", "Basic",
                    1, 100, 5, "E_VALUECURVE_Snowstorm_Count"),
    XL_PARAM_INT_VC("E_SLIDER_Snowstorm_Length", "Trail Length", "Basic",
                    1, 100, 5, "E_VALUECURVE_Snowstorm_Length"),
    XL_PARAM_INT_VC("E_SLIDER_Snowstorm_Speed", "Speed", "Basic",
                    1, 50, 10, "E_VALUECURVE_Snowstorm_Speed"),
    XL_PARAM_END
};

static const char * const kSnowstormGroups[] = { "Basic", NULL };

// --------------------------------------------------------------------------
// Spirals Effect
// --------------------------------------------------------------------------
static const XLParameterDef kSpiralsParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Spirals_Count", "Palette Rep", "Basic",
                    1, 5, 1, "E_VALUECURVE_Spirals_Count"),
    XL_PARAM_INT_VC("E_SLIDER_Spirals_Rotation", "Rotations", "Motion",
                    -500, 500, 20, "E_VALUECURVE_Spirals_Rotation"),
    XL_PARAM_INT_VC("E_SLIDER_Spirals_Thickness", "Thickness", "Basic",
                    0, 100, 50, "E_VALUECURVE_Spirals_Thickness"),
    XL_PARAM_CHOICE("E_CHOICE_Spirals_Direction", "Direction", "Motion",
                    kSpiralsDirectionChoices, 0),
    XL_PARAM_BOOL("E_CHECKBOX_Spirals_Blend", "Blend", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Spirals_3D", "3D", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Spirals_Grow", "Grow", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Spirals_Shrink", "Shrink", "Options", 0),
    XL_PARAM_END
};

static const char * const kSpiralsGroups[] = { "Basic", "Motion", "Options", NULL };

// --------------------------------------------------------------------------
// Spirograph Effect
// --------------------------------------------------------------------------
static const XLParameterDef kSpirographParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Spirograph_R", "R", "Basic",
                    1, 100, 20, "E_VALUECURVE_Spirograph_R"),
    XL_PARAM_INT_VC("E_SLIDER_Spirograph_r", "r", "Basic",
                    1, 100, 10, "E_VALUECURVE_Spirograph_r"),
    XL_PARAM_INT_VC("E_SLIDER_Spirograph_d", "d", "Basic",
                    1, 100, 30, "E_VALUECURVE_Spirograph_d"),
    XL_PARAM_INT_VC("E_SLIDER_Spirograph_Speed", "Speed", "Motion",
                    1, 50, 10, "E_VALUECURVE_Spirograph_Speed"),
    XL_PARAM_CHOICE("E_CHOICE_Spirograph_Animate", "Animate", "Motion",
                    kSpirographAnimateChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Spirograph_Length", "Length", "Drawing",
                    0, 100, 0, "E_VALUECURVE_Spirograph_Length"),
    XL_PARAM_INT_VC("E_SLIDER_Spirograph_Width", "Width", "Drawing",
                    1, 10, 1, "E_VALUECURVE_Spirograph_Width"),
    XL_PARAM_END
};

static const char * const kSpirographGroups[] = { "Basic", "Motion", "Drawing", NULL };

// --------------------------------------------------------------------------
// State Effect
// --------------------------------------------------------------------------
static const XLParameterDef kStateParameters[] = {
    XL_PARAM_STRING("E_CHOICE_State_StateDefinition", "State Definition", "Basic", ""),
    XL_PARAM_STRING("E_CHOICE_State_TimingTrack", "Timing Track", "Basic", ""),
    XL_PARAM_STRING("E_CHOICE_State_State", "State", "Basic", ""),
    XL_PARAM_STRING("E_CHOICE_State_Color", "Color", "Basic", ""),
    XL_PARAM_STRING("E_CHOICE_State_Mode", "Mode", "Basic", ""),
    XL_PARAM_END
};

static const char * const kStateGroups[] = { "Basic", NULL };

// --------------------------------------------------------------------------
// Strobe Effect
// --------------------------------------------------------------------------
static const XLParameterDef kStrobeParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Strobe_Number", "Number Strobes", "Basic",
                    1, 300, 10, "E_VALUECURVE_Strobe_Number"),
    XL_PARAM_INT_VC("E_SLIDER_Strobe_Duration", "Strobe Duration", "Basic",
                    1, 100, 10, "E_VALUECURVE_Strobe_Duration"),
    XL_PARAM_CHOICE("E_CHOICE_Strobe_Type", "Type", "Basic",
                    kStrobeTypeChoices, 0),
    XL_PARAM_BOOL("E_CHECKBOX_Strobe_Music", "React to Music", "Music", 0),
    XL_PARAM_END
};

static const char * const kStrobeGroups[] = { "Basic", "Music", NULL };

// --------------------------------------------------------------------------
// Tendril Effect
// --------------------------------------------------------------------------
static const XLParameterDef kTendrilParameters[] = {
    XL_PARAM_CHOICE("E_CHOICE_Tendril_Movement", "Movement", "Basic",
                    kTendrilMovementChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Tendril_Thickness", "Thickness", "Basic",
                    1, 20, 1, "E_VALUECURVE_Tendril_Thickness"),
    XL_PARAM_INT_VC("E_SLIDER_Tendril_Friction", "Friction", "Physics",
                    0, 100, 10, "E_VALUECURVE_Tendril_Friction"),
    XL_PARAM_INT_VC("E_SLIDER_Tendril_Dampening", "Dampening", "Physics",
                    0, 100, 10, "E_VALUECURVE_Tendril_Dampening"),
    XL_PARAM_INT_VC("E_SLIDER_Tendril_Tension", "Tension", "Physics",
                    0, 100, 20, "E_VALUECURVE_Tendril_Tension"),
    XL_PARAM_INT_VC("E_SLIDER_Tendril_Speed", "Speed", "Motion",
                    1, 100, 10, "E_VALUECURVE_Tendril_Speed"),
    XL_PARAM_INT_VC("E_SLIDER_Tendril_XOffset", "X Offset", "Position",
                    0, 100, 50, "E_VALUECURVE_Tendril_XOffset"),
    XL_PARAM_INT_VC("E_SLIDER_Tendril_YOffset", "Y Offset", "Position",
                    0, 100, 50, "E_VALUECURVE_Tendril_YOffset"),
    XL_PARAM_BOOL("E_CHECKBOX_Tendril_ManualSettings", "Manual Settings", "Options", 0),
    XL_PARAM_END
};

static const char * const kTendrilGroups[] = { "Basic", "Physics", "Motion", "Position", "Options", NULL };

// --------------------------------------------------------------------------
// Text Effect (needs custom panel for font picker)
// --------------------------------------------------------------------------
static const XLParameterDef kTextParameters[] = {
    XL_PARAM_STRING("E_TEXTCTRL_Text", "Text", "Text", ""),
    XL_PARAM_FILE("E_FILEPICKERCTRL_Text_File", "From File", "Text", "txt"),
    XL_PARAM_FONT("E_FONTPICKER_Text_Font", "Font", "Text"),
    XL_PARAM_CHOICE("E_CHOICE_Text_Dir", "Movement", "Movement",
                    kTextDirectionChoices, 0),
    XL_PARAM_BOOL("E_CHECKBOX_TextToCenter", "Center", "Movement", 0),
    XL_PARAM_BOOL("E_CHECKBOX_TextNoRepeat", "No Repeat", "Movement", 0),
    XL_PARAM_INT_VC("E_SLIDER_Text_Speed", "Speed", "Movement",
                    0, 50, 10, "E_VALUECURVE_Text_Speed"),
    XL_PARAM_INT_VC("E_SLIDER_Text_XStart", "X Start", "Position",
                    0, 100, 0, "E_VALUECURVE_Text_XStart"),
    XL_PARAM_INT_VC("E_SLIDER_Text_YStart", "Y Start", "Position",
                    0, 100, 0, "E_VALUECURVE_Text_YStart"),
    XL_PARAM_INT_VC("E_SLIDER_Text_XEnd", "X End", "Position",
                    0, 100, 0, "E_VALUECURVE_Text_XEnd"),
    XL_PARAM_INT_VC("E_SLIDER_Text_YEnd", "Y End", "Position",
                    0, 100, 0, "E_VALUECURVE_Text_YEnd"),
    XL_PARAM_CHOICE("E_CHOICE_Text_Effect", "Effect", "Effects",
                    kTextEffectChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Text_Count", "Count Down", "Effects",
                    kTextCountChoices, 0),
    XL_PARAM_BOOL("E_CHECKBOX_Text_PixelOffsets", "Pixel Offsets", "Options", 0),
    XL_PARAM_END
};

static const char * const kTextGroups[] = { "Text", "Movement", "Position", "Effects", "Options", NULL };

// --------------------------------------------------------------------------
// Tree Effect
// --------------------------------------------------------------------------
static const XLParameterDef kTreeParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Tree_Branches", "Branches", "Basic",
                    1, 20, 3, "E_VALUECURVE_Tree_Branches"),
    XL_PARAM_INT_VC("E_SLIDER_Tree_Speed", "Speed", "Basic",
                    1, 50, 10, "E_VALUECURVE_Tree_Speed"),
    XL_PARAM_CHOICE("E_CHOICE_Tree_Type", "Type", "Basic",
                    kTreeTypeChoices, 0),
    XL_PARAM_END
};

static const char * const kTreeGroups[] = { "Basic", NULL };

// --------------------------------------------------------------------------
// Twinkle Effect
// --------------------------------------------------------------------------
static const XLParameterDef kTwinkleParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Twinkle_Count", "Number Lights", "Basic",
                    2, 100, 3, "E_VALUECURVE_Twinkle_Count"),
    XL_PARAM_INT_VC("E_SLIDER_Twinkle_Steps", "Twinkle Steps", "Basic",
                    2, 200, 30, "E_VALUECURVE_Twinkle_Steps"),
    XL_PARAM_BOOL("E_CHECKBOX_Twinkle_Strobe", "Strobe", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Twinkle_ReRandom", "Re-Randomize after Twinkle", "Options", 0),
    XL_PARAM_END
};

static const char * const kTwinkleGroups[] = { "Basic", "Options", NULL };

// --------------------------------------------------------------------------
// Video Effect (needs custom panel for video preview)
// --------------------------------------------------------------------------
static const XLParameterDef kVideoParameters[] = {
    XL_PARAM_FILE("E_FILEPICKERCTRL_Video_Filename", "Filename", "Basic", "mp4,mov,avi,mkv"),
    XL_PARAM_FLOAT_VC("E_SLIDER_Video_Starttime", "Start Time", "Timing",
                      0, 36000, 0, 10, "E_VALUECURVE_Video_Starttime"),
    XL_PARAM_FLOAT_VC("E_SLIDER_Video_Speed", "Playback Speed", "Timing",
                      -1000, 1000, 100, 100, "E_VALUECURVE_Video_Speed"),
    XL_PARAM_BOOL("E_CHECKBOX_Video_AspectRatio", "Keep Aspect Ratio", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_SynchroniseStatic", "Synchronise", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_Video_TransparentBlack", "Transparent Black", "Options", 0),
    XL_PARAM_INT_VC("E_SLIDER_Video_TransparentBlackLevel", "Transparency Level", "Options",
                    0, 255, 0, "E_VALUECURVE_Video_TransparentBlackLevel"),
    XL_PARAM_CHOICE("E_CHOICE_Video_DurationTreatment", "Duration Treatment", "Timing",
                    kVideoStartChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Video_Scaling", "Scaling", "Options",
                    kVideoScalingChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Video_CropLeft", "Crop Left", "Crop",
                    0, 100, 0, "E_VALUECURVE_Video_CropLeft"),
    XL_PARAM_INT_VC("E_SLIDER_Video_CropRight", "Crop Right", "Crop",
                    0, 100, 0, "E_VALUECURVE_Video_CropRight"),
    XL_PARAM_INT_VC("E_SLIDER_Video_CropTop", "Crop Top", "Crop",
                    0, 100, 0, "E_VALUECURVE_Video_CropTop"),
    XL_PARAM_INT_VC("E_SLIDER_Video_CropBottom", "Crop Bottom", "Crop",
                    0, 100, 0, "E_VALUECURVE_Video_CropBottom"),
    XL_PARAM_END
};

static const char * const kVideoGroups[] = { "Basic", "Timing", "Options", "Crop", NULL };

// --------------------------------------------------------------------------
// VUMeter Effect
// --------------------------------------------------------------------------
static const XLParameterDef kVUMeterParameters[] = {
    XL_PARAM_CHOICE("E_CHOICE_VUMeter_Type", "Type", "Basic",
                    kVUMeterTypeChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_VUMeter_Bars", "Bars", "Basic",
                    1, 100, 6, "E_VALUECURVE_VUMeter_Bars"),
    XL_PARAM_INT_VC("E_SLIDER_VUMeter_Sensitivity", "Sensitivity", "Basic",
                    0, 100, 70, "E_VALUECURVE_VUMeter_Sensitivity"),
    XL_PARAM_INT_VC("E_SLIDER_VUMeter_StartNote", "Start Note", "Range",
                    0, 127, 36, "E_VALUECURVE_VUMeter_StartNote"),
    XL_PARAM_INT_VC("E_SLIDER_VUMeter_EndNote", "End Note", "Range",
                    0, 127, 84, "E_VALUECURVE_VUMeter_EndNote"),
    XL_PARAM_INT_VC("E_SLIDER_VUMeter_XOffset", "X Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_VUMeter_XOffset"),
    XL_PARAM_INT_VC("E_SLIDER_VUMeter_YOffset", "Y Offset", "Position",
                    -100, 100, 0, "E_VALUECURVE_VUMeter_YOffset"),
    XL_PARAM_CHOICE("E_CHOICE_VUMeter_Shape", "Shape", "Shape",
                    kVUMeterShapeChoices, 0),
    XL_PARAM_BOOL("E_CHECKBOX_VUMeter_SlowDownFalls", "Slow Down Falls", "Options", 1),
    XL_PARAM_BOOL("E_CHECKBOX_VUMeter_LogarithmicX", "Logarithmic X", "Options", 0),
    XL_PARAM_END
};

static const char * const kVUMeterGroups[] = { "Basic", "Range", "Position", "Shape", "Options", NULL };

// --------------------------------------------------------------------------
// Warp Effect
// --------------------------------------------------------------------------
static const XLParameterDef kWarpParameters[] = {
    XL_PARAM_CHOICE("E_CHOICE_Warp_Type", "Type", "Basic",
                    kWarpEffectChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Warp_Treatment", "Treatment", "Basic",
                    kWarpTreatmentChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Warp_X", "X", "Position",
                    0, 100, 50, "E_VALUECURVE_Warp_X"),
    XL_PARAM_INT_VC("E_SLIDER_Warp_Y", "Y", "Position",
                    0, 100, 50, "E_VALUECURVE_Warp_Y"),
    XL_PARAM_INT_VC("E_SLIDER_Warp_Cycle_Count", "Cycle Count", "Cycles",
                    0, 50, 1, "E_VALUECURVE_Warp_Cycle_Count"),
    XL_PARAM_FLOAT_VC("E_SLIDER_Warp_Speed", "Speed", "Cycles",
                      0, 40, 20, 10, "E_VALUECURVE_Warp_Speed"),
    XL_PARAM_FLOAT_VC("E_SLIDER_Warp_Frequency", "Frequency", "Cycles",
                      0, 200, 20, 10, "E_VALUECURVE_Warp_Frequency"),
    XL_PARAM_END
};

static const char * const kWarpGroups[] = { "Basic", "Position", "Cycles", NULL };

// --------------------------------------------------------------------------
// Wave Effect
// --------------------------------------------------------------------------
static const XLParameterDef kWaveParameters[] = {
    XL_PARAM_CHOICE("E_CHOICE_Wave_Type", "Type", "Basic",
                    kWaveTypeChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Wave_Direction", "Direction", "Basic",
                    kWaveDirectionChoices, 0),
    XL_PARAM_CHOICE("E_CHOICE_Wave_Fill_Colors", "Fill", "Basic",
                    kWaveFillChoices, 0),
    XL_PARAM_INT_VC("E_SLIDER_Number_Waves", "Number of Waves", "Basic",
                    1, 3600, 900, "E_VALUECURVE_Number_Waves"),
    XL_PARAM_INT_VC("E_SLIDER_Wave_Thickness", "Thickness", "Basic",
                    0, 100, 5, "E_VALUECURVE_Wave_Thickness"),
    XL_PARAM_INT_VC("E_SLIDER_Wave_Height", "Height", "Size",
                    0, 100, 50, "E_VALUECURVE_Wave_Height"),
    XL_PARAM_INT_VC("E_SLIDER_Wave_Speed", "Speed", "Motion",
                    0, 50, 10, "E_VALUECURVE_Wave_Speed"),
    XL_PARAM_INT_VC("E_SLIDER_Wave_YOffset", "Y Offset", "Position",
                    -250, 250, 0, "E_VALUECURVE_Wave_YOffset"),
    XL_PARAM_BOOL("E_CHECKBOX_Wave_Mirror", "Mirror", "Options", 0),
    XL_PARAM_END
};

static const char * const kWaveGroups[] = { "Basic", "Size", "Motion", "Position", "Options", NULL };


// ============================================================================
// MARK: - Additional Effects (Arpeggio, Duplicate, Guitar, MovingHead, Piano, Sketch)
// ============================================================================

// --------------------------------------------------------------------------
// Arpeggio Effect
// --------------------------------------------------------------------------
static const XLParameterDef kArpeggioParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Arpeggio_BPM", "BPM", "Basic",
                    1, 300, 120, "E_VALUECURVE_Arpeggio_BPM"),
    XL_PARAM_INT_VC("E_SLIDER_Arpeggio_Steps", "Steps", "Basic",
                    1, 16, 8, "E_VALUECURVE_Arpeggio_Steps"),
    XL_PARAM_INT_VC("E_SLIDER_Arpeggio_StartNote", "Start Note", "Range",
                    0, 127, 36, "E_VALUECURVE_Arpeggio_StartNote"),
    XL_PARAM_INT_VC("E_SLIDER_Arpeggio_EndNote", "End Note", "Range",
                    0, 127, 84, "E_VALUECURVE_Arpeggio_EndNote"),
    XL_PARAM_END
};

static const char * const kArpeggioGroups[] = { "Basic", "Range", NULL };

// --------------------------------------------------------------------------
// Duplicate Effect
// --------------------------------------------------------------------------
static const XLParameterDef kDuplicateParameters[] = {
    // Duplicate effect just references another effect
    XL_PARAM_END
};

static const char * const kDuplicateGroups[] = { NULL };

// --------------------------------------------------------------------------
// Guitar Effect
// --------------------------------------------------------------------------
static const XLParameterDef kGuitarParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Guitar_Strings", "Strings", "Basic",
                    1, 12, 6, "E_VALUECURVE_Guitar_Strings"),
    XL_PARAM_INT_VC("E_SLIDER_Guitar_StringType", "String Type", "Basic",
                    0, 10, 0, "E_VALUECURVE_Guitar_StringType"),
    XL_PARAM_INT_VC("E_SLIDER_Guitar_MaxFrets", "Max Frets", "Basic",
                    1, 30, 20, "E_VALUECURVE_Guitar_MaxFrets"),
    XL_PARAM_END
};

static const char * const kGuitarGroups[] = { "Basic", NULL };

// --------------------------------------------------------------------------
// MovingHead Effect
// --------------------------------------------------------------------------
static const XLParameterDef kMovingHeadParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_MHead_Pan", "Pan", "Position",
                    0, 540, 270, "E_VALUECURVE_MHead_Pan"),
    XL_PARAM_INT_VC("E_SLIDER_MHead_Tilt", "Tilt", "Position",
                    0, 270, 135, "E_VALUECURVE_MHead_Tilt"),
    XL_PARAM_INT_VC("E_SLIDER_MHead_GroupingsCount", "Groupings Count", "Options",
                    1, 8, 1, "E_VALUECURVE_MHead_GroupingsCount"),
    XL_PARAM_BOOL("E_CHECKBOX_MHead_Use16BitPan", "16 Bit Pan", "Options", 0),
    XL_PARAM_BOOL("E_CHECKBOX_MHead_Use16BitTilt", "16 Bit Tilt", "Options", 0),
    XL_PARAM_END
};

static const char * const kMovingHeadGroups[] = { "Position", "Options", NULL };

// --------------------------------------------------------------------------
// Piano Effect
// --------------------------------------------------------------------------
static const XLParameterDef kPianoParameters[] = {
    XL_PARAM_INT_VC("E_SLIDER_Piano_StartMIDI", "Start MIDI", "Range",
                    0, 127, 36, "E_VALUECURVE_Piano_StartMIDI"),
    XL_PARAM_INT_VC("E_SLIDER_Piano_EndMIDI", "End MIDI", "Range",
                    0, 127, 84, "E_VALUECURVE_Piano_EndMIDI"),
    XL_PARAM_BOOL("E_CHECKBOX_Piano_ShowSharps", "Show Sharps", "Options", 1),
    XL_PARAM_END
};

static const char * const kPianoGroups[] = { "Range", "Options", NULL };

// --------------------------------------------------------------------------
// Sketch Effect
// --------------------------------------------------------------------------
static const XLParameterDef kSketchParameters[] = {
    XL_PARAM_FILE("E_FILEPICKERCTRL_Sketch_Filename", "Sketch File", "Basic", "xsketch"),
    XL_PARAM_INT_VC("E_SLIDER_Sketch_Thickness", "Thickness", "Basic",
                    1, 50, 3, "E_VALUECURVE_Sketch_Thickness"),
    XL_PARAM_FLOAT_VC("E_SLIDER_Sketch_MotionPercentage", "Progress", "Motion",
                      0, 100, 100, 1, "E_VALUECURVE_Sketch_MotionPercentage"),
    XL_PARAM_BOOL("E_CHECKBOX_Sketch_DrawMode", "Draw Mode", "Options", 0),
    XL_PARAM_END
};

static const char * const kSketchGroups[] = { "Basic", "Motion", "Options", NULL };


// ============================================================================
// MARK: - Effect Panel Definitions Registry
// ============================================================================

// Master array of all effect panel definitions
static const XLEffectPanelDef kEffectPanelDefs[] = {
    // Basic effects
    { "Off", "Turns off the element", kOffParameters, kOffGroups, NO, NULL },
    { "On", "Turns on the element with intensity control", kOnParameters, kOnGroups, NO, NULL },
    { "Adjust", "Adjust brightness, contrast, saturation, hue, and value", kAdjustParameters, kAdjustGroups, NO, NULL },
    { "Arpeggio", "Musical arpeggio effect", kArpeggioParameters, kArpeggioGroups, NO, NULL },

    // Standard effects (alphabetical)
    { "Bars", "Moving bars effect", kBarsParameters, kBarsGroups, NO, NULL },
    { "Butterfly", "Butterfly pattern effect", kButterflyParameters, kButterflyGroups, NO, NULL },
    { "Candle", "Candle flame simulation", kCandleParameters, kCandleGroups, NO, NULL },
    { "Circles", "Bouncing circles effect", kCirclesParameters, kCirclesGroups, NO, NULL },
    { "ColorWash", "Color wash gradient effect", kColorWashParameters, kColorWashGroups, NO, NULL },
    { "Curtain", "Curtain open/close effect", kCurtainParameters, kCurtainGroups, NO, NULL },
    { "DMX", "Direct DMX channel control", kDMXParameters, kDMXGroups, YES, "XLDMXPanelViewController" },
    { "Duplicate", "Duplicates another effect", kDuplicateParameters, kDuplicateGroups, YES, "XLDuplicatePanelViewController" },

    // F-G effects
    { "Faces", "Lip sync face animation", kFacesParameters, kFacesGroups, YES, "XLFacesPanelViewController" },
    { "Fan", "Rotating fan blade effect", kFanParameters, kFanGroups, NO, NULL },
    { "Fill", "Fills from one end", kFillParameters, kFillGroups, NO, NULL },
    { "Fire", "Fire simulation effect", kFireParameters, kFireGroups, NO, NULL },
    { "Fireworks", "Fireworks explosion effect", kFireworksParameters, kFireworksGroups, NO, NULL },
    { "Galaxy", "Galaxy spiral effect", kGalaxyParameters, kGalaxyGroups, NO, NULL },
    { "Garlands", "Garland pattern effect", kGarlandsParameters, kGarlandsGroups, NO, NULL },
    { "Glediator", "Glediator file playback", kGlediatorParameters, kGlediatorGroups, NO, NULL },
    { "Guitar", "Guitar visualization", kGuitarParameters, kGuitarGroups, NO, NULL },

    // K-M effects
    { "Kaleidoscope", "Kaleidoscope mirror effect", kKaleidoscopeParameters, kKaleidoscopeGroups, NO, NULL },
    { "Life", "Conway's Game of Life", kLifeParameters, kLifeGroups, NO, NULL },
    { "Lightning", "Lightning bolt effect", kLightningParameters, kLightningGroups, NO, NULL },
    { "Lines", "Moving lines effect", kLinesParameters, kLinesGroups, NO, NULL },
    { "Liquid", "Liquid particle simulation", kLiquidParameters, kLiquidGroups, NO, NULL },
    { "Marquee", "Marquee chase lights", kMarqueeParameters, kMarqueeGroups, NO, NULL },
    { "Meteors", "Falling meteors effect", kMeteorsParameters, kMeteorsGroups, NO, NULL },
    { "Morph", "Morphing shape effect", kMorphParameters, kMorphGroups, NO, NULL },
    { "MovingHead", "Moving head fixture control", kMovingHeadParameters, kMovingHeadGroups, NO, NULL },
    { "Music", "Music visualization effect", kMusicParameters, kMusicGroups, NO, NULL },

    // P-R effects
    { "Piano", "Piano key visualization", kPianoParameters, kPianoGroups, NO, NULL },
    { "Pictures", "Image display effect", kPicturesParameters, kPicturesGroups, YES, "XLPicturesPanelViewController" },
    { "Pinwheel", "Spinning pinwheel effect", kPinwheelParameters, kPinwheelGroups, NO, NULL },
    { "Plasma", "Plasma pattern effect", kPlasmaParameters, kPlasmaGroups, NO, NULL },
    { "Ripple", "Expanding ripple effect", kRippleParameters, kRippleGroups, NO, NULL },

    // S effects
    { "Servo", "Servo motor control", kServoParameters, kServoGroups, NO, NULL },
    { "Shader", "GPU shader effect", kShaderParameters, kShaderGroups, YES, "XLShaderPanelViewController" },
    { "Shape", "Geometric shape effect", kShapeParameters, kShapeGroups, NO, NULL },
    { "Shimmer", "Shimmer/blink effect", kShimmerParameters, kShimmerGroups, NO, NULL },
    { "Shockwave", "Expanding shockwave effect", kShockwaveParameters, kShockwaveGroups, NO, NULL },
    { "SingleStrand", "Single strand chase effect", kSingleStrandParameters, kSingleStrandGroups, NO, NULL },
    { "Sketch", "Sketch drawing effect", kSketchParameters, kSketchGroups, NO, NULL },
    { "Snowflakes", "Falling snowflakes effect", kSnowflakesParameters, kSnowflakesGroups, NO, NULL },
    { "Snowstorm", "Snowstorm effect", kSnowstormParameters, kSnowstormGroups, NO, NULL },
    { "Spirals", "Spiral pattern effect", kSpiralsParameters, kSpiralsGroups, NO, NULL },
    { "Spirograph", "Spirograph drawing effect", kSpirographParameters, kSpirographGroups, NO, NULL },
    { "State", "State machine effect", kStateParameters, kStateGroups, YES, "XLStatePanelViewController" },
    { "Strobe", "Strobe light effect", kStrobeParameters, kStrobeGroups, NO, NULL },

    // T-W effects
    { "Tendril", "Tendril wave effect", kTendrilParameters, kTendrilGroups, NO, NULL },
    { "Text", "Text display effect", kTextParameters, kTextGroups, YES, "XLTextPanelViewController" },
    { "Tree", "Christmas tree effect", kTreeParameters, kTreeGroups, NO, NULL },
    { "Twinkle", "Twinkling lights effect", kTwinkleParameters, kTwinkleGroups, NO, NULL },
    { "Video", "Video playback effect", kVideoParameters, kVideoGroups, YES, "XLVideoPanelViewController" },
    { "VUMeter", "Audio VU meter visualization", kVUMeterParameters, kVUMeterGroups, NO, NULL },
    { "Warp", "Image warp effect", kWarpParameters, kWarpGroups, NO, NULL },
    { "Wave", "Wave pattern effect", kWaveParameters, kWaveGroups, NO, NULL },

    // Sentinel
    { NULL, NULL, NULL, NULL, NO, NULL }
};

// ============================================================================
// MARK: - XLEffectPanelRegistry Implementation
// ============================================================================

@implementation XLEffectPanelRegistry {
    NSMutableDictionary<NSString *, NSValue *> *_definitionMap;
    NSArray<NSString *> *_effectNames;
}

+ (instancetype)sharedRegistry {
    static XLEffectPanelRegistry *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[XLEffectPanelRegistry alloc] initPrivate];
    });
    return instance;
}

- (instancetype)init {
    // Use sharedRegistry instead
    return [XLEffectPanelRegistry sharedRegistry];
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        [self buildIndex];
    }
    return self;
}

- (void)buildIndex {
    _definitionMap = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *names = [NSMutableArray array];

    for (size_t i = 0; kEffectPanelDefs[i].effectName != NULL; i++) {
        NSString *name = [NSString stringWithUTF8String:kEffectPanelDefs[i].effectName];
        // Store pointer to definition as NSValue
        NSValue *ptrValue = [NSValue valueWithPointer:&kEffectPanelDefs[i]];
        _definitionMap[name] = ptrValue;
        [names addObject:name];
    }

    // Sort names alphabetically
    _effectNames = [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (const XLEffectPanelDef *)definitionForEffect:(NSString *)effectName {
    NSValue *ptrValue = _definitionMap[effectName];
    if (!ptrValue) {
        return NULL;
    }
    return (const XLEffectPanelDef *)[ptrValue pointerValue];
}

- (NSArray<NSString *> *)allEffectNames {
    return _effectNames;
}

- (NSUInteger)effectCount {
    return _effectNames.count;
}

- (BOOL)hasDefinitionForEffect:(NSString *)effectName {
    return _definitionMap[effectName] != nil;
}

@end
