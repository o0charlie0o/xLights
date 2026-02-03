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
#import "sequencer/XLEffectPaletteView.h"
#import "sequencer/XLRowHeadingsView.h"
#import "sequencer/XLWaveformView.h"
#import "sequencer/XLTransportBarView.h"
#import "sequencer/XLScrollCoordinator.h"
#import "sequencer/XLUndoController.h"
#import "sequencer/XLAudioLoader.h"
#import "sequencer/XLAudioPlayer.h"
#import "XLEngineBridge.h"
#import "XLPlaybackController.h"
#import "XLEffectPropertiesViewController.h"

static const CGFloat kRowHeaderWidth = 180.0;
static const CGFloat kTimelineRulerHeight = 28.0;
static const CGFloat kWaveformHeight = 60.0;
static const CGFloat kTransportBarHeight = 44.0;
static const CGFloat kEffectPaletteWidth = 160.0;

// Row data stored as plain C struct - immune to wxWidgets heap corruption.
// No ObjC objects means no isa pointer dereference, no ARC, no message dispatch.
typedef struct {
    char name[256];       // Copy of name (avoids dangling pointer issues)
    XLElementType type;
    BOOL expandable;
    BOOL expanded;
    NSInteger indent;
    NSInteger elementIndex;  // Index into SequenceElements for real data
    NSInteger effectLayerCount;
} XLRowEntry;

// Effect data stored as plain C struct for real sequence effects
typedef struct {
    NSInteger elementIndex;
    NSInteger layerIndex;
    NSInteger effectIndex;
    CGFloat startTimeMS;
    CGFloat endTimeMS;
    NSInteger effectTypeIndex;
    BOOL selected;
    BOOL locked;
    BOOL renderDisabled;
} XLEffectEntry;

@interface XLSequencerViewController () <XLTimelineRulerDelegate,
                                          XLEffectsGridDataSource,
                                          XLEffectsGridDelegate,
                                          XLEffectPaletteViewDelegate,
                                          XLTransportBarDelegate,
                                          XLWaveformViewDelegate,
                                          XLRowHeadingsDataSource,
                                          XLRowHeadingsDelegate,
                                          XLScrollCoordinatorDelegate,
                                          XLPlaybackControllerDelegate> {
    // C array of row data - immune to heap corruption
    XLRowEntry *_rowData;
    NSUInteger _rowCount;
    NSUInteger _rowCapacity;

    // C array of effect data for all visible rows
    XLEffectEntry *_effectData;
    NSUInteger _effectCount;
    NSUInteger _effectCapacity;

    // Track whether we're using real or demo data
    BOOL _usingRealData;

    // Cached sequence properties
    CGFloat _sequenceDurationMS;
    NSInteger _frameRate;
}

@property (nonatomic, strong) XLTimelineRulerView *timelineRuler;
@property (nonatomic, strong) XLWaveformView *waveformView;
@property (nonatomic, strong) XLTransportBarView *transportBar;
@property (nonatomic, strong, readwrite) XLScrollCoordinator *scrollCoordinator;
@property (nonatomic, strong, readwrite) XLUndoController *undoController;
@property (nonatomic, strong) XLAudioSampleData *audioSampleData;
@property (nonatomic, strong, readwrite) XLEffectPaletteView *effectPaletteView;
@property (nonatomic, strong) NSLayoutConstraint *effectPaletteWidthConstraint;

// Effect index offset per row for fast lookup
@property (nonatomic, assign) NSUInteger *effectOffsetPerRow;
@property (nonatomic, assign) NSUInteger effectOffsetCapacity;

@end

