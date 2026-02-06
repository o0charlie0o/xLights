/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLEffectsGridView.h"
#import "XLEffectsGridRenderer.h"
#import "XLUndoController.h"
#import <QuartzCore/CATransaction.h>

// Pasteboard type for effect drags from the palette
NSPasteboardType const XLEffectTypePasteboardType = @"com.xlights.effectType";

// Notification names for clipboard operations
NSNotificationName const XLEffectsGridDidCopyNotification = @"XLEffectsGridDidCopyNotification";
NSNotificationName const XLEffectsGridDidPasteNotification = @"XLEffectsGridDidPasteNotification";
NSNotificationName const XLEffectsGridDidCutNotification = @"XLEffectsGridDidCutNotification";

static const CGFloat kDefaultZoomLevel = 0.1;     // pixels per ms
static const CGFloat kDefaultMinZoom = 0.001;
static const CGFloat kDefaultMaxZoom = 5.0;
static const CGFloat kDefaultRowHeight = 22.0;
static const CGFloat kEdgeHitTestWidth = 6.0;      // pixels from edge to trigger resize
static const CGFloat kDragThreshold = 4.0;          // pixels before drag starts
static const CGFloat kMinimumEffectWidthMS = 10.0;  // minimum effect width in ms
static const CGFloat kSnapThresholdPixels = 5.0;    // pixel distance for snap-to-grid
static const CGFloat kDefaultDropDurationMS = 1000.0; // default effect duration for palette drops
static const CGFloat kGhostAlpha = 0.4;             // alpha for ghost/preview effect during drag

// Context menu item tags
static const NSInteger kMenuTagCut = 1001;
static const NSInteger kMenuTagCopy = 1002;
static const NSInteger kMenuTagPaste = 1003;
static const NSInteger kMenuTagDelete = 1004;
static const NSInteger kMenuTagEditSettings = 1005;
static const NSInteger kMenuTagSplit = 1010;
static const NSInteger kMenuTagDuplicate = 1011;
static const NSInteger kMenuTagDuplicateRight = 1012;
static const NSInteger kMenuTagDuplicateLeft = 1013;
static const NSInteger kMenuTagDuplicateUp = 1014;
static const NSInteger kMenuTagDuplicateDown = 1015;
static const NSInteger kMenuTagCreateTiming = 1020;
static const NSInteger kMenuTagLock = 1021;
static const NSInteger kMenuTagUnlock = 1022;
static const NSInteger kMenuTagEnableRender = 1023;
static const NSInteger kMenuTagDisableRender = 1024;
static const NSInteger kMenuTagDescription = 1025;
static const NSInteger kMenuTagResetEffect = 1026;
static const NSInteger kMenuTagEffectPresets = 1027;
static const NSInteger kMenuTagRandomEffects = 1028;
static const NSInteger kMenuTagTiming = 1029;

// Timing track context menu tags
static const NSInteger kMenuTagBreakdownPhrase = 1040;
static const NSInteger kMenuTagBreakdownSelectedPhrases = 1041;
static const NSInteger kMenuTagBreakdownWord = 1042;
static const NSInteger kMenuTagBreakdownSelectedWords = 1043;
static const NSInteger kMenuTagDivideTimings = 1044;
static const NSInteger kMenuTagAutoLabelTimings = 1045;
static const NSInteger kMenuTagAddShimmer = 1046;
static const NSInteger kMenuTagRemoveShimmer = 1047;
static const NSInteger kMenuTagCreateAlternatingPhonemes = 1048;
static const NSInteger kMenuTagFindTimingLabel = 1049;
static const NSInteger kMenuTagFindNextTimingLabel = 1050;
static const NSInteger kMenuTagFindPreviousTimingLabel = 1051;
static const NSInteger kMenuTagReplaceAllTimingLabels = 1052;

// Alignment submenu tags
static const NSInteger kMenuTagAlignStartTimes = 1060;
static const NSInteger kMenuTagAlignEndTimes = 1061;
static const NSInteger kMenuTagAlignBothTimes = 1062;
static const NSInteger kMenuTagAlignCenterpoints = 1063;
static const NSInteger kMenuTagAlignMatchDuration = 1064;
static const NSInteger kMenuTagAlignShiftStartTimes = 1065;
static const NSInteger kMenuTagAlignShiftEndTimes = 1066;
static const NSInteger kMenuTagAlignToTimingMark = 1067;
static const NSInteger kMenuTagCloseGap = 1068;

// Symbol library tags
static const NSInteger kMenuTagCreateSymbol = 1070;
static const NSInteger kMenuTagUnlinkSymbol = 1071;
static const NSInteger kMenuTagLinkSymbolBase = 1080;  // 1080+ for individual symbols

// Duplicate directions (passed as representedObject on menu items)
static const NSInteger kDuplicateDirectionNone = 0;
static const NSInteger kDuplicateDirectionRight = 1;
static const NSInteger kDuplicateDirectionLeft = 2;
static const NSInteger kDuplicateDirectionUp = 3;
static const NSInteger kDuplicateDirectionDown = 4;

// SF Symbol icon mapping for effect types (matching Swift EffectPaletteGridView)
static NSDictionary<NSString *, NSString *> *sEffectIconMapping = nil;

@interface XLEffectsGridView () <NSTextFieldDelegate> {
    dispatch_source_t _displayTimer;

    // Render-path snapshot: plain C arrays copied from the ObjC collections.
    // The render path (drawGrid → renderer) MUST NOT touch any ObjC object
    // ivars because the wxWidgets/C++ side of the process corrupts the ObjC
    // heap region where those pointers live.  Primitive C data is immune.
    CGFloat *_timingMarkValues;
    NSUInteger _timingMarkCount;
    XLEffectRenderInfo *_renderEffects;
    NSUInteger _renderEffectCount;

    // Selection tracking as C array (immune to heap corruption)
    BOOL *_selectedEffects;
    NSUInteger _selectedEffectsCapacity;
    NSUInteger _selectedEffectsCount;  // cached count for quick access

    // Icon overlay layer for drawing SF Symbols on effect blocks
    CALayer *_iconOverlayLayer;

    // Label overlay layer for drawing timing mark text labels
    CALayer *_labelOverlayLayer;

    // Inline label editor for timing marks
    NSTextField *_labelEditor;
    void (^_labelEditCompletion)(NSString * _Nullable);

    // Context menu state: saved when the menu is built
    CGFloat _contextMenuTimeMS;
    NSInteger _contextMenuEffectIndex;
    NSInteger _contextMenuRow;
}

@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) XLEffectsGridRenderer *renderer;

// Cached data from data source
@property (nonatomic, assign) NSInteger totalRows;
@property (nonatomic, assign) CGFloat sequenceLengthMS;
// NOTE: effectRenderInfos and timingMarks removed - using C arrays directly
// to avoid ObjC heap corruption from wxWidgets/C++ interop

// Mouse interaction state
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) BOOL isResizing;
@property (nonatomic, assign) BOOL isRubberBanding;
@property (nonatomic, assign) BOOL isMiddleMouseScrolling;
@property (nonatomic, assign) NSPoint mouseDownPoint;
@property (nonatomic, assign) NSPoint lastMousePoint;
@property (nonatomic, assign) CGPoint mouseDownScrollOffset;
@property (nonatomic, assign) NSInteger mouseDownRow;
@property (nonatomic, assign) NSInteger mouseDownEffectIndex;
@property (nonatomic, assign) XLEffectHitLocation mouseDownHitLocation;
@property (nonatomic, assign) CGFloat dragStartTimeMS;
@property (nonatomic, assign) CGFloat dragOriginalStartMS;
@property (nonatomic, assign) CGFloat dragOriginalEndMS;

// Cross-row drag state
@property (nonatomic, assign) NSInteger dragCurrentRow;
@property (nonatomic, assign) CGFloat dragCurrentStartMS;

// Slip-drag: adjacent timing mark that moves with the dragged edge
@property (nonatomic, assign) NSInteger adjacentEffectIndex;
@property (nonatomic, assign) CGFloat adjacentOriginalStartMS;
@property (nonatomic, assign) CGFloat adjacentOriginalEndMS;

// Undo state - captured snapshot at drag/resize start
@property (nonatomic, assign) XLEffectSnapshot undoSnapshot;
@property (nonatomic, assign) BOOL hasUndoSnapshot;

// Rubber band selection
@property (nonatomic, assign) NSPoint rubberBandOrigin;
@property (nonatomic, assign) NSPoint rubberBandCurrent;

// Multi-selection (synthesized from C array on demand for delegate callbacks)

// Palette drop state
@property (nonatomic, assign) BOOL isReceivingDrop;
@property (nonatomic, assign) NSInteger dropTargetRow;
@property (nonatomic, assign) CGFloat dropTargetStartMS;
@property (nonatomic, assign) CGFloat dropTargetEndMS;
@property (nonatomic, copy) NSString *dropEffectType;

// Display link
@property (nonatomic, assign) BOOL needsRedraw;
@property (nonatomic, assign) BOOL isDrawing;  // Guard against concurrent draws

@end

@implementation XLEffectsGridView

#pragma mark - Class Initialization

+ (void)initialize {
    if (self == [XLEffectsGridView class]) {
        // Initialize the effect icon mapping (matching Swift EffectPaletteGridView)
        sEffectIconMapping = @{
            @"Adjust": @"slider.horizontal.3",
            @"Arpeggio": @"music.note.list",
            @"Bars": @"chart.bar.fill",
            @"Butterfly": @"bird.fill",
            @"Candle": @"flame",
            @"Circles": @"circle.grid.3x3.fill",
            @"ColorWash": @"paintbrush.fill",
            @"Curtain": @"rectangle.split.2x1.fill",
            @"DMX": @"slider.vertical.3",
            @"Duplicate": @"plus.square.on.square",
            @"Faces": @"face.smiling.fill",
            @"Fan": @"fan.fill",
            @"Fill": @"square.fill",
            @"Fire": @"flame.fill",
            @"Fireworks": @"sparkles",
            @"Galaxy": @"staroflife.fill",
            @"Garlands": @"leaf.fill",
            @"Glediator": @"square.grid.3x3.fill",
            @"Guitar": @"guitars.fill",
            @"Kaleidoscope": @"camera.filters",
            @"Life": @"heart.fill",
            @"Lightning": @"bolt.fill",
            @"Lines": @"line.3.horizontal",
            @"Liquid": @"drop.fill",
            @"Marquee": @"text.badge.star",
            @"Meteors": @"moonphase.waning.crescent",
            @"Morph": @"arrow.triangle.2.circlepath",
            @"MovingHead": @"light.beacon.max.fill",
            @"Music": @"music.note",
            @"Off": @"power.circle",
            @"On": @"lightbulb.fill",
            @"Piano": @"pianokeys",
            @"Pictures": @"photo.fill",
            @"Pinwheel": @"rotate.3d",
            @"Plasma": @"waveform",
            @"Ripple": @"drop.circle.fill",
            @"Servo": @"gearshape.2.fill",
            @"Shader": @"paintpalette.fill",
            @"Shape": @"star.fill",
            @"Shimmer": @"sparkle",
            @"Shockwave": @"waveform.circle.fill",
            @"SingleStrand": @"line.diagonal",
            @"Sketch": @"pencil.tip",
            @"Snowflakes": @"snowflake",
            @"Snowstorm": @"cloud.snow.fill",
            @"Spirals": @"tornado",
            @"Spirograph": @"circle.circle",
            @"State": @"switch.2",
            @"Strobe": @"light.max",
            @"Tendril": @"leaf.arrow.circlepath",
            @"Text": @"textformat",
            @"Tree": @"tree.fill",
            @"Twinkle": @"sparkles",
            @"Video": @"video.fill",
            @"VUMeter": @"chart.bar.fill",
            @"Warp": @"arrow.up.and.down.and.arrow.left.and.right",
            @"Wave": @"water.waves"
        };
    }
}

#pragma mark - Initialization

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _zoomLevel = kDefaultZoomLevel;
    _minZoomLevel = kDefaultMinZoom;
    _maxZoomLevel = kDefaultMaxZoom;
    _rowHeight = kDefaultRowHeight;
    _playbackPositionMS = -1;
    _scrollOffset = CGPointZero;
    _selectedEffectID = -1;
    _totalRows = 0;
    _sequenceLengthMS = 0;
    // NOTE: Using C arrays directly for effects and timing marks
    // to avoid ObjC heap corruption from wxWidgets/C++ interop
    _timingMarkValues = NULL;
    _timingMarkCount = 0;
    _renderEffects = NULL;
    _renderEffectCount = 0;
    _needsRedraw = YES;
    _snapToTimingMarks = YES;
    _selectedEffects = NULL;
    _selectedEffectsCapacity = 0;
    _selectedEffectsCount = 0;

    // Disable icon drawing for performance testing
    _disableIconDrawing = YES;

    // Drop state
    _isReceivingDrop = NO;
    _dropTargetRow = -1;
    _dropTargetStartMS = 0;
    _dropTargetEndMS = 0;
    _dropEffectType = nil;

    // Cross-row drag state
    _dragCurrentRow = -1;
    _dragCurrentStartMS = 0;

    // Set up Metal layer - must set layer before wantsLayer for layer-hosting views
    _metalLayer = [CAMetalLayer layer];
    _metalLayer.device = MTLCreateSystemDefaultDevice();
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.contentsScale = self.window.backingScaleFactor ?: 2.0;
    _metalLayer.framebufferOnly = YES;
    self.layer = _metalLayer;
    self.wantsLayer = YES;

    // Initialize renderer (may return nil if Metal is unavailable)
    _renderer = [[XLEffectsGridRenderer alloc] initWithLayer:_metalLayer];
    if (!_renderer) {
        NSLog(@"XLEffectsGridView: Metal renderer unavailable, grid will not render");
    }

    // Add icon overlay layer on top of Metal layer
    _iconOverlayLayer = [CALayer layer];
    _iconOverlayLayer.contentsScale = self.window.backingScaleFactor ?: 2.0;
    _iconOverlayLayer.frame = self.bounds;
    _iconOverlayLayer.backgroundColor = nil;  // Transparent
    // Disable all implicit animations on this layer to keep it in sync with Metal
    _iconOverlayLayer.actions = @{
        @"contents": [NSNull null],
        @"bounds": [NSNull null],
        @"position": [NSNull null],
        @"frame": [NSNull null]
    };
    [self.layer addSublayer:_iconOverlayLayer];

    // Add label overlay layer for timing mark text (below icon overlay, above Metal)
    _labelOverlayLayer = [CALayer layer];
    _labelOverlayLayer.contentsScale = self.window.backingScaleFactor ?: 2.0;
    _labelOverlayLayer.frame = self.bounds;
    _labelOverlayLayer.backgroundColor = nil;
    _labelOverlayLayer.actions = @{
        @"contents": [NSNull null],
        @"bounds": [NSNull null],
        @"position": [NSNull null],
        @"frame": [NSNull null]
    };
    // Insert below icon overlay so icons draw on top
    [self.layer insertSublayer:_labelOverlayLayer below:_iconOverlayLayer];

    // Display timer is created lazily in viewDidMoveToWindow when the view
    // first gets a window. Starting it here (before the view has a window,
    // proper frame, or backing layer) can cause renders with corrupt state.

    // Accept mouse events
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited
                                  | NSTrackingMouseMoved
                                  | NSTrackingActiveInActiveApp
                                  | NSTrackingInVisibleRect;
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                               options:options
                                                                 owner:self
                                                              userInfo:nil];
    [self addTrackingArea:trackingArea];

    // Register for drag types (palette drops)
    [self registerForDraggedTypes:@[XLEffectTypePasteboardType]];
}

