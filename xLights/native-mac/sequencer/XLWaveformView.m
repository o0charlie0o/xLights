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

// Loop region selection overlay colors
static const CGFloat kLoopR = 0.2, kLoopG = 0.5, kLoopB = 1.0, kLoopAlpha = 0.2;
static const CGFloat kLoopEdgeR = 0.3, kLoopEdgeG = 0.6, kLoopEdgeB = 1.0, kLoopEdgeAlpha = 0.8;

// Drag detection threshold in points
static const CGFloat kDragThreshold = 3.0;
// Minimum region size in milliseconds to count as a selection
static const CGFloat kMinRegionMS = 50.0;

// Maximum number of waveform overview buckets to pre-compute.
// This provides sub-pixel resolution at reasonable zoom levels.
static const NSUInteger kMaxOverviewBuckets = 65536;

@interface XLWaveformView () {
    CVDisplayLinkRef _displayLink;

    // Visible-region waveform cache: covers viewport + padding.
    // Rebuilt when scrolling outside cached region, or on zoom/height/data change.
    // Rendered at contentsScale resolution for crisp Retina display.
    CGImageRef _cachedWaveformImage;
    CGFloat _cacheZoomLevel;
    CGFloat _cacheScrollX;     // left edge of cached region in zoomed-pixel coordinates
    CGFloat _cacheWidthPts;    // width of cached region in points
    CGFloat _cacheHeightPts;   // height in points when cached
    CGFloat _cacheScale;       // backing scale factor when cached
    BOOL _cacheStereo;         // stereo mode when cached
}

@property (nonatomic, strong) XLAudioSampleData *audioData;
@property (nonatomic, strong) NSArray<NSValue *> *overviewBuckets;
@property (nonatomic, assign) BOOL needsRedraw;
@property (nonatomic, assign) BOOL dragging;

// Drag-to-select state
@property (nonatomic, assign) NSPoint mouseDownPoint;
@property (nonatomic, assign) CGFloat dragStartMS;
@property (nonatomic, assign) BOOL isDragSelecting;

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
    _waveformType = XLWaveformTypeRaw;
    _doubleHeight = NO;
    _customLowNote = -1;
    _customHighNote = -1;
    _waveformColor = nil;
    _needsRedraw = YES;
    _dragging = NO;
    _isDragSelecting = NO;
    _dragStartMS = -1;
    _loopRegionStartMS = -1;
    _loopRegionEndMS = -1;

    _cachedWaveformImage = NULL;

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
    CGImageRelease(_cachedWaveformImage);
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
    [self invalidateWaveformCache];
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
        [self invalidateWaveformCache];
        _needsRedraw = YES;
    }
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self invalidateWaveformCache];
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
    [self invalidateWaveformCache];

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
    [self invalidateWaveformCache];
    _needsRedraw = YES;
}

#pragma mark - Property Setters

- (void)setZoomLevel:(CGFloat)zoomLevel {
    if (fabs(zoomLevel - _zoomLevel) < 0.00001) return;
    _zoomLevel = zoomLevel;
    [self invalidateWaveformCache];
    _needsRedraw = YES;
}

- (void)setScrollOffsetX:(CGFloat)scrollOffsetX {
    scrollOffsetX = [self clampScrollOffset:scrollOffsetX];
    if (fabs(scrollOffsetX - _scrollOffsetX) < 0.01) return;
    _scrollOffsetX = scrollOffsetX;
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
    [self invalidateWaveformCache];
    _needsRedraw = YES;
}