@implementation XLSequencerViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor colorWithWhite:0.12 alpha:1.0] CGColor];

    // Initialize with default values
    _sequenceDurationMS = 60000.0;
    _frameRate = 20;
    _usingRealData = NO;

    // Try to load real data, fall back to demo
    [self reloadSequenceData];

    // Timeline ruler at the top
    _timelineRuler = [[XLTimelineRulerView alloc] initWithFrame:NSZeroRect];
    _timelineRuler.translatesAutoresizingMaskIntoConstraints = NO;
    _timelineRuler.delegate = self;
    _timelineRuler.sequenceDuration = _sequenceDurationMS / 1000.0;
    _timelineRuler.frameRate = _frameRate;
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
    _waveformView.sequenceLengthMS = _sequenceDurationMS;
    _waveformView.playbackPositionMS = -1;
    [view addSubview:_waveformView];

    // Transport bar at the bottom
    _transportBar = [[XLTransportBarView alloc] initWithFrame:NSZeroRect];
    _transportBar.translatesAutoresizingMaskIntoConstraints = NO;
    _transportBar.delegate = self;
    _transportBar.engineBridge = self.engineBridge;
    _transportBar.totalDurationMS = _sequenceDurationMS;
    [view addSubview:_transportBar];

    // Effect palette view (right sidebar for dragging effects onto timeline)
    _effectPaletteView = [[XLEffectPaletteView alloc] initWithFrame:NSZeroRect];
    _effectPaletteView.translatesAutoresizingMaskIntoConstraints = NO;
    _effectPaletteView.engineBridge = self.engineBridge;
    _effectPaletteView.delegate = self;
    _effectPaletteVisible = YES;
    [view addSubview:_effectPaletteView];

    // Set up scroll coordinator for synchronized scrolling
    _scrollCoordinator = [[XLScrollCoordinator alloc] init];
    _scrollCoordinator.timelineRulerView = _timelineRuler;
    _scrollCoordinator.effectsGridView = _effectsGridView;
    _scrollCoordinator.waveformView = _waveformView;
    _scrollCoordinator.rowHeadingsView = _rowHeadingsView;
    _scrollCoordinator.delegate = self;

    // Set up playback controller for coordinated audio and preview playback
    _playbackController = [[XLPlaybackController alloc] init];
    _playbackController.engineBridge = self.engineBridge;
    _playbackController.delegate = self;
    _playbackController.audioPlayer.positionUpdateIntervalMS = 50.0;  // 20 updates/sec

    // Set scroll/zoom limits based on sequence properties
    CGFloat rowCount = (CGFloat)_rowCount;
    CGFloat rowHeight = 22.0;
    _scrollCoordinator.maxHorizontalScrollOffset = _sequenceDurationMS * _scrollCoordinator.zoomLevel;
    _scrollCoordinator.maxVerticalScrollOffset = rowCount * rowHeight;

    // Create effect palette width constraint (stored so we can animate show/hide)
    _effectPaletteWidthConstraint = [_effectPaletteView.widthAnchor constraintEqualToConstant:kEffectPaletteWidth];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Effect palette: right side, from top to above waveform
        [_effectPaletteView.topAnchor constraintEqualToAnchor:view.topAnchor],
        [_effectPaletteView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        _effectPaletteWidthConstraint,
        [_effectPaletteView.bottomAnchor constraintEqualToAnchor:_waveformView.topAnchor],

        // Timeline ruler: right of row header column, left of palette at top
        [_timelineRuler.topAnchor constraintEqualToAnchor:view.topAnchor],
        [_timelineRuler.leadingAnchor constraintEqualToAnchor:view.leadingAnchor
                                                     constant:kRowHeaderWidth],
        [_timelineRuler.trailingAnchor constraintEqualToAnchor:_effectPaletteView.leadingAnchor],
        [_timelineRuler.heightAnchor constraintEqualToConstant:kTimelineRulerHeight],

        // Row headings: left side, below ruler, above waveform
        [_rowHeadingsView.topAnchor constraintEqualToAnchor:_timelineRuler.bottomAnchor],
        [_rowHeadingsView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_rowHeadingsView.widthAnchor constraintEqualToConstant:kRowHeaderWidth],
        [_rowHeadingsView.bottomAnchor constraintEqualToAnchor:_waveformView.topAnchor],

        // Effects grid: main area, right of row headings, below ruler, above waveform, left of palette
        [_effectsGridView.topAnchor constraintEqualToAnchor:_timelineRuler.bottomAnchor],
        [_effectsGridView.leadingAnchor constraintEqualToAnchor:_rowHeadingsView.trailingAnchor],
        [_effectsGridView.trailingAnchor constraintEqualToAnchor:_effectPaletteView.leadingAnchor],
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
    [_effectPaletteView reloadEffectTypes];

    // Load audio if sequence has media file
    [self loadAudioForSequence];
}

#pragma mark - Audio Loading

