/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLMainWindowController.h"
#import "XLSetupViewController.h"
#import "XLLayoutViewController.h"
#import "XLSequencerViewController.h"
#import "XLInspectorViewController.h"
#import "XLEngineBridge.h"

static const CGFloat kDefaultWindowWidth = 1600.0;
static const CGFloat kDefaultWindowHeight = 1000.0;
static const CGFloat kDefaultInspectorWidth = 300.0;
static const CGFloat kDefaultBottomPanelHeight = 250.0;
static const CGFloat kMinInspectorWidth = 220.0;
static const CGFloat kMinBottomPanelHeight = 150.0;

static NSString * const kXLWindowFrameKey = @"XLMainWindowFrame";
static NSString * const kXLInspectorVisibleKey = @"XLInspectorVisible";
static NSString * const kXLBottomPanelVisibleKey = @"XLBottomPanelVisible";
static NSString * const kXLInspectorWidthKey = @"XLInspectorWidth";
static NSString * const kXLBottomPanelHeightKey = @"XLBottomPanelHeight";
static NSString * const kXLCurrentTabKey = @"XLCurrentTab";

@interface XLMainWindowController () <NSWindowDelegate>

@property (nonatomic, strong) NSSplitViewController *mainSplitController;
@property (nonatomic, strong) NSSplitViewController *verticalSplitController;
@property (nonatomic, strong) NSViewController *contentWrapperController;
@property (nonatomic, strong) NSSegmentedControl *tabSelector;
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) NSView *bottomPanelContainer;

@property (nonatomic, assign) BOOL inspectorVisible;
@property (nonatomic, assign) BOOL bottomPanelVisible;
@property (nonatomic, assign) CGFloat inspectorWidth;
@property (nonatomic, assign) CGFloat bottomPanelHeight;

@end

@implementation XLMainWindowController

#pragma mark - Initialization

- (instancetype)init {
    NSRect frame = NSMakeRect(100, 100, kDefaultWindowWidth, kDefaultWindowHeight);
    NSWindowStyleMask style = NSWindowStyleMaskTitled
        | NSWindowStyleMaskClosable
        | NSWindowStyleMaskMiniaturizable
        | NSWindowStyleMaskResizable;

    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];

    self = [super initWithWindow:window];
    if (self) {
        window.minSize = NSMakeSize(1024, 600);
        window.delegate = self;

        // Dark appearance by default
        if (@available(macOS 10.14, *)) {
            window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        }

        _inspectorVisible = YES;
        _bottomPanelVisible = YES;
        _inspectorWidth = kDefaultInspectorWidth;
        _bottomPanelHeight = kDefaultBottomPanelHeight;
        _currentTab = 2; // Default to Sequencer tab

        // Register for resize notifications to trace what's changing the frame
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(debugWindowDidResize:)
                                                     name:NSWindowDidResizeNotification
                                                   object:window];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(debugWindowWillClose:)
                                                     name:NSWindowWillCloseNotification
                                                   object:window];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(debugWindowDidMiniaturize:)
                                                     name:NSWindowDidMiniaturizeNotification
                                                   object:window];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(debugWindowOcclusionChanged:)
                                                     name:NSWindowDidChangeOcclusionStateNotification
                                                   object:window];

        NSLog(@"NativeUI [init]: frame after window create: %@", NSStringFromRect(window.frame));

        [self setupEngine];
        NSLog(@"NativeUI [init]: frame after setupEngine: %@", NSStringFromRect(window.frame));

        [self setupViewControllers];
        NSLog(@"NativeUI [init]: frame after setupViewControllers: %@", NSStringFromRect(window.frame));

        [self setupSplitView];
        NSLog(@"NativeUI [init]: frame after setupSplitView: %@", NSStringFromRect(window.frame));

        [self setupToolbar];
        NSLog(@"NativeUI [init]: frame after setupToolbar: %@", NSStringFromRect(window.frame));

        [self restoreWindowState];
        NSLog(@"NativeUI [init]: frame after restoreWindowState: %@", NSStringFromRect(window.frame));

        // Diagnostic: check resize capability
        NSLog(@"NativeUI [init]: styleMask=%lu hasResizable=%d",
              (unsigned long)window.styleMask,
              (window.styleMask & NSWindowStyleMaskResizable) != 0);
        NSLog(@"NativeUI [init]: minSize=%@ maxSize=%@",
              NSStringFromSize(window.minSize), NSStringFromSize(window.maxSize));
        NSLog(@"NativeUI [init]: contentMinSize=%@ contentMaxSize=%@",
              NSStringFromSize(window.contentMinSize), NSStringFromSize(window.contentMaxSize));
    }
    return self;
}

