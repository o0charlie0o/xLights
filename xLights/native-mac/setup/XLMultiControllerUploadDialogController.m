/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLMultiControllerUploadDialogController.h"
#import "XLControllersViewController.h"
#import "../XLEngineBridge.h"

static const CGFloat kDialogWidth = 700.0;
static const CGFloat kDialogHeight = 560.0;
static const CGFloat kMargin = 16.0;
static const CGFloat kSmallMargin = 8.0;

// Table column identifiers
static NSString * const kColumnSelect     = @"Select";
static NSString * const kColumnName       = @"Name";
static NSString * const kColumnAddress    = @"Address";
static NSString * const kColumnMode       = @"Mode";
static NSString * const kColumnStatus     = @"Status";
static NSString * const kColumnProgress   = @"Progress";

#pragma mark - XLMultiUploadControllerEntry

@implementation XLMultiUploadControllerEntry

- (instancetype)init {
    self = [super init];
    if (self) {
        _selected = YES;
        _uploadMode = XLUploadModeBoth;
        _status = XLMultiUploadStatusPending;
    }
    return self;
}

@end

#pragma mark - XLMultiControllerUploadDialogController

@interface XLMultiControllerUploadDialogController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSMutableArray<XLMultiUploadControllerEntry *> *entries;
@property (nonatomic, assign) BOOL uploadInProgress;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) NSUInteger currentUploadIndex;

// UI elements - top controls
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *selectAllButton;
@property (nonatomic, strong) NSButton *deselectAllButton;
@property (nonatomic, strong) NSTextField *globalModeLabel;
@property (nonatomic, strong) NSPopUpButton *globalModePopup;

// UI elements - controller table
@property (nonatomic, strong) NSScrollView *tableScrollView;
@property (nonatomic, strong) NSTableView *tableView;

// UI elements - log area
@property (nonatomic, strong) NSScrollView *logScrollView;
@property (nonatomic, strong) NSTextView *logTextView;

// UI elements - bottom bar
@property (nonatomic, strong) NSProgressIndicator *overallProgressBar;
@property (nonatomic, strong) NSTextField *summaryLabel;
@property (nonatomic, strong) NSButton *uploadButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *closeButton;

// Splitter between table and log
@property (nonatomic, strong) NSSplitView *splitView;

@end

@implementation XLMultiControllerUploadDialogController

#pragma mark - Initialization

- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, kDialogWidth, kDialogHeight)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:YES];
    window.title = @"Bulk Controller Upload";
    window.minSize = NSMakeSize(550, 400);

    self = [super initWithWindow:window];
    if (self) {
        _engineBridge = engineBridge;
        _entries = [NSMutableArray array];
        _uploadInProgress = NO;
        _cancelled = NO;

        [self setupUI];
        [self loadControllers];
    }
    return self;
}

- (instancetype)init {
    return [self initWithEngineBridge:nil];
}

- (BOOL)isUploading {
    return _uploadInProgress;
}

#pragma mark - UI Setup

