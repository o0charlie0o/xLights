#import <Cocoa/Cocoa.h>
#import "InspectorProperty.h"

/// View representing a single property row in the inspector.
///
/// Constructs the appropriate control layout based on the property type
/// and manages bidirectional binding between the model and the controls.
@interface InspectorPropertyRow : NSView

@property (nonatomic, strong, readonly) InspectorProperty *property;

- (instancetype)initWithProperty:(InspectorProperty *)property;

/// Update the controls to reflect the current model value.
- (void)refreshFromModel;

/// The fixed label width used for alignment across rows.
+ (CGFloat)labelWidth;

@end
