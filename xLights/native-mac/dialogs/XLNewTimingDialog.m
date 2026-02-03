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

@interface XLNewTimingDialog ()

@property (nonatomic, strong) NSPopUpButton *intervalPopup;

@end

@implementation XLNewTimingDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"New Timing";
        self.minWidth = 300;
        self.minHeight = 140;
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
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 16;

    // Label
    NSTextField *label = [NSTextField labelWithString:@"Select New Timing Interval:"];
    label.font = [NSFont systemFontOfSize:13];
    [stack addArrangedSubview:label];

    // Popup
    _intervalPopup = [XLBaseSheetController createPopUpButton];
    [_intervalPopup.widthAnchor constraintEqualToConstant:200].active = YES;

    [self populateIntervals];
    [stack addArrangedSubview:_intervalPopup];

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
}

- (void)okClicked:(id)sender {
    _selectedInterval = (XLTimingInterval)_intervalPopup.selectedItem.tag;
    [super okClicked:sender];
}

@end
