/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLConvertDialogs.h"
#import "../XLEngineBridge.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const CGFloat kLabelWidth = 140.0;

#pragma mark - XLConvertDialog

@interface XLConvertDialog () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSPopUpButton *formatPopup;
@property (nonatomic, strong) NSTextField *filePathField;
@property (nonatomic, strong) NSButton *browseButton;
@property (nonatomic, strong) NSButton *mapEmptyCheckbox;
@property (nonatomic, strong) NSButton *offAtEndCheckbox;
@property (nonatomic, strong) NSButton *showMappingCheckbox;
@property (nonatomic, strong) NSButton *lorNoNetworkCheckbox;
@property (nonatomic, strong) NSPopUpButton *lorResolutionPopup;
@property (nonatomic, strong) NSTextView *statusTextView;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSButton *convertButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, copy) void (^completionHandler)(void);

@end

@implementation XLConvertDialog

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 550, 500)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Convert Sequence";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    NSStackView *mainStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.alignment = NSLayoutAttributeLeading;
    mainStack.spacing = 12;
    mainStack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);

    [contentView addSubview:mainStack];
    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [mainStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [mainStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [mainStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];

    // File selection
    NSStackView *fileRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    fileRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fileRow.spacing = 8;

    NSTextField *fileLabel = [NSTextField labelWithString:@"File to Convert:"];
    fileLabel.alignment = NSTextAlignmentRight;
    [fileLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _filePathField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _filePathField.editable = NO;
    _filePathField.placeholderString = @"Select a file...";
    [_filePathField.widthAnchor constraintGreaterThanOrEqualToConstant:250].active = YES;

    _browseButton = [NSButton buttonWithTitle:@"Choose File..." target:self action:@selector(browseFile:)];

    [fileRow addArrangedSubview:fileLabel];
    [fileRow addArrangedSubview:_filePathField];
    [fileRow addArrangedSubview:_browseButton];
    [mainStack addArrangedSubview:fileRow];

    // Output format
    _formatPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_formatPopup addItemWithTitle:@"xLights Sequence (.xsq)"];
    [_formatPopup addItemWithTitle:@"Falcon Pi Player (.fseq)"];
    [_formatPopup addItemWithTitle:@"Vixen 3 (.tim)"];
    [_formatPopup addItemWithTitle:@"LOR S5 (.lms)"];
    [_formatPopup addItemWithTitle:@"HLS (.hls)"];
    [_formatPopup addItemWithTitle:@"LedBlinky (.lwax)"];

    NSStackView *formatRow = [self createFormRowWithLabel:@"Output Format:" control:_formatPopup];
    [mainStack addArrangedSubview:formatRow];

    // Options section
    NSBox *optionsBox = [[NSBox alloc] initWithFrame:NSZeroRect];
    optionsBox.title = @"Options";
    optionsBox.boxType = NSBoxPrimary;

    NSStackView *optionsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    optionsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    optionsStack.alignment = NSLayoutAttributeLeading;
    optionsStack.spacing = 8;

    _offAtEndCheckbox = [NSButton checkboxWithTitle:@"Turn lights off at end" target:nil action:nil];
    _offAtEndCheckbox.state = NSControlStateValueOn;

    _mapEmptyCheckbox = [NSButton checkboxWithTitle:@"Map empty channels" target:nil action:nil];
    _mapEmptyCheckbox.state = NSControlStateValueOff;

    _showMappingCheckbox = [NSButton checkboxWithTitle:@"Show channel mapping dialog" target:nil action:nil];
    _showMappingCheckbox.state = NSControlStateValueOff;

    _lorNoNetworkCheckbox = [NSButton checkboxWithTitle:@"Map LOR channels with no network" target:nil action:nil];
    _lorNoNetworkCheckbox.state = NSControlStateValueOff;

    // LOR resolution
    NSStackView *lorResRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    lorResRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    lorResRow.spacing = 8;

    NSTextField *lorResLabel = [NSTextField labelWithString:@"LOR Import Resolution:"];

    _lorResolutionPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_lorResolutionPopup addItemWithTitle:@"25 ms"];
    [_lorResolutionPopup addItemWithTitle:@"50 ms"];
    [_lorResolutionPopup addItemWithTitle:@"100 ms"];
    [_lorResolutionPopup addItemWithTitle:@"Use original"];
    [_lorResolutionPopup selectItemAtIndex:1];

    [lorResRow addArrangedSubview:lorResLabel];
    [lorResRow addArrangedSubview:_lorResolutionPopup];

    [optionsStack addArrangedSubview:_offAtEndCheckbox];
    [optionsStack addArrangedSubview:_mapEmptyCheckbox];
    [optionsStack addArrangedSubview:_showMappingCheckbox];
    [optionsStack addArrangedSubview:_lorNoNetworkCheckbox];
    [optionsStack addArrangedSubview:lorResRow];

    optionsBox.contentView = optionsStack;
    [mainStack addArrangedSubview:optionsBox];
    [optionsBox.leadingAnchor constraintEqualToAnchor:mainStack.leadingAnchor constant:20].active = YES;
    [optionsBox.trailingAnchor constraintEqualToAnchor:mainStack.trailingAnchor constant:-20].active = YES;

    // Status text view
    NSTextField *statusLabel = [NSTextField labelWithString:@"Conversion Status:"];
    [mainStack addArrangedSubview:statusLabel];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;

    _statusTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    _statusTextView.editable = NO;
    _statusTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    scrollView.documentView = _statusTextView;

    [mainStack addArrangedSubview:scrollView];
    [scrollView.leadingAnchor constraintEqualToAnchor:mainStack.leadingAnchor constant:20].active = YES;
    [scrollView.trailingAnchor constraintEqualToAnchor:mainStack.trailingAnchor constant:-20].active = YES;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;

    // Progress indicator
    _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _progressIndicator.style = NSProgressIndicatorStyleBar;
    _progressIndicator.indeterminate = NO;
    _progressIndicator.minValue = 0;
    _progressIndicator.maxValue = 100;
    _progressIndicator.hidden = YES;

    [mainStack addArrangedSubview:_progressIndicator];
    [_progressIndicator.leadingAnchor constraintEqualToAnchor:mainStack.leadingAnchor constant:20].active = YES;
    [_progressIndicator.trailingAnchor constraintEqualToAnchor:mainStack.trailingAnchor constant:-20].active = YES;

    // Button row
    NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 12;

    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    _convertButton = [NSButton buttonWithTitle:@"Convert" target:self action:@selector(startConversion:)];
    _convertButton.keyEquivalent = @"\r";

    _closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeWindow:)];
    _closeButton.keyEquivalent = @"\033";

    [buttonRow addArrangedSubview:spacer];
    [buttonRow addArrangedSubview:_closeButton];
    [buttonRow addArrangedSubview:_convertButton];

    [mainStack addArrangedSubview:buttonRow];
    [buttonRow.trailingAnchor constraintEqualToAnchor:mainStack.trailingAnchor constant:-20].active = YES;
}

- (NSStackView *)createFormRowWithLabel:(NSString *)labelText control:(NSView *)control {
    NSStackView *row = [[NSStackView alloc] initWithFrame:NSZeroRect];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;

    NSTextField *label = [NSTextField labelWithString:labelText];
    label.alignment = NSTextAlignmentRight;
    [label.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    [row addArrangedSubview:label];
    [row addArrangedSubview:control];

    return row;
}

- (void)showWithCompletion:(void (^)(void))completion {
    _completionHandler = completion;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)browseFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            self.filePathField.stringValue = panel.URL.path;
        }
    }];
}

- (void)startConversion:(id)sender {
    if (_filePathField.stringValue.length == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No File Selected";
        alert.informativeText = @"Please select a file to convert.";
        [alert runModal];
        return;
    }

    _convertButton.enabled = NO;
    _progressIndicator.hidden = NO;
    _progressIndicator.doubleValue = 0;

    [self appendStatus:@"Starting conversion..."];
    [self appendStatus:[NSString stringWithFormat:@"Input file: %@", _filePathField.stringValue]];
    [self appendStatus:[NSString stringWithFormat:@"Output format: %@", _formatPopup.selectedItem.title]];

    // TODO: Actual conversion would be performed here via XLEngineBridge
    // For now, simulate progress
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (int i = 0; i <= 100; i += 10) {
            [NSThread sleepForTimeInterval:0.2];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.progressIndicator.doubleValue = i;
            });
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendStatus:@"Conversion complete."];
            self.convertButton.enabled = YES;
            self.progressIndicator.hidden = YES;
        });
    });
}

- (void)appendStatus:(NSString *)text {
    NSString *current = _statusTextView.string;
    NSString *timestamp = [[NSDateFormatter localizedStringFromDate:[NSDate date]
                                                          dateStyle:NSDateFormatterNoStyle
                                                          timeStyle:NSDateFormatterMediumStyle] stringByAppendingString:@": "];
    _statusTextView.string = [current stringByAppendingFormat:@"%@%@\n", timestamp, text];
    [_statusTextView scrollToEndOfDocument:nil];
}

- (void)closeWindow:(id)sender {
    [self.window close];
    if (_completionHandler) {
        _completionHandler();
    }
}

@end

#pragma mark - XLConvertLogDialog

@interface XLConvertLogDialog ()

