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
#import "XLHousePreviewWindowController.h"
#import "XLEffectPropertiesViewController.h"
#import "dialogs/XLNewTimingDialog.h"
#import "dialogs/XLTimingImportDialog.h"

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

    // Empty state overlay (shown when no sequence is loaded)
    NSView *_emptyStateView;
    NSTextField *_recentLabel;
    NSStackView *_recentSequencesStack;

    // House preview floating window
    XLHousePreviewWindowController *_housePreviewController;
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

        // Empty state overlay: covers the row headings + effects grid area
        [_emptyStateView.topAnchor constraintEqualToAnchor:_waveformView.bottomAnchor],
        [_emptyStateView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_emptyStateView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_emptyStateView.bottomAnchor constraintEqualToAnchor:_transportBar.topAnchor],
    ]];

    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [_effectsGridView reloadData];
    [_rowHeadingsView reloadData];

    // Load audio if sequence has media file
    [self loadAudioForSequence];

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

    // Listen for command palette actions
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleZoomToSelection:)
                                                 name:@"XLZoomToSelection"
                                               object:nil];
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
    }

    NSWindow *previewWindow = _housePreviewController.window;
    if (previewWindow.isVisible) {
        [previewWindow orderOut:nil];
    } else {
        [previewWindow makeKeyAndOrderFront:nil];
        [_housePreviewController reloadModels];
    }
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

    // Load saved zoom level for this sequence (if any)
    [self loadZoomLevelForCurrentSequence];

    // Sync active timing track color with grid view
    [self updateActiveTimingColorIndex];
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
        NSLog(@"Loading effects for row %lu: name='%s' originalIndex=%ld layers=%ld",
              (unsigned long)i, row->name, (long)originalIndex, (long)row->effectLayerCount);
        for (NSInteger layer = 0; layer < row->effectLayerCount; layer++) {
            NSArray *effects = [self.engineBridge getEffectsForElementAtIndex:originalIndex layer:layer];
            NSLog(@"  Layer %ld: %lu effects", (long)layer, (unsigned long)effects.count);
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

                _effectCount++;
            }
        }
    }

    // Sort rows so timing tracks always appear at the top
    // This is the standard xLights behavior - timing tracks are always first
    [self sortRowsWithTimingFirst];

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

    NSLog(@"XLSequencerViewController: Loaded %lu rows with %lu effects from real sequence (duration: %.0f ms)",
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
    NSLog(@"Delete requested for %lu effects", (unsigned long)effectIndices.count);

    if (!_engineBridge || effectIndices.count == 0) return;

    // Collect all effect IDs to delete
    NSMutableArray<NSNumber *> *effectIdsToDelete = [NSMutableArray arrayWithCapacity:effectIndices.count];

    [effectIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSInteger effectId = [gridView effectIdAtRenderIndex:idx];
        if (effectId >= 0) {
            [effectIdsToDelete addObject:@(effectId)];
        }
    }];

    // Delete each effect via engine bridge
    for (NSNumber *effectIdNum in effectIdsToDelete) {
        NSInteger effectId = effectIdNum.integerValue;
        if (effectId >= 0) {
            [_engineBridge deleteEffect:effectId];
        }
    }

    // Reload data to reflect deletions
    [self reloadSequenceData];

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

- (NSInteger)rowHeadings:(XLRowHeadingsView *)view timingColorIndexForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rowCount || !_rowData) return 0;
    return _rowData[row].timingColorIndex;
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
            layerRow->timingColorIndex = mainRow->timingColorIndex;
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

    // Reload the grid views
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

- (void)handleZoomToSelection:(NSNotification *)notification {
    [_effectsGridView zoomToSelection];
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

    NSLog(@"XLSequencerViewController: Unhandled key action: %@", actionType);
    return NO;
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

@end