- (void)loadAudioForSequence {
    if (!self.engineBridge || ![self.engineBridge isSequenceLoaded]) {
        [self clearAudioDisplay];
        return;
    }

    NSDictionary *seqInfo = [self.engineBridge getSequenceInfo];
    NSString *mediaFile = seqInfo[@"mediaFile"];

    if (!mediaFile || mediaFile.length == 0) {
        NSLog(@"XLSequencerViewController: No media file in sequence - audio waveform will be empty");
        [self clearAudioDisplay];
        return;
    }

    // Check if the file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:mediaFile]) {
        NSLog(@"XLSequencerViewController: Media file not found: %@ - audio waveform will be empty", mediaFile);
        [self clearAudioDisplay];
        return;
    }

    // Load audio for playback via playback controller
    BOOL audioLoaded = [_playbackController loadAudioFile:mediaFile];
    if (audioLoaded) {
        NSLog(@"XLSequencerViewController: Audio loaded for playback");
    } else {
        NSLog(@"XLSequencerViewController: Failed to load audio, will use engine audio");
    }

    // Also load sample data for waveform display (separate from playback)
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        XLAudioSampleData *sampleData = [XLAudioLoader loadAudioFile:mediaFile];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                if (sampleData && sampleData.sampleCount > 0) {
                    strongSelf.audioSampleData = sampleData;
                    [strongSelf.waveformView loadAudioData:sampleData];
                } else {
                    NSLog(@"XLSequencerViewController: Failed to load audio samples, waveform will be empty");
                    [strongSelf clearAudioDisplay];
                }
            }
        });
    });
}

- (void)clearAudioDisplay {
    self.audioSampleData = nil;
    [_waveformView clearWaveform];
}

#pragma mark - Data Loading

- (void)reloadSequenceData {
    // Stop any current audio playback
    [_playbackController stop];

    // First try to load real data from the engine
    if (self.engineBridge && [self.engineBridge isSequenceLoaded]) {
        [self loadRealSequenceData];
    } else {
        [self buildDemoData];
    }

    // Update all views with new sequence properties
    [self updateViewsForSequenceChange];

    // Load audio for the sequence
    [self loadAudioForSequence];
}

- (void)updateViewsForSequenceChange {
    // Update timeline ruler
    if (_timelineRuler) {
        _timelineRuler.sequenceDuration = _sequenceDurationMS / 1000.0;
        _timelineRuler.frameRate = _frameRate;
    }

    // Update waveform view
    if (_waveformView) {
        _waveformView.sequenceLengthMS = _sequenceDurationMS;
    }

    // Update transport bar
    if (_transportBar) {
        _transportBar.totalDurationMS = _sequenceDurationMS;
    }

    // Update scroll coordinator limits
    if (_scrollCoordinator) {
        CGFloat viewWidth = NSWidth(_effectsGridView.bounds);
        CGFloat maxScrollX = _sequenceDurationMS * _scrollCoordinator.zoomLevel - viewWidth;
        _scrollCoordinator.maxHorizontalScrollOffset = fmax(0, maxScrollX);

        CGFloat rowHeight = _effectsGridView.rowHeight;
        CGFloat viewHeight = NSHeight(_effectsGridView.bounds);
        CGFloat maxScrollY = _rowCount * rowHeight - viewHeight;
        _scrollCoordinator.maxVerticalScrollOffset = fmax(0, maxScrollY);
    }

    // Reload grid and row headings
    if (_effectsGridView) {
        [_effectsGridView reloadData];
    }
    if (_rowHeadingsView) {
        [_rowHeadingsView reloadData];
    }
}

#pragma mark - Property Accessors

- (BOOL)isUsingRealData {
    return _usingRealData;
}

- (CGFloat)sequenceDurationMS {
    return _sequenceDurationMS;
}

