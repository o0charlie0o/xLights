/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLEffectPanelView.h"
#import "XLEngineBridge.h"

// Control tag encoding: parameter index in lower 16 bits, control type in upper 16 bits
typedef NS_ENUM(NSInteger, XLControlType) {
    XLControlTypeSlider = 0,
    XLControlTypeTextField = 1,
    XLControlTypeSwitch = 2,
    XLControlTypePopup = 3,
    XLControlTypeColorWell = 4,
    XLControlTypeFilePicker = 5,
    XLControlTypeValueCurve = 6,
    XLControlTypeLock = 7
};

static NSInteger EncodeTag(NSInteger paramIndex, XLControlType type) {
    return (paramIndex & 0xFFFF) | ((NSInteger)type << 16);
}

static void DecodeTag(NSInteger tag, NSInteger *paramIndex, XLControlType *type) {
    *paramIndex = tag & 0xFFFF;
    *type = (XLControlType)(tag >> 16);
}

@interface XLEffectPanelView () <NSTextFieldDelegate>

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSStackView *mainStack;
@property (nonatomic, copy) NSString *currentEffectName;
@property (nonatomic, assign) const XLEffectPanelDef *currentDef;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSControl *> *controlMap;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lockedParams;

@end

@implementation XLEffectPanelView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setupView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setupView];
    }
    return self;
}

- (void)setupView {
    _controlMap = [NSMutableDictionary dictionary];
    _lockedParams = [NSMutableDictionary dictionary];
    _effectId = 0;

    // Create scroll view
    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers = YES;
    _scrollView.borderType = NSNoBorder;
    _scrollView.drawsBackground = NO;
    [self addSubview:_scrollView];

    // Create main stack view
    _mainStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    _mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _mainStack.alignment = NSLayoutAttributeLeading;
    _mainStack.spacing = 8;
    _mainStack.edgeInsets = NSEdgeInsetsMake(8, 8, 8, 8);

    // Embed stack in scroll view
    _scrollView.documentView = _mainStack;

    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [_mainStack.leadingAnchor constraintEqualToAnchor:_scrollView.contentView.leadingAnchor],
        [_mainStack.trailingAnchor constraintEqualToAnchor:_scrollView.contentView.trailingAnchor],
        [_mainStack.topAnchor constraintEqualToAnchor:_scrollView.contentView.topAnchor],
    ]];

    // Show placeholder
    [self showPlaceholder:@"Select an effect"];
}

#pragma mark - Public Methods