@property (nonatomic, strong) NSTextView *logTextView;
@property (nonatomic, strong) NSTextField *summaryLabel;
@property (nonatomic, strong) NSMutableString *mutableLogText;

@end

@implementation XLConvertLogDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Conversion Log";
        self.okButtonTitle = @"Close";
        self.cancelButtonTitle = nil;
        self.minWidth = 500;
        self.minHeight = 400;
        _mutableLogText = [NSMutableString string];
        _errorCount = 0;
        _warningCount = 0;
        _conversionSuccessful = YES;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Summary label
    _summaryLabel = [NSTextField labelWithString:@"Conversion in progress..."];
    _summaryLabel.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:_summaryLabel];

    // Log text view
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:280].active = YES;

    _logTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    _logTextView.editable = NO;
    _logTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _logTextView.string = _mutableLogText;
    scrollView.documentView = _logTextView;

    [stack addArrangedSubview:scrollView];
    [scrollView.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [scrollView.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    return stack;
}

- (NSString *)logText {
    return [_mutableLogText copy];
}

- (void)setLogText:(NSString *)logText {
    _mutableLogText = [logText mutableCopy];
    _logTextView.string = _mutableLogText;
}

- (void)appendLog:(NSString *)text {
    [_mutableLogText appendFormat:@"%@\n", text];
    _logTextView.string = _mutableLogText;
    [_logTextView scrollToEndOfDocument:nil];
}

- (void)appendError:(NSString *)error {
    _errorCount++;
    _conversionSuccessful = NO;
    [_mutableLogText appendFormat:@"ERROR: %@\n", error];
    _logTextView.string = _mutableLogText;
    [_logTextView scrollToEndOfDocument:nil];
    [self updateSummary];
}

- (void)appendWarning:(NSString *)warning {
    _warningCount++;
    [_mutableLogText appendFormat:@"WARNING: %@\n", warning];
    _logTextView.string = _mutableLogText;
    [_logTextView scrollToEndOfDocument:nil];
    [self updateSummary];
}

- (void)clearLog {
    _mutableLogText = [NSMutableString string];
    _logTextView.string = @"";
    _errorCount = 0;
    _warningCount = 0;
    _conversionSuccessful = YES;
    [self updateSummary];
}

- (void)updateSummary {
    if (_conversionSuccessful) {
        if (_warningCount > 0) {
            _summaryLabel.stringValue = [NSString stringWithFormat:@"Conversion completed with %ld warning(s)",
                                         (long)_warningCount];
            _summaryLabel.textColor = [NSColor systemOrangeColor];
        } else {
            _summaryLabel.stringValue = @"Conversion completed successfully";
            _summaryLabel.textColor = [NSColor systemGreenColor];
        }
    } else {
        _summaryLabel.stringValue = [NSString stringWithFormat:@"Conversion failed with %ld error(s), %ld warning(s)",
                                     (long)_errorCount, (long)_warningCount];
        _summaryLabel.textColor = [NSColor systemRedColor];
    }
}

@end

#pragma mark - XLChannelMappingDialog

@interface XLChannelMappingDialog () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *mutableMapping;
@property (nonatomic, copy) void (^mappingCompletion)(BOOL accepted);

@end

@implementation XLChannelMappingDialog

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Channel Mapping";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        _sourceChannels = @[];
        _destinationModels = @[];
        _mutableMapping = [NSMutableDictionary dictionary];
        _mapEmptyChannels = NO;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    NSStackView *mainStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.alignment = NSLayoutAttributeLeading;
    mainStack.spacing = 12;
    mainStack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);

    [contentView addSubview:mainStack];
    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [mainStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [mainStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [mainStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];

    // Instructions
    NSTextField *instructions = [NSTextField wrappingLabelWithString:
        @"Map source channels to destination models. Select a destination for each source channel, or leave unmapped."];
    instructions.textColor = [NSColor secondaryLabelColor];
    [mainStack addArrangedSubview:instructions];
    [instructions.leadingAnchor constraintEqualToAnchor:mainStack.leadingAnchor constant:20].active = YES;
    [instructions.trailingAnchor constraintEqualToAnchor:mainStack.trailingAnchor constant:-20].active = YES;

    // Table
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 26;
    _tableView.usesAlternatingRowBackgroundColors = YES;

    NSTableColumn *sourceColumn = [[NSTableColumn alloc] initWithIdentifier:@"source"];
    sourceColumn.title = @"Source Channel";
    sourceColumn.width = 250;
    [_tableView addTableColumn:sourceColumn];

    NSTableColumn *destColumn = [[NSTableColumn alloc] initWithIdentifier:@"destination"];
    destColumn.title = @"Destination Model";
    destColumn.width = 250;
    [_tableView addTableColumn:destColumn];

    scrollView.documentView = _tableView;

    [mainStack addArrangedSubview:scrollView];
    [scrollView.leadingAnchor constraintEqualToAnchor:mainStack.leadingAnchor constant:20].active = YES;
    [scrollView.trailingAnchor constraintEqualToAnchor:mainStack.trailingAnchor constant:-20].active = YES;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;

    // Options
    NSButton *mapEmptyCheckbox = [NSButton checkboxWithTitle:@"Map empty/unused channels" target:nil action:nil];
    [mainStack addArrangedSubview:mapEmptyCheckbox];

    // Buttons
    NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 12;

    NSButton *autoMapBtn = [NSButton buttonWithTitle:@"Auto-Map by Name" target:self action:@selector(autoMap:)];
    NSButton *clearBtn = [NSButton buttonWithTitle:@"Clear All" target:self action:@selector(clearMapping:)];

    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *cancelBtn = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    cancelBtn.keyEquivalent = @"\033";

    NSButton *okBtn = [NSButton buttonWithTitle:@"Apply Mapping" target:self action:@selector(accept:)];
    okBtn.keyEquivalent = @"\r";

    [buttonRow addArrangedSubview:autoMapBtn];
    [buttonRow addArrangedSubview:clearBtn];
    [buttonRow addArrangedSubview:spacer];
    [buttonRow addArrangedSubview:cancelBtn];
    [buttonRow addArrangedSubview:okBtn];

    [mainStack addArrangedSubview:buttonRow];
    [buttonRow.leadingAnchor constraintEqualToAnchor:mainStack.leadingAnchor constant:20].active = YES;
    [buttonRow.trailingAnchor constraintEqualToAnchor:mainStack.trailingAnchor constant:-20].active = YES;
}

- (NSDictionary<NSNumber *,NSString *> *)channelMapping {
    return [_mutableMapping copy];
}

- (void)showWithCompletion:(void (^)(BOOL))completion {
    _mappingCompletion = completion;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)autoMap:(id)sender {
    [_mutableMapping removeAllObjects];

    for (NSUInteger i = 0; i < _sourceChannels.count; i++) {
        NSString *source = _sourceChannels[i].lowercaseString;
        for (NSString *dest in _destinationModels) {
            if ([dest.lowercaseString containsString:source] ||
                [source containsString:dest.lowercaseString]) {
                _mutableMapping[@(i)] = dest;
                break;
            }
        }
    }

    [_tableView reloadData];
}

- (void)clearMapping:(id)sender {
    [_mutableMapping removeAllObjects];
    [_tableView reloadData];
}

- (void)cancel:(id)sender {
    [self.window close];
    if (_mappingCompletion) {
        _mappingCompletion(NO);
    }
}

- (void)accept:(id)sender {
    [self.window close];
    if (_mappingCompletion) {
        _mappingCompletion(YES);
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _sourceChannels.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"source"]) {
        NSTextField *cell = [tableView makeViewWithIdentifier:@"sourceCell" owner:self];
        if (!cell) {
            cell = [NSTextField labelWithString:@""];
            cell.identifier = @"sourceCell";
        }
        cell.stringValue = _sourceChannels[row];
        return cell;
    } else {
        NSPopUpButton *popup = [tableView makeViewWithIdentifier:@"destPopup" owner:self];
        if (!popup) {
            popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
            popup.identifier = @"destPopup";
            [popup setTarget:self];
            [popup setAction:@selector(mappingChanged:)];
        }

        [popup removeAllItems];
        [popup addItemWithTitle:@"(Unmapped)"];
        for (NSString *model in _destinationModels) {
            [popup addItemWithTitle:model];
        }

        NSString *mapped = _mutableMapping[@(row)];
        if (mapped) {
            [popup selectItemWithTitle:mapped];
        } else {
            [popup selectItemAtIndex:0];
        }

        popup.tag = row;
        return popup;
    }
}

- (void)mappingChanged:(NSPopUpButton *)sender {
    NSInteger row = sender.tag;
    if (sender.indexOfSelectedItem == 0) {
        [_mutableMapping removeObjectForKey:@(row)];
    } else {
        _mutableMapping[@(row)] = sender.selectedItem.title;
    }
}

@end

#pragma mark - XLImportPreviewsModelsDialog

@interface XLImportPreviewsModelsDialog () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTableView *previewsTable;
@property (nonatomic, strong) NSTableView *modelsTable;
@property (nonatomic, strong) NSMutableIndexSet *mutableSelectedPreviews;
@property (nonatomic, strong) NSMutableIndexSet *mutableSelectedModels;
@property (nonatomic, strong) NSButton *groupsCheckbox;
@property (nonatomic, strong) NSButton *submodelsCheckbox;

