/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLMiniWaveformView.h"
#import "XLStemData.h"
#import "XLAudioLoader.h"

@implementation XLMiniWaveformView {
    // Visible-region cache: covers viewport + padding on each side.
    // Rebuilt when scrolling outside cached region, or on zoom/height/data change.
    // Rendered at backingScaleFactor resolution for crisp Retina display.
    CGImageRef _cachedImage;
    CGFloat _cachedZoomLevel;
    CGFloat _cachedScrollX;    // left edge of cached region in zoomed-pixel coordinates
    CGFloat _cachedWidthPts;   // width of cached region in points
    CGFloat _cachedHeightPts;  // height in points when cached
    CGFloat _cachedScale;      // backing scale factor when cached
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _zoomLevel = 0.1;
        _scrollOffsetX = 0;
        _sequenceLengthMS = 60000;
        _playbackPositionMS = -1;
        _cursorPositionMS = -1;
    }
    return self;
}

- (void)dealloc {
    CGImageRelease(_cachedImage);
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self invalidateCache];
    [self setNeedsDisplay:YES];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [self invalidateCache];
    [self setNeedsDisplay:YES];
}

#pragma mark - Property Setters

- (void)setZoomLevel:(CGFloat)zoomLevel {
    if (fabs(_zoomLevel - zoomLevel) < 0.00001) return;
    _zoomLevel = zoomLevel;
    [self invalidateCache];
    [self setNeedsDisplay:YES];
}

- (void)setScrollOffsetX:(CGFloat)scrollOffsetX {
    if (fabs(_scrollOffsetX - scrollOffsetX) < 0.01) return;
    _scrollOffsetX = scrollOffsetX;
    [self setNeedsDisplay:YES];  // drawRect checks if cache still covers viewport
}

- (void)setPlaybackPositionMS:(CGFloat)playbackPositionMS {
    _playbackPositionMS = playbackPositionMS;
    [self setNeedsDisplay:YES];
}

- (void)setCursorPositionMS:(CGFloat)cursorPositionMS {
    if (fabs(cursorPositionMS - _cursorPositionMS) < 0.01) return;
    _cursorPositionMS = cursorPositionMS;
    [self setNeedsDisplay:YES];
}

- (void)setStemData:(XLStemData *)stemData {
    _stemData = stemData;
    [self invalidateCache];
    [self setNeedsDisplay:YES];
}

- (void)setSequenceLengthMS:(CGFloat)sequenceLengthMS {
    _sequenceLengthMS = sequenceLengthMS;
    [self invalidateCache];
    [self setNeedsDisplay:YES];
}

- (void)setOnsetPreviewTimesMS:(NSArray<NSNumber *> *)onsetPreviewTimesMS {
    _onsetPreviewTimesMS = [onsetPreviewTimesMS copy];
    [self setNeedsDisplay:YES];
}

#pragma mark - Coordinate Conversion

- (CGFloat)pointXForTimeMS:(CGFloat)timeMS {
    return (timeMS * _zoomLevel) - _scrollOffsetX;
}

#pragma mark - Waveform Cache

- (void)invalidateCache {
    CGImageRelease(_cachedImage);
    _cachedImage = NULL;
}

