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
    BOOL expandable;      // Has multiple layers that can be expanded
    BOOL expanded;        // Currently showing layer sub-rows
    NSInteger indent;
    NSInteger elementIndex;  // Index into SequenceElements for real data
    NSInteger effectLayerCount;
    NSInteger layerIndex;    // -1 for main element row, 0+ for specific layer rows
    BOOL isLayerRow;         // YES if this is a layer sub-row (not the main element)
} XLRowEntry;

// Effect data stored as plain C struct for real sequence effects
typedef struct {
    NSInteger elementIndex;
    NSInteger layerIndex;
    NSInteger effectIndex;
    CGFloat startTimeMS;
    CGFloat endTimeMS;
    NSInteger effectTypeIndex;
    uint32_t colorARGB;  // Pre-computed color from effect type name
    char effectTypeName[XL_EFFECT_TYPE_NAME_MAX];  // Effect type name for icon display
    BOOL selected;
    BOOL locked;
    BOOL renderDisabled;
} XLEffectEntry;

/// Compute a consistent hash for a string (matching Swift's simple hash for color generation)
static NSUInteger XLSimpleStringHash(NSString *string) {
    NSUInteger hash = 0;
    NSUInteger len = string.length;
    for (NSUInteger i = 0; i < len; i++) {
        hash = hash * 31 + [string characterAtIndex:i];
    }
    return hash;
}

/// Convert HSB to ARGB (matching SwiftUI's Color(hue:saturation:brightness:))
static uint32_t XLColorARGBFromHSB(CGFloat hue, CGFloat saturation, CGFloat brightness) {
    CGFloat r, g, b;

    NSInteger hi = (NSInteger)(hue * 6.0) % 6;
    CGFloat f = hue * 6.0 - floor(hue * 6.0);
    CGFloat p = brightness * (1.0 - saturation);
    CGFloat q = brightness * (1.0 - f * saturation);
    CGFloat t = brightness * (1.0 - (1.0 - f) * saturation);

    switch (hi) {
        case 0: r = brightness; g = t; b = p; break;
        case 1: r = q; g = brightness; b = p; break;
        case 2: r = p; g = brightness; b = t; break;
        case 3: r = p; g = q; b = brightness; break;
        case 4: r = t; g = p; b = brightness; break;
        default: r = brightness; g = p; b = q; break;
    }

    uint8_t ri = (uint8_t)(r * 255.0);
    uint8_t gi = (uint8_t)(g * 255.0);
    uint8_t bi = (uint8_t)(b * 255.0);

    return (0xFF << 24) | (ri << 16) | (gi << 8) | bi;
}

/// Effect color lookup table for visually meaningful colors
static NSDictionary<NSString *, NSNumber *> *sEffectColorMap = nil;

static void XLInitEffectColorMap(void) {
    if (sEffectColorMap) return;
    sEffectColorMap = @{
        // Fire/Heat effects - Red/Orange
        @"Fire": @0xFFFF4400,
        @"Fireworks": @0xFFFF6600,
        @"Candle": @0xFFFF8800,
        @"Meteors": @0xFFFF5500,

        // Snow/Ice effects - White/Light Blue
        @"Snowflakes": @0xFFE8F4FF,
        @"Snowstorm": @0xFFD0E8FF,

        // Water effects - Blue
        @"Wave": @0xFF0088DD,
        @"Liquid": @0xFF0066CC,
        @"Ripple": @0xFF0099EE,

        // Nature effects - Green
        @"Tree": @0xFF228B22,
        @"Life": @0xFF32CD32,
        @"Garlands": @0xFF2E8B57,
        @"Tendril": @0xFF3CB371,

        // Light effects - Yellow/Warm White
        @"On": @0xFFFFDD00,
        @"Off": @0xFF444444,
        @"Strobe": @0xFFFFFF88,
        @"Shimmer": @0xFFFFEE66,
        @"Twinkle": @0xFFFFDD88,

        // Music/Audio effects - Purple/Magenta
        @"Music": @0xFF9933FF,
        @"VUMeter": @0xFFAA44FF,
        @"Piano": @0xFF8844CC,
        @"Guitar": @0xFF7733BB,
        @"Arpeggio": @0xFFBB55DD,

        // Shape/Pattern effects - Cyan/Teal
        @"Bars": @0xFF00AACC,
        @"Circles": @0xFF00BBDD,
        @"Lines": @0xFF0099BB,
        @"Marquee": @0xFF00CCEE,
        @"Shape": @0xFF00AAAA,

        // Motion/Transform effects - Orange
        @"Spirals": @0xFFFF8800,
        @"Spirograph": @0xFFFF9922,
        @"Pinwheel": @0xFFFFAA44,
        @"Warp": @0xFFEE7700,
        @"Kaleidoscope": @0xFFFF7755,
        @"Morph": @0xFFFF8866,
        @"Fan": @0xFFFFBB66,

        // Galaxy/Space effects - Deep Blue/Purple
        @"Galaxy": @0xFF3333AA,
        @"Plasma": @0xFF6644BB,
        @"Shockwave": @0xFF5555CC,

        // Color effects - Rainbow/Gradient
        @"ColorWash": @0xFFFF66AA,
        @"Butterfly": @0xFFFF88CC,
        @"Fill": @0xFF66AAFF,

        // Text/Picture effects - Neutral
        @"Text": @0xFF888888,
        @"Pictures": @0xFF779988,
        @"Video": @0xFF667788,
        @"Glediator": @0xFF778899,

        // DMX/Control effects - Steel Blue
        @"DMX": @0xFF4682B4,
        @"Servo": @0xFF5588AA,
        @"State": @0xFF6699BB,
        @"MovingHead": @0xFF5599BB,

        // Misc effects
        @"Lightning": @0xFFFFFF00,
        @"Curtain": @0xFFCC6699,
        @"Faces": @0xFFFFCC99,
        @"Duplicate": @0xFF888888,
        @"Adjust": @0xFF999999,
        @"Shader": @0xFF66CCAA,
        @"Sketch": @0xFFBBBBBB,
        @"SingleStrand": @0xFF77AACC,
    };
}

