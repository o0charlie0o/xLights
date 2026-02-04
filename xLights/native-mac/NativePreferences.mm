/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "NativePreferences.h"

@interface NativePreferences ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation NativePreferences

#pragma mark - Lifecycle

+ (instancetype)sharedPreferences {
    static NativePreferences *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[NativePreferences alloc] initWithSuiteName:nil];
    });
    return sharedInstance;
}

- (instancetype)initWithSuiteName:(nullable NSString *)suiteName {
    self = [super init];
    if (self) {
        if (suiteName) {
            _defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
        } else {
            _defaults = [NSUserDefaults standardUserDefaults];
        }
    }
    return self;
}

- (instancetype)init {
    return [self initWithSuiteName:nil];
}

#pragma mark - String Operations

- (NSString *)stringForKey:(NSString *)key defaultValue:(NSString *)defaultValue {
    NSString *value = [self.defaults stringForKey:key];
    return value ?: defaultValue;
}

- (std::string)getString:(const std::string&)key defaultValue:(const std::string&)defaultValue {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    NSString *nsDefault = [NativePreferences nsStringFromStdString:defaultValue];
    NSString *result = [self stringForKey:nsKey defaultValue:nsDefault];
    return [NativePreferences stdStringFromNSString:result];
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
    [self.defaults setObject:value forKey:key];
}

- (void)setString:(const std::string&)key value:(const std::string&)value {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    NSString *nsValue = [NativePreferences nsStringFromStdString:value];
    [self setString:nsValue forKey:nsKey];
}

#pragma mark - Integer Operations

- (NSInteger)integerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue {
    if ([self.defaults objectForKey:key] == nil) {
        return defaultValue;
    }
    return [self.defaults integerForKey:key];
}

- (int)getInt:(const std::string&)key defaultValue:(int)defaultValue {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    return (int)[self integerForKey:nsKey defaultValue:defaultValue];
}

- (long)getLong:(const std::string&)key defaultValue:(long)defaultValue {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    return (long)[self integerForKey:nsKey defaultValue:defaultValue];
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    [self.defaults setInteger:value forKey:key];
}

- (void)setInt:(const std::string&)key value:(int)value {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    [self setInteger:value forKey:nsKey];
}

- (void)setLong:(const std::string&)key value:(long)value {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    [self setInteger:value forKey:nsKey];
}

#pragma mark - Boolean Operations

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    if ([self.defaults objectForKey:key] == nil) {
        return defaultValue;
    }
    return [self.defaults boolForKey:key];
}

- (bool)getBool:(const std::string&)key defaultValue:(bool)defaultValue {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    return [self boolForKey:nsKey defaultValue:defaultValue];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    [self.defaults setBool:value forKey:key];
}

- (void)setBool:(const std::string&)key value:(bool)value {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    [self setBool:value forKey:nsKey];
}

#pragma mark - Double/Float Operations

- (double)doubleForKey:(NSString *)key defaultValue:(double)defaultValue {
    if ([self.defaults objectForKey:key] == nil) {
        return defaultValue;
    }
    return [self.defaults doubleForKey:key];
}

- (double)getDouble:(const std::string&)key defaultValue:(double)defaultValue {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    return [self doubleForKey:nsKey defaultValue:defaultValue];
}

- (float)getFloat:(const std::string&)key defaultValue:(float)defaultValue {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    return (float)[self doubleForKey:nsKey defaultValue:defaultValue];
}

- (void)setDouble:(double)value forKey:(NSString *)key {
    [self.defaults setDouble:value forKey:key];
}

- (void)setDouble:(const std::string&)key value:(double)value {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    [self setDouble:value forKey:nsKey];
}

- (void)setFloat:(const std::string&)key value:(float)value {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    [self setDouble:value forKey:nsKey];
}

#pragma mark - Data Operations

- (nullable NSData *)dataForKey:(NSString *)key {
    return [self.defaults dataForKey:key];
}

- (void)setData:(NSData *)data forKey:(NSString *)key {
    [self.defaults setObject:data forKey:key];
}

#pragma mark - Array Operations

- (NSArray<NSString *> *)stringArrayForKey:(NSString *)key {
    NSArray *array = [self.defaults stringArrayForKey:key];
    return array ?: @[];
}

- (std::vector<std::string>)getStringArray:(const std::string&)key {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    NSArray<NSString *> *array = [self stringArrayForKey:nsKey];

    std::vector<std::string> result;
    result.reserve(array.count);
    for (NSString *str in array) {
        result.push_back([NativePreferences stdStringFromNSString:str]);
    }
    return result;
}

- (void)setStringArray:(NSArray<NSString *> *)array forKey:(NSString *)key {
    [self.defaults setObject:array forKey:key];
}

- (void)setStringArray:(const std::string&)key values:(const std::vector<std::string>&)values {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];

    NSMutableArray<NSString *> *array = [NSMutableArray arrayWithCapacity:values.size()];
    for (const auto& str : values) {
        [array addObject:[NativePreferences nsStringFromStdString:str]];
    }
    [self setStringArray:array forKey:nsKey];
}

#pragma mark - Dictionary Operations

- (nullable NSDictionary *)dictionaryForKey:(NSString *)key {
    return [self.defaults dictionaryForKey:key];
}

- (void)setDictionary:(NSDictionary *)dictionary forKey:(NSString *)key {
    [self.defaults setObject:dictionary forKey:key];
}

#pragma mark - Key Management

- (BOOL)hasKey:(NSString *)key {
    return [self.defaults objectForKey:key] != nil;
}

- (bool)hasKeyStd:(const std::string&)key {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    return [self hasKey:nsKey];
}

- (void)removeKey:(NSString *)key {
    [self.defaults removeObjectForKey:key];
}

- (void)removeKeyStd:(const std::string&)key {
    NSString *nsKey = [NativePreferences nsStringFromStdString:key];
    [self removeKey:nsKey];
}

- (NSArray<NSString *> *)allKeys {
    NSDictionary *dict = [self.defaults dictionaryRepresentation];
    return [dict allKeys];
}

#pragma mark - Synchronization

- (BOOL)synchronize {
    return [self.defaults synchronize];
}

#pragma mark - Migration Support

- (void)registerDefaults:(NSDictionary *)defaults {
    [self.defaults registerDefaults:defaults];
}

- (void)resetToDefaults {
    NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
    if (appDomain) {
        [self.defaults removePersistentDomainForName:appDomain];
    }
}

#pragma mark - Utility Methods

+ (std::string)stdStringFromNSString:(NSString *)nsString {
    if (!nsString) {
        return std::string();
    }
    return std::string([nsString UTF8String]);
}

+ (NSString *)nsStringFromStdString:(const std::string&)stdString {
    return [NSString stringWithUTF8String:stdString.c_str()];
}

@end
