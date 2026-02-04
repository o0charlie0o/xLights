/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLNewTimingDialog.h"

static const CGFloat kLabelWidth = 100.0;

@interface XLNewTimingDialog ()

@property (nonatomic, strong) NSTextField *trackNameField;
@property (nonatomic, strong) NSPopUpButton *intervalPopup;

@end

@implementation XLNewTimingDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"New Timing Track";
        self.okButtonTitle = @"Create";
        self.minWidth = 350;
        self.minHeight = 180;
        _trackName = @"New Timing";
        _selectedInterval = XLTimingIntervalEmpty;
    }
    return self;
}

+ (NSString *)displayNameForInterval:(XLTimingInterval)interval {
    switch (interval) {
        case XLTimingIntervalEmpty: return @"Empty";
        case XLTimingInterval25ms: return @"25ms";
        case XLTimingInterval50ms: return @"50ms";
        case XLTimingInterval100ms: return @"100ms";
        case XLTimingIntervalMetronome: return @"Metronome";
        case XLTimingIntervalMetronomeWithTags: return @"Metronome w/ Tags";
        case XLTimingIntervalFPPCommands: return @"FPP Commands";
        case XLTimingIntervalFPPEffects: return @"FPP Effects";
    }
    return @"Unknown";
}

+ (NSString *)timingNameForInterval:(XLTimingInterval)interval {
    switch (interval) {
        case XLTimingIntervalEmpty: return nil;
        case XLTimingInterval25ms: return @"25ms";
        case XLTimingInterval50ms: return @"50ms";
        case XLTimingInterval100ms: return @"100ms";
        case XLTimingIntervalMetronome: return @"Metronome";
        case XLTimingIntervalMetronomeWithTags: return @"Metronome w/ Tags";
        case XLTimingIntervalFPPCommands: return @"FPP Commands";
        case XLTimingIntervalFPPEffects: return @"FPP Effects";
    }
    return nil;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Track name field
    _trackNameField = [XLBaseSheetController createTextField];
    _trackNameField.stringValue = _trackName;
    [_trackNameField.widthAnchor constraintEqualToConstant:200].active = YES;

    NSStackView *nameRow = [XLBaseSheetController formRowWithLabel:@"Track Name:"
                                                           control:_trackNameField
                                                        labelWidth:kLabelWidth];
    [stack addArrangedSubview:nameRow];

    // Timing interval popup
    _intervalPopup = [XLBaseSheetController createPopUpButton];
    [_intervalPopup.widthAnchor constraintEqualToConstant:200].active = YES;

    [self populateIntervals];

    NSStackView *intervalRow = [XLBaseSheetController formRowWithLabel:@"Interval:"
                                                               control:_intervalPopup
                                                            labelWidth:kLabelWidth];
    [stack addArrangedSubview:intervalRow];

    // Help text
    NSTextField *helpLabel = [NSTextField wrappingLabelWithString:
        @"Choose 'Empty' for a manual timing track, or select a fixed interval for auto-generated marks."];
    helpLabel.textColor = [NSColor secondaryLabelColor];
    helpLabel.font = [NSFont systemFontOfSize:11];
    [helpLabel.widthAnchor constraintLessThanOrEqualToConstant:280].active = YES;
    [stack addArrangedSubview:helpLabel];

    return stack;
}

- (void)populateIntervals {
    [_intervalPopup removeAllItems];

    NSArray<NSNumber *> *allIntervals = @[
        @(XLTimingIntervalEmpty),
        @(XLTimingInterval25ms),
        @(XLTimingInterval50ms),
        @(XLTimingInterval100ms),
        @(XLTimingIntervalMetronome),
        @(XLTimingIntervalMetronomeWithTags),
        @(XLTimingIntervalFPPCommands),
        @(XLTimingIntervalFPPEffects),
    ];

    for (NSNumber *intervalNum in allIntervals) {
        XLTimingInterval interval = (XLTimingInterval)[intervalNum integerValue];

        // Skip excluded intervals
        if (_excludedIntervals && [_excludedIntervals containsObject:intervalNum]) {
            continue;
        }

        NSString *title = [XLNewTimingDialog displayNameForInterval:interval];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        item.tag = interval;
        [_intervalPopup.menu addItem:item];
    }

    // Select Empty by default
    [_intervalPopup selectItemWithTag:XLTimingIntervalEmpty];
}

- (void)sheetDidLoad {
    // If there's an existing selection, select it
    [_intervalPopup selectItemWithTag:_selectedInterval];

    // Make track name field first responder
    [self.sheet makeFirstResponder:_trackNameField];
}

- (NSString *)validate {
    NSString *name = [_trackNameField.stringValue stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (name.length == 0) {
        return @"Please enter a track name.";
    }

    // Check for duplicate names
    if (_existingTrackNames) {
        for (NSString *existing in _existingTrackNames) {
            if ([existing caseInsensitiveCompare:name] == NSOrderedSame) {
                return @"A timing track with this name already exists.";
            }
        }
    }

    return nil;
}

- (void)okClicked:(id)sender {
    _trackName = [_trackNameField.stringValue stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _selectedInterval = (XLTimingInterval)_intervalPopup.selectedItem.tag;
    [super okClicked:sender];
}

@end
