/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLCameraController.h"
#import <math.h>

static const float kDefaultAzimuth = 0.0f;
static const float kDefaultElevation = M_PI / 6.0f; // 30 degrees
static const float kDefaultDistance = 500.0f;
static const float kDefaultFOV = M_PI / 4.0f; // 45 degrees
static const float kDefaultNearPlane = 1.0f;
static const float kDefaultFarPlane = 200000.0f;
static const float kDefaultMinDistance = 10.0f;
static const float kDefaultMaxDistance = 100000.0f;
static const float kDefaultMinElevation = -M_PI_2 + 0.01f;
static const float kDefaultMaxElevation = M_PI_2 - 0.01f;

@interface XLCameraController ()

@property (nonatomic, assign) BOOL animating;
@property (nonatomic, assign) NSTimeInterval animationElapsed;
@property (nonatomic, assign) NSTimeInterval animationDuration;

@property (nonatomic, assign) float startAzimuth;
@property (nonatomic, assign) float startElevation;
@property (nonatomic, assign) float startDistance;
@property (nonatomic, assign) simd_float3 startTarget;

@property (nonatomic, assign) float endAzimuth;
@property (nonatomic, assign) float endElevation;
@property (nonatomic, assign) float endDistance;
@property (nonatomic, assign) simd_float3 endTarget;

@end

@implementation XLCameraController

- (instancetype)init {
    self = [super init];
    if (self) {
        _azimuth = kDefaultAzimuth;
        _elevation = kDefaultElevation;
        _distance = kDefaultDistance;
        _target = (simd_float3){0.0f, 0.0f, 0.0f};
        _up = (simd_float3){0.0f, 1.0f, 0.0f};

        _minDistance = kDefaultMinDistance;
        _maxDistance = kDefaultMaxDistance;
        _minElevation = kDefaultMinElevation;
        _maxElevation = kDefaultMaxElevation;

        _fieldOfView = kDefaultFOV;
        _nearPlane = kDefaultNearPlane;
        _farPlane = kDefaultFarPlane;
        _perspective = YES;

        _animating = NO;
    }
    return self;
}

#pragma mark - Computed Properties

- (simd_float3)eyePosition {
    float cosElev = cosf(_elevation);
    float x = _target.x + _distance * cosElev * sinf(_azimuth);
    float y = _target.y + _distance * sinf(_elevation);
    float z = _target.z + _distance * cosElev * cosf(_azimuth);
    return (simd_float3){x, y, z};
}

- (simd_float4x4)viewMatrix {
    simd_float3 eye = self.eyePosition;
    return [self lookAtEye:eye target:_target up:_up];
}

- (simd_float4x4)projectionMatrixForAspect:(float)aspect {
    if (_perspective) {
        return [self perspectiveMatrixFov:_fieldOfView aspect:aspect near:_nearPlane far:_farPlane];
    } else {
        float halfHeight = _distance * tanf(_fieldOfView * 0.5f);
        float halfWidth = halfHeight * aspect;
        return [self orthoMatrixLeft:-halfWidth right:halfWidth
                              bottom:-halfHeight top:halfHeight
                                near:_nearPlane far:_farPlane];
    }
}

- (BOOL)isAnimating {
    return _animating;
}

#pragma mark - Animation

- (void)animateToAzimuth:(float)azimuth
               elevation:(float)elevation
                distance:(float)distance
                  target:(simd_float3)target
                duration:(NSTimeInterval)duration {
    _startAzimuth = _azimuth;
    _startElevation = _elevation;
    _startDistance = _distance;
    _startTarget = _target;

    _endAzimuth = azimuth;
    _endElevation = elevation;
    _endDistance = distance;
    _endTarget = target;

    _animationElapsed = 0.0;
    _animationDuration = duration;
    _animating = YES;
}

