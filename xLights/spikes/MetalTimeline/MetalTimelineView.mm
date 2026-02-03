#import "MetalTimelineView.h"
#import <QuartzCore/QuartzCore.h>
#import <mach/mach_time.h>
#import <string>
#import <algorithm>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation MetalTimelineView {
    // Metal pipeline
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLBuffer> _uniformBuffer;
    CAMetalLayer *_metalLayer;

    // Display link for vsync - use CADisplayLink on macOS 14+, CVDisplayLink as fallback
    CADisplayLink *_caDisplayLink API_AVAILABLE(macos(14.0));
    CVDisplayLinkRef _cvDisplayLink;
    BOOL _needsRedraw;

    // Data
    std::vector<EffectBlock> _effects;
    std::vector<std::string> _rowNames;
    int _numRows;
    double _totalDuration;

    // Interaction state
    int _selectedEffectId;
    int _dragEffectId;
    CGPoint _dragStartPoint;
    float _dragOrigStartTime;
    float _dragOrigEndTime;
    BOOL _isDragging;

    // Performance tracking
    uint64_t _frameCount;
    double _fpsAccumulator;
    double _lastFPSUpdate;
    double _lastFrameTime;
    double _fps;
    mach_timebase_info_data_t _timebaseInfo;

    // Scroll momentum
    BOOL _isScrolling;

    // Triple-buffered vertex storage to avoid per-frame allocation
    id<MTLBuffer> _vertexBuffers[3];
    id<MTLBuffer> _overlayBuffers[3];
    int _currentBuffer;
    size_t _vertexBufferCapacity;
    size_t _overlayBufferCapacity;
}

@synthesize device = _device;
@synthesize metalLayer = _metalLayer;
@synthesize lastFrameTime = _lastFrameTime;
@synthesize fps = _fps;

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
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;

    _scrollOffsetX = 0;
    _scrollOffsetY = 0;
    _zoomScale = 1.0;
    _playheadPosition = 5.0;
    _selectedEffectId = -1;
    _dragEffectId = -1;
    _isDragging = NO;
    _needsRedraw = YES;
    _frameCount = 0;
    _fps = 0;
    _fpsAccumulator = 0;
    _lastFPSUpdate = 0;

    mach_timebase_info(&_timebaseInfo);
    _currentBuffer = 0;
    _vertexBufferCapacity = 0;
    _overlayBufferCapacity = 0;

    [self setupMetal];
    [self setupDisplayLink];
}

- (CALayer *)makeBackingLayer {
    _metalLayer = [CAMetalLayer layer];
    return _metalLayer;
}

- (void)setupMetal {
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) {
        NSLog(@"Metal is not supported on this device");
        return;
    }

    _metalLayer.device = _device;
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.framebufferOnly = YES;
    _metalLayer.presentsWithTransaction = NO;
    _metalLayer.displaySyncEnabled = YES;

    // Enable EDR / ProMotion if available
    if (@available(macOS 12.0, *)) {
        _metalLayer.wantsExtendedDynamicRangeContent = NO;
    }

    // Set up for ProMotion (120Hz) by using maximum frame rate
    if (@available(macOS 14.0, *)) {
        // Use maximum display refresh rate
    }

    _commandQueue = [_device newCommandQueue];

    [self buildPipeline];
}

