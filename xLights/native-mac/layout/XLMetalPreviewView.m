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
#import "XLPolylinePointRenderer.h"
#import "../XLEngineBridge.h"
#import <QuartzCore/CVDisplayLink.h>

static const NSUInteger kDefaultMSAASampleCount = 4;
static const float kGridExtent = 1000.0f;
static const float kDefaultGridSpacing = 50.0f;

static NSString * const kGridVisibleKey = @"XLPreviewGridVisible";
static NSString * const kGridSpacingKey = @"XLPreviewGridSpacing";
static NSString * const kGridCenterAtOriginKey = @"XLPreviewGridCenterAtOrigin";
static NSString * const kGridColorRKey = @"XLPreviewGridColorR";
static NSString * const kGridColorGKey = @"XLPreviewGridColorG";
static NSString * const kGridColorBKey = @"XLPreviewGridColorB";
static NSString * const kGridColorAKey = @"XLPreviewGridColorA";

#pragma mark - Grid Vertex Structures

typedef struct {
    simd_float3 position;
    simd_float4 color;
} XLGridVertex;

typedef struct {
    simd_float2 position;
    simd_float2 texCoord;
} XLTexturedVertex;

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
    int _renderLogCount;
    BOOL _rightMouseDidDrag;
    BOOL _hasAutoFramed;
    dispatch_block_t _pendingReloadWork;
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

// Optimization: track when vertex rebuild is actually needed
@property (nonatomic, assign) BOOL modelVerticesDirty;
@property (nonatomic, assign) NSUInteger lastPixelDataGeneration;
@property (nonatomic, assign) NSUInteger pixelDataGeneration;

// Triple-buffered vertex buffers to avoid GPU/CPU contention on shared storage.
// nextDrawable provides back-pressure: with 3 drawables and 3 ring buffers,
// the oldest inflight frame has completed by the time nextDrawable returns.
@property (nonatomic, assign) NSUInteger currentRingIndex;

@property (nonatomic, assign) NSPoint lastDragPoint;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) BOOL isRightDragging;
@property (nonatomic, assign) BOOL isManipulatingHandle;
@property (nonatomic, assign) XLHandleType activeHandleType;

@property (nonatomic, assign) CFAbsoluteTime lastFrameTime;

@property (nonatomic, strong) XLManipulationHandlesRenderer *handles;

// Polyline point editing
@property (nonatomic, strong) XLPolylinePointRenderer *polylineRenderer;
@property (nonatomic, assign) BOOL isManipulatingPolylinePoint;
@property (nonatomic, assign) XLPolylineHitType polylineHitType;
@property (nonatomic, assign) NSInteger polylineHitIndex;
@property (nonatomic, assign) XLPolylineHitType contextMenuPolylineHitType;
@property (nonatomic, assign) NSInteger contextMenuPolylineHitIndex;

// Background image rendering
@property (nonatomic, strong) id<MTLTexture> backgroundTexture;
@property (nonatomic, strong) id<MTLRenderPipelineState> backgroundPipelineState;
@property (nonatomic, strong) id<MTLBuffer> backgroundVertexBuffer;
@property (nonatomic, strong) id<MTLSamplerState> backgroundSamplerState;
@property (nonatomic, assign) CGSize backgroundImageSize;

// 2D Scrollbars
@property (nonatomic, strong) NSScroller *horizontalScroller;
@property (nonatomic, strong) NSScroller *verticalScroller;
@property (nonatomic, assign) CGRect contentBoundingBox;
@property (nonatomic, assign) BOOL scrollbarsDirty;
@property (nonatomic, strong) NSTimer *scrollbarFadeTimer;

// Multi-selection state
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selectedModelNamesSet;

// Rubber-band selection state
@property (nonatomic, assign) BOOL isRubberBanding;
@property (nonatomic, assign) NSPoint rubberBandOrigin;
@property (nonatomic, assign) NSPoint rubberBandCurrent;
@property (nonatomic, strong) id<MTLRenderPipelineState> rubberBandPipelineState;

- (void)completeRubberBandSelection;

@end

@implementation XLMetalPreviewView {
    // Triple-buffered vertex buffers (C arrays can't be @property)
    id<MTLBuffer> _vertexBufferRing[3];
    NSUInteger _vertexBufferRingCapacity[3]; // in vertices

    // Pre-flattened node data: built once on model reload, read every frame.
    // Eliminates NSDictionary/NSNumber unboxing in the hot render path.
    XLFlatNode *_flatNodes;
    NSUInteger _flatNodeCount;
    XLModelLookup *_flatModelLookups;
    NSUInteger _flatModelCount;
    NSArray<NSString *> *_flatModelNames;         // model name per lookup entry
    NSArray<NSString *> *_flatModelShadowSources;  // ShadowModelFor per lookup (nil if none)
    BOOL _flatNodesDirty;                          // rebuilt on next vertex build if YES
}

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
    // Create the Metal device BEFORE setting wantsLayer, because wantsLayer = YES
    // triggers makeBackingLayer synchronously, which needs _device for the CAMetalLayer.
    _device = MTLCreateSystemDefaultDevice();
    _queue = [_device newCommandQueue];

    self.wantsLayer = YES;

    _sampleCount = kDefaultMSAASampleCount;

    _cameraController = [[XLCameraController alloc] init];
    _show3D = YES;
    _contentDirty = YES;
    _needsRenderFlag = YES;
    _lastFrameTime = CFAbsoluteTimeGetCurrent();

    // Load grid settings from NSUserDefaults (with sensible defaults)
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kGridVisibleKey] != nil) {
        _showGrid = [defaults boolForKey:kGridVisibleKey];
    } else {
        _showGrid = YES;
    }
    float savedSpacing = [defaults floatForKey:kGridSpacingKey];
    _gridSpacing = (savedSpacing > 0.0f) ? savedSpacing : kDefaultGridSpacing;
    if ([defaults objectForKey:kGridCenterAtOriginKey] != nil) {
        _gridCenterAtOrigin = [defaults boolForKey:kGridCenterAtOriginKey];
    } else {
        _gridCenterAtOrigin = YES;
    }
    float cr = [defaults objectForKey:kGridColorRKey] ? [defaults floatForKey:kGridColorRKey] : 0.3f;
    float cg = [defaults objectForKey:kGridColorGKey] ? [defaults floatForKey:kGridColorGKey] : 0.3f;
    float cb = [defaults objectForKey:kGridColorBKey] ? [defaults floatForKey:kGridColorBKey] : 0.3f;
    float ca = [defaults objectForKey:kGridColorAKey] ? [defaults floatForKey:kGridColorAKey] : 0.4f;
    _gridColor = simd_make_float4(cr, cg, cb, ca);

    _backgroundColor = [NSColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:1.0];
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
    _modelVerticesDirty = YES;
    _pixelDataGeneration = 0;
    _lastPixelDataGeneration = 0;
    _currentRingIndex = 0;

    // Pre-flattened node arrays (built on model reload)
    _flatNodes = NULL;
    _flatNodeCount = 0;
    _flatModelLookups = NULL;
    _flatModelCount = 0;
    _flatModelNames = nil;
    _flatModelShadowSources = nil;
    _flatNodesDirty = YES;

    // Background image defaults
    _backgroundBrightness = 1.0f;
    _backgroundAlpha = 1.0f;
    _backgroundImageSize = CGSizeZero;

    // Multi-selection and rubber-band
    _selectedModelNamesSet = [[NSMutableOrderedSet alloc] init];
    _isRubberBanding = NO;

    [self setupDepthStencilState];
    [self buildGridPipeline];
    [self buildGridVertices];
    [self buildRubberBandPipeline];

    // Initialize manipulation handles renderer
    _handles = [[XLManipulationHandlesRenderer alloc] initWithDevice:_device];
    _handles.is3D = _show3D;

    // Initialize polyline point renderer
    _polylineRenderer = [[XLPolylinePointRenderer alloc] initWithDevice:_device];

    // Accept mouse events
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
               owner:self
            userInfo:nil];
    [self addTrackingArea:trackingArea];

    // 2D Scrollbars
    _scrollbarsEnabled = YES;
    _contentBoundingBox = CGRectZero;
    _scrollbarsDirty = YES;
    [self setupScrollbars];
}

- (void)dealloc {
    [_scrollbarFadeTimer invalidate];
    [self stopRenderLoop];
    free(_flatNodes);
    free(_flatModelLookups);
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

    // Only update drawable size with valid dimensions (NSSplitView may
    // initially give us zero width before divider positions are set)
    if (newSize.width > 0 && newSize.height > 0) {
        CGFloat scale = self.window.backingScaleFactor ?: 1.0;
        _mlayer.drawableSize = CGSizeMake(newSize.width * scale, newSize.height * scale);
        _contentDirty = YES;
        _scrollbarsDirty = YES;
    }
}

- (void)setBoundsSize:(NSSize)newSize {
    [super setBoundsSize:newSize];
    _contentDirty = YES;
    _scrollbarsDirty = YES;
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

    // Build a separate pipeline for model points with controllable point size
    NSString *modelShaderSource = @
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "\n"
        "struct ModelVertex {\n"
        "    float3 position [[attribute(0)]];\n"
        "    float4 color    [[attribute(1)]];\n"
        "};\n"
        "\n"
        "struct ModelUniforms {\n"
        "    float4x4 viewProjection;\n"
        "    float pointSize;\n"
        "};\n"
        "\n"
        "struct ModelOut {\n"
        "    float4 position [[position]];\n"
        "    float pointSize [[point_size]];\n"
        "    float4 color;\n"
        "};\n"
        "\n"
        "vertex ModelOut modelVertexShader(\n"
        "    ModelVertex in [[stage_in]],\n"
        "    constant ModelUniforms &uniforms [[buffer(1)]]) {\n"
        "    ModelOut out;\n"
        "    out.position = uniforms.viewProjection * float4(in.position, 1.0);\n"
        "    out.pointSize = uniforms.pointSize;\n"
        "    out.color = in.color;\n"
        "    return out;\n"
        "}\n"
        "\n"
        "fragment float4 modelFragmentShader(ModelOut in [[stage_in]]) {\n"
        "    return in.color;\n"
        "}\n";

    id<MTLLibrary> modelLib = [_device newLibraryWithSource:modelShaderSource options:nil error:&error];
    if (!modelLib) {
        NSLog(@"XLMetalPreviewView: Failed to compile model shaders: %@", error);
        return;
    }

    MTLRenderPipelineDescriptor *modelPipeDesc = [[MTLRenderPipelineDescriptor alloc] init];
    modelPipeDesc.vertexFunction = [modelLib newFunctionWithName:@"modelVertexShader"];
    modelPipeDesc.fragmentFunction = [modelLib newFunctionWithName:@"modelFragmentShader"];
    modelPipeDesc.vertexDescriptor = vertexDesc; // Same vertex layout
    modelPipeDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    modelPipeDesc.colorAttachments[0].blendingEnabled = YES;
    modelPipeDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    modelPipeDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    modelPipeDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    modelPipeDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    modelPipeDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    modelPipeDesc.sampleCount = _sampleCount;

    _modelPipelineState = [_device newRenderPipelineStateWithDescriptor:modelPipeDesc error:&error];
    if (!_modelPipelineState) {
        NSLog(@"XLMetalPreviewView: Failed to create model pipeline: %@", error);
    }

    // Build background image pipeline (textured quad with brightness/alpha)
    NSString *bgShaderSource = @
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "\n"
        "struct BgVertex {\n"
        "    float2 position [[attribute(0)]];\n"
        "    float2 texCoord [[attribute(1)]];\n"
        "};\n"
        "\n"
        "struct BgUniforms {\n"
        "    float brightness;\n"
        "    float alpha;\n"
        "};\n"
        "\n"
        "struct BgOut {\n"
        "    float4 position [[position]];\n"
        "    float2 texCoord;\n"
        "};\n"
        "\n"
        "vertex BgOut bgVertexShader(\n"
        "    BgVertex in [[stage_in]]) {\n"
        "    BgOut out;\n"
        "    out.position = float4(in.position, 0.0, 1.0);\n"
        "    out.texCoord = in.texCoord;\n"
        "    return out;\n"
        "}\n"
        "\n"
        "fragment float4 bgFragmentShader(\n"
        "    BgOut in [[stage_in]],\n"
        "    texture2d<float> bgTexture [[texture(0)]],\n"
        "    sampler bgSampler [[sampler(0)]],\n"
        "    constant BgUniforms &uniforms [[buffer(0)]]) {\n"
        "    float4 texColor = bgTexture.sample(bgSampler, in.texCoord);\n"
        "    texColor.rgb *= uniforms.brightness;\n"
        "    texColor.a *= uniforms.alpha;\n"
        "    return texColor;\n"
        "}\n";

    id<MTLLibrary> bgLib = [_device newLibraryWithSource:bgShaderSource options:nil error:&error];
    if (!bgLib) {
        NSLog(@"XLMetalPreviewView: Failed to compile background shaders: %@", error);
        return;
    }

    MTLVertexDescriptor *bgVertexDesc = [[MTLVertexDescriptor alloc] init];
    bgVertexDesc.attributes[0].format = MTLVertexFormatFloat2;
    bgVertexDesc.attributes[0].offset = 0;
    bgVertexDesc.attributes[0].bufferIndex = 0;
    bgVertexDesc.attributes[1].format = MTLVertexFormatFloat2;
    bgVertexDesc.attributes[1].offset = sizeof(simd_float2);
    bgVertexDesc.attributes[1].bufferIndex = 0;
    bgVertexDesc.layouts[0].stride = sizeof(XLTexturedVertex);
    bgVertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    MTLRenderPipelineDescriptor *bgPipeDesc = [[MTLRenderPipelineDescriptor alloc] init];
    bgPipeDesc.vertexFunction = [bgLib newFunctionWithName:@"bgVertexShader"];
    bgPipeDesc.fragmentFunction = [bgLib newFunctionWithName:@"bgFragmentShader"];
    bgPipeDesc.vertexDescriptor = bgVertexDesc;
    bgPipeDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    bgPipeDesc.colorAttachments[0].blendingEnabled = YES;
    bgPipeDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    bgPipeDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    bgPipeDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    bgPipeDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    bgPipeDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    bgPipeDesc.sampleCount = _sampleCount;

    _backgroundPipelineState = [_device newRenderPipelineStateWithDescriptor:bgPipeDesc error:&error];
    if (!_backgroundPipelineState) {
        NSLog(@"XLMetalPreviewView: Failed to create background pipeline: %@", error);
    }

    // Fullscreen quad in NDC for background rendering
    XLTexturedVertex bgQuad[6] = {
        { .position = {-1.0f, -1.0f}, .texCoord = {0.0f, 1.0f} },
        { .position = { 1.0f, -1.0f}, .texCoord = {1.0f, 1.0f} },
        { .position = {-1.0f,  1.0f}, .texCoord = {0.0f, 0.0f} },
        { .position = {-1.0f,  1.0f}, .texCoord = {0.0f, 0.0f} },
        { .position = { 1.0f, -1.0f}, .texCoord = {1.0f, 1.0f} },
        { .position = { 1.0f,  1.0f}, .texCoord = {1.0f, 0.0f} },
    };
    _backgroundVertexBuffer = [_device newBufferWithBytes:bgQuad
                                                    length:sizeof(bgQuad)
                                                   options:MTLResourceStorageModeShared];
    [_backgroundVertexBuffer setLabel:@"BackgroundQuadVertices"];

    // Sampler for background texture
    MTLSamplerDescriptor *samplerDesc = [[MTLSamplerDescriptor alloc] init];
    samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
    samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
    samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    _backgroundSamplerState = [_device newSamplerStateWithDescriptor:samplerDesc];
}

