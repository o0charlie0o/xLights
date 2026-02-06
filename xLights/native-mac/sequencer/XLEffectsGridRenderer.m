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

typedef struct {
    simd_float2 position;
    simd_float2 texCoord;
} TexturedVertex;

// Icon atlas configuration (2x for Retina)
static const NSInteger kIconAtlasSize = 1024;     // Atlas texture size (1024x1024 for Retina)
static const NSInteger kIconCellSize = 64;        // Each icon cell size (2x for Retina)
static const NSInteger kIconsPerRow = 16;         // 1024/64 = 16 icons per row
static const NSInteger kMaxIconVertices = 8192;   // Max icon quads (6 verts each)

static const NSInteger kMaxGridLineVertices = 8192;
static const NSInteger kMaxEffectVertices = 32768;
static const CGFloat kEffectBlockCornerRadius = 3.0;
static const CGFloat kEffectBlockInset = 1.0;

// Pre-allocated buffer sizes for reuse (avoids per-frame allocations)
static const NSUInteger kGridLineBufferSize = kMaxGridLineVertices * sizeof(SimpleVertex);
static const NSUInteger kEffectBlockBufferSize = kMaxEffectVertices * sizeof(RoundedRectVertex);
static const NSUInteger kOutlineBufferSize = 4096 * sizeof(RoundedRectVertex);
static const NSUInteger kIconBufferSize = kMaxIconVertices * sizeof(TexturedVertex);
static const NSUInteger kLabelBufferSize = 6 * sizeof(TexturedVertex);  // One full-screen quad

// Triple-buffering to prevent CPU/GPU race conditions during scrolling
static const NSInteger kMaxInflightFrames = 3;

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
    NSInteger timingRowCount;  // Number of timing track rows at the top of the grid
    NSInteger activeTimingColorIndex; // Color index of the active timing track (-1 if none)
    CGFloat contentsScale;     // Backing scale factor (1.0 or 2.0 for retina)
} XLGridFrameParams;

@interface XLEffectsGridRenderer () {
    // Triple-buffered vertex buffers to prevent CPU/GPU race conditions during scrolling.
    // While the GPU is rendering frame N, the CPU can write to frame N+1 and N+2 buffers.
    id<MTLBuffer> _gridLineBuffers[kMaxInflightFrames];
    id<MTLBuffer> _effectBlockBuffers[kMaxInflightFrames];
    id<MTLBuffer> _outlineBuffers[kMaxInflightFrames];
    id<MTLBuffer> _iconBuffers[kMaxInflightFrames];
    id<MTLBuffer> _labelBuffers[kMaxInflightFrames];
    NSInteger _currentBufferIndex;
    dispatch_semaphore_t _frameSemaphore;
    NSInteger _nextIconIndex;
    id<MTLTexture> _labelTexture;
    NSUInteger _labelTextureWidth;
    NSUInteger _labelTextureHeight;
}

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> linePipeline;
@property (nonatomic, strong) id<MTLRenderPipelineState> effectBlockPipeline;
@property (nonatomic, strong) id<MTLRenderPipelineState> outlinePipeline;
@property (nonatomic, strong) id<MTLRenderPipelineState> iconPipeline;

// Icon texture atlas
@property (nonatomic, strong) id<MTLTexture> iconAtlasTexture;
@property (nonatomic, strong) id<MTLSamplerState> iconSampler;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *iconAtlasMap;

// Single-buffered (small data, updated infrequently, less contention)
@property (nonatomic, strong) id<MTLBuffer> playbackBuffer;
@property (nonatomic, strong) id<MTLBuffer> dropIndicatorBuffer;
@property (nonatomic, strong) id<MTLBuffer> rubberBandBuffer;

@end

@implementation XLEffectsGridRenderer

#pragma mark - Initialization

- (instancetype)initWithLayer:(CAMetalLayer *)metalLayer {
    self = [super init];
    if (self) {
        if (!metalLayer) {
            NSLog(@"XLEffectsGridRenderer: Cannot initialize - metalLayer is nil");
            return nil;
        }

        _device = MTLCreateSystemDefaultDevice();
        if (!_device) {
            NSLog(@"XLEffectsGridRenderer: Metal not available on this system");
            return nil;
        }

        @try {
            metalLayer.device = _device;
            metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
            metalLayer.framebufferOnly = YES;

            _commandQueue = [_device newCommandQueue];
            if (!_commandQueue) {
                NSLog(@"XLEffectsGridRenderer: Failed to create command queue");
                return nil;
            }

            if (![self buildPipelines]) {
                NSLog(@"XLEffectsGridRenderer: Failed to build render pipelines");
                return nil;
            }

            // Pre-allocate reusable Metal buffers
            [self allocateReusableBuffers];

            // Build icon texture atlas
            [self buildIconAtlas];
        } @catch (NSException *exception) {
            NSLog(@"XLEffectsGridRenderer: Exception during initialization: %@ - %@",
                  exception.name, exception.reason);
            return nil;
        }
    }
    return self;
}

+ (BOOL)isMetalAvailable {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    return device != nil;
}

