/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLSequencerEffectPanelView.h"

// Flipped NSView subclass so scroll view content starts at the top.
@interface XLSequencerEffectPanelFlippedView : NSView
@end

static const CGFloat kPlaceholderFontSize = 13.0;

@interface XLSequencerEffectPanelView ()

/// The builder instance that constructs and manages the panel controls.
@property (nonatomic, strong) XLEffectPanelBuilder *builder;

/// The currently displayed panel view (built from the descriptor).
@property (nonatomic, strong) NSView *panelContentView;

/// Scroll view wrapping the panel content for tall panels.
@property (nonatomic, strong) NSScrollView *scrollView;

/// Placeholder label shown when no effect is selected.
@property (nonatomic, strong) NSTextField *placeholderLabel;

/// Writable backing for the readonly descriptor property.
@property (nonatomic, strong, readwrite) XLEffectPanelDescriptor *descriptor;

/// Writable backing for the readonly settings property.
@property (nonatomic, strong, readwrite) NSDictionary<NSString *, id> *settings;

@end

@implementation XLSequencerEffectPanelView

// ---------------------------------------------------------------------------
// MARK: - Initialization
// ---------------------------------------------------------------------------

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
    self.builder = [[XLEffectPanelBuilder alloc] init];
    self.settings = @{};

    // Scroll view for panel content
    self.scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.hasHorizontalScroller = NO;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.drawsBackground = NO;
    self.scrollView.hidden = YES;
    [self addSubview:self.scrollView];

    [self.scrollView.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
    [self.scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = YES;
    [self.scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
    [self.scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = YES;

    // Placeholder
    self.placeholderLabel = [NSTextField labelWithString:@"No Effect Selected"];
    self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.placeholderLabel.font = [NSFont systemFontOfSize:kPlaceholderFontSize weight:NSFontWeightLight];
    self.placeholderLabel.textColor = [NSColor tertiaryLabelColor];
    self.placeholderLabel.alignment = NSTextAlignmentCenter;
    [self addSubview:self.placeholderLabel];

    [self.placeholderLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
    [self.placeholderLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
}

// ---------------------------------------------------------------------------
// MARK: - Public API
// ---------------------------------------------------------------------------

- (void)loadEffectPanel:(NSString *)effectName
               settings:(NSDictionary<NSString *, id> *)settings
{
    XLEffectPanelDescriptor *desc = [XLEffectPanelDescriptor descriptorForEffect:effectName];
    if (!desc) {
        [self showPlaceholderWithMessage:
            [NSString stringWithFormat:@"Unknown effect: %@", effectName]];
        return;
    }

    self.descriptor = desc;
    self.builder.delegate = self.delegate;

    NSView *panelView = [self.builder buildPanelForDescriptor:desc settings:settings ?: @{}];
    self.settings = [self.builder currentSettings];

    [self removePanelContent];

    self.panelContentView = panelView;

    // Wrap in a flipped clip view so content starts at the top
    NSView *documentView = [[XLSequencerEffectPanelFlippedView alloc] initWithFrame:NSZeroRect];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    [documentView addSubview:panelView];

    [panelView.topAnchor constraintEqualToAnchor:documentView.topAnchor].active = YES;
    [panelView.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor].active = YES;
    [panelView.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor].active = YES;
    [panelView.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor].active = YES;

    self.scrollView.documentView = documentView;

    // Match document view width to scroll view content width
    [documentView.widthAnchor constraintEqualToAnchor:self.scrollView.contentView.widthAnchor].active = YES;

    self.scrollView.hidden = NO;
    self.placeholderLabel.hidden = YES;
}

- (void)updateSettings:(NSDictionary<NSString *, id> *)settings
{
    if (!self.panelContentView || !settings) return;

    [self.builder updateControlsFromSettings:settings];
    self.settings = [self.builder currentSettings];
}

- (NSDictionary<NSString *, id> *)currentSettings
{
    if (!self.panelContentView) return @{};
    return [self.builder currentSettings];
}

- (void)showPlaceholder
{
    [self showPlaceholderWithMessage:@"No Effect Selected"];
}

// ---------------------------------------------------------------------------
// MARK: - Delegate forwarding
// ---------------------------------------------------------------------------

- (void)setDelegate:(id<XLEffectPanelBuilderDelegate>)delegate
{
    _delegate = delegate;
    self.builder.delegate = delegate;
}

// ---------------------------------------------------------------------------
// MARK: - Private helpers
// ---------------------------------------------------------------------------

- (void)removePanelContent
{
    if (self.panelContentView) {
        NSView *documentView = self.scrollView.documentView;
        self.scrollView.documentView = nil;
        [documentView removeFromSuperview];
        self.panelContentView = nil;
    }
}

- (void)showPlaceholderWithMessage:(NSString *)message
{
    [self removePanelContent];

    self.descriptor = nil;
    self.settings = @{};
    self.scrollView.hidden = YES;
    self.placeholderLabel.stringValue = message;
    self.placeholderLabel.hidden = NO;
}

// ---------------------------------------------------------------------------
// MARK: - Dark mode support
// ---------------------------------------------------------------------------

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];

    // Controls use semantic colors so they adapt automatically.
    // Force a layout pass to ensure any custom drawing updates.
    [self setNeedsLayout:YES];
}

// ---------------------------------------------------------------------------
// MARK: - Drawing
// ---------------------------------------------------------------------------

- (BOOL)isFlipped
{
    return YES;
}

@end

// ---------------------------------------------------------------------------
// MARK: - Flipped document view (content starts at top)
// ---------------------------------------------------------------------------

@implementation XLSequencerEffectPanelFlippedView

- (BOOL)isFlipped
{
    return YES;
}

@end
