/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLSymbolLibraryManager.h"
#import "XLEngineBridge.h"

NSNotificationName const XLSymbolDidUpdateNotification = @"XLSymbolDidUpdateNotification";
NSString * const XLSymbolIDKey = @"symbolId";

static NSString * const kSymbolsFolderName = @"Symbols";
static NSString * const kSymbolMetadataKey = @"X_SYMBOL_ID";

// Symbol plist keys
static NSString * const kSymKeyId = @"symbolId";
static NSString * const kSymKeyName = @"name";
static NSString * const kSymKeyEffectType = @"effectType";
static NSString * const kSymKeySettings = @"settings";
static NSString * const kSymKeyPalette = @"palette";
static NSString * const kSymKeyDateCreated = @"dateCreated";
static NSString * const kSymKeyDateModified = @"dateModified";

@implementation XLSymbolLibraryManager {
    NSMutableArray<NSDictionary *> *_symbols;
}

static XLSymbolLibraryManager *_sharedInstance = nil;

+ (XLSymbolLibraryManager *)sharedManager {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[XLSymbolLibraryManager alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _symbols = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge {
    self = [self init];
    if (self) {
        _engineBridge = engineBridge;
        [self reloadSymbols];
    }
    return self;
}

#pragma mark - Storage Helpers

- (NSString *)symbolsDirectory {
    NSString *showFolder = [_engineBridge getShowFolderPath];
    if (!showFolder || showFolder.length == 0) {
        showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    }
    if (!showFolder || showFolder.length == 0) return nil;

    NSString *symbolsDir = [showFolder stringByAppendingPathComponent:kSymbolsFolderName];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:symbolsDir]) {
        [fm createDirectoryAtPath:symbolsDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return symbolsDir;
}

- (NSString *)sanitizedFilename:(NSString *)name {
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    return [[name componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@"_"];
}

- (NSString *)symbolPathForId:(NSString *)symbolId {
    NSString *dir = [self symbolsDirectory];
    if (!dir) return nil;
    NSString *filename = [NSString stringWithFormat:@"%@.xlsymbol", [self sanitizedFilename:symbolId]];
    return [dir stringByAppendingPathComponent:filename];
}

- (NSString *)generateSymbolId {
    return [[NSUUID UUID] UUIDString];
}

- (NSDictionary *)loadSymbolFromFile:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [NSDictionary dictionaryWithContentsOfFile:path];
}

- (BOOL)saveSymbolToFile:(NSDictionary *)symbolData path:(NSString *)path {
    return [symbolData writeToFile:path atomically:YES];
}

#pragma mark - Symbol CRUD

- (NSString *)createSymbolFromEffect:(NSInteger)effectId withName:(NSString *)name {
    if (effectId < 0 || !name || name.length == 0 || !_engineBridge) return nil;

    NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
    if (!effectInfo) {
        NSLog(@"SymbolLibrary: Cannot get effect info for ID %ld", (long)effectId);
        return nil;
    }

    NSString *effectType = effectInfo[@"effectType"] ?: @"Unknown";
    NSString *settings = [_engineBridge getEffectSettings:effectId];
    NSString *palette = [_engineBridge getEffectPalette:effectId];
    NSString *symbolId = [self generateSymbolId];

    NSMutableDictionary *symbolData = [NSMutableDictionary dictionary];
    symbolData[kSymKeyId] = symbolId;
    symbolData[kSymKeyName] = name;
    symbolData[kSymKeyEffectType] = effectType;
    symbolData[kSymKeyDateCreated] = [[NSDate date] description];
    symbolData[kSymKeyDateModified] = [[NSDate date] description];
    if (settings) symbolData[kSymKeySettings] = settings;
    if (palette) symbolData[kSymKeyPalette] = palette;

    NSString *path = [self symbolPathForId:symbolId];
    if (path && [self saveSymbolToFile:symbolData path:path]) {
        // Link the source effect to this symbol
        [_engineBridge setEffectParameter:effectId key:kSymbolMetadataKey value:symbolId];
        [self reloadSymbols];
        NSLog(@"SymbolLibrary: Created symbol '%@' (ID: %@) from effect %ld", name, symbolId, (long)effectId);
        return symbolId;
    }

    NSLog(@"SymbolLibrary: Failed to save symbol '%@'", name);
    return nil;
}

- (NSArray<NSDictionary *> *)allSymbols {
    return [_symbols copy];
}

- (NSArray<NSString *> *)symbolNames {
    NSMutableArray *names = [NSMutableArray arrayWithCapacity:_symbols.count];
    for (NSDictionary *sym in _symbols) {
        [names addObject:sym[kSymKeyName] ?: @"Unnamed"];
    }
    return names;
}

- (NSDictionary *)symbolWithId:(NSString *)symbolId {
    if (!symbolId) return nil;
    for (NSDictionary *sym in _symbols) {
        if ([sym[kSymKeyId] isEqualToString:symbolId]) {
            return sym;
        }
    }
    // Not in cache, try loading from disk
    NSString *path = [self symbolPathForId:symbolId];
    return [self loadSymbolFromFile:path];
}

- (NSDictionary *)symbolAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_symbols.count) return nil;
    return _symbols[index];
}