- (void)buildRubberBandPipeline {
    NSError *error = nil;

    NSString *shaderSource = @
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "\n"
        "struct RBVertex {\n"
        "    float2 position [[attribute(0)]];\n"
        "    float4 color    [[attribute(1)]];\n"
        "};\n"
        "\n"
        "struct RBOut {\n"
        "    float4 position [[position]];\n"
        "    float4 color;\n"
        "};\n"
        "\n"
        "vertex RBOut rbVertexShader(\n"
        "    RBVertex in [[stage_in]]) {\n"
        "    RBOut out;\n"
        "    out.position = float4(in.position, 0.0, 1.0);\n"
        "    out.color = in.color;\n"
        "    return out;\n"
        "}\n"
        "\n"
        "fragment float4 rbFragmentShader(RBOut in [[stage_in]]) {\n"
        "    return in.color;\n"
        "}\n";

    id<MTLLibrary> library = [_device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"XLMetalPreviewView: Failed to compile rubber-band shaders: %@", error);
        return;
    }

    MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
    vertexDesc.attributes[0].format = MTLVertexFormatFloat2;
    vertexDesc.attributes[0].offset = 0;
    vertexDesc.attributes[0].bufferIndex = 0;
    vertexDesc.attributes[1].format = MTLVertexFormatFloat4;
    vertexDesc.attributes[1].offset = sizeof(simd_float2);
    vertexDesc.attributes[1].bufferIndex = 0;
    vertexDesc.layouts[0].stride = sizeof(simd_float2) + sizeof(simd_float4);
    vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    MTLRenderPipelineDescriptor *pipeDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipeDesc.vertexFunction = [library newFunctionWithName:@"rbVertexShader"];
    pipeDesc.fragmentFunction = [library newFunctionWithName:@"rbFragmentShader"];
    pipeDesc.vertexDescriptor = vertexDesc;
    pipeDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipeDesc.colorAttachments[0].blendingEnabled = YES;
    pipeDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipeDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipeDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipeDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipeDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    pipeDesc.sampleCount = _sampleCount;

    _rubberBandPipelineState = [_device newRenderPipelineStateWithDescriptor:pipeDesc error:&error];
    if (!_rubberBandPipelineState) {
        NSLog(@"XLMetalPreviewView: Failed to create rubber-band pipeline: %@", error);
    }
}

