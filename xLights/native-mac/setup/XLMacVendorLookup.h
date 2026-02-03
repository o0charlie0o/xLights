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

/// Singleton class for MAC address to vendor name lookup.
///
/// Loads the MacLookup.txt file from the app bundle's xScanner resources
/// and provides fast lookup of vendor names from MAC addresses.
/// Uses a C array internally to avoid heap corruption from ObjC/C++ mixing.
@interface XLMacVendorLookup : NSObject

/// Returns the shared singleton instance.
+ (instancetype)sharedInstance;

/// Loads the MAC vendor database from the bundle resources.
/// Call this once at app startup or lazily on first lookup.
/// Thread-safe - can be called from any thread.
- (void)loadDatabase;

/// Looks up the vendor name for a given MAC address.
/// @param macAddress MAC address in any common format (XX:XX:XX:XX:XX:XX,
///                   XX-XX-XX-XX-XX-XX, or XXXXXXXXXXXX).
/// @return Vendor name string, or nil if not found.
- (NSString *)vendorForMacAddress:(NSString *)macAddress;

/// Returns YES if the database has been loaded.
@property (nonatomic, readonly) BOOL isLoaded;

/// Returns the number of vendor entries loaded.
@property (nonatomic, readonly) NSUInteger entryCount;

@end
