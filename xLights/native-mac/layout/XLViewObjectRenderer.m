/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLViewObjectRenderer.h"
#import "XLViewObject.h"
#import <AppKit/AppKit.h>

#pragma mark - Vertex Structures

typedef struct {
    simd_float3 position;
    simd_float4 color;
} XLVOLineVertex;

typedef struct {
    simd_float3 position;
    simd_float2 texCoord;
} XLVOTexturedVertex;

typedef struct {
    simd_float4x4 viewProjection;
} XLVOUniforms;

typedef struct {
    simd_float4x4 viewProjection;
    float brightness;
    float alpha;
    float _pad0;
    float _pad1;
} XLVOImageUniforms;

#pragma mark - Per-Object Render State

@interface XLViewObjectRenderState : NSObject
@property (nonatomic, strong) XLViewObject *object;
@property (nonatomic, assign) BOOL dirty;

// Gridlines
@property (nonatomic, strong, nullable) id<MTLBuffer> lineVertexBuffer;
@property (nonatomic, assign) NSUInteger lineVertexCount;

// Image
@property (nonatomic, strong, nullable) id<MTLTexture> texture;
@property (nonatomic, strong, nullable) id<MTLBuffer> quadVertexBuffer;
@end

@implementation XLViewObjectRenderState
- (instancetype)init {
    self = [super init];
    if (self) {
        _dirty = YES;
    }
    return self;
}
@end

#pragma mark - Renderer

@interface XLViewObjectRenderer ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, assign) NSUInteger sampleCount;

// Line pipeline (for gridlines) - same vertex format as the preview grid
@property (nonatomic, strong, nullable) id<MTLRenderPipelineState> linePipelineState;

// Textured pipeline (for image objects) - world-space textured quads
@property (nonatomic, strong, nullable) id<MTLRenderPipelineState> imagePipelineState;
@property (nonatomic, strong, nullable) id<MTLSamplerState> imageSamplerState;

// Per-object render state keyed by object name
@property (nonatomic, strong) NSMutableDictionary<NSString *, XLViewObjectRenderState *> *renderStates;
@end

@implementation XLViewObjectRenderer

- (instancetype)initWithDevice:(id<MTLDevice>)device sampleCount:(NSUInteger)sampleCount {
    self = [super init];
    if (self) {
        _device = device;
        _sampleCount = sampleCount;
        _renderStates = [NSMutableDictionary dictionary];

        [self buildLinePipeline];
        [self buildImagePipeline];
    }
    return self;
}

#pragma mark - Pipeline Setup

- (void)buildLinePipeline {
    NSError *error = nil;

    // Same shader as the grid pipeline in XLMetalPreviewView — position + color lines
    NSString *shaderSource = @
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "\n"
        "struct VOLineVertex {\n"
        "    float3 position [[attribute(0)]];\n"
        "    float4 color    [[attribute(1)]];\n"
        "};\n"
        "\n"
        "struct VOUniforms {\n"
        "    float4x4 viewProjection;\n"
        "};\n"
        "\n"
        "struct VOLineOut {\n"
        "    float4 position [[position]];\n"
        "    float4 color;\n"
        "};\n"
        "\n"
        "vertex VOLineOut voLineVertexShader(\n"
        "    VOLineVertex in [[stage_in]],\n"
        "    constant VOUniforms &uniforms [[buffer(1)]]) {\n"
        "    VOLineOut out;\n"
        "    out.position = uniforms.viewProjection * float4(in.position, 1.0);\n"
        "    out.color = in.color;\n"
        "    return out;\n"
        "}\n"
        "\n"
        "fragment float4 voLineFragmentShader(VOLineOut in [[stage_in]]) {\n"
        "    return in.color;\n"
        "}\n";

    id<MTLLibrary> library = [_device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"XLViewObjectRenderer: Failed to compile line shaders: %@", error);
        return;
    }

    MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
    vertexDesc.attributes[0].format = MTLVertexFormatFloat3;
    vertexDesc.attributes[0].offset = 0;
    vertexDesc.attributes[0].bufferIndex = 0;
    vertexDesc.attributes[1].format = MTLVertexFormatFloat4;
    vertexDesc.attributes[1].offset = sizeof(simd_float3);
    vertexDesc.attributes[1].bufferIndex = 0;
    vertexDesc.layouts[0].stride = sizeof(XLVOLineVertex);
    vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    MTLRenderPipelineDescriptor *pipeDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipeDesc.vertexFunction = [library newFunctionWithName:@"voLineVertexShader"];
    pipeDesc.fragmentFunction = [library newFunctionWithName:@"voLineFragmentShader"];
    pipeDesc.vertexDescriptor = vertexDesc;
    pipeDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipeDesc.colorAttachments[0].blendingEnabled = YES;
    pipeDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipeDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipeDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipeDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipeDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    pipeDesc.rasterSampleCount = _sampleCount;

    _linePipelineState = [_device newRenderPipelineStateWithDescriptor:pipeDesc error:&error];
    if (!_linePipelineState) {
        NSLog(@"XLViewObjectRenderer: Failed to create line pipeline: %@", error);
    }
}

