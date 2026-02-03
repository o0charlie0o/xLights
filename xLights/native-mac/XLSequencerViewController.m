/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLSequencerViewController.h"
#import "sequencer/XLTimelineRulerView.h"

@interface XLSequencerViewController () <XLTimelineRulerDelegate>
@end

@implementation XLSequencerViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor colorWithWhite:0.14 alpha:1.0] CGColor];

    // Timeline ruler at the top
    _timelineRuler = [[XLTimelineRulerView alloc] initWithFrame:NSZeroRect];
    _timelineRuler.translatesAutoresizingMaskIntoConstraints = NO;
    _timelineRuler.delegate = self;
    _timelineRuler.sequenceDuration = 120.0; // Placeholder: 2 minutes
    _timelineRuler.frameRate = 20;
    [view addSubview:_timelineRuler];

    // Placeholder for the rest of the sequencer content
    NSView *contentArea = [[NSView alloc] initWithFrame:NSZeroRect];
    contentArea.wantsLayer = YES;
    contentArea.layer.backgroundColor = [[NSColor colorWithWhite:0.12 alpha:1.0] CGColor];
    contentArea.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:contentArea];

    NSTextField *label = [NSTextField labelWithString:@"Effects Grid"];
    label.font = [NSFont systemFontOfSize:24 weight:NSFontWeightLight];
    label.textColor = [NSColor secondaryLabelColor];
    label.alignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [contentArea addSubview:label];

    NSTextField *sublabel = [NSTextField labelWithString:@"Metal effects grid, waveform, and row headings will go here"];
    sublabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    sublabel.textColor = [NSColor tertiaryLabelColor];
    sublabel.alignment = NSTextAlignmentCenter;
    sublabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentArea addSubview:sublabel];

    [NSLayoutConstraint activateConstraints:@[
        // Timeline ruler: full width at top, intrinsic height (28pt)
        [_timelineRuler.topAnchor constraintEqualToAnchor:view.topAnchor],
        [_timelineRuler.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_timelineRuler.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_timelineRuler.heightAnchor constraintEqualToConstant:28.0],

        // Content area: below ruler, fills remaining space
        [contentArea.topAnchor constraintEqualToAnchor:_timelineRuler.bottomAnchor],
        [contentArea.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [contentArea.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [contentArea.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],

        // Placeholder labels centered in content area
        [label.centerXAnchor constraintEqualToAnchor:contentArea.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:contentArea.centerYAnchor constant:-20],
        [sublabel.centerXAnchor constraintEqualToAnchor:contentArea.centerXAnchor],
        [sublabel.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:8],
    ]];

    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

#pragma mark - XLTimelineRulerDelegate

- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangePlaybackPosition:(NSTimeInterval)positionSeconds {
    NSInteger positionMS = (NSInteger)(positionSeconds * 1000.0);
    [self.engineBridge seek:positionMS];
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangeZoomLevel:(CGFloat)pixelsPerMillisecond {
    // Will be used to sync with effects grid and waveform view (xlmac-otb)
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didBeginScrubbing:(NSTimeInterval)positionSeconds {
    // Pause playback during scrub if playing
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didEndScrubbing:(NSTimeInterval)positionSeconds {
    // Resume playback after scrub if was playing
}

@end