- (void)loadEffectPanel:(NSString *)effectName {
    if (!effectName) {
        [self clearPanel];
        return;
    }

    const XLEffectPanelDef *def = [[XLEffectPanelRegistry sharedRegistry] definitionForEffect:effectName];
    if (!def) {
        [self showPlaceholder:[NSString stringWithFormat:@"Unknown effect: %@", effectName]];
        return;
    }

    _currentEffectName = effectName;
    _currentDef = def;
    [_controlMap removeAllObjects];

    // Clear existing views
    for (NSView *view in [_mainStack.arrangedSubviews copy]) {
        [_mainStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    // Check if custom panel needed
    if (def->needsCustomPanel && def->customPanelClass) {
        [self showPlaceholder:[NSString stringWithFormat:@"Custom panel: %s", def->customPanelClass]];
        return;
    }

    // Build parameter groups
    [self buildParameterGroups];

    // Refresh values if we have an effect ID
    if (_effectId > 0) {
        [self refreshFromEffect];
    }
}

- (void)refreshFromEffect {
    if (_effectId == 0 || !_currentDef) return;

    // Query engine bridge for current parameter values
    if (_engineBridge) {
        [self loadValuesFromEngine];
    } else {
        // Fall back to defaults if no engine bridge
        [self setDefaultValues];
    }
}

- (void)loadValuesFromEngine {
    if (!_engineBridge || _effectId == 0 || !_currentDef) return;

    // Iterate through parameters and query their values
    for (int p = 0; _currentDef->parameters[p].key != NULL; p++) {
        const XLParameterDef *param = &_currentDef->parameters[p];
        NSString *key = [NSString stringWithUTF8String:param->key];
        NSControl *control = _controlMap[key];

        if (!control) continue;

        // Get current value from engine
        NSString *value = [_engineBridge getEffectParameter:_effectId key:key];
        if (!value || value.length == 0) {
            // Use default if no value set
            continue;
        }

        // Update control based on type
        switch (param->type) {
            case XLParameterTypeInt:
            case XLParameterTypeFloat:
                if ([control isKindOfClass:[NSSlider class]]) {
                    NSSlider *slider = (NSSlider *)control;
                    double numValue = [value doubleValue];
                    if (param->type == XLParameterTypeFloat && param->divisor > 1) {
                        slider.doubleValue = numValue * param->divisor;
                    } else {
                        slider.doubleValue = numValue;
                    }

                    // Update linked text field
                    NSTextField *textField = (NSTextField *)_controlMap[[key stringByAppendingString:@"_text"]];
                    if (textField) {
                        if (param->type == XLParameterTypeFloat && param->divisor > 1) {
                            textField.stringValue = [NSString stringWithFormat:@"%.1f", numValue];
                        } else {
                            textField.integerValue = (NSInteger)numValue;
                        }
                    }
                }
                break;

            case XLParameterTypeBool:
                if ([control isKindOfClass:[NSSwitch class]]) {
                    ((NSSwitch *)control).state = [value boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
                }
                break;

            case XLParameterTypeChoice:
                if ([control isKindOfClass:[NSPopUpButton class]]) {
                    NSPopUpButton *popup = (NSPopUpButton *)control;
                    // Try to select by title first
                    if ([popup itemWithTitle:value]) {
                        [popup selectItemWithTitle:value];
                    } else {
                        // Try as index
                        NSInteger idx = [value integerValue];
                        if (idx >= 0 && idx < popup.numberOfItems) {
                            [popup selectItemAtIndex:idx];
                        }
                    }
                }
                break;

            case XLParameterTypeColor:
                if ([control isKindOfClass:[NSColorWell class]]) {
                    // Parse hex color string
                    NSColor *color = [self colorFromHexString:value];
                    if (color) {
                        ((NSColorWell *)control).color = color;
                    }
                }
                break;

            case XLParameterTypeString:
            case XLParameterTypeFile:
                if ([control isKindOfClass:[NSTextField class]]) {
                    ((NSTextField *)control).stringValue = value;
                }
                break;

            default:
                break;
        }
    }
}

- (NSColor *)colorFromHexString:(NSString *)hexString {
    if (!hexString || hexString.length < 6) return nil;

    // Remove # prefix if present
    if ([hexString hasPrefix:@"#"]) {
        hexString = [hexString substringFromIndex:1];
    }

    if (hexString.length < 6) return nil;

    unsigned int red, green, blue;
    [[NSScanner scannerWithString:[hexString substringWithRange:NSMakeRange(0, 2)]] scanHexInt:&red];
    [[NSScanner scannerWithString:[hexString substringWithRange:NSMakeRange(2, 2)]] scanHexInt:&green];
    [[NSScanner scannerWithString:[hexString substringWithRange:NSMakeRange(4, 2)]] scanHexInt:&blue];

    return [NSColor colorWithRed:red/255.0 green:green/255.0 blue:blue/255.0 alpha:1.0];
}

- (NSString *)currentEffectName {
    return _currentEffectName;
}

- (void)clearPanel {
    _currentEffectName = nil;
    _currentDef = NULL;

    // Re-initialize control map if nil (may happen if view wasn't properly set up)
    if (!_controlMap) {
        _controlMap = [NSMutableDictionary dictionary];
    } else {
        [_controlMap removeAllObjects];
    }

    if (_mainStack) {
        for (NSView *view in [_mainStack.arrangedSubviews copy]) {
            [_mainStack removeArrangedSubview:view];
            [view removeFromSuperview];
        }
    }

    [self showPlaceholder:@"Select an effect"];
}

#pragma mark - Private Methods

- (void)showPlaceholder:(NSString *)message {
    for (NSView *view in [_mainStack.arrangedSubviews copy]) {
        [_mainStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSTextField *label = [NSTextField labelWithString:message];
    label.textColor = [NSColor secondaryLabelColor];
    label.alignment = NSTextAlignmentCenter;
    [_mainStack addArrangedSubview:label];
}

- (void)buildParameterGroups {
    if (!_currentDef || !_currentDef->groupOrder) return;

    // Iterate through groups in order
    for (int g = 0; _currentDef->groupOrder[g] != NULL; g++) {
        const char *groupName = _currentDef->groupOrder[g];
        NSString *groupNameStr = [NSString stringWithUTF8String:groupName];

        // Create disclosure view for group
        NSStackView *groupStack = [[NSStackView alloc] init];
        groupStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        groupStack.alignment = NSLayoutAttributeLeading;
        groupStack.spacing = 4;

        // Group header
        NSTextField *header = [NSTextField labelWithString:groupNameStr];
        header.font = [NSFont boldSystemFontOfSize:11];
        header.textColor = [NSColor secondaryLabelColor];
        [groupStack addArrangedSubview:header];

        // Add parameters for this group
        for (int p = 0; _currentDef->parameters[p].key != NULL; p++) {
            const XLParameterDef *param = &_currentDef->parameters[p];

            // Check if this parameter belongs to current group
            if (param->group && strcmp(param->group, groupName) == 0) {
                NSView *paramView = [self createControlForParameter:param index:p];
                if (paramView) {
                    [groupStack addArrangedSubview:paramView];
                }
            }
        }

        // Only add group if it has parameters
        if (groupStack.arrangedSubviews.count > 1) {
            [_mainStack addArrangedSubview:groupStack];

            // Width constraint
            [groupStack.widthAnchor constraintEqualToAnchor:_mainStack.widthAnchor constant:-16].active = YES;
        }
    }
}

- (NSView *)createControlForParameter:(const XLParameterDef *)param index:(NSInteger)idx {
    if (!param || !param->key) return nil;

    NSString *key = [NSString stringWithUTF8String:param->key];
    NSString *label = param->displayLabel ?
                      [NSString stringWithUTF8String:param->displayLabel] : key;

    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 4;
    row.distribution = NSStackViewDistributionFill;

    // Label
    NSTextField *labelField = [NSTextField labelWithString:label];
    labelField.font = [NSFont systemFontOfSize:11];
    [labelField setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [labelField setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addArrangedSubview:labelField];

    // Create appropriate control based on type
    NSControl *mainControl = nil;

    switch (param->type) {
        case XLParameterTypeInt:
        case XLParameterTypeFloat:
            mainControl = [self createSliderControlForParameter:param index:idx inRow:row];
            break;

        case XLParameterTypeBool:
            mainControl = [self createSwitchControlForParameter:param index:idx];
            break;

        case XLParameterTypeChoice:
            mainControl = [self createPopupControlForParameter:param index:idx];
            break;

        case XLParameterTypeColor:
            mainControl = [self createColorWellForParameter:param index:idx];
            break;

        case XLParameterTypeString:
            mainControl = [self createTextFieldForParameter:param index:idx];
            break;

        case XLParameterTypeFile:
            mainControl = (NSControl *)[self createFilePickerForParameter:param index:idx inRow:row];
            break;

        case XLParameterTypeFont:
            mainControl = [self createFontButtonForParameter:param index:idx];
            break;

        default:
            break;
    }

    if (mainControl && mainControl.superview == nil) {
        [row addArrangedSubview:mainControl];
    }

    // Store control reference
    if (mainControl) {
        _controlMap[key] = mainControl;
    }

    // Value curve button (if supported)
    if (param->flags & XLParameterFlagsSupportsValueCurve) {
        NSButton *vcButton = [self createValueCurveButtonForIndex:idx];
        [row addArrangedSubview:vcButton];
    }

    // Lock button (if lockable)
    if (param->flags & XLParameterFlagsLockable) {
        NSButton *lockButton = [self createLockButtonForIndex:idx];
        [row addArrangedSubview:lockButton];
    }

    return row;
}

#pragma mark - Control Creators

- (NSSlider *)createSliderControlForParameter:(const XLParameterDef *)param index:(NSInteger)idx inRow:(NSStackView *)row {
    // Create slider
    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(0, 0, 150, 20)];
    slider.minValue = param->minValue;
    slider.maxValue = param->maxValue;
    slider.doubleValue = param->defaultValue;
    slider.continuous = YES;
    slider.target = self;
    slider.action = @selector(sliderChanged:);
    slider.tag = EncodeTag(idx, XLControlTypeSlider);
    [slider setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addArrangedSubview:slider];

    // Create linked text field
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)];
    textField.font = [NSFont systemFontOfSize:11];
    textField.alignment = NSTextAlignmentRight;
    textField.delegate = self;
    textField.tag = EncodeTag(idx, XLControlTypeTextField);

    if (param->type == XLParameterTypeFloat && param->divisor > 1) {
        textField.stringValue = [NSString stringWithFormat:@"%.1f", param->defaultValue / param->divisor];
    } else {
        textField.integerValue = (NSInteger)param->defaultValue;
    }

    [textField setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addArrangedSubview:textField];

    // Store text field in control map with "_text" suffix
    NSString *key = [NSString stringWithUTF8String:param->key];
    _controlMap[[key stringByAppendingString:@"_text"]] = textField;

    return slider;
}

- (NSSwitch *)createSwitchControlForParameter:(const XLParameterDef *)param index:(NSInteger)idx {
    NSSwitch *toggle = [[NSSwitch alloc] initWithFrame:NSMakeRect(0, 0, 40, 20)];
    toggle.state = (param->defaultValue != 0) ? NSControlStateValueOn : NSControlStateValueOff;
    toggle.target = self;
    toggle.action = @selector(switchChanged:);
    toggle.tag = EncodeTag(idx, XLControlTypeSwitch);
    return toggle;
}

- (NSPopUpButton *)createPopupControlForParameter:(const XLParameterDef *)param index:(NSInteger)idx {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 150, 20) pullsDown:NO];
    popup.font = [NSFont systemFontOfSize:11];

    // Add choices
    if (param->choices) {
        for (int i = 0; param->choices[i] != NULL; i++) {
            [popup addItemWithTitle:[NSString stringWithUTF8String:param->choices[i]]];
        }
        [popup selectItemAtIndex:param->defaultChoiceIndex];
    }

    popup.target = self;
    popup.action = @selector(popupChanged:);
    popup.tag = EncodeTag(idx, XLControlTypePopup);

    return popup;
}

- (NSColorWell *)createColorWellForParameter:(const XLParameterDef *)param index:(NSInteger)idx {
    NSColorWell *colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 40, 20)];
    colorWell.color = [NSColor whiteColor];  // Default, parse from param->defaultString if needed
    colorWell.target = self;
    colorWell.action = @selector(colorWellChanged:);
    colorWell.tag = EncodeTag(idx, XLControlTypeColorWell);
    return colorWell;
}

