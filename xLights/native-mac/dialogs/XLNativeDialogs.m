/***************************************************************
 * Name:      XLNativeDialogs.m
 * Purpose:   Native macOS dialog utilities for xLights
 * Author:    xLights Team
 * Created:   2026-02-03
 * Copyright: xLights (https://xlights.org)
 * License:   GPLv3
 **************************************************************/

#import "XLNativeDialogs.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#pragma mark - XLProgressController Private

@interface XLProgressController ()

@property (nonatomic, strong) NSWindow *progressWindow;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, weak) NSWindow *parentWindow;
@property (nonatomic, assign) BOOL wasCancelled;
@property (nonatomic, assign) NSUInteger maximum;

@end

#pragma mark - XLProgressController Implementation

@implementation XLProgressController

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
                      maximum:(NSUInteger)maximum
                    canCancel:(BOOL)canCancel
                 parentWindow:(NSWindow *)parentWindow {
    self = [super init];
    if (self) {
        _maximum = maximum;
        _wasCancelled = NO;
        _parentWindow = parentWindow;

        // Create the window
        NSRect windowRect = NSMakeRect(0, 0, 450, 130);
        _progressWindow = [[NSWindow alloc] initWithContentRect:windowRect
                                                      styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered
                                                          defer:YES];
        _progressWindow.title = title;
        _progressWindow.releasedWhenClosed = NO;

        NSView *contentView = _progressWindow.contentView;

        // Create message label
        _messageLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 80, 410, 30)];
        _messageLabel.stringValue = message;
        _messageLabel.bordered = NO;
        _messageLabel.editable = NO;
        _messageLabel.backgroundColor = NSColor.clearColor;
        _messageLabel.font = [NSFont systemFontOfSize:13];
        _messageLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [contentView addSubview:_messageLabel];

        // Create progress indicator
        _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 50, 410, 20)];
        _progressIndicator.style = NSProgressIndicatorStyleBar;
        if (maximum == 0) {
            _progressIndicator.indeterminate = YES;
            [_progressIndicator startAnimation:nil];
        } else {
            _progressIndicator.indeterminate = NO;
            _progressIndicator.minValue = 0;
            _progressIndicator.maxValue = (double)maximum;
            _progressIndicator.doubleValue = 0;
        }
        [contentView addSubview:_progressIndicator];

        // Create cancel button if allowed
        if (canCancel) {
            _cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(350, 10, 80, 30)];
            _cancelButton.title = @"Cancel";
            _cancelButton.bezelStyle = NSBezelStyleRounded;
            _cancelButton.target = self;
            _cancelButton.action = @selector(cancelClicked:);
            [contentView addSubview:_cancelButton];
        }

        // Show the window
        if (parentWindow) {
            [_progressWindow center];
            NSRect parentFrame = parentWindow.frame;
            NSRect progressFrame = _progressWindow.frame;
            CGFloat x = NSMidX(parentFrame) - progressFrame.size.width / 2;
            CGFloat y = NSMidY(parentFrame) - progressFrame.size.height / 2;
            [_progressWindow setFrameOrigin:NSMakePoint(x, y)];
        } else {
            [_progressWindow center];
        }
        [_progressWindow makeKeyAndOrderFront:nil];
    }
    return self;
}

- (void)cancelClicked:(id)sender {
    _wasCancelled = YES;
}

- (void)updateProgress:(NSUInteger)value {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.progressIndicator.indeterminate) {
            self.progressIndicator.doubleValue = (double)value;
        }
    });
}

- (void)updateMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.messageLabel.stringValue = message;
    });
}

- (void)updateProgress:(NSUInteger)value message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.progressIndicator.indeterminate) {
            self.progressIndicator.doubleValue = (double)value;
        }
        self.messageLabel.stringValue = message;
    });
}

- (void)setIndeterminate:(BOOL)indeterminate {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressIndicator.indeterminate = indeterminate;
        if (indeterminate) {
            [self.progressIndicator startAnimation:nil];
        } else {
            [self.progressIndicator stopAnimation:nil];
        }
    });
}

