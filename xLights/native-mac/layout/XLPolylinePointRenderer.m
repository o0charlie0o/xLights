/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLPolylinePointRenderer.h"
#import <simd/simd.h>
#import <math.h>

static const float kPointHandleSize = 8.0f;
static const float kCurveHandleSize = 6.0f;
static const NSInteger kBezierSubdivisions = 32;

#pragma mark - Vertex Structure

typedef struct {
    simd_float3 position;
    simd_float4 color;
} XLPolyVertex;

#pragma mark - Colors

static simd_float4 kColorGreen      = {0.0f, 0.85f, 0.0f, 0.7f};   // Start point
static simd_float4 kColorBlue       = {0.2f, 0.4f, 1.0f, 0.7f};    // Normal points
static simd_float4 kColorYellow     = {1.0f, 1.0f, 0.0f, 0.9f};    // Highlighted
static simd_float4 kColorOrange     = {1.0f, 0.6f, 0.0f, 0.7f};    // Selected
static simd_float4 kColorRed        = {1.0f, 0.15f, 0.15f, 0.7f};  // Curve control points
static simd_float4 kColorMagenta    = {1.0f, 0.0f, 1.0f, 0.8f};    // Selected segment
static simd_float4 kColorWhiteTrans = {1.0f, 1.0f, 1.0f, 0.3f};    // Segment lines
static simd_float4 kColorRedLine    = {1.0f, 0.3f, 0.3f, 0.6f};    // Curve control lines

#pragma mark - Private Interface

@interface XLPolylinePointRenderer () {
    XLPolylinePoint _points[XL_MAX_POLYLINE_POINTS];
    NSInteger _pointCount;

    // Drag state
    simd_float3 _dragStartWorld;
    simd_float3 _dragOriginalPos;
    NSInteger _dragIndex;
    XLPolylineHitType _dragHitType;
    BOOL _dragging;
}

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, assign) NSInteger vertexCapacity;

@end

@implementation XLPolylinePointRenderer

#pragma mark - Initialization

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
        _active = NO;
        _pointCount = 0;
        _selectedPoint = -1;
        _selectedSegment = -1;
        _highlightedPoint = -1;
        _handleSize = kPointHandleSize;
        _dragging = NO;
        _dragIndex = -1;
        _vertexCapacity = 4096;

        memset(_points, 0, sizeof(_points));

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
        "struct PolyVertex {\n"
        "    float3 position [[attribute(0)]];\n"
        "    float4 color    [[attribute(1)]];\n"
        "};\n"
        "\n"
        "struct PolyUniforms {\n"
        "    float4x4 viewProjection;\n"
        "    float pointSize;\n"
        "};\n"
        "\n"
        "struct PolyOut {\n"
        "    float4 position [[position]];\n"
        "    float4 color;\n"
        "    float pointSize [[point_size]];\n"
        "};\n"
        "\n"
        "vertex PolyOut polyVertexShader(\n"
        "    PolyVertex in [[stage_in]],\n"
        "    constant PolyUniforms &uniforms [[buffer(1)]]) {\n"
        "    PolyOut out;\n"
        "    out.position = uniforms.viewProjection * float4(in.position, 1.0);\n"
        "    out.color = in.color;\n"
        "    out.pointSize = uniforms.pointSize;\n"
        "    return out;\n"
        "}\n"
        "\n"
        "fragment float4 polyFragmentShader(PolyOut in [[stage_in]]) {\n"
        "    return in.color;\n"
        "}\n";

    id<MTLLibrary> library = [_device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"XLPolylinePointRenderer: Failed to compile shaders: %@", error);
        return;
    }

    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"polyVertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"polyFragmentShader"];

    MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
    vertexDesc.attributes[0].format = MTLVertexFormatFloat3;
    vertexDesc.attributes[0].offset = 0;
    vertexDesc.attributes[0].bufferIndex = 0;
    vertexDesc.attributes[1].format = MTLVertexFormatFloat4;
    vertexDesc.attributes[1].offset = sizeof(simd_float3);
    vertexDesc.attributes[1].bufferIndex = 0;
    vertexDesc.layouts[0].stride = sizeof(XLPolyVertex);
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

    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipeDesc error:&error];
    if (!_pipelineState) {
        NSLog(@"XLPolylinePointRenderer: Failed to create pipeline: %@", error);
    }
}