- (void)buildPipeline {
    NSError *error = nil;

    // Load shaders from .metal source file compiled into default library,
    // or compile from source at runtime for standalone testing
    NSString *shaderPath = [[NSBundle mainBundle] pathForResource:@"TimelineShaders" ofType:@"metallib"];
    id<MTLLibrary> library = nil;

    if (shaderPath) {
        NSURL *shaderURL = [NSURL fileURLWithPath:shaderPath];
        library = [_device newLibraryWithURL:shaderURL error:&error];
    }

    if (!library) {
        // Try loading from default library (Xcode compiles .metal files automatically)
        library = [_device newDefaultLibrary];
    }

    if (!library) {
        // Fallback: compile from source at runtime
        NSString *sourcePath = [[NSBundle mainBundle] pathForResource:@"TimelineShaders" ofType:@"metal"];
        if (sourcePath) {
            NSString *source = [NSString stringWithContentsOfFile:sourcePath encoding:NSUTF8StringEncoding error:&error];
            if (source) {
                MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
                library = [_device newLibraryWithSource:source options:options error:&error];
            }
        }
    }

    if (!library) {
        NSLog(@"Failed to load Metal library: %@", error);
        // Compile shader source inline as last resort
        NSString *shaderSource = @
            "#include <metal_stdlib>\n"
            "using namespace metal;\n"
            "struct VertexIn { float2 position [[attribute(0)]]; float4 color [[attribute(1)]]; };\n"
            "struct VertexOut { float4 position [[position]]; float4 color; };\n"
            "struct Uniforms { float2 viewportSize; float2 scrollOffset; float zoomScale; float padding; };\n"
            "vertex VertexOut timelineVertex(VertexIn in [[stage_in]], constant Uniforms &u [[buffer(2)]]) {\n"
            "  VertexOut out;\n"
            "  float2 pos = in.position;\n"
            "  pos.x = (pos.x - u.scrollOffset.x) * u.zoomScale;\n"
            "  pos.y = pos.y - u.scrollOffset.y;\n"
            "  out.position = float4((pos.x / u.viewportSize.x) * 2.0 - 1.0, 1.0 - (pos.y / u.viewportSize.y) * 2.0, 0.0, 1.0);\n"
            "  out.color = in.color;\n"
            "  return out;\n"
            "}\n"
            "fragment float4 timelineFragment(VertexOut in [[stage_in]]) { return in.color; }\n";

        MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
        library = [_device newLibraryWithSource:shaderSource options:options error:&error];
        if (!library) {
            NSLog(@"Failed to compile inline shaders: %@", error);
            return;
        }
    }

    id<MTLFunction> vertexFunc = [library newFunctionWithName:@"timelineVertex"];
    id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"timelineFragment"];

    // Vertex descriptor matching TimelineVertex struct
    MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
    // position: float2 at offset 0
    vertexDesc.attributes[0].format = MTLVertexFormatFloat2;
    vertexDesc.attributes[0].offset = 0;
    vertexDesc.attributes[0].bufferIndex = 0;
    // color: float4 at offset 8
    vertexDesc.attributes[1].format = MTLVertexFormatFloat4;
    vertexDesc.attributes[1].offset = sizeof(simd_float2);
    vertexDesc.attributes[1].bufferIndex = 0;
    // stride
    vertexDesc.layouts[0].stride = sizeof(TimelineVertex);
    vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;

    MTLRenderPipelineDescriptor *pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.vertexFunction = vertexFunc;
    pipelineDesc.fragmentFunction = fragmentFunc;
    pipelineDesc.vertexDescriptor = vertexDesc;
    pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    // Enable alpha blending for selection highlights and playhead
    pipelineDesc.colorAttachments[0].blendingEnabled = YES;
    pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (!_pipelineState) {
        NSLog(@"Failed to create pipeline state: %@", error);
        return;
    }

    _uniformBuffer = [_device newBufferWithLength:sizeof(TimelineUniforms) * 2
                                          options:MTLResourceStorageModeShared];
}

#pragma mark - Display Link

static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                     const CVTimeStamp *inNow,
                                     const CVTimeStamp *inOutputTime,
                                     CVOptionFlags flagsIn,
                                     CVOptionFlags *flagsOut,
                                     void *displayLinkContext) {
    @autoreleasepool {
        MetalTimelineView *view = (__bridge MetalTimelineView *)displayLinkContext;
        [view renderFrame];
    }
    return kCVReturnSuccess;
}

- (void)setupDisplayLink {
    if (@available(macOS 14.0, *)) {
        // Modern CADisplayLink - supports ProMotion 120Hz natively
        _caDisplayLink = [self displayLinkWithTarget:self selector:@selector(displayLinkFired:)];
        [_caDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    } else {
        // Fallback to CVDisplayLink for macOS 13
        CVDisplayLinkCreateWithActiveCGDisplays(&_cvDisplayLink);
        CVDisplayLinkSetOutputCallback(_cvDisplayLink, &displayLinkCallback, (__bridge void *)self);
        CGDirectDisplayID displayID = CGMainDisplayID();
        CVDisplayLinkSetCurrentCGDisplay(_cvDisplayLink, displayID);
        CVDisplayLinkStart(_cvDisplayLink);
    }
}

- (void)displayLinkFired:(CADisplayLink *)sender API_AVAILABLE(macos(14.0)) {
    [self renderFrame];
}

- (void)dealloc {
    if (@available(macOS 14.0, *)) {
        if (_caDisplayLink) {
            [_caDisplayLink invalidate];
            _caDisplayLink = nil;
        }
    }
    if (_cvDisplayLink) {
        CVDisplayLinkStop(_cvDisplayLink);
        CVDisplayLinkRelease(_cvDisplayLink);
        _cvDisplayLink = NULL;
    }
}

#pragma mark - View Lifecycle

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        CGFloat scale = self.window.backingScaleFactor;
        _metalLayer.contentsScale = scale;
        _needsRedraw = YES;
    }
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    if (self.window) {
        CGFloat scale = self.window.backingScaleFactor;
        _metalLayer.drawableSize = CGSizeMake(newSize.width * scale, newSize.height * scale);
        _metalLayer.contentsScale = scale;
    }
    _needsRedraw = YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

