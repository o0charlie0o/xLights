/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLTimelineRulerView.h"
#import "../XLSongRegionEditPopover.h"

static const CGFloat kRulerHeight = 28.0;
static const CGFloat kPlayheadTriangleSize = 8.0;
static const CGFloat kMajorTickHeight = 12.0;
static const CGFloat kMinorTickHeight = 6.0;
static const CGFloat kMinPixelsBetweenLabels = 80.0;
static const CGFloat kDefaultZoomLevel = 0.1; // pixels per ms
static const CGFloat kMinZoomLevel = 0.001;
static const CGFloat kMaxZoomLevel = 10.0;

// Timing mark constants
static const CGFloat kTimingMarkTriangleSize = 5.0;
static const CGFloat kTimingMarkHitTestWidth = 8.0;
static const CGFloat kTimingMarkR = 0.3, kTimingMarkG = 0.7, kTimingMarkB = 1.0;
static const CGFloat kTimingMarkSelectedR = 1.0, kTimingMarkSelectedG = 0.5, kTimingMarkSelectedB = 0.0;

// Song region constants
static const CGFloat kBoundaryHitTestWidth = 5.0;
static const CGFloat kBoundaryHandleWidth = 2.0;
static const CGFloat kRegionNameFontSize = 8.0;
static const CGFloat kRegionBandTop = 0.0;

// Color constants as raw RGBA values to avoid NSColor object lifetime issues
// with static variables in CALayerDelegate callbacks
static const CGFloat kBgR = 0.118, kBgG = 0.118, kBgB = 0.118;
static const CGFloat kTickGray = 0.55;
static const CGFloat kPlayheadR = 0.2, kPlayheadG = 0.5, kPlayheadB = 1.0;

@interface XLTimelineRulerView ()

@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, strong) CALayer *playheadLayer;
@property (nonatomic, strong) CALayer *timingMarksLayer;
@property (nonatomic, strong) CALayer *songRegionsLayer;
@property (nonatomic, strong) NSTimer *playheadTimer;
@property (nonatomic, assign) CFTimeInterval lastDisplayLinkTimestamp;

// For smooth playhead interpolation during playback
@property (nonatomic, assign) NSTimeInterval lastSyncedPosition;
@property (nonatomic, assign) CFAbsoluteTime lastSyncTime;

// Timing mark dragging state
@property (nonatomic, assign) BOOL draggingTimingMark;
@property (nonatomic, assign) NSInteger draggingTimingMarkId;
@property (nonatomic, assign) CGFloat dragStartTimeMS;

// Song region boundary dragging state
@property (nonatomic, assign) BOOL draggingBoundary;
@property (nonatomic, assign) NSInteger draggingBoundaryIndex;

// Right-click context position (ms)
@property (nonatomic, assign) NSInteger rightClickPositionMS;

@end

// Timing tag storage (10 slots, C array for direct access)
static const NSInteger kTimingTagCount = 10;

@implementation XLTimelineRulerView {
    NSInteger _timingTags[10];  // -1 = unset
    XLSongRegion *_songRegionStorage;
    NSInteger _songRegionStorageCount;
}

@synthesize songRegions = _songRegionStorage;
@synthesize songRegionCount = _songRegionStorageCount;

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
    _zoomLevel = kDefaultZoomLevel;
    _scrollOffset = 0.0;
    _sequenceDuration = 0.0;
    _playbackPosition = 0.0;
    _playbackRate = 1.0;
    _frameRate = 20;
    _playing = NO;
    _dragging = NO;
    _lastSyncedPosition = 0.0;
    _lastSyncTime = 0;

    // Timing marks
    _timingMarks = @[];
    _timingMarksEditable = YES;
    _selectedTimingMarkId = -1;
    _draggingTimingMark = NO;
    _draggingTimingMarkId = -1;

    // Song regions
    _songRegionStorage = NULL;
    _songRegionStorageCount = 0;
    _selectedSongRegionId = -1;
    _draggingBoundary = NO;
    _draggingBoundaryIndex = -1;

    // Timing tags (bookmarks)
    for (NSInteger i = 0; i < kTimingTagCount; i++) {
        _timingTags[i] = -1;
    }
    _rightClickPositionMS = 0;

    [self setupPlayheadLayer];
    [self setupTimingMarksLayer];
    [self setupSongRegionsLayer];
}

- (void)dealloc {
    [self stopDisplayLink];
    if (_songRegionStorage) {
        free(_songRegionStorage);
        _songRegionStorage = NULL;
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
    return layer;
}

- (void)updateLayer {
    [self.layer setNeedsDisplay];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    CGFloat scale = self.window.backingScaleFactor ?: 1.0;
    self.layer.contentsScale = scale;
    _playheadLayer.contentsScale = scale;
    _timingMarksLayer.contentsScale = scale;
    _songRegionsLayer.contentsScale = scale;
    [self.layer setNeedsDisplay];
    [_timingMarksLayer setNeedsDisplay];
    [_songRegionsLayer setNeedsDisplay];
}

#pragma mark - Playhead Layer

- (void)setupPlayheadLayer {
    _playheadLayer = [CALayer layer];
    _playheadLayer.zPosition = 100;
    [self.layer addSublayer:_playheadLayer];
    [self updatePlayheadPosition];
}

- (void)setupTimingMarksLayer {
    _timingMarksLayer = [CALayer layer];
    _timingMarksLayer.zPosition = 60;  // Above song regions, below playhead
    _timingMarksLayer.delegate = self;
    _timingMarksLayer.needsDisplayOnBoundsChange = YES;
    [self.layer addSublayer:_timingMarksLayer];
}

- (void)setupSongRegionsLayer {
    _songRegionsLayer = [CALayer layer];
    _songRegionsLayer.zPosition = 50;  // Below timing marks and playhead
    _songRegionsLayer.delegate = self;
    _songRegionsLayer.needsDisplayOnBoundsChange = YES;
    [self.layer addSublayer:_songRegionsLayer];
}

- (void)updateTimingMarksLayer {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _timingMarksLayer.frame = self.bounds;
    CGFloat scale = self.window.backingScaleFactor ?: 1.0;
    _timingMarksLayer.contentsScale = scale;
    [_timingMarksLayer setNeedsDisplay];
    [CATransaction commit];
}

- (void)updateSongRegionsLayer {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _songRegionsLayer.frame = self.bounds;
    CGFloat scale = self.window.backingScaleFactor ?: 1.0;
    _songRegionsLayer.contentsScale = scale;
    [_songRegionsLayer setNeedsDisplay];
    [CATransaction commit];
}

- (void)updatePlayheadPosition {
    CGFloat x = [self pointForTime:_playbackPosition];
    CGFloat height = NSHeight(self.bounds);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    CGFloat triangleWidth = kPlayheadTriangleSize * 2;
    _playheadLayer.frame = CGRectMake(x - kPlayheadTriangleSize, 0,
                                       triangleWidth, height);
    [_playheadLayer setNeedsDisplay];

    [CATransaction commit];
}

- (void)drawPlayheadInContext:(CGContextRef)ctx bounds:(CGRect)bounds {
    CGFloat midX = CGRectGetMidX(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    CGContextSetRGBFillColor(ctx, kPlayheadR, kPlayheadG, kPlayheadB, 1.0);
    CGContextSetRGBStrokeColor(ctx, kPlayheadR, kPlayheadG, kPlayheadB, 1.0);

    // Triangle at top
    CGFloat triSize = kPlayheadTriangleSize;
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, midX - triSize, 0);
    CGContextAddLineToPoint(ctx, midX + triSize, 0);
    CGContextAddLineToPoint(ctx, midX, triSize);
    CGContextClosePath(ctx);
    CGContextFillPath(ctx);

    // Vertical line
    CGContextSetLineWidth(ctx, 1.0);
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, midX, triSize);
    CGContextAddLineToPoint(ctx, midX, height);
    CGContextStrokePath(ctx);
}