- (void)allocateVertexBuffer {
    _vertexBuffer = [_device newBufferWithLength:_vertexCapacity * sizeof(XLPolyVertex)
                                         options:MTLResourceStorageModeShared];
    [_vertexBuffer setLabel:@"PolylinePointVertices"];
}

- (void)ensureCapacity:(NSInteger)needed {
    if (needed > _vertexCapacity) {
        _vertexCapacity = needed * 2;
        [self allocateVertexBuffer];
    }
}

#pragma mark - Properties

- (BOOL)isDragging {
    return _dragging;
}

- (NSInteger)pointCount {
    return _pointCount;
}

#pragma mark - Point Data

- (void)setPoints:(const XLPolylinePoint *)points count:(NSInteger)count {
    if (count > XL_MAX_POLYLINE_POINTS) count = XL_MAX_POLYLINE_POINTS;
    _pointCount = count;
    memcpy(_points, points, count * sizeof(XLPolylinePoint));
    _active = (count >= 2);
}

- (simd_float3)positionForPoint:(NSInteger)index {
    if (index < 0 || index >= _pointCount) {
        return simd_make_float3(0, 0, 0);
    }
    return _points[index].position;
}

- (void)clearPoints {
    _pointCount = 0;
    _active = NO;
    _selectedPoint = -1;
    _selectedSegment = -1;
    _highlightedPoint = -1;
    _dragging = NO;
}

#pragma mark - Hit Testing

- (XLPolylineHitType)hitTestWithRayOrigin:(simd_float3)rayOrigin
                             rayDirection:(simd_float3)rayDirection
                                     zoom:(float)zoom
                                 hitIndex:(NSInteger *)hitIndex {
    if (!_active || _pointCount < 2) {
        *hitIndex = -1;
        return XLPolylineHitNone;
    }

    float handleRadius = kPointHandleSize * (zoom > 0 ? 1.0f / zoom : 1.0f);
    float curveHandleRadius = kCurveHandleSize * (zoom > 0 ? 1.0f / zoom : 1.0f);
    float closestDist = MAXFLOAT;
    XLPolylineHitType bestHit = XLPolylineHitNone;
    NSInteger bestIndex = -1;

    // Test curve control points first (if a segment is selected and has a curve)
    if (_selectedSegment >= 0 && _selectedSegment < _pointCount - 1 &&
        _points[_selectedSegment].hasCurve) {
        simd_float3 cpPositions[2] = {
            _points[_selectedSegment].cp0,
            _points[_selectedSegment].cp1
        };
        XLPolylineHitType cpTypes[2] = { XLPolylineHitCP0, XLPolylineHitCP1 };

        for (int i = 0; i < 2; i++) {
            simd_float3 oc = rayOrigin - cpPositions[i];
            float a = simd_dot(rayDirection, rayDirection);
            float b = 2.0f * simd_dot(oc, rayDirection);
            float c = simd_dot(oc, oc) - curveHandleRadius * curveHandleRadius;
            float discriminant = b * b - 4.0f * a * c;

            if (discriminant >= 0) {
                float t = (-b - sqrtf(discriminant)) / (2.0f * a);
                if (t > 0 && t < closestDist) {
                    closestDist = t;
                    bestHit = cpTypes[i];
                    bestIndex = _selectedSegment;
                }
            }
        }
    }

    // Test control points
    for (NSInteger i = 0; i < _pointCount; i++) {
        simd_float3 oc = rayOrigin - _points[i].position;
        float a = simd_dot(rayDirection, rayDirection);
        float b = 2.0f * simd_dot(oc, rayDirection);
        float c = simd_dot(oc, oc) - handleRadius * handleRadius;
        float discriminant = b * b - 4.0f * a * c;

        if (discriminant >= 0) {
            float t = (-b - sqrtf(discriminant)) / (2.0f * a);
            if (t > 0 && t < closestDist) {
                closestDist = t;
                bestHit = XLPolylineHitPoint;
                bestIndex = i;
            }
        }
    }

    // Test segments (line proximity)
    if (bestHit == XLPolylineHitNone) {
        float segmentThreshold = handleRadius * 2.0f;

        for (NSInteger i = 0; i < _pointCount - 1; i++) {
            simd_float3 p0 = _points[i].position;
            simd_float3 p1 = _points[i + 1].position;

            // Point-line-segment distance using ray
            // Project ray onto the segment's plane and check distance
            simd_float3 segDir = p1 - p0;
            float segLen = simd_length(segDir);
            if (segLen < 0.001f) continue;
            segDir = segDir / segLen;

            // Find closest approach between ray and segment
            simd_float3 w0 = rayOrigin - p0;
            float a = simd_dot(rayDirection, rayDirection);
            float b = simd_dot(rayDirection, segDir);
            float c = simd_dot(segDir, segDir);
            float d = simd_dot(rayDirection, w0);
            float e = simd_dot(segDir, w0);
            float denom = a * c - b * b;

            if (fabsf(denom) < 0.0001f) continue;

            float tRay = (b * e - c * d) / denom;
            float tSeg = (a * e - b * d) / denom;

            if (tRay < 0 || tSeg < 0 || tSeg > segLen) continue;

            simd_float3 closestOnRay = rayOrigin + rayDirection * tRay;
            simd_float3 closestOnSeg = p0 + segDir * tSeg;
            float dist = simd_length(closestOnRay - closestOnSeg);

            if (dist < segmentThreshold && tRay < closestDist) {
                closestDist = tRay;
                bestHit = XLPolylineHitSegment;
                bestIndex = i;
            }
        }
    }

    *hitIndex = bestIndex;
    return bestHit;
}

