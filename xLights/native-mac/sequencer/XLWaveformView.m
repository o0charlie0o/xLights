/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLWaveformView.h"
#import "XLAudioLoader.h"
#import <CoreVideo/CVDisplayLink.h>

static const CGFloat kDefaultZoomLevel = 0.1;   // pixels per ms
static const CGFloat kVerticalPadding = 4.0;     // top/bottom padding in view
static const CGFloat kPlayheadWidth = 1.0;

// Waveform fill color (classic green) as raw RGBA to avoid NSColor lifetime
// issues in CALayerDelegate callbacks
static const CGFloat kWaveR = 0.51, kWaveG = 0.70, kWaveB = 0.81;  // 130/255, 178/255, 207/255
static const CGFloat kBgR = 0.08, kBgG = 0.08, kBgB = 0.08;
static const CGFloat kPlayheadR = 1.0, kPlayheadG = 0.2, kPlayheadB = 0.2;
static const CGFloat kCursorR = 1.0, kCursorG = 1.0, kCursorB = 1.0;  // White cursor line
static const CGFloat kCursorAlpha = 0.6;
static const CGFloat kCenterLineGray = 0.25;

// Maximum number of waveform overview buckets to pre-compute.
// This provides sub-pixel resolution at reasonable zoom levels.
static const NSUInteger kMaxOverviewBuckets = 65536;

@interface XLWaveformView () {
    CVDisplayLinkRef _displayLink;
}

@property (nonatomic, strong) XLAudioSampleData *audioData;
@property (nonatomic, strong) NSArray<NSValue *> *overviewBuckets;
@property (nonatomic, assign) BOOL needsRedraw;
@property (nonatomic, assign) BOOL dragging;

// Cached waveform path for efficient redraw
@property (nonatomic, assign) CGMutablePathRef cachedWaveformPath;
@property (nonatomic, assign) CGFloat cachedZoomLevel;
@property (nonatomic, assign) CGFloat cachedScrollOffsetX;
@property (nonatomic, assign) CGFloat cachedWidth;
@property (nonatomic, assign) CGFloat cachedHeight;

@end

// CVDisplayLink callback — runs on a high-priority background thread.
// Dispatches redraw to the main thread when needed.
static CVReturn waveformDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                             const CVTimeStamp *inNow,
                                             const CVTimeStamp *inOutputTime,
                                             CVOptionFlags flagsIn,
                                             CVOptionFlags *flagsOut,
                                             void *displayLinkContext)
{
    @autoreleasepool {
        XLWaveformView *view = (__bridge XLWaveformView *)displayLinkContext;
        if (view.needsRedraw) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [view.layer setNeedsDisplay];
            });
        }
    }
    return kCVReturnSuccess;
}

@implementation XLWaveformView

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
    _zoomLevel = kDefaultZoomLevel;
    _scrollOffsetX = 0.0;
    _playbackPositionMS = -1.0;
    _cursorPositionMS = -1.0;
    _sequenceLengthMS = 0.0;
    _showStereo = NO;
    _waveformColor = nil;
    _needsRedraw = YES;
    _dragging = NO;

    // Waveform path cache
    _cachedWaveformPath = NULL;
    _cachedZoomLevel = 0;
    _cachedScrollOffsetX = -1;
    _cachedWidth = 0;
    _cachedHeight = 0;

    self.wantsLayer = YES;

    // Set up mouse tracking for cursor line display
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited
                                  | NSTrackingMouseMoved
                                  | NSTrackingActiveInActiveApp
                                  | NSTrackingInVisibleRect;
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                               options:options
                                                                 owner:self
                                                              userInfo:nil];
    [self addTrackingArea:trackingArea];

    [self setupDisplayLink];
}

- (void)dealloc {
    if (_displayLink) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
        _displayLink = NULL;
    }
    if (_cachedWaveformPath) {
        CGPathRelease(_cachedWaveformPath);
        _cachedWaveformPath = NULL;
    }
}

