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
#import "sequencer/XLScrollCoordinator.h"
#import "sequencer/XLUndoController.h"
#import "XLEngineBridge.h"

static const CGFloat kRowHeaderWidth = 180.0;
static const CGFloat kTimelineRulerHeight = 28.0;
static const CGFloat kWaveformHeight = 60.0;
static const CGFloat kTransportBarHeight = 44.0;

// Demo row data stored as plain C struct - immune to wxWidgets heap corruption.
// No ObjC objects means no isa pointer dereference, no ARC, no message dispatch.
typedef struct {
    const char *name;     // Static string pointer (lives in DATA segment)
    XLElementType type;
    BOOL expandable;
    BOOL expanded;
    NSInteger indent;
} XLDemoRowEntry;

@interface XLSequencerViewController () <XLTimelineRulerDelegate,
                                          XLEffectsGridDataSource,
                                          XLEffectsGridDelegate,
                                          XLTransportBarDelegate,
                                          XLWaveformViewDelegate,
                                          XLRowHeadingsDataSource,
                                          XLRowHeadingsDelegate,
                                          XLScrollCoordinatorDelegate> {
    // C array of demo row data - immune to heap corruption
    XLDemoRowEntry *_demoRowData;
    NSUInteger _demoRowCount;
    NSUInteger _demoRowCapacity;
}

@property (nonatomic, strong) XLTimelineRulerView *timelineRuler;
@property (nonatomic, strong) XLWaveformView *waveformView;
@property (nonatomic, strong) XLTransportBarView *transportBar;
@property (nonatomic, strong, readwrite) XLScrollCoordinator *scrollCoordinator;
@property (nonatomic, strong, readwrite) XLUndoController *undoController;

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

    // Undo controller for effect operations
    _undoController = [[XLUndoController alloc] initWithGridView:_effectsGridView];
    _effectsGridView.undoController = _undoController;

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

    // Set up scroll coordinator for synchronized scrolling
    _scrollCoordinator = [[XLScrollCoordinator alloc] init];
    _scrollCoordinator.timelineRulerView = _timelineRuler;
    _scrollCoordinator.effectsGridView = _effectsGridView;
    _scrollCoordinator.waveformView = _waveformView;
    _scrollCoordinator.rowHeadingsView = _rowHeadingsView;
    _scrollCoordinator.delegate = self;

    // Set scroll/zoom limits based on sequence properties
    CGFloat sequenceLengthMS = 60000.0;
    CGFloat rowCount = (CGFloat)_demoRowCount;
    CGFloat rowHeight = 22.0;
    _scrollCoordinator.maxHorizontalScrollOffset = sequenceLengthMS * _scrollCoordinator.zoomLevel;
    _scrollCoordinator.maxVerticalScrollOffset = rowCount * rowHeight;

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
    // Static demo data - all strings are string literals in the DATA segment,
    // so they're immune to heap corruption.
    static const XLDemoRowEntry kInitialDemoRows[] = {
        { "Beat Timing",    XLElementTypeTiming,    NO,  NO,  0 },
        { "Phrase Timing",  XLElementTypeTiming,    NO,  NO,  0 },
        { "Mega Tree",      XLElementTypeModel,     YES, YES, 0 },
        { "  Strand 1",     XLElementTypeStrand,    NO,  NO,  1 },
        { "  Strand 2",     XLElementTypeStrand,    NO,  NO,  1 },
        { "Arches",         XLElementTypeModelGroup,YES, NO,  0 },
        { "Matrix",         XLElementTypeModel,     YES, NO,  0 },
        { "Roofline",       XLElementTypeModel,     NO,  NO,  0 },
        { "Windows",        XLElementTypeModelGroup,YES, YES, 0 },
        { "  Window Left",  XLElementTypeModel,     NO,  NO,  1 },
        { "  Window Right", XLElementTypeModel,     NO,  NO,  1 },
        { "  Window Top",   XLElementTypeModel,     NO,  NO,  1 },
        { "Candy Canes",    XLElementTypeModel,     YES, NO,  0 },
        { "Snowflakes",     XLElementTypeModel,     NO,  NO,  0 },
        { "Star",           XLElementTypeModel,     YES, YES, 0 },
        { "  Star Inner",   XLElementTypeSubmodel,  NO,  NO,  1 },
        { "  Star Outer",   XLElementTypeSubmodel,  NO,  NO,  1 },
        { "Wreath",         XLElementTypeModel,     NO,  NO,  0 },
        { "Icicles",        XLElementTypeModel,     NO,  NO,  0 },
        { "Ground Plane",   XLElementTypeModel,     NO,  NO,  0 },
    };

    _demoRowCount = sizeof(kInitialDemoRows) / sizeof(kInitialDemoRows[0]);
    _demoRowCapacity = _demoRowCount + 16; // Room for growth
    _demoRowData = (XLDemoRowEntry *)malloc(_demoRowCapacity * sizeof(XLDemoRowEntry));

    // Copy static data to mutable C array (for expanded state toggling, reordering)
    memcpy(_demoRowData, kInitialDemoRows, _demoRowCount * sizeof(XLDemoRowEntry));
}