- (void)setupUI {
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;

    // Title
    _titleLabel = [NSTextField labelWithString:@"Select controllers to upload configuration:"];
    _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    _titleLabel.textColor = [NSColor labelColor];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_titleLabel];

    // Select All / Deselect All buttons
    _selectAllButton = [NSButton buttonWithTitle:@"Select All" target:self action:@selector(selectAllClicked:)];
    _selectAllButton.bezelStyle = NSBezelStyleRounded;
    _selectAllButton.controlSize = NSControlSizeSmall;
    _selectAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_selectAllButton];

    _deselectAllButton = [NSButton buttonWithTitle:@"Deselect All" target:self action:@selector(deselectAllClicked:)];
    _deselectAllButton.bezelStyle = NSBezelStyleRounded;
    _deselectAllButton.controlSize = NSControlSizeSmall;
    _deselectAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_deselectAllButton];

    // Global upload mode
    _globalModeLabel = [NSTextField labelWithString:@"Set All Modes:"];
    _globalModeLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    _globalModeLabel.textColor = [NSColor secondaryLabelColor];
    _globalModeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_globalModeLabel];

    _globalModePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _globalModePopup.controlSize = NSControlSizeSmall;
    [_globalModePopup addItemsWithTitles:@[@"Combined", @"Output Only", @"Input Only"]];
    _globalModePopup.target = self;
    _globalModePopup.action = @selector(globalModeChanged:);
    _globalModePopup.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_globalModePopup];

    // Split view for table + log
    _splitView = [[NSSplitView alloc] initWithFrame:NSZeroRect];
    _splitView.vertical = NO;
    _splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_splitView];

    // Controller table
    [self setupTableView];
    [_splitView addSubview:_tableScrollView];

    // Log area
    [self setupLogView];
    [_splitView addSubview:_logScrollView];

    // Overall progress bar
    _overallProgressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _overallProgressBar.style = NSProgressIndicatorStyleBar;
    _overallProgressBar.indeterminate = NO;
    _overallProgressBar.minValue = 0.0;
    _overallProgressBar.maxValue = 100.0;
    _overallProgressBar.doubleValue = 0.0;
    _overallProgressBar.translatesAutoresizingMaskIntoConstraints = NO;
    _overallProgressBar.hidden = YES;
    [contentView addSubview:_overallProgressBar];

    // Summary label
    _summaryLabel = [NSTextField labelWithString:@""];
    _summaryLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _summaryLabel.textColor = [NSColor secondaryLabelColor];
    _summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_summaryLabel];

    // Upload button
    _uploadButton = [NSButton buttonWithTitle:@"Upload Selected" target:self action:@selector(uploadClicked:)];
    _uploadButton.bezelStyle = NSBezelStyleRounded;
    _uploadButton.keyEquivalent = @"\r";
    _uploadButton.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_uploadButton];

    // Cancel button
    _cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelClicked:)];
    _cancelButton.bezelStyle = NSBezelStyleRounded;
    _cancelButton.keyEquivalent = @"\033";
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_cancelButton];

    // Close button (hidden until upload complete)
    _closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeClicked:)];
    _closeButton.bezelStyle = NSBezelStyleRounded;
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _closeButton.hidden = YES;
    [contentView addSubview:_closeButton];

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        // Title
        [_titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:kMargin],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:kMargin],

        // Select All / Deselect All (right side of title row)
        [_deselectAllButton.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_deselectAllButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kMargin],

        [_selectAllButton.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_selectAllButton.trailingAnchor constraintEqualToAnchor:_deselectAllButton.leadingAnchor constant:-kSmallMargin],

        // Global mode selector row
        [_globalModeLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:kSmallMargin],
        [_globalModeLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:kMargin],
        [_globalModeLabel.centerYAnchor constraintEqualToAnchor:_globalModePopup.centerYAnchor],

        [_globalModePopup.leadingAnchor constraintEqualToAnchor:_globalModeLabel.trailingAnchor constant:kSmallMargin],
        [_globalModePopup.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:kSmallMargin - 2],
        [_globalModePopup.widthAnchor constraintEqualToConstant:130],

        // Split view (table + log)
        [_splitView.topAnchor constraintEqualToAnchor:_globalModePopup.bottomAnchor constant:kSmallMargin],
        [_splitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:kMargin],
        [_splitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kMargin],
        [_splitView.bottomAnchor constraintEqualToAnchor:_overallProgressBar.topAnchor constant:-kSmallMargin],

        // Overall progress bar
        [_overallProgressBar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:kMargin],
        [_overallProgressBar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kMargin],
        [_overallProgressBar.bottomAnchor constraintEqualToAnchor:_summaryLabel.topAnchor constant:-kSmallMargin],
        [_overallProgressBar.heightAnchor constraintEqualToConstant:8],

        // Summary label
        [_summaryLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:kMargin],
        [_summaryLabel.bottomAnchor constraintEqualToAnchor:_uploadButton.topAnchor constant:-kSmallMargin],
        [_summaryLabel.trailingAnchor constraintEqualToAnchor:_uploadButton.leadingAnchor constant:-kMargin],

        // Buttons at bottom right
        [_uploadButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kMargin],
        [_uploadButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-kMargin],
        [_uploadButton.widthAnchor constraintGreaterThanOrEqualToConstant:120],

        [_cancelButton.trailingAnchor constraintEqualToAnchor:_uploadButton.leadingAnchor constant:-kSmallMargin],
        [_cancelButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-kMargin],
        [_cancelButton.widthAnchor constraintGreaterThanOrEqualToConstant:80],

        [_closeButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-kMargin],
        [_closeButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-kMargin],
        [_closeButton.widthAnchor constraintGreaterThanOrEqualToConstant:80],
    ]];
}

