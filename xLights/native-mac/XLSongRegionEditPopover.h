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

/// Completion block called when the popover is dismissed.
/// name and color reflect the edited values.
typedef void (^XLSongRegionEditCompletion)(NSString *name, NSColor *color);

/// Simple popover for editing a song structure region's name and color.
@interface XLSongRegionEditPopover : NSViewController

/// Show the popover anchored to the given rect in the specified view.
/// @param rect Anchoring rectangle (in view coordinates)
/// @param view The view to anchor to
/// @param name Current region name
/// @param color Current region color
/// @param completion Called when the user dismisses or confirms the edit
+ (void)showRelativeToRect:(NSRect)rect
                    ofView:(NSView *)view
                  withName:(NSString *)name
                     color:(NSColor *)color
                completion:(XLSongRegionEditCompletion)completion;

@end