- (void)dealloc {
    if (_demoRowData) {
        free(_demoRowData);
        _demoRowData = NULL;
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
    // Use scroll coordinator for synchronized zoom
    [_scrollCoordinator viewDidChangeZoomLevel:pixelsPerMillisecond centeredOnPointX:-1 fromView:ruler];
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangeZoomLevel:(CGFloat)pixelsPerMillisecond centeredOnPointX:(CGFloat)pointX {
    // Use scroll coordinator for synchronized zoom with center point
    [_scrollCoordinator viewDidChangeZoomLevel:pixelsPerMillisecond centeredOnPointX:pointX fromView:ruler];
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangeScrollOffset:(CGFloat)scrollOffset {
    // Use scroll coordinator for synchronized horizontal scroll
    [_scrollCoordinator viewDidScrollHorizontally:scrollOffset fromView:ruler];
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didBeginScrubbing:(NSTimeInterval)positionSeconds {
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didEndScrubbing:(NSTimeInterval)positionSeconds {
}

#pragma mark - XLEffectsGridDataSource

- (NSInteger)numberOfRowsInEffectsGrid:(XLEffectsGridView *)gridView {
    return (NSInteger)_demoRowCount;
}

- (NSString *)effectsGrid:(XLEffectsGridView *)gridView nameForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRowCount || !_demoRowData) return @"";
    const char *name = _demoRowData[row].name;
    return name ? [NSString stringWithUTF8String:name] : @"";
}

- (NSInteger)effectsGrid:(XLEffectsGridView *)gridView elementTypeForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRowCount || !_demoRowData) return 0;
    return (NSInteger)_demoRowData[row].type;
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
    info.colorARGB = 0;  // 0 = use palette color from effectIndex
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
    // Use scroll coordinator for synchronized zoom
    [_scrollCoordinator viewDidChangeZoomLevel:zoomLevel centeredOnPointX:-1 fromView:gridView];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didChangeScrollOffset:(CGPoint)scrollOffset
{
    // Use scroll coordinator for synchronized scroll
    [_scrollCoordinator viewDidScrollHorizontally:scrollOffset.x fromView:gridView];
    [_scrollCoordinator viewDidScrollVertically:scrollOffset.y fromView:gridView];
}

#pragma mark - XLRowHeadingsDataSource

- (NSInteger)numberOfRowsInRowHeadings:(XLRowHeadingsView *)view {
    return (NSInteger)_demoRowCount;
}

- (NSString *)rowHeadings:(XLRowHeadingsView *)view nameForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRowCount || !_demoRowData) return @"";
    const char *name = _demoRowData[row].name;
    return name ? [NSString stringWithUTF8String:name] : @"";
}

- (XLElementType)rowHeadings:(XLRowHeadingsView *)view elementTypeForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRowCount || !_demoRowData) return XLElementTypeModel;
    return _demoRowData[row].type;
}

- (BOOL)rowHeadings:(XLRowHeadingsView *)view isExpandableAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRowCount || !_demoRowData) return NO;
    return _demoRowData[row].expandable;
}

- (BOOL)rowHeadings:(XLRowHeadingsView *)view isExpandedAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRowCount || !_demoRowData) return NO;
    return _demoRowData[row].expanded;
}

- (NSInteger)rowHeadings:(XLRowHeadingsView *)view indentLevelForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRowCount || !_demoRowData) return 0;
    return _demoRowData[row].indent;
}

#pragma mark - XLRowHeadingsDelegate

