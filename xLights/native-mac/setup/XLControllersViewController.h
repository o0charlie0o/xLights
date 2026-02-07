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
#import "XLDiscoveryResultsViewController.h"

@class XLControllersViewController;
@class XLEngineBridge;

/// Controller type identifiers matching the C++ CONTROLLER_* constants.
typedef NS_ENUM(NSInteger, XLControllerType) {
    XLControllerTypeEthernet = 0,
    XLControllerTypeSerial,
    XLControllerTypeNull
};

/// Ping/connectivity status for a controller.
typedef NS_ENUM(NSInteger, XLControllerStatus) {
    XLControllerStatusUnknown = 0,
    XLControllerStatusOK,
    XLControllerStatusOpen,
    XLControllerStatusOpenFail,
    XLControllerStatusWebOK,
    XLControllerStatusAliveOnly,
    XLControllerStatusUnavailable
};

/// Delegate protocol for controller list user interactions.
@protocol XLControllersViewDelegate <NSObject>

@optional

/// Called when the selected controller changes.
- (void)controllersView:(XLControllersViewController *)controllersView
    didSelectControllerAtIndex:(NSInteger)index;

/// Called when the user requests adding a controller of the given type.
- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestAddController:(XLControllerType)type;

/// Called when the user requests deleting the controller at the given index.
- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestDeleteControllerAtIndex:(NSInteger)index;

/// Called when the user double-clicks or requests editing a controller.
- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestEditControllerAtIndex:(NSInteger)index;

/// Called when the user requests uploading configuration to a controller.
- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestUploadControllerAtIndex:(NSInteger)index;

/// Called when the user requests uploading configuration to multiple controllers.
- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestUploadControllersAtIndices:(NSIndexSet *)indices;

/// Called when the user requests activating/deactivating controllers.
- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestSetActive:(NSString *)activeState
    forControllerAtIndex:(NSInteger)index;

/// Called when the user requests reordering controllers via drag.
- (void)controllersView:(XLControllersViewController *)controllersView
    didMoveControllerFromIndex:(NSInteger)fromIndex
    toIndex:(NSInteger)toIndex;

/// Called when the user requests visualising (controller model dialog) for a controller.
- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestVisualiseControllerAtIndex:(NSInteger)index;

/// Called when the user requests unlinking controllers from the base show folder.
- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestUnlinkFromBaseAtIndices:(NSIndexSet *)indices;

@end

/// Column identifiers for the controller table view.
extern NSString * const XLControllerColumnName;
extern NSString * const XLControllerColumnProtocol;
extern NSString * const XLControllerColumnAddress;
extern NSString * const XLControllerColumnChannels;
extern NSString * const XLControllerColumnVendor;
extern NSString * const XLControllerColumnModel;
extern NSString * const XLControllerColumnActive;
extern NSString * const XLControllerColumnStatus;

/// NSTableView-based controller list for the Setup tab.
///
/// Displays all configured controllers with columns for name, protocol,
/// address, vendor/model, channels, active state, and connectivity status.
/// Supports add/remove, context menu, drag-to-reorder, and column sorting.
/// Includes network discovery integration with a Discover button in the footer.
///
/// Data is loaded from XLEngineBridge and cached locally as an NSArray
/// of NSDictionary objects keyed by the column identifiers above.
@interface XLControllersViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, XLNetworkDiscoveryDelegate, XLDiscoveryResultsDelegate>

/// The table view displaying the controller list.
@property (nonatomic, strong, readonly) NSTableView *tableView;

/// Delegate for user interaction callbacks.
@property (nonatomic, weak) id<XLControllersViewDelegate> delegate;

/// Engine bridge used to fetch controller data.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Cached controller data (NSArray of NSDictionary).
@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *controllers;

/// Refresh controller data from the engine bridge and reload the table.
- (void)reloadData;

/// Programmatically select a controller by index.
- (void)selectControllerAtIndex:(NSInteger)index;

/// Returns the index of the currently selected controller, or -1 if none.
- (NSInteger)selectedControllerIndex;

/// Returns the name of the currently selected controller, or nil.
- (NSString *)selectedControllerName;

/// Network discovery controller for finding controllers on the network.
@property (nonatomic, strong, readonly) XLNetworkDiscoveryController *discoveryController;

/// Starts network discovery and shows results in a popover.
- (void)startDiscovery;

/// Updates the ping status indicator for a specific controller.
- (void)updatePingStatus:(XLControllerStatus)status forControllerNamed:(NSString *)name;

@end