- (void)loadRealSequenceData {
    // Free existing data
    if (_rowData) {
        free(_rowData);
        _rowData = NULL;
    }
    if (_effectData) {
        free(_effectData);
        _effectData = NULL;
    }
    if (_effectOffsetPerRow) {
        free(_effectOffsetPerRow);
        _effectOffsetPerRow = NULL;
    }

    _usingRealData = YES;

    // Get sequence info
    NSDictionary *seqInfo = [self.engineBridge getSequenceInfo];
    if (seqInfo) {
        _sequenceDurationMS = [seqInfo[@"durationMS"] doubleValue];
        NSInteger frameTimeMS = [seqInfo[@"frameTimeMS"] integerValue];
        _frameRate = (frameTimeMS > 0) ? (1000 / frameTimeMS) : 20;
    } else {
        _sequenceDurationMS = [self.engineBridge getDuration];
        _frameRate = [self.engineBridge getFrameRate];
        if (_frameRate == 0) _frameRate = 20;
    }

    if (_sequenceDurationMS == 0) {
        _sequenceDurationMS = 60000.0;
    }

    // Get sequence elements
    NSArray<NSDictionary *> *elements = [self.engineBridge getSequenceElements];
    NSInteger elementCount = elements.count;

    if (elementCount == 0) {
        // Fall back to demo data if no elements
        [self buildDemoData];
        return;
    }

    // Allocate row data
    _rowCapacity = (NSUInteger)elementCount + 32;
    _rowCount = (NSUInteger)elementCount;
    _rowData = (XLRowEntry *)calloc(_rowCapacity, sizeof(XLRowEntry));

    // Allocate effect offset array
    _effectOffsetCapacity = _rowCapacity;
    _effectOffsetPerRow = (NSUInteger *)calloc(_effectOffsetCapacity, sizeof(NSUInteger));

    // Count total effects first
    NSUInteger totalEffects = 0;
    for (NSUInteger i = 0; i < _rowCount; i++) {
        NSDictionary *elem = elements[i];
        NSInteger layerCount = [elem[@"effectLayerCount"] integerValue];
        // For now, just count layer 0 effects
        if (layerCount > 0) {
            NSArray *effects = [self.engineBridge getEffectsForElementAtIndex:(NSInteger)i layer:0];
            totalEffects += effects.count;
        }
    }

    // Allocate effect data
    _effectCapacity = totalEffects + 64;
    _effectCount = 0;
    _effectData = (XLEffectEntry *)calloc(_effectCapacity, sizeof(XLEffectEntry));

    // Populate row and effect data
    for (NSUInteger i = 0; i < _rowCount; i++) {
        NSDictionary *elem = elements[i];
        XLRowEntry *row = &_rowData[i];

        // Copy name (truncate if necessary)
        NSString *name = elem[@"name"];
        if (name) {
            const char *utf8Name = [name UTF8String];
            strncpy(row->name, utf8Name, sizeof(row->name) - 1);
            row->name[sizeof(row->name) - 1] = '\0';
        } else {
            strcpy(row->name, "");
        }

        // Set type
        NSString *typeStr = elem[@"type"];
        if ([typeStr isEqualToString:@"timing"]) {
            row->type = XLElementTypeTiming;
        } else if ([typeStr isEqualToString:@"submodel"]) {
            row->type = XLElementTypeSubmodel;
        } else if ([typeStr isEqualToString:@"strand"]) {
            row->type = XLElementTypeStrand;
        } else {
            row->type = XLElementTypeModel;
        }

        row->effectLayerCount = [elem[@"effectLayerCount"] integerValue];
        row->expandable = (row->effectLayerCount > 1);
        row->expanded = ![elem[@"collapsed"] boolValue];
        row->indent = 0; // TODO: Calculate based on group hierarchy
        row->elementIndex = (NSInteger)i;

        // Store effect offset for this row
        _effectOffsetPerRow[i] = _effectCount;

        // Load effects for layer 0
        if (row->effectLayerCount > 0) {
            NSArray *effects = [self.engineBridge getEffectsForElementAtIndex:(NSInteger)i layer:0];
            for (NSDictionary *eff in effects) {
                if (_effectCount >= _effectCapacity) {
                    // Grow the array
                    _effectCapacity *= 2;
                    _effectData = (XLEffectEntry *)realloc(_effectData, _effectCapacity * sizeof(XLEffectEntry));
                }

                XLEffectEntry *entry = &_effectData[_effectCount];
                entry->elementIndex = (NSInteger)i;
                entry->layerIndex = 0;
                entry->effectIndex = [eff[@"id"] integerValue];
                entry->startTimeMS = [eff[@"startTimeMS"] doubleValue];
                entry->endTimeMS = [eff[@"endTimeMS"] doubleValue];
                entry->effectTypeIndex = [eff[@"effectIndex"] integerValue];
                entry->selected = [eff[@"selected"] boolValue];
                entry->locked = [eff[@"protected"] boolValue];
                entry->renderDisabled = NO;

                _effectCount++;
            }
        }
    }

    NSLog(@"XLSequencerViewController: Loaded %lu elements with %lu effects from real sequence (duration: %.0f ms)",
          (unsigned long)_rowCount, (unsigned long)_effectCount, _sequenceDurationMS);
}