- (BOOL)updateAnimation:(NSTimeInterval)dt {
    if (!_animating) return NO;

    _animationElapsed += dt;
    if (_animationElapsed >= _animationDuration) {
        _azimuth = _endAzimuth;
        _elevation = _endElevation;
        _distance = _endDistance;
        _target = _endTarget;
        _animating = NO;
        return NO;
    }

    float t = (float)(_animationElapsed / _animationDuration);
    t = [self easeOutCubic:t];

    _azimuth = _startAzimuth + (_endAzimuth - _startAzimuth) * t;
    _elevation = _startElevation + (_endElevation - _startElevation) * t;
    _distance = _startDistance + (_endDistance - _startDistance) * t;
    _target = _startTarget + (_endTarget - _startTarget) * t;

    return YES;
}

- (void)cancelAnimation {
    _animating = NO;
}

- (float)easeOutCubic:(float)t {
    float f = t - 1.0f;
    return f * f * f + 1.0f;
}

#pragma mark - Input Handling

- (void)orbitByDeltaX:(float)dx deltaY:(float)dy sensitivity:(float)sensitivity {
    [self cancelAnimation];

    _azimuth -= dx * sensitivity;
    _elevation += dy * sensitivity;

    // Wrap azimuth to [0, 2*PI]
    while (_azimuth < 0.0f) _azimuth += 2.0f * M_PI;
    while (_azimuth >= 2.0f * M_PI) _azimuth -= 2.0f * M_PI;

    // Clamp elevation
    _elevation = fmaxf(_minElevation, fminf(_maxElevation, _elevation));
}

- (void)panByDeltaX:(float)dx deltaY:(float)dy sensitivity:(float)sensitivity {
    [self cancelAnimation];

    float panScale = _distance * sensitivity;

    // Compute camera right and up vectors in world space
    simd_float3 forward = simd_normalize(_target - self.eyePosition);
    simd_float3 right = simd_normalize(simd_cross(forward, _up));
    simd_float3 camUp = simd_normalize(simd_cross(right, forward));

    _target = _target - right * (dx * panScale) + camUp * (dy * panScale);
}

- (void)zoomByDelta:(float)delta sensitivity:(float)sensitivity {
    [self cancelAnimation];

    float zoomFactor = 1.0f + delta * sensitivity;
    _distance *= zoomFactor;
    _distance = fmaxf(_minDistance, fminf(_maxDistance, _distance));
}

#pragma mark - Visible Rect (2D Orthographic)

- (CGRect)visibleRectForAspect:(float)aspect {
    float halfHeight = _distance * tanf(_fieldOfView * 0.5f);
    float halfWidth = halfHeight * aspect;
    float minX = _target.x - halfWidth;
    float minY = _target.y - halfHeight;
    return CGRectMake(minX, minY, halfWidth * 2.0f, halfHeight * 2.0f);
}

- (void)setTargetX:(float)x {
    [self cancelAnimation];
    _target = (simd_float3){x, _target.y, _target.z};
}

- (void)setTargetY:(float)y {
    [self cancelAnimation];
    _target = (simd_float3){_target.x, y, _target.z};
}

#pragma mark - Presets

- (void)reset {
    [self animateToAzimuth:kDefaultAzimuth
                 elevation:kDefaultElevation
                  distance:kDefaultDistance
                    target:(simd_float3){0.0f, 0.0f, 0.0f}
                  duration:0.3];
}

- (void)frameBoundingBoxMin:(simd_float3)bbMin
                        max:(simd_float3)bbMax
                     aspect:(float)aspect {
    simd_float3 center = (bbMin + bbMax) * 0.5f;
    simd_float3 extents = bbMax - bbMin;
    float maxExtent = fmaxf(extents.x, fmaxf(extents.y, extents.z));

    float dist;
    if (_perspective) {
        dist = (maxExtent * 0.5f) / tanf(_fieldOfView * 0.5f);
        dist *= 0.85f; // tight framing
    } else {
        dist = maxExtent * 1.5f;
    }

    [self animateToAzimuth:_azimuth
                 elevation:_elevation
                  distance:dist
                    target:center
                  duration:0.3];
}

