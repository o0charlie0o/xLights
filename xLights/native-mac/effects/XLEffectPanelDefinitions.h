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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Parameter types for effect controls.
/// These map to AppKit controls:
///   Int -> NSSlider + NSTextField (linked)
///   Float -> NSSlider + NSTextField (linked, with decimal)
///   Bool -> NSSwitch
///   Choice -> NSPopUpButton
///   Color -> NSColorWell
///   String -> NSTextField
///   File -> NSTextField + Browse button
///   Font -> NSFontPanel button
///   ValueCurve -> Custom curve editor button
///   ColorCurve -> Custom color curve editor button
typedef NS_ENUM(NSInteger, XLParameterType) {
    XLParameterTypeInt = 0,
    XLParameterTypeFloat,
    XLParameterTypeBool,
    XLParameterTypeChoice,
    XLParameterTypeColor,
    XLParameterTypeString,
    XLParameterTypeFile,
    XLParameterTypeFont,
    XLParameterTypeValueCurve,
    XLParameterTypeColorCurve
};

/// Flags for parameter behavior.
typedef NS_OPTIONS(NSUInteger, XLParameterFlags) {
    XLParameterFlagsNone = 0,
    XLParameterFlagsSupportsValueCurve = 1 << 0,
    XLParameterFlagsLockable = 1 << 1,
    XLParameterFlagsHidden = 1 << 2,           // Hidden by default (shown conditionally)
    XLParameterFlagsReadOnly = 1 << 3,         // Display only, not editable
    XLParameterFlagsRequired = 1 << 4,         // Must have a value
};

/// A single parameter definition.
/// Uses C types for heap-safety in hot paths.
typedef struct {
    const char *key;              // SettingsMap key (e.g. "E_SLIDER_Bars_BarCount")
    const char *displayLabel;     // Human-readable label (e.g. "Palette Rep")
    const char *group;            // Group name for panel sections (e.g. "Basic", "Options")
    const char *tooltip;          // Tooltip text (nullable)

    XLParameterType type;
    XLParameterFlags flags;

    // Numeric range (for Int and Float types)
    double minValue;
    double maxValue;
    double defaultValue;
    int divisor;                  // For scaled float values (slider value / divisor = actual value)

    // Choice list (for Choice type) - NULL-terminated array of strings
    const char * _Nullable const * _Nullable choices;
    int defaultChoiceIndex;

    // Default string value (for String, Color, File, Font types)
    const char * _Nullable defaultString;

    // Value curve key (if supportsValueCurve)
    const char * _Nullable valueCurveKey;

    // File filter (for File type, e.g. "png,jpg,gif")
    const char * _Nullable fileFilter;

    // Conditional visibility key (show when this key's value matches conditionValue)
    const char * _Nullable conditionKey;
    const char * _Nullable conditionValue;

    // Sort order within group (lower = earlier)
    int sortOrder;
} XLParameterDef;

/// An effect panel definition.
/// Contains all parameters for a single effect type.
typedef struct {
    const char *effectName;       // Effect name (e.g. "Bars", "Fire")
    const char *effectTooltip;    // Effect description

    // Parameter array - terminated by entry with NULL key
    const XLParameterDef *parameters;

    // Group names in display order - NULL-terminated array
    const char * _Nullable const * _Nullable groupOrder;

    // Special flags for effects requiring custom UI
    BOOL needsCustomPanel;        // Effect needs custom panel beyond standard controls
    const char * _Nullable customPanelClass;  // Objective-C class name for custom panel
} XLEffectPanelDef;

/// Registry of all effect panel definitions.
/// Provides fast lookup by effect name.
@interface XLEffectPanelRegistry : NSObject

/// Shared singleton instance.
+ (instancetype)sharedRegistry;

/// Get the panel definition for an effect type.
/// @param effectName The effect name (e.g. "Bars", "Fire")
/// @return The panel definition, or NULL if not found.
- (const XLEffectPanelDef * _Nullable)definitionForEffect:(NSString *)effectName;

