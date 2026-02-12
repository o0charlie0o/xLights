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
    // Draw grip dots (3 dots in the center)
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
    _dragStartPoint = [self convertPoint:event.locationInWindow fromView:nil];
    _dragStartHeight = _container.currentHeight;
    _isDragging = YES;
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_isDragging) return;
    NSPoint currentPoint = [self convertPoint:event.locationInWindow fromView:nil];
    // In flipped coordinates, dragging down increases height
    CGFloat delta = currentPoint.y - _dragStartPoint.y;
    CGFloat newHeight = _dragStartHeight + delta;
    newHeight = fmax(kStemsMinExpandedHeight, fmin(newHeight, kStemsMaxExpandedHeight));

    if ([_container.delegate respondsToSelector:@selector(stemsContainer:didChangeHeight:)]) {
        [_container.delegate stemsContainer:_container didChangeHeight:newHeight];
    }

    // Persist the expanded height
    [[NSUserDefaults standardUserDefaults] setDouble:newHeight forKey:kDefaultsExpandedHeightKey];
}

- (void)mouseUp:(NSEvent *)event {
    _isDragging = NO;
}

@end

#pragma mark - Stems Container View

@implementation XLStemsContainerView {
    NSView *_headerView;
    NSButton *_chevronButton;
    NSTextField *_titleLabel;
    NSButton *_importButton;
    NSButton *_importFolderButton;

    NSScrollView *_scrollView;
    NSView *_stackDocumentView;  // Holds the mini waveform views vertically

    XLStemsResizeHandle *_resizeHandle;

    NSMutableArray<XLMiniWaveformView *> *_miniWaveformViews;
    NSLayoutConstraint *_docHeightConstraint;

    CGFloat _savedExpandedHeight;
    CGFloat _scrollOffsetX;
    CGFloat _zoomLevel;
    CGFloat _sequenceLengthMS;
    CGFloat _playbackPositionMS;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor colorWithWhite:0.12 alpha:1.0] CGColor];
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _miniWaveformViews = [NSMutableArray array];
        _zoomLevel = 0.1;
        _sequenceLengthMS = 60000;
        _playbackPositionMS = -1;

        // Restore persisted state
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _collapsed = [defaults boolForKey:kDefaultsCollapsedKey];
        _savedExpandedHeight = [defaults doubleForKey:kDefaultsExpandedHeightKey];
        if (_savedExpandedHeight < kStemsMinExpandedHeight) {
            _savedExpandedHeight = kStemsDefaultExpandedHeight;
        }

        [self setupHeader];
        [self setupScrollView];
        [self setupResizeHandle];
        [self setupConstraints];

        // Observe stem manager changes
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

    // Chevron button (disclosure triangle)
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

    // Title label
    _titleLabel = [NSTextField labelWithString:@"Stems"];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _titleLabel.textColor = [NSColor secondaryLabelColor];
    [_headerView addSubview:_titleLabel];

    // Import button
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

    // Import from folder button
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

- (void)setupScrollView {
    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.verticalScroller.controlSize = NSControlSizeSmall;
    _scrollView.borderType = NSNoBorder;
    _scrollView.backgroundColor = [NSColor colorWithWhite:0.10 alpha:1.0];
    _scrollView.drawsBackground = YES;

    _stackDocumentView = [[NSView alloc] initWithFrame:NSZeroRect];
    _stackDocumentView.translatesAutoresizingMaskIntoConstraints = NO;
    _stackDocumentView.wantsLayer = YES;
    _scrollView.documentView = _stackDocumentView;

    [self addSubview:_scrollView];
}

