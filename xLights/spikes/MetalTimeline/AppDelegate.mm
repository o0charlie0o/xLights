#import "AppDelegate.h"
#import "MetalTimelineView.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Create window
    NSRect frame = NSMakeRect(100, 100, 1440, 900);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskResizable;
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:style
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = @"Metal Timeline Spike - Loading...";
    _window.minSize = NSMakeSize(800, 400);

    // Dark appearance
    if (@available(macOS 10.14, *)) {
        _window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    }

    // Create the Metal timeline view
    MetalTimelineView *timelineView = [[MetalTimelineView alloc] initWithFrame:_window.contentView.bounds];
    timelineView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_window.contentView addSubview:timelineView];

    // Generate test data: 100 rows x 50 effects = 5,000 effects
    [timelineView generateMockData:100 effectsPerRow:50 totalDuration:300.0];

    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:timelineView];

    // Add performance controls menu
    [self setupMenu];
}

- (void)setupMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    // App menu
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"MetalTimeline"];
    [appMenu addItemWithTitle:@"About Metal Timeline Spike"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;
    [mainMenu addItem:appMenuItem];

    // Test menu
    NSMenuItem *testMenuItem = [[NSMenuItem alloc] init];
    NSMenu *testMenu = [[NSMenu alloc] initWithTitle:@"Test"];
    [testMenu addItemWithTitle:@"100 rows x 50 effects (5,000)"
                        action:@selector(load5k:)
                 keyEquivalent:@"1"];
    [testMenu addItemWithTitle:@"200 rows x 100 effects (20,000)"
                        action:@selector(load20k:)
                 keyEquivalent:@"2"];
    [testMenu addItemWithTitle:@"500 rows x 200 effects (100,000)"
                        action:@selector(load100k:)
                 keyEquivalent:@"3"];
    [testMenu addItemWithTitle:@"10 rows x 10 effects (100)"
                        action:@selector(load100:)
                 keyEquivalent:@"4"];
    testMenuItem.submenu = testMenu;
    [mainMenu addItem:testMenuItem];

    [NSApp setMainMenu:mainMenu];
}

- (MetalTimelineView *)timelineView {
    return (MetalTimelineView *)_window.contentView.subviews.firstObject;
}

- (void)load5k:(id)sender {
    [[self timelineView] generateMockData:100 effectsPerRow:50 totalDuration:300.0];
}

- (void)load20k:(id)sender {
    [[self timelineView] generateMockData:200 effectsPerRow:100 totalDuration:600.0];
}

- (void)load100k:(id)sender {
    [[self timelineView] generateMockData:500 effectsPerRow:200 totalDuration:1200.0];
}

- (void)load100:(id)sender {
    [[self timelineView] generateMockData:10 effectsPerRow:10 totalDuration:60.0];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end