- (void)rowHeadings:(XLRowHeadingsView *)view didToggleExpandAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_demoRowCount || !_demoRowData) return;

    _demoRowData[row].expanded = !_demoRowData[row].expanded;
    NSLog(@"Toggled expand for row %ld: %s", (long)row, _demoRowData[row].name);
    [_rowHeadingsView reloadData];
}

- (void)rowHeadings:(XLRowHeadingsView *)view didSelectRow:(NSInteger)row {
    const char *name = (row >= 0 && row < (NSInteger)_demoRowCount && _demoRowData)
                       ? _demoRowData[row].name : "(none)";
    NSLog(@"Selected row heading %ld: %s", (long)row, name);
}

- (void)rowHeadings:(XLRowHeadingsView *)view didReorderRow:(NSInteger)fromRow toRow:(NSInteger)toRow {
    NSLog(@"Reorder row %ld to %ld", (long)fromRow, (long)toRow);
    if (!_demoRowData) return;
    if (fromRow < 0 || fromRow >= (NSInteger)_demoRowCount) return;
    if (toRow < 0 || toRow > (NSInteger)_demoRowCount) return;

    // Save the row being moved
    XLDemoRowEntry moved = _demoRowData[fromRow];

    // Shift elements to fill the gap
    NSInteger insertIdx = (toRow > fromRow) ? toRow - 1 : toRow;
    if (insertIdx > (NSInteger)_demoRowCount - 1) insertIdx = (NSInteger)_demoRowCount - 1;

    if (fromRow < insertIdx) {
        // Moving down: shift elements up
        memmove(&_demoRowData[fromRow], &_demoRowData[fromRow + 1],
                (insertIdx - fromRow) * sizeof(XLDemoRowEntry));
    } else if (fromRow > insertIdx) {
        // Moving up: shift elements down
        memmove(&_demoRowData[insertIdx + 1], &_demoRowData[insertIdx],
                (fromRow - insertIdx) * sizeof(XLDemoRowEntry));
    }

    _demoRowData[insertIdx] = moved;

    [_rowHeadingsView reloadData];
    [_effectsGridView reloadData];
}

- (void)rowHeadings:(XLRowHeadingsView *)view didChangeVerticalScrollOffset:(CGFloat)offsetY {
    // Use scroll coordinator for synchronized vertical scroll
    [_scrollCoordinator viewDidScrollVertically:offsetY fromView:view];
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
    // Use scroll coordinator for synchronized horizontal scroll
    [_scrollCoordinator viewDidScrollHorizontally:scrollOffsetX fromView:view];
}

- (void)waveformView:(XLWaveformView *)view didChangeZoomLevel:(CGFloat)zoomLevel centeredOnPointX:(CGFloat)pointX {
    // Use scroll coordinator for synchronized zoom
    [_scrollCoordinator viewDidChangeZoomLevel:zoomLevel centeredOnPointX:pointX fromView:view];
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

#pragma mark - XLScrollCoordinatorDelegate

- (void)scrollCoordinator:(XLScrollCoordinator *)coordinator didChangeHorizontalScrollOffset:(CGFloat)offsetX {
    // Update max scroll offset based on zoom level change
    CGFloat sequenceLengthMS = 60000.0;
    CGFloat viewWidth = NSWidth(_effectsGridView.bounds);
    CGFloat maxScroll = sequenceLengthMS * coordinator.zoomLevel - viewWidth;
    coordinator.maxHorizontalScrollOffset = fmax(0, maxScroll);
}

- (void)scrollCoordinator:(XLScrollCoordinator *)coordinator didChangeVerticalScrollOffset:(CGFloat)offsetY {
    // Update max scroll offset if needed
    CGFloat rowHeight = _effectsGridView.rowHeight;
    CGFloat viewHeight = NSHeight(_effectsGridView.bounds);
    CGFloat maxScroll = _demoRowCount * rowHeight - viewHeight;
    coordinator.maxVerticalScrollOffset = fmax(0, maxScroll);
}

- (void)scrollCoordinator:(XLScrollCoordinator *)coordinator didChangeZoomLevel:(CGFloat)zoomLevel {
    // Update max horizontal scroll offset when zoom changes
    CGFloat sequenceLengthMS = 60000.0;
    CGFloat viewWidth = NSWidth(_effectsGridView.bounds);
    CGFloat maxScroll = sequenceLengthMS * zoomLevel - viewWidth;
    coordinator.maxHorizontalScrollOffset = fmax(0, maxScroll);
}

@end
