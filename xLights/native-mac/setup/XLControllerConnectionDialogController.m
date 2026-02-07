/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLControllerConnectionDialogController.h"

#pragma mark - Constants

static const CGFloat kFieldWidth       = 200.0;
static const CGFloat kLabelWidth       = 140.0;
static const CGFloat kRowHeight        = 28.0;
static const CGFloat kCheckboxWidth    = 24.0;
static const CGFloat kHPad             = 12.0;
static const CGFloat kVPad             = 6.0;

static NSArray<NSString *> *AllProtocols(void) {
    return @[@"ws2811", @"ws2801", @"TLS3001", @"LPD6803", @"LPD8806",
             @"WS2811 800kbit", @"TM1803", @"TM1804", @"TM1809", @"TM1814",
             @"UCS1903", @"UCS2903", @"UCS8903", @"UCS8903 16 Bit",
             @"GS8208", @"APA102", @"APA109", @"DMX", @"LOR", @"Renard",
             @"OpenDMX", @"GenericSerial"];
}

static NSArray<NSString *> *AllColorOrders(void) {
    return @[@"RGB", @"RBG", @"GBR", @"GRB", @"BGR", @"BRG",
             @"RGBW", @"RBGW", @"GBRW", @"GRBW", @"BGRW", @"BRGW",
             @"WRGB", @"WRBG", @"WGBR", @"WGRB", @"WBGR", @"WBRG"];
}

static NSArray<NSString *> *AllDirections(void) {
    return @[@"Forward", @"Reverse"];
}

static NSArray<NSString *> *AllSmartRemotes(void) {
    return @[@"None", @"A", @"B", @"C", @"D", @"E", @"F"];
}

#pragma mark - XLControllerConnectionResult

@implementation XLControllerConnectionResult
@end

#pragma mark - Row Helper

/// A single row in the dialog: checkbox | label | control.
@interface XLCCRow : NSObject
@property (nonatomic, strong) NSButton *checkbox;
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, strong) NSView *control; // NSPopUpButton, NSTextField, NSStepper combo, etc.
@end

@implementation XLCCRow
@end

#pragma mark - Private Interface

@interface XLControllerConnectionDialogController ()

@property (nonatomic, copy) XLControllerConnectionCompletion completion;

// Row containers
@property (nonatomic, strong) XLCCRow *protocolRow;
@property (nonatomic, strong) XLCCRow *portRow;
@property (nonatomic, strong) XLCCRow *directionRow;
@property (nonatomic, strong) XLCCRow *colorOrderRow;
@property (nonatomic, strong) XLCCRow *startNullRow;
@property (nonatomic, strong) XLCCRow *endNullRow;
@property (nonatomic, strong) XLCCRow *brightnessRow;
@property (nonatomic, strong) XLCCRow *gammaRow;
@property (nonatomic, strong) XLCCRow *groupCountRow;
@property (nonatomic, strong) XLCCRow *smartRemoteRow;

// Buttons
@property (nonatomic, strong) NSButton *applyButton;
@property (nonatomic, strong) NSButton *cancelButton;

@end

@implementation XLControllerConnectionDialogController

#pragma mark - Lifecycle

- (instancetype)initWithModelCount:(NSUInteger)count {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 440, 420)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:YES];
    window.title = [NSString stringWithFormat:@"Edit Connection for %lu model%s",
                    (unsigned long)count, count == 1 ? "" : "s"];

    self = [super initWithWindow:window];
    if (self) {
        _modelCount = count;
        [self buildUI];
    }
    return self;
}

#pragma mark - UI Construction

