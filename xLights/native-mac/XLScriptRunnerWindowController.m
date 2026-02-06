/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLScriptRunnerWindowController.h"
#import "XLEngineBridge.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString * const kRecentScriptsKey = @"XLRecentScripts";
static NSString * const kScriptRunnerWindowFrameKey = @"XLScriptRunnerWindowFrame";
static const NSInteger kMaxRecentScripts = 10;

@interface XLScriptRunnerWindowController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTextView *consoleTextView;
@property (nonatomic, strong) NSTextView *sourceTextView;
@property (nonatomic, strong) NSTextField *filePathField;
@property (nonatomic, strong) NSButton *runButton;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) NSButton *clearButton;
@property (nonatomic, strong) NSTableView *recentScriptsTable;
@property (nonatomic, strong) NSMutableArray<NSString *> *recentScripts;
@property (nonatomic, copy) NSString *currentScriptPath;
@property (nonatomic, assign) BOOL isRunning;

@end

@implementation XLScriptRunnerWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskMiniaturizable |
                                                            NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Script Runner";
    window.minSize = NSMakeSize(600, 400);
    window.releasedWhenClosed = NO;
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];

    self = [super initWithWindow:window];
    if (self) {
        _recentScripts = [[[NSUserDefaults standardUserDefaults] arrayForKey:kRecentScriptsKey] mutableCopy]
                          ?: [NSMutableArray new];
        _isRunning = NO;
        [self setupUI];

        NSString *frameString = [[NSUserDefaults standardUserDefaults] stringForKey:kScriptRunnerWindowFrameKey];
        if (frameString) {
            NSRect frame = NSRectFromString(frameString);
            if (frame.size.width > 0 && frame.size.height > 0) {
                [window setFrame:frame display:NO];
            }
        }
    }
    return self;
}

#pragma mark - UI Setup

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    // Main split view: left (recent scripts) | right (source + console)
    NSSplitView *mainSplit = [[NSSplitView alloc] initWithFrame:contentView.bounds];
    mainSplit.translatesAutoresizingMaskIntoConstraints = NO;
    mainSplit.dividerStyle = NSSplitViewDividerStyleThin;
    mainSplit.vertical = YES;
    [contentView addSubview:mainSplit];

    [NSLayoutConstraint activateConstraints:@[
        [mainSplit.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [mainSplit.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [mainSplit.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [mainSplit.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];

    // Left panel: Recent scripts list
    NSView *leftPanel = [self buildRecentScriptsPanel];
    [mainSplit addSubview:leftPanel];

    // Right panel: source + console
    NSView *rightPanel = [self buildMainPanel];
    [mainSplit addSubview:rightPanel];

    // Set initial split position
    [mainSplit setPosition:180 ofDividerAtIndex:0];
    [mainSplit setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:0];
}

- (NSView *)buildRecentScriptsPanel {
    NSView *panel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 180, 600)];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    [panel.widthAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;

    // Header
    NSTextField *header = [NSTextField labelWithString:@"Recent Scripts"];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    header.textColor = [NSColor secondaryLabelColor];
    [panel addSubview:header];

    // Table view
    _recentScriptsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _recentScriptsTable.dataSource = self;
    _recentScriptsTable.delegate = self;
    _recentScriptsTable.headerView = nil;
    _recentScriptsTable.rowHeight = 24;
    _recentScriptsTable.usesAlternatingRowBackgroundColors = YES;
    _recentScriptsTable.target = self;
    _recentScriptsTable.doubleAction = @selector(recentScriptDoubleClicked:);

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Script";
    nameColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_recentScriptsTable addTableColumn:nameColumn];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.documentView = _recentScriptsTable;
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    [panel addSubview:scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:panel.topAnchor constant:8],
        [header.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
        [header.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],
        [scrollView.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:4],
        [scrollView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor]
    ]];

    return panel;
}

- (NSView *)buildMainPanel {
    NSView *panel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 620, 600)];
    panel.translatesAutoresizingMaskIntoConstraints = NO;

    // Top toolbar: file path + browse + run/stop/clear
    NSView *toolbar = [self buildToolbar];
    [panel addSubview:toolbar];

    // Split: source view (top) | console (bottom)
    NSSplitView *vertSplit = [[NSSplitView alloc] initWithFrame:NSZeroRect];
    vertSplit.translatesAutoresizingMaskIntoConstraints = NO;
    vertSplit.dividerStyle = NSSplitViewDividerStyleThin;
    vertSplit.vertical = NO;
    [panel addSubview:vertSplit];

    // Source text view
    NSScrollView *sourceScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _sourceTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 620, 300)];
    _sourceTextView.editable = NO;
    _sourceTextView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _sourceTextView.backgroundColor = [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
    _sourceTextView.textColor = [NSColor colorWithCalibratedWhite:0.85 alpha:1.0];
    _sourceTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _sourceTextView.textContainerInset = NSMakeSize(8, 8);
    _sourceTextView.automaticQuoteSubstitutionEnabled = NO;
    _sourceTextView.automaticDashSubstitutionEnabled = NO;
    sourceScroll.documentView = _sourceTextView;
    sourceScroll.hasVerticalScroller = YES;
    sourceScroll.autohidesScrollers = YES;

    // Console text view
    NSScrollView *consoleScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _consoleTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 620, 200)];
    _consoleTextView.editable = NO;
    _consoleTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _consoleTextView.backgroundColor = [NSColor colorWithCalibratedWhite:0.08 alpha:1.0];
    _consoleTextView.textColor = [NSColor colorWithCalibratedRed:0.4 green:1.0 blue:0.4 alpha:1.0];
    _consoleTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _consoleTextView.textContainerInset = NSMakeSize(8, 8);
    consoleScroll.documentView = _consoleTextView;
    consoleScroll.hasVerticalScroller = YES;
    consoleScroll.autohidesScrollers = YES;

    [vertSplit addSubview:sourceScroll];
    [vertSplit addSubview:consoleScroll];

    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:panel.topAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:44],
        [vertSplit.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [vertSplit.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [vertSplit.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [vertSplit.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor]
    ]];

    // Set initial split position after layout
    dispatch_async(dispatch_get_main_queue(), ^{
        [vertSplit setPosition:vertSplit.frame.size.height * 0.6 ofDividerAtIndex:0];
    });

    return panel;
}