- (void)debugWindowDidResize:(NSNotification *)note {
    NSWindow *win = note.object;
    // Get a backtrace to see WHO is resizing
    NSArray *symbols = [NSThread callStackSymbols];
    NSMutableString *trace = [NSMutableString string];
    // Print first 10 frames (skip 0=this method, 1=notification center)
    for (NSUInteger i = 2; i < MIN(symbols.count, 12); i++) {
        [trace appendFormat:@"\n    %@", symbols[i]];
    }
    NSLog(@"NativeUI [RESIZE]: new frame=%@  stack:%@", NSStringFromRect(win.frame), trace);
}

- (void)debugWindowWillClose:(NSNotification *)note {
    NSLog(@"NativeUI [CLOSE]: window is closing!");
    NSArray *symbols = [NSThread callStackSymbols];
    for (NSUInteger i = 2; i < MIN(symbols.count, 10); i++) {
        NSLog(@"NativeUI [CLOSE]:   %@", symbols[i]);
    }
}

- (void)debugWindowDidMiniaturize:(NSNotification *)note {
    NSLog(@"NativeUI [MINIATURIZE]: window miniaturized");
}

- (void)debugWindowOcclusionChanged:(NSNotification *)note {
    NSWindow *win = note.object;
    BOOL visible = (win.occlusionState & NSWindowOcclusionStateVisible) != 0;
    NSLog(@"NativeUI [OCCLUSION]: visible=%d  frame=%@", visible, NSStringFromRect(win.frame));
    if (!visible) {
        NSArray *symbols = [NSThread callStackSymbols];
        for (NSUInteger i = 2; i < MIN(symbols.count, 10); i++) {
            NSLog(@"NativeUI [OCCLUSION]:   %@", symbols[i]);
        }
    }
}

- (void)setupEngine {
    _engineBridge = [[XLEngineBridge alloc] init];
}

- (void)setupViewControllers {
    _setupViewController = [[XLSetupViewController alloc] init];
    _setupViewController.engineBridge = _engineBridge;

    _layoutViewController = [[XLLayoutViewController alloc] init];
    _layoutViewController.engineBridge = _engineBridge;

    _sequencerViewController = [[XLSequencerViewController alloc] init];
    _sequencerViewController.engineBridge = _engineBridge;

    _inspectorViewController = [[XLInspectorViewController alloc] init];
    _inspectorViewController.engineBridge = _engineBridge;
}