- (void)setShowStereo:(BOOL)showStereo {
    _showStereo = showStereo;
    [self invalidateWaveformCache];
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

- (BOOL)hasLoopRegion {
    return _loopRegionStartMS >= 0 && _loopRegionEndMS >= 0 && _loopRegionEndMS > _loopRegionStartMS;
}

- (void)clearLoopRegion {
    if (!self.hasLoopRegion) return;
    _loopRegionStartMS = -1;
    _loopRegionEndMS = -1;
    _needsRedraw = YES;
    [self.layer setNeedsDisplay];

    if ([_delegate respondsToSelector:@selector(waveformViewDidClearLoopRegion:)]) {
        [_delegate waveformViewDidClearLoopRegion:self];
    }
}

#pragma mark - Scroll Clamping

- (CGFloat)clampScrollOffset:(CGFloat)offset {
    CGFloat maxScroll = _sequenceLengthMS * _zoomLevel - NSWidth(self.bounds);
    if (maxScroll < 0) maxScroll = 0;
    return fmax(0, fmin(offset, maxScroll));
}

#pragma mark - Coordinate Conversion

- (CGFloat)timeMSForPointX:(CGFloat)x {
    return (x + _scrollOffsetX) / _zoomLevel;
}

- (CGFloat)pointXForTimeMS:(CGFloat)timeMS {
    return (timeMS * _zoomLevel) - _scrollOffsetX;
}

#pragma mark - Waveform Cache

- (void)invalidateWaveformCache {
    CGImageRelease(_cachedWaveformImage);
    _cachedWaveformImage = NULL;
}

- (void)rebuildWaveformCacheIfNeeded {
    NSUInteger bucketCount = _overviewBuckets.count;
    if (bucketCount == 0 || _sequenceLengthMS <= 0) return;

    CGFloat height = CGRectGetHeight(self.layer.bounds);
    CGFloat viewWidth = CGRectGetWidth(self.layer.bounds);
    if (height < 1 || viewWidth < 1) return;

    CGFloat scale = self.layer.contentsScale ?: 2.0;

    // Check if existing cache covers the visible region
    if (_cachedWaveformImage &&
        fabs(_cacheZoomLevel - _zoomLevel) < 0.00001 &&
        fabs(_cacheHeightPts - height) < 0.5 &&
        fabs(_cacheScale - scale) < 0.01 &&
        _cacheStereo == _showStereo &&
        _scrollOffsetX >= _cacheScrollX &&
        (_scrollOffsetX + viewWidth) <= (_cacheScrollX + _cacheWidthPts + 0.5)) {
        return;
    }

    // Cache viewport + 1x padding on each side (3x total)
    CGFloat padding = viewWidth;
    CGFloat cacheStartX = fmax(0, _scrollOffsetX - padding);
    CGFloat fullZoomedWidth = _sequenceLengthMS * _zoomLevel;
    CGFloat cacheWidthPts = viewWidth + 2 * padding;
    if (cacheStartX + cacheWidthPts > fullZoomedWidth) {
        cacheWidthPts = fullZoomedWidth - cacheStartX;
    }
    if (cacheWidthPts < 1) return;

    // Create bitmap at Retina resolution
    NSUInteger pixelWidth = (NSUInteger)(cacheWidthPts * scale);
    NSUInteger pixelHeight = (NSUInteger)(height * scale);
    if (pixelWidth == 0 || pixelHeight == 0) return;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef bctx = CGBitmapContextCreate(NULL, pixelWidth, pixelHeight, 8,
                                               pixelWidth * 4, cs,
                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(cs);
    if (!bctx) return;

    CGContextClearRect(bctx, CGRectMake(0, 0, pixelWidth, pixelHeight));

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

    double msPerBucket = _sequenceLengthMS / (double)bucketCount;

    // Determine rendering mode: raw samples at high zoom, buckets at low zoom
    CGFloat msPerPixel = 1.0 / (_zoomLevel * scale);
    BOOL useSamples = NO;
    float *samples = NULL;
    NSUInteger sampleCount = 0;
    NSUInteger channelCount = 0;
    double sampleRate = 0;

    if (_audioData && msPerPixel < msPerBucket * 2.0) {
        useSamples = YES;
        samples = _audioData.samples;
        sampleCount = _audioData.sampleCount;
        channelCount = _audioData.channelCount;
        sampleRate = _audioData.sampleRate;
    }

    // Pre-extract bucket data to C array for fast access
    XLWaveformBucket *bucketData = NULL;
    if (!useSamples) {
        bucketData = (XLWaveformBucket *)malloc(bucketCount * sizeof(XLWaveformBucket));
        for (NSUInteger i = 0; i < bucketCount; i++) {
            [_overviewBuckets[i] getValue:&bucketData[i]];
        }
    }

    CGFloat usableHeightPx = pixelHeight - kVerticalPadding * 2.0 * scale;

    if (_showStereo) {
        // Stereo: top half = left channel, bottom half = right channel
        CGFloat halfChannelHeightPx = usableHeightPx / 4.0;  // each channel gets half of usable
        CGFloat leftCenterPx = kVerticalPadding * scale + usableHeightPx / 4.0;
        CGFloat rightCenterPx = kVerticalPadding * scale + usableHeightPx * 3.0 / 4.0;

        // Separator line between channels
        CGFloat sepYPx = kVerticalPadding * scale + usableHeightPx / 2.0;
        CGContextSetGrayStrokeColor(bctx, kCenterLineGray, 0.6);
        CGContextSetLineWidth(bctx, 0.5 * scale);
        CGContextBeginPath(bctx);
        CGContextMoveToPoint(bctx, 0, sepYPx);
        CGContextAddLineToPoint(bctx, pixelWidth, sepYPx);
        CGContextStrokePath(bctx);

        // Left channel
        CGContextSetRGBFillColor(bctx, wR, wG, wB, 0.7);
        [self renderChannelToBitmap:bctx pixelWidth:pixelWidth scale:scale
                        cacheStartX:cacheStartX centerYPx:leftCenterPx halfHeightPx:halfChannelHeightPx
                         useLeft:YES useSamples:useSamples samples:samples
                        sampleCount:sampleCount channelCount:channelCount sampleRate:sampleRate
                         bucketData:bucketData bucketCount:bucketCount msPerBucket:msPerBucket];

        // Right channel
        CGContextSetRGBFillColor(bctx, wR, wG, wB, 0.7);
        [self renderChannelToBitmap:bctx pixelWidth:pixelWidth scale:scale
                        cacheStartX:cacheStartX centerYPx:rightCenterPx halfHeightPx:halfChannelHeightPx
                         useLeft:NO useSamples:useSamples samples:samples
                        sampleCount:sampleCount channelCount:channelCount sampleRate:sampleRate
                         bucketData:bucketData bucketCount:bucketCount msPerBucket:msPerBucket];
    } else {
        // Mono/combined: full height
        CGFloat centerPx = pixelHeight / 2.0;
        CGFloat halfHeightPx = usableHeightPx / 2.0;

        // Fill
        CGContextSetRGBFillColor(bctx, wR, wG, wB, 0.7);
        [self renderChannelToBitmap:bctx pixelWidth:pixelWidth scale:scale
                        cacheStartX:cacheStartX centerYPx:centerPx halfHeightPx:halfHeightPx
                         useLeft:YES useSamples:useSamples samples:samples
                        sampleCount:sampleCount channelCount:channelCount sampleRate:sampleRate
                         bucketData:bucketData bucketCount:bucketCount msPerBucket:msPerBucket];

        // Stroke outline in brighter white
        CGContextSetRGBStrokeColor(bctx, 1.0, 1.0, 1.0, 0.3);
        CGContextSetLineWidth(bctx, 0.5 * scale);
        [self strokeChannelToBitmap:bctx pixelWidth:pixelWidth scale:scale
                        cacheStartX:cacheStartX centerYPx:centerPx halfHeightPx:halfHeightPx
                         useLeft:YES useSamples:useSamples samples:samples
                        sampleCount:sampleCount channelCount:channelCount sampleRate:sampleRate
                         bucketData:bucketData bucketCount:bucketCount msPerBucket:msPerBucket];
    }

    free(bucketData);

    CGImageRelease(_cachedWaveformImage);
    _cachedWaveformImage = CGBitmapContextCreateImage(bctx);
    CGContextRelease(bctx);

    _cacheZoomLevel = _zoomLevel;
    _cacheScrollX = cacheStartX;
    _cacheWidthPts = cacheWidthPts;
    _cacheHeightPts = height;
    _cacheScale = scale;
    _cacheStereo = _showStereo;
}

- (void)renderChannelToBitmap:(CGContextRef)bctx
                   pixelWidth:(NSUInteger)pixelWidth
                        scale:(CGFloat)scale
                  cacheStartX:(CGFloat)cacheStartX
                    centerYPx:(CGFloat)centerYPx
                  halfHeightPx:(CGFloat)halfHeightPx
                      useLeft:(BOOL)useLeft
                   useSamples:(BOOL)useSamples
                      samples:(float *)samples
                  sampleCount:(NSUInteger)sampleCount
                 channelCount:(NSUInteger)channelCount
                   sampleRate:(double)sampleRate
                   bucketData:(XLWaveformBucket *)bucketData
                  bucketCount:(NSUInteger)bucketCount
                  msPerBucket:(double)msPerBucket
{
    CGFloat durationMS = _sequenceLengthMS;

    for (NSUInteger px = 0; px < pixelWidth; px++) {
        CGFloat zoomedPt = cacheStartX + (CGFloat)px / scale;
        CGFloat timeMS1 = zoomedPt / _zoomLevel;
        CGFloat timeMS2 = (zoomedPt + 1.0 / scale) / _zoomLevel;
        if (timeMS1 < 0) continue;
        if (timeMS1 >= durationMS) break;
        if (timeMS2 > durationMS) timeMS2 = durationMS;

        float minVal = 1.0f, maxVal = -1.0f;

        if (useSamples) {
            NSUInteger startFrame = (NSUInteger)(timeMS1 / 1000.0 * sampleRate);
            NSUInteger endFrame = (NSUInteger)(timeMS2 / 1000.0 * sampleRate);
            if (startFrame >= sampleCount) startFrame = sampleCount - 1;
            if (endFrame >= sampleCount) endFrame = sampleCount - 1;

            for (NSUInteger f = startFrame; f <= endFrame; f++) {
                float val;
                if (useLeft) {
                    val = samples[f * channelCount];
                } else {
                    val = (channelCount > 1) ? samples[f * channelCount + 1] : samples[f * channelCount];
                }
                if (val < minVal) minVal = val;
                if (val > maxVal) maxVal = val;
            }
        } else {
            NSUInteger bi1 = (NSUInteger)(timeMS1 / msPerBucket);
            if (bi1 >= bucketCount) bi1 = bucketCount - 1;
            NSUInteger bi2 = (NSUInteger)(timeMS2 / msPerBucket);
            if (bi2 >= bucketCount) bi2 = bucketCount - 1;

            for (NSUInteger bi = bi1; bi <= bi2; bi++) {
                float bMin, bMax;
                if (useLeft) {
                    bMin = bucketData[bi].minL;
                    bMax = bucketData[bi].maxL;
                } else {
                    bMin = bucketData[bi].minR;
                    bMax = bucketData[bi].maxR;
                }
                if (bMin < minVal) minVal = bMin;
                if (bMax > maxVal) maxVal = bMax;
            }
        }

        // Non-flipped bitmap (y=0 is bottom): positive values go up from center
        CGFloat y1 = centerYPx + minVal * halfHeightPx;
        CGFloat y2 = centerYPx + maxVal * halfHeightPx;
        if (fabs(y2 - y1) < 1.0) {
            y1 = centerYPx - 0.5;
            y2 = centerYPx + 0.5;
        }

        CGContextFillRect(bctx, CGRectMake(px, fmin(y1, y2), 1.0, fabs(y2 - y1)));
    }
}

- (void)strokeChannelToBitmap:(CGContextRef)bctx
                   pixelWidth:(NSUInteger)pixelWidth
                        scale:(CGFloat)scale
                  cacheStartX:(CGFloat)cacheStartX
                    centerYPx:(CGFloat)centerYPx
                  halfHeightPx:(CGFloat)halfHeightPx
                      useLeft:(BOOL)useLeft
                   useSamples:(BOOL)useSamples
                      samples:(float *)samples
                  sampleCount:(NSUInteger)sampleCount
                 channelCount:(NSUInteger)channelCount
                   sampleRate:(double)sampleRate
                   bucketData:(XLWaveformBucket *)bucketData
                  bucketCount:(NSUInteger)bucketCount
                  msPerBucket:(double)msPerBucket
{
    CGFloat durationMS = _sequenceLengthMS;

    // Top outline (min values)
    CGContextBeginPath(bctx);
    BOOL firstPoint = YES;

    for (NSUInteger px = 0; px < pixelWidth; px++) {
        CGFloat zoomedPt = cacheStartX + (CGFloat)px / scale;
        CGFloat timeMS1 = zoomedPt / _zoomLevel;
        CGFloat timeMS2 = (zoomedPt + 1.0 / scale) / _zoomLevel;
        if (timeMS1 < 0) continue;
        if (timeMS1 >= durationMS) break;
        if (timeMS2 > durationMS) timeMS2 = durationMS;

        float minVal = 1.0f;

        if (useSamples) {
            NSUInteger startFrame = (NSUInteger)(timeMS1 / 1000.0 * sampleRate);
            NSUInteger endFrame = (NSUInteger)(timeMS2 / 1000.0 * sampleRate);
            if (startFrame >= sampleCount) startFrame = sampleCount - 1;
            if (endFrame >= sampleCount) endFrame = sampleCount - 1;
            for (NSUInteger f = startFrame; f <= endFrame; f++) {
                float val = useLeft ? samples[f * channelCount]
                    : ((channelCount > 1) ? samples[f * channelCount + 1] : samples[f * channelCount]);
                if (val < minVal) minVal = val;
            }
        } else {
            NSUInteger bi1 = (NSUInteger)(timeMS1 / msPerBucket);
            if (bi1 >= bucketCount) bi1 = bucketCount - 1;
            NSUInteger bi2 = (NSUInteger)(timeMS2 / msPerBucket);
            if (bi2 >= bucketCount) bi2 = bucketCount - 1;
            for (NSUInteger bi = bi1; bi <= bi2; bi++) {
                float bMin = useLeft ? bucketData[bi].minL : bucketData[bi].minR;
                if (bMin < minVal) minVal = bMin;
            }
        }

        CGFloat y = centerYPx + minVal * halfHeightPx;
        if (firstPoint) {
            CGContextMoveToPoint(bctx, px, y);
            firstPoint = NO;
        } else {
            CGContextAddLineToPoint(bctx, px, y);
        }
    }
    CGContextStrokePath(bctx);

    // Bottom outline (max values)
    CGContextBeginPath(bctx);
    firstPoint = YES;

    for (NSUInteger px = 0; px < pixelWidth; px++) {
        CGFloat zoomedPt = cacheStartX + (CGFloat)px / scale;
        CGFloat timeMS1 = zoomedPt / _zoomLevel;
        CGFloat timeMS2 = (zoomedPt + 1.0 / scale) / _zoomLevel;
        if (timeMS1 < 0) continue;
        if (timeMS1 >= durationMS) break;
        if (timeMS2 > durationMS) timeMS2 = durationMS;

        float maxVal = -1.0f;

        if (useSamples) {
            NSUInteger startFrame = (NSUInteger)(timeMS1 / 1000.0 * sampleRate);
            NSUInteger endFrame = (NSUInteger)(timeMS2 / 1000.0 * sampleRate);
            if (startFrame >= sampleCount) startFrame = sampleCount - 1;
            if (endFrame >= sampleCount) endFrame = sampleCount - 1;
            for (NSUInteger f = startFrame; f <= endFrame; f++) {
                float val = useLeft ? samples[f * channelCount]
                    : ((channelCount > 1) ? samples[f * channelCount + 1] : samples[f * channelCount]);
                if (val > maxVal) maxVal = val;
            }
        } else {
            NSUInteger bi1 = (NSUInteger)(timeMS1 / msPerBucket);
            if (bi1 >= bucketCount) bi1 = bucketCount - 1;
            NSUInteger bi2 = (NSUInteger)(timeMS2 / msPerBucket);
            if (bi2 >= bucketCount) bi2 = bucketCount - 1;
            for (NSUInteger bi = bi1; bi <= bi2; bi++) {
                float bMax = useLeft ? bucketData[bi].maxL : bucketData[bi].maxR;
                if (bMax > maxVal) maxVal = bMax;
            }
        }

        CGFloat y = centerYPx + maxVal * halfHeightPx;
        if (firstPoint) {
            CGContextMoveToPoint(bctx, px, y);
            firstPoint = NO;
        } else {
            CGContextAddLineToPoint(bctx, px, y);
        }
    }
    CGContextStrokePath(bctx);
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

    // Draw cached waveform if available
    if (_overviewBuckets.count > 0 && _sequenceLengthMS > 0) {
        [self rebuildWaveformCacheIfNeeded];

        if (_cachedWaveformImage) {
            CGFloat offsetInCache = _scrollOffsetX - _cacheScrollX;
            CGFloat availableWidth = _cacheWidthPts - offsetInCache;
            CGFloat blitWidth = fmin(width, availableWidth);

            if (blitWidth > 0) {
                CGFloat srcPixelX = offsetInCache * _cacheScale;
                CGFloat srcPixelW = blitWidth * _cacheScale;
                CGFloat srcPixelH = (CGFloat)CGImageGetHeight(_cachedWaveformImage);

                CGRect srcRect = CGRectMake(srcPixelX, 0, srcPixelW, srcPixelH);
                CGRect dstRect = CGRectMake(0, 0, blitWidth, height);

                // Flip for CGImage drawing (CGImage is non-flipped, context is flipped)
                CGContextSaveGState(ctx);
                CGContextTranslateCTM(ctx, 0, height);
                CGContextScaleCTM(ctx, 1.0, -1.0);
                CGImageRef subImage = CGImageCreateWithImageInRect(_cachedWaveformImage, srcRect);
                CGContextDrawImage(ctx, dstRect, subImage);
                CGImageRelease(subImage);
                CGContextRestoreGState(ctx);
            }
        }
    }

    // Draw loop region selection overlay
    if (self.hasLoopRegion) {
        CGFloat regionStartX = [self pointXForTimeMS:_loopRegionStartMS];
        CGFloat regionEndX = [self pointXForTimeMS:_loopRegionEndMS];

        // Clamp to visible area
        CGFloat visStartX = fmax(0, regionStartX);
        CGFloat visEndX = fmin(width, regionEndX);

        if (visEndX > visStartX) {
            // Semi-transparent fill
            CGContextSetRGBFillColor(ctx, kLoopR, kLoopG, kLoopB, kLoopAlpha);
            CGContextFillRect(ctx, CGRectMake(visStartX, 0, visEndX - visStartX, height));

            // Edge lines
            CGContextSetRGBStrokeColor(ctx, kLoopEdgeR, kLoopEdgeG, kLoopEdgeB, kLoopEdgeAlpha);
            CGContextSetLineWidth(ctx, 1.0);
            if (regionStartX >= 0 && regionStartX <= width) {
                CGContextBeginPath(ctx);
                CGContextMoveToPoint(ctx, regionStartX, 0);
                CGContextAddLineToPoint(ctx, regionStartX, height);
                CGContextStrokePath(ctx);
            }
            if (regionEndX >= 0 && regionEndX <= width) {
                CGContextBeginPath(ctx);
                CGContextMoveToPoint(ctx, regionEndX, 0);
                CGContextAddLineToPoint(ctx, regionEndX, height);
                CGContextStrokePath(ctx);
            }
        }
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

#pragma mark - Keyboard Events

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    if ([_delegate respondsToSelector:@selector(waveformView:shouldHandleKeyEvent:)]) {
        if ([_delegate waveformView:self shouldHandleKeyEvent:event]) {
            return;
        }
    }
    [super keyDown:event];
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat timeMS = [self timeMSForPointX:loc.x];
    timeMS = fmax(0, fmin(timeMS, _sequenceLengthMS));

    _dragging = YES;
    _isDragSelecting = NO;
    _mouseDownPoint = loc;
    _dragStartMS = timeMS;

    // Clear any existing loop region on click
    if (self.hasLoopRegion) {
        _loopRegionStartMS = -1;
        _loopRegionEndMS = -1;
        _needsRedraw = YES;
        [self.layer setNeedsDisplay];

        if ([_delegate respondsToSelector:@selector(waveformViewDidClearLoopRegion:)]) {
            [_delegate waveformViewDidClearLoopRegion:self];
        }
    }

    // Immediate seek
    _playbackPositionMS = timeMS;
    _needsRedraw = YES;
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

    // Check if we've exceeded the drag threshold to start selecting
    if (!_isDragSelecting) {
        CGFloat dx = loc.x - _mouseDownPoint.x;
        CGFloat dy = loc.y - _mouseDownPoint.y;
        if (sqrt(dx * dx + dy * dy) >= kDragThreshold) {
            _isDragSelecting = YES;
        }
    }

    if (_isDragSelecting) {
        // Update loop region (always keep start < end)
        _loopRegionStartMS = fmin(_dragStartMS, timeMS);
        _loopRegionEndMS = fmax(_dragStartMS, timeMS);
        _needsRedraw = YES;
        [self.layer setNeedsDisplay];
    } else {
        // Still under threshold — continue seeking
        _playbackPositionMS = timeMS;
        _needsRedraw = YES;
        [self.layer setNeedsDisplay];
        [self.layer displayIfNeeded];

        if ([_delegate respondsToSelector:@selector(waveformView:didSeekToTimeMS:)]) {
            [_delegate waveformView:self didSeekToTimeMS:timeMS];
        }
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (_isDragSelecting && self.hasLoopRegion) {
        // If region is too small, treat as a click
        if ((_loopRegionEndMS - _loopRegionStartMS) < kMinRegionMS) {
            _loopRegionStartMS = -1;
            _loopRegionEndMS = -1;
            _needsRedraw = YES;
            [self.layer setNeedsDisplay];
        } else {
            // Notify delegate of the completed selection
            if ([_delegate respondsToSelector:@selector(waveformView:didSelectLoopRegionFromTimeMS:toTimeMS:)]) {
                [_delegate waveformView:self didSelectLoopRegionFromTimeMS:_loopRegionStartMS toTimeMS:_loopRegionEndMS];
            }
        }
    }

    _dragging = NO;
    _isDragSelecting = NO;
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat timeMS = [self timeMSForPointX:loc.x];

    // Update cursor position (will trigger redraw via setter)
    self.cursorPositionMS = timeMS;

    if ([_delegate respondsToSelector:@selector(waveformView:didMoveCursorToTimeMS:)]) {
        [_delegate waveformView:self didMoveCursorToTimeMS:timeMS];
    }
}

- (void)mouseExited:(NSEvent *)event {
    // Clear cursor position when mouse leaves
    self.cursorPositionMS = -1;

    if ([_delegate respondsToSelector:@selector(waveformView:didMoveCursorToTimeMS:)]) {
        [_delegate waveformView:self didMoveCursorToTimeMS:-1];
    }
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
        [self invalidateWaveformCache];

        // Adjust scroll to keep time under cursor stable
        CGFloat newX = timeAtCursor * _zoomLevel - loc.x;
        _scrollOffsetX = [self clampScrollOffset:newX];
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
        _scrollOffsetX = [self clampScrollOffset:_scrollOffsetX - dx];
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(waveformView:didChangeScrollOffset:)]) {
            [_delegate waveformView:self didChangeScrollOffset:_scrollOffsetX];
        }
    } else {
        // Normal horizontal scroll
        CGFloat dx = event.scrollingDeltaX;
        if (fabs(dx) > 0.01) {
            _scrollOffsetX = [self clampScrollOffset:_scrollOffsetX - dx];
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
    [self invalidateWaveformCache];

    // Adjust scroll to keep time under cursor stable
    CGFloat newX = timeAtCursor * _zoomLevel - loc.x;
    _scrollOffsetX = [self clampScrollOffset:newX];
    _needsRedraw = YES;

    if ([_delegate respondsToSelector:@selector(waveformView:didChangeZoomLevel:centeredOnPointX:)]) {
        [_delegate waveformView:self didChangeZoomLevel:_zoomLevel centeredOnPointX:loc.x];
    }

    if ([_delegate respondsToSelector:@selector(waveformView:didChangeScrollOffset:)]) {
        [_delegate waveformView:self didChangeScrollOffset:_scrollOffsetX];
    }
}

#pragma mark - Context Menu

static const NSInteger kMenuTagRenderSelected = 100;
static const NSInteger kMenuTagWaveformRaw = 200;
static const NSInteger kMenuTagWaveformBass = 201;
static const NSInteger kMenuTagWaveformTreble = 202;
static const NSInteger kMenuTagWaveformAlto = 203;
static const NSInteger kMenuTagWaveformCustom = 204;
static const NSInteger kMenuTagWaveformNonVocals = 205;
static const NSInteger kMenuTagDoubleHeight = 300;

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Waveform"];

    // "Render Selected Region" — only if a loop region is selected
    if (self.hasLoopRegion) {
        NSMenuItem *renderItem = [[NSMenuItem alloc] initWithTitle:@"Render Selected Region"
                                                            action:@selector(contextMenuRenderSelected:)
                                                     keyEquivalent:@""];
        renderItem.target = self;
        renderItem.tag = kMenuTagRenderSelected;
        [menu addItem:renderItem];
    }

    // Only show waveform type options when audio data is loaded
    if (_audioData) {
        if (menu.numberOfItems > 0) {
            [menu addItem:[NSMenuItem separatorItem]];
        }

        // Waveform type radio group
        struct {
            NSString *title;
            NSInteger tag;
            XLWaveformType type;
        } waveformTypes[] = {
            { @"Raw waveform",              kMenuTagWaveformRaw,      XLWaveformTypeRaw },
            { @"Bass waveform",             kMenuTagWaveformBass,     XLWaveformTypeBass },
            { @"Treble waveform",           kMenuTagWaveformTreble,   XLWaveformTypeTreble },
            { @"Alto waveform",             kMenuTagWaveformAlto,     XLWaveformTypeAlto },
            { @"Custom filtered waveform",  kMenuTagWaveformCustom,   XLWaveformTypeCustom },
            { @"Non Vocals waveform",       kMenuTagWaveformNonVocals, XLWaveformTypeNonVocals },
        };

        for (int i = 0; i < 6; i++) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:waveformTypes[i].title
                                                          action:@selector(contextMenuWaveformType:)
                                                   keyEquivalent:@""];
            item.target = self;
            item.tag = waveformTypes[i].tag;
            item.state = (_waveformType == waveformTypes[i].type)
                         ? NSControlStateValueOn : NSControlStateValueOff;
            [menu addItem:item];
        }

        [menu addItem:[NSMenuItem separatorItem]];

        // Double height toggle
        NSMenuItem *doubleItem = [[NSMenuItem alloc] initWithTitle:@"Double height waveform"
                                                            action:@selector(contextMenuDoubleHeight:)
                                                     keyEquivalent:@""];
        doubleItem.target = self;
        doubleItem.tag = kMenuTagDoubleHeight;
        doubleItem.state = _doubleHeight ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:doubleItem];
    }

    if (menu.numberOfItems == 0) {
        return nil;
    }

    return menu;
}