#pragma mark - Mock Data Generation

- (void)generateMockData:(int)numRows effectsPerRow:(int)effectsPerRow totalDuration:(double)duration {
    _numRows = numRows;
    _totalDuration = duration;
    _effects.clear();
    _rowNames.clear();

    int effectId = 0;

    // Bright, high-saturation effect colors for clear visibility on dark background
    struct EffectColor { float r, g, b; };
    EffectColor colors[] = {
        {1.00f, 0.30f, 0.30f},  // bright red
        {0.30f, 0.90f, 0.35f},  // bright green
        {0.40f, 0.55f, 1.00f},  // bright blue
        {1.00f, 0.70f, 0.15f},  // bright orange
        {0.90f, 0.35f, 0.90f},  // bright purple
        {0.25f, 0.95f, 0.95f},  // bright cyan
        {1.00f, 0.95f, 0.25f},  // bright yellow
        {1.00f, 0.45f, 0.65f},  // bright pink
        {0.45f, 1.00f, 0.60f},  // bright mint
        {0.85f, 0.55f, 0.25f},  // bright amber
        {0.65f, 0.40f, 1.00f},  // bright indigo
        {0.90f, 0.25f, 0.50f},  // bright crimson
        {0.50f, 0.90f, 1.00f},  // bright sky
        {0.75f, 1.00f, 0.35f},  // bright lime
        {1.00f, 0.60f, 0.55f},  // bright coral
        {0.70f, 0.35f, 0.75f},  // bright plum
    };
    int numColors = sizeof(colors) / sizeof(colors[0]);

    srand(42); // deterministic for benchmarking

    for (int row = 0; row < numRows; row++) {
        char name[64];
        snprintf(name, sizeof(name), "Model %d - %s", row + 1,
                 (row % 4 == 0) ? "Arch" :
                 (row % 4 == 1) ? "Matrix" :
                 (row % 4 == 2) ? "Tree" : "Star");
        _rowNames.push_back(std::string(name));

        double t = 0.0;
        for (int e = 0; e < effectsPerRow; e++) {
            EffectBlock block;
            block.rowIndex = row;

            // Random gap between effects (0 to 0.5 seconds)
            double gap = (rand() % 50) / 100.0;
            t += gap;

            block.startTime = (float)t;

            // Random duration (0.5 to 4 seconds)
            double dur = 0.5 + (rand() % 350) / 100.0;
            block.endTime = (float)(t + dur);

            // Pick a color using a simple hash for good distribution
            unsigned int hash = (unsigned int)(row * 13 + e * 7 + (row ^ e) * 3);
            int ci = (int)(hash % numColors);
            block.r = colors[ci].r;
            block.g = colors[ci].g;
            block.b = colors[ci].b;
            block.a = 1.0f;

            block.selected = false;
            block.effectId = effectId++;

            _effects.push_back(block);
            t += dur;
        }
    }

    _needsRedraw = YES;
    NSLog(@"Generated %d effects across %d rows (%.1f seconds)", (int)_effects.size(), numRows, duration);
}

- (id<MTLBuffer>)getVertexBuffer:(int)index capacity:(size_t)needed currentCapacity:(size_t *)cap {
    if (needed > *cap || _vertexBuffers[index] == nil) {
        size_t newCap = std::max(needed * 2, (size_t)(1024 * 1024)); // at least 1MB
        _vertexBuffers[index] = [_device newBufferWithLength:newCap options:MTLResourceStorageModeShared];
        *cap = newCap;
    }
    return _vertexBuffers[index];
}

- (id<MTLBuffer>)getOverlayBuffer:(int)index capacity:(size_t)needed currentCapacity:(size_t *)cap {
    if (needed > *cap || _overlayBuffers[index] == nil) {
        size_t newCap = std::max(needed * 2, (size_t)(256 * 1024)); // at least 256KB
        _overlayBuffers[index] = [_device newBufferWithLength:newCap options:MTLResourceStorageModeShared];
        *cap = newCap;
    }
    return _overlayBuffers[index];
}