- (void)pulse {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progressIndicator.indeterminate) {
            // For indeterminate mode, the animation handles pulsing
        } else {
            // For determinate mode, increment slightly
            double current = self.progressIndicator.doubleValue;
            double max = self.progressIndicator.maxValue;
            if (current < max) {
                self.progressIndicator.doubleValue = current + 1;
            }
        }
    });
}

- (void)close {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressIndicator stopAnimation:nil];
        [self.progressWindow close];
    });
}

@end

#pragma mark - XLMultiChoiceController Implementation

@implementation XLMultiChoiceController

- (instancetype)initWithChoices:(NSArray<NSString *> *)choices
             initialSelections:(NSArray<NSNumber *> *)initialSelections {
    self = [super init];
    if (self) {
        _choices = [choices copy];
        _selectedIndices = [NSMutableIndexSet indexSet];

        for (NSNumber *index in initialSelections) {
            NSUInteger idx = index.unsignedIntegerValue;
            if (idx < choices.count) {
                [_selectedIndices addIndex:idx];
            }
        }
    }
    return self;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.choices.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *identifier = tableColumn.identifier;
    NSTableCellView *cellView = [tableView makeViewWithIdentifier:identifier owner:self];

    if (!cellView) {
        cellView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 24)];
        cellView.identifier = identifier;

        if ([identifier isEqualToString:@"CheckColumn"]) {
            NSButton *checkbox = [[NSButton alloc] initWithFrame:NSMakeRect(2, 2, 20, 20)];
            checkbox.buttonType = NSButtonTypeSwitch;
            checkbox.title = @"";
            checkbox.target = self;
            checkbox.action = @selector(checkboxClicked:);
            [cellView addSubview:checkbox];
        } else {
            NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 20)];
            textField.bordered = NO;
            textField.editable = NO;
            textField.backgroundColor = NSColor.clearColor;
            cellView.textField = textField;
            [cellView addSubview:textField];
        }
    }

    if ([identifier isEqualToString:@"CheckColumn"]) {
        NSButton *checkbox = cellView.subviews.firstObject;
        checkbox.state = [self.selectedIndices containsIndex:row] ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.tag = row;
    } else {
        cellView.textField.stringValue = self.choices[row];
    }

    return cellView;
}

- (void)checkboxClicked:(NSButton *)sender {
    NSInteger row = sender.tag;
    if (sender.state == NSControlStateValueOn) {
        [self.selectedIndices addIndex:row];
    } else {
        [self.selectedIndices removeIndex:row];
    }
}

@end

#pragma mark - XLNativeDialogs Implementation

@implementation XLNativeDialogs

#pragma mark - Alert Dialogs

+ (XLAlertResult)showAlertWithTitle:(NSString *)title
                            message:(NSString *)message
                              style:(XLAlertStyle)style
                            buttons:(XLAlertButtons)buttons
                       parentWindow:(NSWindow *)parentWindow {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;

    // Set alert style
    switch (style) {
        case XLAlertStyleInformational:
            alert.alertStyle = NSAlertStyleInformational;
            break;
        case XLAlertStyleWarning:
            alert.alertStyle = NSAlertStyleWarning;
            break;
        case XLAlertStyleCritical:
            alert.alertStyle = NSAlertStyleCritical;
            break;
        case XLAlertStyleQuestion:
            alert.alertStyle = NSAlertStyleInformational;
            break;
    }

    // Add buttons (macOS order: rightmost is default/first added)
    switch (buttons) {
        case XLAlertButtonsOK:
            [alert addButtonWithTitle:@"OK"];
            break;
        case XLAlertButtonsOKCancel:
            [alert addButtonWithTitle:@"OK"];
            [alert addButtonWithTitle:@"Cancel"];
            break;
        case XLAlertButtonsYesNo:
            [alert addButtonWithTitle:@"Yes"];
            [alert addButtonWithTitle:@"No"];
            break;
        case XLAlertButtonsYesNoCancel:
            [alert addButtonWithTitle:@"Yes"];
            [alert addButtonWithTitle:@"No"];
            [alert addButtonWithTitle:@"Cancel"];
            break;
    }

    // Show the alert
    NSModalResponse response;
    if (parentWindow) {
        __block NSModalResponse blockResponse = NSModalResponseCancel;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [alert beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse returnCode) {
            blockResponse = returnCode;
            dispatch_semaphore_signal(semaphore);
        }];

        // Run the modal loop until the sheet is dismissed
        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        response = blockResponse;
    } else {
        response = [alert runModal];
    }

    // Convert response to XLAlertResult
    switch (buttons) {
        case XLAlertButtonsOK:
            return XLAlertResultOK;

        case XLAlertButtonsOKCancel:
            return (response == NSAlertFirstButtonReturn) ? XLAlertResultOK : XLAlertResultCancel;

        case XLAlertButtonsYesNo:
            return (response == NSAlertFirstButtonReturn) ? XLAlertResultYes : XLAlertResultNo;

        case XLAlertButtonsYesNoCancel:
            if (response == NSAlertFirstButtonReturn) return XLAlertResultYes;
            if (response == NSAlertSecondButtonReturn) return XLAlertResultNo;
            return XLAlertResultCancel;
    }

    return XLAlertResultCancel;
}