- (void)allocateReusableBuffers {
    // Initialize triple-buffering semaphore - allows up to 3 frames in flight
    _frameSemaphore = dispatch_semaphore_create(kMaxInflightFrames);
    _currentBufferIndex = 0;

    // Allocate triple-buffered vertex buffers for grid lines, effect blocks, and outlines.
    // This prevents CPU/GPU race conditions: while GPU renders buffer N,
    // CPU can safely write to buffers N+1 and N+2.
    for (NSInteger i = 0; i < kMaxInflightFrames; i++) {
        _gridLineBuffers[i] = [_device newBufferWithLength:kGridLineBufferSize
                                                   options:MTLResourceStorageModeShared];
        [_gridLineBuffers[i] setLabel:[NSString stringWithFormat:@"GridLineBuffer_%ld", (long)i]];

        _effectBlockBuffers[i] = [_device newBufferWithLength:kEffectBlockBufferSize
                                                      options:MTLResourceStorageModeShared];
        [_effectBlockBuffers[i] setLabel:[NSString stringWithFormat:@"EffectBlockBuffer_%ld", (long)i]];

        _outlineBuffers[i] = [_device newBufferWithLength:kOutlineBufferSize
                                                  options:MTLResourceStorageModeShared];
        [_outlineBuffers[i] setLabel:[NSString stringWithFormat:@"OutlineBuffer_%ld", (long)i]];

        _iconBuffers[i] = [_device newBufferWithLength:kIconBufferSize
                                               options:MTLResourceStorageModeShared];
        [_iconBuffers[i] setLabel:[NSString stringWithFormat:@"IconBuffer_%ld", (long)i]];

        _labelBuffers[i] = [_device newBufferWithLength:kLabelBufferSize
                                                options:MTLResourceStorageModeShared];
        [_labelBuffers[i] setLabel:[NSString stringWithFormat:@"LabelBuffer_%ld", (long)i]];
    }

    // Playback indicator buffer (6 vertices for 2 triangles) - single buffered, small data
    _playbackBuffer = [_device newBufferWithLength:6 * sizeof(SimpleVertex)
                                           options:MTLResourceStorageModeShared];
    [_playbackBuffer setLabel:@"PlaybackBuffer"];

    // Drop indicator buffer (6 vertices for 2 triangles forming a rounded rect)
    _dropIndicatorBuffer = [_device newBufferWithLength:6 * sizeof(RoundedRectVertex)
                                                options:MTLResourceStorageModeShared];
    [_dropIndicatorBuffer setLabel:@"DropIndicatorBuffer"];

    // Rubber band selection buffer (6 vertices for fill + up to 512 for dashed border)
    _rubberBandBuffer = [_device newBufferWithLength:520 * sizeof(SimpleVertex)
                                             options:MTLResourceStorageModeShared];
    [_rubberBandBuffer setLabel:@"RubberBandBuffer"];
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
        "}\n"
        "\n"
        "// Icon rendering shaders (textured quads)\n"
        "struct IconVertexIn {\n"
        "    float2 position [[attribute(0)]];\n"
        "    float2 texCoord [[attribute(1)]];\n"
        "};\n"
        "\n"
        "struct IconVertexOut {\n"
        "    float4 position [[position]];\n"
        "    float2 texCoord;\n"
        "};\n"
        "\n"
        "vertex IconVertexOut iconVertexShader(\n"
        "    IconVertexIn in [[stage_in]],\n"
        "    constant EffectsGridUniforms &uniforms [[buffer(1)]])\n"
        "{\n"
        "    IconVertexOut out;\n"
        "    float2 pos = in.position;\n"
        "    float2 ndc = (pos / uniforms.viewportSize) * 2.0 - 1.0;\n"
        "    ndc.y = -ndc.y;\n"
        "    out.position = float4(ndc, 0.0, 1.0);\n"
        "    out.texCoord = in.texCoord;\n"
        "    return out;\n"
        "}\n"
        "\n"
        "fragment float4 iconFragmentShader(\n"
        "    IconVertexOut in [[stage_in]],\n"
        "    texture2d<float> iconAtlas [[texture(0)]],\n"
        "    sampler iconSampler [[sampler(0)]])\n"
        "{\n"
        "    float4 texColor = iconAtlas.sample(iconSampler, in.texCoord);\n"
        "    // Icons are white on transparent - use alpha as mask\n"
        "    return texColor;\n"
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
        vertexDesc.attributes[1].offset = offsetof(SimpleVertex, color);
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

    // Icon pipeline (textured quads)
    {
        MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
        vertexDesc.attributes[0].format = MTLVertexFormatFloat2;
        vertexDesc.attributes[0].offset = offsetof(TexturedVertex, position);
        vertexDesc.attributes[0].bufferIndex = 0;
        vertexDesc.attributes[1].format = MTLVertexFormatFloat2;
        vertexDesc.attributes[1].offset = offsetof(TexturedVertex, texCoord);
        vertexDesc.attributes[1].bufferIndex = 0;
        vertexDesc.layouts[0].stride = sizeof(TexturedVertex);

        MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
        desc.vertexFunction = [library newFunctionWithName:@"iconVertexShader"];
        desc.fragmentFunction = [library newFunctionWithName:@"iconFragmentShader"];
        desc.vertexDescriptor = vertexDesc;
        desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        desc.colorAttachments[0].blendingEnabled = YES;
        desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

        _iconPipeline = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
        if (!_iconPipeline) {
            NSLog(@"XLEffectsGridRenderer: Icon pipeline error: %@", error);
            return NO;
        }

        // Create sampler for icon texture
        MTLSamplerDescriptor *samplerDesc = [[MTLSamplerDescriptor alloc] init];
        samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
        samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
        samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
        samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
        _iconSampler = [_device newSamplerStateWithDescriptor:samplerDesc];
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
activeTimingColorIndex:(NSInteger)activeTimingColorIndex
      dropIndicator:(BOOL)showDropIndicator
            dropRow:(NSInteger)dropRow
        dropStartMS:(CGFloat)dropStartMS
          dropEndMS:(CGFloat)dropEndMS
   rubberBandActive:(BOOL)rubberBandActive
     rubberBandRect:(NSRect)rubberBandRect
{
    // Wait for a buffer slot to become available (blocks if all 3 are in-flight).
    // This prevents CPU from writing to a buffer the GPU is still reading.
    dispatch_semaphore_wait(_frameSemaphore, DISPATCH_TIME_FOREVER);

    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (!drawable) {
        // Release semaphore if we can't get a drawable
        dispatch_semaphore_signal(_frameSemaphore);
        return;
    }

    // Capture current buffer index for this frame (local copy for thread safety)
    NSInteger bufferIndex = _currentBufferIndex;
    // Rotate to next buffer for the next frame
    _currentBufferIndex = (_currentBufferIndex + 1) % kMaxInflightFrames;

    // All per-frame state lives on the stack — no ivars, no heap pointers
    // that could become stale due to concurrent mutation.
    // Count timing rows from effect data (timing rows are sorted to top)
    NSInteger timingRowCount = 0;
    if (effects && effectCount > 0) {
        BOOL seenRows[512];
        memset(seenRows, 0, sizeof(seenRows));
        for (NSUInteger i = 0; i < effectCount; i++) {
            if (effects[i].isTimingMark && effects[i].row >= 0 && effects[i].row < 512) {
                if (!seenRows[effects[i].row]) {
                    seenRows[effects[i].row] = YES;
                    timingRowCount++;
                }
            }
        }
    }

    XLGridFrameParams fp = {
        .viewSize = viewSize,
        .scrollOffset = scrollOffset,
        .zoomLevel = zoomLevel,
        .rowHeight = rowHeight,
        .totalRows = totalRows,
        .sequenceLengthMS = sequenceLengthMS,
        .selectedEffectID = selectedEffectID,
        .playbackPositionMS = playbackPositionMS,
        .timingRowCount = timingRowCount,
        .activeTimingColorIndex = activeTimingColorIndex,
        .contentsScale = layer.contentsScale,
    };

    MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.colorAttachments[0].texture = drawable.texture;
    passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.118, 0.118, 0.118, 1.0);

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    if (!commandBuffer) {
        dispatch_semaphore_signal(_frameSemaphore);
        return;
    }

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];
    if (!encoder) {
        dispatch_semaphore_signal(_frameSemaphore);
        return;
    }

    EffectsGridUniforms uniforms;
    uniforms.viewportSize = simd_make_float2(viewSize.width, viewSize.height);
    uniforms.scrollOffset = simd_make_float2(scrollOffset.x, scrollOffset.y);
    uniforms.zoomLevel = (float)zoomLevel;
    uniforms.rowHeight = (float)rowHeight;
    uniforms.padding0 = 0;
    uniforms.padding1 = 0;

    [self drawGridLinesWithEncoder:encoder uniforms:uniforms params:fp
                       bufferIndex:bufferIndex
                  timingMarkValues:timingMarkValues timingMarkCount:timingMarkCount];
    [self drawTimingTracksWithEncoder:encoder uniforms:uniforms params:fp
                              effects:effects effectCount:effectCount];
    [self drawTimingLabelsWithEncoder:encoder uniforms:uniforms params:fp
                          bufferIndex:bufferIndex
                              effects:effects effectCount:effectCount];
    [self drawEffectBlocksWithEncoder:encoder uniforms:uniforms params:fp
                          bufferIndex:bufferIndex
                              effects:effects effectCount:effectCount];

    [self drawIconsWithEncoder:encoder uniforms:uniforms params:fp
                   bufferIndex:bufferIndex
                       effects:effects effectCount:effectCount];

    // Draw drop indicator (ghost effect) during palette drag
    if (showDropIndicator && dropRow >= 0) {
        [self drawDropIndicatorWithEncoder:encoder uniforms:uniforms params:fp
                                       row:dropRow startMS:dropStartMS endMS:dropEndMS];
    }

    // Draw rubber band selection rectangle
    if (rubberBandActive) {
        [self drawRubberBandWithEncoder:encoder uniforms:uniforms params:fp rect:rubberBandRect];
    }

    [self drawPlaybackIndicatorWithEncoder:encoder uniforms:uniforms params:fp];

    [encoder endEncoding];

    // Signal semaphore when GPU completes this frame, allowing CPU to reuse the buffer
    __block dispatch_semaphore_t semaphore = _frameSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull buffer) {
        dispatch_semaphore_signal(semaphore);
    }];

    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

