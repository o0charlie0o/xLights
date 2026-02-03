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

    // Load shaders from the default library
    id<MTLLibrary> library = [_device newDefaultLibrary];
    if (!library) {
        // Try loading from a compiled metallib file or source
        NSString *shaderPath = [[NSBundle mainBundle] pathForResource:@"XLEffectsGridShaders"
                                                              ofType:@"metal"];
        if (shaderPath) {
            NSString *source = [NSString stringWithContentsOfFile:shaderPath
                                                        encoding:NSUTF8StringEncoding
                                                           error:&error];
            if (source) {
                MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
                library = [_device newLibraryWithSource:source options:options error:&error];
            }
        }
        if (!library) {
            NSLog(@"XLEffectsGridRenderer: Could not load shader library: %@", error);
            return NO;
        }
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
            effects:(NSArray<NSValue *> *)effects
   selectedEffectID:(NSInteger)selectedEffectID
 playbackPositionMS:(CGFloat)playbackPositionMS
      timingMarksMS:(NSArray<NSNumber *> *)timingMarksMS
{
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (!drawable) return;

    MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.colorAttachments[0].texture = drawable.texture;
    passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    // Dark background matching Logic Pro X style
    passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.118, 0.118, 0.118, 1.0);

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];

    EffectsGridUniforms uniforms;
    uniforms.viewportSize = simd_make_float2(viewSize.width, viewSize.height);
    uniforms.scrollOffset = simd_make_float2(scrollOffset.x, scrollOffset.y);
    uniforms.zoomLevel = (float)zoomLevel;
    uniforms.rowHeight = (float)rowHeight;
    uniforms.padding0 = 0;
    uniforms.padding1 = 0;

    // Draw grid lines
    [self drawGridLinesWithEncoder:encoder
                          uniforms:uniforms
                          viewSize:viewSize
                      scrollOffset:scrollOffset
                         zoomLevel:zoomLevel
                         rowHeight:rowHeight
                         totalRows:totalRows
                  sequenceLengthMS:sequenceLengthMS
                     timingMarksMS:timingMarksMS];

    // Draw effect blocks
    [self drawEffectBlocksWithEncoder:encoder
                             uniforms:uniforms
                             viewSize:viewSize
                         scrollOffset:scrollOffset
                            zoomLevel:zoomLevel
                            rowHeight:rowHeight
                              effects:effects
                     selectedEffectID:selectedEffectID];

    // Draw playback position indicator
    [self drawPlaybackIndicatorWithEncoder:encoder
                                  uniforms:uniforms
                                  viewSize:viewSize
                              scrollOffset:scrollOffset
                                 zoomLevel:zoomLevel
                        playbackPositionMS:playbackPositionMS];

    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

#pragma mark - Grid Lines

