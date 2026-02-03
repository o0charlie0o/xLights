/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLEffectPanelBuilder.h"
#import <objc/runtime.h>

// macOS HIG spacing constants (8pt grid)
static const CGFloat kRowSpacing        = 8.0;
static const CGFloat kColumnSpacing     = 8.0;
static const CGFloat kSectionSpacing    = 16.0;
static const CGFloat kLabelWidth        = 120.0;
static const CGFloat kLockButtonSize    = 14.0;
static const CGFloat kVCButtonSize      = 20.0;
static const CGFloat kSpacerHeight      = 8.0;
static const CGFloat kEdgeInset         = 8.0;
static const CGFloat kSliderMinWidth    = 120.0;
static const CGFloat kTextFieldWidth    = 50.0;

// Tags used for identifying controls by key via associated objects
static const void *kParamKeyAssociationKey = &kParamKeyAssociationKey;
static const void *kParamDescriptorAssociationKey = &kParamDescriptorAssociationKey;

// ---------------------------------------------------------------------------
// MARK: - Private helpers
// ---------------------------------------------------------------------------

@interface XLEffectPanelBuilder ()

/// Maps parameter key -> primary control (slider, checkbox, popup, etc.)
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSControl *> *controlsByKey;

/// Maps parameter key -> text field companion (for sliders).
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSTextField *> *textFieldsByKey;

/// Maps parameter key -> value curve button.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSButton *> *vcButtonsByKey;

/// Maps parameter key -> lock button.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSButton *> *lockButtonsByKey;

/// The descriptor used for the last build.
@property (nonatomic, strong) XLEffectPanelDescriptor *currentDescriptor;

/// Internal mutable copy of settings.
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *internalSettings;

/// Maps group name -> NSDisclosureButton / disclosure view for collapsible sections.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSStackView *> *groupStackViews;

/// The root stack view of the built panel.
@property (nonatomic, weak) NSStackView *rootStackView;

@end

@implementation XLEffectPanelBuilder

