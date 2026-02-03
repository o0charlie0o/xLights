/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLMetalPreviewView.h"
#import "XLCameraController.h"
#import "XLManipulationHandlesRenderer.h"
#import "../XLEngineBridge.h"
#import <QuartzCore/CVDisplayLink.h>

static const NSUInteger kDefaultMSAASampleCount = 4;
static const NSInteger kGridLineCount = 41; // -20 to +20, step 1
static const float kGridSpacing = 50.0f;
static const float kGridExtent = 1000.0f;

#pragma mark - Grid Vertex Structures

typedef struct {
    simd_float3 position;
    simd_float4 color;
} XLGridVertex;

#pragma mark - CVDisplayLink Callback

// Forward declaration for the C callback
@interface XLMetalPreviewView (DisplayLinkPrivate)
- (void)displayLinkFired:(const CVTimeStamp *)outputTime;
@end

static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                    const CVTimeStamp *inNow,
                                    const CVTimeStamp *inOutputTime,
                                    CVOptionFlags flagsIn,
                                    CVOptionFlags *flagsOut,
                                    void *displayLinkContext) {
    @autoreleasepool {
        XLMetalPreviewView *view = (__bridge XLMetalPreviewView *)displayLinkContext;
        [view displayLinkFired:inOutputTime];
    }
    return kCVReturnSuccess;
}

@interface XLMetalPreviewView () {
    CVDisplayLinkRef _displayLink;
}

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> queue;
@property (nonatomic, strong) CAMetalLayer *mlayer;
@property (nonatomic, assign) BOOL renderLoopRunning;
@property (nonatomic, assign) BOOL needsRenderFlag;
@property (nonatomic, assign) BOOL contentDirty;

@property (nonatomic, strong) id<MTLRenderPipelineState> gridPipelineState;
@property (nonatomic, strong) id<MTLBuffer> gridVertexBuffer;
@property (nonatomic, assign) NSUInteger gridVertexCount;

@property (nonatomic, strong) id<MTLTexture> msaaTexture;
@property (nonatomic, strong) id<MTLTexture> depthTexture;
@property (nonatomic, assign) CGSize lastDrawableSize;

@property (nonatomic, strong) id<MTLDepthStencilState> depthStencilState;

@property (nonatomic, strong) NSString *highlightedModelName;

// Model data cache from engine bridge
@property (nonatomic, strong) NSArray<NSDictionary *> *modelDataCache;
@property (nonatomic, strong) id<MTLBuffer> modelVertexBuffer;
@property (nonatomic, assign) NSUInteger modelVertexCount;
@property (nonatomic, strong) id<MTLRenderPipelineState> modelPipelineState;

// Real-time preview rendering
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *renderedPixelData;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *renderedPixelWidths;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *renderedPixelHeights;
@property (nonatomic, strong) id<MTLBuffer> previewColorBuffer;
@property (nonatomic, assign) NSUInteger previewColorCount;
@property (nonatomic, strong) NSLock *pixelDataLock;

@property (nonatomic, assign) NSPoint lastDragPoint;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) BOOL isRightDragging;
@property (nonatomic, assign) BOOL isManipulatingHandle;
@property (nonatomic, assign) XLHandleType activeHandleType;

@property (nonatomic, assign) CFAbsoluteTime lastFrameTime;

@property (nonatomic, strong) XLManipulationHandlesRenderer *handles;

@end

@implementation XLMetalPreviewView

#pragma mark - Initialization

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.wantsLayer = YES;

    _device = MTLCreateSystemDefaultDevice();
    _queue = [_device newCommandQueue];
    _sampleCount = kDefaultMSAASampleCount;

    _cameraController = [[XLCameraController alloc] init];
    _show3D = YES;
    _showGrid = YES;
    _contentDirty = YES;
    _needsRenderFlag = YES;
    _lastFrameTime = CFAbsoluteTimeGetCurrent();

    _backgroundColor = [NSColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0];
    _isManipulatingHandle = NO;
    _activeHandleType = XLHandleTypeNone;

    // Real-time preview rendering
    _previewRenderingActive = NO;
    _playbackPositionMS = 0;
    _sequenceDurationMS = 0;
    _frameTimeMS = 50; // Default 20fps
    _showEffectColors = NO;
    _renderedPixelData = [[NSMutableDictionary alloc] init];
    _renderedPixelWidths = [[NSMutableDictionary alloc] init];
    _renderedPixelHeights = [[NSMutableDictionary alloc] init];
    _pixelDataLock = [[NSLock alloc] init];

    [self setupDepthStencilState];
    [self buildGridPipeline];
    [self buildGridVertices];

    // Initialize manipulation handles renderer
    _handles = [[XLManipulationHandlesRenderer alloc] initWithDevice:_device];
    _handles.is3D = _show3D;

    // Accept mouse events
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
               owner:self
            userInfo:nil];
    [self addTrackingArea:trackingArea];
}

- (void)dealloc {
    [self stopRenderLoop];
}

#pragma mark - Layer Setup

- (CALayer *)makeBackingLayer {
    CAMetalLayer *metalLayer = [[CAMetalLayer alloc] init];
    metalLayer.device = _device;
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metalLayer.framebufferOnly = YES;
    metalLayer.presentsWithTransaction = NO;

    // Enable EDR / wide color if available
    if (@available(macOS 10.15, *)) {
        metalLayer.wantsExtendedDynamicRangeContent = NO;
    }

    // ProMotion: allow the display link to drive at native refresh rate
    metalLayer.displaySyncEnabled = YES;

    _mlayer = metalLayer;
    return metalLayer;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (void)updateLayer {
    // Layer content is driven by the display link, not by updateLayer
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];

    CGFloat scale = self.window.backingScaleFactor ?: 1.0;
    _mlayer.contentsScale = scale;
    _contentDirty = YES;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];

    CGFloat scale = self.window.backingScaleFactor ?: 1.0;
    _mlayer.drawableSize = CGSizeMake(newSize.width * scale, newSize.height * scale);
    _contentDirty = YES;
}

- (void)setBoundsSize:(NSSize)newSize {
    [super setBoundsSize:newSize];
    _contentDirty = YES;
}

#pragma mark - Depth / Stencil

- (void)setupDepthStencilState {
    MTLDepthStencilDescriptor *desc = [[MTLDepthStencilDescriptor alloc] init];
    desc.depthCompareFunction = MTLCompareFunctionLessEqual;
    desc.depthWriteEnabled = YES;
    _depthStencilState = [_device newDepthStencilStateWithDescriptor:desc];
}