- (void)buildGridVertices {
    NSMutableData *vertexData = [[NSMutableData alloc] init];

    float spacing = _gridSpacing > 0.0f ? _gridSpacing : kDefaultGridSpacing;
    float halfExtent = kGridExtent;
    float fadeStart = halfExtent * 0.6f;
    NSInteger lineCount = (NSInteger)(2.0f * halfExtent / spacing) + 1;
    // Cap at a reasonable maximum to avoid excessive vertex data
    if (lineCount > 201) lineCount = 201;

    float gridR = _gridColor.x;
    float gridG = _gridColor.y;
    float gridB = _gridColor.z;
    float gridBaseAlpha = _gridColor.w;

    float centerOffset = 0.0f;
    if (!_gridCenterAtOrigin) {
        centerOffset = fmodf(_cameraController.target.x, spacing);
    }

    for (NSInteger i = 0; i < lineCount; i++) {
        float offset = (i - (lineCount - 1) / 2.0f) * spacing + centerOffset;

        float alphaStart = [self gridAlphaForDistance:fabsf(offset) fadeStart:fadeStart fadeEnd:halfExtent baseAlpha:gridBaseAlpha];

        // Line along Z axis
        XLGridVertex v0 = {
            .position = {offset, 0.0f, -halfExtent},
            .color = {gridR, gridG, gridB, 0.0f}
        };
        XLGridVertex v1 = {
            .position = {offset, 0.0f, 0.0f},
            .color = {gridR, gridG, gridB, alphaStart}
        };
        XLGridVertex v2 = {
            .position = {offset, 0.0f, halfExtent},
            .color = {gridR, gridG, gridB, 0.0f}
        };

        [vertexData appendBytes:&v0 length:sizeof(XLGridVertex)];
        [vertexData appendBytes:&v1 length:sizeof(XLGridVertex)];
        [vertexData appendBytes:&v1 length:sizeof(XLGridVertex)];
        [vertexData appendBytes:&v2 length:sizeof(XLGridVertex)];

        // Line along X axis
        XLGridVertex h0 = {
            .position = {-halfExtent, 0.0f, offset},
            .color = {gridR, gridG, gridB, 0.0f}
        };
        XLGridVertex h1 = {
            .position = {0.0f, 0.0f, offset},
            .color = {gridR, gridG, gridB, alphaStart}
        };
        XLGridVertex h2 = {
            .position = {halfExtent, 0.0f, offset},
            .color = {gridR, gridG, gridB, 0.0f}
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

- (float)gridAlphaForDistance:(float)dist fadeStart:(float)fadeStart fadeEnd:(float)fadeEnd baseAlpha:(float)baseAlpha {
    if (dist <= fadeStart) return baseAlpha;
    if (dist >= fadeEnd) return 0.0f;
    float t = (dist - fadeStart) / (fadeEnd - fadeStart);
    return baseAlpha * (1.0f - t);
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
    // Don't clear _contentDirty here — renderFrame clears it after a successful render.
    // This ensures we retry if nextDrawable returns nil (e.g. window not yet visible).

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    NSTimeInterval dt = now - _lastFrameTime;
    _lastFrameTime = now;

    if (_cameraController.isAnimating) {
        BOOL stillAnimating = [_cameraController updateAnimation:dt];
        if (stillAnimating) {
            _contentDirty = YES;
            _scrollbarsDirty = YES;
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self renderFrame];
        if (self->_scrollbarsDirty) {
            self->_scrollbarsDirty = NO;
            [self updateScrollbars];
        }
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
        if (frameSize.width > 0 && frameSize.height > 0) {
            _mlayer.drawableSize = CGSizeMake(frameSize.width * scale, frameSize.height * scale);
        }

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
        CGSize ds = _mlayer.drawableSize;
        if (ds.width <= 0 || ds.height <= 0) return;

        id<CAMetalDrawable> drawable = [_mlayer nextDrawable];
        if (!drawable) {
            if (_renderLogCount < 5) {
                NSLog(@"[HousePreview] renderFrame: NO drawable! mlayer=%@ device=%@ drawableSize=%@",
                      _mlayer, _mlayer.device, NSStringFromSize(NSSizeFromCGSize(_mlayer.drawableSize)));
                _renderLogCount++;
            }
            return;
        }

        // Successfully got a drawable — clear the content dirty flag
        _contentDirty = NO;

        // Rebuild model vertices if selection/highlight changed OR pixel data updated.
        // Pixel data updates (from setRenderedPixels:) increment _pixelDataGeneration;
        // we coalesce all updates since the last render into a single rebuild here.
        BOOL pixelDataChanged = _showEffectColors && _lastPixelDataGeneration != _pixelDataGeneration;
        if (_modelVerticesDirty || pixelDataChanged) {
            _modelVerticesDirty = NO;
            _lastPixelDataGeneration = _pixelDataGeneration;
            [self buildModelVerticesWithEffectColors:_showEffectColors];
        }

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

        // Render background image (behind everything else)
        if (_backgroundTexture && _backgroundPipelineState && _backgroundVertexBuffer) {
            [encoder pushDebugGroup:@"BackgroundImage"];
            [encoder setRenderPipelineState:_backgroundPipelineState];
            [encoder setVertexBuffer:_backgroundVertexBuffer offset:0 atIndex:0];

            struct {
                float brightness;
                float alpha;
            } bgUniforms;
            bgUniforms.brightness = _backgroundBrightness;
            bgUniforms.alpha = _backgroundAlpha;

            [encoder setFragmentBytes:&bgUniforms length:sizeof(bgUniforms) atIndex:0];
            [encoder setFragmentTexture:_backgroundTexture atIndex:0];
            [encoder setFragmentSamplerState:_backgroundSamplerState atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
            [encoder popDebugGroup];
        }

        // Camera matrices
        float aspect = width / height;
        simd_float4x4 viewMatrix = _cameraController.viewMatrix;
        simd_float4x4 projMatrix = [_cameraController projectionMatrixForAspect:aspect];
        simd_float4x4 viewProjection = simd_mul(projMatrix, viewMatrix);

        // Render ground grid (3D) or 2D grid overlay
        if (_showGrid && _gridPipelineState) {
            [encoder pushDebugGroup:@"Grid"];
            [encoder setRenderPipelineState:_gridPipelineState];
            [encoder setVertexBuffer:_gridVertexBuffer offset:0 atIndex:0];
            [encoder setVertexBytes:&viewProjection length:sizeof(simd_float4x4) atIndex:1];
            [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:_gridVertexCount];
            [encoder popDebugGroup];
        }

        // Render model nodes as points
        if (_modelVertexBuffer && _modelVertexCount > 0 && _modelPipelineState) {
            [encoder pushDebugGroup:@"Models"];
            [encoder setRenderPipelineState:_modelPipelineState];
            [encoder setVertexBuffer:_modelVertexBuffer offset:0 atIndex:0];

            // Pack viewProjection + pointSize into uniforms buffer
            struct {
                simd_float4x4 viewProjection;
                float pointSize;
            } modelUniforms;
            modelUniforms.viewProjection = viewProjection;
            modelUniforms.pointSize = 2.0f;
            [encoder setVertexBytes:&modelUniforms length:sizeof(modelUniforms) atIndex:1];

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

        // Render polyline point handles
        if (_polylineRenderer && _polylineRenderer.active && _selectedModelName) {
            [_polylineRenderer renderWithEncoder:encoder
                                 viewProjection:viewProjection
                                           zoom:(float)_cameraController.distance
                                          scale:1];
        }

        // Render multi-selection bounding boxes for non-primary selected models
        if (_selectedModelNamesSet.count > 1 && _handles) {
            [self renderMultiSelectionBoundsWithEncoder:encoder
                                        viewProjection:viewProjection
                                                  zoom:(float)_cameraController.distance];
        }

        // Render rubber-band selection overlay
        [self renderRubberBandWithEncoder:encoder drawableSize:drawableSize];

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
    _scrollbarsDirty = YES;
}

- (void)setShowGrid:(BOOL)showGrid {
    _showGrid = showGrid;
    _contentDirty = YES;
    [[NSUserDefaults standardUserDefaults] setBool:showGrid forKey:kGridVisibleKey];
}

- (void)setGridSpacing:(float)gridSpacing {
    if (gridSpacing < 1.0f) gridSpacing = 1.0f;
    _gridSpacing = gridSpacing;
    [self buildGridVertices];
    _contentDirty = YES;
    [[NSUserDefaults standardUserDefaults] setFloat:gridSpacing forKey:kGridSpacingKey];
}

- (void)setGridCenterAtOrigin:(BOOL)gridCenterAtOrigin {
    _gridCenterAtOrigin = gridCenterAtOrigin;
    [self buildGridVertices];
    _contentDirty = YES;
    [[NSUserDefaults standardUserDefaults] setBool:gridCenterAtOrigin forKey:kGridCenterAtOriginKey];
}

- (void)setGridColor:(simd_float4)gridColor {
    _gridColor = gridColor;
    [self buildGridVertices];
    _contentDirty = YES;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setFloat:gridColor.x forKey:kGridColorRKey];
    [defaults setFloat:gridColor.y forKey:kGridColorGKey];
    [defaults setFloat:gridColor.z forKey:kGridColorBKey];
    [defaults setFloat:gridColor.w forKey:kGridColorAKey];
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
    for (NSUInteger mi = 0; mi < _flatModelCount; mi++) {
        XLModelLookup *lookup = &_flatModelLookups[mi];
        if (!lookup->hasBounds) continue;

        hasModels = YES;
        bbMin.x = fminf(bbMin.x, lookup->boundsMinX);
        bbMin.y = fminf(bbMin.y, lookup->boundsMinY);
        bbMin.z = fminf(bbMin.z, lookup->boundsMinZ);
        bbMax.x = fmaxf(bbMax.x, lookup->boundsMaxX);
        bbMax.y = fmaxf(bbMax.y, lookup->boundsMaxY);
        bbMax.z = fmaxf(bbMax.z, lookup->boundsMaxZ);
    }

    if (!hasModels) {
        // Default scene volume if no models
        bbMin = (simd_float3){-500.0f, 0.0f, -500.0f};
        bbMax = (simd_float3){500.0f, 500.0f, 500.0f};
    }

    // Apply frame padding (expands bounding box for breathing room)
    if (_framePadding > 0.0f) {
        simd_float3 extents = bbMax - bbMin;
        simd_float3 pad = extents * _framePadding;
        bbMin -= pad;
        bbMax += pad;
    }

    float aspect = (float)_mlayer.drawableSize.width / (float)_mlayer.drawableSize.height;
    [_cameraController frameBoundingBoxMin:bbMin max:bbMax aspect:aspect];
    _contentDirty = YES;
}

- (void)highlightModel:(NSString *)modelName {
    _highlightedModelName = modelName;
    _modelVerticesDirty = YES;
    _contentDirty = YES;
}

- (void)reloadModels {
    if (!_engineBridge) {
        _modelDataCache = @[];
        _flatNodesDirty = YES;
        _modelVertexBuffer = nil;
        _modelVertexCount = 0;
        for (int i = 0; i < 3; i++) {
            _vertexBufferRing[i] = nil;
            _vertexBufferRingCapacity[i] = 0;
        }
        _contentDirty = YES;
        return;
    }

    NSSet<NSString *> *filter = _visibleModelFilter;
    BOOL hasFilter = (filter != nil && filter.count > 0);

    // Use batch API: single bridge call fetches info+nodes+bounds for all models.
    // For filtered views (sidebar), pass only the requested names.
    NSArray<NSDictionary *> *allData;
    if (hasFilter) {
        allData = [_engineBridge getAllModelDataForNames:[filter allObjects]];
    } else {
        allData = [_engineBridge getAllModelData];
    }

    // Apply LayoutGroup filter for full-view mode (not sidebar filtered views)
    NSMutableArray<NSDictionary *> *modelData;
    if (!hasFilter) {
        modelData = [NSMutableArray arrayWithCapacity:allData.count];
        for (NSDictionary *entry in allData) {
            NSDictionary *info = entry[@"info"];
            NSString *layoutGroup = info[@"LayoutGroup"];
            if (layoutGroup && layoutGroup.length > 0 &&
                ![layoutGroup isEqualToString:@"Default"] &&
                ![layoutGroup isEqualToString:@"All Previews"]) {
                continue;
            }
            [modelData addObject:entry];
        }
    } else {
        modelData = [allData mutableCopy];
    }

    _modelDataCache = [modelData copy];
    _flatNodesDirty = YES;
    [self buildModelVertices];
    _contentDirty = YES;
    _scrollbarsDirty = YES;

    // Auto-frame camera on first successful model load
    if (!_hasAutoFramed && _modelVertexCount > 0) {
        _hasAutoFramed = YES;
        [self frameAllModels];
    }
}

- (void)loadModelData:(NSArray<NSDictionary *> *)modelData {
    _modelDataCache = [modelData copy];
    _flatNodesDirty = YES;
    [self buildModelVertices];
    _contentDirty = YES;
    _scrollbarsDirty = YES;
}

- (void)scheduleReloadModels {
    if (_pendingReloadWork) {
        dispatch_block_cancel(_pendingReloadWork);
    }
    __weak typeof(self) weakSelf = self;
    _pendingReloadWork = dispatch_block_create(0, ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf->_pendingReloadWork = nil;
            [strongSelf reloadModels];
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(16 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), _pendingReloadWork);
}

- (void)cancelPendingReload {
    if (_pendingReloadWork) {
        dispatch_block_cancel(_pendingReloadWork);
        _pendingReloadWork = nil;
    }
}

- (void)setSelectedSubmodelNodeIndices:(NSDictionary<NSString *, NSIndexSet *> *)selectedSubmodelNodeIndices {
    _selectedSubmodelNodeIndices = [selectedSubmodelNodeIndices copy];
    _modelVerticesDirty = YES;
    _contentDirty = YES;
}

/// Look up the actual world-space bounds for a model from the vertex data cache.
/// Returns nil if the model is not found or has no bounds.
- (NSDictionary *)cachedBoundsForModel:(NSString *)modelName {
    if (!modelName) return nil;
    for (NSUInteger mi = 0; mi < _flatModelCount; mi++) {
        if ([_flatModelNames[mi] isEqualToString:modelName]) {
            XLModelLookup *lookup = &_flatModelLookups[mi];
            if (!lookup->hasBounds) break;
            return @{
                @"minX": @(lookup->boundsMinX), @"maxX": @(lookup->boundsMaxX),
                @"minY": @(lookup->boundsMinY), @"maxY": @(lookup->boundsMaxY),
                @"minZ": @(lookup->boundsMinZ), @"maxZ": @(lookup->boundsMaxZ),
            };
        }
    }
    return nil;
}

/// Compute renderWidth/renderHeight/renderDepth from actual vertex bounds when available.
/// Falls back to RenderWidth/RenderHeight from model info if no cached bounds exist.
/// For complex models (MegaTree, stars, wreaths), the render buffer dimensions
/// may not match the actual visual extent, so we use the larger of the two.
- (void)adjustRenderDimensionsForModel:(NSString *)modelName
                              position:(simd_float3)position
                                 scale:(simd_float3)scale
                           renderWidth:(float *)renderWidth
                          renderHeight:(float *)renderHeight
                           renderDepth:(float *)renderDepth {
    NSDictionary *bounds = [self cachedBoundsForModel:modelName];
    if (!bounds) return;

    float minX = [bounds[@"minX"] floatValue];
    float maxX = [bounds[@"maxX"] floatValue];
    float minY = [bounds[@"minY"] floatValue];
    float maxY = [bounds[@"maxY"] floatValue];
    float minZ = [bounds[@"minZ"] floatValue];
    float maxZ = [bounds[@"maxZ"] floatValue];

    // Compute the world-space extent of the model from its actual vertices
    float worldWidth = maxX - minX;
    float worldHeight = maxY - minY;
    float worldDepth = maxZ - minZ;

    // Convert world-space extent back to local-space (undo scale) for the handles renderer
    float localWidth = (scale.x > 0.001f) ? worldWidth / scale.x : worldWidth;
    float localHeight = (scale.y > 0.001f) ? worldHeight / scale.y : worldHeight;
    float localDepth = (scale.z > 0.001f) ? worldDepth / scale.z : worldDepth;

    // Use the larger of RenderWidth/Height and actual vertex extent
    if (localWidth > *renderWidth) *renderWidth = localWidth;
    if (localHeight > *renderHeight) *renderHeight = localHeight;
    if (localDepth > *renderDepth) *renderDepth = localDepth;
}

- (void)selectModel:(NSString *)modelName {
    _selectedModelName = modelName;
    _selectedSubmodelNodeIndices = nil;

    // Update multi-selection set: single select replaces all
    [_selectedModelNamesSet removeAllObjects];
    if (modelName) {
        [_selectedModelNamesSet addObject:modelName];
    }

    _modelVerticesDirty = YES;

    if (!modelName) {
        [self clearModelSelection];
        return;
    }

    // Get model info and set up manipulation handles
    NSDictionary *info = [_engineBridge getModelInfo:modelName];

    if (!info) {
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

    // Use model-space render dimensions from buffer dims (matches legacy RenderWi/RenderHt).
    // These are the intrinsic model size before scale is applied.
    float renderWidth = [info[@"RenderWidth"] floatValue];
    float renderHeight = [info[@"RenderHeight"] floatValue];
    float renderDepth = [info[@"RenderDepth"] floatValue];
    if (renderWidth < 0.001f) renderWidth = 1.0f;
    if (renderHeight < 0.001f) renderHeight = 1.0f;
    if (renderDepth < 0.001f) renderDepth = 2.0f;

    // Adjust render dimensions using actual vertex bounds for complex model types
    [self adjustRenderDimensionsForModel:modelName
                                position:(simd_float3){posX, posY, posZ}
                                   scale:(simd_float3){scaleX, scaleY, scaleZ}
                             renderWidth:&renderWidth
                            renderHeight:&renderHeight
                             renderDepth:&renderDepth];

    // Bounding box in local space, centered at origin
    simd_float3 bbMin = simd_make_float3(-renderWidth/2, -renderHeight/2, -renderDepth/2);
    simd_float3 bbMax = simd_make_float3(renderWidth/2, renderHeight/2, renderDepth/2);

    // Check if locked
    BOOL isLocked = [info[@"Locked"] boolValue];

    // Check if supports Z scaling (3D models)
    BOOL supportsZScaling = _show3D && (renderDepth > 2.1f);

    [self setModelTransformWithPosition:(simd_float3){posX, posY, posZ}
                                  scale:(simd_float3){scaleX, scaleY, scaleZ}
                               rotation:(simd_float3){rotX, rotY, rotZ}
                         boundingBoxMin:bbMin
                         boundingBoxMax:bbMax
                            renderWidth:renderWidth
                           renderHeight:renderHeight
                            renderDepth:renderDepth
                               isLocked:isLocked
                       supportsZScaling:supportsZScaling];

    // Load polyline points if this is a polyline model
    [self loadPolylinePointsForModel:modelName];

    _contentDirty = YES;

    if ([_delegate respondsToSelector:@selector(previewView:didSelectModel:)]) {
        [_delegate previewView:self didSelectModel:modelName];
    }
}

- (void)buildModelVertices {
    [self buildModelVerticesWithEffectColors:_showEffectColors];
}

/// Build pre-flattened C arrays from the NSDictionary model data cache.
/// Called once per model reload — extracts position, buffer coords, bounds,
/// and shadow source info so the per-frame vertex builder never touches
/// NSDictionary or NSNumber.
- (void)rebuildFlatNodeArrays {
    // Free previous allocations
    free(_flatNodes);
    _flatNodes = NULL;
    free(_flatModelLookups);
    _flatModelLookups = NULL;
    _flatNodeCount = 0;
    _flatModelCount = 0;
    _flatModelNames = nil;
    _flatModelShadowSources = nil;
    _flatNodesDirty = NO;

    NSUInteger modelCount = _modelDataCache.count;
    if (modelCount == 0) return;

    // First pass: count total nodes
    NSUInteger totalNodes = 0;
    for (NSDictionary *modelData in _modelDataCache) {
        NSArray *nodes = modelData[@"nodes"];
        totalNodes += nodes.count;
    }

    if (totalNodes == 0 && modelCount == 0) return;

    // Allocate flat arrays
    _flatNodes = (XLFlatNode *)malloc(totalNodes * sizeof(XLFlatNode));
    _flatModelLookups = (XLModelLookup *)calloc(modelCount, sizeof(XLModelLookup));
    if (!_flatNodes || !_flatModelLookups) {
        free(_flatNodes);
        free(_flatModelLookups);
        _flatNodes = NULL;
        _flatModelLookups = NULL;
        return;
    }

    NSMutableArray<NSString *> *names = [[NSMutableArray alloc] initWithCapacity:modelCount];
    NSMutableArray<NSString *> *shadowSources = [[NSMutableArray alloc] initWithCapacity:modelCount];

    NSUInteger nodeWriteIdx = 0;
    NSUInteger modelIdx = 0;

    for (NSDictionary *modelData in _modelDataCache) {
        NSArray<NSDictionary *> *nodes = modelData[@"nodes"];
        NSString *modelName = modelData[@"name"] ?: @"";
        [names addObject:modelName];

        // Extract ShadowModelFor from model info (used during playback)
        NSDictionary *mInfo = modelData[@"info"];
        NSString *shadowFor = nil;
        if (mInfo != nil) {
            id shadowVal = mInfo[@"ShadowModelFor"];
            if ([shadowVal isKindOfClass:[NSString class]] && [shadowVal length] > 0) {
                shadowFor = shadowVal;
            }
        }
        [shadowSources addObject:shadowFor ?: (id)[NSNull null]];

        // Fill model lookup
        XLModelLookup *lookup = &_flatModelLookups[modelIdx];
        lookup->nodeStart = nodeWriteIdx;
        lookup->nodeCount = nodes.count;
        lookup->pixelWidth = 0;
        lookup->pixelHeight = 0;

        // Extract bounds
        NSDictionary *bounds = modelData[@"bounds"];
        if (bounds && bounds.count > 0) {
            lookup->hasBounds = YES;
            lookup->boundsMinX = [bounds[@"minX"] floatValue];
            lookup->boundsMinY = [bounds[@"minY"] floatValue];
            lookup->boundsMinZ = [bounds[@"minZ"] floatValue];
            lookup->boundsMaxX = [bounds[@"maxX"] floatValue];
            lookup->boundsMaxY = [bounds[@"maxY"] floatValue];
            lookup->boundsMaxZ = [bounds[@"maxZ"] floatValue];
        } else {
            lookup->hasBounds = NO;
        }

        // Extract each node's position and buffer coordinates (the expensive part)
        uint16_t mIdx16 = (uint16_t)(modelIdx & 0xFFFF);
        for (NSDictionary *node in nodes) {
            XLFlatNode *fn = &_flatNodes[nodeWriteIdx];
            fn->position = (simd_float3){
                [node[@"x"] floatValue],
                [node[@"y"] floatValue],
                [node[@"z"] floatValue],
            };
            fn->bufX = (int16_t)[node[@"bufX"] integerValue];
            fn->bufY = (int16_t)[node[@"bufY"] integerValue];
            fn->modelIndex = mIdx16;
            fn->_pad = 0;
            nodeWriteIdx++;
        }

        modelIdx++;
    }

    _flatNodeCount = nodeWriteIdx;
    _flatModelCount = modelIdx;
    _flatModelNames = [names copy];
    _flatModelShadowSources = [shadowSources copy];
}

- (void)buildModelVerticesWithEffectColors:(BOOL)useEffectColors {
    // Rebuild flat arrays if they are stale (model data changed)
    if (_flatNodesDirty || _flatNodes == NULL) {
        [self rebuildFlatNodeArrays];
    }

    if (_flatNodeCount == 0) {
        _modelVertexBuffer = nil;
        _modelVertexCount = 0;
        return;
    }

    NSUInteger totalNodes = _flatNodeCount;

    // Triple-buffering: pick the next ring slot so the GPU can still be
    // reading from previous slots while we write to this one.
    NSUInteger ringIdx = _currentRingIndex;
    _currentRingIndex = (_currentRingIndex + 1) % 3;

    // Grow the ring slot if needed (1.5x headroom to reduce reallocations)
    if (_vertexBufferRing[ringIdx] == nil || _vertexBufferRingCapacity[ringIdx] < totalNodes) {
        NSUInteger newCapacity = (NSUInteger)(totalNodes * 1.5);
        _vertexBufferRing[ringIdx] = [_device newBufferWithLength:newCapacity * sizeof(XLGridVertex)
                                                          options:MTLResourceStorageModeShared];
        [_vertexBufferRing[ringIdx] setLabel:@"ModelVertices"];
        _vertexBufferRingCapacity[ringIdx] = newCapacity;
    }

    XLGridVertex *vertices = (XLGridVertex *)_vertexBufferRing[ringIdx].contents;

    // Single lock around entire model loop to avoid per-model lock/unlock cycles.
    if (useEffectColors) {
        [_pixelDataLock lock];
    }

    for (NSUInteger mi = 0; mi < _flatModelCount; mi++) {
        XLModelLookup *lookup = &_flatModelLookups[mi];
        NSString *modelName = _flatModelNames[mi];

        // Look up rendered pixel data for this model
        NSData *pixelData = nil;
        NSUInteger pixelWidth = 0;
        NSUInteger pixelHeight = 0;

        if (useEffectColors) {
            pixelData = _renderedPixelData[modelName];
            pixelWidth = [_renderedPixelWidths[modelName] unsignedIntegerValue];
            pixelHeight = [_renderedPixelHeights[modelName] unsignedIntegerValue];

            // Shadow models mirror their source model's pixel data during playback
            if (pixelData == nil) {
                id shadowVal = _flatModelShadowSources[mi];
                if (shadowVal != (id)[NSNull null]) {
                    NSString *shadowFor = (NSString *)shadowVal;
                    pixelData = _renderedPixelData[shadowFor];
                    pixelWidth = [_renderedPixelWidths[shadowFor] unsignedIntegerValue];
                    pixelHeight = [_renderedPixelHeights[shadowFor] unsignedIntegerValue];
                }
            }
        }

        const uint8_t *pixels = (const uint8_t *)pixelData.bytes;
        NSUInteger pixelDataLength = pixelData.length;

        // Determine color - highlighted and selected models get brighter colors
        BOOL isHighlighted = [modelName isEqualToString:_highlightedModelName];
        BOOL isSelected = [modelName isEqualToString:_selectedModelName];
        BOOL isMultiSelected = !isSelected && [_selectedModelNamesSet containsObject:modelName];

        // Check if this model has a submodel node index restriction
        NSIndexSet *submodelIndices = _selectedSubmodelNodeIndices[modelName];
        BOOL hasSubmodelSelection = (isSelected || isMultiSelected) && submodelIndices != nil;

        float baseGray = 0.6f;
        if (isSelected && !hasSubmodelSelection) {
            baseGray = 1.0f;
        } else if (isMultiSelected) {
            baseGray = 0.95f;
        } else if (isHighlighted) {
            baseGray = 0.9f;
        }

        // Use hue based on model index for visual distinction (fallback color)
        float hue = fmod((float)mi * 0.15f, 1.0f);
        float defaultR, defaultG, defaultB;
        [self hueToRGB:hue r:&defaultR g:&defaultG b:&defaultB];

        // Iterate pre-flattened nodes — no NSDictionary/NSNumber unboxing
        NSUInteger nodeStart = lookup->nodeStart;
        NSUInteger nodeEnd = nodeStart + lookup->nodeCount;
        for (NSUInteger ni = nodeStart; ni < nodeEnd; ni++) {
            XLFlatNode *fn = &_flatNodes[ni];
            XLGridVertex *v = &vertices[ni];

            v->position = fn->position;

            int16_t bufX = fn->bufX;
            int16_t bufY = fn->bufY;

            // Determine if this node should render pure white
            NSUInteger nodeLocalIdx = ni - nodeStart;
            BOOL nodeIsWhite = NO;
            if (hasSubmodelSelection) {
                nodeIsWhite = [submodelIndices containsIndex:nodeLocalIdx];
            } else if (isSelected || isMultiSelected) {
                nodeIsWhite = YES;
            }

            if (nodeIsWhite) {
                v->color = (simd_float4){1.0f, 1.0f, 1.0f, 1.0f};
            } else {
                BOOL gotPixelColor = NO;
                if (pixels && pixelWidth > 0 && pixelHeight > 0) {
                    if (bufX >= 0 && bufX < (int16_t)pixelWidth &&
                        bufY >= 0 && bufY < (int16_t)pixelHeight) {
                        NSUInteger pixelIdx = ((NSUInteger)bufY * pixelWidth + (NSUInteger)bufX) * 4;
                        if (pixelIdx + 3 < pixelDataLength) {
                            float r = pixels[pixelIdx + 0] / 255.0f;
                            float g = pixels[pixelIdx + 1] / 255.0f;
                            float b = pixels[pixelIdx + 2] / 255.0f;
                            v->color = (simd_float4){r, g, b, 1.0f};
                            gotPixelColor = YES;
                        }
                    }
                }

                if (!gotPixelColor) {
                    if (useEffectColors) {
                        v->color = (simd_float4){0.0f, 0.0f, 0.0f, 1.0f};
                    } else {
                        v->color = (simd_float4){
                            baseGray * (0.3f + 0.7f * defaultR),
                            baseGray * (0.3f + 0.7f * defaultG),
                            baseGray * (0.3f + 0.7f * defaultB),
                            1.0f
                        };
                    }
                }
            }
        }
    }

    if (useEffectColors) {
        [_pixelDataLock unlock];
    }

    _modelVertexCount = totalNodes;
    _modelVertexBuffer = _vertexBufferRing[ringIdx];
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

    // Don't rebuild vertices here — just mark dirty and let renderFrame
    // coalesce all pixel data updates into a single vertex rebuild per render.
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
        _renderedPixelData[modelName] = pixelData;
        _renderedPixelWidths[modelName] = @(width);
        _renderedPixelHeights[modelName] = @(height);
    } else {
        [_renderedPixelData removeObjectForKey:modelName];
        [_renderedPixelWidths removeObjectForKey:modelName];
        [_renderedPixelHeights removeObjectForKey:modelName];
    }
    // Increment generation counter to signal pixel data has changed
    _pixelDataGeneration++;
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
    _isRightDragging = NO;
    _rightMouseDidDrag = NO;
}

- (void)rightMouseDragged:(NSEvent *)event {
    NSPoint current = [self convertPoint:event.locationInWindow fromView:nil];
    float dx = (float)(current.x - _lastDragPoint.x);
    float dy = (float)(current.y - _lastDragPoint.y);
    _lastDragPoint = current;

    _isRightDragging = YES;
    _rightMouseDidDrag = YES;

    // Right drag = pan
    [_cameraController panByDeltaX:dx deltaY:dy sensitivity:0.002f];
    _contentDirty = YES;
    _scrollbarsDirty = YES;

    if ([_delegate respondsToSelector:@selector(previewView:didChangeCamera:)]) {
        [_delegate previewView:self didChangeCamera:_cameraController];
    }
}

- (void)rightMouseUp:(NSEvent *)event {
    _isRightDragging = NO;

    if (!_rightMouseDidDrag) {
        [self showContextMenuForEvent:event];
    }
    _rightMouseDidDrag = NO;
}

- (void)mouseExited:(NSEvent *)event {
    _isDragging = NO;
    _isRightDragging = NO;
    _isManipulatingHandle = NO;
    _isRubberBanding = NO;
}

- (void)scrollWheel:(NSEvent *)event {
    // Cmd+scroll = zoom (works with both trackpad and mouse)
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        float delta = (float)event.scrollingDeltaY;
        float sensitivity = event.hasPreciseScrollingDeltas ? 0.01f : 0.05f;
        [_cameraController zoomByDelta:-delta sensitivity:sensitivity];
        _contentDirty = YES;
        _scrollbarsDirty = YES;
        if ([_delegate respondsToSelector:@selector(previewView:didChangeCamera:)]) {
            [_delegate previewView:self didChangeCamera:_cameraController];
        }
        return;
    }

    if (event.momentumPhase != NSEventPhaseNone && event.momentumPhase != NSEventPhaseBegan) {
        // Two-finger pan from trackpad momentum scrolling
        float dx = (float)event.scrollingDeltaX;
        float dy = (float)event.scrollingDeltaY;
        [_cameraController panByDeltaX:dx deltaY:dy sensitivity:0.003f];
    } else if (event.hasPreciseScrollingDeltas) {
        // Trackpad two-finger scroll = pan
        float dx = (float)event.scrollingDeltaX;
        float dy = (float)event.scrollingDeltaY;
        [_cameraController panByDeltaX:dx deltaY:dy sensitivity:0.003f];
    } else {
        // Mouse scroll wheel = zoom
        float delta = (float)event.scrollingDeltaY;
        [_cameraController zoomByDelta:-delta sensitivity:0.05f];
    }

    _contentDirty = YES;
    _scrollbarsDirty = YES;

    if ([_delegate respondsToSelector:@selector(previewView:didChangeCamera:)]) {
        [_delegate previewView:self didChangeCamera:_cameraController];
    }
}

- (void)magnifyWithEvent:(NSEvent *)event {
    // Pinch-to-zoom on trackpad
    float delta = (float)event.magnification;
    [_cameraController zoomByDelta:-delta sensitivity:2.0f];
    _contentDirty = YES;
    _scrollbarsDirty = YES;

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
            _cameraController.azimuth = 0.0f;
            _cameraController.elevation = 0.0f;
            [self frameAllModels];
            break;
        case 0x13: // '2' key - top view
            _cameraController.azimuth = 0.0f;
            _cameraController.elevation = M_PI_2 - 0.01f;
            [self frameAllModels];
            break;
        case 0x14: // '3' key - left view
            _cameraController.azimuth = M_PI_2;
            _cameraController.elevation = 0.0f;
            [self frameAllModels];
            break;
        case 0x15: // '4' key - right view
            _cameraController.azimuth = -M_PI_2;
            _cameraController.elevation = 0.0f;
            [self frameAllModels];
            break;
        case 0x17: // '5' key - back view
            _cameraController.azimuth = M_PI;
            _cameraController.elevation = 0.0f;
            [self frameAllModels];
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
        case 0x31: // space key - forward to delegate (play/pause) or toggle tool mode
            if ([_delegate respondsToSelector:@selector(previewView:didReceiveKeyEvent:)]) {
                [_delegate previewView:self didReceiveKeyEvent:event];
            } else {
                [self toggleToolMode];
            }
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

        // Arrow keys - nudge selected model
        case 0x7B: // left arrow
        case 0x7C: // right arrow
        case 0x7D: // down arrow
        case 0x7E: // up arrow
        {
            if (_selectedModelName &&
                [_delegate respondsToSelector:@selector(previewView:didNudgeModelWithDeltaX:deltaY:)]) {
                float nudgeAmount = 1.0f;
                NSEventModifierFlags mods = event.modifierFlags;
                if (mods & NSEventModifierFlagCommand) {
                    nudgeAmount = 50.0f;
                } else if (mods & NSEventModifierFlagShift) {
                    nudgeAmount = 10.0f;
                }

                float dx = 0.0f, dy = 0.0f;
                switch (event.keyCode) {
                    case 0x7B: dx = -nudgeAmount; break; // left
                    case 0x7C: dx =  nudgeAmount; break; // right
                    case 0x7D: dy = -nudgeAmount; break; // down
                    case 0x7E: dy =  nudgeAmount; break; // up
                }
                [_delegate previewView:self didNudgeModelWithDeltaX:dx deltaY:dy];
            }
            break;
        }

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
    NSString *hitModel = [self hitTestModelAtEvent:event];
    BOOL cmdHeld = (event.modifierFlags & NSEventModifierFlagCommand) != 0;

    if (hitModel) {
        if (cmdHeld) {
            // Cmd+click: toggle model in/out of multi-selection
            if ([_selectedModelNamesSet containsObject:hitModel]) {
                [_selectedModelNamesSet removeObject:hitModel];
            } else {
                [_selectedModelNamesSet addObject:hitModel];
            }

            if (_selectedModelNamesSet.count == 0) {
                [self clearModelSelection];
                if ([_delegate respondsToSelector:@selector(previewView:didSelectModel:)]) {
                    [_delegate previewView:self didSelectModel:nil];
                }
            } else if (_selectedModelNamesSet.count == 1) {
                NSString *onlyModel = _selectedModelNamesSet.firstObject;
                [self selectModel:onlyModel];
            } else {
                // Multiple models selected: update primary to last added
                _selectedModelName = _selectedModelNamesSet.lastObject;
                _modelVerticesDirty = YES;
                _contentDirty = YES;

                // Show handles for primary model
                NSDictionary *info = [_engineBridge getModelInfo:_selectedModelName];
                if (info) {
                    float posX = [info[@"WorldPosX"] floatValue];
                    float posY = [info[@"WorldPosY"] floatValue];
                    float posZ = [info[@"WorldPosZ"] floatValue];
                    float scaleX = [info[@"ScaleX"] floatValue] ?: 1.0f;
                    float scaleY = [info[@"ScaleY"] floatValue] ?: 1.0f;
                    float scaleZ = [info[@"ScaleZ"] floatValue] ?: 1.0f;
                    float rotX = [info[@"RotateX"] floatValue];
                    float rotY = [info[@"RotateY"] floatValue];
                    float rotZ = [info[@"RotateZ"] floatValue];
                    float renderWidth = [info[@"RenderWidth"] floatValue];
                    float renderHeight = [info[@"RenderHeight"] floatValue];
                    float renderDepth = [info[@"RenderDepth"] floatValue];
                    if (renderWidth < 0.001f) renderWidth = 1.0f;
                    if (renderHeight < 0.001f) renderHeight = 1.0f;
                    if (renderDepth < 0.001f) renderDepth = 2.0f;
                    [self adjustRenderDimensionsForModel:_selectedModelName
                                                position:(simd_float3){posX, posY, posZ}
                                                   scale:(simd_float3){scaleX, scaleY, scaleZ}
                                             renderWidth:&renderWidth
                                            renderHeight:&renderHeight
                                             renderDepth:&renderDepth];
                    BOOL isLocked = [info[@"Locked"] boolValue];
                    BOOL supportsZScaling = _show3D && (renderDepth > 2.1f);
                    simd_float3 bbMin = simd_make_float3(-renderWidth/2, -renderHeight/2, -renderDepth/2);
                    simd_float3 bbMax = simd_make_float3(renderWidth/2, renderHeight/2, renderDepth/2);
                    [self setModelTransformWithPosition:(simd_float3){posX, posY, posZ}
                                                  scale:(simd_float3){scaleX, scaleY, scaleZ}
                                               rotation:(simd_float3){rotX, rotY, rotZ}
                                         boundingBoxMin:bbMin
                                         boundingBoxMax:bbMax
                                            renderWidth:renderWidth
                                           renderHeight:renderHeight
                                            renderDepth:renderDepth
                                               isLocked:isLocked
                                       supportsZScaling:supportsZScaling];
                }

                if ([_delegate respondsToSelector:@selector(previewView:didSelectModels:)]) {
                    [_delegate previewView:self didSelectModels:[_selectedModelNamesSet array]];
                }
            }
        } else {
            // Regular click: single select
            [self selectModel:hitModel];
        }
    } else {
        // Clicked empty area: deselect all
        [self clearModelSelection];
        if ([_delegate respondsToSelector:@selector(previewView:didSelectModel:)]) {
            [_delegate previewView:self didSelectModel:nil];
        }
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
    _isManipulatingPolylinePoint = NO;
    _isRubberBanding = NO;
    _rubberBandOrigin = NSZeroPoint;

    // Check polyline points first (higher priority than bounding box handles)
    if (_selectedModelName && _polylineRenderer && _polylineRenderer.active) {
        simd_float3 rayOrigin, rayDir;
        [self rayFromScreenPoint:_lastDragPoint rayOrigin:&rayOrigin rayDirection:&rayDir];

        NSInteger hitIndex = -1;
        XLPolylineHitType hitType = [_polylineRenderer hitTestWithRayOrigin:rayOrigin
                                                              rayDirection:rayDir
                                                                      zoom:(float)_cameraController.distance
                                                                  hitIndex:&hitIndex];

        if (hitType == XLPolylineHitPoint || hitType == XLPolylineHitCP0 || hitType == XLPolylineHitCP1) {
            _isManipulatingPolylinePoint = YES;
            _polylineHitType = hitType;
            _polylineHitIndex = hitIndex;

            if (hitType == XLPolylineHitPoint) {
                _polylineRenderer.selectedPoint = hitIndex;
            }

            simd_float3 planePoint = [_polylineRenderer positionForPoint:
                (hitType == XLPolylineHitPoint) ? hitIndex : 0];
            simd_float3 worldPoint = [self worldPointFromScreenPoint:_lastDragPoint onPlane:planePoint];
            [_polylineRenderer beginDragAtPoint:worldPoint pointIndex:hitIndex hitType:hitType];

            if ([_delegate respondsToSelector:@selector(previewView:didBeginManipulatingModel:)]) {
                [_delegate previewView:self didBeginManipulatingModel:_selectedModelName];
            }

            _contentDirty = YES;
            return;
        } else if (hitType == XLPolylineHitSegment) {
            _polylineRenderer.selectedSegment = hitIndex;
            _contentDirty = YES;
            // Fall through to allow other interactions
        }
    }

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

    // Check if clicking on a model (for potential single-click select in mouseUp)
    // or on empty space (potential rubber-band start)
    NSString *hitModel = [self hitTestModelAtEvent:event];
    if (!hitModel) {
        // Empty space: prepare for rubber-band selection on drag
        _rubberBandOrigin = _lastDragPoint;
        _rubberBandCurrent = _lastDragPoint;
    }
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint current = [self convertPoint:event.locationInWindow fromView:nil];
    float dx = (float)(current.x - _lastDragPoint.x);
    float dy = (float)(current.y - _lastDragPoint.y);
    _lastDragPoint = current;

    if (_isManipulatingPolylinePoint && _polylineRenderer) {
        simd_float3 planePoint = [_polylineRenderer positionForPoint:
            (_polylineHitType == XLPolylineHitPoint) ? _polylineHitIndex : 0];
        simd_float3 worldPoint = [self worldPointFromScreenPoint:current onPlane:planePoint];
        simd_float3 newPos = [_polylineRenderer updateDragToPoint:worldPoint];

        if (_engineBridge && _selectedModelName) {
            if (_polylineHitType == XLPolylineHitPoint) {
                [_engineBridge movePolylinePoint:_selectedModelName
                                          index:_polylineHitIndex
                                              x:newPos.x y:newPos.y z:newPos.z];
            } else if (_polylineHitType == XLPolylineHitCP0) {
                [_engineBridge movePolylineCurvePoint:_selectedModelName
                                        segmentIndex:_polylineHitIndex
                                        controlPoint:0
                                                   x:newPos.x y:newPos.y z:newPos.z];
            } else if (_polylineHitType == XLPolylineHitCP1) {
                [_engineBridge movePolylineCurvePoint:_selectedModelName
                                        segmentIndex:_polylineHitIndex
                                        controlPoint:1
                                                   x:newPos.x y:newPos.y z:newPos.z];
            }
        }

        _contentDirty = YES;
        return;
    }

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

    // Check if we should start or continue rubber-band selection.
    // Rubber-band activates when mouse-down was on empty space (rubberBandOrigin was set
    // to a valid point by mouseDown:) and we drag beyond a small threshold.
    if (!_isDragging && !_isRubberBanding &&
        !NSEqualPoints(_rubberBandOrigin, NSZeroPoint)) {
        float dragDist = sqrtf(
            (float)(current.x - _rubberBandOrigin.x) * (float)(current.x - _rubberBandOrigin.x) +
            (float)(current.y - _rubberBandOrigin.y) * (float)(current.y - _rubberBandOrigin.y));
        if (dragDist > 3.0f) {
            _isRubberBanding = YES;
        }
    }

    if (_isRubberBanding) {
        _rubberBandCurrent = current;
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
    if (_isManipulatingPolylinePoint) {
        [_polylineRenderer endDrag];
        _isManipulatingPolylinePoint = NO;

        [self refreshPolylinePoints];
        [self reloadModels];

        if ([_delegate respondsToSelector:@selector(previewView:didEndManipulatingModel:)]) {
            [_delegate previewView:self didEndManipulatingModel:_selectedModelName];
        }

        _contentDirty = YES;
        return;
    }

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

    if (_isRubberBanding) {
        _isRubberBanding = NO;
        [self completeRubberBandSelection];
        _contentDirty = YES;
        return;
    }

    if (!_isDragging && event.clickCount == 1) {
        [self handleClickAtEvent:event];
    }
    _isDragging = NO;
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint localPoint = [self convertPoint:event.locationInWindow fromView:nil];
    simd_float3 rayOrigin, rayDir;
    [self rayFromScreenPoint:localPoint rayOrigin:&rayOrigin rayDirection:&rayDir];

    // Check polyline points first
    if (_selectedModelName && _polylineRenderer && _polylineRenderer.active) {
        NSInteger hitIndex = -1;
        XLPolylineHitType hitType = [_polylineRenderer hitTestWithRayOrigin:rayOrigin
                                                              rayDirection:rayDir
                                                                      zoom:(float)_cameraController.distance
                                                                  hitIndex:&hitIndex];

        if (hitType == XLPolylineHitPoint) {
            if (hitIndex != _polylineRenderer.highlightedPoint) {
                _polylineRenderer.highlightedPoint = hitIndex;
                _contentDirty = YES;
            }
            [[NSCursor pointingHandCursor] set];
            return;
        } else {
            if (_polylineRenderer.highlightedPoint != -1) {
                _polylineRenderer.highlightedPoint = -1;
                _contentDirty = YES;
            }
        }

        if (hitType == XLPolylineHitCP0 || hitType == XLPolylineHitCP1) {
            [[NSCursor pointingHandCursor] set];
            return;
        }

        if (hitType == XLPolylineHitSegment) {
            [[NSCursor crosshairCursor] set];
            return;
        }
    }

    // Update highlighted handle on mouse move
    if (_selectedModelName && _handles) {
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

#pragma mark - Polyline Point Support

- (void)loadPolylinePointsForModel:(NSString *)modelName {
    if (!_engineBridge || !modelName) {
        [_polylineRenderer clearPoints];
        return;
    }

    if (![_engineBridge isPolylineModel:modelName]) {
        [_polylineRenderer clearPoints];
        return;
    }

    NSArray<NSDictionary *> *pointData = [_engineBridge getPolylinePoints:modelName];
    if (!pointData || pointData.count < 2) {
        [_polylineRenderer clearPoints];
        return;
    }

    XLPolylinePoint points[XL_MAX_POLYLINE_POINTS];
    NSInteger count = MIN((NSInteger)pointData.count, (NSInteger)XL_MAX_POLYLINE_POINTS);

    for (NSInteger i = 0; i < count; i++) {
        NSDictionary *pt = pointData[i];
        points[i].position = simd_make_float3(
            [pt[@"x"] floatValue],
            [pt[@"y"] floatValue],
            [pt[@"z"] floatValue]
        );
        points[i].hasCurve = [pt[@"hasCurve"] boolValue];
        points[i].cp0 = simd_make_float3(
            [pt[@"cp0x"] floatValue],
            [pt[@"cp0y"] floatValue],
            [pt[@"cp0z"] floatValue]
        );
        points[i].cp1 = simd_make_float3(
            [pt[@"cp1x"] floatValue],
            [pt[@"cp1y"] floatValue],
            [pt[@"cp1z"] floatValue]
        );
    }

    [_polylineRenderer setPoints:points count:count];
}

- (void)refreshPolylinePoints {
    if (_selectedModelName && _polylineRenderer.active) {
        [self loadPolylinePointsForModel:_selectedModelName];
        _contentDirty = YES;
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

#pragma mark - Multi-Selection Rendering

- (void)renderMultiSelectionBoundsWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                               viewProjection:(simd_float4x4)viewProjection
                                         zoom:(float)zoom {
    if (_selectedModelNamesSet.count < 2) return;

    typedef struct {
        simd_float3 position;
        simd_float4 color;
    } MSVertex;

    NSMutableData *vertexData = [[NSMutableData alloc] init];
    simd_float4 multiColor = simd_make_float4(0.4f, 1.0f, 0.4f, 0.6f);

    for (NSString *modelName in _selectedModelNamesSet) {
        if ([modelName isEqualToString:_selectedModelName]) continue;

        // Find this model's bounds in the flat lookup array
        XLModelLookup *foundLookup = NULL;
        for (NSUInteger mi = 0; mi < _flatModelCount; mi++) {
            if ([_flatModelNames[mi] isEqualToString:modelName]) {
                foundLookup = &_flatModelLookups[mi];
                break;
            }
        }
        if (!foundLookup || !foundLookup->hasBounds) continue;

        float minX = foundLookup->boundsMinX;
        float maxX = foundLookup->boundsMaxX;
        float minY = foundLookup->boundsMinY;
        float maxY = foundLookup->boundsMaxY;
        float minZ = foundLookup->boundsMinZ;
        float maxZ = foundLookup->boundsMaxZ;

        float pad = 3.0f;
        minX -= pad; maxX += pad;
        minY -= pad; maxY += pad;
        minZ -= pad; maxZ += pad;

        MSVertex box[24] = {
            // Front face
            { .position = {minX, minY, maxZ}, .color = multiColor },
            { .position = {maxX, minY, maxZ}, .color = multiColor },
            { .position = {maxX, minY, maxZ}, .color = multiColor },
            { .position = {maxX, maxY, maxZ}, .color = multiColor },
            { .position = {maxX, maxY, maxZ}, .color = multiColor },
            { .position = {minX, maxY, maxZ}, .color = multiColor },
            { .position = {minX, maxY, maxZ}, .color = multiColor },
            { .position = {minX, minY, maxZ}, .color = multiColor },
            // Back face
            { .position = {minX, minY, minZ}, .color = multiColor },
            { .position = {maxX, minY, minZ}, .color = multiColor },
            { .position = {maxX, minY, minZ}, .color = multiColor },
            { .position = {maxX, maxY, minZ}, .color = multiColor },
            { .position = {maxX, maxY, minZ}, .color = multiColor },
            { .position = {minX, maxY, minZ}, .color = multiColor },
            { .position = {minX, maxY, minZ}, .color = multiColor },
            { .position = {minX, minY, minZ}, .color = multiColor },
            // Connecting edges
            { .position = {minX, minY, minZ}, .color = multiColor },
            { .position = {minX, minY, maxZ}, .color = multiColor },
            { .position = {maxX, minY, minZ}, .color = multiColor },
            { .position = {maxX, minY, maxZ}, .color = multiColor },
            { .position = {maxX, maxY, minZ}, .color = multiColor },
            { .position = {maxX, maxY, maxZ}, .color = multiColor },
            { .position = {minX, maxY, minZ}, .color = multiColor },
            { .position = {minX, maxY, maxZ}, .color = multiColor },
        };
        [vertexData appendBytes:box length:sizeof(box)];
    }

    NSUInteger vertexCount = vertexData.length / sizeof(MSVertex);
    if (vertexCount > 0) {
        // Use newBufferWithBytes for large payloads (setVertexBytes has 4096-byte limit)
        id<MTLBuffer> vtxBuffer = [_device newBufferWithBytes:vertexData.bytes
                                                       length:vertexData.length
                                                      options:MTLResourceStorageModeShared];
        [encoder pushDebugGroup:@"MultiSelectionBounds"];
        [encoder setRenderPipelineState:_gridPipelineState];
        [encoder setVertexBuffer:vtxBuffer offset:0 atIndex:0];
        [encoder setVertexBytes:&viewProjection length:sizeof(simd_float4x4) atIndex:1];
        [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:vertexCount];
        [encoder popDebugGroup];
    }
}

#pragma mark - Rubber-Band Selection

- (void)completeRubberBandSelection {
    // Build the screen-space selection rectangle
    CGFloat minX = fmin(_rubberBandOrigin.x, _rubberBandCurrent.x);
    CGFloat maxX = fmax(_rubberBandOrigin.x, _rubberBandCurrent.x);
    CGFloat minY = fmin(_rubberBandOrigin.y, _rubberBandCurrent.y);
    CGFloat maxY = fmax(_rubberBandOrigin.y, _rubberBandCurrent.y);

    // Ignore tiny rubber-bands (accidental clicks)
    if ((maxX - minX) < 4.0 && (maxY - minY) < 4.0) {
        return;
    }

    CGSize drawableSize = _mlayer.drawableSize;
    CGFloat backingScale = self.window.backingScaleFactor ?: 1.0;
    float aspect = (float)drawableSize.width / (float)drawableSize.height;
    simd_float4x4 viewMatrix = _cameraController.viewMatrix;
    simd_float4x4 projMatrix = [_cameraController projectionMatrixForAspect:aspect];
    simd_float4x4 viewProj = simd_mul(projMatrix, viewMatrix);

    float viewWidth = (float)(drawableSize.width / backingScale);
    float viewHeight = (float)(drawableSize.height / backingScale);

    NSMutableArray<NSString *> *modelsInRect = [[NSMutableArray alloc] init];

    for (NSUInteger mi = 0; mi < _flatModelCount; mi++) {
        XLModelLookup *lookup = &_flatModelLookups[mi];
        if (!lookup->hasBounds) continue;

        float bMinX = lookup->boundsMinX;
        float bMaxX = lookup->boundsMaxX;
        float bMinY = lookup->boundsMinY;
        float bMaxY = lookup->boundsMaxY;
        float bMinZ = lookup->boundsMinZ;
        float bMaxZ = lookup->boundsMaxZ;

        // Project all 8 corners of the AABB to screen and find 2D bounding rect
        float corners[8][3] = {
            {bMinX, bMinY, bMinZ}, {bMaxX, bMinY, bMinZ},
            {bMinX, bMaxY, bMinZ}, {bMaxX, bMaxY, bMinZ},
            {bMinX, bMinY, bMaxZ}, {bMaxX, bMinY, bMaxZ},
            {bMinX, bMaxY, bMaxZ}, {bMaxX, bMaxY, bMaxZ},
        };

        float screenMinX = FLT_MAX, screenMaxX = -FLT_MAX;
        float screenMinY = FLT_MAX, screenMaxY = -FLT_MAX;
        BOOL allBehind = YES;

        for (int c = 0; c < 8; c++) {
            simd_float4 worldPos = simd_make_float4(corners[c][0], corners[c][1], corners[c][2], 1.0f);
            simd_float4 clipPos = simd_mul(viewProj, worldPos);

            if (clipPos.w <= 0.001f) continue;
            allBehind = NO;

            float ndcX = clipPos.x / clipPos.w;
            float ndcY = clipPos.y / clipPos.w;

            float sx = (ndcX * 0.5f + 0.5f) * viewWidth;
            float sy = (1.0f - (ndcY * 0.5f + 0.5f)) * viewHeight;

            sy = viewHeight - sy; // convert from top-down to NSView bottom-up

            screenMinX = fminf(screenMinX, sx);
            screenMaxX = fmaxf(screenMaxX, sx);
            screenMinY = fminf(screenMinY, sy);
            screenMaxY = fmaxf(screenMaxY, sy);
        }

        if (allBehind) continue;

        // Check if the model's screen-space bounds intersect with the rubber-band rect
        BOOL intersects = !(screenMaxX < (float)minX || screenMinX > (float)maxX ||
                           screenMaxY < (float)minY || screenMinY > (float)maxY);

        if (intersects) {
            NSString *name = _flatModelNames[mi];
            if (name) {
                [modelsInRect addObject:name];
            }
        }
    }

    if (modelsInRect.count > 0) {
        [self selectModels:modelsInRect];
    } else {
        [self clearModelSelection];
        if ([_delegate respondsToSelector:@selector(previewView:didSelectModel:)]) {
            [_delegate previewView:self didSelectModel:nil];
        }
    }
}

- (void)renderRubberBandWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                         drawableSize:(CGSize)drawableSize {
    if (!_isRubberBanding || !_rubberBandPipelineState) return;

    CGFloat backingScale = self.window.backingScaleFactor ?: 1.0;
    float viewWidth = (float)(drawableSize.width / backingScale);
    float viewHeight = (float)(drawableSize.height / backingScale);

    // Convert screen points to NDC (-1..1)
    float x0 = ((float)_rubberBandOrigin.x / viewWidth) * 2.0f - 1.0f;
    float y0 = ((float)_rubberBandOrigin.y / viewHeight) * 2.0f - 1.0f;
    float x1 = ((float)_rubberBandCurrent.x / viewWidth) * 2.0f - 1.0f;
    float y1 = ((float)_rubberBandCurrent.y / viewHeight) * 2.0f - 1.0f;

    // Semi-transparent fill color (light blue)
    simd_float4 fillColor = simd_make_float4(0.3f, 0.5f, 1.0f, 0.15f);
    // Border color (brighter blue)
    simd_float4 borderColor = simd_make_float4(0.3f, 0.5f, 1.0f, 0.7f);

    typedef struct {
        simd_float2 position;
        simd_float4 color;
    } RBVertex;

    // Fill: two triangles
    RBVertex fillVertices[6] = {
        { .position = {x0, y0}, .color = fillColor },
        { .position = {x1, y0}, .color = fillColor },
        { .position = {x0, y1}, .color = fillColor },
        { .position = {x0, y1}, .color = fillColor },
        { .position = {x1, y0}, .color = fillColor },
        { .position = {x1, y1}, .color = fillColor },
    };

    // Border: 4 lines (8 vertices)
    RBVertex borderVertices[8] = {
        { .position = {x0, y0}, .color = borderColor },
        { .position = {x1, y0}, .color = borderColor },
        { .position = {x1, y0}, .color = borderColor },
        { .position = {x1, y1}, .color = borderColor },
        { .position = {x1, y1}, .color = borderColor },
        { .position = {x0, y1}, .color = borderColor },
        { .position = {x0, y1}, .color = borderColor },
        { .position = {x0, y0}, .color = borderColor },
    };

    [encoder pushDebugGroup:@"RubberBandSelection"];
    [encoder setRenderPipelineState:_rubberBandPipelineState];

    // Draw fill
    [encoder setVertexBytes:fillVertices length:sizeof(fillVertices) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];

    // Draw border
    [encoder setVertexBytes:borderVertices length:sizeof(borderVertices) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:8];

    [encoder popDebugGroup];
}

#pragma mark - Context Menu

- (NSString *)hitTestModelAtEvent:(NSEvent *)event {
    NSPoint localPoint = [self convertPoint:event.locationInWindow fromView:nil];

    CGSize drawableSize = _mlayer.drawableSize;
    CGFloat scale = self.window.backingScaleFactor ?: 1.0;
    float ndcX = (float)(localPoint.x * scale / drawableSize.width) * 2.0f - 1.0f;
    float ndcY = (float)(localPoint.y * scale / drawableSize.height) * 2.0f - 1.0f;

    float aspect = (float)drawableSize.width / (float)drawableSize.height;
    simd_float4x4 viewMatrix = _cameraController.viewMatrix;
    simd_float4x4 projMatrix = [_cameraController projectionMatrixForAspect:aspect];
    simd_float4x4 viewProj = simd_mul(projMatrix, viewMatrix);
    simd_float4x4 invViewProj = simd_inverse(viewProj);

    simd_float4 nearPoint = simd_mul(invViewProj, (simd_float4){ndcX, ndcY, 0.0f, 1.0f});
    simd_float4 farPoint = simd_mul(invViewProj, (simd_float4){ndcX, ndcY, 1.0f, 1.0f});

    simd_float3 rayOrigin = (simd_float3){nearPoint.x, nearPoint.y, nearPoint.z} / nearPoint.w;
    simd_float3 rayEnd = (simd_float3){farPoint.x, farPoint.y, farPoint.z} / farPoint.w;
    simd_float3 rayDir = simd_normalize(rayEnd - rayOrigin);

    NSString *closestModel = nil;
    float closestDist = FLT_MAX;

    for (NSUInteger mi = 0; mi < _flatModelCount; mi++) {
        XLModelLookup *lookup = &_flatModelLookups[mi];
        if (!lookup->hasBounds) continue;

        float minX = lookup->boundsMinX;
        float maxX = lookup->boundsMaxX;
        float minY = lookup->boundsMinY;
        float maxY = lookup->boundsMaxY;
        float minZ = lookup->boundsMinZ;
        float maxZ = lookup->boundsMaxZ;

        // Expand bounding box slightly for easier clicking
        float pad = fmaxf(fmaxf(maxX - minX, maxY - minY), maxZ - minZ) * 0.05f;
        pad = fmaxf(pad, 5.0f);
        minX -= pad; maxX += pad;
        minY -= pad; maxY += pad;
        minZ -= pad; maxZ += pad;

        // Ray-AABB intersection test
        float tmin = -FLT_MAX;
        float tmax = FLT_MAX;

        for (int axis = 0; axis < 3; axis++) {
            float orig, dir, bmin, bmax;
            switch (axis) {
                case 0: orig = rayOrigin.x; dir = rayDir.x; bmin = minX; bmax = maxX; break;
                case 1: orig = rayOrigin.y; dir = rayDir.y; bmin = minY; bmax = maxY; break;
                case 2: orig = rayOrigin.z; dir = rayDir.z; bmin = minZ; bmax = maxZ; break;
                default: continue;
            }

            if (fabsf(dir) < 1e-8f) {
                if (orig < bmin || orig > bmax) { tmin = FLT_MAX; break; }
            } else {
                float t1 = (bmin - orig) / dir;
                float t2 = (bmax - orig) / dir;
                if (t1 > t2) { float tmp = t1; t1 = t2; t2 = tmp; }
                tmin = fmaxf(tmin, t1);
                tmax = fminf(tmax, t2);
                if (tmin > tmax) { tmin = FLT_MAX; break; }
            }
        }

        if (tmin < FLT_MAX && tmin < closestDist && tmax >= 0.0f) {
            closestDist = tmin;
            closestModel = _flatModelNames[mi];
        }
    }

    return closestModel;
}

- (void)showContextMenuForEvent:(NSEvent *)event {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Preview"];

    // Determine what model is under the cursor
    NSString *modelUnderCursor = [self hitTestModelAtEvent:event];

    // If there is a model under cursor, select it first
    if (modelUnderCursor) {
        [self selectModel:modelUnderCursor];
    }

    // Query the delegate for the full multi-selection list
    NSArray<NSString *> *allSelectedNames = nil;
    if ([_delegate respondsToSelector:@selector(previewViewSelectedModelNames:)]) {
        allSelectedNames = [_delegate previewViewSelectedModelNames:self];
    }
    // Fall back to just the preview's single selection
    if (allSelectedNames.count == 0 && _selectedModelName) {
        allSelectedNames = @[_selectedModelName];
    }

    NSUInteger selectionCount = allSelectedNames.count;
    BOOL hasSelectedModel = (_selectedModelName != nil);

    // ===== MULTI-MODEL SELECTION (2+ models) =====
    if (selectionCount >= 2) {
        NSString *headerTitle = [NSString stringWithFormat:@"%lu Models Selected", (unsigned long)selectionCount];
        NSMenuItem *headerItem = [[NSMenuItem alloc] initWithTitle:headerTitle action:nil keyEquivalent:@""];
        headerItem.enabled = NO;
        [menu addItem:headerItem];
        [menu addItem:[NSMenuItem separatorItem]];

        // Bulk Edit submenu
        [menu addItem:[self buildBulkEditMenuItem]];

        [menu addItem:[NSMenuItem separatorItem]];

        // Align submenu
        [menu addItem:[self buildAlignMenuItem]];

        // Distribute submenu
        [menu addItem:[self buildDistributeMenuItem]];

        // Resize submenu
        [menu addItem:[self buildResizeMenuItem]];

        [menu addItem:[NSMenuItem separatorItem]];

        // Lock/Unlock All
        NSMenuItem *lockAllItem = [[NSMenuItem alloc] initWithTitle:@"Lock All Selected"
                                                             action:@selector(contextMenuLockAllModels:)
                                                      keyEquivalent:@""];
        lockAllItem.target = self;
        [menu addItem:lockAllItem];

        NSMenuItem *unlockAllItem = [[NSMenuItem alloc] initWithTitle:@"Unlock All Selected"
                                                               action:@selector(contextMenuUnlockAllModels:)
                                                        keyEquivalent:@""];
        unlockAllItem.target = self;
        [menu addItem:unlockAllItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Delete Models
        NSMenuItem *deleteAllItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Delete %lu Models", (unsigned long)selectionCount]
                                                               action:@selector(contextMenuDeleteAllModels:)
                                                        keyEquivalent:@""];
        deleteAllItem.target = self;
        [menu addItem:deleteAllItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Create Group from Selection
        NSMenuItem *createGroupItem = [[NSMenuItem alloc] initWithTitle:@"Create Group from Selection"
                                                                action:@selector(contextMenuCreateGroupFromSelection:)
                                                         keyEquivalent:@""];
        createGroupItem.target = self;
        [menu addItem:createGroupItem];

        [menu addItem:[NSMenuItem separatorItem]];

    // ===== SINGLE MODEL SELECTION =====
    } else if (hasSelectedModel) {
        NSMenuItem *selectItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Select \"%@\"", _selectedModelName]
                                                            action:nil
                                                     keyEquivalent:@""];
        selectItem.enabled = NO;
        [menu addItem:selectItem];
        [menu addItem:[NSMenuItem separatorItem]];

        // Lock/Unlock
        NSDictionary *info = [_engineBridge getModelInfo:_selectedModelName];
        BOOL isLocked = [info[@"Locked"] boolValue];

        if (isLocked) {
            NSMenuItem *unlockItem = [[NSMenuItem alloc] initWithTitle:@"Unlock Model"
                                                                action:@selector(contextMenuUnlockModel:)
                                                         keyEquivalent:@""];
            unlockItem.target = self;
            unlockItem.representedObject = _selectedModelName;
            [menu addItem:unlockItem];
        } else {
            NSMenuItem *lockItem = [[NSMenuItem alloc] initWithTitle:@"Lock Model"
                                                              action:@selector(contextMenuLockModel:)
                                                       keyEquivalent:@""];
            lockItem.target = self;
            lockItem.representedObject = _selectedModelName;
            [menu addItem:lockItem];
        }

        [menu addItem:[NSMenuItem separatorItem]];

        // Node Layout
        NSMenuItem *nodeLayoutItem = [[NSMenuItem alloc] initWithTitle:@"Node Layout"
                                                                action:@selector(contextMenuNodeLayout:)
                                                         keyEquivalent:@""];
        nodeLayoutItem.target = self;
        nodeLayoutItem.representedObject = _selectedModelName;
        [menu addItem:nodeLayoutItem];

        // Wiring View
        NSMenuItem *wiringItem = [[NSMenuItem alloc] initWithTitle:@"Wiring View"
                                                            action:@selector(contextMenuWiringView:)
                                                     keyEquivalent:@""];
        wiringItem.target = self;
        wiringItem.representedObject = _selectedModelName;
        [menu addItem:wiringItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Export as Custom xLights Model
        NSMenuItem *exportCustomItem = [[NSMenuItem alloc] initWithTitle:@"Export as Custom xLights Model"
                                                                 action:@selector(contextMenuExportAsCustomModel:)
                                                          keyEquivalent:@""];
        exportCustomItem.target = self;
        exportCustomItem.representedObject = _selectedModelName;
        [menu addItem:exportCustomItem];

        // Export xLights Model (.xmodel)
        NSMenuItem *exportModelItem = [[NSMenuItem alloc] initWithTitle:@"Export xLights Model (.xmodel)"
                                                                action:@selector(contextMenuExportXModel:)
                                                         keyEquivalent:@""];
        exportModelItem.target = self;
        exportModelItem.representedObject = _selectedModelName;
        [menu addItem:exportModelItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Add to Existing Groups submenu
        if (_engineBridge) {
            NSArray<NSDictionary *> *groups = [_engineBridge getModelGroups];
            if (groups.count > 0) {
                NSMenu *addToGroupMenu = [[NSMenu alloc] initWithTitle:@"Add to Group"];
                BOOL hasOptions = NO;
                for (NSDictionary *group in groups) {
                    NSString *groupName = group[@"name"];
                    NSArray<NSString *> *members = group[@"modelNames"];
                    if (![members containsObject:_selectedModelName]) {
                        NSMenuItem *gItem = [[NSMenuItem alloc] initWithTitle:groupName
                                                                      action:@selector(contextMenuAddToGroup:)
                                                               keyEquivalent:@""];
                        gItem.target = self;
                        gItem.representedObject = groupName;
                        [addToGroupMenu addItem:gItem];
                        hasOptions = YES;
                    }
                }
                if (hasOptions) {
                    NSMenuItem *addToGroupItem = [[NSMenuItem alloc] initWithTitle:@"Add to Existing Group" action:nil keyEquivalent:@""];
                    [menu setSubmenu:addToGroupMenu forItem:addToGroupItem];
                    [menu addItem:addToGroupItem];
                }
            }
        }

        // Create Group
        NSMenuItem *createGroupItem = [[NSMenuItem alloc] initWithTitle:@"Create Group"
                                                                action:@selector(contextMenuCreateGroupFromSelection:)
                                                         keyEquivalent:@""];
        createGroupItem.target = self;
        [menu addItem:createGroupItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Flip
        NSMenuItem *flipHItem = [[NSMenuItem alloc] initWithTitle:@"Flip Horizontal"
                                                           action:@selector(contextMenuFlipHorizontal:)
                                                    keyEquivalent:@""];
        flipHItem.target = self;
        flipHItem.representedObject = _selectedModelName;
        flipHItem.enabled = !isLocked;
        [menu addItem:flipHItem];

        NSMenuItem *flipVItem = [[NSMenuItem alloc] initWithTitle:@"Flip Vertical"
                                                           action:@selector(contextMenuFlipVertical:)
                                                    keyEquivalent:@""];
        flipVItem.target = self;
        flipVItem.representedObject = _selectedModelName;
        flipVItem.enabled = !isLocked;
        [menu addItem:flipVItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Create Shadow Model
        NSMenuItem *shadowItem = [[NSMenuItem alloc] initWithTitle:@"Create Shadow Model"
                                                            action:@selector(contextMenuCreateShadow:)
                                                     keyEquivalent:@""];
        shadowItem.target = self;
        shadowItem.representedObject = _selectedModelName;
        [menu addItem:shadowItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Delete
        NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete Model"
                                                            action:@selector(contextMenuDeleteModel:)
                                                     keyEquivalent:@""];
        deleteItem.target = self;
        deleteItem.representedObject = _selectedModelName;
        deleteItem.enabled = !isLocked;
        [menu addItem:deleteItem];

        // Polyline point editing items
        if (_engineBridge && [_engineBridge isPolylineModel:_selectedModelName]) {
            [menu addItem:[NSMenuItem separatorItem]];

            NSPoint eventPoint = [self convertPoint:event.locationInWindow fromView:nil];
            simd_float3 rayOrigin, rayDir;
            [self rayFromScreenPoint:eventPoint rayOrigin:&rayOrigin rayDirection:&rayDir];

            _contextMenuPolylineHitType = XLPolylineHitNone;
            _contextMenuPolylineHitIndex = -1;

            if (_polylineRenderer && _polylineRenderer.active) {
                NSInteger hitIdx = -1;
                XLPolylineHitType hitType = [_polylineRenderer hitTestWithRayOrigin:rayOrigin
                                                                      rayDirection:rayDir
                                                                              zoom:(float)_cameraController.distance
                                                                          hitIndex:&hitIdx];
                _contextMenuPolylineHitType = hitType;
                _contextMenuPolylineHitIndex = hitIdx;
            }

            if (_contextMenuPolylineHitType == XLPolylineHitSegment && _contextMenuPolylineHitIndex >= 0) {
                NSMenuItem *addPointItem = [[NSMenuItem alloc] initWithTitle:@"Add Point"
                                                                     action:@selector(contextMenuAddPolylinePoint:)
                                                              keyEquivalent:@""];
                addPointItem.target = self;
                addPointItem.enabled = !isLocked;
                [menu addItem:addPointItem];
            }

            NSInteger pointCount = [_engineBridge getPolylinePointCount:_selectedModelName];
            if (_polylineRenderer.selectedPoint >= 0 && pointCount > 2) {
                NSMenuItem *deletePointItem = [[NSMenuItem alloc] initWithTitle:@"Delete Point"
                                                                        action:@selector(contextMenuDeletePolylinePoint:)
                                                                 keyEquivalent:@""];
                deletePointItem.target = self;
                deletePointItem.enabled = !isLocked;
                [menu addItem:deletePointItem];
            }

            if ([_engineBridge polylineModelSupportsCurves:_selectedModelName]) {
                NSInteger segIndex = -1;
                if (_contextMenuPolylineHitType == XLPolylineHitSegment) {
                    segIndex = _contextMenuPolylineHitIndex;
                } else if (_polylineRenderer.selectedSegment >= 0) {
                    segIndex = _polylineRenderer.selectedSegment;
                }

                if (segIndex >= 0 && segIndex < _polylineRenderer.pointCount - 1) {
                    NSArray<NSDictionary *> *pts = [_engineBridge getPolylinePoints:_selectedModelName];
                    BOOL hasCurve = NO;
                    if (segIndex < (NSInteger)pts.count) {
                        hasCurve = [pts[segIndex][@"hasCurve"] boolValue];
                    }

                    if (hasCurve) {
                        NSMenuItem *removeCurveItem = [[NSMenuItem alloc] initWithTitle:@"Remove Curve"
                                                                                action:@selector(contextMenuRemovePolylineCurve:)
                                                                         keyEquivalent:@""];
                        removeCurveItem.target = self;
                        removeCurveItem.enabled = !isLocked;
                        [menu addItem:removeCurveItem];
                    } else {
                        NSMenuItem *addCurveItem = [[NSMenuItem alloc] initWithTitle:@"Add Curve"
                                                                             action:@selector(contextMenuAddPolylineCurve:)
                                                                      keyEquivalent:@""];
                        addCurveItem.target = self;
                        addCurveItem.enabled = !isLocked;
                        [menu addItem:addCurveItem];
                    }
                }
            }
        }

        [menu addItem:[NSMenuItem separatorItem]];

    // ===== NO SELECTION (background click) =====
    } else {
        // Preview/layout group management
        NSMenuItem *deletePreviewItem = [[NSMenuItem alloc] initWithTitle:@"Delete this Preview"
                                                                  action:@selector(contextMenuDeletePreview:)
                                                           keyEquivalent:@""];
        deletePreviewItem.target = self;
        [menu addItem:deletePreviewItem];

        NSMenuItem *renamePreviewItem = [[NSMenuItem alloc] initWithTitle:@"Rename this Preview"
                                                                  action:@selector(contextMenuRenamePreview:)
                                                           keyEquivalent:@""];
        renamePreviewItem.target = self;
        [menu addItem:renamePreviewItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // Import
        NSMenuItem *importModelsItem = [[NSMenuItem alloc] initWithTitle:@"Import Models"
                                                                 action:@selector(contextMenuImportModels:)
                                                          keyEquivalent:@""];
        importModelsItem.target = self;
        [menu addItem:importModelsItem];

        NSMenuItem *importPreviewsItem = [[NSMenuItem alloc] initWithTitle:@"Import Previews"
                                                                   action:@selector(contextMenuImportPreviews:)
                                                            keyEquivalent:@""];
        importPreviewsItem.target = self;
        [menu addItem:importPreviewsItem];

        [menu addItem:[NSMenuItem separatorItem]];
    }

    // ===== COMMON SECTION (always shown) =====

    // View operations
    NSMenuItem *resetItem = [[NSMenuItem alloc] initWithTitle:@"Reset View"
                                                      action:@selector(contextMenuResetView:)
                                               keyEquivalent:@""];
    resetItem.target = self;
    [menu addItem:resetItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // Save / Print Layout Image
    NSMenuItem *saveImageItem = [[NSMenuItem alloc] initWithTitle:@"Save Layout Image"
                                                          action:@selector(contextMenuSaveLayoutImage:)
                                                   keyEquivalent:@""];
    saveImageItem.target = self;
    [menu addItem:saveImageItem];

    NSMenuItem *printImageItem = [[NSMenuItem alloc] initWithTitle:@"Print Layout Image"
                                                           action:@selector(contextMenuPrintLayoutImage:)
                                                    keyEquivalent:@""];
    printImageItem.target = self;
    [menu addItem:printImageItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // Grid controls
    NSMenuItem *gridToggle = [[NSMenuItem alloc] initWithTitle:@"Show Grid"
                                                        action:@selector(contextMenuToggleGrid:)
                                                 keyEquivalent:@"["];
    gridToggle.target = self;
    gridToggle.state = _showGrid ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:gridToggle];

    // Grid Spacing submenu
    NSMenu *gridSpacingMenu = [[NSMenu alloc] initWithTitle:@"Grid Spacing"];
    for (NSNumber *spacingVal in @[@10, @25, @50, @100, @200]) {
        float spacing = spacingVal.floatValue;
        NSString *title = [NSString stringWithFormat:@"%.0f", spacing];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(contextMenuSetGridSpacing:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = spacingVal;
        if (fabsf(_gridSpacing - spacing) < 0.01f) {
            item.state = NSControlStateValueOn;
        }
        [gridSpacingMenu addItem:item];
    }
    NSMenuItem *gridSpacingItem = [[NSMenuItem alloc] initWithTitle:@"Grid Spacing" action:nil keyEquivalent:@""];
    [menu setSubmenu:gridSpacingMenu forItem:gridSpacingItem];
    [menu addItem:gridSpacingItem];

    NSMenuItem *gridCenterItem = [[NSMenuItem alloc] initWithTitle:@"Center Grid at Origin"
                                                            action:@selector(contextMenuToggleGridCenter:)
                                                     keyEquivalent:@""];
    gridCenterItem.target = self;
    gridCenterItem.state = _gridCenterAtOrigin ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:gridCenterItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // Viewpoint management
    NSMenuItem *setDefaultVP = [[NSMenuItem alloc] initWithTitle:@"Set Current ViewPoint as Default"
                                                          action:@selector(contextMenuSetDefaultViewpoint:)
                                                   keyEquivalent:@""];
    setDefaultVP.target = self;
    [menu addItem:setDefaultVP];

    NSMenuItem *restoreDefaultVP = [[NSMenuItem alloc] initWithTitle:@"Restore Default ViewPoint"
                                                              action:@selector(contextMenuRestoreDefaultViewpoint:)
                                                       keyEquivalent:@""];
    restoreDefaultVP.target = self;
    [menu addItem:restoreDefaultVP];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *saveVP = [[NSMenuItem alloc] initWithTitle:@"Save Current ViewPoint"
                                                    action:@selector(contextMenuSaveViewpoint:)
                                             keyEquivalent:@""];
    saveVP.target = self;
    [menu addItem:saveVP];

    // Load ViewPoint submenu
    NSArray<NSString *> *viewpointNames = [_cameraController savedViewpointNames];
    if (viewpointNames.count > 0) {
        NSMenu *loadVPMenu = [[NSMenu alloc] initWithTitle:@"Load ViewPoint"];
        for (NSString *name in viewpointNames) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name
                                                         action:@selector(contextMenuLoadViewpoint:)
                                                  keyEquivalent:@""];
            item.target = self;
            item.representedObject = name;
            [loadVPMenu addItem:item];
        }
        NSMenuItem *loadVPItem = [[NSMenuItem alloc] initWithTitle:@"Load ViewPoint" action:nil keyEquivalent:@""];
        [menu setSubmenu:loadVPMenu forItem:loadVPItem];
        [menu addItem:loadVPItem];

        // Delete ViewPoint submenu
        NSMenu *deleteVPMenu = [[NSMenu alloc] initWithTitle:@"Delete ViewPoint"];
        for (NSString *name in viewpointNames) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name
                                                         action:@selector(contextMenuDeleteViewpoint:)
                                                  keyEquivalent:@""];
            item.target = self;
            item.representedObject = name;
            [deleteVPMenu addItem:item];
        }
        NSMenuItem *deleteVPItem = [[NSMenuItem alloc] initWithTitle:@"Delete ViewPoint" action:nil keyEquivalent:@""];
        [menu setSubmenu:deleteVPMenu forItem:deleteVPItem];
        [menu addItem:deleteVPItem];
    }

    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

#pragma mark - Context Menu Submenu Builders

- (NSMenuItem *)buildBulkEditMenuItem {
    NSMenu *bulkEditMenu = [[NSMenu alloc] initWithTitle:@"Bulk Edit"];
    NSArray *bulkEditOptions = @[
        @"Active", @"Inactive", @"---",
        @"Tag Color", @"Preview",
        @"Pixel Size", @"Pixel Style", @"Transparency", @"---",
        @"Controller Name", @"Controller Port", @"Controller Protocol",
    ];
    for (NSString *option in bulkEditOptions) {
        if ([option isEqualToString:@"---"]) {
            [bulkEditMenu addItem:[NSMenuItem separatorItem]];
        } else {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option
                                                         action:@selector(contextMenuBulkEdit:)
                                                  keyEquivalent:@""];
            item.target = self;
            item.representedObject = option;
            [bulkEditMenu addItem:item];
        }
    }
    NSMenuItem *bulkEditItem = [[NSMenuItem alloc] initWithTitle:@"Bulk Edit" action:nil keyEquivalent:@""];
    [bulkEditItem setSubmenu:bulkEditMenu];
    return bulkEditItem;
}

- (NSMenuItem *)buildAlignMenuItem {
    NSMenu *alignMenu = [[NSMenu alloc] initWithTitle:@"Align"];
    for (NSString *option in @[@"Top", @"Bottom", @"Left", @"Right", @"Horizontal Center", @"Vertical Center"]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option
                                                     action:@selector(contextMenuAlignModels:)
                                              keyEquivalent:@""];
        item.target = self;
        item.representedObject = option;
        [alignMenu addItem:item];
    }
    if (_show3D) {
        [alignMenu addItem:[NSMenuItem separatorItem]];
        for (NSString *option in @[@"Front", @"Back", @"Depth Center", @"Align With Ground"]) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option
                                                         action:@selector(contextMenuAlignModels:)
                                                  keyEquivalent:@""];
            item.target = self;
            item.representedObject = option;
            [alignMenu addItem:item];
        }
    }
    NSMenuItem *alignItem = [[NSMenuItem alloc] initWithTitle:@"Align" action:nil keyEquivalent:@""];
    [alignItem setSubmenu:alignMenu];
    return alignItem;
}

- (NSMenuItem *)buildDistributeMenuItem {
    NSMenu *distributeMenu = [[NSMenu alloc] initWithTitle:@"Distribute"];
    NSArray *options = @[@"Horizontal", @"Vertical"];
    if (_show3D) {
        options = @[@"Horizontal", @"Vertical", @"Depth"];
    }
    for (NSString *option in options) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option
                                                     action:@selector(contextMenuDistributeModels:)
                                              keyEquivalent:@""];
        item.target = self;
        item.representedObject = option;
        [distributeMenu addItem:item];
    }
    NSMenuItem *distributeItem = [[NSMenuItem alloc] initWithTitle:@"Distribute" action:nil keyEquivalent:@""];
    [distributeItem setSubmenu:distributeMenu];
    return distributeItem;
}

- (NSMenuItem *)buildResizeMenuItem {
    NSMenu *resizeMenu = [[NSMenu alloc] initWithTitle:@"Resize"];
    for (NSString *option in @[@"Match Width", @"Match Height", @"Match Size"]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:option
                                                     action:@selector(contextMenuResizeModels:)
                                              keyEquivalent:@""];
        item.target = self;
        item.representedObject = option;
        [resizeMenu addItem:item];
    }
    NSMenuItem *resizeItem = [[NSMenuItem alloc] initWithTitle:@"Resize" action:nil keyEquivalent:@""];
    [resizeItem setSubmenu:resizeMenu];
    return resizeItem;
}

#pragma mark - Context Menu Actions (Grid)

- (void)contextMenuToggleGrid:(NSMenuItem *)sender {
    self.showGrid = !self.showGrid;
}

- (void)contextMenuSetGridSpacing:(NSMenuItem *)sender {
    NSNumber *spacingValue = sender.representedObject;
    if (spacingValue) {
        self.gridSpacing = spacingValue.floatValue;
    }
}

- (void)contextMenuToggleGridCenter:(NSMenuItem *)sender {
    self.gridCenterAtOrigin = !self.gridCenterAtOrigin;
}

#pragma mark - Context Menu Actions (Model - Single)

- (void)contextMenuLockModel:(NSMenuItem *)sender {
    NSString *modelName = sender.representedObject;
    if (!modelName) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestLockModel:lock:)]) {
        [_delegate previewView:self didRequestLockModel:modelName lock:YES];
    }
}

- (void)contextMenuUnlockModel:(NSMenuItem *)sender {
    NSString *modelName = sender.representedObject;
    if (!modelName) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestLockModel:lock:)]) {
        [_delegate previewView:self didRequestLockModel:modelName lock:NO];
    }
}

