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

@implementation XLVixenImportDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Vixen Import";
        self.minWidth = 400;
        self.minHeight = 250;
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
    // TODO: Full implementation
    NSTextField *placeholder = [NSTextField labelWithString:@"Vixen import options will appear here"];
    return placeholder;
}

@end

@implementation XLLORImportDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"LOR Import";
        self.minWidth = 400;
        self.minHeight = 250;
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
    // TODO: Full implementation
    NSTextField *placeholder = [NSTextField labelWithString:@"LOR import options will appear here"];
    return placeholder;
}

@end

@implementation XLHLSImportDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"HLS Import";
        self.minWidth = 350;
        self.minHeight = 200;
        _importTimingTracks = YES;
        _importMappings = YES;
    }
    return self;
}

- (NSView *)buildContentView {
    // TODO: Full implementation
    NSTextField *placeholder = [NSTextField labelWithString:@"HLS import options will appear here"];
    return placeholder;
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
    // TODO: Full implementation
    NSTextField *placeholder = [NSTextField labelWithString:@"VSA import options will appear here"];
    return placeholder;
}

@end
