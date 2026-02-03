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
#import "setup/XLControllersViewController.h"

@class XLEngineBridge;

/// View controller for the Setup tab.
///
/// Displays controller list, port configuration, and network discovery.
/// This is the simplest of the three main tabs — mostly table views and forms.
/// The controller list occupies the left region of a split view; the right
/// region will hold the controller detail inspector (ticket 2B).
@interface XLSetupViewController : NSViewController <XLControllersViewDelegate>

@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Controller list view controller (left panel).
@property (nonatomic, strong, readonly) XLControllersViewController *controllersViewController;

@end