#pragma mark - Layer Backing

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (CALayer *)makeBackingLayer {
    CALayer *layer = [CALayer layer];
    layer.delegate = self;
    layer.needsDisplayOnBoundsChange = YES;
    layer.backgroundColor = CGColorCreateGenericRGB(kBgR, kBgG, kBgB, 1.0);
    return layer;
}

- (void)updateLayer {
    [self.layer setNeedsDisplay];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    CGFloat scale = self.window.backingScaleFactor ?: 1.0;
    self.layer.contentsScale = scale;
    _needsRedraw = YES;
}

#pragma mark - CVDisplayLink

- (void)setupDisplayLink {
    CVDisplayLinkRef dl;
    CVDisplayLinkCreateWithActiveCGDisplays(&dl);
    CVDisplayLinkSetOutputCallback(dl, &waveformDisplayLinkCallback, (__bridge void *)self);
    CVDisplayLinkStart(dl);
    _displayLink = dl;
}

#pragma mark - View Lifecycle

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        CGFloat scale = self.window.backingScaleFactor;
        self.layer.contentsScale = scale;
        _needsRedraw = YES;
    }
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    // Invalidate cached path when view size changes
    if (_cachedWaveformPath) {
        CGPathRelease(_cachedWaveformPath);
        _cachedWaveformPath = NULL;
    }
    _needsRedraw = YES;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

#pragma mark - Audio Data

- (void)loadAudioData:(XLAudioSampleData *)audioData {
    _audioData = audioData;

    // Invalidate cached waveform path
    if (_cachedWaveformPath) {
        CGPathRelease(_cachedWaveformPath);
        _cachedWaveformPath = NULL;
    }

    if (!audioData || audioData.sampleCount == 0) {
        _overviewBuckets = nil;
        _needsRedraw = YES;
        return;
    }

    _sequenceLengthMS = audioData.duration * 1000.0;

    // Compute the overview at a resolution sufficient for pixel-level rendering.
    // Use one bucket per expected pixel at maximum zoom, capped at kMaxOverviewBuckets.
    NSUInteger bucketCount = (NSUInteger)(audioData.duration * audioData.sampleRate);
    if (bucketCount > kMaxOverviewBuckets) {
        bucketCount = kMaxOverviewBuckets;
    }
    if (bucketCount == 0) bucketCount = 1;

    _overviewBuckets = [XLAudioLoader generateWaveformOverview:audioData
                                                   bucketCount:bucketCount];
    _needsRedraw = YES;
}

- (void)clearWaveform {
    _audioData = nil;
    _overviewBuckets = nil;
    _needsRedraw = YES;
}

#pragma mark - Property Setters

- (void)setZoomLevel:(CGFloat)zoomLevel {
    if (fabs(zoomLevel - _zoomLevel) < 0.00001) return;
    _zoomLevel = zoomLevel;
    // Invalidate cached path when zoom changes
    if (_cachedWaveformPath) {
        CGPathRelease(_cachedWaveformPath);
        _cachedWaveformPath = NULL;
    }
    _needsRedraw = YES;
}

- (void)setScrollOffsetX:(CGFloat)scrollOffsetX {
    if (fabs(scrollOffsetX - _scrollOffsetX) < 0.01) return;
    _scrollOffsetX = scrollOffsetX;
    // Invalidate cached path when scroll position changes
    if (_cachedWaveformPath) {
        CGPathRelease(_cachedWaveformPath);
        _cachedWaveformPath = NULL;
    }
    _needsRedraw = YES;
    // Trigger immediate redraw for smooth synchronized scrolling
    [self.layer setNeedsDisplay];
}

- (void)setPlaybackPositionMS:(CGFloat)playbackPositionMS {
    _playbackPositionMS = playbackPositionMS;
    _needsRedraw = YES;
    // Trigger immediate redraw for responsive playhead updates
    [self.layer setNeedsDisplay];
}

- (void)setSequenceLengthMS:(CGFloat)sequenceLengthMS {
    _sequenceLengthMS = sequenceLengthMS;
    _needsRedraw = YES;
}

- (void)setShowStereo:(BOOL)showStereo {
    _showStereo = showStereo;
    _needsRedraw = YES;
}

