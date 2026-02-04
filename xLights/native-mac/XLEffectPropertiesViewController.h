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

@class XLEngineBridge;

NS_ASSUME_NONNULL_BEGIN

/// Notification posted when an effect is selected in the sequencer.
/// The userInfo dictionary contains:
///   - "effectId": NSNumber with the primary effect ID (-1 = no selection)
///   - "effectType": NSString with the effect type name (nil if no selection)
///   - "selectedEffectIds": NSArray<NSNumber *> of all selected effect IDs (for multi-select)
///   - "selectedEffectTypes": NSArray<NSString *> of effect types for each selected effect
extern NSNotificationName const XLEffectSelectionDidChangeNotification;

/// View controller for the Effect Properties Panel shown at the bottom of the main window.
///
/// This controller manages the effect parameter editing UI. It listens for effect
/// selection changes from the sequencer and dynamically loads the appropriate
/// effect panel based on the selected effect type.
///
/// The panel displays:
/// - Parameter controls (sliders, checkboxes, popups, etc.) for the selected effect
/// - Value curve buttons for animatable parameters
/// - Lock buttons for bulk edit operations
/// - A placeholder message when no effect is selected
@interface XLEffectPropertiesViewController : NSViewController

/// The engine bridge for getting/setting effect parameters.
@property (nonatomic, weak, nullable) XLEngineBridge *engineBridge;

/// The currently selected effect ID (0 = no selection).
@property (nonatomic, readonly) NSInteger selectedEffectId;

/// The currently selected effect type name (nil if no selection).
@property (nonatomic, readonly, nullable) NSString *selectedEffectType;

/// Select an effect by ID. Loads the appropriate panel and refreshes values.
/// @param effectId The effect ID to select, or 0 to clear selection.
- (void)selectEffect:(NSInteger)effectId;

/// Clear the current selection and show placeholder.
- (void)clearSelection;

/// Refresh all parameter values from the engine.
/// Call this after external changes to effect parameters.
- (void)refreshFromEngine;

@end

NS_ASSUME_NONNULL_END
