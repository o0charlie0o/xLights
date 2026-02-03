#import "InspectorDisclosureGroup.h"

static const CGFloat kHeaderHeight = 26.0;
static const CGFloat kPropertySpacing = 4.0;
static const CGFloat kContentInsetLeft = 4.0;
static const CGFloat kContentInsetRight = 8.0;
static const CGFloat kSeparatorHeight = 1.0;

@interface InspectorDisclosureGroup ()

@property (nonatomic, strong) NSButton *disclosureButton;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSStackView *contentStack;
@property (nonatomic, strong) NSView *separator;
@property (nonatomic, strong) NSLayoutConstraint *contentHeightConstraint;
@property (nonatomic, strong) NSMutableArray<InspectorPropertyRow *> *mutablePropertyRows;

@end

@implementation InspectorDisclosureGroup

- (instancetype)initWithGroup:(InspectorGroup *)group {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _group = group;
        _mutablePropertyRows = [NSMutableArray array];
        self.translatesAutoresizingMaskIntoConstraints = NO;

        [self buildHeader];
        [self buildContent];
        [self buildSeparator];
        [self updateContentVisibility:NO];
    }
    return self;
}

- (NSArray<InspectorPropertyRow *> *)propertyRows {
    return [_mutablePropertyRows copy];
}

#pragma mark - Header

- (void)buildHeader {
    _disclosureButton = [NSButton buttonWithTitle:@""
                                           target:self
                                           action:@selector(headerClicked:)];
    _disclosureButton.translatesAutoresizingMaskIntoConstraints = NO;
    _disclosureButton.bezelStyle = NSBezelStyleDisclosure;
    _disclosureButton.state = _group.isExpanded ? NSControlStateValueOn : NSControlStateValueOff;
    _disclosureButton.controlSize = NSControlSizeSmall;
    [self addSubview:_disclosureButton];

    _titleLabel = [NSTextField labelWithString:_group.title];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont boldSystemFontOfSize:11.0];
    _titleLabel.textColor = [NSColor labelColor];

    // Make title clickable via a gesture recognizer
    NSClickGestureRecognizer *click = [[NSClickGestureRecognizer alloc]
                                       initWithTarget:self
                                       action:@selector(titleClicked:)];
    _titleLabel.allowsExpansionToolTips = YES;
    [_titleLabel addGestureRecognizer:click];
    [self addSubview:_titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_disclosureButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
        [_disclosureButton.centerYAnchor constraintEqualToAnchor:self.topAnchor constant:kHeaderHeight / 2.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_disclosureButton.trailingAnchor constant:2],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-8],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_disclosureButton.centerYAnchor],
    ]];
}

#pragma mark - Content

- (void)buildContent {
    _contentStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _contentStack.alignment = NSLayoutAttributeLeading;
    _contentStack.spacing = kPropertySpacing;
    _contentStack.edgeInsets = NSEdgeInsetsMake(0, kContentInsetLeft, 6, kContentInsetRight);
    [self addSubview:_contentStack];

    for (InspectorProperty *prop in _group.properties) {
        InspectorPropertyRow *row = [[InspectorPropertyRow alloc] initWithProperty:prop];
        [_contentStack addArrangedSubview:row];
        [_mutablePropertyRows addObject:row];

        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:_contentStack.leadingAnchor constant:kContentInsetLeft],
            [row.trailingAnchor constraintEqualToAnchor:_contentStack.trailingAnchor constant:-kContentInsetRight],
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [_contentStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:kHeaderHeight],
        [_contentStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_contentStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_contentStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-kSeparatorHeight],
    ]];
}

#pragma mark - Separator

- (void)buildSeparator {
    _separator = [[NSView alloc] initWithFrame:NSZeroRect];
    _separator.translatesAutoresizingMaskIntoConstraints = NO;
    _separator.wantsLayer = YES;
    _separator.layer.backgroundColor = [NSColor separatorColor].CGColor;
    [self addSubview:_separator];

    [NSLayoutConstraint activateConstraints:@[
        [_separator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_separator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_separator.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_separator.heightAnchor constraintEqualToConstant:kSeparatorHeight],
    ]];
}

#pragma mark - Expand/Collapse

- (void)headerClicked:(NSButton *)sender {
    [self toggleExpanded:YES];
}

- (void)titleClicked:(NSClickGestureRecognizer *)gesture {
    [self toggleExpanded:YES];
}

- (void)toggleExpanded:(BOOL)animated {
    [self setExpanded:!_group.isExpanded animated:animated];
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    _group.expanded = expanded;
    _disclosureButton.state = expanded ? NSControlStateValueOn : NSControlStateValueOff;
    [self updateContentVisibility:animated];
}

- (void)updateContentVisibility:(BOOL)animated {
    BOOL expanded = _group.isExpanded;

    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            context.allowsImplicitAnimation = YES;
            self.contentStack.hidden = !expanded;
            self.contentStack.alphaValue = expanded ? 1.0 : 0.0;
            [self.superview layoutSubtreeIfNeeded];
        } completionHandler:nil];
    } else {
        _contentStack.hidden = !expanded;
        _contentStack.alphaValue = expanded ? 1.0 : 0.0;
    }
}

#pragma mark - Refresh

- (void)refreshFromModel {
    for (InspectorPropertyRow *row in _mutablePropertyRows) {
        [row refreshFromModel];
    }
}

@end