#pragma mark - Grid Lines

- (void)drawGridLinesWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                        uniforms:(EffectsGridUniforms)uniforms
                          params:(XLGridFrameParams)fp
                     bufferIndex:(NSInteger)bufferIndex
                timingMarkValues:(const CGFloat *)timingMarkValues
                 timingMarkCount:(NSUInteger)timingMarkCount
{
    CGSize viewSize = fp.viewSize;
    CGPoint scrollOffset = fp.scrollOffset;
    CGFloat zoomLevel = fp.zoomLevel;
    CGFloat rowHeight = fp.rowHeight;
    NSInteger totalRows = fp.totalRows;
    CGFloat sequenceLengthMS = fp.sequenceLengthMS;

    // Write directly into pre-allocated buffer for this frame (triple-buffered)
    id<MTLBuffer> gridLineBuffer = _gridLineBuffers[bufferIndex];
    SimpleVertex *vertices = (SimpleVertex *)gridLineBuffer.contents;
    NSUInteger vertexCount = 0;
    NSUInteger maxVertices = kGridLineBufferSize / sizeof(SimpleVertex);

    // Horizontal row separator lines
    simd_float4 rowLineColor = simd_make_float4(0.25, 0.25, 0.25, 1.0);
    CGFloat firstVisibleRow = scrollOffset.y / rowHeight;
    CGFloat lastVisibleRow = (scrollOffset.y + viewSize.height) / rowHeight;
    NSInteger startRow = MAX(0, (NSInteger)floor(firstVisibleRow));
    NSInteger endRow = MIN(totalRows, (NSInteger)ceil(lastVisibleRow) + 1);

    for (NSInteger row = startRow; row <= endRow; row++) {
        CGFloat y = row * rowHeight - scrollOffset.y;
        if (y < -1 || y > viewSize.height + 1) continue;
        if (vertexCount + 2 > maxVertices) break;

        vertices[vertexCount++] = (SimpleVertex){ simd_make_float2(0, y), rowLineColor };
        vertices[vertexCount++] = (SimpleVertex){ simd_make_float2(viewSize.width, y), rowLineColor };
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
        if (vertexCount + 2 > maxVertices) break;

        BOOL isMajor = fmod(t, gridIntervalMS * 4) < 0.1;
        simd_float4 lineColor = isMajor ? majorLineColor : minorLineColor;

        vertices[vertexCount++] = (SimpleVertex){ simd_make_float2(x, 0), lineColor };
        vertices[vertexCount++] = (SimpleVertex){ simd_make_float2(x, viewSize.height), lineColor };
    }

    // Timing mark lines (from active timing track) — extend below timing rows
    // to provide snap-to visual across the effects area.
    if (timingMarkValues && timingMarkCount > 0) {
        // Use active timing track's color from the shared palette
        simd_float4 timingColor;
        if (fp.activeTimingColorIndex >= 0) {
            CGFloat cr, cg, cb;
            XLTimingTrackColor(fp.activeTimingColorIndex, &cr, &cg, &cb);
            timingColor = simd_make_float4(cr, cg, cb, 1.0);
        } else {
            timingColor = simd_make_float4(0.25, 0.25, 0.25, 0.3);
        }
        // Start grid lines below timing track rows (they're always at the top)
        CGFloat timingGridTop = fp.timingRowCount * rowHeight - scrollOffset.y;
        for (NSUInteger mi = 0; mi < timingMarkCount; mi++) {
            CGFloat t = timingMarkValues[mi];
            CGFloat x = t * zoomLevel - scrollOffset.x;
            if (x < -1 || x > viewSize.width + 1) continue;
            if (vertexCount + 2 > maxVertices) break;

            vertices[vertexCount++] = (SimpleVertex){ simd_make_float2(x, timingGridTop), timingColor };
            vertices[vertexCount++] = (SimpleVertex){ simd_make_float2(x, viewSize.height), timingColor };
        }
    }

    if (vertexCount == 0) return;

    // Use pre-allocated triple-buffered buffer - data is already written
    [encoder setRenderPipelineState:_linePipeline];
    [encoder setVertexBuffer:gridLineBuffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:vertexCount];
}

#pragma mark - Timing Tracks

- (void)drawTimingTracksWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                           uniforms:(EffectsGridUniforms)uniforms
                             params:(XLGridFrameParams)fp
                            effects:(const XLEffectRenderInfo *)effects
                        effectCount:(NSUInteger)effectCount
{
    if (!effects || effectCount == 0) return;

    CGSize viewSize = fp.viewSize;
    CGPoint scrollOffset = fp.scrollOffset;
    CGFloat zoomLevel = fp.zoomLevel;
    CGFloat rowHeight = fp.rowHeight;

    CGFloat msPerPixel = 1.0 / zoomLevel;
    CGFloat visibleStartMS = scrollOffset.x * msPerPixel;
    CGFloat visibleEndMS = visibleStartMS + viewSize.width * msPerPixel;
    CGFloat visibleStartRow = scrollOffset.y / rowHeight;
    CGFloat visibleEndRow = (scrollOffset.y + viewSize.height) / rowHeight;

    // Timing tracks need far fewer vertices than the effects grid —
    // a horizontal line per row + 2 vertices per tick boundary.
    static const NSUInteger kMaxTimingVertices = 2048;
    SimpleVertex vertices[kMaxTimingVertices];
    NSUInteger maxVertices = kMaxTimingVertices;
    NSUInteger vertexCount = 0;

    // Collect which rows are timing tracks (for horizontal center lines)
    // and collect all tick positions
    BOOL rowSeen[512];
    memset(rowSeen, 0, sizeof(rowSeen));

    for (NSUInteger ei = 0; ei < effectCount; ei++) {
        XLEffectRenderInfo info = effects[ei];
        if (!info.isTimingMark) continue;

        // Row visibility culling
        if (info.row < (NSInteger)floor(visibleStartRow) - 1 ||
            info.row > (NSInteger)ceil(visibleEndRow) + 1) continue;

        CGFloat cr, cg, cb;
        XLTimingTrackColor(info.timingColorIndex, &cr, &cg, &cb);
        simd_float4 tickColor = simd_make_float4(cr, cg, cb, 0.9);
        simd_float4 lineColor = simd_make_float4(cr * 0.6, cg * 0.6, cb * 0.6, 0.5);

        CGFloat yTop = info.row * rowHeight - scrollOffset.y;
        CGFloat yBot = yTop + rowHeight;
        CGFloat yMid = yTop + rowHeight * 0.5;

        // Draw horizontal center line once per row
        if (info.row >= 0 && info.row < 512 && !rowSeen[info.row]) {
            rowSeen[info.row] = YES;
            if (vertexCount + 2 <= maxVertices) {
                vertices[vertexCount++] = (SimpleVertex){ simd_make_float2(0, yMid), lineColor };
                vertices[vertexCount++] = (SimpleVertex){ simd_make_float2(viewSize.width, yMid), lineColor };
            }
        }

        // Vertical tick at start time
        CGFloat xStart = info.startTimeMS * zoomLevel - scrollOffset.x;
        if (xStart >= -1 && xStart <= viewSize.width + 1) {
            if (vertexCount + 2 <= maxVertices) {
                vertices[vertexCount++] = (SimpleVertex){ simd_make_float2(xStart, yTop + 2), tickColor };
                vertices[vertexCount++] = (SimpleVertex){ simd_make_float2(xStart, yBot - 2), tickColor };
            }
        }

        // Vertical tick at end time
        CGFloat xEnd = info.endTimeMS * zoomLevel - scrollOffset.x;
        if (xEnd >= -1 && xEnd <= viewSize.width + 1) {
            if (vertexCount + 2 <= maxVertices) {
                vertices[vertexCount++] = (SimpleVertex){ simd_make_float2(xEnd, yTop + 2), tickColor };
                vertices[vertexCount++] = (SimpleVertex){ simd_make_float2(xEnd, yBot - 2), tickColor };
            }
        }
    }

    if (vertexCount == 0) return;

    // Upload and draw using the line pipeline
    id<MTLBuffer> buffer = [_device newBufferWithBytes:vertices
                                               length:vertexCount * sizeof(SimpleVertex)
                                              options:MTLResourceStorageModeShared];
    [encoder setRenderPipelineState:_linePipeline];
    [encoder setVertexBuffer:buffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:vertexCount];
}

