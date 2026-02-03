/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLManipulationHandlesRenderer.h"
#import <simd/simd.h>
#import <math.h>

static const float kBoundingRectOffset = 8.0f;
static const float kDefaultHandleSize = 8.0f;
static const float kAxisToolLength = 100.0f;
static const float kAxisToolHeadLength = 20.0f;
static const float kAxisToolRadius = 2.0f;

#pragma mark - Vertex Structures

typedef struct {
    simd_float3 position;
    simd_float4 color;
} XLHandleVertex;

#pragma mark - Private Interface

@interface XLManipulationHandlesRenderer () {
    // C arrays for heap corruption immunity
    XLHandlePosition _handlePositions[XL_MAX_HANDLES];
    simd_float3 _handleAABBMin[XL_MAX_HANDLES];
    simd_float3 _handleAABBMax[XL_MAX_HANDLES];
    XLSnapGuide _snapGuides[XL_MAX_SNAP_GUIDES];
    NSInteger _snapGuideCount;

    // Drag state
    simd_float3 _dragStartPoint;
    simd_float3 _savedPosition;
    simd_float3 _savedScale;
    simd_float3 _savedRotation;
    simd_float3 _savedSize;
    BOOL _isDragging;
}

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLRenderPipelineState> handlePipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, assign) NSInteger vertexCapacity;

@property (nonatomic, assign) XLModelTransform currentTransform;
@property (nonatomic, assign) BOOL hasSelection;
@property (nonatomic, assign) NSInteger handleCountInternal;

@end

@implementation XLManipulationHandlesRenderer

#pragma mark - Initialization

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
        _toolMode = XLToolModeTranslate;
        _activeAxis = XLActiveAxisNone;
        _activeHandle = -1;
        _highlightedHandle = -1;
        _is3D = YES;
        _gridSnapSize = 0;
        _angleSnapDegrees = 15.0f;
        _edgeSnapEnabled = YES;
        _hasSelection = NO;
        _handleCountInternal = 0;
        _snapGuideCount = 0;
        _isDragging = NO;
        _vertexCapacity = 1024;

        memset(_handlePositions, 0, sizeof(_handlePositions));
        memset(_handleAABBMin, 0, sizeof(_handleAABBMin));
        memset(_handleAABBMax, 0, sizeof(_handleAABBMax));
        memset(_snapGuides, 0, sizeof(_snapGuides));
        memset(&_currentTransform, 0, sizeof(_currentTransform));

        [self buildPipeline];
        [self allocateVertexBuffer];
    }
    return self;
}

- (void)buildPipeline {
    NSError *error = nil;

    NSString *shaderSource = @
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "\n"
        "struct HandleVertex {\n"
        "    float3 position [[attribute(0)]];\n"
        "    float4 color    [[attribute(1)]];\n"
        "};\n"
        "\n"
        "struct HandleUniforms {\n"
        "    float4x4 viewProjection;\n"
        "};\n"
        "\n"
        "struct HandleOut {\n"
        "    float4 position [[position]];\n"
        "    float4 color;\n"
        "};\n"
        "\n"
        "vertex HandleOut handleVertexShader(\n"
        "    HandleVertex in [[stage_in]],\n"
        "    constant HandleUniforms &uniforms [[buffer(1)]]) {\n"
        "    HandleOut out;\n"
        "    out.position = uniforms.viewProjection * float4(in.position, 1.0);\n"
        "    out.color = in.color;\n"
        "    return out;\n"
        "}\n"
        "\n"
        "fragment float4 handleFragmentShader(HandleOut in [[stage_in]]) {\n"
        "    return in.color;\n"
        "}\n";

    id<MTLLibrary> library = [_device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"XLManipulationHandlesRenderer: Failed to compile shaders: %@", error);
        return;
    }

    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"handleVertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"handleFragmentShader"];

    MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
    vertexDesc.attributes[0].format = MTLVertexFormatFloat3;
    vertexDesc.attributes[0].offset = 0;
    vertexDesc.attributes[0].bufferIndex = 0;
    vertexDesc.attributes[1].format = MTLVertexFormatFloat4;
    vertexDesc.attributes[1].offset = sizeof(simd_float3);
    vertexDesc.attributes[1].bufferIndex = 0;
    vertexDesc.layouts[0].stride = sizeof(XLHandleVertex);
    vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    MTLRenderPipelineDescriptor *pipeDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipeDesc.vertexFunction = vertexFunction;
    pipeDesc.fragmentFunction = fragmentFunction;
    pipeDesc.vertexDescriptor = vertexDesc;
    pipeDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipeDesc.colorAttachments[0].blendingEnabled = YES;
    pipeDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipeDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipeDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipeDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipeDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    if (@available(macOS 13.0, *)) {
        pipeDesc.rasterSampleCount = 4;
    } else {
        pipeDesc.sampleCount = 4;
    }

    _handlePipelineState = [_device newRenderPipelineStateWithDescriptor:pipeDesc error:&error];
    if (!_handlePipelineState) {
        NSLog(@"XLManipulationHandlesRenderer: Failed to create pipeline: %@", error);
    }
}

