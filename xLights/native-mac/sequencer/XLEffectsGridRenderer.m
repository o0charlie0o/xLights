/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLEffectsGridRenderer.h"
#import <simd/simd.h>

// Must match the struct in XLEffectsGridShaders.metal
typedef struct {
    simd_float2 viewportSize;
    simd_float2 scrollOffset;
    float zoomLevel;
    float rowHeight;
    float padding0;
    float padding1;
} EffectsGridUniforms;

typedef struct {
    simd_float2 position;
    simd_float4 color;
} SimpleVertex;

typedef struct {
    simd_float2 position;
    simd_float4 color;
    simd_float2 rectMin;
    simd_float2 rectMax;
    float cornerRadius;
} RoundedRectVertex;

static const NSInteger kMaxGridLineVertices = 8192;
static const NSInteger kMaxEffectVertices = 32768;
static const CGFloat kEffectBlockCornerRadius = 3.0;
static const CGFloat kEffectBlockInset = 1.0;

/// Per-frame scalar rendering parameters, passed by value to sub-draw methods.
/// All data stays on the stack (no heap/ivar involvement) to avoid stale or
/// corrupted pointer reads.
typedef struct {
    CGSize viewSize;
    CGPoint scrollOffset;
    CGFloat zoomLevel;
    CGFloat rowHeight;
    NSInteger totalRows;
    CGFloat sequenceLengthMS;
    NSInteger selectedEffectID;
    CGFloat playbackPositionMS;
} XLGridFrameParams;

@interface XLEffectsGridRenderer ()

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> linePipeline;
@property (nonatomic, strong) id<MTLRenderPipelineState> effectBlockPipeline;
@property (nonatomic, strong) id<MTLRenderPipelineState> outlinePipeline;

@end

@implementation XLEffectsGridRenderer

#pragma mark - Initialization

- (instancetype)initWithLayer:(CAMetalLayer *)metalLayer {
    self = [super init];
    if (self) {
        _device = MTLCreateSystemDefaultDevice();
        if (!_device) {
            NSLog(@"XLEffectsGridRenderer: Metal not available");
            return nil;
        }

        metalLayer.device = _device;
        metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        metalLayer.framebufferOnly = YES;

        _commandQueue = [_device newCommandQueue];

        if (![self buildPipelines]) {
            NSLog(@"XLEffectsGridRenderer: Failed to build render pipelines");
            return nil;
        }
    }
    return self;
}