- (void)setupDisplayTimer {
    if (_displayTimer) return;

    dispatch_source_t timer = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    // ~60 fps with 4ms leeway for power efficiency
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              NSEC_PER_SEC / 60,
                              NSEC_PER_MSEC * 4);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf.needsRedraw && strongSelf.window) {
            [strongSelf drawGrid];
        }
    });
    dispatch_resume(timer);
    _displayTimer = timer;
}

- (void)stopDisplayTimer {
    if (_displayTimer) {
        dispatch_source_cancel(_displayTimer);
        _displayTimer = nil;
    }
}

- (void)dealloc {
    [self stopDisplayTimer];
    free(_timingMarkValues);
    _timingMarkValues = NULL;
    _timingMarkCount = 0;
    free(_renderEffects);
    _renderEffects = NULL;
    _renderEffectCount = 0;
    free(_selectedEffects);
    _selectedEffects = NULL;
    _selectedEffectsCapacity = 0;
    _selectedEffectsCount = 0;
}

#pragma mark - Selection C Array Helpers

/// Ensure the selection array has capacity for at least `count` effects.
- (void)ensureSelectionCapacity:(NSUInteger)count {
    if (count <= _selectedEffectsCapacity) return;

    NSUInteger newCapacity = MAX(count, _selectedEffectsCapacity * 2);
    if (newCapacity < 64) newCapacity = 64;

    BOOL *newArray = (BOOL *)calloc(newCapacity, sizeof(BOOL));
    if (_selectedEffects && _selectedEffectsCapacity > 0) {
        memcpy(newArray, _selectedEffects, _selectedEffectsCapacity * sizeof(BOOL));
        free(_selectedEffects);
    }
    _selectedEffects = newArray;
    _selectedEffectsCapacity = newCapacity;
}

/// Check if an effect index is selected.
- (BOOL)isEffectSelected:(NSUInteger)idx {
    if (idx >= _selectedEffectsCapacity) return NO;
    return _selectedEffects[idx];
}

/// Select an effect at the given index.
- (void)selectEffectAtIndex:(NSUInteger)idx {
    [self ensureSelectionCapacity:idx + 1];
    if (!_selectedEffects[idx]) {
        _selectedEffects[idx] = YES;
        _selectedEffectsCount++;
    }
}

/// Deselect an effect at the given index.
- (void)deselectEffectAtIndex:(NSUInteger)idx {
    if (idx >= _selectedEffectsCapacity) return;
    if (_selectedEffects[idx]) {
        _selectedEffects[idx] = NO;
        _selectedEffectsCount--;
    }
}

/// Clear all selections.
- (void)clearAllSelections {
    if (_selectedEffects && _selectedEffectsCapacity > 0) {
        memset(_selectedEffects, 0, _selectedEffectsCapacity * sizeof(BOOL));
    }
    _selectedEffectsCount = 0;
}

/// Get the first selected index, or NSNotFound if none.
- (NSUInteger)firstSelectedIndex {
    for (NSUInteger i = 0; i < _selectedEffectsCapacity; i++) {
        if (_selectedEffects[i]) return i;
    }
    return NSNotFound;
}

/// Synthesize an NSMutableIndexSet from the C selection array (for delegate callbacks).
- (NSMutableIndexSet *)selectedEffectIndices {
    NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < _selectedEffectsCapacity; i++) {
        if (_selectedEffects[i]) {
            [indices addIndex:i];
        }
    }
    return indices;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        _metalLayer.contentsScale = self.window.backingScaleFactor;
        _iconOverlayLayer.contentsScale = self.window.backingScaleFactor;
        _labelOverlayLayer.contentsScale = self.window.backingScaleFactor;
        if (!_displayTimer) {
            [self setupDisplayTimer];
        }
    } else {
        [self stopDisplayTimer];
    }
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];

    // Disable implicit animations during resize to keep Metal and overlay layers in sync
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    _metalLayer.drawableSize = CGSizeMake(newSize.width * _metalLayer.contentsScale,
                                           newSize.height * _metalLayer.contentsScale);
    _iconOverlayLayer.frame = CGRectMake(0, 0, newSize.width, newSize.height);
    _labelOverlayLayer.frame = CGRectMake(0, 0, newSize.width, newSize.height);

    [CATransaction commit];

    _needsRedraw = YES;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

#pragma mark - Data Loading

- (void)reloadData {
    // Safety check: ensure we're on the main thread and the view is valid
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadData];
        });
        return;
    }

    // Safety check: if the view has been deallocated or is in an invalid state, bail out
    if (!self.window && !_metalLayer) {
        return;
    }

    // Free old C arrays first (immune to corruption)
    free(_timingMarkValues);
    _timingMarkValues = NULL;
    _timingMarkCount = 0;

    free(_renderEffects);
    _renderEffects = NULL;
    _renderEffectCount = 0;

    if (!_dataSource) {
        _totalRows = 0;
        _sequenceLengthMS = 0;
        _needsRedraw = YES;
        return;
    }

    @try {
        _totalRows = [_dataSource numberOfRowsInEffectsGrid:self];
        _sequenceLengthMS = [_dataSource sequenceLengthMSForEffectsGrid:self];
    } @catch (NSException *exception) {
        NSLog(@"XLEffectsGridView: Exception getting basic data: %@ - %@",
              exception.name, exception.reason);
        _totalRows = 0;
        _sequenceLengthMS = 0;
        _needsRedraw = YES;
        return;
    }

    // Validate data
    if (_totalRows < 0) _totalRows = 0;
    if (_sequenceLengthMS < 0) _sequenceLengthMS = 0;

    // Convert timing marks directly to a plain C array for the render path.
    // This avoids ALL ObjC message sends / ARC retain-release during drawing,
    // making the render path immune to heap corruption of ObjC object pointers.
    NSArray<NSNumber *> *timingMarks = nil;
    if ([_dataSource respondsToSelector:@selector(timingMarksForEffectsGrid:)]) {
        timingMarks = [_dataSource timingMarksForEffectsGrid:self];
    }

    NSUInteger timingCount = timingMarks.count;
    if (timingCount > 0) {
        _timingMarkValues = (CGFloat *)malloc(timingCount * sizeof(CGFloat));
        if (_timingMarkValues) {
            for (NSUInteger i = 0; i < timingCount; i++) {
                _timingMarkValues[i] = [timingMarks[i] doubleValue];
            }
            _timingMarkCount = timingCount;
        }
    }

    // Count total effects first to allocate C array in one shot
    NSUInteger totalEffects = 0;
    for (NSInteger row = 0; row < _totalRows; row++) {
        totalEffects += [_dataSource effectsGrid:self numberOfEffectsInRow:row];
    }

    // Allocate C array for effects directly (bypassing ObjC collections entirely)
    if (totalEffects > 0) {
        _renderEffects = (XLEffectRenderInfo *)malloc(totalEffects * sizeof(XLEffectRenderInfo));
        if (_renderEffects) {
            NSUInteger idx = 0;
            for (NSInteger row = 0; row < _totalRows; row++) {
                @try {
                    NSInteger effectCount = [_dataSource effectsGrid:self numberOfEffectsInRow:row];
                    for (NSInteger i = 0; i < effectCount && idx < totalEffects; i++) {
                        XLEffectRenderInfo info = [_dataSource effectsGrid:self effectInfoForRow:row atIndex:i];
                        info.row = row;
                        _renderEffects[idx++] = info;
                    }
                } @catch (NSException *exception) {
                    NSLog(@"XLEffectsGridView: Exception getting effects for row %ld: %@ - %@",
                          (long)row, exception.name, exception.reason);
                    // Skip this row and continue with the next
                }
            }
            _renderEffectCount = idx;
        } else {
            NSLog(@"XLEffectsGridView: Failed to allocate memory for %lu effects",
                  (unsigned long)totalEffects);
        }
    }

    // Ensure selection array can accommodate all effects
    [self ensureSelectionCapacity:_renderEffectCount];

    _needsRedraw = YES;
}

// syncRenderSnapshot removed - _renderEffects is now populated directly in reloadData
// to avoid using ObjC collections (NSMutableArray) which are vulnerable to heap corruption

#pragma mark - Drawing

- (void)setNeedsDisplay {
    _needsRedraw = YES;
}

- (void)drawGrid {
    if (!_renderer || !_metalLayer || !self.window) return;
    if (_isDrawing) return;  // Prevent concurrent draws which cause jitter

    _isDrawing = YES;
    _needsRedraw = NO;

    CGSize viewSize = _metalLayer.drawableSize;
    if (viewSize.width <= 0 || viewSize.height <= 0) return;

    CGFloat scale = _metalLayer.contentsScale;
    CGPoint scaledScroll = CGPointMake(_scrollOffset.x * scale, _scrollOffset.y * scale);
    CGFloat scaledRowHeight = _rowHeight * scale;
    CGFloat scaledZoom = _zoomLevel * scale;

    // Calculate rubber band rect in scaled coordinates
    NSRect rubberBandRect = NSZeroRect;
    if (_isRubberBanding) {
        CGFloat x1 = _rubberBandOrigin.x * scale;
        CGFloat y1 = _rubberBandOrigin.y * scale;
        CGFloat x2 = _rubberBandCurrent.x * scale;
        CGFloat y2 = _rubberBandCurrent.y * scale;
        rubberBandRect = NSMakeRect(MIN(x1, x2), MIN(y1, y2),
                                    fabs(x2 - x1), fabs(y2 - y1));
    }

    // Pass only plain C arrays to the renderer — no ObjC collections.
    // The wxWidgets/C++ heap corruption overwrites ObjC object pointers
    // stored as ivars, so we must never touch NSArray during rendering.
    [_renderer drawInLayer:_metalLayer
                  viewSize:viewSize
              scrollOffset:scaledScroll
                 zoomLevel:scaledZoom
                 rowHeight:scaledRowHeight
                 totalRows:_totalRows
          sequenceLengthMS:_sequenceLengthMS
                   effects:_renderEffects
              effectCount:_renderEffectCount
          selectedEffectID:_selectedEffectID
       playbackPositionMS:_playbackPositionMS
         timingMarkValues:_timingMarkValues
          timingMarkCount:_timingMarkCount
  activeTimingColorIndex:_activeTimingColorIndex
            dropIndicator:_isReceivingDrop
                  dropRow:_dropTargetRow
              dropStartMS:_dropTargetStartMS
                dropEndMS:_dropTargetEndMS
         rubberBandActive:_isRubberBanding
           rubberBandRect:rubberBandRect];

    // Draw timing mark labels on their own overlay layer
    [self drawTimingLabels];

    // Draw effect icons on the overlay layer (can be disabled for performance testing)
    if (!_disableIconDrawing) {
        [self drawEffectIcons];
    } else {
        _iconOverlayLayer.contents = nil;
    }

    _isDrawing = NO;
}

- (void)drawTimingLabels {
    if (!_renderEffects || _renderEffectCount == 0) {
        _labelOverlayLayer.contents = nil;
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    _labelOverlayLayer.frame = self.bounds;

    CGFloat viewHeight = self.bounds.size.height;
    CGFloat viewWidth = self.bounds.size.width;
    if (viewWidth < 1 || viewHeight < 1) {
        _labelOverlayLayer.contents = nil;
        [CATransaction commit];
        return;
    }

    // Calculate visible region
    CGFloat msPerPixel = 1.0 / _zoomLevel;
    CGFloat visibleStartMS = _scrollOffset.x * msPerPixel;
    CGFloat visibleEndMS = visibleStartMS + viewWidth * msPerPixel;
    CGFloat visibleStartRow = _scrollOffset.y / _rowHeight;
    CGFloat visibleEndRow = (viewHeight + _scrollOffset.y) / _rowHeight;

    // Check if we have any visible timing labels at all
    // Only draw labels for lyric tracks (multi-layer timing tracks, not plain timing)
    BOOL hasLabels = NO;
    for (NSUInteger i = 0; i < _renderEffectCount; i++) {
        XLEffectRenderInfo info = _renderEffects[i];
        if (!info.isTimingMark || info.label[0] == '\0') continue;
        if (info.timingTrackLayerCount <= 1) continue;
        if (info.endTimeMS < visibleStartMS || info.startTimeMS > visibleEndMS) continue;
        if (info.row < (NSInteger)floor(visibleStartRow) - 1 ||
            info.row > (NSInteger)ceil(visibleEndRow) + 1) continue;
        hasLabels = YES;
        break;
    }

    if (!hasLabels) {
        _labelOverlayLayer.contents = nil;
        [CATransaction commit];
        return;
    }

    // Create image for drawing labels (bottom-left origin since view is flipped)
    NSImage *labelImage = [[NSImage alloc] initWithSize:self.bounds.size];
    [labelImage lockFocus];

    NSFont *labelFont = [NSFont systemFontOfSize:9.0 weight:NSFontWeightMedium];
    NSDictionary *textAttrs = @{
        NSFontAttributeName: labelFont,
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };

    for (NSUInteger i = 0; i < _renderEffectCount; i++) {
        XLEffectRenderInfo info = _renderEffects[i];
        if (!info.isTimingMark || info.label[0] == '\0') continue;
        if (info.timingTrackLayerCount <= 1) continue; // Skip plain timing tracks

        // Frustum culling
        if (info.endTimeMS < visibleStartMS || info.startTimeMS > visibleEndMS) continue;
        if (info.row < (NSInteger)floor(visibleStartRow) - 1 ||
            info.row > (NSInteger)ceil(visibleEndRow) + 1) continue;

        CGFloat x1 = info.startTimeMS * _zoomLevel - _scrollOffset.x;
        CGFloat x2 = info.endTimeMS * _zoomLevel - _scrollOffset.x;
        CGFloat blockWidth = x2 - x1;
        if (blockWidth < 10.0) continue; // Too narrow for text

        NSString *text = [NSString stringWithUTF8String:info.label];
        if (!text || text.length == 0) continue;

        NSSize textSize = [text sizeWithAttributes:textAttrs];

        // View Y is top-left origin (flipped view), NSImage is bottom-left origin
        CGFloat viewY = info.row * _rowHeight - _scrollOffset.y;
        CGFloat viewCenterY = viewY + _rowHeight / 2.0;

        // Convert to image coordinates (bottom-left origin)
        CGFloat imageY = viewHeight - viewCenterY - textSize.height / 2.0;

        // Center text horizontally, clipped to block width
        CGFloat padding = 4.0;
        CGFloat textW = MIN(textSize.width, blockWidth - padding * 2);
        CGFloat textX = x1 + (blockWidth - textW) / 2.0;

        NSRect textRect = NSMakeRect(textX, imageY, textW, textSize.height);
        [text drawWithRect:textRect
                   options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine
                attributes:textAttrs context:nil];
    }

    [labelImage unlockFocus];

    _labelOverlayLayer.contents = labelImage;

    [CATransaction commit];
}

- (void)drawEffectIcons {
    if (!_renderEffects || _renderEffectCount == 0) {
        _iconOverlayLayer.contents = nil;
        return;
    }

    // Disable implicit animations to prevent jitter during resize
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // Update overlay layer frame to match view bounds
    _iconOverlayLayer.frame = self.bounds;

    CGFloat viewHeight = self.bounds.size.height;

    // Only draw icons if effect blocks are wide enough (minimum 24pt)
    CGFloat minWidthForIcons = 24.0;

    // Create image context for drawing icons
    // NSImage uses bottom-left origin by default, same as our view's coordinate calculations
    // when we account for the flip. We'll calculate positions directly without a global flip.
    NSImage *iconImage = [[NSImage alloc] initWithSize:self.bounds.size];
    [iconImage lockFocus];

    // Calculate visible region
    CGFloat msPerPixel = 1.0 / _zoomLevel;
    CGFloat visibleStartMS = _scrollOffset.x * msPerPixel;
    CGFloat visibleEndMS = visibleStartMS + self.bounds.size.width * msPerPixel;
    CGFloat visibleStartRow = _scrollOffset.y / _rowHeight;
    CGFloat visibleEndRow = (self.bounds.size.height + _scrollOffset.y) / _rowHeight;

    // Draw icons for visible effects (skip timing marks — they have text labels instead)
    for (NSUInteger i = 0; i < _renderEffectCount; i++) {
        XLEffectRenderInfo info = _renderEffects[i];
        if (info.isTimingMark) continue;

        // Skip effects outside visible region
        if (info.endTimeMS < visibleStartMS || info.startTimeMS > visibleEndMS) continue;
        if (info.row < (NSInteger)floor(visibleStartRow) - 1 ||
            info.row > (NSInteger)ceil(visibleEndRow) + 1) continue;

        // Calculate effect block position
        CGFloat x1 = info.startTimeMS * _zoomLevel - _scrollOffset.x;
        CGFloat x2 = info.endTimeMS * _zoomLevel - _scrollOffset.x;
        CGFloat effectWidth = x2 - x1;

        // Skip if effect is too narrow for an icon
        if (effectWidth < minWidthForIcons) continue;

        // Calculate Y in view coordinates (flipped: row 0 at top)
        // Our view is flipped (top-left origin), but NSImage is not (bottom-left origin)
        // So we need to convert: imageY = viewHeight - viewY - height
        CGFloat viewY = info.row * _rowHeight - _scrollOffset.y;
        CGFloat centerX = (x1 + x2) / 2.0;

        // Get the SF Symbol for this effect type
        NSString *effectTypeName = [NSString stringWithUTF8String:info.effectTypeName];
        if (effectTypeName.length == 0) continue;

        NSString *symbolName = sEffectIconMapping[effectTypeName];
        if (!symbolName) symbolName = @"questionmark.square.fill";

        NSImage *symbolImage = [NSImage imageWithSystemSymbolName:symbolName
                                         accessibilityDescription:effectTypeName];
        if (!symbolImage) continue;

        // Configure symbol for white color
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:10
                                                                                             weight:NSFontWeightMedium];
        config = [config configurationByApplyingConfiguration:
                  [NSImageSymbolConfiguration configurationWithPaletteColors:@[[NSColor whiteColor]]]];
        NSImage *configuredSymbol = [symbolImage imageWithSymbolConfiguration:config];

        // Calculate icon size and position (centered in the effect block)
        CGFloat iconSize = MIN(14.0, effectWidth - 4.0);

        // Convert view coordinates (top-left origin) to image coordinates (bottom-left origin)
        // viewY is the top of the row in view coords
        // centerY in view coords = viewY + rowHeight/2
        // In image coords (bottom-left origin): imageY = viewHeight - viewCenterY - iconSize/2
        CGFloat viewCenterY = viewY + _rowHeight / 2.0;
        CGFloat imageY = viewHeight - viewCenterY - iconSize / 2.0;

        CGRect iconRect = CGRectMake(centerX - iconSize / 2.0,
                                     imageY,
                                     iconSize, iconSize);

        // Draw the symbol (it will render right-side up in image coordinates)
        [configuredSymbol drawInRect:iconRect];
    }

    [iconImage unlockFocus];

    // Set the image as layer contents
    _iconOverlayLayer.contents = iconImage;

    [CATransaction commit];
}

