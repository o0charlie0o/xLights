/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLUploadProgressSheet.h"
#import "../XLEngineBridge.h"

static const CGFloat kSheetWidth = 500.0;
static const CGFloat kSheetHeight = 400.0;
static const CGFloat kMargin = 16.0;
static const CGFloat kSmallMargin = 8.0;

#pragma mark - XLUploadResult Implementation

@implementation XLUploadResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _status = XLUploadStatusPending;
    }
    return self;
}

@end

#pragma mark - XLUploadProgressSheet Implementation

@interface XLUploadProgressSheet ()

@property (nonatomic, strong) NSProgressIndicator *progressBar;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *controllerLabel;
@property (nonatomic, strong) NSTextField *operationLabel;
@property (nonatomic, strong) NSScrollView *logScrollView;
@property (nonatomic, strong) NSTextView *logTextView;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSTextField *summaryLabel;
@property (nonatomic, strong) NSImageView *summaryIcon;

@property (nonatomic, strong) NSMutableArray<XLUploadResult *> *mutableResults;
@property (nonatomic, strong) NSArray<NSString *> *controllersToUpload;
@property (nonatomic, assign) NSUInteger currentControllerIndex;
@property (nonatomic, assign) BOOL uploadInProgress;
@property (nonatomic, assign) BOOL cancelled;

@end

@implementation XLUploadProgressSheet

#pragma mark - Initialization

- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge {
    NSWindow *sheetWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kSheetWidth, kSheetHeight)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered
                                                            defer:YES];
    sheetWindow.title = @"Upload Configuration";

    self = [super initWithWindow:sheetWindow];
    if (self) {
        _engineBridge = engineBridge;
        _mutableResults = [NSMutableArray array];
        _uploadInProgress = NO;
        _cancelled = NO;

        [self setupUI];
    }
    return self;
}

- (instancetype)init {
    return [self initWithEngineBridge:nil];
}

- (NSArray<XLUploadResult *> *)results {
    return [_mutableResults copy];
}

- (BOOL)isUploading {
    return _uploadInProgress;
}

- (BOOL)wasCancelled {
    return _cancelled;
}

#pragma mark - UI Setup