- (BOOL)buildPipelines {
    NSError *error = nil;

    // Compile shaders from inline source to avoid dependency on default.metallib
    // which may not contain our functions if other Metal shaders exist in the project
    NSString *shaderSource = @
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "\n"
        "struct EffectsGridUniforms {\n"
        "    float2 viewportSize;\n"
        "    float2 scrollOffset;\n"
        "    float zoomLevel;\n"
        "    float rowHeight;\n"
        "    float padding0;\n"
        "    float padding1;\n"
        "};\n"
        "\n"
        "struct VertexIn {\n"
        "    float2 position [[attribute(0)]];\n"
        "    float4 color    [[attribute(1)]];\n"
        "};\n"
        "\n"
        "struct VertexOut {\n"
        "    float4 position [[position]];\n"
        "    float4 color;\n"
        "};\n"
        "\n"
        "struct RoundedRectVertexIn {\n"
        "    float2 position  [[attribute(0)]];\n"
        "    float4 color     [[attribute(1)]];\n"
        "    float2 rectMin   [[attribute(2)]];\n"
        "    float2 rectMax   [[attribute(3)]];\n"
        "    float  cornerRadius [[attribute(4)]];\n"
        "};\n"
        "\n"
        "struct RoundedRectVertexOut {\n"
        "    float4 position [[position]];\n"
        "    float4 color;\n"
        "    float2 fragCoord;\n"
        "    float2 rectMin;\n"
        "    float2 rectMax;\n"
        "    float  cornerRadius;\n"
        "};\n"
        "\n"
        "vertex VertexOut effectsGridVertexShader(\n"
        "    VertexIn in [[stage_in]],\n"
        "    constant EffectsGridUniforms &uniforms [[buffer(1)]])\n"
        "{\n"
        "    VertexOut out;\n"
        "    float2 pos = in.position;\n"
        "    float2 ndc = (pos / uniforms.viewportSize) * 2.0 - 1.0;\n"
        "    ndc.y = -ndc.y;\n"
        "    out.position = float4(ndc, 0.0, 1.0);\n"
        "    out.color = in.color;\n"
        "    return out;\n"
        "}\n"
        "\n"
        "fragment float4 effectsGridFragmentShader(VertexOut in [[stage_in]])\n"
        "{\n"
        "    return in.color;\n"
        "}\n"
        "\n"
        "vertex RoundedRectVertexOut effectBlockVertexShader(\n"
        "    RoundedRectVertexIn in [[stage_in]],\n"
        "    constant EffectsGridUniforms &uniforms [[buffer(1)]])\n"
        "{\n"
        "    RoundedRectVertexOut out;\n"
        "    float2 pos = in.position;\n"
        "    float2 ndc = (pos / uniforms.viewportSize) * 2.0 - 1.0;\n"
        "    ndc.y = -ndc.y;\n"
        "    out.position = float4(ndc, 0.0, 1.0);\n"
        "    out.color = in.color;\n"
        "    out.fragCoord = in.position;\n"
        "    out.rectMin = in.rectMin;\n"
        "    out.rectMax = in.rectMax;\n"
        "    out.cornerRadius = in.cornerRadius;\n"
        "    return out;\n"
        "}\n"
        "\n"
        "fragment float4 effectBlockFragmentShader(RoundedRectVertexOut in [[stage_in]])\n"
        "{\n"
        "    float2 p = in.fragCoord;\n"
        "    float2 rMin = in.rectMin;\n"
        "    float2 rMax = in.rectMax;\n"
        "    float r = in.cornerRadius;\n"
        "    float2 halfSize = (rMax - rMin) * 0.5;\n"
        "    float2 center = (rMin + rMax) * 0.5;\n"
        "    float2 q = abs(p - center) - halfSize + r;\n"
        "    float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;\n"
        "    if (dist > 0.5) { discard_fragment(); }\n"
        "    float4 color = in.color;\n"
        "    float edgeFactor = smoothstep(0.0, 2.0, -dist);\n"
        "    color.rgb *= mix(0.85, 1.0, edgeFactor);\n"
        "    float alpha = 1.0 - smoothstep(-0.5, 0.5, dist);\n"
        "    color.a *= alpha;\n"
        "    return color;\n"
        "}\n"
        "\n"
        "fragment float4 effectBlockOutlineFragmentShader(RoundedRectVertexOut in [[stage_in]])\n"
        "{\n"
        "    float2 p = in.fragCoord;\n"
        "    float2 rMin = in.rectMin;\n"
        "    float2 rMax = in.rectMax;\n"
        "    float r = in.cornerRadius;\n"
        "    float2 halfSize = (rMax - rMin) * 0.5;\n"
        "    float2 center = (rMin + rMax) * 0.5;\n"
        "    float2 q = abs(p - center) - halfSize + r;\n"
        "    float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;\n"
        "    float outerEdge = smoothstep(0.5, -0.5, dist);\n"
        "    float innerEdge = smoothstep(-1.5, -2.5, dist);\n"
        "    float outline = outerEdge - innerEdge;\n"
        "    if (outline < 0.01) { discard_fragment(); }\n"
        "    float4 color = in.color;\n"
        "    color.a *= outline;\n"
        "    return color;\n"
        "}\n";

    id<MTLLibrary> library = [_device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"XLEffectsGridRenderer: Could not compile shader library: %@", error);
        return NO;
    }

    // Simple line pipeline (grid lines, playback indicator)
    {
        MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
        vertexDesc.attributes[0].format = MTLVertexFormatFloat2;
        vertexDesc.attributes[0].offset = 0;
        vertexDesc.attributes[0].bufferIndex = 0;
        vertexDesc.attributes[1].format = MTLVertexFormatFloat4;
        vertexDesc.attributes[1].offset = sizeof(simd_float2);
        vertexDesc.attributes[1].bufferIndex = 0;
        vertexDesc.layouts[0].stride = sizeof(SimpleVertex);

        MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
        desc.vertexFunction = [library newFunctionWithName:@"effectsGridVertexShader"];
        desc.fragmentFunction = [library newFunctionWithName:@"effectsGridFragmentShader"];
        desc.vertexDescriptor = vertexDesc;
        desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        desc.colorAttachments[0].blendingEnabled = YES;
        desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

        _linePipeline = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
        if (!_linePipeline) {
            NSLog(@"XLEffectsGridRenderer: Line pipeline error: %@", error);
            return NO;
        }
    }

    // Rounded rectangle pipeline (effect blocks)
    {
        MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
        vertexDesc.attributes[0].format = MTLVertexFormatFloat2;
        vertexDesc.attributes[0].offset = offsetof(RoundedRectVertex, position);
        vertexDesc.attributes[0].bufferIndex = 0;
        vertexDesc.attributes[1].format = MTLVertexFormatFloat4;
        vertexDesc.attributes[1].offset = offsetof(RoundedRectVertex, color);
        vertexDesc.attributes[1].bufferIndex = 0;
        vertexDesc.attributes[2].format = MTLVertexFormatFloat2;
        vertexDesc.attributes[2].offset = offsetof(RoundedRectVertex, rectMin);
        vertexDesc.attributes[2].bufferIndex = 0;
        vertexDesc.attributes[3].format = MTLVertexFormatFloat2;
        vertexDesc.attributes[3].offset = offsetof(RoundedRectVertex, rectMax);
        vertexDesc.attributes[3].bufferIndex = 0;
        vertexDesc.attributes[4].format = MTLVertexFormatFloat;
        vertexDesc.attributes[4].offset = offsetof(RoundedRectVertex, cornerRadius);
        vertexDesc.attributes[4].bufferIndex = 0;
        vertexDesc.layouts[0].stride = sizeof(RoundedRectVertex);

        MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
        desc.vertexFunction = [library newFunctionWithName:@"effectBlockVertexShader"];
        desc.fragmentFunction = [library newFunctionWithName:@"effectBlockFragmentShader"];
        desc.vertexDescriptor = vertexDesc;
        desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        desc.colorAttachments[0].blendingEnabled = YES;
        desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

        _effectBlockPipeline = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
        if (!_effectBlockPipeline) {
            NSLog(@"XLEffectsGridRenderer: Effect block pipeline error: %@", error);
            return NO;
        }

        // Outline pipeline (same vertex shader, different fragment)
        desc.fragmentFunction = [library newFunctionWithName:@"effectBlockOutlineFragmentShader"];
        _outlinePipeline = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
        if (!_outlinePipeline) {
            NSLog(@"XLEffectsGridRenderer: Outline pipeline error: %@", error);
            return NO;
        }
    }

    return YES;
}

