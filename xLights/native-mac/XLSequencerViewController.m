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
#import "sequencer/XLEffectsGridView.h"

static const CGFloat kRowHeaderWidth = 180.0;
static const CGFloat kTimelineRulerHeight = 28.0;
static const CGFloat kWaveformHeight = 50.0;

@interface XLSequencerViewController () <XLTimelineRulerDelegate, XLEffectsGridDataSource, XLEffectsGridDelegate>

@property (nonatomic, strong) XLTimelineRulerView *timelineRuler;
@property (nonatomic, strong) NSView *rowHeaderView;
@property (nonatomic, strong) NSView *waveformArea;

@end

@implementation XLSequencerViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor colorWithWhite:0.12 alpha:1.0] CGColor];

    // Timeline ruler at the top
    _timelineRuler = [[XLTimelineRulerView alloc] initWithFrame:NSZeroRect];
    _timelineRuler.translatesAutoresizingMaskIntoConstraints = NO;
    _timelineRuler.delegate = self;
    _timelineRuler.sequenceDuration = 60.0;
    _timelineRuler.frameRate = 20;
    [view addSubview:_timelineRuler];

    // Row header area (left sidebar with model names)
    _rowHeaderView = [[NSView alloc] init];
    _rowHeaderView.wantsLayer = YES;
    _rowHeaderView.layer.backgroundColor = [[NSColor colorWithWhite:0.14 alpha:1.0] CGColor];
    _rowHeaderView.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:_rowHeaderView];

    NSTextField *rowLabel = [NSTextField labelWithString:@"Row Headers"];
    rowLabel.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
    rowLabel.textColor = [NSColor tertiaryLabelColor];
    rowLabel.alignment = NSTextAlignmentCenter;
    rowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_rowHeaderView addSubview:rowLabel];
    [NSLayoutConstraint activateConstraints:@[
        [rowLabel.centerXAnchor constraintEqualToAnchor:_rowHeaderView.centerXAnchor],
        [rowLabel.topAnchor constraintEqualToAnchor:_rowHeaderView.topAnchor constant:40],
    ]];

    // Effects grid (Metal-backed timeline)
    _effectsGridView = [[XLEffectsGridView alloc] initWithFrame:NSZeroRect];
    _effectsGridView.translatesAutoresizingMaskIntoConstraints = NO;
    _effectsGridView.dataSource = self;
    _effectsGridView.delegate = self;
    [view addSubview:_effectsGridView];

    // Waveform area (below the grid)
    _waveformArea = [[NSView alloc] init];
    _waveformArea.wantsLayer = YES;
    _waveformArea.layer.backgroundColor = [[NSColor colorWithWhite:0.10 alpha:1.0] CGColor];
    _waveformArea.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:_waveformArea];

    NSTextField *waveLabel = [NSTextField labelWithString:@"Waveform"];
    waveLabel.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
    waveLabel.textColor = [NSColor tertiaryLabelColor];
    waveLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_waveformArea addSubview:waveLabel];
    [NSLayoutConstraint activateConstraints:@[
        [waveLabel.centerXAnchor constraintEqualToAnchor:_waveformArea.centerXAnchor],
        [waveLabel.centerYAnchor constraintEqualToAnchor:_waveformArea.centerYAnchor],
    ]];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Timeline ruler: right of row header column, full remaining width at top
        [_timelineRuler.topAnchor constraintEqualToAnchor:view.topAnchor],
        [_timelineRuler.leadingAnchor constraintEqualToAnchor:view.leadingAnchor
                                                     constant:kRowHeaderWidth],
        [_timelineRuler.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_timelineRuler.heightAnchor constraintEqualToConstant:kTimelineRulerHeight],

        // Row header: left side, below ruler, above waveform
        [_rowHeaderView.topAnchor constraintEqualToAnchor:view.topAnchor],
        [_rowHeaderView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_rowHeaderView.widthAnchor constraintEqualToConstant:kRowHeaderWidth],
        [_rowHeaderView.bottomAnchor constraintEqualToAnchor:_waveformArea.topAnchor],

        // Effects grid: main area, right of row headers, below ruler, above waveform
        [_effectsGridView.topAnchor constraintEqualToAnchor:_timelineRuler.bottomAnchor],
        [_effectsGridView.leadingAnchor constraintEqualToAnchor:_rowHeaderView.trailingAnchor],
        [_effectsGridView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_effectsGridView.bottomAnchor constraintEqualToAnchor:_waveformArea.topAnchor],

        // Waveform: full width at bottom, fixed height
        [_waveformArea.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_waveformArea.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_waveformArea.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [_waveformArea.heightAnchor constraintEqualToConstant:kWaveformHeight],
    ]];

    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [_effectsGridView reloadData];
}