#pragma mark - Coordinate Conversion

- (void)convertPoint:(NSPoint)viewPoint toTimeMS:(CGFloat *)outTimeMS row:(NSInteger *)outRow {
    if (outTimeMS) {
        *outTimeMS = (viewPoint.x + _scrollOffset.x) / _zoomLevel;
    }
    if (outRow) {
        *outRow = (NSInteger)floor((viewPoint.y + _scrollOffset.y) / _rowHeight);
    }
}

- (NSPoint)pointForTimeMS:(CGFloat)timeMS row:(NSInteger)row {
    CGFloat x = timeMS * _zoomLevel - _scrollOffset.x;
    CGFloat y = row * _rowHeight - _scrollOffset.y;
    return NSMakePoint(x, y);
}

#pragma mark - Scrolling

- (void)scrollToTimeMS:(CGFloat)timeMS {
    CGFloat x = timeMS * _zoomLevel - self.bounds.size.width * 0.5;
    _scrollOffset = CGPointMake(MAX(0, x), _scrollOffset.y);
    _needsRedraw = YES;

    if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeScrollOffset:)]) {
        [_delegate effectsGrid:self didChangeScrollOffset:_scrollOffset];
    }
}

- (void)setPlaybackPositionMS:(CGFloat)positionMS animated:(BOOL)animated {
    _playbackPositionMS = positionMS;
    _needsRedraw = YES;
    // Trigger immediate redraw for responsive playhead updates
    [self.layer setNeedsDisplay];
}

- (void)clampScrollOffset {
    CGFloat maxScrollX = MAX(0, _sequenceLengthMS * _zoomLevel - self.bounds.size.width);
    CGFloat maxScrollY = MAX(0, _totalRows * _rowHeight - self.bounds.size.height);

    _scrollOffset = CGPointMake(
        MAX(0, MIN(_scrollOffset.x, maxScrollX)),
        MAX(0, MIN(_scrollOffset.y, maxScrollY))
    );
}

#pragma mark - Snap-to-Grid

- (CGFloat)snapTimeMS:(CGFloat)timeMS {
    if (!_snapToTimingMarks) return timeMS;

    CGFloat snapThresholdMS = kSnapThresholdPixels / _zoomLevel;
    CGFloat bestSnap = timeMS;
    CGFloat bestDistance = snapThresholdMS + 1;

    // Snap to timing marks (uses pre-computed C array)
    for (NSUInteger i = 0; i < _timingMarkCount; i++) {
        CGFloat markMS = _timingMarkValues[i];
        CGFloat dist = fabs(timeMS - markMS);
        if (dist < bestDistance) {
            bestDistance = dist;
            bestSnap = markMS;
        }
    }

    // Also snap to sequence start and end
    if (fabs(timeMS) < snapThresholdMS) {
        if (fabs(timeMS) < bestDistance) {
            bestSnap = 0;
            bestDistance = fabs(timeMS);
        }
    }
    if (fabs(timeMS - _sequenceLengthMS) < snapThresholdMS) {
        if (fabs(timeMS - _sequenceLengthMS) < bestDistance) {
            bestSnap = _sequenceLengthMS;
        }
    }

    if (bestDistance <= snapThresholdMS) {
        return bestSnap;
    }
    return timeMS;
}

- (CGFloat)timingGridSnapInterval {
    if ([_dataSource respondsToSelector:@selector(timingGridSnapIntervalMSForEffectsGrid:)]) {
        CGFloat interval = [_dataSource timingGridSnapIntervalMSForEffectsGrid:self];
        if (interval > 0) return interval;
    }
    return 0;
}

#pragma mark - Selection Management

- (void)updateSelectionState {
    // Update the selected flags directly in the C render array — immune to heap corruption
    for (NSUInteger i = 0; i < _renderEffectCount; i++) {
        _renderEffects[i].selected = [self isEffectSelected:i];
    }
}

- (void)notifySelectionChanged {
    if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeSelection:)]) {
        [_delegate effectsGrid:self didChangeSelection:[self selectedEffectIndices]];
    }
}

- (void)clearSelection {
    [self clearAllSelections];
    _selectedEffectID = -1;
    [self updateSelectionState];
    [self notifySelectionChanged];
    _needsRedraw = YES;
}

- (void)selectAllEffectsInRow:(NSInteger)row {
    [self clearAllSelections];
    _selectedEffectID = -1;

    for (NSUInteger i = 0; i < _renderEffectCount; i++) {
        if (_renderEffects[i].row == row) {
            [self selectEffectAtIndex:i];
            if (_selectedEffectID < 0) {
                _selectedEffectID = (NSInteger)i;
            }
        }
    }

    [self updateSelectionState];
    [self notifySelectionChanged];
    _needsRedraw = YES;
}

- (void)zoomToSelection {
    if (_renderEffectCount == 0) return;

    // Find the time range of all selected effects
    CGFloat minTime = CGFLOAT_MAX;
    CGFloat maxTime = -CGFLOAT_MAX;
    NSUInteger selectedCount = 0;

    for (NSUInteger i = 0; i < _renderEffectCount; i++) {
        BOOL isSelected = (i < _selectedEffectsCapacity && _selectedEffects[i]);
        if (!isSelected && (NSInteger)i == _selectedEffectID) {
            isSelected = YES;
        }
        if (isSelected) {
            XLEffectRenderInfo info = _renderEffects[i];
            if (info.startTimeMS < minTime) minTime = info.startTimeMS;
            if (info.endTimeMS > maxTime) maxTime = info.endTimeMS;
            selectedCount++;
        }
    }

    if (selectedCount == 0 || minTime >= maxTime) return;

    // Add 10% padding on each side
    CGFloat range = maxTime - minTime;
    CGFloat padding = range * 0.1;
    minTime -= padding;
    maxTime += padding;
    if (minTime < 0) minTime = 0;

    // Calculate zoom level to fit the selection in the visible width
    CGFloat visibleWidth = self.bounds.size.width;
    if (visibleWidth <= 0) return;

    CGFloat newZoom = visibleWidth / (maxTime - minTime);
    newZoom = MAX(self.minZoomLevel, MIN(self.maxZoomLevel, newZoom));

    self.zoomLevel = newZoom;
    self.scrollOffset = CGPointMake(minTime * newZoom, self.scrollOffset.y);

    _needsRedraw = YES;

    if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeZoomLevel:)]) {
        [_delegate effectsGrid:self didChangeZoomLevel:newZoom];
    }
    if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeScrollOffset:)]) {
        [_delegate effectsGrid:self didChangeScrollOffset:self.scrollOffset];
    }
}

- (NSInteger)rowForEffectIndex:(NSInteger)effectIndex {
    if (effectIndex < 0 || (NSUInteger)effectIndex >= _renderEffectCount) return -1;
    return _renderEffects[effectIndex].row;
}