#pragma mark - Rendering

- (void)renderFrame {
    uint64_t startTime = mach_absolute_time();

    @autoreleasepool {
        id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
        if (!drawable) return;

        CGSize drawableSize = _metalLayer.drawableSize;
        if (drawableSize.width <= 0 || drawableSize.height <= 0) return;

        CGFloat scale = _metalLayer.contentsScale;
        float viewWidth = (float)drawableSize.width;
        float viewHeight = (float)drawableSize.height;

        // Scaled layout constants
        float scaledRowHeight = kRowHeight * (float)scale;
        float scaledRulerHeight = kRulerHeight * (float)scale;
        float scaledLabelWidth = kRowLabelWidth * (float)scale;
        float scaledPPS = kPixelsPerSecond * (float)scale;

        // PASS 1 uniforms: scrollable content with zoom
        TimelineUniforms *uniforms = (TimelineUniforms *)_uniformBuffer.contents;
        uniforms[0].viewportSize = simd_make_float2(viewWidth, viewHeight);
        uniforms[0].scrollOffset = simd_make_float2((float)_scrollOffsetX, (float)_scrollOffsetY);
        uniforms[0].zoomScale = (float)_zoomScale;
        uniforms[0].padding = 0;

        // PASS 2 uniforms: fixed overlay (no scroll, no zoom)
        uniforms[1].viewportSize = simd_make_float2(viewWidth, viewHeight);
        uniforms[1].scrollOffset = simd_make_float2(0, 0);
        uniforms[1].zoomScale = 1.0f;
        uniforms[1].padding = 0;

        // Visible range in content coordinates
        float visibleLeft = (float)_scrollOffsetX;
        float visibleRight = visibleLeft + viewWidth / (float)_zoomScale;
        float visibleTop = (float)_scrollOffsetY;
        float visibleBottom = visibleTop + viewHeight;

        // ---- PASS 1: Scrollable content ----
        std::vector<TimelineVertex> contentVerts;
        contentVerts.reserve(80000);

        // Background
        [self addRect:contentVerts
                    x:visibleLeft y:visibleTop
                width:(visibleRight - visibleLeft) height:(visibleBottom - visibleTop)
                    r:0.14f g:0.14f b:0.16f a:1.0f];

        // Alternating row backgrounds
        for (int row = 0; row < _numRows; row++) {
            float y = scaledRulerHeight + row * scaledRowHeight;
            if (y + scaledRowHeight < visibleTop || y > visibleBottom) continue;
            float bgShade = (row % 2 == 0) ? 0.17f : 0.19f;
            [self addRect:contentVerts
                        x:visibleLeft y:y
                    width:(visibleRight - visibleLeft) height:scaledRowHeight
                        r:bgShade g:bgShade b:bgShade + 0.01f a:1.0f];
        }

        // Horizontal grid lines
        for (int row = 0; row <= _numRows; row++) {
            float y = scaledRulerHeight + row * scaledRowHeight;
            if (y < visibleTop - 1 || y > visibleBottom + 1) continue;
            [self addRect:contentVerts
                        x:visibleLeft y:y
                    width:(visibleRight - visibleLeft) height:1.0f
                        r:0.25f g:0.25f b:0.28f a:0.6f];
        }

        // Vertical grid lines (time ticks)
        float tickSpacing = [self tickSpacingForZoom:_zoomScale scale:scale];
        float startTick = floor(visibleLeft / (scaledPPS * tickSpacing)) * tickSpacing;
        for (float t = startTick; t * scaledPPS <= visibleRight; t += tickSpacing) {
            float x = t * scaledPPS;
            [self addRect:contentVerts
                        x:x y:visibleTop
                    width:1.0f height:(visibleBottom - visibleTop)
                        r:0.25f g:0.25f b:0.28f a:0.35f];
        }

        // Effect blocks
        for (const auto &effect : _effects) {
            float x = effect.startTime * scaledPPS;
            float x2 = effect.endTime * scaledPPS;
            float y = scaledRulerHeight + effect.rowIndex * scaledRowHeight + kEffectPadding * (float)scale;
            float h = scaledRowHeight - 2.0f * kEffectPadding * (float)scale;

            if (x2 < visibleLeft || x > visibleRight) continue;
            if (y + h < visibleTop || y > visibleBottom) continue;

            float er = effect.r, eg = effect.g, eb = effect.b;

            // Selection highlight (white border)
            if (effect.effectId == _selectedEffectId) {
                [self addRect:contentVerts
                            x:x - 2.0f y:y - 2.0f
                        width:(x2 - x) + 4.0f height:h + 4.0f
                            r:1.0f g:1.0f b:1.0f a:0.9f];
            }

            // Effect body
            [self addRect:contentVerts x:x y:y width:(x2 - x) height:h r:er g:eg b:eb a:effect.a];

            // Top highlight
            [self addRect:contentVerts x:x y:y width:(x2 - x) height:2.0f * (float)scale
                        r:fmin(er + 0.2f, 1.0f) g:fmin(eg + 0.2f, 1.0f) b:fmin(eb + 0.2f, 1.0f) a:0.4f];

            // Bottom shadow
            [self addRect:contentVerts x:x y:y + h - 2.0f * (float)scale width:(x2 - x) height:2.0f * (float)scale
                        r:er * 0.5f g:eg * 0.5f b:eb * 0.5f a:0.5f];
        }

        // Playhead in content space (scrolls horizontally with content)
        float playX = (float)_playheadPosition * scaledPPS;
        if (playX >= visibleLeft && playX <= visibleRight) {
            [self addRect:contentVerts
                        x:playX - 1.5f * (float)scale y:visibleTop
                    width:3.0f * (float)scale height:(visibleBottom - visibleTop)
                        r:1.0f g:0.15f b:0.15f a:0.85f];
        }

        // ---- PASS 2: Fixed overlay (ruler, labels) in screen space ----
        std::vector<TimelineVertex> overlayVerts;
        overlayVerts.reserve(20000);

        // Row label background (fixed left panel)
        [self addRect:overlayVerts
                    x:0 y:0
                width:scaledLabelWidth height:viewHeight
                    r:0.11f g:0.11f b:0.13f a:1.0f];

        // Row label separator
        [self addRect:overlayVerts
                    x:scaledLabelWidth - 1.0f y:0
                width:2.0f height:viewHeight
                    r:0.30f g:0.30f b:0.35f a:1.0f];

        // Row name areas (in overlay space, accounting for vertical scroll)
        for (int row = 0; row < _numRows; row++) {
            float y = scaledRulerHeight + row * scaledRowHeight - (float)_scrollOffsetY;
            if (y + scaledRowHeight < 0 || y > viewHeight) continue;

            // Alternating shade for label area
            float bgShade = (row % 2 == 0) ? 0.13f : 0.15f;
            [self addRect:overlayVerts
                        x:0 y:y
                    width:scaledLabelWidth height:scaledRowHeight
                        r:bgShade g:bgShade b:bgShade + 0.01f a:1.0f];

            // Row grid line in label area
            [self addRect:overlayVerts
                        x:0 y:y + scaledRowHeight - 1.0f
                    width:scaledLabelWidth height:1.0f
                        r:0.25f g:0.25f b:0.28f a:0.5f];

            // Simple row indicator bar (colored strip to make rows identifiable)
            float hue = fmod(row * 0.07f, 1.0f);
            float cr, cg, cb;
            [self hsvToRgb:hue s:0.5f v:0.5f r:&cr g:&cg b:&cb];
            [self addRect:overlayVerts
                        x:4.0f * (float)scale y:y + 4.0f * (float)scale
                    width:4.0f * (float)scale height:scaledRowHeight - 8.0f * (float)scale
                        r:cr g:cg b:cb a:0.8f];
        }

        // Ruler background (full width, fixed at top)
        [self addRect:overlayVerts
                    x:0 y:0
                width:viewWidth height:scaledRulerHeight
                    r:0.10f g:0.10f b:0.12f a:1.0f];

        // Ruler bottom border
        [self addRect:overlayVerts
                    x:0 y:scaledRulerHeight - 1.0f
                width:viewWidth height:2.0f
                    r:0.40f g:0.40f b:0.45f a:0.8f];

        // Ruler tick marks (need to account for scroll/zoom to place correctly in screen space)
        float minorTickSpacing = tickSpacing / 4.0f;
        float startMinor = floor(visibleLeft / (scaledPPS * minorTickSpacing)) * minorTickSpacing;
        for (float t = startMinor; t * scaledPPS <= visibleRight; t += minorTickSpacing) {
            // Convert content coordinate to screen coordinate
            float contentX = t * scaledPPS;
            float screenX = (contentX - (float)_scrollOffsetX) * (float)_zoomScale;
            if (screenX < scaledLabelWidth || screenX > viewWidth) continue;

            bool isMajor = fmod(t + 0.0001f, tickSpacing) < 0.01f;
            float tickH = isMajor ? scaledRulerHeight * 0.65f : scaledRulerHeight * 0.3f;
            float tickAlpha = isMajor ? 0.9f : 0.4f;

            [self addRect:overlayVerts
                        x:screenX y:scaledRulerHeight - tickH
                    width:(isMajor ? 2.0f : 1.0f) height:tickH
                        r:0.65f g:0.65f b:0.70f a:tickAlpha];
        }

        // Playhead indicator in ruler (fixed overlay)
        if (playX >= visibleLeft && playX <= visibleRight) {
            float screenPlayX = (playX - (float)_scrollOffsetX) * (float)_zoomScale;
            // Playhead triangle at top of ruler
            float triSize = 8.0f * (float)scale;
            TimelineVertex tv;
            tv.color = simd_make_float4(1.0f, 0.15f, 0.15f, 0.95f);
            tv.position = simd_make_float2(screenPlayX - triSize, 0);
            overlayVerts.push_back(tv);
            tv.position = simd_make_float2(screenPlayX + triSize, 0);
            overlayVerts.push_back(tv);
            tv.position = simd_make_float2(screenPlayX, triSize * 1.5f);
            overlayVerts.push_back(tv);

            // Thin playhead line through ruler
            [self addRect:overlayVerts
                        x:screenPlayX - 1.0f y:0
                    width:2.0f height:scaledRulerHeight
                        r:1.0f g:0.15f b:0.15f a:0.9f];
        }

        // Corner piece (top-left, above labels)
        [self addRect:overlayVerts
                    x:0 y:0
                width:scaledLabelWidth height:scaledRulerHeight
                    r:0.08f g:0.08f b:0.10f a:1.0f];

        // ---- Encode and submit ----
        MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
        passDesc.colorAttachments[0].texture = drawable.texture;
        passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
        passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0.12, 0.12, 0.14, 1.0);

        id<MTLCommandBuffer> cmdBuffer = [_commandQueue commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [cmdBuffer renderCommandEncoderWithDescriptor:passDesc];
        [encoder setRenderPipelineState:_pipelineState];

        int bufIdx = _currentBuffer;
        _currentBuffer = (_currentBuffer + 1) % 3;

        // Draw pass 1: scrollable content
        if (!contentVerts.empty()) {
            size_t sz = contentVerts.size() * sizeof(TimelineVertex);
            id<MTLBuffer> vb = [self getVertexBuffer:bufIdx capacity:sz currentCapacity:&_vertexBufferCapacity];
            memcpy(vb.contents, contentVerts.data(), sz);
            [encoder setVertexBuffer:vb offset:0 atIndex:0];
            [encoder setVertexBuffer:_uniformBuffer offset:0 atIndex:2];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:contentVerts.size()];
        }

        // Draw pass 2: fixed overlays
        if (!overlayVerts.empty()) {
            size_t sz = overlayVerts.size() * sizeof(TimelineVertex);
            id<MTLBuffer> vb = [self getOverlayBuffer:bufIdx capacity:sz currentCapacity:&_overlayBufferCapacity];
            memcpy(vb.contents, overlayVerts.data(), sz);
            [encoder setVertexBuffer:vb offset:0 atIndex:0];
            [encoder setVertexBuffer:_uniformBuffer offset:sizeof(TimelineUniforms) atIndex:2];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:overlayVerts.size()];
        }

        [encoder endEncoding];
        [cmdBuffer presentDrawable:drawable];
        [cmdBuffer commit];
    }

    // Performance tracking
    uint64_t endTime = mach_absolute_time();
    uint64_t elapsed = endTime - startTime;
    double elapsedMs = (double)elapsed * (double)_timebaseInfo.numer / (double)_timebaseInfo.denom / 1e6;
    _lastFrameTime = elapsedMs;
    _frameCount++;
    _fpsAccumulator += elapsedMs;

    double now = (double)mach_absolute_time() * (double)_timebaseInfo.numer / (double)_timebaseInfo.denom / 1e9;
    if (now - _lastFPSUpdate >= 1.0) {
        _fps = _frameCount / (now - _lastFPSUpdate);
        _frameCount = 0;
        _lastFPSUpdate = now;
        _fpsAccumulator = 0;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.window) {
                self.window.title = [NSString stringWithFormat:@"Metal Timeline Spike - %.0f FPS (%.2f ms/frame) - %lu effects",
                                     self->_fps, self->_lastFrameTime, (unsigned long)self->_effects.size()];
            }
        });
    }
}