- (void)buildUI {
    NSView *content = self.window.contentView;
    content.wantsLayer = YES;

    // Create all rows
    _protocolRow     = [self makePopUpRow:@"Protocol"       items:AllProtocols()];
    _portRow         = [self makeStepperRow:@"Port"          minVal:1    maxVal:100  defaultVal:1];
    _smartRemoteRow  = [self makePopUpRow:@"Smart Remote"    items:AllSmartRemotes()];
    _directionRow    = [self makePopUpRow:@"Direction"       items:AllDirections()];
    _colorOrderRow   = [self makePopUpRow:@"Color Order"     items:AllColorOrders()];
    _startNullRow    = [self makeStepperRow:@"Start Null Pixels" minVal:0 maxVal:100 defaultVal:0];
    _endNullRow      = [self makeStepperRow:@"End Null Pixels"   minVal:0 maxVal:100 defaultVal:0];
    _brightnessRow   = [self makeStepperRow:@"Brightness"    minVal:0    maxVal:100  defaultVal:100];
    _gammaRow        = [self makeDoubleRow:@"Gamma"          minVal:0.1  maxVal:5.0  defaultVal:1.0 increment:0.1];
    _groupCountRow   = [self makeStepperRow:@"Group Count"   minVal:1    maxVal:100  defaultVal:1];

    NSArray<XLCCRow *> *rows = @[
        _protocolRow, _portRow, _smartRemoteRow, _directionRow,
        _colorOrderRow, _startNullRow, _endNullRow,
        _brightnessRow, _gammaRow, _groupCountRow
    ];

    // Layout rows vertically
    CGFloat y = kVPad;

    // Buttons at bottom
    _cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelClicked:)];
    _cancelButton.keyEquivalent = @"\033"; // Escape key
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_cancelButton];

    _applyButton = [NSButton buttonWithTitle:@"Apply" target:self action:@selector(applyClicked:)];
    _applyButton.keyEquivalent = @"\r"; // Enter key
    _applyButton.bezelStyle = NSBezelStyleRounded;
    _applyButton.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 11.0, *)) {
        _applyButton.hasDestructiveAction = NO;
    }
    [content addSubview:_applyButton];

    [NSLayoutConstraint activateConstraints:@[
        [_applyButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-kHPad],
        [_applyButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-kVPad],
        [_applyButton.widthAnchor constraintGreaterThanOrEqualToConstant:80],

        [_cancelButton.trailingAnchor constraintEqualToAnchor:_applyButton.leadingAnchor constant:-8],
        [_cancelButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-kVPad],
        [_cancelButton.widthAnchor constraintGreaterThanOrEqualToConstant:80],
    ]];

    y += 40; // Button area height

    // Separator
    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:separator];
    [NSLayoutConstraint activateConstraints:@[
        [separator.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:kHPad],
        [separator.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-kHPad],
        [separator.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-(y)],
        [separator.heightAnchor constraintEqualToConstant:1],
    ]];
    y += kVPad;

    // Place rows from bottom to top (since AppKit origin is bottom-left)
    for (NSInteger i = (NSInteger)rows.count - 1; i >= 0; i--) {
        XLCCRow *row = rows[i];
        [self addRow:row toView:content atY:y];
        y += kRowHeight + kVPad;
    }

    // Title label at top
    y += kVPad;
    NSTextField *titleLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Set properties for %lu model%s.\nOnly checked fields will be applied.",
         (unsigned long)_modelCount, _modelCount == 1 ? "" : "s"]];
    titleLabel.font = [NSFont systemFontOfSize:12];
    titleLabel.textColor = [NSColor secondaryLabelColor];
    titleLabel.maximumNumberOfLines = 2;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:kHPad],
        [titleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-kHPad],
        [titleLabel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-(y)],
    ]];

    y += 40;

    // Resize window to fit
    NSRect frame = self.window.frame;
    frame.size.height = y + kVPad;
    [self.window setFrame:frame display:NO];
}

- (void)addRow:(XLCCRow *)row toView:(NSView *)parent atY:(CGFloat)y {
    row.checkbox.translatesAutoresizingMaskIntoConstraints = NO;
    row.label.translatesAutoresizingMaskIntoConstraints = NO;
    row.control.translatesAutoresizingMaskIntoConstraints = NO;

    [parent addSubview:row.checkbox];
    [parent addSubview:row.label];
    [parent addSubview:row.control];

    [NSLayoutConstraint activateConstraints:@[
        [row.checkbox.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:kHPad],
        [row.checkbox.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor constant:-(y)],
        [row.checkbox.widthAnchor constraintEqualToConstant:kCheckboxWidth],
        [row.checkbox.heightAnchor constraintEqualToConstant:kRowHeight],

        [row.label.leadingAnchor constraintEqualToAnchor:row.checkbox.trailingAnchor constant:4],
        [row.label.centerYAnchor constraintEqualToAnchor:row.checkbox.centerYAnchor],
        [row.label.widthAnchor constraintEqualToConstant:kLabelWidth],

        [row.control.leadingAnchor constraintEqualToAnchor:row.label.trailingAnchor constant:4],
        [row.control.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-kHPad],
        [row.control.centerYAnchor constraintEqualToAnchor:row.checkbox.centerYAnchor],
        [row.control.heightAnchor constraintEqualToConstant:kRowHeight],
    ]];
}

#pragma mark - Row Factory Methods

- (XLCCRow *)makePopUpRow:(NSString *)labelText items:(NSArray<NSString *> *)items {
    XLCCRow *row = [[XLCCRow alloc] init];

    row.checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxToggled:)];
    row.checkbox.state = NSControlStateValueOff;

    row.label = [NSTextField labelWithString:labelText];
    row.label.font = [NSFont systemFontOfSize:12];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [popup addItemsWithTitles:items];
    popup.enabled = NO;
    row.control = popup;

    return row;
}