- (void)allocateVertexBuffer {
    _vertexBuffer = [_device newBufferWithLength:_vertexCapacity * sizeof(XLHandleVertex)
                                         options:MTLResourceStorageModeShared];
    [_vertexBuffer setLabel:@"HandleVertices"];
}

#pragma mark - Model State

- (void)setModelTransform:(XLModelTransform)transform {
    _currentTransform = transform;
    _hasSelection = YES;
    [self updateHandlePositions];
}

- (XLModelTransform)modelTransform {
    return _currentTransform;
}

- (void)clearSelection {
    _hasSelection = NO;
    _activeHandle = -1;
    _highlightedHandle = -1;
    _handleCountInternal = 0;
    _isDragging = NO;
}

#pragma mark - Handle Positions

- (void)updateHandlePositions {
    if (!_hasSelection) return;

    XLModelTransform t = _currentTransform;
    float halfW = t.renderWidth / 2.0f;
    float halfH = t.renderHeight / 2.0f;
    float halfD = t.renderDepth / 2.0f;

    // Calculate rotation matrix from Euler angles
    float rx = t.rotation.x * M_PI / 180.0f;
    float ry = t.rotation.y * M_PI / 180.0f;
    float rz = t.rotation.z * M_PI / 180.0f;

    float cosX = cosf(rx), sinX = sinf(rx);
    float cosY = cosf(ry), sinY = sinf(ry);
    float cosZ = cosf(rz), sinZ = sinf(rz);

    simd_float4x4 rotX = (simd_float4x4){{
        {1, 0, 0, 0},
        {0, cosX, sinX, 0},
        {0, -sinX, cosX, 0},
        {0, 0, 0, 1}
    }};
    simd_float4x4 rotY = (simd_float4x4){{
        {cosY, 0, -sinY, 0},
        {0, 1, 0, 0},
        {sinY, 0, cosY, 0},
        {0, 0, 0, 1}
    }};
    simd_float4x4 rotZ = (simd_float4x4){{
        {cosZ, sinZ, 0, 0},
        {-sinZ, cosZ, 0, 0},
        {0, 0, 1, 0},
        {0, 0, 0, 1}
    }};

    simd_float4x4 rotationMatrix = simd_mul(simd_mul(rotZ, rotY), rotX);

    // Helper to transform and store a handle position
    void (^transformHandle)(XLHandleType, float, float, float) = ^(XLHandleType handle, float lx, float ly, float lz) {
        // Apply scale
        float sx = lx * t.scale.x;
        float sy = ly * t.scale.y;
        float sz = lz * t.scale.z;

        // Apply rotation
        simd_float4 local = simd_make_float4(sx, sy, sz, 1.0f);
        simd_float4 rotated = simd_mul(rotationMatrix, local);

        // Apply translation
        self->_handlePositions[handle].x = rotated.x + t.position.x;
        self->_handlePositions[handle].y = rotated.y + t.position.y;
        self->_handlePositions[handle].z = rotated.z + t.position.z;
    };

    if (_is3D) {
        // 3D mode: 8 corner handles + center + rotation
        float offsetX = kBoundingRectOffset / t.scale.x;
        float offsetY = kBoundingRectOffset / t.scale.y;

        // Front face corners (Z+)
        transformHandle(XLHandleTypeLeftTop, -halfW - offsetX, halfH + offsetY, halfD);
        transformHandle(XLHandleTypeRightTop, halfW + offsetX, halfH + offsetY, halfD);
        transformHandle(XLHandleTypeRightBottom, halfW + offsetX, -halfH - offsetY, halfD);
        transformHandle(XLHandleTypeLeftBottom, -halfW - offsetX, -halfH - offsetY, halfD);

        // Back face corners (Z-)
        transformHandle(XLHandleTypeLeftTopZ, -halfW - offsetX, halfH + offsetY, -halfD);
        transformHandle(XLHandleTypeRightTopZ, halfW + offsetX, halfH + offsetY, -halfD);
        transformHandle(XLHandleTypeRightBottomZ, halfW + offsetX, -halfH - offsetY, -halfD);
        transformHandle(XLHandleTypeLeftBottomZ, -halfW - offsetX, -halfH - offsetY, -halfD);

        // Center handle at model position
        _handlePositions[XLHandleTypeCenter].x = t.position.x;
        _handlePositions[XLHandleTypeCenter].y = t.position.y;
        _handlePositions[XLHandleTypeCenter].z = t.position.z;

        _handleCountInternal = 10;
    } else {
        // 2D mode: 4 corner handles + rotation + center
        float offsetX = kBoundingRectOffset;
        float offsetY = kBoundingRectOffset;

        transformHandle(XLHandleTypeLeftTop, -halfW, halfH, 0);
        _handlePositions[XLHandleTypeLeftTop].x -= offsetX;
        _handlePositions[XLHandleTypeLeftTop].y += offsetY;

        transformHandle(XLHandleTypeRightTop, halfW, halfH, 0);
        _handlePositions[XLHandleTypeRightTop].x += offsetX;
        _handlePositions[XLHandleTypeRightTop].y += offsetY;

        transformHandle(XLHandleTypeRightBottom, halfW, -halfH, 0);
        _handlePositions[XLHandleTypeRightBottom].x += offsetX;
        _handlePositions[XLHandleTypeRightBottom].y -= offsetY;

        transformHandle(XLHandleTypeLeftBottom, -halfW, -halfH, 0);
        _handlePositions[XLHandleTypeLeftBottom].x -= offsetX;
        _handlePositions[XLHandleTypeLeftBottom].y -= offsetY;

        // Rotation handle above center
        float rotHandleOffset = halfH + 50.0f / t.scale.y;
        transformHandle(XLHandleTypeRotate, 0, rotHandleOffset, 0);

        // Center handle
        _handlePositions[XLHandleTypeCenter].x = t.position.x;
        _handlePositions[XLHandleTypeCenter].y = t.position.y;
        _handlePositions[XLHandleTypeCenter].z = t.position.z;

        _handleCountInternal = 6;
    }

    // Update AABBs for hit testing
    [self updateHandleAABBs];
}