@end

@implementation XLImportPreviewsModelsDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Import Previews & Models";
        self.okButtonTitle = @"Import";
        self.minWidth = 600;
        self.minHeight = 450;
        _availablePreviews = @[];
        _availableModels = @[];
        _mutableSelectedPreviews = [NSMutableIndexSet indexSet];
        _mutableSelectedModels = [NSMutableIndexSet indexSet];
        _includeModelGroups = YES;
        _includeSubmodels = YES;
    }
    return self;
}

- (NSIndexSet *)selectedPreviews {
    return [_mutableSelectedPreviews copy];
}

- (void)setSelectedPreviews:(NSIndexSet *)selectedPreviews {
    _mutableSelectedPreviews = selectedPreviews ? [selectedPreviews mutableCopy] : [NSMutableIndexSet indexSet];
}

- (NSIndexSet *)selectedModels {
    return [_mutableSelectedModels copy];
}

- (void)setSelectedModels:(NSIndexSet *)selectedModels {
    _mutableSelectedModels = selectedModels ? [selectedModels mutableCopy] : [NSMutableIndexSet indexSet];
}

- (NSView *)buildContentView {
    NSStackView *mainStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.alignment = NSLayoutAttributeLeading;
    mainStack.spacing = 12;

    // Source path
    NSTextField *pathLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Importing from: %@", _sourceShowPath ?: @"(not set)"]];
    pathLabel.textColor = [NSColor secondaryLabelColor];
    [mainStack addArrangedSubview:pathLabel];

    // Split view for previews and models
    NSStackView *splitStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    splitStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    splitStack.spacing = 16;
    splitStack.distribution = NSStackViewDistributionFillEqually;

    // Previews section
    NSStackView *previewsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    previewsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    previewsStack.spacing = 8;

    NSTextField *previewsLabel = [NSTextField labelWithString:@"Previews"];
    previewsLabel.font = [NSFont boldSystemFontOfSize:12];
    [previewsStack addArrangedSubview:previewsLabel];

    NSScrollView *previewsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    previewsScroll.hasVerticalScroller = YES;
    previewsScroll.borderType = NSBezelBorder;

    _previewsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _previewsTable.dataSource = self;
    _previewsTable.delegate = self;
    _previewsTable.rowHeight = 24;
    _previewsTable.tag = 1;

    NSTableColumn *previewCheckCol = [[NSTableColumn alloc] initWithIdentifier:@"check"];
    previewCheckCol.width = 30;
    [_previewsTable addTableColumn:previewCheckCol];

    NSTableColumn *previewNameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    previewNameCol.title = @"Name";
    previewNameCol.width = 200;
    [_previewsTable addTableColumn:previewNameCol];

    previewsScroll.documentView = _previewsTable;
    [previewsStack addArrangedSubview:previewsScroll];
    [previewsScroll.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;

    [splitStack addArrangedSubview:previewsStack];

    // Models section
    NSStackView *modelsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    modelsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    modelsStack.spacing = 8;

    NSTextField *modelsLabel = [NSTextField labelWithString:@"Models"];
    modelsLabel.font = [NSFont boldSystemFontOfSize:12];
    [modelsStack addArrangedSubview:modelsLabel];

    NSScrollView *modelsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    modelsScroll.hasVerticalScroller = YES;
    modelsScroll.borderType = NSBezelBorder;

    _modelsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _modelsTable.dataSource = self;
    _modelsTable.delegate = self;
    _modelsTable.rowHeight = 24;
    _modelsTable.tag = 2;

    NSTableColumn *modelCheckCol = [[NSTableColumn alloc] initWithIdentifier:@"check"];
    modelCheckCol.width = 30;
    [_modelsTable addTableColumn:modelCheckCol];

    NSTableColumn *modelNameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    modelNameCol.title = @"Name";
    modelNameCol.width = 200;
    [_modelsTable addTableColumn:modelNameCol];

    modelsScroll.documentView = _modelsTable;
    [modelsStack addArrangedSubview:modelsScroll];
    [modelsScroll.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;

    [splitStack addArrangedSubview:modelsStack];

    [mainStack addArrangedSubview:splitStack];
    [splitStack.leadingAnchor constraintEqualToAnchor:mainStack.leadingAnchor].active = YES;
    [splitStack.trailingAnchor constraintEqualToAnchor:mainStack.trailingAnchor].active = YES;

    // Options
    _groupsCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Include model groups"];
    _groupsCheckbox.state = _includeModelGroups ? NSControlStateValueOn : NSControlStateValueOff;
    [mainStack addArrangedSubview:_groupsCheckbox];

    _submodelsCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Include submodels"];
    _submodelsCheckbox.state = _includeSubmodels ? NSControlStateValueOn : NSControlStateValueOff;
    [mainStack addArrangedSubview:_submodelsCheckbox];

    return mainStack;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView.tag == 1) {
        return _availablePreviews.count;
    } else {
        return _availableModels.count;
    }
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSMutableIndexSet *selectedSet = (tableView.tag == 1) ? _mutableSelectedPreviews : _mutableSelectedModels;
    NSArray *items = (tableView.tag == 1) ? _availablePreviews : _availableModels;

    if ([tableColumn.identifier isEqualToString:@"check"]) {
        NSButton *checkbox = [tableView makeViewWithIdentifier:@"checkbox" owner:self];
        if (!checkbox) {
            checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(itemCheckboxToggled:)];
            checkbox.identifier = @"checkbox";
        }
        checkbox.state = [selectedSet containsIndex:row] ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.tag = row + (tableView.tag * 10000);
        return checkbox;
    } else {
        NSTextField *cell = [tableView makeViewWithIdentifier:@"cell" owner:self];
        if (!cell) {
            cell = [NSTextField labelWithString:@""];
            cell.identifier = @"cell";
        }
        cell.stringValue = items[row];
        return cell;
    }
}

- (void)itemCheckboxToggled:(NSButton *)sender {
    NSInteger tag = sender.tag;
    NSInteger tableTag = tag / 10000;
    NSInteger row = tag % 10000;

    NSMutableIndexSet *selectedSet = (tableTag == 1) ? _mutableSelectedPreviews : _mutableSelectedModels;

    if (sender.state == NSControlStateValueOn) {
        [selectedSet addIndex:row];
    } else {
        [selectedSet removeIndex:row];
    }
}

- (void)okClicked:(id)sender {
    _includeModelGroups = (_groupsCheckbox.state == NSControlStateValueOn);
    _includeSubmodels = (_submodelsCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end

#pragma mark - Remaining Import Dialogs (Stubs)

@implementation XLSuperStarImportDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"SuperStar Import";
        self.minWidth = 400;
        self.minHeight = 300;
        _availableModels = @[];
        _resizeMode = 0;
        _flipHorizontal = NO;
        _flipVertical = NO;
    }
    return self;
}

- (NSView *)buildContentView {
    // TODO: Full implementation
    NSTextField *placeholder = [NSTextField labelWithString:@"SuperStar import options will appear here"];
    return placeholder;
}

@end

@interface XLVixenImportDialog ()

@property (nonatomic, strong) NSPopUpButton *resolutionPopup;
@property (nonatomic, strong) NSButton *importMappingsCheckbox;
@property (nonatomic, strong) NSPopUpButton *channelMappingPopup;
@property (nonatomic, strong) NSTextField *filePathLabel;

@end

@implementation XLVixenImportDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Vixen Import Options";
        self.okButtonTitle = @"Import";
        self.minWidth = 450;
        self.minHeight = 280;
        _timeResolutionMs = 50;
        _importControllerMappings = YES;
        _channelMappingMode = 1;
    }
    return self;
}

- (NSArray<NSNumber *> *)availableResolutions {
    return @[@25, @50, @100];
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // File path display
    _filePathLabel = [NSTextField wrappingLabelWithString:
        [NSString stringWithFormat:@"File: %@", _vixenFilePath.lastPathComponent ?: @"(none)"]];
    _filePathLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:_filePathLabel];

    // Time resolution
    _resolutionPopup = [XLBaseSheetController createPopUpButton];
    [_resolutionPopup addItemWithTitle:@"25 ms (40 fps)"];
    _resolutionPopup.lastItem.tag = 25;
    [_resolutionPopup addItemWithTitle:@"50 ms (20 fps)"];
    _resolutionPopup.lastItem.tag = 50;
    [_resolutionPopup addItemWithTitle:@"100 ms (10 fps)"];
    _resolutionPopup.lastItem.tag = 100;
    [_resolutionPopup selectItemWithTag:_timeResolutionMs];

    NSStackView *resRow = [XLBaseSheetController formRowWithLabel:@"Time Resolution:" control:_resolutionPopup labelWidth:kLabelWidth];
    [stack addArrangedSubview:resRow];

    // Import mappings
    _importMappingsCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Import controller/channel mappings from Vixen profile"];
    _importMappingsCheckbox.state = _importControllerMappings ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_importMappingsCheckbox];

    // Channel mapping mode
    _channelMappingPopup = [XLBaseSheetController createPopUpButton];
    [_channelMappingPopup addItemWithTitle:@"No mapping (use raw channels)"];
    _channelMappingPopup.lastItem.tag = 0;
    [_channelMappingPopup addItemWithTitle:@"Show mapping dialog"];
    _channelMappingPopup.lastItem.tag = 1;
    [_channelMappingPopup addItemWithTitle:@"Auto-map by channel name"];
    _channelMappingPopup.lastItem.tag = 2;
    [_channelMappingPopup selectItemWithTag:_channelMappingMode];

    NSStackView *mapRow = [XLBaseSheetController formRowWithLabel:@"Channel Mapping:" control:_channelMappingPopup labelWidth:kLabelWidth];
    [stack addArrangedSubview:mapRow];

    // Info text
    NSTextField *infoLabel = [NSTextField wrappingLabelWithString:
        @"Note: Vixen 2 and 3 files use different formats. The importer will "
        @"automatically detect the version and extract timing and effect data."];
    infoLabel.textColor = [NSColor tertiaryLabelColor];
    infoLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:infoLabel];
    [infoLabel.widthAnchor constraintLessThanOrEqualToConstant:400].active = YES;

    return stack;
}