#pragma mark - XLTimelineRulerDelegate

- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangePlaybackPosition:(NSTimeInterval)positionSeconds {
    NSInteger positionMS = (NSInteger)(positionSeconds * 1000.0);
    [self.engineBridge seek:positionMS];
    [_effectsGridView setPlaybackPositionMS:positionMS animated:NO];
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangeZoomLevel:(CGFloat)pixelsPerMillisecond {
    _effectsGridView.zoomLevel = pixelsPerMillisecond;
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didBeginScrubbing:(NSTimeInterval)positionSeconds {
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didEndScrubbing:(NSTimeInterval)positionSeconds {
}

#pragma mark - XLEffectsGridDataSource

- (NSInteger)numberOfRowsInEffectsGrid:(XLEffectsGridView *)gridView {
    return 20;
}

- (NSString *)effectsGrid:(XLEffectsGridView *)gridView nameForRow:(NSInteger)row {
    return [NSString stringWithFormat:@"Model %ld", (long)(row + 1)];
}

- (NSInteger)effectsGrid:(XLEffectsGridView *)gridView elementTypeForRow:(NSInteger)row {
    return 0;
}

- (NSInteger)effectsGrid:(XLEffectsGridView *)gridView numberOfEffectsInRow:(NSInteger)row {
    if (row < 5) return 3;
    if (row < 10) return 2;
    return 1;
}

- (XLEffectRenderInfo)effectsGrid:(XLEffectsGridView *)gridView
                 effectInfoForRow:(NSInteger)row
                          atIndex:(NSInteger)effectIndex
{
    XLEffectRenderInfo info;
    memset(&info, 0, sizeof(info));

    CGFloat baseOffset = effectIndex * 5000.0 + row * 300.0;
    info.startTimeMS = baseOffset + 500;
    info.endTimeMS = baseOffset + 3500 + effectIndex * 1000;
    info.row = row;
    info.layer = 0;
    info.effectIndex = (row + effectIndex) % 30;
    info.effectName = @"Demo";
    info.color = nil;
    info.selected = NO;
    info.locked = (row == 3 && effectIndex == 0);
    info.renderDisabled = (row == 7 && effectIndex == 0);

    return info;
}

- (CGFloat)sequenceLengthMSForEffectsGrid:(XLEffectsGridView *)gridView {
    return 60000.0;
}

- (NSArray<NSNumber *> *)timingMarksForEffectsGrid:(XLEffectsGridView *)gridView {
    NSMutableArray *marks = [NSMutableArray array];
    for (CGFloat t = 0; t <= 60000; t += 2000) {
        [marks addObject:@(t)];
    }
    return marks;
}

#pragma mark - XLEffectsGridDelegate

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didSelectEffectAtRow:(NSInteger)row
          effectIndex:(NSInteger)effectIndex
{
    NSLog(@"Selected effect at row %ld, index %ld", (long)row, (long)effectIndex);
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didDoubleClickEffectAtRow:(NSInteger)row
              effectIndex:(NSInteger)effectIndex
{
    NSLog(@"Double-clicked effect at row %ld, index %ld", (long)row, (long)effectIndex);
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didClickAtTimeMS:(CGFloat)timeMS
                 row:(NSInteger)row
{
    NSLog(@"Clicked at time %.0fms, row %ld", timeMS, (long)row);
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didChangeZoomLevel:(CGFloat)zoomLevel
{
    _timelineRuler.zoomLevel = zoomLevel;
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didChangeScrollOffset:(CGPoint)scrollOffset
{
    _timelineRuler.scrollOffset = scrollOffset.x;
}

@end
