/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLValueCurveWindow.h"

// Curve type definitions - C array for heap safety
static const XLCurveTypeDef kCurveTypes[] = {
    { "Flat", "Flat", "minus", 1 },
    { "Ramp", "Ramp", "arrow.up.right", 2 },
    { "Ramp Up/Down", "Ramp Up/Down", "arrow.up.and.down", 2 },
    { "Ramp Up/Down Hold", "Ramp Up/Down Hold", "arrow.up.and.down", 3 },
    { "Saw Tooth", "Saw Tooth", "waveform.path", 2 },
    { "Parabolic Down", "Parabolic Down", "arrow.down.forward.and.arrow.up.backward", 2 },
    { "Parabolic Up", "Parabolic Up", "arrow.up.forward.and.arrow.down.backward", 2 },
    { "Logarithmic Up", "Logarithmic Up", "chart.line.uptrend.xyaxis", 2 },
    { "Logarithmic Down", "Logarithmic Down", "chart.line.downtrend.xyaxis", 2 },
    { "Exponential Up", "Exponential Up", "chart.line.uptrend.xyaxis", 2 },
    { "Exponential Down", "Exponential Down", "chart.line.downtrend.xyaxis", 2 },
    { "Sine", "Sine", "waveform", 4 },
    { "Abs Sine", "Absolute Sine", "waveform", 4 },
    { "Square", "Square", "square.fill", 3 },
    { "Custom", "Custom", "scribble.variable", 0 },
    { "Music", "Music", "music.note", 2 },
    { "Music Trigger Fade", "Music Trigger Fade", "music.note.list", 3 },
    { "Random", "Random", "dice", 2 },
    { "Timing Track Toggle", "Timing Track Toggle", "metronome", 2 },
    { "Timing Track Fade Fixed", "Timing Track Fade Fixed", "metronome.fill", 3 },
    { "Timing Track Fade Proportional", "Timing Track Fade Proportional", "metronome.fill", 3 },
};
static const int kCurveTypeCount = sizeof(kCurveTypes) / sizeof(kCurveTypes[0]);

static const CGFloat kWindowWidth = 700.0;
static const CGFloat kWindowHeight = 550.0;
static const CGFloat kCurveViewHeight = 300.0;

#pragma mark - XLValueCurveView

@interface XLValueCurveView () {
    XLCurvePoint _customPoints[XL_MAX_CURVE_POINTS];
}
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) NSPoint lastMousePoint;
@property (nonatomic, strong) NSMutableArray<NSValue *> *undoStack;
@end

@implementation XLValueCurveView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _curveType = @"Flat";
        _parameter1 = 1.0;
        _parameter2 = 0.0;
        _parameter3 = 0.0;
        _parameter4 = 0.0;
        _wrapValues = NO;
        _minValue = 0.0;
        _maxValue = 100.0;
        _timeOffset = 0.0;
        _editable = YES;
        _selectedPointIndex = -1;
        _customPointCount = 0;
        _undoStack = [NSMutableArray array];

        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor controlBackgroundColor] CGColor];
        self.layer.cornerRadius = 4.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [[NSColor separatorColor] CGColor];
    }
    return self;
}

- (XLCurvePoint *)customPoints {
    return _customPoints;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                options:(NSTrackingMouseEnteredAndExited |
                                                        NSTrackingMouseMoved |
                                                        NSTrackingActiveInKeyWindow)
                                                  owner:self
                                               userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;
    CGFloat margin = 30.0;
    NSRect graphRect = NSInsetRect(bounds, margin, margin);

    // Draw background
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(dirtyRect);

    // Draw grid
    [self drawGridInRect:graphRect];

    // Draw axes
    [self drawAxesInRect:graphRect];

    // Draw the curve
    [self drawCurveInRect:graphRect];

    // Draw custom points if Custom curve type
    if ([_curveType isEqualToString:@"Custom"]) {
        [self drawCustomPointsInRect:graphRect];
    }

    // Draw axis labels
    [self drawLabelsInRect:graphRect margin:margin];
}

- (void)drawGridInRect:(NSRect)rect {
    [[NSColor separatorColor] setStroke];

    NSBezierPath *gridPath = [NSBezierPath bezierPath];
    gridPath.lineWidth = 0.5;

    // Vertical grid lines
    for (int i = 1; i < 10; i++) {
        CGFloat x = rect.origin.x + (rect.size.width * i / 10.0);
        [gridPath moveToPoint:NSMakePoint(x, rect.origin.y)];
        [gridPath lineToPoint:NSMakePoint(x, rect.origin.y + rect.size.height)];
    }

    // Horizontal grid lines
    for (int i = 1; i < 10; i++) {
        CGFloat y = rect.origin.y + (rect.size.height * i / 10.0);
        [gridPath moveToPoint:NSMakePoint(rect.origin.x, y)];
        [gridPath lineToPoint:NSMakePoint(rect.origin.x + rect.size.width, y)];
    }

    CGFloat pattern[] = {2.0, 2.0};
    [gridPath setLineDash:pattern count:2 phase:0];
    [gridPath stroke];
}