- (void)updateHandleAABBs {
    float hw = kDefaultHandleSize;

    for (NSInteger i = 0; i < _handleCountInternal; i++) {
        _handleAABBMin[i] = simd_make_float3(
            _handlePositions[i].x - hw,
            _handlePositions[i].y - hw,
            _handlePositions[i].z - hw
        );
        _handleAABBMax[i] = simd_make_float3(
            _handlePositions[i].x + hw,
            _handlePositions[i].y + hw,
            _handlePositions[i].z + hw
        );
    }
}

- (const XLHandlePosition *)handlePositions {
    return _handlePositions;
}

- (NSInteger)handleCount {
    return _handleCountInternal;
}

- (simd_float3)positionForHandle:(XLHandleType)handleType {
    if (handleType < 0 || handleType >= XL_MAX_HANDLES) {
        return simd_make_float3(0, 0, 0);
    }
    return simd_make_float3(
        _handlePositions[handleType].x,
        _handlePositions[handleType].y,
        _handlePositions[handleType].z
    );
}

#pragma mark - Hit Testing

- (XLHandleType)hitTestWithRayOrigin:(simd_float3)rayOrigin
                        rayDirection:(simd_float3)rayDirection
                                zoom:(float)zoom
                               scale:(int)scale {
    if (!_hasSelection || _currentTransform.isLocked) {
        return XLHandleTypeNone;
    }

    float closestDist = MAXFLOAT;
    XLHandleType closestHandle = XLHandleTypeNone;

    float handleSize = kDefaultHandleSize * (zoom > 0 ? 1.0f / zoom : 1.0f) * scale;

    for (NSInteger i = 0; i < _handleCountInternal; i++) {
        simd_float3 handlePos = simd_make_float3(
            _handlePositions[i].x,
            _handlePositions[i].y,
            _handlePositions[i].z
        );

        // Ray-sphere intersection for handle hit testing
        simd_float3 oc = rayOrigin - handlePos;
        float a = simd_dot(rayDirection, rayDirection);
        float b = 2.0f * simd_dot(oc, rayDirection);
        float c = simd_dot(oc, oc) - handleSize * handleSize;
        float discriminant = b * b - 4.0f * a * c;

        if (discriminant >= 0) {
            float t = (-b - sqrt(discriminant)) / (2.0f * a);
            if (t > 0 && t < closestDist) {
                closestDist = t;
                closestHandle = (XLHandleType)i;
            }
        }
    }

    return closestHandle;
}

- (XLHandleType)hitTestAtScreenPoint:(CGPoint)point
                          viewWidth:(CGFloat)viewWidth
                         viewHeight:(CGFloat)viewHeight
                     viewProjection:(simd_float4x4)viewProjection
                               zoom:(float)zoom
                              scale:(int)scale {
    if (!_hasSelection || _currentTransform.isLocked) {
        return XLHandleTypeNone;
    }

    float handleSize = kDefaultHandleSize * scale;

    for (NSInteger i = 0; i < _handleCountInternal; i++) {
        simd_float3 handlePos = simd_make_float3(
            _handlePositions[i].x,
            _handlePositions[i].y,
            _handlePositions[i].z
        );

        // Project handle position to screen
        simd_float4 worldPos = simd_make_float4(handlePos.x, handlePos.y, handlePos.z, 1.0f);
        simd_float4 clipPos = simd_mul(viewProjection, worldPos);

        if (clipPos.w != 0) {
            simd_float3 ndc = simd_make_float3(clipPos.x / clipPos.w, clipPos.y / clipPos.w, clipPos.z / clipPos.w);

            float screenX = (ndc.x * 0.5f + 0.5f) * viewWidth;
            float screenY = (1.0f - (ndc.y * 0.5f + 0.5f)) * viewHeight;

            float dx = point.x - screenX;
            float dy = point.y - screenY;
            float dist = sqrt(dx * dx + dy * dy);

            if (dist <= handleSize) {
                return (XLHandleType)i;
            }
        }
    }

    return XLHandleTypeNone;
}