#pragma mark - Dragging

- (void)beginDragAtPoint:(simd_float3)worldPoint
              pointIndex:(NSInteger)pointIndex
                 hitType:(XLPolylineHitType)hitType {
    _dragStartWorld = worldPoint;
    _dragIndex = pointIndex;
    _dragHitType = hitType;
    _dragging = YES;

    if (hitType == XLPolylineHitPoint && pointIndex >= 0 && pointIndex < _pointCount) {
        _dragOriginalPos = _points[pointIndex].position;
    } else if (hitType == XLPolylineHitCP0 && pointIndex >= 0 && pointIndex < _pointCount) {
        _dragOriginalPos = _points[pointIndex].cp0;
    } else if (hitType == XLPolylineHitCP1 && pointIndex >= 0 && pointIndex < _pointCount) {
        _dragOriginalPos = _points[pointIndex].cp1;
    }
}

- (simd_float3)updateDragToPoint:(simd_float3)worldPoint {
    if (!_dragging || _dragIndex < 0 || _dragIndex >= _pointCount) {
        return simd_make_float3(0, 0, 0);
    }

    simd_float3 delta = worldPoint - _dragStartWorld;
    simd_float3 newPos = _dragOriginalPos + delta;

    // Update the local copy
    if (_dragHitType == XLPolylineHitPoint) {
        _points[_dragIndex].position = newPos;
    } else if (_dragHitType == XLPolylineHitCP0) {
        _points[_dragIndex].cp0 = newPos;
    } else if (_dragHitType == XLPolylineHitCP1) {
        _points[_dragIndex].cp1 = newPos;
    }

    return newPos;
}

- (void)endDrag {
    _dragging = NO;
    _dragIndex = -1;
}

#pragma mark - Rendering