- (void)drawAxesInRect:(NSRect)rect {
    [[NSColor labelColor] setStroke];

    NSBezierPath *axesPath = [NSBezierPath bezierPath];
    axesPath.lineWidth = 1.0;

    // X axis
    [axesPath moveToPoint:NSMakePoint(rect.origin.x, rect.origin.y)];
    [axesPath lineToPoint:NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y)];

    // Y axis
    [axesPath moveToPoint:NSMakePoint(rect.origin.x, rect.origin.y)];
    [axesPath lineToPoint:NSMakePoint(rect.origin.x, rect.origin.y + rect.size.height)];

    [axesPath stroke];
}

- (void)drawCurveInRect:(NSRect)rect {
    NSBezierPath *curvePath = [NSBezierPath bezierPath];
    curvePath.lineWidth = 2.0;
    [[NSColor controlAccentColor] setStroke];

    BOOL first = YES;
    for (int i = 0; i <= 200; i++) {
        float x = (float)i / 200.0;
        float y = [self valueAtX:x];

        if (!_wrapValues) {
            y = MAX(0.0, MIN(1.0, y));
        } else {
            while (y > 1.0) y -= 1.0;
            while (y < 0.0) y += 1.0;
        }

        CGFloat screenX = rect.origin.x + (x * rect.size.width);
        CGFloat screenY = rect.origin.y + (y * rect.size.height);

        if (first) {
            [curvePath moveToPoint:NSMakePoint(screenX, screenY)];
            first = NO;
        } else {
            [curvePath lineToPoint:NSMakePoint(screenX, screenY)];
        }
    }

    [curvePath stroke];
}

- (void)drawCustomPointsInRect:(NSRect)rect {
    CGFloat pointRadius = 5.0;

    for (NSInteger i = 0; i < _customPointCount; i++) {
        CGFloat screenX = rect.origin.x + (_customPoints[i].x * rect.size.width);
        CGFloat screenY = rect.origin.y + (_customPoints[i].y * rect.size.height);

        NSRect pointRect = NSMakeRect(screenX - pointRadius, screenY - pointRadius,
                                      pointRadius * 2, pointRadius * 2);

        NSBezierPath *pointPath = [NSBezierPath bezierPathWithOvalInRect:pointRect];

        if (i == _selectedPointIndex) {
            [[NSColor selectedContentBackgroundColor] setFill];
            [[NSColor labelColor] setStroke];
        } else {
            [[NSColor controlAccentColor] setFill];
            [[NSColor controlAccentColor] setStroke];
        }

        [pointPath fill];
        pointPath.lineWidth = 1.0;
        [pointPath stroke];
    }
}

- (void)drawLabelsInRect:(NSRect)rect margin:(CGFloat)margin {
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };

    // Y axis labels
    NSString *maxLabel = [NSString stringWithFormat:@"%.0f", _maxValue];
    NSString *minLabel = [NSString stringWithFormat:@"%.0f", _minValue];

    [maxLabel drawAtPoint:NSMakePoint(5, rect.origin.y + rect.size.height - 5)
           withAttributes:attrs];
    [minLabel drawAtPoint:NSMakePoint(5, rect.origin.y)
           withAttributes:attrs];

    // X axis labels
    [@"0%" drawAtPoint:NSMakePoint(rect.origin.x, 5) withAttributes:attrs];
    [@"100%" drawAtPoint:NSMakePoint(rect.origin.x + rect.size.width - 25, 5) withAttributes:attrs];
}