#pragma mark - Timing Labels

- (void)drawTimingLabelsWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                           uniforms:(EffectsGridUniforms)uniforms
                             params:(XLGridFrameParams)fp
                        bufferIndex:(NSInteger)bufferIndex
                            effects:(const XLEffectRenderInfo *)effects
                        effectCount:(NSUInteger)effectCount
{
    // Labels are now drawn via CALayer overlay in XLEffectsGridView -drawTimingLabels
    return;
    if (!effects || effectCount == 0 || !_iconPipeline || !_iconSampler) return;

    CGSize viewSize = fp.viewSize;
    CGPoint scrollOffset = fp.scrollOffset;
    CGFloat zoomLevel = fp.zoomLevel;
    CGFloat rowHeight = fp.rowHeight;

    CGFloat msPerPixel = 1.0 / zoomLevel;
    CGFloat visibleStartMS = scrollOffset.x * msPerPixel;
    CGFloat visibleEndMS = visibleStartMS + viewSize.width * msPerPixel;
    CGFloat visibleStartRow = scrollOffset.y / rowHeight;
    CGFloat visibleEndRow = (scrollOffset.y + viewSize.height) / rowHeight;

    // Collect visible timing marks with non-empty labels
    typedef struct {
        CGFloat x1, x2, yMid;
        NSInteger layer;
        const char *label;
    } LabelEntry;

    static const NSUInteger kMaxLabels = 512;
    LabelEntry labels[kMaxLabels];
    NSUInteger labelCount = 0;

    for (NSUInteger ei = 0; ei < effectCount && labelCount < kMaxLabels; ei++) {
        XLEffectRenderInfo info = effects[ei];
        if (!info.isTimingMark || info.label[0] == '\0') continue;

        if (info.endTimeMS < visibleStartMS || info.startTimeMS > visibleEndMS) continue;
        if (info.row < (NSInteger)floor(visibleStartRow) - 1 ||
            info.row > (NSInteger)ceil(visibleEndRow) + 1) continue;

        CGFloat x1 = info.startTimeMS * zoomLevel - scrollOffset.x;
        CGFloat x2 = info.endTimeMS * zoomLevel - scrollOffset.x;
        if (x2 - x1 < 8.0) continue;  // Too narrow for text

        CGFloat yMid = info.row * rowHeight - scrollOffset.y + rowHeight * 0.5;

        labels[labelCount++] = (LabelEntry){ x1, x2, yMid, info.layer, info.label };
    }

    if (labelCount == 0) return;

    // Create bitmap context matching viewport size
    NSUInteger texW = (NSUInteger)viewSize.width;
    NSUInteger texH = (NSUInteger)viewSize.height;
    if (texW == 0 || texH == 0) return;

    NSUInteger bytesPerRow = texW * 4;
    NSMutableData *bitmapData = [NSMutableData dataWithLength:texH * bytesPerRow];
    unsigned char *pixels = (unsigned char *)bitmapData.mutableBytes;
    memset(pixels, 0, bitmapData.length);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels, texW, texH, 8, bytesPerRow,
                                              colorSpace, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!ctx) return;

    // Flip for correct text orientation
    CGContextTranslateCTM(ctx, 0, texH);
    CGContextScaleCTM(ctx, 1.0, -1.0);

    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:gc];

    // Scale font size for retina — the bitmap is at pixel resolution
    CGFloat scale = fp.contentsScale;
    if (scale < 1.0) scale = 2.0;
    CGFloat fontSize = 9.0 * scale;
    NSFont *labelFont = [NSFont systemFontOfSize:fontSize weight:NSFontWeightMedium];
    NSDictionary *textAttrs = @{
        NSFontAttributeName: labelFont,
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };

    for (NSUInteger i = 0; i < labelCount; i++) {
        LabelEntry le = labels[i];
        CGFloat padding = 2.0 * scale;
        CGFloat availW = le.x2 - le.x1 - padding * 2;
        if (availW < 4.0 * scale) continue;

        NSString *text = [NSString stringWithUTF8String:le.label];
        if (!text || text.length == 0) continue;

        NSSize textSize = [text sizeWithAttributes:textAttrs];

        // Background color by layer index
        // Layer 0 = phrases (green), layer 1 = words (cyan), layer 2 = phonemes (pink/magenta)
        NSColor *bgColor;
        if (le.layer == 0) {
            bgColor = [NSColor colorWithCalibratedRed:0.15 green:0.4 blue:0.15 alpha:0.9];
        } else if (le.layer == 1) {
            bgColor = [NSColor colorWithCalibratedRed:0.1 green:0.4 blue:0.5 alpha:0.9];
        } else if (le.layer == 2) {
            bgColor = [NSColor colorWithCalibratedRed:0.5 green:0.15 blue:0.45 alpha:0.9];
        } else {
            bgColor = [NSColor colorWithCalibratedRed:0.35 green:0.35 blue:0.35 alpha:0.9];
        }

        // Fill the entire cell area between tick marks
        CGFloat bgX = le.x1 + 1.0;
        CGFloat bgW = le.x2 - le.x1 - 2.0;
        CGFloat bgH = rowHeight - 2.0;
        CGFloat bgY = le.yMid - bgH * 0.5;
        NSRect bgRect = NSMakeRect(bgX, bgY, bgW, bgH);
        CGFloat cornerR = 3.0 * scale;
        NSBezierPath *bgPath = [NSBezierPath bezierPathWithRoundedRect:bgRect xRadius:cornerR yRadius:cornerR];
        [bgColor setFill];
        [bgPath fill];

        // Draw text centered in the cell (clipped to available width)
        CGFloat textW = MIN(textSize.width, bgW - padding * 2);
        CGFloat textX = bgX + (bgW - textW) * 0.5;
        CGFloat textY = le.yMid - textSize.height * 0.5;
        NSRect textRect = NSMakeRect(textX, textY, textW, textSize.height);
        [text drawWithRect:textRect options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                attributes:textAttrs context:nil];
    }

    [NSGraphicsContext restoreGraphicsState];
    CGContextRelease(ctx);

    // Create/update label texture
    if (!_labelTexture || _labelTextureWidth != texW || _labelTextureHeight != texH) {
        MTLTextureDescriptor *texDesc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                         width:texW height:texH mipmapped:NO];
        texDesc.usage = MTLTextureUsageShaderRead;
        _labelTexture = [_device newTextureWithDescriptor:texDesc];
        [_labelTexture setLabel:@"TimingLabels"];
        _labelTextureWidth = texW;
        _labelTextureHeight = texH;
    }

    MTLRegion region = MTLRegionMake2D(0, 0, texW, texH);
    [_labelTexture replaceRegion:region mipmapLevel:0 withBytes:pixels bytesPerRow:bytesPerRow];

    // Draw full-screen textured quad
    id<MTLBuffer> labelBuffer = _labelBuffers[bufferIndex];
    if (!labelBuffer) return;
    TexturedVertex *verts = (TexturedVertex *)labelBuffer.contents;

    CGFloat w = viewSize.width;
    CGFloat h = viewSize.height;
    verts[0] = (TexturedVertex){ simd_make_float2(0, 0), simd_make_float2(0, 0) };
    verts[1] = (TexturedVertex){ simd_make_float2(w, 0), simd_make_float2(1, 0) };
    verts[2] = (TexturedVertex){ simd_make_float2(0, h), simd_make_float2(0, 1) };
    verts[3] = (TexturedVertex){ simd_make_float2(w, 0), simd_make_float2(1, 0) };
    verts[4] = (TexturedVertex){ simd_make_float2(w, h), simd_make_float2(1, 1) };
    verts[5] = (TexturedVertex){ simd_make_float2(0, h), simd_make_float2(0, 1) };

    [encoder setRenderPipelineState:_iconPipeline];
    [encoder setVertexBuffer:labelBuffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder setFragmentTexture:_labelTexture atIndex:0];
    [encoder setFragmentSamplerState:_iconSampler atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
}