- (void)drawTimingMarksInContext:(CGContextRef)ctx bounds:(CGRect)bounds {
    if (_timingMarks.count == 0) return;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    // Text attributes for labels
    NSDictionary *labelAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:8.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };

    for (NSDictionary *mark in _timingMarks) {
        NSNumber *markIdNum = mark[@"id"];
        NSNumber *startTimeMSNum = mark[@"startTimeMS"];
        NSString *label = mark[@"label"];

        if (!markIdNum || !startTimeMSNum) continue;

        NSInteger markId = markIdNum.integerValue;
        NSTimeInterval time = startTimeMSNum.doubleValue / 1000.0;
        CGFloat x = [self pointForTime:time];

        // Skip if off-screen
        if (x < -kTimingMarkHitTestWidth || x > width + kTimingMarkHitTestWidth) continue;

        BOOL isSelected = (markId == _selectedTimingMarkId);

        // Set color based on selection
        if (isSelected) {
            CGContextSetRGBFillColor(ctx, kTimingMarkSelectedR, kTimingMarkSelectedG, kTimingMarkSelectedB, 1.0);
            CGContextSetRGBStrokeColor(ctx, kTimingMarkSelectedR, kTimingMarkSelectedG, kTimingMarkSelectedB, 1.0);
        } else {
            CGContextSetRGBFillColor(ctx, kTimingMarkR, kTimingMarkG, kTimingMarkB, 1.0);
            CGContextSetRGBStrokeColor(ctx, kTimingMarkR, kTimingMarkG, kTimingMarkB, 1.0);
        }

        // Draw inverted triangle at bottom (pointing up)
        CGFloat triSize = kTimingMarkTriangleSize;
        CGFloat triTop = height - triSize;
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, x - triSize, height);
        CGContextAddLineToPoint(ctx, x + triSize, height);
        CGContextAddLineToPoint(ctx, x, triTop);
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);

        // Draw vertical line extending up
        CGContextSetLineWidth(ctx, 1.0);
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, x, triTop);
        CGContextAddLineToPoint(ctx, x, 0);
        CGContextStrokePath(ctx);

        // Draw label if present
        if (label.length > 0) {
            NSSize labelSize = [label sizeWithAttributes:labelAttrs];
            CGFloat labelX = x + 3.0;
            CGFloat labelY = height - triSize - labelSize.height - 2.0;

            // Clamp to view bounds
            if (labelX + labelSize.width > width - 2.0) {
                labelX = x - labelSize.width - 3.0;
            }
            if (labelY < 2.0) labelY = 2.0;

            NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:nsCtx];
            [label drawAtPoint:NSMakePoint(labelX, labelY) withAttributes:labelAttrs];
            [NSGraphicsContext restoreGraphicsState];
        }
    }
}

#pragma mark - Song Region Drawing

- (void)drawSongRegionsInContext:(CGContextRef)ctx bounds:(CGRect)bounds {
    if (_songRegionStorageCount == 0 || !_songRegionStorage) return;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    NSDictionary *nameAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:kRegionNameFontSize weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:1.0 alpha:0.85],
    };

    for (NSInteger i = 0; i < _songRegionStorageCount; i++) {
        XLSongRegion *region = &_songRegionStorage[i];

        CGFloat x0 = [self pointForTime:region->startTimeMS / 1000.0];
        CGFloat x1 = [self pointForTime:region->endTimeMS / 1000.0];

        // Clip to visible area
        if (x1 < 0 || x0 > width) continue;
        if (x0 < 0) x0 = 0;
        if (x1 > width) x1 = width;

        CGFloat regionWidth = x1 - x0;
        if (regionWidth < 1) continue;

        // Fill semi-transparent band
        BOOL isSelected = (region->regionId == _selectedSongRegionId);
        CGFloat alpha = isSelected ? region->colorA * 1.8 : region->colorA;
        if (alpha > 1.0) alpha = 1.0;
        CGContextSetRGBFillColor(ctx, region->colorR, region->colorG, region->colorB, alpha);
        CGContextFillRect(ctx, CGRectMake(x0, kRegionBandTop, regionWidth, height));

        // Selected border
        if (isSelected) {
            CGContextSetRGBStrokeColor(ctx, region->colorR, region->colorG, region->colorB, 0.8);
            CGContextSetLineWidth(ctx, 1.0);
            CGContextStrokeRect(ctx, CGRectMake(x0 + 0.5, kRegionBandTop + 0.5, regionWidth - 1.0, height - 1.0));
        }

        // Draw region name (centered, truncated with ellipsis if too wide)
        if (region->name[0] != '\0' && regionWidth > 20) {
            NSString *name = [NSString stringWithUTF8String:region->name];
            NSSize nameSize = [name sizeWithAttributes:nameAttrs];

            // Truncate if needed
            if (nameSize.width > regionWidth - 8) {
                while (name.length > 1) {
                    name = [[name substringToIndex:name.length - 1] stringByAppendingString:@"\u2026"];
                    nameSize = [name sizeWithAttributes:nameAttrs];
                    if (nameSize.width <= regionWidth - 8) break;
                    name = [name substringToIndex:name.length - 2]; // Remove char + ellipsis
                }
            }

            CGFloat nameX = x0 + (regionWidth - nameSize.width) / 2.0;
            CGFloat nameY = (height - nameSize.height) / 2.0;

            NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:nsCtx];
            [name drawAtPoint:NSMakePoint(nameX, nameY) withAttributes:nameAttrs];
            [NSGraphicsContext restoreGraphicsState];
        }

        // Draw boundary handle at the right edge (internal boundaries only)
        if (i < _songRegionStorageCount - 1) {
            CGFloat bx = [self pointForTime:region->endTimeMS / 1000.0];
            if (bx >= 0 && bx <= width) {
                CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.4);
                CGContextFillRect(ctx, CGRectMake(bx - kBoundaryHandleWidth / 2.0, 2, kBoundaryHandleWidth, height - 4));
            }
        }
    }
}

