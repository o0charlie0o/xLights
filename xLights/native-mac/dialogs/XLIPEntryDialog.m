/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLIPEntryDialog.h"
#include <arpa/inet.h>
#include <netdb.h>

@interface XLIPEntryDialog () <NSTextFieldDelegate>

@property (nonatomic, strong) NSTextField *ipField;
@property (nonatomic, strong) NSTextField *promptLabel;
@property (nonatomic, strong) NSTextField *validationLabel;

@end

@implementation XLIPEntryDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Enter IP Address";
        self.minWidth = 350;
        self.minHeight = 150;
        _ipAddress = @"";
        _allowsEmptyInput = YES;
        _allowsHostnames = YES;
        _promptText = @"IP Address:";
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Prompt label
    _promptLabel = [NSTextField labelWithString:_promptText];
    [stack addArrangedSubview:_promptLabel];

    // IP field
    _ipField = [XLBaseSheetController createTextField];
    _ipField.stringValue = _ipAddress ?: @"";
    _ipField.placeholderString = @"192.168.1.100";
    _ipField.delegate = self;
    [_ipField.widthAnchor constraintEqualToConstant:200].active = YES;
    [stack addArrangedSubview:_ipField];

    // Validation label
    _validationLabel = [NSTextField labelWithString:@""];
    _validationLabel.textColor = [NSColor systemRedColor];
    _validationLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:_validationLabel];

    return stack;
}

- (void)sheetDidLoad {
    // Make the IP field first responder
    [self.sheet makeFirstResponder:_ipField];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)notification {
    [self updateValidationLabel];
    [self updateOKButtonState];
}

- (void)updateValidationLabel {
    NSString *text = _ipField.stringValue;

    if (text.length == 0) {
        _validationLabel.stringValue = @"";
        return;
    }

    NSString *error = [self validateIPOrHostname:text];
    if (error) {
        _validationLabel.stringValue = error;
        _validationLabel.textColor = [NSColor systemRedColor];
    } else {
        _validationLabel.stringValue = @"Valid";
        _validationLabel.textColor = [NSColor systemGreenColor];
    }
}

#pragma mark - Validation

- (NSString *)validate {
    NSString *text = _ipField.stringValue;

    if (text.length == 0) {
        if (_allowsEmptyInput) {
            return nil;
        }
        return @"Please enter an IP address.";
    }

    return [self validateIPOrHostname:text];
}

- (NSString *)validateIPOrHostname:(NSString *)text {
    // Check for valid IPv4
    struct in_addr addr;
    if (inet_pton(AF_INET, [text UTF8String], &addr) == 1) {
        return nil; // Valid IPv4
    }

    // Check for valid IPv6
    struct in6_addr addr6;
    if (inet_pton(AF_INET6, [text UTF8String], &addr6) == 1) {
        return nil; // Valid IPv6
    }

    // Check for valid hostname
    if (_allowsHostnames) {
        if ([self isValidHostname:text]) {
            return nil;
        }
    }

    if (_allowsHostnames) {
        return @"Invalid IP address or hostname.";
    } else {
        return @"Invalid IP address.";
    }
}

- (BOOL)isValidHostname:(NSString *)hostname {
    // Basic hostname validation
    if (hostname.length == 0 || hostname.length > 253) {
        return NO;
    }

    // Check for valid characters
    NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];

    if ([hostname rangeOfCharacterFromSet:[validChars invertedSet]].location != NSNotFound) {
        return NO;
    }

    // Labels must be 1-63 characters
    NSArray<NSString *> *labels = [hostname componentsSeparatedByString:@"."];
    for (NSString *label in labels) {
        if (label.length == 0 || label.length > 63) {
            return NO;
        }
        // Labels cannot start or end with hyphen
        if ([label hasPrefix:@"-"] || [label hasSuffix:@"-"]) {
            return NO;
        }
    }

    return YES;
}

- (void)okClicked:(id)sender {
    _ipAddress = _ipField.stringValue;
    [super okClicked:sender];
}

@end