- (void)setCursorPositionMS:(CGFloat)cursorPositionMS {
    if (fabs(cursorPositionMS - _cursorPositionMS) < 0.01) return;
    _cursorPositionMS = cursorPositionMS;
    _needsRedraw = YES;
    [self.layer setNeedsDisplay];
}

- (void)setNeedsDisplay {
    _needsRedraw = YES;
    [self.layer setNeedsDisplay];
}

#pragma mark - Coordinate Conversion

- (CGFloat)timeMSForPointX:(CGFloat)x {
    return (x + _scrollOffsetX) / _zoomLevel;
}

- (CGFloat)pointXForTimeMS:(CGFloat)timeMS {
    return (timeMS * _zoomLevel) - _scrollOffsetX;
}

#pragma mark - CALayerDelegate

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
    _needsRedraw = NO;

    CGRect bounds = layer.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    // Background
    CGContextSetRGBFillColor(ctx, kBgR, kBgG, kBgB, 1.0);
    CGContextFillRect(ctx, bounds);

    // Top border
    CGContextSetGrayStrokeColor(ctx, 0.3, 1.0);
    CGContextSetLineWidth(ctx, 0.5);
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, 0, 0);
    CGContextAddLineToPoint(ctx, width, 0);
    CGContextStrokePath(ctx);

    // Center line
    CGFloat centerY = height / 2.0;
    CGContextSetGrayStrokeColor(ctx, kCenterLineGray, 1.0);
    CGContextSetLineWidth(ctx, 0.5);
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, 0, centerY);
    CGContextAddLineToPoint(ctx, width, centerY);
    CGContextStrokePath(ctx);

    // Draw waveform data if available
    if (_overviewBuckets.count > 0 && _sequenceLengthMS > 0) {
        [self drawWaveformInContext:ctx bounds:bounds];
    }

    // Draw playback position indicator
    if (_playbackPositionMS >= 0) {
        CGFloat playX = [self pointXForTimeMS:_playbackPositionMS];
        if (playX >= 0 && playX <= width) {
            CGContextSetRGBStrokeColor(ctx, kPlayheadR, kPlayheadG, kPlayheadB, 1.0);
            CGContextSetLineWidth(ctx, kPlayheadWidth);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, playX, 0);
            CGContextAddLineToPoint(ctx, playX, height);
            CGContextStrokePath(ctx);
        }
    }

    // Draw cursor position indicator (mouse tracking from effects grid)
    if (_cursorPositionMS >= 0 && _cursorPositionMS <= _sequenceLengthMS) {
        CGFloat cursorX = [self pointXForTimeMS:_cursorPositionMS];
        if (cursorX >= 0 && cursorX <= width) {
            CGContextSetRGBStrokeColor(ctx, kCursorR, kCursorG, kCursorB, kCursorAlpha);
            CGContextSetLineWidth(ctx, kPlayheadWidth);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, cursorX, 0);
            CGContextAddLineToPoint(ctx, cursorX, height);
            CGContextStrokePath(ctx);
        }
    }

    // Sequence end marker (dim area beyond sequence)
    if (_sequenceLengthMS > 0) {
        CGFloat seqEndX = [self pointXForTimeMS:_sequenceLengthMS];
        if (seqEndX >= 0 && seqEndX < width) {
            CGContextSetGrayFillColor(ctx, 0.05, 0.6);
            CGContextFillRect(ctx, CGRectMake(seqEndX, 0, width - seqEndX, height));
        }
    }
}

