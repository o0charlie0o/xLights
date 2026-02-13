/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLStemsContainerView.h"
#import "XLMiniWaveformView.h"
#import "XLStemManager.h"
#import "XLStemData.h"
#import "XLScrollCoordinator.h"

static NSString *const kDefaultsCollapsedKey = @"StemsPanel.collapsed";
static NSString *const kDefaultsExpandedHeightKey = @"StemsPanel.expandedHeight";
static NSString *const kDefaultsStemRowHeightKey = @"StemsPanel.stemRowHeight";

static const CGFloat kRowHeaderFontSize = 11.0;
static const CGFloat kRowHeaderLeftPadding = 8.0;
static const CGFloat kStemRowHeightMin = 16.0;
static const CGFloat kStemRowHeightMax = 80.0;
static const CGFloat kStemRowHeightDefault = 30.0;

#pragma mark - Resize Handle View

@interface XLStemsResizeHandle : NSView
@property (nonatomic, weak) XLStemsContainerView *container;
@end

@implementation XLStemsResizeHandle {
    CGFloat _lastY;
    BOOL _isDragging;
    BOOL _isHovering;
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        [self updateAppearance];
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor resizeUpDownCursor]];
}

- (void)mouseEntered:(NSEvent *)event {
    _isHovering = YES;
    [self updateAppearance];
}

- (void)mouseExited:(NSEvent *)event {
    _isHovering = NO;
    [self updateAppearance];
}

- (void)mouseDown:(NSEvent *)event {
    _isDragging = YES;
    _lastY = event.locationInWindow.y;
    [self updateAppearance];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_isDragging) return;
    CGFloat currentY = event.locationInWindow.y;
    CGFloat delta = _lastY - currentY;
    _lastY = currentY;

    CGFloat newHeight = _container.currentHeight + delta;
    newHeight = fmax(kStemsMinExpandedHeight, fmin(newHeight, kStemsMaxExpandedHeight));

    [_container setExpandedHeight:newHeight];

    if ([_container.delegate respondsToSelector:@selector(stemsContainer:didChangeHeight:)]) {
        [_container.delegate stemsContainer:_container didChangeHeight:newHeight];
    }
}

- (void)mouseUp:(NSEvent *)event {
    _isDragging = NO;
    [self updateAppearance];
}

- (void)updateAppearance {
    if (_isDragging || _isHovering) {
        self.layer.backgroundColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.5].CGColor;
    } else {
        self.layer.backgroundColor = [NSColor separatorColor].CGColor;
    }
}

@end

#pragma mark - Flipped Document View

@interface XLFlippedDocumentView : NSView
@end

@implementation XLFlippedDocumentView
- (BOOL)isFlipped { return YES; }
@end

#pragma mark - Vertical-Only Scroll View

/// NSScrollView subclass that only handles vertical scrolling.
/// Horizontal scroll, Cmd+scroll (zoom), and Shift+scroll are forwarded to the superview.
@interface XLVerticalOnlyScrollView : NSScrollView
@end

@implementation XLVerticalOnlyScrollView

- (void)scrollWheel:(NSEvent *)event {
    // Cmd+scroll = zoom, Shift+scroll = horizontal — forward to container
    if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift)) {
        [self.superview scrollWheel:event];
        return;
    }

    // If primarily horizontal, forward to container
    if (fabs(event.scrollingDeltaX) > fabs(event.scrollingDeltaY)) {
        [self.superview scrollWheel:event];
        return;
    }

    // Vertical scrolling — handle normally
    [super scrollWheel:event];
}

@end

#pragma mark - Stem Row Header Delegate

@protocol XLStemRowHeaderDelegate <NSObject>
- (void)stemRowDidReorder:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex;
- (void)stemRowDidRequestEdit:(NSUInteger)index;
- (void)stemRowDidRequestContextMenu:(NSUInteger)index atPoint:(NSPoint)point inView:(NSView *)view;
@end

#pragma mark - Stem Row Header View (draws one stem name)

static const CGFloat kDragThreshold = 4.0;

@interface XLStemRowHeaderView : NSView
@property (nonatomic, copy) NSString *stemName;
@property (nonatomic, strong) NSColor *stemColor;
@property (nonatomic, assign) NSUInteger stemIndex;
@property (nonatomic, weak) id<XLStemRowHeaderDelegate> delegate;
@end

