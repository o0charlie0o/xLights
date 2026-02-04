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

/// View controller for the Color Palette panel.
///
/// This controller manages the color palette editing UI for effects. It displays:
/// - 8 palette color swatches with enable/disable toggles
/// - Brightness and contrast sliders
/// - HSV color adjustment sliders (hue, saturation, value)
/// - Sparkle frequency and music sparkle controls
///
/// The panel listens for effect selection changes and updates accordingly.
@interface XLColorPaletteViewController : NSViewController

/// The engine bridge for getting/setting color parameters.
@property (nonatomic, weak, nullable) XLEngineBridge *engineBridge;

/// Reload colors from the currently selected effect.
- (void)reloadColors;

@end

NS_ASSUME_NONNULL_END
