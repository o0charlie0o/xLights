#import <Cocoa/Cocoa.h>
#import "InspectorGroup.h"
#import "InspectorProperty.h"
#import "InspectorDisclosureGroup.h"

@class InspectorView;

/// Delegate protocol for receiving inspector events.
@protocol InspectorViewDelegate <NSObject>
@optional
- (void)inspectorView:(InspectorView *)inspectorView
    didChangeProperty:(InspectorProperty *)property
              inGroup:(InspectorGroup *)group;
@end

/// A reusable property inspector view modeled after Xcode/Sketch inspectors.
///
/// InspectorView displays a vertical list of disclosure groups, each
/// containing typed property rows. It wraps content in an NSScrollView
/// for large property sets.
///
/// Usage:
///   InspectorView *inspector = [[InspectorView alloc] initWithFrame:rect];
///   [inspector setGroups:@[generalGroup, positionGroup, ...]];
///
/// The view handles its own scroll view and can be embedded in any
/// container (NSSplitView sidebar, sheet, etc.).
@interface InspectorView : NSView

@property (nonatomic, weak) id<InspectorViewDelegate> delegate;
@property (nonatomic, copy, readonly) NSArray<InspectorGroup *> *groups;

/// Replace all groups and rebuild the view hierarchy.
- (void)setGroups:(NSArray<InspectorGroup *> *)groups;

/// Find a property by its identifier across all groups.
- (InspectorProperty *)propertyWithId:(NSString *)identifier;

/// Find a group by its identifier.
- (InspectorGroup *)groupWithId:(NSString *)identifier;

/// Refresh all controls from their model values.
- (void)refreshFromModel;

/// Expand or collapse all groups.
- (void)expandAll;
- (void)collapseAll;

/// Get all current property values as a dictionary keyed by identifier.
- (NSDictionary<NSString *, id> *)allValues;

@end