#pragma mark - CALayerDelegate

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
    if (layer == _playheadLayer) {
        [self drawPlayheadInContext:ctx bounds:layer.bounds];
        return;
    }

    if (layer == _timingMarksLayer) {
        [self drawTimingMarksInContext:ctx bounds:layer.bounds];
        return;
    }

    if (layer == _songRegionsLayer) {
        [self drawSongRegionsInContext:ctx bounds:layer.bounds];
        return;
    }

    CGRect bounds = layer.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    // Background
    CGContextSetRGBFillColor(ctx, kBgR, kBgG, kBgB, 1.0);
    CGContextFillRect(ctx, bounds);

    // Bottom border
    CGContextSetGrayStrokeColor(ctx, 0.3, 1.0);
    CGContextSetLineWidth(ctx, 0.5);
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, 0, 0);
    CGContextAddLineToPoint(ctx, width, 0);
    CGContextStrokePath(ctx);

    if (_sequenceDuration <= 0) return;

    // Determine tick interval based on zoom
    NSTimeInterval majorInterval = [self majorTickIntervalForZoom];
    NSTimeInterval minorInterval = majorInterval / 5.0;

    // Time range visible in the view
    NSTimeInterval startTime = [self timeForPoint:0];
    NSTimeInterval endTime = [self timeForPoint:width];

    // Clamp to sequence bounds
    if (startTime < 0) startTime = 0;
    if (endTime > _sequenceDuration) endTime = _sequenceDuration;

    // Draw minor ticks
    CGContextSetGrayStrokeColor(ctx, kTickGray, 0.4);
    CGContextSetLineWidth(ctx, 0.5);

    NSTimeInterval minorStart = floor(startTime / minorInterval) * minorInterval;
    for (NSTimeInterval t = minorStart; t <= endTime; t += minorInterval) {
        if (t < 0) continue;
        CGFloat x = [self pointForTime:t];
        if (x < 0 || x > width) continue;

        // Skip positions that align with major ticks
        double ratio = t / majorInterval;
        if (fabs(ratio - round(ratio)) < 0.001) continue;

        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, x, 0);
        CGContextAddLineToPoint(ctx, x, kMinorTickHeight);
        CGContextStrokePath(ctx);
    }

    // Draw major ticks and labels
    CGContextSetGrayStrokeColor(ctx, kTickGray, 1.0);
    CGContextSetLineWidth(ctx, 1.0);

    NSDictionary *textAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };

    NSTimeInterval majorStart = floor(startTime / majorInterval) * majorInterval;
    for (NSTimeInterval t = majorStart; t <= endTime; t += majorInterval) {
        if (t < 0) continue;
        CGFloat x = [self pointForTime:t];
        if (x < 0 || x > width) continue;

        // Tick line
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, x, 0);
        CGContextAddLineToPoint(ctx, x, kMajorTickHeight);
        CGContextStrokePath(ctx);

        // Label
        NSString *label = [self labelForTime:t];
        NSSize labelSize = [label sizeWithAttributes:textAttrs];
        CGFloat labelX = x - labelSize.width / 2.0;
        CGFloat labelY = kMajorTickHeight + 1.0;

        // Clamp label to view bounds
        if (labelX < 2.0) labelX = 2.0;
        if (labelX + labelSize.width > width - 2.0) labelX = width - 2.0 - labelSize.width;

        NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:nsCtx];
        [label drawAtPoint:NSMakePoint(labelX, labelY) withAttributes:textAttrs];
        [NSGraphicsContext restoreGraphicsState];
    }

    // Sequence end marker
    CGFloat seqEndX = [self pointForTime:_sequenceDuration];
    if (seqEndX >= 0 && seqEndX <= width) {
        CGContextSetGrayFillColor(ctx, 0.3, 0.4);
        CGContextFillRect(ctx, CGRectMake(seqEndX, 0, width - seqEndX, height));
    }

    // Draw preview timing marks (translucent cyan lines)
    if (_previewTimingMarks.count > 0) {
        CGContextSetRGBStrokeColor(ctx, 0.0, 0.9, 1.0, 0.5);
        CGContextSetLineWidth(ctx, 1.0);
        for (NSNumber *timeNum in _previewTimingMarks) {
            CGFloat timeMS = timeNum.doubleValue;
            CGFloat x = (timeMS * _zoomLevel) - _scrollOffset;
            if (x < -1 || x > width + 1) continue;
            CGContextMoveToPoint(ctx, x, 0);
            CGContextAddLineToPoint(ctx, x, height);
        }
        CGContextStrokePath(ctx);
    }
}

#pragma mark - Tick Interval Calculation

- (NSTimeInterval)majorTickIntervalForZoom {
    CGFloat targetIntervalMS = kMinPixelsBetweenLabels / _zoomLevel;

    static const double niceIntervals[] = {
        10, 20, 25, 50, 100, 200, 250, 500,
        1000, 2000, 2500, 5000, 10000, 15000, 30000,
        60000, 120000, 300000, 600000
    };
    static const int niceCount = sizeof(niceIntervals) / sizeof(niceIntervals[0]);

    for (int i = 0; i < niceCount; i++) {
        if (niceIntervals[i] >= targetIntervalMS) {
            return niceIntervals[i] / 1000.0;
        }
    }
    return niceIntervals[niceCount - 1] / 1000.0;
}

#pragma mark - Time Label Formatting

- (NSString *)labelForTime:(NSTimeInterval)time {
    if (time < 0) time = 0;

    int totalMS = (int)(time * 1000.0 + 0.5);
    int minutes = totalMS / 60000;
    int seconds = (totalMS % 60000) / 1000;
    int ms = totalMS % 1000;

    NSTimeInterval majorInterval = [self majorTickIntervalForZoom];

    if (majorInterval < 0.1) {
        if (minutes > 0) {
            return [NSString stringWithFormat:@"%d:%02d.%03d", minutes, seconds, ms];
        }
        return [NSString stringWithFormat:@"%d.%03d", seconds, ms];
    }
    else if (majorInterval < 1.0) {
        if (minutes > 0) {
            return [NSString stringWithFormat:@"%d:%02d.%d", minutes, seconds, ms / 100];
        }
        return [NSString stringWithFormat:@"%d.%d", seconds, ms / 100];
    }
    else if (majorInterval < 60.0) {
        if (minutes > 0) {
            return [NSString stringWithFormat:@"%d:%02d", minutes, seconds];
        }
        return [NSString stringWithFormat:@"%ds", seconds];
    }
    else {
        return [NSString stringWithFormat:@"%dm", minutes];
    }
}

