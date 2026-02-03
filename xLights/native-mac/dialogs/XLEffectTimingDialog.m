/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLEffectTimingDialog.h"

static const CGFloat kLabelWidth = 100.0;

@interface XLEffectTimingDialog ()

@property (nonatomic, strong) NSTextField *startTimeField;
@property (nonatomic, strong) NSTextField *endTimeField;
@property (nonatomic, strong) NSTextField *durationLabel;
@property (nonatomic, strong) NSStepper *startStepper;
@property (nonatomic, strong) NSStepper *endStepper;

@end

@implementation XLEffectTimingDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Effect Timing";
        self.minWidth = 350;
        self.minHeight = 180;
        _startTimeMs = 0;
        _endTimeMs = 1000;
        _sequenceDurationMs = 60000;
        _frameIntervalMs = 50;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Effect name (if provided)
    if (_effectName && _effectName.length > 0) {
        NSTextField *nameLabel = [NSTextField labelWithString:
            [NSString stringWithFormat:@"Effect: %@", _effectName]];
        nameLabel.font = [NSFont boldSystemFontOfSize:12];
        [stack addArrangedSubview:nameLabel];
    }

    // Start time row
    NSStackView *startRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    startRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    startRow.spacing = 8;

    NSTextField *startLabel = [NSTextField labelWithString:@"Start Time:"];
    startLabel.alignment = NSTextAlignmentRight;
    [startLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _startTimeField = [XLBaseSheetController createTextField];
    _startTimeField.stringValue = [self formatTime:_startTimeMs];
    [_startTimeField setTarget:self];
    [_startTimeField setAction:@selector(timeFieldChanged:)];
    [_startTimeField.widthAnchor constraintEqualToConstant:100].active = YES;

    _startStepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    _startStepper.minValue = 0;
    _startStepper.maxValue = _sequenceDurationMs;
    _startStepper.increment = _frameIntervalMs;
    _startStepper.integerValue = _startTimeMs;
    [_startStepper setTarget:self];
    [_startStepper setAction:@selector(startStepperChanged:)];

    NSTextField *startHint = [NSTextField labelWithString:@"(mm:ss.ms)"];
    startHint.textColor = [NSColor secondaryLabelColor];
    startHint.font = [NSFont systemFontOfSize:10];

    [startRow addArrangedSubview:startLabel];
    [startRow addArrangedSubview:_startTimeField];
    [startRow addArrangedSubview:_startStepper];
    [startRow addArrangedSubview:startHint];
    [stack addArrangedSubview:startRow];

    // End time row
    NSStackView *endRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    endRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    endRow.spacing = 8;

    NSTextField *endLabel = [NSTextField labelWithString:@"End Time:"];
    endLabel.alignment = NSTextAlignmentRight;
    [endLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _endTimeField = [XLBaseSheetController createTextField];
    _endTimeField.stringValue = [self formatTime:_endTimeMs];
    [_endTimeField setTarget:self];
    [_endTimeField setAction:@selector(timeFieldChanged:)];
    [_endTimeField.widthAnchor constraintEqualToConstant:100].active = YES;

    _endStepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    _endStepper.minValue = 0;
    _endStepper.maxValue = _sequenceDurationMs;
    _endStepper.increment = _frameIntervalMs;
    _endStepper.integerValue = _endTimeMs;
    [_endStepper setTarget:self];
    [_endStepper setAction:@selector(endStepperChanged:)];

    NSTextField *endHint = [NSTextField labelWithString:@"(mm:ss.ms)"];
    endHint.textColor = [NSColor secondaryLabelColor];
    endHint.font = [NSFont systemFontOfSize:10];

    [endRow addArrangedSubview:endLabel];
    [endRow addArrangedSubview:_endTimeField];
    [endRow addArrangedSubview:_endStepper];
    [endRow addArrangedSubview:endHint];
    [stack addArrangedSubview:endRow];

    // Duration label
    _durationLabel = [NSTextField labelWithString:@"Duration: 0:00.000"];
    _durationLabel.textColor = [NSColor secondaryLabelColor];
    [self updateDurationLabel];

    NSStackView *durationRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    durationRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    durationRow.spacing = 8;

    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer.widthAnchor constraintEqualToConstant:kLabelWidth + 8].active = YES;

    [durationRow addArrangedSubview:spacer];
    [durationRow addArrangedSubview:_durationLabel];
    [stack addArrangedSubview:durationRow];

    return stack;
}