#pragma mark - Manipulation

- (void)beginDragAtPoint:(simd_float3)worldPoint
               forHandle:(XLHandleType)handle {
    _isDragging = YES;
    _dragStartPoint = worldPoint;
    _savedPosition = _currentTransform.position;
    _savedScale = _currentTransform.scale;
    _savedRotation = _currentTransform.rotation;
    _savedSize = simd_make_float3(_currentTransform.renderWidth,
                                  _currentTransform.renderHeight,
                                  _currentTransform.renderDepth);
    _activeHandle = handle;
}

- (simd_float3)updateDragToPoint:(simd_float3)worldPoint
                       shiftHeld:(BOOL)shiftHeld
                      optionHeld:(BOOL)optionHeld
                         cmdHeld:(BOOL)cmdHeld {
    if (!_isDragging) {
        return simd_make_float3(0, 0, 0);
    }

    simd_float3 delta = worldPoint - _dragStartPoint;

    if (_activeHandle == XLHandleTypeCenter) {
        switch (_toolMode) {
            case XLToolModeTranslate:
                [self applyTranslateDelta:delta];
                break;
            case XLToolModeScale:
                [self applyScaleDelta:delta shiftHeld:shiftHeld optionHeld:optionHeld];
                break;
            case XLToolModeRotate:
                [self applyRotateDelta:delta cmdHeld:cmdHeld];
                break;
            default:
                break;
        }
    } else if (_activeHandle == XLHandleTypeRotate) {
        [self applyRotateHandleDelta:delta shiftHeld:shiftHeld];
    } else {
        // Corner/edge handles for scaling
        [self applyCornerScaleDelta:delta handle:_activeHandle shiftHeld:shiftHeld optionHeld:optionHeld];
    }

    [self updateHandlePositions];
    return delta;
}

- (void)applyTranslateDelta:(simd_float3)delta {
    switch (_activeAxis) {
        case XLActiveAxisX:
            _currentTransform.position.x = _savedPosition.x + delta.x;
            break;
        case XLActiveAxisY:
            _currentTransform.position.y = _savedPosition.y + delta.y;
            break;
        case XLActiveAxisZ:
            _currentTransform.position.z = _savedPosition.z + delta.z;
            break;
        default:
            _currentTransform.position = _savedPosition + delta;
            break;
    }

    // Apply grid snapping
    if (_gridSnapSize > 0) {
        _currentTransform.position = [self snapPosition:_currentTransform.position];
    }
}

- (void)applyScaleDelta:(simd_float3)delta shiftHeld:(BOOL)shiftHeld optionHeld:(BOOL)optionHeld {
    simd_float3 scaledSize = _savedSize * _savedScale;

    float changeX = (scaledSize.x + delta.x) / scaledSize.x;
    float changeY = (scaledSize.y + delta.y) / scaledSize.y;
    float changeZ = (scaledSize.z + delta.z) / scaledSize.z;

    if (shiftHeld) {
        // Proportional scaling
        float avgChange = (changeX + changeY + changeZ) / 3.0f;
        changeX = changeY = changeZ = avgChange;
    }

    switch (_activeAxis) {
        case XLActiveAxisX:
            _currentTransform.scale.x = _savedScale.x * changeX;
            if (shiftHeld && _currentTransform.supportsZScaling) {
                _currentTransform.scale.z = _currentTransform.scale.x;
            }
            break;
        case XLActiveAxisY:
            _currentTransform.scale.y = _savedScale.y * changeY;
            if (optionHeld) {
                // Keep bottom anchored
                float heightDelta = (_currentTransform.scale.y - _savedScale.y) * _currentTransform.renderHeight / 2.0f;
                _currentTransform.position.y = _savedPosition.y + heightDelta;
            }
            break;
        case XLActiveAxisZ:
            if (_currentTransform.supportsZScaling) {
                _currentTransform.scale.z = _savedScale.z * changeZ;
            }
            break;
        default:
            _currentTransform.scale.x = _savedScale.x * changeX;
            _currentTransform.scale.y = _savedScale.y * changeY;
            if (_currentTransform.supportsZScaling) {
                _currentTransform.scale.z = _savedScale.z * changeZ;
            }
            break;
    }
}