#pragma mark - Drawing

- (void)drawInLayer:(CAMetalLayer *)layer
           viewSize:(CGSize)viewSize
       scrollOffset:(CGPoint)scrollOffset
          zoomLevel:(CGFloat)zoomLevel
          rowHeight:(CGFloat)rowHeight
          totalRows:(NSInteger)totalRows
   sequenceLengthMS:(CGFloat)sequenceLengthMS
            effects:(const XLEffectRenderInfo *)effects
        effectCount:(NSUInteger)effectCount
   selectedEffectID:(NSInteger)selectedEffectID
 playbackPositionMS:(CGFloat)playbackPositionMS
   timingMarkValues:(const CGFloat *)timingMarkValues
    timingMarkCount:(NSUInteger)timingMarkCount
{
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (!drawable) return;

    // All per-frame state lives on the stack — no ivars, no heap pointers
    // that could become stale due to concurrent mutation.
    XLGridFrameParams fp = {
        .viewSize = viewSize,
        .scrollOffset = scrollOffset,
        .zoomLevel = zoomLevel,
        .rowHeight = rowHeight,
        .totalRows = totalRows,
        .sequenceLengthMS = sequenceLengthMS,
        .selectedEffectID = selectedEffectID,
        .playbackPositionMS = playbackPositionMS,
    };

    MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.colorAttachments[0].texture = drawable.texture;
    passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.118, 0.118, 0.118, 1.0);

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    if (!commandBuffer) return;

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];
    if (!encoder) return;

    EffectsGridUniforms uniforms;
    uniforms.viewportSize = simd_make_float2(viewSize.width, viewSize.height);
    uniforms.scrollOffset = simd_make_float2(scrollOffset.x, scrollOffset.y);
    uniforms.zoomLevel = (float)zoomLevel;
    uniforms.rowHeight = (float)rowHeight;
    uniforms.padding0 = 0;
    uniforms.padding1 = 0;

    [self drawGridLinesWithEncoder:encoder uniforms:uniforms params:fp
                  timingMarkValues:timingMarkValues timingMarkCount:timingMarkCount];
    [self drawEffectBlocksWithEncoder:encoder uniforms:uniforms params:fp
                              effects:effects effectCount:effectCount];
    [self drawPlaybackIndicatorWithEncoder:encoder uniforms:uniforms params:fp];

    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

