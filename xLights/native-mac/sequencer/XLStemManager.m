/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLStemManager.h"
#import "XLStemData.h"
#import "XLAudioLoader.h"

NSNotificationName const XLStemManagerDidChangeNotification = @"XLStemManagerDidChangeNotification";

// 8-color palette for stem waveforms (distinct, readable on dark background)
static NSColor *XLStemColorPalette(NSUInteger index) {
    static NSArray<NSColor *> *palette = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        palette = @[
            [NSColor colorWithRed:0.40 green:0.85 blue:0.40 alpha:1.0],  // Green (Vocals)
            [NSColor colorWithRed:0.95 green:0.60 blue:0.20 alpha:1.0],  // Orange (Drums)
            [NSColor colorWithRed:0.40 green:0.65 blue:1.00 alpha:1.0],  // Blue (Bass)
            [NSColor colorWithRed:0.95 green:0.45 blue:0.45 alpha:1.0],  // Red (Guitar)
            [NSColor colorWithRed:0.85 green:0.70 blue:1.00 alpha:1.0],  // Lavender (Piano)
            [NSColor colorWithRed:1.00 green:0.90 blue:0.40 alpha:1.0],  // Yellow (Other)
            [NSColor colorWithRed:0.40 green:0.90 blue:0.90 alpha:1.0],  // Cyan
            [NSColor colorWithRed:1.00 green:0.55 blue:0.80 alpha:1.0],  // Pink
        ];
    });
    return palette[index % palette.count];
}

static NSString *XLHexFromColor(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)(rgb.redComponent * 255),
            (int)(rgb.greenComponent * 255),
            (int)(rgb.blueComponent * 255)];
}

static NSColor *XLColorFromHex(NSString *hex) {
    if (hex.length < 7) return nil;
    unsigned int r, g, b;
    NSScanner *scanner = [NSScanner scannerWithString:[hex substringFromIndex:1]];
    unsigned int rgb;
    if ([scanner scanHexInt:&rgb]) {
        r = (rgb >> 16) & 0xFF;
        g = (rgb >> 8) & 0xFF;
        b = rgb & 0xFF;
        return [NSColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
    }
    return nil;
}

/// Audio extensions to scan when importing from a folder.
static NSSet<NSString *> *XLAudioExtensions(void) {
    static NSSet *exts = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        exts = [NSSet setWithObjects:@"wav", @"mp3", @"m4a", @"aac", @"aiff", @"aif", @"flac", nil];
    });
    return exts;
}

/// Derive a display name from a filename (strip extension, capitalize).
static NSString *XLStemNameFromFilename(NSString *filename) {
    NSString *name = [filename stringByDeletingPathExtension];
    if (name.length > 0) {
        return [[[name substringToIndex:1] uppercaseString]
                stringByAppendingString:[name substringFromIndex:1]];
    }
    return name;
}

@implementation XLStemManager {
    NSMutableArray<XLStemData *> *_stems;
    dispatch_queue_t _loadQueue;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _stems = [NSMutableArray array];
        _loadQueue = dispatch_queue_create("org.xlights.stemLoader", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (NSArray<XLStemData *> *)stems {
    return [_stems copy];
}

#pragma mark - Import

- (void)importStemFiles:(NSArray<NSURL *> *)fileURLs completion:(void (^)(void))completion {
    NSLog(@"[Stems] importStemFiles: %lu files", (unsigned long)fileURLs.count);
    if (fileURLs.count == 0) {
        if (completion) completion();
        return;
    }

    NSMutableArray<XLStemData *> *newStems = [NSMutableArray array];
    NSUInteger baseIndex = _stems.count;

    for (NSUInteger i = 0; i < fileURLs.count; i++) {
        NSURL *url = fileURLs[i];
        XLStemData *stem = [[XLStemData alloc] init];
        stem.name = XLStemNameFromFilename(url.lastPathComponent);
        stem.filePath = url.path;
        stem.relativePath = [self relativePathForFile:url.path];
        stem.waveformColor = XLStemColorPalette(baseIndex + i);
        stem.isLoading = YES;
        NSLog(@"[Stems]   stem '%@' path=%@", stem.name, stem.filePath);
        [newStems addObject:stem];
    }

    [_stems addObjectsFromArray:newStems];
    NSLog(@"[Stems] Total stems now: %lu, posting notification", (unsigned long)_stems.count);
    [self postChangeNotification];

    dispatch_group_t group = dispatch_group_create();

    for (XLStemData *stem in newStems) {
        dispatch_group_enter(group);
        dispatch_async(_loadQueue, ^{
            NSLog(@"[Stems] Loading audio for '%@' from %@", stem.name, stem.filePath);
            XLAudioSampleData *audioData = [XLAudioLoader loadAudioFile:stem.filePath];
            NSArray<NSValue *> *buckets = nil;
            CGFloat durationMS = 0;
            if (audioData) {
                buckets = [XLAudioLoader generateWaveformOverview:audioData bucketCount:kStemBucketCount];
                durationMS = audioData.duration * 1000.0;
                NSLog(@"[Stems] Loaded '%@': %lu samples, %lu buckets, %.0fms",
                      stem.name, (unsigned long)audioData.sampleCount,
                      (unsigned long)buckets.count, durationMS);
            } else {
                NSLog(@"[Stems] FAILED to load audio for '%@'", stem.name);
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                stem.audioData = audioData;
                stem.overviewBuckets = buckets;
                stem.durationMS = durationMS;
                stem.isLoading = NO;
                NSLog(@"[Stems] Stem '%@' ready: buckets=%lu duration=%.0fms",
                      stem.name, (unsigned long)(stem.overviewBuckets.count), stem.durationMS);
                [self postChangeNotification];
            });
            dispatch_group_leave(group);
        });
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSLog(@"[Stems] All %lu stems finished loading", (unsigned long)newStems.count);
        if (completion) completion();
    });
}