- (void)buildImagePipeline {
    NSError *error = nil;

    // World-space textured quad shader with brightness and alpha uniforms
    NSString *shaderSource = @
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "\n"
        "struct VOTexVertex {\n"
        "    float3 position [[attribute(0)]];\n"
        "    float2 texCoord [[attribute(1)]];\n"
        "};\n"
        "\n"
        "struct VOImageUniforms {\n"
        "    float4x4 viewProjection;\n"
        "    float brightness;\n"
        "    float alpha;\n"
        "};\n"
        "\n"
        "struct VOTexOut {\n"
        "    float4 position [[position]];\n"
        "    float2 texCoord;\n"
        "};\n"
        "\n"
        "vertex VOTexOut voImageVertexShader(\n"
        "    VOTexVertex in [[stage_in]],\n"
        "    constant VOImageUniforms &uniforms [[buffer(1)]]) {\n"
        "    VOTexOut out;\n"
        "    out.position = uniforms.viewProjection * float4(in.position, 1.0);\n"
        "    out.texCoord = in.texCoord;\n"
        "    return out;\n"
        "}\n"
        "\n"
        "fragment float4 voImageFragmentShader(\n"
        "    VOTexOut in [[stage_in]],\n"
        "    texture2d<float> tex [[texture(0)]],\n"
        "    sampler smp [[sampler(0)]],\n"
        "    constant VOImageUniforms &uniforms [[buffer(0)]]) {\n"
        "    float4 texColor = tex.sample(smp, in.texCoord);\n"
        "    texColor.rgb *= uniforms.brightness;\n"
        "    texColor.a *= uniforms.alpha;\n"
        "    return texColor;\n"
        "}\n";

    id<MTLLibrary> library = [_device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"XLViewObjectRenderer: Failed to compile image shaders: %@", error);
        return;
    }

    MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
    vertexDesc.attributes[0].format = MTLVertexFormatFloat3;
    vertexDesc.attributes[0].offset = 0;
    vertexDesc.attributes[0].bufferIndex = 0;
    vertexDesc.attributes[1].format = MTLVertexFormatFloat2;
    vertexDesc.attributes[1].offset = sizeof(simd_float3);
    vertexDesc.attributes[1].bufferIndex = 0;
    vertexDesc.layouts[0].stride = sizeof(XLVOTexturedVertex);
    vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    MTLRenderPipelineDescriptor *pipeDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipeDesc.vertexFunction = [library newFunctionWithName:@"voImageVertexShader"];
    pipeDesc.fragmentFunction = [library newFunctionWithName:@"voImageFragmentShader"];
    pipeDesc.vertexDescriptor = vertexDesc;
    pipeDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipeDesc.colorAttachments[0].blendingEnabled = YES;
    pipeDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipeDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipeDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipeDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipeDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    pipeDesc.rasterSampleCount = _sampleCount;

    _imagePipelineState = [_device newRenderPipelineStateWithDescriptor:pipeDesc error:&error];
    if (!_imagePipelineState) {
        NSLog(@"XLViewObjectRenderer: Failed to create image pipeline: %@", error);
    }

    // Sampler state for image textures
    MTLSamplerDescriptor *samplerDesc = [[MTLSamplerDescriptor alloc] init];
    samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
    samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
    samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    _imageSamplerState = [_device newSamplerStateWithDescriptor:samplerDesc];
}