- (float)valueAtX:(float)x {
    if ([_curveType isEqualToString:@"Flat"]) {
        return _parameter1;
    } else if ([_curveType isEqualToString:@"Ramp"]) {
        return _parameter2 + (_parameter1 - _parameter2) * x;
    } else if ([_curveType isEqualToString:@"Ramp Up/Down"]) {
        if (x < 0.5) {
            return _parameter2 + (_parameter1 - _parameter2) * (x * 2);
        } else {
            return _parameter1 + (_parameter2 - _parameter1) * ((x - 0.5) * 2);
        }
    } else if ([_curveType isEqualToString:@"Saw Tooth"]) {
        float cycles = MAX(1, _parameter2 * 10);
        float phase = fmodf(x * cycles, 1.0);
        return _parameter1 * phase;
    } else if ([_curveType isEqualToString:@"Sine"]) {
        float cycles = MAX(1, _parameter3 * 10);
        float amp = _parameter1 - _parameter2;
        float offset = _parameter2;
        float phase = _parameter4 * M_PI * 2;
        return offset + amp * 0.5 * (1.0 + sinf(x * cycles * M_PI * 2 + phase));
    } else if ([_curveType isEqualToString:@"Abs Sine"]) {
        float cycles = MAX(1, _parameter3 * 10);
        float amp = _parameter1 - _parameter2;
        float offset = _parameter2;
        float phase = _parameter4 * M_PI * 2;
        return offset + amp * fabsf(sinf(x * cycles * M_PI * 2 + phase));
    } else if ([_curveType isEqualToString:@"Square"]) {
        float cycles = MAX(1, _parameter3 * 10);
        float phase = fmodf(x * cycles, 1.0);
        return phase < 0.5 ? _parameter1 : _parameter2;
    } else if ([_curveType isEqualToString:@"Parabolic Down"]) {
        float peak = _parameter1;
        float base = _parameter2;
        float t = 2 * x - 1; // -1 to 1
        return peak - (peak - base) * t * t;
    } else if ([_curveType isEqualToString:@"Parabolic Up"]) {
        float peak = _parameter1;
        float base = _parameter2;
        float t = 2 * x - 1;
        return base + (peak - base) * t * t;
    } else if ([_curveType isEqualToString:@"Exponential Up"]) {
        float top = _parameter1;
        float bottom = _parameter2;
        return bottom + (top - bottom) * (expf(x * 3) - 1) / (expf(3) - 1);
    } else if ([_curveType isEqualToString:@"Exponential Down"]) {
        float top = _parameter1;
        float bottom = _parameter2;
        return top - (top - bottom) * (expf(x * 3) - 1) / (expf(3) - 1);
    } else if ([_curveType isEqualToString:@"Logarithmic Up"]) {
        float top = _parameter1;
        float bottom = _parameter2;
        return bottom + (top - bottom) * logf(1 + x * (M_E - 1));
    } else if ([_curveType isEqualToString:@"Logarithmic Down"]) {
        float top = _parameter1;
        float bottom = _parameter2;
        return top - (top - bottom) * logf(1 + x * (M_E - 1));
    } else if ([_curveType isEqualToString:@"Random"]) {
        // Random curve returns interpolated random values
        // For display, we use a deterministic pseudo-random based on x
        float seed = floorf(x * 100) / 100.0;
        float r = sinf(seed * 12.9898 + 78.233) * 43758.5453;
        r = r - floorf(r);
        return _parameter2 + (_parameter1 - _parameter2) * r;
    } else if ([_curveType isEqualToString:@"Custom"]) {
        return [self customValueAtX:x];
    }

    return 0.5;
}

- (float)customValueAtX:(float)x {
    if (_customPointCount == 0) return 0.5;
    if (_customPointCount == 1) return _customPoints[0].y;

    // Find surrounding points
    NSInteger leftIdx = -1;
    NSInteger rightIdx = -1;

    for (NSInteger i = 0; i < _customPointCount; i++) {
        if (_customPoints[i].x <= x) {
            leftIdx = i;
        }
        if (_customPoints[i].x >= x && rightIdx == -1) {
            rightIdx = i;
        }
    }

    if (leftIdx == -1) return _customPoints[0].y;
    if (rightIdx == -1) return _customPoints[_customPointCount - 1].y;
    if (leftIdx == rightIdx) return _customPoints[leftIdx].y;

    // Linear interpolation
    float x1 = _customPoints[leftIdx].x;
    float y1 = _customPoints[leftIdx].y;
    float x2 = _customPoints[rightIdx].x;
    float y2 = _customPoints[rightIdx].y;

    if (x2 == x1) return y1;

    float t = (x - x1) / (x2 - x1);
    return y1 + (y2 - y1) * t;
}

- (void)addPointAtX:(float)x y:(float)y {
    if (_customPointCount >= XL_MAX_CURVE_POINTS) return;

    // Save undo state
    [self saveUndoState];

    // Insert in sorted order by x
    NSInteger insertIdx = _customPointCount;
    for (NSInteger i = 0; i < _customPointCount; i++) {
        if (_customPoints[i].x > x) {
            insertIdx = i;
            break;
        }
    }

    // Shift points right
    for (NSInteger i = _customPointCount; i > insertIdx; i--) {
        _customPoints[i] = _customPoints[i - 1];
    }

    _customPoints[insertIdx].x = x;
    _customPoints[insertIdx].y = y;
    _customPointCount++;

    _selectedPointIndex = insertIdx;

    [self setNeedsDisplay:YES];
    [_delegate valueCurveViewDidChange:self];
}