#pragma mark - Effect Blocks

- (void)drawEffectBlocksWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                           uniforms:(EffectsGridUniforms)uniforms
                             params:(XLGridFrameParams)fp
                        bufferIndex:(NSInteger)bufferIndex
                            effects:(const XLEffectRenderInfo *)effects
                        effectCount:(NSUInteger)effectCount
{
    CGSize viewSize = fp.viewSize;
    CGPoint scrollOffset = fp.scrollOffset;
    CGFloat zoomLevel = fp.zoomLevel;
    CGFloat rowHeight = fp.rowHeight;

    if (!effects || effectCount == 0) return;

    // Write directly into pre-allocated triple-buffered buffers for this frame
    id<MTLBuffer> effectBlockBuffer = _effectBlockBuffers[bufferIndex];
    id<MTLBuffer> outlineBuffer = _outlineBuffers[bufferIndex];
    RoundedRectVertex *blockVertices = (RoundedRectVertex *)effectBlockBuffer.contents;
    RoundedRectVertex *outlineVertices = (RoundedRectVertex *)outlineBuffer.contents;
    NSUInteger blockVertexCount = 0;
    NSUInteger outlineVertexCount = 0;
    NSUInteger maxBlockVertices = kEffectBlockBufferSize / sizeof(RoundedRectVertex);
    NSUInteger maxOutlineVertices = kOutlineBufferSize / sizeof(RoundedRectVertex);

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

        // Inset timing mark blocks so tick lines are visible between them
        if (info.isTimingMark) {
            x1 += 1.0;
            x2 -= 1.0;
        }

        // Skip if too narrow to draw
        if (x2 - x1 < 2.0) continue;

        // Check buffer capacity
        if (blockVertexCount + 6 > maxBlockVertices) break;

        simd_float4 color;
        if (info.isTimingMark) {
            // Only draw colored blocks for lyric tracks (multi-layer timing tracks)
            // Plain timing tracks (1 layer) keep their original tick-only appearance
            if (info.timingTrackLayerCount <= 1 || info.label[0] == '\0') continue;
            // Lyric track colors by layer: phrases=emerald, words=electric blue, phonemes=magenta
            if (info.layer == 0) {
                color = simd_make_float4(0.1, 0.55, 0.3, 0.85);
            } else if (info.layer == 1) {
                color = simd_make_float4(0.15, 0.4, 0.75, 0.85);
            } else if (info.layer == 2) {
                color = simd_make_float4(0.7, 0.15, 0.55, 0.85);
            } else {
                color = simd_make_float4(0.4, 0.4, 0.4, 0.85);
            }
        } else if (info.colorARGB != 0) {
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
        // Write directly to pre-allocated buffer
        RoundedRectVertex *vptr = &blockVertices[blockVertexCount];
        for (int i = 0; i < 6; i++) {
            vptr[i].color = color;
            vptr[i].rectMin = rectMin;
            vptr[i].rectMax = rectMax;
            vptr[i].cornerRadius = cornerRadius;
        }
        vptr[0].position = simd_make_float2(x1, y1);
        vptr[1].position = simd_make_float2(x2, y1);
        vptr[2].position = simd_make_float2(x1, y2);
        vptr[3].position = simd_make_float2(x2, y1);
        vptr[4].position = simd_make_float2(x2, y2);
        vptr[5].position = simd_make_float2(x1, y2);
        blockVertexCount += 6;

        // Selection outline
        if (info.selected && outlineVertexCount + 6 <= maxOutlineVertices) {
            simd_float4 selColor = simd_make_float4(0.3, 0.6, 1.0, 1.0);
            simd_float2 outlineMin = simd_make_float2(x1 - 1, y1 - 1);
            simd_float2 outlineMax = simd_make_float2(x2 + 1, y2 + 1);

            RoundedRectVertex *optr = &outlineVertices[outlineVertexCount];
            for (int i = 0; i < 6; i++) {
                optr[i].color = selColor;
                optr[i].rectMin = outlineMin;
                optr[i].rectMax = outlineMax;
                optr[i].cornerRadius = cornerRadius;
            }
            optr[0].position = simd_make_float2(x1 - 1, y1 - 1);
            optr[1].position = simd_make_float2(x2 + 1, y1 - 1);
            optr[2].position = simd_make_float2(x1 - 1, y2 + 1);
            optr[3].position = simd_make_float2(x2 + 1, y1 - 1);
            optr[4].position = simd_make_float2(x2 + 1, y2 + 1);
            optr[5].position = simd_make_float2(x1 - 1, y2 + 1);
            outlineVertexCount += 6;
        }
    }

    // Draw filled effect blocks using pre-allocated triple-buffered buffer
    if (blockVertexCount > 0) {
        [encoder setRenderPipelineState:_effectBlockPipeline];
        [encoder setVertexBuffer:effectBlockBuffer offset:0 atIndex:0];
        [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:blockVertexCount];
    }

    // Draw fade in/out ramp overlays on top of effect blocks.
    // DAW-style: dark semi-transparent triangles at left (fade in) and right (fade out).
    {
        static const NSUInteger kMaxFadeVertices = 4096;
        SimpleVertex fadeVertices[kMaxFadeVertices];
        NSUInteger fadeVertexCount = 0;

        simd_float4 fadeColor = simd_make_float4(0.0, 0.0, 0.0, 0.4);

        for (NSUInteger ei = 0; ei < effectCount; ei++) {
            XLEffectRenderInfo info = effects[ei];
            if (info.isTimingMark) continue;
            if (info.fadeInMS <= 0 && info.fadeOutMS <= 0) continue;

            // Frustum culling
            if (info.endTimeMS < visibleStartMS || info.startTimeMS > visibleEndMS) continue;
            if (info.row < (NSInteger)floor(visibleStartRow) - 1 ||
                info.row > (NSInteger)ceil(visibleEndRow) + 1) continue;

            CGFloat x1 = info.startTimeMS * zoomLevel - scrollOffset.x;
            CGFloat x2 = info.endTimeMS * zoomLevel - scrollOffset.x;
            CGFloat y1 = info.row * rowHeight - scrollOffset.y + kEffectBlockInset;
            CGFloat y2 = (info.row + 1) * rowHeight - scrollOffset.y - kEffectBlockInset;
            CGFloat blockWidth = x2 - x1;
            if (blockWidth < 2.0) continue;

            CGFloat durationMS = info.endTimeMS - info.startTimeMS;
            if (durationMS <= 0) continue;

            // Fade in: triangle from bottom-left to top at fade-in end
            if (info.fadeInMS > 0 && fadeVertexCount + 3 <= kMaxFadeVertices) {
                CGFloat fadeFrac = MIN(info.fadeInMS / durationMS, 1.0);
                CGFloat fadeEndX = x1 + blockWidth * fadeFrac;
                // Triangle: bottom-left, top-left, top at fade end
                fadeVertices[fadeVertexCount++] = (SimpleVertex){ simd_make_float2(x1, y2), fadeColor };
                fadeVertices[fadeVertexCount++] = (SimpleVertex){ simd_make_float2(x1, y1), fadeColor };
                fadeVertices[fadeVertexCount++] = (SimpleVertex){ simd_make_float2(fadeEndX, y1), fadeColor };
            }

            // Fade out: triangle from top at fade-out start to bottom-right
            if (info.fadeOutMS > 0 && fadeVertexCount + 3 <= kMaxFadeVertices) {
                CGFloat fadeFrac = MIN(info.fadeOutMS / durationMS, 1.0);
                CGFloat fadeStartX = x2 - blockWidth * fadeFrac;
                // Triangle: top at fade start, top-right, bottom-right
                fadeVertices[fadeVertexCount++] = (SimpleVertex){ simd_make_float2(fadeStartX, y1), fadeColor };
                fadeVertices[fadeVertexCount++] = (SimpleVertex){ simd_make_float2(x2, y1), fadeColor };
                fadeVertices[fadeVertexCount++] = (SimpleVertex){ simd_make_float2(x2, y2), fadeColor };
            }
        }

        if (fadeVertexCount > 0) {
            id<MTLBuffer> fadeBuffer = [_device newBufferWithBytes:fadeVertices
                                                           length:fadeVertexCount * sizeof(SimpleVertex)
                                                          options:MTLResourceStorageModeShared];
            [encoder setRenderPipelineState:_linePipeline];
            [encoder setVertexBuffer:fadeBuffer offset:0 atIndex:0];
            [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:fadeVertexCount];
        }
    }

    // Draw selection outlines on top using pre-allocated triple-buffered buffer
    if (outlineVertexCount > 0) {
        [encoder setRenderPipelineState:_outlinePipeline];
        [encoder setVertexBuffer:outlineBuffer offset:0 atIndex:0];
        [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:outlineVertexCount];
    }
}

