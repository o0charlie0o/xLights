#import "InspectorView.h"

@interface InspectorView ()

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSView *documentView;
@property (nonatomic, strong) NSStackView *rootStack;
@property (nonatomic, strong) NSMutableArray<InspectorDisclosureGroup *> *disclosureGroups;

@end

@implementation InspectorView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _disclosureGroups = [NSMutableArray array];
        [self setupScrollView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _disclosureGroups = [NSMutableArray array];
        [self setupScrollView];
    }
    return self;
}

#pragma mark - Setup

- (void)setupScrollView {
    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers = YES;
    _scrollView.drawsBackground = NO;
    _scrollView.automaticallyAdjustsContentInsets = YES;
    [self addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];

    _documentView = [[NSView alloc] initWithFrame:NSZeroRect];
    _documentView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.documentView = _documentView;

    // Pin document view width to clip view width so content doesn't scroll horizontally
    NSClipView *clipView = _scrollView.contentView;
    [NSLayoutConstraint activateConstraints:@[
        [_documentView.topAnchor constraintEqualToAnchor:clipView.topAnchor],
        [_documentView.leadingAnchor constraintEqualToAnchor:clipView.leadingAnchor],
        [_documentView.trailingAnchor constraintEqualToAnchor:clipView.trailingAnchor],
    ]];

    [self buildRootStack];
}

- (void)buildRootStack {
    _rootStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    _rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _rootStack.alignment = NSLayoutAttributeLeading;
    _rootStack.spacing = 0;
    [_documentView addSubview:_rootStack];

    [NSLayoutConstraint activateConstraints:@[
        [_rootStack.topAnchor constraintEqualToAnchor:_documentView.topAnchor],
        [_rootStack.leadingAnchor constraintEqualToAnchor:_documentView.leadingAnchor],
        [_rootStack.trailingAnchor constraintEqualToAnchor:_documentView.trailingAnchor],
        [_rootStack.bottomAnchor constraintEqualToAnchor:_documentView.bottomAnchor],
    ]];
}

#pragma mark - Public API

- (void)setGroups:(NSArray<InspectorGroup *> *)groups {
    _groups = [groups copy];

    // Tear down existing group views
    for (InspectorDisclosureGroup *dg in _disclosureGroups) {
        [dg removeFromSuperview];
    }
    [_disclosureGroups removeAllObjects];

    // Build new group views
    for (InspectorGroup *group in groups) {
        InspectorDisclosureGroup *dg = [[InspectorDisclosureGroup alloc] initWithGroup:group];
        [_rootStack addArrangedSubview:dg];
        [_disclosureGroups addObject:dg];

        [NSLayoutConstraint activateConstraints:@[
            [dg.leadingAnchor constraintEqualToAnchor:_rootStack.leadingAnchor],
            [dg.trailingAnchor constraintEqualToAnchor:_rootStack.trailingAnchor],
        ]];

        // Wire up change callbacks to delegate
        __weak InspectorView *weakSelf = self;
        for (InspectorProperty *prop in group.properties) {
            InspectorValueChangedBlock existing = prop.onValueChanged;
            prop.onValueChanged = ^(id sender) {
                if (existing) existing(sender);
                InspectorView *strongSelf = weakSelf;
                if (strongSelf && [strongSelf.delegate respondsToSelector:@selector(inspectorView:didChangeProperty:inGroup:)]) {
                    [strongSelf.delegate inspectorView:strongSelf
                                     didChangeProperty:sender
                                               inGroup:group];
                }
            };
        }
    }
}

- (InspectorProperty *)propertyWithId:(NSString *)identifier {
    for (InspectorGroup *group in _groups) {
        InspectorProperty *prop = [group propertyWithId:identifier];
        if (prop) return prop;
    }
    return nil;
}

- (InspectorGroup *)groupWithId:(NSString *)identifier {
    for (InspectorGroup *group in _groups) {
        if ([group.identifier isEqualToString:identifier]) {
            return group;
        }
    }
    return nil;
}

- (void)refreshFromModel {
    for (InspectorDisclosureGroup *dg in _disclosureGroups) {
        [dg refreshFromModel];
    }
}

- (void)expandAll {
    for (InspectorDisclosureGroup *dg in _disclosureGroups) {
        [dg setExpanded:YES animated:YES];
    }
}

- (void)collapseAll {
    for (InspectorDisclosureGroup *dg in _disclosureGroups) {
        [dg setExpanded:NO animated:YES];
    }
}

- (NSDictionary<NSString *, id> *)allValues {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (InspectorGroup *group in _groups) {
        for (InspectorProperty *prop in group.properties) {
            if (prop.identifier && prop.value) {
                result[prop.identifier] = prop.value;
            }
        }
    }
    return [result copy];
}

@end