- (void)removePointAtIndex:(NSInteger)index {
    if (index < 0 || index >= _customPointCount) return;

    [self saveUndoState];

    for (NSInteger i = index; i < _customPointCount - 1; i++) {
        _customPoints[i] = _customPoints[i + 1];
    }
    _customPointCount--;

    if (_selectedPointIndex == index) {
        _selectedPointIndex = -1;
    } else if (_selectedPointIndex > index) {
        _selectedPointIndex--;
    }

    [self setNeedsDisplay:YES];
    [_delegate valueCurveViewDidChange:self];
}

- (void)deleteSelectedPoint {
    [self removePointAtIndex:_selectedPointIndex];
}

- (void)saveUndoState {
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&_customPointCount length:sizeof(_customPointCount)];
    [data appendBytes:_customPoints length:sizeof(XLCurvePoint) * _customPointCount];
    [_undoStack addObject:data];

    // Limit undo stack
    while (_undoStack.count > 50) {
        [_undoStack removeObjectAtIndex:0];
    }
}

- (void)undo {
    if (_undoStack.count == 0) return;

    NSData *data = _undoStack.lastObject;
    [_undoStack removeLastObject];

    const void *bytes = data.bytes;
    memcpy(&_customPointCount, bytes, sizeof(_customPointCount));
    memcpy(_customPoints, bytes + sizeof(_customPointCount), sizeof(XLCurvePoint) * _customPointCount);

    _selectedPointIndex = -1;
    [self setNeedsDisplay:YES];
    [_delegate valueCurveViewDidChange:self];
}

- (void)flipHorizontal {
    if (![_curveType isEqualToString:@"Custom"]) return;

    [self saveUndoState];

    for (NSInteger i = 0; i < _customPointCount; i++) {
        _customPoints[i].x = 1.0 - _customPoints[i].x;
    }

    // Re-sort by x
    for (NSInteger i = 0; i < _customPointCount - 1; i++) {
        for (NSInteger j = i + 1; j < _customPointCount; j++) {
            if (_customPoints[i].x > _customPoints[j].x) {
                XLCurvePoint temp = _customPoints[i];
                _customPoints[i] = _customPoints[j];
                _customPoints[j] = temp;
            }
        }
    }

    [self setNeedsDisplay:YES];
    [_delegate valueCurveViewDidChange:self];
}

- (void)flipVertical {
    if (![_curveType isEqualToString:@"Custom"]) {
        // For non-custom, swap parameter1 and parameter2
        float temp = _parameter1;
        _parameter1 = _parameter2;
        _parameter2 = temp;
    } else {
        [self saveUndoState];
        for (NSInteger i = 0; i < _customPointCount; i++) {
            _customPoints[i].y = 1.0 - _customPoints[i].y;
        }
    }

    [self setNeedsDisplay:YES];
    [_delegate valueCurveViewDidChange:self];
}

- (void)reverse {
    [self flipHorizontal];
    [self flipVertical];
}

#pragma mark - Mouse Handling

- (void)mouseDown:(NSEvent *)event {
    if (!_editable) return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect bounds = self.bounds;
    CGFloat margin = 30.0;
    NSRect graphRect = NSInsetRect(bounds, margin, margin);

    float x = (point.x - graphRect.origin.x) / graphRect.size.width;
    float y = (point.y - graphRect.origin.y) / graphRect.size.height;

    x = MAX(0, MIN(1, x));
    y = MAX(0, MIN(1, y));

    if ([_curveType isEqualToString:@"Custom"]) {
        // Check if clicking on existing point
        _selectedPointIndex = -1;
        CGFloat hitRadius = 10.0;

        for (NSInteger i = 0; i < _customPointCount; i++) {
            CGFloat px = graphRect.origin.x + (_customPoints[i].x * graphRect.size.width);
            CGFloat py = graphRect.origin.y + (_customPoints[i].y * graphRect.size.height);

            if (hypot(point.x - px, point.y - py) < hitRadius) {
                _selectedPointIndex = i;
                break;
            }
        }

        if (_selectedPointIndex == -1 && event.clickCount == 2) {
            // Double-click adds a point
            [self addPointAtX:x y:y];
        } else if (_selectedPointIndex >= 0) {
            _isDragging = YES;
            _lastMousePoint = point;
            [_delegate valueCurveView:self didSelectPointAtIndex:_selectedPointIndex];
        }
    }

    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_editable || !_isDragging || _selectedPointIndex < 0) return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect bounds = self.bounds;
    CGFloat margin = 30.0;
    NSRect graphRect = NSInsetRect(bounds, margin, margin);

    float x = (point.x - graphRect.origin.x) / graphRect.size.width;
    float y = (point.y - graphRect.origin.y) / graphRect.size.height;

    x = MAX(0, MIN(1, x));
    y = MAX(0, MIN(1, y));

    // Don't allow crossing other points
    if (_selectedPointIndex > 0) {
        x = MAX(x, _customPoints[_selectedPointIndex - 1].x + 0.001);
    }
    if (_selectedPointIndex < _customPointCount - 1) {
        x = MIN(x, _customPoints[_selectedPointIndex + 1].x - 0.001);
    }

    _customPoints[_selectedPointIndex].x = x;
    _customPoints[_selectedPointIndex].y = y;

    _lastMousePoint = point;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (_isDragging) {
        _isDragging = NO;
        [_delegate valueCurveViewDidChange:self];
    }
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 51 || event.keyCode == 117) { // Delete or Backspace
        [self deleteSelectedPoint];
    } else if (event.modifierFlags & NSEventModifierFlagCommand && event.keyCode == 6) { // Cmd+Z
        [self undo];
    } else {
        [super keyDown:event];
    }
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

