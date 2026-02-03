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
#import "XLEffectPanelDescriptor.h"

@class XLEffectPanelBuilder;

/// Delegate protocol for receiving control value changes from a built effect panel.
@protocol XLEffectPanelBuilderDelegate <NSObject>

/// Called when a control value changes (slider moved, checkbox toggled, etc.).
/// @param builder The builder instance that owns the panel.
/// @param key The settings dictionary key for the changed parameter.
/// @param value The new value (NSNumber for sliders/checkboxes, NSString for popups/text).
- (void)effectPanelBuilder:(XLEffectPanelBuilder *)builder
      didChangeValueForKey:(NSString *)key
                     value:(id)value;

/// Called when the user clicks the value curve button on a slider.
/// @param builder The builder instance that owns the panel.
/// @param key The settings dictionary key for the parameter.
- (void)effectPanelBuilder:(XLEffectPanelBuilder *)builder
    didRequestValueCurveForKey:(NSString *)key;

@optional

/// Called when the user clicks the bulk-edit lock button on a control.
/// @param builder The builder instance that owns the panel.
/// @param key The settings dictionary key for the parameter.
- (void)effectPanelBuilder:(XLEffectPanelBuilder *)builder
    didToggleBulkEditForKey:(NSString *)key;

@end

/// Builds a native AppKit view hierarchy from an XLEffectPanelDescriptor.
///
/// The builder creates an NSStackView containing rows of label + control pairs,
/// grouped by optional disclosure sections. It supports two-way binding between
/// a settings dictionary and the built controls.
///
/// Usage:
/// @code
///   XLEffectPanelBuilder *builder = [[XLEffectPanelBuilder alloc] init];
///   builder.delegate = self;
///   NSView *panel = [builder buildPanelForDescriptor:descriptor settings:initialSettings];
///   [containerView addSubview:panel];
/// @endcode
@interface XLEffectPanelBuilder : NSObject

/// Delegate that receives value change and value curve request callbacks.
@property (nonatomic, weak) id<XLEffectPanelBuilderDelegate> delegate;

/// Build an effect panel view from a descriptor with initial settings.
/// @param descriptor The effect panel descriptor defining parameters.
/// @param settings Initial settings dictionary to populate controls.
/// @return A fully configured NSView containing all controls.
- (NSView *)buildPanelForDescriptor:(XLEffectPanelDescriptor *)descriptor
                           settings:(NSDictionary<NSString *, id> *)settings;

/// Update controls from a settings dictionary (settings -> controls direction).
/// Only updates controls whose keys appear in the dictionary.
/// @param settings Dictionary of key-value pairs to apply to controls.
- (void)updateControlsFromSettings:(NSDictionary<NSString *, id> *)settings;

/// Extract current settings from all controls (controls -> settings direction).
/// @return Dictionary of all parameter key-value pairs from current control states.
- (NSDictionary<NSString *, id> *)currentSettings;

@end