@implementation XLStemRowHeaderView {
    NSPoint _mouseDownPoint;
    CGFloat _dragStartOriginY;
    BOOL _isDragging;
    NSView *_insertionIndicator;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }

- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)mouseDown:(NSEvent *)event {
    if (event.clickCount == 2) {
        [_delegate stemRowDidRequestEdit:_stemIndex];
        return;
    }
    _mouseDownPoint = [self.superview convertPoint:event.locationInWindow fromView:nil];
    _dragStartOriginY = self.frame.origin.y;
    _isDragging = NO;
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint currentPoint = [self.superview convertPoint:event.locationInWindow fromView:nil];
    CGFloat deltaY = currentPoint.y - _mouseDownPoint.y;

    if (!_isDragging) {
        if (fabs(deltaY) < kDragThreshold) return;
        _isDragging = YES;
        self.layer.zPosition = 100;
        self.alphaValue = 0.85;

        _insertionIndicator = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(self.superview.bounds), 2)];
        _insertionIndicator.wantsLayer = YES;
        _insertionIndicator.layer.backgroundColor = [[NSColor systemBlueColor] CGColor];
        [self.superview addSubview:_insertionIndicator];
    }

    CGFloat newY = _dragStartOriginY + deltaY;
    NSRect frame = self.frame;
    frame.origin.y = newY;
    self.frame = frame;

    // Calculate insertion indicator position
    CGFloat rowH = NSHeight(self.bounds);
    NSUInteger targetIdx = (NSUInteger)fmax(0, round((newY) / rowH));
    NSUInteger siblingCount = self.superview.subviews.count - 1; // minus indicator
    if (targetIdx > siblingCount) targetIdx = siblingCount;
    CGFloat indicatorY = targetIdx * rowH - 1;
    _insertionIndicator.frame = NSMakeRect(0, indicatorY, NSWidth(self.superview.bounds), 2);
}

- (void)mouseUp:(NSEvent *)event {
    if (!_isDragging) return;
    _isDragging = NO;
    self.layer.zPosition = 0;
    self.alphaValue = 1.0;

    [_insertionIndicator removeFromSuperview];
    _insertionIndicator = nil;

    CGFloat rowH = NSHeight(self.bounds);
    CGFloat currentY = self.frame.origin.y;
    NSUInteger targetIdx = (NSUInteger)fmax(0, round(currentY / rowH));
    NSUInteger maxIdx = self.superview.subviews.count - 1;
    if (targetIdx > maxIdx) targetIdx = maxIdx;

    // Snap back to original position (reloadStems will rebuild)
    NSRect frame = self.frame;
    frame.origin.y = _dragStartOriginY;
    self.frame = frame;

    if (targetIdx != _stemIndex) {
        [_delegate stemRowDidReorder:_stemIndex toIndex:targetIdx];
    }
}

- (void)rightMouseDown:(NSEvent *)event {
    [_delegate stemRowDidRequestContextMenu:_stemIndex
                                    atPoint:[self convertPoint:event.locationInWindow fromView:nil]
                                     inView:self];
}

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    if (!ctx) return;

    CGFloat w = NSWidth(self.bounds);
    CGFloat h = NSHeight(self.bounds);

    // Background matching row headings style
    CGContextSetRGBFillColor(ctx, 0.14, 0.14, 0.14, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, w, h));

    // Bottom separator line
    CGContextSetRGBStrokeColor(ctx, 0.25, 0.25, 0.25, 1.0);
    CGContextSetLineWidth(ctx, 0.5);
    CGContextMoveToPoint(ctx, 0, h - 0.25);
    CGContextAddLineToPoint(ctx, w, h - 0.25);
    CGContextStrokePath(ctx);

    // Right edge separator (matching row headings)
    CGContextSetRGBStrokeColor(ctx, 0.25, 0.25, 0.25, 1.0);
    CGContextMoveToPoint(ctx, w - 0.25, 0);
    CGContextAddLineToPoint(ctx, w - 0.25, h);
    CGContextStrokePath(ctx);

    // Small color indicator bar on the left
    if (_stemColor) {
        CGFloat r, g, b, a;
        [[_stemColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace] getRed:&r green:&g blue:&b alpha:&a];
        CGContextSetRGBFillColor(ctx, r, g, b, 0.8);
        CGContextFillRect(ctx, CGRectMake(0, 2, 3, h - 4));
    }

    // Stem name label
    if (_stemName.length > 0) {
        NSColor *textColor = _stemColor ?: [NSColor labelColor];
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:kRowHeaderFontSize weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: textColor,
        };
        NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:_stemName attributes:attrs];
        NSSize textSize = [attrStr size];
        CGFloat textY = (h - textSize.height) / 2.0;

        // Truncate to fit
        CGFloat maxWidth = w - kRowHeaderLeftPadding - 6;
        NSRect textRect = NSMakeRect(kRowHeaderLeftPadding, textY, maxWidth, textSize.height);

        NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:gc];

        // Clip to available width for truncation
        CGContextSaveGState(ctx);
        CGContextClipToRect(ctx, CGRectMake(kRowHeaderLeftPadding, 0, maxWidth, h));
        [attrStr drawAtPoint:NSMakePoint(kRowHeaderLeftPadding, textY)];
        CGContextRestoreGState(ctx);

        [NSGraphicsContext restoreGraphicsState];
    }
}