- (XLCCRow *)makeStepperRow:(NSString *)labelText minVal:(NSInteger)minVal maxVal:(NSInteger)maxVal defaultVal:(NSInteger)defaultVal {
    XLCCRow *row = [[XLCCRow alloc] init];

    row.checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxToggled:)];
    row.checkbox.state = NSControlStateValueOff;

    row.label = [NSTextField labelWithString:labelText];
    row.label.font = [NSFont systemFontOfSize:12];

    // Container with text field + stepper
    NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.integerValue = defaultVal;
    field.editable = YES;
    field.bordered = YES;
    field.bezeled = YES;
    field.bezelStyle = NSTextFieldSquareBezel;
    field.enabled = NO;
    field.tag = 100;
    field.translatesAutoresizingMaskIntoConstraints = NO;

    NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    stepper.minValue = minVal;
    stepper.maxValue = maxVal;
    stepper.integerValue = defaultVal;
    stepper.increment = 1;
    stepper.valueWraps = NO;
    stepper.enabled = NO;
    stepper.target = self;
    stepper.action = @selector(stepperChanged:);
    stepper.tag = 101;
    stepper.translatesAutoresizingMaskIntoConstraints = NO;

    [container addSubview:field];
    [container addSubview:stepper];

    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [field.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [field.widthAnchor constraintGreaterThanOrEqualToConstant:60],

        [stepper.leadingAnchor constraintEqualToAnchor:field.trailingAnchor constant:4],
        [stepper.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
    ]];

    row.control = container;
    return row;
}

- (XLCCRow *)makeDoubleRow:(NSString *)labelText minVal:(double)minVal maxVal:(double)maxVal defaultVal:(double)defaultVal increment:(double)increment {
    XLCCRow *row = [[XLCCRow alloc] init];

    row.checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxToggled:)];
    row.checkbox.state = NSControlStateValueOff;

    row.label = [NSTextField labelWithString:labelText];
    row.label.font = [NSFont systemFontOfSize:12];

    // Container with text field + stepper for double values
    NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.doubleValue = defaultVal;
    field.editable = YES;
    field.bordered = YES;
    field.bezeled = YES;
    field.bezelStyle = NSTextFieldSquareBezel;
    field.enabled = NO;
    field.tag = 100;

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 1;
    formatter.maximumFractionDigits = 1;
    formatter.minimum = @(minVal);
    formatter.maximum = @(maxVal);
    field.formatter = formatter;
    field.translatesAutoresizingMaskIntoConstraints = NO;

    NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    stepper.minValue = minVal;
    stepper.maxValue = maxVal;
    stepper.doubleValue = defaultVal;
    stepper.increment = increment;
    stepper.valueWraps = NO;
    stepper.enabled = NO;
    stepper.target = self;
    stepper.action = @selector(doubleStepperChanged:);
    stepper.tag = 102;
    stepper.translatesAutoresizingMaskIntoConstraints = NO;

    [container addSubview:field];
    [container addSubview:stepper];

    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [field.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [field.widthAnchor constraintGreaterThanOrEqualToConstant:60],

        [stepper.leadingAnchor constraintEqualToAnchor:field.trailingAnchor constant:4],
        [stepper.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
    ]];

    row.control = container;
    return row;
}

#pragma mark - Checkbox / Stepper Actions

- (void)checkboxToggled:(NSButton *)sender {
    NSArray<XLCCRow *> *rows = @[
        _protocolRow, _portRow, _smartRemoteRow, _directionRow,
        _colorOrderRow, _startNullRow, _endNullRow,
        _brightnessRow, _gammaRow, _groupCountRow
    ];

    for (XLCCRow *row in rows) {
        if (row.checkbox == sender) {
            BOOL enabled = (sender.state == NSControlStateValueOn);
            [self setControlEnabled:enabled inRow:row];
            break;
        }
    }
}

- (void)setControlEnabled:(BOOL)enabled inRow:(XLCCRow *)row {
    if ([row.control isKindOfClass:[NSPopUpButton class]]) {
        ((NSPopUpButton *)row.control).enabled = enabled;
    } else {
        // Container with text field + stepper
        for (NSView *sub in row.control.subviews) {
            if ([sub isKindOfClass:[NSTextField class]]) {
                ((NSTextField *)sub).enabled = enabled;
            } else if ([sub isKindOfClass:[NSStepper class]]) {
                ((NSStepper *)sub).enabled = enabled;
            }
        }
    }
}

