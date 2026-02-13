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
#import "dialogs/XLCustomModelWindow.h"

@interface XLInspectorViewController () <XLModelPropertiesDelegate>

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSStackView *stackView;
@property (nonatomic, strong) XLModelPropertiesView *modelPropertiesView;
@property (nonatomic, strong) NSViewController *hostedContentVC;

@end

/// Last selection posted by the layout tab, so a newly created inspector can restore it.
static NSArray<NSString *> *sLastLayoutSelection = nil;

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
    _stackView.distribution = NSStackViewDistributionGravityAreas;

    _scrollView.documentView = _stackView;

    NSClipView *clipView = _scrollView.contentView;
    [NSLayoutConstraint activateConstraints:@[
        [_stackView.topAnchor constraintEqualToAnchor:clipView.topAnchor],
        [_stackView.leadingAnchor constraintEqualToAnchor:clipView.leadingAnchor],
        [_stackView.trailingAnchor constraintEqualToAnchor:clipView.trailingAnchor],
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

    // Listen for model selection changes from the layout tab
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(layoutModelSelectionDidChange:)
                                                 name:@"XLLayoutModelSelectionDidChange"
                                               object:nil];
}

- (void)viewDidAppear {
    [super viewDidAppear];

    // Restore last layout selection when the inspector is (re)created
    if (sLastLayoutSelection.count > 0) {
        if (sLastLayoutSelection.count == 1) {
            [self inspectModel:sLastLayoutSelection.firstObject];
        } else {
            [self inspectModels:sLastLayoutSelection];
        }
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
        // Might be a model group — show group info
        NSDictionary *groupInfo = [_engineBridge getModelGroup:modelName];
        if (groupInfo) {
            [self inspectGroup:modelName info:groupInfo];
        } else {
            [self clearInspector];
        }
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

- (void)inspectGroup:(NSString *)groupName info:(NSDictionary *)groupInfo {
    [self clearStackView];

    NSArray<NSString *> *members = groupInfo[@"modelNames"] ?: @[];
    NSString *bufferStyle = groupInfo[@"defaultBufferStyle"] ?: @"Default";

    // Group header
    NSTextField *header = [NSTextField labelWithString:groupName];
    header.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
    header.textColor = [NSColor labelColor];
    [_stackView addArrangedSubview:header];

    // Type label
    NSTextField *typeLabel = [NSTextField labelWithString:@"Model Group"];
    typeLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    typeLabel.textColor = [NSColor secondaryLabelColor];
    [_stackView addArrangedSubview:typeLabel];

    // Member count
    NSString *countText = [NSString stringWithFormat:@"%lu model%@",
                           (unsigned long)members.count,
                           members.count == 1 ? @"" : @"s"];
    NSTextField *countLabel = [NSTextField labelWithString:countText];
    countLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    countLabel.textColor = [NSColor secondaryLabelColor];
    [_stackView addArrangedSubview:countLabel];

    // Buffer style
    NSTextField *bufferLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Buffer Style: %@", bufferStyle]];
    bufferLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    bufferLabel.textColor = [NSColor secondaryLabelColor];
    [_stackView addArrangedSubview:bufferLabel];

    // Spacer
    NSView *spacer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 8)];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer.heightAnchor constraintEqualToConstant:8].active = YES;
    [_stackView addArrangedSubview:spacer];

    // Member list
    if (members.count > 0) {
        NSTextField *membersHeader = [NSTextField labelWithString:@"Members"];
        membersHeader.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        membersHeader.textColor = [NSColor labelColor];
        [_stackView addArrangedSubview:membersHeader];

        for (NSString *member in members) {
            NSTextField *memberLabel = [NSTextField labelWithString:
                [NSString stringWithFormat:@"  %@", member]];
            memberLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
            memberLabel.textColor = [NSColor secondaryLabelColor];
            [_stackView addArrangedSubview:memberLabel];
        }
    }

    // Add padding constraints
    for (NSView *subview in _stackView.arrangedSubviews) {
        if ([subview isKindOfClass:[NSTextField class]]) {
            [NSLayoutConstraint activateConstraints:@[
                [subview.leadingAnchor constraintEqualToAnchor:_stackView.leadingAnchor constant:12],
                [subview.trailingAnchor constraintEqualToAnchor:_stackView.trailingAnchor constant:-12],
            ]];
        }
    }
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

#pragma mark - Content VC Hosting

- (void)setContentViewController:(NSViewController *)viewController {
    if (_hostedContentVC == viewController) return;

    [self removeContentViewController];

    _hostedContentVC = viewController;
    [self clearStackView];

    // Hide the scroll view and host the child VC's view directly in our view
    _scrollView.hidden = YES;

    [self addChildViewController:viewController];
    NSView *childView = viewController.view;
    childView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:childView];

    [NSLayoutConstraint activateConstraints:@[
        [childView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [childView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [childView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [childView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)removeContentViewController {
    if (!_hostedContentVC) return;

    [_hostedContentVC.view removeFromSuperview];
    [_hostedContentVC removeFromParentViewController];
    _hostedContentVC = nil;

    _scrollView.hidden = NO;
    [self clearStackView];
    [self addPlaceholderContent];
}

#pragma mark - Layout Model Selection Notification

- (void)layoutModelSelectionDidChange:(NSNotification *)notification {
    NSArray<NSString *> *modelNames = notification.userInfo[@"modelNames"];
    sLastLayoutSelection = [modelNames copy];

    if (!modelNames || modelNames.count == 0) {
        [self clearInspector];
    } else if (modelNames.count == 1) {
        [self inspectModel:modelNames.firstObject];
    } else {
        [self inspectModels:modelNames];
    }
}

#pragma mark - XLModelPropertiesDelegate

- (void)modelProperties:(XLModelPropertiesView *)view
       didChangeProperty:(NSString *)key
                   value:(id)value
                forModel:(NSString *)modelName {
    // Get old value before updating
    NSDictionary *modelInfo = [_engineBridge getModelInfo:modelName];
    id oldValue = modelInfo[key];

    // Update model via engine bridge
    BOOL success = [_engineBridge updateModelProperty:modelName key:key value:value];
    if (success) {
        // Notify the layout tab about the property change (for undo, preview refresh)
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{
            @"modelName": modelName,
            @"key": key,
            @"value": value ?: [NSNull null],
        }];
        if (oldValue) {
            userInfo[@"oldValue"] = oldValue;
        }
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"XLInspectorPropertyDidChange"
                          object:self
                        userInfo:userInfo];
    }
}

- (void)modelPropertiesDidRequestEditCustomModel:(XLModelPropertiesView *)view
                                        forModel:(NSString *)modelName {
    XLCustomModelWindow *customModelWindow = [[XLCustomModelWindow alloc] initWithModelName:modelName];
    customModelWindow.engineBridge = _engineBridge;

    [customModelWindow showWithCompletion:^(BOOL saved) {
        if (saved) {
            NSDictionary *modelInfo = [self.engineBridge getModelInfo:modelName];
            if (modelInfo) {
                [self.modelPropertiesView showPropertiesForModel:modelName info:modelInfo];
            }
        }
    }];
}

@end