- (void)setupSplitView {
    // Main vertical split: content (with bottom panel) | inspector
    _mainSplitController = [[NSSplitViewController alloc] init];
    _mainSplitController.splitView.vertical = YES;
    _mainSplitController.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    // NOTE: Do NOT set preferredContentSize on split view controllers - it causes
    // Auto Layout to fight window resizing by snapping back to the preferred size.

    // Left side: vertical split for main content + bottom panel
    _verticalSplitController = [[NSSplitViewController alloc] init];
    _verticalSplitController.splitView.vertical = NO;
    _verticalSplitController.splitView.dividerStyle = NSSplitViewDividerStyleThin;

    // Content container (holds tab views)
    _contentContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _contentWrapperController = [self wrapViewInController:_contentContainer];
    NSSplitViewItem *contentItem = [NSSplitViewItem splitViewItemWithViewController:_contentWrapperController];
    contentItem.canCollapse = NO;
    contentItem.minimumThickness = 400.0;
    contentItem.holdingPriority = NSLayoutPriorityDefaultHigh;
    [_verticalSplitController addSplitViewItem:contentItem];

    // Bottom panel container
    _bottomPanelContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _bottomPanelContainer.wantsLayer = YES;
    _bottomPanelContainer.layer.backgroundColor = [[NSColor colorWithWhite:0.15 alpha:1.0] CGColor];
    NSViewController *bottomVC = [self wrapViewInController:_bottomPanelContainer];
    NSSplitViewItem *bottomItem = [NSSplitViewItem splitViewItemWithViewController:bottomVC];
    bottomItem.canCollapse = YES;
    bottomItem.minimumThickness = kMinBottomPanelHeight;
    bottomItem.maximumThickness = 500.0;
    [_verticalSplitController addSplitViewItem:bottomItem];

    // Add vertical split to main split
    NSSplitViewItem *leftItem = [NSSplitViewItem splitViewItemWithViewController:_verticalSplitController];
    leftItem.canCollapse = NO;
    leftItem.minimumThickness = 400.0;
    leftItem.holdingPriority = NSLayoutPriorityDefaultHigh;
    [_mainSplitController addSplitViewItem:leftItem];

    // Inspector (right side)
    NSSplitViewItem *inspectorItem = [NSSplitViewItem splitViewItemWithViewController:_inspectorViewController];
    inspectorItem.canCollapse = YES;
    inspectorItem.minimumThickness = kMinInspectorWidth;
    inspectorItem.maximumThickness = 500.0;
    [_mainSplitController addSplitViewItem:inspectorItem];

    // Use contentViewController but disable automatic window sizing from content.
    // This lets NSSplitViewController manage the view hierarchy properly while
    // preventing Auto Layout from fighting window resizing.
    NSLog(@"NativeUI [setupSplitView]: setting contentViewController");
    self.window.contentViewController = _mainSplitController;

    // Disable automatic content size updates - this is the key to preventing
    // Auto Layout from snapping the window back to content-derived sizes.
    if (@available(macOS 10.10, *)) {
        // The split view should not drive window size
        _mainSplitController.splitView.translatesAutoresizingMaskIntoConstraints = YES;
    }
    NSLog(@"NativeUI [setupSplitView]: after contentViewController, frame=%@", NSStringFromRect(self.window.frame));

    // Add tab views to content container
    [self setupTabViews];
}

- (void)setupTabViews {
    // Add tab VCs as children of the content VC so they stay in the
    // view controller containment chain (prevents zombie crashes during
    // fullscreen transitions and appearance changes).
    [_contentWrapperController addChildViewController:_setupViewController];
    [_contentWrapperController addChildViewController:_layoutViewController];
    [_contentWrapperController addChildViewController:_sequencerViewController];

    [self addViewToContainer:_setupViewController.view];
    [self addViewToContainer:_layoutViewController.view];
    [self addViewToContainer:_sequencerViewController.view];

    [self switchToTab:_currentTab];
}

- (void)addViewToContainer:(NSView *)view {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.hidden = YES;
    [_contentContainer addSubview:view];

    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:_contentContainer.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:_contentContainer.bottomAnchor],
        [view.leadingAnchor constraintEqualToAnchor:_contentContainer.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:_contentContainer.trailingAnchor],
    ]];
}

- (NSViewController *)wrapViewInController:(NSView *)view {
    NSViewController *controller = [[NSViewController alloc] init];
    controller.view = view;
    return controller;
}

#pragma mark - Toolbar