- (BOOL)deleteSymbol:(NSString *)symbolId {
    if (!symbolId) return NO;

    NSString *path = [self symbolPathForId:symbolId];
    if (!path) return NO;

    NSError *error = nil;
    BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    if (removed) {
        [self reloadSymbols];
        NSLog(@"SymbolLibrary: Deleted symbol '%@'", symbolId);
    } else {
        NSLog(@"SymbolLibrary: Failed to delete symbol '%@': %@", symbolId, error.localizedDescription);
    }
    return removed;
}

- (BOOL)updateSymbol:(NSString *)symbolId fromEffect:(NSInteger)effectId {
    if (!symbolId || effectId < 0 || !_engineBridge) return NO;

    NSDictionary *existing = [self symbolWithId:symbolId];
    if (!existing) return NO;

    NSString *settings = [_engineBridge getEffectSettings:effectId];
    NSString *palette = [_engineBridge getEffectPalette:effectId];

    NSMutableDictionary *updated = [existing mutableCopy];
    updated[kSymKeyDateModified] = [[NSDate date] description];
    if (settings) updated[kSymKeySettings] = settings;
    if (palette) updated[kSymKeyPalette] = palette;

    NSString *path = [self symbolPathForId:symbolId];
    if (path && [self saveSymbolToFile:updated path:path]) {
        [self reloadSymbols];
        [[NSNotificationCenter defaultCenter] postNotificationName:XLSymbolDidUpdateNotification
                                                            object:self
                                                          userInfo:@{XLSymbolIDKey: symbolId}];
        NSLog(@"SymbolLibrary: Updated symbol '%@' from effect %ld", symbolId, (long)effectId);
        return YES;
    }
    return NO;
}

- (BOOL)renameSymbol:(NSString *)symbolId toName:(NSString *)newName {
    if (!symbolId || !newName || newName.length == 0) return NO;

    NSDictionary *existing = [self symbolWithId:symbolId];
    if (!existing) return NO;

    NSMutableDictionary *updated = [existing mutableCopy];
    updated[kSymKeyName] = newName;
    updated[kSymKeyDateModified] = [[NSDate date] description];

    NSString *path = [self symbolPathForId:symbolId];
    if (path && [self saveSymbolToFile:updated path:path]) {
        [self reloadSymbols];
        return YES;
    }
    return NO;
}

#pragma mark - Linking

