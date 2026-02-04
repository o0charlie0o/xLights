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

// Color constants as raw RGBA values to avoid NSColor object lifetime issues
// with static variables in CALayerDelegate callbacks
static const CGFloat kBgR = 0.118, kBgG = 0.118, kBgB = 0.118;
static const CGFloat kTickGray = 0.55;
static const CGFloat kPlayheadR = 1.0, kPlayheadG = 0.2, kPlayheadB = 0.2;

@interface XLTimelineRulerView ()

@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, strong) CALayer *playheadLayer;
@property (nonatomic, strong) CALayer *timingMarksLayer;
@property (nonatomic, strong) NSTimer *playheadTimer;
@property (nonatomic, assign) CFTimeInterval lastDisplayLinkTimestamp;

// For smooth playhead interpolation during playback
@property (nonatomic, assign) NSTimeInterval lastSyncedPosition;
@property (nonatomic, assign) CFAbsoluteTime lastSyncTime;

// Timing mark dragging state
@property (nonatomic, assign) BOOL draggingTimingMark;
@property (nonatomic, assign) NSInteger draggingTimingMarkId;
@property (nonatomic, assign) CGFloat dragStartTimeMS;

@end

@implementation XLTimelineRulerView

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

    [self setupPlayheadLayer];
    [self setupTimingMarksLayer];
}

- (void)dealloc {
    [self stopDisplayLink];
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
    [self.layer setNeedsDisplay];
    [_timingMarksLayer setNeedsDisplay];
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
    _timingMarksLayer.zPosition = 50;  // Below playhead, above ticks
    _timingMarksLayer.delegate = self;
    _timingMarksLayer.needsDisplayOnBoundsChange = YES;
    [self.layer addSublayer:_timingMarksLayer];
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
}

#pragma mark - Tick Interval Calculation

