/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLVideoModelGenerator.h"
#import <Accelerate/Accelerate.h>

// Timing constants matching the legacy xLights protocol
static const NSTimeInterval kLeadOff       = 3.0;   // seconds of darkness before start
static const NSTimeInterval kFlagOn        = 0.6;   // seconds for all-on flash
static const NSTimeInterval kFlagOff       = 0.4;   // seconds for all-off gap
static const NSTimeInterval kNodeOn        = 0.5;   // seconds per node/encoding frame
static const NSTimeInterval kDelaySample   = 0.25;  // delay into flash before sampling
static const NSTimeInterval kFrameInterval = 0.05;  // 50ms between scanned frames
static const NSTimeInterval kStartScanDuration = 15.0; // scan first 15 seconds for start pattern

// Model sizing
static const NSInteger kModelSizeMultiplier = 2; // extra padding around model
static const NSInteger kMatrixFudge = kModelSizeMultiplier * 2;

#pragma mark - XLDetectedNode

@implementation XLDetectedNode

+ (instancetype)nodeWithLocation:(NSPoint)location number:(NSInteger)number {
    XLDetectedNode *node = [[XLDetectedNode alloc] init];
    node.location = location;
    node.nodeNumber = number;
    return node;
}

@end

#pragma mark - XLProcessedFrame

@implementation XLProcessedFrame

- (instancetype)initWithBitmap:(NSBitmapImageRep *)bitmap timestamp:(NSTimeInterval)timestamp {
    self = [super init];
    if (self) {
        _bitmap = bitmap;
        _timestamp = timestamp;
        _width = bitmap.pixelsWide;
        _height = bitmap.pixelsHigh;
    }
    return self;
}

