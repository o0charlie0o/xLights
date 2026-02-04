/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLColorPaletteViewController.h"
#import "XLEngineBridge.h"
#import <SwiftUI/SwiftUI.h>

// Import Swift-generated header for SwiftUI views
#if __has_include("xLights-Swift.h")
#import "xLights-Swift.h"
#elif __has_include("xLights_macOSLib-Swift.h")
#import "xLights_macOSLib-Swift.h"
#endif

@interface XLColorPaletteViewController ()

@property (nonatomic, strong) NSView *hostingView;

@end

@implementation XLColorPaletteViewController

- (void)loadView {
    NSView *containerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 500)];
    containerView.wantsLayer = YES;
    containerView.layer.backgroundColor = [[NSColor colorWithWhite:0.15 alpha:1.0] CGColor];

    self.view = containerView;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupSwiftUIHosting];
}

- (void)setupSwiftUIHosting {
    // Create the SwiftUI hosting view
    // Note: The ColorPaletteHostingView is defined in ColorPaletteView.swift
    ColorPaletteHostingView *hostingView = [[ColorPaletteHostingView alloc] initWithFrame:self.view.bounds];
    hostingView.translatesAutoresizingMaskIntoConstraints = NO;
    hostingView.engineBridge = _engineBridge;

    [self.view addSubview:hostingView];

    [NSLayoutConstraint activateConstraints:@[
        [hostingView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [hostingView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [hostingView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [hostingView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    self.hostingView = hostingView;
}

- (void)setEngineBridge:(XLEngineBridge *)engineBridge {
    _engineBridge = engineBridge;

    if ([self.hostingView isKindOfClass:[ColorPaletteHostingView class]]) {
        ((ColorPaletteHostingView *)self.hostingView).engineBridge = engineBridge;
    }
}

- (void)reloadColors {
    if ([self.hostingView isKindOfClass:[ColorPaletteHostingView class]]) {
        [((ColorPaletteHostingView *)self.hostingView) reloadColors];
    }
}

@end