#pragma mark - Coordinate Conversion

- (NSTimeInterval)timeForPoint:(CGFloat)x {
    CGFloat timeMS = (x + _scrollOffset) / _zoomLevel;
    return timeMS / 1000.0;
}

- (CGFloat)pointForTime:(NSTimeInterval)time {
    CGFloat timeMS = time * 1000.0;
    return (timeMS * _zoomLevel) - _scrollOffset;
}

#pragma mark - Property Setters

- (void)setPlaybackPosition:(NSTimeInterval)position animated:(BOOL)animated {
    _playbackPosition = position;
    _lastSyncedPosition = position;
    _lastSyncTime = CFAbsoluteTimeGetCurrent();
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.05;
            [self updatePlayheadPosition];
        }];
    } else {
        [self updatePlayheadPosition];
    }
}

- (void)setPlaybackPosition:(NSTimeInterval)playbackPosition {
    _playbackPosition = playbackPosition;
    _lastSyncedPosition = playbackPosition;
    _lastSyncTime = CFAbsoluteTimeGetCurrent();
    [self updatePlayheadPosition];
}

- (void)setZoomLevel:(CGFloat)zoomLevel {
    CGFloat clamped = fmin(fmax(zoomLevel, kMinZoomLevel), kMaxZoomLevel);
    if (fabs(clamped - _zoomLevel) < 0.00001) return;
    _zoomLevel = clamped;
    [self.layer setNeedsDisplay];
    [self updatePlayheadPosition];
    [_timingMarksLayer setNeedsDisplay];
    [_songRegionsLayer setNeedsDisplay];
}

- (void)setScrollOffset:(CGFloat)scrollOffset {
    if (fabs(scrollOffset - _scrollOffset) < 0.01) return;
    _scrollOffset = scrollOffset;
    [self.layer setNeedsDisplay];
    [self updatePlayheadPosition];
    [_timingMarksLayer setNeedsDisplay];
    [_songRegionsLayer setNeedsDisplay];
}

- (void)setSequenceDuration:(NSTimeInterval)sequenceDuration {
    _sequenceDuration = sequenceDuration;
    [self.layer setNeedsDisplay];
}

- (void)setPlaying:(BOOL)playing {
    BOOL wasPlaying = _playing;
    _playing = playing;
    if (playing && !wasPlaying) {
        _lastSyncedPosition = _playbackPosition;
        _lastSyncTime = CFAbsoluteTimeGetCurrent();
        [self startDisplayLink];
    } else if (!playing && wasPlaying) {
        [self stopDisplayLink];
        _lastSyncTime = 0;
    }
}

- (void)setTimingMarks:(NSArray<NSDictionary *> *)timingMarks {
    _timingMarks = [timingMarks copy];
    [_timingMarksLayer setNeedsDisplay];
}

- (void)setSelectedTimingMarkId:(NSInteger)selectedTimingMarkId {
    if (_selectedTimingMarkId != selectedTimingMarkId) {
        _selectedTimingMarkId = selectedTimingMarkId;
        [_timingMarksLayer setNeedsDisplay];
    }
}

- (void)reloadTimingMarks {
    [_timingMarksLayer setNeedsDisplay];
}

- (void)setSelectedSongRegionId:(NSInteger)selectedSongRegionId {
    if (_selectedSongRegionId != selectedSongRegionId) {
        _selectedSongRegionId = selectedSongRegionId;
        [_songRegionsLayer setNeedsDisplay];
    }
}

#pragma mark - Song Regions Data

- (void)setSongRegions:(const XLSongRegion *)regions count:(NSInteger)count {
    if (_songRegionStorage) {
        free(_songRegionStorage);
        _songRegionStorage = NULL;
    }
    _songRegionStorageCount = 0;

    if (regions && count > 0) {
        _songRegionStorage = (XLSongRegion *)malloc(sizeof(XLSongRegion) * count);
        memcpy(_songRegionStorage, regions, sizeof(XLSongRegion) * count);
        _songRegionStorageCount = count;
    }

    [_songRegionsLayer setNeedsDisplay];
}

- (void)reloadSongRegions {
    [_songRegionsLayer setNeedsDisplay];
}

- (void)setPreviewTimingMarks:(NSArray<NSNumber *> *)previewTimingMarks {
    _previewTimingMarks = [previewTimingMarks copy];
    [self.layer setNeedsDisplay];
}

#pragma mark - Scrolling

- (void)scrollToTime:(NSTimeInterval)time {
    CGFloat x = time * 1000.0 * _zoomLevel;
    CGFloat viewWidth = NSWidth(self.bounds);
    CGFloat margin = viewWidth * 0.1;

    if (x < _scrollOffset + margin) {
        self.scrollOffset = fmax(0, x - margin);
    } else if (x > _scrollOffset + viewWidth - margin) {
        self.scrollOffset = x - viewWidth + margin;
    }
}

#pragma mark - Song Region Hit Testing

- (NSInteger)boundaryIndexAtPoint:(NSPoint)point {
    if (_songRegionStorageCount < 2 || !_songRegionStorage) return -1;

    // Check internal boundaries (between adjacent regions)
    for (NSInteger i = 0; i < _songRegionStorageCount - 1; i++) {
        CGFloat bx = [self pointForTime:_songRegionStorage[i].endTimeMS / 1000.0];
        if (fabs(point.x - bx) <= kBoundaryHitTestWidth) {
            return i;
        }
    }
    return -1;
}

- (NSInteger)songRegionIdAtPoint:(NSPoint)point {
    if (_songRegionStorageCount == 0 || !_songRegionStorage) return -1;

    NSTimeInterval time = [self timeForPoint:point.x];
    NSInteger timeMS = (NSInteger)(time * 1000.0);

    for (NSInteger i = 0; i < _songRegionStorageCount; i++) {
        if (timeMS >= _songRegionStorage[i].startTimeMS && timeMS < _songRegionStorage[i].endTimeMS) {
            return _songRegionStorage[i].regionId;
        }
    }
    return -1;
}

#pragma mark - Timing Mark Hit Testing

- (NSInteger)timingMarkIdAtPoint:(NSPoint)point {
    CGFloat height = NSHeight(self.bounds);

    for (NSDictionary *mark in _timingMarks) {
        NSNumber *markIdNum = mark[@"id"];
        NSNumber *startTimeMSNum = mark[@"startTimeMS"];

        if (!markIdNum || !startTimeMSNum) continue;

        NSTimeInterval time = startTimeMSNum.doubleValue / 1000.0;
        CGFloat markX = [self pointForTime:time];

        if (fabs(point.x - markX) <= kTimingMarkHitTestWidth) {
            if (point.y >= height - kTimingMarkTriangleSize * 3) {
                return markIdNum.integerValue;
            }
        }
    }
    return -1;
}