- (NSString *)formatTime:(NSInteger)ms {
    NSInteger totalSeconds = ms / 1000;
    NSInteger minutes = totalSeconds / 60;
    NSInteger seconds = totalSeconds % 60;
    NSInteger millis = ms % 1000;

    return [NSString stringWithFormat:@"%ld:%02ld.%03ld", (long)minutes, (long)seconds, (long)millis];
}

- (NSInteger)parseTime:(NSString *)timeStr {
    // Parse mm:ss.ms format
    NSInteger minutes = 0, seconds = 0, millis = 0;

    NSArray<NSString *> *parts = [timeStr componentsSeparatedByString:@":"];
    if (parts.count == 2) {
        minutes = [parts[0] integerValue];
        NSArray<NSString *> *secParts = [parts[1] componentsSeparatedByString:@"."];
        if (secParts.count == 2) {
            seconds = [secParts[0] integerValue];
            millis = [secParts[1] integerValue];
        } else {
            seconds = [parts[1] integerValue];
        }
    } else if (parts.count == 1) {
        NSArray<NSString *> *secParts = [timeStr componentsSeparatedByString:@"."];
        if (secParts.count == 2) {
            seconds = [secParts[0] integerValue];
            millis = [secParts[1] integerValue];
        } else {
            seconds = [timeStr integerValue];
        }
    }

    return (minutes * 60 + seconds) * 1000 + millis;
}

- (void)updateDurationLabel {
    NSInteger startMs = [self parseTime:_startTimeField.stringValue];
    NSInteger endMs = [self parseTime:_endTimeField.stringValue];
    NSInteger duration = endMs - startMs;

    _durationLabel.stringValue = [NSString stringWithFormat:@"Duration: %@",
                                   [self formatTime:MAX(0, duration)]];
}

#pragma mark - Actions

- (void)startStepperChanged:(id)sender {
    _startTimeField.stringValue = [self formatTime:_startStepper.integerValue];
    [self updateDurationLabel];
    [self updateOKButtonState];
}

- (void)endStepperChanged:(id)sender {
    _endTimeField.stringValue = [self formatTime:_endStepper.integerValue];
    [self updateDurationLabel];
    [self updateOKButtonState];
}

- (void)timeFieldChanged:(id)sender {
    NSTextField *field = (NSTextField *)sender;
    NSInteger ms = [self parseTime:field.stringValue];

    // Snap to frame interval
    ms = (ms / _frameIntervalMs) * _frameIntervalMs;

    field.stringValue = [self formatTime:ms];

    if (field == _startTimeField) {
        _startStepper.integerValue = ms;
    } else {
        _endStepper.integerValue = ms;
    }

    [self updateDurationLabel];
    [self updateOKButtonState];
}

#pragma mark - Validation

- (NSString *)validate {
    NSInteger startMs = [self parseTime:_startTimeField.stringValue];
    NSInteger endMs = [self parseTime:_endTimeField.stringValue];

    if (startMs < 0) {
        return @"Start time cannot be negative.";
    }

    if (endMs <= startMs) {
        return @"End time must be greater than start time.";
    }

    if (endMs > _sequenceDurationMs) {
        return @"End time cannot exceed sequence duration.";
    }

    return nil;
}

- (void)okClicked:(id)sender {
    _startTimeMs = [self parseTime:_startTimeField.stringValue];
    _endTimeMs = [self parseTime:_endTimeField.stringValue];
    [super okClicked:sender];
}

@end