- (NSView *)buildToolbar {
    NSView *toolbar = [[NSView alloc] initWithFrame:NSZeroRect];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;

    _filePathField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _filePathField.translatesAutoresizingMaskIntoConstraints = NO;
    _filePathField.editable = NO;
    _filePathField.placeholderString = @"Select a script file...";
    _filePathField.font = [NSFont systemFontOfSize:12];
    [toolbar addSubview:_filePathField];

    NSButton *browseBtn = [NSButton buttonWithTitle:@"Open..." target:self action:@selector(browseScript:)];
    browseBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:browseBtn];

    _runButton = [NSButton buttonWithTitle:@"Run" target:self action:@selector(runScript:)];
    _runButton.translatesAutoresizingMaskIntoConstraints = NO;
    _runButton.bezelColor = [NSColor systemGreenColor];
    _runButton.enabled = NO;
    [toolbar addSubview:_runButton];

    _stopButton = [NSButton buttonWithTitle:@"Stop" target:self action:@selector(stopScript:)];
    _stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    _stopButton.bezelColor = [NSColor systemRedColor];
    _stopButton.enabled = NO;
    [toolbar addSubview:_stopButton];

    _clearButton = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clearConsole:)];
    _clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:_clearButton];

    [NSLayoutConstraint activateConstraints:@[
        [_filePathField.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:8],
        [_filePathField.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [browseBtn.leadingAnchor constraintEqualToAnchor:_filePathField.trailingAnchor constant:8],
        [browseBtn.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [_runButton.leadingAnchor constraintEqualToAnchor:browseBtn.trailingAnchor constant:16],
        [_runButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [_stopButton.leadingAnchor constraintEqualToAnchor:_runButton.trailingAnchor constant:8],
        [_stopButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [_clearButton.leadingAnchor constraintEqualToAnchor:_stopButton.trailingAnchor constant:8],
        [_clearButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [_clearButton.trailingAnchor constraintLessThanOrEqualToAnchor:toolbar.trailingAnchor constant:-8],
        [_filePathField.trailingAnchor constraintLessThanOrEqualToAnchor:browseBtn.leadingAnchor constant:-8],
    ]];

    // Let file path field expand
    [_filePathField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_filePathField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    return toolbar;
}

#pragma mark - Actions

- (void)browseScript:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Select Script";
    panel.message = @"Choose a Lua (.lua) or Python (.py) script to run";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;

    if (@available(macOS 11.0, *)) {
        panel.allowedContentTypes = @[
            [UTType typeWithFilenameExtension:@"lua"],
            [UTType typeWithFilenameExtension:@"py"]
        ];
    } else {
        panel.allowedFileTypes = @[@"lua", @"py"];
    }

    // Start in show folder if available
    NSString *showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    if (showFolder) {
        panel.directoryURL = [NSURL fileURLWithPath:showFolder];
    }

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            [self loadScriptAtPath:panel.URL.path];
        }
    }];
}

- (void)runScript:(id)sender {
    if (!_currentScriptPath) return;

    _isRunning = YES;
    [self updateButtonStates];

    NSString *extension = _currentScriptPath.pathExtension.lowercaseString;
    NSString *scriptType = [extension isEqualToString:@"lua"] ? @"Lua" : @"Python";

    [self appendToConsole:[NSString stringWithFormat:@"--- Running %@ script: %@ ---\n",
                           scriptType, _currentScriptPath.lastPathComponent]
                withColor:[NSColor systemYellowColor]];
    [self appendToConsole:@"Script execution is not yet available in the native build.\n"
                withColor:[NSColor systemOrangeColor]];
    [self appendToConsole:@"TODO: Integrate with Lua 5.3 runtime and Python via pybind11.\n"
                withColor:[NSColor secondaryLabelColor]];

    // Simulate completion after brief delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self appendToConsole:@"--- Script finished ---\n\n"
                    withColor:[NSColor systemYellowColor]];
        self->_isRunning = NO;
        [self updateButtonStates];
    });
}

