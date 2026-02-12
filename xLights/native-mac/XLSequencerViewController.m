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
#import "input/XLKeyboardHandler.h"
#import "XLKeyBindingsWindowController.h"
#import "sequencer/XLTimelineRulerView.h"
#import "sequencer/XLEffectsGridView.h"
#import "sequencer/XLEffectPaletteView.h"
#import "sequencer/XLRowHeadingsView.h"
#import "sequencer/XLWaveformView.h"
#import "sequencer/XLTransportBarView.h"
#import "sequencer/XLRenderProgressIndicator.h"
#import "sequencer/XLScrollCoordinator.h"
#import "sequencer/XLUndoController.h"
#import "sequencer/XLAudioLoader.h"
#import "sequencer/XLStemsContainerView.h"
#import "sequencer/XLStemManager.h"
#import "sequencer/XLStemData.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "sequencer/XLAudioPlayer.h"
#import "XLEngineBridge.h"
#import "XLAppDelegate.h"
#import "XLPlaybackController.h"
#import "XLHousePreviewWindowController.h"
#import "XLEffectPresetsWindowController.h"
#import "XLSymbolLibraryManager.h"
#import <objc/runtime.h>
#import "XLEffectPropertiesViewController.h"
#import "dialogs/XLNewTimingDialog.h"
#import "dialogs/XLTimingImportDialog.h"
#import "XLSongRegionEditPopover.h"

// Import Swift generated header for XLSwiftUIWindowHelper
#if __has_include("xLights_Native-Swift.h")
#import "xLights_Native-Swift.h"
#elif __has_include("xLights-Swift.h")
#import "xLights-Swift.h"
#endif

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
    NSInteger timingColorIndex;  // Sequential color index for timing tracks (0, 1, 2...)
    BOOL isFolder;           // YES if this row is a track folder header
    BOOL folderCollapsed;    // YES if folder is collapsed (children hidden)
    char folderName[256];    // For folder rows: the folder name; for children: parent folder name
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
    CGFloat fadeInMS;
    CGFloat fadeOutMS;
    BOOL isLinkedToSymbol;
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

/// Extract the first enabled palette color from a palette string.
/// Checks C_CHECKBOX_PaletteN to find which colors are enabled,
/// then returns the color value from C_BUTTON_PaletteN for the first enabled one.
/// Format: "C_BUTTON_Palette1=#FF0000,C_CHECKBOX_Palette1=1,..."
static NSString *XLExtractFirstPaletteColor(NSString *paletteString) {
    if (!paletteString || paletteString.length == 0) {
        return nil;
    }

    // Parse all key=value pairs into a dictionary
    NSArray *pairs = [paletteString componentsSeparatedByString:@","];
    NSMutableDictionary *kvMap = [NSMutableDictionary dictionaryWithCapacity:pairs.count];
    for (NSString *pair in pairs) {
        NSRange eqRange = [pair rangeOfString:@"="];
        if (eqRange.location == NSNotFound) continue;
        NSString *key = [pair substringToIndex:eqRange.location];
        NSString *val = [pair substringFromIndex:eqRange.location + 1];
        val = [val stringByReplacingOccurrencesOfString:@"&comma;" withString:@","];
        val = [val stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        kvMap[key] = val;
    }

    // Find the first enabled palette color (check palettes 1-8)
    for (int i = 1; i <= 8; i++) {
        NSString *checkboxKey = [NSString stringWithFormat:@"C_CHECKBOX_Palette%d", i];
        NSString *checkboxVal = kvMap[checkboxKey];
        if (checkboxVal && [checkboxVal isEqualToString:@"1"]) {
            NSString *colorKey = [NSString stringWithFormat:@"C_BUTTON_Palette%d", i];
            NSString *colorVal = kvMap[colorKey];
            if (colorVal && colorVal.length > 0) {
                return colorVal;
            }
        }
    }

    // Fallback: return palette 1 color if no checkbox data found
    return kvMap[@"C_BUTTON_Palette1"];
}

// MARK: - Recent Sequence Row View

@interface XLRecentSequenceRow : NSView
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@property (nonatomic, assign) BOOL isHovered;
@end

@implementation XLRecentSequenceRow {
    NSTrackingArea *_trackingArea;
    NSImageView *_iconView;
    NSTextField *_nameLabel;
    NSTextField *_pathLabel;
    CALayer *_backgroundLayer;
}

- (instancetype)initWithFilePath:(NSString *)path target:(id)target action:(SEL)action {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _filePath = [path copy];
        _target = target;
        _action = action;
        _isHovered = NO;

        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6;

        // Icon
        _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        if (@available(macOS 11.0, *)) {
            NSImage *img = [NSImage imageWithSystemSymbolName:@"doc.text.fill"
                                     accessibilityDescription:@"Sequence"];
            NSImageSymbolConfiguration *config =
                [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightRegular];
            _iconView.image = [img imageWithSymbolConfiguration:config];
        }
        _iconView.contentTintColor = [NSColor secondaryLabelColor];
        [self addSubview:_iconView];

        // Filename
        NSString *filename = [path lastPathComponent];
        NSString *ext = [filename pathExtension];
        NSString *nameWithoutExt = [filename stringByDeletingPathExtension];

        _nameLabel = [NSTextField labelWithString:nameWithoutExt];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        _nameLabel.textColor = [NSColor labelColor];
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self addSubview:_nameLabel];

        // Folder path
        NSString *folder = [[path stringByDeletingLastPathComponent] lastPathComponent];
        NSString *detail = ext.length > 0 ?
            [NSString stringWithFormat:@".%@ — %@", ext, folder] :
            folder;

        _pathLabel = [NSTextField labelWithString:detail];
        _pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _pathLabel.font = [NSFont systemFontOfSize:11];
        _pathLabel.textColor = [NSColor tertiaryLabelColor];
        _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self addSubview:_pathLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:40],

            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:20],
            [_iconView.heightAnchor constraintEqualToConstant:20],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:8],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-10],
            [_nameLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],

            [_pathLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_pathLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-10],
            [_pathLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:0],
        ]];
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingCursorUpdate)
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)cursorUpdate:(NSEvent *)event {
    [[NSCursor pointingHandCursor] set];
}

- (void)mouseEntered:(NSEvent *)event {
    _isHovered = YES;
    self.layer.backgroundColor = [[NSColor colorWithWhite:1.0 alpha:0.08] CGColor];
    _iconView.contentTintColor = [NSColor controlAccentColor];
    _nameLabel.textColor = [NSColor controlAccentColor];
}

- (void)mouseExited:(NSEvent *)event {
    _isHovered = NO;
    self.layer.backgroundColor = nil;
    _iconView.contentTintColor = [NSColor secondaryLabelColor];
    _nameLabel.textColor = [NSColor labelColor];
}

- (void)mouseDown:(NSEvent *)event {
    self.layer.backgroundColor = [[NSColor colorWithWhite:1.0 alpha:0.12] CGColor];
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, self.bounds)) {
        if (_isHovered) {
            self.layer.backgroundColor = [[NSColor colorWithWhite:1.0 alpha:0.08] CGColor];
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        if (_target && _action) {
            [_target performSelector:_action withObject:self];
        }
#pragma clang diagnostic pop
    } else {
        self.layer.backgroundColor = nil;
    }
}

@end

@interface XLSequencerViewController () <XLTimelineRulerDelegate,
                                          XLEffectsGridDataSource,
                                          XLEffectsGridDelegate,
                                          XLEffectPaletteViewDelegate,
                                          XLTransportBarDelegate,
                                          XLWaveformViewDelegate,
                                          XLRowHeadingsDataSource,
                                          XLRowHeadingsDelegate,
                                          XLScrollCoordinatorDelegate,
                                          XLPlaybackControllerDelegate,
                                          XLStemsContainerDelegate> {
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

    // Empty state overlay (shown when no sequence is loaded)
    NSView *_emptyStateView;
    NSTextField *_recentLabel;
    NSStackView *_recentSequencesStack;

    // House preview floating window
    XLHousePreviewWindowController *_housePreviewController;

    // Effect presets window
    XLEffectPresetsWindowController *_presetsWindowController;

    // Symbol library manager
    XLSymbolLibraryManager *_symbolLibraryManager;
    BOOL _symbolPropagating;

    // Find/replace state for timing labels
    NSString *_timingSearchText;
    NSInteger _timingSearchLayer;       // Layer index being searched
    NSString *_timingSearchTrackName;   // Track name being searched
    NSInteger _timingLastFoundIndex;    // Index into timing marks array of last found match

    // MARK_SPOT / RETURN_TO_SPOT bookmark position (-1 = not set)
    NSInteger _markedPositionMS;

    // Paste mode: YES = paste by cell (relative), NO = paste by time (original timestamps)
    BOOL _pasteByCellMode;

    // Background auto-render toggle
    BOOL _backgroundRenderEnabled;

    // Number of timing track rows pinned at top of grid (set during sortRowsWithTimingFirst)
    NSInteger _timingRowCount;

    // Multi-cell range selection state (from rubber band selection)
    BOOL _cellRangeSelected;
    NSInteger _rangeStartRow;
    NSInteger _rangeEndRow;
    CGFloat _rangeStartTimeMS;
    CGFloat _rangeEndTimeMS;

    // Audio stems panel
    XLStemsContainerView *_stemsContainerView;
    XLStemManager *_stemManager;
    NSLayoutConstraint *_stemsHeightConstraint;
    BOOL _stemsPanelVisible;
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

// Timing track selector (in the view selector container, below view dropdown)
@property (nonatomic, strong) NSPopUpButton *timingTrackPopup;

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
    _markedPositionMS = -1;
    _pasteByCellMode = YES;  // Default to paste-by-cell
    _backgroundRenderEnabled = YES;
    _cellRangeSelected = NO;
    _rangeStartRow = -1;
    _rangeEndRow = -1;
    _rangeStartTimeMS = 0;
    _rangeEndTimeMS = 0;

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
    // Contains two rows: View dropdown and Timing Track dropdown
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
    viewLabel.font = [NSFont systemFontOfSize:10];
    [viewLabel setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_viewSelectorContainer addSubview:viewLabel];

    // View dropdown popup button
    _viewSelectorPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _viewSelectorPopup.translatesAutoresizingMaskIntoConstraints = NO;
    _viewSelectorPopup.controlSize = NSControlSizeMini;
    _viewSelectorPopup.font = [NSFont systemFontOfSize:10];
    _viewSelectorPopup.target = self;
    _viewSelectorPopup.action = @selector(viewSelectorChanged:);
    [_viewSelectorContainer addSubview:_viewSelectorPopup];

    // Timing label
    NSTextField *timingLabel = [[NSTextField alloc] init];
    timingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    timingLabel.stringValue = @"Timing:";
    timingLabel.editable = NO;
    timingLabel.bordered = NO;
    timingLabel.drawsBackground = NO;
    timingLabel.textColor = [NSColor secondaryLabelColor];
    timingLabel.font = [NSFont systemFontOfSize:10];
    [timingLabel setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_viewSelectorContainer addSubview:timingLabel];

    // Timing track dropdown popup button
    _timingTrackPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _timingTrackPopup.translatesAutoresizingMaskIntoConstraints = NO;
    _timingTrackPopup.controlSize = NSControlSizeMini;
    _timingTrackPopup.font = [NSFont systemFontOfSize:10];
    _timingTrackPopup.target = self;
    _timingTrackPopup.action = @selector(timingTrackChanged:);
    [_viewSelectorContainer addSubview:_timingTrackPopup];

    // Populate the dropdowns
    [self populateViewSelector];
    [self populateTimingTrackSelector];

    // Layout constraints for view selector container contents (two rows)
    // Row 1 (top): View label + popup
    // Row 2 (bottom): Timing label + popup
    [NSLayoutConstraint activateConstraints:@[
        // View row (top half)
        [viewLabel.leadingAnchor constraintEqualToAnchor:_viewSelectorContainer.leadingAnchor constant:8],
        [viewLabel.topAnchor constraintEqualToAnchor:_viewSelectorContainer.topAnchor constant:6],
        [viewLabel.widthAnchor constraintEqualToConstant:42],

        [_viewSelectorPopup.leadingAnchor constraintEqualToAnchor:viewLabel.trailingAnchor constant:2],
        [_viewSelectorPopup.trailingAnchor constraintLessThanOrEqualToAnchor:_viewSelectorContainer.trailingAnchor constant:-4],
        [_viewSelectorPopup.centerYAnchor constraintEqualToAnchor:viewLabel.centerYAnchor],

        // Timing row (bottom half)
        [timingLabel.leadingAnchor constraintEqualToAnchor:_viewSelectorContainer.leadingAnchor constant:8],
        [timingLabel.topAnchor constraintEqualToAnchor:viewLabel.bottomAnchor constant:6],
        [timingLabel.widthAnchor constraintEqualToConstant:42],

        [_timingTrackPopup.leadingAnchor constraintEqualToAnchor:timingLabel.trailingAnchor constant:2],
        [_timingTrackPopup.trailingAnchor constraintLessThanOrEqualToAnchor:_viewSelectorContainer.trailingAnchor constant:-4],
        [_timingTrackPopup.centerYAnchor constraintEqualToAnchor:timingLabel.centerYAnchor],
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
    // Default snap to YES when the preference hasn't been set yet
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"SnapToTiming"] != nil) {
        _effectsGridView.snapToTimingMarks = [defaults boolForKey:@"SnapToTiming"];
    } else {
        _effectsGridView.snapToTimingMarks = YES;
    }
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

    // Audio stems container (between waveform and effects grid)
    _stemManager = [[XLStemManager alloc] init];
    _stemManager.showFolderPath = [self.engineBridge getShowFolderPath];

    // Stems panel visibility — defaults to YES if key not set
    _stemsPanelVisible = ([[NSUserDefaults standardUserDefaults] objectForKey:@"StemsPanel.visible"] == nil)
                          ? YES
                          : [[NSUserDefaults standardUserDefaults] boolForKey:@"StemsPanel.visible"];

    _stemsContainerView = [[XLStemsContainerView alloc] initWithFrame:NSZeroRect];
    _stemsContainerView.stemManager = _stemManager;
    _stemsContainerView.delegate = self;
    _stemsContainerView.rowHeaderWidth = kRowHeaderWidth;
    _stemsContainerView.scrollCoordinator = _scrollCoordinator;
    [_stemsContainerView setSequenceLengthMS:_sequenceDurationMS];
    [_stemsContainerView setZoomLevel:_effectsGridView.zoomLevel];
    [view addSubview:_stemsContainerView];

    // (Left spacer removed — stems panel now spans full width)

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

    // Empty state overlay (shown when no sequence is loaded)
    _emptyStateView = [[NSView alloc] initWithFrame:NSZeroRect];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyStateView.wantsLayer = YES;
    _emptyStateView.layer.backgroundColor = [[NSColor colorWithWhite:0.12 alpha:1.0] CGColor];
    _emptyStateView.hidden = YES;

    // Icon
    NSImageView *emptyIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    emptyIcon.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 11.0, *)) {
        NSImage *img = [NSImage imageWithSystemSymbolName:@"music.note.list"
                                 accessibilityDescription:@"No sequence"];
        NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:48 weight:NSFontWeightLight];
        emptyIcon.image = [img imageWithSymbolConfiguration:config];
    }
    emptyIcon.contentTintColor = [NSColor tertiaryLabelColor];
    [_emptyStateView addSubview:emptyIcon];

    // Title label
    NSTextField *emptyTitle = [NSTextField labelWithString:@"No Sequence Open"];
    emptyTitle.translatesAutoresizingMaskIntoConstraints = NO;
    emptyTitle.font = [NSFont systemFontOfSize:20 weight:NSFontWeightMedium];
    emptyTitle.textColor = [NSColor secondaryLabelColor];
    emptyTitle.alignment = NSTextAlignmentCenter;
    [_emptyStateView addSubview:emptyTitle];

    // Subtitle label
    NSTextField *emptySubtitle = [NSTextField labelWithString:@"Create a new sequence or open an existing one to get started."];
    emptySubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    emptySubtitle.font = [NSFont systemFontOfSize:13];
    emptySubtitle.textColor = [NSColor tertiaryLabelColor];
    emptySubtitle.alignment = NSTextAlignmentCenter;
    [_emptyStateView addSubview:emptySubtitle];

    // New Sequence button
    NSButton *newSeqButton = [NSButton buttonWithTitle:@"New Sequence"
                                                target:self
                                                action:@selector(emptyStateNewSequence:)];
    newSeqButton.translatesAutoresizingMaskIntoConstraints = NO;
    newSeqButton.bezelStyle = NSBezelStyleRounded;
    newSeqButton.controlSize = NSControlSizeLarge;
    if (@available(macOS 11.0, *)) {
        newSeqButton.hasDestructiveAction = NO;
    }
    newSeqButton.keyEquivalent = @"";
    [_emptyStateView addSubview:newSeqButton];

    // Open Sequence button
    NSButton *openSeqButton = [NSButton buttonWithTitle:@"Open Sequence\u2026"
                                                 target:self
                                                 action:@selector(emptyStateOpenSequence:)];
    openSeqButton.translatesAutoresizingMaskIntoConstraints = NO;
    openSeqButton.bezelStyle = NSBezelStyleRounded;
    openSeqButton.controlSize = NSControlSizeLarge;
    openSeqButton.keyEquivalent = @"";
    [_emptyStateView addSubview:openSeqButton];

    // Stack the empty state content vertically, centered
    [NSLayoutConstraint activateConstraints:@[
        [emptyIcon.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [emptyIcon.bottomAnchor constraintEqualToAnchor:emptyTitle.topAnchor constant:-12],
        [emptyIcon.widthAnchor constraintEqualToConstant:56],
        [emptyIcon.heightAnchor constraintEqualToConstant:56],

        [emptyTitle.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [emptyTitle.centerYAnchor constraintEqualToAnchor:_emptyStateView.centerYAnchor constant:-20],

        [emptySubtitle.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [emptySubtitle.topAnchor constraintEqualToAnchor:emptyTitle.bottomAnchor constant:6],
        [emptySubtitle.widthAnchor constraintLessThanOrEqualToConstant:400],

        [newSeqButton.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor constant:-70],
        [newSeqButton.topAnchor constraintEqualToAnchor:emptySubtitle.bottomAnchor constant:20],
        [newSeqButton.widthAnchor constraintEqualToConstant:130],

        [openSeqButton.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor constant:70],
        [openSeqButton.topAnchor constraintEqualToAnchor:emptySubtitle.bottomAnchor constant:20],
        [openSeqButton.widthAnchor constraintEqualToConstant:140],
    ]];

    // Recent sequences section
    _recentLabel = [NSTextField labelWithString:@"Recent Sequences"];
    _recentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _recentLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _recentLabel.textColor = [NSColor tertiaryLabelColor];
    _recentLabel.alignment = NSTextAlignmentCenter;
    [_emptyStateView addSubview:_recentLabel];

    _recentSequencesStack = [[NSStackView alloc] init];
    _recentSequencesStack.translatesAutoresizingMaskIntoConstraints = NO;
    _recentSequencesStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _recentSequencesStack.spacing = 1;
    _recentSequencesStack.alignment = NSLayoutAttributeLeading;
    [_emptyStateView addSubview:_recentSequencesStack];

    [NSLayoutConstraint activateConstraints:@[
        [_recentLabel.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [_recentLabel.topAnchor constraintEqualToAnchor:newSeqButton.bottomAnchor constant:30],

        [_recentSequencesStack.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [_recentSequencesStack.topAnchor constraintEqualToAnchor:_recentLabel.bottomAnchor constant:8],
        [_recentSequencesStack.widthAnchor constraintLessThanOrEqualToConstant:400],
    ]];

    // Observe recent sequences changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(recentSequencesDidChange:)
                                                 name:@"XLRecentSequencesDidChange"
                                               object:nil];

    [view addSubview:_emptyStateView];

    // Set up scroll coordinator for synchronized scrolling
    _scrollCoordinator = [[XLScrollCoordinator alloc] init];
    _scrollCoordinator.timelineRulerView = _timelineRuler;
    _scrollCoordinator.effectsGridView = _effectsGridView;
    _scrollCoordinator.waveformView = _waveformView;
    _scrollCoordinator.rowHeadingsView = _rowHeadingsView;
    _scrollCoordinator.stemsContainerView = _stemsContainerView;
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
    // 3. Stems left spacer (left) | Stems container (right) - optional, variable height
    // 4. Row headings (left) | Effects grid (right)
    // 5. Transport bar (full width)

    // Create the stems height constraint — show header when visible, hidden otherwise
    _stemsHeightConstraint = [_stemsContainerView.heightAnchor constraintEqualToConstant:
                              _stemsPanelVisible ? kStemsHeaderHeight : 0];

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

        // Stems container: below waveform, full width
        [_stemsContainerView.topAnchor constraintEqualToAnchor:_waveformView.bottomAnchor],
        [_stemsContainerView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_stemsContainerView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        _stemsHeightConstraint,

        // Row headings: left side, below stems container, above transport bar
        [_rowHeadingsView.topAnchor constraintEqualToAnchor:_stemsContainerView.bottomAnchor],
        [_rowHeadingsView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_rowHeadingsView.widthAnchor constraintEqualToConstant:kRowHeaderWidth],
        [_rowHeadingsView.bottomAnchor constraintEqualToAnchor:_transportBar.topAnchor],

        // Effects grid: main area, right of row headings, below stems container, above transport bar
        [_effectsGridView.topAnchor constraintEqualToAnchor:_stemsContainerView.bottomAnchor],
        [_effectsGridView.leadingAnchor constraintEqualToAnchor:_rowHeadingsView.trailingAnchor],
        [_effectsGridView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_effectsGridView.bottomAnchor constraintEqualToAnchor:_transportBar.topAnchor],

        // Transport bar: full width at the very bottom
        [_transportBar.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_transportBar.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_transportBar.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [_transportBar.heightAnchor constraintEqualToConstant:kTransportBarHeight],

        // Empty state overlay: covers the stems + row headings + effects grid area
        [_emptyStateView.topAnchor constraintEqualToAnchor:_stemsContainerView.bottomAnchor],
        [_emptyStateView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_emptyStateView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_emptyStateView.bottomAnchor constraintEqualToAnchor:_transportBar.topAnchor],
    ]];

    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Initialize keyboard handler for processing key bindings
    // Use the show folder path so custom key_bindings.xml is loaded
    NSString *showFolder = [self.engineBridge getShowFolderPath];
    NSLog(@"XLSequencerViewController viewDidLoad: showFolder from engineBridge = '%@'", showFolder);
    // Fallback to UserDefaults if engine bridge doesn't have a show folder yet
    if (!showFolder || showFolder.length == 0) {
        showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
        NSLog(@"XLSequencerViewController: Fallback to UserDefaults showFolder = '%@'", showFolder);
    }
    self.keyboardHandler = [[XLKeyboardHandler alloc] initWithShowFolderPath:showFolder];
    self.keyboardHandler.delegate = self;
    NSLog(@"XLSequencerViewController: keyboardHandler initialized = %@, bindingCount = %lu",
          self.keyboardHandler, (unsigned long)[self.keyboardHandler bindingCount]);

    // Listen for show folder changes to reload key bindings
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showFolderDidChange:)
                                                 name:@"XLShowFolderDidChangeNotification"
                                               object:nil];

    // Listen for key bindings changes (from the Key Bindings editor window)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyBindingsDidChange:)
                                                 name:XLKeyBindingsDidChangeNotification
                                               object:nil];

    // Listen for effect parameter/palette changes to update preview
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(effectDidChange:)
                                                 name:@"XLEffectDidChangeNotification"
                                               object:nil];

    // Listen for command palette actions
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleZoomToSelection:)
                                                 name:@"XLZoomToSelection"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleApplyEffectFromCommandPalette:)
                                                 name:@"XLApplyEffectFromCommandPalette"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSnapEnabledDidChange:)
                                                 name:@"XLSnapEnabledDidChange"
                                               object:nil];

    // Listen for stem manager changes to sync with engine bridge
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(stemManagerDidChange:)
                                                 name:XLStemManagerDidChangeNotification
                                               object:nil];

    // Check sequence state and show/hide empty state accordingly.
    // This is needed because SwiftUI recreates this VC on tab switches,
    // and the empty state starts hidden by default in loadView.
    [self reloadSequenceData];
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

#pragma mark - Audio Stems Loading

- (void)loadStemsForSequence {
    _stemManager.showFolderPath = [self.engineBridge getShowFolderPath];

    if (!self.engineBridge || ![self.engineBridge isSequenceLoaded]) {
        [_stemManager removeAllStems];
        return;
    }

    // Check if the loaded sequence has audio stem references
    NSDictionary *seqInfo = [self.engineBridge getSequenceInfo];
    NSArray *stemDicts = seqInfo[@"audioStems"];
    if (stemDicts && [stemDicts isKindOfClass:[NSArray class]] && stemDicts.count > 0) {
        [_stemManager restoreFromDicts:stemDicts];
    } else {
        [_stemManager removeAllStems];
    }

    // Update sequence length on stems container
    [_stemsContainerView setSequenceLengthMS:_sequenceDurationMS];
}

- (void)stemManagerDidChange:(NSNotification *)note {
    // Keep engine bridge's stem dicts in sync for save
    self.engineBridge.audioStemDicts = [_stemManager serializeToDicts];
}

#pragma mark - Empty State

- (void)showEmptyState {
    _emptyStateView.hidden = NO;
    [self refreshRecentSequences];
}

- (void)hideEmptyState {
    _emptyStateView.hidden = YES;
}

