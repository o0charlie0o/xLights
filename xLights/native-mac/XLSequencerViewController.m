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
#import "sequencer/XLRowHeadingsView.h"
#import "sequencer/XLWaveformView.h"
#import "sequencer/XLTransportBarView.h"
#import "XLEngineBridge.h"

static const CGFloat kRowHeaderWidth = 180.0;
static const CGFloat kTimelineRulerHeight = 28.0;
static const CGFloat kWaveformHeight = 60.0;
static const CGFloat kTransportBarHeight = 44.0;

@interface XLSequencerViewController () <XLTimelineRulerDelegate,
                                          XLEffectsGridDataSource,
                                          XLEffectsGridDelegate,
                                          XLTransportBarDelegate,
                                          XLWaveformViewDelegate,
                                          XLRowHeadingsDataSource,
                                          XLRowHeadingsDelegate>

@property (nonatomic, strong) XLTimelineRulerView *timelineRuler;
@property (nonatomic, strong) XLWaveformView *waveformView;
@property (nonatomic, strong) XLTransportBarView *transportBar;
@property (nonatomic, strong) NSMutableArray *demoRows;

@end

@implementation XLSequencerViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor colorWithWhite:0.12 alpha:1.0] CGColor];

    [self buildDemoData];

    // Timeline ruler at the top
    _timelineRuler = [[XLTimelineRulerView alloc] initWithFrame:NSZeroRect];
    _timelineRuler.translatesAutoresizingMaskIntoConstraints = NO;
    _timelineRuler.delegate = self;
    _timelineRuler.sequenceDuration = 60.0;
    _timelineRuler.frameRate = 20;
    [view addSubview:_timelineRuler];

    // Row headings view (left sidebar with model names, expand/collapse, mute/solo)
    _rowHeadingsView = [[XLRowHeadingsView alloc] initWithFrame:NSZeroRect];
    _rowHeadingsView.translatesAutoresizingMaskIntoConstraints = NO;
    _rowHeadingsView.dataSource = self;
    _rowHeadingsView.delegate = self;
    _rowHeadingsView.rowHeight = 22.0;
    [view addSubview:_rowHeadingsView];

    // Effects grid (Metal-backed timeline)
    _effectsGridView = [[XLEffectsGridView alloc] initWithFrame:NSZeroRect];
    _effectsGridView.translatesAutoresizingMaskIntoConstraints = NO;
    _effectsGridView.dataSource = self;
    _effectsGridView.delegate = self;
    [view addSubview:_effectsGridView];

    // Waveform view (below the grid)
    _waveformView = [[XLWaveformView alloc] initWithFrame:NSZeroRect];
    _waveformView.translatesAutoresizingMaskIntoConstraints = NO;
    _waveformView.delegate = self;
    _waveformView.zoomLevel = _effectsGridView.zoomLevel;
    _waveformView.scrollOffsetX = _effectsGridView.scrollOffset.x;
    _waveformView.sequenceLengthMS = 60000.0;
    _waveformView.playbackPositionMS = -1;
    [view addSubview:_waveformView];

    // Transport bar at the bottom
    _transportBar = [[XLTransportBarView alloc] initWithFrame:NSZeroRect];
    _transportBar.translatesAutoresizingMaskIntoConstraints = NO;
    _transportBar.delegate = self;
    _transportBar.engineBridge = self.engineBridge;
    _transportBar.totalDurationMS = 60000.0;
    [view addSubview:_transportBar];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Timeline ruler: right of row header column, full remaining width at top
        [_timelineRuler.topAnchor constraintEqualToAnchor:view.topAnchor],
        [_timelineRuler.leadingAnchor constraintEqualToAnchor:view.leadingAnchor
                                                     constant:kRowHeaderWidth],
        [_timelineRuler.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_timelineRuler.heightAnchor constraintEqualToConstant:kTimelineRulerHeight],

        // Row headings: left side, below ruler, above waveform
        [_rowHeadingsView.topAnchor constraintEqualToAnchor:_timelineRuler.bottomAnchor],
        [_rowHeadingsView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_rowHeadingsView.widthAnchor constraintEqualToConstant:kRowHeaderWidth],
        [_rowHeadingsView.bottomAnchor constraintEqualToAnchor:_waveformView.topAnchor],

        // Effects grid: main area, right of row headings, below ruler, above waveform
        [_effectsGridView.topAnchor constraintEqualToAnchor:_timelineRuler.bottomAnchor],
        [_effectsGridView.leadingAnchor constraintEqualToAnchor:_rowHeadingsView.trailingAnchor],
        [_effectsGridView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_effectsGridView.bottomAnchor constraintEqualToAnchor:_waveformView.topAnchor],

        // Waveform: full width, above transport bar
        [_waveformView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_waveformView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_waveformView.bottomAnchor constraintEqualToAnchor:_transportBar.topAnchor],
        [_waveformView.heightAnchor constraintEqualToConstant:kWaveformHeight],

        // Transport bar: full width at the very bottom
        [_transportBar.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_transportBar.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_transportBar.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [_transportBar.heightAnchor constraintEqualToConstant:kTransportBarHeight],
    ]];

    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [_effectsGridView reloadData];
    [_rowHeadingsView reloadData];
}