+ (void)showErrorWithTitle:(NSString *)title
                   message:(NSString *)message
              parentWindow:(NSWindow *)parentWindow {
    [self showAlertWithTitle:title
                     message:message
                       style:XLAlertStyleCritical
                     buttons:XLAlertButtonsOK
                parentWindow:parentWindow];
}

+ (void)showWarningWithTitle:(NSString *)title
                     message:(NSString *)message
                parentWindow:(NSWindow *)parentWindow {
    [self showAlertWithTitle:title
                     message:message
                       style:XLAlertStyleWarning
                     buttons:XLAlertButtonsOK
                parentWindow:parentWindow];
}

+ (void)showInfoWithTitle:(NSString *)title
                  message:(NSString *)message
             parentWindow:(NSWindow *)parentWindow {
    [self showAlertWithTitle:title
                     message:message
                       style:XLAlertStyleInformational
                     buttons:XLAlertButtonsOK
                parentWindow:parentWindow];
}

+ (BOOL)showConfirmationWithTitle:(NSString *)title
                          message:(NSString *)message
                     parentWindow:(NSWindow *)parentWindow {
    XLAlertResult result = [self showAlertWithTitle:title
                                            message:message
                                              style:XLAlertStyleQuestion
                                            buttons:XLAlertButtonsYesNo
                                       parentWindow:parentWindow];
    return result == XLAlertResultYes;
}

+ (XLAlertResult)showConfirmationWithCancelTitle:(NSString *)title
                                         message:(NSString *)message
                                    parentWindow:(NSWindow *)parentWindow {
    return [self showAlertWithTitle:title
                            message:message
                              style:XLAlertStyleQuestion
                            buttons:XLAlertButtonsYesNoCancel
                       parentWindow:parentWindow];
}

#pragma mark - File Dialogs

+ (NSArray<NSURL *> *)showOpenPanelWithTitle:(NSString *)title
                                   directory:(NSString *)directory
                                   fileTypes:(NSArray<NSString *> *)fileTypes
                               allowMultiple:(BOOL)allowMultiple
                                parentWindow:(NSWindow *)parentWindow {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = title;
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = allowMultiple;
    panel.canCreateDirectories = NO;

    if (directory) {
        panel.directoryURL = [NSURL fileURLWithPath:directory];
    }

    if (fileTypes && fileTypes.count > 0) {
        if (@available(macOS 11.0, *)) {
            NSMutableArray<UTType *> *utTypes = [NSMutableArray array];
            for (NSString *ext in fileTypes) {
                UTType *type = [UTType typeWithFilenameExtension:ext];
                if (type) {
                    [utTypes addObject:type];
                }
            }
            if (utTypes.count > 0) {
                panel.allowedContentTypes = utTypes;
            }
        } else {
            panel.allowedFileTypes = fileTypes;
        }
    }

    NSModalResponse response;
    if (parentWindow) {
        __block NSModalResponse blockResponse = NSModalResponseCancel;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [panel beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse result) {
            blockResponse = result;
            dispatch_semaphore_signal(semaphore);
        }];

        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        response = blockResponse;
    } else {
        response = [panel runModal];
    }

    if (response == NSModalResponseOK) {
        return panel.URLs;
    }
    return nil;
}