- (void)stopScript:(id)sender {
    if (!_isRunning) return;

    [self appendToConsole:@"--- Script stopped by user ---\n\n"
                withColor:[NSColor systemRedColor]];
    _isRunning = NO;
    [self updateButtonStates];
}

- (void)clearConsole:(id)sender {
    [_consoleTextView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
}

#pragma mark - Script Loading

- (void)loadScriptAtPath:(NSString *)path {
    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];

    if (error) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Failed to Load Script";
        alert.informativeText = [NSString stringWithFormat:@"Could not read file:\n%@", error.localizedDescription];
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    _currentScriptPath = path;
    _filePathField.stringValue = path;

    // Display file contents in source view
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.85 alpha:1.0]
    };
    NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:contents attributes:attrs];
    [_sourceTextView.textStorage setAttributedString:attrStr];

    [self addRecentScript:path];
    [self updateButtonStates];

    NSLog(@"XLScriptRunner: Loaded script: %@", path);
}

- (void)addRecentScript:(NSString *)path {
    [_recentScripts removeObject:path];
    [_recentScripts insertObject:path atIndex:0];

    if (_recentScripts.count > kMaxRecentScripts) {
        [_recentScripts removeObjectsInRange:NSMakeRange(kMaxRecentScripts,
                                                          _recentScripts.count - kMaxRecentScripts)];
    }

    [[NSUserDefaults standardUserDefaults] setObject:[_recentScripts copy] forKey:kRecentScriptsKey];
    [_recentScriptsTable reloadData];
}

#pragma mark - Console Output

- (void)appendToConsole:(NSString *)text withColor:(NSColor *)color {
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: color ?: [NSColor colorWithCalibratedRed:0.4 green:1.0 blue:0.4 alpha:1.0]
    };
    NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    [_consoleTextView.textStorage appendAttributedString:attrStr];

    // Scroll to bottom
    [_consoleTextView scrollRangeToVisible:NSMakeRange(_consoleTextView.string.length, 0)];
}

#pragma mark - State Management

- (void)updateButtonStates {
    _runButton.enabled = (_currentScriptPath != nil && !_isRunning);
    _stopButton.enabled = _isRunning;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _recentScripts.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTextField *cell = [tableView makeViewWithIdentifier:@"ScriptCell" owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = @"ScriptCell";
        cell.lineBreakMode = NSLineBreakByTruncatingHead;
        cell.font = [NSFont systemFontOfSize:11];
    }

    NSString *path = _recentScripts[row];
    cell.stringValue = path.lastPathComponent;
    cell.toolTip = path;

    // Dim entries for files that no longer exist
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        cell.textColor = [NSColor tertiaryLabelColor];
    } else {
        cell.textColor = [NSColor labelColor];
    }

    return cell;
}

#pragma mark - NSTableViewDelegate

- (void)recentScriptDoubleClicked:(id)sender {
    NSInteger row = _recentScriptsTable.clickedRow;
    if (row >= 0 && row < (NSInteger)_recentScripts.count) {
        NSString *path = _recentScripts[row];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [self loadScriptAtPath:path];
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Script Not Found";
            alert.informativeText = [NSString stringWithFormat:@"The script file no longer exists:\n%@", path];
            alert.alertStyle = NSAlertStyleWarning;
            [alert addButtonWithTitle:@"OK"];
            [alert addButtonWithTitle:@"Remove from List"];
            if ([alert runModal] != NSAlertFirstButtonReturn) {
                [_recentScripts removeObjectAtIndex:row];
                [[NSUserDefaults standardUserDefaults] setObject:[_recentScripts copy] forKey:kRecentScriptsKey];
                [_recentScriptsTable reloadData];
            }
        }
    }
}

#pragma mark - Window Lifecycle

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self.window center];
}

- (void)windowWillClose:(NSNotification *)notification {
    NSString *frameString = NSStringFromRect(self.window.frame);
    [[NSUserDefaults standardUserDefaults] setObject:frameString forKey:kScriptRunnerWindowFrameKey];
}

@end