#pragma mark - Object Management

- (void)addOrUpdateObject:(XLViewObject *)object {
    XLViewObjectRenderState *state = _renderStates[object.name];
    if (!state) {
        state = [[XLViewObjectRenderState alloc] init];
    }
    state.object = object;
    state.dirty = YES;
    _renderStates[object.name] = state;
}

- (void)removeObjectWithName:(NSString *)name {
    [_renderStates removeObjectForKey:name];
}

- (void)removeAllObjects {
    [_renderStates removeAllObjects];
}

- (NSArray<NSString *> *)objectNames {
    return [_renderStates allKeys];
}

- (nullable XLViewObject *)objectWithName:(NSString *)name {
    return _renderStates[name].object;
}

- (void)invalidateObject:(NSString *)name {
    _renderStates[name].dirty = YES;
}

- (void)invalidateAll {
    for (XLViewObjectRenderState *state in _renderStates.allValues) {
        state.dirty = YES;
    }
}

#pragma mark - Rendering

- (void)renderWithEncoder:(id<MTLRenderCommandEncoder>)encoder
           viewProjection:(simd_float4x4)viewProjection {
    for (XLViewObjectRenderState *state in _renderStates.allValues) {
        if (!state.object.active) continue;

        if (state.dirty) {
            [self rebuildState:state];
        }

        switch (state.object.objectType) {
            case XLViewObjectTypeGridlines:
                [self renderGridlines:state encoder:encoder viewProjection:viewProjection];
                break;

            case XLViewObjectTypeImage:
                [self renderImage:state encoder:encoder viewProjection:viewProjection];
                break;

            default:
                break;
        }
    }
}

#pragma mark - Rebuild Metal Resources

- (void)rebuildState:(XLViewObjectRenderState *)state {
    switch (state.object.objectType) {
        case XLViewObjectTypeGridlines:
            [self rebuildGridlines:state];
            break;

        case XLViewObjectTypeImage:
            [self rebuildImage:state];
            break;

        default:
            break;
    }
    state.dirty = NO;
}

- (void)rebuildGridlines:(XLViewObjectRenderState *)state {
    XLViewObject *obj = state.object;

    NSInteger lineSpacing = obj.gridLineSpacing > 0 ? obj.gridLineSpacing : 50;
    float halfWidth = (float)obj.gridWidth / 2.0f;
    float halfHeight = (float)obj.gridHeight / 2.0f;
    simd_float4 color = obj.gridColor;
    simd_float3 pos = obj.position;

    NSMutableData *vertexData = [[NSMutableData alloc] init];

    simd_float4 xAxisColor = simd_make_float4(0.5f, 0.0f, 0.0f, 1.0f);
    simd_float4 yAxisColor = simd_make_float4(0.0f, 0.0f, 0.5f, 1.0f);

    // Horizontal lines (along X axis)
    for (float y = -halfHeight; y <= halfHeight; y += lineSpacing) {
        simd_float4 lineColor = color;
        if (obj.gridShowAxis && fabsf(y) < 0.01f) {
            lineColor = xAxisColor;
        }

        XLVOLineVertex v0 = {
            .position = { pos.x - halfWidth, pos.y + y, pos.z },
            .color = lineColor
        };
        XLVOLineVertex v1 = {
            .position = { pos.x + halfWidth, pos.y + y, pos.z },
            .color = lineColor
        };
        [vertexData appendBytes:&v0 length:sizeof(XLVOLineVertex)];
        [vertexData appendBytes:&v1 length:sizeof(XLVOLineVertex)];
    }

    // Vertical lines (along Y axis)
    for (float x = -halfWidth; x <= halfWidth; x += lineSpacing) {
        simd_float4 lineColor = color;
        if (obj.gridShowAxis && fabsf(x) < 0.01f) {
            lineColor = yAxisColor;
        }

        XLVOLineVertex v0 = {
            .position = { pos.x + x, pos.y - halfHeight, pos.z },
            .color = lineColor
        };
        XLVOLineVertex v1 = {
            .position = { pos.x + x, pos.y + halfHeight, pos.z },
            .color = lineColor
        };
        [vertexData appendBytes:&v0 length:sizeof(XLVOLineVertex)];
        [vertexData appendBytes:&v1 length:sizeof(XLVOLineVertex)];
    }

    state.lineVertexCount = vertexData.length / sizeof(XLVOLineVertex);
    if (state.lineVertexCount > 0) {
        state.lineVertexBuffer = [_device newBufferWithBytes:vertexData.bytes
                                                      length:vertexData.length
                                                     options:MTLResourceStorageModeShared];
        [state.lineVertexBuffer setLabel:[NSString stringWithFormat:@"ViewObject_%@_Grid", obj.name]];
    } else {
        state.lineVertexBuffer = nil;
    }
}

