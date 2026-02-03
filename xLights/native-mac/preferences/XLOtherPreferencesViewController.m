//
//  XLOtherPreferencesViewController.m
//  xLights
//

#import "XLOtherPreferencesViewController.h"

// Import the native UI feature flag functions
extern int XLIsNativeUIEnabled(void);
extern void XLSetNativeUIEnabled(int enabled);

static NSString *const kXLNativeUIEnabledKey = @"XLNativeUIEnabled";

@interface XLOtherPreferencesViewController ()

@property (nonatomic, strong) NSButton *nativeUICheckbox;

@end

@implementation XLOtherPreferencesViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)];

    // Create a stack view for organized layout
    NSStackView *stackView = [[NSStackView alloc] initWithFrame:NSMakeRect(20, 20, 560, 260)];
    stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    stackView.alignment = NSLayoutAttributeLeading;
    stackView.spacing = 16;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stackView];

    // Constrain stack view to parent
    [NSLayoutConstraint activateConstraints:@[
        [stackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [stackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [stackView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],
    ]];

    // Section header: Experimental Features
    NSTextField *sectionHeader = [NSTextField labelWithString:@"Experimental Features"];
    sectionHeader.font = [NSFont boldSystemFontOfSize:13];
    [stackView addArrangedSubview:sectionHeader];

    // Native UI checkbox
    self.nativeUICheckbox = [NSButton checkboxWithTitle:@"Enable native macOS UI (requires restart)"
                                                 target:self
                                                 action:@selector(nativeUICheckboxChanged:)];
    self.nativeUICheckbox.state = XLIsNativeUIEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
    [stackView addArrangedSubview:self.nativeUICheckbox];

    // Description label
    NSTextField *descriptionLabel = [NSTextField wrappingLabelWithString:
        @"When enabled, xLights will launch an experimental native macOS user interface alongside the standard wxWidgets interface. This is a preview feature and may not include all functionality. You can also use the -nativeUI command-line flag to enable this temporarily."];
    descriptionLabel.textColor = [NSColor secondaryLabelColor];
    descriptionLabel.font = [NSFont systemFontOfSize:11];
    descriptionLabel.preferredMaxLayoutWidth = 520;
    [stackView addArrangedSubview:descriptionLabel];

    // Spacer
    NSView *spacer = [[NSView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer.heightAnchor constraintGreaterThanOrEqualToConstant:20].active = YES;
    [stackView addArrangedSubview:spacer];

    // Other settings header (placeholder for future settings)
    NSTextField *otherHeader = [NSTextField labelWithString:@"Other Settings"];
    otherHeader.font = [NSFont boldSystemFontOfSize:13];
    [stackView addArrangedSubview:otherHeader];

    NSTextField *placeholderLabel = [NSTextField labelWithString:@"Additional settings will appear here."];
    placeholderLabel.textColor = [NSColor tertiaryLabelColor];
    [stackView addArrangedSubview:placeholderLabel];
}

- (void)nativeUICheckboxChanged:(NSButton *)sender {
    BOOL enabled = (sender.state == NSControlStateValueOn);
    XLSetNativeUIEnabled(enabled ? 1 : 0);

    // Show restart reminder
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = enabled ? @"Native UI Enabled" : @"Native UI Disabled";
    alert.informativeText = @"Please restart xLights for this change to take effect.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end