#pragma mark - Mouse Handling

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    NSTimeInterval time = [self timeForPoint:loc.x];
    time = fmax(0, fmin(time, _sequenceDuration));

    // Check for Option+click to add song region boundary (or create timing mark if no regions)
    if (event.modifierFlags & NSEventModifierFlagOption) {
        // Snap to frame boundary for timing marks and boundaries
        NSTimeInterval snappedTime = [self snapTimeToFrame:time];
        snappedTime = fmax(0, fmin(snappedTime, _sequenceDuration));
        NSInteger timeMS = (NSInteger)(snappedTime * 1000.0);
        if ([_delegate respondsToSelector:@selector(timelineRuler:didRequestAddSongRegionBoundaryAtTimeMS:)]) {
            [_delegate timelineRuler:self didRequestAddSongRegionBoundaryAtTimeMS:timeMS];
            return;
        }
        // Fallback to timing mark creation
        if (_timingMarksEditable && [_delegate respondsToSelector:@selector(timelineRuler:didRequestTimingMarkAtSeconds:)]) {
            [_delegate timelineRuler:self didRequestTimingMarkAtSeconds:snappedTime];
        }
        return;
    }

    // Check if clicking on a song region boundary
    NSInteger boundaryIdx = [self boundaryIndexAtPoint:loc];
    if (boundaryIdx >= 0) {
        _draggingBoundary = YES;
        _draggingBoundaryIndex = boundaryIdx;
        return;
    }

    // Check double-click on a song region → edit popover
    if (event.clickCount == 2) {
        NSInteger regionId = [self songRegionIdAtPoint:loc];
        if (regionId >= 0) {
            [self showEditPopoverForRegionId:regionId atPoint:loc];
            return;
        }
    }

    // Check single click on a song region → select
    NSInteger regionId = [self songRegionIdAtPoint:loc];
    if (regionId >= 0 && _songRegionStorageCount > 0) {
        self.selectedSongRegionId = regionId;
        if ([_delegate respondsToSelector:@selector(timelineRuler:didSelectSongRegionId:)]) {
            [_delegate timelineRuler:self didSelectSongRegionId:regionId];
        }
        // Don't return — also start scrubbing
    }

    // Check if clicking on a timing mark
    NSInteger hitMarkId = [self timingMarkIdAtPoint:loc];
    if (hitMarkId >= 0 && _timingMarksEditable) {
        _draggingTimingMark = YES;
        _draggingTimingMarkId = hitMarkId;
        _selectedTimingMarkId = hitMarkId;
        _dragStartTimeMS = time * 1000.0;
        [_timingMarksLayer setNeedsDisplay];
        return;
    }

    // Regular click - scrub to position
    _dragging = YES;
    _playbackPosition = time;
    [self updatePlayheadPosition];

    if ([_delegate respondsToSelector:@selector(timelineRuler:didBeginScrubbing:)]) {
        [_delegate timelineRuler:self didBeginScrubbing:time];
    }
    if ([_delegate respondsToSelector:@selector(timelineRuler:didChangePlaybackPosition:)]) {
        [_delegate timelineRuler:self didChangePlaybackPosition:time];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    NSTimeInterval time = [self timeForPoint:loc.x];
    time = fmax(0, fmin(time, _sequenceDuration));

    // Handle song region boundary dragging (snap to frame)
    if (_draggingBoundary && _draggingBoundaryIndex >= 0) {
        NSTimeInterval snappedTime = [self snapTimeToFrame:time];
        snappedTime = fmax(0, fmin(snappedTime, _sequenceDuration));
        NSInteger timeMS = (NSInteger)(snappedTime * 1000.0);
        if (_songRegionStorage && _draggingBoundaryIndex < _songRegionStorageCount - 1) {
            NSInteger idx = _draggingBoundaryIndex;
            // Clamp to adjacent region bounds
            NSInteger minT = _songRegionStorage[idx].startTimeMS + 1;
            NSInteger maxT = _songRegionStorage[idx + 1].endTimeMS - 1;
            if (timeMS < minT) timeMS = minT;
            if (timeMS > maxT) timeMS = maxT;

            _songRegionStorage[idx].endTimeMS = timeMS;
            _songRegionStorage[idx + 1].startTimeMS = timeMS;
            [_songRegionsLayer setNeedsDisplay];
        }
        return;
    }

    // Handle timing mark dragging (snap to frame)
    if (_draggingTimingMark && _draggingTimingMarkId >= 0) {
        NSTimeInterval snappedTime = [self snapTimeToFrame:time];
        snappedTime = fmax(0, fmin(snappedTime, _sequenceDuration));
        NSMutableArray *updatedMarks = [_timingMarks mutableCopy];
        for (NSUInteger i = 0; i < updatedMarks.count; i++) {
            NSDictionary *mark = updatedMarks[i];
            NSNumber *markIdNum = mark[@"id"];
            if (markIdNum && markIdNum.integerValue == _draggingTimingMarkId) {
                NSMutableDictionary *mutableMark = [mark mutableCopy];
                mutableMark[@"startTimeMS"] = @((NSInteger)(snappedTime * 1000.0));
                updatedMarks[i] = mutableMark;
                break;
            }
        }
        _timingMarks = updatedMarks;
        [_timingMarksLayer setNeedsDisplay];
        return;
    }

    // Handle normal playhead scrubbing
    if (!_dragging) return;

    _playbackPosition = time;
    [self updatePlayheadPosition];

    if ([_delegate respondsToSelector:@selector(timelineRuler:didChangePlaybackPosition:)]) {
        [_delegate timelineRuler:self didChangePlaybackPosition:time];
    }
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    NSTimeInterval time = [self timeForPoint:loc.x];
    time = fmax(0, fmin(time, _sequenceDuration));

    // Finalize song region boundary drag (snap to frame)
    if (_draggingBoundary && _draggingBoundaryIndex >= 0) {
        NSTimeInterval snappedTime = [self snapTimeToFrame:time];
        snappedTime = fmax(0, fmin(snappedTime, _sequenceDuration));
        NSInteger timeMS = (NSInteger)(snappedTime * 1000.0);
        if ([_delegate respondsToSelector:@selector(timelineRuler:didMoveSongRegionBoundaryAtIndex:toTimeMS:)]) {
            // Clamp the same way as during drag
            if (_songRegionStorage && _draggingBoundaryIndex < _songRegionStorageCount - 1) {
                NSInteger idx = _draggingBoundaryIndex;
                NSInteger minT = _songRegionStorage[idx].startTimeMS;
                NSInteger maxT = _songRegionStorage[idx + 1].endTimeMS;
                if (timeMS < minT + 1) timeMS = minT + 1;
                if (timeMS > maxT - 1) timeMS = maxT - 1;
            }
            [_delegate timelineRuler:self didMoveSongRegionBoundaryAtIndex:_draggingBoundaryIndex toTimeMS:timeMS];
        }
        _draggingBoundary = NO;
        _draggingBoundaryIndex = -1;
        return;
    }

    // Finalize timing mark drag (snap to frame)
    if (_draggingTimingMark && _draggingTimingMarkId >= 0) {
        NSTimeInterval snappedTime = [self snapTimeToFrame:time];
        snappedTime = fmax(0, fmin(snappedTime, _sequenceDuration));
        if ([_delegate respondsToSelector:@selector(timelineRuler:didMoveTimingMarkId:toSeconds:)]) {
            [_delegate timelineRuler:self didMoveTimingMarkId:_draggingTimingMarkId toSeconds:snappedTime];
        }
        _draggingTimingMark = NO;
        _draggingTimingMarkId = -1;
        return;
    }

    // Finalize normal playhead scrubbing (no snap — sub-frame precision)
    if (!_dragging) return;

    _dragging = NO;
    _playbackPosition = time;
    [self updatePlayheadPosition];

    if ([_delegate respondsToSelector:@selector(timelineRuler:didEndScrubbing:)]) {
        [_delegate timelineRuler:self didEndScrubbing:time];
    }
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    [self updateCursorForPoint:loc modifierFlags:event.modifierFlags];
}