- (void)buildDemoData {
    // Free existing data
    if (_rowData) {
        free(_rowData);
        _rowData = NULL;
    }
    if (_effectData) {
        free(_effectData);
        _effectData = NULL;
    }
    if (_effectOffsetPerRow) {
        free(_effectOffsetPerRow);
        _effectOffsetPerRow = NULL;
    }

    _usingRealData = NO;
    _sequenceDurationMS = 60000.0;
    _frameRate = 20;

    // Static demo row definitions
    typedef struct {
        const char *name;
        XLElementType type;
        BOOL expandable;
        BOOL expanded;
        NSInteger indent;
    } DemoRowDef;

    static const DemoRowDef kDemoRows[] = {
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

    _rowCount = sizeof(kDemoRows) / sizeof(kDemoRows[0]);
    _rowCapacity = _rowCount + 16;
    _rowData = (XLRowEntry *)calloc(_rowCapacity, sizeof(XLRowEntry));

    // Allocate effect offset array
    _effectOffsetCapacity = _rowCapacity;
    _effectOffsetPerRow = (NSUInteger *)calloc(_effectOffsetCapacity, sizeof(NSUInteger));

    // Copy demo rows
    for (NSUInteger i = 0; i < _rowCount; i++) {
        XLRowEntry *row = &_rowData[i];
        strncpy(row->name, kDemoRows[i].name, sizeof(row->name) - 1);
        row->name[sizeof(row->name) - 1] = '\0';
        row->type = kDemoRows[i].type;
        row->expandable = kDemoRows[i].expandable;
        row->expanded = kDemoRows[i].expanded;
        row->indent = kDemoRows[i].indent;
        row->elementIndex = (NSInteger)i;
        row->effectLayerCount = 1;
    }

    // Generate demo effects - same pattern as before
    NSUInteger totalDemoEffects = 0;
    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (i < 5) totalDemoEffects += 3;
        else if (i < 10) totalDemoEffects += 2;
        else totalDemoEffects += 1;
    }

    _effectCapacity = totalDemoEffects + 16;
    _effectCount = 0;
    _effectData = (XLEffectEntry *)calloc(_effectCapacity, sizeof(XLEffectEntry));

    // Create demo effects
    for (NSUInteger row = 0; row < _rowCount; row++) {
        _effectOffsetPerRow[row] = _effectCount;

        NSUInteger numEffects = (row < 5) ? 3 : ((row < 10) ? 2 : 1);
        for (NSUInteger j = 0; j < numEffects; j++) {
            XLEffectEntry *eff = &_effectData[_effectCount];
            CGFloat baseOffset = j * 5000.0 + row * 300.0;
            eff->elementIndex = (NSInteger)row;
            eff->layerIndex = 0;
            eff->effectIndex = (NSInteger)_effectCount;
            eff->startTimeMS = baseOffset + 500;
            eff->endTimeMS = baseOffset + 3500 + j * 1000;
            eff->effectTypeIndex = (row + j) % 30;
            eff->selected = NO;
            eff->locked = (row == 3 && j == 0);
            eff->renderDisabled = (row == 7 && j == 0);
            _effectCount++;
        }
    }

    NSLog(@"XLSequencerViewController: Using demo data with %lu rows and %lu effects",
          (unsigned long)_rowCount, (unsigned long)_effectCount);
}

- (void)dealloc {
    if (_rowData) {
        free(_rowData);
        _rowData = NULL;
    }
    if (_effectData) {
        free(_effectData);
        _effectData = NULL;
    }
    if (_effectOffsetPerRow) {
        free(_effectOffsetPerRow);
        _effectOffsetPerRow = NULL;
    }
}

#pragma mark - XLTimelineRulerDelegate

- (void)timelineRuler:(XLTimelineRulerView *)ruler didChangePlaybackPosition:(NSTimeInterval)positionSeconds {
    CGFloat positionMS = positionSeconds * 1000.0;

    // Seek via playback controller (handles audio and preview sync)
    if (_playbackController) {
        [_playbackController seekToPositionMS:(NSInteger)positionMS];
    } else {
        // Fallback: sync with engine bridge for output
        [self.engineBridge seek:(NSInteger)positionMS];
    }

    // Update UI
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
    return (NSInteger)_rowCount;
}

- (NSString *)effectsGrid:(XLEffectsGridView *)gridView nameForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return @"";
    return [NSString stringWithUTF8String:_rowData[row].name];
}

- (NSInteger)effectsGrid:(XLEffectsGridView *)gridView elementTypeForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return 0;
    return (NSInteger)_rowData[row].type;
}

