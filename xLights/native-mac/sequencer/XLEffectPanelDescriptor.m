/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLEffectPanelDescriptor.h"

// ---------------------------------------------------------------------------
// MARK: - XLEffectParamDescriptor
// ---------------------------------------------------------------------------

@implementation XLEffectParamDescriptor

+ (instancetype)sliderWithKey:(NSString *)key
                         name:(NSString *)name
                          min:(CGFloat)min
                          max:(CGFloat)max
                 defaultValue:(CGFloat)def
{
    return [self sliderWithKey:key name:name min:min max:max defaultValue:def divisor:1];
}

+ (instancetype)sliderWithKey:(NSString *)key
                         name:(NSString *)name
                          min:(CGFloat)min
                          max:(CGFloat)max
                 defaultValue:(CGFloat)def
                      divisor:(CGFloat)divisor
{
    XLEffectParamDescriptor *desc = [[XLEffectParamDescriptor alloc] init];
    desc.key = key;
    desc.displayName = name;
    desc.type = XLEffectParamTypeSlider;
    desc.minValue = min;
    desc.maxValue = max;
    desc.defaultValue = def;
    desc.divisor = divisor;
    desc.supportsValueCurve = YES;
    desc.supportsBulkEdit = YES;
    return desc;
}

+ (instancetype)checkboxWithKey:(NSString *)key
                           name:(NSString *)name
                   defaultValue:(BOOL)def
{
    XLEffectParamDescriptor *desc = [[XLEffectParamDescriptor alloc] init];
    desc.key = key;
    desc.displayName = name;
    desc.type = XLEffectParamTypeCheckbox;
    desc.defaultChecked = def;
    desc.supportsBulkEdit = YES;
    return desc;
}

+ (instancetype)popupWithKey:(NSString *)key
                        name:(NSString *)name
                       items:(NSArray<NSString *> *)items
                defaultIndex:(NSInteger)idx
{
    XLEffectParamDescriptor *desc = [[XLEffectParamDescriptor alloc] init];
    desc.key = key;
    desc.displayName = name;
    desc.type = XLEffectParamTypePopupMenu;
    desc.menuItems = items;
    desc.defaultIndex = idx;
    desc.supportsBulkEdit = YES;
    return desc;
}

+ (instancetype)colorPickerWithKey:(NSString *)key
                              name:(NSString *)name
{
    XLEffectParamDescriptor *desc = [[XLEffectParamDescriptor alloc] init];
    desc.key = key;
    desc.displayName = name;
    desc.type = XLEffectParamTypeColorPicker;
    desc.supportsBulkEdit = YES;
    return desc;
}

+ (instancetype)textFieldWithKey:(NSString *)key
                            name:(NSString *)name
{
    XLEffectParamDescriptor *desc = [[XLEffectParamDescriptor alloc] init];
    desc.key = key;
    desc.displayName = name;
    desc.type = XLEffectParamTypeTextField;
    desc.supportsBulkEdit = YES;
    return desc;
}

+ (instancetype)filePickerWithKey:(NSString *)key
                             name:(NSString *)name
{
    XLEffectParamDescriptor *desc = [[XLEffectParamDescriptor alloc] init];
    desc.key = key;
    desc.displayName = name;
    desc.type = XLEffectParamTypeFilePicker;
    desc.supportsBulkEdit = YES;
    return desc;
}

+ (instancetype)labelWithName:(NSString *)name
{
    XLEffectParamDescriptor *desc = [[XLEffectParamDescriptor alloc] init];
    desc.displayName = name;
    desc.type = XLEffectParamTypeLabel;
    return desc;
}

+ (instancetype)spacer
{
    XLEffectParamDescriptor *desc = [[XLEffectParamDescriptor alloc] init];
    desc.type = XLEffectParamTypeSpacer;
    return desc;
}

@end

// ---------------------------------------------------------------------------
// MARK: - XLEffectPanelDescriptor
// ---------------------------------------------------------------------------

static NSMutableDictionary<NSString *, XLEffectPanelDescriptor *> *sDescriptorRegistry = nil;

@implementation XLEffectPanelDescriptor

+ (void)initialize
{
    if (self == [XLEffectPanelDescriptor class]) {
        sDescriptorRegistry = [NSMutableDictionary dictionary];
        [self registerBuiltInDescriptors];
    }
}