- (void)contextMenuDeleteModel:(NSMenuItem *)sender {
    NSString *modelName = sender.representedObject;
    if (!modelName) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Delete Model \"%@\"?", modelName];
    alert.informativeText = @"This action cannot be undone.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;
    alert.buttons.firstObject.hasDestructiveAction = YES;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        if ([_delegate respondsToSelector:@selector(previewView:didRequestDeleteModel:)]) {
            [_delegate previewView:self didRequestDeleteModel:modelName];
        }
    }
}

- (void)contextMenuCreateShadow:(NSMenuItem *)sender {
    NSString *modelName = sender.representedObject;
    if (!modelName || !_engineBridge) return;

    NSString *shadowName = [_engineBridge createShadowModel:modelName];
    if (shadowName) {
        [self reloadModels];
        [self selectModel:shadowName];

        [[NSNotificationCenter defaultCenter] postNotificationName:@"XLModelListDidChangeNotification"
                                                            object:nil
                                                          userInfo:@{@"selectedModel": shadowName}];
    }
}

- (void)contextMenuFlipHorizontal:(NSMenuItem *)sender {
    NSString *modelName = sender.representedObject;
    if (!modelName) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestFlipModel:horizontal:)]) {
        [_delegate previewView:self didRequestFlipModel:modelName horizontal:YES];
    }
}

