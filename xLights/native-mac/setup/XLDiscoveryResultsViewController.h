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
#import "XLNetworkDiscoveryController.h"

@class XLDiscoveryResultsViewController;

/// Delegate protocol for discovery results interactions.
@protocol XLDiscoveryResultsDelegate <NSObject>

@optional

/// Called when the user wants to add selected controllers.
/// @param controllers Array of indices of selected controllers.
- (void)discoveryResults:(XLDiscoveryResultsViewController *)controller
    didRequestAddControllers:(NSArray<NSNumber *> *)controllerIndices;

/// Called when the user dismisses the results view.
- (void)discoveryResultsDidDismiss:(XLDiscoveryResultsViewController *)controller;

/// Called when the user requests to rescan.
- (void)discoveryResultsDidRequestRescan:(XLDiscoveryResultsViewController *)controller;

@end

/// View controller for displaying network discovery results in a popover.
///
/// Shows a table of discovered controllers with columns for IP, hostname,
/// vendor/model, mode, and whether they're already configured. Allows
/// selecting multiple controllers to add to the configuration.
@interface XLDiscoveryResultsViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

/// Delegate for user interactions.
@property (nonatomic, weak) id<XLDiscoveryResultsDelegate> delegate;

/// The network discovery controller providing data.
@property (nonatomic, weak) XLNetworkDiscoveryController *discoveryController;

/// Updates the view with results from the discovery controller.
- (void)reloadResults;

/// Sets the discovery state to update the UI accordingly.
- (void)setDiscoveryState:(XLDiscoveryState)state;

/// Returns indices of selected controllers.
- (NSArray<NSNumber *> *)selectedControllerIndices;

@end