/// Get all registered effect names.
/// @return Array of effect names in alphabetical order.
- (NSArray<NSString *> *)allEffectNames;

/// Get the number of registered effects.
- (NSUInteger)effectCount;

/// Check if an effect has a registered panel definition.
- (BOOL)hasDefinitionForEffect:(NSString *)effectName;

@end

// Convenience macros for defining parameters

/// Define an integer slider parameter with value curve support.
#define XL_PARAM_INT_VC(key, label, group, min, max, def, vcKey) \
    { key, label, group, NULL, XLParameterTypeInt, \
      XLParameterFlagsSupportsValueCurve | XLParameterFlagsLockable, \
      min, max, def, 1, NULL, 0, NULL, vcKey, NULL, NULL, NULL, 0 }

/// Define an integer slider parameter without value curve.
#define XL_PARAM_INT(key, label, group, min, max, def) \
    { key, label, group, NULL, XLParameterTypeInt, \
      XLParameterFlagsLockable, \
      min, max, def, 1, NULL, 0, NULL, NULL, NULL, NULL, NULL, 0 }

/// Define a float slider parameter with value curve support.
#define XL_PARAM_FLOAT_VC(key, label, group, min, max, def, div, vcKey) \
    { key, label, group, NULL, XLParameterTypeFloat, \
      XLParameterFlagsSupportsValueCurve | XLParameterFlagsLockable, \
      min, max, def, div, NULL, 0, NULL, vcKey, NULL, NULL, NULL, 0 }

/// Define a float slider parameter without value curve.
#define XL_PARAM_FLOAT(key, label, group, min, max, def, div) \
    { key, label, group, NULL, XLParameterTypeFloat, \
      XLParameterFlagsLockable, \
      min, max, def, div, NULL, 0, NULL, NULL, NULL, NULL, NULL, 0 }

/// Define a boolean checkbox parameter.
#define XL_PARAM_BOOL(key, label, group, def) \
    { key, label, group, NULL, XLParameterTypeBool, \
      XLParameterFlagsLockable, \
      0, 1, def, 1, NULL, 0, NULL, NULL, NULL, NULL, NULL, 0 }

/// Define a choice (dropdown) parameter.
#define XL_PARAM_CHOICE(key, label, group, choiceList, defIdx) \
    { key, label, group, NULL, XLParameterTypeChoice, \
      XLParameterFlagsLockable, \
      0, 0, 0, 1, choiceList, defIdx, NULL, NULL, NULL, NULL, NULL, 0 }

/// Define a string text field parameter.
#define XL_PARAM_STRING(key, label, group, defVal) \
    { key, label, group, NULL, XLParameterTypeString, \
      XLParameterFlagsLockable, \
      0, 0, 0, 1, NULL, 0, defVal, NULL, NULL, NULL, NULL, 0 }

/// Define a color parameter.
#define XL_PARAM_COLOR(key, label, group, defVal) \
    { key, label, group, NULL, XLParameterTypeColor, \
      XLParameterFlagsLockable, \
      0, 0, 0, 1, NULL, 0, defVal, NULL, NULL, NULL, NULL, 0 }

/// Define a file picker parameter.
#define XL_PARAM_FILE(key, label, group, filter) \
    { key, label, group, NULL, XLParameterTypeFile, \
      XLParameterFlagsLockable, \
      0, 0, 0, 1, NULL, 0, NULL, NULL, filter, NULL, NULL, 0 }

/// Define a font picker parameter.
#define XL_PARAM_FONT(key, label, group) \
    { key, label, group, NULL, XLParameterTypeFont, \
      XLParameterFlagsLockable, \
      0, 0, 0, 1, NULL, 0, NULL, NULL, NULL, NULL, NULL, 0 }

/// Sentinel value to mark end of parameter array.
#define XL_PARAM_END \
    { NULL, NULL, NULL, NULL, XLParameterTypeInt, XLParameterFlagsNone, \
      0, 0, 0, 1, NULL, 0, NULL, NULL, NULL, NULL, NULL, 0 }

NS_ASSUME_NONNULL_END