- (void)okClicked:(id)sender {
    _timeResolutionMs = _resolutionPopup.selectedItem.tag;
    _importControllerMappings = (_importMappingsCheckbox.state == NSControlStateValueOn);
    _channelMappingMode = _channelMappingPopup.selectedItem.tag;
    [super okClicked:sender];
}

@end

@interface XLLORImportDialog ()

@property (nonatomic, strong) NSPopUpButton *resolutionPopup;
@property (nonatomic, strong) NSButton *mapNoNetworkCheckbox;
@property (nonatomic, strong) NSPopUpButton *channelMappingPopup;
@property (nonatomic, strong) NSTextField *filePathLabel;
@property (nonatomic, strong) NSButton *offAtEndCheckbox;
@property (nonatomic, strong) NSButton *mapEmptyCheckbox;

@end

@implementation XLLORImportDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"LOR Import Options";
        self.okButtonTitle = @"Import";
        self.minWidth = 480;
        self.minHeight = 350;
        _timeResolutionCs = 5;
        _mapChannelsWithNoNetwork = NO;
        _channelMappingMode = 1;
    }
    return self;
}

- (NSArray<NSNumber *> *)availableResolutions {
    return @[@1, @2, @5, @10];
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // File path display
    _filePathLabel = [NSTextField wrappingLabelWithString:
        [NSString stringWithFormat:@"File: %@", _lorFilePath.lastPathComponent ?: @"(none)"]];
    _filePathLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:_filePathLabel];

    // Time resolution
    _resolutionPopup = [XLBaseSheetController createPopUpButton];
    [_resolutionPopup addItemWithTitle:@"10 ms (1 centisecond)"];
    _resolutionPopup.lastItem.tag = 1;
    [_resolutionPopup addItemWithTitle:@"20 ms (2 centiseconds)"];
    _resolutionPopup.lastItem.tag = 2;
    [_resolutionPopup addItemWithTitle:@"50 ms (5 centiseconds)"];
    _resolutionPopup.lastItem.tag = 5;
    [_resolutionPopup addItemWithTitle:@"100 ms (10 centiseconds)"];
    _resolutionPopup.lastItem.tag = 10;
    [_resolutionPopup selectItemWithTag:_timeResolutionCs];

    NSStackView *resRow = [XLBaseSheetController formRowWithLabel:@"Time Resolution:" control:_resolutionPopup labelWidth:kLabelWidth];
    [stack addArrangedSubview:resRow];

    // Channel mapping mode
    _channelMappingPopup = [XLBaseSheetController createPopUpButton];
    [_channelMappingPopup addItemWithTitle:@"No mapping (use raw channels)"];
    _channelMappingPopup.lastItem.tag = 0;
    [_channelMappingPopup addItemWithTitle:@"Show mapping dialog"];
    _channelMappingPopup.lastItem.tag = 1;
    [_channelMappingPopup addItemWithTitle:@"Auto-map by channel name"];
    _channelMappingPopup.lastItem.tag = 2;
    [_channelMappingPopup selectItemWithTag:_channelMappingMode];

    NSStackView *mapRow = [XLBaseSheetController formRowWithLabel:@"Channel Mapping:" control:_channelMappingPopup labelWidth:kLabelWidth];
    [stack addArrangedSubview:mapRow];

    // Options box
    NSBox *optionsBox = [[NSBox alloc] initWithFrame:NSZeroRect];
    optionsBox.title = @"Import Options";
    optionsBox.boxType = NSBoxPrimary;

    NSStackView *optionsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    optionsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    optionsStack.alignment = NSLayoutAttributeLeading;
    optionsStack.spacing = 8;

    _mapNoNetworkCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Map channels with no network assignment"];
    _mapNoNetworkCheckbox.state = _mapChannelsWithNoNetwork ? NSControlStateValueOn : NSControlStateValueOff;
    [optionsStack addArrangedSubview:_mapNoNetworkCheckbox];

    _mapEmptyCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Map empty/unused channels"];
    _mapEmptyCheckbox.state = NSControlStateValueOff;
    [optionsStack addArrangedSubview:_mapEmptyCheckbox];

    _offAtEndCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Turn channels off at end of sequence"];
    _offAtEndCheckbox.state = NSControlStateValueOn;
    [optionsStack addArrangedSubview:_offAtEndCheckbox];

    optionsBox.contentView = optionsStack;
    [stack addArrangedSubview:optionsBox];
    [optionsBox.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [optionsBox.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    // Info text
    NSTextField *infoLabel = [NSTextField wrappingLabelWithString:
        @"Light-O-Rama files (.lms, .las, .lss) contain controller and channel "
        @"information. The importer will read intensity, twinkle, and shimmer effects."];
    infoLabel.textColor = [NSColor tertiaryLabelColor];
    infoLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:infoLabel];
    [infoLabel.widthAnchor constraintLessThanOrEqualToConstant:440].active = YES;

    return stack;
}

- (void)okClicked:(id)sender {
    _timeResolutionCs = _resolutionPopup.selectedItem.tag;
    _mapChannelsWithNoNetwork = (_mapNoNetworkCheckbox.state == NSControlStateValueOn);
    _channelMappingMode = _channelMappingPopup.selectedItem.tag;
    [super okClicked:sender];
}

@end

@interface XLHLSImportDialog ()

@property (nonatomic, strong) NSButton *importTimingCheckbox;
@property (nonatomic, strong) NSButton *importMappingsCheckbox;
@property (nonatomic, strong) NSTextField *filePathLabel;

@end

@implementation XLHLSImportDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"HLS Import Options";
        self.okButtonTitle = @"Import";
        self.minWidth = 420;
        self.minHeight = 220;
        _importTimingTracks = YES;
        _importMappings = YES;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // File path display
    _filePathLabel = [NSTextField wrappingLabelWithString:
        [NSString stringWithFormat:@"File: %@", _hlsFilePath.lastPathComponent ?: @"(none)"]];
    _filePathLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:_filePathLabel];

    // Options
    _importTimingCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Import timing tracks"];
    _importTimingCheckbox.state = _importTimingTracks ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_importTimingCheckbox];

    _importMappingsCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Import universe/channel mappings"];
    _importMappingsCheckbox.state = _importMappings ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_importMappingsCheckbox];

    // Info text
    NSTextField *infoLabel = [NSTextField wrappingLabelWithString:
        @"Hinkle's Light Sequencer (HLS) files contain universe-based channel data. "
        @"The importer will map channels to your configured outputs."];
    infoLabel.textColor = [NSColor tertiaryLabelColor];
    infoLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:infoLabel];
    [infoLabel.widthAnchor constraintLessThanOrEqualToConstant:380].active = YES;

    return stack;
}

- (void)okClicked:(id)sender {
    _importTimingTracks = (_importTimingCheckbox.state == NSControlStateValueOn);
    _importMappings = (_importMappingsCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end

@implementation XLVSAImportDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"VSA Import";
        self.minWidth = 450;
        self.minHeight = 350;
        _availableModels = @[];
        _servoMapping = @{};
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    NSTextField *infoLabel = [NSTextField wrappingLabelWithString:
        @"Import servo animation data from Visual Show Automation (VSA) files. "
        @"Map servos to DMX models for conversion."];
    infoLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:infoLabel];

    NSTextField *placeholder = [NSTextField labelWithString:@"Servo mapping configuration will appear here"];
    placeholder.textColor = [NSColor tertiaryLabelColor];
    [stack addArrangedSubview:placeholder];

    return stack;
}

@end

#pragma mark - XLExportSequenceDialog

@interface XLExportSequenceDialog ()

@property (nonatomic, strong) NSPopUpButton *formatPopup;
@property (nonatomic, strong) NSTextField *pathField;
@property (nonatomic, strong) NSButton *browseButton;
@property (nonatomic, strong) NSButton *allModelsRadio;
@property (nonatomic, strong) NSButton *selectedModelsRadio;
@property (nonatomic, strong) NSTableView *modelsTable;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedModelsSet;
@property (nonatomic, strong) NSTextField *startTimeField;
@property (nonatomic, strong) NSTextField *endTimeField;
@property (nonatomic, strong) NSButton *includeAudioCheckbox;
@property (nonatomic, strong) NSTextField *widthField;
@property (nonatomic, strong) NSTextField *heightField;
@property (nonatomic, strong) NSTextField *fpsField;
@property (nonatomic, strong) NSSlider *qualitySlider;
@property (nonatomic, strong) NSSlider *compressionSlider;
@property (nonatomic, strong) NSView *videoOptionsBox;
@property (nonatomic, strong) NSView *fseqOptionsBox;