- (instancetype)init
{
    self = [super init];
    if (self) {
        _controlsByKey = [NSMutableDictionary dictionary];
        _textFieldsByKey = [NSMutableDictionary dictionary];
        _vcButtonsByKey = [NSMutableDictionary dictionary];
        _lockButtonsByKey = [NSMutableDictionary dictionary];
        _groupStackViews = [NSMutableDictionary dictionary];
        _internalSettings = [NSMutableDictionary dictionary];
    }
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - Public API
// ---------------------------------------------------------------------------

- (NSView *)buildPanelForDescriptor:(XLEffectPanelDescriptor *)descriptor
                           settings:(NSDictionary<NSString *, id> *)settings
{
    [self.controlsByKey removeAllObjects];
    [self.textFieldsByKey removeAllObjects];
    [self.vcButtonsByKey removeAllObjects];
    [self.lockButtonsByKey removeAllObjects];
    [self.groupStackViews removeAllObjects];
    self.internalSettings = settings ? [settings mutableCopy] : [NSMutableDictionary dictionary];
    self.currentDescriptor = descriptor;

    NSStackView *rootStack = [NSStackView stackViewWithViews:@[]];
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.alignment = NSLayoutAttributeLeading;
    rootStack.spacing = kRowSpacing;
    rootStack.edgeInsets = NSEdgeInsetsMake(kEdgeInset, kEdgeInset, kEdgeInset, kEdgeInset);
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.rootStackView = rootStack;

    NSString *currentGroup = nil;
    NSStackView *currentGroupStack = nil;

    for (XLEffectParamDescriptor *param in descriptor.parameters) {
        // Handle group transitions
        if (param.groupName.length > 0 && ![param.groupName isEqualToString:currentGroup]) {
            currentGroup = param.groupName;
            currentGroupStack = [self createDisclosureSectionForGroup:currentGroup
                                                         inRootStack:rootStack];
        } else if (param.groupName.length == 0 && currentGroup != nil) {
            currentGroup = nil;
            currentGroupStack = nil;
        }

        NSStackView *targetStack = currentGroupStack ?: rootStack;
        NSView *rowView = [self buildRowForParam:param];
        if (rowView) {
            [targetStack addArrangedSubview:rowView];
            [rowView.leadingAnchor constraintEqualToAnchor:targetStack.leadingAnchor].active = YES;
            [rowView.trailingAnchor constraintEqualToAnchor:targetStack.trailingAnchor].active = YES;
        }
    }

    [self updateControlsFromSettings:self.internalSettings];

    return rootStack;
}

- (void)updateControlsFromSettings:(NSDictionary<NSString *, id> *)settings
{
    for (NSString *key in settings) {
        id value = settings[key];
        [self.internalSettings setObject:value forKey:key];

        NSControl *control = self.controlsByKey[key];
        if (!control) continue;

        XLEffectParamDescriptor *paramDesc = [self descriptorForKey:key];

        if ([control isKindOfClass:[NSSlider class]]) {
            CGFloat numericValue = [self numericValueFromSettingsValue:value];
            CGFloat divisor = (paramDesc.divisor > 1) ? paramDesc.divisor : 1;
            [(NSSlider *)control setDoubleValue:numericValue * divisor];
            NSTextField *companion = self.textFieldsByKey[key];
            if (companion) {
                if (divisor > 1) {
                    companion.stringValue = [NSString stringWithFormat:@"%.1f", numericValue];
                } else {
                    companion.stringValue = [NSString stringWithFormat:@"%d", (int)numericValue];
                }
            }
        } else if ([control isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)control;
            if (![button isKindOfClass:[NSPopUpButton class]]) {
                button.state = [value boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
            }
        } else if ([control isKindOfClass:[NSPopUpButton class]]) {
            NSPopUpButton *popup = (NSPopUpButton *)control;
            if ([value isKindOfClass:[NSString class]]) {
                [popup selectItemWithTitle:value];
            } else if ([value isKindOfClass:[NSNumber class]]) {
                [popup selectItemAtIndex:[value integerValue]];
            }
        } else if ([control isKindOfClass:[NSTextField class]]) {
            [(NSTextField *)control setStringValue:[NSString stringWithFormat:@"%@", value]];
        } else if ([control isKindOfClass:[NSColorWell class]]) {
            if ([value isKindOfClass:[NSColor class]]) {
                [(NSColorWell *)control setColor:value];
            }
        }
    }
}

- (NSDictionary<NSString *, id> *)currentSettings
{
    NSMutableDictionary *result = [self.internalSettings mutableCopy];

    for (NSString *key in self.controlsByKey) {
        NSControl *control = self.controlsByKey[key];
        XLEffectParamDescriptor *paramDesc = [self descriptorForKey:key];

        if ([control isKindOfClass:[NSSlider class]]) {
            CGFloat rawValue = [(NSSlider *)control doubleValue];
            CGFloat divisor = (paramDesc.divisor > 1) ? paramDesc.divisor : 1;
            if (divisor > 1) {
                result[key] = @(rawValue / divisor);
            } else {
                result[key] = @((NSInteger)rawValue);
            }
        } else if ([control isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)control;
            if (![button isKindOfClass:[NSPopUpButton class]]) {
                result[key] = @(button.state == NSControlStateValueOn);
            }
        } else if ([control isKindOfClass:[NSPopUpButton class]]) {
            NSPopUpButton *popup = (NSPopUpButton *)control;
            NSString *title = popup.titleOfSelectedItem;
            result[key] = title ?: @"";
        } else if ([control isKindOfClass:[NSTextField class]]) {
            result[key] = [(NSTextField *)control stringValue];
        } else if ([control isKindOfClass:[NSColorWell class]]) {
            result[key] = [(NSColorWell *)control color];
        }
    }

    return [result copy];
}

// ---------------------------------------------------------------------------
// MARK: - Row construction
// ---------------------------------------------------------------------------

- (NSView *)buildRowForParam:(XLEffectParamDescriptor *)param
{
    switch (param.type) {
        case XLEffectParamTypeSpacer:
            return [self buildSpacerRow];

        case XLEffectParamTypeLabel:
            return [self buildLabelRow:param];

        case XLEffectParamTypeSlider:
            return [self buildSliderRow:param];

        case XLEffectParamTypeCheckbox:
            return [self buildCheckboxRow:param];

        case XLEffectParamTypePopupMenu:
            return [self buildPopupRow:param];

        case XLEffectParamTypeColorPicker:
            return [self buildColorPickerRow:param];

        case XLEffectParamTypeTextField:
            return [self buildTextFieldRow:param];

        case XLEffectParamTypeFilePicker:
            return [self buildFilePickerRow:param];

        case XLEffectParamTypeBitmapButton:
            return [self buildLabelRow:param];

        case XLEffectParamTypeColorCurve:
            return [self buildColorPickerRow:param];
    }

    return nil;
}

// ---------------------------------------------------------------------------
// MARK: - Spacer
// ---------------------------------------------------------------------------

- (NSView *)buildSpacerRow
{
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer.heightAnchor constraintEqualToConstant:kSpacerHeight].active = YES;
    return spacer;
}

// ---------------------------------------------------------------------------
// MARK: - Label
// ---------------------------------------------------------------------------

- (NSView *)buildLabelRow:(XLEffectParamDescriptor *)param
{
    NSTextField *label = [NSTextField labelWithString:param.displayName ?: @""];
    label.font = [NSFont systemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightMedium];
    label.textColor = [NSColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

// ---------------------------------------------------------------------------
// MARK: - Slider row
// ---------------------------------------------------------------------------

- (NSView *)buildSliderRow:(XLEffectParamDescriptor *)param
{
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    // Label
    NSTextField *label = [NSTextField labelWithString:param.displayName ?: @""];
    label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    label.textColor = [NSColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addSubview:label];

    // Slider
    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minValue = param.minValue;
    slider.maxValue = param.maxValue;
    if (param.divisor > 1) {
        slider.minValue = param.minValue * param.divisor;
        slider.maxValue = param.maxValue * param.divisor;
        slider.doubleValue = param.defaultValue * param.divisor;
    } else {
        slider.doubleValue = param.defaultValue;
    }
    slider.continuous = YES;
    slider.target = self;
    slider.action = @selector(sliderValueChanged:);
    [self associateKey:param.key withControl:slider];
    [self associateDescriptor:param withControl:slider];
    [row addSubview:slider];
    self.controlsByKey[param.key] = slider;

    // Value text field (read-only display of slider value)
    NSTextField *valueField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    valueField.translatesAutoresizingMaskIntoConstraints = NO;
    valueField.editable = YES;
    valueField.bordered = YES;
    valueField.bezeled = YES;
    valueField.bezelStyle = NSTextFieldRoundedBezel;
    valueField.font = [NSFont monospacedDigitSystemFontOfSize:[NSFont smallSystemFontSize]
                                                       weight:NSFontWeightRegular];
    valueField.alignment = NSTextAlignmentCenter;
    valueField.delegate = (id<NSTextFieldDelegate>)self;
    [self associateKey:param.key withControl:valueField];
    [self associateDescriptor:param withControl:valueField];
    if (param.divisor > 1) {
        valueField.stringValue = [NSString stringWithFormat:@"%.1f", param.defaultValue];
    } else {
        valueField.stringValue = [NSString stringWithFormat:@"%d", (int)param.defaultValue];
    }
    [row addSubview:valueField];
    self.textFieldsByKey[param.key] = valueField;

    // Value curve button
    NSButton *vcButton = nil;
    if (param.supportsValueCurve) {
        vcButton = [self createValueCurveButtonForKey:param.key];
        [row addSubview:vcButton];
        self.vcButtonsByKey[param.key] = vcButton;
    }

    // Lock button
    NSButton *lockButton = nil;
    if (param.supportsBulkEdit) {
        lockButton = [self createLockButtonForKey:param.key];
        [row addSubview:lockButton];
        self.lockButtonsByKey[param.key] = lockButton;
    }

    // Layout constraints
    [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor].active = YES;
    [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [label.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    [slider.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:kColumnSpacing].active = YES;
    [slider.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [slider.widthAnchor constraintGreaterThanOrEqualToConstant:kSliderMinWidth].active = YES;

    NSView *afterSlider = slider;

    if (vcButton) {
        [vcButton.leadingAnchor constraintEqualToAnchor:slider.trailingAnchor constant:4].active = YES;
        [vcButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
        afterSlider = vcButton;
    }

    [valueField.leadingAnchor constraintEqualToAnchor:afterSlider.trailingAnchor constant:4].active = YES;
    [valueField.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [valueField.widthAnchor constraintEqualToConstant:kTextFieldWidth].active = YES;

    NSView *trailingAnchorView = valueField;
    if (lockButton) {
        [lockButton.leadingAnchor constraintEqualToAnchor:valueField.trailingAnchor constant:4].active = YES;
        [lockButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
        trailingAnchorView = lockButton;
    }

    [trailingAnchorView.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;

    [row.heightAnchor constraintGreaterThanOrEqualToConstant:24].active = YES;

    // Slider fills remaining space
    [slider setContentHuggingPriority:NSLayoutPriorityDefaultLow
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    [slider setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                     forOrientation:NSLayoutConstraintOrientationHorizontal];

    return row;
}

// ---------------------------------------------------------------------------
// MARK: - Checkbox row
// ---------------------------------------------------------------------------

- (NSView *)buildCheckboxRow:(XLEffectParamDescriptor *)param
{
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    // Indent to align with slider controls
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:spacer];

    NSButton *checkbox = [NSButton checkboxWithTitle:param.displayName ?: @""
                                              target:self
                                              action:@selector(checkboxValueChanged:)];
    checkbox.translatesAutoresizingMaskIntoConstraints = NO;
    checkbox.state = param.defaultChecked ? NSControlStateValueOn : NSControlStateValueOff;
    checkbox.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    [self associateKey:param.key withControl:checkbox];
    [row addSubview:checkbox];
    self.controlsByKey[param.key] = checkbox;

    NSButton *lockButton = nil;
    if (param.supportsBulkEdit) {
        lockButton = [self createLockButtonForKey:param.key];
        [row addSubview:lockButton];
        self.lockButtonsByKey[param.key] = lockButton;
    }

    // Layout
    [spacer.leadingAnchor constraintEqualToAnchor:row.leadingAnchor].active = YES;
    [spacer.widthAnchor constraintEqualToConstant:kLabelWidth + kColumnSpacing].active = YES;
    [spacer.heightAnchor constraintEqualToConstant:1].active = YES;
    [spacer.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;

    [checkbox.leadingAnchor constraintEqualToAnchor:spacer.trailingAnchor].active = YES;
    [checkbox.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;

    if (lockButton) {
        [lockButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:checkbox.trailingAnchor
                                                              constant:kColumnSpacing].active = YES;
        [lockButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;
        [lockButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    } else {
        [checkbox.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor].active = YES;
    }

    [row.heightAnchor constraintGreaterThanOrEqualToConstant:22].active = YES;

    return row;
}

// ---------------------------------------------------------------------------
// MARK: - Popup menu row
// ---------------------------------------------------------------------------

- (NSView *)buildPopupRow:(XLEffectParamDescriptor *)param
{
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *label = [NSTextField labelWithString:param.displayName ?: @""];
    label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    label.textColor = [NSColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addSubview:label];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.translatesAutoresizingMaskIntoConstraints = NO;
    popup.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    for (NSString *item in param.menuItems) {
        [popup addItemWithTitle:item];
    }
    if (param.defaultIndex >= 0 && param.defaultIndex < (NSInteger)param.menuItems.count) {
        [popup selectItemAtIndex:param.defaultIndex];
    }
    popup.target = self;
    popup.action = @selector(popupValueChanged:);
    [self associateKey:param.key withControl:popup];
    [row addSubview:popup];
    self.controlsByKey[param.key] = popup;

    NSButton *lockButton = nil;
    if (param.supportsBulkEdit) {
        lockButton = [self createLockButtonForKey:param.key];
        [row addSubview:lockButton];
        self.lockButtonsByKey[param.key] = lockButton;
    }

    // Layout
    [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor].active = YES;
    [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [label.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    [popup.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:kColumnSpacing].active = YES;
    [popup.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;

    if (lockButton) {
        [lockButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:popup.trailingAnchor
                                                              constant:kColumnSpacing].active = YES;
        [lockButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;
        [lockButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    } else {
        [popup.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor].active = YES;
    }

    [row.heightAnchor constraintGreaterThanOrEqualToConstant:24].active = YES;

    return row;
}

// ---------------------------------------------------------------------------
// MARK: - Color picker row
// ---------------------------------------------------------------------------

- (NSView *)buildColorPickerRow:(XLEffectParamDescriptor *)param
{
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *label = [NSTextField labelWithString:param.displayName ?: @""];
    label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    label.textColor = [NSColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];

    NSColorWell *colorWell = [[NSColorWell alloc] initWithFrame:NSZeroRect];
    colorWell.translatesAutoresizingMaskIntoConstraints = NO;
    colorWell.color = [NSColor whiteColor];
    colorWell.target = self;
    colorWell.action = @selector(colorWellValueChanged:);
    [self associateKey:param.key withControl:colorWell];
    [row addSubview:colorWell];
    self.controlsByKey[param.key] = colorWell;

    NSButton *lockButton = nil;
    if (param.supportsBulkEdit) {
        lockButton = [self createLockButtonForKey:param.key];
        [row addSubview:lockButton];
        self.lockButtonsByKey[param.key] = lockButton;
    }

    [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor].active = YES;
    [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [label.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    [colorWell.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:kColumnSpacing].active = YES;
    [colorWell.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [colorWell.widthAnchor constraintEqualToConstant:44].active = YES;
    [colorWell.heightAnchor constraintEqualToConstant:24].active = YES;

    if (lockButton) {
        [lockButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:colorWell.trailingAnchor
                                                              constant:kColumnSpacing].active = YES;
        [lockButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;
        [lockButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    } else {
        [colorWell.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor].active = YES;
    }

    [row.heightAnchor constraintGreaterThanOrEqualToConstant:28].active = YES;

    return row;
}

// ---------------------------------------------------------------------------
// MARK: - Text field row
// ---------------------------------------------------------------------------

- (NSView *)buildTextFieldRow:(XLEffectParamDescriptor *)param
{
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *label = [NSTextField labelWithString:param.displayName ?: @""];
    label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    label.textColor = [NSColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];

    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    textField.bordered = YES;
    textField.bezeled = YES;
    textField.bezelStyle = NSTextFieldRoundedBezel;
    textField.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    textField.stringValue = param.defaultText ?: @"";
    textField.delegate = (id<NSTextFieldDelegate>)self;
    [self associateKey:param.key withControl:textField];
    [row addSubview:textField];
    self.controlsByKey[param.key] = textField;

    NSButton *lockButton = nil;
    if (param.supportsBulkEdit) {
        lockButton = [self createLockButtonForKey:param.key];
        [row addSubview:lockButton];
        self.lockButtonsByKey[param.key] = lockButton;
    }

    [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor].active = YES;
    [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [label.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    [textField.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:kColumnSpacing].active = YES;
    [textField.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;

    if (lockButton) {
        [lockButton.leadingAnchor constraintEqualToAnchor:textField.trailingAnchor constant:kColumnSpacing].active = YES;
        [lockButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;
        [lockButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    } else {
        [textField.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;
    }

    [row.heightAnchor constraintGreaterThanOrEqualToConstant:24].active = YES;

    return row;
}

// ---------------------------------------------------------------------------
// MARK: - File picker row
// ---------------------------------------------------------------------------

- (NSView *)buildFilePickerRow:(XLEffectParamDescriptor *)param
{
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *label = [NSTextField labelWithString:param.displayName ?: @""];
    label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    label.textColor = [NSColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];

    NSTextField *pathField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    pathField.translatesAutoresizingMaskIntoConstraints = NO;
    pathField.bordered = YES;
    pathField.bezeled = YES;
    pathField.bezelStyle = NSTextFieldRoundedBezel;
    pathField.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    pathField.placeholderString = @"Choose file...";
    pathField.editable = NO;
    [self associateKey:param.key withControl:pathField];
    [row addSubview:pathField];
    self.controlsByKey[param.key] = pathField;

    NSButton *browseButton = [NSButton buttonWithTitle:@"Browse..."
                                                target:self
                                                action:@selector(browseButtonClicked:)];
    browseButton.translatesAutoresizingMaskIntoConstraints = NO;
    browseButton.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    [self associateKey:param.key withControl:browseButton];
    [row addSubview:browseButton];

    NSButton *lockButton = nil;
    if (param.supportsBulkEdit) {
        lockButton = [self createLockButtonForKey:param.key];
        [row addSubview:lockButton];
        self.lockButtonsByKey[param.key] = lockButton;
    }

    [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor].active = YES;
    [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [label.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    [pathField.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:kColumnSpacing].active = YES;
    [pathField.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;

    [browseButton.leadingAnchor constraintEqualToAnchor:pathField.trailingAnchor constant:4].active = YES;
    [browseButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [browseButton setContentHuggingPriority:NSLayoutPriorityRequired
                             forOrientation:NSLayoutConstraintOrientationHorizontal];

    if (lockButton) {
        [lockButton.leadingAnchor constraintEqualToAnchor:browseButton.trailingAnchor constant:4].active = YES;
        [lockButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;
        [lockButton.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    } else {
        [browseButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;
    }

    [row.heightAnchor constraintGreaterThanOrEqualToConstant:24].active = YES;

    return row;
}

// ---------------------------------------------------------------------------
// MARK: - Disclosure section
// ---------------------------------------------------------------------------

- (NSStackView *)createDisclosureSectionForGroup:(NSString *)groupName
                                     inRootStack:(NSStackView *)rootStack
{
    NSStackView *existingStack = self.groupStackViews[groupName];
    if (existingStack) {
        return existingStack;
    }

    // Disclosure button
    NSButton *disclosure = [NSButton buttonWithTitle:groupName
                                              target:self
                                              action:@selector(disclosureToggled:)];
    disclosure.translatesAutoresizingMaskIntoConstraints = NO;
    disclosure.bezelStyle = NSBezelStyleDisclosure;
    disclosure.state = NSControlStateValueOn;
    disclosure.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize] weight:NSFontWeightMedium];

    // Section header with disclosure triangle and label
    NSView *headerRow = [[NSView alloc] initWithFrame:NSZeroRect];
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *triangle = [[NSButton alloc] initWithFrame:NSZeroRect];
    triangle.translatesAutoresizingMaskIntoConstraints = NO;
    triangle.bezelStyle = NSBezelStyleDisclosure;
    triangle.buttonType = NSButtonTypeOnOff;
    triangle.state = NSControlStateValueOn;
    triangle.title = @"";
    triangle.target = self;
    triangle.action = @selector(disclosureToggled:);
    [headerRow addSubview:triangle];

    NSTextField *groupLabel = [NSTextField labelWithString:groupName];
    groupLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize] weight:NSFontWeightMedium];
    groupLabel.textColor = [NSColor labelColor];
    groupLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:groupLabel];

    [triangle.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor].active = YES;
    [triangle.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor].active = YES;
    [groupLabel.leadingAnchor constraintEqualToAnchor:triangle.trailingAnchor constant:4].active = YES;
    [groupLabel.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor].active = YES;
    [groupLabel.trailingAnchor constraintLessThanOrEqualToAnchor:headerRow.trailingAnchor].active = YES;
    [headerRow.heightAnchor constraintGreaterThanOrEqualToConstant:20].active = YES;

    [rootStack addArrangedSubview:headerRow];

    // Content stack for grouped controls
    NSStackView *groupStack = [NSStackView stackViewWithViews:@[]];
    groupStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    groupStack.alignment = NSLayoutAttributeLeading;
    groupStack.spacing = kRowSpacing;
    groupStack.translatesAutoresizingMaskIntoConstraints = NO;

    [rootStack addArrangedSubview:groupStack];
    [groupStack.leadingAnchor constraintEqualToAnchor:rootStack.leadingAnchor constant:16].active = YES;
    [groupStack.trailingAnchor constraintEqualToAnchor:rootStack.trailingAnchor].active = YES;

    // Associate the disclosure triangle with the group stack
    objc_setAssociatedObject(triangle, kParamKeyAssociationKey, groupStack,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    self.groupStackViews[groupName] = groupStack;
    return groupStack;
}

// ---------------------------------------------------------------------------
// MARK: - Button factory helpers
// ---------------------------------------------------------------------------

- (NSButton *)createValueCurveButtonForKey:(NSString *)key
{
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = YES;
    button.title = @"VC";
    button.font = [NSFont systemFontOfSize:9 weight:NSFontWeightMedium];
    button.toolTip = @"Value Curve";
    button.target = self;
    button.action = @selector(valueCurveButtonClicked:);
    [button.widthAnchor constraintEqualToConstant:kVCButtonSize].active = YES;
    [button.heightAnchor constraintEqualToConstant:kVCButtonSize].active = YES;
    [self associateKey:key withControl:button];
    return button;
}

- (NSButton *)createLockButtonForKey:(NSString *)key
{
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleInline;
    button.bordered = NO;
    button.buttonType = NSButtonTypeToggle;
    button.image = [NSImage imageWithSystemSymbolName:@"lock.open"
                            accessibilityDescription:@"Bulk edit unlocked"];
    button.alternateImage = [NSImage imageWithSystemSymbolName:@"lock"
                                     accessibilityDescription:@"Bulk edit locked"];
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = @"Lock for bulk edit";
    button.target = self;
    button.action = @selector(lockButtonClicked:);
    [button.widthAnchor constraintEqualToConstant:kLockButtonSize].active = YES;
    [button.heightAnchor constraintEqualToConstant:kLockButtonSize].active = YES;

    NSButtonCell *cell = button.cell;
    if ([cell respondsToSelector:@selector(setImageDimsWhenDisabled:)]) {
        cell.imageDimsWhenDisabled = YES;
    }

    [self associateKey:key withControl:button];
    return button;
}

// ---------------------------------------------------------------------------
// MARK: - Associated object helpers (maps controls to param keys)
// ---------------------------------------------------------------------------

- (void)associateKey:(NSString *)key withControl:(NSControl *)control
{
    objc_setAssociatedObject(control, kParamKeyAssociationKey, key,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)associateDescriptor:(XLEffectParamDescriptor *)desc withControl:(NSControl *)control
{
    objc_setAssociatedObject(control, kParamDescriptorAssociationKey, desc,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)keyForControl:(NSControl *)control
{
    return objc_getAssociatedObject(control, kParamKeyAssociationKey);
}

- (XLEffectParamDescriptor *)descriptorForControl:(NSControl *)control
{
    return objc_getAssociatedObject(control, kParamDescriptorAssociationKey);
}

- (XLEffectParamDescriptor *)descriptorForKey:(NSString *)key
{
    for (XLEffectParamDescriptor *param in self.currentDescriptor.parameters) {
        if ([param.key isEqualToString:key]) {
            return param;
        }
    }
    return nil;
}

// ---------------------------------------------------------------------------
// MARK: - Control action handlers
// ---------------------------------------------------------------------------

- (void)sliderValueChanged:(NSSlider *)sender
{
    NSString *key = [self keyForControl:sender];
    if (!key) return;

    XLEffectParamDescriptor *paramDesc = [self descriptorForKey:key];
    CGFloat rawValue = sender.doubleValue;
    CGFloat divisor = (paramDesc.divisor > 1) ? paramDesc.divisor : 1;
    CGFloat displayValue = rawValue / divisor;

    // Update companion text field
    NSTextField *companion = self.textFieldsByKey[key];
    if (companion) {
        if (divisor > 1) {
            companion.stringValue = [NSString stringWithFormat:@"%.1f", displayValue];
        } else {
            companion.stringValue = [NSString stringWithFormat:@"%d", (int)displayValue];
        }
    }

    id settingsValue = (divisor > 1) ? @(displayValue) : @((NSInteger)displayValue);
    self.internalSettings[key] = settingsValue;

    if ([self.delegate respondsToSelector:@selector(effectPanelBuilder:didChangeValueForKey:value:)]) {
        [self.delegate effectPanelBuilder:self didChangeValueForKey:key value:settingsValue];
    }
}

- (void)checkboxValueChanged:(NSButton *)sender
{
    NSString *key = [self keyForControl:sender];
    if (!key) return;

    BOOL isChecked = (sender.state == NSControlStateValueOn);
    self.internalSettings[key] = @(isChecked);

    if ([self.delegate respondsToSelector:@selector(effectPanelBuilder:didChangeValueForKey:value:)]) {
        [self.delegate effectPanelBuilder:self didChangeValueForKey:key value:@(isChecked)];
    }
}

- (void)popupValueChanged:(NSPopUpButton *)sender
{
    NSString *key = [self keyForControl:sender];
    if (!key) return;

    NSString *selectedTitle = sender.titleOfSelectedItem ?: @"";
    self.internalSettings[key] = selectedTitle;

    if ([self.delegate respondsToSelector:@selector(effectPanelBuilder:didChangeValueForKey:value:)]) {
        [self.delegate effectPanelBuilder:self didChangeValueForKey:key value:selectedTitle];
    }
}

- (void)colorWellValueChanged:(NSColorWell *)sender
{
    NSString *key = [self keyForControl:sender];
    if (!key) return;

    NSColor *color = sender.color;
    self.internalSettings[key] = color;

    if ([self.delegate respondsToSelector:@selector(effectPanelBuilder:didChangeValueForKey:value:)]) {
        [self.delegate effectPanelBuilder:self didChangeValueForKey:key value:color];
    }
}

- (void)valueCurveButtonClicked:(NSButton *)sender
{
    NSString *key = [self keyForControl:sender];
    if (!key) return;

    if ([self.delegate respondsToSelector:@selector(effectPanelBuilder:didRequestValueCurveForKey:)]) {
        [self.delegate effectPanelBuilder:self didRequestValueCurveForKey:key];
    }
}

- (void)lockButtonClicked:(NSButton *)sender
{
    NSString *key = [self keyForControl:sender];
    if (!key) return;

    if ([self.delegate respondsToSelector:@selector(effectPanelBuilder:didToggleBulkEditForKey:)]) {
        [self.delegate effectPanelBuilder:self didToggleBulkEditForKey:key];
    }
}

- (void)browseButtonClicked:(NSButton *)sender
{
    NSString *key = [self keyForControl:sender];
    if (!key) return;

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSString *path = panel.URL.path;
            if (path) {
                NSTextField *pathField = (NSTextField *)self.controlsByKey[key];
                pathField.stringValue = path;
                self.internalSettings[key] = path;

                if ([self.delegate respondsToSelector:@selector(effectPanelBuilder:didChangeValueForKey:value:)]) {
                    [self.delegate effectPanelBuilder:self didChangeValueForKey:key value:path];
                }
            }
        }
    }];
}

- (void)disclosureToggled:(NSButton *)sender
{
    NSStackView *groupStack = objc_getAssociatedObject(sender, kParamKeyAssociationKey);
    if (!groupStack) return;

    BOOL isExpanded = (sender.state == NSControlStateValueOn);
    groupStack.hidden = !isExpanded;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.2;
        context.allowsImplicitAnimation = YES;
        [self.rootStackView layoutSubtreeIfNeeded];
    }];
}

// ---------------------------------------------------------------------------
// MARK: - NSTextFieldDelegate (for slider companion text fields)
// ---------------------------------------------------------------------------

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *textField = notification.object;
    NSString *key = [self keyForControl:textField];
    if (!key) return;

    XLEffectParamDescriptor *paramDesc = [self descriptorForKey:key];
    if (!paramDesc) return;

    // If this is a companion text field for a slider, update the slider
    NSSlider *slider = (NSSlider *)self.controlsByKey[key];
    if ([slider isKindOfClass:[NSSlider class]]) {
        CGFloat divisor = (paramDesc.divisor > 1) ? paramDesc.divisor : 1;
        CGFloat inputValue = textField.doubleValue;

        // Clamp to valid range
        CGFloat minDisplay = paramDesc.minValue;
        CGFloat maxDisplay = paramDesc.maxValue;
        if (divisor > 1) {
            minDisplay = paramDesc.minValue;
            maxDisplay = paramDesc.maxValue;
        }
        inputValue = MAX(minDisplay, MIN(maxDisplay, inputValue));

        slider.doubleValue = inputValue * divisor;

        if (divisor > 1) {
            textField.stringValue = [NSString stringWithFormat:@"%.1f", inputValue];
        } else {
            textField.stringValue = [NSString stringWithFormat:@"%d", (int)inputValue];
        }

        id settingsValue = (divisor > 1) ? @(inputValue) : @((NSInteger)inputValue);
        self.internalSettings[key] = settingsValue;

        if ([self.delegate respondsToSelector:@selector(effectPanelBuilder:didChangeValueForKey:value:)]) {
            [self.delegate effectPanelBuilder:self didChangeValueForKey:key value:settingsValue];
        }
    } else if (paramDesc.type == XLEffectParamTypeTextField) {
        NSString *value = textField.stringValue;
        self.internalSettings[key] = value;

        if ([self.delegate respondsToSelector:@selector(effectPanelBuilder:didChangeValueForKey:value:)]) {
            [self.delegate effectPanelBuilder:self didChangeValueForKey:key value:value];
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Utility
// ---------------------------------------------------------------------------

- (CGFloat)numericValueFromSettingsValue:(id)value
{
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value doubleValue];
    } else if ([value isKindOfClass:[NSString class]]) {
        return [value doubleValue];
    }
    return 0;
}

@end
