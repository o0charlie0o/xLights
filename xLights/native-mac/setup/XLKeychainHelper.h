/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

#import <Foundation/Foundation.h>

/// Utility class for storing and retrieving controller authentication
/// credentials using the macOS Keychain Services API.
///
/// Credentials are stored with service name "com.xlights.controller-auth"
/// and an account key that combines the controller name with the username.
@interface XLKeychainHelper : NSObject

/// Save a password to the keychain for a given controller and username.
/// If an entry already exists, it will be updated.
/// @param password The password to store.
/// @param controllerName The name or IP of the controller.
/// @param username The username for authentication.
/// @return YES if the password was saved successfully.
+ (BOOL)savePassword:(NSString *)password
       forController:(NSString *)controllerName
            username:(NSString *)username;

/// Retrieve a password from the keychain for a given controller and username.
/// @param controllerName The name or IP of the controller.
/// @param username The username for authentication.
/// @return The stored password, or nil if not found.
+ (NSString *)passwordForController:(NSString *)controllerName
                           username:(NSString *)username;

/// Delete a stored password from the keychain.
/// @param controllerName The name or IP of the controller.
/// @param username The username for authentication.
/// @return YES if the entry was deleted (or did not exist).
+ (BOOL)deletePasswordForController:(NSString *)controllerName
                           username:(NSString *)username;

@end
