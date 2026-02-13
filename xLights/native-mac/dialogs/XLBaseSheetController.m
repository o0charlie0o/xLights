/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLBaseSheetController.h"
#import <objc/runtime.h>

static const CGFloat kDefaultMinWidth = 400.0;
static const CGFloat kDefaultMinHeight = 200.0;
static const CGFloat kButtonBarHeight = 50.0;
static const CGFloat kButtonSpacing = 8.0;
static const CGFloat kEdgePadding = 20.0;

@interface XLBaseSheetController ()

@property (nonatomic, strong, readwrite) NSWindow *sheet;
@property (nonatomic, weak, readwrite) NSWindow *parentWindow;
@property (nonatomic, copy) XLSheetCompletion completion;

@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) NSButton *okButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *actionButton;
@property (nonatomic, assign) BOOL isFloatingPanel;

@end

@implementation XLBaseSheetController

- (instancetype)init {
    self = [super init];
    if (self) {
        _title = @"";
        _okButtonTitle = @"OK";
        _cancelButtonTitle = @"Cancel";
        _minWidth = kDefaultMinWidth;
        _minHeight = kDefaultMinHeight;
        _showsActionButton = NO;
    }
    return self;
}

#pragma mark - Sheet Building

- (void)buildSheet {
    CGFloat width = MAX(_minWidth, kDefaultMinWidth);
    CGFloat height = MAX(_minHeight, kDefaultMinHeight);

    _sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                           backing:NSBackingStoreBuffered
                                             defer:YES];
    _sheet.title = _title;
    _sheet.minSize = NSMakeSize(_minWidth, _minHeight);

    NSView *mainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    _sheet.contentView = mainView;

    // Content container (above button bar)
    _contentContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [mainView addSubview:_contentContainer];

    // Button bar
    NSView *buttonBar = [self buildButtonBar];
    buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
    [mainView addSubview:buttonBar];

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [_contentContainer.topAnchor constraintEqualToAnchor:mainView.topAnchor],
        [_contentContainer.leadingAnchor constraintEqualToAnchor:mainView.leadingAnchor],
        [_contentContainer.trailingAnchor constraintEqualToAnchor:mainView.trailingAnchor],
        [_contentContainer.bottomAnchor constraintEqualToAnchor:buttonBar.topAnchor],

        [buttonBar.leadingAnchor constraintEqualToAnchor:mainView.leadingAnchor],
        [buttonBar.trailingAnchor constraintEqualToAnchor:mainView.trailingAnchor],
        [buttonBar.bottomAnchor constraintEqualToAnchor:mainView.bottomAnchor],
        [buttonBar.heightAnchor constraintEqualToConstant:kButtonBarHeight],
    ]];

    // Add content view from subclass
    NSView *contentView = [self buildContentView];
    if (contentView) {
        contentView.translatesAutoresizingMaskIntoConstraints = NO;
        [_contentContainer addSubview:contentView];

        [NSLayoutConstraint activateConstraints:@[
            [contentView.topAnchor constraintEqualToAnchor:_contentContainer.topAnchor constant:kEdgePadding],
            [contentView.leadingAnchor constraintEqualToAnchor:_contentContainer.leadingAnchor constant:kEdgePadding],
            [contentView.trailingAnchor constraintEqualToAnchor:_contentContainer.trailingAnchor constant:-kEdgePadding],
            [contentView.bottomAnchor constraintLessThanOrEqualToAnchor:_contentContainer.bottomAnchor constant:-kEdgePadding],
        ]];
    }

    [self sheetDidLoad];
    [self updateOKButtonState];
}