- (NSTextField *)createTextFieldForParameter:(const XLParameterDef *)param index:(NSInteger)idx {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 150, 20)];
    textField.font = [NSFont systemFontOfSize:11];
    textField.delegate = self;
    textField.stringValue = param->defaultString ? [NSString stringWithUTF8String:param->defaultString] : @"";
    textField.tag = EncodeTag(idx, XLControlTypeTextField);
    return textField;
}

- (NSView *)createFilePickerForParameter:(const XLParameterDef *)param index:(NSInteger)idx inRow:(NSStackView *)row {
    NSTextField *pathField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 120, 20)];
    pathField.font = [NSFont systemFontOfSize:11];
    pathField.placeholderString = @"Choose file...";
    pathField.editable = NO;
    pathField.tag = EncodeTag(idx, XLControlTypeFilePicker);
    [pathField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addArrangedSubview:pathField];

    NSButton *browseButton = [NSButton buttonWithTitle:@"..." target:self action:@selector(browseFileClicked:)];
    browseButton.bezelStyle = NSBezelStyleRounded;
    browseButton.font = [NSFont systemFontOfSize:11];
    browseButton.tag = EncodeTag(idx, XLControlTypeFilePicker);
    [row addArrangedSubview:browseButton];

    return pathField;
}

- (NSButton *)createFontButtonForParameter:(const XLParameterDef *)param index:(NSInteger)idx {
    NSButton *fontButton = [NSButton buttonWithTitle:@"Select Font..." target:self action:@selector(fontButtonClicked:)];
    fontButton.bezelStyle = NSBezelStyleRounded;
    fontButton.font = [NSFont systemFontOfSize:11];
    fontButton.tag = EncodeTag(idx, XLControlTypeTextField);
    return fontButton;
}

