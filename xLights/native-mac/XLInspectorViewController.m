/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLInspectorViewController.h"

@interface XLInspectorViewController ()

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSStackView *stackView;

@end

@implementation XLInspectorViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 600)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor colorWithWhite:0.12 alpha:1.0] CGColor];

    // Scroll view for inspector content
    _scrollView = [[NSScrollView alloc] initWithFrame:view.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.drawsBackground = NO;
    [view addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:view.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
    ]];

    // Stack view for disclosure groups
    _stackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    _stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stackView.alignment = NSLayoutAttributeLeading;
    _stackView.spacing = 0;
    _stackView.distribution = NSStackViewDistributionFill;

    _scrollView.documentView = _stackView;

    NSClipView *clipView = _scrollView.contentView;
    [NSLayoutConstraint activateConstraints:@[
        [_stackView.topAnchor constraintEqualToAnchor:clipView.topAnchor],
        [_stackView.leadingAnchor constraintEqualToAnchor:clipView.leadingAnchor],
        [_stackView.trailingAnchor constraintEqualToAnchor:clipView.trailingAnchor],
        [_stackView.bottomAnchor constraintEqualToAnchor:clipView.bottomAnchor],
    ]];

    [self addPlaceholderContent];

    self.view = view;
}

- (void)addPlaceholderContent {
    NSTextField *label = [NSTextField labelWithString:@"Inspector"];
    label.font = [NSFont systemFontOfSize:16 weight:NSFontWeightMedium];
    label.textColor = [NSColor secondaryLabelColor];
    label.alignment = NSTextAlignmentCenter;
    [_stackView addArrangedSubview:label];

    NSTextField *sublabel = [NSTextField labelWithString:@"Select an object to see properties"];
    sublabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    sublabel.textColor = [NSColor tertiaryLabelColor];
    sublabel.alignment = NSTextAlignmentCenter;
    [_stackView addArrangedSubview:sublabel];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:_stackView.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:_stackView.trailingAnchor constant:-20],
        [sublabel.leadingAnchor constraintEqualToAnchor:_stackView.leadingAnchor constant:20],
        [sublabel.trailingAnchor constraintEqualToAnchor:_stackView.trailingAnchor constant:-20],
    ]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)inspectObject:(id)object {
    // Clear existing content
    for (NSView *subview in _stackView.arrangedSubviews) {
        [_stackView removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }

    // Build inspector UI based on object type
    // TODO: Use InspectorView pattern from AppKitInspector spike
}

- (void)clearInspector {
    for (NSView *subview in _stackView.arrangedSubviews) {
        [_stackView removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }

    [self addPlaceholderContent];
}

@end