- (void)setupTableView {
    _tableScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kDialogWidth - 2 * kMargin, 200)];
    _tableScrollView.hasVerticalScroller = YES;
    _tableScrollView.hasHorizontalScroller = NO;
    _tableScrollView.autohidesScrollers = YES;
    _tableScrollView.borderType = NSBezelBorder;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.allowsMultipleSelection = NO;
    _tableView.rowSizeStyle = NSTableViewRowSizeStyleDefault;
    _tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;

    if (@available(macOS 11.0, *)) {
        _tableView.style = NSTableViewStyleInset;
    }

    // Checkbox column
    NSTableColumn *selectCol = [[NSTableColumn alloc] initWithIdentifier:kColumnSelect];
    selectCol.title = @"";
    selectCol.minWidth = 30;
    selectCol.maxWidth = 30;
    selectCol.width = 30;
    [_tableView addTableColumn:selectCol];

    // Name column
    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:kColumnName];
    nameCol.title = @"Controller";
    nameCol.minWidth = 100;
    nameCol.maxWidth = 300;
    nameCol.width = 160;
    [_tableView addTableColumn:nameCol];

    // Address column
    NSTableColumn *addrCol = [[NSTableColumn alloc] initWithIdentifier:kColumnAddress];
    addrCol.title = @"Address";
    addrCol.minWidth = 80;
    addrCol.maxWidth = 200;
    addrCol.width = 120;
    [_tableView addTableColumn:addrCol];

    // Upload mode column
    NSTableColumn *modeCol = [[NSTableColumn alloc] initWithIdentifier:kColumnMode];
    modeCol.title = @"Upload Mode";
    modeCol.minWidth = 100;
    modeCol.maxWidth = 160;
    modeCol.width = 120;
    [_tableView addTableColumn:modeCol];

    // Status column
    NSTableColumn *statusCol = [[NSTableColumn alloc] initWithIdentifier:kColumnStatus];
    statusCol.title = @"Status";
    statusCol.minWidth = 80;
    statusCol.maxWidth = 200;
    statusCol.width = 120;
    [_tableView addTableColumn:statusCol];

    // Progress column
    NSTableColumn *progressCol = [[NSTableColumn alloc] initWithIdentifier:kColumnProgress];
    progressCol.title = @"";
    progressCol.minWidth = 24;
    progressCol.maxWidth = 32;
    progressCol.width = 28;
    [_tableView addTableColumn:progressCol];

    _tableScrollView.documentView = _tableView;
}

- (void)setupLogView {
    _logScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kDialogWidth - 2 * kMargin, 120)];
    _logScrollView.hasVerticalScroller = YES;
    _logScrollView.hasHorizontalScroller = NO;
    _logScrollView.autohidesScrollers = YES;
    _logScrollView.borderType = NSBezelBorder;

    _logTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    _logTextView.editable = NO;
    _logTextView.selectable = YES;
    _logTextView.backgroundColor = [NSColor textBackgroundColor];
    _logTextView.textColor = [NSColor labelColor];
    _logTextView.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    _logTextView.textContainerInset = NSMakeSize(4, 4);
    [_logTextView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _logScrollView.documentView = _logTextView;
}

#pragma mark - Data Loading

- (void)loadControllers {
    [_entries removeAllObjects];

    if (!_engineBridge) return;

    NSArray<NSString *> *controllerNames = [_engineBridge getControllerNames];
    if (!controllerNames) return;

    for (NSString *name in controllerNames) {
        NSDictionary *info = [_engineBridge getControllerInfo:name];
        if (!info) continue;

        // Skip inactive controllers
        NSString *active = info[XLControllerColumnActive];
        if ([active caseInsensitiveCompare:@"Inactive"] == NSOrderedSame) continue;

        XLMultiUploadControllerEntry *entry = [[XLMultiUploadControllerEntry alloc] init];
        entry.name = name;
        entry.address = info[XLControllerColumnAddress] ?: @"";
        entry.selected = YES;
        entry.uploadMode = XLUploadModeBoth;
        entry.status = XLMultiUploadStatusPending;
        entry.statusMessage = @"Ready";

        [_entries addObject:entry];
    }

    [_tableView reloadData];
    [self updateSelectedCount];
}

#pragma mark - Presentation