- (NSButton *)createValueCurveButtonForIndex:(NSInteger)idx {
    NSButton *vcButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
    vcButton.bezelStyle = NSBezelStyleRounded;
    vcButton.image = [NSImage imageWithSystemSymbolName:@"waveform" accessibilityDescription:@"Value Curve"];
    vcButton.imagePosition = NSImageOnly;
    vcButton.target = self;
    vcButton.action = @selector(valueCurveClicked:);
    vcButton.tag = EncodeTag(idx, XLControlTypeValueCurve);
    vcButton.toolTip = @"Edit Value Curve";
    return vcButton;
}

- (NSButton *)createLockButtonForIndex:(NSInteger)idx {
    NSButton *lockButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
    lockButton.bezelStyle = NSBezelStyleRounded;
    lockButton.image = [NSImage imageWithSystemSymbolName:@"lock.open" accessibilityDescription:@"Lock"];
    lockButton.imagePosition = NSImageOnly;
    lockButton.target = self;
    lockButton.action = @selector(lockButtonClicked:);
    lockButton.tag = EncodeTag(idx, XLControlTypeLock);
    lockButton.toolTip = @"Lock Parameter";
    return lockButton;
}

#pragma mark - Control Actions

- (void)sliderChanged:(NSSlider *)sender {
    NSInteger paramIndex;
    XLControlType type;
    DecodeTag(sender.tag, &paramIndex, &type);

    if (!_currentDef || paramIndex >= [self parameterCount]) return;

    const XLParameterDef *param = &_currentDef->parameters[paramIndex];
    NSString *key = [NSString stringWithUTF8String:param->key];

    // Update linked text field
    NSTextField *textField = (NSTextField *)_controlMap[[key stringByAppendingString:@"_text"]];
    if (textField) {
        if (param->type == XLParameterTypeFloat && param->divisor > 1) {
            textField.stringValue = [NSString stringWithFormat:@"%.1f", sender.doubleValue / param->divisor];
        } else {
            textField.integerValue = (NSInteger)sender.doubleValue;
        }
    }

    // Notify delegate
    NSString *value;
    if (param->type == XLParameterTypeFloat && param->divisor > 1) {
        value = [NSString stringWithFormat:@"%.1f", sender.doubleValue / param->divisor];
    } else {
        value = [NSString stringWithFormat:@"%ld", (long)sender.integerValue];
    }

    [self notifyParameterChange:key value:value];
}