- (void)refreshRecentSequences {
    for (NSView *v in [_recentSequencesStack.arrangedSubviews copy]) {
        [_recentSequencesStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    NSArray *recents = [[NSUserDefaults standardUserDefaults] arrayForKey:@"RecentSequences"];
    if (!recents || recents.count == 0) {
        _recentLabel.hidden = YES;
        _recentSequencesStack.hidden = YES;
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger shown = 0;

    for (NSString *path in recents) {
        if (![fm fileExistsAtPath:path]) continue;
        if (shown >= 10) break;

        XLRecentSequenceRow *row = [[XLRecentSequenceRow alloc]
            initWithFilePath:path
                      target:self
                      action:@selector(emptyStateOpenRecentSequence:)];
        [row.widthAnchor constraintEqualToConstant:340].active = YES;
        [_recentSequencesStack addArrangedSubview:row];
        shown++;
    }

    BOOL hasEntries = (shown > 0);
    _recentLabel.hidden = !hasEntries;
    _recentSequencesStack.hidden = !hasEntries;
}

- (void)emptyStateOpenRecentSequence:(XLRecentSequenceRow *)sender {
    NSString *path = sender.filePath;
    if (!path) return;

    XLSwiftUIWindowHelper *swiftHelper = [XLSwiftUIWindowHelper shared];
    XLEngineBridge *engineBridge = swiftHelper.engineBridge;

    if (!engineBridge) {
        NSLog(@"XLSequencerViewController: Cannot open recent sequence — engine bridge not available");
        return;
    }

    NSLog(@"XLSequencerViewController: Opening recent sequence: %@", path);
    BOOL success = [engineBridge loadSequence:path];
    if (success) {
        // Move to top of recents
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSMutableArray *recents = [[defaults arrayForKey:@"RecentSequences"] mutableCopy] ?: [NSMutableArray new];
        [recents removeObject:path];
        [recents insertObject:path atIndex:0];
        [defaults setObject:recents forKey:@"RecentSequences"];

        [swiftHelper notifySequenceDataChanged];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Failed to Open Sequence";
        alert.informativeText = [NSString stringWithFormat:@"Could not load the sequence file:\n%@", path];
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
}

- (void)recentSequencesDidChange:(NSNotification *)notification {
    if (!_emptyStateView.hidden) {
        [self refreshRecentSequences];
    }
}

- (void)effectDidChange:(NSNotification *)notification {
    [_effectsGridView setNeedsDisplay:YES];
    _renderProgressIndicator.animating = YES;
    [_playbackController renderCurrentFrame];

    if (!_symbolPropagating && _symbolLibraryManager && _engineBridge) {
        NSInteger selectedRenderIdx = _effectsGridView.selectedEffectID;
        if (selectedRenderIdx >= 0) {
            NSInteger effectId = [_effectsGridView effectIdAtRenderIndex:(NSUInteger)selectedRenderIdx];
            if (effectId >= 0) {
                NSString *symbolId = [_symbolLibraryManager symbolIdForEffect:effectId];
                if (symbolId) {
                    _symbolPropagating = YES;
                    [_symbolLibraryManager updateSymbol:symbolId fromEffect:effectId];
                    NSMutableArray<NSNumber *> *linkedEffects = [NSMutableArray array];
                    for (NSUInteger i = 0; i < _effectCount; i++) {
                        if (_effectData[i].isLinkedToSymbol && _effectData[i].effectIndex != effectId) {
                            NSString *otherSymId = [_symbolLibraryManager symbolIdForEffect:_effectData[i].effectIndex];
                            if ([otherSymId isEqualToString:symbolId]) {
                                [linkedEffects addObject:@(_effectData[i].effectIndex)];
                            }
                        }
                    }
                    if (linkedEffects.count > 0) {
                        [_symbolLibraryManager propagateSymbol:symbolId toEffects:linkedEffects];
                    }
                    _symbolPropagating = NO;
                }
            }
        }
    }
}

- (void)clearSequenceData {
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
    _rowCount = 0;
    _rowCapacity = 0;
    _effectCount = 0;
    _effectCapacity = 0;
    _usingRealData = NO;
    _sequenceDurationMS = 60000.0;
    _frameRate = 20;
}

- (void)emptyStateNewSequence:(id)sender {
    [NSApp sendAction:@selector(newSequence:) to:nil from:self];
}

- (void)emptyStateOpenSequence:(id)sender {
    [NSApp sendAction:@selector(openSequence:) to:nil from:self];
}

#pragma mark - House Preview

- (void)toggleHousePreview {
    if (!_housePreviewController) {
        _housePreviewController = [[XLHousePreviewWindowController alloc]
            initWithEngineBridge:self.engineBridge];
        _housePreviewController.playbackController = _playbackController;
        _playbackController.previewView = _housePreviewController.previewView;

        // Observe window close so the toolbar button stays in sync
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleHousePreviewWindowDidClose:)
                                                     name:NSWindowWillCloseNotification
                                                   object:_housePreviewController.window];
    }

    NSWindow *previewWindow = _housePreviewController.window;
    if (previewWindow.isVisible) {
        [previewWindow orderOut:nil];
        [[XLSwiftUIWindowHelper shared] setHousePreviewVisible:NO];
    } else {
        [previewWindow makeKeyAndOrderFront:nil];
        [_housePreviewController reloadModels];
        [[XLSwiftUIWindowHelper shared] setHousePreviewVisible:YES];
    }
}

- (void)handleHousePreviewWindowDidClose:(NSNotification *)note {
    [[XLSwiftUIWindowHelper shared] setHousePreviewVisible:NO];
}

/// Responder chain action for the View > Show Preview menu item and toolbar button.
- (IBAction)togglePreview:(id)sender {
    [self toggleHousePreview];
}

#pragma mark - Data Loading

- (void)reloadSequenceData {
    // Stop any current audio playback
    [_playbackController stop];

    // First try to load real data from the engine
    if (self.engineBridge && [self.engineBridge isSequenceLoaded]) {
        [self hideEmptyState];
        [self loadRealSequenceData];
    } else {
        [self clearSequenceData];
        [self showEmptyState];
    }

    // Update all views with new sequence properties
    [self updateViewsForSequenceChange];

    // Refresh the view selector and timing track dropdowns
    [self populateViewSelector];
    [self populateTimingTrackSelector];

    // Load audio for the sequence
    [self loadAudioForSequence];

    // Load audio stems for the sequence
    [self loadStemsForSequence];

    // Load saved zoom level for this sequence (if any)
    [self loadZoomLevelForCurrentSequence];

    // Sync active timing track color with grid view
    [self updateActiveTimingColorIndex];

    // Update symbol names for context menu
    [self updateAvailableSymbolNames];
}

- (void)updateAvailableSymbolNames {
    [self ensureSymbolLibraryManager];
    [_symbolLibraryManager reloadSymbols];
    _effectsGridView.availableSymbolNames = [_symbolLibraryManager symbolNames];
}

- (void)updateViewsForSequenceChange {
    // Update timeline ruler
    if (_timelineRuler) {
        _timelineRuler.sequenceDuration = _sequenceDurationMS / 1000.0;
        _timelineRuler.frameRate = _frameRate;
        [self reloadTimingMarksForRuler];
        [self reloadSongRegionsForRuler];
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

    // Set pinned timing row count on both views before reloading
    if (_effectsGridView) {
        _effectsGridView.pinnedTimingRowCount = _timingRowCount;
        [_effectsGridView reloadData];
    }
    if (_rowHeadingsView) {
        _rowHeadingsView.pinnedTimingRowCount = _timingRowCount;
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
        [self clearSequenceData];
        [self showEmptyState];
        return;
    }

    // First pass: count total effects from ALL layers
    NSUInteger totalEffects = 0;
    for (NSUInteger i = 0; i < (NSUInteger)elementCount; i++) {
        NSDictionary *elem = elements[i];
        NSInteger originalIndex = [elem[@"index"] integerValue];  // Use original element index
        NSInteger layerCount = [elem[@"effectLayerCount"] integerValue];
        for (NSInteger layer = 0; layer < layerCount; layer++) {
            NSArray *effects = [self.engineBridge getEffectsForElementAtIndex:originalIndex layer:layer];
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
    NSInteger timingTrackColorCounter = 0;
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
            row->timingColorIndex = timingTrackColorCounter++;
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
        NSInteger originalIndex = [elem[@"index"] integerValue];  // Use original element index
        row->elementIndex = originalIndex;  // Store original index for effect lookups
        row->indent = 0;
        row->layerIndex = -1;  // -1 means this is the main element row (not a layer sub-row)
        row->isLayerRow = NO;

        // Elements with multiple layers are expandable (including timing tracks)
        if (row->effectLayerCount > 1) {
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
            NSArray *effects = [self.engineBridge getEffectsForElementAtIndex:originalIndex layer:layer];
            for (NSDictionary *eff in effects) {
                if (_effectCount >= _effectCapacity) {
                    // Grow the array
                    _effectCapacity *= 2;
                    _effectData = (XLEffectEntry *)realloc(_effectData, _effectCapacity * sizeof(XLEffectEntry));
                }

                XLEffectEntry *entry = &_effectData[_effectCount];
                entry->elementIndex = originalIndex;  // Use original sequence element index to match row->elementIndex
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
                entry->fadeInMS = [eff[@"fadeInMS"] doubleValue];
                entry->fadeOutMS = [eff[@"fadeOutMS"] doubleValue];

                entry->isLinkedToSymbol = NO;
                if (_symbolLibraryManager && _symbolLibraryManager.symbolCount > 0) {
                    entry->isLinkedToSymbol = [_symbolLibraryManager isEffectLinked:entry->effectIndex];
                }

                _effectCount++;
            }
        }
    }

    // Sort rows so timing tracks always appear at the top
    // This is the standard xLights behavior - timing tracks are always first
    [self sortRowsWithTimingFirst];

    // Insert track folder headers and group elements
    [self insertTrackFolderRows:elements];

    // Expand all rows with multiple layers by default
    // Iterate backwards so inserted rows don't shift indices of rows we haven't processed yet
    for (NSInteger r = (NSInteger)_rowCount - 1; r >= 0; r--) {
        XLRowEntry *mainRow = &_rowData[r];
        if (!mainRow->expandable || mainRow->effectLayerCount <= 1) continue;

        mainRow->expanded = YES;

        NSInteger layersToInsert = mainRow->effectLayerCount - 1;  // Layer 0 shown on main row
        NSUInteger newRowCount = _rowCount + (NSUInteger)layersToInsert;

        // Ensure capacity
        if (newRowCount > _rowCapacity) {
            _rowCapacity = newRowCount + 32;
            _rowData = (XLRowEntry *)realloc(_rowData, _rowCapacity * sizeof(XLRowEntry));
            mainRow = &_rowData[r];  // Pointer may have moved
        }

        // Shift rows down to make room
        NSInteger insertPos = r + 1;
        if (insertPos < (NSInteger)_rowCount) {
            memmove(&_rowData[insertPos + layersToInsert], &_rowData[insertPos],
                    (_rowCount - (NSUInteger)insertPos) * sizeof(XLRowEntry));
        }

        // Insert layer rows
        for (NSInteger li = 0; li < layersToInsert; li++) {
            XLRowEntry *layerRow = &_rowData[insertPos + li];
            memset(layerRow, 0, sizeof(XLRowEntry));

            // Timing tracks with 3 layers use Phrases/Words/Phonemes naming
            if (mainRow->type == XLElementTypeTiming && mainRow->effectLayerCount == 3) {
                const char *layerNames[] = { "Words", "Phonemes" };
                snprintf(layerRow->name, sizeof(layerRow->name), "   %s", layerNames[li < 2 ? li : 1]);
            } else if (mainRow->type == XLElementTypeTiming) {
                snprintf(layerRow->name, sizeof(layerRow->name), "   [Layer %ld]", (long)(li + 2));
            } else {
                snprintf(layerRow->name, sizeof(layerRow->name), "   [Layer %ld]", (long)(li + 2));
            }

            layerRow->type = mainRow->type;
            layerRow->elementIndex = mainRow->elementIndex;
            layerRow->effectLayerCount = mainRow->effectLayerCount;
            layerRow->timingColorIndex = mainRow->timingColorIndex;
            layerRow->layerIndex = li + 1;
            layerRow->isLayerRow = YES;
            layerRow->indent = 1;
            layerRow->expandable = NO;
            layerRow->expanded = NO;
        }

        _rowCount = newRowCount;
    }

    // Recount timing rows after expansion (layer rows also have XLElementTypeTiming type)
    _timingRowCount = 0;
    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (_rowData[i].type == XLElementTypeTiming) {
            _timingRowCount++;
        } else {
            break; // Timing rows are sorted to top, first non-timing ends the run
        }
    }

    NSLog(@"XLSequencerViewController: Loaded %lu rows (%ld timing) with %lu effects from real sequence (duration: %.0f ms)",
          (unsigned long)_rowCount, (long)_timingRowCount, (unsigned long)_effectCount, _sequenceDurationMS);
}

- (void)sortRowsWithTimingFirst {
    if (!_rowData || _rowCount < 2) {
        _timingRowCount = 0;
        return;
    }

    // Count timing tracks
    NSUInteger timingCount = 0;
    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (_rowData[i].type == XLElementTypeTiming) {
            timingCount++;
        }
    }

    _timingRowCount = (NSInteger)timingCount;

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

- (void)insertTrackFolderRows:(NSArray<NSDictionary *> *)elements {
    // Get track folders from the engine
    NSArray<NSDictionary *> *folders = [self.engineBridge getTrackFolders];
    if (folders.count == 0) return;

    // Build a lookup: folder name -> folder info
    NSMutableDictionary<NSString *, NSDictionary *> *folderLookup = [NSMutableDictionary dictionary];
    for (NSDictionary *f in folders) {
        folderLookup[f[@"name"]] = f;
    }

    // Build element-name -> folder-name mapping from the elements array
    NSMutableDictionary<NSString *, NSString *> *elementFolderMap = [NSMutableDictionary dictionary];
    for (NSDictionary *elem in elements) {
        NSString *folder = elem[@"folder"];
        if (folder && folder.length > 0) {
            elementFolderMap[elem[@"name"]] = folder;
        }
    }

    if (elementFolderMap.count == 0) return;

    // Set folderName on existing rows (non-timing only)
    for (NSUInteger i = 0; i < _rowCount; i++) {
        XLRowEntry *row = &_rowData[i];
        if (row->type == XLElementTypeTiming) continue;

        NSString *rowName = [NSString stringWithUTF8String:row->name];
        NSString *folder = elementFolderMap[rowName];
        if (folder) {
            strncpy(row->folderName, [folder UTF8String], sizeof(row->folderName) - 1);
            row->folderName[sizeof(row->folderName) - 1] = '\0';
            row->indent = 1;
        }
    }

    // Now we need to group elements by folder and insert folder header rows.
    // Strategy: scan non-timing rows and when we see a new folder group, insert
    // a header row before the first element of that group.

    // Collect the ordered folder names (in the order they first appear)
    NSMutableArray<NSString *> *orderedFolders = [NSMutableArray array];
    NSMutableSet<NSString *> *seenFolders = [NSMutableSet set];
    for (NSUInteger i = _timingRowCount; i < _rowCount; i++) {
        XLRowEntry *row = &_rowData[i];
        if (row->folderName[0] != '\0') {
            NSString *fn = [NSString stringWithUTF8String:row->folderName];
            if (![seenFolders containsObject:fn]) {
                [orderedFolders addObject:fn];
                [seenFolders addObject:fn];
            }
        }
    }

    if (orderedFolders.count == 0) return;

    // Re-sort non-timing rows: folders appear inline at the position of their first member.
    // Scan original order, and when we encounter the first element of a folder, emit
    // the folder header + all its children. Subsequent elements of that folder are skipped
    // (already emitted with the header). Ungrouped elements are emitted in their original position.
    NSUInteger nonTimingCount = _rowCount - _timingRowCount;
    XLRowEntry *sortedNonTiming = (XLRowEntry *)calloc(nonTimingCount + orderedFolders.count, sizeof(XLRowEntry));
    NSUInteger writeIdx = 0;

    NSMutableSet<NSString *> *emittedFolders = [NSMutableSet set];

    for (NSUInteger i = _timingRowCount; i < _rowCount; i++) {
        XLRowEntry *row = &_rowData[i];

        if (row->folderName[0] != '\0') {
            NSString *fn = [NSString stringWithUTF8String:row->folderName];
            if ([emittedFolders containsObject:fn]) {
                // Already emitted this folder and its children — skip
                continue;
            }
            [emittedFolders addObject:fn];

            const char *fnCStr = [fn UTF8String];

            // Insert folder header row at this position
            XLRowEntry *folderRow = &sortedNonTiming[writeIdx++];
            memset(folderRow, 0, sizeof(XLRowEntry));
            strncpy(folderRow->name, fnCStr, sizeof(folderRow->name) - 1);
            folderRow->name[sizeof(folderRow->name) - 1] = '\0';
            strncpy(folderRow->folderName, fnCStr, sizeof(folderRow->folderName) - 1);
            folderRow->folderName[sizeof(folderRow->folderName) - 1] = '\0';
            folderRow->type = XLElementTypeModel;
            folderRow->isFolder = YES;
            folderRow->expandable = YES;
            folderRow->indent = 0;
            folderRow->elementIndex = -1;
            folderRow->layerIndex = -1;

            NSDictionary *fInfo = folderLookup[fn];
            BOOL collapsed = [fInfo[@"collapsed"] boolValue];
            folderRow->folderCollapsed = collapsed;
            folderRow->expanded = !collapsed;

            // Insert ALL children of this folder (if not collapsed)
            if (!collapsed) {
                for (NSUInteger j = _timingRowCount; j < _rowCount; j++) {
                    if (strcmp(_rowData[j].folderName, fnCStr) == 0) {
                        sortedNonTiming[writeIdx++] = _rowData[j];
                    }
                }
            }
        } else {
            // Ungrouped element — emit in its original position
            sortedNonTiming[writeIdx++] = *row;
        }
    }

    // Ensure capacity for the new total row count
    NSUInteger newRowCount = _timingRowCount + writeIdx;
    if (newRowCount > _rowCapacity) {
        _rowCapacity = newRowCount + 32;
        _rowData = (XLRowEntry *)realloc(_rowData, _rowCapacity * sizeof(XLRowEntry));
    }

    // Copy sorted non-timing rows back after timing rows
    memcpy(&_rowData[_timingRowCount], sortedNonTiming, writeIdx * sizeof(XLRowEntry));
    _rowCount = newRowCount;

    free(sortedNonTiming);

    NSLog(@"XLSequencerViewController: Inserted %lu track folder headers", (unsigned long)orderedFolders.count);
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

    // Count timing rows at the top
    _timingRowCount = 0;
    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (_rowData[i].type == XLElementTypeTiming) {
            _timingRowCount++;
        } else {
            break;
        }
    }

    NSLog(@"XLSequencerViewController: Using demo data with %lu rows (%ld timing) and %lu effects",
          (unsigned long)_rowCount, (long)_timingRowCount, (unsigned long)_effectCount);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

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

#pragma mark - Song Structure Region Delegate

- (void)timelineRuler:(XLTimelineRulerView *)ruler didRequestAddSongRegionBoundaryAtTimeMS:(NSInteger)timeMS {
    if (!_engineBridge || ![_engineBridge isSequenceLoaded]) return;
    [_engineBridge addSongStructureBoundaryAtTimeMS:timeMS];
    [self reloadSongRegionsForRuler];
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didMoveSongRegionBoundaryAtIndex:(NSInteger)idx toTimeMS:(NSInteger)timeMS {
    if (!_engineBridge || ![_engineBridge isSequenceLoaded]) return;
    [_engineBridge moveSongStructureBoundary:idx toTimeMS:timeMS];
    [self reloadSongRegionsForRuler];
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didRequestDeleteSongRegionBoundaryAtIndex:(NSInteger)idx {
    if (!_engineBridge || ![_engineBridge isSequenceLoaded]) return;
    [_engineBridge deleteSongStructureBoundary:idx];
    [self reloadSongRegionsForRuler];
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didEditSongRegionId:(NSInteger)regionId name:(NSString *)name color:(NSColor *)color {
    if (!_engineBridge || ![_engineBridge isSequenceLoaded]) return;

    // Convert NSColor to 0xAARRGGBB
    NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    uint32_t a = (uint32_t)(rgb.alphaComponent * 255.0) & 0xFF;
    uint32_t r = (uint32_t)(rgb.redComponent * 255.0) & 0xFF;
    uint32_t g = (uint32_t)(rgb.greenComponent * 255.0) & 0xFF;
    uint32_t b = (uint32_t)(rgb.blueComponent * 255.0) & 0xFF;
    uint32_t argb = (a << 24) | (r << 16) | (g << 8) | b;

    [_engineBridge setSongStructureRegion:regionId name:name colorARGB:argb];
    [self reloadSongRegionsForRuler];
}

- (void)timelineRuler:(XLTimelineRulerView *)ruler didSelectSongRegionId:(NSInteger)regionId {
    _timelineRuler.selectedSongRegionId = regionId;
}

- (void)timelineRulerDidRequestClearSongStructure:(XLTimelineRulerView *)ruler {
    if (!_engineBridge || ![_engineBridge isSequenceLoaded]) return;
    [_engineBridge clearSongStructure];
    [self reloadSongRegionsForRuler];
}

/// Lightweight refresh after timing mark add/split/delete.
/// Only reloads timing data in grid + ruler without resetting zoom, audio, or playhead.
- (void)refreshTimingData {
    [self loadRealSequenceData];
    [_effectsGridView reloadData];
    [self reloadTimingMarksForRuler];
    [_rowHeadingsView reloadData];
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

- (void)reloadSongRegionsForRuler {
    if (!_engineBridge || ![_engineBridge isSequenceLoaded]) {
        [_timelineRuler setSongRegions:NULL count:0];
        return;
    }

    NSArray<NSDictionary *> *regions = [_engineBridge getSongStructureRegions];
    if (!regions || regions.count == 0) {
        [_timelineRuler setSongRegions:NULL count:0];
        return;
    }

    NSInteger count = (NSInteger)regions.count;
    XLSongRegion *cRegions = (XLSongRegion *)calloc(count, sizeof(XLSongRegion));

    for (NSInteger i = 0; i < count; i++) {
        NSDictionary *d = regions[i];
        cRegions[i].regionId = [d[@"regionId"] integerValue];
        cRegions[i].startTimeMS = [d[@"startTimeMS"] integerValue];
        cRegions[i].endTimeMS = [d[@"endTimeMS"] integerValue];

        uint32_t argb = (uint32_t)[d[@"colorARGB"] unsignedIntValue];
        CGFloat a = ((argb >> 24) & 0xFF) / 255.0;
        CGFloat r = ((argb >> 16) & 0xFF) / 255.0;
        CGFloat g = ((argb >> 8) & 0xFF) / 255.0;
        CGFloat b = (argb & 0xFF) / 255.0;
        cRegions[i].colorR = r;
        cRegions[i].colorG = g;
        cRegions[i].colorB = b;
        cRegions[i].colorA = a;

        NSString *name = d[@"name"];
        if (name) {
            strlcpy(cRegions[i].name, [name UTF8String], sizeof(cRegions[i].name));
        }
    }

    [_timelineRuler setSongRegions:cRegions count:count];
    free(cRegions);
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
        // Main row when collapsed: show only layer 0 (top layer)
        for (NSUInteger i = 0; i < _effectCount; i++) {
            if (_effectData[i].elementIndex == elementIndex &&
                _effectData[i].layerIndex == 0) {
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
        } else {
            // Main row (expanded or collapsed): show only layer 0
            if (_effectData[i].layerIndex != 0) continue;
        }

        if (matchIndex == effectIndex) {
            XLEffectEntry *eff = &_effectData[i];
            info.startTimeMS = eff->startTimeMS;
            info.endTimeMS = eff->endTimeMS;
            info.row = row;
            info.layer = eff->layerIndex;
            info.effectIndex = eff->effectTypeIndex;
            info.effectId = eff->effectIndex;
            info.colorARGB = eff->colorARGB;
            strncpy(info.effectTypeName, eff->effectTypeName, XL_EFFECT_TYPE_NAME_MAX - 1);
            info.effectTypeName[XL_EFFECT_TYPE_NAME_MAX - 1] = '\0';
            info.selected = eff->selected;
            info.locked = eff->locked;
            info.renderDisabled = eff->renderDisabled;
            info.fadeInMS = eff->fadeInMS;
            info.fadeOutMS = eff->fadeOutMS;
            info.isLinkedToSymbol = eff->isLinkedToSymbol;
            info.isTimingMark = (rowEntry->type == XLElementTypeTiming);
            info.timingTrackLayerCount = rowEntry->effectLayerCount;
            info.timingColorIndex = rowEntry->timingColorIndex;
            if (info.isTimingMark) {
                strncpy(info.label, eff->effectTypeName, XL_LABEL_MAX - 1);
                info.label[XL_LABEL_MAX - 1] = '\0';
            } else {
                info.label[0] = '\0';
            }
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

- (BOOL)effectsGrid:(XLEffectsGridView *)gridView shouldHandleKeyEvent:(NSEvent *)event {
    // Forward key events to the keyboard handler for custom key bindings
    // (e.g., 't' for zoom in, 'r' for zoom out, etc.)
    NSLog(@"XLSequencerViewController effectsGrid:shouldHandleKeyEvent: keyCode=%hu, chars='%@'",
          event.keyCode, event.charactersIgnoringModifiers);
    NSLog(@"  _keyboardHandler = %@", _keyboardHandler);

    BOOL handled = [_keyboardHandler handleKeyEvent:event inScope:XLKeyScopeSequence];
    NSLog(@"  keyboardHandler returned: %@", handled ? @"YES" : @"NO");
    return handled;
}

#pragma mark - XLWaveformViewDelegate (key events)

- (BOOL)waveformView:(XLWaveformView *)view shouldHandleKeyEvent:(NSEvent *)event {
    // Escape clears the loop region
    if (event.keyCode == 53 && view.hasLoopRegion) {
        [view clearLoopRegion];
        return YES;
    }
    return [_keyboardHandler handleKeyEvent:event inScope:XLKeyScopeSequence];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didSelectEffectAtRow:(NSInteger)row
          effectIndex:(NSInteger)effectIndex
{
    _cellRangeSelected = NO;

    // Use -1 as sentinel for "no effect" since 0 can be a valid effect ID
    NSInteger effectId = -1;
    NSString *effectType = nil;

    // effectIndex is a flat render index — use the grid view's stored effectId
    effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];

    if (_engineBridge && effectId >= 0) {
        NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
        effectType = effectInfo[@"effectType"];
    }

    // Post notification for effect properties panel (single selection)
    NSArray<NSNumber *> *selectedIds = (effectId >= 0) ? @[@(effectId)] : @[];
    NSArray<NSString *> *selectedTypes = effectType ? @[effectType] : @[];

    NSDictionary *userInfo = @{
        @"effectId": @(effectId),
        @"effectType": effectType ?: [NSNull null],
        @"selectedEffectIds": selectedIds,
        @"selectedEffectTypes": selectedTypes
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

    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return;

    XLRowEntry *rowEntry = &_rowData[row];

    // Only handle inline editing for timing track marks
    if (rowEntry->type != XLElementTypeTiming) return;

    // Get the effect info to find the effectId and current label
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0) return;

    // Get the current label from the bridge
    NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
    NSString *currentLabel = effectInfo[@"effectType"] ?: @"";

    // Get timing info for positioning the editor
    CGFloat startMS = [effectInfo[@"startTimeMS"] doubleValue];
    CGFloat endMS = [effectInfo[@"endTimeMS"] doubleValue];

    // Show inline text editor on the grid view
    [gridView beginEditingLabelAtRow:row
                             startMS:startMS
                               endMS:endMS
                        currentLabel:currentLabel
                   completionHandler:^(NSString *newLabel) {
        if (newLabel && ![newLabel isEqualToString:currentLabel]) {
            BOOL success = [self->_engineBridge setTimingMarkLabel:effectId label:newLabel];
            if (success) {
                NSLog(@"Updated timing mark %ld label to '%@'", (long)effectId, newLabel);
                [self reloadSequenceData];
                [gridView reloadData];
            }
        }
    }];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didClickAtTimeMS:(CGFloat)timeMS
                 row:(NSInteger)row
{
    _cellRangeSelected = NO;
    NSLog(@"Clicked at time %.0fms, row %ld", timeMS, (long)row);

    // Clicking on empty area clears selection (use -1 as "no effect" sentinel)
    NSDictionary *userInfo = @{
        @"effectId": @(-1),
        @"effectType": [NSNull null],
        @"selectedEffectIds": @[],
        @"selectedEffectTypes": @[]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:XLEffectSelectionDidChangeNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didResizeEffectAtRow:(NSInteger)row
           effectIndex:(NSInteger)effectIndex
         newStartTimeMS:(CGFloat)startTimeMS
           newEndTimeMS:(CGFloat)endTimeMS
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    [_engineBridge moveEffect:effectId startTimeMS:(NSInteger)startTimeMS endTimeMS:(NSInteger)endTimeMS];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didMoveEffectAtRow:(NSInteger)fromRow
          effectIndex:(NSInteger)effectIndex
            toTimeMS:(CGFloat)newStartTimeMS
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
    NSInteger origStart = [effectInfo[@"startTimeMS"] integerValue];
    NSInteger origEnd = [effectInfo[@"endTimeMS"] integerValue];
    NSInteger duration = origEnd - origStart;
    NSInteger newStart = (NSInteger)newStartTimeMS;
    NSInteger newEnd = newStart + duration;

    [_engineBridge moveEffect:effectId startTimeMS:newStart endTimeMS:newEnd];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didMoveEffectAtRow:(NSInteger)fromRow
          effectIndex:(NSInteger)effectIndex
                toRow:(NSInteger)toRow
            toTimeMS:(CGFloat)newStartTimeMS
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
    NSInteger origStart = [effectInfo[@"startTimeMS"] integerValue];
    NSInteger origEnd = [effectInfo[@"endTimeMS"] integerValue];
    NSInteger duration = origEnd - origStart;
    NSInteger newStart = (NSInteger)newStartTimeMS;
    NSInteger newEnd = newStart + duration;

    // For cross-row moves, we need to delete and recreate on the target row
    if (toRow >= 0 && toRow < (NSInteger)_rowCount && _rowData) {
        NSString *effectType = effectInfo[@"effectType"];
        // Get settings/palette as serialized strings (NOT the NSDictionary from effectInfo)
        NSString *settings = [_engineBridge getEffectSettings:effectId];
        NSString *palette = [_engineBridge getEffectPalette:effectId];
        NSString *modelName = [NSString stringWithUTF8String:_rowData[toRow].name];
        NSInteger layer = _rowData[toRow].isLayerRow ? _rowData[toRow].layerIndex : 0;

        [_engineBridge deleteEffect:effectId];
        NSInteger newEffectId = [_engineBridge createEffect:modelName
                                                      layer:layer
                                                 effectType:effectType
                                                startTimeMS:newStart
                                                  endTimeMS:newEnd];
        if (newEffectId >= 0 && settings.length > 0) {
            [_engineBridge setEffectSettings:newEffectId settings:settings];
        }
        if (newEffectId >= 0 && palette.length > 0) {
            [_engineBridge setEffectPalette:newEffectId palette:palette];
        }
        [self reloadSequenceData];
        [gridView reloadData];
    } else {
        [_engineBridge moveEffect:effectId startTimeMS:newStart endTimeMS:newEnd];
    }
}

// Batch move: same-row, by engine effectId. No reload — caller handles.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didBatchMoveEffectId:(NSInteger)effectId
               toTimeMS:(CGFloat)newStartTimeMS
{
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
    if (!effectInfo) return;

    NSInteger origStart = [effectInfo[@"startTimeMS"] integerValue];
    NSInteger origEnd = [effectInfo[@"endTimeMS"] integerValue];
    NSInteger duration = origEnd - origStart;
    NSInteger newStart = (NSInteger)newStartTimeMS;
    NSInteger newEnd = newStart + duration;

    [_engineBridge moveEffect:effectId startTimeMS:newStart endTimeMS:newEnd];
}

// Batch move: cross-row, by engine effectId. No reload — caller handles.
- (void)effectsGrid:(XLEffectsGridView *)gridView
    didBatchMoveEffectId:(NSInteger)effectId
               fromRow:(NSInteger)fromRow
                 toRow:(NSInteger)toRow
             toTimeMS:(CGFloat)newStartTimeMS
{
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
    if (!effectInfo) return;

    NSInteger origStart = [effectInfo[@"startTimeMS"] integerValue];
    NSInteger origEnd = [effectInfo[@"endTimeMS"] integerValue];
    NSInteger duration = origEnd - origStart;
    NSInteger newStart = (NSInteger)newStartTimeMS;
    NSInteger newEnd = newStart + duration;

    if (toRow >= 0 && toRow < (NSInteger)_rowCount && _rowData) {
        NSString *effectType = effectInfo[@"effectType"];
        NSString *settings = [_engineBridge getEffectSettings:effectId];
        NSString *palette = [_engineBridge getEffectPalette:effectId];
        NSString *modelName = [NSString stringWithUTF8String:_rowData[toRow].name];
        NSInteger layer = _rowData[toRow].isLayerRow ? _rowData[toRow].layerIndex : 0;

        [_engineBridge deleteEffect:effectId];
        NSInteger newEffectId = [_engineBridge createEffect:modelName
                                                      layer:layer
                                                 effectType:effectType
                                                startTimeMS:newStart
                                                  endTimeMS:newEnd];
        if (newEffectId >= 0 && settings.length > 0) {
            [_engineBridge setEffectSettings:newEffectId settings:settings];
        }
        if (newEffectId >= 0 && palette.length > 0) {
            [_engineBridge setEffectPalette:newEffectId palette:palette];
        }
        // NO reload here — caller handles after all batch moves complete
    } else {
        [_engineBridge moveEffect:effectId startTimeMS:newStart endTimeMS:newEnd];
    }
}

- (void)effectsGridDidCompleteBatchMoves:(XLEffectsGridView *)gridView {
    [self reloadSequenceData];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didChangeSelection:(NSIndexSet *)selectedIndices
{
    if (selectedIndices.count == 0) {
        // No selection
        NSDictionary *userInfo = @{
            @"effectId": @(-1),
            @"effectType": [NSNull null],
            @"selectedEffectIds": @[],
            @"selectedEffectTypes": @[]
        };
        [[NSNotificationCenter defaultCenter] postNotificationName:XLEffectSelectionDidChangeNotification
                                                            object:self
                                                          userInfo:userInfo];
        return;
    }

    // Build arrays of effect IDs and types for all selected effects
    NSMutableArray<NSNumber *> *effectIds = [NSMutableArray arrayWithCapacity:selectedIndices.count];
    NSMutableArray<NSString *> *effectTypes = [NSMutableArray arrayWithCapacity:selectedIndices.count];
    __block NSInteger primaryEffectId = -1;
    __block NSString *primaryEffectType = nil;

    [selectedIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        // Use the grid view's stored effectId for this render index
        NSInteger effectId = [gridView effectIdAtRenderIndex:idx];
        NSString *effectType = nil;

        if (self->_engineBridge && effectId >= 0) {
            NSDictionary *effectInfo = [self->_engineBridge getEffect:effectId];
            effectType = effectInfo[@"effectType"];
        }

        // First effect becomes primary
        if (primaryEffectId < 0) {
            primaryEffectId = effectId;
            primaryEffectType = effectType;
        }

        [effectIds addObject:@(effectId)];
        [effectTypes addObject:effectType ?: @""];
    }];

    NSDictionary *userInfo = @{
        @"effectId": @(primaryEffectId),
        @"effectType": primaryEffectType ?: [NSNull null],
        @"selectedEffectIds": effectIds,
        @"selectedEffectTypes": effectTypes
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:XLEffectSelectionDidChangeNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestDeleteEffects:(NSIndexSet *)effectIndices
{
    if (!_engineBridge || effectIndices.count == 0) return;

    // Collect all effect IDs to delete
    NSMutableArray<NSNumber *> *effectIdsToDelete = [NSMutableArray arrayWithCapacity:effectIndices.count];

    [effectIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger effectId = [gridView effectIdAtRenderIndex:idx];
        if (effectId >= 0) {
            [effectIdsToDelete addObject:@(effectId)];
        }
    }];

    NSLog(@"Delete requested for %lu effects (renderIndices=%@, effectIds=%@)",
          (unsigned long)effectIndices.count, effectIndices, effectIdsToDelete);

    // Delete each effect via engine bridge
    for (NSNumber *effectIdNum in effectIdsToDelete) {
        NSInteger effectId = effectIdNum.integerValue;
        if (effectId >= 0) {
            [_engineBridge deleteEffect:effectId];
        }
    }

    // Lightweight refresh — don't reset playback or zoom
    [self refreshTimingData];

    // Clear selection notification
    NSDictionary *userInfo = @{
        @"effectId": @(-1),
        @"effectType": [NSNull null],
        @"selectedEffectIds": @[],
        @"selectedEffectTypes": @[]
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:XLEffectSelectionDidChangeNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didSelectRangeFromRow:(NSInteger)startRow
                    toRow:(NSInteger)endRow
              fromTimeMS:(CGFloat)startTimeMS
                toTimeMS:(CGFloat)endTimeMS
{
    _cellRangeSelected = YES;
    _rangeStartRow = startRow;
    _rangeEndRow = endRow;
    _rangeStartTimeMS = startTimeMS;
    _rangeEndTimeMS = endTimeMS;
    NSLog(@"XLSequencerViewController: Range selected rows %ld-%ld, time %ld-%ld ms",
          (long)startRow, (long)endRow, (long)(NSInteger)startTimeMS, (long)(NSInteger)endTimeMS);
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
        [_playbackController renderCurrentFrame];
    } else {
        NSLog(@"XLSequencerViewController: Failed to create effect");
    }
}

#pragma mark - Directional Effect Duplication

- (BOOL)hasConflictOnModel:(NSString *)modelName
                     layer:(NSInteger)layer
                   startMS:(NSInteger)startMS
                     endMS:(NSInteger)endMS
                excludeIds:(NSSet<NSNumber *> *)excludeIds
{
    NSArray<NSDictionary *> *existing = [_engineBridge getEffectsForLayer:modelName layer:layer];
    for (NSDictionary *eff in existing) {
        NSInteger eId = [eff[@"id"] integerValue];
        if ([excludeIds containsObject:@(eId)]) continue;
        NSInteger eStart = [eff[@"startTimeMS"] integerValue];
        NSInteger eEnd = [eff[@"endTimeMS"] integerValue];
        if (startMS < eEnd && endMS > eStart) {
            return YES;
        }
    }
    return NO;
}

- (NSInteger)gridRowForModelName:(NSString *)modelName {
    for (NSUInteger r = 0; r < _rowCount; r++) {
        if (_rowData[r].isLayerRow) continue;
        if (_rowData[r].type == XLElementTypeTiming) continue;
        NSString *rowName = [NSString stringWithUTF8String:_rowData[r].name];
        if ([rowName isEqualToString:modelName]) {
            return (NSInteger)r;
        }
    }
    return -1;
}

- (NSInteger)findTargetRow:(NSInteger)startRow direction:(NSInteger)direction steps:(NSInteger)steps {
    NSInteger found = 0;
    if (direction == 3) {
        for (NSInteger r = startRow - 1; r >= 0; r--) {
            if (_rowData[r].type != XLElementTypeTiming && !_rowData[r].isLayerRow) {
                found++;
                if (found >= steps) return r;
            }
        }
    } else {
        for (NSUInteger r = (NSUInteger)(startRow + 1); r < _rowCount; r++) {
            if (_rowData[r].type != XLElementTypeTiming && !_rowData[r].isLayerRow) {
                found++;
                if (found >= steps) return (NSInteger)r;
            }
        }
    }
    return -1;
}

- (void)duplicateSelectedEffects:(NSIndexSet *)selected direction:(NSInteger)direction {
    if (!_engineBridge || selected.count == 0) return;

    NSMutableArray<NSDictionary *> *effectInfos = [NSMutableArray arrayWithCapacity:selected.count];
    NSMutableSet<NSNumber *> *sourceIds = [NSMutableSet setWithCapacity:selected.count];

    [selected enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger effectId = [self->_effectsGridView effectIdAtRenderIndex:idx];
        if (effectId < 0) return;

        NSDictionary *info = [self->_engineBridge getEffect:effectId];
        if (!info) return;

        NSInteger gridRow = [self->_effectsGridView rowForRenderIndex:idx];

        NSMutableDictionary *entry = [info mutableCopy];
        entry[@"_sourceId"] = @(effectId);
        entry[@"_gridRow"] = @(gridRow);
        [effectInfos addObject:entry];
        [sourceIds addObject:@(effectId)];
    }];

    if (effectInfos.count == 0) return;

    NSMutableDictionary<NSNumber *, NSMutableArray<NSDictionary *> *> *rowGroups = [NSMutableDictionary new];
    for (NSDictionary *info in effectInfos) {
        NSNumber *rowKey = info[@"_gridRow"];
        if (!rowGroups[rowKey]) {
            rowGroups[rowKey] = [NSMutableArray new];
        }
        [rowGroups[rowKey] addObject:info];
    }

    for (NSNumber *rowKey in rowGroups) {
        [rowGroups[rowKey] sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [@([a[@"startTimeMS"] integerValue]) compare:@([b[@"startTimeMS"] integerValue])];
        }];
    }

    [_undoController beginUndoGroupingWithActionName:@"Duplicate Effects"];
    BOOL anyCreated = NO;

    if (direction == 1 || direction == 2) {
        NSInteger globalLeftmost = NSIntegerMax;
        NSInteger globalRightmost = NSIntegerMin;
        for (NSDictionary *info in effectInfos) {
            NSInteger s = [info[@"startTimeMS"] integerValue];
            NSInteger e = [info[@"endTimeMS"] integerValue];
            if (s < globalLeftmost) globalLeftmost = s;
            if (e > globalRightmost) globalRightmost = e;
        }
        NSInteger rangeWidth = globalRightmost - globalLeftmost;

        for (NSDictionary *info in effectInfos) {
            NSString *modelName = info[@"modelName"];
            NSString *effectType = info[@"effectType"];
            NSInteger layer = [info[@"layerIndex"] integerValue];
            NSInteger startMS = [info[@"startTimeMS"] integerValue];
            NSInteger endMS = [info[@"endTimeMS"] integerValue];
            NSInteger durationMS = endMS - startMS;
            NSInteger sourceId = [info[@"_sourceId"] integerValue];

            NSInteger newStartMS, newEndMS;
            if (direction == 1) {
                NSInteger offset = startMS - globalLeftmost;
                newStartMS = globalRightmost + offset;
                newEndMS = newStartMS + durationMS;
            } else {
                NSInteger offset = startMS - globalLeftmost;
                newStartMS = globalLeftmost - rangeWidth + offset;
                newEndMS = newStartMS + durationMS;
            }

            if (newStartMS < 0) {
                NSInteger shift = -newStartMS;
                newStartMS += shift;
                newEndMS += shift;
            }
            if (newEndMS > (NSInteger)_sequenceDurationMS) {
                continue;
            }

            if ([self hasConflictOnModel:modelName layer:layer
                                 startMS:newStartMS endMS:newEndMS
                              excludeIds:sourceIds]) {
                NSLog(@"Duplicate %@: conflict on %@ layer %ld at [%ld-%ld], skipping",
                      direction == 1 ? @"Right" : @"Left",
                      modelName, (long)layer, (long)newStartMS, (long)newEndMS);
                continue;
            }

            NSInteger newId = [_engineBridge createEffect:modelName
                                                    layer:layer
                                               effectType:effectType
                                              startTimeMS:newStartMS
                                                endTimeMS:newEndMS];
            if (newId >= 0) {
                NSString *settings = [_engineBridge getEffectSettings:sourceId];
                NSString *palette = [_engineBridge getEffectPalette:sourceId];
                if (settings) [_engineBridge setEffectSettings:newId settings:settings];
                if (palette) [_engineBridge setEffectPalette:newId palette:palette];
                anyCreated = YES;
            }
        }

        if (anyCreated && _effectsGridView.hasCellSelection) {
            NSInteger cellRow = _effectsGridView.cellSelectionRow;
            CGFloat cellStart = _effectsGridView.cellSelectionStartMS;
            CGFloat cellEnd = _effectsGridView.cellSelectionEndMS;
            CGFloat cellWidth = cellEnd - cellStart;
            if (direction == 1) {
                [_effectsGridView setCellSelectionRow:cellRow
                                             startMS:cellStart + cellWidth
                                               endMS:cellEnd + cellWidth];
            } else {
                [_effectsGridView setCellSelectionRow:cellRow
                                             startMS:cellStart - cellWidth
                                               endMS:cellEnd - cellWidth];
            }
        }

    } else {
        NSArray<NSNumber *> *sortedRows = [[rowGroups allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSInteger minRow = sortedRows.firstObject.integerValue;
        NSInteger maxRow = sortedRows.lastObject.integerValue;

        NSInteger distinctRowCount = (NSInteger)sortedRows.count;
        if (distinctRowCount < 1) distinctRowCount = 1;

        BOOL allTargetsValid = YES;
        NSMutableDictionary<NSNumber *, NSNumber *> *rowMapping = [NSMutableDictionary new];

        for (NSNumber *srcRowNum in sortedRows) {
            NSInteger srcRow = srcRowNum.integerValue;
            NSInteger rowOffsetFromEdge = srcRow - minRow;

            NSInteger targetRow;
            if (direction == 3) {
                targetRow = [self findTargetRow:minRow direction:3 steps:(distinctRowCount - rowOffsetFromEdge)];
            } else {
                targetRow = [self findTargetRow:maxRow direction:4 steps:(rowOffsetFromEdge + 1)];
            }

            if (targetRow < 0) {
                allTargetsValid = NO;
                break;
            }
            rowMapping[srcRowNum] = @(targetRow);
        }

        if (!allTargetsValid) {
            NSLog(@"Duplicate %@: not enough rows available", direction == 3 ? @"Up" : @"Down");
            [_undoController endUndoGrouping];
            return;
        }

        for (NSNumber *srcRowNum in sortedRows) {
            NSInteger targetRow = [rowMapping[srcRowNum] integerValue];
            NSString *targetModel = [NSString stringWithUTF8String:_rowData[targetRow].name];

            for (NSDictionary *info in rowGroups[srcRowNum]) {
                NSString *effectType = info[@"effectType"];
                NSInteger layer = [info[@"layerIndex"] integerValue];
                NSInteger startMS = [info[@"startTimeMS"] integerValue];
                NSInteger endMS = [info[@"endTimeMS"] integerValue];
                NSInteger sourceId = [info[@"_sourceId"] integerValue];

                if ([self hasConflictOnModel:targetModel layer:layer
                                     startMS:startMS endMS:endMS
                                  excludeIds:sourceIds]) {
                    NSLog(@"Duplicate %@: conflict on %@ layer %ld at [%ld-%ld], skipping",
                          direction == 3 ? @"Up" : @"Down",
                          targetModel, (long)layer, (long)startMS, (long)endMS);
                    continue;
                }

                NSInteger newId = [_engineBridge createEffect:targetModel
                                                        layer:layer
                                                   effectType:effectType
                                                  startTimeMS:startMS
                                                    endTimeMS:endMS];
                if (newId >= 0) {
                    NSString *settings = [_engineBridge getEffectSettings:sourceId];
                    NSString *palette = [_engineBridge getEffectPalette:sourceId];
                    if (settings) [_engineBridge setEffectSettings:newId settings:settings];
                    if (palette) [_engineBridge setEffectPalette:newId palette:palette];
                    anyCreated = YES;
                }
            }
        }
    }

    [_undoController endUndoGrouping];

    if (anyCreated) {
        [self reloadSequenceData];
        [_playbackController renderCurrentFrame];
        [_effectsGridView reloadData];
    }
}

#pragma mark - XLEffectsGridDelegate (Effect Operations)

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestSplitEffectAtIndex:(NSInteger)effectIndex
                        atTimeMS:(CGFloat)timeMS
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
    if (!effectInfo) return;

    NSInteger startMS = [effectInfo[@"startTimeMS"] integerValue];
    NSInteger endMS = [effectInfo[@"endTimeMS"] integerValue];
    NSInteger splitMS = (NSInteger)timeMS;

    if (splitMS <= startMS || splitMS >= endMS) return;

    NSString *modelName = effectInfo[@"modelName"];
    NSString *effectType = effectInfo[@"effectType"];
    NSInteger layer = [effectInfo[@"layerIndex"] integerValue];

    // Resize original to end at split point
    [_engineBridge moveEffect:effectId startTimeMS:startMS endTimeMS:splitMS];

    // Create new effect from split point to original end
    // TODO: Copy effect settings/palette from original to the new effect
    [_engineBridge createEffect:modelName
                          layer:layer
                     effectType:effectType
                    startTimeMS:splitMS
                      endTimeMS:endMS];

    [self reloadSequenceData];
    [_playbackController renderCurrentFrame];
    [gridView reloadData];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestDuplicateEffectAtIndex:(NSInteger)effectIndex
                          direction:(NSInteger)direction
{
    if (!_engineBridge) return;

    // Build an index set from the context menu effect (or current multi-selection)
    NSIndexSet *selected = gridView.selectedEffectIndices;
    if (selected.count == 0 && effectIndex >= 0) {
        selected = [NSIndexSet indexSetWithIndex:(NSUInteger)effectIndex];
    }
    if (selected.count == 0) return;

    // Direction 0 (basic duplicate) maps to right
    NSInteger dir = (direction == 0) ? 1 : direction;
    [self duplicateSelectedEffects:selected direction:dir];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestCreateTimingFromEffects:(NSIndexSet *)effectIndices
{
    if (!_engineBridge || effectIndices.count == 0) return;

    NSString *activeTrack = [_engineBridge getActiveTimingTrackName];
    if (!activeTrack) {
        NSLog(@"Create Timing: no active timing track");
        return;
    }

    [effectIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger effectId = [gridView effectIdAtRenderIndex:idx];
        if (effectId < 0) return;

        NSDictionary *effectInfo = [self->_engineBridge getEffect:effectId];
        if (!effectInfo) return;

        NSInteger startMS = [effectInfo[@"startTimeMS"] integerValue];
        NSInteger endMS = [effectInfo[@"endTimeMS"] integerValue];

        [self->_engineBridge createTimingMark:activeTrack
                                       layer:0
                                 startTimeMS:startMS
                                   endTimeMS:endMS
                                       label:nil];
    }];

    [self reloadSequenceData];
    [gridView reloadData];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestSetLocked:(BOOL)locked
             forEffects:(NSIndexSet *)effectIndices
{
    if (!_engineBridge || effectIndices.count == 0) return;

    [effectIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger effectId = [gridView effectIdAtRenderIndex:idx];
        if (effectId < 0) return;
        [self->_engineBridge setEffectLocked:effectId locked:locked];
    }];

    [self reloadSequenceData];
    [gridView reloadData];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestSetRenderDisabled:(BOOL)disabled
                     forEffects:(NSIndexSet *)effectIndices
{
    if (!_engineBridge || effectIndices.count == 0) return;

    [effectIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger effectId = [gridView effectIdAtRenderIndex:idx];
        if (effectId < 0) return;
        [self->_engineBridge setEffectRenderDisabled:effectId disabled:disabled];
    }];

    [self reloadSequenceData];
    [gridView reloadData];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestEditDescriptionForEffectAtIndex:(NSInteger)effectIndex
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    NSString *currentDesc = [_engineBridge getEffectParameter:effectId key:@"Description"] ?: @"";

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Effect Description";
    alert.informativeText = @"Enter a description for this effect:";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    input.stringValue = currentDesc;
    alert.accessoryView = input;

    [alert beginSheetModalForWindow:gridView.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString *newDesc = input.stringValue;
            [self->_engineBridge setEffectParameter:effectId key:@"Description" value:newDesc];
            [self reloadSequenceData];
            [gridView reloadData];
        }
    }];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestResetEffectAtIndex:(NSInteger)effectIndex
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    [_engineBridge resetEffectToDefaults:effectId];

    [self reloadSequenceData];
    [gridView reloadData];
}

- (void)effectsGridDidRequestEffectPresets:(XLEffectsGridView *)gridView
{
    if (!_presetsWindowController) {
        _presetsWindowController = [[XLEffectPresetsWindowController alloc]
            initWithEngineBridge:_engineBridge];
    }

    // Set the current effect so Save/Load buttons know what to operate on
    NSInteger selectedIdx = gridView.selectedEffectID;
    if (selectedIdx >= 0) {
        NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)selectedIdx];
        [_presetsWindowController setCurrentEffectId:effectId];
    }

    NSWindow *presetsWindow = _presetsWindowController.window;
    if (presetsWindow.isVisible) {
        [presetsWindow makeKeyAndOrderFront:nil];
    } else {
        [_presetsWindowController reloadPresets];
        [presetsWindow makeKeyAndOrderFront:nil];
    }
}

- (void)effectsGridDidRequestCreateRandomEffects:(XLEffectsGridView *)gridView
{
    // TODO: Implement random effects generation for the selected range.
    NSLog(@"Create Random Effects requested (not yet implemented)");
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestEditTimingForEffectAtIndex:(NSInteger)effectIndex
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
    if (!effectInfo) return;

    NSInteger currentStartMS = [effectInfo[@"startTimeMS"] integerValue];
    NSInteger currentEndMS = [effectInfo[@"endTimeMS"] integerValue];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Effect Timing";
    alert.informativeText = @"Edit start and end time (milliseconds):";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 60)];

    NSTextField *startLabel = [NSTextField labelWithString:@"Start (ms):"];
    startLabel.frame = NSMakeRect(0, 32, 80, 20);
    [accessoryView addSubview:startLabel];

    NSTextField *startField = [[NSTextField alloc] initWithFrame:NSMakeRect(85, 32, 200, 24)];
    startField.stringValue = [NSString stringWithFormat:@"%ld", (long)currentStartMS];
    [accessoryView addSubview:startField];

    NSTextField *endLabel = [NSTextField labelWithString:@"End (ms):"];
    endLabel.frame = NSMakeRect(0, 2, 80, 20);
    [accessoryView addSubview:endLabel];

    NSTextField *endField = [[NSTextField alloc] initWithFrame:NSMakeRect(85, 2, 200, 24)];
    endField.stringValue = [NSString stringWithFormat:@"%ld", (long)currentEndMS];
    [accessoryView addSubview:endField];

    alert.accessoryView = accessoryView;

    [alert beginSheetModalForWindow:gridView.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSInteger newStartMS = startField.integerValue;
            NSInteger newEndMS = endField.integerValue;
            if (newEndMS > newStartMS && newStartMS >= 0) {
                [self->_engineBridge moveEffect:effectId startTimeMS:newStartMS endTimeMS:newEndMS];
                [self reloadSequenceData];
                [self->_playbackController renderCurrentFrame];
                [gridView reloadData];
            }
        }
    }];
}

#pragma mark - XLEffectsGridDelegate (Smart Tool)

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestSetSmartToolParameter:(NSString *)key
                              value:(NSString *)value
                       forEffectId:(NSInteger)effectId
{
    if (!self.engineBridge || effectId < 0 || !key || !value) return;
    [self.engineBridge setEffectParameter:effectId key:key value:value];
}

- (NSString *)effectsGrid:(XLEffectsGridView *)gridView
    smartToolParameterValue:(NSString *)key
               forEffectId:(NSInteger)effectId
{
    if (!self.engineBridge || effectId < 0 || !key) return nil;
    return [self.engineBridge getEffectParameter:effectId key:key];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didCompleteSmartToolDragForEffectIds:(NSArray<NSNumber *> *)effectIds
                               parameter:(NSString *)parameterKey
{
    // Trigger render and reload sequence data so changes are reflected
    [_playbackController renderCurrentFrame];
    [self reloadSequenceData];
    [gridView reloadData];
}

#pragma mark - XLEffectsGridDelegate (Timing Track Operations)

/// Round a time value to the nearest frame boundary
- (NSInteger)roundToFrameBoundary:(double)timeMS {
    if (_frameRate <= 0) return (NSInteger)timeMS;
    double frameDuration = 1000.0 / (double)_frameRate;
    return (NSInteger)(round(timeMS / frameDuration) * frameDuration);
}

/// Get the active timing track name (convenience)
- (NSString *)activeTimingTrackForOperation {
    return [_engineBridge getActiveTimingTrackName];
}

/// Perform phrase breakdown: split a phrase timing mark into word timing marks on layer 1
- (void)breakdownPhraseWithId:(NSInteger)effectId trackName:(NSString *)trackName {
    NSDictionary *markInfo = [_engineBridge getTimingMark:effectId];
    if (!markInfo) return;

    NSString *phrase = markInfo[@"label"];
    NSInteger startTime = [markInfo[@"startTimeMS"] integerValue];
    NSInteger endTime = [markInfo[@"endTimeMS"] integerValue];

    if (!phrase || phrase.length == 0 || endTime <= startTime) return;

    // Tokenize phrase into words (same delimiters as legacy code)
    NSCharacterSet *delimiters = [NSCharacterSet characterSetWithCharactersInString:@" \t:;,.-_!?{}[]()<>+=|"];
    NSArray<NSString *> *rawWords = [phrase componentsSeparatedByCharactersInSet:delimiters];
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *w in rawWords) {
        if (w.length > 0) [words addObject:w];
    }

    NSInteger numWords = (NSInteger)words.count;
    if (numWords == 0) return;

    // Clear existing word marks in this time range on layer 1
    NSArray<NSDictionary *> *existingLayer1 = [_engineBridge getTimingMarks:trackName layer:1];
    for (NSDictionary *mark in existingLayer1) {
        NSInteger mStart = [mark[@"startTimeMS"] integerValue];
        NSInteger mEnd = [mark[@"endTimeMS"] integerValue];
        if (mStart >= startTime && mEnd <= endTime) {
            [_engineBridge deleteTimingMark:[mark[@"id"] integerValue]];
        }
    }

    // Create word timing marks evenly distributed
    double intervalMS = (double)(endTime - startTime) / (double)numWords;
    NSInteger wordStartTime = startTime;
    for (NSInteger i = 0; i < numWords; i++) {
        NSInteger wordEndTime = [self roundToFrameBoundary:startTime + intervalMS * (i + 1)];
        if (i == numWords - 1 || wordEndTime > endTime) {
            wordEndTime = endTime;
        }
        [_engineBridge createTimingMark:trackName layer:1
                            startTimeMS:wordStartTime endTimeMS:wordEndTime
                                  label:words[(NSUInteger)i]];
        wordStartTime = wordEndTime;
    }
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestBreakdownPhraseAtIndex:(NSInteger)effectIndex
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *markInfo = [_engineBridge getTimingMark:effectId];
    if (!markInfo) return;
    NSString *trackName = markInfo[@"trackName"];
    if (!trackName) return;

    [self breakdownPhraseWithId:effectId trackName:trackName];
    [self reloadSequenceData];
    [gridView reloadData];
    NSLog(@"Breakdown Phrase completed for effect %ld", (long)effectId);
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestBreakdownSelectedPhrases:(NSIndexSet *)effectIndices
{
    if (!_engineBridge || effectIndices.count == 0) return;

    __block NSString *trackName = nil;

    // Collect all effect IDs and determine track
    NSMutableArray<NSNumber *> *effectIds = [NSMutableArray array];
    [effectIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger eid = [gridView effectIdAtRenderIndex:idx];
        if (eid >= 0) {
            [effectIds addObject:@(eid)];
            if (!trackName) {
                NSDictionary *info = [self->_engineBridge getTimingMark:eid];
                if (info[@"trackName"]) trackName = info[@"trackName"];
            }
        }
    }];

    if (!trackName) return;

    for (NSNumber *eid in effectIds) {
        [self breakdownPhraseWithId:eid.integerValue trackName:trackName];
    }

    [self reloadSequenceData];
    [gridView reloadData];
    NSLog(@"Breakdown Selected Phrases completed (%lu marks)", (unsigned long)effectIds.count);
}

/// Perform word breakdown: split a word timing mark into phoneme timing marks on layer 2.
/// Uses a simple phoneme mapping since we don't have the wxWidgets dictionary available directly.
/// The engine bridge can access the PhonemeDictionary through the C++ engine.
- (void)breakdownWordWithId:(NSInteger)effectId trackName:(NSString *)trackName {
    NSDictionary *markInfo = [_engineBridge getTimingMark:effectId];
    if (!markInfo) return;

    NSString *word = markInfo[@"label"];
    NSInteger startTime = [markInfo[@"startTimeMS"] integerValue];
    NSInteger endTime = [markInfo[@"endTimeMS"] integerValue];

    if (!word || word.length == 0 || endTime <= startTime) return;

    // Get phonemes for this word from the engine bridge
    NSArray<NSString *> *phonemes = [_engineBridge getPhonemesForWord:word];

    if (!phonemes || phonemes.count == 0) {
        // Fallback: create a single "rest" phoneme spanning the full word
        phonemes = @[@"rest"];
    }

    // Clear existing phoneme marks in this time range on layer 2
    NSArray<NSDictionary *> *existingLayer2 = [_engineBridge getTimingMarks:trackName layer:2];
    for (NSDictionary *mark in existingLayer2) {
        NSInteger mStart = [mark[@"startTimeMS"] integerValue];
        NSInteger mEnd = [mark[@"endTimeMS"] integerValue];
        if (mStart >= startTime && mEnd <= endTime) {
            [_engineBridge deleteTimingMark:[mark[@"id"] integerValue]];
        }
    }

    // Calculate timing using the same algorithm as legacy code:
    // MBP and "etc" phonemes get shorter duration, others get longer
    NSInteger countShort = 0;
    for (NSString *p in phonemes) {
        if ([p isEqualToString:@"etc"] || [p isEqualToString:@"MBP"]) countShort++;
    }

    double defaultInterval = (double)(endTime - startTime) / (double)phonemes.count;
    double shortInterval = 50.0;
    if (defaultInterval < 50.0) {
        shortInterval = (_frameRate > 0) ? (1000.0 / _frameRate) : 50.0;
    }

    double adjustedInterval = defaultInterval;
    if ((NSInteger)phonemes.count > 1) {
        NSInteger longCount = (NSInteger)phonemes.count - countShort;
        if (longCount > 0) {
            adjustedInterval = ((double)(endTime - startTime) - countShort * shortInterval) / (double)longCount;
        }
    } else {
        shortInterval = defaultInterval;
    }

    NSInteger phonemeStartTime = startTime;
    NSInteger shorts = 0;
    NSInteger longs = 0;
    for (NSString *phoneme in phonemes) {
        if ([phoneme isEqualToString:@"etc"] || [phoneme isEqualToString:@"MBP"]) {
            shorts++;
        } else {
            longs++;
        }
        NSInteger phonemeEndTime = [self roundToFrameBoundary:startTime + longs * adjustedInterval + shorts * shortInterval];
        if (phonemeEndTime > endTime) phonemeEndTime = endTime;
        if (phonemeEndTime > phonemeStartTime) {
            [_engineBridge createTimingMark:trackName layer:2
                                startTimeMS:phonemeStartTime endTimeMS:phonemeEndTime
                                      label:phoneme];
        }
        phonemeStartTime = phonemeEndTime;
    }
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestBreakdownWordAtIndex:(NSInteger)effectIndex
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *markInfo = [_engineBridge getTimingMark:effectId];
    if (!markInfo) return;
    NSString *trackName = markInfo[@"trackName"];
    if (!trackName) return;

    [self breakdownWordWithId:effectId trackName:trackName];
    [self reloadSequenceData];
    [gridView reloadData];
    NSLog(@"Breakdown Word completed for effect %ld", (long)effectId);
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestBreakdownSelectedWords:(NSIndexSet *)effectIndices
{
    if (!_engineBridge || effectIndices.count == 0) return;

    __block NSString *trackName = nil;

    NSMutableArray<NSNumber *> *effectIds = [NSMutableArray array];
    [effectIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger eid = [gridView effectIdAtRenderIndex:idx];
        if (eid >= 0) {
            [effectIds addObject:@(eid)];
            if (!trackName) {
                NSDictionary *info = [self->_engineBridge getTimingMark:eid];
                if (info[@"trackName"]) trackName = info[@"trackName"];
            }
        }
    }];

    if (!trackName) return;

    for (NSNumber *eid in effectIds) {
        [self breakdownWordWithId:eid.integerValue trackName:trackName];
    }

    [self reloadSequenceData];
    [gridView reloadData];
    NSLog(@"Breakdown Selected Words completed (%lu marks)", (unsigned long)effectIds.count);
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestDivideTimingsAtIndex:(NSInteger)effectIndex
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *markInfo = [_engineBridge getTimingMark:effectId];
    if (!markInfo) return;

    NSString *trackName = markInfo[@"trackName"];
    NSInteger layer = [markInfo[@"layer"] integerValue];
    NSInteger startTime = [markInfo[@"startTimeMS"] integerValue];
    NSInteger endTime = [markInfo[@"endTimeMS"] integerValue];
    NSString *label = markInfo[@"label"];

    if (endTime <= startTime || !trackName) return;

    NSInteger baseTiming = (_frameRate > 0) ? (1000 / _frameRate) : 50;
    if (endTime - startTime <= baseTiming) return;

    // Show divide-by dialog
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Divide Timings";
    alert.informativeText = @"Divide timing mark into how many parts?";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *inputField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    inputField.stringValue = @"2";
    alert.accessoryView = inputField;

    [alert beginSheetModalForWindow:gridView.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) return;
        NSInteger divideBy = inputField.integerValue;
        if (divideBy < 2 || divideBy > 100) return;

        double splitDuration = (double)(endTime - startTime) / (double)divideBy;

        // Resize original mark to first subdivision
        NSInteger firstEnd = [self roundToFrameBoundary:(double)startTime + splitDuration];
        [self->_engineBridge moveTimingMark:effectId startTimeMS:startTime endTimeMS:firstEnd];

        // Create additional subdivisions
        for (NSInteger j = 1; j < divideBy; j++) {
            NSInteger newStart = [self roundToFrameBoundary:(double)startTime + splitDuration * (double)j];
            NSInteger newEnd;
            if (j == divideBy - 1) {
                newEnd = endTime;
            } else {
                newEnd = [self roundToFrameBoundary:(double)startTime + splitDuration * (double)(j + 1)];
            }
            if (newStart < newEnd) {
                [self->_engineBridge createTimingMark:trackName layer:layer
                                         startTimeMS:newStart endTimeMS:newEnd
                                               label:@""];
            }
        }

        [self reloadSequenceData];
        [gridView reloadData];
        NSLog(@"Divide Timings completed: effect %ld divided by %ld", (long)effectId, (long)divideBy);
    }];
}

- (void)effectsGridDidRequestAutoLabelTimings:(XLEffectsGridView *)gridView
{
    NSString *trackName = [self activeTimingTrackForOperation];
    if (!trackName) return;

    // Show auto-label configuration dialog
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Auto Label Timings";
    alert.informativeText = @"Set numeric labels for timing marks:";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 95)];

    NSTextField *startLabel = [NSTextField labelWithString:@"Start number:"];
    startLabel.frame = NSMakeRect(0, 67, 100, 20);
    [accessoryView addSubview:startLabel];
    NSTextField *startField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, 67, 80, 24)];
    startField.stringValue = @"1";
    [accessoryView addSubview:startField];

    NSTextField *endLabel = [NSTextField labelWithString:@"End number:"];
    endLabel.frame = NSMakeRect(0, 37, 100, 20);
    [accessoryView addSubview:endLabel];
    NSTextField *endField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, 37, 80, 24)];
    endField.stringValue = @"100";
    [accessoryView addSubview:endField];

    NSButton *overwriteCheck = [NSButton checkboxWithTitle:@"Overwrite existing labels"
                                                    target:nil action:nil];
    overwriteCheck.frame = NSMakeRect(0, 5, 280, 24);
    overwriteCheck.state = NSControlStateValueOff;
    [accessoryView addSubview:overwriteCheck];

    alert.accessoryView = accessoryView;

    [alert beginSheetModalForWindow:gridView.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) return;

        NSInteger startNum = startField.integerValue;
        NSInteger endNum = endField.integerValue;
        BOOL overwrite = (overwriteCheck.state == NSControlStateValueOn);
        NSInteger current = startNum;
        NSInteger increment = (startNum <= endNum) ? 1 : -1;

        // Get all timing marks on layer 0
        NSArray<NSDictionary *> *marks = [self->_engineBridge getTimingMarks:trackName layer:0];

        for (NSDictionary *mark in marks) {
            NSString *existingLabel = mark[@"label"];
            if (overwrite || !existingLabel || existingLabel.length == 0) {
                NSInteger markId = [mark[@"id"] integerValue];
                NSString *newLabel = [NSString stringWithFormat:@"%ld", (long)current];
                [self->_engineBridge setTimingMarkLabel:markId label:newLabel];

                current += increment;
                if (increment == 1 && current > endNum) {
                    current = startNum;
                } else if (increment == -1 && current < endNum) {
                    current = startNum;
                }
            }
        }

        [self reloadSequenceData];
        [gridView reloadData];
        NSLog(@"Auto Label Timings completed on track '%@'", trackName);
    }];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestAddShimmerAtIndex:(NSInteger)effectIndex
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *markInfo = [_engineBridge getTimingMark:effectId];
    if (!markInfo) return;

    NSString *currentLabel = markInfo[@"label"];
    if (!currentLabel) currentLabel = @"";

    // Only add to short phoneme labels (3 chars or less, matching legacy behavior)
    if (currentLabel.length <= 3 && ![currentLabel.lowercaseString hasSuffix:@"-shimmer"]) {
        NSString *newLabel = [currentLabel stringByAppendingString:@"-shimmer"];
        [_engineBridge setTimingMarkLabel:effectId label:newLabel];
        [self reloadSequenceData];
        [gridView reloadData];
        NSLog(@"Added '-shimmer' to effect %ld: '%@' -> '%@'", (long)effectId, currentLabel, newLabel);
    }
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestRemoveShimmerAtIndex:(NSInteger)effectIndex
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *markInfo = [_engineBridge getTimingMark:effectId];
    if (!markInfo) return;

    NSString *currentLabel = markInfo[@"label"];
    if (!currentLabel) return;

    if ([currentLabel.lowercaseString hasSuffix:@"-shimmer"]) {
        NSString *newLabel = [currentLabel substringToIndex:currentLabel.length - 8];
        [_engineBridge setTimingMarkLabel:effectId label:newLabel];
        [self reloadSequenceData];
        [gridView reloadData];
        NSLog(@"Removed '-shimmer' from effect %ld: '%@' -> '%@'", (long)effectId, currentLabel, newLabel);
    }
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestCreateAlternatingPhonemesAtIndex:(NSInteger)effectIndex
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *markInfo = [_engineBridge getTimingMark:effectId];
    if (!markInfo) return;

    NSString *trackName = markInfo[@"trackName"];
    NSInteger layer = [markInfo[@"layer"] integerValue];
    NSInteger startTime = [markInfo[@"startTimeMS"] integerValue];
    NSInteger endTime = [markInfo[@"endTimeMS"] integerValue];
    NSString *currentLabel = markInfo[@"label"] ?: @"";

    if (endTime <= startTime || !trackName) return;

    // Show alternating phonemes configuration dialog
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Create Alternating Phonemes";
    alert.informativeText = @"Enter two phonemes and the number of alternations:";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 95)];

    NSTextField *phoneme1Label = [NSTextField labelWithString:@"Phoneme 1:"];
    phoneme1Label.frame = NSMakeRect(0, 67, 90, 20);
    [accessoryView addSubview:phoneme1Label];
    NSTextField *phoneme1Field = [[NSTextField alloc] initWithFrame:NSMakeRect(95, 67, 80, 24)];
    phoneme1Field.stringValue = currentLabel.length > 0 ? currentLabel : @"AI";
    [accessoryView addSubview:phoneme1Field];

    NSTextField *phoneme2Label = [NSTextField labelWithString:@"Phoneme 2:"];
    phoneme2Label.frame = NSMakeRect(0, 37, 90, 20);
    [accessoryView addSubview:phoneme2Label];
    NSTextField *phoneme2Field = [[NSTextField alloc] initWithFrame:NSMakeRect(95, 37, 80, 24)];
    phoneme2Field.stringValue = @"rest";
    [accessoryView addSubview:phoneme2Field];

    NSTextField *countLabel = [NSTextField labelWithString:@"Count:"];
    countLabel.frame = NSMakeRect(0, 7, 90, 20);
    [accessoryView addSubview:countLabel];
    NSTextField *countField = [[NSTextField alloc] initWithFrame:NSMakeRect(95, 7, 80, 24)];
    countField.stringValue = @"4";
    [accessoryView addSubview:countField];

    alert.accessoryView = accessoryView;

    [alert beginSheetModalForWindow:gridView.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) return;

        NSString *phoneme1 = phoneme1Field.stringValue;
        NSString *phoneme2 = phoneme2Field.stringValue;
        NSInteger count = countField.integerValue;

        if (count < 2 || phoneme1.length == 0 || phoneme2.length == 0) return;

        double subdivisionDuration = (double)(endTime - startTime) / (double)count;

        // Delete the original timing mark
        [self->_engineBridge deleteTimingMark:effectId];

        // Create alternating phoneme marks
        for (NSInteger i = 0; i < count; i++) {
            NSInteger newStart = startTime + (NSInteger)(subdivisionDuration * (double)i);
            NSInteger newEnd = (i == count - 1) ? endTime
                : startTime + (NSInteger)(subdivisionDuration * (double)(i + 1));
            NSString *phonemeLabel = (i % 2 == 0) ? phoneme1 : phoneme2;

            if (newStart < newEnd) {
                [self->_engineBridge createTimingMark:trackName layer:layer
                                         startTimeMS:newStart endTimeMS:newEnd
                                               label:phonemeLabel];
            }
        }

        [self reloadSequenceData];
        [gridView reloadData];
        NSLog(@"Created %ld alternating phonemes ('%@'/'%@') for effect %ld",
              (long)count, phoneme1, phoneme2, (long)effectId);
    }];
}