#pragma mark - Geometry Helpers

- (void)addRect:(std::vector<TimelineVertex> &)vertices
              x:(float)x y:(float)y
          width:(float)w height:(float)h
              r:(float)r g:(float)g b:(float)b a:(float)a {
    simd_float4 color = simd_make_float4(r, g, b, a);

    // Two triangles for a rectangle
    TimelineVertex tl = { simd_make_float2(x, y), color };
    TimelineVertex tr = { simd_make_float2(x + w, y), color };
    TimelineVertex bl = { simd_make_float2(x, y + h), color };
    TimelineVertex br = { simd_make_float2(x + w, y + h), color };

    // Triangle 1
    vertices.push_back(tl);
    vertices.push_back(tr);
    vertices.push_back(bl);

    // Triangle 2
    vertices.push_back(tr);
    vertices.push_back(br);
    vertices.push_back(bl);
}

- (void)hsvToRgb:(float)h s:(float)s v:(float)v r:(float *)r g:(float *)g b:(float *)b {
    int i = (int)(h * 6.0f);
    float f = h * 6.0f - i;
    float p = v * (1.0f - s);
    float q = v * (1.0f - f * s);
    float t = v * (1.0f - (1.0f - f) * s);
    switch (i % 6) {
        case 0: *r = v; *g = t; *b = p; break;
        case 1: *r = q; *g = v; *b = p; break;
        case 2: *r = p; *g = v; *b = t; break;
        case 3: *r = p; *g = q; *b = v; break;
        case 4: *r = t; *g = p; *b = v; break;
        case 5: *r = v; *g = p; *b = q; break;
        default: *r = v; *g = v; *b = v; break;
    }
}

