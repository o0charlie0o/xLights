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

// SF Symbol icon mapping for effect types (matching Swift EffectPaletteGridView)
static NSDictionary<NSString *, NSString *> *sEffectIconMapping = nil;

@interface XLEffectsGridView () {
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
            dropIndicator:_isReceivingDrop
                  dropRow:_dropTargetRow
              dropStartMS:_dropTargetStartMS
                dropEndMS:_dropTargetEndMS];

    // Draw effect icons on the overlay layer (can be disabled for performance testing)
    if (!_disableIconDrawing) {
        [self drawEffectIcons];
    } else {
        _iconOverlayLayer.contents = nil;
    }

    _isDrawing = NO;
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

    // Draw icons for visible effects
    for (NSUInteger i = 0; i < _renderEffectCount; i++) {
        XLEffectRenderInfo info = _renderEffects[i];

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

- (NSInteger)rowForEffectIndex:(NSInteger)effectIndex {
    if (effectIndex < 0 || (NSUInteger)effectIndex >= _renderEffectCount) return -1;
    return _renderEffects[effectIndex].row;
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
        } else {
            newEnd = _dragOriginalEndMS + deltaMS;
            newEnd = MAX(newStart + kMinimumEffectWidthMS, MIN(newEnd, _sequenceLengthMS));
            if (snapEnabled) {
                newEnd = [self snapTimeMS:newEnd];
                newEnd = MAX(newStart + kMinimumEffectWidthMS, newEnd);
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
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Effects"];

    BOOL hasSelection = _selectedEffectsCount > 0;

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

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit Effect Settings..."
                                                     action:@selector(editEffectSettings:)
                                              keyEquivalent:@""];
    editItem.tag = kMenuTagEditSettings;
    editItem.target = self;
    editItem.enabled = (effectIndex >= 0);
    [menu addItem:editItem];

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

@end