- (uint8_t)brightnessAtX:(NSInteger)x y:(NSInteger)y {
    if (x < 0 || x >= _width || y < 0 || y >= _height) return 0;
    NSColor *color = [[_bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!color) return 0;
    return (uint8_t)((color.redComponent + color.greenComponent + color.blueComponent) / 3.0 * 255.0);
}

- (uint8_t)redAtX:(NSInteger)x y:(NSInteger)y {
    if (x < 0 || x >= _width || y < 0 || y >= _height) return 0;
    NSColor *color = [[_bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return color ? (uint8_t)(color.redComponent * 255.0) : 0;
}

- (uint8_t)greenAtX:(NSInteger)x y:(NSInteger)y {
    if (x < 0 || x >= _width || y < 0 || y >= _height) return 0;
    NSColor *color = [[_bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return color ? (uint8_t)(color.greenComponent * 255.0) : 0;
}

- (uint8_t)blueAtX:(NSInteger)x y:(NSInteger)y {
    if (x < 0 || x >= _width || y < 0 || y >= _height) return 0;
    NSColor *color = [[_bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return color ? (uint8_t)(color.blueComponent * 255.0) : 0;
}

- (XLProcessedFrame *)greyscaleCopy {
    NSBitmapImageRep *grey = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:_width
                      pixelsHigh:_height
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSCalibratedRGBColorSpace
                     bytesPerRow:0
                    bitsPerPixel:0];

    for (NSInteger y = 0; y < _height; y++) {
        for (NSInteger x = 0; x < _width; x++) {
            uint8_t b = [self brightnessAtX:x y:y];
            [grey setColor:[NSColor colorWithCalibratedWhite:b / 255.0 alpha:1.0] atX:x y:y];
        }
    }

    return [[XLProcessedFrame alloc] initWithBitmap:grey timestamp:_timestamp];
}

- (XLProcessedFrame *)subtractBackground:(XLProcessedFrame *)background scale:(float)scale {
    NSBitmapImageRep *result = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:_width
                      pixelsHigh:_height
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSCalibratedRGBColorSpace
                     bytesPerRow:0
                    bitsPerPixel:0];

    for (NSInteger y = 0; y < _height; y++) {
        for (NSInteger x = 0; x < _width; x++) {
            NSColor *srcColor = [[_bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            NSColor *bgColor = [[background.bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            if (!srcColor || !bgColor) {
                [result setColor:[NSColor blackColor] atX:x y:y];
                continue;
            }
            CGFloat r = MAX(0, srcColor.redComponent - bgColor.redComponent * scale);
            CGFloat g = MAX(0, srcColor.greenComponent - bgColor.greenComponent * scale);
            CGFloat b = MAX(0, srcColor.blueComponent - bgColor.blueComponent * scale);
            [result setColor:[NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0] atX:x y:y];
        }
    }

    return [[XLProcessedFrame alloc] initWithBitmap:result timestamp:_timestamp];
}

- (NSInteger)frameDeltaFrom:(XLProcessedFrame *)other {
    NSInteger delta = 0;
    NSInteger step = MAX(1, _width * _height / 10000); // sample for speed
    for (NSInteger i = 0; i < _width * _height; i += step) {
        NSInteger x = i % _width;
        NSInteger y = i / _width;
        delta += (NSInteger)[self brightnessAtX:x y:y] - (NSInteger)[other brightnessAtX:x y:y];
    }
    return delta;
}

- (XLProcessedFrame *)channelImage:(NSInteger)channel {
    NSBitmapImageRep *chBitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:_width
                      pixelsHigh:_height
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSCalibratedRGBColorSpace
                     bytesPerRow:0
                    bitsPerPixel:0];

    for (NSInteger y = 0; y < _height; y++) {
        for (NSInteger x = 0; x < _width; x++) {
            NSColor *color = [[_bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            uint8_t val = 0;
            if (color) {
                switch (channel) {
                    case 0: val = (uint8_t)(color.redComponent * 255.0); break;
                    case 1: val = (uint8_t)(color.greenComponent * 255.0); break;
                    case 2: val = (uint8_t)(color.blueComponent * 255.0); break;
                }
            }
            CGFloat v = val / 255.0;
            [chBitmap setColor:[NSColor colorWithCalibratedRed:v green:v blue:v alpha:1.0] atX:x y:y];
        }
    }

    return [[XLProcessedFrame alloc] initWithBitmap:chBitmap timestamp:_timestamp];
}

- (void)applyMinWith:(XLProcessedFrame *)other {
    for (NSInteger y = 0; y < _height; y++) {
        for (NSInteger x = 0; x < _width; x++) {
            NSColor *c1 = [[_bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            NSColor *c2 = [[other.bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            if (!c1 || !c2) continue;
            CGFloat r = MIN(c1.redComponent, c2.redComponent);
            CGFloat g = MIN(c1.greenComponent, c2.greenComponent);
            CGFloat b = MIN(c1.blueComponent, c2.blueComponent);
            [_bitmap setColor:[NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0] atX:x y:y];
        }
    }
}

- (void)applyThreshold:(uint8_t)threshold {
    for (NSInteger y = 0; y < _height; y++) {
        for (NSInteger x = 0; x < _width; x++) {
            uint8_t b = [self brightnessAtX:x y:y];
            CGFloat v = (b >= threshold) ? 1.0 : 0.0;
            [_bitmap setColor:[NSColor colorWithCalibratedWhite:v alpha:1.0] atX:x y:y];
        }
    }
}

- (void)applyBlur:(NSInteger)radius {
    if (radius <= 0) return;

    // Simple box blur implementation
    NSBitmapImageRep *temp = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:_width
                      pixelsHigh:_height
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSCalibratedRGBColorSpace
                     bytesPerRow:0
                    bitsPerPixel:0];

    for (NSInteger y = 0; y < _height; y++) {
        for (NSInteger x = 0; x < _width; x++) {
            CGFloat sumR = 0, sumG = 0, sumB = 0;
            NSInteger count = 0;
            for (NSInteger dy = -radius; dy <= radius; dy++) {
                for (NSInteger dx = -radius; dx <= radius; dx++) {
                    NSInteger nx = x + dx;
                    NSInteger ny = y + dy;
                    if (nx >= 0 && nx < _width && ny >= 0 && ny < _height) {
                        NSColor *c = [[_bitmap colorAtX:nx y:ny] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                        if (c) {
                            sumR += c.redComponent;
                            sumG += c.greenComponent;
                            sumB += c.blueComponent;
                            count++;
                        }
                    }
                }
            }
            if (count > 0) {
                [temp setColor:[NSColor colorWithCalibratedRed:sumR/count green:sumG/count blue:sumB/count alpha:1.0] atX:x y:y];
            }
        }
    }

    _bitmap = temp;
}

- (void)applyContrast:(NSInteger)contrast {
    if (contrast == 0) return;
    CGFloat factor = (259.0 * (contrast + 255.0)) / (255.0 * (259.0 - contrast));

    for (NSInteger y = 0; y < _height; y++) {
        for (NSInteger x = 0; x < _width; x++) {
            NSColor *c = [[_bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            if (!c) continue;
            CGFloat r = MAX(0, MIN(1, factor * (c.redComponent - 0.5) + 0.5));
            CGFloat g = MAX(0, MIN(1, factor * (c.greenComponent - 0.5) + 0.5));
            CGFloat b = MAX(0, MIN(1, factor * (c.blueComponent - 0.5) + 0.5));
            [_bitmap setColor:[NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0] atX:x y:y];
        }
    }
}

- (void)applyGamma:(float)gamma {
    if (gamma == 1.0) return;
    float invGamma = 1.0f / gamma;

    for (NSInteger y = 0; y < _height; y++) {
        for (NSInteger x = 0; x < _width; x++) {
            NSColor *c = [[_bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            if (!c) continue;
            CGFloat r = powf(c.redComponent, invGamma);
            CGFloat g = powf(c.greenComponent, invGamma);
            CGFloat b = powf(c.blueComponent, invGamma);
            [_bitmap setColor:[NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0] atX:x y:y];
        }
    }
}

- (NSPoint)findBrightestRegionCenter {
    // Find connected bright regions using flood fill, return center of largest
    NSMutableData *visited = [NSMutableData dataWithLength:_width * _height];
    uint8_t *vis = (uint8_t *)visited.mutableBytes;

    NSPoint bestCenter = NSMakePoint(-1, -1);
    NSInteger bestSize = 0;

    for (NSInteger y = 0; y < _height; y++) {
        for (NSInteger x = 0; x < _width; x++) {
            if (vis[y * _width + x]) continue;
            uint8_t b = [self brightnessAtX:x y:y];
            if (b < 128) { vis[y * _width + x] = 1; continue; }

            // Flood fill from this bright pixel
            NSMutableArray *stack = [NSMutableArray arrayWithObject:[NSValue valueWithPoint:NSMakePoint(x, y)]];
            CGFloat sumX = 0, sumY = 0;
            NSInteger count = 0;

            while (stack.count > 0) {
                NSPoint pt = ((NSValue *)stack.lastObject).pointValue;
                [stack removeLastObject];
                NSInteger px = (NSInteger)pt.x;
                NSInteger py = (NSInteger)pt.y;
                if (px < 0 || px >= _width || py < 0 || py >= _height) continue;
                if (vis[py * _width + px]) continue;
                if ([self brightnessAtX:px y:py] < 128) continue;

                vis[py * _width + px] = 1;
                sumX += px;
                sumY += py;
                count++;

                [stack addObject:[NSValue valueWithPoint:NSMakePoint(px + 1, py)]];
                [stack addObject:[NSValue valueWithPoint:NSMakePoint(px - 1, py)]];
                [stack addObject:[NSValue valueWithPoint:NSMakePoint(px, py + 1)]];
                [stack addObject:[NSValue valueWithPoint:NSMakePoint(px, py - 1)]];
            }

            if (count > bestSize) {
                bestSize = count;
                bestCenter = NSMakePoint(sumX / count, sumY / count);
            }
        }
    }

    return bestCenter;
}

- (NSArray<NSValue *> *)findBrightPixelCenters:(NSInteger)minSeparation {
    NSMutableArray<NSValue *> *centers = [NSMutableArray array];
    NSMutableData *visited = [NSMutableData dataWithLength:_width * _height];
    uint8_t *vis = (uint8_t *)visited.mutableBytes;

    // Collect all bright regions
    NSMutableArray *regions = [NSMutableArray array];

    for (NSInteger y = 0; y < _height; y++) {
        for (NSInteger x = 0; x < _width; x++) {
            if (vis[y * _width + x]) continue;
            uint8_t b = [self brightnessAtX:x y:y];
            if (b < 128) { vis[y * _width + x] = 1; continue; }

            NSMutableArray *stack = [NSMutableArray arrayWithObject:[NSValue valueWithPoint:NSMakePoint(x, y)]];
            CGFloat sumX = 0, sumY = 0;
            NSInteger count = 0;

            while (stack.count > 0) {
                NSPoint pt = ((NSValue *)stack.lastObject).pointValue;
                [stack removeLastObject];
                NSInteger px = (NSInteger)pt.x;
                NSInteger py = (NSInteger)pt.y;
                if (px < 0 || px >= _width || py < 0 || py >= _height) continue;
                if (vis[py * _width + px]) continue;
                if ([self brightnessAtX:px y:py] < 128) continue;

                vis[py * _width + px] = 1;
                sumX += px;
                sumY += py;
                count++;

                [stack addObject:[NSValue valueWithPoint:NSMakePoint(px + 1, py)]];
                [stack addObject:[NSValue valueWithPoint:NSMakePoint(px - 1, py)]];
                [stack addObject:[NSValue valueWithPoint:NSMakePoint(px, py + 1)]];
                [stack addObject:[NSValue valueWithPoint:NSMakePoint(px, py - 1)]];
            }

            if (count > 0) {
                NSPoint center = NSMakePoint(sumX / count, sumY / count);
                [regions addObject:@{@"center": [NSValue valueWithPoint:center], @"size": @(count)}];
            }
        }
    }

    // Sort by size descending
    [regions sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"size"] compare:a[@"size"]];
    }];

    // Add centers that are far enough apart
    for (NSDictionary *region in regions) {
        NSPoint center = [region[@"center"] pointValue];
        BOOL tooClose = NO;
        for (NSValue *existing in centers) {
            NSPoint ep = existing.pointValue;
            CGFloat dist = hypot(center.x - ep.x, center.y - ep.y);
            if (dist < minSeparation) {
                tooClose = YES;
                break;
            }
        }
        if (!tooClose) {
            [centers addObject:[NSValue valueWithPoint:center]];
        }
    }

    return centers;
}

@end

#pragma mark - XLVideoModelGenerator

@interface XLVideoModelGenerator ()

@property (nonatomic, strong) AVAsset *asset;
@property (nonatomic, strong) AVAssetImageGenerator *imageGenerator;
@property (nonatomic, strong) NSMutableArray<XLProcessedFrame *> *rawFrames;
@property (nonatomic, strong) NSMutableArray<XLProcessedFrame *> *processedFrames;
@property (nonatomic, strong) XLProcessedFrame *offFrame;       // background/dark frame
@property (nonatomic, strong) XLProcessedFrame *startFrame1;    // first all-on flash
@property (nonatomic, strong) XLProcessedFrame *startFrame2;    // second all-on flash
@property (nonatomic, strong) XLProcessedFrame *firstFrame;     // very first frame of video
@property (nonatomic, strong) NSMutableArray<XLDetectedNode *> *mutableDetectedNodes;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL internalStartDetected;
@property (nonatomic, strong) NSImage *internalFirstFrameImage;
@property (nonatomic, strong) NSImage *internalStartFrameImage;

@end

@implementation XLVideoModelGenerator

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = XLVideoGenStateChooseVideo;
        _expectedNodeCount = 100;
        _isSteadyCamera = YES;
        _blur = 1;
        _sensitivity = 128;
        _contrast = 0;
        _gamma = 1.0;
        _saturation = 50;
        _minSeparation = 5;
        _despeckle = 2;
        _cropRect = NSMakeRect(0, 0, 1, 1);
        _rawFrames = [NSMutableArray array];
        _processedFrames = [NSMutableArray array];
        _mutableDetectedNodes = [NSMutableArray array];
    }
    return self;
}

- (NSArray<XLDetectedNode *> *)detectedNodes { return [_mutableDetectedNodes copy]; }
- (BOOL)startFrameDetected { return _internalStartDetected; }
- (NSImage *)firstFrameImage { return _internalFirstFrameImage; }
- (NSImage *)startFrameImage { return _internalStartFrameImage; }

#pragma mark - Base-3 Encoding (matches legacy algorithm)

/// Number of base-3 digits needed to encode numPixels unique values
- (NSInteger)bitsForPixelCount:(NSInteger)numPixels {
    NSInteger count = 0;
    NSInteger p = numPixels;
    while (p > 0) {
        p = p / 3;
        count++;
    }
    return count + 2; // +2 for check digits
}

/// Convert a pixel number to base-3 string with check digits (matches legacy)
- (NSString *)convertToBase3:(NSInteger)number minDigits:(NSInteger)minDigits {
    NSMutableString *res = [NSMutableString string];
    NSInteger total = 0;
    NSInteger n = number;

    while (n > 0) {
        NSInteger r = n % 3;
        [res insertString:[NSString stringWithFormat:@"%ld", (long)r] atIndex:0];
        total += r;
        n = n / 3;
    }

    NSInteger check = 2 - (total % 3);
    [res appendString:[NSString stringWithFormat:@"%ld", (long)check]];
    check = (check + 1) % 3;
    [res appendString:[NSString stringWithFormat:@"%ld", (long)check]];

    while ((NSInteger)res.length < minDigits) {
        [res insertString:@"0" atIndex:0];
    }

    return res;
}

#pragma mark - Video Loading

- (BOOL)loadVideoFromURL:(NSURL *)url error:(NSError **)error {
    [self reset];

    _videoURL = url;
    _asset = [AVAsset assetWithURL:url];

    if (!_asset) {
        if (error) *error = [NSError errorWithDomain:@"XLVideoModelGenerator"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to load video asset"}];
        return NO;
    }

    // Get video track info
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<AVAssetTrack *> *videoTracks = [_asset tracksWithMediaType:AVMediaTypeVideo];
#pragma clang diagnostic pop
    if (videoTracks.count == 0) {
        if (error) *error = [NSError errorWithDomain:@"XLVideoModelGenerator"
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"No video track found in file"}];
        return NO;
    }

    AVAssetTrack *track = videoTracks.firstObject;
    _videoDuration = CMTimeGetSeconds(_asset.duration);
    _videoFrameRate = track.nominalFrameRate;
    _videoDimensions = track.naturalSize;

    // Set up image generator
    _imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:_asset];
    _imageGenerator.appliesPreferredTrackTransform = YES;
    _imageGenerator.requestedTimeToleranceBefore = CMTimeMake(1, 100);
    _imageGenerator.requestedTimeToleranceAfter = CMTimeMake(1, 100);

    // Extract first frame
    NSImage *firstImage = [self frameAtTime:0];
    if (firstImage) {
        _internalFirstFrameImage = firstImage;
    }

    _state = XLVideoGenStateChooseVideo;
    return YES;
}

- (nullable NSImage *)frameAtTime:(NSTimeInterval)time {
    if (!_imageGenerator) return nil;

    CMTime requestTime = CMTimeMakeWithSeconds(time, 600);
    CMTime actualTime;
    NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGImageRef cgImage = [_imageGenerator copyCGImageAtTime:requestTime actualTime:&actualTime error:&error];
#pragma clang diagnostic pop
    if (!cgImage) return nil;

    NSSize size = NSMakeSize(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
    NSImage *image = [[NSImage alloc] initWithCGImage:cgImage size:size];
    CGImageRelease(cgImage);
    return image;
}

- (nullable XLProcessedFrame *)processedFrameAtTime:(NSTimeInterval)time {
    if (!_imageGenerator) return nil;

    CMTime requestTime = CMTimeMakeWithSeconds(time, 600);
    CMTime actualTime;
    NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGImageRef cgImage = [_imageGenerator copyCGImageAtTime:requestTime actualTime:&actualTime error:&error];
#pragma clang diagnostic pop
    if (!cgImage) return nil;

    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    CGImageRelease(cgImage);

    return [[XLProcessedFrame alloc] initWithBitmap:bitmap timestamp:CMTimeGetSeconds(actualTime)];
}

#pragma mark - Start Frame Detection

- (BOOL)findStartFrame {
    if (!_imageGenerator) return NO;

    _state = XLVideoGenStateFindingStart;
    _cancelled = NO;

    if (_statusCallback) _statusCallback(@"Scanning for start flash pattern...");

    // Read frames from the first kStartScanDuration seconds
    NSMutableArray<XLProcessedFrame *> *scanFrames = [NSMutableArray array];
    NSTimeInterval scanEnd = MIN(kStartScanDuration, _videoDuration);

    for (NSTimeInterval t = 0; t < scanEnd && !_cancelled; t += kFrameInterval) {
        XLProcessedFrame *frame = [self processedFrameAtTime:t];
        if (frame) {
            [scanFrames addObject:frame];
        }

        if (_progressCallback) {
            _progressCallback((float)(t * 0.7) / (float)scanEnd);
        }
    }

    if (_cancelled || scanFrames.count < 4) return NO;

    // Compute frame deltas (brightness change between consecutive frames)
    NSMutableArray *frameDeltas = [NSMutableArray array];
    for (NSInteger i = 2; i < (NSInteger)scanFrames.count; i++) {
        NSInteger delta = [scanFrames[i] frameDeltaFrom:scanFrames[i - 2]];
        [frameDeltas addObject:@{
            @"frame": scanFrames[i],
            @"delta": @(delta),
            @"index": @(i)
        }];

        if (_progressCallback) {
            _progressCallback(0.7f + (0.2f * (float)i / (float)scanFrames.count));
        }
    }

    // Sort by absolute delta (largest brightness changes first)
    [frameDeltas sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [@(labs([b[@"delta"] integerValue])) compare:@(labs([a[@"delta"] integerValue]))];
    }];

    // Find candidate start flashes: pairs of large deltas with correct timing
    NSMutableArray<XLProcessedFrame *> *candidates = [NSMutableArray array];

    NSInteger searchLimit = MIN(20, (NSInteger)frameDeltas.count);
    for (NSInteger j = 0; j < searchLimit && !_cancelled; j++) {
        NSDictionary *entry1 = frameDeltas[j];
        NSInteger delta1 = [entry1[@"delta"] integerValue];
        XLProcessedFrame *f1 = entry1[@"frame"];

        for (NSInteger i = j + 1; i < searchLimit; i++) {
            NSDictionary *entry2 = frameDeltas[i];
            NSInteger delta2 = [entry2[@"delta"] integerValue];
            XLProcessedFrame *f2 = entry2[@"frame"];

            // Two signs must be different, separation must match flag-on duration
            NSTimeInterval timeDiff = fabs(f1.timestamp - f2.timestamp);
            NSTimeInterval expectedDiff = kFlagOn;

            if ((delta1 > 0) != (delta2 > 0) && fabs(timeDiff - expectedDiff) <= kFrameInterval) {
                XLProcessedFrame *candidate = (f1.timestamp < f2.timestamp) ? f1 : f2;
                // Must be brightness increase
                NSInteger candDelta = (candidate == f1) ? delta1 : delta2;
                if (candDelta > 0) {
                    BOOL duplicate = NO;
                    for (XLProcessedFrame *existing in candidates) {
                        if (fabs(existing.timestamp - candidate.timestamp) < 0.15) {
                            duplicate = YES;
                            break;
                        }
                    }
                    if (!duplicate) {
                        [candidates addObject:candidate];
                    }
                }
            }
        }
    }

    if (candidates.count < 2) {
        if (_statusCallback) _statusCallback(@"Could not find start flash pattern in video");
        return NO;
    }

    // Sort candidates by timestamp
    [candidates sortUsingComparator:^NSComparisonResult(XLProcessedFrame *a, XLProcessedFrame *b) {
        return [@(a.timestamp) compare:@(b.timestamp)];
    }];

    // Validate: first two candidates should be separated by FlagOn + FlagOff
    NSTimeInterval separation = candidates[1].timestamp - candidates[0].timestamp;
    NSTimeInterval expected = kFlagOn + kFlagOff;
    if (fabs(separation - expected) > kFrameInterval) {
        if (_statusCallback) _statusCallback(@"Flash pattern timing did not match expected protocol");
        return NO;
    }

    // Find the actual sample frames (offset by delay into flash)
    XLProcessedFrame *actualStart1 = nil;
    XLProcessedFrame *actualStart2 = nil;
    XLProcessedFrame *blankFrame = nil;
    NSTimeInterval blankTime = candidates[0].timestamp + kFlagOn + kFlagOff / 2.0;

    for (XLProcessedFrame *f in scanFrames) {
        if (!actualStart1 && f.timestamp >= candidates[0].timestamp + kDelaySample) {
            actualStart1 = f;
        }
        if (!actualStart2 && f.timestamp >= candidates[1].timestamp + kDelaySample) {
            actualStart2 = f;
        }
        if (!blankFrame && f.timestamp >= blankTime) {
            blankFrame = f;
        }
    }

    if (!actualStart1 || !actualStart2 || !blankFrame) {
        if (_statusCallback) _statusCallback(@"Could not extract key frames from flash pattern");
        return NO;
    }

    _startFrame1 = actualStart1;
    _startFrame2 = actualStart2;
    _offFrame = blankFrame;
    _startFrameTime = actualStart1.timestamp;
    _internalStartDetected = YES;

    // Create start frame preview image
    NSImage *startImg = [[NSImage alloc] initWithSize:NSMakeSize(actualStart1.width, actualStart1.height)];
    [startImg addRepresentation:actualStart1.bitmap];
    _internalStartFrameImage = startImg;

    if (_statusCallback) {
        _statusCallback([NSString stringWithFormat:@"Start frame found at %.2fs", _startFrameTime]);
    }

    if (_progressCallback) _progressCallback(1.0);
    return YES;
}

- (void)setManualStartTime:(NSTimeInterval)time {
    _startFrameTime = time;

    // Extract frames at the expected positions
    _startFrame1 = [self processedFrameAtTime:time + kDelaySample];
    _startFrame2 = [self processedFrameAtTime:time + kFlagOn + kFlagOff + kDelaySample];
    _offFrame = [self processedFrameAtTime:time + kFlagOn + kFlagOff / 2.0];

    if (_startFrame1) {
        NSImage *startImg = [[NSImage alloc] initWithSize:NSMakeSize(_startFrame1.width, _startFrame1.height)];
        [startImg addRepresentation:_startFrame1.bitmap];
        _internalStartFrameImage = startImg;
        _internalStartDetected = YES;
    }
}

#pragma mark - Frame Reading

- (BOOL)readNodeFrames {
    if (!_startFrame1) return NO;

    _state = XLVideoGenStateReadingFrames;
    _cancelled = NO;

    NSInteger framesToRead = [self bitsForPixelCount:_expectedNodeCount];
    NSTimeInterval firstNodeTime = _startFrameTime + kFlagOn + kFlagOff + kFlagOn + kFlagOff;

    [_rawFrames removeAllObjects];

    if (_statusCallback) {
        _statusCallback([NSString stringWithFormat:@"Reading %ld encoded frames...", (long)framesToRead]);
    }

    for (NSInteger i = 0; i < framesToRead && !_cancelled; i++) {
        NSTimeInterval frameTime = firstNodeTime + i * kNodeOn + kDelaySample;
        XLProcessedFrame *frame = [self processedFrameAtTime:frameTime];

        if (frame) {
            [_rawFrames addObject:frame];

            if (_frameDisplayCallback) {
                NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(frame.width, frame.height)];
                [img addRepresentation:frame.bitmap];
                _frameDisplayCallback(img);
            }
        }

        if (_progressCallback) {
            _progressCallback((float)(i + 1) / (float)framesToRead);
        }
    }

    if (_cancelled) return NO;

    // Subtract background if camera is steady
    if (_isSteadyCamera && _offFrame) {
        if (_statusCallback) _statusCallback(@"Removing background...");
        NSMutableArray<XLProcessedFrame *> *adjusted = [NSMutableArray array];
        for (XLProcessedFrame *frame in _rawFrames) {
            [adjusted addObject:[frame subtractBackground:_offFrame scale:0.8]];
        }
        [_rawFrames setArray:adjusted];
    }

    if (_statusCallback) {
        _statusCallback([NSString stringWithFormat:@"Read %ld frames", (long)_rawFrames.count]);
    }

    return _rawFrames.count == (NSUInteger)framesToRead;
}

#pragma mark - Bulb Identification

- (NSInteger)identifyNodes {
    if (_rawFrames.count == 0) return 0;

    _state = XLVideoGenStateIdentifyingBulbs;
    _cancelled = NO;
    [_mutableDetectedNodes removeAllObjects];

    if (_statusCallback) _statusCallback(@"Processing frames...");

    // Apply image processing to all frames
    [_processedFrames removeAllObjects];
    for (XLProcessedFrame *raw in _rawFrames) {
        // Create a working copy
        XLProcessedFrame *processed = [[XLProcessedFrame alloc] initWithBitmap:
            [[NSBitmapImageRep alloc] initWithData:[raw.bitmap TIFFRepresentation]]
                                         timestamp:raw.timestamp];

        // Apply crop
        // (crop is applied during pixel lookup, not modifying frames)

        // Apply contrast
        [processed applyContrast:_contrast];

        // Apply blur
        [processed applyBlur:_blur];

        // Apply gamma
        [processed applyGamma:_gamma];

        [_processedFrames addObject:processed];
    }

    if (_statusCallback) _statusCallback(@"Identifying nodes using base-3 encoding...");

    NSInteger bits = [self bitsForPixelCount:_expectedNodeCount];
    NSMutableDictionary<NSString *, XLProcessedFrame *> *cache = [NSMutableDictionary dictionary];

    NSInteger found = 0;
    for (NSInteger pixel = 1; pixel <= _expectedNodeCount && !_cancelled; pixel++) {
        NSString *base3 = [self convertToBase3:pixel minDigits:bits];

        XLProcessedFrame *combined = nil;
        NSInteger startAt = 0;

        // Check cache for partial results
        for (NSInteger len = bits - 1; len > 1; len--) {
            NSString *key = [base3 substringToIndex:len];
            XLProcessedFrame *cached = cache[key];
            if (cached) {
                // Make a copy
                combined = [[XLProcessedFrame alloc] initWithBitmap:
                    [[NSBitmapImageRep alloc] initWithData:[cached.bitmap TIFFRepresentation]]
                                                         timestamp:0];
                startAt = len;
                break;
            }
        }

        // Combine channel images for each digit
        for (NSInteger i = startAt; i < bits && i < (NSInteger)_processedFrames.count && !_cancelled; i++) {
            NSInteger digit = [base3 characterAtIndex:i] - '0';
            XLProcessedFrame *channelFrame = [_processedFrames[i] channelImage:digit];

            if (!combined) {
                combined = channelFrame;
            } else {
                [combined applyMinWith:channelFrame];
            }

            // Cache intermediate results
            NSString *cacheKey = [base3 substringToIndex:i + 1];
            if (!cache[cacheKey]) {
                cache[cacheKey] = [[XLProcessedFrame alloc] initWithBitmap:
                    [[NSBitmapImageRep alloc] initWithData:[combined.bitmap TIFFRepresentation]]
                                                             timestamp:0];
            }
        }

        if (combined) {
            // Apply threshold and despeckle
            [combined applyThreshold:(uint8_t)_sensitivity];

            // Find the brightest region center
            NSPoint location = [combined findBrightestRegionCenter];

            if (location.x >= 0 && location.y >= 0) {
                // Check if within crop bounds
                BOOL inCrop = YES;
                if (!NSIsEmptyRect(_cropRect) && !NSEqualRects(_cropRect, NSMakeRect(0, 0, 1, 1))) {
                    CGFloat nx = location.x / combined.width;
                    CGFloat ny = location.y / combined.height;
                    inCrop = NSPointInRect(NSMakePoint(nx, ny), _cropRect);
                }

                if (inCrop) {
                    [_mutableDetectedNodes addObject:[XLDetectedNode nodeWithLocation:location number:pixel]];
                    found++;
                }
            }
        }

        if (_progressCallback) {
            _progressCallback((float)pixel / (float)_expectedNodeCount);
        }
    }

    _state = XLVideoGenStateReviewModel;

    if (_statusCallback) {
        _statusCallback([NSString stringWithFormat:@"Found %ld of %ld nodes", (long)found, (long)_expectedNodeCount]);
    }

    return found;
}

#pragma mark - Model Data Generation

- (NSRect)detectedNodesBounds {
    if (_mutableDetectedNodes.count == 0) return NSZeroRect;

    CGFloat minX = CGFLOAT_MAX, minY = CGFLOAT_MAX;
    CGFloat maxX = -CGFLOAT_MAX, maxY = -CGFLOAT_MAX;

    for (XLDetectedNode *node in _mutableDetectedNodes) {
        minX = MIN(minX, node.location.x);
        minY = MIN(minY, node.location.y);
        maxX = MAX(maxX, node.location.x);
        maxY = MAX(maxY, node.location.y);
    }

    return NSMakeRect(minX, minY, maxX - minX, maxY - minY);
}

- (nullable NSString *)generateModelData {
    NSRect bounds = [self detectedNodesBounds];
    if (NSIsEmptyRect(bounds)) return nil;

    // Add padding and compute grid size
    NSInteger gridWidth = (NSInteger)(bounds.size.width / MAX(1, _minSeparation)) + 1 + kMatrixFudge;
    NSInteger gridHeight = (NSInteger)(bounds.size.height / MAX(1, _minSeparation)) + 1 + kMatrixFudge;

    return [self generateModelDataWithWidth:gridWidth height:gridHeight];
}

- (nullable NSString *)generateModelDataWithWidth:(NSInteger)width height:(NSInteger)height {
    if (_mutableDetectedNodes.count == 0 || width <= 0 || height <= 0) return nil;

    NSRect bounds = [self detectedNodesBounds];
    if (NSIsEmptyRect(bounds)) return nil;

    // Create grid
    int *grid = (int *)calloc(width * height, sizeof(int));

    // Map detected nodes to grid positions
    CGFloat scaleX = (width - kMatrixFudge - 1) / MAX(1, bounds.size.width);
    CGFloat scaleY = (height - kMatrixFudge - 1) / MAX(1, bounds.size.height);
    NSInteger offsetX = kMatrixFudge / 2;
    NSInteger offsetY = kMatrixFudge / 2;

    for (XLDetectedNode *node in _mutableDetectedNodes) {
        NSInteger gx = (NSInteger)((node.location.x - bounds.origin.x) * scaleX) + offsetX;
        NSInteger gy = (NSInteger)((node.location.y - bounds.origin.y) * scaleY) + offsetY;

        gx = MAX(0, MIN(width - 1, gx));
        gy = MAX(0, MIN(height - 1, gy));

        // Handle collision: find nearest empty cell
        if (grid[gy * width + gx] != 0) {
            BOOL placed = NO;
            for (NSInteger radius = 1; radius < MAX(width, height) && !placed; radius++) {
                for (NSInteger dy = -radius; dy <= radius && !placed; dy++) {
                    for (NSInteger dx = -radius; dx <= radius && !placed; dx++) {
                        if (abs((int)dx) != radius && abs((int)dy) != radius) continue;
                        NSInteger nx = gx + dx;
                        NSInteger ny = gy + dy;
                        if (nx >= 0 && nx < width && ny >= 0 && ny < height && grid[ny * width + nx] == 0) {
                            gx = nx;
                            gy = ny;
                            placed = YES;
                        }
                    }
                }
            }
        }

        grid[gy * width + gx] = (int)node.nodeNumber;
    }

    // Convert grid to custom model data string
    NSMutableString *result = [NSMutableString string];
    for (NSInteger y = 0; y < height; y++) {
        NSMutableArray *rowCells = [NSMutableArray array];
        for (NSInteger x = 0; x < width; x++) {
            int num = grid[y * width + x];
            [rowCells addObject:(num > 0) ? [NSString stringWithFormat:@"%d", num] : @""];
        }
        [result appendString:[rowCells componentsJoinedByString:@","]];
        if (y < height - 1) [result appendString:@";"];
    }

    free(grid);
    return result;
}

- (NSDictionary<NSString *, id> *)detectionStatistics {
    NSRect bounds = [self detectedNodesBounds];
    NSInteger missing = _expectedNodeCount - (NSInteger)_mutableDetectedNodes.count;

    NSMutableString *missingNodes = [NSMutableString string];
    NSMutableSet<NSNumber *> *foundSet = [NSMutableSet set];
    for (XLDetectedNode *node in _mutableDetectedNodes) {
        [foundSet addObject:@(node.nodeNumber)];
    }
    for (NSInteger i = 1; i <= _expectedNodeCount; i++) {
        if (![foundSet containsObject:@(i)]) {
            if (missingNodes.length > 0) [missingNodes appendString:@", "];
            [missingNodes appendFormat:@"%ld", (long)i];
        }
    }

    return @{
        @"totalExpected": @(_expectedNodeCount),
        @"totalFound": @(_mutableDetectedNodes.count),
        @"totalMissing": @(missing),
        @"missingNodes": missingNodes.length > 0 ? missingNodes : @"(none)",
        @"boundsWidth": @(bounds.size.width),
        @"boundsHeight": @(bounds.size.height),
    };
}

- (nullable NSImage *)detectionPreviewImage {
    if (_mutableDetectedNodes.count == 0) return nil;

    NSRect bounds = [self detectedNodesBounds];
    CGFloat padding = 20;
    CGFloat imgWidth = bounds.size.width + padding * 2;
    CGFloat imgHeight = bounds.size.height + padding * 2;

    // Scale to reasonable preview size
    CGFloat maxPreviewSize = 500.0;
    CGFloat scale = MIN(maxPreviewSize / imgWidth, maxPreviewSize / imgHeight);
    if (scale > 1.0) scale = 1.0;

    CGFloat drawWidth = imgWidth * scale;
    CGFloat drawHeight = imgHeight * scale;

    NSImage *preview = [[NSImage alloc] initWithSize:NSMakeSize(drawWidth, drawHeight)];
    [preview lockFocus];

    // Background
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(NSMakeRect(0, 0, drawWidth, drawHeight));

    // Draw lines connecting sequential nodes
    [[NSColor colorWithCalibratedRed:1.0 green:1.0 blue:0.0 alpha:0.4] setStroke];
    NSBezierPath *linePath = [NSBezierPath bezierPath];
    linePath.lineWidth = 0.5;

    NSArray<XLDetectedNode *> *sorted = [_mutableDetectedNodes sortedArrayUsingComparator:
        ^NSComparisonResult(XLDetectedNode *a, XLDetectedNode *b) {
            return [@(a.nodeNumber) compare:@(b.nodeNumber)];
        }];

    for (NSInteger i = 0; i < (NSInteger)sorted.count - 1; i++) {
        CGFloat x1 = (sorted[i].location.x - bounds.origin.x + padding) * scale;
        CGFloat y1 = drawHeight - (sorted[i].location.y - bounds.origin.y + padding) * scale;
        CGFloat x2 = (sorted[i+1].location.x - bounds.origin.x + padding) * scale;
        CGFloat y2 = drawHeight - (sorted[i+1].location.y - bounds.origin.y + padding) * scale;
        [linePath moveToPoint:NSMakePoint(x1, y1)];
        [linePath lineToPoint:NSMakePoint(x2, y2)];
    }
    [linePath stroke];

    // Draw nodes
    for (XLDetectedNode *node in _mutableDetectedNodes) {
        CGFloat x = (node.location.x - bounds.origin.x + padding) * scale;
        CGFloat y = drawHeight - (node.location.y - bounds.origin.y + padding) * scale;

        // Draw dot
        [[NSColor controlAccentColor] setFill];
        NSRect dotRect = NSMakeRect(x - 3, y - 3, 6, 6);
        [[NSBezierPath bezierPathWithOvalInRect:dotRect] fill];

        // Draw node number for small models
        if (_mutableDetectedNodes.count <= 200 && scale >= 0.3) {
            NSString *label = [NSString stringWithFormat:@"%ld", (long)node.nodeNumber];
            NSDictionary *attrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:MAX(7, 9 * scale)],
                NSForegroundColorAttributeName: [NSColor labelColor]
            };
            [label drawAtPoint:NSMakePoint(x + 4, y - 4) withAttributes:attrs];
        }
    }

    [preview unlockFocus];
    return preview;
}

- (void)cancel {
    _cancelled = YES;
}

- (void)reset {
    _cancelled = YES;
    [_rawFrames removeAllObjects];
    [_processedFrames removeAllObjects];
    [_mutableDetectedNodes removeAllObjects];
    _offFrame = nil;
    _startFrame1 = nil;
    _startFrame2 = nil;
    _firstFrame = nil;
    _internalStartDetected = NO;
    _internalFirstFrameImage = nil;
    _internalStartFrameImage = nil;
    _state = XLVideoGenStateChooseVideo;
    _asset = nil;
    _imageGenerator = nil;
    _videoURL = nil;
}

@end
