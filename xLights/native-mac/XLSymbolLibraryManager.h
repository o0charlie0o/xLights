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

@class XLEngineBridge;

/// Notification posted when a symbol is updated and linked effects should refresh.
extern NSNotificationName const XLSymbolDidUpdateNotification;

/// Key for the symbol ID in XLSymbolDidUpdateNotification userInfo.
extern NSString * const XLSymbolIDKey;

/// Manages the symbol library for the current show folder.
///
/// A symbol is a named, reusable effect configuration. Multiple effects can be
/// "linked" to a symbol. When the symbol is updated, all linked effects update.
///
/// Symbol metadata is stored as a custom effect parameter (X_SYMBOL_ID) on each
/// linked effect. Symbol definitions are stored as plist files in <showfolder>/Symbols/.
@interface XLSymbolLibraryManager : NSObject

/// Engine bridge for reading/writing effect parameters.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Shared singleton instance.
@property (class, readonly, strong) XLSymbolLibraryManager *sharedManager;

/// Initialize with an engine bridge.
- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge;

#pragma mark - Symbol CRUD

/// Create a new symbol from the given effect.
/// @param effectId The effect to create a symbol from.
/// @param name The name for the new symbol.
/// @return The generated symbol ID, or nil on failure.
- (NSString *)createSymbolFromEffect:(NSInteger)effectId withName:(NSString *)name;

/// Get all available symbol definitions.
/// Returns array of dictionaries with keys: symbolId, name, effectType, dateCreated.
- (NSArray<NSDictionary *> *)allSymbols;

/// Get symbol names for display in menus.
- (NSArray<NSString *> *)symbolNames;

/// Get a symbol definition by its ID.
/// Returns dictionary with: symbolId, name, effectType, settings, palette, dateCreated.
- (NSDictionary *)symbolWithId:(NSString *)symbolId;

/// Get a symbol definition by index (for menu-based access).
- (NSDictionary *)symbolAtIndex:(NSInteger)index;

/// Delete a symbol by ID. Does not unlink effects -- they retain their last settings.
/// @param symbolId The symbol to delete.
/// @return YES if deleted.
- (BOOL)deleteSymbol:(NSString *)symbolId;

/// Update a symbol definition from the given effect's current settings.
/// @param symbolId The symbol to update.
/// @param effectId The effect whose settings will be used.
/// @return YES if updated. Posts XLSymbolDidUpdateNotification on success.
- (BOOL)updateSymbol:(NSString *)symbolId fromEffect:(NSInteger)effectId;

/// Rename a symbol.
- (BOOL)renameSymbol:(NSString *)symbolId toName:(NSString *)newName;

#pragma mark - Linking

/// Link an effect to a symbol. Applies the symbol's settings and palette to the effect
/// and stores the symbol ID as a metadata parameter on the effect.
/// @param effectId The effect to link.
/// @param symbolId The symbol to link to.
/// @return YES if linked and settings applied.
- (BOOL)linkEffect:(NSInteger)effectId toSymbol:(NSString *)symbolId;

/// Unlink an effect from its symbol. Removes the symbol metadata but preserves
/// the current settings/palette on the effect.
/// @param effectId The effect to unlink.
/// @return YES if unlinked.
- (BOOL)unlinkEffect:(NSInteger)effectId;

/// Get the symbol ID that an effect is linked to (or nil if not linked).
- (NSString *)symbolIdForEffect:(NSInteger)effectId;

/// Check if an effect is linked to any symbol.
- (BOOL)isEffectLinked:(NSInteger)effectId;

/// Apply a symbol's settings to all effects currently linked to it.
/// @param symbolId The symbol whose settings to propagate.
/// @param effectIds Array of NSNumber effect IDs to update.
/// @return Number of effects updated.
- (NSInteger)propagateSymbol:(NSString *)symbolId toEffects:(NSArray<NSNumber *> *)effectIds;

#pragma mark - Reload

/// Reload symbol definitions from disk.
- (void)reloadSymbols;

/// Get the count of loaded symbols.
- (NSInteger)symbolCount;

@end