#pragma mark - Grid Pipeline

- (void)buildGridPipeline {
    NSError *error = nil;

    // Inline Metal shader source for the ground grid
    NSString *shaderSource = @
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "\n"
        "struct GridVertex {\n"
        "    float3 position [[attribute(0)]];\n"
        "    float4 color    [[attribute(1)]];\n"
        "};\n"
        "\n"
        "struct GridUniforms {\n"
        "    float4x4 viewProjection;\n"
        "};\n"
        "\n"
        "struct GridOut {\n"
        "    float4 position [[position]];\n"
        "    float4 color;\n"
        "};\n"
        "\n"
        "vertex GridOut gridVertexShader(\n"
        "    GridVertex in [[stage_in]],\n"
        "    constant GridUniforms &uniforms [[buffer(1)]]) {\n"
        "    GridOut out;\n"
        "    out.position = uniforms.viewProjection * float4(in.position, 1.0);\n"
        "    out.color = in.color;\n"
        "    return out;\n"
        "}\n"
        "\n"
        "fragment float4 gridFragmentShader(GridOut in [[stage_in]]) {\n"
        "    return in.color;\n"
        "}\n";

    id<MTLLibrary> library = [_device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"XLMetalPreviewView: Failed to compile grid shaders: %@", error);
        return;
    }

    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"gridVertexShader"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"gridFragmentShader"];

    MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
    // Position: float3 at offset 0
    vertexDesc.attributes[0].format = MTLVertexFormatFloat3;
    vertexDesc.attributes[0].offset = 0;
    vertexDesc.attributes[0].bufferIndex = 0;
    // Color: float4 at offset 12
    vertexDesc.attributes[1].format = MTLVertexFormatFloat4;
    vertexDesc.attributes[1].offset = sizeof(simd_float3);
    vertexDesc.attributes[1].bufferIndex = 0;
    // Stride
    vertexDesc.layouts[0].stride = sizeof(XLGridVertex);
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
    pipeDesc.sampleCount = _sampleCount;

    _gridPipelineState = [_device newRenderPipelineStateWithDescriptor:pipeDesc error:&error];
    if (!_gridPipelineState) {
        NSLog(@"XLMetalPreviewView: Failed to create grid pipeline: %@", error);
    }
}

- (void)buildGridVertices {
    NSMutableData *vertexData = [[NSMutableData alloc] init];

    float halfExtent = kGridExtent;
    float fadeStart = halfExtent * 0.6f;

    for (NSInteger i = 0; i < kGridLineCount; i++) {
        float offset = (i - (kGridLineCount - 1) / 2.0f) * kGridSpacing;

        // Line along Z axis
        float alphaStart = [self gridAlphaForDistance:fabsf(offset) fadeStart:fadeStart fadeEnd:halfExtent];

        XLGridVertex v0 = {
            .position = {offset, 0.0f, -halfExtent},
            .color = {0.3f, 0.3f, 0.3f, 0.0f}
        };
        XLGridVertex v1 = {
            .position = {offset, 0.0f, 0.0f},
            .color = {0.3f, 0.3f, 0.3f, alphaStart}
        };
        XLGridVertex v2 = {
            .position = {offset, 0.0f, halfExtent},
            .color = {0.3f, 0.3f, 0.3f, 0.0f}
        };

        [vertexData appendBytes:&v0 length:sizeof(XLGridVertex)];
        [vertexData appendBytes:&v1 length:sizeof(XLGridVertex)];
        [vertexData appendBytes:&v1 length:sizeof(XLGridVertex)];
        [vertexData appendBytes:&v2 length:sizeof(XLGridVertex)];

        // Line along X axis
        XLGridVertex h0 = {
            .position = {-halfExtent, 0.0f, offset},
            .color = {0.3f, 0.3f, 0.3f, 0.0f}
        };
        XLGridVertex h1 = {
            .position = {0.0f, 0.0f, offset},
            .color = {0.3f, 0.3f, 0.3f, alphaStart}
        };
        XLGridVertex h2 = {
            .position = {halfExtent, 0.0f, offset},
            .color = {0.3f, 0.3f, 0.3f, 0.0f}
        };

        [vertexData appendBytes:&h0 length:sizeof(XLGridVertex)];
        [vertexData appendBytes:&h1 length:sizeof(XLGridVertex)];
        [vertexData appendBytes:&h1 length:sizeof(XLGridVertex)];
        [vertexData appendBytes:&h2 length:sizeof(XLGridVertex)];
    }

    _gridVertexCount = vertexData.length / sizeof(XLGridVertex);
    _gridVertexBuffer = [_device newBufferWithBytes:vertexData.bytes
                                             length:vertexData.length
                                            options:MTLResourceStorageModeShared];
    [_gridVertexBuffer setLabel:@"GridVertices"];
}

- (float)gridAlphaForDistance:(float)dist fadeStart:(float)fadeStart fadeEnd:(float)fadeEnd {
    if (dist <= fadeStart) return 0.4f;
    if (dist >= fadeEnd) return 0.0f;
    float t = (dist - fadeStart) / (fadeEnd - fadeStart);
    return 0.4f * (1.0f - t);
}

#pragma mark - MSAA / Depth Texture Management

- (void)ensureTexturesForSize:(CGSize)size {
    if (CGSizeEqualToSize(size, _lastDrawableSize) && _msaaTexture && _depthTexture) {
        return;
    }
    _lastDrawableSize = size;
    NSUInteger w = (NSUInteger)size.width;
    NSUInteger h = (NSUInteger)size.height;
    if (w == 0 || h == 0) return;

    // MSAA resolve texture
    MTLTextureDescriptor *msaaDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                        width:w
                                                                                       height:h
                                                                                    mipmapped:NO];
    msaaDesc.textureType = MTLTextureType2DMultisample;
    msaaDesc.sampleCount = _sampleCount;
    msaaDesc.usage = MTLTextureUsageRenderTarget;
    msaaDesc.storageMode = MTLStorageModePrivate;
    _msaaTexture = [_device newTextureWithDescriptor:msaaDesc];
    [_msaaTexture setLabel:@"PreviewMSAA"];

    // Depth texture
    MTLTextureDescriptor *depthDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                         width:w
                                                                                        height:h
                                                                                     mipmapped:NO];
    depthDesc.textureType = MTLTextureType2DMultisample;
    depthDesc.sampleCount = _sampleCount;
    depthDesc.usage = MTLTextureUsageRenderTarget;
    depthDesc.storageMode = MTLStorageModePrivate;

    // Use memoryless if supported (Apple Silicon)
    if (@available(macOS 11.0, *)) {
        if ([_device supportsFamily:MTLGPUFamilyApple5]) {
            depthDesc.storageMode = MTLStorageModeMemoryless;
        }
    }

    _depthTexture = [_device newTextureWithDescriptor:depthDesc];
    [_depthTexture setLabel:@"PreviewDepth"];
}

