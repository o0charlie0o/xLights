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

/// View controller for the Setup tab.
///
/// Displays controller list, port configuration, and network discovery.
/// This is the simplest of the three main tabs — mostly table views and forms.
@interface XLSetupViewController : NSViewController

@property (nonatomic, weak) XLEngineBridge *engineBridge;

@end
