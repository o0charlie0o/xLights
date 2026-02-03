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

#import <Cocoa/Cocoa.h>
#import "XLEffectPanelDefinitions.h"

@class XLEngineBridge;

NS_ASSUME_NONNULL_BEGIN

/// Delegate protocol for effect panel parameter changes.
@protocol XLEffectPanelViewDelegate <NSObject>
@optional
/// Called when a parameter value changes.
/// @param effectName The effect type name.
/// @param key The parameter key.
/// @param value The new value as a string.
- (void)effectPanel:(NSString *)effectName didChangeParameter:(NSString *)key value:(NSString *)value;

/// Called when the user requests to edit a value curve.
/// @param effectName The effect type name.
/// @param key The parameter key.
- (void)effectPanel:(NSString *)effectName editValueCurveForParameter:(NSString *)key;

/// Called when the user locks/unlocks a parameter.
/// @param effectName The effect type name.
/// @param key The parameter key.
/// @param locked Whether the parameter is now locked.
- (void)effectPanel:(NSString *)effectName didLockParameter:(NSString *)key locked:(BOOL)locked;
@end


/// A view that displays effect parameters from an XLEffectPanelDef.
/// Automatically generates appropriate controls based on parameter types.
///
/// This class creates a scrollable stack view containing:
/// - Disclosure groups for each parameter group
/// - Slider + text field combos for numeric parameters
/// - Switches for boolean parameters
/// - Popup buttons for choice parameters
/// - Color wells for color parameters
/// - Text fields for string parameters
/// - File pickers for file parameters
/// - Value curve buttons where applicable
/// - Lock buttons for lockable parameters
@interface XLEffectPanelView : NSView

/// The current effect ID being edited (0 = no effect selected).
@property (nonatomic, assign) NSInteger effectId;

/// The engine bridge for getting/setting effect parameters.
@property (nonatomic, weak, nullable) XLEngineBridge *engineBridge;

/// Delegate for parameter change callbacks.
@property (nonatomic, weak, nullable) id<XLEffectPanelViewDelegate> delegate;

/// Load and display controls for the specified effect type.
/// @param effectName The effect type name (e.g., "Bars", "Fire").
- (void)loadEffectPanel:(NSString *)effectName;

/// Update all controls from the current effect's settings.
/// Call this after changing effectId to refresh displayed values.
- (void)refreshFromEffect;

/// Get the currently loaded effect name.
- (NSString * _Nullable)currentEffectName;

/// Clear all controls (show empty panel).
- (void)clearPanel;

@end

NS_ASSUME_NONNULL_END