@end

#pragma mark - XLValueCurvePanel

@interface XLValueCurvePanel () <XLValueCurveViewDelegate>
@property (nonatomic, strong) NSStackView *mainStack;
@property (nonatomic, strong) NSTextField *param1Label;
@property (nonatomic, strong) NSTextField *param2Label;
@property (nonatomic, strong) NSTextField *param3Label;
@property (nonatomic, strong) NSTextField *param4Label;
@property (nonatomic, strong) NSTextField *param1ValueLabel;
@property (nonatomic, strong) NSTextField *param2ValueLabel;
@property (nonatomic, strong) NSTextField *param3ValueLabel;
@property (nonatomic, strong) NSTextField *param4ValueLabel;
@end

@implementation XLValueCurvePanel

- (instancetype)initWithCurveData:(NSString *)curveData
                         minValue:(float)minValue
                         maxValue:(float)maxValue {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        [self setupUI];
        _curveView.minValue = minValue;
        _curveView.maxValue = maxValue;
        [self setCurveDataString:curveData];
    }
    return self;
}

- (void)setupUI {
    _mainStack = [[NSStackView alloc] init];
    _mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    _mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _mainStack.spacing = 12;
    [self addSubview:_mainStack];

    // Curve type selector
    NSStackView *typeRow = [[NSStackView alloc] init];
    typeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    typeRow.spacing = 8;

    NSTextField *typeLabel = [NSTextField labelWithString:@"Curve Type:"];
    _curveTypePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (int i = 0; i < kCurveTypeCount; i++) {
        [_curveTypePopup addItemWithTitle:[NSString stringWithUTF8String:kCurveTypes[i].displayName]];
    }
    [_curveTypePopup setTarget:self];
    [_curveTypePopup setAction:@selector(curveTypeChanged:)];

    [typeRow addArrangedSubview:typeLabel];
    [typeRow addArrangedSubview:_curveTypePopup];
    [_mainStack addArrangedSubview:typeRow];

    // Curve view
    _curveView = [[XLValueCurveView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    _curveView.delegate = self;
    _curveView.translatesAutoresizingMaskIntoConstraints = NO;
    [_mainStack addArrangedSubview:_curveView];

    [NSLayoutConstraint activateConstraints:@[
        [_curveView.heightAnchor constraintEqualToConstant:200],
    ]];

    // Parameter sliders
    [self addParameterRow:1 label:@"Parameter 1:" slider:&_parameter1Slider
                labelField:&_param1Label valueField:&_param1ValueLabel];
    [self addParameterRow:2 label:@"Parameter 2:" slider:&_parameter2Slider
                labelField:&_param2Label valueField:&_param2ValueLabel];
    [self addParameterRow:3 label:@"Parameter 3:" slider:&_parameter3Slider
                labelField:&_param3Label valueField:&_param3ValueLabel];
    [self addParameterRow:4 label:@"Parameter 4:" slider:&_parameter4Slider
                labelField:&_param4Label valueField:&_param4ValueLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_mainStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_mainStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [_mainStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [_mainStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
    ]];

    [self updateParameterVisibility];
}

- (void)addParameterRow:(int)num
                  label:(NSString *)labelText
                 slider:(NSSlider *__strong *)slider
             labelField:(NSTextField *__strong *)labelField
             valueField:(NSTextField *__strong *)valueField {
    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;

    *labelField = [NSTextField labelWithString:labelText];
    (*labelField).translatesAutoresizingMaskIntoConstraints = NO;
    [(*labelField).widthAnchor constraintEqualToConstant:100].active = YES;

    *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    (*slider).minValue = 0;
    (*slider).maxValue = 100;
    (*slider).integerValue = 50;
    (*slider).tag = num;
    [*slider setTarget:self];
    [*slider setAction:@selector(sliderChanged:)];

    *valueField = [NSTextField labelWithString:@"50"];
    (*valueField).translatesAutoresizingMaskIntoConstraints = NO;
    [(*valueField).widthAnchor constraintEqualToConstant:40].active = YES;

    [row addArrangedSubview:*labelField];
    [row addArrangedSubview:*slider];
    [row addArrangedSubview:*valueField];
    [_mainStack addArrangedSubview:row];
}

- (void)curveTypeChanged:(id)sender {
    NSInteger idx = _curveTypePopup.indexOfSelectedItem;
    if (idx >= 0 && idx < kCurveTypeCount) {
        _curveView.curveType = [NSString stringWithUTF8String:kCurveTypes[idx].typeId];
        [self updateParameterVisibility];
        [_curveView setNeedsDisplay:YES];
        [self notifyChange];
    }
}

- (void)sliderChanged:(NSSlider *)slider {
    float value = slider.floatValue / 100.0;

    switch (slider.tag) {
        case 1:
            _curveView.parameter1 = value;
            _param1ValueLabel.stringValue = [NSString stringWithFormat:@"%.0f", slider.floatValue];
            break;
        case 2:
            _curveView.parameter2 = value;
            _param2ValueLabel.stringValue = [NSString stringWithFormat:@"%.0f", slider.floatValue];
            break;
        case 3:
            _curveView.parameter3 = value;
            _param3ValueLabel.stringValue = [NSString stringWithFormat:@"%.0f", slider.floatValue];
            break;
        case 4:
            _curveView.parameter4 = value;
            _param4ValueLabel.stringValue = [NSString stringWithFormat:@"%.0f", slider.floatValue];
            break;
    }

    [_curveView setNeedsDisplay:YES];
    [self notifyChange];
}

- (void)updateParameterVisibility {
    NSInteger idx = _curveTypePopup.indexOfSelectedItem;
    int paramCount = 0;
    if (idx >= 0 && idx < kCurveTypeCount) {
        paramCount = kCurveTypes[idx].parameterCount;
    }

    _param1Label.superview.hidden = (paramCount < 1);
    _param2Label.superview.hidden = (paramCount < 2);
    _param3Label.superview.hidden = (paramCount < 3);
    _param4Label.superview.hidden = (paramCount < 4);
}

- (void)notifyChange {
    if (_target && _action) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_target performSelector:_action withObject:self];
#pragma clang diagnostic pop
    }
}

- (NSString *)curveDataString {
    NSMutableString *result = [NSMutableString stringWithString:_curveView.curveType];

    [result appendFormat:@"|%.2f", _curveView.parameter1 * 100];
    [result appendFormat:@"|%.2f", _curveView.parameter2 * 100];
    [result appendFormat:@"|%.2f", _curveView.parameter3 * 100];
    [result appendFormat:@"|%.2f", _curveView.parameter4 * 100];

    if ([_curveView.curveType isEqualToString:@"Custom"]) {
        for (NSInteger i = 0; i < _curveView.customPointCount; i++) {
            [result appendFormat:@"|%.4f,%.4f",
             _curveView.customPoints[i].x, _curveView.customPoints[i].y];
        }
    }

    return result;
}

- (void)setCurveDataString:(NSString *)curveData {
    if (!curveData || curveData.length == 0) {
        _curveView.curveType = @"Flat";
        _curveView.parameter1 = 1.0;
        return;
    }

    NSArray *parts = [curveData componentsSeparatedByString:@"|"];
    if (parts.count == 0) return;

    // Set curve type
    NSString *typeStr = parts[0];
    _curveView.curveType = typeStr;

    // Select in popup
    for (int i = 0; i < kCurveTypeCount; i++) {
        if ([typeStr isEqualToString:[NSString stringWithUTF8String:kCurveTypes[i].typeId]]) {
            [_curveTypePopup selectItemAtIndex:i];
            break;
        }
    }

    // Set parameters
    if (parts.count > 1) {
        _curveView.parameter1 = [parts[1] floatValue] / 100.0;
        _parameter1Slider.floatValue = [parts[1] floatValue];
        _param1ValueLabel.stringValue = [NSString stringWithFormat:@"%.0f", [parts[1] floatValue]];
    }
    if (parts.count > 2) {
        _curveView.parameter2 = [parts[2] floatValue] / 100.0;
        _parameter2Slider.floatValue = [parts[2] floatValue];
        _param2ValueLabel.stringValue = [NSString stringWithFormat:@"%.0f", [parts[2] floatValue]];
    }
    if (parts.count > 3) {
        _curveView.parameter3 = [parts[3] floatValue] / 100.0;
        _parameter3Slider.floatValue = [parts[3] floatValue];
        _param3ValueLabel.stringValue = [NSString stringWithFormat:@"%.0f", [parts[3] floatValue]];
    }
    if (parts.count > 4) {
        _curveView.parameter4 = [parts[4] floatValue] / 100.0;
        _parameter4Slider.floatValue = [parts[4] floatValue];
        _param4ValueLabel.stringValue = [NSString stringWithFormat:@"%.0f", [parts[4] floatValue]];
    }

    // Parse custom points
    if ([typeStr isEqualToString:@"Custom"] && parts.count > 5) {
        _curveView.customPointCount = 0;
        for (NSUInteger i = 5; i < parts.count && _curveView.customPointCount < XL_MAX_CURVE_POINTS; i++) {
            NSArray *coords = [parts[i] componentsSeparatedByString:@","];
            if (coords.count == 2) {
                _curveView.customPoints[_curveView.customPointCount].x = [coords[0] floatValue];
                _curveView.customPoints[_curveView.customPointCount].y = [coords[1] floatValue];
                _curveView.customPointCount++;
            }
        }
    }

    [self updateParameterVisibility];
    [_curveView setNeedsDisplay:YES];
}

#pragma mark - XLValueCurveViewDelegate

- (void)valueCurveViewDidChange:(XLValueCurveView *)view {
    [self notifyChange];
}

- (void)valueCurveView:(XLValueCurveView *)view didSelectPointAtIndex:(NSInteger)index {
    // Could update a status display
}

@end

#pragma mark - XLValueCurveWindow

@interface XLValueCurveWindow () <XLValueCurveViewDelegate>
@property (nonatomic, strong) XLValueCurvePanel *curvePanel;
@property (nonatomic, strong) NSScrollView *presetsScrollView;
@property (nonatomic, strong) NSStackView *presetsStack;
@property (nonatomic, strong) NSButton *wrapValuesCheckbox;
@property (nonatomic, strong) NSButton *flipButton;
@property (nonatomic, strong) NSButton *reverseButton;
@property (nonatomic, strong) NSButton *loadButton;
@property (nonatomic, strong) NSButton *exportButton;
@property (nonatomic, copy) XLValueCurveCompletion completion;
@property (nonatomic, copy) NSString *originalCurveData;
@property (nonatomic, assign) float minValue;
@property (nonatomic, assign) float maxValue;
@end

@implementation XLValueCurveWindow

- (instancetype)initWithCurveData:(NSString *)curveData
                         minValue:(float)minValue
                         maxValue:(float)maxValue {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowWidth, kWindowHeight)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Value Curve Editor";
    window.minSize = NSMakeSize(500, 400);

    self = [super initWithWindow:window];
    if (self) {
        _originalCurveData = [curveData copy];
        _minValue = minValue;
        _maxValue = maxValue;
        _wasModified = NO;

        [self buildUI];
        [_curvePanel setCurveDataString:curveData];
    }
    return self;
}