- (void)drawWaveformInContext:(CGContextRef)ctx bounds:(CGRect)bounds {
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    NSUInteger bucketCount = _overviewBuckets.count;

    // Determine waveform color
    CGFloat wR = kWaveR, wG = kWaveG, wB = kWaveB;
    if (_waveformColor) {
        CGFloat r, g, b, a;
        NSColor *calibrated = [_waveformColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        if (calibrated) {
            [calibrated getRed:&r green:&g blue:&b alpha:&a];
            wR = r; wG = g; wB = b;
        }
    }

    CGFloat usableHeight = height - kVerticalPadding * 2.0;

    if (_showStereo) {
        // Stereo: top half = left, bottom half = right
        CGFloat halfHeight = usableHeight / 2.0;
        CGFloat leftCenterY = kVerticalPadding + halfHeight / 2.0;
        CGFloat rightCenterY = kVerticalPadding + halfHeight + halfHeight / 2.0;

        // Draw separator line between channels
        CGFloat sepY = kVerticalPadding + halfHeight;
        CGContextSetGrayStrokeColor(ctx, kCenterLineGray, 0.6);
        CGContextSetLineWidth(ctx, 0.5);
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, 0, sepY);
        CGContextAddLineToPoint(ctx, width, sepY);
        CGContextStrokePath(ctx);

        // Left channel waveform
        CGContextSetRGBFillColor(ctx, wR, wG, wB, 0.7);
        [self drawChannelInContext:ctx
                             width:width
                          centerY:leftCenterY
                       halfHeight:halfHeight / 2.0
                       useLeftChannel:YES];

        // Right channel waveform
        CGContextSetRGBFillColor(ctx, wR, wG, wB, 0.7);
        [self drawChannelInContext:ctx
                             width:width
                          centerY:rightCenterY
                       halfHeight:halfHeight / 2.0
                       useLeftChannel:NO];
    } else {
        // Mono/combined: centered in full height
        CGFloat centerY = height / 2.0;
        CGFloat halfAmplitude = usableHeight / 2.0;

        CGContextSetRGBFillColor(ctx, wR, wG, wB, 0.7);
        [self drawChannelInContext:ctx
                             width:width
                          centerY:centerY
                       halfHeight:halfAmplitude
                       useLeftChannel:YES];

        // Outline in brighter white
        CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, 0.3);
        CGContextSetLineWidth(ctx, 0.5);
        [self strokeChannelInContext:ctx
                               width:width
                            centerY:centerY
                         halfHeight:halfAmplitude
                         useLeftChannel:YES];
    }
}

- (void)drawChannelInContext:(CGContextRef)ctx
                       width:(CGFloat)width
                    centerY:(CGFloat)centerY
                 halfHeight:(CGFloat)halfHeight
                 useLeftChannel:(BOOL)useLeft
{
    NSUInteger bucketCount = _overviewBuckets.count;
    if (bucketCount == 0 || _sequenceLengthMS <= 0) return;

    double msPerBucket = _sequenceLengthMS / (double)bucketCount;

    for (NSUInteger px = 0; px < (NSUInteger)width; px++) {
        CGFloat timeMS = [self timeMSForPointX:(CGFloat)px];
        if (timeMS < 0 || timeMS >= _sequenceLengthMS) continue;

        // Find the bucket index for this pixel
        NSUInteger bucketIndex = (NSUInteger)(timeMS / msPerBucket);
        if (bucketIndex >= bucketCount) bucketIndex = bucketCount - 1;

        // For wider zoom levels, aggregate multiple buckets per pixel
        CGFloat timeMS2 = [self timeMSForPointX:(CGFloat)(px + 1)];
        NSUInteger bucketIndex2 = (NSUInteger)(timeMS2 / msPerBucket);
        if (bucketIndex2 >= bucketCount) bucketIndex2 = bucketCount - 1;

        float minVal = 1.0f, maxVal = -1.0f;

        for (NSUInteger bi = bucketIndex; bi <= bucketIndex2; bi++) {
            XLWaveformBucket bucket;
            [_overviewBuckets[bi] getValue:&bucket];

            float bMin, bMax;
            if (useLeft) {
                bMin = bucket.minL;
                bMax = bucket.maxL;
            } else {
                bMin = bucket.minR;
                bMax = bucket.maxR;
            }

            if (bMin < minVal) minVal = bMin;
            if (bMax > maxVal) maxVal = bMax;
        }

        CGFloat y1 = centerY + minVal * halfHeight;
        CGFloat y2 = centerY + maxVal * halfHeight;

        // Ensure at least 1px visible
        if (fabs(y2 - y1) < 1.0) {
            y1 = centerY - 0.5;
            y2 = centerY + 0.5;
        }

        CGContextFillRect(ctx, CGRectMake((CGFloat)px, fmin(y1, y2), 1.0, fabs(y2 - y1)));
    }
}