/// Compute effect color from type name using lookup table with fallback to hash
static uint32_t XLColorForEffectTypeName(NSString *effectTypeName) {
    if (!effectTypeName || effectTypeName.length == 0) {
        return 0xFF808080;  // Gray fallback
    }

    // Initialize lookup table on first call
    XLInitEffectColorMap();

    // Check lookup table first
    NSNumber *colorNum = sEffectColorMap[effectTypeName];
    if (colorNum) {
        return colorNum.unsignedIntValue;
    }

    // Fallback to hash-based color for unknown effects
    NSUInteger hash = XLSimpleStringHash(effectTypeName);
    CGFloat hue = (CGFloat)(hash % 360) / 360.0;
    return XLColorARGBFromHSB(hue, 0.7, 0.7);
}

/// Parse a hex color string (#RRGGBB or #AARRGGBB) to ARGB uint32
static uint32_t XLParseHexColor(NSString *hexString) {
    if (!hexString || hexString.length == 0) {
        return 0xFF808080;  // Gray fallback
    }

    // Remove # prefix if present
    if ([hexString hasPrefix:@"#"]) {
        hexString = [hexString substringFromIndex:1];
    }

    unsigned int colorValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner scanHexInt:&colorValue];

    // If only RGB (6 chars), add full alpha
    if (hexString.length == 6) {
        colorValue = 0xFF000000 | colorValue;
    }

    return (uint32_t)colorValue;
}