+ (NSURL *)showSavePanelWithTitle:(NSString *)title
                        directory:(NSString *)directory
                      defaultName:(NSString *)defaultName
                        fileTypes:(NSArray<NSString *> *)fileTypes
                     parentWindow:(NSWindow *)parentWindow {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = title;
    panel.canCreateDirectories = YES;

    if (directory) {
        panel.directoryURL = [NSURL fileURLWithPath:directory];
    }

    if (defaultName) {
        panel.nameFieldStringValue = defaultName;
    }

    if (fileTypes && fileTypes.count > 0) {
        if (@available(macOS 11.0, *)) {
            NSMutableArray<UTType *> *utTypes = [NSMutableArray array];
            for (NSString *ext in fileTypes) {
                UTType *type = [UTType typeWithFilenameExtension:ext];
                if (type) {
                    [utTypes addObject:type];
                }
            }
            if (utTypes.count > 0) {
                panel.allowedContentTypes = utTypes;
            }
        } else {
            panel.allowedFileTypes = fileTypes;
        }
    }

    NSModalResponse response;
    if (parentWindow) {
        __block NSModalResponse blockResponse = NSModalResponseCancel;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [panel beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse result) {
            blockResponse = result;
            dispatch_semaphore_signal(semaphore);
        }];

        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        response = blockResponse;
    } else {
        response = [panel runModal];
    }

    if (response == NSModalResponseOK) {
        return panel.URL;
    }
    return nil;
}

+ (NSURL *)showDirectoryPanelWithTitle:(NSString *)title
                             directory:(NSString *)directory
                  canCreateDirectories:(BOOL)canCreateDirectories
                          parentWindow:(NSWindow *)parentWindow {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = title;
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = canCreateDirectories;

    if (directory) {
        panel.directoryURL = [NSURL fileURLWithPath:directory];
    }

    NSModalResponse response;
    if (parentWindow) {
        __block NSModalResponse blockResponse = NSModalResponseCancel;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [panel beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse result) {
            blockResponse = result;
            dispatch_semaphore_signal(semaphore);
        }];

        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        response = blockResponse;
    } else {
        response = [panel runModal];
    }

    if (response == NSModalResponseOK) {
        return panel.URL;
    }
    return nil;
}

#pragma mark - Text Input Dialogs

+ (NSString *)showTextInputWithTitle:(NSString *)title
                             message:(NSString *)message
                        defaultValue:(NSString *)defaultValue
                         placeholder:(NSString *)placeholder
                        parentWindow:(NSWindow *)parentWindow {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleInformational;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    // Create text field as accessory view
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    textField.stringValue = defaultValue ?: @"";
    if (placeholder) {
        textField.placeholderString = placeholder;
    }
    alert.accessoryView = textField;

    // Make the text field first responder
    [alert.window setInitialFirstResponder:textField];

    NSModalResponse response;
    if (parentWindow) {
        __block NSModalResponse blockResponse = NSModalResponseCancel;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [alert beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse returnCode) {
            blockResponse = returnCode;
            dispatch_semaphore_signal(semaphore);
        }];

        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        response = blockResponse;
    } else {
        response = [alert runModal];
    }

    if (response == NSAlertFirstButtonReturn) {
        return textField.stringValue;
    }
    return nil;
}

+ (NSString *)showSecureTextInputWithTitle:(NSString *)title
                                   message:(NSString *)message
                               placeholder:(NSString *)placeholder
                              parentWindow:(NSWindow *)parentWindow {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleInformational;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    // Create secure text field as accessory view
    NSSecureTextField *textField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    if (placeholder) {
        textField.placeholderString = placeholder;
    }
    alert.accessoryView = textField;

    [alert.window setInitialFirstResponder:textField];

    NSModalResponse response;
    if (parentWindow) {
        __block NSModalResponse blockResponse = NSModalResponseCancel;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [alert beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse returnCode) {
            blockResponse = returnCode;
            dispatch_semaphore_signal(semaphore);
        }];

        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        response = blockResponse;
    } else {
        response = [alert runModal];
    }

    if (response == NSAlertFirstButtonReturn) {
        return textField.stringValue;
    }
    return nil;
}

#pragma mark - Choice Dialogs