@end

@implementation XLExportSequenceDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Export Sequence";
        self.okButtonTitle = @"Export";
        self.minWidth = 550;
        self.minHeight = 500;
        _exportFormat = XLExportFormatFSEQ;
        _exportAllModels = YES;
        _selectedModelNames = @[];
        _selectedModelsSet = [NSMutableSet set];
        _startTimeMs = 0;
        _endTimeMs = 0;
        _includeAudio = YES;
        _videoWidth = 1920;
        _videoHeight = 1080;
        _frameRate = 30;
        _gifQuality = 80;
        _fseqCompressionLevel = 2;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Format selection
    _formatPopup = [XLBaseSheetController createPopUpButton];
    [_formatPopup addItemWithTitle:@"FSEQ v2 (Falcon Player)"];
    _formatPopup.lastItem.tag = XLExportFormatFSEQ;
    [_formatPopup addItemWithTitle:@"FSEQ v1 (Legacy)"];
    _formatPopup.lastItem.tag = XLExportFormatFSEQv1;
    [_formatPopup addItemWithTitle:@"Video (MP4)"];
    _formatPopup.lastItem.tag = XLExportFormatVideo;
    [_formatPopup addItemWithTitle:@"Animated GIF"];
    _formatPopup.lastItem.tag = XLExportFormatGIF;
    [_formatPopup addItemWithTitle:@"Minleon NDB"];
    _formatPopup.lastItem.tag = XLExportFormatMinleon;
    [_formatPopup addItemWithTitle:@"Light-O-Rama"];
    _formatPopup.lastItem.tag = XLExportFormatLOR;
    [_formatPopup addItemWithTitle:@"Vixen 2"];
    _formatPopup.lastItem.tag = XLExportFormatVixen2;
    [_formatPopup addItemWithTitle:@"HLS"];
    _formatPopup.lastItem.tag = XLExportFormatHLS;
    [_formatPopup addItemWithTitle:@"Effect Sequence (.eseq)"];
    _formatPopup.lastItem.tag = XLExportFormatEseq;
    [_formatPopup setTarget:self];
    [_formatPopup setAction:@selector(formatChanged:)];

    NSStackView *formatRow = [XLBaseSheetController formRowWithLabel:@"Export Format:" control:_formatPopup labelWidth:kLabelWidth];
    [stack addArrangedSubview:formatRow];

    // Export path
    NSStackView *pathRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    pathRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    pathRow.spacing = 8;

    NSTextField *pathLabel = [NSTextField labelWithString:@"Export To:"];
    pathLabel.alignment = NSTextAlignmentRight;
    [pathLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _pathField = [XLBaseSheetController createTextField];
    _pathField.editable = NO;
    _pathField.stringValue = _exportPath ?: @"";
    [_pathField.widthAnchor constraintGreaterThanOrEqualToConstant:280].active = YES;

    _browseButton = [NSButton buttonWithTitle:@"Browse..." target:self action:@selector(browsePath:)];

    [pathRow addArrangedSubview:pathLabel];
    [pathRow addArrangedSubview:_pathField];
    [pathRow addArrangedSubview:_browseButton];
    [stack addArrangedSubview:pathRow];

    // Time range
    NSStackView *timeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    timeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    timeRow.spacing = 8;

    NSTextField *timeLabel = [NSTextField labelWithString:@"Time Range:"];
    timeLabel.alignment = NSTextAlignmentRight;
    [timeLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _startTimeField = [XLBaseSheetController createNumericField];
    _startTimeField.integerValue = _startTimeMs;
    [_startTimeField.widthAnchor constraintEqualToConstant:80].active = YES;

    NSTextField *toLabel = [NSTextField labelWithString:@"to"];

    _endTimeField = [XLBaseSheetController createNumericField];
    _endTimeField.integerValue = _endTimeMs;
    _endTimeField.placeholderString = @"(end)";
    [_endTimeField.widthAnchor constraintEqualToConstant:80].active = YES;

    NSTextField *msLabel = [NSTextField labelWithString:@"ms (0 = use full range)"];
    msLabel.textColor = [NSColor secondaryLabelColor];

    [timeRow addArrangedSubview:timeLabel];
    [timeRow addArrangedSubview:_startTimeField];
    [timeRow addArrangedSubview:toLabel];
    [timeRow addArrangedSubview:_endTimeField];
    [timeRow addArrangedSubview:msLabel];
    [stack addArrangedSubview:timeRow];

    // Model selection
    NSBox *modelsBox = [[NSBox alloc] initWithFrame:NSZeroRect];
    modelsBox.title = @"Models to Export";
    modelsBox.boxType = NSBoxPrimary;

    NSStackView *modelsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    modelsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    modelsStack.alignment = NSLayoutAttributeLeading;
    modelsStack.spacing = 8;

    _allModelsRadio = [NSButton radioButtonWithTitle:@"All models" target:self action:@selector(modelSelectionChanged:)];
    _allModelsRadio.state = NSControlStateValueOn;

    _selectedModelsRadio = [NSButton radioButtonWithTitle:@"Selected models only:" target:self action:@selector(modelSelectionChanged:)];
    _selectedModelsRadio.state = NSControlStateValueOff;

    [modelsStack addArrangedSubview:_allModelsRadio];
    [modelsStack addArrangedSubview:_selectedModelsRadio];

    // Models table (initially disabled)
    NSScrollView *modelsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    modelsScroll.hasVerticalScroller = YES;
    modelsScroll.borderType = NSBezelBorder;
    [modelsScroll.heightAnchor constraintEqualToConstant:100].active = YES;

    _modelsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _modelsTable.dataSource = self;
    _modelsTable.delegate = self;
    _modelsTable.rowHeight = 22;
    _modelsTable.enabled = NO;

    NSTableColumn *checkCol = [[NSTableColumn alloc] initWithIdentifier:@"check"];
    checkCol.width = 30;
    [_modelsTable addTableColumn:checkCol];

    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameCol.title = @"Model";
    nameCol.width = 300;
    [_modelsTable addTableColumn:nameCol];

    modelsScroll.documentView = _modelsTable;
    [modelsStack addArrangedSubview:modelsScroll];
    [modelsScroll.leadingAnchor constraintEqualToAnchor:modelsStack.leadingAnchor].active = YES;
    [modelsScroll.trailingAnchor constraintEqualToAnchor:modelsStack.trailingAnchor].active = YES;

    modelsBox.contentView = modelsStack;
    [stack addArrangedSubview:modelsBox];
    [modelsBox.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [modelsBox.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    // FSEQ options
    _fseqOptionsBox = [self buildFSEQOptionsBox];
    [stack addArrangedSubview:_fseqOptionsBox];
    [_fseqOptionsBox.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [_fseqOptionsBox.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    // Video/GIF options
    _videoOptionsBox = [self buildVideoOptionsBox];
    _videoOptionsBox.hidden = YES;
    [stack addArrangedSubview:_videoOptionsBox];
    [_videoOptionsBox.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [_videoOptionsBox.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    return stack;
}

- (NSView *)buildFSEQOptionsBox {
    NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
    box.title = @"FSEQ Options";
    box.boxType = NSBoxPrimary;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;

    // Compression level
    NSStackView *compRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    compRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    compRow.spacing = 8;

    NSTextField *compLabel = [NSTextField labelWithString:@"Compression Level:"];
    _compressionSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _compressionSlider.minValue = 0;
    _compressionSlider.maxValue = 9;
    _compressionSlider.integerValue = _fseqCompressionLevel;
    _compressionSlider.numberOfTickMarks = 10;
    _compressionSlider.allowsTickMarkValuesOnly = YES;
    [_compressionSlider.widthAnchor constraintEqualToConstant:200].active = YES;

    NSTextField *compValueLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld", (long)_fseqCompressionLevel]];
    [compValueLabel.widthAnchor constraintEqualToConstant:30].active = YES;

    [compRow addArrangedSubview:compLabel];
    [compRow addArrangedSubview:_compressionSlider];
    [compRow addArrangedSubview:compValueLabel];
    [stack addArrangedSubview:compRow];

    box.contentView = stack;
    return box;
}

- (NSView *)buildVideoOptionsBox {
    NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
    box.title = @"Video/GIF Options";
    box.boxType = NSBoxPrimary;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;

    // Resolution
    NSStackView *resRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    resRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    resRow.spacing = 8;

    NSTextField *resLabel = [NSTextField labelWithString:@"Resolution:"];
    _widthField = [XLBaseSheetController createNumericField];
    _widthField.integerValue = _videoWidth;
    [_widthField.widthAnchor constraintEqualToConstant:70].active = YES;

    NSTextField *xLabel = [NSTextField labelWithString:@"x"];

    _heightField = [XLBaseSheetController createNumericField];
    _heightField.integerValue = _videoHeight;
    [_heightField.widthAnchor constraintEqualToConstant:70].active = YES;

    NSTextField *pxLabel = [NSTextField labelWithString:@"pixels"];
    pxLabel.textColor = [NSColor secondaryLabelColor];

    [resRow addArrangedSubview:resLabel];
    [resRow addArrangedSubview:_widthField];
    [resRow addArrangedSubview:xLabel];
    [resRow addArrangedSubview:_heightField];
    [resRow addArrangedSubview:pxLabel];
    [stack addArrangedSubview:resRow];

    // Frame rate
    NSStackView *fpsRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    fpsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fpsRow.spacing = 8;

    NSTextField *fpsLabel = [NSTextField labelWithString:@"Frame Rate:"];
    _fpsField = [XLBaseSheetController createNumericField];
    _fpsField.integerValue = _frameRate;
    [_fpsField.widthAnchor constraintEqualToConstant:50].active = YES;

    NSTextField *fpsUnitLabel = [NSTextField labelWithString:@"fps"];
    fpsUnitLabel.textColor = [NSColor secondaryLabelColor];

    [fpsRow addArrangedSubview:fpsLabel];
    [fpsRow addArrangedSubview:_fpsField];
    [fpsRow addArrangedSubview:fpsUnitLabel];
    [stack addArrangedSubview:fpsRow];

    // Quality
    NSStackView *qualRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    qualRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    qualRow.spacing = 8;

    NSTextField *qualLabel = [NSTextField labelWithString:@"Quality:"];
    _qualitySlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _qualitySlider.minValue = 1;
    _qualitySlider.maxValue = 100;
    _qualitySlider.integerValue = _gifQuality;
    [_qualitySlider.widthAnchor constraintEqualToConstant:200].active = YES;

    NSTextField *qualValueLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld%%", (long)_gifQuality]];
    [qualValueLabel.widthAnchor constraintEqualToConstant:40].active = YES;

    [qualRow addArrangedSubview:qualLabel];
    [qualRow addArrangedSubview:_qualitySlider];
    [qualRow addArrangedSubview:qualValueLabel];
    [stack addArrangedSubview:qualRow];

    // Include audio
    _includeAudioCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Include audio in video export"];
    _includeAudioCheckbox.state = _includeAudio ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_includeAudioCheckbox];

    box.contentView = stack;
    return box;
}

- (void)formatChanged:(id)sender {
    XLExportFormat format = (XLExportFormat)_formatPopup.selectedItem.tag;
    _exportFormat = format;

    BOOL isVideo = (format == XLExportFormatVideo || format == XLExportFormatGIF);
    BOOL isFSEQ = (format == XLExportFormatFSEQ || format == XLExportFormatFSEQv1 || format == XLExportFormatFSEQv2);

    _videoOptionsBox.hidden = !isVideo;
    _fseqOptionsBox.hidden = !isFSEQ;
}

- (void)browsePath:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;

    NSString *ext = [[self class] fileExtensionForFormat:_exportFormat];
    if (ext) {
        panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:ext]];
    }

    [panel beginSheetModalForWindow:self.sheet completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            self.pathField.stringValue = panel.URL.path;
            self.exportPath = panel.URL.path;
        }
    }];
}

- (void)modelSelectionChanged:(id)sender {
    BOOL selectModels = (_selectedModelsRadio.state == NSControlStateValueOn);
    _modelsTable.enabled = selectModels;
    _exportAllModels = !selectModels;
}

+ (NSString *)fileExtensionForFormat:(XLExportFormat)format {
    switch (format) {
        case XLExportFormatFSEQ:
        case XLExportFormatFSEQv1:
        case XLExportFormatFSEQv2:
            return @"fseq";
        case XLExportFormatVideo:
            return @"mp4";
        case XLExportFormatGIF:
            return @"gif";
        case XLExportFormatMinleon:
            return @"ndb";
        case XLExportFormatLOR:
            return @"lms";
        case XLExportFormatVixen2:
            return @"vix";
        case XLExportFormatHLS:
            return @"hlsseq";
        case XLExportFormatEseq:
            return @"eseq";
    }
    return nil;
}

+ (NSString *)displayNameForFormat:(XLExportFormat)format {
    switch (format) {
        case XLExportFormatFSEQ:
            return @"FSEQ (Falcon Player)";
        case XLExportFormatFSEQv1:
            return @"FSEQ v1 (Legacy)";
        case XLExportFormatFSEQv2:
            return @"FSEQ v2";
        case XLExportFormatVideo:
            return @"Video (MP4)";
        case XLExportFormatGIF:
            return @"Animated GIF";
        case XLExportFormatMinleon:
            return @"Minleon NDB";
        case XLExportFormatLOR:
            return @"Light-O-Rama";
        case XLExportFormatVixen2:
            return @"Vixen 2";
        case XLExportFormatHLS:
            return @"HLS";
        case XLExportFormatEseq:
            return @"Effect Sequence";
    }
    return @"Unknown";
}

- (NSString *)validate {
    if (_pathField.stringValue.length == 0) {
        return @"Please select an export location.";
    }
    return nil;
}

- (void)okClicked:(id)sender {
    _exportPath = _pathField.stringValue;
    _startTimeMs = _startTimeField.integerValue;
    _endTimeMs = _endTimeField.integerValue;
    _exportAllModels = (_allModelsRadio.state == NSControlStateValueOn);
    _includeAudio = (_includeAudioCheckbox.state == NSControlStateValueOn);
    _videoWidth = _widthField.integerValue;
    _videoHeight = _heightField.integerValue;
    _frameRate = _fpsField.integerValue;
    _gifQuality = _qualitySlider.integerValue;
    _fseqCompressionLevel = _compressionSlider.integerValue;
    _selectedModelNames = [_selectedModelsSet allObjects];
    [super okClicked:sender];
}

#pragma mark - NSTableViewDataSource/Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [_engineBridge getModelNames].count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSArray *models = [_engineBridge getModelNames];
    if (row >= (NSInteger)models.count) return nil;

    NSString *modelName = models[row];

    if ([tableColumn.identifier isEqualToString:@"check"]) {
        NSButton *checkbox = [tableView makeViewWithIdentifier:@"exportCheck" owner:self];
        if (!checkbox) {
            checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(modelCheckboxToggled:)];
            checkbox.identifier = @"exportCheck";
        }
        checkbox.state = [_selectedModelsSet containsObject:modelName] ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.tag = row;
        return checkbox;
    } else {
        NSTextField *cell = [tableView makeViewWithIdentifier:@"modelCell" owner:self];
        if (!cell) {
            cell = [NSTextField labelWithString:@""];
            cell.identifier = @"modelCell";
        }
        cell.stringValue = modelName;
        return cell;
    }
}

