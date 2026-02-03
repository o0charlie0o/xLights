/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLRenderProgressDialog.h"

static const CGFloat kDialogWidth = 500.0;
static const CGFloat kDialogMinHeight = 300.0;
static const CGFloat kRowHeight = 40.0;
static const CGFloat kPadding = 12.0;

@implementation XLRenderProgressItem
@end

@interface XLRenderProgressRowView : NSView

@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSProgressIndicator *progressBar;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSImageView *checkmarkView;

@end

@implementation XLRenderProgressRowView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    _nameLabel = [NSTextField labelWithString:@""];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    [self addSubview:_nameLabel];

    _progressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    _progressBar.style = NSProgressIndicatorStyleBar;
    _progressBar.minValue = 0.0;
    _progressBar.maxValue = 1.0;
    _progressBar.doubleValue = 0.0;
    [self addSubview:_progressBar];

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = [NSFont systemFontOfSize:10];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    [self addSubview:_statusLabel];

    _checkmarkView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _checkmarkView.translatesAutoresizingMaskIntoConstraints = NO;
    _checkmarkView.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill"
                                     accessibilityDescription:@"Complete"];
    _checkmarkView.contentTintColor = [NSColor systemGreenColor];
    _checkmarkView.hidden = YES;
    [self addSubview:_checkmarkView];

    [NSLayoutConstraint activateConstraints:@[
        [_nameLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kPadding],
        [_nameLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
        [_nameLabel.widthAnchor constraintEqualToConstant:150],

        [_progressBar.leadingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor constant:kPadding],
        [_progressBar.trailingAnchor constraintEqualToAnchor:_checkmarkView.leadingAnchor constant:-kPadding],
        [_progressBar.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-6],

        [_statusLabel.leadingAnchor constraintEqualToAnchor:_progressBar.leadingAnchor],
        [_statusLabel.topAnchor constraintEqualToAnchor:_progressBar.bottomAnchor constant:2],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_progressBar.trailingAnchor],

        [_checkmarkView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kPadding],
        [_checkmarkView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_checkmarkView.widthAnchor constraintEqualToConstant:20],
        [_checkmarkView.heightAnchor constraintEqualToConstant:20],
    ]];
}

- (void)setCompleted:(BOOL)completed {
    _checkmarkView.hidden = !completed;
    if (completed) {
        _progressBar.doubleValue = 1.0;
    }
}

@end

@interface XLRenderProgressDialog ()

@property (nonatomic, strong, readwrite) NSWindow *window;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSStackView *progressStack;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSMutableDictionary<NSString *, XLRenderProgressRowView *> *rowViews;
@property (nonatomic, assign, readwrite) BOOL isComplete;

@end

@implementation XLRenderProgressDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        _rowViews = [NSMutableDictionary dictionary];
        _isComplete = NO;
        [self buildWindow];
    }
    return self;
}

- (void)buildWindow {
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kDialogWidth, kDialogMinHeight)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:YES];
    _window.title = @"Rendering Progress";
    _window.minSize = NSMakeSize(kDialogWidth, kDialogMinHeight);

    NSView *contentView = [[NSView alloc] initWithFrame:_window.contentView.bounds];
    _window.contentView = contentView;

    // Scroll view
    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.borderType = NSNoBorder;
    _scrollView.drawsBackground = NO;
    [contentView addSubview:_scrollView];

    // Stack view for progress rows
    _progressStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _progressStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _progressStack.alignment = NSLayoutAttributeLeading;
    _progressStack.spacing = 0;

    NSView *stackContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    stackContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [stackContainer addSubview:_progressStack];
    _progressStack.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [_progressStack.topAnchor constraintEqualToAnchor:stackContainer.topAnchor],
        [_progressStack.leadingAnchor constraintEqualToAnchor:stackContainer.leadingAnchor],
        [_progressStack.trailingAnchor constraintEqualToAnchor:stackContainer.trailingAnchor],
        [_progressStack.bottomAnchor constraintLessThanOrEqualToAnchor:stackContainer.bottomAnchor],
    ]];

    _scrollView.documentView = stackContainer;

    // Close button
    _closeButton = [NSButton buttonWithTitle:@"OK" target:self action:@selector(closeClicked:)];
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _closeButton.keyEquivalent = @"\r";
    [contentView addSubview:_closeButton];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_closeButton.topAnchor constant:-kPadding],

        [_closeButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kPadding],
        [_closeButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-kPadding],
    ]];
}

#pragma mark - Public Methods

- (void)showForWindow:(NSWindow *)parentWindow {
    [_window center];
    [_window makeKeyAndOrderFront:nil];
}

- (void)close {
    [_window close];
}

- (void)closeClicked:(id)sender {
    [self close];
}

- (void)addProgressItemForModel:(NSString *)modelName {
    if (_rowViews[modelName]) {
        return; // Already exists
    }

    XLRenderProgressRowView *row = [[XLRenderProgressRowView alloc]
                                     initWithFrame:NSMakeRect(0, 0, kDialogWidth - 40, kRowHeight)];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.nameLabel.stringValue = modelName;

    [_progressStack addArrangedSubview:row];
    [row.heightAnchor constraintEqualToConstant:kRowHeight].active = YES;
    [row.leadingAnchor constraintEqualToAnchor:_progressStack.leadingAnchor].active = YES;
    [row.trailingAnchor constraintEqualToAnchor:_progressStack.trailingAnchor].active = YES;

    _rowViews[modelName] = row;

    // Update scroll view document size
    NSView *doc = _scrollView.documentView;
    [doc setFrameSize:NSMakeSize(_scrollView.contentSize.width, _progressStack.fittingSize.height)];
}

- (void)updateProgressForModel:(NSString *)modelName progress:(double)progress {
    XLRenderProgressRowView *row = _rowViews[modelName];
    if (row) {
        row.progressBar.doubleValue = progress;
    }
}

- (void)updateStatusForModel:(NSString *)modelName status:(NSString *)status {
    XLRenderProgressRowView *row = _rowViews[modelName];
    if (row) {
        row.statusLabel.stringValue = status ?: @"";
    }
}

- (void)markCompleted:(NSString *)modelName {
    XLRenderProgressRowView *row = _rowViews[modelName];
    if (row) {
        [row setCompleted:YES];
    }

    [self checkAllCompleted];
}

- (void)markAllCompleted {
    for (XLRenderProgressRowView *row in _rowViews.allValues) {
        [row setCompleted:YES];
    }
    _isComplete = YES;
}

- (void)checkAllCompleted {
    BOOL allDone = YES;
    for (XLRenderProgressRowView *row in _rowViews.allValues) {
        if (row.checkmarkView.hidden) {
            allDone = NO;
            break;
        }
    }
    _isComplete = allDone;
}

- (void)clearAll {
    for (NSView *view in _progressStack.arrangedSubviews) {
        [_progressStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    [_rowViews removeAllObjects];
    _isComplete = NO;
}

@end
