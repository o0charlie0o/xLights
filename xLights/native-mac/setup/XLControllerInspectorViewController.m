/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLControllerInspectorViewController.h"
#import "XLKeychainHelper.h"
#import "../XLEngineBridge.h"

static const CGFloat kSectionHeaderHeight = 28.0;
static const CGFloat kSectionContentInset = 12.0;
static const CGFloat kRowHeight = 24.0;
static const CGFloat kRowSpacing = 6.0;
static const CGFloat kLabelWidth = 110.0;
static NSString * const kDisclosureStatePrefix = @"XLDisclosure_";

#pragma mark - XLDisclosureSection

@interface XLDisclosureSection ()

@property (nonatomic, copy) NSString *sectionIdentifier;
@property (nonatomic, strong) NSButton *disclosureButton;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSView *headerView;
@property (nonatomic, strong) NSLayoutConstraint *contentHeightConstraint;

@end

@implementation XLDisclosureSection

- (instancetype)initWithTitle:(NSString *)title identifier:(NSString *)identifier {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _title = [title copy];
        _sectionIdentifier = [identifier copy];
        _expanded = YES;

        self.translatesAutoresizingMaskIntoConstraints = NO;

        [self setupHeader];
        [self setupContentStack];
        [self restoreState];
        [self updateContentVisibility];
    }
    return self;
}

- (void)setupHeader {
    _headerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    _headerView.wantsLayer = YES;
    _headerView.layer.backgroundColor = [[NSColor colorWithWhite:0.2 alpha:1.0] CGColor];
    [self addSubview:_headerView];

    _disclosureButton = [NSButton buttonWithTitle:@""
                                           target:self
                                           action:@selector(toggleDisclosure:)];
    _disclosureButton.translatesAutoresizingMaskIntoConstraints = NO;
    _disclosureButton.bezelStyle = NSBezelStyleDisclosure;
    _disclosureButton.state = NSControlStateValueOn;
    [_disclosureButton setButtonType:NSButtonTypeOnOff];
    [_headerView addSubview:_disclosureButton];

    _titleLabel = [NSTextField labelWithString:_title];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    _titleLabel.textColor = [NSColor secondaryLabelColor];
    [_headerView addSubview:_titleLabel];

    // Make the whole header clickable
    NSClickGestureRecognizer *click = [[NSClickGestureRecognizer alloc]
                                       initWithTarget:self
                                       action:@selector(headerClicked:)];
    [_headerView addGestureRecognizer:click];

    [NSLayoutConstraint activateConstraints:@[
        [_headerView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_headerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_headerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_headerView.heightAnchor constraintEqualToConstant:kSectionHeaderHeight],

        [_disclosureButton.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:6],
        [_disclosureButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_disclosureButton.trailingAnchor constant:2],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_headerView.trailingAnchor constant:-8],
    ]];
}

- (void)setupContentStack {
    _contentStackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _contentStackView.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    _contentStackView.alignment = NSLayoutAttributeLeading;
    _contentStackView.spacing = kRowSpacing;
    _contentStackView.edgeInsets = NSEdgeInsetsMake(8, kSectionContentInset, 8, kSectionContentInset);
    [self addSubview:_contentStackView];

    [NSLayoutConstraint activateConstraints:@[
        [_contentStackView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_contentStackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_contentStackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_contentStackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)addRowWithLabel:(NSString *)label control:(NSView *)control {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *labelField = [NSTextField labelWithString:label];
    labelField.translatesAutoresizingMaskIntoConstraints = NO;
    labelField.font = [NSFont systemFontOfSize:11];
    labelField.textColor = [NSColor secondaryLabelColor];
    labelField.alignment = NSTextAlignmentRight;
    [labelField setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addSubview:labelField];

    control.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:control];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:kRowHeight],

        [labelField.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [labelField.widthAnchor constraintEqualToConstant:kLabelWidth],
        [labelField.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [control.leadingAnchor constraintEqualToAnchor:labelField.trailingAnchor constant:6],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    [_contentStackView addArrangedSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:_contentStackView.leadingAnchor constant:kSectionContentInset],
        [row.trailingAnchor constraintEqualToAnchor:_contentStackView.trailingAnchor constant:-kSectionContentInset],
    ]];
}

- (void)addFullWidthView:(NSView *)view {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStackView addArrangedSubview:view];

    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:_contentStackView.leadingAnchor constant:kSectionContentInset],
        [view.trailingAnchor constraintEqualToAnchor:_contentStackView.trailingAnchor constant:-kSectionContentInset],
    ]];
}