- (NSInteger)effectIdAtRenderIndex:(NSUInteger)index {
    if (index < _renderEffectCount) {
        return _renderEffects[index].effectId;
    }
    return -1;
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event {
    // Handle double-click (AppKit delivers double-clicks as mouseDown with clickCount==2)
    if (event.clickCount == 2) {
        NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
        CGFloat timeMS;
        NSInteger row;
        [self convertPoint:loc toTimeMS:&timeMS row:&row];

        NSInteger hitEffectIndex = -1;
        XLEffectHitLocation hitLoc;
        [self hitTestPoint:loc effectIndex:&hitEffectIndex hitLocation:&hitLoc];

        if (hitEffectIndex >= 0) {
            if ([_delegate respondsToSelector:@selector(effectsGrid:didDoubleClickEffectAtRow:effectIndex:)]) {
                [_delegate effectsGrid:self didDoubleClickEffectAtRow:row effectIndex:hitEffectIndex];
            }
        }
        return;
    }

    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    _mouseDownPoint = loc;
    _lastMousePoint = loc;
    _isDragging = NO;
    _isResizing = NO;
    _isRubberBanding = NO;

    CGFloat timeMS;
    NSInteger row;
    [self convertPoint:loc toTimeMS:&timeMS row:&row];
    _mouseDownRow = row;
    _dragCurrentRow = row;

    // Find effect at click location
    NSInteger hitEffectIndex = -1;
    XLEffectHitLocation hitLoc = XLEffectHitLocationNone;
    [self hitTestPoint:loc effectIndex:&hitEffectIndex hitLocation:&hitLoc];

    _mouseDownEffectIndex = hitEffectIndex;
    _mouseDownHitLocation = hitLoc;

    BOOL shiftDown = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    BOOL cmdDown = (event.modifierFlags & NSEventModifierFlagCommand) != 0;

    if (hitEffectIndex >= 0) {
        if (shiftDown) {
            // Shift+click: extend selection from primary to this effect
            if (_selectedEffectID >= 0) {
                NSInteger startIdx = MIN(_selectedEffectID, hitEffectIndex);
                NSInteger endIdx = MAX(_selectedEffectID, hitEffectIndex);
                for (NSInteger i = startIdx; i <= endIdx; i++) {
                    [self selectEffectAtIndex:i];
                }
            } else {
                [self selectEffectAtIndex:hitEffectIndex];
                _selectedEffectID = hitEffectIndex;
            }
        } else if (cmdDown) {
            // Cmd+click: toggle individual selection
            if ([self isEffectSelected:hitEffectIndex]) {
                [self deselectEffectAtIndex:hitEffectIndex];
                if (_selectedEffectID == hitEffectIndex) {
                    _selectedEffectID = (_selectedEffectsCount > 0)
                        ? (NSInteger)[self firstSelectedIndex]
                        : -1;
                }
            } else {
                [self selectEffectAtIndex:hitEffectIndex];
                _selectedEffectID = hitEffectIndex;
            }
        } else {
            // Plain click: select only this effect (unless it's already part of multi-selection
            // and user might be about to drag)
            if (![self isEffectSelected:hitEffectIndex]) {
                [self clearAllSelections];
                [self selectEffectAtIndex:hitEffectIndex];
                _selectedEffectID = hitEffectIndex;
            }
            // If already in selection, keep multi-selection intact for potential drag.
            // On mouseUp without drag, narrow to single selection.
        }

        [self updateSelectionState];
        [self notifySelectionChanged];
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(effectsGrid:didSelectEffectAtRow:effectIndex:)]) {
            [_delegate effectsGrid:self didSelectEffectAtRow:row effectIndex:hitEffectIndex];
        }

        // Store original timing for potential drag/resize
        if (hitEffectIndex >= 0 && (NSUInteger)hitEffectIndex < _renderEffectCount) {
            _dragOriginalStartMS = _renderEffects[hitEffectIndex].startTimeMS;
            _dragOriginalEndMS = _renderEffects[hitEffectIndex].endTimeMS;

            // Capture undo snapshot before any changes
            if (_undoController) {
                XLEffectRenderInfo info = _renderEffects[hitEffectIndex];
                _undoSnapshot.effectID = hitEffectIndex;
                _undoSnapshot.row = info.row;
                _undoSnapshot.layer = info.layer;
                _undoSnapshot.startTimeMS = info.startTimeMS;
                _undoSnapshot.endTimeMS = info.endTimeMS;
                _undoSnapshot.effectTypeIndex = info.effectIndex;
                _undoSnapshot.colorARGB = info.colorARGB;
                _undoSnapshot.selected = info.selected;
                _undoSnapshot.locked = info.locked;
                _undoSnapshot.renderDisabled = info.renderDisabled;
                _hasUndoSnapshot = YES;
            }
        }
        // Find adjacent timing mark for slip-drag
        _adjacentEffectIndex = -1;
        if (hitEffectIndex >= 0 && (NSUInteger)hitEffectIndex < _renderEffectCount &&
            _renderEffects[hitEffectIndex].isTimingMark) {
            NSInteger dragRow = _renderEffects[hitEffectIndex].row;

            if (hitLoc == XLEffectHitLocationLeftEdge) {
                CGFloat ourStart = _dragOriginalStartMS;
                for (NSUInteger i = 0; i < _renderEffectCount; i++) {
                    if ((NSInteger)i == hitEffectIndex) continue;
                    if (!_renderEffects[i].isTimingMark) continue;
                    if (_renderEffects[i].row != dragRow) continue;
                    if (fabs(_renderEffects[i].endTimeMS - ourStart) < 1.0) {
                        _adjacentEffectIndex = (NSInteger)i;
                        _adjacentOriginalStartMS = _renderEffects[i].startTimeMS;
                        _adjacentOriginalEndMS = _renderEffects[i].endTimeMS;
                        break;
                    }
                }
            } else if (hitLoc == XLEffectHitLocationRightEdge) {
                CGFloat ourEnd = _dragOriginalEndMS;
                for (NSUInteger i = 0; i < _renderEffectCount; i++) {
                    if ((NSInteger)i == hitEffectIndex) continue;
                    if (!_renderEffects[i].isTimingMark) continue;
                    if (_renderEffects[i].row != dragRow) continue;
                    if (fabs(_renderEffects[i].startTimeMS - ourEnd) < 1.0) {
                        _adjacentEffectIndex = (NSInteger)i;
                        _adjacentOriginalStartMS = _renderEffects[i].startTimeMS;
                        _adjacentOriginalEndMS = _renderEffects[i].endTimeMS;
                        break;
                    }
                }
            }
        }

        _dragStartTimeMS = timeMS;
    } else {
        // Clicked on empty area
        if (!shiftDown && !cmdDown) {
            [self clearSelection];
        }

        if ([_delegate respondsToSelector:@selector(effectsGrid:didClickAtTimeMS:row:)]) {
            [_delegate effectsGrid:self didClickAtTimeMS:timeMS row:row];
        }

        // Start rubber band selection
        _rubberBandOrigin = loc;
        _rubberBandCurrent = loc;
    }
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = loc.x - _mouseDownPoint.x;
    CGFloat dy = loc.y - _mouseDownPoint.y;
    CGFloat distance = sqrt(dx * dx + dy * dy);

    if (distance < kDragThreshold && !_isDragging && !_isResizing && !_isRubberBanding) {
        return;
    }

    BOOL optionDown = (event.modifierFlags & NSEventModifierFlagOption) != 0;
    BOOL snapEnabled = _snapToTimingMarks && !optionDown;

    if (_mouseDownEffectIndex >= 0 && !_isDragging && !_isResizing) {
        if (_mouseDownHitLocation == XLEffectHitLocationLeftEdge ||
            _mouseDownHitLocation == XLEffectHitLocationRightEdge) {
            _isResizing = YES;
        } else {
            _isDragging = YES;
        }
    } else if (_mouseDownEffectIndex < 0 && !_isRubberBanding) {
        _isRubberBanding = YES;
    }

    if (_isResizing && _mouseDownEffectIndex >= 0) {
        CGFloat timeMS;
        [self convertPoint:loc toTimeMS:&timeMS row:NULL];
        CGFloat deltaMS = timeMS - _dragStartTimeMS;

        CGFloat newStart = _dragOriginalStartMS;
        CGFloat newEnd = _dragOriginalEndMS;

        if (_mouseDownHitLocation == XLEffectHitLocationLeftEdge) {
            newStart = _dragOriginalStartMS + deltaMS;
            newStart = MAX(0, MIN(newStart, newEnd - kMinimumEffectWidthMS));
            if (snapEnabled) {
                newStart = [self snapTimeMS:newStart];
                newStart = MIN(newStart, newEnd - kMinimumEffectWidthMS);
            }
            // Slip-drag: clamp to left neighbor's minimum width and update its right edge
            if (_adjacentEffectIndex >= 0) {
                CGFloat neighborMinEnd = _adjacentOriginalStartMS + kMinimumEffectWidthMS;
                newStart = MAX(newStart, neighborMinEnd);
                if ((NSUInteger)_adjacentEffectIndex < _renderEffectCount) {
                    _renderEffects[_adjacentEffectIndex].endTimeMS = newStart;
                }
            }
        } else {
            newEnd = _dragOriginalEndMS + deltaMS;
            newEnd = MAX(newStart + kMinimumEffectWidthMS, MIN(newEnd, _sequenceLengthMS));
            if (snapEnabled) {
                newEnd = [self snapTimeMS:newEnd];
                newEnd = MAX(newStart + kMinimumEffectWidthMS, newEnd);
            }
            // Slip-drag: clamp to right neighbor's minimum width and update its left edge
            if (_adjacentEffectIndex >= 0) {
                CGFloat neighborMaxStart = _adjacentOriginalEndMS - kMinimumEffectWidthMS;
                newEnd = MIN(newEnd, neighborMaxStart);
                if ((NSUInteger)_adjacentEffectIndex < _renderEffectCount) {
                    _renderEffects[_adjacentEffectIndex].startTimeMS = newEnd;
                }
            }
        }

        // Update the C array directly for visual feedback — immune to heap corruption
        if ((NSUInteger)_mouseDownEffectIndex < _renderEffectCount) {
            _renderEffects[_mouseDownEffectIndex].startTimeMS = newStart;
            _renderEffects[_mouseDownEffectIndex].endTimeMS = newEnd;
        }

        _needsRedraw = YES;
    } else if (_isDragging && _mouseDownEffectIndex >= 0) {
        CGFloat timeMS;
        NSInteger targetRow;
        [self convertPoint:loc toTimeMS:&timeMS row:&targetRow];
        targetRow = MAX(0, MIN(targetRow, _totalRows - 1));

        CGFloat deltaMS = timeMS - _dragStartTimeMS;
        CGFloat duration = _dragOriginalEndMS - _dragOriginalStartMS;
        CGFloat newStart = _dragOriginalStartMS + deltaMS;
        newStart = MAX(0, MIN(newStart, _sequenceLengthMS - duration));

        if (snapEnabled) {
            CGFloat snappedStart = [self snapTimeMS:newStart];
            CGFloat snappedEnd = [self snapTimeMS:newStart + duration];
            CGFloat snapDeltaStart = fabs(snappedStart - newStart);
            CGFloat snapDeltaEnd = fabs(snappedEnd - (newStart + duration));

            if (snapDeltaStart <= snapDeltaEnd && snapDeltaStart <= (kSnapThresholdPixels / _zoomLevel)) {
                newStart = snappedStart;
            } else if (snapDeltaEnd <= (kSnapThresholdPixels / _zoomLevel)) {
                newStart = snappedEnd - duration;
            }
            newStart = MAX(0, MIN(newStart, _sequenceLengthMS - duration));
        }

        _dragCurrentRow = targetRow;
        _dragCurrentStartMS = newStart;

        // Update the C array directly for visual feedback — immune to heap corruption
        if ((NSUInteger)_mouseDownEffectIndex < _renderEffectCount) {
            _renderEffects[_mouseDownEffectIndex].startTimeMS = newStart;
            _renderEffects[_mouseDownEffectIndex].endTimeMS = newStart + duration;
            _renderEffects[_mouseDownEffectIndex].row = targetRow;
        }

        _needsRedraw = YES;
    } else if (_isRubberBanding) {
        _rubberBandCurrent = loc;
        [self updateRubberBandSelection];
        _needsRedraw = YES;
    }

    _lastMousePoint = loc;
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    BOOL shiftDown = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    BOOL cmdDown = (event.modifierFlags & NSEventModifierFlagCommand) != 0;

    if (_isResizing && _mouseDownEffectIndex >= 0 && (NSUInteger)_mouseDownEffectIndex < _renderEffectCount) {
        XLEffectRenderInfo info = _renderEffects[_mouseDownEffectIndex];

        // Register undo action for resize
        if (_undoController && _hasUndoSnapshot) {
            [_undoController captureEffectToBeResized:_undoSnapshot actionName:@"Resize Effect"];
        }

        if ([_delegate respondsToSelector:@selector(effectsGrid:didResizeEffectAtRow:effectIndex:newStartTimeMS:newEndTimeMS:)]) {
            [_delegate effectsGrid:self
               didResizeEffectAtRow:info.row
                      effectIndex:_mouseDownEffectIndex
                    newStartTimeMS:info.startTimeMS
                      newEndTimeMS:info.endTimeMS];

            // Also resize the adjacent mark that was slip-dragged
            if (_adjacentEffectIndex >= 0 && (NSUInteger)_adjacentEffectIndex < _renderEffectCount) {
                XLEffectRenderInfo adjInfo = _renderEffects[_adjacentEffectIndex];
                [_delegate effectsGrid:self
                   didResizeEffectAtRow:adjInfo.row
                          effectIndex:_adjacentEffectIndex
                        newStartTimeMS:adjInfo.startTimeMS
                          newEndTimeMS:adjInfo.endTimeMS];
            }
        }
    } else if (_isDragging && _mouseDownEffectIndex >= 0 && (NSUInteger)_mouseDownEffectIndex < _renderEffectCount) {
        XLEffectRenderInfo info = _renderEffects[_mouseDownEffectIndex];

        // Register undo action for move
        if (_undoController && _hasUndoSnapshot) {
            [_undoController captureEffectToBeMoved:_undoSnapshot actionName:@"Move Effect"];
        }

        if (_dragCurrentRow != _mouseDownRow) {
            // Cross-row move
            if ([_delegate respondsToSelector:@selector(effectsGrid:didMoveEffectAtRow:effectIndex:toRow:toTimeMS:)]) {
                [_delegate effectsGrid:self
                  didMoveEffectAtRow:_mouseDownRow
                        effectIndex:_mouseDownEffectIndex
                              toRow:_dragCurrentRow
                          toTimeMS:info.startTimeMS];
            }
        } else {
            // Same-row move
            if ([_delegate respondsToSelector:@selector(effectsGrid:didMoveEffectAtRow:effectIndex:toTimeMS:)]) {
                [_delegate effectsGrid:self
                  didMoveEffectAtRow:_mouseDownRow
                        effectIndex:_mouseDownEffectIndex
                          toTimeMS:info.startTimeMS];
            }
        }
    } else if (_isRubberBanding) {
        CGFloat startTimeMS, endTimeMS;
        NSInteger startRow, endRow;
        [self convertPoint:_rubberBandOrigin toTimeMS:&startTimeMS row:&startRow];
        [self convertPoint:_rubberBandCurrent toTimeMS:&endTimeMS row:&endRow];

        if (startTimeMS > endTimeMS) {
            CGFloat tmp = startTimeMS; startTimeMS = endTimeMS; endTimeMS = tmp;
        }
        if (startRow > endRow) {
            NSInteger tmp = startRow; startRow = endRow; endRow = tmp;
        }

        if ([_delegate respondsToSelector:@selector(effectsGrid:didSelectRangeFromRow:toRow:fromTimeMS:toTimeMS:)]) {
            [_delegate effectsGrid:self
              didSelectRangeFromRow:startRow
                             toRow:endRow
                        fromTimeMS:startTimeMS
                          toTimeMS:endTimeMS];
        }
    } else if (_mouseDownEffectIndex >= 0 && !shiftDown && !cmdDown) {
        // Plain click without drag: narrow to single selection
        [self clearAllSelections];
        [self selectEffectAtIndex:_mouseDownEffectIndex];
        _selectedEffectID = _mouseDownEffectIndex;
        [self updateSelectionState];
        [self notifySelectionChanged];
    }

    _isDragging = NO;
    _isResizing = NO;
    _isRubberBanding = NO;
    _dragCurrentRow = -1;
    _adjacentEffectIndex = -1;
    _hasUndoSnapshot = NO;
    _needsRedraw = YES;
}

- (void)rightMouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat timeMS;
    NSInteger row;
    [self convertPoint:loc toTimeMS:&timeMS row:&row];

    NSInteger hitEffectIndex = -1;
    XLEffectHitLocation hitLoc;
    [self hitTestPoint:loc effectIndex:&hitEffectIndex hitLocation:&hitLoc];

    if (hitEffectIndex >= 0) {
        // Select the right-clicked effect if not already selected
        if (![self isEffectSelected:hitEffectIndex]) {
            [self clearAllSelections];
            [self selectEffectAtIndex:hitEffectIndex];
            _selectedEffectID = hitEffectIndex;
            [self updateSelectionState];
            [self notifySelectionChanged];
        }
        _needsRedraw = YES;
    }

    NSMenu *menu = nil;

    if ([_delegate respondsToSelector:@selector(effectsGrid:contextMenuForRow:effectIndex:atTimeMS:)]) {
        menu = [_delegate effectsGrid:self
                    contextMenuForRow:row
                         effectIndex:hitEffectIndex
                            atTimeMS:timeMS];
    }

    if (!menu) {
        menu = [self buildDefaultContextMenuForRow:row effectIndex:hitEffectIndex atTimeMS:timeMS];
    }

    if (menu) {
        [NSMenu popUpContextMenu:menu withEvent:event forView:self];
    }
}

