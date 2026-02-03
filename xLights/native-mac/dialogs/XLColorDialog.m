/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLColorDialog.h"

static const NSInteger kMaxHistoryColors = 20;
static NSMutableArray<NSColor *> *sColorHistory = nil;

@interface XLColorDialog ()

@property (nonatomic, strong) NSColorWell *colorWell;
@property (nonatomic, strong) NSTextField *rgbLabel;
@property (nonatomic, strong) NSTextField *hsvLabel;
@property (nonatomic, strong) NSSlider *brightnessSlider;
@property (nonatomic, strong) NSStackView *historyStack;
@property (nonatomic, strong) NSStackView *presetsStack;

@end

@implementation XLColorDialog

+ (void)initialize {
    if (self == [XLColorDialog class]) {
        sColorHistory = [NSMutableArray array];
    }
}

+ (void)addColorToHistory:(NSColor *)color {
    if (!color) return;

    // Remove if already in history
    NSColor *rgbColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!rgbColor) return;

    NSInteger indexToRemove = NSNotFound;
    for (NSInteger i = 0; i < sColorHistory.count; i++) {
        NSColor *histColor = [sColorHistory[i] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        if (histColor &&
            fabs(histColor.redComponent - rgbColor.redComponent) < 0.01 &&
            fabs(histColor.greenComponent - rgbColor.greenComponent) < 0.01 &&
            fabs(histColor.blueComponent - rgbColor.blueComponent) < 0.01) {
            indexToRemove = i;
            break;
        }
    }

    if (indexToRemove != NSNotFound) {
        [sColorHistory removeObjectAtIndex:indexToRemove];
    }

    // Add to front
    [sColorHistory insertObject:color atIndex:0];

    // Trim if needed
    while (sColorHistory.count > kMaxHistoryColors) {
        [sColorHistory removeLastObject];
    }
}

