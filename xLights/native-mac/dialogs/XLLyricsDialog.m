/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLLyricsDialog.h"

@interface XLLyricsDialog ()

@property (nonatomic, strong) NSScrollView *textScrollView;
@property (nonatomic, strong) NSTextField *startTimeField;
@property (nonatomic, strong) NSTextField *endTimeField;
@property (nonatomic, strong) NSTextField *warningLabel;

@end

@implementation XLLyricsDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Type or Paste Lyrics";
        self.minWidth = 450;
        self.minHeight = 400;
        _lyricsText = @"";
        _startTime = 0.0;
        _endTime = 0.0;
        _sequenceDurationMs = 0;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Text view for lyrics
    _textScrollView = [XLBaseSheetController createTextViewWithHeight:200];
    [_textScrollView.widthAnchor constraintGreaterThanOrEqualToConstant:380].active = YES;

    NSTextView *textView = [XLBaseSheetController textViewFromScrollView:_textScrollView];
    textView.string = _lyricsText;

    [stack addArrangedSubview:_textScrollView];
    [_textScrollView.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [_textScrollView.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    // Time fields
    NSStackView *timeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    timeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    timeRow.spacing = 16;

    // Start time
    NSTextField *startLabel = [NSTextField labelWithString:@"Start Time (sec):"];
    _startTimeField = [XLBaseSheetController createTextField];
    _startTimeField.stringValue = [NSString stringWithFormat:@"%.3f", _startTime];
    [_startTimeField.widthAnchor constraintEqualToConstant:80].active = YES;

    [timeRow addArrangedSubview:startLabel];
    [timeRow addArrangedSubview:_startTimeField];

    // End time
    NSTextField *endLabel = [NSTextField labelWithString:@"End Time (sec):"];
    _endTimeField = [XLBaseSheetController createTextField];
    _endTimeField.stringValue = [NSString stringWithFormat:@"%.3f", _endTime];
    [_endTimeField.widthAnchor constraintEqualToConstant:80].active = YES;

    [timeRow addArrangedSubview:endLabel];
    [timeRow addArrangedSubview:_endTimeField];

    [stack addArrangedSubview:timeRow];

    // Warning label
    _warningLabel = [NSTextField wrappingLabelWithString:@"Caution: All timings/labels on this track will be replaced."];
    _warningLabel.textColor = [NSColor secondaryLabelColor];
    _warningLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:_warningLabel];
    [_warningLabel.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [_warningLabel.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    return stack;
}

- (void)sheetDidLoad {
    // Set initial values
    _endTimeField.stringValue = [NSString stringWithFormat:@"%.3f", (double)_sequenceDurationMs / 1000.0];

    // Focus the text view
    NSTextView *textView = [XLBaseSheetController textViewFromScrollView:_textScrollView];
    [self.sheet makeFirstResponder:textView];
}

- (NSString *)validate {
    double start = [_startTimeField doubleValue];
    double end = [_endTimeField doubleValue];

    if (start < 0) {
        return @"Start time cannot be negative.";
    }

    if (end <= start) {
        return @"End time must be greater than start time.";
    }

    if (_sequenceDurationMs > 0 && end > (double)_sequenceDurationMs / 1000.0) {
        return @"End time cannot exceed sequence duration.";
    }

    return nil;
}

- (void)okClicked:(id)sender {
    NSTextView *textView = [XLBaseSheetController textViewFromScrollView:_textScrollView];
    _lyricsText = textView.string ?: @"";
    _startTime = [_startTimeField doubleValue];
    _endTime = [_endTimeField doubleValue];

    [super okClicked:sender];
}

@end