- (void)effectsGridDidRequestFindTimingLabel:(XLEffectsGridView *)gridView
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Find Timing Label";
    alert.informativeText = @"Enter text to find:";
    [alert addButtonWithTitle:@"Find"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *searchField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    searchField.stringValue = _timingSearchText ?: @"";
    alert.accessoryView = searchField;

    [alert beginSheetModalForWindow:gridView.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) return;

        NSString *searchText = searchField.stringValue;
        if (searchText.length == 0) return;

        self->_timingSearchText = searchText;
        self->_timingLastFoundIndex = -1;
        self->_timingSearchTrackName = [self activeTimingTrackForOperation];

        [self effectsGridDidRequestFindNextTimingLabel:gridView];
    }];
}

- (void)effectsGridDidRequestFindNextTimingLabel:(XLEffectsGridView *)gridView
{
    if (!_timingSearchText || _timingSearchText.length == 0 || !_timingSearchTrackName) {
        NSAlert *noSearch = [[NSAlert alloc] init];
        noSearch.messageText = @"Find";
        noSearch.informativeText = @"No search text. Use Find... first.";
        [noSearch addButtonWithTitle:@"OK"];
        [noSearch beginSheetModalForWindow:gridView.window completionHandler:nil];
        return;
    }

    // Search all layers of the active timing track
    for (NSInteger layer = 0; layer <= 2; layer++) {
        NSArray<NSDictionary *> *marks = [_engineBridge getTimingMarks:_timingSearchTrackName layer:layer];
        if (!marks || marks.count == 0) continue;

        NSInteger startIdx = (_timingSearchLayer == layer) ? _timingLastFoundIndex + 1 : 0;
        if (_timingSearchLayer > layer) continue;
        if (_timingSearchLayer < layer) startIdx = 0;

        for (NSInteger i = startIdx; i < (NSInteger)marks.count; i++) {
            NSString *label = marks[(NSUInteger)i][@"label"];
            if (label && [label.lowercaseString containsString:_timingSearchText.lowercaseString]) {
                _timingLastFoundIndex = i;
                _timingSearchLayer = layer;

                // Scroll to the found mark
                NSInteger midTimeMS = ([marks[(NSUInteger)i][@"startTimeMS"] integerValue] +
                                       [marks[(NSUInteger)i][@"endTimeMS"] integerValue]) / 2;
                [gridView scrollToTimeMS:(CGFloat)midTimeMS];
                NSLog(@"Found '%@' at layer %ld, index %ld, time %ldms",
                      label, (long)layer, (long)i, (long)midTimeMS);
                return;
            }
        }
    }

    NSAlert *notFound = [[NSAlert alloc] init];
    notFound.messageText = @"Find";
    notFound.informativeText = @"Text not found.";
    [notFound addButtonWithTitle:@"OK"];
    [notFound beginSheetModalForWindow:gridView.window completionHandler:nil];
}