- (void)setupToolbar {
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"XLMainToolbar"];
    toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    toolbar.allowsUserCustomization = NO;
    toolbar.autosavesConfiguration = NO;
    toolbar.delegate = self;
    self.window.toolbar = toolbar;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[
        @"TabSelector",
        NSToolbarSpaceItemIdentifier,
        NSToolbarFlexibleSpaceItemIdentifier,
        @"Play",
        @"Pause",
        @"Stop",
        @"Render",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"ToggleInspector",
        @"ToggleBottomPanel"
    ];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[
        @"TabSelector",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"Play",
        @"Pause",
        @"Stop",
        @"Render",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"ToggleInspector",
        @"ToggleBottomPanel"
    ];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];

    if ([itemIdentifier isEqualToString:@"TabSelector"]) {
        item.label = @"Tab";

        _tabSelector = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, 0, 250, 28)];
        _tabSelector.segmentCount = 3;
        [_tabSelector setLabel:@"Setup" forSegment:0];
        [_tabSelector setLabel:@"Layout" forSegment:1];
        [_tabSelector setLabel:@"Sequencer" forSegment:2];
        _tabSelector.selectedSegment = _currentTab;
        _tabSelector.segmentStyle = NSSegmentStyleTexturedRounded;
        _tabSelector.target = self;
        _tabSelector.action = @selector(tabSelectorChanged:);

        item.view = _tabSelector;

        // Use constraints instead of deprecated minSize/maxSize
        _tabSelector.translatesAutoresizingMaskIntoConstraints = NO;
        [_tabSelector.widthAnchor constraintEqualToConstant:250].active = YES;
        [_tabSelector.heightAnchor constraintEqualToConstant:28].active = YES;
    }
    else if ([itemIdentifier isEqualToString:@"Play"]) {
        item.label = @"Play";
        item.image = [NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:@"Play"];
        item.target = self;
        item.action = @selector(playSequence:);
    }
    else if ([itemIdentifier isEqualToString:@"Pause"]) {
        item.label = @"Pause";
        item.image = [NSImage imageWithSystemSymbolName:@"pause.fill" accessibilityDescription:@"Pause"];
        item.target = self;
        item.action = @selector(pauseSequence:);
    }
    else if ([itemIdentifier isEqualToString:@"Stop"]) {
        item.label = @"Stop";
        item.image = [NSImage imageWithSystemSymbolName:@"stop.fill" accessibilityDescription:@"Stop"];
        item.target = self;
        item.action = @selector(stopSequence:);
    }
    else if ([itemIdentifier isEqualToString:@"Render"]) {
        item.label = @"Render";
        item.image = [NSImage imageWithSystemSymbolName:@"gearshape.fill" accessibilityDescription:@"Render"];
        item.target = self;
        item.action = @selector(renderAll:);
    }
    else if ([itemIdentifier isEqualToString:@"ToggleInspector"]) {
        item.label = @"Inspector";
        item.image = [NSImage imageWithSystemSymbolName:@"sidebar.right" accessibilityDescription:@"Inspector"];
        item.target = self;
        item.action = @selector(toggleInspector:);
    }
    else if ([itemIdentifier isEqualToString:@"ToggleBottomPanel"]) {
        item.label = @"Properties";
        item.image = [NSImage imageWithSystemSymbolName:@"rectangle.split.1x2" accessibilityDescription:@"Properties"];
        item.target = self;
        item.action = @selector(toggleBottomPanel:);
    }

    return item;
}

#pragma mark - Tab Switching

- (void)tabSelectorChanged:(NSSegmentedControl *)sender {
    [self switchToTab:sender.selectedSegment];
}

- (void)switchToTab:(NSInteger)tabIndex {
    if (tabIndex < 0 || tabIndex > 2) return;

    _currentTab = tabIndex;
    _tabSelector.selectedSegment = tabIndex;

    _setupViewController.view.hidden = (tabIndex != 0);
    _layoutViewController.view.hidden = (tabIndex != 1);
    _sequencerViewController.view.hidden = (tabIndex != 2);

    [[NSUserDefaults standardUserDefaults] setInteger:tabIndex forKey:kXLCurrentTabKey];
}

#pragma mark - Panel Visibility

- (void)toggleInspector:(id)sender {
    _inspectorVisible = !_inspectorVisible;

    NSSplitViewItem *inspectorItem = _mainSplitController.splitViewItems.lastObject;
    inspectorItem.collapsed = !_inspectorVisible;

    [[NSUserDefaults standardUserDefaults] setBool:_inspectorVisible forKey:kXLInspectorVisibleKey];
}

- (void)toggleBottomPanel:(id)sender {
    _bottomPanelVisible = !_bottomPanelVisible;

    NSSplitViewItem *bottomItem = _verticalSplitController.splitViewItems.lastObject;
    bottomItem.collapsed = !_bottomPanelVisible;

    [[NSUserDefaults standardUserDefaults] setBool:_bottomPanelVisible forKey:kXLBottomPanelVisibleKey];
}

#pragma mark - Playback Actions

- (void)playSequence:(id)sender {
    [_engineBridge play];
}

- (void)pauseSequence:(id)sender {
    [_engineBridge pause];
}

- (void)stopSequence:(id)sender {
    [_engineBridge stop];
}

- (void)renderAll:(id)sender {
    [_engineBridge renderAll];
}

#pragma mark - Window State Persistence

