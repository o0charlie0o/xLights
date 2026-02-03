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

#import <Foundation/Foundation.h>
#import "XLNetworkDiscoveryTypes.h"

@class XLEngineBridge;
@class XLNetworkDiscoveryController;

/// Delegate protocol for network discovery events.
@protocol XLNetworkDiscoveryDelegate <NSObject>

@optional

/// Called when discovery state changes.
- (void)discoveryController:(XLNetworkDiscoveryController *)controller
         didChangeState:(XLDiscoveryState)state;

/// Called when discovery completes successfully.
/// @param controllers C array of discovered controllers (valid until next discovery).
/// @param count Number of controllers in the array.
- (void)discoveryController:(XLNetworkDiscoveryController *)controller
   didDiscoverControllers:(const XLDiscoveredController *)controllers
                    count:(NSUInteger)count;

/// Called when discovery fails with an error.
- (void)discoveryController:(XLNetworkDiscoveryController *)controller
       didFailWithError:(NSError *)error;

/// Called when a controller's ping status is updated.
- (void)discoveryController:(XLNetworkDiscoveryController *)controller
     didUpdatePingStatus:(XLPingState)status
       forControllerName:(NSString *)name;

@end

/// Network discovery controller for finding controllers on the local network.
///
/// This controller wraps the C++ Discovery class and provides an Objective-C
/// interface with GCD-based async operations. Results are stored in C arrays
/// to avoid heap corruption from ObjC/C++ mixing.
///
/// Usage:
/// 1. Create an instance and set the delegate
/// 2. Call startDiscovery to begin scanning
/// 3. Receive results via delegate callbacks
/// 4. Use getDiscoveredController: to access individual results
/// 5. Call addControllerToConfiguration: to add selected controllers
@interface XLNetworkDiscoveryController : NSObject

/// The delegate to receive discovery events.
@property (nonatomic, weak) id<XLNetworkDiscoveryDelegate> delegate;

/// Engine bridge for adding discovered controllers to configuration.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Current discovery state.
@property (nonatomic, readonly) XLDiscoveryState state;

/// Number of discovered controllers from the last scan.
@property (nonatomic, readonly) NSUInteger discoveredCount;

/// Timeout for discovery operations in seconds (default: 5.0).
@property (nonatomic, assign) NSTimeInterval discoveryTimeout;

/// Interval for background ping checks in seconds (default: 30.0).
/// Set to 0 to disable background ping.
@property (nonatomic, assign) NSTimeInterval pingInterval;

#pragma mark - Discovery Operations

/// Starts network discovery for controllers.
/// Discovery runs asynchronously; results are delivered via delegate.
/// If discovery is already in progress, this call is ignored.
- (void)startDiscovery;

/// Cancels any in-progress discovery operation.
- (void)cancelDiscovery;

/// Returns a copy of the discovered controller at the given index.
/// @param index Index into the discovered controllers array.
/// @return YES if the controller was copied, NO if index is out of bounds.
- (BOOL)getDiscoveredController:(XLDiscoveredController *)outController
                        atIndex:(NSUInteger)index;

/// Returns all discovered controllers as an NSArray of NSDictionary.
/// This creates new ObjC objects, so should only be used for UI binding.
/// For performance-critical code, use getDiscoveredController:atIndex:.
- (NSArray<NSDictionary *> *)discoveredControllersAsDictionaries;

#pragma mark - Configuration Operations

/// Adds a discovered controller to the xLights configuration.
/// @param index Index of the discovered controller to add.
/// @return YES if successful, NO if failed or index out of bounds.
- (BOOL)addDiscoveredControllerAtIndex:(NSUInteger)index;

/// Adds a discovered controller to the configuration with a custom name.
/// @param index Index of the discovered controller to add.
/// @param name Custom name for the controller.
/// @return YES if successful, NO if failed or index out of bounds.
- (BOOL)addDiscoveredControllerAtIndex:(NSUInteger)index
                              withName:(NSString *)name;

#pragma mark - Ping Status Operations

/// Starts background ping monitoring for all configured controllers.
/// Ping results are delivered via didUpdatePingStatus:forControllerName:.
- (void)startBackgroundPing;

/// Stops background ping monitoring.
- (void)stopBackgroundPing;

/// Returns YES if background ping is currently active.
@property (nonatomic, readonly) BOOL isBackgroundPingActive;

/// Performs an immediate ping check on all controllers.
/// Results are delivered via delegate callbacks.
- (void)pingAllControllersNow;

/// Performs an immediate ping check on a specific controller.
/// @param name Name of the controller to ping.
- (void)pingControllerNamed:(NSString *)name;

@end
