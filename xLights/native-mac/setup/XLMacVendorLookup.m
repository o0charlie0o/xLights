/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLMacVendorLookup.h"
#import "XLNetworkDiscoveryTypes.h"
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

/// Internal storage for MAC vendor entries.
/// Uses C array to avoid heap corruption from ObjC/C++ mixing.
static XLMacVendorEntry *_vendorEntries = NULL;
static size_t _vendorCount = 0;
static pthread_mutex_t _vendorMutex = PTHREAD_MUTEX_INITIALIZER;
static BOOL _vendorLoaded = NO;

/// Binary search comparator for vendor lookup.
static int compareVendorPrefix(const void *key, const void *entry) {
    const char *prefix = (const char *)key;
    const XLMacVendorEntry *vendor = (const XLMacVendorEntry *)entry;
    return strncasecmp(prefix, vendor->prefix, 6);
}

/// Sort comparator for vendor entries.
static int compareVendorEntries(const void *a, const void *b) {
    const XLMacVendorEntry *va = (const XLMacVendorEntry *)a;
    const XLMacVendorEntry *vb = (const XLMacVendorEntry *)b;
    return strncasecmp(va->prefix, vb->prefix, 6);
}

@implementation XLMacVendorLookup

+ (instancetype)sharedInstance {
    static XLMacVendorLookup *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[XLMacVendorLookup alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    return self;
}

- (void)dealloc {
    pthread_mutex_lock(&_vendorMutex);
    if (_vendorEntries) {
        free(_vendorEntries);
        _vendorEntries = NULL;
        _vendorCount = 0;
    }
    pthread_mutex_unlock(&_vendorMutex);
}

- (BOOL)isLoaded {
    pthread_mutex_lock(&_vendorMutex);
    BOOL loaded = _vendorLoaded;
    pthread_mutex_unlock(&_vendorMutex);
    return loaded;
}

- (NSUInteger)entryCount {
    pthread_mutex_lock(&_vendorMutex);
    NSUInteger count = _vendorCount;
    pthread_mutex_unlock(&_vendorMutex);
    return count;
}

- (void)loadDatabase {
    pthread_mutex_lock(&_vendorMutex);
    if (_vendorLoaded) {
        pthread_mutex_unlock(&_vendorMutex);
        return;
    }

    // Find MacLookup.txt in bundle resources
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *path = [bundle pathForResource:@"MacLookup" ofType:@"txt" inDirectory:@"xScanner"];

    if (!path) {
        // Try alternate locations
        path = [bundle pathForResource:@"MacLookup" ofType:@"txt"];
    }

    if (!path) {
        NSLog(@"XLMacVendorLookup: MacLookup.txt not found in bundle");
        _vendorLoaded = YES; // Mark as loaded even if file not found
        pthread_mutex_unlock(&_vendorMutex);
        return;
    }

    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
    if (error || !contents) {
        NSLog(@"XLMacVendorLookup: Failed to read MacLookup.txt: %@", error);
        _vendorLoaded = YES;
        pthread_mutex_unlock(&_vendorMutex);
        return;
    }

    // Count lines first to allocate array
    NSArray<NSString *> *lines = [contents componentsSeparatedByString:@"\n"];
    size_t maxEntries = lines.count;

    if (maxEntries > XL_MAX_MAC_VENDORS) {
        maxEntries = XL_MAX_MAC_VENDORS;
    }

    _vendorEntries = (XLMacVendorEntry *)calloc(maxEntries, sizeof(XLMacVendorEntry));
    if (!_vendorEntries) {
        NSLog(@"XLMacVendorLookup: Failed to allocate memory for %zu entries", maxEntries);
        _vendorLoaded = YES;
        pthread_mutex_unlock(&_vendorMutex);
        return;
    }

    // Parse lines in format "PREFIX|VENDOR"
    _vendorCount = 0;
    for (NSString *line in lines) {
        if (_vendorCount >= maxEntries) break;

        NSArray<NSString *> *parts = [line componentsSeparatedByString:@"|"];
        if (parts.count < 2) continue;

        NSString *prefix = parts[0];
        NSString *vendor = parts[1];

        if (prefix.length < 6) continue;

        XLMacVendorEntry *entry = &_vendorEntries[_vendorCount];

        // Copy prefix (first 6 chars, uppercase)
        const char *prefixCStr = [prefix UTF8String];
        for (int i = 0; i < 6 && prefixCStr[i]; i++) {
            char c = prefixCStr[i];
            if (c >= 'a' && c <= 'f') c -= 32; // uppercase
            entry->prefix[i] = c;
        }
        entry->prefix[6] = '\0';

        // Copy vendor name
        xl_safe_strcpy(entry->vendor, sizeof(entry->vendor), [vendor UTF8String]);

        _vendorCount++;
    }

    // Sort for binary search
    qsort(_vendorEntries, _vendorCount, sizeof(XLMacVendorEntry), compareVendorEntries);

    NSLog(@"XLMacVendorLookup: Loaded %zu vendor entries", _vendorCount);
    _vendorLoaded = YES;
    pthread_mutex_unlock(&_vendorMutex);
}

- (NSString *)vendorForMacAddress:(NSString *)macAddress {
    if (!macAddress || macAddress.length < 6) return nil;

    // Ensure database is loaded
    if (!self.isLoaded) {
        [self loadDatabase];
    }

    pthread_mutex_lock(&_vendorMutex);

    if (!_vendorEntries || _vendorCount == 0) {
        pthread_mutex_unlock(&_vendorMutex);
        return nil;
    }

    // Extract first 6 hex characters from MAC address
    // Handles formats: XX:XX:XX:XX:XX:XX, XX-XX-XX-XX-XX-XX, XXXXXXXXXXXX
    char prefix[7] = {0};
    int prefixIdx = 0;
    const char *mac = [macAddress UTF8String];

    for (int i = 0; mac[i] && prefixIdx < 6; i++) {
        char c = mac[i];
        if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
            if (c >= 'a' && c <= 'f') c -= 32; // uppercase
            prefix[prefixIdx++] = c;
        }
        // Skip separators (: - .)
    }

    if (prefixIdx < 6) {
        pthread_mutex_unlock(&_vendorMutex);
        return nil;
    }

    // Binary search for vendor
    XLMacVendorEntry *found = bsearch(prefix, _vendorEntries, _vendorCount,
                                       sizeof(XLMacVendorEntry), compareVendorPrefix);

    NSString *result = nil;
    if (found) {
        result = [NSString stringWithUTF8String:found->vendor];
    }

    pthread_mutex_unlock(&_vendorMutex);
    return result;
}

@end
