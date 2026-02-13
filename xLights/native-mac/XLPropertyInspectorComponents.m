/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLPropertyInspectorComponents.h"

#pragma mark - XLPropertySectionHeader

@implementation XLPropertySectionHeader

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _expanded = YES;

        _disclosureButton = [NSButton buttonWithTitle:@""
                                               target:self
                                               action:@selector(toggleDisclosure:)];
        _disclosureButton.translatesAutoresizingMaskIntoConstraints = NO;
        _disclosureButton.bezelStyle = NSBezelStyleDisclosure;
        [_disclosureButton setButtonType:NSButtonTypeOnOff];
        _disclosureButton.state = NSControlStateValueOn;
        [self addSubview:_disclosureButton];

        _titleLabel = [NSTextField labelWithString:title];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont boldSystemFontOfSize:11];
        _titleLabel.textColor = [NSColor secondaryLabelColor];
        [self addSubview:_titleLabel];

        NSClickGestureRecognizer *click = [[NSClickGestureRecognizer alloc]
                                            initWithTarget:self
                                            action:@selector(headerClicked:)];
        [self addGestureRecognizer:click];

        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:24],
            [_disclosureButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
            [_disclosureButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_disclosureButton.trailingAnchor constant:2],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)setContentView:(NSView *)contentView {
    _contentView = contentView;
}

- (void)toggleDisclosure:(id)sender {
    _expanded = !_expanded;
    _disclosureButton.state = _expanded ? NSControlStateValueOn : NSControlStateValueOff;
    _contentView.hidden = !_expanded;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"XLPropertySectionDisclosureDidChange"
                      object:self];
}

- (void)headerClicked:(NSClickGestureRecognizer *)recognizer {
    [self toggleDisclosure:nil];
}

@end

#pragma mark - XLPropertyRowBuilder

@implementation XLPropertyRowBuilder

+ (NSView *)rowWithLabel:(NSString *)label control:(NSView *)control {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *lbl = [NSTextField labelWithString:label];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.font = [NSFont systemFontOfSize:11];
    lbl.textColor = [NSColor tertiaryLabelColor];
    lbl.alignment = NSTextAlignmentRight;
    lbl.lineBreakMode = NSLineBreakByTruncatingTail;
    [lbl setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addSubview:lbl];

    control.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:control];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:22],
        [lbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:8],
        [lbl.widthAnchor constraintEqualToConstant:80],
        [lbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [control.leadingAnchor constraintEqualToAnchor:lbl.trailingAnchor constant:6],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    return row;
}

+ (NSTextField *)editableTextField {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.bordered = YES;
    field.bezeled = YES;
    field.bezelStyle = NSTextFieldRoundedBezel;
    field.editable = YES;
    field.selectable = YES;
    field.drawsBackground = YES;
    field.font = [NSFont systemFontOfSize:11];
    field.controlSize = NSControlSizeSmall;
    [field.heightAnchor constraintEqualToConstant:20].active = YES;
    return field;
}

+ (NSTextField *)readOnlyTextField {
    NSTextField *field = [self editableTextField];
    field.editable = NO;
    field.selectable = YES;
    field.textColor = [NSColor secondaryLabelColor];
    return field;
}

+ (NSTextField *)numericTextField {
    NSTextField *field = [self editableTextField];
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.allowsFloats = YES;
    field.formatter = formatter;
    return field;
}

+ (NSSlider *)sliderWithMin:(double)min max:(double)max value:(double)value {
    NSSlider *slider = [NSSlider sliderWithValue:value minValue:min maxValue:max
                                          target:nil action:nil];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.controlSize = NSControlSizeSmall;
    [slider.heightAnchor constraintEqualToConstant:20].active = YES;
    return slider;
}

+ (NSPopUpButton *)popUpWithItems:(NSArray<NSString *> *)items selectedTitle:(NSString *)selected {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.translatesAutoresizingMaskIntoConstraints = NO;
    popup.controlSize = NSControlSizeSmall;
    popup.font = [NSFont systemFontOfSize:11];
    [popup addItemsWithTitles:items];
    if (selected) {
        [popup selectItemWithTitle:selected];
    }
    [popup.heightAnchor constraintEqualToConstant:20].active = YES;
    return popup;
}

+ (NSButton *)checkbox {
    NSButton *btn = [NSButton checkboxWithTitle:@"" target:nil action:nil];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.controlSize = NSControlSizeSmall;
    return btn;
}

@end
