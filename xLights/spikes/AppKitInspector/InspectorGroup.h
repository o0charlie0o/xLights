#import <Cocoa/Cocoa.h>
#import "InspectorProperty.h"

/// Model object representing a disclosure group of properties.
///
/// Each group has a title, an expanded/collapsed state, and an ordered
/// array of InspectorProperty objects.
@interface InspectorGroup : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) NSMutableArray<InspectorProperty *> *properties;
@property (nonatomic, assign, getter=isExpanded) BOOL expanded;

+ (instancetype)groupWithTitle:(NSString *)title
                    identifier:(NSString *)identifier
                    properties:(NSArray<InspectorProperty *> *)properties;

- (void)addProperty:(InspectorProperty *)property;
- (InspectorProperty *)propertyWithId:(NSString *)identifier;

@end