- (void)rebuildCacheIfNeeded {
    XLStemData *stem = _stemData;
    if (!stem || stem.isLoading) return;

    NSArray<NSValue *> *buckets = stem.overviewBuckets;
    if (!buckets || buckets.count == 0) return;

    CGFloat height = NSHeight(self.bounds);
    CGFloat viewWidth = NSWidth(self.bounds);
    if (height < 1 || viewWidth < 1) return;

    CGFloat scale = self.window.backingScaleFactor ?: 2.0;
    CGFloat durationMS = stem.durationMS;
    if (durationMS <= 0) return;

    // Check if existing cache covers the visible region
    if (_cachedImage &&
        fabs(_cachedZoomLevel - _zoomLevel) < 0.00001 &&
        fabs(_cachedHeightPts - height) < 0.5 &&
        fabs(_cachedScale - scale) < 0.01 &&
        _scrollOffsetX >= _cachedScrollX &&
        (_scrollOffsetX + viewWidth) <= (_cachedScrollX + _cachedWidthPts + 0.5)) {
        return;
    }

    // Cache viewport + 1x padding on each side (3x total)
    CGFloat padding = viewWidth;
    CGFloat cacheStartX = fmax(0, _scrollOffsetX - padding);
    CGFloat fullZoomedWidth = durationMS * _zoomLevel;
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

    // Waveform color
    NSColor *color = stem.waveformColor ?: [NSColor greenColor];
    CGFloat r, g, b, a;
    [[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] getRed:&r green:&g blue:&b alpha:&a];
    CGContextSetRGBFillColor(bctx, r, g, b, 0.8);

    // Render in raw pixel coordinates (non-flipped: y=0 is bottom)
    CGFloat centerYPx = pixelHeight / 2.0;
    CGFloat halfHeightPx = (pixelHeight - 4.0 * scale) / 2.0;

    NSUInteger bucketCount = buckets.count;
    double msPerBucket = durationMS / (double)bucketCount;

    // Determine rendering mode: raw samples at high zoom, buckets at low zoom.
    // Switch to samples when each bucket spans more than ~2 pixels.
    CGFloat msPerPixel = 1.0 / (_zoomLevel * scale);
    BOOL useSamples = NO;
    float *samples = NULL;
    NSUInteger sampleCount = 0;
    NSUInteger channelCount = 0;
    double sampleRate = 0;

    if (stem.audioData && msPerPixel < msPerBucket * 2.0) {
        useSamples = YES;
        samples = stem.audioData.samples;
        sampleCount = stem.audioData.sampleCount;
        channelCount = stem.audioData.channelCount;
        sampleRate = stem.audioData.sampleRate;
    }

    // Pre-extract bucket data to C array for fast access (only when using buckets)
    XLWaveformBucket *bucketData = NULL;
    if (!useSamples) {
        bucketData = (XLWaveformBucket *)malloc(bucketCount * sizeof(XLWaveformBucket));
        for (NSUInteger i = 0; i < bucketCount; i++) {
            [buckets[i] getValue:&bucketData[i]];
        }
    }

    for (NSUInteger px = 0; px < pixelWidth; px++) {
        // Map each bitmap pixel to a time range
        CGFloat zoomedPt = cacheStartX + (CGFloat)px / scale;
        CGFloat timeMS1 = zoomedPt / _zoomLevel;
        CGFloat timeMS2 = (zoomedPt + 1.0 / scale) / _zoomLevel;
        if (timeMS1 >= durationMS) break;
        if (timeMS2 > durationMS) timeMS2 = durationMS;

        float minVal = 1.0f, maxVal = -1.0f;

        if (useSamples) {
            // High zoom: compute min/max from raw PCM samples
            NSUInteger startFrame = (NSUInteger)(timeMS1 / 1000.0 * sampleRate);
            NSUInteger endFrame = (NSUInteger)(timeMS2 / 1000.0 * sampleRate);
            if (startFrame >= sampleCount) startFrame = sampleCount - 1;
            if (endFrame >= sampleCount) endFrame = sampleCount - 1;

            for (NSUInteger f = startFrame; f <= endFrame; f++) {
                float sL = samples[f * channelCount];
                float sR = (channelCount > 1) ? samples[f * channelCount + 1] : sL;
                float sMin = fminf(sL, sR);
                float sMax = fmaxf(sL, sR);
                if (sMin < minVal) minVal = sMin;
                if (sMax > maxVal) maxVal = sMax;
            }
        } else {
            // Low zoom: compute min/max from overview buckets
            NSUInteger bi1 = (NSUInteger)(timeMS1 / msPerBucket);
            if (bi1 >= bucketCount) bi1 = bucketCount - 1;
            NSUInteger bi2 = (NSUInteger)(timeMS2 / msPerBucket);
            if (bi2 >= bucketCount) bi2 = bucketCount - 1;

            for (NSUInteger bi = bi1; bi <= bi2; bi++) {
                float bMin = fminf(bucketData[bi].minL, bucketData[bi].minR);
                float bMax = fmaxf(bucketData[bi].maxL, bucketData[bi].maxR);
                if (bMin < minVal) minVal = bMin;
                if (bMax > maxVal) maxVal = bMax;
            }
        }

        CGFloat y1 = centerYPx - maxVal * halfHeightPx;
        CGFloat y2 = centerYPx - minVal * halfHeightPx;
        if (fabs(y2 - y1) < 1.0) {
            y1 = centerYPx - 0.5;
            y2 = centerYPx + 0.5;
        }

        CGContextFillRect(bctx, CGRectMake(px, fmin(y1, y2), 1.0, fabs(y2 - y1)));
    }

    free(bucketData);

    CGImageRelease(_cachedImage);
    _cachedImage = CGBitmapContextCreateImage(bctx);
    CGContextRelease(bctx);

    _cachedZoomLevel = _zoomLevel;
    _cachedScrollX = cacheStartX;
    _cachedWidthPts = cacheWidthPts;
    _cachedHeightPts = height;
    _cachedScale = scale;
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    if (!ctx) return;

    CGFloat width = NSWidth(self.bounds);
    CGFloat height = NSHeight(self.bounds);

    // Dark background
    CGContextSetRGBFillColor(ctx, 0.10, 0.10, 0.10, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, width, height));

    // Bottom separator line
    CGContextSetRGBStrokeColor(ctx, 0.25, 0.25, 0.25, 1.0);
    CGContextSetLineWidth(ctx, 0.5);
    CGContextMoveToPoint(ctx, 0, height - 0.25);
    CGContextAddLineToPoint(ctx, width, height - 0.25);
    CGContextStrokePath(ctx);

    XLStemData *stem = _stemData;
    if (!stem || stem.isLoading) return;
    if (!stem.overviewBuckets || stem.overviewBuckets.count == 0) return;

    // Rebuild cache if needed (checks zoom, height, scale, and scroll coverage)
    [self rebuildCacheIfNeeded];

    if (_cachedImage) {
        CGFloat offsetInCache = _scrollOffsetX - _cachedScrollX;
        CGFloat availableWidth = _cachedWidthPts - offsetInCache;
        CGFloat blitWidth = fmin(width, availableWidth);
        if (blitWidth <= 0) goto playhead;

        // Source rect in pixel coordinates of the cached image
        CGFloat srcPixelX = offsetInCache * _cachedScale;
        CGFloat srcPixelW = blitWidth * _cachedScale;
        CGFloat srcPixelH = (CGFloat)CGImageGetHeight(_cachedImage);

        CGRect srcRect = CGRectMake(srcPixelX, 0, srcPixelW, srcPixelH);
        CGRect dstRect = CGRectMake(0, 0, blitWidth, height);

        // Flip for CGImage drawing (CGImage is non-flipped, our context is flipped)
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, 0, height);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGImageRef subImage = CGImageCreateWithImageInRect(_cachedImage, srcRect);
        CGContextDrawImage(ctx, dstRect, subImage);
        CGImageRelease(subImage);
        CGContextRestoreGState(ctx);
    }