#pragma mark - Demo Data

- (void)buildDemoData {
    _demoRows = [NSMutableArray array];

    NSArray *demoElements = @[
        @[@"Beat Timing",       @(XLElementTypeTiming),    @NO,  @NO,  @0],
        @[@"Phrase Timing",     @(XLElementTypeTiming),    @NO,  @NO,  @0],
        @[@"Mega Tree",         @(XLElementTypeModel),     @YES, @YES, @0],
        @[@"  Strand 1",        @(XLElementTypeStrand),    @NO,  @NO,  @1],
        @[@"  Strand 2",        @(XLElementTypeStrand),    @NO,  @NO,  @1],
        @[@"Arches",            @(XLElementTypeModelGroup),@YES, @NO,  @0],
        @[@"Matrix",            @(XLElementTypeModel),     @YES, @NO,  @0],
        @[@"Roofline",          @(XLElementTypeModel),     @NO,  @NO,  @0],
        @[@"Windows",           @(XLElementTypeModelGroup),@YES, @YES, @0],
        @[@"  Window Left",     @(XLElementTypeModel),     @NO,  @NO,  @1],
        @[@"  Window Right",    @(XLElementTypeModel),     @NO,  @NO,  @1],
        @[@"  Window Top",      @(XLElementTypeModel),     @NO,  @NO,  @1],
        @[@"Candy Canes",       @(XLElementTypeModel),     @YES, @NO,  @0],
        @[@"Snowflakes",        @(XLElementTypeModel),     @NO,  @NO,  @0],
        @[@"Star",              @(XLElementTypeModel),     @YES, @YES, @0],
        @[@"  Star Inner",      @(XLElementTypeSubmodel),  @NO,  @NO,  @1],
        @[@"  Star Outer",      @(XLElementTypeSubmodel),  @NO,  @NO,  @1],
        @[@"Wreath",            @(XLElementTypeModel),     @NO,  @NO,  @0],
        @[@"Icicles",           @(XLElementTypeModel),     @NO,  @NO,  @0],
        @[@"Ground Plane",      @(XLElementTypeModel),     @NO,  @NO,  @0],
    ];

    for (NSArray *elem in demoElements) {
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        row[@"name"]       = elem[0];
        row[@"type"]       = elem[1];
        row[@"expandable"] = elem[2];
        row[@"expanded"]   = elem[3];
        row[@"indent"]     = elem[4];
        [_demoRows addObject:row];
    }
}

#pragma mark - XLTimelineRulerDelegate

- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangePlaybackPosition:(NSTimeInterval)positionSeconds {
    NSInteger positionMS = (NSInteger)(positionSeconds * 1000.0);
    [self.engineBridge seek:positionMS];
    [_effectsGridView setPlaybackPositionMS:positionMS animated:NO];
    _waveformView.playbackPositionMS = positionMS;
    _transportBar.currentPositionMS = positionMS;
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangeZoomLevel:(CGFloat)pixelsPerMillisecond {
    _effectsGridView.zoomLevel = pixelsPerMillisecond;
    _waveformView.zoomLevel = pixelsPerMillisecond;
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didBeginScrubbing:(NSTimeInterval)positionSeconds {
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didEndScrubbing:(NSTimeInterval)positionSeconds {
}

#pragma mark - XLEffectsGridDataSource

- (NSInteger)numberOfRowsInEffectsGrid:(XLEffectsGridView *)gridView {
    return (NSInteger)_demoRows.count;
}

- (NSString *)effectsGrid:(XLEffectsGridView *)gridView nameForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRows.count) return @"";
    return _demoRows[row][@"name"];
}

- (NSInteger)effectsGrid:(XLEffectsGridView *)gridView elementTypeForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRows.count) return 0;
    return [_demoRows[row][@"type"] integerValue];
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
    _waveformView.zoomLevel = zoomLevel;
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didChangeScrollOffset:(CGPoint)scrollOffset
{
    _timelineRuler.scrollOffset = scrollOffset.x;
    _waveformView.scrollOffsetX = scrollOffset.x;
    _rowHeadingsView.verticalScrollOffset = scrollOffset.y;
}

#pragma mark - XLRowHeadingsDataSource

- (NSInteger)numberOfRowsInRowHeadings:(XLRowHeadingsView *)view {
    return (NSInteger)_demoRows.count;
}

- (NSString *)rowHeadings:(XLRowHeadingsView *)view nameForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRows.count) return @"";
    return _demoRows[row][@"name"];
}