@end

#pragma mark - Stems Container View

@interface XLStemsContainerView () <XLStemRowHeaderDelegate>
@end

@implementation XLStemsContainerView {
    NSView *_headerView;
    NSButton *_chevronButton;
    NSTextField *_titleLabel;
    NSSlider *_stemHeightSlider;
    NSButton *_importButton;

    // Row headers (left side)
    NSScrollView *_rowHeadersScrollView;
    NSView *_rowHeadersDocView;
    NSMutableArray<XLStemRowHeaderView *> *_rowHeaderViews;

    // Waveforms (right side)
    NSScrollView *_scrollView;
    NSView *_stackDocumentView;

    XLStemsResizeHandle *_resizeHandle;

    NSMutableArray<XLMiniWaveformView *> *_miniWaveformViews;

    NSLayoutConstraint *_rowHeadersWidthConstraint;
    NSLayoutConstraint *_scrollViewLeadingConstraint;

    CGFloat _savedExpandedHeight;
    CGFloat _stemRowHeight;
    CGFloat _scrollOffsetX;
    CGFloat _zoomLevel;
    CGFloat _sequenceLengthMS;
    CGFloat _playbackPositionMS;
    CGFloat _cursorPositionMS;

    NSTrackingArea *_waveformTrackingArea;
    BOOL _isScrubbing;
    BOOL _syncingScroll;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor colorWithWhite:0.12 alpha:1.0] CGColor];
        self.layer.masksToBounds = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _miniWaveformViews = [NSMutableArray array];
        _rowHeaderViews = [NSMutableArray array];
        _zoomLevel = 0.1;
        _sequenceLengthMS = 60000;
        _playbackPositionMS = -1;
        _cursorPositionMS = -1;
        _rowHeaderWidth = 180.0;  // Default, overridden by sequencer VC

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _collapsed = [defaults boolForKey:kDefaultsCollapsedKey];
        _savedExpandedHeight = [defaults doubleForKey:kDefaultsExpandedHeightKey];
        _stemRowHeight = [defaults doubleForKey:kDefaultsStemRowHeightKey];
        if (_stemRowHeight < kStemRowHeightMin || _stemRowHeight > kStemRowHeightMax) {
            _stemRowHeight = kStemRowHeightDefault;
        }
        if (_savedExpandedHeight < kStemsMinExpandedHeight) {
            _savedExpandedHeight = kStemsDefaultExpandedHeight;
        }

        [self setupHeader];
        [self setupRowHeaders];
        [self setupScrollView];
        [self setupResizeHandle];
        [self setupConstraints];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(stemManagerDidChange:)
                                                     name:XLStemManagerDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Setup

