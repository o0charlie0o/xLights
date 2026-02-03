#import "InspectorGroup.h"

@implementation InspectorGroup

- (instancetype)init {
    self = [super init];
    if (self) {
        _properties = [NSMutableArray array];
        _expanded = YES;
    }
    return self;
}

+ (instancetype)groupWithTitle:(NSString *)title
                    identifier:(NSString *)identifier
                    properties:(NSArray<InspectorProperty *> *)properties {
    InspectorGroup *group = [[InspectorGroup alloc] init];
    group.title = title;
    group.identifier = identifier;
    if (properties) {
        [group.properties addObjectsFromArray:properties];
    }
    return group;
}

- (void)addProperty:(InspectorProperty *)property {
    [self.properties addObject:property];
}

- (InspectorProperty *)propertyWithId:(NSString *)identifier {
    for (InspectorProperty *prop in self.properties) {
        if ([prop.identifier isEqualToString:identifier]) {
            return prop;
        }
    }
    return nil;
}

@end
