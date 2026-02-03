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

#import <Cocoa/Cocoa.h>

/// Describes the type of UI control for an effect parameter.
typedef NS_ENUM(NSInteger, XLEffectParamType) {
    XLEffectParamTypeSlider,          // NSSlider with optional value curve
    XLEffectParamTypeColorPicker,     // NSColorWell
    XLEffectParamTypeCheckbox,        // NSButton checkbox
    XLEffectParamTypePopupMenu,       // NSPopUpButton
    XLEffectParamTypeTextField,       // NSTextField
    XLEffectParamTypeBitmapButton,    // NSButton with image
    XLEffectParamTypeFilePicker,      // Path text field + browse button
    XLEffectParamTypeColorCurve,      // Color palette picker (for multi-color effects)
    XLEffectParamTypeSpacer,          // Visual separator
    XLEffectParamTypeLabel,           // Static label text
};

/// Describes a single parameter within an effect panel.
///
/// Each descriptor maps to one control row in the built panel. The key
/// corresponds to the settings dictionary key used by the xLights rendering
/// engine (e.g., "E_SLIDER_Bars_BarCount").
@interface XLEffectParamDescriptor : NSObject

/// Settings dictionary key (e.g., "E_SLIDER_Bars_BarCount").
@property (nonatomic, copy) NSString *key;

/// Human-readable label shown next to the control.
@property (nonatomic, copy) NSString *displayName;

/// Type of control to create.
@property (nonatomic, assign) XLEffectParamType type;

/// Minimum value for sliders.
@property (nonatomic, assign) CGFloat minValue;

/// Maximum value for sliders.
@property (nonatomic, assign) CGFloat maxValue;

/// Default value for sliders.
@property (nonatomic, assign) CGFloat defaultValue;

/// Divisor for sliders that represent fractional values (e.g., 10 means slider
/// value of 10 represents 1.0). A value of 0 or 1 means no divisor.
@property (nonatomic, assign) CGFloat divisor;

/// Items for popup menu controls.
@property (nonatomic, strong) NSArray<NSString *> *menuItems;

/// Tooltip text shown on hover.
@property (nonatomic, copy) NSString *toolTip;

/// Whether the slider supports value curves (shows VC button).
@property (nonatomic, assign) BOOL supportsValueCurve;

/// Whether the control supports bulk edit (shows lock icon).
@property (nonatomic, assign) BOOL supportsBulkEdit;

/// Optional group name for disclosure section grouping.
@property (nonatomic, copy) NSString *groupName;

/// Default checkbox state (for checkbox type).
@property (nonatomic, assign) BOOL defaultChecked;

/// Default selected index (for popup menu type).
@property (nonatomic, assign) NSInteger defaultIndex;

/// Default text (for text field type).
@property (nonatomic, copy) NSString *defaultText;

// Convenience constructors

+ (instancetype)sliderWithKey:(NSString *)key
                         name:(NSString *)name
                          min:(CGFloat)min
                          max:(CGFloat)max
                 defaultValue:(CGFloat)def;

+ (instancetype)sliderWithKey:(NSString *)key
                         name:(NSString *)name
                          min:(CGFloat)min
                          max:(CGFloat)max
                 defaultValue:(CGFloat)def
                      divisor:(CGFloat)divisor;

+ (instancetype)checkboxWithKey:(NSString *)key
                           name:(NSString *)name
                   defaultValue:(BOOL)def;

+ (instancetype)popupWithKey:(NSString *)key
                        name:(NSString *)name
                       items:(NSArray<NSString *> *)items
                defaultIndex:(NSInteger)idx;

+ (instancetype)colorPickerWithKey:(NSString *)key
                              name:(NSString *)name;

+ (instancetype)textFieldWithKey:(NSString *)key
                            name:(NSString *)name;

+ (instancetype)filePickerWithKey:(NSString *)key
                             name:(NSString *)name;

+ (instancetype)labelWithName:(NSString *)name;

+ (instancetype)spacer;

@end

/// Describes the full set of parameters for a single effect type.
///
/// Each effect (Bars, Fire, Color Wash, etc.) has one descriptor that defines
/// all the controls shown in its settings panel. The builder uses this to
/// construct the native AppKit view hierarchy.
@interface XLEffectPanelDescriptor : NSObject

/// Name of the effect (e.g., "Bars", "Fire", "Color Wash").
@property (nonatomic, copy) NSString *effectName;

/// Ordered list of parameter descriptors defining the panel layout.
@property (nonatomic, strong) NSArray<XLEffectParamDescriptor *> *parameters;

/// Returns a registered descriptor for the given effect name, or nil if unknown.
+ (instancetype)descriptorForEffect:(NSString *)effectName;

/// Registers a descriptor for later lookup by effect name.
+ (void)registerDescriptor:(XLEffectPanelDescriptor *)descriptor;

@end