- (void)setupHeader {
    _headerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    _headerView.wantsLayer = YES;
    _headerView.layer.backgroundColor = [[NSColor colorWithWhite:0.16 alpha:1.0] CGColor];
    [self addSubview:_headerView];

    _chevronButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.right"
                                                         accessibilityDescription:@"Expand"]
                                        target:self
                                        action:@selector(toggleCollapsed)];
    _chevronButton.translatesAutoresizingMaskIntoConstraints = NO;
    _chevronButton.bordered = NO;
    _chevronButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightMedium];
    _chevronButton.image = [[NSImage imageWithSystemSymbolName:(_collapsed ? @"chevron.right" : @"chevron.down")
                                     accessibilityDescription:@"Toggle stems"]
                            imageWithSymbolConfiguration:config];
    _chevronButton.contentTintColor = [NSColor secondaryLabelColor];
    [_headerView addSubview:_chevronButton];

    _titleLabel = [NSTextField labelWithString:@"Stems"];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _titleLabel.textColor = [NSColor secondaryLabelColor];
    [_headerView addSubview:_titleLabel];

    // Stem row height slider (between title and import buttons)
    _stemHeightSlider = [[NSSlider alloc] init];
    _stemHeightSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _stemHeightSlider.minValue = kStemRowHeightMin;
    _stemHeightSlider.maxValue = kStemRowHeightMax;
    _stemHeightSlider.doubleValue = _stemRowHeight;
    _stemHeightSlider.continuous = YES;
    _stemHeightSlider.target = self;
    _stemHeightSlider.action = @selector(stemHeightSliderChanged:);
    _stemHeightSlider.controlSize = NSControlSizeMini;
    _stemHeightSlider.toolTip = @"Stem row height (Cmd-click to reset)";
    [_headerView addSubview:_stemHeightSlider];

    _importButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"plus.circle"
                                                       accessibilityDescription:@"Import stems"]
                                       target:self
                                       action:@selector(importButtonClicked:)];
    _importButton.translatesAutoresizingMaskIntoConstraints = NO;
    _importButton.bordered = YES;
    _importButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    _importButton.showsBorderOnlyWhileMouseInside = YES;
    _importButton.contentTintColor = [NSColor secondaryLabelColor];
    _importButton.toolTip = @"Import audio stems";
    [_headerView addSubview:_importButton];

    // Click on header title/empty space toggles collapse
    NSClickGestureRecognizer *headerClick = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(headerClicked:)];
    headerClick.numberOfClicksRequired = 1;
    [_headerView addGestureRecognizer:headerClick];
}

- (void)setupRowHeaders {
    _rowHeadersScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _rowHeadersScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _rowHeadersScrollView.hasVerticalScroller = NO;
    _rowHeadersScrollView.hasHorizontalScroller = NO;
    _rowHeadersScrollView.borderType = NSNoBorder;
    _rowHeadersScrollView.backgroundColor = [NSColor colorWithWhite:0.14 alpha:1.0];
    _rowHeadersScrollView.drawsBackground = YES;

    _rowHeadersDocView = [[XLFlippedDocumentView alloc] initWithFrame:NSZeroRect];
    _rowHeadersDocView.wantsLayer = YES;
    _rowHeadersScrollView.documentView = _rowHeadersDocView;

    [self addSubview:_rowHeadersScrollView];
}