- (void)renderWithEncoder:(id<MTLRenderCommandEncoder>)encoder
           viewProjection:(simd_float4x4)viewProjection
                     zoom:(float)zoom
                    scale:(int)scale {
    if (!_active || _pointCount < 2 || !_pipelineState) return;

    // Calculate needed vertices:
    // Lines between points: (_pointCount-1) * 2 (or more for curves)
    // Point spheres: ~24 tris * 3 verts per point = 72 per point
    // Curve control lines: 4 verts per curve segment
    // Curve control points: 72 per control point
    NSInteger maxVerts = _pointCount * 200 + _pointCount * kBezierSubdivisions * 2;
    [self ensureCapacity:maxVerts];

    XLPolyVertex *verts = (XLPolyVertex *)[_vertexBuffer contents];
    NSInteger lineStart = 0;
    NSInteger lineCount = 0;
    NSInteger triStart = 0;
    NSInteger triCount = 0;
    NSInteger pointStart = 0;
    NSInteger pointCount = 0;

    float hw = kPointHandleSize * (zoom > 0 ? 1.0f / zoom : 1.0f) * scale;
    float chw = kCurveHandleSize * (zoom > 0 ? 1.0f / zoom : 1.0f) * scale;

    // Phase 1: Build segment lines
    NSInteger vi = 0;
    for (NSInteger i = 0; i < _pointCount - 1; i++) {
        simd_float4 lineColor = (i == _selectedSegment) ? kColorMagenta : kColorWhiteTrans;

        if (_points[i].hasCurve) {
            // Draw Bezier curve with subdivisions
            simd_float3 p0 = _points[i].position;
            simd_float3 p1 = _points[i + 1].position;
            simd_float3 c0 = _points[i].cp0;
            simd_float3 c1 = _points[i].cp1;

            simd_float3 prev = p0;
            for (NSInteger s = 1; s <= kBezierSubdivisions; s++) {
                float t = (float)s / (float)kBezierSubdivisions;
                float u = 1.0f - t;
                // Cubic Bezier: B(t) = (1-t)^3*P0 + 3*(1-t)^2*t*C0 + 3*(1-t)*t^2*C1 + t^3*P1
                simd_float3 pt = p0 * (u * u * u) + c0 * (3.0f * u * u * t) +
                                 c1 * (3.0f * u * t * t) + p1 * (t * t * t);

                verts[vi++] = (XLPolyVertex){prev, lineColor};
                verts[vi++] = (XLPolyVertex){pt, lineColor};
                prev = pt;
            }

            // Draw control point lines if this segment is selected
            if (i == _selectedSegment) {
                verts[vi++] = (XLPolyVertex){p0, kColorRedLine};
                verts[vi++] = (XLPolyVertex){c0, kColorRedLine};
                verts[vi++] = (XLPolyVertex){p1, kColorRedLine};
                verts[vi++] = (XLPolyVertex){c1, kColorRedLine};
            }
        } else {
            // Straight line segment
            verts[vi++] = (XLPolyVertex){_points[i].position, lineColor};
            verts[vi++] = (XLPolyVertex){_points[i + 1].position, lineColor};
        }
    }
    lineCount = vi;

    // Phase 2: Build point handle spheres (as simple diamonds/crosses for efficiency)
    triStart = vi;
    for (NSInteger i = 0; i < _pointCount; i++) {
        simd_float4 color;
        if (i == _highlightedPoint) {
            color = kColorYellow;
        } else if (i == _selectedPoint) {
            color = kColorOrange;
        } else if (i == 0) {
            color = kColorGreen;
        } else {
            color = kColorBlue;
        }

        simd_float3 pos = _points[i].position;
        // Draw a small diamond (4 triangles) around the point
        simd_float3 top    = simd_make_float3(pos.x, pos.y + hw, pos.z);
        simd_float3 bottom = simd_make_float3(pos.x, pos.y - hw, pos.z);
        simd_float3 left   = simd_make_float3(pos.x - hw, pos.y, pos.z);
        simd_float3 right  = simd_make_float3(pos.x + hw, pos.y, pos.z);
        simd_float3 front  = simd_make_float3(pos.x, pos.y, pos.z + hw);
        simd_float3 back   = simd_make_float3(pos.x, pos.y, pos.z - hw);

        // Front-facing triangles (XY plane diamond)
        verts[vi++] = (XLPolyVertex){top, color};
        verts[vi++] = (XLPolyVertex){right, color};
        verts[vi++] = (XLPolyVertex){front, color};

        verts[vi++] = (XLPolyVertex){right, color};
        verts[vi++] = (XLPolyVertex){bottom, color};
        verts[vi++] = (XLPolyVertex){front, color};

        verts[vi++] = (XLPolyVertex){bottom, color};
        verts[vi++] = (XLPolyVertex){left, color};
        verts[vi++] = (XLPolyVertex){front, color};

        verts[vi++] = (XLPolyVertex){left, color};
        verts[vi++] = (XLPolyVertex){top, color};
        verts[vi++] = (XLPolyVertex){front, color};

        // Back-facing triangles
        verts[vi++] = (XLPolyVertex){top, color};
        verts[vi++] = (XLPolyVertex){left, color};
        verts[vi++] = (XLPolyVertex){back, color};

        verts[vi++] = (XLPolyVertex){left, color};
        verts[vi++] = (XLPolyVertex){bottom, color};
        verts[vi++] = (XLPolyVertex){back, color};

        verts[vi++] = (XLPolyVertex){bottom, color};
        verts[vi++] = (XLPolyVertex){right, color};
        verts[vi++] = (XLPolyVertex){back, color};

        verts[vi++] = (XLPolyVertex){right, color};
        verts[vi++] = (XLPolyVertex){top, color};
        verts[vi++] = (XLPolyVertex){back, color};
    }

    // Phase 3: Draw curve control point handles
    if (_selectedSegment >= 0 && _selectedSegment < _pointCount - 1 &&
        _points[_selectedSegment].hasCurve) {
        simd_float3 cpPositions[2] = {
            _points[_selectedSegment].cp0,
            _points[_selectedSegment].cp1
        };

        for (int c = 0; c < 2; c++) {
            simd_float3 pos = cpPositions[c];
            simd_float4 color = kColorRed;

            simd_float3 top    = simd_make_float3(pos.x, pos.y + chw, pos.z);
            simd_float3 bottom = simd_make_float3(pos.x, pos.y - chw, pos.z);
            simd_float3 left   = simd_make_float3(pos.x - chw, pos.y, pos.z);
            simd_float3 right  = simd_make_float3(pos.x + chw, pos.y, pos.z);
            simd_float3 front  = simd_make_float3(pos.x, pos.y, pos.z + chw);
            simd_float3 back   = simd_make_float3(pos.x, pos.y, pos.z - chw);

            verts[vi++] = (XLPolyVertex){top, color};
            verts[vi++] = (XLPolyVertex){right, color};
            verts[vi++] = (XLPolyVertex){front, color};

            verts[vi++] = (XLPolyVertex){right, color};
            verts[vi++] = (XLPolyVertex){bottom, color};
            verts[vi++] = (XLPolyVertex){front, color};

            verts[vi++] = (XLPolyVertex){bottom, color};
            verts[vi++] = (XLPolyVertex){left, color};
            verts[vi++] = (XLPolyVertex){front, color};

            verts[vi++] = (XLPolyVertex){left, color};
            verts[vi++] = (XLPolyVertex){top, color};
            verts[vi++] = (XLPolyVertex){front, color};

            verts[vi++] = (XLPolyVertex){top, color};
            verts[vi++] = (XLPolyVertex){left, color};
            verts[vi++] = (XLPolyVertex){back, color};

            verts[vi++] = (XLPolyVertex){left, color};
            verts[vi++] = (XLPolyVertex){bottom, color};
            verts[vi++] = (XLPolyVertex){back, color};

            verts[vi++] = (XLPolyVertex){bottom, color};
            verts[vi++] = (XLPolyVertex){right, color};
            verts[vi++] = (XLPolyVertex){back, color};

            verts[vi++] = (XLPolyVertex){right, color};
            verts[vi++] = (XLPolyVertex){top, color};
            verts[vi++] = (XLPolyVertex){back, color};
        }
    }

    triCount = vi - triStart;

    // Render
    [encoder pushDebugGroup:@"PolylinePoints"];
    [encoder setRenderPipelineState:_pipelineState];
    [encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];

    struct {
        simd_float4x4 viewProjection;
        float pointSize;
    } uniforms;
    uniforms.viewProjection = viewProjection;
    uniforms.pointSize = hw;

    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];

    // Draw segment lines
    if (lineCount > 0) {
        [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:lineStart vertexCount:lineCount];
    }

    // Draw point handle triangles and curve control point triangles
    if (triCount > 0) {
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:triStart vertexCount:triCount];
    }

    [encoder popDebugGroup];
}

#pragma mark - Cursor

- (NSString *)cursorForHitType:(XLPolylineHitType)hitType {
    switch (hitType) {
        case XLPolylineHitPoint:
        case XLPolylineHitCP0:
        case XLPolylineHitCP1:
            return @"hand";
        case XLPolylineHitSegment:
            return @"crosshair";
        default:
            return @"default";
    }
}

@end
