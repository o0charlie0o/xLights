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
    // Cached full-width waveform rendered at current zoom level.
    // Only regenerated when stem data or zoom changes — scroll just blits a portion.
    CGImageRef _cachedWaveformImage;
    CGFloat _cachedZoomLevel;
    CGFloat _cachedImageWidth;
    CGFloat _cachedImageHeight;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _zoomLevel = 0.1;
        _scrollOffsetX = 0;
        _sequenceLengthMS = 60000;
        _playbackPositionMS = -1;
    }
    return self;
}

- (void)dealloc {
    CGImageRelease(_cachedWaveformImage);
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return YES;
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
    [self setNeedsDisplay:YES];  // No cache invalidation — just blits a different portion
}

- (void)setPlaybackPositionMS:(CGFloat)playbackPositionMS {
    _playbackPositionMS = playbackPositionMS;
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

#pragma mark - Coordinate Conversion

- (CGFloat)pointXForTimeMS:(CGFloat)timeMS {
    return (timeMS * _zoomLevel) - _scrollOffsetX;
}

#pragma mark - Waveform Cache

- (void)invalidateCache {
    CGImageRelease(_cachedWaveformImage);
    _cachedWaveformImage = NULL;
}

- (void)rebuildCacheIfNeeded {
    XLStemData *stem = _stemData;
    if (!stem || stem.isLoading) return;

    NSArray<NSValue *> *buckets = stem.overviewBuckets;
    if (!buckets || buckets.count == 0) return;

    CGFloat height = NSHeight(self.bounds);
    if (height < 1) return;

    // Calculate full waveform width at current zoom
    CGFloat fullWidth = stem.durationMS * _zoomLevel;
    if (fullWidth < 1) return;

    // Cap at a reasonable max to avoid huge allocations (e.g., 32K pixels)
    CGFloat maxCacheWidth = 32768.0;
    CGFloat cacheWidth = fmin(fullWidth, maxCacheWidth);

    // If cache is still valid, skip
    if (_cachedWaveformImage &&
        fabs(_cachedZoomLevel - _zoomLevel) < 0.00001 &&
        fabs(_cachedImageHeight - height) < 0.5) {
        return;
    }

    _cachedZoomLevel = _zoomLevel;
    _cachedImageWidth = cacheWidth;
    _cachedImageHeight = height;

    // Create bitmap context
    NSUInteger pixelWidth = (NSUInteger)cacheWidth;
    NSUInteger pixelHeight = (NSUInteger)height;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef bctx = CGBitmapContextCreate(NULL, pixelWidth, pixelHeight, 8,
                                               pixelWidth * 4,
                                               cs,
                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(cs);
    if (!bctx) return;

    // Transparent background (the view draws its own background)
    CGContextClearRect(bctx, CGRectMake(0, 0, pixelWidth, pixelHeight));

    // Waveform color
    NSColor *color = stem.waveformColor ?: [NSColor greenColor];
    CGFloat r, g, b, a;
    [[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] getRed:&r green:&g blue:&b alpha:&a];
    CGContextSetRGBFillColor(bctx, r, g, b, 0.8);

    // Render waveform into bitmap (non-flipped: y=0 is bottom)
    CGFloat centerY = height / 2.0;
    CGFloat halfHeight = (height - 4.0) / 2.0;

    NSUInteger bucketCount = buckets.count;
    CGFloat durationMS = stem.durationMS;
    double msPerBucket = durationMS / (double)bucketCount;

    // Pre-extract bucket data to C array for fast access
    XLWaveformBucket *bucketData = (XLWaveformBucket *)malloc(bucketCount * sizeof(XLWaveformBucket));
    for (NSUInteger i = 0; i < bucketCount; i++) {
        [buckets[i] getValue:&bucketData[i]];
    }

    for (NSUInteger px = 0; px < pixelWidth; px++) {
        // This pixel corresponds to time: px / zoomLevel
        CGFloat timeMS = (CGFloat)px / _zoomLevel;
        if (timeMS >= durationMS) break;

        NSUInteger bi1 = (NSUInteger)(timeMS / msPerBucket);
        if (bi1 >= bucketCount) bi1 = bucketCount - 1;

        CGFloat timeMS2 = (CGFloat)(px + 1) / _zoomLevel;
        NSUInteger bi2 = (NSUInteger)(timeMS2 / msPerBucket);
        if (bi2 >= bucketCount) bi2 = bucketCount - 1;

        float minVal = 1.0f, maxVal = -1.0f;
        for (NSUInteger bi = bi1; bi <= bi2; bi++) {
            float bMin = fminf(bucketData[bi].minL, bucketData[bi].minR);
            float bMax = fmaxf(bucketData[bi].maxL, bucketData[bi].maxR);
            if (bMin < minVal) minVal = bMin;
            if (bMax > maxVal) maxVal = bMax;
        }

        // Non-flipped bitmap: flip Y
        CGFloat y1 = centerY - maxVal * halfHeight;
        CGFloat y2 = centerY - minVal * halfHeight;
        if (fabs(y2 - y1) < 1.0) {
            y1 = centerY - 0.5;
            y2 = centerY + 0.5;
        }

        CGContextFillRect(bctx, CGRectMake((CGFloat)px, fmin(y1, y2), 1.0, fabs(y2 - y1)));
    }

    free(bucketData);

    CGImageRelease(_cachedWaveformImage);
    _cachedWaveformImage = CGBitmapContextCreateImage(bctx);
    CGContextRelease(bctx);
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

    // Rebuild cache if needed (only on data/zoom/height change)
    [self rebuildCacheIfNeeded];

    if (_cachedWaveformImage) {
        // Blit the visible portion of the cached waveform image
        // Source rect in image coords (non-flipped: origin at bottom-left)
        CGFloat srcX = _scrollOffsetX;
        CGFloat srcWidth = fmin(width, _cachedImageWidth - srcX);
        if (srcWidth <= 0) goto playhead;

        CGRect srcRect = CGRectMake(srcX, 0, srcWidth, _cachedImageHeight);
        // Destination rect in view coords (flipped context)
        CGRect dstRect = CGRectMake(0, 0, srcWidth, height);

        // Save state and flip for CGImage drawing (CGImage draws non-flipped)
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, 0, height);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGImageRef subImage = CGImageCreateWithImageInRect(_cachedWaveformImage, srcRect);
        CGContextDrawImage(ctx, dstRect, subImage);
        CGImageRelease(subImage);
        CGContextRestoreGState(ctx);
    }

playhead:
    // Draw playhead
    if (_playbackPositionMS >= 0) {
        CGFloat playheadX = [self pointXForTimeMS:_playbackPositionMS];
        if (playheadX >= 0 && playheadX <= width) {
            CGContextSetRGBStrokeColor(ctx, 1.0, 0.2, 0.2, 0.9);
            CGContextSetLineWidth(ctx, 1.0);
            CGContextMoveToPoint(ctx, playheadX, 0);
            CGContextAddLineToPoint(ctx, playheadX, height);
            CGContextStrokePath(ctx);
        }
    }
}

@end
