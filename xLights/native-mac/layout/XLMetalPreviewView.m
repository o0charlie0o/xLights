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

@interface XLMetalPreviewView ()

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> queue;
@property (nonatomic, strong) CAMetalLayer *layer;

@property (nonatomic, assign) CVDisplayLinkRef displayLink;
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

@property (nonatomic, assign) NSPoint lastDragPoint;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) BOOL isRightDragging;

@property (nonatomic, assign) CFAbsoluteTime lastFrameTime;

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

    [self setupDepthStencilState];
    [self buildGridPipeline];
    [self buildGridVertices];

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

    _layer = metalLayer;
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
    _layer.contentsScale = scale;
    _contentDirty = YES;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];

    CGFloat scale = self.window.backingScaleFactor ?: 1.0;
    _layer.drawableSize = CGSizeMake(newSize.width * scale, newSize.height * scale);
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
        _layer.contentsScale = scale;

        NSSize frameSize = self.frame.size;
        _layer.drawableSize = CGSizeMake(frameSize.width * scale, frameSize.height * scale);

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
        id<CAMetalDrawable> drawable = [_layer nextDrawable];
        if (!drawable) return;

        CGSize drawableSize = _layer.drawableSize;
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

        CGFloat r, g, b, a;
        [_backgroundColor getRed:&r green:&g blue:&b alpha:&a];
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

        // Model rendering placeholder:
        // The actual model rendering will be driven through XLEngineBridge,
        // which calls into the existing xlMetalGraphicsContext pipeline.
        // That integration requires passing this encoder/commandBuffer to
        // the engine's render pipeline. For now, the view provides the
        // drawable surface and camera state.

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
    return _layer;
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

- (void)setShow3D:(BOOL)show3D {
    _show3D = show3D;
    _cameraController.perspective = show3D;
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
    // Placeholder: will query bounding box from engine bridge
    // For now, frame a default scene volume
    simd_float3 bbMin = {-500.0f, 0.0f, -500.0f};
    simd_float3 bbMax = {500.0f, 500.0f, 500.0f};
    float aspect = (float)_layer.drawableSize.width / (float)_layer.drawableSize.height;
    [_cameraController frameBoundingBoxMin:bbMin max:bbMax aspect:aspect];
    _contentDirty = YES;
}

- (void)highlightModel:(NSString *)modelName {
    _highlightedModelName = modelName;
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

- (void)mouseDragged:(NSEvent *)event {
    NSPoint current = [self convertPoint:event.locationInWindow fromView:nil];
    float dx = (float)(current.x - _lastDragPoint.x);
    float dy = (float)(current.y - _lastDragPoint.y);
    _lastDragPoint = current;
    _isDragging = YES;

    // Left drag = orbit
    [_cameraController orbitByDeltaX:dx deltaY:dy sensitivity:0.005f];
    _contentDirty = YES;

    if ([_delegate respondsToSelector:@selector(previewView:didChangeCamera:)]) {
        [_delegate previewView:self didChangeCamera:_cameraController];
    }
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

- (void)mouseUp:(NSEvent *)event {
    if (!_isDragging && event.clickCount == 1) {
        [self handleClickAtEvent:event];
    }
    _isDragging = NO;
}

- (void)rightMouseUp:(NSEvent *)event {
    _isRightDragging = NO;
}

- (void)mouseExited:(NSEvent *)event {
    _isDragging = NO;
    _isRightDragging = NO;
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
        default:
            [super keyDown:event];
            break;
    }
}

#pragma mark - Hit Testing

- (void)handleClickAtEvent:(NSEvent *)event {
    NSPoint localPoint = [self convertPoint:event.locationInWindow fromView:nil];

    // Convert to normalized device coordinates
    CGSize drawableSize = _layer.drawableSize;
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
}

@end