- (void)presentAsSheetOnWindow:(NSWindow *)parentWindow {
    [self loadControllers];
    [self resetUIForSelection];
    [parentWindow beginSheet:self.window completionHandler:nil];
}

- (void)presentAsWindow {
    [self loadControllers];
    [self resetUIForSelection];
    [self.window center];
    [self showWindow:nil];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_entries.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView
    viewForTableColumn:(NSTableColumn *)tableColumn
                   row:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= _entries.count) return nil;

    XLMultiUploadControllerEntry *entry = _entries[row];
    NSString *identifier = tableColumn.identifier;

    if ([identifier isEqualToString:kColumnSelect]) {
        return [self checkboxCellForEntry:entry row:row reusingView:
                [tableView makeViewWithIdentifier:@"CheckboxCell" owner:self]];
    }

    if ([identifier isEqualToString:kColumnMode]) {
        return [self modeCellForEntry:entry row:row reusingView:
                [tableView makeViewWithIdentifier:@"ModeCell" owner:self]];
    }

    if ([identifier isEqualToString:kColumnProgress]) {
        return [self progressCellForEntry:entry reusingView:
                [tableView makeViewWithIdentifier:@"ProgressCell" owner:self]];
    }

    if ([identifier isEqualToString:kColumnStatus]) {
        return [self statusCellForEntry:entry reusingView:
                [tableView makeViewWithIdentifier:@"StatusTextCell" owner:self]];
    }

    // Text cell for Name and Address
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [self makeTextCellWithIdentifier:identifier];
    }

    if ([identifier isEqualToString:kColumnName]) {
        cell.textField.stringValue = entry.name ?: @"";
    } else if ([identifier isEqualToString:kColumnAddress]) {
        cell.textField.stringValue = entry.address ?: @"";
    }

    cell.textField.textColor = entry.selected ? [NSColor labelColor] : [NSColor tertiaryLabelColor];

    return cell;
}

#pragma mark - Cell Factories

