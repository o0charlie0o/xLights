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
#import <simd/simd.h>

/// Orbit camera model for the 3D model preview.
///
/// Provides azimuth/elevation/distance orbit controls with smooth
/// animation and produces view and projection matrices suitable
/// for feeding into the Metal rendering pipeline.
@interface XLCameraController : NSObject

#pragma mark - Orbit Parameters

/// Horizontal orbit angle in radians (around Y axis)
@property (nonatomic, assign) float azimuth;

/// Vertical orbit angle in radians (above/below horizon)
@property (nonatomic, assign) float elevation;

/// Distance from the camera to the orbit target
@property (nonatomic, assign) float distance;

/// The point the camera orbits around / looks at
@property (nonatomic, assign) simd_float3 target;

/// Up vector (default: {0, 1, 0})
@property (nonatomic, assign) simd_float3 up;

#pragma mark - Limits

/// Minimum distance for zoom (prevents camera from entering target)
@property (nonatomic, assign) float minDistance;

/// Maximum distance for zoom
@property (nonatomic, assign) float maxDistance;

/// Minimum elevation angle in radians (prevents flipping)
@property (nonatomic, assign) float minElevation;

/// Maximum elevation angle in radians
@property (nonatomic, assign) float maxElevation;

#pragma mark - Projection

/// Field of view in radians for perspective projection
@property (nonatomic, assign) float fieldOfView;

/// Near clip plane distance
@property (nonatomic, assign) float nearPlane;

/// Far clip plane distance
@property (nonatomic, assign) float farPlane;

/// Whether to use 3D perspective (YES) or 2D orthographic (NO)
@property (nonatomic, assign) BOOL perspective;

#pragma mark - Computed Properties (read-only)

/// Current camera position in world space
@property (nonatomic, readonly) simd_float3 eyePosition;

/// View matrix (world -> camera space)
@property (nonatomic, readonly) simd_float4x4 viewMatrix;

/// Projection matrix for the given aspect ratio
- (simd_float4x4)projectionMatrixForAspect:(float)aspect;

/// Returns the visible world-space rectangle in orthographic mode.
/// The rect origin is the bottom-left corner (minX, minY), and size is (width, height).
/// Only meaningful when perspective == NO.
- (CGRect)visibleRectForAspect:(float)aspect;

/// Set the camera target X directly (for scrollbar-driven panning)
- (void)setTargetX:(float)x;

/// Set the camera target Y directly (for scrollbar-driven panning)
- (void)setTargetY:(float)y;

#pragma mark - Animation

/// Whether the camera is currently animating
@property (nonatomic, readonly) BOOL isAnimating;

/// Animate to new orbit parameters with ease-out timing
- (void)animateToAzimuth:(float)azimuth
               elevation:(float)elevation
                distance:(float)distance
                  target:(simd_float3)target
                duration:(NSTimeInterval)duration;

/// Advance animation by dt seconds. Returns YES if still animating.
- (BOOL)updateAnimation:(NSTimeInterval)dt;

/// Cancel any in-progress animation
- (void)cancelAnimation;

#pragma mark - Input Handling

/// Apply orbit rotation from a drag delta (in points)
- (void)orbitByDeltaX:(float)dx deltaY:(float)dy sensitivity:(float)sensitivity;

/// Apply pan translation from a drag delta (in points)
- (void)panByDeltaX:(float)dx deltaY:(float)dy sensitivity:(float)sensitivity;

/// Apply zoom from a scroll/pinch delta
- (void)zoomByDelta:(float)delta sensitivity:(float)sensitivity;

#pragma mark - Presets

/// Reset camera to default position
- (void)reset;

/// Frame a bounding box (center the target and set distance to fit)
- (void)frameBoundingBoxMin:(simd_float3)bbMin
                        max:(simd_float3)bbMax
                     aspect:(float)aspect;

/// Set camera for top-down 2D view
- (void)setTopDownView;

/// Set camera for front view
- (void)setFrontView;

/// Set camera for left view
- (void)setLeftView;

/// Set camera for right view
- (void)setRightView;

/// Set camera for back view
- (void)setBackView;

#pragma mark - Persistence

/// Save current camera state to NSUserDefaults
- (void)saveCameraState;

/// Restore camera state from NSUserDefaults. Returns YES if state was restored.
- (BOOL)restoreCameraState;

#pragma mark - Named Viewpoints

/// Save current camera state as a named viewpoint.
/// @param name Display name for the viewpoint
- (void)saveViewpointWithName:(NSString *)name;

/// Load a previously saved viewpoint by name.
/// @param name The viewpoint name to load
/// @return YES if the viewpoint was found and loaded
- (BOOL)loadViewpointWithName:(NSString *)name;

/// Delete a saved viewpoint by name.
/// @param name The viewpoint name to delete
/// @return YES if the viewpoint was found and deleted
- (BOOL)deleteViewpointWithName:(NSString *)name;

/// Get an array of all saved viewpoint names.
- (NSArray<NSString *> *)savedViewpointNames;

/// Save current camera state as the default viewpoint.
- (void)saveAsDefaultViewpoint;

/// Restore the default viewpoint. Returns YES if a default was saved.
- (BOOL)restoreDefaultViewpoint;

@end