- (void)effectsGridDidRequestFindPreviousTimingLabel:(XLEffectsGridView *)gridView
{
    if (!_timingSearchText || _timingSearchText.length == 0 || !_timingSearchTrackName) {
        NSAlert *noSearch = [[NSAlert alloc] init];
        noSearch.messageText = @"Find";
        noSearch.informativeText = @"No search text. Use Find... first.";
        [noSearch addButtonWithTitle:@"OK"];
        [noSearch beginSheetModalForWindow:gridView.window completionHandler:nil];
        return;
    }

    // Search backwards through all layers
    for (NSInteger layer = 2; layer >= 0; layer--) {
        NSArray<NSDictionary *> *marks = [_engineBridge getTimingMarks:_timingSearchTrackName layer:layer];
        if (!marks || marks.count == 0) continue;

        NSInteger startIdx;
        if (_timingSearchLayer == layer) {
            startIdx = _timingLastFoundIndex - 1;
        } else if (_timingSearchLayer > layer) {
            startIdx = (NSInteger)marks.count - 1;
        } else {
            continue;
        }

        for (NSInteger i = startIdx; i >= 0; i--) {
            NSString *label = marks[(NSUInteger)i][@"label"];
            if (label && [label.lowercaseString containsString:_timingSearchText.lowercaseString]) {
                _timingLastFoundIndex = i;
                _timingSearchLayer = layer;

                NSInteger midTimeMS = ([marks[(NSUInteger)i][@"startTimeMS"] integerValue] +
                                       [marks[(NSUInteger)i][@"endTimeMS"] integerValue]) / 2;
                [gridView scrollToTimeMS:(CGFloat)midTimeMS];
                NSLog(@"Found '%@' at layer %ld, index %ld, time %ldms",
                      label, (long)layer, (long)i, (long)midTimeMS);
                return;
            }
        }
    }

    NSAlert *notFound = [[NSAlert alloc] init];
    notFound.messageText = @"Find";
    notFound.informativeText = @"Text not found.";
    [notFound addButtonWithTitle:@"OK"];
    [notFound beginSheetModalForWindow:gridView.window completionHandler:nil];
}

- (void)effectsGridDidRequestReplaceAllTimingLabels:(XLEffectsGridView *)gridView
{
    if (!_timingSearchText || _timingSearchText.length == 0) {
        NSAlert *noSearch = [[NSAlert alloc] init];
        noSearch.messageText = @"Replace All";
        noSearch.informativeText = @"No search text. Use Find... first.";
        [noSearch addButtonWithTitle:@"OK"];
        [noSearch beginSheetModalForWindow:gridView.window completionHandler:nil];
        return;
    }

    NSString *trackName = _timingSearchTrackName ?: [self activeTimingTrackForOperation];
    if (!trackName) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Replace All";
    alert.informativeText = [NSString stringWithFormat:@"Replace all occurrences of \"%@\" with:", _timingSearchText];
    [alert addButtonWithTitle:@"Replace All"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *replaceField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    replaceField.stringValue = _timingSearchText;
    alert.accessoryView = replaceField;

    [alert beginSheetModalForWindow:gridView.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) return;

        NSString *replaceText = replaceField.stringValue;
        NSInteger replacedCount = 0;

        // Replace across all layers
        for (NSInteger layer = 0; layer <= 2; layer++) {
            NSArray<NSDictionary *> *marks = [self->_engineBridge getTimingMarks:trackName layer:layer];
            for (NSDictionary *mark in marks) {
                NSString *label = mark[@"label"];
                if (label && [label.lowercaseString containsString:self->_timingSearchText.lowercaseString]) {
                    NSInteger markId = [mark[@"id"] integerValue];
                    [self->_engineBridge setTimingMarkLabel:markId label:replaceText];
                    replacedCount++;
                }
            }
        }

        [self reloadSequenceData];
        [gridView reloadData];
        NSLog(@"Replace All completed: replaced %ld occurrence(s) of '%@' with '%@'",
              (long)replacedCount, self->_timingSearchText, replaceText);
    }];
}

#pragma mark - XLEffectsGridDelegate (Alignment Operations)

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestAlignEffects:(NSIndexSet *)effectIndices
           alignmentType:(XLAlignmentType)alignmentType
{
    if (!_engineBridge || effectIndices.count == 0) return;

    NSString *typeName;
    switch (alignmentType) {
        case XLAlignmentTypeStartTimes:           typeName = @"Align Start Times"; break;
        case XLAlignmentTypeEndTimes:             typeName = @"Align End Times"; break;
        case XLAlignmentTypeBothTimes:            typeName = @"Align Both Times"; break;
        case XLAlignmentTypeCenterpoints:         typeName = @"Align Centerpoints"; break;
        case XLAlignmentTypeMatchDuration:        typeName = @"Match Duration"; break;
        case XLAlignmentTypeShiftStartTimes:      typeName = @"Shift Align Start Times"; break;
        case XLAlignmentTypeShiftEndTimes:        typeName = @"Shift Align End Times"; break;
        case XLAlignmentTypeToClosestTimingMark:  typeName = @"Align To Closest Timing Mark"; break;
        case XLAlignmentTypeCloseGap:             typeName = @"Close Gap"; break;
    }

    // Gather effect info for all selected effects, preserving index order
    NSMutableArray<NSDictionary *> *selectedEffects = [NSMutableArray arrayWithCapacity:effectIndices.count];
    [effectIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger effectId = [gridView effectIdAtRenderIndex:idx];
        if (effectId < 0) return;
        NSDictionary *info = [self->_engineBridge getEffect:effectId];
        if (!info) return;
        [selectedEffects addObject:info];
    }];

    if (selectedEffects.count < 1) return;

    // The first selected effect serves as the reference (anchor) for alignment
    NSDictionary *refEffect = selectedEffects[0];
    NSInteger refStart = [refEffect[@"startTimeMS"] integerValue];
    NSInteger refEnd = [refEffect[@"endTimeMS"] integerValue];
    NSInteger refDuration = refEnd - refStart;
    NSInteger refCenter = refStart + refDuration / 2;

    // Dispatch to timing-mark and close-gap handlers which have different logic
    if (alignmentType == XLAlignmentTypeToClosestTimingMark) {
        [self alignEffectsToClosestTimingMark:selectedEffects gridView:gridView];
        return;
    }
    if (alignmentType == XLAlignmentTypeCloseGap) {
        [self closeGapBetweenEffects:selectedEffects gridView:gridView];
        return;
    }

    // Register undo for the batch
    [_undoController beginUndoGroupingWithActionName:typeName];

    BOOL anyMoved = NO;
    for (NSDictionary *info in selectedEffects) {
        NSInteger effectId = [info[@"id"] integerValue];
        NSInteger origStart = [info[@"startTimeMS"] integerValue];
        NSInteger origEnd = [info[@"endTimeMS"] integerValue];
        BOOL locked = [info[@"isLocked"] boolValue];
        if (locked) continue;

        NSInteger newStart = origStart;
        NSInteger newEnd = origEnd;

        switch (alignmentType) {
            case XLAlignmentTypeStartTimes: {
                newStart = refStart;
                if (origEnd > refStart) {
                    newEnd = origEnd;
                } else {
                    NSInteger delta = newStart - origStart;
                    newEnd = origEnd + delta;
                }
                break;
            }
            case XLAlignmentTypeEndTimes: {
                newEnd = refEnd;
                if (origStart < refEnd) {
                    newStart = origStart;
                } else {
                    NSInteger delta = newEnd - origEnd;
                    newStart = origStart + delta;
                }
                break;
            }
            case XLAlignmentTypeBothTimes: {
                newStart = refStart;
                newEnd = refEnd;
                break;
            }
            case XLAlignmentTypeCenterpoints: {
                NSInteger effDuration = origEnd - origStart;
                NSInteger effCenter = origStart + effDuration / 2;
                NSInteger delta = refCenter - effCenter;
                newStart = origStart + delta;
                newEnd = origEnd + delta;
                break;
            }
            case XLAlignmentTypeMatchDuration: {
                newStart = origStart;
                newEnd = origStart + refDuration;
                break;
            }
            case XLAlignmentTypeShiftStartTimes: {
                newStart = refStart;
                NSInteger delta = newStart - origStart;
                newEnd = origEnd + delta;
                break;
            }
            case XLAlignmentTypeShiftEndTimes: {
                newEnd = refEnd;
                NSInteger delta = newEnd - origEnd;
                newStart = origStart + delta;
                break;
            }
            default:
                break;
        }

        // Clamp start to >= 0
        if (newStart < 0) {
            NSInteger shift = -newStart;
            newStart = 0;
            newEnd += shift;
        }

        // Only move if something changed and the result is valid
        if ((newStart != origStart || newEnd != origEnd) && newEnd > newStart) {
            XLEffectSnapshot snapshot;
            snapshot.effectID = effectId;
            snapshot.startTimeMS = (CGFloat)origStart;
            snapshot.endTimeMS = (CGFloat)origEnd;
            snapshot.row = [info[@"layerIndex"] integerValue];
            snapshot.layer = [info[@"layerIndex"] integerValue];
            snapshot.effectTypeIndex = [info[@"effectIndex"] integerValue];
            snapshot.colorARGB = 0;
            snapshot.selected = YES;
            snapshot.locked = NO;
            snapshot.renderDisabled = [info[@"isRenderDisabled"] boolValue];
            [_undoController captureEffectToBeMoved:snapshot actionName:typeName];

            [_engineBridge moveEffect:effectId startTimeMS:newStart endTimeMS:newEnd];
            anyMoved = YES;
        }
    }

    [_undoController endUndoGrouping];

    if (anyMoved) {
        [self reloadSequenceData];
        [_playbackController renderCurrentFrame];
        [gridView reloadData];
    }
}

/// Snap each selected effect's start and end to the nearest timing mark.
- (void)alignEffectsToClosestTimingMark:(NSArray<NSDictionary *> *)selectedEffects
                               gridView:(XLEffectsGridView *)gridView
{
    NSArray<NSNumber *> *markTimes = [_engineBridge getActiveTimingMarkTimes];
    if (markTimes.count == 0) {
        NSLog(@"Align To Closest Timing Mark: no active timing track or no marks");
        return;
    }

    // Sort mark times for efficient lookup
    NSArray<NSNumber *> *sortedMarks = [markTimes sortedArrayUsingSelector:@selector(compare:)];

    [_undoController beginUndoGroupingWithActionName:@"Align To Closest Timing Mark"];

    BOOL anyMoved = NO;
    for (NSDictionary *info in selectedEffects) {
        NSInteger effectId = [info[@"id"] integerValue];
        NSInteger origStart = [info[@"startTimeMS"] integerValue];
        NSInteger origEnd = [info[@"endTimeMS"] integerValue];
        BOOL locked = [info[@"isLocked"] boolValue];
        if (locked) continue;

        NSInteger closestStart = [self findClosestTimingMark:origStart inSortedMarks:sortedMarks];
        NSInteger closestEnd = [self findClosestTimingMark:origEnd inSortedMarks:sortedMarks];

        // Skip if snapped start equals snapped end (would create zero-length effect)
        if (closestStart == closestEnd) continue;
        // Skip if nothing changed
        if (closestStart == origStart && closestEnd == origEnd) continue;
        // Ensure valid ordering
        if (closestEnd <= closestStart) continue;

        XLEffectSnapshot snapshot;
        snapshot.effectID = effectId;
        snapshot.startTimeMS = (CGFloat)origStart;
        snapshot.endTimeMS = (CGFloat)origEnd;
        snapshot.row = [info[@"layerIndex"] integerValue];
        snapshot.layer = [info[@"layerIndex"] integerValue];
        snapshot.effectTypeIndex = [info[@"effectIndex"] integerValue];
        snapshot.colorARGB = 0;
        snapshot.selected = YES;
        snapshot.locked = NO;
        snapshot.renderDisabled = [info[@"isRenderDisabled"] boolValue];
        [_undoController captureEffectToBeMoved:snapshot actionName:@"Align To Closest Timing Mark"];

        [_engineBridge moveEffect:effectId startTimeMS:closestStart endTimeMS:closestEnd];
        anyMoved = YES;
    }

    [_undoController endUndoGrouping];

    if (anyMoved) {
        [self reloadSequenceData];
        [_playbackController renderCurrentFrame];
        [gridView reloadData];
    }
}

/// Find the timing mark time closest to a given time value.
- (NSInteger)findClosestTimingMark:(NSInteger)timeMS inSortedMarks:(NSArray<NSNumber *> *)sortedMarks
{
    if (sortedMarks.count == 0) return timeMS;

    // Binary search for the insertion point
    NSUInteger lo = 0;
    NSUInteger hi = sortedMarks.count;
    while (lo < hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        if (sortedMarks[mid].integerValue < timeMS) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }

    // Compare the candidate at `lo` and `lo-1` to find the closest
    NSInteger bestTime = timeMS;
    NSInteger bestDist = NSIntegerMax;

    if (lo < sortedMarks.count) {
        NSInteger dist = ABS(sortedMarks[lo].integerValue - timeMS);
        if (dist < bestDist) {
            bestDist = dist;
            bestTime = sortedMarks[lo].integerValue;
        }
    }
    if (lo > 0) {
        NSInteger dist = ABS(sortedMarks[lo - 1].integerValue - timeMS);
        if (dist < bestDist) {
            bestDist = dist;
            bestTime = sortedMarks[lo - 1].integerValue;
        }
    }

    return bestTime;
}

/// Remove gaps between consecutive selected effects, collapsing them toward
/// the primary (first) selected effect.
- (void)closeGapBetweenEffects:(NSArray<NSDictionary *> *)selectedEffects
                      gridView:(XLEffectsGridView *)gridView
{
    if (selectedEffects.count < 2) return;

    // Sort by start time to process in temporal order
    NSArray<NSDictionary *> *sorted = [selectedEffects sortedArrayUsingComparator:
        ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [@([a[@"startTimeMS"] integerValue]) compare:@([b[@"startTimeMS"] integerValue])];
        }];

    // Find the index of the primary (first-selected, reference) effect in the sorted list
    NSInteger refId = [selectedEffects[0][@"id"] integerValue];
    NSUInteger refSortedIndex = 0;
    for (NSUInteger i = 0; i < sorted.count; i++) {
        if ([sorted[i][@"id"] integerValue] == refId) {
            refSortedIndex = i;
            break;
        }
    }

    NSInteger refStart = [sorted[refSortedIndex][@"startTimeMS"] integerValue];
    NSInteger refEnd = [sorted[refSortedIndex][@"endTimeMS"] integerValue];

    [_undoController beginUndoGroupingWithActionName:@"Close Gap"];

    BOOL anyMoved = NO;

    // Close gaps for effects BEFORE the reference (shift them rightward to abut)
    for (NSInteger i = (NSInteger)refSortedIndex - 1; i >= 0; i--) {
        NSDictionary *info = sorted[(NSUInteger)i];
        NSInteger effectId = [info[@"id"] integerValue];
        NSInteger origStart = [info[@"startTimeMS"] integerValue];
        NSInteger origEnd = [info[@"endTimeMS"] integerValue];
        BOOL locked = [info[@"isLocked"] boolValue];
        if (locked) continue;

        // The next effect toward the reference (i+1) provides the target start
        NSInteger nextStart;
        if (i == (NSInteger)refSortedIndex - 1) {
            nextStart = refStart;
        } else {
            // Use the already-moved position of the effect at i+1
            NSDictionary *nextInfo = sorted[(NSUInteger)(i + 1)];
            NSInteger nextEffectId = [nextInfo[@"id"] integerValue];
            NSDictionary *updatedNext = [_engineBridge getEffect:nextEffectId];
            nextStart = updatedNext ? [updatedNext[@"startTimeMS"] integerValue] : [nextInfo[@"startTimeMS"] integerValue];
        }

        NSInteger gap = nextStart - origEnd;
        if (gap <= 0) continue;

        NSInteger newStart = origStart + gap;
        NSInteger newEnd = origEnd + gap;

        XLEffectSnapshot snapshot;
        snapshot.effectID = effectId;
        snapshot.startTimeMS = (CGFloat)origStart;
        snapshot.endTimeMS = (CGFloat)origEnd;
        snapshot.row = [info[@"layerIndex"] integerValue];
        snapshot.layer = [info[@"layerIndex"] integerValue];
        snapshot.effectTypeIndex = [info[@"effectIndex"] integerValue];
        snapshot.colorARGB = 0;
        snapshot.selected = YES;
        snapshot.locked = NO;
        snapshot.renderDisabled = [info[@"isRenderDisabled"] boolValue];
        [_undoController captureEffectToBeMoved:snapshot actionName:@"Close Gap"];

        [_engineBridge moveEffect:effectId startTimeMS:newStart endTimeMS:newEnd];
        anyMoved = YES;
    }

    // Close gaps for effects AFTER the reference (shift them leftward to abut)
    NSInteger lastEndTime = refEnd;
    for (NSUInteger i = refSortedIndex + 1; i < sorted.count; i++) {
        NSDictionary *info = sorted[i];
        NSInteger effectId = [info[@"id"] integerValue];
        NSInteger origStart = [info[@"startTimeMS"] integerValue];
        NSInteger origEnd = [info[@"endTimeMS"] integerValue];
        BOOL locked = [info[@"isLocked"] boolValue];
        if (locked) {
            lastEndTime = origEnd;
            continue;
        }

        NSInteger gap = origStart - lastEndTime;
        if (gap > 0) {
            NSInteger newStart = origStart - gap;
            NSInteger newEnd = origEnd - gap;

            XLEffectSnapshot snapshot;
            snapshot.effectID = effectId;
            snapshot.startTimeMS = (CGFloat)origStart;
            snapshot.endTimeMS = (CGFloat)origEnd;
            snapshot.row = [info[@"layerIndex"] integerValue];
            snapshot.layer = [info[@"layerIndex"] integerValue];
            snapshot.effectTypeIndex = [info[@"effectIndex"] integerValue];
            snapshot.colorARGB = 0;
            snapshot.selected = YES;
            snapshot.locked = NO;
            snapshot.renderDisabled = [info[@"isRenderDisabled"] boolValue];
            [_undoController captureEffectToBeMoved:snapshot actionName:@"Close Gap"];

            [_engineBridge moveEffect:effectId startTimeMS:newStart endTimeMS:newEnd];
            anyMoved = YES;

            lastEndTime = newEnd;
        } else {
            lastEndTime = origEnd;
        }
    }

    [_undoController endUndoGrouping];

    if (anyMoved) {
        [self reloadSequenceData];
        [_playbackController renderCurrentFrame];
        [gridView reloadData];
    }
}

#pragma mark - Symbol Library / Presets Helpers

- (void)ensureSymbolLibraryManager {
    if (!_symbolLibraryManager) {
        _symbolLibraryManager = [[XLSymbolLibraryManager alloc] initWithEngineBridge:_engineBridge];
    }
}

#pragma mark - XLEffectsGridDelegate (Symbol Library Operations)

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestCreateSymbolFromEffectAtIndex:(NSInteger)effectIndex
{
    NSInteger effectId = [gridView effectIdAtRenderIndex:(NSUInteger)effectIndex];
    if (effectId < 0 || !_engineBridge) return;

    [self ensureSymbolLibraryManager];

    NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
    NSString *effectType = effectInfo[@"effectType"] ?: @"Effect";

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Create Symbol";
    alert.informativeText = [NSString stringWithFormat:
        @"Save the current %@ effect as a reusable symbol.\nLinked effects will update when the symbol changes.", effectType];
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    nameField.stringValue = [NSString stringWithFormat:@"My %@ Symbol", effectType];
    nameField.placeholderString = @"Symbol name";
    alert.accessoryView = nameField;

    [alert beginSheetModalForWindow:gridView.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) return;

        NSString *name = nameField.stringValue;
        if (name.length == 0) return;

        NSString *symbolId = [self->_symbolLibraryManager createSymbolFromEffect:effectId withName:name];
        if (symbolId) {
            NSLog(@"Created symbol '%@' (ID: %@) from effect %ld", name, symbolId, (long)effectId);
            [self updateAvailableSymbolNames];
            [self reloadSequenceData];
            [gridView reloadData];
        }
    }];
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestUnlinkFromSymbol:(NSIndexSet *)effectIndices
{
    if (!_engineBridge || effectIndices.count == 0) return;

    [self ensureSymbolLibraryManager];

    __block NSInteger unlinkedCount = 0;
    [effectIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger effectId = [gridView effectIdAtRenderIndex:idx];
        if (effectId >= 0 && [self->_symbolLibraryManager unlinkEffect:effectId]) {
            unlinkedCount++;
        }
    }];

    NSLog(@"Unlinked %ld of %lu effects from their symbols",
          (long)unlinkedCount, (unsigned long)effectIndices.count);

    if (unlinkedCount > 0) {
        [self reloadSequenceData];
        [gridView reloadData];
    }
}

- (void)effectsGrid:(XLEffectsGridView *)gridView
    didRequestLinkEffects:(NSIndexSet *)effectIndices
           toSymbolIndex:(NSInteger)symbolIndex
{
    if (!_engineBridge || effectIndices.count == 0) return;

    [self ensureSymbolLibraryManager];

    NSDictionary *symbol = [_symbolLibraryManager symbolAtIndex:symbolIndex];
    if (!symbol) {
        NSLog(@"Cannot link effects: symbol at index %ld not found", (long)symbolIndex);
        return;
    }

    NSString *symbolId = symbol[@"symbolId"];
    if (!symbolId) return;

    __block NSInteger linkedCount = 0;
    [effectIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger effectId = [gridView effectIdAtRenderIndex:idx];
        if (effectId >= 0 && [self->_symbolLibraryManager linkEffect:effectId toSymbol:symbolId]) {
            linkedCount++;
        }
    }];

    NSLog(@"Linked %ld of %lu effects to symbol '%@'",
          (long)linkedCount, (unsigned long)effectIndices.count, symbol[@"name"]);

    if (linkedCount > 0) {
        [self reloadSequenceData];
        [gridView reloadData];
    }
}

#pragma mark - Symbol Library Menu Actions

