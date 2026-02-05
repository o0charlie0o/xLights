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
#import "XLEngineBridge.h"

static NSString * const kWindowFrameKey = @"XLHousePreviewWindowFrame";

@implementation XLHousePreviewWindowController

- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge {
    // Create a floating utility panel
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(100, 100, 640, 480)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable |
                             NSWindowStyleMaskUtilityWindow |
                             NSWindowStyleMaskNonactivatingPanel)
                    backing:NSBackingStoreBuffered
                      defer:NO];

    panel.title = @"House Preview";
    panel.minSize = NSMakeSize(320, 240);
    panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    panel.floatingPanel = YES;
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.hidesOnDeactivate = NO;

    self = [super initWithWindow:panel];
    if (self) {
        _engineBridge = engineBridge;
        panel.delegate = self;

        NSLog(@"[HousePreview] init: engineBridge=%@ (class=%@)", engineBridge, [engineBridge class]);

        // Create the Metal preview view — use the panel's content rect so it has a real size.
        NSRect contentRect = [panel contentRectForFrameRect:panel.frame];
        NSLog(@"[HousePreview] init: creating preview view with frame=%@", NSStringFromRect(contentRect));

        _previewView = [[XLMetalPreviewView alloc] initWithFrame:contentRect];
        _previewView.show3D = YES;
        _previewView.showGrid = YES;
        _previewView.engineBridge = engineBridge;

        panel.contentView = _previewView;

        NSLog(@"[HousePreview] init: contentView set, previewView=%p frame=%@ bounds=%@",
              _previewView, NSStringFromRect(_previewView.frame), NSStringFromRect(_previewView.bounds));

        // Restore saved window frame
        NSString *frameString = [[NSUserDefaults standardUserDefaults] stringForKey:kWindowFrameKey];
        if (frameString) {
            NSRect frame = NSRectFromString(frameString);
            if (frame.size.width > 0 && frame.size.height > 0) {
                [panel setFrame:frame display:NO];
            }
        }

        // Listen for sequence data changes to reload models
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sequenceDataDidChange:)
                                                     name:@"XLSequenceDataDidChangeNotification"
                                                   object:nil];

        // Pre-load model data. Render loop is started by viewDidMoveToWindow
        // when the window becomes visible.
        NSLog(@"[HousePreview] init: calling reloadModels (previewView=%p)...", _previewView);
        [_previewView reloadModels];
        [_previewView frameAllModels];
        NSLog(@"[HousePreview] init: complete");
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_previewView stopRenderLoop];
}

- (void)reloadModels {
    NSLog(@"[HousePreview] reloadModels called (previewView=%p)", _previewView);
    [_previewView reloadModels];
    [_previewView frameAllModels];
}

#pragma mark - Notifications

- (void)sequenceDataDidChange:(NSNotification *)notification {
    [self reloadModels];
}

#pragma mark - NSWindowDelegate

- (void)windowDidBecomeKey:(NSNotification *)notification {
    NSLog(@"[HousePreview] windowDidBecomeKey — triggering render");
    [_previewView setNeedsRender];
}

- (void)windowWillClose:(NSNotification *)notification {
    NSString *frameString = NSStringFromRect(self.window.frame);
    [[NSUserDefaults standardUserDefaults] setObject:frameString forKey:kWindowFrameKey];
}

- (void)windowDidResize:(NSNotification *)notification {
    [_previewView setNeedsRender];
}

@end