- (void)contextMenuRenderSelected:(NSMenuItem *)sender {
    if ([_delegate respondsToSelector:@selector(waveformViewDidRequestRenderSelectedRegion:)]) {
        [_delegate waveformViewDidRequestRenderSelectedRegion:self];
    }
}

- (void)contextMenuWaveformType:(NSMenuItem *)sender {
    XLWaveformType newType;
    switch (sender.tag) {
        case kMenuTagWaveformRaw:      newType = XLWaveformTypeRaw; break;
        case kMenuTagWaveformBass:     newType = XLWaveformTypeBass; break;
        case kMenuTagWaveformTreble:   newType = XLWaveformTypeTreble; break;
        case kMenuTagWaveformAlto:     newType = XLWaveformTypeAlto; break;
        case kMenuTagWaveformNonVocals: newType = XLWaveformTypeNonVocals; break;
        case kMenuTagWaveformCustom: {
            [self showCustomFilterDialog];
            return;
        }
        default: return;
    }

    _waveformType = newType;
    [self invalidateWaveformCache];
    _needsRedraw = YES;
    [self.layer setNeedsDisplay];

    if ([_delegate respondsToSelector:@selector(waveformView:didChangeWaveformType:lowNote:highNote:)]) {
        [_delegate waveformView:self didChangeWaveformType:_waveformType lowNote:_customLowNote highNote:_customHighNote];
    }
}