- (void)rebuildImage:(XLViewObjectRenderState *)state {
    XLViewObject *obj = state.object;

    // Load texture if we have a path and no texture yet
    if (obj.imagePath && obj.imagePath.length > 0 && !state.texture) {
        [self loadTextureForState:state fromPath:obj.imagePath];
    }

    // Build quad vertices in world space
    float w = (float)obj.imageWidth;
    float h = (float)obj.imageHeight;

    // If we don't have valid image dimensions, use a default placeholder size
    if (w <= 0 || h <= 0) {
        w = 100.0f;
        h = 100.0f;
    }

    // Apply scale
    float sw = w * obj.scale.x;
    float sh = h * obj.scale.y;

    float halfW = sw / 2.0f;
    float halfH = sh / 2.0f;
    simd_float3 pos = obj.position;

    // Simple axis-aligned quad (rotation not applied in vertex data for now)
    XLVOTexturedVertex quad[6] = {
        { .position = { pos.x - halfW, pos.y - halfH, pos.z }, .texCoord = { 0.0f, 1.0f } },
        { .position = { pos.x + halfW, pos.y - halfH, pos.z }, .texCoord = { 1.0f, 1.0f } },
        { .position = { pos.x - halfW, pos.y + halfH, pos.z }, .texCoord = { 0.0f, 0.0f } },

        { .position = { pos.x - halfW, pos.y + halfH, pos.z }, .texCoord = { 0.0f, 0.0f } },
        { .position = { pos.x + halfW, pos.y - halfH, pos.z }, .texCoord = { 1.0f, 1.0f } },
        { .position = { pos.x + halfW, pos.y + halfH, pos.z }, .texCoord = { 1.0f, 0.0f } },
    };

    state.quadVertexBuffer = [_device newBufferWithBytes:quad
                                                   length:sizeof(quad)
                                                  options:MTLResourceStorageModeShared];
    [state.quadVertexBuffer setLabel:[NSString stringWithFormat:@"ViewObject_%@_Quad", obj.name]];
}