- (NSTableCellView *)makeTextCellWithIdentifier:(NSString *)identifier {
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
    cell.identifier = identifier;

    NSTextField *textField = [NSTextField labelWithString:@""];
    textField.lineBreakMode = NSLineBreakByTruncatingTail;
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:textField];
    cell.textField = textField;

    [NSLayoutConstraint activateConstraints:@[
        [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
        [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
        [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];

    return cell;
}

- (NSView *)checkboxCellForEntry:(XLMultiUploadControllerEntry *)entry
                             row:(NSInteger)row
                     reusingView:(NSView *)existingView {
    NSTableCellView *cell = (NSTableCellView *)existingView;
    NSButton *checkbox;

    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"CheckboxCell";

        checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxToggled:)];
        checkbox.translatesAutoresizingMaskIntoConstraints = NO;
        checkbox.tag = row;
        [cell addSubview:checkbox];

        [NSLayoutConstraint activateConstraints:@[
            [checkbox.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor],
            [checkbox.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    } else {
        checkbox = (NSButton *)[cell viewWithTag:row];
        if (!checkbox) {
            for (NSView *subview in cell.subviews) {
                if ([subview isKindOfClass:[NSButton class]]) {
                    checkbox = (NSButton *)subview;
                    break;
                }
            }
        }
    }

    if (checkbox) {
        checkbox.state = entry.selected ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.tag = row;
        checkbox.enabled = !_uploadInProgress;
    }

    return cell;
}

- (NSView *)modeCellForEntry:(XLMultiUploadControllerEntry *)entry
                         row:(NSInteger)row
                 reusingView:(NSView *)existingView {
    NSTableCellView *cell = (NSTableCellView *)existingView;
    NSPopUpButton *popup;

    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"ModeCell";

        popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        popup.controlSize = NSControlSizeSmall;
        [popup addItemsWithTitles:@[@"Combined", @"Output Only", @"Input Only"]];
        popup.target = self;
        popup.action = @selector(rowModeChanged:);
        popup.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:popup];

        [NSLayoutConstraint activateConstraints:@[
            [popup.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [popup.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [popup.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    } else {
        popup = nil;
        for (NSView *subview in cell.subviews) {
            if ([subview isKindOfClass:[NSPopUpButton class]]) {
                popup = (NSPopUpButton *)subview;
                break;
            }
        }
    }

    if (popup) {
        [popup selectItemAtIndex:entry.uploadMode];
        popup.tag = row;
        popup.enabled = !_uploadInProgress;
    }

    return cell;
}

- (NSView *)statusCellForEntry:(XLMultiUploadControllerEntry *)entry
                   reusingView:(NSView *)existingView {
    NSTableCellView *cell = (NSTableCellView *)existingView;
    if (!cell) {
        cell = [self makeTextCellWithIdentifier:@"StatusTextCell"];
    }

    cell.textField.stringValue = entry.statusMessage ?: @"";

    switch (entry.status) {
        case XLMultiUploadStatusPending:
            cell.textField.textColor = [NSColor secondaryLabelColor];
            break;
        case XLMultiUploadStatusInProgress:
            cell.textField.textColor = [NSColor systemBlueColor];
            break;
        case XLMultiUploadStatusSuccess:
            cell.textField.textColor = [NSColor systemGreenColor];
            break;
        case XLMultiUploadStatusFailed:
            cell.textField.textColor = [NSColor systemRedColor];
            break;
        case XLMultiUploadStatusCancelled:
            cell.textField.textColor = [NSColor systemOrangeColor];
            break;
    }

    return cell;
}

- (NSView *)progressCellForEntry:(XLMultiUploadControllerEntry *)entry
                     reusingView:(NSView *)existingView {
    NSTableCellView *cell = (NSTableCellView *)existingView;
    NSImageView *imageView;

    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"ProgressCell";

        imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:imageView];
        cell.imageView = imageView;

        [NSLayoutConstraint activateConstraints:@[
            [imageView.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor],
            [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [imageView.widthAnchor constraintEqualToConstant:16],
            [imageView.heightAnchor constraintEqualToConstant:16],
        ]];
    } else {
        imageView = cell.imageView;
    }

    switch (entry.status) {
        case XLMultiUploadStatusPending:
            imageView.image = nil;
            imageView.contentTintColor = nil;
            break;
        case XLMultiUploadStatusInProgress:
            imageView.image = [NSImage imageWithSystemSymbolName:@"arrow.triangle.2.circlepath"
                                       accessibilityDescription:@"In Progress"];
            imageView.contentTintColor = [NSColor systemBlueColor];
            break;
        case XLMultiUploadStatusSuccess:
            imageView.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill"
                                       accessibilityDescription:@"Success"];
            imageView.contentTintColor = [NSColor systemGreenColor];
            break;
        case XLMultiUploadStatusFailed:
            imageView.image = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill"
                                       accessibilityDescription:@"Failed"];
            imageView.contentTintColor = [NSColor systemRedColor];
            break;
        case XLMultiUploadStatusCancelled:
            imageView.image = [NSImage imageWithSystemSymbolName:@"slash.circle"
                                       accessibilityDescription:@"Cancelled"];
            imageView.contentTintColor = [NSColor systemOrangeColor];
            break;
    }

    return cell;
}

#pragma mark - Button Actions

- (void)selectAllClicked:(id)sender {
    for (XLMultiUploadControllerEntry *entry in _entries) {
        entry.selected = YES;
    }
    [_tableView reloadData];
    [self updateSelectedCount];
}

- (void)deselectAllClicked:(id)sender {
    for (XLMultiUploadControllerEntry *entry in _entries) {
        entry.selected = NO;
    }
    [_tableView reloadData];
    [self updateSelectedCount];
}

- (void)globalModeChanged:(id)sender {
    XLUploadMode mode = (XLUploadMode)_globalModePopup.indexOfSelectedItem;
    for (XLMultiUploadControllerEntry *entry in _entries) {
        entry.uploadMode = mode;
    }
    [_tableView reloadData];
}

- (void)checkboxToggled:(id)sender {
    NSButton *checkbox = (NSButton *)sender;
    NSInteger row = [_tableView rowForView:checkbox];
    if (row < 0 || (NSUInteger)row >= _entries.count) return;

    _entries[row].selected = (checkbox.state == NSControlStateValueOn);
    [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
                          columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _tableView.numberOfColumns)]];
    [self updateSelectedCount];
}

- (void)rowModeChanged:(id)sender {
    NSPopUpButton *popup = (NSPopUpButton *)sender;
    NSInteger row = [_tableView rowForView:popup];
    if (row < 0 || (NSUInteger)row >= _entries.count) return;

    _entries[row].uploadMode = (XLUploadMode)popup.indexOfSelectedItem;
}

- (void)uploadClicked:(id)sender {
    [self startUpload];
}

- (void)cancelClicked:(id)sender {
    if (_uploadInProgress) {
        [self cancelUpload];
    } else {
        [self dismissDialog];
    }
}

- (void)closeClicked:(id)sender {
    [self dismissDialog];

    if ([_delegate respondsToSelector:@selector(multiControllerUploadDialog:didCompleteWithResults:)]) {
        [_delegate multiControllerUploadDialog:self didCompleteWithResults:[_entries copy]];
    }
}

#pragma mark - UI State Management

- (void)resetUIForSelection {
    _overallProgressBar.hidden = YES;
    _overallProgressBar.doubleValue = 0.0;
    _summaryLabel.stringValue = @"";
    _logTextView.string = @"";

    _uploadButton.hidden = NO;
    _uploadButton.enabled = YES;
    _cancelButton.hidden = NO;
    _cancelButton.enabled = YES;
    _cancelButton.title = @"Close";
    _closeButton.hidden = YES;

    _selectAllButton.enabled = YES;
    _deselectAllButton.enabled = YES;
    _globalModePopup.enabled = YES;

    for (XLMultiUploadControllerEntry *entry in _entries) {
        entry.status = XLMultiUploadStatusPending;
        entry.statusMessage = @"Ready";
    }

    [_tableView reloadData];
    [self updateSelectedCount];
}

- (void)transitionToUploadingState {
    _uploadButton.hidden = YES;
    _cancelButton.title = @"Cancel";
    _cancelButton.enabled = YES;
    _closeButton.hidden = YES;

    _selectAllButton.enabled = NO;
    _deselectAllButton.enabled = NO;
    _globalModePopup.enabled = NO;

    _overallProgressBar.hidden = NO;
    _overallProgressBar.doubleValue = 0.0;
}

- (void)transitionToCompletedState {
    _uploadButton.hidden = YES;
    _cancelButton.hidden = YES;
    _closeButton.hidden = NO;
    _closeButton.keyEquivalent = @"\r";

    _overallProgressBar.doubleValue = 100.0;

    NSUInteger successCount = 0, failedCount = 0, cancelledCount = 0;
    for (XLMultiUploadControllerEntry *entry in _entries) {
        if (!entry.selected) continue;
        switch (entry.status) {
            case XLMultiUploadStatusSuccess: successCount++; break;
            case XLMultiUploadStatusFailed: failedCount++; break;
            case XLMultiUploadStatusCancelled: cancelledCount++; break;
            default: break;
        }
    }

    if (_cancelled) {
        _summaryLabel.stringValue = [NSString stringWithFormat:@"Cancelled. %lu succeeded, %lu cancelled.",
                                     (unsigned long)successCount, (unsigned long)cancelledCount];
        _summaryLabel.textColor = [NSColor systemOrangeColor];
    } else if (failedCount == 0) {
        _summaryLabel.stringValue = [NSString stringWithFormat:@"All %lu controllers uploaded successfully.",
                                     (unsigned long)successCount];
        _summaryLabel.textColor = [NSColor systemGreenColor];
    } else if (successCount == 0) {
        _summaryLabel.stringValue = [NSString stringWithFormat:@"All %lu controllers failed.",
                                     (unsigned long)failedCount];
        _summaryLabel.textColor = [NSColor systemRedColor];
    } else {
        _summaryLabel.stringValue = [NSString stringWithFormat:@"%lu succeeded, %lu failed.",
                                     (unsigned long)successCount, (unsigned long)failedCount];
        _summaryLabel.textColor = [NSColor systemYellowColor];
    }
}

- (void)updateSelectedCount {
    NSUInteger selectedCount = 0;
    for (XLMultiUploadControllerEntry *entry in _entries) {
        if (entry.selected) selectedCount++;
    }

    _uploadButton.enabled = (selectedCount > 0);
    _titleLabel.stringValue = [NSString stringWithFormat:@"Select controllers to upload configuration (%lu of %lu selected):",
                               (unsigned long)selectedCount, (unsigned long)_entries.count];
}

#pragma mark - Upload Process

- (void)startUpload {
    // Collect selected entries
    NSMutableArray<XLMultiUploadControllerEntry *> *toUpload = [NSMutableArray array];
    for (XLMultiUploadControllerEntry *entry in _entries) {
        if (entry.selected) {
            [toUpload addObject:entry];
        }
    }

    if (toUpload.count == 0) return;

    _uploadInProgress = YES;
    _cancelled = NO;
    _currentUploadIndex = 0;

    [self transitionToUploadingState];

    [self appendLogMessage:@"=== Starting Bulk Upload ===\n" color:[NSColor labelColor]];
    [self appendLogMessage:[NSString stringWithFormat:@"Uploading to %lu controller(s)...\n\n",
                            (unsigned long)toUpload.count]
                     color:[NSColor secondaryLabelColor]];

    [_tableView reloadData];
    [self uploadNextSelectedController];
}

- (void)cancelUpload {
    if (!_uploadInProgress) return;

    _cancelled = YES;
    _cancelButton.enabled = NO;

    for (XLMultiUploadControllerEntry *entry in _entries) {
        if (entry.selected && entry.status == XLMultiUploadStatusPending) {
            entry.status = XLMultiUploadStatusCancelled;
            entry.statusMessage = @"Cancelled";
        }
    }

    [self appendLogMessage:@"\nUpload cancelled by user.\n" color:[NSColor systemOrangeColor]];
    [_tableView reloadData];
}

- (void)uploadNextSelectedController {
    // Find next selected, pending entry
    XLMultiUploadControllerEntry *nextEntry = nil;
    for (XLMultiUploadControllerEntry *entry in _entries) {
        if (entry.selected && entry.status == XLMultiUploadStatusPending) {
            nextEntry = entry;
            break;
        }
    }

    if (!nextEntry || _cancelled) {
        [self finishUpload];
        return;
    }

    nextEntry.status = XLMultiUploadStatusInProgress;
    nextEntry.statusMessage = @"Uploading...";
    [self reloadRowForEntry:nextEntry];

    // Update overall progress
    NSUInteger completedCount = [self completedCount];
    NSUInteger totalSelected = [self selectedCount];
    if (totalSelected > 0) {
        _overallProgressBar.doubleValue = (double)completedCount / (double)totalSelected * 100.0;
    }

    [self appendLogMessage:[NSString stringWithFormat:@"--- %@ (%@) ---\n", nextEntry.name, nextEntry.address]
                     color:[NSColor labelColor]];

    [self performUploadForEntry:nextEntry];
}

- (void)performUploadForEntry:(XLMultiUploadControllerEntry *)entry {
    switch (entry.uploadMode) {
        case XLUploadModeBoth: {
            [self uploadInputForEntry:entry thenOutput:YES];
            break;
        }

        case XLUploadModeOutputOnly: {
            __weak typeof(self) weakSelf = self;
            [self appendLogMessage:@"  Uploading output configuration...\n" color:[NSColor secondaryLabelColor]];
            [_engineBridge uploadOutputToController:entry.name completion:^(BOOL success, NSString *message) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    [strongSelf handleSingleResult:success message:message forEntry:entry];
                });
            }];
            break;
        }

        case XLUploadModeInputOnly: {
            __weak typeof(self) weakSelf = self;
            [self appendLogMessage:@"  Uploading input configuration...\n" color:[NSColor secondaryLabelColor]];
            [_engineBridge uploadInputToController:entry.name completion:^(BOOL success, NSString *message) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf) return;
                    [strongSelf handleSingleResult:success message:message forEntry:entry];
                });
            }];
            break;
        }
    }
}