- (void)applyRotateDelta:(simd_float3)delta cmdHeld:(BOOL)cmdHeld {
    simd_float3 startVector = _dragStartPoint - _savedPosition;
    simd_float3 endVector = startVector + delta;

    float angle = 0;

    switch (_activeAxis) {
        case XLActiveAxisX: {
            float startAngle = atan2(startVector.y, startVector.z) * 180.0f / M_PI;
            float endAngle = atan2(endVector.y, endVector.z) * 180.0f / M_PI;
            angle = endAngle - startAngle;
            if (!cmdHeld) angle = [self snapAngle:angle];
            _currentTransform.rotation.x = _savedRotation.x + angle;
            break;
        }
        case XLActiveAxisY: {
            float startAngle = atan2(startVector.x, startVector.z) * 180.0f / M_PI;
            float endAngle = atan2(endVector.x, endVector.z) * 180.0f / M_PI;
            angle = endAngle - startAngle;
            if (!cmdHeld) angle = [self snapAngle:angle];
            _currentTransform.rotation.y = _savedRotation.y - angle;
            break;
        }
        case XLActiveAxisZ:
        default: {
            float startAngle = atan2(startVector.y, startVector.x) * 180.0f / M_PI;
            float endAngle = atan2(endVector.y, endVector.x) * 180.0f / M_PI;
            angle = endAngle - startAngle;
            if (!cmdHeld) angle = [self snapAngle:angle];
            _currentTransform.rotation.z = _savedRotation.z - angle;
            break;
        }
    }
}

- (void)applyRotateHandleDelta:(simd_float3)delta shiftHeld:(BOOL)shiftHeld {
    simd_float3 center = _savedPosition;
    simd_float3 startVector = _dragStartPoint - center;
    simd_float3 endVector = startVector + delta;

    float startAngle = atan2(startVector.x, startVector.y) * 180.0f / M_PI;
    float endAngle = atan2(endVector.x, endVector.y) * 180.0f / M_PI;
    float angle = endAngle - startAngle;

    if (shiftHeld) {
        angle = [self snapAngle:angle];
    }

    _currentTransform.rotation.z = _savedRotation.z - angle;
}

- (void)applyCornerScaleDelta:(simd_float3)delta handle:(NSInteger)handle shiftHeld:(BOOL)shiftHeld optionHeld:(BOOL)optionHeld {
    // Determine which axes to scale based on handle
    BOOL scaleX = (handle == XLHandleTypeLeftTop || handle == XLHandleTypeLeftBottom ||
                   handle == XLHandleTypeRightTop || handle == XLHandleTypeRightBottom);
    BOOL scaleY = scaleX;

    if (scaleX) {
        BOOL isLeft = (handle == XLHandleTypeLeftTop || handle == XLHandleTypeLeftBottom);
        BOOL isTop = (handle == XLHandleTypeLeftTop || handle == XLHandleTypeRightTop);

        float dx = isLeft ? -delta.x : delta.x;
        float dy = isTop ? delta.y : -delta.y;

        float newScaleX = _savedScale.x + dx / _currentTransform.renderWidth;
        float newScaleY = _savedScale.y + dy / _currentTransform.renderHeight;

        if (shiftHeld) {
            // Proportional
            float avg = (newScaleX / _savedScale.x + newScaleY / _savedScale.y) / 2.0f;
            newScaleX = _savedScale.x * avg;
            newScaleY = _savedScale.y * avg;
        }

        _currentTransform.scale.x = fmax(0.01f, newScaleX);
        _currentTransform.scale.y = fmax(0.01f, newScaleY);

        if (!optionHeld) {
            // Anchor opposite corner
            float widthDiff = (_currentTransform.scale.x - _savedScale.x) * _currentTransform.renderWidth / 2.0f;
            float heightDiff = (_currentTransform.scale.y - _savedScale.y) * _currentTransform.renderHeight / 2.0f;

            _currentTransform.position.x = _savedPosition.x + (isLeft ? widthDiff : -widthDiff);
            _currentTransform.position.y = _savedPosition.y + (isTop ? -heightDiff : heightDiff);
        }
    }
}

- (void)endDrag {
    _isDragging = NO;
}

- (simd_float3)snapPosition:(simd_float3)position {
    if (_gridSnapSize <= 0) return position;

    return simd_make_float3(
        roundf(position.x / _gridSnapSize) * _gridSnapSize,
        roundf(position.y / _gridSnapSize) * _gridSnapSize,
        roundf(position.z / _gridSnapSize) * _gridSnapSize
    );
}

- (float)snapAngle:(float)angleDegrees {
    if (_angleSnapDegrees <= 0) return angleDegrees;
    return roundf(angleDegrees / _angleSnapDegrees) * _angleSnapDegrees;
}

#pragma mark - Snap Guides