- (void)contextMenuFlipVertical:(NSMenuItem *)sender {
    NSString *modelName = sender.representedObject;
    if (!modelName) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestFlipModel:horizontal:)]) {
        [_delegate previewView:self didRequestFlipModel:modelName horizontal:NO];
    }
}

- (void)contextMenuNodeLayout:(NSMenuItem *)sender {
    NSString *modelName = sender.representedObject;
    if (!modelName) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestNodeLayout:)]) {
        [_delegate previewView:self didRequestNodeLayout:modelName];
    }
}

- (void)contextMenuWiringView:(NSMenuItem *)sender {
    NSString *modelName = sender.representedObject;
    if (!modelName) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestWiringView:)]) {
        [_delegate previewView:self didRequestWiringView:modelName];
    }
}

- (void)contextMenuExportAsCustomModel:(NSMenuItem *)sender {
    NSString *modelName = sender.representedObject;
    if (!modelName) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestExportAsCustomModel:)]) {
        [_delegate previewView:self didRequestExportAsCustomModel:modelName];
    }
}

- (void)contextMenuExportXModel:(NSMenuItem *)sender {
    NSString *modelName = sender.representedObject;
    if (!modelName) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestExportXModel:)]) {
        [_delegate previewView:self didRequestExportXModel:modelName];
    }
}