- (void)strokeChannelInContext:(CGContextRef)ctx
                         width:(CGFloat)width
                      centerY:(CGFloat)centerY
                   halfHeight:(CGFloat)halfHeight
                   useLeftChannel:(BOOL)useLeft
{
    NSUInteger bucketCount = _overviewBuckets.count;
    if (bucketCount == 0 || _sequenceLengthMS <= 0) return;

    double msPerBucket = _sequenceLengthMS / (double)bucketCount;

    // Draw top outline
    CGContextBeginPath(ctx);
    BOOL firstPoint = YES;

    for (NSUInteger px = 0; px < (NSUInteger)width; px++) {
        CGFloat timeMS = [self timeMSForPointX:(CGFloat)px];
        if (timeMS < 0 || timeMS >= _sequenceLengthMS) continue;

        NSUInteger bucketIndex = (NSUInteger)(timeMS / msPerBucket);
        if (bucketIndex >= bucketCount) bucketIndex = bucketCount - 1;

        CGFloat timeMS2 = [self timeMSForPointX:(CGFloat)(px + 1)];
        NSUInteger bucketIndex2 = (NSUInteger)(timeMS2 / msPerBucket);
        if (bucketIndex2 >= bucketCount) bucketIndex2 = bucketCount - 1;

        float minVal = 1.0f;
        for (NSUInteger bi = bucketIndex; bi <= bucketIndex2; bi++) {
            XLWaveformBucket bucket;
            [_overviewBuckets[bi] getValue:&bucket];
            float bMin = useLeft ? bucket.minL : bucket.minR;
            if (bMin < minVal) minVal = bMin;
        }

        CGFloat y = centerY + minVal * halfHeight;
        if (firstPoint) {
            CGContextMoveToPoint(ctx, (CGFloat)px, y);
            firstPoint = NO;
        } else {
            CGContextAddLineToPoint(ctx, (CGFloat)px, y);
        }
    }
    CGContextStrokePath(ctx);

    // Draw bottom outline
    CGContextBeginPath(ctx);
    firstPoint = YES;

    for (NSUInteger px = 0; px < (NSUInteger)width; px++) {
        CGFloat timeMS = [self timeMSForPointX:(CGFloat)px];
        if (timeMS < 0 || timeMS >= _sequenceLengthMS) continue;

        NSUInteger bucketIndex = (NSUInteger)(timeMS / msPerBucket);
        if (bucketIndex >= bucketCount) bucketIndex = bucketCount - 1;

        CGFloat timeMS2 = [self timeMSForPointX:(CGFloat)(px + 1)];
        NSUInteger bucketIndex2 = (NSUInteger)(timeMS2 / msPerBucket);
        if (bucketIndex2 >= bucketCount) bucketIndex2 = bucketCount - 1;

        float maxVal = -1.0f;
        for (NSUInteger bi = bucketIndex; bi <= bucketIndex2; bi++) {
            XLWaveformBucket bucket;
            [_overviewBuckets[bi] getValue:&bucket];
            float bMax = useLeft ? bucket.maxL : bucket.maxR;
            if (bMax > maxVal) maxVal = bMax;
        }

        CGFloat y = centerY + maxVal * halfHeight;
        if (firstPoint) {
            CGContextMoveToPoint(ctx, (CGFloat)px, y);
            firstPoint = NO;
        } else {
            CGContextAddLineToPoint(ctx, (CGFloat)px, y);
        }
    }
    CGContextStrokePath(ctx);
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat timeMS = [self timeMSForPointX:loc.x];
    timeMS = fmax(0, fmin(timeMS, _sequenceLengthMS));

    _dragging = YES;
    _playbackPositionMS = timeMS;
    _needsRedraw = YES;
    // Force immediate synchronous redraw before delegate call (which may block)
    [self.layer setNeedsDisplay];
    [self.layer displayIfNeeded];

    if ([_delegate respondsToSelector:@selector(waveformView:didSeekToTimeMS:)]) {
        [_delegate waveformView:self didSeekToTimeMS:timeMS];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_dragging) return;

    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat timeMS = [self timeMSForPointX:loc.x];
    timeMS = fmax(0, fmin(timeMS, _sequenceLengthMS));

    _playbackPositionMS = timeMS;
    _needsRedraw = YES;
    // Force immediate synchronous redraw before delegate call (which may block)
    [self.layer setNeedsDisplay];
    [self.layer displayIfNeeded];

    if ([_delegate respondsToSelector:@selector(waveformView:didSeekToTimeMS:)]) {
        [_delegate waveformView:self didSeekToTimeMS:timeMS];
    }
}