- (void)showCustomFilterDialog {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Custom Filtered Waveform";
    alert.informativeText = @"Enter the MIDI note range (0-127):";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    // Create accessory view with two text fields for low/high note
    NSView *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 54)];

    NSTextField *lowLabel = [NSTextField labelWithString:@"Low Note:"];
    lowLabel.frame = NSMakeRect(0, 30, 80, 18);
    [accessoryView addSubview:lowLabel];

    NSTextField *lowField = [[NSTextField alloc] initWithFrame:NSMakeRect(85, 28, 60, 22)];
    NSInteger startLow = (_customLowNote >= 0) ? _customLowNote : 0;
    lowField.stringValue = [NSString stringWithFormat:@"%ld", (long)startLow];
    [accessoryView addSubview:lowField];

    NSTextField *highLabel = [NSTextField labelWithString:@"High Note:"];
    highLabel.frame = NSMakeRect(0, 2, 80, 18);
    [accessoryView addSubview:highLabel];

    NSTextField *highField = [[NSTextField alloc] initWithFrame:NSMakeRect(85, 0, 60, 22)];
    NSInteger startHigh = (_customHighNote >= 0) ? _customHighNote : 127;
    highField.stringValue = [NSString stringWithFormat:@"%ld", (long)startHigh];
    [accessoryView addSubview:highField];

    alert.accessoryView = accessoryView;
    [alert.window setInitialFirstResponder:lowField];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSInteger low = lowField.integerValue;
        NSInteger high = highField.integerValue;

        // Clamp to valid MIDI range
        low = MAX(0, MIN(127, low));
        high = MAX(0, MIN(127, high));
        if (low > high) {
            NSInteger temp = low;
            low = high;
            high = temp;
        }

        _customLowNote = low;
        _customHighNote = high;
        _waveformType = XLWaveformTypeCustom;
        [self invalidateWaveformCache];
        _needsRedraw = YES;
        [self.layer setNeedsDisplay];

        if ([_delegate respondsToSelector:@selector(waveformView:didChangeWaveformType:lowNote:highNote:)]) {
            [_delegate waveformView:self didChangeWaveformType:_waveformType lowNote:_customLowNote highNote:_customHighNote];
        }
    }
}

- (void)contextMenuDoubleHeight:(NSMenuItem *)sender {
    _doubleHeight = !_doubleHeight;
    [self invalidateWaveformCache];
    _needsRedraw = YES;
    [self.layer setNeedsDisplay];

    if ([_delegate respondsToSelector:@selector(waveformView:didChangeDoubleHeight:)]) {
        [_delegate waveformView:self didChangeDoubleHeight:_doubleHeight];
    }
}

#pragma mark - Intrinsic Content Size

- (NSSize)intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric, 60.0);
}

@end
