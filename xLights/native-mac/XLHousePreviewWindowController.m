/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLHousePreviewWindowController.h"
#import "layout/XLMetalPreviewView.h"
#import "layout/XLCameraController.h"
#import "XLPlaybackController.h"
#import "XLEngineBridge.h"

static NSString * const kWindowFrameKey = @"XLHousePreviewWindowFrame";

// Toolbar item identifiers
static NSToolbarIdentifier const kToolbarIdentifier = @"XLHousePreviewToolbar";
static NSToolbarItemIdentifier const kToolbarTransportItem = @"XLHousePreviewTransport";
static NSToolbarItemIdentifier const kToolbarViewpointItem = @"XLHousePreviewViewpoint";

@implementation XLHousePreviewWindowController {
    NSPopUpButton *_viewpointPopup;
}

- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge {
    // Create a floating panel — no UtilityWindow style so we get a full-height title bar
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(100, 100, 640, 480)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable |
                             NSWindowStyleMaskNonactivatingPanel)
                    backing:NSBackingStoreBuffered
                      defer:NO];

    panel.title = @"House Preview";
    panel.minSize = NSMakeSize(320, 240);
    panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    panel.floatingPanel = YES;
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.hidesOnDeactivate = NO;

    // Float above xLights windows, but drop to normal level when another app is active.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive:)
                                                 name:NSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidResignActive:)
                                                 name:NSApplicationDidResignActiveNotification
                                               object:nil];

    self = [super initWithWindow:panel];
    if (self) {
        _engineBridge = engineBridge;
        panel.delegate = self;

        // Set up toolbar
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:kToolbarIdentifier];
        toolbar.delegate = self;
        toolbar.displayMode = NSToolbarDisplayModeIconOnly;
        toolbar.allowsUserCustomization = NO;
        if (@available(macOS 11.0, *)) {
            panel.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;
        }
        panel.toolbar = toolbar;

        // Create the Metal preview view
        NSRect contentRect = [panel contentRectForFrameRect:panel.frame];
        _previewView = [[XLMetalPreviewView alloc] initWithFrame:contentRect];
        _previewView.show3D = YES;
        _previewView.showGrid = YES;
        _previewView.engineBridge = engineBridge;
        _previewView.delegate = self;

        panel.contentView = _previewView;

        // Restore saved window frame
        NSString *frameString = [[NSUserDefaults standardUserDefaults] stringForKey:kWindowFrameKey];
        NSLog(@"[PERSIST] HousePreview init: saved frame string=%@", frameString ?: @"(none)");
        if (frameString) {
            NSRect frame = NSRectFromString(frameString);
            if (frame.size.width > 0 && frame.size.height > 0) {
                [panel setFrame:frame display:NO];
                NSLog(@"[PERSIST] HousePreview init: restored frame=%.0fx%.0f at (%.0f,%.0f)",
                      frame.size.width, frame.size.height, frame.origin.x, frame.origin.y);
            }
        }

        // Listen for sequence data changes to reload models
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sequenceDataDidChange:)
                                                     name:@"XLSequenceDataDidChangeNotification"
                                                   object:nil];

        // Pre-load model data
        [_previewView reloadModels];

        // Restore saved camera state, or frame all models on first launch
        if (![_previewView.cameraController restoreCameraState]) {
            [_previewView frameAllModels];
        }
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_previewView stopRenderLoop];
}

- (void)reloadModels {
    [_previewView reloadModels];
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[kToolbarTransportItem, NSToolbarFlexibleSpaceItemIdentifier, kToolbarViewpointItem];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[kToolbarTransportItem, NSToolbarFlexibleSpaceItemIdentifier, kToolbarViewpointItem];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {

    if ([itemIdentifier isEqualToString:kToolbarTransportItem]) {
        return [self makeTransportToolbarItem];
    }
    if ([itemIdentifier isEqualToString:kToolbarViewpointItem]) {
        return [self makeViewpointToolbarItem];
    }
    return nil;
}

- (NSToolbarItem *)makeTransportToolbarItem {
    if (@available(macOS 10.15, *)) {
        NSToolbarItemGroup *group = [[NSToolbarItemGroup alloc] initWithItemIdentifier:kToolbarTransportItem];

        // Play button
        NSButton *playBtn = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"play.fill"
                                                                accessibilityDescription:@"Play"]
                                               target:self
                                               action:@selector(toolbarPlay:)];
        playBtn.bezelStyle = NSBezelStyleTexturedRounded;
        playBtn.bordered = NO;

        // Pause button
        NSButton *pauseBtn = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"pause.fill"
                                                                 accessibilityDescription:@"Pause"]
                                                target:self
                                                action:@selector(toolbarPause:)];
        pauseBtn.bezelStyle = NSBezelStyleTexturedRounded;
        pauseBtn.bordered = NO;

        // Stop button
        NSButton *stopBtn = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"stop.fill"
                                                                accessibilityDescription:@"Stop"]
                                               target:self
                                               action:@selector(toolbarStop:)];
        stopBtn.bezelStyle = NSBezelStyleTexturedRounded;
        stopBtn.bordered = NO;

        NSStackView *stack = [NSStackView stackViewWithViews:@[playBtn, pauseBtn, stopBtn]];
        stack.spacing = 4;

        group.view = stack;
        group.label = @"Transport";
        group.paletteLabel = @"Transport";
        return group;
    }

    // Fallback for older macOS
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:kToolbarTransportItem];
    item.label = @"Transport";
    return item;
}

