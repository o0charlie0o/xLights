/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLBaseSheetController.h"

NS_ASSUME_NONNULL_BEGIN

/// Native macOS color picker dialog with extended features.
///
/// Wraps NSColorPanel with additional xLights-specific functionality:
/// - HSV and RGB value display
/// - Brightness presets
/// - Color history
@interface XLColorDialog : XLBaseSheetController

/// The selected color
@property (nonatomic, strong) NSColor *color;

/// Whether to show brightness presets (default: YES)
@property (nonatomic, assign) BOOL showBrightnessPresets;

/// Whether to show color history (default: YES)
@property (nonatomic, assign) BOOL showColorHistory;

/// Add a color to the history
+ (void)addColorToHistory:(NSColor *)color;

/// Get the color history (most recent first)
+ (NSArray<NSColor *> *)colorHistory;

@end

NS_ASSUME_NONNULL_END
