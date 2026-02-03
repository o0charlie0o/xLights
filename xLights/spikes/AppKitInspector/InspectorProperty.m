#import "InspectorProperty.h"

@implementation InspectorProperty

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = YES;
        _minValue = 0.0;
        _maxValue = 100.0;
        _tickInterval = 1.0;
    }
    return self;
}

+ (instancetype)textPropertyWithId:(NSString *)identifier
                             label:(NSString *)label
                             value:(NSString *)value {
    InspectorProperty *prop = [[InspectorProperty alloc] init];
    prop.identifier = identifier;
    prop.label = label;
    prop.type = InspectorPropertyTypeText;
    prop.value = value ?: @"";
    return prop;
}

+ (instancetype)numberPropertyWithId:(NSString *)identifier
                               label:(NSString *)label
                               value:(NSNumber *)value {
    InspectorProperty *prop = [[InspectorProperty alloc] init];
    prop.identifier = identifier;
    prop.label = label;
    prop.type = InspectorPropertyTypeNumber;
    prop.value = value ?: @0;
    return prop;
}

+ (instancetype)sliderPropertyWithId:(NSString *)identifier
                               label:(NSString *)label
                               value:(double)value
                                 min:(double)min
                                 max:(double)max {
    InspectorProperty *prop = [[InspectorProperty alloc] init];
    prop.identifier = identifier;
    prop.label = label;
    prop.type = InspectorPropertyTypeSlider;
    prop.value = @(value);
    prop.minValue = min;
    prop.maxValue = max;
    return prop;
}

+ (instancetype)choicePropertyWithId:(NSString *)identifier
                               label:(NSString *)label
                             choices:(NSArray<NSString *> *)choices
                       selectedIndex:(NSInteger)selectedIndex {
    InspectorProperty *prop = [[InspectorProperty alloc] init];
    prop.identifier = identifier;
    prop.label = label;
    prop.type = InspectorPropertyTypeChoice;
    prop.choices = choices;
    prop.value = @(selectedIndex);
    return prop;
}

+ (instancetype)togglePropertyWithId:(NSString *)identifier
                               label:(NSString *)label
                               value:(BOOL)value {
    InspectorProperty *prop = [[InspectorProperty alloc] init];
    prop.identifier = identifier;
    prop.label = label;
    prop.type = InspectorPropertyTypeToggle;
    prop.value = @(value);
    return prop;
}

+ (instancetype)colorPropertyWithId:(NSString *)identifier
                              label:(NSString *)label
                              color:(NSColor *)color {
    InspectorProperty *prop = [[InspectorProperty alloc] init];
    prop.identifier = identifier;
    prop.label = label;
    prop.type = InspectorPropertyTypeColor;
    prop.value = color ?: [NSColor whiteColor];
    return prop;
}

+ (instancetype)pathPropertyWithId:(NSString *)identifier
                             label:(NSString *)label
                              path:(NSString *)path
                     allowedTypes:(NSArray<NSString *> *)types {
    InspectorProperty *prop = [[InspectorProperty alloc] init];
    prop.identifier = identifier;
    prop.label = label;
    prop.type = InspectorPropertyTypePath;
    prop.value = path ?: @"";
    prop.allowedFileTypes = types;
    return prop;
}

@end