+ (NSInteger)showSingleChoiceWithTitle:(NSString *)title
                               message:(NSString *)message
                               choices:(NSArray<NSString *> *)choices
                      defaultSelection:(NSInteger)defaultSelection
                          parentWindow:(NSWindow *)parentWindow {
    if (choices.count == 0) return -1;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleInformational;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    // Create popup button as accessory view
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 300, 26) pullsDown:NO];
    [popup addItemsWithTitles:choices];

    if (defaultSelection >= 0 && defaultSelection < (NSInteger)choices.count) {
        [popup selectItemAtIndex:defaultSelection];
    }

    alert.accessoryView = popup;

    NSModalResponse response;
    if (parentWindow) {
        __block NSModalResponse blockResponse = NSModalResponseCancel;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [alert beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse returnCode) {
            blockResponse = returnCode;
            dispatch_semaphore_signal(semaphore);
        }];

        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        response = blockResponse;
    } else {
        response = [alert runModal];
    }

    if (response == NSAlertFirstButtonReturn) {
        return popup.indexOfSelectedItem;
    }
    return -1;
}

+ (NSString *)showSingleChoiceStringWithTitle:(NSString *)title
                                      message:(NSString *)message
                                      choices:(NSArray<NSString *> *)choices
                             defaultSelection:(NSInteger)defaultSelection
                                 parentWindow:(NSWindow *)parentWindow {
    NSInteger index = [self showSingleChoiceWithTitle:title
                                              message:message
                                              choices:choices
                                     defaultSelection:defaultSelection
                                         parentWindow:parentWindow];
    if (index >= 0 && index < (NSInteger)choices.count) {
        return choices[index];
    }
    return nil;
}

+ (NSArray<NSNumber *> *)showMultiChoiceWithTitle:(NSString *)title
                                          message:(NSString *)message
                                          choices:(NSArray<NSString *> *)choices
                               initialSelections:(NSArray<NSNumber *> *)initialSelections
                                     parentWindow:(NSWindow *)parentWindow {
    if (choices.count == 0) return nil;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleInformational;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    // Create table view in scroll view as accessory view
    XLMultiChoiceController *controller = [[XLMultiChoiceController alloc] initWithChoices:choices
                                                                        initialSelections:initialSelections];

    // Create scroll view with table
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.borderType = NSBezelBorder;

    NSTableView *tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    tableView.dataSource = controller;
    tableView.delegate = controller;
    tableView.headerView = nil;

    // Add checkbox column
    NSTableColumn *checkColumn = [[NSTableColumn alloc] initWithIdentifier:@"CheckColumn"];
    checkColumn.width = 30;
    checkColumn.minWidth = 30;
    checkColumn.maxWidth = 30;
    [tableView addTableColumn:checkColumn];

    // Add text column
    NSTableColumn *textColumn = [[NSTableColumn alloc] initWithIdentifier:@"TextColumn"];
    textColumn.width = 250;
    [tableView addTableColumn:textColumn];

    scrollView.documentView = tableView;
    alert.accessoryView = scrollView;

    NSModalResponse response;
    if (parentWindow) {
        __block NSModalResponse blockResponse = NSModalResponseCancel;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [alert beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse returnCode) {
            blockResponse = returnCode;
            dispatch_semaphore_signal(semaphore);
        }];

        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        response = blockResponse;
    } else {
        response = [alert runModal];
    }

    if (response == NSAlertFirstButtonReturn) {
        NSMutableArray<NSNumber *> *result = [NSMutableArray array];
        [controller.selectedIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            [result addObject:@(idx)];
        }];
        return result;
    }
    return nil;
}

#pragma mark - Progress Dialogs

+ (XLProgressController *)showProgressWithTitle:(NSString *)title
                                        message:(NSString *)message
                                        maximum:(NSUInteger)maximum
                                      canCancel:(BOOL)canCancel
                                   parentWindow:(NSWindow *)parentWindow {
    return [[XLProgressController alloc] initWithTitle:title
                                               message:message
                                               maximum:maximum
                                             canCancel:canCancel
                                          parentWindow:parentWindow];
}

#pragma mark - Color Dialogs