- (void)toggleDisclosure:(id)sender {
    self.expanded = !self.expanded;
}

- (void)headerClicked:(NSClickGestureRecognizer *)gesture {
    self.expanded = !self.expanded;
}

- (void)setExpanded:(BOOL)expanded {
    _expanded = expanded;
    _disclosureButton.state = expanded ? NSControlStateValueOn : NSControlStateValueOff;
    [self saveState];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.2;
        context.allowsImplicitAnimation = YES;
        [self updateContentVisibility];
        [self.superview layoutSubtreeIfNeeded];
    }];
}

- (void)updateContentVisibility {
    _contentStackView.hidden = !_expanded;
}

- (void)saveState {
    NSString *key = [kDisclosureStatePrefix stringByAppendingString:_sectionIdentifier];
    [[NSUserDefaults standardUserDefaults] setBool:_expanded forKey:key];
}

- (void)restoreState {
    NSString *key = [kDisclosureStatePrefix stringByAppendingString:_sectionIdentifier];
    if ([[NSUserDefaults standardUserDefaults] objectForKey:key]) {
        _expanded = [[NSUserDefaults standardUserDefaults] boolForKey:key];
        _disclosureButton.state = _expanded ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

@end

#pragma mark - XLControllerInspectorViewController

@interface XLControllerInspectorViewController () <NSTextFieldDelegate>

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSStackView *mainStack;
@property (nonatomic, strong) NSView *emptyStateView;

// General section controls
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *descriptionField;
@property (nonatomic, strong) NSSwitch *activeSwitch;
@property (nonatomic, strong) NSTextField *idField;

// Connection section controls
@property (nonatomic, strong) NSTextField *ipAddressField;
@property (nonatomic, strong) NSPopUpButton *serialPortPopUp;
@property (nonatomic, strong) NSPopUpButton *protocolPopUp;
@property (nonatomic, strong) NSTextField *startUniverseField;
@property (nonatomic, strong) NSTextField *universeCountField;
@property (nonatomic, strong) NSTextField *startChannelField;

// Authentication section controls
@property (nonatomic, strong) NSTextField *authUsernameField;
@property (nonatomic, strong) NSSecureTextField *authPasswordField;

// Hardware section controls
@property (nonatomic, strong) NSPopUpButton *vendorPopUp;
@property (nonatomic, strong) NSPopUpButton *modelPopUp;
@property (nonatomic, strong) NSPopUpButton *variantPopUp;

// Capabilities section controls (read-only)
@property (nonatomic, strong) NSTextField *maxChannelsField;
@property (nonatomic, strong) NSTextField *supportedProtocolsField;
@property (nonatomic, strong) NSTextField *maxUniversesField;
@property (nonatomic, strong) NSTextField *supportsUploadField;

// Upload section controls
@property (nonatomic, strong) NSButton *uploadButton;
@property (nonatomic, strong) NSSwitch *autoUploadSwitch;
@property (nonatomic, strong) NSTextField *lastUploadField;

// Section references
@property (nonatomic, strong) XLDisclosureSection *generalSection;
@property (nonatomic, strong) XLDisclosureSection *connectionSection;
@property (nonatomic, strong) XLDisclosureSection *authSection;
@property (nonatomic, strong) XLDisclosureSection *hardwareSection;
@property (nonatomic, strong) XLDisclosureSection *capabilitiesSection;
@property (nonatomic, strong) XLDisclosureSection *uploadSection;

// Current data
@property (nonatomic, strong) NSDictionary *currentData;
@property (nonatomic, assign) BOOL isEthernetController;
@property (nonatomic, assign) BOOL supportsAuth;

// Base show folder state
@property (nonatomic, strong) NSView *baseBannerView;
@property (nonatomic, assign) BOOL isFromBase;

@end

@implementation XLControllerInspectorViewController

#pragma mark - View Lifecycle

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 600)];
    root.wantsLayer = YES;
    root.layer.backgroundColor = [[NSColor colorWithWhite:0.14 alpha:1.0] CGColor];

    _scrollView = [[NSScrollView alloc] initWithFrame:root.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.drawsBackground = NO;
    _scrollView.automaticallyAdjustsContentInsets = NO;
    _scrollView.contentInsets = NSEdgeInsetsMake(0, 0, 0, 0);
    [root addSubview:_scrollView];

    _mainStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    _mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _mainStack.alignment = NSLayoutAttributeLeading;
    _mainStack.spacing = 1;
    _mainStack.distribution = NSStackViewDistributionFill;

    _scrollView.documentView = _mainStack;

    NSClipView *clipView = _scrollView.contentView;
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],

        [_mainStack.topAnchor constraintEqualToAnchor:clipView.topAnchor],
        [_mainStack.leadingAnchor constraintEqualToAnchor:clipView.leadingAnchor],
        [_mainStack.trailingAnchor constraintEqualToAnchor:clipView.trailingAnchor],
    ]];

    [self setupEmptyState:root];
    [self buildSections];
    [self showEmptyState];

    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