- (void)showSymbolLibrary:(id)sender {
    [self ensureSymbolLibraryManager];
    [_symbolLibraryManager reloadSymbols];
    NSArray<NSDictionary *> *symbols = [_symbolLibraryManager allSymbols];

    if (symbols.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Effect Symbol Library";
        alert.informativeText = @"No symbols defined.\n\nRight-click an effect and choose \"Create Symbol from Effect...\" to create one.";
        alert.alertStyle = NSAlertStyleInformational;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Effect Symbol Library";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"Done"];
    [alert addButtonWithTitle:@"Rename"];
    [alert addButtonWithTitle:@"Delete"];
    alert.informativeText = [NSString stringWithFormat:@"%lu symbol(s) defined. Select a symbol then click Rename or Delete.", (unsigned long)symbols.count];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    NSTableView *tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    tableView.usesAlternatingRowBackgroundColors = YES;
    tableView.rowHeight = 22;
    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameCol.title = @"Symbol Name";
    nameCol.width = 200;
    [tableView addTableColumn:nameCol];
    NSTableColumn *typeCol = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeCol.title = @"Effect Type";
    typeCol.width = 120;
    [tableView addTableColumn:typeCol];
    scrollView.documentView = tableView;

    NSMutableArray<NSDictionary *> *mutableSymbols = [symbols mutableCopy];
    objc_setAssociatedObject(self, @selector(showSymbolLibrary:), mutableSymbols, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    tableView.tag = 9999;
    tableView.dataSource = (id<NSTableViewDataSource>)self;
    tableView.delegate = (id<NSTableViewDelegate>)self;
    alert.accessoryView = scrollView;
    [tableView reloadData];

    NSModalResponse response = [alert runModal];

    if (response == NSAlertSecondButtonReturn) {
        NSInteger selectedRow = tableView.selectedRow;
        if (selectedRow >= 0 && selectedRow < (NSInteger)mutableSymbols.count) {
            NSDictionary *sym = mutableSymbols[(NSUInteger)selectedRow];
            NSAlert *renameAlert = [[NSAlert alloc] init];
            renameAlert.messageText = @"Rename Symbol";
            [renameAlert addButtonWithTitle:@"Rename"];
            [renameAlert addButtonWithTitle:@"Cancel"];
            NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
            nameField.stringValue = sym[@"name"] ?: @"";
            renameAlert.accessoryView = nameField;
            if ([renameAlert runModal] == NSAlertFirstButtonReturn && nameField.stringValue.length > 0) {
                [_symbolLibraryManager renameSymbol:sym[@"symbolId"] toName:nameField.stringValue];
                [self updateAvailableSymbolNames];
            }
        }
    } else if (response == NSAlertThirdButtonReturn) {
        NSInteger selectedRow = tableView.selectedRow;
        if (selectedRow >= 0 && selectedRow < (NSInteger)mutableSymbols.count) {
            NSDictionary *sym = mutableSymbols[(NSUInteger)selectedRow];
            NSString *symbolName = sym[@"name"] ?: @"Unknown";
            NSAlert *confirmAlert = [[NSAlert alloc] init];
            confirmAlert.messageText = @"Delete Symbol?";
            confirmAlert.informativeText = [NSString stringWithFormat:@"Delete \"%@\"?\n\nLinked effects keep settings but are no longer linked.", symbolName];
            [confirmAlert addButtonWithTitle:@"Delete"];
            [confirmAlert addButtonWithTitle:@"Cancel"];
            confirmAlert.alertStyle = NSAlertStyleWarning;
            if ([confirmAlert runModal] == NSAlertFirstButtonReturn) {
                [_symbolLibraryManager deleteSymbol:sym[@"symbolId"]];
                [self updateAvailableSymbolNames];
                [self reloadSequenceData];
                [_effectsGridView reloadData];
            }
        }
    }
    objc_setAssociatedObject(self, @selector(showSymbolLibrary:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)convertAllSymbolsToEffects:(id)sender {
    [self ensureSymbolLibraryManager];
    if (_symbolLibraryManager.symbolCount == 0) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"No Symbols";
        a.informativeText = @"There are no effect symbols to convert.";
        [a addButtonWithTitle:@"OK"];
        [a runModal];
        return;
    }
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Convert All Symbols to Effects?";
    confirm.informativeText = @"This will unlink all effects and delete all symbol definitions.\nEffects keep their current settings.";
    [confirm addButtonWithTitle:@"Convert"];
    [confirm addButtonWithTitle:@"Cancel"];
    confirm.alertStyle = NSAlertStyleWarning;
    if ([confirm runModal] != NSAlertFirstButtonReturn) return;

    NSInteger unlinkedCount = 0;
    for (NSUInteger i = 0; i < _effectCount; i++) {
        if (_effectData[i].isLinkedToSymbol) {
            [_symbolLibraryManager unlinkEffect:_effectData[i].effectIndex];
            unlinkedCount++;
        }
    }
    NSArray<NSDictionary *> *allSymbols = [[_symbolLibraryManager allSymbols] copy];
    for (NSDictionary *sym in allSymbols) {
        [_symbolLibraryManager deleteSymbol:sym[@"symbolId"]];
    }
    [self updateAvailableSymbolNames];
    [self reloadSequenceData];
    [_effectsGridView reloadData];
    NSLog(@"Converted all symbols: unlinked %ld effects, deleted %lu symbols", (long)unlinkedCount, (unsigned long)allSymbols.count);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView.tag == 9999) {
        NSArray *syms = objc_getAssociatedObject(self, @selector(showSymbolLibrary:));
        return (NSInteger)syms.count;
    }
    return 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView.tag != 9999) return nil;
    NSArray<NSDictionary *> *syms = objc_getAssociatedObject(self, @selector(showSymbolLibrary:));
    if (row < 0 || row >= (NSInteger)syms.count) return nil;
    NSDictionary *sym = syms[(NSUInteger)row];
    NSTextField *cell = [NSTextField labelWithString:@""];
    cell.lineBreakMode = NSLineBreakByTruncatingTail;
    if ([tableColumn.identifier isEqualToString:@"name"]) {
        cell.stringValue = sym[@"name"] ?: @"Unnamed";
    } else if ([tableColumn.identifier isEqualToString:@"type"]) {
        cell.stringValue = sym[@"effectType"] ?: @"Unknown";
    }
    return cell;
}

#pragma mark - XLRowHeadingsDataSource

- (NSInteger)numberOfRowsInRowHeadings:(XLRowHeadingsView *)view {
    return (NSInteger)_rowCount;
}

- (NSString *)rowHeadings:(XLRowHeadingsView *)view nameForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return @"";

    XLRowEntry *rowEntry = &_rowData[row];
    NSString *name = [NSString stringWithUTF8String:rowEntry->name];

    // Folder rows just show folder name
    if (rowEntry->isFolder) return name;

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

- (NSInteger)rowHeadings:(XLRowHeadingsView *)view timingColorIndexForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return 0;
    return _rowData[row].timingColorIndex;
}

- (BOOL)rowHeadings:(XLRowHeadingsView *)view isFolderAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return NO;
    return _rowData[row].isFolder;
}

- (BOOL)rowHeadings:(XLRowHeadingsView *)view isFolderCollapsedAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return NO;
    return _rowData[row].folderCollapsed;
}

#pragma mark - XLRowHeadingsDelegate

- (void)rowHeadings:(XLRowHeadingsView *)view didToggleExpandAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return;

    XLRowEntry *mainRow = &_rowData[row];

    // Handle folder expand/collapse
    if (mainRow->isFolder) {
        [self toggleFolderAtRow:row];
        return;
    }

    // Only allow expand/collapse on main element rows with multiple layers
    if (mainRow->isLayerRow || !mainRow->expandable) return;

    BOOL wasExpanded = mainRow->expanded;
    mainRow->expanded = !wasExpanded;

    NSLog(@"Toggled expand for row %ld: %s (layers: %ld)", (long)row, mainRow->name, (long)mainRow->effectLayerCount);

    // Compute indent for layer rows based on whether parent is in a folder
    NSInteger layerIndent = (mainRow->folderName[0] != '\0') ? 2 : 1;

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
            layerRow->timingColorIndex = mainRow->timingColorIndex;
            layerRow->layerIndex = i + 1;  // Layer 1, 2, 3, etc.
            layerRow->isLayerRow = YES;
            layerRow->indent = layerIndent;
            layerRow->expandable = NO;
            layerRow->expanded = NO;
            // Inherit folder membership
            strncpy(layerRow->folderName, mainRow->folderName, sizeof(layerRow->folderName));
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

    // Recount timing rows after expand/collapse (timing track layers change the count)
    _timingRowCount = 0;
    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (_rowData[i].type == XLElementTypeTiming) {
            _timingRowCount++;
        } else {
            break;
        }
    }
    _effectsGridView.pinnedTimingRowCount = _timingRowCount;
    _rowHeadingsView.pinnedTimingRowCount = _timingRowCount;

    // Update max scroll for changed row count
    if (_scrollCoordinator) {
        CGFloat viewHeight = NSHeight(_effectsGridView.bounds);
        CGFloat maxScrollY = _rowCount * _effectsGridView.rowHeight - viewHeight;
        _scrollCoordinator.maxVerticalScrollOffset = fmax(0, maxScrollY);
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

    XLRowEntry *sourceEntry = &_rowData[fromRow];

    if (sourceEntry->isFolder) {
        // Moving an entire folder — count children that follow
        NSInteger childCount = 0;
        const char *fn = sourceEntry->folderName;
        for (NSInteger i = fromRow + 1; i < (NSInteger)_rowCount; i++) {
            if (!_rowData[i].isFolder && strcmp(_rowData[i].folderName, fn) == 0) {
                childCount++;
            } else {
                break;
            }
        }

        NSInteger blockSize = 1 + childCount;

        // Prevent dropping inside the folder's own range
        if (toRow > fromRow && toRow <= fromRow + blockSize) return;

        // Save the block
        XLRowEntry *block = (XLRowEntry *)malloc((size_t)blockSize * sizeof(XLRowEntry));
        memcpy(block, &_rowData[fromRow], (size_t)blockSize * sizeof(XLRowEntry));

        // Calculate adjusted insert position
        NSInteger adjustedTo = (toRow > fromRow) ? toRow - blockSize : toRow;
        if (adjustedTo < 0) adjustedTo = 0;
        if (adjustedTo > (NSInteger)_rowCount - blockSize)
            adjustedTo = (NSInteger)_rowCount - blockSize;

        // Remove block from old position
        if (fromRow + blockSize < (NSInteger)_rowCount) {
            memmove(&_rowData[fromRow], &_rowData[fromRow + blockSize],
                    (_rowCount - (NSUInteger)(fromRow + blockSize)) * sizeof(XLRowEntry));
        }
        _rowCount -= (NSUInteger)blockSize;

        // Insert block at new position
        if (adjustedTo < (NSInteger)_rowCount) {
            memmove(&_rowData[adjustedTo + blockSize], &_rowData[adjustedTo],
                    (_rowCount - (NSUInteger)adjustedTo) * sizeof(XLRowEntry));
        }
        memcpy(&_rowData[adjustedTo], block, (size_t)blockSize * sizeof(XLRowEntry));
        _rowCount += (NSUInteger)blockSize;

        free(block);
    } else if (sourceEntry->folderName[0] != '\0' && !sourceEntry->isLayerRow) {
        // Moving a child element — check if it's leaving its folder
        const char *currentFolderCStr = sourceEntry->folderName;

        // Find the folder header row
        NSInteger folderHeaderRow = -1;
        for (NSInteger i = fromRow - 1; i >= 0; i--) {
            if (_rowData[i].isFolder && strcmp(_rowData[i].folderName, currentFolderCStr) == 0) {
                folderHeaderRow = i;
                break;
            }
        }

        // Find the last child in the folder
        NSInteger lastFolderChild = fromRow;
        if (folderHeaderRow >= 0) {
            for (NSInteger i = folderHeaderRow + 1; i < (NSInteger)_rowCount; i++) {
                if (!_rowData[i].isFolder && strcmp(_rowData[i].folderName, currentFolderCStr) == 0) {
                    lastFolderChild = i;
                } else {
                    break;
                }
            }
        }

        // If dropping outside the folder range, ungroup
        BOOL leavingFolder = (toRow <= folderHeaderRow || toRow > lastFolderChild + 1);
        if (leavingFolder) {
            NSString *elemName = [NSString stringWithUTF8String:sourceEntry->name];
            [self.engineBridge setElement:elemName folder:nil];
            sourceEntry->folderName[0] = '\0';
            sourceEntry->indent = 0;
        }

        // Standard single-row reorder
        XLRowEntry moved = _rowData[fromRow];
        NSInteger insertIdx = (toRow > fromRow) ? toRow - 1 : toRow;
        if (insertIdx > (NSInteger)_rowCount - 1) insertIdx = (NSInteger)_rowCount - 1;
        if (insertIdx < 0) insertIdx = 0;

        if (fromRow < insertIdx) {
            memmove(&_rowData[fromRow], &_rowData[fromRow + 1],
                    (size_t)(insertIdx - fromRow) * sizeof(XLRowEntry));
        } else if (fromRow > insertIdx) {
            memmove(&_rowData[insertIdx + 1], &_rowData[insertIdx],
                    (size_t)(fromRow - insertIdx) * sizeof(XLRowEntry));
        }
        _rowData[insertIdx] = moved;
    } else {
        // Standard single-row reorder (no folder involvement)
        XLRowEntry moved = _rowData[fromRow];
        NSInteger insertIdx = (toRow > fromRow) ? toRow - 1 : toRow;
        if (insertIdx > (NSInteger)_rowCount - 1) insertIdx = (NSInteger)_rowCount - 1;
        if (insertIdx < 0) insertIdx = 0;

        if (fromRow < insertIdx) {
            memmove(&_rowData[fromRow], &_rowData[fromRow + 1],
                    (size_t)(insertIdx - fromRow) * sizeof(XLRowEntry));
        } else if (fromRow > insertIdx) {
            memmove(&_rowData[insertIdx + 1], &_rowData[insertIdx],
                    (size_t)(fromRow - insertIdx) * sizeof(XLRowEntry));
        }
        _rowData[insertIdx] = moved;
    }

    [_rowHeadingsView reloadData];
    [_effectsGridView reloadData];
}

- (void)rowHeadings:(XLRowHeadingsView *)view didChangeVerticalScrollOffset:(CGFloat)offsetY {
    // Use scroll coordinator for synchronized vertical scroll
    [_scrollCoordinator viewDidScrollVertically:offsetY fromView:view];
}

#pragma mark - Row Headings Layer Management

- (NSString *)modelNameForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return nil;

    // If this is a layer sub-row, walk backwards to find the parent element row
    if (_rowData[row].isLayerRow) {
        NSInteger parentElementIndex = _rowData[row].elementIndex;
        for (NSInteger i = row - 1; i >= 0; i--) {
            if (!_rowData[i].isLayerRow && _rowData[i].elementIndex == parentElementIndex) {
                return [NSString stringWithUTF8String:_rowData[i].name];
            }
        }
        return nil;
    }

    return [NSString stringWithUTF8String:_rowData[row].name];
}

- (NSInteger)layerIndexForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return 0;

    if (_rowData[row].isLayerRow) {
        return _rowData[row].layerIndex;
    }

    // Main element row defaults to layer 0
    return 0;
}

- (void)rowHeadings:(XLRowHeadingsView *)view insertLayerAboveRow:(NSInteger)row {
    if (!_engineBridge || !_usingRealData) return;

    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;

    NSInteger layerIndex = [self layerIndexForRow:row];
    NSInteger result = [_engineBridge insertLayer:modelName atIndex:layerIndex];
    if (result >= 0) {
        [self reloadSequenceData];
    }
}

- (void)rowHeadings:(XLRowHeadingsView *)view insertLayerBelowRow:(NSInteger)row {
    if (!_engineBridge || !_usingRealData) return;

    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;

    NSInteger layerIndex = [self layerIndexForRow:row];
    NSInteger layerCount = [_engineBridge getLayerCount:modelName];

    if (layerIndex < layerCount - 1) {
        NSInteger result = [_engineBridge insertLayer:modelName atIndex:layerIndex + 1];
        if (result >= 0) {
            [self reloadSequenceData];
        }
    } else {
        NSInteger result = [_engineBridge addLayer:modelName];
        if (result >= 0) {
            [self reloadSequenceData];
        }
    }
}

- (void)rowHeadings:(XLRowHeadingsView *)view insertMultipleLayersBelowRow:(NSInteger)row count:(NSInteger)count {
    if (!_engineBridge || !_usingRealData || count <= 0) return;

    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;

    NSInteger layerIndex = [self layerIndexForRow:row];
    NSInteger layerCount = [_engineBridge getLayerCount:modelName];

    for (NSInteger i = 0; i < count; i++) {
        if (layerIndex < layerCount - 1) {
            [_engineBridge insertLayer:modelName atIndex:layerIndex + 1];
        } else {
            [_engineBridge addLayer:modelName];
        }
    }

    [self reloadSequenceData];
}

- (void)rowHeadings:(XLRowHeadingsView *)view deleteLayerAtRow:(NSInteger)row {
    if (!_engineBridge || !_usingRealData) return;

    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;

    NSInteger layerCount = [_engineBridge getLayerCount:modelName];
    if (layerCount <= 1) return;

    NSInteger layerIndex = [self layerIndexForRow:row];

    // Check if layer has effects and confirm deletion
    NSArray *effects = [_engineBridge getEffectsForLayer:modelName layer:layerIndex];
    if (effects.count > 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Confirm Layer Deletion";
        alert.informativeText = [NSString stringWithFormat:
            @"Layer contains %ld effect(s). Are you sure you want to delete Layer %ld of '%@'?",
            (long)effects.count, (long)(layerIndex + 1), modelName];
        [alert addButtonWithTitle:@"Delete"];
        [alert addButtonWithTitle:@"Cancel"];
        alert.alertStyle = NSAlertStyleWarning;

        if ([alert runModal] != NSAlertFirstButtonReturn) {
            return;
        }
    }

    BOOL success = [_engineBridge removeLayer:modelName layer:layerIndex];
    if (success) {
        [self reloadSequenceData];
    }
}

- (void)rowHeadings:(XLRowHeadingsView *)view deleteMultipleLayersAtRow:(NSInteger)row {
    if (!_engineBridge || !_usingRealData) return;

    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;

    NSInteger layerIndex = [self layerIndexForRow:row];
    NSInteger layerCount = [_engineBridge getLayerCount:modelName];
    if (layerCount <= 1) return;

    NSInteger maxDeletable = layerCount - layerIndex;

    // Ask how many layers to delete
    NSAlert *countAlert = [[NSAlert alloc] init];
    countAlert.messageText = @"Delete Multiple Layers";
    countAlert.informativeText = [NSString stringWithFormat:
        @"Enter number of layers to delete (max %ld):", (long)maxDeletable];
    [countAlert addButtonWithTitle:@"Delete"];
    [countAlert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    input.stringValue = [NSString stringWithFormat:@"%ld", (long)maxDeletable];
    countAlert.accessoryView = input;
    [countAlert.window makeFirstResponder:input];

    if ([countAlert runModal] != NSAlertFirstButtonReturn) return;

    NSInteger numToDelete = input.integerValue;
    if (numToDelete <= 0 || numToDelete > maxDeletable) return;

    // Check if any layers contain effects
    BOOL containsEffects = NO;
    for (NSInteger i = layerIndex; i < layerIndex + numToDelete; i++) {
        NSArray *effects = [_engineBridge getEffectsForLayer:modelName layer:i];
        if (effects.count > 0) {
            containsEffects = YES;
            break;
        }
    }

    if (containsEffects) {
        NSAlert *confirmAlert = [[NSAlert alloc] init];
        confirmAlert.messageText = @"Confirm Layer Deletion";
        confirmAlert.informativeText = @"One or more layers contain effects. Delete?";
        [confirmAlert addButtonWithTitle:@"Delete"];
        [confirmAlert addButtonWithTitle:@"Cancel"];
        confirmAlert.alertStyle = NSAlertStyleWarning;

        if ([confirmAlert runModal] != NSAlertFirstButtonReturn) return;
    }

    // Delete layers from bottom to top to preserve indices
    for (NSInteger i = layerIndex + numToDelete - 1; i >= layerIndex; i--) {
        [_engineBridge removeLayer:modelName layer:i];
    }

    // If we deleted layer 0, add a new layer so the model always has at least one
    if (layerIndex == 0) {
        NSInteger remaining = [_engineBridge getLayerCount:modelName];
        if (remaining == 0) {
            [_engineBridge addLayer:modelName];
        }
    }

    [self reloadSequenceData];
}

- (void)rowHeadings:(XLRowHeadingsView *)view deleteUnusedLayersAtRow:(NSInteger)row {
    if (!_engineBridge || !_usingRealData) return;

    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;

    NSInteger layerCount = [_engineBridge getLayerCount:modelName];
    BOOL deleted = NO;

    // Delete from top to bottom, skipping layers with effects and keeping at least one layer
    for (NSInteger i = layerCount - 1; i >= 0; i--) {
        NSInteger currentCount = [_engineBridge getLayerCount:modelName];
        if (currentCount <= 1) break;

        NSArray *effects = [_engineBridge getEffectsForLayer:modelName layer:i];
        if (effects.count == 0) {
            [_engineBridge removeLayer:modelName layer:i];
            deleted = YES;
        }
    }

    if (deleted) {
        [self reloadSequenceData];
    }
}

- (void)rowHeadings:(XLRowHeadingsView *)view editLayerNameAtRow:(NSInteger)row {
    if (!_engineBridge || !_usingRealData) return;

    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;

    NSInteger layerIndex = [self layerIndexForRow:row];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Layer Name";
    alert.informativeText = @"Enter a new name for this layer:";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
    // Pre-fill with current layer name if it's a named layer row
    if (_rowData[row].isLayerRow) {
        NSString *currentName = [NSString stringWithUTF8String:_rowData[row].name];
        // Strip leading spaces and brackets from display name like "   [Layer 2]"
        currentName = [currentName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([currentName hasPrefix:@"["] && [currentName hasSuffix:@"]"]) {
            currentName = @"";  // Default layer name, start fresh
        }
        input.stringValue = currentName;
    }
    alert.accessoryView = input;
    [alert.window makeFirstResponder:input];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *newName = input.stringValue;
        // TODO: Set layer name via engine bridge when setLayerName: is available
        NSLog(@"XLSequencerViewController: Set layer name for '%@' layer %ld to '%@'",
              modelName, (long)layerIndex, newName);
    }
}

- (void)rowHeadingsCollapseAllModels:(XLRowHeadingsView *)view {
    // Collapse all expanded model rows
    BOOL changed = NO;
    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (!_rowData[i].isLayerRow && _rowData[i].expanded) {
            _rowData[i].expanded = NO;
            changed = YES;
        }
    }

    if (changed) {
        // Remove all layer sub-rows
        NSUInteger writeIdx = 0;
        for (NSUInteger readIdx = 0; readIdx < _rowCount; readIdx++) {
            if (!_rowData[readIdx].isLayerRow) {
                if (writeIdx != readIdx) {
                    _rowData[writeIdx] = _rowData[readIdx];
                }
                writeIdx++;
            }
        }
        _rowCount = writeIdx;

        [_rowHeadingsView reloadData];
        [_effectsGridView reloadData];
    }
}

- (void)rowHeadingsCollapseAllLayers:(XLRowHeadingsView *)view {
    // Same as collapse all models - layers are model sub-rows
    [self rowHeadingsCollapseAllModels:view];
}

- (void)toggleFolderAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return;

    XLRowEntry *folderRow = &_rowData[row];
    if (!folderRow->isFolder) return;

    NSString *folderName = [NSString stringWithUTF8String:folderRow->folderName];
    BOOL wasCollapsed = folderRow->folderCollapsed;

    if (wasCollapsed) {
        // EXPANDING: Insert child rows from engine data
        folderRow->folderCollapsed = NO;
        folderRow->expanded = YES;
        [self.engineBridge setTrackFolderCollapsed:folderName collapsed:NO];

        // Get all elements from the engine and find those in this folder
        NSArray<NSDictionary *> *allElements = [self.engineBridge getSequenceElements];
        NSMutableArray<NSDictionary *> *folderElements = [NSMutableArray array];
        for (NSDictionary *elem in allElements) {
            NSString *ef = elem[@"folder"];
            if ([ef isEqualToString:folderName]) {
                [folderElements addObject:elem];
            }
        }

        if (folderElements.count == 0) return;

        // Count total rows to insert (element + expanded layers)
        NSUInteger rowsToInsert = folderElements.count;

        // Ensure capacity
        NSUInteger newRowCount = _rowCount + rowsToInsert;
        if (newRowCount > _rowCapacity) {
            _rowCapacity = newRowCount + 32;
            _rowData = (XLRowEntry *)realloc(_rowData, _rowCapacity * sizeof(XLRowEntry));
            folderRow = &_rowData[row]; // pointer may have moved
        }

        // Shift rows down
        NSInteger insertPos = row + 1;
        if (insertPos < (NSInteger)_rowCount) {
            memmove(&_rowData[insertPos + rowsToInsert], &_rowData[insertPos],
                    (_rowCount - (NSUInteger)insertPos) * sizeof(XLRowEntry));
        }

        // Insert child rows
        for (NSUInteger ci = 0; ci < folderElements.count; ci++) {
            NSDictionary *elem = folderElements[ci];
            XLRowEntry *childRow = &_rowData[insertPos + ci];
            memset(childRow, 0, sizeof(XLRowEntry));

            NSString *name = elem[@"name"];
            strncpy(childRow->name, [name UTF8String], sizeof(childRow->name) - 1);
            childRow->name[sizeof(childRow->name) - 1] = '\0';
            strncpy(childRow->folderName, [folderName UTF8String], sizeof(childRow->folderName) - 1);
            childRow->folderName[sizeof(childRow->folderName) - 1] = '\0';

            BOOL isGroup = [elem[@"isGroup"] boolValue];
            NSString *typeStr = elem[@"type"];
            if (isGroup || [typeStr isEqualToString:@"group"]) {
                childRow->type = XLElementTypeModelGroup;
            } else {
                childRow->type = XLElementTypeModel;
            }

            childRow->effectLayerCount = [elem[@"effectLayerCount"] integerValue];
            childRow->elementIndex = [elem[@"index"] integerValue];
            childRow->indent = 1;
            childRow->layerIndex = -1;
            childRow->isLayerRow = NO;
            childRow->expandable = (childRow->effectLayerCount > 1);
            childRow->expanded = NO;
        }

        _rowCount = newRowCount;
    } else {
        // COLLAPSING: Remove all child rows (and their layer sub-rows)
        folderRow->folderCollapsed = YES;
        folderRow->expanded = NO;
        [self.engineBridge setTrackFolderCollapsed:folderName collapsed:YES];

        const char *fn = [folderName UTF8String];
        NSInteger rowsToRemove = 0;
        for (NSInteger i = row + 1; i < (NSInteger)_rowCount; i++) {
            // Child rows and their layer sub-rows share the same folderName
            if (strcmp(_rowData[i].folderName, fn) == 0 && !_rowData[i].isFolder) {
                rowsToRemove++;
            } else {
                break;
            }
        }

        if (rowsToRemove > 0) {
            NSInteger removeStart = row + 1;
            NSInteger removeEnd = removeStart + rowsToRemove;
            if (removeEnd < (NSInteger)_rowCount) {
                memmove(&_rowData[removeStart], &_rowData[removeEnd],
                        (_rowCount - (NSUInteger)removeEnd) * sizeof(XLRowEntry));
            }
            _rowCount -= (NSUInteger)rowsToRemove;
        }
    }

    // Update max scroll and reload
    if (_scrollCoordinator) {
        CGFloat viewHeight = NSHeight(_effectsGridView.bounds);
        CGFloat maxScrollY = _rowCount * _effectsGridView.rowHeight - viewHeight;
        _scrollCoordinator.maxVerticalScrollOffset = fmax(0, maxScrollY);
    }

    [_rowHeadingsView reloadData];
    [_effectsGridView reloadData];
}

- (void)rowHeadingsCollapseAllFolders:(XLRowHeadingsView *)view {
    BOOL changed = NO;
    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (_rowData[i].isFolder && !_rowData[i].folderCollapsed) {
            // Collapse by toggling
            [self toggleFolderAtRow:(NSInteger)i];
            changed = YES;
            // After collapsing, children are removed, continue from same index
            // since the next row is now different
            i--; // Re-check this index since toggleFolderAtRow shifts rows
            // Actually we just need to continue scanning from current position
            i++; // Undo the decrement, the folder row itself stays
        }
    }
    if (changed) {
        [_rowHeadingsView reloadData];
        [_effectsGridView reloadData];
    }
}

- (void)rowHeadingsExpandAllFolders:(XLRowHeadingsView *)view {
    BOOL changed = NO;
    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (_rowData[i].isFolder && _rowData[i].folderCollapsed) {
            [self toggleFolderAtRow:(NSInteger)i];
            changed = YES;
        }
    }
    if (changed) {
        [_rowHeadingsView reloadData];
        [_effectsGridView reloadData];
    }
}

#pragma mark - Track Folder Operations

- (void)createTrackFolderFromSelection {
    // Collect selected model row names (non-timing, non-folder, non-layer rows)
    NSMutableArray<NSString *> *selectedNames = [NSMutableArray array];
    NSIndexSet *selectedRows = _rowHeadingsView.selectedRows;

    [selectedRows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if (idx >= self->_rowCount) return;
        XLRowEntry *row = &self->_rowData[idx];
        if (!row->isFolder && !row->isLayerRow && row->type != XLElementTypeTiming) {
            [selectedNames addObject:[NSString stringWithUTF8String:row->name]];
        }
    }];

    if (selectedNames.count == 0) return;

    // Ask for folder name
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Create Track Folder";
    alert.informativeText = @"Enter a name for the new track folder:";
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    input.stringValue = @"New Folder";
    alert.accessoryView = input;

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *folderName = input.stringValue;
    if (folderName.length == 0) return;

    [self.engineBridge createTrackFolder:folderName];
    for (NSString *name in selectedNames) {
        [self.engineBridge setElement:name folder:folderName];
    }

    [self loadRealSequenceData];
    [_rowHeadingsView reloadData];
    [_effectsGridView reloadData];
}

- (void)moveElementAtRow:(NSInteger)row toFolder:(NSString *)folderName {
    if (row < 0 || row >= (NSInteger)_rowCount) return;

    // If this row is part of a multi-selection, move all selected eligible rows
    NSIndexSet *selectedRows = _rowHeadingsView.selectedRows;
    if (selectedRows.count > 1 && [selectedRows containsIndex:(NSUInteger)row]) {
        [selectedRows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            if (idx >= self->_rowCount) return;
            XLRowEntry *entry = &self->_rowData[idx];
            if (entry->isFolder || entry->isLayerRow || entry->type == XLElementTypeTiming) return;
            NSString *elemName = [NSString stringWithUTF8String:entry->name];
            [self.engineBridge setElement:elemName folder:folderName];
        }];
    } else {
        XLRowEntry *entry = &_rowData[row];
        if (entry->isFolder || entry->isLayerRow || entry->type == XLElementTypeTiming) return;
        NSString *elemName = [NSString stringWithUTF8String:entry->name];
        [self.engineBridge setElement:elemName folder:folderName];
    }

    [self loadRealSequenceData];
    [_rowHeadingsView reloadData];
    [_effectsGridView reloadData];
}

- (void)removeElementFromFolderAtRow:(NSInteger)row {
    [self moveElementAtRow:row toFolder:nil];
}

- (void)renameFolderAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount) return;
    XLRowEntry *entry = &_rowData[row];
    if (!entry->isFolder) return;

    NSString *oldName = [NSString stringWithUTF8String:entry->folderName];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename Track Folder";
    alert.informativeText = @"Enter the new name:";
    [alert addButtonWithTitle:@"Rename"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    input.stringValue = oldName;
    alert.accessoryView = input;

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *newName = input.stringValue;
    if (newName.length == 0 || [newName isEqualToString:oldName]) return;

    [self.engineBridge renameTrackFolder:oldName toName:newName];

    [self loadRealSequenceData];
    [_rowHeadingsView reloadData];
    [_effectsGridView reloadData];
}

- (void)deleteFolderAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount) return;
    XLRowEntry *entry = &_rowData[row];
    if (!entry->isFolder) return;

    NSString *folderName = [NSString stringWithUTF8String:entry->folderName];

    [self.engineBridge deleteTrackFolder:folderName];

    [self loadRealSequenceData];
    [_rowHeadingsView reloadData];
    [_effectsGridView reloadData];
}

#pragma mark - Track Folder Delegate Methods

- (void)rowHeadings:(XLRowHeadingsView *)view createFolderFromRow:(NSInteger)row {
    [self createTrackFolderFromSelection];
}

- (void)rowHeadings:(XLRowHeadingsView *)view moveRowToFolder:(NSInteger)row folderName:(NSString *)folderName {
    [self moveElementAtRow:row toFolder:folderName];
}

- (void)rowHeadings:(XLRowHeadingsView *)view removeFromFolderAtRow:(NSInteger)row {
    [self removeElementFromFolderAtRow:row];
}

- (void)rowHeadings:(XLRowHeadingsView *)view renameFolderAtRow:(NSInteger)row {
    [self renameFolderAtRow:row];
}

- (void)rowHeadings:(XLRowHeadingsView *)view deleteFolderAtRow:(NSInteger)row {
    [self deleteFolderAtRow:row];
}

#pragma mark - Model Operations (Row Heading Context Menu)

- (void)rowHeadings:(XLRowHeadingsView *)view toggleStrandsAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return;

    // Toggle expand/collapse on this row (shows/hides strands/nodes)
    if ([self respondsToSelector:@selector(rowHeadings:didToggleExpandAtRow:)]) {
        [self rowHeadings:view didToggleExpandAtRow:row];
    }
}

- (void)rowHeadings:(XLRowHeadingsView *)view showAllEffectsAtRow:(NSInteger)row {
    if (!_engineBridge || !_usingRealData) return;

    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;

    NSInteger layerCount = [_engineBridge getLayerCount:modelName];

    // Select all effects across all layers for this model
    for (NSInteger layer = 0; layer < layerCount; layer++) {
        NSArray *effects = [_engineBridge getEffectsForLayer:modelName layer:layer];
        for (NSDictionary *effect in effects) {
            NSInteger effectId = [effect[@"id"] integerValue];
            [_engineBridge selectEffect:effectId];
        }
    }

    [_effectsGridView reloadData];
}