- (void)mouseExited:(NSEvent *)event {
    [[NSCursor arrowCursor] set];
}

- (void)flagsChanged:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(loc, self.bounds)) {
        [self updateCursorForPoint:loc modifierFlags:event.modifierFlags];
    }
}

- (void)updateCursorForPoint:(NSPoint)loc modifierFlags:(NSEventModifierFlags)flags {
    NSInteger boundaryIdx = [self boundaryIndexAtPoint:loc];
    if (boundaryIdx >= 0) {
        [[NSCursor resizeLeftRightCursor] set];
    } else if (flags & NSEventModifierFlagOption) {
        [[NSCursor crosshairCursor] set];
    } else {
        [[NSCursor arrowCursor] set];
    }
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:(NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp)
               owner:self
            userInfo:nil];
    [self addTrackingArea:trackingArea];
}

#pragma mark - Edit Popover

- (void)showEditPopoverForRegionId:(NSInteger)regionId atPoint:(NSPoint)loc {
    XLSongRegion *region = NULL;
    for (NSInteger i = 0; i < _songRegionStorageCount; i++) {
        if (_songRegionStorage[i].regionId == regionId) {
            region = &_songRegionStorage[i];
            break;
        }
    }
    if (!region) return;

    NSString *name = [NSString stringWithUTF8String:region->name];
    NSColor *color = [NSColor colorWithRed:region->colorR green:region->colorG blue:region->colorB alpha:region->colorA];

    // Anchor rect: small area around the click point
    NSRect anchorRect = NSMakeRect(loc.x - 10, loc.y - 5, 20, 10);

    __weak XLTimelineRulerView *weakSelf = self;
    NSInteger capturedRegionId = regionId;

    [XLSongRegionEditPopover showRelativeToRect:anchorRect
                                         ofView:self
                                       withName:name
                                          color:color
                                     completion:^(NSString *newName, NSColor *newColor) {
        XLTimelineRulerView *strongSelf = weakSelf;
        if (!strongSelf) return;
        if ([strongSelf.delegate respondsToSelector:@selector(timelineRuler:didEditSongRegionId:name:color:)]) {
            [strongSelf.delegate timelineRuler:strongSelf didEditSongRegionId:capturedRegionId name:newName color:newColor];
        }
    }];
}

#pragma mark - Context Menu

- (void)rightMouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    NSTimeInterval clickTime = [self timeForPoint:loc.x];
    clickTime = [self snapTimeToFrame:clickTime];
    clickTime = fmax(0, fmin(clickTime, _sequenceDuration));
    _rightClickPositionMS = (NSInteger)(clickTime * 1000.0);

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Timeline"];

    // --- Zoom items ---
    BOOL hasSelection = NO;
    if ([_delegate respondsToSelector:@selector(timelineRulerHasTimeSelection:)]) {
        hasSelection = [_delegate timelineRulerHasTimeSelection:self];
    }

    NSMenuItem *zoomSelItem = [[NSMenuItem alloc] initWithTitle:@"Zoom to Selection"
                                                        action:@selector(contextZoomToSelection:)
                                                 keyEquivalent:@""];
    zoomSelItem.target = self;
    zoomSelItem.enabled = hasSelection;
    [menu addItem:zoomSelItem];

    NSMenuItem *resetZoomItem = [[NSMenuItem alloc] initWithTitle:@"Reset Zoom"
                                                          action:@selector(contextResetZoom:)
                                                   keyEquivalent:@""];
    resetZoomItem.target = self;
    [menu addItem:resetZoomItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Song Structure items ---
    NSInteger boundaryIdx = [self boundaryIndexAtPoint:loc];

    NSMenuItem *addBoundaryItem = [[NSMenuItem alloc] initWithTitle:@"Add Boundary Here"
                                                             action:@selector(contextAddBoundary:)
                                                      keyEquivalent:@""];
    addBoundaryItem.target = self;
    [menu addItem:addBoundaryItem];

    if (boundaryIdx >= 0) {
        NSMenuItem *deleteBoundaryItem = [[NSMenuItem alloc] initWithTitle:@"Delete Boundary"
                                                                   action:@selector(contextDeleteBoundary:)
                                                            keyEquivalent:@""];
        deleteBoundaryItem.target = self;
        deleteBoundaryItem.tag = boundaryIdx;
        [menu addItem:deleteBoundaryItem];
    }

    NSInteger regionId = [self songRegionIdAtPoint:loc];
    if (regionId >= 0) {
        NSMenuItem *editRegionItem = [[NSMenuItem alloc] initWithTitle:@"Edit Region..."
                                                               action:@selector(contextEditRegion:)
                                                        keyEquivalent:@""];
        editRegionItem.target = self;
        editRegionItem.tag = regionId;
        [menu addItem:editRegionItem];
    }

    if (_songRegionStorageCount > 0) {
        NSMenuItem *clearItem = [[NSMenuItem alloc] initWithTitle:@"Clear Song Structure"
                                                          action:@selector(contextClearSongStructure:)
                                                   keyEquivalent:@""];
        clearItem.target = self;
        [menu addItem:clearItem];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Timing mark delete (if right-clicked on one) ---
    NSInteger hitMarkId = [self timingMarkIdAtPoint:loc];
    if (hitMarkId >= 0 && _timingMarksEditable) {
        _selectedTimingMarkId = hitMarkId;
        [_timingMarksLayer setNeedsDisplay];

        NSMenuItem *deleteMarkItem = [[NSMenuItem alloc] initWithTitle:@"Delete Timing Mark"
                                                               action:@selector(deleteSelectedTimingMark:)
                                                        keyEquivalent:@""];
        deleteMarkItem.target = self;
        [menu addItem:deleteMarkItem];
        [menu addItem:[NSMenuItem separatorItem]];
    }

    // --- Timing tags 0-9 ---
    for (NSInteger i = 0; i < kTimingTagCount; i++) {
        NSMenuItem *tagItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld", (long)i]
                                                         action:@selector(contextToggleTimingTag:)
                                                  keyEquivalent:@""];
        tagItem.target = self;
        tagItem.tag = i;
        tagItem.state = (_timingTags[i] != -1) ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:tagItem];
    }

    // --- Delete Tag submenu ---
    NSInteger tagCount = [self activeTimingTagCount];
    if (tagCount > 0) {
        [menu addItem:[NSMenuItem separatorItem]];

        NSMenu *deleteSubmenu = [[NSMenu alloc] initWithTitle:@"Delete"];

        if (tagCount > 1) {
            NSMenuItem *deleteAllItem = [[NSMenuItem alloc] initWithTitle:@"All"
                                                                  action:@selector(contextDeleteAllTimingTags:)
                                                           keyEquivalent:@""];
            deleteAllItem.target = self;
            [deleteSubmenu addItem:deleteAllItem];
        }

        for (NSInteger i = 0; i < kTimingTagCount; i++) {
            if (_timingTags[i] != -1) {
                NSMenuItem *deleteTagItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld", (long)i]
                                                                      action:@selector(contextDeleteTimingTag:)
                                                               keyEquivalent:@""];
                deleteTagItem.target = self;
                deleteTagItem.tag = i;
                [deleteSubmenu addItem:deleteTagItem];
            }
        }

        NSMenuItem *deleteSubmenuItem = [[NSMenuItem alloc] initWithTitle:@"Delete" action:nil keyEquivalent:@""];
        [menu setSubmenu:deleteSubmenu forItem:deleteSubmenuItem];
        [menu addItem:deleteSubmenuItem];
    }

    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

