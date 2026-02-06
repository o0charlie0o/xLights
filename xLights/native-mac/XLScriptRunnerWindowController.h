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

/// Window controller for the script runner (Tools > Run Scripts).
///
/// Provides a UI for selecting and running Lua (.lua) or Python (.py) scripts.
/// Currently implements the UI scaffold with file picker and output console.
/// TODO: Integrate with Lua 5.3 runtime and Python via pybind11.
@interface XLScriptRunnerWindowController : NSWindowController

/// Engine bridge for script access to models, effects, and outputs.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Show the script runner window.
- (void)showWindow:(id)sender;

@end