/// Extract the first palette color from a palette string
/// Format: "C_BUTTON_Palette1=#FF0000,C_CHECKBOX_Palette1=1,..."
static NSString *XLExtractFirstPaletteColor(NSString *paletteString) {
    if (!paletteString || paletteString.length == 0) {
        return nil;
    }

    // Split by comma
    NSArray *pairs = [paletteString componentsSeparatedByString:@","];
    for (NSString *pair in pairs) {
        // Look for C_BUTTON_Palette1=
        if ([pair hasPrefix:@"C_BUTTON_Palette1="]) {
            NSString *value = [pair substringFromIndex:[@"C_BUTTON_Palette1=" length]];
            // Unescape special characters
            value = [value stringByReplacingOccurrencesOfString:@"&comma;" withString:@","];
            value = [value stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
            return value;
        }
    }
    return nil;
}

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

// Track height slider (top-left corner)
@property (nonatomic, strong) NSView *trackHeightSliderContainer;
@property (nonatomic, strong) NSSlider *trackHeightSlider;
@property (nonatomic, assign) CGFloat minRowHeight;
@property (nonatomic, assign) CGFloat maxRowHeight;

// View selector dropdown (below track height slider, left of waveform)
@property (nonatomic, strong) NSView *viewSelectorContainer;
@property (nonatomic, strong) NSPopUpButton *viewSelectorPopup;

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

    // Track height slider defaults
    _minRowHeight = 16.0;
    _maxRowHeight = 80.0;

    // Load saved row height preference (default 22.0)
    CGFloat savedRowHeight = [[NSUserDefaults standardUserDefaults] doubleForKey:@"XLSequencerRowHeight"];
    if (savedRowHeight < _minRowHeight || savedRowHeight > _maxRowHeight) {
        savedRowHeight = 22.0;  // Use default if invalid
    }

    // Track height slider container (top-left corner, above track labels)
    _trackHeightSliderContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _trackHeightSliderContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _trackHeightSliderContainer.wantsLayer = YES;
    _trackHeightSliderContainer.layer.backgroundColor = CGColorCreateGenericRGB(0.12, 0.12, 0.12, 1.0);
    [view addSubview:_trackHeightSliderContainer];

    // Small track icon (left side of slider)
    NSImageView *smallTrackIcon = [[NSImageView alloc] init];
    smallTrackIcon.translatesAutoresizingMaskIntoConstraints = NO;
    NSImage *smallIcon = [NSImage imageWithSystemSymbolName:@"rectangle.split.1x2"
                                   accessibilityDescription:@"Small tracks"];
    NSImageSymbolConfiguration *smallConfig =
        [NSImageSymbolConfiguration configurationWithPointSize:8 weight:NSFontWeightRegular scale:NSImageSymbolScaleSmall];
    smallTrackIcon.image = [smallIcon imageWithSymbolConfiguration:smallConfig];
    smallTrackIcon.contentTintColor = [NSColor secondaryLabelColor];
    [_trackHeightSliderContainer addSubview:smallTrackIcon];

    // Large track icon (right side of slider)
    NSImageView *largeTrackIcon = [[NSImageView alloc] init];
    largeTrackIcon.translatesAutoresizingMaskIntoConstraints = NO;
    NSImage *largeIcon = [NSImage imageWithSystemSymbolName:@"rectangle.split.1x2"
                                   accessibilityDescription:@"Large tracks"];
    NSImageSymbolConfiguration *largeConfig =
        [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightRegular scale:NSImageSymbolScaleMedium];
    largeTrackIcon.image = [largeIcon imageWithSymbolConfiguration:largeConfig];
    largeTrackIcon.contentTintColor = [NSColor secondaryLabelColor];
    [_trackHeightSliderContainer addSubview:largeTrackIcon];

    // Track height slider
    _trackHeightSlider = [[NSSlider alloc] init];
    _trackHeightSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _trackHeightSlider.minValue = _minRowHeight;
    _trackHeightSlider.maxValue = _maxRowHeight;
    _trackHeightSlider.doubleValue = savedRowHeight;
    _trackHeightSlider.continuous = YES;
    _trackHeightSlider.target = self;
    _trackHeightSlider.action = @selector(trackHeightSliderChanged:);
    _trackHeightSlider.controlSize = NSControlSizeMini;
    [_trackHeightSliderContainer addSubview:_trackHeightSlider];

    // Layout constraints for track height slider container contents
    [NSLayoutConstraint activateConstraints:@[
        [smallTrackIcon.leadingAnchor constraintEqualToAnchor:_trackHeightSliderContainer.leadingAnchor constant:8],
        [smallTrackIcon.centerYAnchor constraintEqualToAnchor:_trackHeightSliderContainer.centerYAnchor],
        [smallTrackIcon.widthAnchor constraintEqualToConstant:12],
        [smallTrackIcon.heightAnchor constraintEqualToConstant:12],

        [_trackHeightSlider.leadingAnchor constraintEqualToAnchor:smallTrackIcon.trailingAnchor constant:4],
        [_trackHeightSlider.trailingAnchor constraintEqualToAnchor:largeTrackIcon.leadingAnchor constant:-4],
        [_trackHeightSlider.centerYAnchor constraintEqualToAnchor:_trackHeightSliderContainer.centerYAnchor],

        [largeTrackIcon.trailingAnchor constraintEqualToAnchor:_trackHeightSliderContainer.trailingAnchor constant:-8],
        [largeTrackIcon.centerYAnchor constraintEqualToAnchor:_trackHeightSliderContainer.centerYAnchor],
        [largeTrackIcon.widthAnchor constraintEqualToConstant:12],
        [largeTrackIcon.heightAnchor constraintEqualToConstant:12],
    ]];

    // View selector container (below track height slider, left of waveform)
    _viewSelectorContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _viewSelectorContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _viewSelectorContainer.wantsLayer = YES;
    _viewSelectorContainer.layer.backgroundColor = CGColorCreateGenericRGB(0.12, 0.12, 0.12, 1.0);
    [view addSubview:_viewSelectorContainer];

    // View label
    NSTextField *viewLabel = [[NSTextField alloc] init];
    viewLabel.translatesAutoresizingMaskIntoConstraints = NO;
    viewLabel.stringValue = @"View:";
    viewLabel.editable = NO;
    viewLabel.bordered = NO;
    viewLabel.drawsBackground = NO;
    viewLabel.textColor = [NSColor secondaryLabelColor];
    viewLabel.font = [NSFont systemFontOfSize:11];
    [viewLabel setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_viewSelectorContainer addSubview:viewLabel];

    // View dropdown popup button
    _viewSelectorPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _viewSelectorPopup.translatesAutoresizingMaskIntoConstraints = NO;
    _viewSelectorPopup.controlSize = NSControlSizeSmall;
    _viewSelectorPopup.font = [NSFont systemFontOfSize:11];
    _viewSelectorPopup.target = self;
    _viewSelectorPopup.action = @selector(viewSelectorChanged:);
    [_viewSelectorContainer addSubview:_viewSelectorPopup];

    // Populate the view dropdown
    [self populateViewSelector];

    // Layout constraints for view selector container contents
    [NSLayoutConstraint activateConstraints:@[
        [viewLabel.leadingAnchor constraintEqualToAnchor:_viewSelectorContainer.leadingAnchor constant:8],
        [viewLabel.centerYAnchor constraintEqualToAnchor:_viewSelectorContainer.centerYAnchor],

        [_viewSelectorPopup.leadingAnchor constraintEqualToAnchor:viewLabel.trailingAnchor constant:4],
        [_viewSelectorPopup.trailingAnchor constraintLessThanOrEqualToAnchor:_viewSelectorContainer.trailingAnchor constant:-8],
        [_viewSelectorPopup.centerYAnchor constraintEqualToAnchor:_viewSelectorContainer.centerYAnchor],
    ]];

    // Timeline ruler at the top (right of track height slider)
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
    _rowHeadingsView.rowHeight = savedRowHeight;
    [view addSubview:_rowHeadingsView];

    // Effects grid (Metal-backed timeline)
    _effectsGridView = [[XLEffectsGridView alloc] initWithFrame:NSZeroRect];
    _effectsGridView.translatesAutoresizingMaskIntoConstraints = NO;
    _effectsGridView.dataSource = self;
    _effectsGridView.delegate = self;
    _effectsGridView.rowHeight = savedRowHeight;  // Sync with row headings
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
    // Initialize zoom properties to match effects grid
    _transportBar.minZoomLevel = _effectsGridView.minZoomLevel;
    _transportBar.maxZoomLevel = _effectsGridView.maxZoomLevel;
    _transportBar.zoomLevel = _effectsGridView.zoomLevel;
    [view addSubview:_transportBar];

    // Effect palette moved to bottom panel in SwiftUI - no longer in sequencer view

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
    _scrollCoordinator.maxHorizontalScrollOffset = _sequenceDurationMS * _scrollCoordinator.zoomLevel;
    _scrollCoordinator.maxVerticalScrollOffset = rowCount * savedRowHeight;

    // Layout constraints (effect palette removed - now in top SwiftUI panel)
    // Layout order from top to bottom:
    // 1. Track height slider (left) | Timeline ruler (right)
    // 2. View selector (left) | Waveform (right) - waveform aligned with timeline
    // 3. Row headings (left) | Effects grid (right)
    // 4. Transport bar (full width)
    [NSLayoutConstraint activateConstraints:@[
        // Track height slider container: top-left corner
        [_trackHeightSliderContainer.topAnchor constraintEqualToAnchor:view.topAnchor],
        [_trackHeightSliderContainer.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_trackHeightSliderContainer.widthAnchor constraintEqualToConstant:kRowHeaderWidth],
        [_trackHeightSliderContainer.heightAnchor constraintEqualToConstant:kTimelineRulerHeight],

        // Timeline ruler: right of track height slider, extends to right edge
        [_timelineRuler.topAnchor constraintEqualToAnchor:view.topAnchor],
        [_timelineRuler.leadingAnchor constraintEqualToAnchor:_trackHeightSliderContainer.trailingAnchor],
        [_timelineRuler.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_timelineRuler.heightAnchor constraintEqualToConstant:kTimelineRulerHeight],

        // View selector container: below track height slider, left of waveform
        [_viewSelectorContainer.topAnchor constraintEqualToAnchor:_trackHeightSliderContainer.bottomAnchor],
        [_viewSelectorContainer.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_viewSelectorContainer.widthAnchor constraintEqualToConstant:kRowHeaderWidth],
        [_viewSelectorContainer.heightAnchor constraintEqualToConstant:kWaveformHeight],

        // Waveform: below timeline ruler, aligned with timeline (right of view selector)
        [_waveformView.topAnchor constraintEqualToAnchor:_timelineRuler.bottomAnchor],
        [_waveformView.leadingAnchor constraintEqualToAnchor:_viewSelectorContainer.trailingAnchor],
        [_waveformView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_waveformView.heightAnchor constraintEqualToConstant:kWaveformHeight],

        // Row headings: left side, below view selector, above transport bar
        [_rowHeadingsView.topAnchor constraintEqualToAnchor:_viewSelectorContainer.bottomAnchor],
        [_rowHeadingsView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_rowHeadingsView.widthAnchor constraintEqualToConstant:kRowHeaderWidth],
        [_rowHeadingsView.bottomAnchor constraintEqualToAnchor:_transportBar.topAnchor],

        // Effects grid: main area, right of row headings, below waveform, above transport bar
        [_effectsGridView.topAnchor constraintEqualToAnchor:_waveformView.bottomAnchor],
        [_effectsGridView.leadingAnchor constraintEqualToAnchor:_rowHeadingsView.trailingAnchor],
        [_effectsGridView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_effectsGridView.bottomAnchor constraintEqualToAnchor:_transportBar.topAnchor],

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

    // Refresh the view selector dropdown
    [self populateViewSelector];

    // Load audio for the sequence
    [self loadAudioForSequence];

    // Load saved zoom level for this sequence (if any)
    [self loadZoomLevelForCurrentSequence];
}

- (void)updateViewsForSequenceChange {
    // Update timeline ruler
    if (_timelineRuler) {
        _timelineRuler.sequenceDuration = _sequenceDurationMS / 1000.0;
        _timelineRuler.frameRate = _frameRate;
        [self reloadTimingMarksForRuler];
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

    // First pass: count total effects from ALL layers
    NSUInteger totalEffects = 0;
    for (NSUInteger i = 0; i < (NSUInteger)elementCount; i++) {
        NSDictionary *elem = elements[i];
        NSInteger layerCount = [elem[@"effectLayerCount"] integerValue];
        for (NSInteger layer = 0; layer < layerCount; layer++) {
            NSArray *effects = [self.engineBridge getEffectsForElementAtIndex:(NSInteger)i layer:layer];
            totalEffects += effects.count;
        }
    }

    // Allocate row data - one row per element initially (collapsed state)
    // Will grow dynamically when layers are expanded
    _rowCapacity = (NSUInteger)elementCount + 32;
    _rowCount = (NSUInteger)elementCount;
    _rowData = (XLRowEntry *)calloc(_rowCapacity, sizeof(XLRowEntry));

    // Allocate effect offset array (not used with new layer system, but keep for compatibility)
    _effectOffsetCapacity = _rowCapacity;
    _effectOffsetPerRow = (NSUInteger *)calloc(_effectOffsetCapacity, sizeof(NSUInteger));

    // Allocate effect data for ALL layers
    _effectCapacity = totalEffects + 64;
    _effectCount = 0;
    _effectData = (XLEffectEntry *)calloc(_effectCapacity, sizeof(XLEffectEntry));

    // Populate row and effect data
    for (NSUInteger i = 0; i < (NSUInteger)elementCount; i++) {
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

        // Set type based on element dictionary
        NSString *typeStr = elem[@"type"];
        BOOL isGroup = [elem[@"isGroup"] boolValue];

        if ([typeStr isEqualToString:@"timing"]) {
            row->type = XLElementTypeTiming;
        } else if ([typeStr isEqualToString:@"submodel"]) {
            row->type = XLElementTypeSubmodel;
        } else if ([typeStr isEqualToString:@"strand"]) {
            row->type = XLElementTypeStrand;
        } else if (isGroup || [typeStr isEqualToString:@"group"]) {
            row->type = XLElementTypeModelGroup;
        } else {
            row->type = XLElementTypeModel;
        }

        row->effectLayerCount = [elem[@"effectLayerCount"] integerValue];
        row->elementIndex = (NSInteger)i;
        row->indent = 0;
        row->layerIndex = -1;  // -1 means this is the main element row (not a layer sub-row)
        row->isLayerRow = NO;

        // Elements with multiple layers are expandable (except timing tracks)
        if (row->type != XLElementTypeTiming && row->effectLayerCount > 1) {
            row->expandable = YES;
            row->expanded = NO;  // Start collapsed
        } else {
            row->expandable = NO;
            row->expanded = NO;
        }

        // Store effect offset for this row (legacy, kept for compatibility)
        _effectOffsetPerRow[i] = _effectCount;

        // Load effects from ALL layers for this element
        for (NSInteger layer = 0; layer < row->effectLayerCount; layer++) {
            NSArray *effects = [self.engineBridge getEffectsForElementAtIndex:(NSInteger)i layer:layer];
            for (NSDictionary *eff in effects) {
                if (_effectCount >= _effectCapacity) {
                    // Grow the array
                    _effectCapacity *= 2;
                    _effectData = (XLEffectEntry *)realloc(_effectData, _effectCapacity * sizeof(XLEffectEntry));
                }

                XLEffectEntry *entry = &_effectData[_effectCount];
                entry->elementIndex = (NSInteger)i;
                entry->layerIndex = layer;  // Store the actual layer index
                entry->effectIndex = [eff[@"id"] integerValue];
                entry->startTimeMS = [eff[@"startTimeMS"] doubleValue];
                entry->endTimeMS = [eff[@"endTimeMS"] doubleValue];
                entry->effectTypeIndex = [eff[@"effectIndex"] integerValue];

                // Store effect type name and compute color
                NSString *effectTypeName = eff[@"effectType"];

                // Special handling for "On" effect - use the actual palette color
                if ([effectTypeName isEqualToString:@"On"]) {
                    NSInteger effectId = [eff[@"id"] integerValue];
                    NSString *paletteString = [self.engineBridge getEffectPalette:effectId];
                    NSString *firstColor = XLExtractFirstPaletteColor(paletteString);
                    if (firstColor && firstColor.length > 0) {
                        entry->colorARGB = XLParseHexColor(firstColor);
                    } else {
                        entry->colorARGB = XLColorForEffectTypeName(effectTypeName);
                    }
                } else {
                    entry->colorARGB = XLColorForEffectTypeName(effectTypeName);
                }

                if (effectTypeName) {
                    strncpy(entry->effectTypeName, [effectTypeName UTF8String], XL_EFFECT_TYPE_NAME_MAX - 1);
                    entry->effectTypeName[XL_EFFECT_TYPE_NAME_MAX - 1] = '\0';
                } else {
                    entry->effectTypeName[0] = '\0';
                }

                entry->selected = [eff[@"selected"] boolValue];
                entry->locked = [eff[@"protected"] boolValue];
                entry->renderDisabled = NO;

                _effectCount++;
            }
        }
    }

    // Sort rows so timing tracks always appear at the top
    // This is the standard xLights behavior - timing tracks are always first
    [self sortRowsWithTimingFirst];

    NSLog(@"XLSequencerViewController: Loaded %lu elements with %lu effects from real sequence (duration: %.0f ms)",
          (unsigned long)_rowCount, (unsigned long)_effectCount, _sequenceDurationMS);
}

- (void)sortRowsWithTimingFirst {
    if (!_rowData || _rowCount < 2) return;

    // Count timing tracks
    NSUInteger timingCount = 0;
    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (_rowData[i].type == XLElementTypeTiming) {
            timingCount++;
        }
    }

    if (timingCount == 0 || timingCount == _rowCount) {
        // Nothing to sort - either no timing tracks or all timing tracks
        return;
    }

    // Allocate temporary arrays for stable partition
    XLRowEntry *timingRows = (XLRowEntry *)malloc(timingCount * sizeof(XLRowEntry));
    XLRowEntry *otherRows = (XLRowEntry *)malloc((_rowCount - timingCount) * sizeof(XLRowEntry));

    NSUInteger timingIdx = 0;
    NSUInteger otherIdx = 0;

    // Partition into timing and non-timing (preserving relative order)
    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (_rowData[i].type == XLElementTypeTiming) {
            timingRows[timingIdx++] = _rowData[i];
        } else {
            otherRows[otherIdx++] = _rowData[i];
        }
    }

    // Copy timing tracks first, then other tracks
    memcpy(_rowData, timingRows, timingCount * sizeof(XLRowEntry));
    memcpy(&_rowData[timingCount], otherRows, (_rowCount - timingCount) * sizeof(XLRowEntry));

    free(timingRows);
    free(otherRows);

    NSLog(@"XLSequencerViewController: Sorted %lu timing tracks to top", (unsigned long)timingCount);
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

    // Demo effect type names for consistent coloring
    static NSString * const kDemoEffectTypes[] = {
        @"Fire", @"Bars", @"Butterfly", @"Candle", @"Circles", @"ColorWash",
        @"Curtain", @"Fireworks", @"Galaxy", @"Garlands", @"Lightning",
        @"Liquid", @"Marquee", @"Meteors", @"Morph", @"Music", @"Pinwheel",
        @"Plasma", @"Ripple", @"Shimmer", @"Snowflakes", @"Spirals",
        @"Strobe", @"Twinkle", @"Wave", @"Text", @"Pictures", @"Video",
        @"On", @"Off"
    };
    static const NSUInteger kDemoEffectTypeCount = sizeof(kDemoEffectTypes) / sizeof(kDemoEffectTypes[0]);

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
            // Use consistent color and effect type name
            NSString *effectTypeName = kDemoEffectTypes[(row + j) % kDemoEffectTypeCount];
            eff->colorARGB = XLColorForEffectTypeName(effectTypeName);
            strncpy(eff->effectTypeName, [effectTypeName UTF8String], XL_EFFECT_TYPE_NAME_MAX - 1);
            eff->effectTypeName[XL_EFFECT_TYPE_NAME_MAX - 1] = '\0';
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

- (void)timelineRuler:(XLTimelineRulerView *)ruler didRequestTimingMarkAtSeconds:(NSTimeInterval)positionSeconds {
    if (!_engineBridge || ![_engineBridge isSequenceLoaded]) {
        NSLog(@"XLSequencerViewController: Cannot create timing mark - no sequence loaded");
        return;
    }

    // Get the active timing track name
    NSString *activeTrack = [_engineBridge getActiveTimingTrackName];
    if (!activeTrack || activeTrack.length == 0) {
        NSLog(@"XLSequencerViewController: No active timing track - cannot create timing mark");
        // TODO: Show alert or auto-select first timing track
        return;
    }

    NSInteger timeMS = (NSInteger)(positionSeconds * 1000.0);

    // Create timing mark on layer 0 with auto-generated end time (one frame)
    NSInteger frameTimeMS = (_frameRate > 0) ? (1000 / _frameRate) : 50;
    NSInteger endTimeMS = timeMS + frameTimeMS;

    NSInteger markId = [_engineBridge createTimingMark:activeTrack
                                                 layer:0
                                           startTimeMS:timeMS
                                             endTimeMS:endTimeMS
                                                 label:nil];

    if (markId >= 0) {
        NSLog(@"XLSequencerViewController: Created timing mark %ld at %.3f seconds", (long)markId, positionSeconds);
        [self reloadTimingMarksForRuler];
        [_effectsGridView reloadData];  // Refresh snap points
    } else {
        NSLog(@"XLSequencerViewController: Failed to create timing mark");
    }
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didMoveTimingMarkId:(NSInteger)markId toSeconds:(NSTimeInterval)positionSeconds {
    if (!_engineBridge || ![_engineBridge isSequenceLoaded]) {
        return;
    }

    NSInteger startMS = (NSInteger)(positionSeconds * 1000.0);

    // Get the current mark info to preserve the duration
    NSDictionary *markInfo = [_engineBridge getTimingMark:markId];
    if (!markInfo) {
        NSLog(@"XLSequencerViewController: Timing mark %ld not found", (long)markId);
        return;
    }

    NSInteger oldStartMS = [markInfo[@"startTimeMS"] integerValue];
    NSInteger oldEndMS = [markInfo[@"endTimeMS"] integerValue];
    NSInteger duration = oldEndMS - oldStartMS;
    NSInteger endMS = startMS + duration;

    BOOL success = [_engineBridge moveTimingMark:markId startTimeMS:startMS endTimeMS:endMS];
    if (success) {
        NSLog(@"XLSequencerViewController: Moved timing mark %ld to %.3f seconds", (long)markId, positionSeconds);
        [self reloadTimingMarksForRuler];
        [_effectsGridView reloadData];  // Refresh snap points
    }
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didRequestDeleteTimingMarkId:(NSInteger)markId {
    if (!_engineBridge || ![_engineBridge isSequenceLoaded]) {
        return;
    }

    BOOL success = [_engineBridge deleteTimingMark:markId];
    if (success) {
        NSLog(@"XLSequencerViewController: Deleted timing mark %ld", (long)markId);
        [self reloadTimingMarksForRuler];
        [_effectsGridView reloadData];  // Refresh snap points
    }
}

- (void)reloadTimingMarksForRuler {
    if (!_engineBridge || ![_engineBridge isSequenceLoaded]) {
        _timelineRuler.timingMarks = @[];
        return;
    }

    // Get timing marks from the active timing track
    NSArray<NSNumber *> *markTimes = [_engineBridge getActiveTimingMarkTimes];
    if (!markTimes || markTimes.count == 0) {
        _timelineRuler.timingMarks = @[];
        return;
    }

    // Convert to the format expected by the ruler view
    // The ruler expects array of dictionaries with id, startTimeMS, label
    NSString *activeTrack = [_engineBridge getActiveTimingTrackName];
    NSArray<NSDictionary *> *fullMarks = [_engineBridge getTimingMarks:activeTrack layer:0];

    _timelineRuler.timingMarks = fullMarks ?: @[];
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
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData || !_effectData) return 0;

    XLRowEntry *rowEntry = &_rowData[row];
    NSInteger elementIndex = rowEntry->elementIndex;
    NSInteger count = 0;

    // Determine which layer(s) to show based on row type
    if (rowEntry->isLayerRow) {
        // Layer sub-row: show only effects for this specific layer
        NSInteger targetLayer = rowEntry->layerIndex;
        for (NSUInteger i = 0; i < _effectCount; i++) {
            if (_effectData[i].elementIndex == elementIndex &&
                _effectData[i].layerIndex == targetLayer) {
                count++;
            }
        }
    } else if (rowEntry->expanded) {
        // Main row when expanded: show only layer 0 (other layers shown in sub-rows)
        for (NSUInteger i = 0; i < _effectCount; i++) {
            if (_effectData[i].elementIndex == elementIndex &&
                _effectData[i].layerIndex == 0) {
                count++;
            }
        }
    } else {
        // Main row when collapsed: show ALL effects from all layers
        for (NSUInteger i = 0; i < _effectCount; i++) {
            if (_effectData[i].elementIndex == elementIndex) {
                count++;
            }
        }
    }
    return count;
}

- (XLEffectRenderInfo)effectsGrid:(XLEffectsGridView *)gridView
                 effectInfoForRow:(NSInteger)row
                          atIndex:(NSInteger)effectIndex
{
    XLEffectRenderInfo info;
    memset(&info, 0, sizeof(info));

    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData || !_effectData) {
        return info;
    }

    XLRowEntry *rowEntry = &_rowData[row];
    NSInteger elementIndex = rowEntry->elementIndex;
    NSInteger matchIndex = 0;

    // Determine which layer(s) to show based on row type
    for (NSUInteger i = 0; i < _effectCount; i++) {
        if (_effectData[i].elementIndex != elementIndex) continue;

        // Filter by layer based on row type
        if (rowEntry->isLayerRow) {
            // Layer sub-row: show only effects for this specific layer
            if (_effectData[i].layerIndex != rowEntry->layerIndex) continue;
        } else if (rowEntry->expanded) {
            // Main row when expanded: show only layer 0
            if (_effectData[i].layerIndex != 0) continue;
        }
        // else: collapsed main row shows all layers

        if (matchIndex == effectIndex) {
            XLEffectEntry *eff = &_effectData[i];
            info.startTimeMS = eff->startTimeMS;
            info.endTimeMS = eff->endTimeMS;
            info.row = row;
            info.layer = eff->layerIndex;
            info.effectIndex = eff->effectTypeIndex;
            info.colorARGB = eff->colorARGB;
            strncpy(info.effectTypeName, eff->effectTypeName, XL_EFFECT_TYPE_NAME_MAX - 1);
            info.effectTypeName[XL_EFFECT_TYPE_NAME_MAX - 1] = '\0';
            info.selected = eff->selected;
            info.locked = eff->locked;
            info.renderDisabled = eff->renderDisabled;
            return info;
        }
        matchIndex++;
    }

    return info;
}

- (CGFloat)sequenceLengthMSForEffectsGrid:(XLEffectsGridView *)gridView {
    return _sequenceDurationMS;
}

- (NSArray<NSNumber *> *)timingMarksForEffectsGrid:(XLEffectsGridView *)gridView {
    if (!_engineBridge || ![_engineBridge isSequenceLoaded]) {
        return @[];
    }

    // Get timing mark times from the active timing track for snap-to functionality
    NSArray<NSNumber *> *markTimes = [_engineBridge getActiveTimingMarkTimes];
    return markTimes ?: @[];
}

#pragma mark - XLEffectsGridDelegate

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didSelectEffectAtRow:(NSInteger)row
          effectIndex:(NSInteger)effectIndex
{
    NSLog(@"Selected effect at row %ld, index %ld", (long)row, (long)effectIndex);

    // Get the actual effect ID from our data
    // Use -1 as sentinel for "no effect" since 0 can be a valid effect ID
    NSInteger effectId = -1;
    NSString *effectType = nil;

    if (row >= 0 && row < (NSInteger)_rowCount && _rowData && _effectData) {
        // Find effect by matching elementIndex - this works correctly after row reordering
        NSInteger elementIndex = _rowData[row].elementIndex;
        NSInteger matchIndex = 0;
        for (NSUInteger i = 0; i < _effectCount; i++) {
            if (_effectData[i].elementIndex == elementIndex) {
                if (matchIndex == effectIndex) {
                    XLEffectEntry *eff = &_effectData[i];
                    effectId = eff->effectIndex;
                    NSLog(@"  Found effect: effectIndex=%ld, startTimeMS=%.0f, endTimeMS=%.0f",
                          (long)eff->effectIndex, eff->startTimeMS, eff->endTimeMS);

                    // Get effect type from engine if available (effectId >= 0 is valid)
                    if (_engineBridge && effectId >= 0) {
                        NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
                        effectType = effectInfo[@"effectType"];
                        NSLog(@"  effectType from engine: %@", effectType);
                    }
                    break;
                }
                matchIndex++;
            }
        }
    } else {
        NSLog(@"  Bounds check failed: row=%ld, _rowCount=%lu", (long)row, (unsigned long)_rowCount);
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

    // Clicking on empty area clears selection (use -1 as "no effect" sentinel)
    NSDictionary *userInfo = @{
        @"effectId": @(-1),
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
    didMoveCursorToTimeMS:(CGFloat)timeMS
{
    // Forward cursor position to waveform view for synchronized cursor line
    _waveformView.cursorPositionMS = timeMS;
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

    XLRowEntry *rowEntry = &_rowData[row];
    NSString *name = [NSString stringWithUTF8String:rowEntry->name];

    // For main rows (not layer sub-rows), append layer count if > 1
    if (!rowEntry->isLayerRow && rowEntry->effectLayerCount > 1) {
        return [NSString stringWithFormat:@"%@ [%ld]", name, (long)rowEntry->effectLayerCount];
    }

    return name;
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

    XLRowEntry *mainRow = &_rowData[row];

    // Only allow expand/collapse on main element rows with multiple layers
    if (mainRow->isLayerRow || !mainRow->expandable) return;

    BOOL wasExpanded = mainRow->expanded;
    mainRow->expanded = !wasExpanded;

    NSLog(@"Toggled expand for row %ld: %s (layers: %ld)", (long)row, mainRow->name, (long)mainRow->effectLayerCount);

    if (!wasExpanded) {
        // EXPANDING: Insert layer rows after the main row
        NSInteger layersToInsert = mainRow->effectLayerCount - 1;  // Layer 0 is shown on main row
        if (layersToInsert <= 0) return;

        // Ensure capacity
        NSUInteger newRowCount = _rowCount + (NSUInteger)layersToInsert;
        if (newRowCount > _rowCapacity) {
            _rowCapacity = newRowCount + 16;
            _rowData = (XLRowEntry *)realloc(_rowData, _rowCapacity * sizeof(XLRowEntry));
        }

        // Shift rows down to make room
        NSInteger insertPos = row + 1;
        if (insertPos < (NSInteger)_rowCount) {
            memmove(&_rowData[insertPos + layersToInsert], &_rowData[insertPos],
                    (_rowCount - (NSUInteger)insertPos) * sizeof(XLRowEntry));
        }

        // Insert layer rows
        for (NSInteger i = 0; i < layersToInsert; i++) {
            XLRowEntry *layerRow = &_rowData[insertPos + i];
            memset(layerRow, 0, sizeof(XLRowEntry));

            // Format name as "   [Layer 2]" etc (layer numbers are 1-indexed for display)
            snprintf(layerRow->name, sizeof(layerRow->name), "   [Layer %ld]", (long)(i + 2));

            layerRow->type = mainRow->type;
            layerRow->elementIndex = mainRow->elementIndex;
            layerRow->effectLayerCount = mainRow->effectLayerCount;
            layerRow->layerIndex = i + 1;  // Layer 1, 2, 3, etc.
            layerRow->isLayerRow = YES;
            layerRow->indent = 1;
            layerRow->expandable = NO;
            layerRow->expanded = NO;
        }

        _rowCount = newRowCount;

    } else {
        // COLLAPSING: Remove layer rows after the main row
        // Find how many consecutive layer rows to remove
        NSInteger layersToRemove = 0;
        for (NSInteger i = row + 1; i < (NSInteger)_rowCount; i++) {
            if (_rowData[i].isLayerRow && _rowData[i].elementIndex == mainRow->elementIndex) {
                layersToRemove++;
            } else {
                break;
            }
        }

        if (layersToRemove > 0) {
            // Shift rows up to close the gap
            NSInteger removeStart = row + 1;
            NSInteger removeEnd = removeStart + layersToRemove;
            if (removeEnd < (NSInteger)_rowCount) {
                memmove(&_rowData[removeStart], &_rowData[removeEnd],
                        (_rowCount - (NSUInteger)removeEnd) * sizeof(XLRowEntry));
            }
            _rowCount -= (NSUInteger)layersToRemove;
        }
    }

    [_rowHeadingsView reloadData];
    [_effectsGridView reloadData];
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

    [_rowHeadingsView reloadData];
    [_effectsGridView reloadData];
}

- (void)rowHeadings:(XLRowHeadingsView *)view didChangeVerticalScrollOffset:(CGFloat)offsetY {
    // Use scroll coordinator for synchronized vertical scroll
    [_scrollCoordinator viewDidScrollVertically:offsetY fromView:view];
}

#pragma mark - Track Height Slider

- (void)trackHeightSliderChanged:(NSSlider *)sender {
    CGFloat rowHeight = sender.doubleValue;

    // Sync row height to both views
    _rowHeadingsView.rowHeight = rowHeight;
    _effectsGridView.rowHeight = rowHeight;

    // Update scroll coordinator max vertical offset
    CGFloat viewHeight = NSHeight(_effectsGridView.bounds);
    CGFloat maxScrollY = _rowCount * rowHeight - viewHeight;
    _scrollCoordinator.maxVerticalScrollOffset = fmax(0, maxScrollY);

    // Save preference
    [[NSUserDefaults standardUserDefaults] setDouble:rowHeight forKey:@"XLSequencerRowHeight"];
}

#pragma mark - View Selector

- (void)populateViewSelector {
    // Temporarily disable action to prevent triggering viewSelectorChanged:
    SEL originalAction = _viewSelectorPopup.action;
    _viewSelectorPopup.action = nil;

    [_viewSelectorPopup removeAllItems];

    if (!self.engineBridge || ![self.engineBridge isSequenceLoaded]) {
        [_viewSelectorPopup addItemWithTitle:@"Master View"];
        _viewSelectorPopup.action = originalAction;
        return;
    }

    // Get all view names from the engine bridge
    NSArray<NSString *> *viewNames = [self.engineBridge getViewNames];
    for (NSString *viewName in viewNames) {
        [_viewSelectorPopup addItemWithTitle:viewName];
    }

    // Select the current view
    NSString *currentViewName = [self.engineBridge getCurrentViewName];
    if (currentViewName) {
        [_viewSelectorPopup selectItemWithTitle:currentViewName];
    }

    // Re-enable action
    _viewSelectorPopup.action = originalAction;
}

- (void)viewSelectorChanged:(NSPopUpButton *)sender {
    NSString *selectedViewName = sender.titleOfSelectedItem;
    if (!selectedViewName) return;

    // Check if we're already on this view
    NSString *currentViewName = [self.engineBridge getCurrentViewName];
    if ([selectedViewName isEqualToString:currentViewName]) {
        return;
    }

    NSLog(@"XLSequencerViewController: Switching to view: %@", selectedViewName);

    // Switch to the selected view via engine bridge
    BOOL success = [self.engineBridge setCurrentView:selectedViewName];
    if (success) {
        // Reload just the elements for the new view (lighter weight than full reloadSequenceData)
        [self reloadElementsForCurrentView];
    } else {
        NSLog(@"XLSequencerViewController: Failed to switch to view: %@", selectedViewName);
        // Revert the dropdown selection
        if (currentViewName) {
            [_viewSelectorPopup selectItemWithTitle:currentViewName];
        }
    }
}

- (void)reloadElementsForCurrentView {
    // Reload just the element/effect data without reloading sequence info, audio, etc.
    if (self.engineBridge && [self.engineBridge isSequenceLoaded]) {
        [self loadRealSequenceData];
    } else {
        [self buildDemoData];
    }

    // Update scroll limits for new row count
    if (_scrollCoordinator) {
        CGFloat rowHeight = _effectsGridView.rowHeight;
        CGFloat viewHeight = NSHeight(_effectsGridView.bounds);
        CGFloat maxScrollY = _rowCount * rowHeight - viewHeight;
        _scrollCoordinator.maxVerticalScrollOffset = fmax(0, maxScrollY);
    }

    // Reload the grid views
    [_effectsGridView reloadData];
    [_rowHeadingsView reloadData];
}

- (void)refreshViewSelector {
    // Re-populate the view dropdown (e.g., when sequence changes)
    [self populateViewSelector];
}

#pragma mark - Zoom Level Persistence

- (NSString *)zoomLevelKeyForCurrentSequence {
    if (!self.engineBridge || ![self.engineBridge isSequenceLoaded]) {
        return nil;
    }

    NSDictionary *seqInfo = [self.engineBridge getSequenceInfo];
    NSString *filePath = seqInfo[@"filePath"];
    if (!filePath || filePath.length == 0) {
        return nil;
    }

    // Create a stable key from the file path
    // Use the file name + a hash of the full path for uniqueness
    NSString *fileName = [filePath lastPathComponent];
    NSUInteger pathHash = [filePath hash];
    return [NSString stringWithFormat:@"XLSequencerZoom_%@_%lu", fileName, (unsigned long)pathHash];
}

- (void)saveZoomLevelForCurrentSequence {
    NSString *key = [self zoomLevelKeyForCurrentSequence];
    if (!key) return;

    CGFloat zoomLevel = _scrollCoordinator.zoomLevel;
    [[NSUserDefaults standardUserDefaults] setDouble:zoomLevel forKey:key];
}

- (void)loadZoomLevelForCurrentSequence {
    NSString *key = [self zoomLevelKeyForCurrentSequence];
    if (!key) return;

    CGFloat savedZoom = [[NSUserDefaults standardUserDefaults] doubleForKey:key];
    if (savedZoom > 0) {
        // Apply the saved zoom level
        [_scrollCoordinator setZoomLevel:savedZoom];
        _transportBar.zoomLevel = savedZoom;
    }
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

- (void)transportBar:(XLTransportBarView *)bar didChangeZoomLevel:(CGFloat)zoomLevel {
    // Use scroll coordinator for synchronized zoom centered on the playhead position
    // Convert playhead time (ms) to pixel position in view coordinates
    CGFloat playheadMS = bar.currentPositionMS;
    CGFloat currentZoom = _scrollCoordinator.zoomLevel;
    CGFloat playheadPixelX = playheadMS * currentZoom - _scrollCoordinator.horizontalScrollOffset;

    // If playhead is off-screen or at zero, fall back to view center
    CGFloat viewWidth = NSWidth(_effectsGridView.bounds);
    if (playheadPixelX < 0 || playheadPixelX > viewWidth || playheadMS <= 0) {
        playheadPixelX = viewWidth / 2.0;
    }

    [_scrollCoordinator setZoomLevel:zoomLevel centeredOnPointX:playheadPixelX];

    // Save zoom level for the current sequence
    [self saveZoomLevelForCurrentSequence];
}

- (void)transportBarDidRequestFitToWindow:(XLTransportBarView *)bar {
    CGFloat viewWidth = NSWidth(_effectsGridView.bounds);
    [_scrollCoordinator zoomToFitSequenceLength:_sequenceDurationMS viewWidth:viewWidth];

    // Save zoom level for the current sequence
    [self saveZoomLevelForCurrentSequence];
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

    // Keep transport bar zoom slider in sync
    _transportBar.zoomLevel = zoomLevel;

    // Save zoom level for the current sequence
    [self saveZoomLevelForCurrentSequence];
}

#pragma mark - XLPlaybackControllerDelegate

- (void)playbackControllerDidStartPlayback:(XLPlaybackController *)controller {
    _transportBar.isPlaying = YES;
    _timelineRuler.playbackRate = controller.playbackRate;
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
    // Debug: log every 60 calls (~1 second at 60fps)
    static int updateCount = 0;
    updateCount++;
    if (updateCount % 60 == 0) {
        NSLog(@"XLSequencerViewController: didUpdatePositionMS called, pos=%ld, updateCount=%d", (long)positionMS, updateCount);
    }

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
