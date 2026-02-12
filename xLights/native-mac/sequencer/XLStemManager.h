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

#import <Cocoa/Cocoa.h>

@class XLStemData;

/// Notification posted when the stem collection changes (add/remove/load complete).
extern NSNotificationName const XLStemManagerDidChangeNotification;

/// Number of waveform overview buckets per stem (half of main waveform's 65K).
static const NSUInteger kStemBucketCount = 32768;

/// Manages the collection of audio stems for a sequence.
/// Handles import, async loading, and serialization for XML persistence.
@interface XLStemManager : NSObject

/// The current collection of stems (read-only).
@property (nonatomic, readonly) NSArray<XLStemData *> *stems;

/// The show folder path used for resolving relative paths.
@property (nonatomic, copy) NSString *showFolderPath;

/// Import stem files from an array of file URLs.
/// Loading happens on a background queue; posts XLStemManagerDidChangeNotification on completion.
/// @param fileURLs Array of NSURL pointing to audio files.
/// @param completion Optional completion block called on main queue when all stems are loaded.
- (void)importStemFiles:(NSArray<NSURL *> *)fileURLs completion:(void (^_Nullable)(void))completion;

/// Import all audio files from a folder (typical Demucs/Spleeter output).
/// Scans for common audio extensions (.wav, .mp3, .m4a, .aac, .aiff, .flac).
/// @param folderURL URL of the folder to scan.
/// @param completion Optional completion block called on main queue when all stems are loaded.
- (void)importStemsFromFolder:(NSURL *)folderURL completion:(void (^_Nullable)(void))completion;

/// Remove a stem at the given index.
- (void)removeStemAtIndex:(NSUInteger)index;

/// Remove all stems.
- (void)removeAllStems;

/// Serialize stems to an array of dictionaries for XML persistence.
/// Each dict contains: name, relativePath, color (#RRGGBB).
- (NSArray<NSDictionary<NSString *, NSString *> *> *)serializeToDicts;

/// Restore stems from serialized dictionaries and reload audio.
/// @param dicts Array of dictionaries from serializeToDicts.
- (void)restoreFromDicts:(NSArray<NSDictionary<NSString *, NSString *> *> *)dicts;

@end
