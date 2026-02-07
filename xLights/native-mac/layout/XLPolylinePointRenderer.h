/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

/// Represents a single polyline control point with optional curve data.
typedef struct {
    simd_float3 position;       // World-space position of the point
    BOOL hasCurve;              // Whether this segment has a Bezier curve
    simd_float3 cp0;            // Control point 0 (curve start control)
    simd_float3 cp1;            // Control point 1 (curve end control)
} XLPolylinePoint;

#define XL_MAX_POLYLINE_POINTS 128

/// Hit result types for polyline point interaction.
typedef NS_ENUM(NSInteger, XLPolylineHitType) {
    XLPolylineHitNone = -1,
    XLPolylineHitPoint = 0,     // Hit a control point (index in hitIndex)
    XLPolylineHitSegment = 1,   // Hit a segment between points (index in hitIndex)
    XLPolylineHitCP0 = 2,       // Hit curve control point 0 (segment index in hitIndex)
    XLPolylineHitCP1 = 3,       // Hit curve control point 1 (segment index in hitIndex)
};

/// Metal-based renderer for polyline control points and segment handles.
///
/// Renders individual draggable control points, segment lines, Bezier curve
/// control handles, and visual feedback during polyline editing.
/// Uses the same shader pipeline as XLManipulationHandlesRenderer.
@interface XLPolylinePointRenderer : NSObject

#pragma mark - Initialization

- (instancetype)initWithDevice:(id<MTLDevice>)device;

#pragma mark - State

/// Whether polyline editing is active
@property (nonatomic, assign) BOOL active;

/// Number of polyline points
@property (nonatomic, assign, readonly) NSInteger pointCount;

/// Currently selected point index (-1 = none)
@property (nonatomic, assign) NSInteger selectedPoint;

/// Currently selected segment index (-1 = none)
@property (nonatomic, assign) NSInteger selectedSegment;

/// Highlighted point (mouse hover, -1 = none)
@property (nonatomic, assign) NSInteger highlightedPoint;

/// Whether currently dragging a point
@property (nonatomic, assign, readonly) BOOL isDragging;

/// Handle size factor for zoom scaling
@property (nonatomic, assign) float handleSize;

#pragma mark - Point Data

/// Set the polyline points from model data.
/// @param points Array of XLPolylinePoint structs
/// @param count Number of points
- (void)setPoints:(const XLPolylinePoint *)points count:(NSInteger)count;

/// Get the position of a specific point.
- (simd_float3)positionForPoint:(NSInteger)index;

/// Clear all points (deactivates rendering)
- (void)clearPoints;

#pragma mark - Hit Testing

/// Test if a ray intersects any polyline handle.
/// @param rayOrigin Ray start position in world space
/// @param rayDirection Normalized ray direction
/// @param zoom Camera zoom level for handle size scaling
/// @param hitIndex Output: index of the hit element
/// @return Type of element hit, or XLPolylineHitNone
- (XLPolylineHitType)hitTestWithRayOrigin:(simd_float3)rayOrigin
                             rayDirection:(simd_float3)rayDirection
                                     zoom:(float)zoom
                                 hitIndex:(NSInteger *)hitIndex;

#pragma mark - Dragging

/// Begin dragging a point.
/// @param worldPoint Initial world position
/// @param pointIndex Index of the point being dragged
/// @param hitType Type of element being dragged
- (void)beginDragAtPoint:(simd_float3)worldPoint
              pointIndex:(NSInteger)pointIndex
                 hitType:(XLPolylineHitType)hitType;

/// Update drag with a new world point.
/// @return The new position for the dragged element
- (simd_float3)updateDragToPoint:(simd_float3)worldPoint;

/// End the current drag operation.
- (void)endDrag;

#pragma mark - Rendering

/// Render polyline handles into the given encoder.
/// @param encoder The render command encoder
/// @param viewProjection Combined view-projection matrix
/// @param zoom Camera zoom level
/// @param scale UI scale factor
- (void)renderWithEncoder:(id<MTLRenderCommandEncoder>)encoder
           viewProjection:(simd_float4x4)viewProjection
                     zoom:(float)zoom
                    scale:(int)scale;

#pragma mark - Cursor

/// Get appropriate cursor name for the given hit type.
/// Returns "default", "hand", or "crosshair"
- (NSString *)cursorForHitType:(XLPolylineHitType)hitType;

@end

NS_ASSUME_NONNULL_END