- (NSTimeInterval)majorTickIntervalForZoom {
    // Target: labels roughly kMinPixelsBetweenLabels apart
    // zoomLevel = pixels per millisecond
    // We want: interval_ms * zoomLevel >= kMinPixelsBetweenLabels
    // interval_ms >= kMinPixelsBetweenLabels / zoomLevel

    CGFloat targetIntervalMS = kMinPixelsBetweenLabels / _zoomLevel;

    // Snap to nice intervals (in ms)
    static const double niceIntervals[] = {
        10, 20, 25, 50, 100, 200, 250, 500,
        1000, 2000, 2500, 5000, 10000, 15000, 30000,
        60000, 120000, 300000, 600000
    };
    static const int niceCount = sizeof(niceIntervals) / sizeof(niceIntervals[0]);

    for (int i = 0; i < niceCount; i++) {
        if (niceIntervals[i] >= targetIntervalMS) {
            return niceIntervals[i] / 1000.0; // Convert to seconds
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
        // Sub-second: show with milliseconds
        if (minutes > 0) {
            return [NSString stringWithFormat:@"%d:%02d.%03d", minutes, seconds, ms];
        }
        return [NSString stringWithFormat:@"%d.%03d", seconds, ms];
    }
    else if (majorInterval < 1.0) {
        // Sub-second: show with fractional seconds
        if (minutes > 0) {
            return [NSString stringWithFormat:@"%d:%02d.%d", minutes, seconds, ms / 100];
        }
        return [NSString stringWithFormat:@"%d.%d", seconds, ms / 100];
    }
    else if (majorInterval < 60.0) {
        // Seconds range
        if (minutes > 0) {
            return [NSString stringWithFormat:@"%d:%02d", minutes, seconds];
        }
        return [NSString stringWithFormat:@"%ds", seconds];
    }
    else {
        // Minutes range
        return [NSString stringWithFormat:@"%dm", minutes];
    }
}

#pragma mark - Coordinate Conversion

- (NSTimeInterval)timeForPoint:(CGFloat)x {
    // x = (time_ms * zoomLevel) - scrollOffset
    // time_ms = (x + scrollOffset) / zoomLevel
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
    // Update visual position - playback controller sends updates at 60fps
    [self updatePlayheadPosition];
}

- (void)setZoomLevel:(CGFloat)zoomLevel {
    CGFloat clamped = fmin(fmax(zoomLevel, kMinZoomLevel), kMaxZoomLevel);
    if (fabs(clamped - _zoomLevel) < 0.0001) return;
    _zoomLevel = clamped;
    [self.layer setNeedsDisplay];
    [self updatePlayheadPosition];
    [_timingMarksLayer setNeedsDisplay];
}

- (void)setScrollOffset:(CGFloat)scrollOffset {
    if (fabs(scrollOffset - _scrollOffset) < 0.01) return;
    _scrollOffset = scrollOffset;
    [self.layer setNeedsDisplay];
    [self updatePlayheadPosition];
    [_timingMarksLayer setNeedsDisplay];
}

- (void)setSequenceDuration:(NSTimeInterval)sequenceDuration {
    _sequenceDuration = sequenceDuration;
    [self.layer setNeedsDisplay];
}

- (void)setPlaying:(BOOL)playing {
    BOOL wasPlaying = _playing;
    _playing = playing;
    if (playing && !wasPlaying) {
        // Initialize interpolation state when playback starts
        _lastSyncedPosition = _playbackPosition;
        _lastSyncTime = CFAbsoluteTimeGetCurrent();
        [self startDisplayLink];
    } else if (!playing && wasPlaying) {
        [self stopDisplayLink];
        // Reset interpolation state
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

#pragma mark - Timing Mark Hit Testing

- (NSInteger)timingMarkIdAtPoint:(NSPoint)point {
    CGFloat height = NSHeight(self.bounds);

    for (NSDictionary *mark in _timingMarks) {
        NSNumber *markIdNum = mark[@"id"];
        NSNumber *startTimeMSNum = mark[@"startTimeMS"];

        if (!markIdNum || !startTimeMSNum) continue;

        NSTimeInterval time = startTimeMSNum.doubleValue / 1000.0;
        CGFloat markX = [self pointForTime:time];

        // Check if click is within hit test area (horizontal)
        if (fabs(point.x - markX) <= kTimingMarkHitTestWidth) {
            // Check if in the lower portion of the view (near the triangle)
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
    time = [self snapTimeToFrame:time];
    time = fmax(0, fmin(time, _sequenceDuration));

    // Check for Option+click to create timing mark
    if ((event.modifierFlags & NSEventModifierFlagOption) && _timingMarksEditable) {
        if ([_delegate respondsToSelector:@selector(timelineRuler:didRequestTimingMarkAtSeconds:)]) {
            [_delegate timelineRuler:self didRequestTimingMarkAtSeconds:time];
        }
        return;
    }

    // Check if clicking on a timing mark
    NSInteger hitMarkId = [self timingMarkIdAtPoint:loc];
    if (hitMarkId >= 0 && _timingMarksEditable) {
        // Start dragging the timing mark
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
    time = [self snapTimeToFrame:time];
    time = fmax(0, fmin(time, _sequenceDuration));

    // Handle timing mark dragging
    if (_draggingTimingMark && _draggingTimingMarkId >= 0) {
        // Update the timing mark position in the local array for visual feedback
        NSMutableArray *updatedMarks = [_timingMarks mutableCopy];
        for (NSUInteger i = 0; i < updatedMarks.count; i++) {
            NSDictionary *mark = updatedMarks[i];
            NSNumber *markIdNum = mark[@"id"];
            if (markIdNum && markIdNum.integerValue == _draggingTimingMarkId) {
                NSMutableDictionary *mutableMark = [mark mutableCopy];
                mutableMark[@"startTimeMS"] = @((NSInteger)(time * 1000.0));
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
    time = [self snapTimeToFrame:time];
    time = fmax(0, fmin(time, _sequenceDuration));

    // Finalize timing mark drag
    if (_draggingTimingMark && _draggingTimingMarkId >= 0) {
        if ([_delegate respondsToSelector:@selector(timelineRuler:didMoveTimingMarkId:toSeconds:)]) {
            [_delegate timelineRuler:self didMoveTimingMarkId:_draggingTimingMarkId toSeconds:time];
        }
        _draggingTimingMark = NO;
        _draggingTimingMarkId = -1;
        return;
    }

    // Finalize normal playhead scrubbing
    if (!_dragging) return;

    _dragging = NO;
    _playbackPosition = time;
    [self updatePlayheadPosition];

    if ([_delegate respondsToSelector:@selector(timelineRuler:didEndScrubbing:)]) {
        [_delegate timelineRuler:self didEndScrubbing:time];
    }
}

- (void)rightMouseDown:(NSEvent *)event {
    if (!_timingMarksEditable) {
        [super rightMouseDown:event];
        return;
    }

    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger hitMarkId = [self timingMarkIdAtPoint:loc];

    if (hitMarkId >= 0) {
        _selectedTimingMarkId = hitMarkId;
        [_timingMarksLayer setNeedsDisplay];

        // Show context menu
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Timing Mark"];
        NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete Timing Mark"
                                                            action:@selector(deleteSelectedTimingMark:)
                                                     keyEquivalent:@""];
        deleteItem.target = self;
        [menu addItem:deleteItem];

        [NSMenu popUpContextMenu:menu withEvent:event forView:self];
    } else {
        [super rightMouseDown:event];
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

- (void)keyDown:(NSEvent *)event {
    // Handle Delete/Backspace to delete selected timing mark
    if (_selectedTimingMarkId >= 0 && _timingMarksEditable) {
        unichar keyChar = 0;
        if (event.characters.length > 0) {
            keyChar = [event.characters characterAtIndex:0];
        }

        if (keyChar == NSDeleteCharacter || keyChar == NSBackspaceCharacter ||
            event.keyCode == 51 || event.keyCode == 117) {  // 51 = Backspace, 117 = Delete
            [self deleteSelectedTimingMark:nil];
            return;
        }
    }

    // Escape to deselect
    if (event.keyCode == 53) {  // Escape
        _selectedTimingMarkId = -1;
        [_timingMarksLayer setNeedsDisplay];
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

        // Adjust scroll offset to keep time under cursor stable
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

    // Horizontal scrolling (shift+scroll or natural horizontal scroll)
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

    // Magnify gesture (pinch) also arrives as scrollWheel on some configurations
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

    // Use NSTimer instead of CADisplayLink - more reliable for this use case
    // 60fps update rate for smooth playhead animation
    _playheadTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                      target:self
                                                    selector:@selector(playheadTimerFired:)
                                                    userInfo:nil
                                                     repeats:YES];
    // Add to common run loop modes so it fires during tracking
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

    // Interpolate the playhead position based on elapsed time since last sync
    // This provides smooth 60fps animation even when position updates are less frequent
    if (_lastSyncTime > 0 && _playbackRate > 0) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        CFAbsoluteTime elapsed = now - _lastSyncTime;
        NSTimeInterval interpolatedPosition = _lastSyncedPosition + (elapsed * _playbackRate);

        // Clamp to valid range
        if (interpolatedPosition < 0) interpolatedPosition = 0;
        if (_sequenceDuration > 0 && interpolatedPosition > _sequenceDuration) {
            interpolatedPosition = _sequenceDuration;
        }

        // Update the visual position directly without triggering sync update
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
        [self.layer setNeedsDisplay];
        [self updateTimingMarksLayer];
    } else {
        [self stopDisplayLink];
    }
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self.layer setNeedsDisplay];
    [self updatePlayheadPosition];
    [self updateTimingMarksLayer];
}

#pragma mark - Flipped Coordinates

- (BOOL)isFlipped {
    return YES;
}

#pragma mark - Intrinsic Content Size

- (NSSize)intrinsicContentSize {
    return NSMakeSize(NSViewNoIntrinsicMetric, kRulerHeight);
}

@end