playhead:
    // Draw onset preview markers (cyan lines — visible against any stem color)
    if (_onsetPreviewTimesMS.count > 0) {
        CGContextSetRGBStrokeColor(ctx, 0.0, 0.9, 1.0, 0.8);
        CGContextSetLineWidth(ctx, 1.0);
        for (NSNumber *timeNum in _onsetPreviewTimesMS) {
            CGFloat timeMS = timeNum.doubleValue;
            CGFloat x = [self pointXForTimeMS:timeMS];
            if (x < -1 || x > width + 1) continue;
            CGContextMoveToPoint(ctx, x, 0);
            CGContextAddLineToPoint(ctx, x, height);
        }
        CGContextStrokePath(ctx);
    }

    // Draw cursor line (white, semi-transparent — same as main waveform)
    if (_cursorPositionMS >= 0 && _cursorPositionMS <= _sequenceLengthMS) {
        CGFloat cursorX = [self pointXForTimeMS:_cursorPositionMS];
        if (cursorX >= 0 && cursorX <= width) {
            CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, 0.6);
            CGContextSetLineWidth(ctx, 1.0);
            CGContextMoveToPoint(ctx, cursorX, 0);
            CGContextAddLineToPoint(ctx, cursorX, height);
            CGContextStrokePath(ctx);
        }
    }

    // Draw playhead
    if (_playbackPositionMS >= 0) {
        CGFloat playheadX = [self pointXForTimeMS:_playbackPositionMS];
        if (playheadX >= 0 && playheadX <= width) {
            CGContextSetRGBStrokeColor(ctx, 0.2, 0.5, 1.0, 0.9);
            CGContextSetLineWidth(ctx, 1.0);
            CGContextMoveToPoint(ctx, playheadX, 0);
            CGContextAddLineToPoint(ctx, playheadX, height);
            CGContextStrokePath(ctx);
        }
    }
}

@end