- (NSMenu *)buildDefaultContextMenuForRow:(NSInteger)row
                             effectIndex:(NSInteger)effectIndex
                                atTimeMS:(CGFloat)timeMS {
    // Save context menu state for action handlers
    _contextMenuTimeMS = timeMS;
    _contextMenuEffectIndex = effectIndex;
    _contextMenuRow = row;

    // Detect if the right-clicked item is a timing mark
    BOOL isTimingMark = NO;
    NSInteger timingLayerIndex = -1;
    NSInteger timingTrackLayerCount = 1;
    BOOL hasMultipleTimingSelected = NO;
    if (effectIndex >= 0 && effectIndex < (NSInteger)_renderEffectCount) {
        XLEffectRenderInfo info = _renderEffects[effectIndex];
        isTimingMark = info.isTimingMark;
        if (isTimingMark) {
            timingTrackLayerCount = info.timingTrackLayerCount;
            // Determine which layer of the timing track this mark is on
            // Layer is stored in the render info
            timingLayerIndex = info.layer;
            // Check if multiple timing marks are selected
            NSUInteger selectedTimingCount = 0;
            for (NSUInteger idx = 0; idx < _renderEffectCount; idx++) {
                if ([self isEffectSelected:idx] && _renderEffects[idx].isTimingMark) {
                    selectedTimingCount++;
                }
            }
            hasMultipleTimingSelected = (selectedTimingCount > 1);
        }
    }

    if (isTimingMark) {
        return [self buildTimingContextMenuWithLayerIndex:timingLayerIndex
                                       layerCount:timingTrackLayerCount
                                  multipleSelected:hasMultipleTimingSelected];
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Effects"];

    BOOL hasSelection = _selectedEffectsCount > 0;
    BOOL hasSingleEffect = (effectIndex >= 0);
    BOOL multipleSelected = _selectedEffectsCount > 1;

    // --- Cut / Copy / Paste / Delete ---

    NSMenuItem *cutItem = [[NSMenuItem alloc] initWithTitle:@"Cut"
                                                    action:@selector(cut:)
                                             keyEquivalent:@"x"];
    cutItem.tag = kMenuTagCut;
    cutItem.target = self;
    cutItem.enabled = hasSelection;
    [menu addItem:cutItem];

    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy"
                                                     action:@selector(copy:)
                                              keyEquivalent:@"c"];
    copyItem.tag = kMenuTagCopy;
    copyItem.target = self;
    copyItem.enabled = hasSelection;
    [menu addItem:copyItem];

    NSMenuItem *pasteItem = [[NSMenuItem alloc] initWithTitle:@"Paste"
                                                      action:@selector(paste:)
                                               keyEquivalent:@"v"];
    pasteItem.tag = kMenuTagPaste;
    pasteItem.target = self;
    [menu addItem:pasteItem];

    NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete"
                                                       action:@selector(deleteSelectedEffects:)
                                                keyEquivalent:@""];
    deleteItem.tag = kMenuTagDelete;
    deleteItem.target = self;
    deleteItem.enabled = hasSelection;
    [menu addItem:deleteItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Edit Effect Settings ---

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit Effect Settings..."
                                                     action:@selector(editEffectSettings:)
                                              keyEquivalent:@""];
    editItem.tag = kMenuTagEditSettings;
    editItem.target = self;
    editItem.enabled = hasSingleEffect;
    [menu addItem:editItem];

    // --- Split Effect ---

    BOOL canSplit = hasSingleEffect;
    if (canSplit && effectIndex < (NSInteger)_renderEffectCount) {
        XLEffectRenderInfo info = _renderEffects[effectIndex];
        CGFloat durationMS = info.endTimeMS - info.startTimeMS;
        if (durationMS <= kMinimumEffectWidthMS * 2.0 ||
            timeMS <= info.startTimeMS || timeMS >= info.endTimeMS) {
            canSplit = NO;
        }
    }
    NSMenuItem *splitItem = [[NSMenuItem alloc] initWithTitle:@"Split Effect"
                                                      action:@selector(splitEffect:)
                                               keyEquivalent:@""];
    splitItem.tag = kMenuTagSplit;
    splitItem.target = self;
    splitItem.enabled = canSplit;
    [menu addItem:splitItem];

    // --- Create Timing from Effect ---

    NSMenuItem *createTimingItem = [[NSMenuItem alloc] initWithTitle:@"Create Timing"
                                                             action:@selector(createTimingFromEffect:)
                                                      keyEquivalent:@""];
    createTimingItem.tag = kMenuTagCreateTiming;
    createTimingItem.target = self;
    createTimingItem.enabled = hasSelection;
    [menu addItem:createTimingItem];

    // --- Duplicate Submenu ---

    NSMenu *dupMenu = [[NSMenu alloc] initWithTitle:@"Duplicate"];

    NSMenuItem *dupItem = [[NSMenuItem alloc] initWithTitle:@"Duplicate"
                                                    action:@selector(duplicateEffect:)
                                             keyEquivalent:@""];
    dupItem.tag = kMenuTagDuplicate;
    dupItem.target = self;
    dupItem.representedObject = @(kDuplicateDirectionNone);
    dupItem.enabled = hasSingleEffect;
    [dupMenu addItem:dupItem];

    [dupMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *dupRight = [[NSMenuItem alloc] initWithTitle:@"Duplicate Right"
                                                     action:@selector(duplicateEffect:)
                                              keyEquivalent:@""];
    dupRight.tag = kMenuTagDuplicateRight;
    dupRight.target = self;
    dupRight.representedObject = @(kDuplicateDirectionRight);
    dupRight.enabled = hasSelection;
    [dupMenu addItem:dupRight];

    NSMenuItem *dupLeft = [[NSMenuItem alloc] initWithTitle:@"Duplicate Left"
                                                    action:@selector(duplicateEffect:)
                                             keyEquivalent:@""];
    dupLeft.tag = kMenuTagDuplicateLeft;
    dupLeft.target = self;
    dupLeft.representedObject = @(kDuplicateDirectionLeft);
    dupLeft.enabled = hasSelection;
    [dupMenu addItem:dupLeft];

    NSMenuItem *dupUp = [[NSMenuItem alloc] initWithTitle:@"Duplicate Up"
                                                  action:@selector(duplicateEffect:)
                                           keyEquivalent:@""];
    dupUp.tag = kMenuTagDuplicateUp;
    dupUp.target = self;
    dupUp.representedObject = @(kDuplicateDirectionUp);
    dupUp.enabled = hasSelection;
    [dupMenu addItem:dupUp];

    NSMenuItem *dupDown = [[NSMenuItem alloc] initWithTitle:@"Duplicate Down"
                                                    action:@selector(duplicateEffect:)
                                             keyEquivalent:@""];
    dupDown.tag = kMenuTagDuplicateDown;
    dupDown.target = self;
    dupDown.representedObject = @(kDuplicateDirectionDown);
    dupDown.enabled = hasSelection;
    [dupMenu addItem:dupDown];

    NSMenuItem *dupSubmenu = [[NSMenuItem alloc] initWithTitle:@"Duplicate"
                                                       action:nil
                                                keyEquivalent:@""];
    dupSubmenu.submenu = dupMenu;
    [menu addItem:dupSubmenu];

    // --- Alignment Submenu (requires multiple effects selected) ---

    NSMenu *alignMenu = [[NSMenu alloc] initWithTitle:@"Alignment"];

    NSMenuItem *alignStart = [[NSMenuItem alloc] initWithTitle:@"Align Start Times"
                                                       action:@selector(alignEffects:)
                                                keyEquivalent:@""];
    alignStart.tag = kMenuTagAlignStartTimes;
    alignStart.target = self;
    alignStart.representedObject = @(XLAlignmentTypeStartTimes);
    alignStart.enabled = multipleSelected;
    [alignMenu addItem:alignStart];

    NSMenuItem *alignEnd = [[NSMenuItem alloc] initWithTitle:@"Align End Times"
                                                     action:@selector(alignEffects:)
                                              keyEquivalent:@""];
    alignEnd.tag = kMenuTagAlignEndTimes;
    alignEnd.target = self;
    alignEnd.representedObject = @(XLAlignmentTypeEndTimes);
    alignEnd.enabled = multipleSelected;
    [alignMenu addItem:alignEnd];

    NSMenuItem *alignBoth = [[NSMenuItem alloc] initWithTitle:@"Align Both Times"
                                                      action:@selector(alignEffects:)
                                               keyEquivalent:@""];
    alignBoth.tag = kMenuTagAlignBothTimes;
    alignBoth.target = self;
    alignBoth.representedObject = @(XLAlignmentTypeBothTimes);
    alignBoth.enabled = multipleSelected;
    [alignMenu addItem:alignBoth];

    NSMenuItem *alignCenter = [[NSMenuItem alloc] initWithTitle:@"Align Centerpoints"
                                                        action:@selector(alignEffects:)
                                                 keyEquivalent:@""];
    alignCenter.tag = kMenuTagAlignCenterpoints;
    alignCenter.target = self;
    alignCenter.representedObject = @(XLAlignmentTypeCenterpoints);
    alignCenter.enabled = multipleSelected;
    [alignMenu addItem:alignCenter];

    NSMenuItem *alignDuration = [[NSMenuItem alloc] initWithTitle:@"Align Match Duration"
                                                          action:@selector(alignEffects:)
                                                   keyEquivalent:@""];
    alignDuration.tag = kMenuTagAlignMatchDuration;
    alignDuration.target = self;
    alignDuration.representedObject = @(XLAlignmentTypeMatchDuration);
    alignDuration.enabled = multipleSelected;
    [alignMenu addItem:alignDuration];

    NSMenuItem *shiftStart = [[NSMenuItem alloc] initWithTitle:@"Shift Align Start Times"
                                                       action:@selector(alignEffects:)
                                                keyEquivalent:@""];
    shiftStart.tag = kMenuTagAlignShiftStartTimes;
    shiftStart.target = self;
    shiftStart.representedObject = @(XLAlignmentTypeShiftStartTimes);
    shiftStart.enabled = multipleSelected;
    [alignMenu addItem:shiftStart];

    NSMenuItem *shiftEnd = [[NSMenuItem alloc] initWithTitle:@"Shift Align End Times"
                                                     action:@selector(alignEffects:)
                                              keyEquivalent:@""];
    shiftEnd.tag = kMenuTagAlignShiftEndTimes;
    shiftEnd.target = self;
    shiftEnd.representedObject = @(XLAlignmentTypeShiftEndTimes);
    shiftEnd.enabled = multipleSelected;
    [alignMenu addItem:shiftEnd];

    NSMenuItem *alignTiming = [[NSMenuItem alloc] initWithTitle:@"Align To Closest Timing Mark"
                                                        action:@selector(alignEffects:)
                                                 keyEquivalent:@""];
    alignTiming.tag = kMenuTagAlignToTimingMark;
    alignTiming.target = self;
    alignTiming.representedObject = @(XLAlignmentTypeToClosestTimingMark);
    alignTiming.enabled = hasSelection;
    [alignMenu addItem:alignTiming];

    NSMenuItem *closeGap = [[NSMenuItem alloc] initWithTitle:@"Close Gap"
                                                     action:@selector(alignEffects:)
                                              keyEquivalent:@""];
    closeGap.tag = kMenuTagCloseGap;
    closeGap.target = self;
    closeGap.representedObject = @(XLAlignmentTypeCloseGap);
    closeGap.enabled = multipleSelected;
    [alignMenu addItem:closeGap];

    NSMenuItem *alignSubmenu = [[NSMenuItem alloc] initWithTitle:@"Alignment"
                                                         action:nil
                                                  keyEquivalent:@""];
    alignSubmenu.submenu = alignMenu;
    [menu addItem:alignSubmenu];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Effect Presets / Random Effects ---

    NSMenuItem *presetsItem = [[NSMenuItem alloc] initWithTitle:@"Effect Presets"
                                                        action:@selector(effectPresets:)
                                                 keyEquivalent:@""];
    presetsItem.tag = kMenuTagEffectPresets;
    presetsItem.target = self;
    [menu addItem:presetsItem];

    NSMenuItem *randomItem = [[NSMenuItem alloc] initWithTitle:@"Create Random Effects"
                                                       action:@selector(createRandomEffects:)
                                                keyEquivalent:@""];
    randomItem.tag = kMenuTagRandomEffects;
    randomItem.target = self;
    [menu addItem:randomItem];

    // --- Reset Effect ---

    NSMenuItem *resetItem = [[NSMenuItem alloc] initWithTitle:@"Reset Effect"
                                                      action:@selector(resetEffect:)
                                               keyEquivalent:@""];
    resetItem.tag = kMenuTagResetEffect;
    resetItem.target = self;
    resetItem.enabled = hasSingleEffect;
    [menu addItem:resetItem];

    // --- Description ---

    NSMenuItem *descItem = [[NSMenuItem alloc] initWithTitle:@"Description"
                                                     action:@selector(editDescription:)
                                              keyEquivalent:@""];
    descItem.tag = kMenuTagDescription;
    descItem.target = self;
    descItem.enabled = hasSelection;
    [menu addItem:descItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Lock / Unlock ---

    BOOL anyLocked = NO;
    BOOL anyUnlocked = NO;
    BOOL anyRenderDisabled = NO;
    BOOL anyRenderEnabled = NO;
    for (NSUInteger idx = 0; idx < _renderEffectCount; idx++) {
        if ([self isEffectSelected:idx]) {
            XLEffectRenderInfo info = _renderEffects[idx];
            if (info.locked) anyLocked = YES;
            else anyUnlocked = YES;
            if (info.renderDisabled) anyRenderDisabled = YES;
            else anyRenderEnabled = YES;
        }
    }

    NSMenuItem *lockItem = [[NSMenuItem alloc] initWithTitle:@"Lock"
                                                      action:@selector(lockEffects:)
                                               keyEquivalent:@""];
    lockItem.tag = kMenuTagLock;
    lockItem.target = self;
    lockItem.enabled = hasSelection && anyUnlocked;
    [menu addItem:lockItem];

    NSMenuItem *unlockItem = [[NSMenuItem alloc] initWithTitle:@"Unlock"
                                                       action:@selector(unlockEffects:)
                                                keyEquivalent:@""];
    unlockItem.tag = kMenuTagUnlock;
    unlockItem.target = self;
    unlockItem.enabled = hasSelection && anyLocked;
    [menu addItem:unlockItem];

    // --- Enable / Disable Render ---

    NSMenuItem *disableRenderItem = [[NSMenuItem alloc] initWithTitle:@"Disable Render"
                                                              action:@selector(disableRender:)
                                                       keyEquivalent:@""];
    disableRenderItem.tag = kMenuTagDisableRender;
    disableRenderItem.target = self;
    disableRenderItem.enabled = hasSelection && anyRenderEnabled;
    [menu addItem:disableRenderItem];

    NSMenuItem *enableRenderItem = [[NSMenuItem alloc] initWithTitle:@"Enable Render"
                                                              action:@selector(enableRender:)
                                                       keyEquivalent:@""];
    enableRenderItem.tag = kMenuTagEnableRender;
    enableRenderItem.target = self;
    enableRenderItem.enabled = hasSelection && anyRenderDisabled;
    [menu addItem:enableRenderItem];

    // --- Symbol Library ---

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *createSymbol = [[NSMenuItem alloc] initWithTitle:@"Create Symbol from Effect..."
                                                         action:@selector(createSymbolFromEffect:)
                                                  keyEquivalent:@""];
    createSymbol.tag = kMenuTagCreateSymbol;
    createSymbol.target = self;
    createSymbol.enabled = hasSingleEffect && !multipleSelected;
    [menu addItem:createSymbol];

    NSMenuItem *unlinkSymbol = [[NSMenuItem alloc] initWithTitle:@"Unlink from Symbol"
                                                         action:@selector(unlinkFromSymbol:)
                                                  keyEquivalent:@""];
    unlinkSymbol.tag = kMenuTagUnlinkSymbol;
    unlinkSymbol.target = self;
    unlinkSymbol.enabled = hasSelection;
    [menu addItem:unlinkSymbol];

    // Link to Symbol submenu (placeholder - populated dynamically when symbols exist)
    NSMenu *linkMenu = [[NSMenu alloc] initWithTitle:@"Link to Symbol"];
    NSMenuItem *linkPlaceholder = [[NSMenuItem alloc] initWithTitle:@"(No symbols defined)"
                                                            action:nil
                                                     keyEquivalent:@""];
    linkPlaceholder.enabled = NO;
    [linkMenu addItem:linkPlaceholder];

    NSMenuItem *linkSubmenu = [[NSMenuItem alloc] initWithTitle:@"Link to Symbol"
                                                        action:nil
                                                 keyEquivalent:@""];
    linkSubmenu.submenu = linkMenu;
    linkSubmenu.enabled = hasSelection;
    [menu addItem:linkSubmenu];

    // --- Timing (edit effect start/end time) ---

    BOOL canEditTiming = hasSingleEffect && !multipleSelected;
    if (canEditTiming && effectIndex < (NSInteger)_renderEffectCount) {
        if (_renderEffects[effectIndex].locked) {
            canEditTiming = NO;
        }
    }
    NSMenuItem *timingItem = [[NSMenuItem alloc] initWithTitle:@"Timing"
                                                       action:@selector(editEffectTiming:)
                                                keyEquivalent:@""];
    timingItem.tag = kMenuTagTiming;
    timingItem.target = self;
    timingItem.enabled = canEditTiming;
    [menu addItem:timingItem];

    return menu;
}

/// Build the context menu shown when right-clicking on a timing mark.
- (NSMenu *)buildTimingContextMenuWithLayerIndex:(NSInteger)layerIndex
                                      layerCount:(NSInteger)layerCount
                                 multipleSelected:(BOOL)multipleSelected {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Timing"];

    BOOL hasSelection = _selectedEffectsCount > 0;
    BOOL hasSingleEffect = (_contextMenuEffectIndex >= 0);

    // --- Timing-specific operations based on layer ---

    if (layerIndex == 0) {
        // Phrase layer (layer 0)
        NSMenuItem *breakdownPhrase = [[NSMenuItem alloc] initWithTitle:@"Breakdown Phrase"
                                                                action:@selector(breakdownPhrase:)
                                                         keyEquivalent:@""];
        breakdownPhrase.tag = kMenuTagBreakdownPhrase;
        breakdownPhrase.target = self;
        breakdownPhrase.enabled = hasSingleEffect;
        [menu addItem:breakdownPhrase];

        if (multipleSelected) {
            NSMenuItem *breakdownPhrases = [[NSMenuItem alloc] initWithTitle:@"Breakdown Selected Phrases"
                                                                     action:@selector(breakdownSelectedPhrases:)
                                                              keyEquivalent:@""];
            breakdownPhrases.tag = kMenuTagBreakdownSelectedPhrases;
            breakdownPhrases.target = self;
            [menu addItem:breakdownPhrases];
        }
    } else if (layerIndex == 1) {
        // Word layer (layer 1)
        NSMenuItem *breakdownWord = [[NSMenuItem alloc] initWithTitle:@"Breakdown Word"
                                                              action:@selector(breakdownWord:)
                                                       keyEquivalent:@""];
        breakdownWord.tag = kMenuTagBreakdownWord;
        breakdownWord.target = self;
        breakdownWord.enabled = hasSingleEffect;
        [menu addItem:breakdownWord];

        if (multipleSelected) {
            NSMenuItem *breakdownWords = [[NSMenuItem alloc] initWithTitle:@"Breakdown Selected Words"
                                                                   action:@selector(breakdownSelectedWords:)
                                                            keyEquivalent:@""];
            breakdownWords.tag = kMenuTagBreakdownSelectedWords;
            breakdownWords.target = self;
            [menu addItem:breakdownWords];
        }
    }

    // Divide Timings (available for all timing layers)
    NSMenuItem *divideItem = [[NSMenuItem alloc] initWithTitle:@"Divide Timings"
                                                       action:@selector(divideTimings:)
                                                keyEquivalent:@""];
    divideItem.tag = kMenuTagDivideTimings;
    divideItem.target = self;
    divideItem.enabled = hasSingleEffect;
    [menu addItem:divideItem];

    // Auto Label Timings (phrase layer only)
    if (layerIndex == 0) {
        NSMenuItem *autoLabel = [[NSMenuItem alloc] initWithTitle:@"Auto Label Timings"
                                                          action:@selector(autoLabelTimings:)
                                                   keyEquivalent:@""];
        autoLabel.tag = kMenuTagAutoLabelTimings;
        autoLabel.target = self;
        [menu addItem:autoLabel];
    }

    // Phoneme layer operations (layer 2)
    if (layerIndex == 2) {
        NSMenuItem *addShimmer = [[NSMenuItem alloc] initWithTitle:@"Add \"-shimmer\""
                                                           action:@selector(addShimmer:)
                                                    keyEquivalent:@""];
        addShimmer.tag = kMenuTagAddShimmer;
        addShimmer.target = self;
        addShimmer.enabled = hasSingleEffect;
        [menu addItem:addShimmer];

        NSMenuItem *removeShimmer = [[NSMenuItem alloc] initWithTitle:@"Remove \"-shimmer\""
                                                              action:@selector(removeShimmer:)
                                                       keyEquivalent:@""];
        removeShimmer.tag = kMenuTagRemoveShimmer;
        removeShimmer.target = self;
        removeShimmer.enabled = hasSingleEffect;
        [menu addItem:removeShimmer];

        NSMenuItem *altPhonemes = [[NSMenuItem alloc] initWithTitle:@"Create Alternating Phonemes"
                                                            action:@selector(createAlternatingPhonemes:)
                                                     keyEquivalent:@""];
        altPhonemes.tag = kMenuTagCreateAlternatingPhonemes;
        altPhonemes.target = self;
        altPhonemes.enabled = hasSingleEffect;
        [menu addItem:altPhonemes];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Lock / Unlock ---

    BOOL anyLocked = NO;
    BOOL anyUnlocked = NO;
    for (NSUInteger idx = 0; idx < _renderEffectCount; idx++) {
        if ([self isEffectSelected:idx] && _renderEffects[idx].isTimingMark) {
            if (_renderEffects[idx].locked) anyLocked = YES;
            else anyUnlocked = YES;
        }
    }

    NSMenuItem *lockItem = [[NSMenuItem alloc] initWithTitle:@"Lock"
                                                      action:@selector(lockEffects:)
                                               keyEquivalent:@""];
    lockItem.tag = kMenuTagLock;
    lockItem.target = self;
    lockItem.enabled = hasSelection && anyUnlocked;
    [menu addItem:lockItem];

    NSMenuItem *unlockItem = [[NSMenuItem alloc] initWithTitle:@"Unlock"
                                                       action:@selector(unlockEffects:)
                                                keyEquivalent:@""];
    unlockItem.tag = kMenuTagUnlock;
    unlockItem.target = self;
    unlockItem.enabled = hasSelection && anyLocked;
    [menu addItem:unlockItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Cut / Copy / Paste / Delete ---

    NSMenuItem *cutItem = [[NSMenuItem alloc] initWithTitle:@"Cut"
                                                    action:@selector(cut:)
                                             keyEquivalent:@"x"];
    cutItem.tag = kMenuTagCut;
    cutItem.target = self;
    cutItem.enabled = hasSelection;
    [menu addItem:cutItem];

    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy"
                                                     action:@selector(copy:)
                                              keyEquivalent:@"c"];
    copyItem.tag = kMenuTagCopy;
    copyItem.target = self;
    copyItem.enabled = hasSelection;
    [menu addItem:copyItem];

    NSMenuItem *pasteItem = [[NSMenuItem alloc] initWithTitle:@"Paste"
                                                      action:@selector(paste:)
                                               keyEquivalent:@"v"];
    pasteItem.tag = kMenuTagPaste;
    pasteItem.target = self;
    [menu addItem:pasteItem];

    NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete"
                                                       action:@selector(deleteSelectedEffects:)
                                                keyEquivalent:@""];
    deleteItem.tag = kMenuTagDelete;
    deleteItem.target = self;
    deleteItem.enabled = hasSelection;
    [menu addItem:deleteItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // --- Find / Replace ---

    NSMenuItem *findItem = [[NSMenuItem alloc] initWithTitle:@"Find..."
                                                     action:@selector(findTimingLabel:)
                                              keyEquivalent:@""];
    findItem.tag = kMenuTagFindTimingLabel;
    findItem.target = self;
    [menu addItem:findItem];

    NSMenuItem *findNext = [[NSMenuItem alloc] initWithTitle:@"Find Next"
                                                     action:@selector(findNextTimingLabel:)
                                              keyEquivalent:@""];
    findNext.tag = kMenuTagFindNextTimingLabel;
    findNext.target = self;
    [menu addItem:findNext];

    NSMenuItem *findPrev = [[NSMenuItem alloc] initWithTitle:@"Find Previous"
                                                     action:@selector(findPreviousTimingLabel:)
                                              keyEquivalent:@""];
    findPrev.tag = kMenuTagFindPreviousTimingLabel;
    findPrev.target = self;
    [menu addItem:findPrev];

    NSMenuItem *replaceAll = [[NSMenuItem alloc] initWithTitle:@"Replace All..."
                                                       action:@selector(replaceAllTimingLabels:)
                                                keyEquivalent:@""];
    replaceAll.tag = kMenuTagReplaceAllTimingLabels;
    replaceAll.target = self;
    [menu addItem:replaceAll];

    return menu;
}

#pragma mark - Context Menu Actions

- (void)cut:(id)sender {
    [self performCopy];
    [self performDelete];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:XLEffectsGridDidCutNotification
                      object:self
                    userInfo:[self selectedEffectUserInfo]];
}

- (void)copy:(id)sender {
    [self performCopy];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:XLEffectsGridDidCopyNotification
                      object:self
                    userInfo:[self selectedEffectUserInfo]];
}