- (void)modelCheckboxToggled:(NSButton *)sender {
    NSArray *models = [_engineBridge getModelNames];
    NSInteger row = sender.tag;
    if (row < (NSInteger)models.count) {
        NSString *modelName = models[row];
        if (sender.state == NSControlStateValueOn) {
            [_selectedModelsSet addObject:modelName];
        } else {
            [_selectedModelsSet removeObject:modelName];
        }
    }
}

@end

#pragma mark - XLBatchConvertDialog

@interface XLBatchConvertDialog ()

@property (nonatomic, strong) NSPopUpButton *sourceFormatPopup;
@property (nonatomic, strong) NSPopUpButton *destFormatPopup;
@property (nonatomic, strong) NSTextField *outputDirField;
@property (nonatomic, strong) NSButton *browseDirButton;
@property (nonatomic, strong) NSTableView *filesTable;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *sourceFiles;
@property (nonatomic, strong) NSButton *overwriteCheckbox;
@property (nonatomic, strong) NSButton *preserveStructureCheckbox;
@property (nonatomic, strong) NSTextField *selectedCountLabel;

@end

@implementation XLBatchConvertDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Batch Convert";
        self.okButtonTitle = @"Convert";
        self.minWidth = 650;
        self.minHeight = 500;
        _sourceFormat = XLImportFormatLOR;
        _destinationFormat = XLExportFormatFSEQ;
        _sourceFiles = [NSMutableArray array];
        _overwriteExisting = NO;
        _preserveFolderStructure = YES;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Source format
    _sourceFormatPopup = [XLBaseSheetController createPopUpButton];
    [_sourceFormatPopup addItemWithTitle:@"Vixen 2 (.vix)"];
    _sourceFormatPopup.lastItem.tag = XLImportFormatVixen2;
    [_sourceFormatPopup addItemWithTitle:@"Vixen 3 (.tim)"];
    _sourceFormatPopup.lastItem.tag = XLImportFormatVixen3;
    [_sourceFormatPopup addItemWithTitle:@"Light-O-Rama (.lms, .las)"];
    _sourceFormatPopup.lastItem.tag = XLImportFormatLOR;
    [_sourceFormatPopup addItemWithTitle:@"HLS (.hlsseq)"];
    _sourceFormatPopup.lastItem.tag = XLImportFormatHLS;
    [_sourceFormatPopup addItemWithTitle:@"Light Show Pro (.msq)"];
    _sourceFormatPopup.lastItem.tag = XLImportFormatLSP;
    [_sourceFormatPopup addItemWithTitle:@"FSEQ (.fseq)"];
    _sourceFormatPopup.lastItem.tag = XLImportFormatFSEQ;
    [_sourceFormatPopup setTarget:self];
    [_sourceFormatPopup setAction:@selector(sourceFormatChanged:)];

    NSStackView *srcRow = [XLBaseSheetController formRowWithLabel:@"Source Format:" control:_sourceFormatPopup labelWidth:kLabelWidth];
    [stack addArrangedSubview:srcRow];

    // Destination format
    _destFormatPopup = [XLBaseSheetController createPopUpButton];
    [_destFormatPopup addItemWithTitle:@"xLights Sequence (.xsq)"];
    _destFormatPopup.lastItem.tag = -1;
    [_destFormatPopup addItemWithTitle:@"FSEQ v2 (.fseq)"];
    _destFormatPopup.lastItem.tag = XLExportFormatFSEQ;
    [_destFormatPopup addItemWithTitle:@"Minleon NDB (.ndb)"];
    _destFormatPopup.lastItem.tag = XLExportFormatMinleon;
    [_destFormatPopup selectItemAtIndex:1];

    NSStackView *destRow = [XLBaseSheetController formRowWithLabel:@"Destination Format:" control:_destFormatPopup labelWidth:kLabelWidth];
    [stack addArrangedSubview:destRow];

    // Output directory
    NSStackView *outRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    outRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    outRow.spacing = 8;

    NSTextField *outLabel = [NSTextField labelWithString:@"Output Directory:"];
    outLabel.alignment = NSTextAlignmentRight;
    [outLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _outputDirField = [XLBaseSheetController createTextField];
    _outputDirField.editable = NO;
    _outputDirField.stringValue = _outputDirectory ?: @"";
    [_outputDirField.widthAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;

    _browseDirButton = [NSButton buttonWithTitle:@"Choose..." target:self action:@selector(browseOutputDir:)];

    [outRow addArrangedSubview:outLabel];
    [outRow addArrangedSubview:_outputDirField];
    [outRow addArrangedSubview:_browseDirButton];
    [stack addArrangedSubview:outRow];

    // Files table
    NSTextField *filesLabel = [NSTextField labelWithString:@"Source Files (select to convert):"];
    [stack addArrangedSubview:filesLabel];

    NSScrollView *filesScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    filesScroll.hasVerticalScroller = YES;
    filesScroll.borderType = NSBezelBorder;
    [filesScroll.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;

    _filesTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _filesTable.dataSource = self;
    _filesTable.delegate = self;
    _filesTable.rowHeight = 22;
    _filesTable.usesAlternatingRowBackgroundColors = YES;

    NSTableColumn *checkCol = [[NSTableColumn alloc] initWithIdentifier:@"check"];
    checkCol.width = 30;
    [_filesTable addTableColumn:checkCol];

    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameCol.title = @"File Name";
    nameCol.width = 300;
    [_filesTable addTableColumn:nameCol];

    NSTableColumn *sizeCol = [[NSTableColumn alloc] initWithIdentifier:@"size"];
    sizeCol.title = @"Size";
    sizeCol.width = 80;
    [_filesTable addTableColumn:sizeCol];

    NSTableColumn *modCol = [[NSTableColumn alloc] initWithIdentifier:@"modified"];
    modCol.title = @"Modified";
    modCol.width = 140;
    [_filesTable addTableColumn:modCol];

    filesScroll.documentView = _filesTable;
    [stack addArrangedSubview:filesScroll];
    [filesScroll.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [filesScroll.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    // Selected count
    _selectedCountLabel = [NSTextField labelWithString:@"0 files selected"];
    _selectedCountLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:_selectedCountLabel];

    // Options
    _overwriteCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Overwrite existing files"];
    _overwriteCheckbox.state = _overwriteExisting ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_overwriteCheckbox];

    _preserveStructureCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Preserve folder structure"];
    _preserveStructureCheckbox.state = _preserveFolderStructure ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_preserveStructureCheckbox];

    return stack;
}

- (void)sheetDidLoad {
    [self scanForSourceFiles];
}

- (void)scanForSourceFiles {
    [_sourceFiles removeAllObjects];

    if (!_showDirectory || _showDirectory.length == 0) {
        [_filesTable reloadData];
        return;
    }

    NSString *ext = [XLImportSequenceDialog fileExtensionForFormat:_sourceFormat];
    if (!ext) {
        [_filesTable reloadData];
        return;
    }

    [self scanDirectory:_showDirectory forExtension:ext];
    [_filesTable reloadData];
    [self updateSelectedCount];
}

- (void)scanDirectory:(NSString *)path forExtension:(NSString *)ext {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:path error:nil];

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm";

    for (NSString *item in contents) {
        if ([item hasPrefix:@"."]) continue;
        if ([item isEqualToString:@"Backup"]) continue;

        NSString *fullPath = [path stringByAppendingPathComponent:item];
        BOOL isDir = NO;

        if ([fm fileExistsAtPath:fullPath isDirectory:&isDir]) {
            if (isDir) {
                [self scanDirectory:fullPath forExtension:ext];
            } else {
                NSString *fileExt = item.pathExtension.lowercaseString;
                // Handle LOR with multiple extensions
                BOOL matches = [fileExt isEqualToString:ext];
                if (_sourceFormat == XLImportFormatLOR) {
                    matches = matches || [fileExt isEqualToString:@"lms"] ||
                              [fileExt isEqualToString:@"las"] || [fileExt isEqualToString:@"lss"];
                }

                if (matches) {
                    NSString *relativePath = [fullPath substringFromIndex:_showDirectory.length];
                    if ([relativePath hasPrefix:@"/"]) {
                        relativePath = [relativePath substringFromIndex:1];
                    }

                    NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
                    NSMutableDictionary *fileInfo = [NSMutableDictionary dictionary];
                    fileInfo[@"path"] = relativePath;
                    fileInfo[@"fullPath"] = fullPath;
                    fileInfo[@"name"] = item;
                    fileInfo[@"selected"] = @NO;

                    if (attrs) {
                        NSNumber *size = attrs[NSFileSize];
                        fileInfo[@"size"] = [NSByteCountFormatter stringFromByteCount:size.longLongValue
                                                                           countStyle:NSByteCountFormatterCountStyleFile];
                        NSDate *modDate = attrs[NSFileModificationDate];
                        if (modDate) {
                            fileInfo[@"modified"] = [dateFormatter stringFromDate:modDate];
                        }
                    }

                    [_sourceFiles addObject:fileInfo];
                }
            }
        }
    }
}

