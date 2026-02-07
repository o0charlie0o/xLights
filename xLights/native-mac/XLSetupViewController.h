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
#import "setup/XLPortConfigurationView.h"

@class XLEngineBridge;
@class XLControllerInspectorViewController;

/// View controller for the Setup tab.
///
/// Displays controller list, port configuration, and network discovery.
/// Layout is a three-pane split view:
///   - Left: Controller list (XLControllersViewController)
///   - Center: Port configuration grid (XLPortConfigurationView)
///   - Right: Controller inspector (XLControllerInspectorViewController)
@interface XLSetupViewController : NSViewController <XLControllersViewDelegate, XLPortConfigurationViewDelegate>

@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Controller list view controller (left panel).
@property (nonatomic, strong, readonly) XLControllersViewController *controllersViewController;

/// Port configuration view controller (center panel).
@property (nonatomic, strong, readonly) XLPortConfigurationView *portConfigurationView;

/// Controller inspector view controller (right panel).
@property (nonatomic, strong, readonly) XLControllerInspectorViewController *inspectorViewController;

/// Present the multi-controller bulk upload dialog as a sheet.
- (void)presentMultiControllerUploadDialog;

@end