- (NSInteger)effectsGrid:(XLEffectsGridView *)gridView numberOfEffectsInRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_effectOffsetPerRow) return 0;

    // Calculate effect count by finding the range between this row's offset and the next
    NSUInteger startOffset = _effectOffsetPerRow[row];
    NSUInteger endOffset;
    if ((NSUInteger)row + 1 < _rowCount) {
        endOffset = _effectOffsetPerRow[row + 1];
    } else {
        endOffset = _effectCount;
    }

    return (NSInteger)(endOffset - startOffset);
}

- (XLEffectRenderInfo)effectsGrid:(XLEffectsGridView *)gridView
                 effectInfoForRow:(NSInteger)row
                          atIndex:(NSInteger)effectIndex
{
    XLEffectRenderInfo info;
    memset(&info, 0, sizeof(info));

    if (row < 0 || row >= (NSInteger)_rowCount || !_effectOffsetPerRow || !_effectData) {
        return info;
    }

    NSUInteger offset = _effectOffsetPerRow[row] + (NSUInteger)effectIndex;
    if (offset >= _effectCount) {
        return info;
    }

    XLEffectEntry *eff = &_effectData[offset];
    info.startTimeMS = eff->startTimeMS;
    info.endTimeMS = eff->endTimeMS;
    info.row = row;
    info.layer = eff->layerIndex;
    info.effectIndex = eff->effectTypeIndex;
    info.colorARGB = 0;  // 0 = use palette color from effectIndex
    info.selected = eff->selected;
    info.locked = eff->locked;
    info.renderDisabled = eff->renderDisabled;

    return info;
}

- (CGFloat)sequenceLengthMSForEffectsGrid:(XLEffectsGridView *)gridView {
    return _sequenceDurationMS;
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

    // Get the actual effect ID from our data
    NSInteger effectId = 0;
    NSString *effectType = nil;

    if (row >= 0 && row < (NSInteger)_rowCount && _effectOffsetPerRow && _effectData) {
        NSUInteger offset = _effectOffsetPerRow[row] + (NSUInteger)effectIndex;
        if (offset < _effectCount) {
            XLEffectEntry *eff = &_effectData[offset];
            effectId = eff->effectIndex;

            // Get effect type from engine if available
            if (_engineBridge && effectId > 0) {
                NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
                effectType = effectInfo[@"effectType"];
            }
        }
    }

    // Post notification for effect properties panel
    NSDictionary *userInfo = @{
        @"effectId": @(effectId),
        @"effectType": effectType ?: [NSNull null]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:XLEffectSelectionDidChangeNotification
                                                        object:self
                                                      userInfo:userInfo];
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

    // Clicking on empty area clears selection
    NSDictionary *userInfo = @{
        @"effectId": @(0),
        @"effectType": [NSNull null]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:XLEffectSelectionDidChangeNotification
                                                        object:self
                                                      userInfo:userInfo];
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

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestCreateEffectOfType:(NSString *)effectType
                           atRow:(NSInteger)row
                     startTimeMS:(CGFloat)startTimeMS
                       endTimeMS:(CGFloat)endTimeMS
{
    NSLog(@"XLSequencerViewController: Create effect '%@' at row %ld, time %.0f-%.0f ms",
          effectType, (long)row, startTimeMS, endTimeMS);

    if (!_engineBridge || !_usingRealData) {
        NSLog(@"XLSequencerViewController: Cannot create effect - no real sequence loaded");
        return;
    }

    // Get the model name for this row
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) {
        NSLog(@"XLSequencerViewController: Invalid row %ld for effect creation", (long)row);
        return;
    }

    NSString *modelName = [NSString stringWithUTF8String:_rowData[row].name];

    // Create the effect via engine bridge
    NSInteger effectId = [_engineBridge createEffect:modelName
                                               layer:0
                                          effectType:effectType
                                         startTimeMS:(NSInteger)startTimeMS
                                           endTimeMS:(NSInteger)endTimeMS];

    if (effectId >= 0) {
        NSLog(@"XLSequencerViewController: Created effect with ID %ld", (long)effectId);
        // Reload data to show the new effect
        [self reloadSequenceData];
    } else {
        NSLog(@"XLSequencerViewController: Failed to create effect");
    }
}

#pragma mark - XLRowHeadingsDataSource

- (NSInteger)numberOfRowsInRowHeadings:(XLRowHeadingsView *)view {
    return (NSInteger)_rowCount;
}

- (NSString *)rowHeadings:(XLRowHeadingsView *)view nameForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return @"";
    return [NSString stringWithUTF8String:_rowData[row].name];
}

- (XLElementType)rowHeadings:(XLRowHeadingsView *)view elementTypeForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return XLElementTypeModel;
    return _rowData[row].type;
}