+ (NSColor *)showColorPickerWithInitialColor:(NSColor *)initialColor
                                parentWindow:(NSWindow *)parentWindow {
    NSColorPanel *colorPanel = [NSColorPanel sharedColorPanel];

    if (initialColor) {
        colorPanel.color = initialColor;
    }

    // Create a modal session approach for color panel
    __block NSColor *selectedColor = nil;
    __block BOOL panelClosed = NO;

    // Store initial color to detect changes
    NSColor *originalColor = colorPanel.color;

    // Show the color panel
    [colorPanel makeKeyAndOrderFront:nil];

    // Create custom buttons panel
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Select Color";
    alert.informativeText = @"Use the color picker to select a color, then click OK.";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    // Run modal for the alert while color panel is open
    NSModalResponse response;
    if (parentWindow) {
        __block NSModalResponse blockResponse = NSModalResponseCancel;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [alert beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse returnCode) {
            blockResponse = returnCode;
            dispatch_semaphore_signal(semaphore);
        }];

        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        response = blockResponse;
    } else {
        response = [alert runModal];
    }

    [colorPanel close];

    if (response == NSAlertFirstButtonReturn) {
        return colorPanel.color;
    }
    return nil;
}

#pragma mark - Number Entry Dialogs

+ (BOOL)showNumberEntryWithTitle:(NSString *)title
                         message:(NSString *)message
                          prompt:(NSString *)prompt
                           value:(NSInteger)value
                             min:(NSInteger)min
                             max:(NSInteger)max
                    parentWindow:(NSWindow *)parentWindow
                        outValue:(NSInteger *)outValue {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleInformational;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    // Create a view with label and stepper/text field
    NSView *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 30)];

    // Add prompt label
    NSTextField *promptLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 5, 100, 20)];
    promptLabel.stringValue = prompt ?: @"";
    promptLabel.bordered = NO;
    promptLabel.editable = NO;
    promptLabel.backgroundColor = NSColor.clearColor;
    [accessoryView addSubview:promptLabel];

    // Add number text field
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(105, 3, 100, 24)];
    textField.integerValue = value;
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.minimum = @(min);
    formatter.maximum = @(max);
    formatter.allowsFloats = NO;
    textField.formatter = formatter;
    [accessoryView addSubview:textField];

    // Add stepper
    NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSMakeRect(210, 3, 19, 24)];
    stepper.minValue = min;
    stepper.maxValue = max;
    stepper.integerValue = value;
    stepper.increment = 1;
    stepper.valueWraps = NO;
    stepper.autorepeat = YES;

    // Bind stepper and text field
    [textField bind:NSValueBinding toObject:stepper withKeyPath:@"integerValue" options:nil];

    [accessoryView addSubview:stepper];

    alert.accessoryView = accessoryView;
    [alert.window setInitialFirstResponder:textField];

    NSModalResponse response;
    if (parentWindow) {
        __block NSModalResponse blockResponse = NSModalResponseCancel;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [alert beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse returnCode) {
            blockResponse = returnCode;
            dispatch_semaphore_signal(semaphore);
        }];

        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        response = blockResponse;
    } else {
        response = [alert runModal];
    }

    if (response == NSAlertFirstButtonReturn) {
        if (outValue) {
            *outValue = textField.integerValue;
        }
        return YES;
    }
    return NO;
}

#pragma mark - Save Changes Dialogs

+ (NSInteger)showSaveChangesDialogForDocument:(NSString *)documentName
                                 parentWindow:(NSWindow *)parentWindow {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Do you want to save changes to \"%@\"?", documentName];
    alert.informativeText = @"Your changes will be lost if you don't save them.";
    alert.alertStyle = NSAlertStyleWarning;

    // macOS standard button order: Save (default), Don't Save, Cancel
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Don't Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSModalResponse response;
    if (parentWindow) {
        __block NSModalResponse blockResponse = NSModalResponseCancel;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [alert beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse returnCode) {
            blockResponse = returnCode;
            dispatch_semaphore_signal(semaphore);
        }];

        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) != 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        response = blockResponse;
    } else {
        response = [alert runModal];
    }

    // Map response to return values: 1=Save, 0=Don't Save, -1=Cancel
    if (response == NSAlertFirstButtonReturn) {
        return 1;  // Save
    } else if (response == NSAlertSecondButtonReturn) {
        return 0;  // Don't Save
    } else {
        return -1; // Cancel
    }
}

@end