#pragma mark - Render Loop (CVDisplayLink)

- (void)startRenderLoop {
    if (_renderLoopRunning) return;

    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &displayLinkCallback, (__bridge void *)self);

    // Try to match the display this window is on
    if (self.window) {
        CGDirectDisplayID displayID = (CGDirectDisplayID)[self.window.screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        CVDisplayLinkSetCurrentCGDisplay(_displayLink, displayID);
    }

    CVDisplayLinkStart(_displayLink);
    _renderLoopRunning = YES;
}

- (void)stopRenderLoop {
    if (!_renderLoopRunning) return;

    CVDisplayLinkStop(_displayLink);
    CVDisplayLinkRelease(_displayLink);
    _displayLink = NULL;
    _renderLoopRunning = NO;
}

- (void)displayLinkFired:(const CVTimeStamp *)outputTime {
    BOOL shouldRender = _needsRenderFlag || _contentDirty || _cameraController.isAnimating;
    if (!shouldRender) return;

    _needsRenderFlag = NO;
    _contentDirty = NO;

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    NSTimeInterval dt = now - _lastFrameTime;
    _lastFrameTime = now;

    if (_cameraController.isAnimating) {
        BOOL stillAnimating = [_cameraController updateAnimation:dt];
        if (stillAnimating) {
            _contentDirty = YES;
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self renderFrame];
    });
}

- (void)setNeedsRender {
    _needsRenderFlag = YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];

    if (self.window) {
        CGFloat scale = self.window.backingScaleFactor;
        _mlayer.contentsScale = scale;

        NSSize frameSize = self.frame.size;
        _mlayer.drawableSize = CGSizeMake(frameSize.width * scale, frameSize.height * scale);

        if (!_renderLoopRunning) {
            [self startRenderLoop];
        }

        // Re-target display link to current display
        if (_displayLink) {
            CGDirectDisplayID displayID = (CGDirectDisplayID)[self.window.screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            CVDisplayLinkSetCurrentCGDisplay(_displayLink, displayID);
        }
    } else {
        [self stopRenderLoop];
    }
}

#pragma mark - Frame Rendering

- (void)renderFrame {
    @autoreleasepool {
        id<CAMetalDrawable> drawable = [_mlayer nextDrawable];
        if (!drawable) return;

        CGSize drawableSize = _mlayer.drawableSize;
        [self ensureTexturesForSize:drawableSize];

        if (!_msaaTexture || !_depthTexture) return;

        id<MTLCommandBuffer> commandBuffer = [_queue commandBuffer];
        [commandBuffer setLabel:@"PreviewFrame"];

        // Build render pass
        MTLRenderPassDescriptor *passDesc = [[MTLRenderPassDescriptor alloc] init];

        // Color with MSAA
        passDesc.colorAttachments[0].texture = _msaaTexture;
        passDesc.colorAttachments[0].resolveTexture = drawable.texture;
        passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
        passDesc.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;

        CGFloat r = 0.1, g = 0.1, b = 0.1, a = 1.0;
        NSColor *bgRGB = [_backgroundColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        if (bgRGB) {
            [bgRGB getRed:&r green:&g blue:&b alpha:&a];
        }
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(r, g, b, a);

        // Depth
        passDesc.depthAttachment.texture = _depthTexture;
        passDesc.depthAttachment.loadAction = MTLLoadActionClear;
        passDesc.depthAttachment.storeAction = MTLStoreActionDontCare;
        passDesc.depthAttachment.clearDepth = 1.0;

        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];
        [encoder setLabel:@"PreviewEncoder"];
        [encoder setDepthStencilState:_depthStencilState];

        // Viewport
        float width = (float)drawableSize.width;
        float height = (float)drawableSize.height;
        MTLViewport viewport = {0, 0, width, height, 0.0, 1.0};
        [encoder setViewport:viewport];

        // Camera matrices
        float aspect = width / height;
        simd_float4x4 viewMatrix = _cameraController.viewMatrix;
        simd_float4x4 projMatrix = [_cameraController projectionMatrixForAspect:aspect];
        simd_float4x4 viewProjection = simd_mul(projMatrix, viewMatrix);

        // Render ground grid
        if (_showGrid && _show3D && _gridPipelineState) {
            [encoder pushDebugGroup:@"Grid"];
            [encoder setRenderPipelineState:_gridPipelineState];
            [encoder setVertexBuffer:_gridVertexBuffer offset:0 atIndex:0];
            [encoder setVertexBytes:&viewProjection length:sizeof(simd_float4x4) atIndex:1];
            [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:_gridVertexCount];
            [encoder popDebugGroup];
        }

        // Render model nodes as points
        if (_modelVertexBuffer && _modelVertexCount > 0 && _gridPipelineState) {
            [encoder pushDebugGroup:@"Models"];
            [encoder setRenderPipelineState:_gridPipelineState];
            [encoder setVertexBuffer:_modelVertexBuffer offset:0 atIndex:0];
            [encoder setVertexBytes:&viewProjection length:sizeof(simd_float4x4) atIndex:1];
            [encoder drawPrimitives:MTLPrimitiveTypePoint vertexStart:0 vertexCount:_modelVertexCount];
            [encoder popDebugGroup];
        }

        // Render manipulation handles
        if (_handles && _selectedModelName) {
            [_handles renderWithEncoder:encoder
                         viewProjection:viewProjection
                                   zoom:(float)_cameraController.distance
                                  scale:1];
        }

        [encoder endEncoding];

        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];
    }
}

#pragma mark - Public Properties

- (id<MTLDevice>)metalDevice {
    return _device;
}

- (id<MTLCommandQueue>)commandQueue {
    return _queue;
}

- (CAMetalLayer *)metalLayer {
    return _mlayer;
}

