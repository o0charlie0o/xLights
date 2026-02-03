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

/// Handle types for model manipulation.
/// Matches the xLights C++ handle constants.
typedef NS_ENUM(NSInteger, XLHandleType) {
    XLHandleTypeNone = -1,
    XLHandleTypeCenter = 0,
    XLHandleTypeLeftTop = 1,
    XLHandleTypeRightTop = 2,
    XLHandleTypeRightBottom = 3,
    XLHandleTypeLeftBottom = 4,
    XLHandleTypeRotate = 5,
    XLHandleTypeLeftTopZ = 6,
    XLHandleTypeRightTopZ = 7,
    XLHandleTypeRightBottomZ = 8,
    XLHandleTypeLeftBottomZ = 9,
};

/// Manipulation tool mode.
typedef NS_ENUM(NSInteger, XLToolMode) {
    XLToolModeTranslate = 0,
    XLToolModeScale = 1,
    XLToolModeRotate = 2,
    XLToolModeXYTranslate = 3,
    XLToolModeElevate = 4,
    XLToolModeNone = 5,
};

/// Active axis for manipulation.
typedef NS_ENUM(NSInteger, XLActiveAxis) {
    XLActiveAxisNone = -1,
    XLActiveAxisX = 0,
    XLActiveAxisY = 1,
    XLActiveAxisZ = 2,
};

/// C struct for handle position (heap corruption immune).
typedef struct {
    float x;
    float y;
    float z;
} XLHandlePosition;

/// C struct for model transform state (heap corruption immune).
typedef struct {
    simd_float3 position;
    simd_float3 scale;
    simd_float3 rotation;
    simd_float3 boundingBoxMin;
    simd_float3 boundingBoxMax;
    float renderWidth;
    float renderHeight;
    float renderDepth;
    BOOL isLocked;
    BOOL supportsZScaling;
} XLModelTransform;

/// C struct for snap guide line (heap corruption immune).
typedef struct {
    simd_float3 start;
    simd_float3 end;
    float r, g, b, a;
    BOOL active;
} XLSnapGuide;

#define XL_MAX_HANDLES 16
#define XL_MAX_SNAP_GUIDES 8

/// Metal-based renderer for 2D/3D manipulation handles.
///
/// Renders selection boxes, corner handles, rotation handles, axis tools,
/// and snap guides for model manipulation in the preview view.
///
/// Uses C arrays for all frequently-accessed data to maintain heap immunity
/// from wxWidgets/C++ corruption.
@interface XLManipulationHandlesRenderer : NSObject

#pragma mark - Initialization

- (instancetype)initWithDevice:(id<MTLDevice>)device;

#pragma mark - State

/// Current tool mode (translate, scale, rotate)
@property (nonatomic, assign) XLToolMode toolMode;

/// Currently active axis for constrained manipulation
@property (nonatomic, assign) XLActiveAxis activeAxis;

/// Active handle being manipulated (-1 = none)
@property (nonatomic, assign) NSInteger activeHandle;

/// Highlighted handle (mouse hover, -1 = none)
@property (nonatomic, assign) NSInteger highlightedHandle;

/// Whether currently in 3D mode
@property (nonatomic, assign) BOOL is3D;

/// Grid snap size (0 = disabled)
@property (nonatomic, assign) float gridSnapSize;

/// Angle snap increment in degrees (0 = disabled)
@property (nonatomic, assign) float angleSnapDegrees;

/// Whether edge snapping is enabled
@property (nonatomic, assign) BOOL edgeSnapEnabled;

#pragma mark - Model State

/// Set the transform for the selected model
- (void)setModelTransform:(XLModelTransform)transform;

/// Get the current model transform
- (XLModelTransform)modelTransform;

/// Clear selection (no handles drawn)
- (void)clearSelection;

#pragma mark - Handle Positions

/// Get handle positions (C array, read-only access)
- (const XLHandlePosition *)handlePositions;

/// Get number of active handles
- (NSInteger)handleCount;

/// Get the position of a specific handle
- (simd_float3)positionForHandle:(XLHandleType)handleType;

#pragma mark - Hit Testing

/// Test if a ray intersects any handle.
/// Returns XLHandleTypeNone if no intersection.
- (XLHandleType)hitTestWithRayOrigin:(simd_float3)rayOrigin
                        rayDirection:(simd_float3)rayDirection
                                zoom:(float)zoom
                               scale:(int)scale;

/// Test if a screen point is over a handle (2D mode).
- (XLHandleType)hitTestAtScreenPoint:(CGPoint)point
                          viewWidth:(CGFloat)viewWidth
                         viewHeight:(CGFloat)viewHeight
                     viewProjection:(simd_float4x4)viewProjection
                               zoom:(float)zoom
                              scale:(int)scale;

#pragma mark - Manipulation

/// Begin a drag operation on a handle.
/// Stores initial state for delta calculations.
- (void)beginDragAtPoint:(simd_float3)worldPoint
               forHandle:(XLHandleType)handle;

/// Update drag with a new world point.
/// Returns the delta from the initial drag point.
/// @param shiftHeld YES if shift key is held (proportional/constrained)
/// @param optionHeld YES if option/alt key is held (center-anchored)
/// @param cmdHeld YES if cmd key is held (free rotation)
- (simd_float3)updateDragToPoint:(simd_float3)worldPoint
                       shiftHeld:(BOOL)shiftHeld
                      optionHeld:(BOOL)optionHeld
                         cmdHeld:(BOOL)cmdHeld;

/// End the current drag operation.
- (void)endDrag;

/// Apply snapping to a proposed position.
- (simd_float3)snapPosition:(simd_float3)position;

/// Apply angle snapping to a proposed rotation.
- (float)snapAngle:(float)angleDegrees;

#pragma mark - Snap Guides

/// Set snap guide lines (max XL_MAX_SNAP_GUIDES).
- (void)setSnapGuides:(const XLSnapGuide *)guides count:(NSInteger)count;

/// Clear all snap guides.
- (void)clearSnapGuides;

#pragma mark - Rendering

/// Render handles into the given encoder.
/// @param encoder The render command encoder.
/// @param viewProjection Combined view-projection matrix.
/// @param zoom Camera zoom level.
/// @param scale UI scale factor.
- (void)renderWithEncoder:(id<MTLRenderCommandEncoder>)encoder
           viewProjection:(simd_float4x4)viewProjection
                     zoom:(float)zoom
                    scale:(int)scale;

#pragma mark - Cursor

/// Get appropriate cursor for the given handle.
/// Returns a string identifier: "default", "resize-nwse", "resize-nesw",
/// "resize-ew", "resize-ns", "rotate", "move"
- (NSString *)cursorForHandle:(XLHandleType)handle rotation:(float)rotationZ;

@end

NS_ASSUME_NONNULL_END