- (float)tickSpacingForZoom:(CGFloat)zoom scale:(CGFloat)scale {
    float effectiveZoom = (float)zoom;
    // Choose tick spacing based on zoom level so ticks are readable
    if (effectiveZoom < 0.3) return 10.0f;
    if (effectiveZoom < 0.7) return 5.0f;
    if (effectiveZoom < 1.5) return 2.0f;
    if (effectiveZoom < 4.0) return 1.0f;
    if (effectiveZoom < 8.0) return 0.5f;
    return 0.25f;
}

#pragma mark - Hit Testing

- (int)effectAtPoint:(NSPoint)point {
    CGFloat scale = self.window ? self.window.backingScaleFactor : 2.0;
    float scaledPPS = kPixelsPerSecond * (float)scale;
    float scaledRowHeight = kRowHeight * (float)scale;
    float scaledRulerHeight = kRulerHeight * (float)scale;
    float scaledLabelWidth = kRowLabelWidth * (float)scale;

    // Convert view point to pixel point
    float px = (float)point.x * (float)scale;
    float py = (float)(self.bounds.size.height - point.y) * (float)scale;  // flip Y

    // Convert screen pixel to content coordinate
    float contentX = px / (float)_zoomScale + (float)_scrollOffsetX;
    float contentY = py + (float)_scrollOffsetY;

    // Skip if in label area
    if (px < scaledLabelWidth) return -1;

    for (const auto &effect : _effects) {
        float x = effect.startTime * scaledPPS;
        float x2 = effect.endTime * scaledPPS;
        float y = scaledRulerHeight + effect.rowIndex * scaledRowHeight + kEffectPadding * (float)scale;
        float h = scaledRowHeight - 2.0f * kEffectPadding * (float)scale;

        if (contentX >= x && contentX <= x2 && contentY >= y && contentY <= y + h) {
            return effect.effectId;
        }
    }
    return -1;
}