+ (void)registerDescriptor:(XLEffectPanelDescriptor *)descriptor
{
    if (descriptor.effectName.length > 0) {
        sDescriptorRegistry[descriptor.effectName] = descriptor;
    }
}

+ (instancetype)descriptorForEffect:(NSString *)effectName
{
    return sDescriptorRegistry[effectName];
}

// ---------------------------------------------------------------------------
// MARK: - Built-in effect descriptors
// ---------------------------------------------------------------------------

+ (void)registerBuiltInDescriptors
{
    [self registerDescriptor:[self barsDescriptor]];
    [self registerDescriptor:[self colorWashDescriptor]];
    [self registerDescriptor:[self fireDescriptor]];
}

// ---------------------------------------------------------------------------
// Bars Effect
//
// Based on BarsPanel.wxs / BarsPanel.cpp / BarsEffect.h:
//   Palette Rep (slider 1-5, VC), Cycles (slider 0-300, div 10, VC),
//   Direction (popup, 14 items), Center Point (slider -100 to 100, VC),
//   Highlight (checkbox), Use First Color for Highlight (checkbox),
//   3D (checkbox), Gradient (checkbox)
// ---------------------------------------------------------------------------

+ (XLEffectPanelDescriptor *)barsDescriptor
{
    XLEffectPanelDescriptor *desc = [[XLEffectPanelDescriptor alloc] init];
    desc.effectName = @"Bars";

    XLEffectParamDescriptor *paletteRep =
        [XLEffectParamDescriptor sliderWithKey:@"E_SLIDER_Bars_BarCount"
                                          name:@"Palette Rep"
                                           min:1 max:5 defaultValue:1];

    XLEffectParamDescriptor *cycles =
        [XLEffectParamDescriptor sliderWithKey:@"E_SLIDER_Bars_Cycles"
                                          name:@"Cycles"
                                           min:0 max:300 defaultValue:10
                                       divisor:10];

    XLEffectParamDescriptor *direction =
        [XLEffectParamDescriptor popupWithKey:@"E_CHOICE_Bars_Direction"
                                        name:@"Direction"
                                       items:@[@"up", @"down", @"expand", @"compress",
                                               @"Left", @"Right", @"H-expand", @"H-compress",
                                               @"Alternate Up", @"Alternate Down",
                                               @"Alternate Left", @"Alternate Right",
                                               @"Custom Horz", @"Custom Vert"]
                                defaultIndex:0];

    XLEffectParamDescriptor *center =
        [XLEffectParamDescriptor sliderWithKey:@"E_SLIDER_Bars_Center"
                                          name:@"Center Point"
                                           min:-100 max:100 defaultValue:0];

    XLEffectParamDescriptor *highlight =
        [XLEffectParamDescriptor checkboxWithKey:@"E_CHECKBOX_Bars_Highlight"
                                            name:@"Highlight"
                                    defaultValue:NO];

    XLEffectParamDescriptor *useFirstColor =
        [XLEffectParamDescriptor checkboxWithKey:@"E_CHECKBOX_Bars_UseFirstColorForHighlight"
                                            name:@"Use First Color for Highlight"
                                    defaultValue:NO];

    XLEffectParamDescriptor *bars3D =
        [XLEffectParamDescriptor checkboxWithKey:@"E_CHECKBOX_Bars_3D"
                                            name:@"3D"
                                    defaultValue:NO];

    XLEffectParamDescriptor *gradient =
        [XLEffectParamDescriptor checkboxWithKey:@"E_CHECKBOX_Bars_Gradient"
                                            name:@"Gradient"
                                    defaultValue:NO];

    desc.parameters = @[paletteRep, cycles, direction, center,
                        [XLEffectParamDescriptor spacer],
                        highlight, useFirstColor, bars3D, gradient];
    return desc;
}

// ---------------------------------------------------------------------------
// Color Wash Effect
//
// Based on ColorWashPanel.cpp / ColorWashEffect.h:
//   Count/Cycles (slider 1-200, div 10, VC), Vertical Fade (checkbox),
//   Horizontal Fade (checkbox), Reverse Fades (checkbox),
//   Shimmer (checkbox), Circular Palette (checkbox)
// ---------------------------------------------------------------------------