- (void)contextMenuAddToGroup:(NSMenuItem *)sender {
    NSString *groupName = sender.representedObject;
    if (!groupName || !_selectedModelName) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestAddModel:toGroup:)]) {
        [_delegate previewView:self didRequestAddModel:_selectedModelName toGroup:groupName];
    }
}

- (void)contextMenuCreateGroupFromSelection:(NSMenuItem *)sender {
    NSArray<NSString *> *names = nil;
    if ([_delegate respondsToSelector:@selector(previewViewSelectedModelNames:)]) {
        names = [_delegate previewViewSelectedModelNames:self];
    }
    if (names.count == 0 && _selectedModelName) {
        names = @[_selectedModelName];
    }
    if (names.count == 0) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestCreateGroupFromModels:)]) {
        [_delegate previewView:self didRequestCreateGroupFromModels:names];
    }
}

#pragma mark - Context Menu Actions (Model - Multi)

- (void)contextMenuLockAllModels:(NSMenuItem *)sender {
    NSArray<NSString *> *names = nil;
    if ([_delegate respondsToSelector:@selector(previewViewSelectedModelNames:)]) {
        names = [_delegate previewViewSelectedModelNames:self];
    }
    if (names.count == 0) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestLockModels:lock:)]) {
        [_delegate previewView:self didRequestLockModels:names lock:YES];
    }
}