#pragma mark - Drop Indicator

- (void)drawDropIndicatorWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                            uniforms:(EffectsGridUniforms)uniforms
                              params:(XLGridFrameParams)fp
                                 row:(NSInteger)row
                             startMS:(CGFloat)startMS
                               endMS:(CGFloat)endMS
{
    if (!_dropIndicatorBuffer) return;

    CGSize viewSize = fp.viewSize;
    CGPoint scrollOffset = fp.scrollOffset;
    CGFloat zoomLevel = fp.zoomLevel;
    CGFloat rowHeight = fp.rowHeight;

    CGFloat x1 = startMS * zoomLevel - scrollOffset.x;
    CGFloat x2 = endMS * zoomLevel - scrollOffset.x;
    CGFloat y1 = row * rowHeight - scrollOffset.y + kEffectBlockInset;
    CGFloat y2 = (row + 1) * rowHeight - scrollOffset.y - kEffectBlockInset;

    // Skip if off-screen or invalid
    if (x2 < 0 || x1 > viewSize.width) return;
    if (y2 < 0 || y1 > viewSize.height) return;
    if (x2 <= x1 || y2 <= y1) return;

    // Semi-transparent white/blue ghost effect
    simd_float4 ghostColor = simd_make_float4(0.5, 0.7, 1.0, 0.5);

    simd_float2 rectMin = simd_make_float2(x1, y1);
    simd_float2 rectMax = simd_make_float2(x2, y2);
    float cornerRadius = (float)kEffectBlockCornerRadius;

    // Write to dedicated drop indicator buffer
    RoundedRectVertex *vptr = (RoundedRectVertex *)_dropIndicatorBuffer.contents;

    for (int i = 0; i < 6; i++) {
        vptr[i].color = ghostColor;
        vptr[i].rectMin = rectMin;
        vptr[i].rectMax = rectMax;
        vptr[i].cornerRadius = cornerRadius;
    }
    vptr[0].position = simd_make_float2(x1, y1);
    vptr[1].position = simd_make_float2(x2, y1);
    vptr[2].position = simd_make_float2(x1, y2);
    vptr[3].position = simd_make_float2(x2, y1);
    vptr[4].position = simd_make_float2(x2, y2);
    vptr[5].position = simd_make_float2(x1, y2);

    [encoder setRenderPipelineState:_effectBlockPipeline];
    [encoder setVertexBuffer:_dropIndicatorBuffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
}

#pragma mark - Rubber Band Selection

- (void)drawRubberBandWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                         uniforms:(EffectsGridUniforms)uniforms
                           params:(XLGridFrameParams)fp
                             rect:(NSRect)rect
{
    if (!_rubberBandBuffer) return;
    if (rect.size.width < 1 && rect.size.height < 1) return;

    CGFloat x1 = rect.origin.x;
    CGFloat y1 = rect.origin.y;
    CGFloat x2 = rect.origin.x + rect.size.width;
    CGFloat y2 = rect.origin.y + rect.size.height;

    // Normalize coordinates (handle negative size from drag direction)
    if (x1 > x2) { CGFloat t = x1; x1 = x2; x2 = t; }
    if (y1 > y2) { CGFloat t = y1; y1 = y2; y2 = t; }

    // White dashed border only (no fill)
    simd_float4 borderColor = simd_make_float4(1.0, 1.0, 1.0, 0.8);

    SimpleVertex *vptr = (SimpleVertex *)_rubberBandBuffer.contents;
    NSUInteger vertexIndex = 0;

    // Dashed border - draw alternating segments
    CGFloat dashLength = 4.0;
    CGFloat gapLength = 4.0;
    CGFloat patternLength = dashLength + gapLength;

    // Top edge (left to right)
    CGFloat edgeLength = x2 - x1;
    for (CGFloat pos = 0; pos < edgeLength && vertexIndex + 2 <= 520; pos += patternLength) {
        CGFloat dashEnd = MIN(pos + dashLength, edgeLength);
        vptr[vertexIndex++] = (SimpleVertex){ simd_make_float2(x1 + pos, y1), borderColor };
        vptr[vertexIndex++] = (SimpleVertex){ simd_make_float2(x1 + dashEnd, y1), borderColor };
    }

    // Right edge (top to bottom)
    edgeLength = y2 - y1;
    for (CGFloat pos = 0; pos < edgeLength && vertexIndex + 2 <= 520; pos += patternLength) {
        CGFloat dashEnd = MIN(pos + dashLength, edgeLength);
        vptr[vertexIndex++] = (SimpleVertex){ simd_make_float2(x2, y1 + pos), borderColor };
        vptr[vertexIndex++] = (SimpleVertex){ simd_make_float2(x2, y1 + dashEnd), borderColor };
    }

    // Bottom edge (right to left)
    edgeLength = x2 - x1;
    for (CGFloat pos = 0; pos < edgeLength && vertexIndex + 2 <= 520; pos += patternLength) {
        CGFloat dashEnd = MIN(pos + dashLength, edgeLength);
        vptr[vertexIndex++] = (SimpleVertex){ simd_make_float2(x2 - pos, y2), borderColor };
        vptr[vertexIndex++] = (SimpleVertex){ simd_make_float2(x2 - dashEnd, y2), borderColor };
    }

    // Left edge (bottom to top)
    edgeLength = y2 - y1;
    for (CGFloat pos = 0; pos < edgeLength && vertexIndex + 2 <= 520; pos += patternLength) {
        CGFloat dashEnd = MIN(pos + dashLength, edgeLength);
        vptr[vertexIndex++] = (SimpleVertex){ simd_make_float2(x1, y2 - pos), borderColor };
        vptr[vertexIndex++] = (SimpleVertex){ simd_make_float2(x1, y2 - dashEnd), borderColor };
    }

    // Draw dashed border only
    if (vertexIndex > 0) {
        [encoder setRenderPipelineState:_linePipeline];
        [encoder setVertexBuffer:_rubberBandBuffer offset:0 atIndex:0];
        [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:vertexIndex];
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

    // Red playback line (2px wide) - write directly to pre-allocated buffer
    simd_float4 playColor = simd_make_float4(1.0, 0.15, 0.15, 0.9);
    SimpleVertex *vertices = (SimpleVertex *)_playbackBuffer.contents;
    vertices[0] = (SimpleVertex){ simd_make_float2(x - 1, 0), playColor };
    vertices[1] = (SimpleVertex){ simd_make_float2(x + 1, 0), playColor };
    vertices[2] = (SimpleVertex){ simd_make_float2(x - 1, viewSize.height), playColor };
    vertices[3] = (SimpleVertex){ simd_make_float2(x + 1, 0), playColor };
    vertices[4] = (SimpleVertex){ simd_make_float2(x + 1, viewSize.height), playColor };
    vertices[5] = (SimpleVertex){ simd_make_float2(x - 1, viewSize.height), playColor };

    [encoder setRenderPipelineState:_linePipeline];
    [encoder setVertexBuffer:_playbackBuffer offset:0 atIndex:0];
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

#pragma mark - Icon Atlas

// Effect type to SF Symbol mapping (same as XLEffectsGridView)
static NSDictionary<NSString *, NSString *> *sEffectIconMapping = nil;

+ (NSDictionary<NSString *, NSString *> *)effectIconMapping {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sEffectIconMapping = @{
            @"Adjust": @"slider.horizontal.3",
            @"Arpeggio": @"music.note.list",
            @"Bars": @"chart.bar.fill",
            @"Butterfly": @"bird.fill",
            @"Candle": @"flame",
            @"Circles": @"circle.grid.3x3.fill",
            @"ColorWash": @"paintbrush.fill",
            @"Curtain": @"rectangle.split.2x1.fill",
            @"DMX": @"slider.vertical.3",
            @"Duplicate": @"plus.square.on.square",
            @"Faces": @"face.smiling.fill",
            @"Fan": @"fan.fill",
            @"Fill": @"square.fill",
            @"Fire": @"flame.fill",
            @"Fireworks": @"sparkles",
            @"Galaxy": @"staroflife.fill",
            @"Garlands": @"leaf.fill",
            @"Glediator": @"square.grid.3x3.fill",
            @"Guitar": @"guitars.fill",
            @"Kaleidoscope": @"camera.filters",
            @"Life": @"heart.fill",
            @"Lightning": @"bolt.fill",
            @"Lines": @"line.3.horizontal",
            @"Liquid": @"drop.fill",
            @"Marquee": @"text.badge.star",
            @"Meteors": @"moonphase.waning.crescent",
            @"Morph": @"arrow.triangle.2.circlepath",
            @"MovingHead": @"light.beacon.max.fill",
            @"Music": @"music.note",
            @"Off": @"power.circle",
            @"On": @"lightbulb.fill",
            @"Piano": @"pianokeys",
            @"Pictures": @"photo.fill",
            @"Pinwheel": @"rotate.3d",
            @"Plasma": @"waveform",
            @"Ripple": @"drop.circle.fill",
            @"Servo": @"gearshape.2.fill",
            @"Shader": @"paintpalette.fill",
            @"Shape": @"star.fill",
            @"Shimmer": @"sparkle",
            @"Shockwave": @"waveform.circle.fill",
            @"SingleStrand": @"line.diagonal",
            @"Sketch": @"pencil.tip",
            @"Snowflakes": @"snowflake",
            @"Snowstorm": @"cloud.snow.fill",
            @"Spirals": @"tornado",
            @"Spirograph": @"circle.circle",
            @"State": @"switch.2",
            @"Strobe": @"light.max",
            @"Tendril": @"leaf.arrow.circlepath",
            @"Text": @"textformat",
            @"Tree": @"tree.fill",
            @"Twinkle": @"sparkles",
            @"Video": @"video.fill",
            @"VUMeter": @"chart.bar.fill",
            @"Warp": @"arrow.up.and.down.and.arrow.left.and.right",
            @"Wave": @"water.waves"
        };
    });
    return sEffectIconMapping;
}

- (void)buildIconAtlas {
    self.iconAtlasMap = [NSMutableDictionary dictionary];
    _nextIconIndex = 0;

    // Create texture descriptor
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                     width:kIconAtlasSize
                                    height:kIconAtlasSize
                                 mipmapped:NO];
    texDesc.usage = MTLTextureUsageShaderRead;
    _iconAtlasTexture = [_device newTextureWithDescriptor:texDesc];
    [_iconAtlasTexture setLabel:@"IconAtlas"];

    // Create a bitmap context to draw icons into
    NSInteger bytesPerRow = kIconAtlasSize * 4;
    NSMutableData *atlasData = [NSMutableData dataWithLength:kIconAtlasSize * bytesPerRow];
    unsigned char *pixels = (unsigned char *)atlasData.mutableBytes;

    // Clear to transparent
    memset(pixels, 0, atlasData.length);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels,
                                              kIconAtlasSize, kIconAtlasSize,
                                              8, bytesPerRow,
                                              colorSpace,
                                              kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);

    if (!ctx) {
        NSLog(@"XLEffectsGridRenderer: Failed to create icon atlas context");
        return;
    }

    // Flip context for correct orientation
    CGContextTranslateCTM(ctx, 0, kIconAtlasSize);
    CGContextScaleCTM(ctx, 1.0, -1.0);

    NSDictionary<NSString *, NSString *> *iconMapping = [XLEffectsGridRenderer effectIconMapping];

    // Render each icon into the atlas
    for (NSString *effectType in iconMapping) {
        NSString *symbolName = iconMapping[effectType];
        NSImage *symbol = [NSImage imageWithSystemSymbolName:symbolName
                                    accessibilityDescription:effectType];
        if (!symbol) {
            symbol = [NSImage imageWithSystemSymbolName:@"questionmark.square.fill"
                                accessibilityDescription:@"Unknown"];
        }

        // Configure symbol for white color at the cell size (larger for Retina quality)
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration
            configurationWithPointSize:kIconCellSize * 0.7
                                weight:NSFontWeightMedium];
        config = [config configurationByApplyingConfiguration:
                  [NSImageSymbolConfiguration configurationWithPaletteColors:@[[NSColor whiteColor]]]];
        NSImage *configuredSymbol = [symbol imageWithSymbolConfiguration:config];

        // Calculate position in atlas
        NSInteger atlasIndex = _nextIconIndex;
        NSInteger col = atlasIndex % kIconsPerRow;
        NSInteger row = atlasIndex / kIconsPerRow;
        CGFloat x = col * kIconCellSize;
        CGFloat y = row * kIconCellSize;

        // Draw the symbol centered in its cell
        NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:gc];

        NSSize symbolSize = configuredSymbol.size;
        CGFloat drawX = x + (kIconCellSize - symbolSize.width) / 2.0;
        CGFloat drawY = y + (kIconCellSize - symbolSize.height) / 2.0;
        [configuredSymbol drawAtPoint:NSMakePoint(drawX, drawY)
                             fromRect:NSZeroRect
                            operation:NSCompositingOperationSourceOver
                             fraction:1.0];

        [NSGraphicsContext restoreGraphicsState];

        // Store mapping
        self.iconAtlasMap[effectType] = @(atlasIndex);
        _nextIconIndex++;

        // Safety check
        if (_nextIconIndex >= kIconsPerRow * kIconsPerRow) {
            NSLog(@"XLEffectsGridRenderer: Icon atlas full, stopping at %ld icons", (long)_nextIconIndex);
            break;
        }
    }

    CGContextRelease(ctx);

    // Upload to Metal texture
    MTLRegion region = MTLRegionMake2D(0, 0, kIconAtlasSize, kIconAtlasSize);
    [_iconAtlasTexture replaceRegion:region
                         mipmapLevel:0
                           withBytes:pixels
                         bytesPerRow:bytesPerRow];

    NSLog(@"XLEffectsGridRenderer: Built icon atlas with %ld icons", (long)_nextIconIndex);
}