- (NSToolbarItem *)makeViewpointToolbarItem {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:kToolbarViewpointItem];

    _viewpointPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 120, 24) pullsDown:NO];
    _viewpointPopup.controlSize = NSControlSizeRegular;
    [_viewpointPopup setFont:[NSFont systemFontOfSize:12]];

    [_viewpointPopup addItemWithTitle:@"Front"];
    [_viewpointPopup addItemWithTitle:@"Top"];
    [_viewpointPopup addItemWithTitle:@"Left"];
    [_viewpointPopup addItemWithTitle:@"Right"];
    [_viewpointPopup addItemWithTitle:@"Back"];
    [[_viewpointPopup menu] addItem:[NSMenuItem separatorItem]];
    [_viewpointPopup addItemWithTitle:@"Frame All"];

    _viewpointPopup.target = self;
    _viewpointPopup.action = @selector(viewpointChanged:);

    item.view = _viewpointPopup;
    item.label = @"Viewpoint";
    item.paletteLabel = @"Viewpoint";
    item.minSize = NSMakeSize(120, 24);
    item.maxSize = NSMakeSize(140, 28);

    return item;
}

#pragma mark - Toolbar Actions

- (void)toolbarPlay:(id)sender {
    [_playbackController play];
}

- (void)toolbarPause:(id)sender {
    [_playbackController pause];
}

- (void)toolbarStop:(id)sender {
    [_playbackController stop];
}

- (void)viewpointChanged:(NSPopUpButton *)sender {
    NSString *title = sender.titleOfSelectedItem;

    if ([title isEqualToString:@"Front"]) {
        _previewView.cameraController.azimuth = 0.0f;
        _previewView.cameraController.elevation = 0.0f;
        [_previewView frameAllModels];
    } else if ([title isEqualToString:@"Top"]) {
        _previewView.cameraController.azimuth = 0.0f;
        _previewView.cameraController.elevation = M_PI_2 - 0.01f;
        [_previewView frameAllModels];
    } else if ([title isEqualToString:@"Left"]) {
        _previewView.cameraController.azimuth = M_PI_2;
        _previewView.cameraController.elevation = 0.0f;
        [_previewView frameAllModels];
    } else if ([title isEqualToString:@"Right"]) {
        _previewView.cameraController.azimuth = -M_PI_2;
        _previewView.cameraController.elevation = 0.0f;
        [_previewView frameAllModels];
    } else if ([title isEqualToString:@"Back"]) {
        _previewView.cameraController.azimuth = M_PI;
        _previewView.cameraController.elevation = 0.0f;
        [_previewView frameAllModels];
    } else if ([title isEqualToString:@"Frame All"]) {
        [_previewView frameAllModels];
    }

    [_previewView setNeedsRender];
}

#pragma mark - App Activation

- (void)appDidBecomeActive:(NSNotification *)notification {
    [self.window setLevel:NSFloatingWindowLevel];
}

- (void)appDidResignActive:(NSNotification *)notification {
    [self.window setLevel:NSNormalWindowLevel];
}

#pragma mark - Notifications

- (void)sequenceDataDidChange:(NSNotification *)notification {
    [self reloadModels];
}

#pragma mark - NSWindowDelegate

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [_previewView setNeedsRender];
}

- (void)windowWillClose:(NSNotification *)notification {
    NSString *frameString = NSStringFromRect(self.window.frame);
    [[NSUserDefaults standardUserDefaults] setObject:frameString forKey:kWindowFrameKey];
    [_previewView.cameraController saveCameraState];
}

- (void)windowDidResize:(NSNotification *)notification {
    NSString *frameString = NSStringFromRect(self.window.frame);
    [[NSUserDefaults standardUserDefaults] setObject:frameString forKey:kWindowFrameKey];
    NSLog(@"[PERSIST] windowDidResize: saved frame=%@", frameString);
    [_previewView setNeedsRender];
}

- (void)windowDidMove:(NSNotification *)notification {
    NSString *frameString = NSStringFromRect(self.window.frame);
    [[NSUserDefaults standardUserDefaults] setObject:frameString forKey:kWindowFrameKey];
    NSLog(@"[PERSIST] windowDidMove: saved frame=%@", frameString);
}

#pragma mark - XLMetalPreviewDelegate

- (void)previewView:(XLMetalPreviewView *)view didChangeCamera:(XLCameraController *)camera {
    [camera saveCameraState];
}

- (void)previewView:(XLMetalPreviewView *)view didReceiveKeyEvent:(NSEvent *)event {
    if (event.keyCode == 0x31) { // spacebar
        [_playbackController togglePlayPause];
    }
}

@end