- (simd_float3)cameraPosition {
    return _cameraController.eyePosition;
}

- (simd_float3)cameraTarget {
    return _cameraController.target;
}

- (simd_float3)cameraUp {
    return _cameraController.up;
}

- (CGFloat)zoomLevel {
    return (CGFloat)_cameraController.distance;
}

- (void)setZoomLevel:(CGFloat)zoomLevel {
    _cameraController.distance = (float)zoomLevel;
    _contentDirty = YES;
}

- (void)setShowGrid:(BOOL)showGrid {
    _showGrid = showGrid;
    _contentDirty = YES;
}

#pragma mark - Camera Control

- (void)resetCamera {
    [_cameraController reset];
    _contentDirty = YES;
}

- (void)frameAllModels {
    // Calculate bounding box from all cached model data
    simd_float3 bbMin = {FLT_MAX, FLT_MAX, FLT_MAX};
    simd_float3 bbMax = {-FLT_MAX, -FLT_MAX, -FLT_MAX};

    BOOL hasModels = NO;
    for (NSDictionary *modelData in _modelDataCache) {
        NSDictionary *bounds = modelData[@"bounds"];
        if (!bounds || bounds.count == 0) continue;

        hasModels = YES;
        float minX = [bounds[@"minX"] floatValue];
        float maxX = [bounds[@"maxX"] floatValue];
        float minY = [bounds[@"minY"] floatValue];
        float maxY = [bounds[@"maxY"] floatValue];
        float minZ = [bounds[@"minZ"] floatValue];
        float maxZ = [bounds[@"maxZ"] floatValue];

        bbMin.x = fminf(bbMin.x, minX);
        bbMin.y = fminf(bbMin.y, minY);
        bbMin.z = fminf(bbMin.z, minZ);
        bbMax.x = fmaxf(bbMax.x, maxX);
        bbMax.y = fmaxf(bbMax.y, maxY);
        bbMax.z = fmaxf(bbMax.z, maxZ);
    }

    if (!hasModels) {
        // Default scene volume if no models
        bbMin = (simd_float3){-500.0f, 0.0f, -500.0f};
        bbMax = (simd_float3){500.0f, 500.0f, 500.0f};
    }

    float aspect = (float)_mlayer.drawableSize.width / (float)_mlayer.drawableSize.height;
    [_cameraController frameBoundingBoxMin:bbMin max:bbMax aspect:aspect];
    _contentDirty = YES;
}

- (void)highlightModel:(NSString *)modelName {
    _highlightedModelName = modelName;
    _contentDirty = YES;
}

- (void)reloadModels {
    if (!_engineBridge) {
        _modelDataCache = @[];
        _modelVertexBuffer = nil;
        _modelVertexCount = 0;
        _contentDirty = YES;
        return;
    }

    // Get all model names and their node data
    NSMutableArray<NSDictionary *> *modelData = [[NSMutableArray alloc] init];
    NSArray<NSString *> *modelNames = [_engineBridge getModelNamesExcludingGroups];

    for (NSString *modelName in modelNames) {
        NSDictionary *info = [_engineBridge getModelInfo:modelName];
        if (!info) continue;

        NSArray<NSDictionary *> *nodes = [_engineBridge getModelNodes:modelName];
        NSDictionary *bounds = [_engineBridge getModelBounds:modelName];

        if (nodes.count > 0) {
            [modelData addObject:@{
                @"name": modelName,
                @"info": info,
                @"nodes": nodes,
                @"bounds": bounds ?: @{},
            }];
        }
    }

    _modelDataCache = [modelData copy];
    [self buildModelVertices];
    _contentDirty = YES;
}

- (void)selectModel:(NSString *)modelName {
    _selectedModelName = modelName;

    if (!modelName) {
        [self clearModelSelection];
        return;
    }

    // Get model info and set up manipulation handles
    NSDictionary *info = [_engineBridge getModelInfo:modelName];
    NSDictionary *bounds = [_engineBridge getModelBounds:modelName];

    if (!info || !bounds) {
        [self clearModelSelection];
        return;
    }

    // Extract position from model info (may be in properties)
    float posX = [info[@"WorldPosX"] floatValue];
    float posY = [info[@"WorldPosY"] floatValue];
    float posZ = [info[@"WorldPosZ"] floatValue];

    // Extract scale
    float scaleX = [info[@"ScaleX"] floatValue];
    float scaleY = [info[@"ScaleY"] floatValue];
    float scaleZ = [info[@"ScaleZ"] floatValue];
    if (scaleX == 0) scaleX = 1.0f;
    if (scaleY == 0) scaleY = 1.0f;
    if (scaleZ == 0) scaleZ = 1.0f;

    // Extract rotation
    float rotX = [info[@"RotateX"] floatValue];
    float rotY = [info[@"RotateY"] floatValue];
    float rotZ = [info[@"RotateZ"] floatValue];

    // Extract bounds
    float minX = [bounds[@"minX"] floatValue];
    float maxX = [bounds[@"maxX"] floatValue];
    float minY = [bounds[@"minY"] floatValue];
    float maxY = [bounds[@"maxY"] floatValue];
    float minZ = [bounds[@"minZ"] floatValue];
    float maxZ = [bounds[@"maxZ"] floatValue];

    // Calculate render dimensions
    float renderWidth = maxX - minX;
    float renderHeight = maxY - minY;
    float renderDepth = maxZ - minZ;

    // Check if locked
    BOOL isLocked = [info[@"Locked"] boolValue];

    // Check if supports Z scaling (3D models)
    BOOL supportsZScaling = _show3D && (renderDepth > 0.1f);

    [self setModelTransformWithPosition:(simd_float3){posX, posY, posZ}
                                  scale:(simd_float3){scaleX, scaleY, scaleZ}
                               rotation:(simd_float3){rotX, rotY, rotZ}
                         boundingBoxMin:(simd_float3){minX, minY, minZ}
                         boundingBoxMax:(simd_float3){maxX, maxY, maxZ}
                            renderWidth:renderWidth
                           renderHeight:renderHeight
                            renderDepth:renderDepth
                               isLocked:isLocked
                       supportsZScaling:supportsZScaling];

    _contentDirty = YES;

    if ([_delegate respondsToSelector:@selector(previewView:didSelectModel:)]) {
        [_delegate previewView:self didSelectModel:modelName];
    }
}