- (void)loadTextureForState:(XLViewObjectRenderState *)state fromPath:(NSString *)path {
    NSImage *nsImage = [[NSImage alloc] initWithContentsOfFile:path];
    if (!nsImage) {
        NSLog(@"XLViewObjectRenderer: Failed to load image: %@", path);
        return;
    }

    // Get the bitmap representation
    NSBitmapImageRep *bitmapRep = nil;
    for (NSImageRep *rep in nsImage.representations) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            bitmapRep = (NSBitmapImageRep *)rep;
            break;
        }
    }

    if (!bitmapRep) {
        CGSize size = nsImage.size;
        NSUInteger w = (NSUInteger)size.width;
        NSUInteger h = (NSUInteger)size.height;
        if (w == 0 || h == 0) return;

        bitmapRep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL
                          pixelsWide:w
                          pixelsHigh:h
                       bitsPerSample:8
                     samplesPerPixel:4
                            hasAlpha:YES
                            isPlanar:NO
                      colorSpaceName:NSCalibratedRGBColorSpace
                        bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
                         bytesPerRow:w * 4
                        bitsPerPixel:32];

        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmapRep];
        [NSGraphicsContext setCurrentContext:ctx];
        [nsImage drawInRect:NSMakeRect(0, 0, w, h)
                   fromRect:NSZeroRect
                  operation:NSCompositingOperationSourceOver
                   fraction:1.0];
        [NSGraphicsContext restoreGraphicsState];
    }

    NSUInteger w = bitmapRep.pixelsWide;
    NSUInteger h = bitmapRep.pixelsHigh;
    if (w == 0 || h == 0) return;

    // Update the object's image dimensions
    state.object.imageWidth = (NSInteger)w;
    state.object.imageHeight = (NSInteger)h;

    // Create Metal texture from bitmap data
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                       width:w
                                                                                      height:h
                                                                                   mipmapped:NO];
    texDesc.usage = MTLTextureUsageShaderRead;
    texDesc.storageMode = MTLStorageModeShared;

    id<MTLTexture> texture = [_device newTextureWithDescriptor:texDesc];
    if (!texture) {
        NSLog(@"XLViewObjectRenderer: Failed to create texture for %@", path);
        return;
    }
    [texture setLabel:[NSString stringWithFormat:@"ViewObject_%@_Tex", state.object.name]];

    // Convert to RGBA8
    NSUInteger bytesPerRow = w * 4;
    NSMutableData *rgbaData = [[NSMutableData alloc] initWithLength:h * bytesPerRow];
    uint8_t *dst = (uint8_t *)rgbaData.mutableBytes;

    for (NSUInteger y = 0; y < h; y++) {
        for (NSUInteger x = 0; x < w; x++) {
            NSColor *pixel = [bitmapRep colorAtX:x y:y];
            NSColor *rgbPixel = [pixel colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];

            NSUInteger idx = (y * w + x) * 4;
            if (rgbPixel) {
                CGFloat cr, cg, cb, ca;
                [rgbPixel getRed:&cr green:&cg blue:&cb alpha:&ca];
                dst[idx + 0] = (uint8_t)(cr * 255.0);
                dst[idx + 1] = (uint8_t)(cg * 255.0);
                dst[idx + 2] = (uint8_t)(cb * 255.0);
                dst[idx + 3] = (uint8_t)(ca * 255.0);
            } else {
                dst[idx + 0] = 0;
                dst[idx + 1] = 0;
                dst[idx + 2] = 0;
                dst[idx + 3] = 255;
            }
        }
    }

    MTLRegion region = MTLRegionMake2D(0, 0, w, h);
    [texture replaceRegion:region mipmapLevel:0 withBytes:dst bytesPerRow:bytesPerRow];

    state.texture = texture;
    NSLog(@"XLViewObjectRenderer: Loaded image %lux%lu from %@", (unsigned long)w, (unsigned long)h, path);
}

#pragma mark - Draw Calls

- (void)renderGridlines:(XLViewObjectRenderState *)state
                encoder:(id<MTLRenderCommandEncoder>)encoder
         viewProjection:(simd_float4x4)viewProjection {
    if (!state.lineVertexBuffer || state.lineVertexCount == 0 || !_linePipelineState) return;

    [encoder pushDebugGroup:[NSString stringWithFormat:@"ViewObject_Grid_%@", state.object.name]];
    [encoder setRenderPipelineState:_linePipelineState];
    [encoder setVertexBuffer:state.lineVertexBuffer offset:0 atIndex:0];

    XLVOUniforms uniforms;
    uniforms.viewProjection = viewProjection;
    [encoder setVertexBytes:&uniforms length:sizeof(XLVOUniforms) atIndex:1];

    [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:state.lineVertexCount];
    [encoder popDebugGroup];
}