- (void)setupUI {
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;

    // Title / Status label
    _statusLabel = [NSTextField labelWithString:@"Preparing upload..."];
    _statusLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    _statusLabel.textColor = [NSColor labelColor];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_statusLabel];

    // Controller name label
    _controllerLabel = [NSTextField labelWithString:@""];
    _controllerLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    _controllerLabel.textColor = [NSColor secondaryLabelColor];
    _controllerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_controllerLabel];

    // Current operation label
    _operationLabel = [NSTextField labelWithString:@""];
    _operationLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    _operationLabel.textColor = [NSColor tertiaryLabelColor];
    _operationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_operationLabel];

    // Progress bar
    _progressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _progressBar.style = NSProgressIndicatorStyleBar;
    _progressBar.indeterminate = NO;
    _progressBar.minValue = 0.0;
    _progressBar.maxValue = 100.0;
    _progressBar.doubleValue = 0.0;
    _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_progressBar];

    // Log scroll view
    _logScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _logScrollView.hasVerticalScroller = YES;
    _logScrollView.hasHorizontalScroller = NO;
    _logScrollView.autohidesScrollers = YES;
    _logScrollView.borderType = NSBezelBorder;
    _logScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_logScrollView];

    // Log text view
    _logTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    _logTextView.editable = NO;
    _logTextView.selectable = YES;
    _logTextView.backgroundColor = [NSColor textBackgroundColor];
    _logTextView.textColor = [NSColor labelColor];
    _logTextView.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    _logTextView.textContainerInset = NSMakeSize(4, 4);
    [_logTextView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _logScrollView.documentView = _logTextView;

    // Summary section (hidden initially)
    _summaryIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _summaryIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _summaryIcon.hidden = YES;
    [contentView addSubview:_summaryIcon];

    _summaryLabel = [NSTextField labelWithString:@""];
    _summaryLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    _summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _summaryLabel.hidden = YES;
    [contentView addSubview:_summaryLabel];

    // Cancel button
    _cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelButtonClicked:)];
    _cancelButton.bezelStyle = NSBezelStyleRounded;
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    _cancelButton.keyEquivalent = @"\033"; // Escape key
    [contentView addSubview:_cancelButton];

    // Close button (hidden initially)
    _closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeButtonClicked:)];
    _closeButton.bezelStyle = NSBezelStyleRounded;
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _closeButton.keyEquivalent = @"\r"; // Return key
    _closeButton.hidden = YES;
    [contentView addSubview:_closeButton];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Status label
        [_statusLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:kMargin],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:kMargin],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kMargin],

        // Controller label
        [_controllerLabel.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:kSmallMargin],
        [_controllerLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:kMargin],
        [_controllerLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kMargin],

        // Operation label
        [_operationLabel.topAnchor constraintEqualToAnchor:_controllerLabel.bottomAnchor constant:4],
        [_operationLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:kMargin],
        [_operationLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kMargin],

        // Progress bar
        [_progressBar.topAnchor constraintEqualToAnchor:_operationLabel.bottomAnchor constant:kSmallMargin],
        [_progressBar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:kMargin],
        [_progressBar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kMargin],
        [_progressBar.heightAnchor constraintEqualToConstant:12],

        // Log scroll view
        [_logScrollView.topAnchor constraintEqualToAnchor:_progressBar.bottomAnchor constant:kMargin],
        [_logScrollView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:kMargin],
        [_logScrollView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kMargin],
        [_logScrollView.bottomAnchor constraintEqualToAnchor:_cancelButton.topAnchor constant:-kMargin],

        // Summary icon
        [_summaryIcon.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:kMargin],
        [_summaryIcon.bottomAnchor constraintEqualToAnchor:_cancelButton.topAnchor constant:-kSmallMargin],
        [_summaryIcon.widthAnchor constraintEqualToConstant:16],
        [_summaryIcon.heightAnchor constraintEqualToConstant:16],

        // Summary label
        [_summaryLabel.leadingAnchor constraintEqualToAnchor:_summaryIcon.trailingAnchor constant:6],
        [_summaryLabel.centerYAnchor constraintEqualToAnchor:_summaryIcon.centerYAnchor],
        [_summaryLabel.trailingAnchor constraintEqualToAnchor:_cancelButton.leadingAnchor constant:-kMargin],

        // Cancel button
        [_cancelButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kMargin],
        [_cancelButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-kMargin],
        [_cancelButton.widthAnchor constraintGreaterThanOrEqualToConstant:80],

        // Close button (same position as cancel)
        [_closeButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kMargin],
        [_closeButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-kMargin],
        [_closeButton.widthAnchor constraintGreaterThanOrEqualToConstant:80],
    ]];
}

#pragma mark - Public Methods

- (void)uploadToController:(NSString *)controllerName
         attachedToWindow:(NSWindow *)parentWindow {
    [self uploadToControllers:@[controllerName] attachedToWindow:parentWindow];
}

- (void)uploadToControllers:(NSArray<NSString *> *)controllerNames
          attachedToWindow:(NSWindow *)parentWindow {
    if (controllerNames.count == 0) {
        return;
    }

    _controllersToUpload = [controllerNames copy];
    _currentControllerIndex = 0;
    _cancelled = NO;
    _uploadInProgress = YES;

    [_mutableResults removeAllObjects];

    // Create result objects for each controller
    for (NSString *name in controllerNames) {
        XLUploadResult *result = [[XLUploadResult alloc] init];
        result.controllerName = name;

        // Get controller address
        NSDictionary *info = [_engineBridge getControllerInfo:name];
        result.controllerAddress = info[@"Address"] ?: info[@"ip"] ?: @"";

        [_mutableResults addObject:result];
    }

    // Reset UI
    [self resetUIForUpload];

    // Update status for multi-controller
    if (controllerNames.count > 1) {
        _statusLabel.stringValue = [NSString stringWithFormat:@"Uploading to %lu controllers...", (unsigned long)controllerNames.count];
    } else {
        _statusLabel.stringValue = @"Uploading configuration...";
    }

    // Show as sheet
    [parentWindow beginSheet:self.window completionHandler:nil];

    // Start upload process
    [self uploadNextController];
}

- (void)cancelUpload {
    if (!_uploadInProgress) return;

    _cancelled = YES;
    _cancelButton.enabled = NO;
    _statusLabel.stringValue = @"Cancelling...";
    _operationLabel.stringValue = @"Waiting for current operation to complete...";

    // Mark remaining controllers as cancelled
    for (NSUInteger i = _currentControllerIndex; i < _mutableResults.count; i++) {
        XLUploadResult *result = _mutableResults[i];
        if (result.status == XLUploadStatusPending || result.status == XLUploadStatusInProgress) {
            result.status = XLUploadStatusCancelled;
        }
    }

    [self appendLogMessage:@"Upload cancelled by user.\n" color:[NSColor systemOrangeColor]];
}

