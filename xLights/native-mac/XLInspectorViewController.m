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
#import "XLEngineBridge.h"
#import "layout/XLModelPropertiesView.h"

@interface XLInspectorViewController () <XLModelPropertiesDelegate>

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSStackView *stackView;
@property (nonatomic, strong) XLModelPropertiesView *modelPropertiesView;

@end

@implementation XLInspectorViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 600)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = CGColorCreateGenericGray(0.12, 1.0);

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

#pragma mark - Model Properties View (lazy)

- (XLModelPropertiesView *)ensureModelPropertiesView {
    if (!_modelPropertiesView) {
        _modelPropertiesView = [[XLModelPropertiesView alloc] initWithFrame:NSZeroRect];
        _modelPropertiesView.delegate = self;
        _modelPropertiesView.engineBridge = _engineBridge;
    }
    return _modelPropertiesView;
}

#pragma mark - Clear Stack

- (void)clearStackView {
    for (NSView *subview in [_stackView.arrangedSubviews copy]) {
        [_stackView removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }
}

#pragma mark - Inspect Methods

- (void)inspectObject:(id)object {
    if ([object isKindOfClass:[NSString class]]) {
        [self inspectModel:(NSString *)object];
        return;
    }

    if ([object isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)object;
        if (arr.count > 0 && [arr.firstObject isKindOfClass:[NSString class]]) {
            [self inspectModels:arr];
            return;
        }
    }

    [self clearStackView];
}

- (void)inspectModel:(NSString *)modelName {
    if (!modelName) {
        [self clearInspector];
        return;
    }

    NSDictionary *info = [_engineBridge getModelInfo:modelName];
    if (!info) {
        [self clearInspector];
        return;
    }

    [self clearStackView];

    XLModelPropertiesView *propsView = [self ensureModelPropertiesView];
    propsView.engineBridge = _engineBridge;
    [propsView showPropertiesForModel:modelName info:info];

    [_stackView addArrangedSubview:propsView];
    [NSLayoutConstraint activateConstraints:@[
        [propsView.leadingAnchor constraintEqualToAnchor:_stackView.leadingAnchor],
        [propsView.trailingAnchor constraintEqualToAnchor:_stackView.trailingAnchor],
    ]];
}

- (void)inspectModels:(NSArray<NSString *> *)modelNames {
    if (!modelNames || modelNames.count == 0) {
        [self clearInspector];
        return;
    }

    if (modelNames.count == 1) {
        [self inspectModel:modelNames.firstObject];
        return;
    }

    NSMutableArray<NSDictionary *> *infos = [[NSMutableArray alloc] initWithCapacity:modelNames.count];
    for (NSString *name in modelNames) {
        NSDictionary *info = [_engineBridge getModelInfo:name];
        if (info) {
            [infos addObject:info];
        }
    }

    if (infos.count == 0) {
        [self clearInspector];
        return;
    }

    [self clearStackView];

    XLModelPropertiesView *propsView = [self ensureModelPropertiesView];
    propsView.engineBridge = _engineBridge;
    [propsView showPropertiesForModels:modelNames infos:infos];

    [_stackView addArrangedSubview:propsView];
    [NSLayoutConstraint activateConstraints:@[
        [propsView.leadingAnchor constraintEqualToAnchor:_stackView.leadingAnchor],
        [propsView.trailingAnchor constraintEqualToAnchor:_stackView.trailingAnchor],
    ]];
}

- (void)clearInspector {
    [self clearStackView];
    [_modelPropertiesView clearProperties];
    [self addPlaceholderContent];
}

#pragma mark - XLModelPropertiesDelegate

- (void)modelProperties:(XLModelPropertiesView *)view
       didChangeProperty:(NSString *)key
                   value:(id)value
                forModel:(NSString *)modelName {
    [_engineBridge updateModelProperty:modelName key:key value:value];
}

@end
