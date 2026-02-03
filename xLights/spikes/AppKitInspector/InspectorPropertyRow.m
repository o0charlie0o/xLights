#import "InspectorPropertyRow.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const CGFloat kRowHeight = 24.0;
static const CGFloat kLabelWidth = 110.0;
static const CGFloat kSpacing = 6.0;
static const CGFloat kSliderFieldWidth = 52.0;

@interface InspectorPropertyRow () <NSTextFieldDelegate>

@property (nonatomic, strong) NSTextField *labelField;
@property (nonatomic, strong) NSTextField *textField;
@property (nonatomic, strong) NSSlider *slider;
@property (nonatomic, strong) NSPopUpButton *popUpButton;
@property (nonatomic, strong) NSSwitch *toggleSwitch;
@property (nonatomic, strong) NSColorWell *colorWell;
@property (nonatomic, strong) NSButton *browseButton;

@end

@implementation InspectorPropertyRow

+ (CGFloat)labelWidth {
    return kLabelWidth;
}

- (instancetype)initWithProperty:(InspectorProperty *)property {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _property = property;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        [self buildLabel];

        switch (property.type) {
            case InspectorPropertyTypeText:
                [self buildTextField:NO];
                break;
            case InspectorPropertyTypeNumber:
                [self buildTextField:YES];
                break;
            case InspectorPropertyTypeSlider:
                [self buildSliderRow];
                break;
            case InspectorPropertyTypeChoice:
                [self buildChoiceRow];
                break;
            case InspectorPropertyTypeToggle:
                [self buildToggleRow];
                break;
            case InspectorPropertyTypeColor:
                [self buildColorRow];
                break;
            case InspectorPropertyTypePath:
                [self buildPathRow];
                break;
        }

        [self setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                         forOrientation:NSLayoutConstraintOrientationVertical];

        NSLayoutConstraint *height = [self.heightAnchor constraintGreaterThanOrEqualToConstant:kRowHeight];
        height.priority = NSLayoutPriorityDefaultHigh;
        height.active = YES;
    }
    return self;
}

#pragma mark - Label

- (void)buildLabel {
    _labelField = [NSTextField labelWithString:_property.label];
    _labelField.translatesAutoresizingMaskIntoConstraints = NO;
    _labelField.font = [NSFont systemFontOfSize:11.0];
    _labelField.textColor = [NSColor secondaryLabelColor];
    _labelField.alignment = NSTextAlignmentRight;
    _labelField.lineBreakMode = NSLineBreakByTruncatingTail;
    [_labelField setContentHuggingPriority:NSLayoutPriorityRequired
                            forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_labelField];

    [NSLayoutConstraint activateConstraints:@[
        [_labelField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_labelField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_labelField.widthAnchor constraintEqualToConstant:kLabelWidth],
    ]];
}

#pragma mark - Text Field