- (void)closeSheet {
    [self.window.sheetParent endSheet:self.window];
}

#pragma mark - Button Actions

- (void)cancelButtonClicked:(id)sender {
    if (_uploadInProgress) {
        [self cancelUpload];
    } else {
        [self closeSheet];
    }
}

- (void)closeButtonClicked:(id)sender {
    [self closeSheet];

    if ([_delegate respondsToSelector:@selector(uploadProgressSheet:didCompleteWithResults:)]) {
        [_delegate uploadProgressSheet:self didCompleteWithResults:self.results];
    }
}

#pragma mark - Upload Process

- (void)resetUIForUpload {
    _progressBar.doubleValue = 0.0;
    _controllerLabel.stringValue = @"";
    _operationLabel.stringValue = @"";
    _logTextView.string = @"";

    _cancelButton.enabled = YES;
    _cancelButton.hidden = NO;
    _closeButton.hidden = YES;

    _summaryIcon.hidden = YES;
    _summaryLabel.hidden = YES;
}

- (void)uploadNextController {
    if (_cancelled || _currentControllerIndex >= _controllersToUpload.count) {
        [self finishUpload];
        return;
    }

    NSString *controllerName = _controllersToUpload[_currentControllerIndex];
    XLUploadResult *result = _mutableResults[_currentControllerIndex];

    result.status = XLUploadStatusInProgress;

    // Update progress
    double progress = (double)_currentControllerIndex / (double)_controllersToUpload.count * 100.0;
    _progressBar.doubleValue = progress;

    // Update labels
    if (_controllersToUpload.count > 1) {
        _controllerLabel.stringValue = [NSString stringWithFormat:@"Controller %lu of %lu: %@",
                                        (unsigned long)(_currentControllerIndex + 1),
                                        (unsigned long)_controllersToUpload.count,
                                        controllerName];
    } else {
        _controllerLabel.stringValue = controllerName;
    }

    [self appendLogMessage:[NSString stringWithFormat:@"--- Uploading to %@ ---\n", controllerName]
                     color:[NSColor labelColor]];

    // Start with input upload
    [self uploadInputForController:controllerName result:result];
}

- (void)uploadInputForController:(NSString *)controllerName result:(XLUploadResult *)result {
    if (_cancelled) {
        result.status = XLUploadStatusCancelled;
        _currentControllerIndex++;
        [self uploadNextController];
        return;
    }

    _operationLabel.stringValue = @"Uploading input configuration...";
    [self appendLogMessage:@"  Uploading input configuration...\n" color:[NSColor secondaryLabelColor]];

    __weak typeof(self) weakSelf = self;

    [_engineBridge uploadInputToController:controllerName completion:^(BOOL success, NSString *message) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            result.inputMessage = message ?: @"";

            if (success) {
                [strongSelf appendLogMessage:[NSString stringWithFormat:@"  Input: %@\n", message ?: @"OK"]
                                       color:[NSColor systemGreenColor]];
            } else {
                [strongSelf appendLogMessage:[NSString stringWithFormat:@"  Input: %@\n", message ?: @"Failed"]
                                       color:[NSColor systemRedColor]];
            }

            // Continue with output upload
            [strongSelf uploadOutputForController:controllerName result:result inputSuccess:success];
        });
    }];
}

- (void)uploadOutputForController:(NSString *)controllerName
                           result:(XLUploadResult *)result
                     inputSuccess:(BOOL)inputSuccess {
    if (_cancelled) {
        result.status = XLUploadStatusCancelled;
        _currentControllerIndex++;
        [self uploadNextController];
        return;
    }

    _operationLabel.stringValue = @"Uploading output configuration...";
    [self appendLogMessage:@"  Uploading output configuration...\n" color:[NSColor secondaryLabelColor]];

    __weak typeof(self) weakSelf = self;

    [_engineBridge uploadOutputToController:controllerName completion:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            result.outputMessage = message ?: @"";

            if (success) {
                [strongSelf appendLogMessage:[NSString stringWithFormat:@"  Output: %@\n", message ?: @"OK"]
                                       color:[NSColor systemGreenColor]];
            } else {
                [strongSelf appendLogMessage:[NSString stringWithFormat:@"  Output: %@\n", message ?: @"Failed"]
                                       color:[NSColor systemRedColor]];
            }

            // Determine overall status
            if (inputSuccess && success) {
                result.status = XLUploadStatusSuccess;
                [strongSelf appendLogMessage:@"  Done.\n\n" color:[NSColor labelColor]];
            } else {
                result.status = XLUploadStatusFailed;
                result.errorMessage = [NSString stringWithFormat:@"Input: %@, Output: %@",
                                       inputSuccess ? @"OK" : (result.inputMessage ?: @"Failed"),
                                       success ? @"OK" : (result.outputMessage ?: @"Failed")];
                [strongSelf appendLogMessage:@"  Upload failed.\n\n" color:[NSColor systemRedColor]];
            }

            // Move to next controller
            strongSelf.currentControllerIndex++;
            [strongSelf uploadNextController];
        });
    }];
}