- (void)switchChanged:(NSSwitch *)sender {
    NSInteger paramIndex;
    XLControlType type;
    DecodeTag(sender.tag, &paramIndex, &type);

    if (!_currentDef || paramIndex >= [self parameterCount]) return;

    const XLParameterDef *param = &_currentDef->parameters[paramIndex];
    NSString *key = [NSString stringWithUTF8String:param->key];
    NSString *value = (sender.state == NSControlStateValueOn) ? @"1" : @"0";

    [self notifyParameterChange:key value:value];
}

- (void)popupChanged:(NSPopUpButton *)sender {
    NSInteger paramIndex;
    XLControlType type;
    DecodeTag(sender.tag, &paramIndex, &type);

    if (!_currentDef || paramIndex >= [self parameterCount]) return;

    const XLParameterDef *param = &_currentDef->parameters[paramIndex];
    NSString *key = [NSString stringWithUTF8String:param->key];
    NSString *value = sender.titleOfSelectedItem ?: @"";

    [self notifyParameterChange:key value:value];
}

- (void)colorWellChanged:(NSColorWell *)sender {
    NSInteger paramIndex;
    XLControlType type;
    DecodeTag(sender.tag, &paramIndex, &type);

    if (!_currentDef || paramIndex >= [self parameterCount]) return;

    const XLParameterDef *param = &_currentDef->parameters[paramIndex];
    NSString *key = [NSString stringWithUTF8String:param->key];

    // Convert color to hex string
    NSColor *color = [sender.color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    NSString *value = [NSString stringWithFormat:@"#%02X%02X%02X",
                       (int)(color.redComponent * 255),
                       (int)(color.greenComponent * 255),
                       (int)(color.blueComponent * 255)];

    [self notifyParameterChange:key value:value];
}

- (void)browseFileClicked:(NSButton *)sender {
    NSInteger paramIndex;
    XLControlType type;
    DecodeTag(sender.tag, &paramIndex, &type);

    if (!_currentDef || paramIndex >= [self parameterCount]) return;

    const XLParameterDef *param = &_currentDef->parameters[paramIndex];

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;

    // Set allowed file types from filter
    if (param->fileFilter) {
        NSString *filter = [NSString stringWithUTF8String:param->fileFilter];
        NSArray *types = [filter componentsSeparatedByString:@","];
        panel.allowedContentTypes = @[];  // Would need to map extensions to UTTypes
    }

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URLs.firstObject) {
            NSString *path = panel.URLs.firstObject.path;
            NSString *key = [NSString stringWithUTF8String:param->key];

            // Update path field
            NSTextField *pathField = (NSTextField *)self->_controlMap[key];
            if (pathField) {
                pathField.stringValue = path.lastPathComponent;
                pathField.toolTip = path;
            }

            [self notifyParameterChange:key value:path];
        }
    }];
}

