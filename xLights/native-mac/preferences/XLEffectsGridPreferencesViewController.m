//
//  XLEffectsGridPreferencesViewController.m
//  xLights
//

#import "XLEffectsGridPreferencesViewController.h"

@interface XLEffectsGridPreferencesViewController ()

@property (nonatomic, strong) NSPopUpButton *spacingPopup;
@property (nonatomic, strong) NSButton *effectBackgroundsCheckbox;
@property (nonatomic, strong) NSButton *nodeValuesCheckbox;
@property (nonatomic, strong) NSButton *groupEffectIndicatorCheckbox;
@property (nonatomic, strong) NSButton *snapToTimingCheckbox;
@property (nonatomic, strong) NSPopUpButton *doubleClickModePopup;
@property (nonatomic, strong) NSButton *smallWaveformCheckbox;
@property (nonatomic, strong) NSButton *transitionMarksCheckbox;
@property (nonatomic, strong) NSButton *hideColorUpdateWarningCheckbox;
@property (nonatomic, strong) NSButton *alternateTimingFormatCheckbox;
@property (nonatomic, strong) NSButton *bellOnRenderCheckbox;

@end

@implementation XLEffectsGridPreferencesViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 500)];

    NSStackView *stackView = [[NSStackView alloc] initWithFrame:self.view.bounds];
    stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    stackView.alignment = NSLayoutAttributeLeading;
    stackView.spacing = 12;
    stackView.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    stackView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:stackView];

    NSView *spacingRow = [self createLabeledControl:@"Spacing:"
                                            control:({
        self.spacingPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [self.spacingPopup addItemsWithTitles:@[@"Extra Small", @"Small", @"Medium", @"Large", @"Extra Large"]];
        self.spacingPopup.target = self;
        self.spacingPopup.action = @selector(settingChanged:);
        self.spacingPopup;
    })];
    [stackView addArrangedSubview:spacingRow];

    self.effectBackgroundsCheckbox = [NSButton checkboxWithTitle:@"Effect Backgrounds" target:self action:@selector(settingChanged:)];
    [stackView addArrangedSubview:self.effectBackgroundsCheckbox];

    self.nodeValuesCheckbox = [NSButton checkboxWithTitle:@"Node Values" target:self action:@selector(settingChanged:)];
    [stackView addArrangedSubview:self.nodeValuesCheckbox];

    self.groupEffectIndicatorCheckbox = [NSButton checkboxWithTitle:@"Group Effect Indicator" target:self action:@selector(settingChanged:)];
    [stackView addArrangedSubview:self.groupEffectIndicatorCheckbox];

    self.snapToTimingCheckbox = [NSButton checkboxWithTitle:@"Snap to Timing Marks" target:self action:@selector(settingChanged:)];
    [stackView addArrangedSubview:self.snapToTimingCheckbox];

    NSView *doubleClickRow = [self createLabeledControl:@"Double Click Mode:"
                                                control:({
        self.doubleClickModePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [self.doubleClickModePopup addItemsWithTitles:@[@"Edit Text", @"Play Timing"]];
        self.doubleClickModePopup.target = self;
        self.doubleClickModePopup.action = @selector(settingChanged:);
        self.doubleClickModePopup;
    })];
    [stackView addArrangedSubview:doubleClickRow];

    self.smallWaveformCheckbox = [NSButton checkboxWithTitle:@"Small Waveform" target:self action:@selector(settingChanged:)];
    [stackView addArrangedSubview:self.smallWaveformCheckbox];

    self.transitionMarksCheckbox = [NSButton checkboxWithTitle:@"Display Transition Marks" target:self action:@selector(settingChanged:)];
    [stackView addArrangedSubview:self.transitionMarksCheckbox];

    self.hideColorUpdateWarningCheckbox = [NSButton checkboxWithTitle:@"Hide Color Update Warning" target:self action:@selector(settingChanged:)];
    [stackView addArrangedSubview:self.hideColorUpdateWarningCheckbox];

    self.alternateTimingFormatCheckbox = [NSButton checkboxWithTitle:@"Show Alternate Timing Format" target:self action:@selector(settingChanged:)];
    [stackView addArrangedSubview:self.alternateTimingFormatCheckbox];

    self.bellOnRenderCheckbox = [NSButton checkboxWithTitle:@"Bell on Render Completion" target:self action:@selector(settingChanged:)];
    [stackView addArrangedSubview:self.bellOnRenderCheckbox];
}

- (NSView *)createLabeledControl:(NSString *)label control:(NSView *)control {
    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;

    NSTextField *labelField = [NSTextField labelWithString:label];
    [labelField setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addArrangedSubview:labelField];

    [control setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addArrangedSubview:control];

    return row;
}

- (void)settingChanged:(id)sender {
    [self saveSettings];
}

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [self.spacingPopup selectItemAtIndex:[defaults integerForKey:@"GridSpacing"]];
    self.effectBackgroundsCheckbox.state = [defaults boolForKey:@"EffectBackgrounds"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.nodeValuesCheckbox.state = [defaults boolForKey:@"NodeValues"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.groupEffectIndicatorCheckbox.state = [defaults boolForKey:@"GroupEffectIndicator"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.snapToTimingCheckbox.state = [defaults boolForKey:@"SnapToTiming"] ? NSControlStateValueOn : NSControlStateValueOff;
    [self.doubleClickModePopup selectItemAtIndex:[defaults integerForKey:@"DoubleClickMode"]];
    self.smallWaveformCheckbox.state = [defaults boolForKey:@"SmallWaveform"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.transitionMarksCheckbox.state = [defaults boolForKey:@"TransitionMarks"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.hideColorUpdateWarningCheckbox.state = [defaults boolForKey:@"HideColorUpdateWarning"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.alternateTimingFormatCheckbox.state = [defaults boolForKey:@"AlternateTimingFormat"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.bellOnRenderCheckbox.state = [defaults boolForKey:@"BellOnRender"] ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [defaults setInteger:self.spacingPopup.indexOfSelectedItem forKey:@"GridSpacing"];
    [defaults setBool:(self.effectBackgroundsCheckbox.state == NSControlStateValueOn) forKey:@"EffectBackgrounds"];
    [defaults setBool:(self.nodeValuesCheckbox.state == NSControlStateValueOn) forKey:@"NodeValues"];
    [defaults setBool:(self.groupEffectIndicatorCheckbox.state == NSControlStateValueOn) forKey:@"GroupEffectIndicator"];
    [defaults setBool:(self.snapToTimingCheckbox.state == NSControlStateValueOn) forKey:@"SnapToTiming"];
    [defaults setInteger:self.doubleClickModePopup.indexOfSelectedItem forKey:@"DoubleClickMode"];
    [defaults setBool:(self.smallWaveformCheckbox.state == NSControlStateValueOn) forKey:@"SmallWaveform"];
    [defaults setBool:(self.transitionMarksCheckbox.state == NSControlStateValueOn) forKey:@"TransitionMarks"];
    [defaults setBool:(self.hideColorUpdateWarningCheckbox.state == NSControlStateValueOn) forKey:@"HideColorUpdateWarning"];
    [defaults setBool:(self.alternateTimingFormatCheckbox.state == NSControlStateValueOn) forKey:@"AlternateTimingFormat"];
    [defaults setBool:(self.bellOnRenderCheckbox.state == NSControlStateValueOn) forKey:@"BellOnRender"];

    [defaults synchronize];
}

@end