- (void)finishUpload {
    _uploadInProgress = NO;
    _progressBar.doubleValue = 100.0;

    // Calculate summary
    NSUInteger successCount = 0;
    NSUInteger failedCount = 0;
    NSUInteger cancelledCount = 0;

    for (XLUploadResult *result in _mutableResults) {
        switch (result.status) {
            case XLUploadStatusSuccess:
                successCount++;
                break;
            case XLUploadStatusFailed:
                failedCount++;
                break;
            case XLUploadStatusCancelled:
                cancelledCount++;
                break;
            default:
                break;
        }
    }

    // Update UI for completion
    _cancelButton.hidden = YES;
    _closeButton.hidden = NO;

    _operationLabel.stringValue = @"";
    _summaryIcon.hidden = NO;
    _summaryLabel.hidden = NO;

    if (_cancelled) {
        _statusLabel.stringValue = @"Upload Cancelled";
        _summaryIcon.image = [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle.fill"
                                      accessibilityDescription:@"Cancelled"];
        _summaryIcon.contentTintColor = [NSColor systemOrangeColor];
        _summaryLabel.stringValue = [NSString stringWithFormat:@"%lu completed, %lu cancelled",
                                     (unsigned long)successCount, (unsigned long)cancelledCount];
        _summaryLabel.textColor = [NSColor systemOrangeColor];

        if ([_delegate respondsToSelector:@selector(uploadProgressSheetDidCancel:)]) {
            [_delegate uploadProgressSheetDidCancel:self];
        }
    } else if (failedCount == 0) {
        _statusLabel.stringValue = @"Upload Complete";
        _summaryIcon.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill"
                                      accessibilityDescription:@"Success"];
        _summaryIcon.contentTintColor = [NSColor systemGreenColor];

        if (_controllersToUpload.count == 1) {
            _summaryLabel.stringValue = @"Configuration uploaded successfully.";
        } else {
            _summaryLabel.stringValue = [NSString stringWithFormat:@"All %lu controllers uploaded successfully.",
                                         (unsigned long)successCount];
        }
        _summaryLabel.textColor = [NSColor systemGreenColor];
    } else if (successCount == 0) {
        _statusLabel.stringValue = @"Upload Failed";
        _summaryIcon.image = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill"
                                      accessibilityDescription:@"Failed"];
        _summaryIcon.contentTintColor = [NSColor systemRedColor];

        if (_controllersToUpload.count == 1) {
            _summaryLabel.stringValue = @"Failed to upload configuration.";
        } else {
            _summaryLabel.stringValue = [NSString stringWithFormat:@"All %lu controllers failed.",
                                         (unsigned long)failedCount];
        }
        _summaryLabel.textColor = [NSColor systemRedColor];
    } else {
        _statusLabel.stringValue = @"Upload Completed with Errors";
        _summaryIcon.image = [NSImage imageWithSystemSymbolName:@"exclamationmark.circle.fill"
                                      accessibilityDescription:@"Partial failure"];
        _summaryIcon.contentTintColor = [NSColor systemYellowColor];
        _summaryLabel.stringValue = [NSString stringWithFormat:@"%lu succeeded, %lu failed",
                                     (unsigned long)successCount, (unsigned long)failedCount];
        _summaryLabel.textColor = [NSColor systemYellowColor];
    }

    [self appendLogMessage:@"=== Upload Complete ===\n" color:[NSColor labelColor]];
}

#pragma mark - Log Output

- (void)appendLogMessage:(NSString *)message color:(NSColor *)color {
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: color ?: [NSColor labelColor]
    };

    NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:message attributes:attrs];

    [[_logTextView textStorage] appendAttributedString:attrString];

    // Scroll to bottom
    [_logTextView scrollRangeToVisible:NSMakeRange(_logTextView.string.length, 0)];
}

@end
