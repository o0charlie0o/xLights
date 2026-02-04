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
#include <string>
#include <vector>

NS_ASSUME_NONNULL_BEGIN

/**
 * @file NativePreferences.h
 * @brief Native macOS preferences wrapper using NSUserDefaults.
 *
 * This class provides an interface similar to wxConfig but uses NSUserDefaults
 * internally. It allows the native macOS app to store and retrieve preferences
 * without depending on wxWidgets.
 *
 * The API is designed to mirror wxConfig patterns for easier migration:
 * - Read(key, &variable) pattern becomes getString/getInt/getBool methods
 * - Write(key, value) pattern becomes setString/setInt/setBool methods
 *
 * Thread Safety:
 * NSUserDefaults is thread-safe for reading and writing. All methods in this
 * class are safe to call from any thread.
 *
 * Synchronization:
 * Changes are automatically synchronized to disk by NSUserDefaults. For
 * immediate persistence, call synchronize().
 */
@interface NativePreferences : NSObject

#pragma mark - Lifecycle

/**
 * @brief Get the shared preferences instance.
 *
 * Returns a singleton instance that uses the standard NSUserDefaults.
 * This is the preferred way to access preferences.
 */
+ (instancetype)sharedPreferences;

/**
 * @brief Initialize with a custom suite name.
 *
 * Use this for app groups or testing with isolated preferences.
 *
 * @param suiteName The suite name for the preferences domain (nil for standard defaults)
 */
- (instancetype)initWithSuiteName:(nullable NSString *)suiteName;

#pragma mark - String Operations

/**
 * @brief Get a string value from preferences.
 *
 * @param key The preference key
 * @param defaultValue Value to return if key doesn't exist
 * @return The stored string value or defaultValue if not found
 */
- (NSString *)stringForKey:(NSString *)key defaultValue:(NSString *)defaultValue;

/**
 * @brief Get a string value as std::string.
 *
 * @param key The preference key (as std::string)
 * @param defaultValue Value to return if key doesn't exist
 * @return The stored string value or defaultValue if not found
 */
- (std::string)getString:(const std::string&)key defaultValue:(const std::string&)defaultValue;

/**
 * @brief Set a string value in preferences.
 *
 * @param value The value to store
 * @param key The preference key
 */
- (void)setString:(NSString *)value forKey:(NSString *)key;

/**
 * @brief Set a string value from std::string.
 *
 * @param key The preference key
 * @param value The value to store
 */
- (void)setString:(const std::string&)key value:(const std::string&)value;

#pragma mark - Integer Operations

/**
 * @brief Get an integer value from preferences.
 *
 * @param key The preference key
 * @param defaultValue Value to return if key doesn't exist
 * @return The stored integer value or defaultValue if not found
 */
- (NSInteger)integerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue;

/**
 * @brief Get an integer value.
 *
 * @param key The preference key (as std::string)
 * @param defaultValue Value to return if key doesn't exist
 * @return The stored integer value or defaultValue if not found
 */
- (int)getInt:(const std::string&)key defaultValue:(int)defaultValue;

/**
 * @brief Get a long integer value.
 *
 * @param key The preference key (as std::string)
 * @param defaultValue Value to return if key doesn't exist
 * @return The stored long value or defaultValue if not found
 */
- (long)getLong:(const std::string&)key defaultValue:(long)defaultValue;

/**
 * @brief Set an integer value in preferences.
 *
 * @param value The value to store
 * @param key The preference key
 */
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;

/**
 * @brief Set an integer value.
 *
 * @param key The preference key
 * @param value The value to store
 */
- (void)setInt:(const std::string&)key value:(int)value;

/**
 * @brief Set a long integer value.
 *
 * @param key The preference key
 * @param value The value to store
 */
- (void)setLong:(const std::string&)key value:(long)value;

#pragma mark - Boolean Operations

/**
 * @brief Get a boolean value from preferences.
 *
 * @param key The preference key
 * @param defaultValue Value to return if key doesn't exist
 * @return The stored boolean value or defaultValue if not found
 */
- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue;

/**
 * @brief Get a boolean value.
 *
 * @param key The preference key (as std::string)
 * @param defaultValue Value to return if key doesn't exist
 * @return The stored boolean value or defaultValue if not found
 */
- (bool)getBool:(const std::string&)key defaultValue:(bool)defaultValue;

/**
 * @brief Set a boolean value in preferences.
 *
 * @param value The value to store
 * @param key The preference key
 */
- (void)setBool:(BOOL)value forKey:(NSString *)key;

/**
 * @brief Set a boolean value.
 *
 * @param key The preference key
 * @param value The value to store
 */
- (void)setBool:(const std::string&)key value:(bool)value;

#pragma mark - Double/Float Operations

/**
 * @brief Get a double value from preferences.
 *
 * @param key The preference key
 * @param defaultValue Value to return if key doesn't exist
 * @return The stored double value or defaultValue if not found
 */