- (NSInteger)atlasIndexForEffectType:(const char *)effectTypeName {
    if (!effectTypeName || effectTypeName[0] == '\0') return -1;
    if (!self.iconAtlasMap) return -1;

    NSString *key = [NSString stringWithUTF8String:effectTypeName];
    if (!key) return -1;

    NSNumber *indexNum = self.iconAtlasMap[key];
    if (indexNum) {
        return indexNum.integerValue;
    }
    return -1;  // Unknown effect type
}

- (void)getUVsForAtlasIndex:(NSInteger)atlasIndex
                      uvMin:(simd_float2 *)outUVMin
                      uvMax:(simd_float2 *)outUVMax
{
    if (atlasIndex < 0) {
        *outUVMin = simd_make_float2(0, 0);
        *outUVMax = simd_make_float2(0, 0);
        return;
    }

    NSInteger col = atlasIndex % kIconsPerRow;
    NSInteger row = atlasIndex / kIconsPerRow;

    CGFloat cellUVSize = (CGFloat)kIconCellSize / (CGFloat)kIconAtlasSize;
    CGFloat u0 = col * cellUVSize;
    CGFloat v0 = row * cellUVSize;
    CGFloat u1 = u0 + cellUVSize;
    CGFloat v1 = v0 + cellUVSize;

    *outUVMin = simd_make_float2(u0, v0);
    *outUVMax = simd_make_float2(u1, v1);
}

