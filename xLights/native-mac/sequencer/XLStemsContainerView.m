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

static NSString *const kDefaultsCollapsedKey = @"StemsPanel.collapsed";
static NSString *const kDefaultsExpandedHeightKey = @"StemsPanel.expandedHeight";

static const CGFloat kRowHeaderFontSize = 11.0;
static const CGFloat kRowHeaderLeftPadding = 8.0;

#pragma mark - Resize Handle View

@interface XLStemsResizeHandle : NSView
@property (nonatomic, weak) XLStemsContainerView *container;
@end

@implementation XLStemsResizeHandle {
    NSPoint _dragStartPoint;
    CGFloat _dragStartHeight;
    BOOL _isDragging;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor colorWithWhite:0.18 alpha:1.0] CGColor];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    CGFloat cx = NSMidX(self.bounds);
    CGFloat cy = NSMidY(self.bounds);
    [[NSColor colorWithWhite:0.45 alpha:1.0] setFill];
    for (int i = -1; i <= 1; i++) {
        NSRect dot = NSMakeRect(cx + i * 8 - 1.5, cy - 1.5, 3, 3);
        [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
    }
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor resizeUpDownCursor]];
}

- (void)mouseDown:(NSEvent *)event {
    _dragStartPoint = event.locationInWindow;
    _dragStartHeight = _container.currentHeight;
    _isDragging = YES;
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_isDragging) return;
    CGFloat delta = _dragStartPoint.y - event.locationInWindow.y;
    CGFloat newHeight = _dragStartHeight + delta;
    newHeight = fmax(kStemsMinExpandedHeight, fmin(newHeight, kStemsMaxExpandedHeight));

    if ([_container.delegate respondsToSelector:@selector(stemsContainer:didChangeHeight:)]) {
        [_container.delegate stemsContainer:_container didChangeHeight:newHeight];
    }

    [[NSUserDefaults standardUserDefaults] setDouble:newHeight forKey:kDefaultsExpandedHeightKey];
}

- (void)mouseUp:(NSEvent *)event {
    _isDragging = NO;
}

@end

#pragma mark - Flipped Document View

@interface XLFlippedDocumentView : NSView
@end

@implementation XLFlippedDocumentView
- (BOOL)isFlipped { return YES; }
@end

#pragma mark - Stem Row Header View (draws one stem name)

@interface XLStemRowHeaderView : NSView
@property (nonatomic, copy) NSString *stemName;
@property (nonatomic, strong) NSColor *stemColor;
@end

@implementation XLStemRowHeaderView

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }

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

@implementation XLStemsContainerView {
    NSView *_headerView;
    NSButton *_chevronButton;
    NSTextField *_titleLabel;
    NSButton *_importButton;
    NSButton *_importFolderButton;

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
    CGFloat _scrollOffsetX;
    CGFloat _zoomLevel;
    CGFloat _sequenceLengthMS;
    CGFloat _playbackPositionMS;

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
        _rowHeaderWidth = 180.0;  // Default, overridden by sequencer VC

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _collapsed = [defaults boolForKey:kDefaultsCollapsedKey];
        _savedExpandedHeight = [defaults doubleForKey:kDefaultsExpandedHeightKey];
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

    _importButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"plus.circle"
                                                       accessibilityDescription:@"Import stems"]
                                       target:self
                                       action:@selector(importButtonClicked:)];
    _importButton.translatesAutoresizingMaskIntoConstraints = NO;
    _importButton.bordered = NO;
    _importButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    _importButton.contentTintColor = [NSColor secondaryLabelColor];
    _importButton.toolTip = @"Import audio stems";
    [_headerView addSubview:_importButton];

    _importFolderButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"folder.badge.plus"
                                                               accessibilityDescription:@"Import stems from folder"]
                                             target:self
                                             action:@selector(importFolderButtonClicked:)];
    _importFolderButton.translatesAutoresizingMaskIntoConstraints = NO;
    _importFolderButton.bordered = NO;
    _importFolderButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    _importFolderButton.contentTintColor = [NSColor secondaryLabelColor];
    _importFolderButton.toolTip = @"Import stems from folder (Demucs/Spleeter output)";
    [_headerView addSubview:_importFolderButton];
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
    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
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

        // Import from folder button: right side
        [_importFolderButton.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-6],
        [_importFolderButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_importFolderButton.widthAnchor constraintEqualToConstant:20],
        [_importFolderButton.heightAnchor constraintEqualToConstant:20],

        // Import button: left of folder button
        [_importButton.trailingAnchor constraintEqualToAnchor:_importFolderButton.leadingAnchor constant:-4],
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

    for (XLStemData *stem in stems) {
        // Row header (left side)
        XLStemRowHeaderView *rh = [[XLStemRowHeaderView alloc] initWithFrame:NSMakeRect(0, y, _rowHeaderWidth, kMiniWaveformHeight)];
        rh.autoresizingMask = NSViewWidthSizable;
        rh.stemName = stem.name;
        rh.stemColor = stem.waveformColor;
        [_rowHeadersDocView addSubview:rh];
        [_rowHeaderViews addObject:rh];

        // Mini waveform (right side)
        XLMiniWaveformView *mv = [[XLMiniWaveformView alloc] initWithFrame:NSMakeRect(0, y, waveWidth, kMiniWaveformHeight)];
        mv.autoresizingMask = NSViewWidthSizable;
        [_stackDocumentView addSubview:mv];
        [_miniWaveformViews addObject:mv];

        mv.stemData = stem;
        mv.zoomLevel = _zoomLevel;
        mv.scrollOffsetX = _scrollOffsetX;
        mv.sequenceLengthMS = _sequenceLengthMS;
        mv.playbackPositionMS = _playbackPositionMS;

        y += kMiniWaveformHeight;
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

#pragma mark - Actions

- (void)importButtonClicked:(id)sender {
    if ([_delegate respondsToSelector:@selector(stemsContainerDidRequestImport:)]) {
        [_delegate stemsContainerDidRequestImport:self];
    }
}

- (void)importFolderButtonClicked:(id)sender {
    if ([_delegate respondsToSelector:@selector(stemsContainerDidRequestImportFromFolder:)]) {
        [_delegate stemsContainerDidRequestImportFromFolder:self];
    }
}

@end