#pragma mark - Empty State

- (void)setupEmptyState:(NSView *)root {
    _emptyStateView = [[NSView alloc] initWithFrame:NSZeroRect];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_emptyStateView];

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [NSImage imageWithSystemSymbolName:@"slider.horizontal.3"
                          accessibilityDescription:@"No Controller"];
    icon.contentTintColor = [NSColor tertiaryLabelColor];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [_emptyStateView addSubview:icon];

    NSTextField *label = [NSTextField labelWithString:@"No Controller Selected"];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    label.textColor = [NSColor tertiaryLabelColor];
    label.alignment = NSTextAlignmentCenter;
    [_emptyStateView addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_emptyStateView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [_emptyStateView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_emptyStateView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],

        [icon.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:_emptyStateView.centerYAnchor constant:-20],
        [icon.widthAnchor constraintEqualToConstant:36],
        [icon.heightAnchor constraintEqualToConstant:36],

        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:10],
        [label.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:_emptyStateView.leadingAnchor constant:20],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:_emptyStateView.trailingAnchor constant:-20],
    ]];
}

- (void)showEmptyState {
    _emptyStateView.hidden = NO;
    _scrollView.hidden = YES;
}

- (void)hideEmptyState {
    _emptyStateView.hidden = YES;
    _scrollView.hidden = NO;
}

#pragma mark - Section Building

- (void)buildSections {
    [self buildBaseBanner];
    [self buildGeneralSection];
    [self buildConnectionSection];
    [self buildAuthSection];
    [self buildHardwareSection];
    [self buildCapabilitiesSection];
    [self buildUploadSection];
}

- (void)buildBaseBanner {
    _baseBannerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _baseBannerView.translatesAutoresizingMaskIntoConstraints = NO;
    _baseBannerView.wantsLayer = YES;
    _baseBannerView.layer.backgroundColor = [[NSColor colorWithRed:0.0 green:0.6 blue:0.8 alpha:0.15] CGColor];
    _baseBannerView.hidden = YES;

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [NSImage imageWithSystemSymbolName:@"link"
                          accessibilityDescription:@"Linked to Base"];
    icon.contentTintColor = [NSColor cyanColor];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [_baseBannerView addSubview:icon];

    NSTextField *label = [NSTextField labelWithString:@"From Base Show Directory"];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    label.textColor = [NSColor cyanColor];
    [_baseBannerView addSubview:label];

    NSTextField *hint = [NSTextField labelWithString:@"Unlink via context menu to edit"];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.font = [NSFont systemFontOfSize:10];
    hint.textColor = [NSColor secondaryLabelColor];
    [_baseBannerView addSubview:hint];

    [NSLayoutConstraint activateConstraints:@[
        [_baseBannerView.heightAnchor constraintEqualToConstant:48.0],

        [icon.leadingAnchor constraintEqualToAnchor:_baseBannerView.leadingAnchor constant:12],
        [icon.centerYAnchor constraintEqualToAnchor:_baseBannerView.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:16],
        [icon.heightAnchor constraintEqualToConstant:16],

        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
        [label.topAnchor constraintEqualToAnchor:_baseBannerView.topAnchor constant:6],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:_baseBannerView.trailingAnchor constant:-12],

        [hint.leadingAnchor constraintEqualToAnchor:label.leadingAnchor],
        [hint.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:2],
        [hint.trailingAnchor constraintLessThanOrEqualToAnchor:_baseBannerView.trailingAnchor constant:-12],
    ]];

    [_mainStack addArrangedSubview:_baseBannerView];
    [NSLayoutConstraint activateConstraints:@[
        [_baseBannerView.leadingAnchor constraintEqualToAnchor:_mainStack.leadingAnchor],
        [_baseBannerView.trailingAnchor constraintEqualToAnchor:_mainStack.trailingAnchor],
    ]];
}