+ (XLEffectPanelDescriptor *)colorWashDescriptor
{
    XLEffectPanelDescriptor *desc = [[XLEffectPanelDescriptor alloc] init];
    desc.effectName = @"Color Wash";

    XLEffectParamDescriptor *cycles =
        [XLEffectParamDescriptor sliderWithKey:@"E_SLIDER_ColorWash_Cycles"
                                          name:@"Count"
                                           min:1 max:200 defaultValue:10
                                       divisor:10];

    XLEffectParamDescriptor *vFade =
        [XLEffectParamDescriptor checkboxWithKey:@"E_CHECKBOX_ColorWash_VFade"
                                            name:@"Vertical Fade"
                                    defaultValue:NO];

    XLEffectParamDescriptor *hFade =
        [XLEffectParamDescriptor checkboxWithKey:@"E_CHECKBOX_ColorWash_HFade"
                                            name:@"Horizontal Fade"
                                    defaultValue:NO];

    XLEffectParamDescriptor *reverseFades =
        [XLEffectParamDescriptor checkboxWithKey:@"E_CHECKBOX_ColorWash_ReverseFades"
                                            name:@"Reverse Fades"
                                    defaultValue:NO];
    reverseFades.supportsBulkEdit = NO;

    XLEffectParamDescriptor *shimmer =
        [XLEffectParamDescriptor checkboxWithKey:@"E_CHECKBOX_ColorWash_Shimmer"
                                            name:@"Shimmer"
                                    defaultValue:NO];
    shimmer.supportsBulkEdit = NO;

    XLEffectParamDescriptor *circularPalette =
        [XLEffectParamDescriptor checkboxWithKey:@"E_CHECKBOX_ColorWash_CircularPalette"
                                            name:@"Circular Palette"
                                    defaultValue:NO];
    circularPalette.supportsBulkEdit = NO;

    desc.parameters = @[cycles,
                        [XLEffectParamDescriptor spacer],
                        vFade, hFade, reverseFades,
                        [XLEffectParamDescriptor spacer],
                        shimmer, circularPalette];
    return desc;
}

// ---------------------------------------------------------------------------
// Fire Effect
//
// Based on FirePanel.wxs / FirePanel.cpp / FireEffect.h:
//   Height (slider 1-100, VC), Hue Shift (slider 0-100, VC),
//   Growth Cycles (slider 0-200, div 10, VC),
//   Grow with music (checkbox),
//   Location (popup: Bottom, Top, Left, Right)
// ---------------------------------------------------------------------------

+ (XLEffectPanelDescriptor *)fireDescriptor
{
    XLEffectPanelDescriptor *desc = [[XLEffectPanelDescriptor alloc] init];
    desc.effectName = @"Fire";

    XLEffectParamDescriptor *height =
        [XLEffectParamDescriptor sliderWithKey:@"E_SLIDER_Fire_Height"
                                          name:@"Height"
                                           min:1 max:100 defaultValue:50];

    XLEffectParamDescriptor *hueShift =
        [XLEffectParamDescriptor sliderWithKey:@"E_SLIDER_Fire_HueShift"
                                          name:@"Hue Shift"
                                           min:0 max:100 defaultValue:0];

    XLEffectParamDescriptor *growthCycles =
        [XLEffectParamDescriptor sliderWithKey:@"E_SLIDER_Fire_GrowthCycles"
                                          name:@"Growth Cycles"
                                           min:0 max:200 defaultValue:0
                                       divisor:10];

    XLEffectParamDescriptor *growWithMusic =
        [XLEffectParamDescriptor checkboxWithKey:@"E_CHECKBOX_Fire_GrowWithMusic"
                                            name:@"Grow with music"
                                    defaultValue:NO];

    XLEffectParamDescriptor *location =
        [XLEffectParamDescriptor popupWithKey:@"E_CHOICE_Fire_Location"
                                        name:@"Location"
                                       items:@[@"Bottom", @"Top", @"Left", @"Right"]
                                defaultIndex:0];
    location.supportsBulkEdit = NO;

    desc.parameters = @[height, hueShift, growthCycles,
                        [XLEffectParamDescriptor spacer],
                        growWithMusic,
                        [XLEffectParamDescriptor spacer],
                        location];
    return desc;
}

@end