- (void)setupResizeHandle {
    _resizeHandle = [[XLStemsResizeHandle alloc] initWithFrame:NSZeroRect];
    _resizeHandle.translatesAutoresizingMaskIntoConstraints = NO;
    _resizeHandle.container = self;
    [self addSubview:_resizeHandle];
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        // Header: top, full width, fixed height
        [_headerView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_headerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_headerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_headerView.heightAnchor constraintEqualToConstant:kStemsHeaderHeight],

        // Chevron button: left of header
        [_chevronButton.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:6],
        [_chevronButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_chevronButton.widthAnchor constraintEqualToConstant:18],
        [_chevronButton.heightAnchor constraintEqualToConstant:18],

        // Title label: right of chevron
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_chevronButton.trailingAnchor constant:4],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],

        // Import from folder button: right side of header
        [_importFolderButton.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-6],
        [_importFolderButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_importFolderButton.widthAnchor constraintEqualToConstant:20],
        [_importFolderButton.heightAnchor constraintEqualToConstant:20],

        // Import button: left of folder button
        [_importButton.trailingAnchor constraintEqualToAnchor:_importFolderButton.leadingAnchor constant:-4],
        [_importButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_importButton.widthAnchor constraintEqualToConstant:20],
        [_importButton.heightAnchor constraintEqualToConstant:20],

        // Scroll view: below header, above resize handle
        [_scrollView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        // Resize handle: bottom, full width, fixed height
        [_resizeHandle.topAnchor constraintEqualToAnchor:_scrollView.bottomAnchor],
        [_resizeHandle.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_resizeHandle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_resizeHandle.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_resizeHandle.heightAnchor constraintEqualToConstant:kStemsResizeHandleHeight],

        // Stack document view: match scroll view width
        [_stackDocumentView.leadingAnchor constraintEqualToAnchor:_scrollView.contentView.leadingAnchor],
        [_stackDocumentView.trailingAnchor constraintEqualToAnchor:_scrollView.contentView.trailingAnchor],
        [_stackDocumentView.topAnchor constraintEqualToAnchor:_scrollView.contentView.topAnchor],
    ]];
}

#pragma mark - Collapse/Expand

- (void)setCollapsed:(BOOL)collapsed {
    _collapsed = collapsed;
    [[NSUserDefaults standardUserDefaults] setBool:collapsed forKey:kDefaultsCollapsedKey];
    [self updateChevronImage];
}

- (void)toggleCollapsed {
    self.collapsed = !_collapsed;

    CGFloat targetHeight = _collapsed ? 0 : _savedExpandedHeight;
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
    if (_collapsed) return 0;
    return _savedExpandedHeight;
}

#pragma mark - Stem Manager Changes

- (void)stemManagerDidChange:(NSNotification *)note {
    [self reloadStems];
}

- (void)reloadStems {
    // Remove old mini waveform views
    for (XLMiniWaveformView *mv in _miniWaveformViews) {
        [mv removeFromSuperview];
    }
    [_miniWaveformViews removeAllObjects];

    NSArray<XLStemData *> *stems = _stemManager.stems;

    // Update title
    if (stems.count > 0) {
        _titleLabel.stringValue = [NSString stringWithFormat:@"Stems (%lu)", (unsigned long)stems.count];
    } else {
        _titleLabel.stringValue = @"Stems";
    }

    // Create mini waveform views
    CGFloat y = 0;
    CGFloat width = NSWidth(self.bounds);
    if (width < 100) width = 800;

    for (XLStemData *stem in stems) {
        XLMiniWaveformView *mv = [[XLMiniWaveformView alloc] initWithFrame:NSMakeRect(0, y, width, kMiniWaveformHeight)];
        mv.translatesAutoresizingMaskIntoConstraints = NO;
        mv.stemData = stem;
        mv.zoomLevel = _zoomLevel;
        mv.scrollOffsetX = _scrollOffsetX;
        mv.sequenceLengthMS = _sequenceLengthMS;
        mv.playbackPositionMS = _playbackPositionMS;

        [_stackDocumentView addSubview:mv];
        [_miniWaveformViews addObject:mv];

        [NSLayoutConstraint activateConstraints:@[
            [mv.topAnchor constraintEqualToAnchor:_stackDocumentView.topAnchor constant:y],
            [mv.leadingAnchor constraintEqualToAnchor:_stackDocumentView.leadingAnchor],
            [mv.trailingAnchor constraintEqualToAnchor:_stackDocumentView.trailingAnchor],
            [mv.heightAnchor constraintEqualToConstant:kMiniWaveformHeight],
        ]];

        y += kMiniWaveformHeight;
    }

    // Update document view height for scrolling
    CGFloat docHeight = fmax(y, 1);
    if (_docHeightConstraint) {
        _docHeightConstraint.constant = docHeight;
    } else {
        _docHeightConstraint = [_stackDocumentView.heightAnchor constraintEqualToConstant:docHeight];
        _docHeightConstraint.priority = NSLayoutPriorityDefaultHigh;
        _docHeightConstraint.active = YES;
    }

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