- (void)sourceFormatChanged:(id)sender {
    _sourceFormat = (XLImportFormat)_sourceFormatPopup.selectedItem.tag;
    [self scanForSourceFiles];
}

- (void)browseOutputDir:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = YES;
    panel.allowsMultipleSelection = NO;

    [panel beginSheetModalForWindow:self.sheet completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            self.outputDirField.stringValue = panel.URL.path;
            self.outputDirectory = panel.URL.path;
        }
    }];
}

- (void)updateSelectedCount {
    NSInteger count = 0;
    for (NSDictionary *file in _sourceFiles) {
        if ([file[@"selected"] boolValue]) {
            count++;
        }
    }
    _selectedCountLabel.stringValue = [NSString stringWithFormat:@"%ld file%@ selected",
                                        (long)count, count == 1 ? @"" : @"s"];
    [self updateOKButtonState];
}

- (NSArray<NSString *> *)selectedSourceFiles {
    NSMutableArray *selected = [NSMutableArray array];
    for (NSDictionary *file in _sourceFiles) {
        if ([file[@"selected"] boolValue]) {
            [selected addObject:file[@"fullPath"]];
        }
    }
    return [selected copy];
}

- (NSString *)validate {
    NSArray *selected = [self selectedSourceFiles];
    if (selected.count == 0) {
        return @"Please select at least one file to convert.";
    }
    if (_outputDirField.stringValue.length == 0) {
        return @"Please select an output directory.";
    }
    return nil;
}

- (void)okClicked:(id)sender {
    _outputDirectory = _outputDirField.stringValue;
    _overwriteExisting = (_overwriteCheckbox.state == NSControlStateValueOn);
    _preserveFolderStructure = (_preserveStructureCheckbox.state == NSControlStateValueOn);
    _destinationFormat = (XLExportFormat)_destFormatPopup.selectedItem.tag;
    [super okClicked:sender];
}

#pragma mark - NSTableViewDataSource/Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _sourceFiles.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row >= (NSInteger)_sourceFiles.count) return nil;

    NSDictionary *file = _sourceFiles[row];
    NSString *identifier = tableColumn.identifier;

    if ([identifier isEqualToString:@"check"]) {
        NSButton *checkbox = [tableView makeViewWithIdentifier:@"batchCheck" owner:self];
        if (!checkbox) {
            checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(fileCheckboxToggled:)];
            checkbox.identifier = @"batchCheck";
        }
        checkbox.state = [file[@"selected"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.tag = row;
        return checkbox;
    }

    NSTextField *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = identifier;
    }

    if ([identifier isEqualToString:@"name"]) {
        cell.stringValue = file[@"path"] ?: @"";
    } else if ([identifier isEqualToString:@"size"]) {
        cell.stringValue = file[@"size"] ?: @"";
    } else if ([identifier isEqualToString:@"modified"]) {
        cell.stringValue = file[@"modified"] ?: @"";
    }

    return cell;
}

