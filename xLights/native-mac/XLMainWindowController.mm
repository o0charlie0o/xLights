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

@interface XLMainWindowController ()

@property (nonatomic, strong) NSSplitViewController *mainSplitController;
@property (nonatomic, strong) NSSplitViewController *verticalSplitController;
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
        | NSWindowStyleMaskResizable
        | NSWindowStyleMaskFullSizeContentView;

    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];

    self = [super initWithWindow:window];
    if (self) {
        window.titlebarAppearsTransparent = YES;
        window.titleVisibility = NSWindowTitleHidden;
        window.minSize = NSMakeSize(1024, 600);

        // Dark appearance by default
        if (@available(macOS 10.14, *)) {
            window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        }

        _inspectorVisible = YES;
        _bottomPanelVisible = YES;
        _inspectorWidth = kDefaultInspectorWidth;
        _bottomPanelHeight = kDefaultBottomPanelHeight;
        _currentTab = 2; // Default to Sequencer tab

        [self setupEngine];
        [self setupViewControllers];
        [self setupSplitView];
        [self setupToolbar];
        [self restoreWindowState];
    }
    return self;
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
    _mainSplitController.splitView.delegate = self;

    // Left side: vertical split for main content + bottom panel
    _verticalSplitController = [[NSSplitViewController alloc] init];
    _verticalSplitController.splitView.vertical = NO;
    _verticalSplitController.splitView.dividerStyle = NSSplitViewDividerStyleThin;

    // Content container (holds tab views)
    _contentContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    NSSplitViewItem *contentItem = [NSSplitViewItem splitViewItemWithViewController:
                                    [self wrapViewInController:_contentContainer]];
    contentItem.canCollapse = NO;
    [_verticalSplitController addSplitViewItem:contentItem];

    // Bottom panel container
    _bottomPanelContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _bottomPanelContainer.wantsLayer = YES;
    _bottomPanelContainer.layer.backgroundColor = [[NSColor colorWithWhite:0.15 alpha:1.0] CGColor];
    NSSplitViewItem *bottomItem = [NSSplitViewItem splitViewItemWithViewController:
                                   [self wrapViewInController:_bottomPanelContainer]];
    bottomItem.canCollapse = YES;
    bottomItem.minimumThickness = kMinBottomPanelHeight;
    bottomItem.maximumThickness = 500.0;
    [_verticalSplitController addSplitViewItem:bottomItem];

    // Add vertical split to main split
    NSSplitViewItem *leftItem = [NSSplitViewItem splitViewItemWithViewController:_verticalSplitController];
    leftItem.canCollapse = NO;
    [_mainSplitController addSplitViewItem:leftItem];

    // Inspector (right side)
    NSSplitViewItem *inspectorItem = [NSSplitViewItem splitViewItemWithViewController:_inspectorViewController];
    inspectorItem.canCollapse = YES;
    inspectorItem.minimumThickness = kMinInspectorWidth;
    inspectorItem.maximumThickness = 500.0;
    [_mainSplitController addSplitViewItem:inspectorItem];

    // Set main split view as window's content
    self.window.contentViewController = _mainSplitController;

    // Add tab views to content container
    [self setupTabViews];
}

- (void)setupTabViews {
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
    toolbar.allowsUserCustomization = YES;
    toolbar.autosavesConfiguration = YES;
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
        item.minSize = NSMakeSize(250, 28);
        item.maxSize = NSMakeSize(250, 28);
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

    // Restore window frame
    NSString *frameString = [defaults stringForKey:kXLWindowFrameKey];
    if (frameString) {
        NSRect frame = NSRectFromString(frameString);
        [self.window setFrame:frame display:YES];
    }

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

- (void)windowWillClose:(NSNotification *)notification {
    [self saveWindowState];
}

#pragma mark - NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMinCoordinate:(CGFloat)proposedMin
         ofSubviewAt:(NSInteger)dividerIndex {
    if (splitView == _mainSplitController.splitView) {
        return proposedMin + 600; // Min width for content area
    }
    else if (splitView == _verticalSplitController.splitView) {
        return proposedMin + 300; // Min height for content area
    }
    return proposedMin;
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMaxCoordinate:(CGFloat)proposedMax
         ofSubviewAt:(NSInteger)dividerIndex {
    if (splitView == _mainSplitController.splitView) {
        return proposedMax - kMinInspectorWidth;
    }
    else if (splitView == _verticalSplitController.splitView) {
        return proposedMax - kMinBottomPanelHeight;
    }
    return proposedMax;
}

@end