- (void)buildModelVertices {
    [self buildModelVerticesWithEffectColors:_showEffectColors];
}

- (void)buildModelVerticesWithEffectColors:(BOOL)useEffectColors {
    if (_modelDataCache.count == 0) {
        _modelVertexBuffer = nil;
        _modelVertexCount = 0;
        return;
    }

    // Count total vertices needed (one per node)
    NSUInteger totalNodes = 0;
    for (NSDictionary *modelData in _modelDataCache) {
        NSArray *nodes = modelData[@"nodes"];
        totalNodes += nodes.count;
    }

    if (totalNodes == 0) {
        _modelVertexBuffer = nil;
        _modelVertexCount = 0;
        return;
    }

    // Build vertex data - position + color for each node
    NSMutableData *vertexData = [[NSMutableData alloc] initWithCapacity:totalNodes * sizeof(XLGridVertex)];

    NSUInteger modelIndex = 0;
    for (NSDictionary *modelData in _modelDataCache) {
        NSArray<NSDictionary *> *nodes = modelData[@"nodes"];
        NSString *modelName = modelData[@"name"];

        // Check for rendered pixel data for this model
        [_pixelDataLock lock];
        NSData *pixelData = useEffectColors ? _renderedPixelData[modelName] : nil;
        NSUInteger pixelWidth = [_renderedPixelWidths[modelName] unsignedIntegerValue];
        NSUInteger pixelHeight = [_renderedPixelHeights[modelName] unsignedIntegerValue];
        [_pixelDataLock unlock];

        const uint8_t *pixels = (const uint8_t *)pixelData.bytes;
        NSUInteger pixelCount = pixelWidth * pixelHeight;

        // Determine color - highlighted models get a brighter color
        BOOL isHighlighted = [modelName isEqualToString:_highlightedModelName];
        BOOL isSelected = [modelName isEqualToString:_selectedModelName];

        float baseGray = 0.6f;
        if (isSelected) {
            baseGray = 1.0f;
        } else if (isHighlighted) {
            baseGray = 0.9f;
        }

        // Use hue based on model index for visual distinction (fallback color)
        float hue = fmod((float)modelIndex * 0.15f, 1.0f);
        float defaultR, defaultG, defaultB;
        [self hueToRGB:hue r:&defaultR g:&defaultG b:&defaultB];

        NSUInteger nodeIndex = 0;
        for (NSDictionary *node in nodes) {
            XLGridVertex vertex;
            vertex.position = (simd_float3){
                [node[@"x"] floatValue],
                [node[@"y"] floatValue],
                [node[@"z"] floatValue],
            };

            // Get buffer position from node for pixel lookup
            NSInteger bufX = [node[@"bufX"] integerValue];
            NSInteger bufY = [node[@"bufY"] integerValue];

            // Try to get color from rendered pixel data
            BOOL gotPixelColor = NO;
            if (pixels && pixelWidth > 0 && pixelHeight > 0) {
                // Calculate pixel index in RGBA buffer
                if (bufX >= 0 && bufX < (NSInteger)pixelWidth &&
                    bufY >= 0 && bufY < (NSInteger)pixelHeight) {
                    NSUInteger pixelIdx = ((NSUInteger)bufY * pixelWidth + (NSUInteger)bufX) * 4;
                    if (pixelIdx + 3 < pixelData.length) {
                        float r = pixels[pixelIdx + 0] / 255.0f;
                        float g = pixels[pixelIdx + 1] / 255.0f;
                        float b = pixels[pixelIdx + 2] / 255.0f;
                        float a = pixels[pixelIdx + 3] / 255.0f;

                        // Only use pixel color if alpha > 0 (has rendered content)
                        if (a > 0.01f) {
                            vertex.color = (simd_float4){r, g, b, 1.0f};
                            gotPixelColor = YES;
                        }
                    }
                }
            }

            // Fall back to layout color if no pixel data
            if (!gotPixelColor) {
                vertex.color = (simd_float4){
                    baseGray * (0.3f + 0.7f * defaultR),
                    baseGray * (0.3f + 0.7f * defaultG),
                    baseGray * (0.3f + 0.7f * defaultB),
                    1.0f
                };
            }

            [vertexData appendBytes:&vertex length:sizeof(XLGridVertex)];
            nodeIndex++;
        }

        modelIndex++;
    }

    _modelVertexCount = totalNodes;
    _modelVertexBuffer = [_device newBufferWithBytes:vertexData.bytes
                                              length:vertexData.length
                                             options:MTLResourceStorageModeShared];
    [_modelVertexBuffer setLabel:@"ModelVertices"];
}

- (void)hueToRGB:(float)hue r:(float *)r g:(float *)g b:(float *)b {
    float h = hue * 6.0f;
    float c = 1.0f;
    float x = c * (1.0f - fabsf(fmodf(h, 2.0f) - 1.0f));

    if (h < 1.0f) {
        *r = c; *g = x; *b = 0;
    } else if (h < 2.0f) {
        *r = x; *g = c; *b = 0;
    } else if (h < 3.0f) {
        *r = 0; *g = c; *b = x;
    } else if (h < 4.0f) {
        *r = 0; *g = x; *b = c;
    } else if (h < 5.0f) {
        *r = x; *g = 0; *b = c;
    } else {
        *r = c; *g = 0; *b = x;
    }
}

#pragma mark - Real-Time Preview Rendering

- (void)setPreviewRenderingActive:(BOOL)previewRenderingActive {
    if (_previewRenderingActive != previewRenderingActive) {
        _previewRenderingActive = previewRenderingActive;

        if (!previewRenderingActive) {
            // When stopping preview, clear rendered pixels and rebuild with layout colors
            [self clearRenderedPixels];
        }

        _showEffectColors = previewRenderingActive;
        _contentDirty = YES;
    }
}

- (void)setPlaybackPositionMS:(NSInteger)playbackPositionMS {
    if (_playbackPositionMS != playbackPositionMS) {
        _playbackPositionMS = playbackPositionMS;

        // If preview rendering is active, mark content as dirty to trigger refresh
        if (_previewRenderingActive) {
            _contentDirty = YES;
        }
    }
}

- (void)setShowEffectColors:(BOOL)showEffectColors {
    if (_showEffectColors != showEffectColors) {
        _showEffectColors = showEffectColors;
        [self buildModelVerticesWithEffectColors:showEffectColors];
        _contentDirty = YES;
    }
}