- (void)setTopDownView {
    [self animateToAzimuth:0.0f
                 elevation:M_PI_2 - 0.01f
                  distance:_distance
                    target:_target
                  duration:0.3];
}

- (void)setFrontView {
    [self animateToAzimuth:0.0f
                 elevation:0.0f
                  distance:_distance
                    target:_target
                  duration:0.3];
}

- (void)setLeftView {
    [self animateToAzimuth:M_PI_2
                 elevation:0.0f
                  distance:_distance
                    target:_target
                  duration:0.3];
}

- (void)setRightView {
    [self animateToAzimuth:-M_PI_2
                 elevation:0.0f
                  distance:_distance
                    target:_target
                  duration:0.3];
}

- (void)setBackView {
    [self animateToAzimuth:M_PI
                 elevation:0.0f
                  distance:_distance
                    target:_target
                  duration:0.3];
}

#pragma mark - Persistence

static NSString * const kCameraAzimuth    = @"XLHousePreviewCamera.azimuth";
static NSString * const kCameraElevation  = @"XLHousePreviewCamera.elevation";
static NSString * const kCameraDistance   = @"XLHousePreviewCamera.distance";
static NSString * const kCameraTargetX    = @"XLHousePreviewCamera.targetX";
static NSString * const kCameraTargetY    = @"XLHousePreviewCamera.targetY";
static NSString * const kCameraTargetZ    = @"XLHousePreviewCamera.targetZ";
static NSString * const kCameraSaved      = @"XLHousePreviewCamera.saved";

- (void)saveCameraState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setFloat:_azimuth forKey:kCameraAzimuth];
    [defaults setFloat:_elevation forKey:kCameraElevation];
    [defaults setFloat:_distance forKey:kCameraDistance];
    [defaults setFloat:_target.x forKey:kCameraTargetX];
    [defaults setFloat:_target.y forKey:kCameraTargetY];
    [defaults setFloat:_target.z forKey:kCameraTargetZ];
    [defaults setBool:YES forKey:kCameraSaved];
}

- (BOOL)restoreCameraState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:kCameraSaved]) {
        return NO;
    }

    _azimuth = [defaults floatForKey:kCameraAzimuth];
    _elevation = [defaults floatForKey:kCameraElevation];
    _distance = [defaults floatForKey:kCameraDistance];
    _target = (simd_float3){
        [defaults floatForKey:kCameraTargetX],
        [defaults floatForKey:kCameraTargetY],
        [defaults floatForKey:kCameraTargetZ]
    };

    _elevation = fmaxf(_minElevation, fminf(_maxElevation, _elevation));
    _distance = fmaxf(_minDistance, fminf(_maxDistance, _distance));

    return YES;
}

#pragma mark - Named Viewpoints

static NSString * const kViewpointsKey = @"XLHousePreviewCamera.viewpoints";
static NSString * const kDefaultViewpointKey = @"XLHousePreviewCamera.defaultViewpoint";

- (NSDictionary *)currentStateDictionary {
    return @{
        @"azimuth": @(_azimuth),
        @"elevation": @(_elevation),
        @"distance": @(_distance),
        @"targetX": @(_target.x),
        @"targetY": @(_target.y),
        @"targetZ": @(_target.z),
    };
}

- (void)applyCameraStateDictionary:(NSDictionary *)state animated:(BOOL)animated {
    float az = [state[@"azimuth"] floatValue];
    float el = [state[@"elevation"] floatValue];
    float dist = [state[@"distance"] floatValue];
    simd_float3 tgt = (simd_float3){
        [state[@"targetX"] floatValue],
        [state[@"targetY"] floatValue],
        [state[@"targetZ"] floatValue],
    };

    el = fmaxf(_minElevation, fminf(_maxElevation, el));
    dist = fmaxf(_minDistance, fminf(_maxDistance, dist));

    if (animated) {
        [self animateToAzimuth:az elevation:el distance:dist target:tgt duration:0.3];
    } else {
        _azimuth = az;
        _elevation = el;
        _distance = dist;
        _target = tgt;
    }
}