- (void)rowHeadings:(XLRowHeadingsView *)view toggleRenderDisabledAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return;
    if (!_engineBridge || !_usingRealData) return;

    NSInteger elemIdx = _rowData[row].elementIndex;
    NSDictionary *elemInfo = [_engineBridge getSequenceElementAtIndex:elemIdx];
    if (!elemInfo) return;

    BOOL currentlyDisabled = [elemInfo[@"isRenderDisabled"] boolValue];
    // Toggle render state - use the element property update pattern
    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;

    // For now, log the toggle and update row data to reflect intended state.
    // Full implementation requires engine bridge support for setting element render state.
    NSLog(@"XLSequencerViewController: Toggle render %@ for '%@'",
          currentlyDisabled ? @"enabled" : @"disabled", modelName);

    [_effectsGridView reloadData];
}

- (void)rowHeadingsEnableRenderOnAllModels:(XLRowHeadingsView *)view {
    if (!_engineBridge || !_usingRealData) return;

    NSLog(@"XLSequencerViewController: Enable render on all models");
    [_effectsGridView reloadData];
}

- (BOOL)rowHeadingsIsRenderDisabledAtRow:(XLRowHeadingsView *)view row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return NO;
    if (!_engineBridge || !_usingRealData) return NO;

    NSInteger elemIdx = _rowData[row].elementIndex;
    NSDictionary *elemInfo = [_engineBridge getSequenceElementAtIndex:elemIdx];
    if (!elemInfo) return NO;

    return [elemInfo[@"isRenderDisabled"] boolValue];
}

- (BOOL)rowHeadingsHasAnyRenderDisabled:(XLRowHeadingsView *)view {
    if (!_engineBridge || !_usingRealData) return NO;

    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (_rowData[i].isLayerRow) continue;
        if (_rowData[i].type == XLElementTypeTiming) continue;

        NSInteger elemIdx = _rowData[i].elementIndex;
        NSDictionary *elemInfo = [_engineBridge getSequenceElementAtIndex:elemIdx];
        if (elemInfo && [elemInfo[@"isRenderDisabled"] boolValue]) {
            return YES;
        }
    }
    return NO;
}

- (void)rowHeadings:(XLRowHeadingsView *)view playModelAtRow:(NSInteger)row {
    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;
    NSLog(@"XLSequencerViewController: Play model '%@' (placeholder)", modelName);
}

- (void)rowHeadings:(XLRowHeadingsView *)view exportModelAtRow:(NSInteger)row {
    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;
    NSLog(@"XLSequencerViewController: Export model '%@' (placeholder)", modelName);
}

- (void)rowHeadings:(XLRowHeadingsView *)view selectAllModelEffectsAtRow:(NSInteger)row {
    if (!_engineBridge || !_usingRealData) return;

    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;

    [_engineBridge deselectAllEffects];

    NSInteger layerCount = [_engineBridge getLayerCount:modelName];
    for (NSInteger layer = 0; layer < layerCount; layer++) {
        NSArray *effects = [_engineBridge getEffectsForLayer:modelName layer:layer];
        for (NSDictionary *effect in effects) {
            NSInteger effectId = [effect[@"id"] integerValue];
            [_engineBridge selectEffect:effectId];
        }
    }

    [_effectsGridView reloadData];
}

- (void)rowHeadings:(XLRowHeadingsView *)view copyModelEffectsAtRow:(NSInteger)row {
    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;
    NSLog(@"XLSequencerViewController: Copy effects for model '%@' (placeholder)", modelName);
}

- (void)rowHeadings:(XLRowHeadingsView *)view cutModelEffectsAtRow:(NSInteger)row {
    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;
    NSLog(@"XLSequencerViewController: Cut effects for model '%@' (placeholder)", modelName);
}

- (void)rowHeadings:(XLRowHeadingsView *)view pasteModelEffectsAtRow:(NSInteger)row {
    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;
    NSLog(@"XLSequencerViewController: Paste effects for model '%@' (placeholder)", modelName);
}

- (void)rowHeadings:(XLRowHeadingsView *)view deleteModelEffectsAtRow:(NSInteger)row {
    if (!_engineBridge || !_usingRealData) return;

    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;

    NSInteger layerCount = [_engineBridge getLayerCount:modelName];
    NSInteger totalEffects = 0;
    for (NSInteger layer = 0; layer < layerCount; layer++) {
        NSArray *effects = [_engineBridge getEffectsForLayer:modelName layer:layer];
        totalEffects += effects.count;
    }

    if (totalEffects == 0) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Delete Model Effects";
    alert.informativeText = [NSString stringWithFormat:
        @"Are you sure you want to delete all %ld effects from '%@'?",
        (long)totalEffects, modelName];
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    for (NSInteger layer = 0; layer < layerCount; layer++) {
        NSArray *effects = [_engineBridge getEffectsForLayer:modelName layer:layer];
        for (NSDictionary *effect in effects) {
            NSInteger effectId = [effect[@"id"] integerValue];
            [_engineBridge deleteEffect:effectId];
        }
    }

    [self reloadSequenceData];
}

- (void)rowHeadings:(XLRowHeadingsView *)view copyModelEffectsIncludingSubmodelsAtRow:(NSInteger)row {
    NSString *modelName = [self modelNameForRow:row];
    if (!modelName) return;
    NSLog(@"XLSequencerViewController: Copy effects incl submodels for '%@' (placeholder)", modelName);
}

#pragma mark - Timing Track Operations (Row Heading Context Menu)

- (void)rowHeadingsAddTimingTrack:(XLRowHeadingsView *)view {
    [self addTimingTrack:nil];
}

- (void)rowHeadings:(XLRowHeadingsView *)view renameTimingTrackAtRow:(NSInteger)row {
    if (!_engineBridge || !_usingRealData) return;
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return;

    NSString *oldName = [NSString stringWithUTF8String:_rowData[row].name];
    if (!oldName || oldName.length == 0) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename Timing Track";
    alert.informativeText = @"Enter the new name:";
    [alert addButtonWithTitle:@"Rename"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 250, 24)];
    input.stringValue = oldName;
    alert.accessoryView = input;
    [alert.window makeFirstResponder:input];

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *newName = [input.stringValue stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (newName.length == 0 || [newName isEqualToString:oldName]) return;

    BOOL success = [_engineBridge renameTimingTrack:oldName toName:newName];
    if (success) {
        [self reloadSequenceData];
    } else {
        NSAlert *errorAlert = [[NSAlert alloc] init];
        errorAlert.messageText = @"Rename Failed";
        errorAlert.informativeText = [NSString stringWithFormat:
            @"Could not rename timing track '%@' to '%@'. The name may already be in use.",
            oldName, newName];
        [errorAlert addButtonWithTitle:@"OK"];
        [errorAlert runModal];
    }
}

- (void)rowHeadings:(XLRowHeadingsView *)view deleteTimingTrackAtRow:(NSInteger)row {
    if (!_engineBridge || !_usingRealData) return;
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return;

    NSString *trackName = [NSString stringWithUTF8String:_rowData[row].name];
    if (!trackName || trackName.length == 0) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Delete Timing Track";
    alert.informativeText = [NSString stringWithFormat:
        @"Are you sure you want to delete the timing track '%@'?\n\nThis action cannot be undone.",
        trackName];
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    BOOL success = [_engineBridge deleteTimingTrack:trackName];
    if (success) {
        [self reloadSequenceData];
    }
}

- (void)rowHeadings:(XLRowHeadingsView *)view importTimingTrackAtRow:(NSInteger)row {
    NSLog(@"XLSequencerViewController: Import timing track (placeholder)");
    [self importTiming:nil];
}

- (void)rowHeadings:(XLRowHeadingsView *)view exportTimingTrackAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return;
    NSString *trackName = [NSString stringWithUTF8String:_rowData[row].name];
    NSLog(@"XLSequencerViewController: Export timing track '%@' (placeholder)", trackName);
}

- (void)rowHeadingsHideAllTimingTracks:(XLRowHeadingsView *)view {
    BOOL changed = NO;
    NSUInteger writeIdx = 0;

    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (_rowData[i].type == XLElementTypeTiming) {
            changed = YES;
            continue;
        }
        if (writeIdx != i) {
            _rowData[writeIdx] = _rowData[i];
        }
        writeIdx++;
    }

    if (changed) {
        _rowCount = writeIdx;
        [_rowHeadingsView reloadData];
        [_effectsGridView reloadData];
    }
}

- (void)rowHeadingsShowAllTimingTracks:(XLRowHeadingsView *)view {
    [self reloadSequenceData];
}

- (void)rowHeadings:(XLRowHeadingsView *)view importNotesAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return;
    NSString *trackName = [NSString stringWithUTF8String:_rowData[row].name];
    NSLog(@"XLSequencerViewController: Import notes for track '%@' (placeholder)", trackName);
}

- (void)rowHeadings:(XLRowHeadingsView *)view importLyricsAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return;
    NSString *trackName = [NSString stringWithUTF8String:_rowData[row].name];
    NSLog(@"XLSequencerViewController: Import lyrics for track '%@' (placeholder)", trackName);
}

- (void)rowHeadings:(XLRowHeadingsView *)view breakdownPhrasesAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData || !_engineBridge) return;
    XLRowEntry *rowEntry = &_rowData[row];
    if (rowEntry->type != XLElementTypeTiming) return;

    NSString *trackName = [NSString stringWithUTF8String:rowEntry->name];

    // Get all phrase marks (layer 0) and break them down into words (layer 1)
    NSArray<NSDictionary *> *phrases = [_engineBridge getTimingMarks:trackName layer:0];
    for (NSDictionary *phrase in phrases) {
        NSInteger phraseId = [phrase[@"id"] integerValue];
        [self breakdownPhraseWithId:phraseId trackName:trackName];
    }

    [self reloadSequenceData];
    [_effectsGridView reloadData];
    NSLog(@"XLSequencerViewController: Breakdown all phrases for track '%@' completed", trackName);
}

- (void)rowHeadings:(XLRowHeadingsView *)view breakdownWordsAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData || !_engineBridge) return;
    XLRowEntry *rowEntry = &_rowData[row];
    if (rowEntry->type != XLElementTypeTiming) return;

    NSString *trackName = [NSString stringWithUTF8String:rowEntry->name];

    // Get all word marks (layer 1) and break them down into phonemes (layer 2)
    NSArray<NSDictionary *> *words = [_engineBridge getTimingMarks:trackName layer:1];
    for (NSDictionary *word in words) {
        NSInteger wordId = [word[@"id"] integerValue];
        [self breakdownWordWithId:wordId trackName:trackName];
    }

    [self reloadSequenceData];
    [_effectsGridView reloadData];
    NSLog(@"XLSequencerViewController: Breakdown all words for track '%@' completed", trackName);
}

#pragma mark - Track Height Slider

- (void)trackHeightSliderChanged:(NSSlider *)sender {
    // Cmd+click resets to default row height
    NSEvent *currentEvent = [NSApp currentEvent];
    if (currentEvent && (currentEvent.modifierFlags & NSEventModifierFlagCommand)) {
        CGFloat defaultHeight = 22.0;
        sender.doubleValue = defaultHeight;
    }

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

    // Set pinned timing row count and reload views
    _effectsGridView.pinnedTimingRowCount = _timingRowCount;
    _rowHeadingsView.pinnedTimingRowCount = _timingRowCount;
    [_effectsGridView reloadData];
    [_rowHeadingsView reloadData];
}

- (void)refreshViewSelector {
    // Re-populate the view dropdown (e.g., when sequence changes)
    [self populateViewSelector];
}

#pragma mark - Timing Track Selector

- (void)populateTimingTrackSelector {
    // Temporarily disable action to prevent triggering timingTrackChanged:
    SEL originalAction = _timingTrackPopup.action;
    _timingTrackPopup.action = nil;

    [_timingTrackPopup removeAllItems];

    if (!self.engineBridge || ![self.engineBridge isSequenceLoaded]) {
        [_timingTrackPopup addItemWithTitle:@"(none)"];
        _timingTrackPopup.action = originalAction;
        return;
    }

    // Get all timing tracks from the engine bridge (returns dictionaries with "name" key)
    NSArray<NSDictionary *> *timingTracks = [self.engineBridge getTimingTracks];
    if (timingTracks.count == 0) {
        [_timingTrackPopup addItemWithTitle:@"(none)"];
    } else {
        [_timingTrackPopup addItemWithTitle:@"Off"];
        for (NSDictionary *track in timingTracks) {
            NSString *trackName = track[@"name"];
            if (trackName) {
                [_timingTrackPopup addItemWithTitle:trackName];
            }
        }
    }

    // Select the active timing track, or "Off" if none active
    NSString *activeTrack = [self.engineBridge getActiveTimingTrackName];
    if (activeTrack && activeTrack.length > 0) {
        [_timingTrackPopup selectItemWithTitle:activeTrack];
    } else {
        [_timingTrackPopup selectItemWithTitle:@"Off"];
    }

    // Re-enable action
    _timingTrackPopup.action = originalAction;
}

- (void)updateActiveTimingColorIndex {
    NSString *activeTrack = [self.engineBridge getActiveTimingTrackName];
    if (!activeTrack || activeTrack.length == 0) {
        _effectsGridView.activeTimingColorIndex = -1;
        NSLog(@"updateActiveTimingColorIndex: no active track, set to -1");
        return;
    }
    // Find the timing track row that matches the active track name
    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (_rowData[i].type == XLElementTypeTiming && !_rowData[i].isLayerRow) {
            NSLog(@"updateActiveTimingColorIndex: checking row %lu '%s' colorIndex=%ld vs active='%@'",
                  (unsigned long)i, _rowData[i].name, (long)_rowData[i].timingColorIndex, activeTrack);
            if (strcmp(_rowData[i].name, [activeTrack UTF8String]) == 0) {
                _effectsGridView.activeTimingColorIndex = _rowData[i].timingColorIndex;
                NSLog(@"updateActiveTimingColorIndex: matched '%@' → colorIndex=%ld",
                      activeTrack, (long)_rowData[i].timingColorIndex);
                return;
            }
        }
    }
    NSLog(@"updateActiveTimingColorIndex: no match found for '%@', set to -1", activeTrack);
    _effectsGridView.activeTimingColorIndex = -1;
}

- (void)timingTrackChanged:(NSPopUpButton *)sender {
    NSString *selectedTrackName = sender.titleOfSelectedItem;
    if (!selectedTrackName || [selectedTrackName isEqualToString:@"(none)"]) {
        return;
    }

    // "Off" deactivates all timing tracks
    if ([selectedTrackName isEqualToString:@"Off"]) {
        [self.engineBridge deactivateAllTimingTracks];
        _effectsGridView.activeTimingColorIndex = -1;
        [self reloadTimingMarksForRuler];
        [_effectsGridView reloadData];
        return;
    }

    // Check if we're already on this track
    NSString *currentTrackName = [self.engineBridge getActiveTimingTrackName];
    if ([selectedTrackName isEqualToString:currentTrackName]) {
        return;
    }

    NSLog(@"XLSequencerViewController: Switching to timing track: %@", selectedTrackName);

    // Switch to the selected timing track via engine bridge
    BOOL success = [self.engineBridge setActiveTimingTrack:selectedTrackName];
    if (success) {
        [self updateActiveTimingColorIndex];
        // Reload timing marks for the ruler
        [self reloadTimingMarksForRuler];
        // Reload effects grid to update snap points
        [_effectsGridView reloadData];
    } else {
        NSLog(@"XLSequencerViewController: Failed to switch to timing track: %@", selectedTrackName);
        // Revert the dropdown selection
        if (currentTrackName) {
            [_timingTrackPopup selectItemWithTitle:currentTrackName];
        }
    }
}

- (void)refreshTimingTrackSelector {
    // Re-populate the timing track dropdown (e.g., when sequence changes or tracks added)
    [self populateTimingTrackSelector];
}

#pragma mark - Timing Track Actions

- (void)addTimingTrack:(id)sender {
    if (!self.engineBridge || ![self.engineBridge isSequenceLoaded]) {
        NSLog(@"XLSequencerViewController: Cannot add timing track - no sequence loaded");
        return;
    }

    // Get existing track names to prevent duplicates
    NSArray<NSDictionary *> *timingTracks = [self.engineBridge getTimingTracks];
    NSMutableArray<NSString *> *existingTrackNames = [NSMutableArray arrayWithCapacity:timingTracks.count];
    for (NSDictionary *track in timingTracks) {
        NSString *name = track[@"name"];
        if (name) {
            [existingTrackNames addObject:name];
        }
    }

    // Create and configure the dialog
    XLNewTimingDialog *dialog = [[XLNewTimingDialog alloc] init];
    dialog.existingTrackNames = existingTrackNames;

    // Show the dialog
    [dialog presentAsSheetForWindow:self.view.window completion:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            NSString *trackName = dialog.trackName;
            XLTimingInterval interval = dialog.selectedInterval;

            NSLog(@"XLSequencerViewController: Creating timing track '%@' with interval %ld",
                  trackName, (long)interval);

            // Get the timing name for this interval (nil for empty track)
            NSString *timingName = [XLNewTimingDialog timingNameForInterval:interval];

            // Create the timing track via engine bridge
            BOOL success = [self.engineBridge createTimingTrack:trackName timingType:timingName];
            if (success) {
                NSLog(@"XLSequencerViewController: Created timing track '%@'", trackName);

                // Set it as the active timing track
                [self.engineBridge setActiveTimingTrack:trackName];

                // Refresh the UI
                [self populateTimingTrackSelector];
                [self reloadTimingMarksForRuler];
                [self reloadSequenceData];
            } else {
                NSLog(@"XLSequencerViewController: Failed to create timing track '%@'", trackName);
            }
        }
    }];
}

- (void)importTiming:(id)sender {
    if (!self.engineBridge || ![self.engineBridge isSequenceLoaded]) {
        NSLog(@"XLSequencerViewController: Cannot import timing - no sequence loaded");
        return;
    }

    // Create and configure the import dialog
    XLTimingImportDialog *dialog = [[XLTimingImportDialog alloc] init];

    // Show the dialog
    [dialog presentAsSheetForWindow:self.view.window completion:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            XLTimingSource source = dialog.source;
            NSString *trackName = dialog.trackName;
            NSString *sourceFilePath = dialog.sourceFilePath;

            NSLog(@"XLSequencerViewController: Importing timing from source %ld as '%@'",
                  (long)source, trackName);

            // Handle different import sources
            switch (source) {
                case XLTimingSourceAudioAnalysis:
                case XLTimingSourceVAMP:
                    // Placeholder - audio analysis not yet implemented
                    NSLog(@"XLSequencerViewController: Audio analysis import not yet implemented");
                    break;

                case XLTimingSourceMIDI:
                    // Placeholder - MIDI import not yet implemented
                    NSLog(@"XLSequencerViewController: MIDI import not yet implemented");
                    break;

                case XLTimingSourceLyrics:
                    // Placeholder - lyrics import not yet implemented
                    NSLog(@"XLSequencerViewController: Lyrics import not yet implemented");
                    break;

                case XLTimingSourcePapagayo:
                    // Placeholder - Papagayo import not yet implemented
                    NSLog(@"XLSequencerViewController: Papagayo import not yet implemented");
                    break;

                case XLTimingSourceOtherSequence: {
                    // Import from another sequence
                    if (sourceFilePath) {
                        // For now, import all timing tracks from the source sequence
                        // A more complete implementation would let the user select which tracks
                        BOOL success = [self.engineBridge importTimingTrack:nil
                                                               fromSequence:sourceFilePath
                                                                asTrackName:trackName];
                        if (success) {
                            NSLog(@"XLSequencerViewController: Imported timing from '%@' as '%@'",
                                  sourceFilePath, trackName);
                            [self.engineBridge setActiveTimingTrack:trackName];
                            [self populateTimingTrackSelector];
                            [self reloadTimingMarksForRuler];
                            [self reloadSequenceData];
                        } else {
                            NSLog(@"XLSequencerViewController: Failed to import timing track");
                        }
                    }
                    break;
                }
            }
        }
    }];
}

- (void)generateTiming:(id)sender {
    // Generate timing from audio is similar to import, just pre-select audio analysis
    [self importTiming:sender];
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
    if (!key) {
        // No sequence loaded, zoom to fit as default
        [self zoomToFit:nil];
        return;
    }

    CGFloat savedZoom = [[NSUserDefaults standardUserDefaults] doubleForKey:key];
    if (savedZoom > 0) {
        // Apply the saved zoom level
        [_scrollCoordinator setZoomLevel:savedZoom];
        _transportBar.zoomLevel = savedZoom;
    } else {
        // No saved zoom for this sequence - default to zoom-to-fit
        [self zoomToFit:nil];
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

- (void)waveformView:(XLWaveformView *)view didSelectLoopRegionFromTimeMS:(CGFloat)startMS toTimeMS:(CGFloat)endMS {
    if (_playbackController) {
        _playbackController.loopRegionStartMS = (NSInteger)startMS;
        _playbackController.loopRegionEndMS = (NSInteger)endMS;
        _playbackController.loopEnabled = YES;
    }
}

- (void)waveformViewDidClearLoopRegion:(XLWaveformView *)view {
    if (_playbackController) {
        [_playbackController clearLoopRegion];
    }
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
    // The controller returns to the play origin and notifies via delegate,
    // so we don't need to manually reset positions here.
    if (_playbackController) {
        [_playbackController stop];
    }

    _timelineRuler.playing = NO;
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
    // Position is updated via didUpdatePositionMS: callback from the controller
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
    [_stemsContainerView setPlaybackPositionMS:(CGFloat)positionMS];
}

- (void)playbackController:(XLPlaybackController *)controller didRenderFrameAtMS:(NSInteger)timeMS {
    // Stop the indeterminate spinner when frame render completes
    _renderProgressIndicator.animating = NO;
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

#pragma mark - First Responder & Keyboard Handling

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    if (![_keyboardHandler handleKeyEvent:event inScope:XLKeyScopeSequence]) {
        [super keyDown:event];
    }
}

- (void)showFolderDidChange:(NSNotification *)notification {
    // Reload key bindings from the new show folder
    NSString *newPath = notification.userInfo[@"path"];
    if (newPath) {
        [_keyboardHandler setShowFolderPath:newPath];
    } else {
        // Try to get from engine bridge
        NSString *showFolder = [self.engineBridge getShowFolderPath];
        [_keyboardHandler setShowFolderPath:showFolder];
    }
}

- (void)keyBindingsDidChange:(NSNotification *)notification {
    [_keyboardHandler reloadKeyBindings];
}

- (void)handleZoomToSelection:(NSNotification *)notification {
    [_effectsGridView zoomToSelection];
}

- (void)handleApplyEffectFromCommandPalette:(NSNotification *)notification {
    NSString *effectName = notification.userInfo[@"effectName"];
    if (!effectName) return;
    [self createEffectOnSelectedCell:effectName settings:nil];
}

- (BOOL)createEffectOnSelectedCell:(NSString *)effectName settings:(NSString *)settings {
    if (!_effectsGridView.hasCellSelection) {
        NSLog(@"XLSequencerViewController: createEffectOnSelectedCell but no cell selected");
        return NO;
    }

    NSInteger row = _effectsGridView.cellSelectionRow;
    CGFloat startMS = _effectsGridView.cellSelectionStartMS;
    CGFloat endMS = _effectsGridView.cellSelectionEndMS;

    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) {
        return NO;
    }

    if (_rowData[row].type == XLElementTypeTiming) {
        return NO;
    }

    if (!_engineBridge || !_usingRealData) {
        return NO;
    }

    NSString *modelName = [NSString stringWithUTF8String:_rowData[row].name];
    NSInteger layer = _rowData[row].isLayerRow ? _rowData[row].layerIndex : 0;

    NSInteger effectId = [_engineBridge createEffect:modelName
                                               layer:layer
                                          effectType:effectName
                                         startTimeMS:(NSInteger)startMS
                                           endTimeMS:(NSInteger)endMS];

    if (effectId >= 0) {
        if (settings.length > 0) {
            [_engineBridge setEffectSettings:effectId settings:settings];
        }
        [_effectsGridView clearCellSelection];
        [self reloadSequenceData];
        NSLog(@"XLSequencerViewController: Created '%@' effect (id=%ld) at row %ld, %ld-%ld ms",
              effectName, (long)effectId, (long)row, (long)(NSInteger)startMS, (long)(NSInteger)endMS);
        return YES;
    }

    NSLog(@"XLSequencerViewController: FAILED to create '%@' effect", effectName);
    return NO;
}

#pragma mark - Multi-Cell Preset Paste

- (BOOL)applyPresetToSelectedCell:(NSDictionary *)presetData {
    if (!presetData || !_effectsGridView.hasCellSelection) return NO;
    if (!_engineBridge || !_usingRealData) return NO;

    NSString *effectType = presetData[@"effectType"];
    NSString *settings = presetData[@"settings"];
    NSString *palette = presetData[@"palette"];
    if (!effectType) return NO;

    NSInteger row = _effectsGridView.cellSelectionRow;
    CGFloat startMS = _effectsGridView.cellSelectionStartMS;
    CGFloat endMS = _effectsGridView.cellSelectionEndMS;

    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return NO;
    if (_rowData[row].type == XLElementTypeTiming) return NO;

    NSString *modelName = [NSString stringWithUTF8String:_rowData[row].name];
    NSInteger layer = _rowData[row].isLayerRow ? _rowData[row].layerIndex : 0;

    NSInteger effectId = [_engineBridge createEffect:modelName
                                               layer:layer
                                          effectType:effectType
                                         startTimeMS:(NSInteger)startMS
                                           endTimeMS:(NSInteger)endMS];
    if (effectId < 0) return NO;

    if (settings.length > 0) {
        [_engineBridge setEffectSettings:effectId settings:settings];
    }
    if (palette.length > 0) {
        [_engineBridge setEffectPalette:effectId palette:palette];
    }

    [_effectsGridView clearCellSelection];
    [self reloadSequenceData];
    return YES;
}

- (NSInteger)applyPresetToMultiCellRange:(NSDictionary *)presetData {
    if (!presetData || !_cellRangeSelected) return 0;
    if (!_engineBridge || !_usingRealData) return 0;

    NSString *effectType = presetData[@"effectType"];
    NSString *settings = presetData[@"settings"];
    NSString *palette = presetData[@"palette"];
    if (!effectType) return 0;

    NSInteger row1 = _rangeStartRow;
    NSInteger row2 = _rangeEndRow;
    if (row1 > row2) { NSInteger tmp = row1; row1 = row2; row2 = tmp; }

    CGFloat timeStart = _rangeStartTimeMS;
    CGFloat timeEnd = _rangeEndTimeMS;
    if (timeStart > timeEnd) { CGFloat tmp = timeStart; timeStart = timeEnd; timeEnd = tmp; }

    NSString *trackName = [self activeTimingTrackForOperation];
    NSInteger effectsCreated = 0;

    if (trackName && _pasteByCellMode) {
        NSArray<NSDictionary *> *marks = [_engineBridge getTimingMarks:trackName layer:0];
        if (!marks) return 0;

        marks = [marks sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [@([a[@"startTimeMS"] integerValue]) compare:@([b[@"startTimeMS"] integerValue])];
        }];

        for (NSDictionary *mark in marks) {
            NSInteger cellStart = [mark[@"startTimeMS"] integerValue];
            NSInteger cellEnd = [mark[@"endTimeMS"] integerValue];

            if (cellEnd <= (NSInteger)timeStart || cellStart >= (NSInteger)timeEnd) continue;

            for (NSInteger row = row1; row <= row2; row++) {
                if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) continue;
                if (_rowData[row].type == XLElementTypeTiming) continue;

                NSString *modelName = [NSString stringWithUTF8String:_rowData[row].name];
                NSInteger layer = _rowData[row].isLayerRow ? _rowData[row].layerIndex : 0;

                NSInteger effectId = [_engineBridge createEffect:modelName
                                                           layer:layer
                                                      effectType:effectType
                                                     startTimeMS:cellStart
                                                       endTimeMS:cellEnd];
                if (effectId >= 0) {
                    if (settings.length > 0) {
                        [_engineBridge setEffectSettings:effectId settings:settings];
                    }
                    if (palette.length > 0) {
                        [_engineBridge setEffectPalette:effectId palette:palette];
                    }
                    effectsCreated++;
                }
            }
        }
    } else {
        for (NSInteger row = row1; row <= row2; row++) {
            if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) continue;
            if (_rowData[row].type == XLElementTypeTiming) continue;

            NSString *modelName = [NSString stringWithUTF8String:_rowData[row].name];
            NSInteger layer = _rowData[row].isLayerRow ? _rowData[row].layerIndex : 0;

            NSInteger effectId = [_engineBridge createEffect:modelName
                                                       layer:layer
                                                  effectType:effectType
                                                 startTimeMS:(NSInteger)timeStart
                                                   endTimeMS:(NSInteger)timeEnd];
            if (effectId >= 0) {
                if (settings.length > 0) {
                    [_engineBridge setEffectSettings:effectId settings:settings];
                }
                if (palette.length > 0) {
                    [_engineBridge setEffectPalette:effectId palette:palette];
                }
                effectsCreated++;
            }
        }
    }

    if (effectsCreated > 0) {
        _cellRangeSelected = NO;
        [self reloadSequenceData];
        NSLog(@"XLSequencerViewController: Applied preset '%@' to %ld cells across rows %ld-%ld",
              effectType, (long)effectsCreated, (long)row1, (long)row2);
    }

    return effectsCreated;
}

#pragma mark - Timing Keyboard Action Helpers

/// Divide the currently selected timing mark(s) into N equal parts.
/// Used by TIMING_DIVIDE_2 through TIMING_DIVIDE_16 keyboard actions.
- (void)divideSelectedTimingMarks:(int)divisions {
    if (!_engineBridge || !_usingRealData || divisions < 2) return;

    // Get selected effect indices from the grid
    NSIndexSet *selectedIndices = _effectsGridView.selectedEffectIndices;
    NSInteger primarySelected = _effectsGridView.selectedEffectID;

    NSMutableArray<NSNumber *> *effectIds = [NSMutableArray array];

    if (selectedIndices.count > 0) {
        [selectedIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            NSInteger eid = [self->_effectsGridView effectIdAtRenderIndex:idx];
            if (eid >= 0) [effectIds addObject:@(eid)];
        }];
    } else if (primarySelected >= 0) {
        NSInteger eid = [_effectsGridView effectIdAtRenderIndex:(NSUInteger)primarySelected];
        if (eid >= 0) [effectIds addObject:@(eid)];
    }

    if (effectIds.count == 0) {
        NSLog(@"XLSequencerViewController: TIMING_DIVIDE_%d - no timing marks selected", divisions);
        return;
    }

    NSInteger baseTiming = (_frameRate > 0) ? (1000 / _frameRate) : 50;

    [_undoController beginUndoGroupingWithActionName:
        [NSString stringWithFormat:@"Divide Timing by %d", divisions]];

    for (NSNumber *eidNum in effectIds) {
        NSInteger effectId = eidNum.integerValue;
        NSDictionary *markInfo = [_engineBridge getTimingMark:effectId];
        if (!markInfo) continue;

        NSString *trackName = markInfo[@"trackName"];
        NSInteger layer = [markInfo[@"layer"] integerValue];
        NSInteger startTime = [markInfo[@"startTimeMS"] integerValue];
        NSInteger endTime = [markInfo[@"endTimeMS"] integerValue];

        if (endTime <= startTime || !trackName) continue;
        if (endTime - startTime <= baseTiming) continue;

        double splitDuration = (double)(endTime - startTime) / (double)divisions;

        // Resize original mark to first subdivision
        NSInteger firstEnd = [self roundToFrameBoundary:(double)startTime + splitDuration];
        [_engineBridge moveTimingMark:effectId startTimeMS:startTime endTimeMS:firstEnd];

        // Create additional subdivisions
        for (NSInteger j = 1; j < divisions; j++) {
            NSInteger newStart = [self roundToFrameBoundary:(double)startTime + splitDuration * (double)j];
            NSInteger newEnd;
            if (j == divisions - 1) {
                newEnd = endTime;
            } else {
                newEnd = [self roundToFrameBoundary:(double)startTime + splitDuration * (double)(j + 1)];
            }
            if (newStart < newEnd) {
                [_engineBridge createTimingMark:trackName layer:layer
                                    startTimeMS:newStart endTimeMS:newEnd
                                          label:@""];
            }
        }
    }

    [_undoController endUndoGrouping];

    [self reloadSequenceData];
    [_effectsGridView reloadData];
    [self reloadTimingMarksForRuler];
    NSLog(@"XLSequencerViewController: Divided %lu timing mark(s) by %d",
          (unsigned long)effectIds.count, divisions);
}

