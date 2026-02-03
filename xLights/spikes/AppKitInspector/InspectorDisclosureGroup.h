#import <Cocoa/Cocoa.h>
#import "InspectorGroup.h"
#import "InspectorPropertyRow.h"

/// View representing a collapsible disclosure group in the inspector.
///
/// Contains a header with a disclosure triangle and title, plus a vertical
/// stack of InspectorPropertyRow views that are shown/hidden when the
/// group is expanded/collapsed.
@interface InspectorDisclosureGroup : NSView

@property (nonatomic, strong, readonly) InspectorGroup *group;
@property (nonatomic, strong, readonly) NSArray<InspectorPropertyRow *> *propertyRows;

- (instancetype)initWithGroup:(InspectorGroup *)group;

/// Toggle the expanded/collapsed state with optional animation.
- (void)toggleExpanded:(BOOL)animated;

/// Set expanded state programmatically.
- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;

/// Refresh all property rows from their model values.
- (void)refreshFromModel;

@end