- (void)stepperChanged:(NSStepper *)sender {
    // Find the text field sibling and sync value
    NSView *container = sender.superview;
    for (NSView *sub in container.subviews) {
        if ([sub isKindOfClass:[NSTextField class]] && sub.tag == 100) {
            ((NSTextField *)sub).integerValue = sender.integerValue;
            break;
        }
    }
}

- (void)doubleStepperChanged:(NSStepper *)sender {
    NSView *container = sender.superview;
    for (NSView *sub in container.subviews) {
        if ([sub isKindOfClass:[NSTextField class]] && sub.tag == 100) {
            ((NSTextField *)sub).doubleValue = sender.doubleValue;
            break;
        }
    }
}

#pragma mark - Button Actions

- (void)applyClicked:(id)sender {
    XLControllerConnectionResult *result = [[XLControllerConnectionResult alloc] init];

    // Protocol
    if (_protocolRow.checkbox.state == NSControlStateValueOn) {
        result.applyProtocol = YES;
        result.protocol = ((NSPopUpButton *)_protocolRow.control).titleOfSelectedItem;
    }

    // Port
    if (_portRow.checkbox.state == NSControlStateValueOn) {
        result.applyPort = YES;
        result.port = [self integerValueFromRow:_portRow];
    }

    // Smart Remote
    if (_smartRemoteRow.checkbox.state == NSControlStateValueOn) {
        result.applySmartRemote = YES;
        result.smartRemote = ((NSPopUpButton *)_smartRemoteRow.control).indexOfSelectedItem;
    }

    // Direction
    if (_directionRow.checkbox.state == NSControlStateValueOn) {
        result.applyDirection = YES;
        result.direction = ((NSPopUpButton *)_directionRow.control).indexOfSelectedItem;
    }

    // Color Order
    if (_colorOrderRow.checkbox.state == NSControlStateValueOn) {
        result.applyColorOrder = YES;
        result.colorOrder = ((NSPopUpButton *)_colorOrderRow.control).titleOfSelectedItem;
    }

    // Start Null Pixels
    if (_startNullRow.checkbox.state == NSControlStateValueOn) {
        result.applyStartNullNodes = YES;
        result.startNullNodes = [self integerValueFromRow:_startNullRow];
    }

    // End Null Pixels
    if (_endNullRow.checkbox.state == NSControlStateValueOn) {
        result.applyEndNullNodes = YES;
        result.endNullNodes = [self integerValueFromRow:_endNullRow];
    }

    // Brightness
    if (_brightnessRow.checkbox.state == NSControlStateValueOn) {
        result.applyBrightness = YES;
        result.brightness = [self integerValueFromRow:_brightnessRow];
    }

    // Gamma
    if (_gammaRow.checkbox.state == NSControlStateValueOn) {
        result.applyGamma = YES;
        result.gamma = [self doubleValueFromRow:_gammaRow];
    }

    // Group Count
    if (_groupCountRow.checkbox.state == NSControlStateValueOn) {
        result.applyGroupCount = YES;
        result.groupCount = [self integerValueFromRow:_groupCountRow];
    }

    [self dismissWithResult:result];
}

- (void)cancelClicked:(id)sender {
    [self dismissWithResult:nil];
}

- (void)dismissWithResult:(XLControllerConnectionResult *)result {
    NSWindow *sheet = self.window;
    NSWindow *parent = sheet.sheetParent;
    if (parent) {
        [parent endSheet:sheet returnCode:(result ? NSModalResponseOK : NSModalResponseCancel)];
    } else {
        [sheet close];
    }
    if (_completion) {
        _completion(result);
        _completion = nil;
    }
}

#pragma mark - Value Extraction Helpers

- (NSInteger)integerValueFromRow:(XLCCRow *)row {
    for (NSView *sub in row.control.subviews) {
        if ([sub isKindOfClass:[NSTextField class]] && sub.tag == 100) {
            return ((NSTextField *)sub).integerValue;
        }
    }
    return 0;
}

- (double)doubleValueFromRow:(XLCCRow *)row {
    for (NSView *sub in row.control.subviews) {
        if ([sub isKindOfClass:[NSTextField class]] && sub.tag == 100) {
            return ((NSTextField *)sub).doubleValue;
        }
    }
    return 0.0;
}

#pragma mark - Presentation

- (void)showAsSheetForWindow:(NSWindow *)parentWindow
                  completion:(XLControllerConnectionCompletion)completion {
    _completion = [completion copy];
    [parentWindow beginSheet:self.window completionHandler:^(NSModalResponse returnCode) {
        // Sheet dismissed - completion already called in dismissWithResult:
    }];
}

@end