- (BOOL)rowHeadings:(XLRowHeadingsView *)view isExpandableAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return NO;
    return _rowData[row].expandable;
}

- (BOOL)rowHeadings:(XLRowHeadingsView *)view isExpandedAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return NO;
    return _rowData[row].expanded;
}

- (NSInteger)rowHeadings:(XLRowHeadingsView *)view indentLevelForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return 0;
    return _rowData[row].indent;
}

#pragma mark - XLRowHeadingsDelegate

- (void)rowHeadings:(XLRowHeadingsView *)view didToggleExpandAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return;

    _rowData[row].expanded = !_rowData[row].expanded;
    NSLog(@"Toggled expand for row %ld: %s", (long)row, _rowData[row].name);
    [_rowHeadingsView reloadData];
}

- (void)rowHeadings:(XLRowHeadingsView *)view didSelectRow:(NSInteger)row {
    const char *name = (row >= 0 && row < (NSInteger)_rowCount && _rowData)
                       ? _rowData[row].name : "(none)";
    NSLog(@"Selected row heading %ld: %s", (long)row, name);
}

- (void)rowHeadings:(XLRowHeadingsView *)view didReorderRow:(NSInteger)fromRow toRow:(NSInteger)toRow {
    NSLog(@"Reorder row %ld to %ld", (long)fromRow, (long)toRow);
    if (!_rowData) return;
    if (fromRow < 0 || fromRow >= (NSInteger)_rowCount) return;
    if (toRow < 0 || toRow > (NSInteger)_rowCount) return;

    // Save the row being moved
    XLRowEntry moved = _rowData[fromRow];

    // Shift elements to fill the gap
    NSInteger insertIdx = (toRow > fromRow) ? toRow - 1 : toRow;
    if (insertIdx > (NSInteger)_rowCount - 1) insertIdx = (NSInteger)_rowCount - 1;

    if (fromRow < insertIdx) {
        // Moving down: shift elements up
        memmove(&_rowData[fromRow], &_rowData[fromRow + 1],
                (insertIdx - fromRow) * sizeof(XLRowEntry));
    } else if (fromRow > insertIdx) {
        // Moving up: shift elements down
        memmove(&_rowData[insertIdx + 1], &_rowData[insertIdx],
                (fromRow - insertIdx) * sizeof(XLRowEntry));
    }

    _rowData[insertIdx] = moved;

    // Note: We would also need to update effect offsets here for real data
    // For now, this is primarily useful with demo data

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

    // Seek via playback controller (handles audio and preview sync)
    if (_playbackController) {
        [_playbackController seekToPositionMS:(NSInteger)timeMS];
    } else {
        // Fallback: sync with engine bridge for output
        [self.engineBridge seek:(NSInteger)timeMS];
    }

    // Update UI
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
    // Seek playback controller (handles audio and preview sync)
    [_playbackController seekToPositionMS:(NSInteger)positionMS];

    // Update UI
    NSTimeInterval positionSeconds = positionMS / 1000.0;
    [_effectsGridView setPlaybackPositionMS:positionMS animated:NO];
    _timelineRuler.playbackPosition = positionSeconds;
    _waveformView.playbackPositionMS = positionMS;
}

- (void)transportBarDidPlay:(XLTransportBarView *)bar {
    // Start playback controller (handles audio and preview sync)
    if (_playbackController) {
        [_playbackController play];
    }

    _timelineRuler.playing = YES;
}

- (void)transportBarDidPause:(XLTransportBarView *)bar {
    // Pause playback controller (handles audio and preview)
    if (_playbackController) {
        [_playbackController pause];
    }

    _timelineRuler.playing = NO;
}

- (void)transportBarDidStop:(XLTransportBarView *)bar {
    // Stop playback controller (handles audio and preview)
    if (_playbackController) {
        [_playbackController stop];
    }

    _timelineRuler.playing = NO;
    [_effectsGridView setPlaybackPositionMS:0 animated:NO];
    _timelineRuler.playbackPosition = 0;
    _waveformView.playbackPositionMS = 0;
}

- (void)transportBar:(XLTransportBarView *)bar didChangePlaybackRate:(CGFloat)rate {
    // Update playback controller rate (handles audio player internally)
    if (_playbackController) {
        _playbackController.playbackRate = rate;
    }

    NSLog(@"Playback rate changed to %.2fx", rate);
}