- (void)drawIconsWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                    uniforms:(EffectsGridUniforms)uniforms
                      params:(XLGridFrameParams)fp
                 bufferIndex:(NSInteger)bufferIndex
                     effects:(const XLEffectRenderInfo *)effects
                 effectCount:(NSUInteger)effectCount
{
    if (!_iconAtlasTexture || !self.iconAtlasMap || !effects || effectCount == 0) return;

    CGSize viewSize = fp.viewSize;
    CGPoint scrollOffset = fp.scrollOffset;
    CGFloat zoomLevel = fp.zoomLevel;
    CGFloat rowHeight = fp.rowHeight;

    // Write to triple-buffered icon buffer
    id<MTLBuffer> iconBuffer = _iconBuffers[bufferIndex];
    if (!iconBuffer) return;
    TexturedVertex *vertices = (TexturedVertex *)iconBuffer.contents;
    if (!vertices) return;
    NSUInteger vertexCount = 0;
    NSUInteger maxVertices = kIconBufferSize / sizeof(TexturedVertex);

    CGFloat msPerPixel = 1.0 / zoomLevel;
    CGFloat visibleStartMS = scrollOffset.x * msPerPixel;
    CGFloat visibleEndMS = visibleStartMS + viewSize.width * msPerPixel;
    CGFloat visibleStartRow = scrollOffset.y / rowHeight;
    CGFloat visibleEndRow = (scrollOffset.y + viewSize.height) / rowHeight;

    CGFloat minWidthForIcons = 48.0;  // Minimum effect width to show icon
    CGFloat iconSize = 36.0;          // Icon size in pixels

    for (NSUInteger ei = 0; ei < effectCount; ei++) {
        XLEffectRenderInfo info = effects[ei];

        // No icons for timing marks
        if (info.isTimingMark) continue;

        // Frustum culling
        if (info.endTimeMS < visibleStartMS || info.startTimeMS > visibleEndMS) continue;
        if (info.row < (NSInteger)floor(visibleStartRow) - 1 ||
            info.row > (NSInteger)ceil(visibleEndRow) + 1) continue;

        CGFloat x1 = info.startTimeMS * zoomLevel - scrollOffset.x;
        CGFloat x2 = info.endTimeMS * zoomLevel - scrollOffset.x;
        CGFloat effectWidth = x2 - x1;

        // Skip if effect is too narrow for an icon
        if (effectWidth < minWidthForIcons) continue;

        // Get atlas index for this effect type
        NSInteger atlasIndex = [self atlasIndexForEffectType:info.effectTypeName];
        if (atlasIndex < 0) continue;

        // Get UVs for this icon
        simd_float2 uvMin, uvMax;
        [self getUVsForAtlasIndex:atlasIndex uvMin:&uvMin uvMax:&uvMax];

        // Calculate icon position (centered in effect block)
        CGFloat y1 = info.row * rowHeight - scrollOffset.y;
        CGFloat centerX = (x1 + x2) / 2.0;
        CGFloat centerY = y1 + rowHeight / 2.0;

        CGFloat halfIcon = iconSize / 2.0;
        CGFloat ix0 = centerX - halfIcon;
        CGFloat iy0 = centerY - halfIcon;
        CGFloat ix1 = centerX + halfIcon;
        CGFloat iy1 = centerY + halfIcon;

        // Check buffer capacity (6 vertices per icon quad)
        if (vertexCount + 6 > maxVertices) break;

        // Two triangles forming the icon quad (UV Y flipped for correct orientation)
        vertices[vertexCount++] = (TexturedVertex){ simd_make_float2(ix0, iy0), simd_make_float2(uvMin.x, uvMax.y) };
        vertices[vertexCount++] = (TexturedVertex){ simd_make_float2(ix1, iy0), simd_make_float2(uvMax.x, uvMax.y) };
        vertices[vertexCount++] = (TexturedVertex){ simd_make_float2(ix0, iy1), simd_make_float2(uvMin.x, uvMin.y) };
        vertices[vertexCount++] = (TexturedVertex){ simd_make_float2(ix1, iy0), simd_make_float2(uvMax.x, uvMax.y) };
        vertices[vertexCount++] = (TexturedVertex){ simd_make_float2(ix1, iy1), simd_make_float2(uvMax.x, uvMin.y) };
        vertices[vertexCount++] = (TexturedVertex){ simd_make_float2(ix0, iy1), simd_make_float2(uvMin.x, uvMin.y) };
    }

    if (vertexCount == 0) return;

    [encoder setRenderPipelineState:_iconPipeline];
    [encoder setVertexBuffer:iconBuffer offset:0 atIndex:0];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder setFragmentTexture:_iconAtlasTexture atIndex:0];
    [encoder setFragmentSamplerState:_iconSampler atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertexCount];
}

@end