- (void)updatePreviewForTime:(NSInteger)timeMS {
    _playbackPositionMS = timeMS;

    // Rebuild model vertices with current pixel data
    if (_showEffectColors) {
        [self buildModelVerticesWithEffectColors:YES];
    }

    _contentDirty = YES;
    [self setNeedsRender];
}

- (void)setRenderedPixels:(NSData *)pixelData
                 forModel:(NSString *)modelName
                    width:(NSUInteger)width
                   height:(NSUInteger)height {
    if (!modelName) return;

    [_pixelDataLock lock];
    if (pixelData && pixelData.length > 0) {
        _renderedPixelData[modelName] = [pixelData copy];
        _renderedPixelWidths[modelName] = @(width);
        _renderedPixelHeights[modelName] = @(height);
    } else {
        [_renderedPixelData removeObjectForKey:modelName];
        [_renderedPixelWidths removeObjectForKey:modelName];
        [_renderedPixelHeights removeObjectForKey:modelName];
    }
    [_pixelDataLock unlock];

    // Mark for rebuild if showing effect colors
    if (_showEffectColors) {
        _contentDirty = YES;
    }
}

- (void)clearRenderedPixels {
    [_pixelDataLock lock];
    [_renderedPixelData removeAllObjects];
    [_renderedPixelWidths removeAllObjects];
    [_renderedPixelHeights removeAllObjects];
    [_pixelDataLock unlock];

    // Rebuild with layout colors
    [self buildModelVerticesWithEffectColors:NO];
    _contentDirty = YES;
}

#pragma mark - Mouse / Trackpad Event Handling

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)rightMouseDown:(NSEvent *)event {
    _lastDragPoint = [self convertPoint:event.locationInWindow fromView:nil];
    _isRightDragging = YES;
}

- (void)rightMouseDragged:(NSEvent *)event {
    NSPoint current = [self convertPoint:event.locationInWindow fromView:nil];
    float dx = (float)(current.x - _lastDragPoint.x);
    float dy = (float)(current.y - _lastDragPoint.y);
    _lastDragPoint = current;

    // Right drag = pan
    [_cameraController panByDeltaX:dx deltaY:dy sensitivity:0.002f];
    _contentDirty = YES;

    if ([_delegate respondsToSelector:@selector(previewView:didChangeCamera:)]) {
        [_delegate previewView:self didChangeCamera:_cameraController];
    }
}

- (void)rightMouseUp:(NSEvent *)event {
    _isRightDragging = NO;
}

- (void)mouseExited:(NSEvent *)event {
    _isDragging = NO;
    _isRightDragging = NO;
    _isManipulatingHandle = NO;
}

- (void)scrollWheel:(NSEvent *)event {
    if (event.momentumPhase != NSEventPhaseNone && event.momentumPhase != NSEventPhaseBegan) {
        // Two-finger pan from trackpad scrolling
        float dx = (float)event.scrollingDeltaX;
        float dy = (float)event.scrollingDeltaY;
        [_cameraController panByDeltaX:-dx deltaY:-dy sensitivity:0.003f];
    } else if (event.hasPreciseScrollingDeltas) {
        // Trackpad two-finger scroll = pan
        float dx = (float)event.scrollingDeltaX;
        float dy = (float)event.scrollingDeltaY;
        [_cameraController panByDeltaX:-dx deltaY:-dy sensitivity:0.003f];
    } else {
        // Mouse scroll wheel = zoom
        float delta = (float)event.scrollingDeltaY;
        [_cameraController zoomByDelta:-delta sensitivity:0.05f];
    }

    _contentDirty = YES;

    if ([_delegate respondsToSelector:@selector(previewView:didChangeCamera:)]) {
        [_delegate previewView:self didChangeCamera:_cameraController];
    }
}

- (void)magnifyWithEvent:(NSEvent *)event {
    // Pinch-to-zoom on trackpad
    float delta = (float)event.magnification;
    [_cameraController zoomByDelta:-delta sensitivity:2.0f];
    _contentDirty = YES;

    if ([_delegate respondsToSelector:@selector(previewView:didChangeCamera:)]) {
        [_delegate previewView:self didChangeCamera:_cameraController];
    }
}

- (void)keyDown:(NSEvent *)event {
    switch (event.keyCode) {
        case 0x1F: // 'o' key - orbit reset
            [self resetCamera];
            break;
        case 0x03: // 'f' key - frame all
            [self frameAllModels];
            break;
        case 0x22: // '[' key - toggle grid
            self.showGrid = !self.showGrid;
            break;
        case 0x12: // '1' key - front view
            [_cameraController setFrontView];
            _contentDirty = YES;
            break;
        case 0x13: // '2' key - top view
            [_cameraController setTopDownView];
            _contentDirty = YES;
            break;

        // Tool mode keys
        case 0x11: // 't' key - translate mode
            _handles.toolMode = XLToolModeTranslate;
            _contentDirty = YES;
            break;
        case 0x01: // 's' key - scale mode
            _handles.toolMode = XLToolModeScale;
            _contentDirty = YES;
            break;
        case 0x0F: // 'r' key - rotate mode
            _handles.toolMode = XLToolModeRotate;
            _contentDirty = YES;
            break;
        case 0x31: // space key - toggle tool mode
            [self toggleToolMode];
            break;

        // Axis constraint keys
        case 0x07: // 'x' key - X axis
            if (_handles.activeAxis == XLActiveAxisX) {
                _handles.activeAxis = XLActiveAxisNone;
            } else {
                _handles.activeAxis = XLActiveAxisX;
            }
            _contentDirty = YES;
            break;
        case 0x10: // 'y' key - Y axis
            if (_handles.activeAxis == XLActiveAxisY) {
                _handles.activeAxis = XLActiveAxisNone;
            } else {
                _handles.activeAxis = XLActiveAxisY;
            }
            _contentDirty = YES;
            break;
        case 0x06: // 'z' key - Z axis
            if (_handles.activeAxis == XLActiveAxisZ) {
                _handles.activeAxis = XLActiveAxisNone;
            } else {
                _handles.activeAxis = XLActiveAxisZ;
            }
            _contentDirty = YES;
            break;

        // Delete key - clear selection
        case 0x33: // delete/backspace
        case 0x75: // forward delete
            if (_selectedModelName) {
                [self clearModelSelection];
            }
            break;

        // Escape key - clear selection or cancel manipulation
        case 0x35: // escape
            if (_isManipulatingHandle) {
                [_handles endDrag];
                _isManipulatingHandle = NO;
                _activeHandleType = XLHandleTypeNone;
                _contentDirty = YES;
            } else if (_selectedModelName) {
                [self clearModelSelection];
            }
            break;

        default:
            [super keyDown:event];
            break;
    }
}