- (void)buildUI {
    NSView *contentView = self.window.contentView;

    // Main vertical stack
    NSStackView *mainStack = [[NSStackView alloc] init];
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.spacing = 16;
    mainStack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    [contentView addSubview:mainStack];

    // Curve panel
    _curvePanel = [[XLValueCurvePanel alloc] initWithCurveData:nil
                                                      minValue:_minValue
                                                      maxValue:_maxValue];
    _curvePanel.target = self;
    _curvePanel.action = @selector(curveDidChange:);
    [mainStack addArrangedSubview:_curvePanel];

    // Wrap values checkbox
    _wrapValuesCheckbox = [NSButton checkboxWithTitle:@"Wrap values (allow values outside 0-100%)"
                                               target:self action:@selector(wrapValuesChanged:)];
    [mainStack addArrangedSubview:_wrapValuesCheckbox];

    // Toolbar buttons
    NSStackView *toolbar = [[NSStackView alloc] init];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 8;

    _flipButton = [NSButton buttonWithTitle:@"Flip" target:self action:@selector(flipClicked:)];
    _reverseButton = [NSButton buttonWithTitle:@"Reverse" target:self action:@selector(reverseClicked:)];
    _loadButton = [NSButton buttonWithTitle:@"Load Preset..." target:self action:@selector(loadClicked:)];
    _exportButton = [NSButton buttonWithTitle:@"Export..." target:self action:@selector(exportClicked:)];

    [toolbar addArrangedSubview:_flipButton];
    [toolbar addArrangedSubview:_reverseButton];
    [toolbar addArrangedSubview:[[NSView alloc] init]]; // Spacer
    [toolbar addArrangedSubview:_loadButton];
    [toolbar addArrangedSubview:_exportButton];

    [mainStack addArrangedSubview:toolbar];

    // Presets section
    NSTextField *presetsLabel = [NSTextField labelWithString:@"Presets"];
    presetsLabel.font = [NSFont boldSystemFontOfSize:13];
    [mainStack addArrangedSubview:presetsLabel];

    _presetsScrollView = [[NSScrollView alloc] init];
    _presetsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _presetsScrollView.hasHorizontalScroller = YES;
    _presetsScrollView.hasVerticalScroller = NO;
    _presetsScrollView.borderType = NSNoBorder;

    _presetsStack = [[NSStackView alloc] init];
    _presetsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _presetsStack.spacing = 8;
    _presetsScrollView.documentView = _presetsStack;

    [self populatePresets];
    [mainStack addArrangedSubview:_presetsScrollView];

    // Bottom buttons
    NSStackView *bottomBar = [[NSStackView alloc] init];
    bottomBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bottomBar.spacing = 12;

    NSButton *cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelClicked:)];
    cancelButton.keyEquivalent = @"\033";

    NSButton *okButton = [NSButton buttonWithTitle:@"OK" target:self action:@selector(okClicked:)];
    okButton.keyEquivalent = @"\r";

    [bottomBar addArrangedSubview:[[NSView alloc] init]]; // Spacer
    [bottomBar addArrangedSubview:cancelButton];
    [bottomBar addArrangedSubview:okButton];

    [mainStack addArrangedSubview:bottomBar];

    [NSLayoutConstraint activateConstraints:@[
        [mainStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [mainStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [mainStack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [mainStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

        [_presetsScrollView.heightAnchor constraintEqualToConstant:80],
    ]];
}

- (void)populatePresets {
    // Add preset buttons for common curves
    NSArray *presets = @[
        @[@"Flat|100", @"Flat 100%"],
        @[@"Flat|50", @"Flat 50%"],
        @[@"Ramp|100|0", @"Ramp Up"],
        @[@"Ramp|0|100", @"Ramp Down"],
        @[@"Ramp Up/Down|100|0", @"Peak"],
        @[@"Sine|100|0|10|0", @"Sine"],
        @[@"Square|100|0|10", @"Square"],
        @[@"Saw Tooth|100|10", @"Saw Tooth"],
        @[@"Parabolic Down|100|0", @"Parabolic"],
        @[@"Exponential Up|100|0", @"Exponential"],
    ];

    for (NSArray *preset in presets) {
        NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 70, 60)];
        btn.title = preset[1];
        btn.bezelStyle = NSBezelStyleRounded;
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [btn.widthAnchor constraintEqualToConstant:70].active = YES;
        [btn.heightAnchor constraintEqualToConstant:60].active = YES;

        btn.tag = [presets indexOfObject:preset];
        [btn setTarget:self];
        [btn setAction:@selector(presetClicked:)];

        [_presetsStack addArrangedSubview:btn];
    }
}

- (void)showWithCompletion:(XLValueCurveCompletion)completion {
    _completion = completion;
    [self.window center];
    [self showWindow:nil];
}

- (NSString *)curveDataString {
    return [_curvePanel curveDataString];
}

#pragma mark - Actions

- (void)curveDidChange:(id)sender {
    _wasModified = YES;
}

- (void)wrapValuesChanged:(id)sender {
    _curvePanel.curveView.wrapValues = (_wrapValuesCheckbox.state == NSControlStateValueOn);
    [_curvePanel.curveView setNeedsDisplay:YES];
    _wasModified = YES;
}

- (void)flipClicked:(id)sender {
    [_curvePanel.curveView flipVertical];
    _wasModified = YES;
}

- (void)reverseClicked:(id)sender {
    [_curvePanel.curveView reverse];
    _wasModified = YES;
}

- (void)loadClicked:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"xvc"]];
    panel.message = @"Select a value curve preset file";

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            NSString *contents = [NSString stringWithContentsOfURL:panel.URL
                                                          encoding:NSUTF8StringEncoding
                                                             error:nil];
            if (contents) {
                [self.curvePanel setCurveDataString:contents];
                self->_wasModified = YES;
            }
        }
    }];
}

- (void)exportClicked:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"xvc"]];
    panel.nameFieldStringValue = @"curve.xvc";

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            NSString *curveData = [self.curvePanel curveDataString];
            [curveData writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }];
}

- (void)presetClicked:(NSButton *)sender {
    NSArray *presets = @[
        @"Flat|100",
        @"Flat|50",
        @"Ramp|100|0",
        @"Ramp|0|100",
        @"Ramp Up/Down|100|0",
        @"Sine|100|0|10|0",
        @"Square|100|0|10",
        @"Saw Tooth|100|10",
        @"Parabolic Down|100|0",
        @"Exponential Up|100|0",
    ];

    NSInteger idx = sender.tag;
    if (idx >= 0 && idx < (NSInteger)presets.count) {
        [_curvePanel setCurveDataString:presets[idx]];
        _wasModified = YES;
    }
}

- (void)cancelClicked:(id)sender {
    [self.window close];
    if (_completion) {
        _completion(NO);
    }
}

- (void)okClicked:(id)sender {
    [self.window close];
    if (_completion) {
        _completion(_wasModified);
    }
}

@end
