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

/// Native Obj-C port of PhonemeDictionary for the native macOS build.
///
/// Loads the CMU pronouncing dictionary files (standard_dictionary,
/// extended_dictionary, user_dictionary) and the phoneme_mapping file
/// from the app bundle's Resources directory. Provides word-to-phoneme
/// breakdown matching the legacy wxWidgets PhonemeDictionary behavior.
@interface XLNativePhonemeDictionary : NSObject

/// Shared singleton instance.
+ (instancetype)sharedInstance;

/// Load all dictionaries from the app bundle.
/// Safe to call multiple times; subsequent calls are no-ops.
- (void)loadDictionaries;

/// Load dictionaries, also checking the show directory for user_dictionary.
/// @param showDirectory Optional path to the show folder (may contain user_dictionary).
- (void)loadDictionariesWithShowDirectory:(NSString *)showDirectory;

/// Break a word down into its phoneme sequence.
/// @param word The word to look up (case-insensitive).
/// @return Array of phoneme strings (e.g., @[@"MBP", @"AI", @"etc"]),
///         or empty array if the word is not in the dictionary.
- (NSArray<NSString *> *)phonemesForWord:(NSString *)word;

/// Whether the dictionary has been loaded.
@property (nonatomic, readonly) BOOL isLoaded;

/// Number of entries in the pronunciation dictionary.
@property (nonatomic, readonly) NSUInteger entryCount;

@end