#pragma mark - Hit Testing

- (void)handleClickAtEvent:(NSEvent *)event {
    NSPoint localPoint = [self convertPoint:event.locationInWindow fromView:nil];

    // Convert to normalized device coordinates
    CGSize drawableSize = _mlayer.drawableSize;
    CGFloat scale = self.window.backingScaleFactor ?: 1.0;
    float ndcX = (float)(localPoint.x * scale / drawableSize.width) * 2.0f - 1.0f;
    float ndcY = (float)(localPoint.y * scale / drawableSize.height) * 2.0f - 1.0f;

    // Build inverse view-projection matrix for ray casting
    float aspect = (float)drawableSize.width / (float)drawableSize.height;
    simd_float4x4 viewMatrix = _cameraController.viewMatrix;
    simd_float4x4 projMatrix = [_cameraController projectionMatrixForAspect:aspect];
    simd_float4x4 viewProj = simd_mul(projMatrix, viewMatrix);
    simd_float4x4 invViewProj = simd_inverse(viewProj);

    // Ray origin and direction in world space
    simd_float4 nearPoint = simd_mul(invViewProj, (simd_float4){ndcX, ndcY, 0.0f, 1.0f});
    simd_float4 farPoint = simd_mul(invViewProj, (simd_float4){ndcX, ndcY, 1.0f, 1.0f});

    simd_float3 rayOrigin = (simd_float3){nearPoint.x, nearPoint.y, nearPoint.z} / nearPoint.w;
    simd_float3 rayEnd = (simd_float3){farPoint.x, farPoint.y, farPoint.z} / farPoint.w;
    simd_float3 rayDir = simd_normalize(rayEnd - rayOrigin);

    // Model hit testing will be performed through XLEngineBridge by passing
    // rayOrigin and rayDir to the model engine for bounding box intersection.
    // For now, store the ray for future use and notify the delegate with nil
    // to indicate a deselect/background click.

    if ([_delegate respondsToSelector:@selector(previewView:didSelectModel:)]) {
        [_delegate previewView:self didSelectModel:nil];
    }
}

