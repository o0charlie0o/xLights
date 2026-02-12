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

static const CGFloat kLabelLeftPadding = 4.0;
static const CGFloat kLabelFontSize = 9.0;

@implementation XLMiniWaveformView {
    BOOL _needsRedraw;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.delegate = (id<CALayerDelegate>)self;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        _zoomLevel = 0.1;
        _scrollOffsetX = 0;
        _sequenceLengthMS = 60000;
        _playbackPositionMS = -1;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

#pragma mark - Property Setters

- (void)setZoomLevel:(CGFloat)zoomLevel {
    if (fabs(_zoomLevel - zoomLevel) < 0.00001) return;
    _zoomLevel = zoomLevel;
    [self setNeedsRedraw];
}

- (void)setScrollOffsetX:(CGFloat)scrollOffsetX {
    if (fabs(_scrollOffsetX - scrollOffsetX) < 0.01) return;
    _scrollOffsetX = scrollOffsetX;
    [self setNeedsRedraw];
}

- (void)setPlaybackPositionMS:(CGFloat)playbackPositionMS {
    _playbackPositionMS = playbackPositionMS;
    [self setNeedsRedraw];
}

- (void)setStemData:(XLStemData *)stemData {
    _stemData = stemData;
    [self setNeedsRedraw];
}

- (void)setNeedsRedraw {
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

#pragma mark - CALayerDelegate Drawing

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
    CGFloat width = NSWidth(self.bounds);
    CGFloat height = NSHeight(self.bounds);

    static int drawCount = 0;
    if (drawCount < 30) {
        NSLog(@"[Stems] drawLayer '%@': bounds=%.0fx%.0f frame=%@ stem=%@ loading=%d buckets=%lu",
              _stemData.name ?: @"(nil)", width, height,
              NSStringFromRect(self.frame),
              _stemData ? @"YES" : @"NO",
              _stemData.isLoading,
              (unsigned long)_stemData.overviewBuckets.count);
        drawCount++;
    }

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
    if (!stem) return;

    NSArray<NSValue *> *buckets = stem.overviewBuckets;

    if (stem.isLoading) {
        // Show loading text
        [self drawLabel:[NSString stringWithFormat:@"%@ (loading...)", stem.name]
              inContext:ctx width:width height:height color:stem.waveformColor];
        return;
    }

    if (!buckets || buckets.count == 0) {
        [self drawLabel:[NSString stringWithFormat:@"%@ (no data)", stem.name]
              inContext:ctx width:width height:height color:stem.waveformColor];
        return;
    }

    // Draw waveform
    CGFloat centerY = height / 2.0;
    CGFloat halfHeight = (height - 4.0) / 2.0;  // 2px padding top/bottom

    NSColor *color = stem.waveformColor ?: [NSColor greenColor];
    CGFloat r, g, b, a;
    [[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] getRed:&r green:&g blue:&b alpha:&a];
    CGContextSetRGBFillColor(ctx, r, g, b, 0.8);

    [self drawWaveformInContext:ctx
                         buckets:buckets
                           width:width
                         centerY:centerY
                      halfHeight:halfHeight
                      durationMS:stem.durationMS];

    // Draw stem name label
    [self drawLabel:stem.name inContext:ctx width:width height:height color:stem.waveformColor];

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

- (void)drawWaveformInContext:(CGContextRef)ctx
                      buckets:(NSArray<NSValue *> *)buckets
                        width:(CGFloat)width
                      centerY:(CGFloat)centerY
                   halfHeight:(CGFloat)halfHeight
                   durationMS:(CGFloat)durationMS
{
    NSUInteger bucketCount = buckets.count;
    if (bucketCount == 0 || durationMS <= 0) return;

    double msPerBucket = durationMS / (double)bucketCount;

    for (NSUInteger px = 0; px < (NSUInteger)width; px++) {
        CGFloat timeMS = [self timeMSForPointX:(CGFloat)px];
        if (timeMS < 0 || timeMS >= durationMS) continue;

        NSUInteger bucketIndex = (NSUInteger)(timeMS / msPerBucket);
        if (bucketIndex >= bucketCount) bucketIndex = bucketCount - 1;

        // Aggregate multiple buckets per pixel at wider zoom
        CGFloat timeMS2 = [self timeMSForPointX:(CGFloat)(px + 1)];
        NSUInteger bucketIndex2 = (NSUInteger)(timeMS2 / msPerBucket);
        if (bucketIndex2 >= bucketCount) bucketIndex2 = bucketCount - 1;

        float minVal = 1.0f, maxVal = -1.0f;

        for (NSUInteger bi = bucketIndex; bi <= bucketIndex2; bi++) {
            XLWaveformBucket bucket;
            [buckets[bi] getValue:&bucket];

            // Mix L+R for mono display
            float bMin = fminf(bucket.minL, bucket.minR);
            float bMax = fmaxf(bucket.maxL, bucket.maxR);

            if (bMin < minVal) minVal = bMin;
            if (bMax > maxVal) maxVal = bMax;
        }

        CGFloat y1 = centerY + minVal * halfHeight;
        CGFloat y2 = centerY + maxVal * halfHeight;

        if (fabs(y2 - y1) < 1.0) {
            y1 = centerY - 0.5;
            y2 = centerY + 0.5;
        }

        CGContextFillRect(ctx, CGRectMake((CGFloat)px, fmin(y1, y2), 1.0, fabs(y2 - y1)));
    }
}

- (void)drawLabel:(NSString *)label
        inContext:(CGContextRef)ctx
            width:(CGFloat)width
           height:(CGFloat)height
            color:(NSColor *)color
{
    if (!label) return;

    // Draw semi-transparent background behind label
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:kLabelFontSize weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: color ?: [NSColor whiteColor]
    };
    NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:label attributes:attrs];
    NSSize textSize = [attrStr size];

    CGFloat textY = (height - textSize.height) / 2.0;
    CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 0.6);
    CGContextFillRect(ctx, CGRectMake(0, textY - 1, textSize.width + kLabelLeftPadding * 2 + 2, textSize.height + 2));

    // Push graphics state for NSAttributedString drawing
    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:gc];
    [attrStr drawAtPoint:NSMakePoint(kLabelLeftPadding, textY)];
    [NSGraphicsContext restoreGraphicsState];
}

@end