- (void)setupScrollView {
    _scrollView = [[XLVerticalOnlyScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.verticalScroller.controlSize = NSControlSizeSmall;
    _scrollView.borderType = NSNoBorder;
    _scrollView.backgroundColor = [NSColor colorWithWhite:0.10 alpha:1.0];
    _scrollView.drawsBackground = YES;

    _stackDocumentView = [[XLFlippedDocumentView alloc] initWithFrame:NSZeroRect];
    _stackDocumentView.wantsLayer = YES;
    _scrollView.documentView = _stackDocumentView;

    [self addSubview:_scrollView];

    // Sync row headers scroll with waveform scroll
    _scrollView.contentView.postsBoundsChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(waveformScrollDidChange:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:_scrollView.contentView];

    // Mouse tracking for cursor line and click-to-seek
    _waveformTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                         options:(NSTrackingMouseMoved |
                                                                  NSTrackingMouseEnteredAndExited |
                                                                  NSTrackingActiveInActiveApp |
                                                                  NSTrackingInVisibleRect)
                                                           owner:self
                                                        userInfo:nil];
    [_scrollView addTrackingArea:_waveformTrackingArea];
}

- (void)setupResizeHandle {
    _resizeHandle = [[XLStemsResizeHandle alloc] initWithFrame:NSZeroRect];
    _resizeHandle.translatesAutoresizingMaskIntoConstraints = NO;
    _resizeHandle.container = self;
    [self addSubview:_resizeHandle];
}

- (void)setupConstraints {
    _rowHeadersWidthConstraint = [_rowHeadersScrollView.widthAnchor constraintEqualToConstant:_rowHeaderWidth];

    [NSLayoutConstraint activateConstraints:@[
        // Header: top, full width, fixed height
        [_headerView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_headerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_headerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_headerView.heightAnchor constraintEqualToConstant:kStemsHeaderHeight],

        // Chevron button
        [_chevronButton.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:6],
        [_chevronButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_chevronButton.widthAnchor constraintEqualToConstant:18],
        [_chevronButton.heightAnchor constraintEqualToConstant:18],

        // Title label
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_chevronButton.trailingAnchor constant:4],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],

        // Stem height slider: centered, between title and import buttons
        [_stemHeightSlider.leadingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor constant:12],
        [_stemHeightSlider.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_stemHeightSlider.widthAnchor constraintEqualToConstant:80],

        // Import button: right side
        [_importButton.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-6],
        [_importButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_importButton.widthAnchor constraintEqualToConstant:20],
        [_importButton.heightAnchor constraintEqualToConstant:20],

        // Row headers scroll view: left side, below header, above resize handle
        [_rowHeadersScrollView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_rowHeadersScrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_rowHeadersScrollView.bottomAnchor constraintEqualToAnchor:_resizeHandle.topAnchor],
        _rowHeadersWidthConstraint,

        // Waveform scroll view: right of row headers, below header, above resize handle
        [_scrollView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:_rowHeadersScrollView.trailingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_resizeHandle.topAnchor],

        // Resize handle: bottom, full width
        [_resizeHandle.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_resizeHandle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_resizeHandle.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_resizeHandle.heightAnchor constraintEqualToConstant:kStemsResizeHandleHeight],
    ]];
}

#pragma mark - Row Header Width

- (void)setRowHeaderWidth:(CGFloat)rowHeaderWidth {
    _rowHeaderWidth = rowHeaderWidth;
    _rowHeadersWidthConstraint.constant = rowHeaderWidth;
}

#pragma mark - Vertical Scroll Sync

- (void)waveformScrollDidChange:(NSNotification *)note {
    if (_syncingScroll) return;
    _syncingScroll = YES;
    NSPoint origin = _scrollView.contentView.bounds.origin;
    [_rowHeadersScrollView.contentView scrollToPoint:NSMakePoint(0, origin.y)];
    [_rowHeadersScrollView reflectScrolledClipView:_rowHeadersScrollView.contentView];
    _syncingScroll = NO;
}

#pragma mark - Collapse/Expand

- (void)setCollapsed:(BOOL)collapsed {
    _collapsed = collapsed;
    [[NSUserDefaults standardUserDefaults] setBool:collapsed forKey:kDefaultsCollapsedKey];
    [self updateChevronImage];
}

- (void)toggleCollapsed {
    self.collapsed = !_collapsed;

    CGFloat targetHeight = _collapsed ? kStemsHeaderHeight : _savedExpandedHeight;
    if ([_delegate respondsToSelector:@selector(stemsContainer:didChangeHeight:)]) {
        [_delegate stemsContainer:self didChangeHeight:targetHeight];
    }
}

- (void)updateChevronImage {
    NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightMedium];
    _chevronButton.image = [[NSImage imageWithSystemSymbolName:(_collapsed ? @"chevron.right" : @"chevron.down")
                                      accessibilityDescription:@"Toggle stems"]
                            imageWithSymbolConfiguration:config];
}

- (CGFloat)currentHeight {
    if (_collapsed) return kStemsHeaderHeight;
    return _savedExpandedHeight;
}

- (void)setExpandedHeight:(CGFloat)height {
    _savedExpandedHeight = height;
    [[NSUserDefaults standardUserDefaults] setDouble:height forKey:kDefaultsExpandedHeightKey];
}

#pragma mark - Stem Manager Changes

- (void)stemManagerDidChange:(NSNotification *)note {
    [self reloadStems];
}