- (void)renderImage:(XLViewObjectRenderState *)state
            encoder:(id<MTLRenderCommandEncoder>)encoder
     viewProjection:(simd_float4x4)viewProjection {
    if (!state.quadVertexBuffer || !_imagePipelineState) return;

    // If we have a texture, draw the textured quad
    if (state.texture) {
        [encoder pushDebugGroup:[NSString stringWithFormat:@"ViewObject_Image_%@", state.object.name]];
        [encoder setRenderPipelineState:_imagePipelineState];
        [encoder setVertexBuffer:state.quadVertexBuffer offset:0 atIndex:0];

        XLVOImageUniforms uniforms;
        uniforms.viewProjection = viewProjection;
        uniforms.brightness = (float)state.object.brightness / 100.0f;
        uniforms.alpha = (100.0f - (float)state.object.transparency) / 100.0f;
        [encoder setVertexBytes:&uniforms length:sizeof(XLVOImageUniforms) atIndex:1];
        [encoder setFragmentBytes:&uniforms length:sizeof(XLVOImageUniforms) atIndex:0];
        [encoder setFragmentTexture:state.texture atIndex:0];
        [encoder setFragmentSamplerState:_imageSamplerState atIndex:0];

        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        [encoder popDebugGroup];
    } else {
        // Draw a red outline placeholder (no texture loaded)
        [self renderImagePlaceholder:state encoder:encoder viewProjection:viewProjection];
    }
}

- (void)renderImagePlaceholder:(XLViewObjectRenderState *)state
                       encoder:(id<MTLRenderCommandEncoder>)encoder
                viewProjection:(simd_float4x4)viewProjection {
    if (!_linePipelineState) return;

    XLViewObject *obj = state.object;
    float w = obj.imageWidth > 0 ? (float)obj.imageWidth : 100.0f;
    float h = obj.imageHeight > 0 ? (float)obj.imageHeight : 100.0f;
    float sw = w * obj.scale.x;
    float sh = h * obj.scale.y;
    float halfW = sw / 2.0f;
    float halfH = sh / 2.0f;
    simd_float3 pos = obj.position;

    simd_float4 red = simd_make_float4(1.0f, 0.0f, 0.0f, 1.0f);

    // Outline + X cross for placeholder
    XLVOLineVertex placeholder[12] = {
        // Outline
        { .position = { pos.x - halfW, pos.y - halfH, pos.z }, .color = red },
        { .position = { pos.x + halfW, pos.y - halfH, pos.z }, .color = red },
        { .position = { pos.x + halfW, pos.y - halfH, pos.z }, .color = red },
        { .position = { pos.x + halfW, pos.y + halfH, pos.z }, .color = red },
        { .position = { pos.x + halfW, pos.y + halfH, pos.z }, .color = red },
        { .position = { pos.x - halfW, pos.y + halfH, pos.z }, .color = red },
        { .position = { pos.x - halfW, pos.y + halfH, pos.z }, .color = red },
        { .position = { pos.x - halfW, pos.y - halfH, pos.z }, .color = red },
        // X cross
        { .position = { pos.x - halfW, pos.y - halfH, pos.z }, .color = red },
        { .position = { pos.x + halfW, pos.y + halfH, pos.z }, .color = red },
        { .position = { pos.x + halfW, pos.y - halfH, pos.z }, .color = red },
        { .position = { pos.x - halfW, pos.y + halfH, pos.z }, .color = red },
    };

    id<MTLBuffer> placeholderBuffer = [_device newBufferWithBytes:placeholder
                                                            length:sizeof(placeholder)
                                                           options:MTLResourceStorageModeShared];
    [placeholderBuffer setLabel:@"ViewObject_ImagePlaceholder"];

    [encoder pushDebugGroup:[NSString stringWithFormat:@"ViewObject_ImagePlaceholder_%@", obj.name]];
    [encoder setRenderPipelineState:_linePipelineState];
    [encoder setVertexBuffer:placeholderBuffer offset:0 atIndex:0];

    XLVOUniforms uniforms;
    uniforms.viewProjection = viewProjection;
    [encoder setVertexBytes:&uniforms length:sizeof(XLVOUniforms) atIndex:1];

    [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:12];
    [encoder popDebugGroup];
}

@end