- (BOOL)linkEffect:(NSInteger)effectId toSymbol:(NSString *)symbolId {
    if (effectId < 0 || !symbolId || !_engineBridge) return NO;

    NSDictionary *symbolData = [self symbolWithId:symbolId];
    if (!symbolData) {
        NSLog(@"SymbolLibrary: Cannot find symbol '%@' to link", symbolId);
        return NO;
    }

    // Apply symbol settings and palette to the effect
    NSString *settings = symbolData[kSymKeySettings];
    NSString *palette = symbolData[kSymKeyPalette];

    BOOL success = YES;
    if (settings) {
        success = [_engineBridge setEffectSettings:effectId settings:settings] && success;
    }
    if (palette) {
        success = [_engineBridge setEffectPalette:effectId palette:palette] && success;
    }

    // Store the symbol link as metadata
    success = [_engineBridge setEffectParameter:effectId key:kSymbolMetadataKey value:symbolId] && success;

    if (success) {
        NSLog(@"SymbolLibrary: Linked effect %ld to symbol '%@'", (long)effectId, symbolId);
    }
    return success;
}

- (BOOL)unlinkEffect:(NSInteger)effectId {
    if (effectId < 0 || !_engineBridge) return NO;

    // Clear the symbol metadata - settings/palette remain unchanged
    BOOL success = [_engineBridge setEffectParameter:effectId key:kSymbolMetadataKey value:@""];
    if (success) {
        NSLog(@"SymbolLibrary: Unlinked effect %ld from its symbol", (long)effectId);
    }
    return success;
}

- (NSString *)symbolIdForEffect:(NSInteger)effectId {
    if (effectId < 0 || !_engineBridge) return nil;
    NSString *symbolId = [_engineBridge getEffectParameter:effectId key:kSymbolMetadataKey];
    if (symbolId && symbolId.length > 0) return symbolId;
    return nil;
}

- (BOOL)isEffectLinked:(NSInteger)effectId {
    return [self symbolIdForEffect:effectId] != nil;
}

- (NSInteger)propagateSymbol:(NSString *)symbolId toEffects:(NSArray<NSNumber *> *)effectIds {
    if (!symbolId || !effectIds || effectIds.count == 0 || !_engineBridge) return 0;

    NSDictionary *symbolData = [self symbolWithId:symbolId];
    if (!symbolData) return 0;

    NSString *settings = symbolData[kSymKeySettings];
    NSString *palette = symbolData[kSymKeyPalette];

    NSInteger updated = 0;
    for (NSNumber *effId in effectIds) {
        NSInteger effectId = effId.integerValue;
        BOOL ok = YES;
        if (settings) {
            ok = [_engineBridge setEffectSettings:effectId settings:settings] && ok;
        }
        if (palette) {
            ok = [_engineBridge setEffectPalette:effectId palette:palette] && ok;
        }
        if (ok) updated++;
    }

    NSLog(@"SymbolLibrary: Propagated symbol '%@' to %ld of %lu effects",
          symbolId, (long)updated, (unsigned long)effectIds.count);
    return updated;
}

#pragma mark - Reload

- (void)reloadSymbols {
    [_symbols removeAllObjects];

    NSString *symbolsDir = [self symbolsDirectory];
    if (!symbolsDir) return;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:symbolsDir error:nil];

    for (NSString *file in files) {
        if (![file.pathExtension isEqualToString:@"xlsymbol"]) continue;

        NSString *fullPath = [symbolsDir stringByAppendingPathComponent:file];
        NSDictionary *data = [self loadSymbolFromFile:fullPath];
        if (data && data[kSymKeyId]) {
            [_symbols addObject:data];
        }
    }

    // Sort by name
    [_symbols sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *nameA = a[kSymKeyName] ?: @"";
        NSString *nameB = b[kSymKeyName] ?: @"";
        return [nameA localizedCaseInsensitiveCompare:nameB];
    }];

    NSLog(@"SymbolLibrary: Loaded %lu symbols", (unsigned long)_symbols.count);
}

- (NSInteger)symbolCount {
    return (NSInteger)_symbols.count;
}

@end