- (EffectBlock *)effectWithId:(int)effectId {
    for (auto &effect : _effects) {
        if (effect.effectId == effectId) return &effect;
    }
    return nullptr;
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    int hitId = [self effectAtPoint:loc];

    // Deselect previous
    if (_selectedEffectId >= 0) {
        EffectBlock *prev = [self effectWithId:_selectedEffectId];
        if (prev) prev->selected = false;
    }

    _selectedEffectId = hitId;

    if (hitId >= 0) {
        EffectBlock *hit = [self effectWithId:hitId];
        if (hit) {
            hit->selected = true;
            _dragEffectId = hitId;
            _dragStartPoint = NSPointToCGPoint(loc);
            _dragOrigStartTime = hit->startTime;
            _dragOrigEndTime = hit->endTime;
            _isDragging = NO; // becomes YES on mouseDragged
        }
    }

    _needsRedraw = YES;
}

- (void)mouseDragged:(NSEvent *)event {
    if (_dragEffectId < 0) return;

    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat scale = self.window ? self.window.backingScaleFactor : 2.0;
    float scaledPPS = kPixelsPerSecond * (float)scale;

    _isDragging = YES;

    // Calculate time delta from drag
    float dx = (float)(loc.x - _dragStartPoint.x) * (float)scale / ((float)_zoomScale * scaledPPS);

    EffectBlock *block = [self effectWithId:_dragEffectId];
    if (block) {
        float duration = _dragOrigEndTime - _dragOrigStartTime;
        float newStart = fmax(0.0f, _dragOrigStartTime + dx);
        block->startTime = newStart;
        block->endTime = newStart + duration;
    }

    _needsRedraw = YES;
}

