/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLDiscoveryResultsViewController.h"

static NSString * const kColumnIP = @"IP";
static NSString * const kColumnHostname = @"Hostname";
static NSString * const kColumnVendor = @"Vendor";
static NSString * const kColumnMode = @"Mode";
static NSString * const kColumnVersion = @"Version";
static NSString * const kColumnConfigured = @"Configured";

static const CGFloat kPopoverWidth = 550.0;
static const CGFloat kPopoverHeight = 350.0;
static const CGFloat kButtonBarHeight = 40.0;

@interface XLDiscoveryResultsViewController ()

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSView *buttonBar;
@property (nonatomic, strong) NSButton *addButton;
@property (nonatomic, strong) NSButton *rescanButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSArray<NSDictionary *> *results;
@property (nonatomic, assign) XLDiscoveryState currentState;

@end

@implementation XLDiscoveryResultsViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _results = @[];
        _currentState = XLDiscoveryStateIdle;
    }
    return self;
}

- (void)dealloc {
    _tableView.dataSource = nil;
    _tableView.delegate = nil;
}

- (void)loadView {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPopoverWidth, kPopoverHeight)];
    container.wantsLayer = YES;
    self.view = container;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupHeader];
    [self setupTableView];
    [self setupButtonBar];
    [self layoutSubviews];
    [self updateUIForState:_currentState];
}

- (void)setupHeader {
    // Status label and spinner
    _statusLabel = [NSTextField labelWithString:@"Discovering controllers..."];
    _statusLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.alignment = NSTextAlignmentLeft;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_statusLabel];

    _spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_spinner];

    [NSLayoutConstraint activateConstraints:@[
        [_statusLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:12.0],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12.0],

        [_spinner.centerYAnchor constraintEqualToAnchor:_statusLabel.centerYAnchor],
        [_spinner.leadingAnchor constraintEqualToAnchor:_statusLabel.trailingAnchor constant:8.0],
        [_spinner.widthAnchor constraintEqualToConstant:16.0],
        [_spinner.heightAnchor constraintEqualToConstant:16.0],
    ]];
}

- (void)setupTableView {
    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers = YES;
    _scrollView.borderType = NSBezelBorder;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scrollView];

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.allowsMultipleSelection = YES;
    _tableView.allowsColumnReordering = NO;
    _tableView.rowSizeStyle = NSTableViewRowSizeStyleDefault;

    if (@available(macOS 11.0, *)) {
        _tableView.style = NSTableViewStyleInset;
    }

    [self addColumn:kColumnIP title:@"IP Address" width:110];
    [self addColumn:kColumnHostname title:@"Hostname" width:140];
    [self addColumn:kColumnVendor title:@"Vendor" width:100];
    [self addColumn:kColumnMode title:@"Mode" width:70];
    [self addColumn:kColumnVersion title:@"Version" width:60];
    [self addColumn:kColumnConfigured title:@"" width:24];

    _scrollView.documentView = _tableView;
}

- (void)addColumn:(NSString *)identifier title:(NSString *)title width:(CGFloat)width {
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
    column.title = title;
    column.width = width;
    column.minWidth = width * 0.5;
    column.maxWidth = width * 2.0;
    [_tableView addTableColumn:column];
}