- (void)paste:(id)sender {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:XLEffectsGridDidPasteNotification
                      object:self
                    userInfo:@{
                        @"row": @(_mouseDownRow >= 0 ? _mouseDownRow : 0),
                        @"timeMS": @(_dragStartTimeMS)
                    }];
}

- (void)deleteSelectedEffects:(id)sender {
    [self performDelete];
}

- (void)editEffectSettings:(id)sender {
    if (_selectedEffectID >= 0) {
        NSInteger row = [self rowForEffectIndex:_selectedEffectID];
        if ([_delegate respondsToSelector:@selector(effectsGrid:didDoubleClickEffectAtRow:effectIndex:)]) {
            [_delegate effectsGrid:self didDoubleClickEffectAtRow:row effectIndex:_selectedEffectID];
        }
    }
}

- (void)splitEffect:(id)sender {
    if (_contextMenuEffectIndex < 0) return;
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestSplitEffectAtIndex:atTimeMS:)]) {
        [_delegate effectsGrid:self
            didRequestSplitEffectAtIndex:_contextMenuEffectIndex
                                atTimeMS:_contextMenuTimeMS];
    }
}

- (void)duplicateEffect:(id)sender {
    NSInteger direction = kDuplicateDirectionNone;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        NSNumber *dirNum = [(NSMenuItem *)sender representedObject];
        if (dirNum) direction = dirNum.integerValue;
    }
    NSInteger idx = (_contextMenuEffectIndex >= 0) ? _contextMenuEffectIndex : _selectedEffectID;
    if (idx < 0) return;
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestDuplicateEffectAtIndex:direction:)]) {
        [_delegate effectsGrid:self
            didRequestDuplicateEffectAtIndex:idx
                                  direction:direction];
    }
}

- (void)createTimingFromEffect:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestCreateTimingFromEffects:)]) {
        [_delegate effectsGrid:self
            didRequestCreateTimingFromEffects:[self selectedEffectIndices]];
    }
}

- (void)lockEffects:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestSetLocked:forEffects:)]) {
        [_delegate effectsGrid:self
            didRequestSetLocked:YES
                     forEffects:[self selectedEffectIndices]];
    }
}

- (void)unlockEffects:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestSetLocked:forEffects:)]) {
        [_delegate effectsGrid:self
            didRequestSetLocked:NO
                     forEffects:[self selectedEffectIndices]];
    }
}

- (void)disableRender:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestSetRenderDisabled:forEffects:)]) {
        [_delegate effectsGrid:self
            didRequestSetRenderDisabled:YES
                             forEffects:[self selectedEffectIndices]];
    }
}

- (void)enableRender:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestSetRenderDisabled:forEffects:)]) {
        [_delegate effectsGrid:self
            didRequestSetRenderDisabled:NO
                             forEffects:[self selectedEffectIndices]];
    }
}

- (void)editDescription:(id)sender {
    NSInteger idx = (_contextMenuEffectIndex >= 0) ? _contextMenuEffectIndex : _selectedEffectID;
    if (idx < 0) return;
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestEditDescriptionForEffectAtIndex:)]) {
        [_delegate effectsGrid:self didRequestEditDescriptionForEffectAtIndex:idx];
    }
}

- (void)resetEffect:(id)sender {
    NSInteger idx = (_contextMenuEffectIndex >= 0) ? _contextMenuEffectIndex : _selectedEffectID;
    if (idx < 0) return;
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestResetEffectAtIndex:)]) {
        [_delegate effectsGrid:self didRequestResetEffectAtIndex:idx];
    }
}

- (void)effectPresets:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGridDidRequestEffectPresets:)]) {
        [_delegate effectsGridDidRequestEffectPresets:self];
    }
}

- (void)createRandomEffects:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGridDidRequestCreateRandomEffects:)]) {
        [_delegate effectsGridDidRequestCreateRandomEffects:self];
    }
}

- (void)editEffectTiming:(id)sender {
    NSInteger idx = (_contextMenuEffectIndex >= 0) ? _contextMenuEffectIndex : _selectedEffectID;
    if (idx < 0) return;
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestEditTimingForEffectAtIndex:)]) {
        [_delegate effectsGrid:self didRequestEditTimingForEffectAtIndex:idx];
    }
}

#pragma mark - Timing Track Context Menu Actions

- (void)breakdownPhrase:(id)sender {
    NSInteger idx = (_contextMenuEffectIndex >= 0) ? _contextMenuEffectIndex : _selectedEffectID;
    if (idx < 0) return;
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestBreakdownPhraseAtIndex:)]) {
        [_delegate effectsGrid:self didRequestBreakdownPhraseAtIndex:idx];
    }
}

- (void)breakdownSelectedPhrases:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestBreakdownSelectedPhrases:)]) {
        [_delegate effectsGrid:self didRequestBreakdownSelectedPhrases:[self selectedEffectIndices]];
    }
}

- (void)breakdownWord:(id)sender {
    NSInteger idx = (_contextMenuEffectIndex >= 0) ? _contextMenuEffectIndex : _selectedEffectID;
    if (idx < 0) return;
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestBreakdownWordAtIndex:)]) {
        [_delegate effectsGrid:self didRequestBreakdownWordAtIndex:idx];
    }
}

- (void)breakdownSelectedWords:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestBreakdownSelectedWords:)]) {
        [_delegate effectsGrid:self didRequestBreakdownSelectedWords:[self selectedEffectIndices]];
    }
}

- (void)divideTimings:(id)sender {
    NSInteger idx = (_contextMenuEffectIndex >= 0) ? _contextMenuEffectIndex : _selectedEffectID;
    if (idx < 0) return;
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestDivideTimingsAtIndex:)]) {
        [_delegate effectsGrid:self didRequestDivideTimingsAtIndex:idx];
    }
}

- (void)autoLabelTimings:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGridDidRequestAutoLabelTimings:)]) {
        [_delegate effectsGridDidRequestAutoLabelTimings:self];
    }
}

- (void)addShimmer:(id)sender {
    NSInteger idx = (_contextMenuEffectIndex >= 0) ? _contextMenuEffectIndex : _selectedEffectID;
    if (idx < 0) return;
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestAddShimmerAtIndex:)]) {
        [_delegate effectsGrid:self didRequestAddShimmerAtIndex:idx];
    }
}

- (void)removeShimmer:(id)sender {
    NSInteger idx = (_contextMenuEffectIndex >= 0) ? _contextMenuEffectIndex : _selectedEffectID;
    if (idx < 0) return;
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestRemoveShimmerAtIndex:)]) {
        [_delegate effectsGrid:self didRequestRemoveShimmerAtIndex:idx];
    }
}

- (void)createAlternatingPhonemes:(id)sender {
    NSInteger idx = (_contextMenuEffectIndex >= 0) ? _contextMenuEffectIndex : _selectedEffectID;
    if (idx < 0) return;
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestCreateAlternatingPhonemesAtIndex:)]) {
        [_delegate effectsGrid:self didRequestCreateAlternatingPhonemesAtIndex:idx];
    }
}

- (void)findTimingLabel:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGridDidRequestFindTimingLabel:)]) {
        [_delegate effectsGridDidRequestFindTimingLabel:self];
    }
}

- (void)findNextTimingLabel:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGridDidRequestFindNextTimingLabel:)]) {
        [_delegate effectsGridDidRequestFindNextTimingLabel:self];
    }
}

- (void)findPreviousTimingLabel:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGridDidRequestFindPreviousTimingLabel:)]) {
        [_delegate effectsGridDidRequestFindPreviousTimingLabel:self];
    }
}

- (void)replaceAllTimingLabels:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGridDidRequestReplaceAllTimingLabels:)]) {
        [_delegate effectsGridDidRequestReplaceAllTimingLabels:self];
    }
}

