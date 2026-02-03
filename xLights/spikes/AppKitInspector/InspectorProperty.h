#import <Cocoa/Cocoa.h>
#import "InspectorTypes.h"

/// Model object representing a single property in the inspector.
///
/// Each property has a type, a label, a current value, and optional
/// configuration (min/max for sliders, choices for dropdowns, etc.).
@interface InspectorProperty : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, assign) InspectorPropertyType type;
@property (nonatomic, strong) id value;

// Slider configuration
@property (nonatomic, assign) double minValue;
@property (nonatomic, assign) double maxValue;
@property (nonatomic, assign) double tickInterval;

// Choice configuration
@property (nonatomic, copy) NSArray<NSString *> *choices;

// Path configuration
@property (nonatomic, copy) NSArray<NSString *> *allowedFileTypes;

// Change callback
@property (nonatomic, copy) InspectorValueChangedBlock onValueChanged;

// Enabled state
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

+ (instancetype)textPropertyWithId:(NSString *)identifier
                             label:(NSString *)label
                             value:(NSString *)value;

+ (instancetype)numberPropertyWithId:(NSString *)identifier
                               label:(NSString *)label
                               value:(NSNumber *)value;

+ (instancetype)sliderPropertyWithId:(NSString *)identifier
                               label:(NSString *)label
                               value:(double)value
                                 min:(double)min
                                 max:(double)max;

+ (instancetype)choicePropertyWithId:(NSString *)identifier
                               label:(NSString *)label
                             choices:(NSArray<NSString *> *)choices
                       selectedIndex:(NSInteger)selectedIndex;

+ (instancetype)togglePropertyWithId:(NSString *)identifier
                               label:(NSString *)label
                               value:(BOOL)value;

+ (instancetype)colorPropertyWithId:(NSString *)identifier
                              label:(NSString *)label
                              color:(NSColor *)color;

+ (instancetype)pathPropertyWithId:(NSString *)identifier
                             label:(NSString *)label
                              path:(NSString *)path
                     allowedTypes:(NSArray<NSString *> *)types;

@end