- (void)reloadStems {
    // Remove old views
    for (XLMiniWaveformView *mv in _miniWaveformViews) {
        [mv removeFromSuperview];
    }
    [_miniWaveformViews removeAllObjects];

    for (XLStemRowHeaderView *rh in _rowHeaderViews) {
        [rh removeFromSuperview];
    }
    [_rowHeaderViews removeAllObjects];

    NSArray<XLStemData *> *stems = _stemManager.stems;

    // Update title
    if (stems.count > 0) {
        _titleLabel.stringValue = [NSString stringWithFormat:@"Stems (%lu)", (unsigned long)stems.count];
    } else {
        _titleLabel.stringValue = @"Stems";
        _collapsed = YES;
        [self updateChevronImage];
        if ([_delegate respondsToSelector:@selector(stemsContainer:didChangeHeight:)]) {
            [_delegate stemsContainer:self didChangeHeight:kStemsHeaderHeight];
        }
        return;
    }

    // Create mini waveform views and row header views
    CGFloat waveWidth = NSWidth(_scrollView.bounds);
    if (waveWidth < 100) waveWidth = 800;
    CGFloat y = 0;

    NSUInteger stemIdx = 0;
    for (XLStemData *stem in stems) {
        // Row header (left side)
        XLStemRowHeaderView *rh = [[XLStemRowHeaderView alloc] initWithFrame:NSMakeRect(0, y, _rowHeaderWidth, _stemRowHeight)];
        rh.autoresizingMask = NSViewWidthSizable;
        rh.stemName = stem.name;
        rh.stemColor = stem.waveformColor;
        rh.stemIndex = stemIdx;
        rh.delegate = self;
        [_rowHeadersDocView addSubview:rh];
        [_rowHeaderViews addObject:rh];

        // Mini waveform (right side)
        XLMiniWaveformView *mv = [[XLMiniWaveformView alloc] initWithFrame:NSMakeRect(0, y, waveWidth, _stemRowHeight)];
        mv.autoresizingMask = NSViewWidthSizable;
        [_stackDocumentView addSubview:mv];
        [_miniWaveformViews addObject:mv];

        mv.stemData = stem;
        mv.zoomLevel = _zoomLevel;
        mv.scrollOffsetX = _scrollOffsetX;
        mv.sequenceLengthMS = _sequenceLengthMS;
        mv.playbackPositionMS = _playbackPositionMS;
        mv.cursorPositionMS = _cursorPositionMS;

        y += _stemRowHeight;
        stemIdx++;
    }

    // Set document view frames for scrollable content size
    [_stackDocumentView setFrame:NSMakeRect(0, 0, waveWidth, y)];
    [_rowHeadersDocView setFrame:NSMakeRect(0, 0, _rowHeaderWidth, y)];

    // Auto-expand if stems were just added and panel is collapsed
    if (stems.count > 0 && _collapsed) {
        self.collapsed = NO;
        CGFloat targetHeight = _savedExpandedHeight;
        if ([_delegate respondsToSelector:@selector(stemsContainer:didChangeHeight:)]) {
            [_delegate stemsContainer:self didChangeHeight:targetHeight];
        }
    }
}

- (void)setOnsetPreviewTimesMS:(NSArray<NSNumber *> *)timesMS forStemAtIndex:(NSUInteger)stemIndex {
    if (stemIndex < _miniWaveformViews.count) {
        _miniWaveformViews[stemIndex].onsetPreviewTimesMS = timesMS;
    }
}

#pragma mark - Scroll/Zoom Forwarding

- (void)setScrollOffsetX:(CGFloat)offsetX {
    _scrollOffsetX = offsetX;
    for (XLMiniWaveformView *mv in _miniWaveformViews) {
        mv.scrollOffsetX = offsetX;
    }
}

- (void)setZoomLevel:(CGFloat)zoomLevel {
    _zoomLevel = zoomLevel;
    for (XLMiniWaveformView *mv in _miniWaveformViews) {
        mv.zoomLevel = zoomLevel;
    }
}

- (void)setSequenceLengthMS:(CGFloat)lengthMS {
    _sequenceLengthMS = lengthMS;
    for (XLMiniWaveformView *mv in _miniWaveformViews) {
        mv.sequenceLengthMS = lengthMS;
    }
}

- (void)setPlaybackPositionMS:(CGFloat)positionMS {
    _playbackPositionMS = positionMS;
    for (XLMiniWaveformView *mv in _miniWaveformViews) {
        mv.playbackPositionMS = positionMS;
    }
}

