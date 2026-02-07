/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLKeychainHelper.h"
#import <Security/Security.h>

static NSString * const kKeychainServiceName = @"com.xlights.controller-auth";

@implementation XLKeychainHelper

#pragma mark - Private Helpers

+ (NSString *)accountKeyForController:(NSString *)controllerName username:(NSString *)username {
    return [NSString stringWithFormat:@"%@:%@", controllerName, username];
}

+ (NSDictionary *)baseQueryForController:(NSString *)controllerName username:(NSString *)username {
    NSString *account = [self accountKeyForController:controllerName username:username];
    return @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainServiceName,
        (__bridge id)kSecAttrAccount: account,
    };
}

#pragma mark - Public API

+ (BOOL)savePassword:(NSString *)password
       forController:(NSString *)controllerName
            username:(NSString *)username {

    if (!password || !controllerName || !username) {
        return NO;
    }

    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    if (!passwordData) {
        return NO;
    }

    NSDictionary *query = [self baseQueryForController:controllerName username:username];

    // Try to update an existing item first
    NSDictionary *updateAttributes = @{
        (__bridge id)kSecValueData: passwordData,
    };

    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
                                    (__bridge CFDictionaryRef)updateAttributes);

    if (status == errSecItemNotFound) {
        // No existing item -- add a new one
        NSMutableDictionary *addQuery = [query mutableCopy];
        addQuery[(__bridge id)kSecValueData] = passwordData;
        addQuery[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlocked;

        status = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    }

    if (status != errSecSuccess) {
        NSLog(@"XLKeychainHelper: Failed to save password for controller '%@' (status %d)",
              controllerName, (int)status);
        return NO;
    }

    return YES;
}

+ (NSString *)passwordForController:(NSString *)controllerName
                           username:(NSString *)username {

    if (!controllerName || !username) {
        return nil;
    }

    NSMutableDictionary *query = [[self baseQueryForController:controllerName username:username] mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    if (status != errSecSuccess || result == NULL) {
        return nil;
    }

    NSData *passwordData = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding];
}

+ (BOOL)deletePasswordForController:(NSString *)controllerName
                           username:(NSString *)username {

    if (!controllerName || !username) {
        return NO;
    }

    NSDictionary *query = [self baseQueryForController:controllerName username:username];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);

    if (status != errSecSuccess && status != errSecItemNotFound) {
        NSLog(@"XLKeychainHelper: Failed to delete password for controller '%@' (status %d)",
              controllerName, (int)status);
        return NO;
    }

    return YES;
}

@end