#pragma mark - Context Menu Actions

- (void)contextAddBoundary:(id)sender {
    if ([_delegate respondsToSelector:@selector(timelineRuler:didRequestAddSongRegionBoundaryAtTimeMS:)]) {
        [_delegate timelineRuler:self didRequestAddSongRegionBoundaryAtTimeMS:_rightClickPositionMS];
    }
}

- (void)contextDeleteBoundary:(id)sender {
    NSInteger idx = [(NSMenuItem *)sender tag];
    if ([_delegate respondsToSelector:@selector(timelineRuler:didRequestDeleteSongRegionBoundaryAtIndex:)]) {
        [_delegate timelineRuler:self didRequestDeleteSongRegionBoundaryAtIndex:idx];
    }
}

- (void)contextEditRegion:(id)sender {
    NSInteger regionId = [(NSMenuItem *)sender tag];
    // Find the region center for popover anchor
    for (NSInteger i = 0; i < _songRegionStorageCount; i++) {
        if (_songRegionStorage[i].regionId == regionId) {
            CGFloat cx = [self pointForTime:(_songRegionStorage[i].startTimeMS + _songRegionStorage[i].endTimeMS) / 2000.0];
            [self showEditPopoverForRegionId:regionId atPoint:NSMakePoint(cx, NSHeight(self.bounds) / 2.0)];
            return;
        }
    }
}

- (void)contextClearSongStructure:(id)sender {
    if ([_delegate respondsToSelector:@selector(timelineRulerDidRequestClearSongStructure:)]) {
        [_delegate timelineRulerDidRequestClearSongStructure:self];
    }
}

- (void)deleteSelectedTimingMark:(id)sender {
    if (_selectedTimingMarkId >= 0 && _timingMarksEditable) {
        if ([_delegate respondsToSelector:@selector(timelineRuler:didRequestDeleteTimingMarkId:)]) {
            [_delegate timelineRuler:self didRequestDeleteTimingMarkId:_selectedTimingMarkId];
        }
        _selectedTimingMarkId = -1;
        [_timingMarksLayer setNeedsDisplay];
    }
}

- (void)contextZoomToSelection:(id)sender {
    if ([_delegate respondsToSelector:@selector(timelineRulerDidRequestZoomToSelection:)]) {
        [_delegate timelineRulerDidRequestZoomToSelection:self];
    }
}

- (void)contextResetZoom:(id)sender {
    if ([_delegate respondsToSelector:@selector(timelineRulerDidRequestResetZoom:)]) {
        [_delegate timelineRulerDidRequestResetZoom:self];
    }
}

- (void)contextToggleTimingTag:(id)sender {
    NSInteger tagIndex = [(NSMenuItem *)sender tag];
    if (tagIndex < 0 || tagIndex >= kTimingTagCount) return;

    if (_timingTags[tagIndex] != -1) {
        _timingTags[tagIndex] = -1;
    } else {
        _timingTags[tagIndex] = _rightClickPositionMS;
    }

    [self.layer setNeedsDisplay];

    if ([_delegate respondsToSelector:@selector(timelineRuler:didToggleTimingTag:atPositionMS:)]) {
        [_delegate timelineRuler:self didToggleTimingTag:tagIndex atPositionMS:_timingTags[tagIndex]];
    }
}

- (void)contextDeleteTimingTag:(id)sender {
    NSInteger tagIndex = [(NSMenuItem *)sender tag];
    if (tagIndex < 0 || tagIndex >= kTimingTagCount) return;

    _timingTags[tagIndex] = -1;
    [self.layer setNeedsDisplay];

    if ([_delegate respondsToSelector:@selector(timelineRuler:didToggleTimingTag:atPositionMS:)]) {
        [_delegate timelineRuler:self didToggleTimingTag:tagIndex atPositionMS:-1];
    }
}

- (void)contextDeleteAllTimingTags:(id)sender {
    [self clearAllTimingTags];

    if ([_delegate respondsToSelector:@selector(timelineRulerDidRequestClearAllTimingTags:)]) {
        [_delegate timelineRulerDidRequestClearAllTimingTags:self];
    }
}

- (void)keyDown:(NSEvent *)event {
    unichar keyChar = 0;
    if (event.characters.length > 0) {
        keyChar = [event.characters characterAtIndex:0];
    }

    // Delete/Backspace: delete selected timing mark or selected boundary
    if (keyChar == NSDeleteCharacter || keyChar == NSBackspaceCharacter ||
        event.keyCode == 51 || event.keyCode == 117) {
        if (_selectedTimingMarkId >= 0 && _timingMarksEditable) {
            [self deleteSelectedTimingMark:nil];
            return;
        }
    }

    // Escape to deselect
    if (event.keyCode == 53) {
        _selectedTimingMarkId = -1;
        _selectedSongRegionId = -1;
        [_timingMarksLayer setNeedsDisplay];
        [_songRegionsLayer setNeedsDisplay];
        return;
    }

    [super keyDown:event];
}