- (void)mouseUp:(NSEvent *)event {
    _dragging = NO;
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat timeMS = [self timeMSForPointX:loc.x];

    // Update cursor position (will trigger redraw via setter)
    self.cursorPositionMS = timeMS;
}

- (void)mouseExited:(NSEvent *)event {
    // Clear cursor position when mouse leaves
    self.cursorPositionMS = -1;
}

- (void)scrollWheel:(NSEvent *)event {
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        // Cmd+Scroll = Zoom
        NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
        CGFloat timeAtCursor = [self timeMSForPointX:loc.x];

        CGFloat factor = 1.0 + event.scrollingDeltaY * 0.05;
        factor = fmax(0.5, fmin(factor, 2.0));

        CGFloat newZoom = _zoomLevel * factor;
        newZoom = fmax(0.001, fmin(newZoom, 10.0));
        _zoomLevel = newZoom;

        // Adjust scroll to keep time under cursor stable
        CGFloat newX = timeAtCursor * _zoomLevel - loc.x;
        _scrollOffsetX = fmax(0, newX);
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(waveformView:didChangeZoomLevel:centeredOnPointX:)]) {
            [_delegate waveformView:self didChangeZoomLevel:_zoomLevel centeredOnPointX:loc.x];
        }

        if ([_delegate respondsToSelector:@selector(waveformView:didChangeScrollOffset:)]) {
            [_delegate waveformView:self didChangeScrollOffset:_scrollOffsetX];
        }
        return;
    }

    if (event.modifierFlags & NSEventModifierFlagShift) {
        // Shift+Scroll = horizontal scroll
        CGFloat dx = event.scrollingDeltaY;
        _scrollOffsetX = fmax(0, _scrollOffsetX - dx);
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(waveformView:didChangeScrollOffset:)]) {
            [_delegate waveformView:self didChangeScrollOffset:_scrollOffsetX];
        }
    } else {
        // Normal horizontal scroll
        CGFloat dx = event.scrollingDeltaX;
        if (fabs(dx) > 0.01) {
            _scrollOffsetX = fmax(0, _scrollOffsetX - dx);
            _needsRedraw = YES;

            if ([_delegate respondsToSelector:@selector(waveformView:didChangeScrollOffset:)]) {
                [_delegate waveformView:self didChangeScrollOffset:_scrollOffsetX];
            }
        } else {
            [super scrollWheel:event];
        }
    }
}

- (void)magnifyWithEvent:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat timeAtCursor = [self timeMSForPointX:loc.x];

    CGFloat factor = 1.0 + event.magnification;
    CGFloat newZoom = _zoomLevel * factor;
    newZoom = fmax(0.001, fmin(newZoom, 10.0));
    _zoomLevel = newZoom;

    // Adjust scroll to keep time under cursor stable
    CGFloat newX = timeAtCursor * _zoomLevel - loc.x;
    _scrollOffsetX = fmax(0, newX);
    _needsRedraw = YES;

    if ([_delegate respondsToSelector:@selector(waveformView:didChangeZoomLevel:centeredOnPointX:)]) {
        [_delegate waveformView:self didChangeZoomLevel:_zoomLevel centeredOnPointX:loc.x];
    }

    if ([_delegate respondsToSelector:@selector(waveformView:didChangeScrollOffset:)]) {
        [_delegate waveformView:self didChangeScrollOffset:_scrollOffsetX];
    }
}

#pragma mark - Intrinsic Content Size

- (NSSize)intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric, 60.0);
}

@end