- (void)saveViewpointWithName:(NSString *)name {
    if (!name || name.length == 0) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *viewpoints = [([defaults dictionaryForKey:kViewpointsKey] ?: @{}) mutableCopy];
    viewpoints[name] = [self currentStateDictionary];
    [defaults setObject:viewpoints forKey:kViewpointsKey];
}

- (BOOL)loadViewpointWithName:(NSString *)name {
    if (!name || name.length == 0) return NO;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *viewpoints = [defaults dictionaryForKey:kViewpointsKey];
    NSDictionary *state = viewpoints[name];
    if (!state) return NO;

    [self applyCameraStateDictionary:state animated:YES];
    return YES;
}

- (BOOL)deleteViewpointWithName:(NSString *)name {
    if (!name || name.length == 0) return NO;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *viewpoints = [([defaults dictionaryForKey:kViewpointsKey] ?: @{}) mutableCopy];
    if (!viewpoints[name]) return NO;

    [viewpoints removeObjectForKey:name];
    [defaults setObject:viewpoints forKey:kViewpointsKey];
    return YES;
}

- (NSArray<NSString *> *)savedViewpointNames {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *viewpoints = [defaults dictionaryForKey:kViewpointsKey];
    if (!viewpoints || viewpoints.count == 0) return @[];
    return [[viewpoints allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (void)saveAsDefaultViewpoint {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[self currentStateDictionary] forKey:kDefaultViewpointKey];
}

- (BOOL)restoreDefaultViewpoint {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *state = [defaults dictionaryForKey:kDefaultViewpointKey];
    if (!state) return NO;

    [self applyCameraStateDictionary:state animated:YES];
    return YES;
}

#pragma mark - Matrix Utilities

- (simd_float4x4)lookAtEye:(simd_float3)eye
                    target:(simd_float3)target
                        up:(simd_float3)up {
    simd_float3 f = simd_normalize(target - eye);
    simd_float3 s = simd_normalize(simd_cross(f, up));
    simd_float3 u = simd_cross(s, f);

    simd_float4x4 m = {
        .columns[0] = {s.x, u.x, -f.x, 0.0f},
        .columns[1] = {s.y, u.y, -f.y, 0.0f},
        .columns[2] = {s.z, u.z, -f.z, 0.0f},
        .columns[3] = {-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1.0f}
    };
    return m;
}

- (simd_float4x4)perspectiveMatrixFov:(float)fov
                               aspect:(float)aspect
                                 near:(float)near
                                  far:(float)far {
    float ys = 1.0f / tanf(fov * 0.5f);
    float xs = ys / aspect;
    float zs = far / (near - far);

    simd_float4x4 m = {
        .columns[0] = {xs, 0, 0, 0},
        .columns[1] = {0, ys, 0, 0},
        .columns[2] = {0, 0, zs, -1},
        .columns[3] = {0, 0, near * zs, 0}
    };
    return m;
}

- (simd_float4x4)orthoMatrixLeft:(float)left right:(float)right
                          bottom:(float)bottom top:(float)top
                            near:(float)near far:(float)far {
    float rl = right - left;
    float tb = top - bottom;
    float fn = far - near;

    simd_float4x4 m = {
        .columns[0] = {2.0f / rl, 0, 0, 0},
        .columns[1] = {0, 2.0f / tb, 0, 0},
        .columns[2] = {0, 0, -1.0f / fn, 0},
        .columns[3] = {-(right + left) / rl, -(top + bottom) / tb, -near / fn, 1.0f}
    };
    return m;
}

@end