/// Set the label of the currently selected timing mark to the given phoneme string.
/// Used by PHONEME_ETC, PHONEME_AI, etc. keyboard actions.
- (void)setSelectedTimingMarkLabel:(NSString *)label {
    if (!_engineBridge || !_usingRealData) return;

    NSInteger selectedIdx = _effectsGridView.selectedEffectID;
    if (selectedIdx < 0) {
        NSLog(@"XLSequencerViewController: setSelectedTimingMarkLabel - no effect selected");
        return;
    }

    NSInteger effectId = [_effectsGridView effectIdAtRenderIndex:(NSUInteger)selectedIdx];
    if (effectId < 0) return;

    NSDictionary *markInfo = [_engineBridge getTimingMark:effectId];
    if (!markInfo) {
        NSLog(@"XLSequencerViewController: setSelectedTimingMarkLabel - selected effect %ld is not a timing mark",
              (long)effectId);
        return;
    }

    [_undoController beginUndoGroupingWithActionName:
        [NSString stringWithFormat:@"Set Phoneme '%@'", label]];
    [_engineBridge setTimingMarkLabel:effectId label:label];
    [_undoController endUndoGrouping];

    [self reloadSequenceData];
    [_effectsGridView reloadData];
    NSLog(@"XLSequencerViewController: Set timing mark %ld label to '%@'", (long)effectId, label);
}

/// Get the row of the currently focused element (from cell selection or selected effect).
/// Returns -1 if no row can be determined.
- (NSInteger)currentFocusedRow {
    if (_effectsGridView.hasCellSelection) {
        return _effectsGridView.cellSelectionRow;
    }
    NSInteger selectedIdx = _effectsGridView.selectedEffectID;
    if (selectedIdx >= 0 && selectedIdx < (NSInteger)_effectCount && _effectData) {
        NSInteger elemIdx = _effectData[selectedIdx].elementIndex;
        NSInteger layerIdx = _effectData[selectedIdx].layerIndex;
        for (NSUInteger r = 0; r < _rowCount; r++) {
            if (_rowData[r].elementIndex == elemIdx &&
                ((_rowData[r].isLayerRow && _rowData[r].layerIndex == layerIdx) ||
                 (!_rowData[r].isLayerRow && layerIdx == 0))) {
                return (NSInteger)r;
            }
        }
    }
    return -1;
}

#pragma mark - XLKeyboardActionDelegate

- (BOOL)performKeyAction:(NSString *)actionType
              effectName:(NSString *)effectName
          effectSettings:(NSString *)effectSettings
                 inScope:(XLKeyScope)scope {

    NSLog(@"XLSequencerViewController performKeyAction: actionType='%@', effectName='%@'",
          actionType, effectName);

    // Space bar - play/pause
    if ([actionType isEqualToString:@"TOGGLE_PLAY"]) {
        [_playbackController togglePlayPause];
        return YES;
    }

    // Toggle effect settings inspector (Cmd+I)
    if ([actionType isEqualToString:@"EFFECT_SETTINGS_TOGGLE"]) {
        NSLog(@"XLSequencerViewController: EFFECT_SETTINGS_TOGGLE - calling SwiftUI toggleInspector");
        [[XLSwiftUIWindowHelper shared] toggleInspector];
        return YES;
    }

    // Snap toggle
    if ([actionType isEqualToString:@"SNAP_TOGGLE"]) {
        [self toggleSnap];
        return YES;
    }

    // Zoom controls
    if ([actionType isEqualToString:@"ZOOM_IN"]) {
        [self zoomIn:nil];
        return YES;
    }
    if ([actionType isEqualToString:@"ZOOM_OUT"]) {
        [self zoomOut:nil];
        return YES;
    }

    // Navigation
    if ([actionType isEqualToString:@"START_OF_SONG"]) {
        [self seekToStart:nil];
        return YES;
    }
    if ([actionType isEqualToString:@"END_OF_SONG"]) {
        [self seekToEnd:nil];
        return YES;
    }

    // Playback controls
    if ([actionType isEqualToString:@"PLAY"]) {
        [_playbackController play];
        return YES;
    }
    if ([actionType isEqualToString:@"PAUSE"]) {
        [_playbackController pause];
        return YES;
    }
    if ([actionType isEqualToString:@"STOP"]) {
        [_playbackController stop];
        return YES;
    }

    // Frame step controls
    if ([actionType isEqualToString:@"STEP_FORWARD"]) {
        [_playbackController stepForward];
        return YES;
    }
    if ([actionType isEqualToString:@"STEP_BACKWARD"]) {
        [_playbackController stepBackward];
        return YES;
    }

    // Undo/Redo
    if ([actionType isEqualToString:@"UNDO"]) {
        [_undoController undo];
        return YES;
    }
    if ([actionType isEqualToString:@"REDO"]) {
        [_undoController redo];
        return YES;
    }

    // Effect insertion via keyboard shortcut (e.g., 'O' for On effect)
    if ([actionType isEqualToString:@"EFFECT"]) {
        [self createEffectOnSelectedCell:effectName settings:effectSettings];
        return YES;
    }

    // MARK: - Timing Operations

    // TIMING_ADD: Add a timing mark at the current playback position on the active timing track
    if ([actionType isEqualToString:@"TIMING_ADD"]) {
        if (!_engineBridge || !_usingRealData) return NO;

        NSString *trackName = [self activeTimingTrackForOperation];
        if (!trackName) {
            NSLog(@"XLSequencerViewController: TIMING_ADD - no active timing track");
            return NO;
        }

        NSInteger cursorTimeMS = (NSInteger)_transportBar.currentPositionMS;
        if (cursorTimeMS <= 0) return NO;

        NSInteger snappedCursor = [self roundToFrameBoundary:(double)cursorTimeMS];
        NSInteger frameTimeMS = (_frameRate > 0) ? (1000 / _frameRate) : 50;

        // Determine the layer: use layer 0 (phrase layer) by default
        NSInteger layer = 0;

        NSArray<NSDictionary *> *marks = [_engineBridge getTimingMarks:trackName layer:layer];

        // Find the timing mark containing the cursor position and split it
        for (NSDictionary *mark in marks) {
            NSInteger markStart = [mark[@"startTimeMS"] integerValue];
            NSInteger markEnd = [mark[@"endTimeMS"] integerValue];
            NSInteger markId = [mark[@"id"] integerValue];

            if (snappedCursor > markStart + frameTimeMS && snappedCursor < markEnd - frameTimeMS) {
                [_undoController beginUndoGroupingWithActionName:@"Add Timing Mark"];

                // Shrink existing mark to end at the split point
                [_engineBridge moveTimingMark:markId startTimeMS:markStart endTimeMS:snappedCursor];

                // Create new mark from split point to original end
                NSInteger newMarkId = [_engineBridge createTimingMark:trackName layer:layer
                                                          startTimeMS:snappedCursor endTimeMS:markEnd
                                                                label:@""];

                [_undoController endUndoGrouping];

                if (newMarkId >= 0) {
                    [self refreshTimingData];
                    NSLog(@"XLSequencerViewController: TIMING_ADD - split mark %ld at %ldms on '%@'",
                          (long)markId, (long)snappedCursor, trackName);
                }
                return YES;
            }
        }

        // No existing mark at cursor — try creating in empty space (e.g. sparse timing track)
        NSInteger endTimeMS = (NSInteger)_sequenceDurationMS;
        for (NSDictionary *mark in marks) {
            NSInteger markStart = [mark[@"startTimeMS"] integerValue];
            if (markStart > snappedCursor && markStart < endTimeMS) {
                endTimeMS = markStart;
            }
        }

        if (endTimeMS - snappedCursor >= frameTimeMS) {
            [_undoController beginUndoGroupingWithActionName:@"Add Timing Mark"];
            NSInteger newMarkId = [_engineBridge createTimingMark:trackName layer:layer
                                                      startTimeMS:snappedCursor endTimeMS:endTimeMS
                                                            label:@""];
            [_undoController endUndoGrouping];

            if (newMarkId >= 0) {
                [self refreshTimingData];
                NSLog(@"XLSequencerViewController: TIMING_ADD - created mark at %ldms-%ldms on '%@'",
                      (long)snappedCursor, (long)endTimeMS, trackName);
            }
        }
        return YES;
    }

    // TIMING_SPLIT: Split the timing mark under the cursor at the current playback position
    if ([actionType isEqualToString:@"TIMING_SPLIT"]) {
        if (!_engineBridge || !_usingRealData) return NO;

        NSString *trackName = [self activeTimingTrackForOperation];
        if (!trackName) {
            NSLog(@"XLSequencerViewController: TIMING_SPLIT - no active timing track");
            return NO;
        }

        NSInteger cursorTimeMS = (NSInteger)_transportBar.currentPositionMS;
        if (cursorTimeMS <= 0) return NO;

        NSInteger snappedCursor = [self roundToFrameBoundary:(double)cursorTimeMS];
        NSInteger frameTimeMS = (_frameRate > 0) ? (1000 / _frameRate) : 50;

        // Search all layers for a timing mark containing the cursor position
        for (NSInteger layer = 0; layer <= 2; layer++) {
            NSArray<NSDictionary *> *marks = [_engineBridge getTimingMarks:trackName layer:layer];
            for (NSDictionary *mark in marks) {
                NSInteger markStart = [mark[@"startTimeMS"] integerValue];
                NSInteger markEnd = [mark[@"endTimeMS"] integerValue];
                NSInteger markId = [mark[@"id"] integerValue];
                NSString *label = mark[@"label"] ?: @"";

                // Check if cursor is inside this mark (with room to split)
                if (snappedCursor > markStart + frameTimeMS && snappedCursor < markEnd - frameTimeMS) {
                    [_undoController beginUndoGroupingWithActionName:@"Split Timing Mark"];

                    // Resize the original mark to end at the split point
                    [_engineBridge moveTimingMark:markId startTimeMS:markStart endTimeMS:snappedCursor];

                    // Create a new mark from the split point to the original end
                    [_engineBridge createTimingMark:trackName layer:layer
                                        startTimeMS:snappedCursor endTimeMS:markEnd
                                              label:@""];

                    [_undoController endUndoGrouping];

                    [self refreshTimingData];
                    NSLog(@"XLSequencerViewController: TIMING_SPLIT - split mark %ld at %ldms (was %ld-%ld, label='%@')",
                          (long)markId, (long)snappedCursor, (long)markStart, (long)markEnd, label);
                    return YES;
                }
            }
        }

        NSLog(@"XLSequencerViewController: TIMING_SPLIT - no timing mark found at %ldms", (long)snappedCursor);
        return NO;
    }

    // TIMING_DIVIDE_N: Divide selected timing mark(s) into N equal parts
    if ([actionType hasPrefix:@"TIMING_DIVIDE_"]) {
        NSString *divisorStr = [actionType substringFromIndex:@"TIMING_DIVIDE_".length];
        NSInteger divisions = [divisorStr integerValue];
        if (divisions < 2 || divisions > 100) {
            NSLog(@"XLSequencerViewController: Invalid TIMING_DIVIDE value: %@", divisorStr);
            return NO;
        }
        [self divideSelectedTimingMarks:(int)divisions];
        return YES;
    }

    // MARK: - Phoneme Operations

    // PHONEME_*: Set the label of the selected timing mark to a specific phoneme
    if ([actionType hasPrefix:@"PHONEME_"]) {
        NSString *phonemeSuffix = [actionType substringFromIndex:@"PHONEME_".length];

        // Map action suffix to phoneme label string
        static NSDictionary *phonemeMap = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            phonemeMap = @{
                @"ETC":  @"etc",
                @"AI":   @"AI",
                @"E":    @"E",
                @"O":    @"O",
                @"WQ":   @"WQ",
                @"FV":   @"FV",
                @"MBP":  @"MBP",
                @"REST": @"rest",
                @"L":    @"L",
            };
        });

        NSString *phonemeLabel = phonemeMap[phonemeSuffix];
        if (!phonemeLabel) {
            NSLog(@"XLSequencerViewController: Unknown PHONEME action suffix: %@", phonemeSuffix);
            return NO;
        }

        [self setSelectedTimingMarkLabel:phonemeLabel];
        return YES;
    }

    // AUTO_ETC_PHONEME: Split selected phoneme at midpoint, set first half to "etc"
    if ([actionType isEqualToString:@"AUTO_ETC_PHONEME"]) {
        if (!_engineBridge || !_usingRealData) return NO;

        NSInteger selectedIdx = _effectsGridView.selectedEffectID;
        if (selectedIdx < 0) {
            NSLog(@"XLSequencerViewController: AUTO_ETC_PHONEME - no effect selected");
            return NO;
        }

        NSInteger effectId = [_effectsGridView effectIdAtRenderIndex:(NSUInteger)selectedIdx];
        if (effectId < 0) return NO;

        NSDictionary *markInfo = [_engineBridge getTimingMark:effectId];
        if (!markInfo) return NO;

        NSString *trackName = markInfo[@"trackName"];
        NSInteger layer = [markInfo[@"layer"] integerValue];
        NSInteger startTime = [markInfo[@"startTimeMS"] integerValue];
        NSInteger endTime = [markInfo[@"endTimeMS"] integerValue];

        if (endTime <= startTime || !trackName) return NO;

        NSInteger midpoint = [self roundToFrameBoundary:(double)(startTime + endTime) / 2.0];
        NSInteger frameTimeMS = (_frameRate > 0) ? (1000 / _frameRate) : 50;

        if (midpoint <= startTime + frameTimeMS || midpoint >= endTime - frameTimeMS) {
            NSLog(@"XLSequencerViewController: AUTO_ETC_PHONEME - mark too short to split");
            return NO;
        }

        [_undoController beginUndoGroupingWithActionName:@"Auto Etc Phoneme"];

        // Resize original mark to first half and label it "etc"
        [_engineBridge moveTimingMark:effectId startTimeMS:startTime endTimeMS:midpoint];
        [_engineBridge setTimingMarkLabel:effectId label:@"etc"];

        // Create second half with the original label (or empty)
        NSString *originalLabel = markInfo[@"label"] ?: @"";
        [_engineBridge createTimingMark:trackName layer:layer
                            startTimeMS:midpoint endTimeMS:endTime
                                  label:originalLabel];

        [_undoController endUndoGrouping];

        [self reloadSequenceData];
        [_effectsGridView reloadData];
        NSLog(@"XLSequencerViewController: AUTO_ETC_PHONEME - split mark %ld at midpoint %ldms, first half set to 'etc'",
              (long)effectId, (long)midpoint);
        return YES;
    }

    // MARK: - Color Operations

    // SET_COLOR_1 through SET_COLOR_8: Set palette primary color via notification
    if ([actionType hasPrefix:@"SET_COLOR_"]) {
        NSString *indexStr = [actionType substringFromIndex:@"SET_COLOR_".length];
        NSInteger colorIndex = [indexStr integerValue];
        if (colorIndex < 1 || colorIndex > 8) return NO;

        // Color map matching legacy xLights KeyBindings.cpp
        static NSDictionary *colorMap = nil;
        static dispatch_once_t colorOnce;
        dispatch_once(&colorOnce, ^{
            colorMap = @{
                @1: @"#FFFFFF",  // White
                @2: @"#FF0000",  // Red
                @3: @"#00FF00",  // Green
                @4: @"#0000FF",  // Blue
                @5: @"#FFFF00",  // Yellow
                @6: @"#000000",  // Black
                @7: @"#00FFFF",  // Cyan
                @8: @"#FF00FF",  // Magenta
            };
        });

        NSString *hexColor = colorMap[@(colorIndex)];
        if (!hexColor) return NO;

        // Post notification so SwiftUI ColorPaletteState can pick it up
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"XLSetPaletteColorNotification"
                          object:nil
                        userInfo:@{
                            @"colorIndex": @(colorIndex - 1),  // 0-indexed for palette array
                            @"hexColor": hexColor
                        }];

        NSLog(@"XLSequencerViewController: SET_COLOR_%ld -> %@", (long)colorIndex, hexColor);
        return YES;
    }

    // COLOR_UPDATE (Shift+F5): Apply current palette colors to all selected effects
    if ([actionType isEqualToString:@"COLOR_UPDATE"]) {
        if (!_engineBridge || !_usingRealData) return NO;

        NSArray<NSNumber *> *selectedIds = [_engineBridge getSelectedEffectIds];
        if (selectedIds.count == 0) {
            NSLog(@"XLSequencerViewController: COLOR_UPDATE - no effects selected");
            return NO;
        }

        [_undoController beginUndoGroupingWithActionName:@"Update Colors"];

        // Post notification asking ColorPaletteState to push its colors to selected effects
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"XLColorUpdateRequestNotification"
                          object:nil
                        userInfo:@{@"selectedEffectIds": selectedIds}];

        [_undoController endUndoGrouping];

        NSLog(@"XLSequencerViewController: COLOR_UPDATE - applied to %lu effects",
              (unsigned long)selectedIds.count);
        return YES;
    }

    // MARK: - Layer Operations

    // INSERT_LAYER_ABOVE (Cmd+Shift+I): Insert layer above current row
    if ([actionType isEqualToString:@"INSERT_LAYER_ABOVE"]) {
        if (!_engineBridge || !_usingRealData) return NO;

        NSInteger row = _effectsGridView.cellSelectionRow;
        if (row < 0 || row >= (NSInteger)_rowCount) {
            NSLog(@"XLSequencerViewController: INSERT_LAYER_ABOVE - no valid row selected");
            return NO;
        }

        [_undoController beginUndoGroupingWithActionName:@"Insert Layer Above"];
        [self rowHeadings:_rowHeadingsView insertLayerAboveRow:row];
        [_undoController endUndoGrouping];
        return YES;
    }

    // INSERT_LAYER_BELOW (Cmd+Shift+A): Insert layer below current row
    if ([actionType isEqualToString:@"INSERT_LAYER_BELOW"]) {
        if (!_engineBridge || !_usingRealData) return NO;

        NSInteger row = _effectsGridView.cellSelectionRow;
        if (row < 0 || row >= (NSInteger)_rowCount) {
            NSLog(@"XLSequencerViewController: INSERT_LAYER_BELOW - no valid row selected");
            return NO;
        }

        [_undoController beginUndoGroupingWithActionName:@"Insert Layer Below"];
        [self rowHeadings:_rowHeadingsView insertLayerBelowRow:row];
        [_undoController endUndoGrouping];
        return YES;
    }

    // MARK: - Audio Speed Operations

    // Predefined speed list for INCREASE/DECREASE stepping
    {
        static const CGFloat kSpeedSteps[] = { 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0 };
        static const NSInteger kSpeedStepCount = sizeof(kSpeedSteps) / sizeof(kSpeedSteps[0]);

        if ([actionType isEqualToString:@"AUDIO_FULL_SPEED"]) {
            [_playbackController setPlaybackRate:1.0];
            [_engineBridge setPlaybackSpeed:1.0];
            NSLog(@"XLSequencerViewController: Audio speed set to 1.0x");
            return YES;
        }
        if ([actionType isEqualToString:@"AUDIO_F_1_5_SPEED"]) {
            [_playbackController setPlaybackRate:1.5];
            [_engineBridge setPlaybackSpeed:1.5];
            NSLog(@"XLSequencerViewController: Audio speed set to 1.5x");
            return YES;
        }
        if ([actionType isEqualToString:@"AUDIO_F_2_SPEED"]) {
            [_playbackController setPlaybackRate:2.0];
            [_engineBridge setPlaybackSpeed:2.0];
            NSLog(@"XLSequencerViewController: Audio speed set to 2.0x");
            return YES;
        }
        if ([actionType isEqualToString:@"AUDIO_F_3_SPEED"]) {
            [_playbackController setPlaybackRate:3.0];
            [_engineBridge setPlaybackSpeed:3.0];
            NSLog(@"XLSequencerViewController: Audio speed set to 3.0x");
            return YES;
        }
        if ([actionType isEqualToString:@"AUDIO_F_4_SPEED"]) {
            [_playbackController setPlaybackRate:4.0];
            [_engineBridge setPlaybackSpeed:4.0];
            NSLog(@"XLSequencerViewController: Audio speed set to 4.0x");
            return YES;
        }
        if ([actionType isEqualToString:@"AUDIO_S_3_4_SPEED"]) {
            [_playbackController setPlaybackRate:0.75];
            [_engineBridge setPlaybackSpeed:0.75];
            NSLog(@"XLSequencerViewController: Audio speed set to 0.75x");
            return YES;
        }
        if ([actionType isEqualToString:@"AUDIO_S_1_2_SPEED"]) {
            [_playbackController setPlaybackRate:0.5];
            [_engineBridge setPlaybackSpeed:0.5];
            NSLog(@"XLSequencerViewController: Audio speed set to 0.5x");
            return YES;
        }
        if ([actionType isEqualToString:@"AUDIO_S_1_4_SPEED"]) {
            [_playbackController setPlaybackRate:0.25];
            [_engineBridge setPlaybackSpeed:0.25];
            NSLog(@"XLSequencerViewController: Audio speed set to 0.25x");
            return YES;
        }
        if ([actionType isEqualToString:@"INCREASE_SPEED"]) {
            CGFloat currentRate = _playbackController.playbackRate;
            CGFloat newRate = kSpeedSteps[kSpeedStepCount - 1];
            for (NSInteger i = 0; i < kSpeedStepCount - 1; i++) {
                if (currentRate < kSpeedSteps[i] + 0.01) {
                    newRate = kSpeedSteps[i + 1 < kSpeedStepCount ? i + 1 : i];
                    break;
                }
            }
            [_playbackController setPlaybackRate:newRate];
            [_engineBridge setPlaybackSpeed:newRate];
            NSLog(@"XLSequencerViewController: INCREASE_SPEED -> %.2fx", newRate);
            return YES;
        }
        if ([actionType isEqualToString:@"DECREASE_SPEED"]) {
            CGFloat currentRate = _playbackController.playbackRate;
            CGFloat newRate = kSpeedSteps[0];
            for (NSInteger i = kSpeedStepCount - 1; i > 0; i--) {
                if (currentRate > kSpeedSteps[i] - 0.01) {
                    newRate = kSpeedSteps[i - 1 >= 0 ? i - 1 : i];
                    break;
                }
            }
            [_playbackController setPlaybackRate:newRate];
            [_engineBridge setPlaybackSpeed:newRate];
            NSLog(@"XLSequencerViewController: DECREASE_SPEED -> %.2fx", newRate);
            return YES;
        }
    }

    // MARK: - Play Loop

    // PLAY_LOOP: Toggle loop playback of selected time region
    if ([actionType isEqualToString:@"PLAY_LOOP"]) {
        if (_playbackController.loopEnabled) {
            _playbackController.loopEnabled = NO;
            [_playbackController clearLoopRegion];
            NSLog(@"XLSequencerViewController: PLAY_LOOP disabled");
        } else {
            _playbackController.loopEnabled = YES;
            if (_effectsGridView.hasCellSelection) {
                CGFloat startMS = _effectsGridView.cellSelectionStartMS;
                CGFloat endMS = _effectsGridView.cellSelectionEndMS;
                _playbackController.loopRegionStartMS = (NSInteger)startMS;
                _playbackController.loopRegionEndMS = (NSInteger)endMS;
                NSLog(@"XLSequencerViewController: PLAY_LOOP enabled for region %ld-%ld ms",
                      (long)(NSInteger)startMS, (long)(NSInteger)endMS);
            } else {
                NSLog(@"XLSequencerViewController: PLAY_LOOP enabled (full sequence)");
            }
            if (!_playbackController.isPlaying) {
                [_playbackController play];
            }
        }
        return YES;
    }

    // MARK: - Audio Tag Navigation

    // TODO: Audio tag/bookmark system not yet implemented in native build.
    if ([actionType isEqualToString:@"PRIOR_TAG"]) {
        NSLog(@"XLSequencerViewController: PRIOR_TAG - audio tag navigation not yet implemented");
        return YES;
    }
    if ([actionType isEqualToString:@"NEXT_TAG"]) {
        NSLog(@"XLSequencerViewController: NEXT_TAG - audio tag navigation not yet implemented");
        return YES;
    }
    if ([actionType isEqualToString:@"PLAY_PRIOR_TAG"]) {
        NSLog(@"XLSequencerViewController: PLAY_PRIOR_TAG - audio tag navigation not yet implemented");
        return YES;
    }
    if ([actionType isEqualToString:@"PLAY_NEXT_TAG"]) {
        NSLog(@"XLSequencerViewController: PLAY_NEXT_TAG - audio tag navigation not yet implemented");
        return YES;
    }

    // MARK: - Navigation Bookmarks (xlmac-5wc7)

    // MARK_SPOT: Save current playback position as a bookmark
    if ([actionType isEqualToString:@"MARK_SPOT"]) {
        _markedPositionMS = (NSInteger)_transportBar.currentPositionMS;
        NSLog(@"XLSequencerViewController: MARK_SPOT - marked position at %ldms", (long)_markedPositionMS);
        return YES;
    }

    // RETURN_TO_SPOT: Return playback cursor to the bookmarked position
    if ([actionType isEqualToString:@"RETURN_TO_SPOT"]) {
        if (_markedPositionMS >= 0) {
            [_playbackController stop];
            [_engineBridge seek:_markedPositionMS];
            [_transportBar setCurrentPositionMS:(CGFloat)_markedPositionMS];
            [_timelineRuler setPlaybackPosition:(NSTimeInterval)_markedPositionMS / 1000.0 animated:YES];
            NSLog(@"XLSequencerViewController: RETURN_TO_SPOT - returned to %ldms", (long)_markedPositionMS);
        } else {
            NSLog(@"XLSequencerViewController: RETURN_TO_SPOT - no position marked");
        }
        return YES;
    }

    // MARK: - Zoom to Selection (xlmac-360v)

    // ZOOM_SEL: Zoom timeline to fit the selected effects
    if ([actionType isEqualToString:@"ZOOM_SEL"]) {
        [_effectsGridView zoomToSelection];
        NSLog(@"XLSequencerViewController: ZOOM_SEL - zoomed to selection");
        return YES;
    }

    // MARK: - Render Controls (xlmac-haqw)

    // CANCEL_RENDER: Abort the current rendering operation
    if ([actionType isEqualToString:@"CANCEL_RENDER"]) {
        if (_engineBridge && [_engineBridge isRendering]) {
            [_engineBridge abortRender];
            NSLog(@"XLSequencerViewController: CANCEL_RENDER - render aborted");
        } else {
            NSLog(@"XLSequencerViewController: CANCEL_RENDER - no render in progress");
        }
        return YES;
    }

    // TOGGLE_RENDER: Toggle background auto-render on/off
    if ([actionType isEqualToString:@"TOGGLE_RENDER"]) {
        _backgroundRenderEnabled = !_backgroundRenderEnabled;
        NSLog(@"XLSequencerViewController: TOGGLE_RENDER - background render %@",
              _backgroundRenderEnabled ? @"ENABLED" : @"DISABLED");
        // TODO: Wire to render engine auto-render flag when available
        return YES;
    }

    // RENDER_ALL: Trigger a full sequence render
    if ([actionType isEqualToString:@"RENDER_ALL"]) {
        if (_engineBridge) {
            [_engineBridge renderAll];
            NSLog(@"XLSequencerViewController: RENDER_ALL - full sequence render triggered");
        }
        return YES;
    }

    // MARK: - Clipboard Paste Modes (xlmac-8wd4)

    // PASTE_BY_CELL: Set paste mode to "by cell" (relative positioning)
    if ([actionType isEqualToString:@"PASTE_BY_CELL"]) {
        _pasteByCellMode = YES;
        NSLog(@"XLSequencerViewController: PASTE_BY_CELL - paste mode set to BY CELL");
        return YES;
    }

    // PASTE_BY_TIME: Set paste mode to "by time" (original timestamps)
    if ([actionType isEqualToString:@"PASTE_BY_TIME"]) {
        _pasteByCellMode = NO;
        NSLog(@"XLSequencerViewController: PASTE_BY_TIME - paste mode set to BY TIME");
        return YES;
    }

    // MARK: - Global Shortcuts (xlmac-qeki)

    // LIGHTS_TOGGLE: Toggle output to physical lights
    if ([actionType isEqualToString:@"LIGHTS_TOGGLE"]) {
        if (_engineBridge) {
            if ([_engineBridge isOutputting]) {
                [_engineBridge stopOutput];
                NSLog(@"XLSequencerViewController: LIGHTS_TOGGLE - output STOPPED");
            } else {
                [_engineBridge startOutput];
                NSLog(@"XLSequencerViewController: LIGHTS_TOGGLE - output STARTED");
            }
        }
        return YES;
    }

    // SEQUENCE_SETTINGS: Open sequence settings dialog
    if ([actionType isEqualToString:@"SEQUENCE_SETTINGS"]) {
        // Dispatch to AppDelegate's showSequenceSettings: which handles the dialog
        [[NSApp delegate] performSelector:@selector(showSequenceSettings:) withObject:nil];
        NSLog(@"XLSequencerViewController: SEQUENCE_SETTINGS - opening dialog");
        return YES;
    }

    // SAVE_SEQUENCE: Save current sequence
    if ([actionType isEqualToString:@"SAVE_SEQUENCE"]) {
        // Use the standard NSDocument save mechanism (same as Cmd+S menu)
        [NSApp sendAction:@selector(saveDocument:) to:nil from:self];
        NSLog(@"XLSequencerViewController: SAVE_SEQUENCE - save triggered");
        return YES;
    }

    // SAVEAS_SEQUENCE: Save current sequence to a new file
    if ([actionType isEqualToString:@"SAVEAS_SEQUENCE"]) {
        [NSApp sendAction:@selector(saveDocumentAs:) to:nil from:self];
        NSLog(@"XLSequencerViewController: SAVEAS_SEQUENCE - save as triggered");
        return YES;
    }

    // SELECT_SHOW_FOLDER: Open folder picker to change show folder (default F9)
    if ([actionType isEqualToString:@"SELECT_SHOW_FOLDER"]) {
        XLAppDelegate *appDelegate = (XLAppDelegate *)[NSApp delegate];
        [appDelegate selectShowFolder:nil];
        return YES;
    }

    // BACKUP: Backup show folder (default F10)
    if ([actionType isEqualToString:@"BACKUP"]) {
        [[NSApp delegate] performSelector:@selector(backupShowFolder:) withObject:nil];
        NSLog(@"XLSequencerViewController: BACKUP - backup show folder triggered");
        return YES;
    }

    // ALTERNATE_BACKUP: Backup to alternate location (default F11)
    if ([actionType isEqualToString:@"ALTERNATE_BACKUP"]) {
        [[NSApp delegate] performSelector:@selector(alternateBackup:) withObject:nil];
        NSLog(@"XLSequencerViewController: ALTERNATE_BACKUP - alternate backup triggered");
        return YES;
    }

    // SAVE_CURRENT_TAB: Save via NSDocument responder chain (same as Cmd+S menu)
    if ([actionType isEqualToString:@"SAVE_CURRENT_TAB"]) {
        [NSApp sendAction:@selector(saveDocument:) to:nil from:self];
        NSLog(@"XLSequencerViewController: SAVE_CURRENT_TAB - save triggered");
        return YES;
    }

    // OPEN_SEQUENCE: Forward to XLAppDelegate openSequence:
    if ([actionType isEqualToString:@"OPEN_SEQUENCE"]) {
        [[NSApp delegate] performSelector:@selector(openSequence:) withObject:nil];
        NSLog(@"XLSequencerViewController: OPEN_SEQUENCE - open triggered");
        return YES;
    }

    // CLOSE_SEQUENCE: Close via standard NSWindow performClose: (same as Cmd+W menu)
    if ([actionType isEqualToString:@"CLOSE_SEQUENCE"]) {
        [NSApp sendAction:@selector(performClose:) to:nil from:self];
        NSLog(@"XLSequencerViewController: CLOSE_SEQUENCE - close triggered");
        return YES;
    }

    // NEW_SEQUENCE: Forward to XLAppDelegate newSequence:
    if ([actionType isEqualToString:@"NEW_SEQUENCE"]) {
        [[NSApp delegate] performSelector:@selector(newSequence:) withObject:nil];
        NSLog(@"XLSequencerViewController: NEW_SEQUENCE - new sequence triggered");
        return YES;
    }

    // MARK: - Preset Operations (xlmac-kodd)

    // SHOW_PRESETS: Toggle the presets panel
    if ([actionType isEqualToString:@"SHOW_PRESETS"]) {
        [self effectsGridDidRequestEffectPresets:_effectsGridView];
        NSLog(@"XLSequencerViewController: SHOW_PRESETS - toggled presets panel");
        return YES;
    }

    // APPLY_SELECTED_PRESET: Apply the currently selected preset
    if ([actionType isEqualToString:@"APPLY_SELECTED_PRESET"]) {
        if (!_presetsWindowController || !_engineBridge) {
            NSLog(@"XLSequencerViewController: APPLY_SELECTED_PRESET - no presets window or engine");
            return YES;
        }
        NSDictionary *presetData = [_presetsWindowController selectedPresetData];
        if (!presetData) {
            NSLog(@"XLSequencerViewController: APPLY_SELECTED_PRESET - no preset selected in panel");
            return YES;
        }

        if (_cellRangeSelected) {
            NSInteger count = [self applyPresetToMultiCellRange:presetData];
            NSLog(@"XLSequencerViewController: APPLY_SELECTED_PRESET - applied to %ld cells in range",
                  (long)count);
        } else if (_effectsGridView.hasCellSelection) {
            [self applyPresetToSelectedCell:presetData];
            NSLog(@"XLSequencerViewController: APPLY_SELECTED_PRESET - applied to selected cell");
        } else {
            NSString *presetName = [_presetsWindowController selectedPresetName];
            NSArray<NSNumber *> *selectedIds = [_engineBridge getSelectedEffectIds];
            if (selectedIds.count > 0 && presetName) {
                for (NSNumber *eid in selectedIds) {
                    [_presetsWindowController applyPreset:presetName toEffect:[eid integerValue]];
                }
                [self reloadSequenceData];
                NSLog(@"XLSequencerViewController: APPLY_SELECTED_PRESET - applied '%@' to %lu effect(s)",
                      presetName, (unsigned long)selectedIds.count);
            } else {
                NSLog(@"XLSequencerViewController: APPLY_SELECTED_PRESET - no cells or effects selected");
            }
        }
        return YES;
    }

    // PRESET: Insert a preset by name (effectName contains the preset name)
    if ([actionType isEqualToString:@"PRESET"]) {
        if (!_engineBridge || !effectName.length) {
            NSLog(@"XLSequencerViewController: PRESET - missing engine or preset name");
            return YES;
        }
        NSArray<NSNumber *> *selectedIds = [_engineBridge getSelectedEffectIds];
        if (selectedIds.count > 0) {
            if (!_presetsWindowController) {
                _presetsWindowController = [[XLEffectPresetsWindowController alloc]
                    initWithEngineBridge:_engineBridge];
            }
            for (NSNumber *eid in selectedIds) {
                [_presetsWindowController applyPreset:effectName toEffect:[eid integerValue]];
            }
            [self reloadSequenceData];
            NSLog(@"XLSequencerViewController: PRESET - applied preset '%@' to %lu effect(s)",
                  effectName, (unsigned long)selectedIds.count);
        } else {
            NSLog(@"XLSequencerViewController: PRESET - no effects selected to apply '%@'", effectName);
        }
        return YES;
    }

    // APPLYSETTING: Apply specific settings to selected effects
    if ([actionType isEqualToString:@"APPLYSETTING"]) {
        if (!_engineBridge || !effectSettings.length) {
            NSLog(@"XLSequencerViewController: APPLYSETTING - missing engine or settings");
            return YES;
        }
        NSArray<NSNumber *> *selectedIds = [_engineBridge getSelectedEffectIds];
        for (NSNumber *eid in selectedIds) {
            [_engineBridge setEffectSettings:[eid integerValue] settings:effectSettings];
        }
        if (selectedIds.count > 0) {
            [self reloadSequenceData];
            NSLog(@"XLSequencerViewController: APPLYSETTING - applied settings to %lu effect(s)",
                  (unsigned long)selectedIds.count);
        } else {
            NSLog(@"XLSequencerViewController: APPLYSETTING - no effects selected");
        }
        return YES;
    }

    // MARK: - Jukebox Buttons (xlmac-mh8h)

    if ([actionType isEqualToString:@"JUKEBOX_BTN_1"]) {
        NSLog(@"XLSequencerViewController: JUKEBOX_BTN_1 - jukebox not yet implemented in native build");
        return YES;
    }
    if ([actionType isEqualToString:@"JUKEBOX_BTN_2"]) {
        NSLog(@"XLSequencerViewController: JUKEBOX_BTN_2 - jukebox not yet implemented in native build");
        return YES;
    }
    if ([actionType isEqualToString:@"JUKEBOX_BTN_3"]) {
        NSLog(@"XLSequencerViewController: JUKEBOX_BTN_3 - jukebox not yet implemented in native build");
        return YES;
    }
    if ([actionType isEqualToString:@"JUKEBOX_BTN_4"]) {
        NSLog(@"XLSequencerViewController: JUKEBOX_BTN_4 - jukebox not yet implemented in native build");
        return YES;
    }
    if ([actionType isEqualToString:@"JUKEBOX_BTN_5"]) {
        NSLog(@"XLSequencerViewController: JUKEBOX_BTN_5 - jukebox not yet implemented in native build");
        return YES;
    }

    // MARK: - Effect Operations

    // --- Duplicate Effects (Shift+Alt+Arrow) ---
    if ([actionType isEqualToString:@"DUPLICATE_RIGHT"] ||
        [actionType isEqualToString:@"DUPLICATE_LEFT"] ||
        [actionType isEqualToString:@"DUPLICATE_UP"] ||
        [actionType isEqualToString:@"DUPLICATE_DOWN"]) {

        NSIndexSet *selected = _effectsGridView.selectedEffectIndices;
        if (!_engineBridge || selected.count == 0) {
            NSLog(@"XLSequencerViewController: %@ - no effects selected", actionType);
            return YES;
        }

        NSInteger direction;
        if ([actionType isEqualToString:@"DUPLICATE_RIGHT"])     direction = 1;
        else if ([actionType isEqualToString:@"DUPLICATE_LEFT"]) direction = 2;
        else if ([actionType isEqualToString:@"DUPLICATE_UP"])   direction = 3;
        else                                                      direction = 4;

        [self duplicateSelectedEffects:selected direction:direction];
        return YES;
    }

    // --- Lock/Unlock Effects (Cmd+L / Cmd+U) ---
    if ([actionType isEqualToString:@"LOCK_EFFECT"] ||
        [actionType isEqualToString:@"UNLOCK_EFFECT"]) {

        NSIndexSet *selected = _effectsGridView.selectedEffectIndices;
        if (!_engineBridge || selected.count == 0) {
            NSLog(@"XLSequencerViewController: %@ - no effects selected", actionType);
            return YES;
        }

        BOOL lock = [actionType isEqualToString:@"LOCK_EFFECT"];
        [self effectsGrid:_effectsGridView didRequestSetLocked:lock forEffects:selected];
        return YES;
    }

    // --- Effect Alignment (EFFECT_ALIGN_START/END/BOTH) ---
    if ([actionType isEqualToString:@"EFFECT_ALIGN_START"] ||
        [actionType isEqualToString:@"EFFECT_ALIGN_END"] ||
        [actionType isEqualToString:@"EFFECT_ALIGN_BOTH"]) {

        NSIndexSet *selected = _effectsGridView.selectedEffectIndices;
        if (!_engineBridge || selected.count < 2) {
            NSLog(@"XLSequencerViewController: %@ - need 2+ effects selected", actionType);
            return YES;
        }

        XLAlignmentType alignType;
        if ([actionType isEqualToString:@"EFFECT_ALIGN_START"])      alignType = XLAlignmentTypeStartTimes;
        else if ([actionType isEqualToString:@"EFFECT_ALIGN_END"])   alignType = XLAlignmentTypeEndTimes;
        else                                                          alignType = XLAlignmentTypeBothTimes;

        [self effectsGrid:_effectsGridView didRequestAlignEffects:selected alignmentType:alignType];
        return YES;
    }

    // --- Effect Description (opens description dialog) ---
    if ([actionType isEqualToString:@"EFFECT_DESCRIPTION"]) {
        NSIndexSet *selected = _effectsGridView.selectedEffectIndices;
        if (!_engineBridge || selected.count == 0) {
            NSLog(@"XLSequencerViewController: EFFECT_DESCRIPTION - no effect selected");
            return YES;
        }
        NSUInteger firstIdx = [selected firstIndex];
        [self effectsGrid:_effectsGridView didRequestEditDescriptionForEffectAtIndex:(NSInteger)firstIdx];
        return YES;
    }

    // --- Effect Update (F5) - apply current panel settings to selected effects ---
    if ([actionType isEqualToString:@"EFFECT_UPDATE"]) {
        NSIndexSet *selected = _effectsGridView.selectedEffectIndices;
        if (!_engineBridge || selected.count == 0) {
            NSLog(@"XLSequencerViewController: EFFECT_UPDATE - no effects selected");
            return YES;
        }

        // TODO: Read current effect panel settings and apply to all selected effects.
        // Requires integration with the SwiftUI effect properties panel to read
        // the current settings state and push them to the engine bridge.
        NSLog(@"XLSequencerViewController: EFFECT_UPDATE (F5) - not yet fully implemented (need panel settings integration)");
        return YES;
    }

    // --- Random Effects (Shift+R) ---
    if ([actionType isEqualToString:@"RANDOM"]) {
        [self effectsGridDidRequestCreateRandomEffects:_effectsGridView];
        return YES;
    }

    // --- Effects to Timing (convert selected effects to timing marks) ---
    if ([actionType isEqualToString:@"EFFECTS_TO_TIMING"]) {
        NSIndexSet *selected = _effectsGridView.selectedEffectIndices;
        if (!_engineBridge || selected.count == 0) {
            NSLog(@"XLSequencerViewController: EFFECTS_TO_TIMING - no effects selected");
            return YES;
        }
        [self effectsGrid:_effectsGridView didRequestCreateTimingFromEffects:selected];
        return YES;
    }

    // MARK: - Selection (xlmac-gf7g)

    // SELECT_ALL: Select all effects and timing marks in the sequence
    if ([actionType isEqualToString:@"SELECT_ALL"]) {
        if (!_engineBridge || !_usingRealData) return NO;

        for (NSUInteger i = 0; i < _rowCount; i++) {
            if (_rowData[i].isLayerRow) continue;
            NSString *modelName = [NSString stringWithUTF8String:_rowData[i].name];
            NSInteger layerCount = _rowData[i].effectLayerCount;
            if (layerCount <= 0) layerCount = 1;

            for (NSInteger layer = 0; layer < layerCount; layer++) {
                NSArray *effects = [_engineBridge getEffectsForLayer:modelName layer:layer];
                for (NSDictionary *effect in effects) {
                    NSInteger effectId = [effect[@"id"] integerValue];
                    [_engineBridge selectEffect:effectId];
                }
            }
        }
        [_effectsGridView reloadData];
        NSLog(@"XLSequencerViewController: SELECT_ALL - selected all effects and timing marks");
        return YES;
    }

    // SELECT_ALL_NO_TIMING: Select all effects excluding timing tracks
    if ([actionType isEqualToString:@"SELECT_ALL_NO_TIMING"]) {
        if (!_engineBridge || !_usingRealData) return NO;

        for (NSUInteger i = 0; i < _rowCount; i++) {
            if (_rowData[i].isLayerRow) continue;
            if (_rowData[i].type == XLElementTypeTiming) continue;

            NSString *modelName = [NSString stringWithUTF8String:_rowData[i].name];
            NSInteger layerCount = _rowData[i].effectLayerCount;
            if (layerCount <= 0) layerCount = 1;

            for (NSInteger layer = 0; layer < layerCount; layer++) {
                NSArray *effects = [_engineBridge getEffectsForLayer:modelName layer:layer];
                for (NSDictionary *effect in effects) {
                    NSInteger effectId = [effect[@"id"] integerValue];
                    [_engineBridge selectEffect:effectId];
                }
            }
        }
        [_effectsGridView reloadData];
        NSLog(@"XLSequencerViewController: SELECT_ALL_NO_TIMING - selected all non-timing effects");
        return YES;
    }

    // TOGGLE_ELEMENT_EXPAND: Toggle expanded/collapsed state of the element at the current row
    if ([actionType isEqualToString:@"TOGGLE_ELEMENT_EXPAND"]) {
        NSInteger targetRow = [self currentFocusedRow];

        if (targetRow < 0 || targetRow >= (NSInteger)_rowCount) {
            NSLog(@"XLSequencerViewController: TOGGLE_ELEMENT_EXPAND - no target row");
            return NO;
        }

        // If on a layer sub-row, find the parent element row
        if (_rowData[targetRow].isLayerRow) {
            NSInteger parentIdx = _rowData[targetRow].elementIndex;
            for (NSInteger r = targetRow - 1; r >= 0; r--) {
                if (!_rowData[r].isLayerRow && _rowData[r].elementIndex == parentIdx) {
                    targetRow = r;
                    break;
                }
            }
        }

        [self rowHeadings:_rowHeadingsView didToggleExpandAtRow:targetRow];
        [_effectsGridView reloadData];
        [_rowHeadingsView setNeedsDisplay:YES];
        NSLog(@"XLSequencerViewController: TOGGLE_ELEMENT_EXPAND at row %ld", (long)targetRow);
        return YES;
    }

    // MARK: - Timing Track Selection (xlmac-r8c4)

    // SELECT_TIMING_1 through SELECT_TIMING_9: Set the Nth timing track as active
    if ([actionType hasPrefix:@"SELECT_TIMING_"]) {
        NSString *numStr = [actionType substringFromIndex:@"SELECT_TIMING_".length];
        NSInteger trackNumber = [numStr integerValue];
        if (trackNumber < 1 || trackNumber > 9) {
            NSLog(@"XLSequencerViewController: Invalid SELECT_TIMING number: %@", numStr);
            return NO;
        }

        NSArray<NSDictionary *> *timingTracks = [_engineBridge getTimingTracks];
        NSInteger trackIndex = trackNumber - 1;

        if (trackIndex >= (NSInteger)timingTracks.count) {
            NSLog(@"XLSequencerViewController: SELECT_TIMING_%ld - only %lu timing tracks available",
                  (long)trackNumber, (unsigned long)timingTracks.count);
            return NO;
        }

        NSString *trackName = timingTracks[(NSUInteger)trackIndex][@"name"];
        if (trackName) {
            BOOL success = [_engineBridge setActiveTimingTrack:trackName];
            if (success) {
                [self updateActiveTimingColorIndex];
                [self reloadTimingMarksForRuler];
                [_effectsGridView reloadData];
                [_timingTrackPopup selectItemWithTitle:trackName];
                NSLog(@"XLSequencerViewController: SELECT_TIMING_%ld - activated '%@'",
                      (long)trackNumber, trackName);
            }
        }
        return YES;
    }

    // SELECT_NO_TIMING: Deactivate all timing tracks
    if ([actionType isEqualToString:@"SELECT_NO_TIMING"]) {
        [_engineBridge deactivateAllTimingTracks];
        [self updateActiveTimingColorIndex];
        [self reloadTimingMarksForRuler];
        [_effectsGridView reloadData];
        NSLog(@"XLSequencerViewController: SELECT_NO_TIMING - deactivated all timing tracks");
        return YES;
    }

    // MARK: - Render Toggles (xlmac-g4ur)

    // MODEL_TOGGLE: Toggle render enable/disable for the model at the current row
    if ([actionType isEqualToString:@"MODEL_TOGGLE"]) {
        NSInteger targetRow = [self currentFocusedRow];
        if (targetRow >= 0 && targetRow < (NSInteger)_rowCount &&
            _rowData[targetRow].type != XLElementTypeTiming) {
            [self rowHeadings:_rowHeadingsView toggleRenderDisabledAtRow:targetRow];
        }
        return YES;
    }

    // MODEL_DISABLE: Disable rendering for the model at the current row
    if ([actionType isEqualToString:@"MODEL_DISABLE"]) {
        NSInteger targetRow = [self currentFocusedRow];
        if (targetRow >= 0 && targetRow < (NSInteger)_rowCount &&
            _rowData[targetRow].type != XLElementTypeTiming) {
            if (![self rowHeadingsIsRenderDisabledAtRow:_rowHeadingsView row:targetRow]) {
                [self rowHeadings:_rowHeadingsView toggleRenderDisabledAtRow:targetRow];
            }
        }
        return YES;
    }

    // MODEL_ENABLE: Enable rendering for the model at the current row
    if ([actionType isEqualToString:@"MODEL_ENABLE"]) {
        NSInteger targetRow = [self currentFocusedRow];
        if (targetRow >= 0 && targetRow < (NSInteger)_rowCount &&
            _rowData[targetRow].type != XLElementTypeTiming) {
            if ([self rowHeadingsIsRenderDisabledAtRow:_rowHeadingsView row:targetRow]) {
                [self rowHeadings:_rowHeadingsView toggleRenderDisabledAtRow:targetRow];
            }
        }
        return YES;
    }

    // EFFECT_TOGGLE: Toggle render enable/disable for the selected effect(s)
    if ([actionType isEqualToString:@"EFFECT_TOGGLE"]) {
        if (!_engineBridge) return NO;
        NSIndexSet *selected = _effectsGridView.selectedEffectIndices;
        if (selected.count > 0) {
            NSInteger firstIdx = (NSInteger)[selected firstIndex];
            NSInteger firstEffectId = [_effectsGridView effectIdAtRenderIndex:(NSUInteger)firstIdx];
            if (firstEffectId >= 0) {
                NSDictionary *info = [_engineBridge getEffect:firstEffectId];
                BOOL currentlyDisabled = [info[@"isRenderDisabled"] boolValue];
                [self effectsGrid:_effectsGridView didRequestSetRenderDisabled:!currentlyDisabled forEffects:selected];
            }
        }
        return YES;
    }

    // EFFECT_DISABLE: Disable rendering for the selected effect(s)
    if ([actionType isEqualToString:@"EFFECT_DISABLE"]) {
        if (!_engineBridge) return NO;
        NSIndexSet *selected = _effectsGridView.selectedEffectIndices;
        if (selected.count > 0) {
            [self effectsGrid:_effectsGridView didRequestSetRenderDisabled:YES forEffects:selected];
        }
        return YES;
    }

    // EFFECT_ENABLE: Enable rendering for the selected effect(s)
    if ([actionType isEqualToString:@"EFFECT_ENABLE"]) {
        if (!_engineBridge) return NO;
        NSIndexSet *selected = _effectsGridView.selectedEffectIndices;
        if (selected.count > 0) {
            [self effectsGrid:_effectsGridView didRequestSetRenderDisabled:NO forEffects:selected];
        }
        return YES;
    }

    // MODEL_EFFECT_TOGGLE: Toggle model or effect rendering depending on selection
    if ([actionType isEqualToString:@"MODEL_EFFECT_TOGGLE"]) {
        if (!_engineBridge) return NO;
        NSIndexSet *selected = _effectsGridView.selectedEffectIndices;
        if (selected.count > 0) {
            NSInteger firstIdx = (NSInteger)[selected firstIndex];
            NSInteger firstEffectId = [_effectsGridView effectIdAtRenderIndex:(NSUInteger)firstIdx];
            if (firstEffectId >= 0) {
                NSDictionary *info = [_engineBridge getEffect:firstEffectId];
                BOOL currentlyDisabled = [info[@"isRenderDisabled"] boolValue];
                [self effectsGrid:_effectsGridView didRequestSetRenderDisabled:!currentlyDisabled forEffects:selected];
            }
        } else {
            NSInteger targetRow = [self currentFocusedRow];
            if (targetRow >= 0 && targetRow < (NSInteger)_rowCount &&
                _rowData[targetRow].type != XLElementTypeTiming) {
                [self rowHeadings:_rowHeadingsView toggleRenderDisabledAtRow:targetRow];
            }
        }
        return YES;
    }

    // MARK: - Panel Toggles (xlmac-nzvp)

    if ([actionType isEqualToString:@"EFFECT_ASSIST_TOGGLE"]) {
        NSLog(@"XLSequencerViewController: EFFECT_ASSIST_TOGGLE - panel not yet implemented");
        return YES;
    }

    if ([actionType isEqualToString:@"COLOR_TOGGLE"]) {
        [[XLSwiftUIWindowHelper shared] toggleColorsPanel];
        return YES;
    }

    if ([actionType isEqualToString:@"LAYER_SETTING_TOGGLE"]) {
        [[XLSwiftUIWindowHelper shared] toggleLayerSettingsPanel];
        return YES;
    }

    if ([actionType isEqualToString:@"LAYER_BLENDING_TOGGLE"]) {
        [[XLSwiftUIWindowHelper shared] toggleLayerBlendingPanel];
        return YES;
    }

    if ([actionType isEqualToString:@"MODEL_PREVIEW_TOGGLE"]) {
        NSLog(@"XLSequencerViewController: MODEL_PREVIEW_TOGGLE - panel not yet implemented");
        return YES;
    }

    if ([actionType isEqualToString:@"HOUSE_PREVIEW_TOGGLE"]) {
        [self toggleHousePreview];
        return YES;
    }

    if ([actionType isEqualToString:@"EFFECTS_TOGGLE"]) {
        [[XLSwiftUIWindowHelper shared] toggleEffectsPanel];
        return YES;
    }

    if ([actionType isEqualToString:@"DISPLAY_ELEMENTS_TOGGLE"]) {
        NSLog(@"XLSequencerViewController: DISPLAY_ELEMENTS_TOGGLE - panel not yet implemented");
        return YES;
    }

    if ([actionType isEqualToString:@"JUKEBOX_TOGGLE"]) {
        NSLog(@"XLSequencerViewController: JUKEBOX_TOGGLE - panel not yet implemented");
        return YES;
    }

    if ([actionType isEqualToString:@"SEARCH_TOGGLE"]) {
        NSLog(@"XLSequencerViewController: SEARCH_TOGGLE - panel not yet implemented");
        return YES;
    }

    if ([actionType isEqualToString:@"PERSPECTIVES_TOGGLE"]) {
        NSLog(@"XLSequencerViewController: PERSPECTIVES_TOGGLE - panel not yet implemented");
        return YES;
    }

    if ([actionType isEqualToString:@"PRESETS_TOGGLE"]) {
        NSLog(@"XLSequencerViewController: PRESETS_TOGGLE - panel not yet implemented");
        return YES;
    }

    if ([actionType isEqualToString:@"VALUECURVES_TOGGLE"]) {
        NSLog(@"XLSequencerViewController: VALUECURVES_TOGGLE - panel not yet implemented");
        return YES;
    }

    if ([actionType isEqualToString:@"COLOR_DROPPER_TOGGLE"]) {
        NSLog(@"XLSequencerViewController: COLOR_DROPPER_TOGGLE - panel not yet implemented");
        return YES;
    }

    // FPP_CONNECT: Show FPP Connect window for device discovery and FSEQ upload
    if ([actionType isEqualToString:@"FPP_CONNECT"]) {
        [[NSApp delegate] performSelector:@selector(fppConnect:) withObject:nil];
        return YES;
    }

    // FOCUS_SEQUENCER: Force keyboard focus to the effects grid
    if ([actionType isEqualToString:@"FOCUS_SEQUENCER"]) {
        [self.view.window makeFirstResponder:_effectsGridView];
        NSLog(@"XLSequencerViewController: FOCUS_SEQUENCER - made effects grid first responder");
        return YES;
    }

    NSLog(@"XLSequencerViewController: Unhandled key action: %@", actionType);
    return NO;
}