#pragma mark - Scroll Forwarding to Scroll Coordinator

- (void)scrollWheel:(NSEvent *)event {
    XLScrollCoordinator *sc = _scrollCoordinator;
    if (!sc) {
        [super scrollWheel:event];
        return;
    }

    if (event.modifierFlags & NSEventModifierFlagCommand) {
        NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
        CGFloat pointX = loc.x - _rowHeaderWidth;
        CGFloat factor = 1.0 + event.scrollingDeltaY * 0.05;
        factor = fmax(0.5, fmin(factor, 2.0));
        CGFloat newZoom = sc.zoomLevel * factor;
        [sc setZoomLevel:newZoom centeredOnPointX:pointX];
        return;
    }

    if (event.modifierFlags & NSEventModifierFlagShift) {
        CGFloat dx = event.scrollingDeltaY;
        [sc setHorizontalScrollOffset:sc.horizontalScrollOffset - dx];
        return;
    }

    CGFloat dx = event.scrollingDeltaX;
    if (fabs(dx) > 0.01) {
        [sc setHorizontalScrollOffset:sc.horizontalScrollOffset - dx];
        return;
    }

    [super scrollWheel:event];
}

#pragma mark - Mouse Tracking (Cursor Line + Click-to-Seek)

- (CGFloat)timeMSForMouseEvent:(NSEvent *)event {
    NSPoint loc = [_scrollView convertPoint:event.locationInWindow fromView:nil];
    CGFloat timeMS = (loc.x + _scrollOffsetX) / _zoomLevel;
    return fmax(0, fmin(timeMS, _sequenceLengthMS));
}

- (void)mouseMoved:(NSEvent *)event {
    CGFloat timeMS = [self timeMSForMouseEvent:event];
    [self updateCursorFromLocalEvent:timeMS];
}

- (void)mouseExited:(NSEvent *)event {
    [self updateCursorFromLocalEvent:-1];
}

- (void)mouseDown:(NSEvent *)event {
    // Check if click is within the scroll view (waveform area)
    NSPoint locInSelf = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(locInSelf, _scrollView.frame)) return;

    CGFloat timeMS = [self timeMSForMouseEvent:event];
    _isScrubbing = YES;

    if ([_delegate respondsToSelector:@selector(stemsContainer:didSeekToTimeMS:)]) {
        [_delegate stemsContainer:self didSeekToTimeMS:timeMS];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_isScrubbing) return;

    CGFloat timeMS = [self timeMSForMouseEvent:event];
    [self setCursorPositionMS:timeMS];

    if ([_delegate respondsToSelector:@selector(stemsContainer:didSeekToTimeMS:)]) {
        [_delegate stemsContainer:self didSeekToTimeMS:timeMS];
    }
}

- (void)mouseUp:(NSEvent *)event {
    _isScrubbing = NO;
}

- (void)updateCursorFromLocalEvent:(CGFloat)positionMS {
    [self setCursorPositionMS:positionMS];
    if ([_delegate respondsToSelector:@selector(stemsContainer:didMoveCursorToTimeMS:)]) {
        [_delegate stemsContainer:self didMoveCursorToTimeMS:positionMS];
    }
}

- (void)setCursorPositionMS:(CGFloat)positionMS {
    if (fabs(positionMS - _cursorPositionMS) < 0.01) return;
    _cursorPositionMS = positionMS;
    for (XLMiniWaveformView *mv in _miniWaveformViews) {
        mv.cursorPositionMS = positionMS;
    }
}

#pragma mark - Actions

- (void)headerClicked:(NSClickGestureRecognizer *)gesture {
    [self toggleCollapsed];
}

- (void)stemHeightSliderChanged:(NSSlider *)sender {
    NSEvent *currentEvent = [NSApp currentEvent];
    if (currentEvent && (currentEvent.modifierFlags & NSEventModifierFlagCommand)) {
        sender.doubleValue = kStemRowHeightDefault;
    }

    _stemRowHeight = sender.doubleValue;
    [[NSUserDefaults standardUserDefaults] setDouble:_stemRowHeight forKey:kDefaultsStemRowHeightKey];
    [self reloadStems];
}

#pragma mark - Stem Row Header Delegate