- (NSView *)buildButtonBar {
    NSView *bar = [[NSView alloc] initWithFrame:NSZeroRect];

    // Cancel button (left side) - macOS convention
    _cancelButton = [NSButton buttonWithTitle:_cancelButtonTitle target:self action:@selector(cancelClicked:)];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    _cancelButton.keyEquivalent = @"\033"; // Escape
    [bar addSubview:_cancelButton];

    // OK button (right side)
    _okButton = [NSButton buttonWithTitle:_okButtonTitle target:self action:@selector(okClicked:)];
    _okButton.translatesAutoresizingMaskIntoConstraints = NO;
    _okButton.keyEquivalent = @"\r"; // Return
    _okButton.bezelStyle = NSBezelStyleRounded;
    [bar addSubview:_okButton];

    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];

    [constraints addObjectsFromArray:@[
        [_cancelButton.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:kEdgePadding],
        [_cancelButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [_okButton.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-kEdgePadding],
        [_okButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
    ]];

    // Optional action button (between cancel and ok)
    if (_showsActionButton && _actionButtonTitle) {
        _actionButton = [NSButton buttonWithTitle:_actionButtonTitle target:self action:@selector(actionClicked:)];
        _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        [bar addSubview:_actionButton];

        [constraints addObjectsFromArray:@[
            [_actionButton.trailingAnchor constraintEqualToAnchor:_okButton.leadingAnchor constant:-kButtonSpacing],
            [_actionButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        ]];
    }

    [NSLayoutConstraint activateConstraints:constraints];

    return bar;
}

#pragma mark - Presentation

- (void)presentAsSheetForWindow:(NSWindow *)parentWindow completion:(XLSheetCompletion)completion {
    _parentWindow = parentWindow;
    _completion = completion;

    [self buildSheet];

    [parentWindow beginSheet:_sheet completionHandler:^(NSModalResponse returnCode) {
        [self handleDismissWithResponse:returnCode];
    }];
}

- (void)presentAsModalWithCompletion:(XLSheetCompletion)completion {
    _completion = completion;

    [self buildSheet];

    [_sheet center];

    NSModalResponse response = [NSApp runModalForWindow:_sheet];
    [self handleDismissWithResponse:response];
}

- (void)presentAsFloatingPanelRelativeTo:(NSWindow *)parentWindow
                              completion:(XLSheetCompletion)completion {
    _parentWindow = parentWindow;
    _completion = completion;
    _isFloatingPanel = YES;

    [self buildSheet];

    // Make the window movable and non-modal
    _sheet.styleMask |= NSWindowStyleMaskClosable;
    _sheet.level = NSFloatingWindowLevel;
    _sheet.hidesOnDeactivate = NO;

    // Position to the right of the parent window
    NSRect parentFrame = parentWindow.frame;
    CGFloat panelX = NSMaxX(parentFrame) + 12;
    CGFloat panelY = NSMidY(parentFrame) - (_sheet.frame.size.height / 2);

    // If it would go off-screen, position to the left instead
    NSRect screenFrame = parentWindow.screen.visibleFrame;
    if (panelX + _sheet.frame.size.width > NSMaxX(screenFrame)) {
        panelX = NSMinX(parentFrame) - _sheet.frame.size.width - 12;
    }
    // Clamp to screen bounds
    panelY = MAX(NSMinY(screenFrame), MIN(panelY, NSMaxY(screenFrame) - _sheet.frame.size.height));
    panelX = MAX(NSMinX(screenFrame), panelX);

    [_sheet setFrameOrigin:NSMakePoint(panelX, panelY)];
    [_sheet orderFront:nil];

    // Keep the dialog alive by retaining self while the panel is visible
    objc_setAssociatedObject(_sheet, "sheetController", self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)dismissWithResponse:(NSModalResponse)response {
    [self sheetWillDismiss];

    if (_isFloatingPanel) {
        [_sheet orderOut:nil];
        objc_setAssociatedObject(_sheet, "sheetController", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self handleDismissWithResponse:response];
    } else if (_parentWindow) {
        [_parentWindow endSheet:_sheet returnCode:response];
    } else {
        [NSApp stopModalWithCode:response];
        [_sheet orderOut:nil];
    }
}

- (void)handleDismissWithResponse:(NSModalResponse)response {
    if (_completion) {
        _completion(response);
    }
}

#pragma mark - Actions

- (void)okClicked:(id)sender {
    NSString *error = [self validate];
    if (error) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Invalid Input";
        alert.informativeText = error;
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:_sheet completionHandler:nil];
        return;
    }

    [self dismissWithResponse:NSModalResponseOK];
}

- (void)cancelClicked:(id)sender {
    [self dismissWithResponse:NSModalResponseCancel];
}

- (void)actionClicked:(id)sender {
    // Subclasses override
}

#pragma mark - Validation

- (NSString *)validate {
    // Subclasses override
    return nil;
}

- (void)updateOKButtonState {
    NSString *error = [self validate];
    _okButton.enabled = (error == nil);
}

#pragma mark - Subclass Hooks

- (NSView *)buildContentView {
    // Subclasses MUST override
    return [[NSView alloc] initWithFrame:NSZeroRect];
}

- (void)sheetDidLoad {
    // Subclasses can override
}

- (void)sheetWillDismiss {
    // Subclasses can override
}

#pragma mark - Utility Methods

+ (NSStackView *)formRowWithLabel:(NSString *)label control:(NSView *)control labelWidth:(CGFloat)labelWidth {
    NSTextField *labelField = [NSTextField labelWithString:label];
    labelField.alignment = NSTextAlignmentRight;

    NSStackView *row = [NSStackView stackViewWithViews:@[labelField, control]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;
    row.alignment = NSLayoutAttributeCenterY;

    [labelField.widthAnchor constraintEqualToConstant:labelWidth].active = YES;

    return row;
}

+ (NSTextField *)createTextField {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.placeholderString = @"";
    field.bezelStyle = NSTextFieldRoundedBezel;
    return field;
}

+ (NSTextField *)createNumericField {
    NSTextField *field = [self createTextField];

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimum = @0;
    formatter.maximum = @999999;
    field.formatter = formatter;

    return field;
}

+ (NSPopUpButton *)createPopUpButton {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    return popup;
}

+ (NSButton *)createCheckboxWithTitle:(NSString *)title {
    NSButton *checkbox = [NSButton checkboxWithTitle:title target:nil action:nil];
    return checkbox;
}

+ (NSScrollView *)createTextViewWithHeight:(CGFloat)height {
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    textView.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    textView.richText = NO;
    textView.automaticQuoteSubstitutionEnabled = NO;
    textView.automaticDashSubstitutionEnabled = NO;

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.documentView = textView;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.borderType = NSBezelBorder;

    textView.minSize = NSMakeSize(0, height);
    textView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.autoresizingMask = NSViewWidthSizable;
    textView.textContainer.containerSize = NSMakeSize(scrollView.contentSize.width, FLT_MAX);
    textView.textContainer.widthTracksTextView = YES;

    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:height].active = YES;

    return scrollView;
}

+ (NSTextView *)textViewFromScrollView:(NSScrollView *)scrollView {
    return scrollView.documentView;
}

@end