- (void)buildGeneralSection {
    _generalSection = [[XLDisclosureSection alloc] initWithTitle:@"GENERAL" identifier:@"controller_general"];

    _nameField = [self makeEditableTextField];
    _nameField.placeholderString = @"Controller Name";
    _nameField.delegate = self;
    _nameField.tag = 100;
    [_generalSection addRowWithLabel:@"Name" control:_nameField];

    _descriptionField = [self makeEditableTextField];
    _descriptionField.placeholderString = @"Description";
    _descriptionField.delegate = self;
    _descriptionField.tag = 101;
    [_generalSection addRowWithLabel:@"Description" control:_descriptionField];

    _activeSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    _activeSwitch.target = self;
    _activeSwitch.action = @selector(activeSwitchChanged:);
    [_generalSection addRowWithLabel:@"Active" control:_activeSwitch];

    _idField = [self makeReadOnlyTextField];
    [_generalSection addRowWithLabel:@"ID" control:_idField];

    [_mainStack addArrangedSubview:_generalSection];
    [NSLayoutConstraint activateConstraints:@[
        [_generalSection.leadingAnchor constraintEqualToAnchor:_mainStack.leadingAnchor],
        [_generalSection.trailingAnchor constraintEqualToAnchor:_mainStack.trailingAnchor],
    ]];
}

- (void)buildConnectionSection {
    _connectionSection = [[XLDisclosureSection alloc] initWithTitle:@"CONNECTION" identifier:@"controller_connection"];

    _ipAddressField = [self makeEditableTextField];
    _ipAddressField.placeholderString = @"192.168.1.100";
    _ipAddressField.delegate = self;
    _ipAddressField.tag = 200;
    [_connectionSection addRowWithLabel:@"IP Address" control:_ipAddressField];

    _serialPortPopUp = [self makePopUpButton];
    _serialPortPopUp.tag = 201;
    [_serialPortPopUp addItemWithTitle:@"(None)"];
    [_connectionSection addRowWithLabel:@"Serial Port" control:_serialPortPopUp];

    _protocolPopUp = [self makePopUpButton];
    _protocolPopUp.tag = 202;
    [_protocolPopUp addItemsWithTitles:@[@"E1.31", @"ArtNet", @"DDP", @"Kinet", @"OPC", @"DMX", @"LOR", @"Renard"]];
    _protocolPopUp.target = self;
    _protocolPopUp.action = @selector(protocolChanged:);
    [_connectionSection addRowWithLabel:@"Protocol" control:_protocolPopUp];

    _startUniverseField = [self makeEditableTextField];
    _startUniverseField.placeholderString = @"1";
    _startUniverseField.delegate = self;
    _startUniverseField.tag = 203;
    [_connectionSection addRowWithLabel:@"Start Universe" control:_startUniverseField];

    _universeCountField = [self makeEditableTextField];
    _universeCountField.placeholderString = @"1";
    _universeCountField.delegate = self;
    _universeCountField.tag = 204;
    [_connectionSection addRowWithLabel:@"Universe Count" control:_universeCountField];

    _startChannelField = [self makeEditableTextField];
    _startChannelField.placeholderString = @"1";
    _startChannelField.delegate = self;
    _startChannelField.tag = 205;
    [_connectionSection addRowWithLabel:@"Start Channel" control:_startChannelField];

    [_mainStack addArrangedSubview:_connectionSection];
    [NSLayoutConstraint activateConstraints:@[
        [_connectionSection.leadingAnchor constraintEqualToAnchor:_mainStack.leadingAnchor],
        [_connectionSection.trailingAnchor constraintEqualToAnchor:_mainStack.trailingAnchor],
    ]];
}

- (void)buildAuthSection {
    _authSection = [[XLDisclosureSection alloc] initWithTitle:@"AUTHENTICATION" identifier:@"controller_auth"];

    _authUsernameField = [self makeEditableTextField];
    _authUsernameField.placeholderString = @"Username";
    _authUsernameField.delegate = self;
    _authUsernameField.tag = 210;
    [_authSection addRowWithLabel:@"Username" control:_authUsernameField];

    _authPasswordField = [self makeSecureTextField];
    _authPasswordField.placeholderString = @"Password";
    _authPasswordField.delegate = self;
    _authPasswordField.tag = 211;
    [_authSection addRowWithLabel:@"Password" control:_authPasswordField];

    _authSection.hidden = YES;

    [_mainStack addArrangedSubview:_authSection];
    [NSLayoutConstraint activateConstraints:@[
        [_authSection.leadingAnchor constraintEqualToAnchor:_mainStack.leadingAnchor],
        [_authSection.trailingAnchor constraintEqualToAnchor:_mainStack.trailingAnchor],
    ]];
}