#pragma mark - Grid Lines

- (void)drawGridLinesWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                        uniforms:(EffectsGridUniforms)uniforms
                          params:(XLGridFrameParams)fp
                timingMarkValues:(const CGFloat *)timingMarkValues
                 timingMarkCount:(NSUInteger)timingMarkCount
{
    CGSize viewSize = fp.viewSize;
    CGPoint scrollOffset = fp.scrollOffset;
    CGFloat zoomLevel = fp.zoomLevel;
    CGFloat rowHeight = fp.rowHeight;
    NSInteger totalRows = fp.totalRows;
    CGFloat sequenceLengthMS = fp.sequenceLengthMS;

    NSMutableData *vertexData = [NSMutableData dataWithCapacity:kMaxGridLineVertices * sizeof(SimpleVertex)];

    // Horizontal row separator lines
    simd_float4 rowLineColor = simd_make_float4(0.25, 0.25, 0.25, 1.0);
    CGFloat firstVisibleRow = scrollOffset.y / rowHeight;
    CGFloat lastVisibleRow = (scrollOffset.y + viewSize.height) / rowHeight;
    NSInteger startRow = MAX(0, (NSInteger)floor(firstVisibleRow));
    NSInteger endRow = MIN(totalRows, (NSInteger)ceil(lastVisibleRow) + 1);

    for (NSInteger row = startRow; row <= endRow; row++) {
        CGFloat y = row * rowHeight - scrollOffset.y;
        if (y < -1 || y > viewSize.height + 1) continue;

        SimpleVertex v0 = { simd_make_float2(0, y), rowLineColor };
        SimpleVertex v1 = { simd_make_float2(viewSize.width, y), rowLineColor };
        [vertexData appendBytes:&v0 length:sizeof(SimpleVertex)];
        [vertexData appendBytes:&v1 length:sizeof(SimpleVertex)];
    }

    // Vertical time division lines
    CGFloat msPerPixel = 1.0 / zoomLevel;
    CGFloat visibleMS = viewSize.width * msPerPixel;

    CGFloat gridIntervals[] = { 50, 100, 250, 500, 1000, 2000, 5000, 10000, 30000, 60000 };
    NSInteger numIntervals = sizeof(gridIntervals) / sizeof(gridIntervals[0]);
    CGFloat gridIntervalMS = gridIntervals[numIntervals - 1];
    CGFloat targetPixelsPerMark = 80.0;

    for (NSInteger i = 0; i < numIntervals; i++) {
        CGFloat pixelsPerMark = gridIntervals[i] * zoomLevel;
        if (pixelsPerMark >= targetPixelsPerMark) {
            gridIntervalMS = gridIntervals[i];
            break;
        }
    }

    CGFloat startTimeMS = scrollOffset.x * msPerPixel;
    CGFloat endTimeMS = startTimeMS + visibleMS;
    CGFloat firstMark = floor(startTimeMS / gridIntervalMS) * gridIntervalMS;

    simd_float4 majorLineColor = simd_make_float4(0.3, 0.3, 0.3, 1.0);
    simd_float4 minorLineColor = simd_make_float4(0.2, 0.2, 0.2, 0.5);

    for (CGFloat t = firstMark; t <= endTimeMS && t <= sequenceLengthMS; t += gridIntervalMS) {
        CGFloat x = t * zoomLevel - scrollOffset.x;
        if (x < -1 || x > viewSize.width + 1) continue;

        BOOL isMajor = fmod(t, gridIntervalMS * 4) < 0.1;
        simd_float4 lineColor = isMajor ? majorLineColor : minorLineColor;

        SimpleVertex v0 = { simd_make_float2(x, 0), lineColor };
        SimpleVertex v1 = { simd_make_float2(x, viewSize.height), lineColor };
        [vertexData appendBytes:&v0 length:sizeof(SimpleVertex)];
        [vertexData appendBytes:&v1 length:sizeof(SimpleVertex)];
    }

    // Timing mark lines (from active timing track)
    // Uses a plain C array — no ObjC message sends, no ARC, no isa dereferences.
    if (timingMarkValues && timingMarkCount > 0) {
        simd_float4 timingColor = simd_make_float4(0.4, 0.6, 0.4, 0.6);
        for (NSUInteger mi = 0; mi < timingMarkCount; mi++) {
            CGFloat t = timingMarkValues[mi];
            CGFloat x = t * zoomLevel - scrollOffset.x;
            if (x < -1 || x > viewSize.width + 1) continue;

            SimpleVertex v0 = { simd_make_float2(x, 0), timingColor };
            SimpleVertex v1 = { simd_make_float2(x, viewSize.height), timingColor };
            [vertexData appendBytes:&v0 length:sizeof(SimpleVertex)];
            [vertexData appendBytes:&v1 length:sizeof(SimpleVertex)];
        }
    }

    if (vertexData.length == 0) return;

    id<MTLBuffer> buffer = [_device newBufferWithBytes:vertexData.bytes
                                               length:vertexData.length
                                              options:MTLResourceStorageModeShared];
    [encoder setRenderPipelineState:_linePipeline];
    [encoder setVertexBuffer:buffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    NSInteger vertexCount = vertexData.length / sizeof(SimpleVertex);
    [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:vertexCount];
}

#pragma mark - Effect Blocks

- (void)drawEffectBlocksWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                           uniforms:(EffectsGridUniforms)uniforms
                             params:(XLGridFrameParams)fp
                            effects:(const XLEffectRenderInfo *)effects
                        effectCount:(NSUInteger)effectCount
{
    CGSize viewSize = fp.viewSize;
    CGPoint scrollOffset = fp.scrollOffset;
    CGFloat zoomLevel = fp.zoomLevel;
    CGFloat rowHeight = fp.rowHeight;

    if (!effects || effectCount == 0) return;

    NSMutableData *blockVertexData = [NSMutableData data];
    NSMutableData *outlineVertexData = [NSMutableData data];

    CGFloat msPerPixel = 1.0 / zoomLevel;
    CGFloat visibleStartMS = scrollOffset.x * msPerPixel;
    CGFloat visibleEndMS = visibleStartMS + viewSize.width * msPerPixel;
    CGFloat visibleStartRow = scrollOffset.y / rowHeight;
    CGFloat visibleEndRow = (scrollOffset.y + viewSize.height) / rowHeight;

    for (NSUInteger ei = 0; ei < effectCount; ei++) {
        XLEffectRenderInfo info = effects[ei];

        // Frustum culling: skip effects outside visible region
        if (info.endTimeMS < visibleStartMS || info.startTimeMS > visibleEndMS) continue;
        if (info.row < (NSInteger)floor(visibleStartRow) - 1 ||
            info.row > (NSInteger)ceil(visibleEndRow) + 1) continue;

        CGFloat x1 = info.startTimeMS * zoomLevel - scrollOffset.x;
        CGFloat x2 = info.endTimeMS * zoomLevel - scrollOffset.x;
        CGFloat y1 = info.row * rowHeight - scrollOffset.y + kEffectBlockInset;
        CGFloat y2 = (info.row + 1) * rowHeight - scrollOffset.y - kEffectBlockInset;

        // Skip if too narrow to draw
        if (x2 - x1 < 2.0) continue;

        simd_float4 color;
        if (info.colorARGB != 0) {
            float a = ((info.colorARGB >> 24) & 0xFF) / 255.0f;
            float r = ((info.colorARGB >> 16) & 0xFF) / 255.0f;
            float g = ((info.colorARGB >>  8) & 0xFF) / 255.0f;
            float b = ((info.colorARGB      ) & 0xFF) / 255.0f;
            color = simd_make_float4(r, g, b, a);
        } else {
            color = [self simdColorForEffectIndex:info.effectIndex];
        }

        if (info.renderDisabled) {
            color = simd_make_float4(color.x * 0.4, color.y * 0.4, color.z * 0.4, 0.5);
        } else if (info.locked) {
            color = simd_make_float4(color.x * 0.7, color.y * 0.7, color.z * 0.7, 0.9);
        }

        simd_float2 rectMin = simd_make_float2(x1, y1);
        simd_float2 rectMax = simd_make_float2(x2, y2);
        float cornerRadius = (float)kEffectBlockCornerRadius;

        // Two triangles forming the bounding quad for the rounded rect
        RoundedRectVertex vertices[6];
        for (int i = 0; i < 6; i++) {
            vertices[i].color = color;
            vertices[i].rectMin = rectMin;
            vertices[i].rectMax = rectMax;
            vertices[i].cornerRadius = cornerRadius;
        }
        vertices[0].position = simd_make_float2(x1, y1);
        vertices[1].position = simd_make_float2(x2, y1);
        vertices[2].position = simd_make_float2(x1, y2);
        vertices[3].position = simd_make_float2(x2, y1);
        vertices[4].position = simd_make_float2(x2, y2);
        vertices[5].position = simd_make_float2(x1, y2);

        [blockVertexData appendBytes:vertices length:sizeof(vertices)];

        // Selection outline
        if (info.selected) {
            simd_float4 selColor = simd_make_float4(0.3, 0.6, 1.0, 1.0);
            RoundedRectVertex outlineVerts[6];
            for (int i = 0; i < 6; i++) {
                outlineVerts[i].color = selColor;
                outlineVerts[i].rectMin = rectMin;
                outlineVerts[i].rectMax = rectMax;
                outlineVerts[i].cornerRadius = cornerRadius;
            }
            outlineVerts[0].position = simd_make_float2(x1 - 1, y1 - 1);
            outlineVerts[1].position = simd_make_float2(x2 + 1, y1 - 1);
            outlineVerts[2].position = simd_make_float2(x1 - 1, y2 + 1);
            outlineVerts[3].position = simd_make_float2(x2 + 1, y1 - 1);
            outlineVerts[4].position = simd_make_float2(x2 + 1, y2 + 1);
            outlineVerts[5].position = simd_make_float2(x1 - 1, y2 + 1);

            // Adjust the outline's rect bounds too
            for (int i = 0; i < 6; i++) {
                outlineVerts[i].rectMin = simd_make_float2(x1 - 1, y1 - 1);
                outlineVerts[i].rectMax = simd_make_float2(x2 + 1, y2 + 1);
            }

            [outlineVertexData appendBytes:outlineVerts length:sizeof(outlineVerts)];
        }
    }

    // Draw filled effect blocks
    if (blockVertexData.length > 0) {
        id<MTLBuffer> buffer = [_device newBufferWithBytes:blockVertexData.bytes
                                                   length:blockVertexData.length
                                                  options:MTLResourceStorageModeShared];
        [encoder setRenderPipelineState:_effectBlockPipeline];
        [encoder setVertexBuffer:buffer offset:0 atIndex:0];
        [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        NSInteger vertexCount = blockVertexData.length / sizeof(RoundedRectVertex);
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertexCount];
    }

    // Draw selection outlines on top
    if (outlineVertexData.length > 0) {
        id<MTLBuffer> buffer = [_device newBufferWithBytes:outlineVertexData.bytes
                                                   length:outlineVertexData.length
                                                  options:MTLResourceStorageModeShared];
        [encoder setRenderPipelineState:_outlinePipeline];
        [encoder setVertexBuffer:buffer offset:0 atIndex:0];
        [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        NSInteger vertexCount = outlineVertexData.length / sizeof(RoundedRectVertex);
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertexCount];
    }
}

#pragma mark - Playback Indicator

- (void)drawPlaybackIndicatorWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                                uniforms:(EffectsGridUniforms)uniforms
                                  params:(XLGridFrameParams)fp
{
    CGSize viewSize = fp.viewSize;
    CGPoint scrollOffset = fp.scrollOffset;
    CGFloat zoomLevel = fp.zoomLevel;
    CGFloat playbackPositionMS = fp.playbackPositionMS;

    if (playbackPositionMS < 0) return;

    CGFloat x = playbackPositionMS * zoomLevel - scrollOffset.x;
    if (x < -2 || x > viewSize.width + 2) return;

    // Red playback line (2px wide)
    simd_float4 playColor = simd_make_float4(1.0, 0.15, 0.15, 0.9);
    SimpleVertex vertices[6];
    vertices[0] = (SimpleVertex){ simd_make_float2(x - 1, 0), playColor };
    vertices[1] = (SimpleVertex){ simd_make_float2(x + 1, 0), playColor };
    vertices[2] = (SimpleVertex){ simd_make_float2(x - 1, viewSize.height), playColor };
    vertices[3] = (SimpleVertex){ simd_make_float2(x + 1, 0), playColor };
    vertices[4] = (SimpleVertex){ simd_make_float2(x + 1, viewSize.height), playColor };
    vertices[5] = (SimpleVertex){ simd_make_float2(x - 1, viewSize.height), playColor };

    id<MTLBuffer> buffer = [_device newBufferWithBytes:vertices
                                               length:sizeof(vertices)
                                              options:MTLResourceStorageModeShared];
    [encoder setRenderPipelineState:_linePipeline];
    [encoder setVertexBuffer:buffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
}

#pragma mark - Color Palette

// Static C array of effect colors - immune to ObjC heap corruption.
// No NSArray, no isa pointer, no ARC - just plain data in the DATA segment.
typedef struct {
    float r, g, b, a;
} XLEffectColorEntry;

static const XLEffectColorEntry kEffectColorPalette[] = {
    {0.30f, 0.55f, 0.85f, 0.85f}, // 0  Bars (blue)
    {0.85f, 0.50f, 0.20f, 0.85f}, // 1  Butterfly (orange)
    {0.90f, 0.35f, 0.25f, 0.85f}, // 2  Candle (red-orange)
    {0.40f, 0.70f, 0.40f, 0.85f}, // 3  Circles (green)
    {0.55f, 0.35f, 0.75f, 0.85f}, // 4  ColorWash (purple)
    {0.75f, 0.45f, 0.55f, 0.85f}, // 5  Curtain (mauve)
    {0.35f, 0.65f, 0.65f, 0.85f}, // 6  DMX (teal)
    {0.80f, 0.60f, 0.30f, 0.85f}, // 7  Faces (gold)
    {0.45f, 0.55f, 0.30f, 0.85f}, // 8  Fan (olive)
    {0.70f, 0.55f, 0.65f, 0.85f}, // 9  Fill (pink)
    {0.85f, 0.30f, 0.20f, 0.85f}, // 10 Fire (red)
    {0.90f, 0.45f, 0.30f, 0.85f}, // 11 Fireworks (orange-red)
    {0.35f, 0.55f, 0.45f, 0.85f}, // 12 Galaxy (dark green)
    {0.55f, 0.75f, 0.35f, 0.85f}, // 13 Garlands (lime)
    {0.50f, 0.40f, 0.60f, 0.85f}, // 14 Glediator (dark purple)
    {0.40f, 0.65f, 0.80f, 0.85f}, // 15 Kaleidoscope (sky blue)
    {0.50f, 0.65f, 0.35f, 0.85f}, // 16 Life (green)
    {0.70f, 0.70f, 0.35f, 0.85f}, // 17 Lightning (yellow)
    {0.45f, 0.45f, 0.65f, 0.85f}, // 18 Lines (slate)
    {0.55f, 0.55f, 0.55f, 0.85f}, // 19 Liquid (gray)
    {0.65f, 0.35f, 0.55f, 0.85f}, // 20 Marquee (magenta)
    {0.80f, 0.55f, 0.30f, 0.85f}, // 21 Meteors (amber)
    {0.60f, 0.40f, 0.50f, 0.85f}, // 22 Morph (rose)
    {0.45f, 0.55f, 0.75f, 0.85f}, // 23 Music (periwinkle)
    {0.30f, 0.30f, 0.30f, 0.85f}, // 24 Off (dark gray)
    {0.85f, 0.85f, 0.50f, 0.85f}, // 25 On (yellow)
    {0.65f, 0.50f, 0.40f, 0.85f}, // 26 Pictures (brown)
    {0.40f, 0.60f, 0.60f, 0.85f}, // 27 Pinwheel (cyan)
    {0.55f, 0.45f, 0.70f, 0.85f}, // 28 Plasma (violet)
    {0.65f, 0.40f, 0.40f, 0.85f}, // 29 Ripple (rust)
};

static const NSUInteger kEffectColorPaletteCount = sizeof(kEffectColorPalette) / sizeof(kEffectColorPalette[0]);

- (simd_float4)simdColorForEffectIndex:(NSInteger)effectIndex {
    // Direct C array access - no ObjC message sends, no heap pointers
    NSUInteger idx = (NSUInteger)(effectIndex % (NSInteger)kEffectColorPaletteCount);
    if (effectIndex < 0) idx = 0;
    const XLEffectColorEntry *e = &kEffectColorPalette[idx];
    return simd_make_float4(e->r, e->g, e->b, e->a);
}

+ (NSColor *)colorForEffectIndex:(NSInteger)effectIndex {
    // Construct NSColor on-demand from static C data.
    // This method is for external callers; the render path uses simdColorForEffectIndex: directly.
    NSUInteger idx = (NSUInteger)(effectIndex % (NSInteger)kEffectColorPaletteCount);
    if (effectIndex < 0) idx = 0;
    const XLEffectColorEntry *e = &kEffectColorPalette[idx];
    return [NSColor colorWithRed:e->r green:e->g blue:e->b alpha:e->a];
}

@end