- (void)saveWindowState {
    NSString *frameString = NSStringFromRect(self.window.frame);
    [[NSUserDefaults standardUserDefaults] setObject:frameString forKey:kXLWindowFrameKey];
    [[NSUserDefaults standardUserDefaults] setBool:_inspectorVisible forKey:kXLInspectorVisibleKey];
    [[NSUserDefaults standardUserDefaults] setBool:_bottomPanelVisible forKey:kXLBottomPanelVisibleKey];
    [[NSUserDefaults standardUserDefaults] setInteger:_currentTab forKey:kXLCurrentTabKey];

    // Save split positions
    if (_mainSplitController.splitViewItems.count >= 2) {
        NSSplitViewItem *inspectorItem = _mainSplitController.splitViewItems.lastObject;
        if (!inspectorItem.collapsed) {
            _inspectorWidth = inspectorItem.viewController.view.frame.size.width;
            [[NSUserDefaults standardUserDefaults] setDouble:_inspectorWidth forKey:kXLInspectorWidthKey];
        }
    }

    if (_verticalSplitController.splitViewItems.count >= 2) {
        NSSplitViewItem *bottomItem = _verticalSplitController.splitViewItems.lastObject;
        if (!bottomItem.collapsed) {
            _bottomPanelHeight = bottomItem.viewController.view.frame.size.height;
            [[NSUserDefaults standardUserDefaults] setDouble:_bottomPanelHeight forKey:kXLBottomPanelHeightKey];
        }
    }
}

- (void)restoreWindowState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSLog(@"NativeUI [restore]: saved frame key = '%@'", [defaults stringForKey:kXLWindowFrameKey]);

    // Restore panel visibility
    if ([defaults objectForKey:kXLInspectorVisibleKey]) {
        _inspectorVisible = [defaults boolForKey:kXLInspectorVisibleKey];
    }
    if ([defaults objectForKey:kXLBottomPanelVisibleKey]) {
        _bottomPanelVisible = [defaults boolForKey:kXLBottomPanelVisibleKey];
    }

    // Restore current tab
    if ([defaults objectForKey:kXLCurrentTabKey]) {
        _currentTab = [defaults integerForKey:kXLCurrentTabKey];
    }

    // Restore split widths
    if ([defaults objectForKey:kXLInspectorWidthKey]) {
        _inspectorWidth = [defaults doubleForKey:kXLInspectorWidthKey];
    }
    if ([defaults objectForKey:kXLBottomPanelHeightKey]) {
        _bottomPanelHeight = [defaults doubleForKey:kXLBottomPanelHeightKey];
    }

    // Apply panel states after layout
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.mainSplitController.splitViewItems.count >= 2) {
            NSSplitViewItem *inspectorItem = self.mainSplitController.splitViewItems.lastObject;
            inspectorItem.collapsed = !self->_inspectorVisible;
        }

        if (self.verticalSplitController.splitViewItems.count >= 2) {
            NSSplitViewItem *bottomItem = self.verticalSplitController.splitViewItems.lastObject;
            bottomItem.collapsed = !self->_bottomPanelVisible;
        }
    });
}

#pragma mark - Window Delegate

- (void)windowDidBecomeKey:(NSNotification *)notification {
    NSWindow *win = self.window;
    NSLog(@"NativeUI [windowDidBecomeKey]: styleMask=%lu hasResizable=%d",
          (unsigned long)win.styleMask,
          (win.styleMask & NSWindowStyleMaskResizable) != 0);
    NSLog(@"NativeUI [windowDidBecomeKey]: minSize=%@ maxSize=%@",
          NSStringFromSize(win.minSize), NSStringFromSize(win.maxSize));
    NSLog(@"NativeUI [windowDidBecomeKey]: frame=%@", NSStringFromRect(win.frame));
}

- (void)windowWillClose:(NSNotification *)notification {
    [self saveWindowState];
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize {
    NSLog(@"NativeUI [windowWillResize]: from %@ to %@",
          NSStringFromSize(sender.frame.size), NSStringFromSize(frameSize));
    if (frameSize.width < sender.minSize.width || frameSize.height < sender.minSize.height) {
        NSArray *symbols = [NSThread callStackSymbols];
        for (NSUInteger i = 2; i < MIN(symbols.count, 12); i++) {
            NSLog(@"NativeUI [windowWillResize]:   %@", symbols[i]);
        }
    }
    return frameSize;
}

@end