- (void)contextMenuUnlockAllModels:(NSMenuItem *)sender {
    NSArray<NSString *> *names = nil;
    if ([_delegate respondsToSelector:@selector(previewViewSelectedModelNames:)]) {
        names = [_delegate previewViewSelectedModelNames:self];
    }
    if (names.count == 0) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestLockModels:lock:)]) {
        [_delegate previewView:self didRequestLockModels:names lock:NO];
    }
}

- (void)contextMenuDeleteAllModels:(NSMenuItem *)sender {
    NSArray<NSString *> *names = nil;
    if ([_delegate respondsToSelector:@selector(previewViewSelectedModelNames:)]) {
        names = [_delegate previewViewSelectedModelNames:self];
    }
    if (names.count == 0) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Delete %lu Models?", (unsigned long)names.count];
    alert.informativeText = @"This action cannot be undone.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;
    alert.buttons.firstObject.hasDestructiveAction = YES;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        if ([_delegate respondsToSelector:@selector(previewView:didRequestDeleteModels:)]) {
            [_delegate previewView:self didRequestDeleteModels:names];
        }
    }
}

- (void)contextMenuAlignModels:(NSMenuItem *)sender {
    NSString *alignment = sender.representedObject;
    if (!alignment) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestAlignModels:)]) {
        [_delegate previewView:self didRequestAlignModels:alignment];
    }
}

- (void)contextMenuDistributeModels:(NSMenuItem *)sender {
    NSString *direction = sender.representedObject;
    if (!direction) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestDistributeModels:)]) {
        [_delegate previewView:self didRequestDistributeModels:direction];
    }
}

- (void)contextMenuResizeModels:(NSMenuItem *)sender {
    NSString *dimension = sender.representedObject;
    if (!dimension) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestResizeModels:)]) {
        [_delegate previewView:self didRequestResizeModels:dimension];
    }
}

- (void)contextMenuBulkEdit:(NSMenuItem *)sender {
    NSString *editType = sender.representedObject;
    if (!editType) return;
    if ([_delegate respondsToSelector:@selector(previewView:didRequestBulkEdit:)]) {
        [_delegate previewView:self didRequestBulkEdit:editType];
    }
}

#pragma mark - Context Menu Actions (Background/Preview)

- (void)contextMenuDeletePreview:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(previewViewDidRequestDeletePreview:)]) {
        [_delegate previewViewDidRequestDeletePreview:self];
    }
}

- (void)contextMenuRenamePreview:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(previewViewDidRequestRenamePreview:)]) {
        [_delegate previewViewDidRequestRenamePreview:self];
    }
}

- (void)contextMenuImportModels:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(previewViewDidRequestImportModels:)]) {
        [_delegate previewViewDidRequestImportModels:self];
    }
}

- (void)contextMenuImportPreviews:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(previewViewDidRequestImportPreviews:)]) {
        [_delegate previewViewDidRequestImportPreviews:self];
    }
}

#pragma mark - Context Menu Actions (Polyline)

- (void)contextMenuAddPolylinePoint:(NSMenuItem *)sender {
    if (!_engineBridge || !_selectedModelName) return;
    if (_contextMenuPolylineHitType != XLPolylineHitSegment || _contextMenuPolylineHitIndex < 0) return;

    if ([_engineBridge insertPolylinePoint:_selectedModelName afterSegment:_contextMenuPolylineHitIndex]) {
        [self refreshPolylinePoints];
        [self reloadModels];
        _contentDirty = YES;
    }
}

- (void)contextMenuDeletePolylinePoint:(NSMenuItem *)sender {
    if (!_engineBridge || !_selectedModelName) return;
    NSInteger pointIndex = _polylineRenderer.selectedPoint;
    if (pointIndex < 0) return;

    if ([_engineBridge deletePolylinePoint:_selectedModelName index:pointIndex]) {
        _polylineRenderer.selectedPoint = -1;
        _polylineRenderer.selectedSegment = -1;
        [self refreshPolylinePoints];
        [self reloadModels];
        _contentDirty = YES;
    }
}

- (void)contextMenuAddPolylineCurve:(NSMenuItem *)sender {
    if (!_engineBridge || !_selectedModelName) return;

    NSInteger segIndex = -1;
    if (_contextMenuPolylineHitType == XLPolylineHitSegment) {
        segIndex = _contextMenuPolylineHitIndex;
    } else if (_polylineRenderer.selectedSegment >= 0) {
        segIndex = _polylineRenderer.selectedSegment;
    }
    if (segIndex < 0) return;

    if ([_engineBridge setPolylineCurve:_selectedModelName segment:segIndex create:YES]) {
        [self refreshPolylinePoints];
        [self reloadModels];
        _contentDirty = YES;
    }
}

- (void)contextMenuRemovePolylineCurve:(NSMenuItem *)sender {
    if (!_engineBridge || !_selectedModelName) return;

    NSInteger segIndex = -1;
    if (_contextMenuPolylineHitType == XLPolylineHitSegment) {
        segIndex = _contextMenuPolylineHitIndex;
    } else if (_polylineRenderer.selectedSegment >= 0) {
        segIndex = _polylineRenderer.selectedSegment;
    }
    if (segIndex < 0) return;

    if ([_engineBridge setPolylineCurve:_selectedModelName segment:segIndex create:NO]) {
        [self refreshPolylinePoints];
        [self reloadModels];
        _contentDirty = YES;
    }
}

#pragma mark - Context Menu Actions (View)

- (void)contextMenuResetView:(NSMenuItem *)sender {
    [self resetCamera];
    [self frameAllModels];
}

- (void)contextMenuSaveLayoutImage:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(previewViewDidRequestSaveLayoutImage:)]) {
        [_delegate previewViewDidRequestSaveLayoutImage:self];
    }
}

- (void)contextMenuPrintLayoutImage:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(previewViewDidRequestPrintLayoutImage:)]) {
        [_delegate previewViewDidRequestPrintLayoutImage:self];
    }
}

- (void)contextMenuSetDefaultViewpoint:(NSMenuItem *)sender {
    [_cameraController saveAsDefaultViewpoint];
}

- (void)contextMenuRestoreDefaultViewpoint:(NSMenuItem *)sender {
    if ([_cameraController restoreDefaultViewpoint]) {
        self.show3D = _cameraController.perspective;
        _contentDirty = YES;
    }
}

- (void)contextMenuSaveViewpoint:(NSMenuItem *)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save ViewPoint";
    alert.informativeText = @"Enter a name for this viewpoint:";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
    input.placeholderString = @"ViewPoint Name";
    alert.accessoryView = input;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *name = input.stringValue;
        if (name.length > 0) {
            [_cameraController saveViewpointWithName:name];
        }
    }
}

- (void)contextMenuLoadViewpoint:(NSMenuItem *)sender {
    NSString *name = sender.representedObject;
    if (!name) return;
    if ([_cameraController loadViewpointWithName:name]) {
        self.show3D = _cameraController.perspective;
        _contentDirty = YES;
    }
}