- (void)stemRowDidReorder:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex {
    [_stemManager moveStemAtIndex:fromIndex toIndex:toIndex];
}

- (void)stemRowDidRequestEdit:(NSUInteger)index {
    NSArray<XLStemData *> *stems = _stemManager.stems;
    if (index >= stems.count) return;
    XLStemData *stem = stems[index];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Edit Stem";
    alert.informativeText = @"Change the display name and waveform color.";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 260, 62)];

    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 34, 260, 24)];
    nameField.stringValue = stem.name ?: @"";
    nameField.placeholderString = @"Stem name";
    [accessory addSubview:nameField];

    NSColorWell *colorWell;
    if (@available(macOS 13.0, *)) {
        colorWell = [NSColorWell colorWellWithStyle:NSColorWellStyleMinimal];
        colorWell.frame = NSMakeRect(0, 0, 44, 28);
    } else {
        colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 28)];
    }
    colorWell.color = stem.waveformColor ?: [NSColor whiteColor];
    [accessory addSubview:colorWell];

    NSTextField *colorLabel = [NSTextField labelWithString:@"Color:"];
    colorLabel.frame = NSMakeRect(50, 4, 200, 20);
    colorLabel.font = [NSFont systemFontOfSize:12];
    [accessory addSubview:colorLabel];

    alert.accessoryView = accessory;
    [alert.window setInitialFirstResponder:nameField];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSString *newName = nameField.stringValue;
        if (newName.length == 0) newName = stem.name;
        [_stemManager updateStemAtIndex:index name:newName color:colorWell.color];
    }
}

- (void)stemRowDidRequestContextMenu:(NSUInteger)index atPoint:(NSPoint)point inView:(NSView *)view {
    NSArray<XLStemData *> *stems = _stemManager.stems;
    if (index >= stems.count) return;
    XLStemData *stem = stems[index];

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Stem"];

    NSMenuItem *onsetItem = [[NSMenuItem alloc] initWithTitle:@"Create Timing Track from Audio..."
                                                      action:@selector(contextMenuOnsetDetection:)
                                               keyEquivalent:@""];
    onsetItem.target = self;
    onsetItem.tag = index;
    onsetItem.enabled = (stem.audioData != nil && !stem.isLoading);
    [menu addItem:onsetItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit Stem..."
                                                     action:@selector(contextMenuEditStem:)
                                              keyEquivalent:@""];
    editItem.target = self;
    editItem.tag = index;
    [menu addItem:editItem];

    NSMenuItem *removeItem = [[NSMenuItem alloc] initWithTitle:@"Remove Stem"
                                                       action:@selector(contextMenuRemoveStem:)
                                                keyEquivalent:@""];
    removeItem.target = self;
    removeItem.tag = index;
    [menu addItem:removeItem];

    [NSMenu popUpContextMenu:menu withEvent:[NSApp currentEvent] forView:view];
}

- (void)contextMenuOnsetDetection:(NSMenuItem *)sender {
    NSUInteger idx = (NSUInteger)sender.tag;
    if ([_delegate respondsToSelector:@selector(stemsContainer:didRequestOnsetDetectionForStemAtIndex:)]) {
        [_delegate stemsContainer:self didRequestOnsetDetectionForStemAtIndex:idx];
    }
}

- (void)contextMenuEditStem:(NSMenuItem *)sender {
    NSUInteger idx = (NSUInteger)sender.tag;
    if ([_delegate respondsToSelector:@selector(stemsContainer:didRequestEditStemAtIndex:)]) {
        [_delegate stemsContainer:self didRequestEditStemAtIndex:idx];
    } else {
        [self stemRowDidRequestEdit:idx];
    }
}

- (void)contextMenuRemoveStem:(NSMenuItem *)sender {
    NSUInteger idx = (NSUInteger)sender.tag;
    if ([_delegate respondsToSelector:@selector(stemsContainer:didRequestRemoveStemAtIndex:)]) {
        [_delegate stemsContainer:self didRequestRemoveStemAtIndex:idx];
    }
}

- (void)importButtonClicked:(id)sender {
    if ([_delegate respondsToSelector:@selector(stemsContainerDidRequestImport:)]) {
        [_delegate stemsContainerDidRequestImport:self];
    }
}

@end