- (XLElementType)rowHeadings:(XLRowHeadingsView *)view elementTypeForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRows.count) return XLElementTypeModel;
    return (XLElementType)[_demoRows[row][@"type"] integerValue];
}

- (BOOL)rowHeadings:(XLRowHeadingsView *)view isExpandableAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRows.count) return NO;
    return [_demoRows[row][@"expandable"] boolValue];
}

- (BOOL)rowHeadings:(XLRowHeadingsView *)view isExpandedAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRows.count) return NO;
    return [_demoRows[row][@"expanded"] boolValue];
}

- (NSInteger)rowHeadings:(XLRowHeadingsView *)view indentLevelForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRows.count) return 0;
    return [_demoRows[row][@"indent"] integerValue];
}

#pragma mark - XLRowHeadingsDelegate

- (void)rowHeadings:(XLRowHeadingsView *)view didToggleExpandAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRows.count) return;

    BOOL current = [_demoRows[row][@"expanded"] boolValue];
    _demoRows[row][@"expanded"] = @(!current);
    NSLog(@"Toggled expand for row %ld: %@", (long)row, _demoRows[row][@"name"]);
    [_rowHeadingsView reloadData];
}

- (void)rowHeadings:(XLRowHeadingsView *)view didSelectRow:(NSInteger)row {
    NSLog(@"Selected row heading %ld: %@", (long)row,
          (row >= 0 && row < (NSInteger)_demoRows.count) ? _demoRows[row][@"name"] : @"(none)");
}

- (void)rowHeadings:(XLRowHeadingsView *)view didReorderRow:(NSInteger)fromRow toRow:(NSInteger)toRow {
    NSLog(@"Reorder row %ld to %ld", (long)fromRow, (long)toRow);
    if (fromRow < 0 || fromRow >= (NSInteger)_demoRows.count) return;
    if (toRow < 0 || toRow > (NSInteger)_demoRows.count) return;

    NSMutableDictionary *moved = _demoRows[fromRow];
    [_demoRows removeObjectAtIndex:fromRow];
    NSInteger insertIdx = (toRow > fromRow) ? toRow - 1 : toRow;
    if (insertIdx > (NSInteger)_demoRows.count) insertIdx = (NSInteger)_demoRows.count;
    [_demoRows insertObject:moved atIndex:insertIdx];

    [_rowHeadingsView reloadData];
    [_effectsGridView reloadData];
}

#pragma mark - XLWaveformViewDelegate

- (void)waveformView:(XLWaveformView *)view didSeekToTimeMS:(CGFloat)timeMS {
    NSTimeInterval positionSeconds = timeMS / 1000.0;
    [self.engineBridge seek:(NSInteger)timeMS];
    [_effectsGridView setPlaybackPositionMS:timeMS animated:NO];
    _timelineRuler.playbackPosition = positionSeconds;
    _transportBar.currentPositionMS = timeMS;
}

- (void)waveformView:(XLWaveformView *)view didChangeScrollOffset:(CGFloat)scrollOffsetX {
    _effectsGridView.scrollOffset = CGPointMake(scrollOffsetX, _effectsGridView.scrollOffset.y);
    _timelineRuler.scrollOffset = scrollOffsetX;
}

#pragma mark - XLTransportBarDelegate

- (void)transportBar:(XLTransportBarView *)bar didSeekToPositionMS:(CGFloat)positionMS {
    NSTimeInterval positionSeconds = positionMS / 1000.0;
    [_effectsGridView setPlaybackPositionMS:positionMS animated:NO];
    _timelineRuler.playbackPosition = positionSeconds;
    _waveformView.playbackPositionMS = positionMS;
}

- (void)transportBarDidPlay:(XLTransportBarView *)bar {
    _timelineRuler.playing = YES;
}

- (void)transportBarDidPause:(XLTransportBarView *)bar {
    _timelineRuler.playing = NO;
}

- (void)transportBarDidStop:(XLTransportBarView *)bar {
    _timelineRuler.playing = NO;
    [_effectsGridView setPlaybackPositionMS:0 animated:NO];
    _timelineRuler.playbackPosition = 0;
    _waveformView.playbackPositionMS = 0;
}

- (void)transportBar:(XLTransportBarView *)bar didChangePlaybackRate:(CGFloat)rate {
    NSLog(@"Playback rate changed to %.2fx", rate);
}

- (void)transportBar:(XLTransportBarView *)bar didToggleLoop:(BOOL)loopEnabled {
    NSLog(@"Loop %@", loopEnabled ? @"enabled" : @"disabled");
}

- (void)transportBar:(XLTransportBarView *)bar didToggleOutput:(BOOL)outputEnabled {
    NSLog(@"Output %@", outputEnabled ? @"enabled" : @"disabled");
}

@end