- (void)importStemsFromFolder:(NSURL *)folderURL completion:(void (^)(void))completion {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSURL *> *contents = [fm contentsOfDirectoryAtURL:folderURL
                                   includingPropertiesForKeys:nil
                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        error:nil];
    NSSet<NSString *> *exts = XLAudioExtensions();
    NSMutableArray<NSURL *> *audioFiles = [NSMutableArray array];
    for (NSURL *url in contents) {
        if ([exts containsObject:url.pathExtension.lowercaseString]) {
            [audioFiles addObject:url];
        }
    }

    // Sort alphabetically for consistent ordering
    [audioFiles sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.lastPathComponent caseInsensitiveCompare:b.lastPathComponent];
    }];

    [self importStemFiles:audioFiles completion:completion];
}

#pragma mark - Remove

- (void)removeStemAtIndex:(NSUInteger)index {
    if (index < _stems.count) {
        [_stems removeObjectAtIndex:index];
        [self postChangeNotification];
    }
}

- (void)removeAllStems {
    [_stems removeAllObjects];
    [self postChangeNotification];
}

#pragma mark - Serialization

- (NSArray<NSDictionary<NSString *, NSString *> *> *)serializeToDicts {
    NSMutableArray *result = [NSMutableArray array];
    for (XLStemData *stem in _stems) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"name"] = stem.name ?: @"";
        dict[@"relativePath"] = stem.relativePath ?: @"";
        dict[@"color"] = XLHexFromColor(stem.waveformColor);
        [result addObject:dict];
    }
    return result;
}

- (void)restoreFromDicts:(NSArray<NSDictionary<NSString *, NSString *> *> *)dicts {
    [_stems removeAllObjects];

    NSMutableArray<NSURL *> *urlsToLoad = [NSMutableArray array];

    for (NSUInteger i = 0; i < dicts.count; i++) {
        NSDictionary *dict = dicts[i];
        XLStemData *stem = [[XLStemData alloc] init];
        stem.name = dict[@"name"] ?: @"Stem";
        stem.relativePath = dict[@"relativePath"] ?: @"";

        NSString *colorHex = dict[@"color"];
        stem.waveformColor = colorHex ? XLColorFromHex(colorHex) : XLStemColorPalette(i);
        if (!stem.waveformColor) stem.waveformColor = XLStemColorPalette(i);

        // Resolve absolute path from relative
        stem.filePath = [self absolutePathForRelative:stem.relativePath];
        stem.isLoading = YES;

        [_stems addObject:stem];
        if (stem.filePath) {
            [urlsToLoad addObject:[NSURL fileURLWithPath:stem.filePath]];
        }
    }

    [self postChangeNotification];

    // Load audio on background queue
    dispatch_group_t group = dispatch_group_create();
    for (XLStemData *stem in _stems) {
        if (!stem.filePath || ![[NSFileManager defaultManager] fileExistsAtPath:stem.filePath]) {
            stem.isLoading = NO;
            continue;
        }
        dispatch_group_enter(group);
        dispatch_async(_loadQueue, ^{
            XLAudioSampleData *audioData = [XLAudioLoader loadAudioFile:stem.filePath];
            NSArray<NSValue *> *buckets = nil;
            CGFloat durationMS = 0;
            if (audioData) {
                buckets = [XLAudioLoader generateWaveformOverview:audioData bucketCount:kStemBucketCount];
                durationMS = audioData.duration * 1000.0;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                stem.audioData = audioData;
                stem.overviewBuckets = buckets;
                stem.durationMS = durationMS;
                stem.isLoading = NO;
                [self postChangeNotification];
            });
            dispatch_group_leave(group);
        });
    }
}

#pragma mark - Path Helpers

- (NSString *)relativePathForFile:(NSString *)absolutePath {
    if (!_showFolderPath || !absolutePath) return absolutePath;
    if ([absolutePath hasPrefix:_showFolderPath]) {
        NSString *rel = [absolutePath substringFromIndex:_showFolderPath.length];
        if ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
        return rel;
    }
    return absolutePath;
}

- (NSString *)absolutePathForRelative:(NSString *)relativePath {
    if (!relativePath || relativePath.length == 0) return nil;
    if ([relativePath hasPrefix:@"/"]) return relativePath;  // Already absolute
    if (!_showFolderPath) return nil;
    return [_showFolderPath stringByAppendingPathComponent:relativePath];
}

#pragma mark - Notifications

- (void)postChangeNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:XLStemManagerDidChangeNotification
                                                        object:self];
}

@end