#pragma mark - Alignment Context Menu Actions

- (void)alignEffects:(id)sender {
    NSInteger alignType = XLAlignmentTypeStartTimes;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        NSNumber *typeNum = [(NSMenuItem *)sender representedObject];
        if (typeNum) alignType = typeNum.integerValue;
    }
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestAlignEffects:alignmentType:)]) {
        [_delegate effectsGrid:self
            didRequestAlignEffects:[self selectedEffectIndices]
                     alignmentType:(XLAlignmentType)alignType];
    }
}

#pragma mark - Symbol Library Context Menu Actions

- (void)createSymbolFromEffect:(id)sender {
    NSInteger idx = (_contextMenuEffectIndex >= 0) ? _contextMenuEffectIndex : _selectedEffectID;
    if (idx < 0) return;
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestCreateSymbolFromEffectAtIndex:)]) {
        [_delegate effectsGrid:self didRequestCreateSymbolFromEffectAtIndex:idx];
    }
}

- (void)unlinkFromSymbol:(id)sender {
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestUnlinkFromSymbol:)]) {
        [_delegate effectsGrid:self didRequestUnlinkFromSymbol:[self selectedEffectIndices]];
    }
}

- (void)linkToSymbol:(id)sender {
    NSInteger symbolIndex = 0;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        symbolIndex = [(NSMenuItem *)sender tag] - kMenuTagLinkSymbolBase;
    }
    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestLinkEffects:toSymbolIndex:)]) {
        [_delegate effectsGrid:self
            didRequestLinkEffects:[self selectedEffectIndices]
                   toSymbolIndex:symbolIndex];
    }
}

- (void)performCopy {
    NSMutableArray *effectInfoArray = [NSMutableArray array];

    for (NSUInteger idx = 0; idx < _renderEffectCount; idx++) {
        if ([self isEffectSelected:idx]) {
            XLEffectRenderInfo info = _renderEffects[idx];
            NSDictionary *dict = @{
                @"index": @(idx),
                @"row": @(info.row),
                @"startTimeMS": @(info.startTimeMS),
                @"endTimeMS": @(info.endTimeMS),
                @"effectIndex": @(info.effectIndex)
            };
            [effectInfoArray addObject:dict];
        }
    }

    if (effectInfoArray.count > 0) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:effectInfoArray
                                             requiringSecureCoding:NO
                                                             error:nil];
        if (data) {
            [pb setData:data forType:XLEffectTypePasteboardType];
        }
    }
}

- (void)performDelete {
    if (_selectedEffectsCount == 0) return;

    // Capture undo snapshots for all selected effects before deletion
    if (_undoController) {
        NSMutableArray<NSValue *> *snapshots = [NSMutableArray array];
        for (NSUInteger idx = 0; idx < _renderEffectCount; idx++) {
            if ([self isEffectSelected:idx]) {
                XLEffectRenderInfo info = _renderEffects[idx];
                XLEffectSnapshot snapshot;
                snapshot.effectID = idx;
                snapshot.row = info.row;
                snapshot.layer = info.layer;
                snapshot.startTimeMS = info.startTimeMS;
                snapshot.endTimeMS = info.endTimeMS;
                snapshot.effectTypeIndex = info.effectIndex;
                snapshot.colorARGB = info.colorARGB;
                snapshot.selected = info.selected;
                snapshot.locked = info.locked;
                snapshot.renderDisabled = info.renderDisabled;
                [snapshots addObject:[NSValue valueWithBytes:&snapshot objCType:@encode(XLEffectSnapshot)]];
            }
        }

        NSString *actionName = (snapshots.count == 1) ? @"Delete Effect"
            : [NSString stringWithFormat:@"Delete %lu Effects", (unsigned long)snapshots.count];
        [_undoController captureEffectsToBeDeleted:snapshots actionName:actionName];
    }

    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestDeleteEffects:)]) {
        [_delegate effectsGrid:self didRequestDeleteEffects:[self selectedEffectIndices]];
    }

    [self clearSelection];
    _needsRedraw = YES;
}

- (NSDictionary *)selectedEffectUserInfo {
    NSMutableArray *indices = [NSMutableArray array];
    for (NSUInteger idx = 0; idx < _selectedEffectsCapacity; idx++) {
        if (_selectedEffects[idx]) {
            [indices addObject:@(idx)];
        }
    }
    return @{@"selectedIndices": indices};
}

#pragma mark - Middle Mouse (Pan)

- (void)otherMouseDown:(NSEvent *)event {
    if (event.buttonNumber == 2) {
        _isMiddleMouseScrolling = YES;
        _mouseDownPoint = [self convertPoint:event.locationInWindow fromView:nil];
        _mouseDownScrollOffset = _scrollOffset;
        [[NSCursor closedHandCursor] push];
    }
}

- (void)otherMouseDragged:(NSEvent *)event {
    if (_isMiddleMouseScrolling) {
        NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
        CGFloat dx = loc.x - _mouseDownPoint.x;
        CGFloat dy = loc.y - _mouseDownPoint.y;
        _scrollOffset = CGPointMake(_mouseDownScrollOffset.x - dx,
                                    _mouseDownScrollOffset.y - dy);
        [self clampScrollOffset];
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeScrollOffset:)]) {
            [_delegate effectsGrid:self didChangeScrollOffset:_scrollOffset];
        }
    }
}

- (void)otherMouseUp:(NSEvent *)event {
    if (_isMiddleMouseScrolling) {
        _isMiddleMouseScrolling = NO;
        [NSCursor pop];
    }
}

#pragma mark - Scroll Wheel & Magnify

- (void)scrollWheel:(NSEvent *)event {
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        // Cmd+Scroll = Zoom
        CGFloat zoomDelta = event.scrollingDeltaY * 0.01;
        CGFloat newZoom = _zoomLevel * (1.0 + zoomDelta);
        newZoom = MAX(_minZoomLevel, MIN(newZoom, _maxZoomLevel));

        // Zoom centered on mouse position
        NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
        CGFloat timeAtMouse = (loc.x + _scrollOffset.x) / _zoomLevel;

        _zoomLevel = newZoom;

        // Adjust scroll to keep the time under the mouse stationary
        _scrollOffset = CGPointMake(timeAtMouse * _zoomLevel - loc.x, _scrollOffset.y);
        [self clampScrollOffset];
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeZoomLevel:)]) {
            [_delegate effectsGrid:self didChangeZoomLevel:_zoomLevel];
        }
        if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeScrollOffset:)]) {
            [_delegate effectsGrid:self didChangeScrollOffset:_scrollOffset];
        }
    } else {
        // Normal scroll
        CGFloat dx = event.scrollingDeltaX;
        CGFloat dy = event.scrollingDeltaY;

        // Shift+scroll = horizontal
        if (event.modifierFlags & NSEventModifierFlagShift) {
            dx = dy;
            dy = 0;
        }

        _scrollOffset = CGPointMake(_scrollOffset.x - dx, _scrollOffset.y - dy);
        [self clampScrollOffset];
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeScrollOffset:)]) {
            [_delegate effectsGrid:self didChangeScrollOffset:_scrollOffset];
        }
    }
}

- (void)magnifyWithEvent:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat timeAtMouse = (loc.x + _scrollOffset.x) / _zoomLevel;

    CGFloat newZoom = _zoomLevel * (1.0 + event.magnification);
    newZoom = MAX(_minZoomLevel, MIN(newZoom, _maxZoomLevel));
    _zoomLevel = newZoom;

    _scrollOffset = CGPointMake(timeAtMouse * _zoomLevel - loc.x, _scrollOffset.y);
    [self clampScrollOffset];
    _needsRedraw = YES;

    if ([_delegate respondsToSelector:@selector(effectsGrid:didChangeZoomLevel:)]) {
        [_delegate effectsGrid:self didChangeZoomLevel:_zoomLevel];
    }
}

#pragma mark - Mouse Move (Cursor Updates)

- (void)mouseMoved:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];

    NSInteger hitEffectIndex = -1;
    XLEffectHitLocation hitLoc;
    [self hitTestPoint:loc effectIndex:&hitEffectIndex hitLocation:&hitLoc];

    // Update cursor based on hit location
    switch (hitLoc) {
        case XLEffectHitLocationLeftEdge:
        case XLEffectHitLocationRightEdge:
            [[NSCursor resizeLeftRightCursor] set];
            break;
        case XLEffectHitLocationCenter:
            [[NSCursor openHandCursor] set];
            break;
        default:
            [[NSCursor arrowCursor] set];
            break;
    }

    // Notify delegate of cursor position for waveform sync
    CGFloat timeMS;
    [self convertPoint:loc toTimeMS:&timeMS row:NULL];
    if ([_delegate respondsToSelector:@selector(effectsGrid:didMoveCursorToTimeMS:)]) {
        [_delegate effectsGrid:self didMoveCursorToTimeMS:timeMS];
    }
}

- (void)mouseExited:(NSEvent *)event {
    // Notify delegate that cursor has left the grid
    if ([_delegate respondsToSelector:@selector(effectsGrid:didMoveCursorToTimeMS:)]) {
        [_delegate effectsGrid:self didMoveCursorToTimeMS:-1];
    }
}

#pragma mark - Keyboard Events

- (void)keyDown:(NSEvent *)event {
    NSLog(@"XLEffectsGridView keyDown: keyCode=%hu, chars='%@', modifiers=0x%lx",
          event.keyCode, event.charactersIgnoringModifiers, (unsigned long)event.modifierFlags);

    // First, let the delegate handle via keyboard bindings (custom shortcuts like 't' for zoom)
    if ([_delegate respondsToSelector:@selector(effectsGrid:shouldHandleKeyEvent:)]) {
        NSLog(@"XLEffectsGridView: Delegate responds to shouldHandleKeyEvent:, calling it...");
        BOOL handled = [_delegate effectsGrid:self shouldHandleKeyEvent:event];
        NSLog(@"XLEffectsGridView: Delegate returned %@", handled ? @"YES (handled)" : @"NO (not handled)");
        if (handled) {
            return; // Delegate handled it
        }
    } else {
        NSLog(@"XLEffectsGridView: Delegate does NOT respond to shouldHandleKeyEvent: (delegate=%@)", _delegate);
    }

    BOOL cmdDown = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    BOOL shiftDown = (event.modifierFlags & NSEventModifierFlagShift) != 0;

    // Handle keyboard shortcuts with Cmd modifier
    if (cmdDown) {
        NSString *chars = event.charactersIgnoringModifiers;
        if ([chars isEqualToString:@"c"]) {
            [self copy:nil];
            return;
        } else if ([chars isEqualToString:@"v"]) {
            [self paste:nil];
            return;
        } else if ([chars isEqualToString:@"x"]) {
            [self cut:nil];
            return;
        } else if ([chars isEqualToString:@"a"]) {
            // Cmd+A: select all effects in the row of the current selection
            NSInteger row = -1;
            if (_selectedEffectID >= 0) {
                row = [self rowForEffectIndex:_selectedEffectID];
            } else if (_mouseDownRow >= 0) {
                row = _mouseDownRow;
            }
            if (row >= 0) {
                [self selectAllEffectsInRow:row];
            }
            return;
        }
    }

    // Delete or Forward Delete
    if (event.keyCode == 51 || event.keyCode == 117) {
        [self performDelete];
        return;
    }

    // Arrow keys
    CGFloat snapInterval = [self timingGridSnapInterval];
    if (snapInterval <= 0) snapInterval = 50.0; // fallback: 50ms

    switch (event.keyCode) {
        case 123: // Left arrow
            if (_selectedEffectID >= 0) {
                if (shiftDown) {
                    [self nudgeSelectedEffectsByMS:-snapInterval];
                } else {
                    [self moveSelectionToAdjacentEffect:NO];
                }
            }
            return;
        case 124: // Right arrow
            if (_selectedEffectID >= 0) {
                if (shiftDown) {
                    [self nudgeSelectedEffectsByMS:snapInterval];
                } else {
                    [self moveSelectionToAdjacentEffect:YES];
                }
            }
            return;
        case 125: // Down arrow
            if (_selectedEffectID >= 0) {
                [self moveSelectionToAdjacentRow:YES];
            }
            return;
        case 126: // Up arrow
            if (_selectedEffectID >= 0) {
                [self moveSelectionToAdjacentRow:NO];
            }
            return;
        default:
            [super keyDown:event];
            break;
    }
}

#pragma mark - Undo/Redo Responder Chain

- (void)undo:(id)sender {
    if (_undoController && [_undoController canUndo]) {
        [_undoController undo];
    }
}

- (void)redo:(id)sender {
    if (_undoController && [_undoController canRedo]) {
        [_undoController redo];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;

    if (action == @selector(undo:)) {
        if (_undoController) {
            menuItem.title = [_undoController undoMenuItemTitle];
            return [_undoController canUndo];
        }
        menuItem.title = @"Undo";
        return NO;
    }

    if (action == @selector(redo:)) {
        if (_undoController) {
            menuItem.title = [_undoController redoMenuItemTitle];
            return [_undoController canRedo];
        }
        menuItem.title = @"Redo";
        return NO;
    }

    if (action == @selector(cut:) || action == @selector(copy:) || action == @selector(delete:)) {
        return _selectedEffectsCount > 0;
    }

    if (action == @selector(paste:)) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        return [pb.types containsObject:XLEffectTypePasteboardType];
    }

    return YES;
}

- (NSUndoManager *)undoManager {
    return _undoController.undoManager;
}

- (void)nudgeSelectedEffectsByMS:(CGFloat)deltaMS {
    if (_selectedEffectsCount == 0) return;

    // Capture undo snapshots before nudging
    if (_undoController) {
        NSMutableArray<NSValue *> *snapshots = [NSMutableArray array];
        for (NSUInteger idx = 0; idx < _renderEffectCount; idx++) {
            if ([self isEffectSelected:idx]) {
                XLEffectRenderInfo info = _renderEffects[idx];
                XLEffectSnapshot snapshot;
                snapshot.effectID = idx;
                snapshot.row = info.row;
                snapshot.layer = info.layer;
                snapshot.startTimeMS = info.startTimeMS;
                snapshot.endTimeMS = info.endTimeMS;
                snapshot.effectTypeIndex = info.effectIndex;
                snapshot.colorARGB = info.colorARGB;
                snapshot.selected = info.selected;
                snapshot.locked = info.locked;
                snapshot.renderDisabled = info.renderDisabled;
                [snapshots addObject:[NSValue valueWithBytes:&snapshot objCType:@encode(XLEffectSnapshot)]];
            }
        }

        NSString *actionName = (snapshots.count == 1) ? @"Nudge Effect"
            : [NSString stringWithFormat:@"Nudge %lu Effects", (unsigned long)snapshots.count];
        [_undoController captureEffectsToBeMoved:snapshots actionName:actionName];
    }

    for (NSUInteger idx = 0; idx < _renderEffectCount; idx++) {
        if ([self isEffectSelected:idx]) {
            CGFloat duration = _renderEffects[idx].endTimeMS - _renderEffects[idx].startTimeMS;
            CGFloat newStart = _renderEffects[idx].startTimeMS + deltaMS;
            newStart = MAX(0, MIN(newStart, _sequenceLengthMS - duration));
            _renderEffects[idx].startTimeMS = newStart;
            _renderEffects[idx].endTimeMS = newStart + duration;
        }
    }

    // Notify delegate about the move of the primary selection
    if (_selectedEffectID >= 0 && (NSUInteger)_selectedEffectID < _renderEffectCount) {
        XLEffectRenderInfo info = _renderEffects[_selectedEffectID];
        NSInteger row = info.row;

        if ([_delegate respondsToSelector:@selector(effectsGrid:didMoveEffectAtRow:effectIndex:toTimeMS:)]) {
            [_delegate effectsGrid:self
              didMoveEffectAtRow:row
                    effectIndex:_selectedEffectID
                      toTimeMS:info.startTimeMS];
        }
    }

    _needsRedraw = YES;
}