- (void)uploadInputForEntry:(XLMultiUploadControllerEntry *)entry thenOutput:(BOOL)thenOutput {
    [self appendLogMessage:@"  Uploading input configuration...\n" color:[NSColor secondaryLabelColor]];

    __weak typeof(self) weakSelf = self;

    [_engineBridge uploadInputToController:entry.name completion:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            if (success) {
                [strongSelf appendLogMessage:[NSString stringWithFormat:@"  Input: %@\n", message ?: @"OK"]
                                       color:[NSColor systemGreenColor]];
            } else {
                [strongSelf appendLogMessage:[NSString stringWithFormat:@"  Input: %@\n", message ?: @"Failed"]
                                       color:[NSColor systemRedColor]];
            }

            if (thenOutput) {
                [strongSelf uploadOutputForEntry:entry inputSuccess:success];
            } else {
                [strongSelf handleSingleResult:success message:message forEntry:entry];
            }
        });
    }];
}

- (void)uploadOutputForEntry:(XLMultiUploadControllerEntry *)entry inputSuccess:(BOOL)inputSuccess {
    if (_cancelled) {
        entry.status = XLMultiUploadStatusCancelled;
        entry.statusMessage = @"Cancelled";
        [self reloadRowForEntry:entry];
        [self uploadNextSelectedController];
        return;
    }

    [self appendLogMessage:@"  Uploading output configuration...\n" color:[NSColor secondaryLabelColor]];

    __weak typeof(self) weakSelf = self;

    [_engineBridge uploadOutputToController:entry.name completion:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            if (success) {
                [strongSelf appendLogMessage:[NSString stringWithFormat:@"  Output: %@\n", message ?: @"OK"]
                                       color:[NSColor systemGreenColor]];
            } else {
                [strongSelf appendLogMessage:[NSString stringWithFormat:@"  Output: %@\n", message ?: @"Failed"]
                                       color:[NSColor systemRedColor]];
            }

            BOOL overallSuccess = inputSuccess && success;
            if (overallSuccess) {
                entry.status = XLMultiUploadStatusSuccess;
                entry.statusMessage = @"Success";
                [strongSelf appendLogMessage:@"  Done.\n\n" color:[NSColor labelColor]];
            } else {
                entry.status = XLMultiUploadStatusFailed;
                entry.statusMessage = [NSString stringWithFormat:@"Input: %@, Output: %@",
                                       inputSuccess ? @"OK" : @"Failed",
                                       success ? @"OK" : @"Failed"];
                [strongSelf appendLogMessage:@"  Upload failed.\n\n" color:[NSColor systemRedColor]];
            }

            [strongSelf reloadRowForEntry:entry];
            [strongSelf uploadNextSelectedController];
        });
    }];
}