- (void)mouseDown:(NSEvent *)event {
    if (event.clickCount == 2) {
        [self frameAllModels];
        return;
    }

    _lastDragPoint = [self convertPoint:event.locationInWindow fromView:nil];
    _isDragging = NO;
    _isRightDragging = NO;
    _isManipulatingHandle = NO;

    // Check if clicking on a manipulation handle
    if (_selectedModelName && _handles) {
        simd_float3 rayOrigin, rayDir;
        [self rayFromScreenPoint:_lastDragPoint rayOrigin:&rayOrigin rayDirection:&rayDir];

        XLHandleType hitHandle = [_handles hitTestWithRayOrigin:rayOrigin
                                                   rayDirection:rayDir
                                                           zoom:(float)_cameraController.distance
                                                          scale:1];

        if (hitHandle != XLHandleTypeNone) {
            _isManipulatingHandle = YES;
            _activeHandleType = hitHandle;
            _handles.activeHandle = hitHandle;

            // Calculate world point for drag start
            simd_float3 worldPoint = [self worldPointFromScreenPoint:_lastDragPoint onPlane:_handles.modelTransform.position];
            [_handles beginDragAtPoint:worldPoint forHandle:hitHandle];

            if ([_delegate respondsToSelector:@selector(previewView:didBeginManipulatingModel:)]) {
                [_delegate previewView:self didBeginManipulatingModel:_selectedModelName];
            }

            _contentDirty = YES;
            return;
        }
    }
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint current = [self convertPoint:event.locationInWindow fromView:nil];
    float dx = (float)(current.x - _lastDragPoint.x);
    float dy = (float)(current.y - _lastDragPoint.y);
    _lastDragPoint = current;

    if (_isManipulatingHandle && _handles) {
        // Handle manipulation mode
        simd_float3 worldPoint = [self worldPointFromScreenPoint:current onPlane:_handles.modelTransform.position];

        BOOL shiftHeld = (event.modifierFlags & NSEventModifierFlagShift) != 0;
        BOOL optionHeld = (event.modifierFlags & NSEventModifierFlagOption) != 0;
        BOOL cmdHeld = (event.modifierFlags & NSEventModifierFlagCommand) != 0;

        simd_float3 delta = [_handles updateDragToPoint:worldPoint
                                              shiftHeld:shiftHeld
                                             optionHeld:optionHeld
                                                cmdHeld:cmdHeld];

        if ([_delegate respondsToSelector:@selector(previewView:didManipulateModelWithDelta:)]) {
            [_delegate previewView:self didManipulateModelWithDelta:delta];
        }

        _contentDirty = YES;
        return;
    }

    // Camera orbit mode
    _isDragging = YES;
    [_cameraController orbitByDeltaX:dx deltaY:dy sensitivity:0.005f];
    _contentDirty = YES;

    if ([_delegate respondsToSelector:@selector(previewView:didChangeCamera:)]) {
        [_delegate previewView:self didChangeCamera:_cameraController];
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (_isManipulatingHandle) {
        [_handles endDrag];
        _isManipulatingHandle = NO;
        _activeHandleType = XLHandleTypeNone;

        if ([_delegate respondsToSelector:@selector(previewView:didEndManipulatingModel:)]) {
            [_delegate previewView:self didEndManipulatingModel:_selectedModelName];
        }

        _contentDirty = YES;
        return;
    }

    if (!_isDragging && event.clickCount == 1) {
        [self handleClickAtEvent:event];
    }
    _isDragging = NO;
}

- (void)mouseMoved:(NSEvent *)event {
    // Update highlighted handle on mouse move
    if (_selectedModelName && _handles) {
        NSPoint localPoint = [self convertPoint:event.locationInWindow fromView:nil];
        simd_float3 rayOrigin, rayDir;
        [self rayFromScreenPoint:localPoint rayOrigin:&rayOrigin rayDirection:&rayDir];

        XLHandleType hitHandle = [_handles hitTestWithRayOrigin:rayOrigin
                                                   rayDirection:rayDir
                                                           zoom:(float)_cameraController.distance
                                                          scale:1];

        if (hitHandle != _handles.highlightedHandle) {
            _handles.highlightedHandle = hitHandle;
            _contentDirty = YES;

            // Update cursor
            if (hitHandle != XLHandleTypeNone) {
                NSString *cursorType = [_handles cursorForHandle:hitHandle rotation:_handles.modelTransform.rotation.z];
                [self updateCursorForType:cursorType];
            } else {
                [[NSCursor arrowCursor] set];
            }
        }
    }
}

#pragma mark - Ray Casting Utilities

- (void)rayFromScreenPoint:(NSPoint)screenPoint rayOrigin:(simd_float3 *)rayOrigin rayDirection:(simd_float3 *)rayDirection {
    CGSize drawableSize = _mlayer.drawableSize;
    CGFloat scale = self.window.backingScaleFactor ?: 1.0;

    float ndcX = (float)(screenPoint.x * scale / drawableSize.width) * 2.0f - 1.0f;
    float ndcY = (float)(screenPoint.y * scale / drawableSize.height) * 2.0f - 1.0f;

    float aspect = (float)drawableSize.width / (float)drawableSize.height;
    simd_float4x4 viewMatrix = _cameraController.viewMatrix;
    simd_float4x4 projMatrix = [_cameraController projectionMatrixForAspect:aspect];
    simd_float4x4 viewProj = simd_mul(projMatrix, viewMatrix);
    simd_float4x4 invViewProj = simd_inverse(viewProj);

    simd_float4 nearPoint = simd_mul(invViewProj, (simd_float4){ndcX, ndcY, 0.0f, 1.0f});
    simd_float4 farPoint = simd_mul(invViewProj, (simd_float4){ndcX, ndcY, 1.0f, 1.0f});

    *rayOrigin = (simd_float3){nearPoint.x, nearPoint.y, nearPoint.z} / nearPoint.w;
    simd_float3 rayEnd = (simd_float3){farPoint.x, farPoint.y, farPoint.z} / farPoint.w;
    *rayDirection = simd_normalize(rayEnd - *rayOrigin);
}

- (simd_float3)worldPointFromScreenPoint:(NSPoint)screenPoint onPlane:(simd_float3)planePoint {
    simd_float3 rayOrigin, rayDir;
    [self rayFromScreenPoint:screenPoint rayOrigin:&rayOrigin rayDirection:&rayDir];

    // Intersect ray with plane through planePoint, facing camera
    simd_float3 planeNormal = simd_normalize(_cameraController.eyePosition - planePoint);

    float denom = simd_dot(planeNormal, rayDir);
    if (fabs(denom) < 0.0001f) {
        return planePoint; // Ray parallel to plane
    }

    float t = simd_dot(planePoint - rayOrigin, planeNormal) / denom;
    return rayOrigin + rayDir * t;
}

- (void)updateCursorForType:(NSString *)cursorType {
    if ([cursorType isEqualToString:@"move"]) {
        [[NSCursor openHandCursor] set];
    } else if ([cursorType isEqualToString:@"rotate"]) {
        [[NSCursor crosshairCursor] set];
    } else if ([cursorType isEqualToString:@"resize-nwse"]) {
        [[NSCursor resizeUpDownCursor] set]; // Approximation
    } else if ([cursorType isEqualToString:@"resize-nesw"]) {
        [[NSCursor resizeLeftRightCursor] set]; // Approximation
    } else if ([cursorType isEqualToString:@"resize-ew"]) {
        [[NSCursor resizeLeftRightCursor] set];
    } else if ([cursorType isEqualToString:@"resize-ns"]) {
        [[NSCursor resizeUpDownCursor] set];
    } else {
        [[NSCursor arrowCursor] set];
    }
}

#pragma mark - Manipulation Handles Public API

- (XLManipulationHandlesRenderer *)handlesRenderer {
    return _handles;
}

- (void)setModelTransformWithPosition:(simd_float3)position
                                scale:(simd_float3)scale
                             rotation:(simd_float3)rotation
                       boundingBoxMin:(simd_float3)boundingBoxMin
                       boundingBoxMax:(simd_float3)boundingBoxMax
                          renderWidth:(float)renderWidth
                         renderHeight:(float)renderHeight
                          renderDepth:(float)renderDepth
                             isLocked:(BOOL)isLocked
                     supportsZScaling:(BOOL)supportsZScaling {

    XLModelTransform transform;
    transform.position = position;
    transform.scale = scale;
    transform.rotation = rotation;
    transform.boundingBoxMin = boundingBoxMin;
    transform.boundingBoxMax = boundingBoxMax;
    transform.renderWidth = renderWidth;
    transform.renderHeight = renderHeight;
    transform.renderDepth = renderDepth;
    transform.isLocked = isLocked;
    transform.supportsZScaling = supportsZScaling;

    [_handles setModelTransform:transform];
    _contentDirty = YES;
}

- (void)clearModelSelection {
    _selectedModelName = nil;
    [_handles clearSelection];
    _isManipulatingHandle = NO;
    _activeHandleType = XLHandleTypeNone;
    _contentDirty = YES;
}

- (void)setToolMode:(NSInteger)mode {
    _handles.toolMode = (XLToolMode)mode;
    _contentDirty = YES;
}

- (void)setActiveAxis:(NSInteger)axis {
    _handles.activeAxis = (XLActiveAxis)axis;
    _contentDirty = YES;
}

- (void)toggleToolMode {
    XLToolMode current = _handles.toolMode;
    switch (current) {
        case XLToolModeTranslate:
            _handles.toolMode = XLToolModeScale;
            break;
        case XLToolModeScale:
            _handles.toolMode = XLToolModeRotate;
            break;
        case XLToolModeRotate:
        default:
            _handles.toolMode = XLToolModeTranslate;
            break;
    }
    _contentDirty = YES;
}

- (void)setGridSnapSize:(float)snapSize {
    _handles.gridSnapSize = snapSize;
}

- (void)setAngleSnapDegrees:(float)angleDegrees {
    _handles.angleSnapDegrees = angleDegrees;
}

- (void)setEdgeSnapEnabled:(BOOL)enabled {
    _handles.edgeSnapEnabled = enabled;
}

- (void)setShow3D:(BOOL)show3D {
    _show3D = show3D;
    _cameraController.perspective = show3D;
    _handles.is3D = show3D;
    _contentDirty = YES;
}

@end