+ (NSArray<NSColor *> *)colorHistory {
    return [sColorHistory copy];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Select Color";
        self.minWidth = 400;
        self.minHeight = 350;
        _color = [NSColor whiteColor];
        _showBrightnessPresets = YES;
        _showColorHistory = YES;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 16;

    // Color well
    _colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 60, 40)];
    _colorWell.color = _color;
    [_colorWell setTarget:self];
    [_colorWell setAction:@selector(colorChanged:)];
    [_colorWell.widthAnchor constraintEqualToConstant:80].active = YES;
    [_colorWell.heightAnchor constraintEqualToConstant:40].active = YES;

    NSStackView *wellRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    wellRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    wellRow.spacing = 16;

    NSTextField *colorLabel = [NSTextField labelWithString:@"Selected Color:"];
    [wellRow addArrangedSubview:colorLabel];
    [wellRow addArrangedSubview:_colorWell];
    [stack addArrangedSubview:wellRow];

    // RGB and HSV labels
    _rgbLabel = [NSTextField labelWithString:@"RGB: 255, 255, 255"];
    _rgbLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    [stack addArrangedSubview:_rgbLabel];

    _hsvLabel = [NSTextField labelWithString:@"HSV: 0, 0%, 100%"];
    _hsvLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    [stack addArrangedSubview:_hsvLabel];

    // Brightness slider
    if (_showBrightnessPresets) {
        NSBox *brightnessBox = [[NSBox alloc] initWithFrame:NSZeroRect];
        brightnessBox.title = @"Brightness";
        brightnessBox.titlePosition = NSAtTop;
        brightnessBox.translatesAutoresizingMaskIntoConstraints = NO;

        NSStackView *brightnessStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        brightnessStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        brightnessStack.spacing = 8;
        brightnessStack.translatesAutoresizingMaskIntoConstraints = NO;

        _brightnessSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
        _brightnessSlider.minValue = 0.0;
        _brightnessSlider.maxValue = 1.0;
        _brightnessSlider.doubleValue = 1.0;
        [_brightnessSlider setTarget:self];
        [_brightnessSlider setAction:@selector(brightnessChanged:)];

        [brightnessStack addArrangedSubview:_brightnessSlider];

        // Preset buttons
        _presetsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        _presetsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _presetsStack.spacing = 8;

        NSArray<NSNumber *> *presets = @[@25, @50, @75, @100];
        for (NSNumber *preset in presets) {
            NSButton *btn = [NSButton buttonWithTitle:[NSString stringWithFormat:@"%@%%", preset]
                                               target:self
                                               action:@selector(presetClicked:)];
            btn.tag = preset.integerValue;
            [btn.widthAnchor constraintEqualToConstant:50].active = YES;
            [_presetsStack addArrangedSubview:btn];
        }

        [brightnessStack addArrangedSubview:_presetsStack];

        brightnessBox.contentView = brightnessStack;
        [brightnessStack.leadingAnchor constraintEqualToAnchor:brightnessBox.contentView.leadingAnchor constant:10].active = YES;
        [brightnessStack.trailingAnchor constraintEqualToAnchor:brightnessBox.contentView.trailingAnchor constant:-10].active = YES;
        [brightnessStack.topAnchor constraintEqualToAnchor:brightnessBox.contentView.topAnchor constant:10].active = YES;
        [brightnessStack.bottomAnchor constraintEqualToAnchor:brightnessBox.contentView.bottomAnchor constant:-10].active = YES;

        [stack addArrangedSubview:brightnessBox];
        [brightnessBox.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [brightnessBox.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
    }

    // Color history
    if (_showColorHistory && sColorHistory.count > 0) {
        NSBox *historyBox = [[NSBox alloc] initWithFrame:NSZeroRect];
        historyBox.title = @"Recent Colors";
        historyBox.titlePosition = NSAtTop;
        historyBox.translatesAutoresizingMaskIntoConstraints = NO;

        _historyStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        _historyStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _historyStack.spacing = 4;
        _historyStack.translatesAutoresizingMaskIntoConstraints = NO;

        [self populateHistoryColors];

        historyBox.contentView = _historyStack;
        [_historyStack.leadingAnchor constraintEqualToAnchor:historyBox.contentView.leadingAnchor constant:10].active = YES;
        [_historyStack.topAnchor constraintEqualToAnchor:historyBox.contentView.topAnchor constant:10].active = YES;
        [_historyStack.bottomAnchor constraintEqualToAnchor:historyBox.contentView.bottomAnchor constant:-10].active = YES;

        [stack addArrangedSubview:historyBox];
        [historyBox.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [historyBox.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
    }

    return stack;
}

- (void)populateHistoryColors {
    // Remove existing
    for (NSView *view in _historyStack.arrangedSubviews) {
        [_historyStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    // Add history colors
    NSInteger count = MIN(sColorHistory.count, 10);
    for (NSInteger i = 0; i < count; i++) {
        NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 24, 24)];
        btn.bordered = NO;
        btn.wantsLayer = YES;
        btn.layer.backgroundColor = sColorHistory[i].CGColor;
        btn.layer.cornerRadius = 4;
        btn.layer.borderWidth = 1;
        btn.layer.borderColor = [NSColor separatorColor].CGColor;
        btn.tag = i;
        [btn setTarget:self];
        [btn setAction:@selector(historyColorClicked:)];
        [btn.widthAnchor constraintEqualToConstant:24].active = YES;
        [btn.heightAnchor constraintEqualToConstant:24].active = YES;

        [_historyStack addArrangedSubview:btn];
    }
}

- (void)sheetDidLoad {
    [self updateColorLabels];
}

- (void)updateColorLabels {
    NSColor *rgbColor = [_colorWell.color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (rgbColor) {
        CGFloat r = rgbColor.redComponent * 255;
        CGFloat g = rgbColor.greenComponent * 255;
        CGFloat b = rgbColor.blueComponent * 255;
        _rgbLabel.stringValue = [NSString stringWithFormat:@"RGB: %.0f, %.0f, %.0f", r, g, b];

        CGFloat h, s, v;
        [rgbColor getHue:&h saturation:&s brightness:&v alpha:nil];
        _hsvLabel.stringValue = [NSString stringWithFormat:@"HSV: %.0f, %.0f%%, %.0f%%", h * 360, s * 100, v * 100];

        if (_brightnessSlider) {
            _brightnessSlider.doubleValue = v;
        }
    }
}

#pragma mark - Actions

- (void)colorChanged:(id)sender {
    [self updateColorLabels];
}

- (void)brightnessChanged:(id)sender {
    NSColor *rgbColor = [_colorWell.color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (rgbColor) {
        CGFloat h, s, v, a;
        [rgbColor getHue:&h saturation:&s brightness:&v alpha:&a];
        v = _brightnessSlider.doubleValue;
        _colorWell.color = [NSColor colorWithHue:h saturation:s brightness:v alpha:a];
        [self updateColorLabels];
    }
}

- (void)presetClicked:(id)sender {
    NSButton *btn = (NSButton *)sender;
    double brightness = (double)btn.tag / 100.0;

    NSColor *rgbColor = [_colorWell.color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (rgbColor) {
        CGFloat h, s, v, a;
        [rgbColor getHue:&h saturation:&s brightness:&v alpha:&a];
        _colorWell.color = [NSColor colorWithHue:h saturation:s brightness:brightness alpha:a];
        _brightnessSlider.doubleValue = brightness;
        [self updateColorLabels];
    }
}

- (void)historyColorClicked:(id)sender {
    NSButton *btn = (NSButton *)sender;
    NSInteger index = btn.tag;
    if (index >= 0 && index < (NSInteger)sColorHistory.count) {
        _colorWell.color = sColorHistory[index];
        [self updateColorLabels];
    }
}

- (void)okClicked:(id)sender {
    _color = _colorWell.color;
    [XLColorDialog addColorToHistory:_color];
    [super okClicked:sender];
}

@end
