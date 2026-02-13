/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLNativePhonemeDictionary.h"

@implementation XLNativePhonemeDictionary {
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *_pronunciationDict;
    NSMutableDictionary<NSString *, NSString *> *_phonemeMap;
    BOOL _loaded;
}

+ (instancetype)sharedInstance {
    static XLNativePhonemeDictionary *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[XLNativePhonemeDictionary alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pronunciationDict = [NSMutableDictionary new];
        _phonemeMap = [NSMutableDictionary new];
        _loaded = NO;
    }
    return self;
}

- (BOOL)isLoaded {
    return _loaded;
}

- (NSUInteger)entryCount {
    return _pronunciationDict.count;
}

- (void)loadDictionaries {
    [self loadDictionariesWithShowDirectory:nil];
}

- (void)loadDictionariesWithShowDirectory:(NSString *)showDirectory {
    if (_loaded) return;

    [self loadDictionaryNamed:@"standard_dictionary" showDirectory:showDirectory];
    [self loadDictionaryNamed:@"extended_dictionary" showDirectory:showDirectory];
    [self loadDictionaryNamed:@"user_dictionary" showDirectory:showDirectory];
    [self loadPhonemeMapping];

    _loaded = YES;
    NSLog(@"XLNativePhonemeDictionary: Loaded %lu pronunciation entries, %lu phoneme mappings",
          (unsigned long)_pronunciationDict.count, (unsigned long)_phonemeMap.count);
}

- (void)loadDictionaryNamed:(NSString *)filename showDirectory:(NSString *)showDirectory {
    NSString *path = nil;

    // First check show directory (user_dictionary may be there)
    if (showDirectory) {
        NSString *showPath = [showDirectory stringByAppendingPathComponent:filename];
        if ([[NSFileManager defaultManager] fileExistsAtPath:showPath]) {
            path = showPath;
        }
    }

    // Then check app bundle
    if (!path) {
        path = [[NSBundle mainBundle] pathForResource:filename ofType:nil];
    }

    if (!path) {
        if (![filename isEqualToString:@"user_dictionary"]) {
            NSLog(@"XLNativePhonemeDictionary: %@ not found", filename);
        }
        return;
    }

    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path
                                                   encoding:NSISOLatin1StringEncoding
                                                      error:&error];
    if (error || !contents) {
        NSLog(@"XLNativePhonemeDictionary: Failed to read %@: %@", filename, error);
        return;
    }

    NSArray<NSString *> *lines = [contents componentsSeparatedByString:@"\n"];
    NSUInteger count = 0;

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;
        if ([trimmed hasPrefix:@"##"] || [trimmed hasPrefix:@";;"]) continue;

        NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@" "];
        // Filter out empty parts from multiple spaces
        NSMutableArray<NSString *> *nonEmpty = [NSMutableArray new];
        for (NSString *part in parts) {
            if (part.length > 0) {
                [nonEmpty addObject:part];
            }
        }

        if (nonEmpty.count > 1) {
            _pronunciationDict[nonEmpty[0]] = [nonEmpty copy];
            count++;
        }
    }

    NSLog(@"XLNativePhonemeDictionary: Loaded %lu entries from %@", (unsigned long)count, filename);
}

- (void)loadPhonemeMapping {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"phoneme_mapping" ofType:nil];
    if (!path) {
        NSLog(@"XLNativePhonemeDictionary: phoneme_mapping not found in bundle");
        return;
    }

    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
    if (error || !contents) {
        NSLog(@"XLNativePhonemeDictionary: Failed to read phoneme_mapping: %@", error);
        return;
    }

    NSArray<NSString *> *lines = [contents componentsSeparatedByString:@"\n"];

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;
        if ([trimmed hasPrefix:@"#"] || [trimmed hasPrefix:@";;"]) continue;

        // Strip inline comments (anything after # that's not at the start)
        NSRange commentRange = [trimmed rangeOfString:@"#"];
        NSString *effective = trimmed;
        if (commentRange.location != NSNotFound && commentRange.location > 0) {
            effective = [[trimmed substringToIndex:commentRange.location]
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }

        NSArray<NSString *> *parts = [effective componentsSeparatedByString:@" "];
        NSMutableArray<NSString *> *nonEmpty = [NSMutableArray new];
        for (NSString *part in parts) {
            if (part.length > 0) {
                [nonEmpty addObject:part];
            }
        }

        if (nonEmpty.count >= 2) {
            // Format: "CMU_PHONEME XLIGHTS_PHONEME"
            // Entries starting with "." define the list of valid phonemes (skip for map)
            if (![nonEmpty[0] isEqualToString:@"."]) {
                _phonemeMap[nonEmpty[0]] = nonEmpty[1];
            }
        }
    }
}

- (NSArray<NSString *> *)phonemesForWord:(NSString *)word {
    if (!word || word.length == 0) return @[];
    if (!_loaded) [self loadDictionaries];

    // Strip punctuation and special characters (matching legacy PhonemeDictionary::BreakdownWord)
    NSMutableString *cleaned = [word mutableCopy];
    NSArray *charsToRemove = @[@"/", @"#", @"~", @"@", @"$", @"%", @"^", @"*",
                               @",", @"!", @"&", @"-", @"_", @"+", @"=",
                               @"[", @"]", @"{", @"}", @"\"", @":", @";",
                               @".", @"<", @">", @"?", @"`"];
    for (NSString *c in charsToRemove) {
        [cleaned replaceOccurrencesOfString:c withString:@"" options:0 range:NSMakeRange(0, cleaned.length)];
    }
    [cleaned replaceOccurrencesOfString:@"\t" withString:@" " options:0 range:NSMakeRange(0, cleaned.length)];

    NSString *upperWord = [cleaned uppercaseString];
    NSArray<NSString *> *pronunciation = _pronunciationDict[upperWord];
    if (!pronunciation || pronunciation.count <= 1) return @[];

    NSMutableArray<NSString *> *result = [NSMutableArray new];

    for (NSUInteger i = 1; i < pronunciation.count; i++) {
        NSString *p = pronunciation[i];
        if (p.length == 0) continue;

        NSString *mapped = _phonemeMap[p];
        if (!mapped) mapped = _phonemeMap[p]; // fallback (same as legacy which maps in both branches)
        if (!mapped) {
            // Unknown phoneme, map to "etc" as fallback
            mapped = @"etc";
        }

        // Skip consecutive duplicates of "etc"
        if ([mapped isEqualToString:@"etc"] && result.count > 0 && [result.lastObject isEqualToString:@"etc"]) {
            continue;
        }

        [result addObject:mapped];
    }

    return result;
}

@end