#pragma mark - Snap Toggle

- (void)toggleSnap {
    BOOL newState = !_effectsGridView.snapToTimingMarks;
    _effectsGridView.snapToTimingMarks = newState;
    [[NSUserDefaults standardUserDefaults] setBool:newState forKey:@"SnapToTiming"];
    [[XLSwiftUIWindowHelper shared] setSnapEnabled:newState];
}

- (void)handleSnapEnabledDidChange:(NSNotification *)note {
    BOOL enabled = [note.userInfo[@"enabled"] boolValue];
    _effectsGridView.snapToTimingMarks = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"SnapToTiming"];
}

- (IBAction)toggleSnapToGrid:(id)sender {
    [self toggleSnap];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(toggleSnapToGrid:)) {
        menuItem.state = _effectsGridView.snapToTimingMarks ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (menuItem.action == @selector(toggleStemsPanel:)) {
        menuItem.state = _stemsPanelVisible ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    return YES;
}

- (void)toggleStemsPanel:(id)sender {
    _stemsPanelVisible = !_stemsPanelVisible;
    [[NSUserDefaults standardUserDefaults] setBool:_stemsPanelVisible forKey:@"StemsPanel.visible"];

    if (_stemsPanelVisible) {
        // Show: collapsed header or expanded, depending on state
        _stemsHeightConstraint.constant = _stemsContainerView.collapsed
            ? kStemsHeaderHeight : [_stemsContainerView currentHeight];
    } else {
        // Hide completely
        _stemsHeightConstraint.constant = 0;
    }
    [self.view layoutSubtreeIfNeeded];
}

#pragma mark - Zoom and Navigation Actions

static const CGFloat kZoomFactor = 1.5;

- (void)zoomIn:(id)sender {
    CGFloat currentZoom = _scrollCoordinator.zoomLevel;
    CGFloat newZoom = currentZoom * kZoomFactor;

    // Center zoom on playhead if playing, otherwise on view center
    CGFloat playheadMS = _transportBar.currentPositionMS;
    CGFloat playheadPixelX = playheadMS * currentZoom - _scrollCoordinator.horizontalScrollOffset;
    CGFloat viewWidth = NSWidth(_effectsGridView.bounds);

    if (playheadPixelX < 0 || playheadPixelX > viewWidth || playheadMS <= 0) {
        playheadPixelX = viewWidth / 2.0;
    }

    [_scrollCoordinator setZoomLevel:newZoom centeredOnPointX:playheadPixelX];
    [self saveZoomLevelForCurrentSequence];
}

- (void)zoomOut:(id)sender {
    CGFloat currentZoom = _scrollCoordinator.zoomLevel;
    CGFloat newZoom = currentZoom / kZoomFactor;

    // Center zoom on playhead if playing, otherwise on view center
    CGFloat playheadMS = _transportBar.currentPositionMS;
    CGFloat playheadPixelX = playheadMS * currentZoom - _scrollCoordinator.horizontalScrollOffset;
    CGFloat viewWidth = NSWidth(_effectsGridView.bounds);

    if (playheadPixelX < 0 || playheadPixelX > viewWidth || playheadMS <= 0) {
        playheadPixelX = viewWidth / 2.0;
    }

    [_scrollCoordinator setZoomLevel:newZoom centeredOnPointX:playheadPixelX];
    [self saveZoomLevelForCurrentSequence];
}

- (void)zoomToFit:(id)sender {
    CGFloat viewWidth = NSWidth(_effectsGridView.bounds);
    [_scrollCoordinator zoomToFitSequenceLength:_sequenceDurationMS viewWidth:viewWidth];
    [self saveZoomLevelForCurrentSequence];
}

- (void)seekToStart:(id)sender {
    [_playbackController seekToPositionMS:0];
}

- (void)seekToEnd:(id)sender {
    [_playbackController seekToPositionMS:(NSInteger)_sequenceDurationMS];
}

#pragma mark - Playback Actions (called from SwiftUI toolbar)

- (void)play {
    _transportBar.isPlaying = YES;
    [_engineBridge play];
    if (_playbackController) {
        [_playbackController play];
    }
    _timelineRuler.playing = YES;
}

- (void)pause {
    _transportBar.isPlaying = NO;
    [_engineBridge pause];
    if (_playbackController) {
        [_playbackController pause];
    }
    _timelineRuler.playing = NO;
}

- (void)stop {
    _transportBar.isPlaying = NO;
    _transportBar.currentPositionMS = 0.0;
    [_engineBridge stop];
    [_engineBridge seek:0];
    if (_playbackController) {
        [_playbackController stop];
    }
    _timelineRuler.playing = NO;
}

- (void)renderAll {
    [_engineBridge renderAll];
}

#pragma mark - XLStemsContainerDelegate

- (void)stemsContainer:(XLStemsContainerView *)container didChangeHeight:(CGFloat)newHeight {
    if (!_stemsPanelVisible) return;  // Panel hidden via menu — ignore height changes
    _stemsHeightConstraint.constant = newHeight;
    [self.view layoutSubtreeIfNeeded];
}

- (void)stemsContainerDidRequestImport:(XLStemsContainerView *)container {
    [self importAudioStems:nil];
}

- (void)stemsContainerDidRequestImportFromFolder:(XLStemsContainerView *)container {
    [self importStemsFromFolder:nil];
}

#pragma mark - Audio Stems Import

- (void)importAudioStems:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.allowedContentTypes = @[
        [UTType typeWithFilenameExtension:@"wav"],
        [UTType typeWithFilenameExtension:@"mp3"],
        [UTType typeWithFilenameExtension:@"m4a"],
        [UTType typeWithFilenameExtension:@"aac"],
        [UTType typeWithFilenameExtension:@"aiff"],
        [UTType typeWithFilenameExtension:@"flac"],
    ];
    panel.title = @"Import Audio Stems";
    panel.message = @"Select audio stem files (vocals, drums, bass, etc.)";

    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            [self->_stemManager importStemFiles:panel.URLs completion:nil];
        }
    }];
}

- (void)importStemsFromFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.title = @"Import Stems from Folder";
    panel.message = @"Select a folder containing audio stems (e.g., Demucs or Spleeter output)";

    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URLs.count > 0) {
            [self->_stemManager importStemsFromFolder:panel.URLs.firstObject completion:nil];
        }
    }];
}

- (void)removeAllAudioStems:(id)sender {
    if (_stemManager.stems.count == 0) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Remove All Audio Stems?";
    alert.informativeText = [NSString stringWithFormat:@"This will remove all %lu audio stems from the sequence.",
                             (unsigned long)_stemManager.stems.count];
    [alert addButtonWithTitle:@"Remove"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [self->_stemManager removeAllStems];
            self->_stemsContainerView.collapsed = YES;
            if (self->_stemsPanelVisible) {
                self->_stemsHeightConstraint.constant = kStemsHeaderHeight;
            }
            [self.view layoutSubtreeIfNeeded];
        }
    }];
}

@end
