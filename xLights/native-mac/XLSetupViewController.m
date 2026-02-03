/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLSetupViewController.h"

@implementation XLSetupViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor colorWithWhite:0.18 alpha:1.0] CGColor];

    // Placeholder label
    NSTextField *label = [NSTextField labelWithString:@"Setup Tab"];
    label.font = [NSFont systemFontOfSize:24 weight:NSFontWeightLight];
    label.textColor = [NSColor secondaryLabelColor];
    label.alignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
    ]];

    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

@end
