#import <Cocoa/Cocoa.h>

/// Property types supported by the inspector view.
typedef NS_ENUM(NSInteger, InspectorPropertyType) {
    InspectorPropertyTypeText,       // Label + NSTextField
    InspectorPropertyTypeNumber,     // Label + NSTextField (numeric)
    InspectorPropertyTypeSlider,     // Label + NSSlider + NSTextField (linked)
    InspectorPropertyTypeChoice,     // Label + NSPopUpButton
    InspectorPropertyTypeToggle,     // Label + NSSwitch
    InspectorPropertyTypeColor,      // Label + NSColorWell
    InspectorPropertyTypePath,       // Label + NSTextField + Browse button
};

/// Callback fired when a property value changes.
/// The sender is the InspectorProperty whose value was modified.
typedef void (^InspectorValueChangedBlock)(id sender);