#pragma mark - Scroll Wheel (Zoom)

- (void)scrollWheel:(NSEvent *)event {
    // Option + scroll = zoom
    if (event.modifierFlags & NSEventModifierFlagOption) {
        NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
        NSTimeInterval timeAtCursor = [self timeForPoint:loc.x];

        CGFloat factor = 1.0 + event.scrollingDeltaY * 0.05;
        factor = fmax(0.5, fmin(factor, 2.0));

        CGFloat newZoom = _zoomLevel * factor;
        self.zoomLevel = newZoom;

        CGFloat newX = timeAtCursor * 1000.0 * _zoomLevel;
        self.scrollOffset = newX - loc.x;
        if (_scrollOffset < 0) self.scrollOffset = 0;

        if ([_delegate respondsToSelector:@selector(timelineRuler:didChangeZoomLevel:centeredOnPointX:)]) {
            [_delegate timelineRuler:self didChangeZoomLevel:_zoomLevel centeredOnPointX:loc.x];
        } else if ([_delegate respondsToSelector:@selector(timelineRuler:didChangeZoomLevel:)]) {
            [_delegate timelineRuler:self didChangeZoomLevel:_zoomLevel];
        }

        if ([_delegate respondsToSelector:@selector(timelineRuler:didChangeScrollOffset:)]) {
            [_delegate timelineRuler:self didChangeScrollOffset:_scrollOffset];
        }
        return;
    }

    // Horizontal scrolling
    CGFloat dx = event.scrollingDeltaX;
    if (event.modifierFlags & NSEventModifierFlagShift) {
        dx = event.scrollingDeltaY;
    }

    if (fabs(dx) > 0.01) {
        CGFloat newOffset = _scrollOffset - dx;
        self.scrollOffset = fmax(0, newOffset);

        if ([_delegate respondsToSelector:@selector(timelineRuler:didChangeScrollOffset:)]) {
            [_delegate timelineRuler:self didChangeScrollOffset:_scrollOffset];
        }
        return;
    }

    [super scrollWheel:event];
}

- (void)magnifyWithEvent:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    NSTimeInterval timeAtCursor = [self timeForPoint:loc.x];

    CGFloat factor = 1.0 + event.magnification;
    CGFloat newZoom = _zoomLevel * factor;
    self.zoomLevel = newZoom;

    CGFloat newX = timeAtCursor * 1000.0 * _zoomLevel;
    self.scrollOffset = newX - loc.x;
    if (_scrollOffset < 0) self.scrollOffset = 0;

    if ([_delegate respondsToSelector:@selector(timelineRuler:didChangeZoomLevel:centeredOnPointX:)]) {
        [_delegate timelineRuler:self didChangeZoomLevel:_zoomLevel centeredOnPointX:loc.x];
    } else if ([_delegate respondsToSelector:@selector(timelineRuler:didChangeZoomLevel:)]) {
        [_delegate timelineRuler:self didChangeZoomLevel:_zoomLevel];
    }

    if ([_delegate respondsToSelector:@selector(timelineRuler:didChangeScrollOffset:)]) {
        [_delegate timelineRuler:self didChangeScrollOffset:_scrollOffset];
    }
}

#pragma mark - Frame Snapping

- (NSTimeInterval)snapTimeToFrame:(NSTimeInterval)time {
    if (_frameRate <= 0) return time;
    double frameMS = 1000.0 / (double)_frameRate;
    double timeMS = time * 1000.0;
    double snapped = round(timeMS / frameMS) * frameMS;
    return snapped / 1000.0;
}

#pragma mark - Playhead Timer

- (void)startDisplayLink {
    if (_playheadTimer) return;

    _playheadTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                      target:self
                                                    selector:@selector(playheadTimerFired:)
                                                    userInfo:nil
                                                     repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_playheadTimer forMode:NSRunLoopCommonModes];
    _lastDisplayLinkTimestamp = 0;
}

- (void)stopDisplayLink {
    if (_playheadTimer) {
        [_playheadTimer invalidate];
        _playheadTimer = nil;
    }
    _lastDisplayLinkTimestamp = 0;
}

- (void)playheadTimerFired:(NSTimer *)timer {
    if (!_playing) return;

    if (_lastSyncTime > 0 && _playbackRate > 0) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        CFAbsoluteTime elapsed = now - _lastSyncTime;
        NSTimeInterval interpolatedPosition = _lastSyncedPosition + (elapsed * _playbackRate);

        if (interpolatedPosition < 0) interpolatedPosition = 0;
        if (_sequenceDuration > 0 && interpolatedPosition > _sequenceDuration) {
            interpolatedPosition = _sequenceDuration;
        }

        _playbackPosition = interpolatedPosition;
    }

    [self updatePlayheadPosition];
}

#pragma mark - View Lifecycle

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        CGFloat scale = self.window.backingScaleFactor;
        self.layer.contentsScale = scale;
        _playheadLayer.contentsScale = scale;
        _timingMarksLayer.contentsScale = scale;
        _songRegionsLayer.contentsScale = scale;
        [self.layer setNeedsDisplay];
        [self updateTimingMarksLayer];
        [self updateSongRegionsLayer];
    } else {
        [self stopDisplayLink];
    }
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self.layer setNeedsDisplay];
    [self updatePlayheadPosition];
    [self updateTimingMarksLayer];
    [self updateSongRegionsLayer];
}

#pragma mark - Flipped Coordinates

- (BOOL)isFlipped {
    return YES;
}

#pragma mark - Intrinsic Content Size

- (NSSize)intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric, kRulerHeight);
}

#pragma mark - Timing Tags (Bookmarks)

- (NSInteger *)timingTagPositions {
    return _timingTags;
}

- (void)setTimingTag:(NSInteger)tagIndex toPositionMS:(NSInteger)positionMS {
    if (tagIndex < 0 || tagIndex >= kTimingTagCount) return;

    if (_sequenceDuration > 0 && positionMS > (NSInteger)(_sequenceDuration * 1000.0)) {
        positionMS = (NSInteger)(_sequenceDuration * 1000.0);
    }

    _timingTags[tagIndex] = positionMS;
    [self.layer setNeedsDisplay];
}

- (void)clearAllTimingTags {
    for (NSInteger i = 0; i < kTimingTagCount; i++) {
        _timingTags[i] = -1;
    }
    [self.layer setNeedsDisplay];
}

- (NSInteger)activeTimingTagCount {
    NSInteger count = 0;
    for (NSInteger i = 0; i < kTimingTagCount; i++) {
        if (_timingTags[i] != -1) count++;
    }
    return count;
}

@end