- (void)mouseUp:(NSEvent *)event {
    _dragEffectId = -1;
    _isDragging = NO;
}

#pragma mark - Scroll Events

- (void)scrollWheel:(NSEvent *)event {
    CGFloat scale = self.window ? self.window.backingScaleFactor : 2.0;

    if (event.modifierFlags & NSEventModifierFlagCommand) {
        // Command + scroll = vertical zoom (not implemented, just ignore)
        return;
    }

    // Handle pinch-to-zoom (magnification events come via magnifyWithEvent)
    // Regular scroll: pan
    CGFloat dx = event.scrollingDeltaX;
    CGFloat dy = event.scrollingDeltaY;

    if (event.hasPreciseScrollingDeltas) {
        // Trackpad - use pixel deltas directly
        _scrollOffsetX -= dx * scale / _zoomScale;
        _scrollOffsetY -= dy * scale;
    } else {
        // Mouse wheel - scale up
        _scrollOffsetX -= dx * 20.0 * scale / _zoomScale;
        _scrollOffsetY -= dy * 20.0 * scale;
    }

    // Clamp scroll offset
    _scrollOffsetX = fmax(0, _scrollOffsetX);
    _scrollOffsetY = fmax(0, _scrollOffsetY);

    float maxY = kRulerHeight * scale + _numRows * kRowHeight * scale - self.bounds.size.height * scale;
    if (maxY > 0) {
        _scrollOffsetY = fmin(_scrollOffsetY, maxY);
    } else {
        _scrollOffsetY = 0;
    }

    _needsRedraw = YES;
}

- (void)magnifyWithEvent:(NSEvent *)event {
    CGFloat scale = self.window ? self.window.backingScaleFactor : 2.0;

    // Pinch-to-zoom centered on cursor position
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    float px = (float)loc.x * (float)scale;

    // Content position under cursor before zoom
    float contentX = px / (float)_zoomScale + (float)_scrollOffsetX;

    // Apply zoom
    CGFloat newZoom = _zoomScale * (1.0 + event.magnification);
    newZoom = fmax(kMinZoom, fmin(kMaxZoom, newZoom));
    _zoomScale = newZoom;

    // Adjust scroll so the content under cursor stays put
    _scrollOffsetX = contentX - px / (float)_zoomScale;
    _scrollOffsetX = fmax(0, _scrollOffsetX);

    _needsRedraw = YES;
}

#pragma mark - Keyboard Events

- (void)keyDown:(NSEvent *)event {
    // Space = toggle playhead animation
    if ([event.characters isEqualToString:@" "]) {
        // Animate playhead forward
        _playheadPosition += 0.5;
        _needsRedraw = YES;
    } else if (event.keyCode == 123) { // Left arrow
        _scrollOffsetX = fmax(0, _scrollOffsetX - 50.0 / _zoomScale);
        _needsRedraw = YES;
    } else if (event.keyCode == 124) { // Right arrow
        _scrollOffsetX += 50.0 / _zoomScale;
        _needsRedraw = YES;
    } else if ([event.characters isEqualToString:@"+"]) {
        _zoomScale = fmin(kMaxZoom, _zoomScale * 1.2);
        _needsRedraw = YES;
    } else if ([event.characters isEqualToString:@"-"]) {
        _zoomScale = fmax(kMinZoom, _zoomScale / 1.2);
        _needsRedraw = YES;
    } else {
        [super keyDown:event];
    }
}

@end

#pragma clang diagnostic pop
