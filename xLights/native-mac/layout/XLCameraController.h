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

@end