- (void)buildHardwareSection {
    _hardwareSection = [[XLDisclosureSection alloc] initWithTitle:@"HARDWARE" identifier:@"controller_hardware"];

    _vendorPopUp = [self makePopUpButton];
    _vendorPopUp.tag = 300;
    _vendorPopUp.target = self;
    _vendorPopUp.action = @selector(vendorChanged:);
    [_hardwareSection addRowWithLabel:@"Vendor" control:_vendorPopUp];

    _modelPopUp = [self makePopUpButton];
    _modelPopUp.tag = 301;
    _modelPopUp.target = self;
    _modelPopUp.action = @selector(modelChanged:);
    [_hardwareSection addRowWithLabel:@"Model" control:_modelPopUp];

    _variantPopUp = [self makePopUpButton];
    _variantPopUp.tag = 302;
    _variantPopUp.target = self;
    _variantPopUp.action = @selector(variantChanged:);
    [_hardwareSection addRowWithLabel:@"Variant" control:_variantPopUp];

    [_mainStack addArrangedSubview:_hardwareSection];
    [NSLayoutConstraint activateConstraints:@[
        [_hardwareSection.leadingAnchor constraintEqualToAnchor:_mainStack.leadingAnchor],
        [_hardwareSection.trailingAnchor constraintEqualToAnchor:_mainStack.trailingAnchor],
    ]];
}

- (void)buildCapabilitiesSection {
    _capabilitiesSection = [[XLDisclosureSection alloc] initWithTitle:@"CAPABILITIES" identifier:@"controller_capabilities"];

    _maxChannelsField = [self makeReadOnlyTextField];
    [_capabilitiesSection addRowWithLabel:@"Max Channels" control:_maxChannelsField];

    _supportedProtocolsField = [self makeReadOnlyTextField];
    [_capabilitiesSection addRowWithLabel:@"Protocols" control:_supportedProtocolsField];

    _maxUniversesField = [self makeReadOnlyTextField];
    [_capabilitiesSection addRowWithLabel:@"Max Universes" control:_maxUniversesField];

    _supportsUploadField = [self makeReadOnlyTextField];
    [_capabilitiesSection addRowWithLabel:@"Upload" control:_supportsUploadField];

    [_mainStack addArrangedSubview:_capabilitiesSection];
    [NSLayoutConstraint activateConstraints:@[
        [_capabilitiesSection.leadingAnchor constraintEqualToAnchor:_mainStack.leadingAnchor],
        [_capabilitiesSection.trailingAnchor constraintEqualToAnchor:_mainStack.trailingAnchor],
    ]];
}

- (void)buildUploadSection {
    _uploadSection = [[XLDisclosureSection alloc] initWithTitle:@"UPLOAD" identifier:@"controller_upload"];

    _uploadButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    _uploadButton.translatesAutoresizingMaskIntoConstraints = NO;
    _uploadButton.title = @"Upload Configuration";
    _uploadButton.bezelStyle = NSBezelStyleRounded;
    _uploadButton.target = self;
    _uploadButton.action = @selector(uploadConfiguration:);
    [_uploadButton setContentHuggingPriority:NSLayoutPriorityDefaultLow
                              forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_uploadSection addFullWidthView:_uploadButton];

    _autoUploadSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    _autoUploadSwitch.target = self;
    _autoUploadSwitch.action = @selector(autoUploadChanged:);
    [_uploadSection addRowWithLabel:@"Auto Upload" control:_autoUploadSwitch];

    _lastUploadField = [self makeReadOnlyTextField];
    [_uploadSection addRowWithLabel:@"Last Upload" control:_lastUploadField];

    [_mainStack addArrangedSubview:_uploadSection];
    [NSLayoutConstraint activateConstraints:@[
        [_uploadSection.leadingAnchor constraintEqualToAnchor:_mainStack.leadingAnchor],
        [_uploadSection.trailingAnchor constraintEqualToAnchor:_mainStack.trailingAnchor],
    ]];
}

#pragma mark - Control Factory Helpers