- (void)transportBar:(XLTransportBarView *)bar didToggleLoop:(BOOL)loopEnabled {
    // Update playback controller loop setting (handles audio player internally)
    if (_playbackController) {
        _playbackController.loopEnabled = loopEnabled;
    }

    NSLog(@"Loop %@", loopEnabled ? @"enabled" : @"disabled");
}

- (void)transportBar:(XLTransportBarView *)bar didToggleOutput:(BOOL)outputEnabled {
    NSLog(@"Output %@", outputEnabled ? @"enabled" : @"disabled");
}

#pragma mark - XLScrollCoordinatorDelegate

- (void)scrollCoordinator:(XLScrollCoordinator *)coordinator didChangeHorizontalScrollOffset:(CGFloat)offsetX {
    // Update max scroll offset based on zoom level change
    CGFloat viewWidth = NSWidth(_effectsGridView.bounds);
    CGFloat maxScroll = _sequenceDurationMS * coordinator.zoomLevel - viewWidth;
    coordinator.maxHorizontalScrollOffset = fmax(0, maxScroll);
}

- (void)scrollCoordinator:(XLScrollCoordinator *)coordinator didChangeVerticalScrollOffset:(CGFloat)offsetY {
    // Update max scroll offset if needed
    CGFloat rowHeight = _effectsGridView.rowHeight;
    CGFloat viewHeight = NSHeight(_effectsGridView.bounds);
    CGFloat maxScroll = _rowCount * rowHeight - viewHeight;
    coordinator.maxVerticalScrollOffset = fmax(0, maxScroll);
}

- (void)scrollCoordinator:(XLScrollCoordinator *)coordinator didChangeZoomLevel:(CGFloat)zoomLevel {
    // Update max horizontal scroll offset when zoom changes
    CGFloat viewWidth = NSWidth(_effectsGridView.bounds);
    CGFloat maxScroll = _sequenceDurationMS * zoomLevel - viewWidth;
    coordinator.maxHorizontalScrollOffset = fmax(0, maxScroll);
}

#pragma mark - XLPlaybackControllerDelegate

- (void)playbackControllerDidStartPlayback:(XLPlaybackController *)controller {
    _transportBar.isPlaying = YES;
    _timelineRuler.playing = YES;
}

- (void)playbackControllerDidPausePlayback:(XLPlaybackController *)controller {
    _transportBar.isPlaying = NO;
    _timelineRuler.playing = NO;
}

- (void)playbackControllerDidStopPlayback:(XLPlaybackController *)controller {
    _transportBar.isPlaying = NO;
    _timelineRuler.playing = NO;
    _transportBar.currentPositionMS = 0;
    _timelineRuler.playbackPosition = 0;
    _waveformView.playbackPositionMS = 0;
    [_effectsGridView setPlaybackPositionMS:0 animated:NO];
}

- (void)playbackController:(XLPlaybackController *)controller didUpdatePositionMS:(NSInteger)positionMS {
    // Update all views with the new playback position
    _transportBar.currentPositionMS = (CGFloat)positionMS;
    _timelineRuler.playbackPosition = positionMS / 1000.0;
    _waveformView.playbackPositionMS = (CGFloat)positionMS;
    [_effectsGridView setPlaybackPositionMS:(CGFloat)positionMS animated:NO];
}

- (void)playbackController:(XLPlaybackController *)controller didRenderFrameAtMS:(NSInteger)timeMS {
    // Frame rendered - nothing additional needed here
    // Preview view is updated by the playback controller directly
}

#pragma mark - XLEffectPaletteViewDelegate

- (void)effectPaletteView:(XLEffectPaletteView *)paletteView didSelectEffectType:(NSString *)effectType {
    NSLog(@"XLSequencerViewController: Selected effect type: %@", effectType);
}

- (void)effectPaletteView:(XLEffectPaletteView *)paletteView didDoubleClickEffectType:(NSString *)effectType {
    NSLog(@"XLSequencerViewController: Double-clicked effect type: %@", effectType);
    // TODO: Apply effect to currently selected range on timeline
}

#pragma mark - Effect Palette Visibility

- (void)setEffectPaletteVisible:(BOOL)effectPaletteVisible {
    if (_effectPaletteVisible == effectPaletteVisible) return;

    _effectPaletteVisible = effectPaletteVisible;

    CGFloat targetWidth = effectPaletteVisible ? kEffectPaletteWidth : 0;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.25;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        _effectPaletteWidthConstraint.animator.constant = targetWidth;
    } completionHandler:nil];
}

@end