- (void)setupButtonBar {
    _buttonBar = [[NSView alloc] initWithFrame:NSZeroRect];
    _buttonBar.wantsLayer = YES;
    _buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_buttonBar];

    // Rescan button
    _rescanButton = [NSButton buttonWithTitle:@"Rescan"
                                       target:self
                                       action:@selector(rescanClicked:)];
    _rescanButton.bezelStyle = NSBezelStyleRounded;
    _rescanButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_buttonBar addSubview:_rescanButton];

    // Add button
    _addButton = [NSButton buttonWithTitle:@"Add Selected"
                                    target:self
                                    action:@selector(addClicked:)];
    _addButton.bezelStyle = NSBezelStyleRounded;
    _addButton.keyEquivalent = @"\r";
    _addButton.translatesAutoresizingMaskIntoConstraints = NO;
    _addButton.enabled = NO;
    [_buttonBar addSubview:_addButton];

    // Close button
    _closeButton = [NSButton buttonWithTitle:@"Close"
                                      target:self
                                      action:@selector(closeClicked:)];
    _closeButton.bezelStyle = NSBezelStyleRounded;
    _closeButton.keyEquivalent = @"\033"; // Escape
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_buttonBar addSubview:_closeButton];

    [NSLayoutConstraint activateConstraints:@[
        [_rescanButton.leadingAnchor constraintEqualToAnchor:_buttonBar.leadingAnchor constant:8.0],
        [_rescanButton.centerYAnchor constraintEqualToAnchor:_buttonBar.centerYAnchor],

        [_closeButton.trailingAnchor constraintEqualToAnchor:_buttonBar.trailingAnchor constant:-8.0],
        [_closeButton.centerYAnchor constraintEqualToAnchor:_buttonBar.centerYAnchor],

        [_addButton.trailingAnchor constraintEqualToAnchor:_closeButton.leadingAnchor constant:-8.0],
        [_addButton.centerYAnchor constraintEqualToAnchor:_buttonBar.centerYAnchor],
    ]];
}

- (void)layoutSubviews {
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:8.0],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8.0],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8.0],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_buttonBar.topAnchor constant:-8.0],

        [_buttonBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_buttonBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_buttonBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_buttonBar.heightAnchor constraintEqualToConstant:kButtonBarHeight],
    ]];
}

#pragma mark - Public Methods

- (void)reloadResults {
    _results = [_discoveryController discoveredControllersAsDictionaries];
    [_tableView reloadData];
    [self updateAddButtonState];
    [self updateStatusLabel];
}

- (void)setDiscoveryState:(XLDiscoveryState)state {
    _currentState = state;
    [self updateUIForState:state];
}

- (void)updateUIForState:(XLDiscoveryState)state {
    switch (state) {
        case XLDiscoveryStateIdle:
            _statusLabel.stringValue = @"Ready to scan";
            [_spinner stopAnimation:nil];
            _spinner.hidden = YES;
            _rescanButton.enabled = YES;
            break;

        case XLDiscoveryStateScanning:
            _statusLabel.stringValue = @"Scanning network...";
            _spinner.hidden = NO;
            [_spinner startAnimation:nil];
            _rescanButton.enabled = NO;
            break;

        case XLDiscoveryStateComplete:
            [_spinner stopAnimation:nil];
            _spinner.hidden = YES;
            _rescanButton.enabled = YES;
            [self updateStatusLabel];
            break;

        case XLDiscoveryStateFailed:
            _statusLabel.stringValue = @"Discovery failed";
            [_spinner stopAnimation:nil];
            _spinner.hidden = YES;
            _rescanButton.enabled = YES;
            break;
    }
}

- (void)updateStatusLabel {
    NSUInteger count = _results.count;
    NSUInteger newCount = 0;
    for (NSDictionary *result in _results) {
        if (![result[@"alreadyConfigured"] boolValue]) {
            newCount++;
        }
    }

    if (count == 0) {
        _statusLabel.stringValue = @"No controllers found";
    } else if (newCount == 0) {
        _statusLabel.stringValue = [NSString stringWithFormat:@"%lu controller(s) found (all already configured)",
                                    (unsigned long)count];
    } else {
        _statusLabel.stringValue = [NSString stringWithFormat:@"%lu controller(s) found (%lu new)",
                                    (unsigned long)count, (unsigned long)newCount];
    }
}

- (NSArray<NSNumber *> *)selectedControllerIndices {
    NSMutableArray<NSNumber *> *indices = [NSMutableArray array];
    NSIndexSet *selected = _tableView.selectedRowIndexes;
    [selected enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [indices addObject:@(idx)];
    }];
    return indices;
}

#pragma mark - Button Actions

- (void)rescanClicked:(id)sender {
    if ([_delegate respondsToSelector:@selector(discoveryResultsDidRequestRescan:)]) {
        [_delegate discoveryResultsDidRequestRescan:self];
    }
}