- (void)fileCheckboxToggled:(NSButton *)sender {
    NSInteger row = sender.tag;
    if (row < (NSInteger)_sourceFiles.count) {
        _sourceFiles[row][@"selected"] = @(sender.state == NSControlStateValueOn);
        [self updateSelectedCount];
    }
}

@end

#pragma mark - XLConversionProgressDialog

@interface XLConversionProgressDialog ()

@property (nonatomic, strong, readwrite) NSWindow *window;
@property (nonatomic, strong) NSTextField *currentFileLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSProgressIndicator *fileProgressBar;
@property (nonatomic, strong) NSProgressIndicator *overallProgressBar;
@property (nonatomic, strong) NSTextView *logTextView;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, assign, readwrite) double overallProgress;
@property (nonatomic, assign, readwrite) BOOL isComplete;
@property (nonatomic, assign, readwrite) BOOL wasCancelled;

@end

@implementation XLConversionProgressDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        _overallProgress = 0.0;
        _isComplete = NO;
        _wasCancelled = NO;
        [self buildWindow];
    }
    return self;
}

- (void)buildWindow {
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 550, 400)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                            backing:NSBackingStoreBuffered
                                              defer:YES];
    _window.title = @"Conversion Progress";
    _window.releasedWhenClosed = NO;

    NSView *contentView = [[NSView alloc] initWithFrame:_window.contentView.bounds];
    _window.contentView = contentView;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);

    [contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];

    // Current file label
    _currentFileLabel = [NSTextField labelWithString:@"Preparing..."];
    _currentFileLabel.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:_currentFileLabel];
    [_currentFileLabel.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:20].active = YES;
    [_currentFileLabel.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:-20].active = YES;

    // File progress
    NSTextField *fileProgressLabel = [NSTextField labelWithString:@"Current File:"];
    fileProgressLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:fileProgressLabel];

    _fileProgressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _fileProgressBar.style = NSProgressIndicatorStyleBar;
    _fileProgressBar.indeterminate = NO;
    _fileProgressBar.minValue = 0;
    _fileProgressBar.maxValue = 1.0;
    [stack addArrangedSubview:_fileProgressBar];
    [_fileProgressBar.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:20].active = YES;
    [_fileProgressBar.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:-20].active = YES;

    // Overall progress
    NSTextField *overallProgressLabel = [NSTextField labelWithString:@"Overall Progress:"];
    overallProgressLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:overallProgressLabel];

    _overallProgressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _overallProgressBar.style = NSProgressIndicatorStyleBar;
    _overallProgressBar.indeterminate = NO;
    _overallProgressBar.minValue = 0;
    _overallProgressBar.maxValue = 1.0;
    [stack addArrangedSubview:_overallProgressBar];
    [_overallProgressBar.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:20].active = YES;
    [_overallProgressBar.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:-20].active = YES;

    // Status label
    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:_statusLabel];

    // Log text view
    NSTextField *logLabel = [NSTextField labelWithString:@"Conversion Log:"];
    [stack addArrangedSubview:logLabel];

    NSScrollView *logScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    logScroll.hasVerticalScroller = YES;
    logScroll.borderType = NSBezelBorder;
    [logScroll.heightAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;

    _logTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    _logTextView.editable = NO;
    _logTextView.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    logScroll.documentView = _logTextView;

    [stack addArrangedSubview:logScroll];
    [logScroll.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:20].active = YES;
    [logScroll.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:-20].active = YES;

    // Buttons
    NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 12;

    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    _cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelClicked:)];
    _closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeClicked:)];
    _closeButton.hidden = YES;
    _closeButton.keyEquivalent = @"\r";

    [buttonRow addArrangedSubview:spacer];
    [buttonRow addArrangedSubview:_cancelButton];
    [buttonRow addArrangedSubview:_closeButton];

    [stack addArrangedSubview:buttonRow];
    [buttonRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:-20].active = YES;
}

- (void)showForWindow:(NSWindow *)parentWindow {
    [_window center];
    [_window makeKeyAndOrderFront:nil];
}

- (void)close {
    [_window close];
}

- (void)cancelClicked:(id)sender {
    _wasCancelled = YES;
    _cancelButton.enabled = NO;
    _statusLabel.stringValue = @"Cancelling...";
    if (_onCancel) {
        _onCancel();
    }
}

- (void)closeClicked:(id)sender {
    [self close];
}

- (void)setCurrentFile:(NSString *)filename {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.currentFileLabel.stringValue = filename ?: @"";
    });
}

- (void)setStatusMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.stringValue = message ?: @"";
    });
}

- (void)setFileProgress:(double)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.fileProgressBar.doubleValue = progress;
    });
}

- (void)setOverallProgress:(double)progress {
    _overallProgress = progress;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.overallProgressBar.doubleValue = progress;
    });
}

- (void)markCompleteWithMessage:(NSString *)message success:(BOOL)success {
    _isComplete = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.fileProgressBar.doubleValue = 1.0;
        self.overallProgressBar.doubleValue = 1.0;
        self.cancelButton.hidden = YES;
        self.closeButton.hidden = NO;

        if (success) {
            self.currentFileLabel.stringValue = @"Conversion Complete";
            self.currentFileLabel.textColor = [NSColor systemGreenColor];
        } else {
            self.currentFileLabel.stringValue = @"Conversion Failed";
            self.currentFileLabel.textColor = [NSColor systemRedColor];
        }

        if (message) {
            self.statusLabel.stringValue = message;
        }
    });
}

- (void)addLogEntry:(NSString *)entry {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                             dateStyle:NSDateFormatterNoStyle
                                                             timeStyle:NSDateFormatterMediumStyle];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, entry];
        NSMutableString *log = [self.logTextView.string mutableCopy];
        [log appendString:line];
        self.logTextView.string = log;
        [self.logTextView scrollToEndOfDocument:nil];
    });
}

- (void)addErrorEntry:(NSString *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                             dateStyle:NSDateFormatterNoStyle
                                                             timeStyle:NSDateFormatterMediumStyle];

        NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"[%@] ERROR: %@\n", timestamp, error]
                attributes:@{
                    NSForegroundColorAttributeName: [NSColor systemRedColor],
                    NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular]
                }];

        [self.logTextView.textStorage appendAttributedString:attrStr];
        [self.logTextView scrollToEndOfDocument:nil];
    });
}

- (void)addWarningEntry:(NSString *)warning {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                             dateStyle:NSDateFormatterNoStyle
                                                             timeStyle:NSDateFormatterMediumStyle];

        NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"[%@] WARNING: %@\n", timestamp, warning]
                attributes:@{
                    NSForegroundColorAttributeName: [NSColor systemOrangeColor],
                    NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular]
                }];

        [self.logTextView.textStorage appendAttributedString:attrStr];
        [self.logTextView scrollToEndOfDocument:nil];
    });
}

@end

#pragma mark - XLImportSequenceDialog Helpers

@implementation XLImportSequenceDialog

+ (NSString *)fileExtensionForFormat:(XLImportFormat)format {
    switch (format) {
        case XLImportFormatVixen2:
            return @"vix";
        case XLImportFormatVixen3:
            return @"tim";
        case XLImportFormatLOR:
            return @"lms";
        case XLImportFormatHLS:
            return @"hlsseq";
        case XLImportFormatLSP:
            return @"msq";
        case XLImportFormatFSEQ:
            return @"fseq";
        case XLImportFormatSuperStar:
            return @"sup";
        case XLImportFormatGlediator:
            return @"led";
        case XLImportFormatConductor:
            return @"seq";
    }
    return nil;
}

+ (NSString *)displayNameForFormat:(XLImportFormat)format {
    switch (format) {
        case XLImportFormatVixen2:
            return @"Vixen 2";
        case XLImportFormatVixen3:
            return @"Vixen 3";
        case XLImportFormatLOR:
            return @"Light-O-Rama";
        case XLImportFormatHLS:
            return @"HLS";
        case XLImportFormatLSP:
            return @"Light Show Pro";
        case XLImportFormatFSEQ:
            return @"Falcon Player FSEQ";
        case XLImportFormatSuperStar:
            return @"SuperStar";
        case XLImportFormatGlediator:
            return @"Glediator";
        case XLImportFormatConductor:
            return @"Conductor";
    }
    return @"Unknown";
}

+ (XLImportFormat)formatFromFileExtension:(NSString *)extension {
    NSString *ext = extension.lowercaseString;
    if ([ext isEqualToString:@"vix"]) return XLImportFormatVixen2;
    if ([ext isEqualToString:@"tim"]) return XLImportFormatVixen3;
    if ([ext isEqualToString:@"lms"] || [ext isEqualToString:@"las"] || [ext isEqualToString:@"lss"]) return XLImportFormatLOR;
    if ([ext isEqualToString:@"hlsseq"]) return XLImportFormatHLS;
    if ([ext isEqualToString:@"msq"]) return XLImportFormatLSP;
    if ([ext isEqualToString:@"fseq"]) return XLImportFormatFSEQ;
    if ([ext isEqualToString:@"sup"]) return XLImportFormatSuperStar;
    if ([ext isEqualToString:@"led"]) return XLImportFormatGlediator;
    if ([ext isEqualToString:@"seq"]) return XLImportFormatConductor;
    return XLImportFormatFSEQ;
}

@end