- (void)handleSingleResult:(BOOL)success message:(NSString *)message forEntry:(XLMultiUploadControllerEntry *)entry {
    if (success) {
        entry.status = XLMultiUploadStatusSuccess;
        entry.statusMessage = @"Success";
        [self appendLogMessage:[NSString stringWithFormat:@"  Result: %@\n\n", message ?: @"OK"]
                         color:[NSColor systemGreenColor]];
    } else {
        entry.status = XLMultiUploadStatusFailed;
        entry.statusMessage = message ?: @"Failed";
        [self appendLogMessage:[NSString stringWithFormat:@"  Result: %@\n\n", message ?: @"Failed"]
                         color:[NSColor systemRedColor]];
    }

    [self reloadRowForEntry:entry];
    [self uploadNextSelectedController];
}

- (void)finishUpload {
    _uploadInProgress = NO;

    [self appendLogMessage:@"=== Upload Complete ===\n" color:[NSColor labelColor]];
    [self transitionToCompletedState];
    [_tableView reloadData];
}

#pragma mark - Helpers

- (NSUInteger)selectedCount {
    NSUInteger count = 0;
    for (XLMultiUploadControllerEntry *entry in _entries) {
        if (entry.selected) count++;
    }
    return count;
}

- (NSUInteger)completedCount {
    NSUInteger count = 0;
    for (XLMultiUploadControllerEntry *entry in _entries) {
        if (!entry.selected) continue;
        if (entry.status == XLMultiUploadStatusSuccess ||
            entry.status == XLMultiUploadStatusFailed ||
            entry.status == XLMultiUploadStatusCancelled) {
            count++;
        }
    }
    return count;
}

- (void)reloadRowForEntry:(XLMultiUploadControllerEntry *)entry {
    NSUInteger idx = [_entries indexOfObject:entry];
    if (idx != NSNotFound) {
        [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:idx]
                              columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _tableView.numberOfColumns)]];
    }
}

- (void)dismissDialog {
    if (self.window.sheetParent) {
        [self.window.sheetParent endSheet:self.window];
    } else {
        [self.window close];
    }
}

#pragma mark - Log Output

- (void)appendLogMessage:(NSString *)message color:(NSColor *)color {
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: color ?: [NSColor labelColor]
    };

    NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:message attributes:attrs];
    [[_logTextView textStorage] appendAttributedString:attrString];
    [_logTextView scrollRangeToVisible:NSMakeRange(_logTextView.string.length, 0)];
}

@end