- (NSTextField *)makeEditableTextField {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.font = [NSFont systemFontOfSize:11];
    field.textColor = [NSColor labelColor];
    field.backgroundColor = [NSColor colorWithWhite:0.22 alpha:1.0];
    field.bordered = YES;
    field.bezelStyle = NSTextFieldRoundedBezel;
    field.editable = YES;
    field.selectable = YES;
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.cell.scrollable = YES;
    [field setContentHuggingPriority:NSLayoutPriorityDefaultLow
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    return field;
}

- (NSSecureTextField *)makeSecureTextField {
    NSSecureTextField *field = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.font = [NSFont systemFontOfSize:11];
    field.textColor = [NSColor labelColor];
    field.backgroundColor = [NSColor colorWithWhite:0.22 alpha:1.0];
    field.bordered = YES;
    field.bezelStyle = NSTextFieldRoundedBezel;
    field.editable = YES;
    field.selectable = YES;
    field.cell.scrollable = YES;
    [field setContentHuggingPriority:NSLayoutPriorityDefaultLow
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    return field;
}

- (NSTextField *)makeReadOnlyTextField {
    NSTextField *field = [NSTextField labelWithString:@"--"];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.font = [NSFont systemFontOfSize:11];
    field.textColor = [NSColor tertiaryLabelColor];
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    [field setContentHuggingPriority:NSLayoutPriorityDefaultLow
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    return field;
}

- (NSPopUpButton *)makePopUpButton {
    NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.font = [NSFont systemFontOfSize:11];
    button.controlSize = NSControlSizeSmall;
    [button setContentHuggingPriority:NSLayoutPriorityDefaultLow
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    return button;
}

#pragma mark - Data Population

- (void)setControllerData:(NSDictionary *)data {
    if (!data) {
        [self clearInspector];
        return;
    }

    _currentData = [data copy];
    [self hideEmptyState];

    NSString *type = data[@"type"] ?: @"Ethernet";
    _isEthernetController = [type isEqualToString:@"Ethernet"];

    NSNumber *authSupported = data[@"supportsAuth"];
    _supportsAuth = authSupported ? authSupported.boolValue : NO;

    [self populateGeneralSection:data];
    [self populateConnectionSection:data];
    [self populateAuthSection:data];
    [self populateHardwareSection:data];
    [self populateCapabilitiesSection:data];
    [self populateUploadSection:data];
    [self updateConnectionFieldVisibility];

    NSNumber *fromBaseNum = data[@"fromBase"];
    _isFromBase = fromBaseNum ? fromBaseNum.boolValue : NO;
    [self updateBaseShowFolderState];
}

- (void)populateGeneralSection:(NSDictionary *)data {
    _nameField.stringValue = data[@"name"] ?: @"";
    _descriptionField.stringValue = data[@"description"] ?: @"";

    NSString *active = data[@"active"] ?: @"Active";
    _activeSwitch.state = [active isEqualToString:@"Active"] ? NSControlStateValueOn : NSControlStateValueOff;

    NSNumber *controllerId = data[@"id"];
    _idField.stringValue = controllerId ? [controllerId stringValue] : @"--";
}

- (void)populateConnectionSection:(NSDictionary *)data {
    _ipAddressField.stringValue = data[@"ip"] ?: @"";

    NSString *protocol = data[@"protocol"] ?: @"E1.31";
    [_protocolPopUp selectItemWithTitle:protocol];
    if (_protocolPopUp.selectedItem == nil && _protocolPopUp.numberOfItems > 0) {
        [_protocolPopUp selectItemAtIndex:0];
    }

    NSNumber *startUniverse = data[@"startUniverse"];
    _startUniverseField.stringValue = startUniverse ? [startUniverse stringValue] : @"1";

    NSNumber *universeCount = data[@"universeCount"];
    _universeCountField.stringValue = universeCount ? [universeCount stringValue] : @"1";

    NSNumber *startChannel = data[@"startChannel"];
    _startChannelField.stringValue = startChannel ? [startChannel stringValue] : @"1";

    [self populateSerialPorts];
    NSString *serialPort = data[@"serialPort"];
    if (serialPort) {
        [_serialPortPopUp selectItemWithTitle:serialPort];
    }
}

- (void)populateAuthSection:(NSDictionary *)data {
    _authSection.hidden = !_supportsAuth;

    if (!_supportsAuth) {
        _authUsernameField.stringValue = @"";
        _authPasswordField.stringValue = @"";
        return;
    }

    NSString *username = data[@"authUsername"] ?: @"";
    _authUsernameField.stringValue = username;

    if (username.length > 0) {
        NSString *controllerName = data[@"name"] ?: @"";
        NSString *password = [XLKeychainHelper passwordForController:controllerName
                                                            username:username];
        _authPasswordField.stringValue = password ?: @"";
    } else {
        _authPasswordField.stringValue = @"";
    }
}

- (void)populateHardwareSection:(NSDictionary *)data {
    [self populateVendorList];

    NSString *vendor = data[@"vendor"] ?: @"";
    if (vendor.length > 0) {
        [_vendorPopUp selectItemWithTitle:vendor];
    } else {
        [_vendorPopUp selectItemAtIndex:0];
    }

    [self updateModelListForVendor:vendor];
    NSString *model = data[@"model"] ?: @"";
    if (model.length > 0) {
        [_modelPopUp selectItemWithTitle:model];
    }

    [self updateVariantListForModel:model vendor:vendor];
    NSString *variant = data[@"variant"] ?: @"";
    if (variant.length > 0) {
        [_variantPopUp selectItemWithTitle:variant];
    }
}

- (void)populateCapabilitiesSection:(NSDictionary *)data {
    NSNumber *maxChannels = data[@"maxChannels"];
    _maxChannelsField.stringValue = maxChannels ? [maxChannels stringValue] : @"--";

    NSString *protocols = data[@"supportedProtocols"];
    _supportedProtocolsField.stringValue = protocols ?: @"--";

    NSNumber *maxUniverses = data[@"maxUniverses"];
    _maxUniversesField.stringValue = maxUniverses ? [maxUniverses stringValue] : @"--";

    NSNumber *supportsUpload = data[@"supportsUpload"];
    _supportsUploadField.stringValue = (supportsUpload && supportsUpload.boolValue) ? @"Yes" : @"No";
}

- (void)populateUploadSection:(NSDictionary *)data {
    NSNumber *autoUpload = data[@"autoUpload"];
    _autoUploadSwitch.state = (autoUpload && autoUpload.boolValue) ? NSControlStateValueOn : NSControlStateValueOff;

    NSString *lastUpload = data[@"lastUpload"];
    _lastUploadField.stringValue = lastUpload ?: @"Never";

    NSNumber *supportsUpload = data[@"supportsUpload"];
    _uploadButton.enabled = supportsUpload ? supportsUpload.boolValue : NO;
}

- (void)clearInspector {
    _currentData = nil;
    _supportsAuth = NO;
    _authSection.hidden = YES;
    _isFromBase = NO;
    _baseBannerView.hidden = YES;
    [self showEmptyState];
}

#pragma mark - Connection Field Visibility

- (void)updateConnectionFieldVisibility {
    // Show IP fields for Ethernet controllers, serial port for Serial controllers
    _ipAddressField.superview.hidden = !_isEthernetController;
    _serialPortPopUp.superview.hidden = _isEthernetController;
    _startUniverseField.superview.hidden = !_isEthernetController;
    _universeCountField.superview.hidden = !_isEthernetController;
}

#pragma mark - Authentication

- (void)saveAuthCredentials {
    NSString *controllerName = _currentData[@"name"] ?: @"";
    NSString *username = _authUsernameField.stringValue;
    NSString *password = _authPasswordField.stringValue;

    if (controllerName.length == 0) return;

    if (username.length > 0 && password.length > 0) {
        [XLKeychainHelper savePassword:password
                         forController:controllerName
                              username:username];
    } else if (username.length == 0) {
        NSString *oldUsername = _currentData[@"authUsername"] ?: @"";
        if (oldUsername.length > 0) {
            [XLKeychainHelper deletePasswordForController:controllerName
                                                username:oldUsername];
        }
    }
}

#pragma mark - Vendor/Model/Variant Cascading

- (void)populateVendorList {
    [_vendorPopUp removeAllItems];
    [_vendorPopUp addItemWithTitle:@"(None)"];

    // Known vendor names from .xcontroller files
    NSArray *vendors = @[
        @"Advatek", @"ESPixelStick", @"Experience Lights", @"Falcon",
        @"FPP", @"Hanson", @"HinksPix", @"Holiday Coro",
        @"iLightThat", @"J1Sys", @"Kulp", @"LOR",
        @"Mattos Designs", @"MicroCyb", @"Minleon", @"RGB2Go",
        @"SanDevices", @"Scott", @"Twinkly", @"Wally's Lights",
        @"Wasatch", @"WLED", @"YPS"
    ];

    [_vendorPopUp addItemsWithTitles:vendors];
}

- (void)updateModelListForVendor:(NSString *)vendor {
    [_modelPopUp removeAllItems];
    [_modelPopUp addItemWithTitle:@"(None)"];

    if (vendor.length == 0 || [vendor isEqualToString:@"(None)"]) return;

    // Query the engine bridge for models available for this vendor
    NSDictionary *info = [_engineBridge getControllerInfo:vendor];
    NSArray *models = info[@"models"];
    if (models) {
        [_modelPopUp addItemsWithTitles:models];
    }
}

- (void)updateVariantListForModel:(NSString *)model vendor:(NSString *)vendor {
    [_variantPopUp removeAllItems];
    [_variantPopUp addItemWithTitle:@"(None)"];

    if (model.length == 0 || [model isEqualToString:@"(None)"]) return;
    if (vendor.length == 0 || [vendor isEqualToString:@"(None)"]) return;

    // Query the engine bridge for variants available for this vendor+model
    NSString *key = [NSString stringWithFormat:@"%@/%@", vendor, model];
    NSDictionary *info = [_engineBridge getControllerInfo:key];
    NSArray *variants = info[@"variants"];
    if (variants) {
        [_variantPopUp addItemsWithTitles:variants];
    }
}

- (void)populateSerialPorts {
    [_serialPortPopUp removeAllItems];
    [_serialPortPopUp addItemWithTitle:@"(None)"];

    // On macOS, list serial ports from /dev/
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *devContents = [fm contentsOfDirectoryAtPath:@"/dev" error:nil];
    for (NSString *entry in devContents) {
        if ([entry hasPrefix:@"cu."] || [entry hasPrefix:@"tty.usb"] || [entry hasPrefix:@"tty.serial"]) {
            [_serialPortPopUp addItemWithTitle:[@"/dev/" stringByAppendingString:entry]];
        }
    }
}

#pragma mark - Actions

- (void)activeSwitchChanged:(NSSwitch *)sender {
    [self notifyDelegate];
}

- (void)protocolChanged:(NSPopUpButton *)sender {
    [self notifyDelegate];
}

- (void)vendorChanged:(NSPopUpButton *)sender {
    NSString *vendor = sender.titleOfSelectedItem;
    [self updateModelListForVendor:vendor];
    [self updateVariantListForModel:@"" vendor:vendor];
    [self notifyDelegate];
}

- (void)modelChanged:(NSPopUpButton *)sender {
    NSString *vendor = _vendorPopUp.titleOfSelectedItem;
    NSString *model = sender.titleOfSelectedItem;
    [self updateVariantListForModel:model vendor:vendor];
    [self notifyDelegate];
}

- (void)variantChanged:(NSPopUpButton *)sender {
    [self notifyDelegate];
}

- (void)uploadConfiguration:(NSButton *)sender {
    [self notifyDelegate];
}

- (void)autoUploadChanged:(NSSwitch *)sender {
    [self notifyDelegate];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *field = notification.object;

    if (field.tag == 100) {
        // Name field - validate non-empty
        if (field.stringValue.length == 0) {
            field.stringValue = _currentData[@"name"] ?: @"";
            return;
        }
    } else if (field.tag == 200) {
        // IP address field - basic validation
        NSString *ip = field.stringValue;
        if (ip.length > 0 && ![self isValidIPAddress:ip] && ![self isValidHostname:ip]) {
            NSBeep();
            return;
        }
    } else if (field.tag >= 203 && field.tag <= 205) {
        // Numeric fields - validate
        NSInteger value = field.integerValue;
        if (value < 0) {
            field.integerValue = 1;
        }
    } else if (field.tag == 210 || field.tag == 211) {
        // Authentication fields - save credentials via keychain
        [self saveAuthCredentials];
        [self notifyDelegate];
        return;
    }

    [self notifyDelegate];
}

#pragma mark - Validation Helpers

- (BOOL)isValidIPAddress:(NSString *)address {
    NSArray *parts = [address componentsSeparatedByString:@"."];
    if (parts.count != 4) return NO;
    for (NSString *part in parts) {
        NSInteger val = part.integerValue;
        if (val < 0 || val > 255) return NO;
        if (part.length == 0) return NO;
    }
    return YES;
}

- (BOOL)isValidHostname:(NSString *)hostname {
    if (hostname.length == 0 || hostname.length > 253) return NO;
    NSString *pattern = @"^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?)*$";
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", pattern];
    return [predicate evaluateWithObject:hostname];
}

#pragma mark - Delegate Notification

- (void)notifyDelegate {
    if ([_delegate respondsToSelector:@selector(inspectorDidUpdateController:)]) {
        [_delegate inspectorDidUpdateController:self];
    }
}

@end