- (void)fontButtonClicked:(NSButton *)sender {
    // Would show font panel - simplified for now
    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    [fontManager orderFrontFontPanel:self];
}

- (void)valueCurveClicked:(NSButton *)sender {
    NSInteger paramIndex;
    XLControlType type;
    DecodeTag(sender.tag, &paramIndex, &type);

    if (!_currentDef || paramIndex >= [self parameterCount]) return;

    const XLParameterDef *param = &_currentDef->parameters[paramIndex];
    NSString *key = [NSString stringWithUTF8String:param->key];

    if ([_delegate respondsToSelector:@selector(effectPanel:editValueCurveForParameter:)]) {
        [_delegate effectPanel:_currentEffectName editValueCurveForParameter:key];
    }
}

- (void)lockButtonClicked:(NSButton *)sender {
    NSInteger paramIndex;
    XLControlType type;
    DecodeTag(sender.tag, &paramIndex, &type);

    if (!_currentDef || paramIndex >= [self parameterCount]) return;

    const XLParameterDef *param = &_currentDef->parameters[paramIndex];
    NSString *key = [NSString stringWithUTF8String:param->key];

    // Toggle lock state
    BOOL currentlyLocked = [_lockedParams[key] boolValue];
    BOOL newLocked = !currentlyLocked;
    _lockedParams[key] = @(newLocked);

    // Update button icon
    sender.image = [NSImage imageWithSystemSymbolName:newLocked ? @"lock" : @"lock.open"
                              accessibilityDescription:@"Lock"];

    if ([_delegate respondsToSelector:@selector(effectPanel:didLockParameter:locked:)]) {
        [_delegate effectPanel:_currentEffectName didLockParameter:key locked:newLocked];
    }
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *textField = notification.object;

    NSInteger paramIndex;
    XLControlType type;
    DecodeTag(textField.tag, &paramIndex, &type);

    if (!_currentDef || paramIndex >= [self parameterCount]) return;

    const XLParameterDef *param = &_currentDef->parameters[paramIndex];
    NSString *key = [NSString stringWithUTF8String:param->key];

    // For slider-linked text fields, update the slider
    if (param->type == XLParameterTypeInt || param->type == XLParameterTypeFloat) {
        NSSlider *slider = (NSSlider *)_controlMap[key];
        if (slider && [slider isKindOfClass:[NSSlider class]]) {
            if (param->type == XLParameterTypeFloat && param->divisor > 1) {
                slider.doubleValue = textField.doubleValue * param->divisor;
            } else {
                slider.integerValue = textField.integerValue;
            }
        }
    }

    [self notifyParameterChange:key value:textField.stringValue];
}

#pragma mark - Helper Methods

- (NSInteger)parameterCount {
    if (!_currentDef || !_currentDef->parameters) return 0;

    NSInteger count = 0;
    while (_currentDef->parameters[count].key != NULL) {
        count++;
    }
    return count;
}

- (void)notifyParameterChange:(NSString *)key value:(NSString *)value {
    // Update engine bridge if available
    if (_engineBridge && _effectId > 0) {
        [_engineBridge setEffectParameter:_effectId key:key value:value];
    }

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(effectPanel:didChangeParameter:value:)]) {
        [_delegate effectPanel:_currentEffectName didChangeParameter:key value:value];
    }
}

- (void)setDefaultValues {
    if (!_currentDef) return;

    for (int p = 0; _currentDef->parameters[p].key != NULL; p++) {
        const XLParameterDef *param = &_currentDef->parameters[p];
        NSString *key = [NSString stringWithUTF8String:param->key];
        NSControl *control = _controlMap[key];

        if (!control) continue;

        switch (param->type) {
            case XLParameterTypeInt:
            case XLParameterTypeFloat:
                if ([control isKindOfClass:[NSSlider class]]) {
                    ((NSSlider *)control).doubleValue = param->defaultValue;
                }
                break;

            case XLParameterTypeBool:
                if ([control isKindOfClass:[NSSwitch class]]) {
                    ((NSSwitch *)control).state = param->defaultValue ? NSControlStateValueOn : NSControlStateValueOff;
                }
                break;

            case XLParameterTypeChoice:
                if ([control isKindOfClass:[NSPopUpButton class]]) {
                    [(NSPopUpButton *)control selectItemAtIndex:param->defaultChoiceIndex];
                }
                break;

            default:
                break;
        }
    }
}

@end