- (void)moveSelectionToAdjacentEffect:(BOOL)forward {
    if (_selectedEffectID < 0 || (NSUInteger)_selectedEffectID >= _renderEffectCount) return;

    XLEffectRenderInfo currentInfo = _renderEffects[_selectedEffectID];
    NSInteger currentRow = currentInfo.row;

    NSInteger bestIndex = -1;
    CGFloat bestDistance = CGFLOAT_MAX;

    for (NSUInteger i = 0; i < _renderEffectCount; i++) {
        if ((NSInteger)i == _selectedEffectID) continue;
        XLEffectRenderInfo info = _renderEffects[i];
        if (info.row != currentRow) continue;

        if (forward && info.startTimeMS > currentInfo.startTimeMS) {
            CGFloat dist = info.startTimeMS - currentInfo.startTimeMS;
            if (dist < bestDistance) {
                bestDistance = dist;
                bestIndex = i;
            }
        } else if (!forward && info.startTimeMS < currentInfo.startTimeMS) {
            CGFloat dist = currentInfo.startTimeMS - info.startTimeMS;
            if (dist < bestDistance) {
                bestDistance = dist;
                bestIndex = i;
            }
        }
    }

    if (bestIndex >= 0) {
        [self clearAllSelections];
        [self selectEffectAtIndex:bestIndex];
        _selectedEffectID = bestIndex;
        [self updateSelectionState];
        [self notifySelectionChanged];
        _needsRedraw = YES;

        NSInteger row = [self rowForEffectIndex:bestIndex];
        if ([_delegate respondsToSelector:@selector(effectsGrid:didSelectEffectAtRow:effectIndex:)]) {
            [_delegate effectsGrid:self didSelectEffectAtRow:row effectIndex:bestIndex];
        }
    }
}

- (void)moveSelectionToAdjacentRow:(BOOL)downward {
    if (_selectedEffectID < 0 || (NSUInteger)_selectedEffectID >= _renderEffectCount) return;

    XLEffectRenderInfo currentInfo = _renderEffects[_selectedEffectID];
    NSInteger currentRow = currentInfo.row;
    CGFloat currentMidTime = (currentInfo.startTimeMS + currentInfo.endTimeMS) / 2.0;

    NSInteger targetRow = downward ? currentRow + 1 : currentRow - 1;
    if (targetRow < 0 || targetRow >= _totalRows) return;

    NSInteger bestIndex = -1;
    CGFloat bestDistance = CGFLOAT_MAX;

    for (NSUInteger i = 0; i < _renderEffectCount; i++) {
        XLEffectRenderInfo info = _renderEffects[i];
        if (info.row != targetRow) continue;

        CGFloat midTime = (info.startTimeMS + info.endTimeMS) / 2.0;
        CGFloat dist = fabs(midTime - currentMidTime);
        if (dist < bestDistance) {
            bestDistance = dist;
            bestIndex = i;
        }
    }

    if (bestIndex >= 0) {
        [self clearAllSelections];
        [self selectEffectAtIndex:bestIndex];
        _selectedEffectID = bestIndex;
        [self updateSelectionState];
        [self notifySelectionChanged];
        _needsRedraw = YES;

        if ([_delegate respondsToSelector:@selector(effectsGrid:didSelectEffectAtRow:effectIndex:)]) {
            [_delegate effectsGrid:self didSelectEffectAtRow:targetRow effectIndex:bestIndex];
        }
    }
}

#pragma mark - Rubber Band Selection

- (void)updateRubberBandSelection {
    CGFloat startTimeMS, endTimeMS;
    NSInteger startRow, endRow;
    [self convertPoint:_rubberBandOrigin toTimeMS:&startTimeMS row:&startRow];
    [self convertPoint:_rubberBandCurrent toTimeMS:&endTimeMS row:&endRow];

    if (startTimeMS > endTimeMS) {
        CGFloat tmp = startTimeMS; startTimeMS = endTimeMS; endTimeMS = tmp;
    }
    if (startRow > endRow) {
        NSInteger tmp = startRow; startRow = endRow; endRow = tmp;
    }

    startRow = MAX(0, startRow);
    endRow = MIN(endRow, _totalRows - 1);

    [self clearAllSelections];
    _selectedEffectID = -1;

    for (NSUInteger i = 0; i < _renderEffectCount; i++) {
        XLEffectRenderInfo info = _renderEffects[i];

        if (info.row < startRow || info.row > endRow) continue;

        // Effect overlaps the selection rectangle if it starts before the end
        // and ends after the start of the selection
        if (info.startTimeMS < endTimeMS && info.endTimeMS > startTimeMS) {
            [self selectEffectAtIndex:i];
            if (_selectedEffectID < 0) {
                _selectedEffectID = (NSInteger)i;
            }
        }
    }

    [self updateSelectionState];
    [self notifySelectionChanged];
}

#pragma mark - Hit Testing

- (void)hitTestPoint:(NSPoint)viewPoint
        effectIndex:(NSInteger *)outEffectIndex
        hitLocation:(XLEffectHitLocation *)outHitLocation
{
    *outEffectIndex = -1;
    *outHitLocation = XLEffectHitLocationNone;

    CGFloat timeMS;
    NSInteger row;
    [self convertPoint:viewPoint toTimeMS:&timeMS row:&row];

    if (row < 0 || row >= _totalRows) return;

    for (NSUInteger i = 0; i < _renderEffectCount; i++) {
        XLEffectRenderInfo info = _renderEffects[i];

        if (info.row != row) continue;
        if (timeMS < info.startTimeMS || timeMS > info.endTimeMS) continue;

        *outEffectIndex = (NSInteger)i;

        // Determine hit location within the effect
        CGFloat x1 = info.startTimeMS * _zoomLevel - _scrollOffset.x;
        CGFloat x2 = info.endTimeMS * _zoomLevel - _scrollOffset.x;

        if (viewPoint.x - x1 < kEdgeHitTestWidth) {
            *outHitLocation = XLEffectHitLocationLeftEdge;
        } else if (x2 - viewPoint.x < kEdgeHitTestWidth) {
            *outHitLocation = XLEffectHitLocationRightEdge;
        } else {
            *outHitLocation = XLEffectHitLocationCenter;
        }
        return;
    }
}

#pragma mark - NSDraggingDestination (Palette Drop)

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = sender.draggingPasteboard;
    if ([pb.types containsObject:XLEffectTypePasteboardType]) {
        _isReceivingDrop = YES;
        [self updateDropIndicatorForDraggingInfo:sender];
        _needsRedraw = YES;
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = sender.draggingPasteboard;
    if ([pb.types containsObject:XLEffectTypePasteboardType]) {
        [self updateDropIndicatorForDraggingInfo:sender];
        _needsRedraw = YES;
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    _isReceivingDrop = NO;
    _dropTargetRow = -1;
    _dropEffectType = nil;
    _needsRedraw = YES;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return YES;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = sender.draggingPasteboard;
    NSString *effectType = [pb stringForType:XLEffectTypePasteboardType];

    if (!effectType || _dropTargetRow < 0) {
        _isReceivingDrop = NO;
        _dropTargetRow = -1;
        _dropEffectType = nil;
        _needsRedraw = YES;
        return NO;
    }

    if ([_delegate respondsToSelector:@selector(effectsGrid:didRequestCreateEffectOfType:atRow:startTimeMS:endTimeMS:)]) {
        [_delegate effectsGrid:self
            didRequestCreateEffectOfType:effectType
                                   atRow:_dropTargetRow
                             startTimeMS:_dropTargetStartMS
                               endTimeMS:_dropTargetEndMS];
    }

    _isReceivingDrop = NO;
    _dropTargetRow = -1;
    _dropEffectType = nil;
    _needsRedraw = YES;
    return YES;
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {
    _isReceivingDrop = NO;
    _dropTargetRow = -1;
    _dropEffectType = nil;
    _needsRedraw = YES;
}

- (void)updateDropIndicatorForDraggingInfo:(id<NSDraggingInfo>)sender {
    NSPoint dragPoint = [self convertPoint:sender.draggingLocation fromView:nil];
    CGFloat timeMS;
    NSInteger row;
    [self convertPoint:dragPoint toTimeMS:&timeMS row:&row];

    // Safety: if no rows, can't drop
    if (_totalRows <= 0) {
        _dropTargetRow = -1;
        return;
    }

    row = MAX(0, MIN(row, _totalRows - 1));

    // Safety: need valid sequence length and zoom
    if (_sequenceLengthMS <= 0 || _zoomLevel <= 0) {
        _dropTargetRow = -1;
        return;
    }

    // Default: center the effect on the cursor position
    CGFloat startMS = timeMS - kDefaultDropDurationMS / 2.0;
    CGFloat endMS = timeMS + kDefaultDropDurationMS / 2.0;

    // Snap to nearest timing marks if enabled
    if (_snapToTimingMarks && _timingMarkCount > 0 && _timingMarkValues && _zoomLevel > 0) {
        // Snap the start to the nearest timing mark
        CGFloat snappedStart = [self snapTimeMS:startMS];
        // Snap the end to the nearest timing mark
        CGFloat snappedEnd = [self snapTimeMS:endMS];

        // Use whichever snap is closer to maintain position near cursor
        CGFloat snapDeltaStart = fabs(snappedStart - startMS);
        CGFloat snapDeltaEnd = fabs(snappedEnd - endMS);
        CGFloat snapThresholdMS = kSnapThresholdPixels / _zoomLevel;

        if (snapDeltaStart <= snapDeltaEnd && snapDeltaStart <= snapThresholdMS) {
            // Snap start, keep duration fixed
            startMS = snappedStart;
            endMS = snappedStart + kDefaultDropDurationMS;
        } else if (snapDeltaEnd <= snapThresholdMS) {
            // Snap end, keep duration fixed
            endMS = snappedEnd;
            startMS = snappedEnd - kDefaultDropDurationMS;
        }
        // Otherwise keep unsnapped position
    }

    // Clamp to sequence bounds
    startMS = MAX(0, startMS);
    endMS = MIN(endMS, _sequenceLengthMS);

    // Ensure minimum duration
    if (endMS - startMS < kMinimumEffectWidthMS) {
        endMS = startMS + kMinimumEffectWidthMS;
        if (endMS > _sequenceLengthMS) {
            endMS = _sequenceLengthMS;
            startMS = MAX(0, endMS - kMinimumEffectWidthMS);
        }
    }

    _dropTargetRow = row;
    _dropTargetStartMS = startMS;
    _dropTargetEndMS = endMS;

    NSPasteboard *pb = sender.draggingPasteboard;
    _dropEffectType = [pb stringForType:XLEffectTypePasteboardType];
}

#pragma mark - Properties

- (void)setZoomLevel:(CGFloat)zoomLevel {
    _zoomLevel = MAX(_minZoomLevel, MIN(zoomLevel, _maxZoomLevel));
    _needsRedraw = YES;
}

- (void)setScrollOffset:(CGPoint)scrollOffset {
    _scrollOffset = scrollOffset;
    [self clampScrollOffset];
    _needsRedraw = YES;
}

- (void)setRowHeight:(CGFloat)rowHeight {
    _rowHeight = MAX(14.0, MIN(rowHeight, 80.0));
    _needsRedraw = YES;
}

- (void)setSelectedEffectID:(NSInteger)selectedEffectID {
    if (_selectedEffectID != selectedEffectID) {
        _selectedEffectID = selectedEffectID;

        // Sync selection with the primary selection if setting directly
        if (selectedEffectID >= 0) {
            if (![self isEffectSelected:selectedEffectID]) {
                [self clearAllSelections];
                [self selectEffectAtIndex:selectedEffectID];
            }
        } else {
            [self clearAllSelections];
        }

        [self updateSelectionState];
        _needsRedraw = YES;
    }
}

#pragma mark - Inline Label Editing

- (void)beginEditingLabelAtRow:(NSInteger)row
                       startMS:(CGFloat)startMS
                         endMS:(CGFloat)endMS
                  currentLabel:(NSString *)currentLabel
             completionHandler:(void (^)(NSString * _Nullable newLabel))completion
{
    // Cancel any existing edit
    [self cancelLabelEditing];

    // Calculate the editor rect in view coordinates
    CGFloat x1 = startMS * _zoomLevel - _scrollOffset.x;
    CGFloat x2 = endMS * _zoomLevel - _scrollOffset.x;
    CGFloat y = row * _rowHeight - _scrollOffset.y;

    // Ensure minimum width for the editor
    CGFloat width = MAX(x2 - x1, 60.0);
    // Inset slightly from the edges
    CGFloat inset = 2.0;
    NSRect editorRect = NSMakeRect(x1 + inset, y + 1.0, width - inset * 2, _rowHeight - 2.0);

    // Create the text field
    _labelEditor = [[NSTextField alloc] initWithFrame:editorRect];
    _labelEditor.stringValue = currentLabel ?: @"";
    _labelEditor.font = [NSFont systemFontOfSize:9.0];
    _labelEditor.alignment = NSTextAlignmentCenter;
    _labelEditor.bordered = YES;
    _labelEditor.bezeled = YES;
    _labelEditor.bezelStyle = NSTextFieldRoundedBezel;
    _labelEditor.drawsBackground = YES;
    _labelEditor.backgroundColor = [NSColor colorWithWhite:0.15 alpha:0.95];
    _labelEditor.textColor = [NSColor whiteColor];
    _labelEditor.focusRingType = NSFocusRingTypeNone;
    _labelEditor.editable = YES;
    _labelEditor.selectable = YES;
    _labelEditor.delegate = (id<NSTextFieldDelegate>)self;
    _labelEditor.target = self;
    _labelEditor.action = @selector(labelEditorDidEndEditing:);

    _labelEditCompletion = [completion copy];

    [self addSubview:_labelEditor];
    [self.window makeFirstResponder:_labelEditor];

    // Select all text for easy replacement
    [_labelEditor selectText:nil];
}

- (void)labelEditorDidEndEditing:(id)sender {
    [self commitLabelEditing];
}

- (void)commitLabelEditing {
    if (!_labelEditor) return;

    NSString *newLabel = [_labelEditor.stringValue copy];
    void (^completion)(NSString * _Nullable) = _labelEditCompletion;

    [_labelEditor removeFromSuperview];
    _labelEditor = nil;
    _labelEditCompletion = nil;

    // Re-focus the grid view
    [self.window makeFirstResponder:self];

    if (completion) {
        completion(newLabel);
    }
}

- (void)cancelLabelEditing {
    if (!_labelEditor) return;

    void (^completion)(NSString * _Nullable) = _labelEditCompletion;

    [_labelEditor removeFromSuperview];
    _labelEditor = nil;
    _labelEditCompletion = nil;

    [self.window makeFirstResponder:self];

    if (completion) {
        completion(nil);
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (control == _labelEditor) {
        if (commandSelector == @selector(insertNewline:)) {
            // Enter key: commit
            [self commitLabelEditing];
            return YES;
        } else if (commandSelector == @selector(cancelOperation:)) {
            // Escape key: cancel
            [self cancelLabelEditing];
            return YES;
        }
    }
    return NO;
}

@end
