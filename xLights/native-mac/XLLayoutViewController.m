/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLLayoutViewController.h"

@implementation XLLayoutViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor colorWithWhite:0.16 alpha:1.0] CGColor];

    // Placeholder label
    NSTextField *label = [NSTextField labelWithString:@"Layout/Preview Tab"];
    label.font = [NSFont systemFontOfSize:24 weight:NSFontWeightLight];
    label.textColor = [NSColor secondaryLabelColor];
    label.alignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:label];

    NSTextField *sublabel = [NSTextField labelWithString:@"Metal 3D preview will go here"];
    sublabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    sublabel.textColor = [NSColor tertiaryLabelColor];
    sublabel.alignment = NSTextAlignmentCenter;
    sublabel.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:sublabel];

    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:view.centerYAnchor constant:-20],
        [sublabel.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [sublabel.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:8],
    ]];

    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

@end
