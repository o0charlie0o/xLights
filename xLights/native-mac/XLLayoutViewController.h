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

@class XLEngineBridge;

/// View controller for the Layout/Preview tab.
///
/// Displays Metal-based 3D preview, model tree, and manipulation handles.
/// The preview already uses Metal — the main work is replacing the wxWidgets
/// wrapper with native NSView-based Metal view.
@interface XLLayoutViewController : NSViewController

@property (nonatomic, weak) XLEngineBridge *engineBridge;

@end