- (void)contextMenuDeleteViewpoint:(NSMenuItem *)sender {
    NSString *name = sender.representedObject;
    if (!name) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Delete ViewPoint \"%@\"?", name];
    alert.informativeText = @"This action cannot be undone.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;
    alert.buttons.firstObject.hasDestructiveAction = YES;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [_cameraController deleteViewpointWithName:name];
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
    _selectedSubmodelNodeIndices = nil;
    [_selectedModelNamesSet removeAllObjects];
    [_handles clearSelection];
    [_polylineRenderer clearPoints];
    _isManipulatingHandle = NO;
    _isManipulatingPolylinePoint = NO;
    _activeHandleType = XLHandleTypeNone;
    _modelVerticesDirty = YES;
    _contentDirty = YES;
}

- (NSArray<NSString *> *)selectedModelNames {
    return [_selectedModelNamesSet array];
}

- (void)selectModels:(NSArray<NSString *> *)modelNames {
    [_selectedModelNamesSet removeAllObjects];

    if (!modelNames || modelNames.count == 0) {
        [self clearModelSelection];
        return;
    }

    [_selectedModelNamesSet addObjectsFromArray:modelNames];

    // The primary (last) model gets manipulation handles
    NSString *primaryModel = modelNames.lastObject;
    _selectedModelName = primaryModel;

    NSDictionary *info = [_engineBridge getModelInfo:primaryModel];
    if (!info) {
        [_handles clearSelection];
    } else {
        float posX = [info[@"WorldPosX"] floatValue];
        float posY = [info[@"WorldPosY"] floatValue];
        float posZ = [info[@"WorldPosZ"] floatValue];
        float scaleX = [info[@"ScaleX"] floatValue] ?: 1.0f;
        float scaleY = [info[@"ScaleY"] floatValue] ?: 1.0f;
        float scaleZ = [info[@"ScaleZ"] floatValue] ?: 1.0f;
        float rotX = [info[@"RotateX"] floatValue];
        float rotY = [info[@"RotateY"] floatValue];
        float rotZ = [info[@"RotateZ"] floatValue];
        float renderWidth = [info[@"RenderWidth"] floatValue];
        float renderHeight = [info[@"RenderHeight"] floatValue];
        float renderDepth = [info[@"RenderDepth"] floatValue];
        if (renderWidth < 0.001f) renderWidth = 1.0f;
        if (renderHeight < 0.001f) renderHeight = 1.0f;
        if (renderDepth < 0.001f) renderDepth = 2.0f;
        [self adjustRenderDimensionsForModel:primaryModel
                                    position:(simd_float3){posX, posY, posZ}
                                       scale:(simd_float3){scaleX, scaleY, scaleZ}
                                 renderWidth:&renderWidth
                                renderHeight:&renderHeight
                                 renderDepth:&renderDepth];
        BOOL isLocked = [info[@"Locked"] boolValue];
        BOOL supportsZScaling = _show3D && (renderDepth > 2.1f);

        simd_float3 bbMin = simd_make_float3(-renderWidth/2, -renderHeight/2, -renderDepth/2);
        simd_float3 bbMax = simd_make_float3(renderWidth/2, renderHeight/2, renderDepth/2);

        [self setModelTransformWithPosition:(simd_float3){posX, posY, posZ}
                                      scale:(simd_float3){scaleX, scaleY, scaleZ}
                                   rotation:(simd_float3){rotX, rotY, rotZ}
                             boundingBoxMin:bbMin
                             boundingBoxMax:bbMax
                                renderWidth:renderWidth
                               renderHeight:renderHeight
                                renderDepth:renderDepth
                                   isLocked:isLocked
                           supportsZScaling:supportsZScaling];
    }

    // Rebuild vertices to update selection highlight colors
    _modelVerticesDirty = YES;
    _contentDirty = YES;

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(previewView:didSelectModels:)]) {
        [_delegate previewView:self didSelectModels:[_selectedModelNamesSet array]];
    }
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
    _scrollbarsDirty = YES;
}


#pragma mark - Background Image

- (void)setBackgroundImage:(NSString *)path {
    if ([path isEqualToString:_backgroundImagePath]) return;

    _backgroundImagePath = [path copy];
    _backgroundTexture = nil;

    if (!path || path.length == 0) {
        _backgroundImageSize = CGSizeZero;
        _contentDirty = YES;
        return;
    }

    [self loadBackgroundTextureFromPath:path];
    _contentDirty = YES;
}

- (void)setBackgroundBrightness:(float)brightness {
    _backgroundBrightness = fmaxf(0.0f, fminf(brightness, 2.0f));
    _contentDirty = YES;
}

- (void)setBackgroundAlpha:(float)alpha {
    _backgroundAlpha = fmaxf(0.0f, fminf(alpha, 1.0f));
    _contentDirty = YES;
}

- (void)removeBackgroundImage {
    _backgroundImagePath = nil;
    _backgroundTexture = nil;
    _backgroundImageSize = CGSizeZero;
    _contentDirty = YES;
}

- (void)loadBackgroundTextureFromPath:(NSString *)path {
    NSImage *nsImage = [[NSImage alloc] initWithContentsOfFile:path];
    if (!nsImage) {
        NSLog(@"XLMetalPreviewView: Failed to load background image: %@", path);
        return;
    }

    // Get the bitmap representation for pixel data
    NSBitmapImageRep *bitmapRep = nil;
    for (NSImageRep *rep in nsImage.representations) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            bitmapRep = (NSBitmapImageRep *)rep;
            break;
        }
    }

    if (!bitmapRep) {
        // Create a bitmap representation by drawing the image
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

    _backgroundImageSize = CGSizeMake(w, h);

    // Create Metal texture from bitmap data
    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                       width:w
                                                                                      height:h
                                                                                   mipmapped:NO];
    texDesc.usage = MTLTextureUsageShaderRead;
    texDesc.storageMode = MTLStorageModeShared;

    id<MTLTexture> texture = [_device newTextureWithDescriptor:texDesc];
    if (!texture) {
        NSLog(@"XLMetalPreviewView: Failed to create background texture");
        return;
    }
    [texture setLabel:@"BackgroundImage"];

    // Convert bitmap to RGBA8 and upload
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

    _backgroundTexture = texture;
    NSLog(@"XLMetalPreviewView: Loaded background image %lux%lu from %@", (unsigned long)w, (unsigned long)h, path);
}

#pragma mark - 2D Scrollbars

static const CGFloat kScrollerWidth = 11.0;
static const CGFloat kScrollerMargin = 2.0;

- (void)setupScrollbars {
    _horizontalScroller = [[NSScroller alloc] initWithFrame:NSZeroRect];
    _horizontalScroller.scrollerStyle = NSScrollerStyleOverlay;
    _horizontalScroller.knobStyle = NSScrollerKnobStyleLight;
    _horizontalScroller.target = self;
    _horizontalScroller.action = @selector(horizontalScrollerAction:);
    _horizontalScroller.alphaValue = 0.0;
    _horizontalScroller.hidden = YES;
    [self addSubview:_horizontalScroller];

    _verticalScroller = [[NSScroller alloc] initWithFrame:NSZeroRect];
    _verticalScroller.scrollerStyle = NSScrollerStyleOverlay;
    _verticalScroller.knobStyle = NSScrollerKnobStyleLight;
    _verticalScroller.target = self;
    _verticalScroller.action = @selector(verticalScrollerAction:);
    _verticalScroller.alphaValue = 0.0;
    _verticalScroller.hidden = YES;
    [self addSubview:_verticalScroller];
}

- (void)layoutScrollbars {
    CGRect bounds = self.bounds;

    CGFloat hScrollerWidth = bounds.size.width - kScrollerMargin * 2.0 - kScrollerWidth;
    if (hScrollerWidth < 40.0) hScrollerWidth = 40.0;
    _horizontalScroller.frame = NSMakeRect(
        kScrollerMargin,
        kScrollerMargin,
        hScrollerWidth,
        kScrollerWidth
    );

    CGFloat vScrollerHeight = bounds.size.height - kScrollerMargin * 2.0 - kScrollerWidth;
    if (vScrollerHeight < 40.0) vScrollerHeight = 40.0;
    _verticalScroller.frame = NSMakeRect(
        bounds.size.width - kScrollerWidth - kScrollerMargin,
        kScrollerMargin + kScrollerWidth,
        kScrollerWidth,
        vScrollerHeight
    );
}

- (void)updateContentBoundingBox {
    CGRect bb = CGRectZero;
    BOOL hasModels = NO;

    for (NSUInteger mi = 0; mi < _flatModelCount; mi++) {
        XLModelLookup *lookup = &_flatModelLookups[mi];
        if (!lookup->hasBounds) continue;

        float minX = lookup->boundsMinX;
        float maxX = lookup->boundsMaxX;
        float minY = lookup->boundsMinY;
        float maxY = lookup->boundsMaxY;

        if (!hasModels) {
            bb = CGRectMake(minX, minY, maxX - minX, maxY - minY);
            hasModels = YES;
        } else {
            CGRect modelRect = CGRectMake(minX, minY, maxX - minX, maxY - minY);
            bb = CGRectUnion(bb, modelRect);
        }
    }

    if (!hasModels) {
        bb = CGRectMake(-500.0, 0.0, 1000.0, 500.0);
    }

    CGFloat padX = bb.size.width * 0.1;
    CGFloat padY = bb.size.height * 0.1;
    bb = CGRectInset(bb, -padX, -padY);

    _contentBoundingBox = bb;
}

- (void)updateScrollbars {
    if (!_scrollbarsEnabled || _show3D) {
        [self hideScrollbarsAnimated:NO];
        return;
    }

    [self layoutScrollbars];
    [self updateContentBoundingBox];

    CGSize drawableSize = _mlayer.drawableSize;
    if (drawableSize.width <= 0 || drawableSize.height <= 0) return;

    float aspect = (float)drawableSize.width / (float)drawableSize.height;
    CGRect visibleRect = [_cameraController visibleRectForAspect:aspect];
    CGRect contentRect = _contentBoundingBox;
    CGRect totalRect = CGRectUnion(visibleRect, contentRect);

    BOOL needsHScroller = (totalRect.size.width > visibleRect.size.width * 1.01);
    if (needsHScroller) {
        double knobProportion = visibleRect.size.width / totalRect.size.width;
        double scrollPosition = (visibleRect.origin.x - totalRect.origin.x) /
                                (totalRect.size.width - visibleRect.size.width);
        scrollPosition = fmax(0.0, fmin(1.0, scrollPosition));
        _horizontalScroller.doubleValue = scrollPosition;
        _horizontalScroller.knobProportion = knobProportion;
        [_horizontalScroller setEnabled:YES];
    }

    BOOL needsVScroller = (totalRect.size.height > visibleRect.size.height * 1.01);
    if (needsVScroller) {
        double knobProportion = visibleRect.size.height / totalRect.size.height;
        double scrollPosition = (visibleRect.origin.y - totalRect.origin.y) /
                                (totalRect.size.height - visibleRect.size.height);
        scrollPosition = fmax(0.0, fmin(1.0, scrollPosition));
        scrollPosition = 1.0 - scrollPosition;
        _verticalScroller.doubleValue = scrollPosition;
        _verticalScroller.knobProportion = knobProportion;
        [_verticalScroller setEnabled:YES];
    }

    BOOL shouldShow = needsHScroller || needsVScroller;
    if (shouldShow) {
        _horizontalScroller.hidden = !needsHScroller;
        _verticalScroller.hidden = !needsVScroller;
        [self showScrollbarsAnimated:YES];
        [self resetScrollbarFadeTimer];
    } else {
        [self hideScrollbarsAnimated:YES];
    }
}

- (void)resetScrollbarFadeTimer {
    [_scrollbarFadeTimer invalidate];
    _scrollbarFadeTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                          target:self
                                                        selector:@selector(scrollbarFadeTimerFired:)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)scrollbarFadeTimerFired:(NSTimer *)timer {
    _scrollbarFadeTimer = nil;
    [self hideScrollbarsAnimated:YES];
}

- (void)showScrollbarsAnimated:(BOOL)animated {
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            if (!self->_horizontalScroller.hidden)
                self->_horizontalScroller.animator.alphaValue = 1.0;
            if (!self->_verticalScroller.hidden)
                self->_verticalScroller.animator.alphaValue = 1.0;
        }];
    } else {
        if (!_horizontalScroller.hidden) _horizontalScroller.alphaValue = 1.0;
        if (!_verticalScroller.hidden) _verticalScroller.alphaValue = 1.0;
    }
}

- (void)hideScrollbarsAnimated:(BOOL)animated {
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.3;
            self->_horizontalScroller.animator.alphaValue = 0.0;
            self->_verticalScroller.animator.alphaValue = 0.0;
        } completionHandler:^{
            if (self->_horizontalScroller.alphaValue == 0.0)
                self->_horizontalScroller.hidden = YES;
            if (self->_verticalScroller.alphaValue == 0.0)
                self->_verticalScroller.hidden = YES;
        }];
    } else {
        _horizontalScroller.alphaValue = 0.0;
        _horizontalScroller.hidden = YES;
        _verticalScroller.alphaValue = 0.0;
        _verticalScroller.hidden = YES;
    }
}

- (void)horizontalScrollerAction:(NSScroller *)sender {
    if (_show3D) return;

    CGSize drawableSize = _mlayer.drawableSize;
    if (drawableSize.width <= 0 || drawableSize.height <= 0) return;

    float aspect = (float)drawableSize.width / (float)drawableSize.height;
    CGRect visibleRect = [_cameraController visibleRectForAspect:aspect];
    CGRect contentRect = _contentBoundingBox;
    CGRect totalRect = CGRectUnion(visibleRect, contentRect);

    double scrollableRange = totalRect.size.width - visibleRect.size.width;
    if (scrollableRange <= 0) return;

    float newCenterX;

    switch (sender.hitPart) {
        case NSScrollerKnob:
        case NSScrollerKnobSlot: {
            double position = sender.doubleValue;
            float newMinX = totalRect.origin.x + position * scrollableRange;
            newCenterX = newMinX + visibleRect.size.width * 0.5f;
            break;
        }
        case NSScrollerDecrementPage:
        case NSScrollerDecrementLine: {
            newCenterX = _cameraController.target.x - visibleRect.size.width * 0.25f;
            break;
        }
        case NSScrollerIncrementPage:
        case NSScrollerIncrementLine: {
            newCenterX = _cameraController.target.x + visibleRect.size.width * 0.25f;
            break;
        }
        default:
            return;
    }

    [_cameraController setTargetX:newCenterX];
    _contentDirty = YES;
    [self updateScrollbars];

    if ([_delegate respondsToSelector:@selector(previewView:didChangeCamera:)]) {
        [_delegate previewView:self didChangeCamera:_cameraController];
    }
}

- (void)verticalScrollerAction:(NSScroller *)sender {
    if (_show3D) return;

    CGSize drawableSize = _mlayer.drawableSize;
    if (drawableSize.width <= 0 || drawableSize.height <= 0) return;

    float aspect = (float)drawableSize.width / (float)drawableSize.height;
    CGRect visibleRect = [_cameraController visibleRectForAspect:aspect];
    CGRect contentRect = _contentBoundingBox;
    CGRect totalRect = CGRectUnion(visibleRect, contentRect);

    double scrollableRange = totalRect.size.height - visibleRect.size.height;
    if (scrollableRange <= 0) return;

    float newCenterY;

    switch (sender.hitPart) {
        case NSScrollerKnob:
        case NSScrollerKnobSlot: {
            double position = 1.0 - sender.doubleValue;
            float newMinY = totalRect.origin.y + position * scrollableRange;
            newCenterY = newMinY + visibleRect.size.height * 0.5f;
            break;
        }
        case NSScrollerDecrementPage:
        case NSScrollerDecrementLine: {
            newCenterY = _cameraController.target.y + visibleRect.size.height * 0.25f;
            break;
        }
        case NSScrollerIncrementPage:
        case NSScrollerIncrementLine: {
            newCenterY = _cameraController.target.y - visibleRect.size.height * 0.25f;
            break;
        }
        default:
            return;
    }

    [_cameraController setTargetY:newCenterY];
    _contentDirty = YES;
    [self updateScrollbars];

    if ([_delegate respondsToSelector:@selector(previewView:didChangeCamera:)]) {
        [_delegate previewView:self didChangeCamera:_cameraController];
    }
}

- (void)setScrollbarsEnabled:(BOOL)scrollbarsEnabled {
    _scrollbarsEnabled = scrollbarsEnabled;
    if (!scrollbarsEnabled) {
        [self hideScrollbarsAnimated:YES];
    } else {
        _scrollbarsDirty = YES;
    }
}

@end