- (void)buildTextField:(BOOL)numericOnly {
    _textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _textField.translatesAutoresizingMaskIntoConstraints = NO;
    _textField.font = [NSFont systemFontOfSize:11.0];
    _textField.controlSize = NSControlSizeSmall;
    _textField.delegate = self;
    _textField.lineBreakMode = NSLineBreakByTruncatingTail;
    [_textField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                           forOrientation:NSLayoutConstraintOrientationHorizontal];

    if (numericOnly) {
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        _textField.formatter = formatter;
        _textField.stringValue = [_property.value description] ?: @"0";
    } else {
        _textField.stringValue = _property.value ?: @"";
    }

    [self addSubview:_textField];

    [NSLayoutConstraint activateConstraints:@[
        [_textField.leadingAnchor constraintEqualToAnchor:_labelField.trailingAnchor constant:kSpacing],
        [_textField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_textField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
}

#pragma mark - Slider + Text

- (void)buildSliderRow {
    _slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    _slider.controlSize = NSControlSizeSmall;
    _slider.minValue = _property.minValue;
    _slider.maxValue = _property.maxValue;
    _slider.doubleValue = [_property.value doubleValue];
    _slider.continuous = YES;
    _slider.target = self;
    _slider.action = @selector(sliderChanged:);
    [_slider setContentHuggingPriority:NSLayoutPriorityDefaultLow
                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_slider];

    _textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _textField.translatesAutoresizingMaskIntoConstraints = NO;
    _textField.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightRegular];
    _textField.controlSize = NSControlSizeSmall;
    _textField.alignment = NSTextAlignmentRight;
    _textField.delegate = self;

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.maximumFractionDigits = 1;
    formatter.minimum = @(_property.minValue);
    formatter.maximum = @(_property.maxValue);
    _textField.formatter = formatter;
    _textField.stringValue = [NSString stringWithFormat:@"%.1f", [_property.value doubleValue]];

    [self addSubview:_textField];

    [NSLayoutConstraint activateConstraints:@[
        [_slider.leadingAnchor constraintEqualToAnchor:_labelField.trailingAnchor constant:kSpacing],
        [_slider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_textField.leadingAnchor constraintEqualToAnchor:_slider.trailingAnchor constant:kSpacing],
        [_textField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_textField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_textField.widthAnchor constraintEqualToConstant:kSliderFieldWidth],
    ]];
}

- (void)sliderChanged:(NSSlider *)sender {
    double val = sender.doubleValue;
    _textField.stringValue = [NSString stringWithFormat:@"%.1f", val];
    _property.value = @(val);
    if (_property.onValueChanged) {
        _property.onValueChanged(_property);
    }
}

#pragma mark - Choice (Popup)

- (void)buildChoiceRow {
    _popUpButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _popUpButton.translatesAutoresizingMaskIntoConstraints = NO;
    _popUpButton.controlSize = NSControlSizeSmall;
    _popUpButton.font = [NSFont systemFontOfSize:11.0];
    [_popUpButton addItemsWithTitles:_property.choices ?: @[]];
    [_popUpButton selectItemAtIndex:[_property.value integerValue]];
    _popUpButton.target = self;
    _popUpButton.action = @selector(choiceChanged:);
    [_popUpButton setContentHuggingPriority:NSLayoutPriorityDefaultLow
                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_popUpButton];

    [NSLayoutConstraint activateConstraints:@[
        [_popUpButton.leadingAnchor constraintEqualToAnchor:_labelField.trailingAnchor constant:kSpacing],
        [_popUpButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_popUpButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
}

- (void)choiceChanged:(NSPopUpButton *)sender {
    _property.value = @(sender.indexOfSelectedItem);
    if (_property.onValueChanged) {
        _property.onValueChanged(_property);
    }
}

#pragma mark - Toggle (Switch)

- (void)buildToggleRow {
    _toggleSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    _toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    _toggleSwitch.controlSize = NSControlSizeSmall;
    _toggleSwitch.state = [_property.value boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    _toggleSwitch.target = self;
    _toggleSwitch.action = @selector(toggleChanged:);
    [self addSubview:_toggleSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [_toggleSwitch.leadingAnchor constraintEqualToAnchor:_labelField.trailingAnchor constant:kSpacing],
        [_toggleSwitch.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
}

- (void)toggleChanged:(NSSwitch *)sender {
    _property.value = @(sender.state == NSControlStateValueOn);
    if (_property.onValueChanged) {
        _property.onValueChanged(_property);
    }
}

#pragma mark - Color Well

- (void)buildColorRow {
    _colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 22)];
    _colorWell.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(macOS 13.0, *)) {
        _colorWell.colorWellStyle = NSColorWellStyleMinimal;
    }
    _colorWell.color = _property.value ?: [NSColor whiteColor];
    _colorWell.target = self;
    _colorWell.action = @selector(colorChanged:);
    [self addSubview:_colorWell];

    [NSLayoutConstraint activateConstraints:@[
        [_colorWell.leadingAnchor constraintEqualToAnchor:_labelField.trailingAnchor constant:kSpacing],
        [_colorWell.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_colorWell.widthAnchor constraintEqualToConstant:44],
        [_colorWell.heightAnchor constraintEqualToConstant:22],
    ]];
}

- (void)colorChanged:(NSColorWell *)sender {
    _property.value = sender.color;
    if (_property.onValueChanged) {
        _property.onValueChanged(_property);
    }
}

#pragma mark - Path Picker

- (void)buildPathRow {
    _textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _textField.translatesAutoresizingMaskIntoConstraints = NO;
    _textField.font = [NSFont systemFontOfSize:11.0];
    _textField.controlSize = NSControlSizeSmall;
    _textField.stringValue = _property.value ?: @"";
    _textField.delegate = self;
    _textField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _textField.placeholderString = @"No file selected";
    [_textField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_textField];

    _browseButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    _browseButton.translatesAutoresizingMaskIntoConstraints = NO;
    _browseButton.title = @"...";
    _browseButton.controlSize = NSControlSizeSmall;
    _browseButton.bezelStyle = NSBezelStyleRecessed;
    _browseButton.font = [NSFont systemFontOfSize:10.0];
    _browseButton.target = self;
    _browseButton.action = @selector(browseClicked:);
    [_browseButton setContentHuggingPriority:NSLayoutPriorityRequired
                              forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_browseButton];

    [NSLayoutConstraint activateConstraints:@[
        [_textField.leadingAnchor constraintEqualToAnchor:_labelField.trailingAnchor constant:kSpacing],
        [_textField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_browseButton.leadingAnchor constraintEqualToAnchor:_textField.trailingAnchor constant:4],
        [_browseButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_browseButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_browseButton.widthAnchor constraintEqualToConstant:30],
    ]];
}

- (void)browseClicked:(NSButton *)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    if (_property.allowedFileTypes.count > 0) {
        NSMutableArray<UTType *> *types = [NSMutableArray array];
        for (NSString *ext in _property.allowedFileTypes) {
            UTType *type = [UTType typeWithFilenameExtension:ext];
            if (type) {
                [types addObject:type];
            }
        }
        if (types.count > 0) {
            panel.allowedContentTypes = types;
        }
    }
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            self.textField.stringValue = panel.URL.path;
            self.property.value = panel.URL.path;
            if (self.property.onValueChanged) {
                self.property.onValueChanged(self.property);
            }
        }
    }];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *field = notification.object;
    switch (_property.type) {
        case InspectorPropertyTypeText:
        case InspectorPropertyTypePath:
            _property.value = field.stringValue;
            break;
        case InspectorPropertyTypeNumber:
            _property.value = @(field.doubleValue);
            break;
        case InspectorPropertyTypeSlider: {
            double val = field.doubleValue;
            val = MAX(_property.minValue, MIN(_property.maxValue, val));
            _slider.doubleValue = val;
            _property.value = @(val);
            field.stringValue = [NSString stringWithFormat:@"%.1f", val];
            break;
        }
        default:
            break;
    }
    if (_property.onValueChanged) {
        _property.onValueChanged(_property);
    }
}

#pragma mark - Refresh

- (void)refreshFromModel {
    switch (_property.type) {
        case InspectorPropertyTypeText:
            _textField.stringValue = _property.value ?: @"";
            break;
        case InspectorPropertyTypeNumber:
            _textField.stringValue = [_property.value description] ?: @"0";
            break;
        case InspectorPropertyTypeSlider:
            _slider.doubleValue = [_property.value doubleValue];
            _textField.stringValue = [NSString stringWithFormat:@"%.1f", [_property.value doubleValue]];
            break;
        case InspectorPropertyTypeChoice:
            [_popUpButton selectItemAtIndex:[_property.value integerValue]];
            break;
        case InspectorPropertyTypeToggle:
            _toggleSwitch.state = [_property.value boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
            break;
        case InspectorPropertyTypeColor:
            _colorWell.color = _property.value ?: [NSColor whiteColor];
            break;
        case InspectorPropertyTypePath:
            _textField.stringValue = _property.value ?: @"";
            break;
    }
}

@end