- (double)doubleForKey:(NSString *)key defaultValue:(double)defaultValue;

/**
 * @brief Get a double value.
 *
 * @param key The preference key (as std::string)
 * @param defaultValue Value to return if key doesn't exist
 * @return The stored double value or defaultValue if not found
 */
- (double)getDouble:(const std::string&)key defaultValue:(double)defaultValue;

/**
 * @brief Get a float value.
 *
 * @param key The preference key (as std::string)
 * @param defaultValue Value to return if key doesn't exist
 * @return The stored float value or defaultValue if not found
 */
- (float)getFloat:(const std::string&)key defaultValue:(float)defaultValue;

/**
 * @brief Set a double value in preferences.
 *
 * @param value The value to store
 * @param key The preference key
 */
- (void)setDouble:(double)value forKey:(NSString *)key;

/**
 * @brief Set a double value.
 *
 * @param key The preference key
 * @param value The value to store
 */
- (void)setDouble:(const std::string&)key value:(double)value;

/**
 * @brief Set a float value.
 *
 * @param key The preference key
 * @param value The value to store
 */
- (void)setFloat:(const std::string&)key value:(float)value;

#pragma mark - Data Operations

/**
 * @brief Get raw data from preferences.
 *
 * @param key The preference key
 * @return The stored data or nil if not found
 */
- (nullable NSData *)dataForKey:(NSString *)key;

/**
 * @brief Set raw data in preferences.
 *
 * @param data The data to store
 * @param key The preference key
 */
- (void)setData:(NSData *)data forKey:(NSString *)key;

#pragma mark - Array Operations

/**
 * @brief Get a string array from preferences.
 *
 * @param key The preference key
 * @return The stored array or empty array if not found
 */
- (NSArray<NSString *> *)stringArrayForKey:(NSString *)key;

/**
 * @brief Get a string array as std::vector.
 *
 * @param key The preference key (as std::string)
 * @return The stored strings or empty vector if not found
 */
- (std::vector<std::string>)getStringArray:(const std::string&)key;

/**
 * @brief Set a string array in preferences.
 *
 * @param array The array to store
 * @param key The preference key
 */
- (void)setStringArray:(NSArray<NSString *> *)array forKey:(NSString *)key;

/**
 * @brief Set a string array from std::vector.
 *
 * @param key The preference key
 * @param values The values to store
 */
- (void)setStringArray:(const std::string&)key values:(const std::vector<std::string>&)values;

#pragma mark - Dictionary Operations

/**
 * @brief Get a dictionary from preferences.
 *
 * @param key The preference key
 * @return The stored dictionary or nil if not found
 */
- (nullable NSDictionary *)dictionaryForKey:(NSString *)key;

/**
 * @brief Set a dictionary in preferences.
 *
 * @param dictionary The dictionary to store
 * @param key The preference key
 */
- (void)setDictionary:(NSDictionary *)dictionary forKey:(NSString *)key;

#pragma mark - Key Management

/**
 * @brief Check if a key exists in preferences.
 *
 * @param key The preference key
 * @return YES if the key exists, NO otherwise
 */
- (BOOL)hasKey:(NSString *)key;

/**
 * @brief Check if a key exists (std::string version).
 *
 * @param key The preference key
 * @return true if the key exists, false otherwise
 */
- (bool)hasKeyStd:(const std::string&)key;

/**
 * @brief Remove a value from preferences.
 *
 * @param key The preference key to remove
 */
- (void)removeKey:(NSString *)key;

/**
 * @brief Remove a value (std::string version).
 *
 * @param key The preference key to remove
 */
- (void)removeKeyStd:(const std::string&)key;

/**
 * @brief Get all preference keys.
 *
 * @return Array of all keys in the preferences domain
 */
- (NSArray<NSString *> *)allKeys;

#pragma mark - Synchronization

/**
 * @brief Force immediate synchronization to disk.
 *
 * Normally NSUserDefaults synchronizes automatically. Call this if you need
 * to ensure changes are persisted immediately (e.g., before app termination).
 *
 * @return YES if synchronization succeeded
 */
- (BOOL)synchronize;

#pragma mark - Migration Support

/**
 * @brief Register default values.
 *
 * These values are returned when no explicit value has been set.
 * Call this early in app initialization.
 *
 * @param defaults Dictionary of key-value pairs for default values
 */
- (void)registerDefaults:(NSDictionary *)defaults;

/**
 * @brief Reset all preferences to defaults.
 *
 * Removes all stored values, leaving only registered defaults.
 */
- (void)resetToDefaults;

#pragma mark - Utility Methods

/**
 * @brief Convert NSString to std::string.
 */
+ (std::string)stdStringFromNSString:(NSString *)nsString;

/**
 * @brief Convert std::string to NSString.
 */
+ (NSString *)nsStringFromStdString:(const std::string&)stdString;

@end

NS_ASSUME_NONNULL_END