- (void)addClicked:(id)sender {
    NSArray<NSNumber *> *indices = [self selectedControllerIndices];
    if (indices.count > 0 && [_delegate respondsToSelector:@selector(discoveryResults:didRequestAddControllers:)]) {
        [_delegate discoveryResults:self didRequestAddControllers:indices];
    }
}

- (void)closeClicked:(id)sender {
    if ([_delegate respondsToSelector:@selector(discoveryResultsDidDismiss:)]) {
        [_delegate discoveryResultsDidDismiss:self];
    }
}

- (void)updateAddButtonState {
    NSIndexSet *selected = _tableView.selectedRowIndexes;
    __block BOOL hasNewControllers = NO;

    [selected enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if (idx < self->_results.count) {
            NSDictionary *result = self->_results[idx];
            if (![result[@"alreadyConfigured"] boolValue]) {
                hasNewControllers = YES;
                *stop = YES;
            }
        }
    }];

    _addButton.enabled = hasNewControllers;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _results.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_results.count) return nil;

    NSString *identifier = tableColumn.identifier;
    NSDictionary *result = _results[row];

    if ([identifier isEqualToString:kColumnConfigured]) {
        return [self configuredCellForRow:row result:result reusingView:[tableView makeViewWithIdentifier:@"ConfiguredCell" owner:self]];
    }

    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [self makeTextCellWithIdentifier:identifier];
    }

    NSString *value = @"";
    if ([identifier isEqualToString:kColumnIP]) {
        value = result[@"ip"] ?: @"";
    } else if ([identifier isEqualToString:kColumnHostname]) {
        value = result[@"hostname"] ?: @"";
    } else if ([identifier isEqualToString:kColumnVendor]) {
        NSString *vendor = result[@"vendor"] ?: @"";
        NSString *model = result[@"model"] ?: @"";
        if (model.length > 0 && vendor.length > 0) {
            value = [NSString stringWithFormat:@"%@ %@", vendor, model];
        } else {
            value = vendor.length > 0 ? vendor : model;
        }
    } else if ([identifier isEqualToString:kColumnMode]) {
        value = result[@"mode"] ?: @"";
    } else if ([identifier isEqualToString:kColumnVersion]) {
        value = result[@"version"] ?: @"";
    }

    cell.textField.stringValue = value;

    // Dim already-configured controllers
    BOOL configured = [result[@"alreadyConfigured"] boolValue];
    cell.textField.textColor = configured ? [NSColor tertiaryLabelColor] : [NSColor labelColor];

    return cell;
}

- (NSTableCellView *)makeTextCellWithIdentifier:(NSString *)identifier {
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
    cell.identifier = identifier;

    NSTextField *textField = [NSTextField labelWithString:@""];
    textField.lineBreakMode = NSLineBreakByTruncatingTail;
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:textField];
    cell.textField = textField;

    [NSLayoutConstraint activateConstraints:@[
        [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4.0],
        [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4.0],
        [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];

    return cell;
}

- (NSView *)configuredCellForRow:(NSInteger)row result:(NSDictionary *)result reusingView:(NSView *)existingView {
    NSTableCellView *cell = (NSTableCellView *)existingView;
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"ConfiguredCell";

        NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:imageView];
        cell.imageView = imageView;

        [NSLayoutConstraint activateConstraints:@[
            [imageView.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor],
            [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [imageView.widthAnchor constraintEqualToConstant:16.0],
            [imageView.heightAnchor constraintEqualToConstant:16.0],
        ]];
    }

    BOOL configured = [result[@"alreadyConfigured"] boolValue];
    if (configured) {
        cell.imageView.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill"
                                         accessibilityDescription:@"Already Configured"];
        cell.imageView.contentTintColor = [NSColor systemGreenColor];
        cell.toolTip = [NSString stringWithFormat:@"Already configured as: %@", result[@"existingName"] ?: @"Unknown"];
    } else {
        cell.imageView.image = nil;
        cell.toolTip = @"New controller - can be added";
    }

    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateAddButtonState];
}

@end