- (void)setSnapGuides:(const XLSnapGuide *)guides count:(NSInteger)count {
    _snapGuideCount = MIN(count, XL_MAX_SNAP_GUIDES);
    memcpy(_snapGuides, guides, _snapGuideCount * sizeof(XLSnapGuide));
}

- (void)clearSnapGuides {
    _snapGuideCount = 0;
    memset(_snapGuides, 0, sizeof(_snapGuides));
}

#pragma mark - Rendering

- (void)renderWithEncoder:(id<MTLRenderCommandEncoder>)encoder
           viewProjection:(simd_float4x4)viewProjection
                     zoom:(float)zoom
                    scale:(int)scale {
    if (!_hasSelection || !_handlePipelineState) return;

    [encoder pushDebugGroup:@"ManipulationHandles"];
    [encoder setRenderPipelineState:_handlePipelineState];

    // Build vertex data
    NSMutableData *vertexData = [[NSMutableData alloc] initWithCapacity:_vertexCapacity * sizeof(XLHandleVertex)];

    // Selection box color
    simd_float4 boxColor;
    if (_currentTransform.isLocked) {
        boxColor = simd_make_float4(1.0f, 0.3f, 0.3f, 0.7f); // Red translucent
    } else {
        boxColor = simd_make_float4(1.0f, 1.0f, 1.0f, 0.8f); // White
    }

    // Handle color
    simd_float4 handleColor;
    if (_currentTransform.isLocked) {
        handleColor = simd_make_float4(1.0f, 0.3f, 0.3f, 0.7f);
    } else {
        handleColor = simd_make_float4(0.3f, 0.5f, 1.0f, 0.7f); // Blue translucent
    }

    // Draw bounding box lines
    if (_is3D) {
        [self addBoundingBox3DToData:vertexData color:boxColor];
    } else {
        [self addBoundingBox2DToData:vertexData color:boxColor];
    }

    // Draw handles as small cubes/squares
    float handleSize = kDefaultHandleSize * (zoom > 0 ? 1.0f / zoom : 1.0f) * scale;

    for (NSInteger i = 0; i < _handleCountInternal; i++) {
        simd_float4 color = handleColor;

        // Highlight active or hovered handle
        if (i == _activeHandle) {
            color = simd_make_float4(1.0f, 0.6f, 0.0f, 0.9f); // Orange
        } else if (i == _highlightedHandle) {
            color = simd_make_float4(0.5f, 0.7f, 1.0f, 0.9f); // Light blue
        }

        simd_float3 pos = simd_make_float3(_handlePositions[i].x, _handlePositions[i].y, _handlePositions[i].z);
        [self addHandleAtPosition:pos size:handleSize color:color toData:vertexData];
    }

    // Draw axis tool if handle is active
    if (_activeHandle == XLHandleTypeCenter && !_currentTransform.isLocked) {
        simd_float3 pos = simd_make_float3(_handlePositions[XLHandleTypeCenter].x,
                                           _handlePositions[XLHandleTypeCenter].y,
                                           _handlePositions[XLHandleTypeCenter].z);
        [self addAxisToolAtPosition:pos zoom:zoom scale:scale toData:vertexData];
    }

    // Draw active axis line
    if (_activeAxis != XLActiveAxisNone && _activeHandle == XLHandleTypeCenter) {
        simd_float3 pos = simd_make_float3(_handlePositions[XLHandleTypeCenter].x,
                                           _handlePositions[XLHandleTypeCenter].y,
                                           _handlePositions[XLHandleTypeCenter].z);
        [self addAxisLineAtPosition:pos axis:_activeAxis toData:vertexData];
    }

    // Draw snap guides
    [self addSnapGuidesToData:vertexData];

    // Upload and draw
    NSUInteger vertexCount = vertexData.length / sizeof(XLHandleVertex);
    if (vertexCount > 0) {
        memcpy(_vertexBuffer.contents, vertexData.bytes, vertexData.length);

        [encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
        [encoder setVertexBytes:&viewProjection length:sizeof(simd_float4x4) atIndex:1];

        // Draw lines (bounding box, axis lines, snap guides)
        // Draw triangles (handles)
        // For simplicity, we draw all as lines here - handles would need triangles in production
        [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:vertexCount];
    }

    [encoder popDebugGroup];
}

- (void)addBoundingBox3DToData:(NSMutableData *)data color:(simd_float4)color {
    // Front face
    [self addLineFrom:_handlePositions[XLHandleTypeLeftTop]
                   to:_handlePositions[XLHandleTypeRightTop]
                color:color toData:data];
    [self addLineFrom:_handlePositions[XLHandleTypeRightTop]
                   to:_handlePositions[XLHandleTypeRightBottom]
                color:color toData:data];
    [self addLineFrom:_handlePositions[XLHandleTypeRightBottom]
                   to:_handlePositions[XLHandleTypeLeftBottom]
                color:color toData:data];
    [self addLineFrom:_handlePositions[XLHandleTypeLeftBottom]
                   to:_handlePositions[XLHandleTypeLeftTop]
                color:color toData:data];

    // Back face
    [self addLineFrom:_handlePositions[XLHandleTypeLeftTopZ]
                   to:_handlePositions[XLHandleTypeRightTopZ]
                color:color toData:data];
    [self addLineFrom:_handlePositions[XLHandleTypeRightTopZ]
                   to:_handlePositions[XLHandleTypeRightBottomZ]
                color:color toData:data];
    [self addLineFrom:_handlePositions[XLHandleTypeRightBottomZ]
                   to:_handlePositions[XLHandleTypeLeftBottomZ]
                color:color toData:data];
    [self addLineFrom:_handlePositions[XLHandleTypeLeftBottomZ]
                   to:_handlePositions[XLHandleTypeLeftTopZ]
                color:color toData:data];

    // Connecting edges
    [self addLineFrom:_handlePositions[XLHandleTypeLeftTop]
                   to:_handlePositions[XLHandleTypeLeftTopZ]
                color:color toData:data];
    [self addLineFrom:_handlePositions[XLHandleTypeRightTop]
                   to:_handlePositions[XLHandleTypeRightTopZ]
                color:color toData:data];
    [self addLineFrom:_handlePositions[XLHandleTypeRightBottom]
                   to:_handlePositions[XLHandleTypeRightBottomZ]
                color:color toData:data];
    [self addLineFrom:_handlePositions[XLHandleTypeLeftBottom]
                   to:_handlePositions[XLHandleTypeLeftBottomZ]
                color:color toData:data];
}

- (void)addBoundingBox2DToData:(NSMutableData *)data color:(simd_float4)color {
    [self addLineFrom:_handlePositions[XLHandleTypeLeftTop]
                   to:_handlePositions[XLHandleTypeRightTop]
                color:color toData:data];
    [self addLineFrom:_handlePositions[XLHandleTypeRightTop]
                   to:_handlePositions[XLHandleTypeRightBottom]
                color:color toData:data];
    [self addLineFrom:_handlePositions[XLHandleTypeRightBottom]
                   to:_handlePositions[XLHandleTypeLeftBottom]
                color:color toData:data];
    [self addLineFrom:_handlePositions[XLHandleTypeLeftBottom]
                   to:_handlePositions[XLHandleTypeLeftTop]
                color:color toData:data];

    // Line to rotation handle
    XLHandlePosition center;
    center.x = _currentTransform.position.x;
    center.y = _currentTransform.position.y;
    center.z = _currentTransform.position.z;

    [self addLineFrom:center to:_handlePositions[XLHandleTypeRotate] color:color toData:data];
}

- (void)addLineFrom:(XLHandlePosition)from to:(XLHandlePosition)to color:(simd_float4)color toData:(NSMutableData *)data {
    XLHandleVertex v0 = {
        .position = simd_make_float3(from.x, from.y, from.z),
        .color = color
    };
    XLHandleVertex v1 = {
        .position = simd_make_float3(to.x, to.y, to.z),
        .color = color
    };
    [data appendBytes:&v0 length:sizeof(XLHandleVertex)];
    [data appendBytes:&v1 length:sizeof(XLHandleVertex)];
}

- (void)addHandleAtPosition:(simd_float3)pos size:(float)size color:(simd_float4)color toData:(NSMutableData *)data {
    // Draw handle as a small wireframe cube
    float hs = size / 2.0f;

    XLHandlePosition corners[8] = {
        {pos.x - hs, pos.y - hs, pos.z - hs},
        {pos.x + hs, pos.y - hs, pos.z - hs},
        {pos.x + hs, pos.y + hs, pos.z - hs},
        {pos.x - hs, pos.y + hs, pos.z - hs},
        {pos.x - hs, pos.y - hs, pos.z + hs},
        {pos.x + hs, pos.y - hs, pos.z + hs},
        {pos.x + hs, pos.y + hs, pos.z + hs},
        {pos.x - hs, pos.y + hs, pos.z + hs},
    };

    // Front face
    [self addLineFrom:corners[0] to:corners[1] color:color toData:data];
    [self addLineFrom:corners[1] to:corners[2] color:color toData:data];
    [self addLineFrom:corners[2] to:corners[3] color:color toData:data];
    [self addLineFrom:corners[3] to:corners[0] color:color toData:data];

    // Back face
    [self addLineFrom:corners[4] to:corners[5] color:color toData:data];
    [self addLineFrom:corners[5] to:corners[6] color:color toData:data];
    [self addLineFrom:corners[6] to:corners[7] color:color toData:data];
    [self addLineFrom:corners[7] to:corners[4] color:color toData:data];

    // Connecting edges
    [self addLineFrom:corners[0] to:corners[4] color:color toData:data];
    [self addLineFrom:corners[1] to:corners[5] color:color toData:data];
    [self addLineFrom:corners[2] to:corners[6] color:color toData:data];
    [self addLineFrom:corners[3] to:corners[7] color:color toData:data];
}

- (void)addAxisToolAtPosition:(simd_float3)pos zoom:(float)zoom scale:(int)scale toData:(NSMutableData *)data {
    float length = kAxisToolLength * (zoom > 0 ? 1.0f / zoom : 1.0f) * scale;

    // X axis (red)
    simd_float4 xColor = simd_make_float4(1.0f, 0.2f, 0.2f, 0.9f);
    XLHandlePosition xEnd = {pos.x + length, pos.y, pos.z};
    XLHandlePosition xStart = {pos.x, pos.y, pos.z};
    [self addLineFrom:xStart to:xEnd color:xColor toData:data];

    // Y axis (green)
    simd_float4 yColor = simd_make_float4(0.2f, 1.0f, 0.2f, 0.9f);
    XLHandlePosition yEnd = {pos.x, pos.y + length, pos.z};
    XLHandlePosition yStart = {pos.x, pos.y, pos.z};
    [self addLineFrom:yStart to:yEnd color:yColor toData:data];

    // Z axis (blue)
    simd_float4 zColor = simd_make_float4(0.2f, 0.2f, 1.0f, 0.9f);
    XLHandlePosition zEnd = {pos.x, pos.y, pos.z + length};
    XLHandlePosition zStart = {pos.x, pos.y, pos.z};
    [self addLineFrom:zStart to:zEnd color:zColor toData:data];
}

- (void)addAxisLineAtPosition:(simd_float3)pos axis:(XLActiveAxis)axis toData:(NSMutableData *)data {
    simd_float4 color;
    XLHandlePosition start, end;

    float extent = 10000.0f;

    switch (axis) {
        case XLActiveAxisX:
            color = simd_make_float4(1.0f, 0.2f, 0.2f, 0.5f);
            start = (XLHandlePosition){pos.x - extent, pos.y, pos.z};
            end = (XLHandlePosition){pos.x + extent, pos.y, pos.z};
            break;
        case XLActiveAxisY:
            color = simd_make_float4(0.2f, 1.0f, 0.2f, 0.5f);
            start = (XLHandlePosition){pos.x, pos.y - extent, pos.z};
            end = (XLHandlePosition){pos.x, pos.y + extent, pos.z};
            break;
        case XLActiveAxisZ:
            color = simd_make_float4(0.2f, 0.2f, 1.0f, 0.5f);
            start = (XLHandlePosition){pos.x, pos.y, pos.z - extent};
            end = (XLHandlePosition){pos.x, pos.y, pos.z + extent};
            break;
        default:
            return;
    }

    [self addLineFrom:start to:end color:color toData:data];
}

- (void)addSnapGuidesToData:(NSMutableData *)data {
    for (NSInteger i = 0; i < _snapGuideCount; i++) {
        if (!_snapGuides[i].active) continue;

        simd_float4 color = simd_make_float4(_snapGuides[i].r, _snapGuides[i].g, _snapGuides[i].b, _snapGuides[i].a);
        XLHandlePosition start = {_snapGuides[i].start.x, _snapGuides[i].start.y, _snapGuides[i].start.z};
        XLHandlePosition end = {_snapGuides[i].end.x, _snapGuides[i].end.y, _snapGuides[i].end.z};
        [self addLineFrom:start to:end color:color toData:data];
    }
}

#pragma mark - Cursor

- (NSString *)cursorForHandle:(XLHandleType)handle rotation:(float)rotationZ {
    if (_currentTransform.isLocked) {
        return @"default";
    }

    switch (handle) {
        case XLHandleTypeNone:
            return @"default";
        case XLHandleTypeCenter:
            return @"move";
        case XLHandleTypeRotate:
            return @"rotate";
        case XLHandleTypeLeftTop:
        case XLHandleTypeRightBottom:
        case XLHandleTypeLeftTopZ:
        case XLHandleTypeRightBottomZ:
            // Adjust cursor based on rotation
            if (fabs(fmod(rotationZ, 180.0f)) < 45.0f || fabs(fmod(rotationZ, 180.0f)) > 135.0f) {
                return @"resize-nwse";
            } else {
                return @"resize-nesw";
            }
        case XLHandleTypeRightTop:
        case XLHandleTypeLeftBottom:
        case XLHandleTypeRightTopZ:
        case XLHandleTypeLeftBottomZ:
            if (fabs(fmod(rotationZ, 180.0f)) < 45.0f || fabs(fmod(rotationZ, 180.0f)) > 135.0f) {
                return @"resize-nesw";
            } else {
                return @"resize-nwse";
            }
        default:
            return @"default";
    }
}

@end