- (void)drawGridLinesWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                        uniforms:(EffectsGridUniforms)uniforms
                        viewSize:(CGSize)viewSize
                    scrollOffset:(CGPoint)scrollOffset
                       zoomLevel:(CGFloat)zoomLevel
                       rowHeight:(CGFloat)rowHeight
                       totalRows:(NSInteger)totalRows
                sequenceLengthMS:(CGFloat)sequenceLengthMS
                   timingMarksMS:(NSArray<NSNumber *> *)timingMarksMS
{
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
    // Calculate appropriate time grid spacing based on zoom level
    CGFloat msPerPixel = 1.0 / zoomLevel;
    CGFloat visibleMS = viewSize.width * msPerPixel;

    // Choose grid interval: 100ms, 250ms, 500ms, 1s, 5s, 10s, 30s, 60s
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
    simd_float4 timingColor = simd_make_float4(0.4, 0.6, 0.4, 0.6);
    for (NSNumber *markMS in timingMarksMS) {
        CGFloat t = markMS.doubleValue;
        CGFloat x = t * zoomLevel - scrollOffset.x;
        if (x < -1 || x > viewSize.width + 1) continue;

        SimpleVertex v0 = { simd_make_float2(x, 0), timingColor };
        SimpleVertex v1 = { simd_make_float2(x, viewSize.height), timingColor };
        [vertexData appendBytes:&v0 length:sizeof(SimpleVertex)];
        [vertexData appendBytes:&v1 length:sizeof(SimpleVertex)];
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
                           viewSize:(CGSize)viewSize
                       scrollOffset:(CGPoint)scrollOffset
                          zoomLevel:(CGFloat)zoomLevel
                          rowHeight:(CGFloat)rowHeight
                            effects:(NSArray<NSValue *> *)effects
                   selectedEffectID:(NSInteger)selectedEffectID
{
    if (effects.count == 0) return;

    NSMutableData *blockVertexData = [NSMutableData data];
    NSMutableData *outlineVertexData = [NSMutableData data];

    CGFloat msPerPixel = 1.0 / zoomLevel;
    CGFloat visibleStartMS = scrollOffset.x * msPerPixel;
    CGFloat visibleEndMS = visibleStartMS + viewSize.width * msPerPixel;
    CGFloat visibleStartRow = scrollOffset.y / rowHeight;
    CGFloat visibleEndRow = (scrollOffset.y + viewSize.height) / rowHeight;

    for (NSValue *effectValue in effects) {
        XLEffectRenderInfo info;
        [effectValue getValue:&info];

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
        if (info.color) {
            CGFloat r, g, b, a;
            NSColor *rgbColor = [info.color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            [rgbColor getRed:&r green:&g blue:&b alpha:&a];
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
                                viewSize:(CGSize)viewSize
                            scrollOffset:(CGPoint)scrollOffset
                               zoomLevel:(CGFloat)zoomLevel
                      playbackPositionMS:(CGFloat)playbackPositionMS
{
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

- (simd_float4)simdColorForEffectIndex:(NSInteger)effectIndex {
    NSColor *c = [XLEffectsGridRenderer colorForEffectIndex:effectIndex];
    CGFloat r, g, b, a;
    NSColor *rgbColor = [c colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    [rgbColor getRed:&r green:&g blue:&b alpha:&a];
    return simd_make_float4(r, g, b, a);
}

+ (NSColor *)colorForEffectIndex:(NSInteger)effectIndex {
    // Effect color palette (matches existing xLights effect coloring conventions)
    static NSArray<NSColor *> *palette = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        palette = @[
            [NSColor colorWithRed:0.30 green:0.55 blue:0.85 alpha:0.85], // Bars (blue)
            [NSColor colorWithRed:0.85 green:0.50 blue:0.20 alpha:0.85], // Butterfly (orange)
            [NSColor colorWithRed:0.90 green:0.35 blue:0.25 alpha:0.85], // Candle (red-orange)
            [NSColor colorWithRed:0.40 green:0.70 blue:0.40 alpha:0.85], // Circles (green)
            [NSColor colorWithRed:0.55 green:0.35 blue:0.75 alpha:0.85], // ColorWash (purple)
            [NSColor colorWithRed:0.75 green:0.45 blue:0.55 alpha:0.85], // Curtain (mauve)
            [NSColor colorWithRed:0.35 green:0.65 blue:0.65 alpha:0.85], // DMX (teal)
            [NSColor colorWithRed:0.80 green:0.60 blue:0.30 alpha:0.85], // Faces (gold)
            [NSColor colorWithRed:0.45 green:0.55 blue:0.30 alpha:0.85], // Fan (olive)
            [NSColor colorWithRed:0.70 green:0.55 blue:0.65 alpha:0.85], // Fill (pink)
            [NSColor colorWithRed:0.85 green:0.30 blue:0.20 alpha:0.85], // Fire (red)
            [NSColor colorWithRed:0.90 green:0.45 blue:0.30 alpha:0.85], // Fireworks (orange-red)
            [NSColor colorWithRed:0.35 green:0.55 blue:0.45 alpha:0.85], // Galaxy (dark green)
            [NSColor colorWithRed:0.55 green:0.75 blue:0.35 alpha:0.85], // Garlands (lime)
            [NSColor colorWithRed:0.50 green:0.40 blue:0.60 alpha:0.85], // Glediator (dark purple)
            [NSColor colorWithRed:0.40 green:0.65 blue:0.80 alpha:0.85], // Kaleidoscope (sky blue)
            [NSColor colorWithRed:0.50 green:0.65 blue:0.35 alpha:0.85], // Life (green)
            [NSColor colorWithRed:0.70 green:0.70 blue:0.35 alpha:0.85], // Lightning (yellow)
            [NSColor colorWithRed:0.45 green:0.45 blue:0.65 alpha:0.85], // Lines (slate)
            [NSColor colorWithRed:0.55 green:0.55 blue:0.55 alpha:0.85], // Liquid (gray)
            [NSColor colorWithRed:0.65 green:0.35 blue:0.55 alpha:0.85], // Marquee (magenta)
            [NSColor colorWithRed:0.80 green:0.55 blue:0.30 alpha:0.85], // Meteors (amber)
            [NSColor colorWithRed:0.60 green:0.40 blue:0.50 alpha:0.85], // Morph (rose)
            [NSColor colorWithRed:0.45 green:0.55 blue:0.75 alpha:0.85], // Music (periwinkle)
            [NSColor colorWithRed:0.30 green:0.30 blue:0.30 alpha:0.85], // Off (dark gray)
            [NSColor colorWithRed:0.85 green:0.85 blue:0.50 alpha:0.85], // On (yellow)
            [NSColor colorWithRed:0.65 green:0.50 blue:0.40 alpha:0.85], // Pictures (brown)
            [NSColor colorWithRed:0.40 green:0.60 blue:0.60 alpha:0.85], // Pinwheel (cyan)
            [NSColor colorWithRed:0.55 green:0.45 blue:0.70 alpha:0.85], // Plasma (violet)
            [NSColor colorWithRed:0.65 green:0.40 blue:0.40 alpha:0.85], // Ripple (rust)
        ];
    });

    NSInteger idx = effectIndex % (NSInteger)palette.count;
    if (idx < 0) idx = 0;
    return palette[idx];
}

@end
