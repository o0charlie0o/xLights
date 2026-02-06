/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLToolsDialogs.h"
#import "../XLEngineBridge.h"

static const CGFloat kLabelWidth = 140.0;

// ============================================================================
#pragma mark - XLCleanupFileLocationsDialog
// ============================================================================

@interface XLCleanupFileLocationsDialog ()

@property (nonatomic, strong) NSTableView *resultsTable;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *scanButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *fileResults;
@property (nonatomic, copy) void (^completionHandler)(void);

@end

@implementation XLCleanupFileLocationsDialog

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 650, 450)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Cleanup File Locations";
    window.minSize = NSMakeSize(500, 350);
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        _fileResults = [NSMutableArray new];
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
    mainStack.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    [contentView addSubview:mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [mainStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [mainStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [mainStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];

    // Description
    NSTextField *desc = [NSTextField wrappingLabelWithString:
        @"Scans sequence files in the show folder for referenced media files (images, audio, video) "
        @"and checks whether those files exist at their expected locations."];
    desc.font = [NSFont systemFontOfSize:12];
    desc.textColor = [NSColor secondaryLabelColor];
    [mainStack addArrangedSubview:desc];

    // Table view for results
    _resultsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _resultsTable.dataSource = self;
    _resultsTable.delegate = self;
    _resultsTable.usesAlternatingRowBackgroundColors = YES;
    _resultsTable.rowHeight = 22;

    NSTableColumn *fileCol = [[NSTableColumn alloc] initWithIdentifier:@"file"];
    fileCol.title = @"Referenced File";
    fileCol.width = 300;
    fileCol.resizingMask = NSTableColumnAutoresizingMask;
    [_resultsTable addTableColumn:fileCol];

    NSTableColumn *statusCol = [[NSTableColumn alloc] initWithIdentifier:@"status"];
    statusCol.title = @"Status";
    statusCol.width = 100;
    [_resultsTable addTableColumn:statusCol];

    NSTableColumn *seqCol = [[NSTableColumn alloc] initWithIdentifier:@"sequence"];
    seqCol.title = @"Referenced By";
    seqCol.width = 200;
    seqCol.resizingMask = NSTableColumnAutoresizingMask;
    [_resultsTable addTableColumn:seqCol];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.documentView = _resultsTable;
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    [mainStack addArrangedSubview:scrollView];

    // Progress and status
    NSStackView *progressRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    progressRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    progressRow.spacing = 8;

    _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
    _progressIndicator.style = NSProgressIndicatorStyleSpinning;
    _progressIndicator.controlSize = NSControlSizeSmall;
    _progressIndicator.displayedWhenStopped = NO;
    [progressRow addArrangedSubview:_progressIndicator];

    _statusLabel = [NSTextField labelWithString:@"Click Scan to check file references."];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    [progressRow addArrangedSubview:_statusLabel];
    [mainStack addArrangedSubview:progressRow];

    // Buttons
    NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 8;

    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [buttonRow addArrangedSubview:spacer];

    _scanButton = [NSButton buttonWithTitle:@"Scan" target:self action:@selector(scanFiles:)];
    _scanButton.bezelColor = [NSColor controlAccentColor];
    [buttonRow addArrangedSubview:_scanButton];

    _closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeDialog:)];
    [buttonRow addArrangedSubview:_closeButton];

    [mainStack addArrangedSubview:buttonRow];

    // Let the scroll view expand
    [scrollView setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
}

- (void)showWithCompletion:(void (^)(void))completion {
    _completionHandler = completion;
    [self.window center];
    [self showWindow:nil];
}

- (void)scanFiles:(id)sender {
    NSString *showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    if (!showFolder) {
        _statusLabel.stringValue = @"No show folder selected.";
        return;
    }

    [_fileResults removeAllObjects];
    [_resultsTable reloadData];
    [_progressIndicator startAnimation:nil];
    _statusLabel.stringValue = @"Scanning...";
    _scanButton.enabled = NO;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *contents = [fm contentsOfDirectoryAtPath:showFolder error:nil];
        NSMutableArray<NSDictionary *> *results = [NSMutableArray new];

        for (NSString *file in contents) {
            NSString *ext = file.pathExtension.lowercaseString;
            if (![ext isEqualToString:@"xml"] && ![ext isEqualToString:@"xsq"] && ![ext isEqualToString:@"xlights"]) {
                continue;
            }

            NSString *fullPath = [showFolder stringByAppendingPathComponent:file];
            NSData *data = [NSData dataWithContentsOfFile:fullPath options:NSDataReadingMappedIfSafe error:nil];
            if (!data) continue;

            NSString *xmlString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!xmlString) continue;

            // Look for common media file reference patterns in the XML
            NSArray *patterns = @[@"mediaFile=\"", @"Image=\"", @"GlediatorFile=\"",
                                  @"VideoFile=\"", @"PictureFile=\"", @"AudioFile=\"",
                                  @"ShaderFile=\"", @"FaceFile=\""];

            for (NSString *pattern in patterns) {
                NSRange searchRange = NSMakeRange(0, xmlString.length);
                while (searchRange.location < xmlString.length) {
                    NSRange found = [xmlString rangeOfString:pattern options:0 range:searchRange];
                    if (found.location == NSNotFound) break;

                    NSUInteger valueStart = found.location + found.length;
                    NSRange endQuote = [xmlString rangeOfString:@"\"" options:0
                                                         range:NSMakeRange(valueStart, xmlString.length - valueStart)];
                    if (endQuote.location == NSNotFound) break;

                    NSString *refPath = [xmlString substringWithRange:NSMakeRange(valueStart, endQuote.location - valueStart)];

                    if (refPath.length > 0 && ![refPath isEqualToString:@""]) {
                        // Resolve relative paths against show folder
                        NSString *resolvedPath = refPath;
                        if (![refPath isAbsolutePath]) {
                            resolvedPath = [showFolder stringByAppendingPathComponent:refPath];
                        }

                        BOOL exists = [fm fileExistsAtPath:resolvedPath];
                        [results addObject:@{
                            @"file": refPath,
                            @"status": exists ? @"Found" : @"Missing",
                            @"sequence": file,
                            @"exists": @(exists)
                        }];
                    }

                    searchRange.location = endQuote.location + 1;
                    searchRange.length = xmlString.length - searchRange.location;
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_progressIndicator stopAnimation:nil];
            self->_scanButton.enabled = YES;
            [self->_fileResults addObjectsFromArray:results];
            [self->_resultsTable reloadData];

            NSInteger missingCount = 0;
            for (NSDictionary *r in results) {
                if (![r[@"exists"] boolValue]) missingCount++;
            }

            if (results.count == 0) {
                self->_statusLabel.stringValue = @"No media file references found in sequences.";
            } else {
                self->_statusLabel.stringValue = [NSString stringWithFormat:
                    @"Found %ld references (%ld missing).",
                    (long)results.count, (long)missingCount];
            }
        });
    });
}

- (void)closeDialog:(id)sender {
    [self.window close];
    if (_completionHandler) _completionHandler();
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _fileResults.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSDictionary *result = _fileResults[row];
    NSString *identifier = tableColumn.identifier;

    NSTextField *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = identifier;
        cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
        cell.font = [NSFont systemFontOfSize:11];
    }

    if ([identifier isEqualToString:@"file"]) {
        cell.stringValue = result[@"file"] ?: @"";
        cell.toolTip = result[@"file"];
    } else if ([identifier isEqualToString:@"status"]) {
        BOOL exists = [result[@"exists"] boolValue];
        cell.stringValue = exists ? @"Found" : @"Missing";
        cell.textColor = exists ? [NSColor systemGreenColor] : [NSColor systemRedColor];
    } else if ([identifier isEqualToString:@"sequence"]) {
        cell.stringValue = result[@"sequence"] ?: @"";
    }

    return cell;
}

@end

// ============================================================================
#pragma mark - XLPackageSequenceDialog
// ============================================================================

@interface XLPackageSequenceDialog ()

@property (nonatomic, strong) NSTextField *sequencePathField;
@property (nonatomic, strong) NSTextField *outputPathField;
@property (nonatomic, strong) NSTextView *logTextView;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSButton *packageButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, copy) void (^completionHandler)(void);

@end

@implementation XLPackageSequenceDialog

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 450)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Package Sequence";
    window.minSize = NSMakeSize(500, 350);
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
    mainStack.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    [contentView addSubview:mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [mainStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [mainStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [mainStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];

    // Description
    NSTextField *desc = [NSTextField wrappingLabelWithString:
        @"Creates a zip archive containing the current sequence file and all referenced media, "
        @"images, and resources. This is useful for sharing sequences or creating backups."];
    desc.font = [NSFont systemFontOfSize:12];
    desc.textColor = [NSColor secondaryLabelColor];
    [mainStack addArrangedSubview:desc];

    // Sequence file row
    NSStackView *seqRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    seqRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    seqRow.spacing = 8;

    NSTextField *seqLabel = [NSTextField labelWithString:@"Sequence:"];
    seqLabel.alignment = NSTextAlignmentRight;
    [seqLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _sequencePathField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _sequencePathField.editable = NO;
    _sequencePathField.placeholderString = @"Select a sequence file...";
    [_sequencePathField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                   forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *seqBrowse = [NSButton buttonWithTitle:@"Browse..." target:self action:@selector(browseSequence:)];

    [seqRow addArrangedSubview:seqLabel];
    [seqRow addArrangedSubview:_sequencePathField];
    [seqRow addArrangedSubview:seqBrowse];
    [mainStack addArrangedSubview:seqRow];

    // Output path row
    NSStackView *outRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    outRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    outRow.spacing = 8;

    NSTextField *outLabel = [NSTextField labelWithString:@"Save To:"];
    outLabel.alignment = NSTextAlignmentRight;
    [outLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _outputPathField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _outputPathField.editable = NO;
    _outputPathField.placeholderString = @"Select output location...";
    [_outputPathField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *outBrowse = [NSButton buttonWithTitle:@"Browse..." target:self action:@selector(browseOutput:)];

    [outRow addArrangedSubview:outLabel];
    [outRow addArrangedSubview:_outputPathField];
    [outRow addArrangedSubview:outBrowse];
    [mainStack addArrangedSubview:outRow];

    // Log view
    NSScrollView *logScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _logTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 550, 200)];
    _logTextView.editable = NO;
    _logTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _logTextView.backgroundColor = [NSColor colorWithCalibratedWhite:0.1 alpha:1.0];
    _logTextView.textColor = [NSColor labelColor];
    _logTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _logTextView.textContainerInset = NSMakeSize(8, 8);
    logScroll.documentView = _logTextView;
    logScroll.hasVerticalScroller = YES;
    logScroll.autohidesScrollers = YES;
    logScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [logScroll.heightAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;
    [logScroll setContentHuggingPriority:NSLayoutPriorityDefaultLow
                          forOrientation:NSLayoutConstraintOrientationVertical];
    [mainStack addArrangedSubview:logScroll];

    // Progress + buttons
    NSStackView *bottomRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    bottomRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bottomRow.spacing = 8;

    _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
    _progressIndicator.style = NSProgressIndicatorStyleSpinning;
    _progressIndicator.controlSize = NSControlSizeSmall;
    _progressIndicator.displayedWhenStopped = NO;
    [bottomRow addArrangedSubview:_progressIndicator];

    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [bottomRow addArrangedSubview:spacer];

    _packageButton = [NSButton buttonWithTitle:@"Package" target:self action:@selector(packageSequence:)];
    _packageButton.bezelColor = [NSColor controlAccentColor];
    _packageButton.enabled = NO;
    [bottomRow addArrangedSubview:_packageButton];

    _closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeDialog:)];
    [bottomRow addArrangedSubview:_closeButton];

    [mainStack addArrangedSubview:bottomRow];
}

- (void)showWithCompletion:(void (^)(void))completion {
    _completionHandler = completion;

    // Auto-populate sequence path if one is loaded
    if (_engineBridge && [_engineBridge isSequenceLoaded]) {
        NSDictionary *info = [_engineBridge getSequenceInfo];
        NSString *name = info[@"name"];
        if (name) {
            NSString *showFolder = [_engineBridge getShowFolderPath];
            if (showFolder) {
                _sequencePathField.stringValue = [showFolder stringByAppendingPathComponent:name];
            }
        }
    }

    [self.window center];
    [self showWindow:nil];
}

- (void)browseSequence:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Select Sequence";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowedFileTypes = @[@"xsq", @"xlights", @"xml"];

    NSString *showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    if (showFolder) panel.directoryURL = [NSURL fileURLWithPath:showFolder];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            self->_sequencePathField.stringValue = panel.URL.path;
            [self updatePackageButton];
        }
    }];
}

- (void)browseOutput:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Save Package As";
    panel.allowedFileTypes = @[@"zip"];
    panel.nameFieldStringValue = @"sequence_package.zip";

    NSString *showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    if (showFolder) panel.directoryURL = [NSURL fileURLWithPath:showFolder];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            self->_outputPathField.stringValue = panel.URL.path;
            [self updatePackageButton];
        }
    }];
}

- (void)updatePackageButton {
    _packageButton.enabled = (_sequencePathField.stringValue.length > 0 &&
                              _outputPathField.stringValue.length > 0);
}

- (void)packageSequence:(id)sender {
    NSString *seqPath = _sequencePathField.stringValue;
    NSString *outputPath = _outputPathField.stringValue;

    if (seqPath.length == 0 || outputPath.length == 0) return;

    _packageButton.enabled = NO;
    [_progressIndicator startAnimation:nil];
    [self appendLog:@"Starting package creation...\n"];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
        NSMutableArray<NSString *> *filesToPackage = [NSMutableArray new];

        // Always include the sequence file itself
        if ([fm fileExistsAtPath:seqPath]) {
            [filesToPackage addObject:seqPath];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"  Adding: %@\n", seqPath.lastPathComponent]];
            });
        }

        // Look for FSEQ companion file
        NSString *fseqPath = [[seqPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"fseq"];
        if ([fm fileExistsAtPath:fseqPath]) {
            [filesToPackage addObject:fseqPath];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"  Adding: %@\n", fseqPath.lastPathComponent]];
            });
        }

        // Scan sequence XML for media references
        NSData *data = [NSData dataWithContentsOfFile:seqPath];
        if (data) {
            NSString *xmlString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (xmlString) {
                NSArray *patterns = @[@"mediaFile=\"", @"Image=\"", @"VideoFile=\"",
                                      @"PictureFile=\"", @"AudioFile=\""];
                for (NSString *pattern in patterns) {
                    NSRange searchRange = NSMakeRange(0, xmlString.length);
                    while (searchRange.location < xmlString.length) {
                        NSRange found = [xmlString rangeOfString:pattern options:0 range:searchRange];
                        if (found.location == NSNotFound) break;

                        NSUInteger valueStart = found.location + found.length;
                        NSRange endQuote = [xmlString rangeOfString:@"\"" options:0
                                                             range:NSMakeRange(valueStart, xmlString.length - valueStart)];
                        if (endQuote.location == NSNotFound) break;

                        NSString *refPath = [xmlString substringWithRange:
                                             NSMakeRange(valueStart, endQuote.location - valueStart)];

                        if (refPath.length > 0) {
                            NSString *resolvedPath = refPath;
                            if (![refPath isAbsolutePath] && showFolder) {
                                resolvedPath = [showFolder stringByAppendingPathComponent:refPath];
                            }
                            if ([fm fileExistsAtPath:resolvedPath] && ![filesToPackage containsObject:resolvedPath]) {
                                [filesToPackage addObject:resolvedPath];
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [self appendLog:[NSString stringWithFormat:@"  Adding: %@\n",
                                                     resolvedPath.lastPathComponent]];
                                });
                            }
                        }

                        searchRange.location = endQuote.location + 1;
                        searchRange.length = xmlString.length - searchRange.location;
                    }
                }
            }
        }

        // Create zip using /usr/bin/ditto (macOS built-in, handles zip well)
        NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [[NSUUID UUID] UUIDString]];
        [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

        // Copy all files to temp directory
        for (NSString *filePath in filesToPackage) {
            NSString *dest = [tempDir stringByAppendingPathComponent:filePath.lastPathComponent];
            [fm copyItemAtPath:filePath toPath:dest error:nil];
        }

        // Create zip archive
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
        task.arguments = @[@"-c", @"-k", @"--sequesterRsrc", tempDir, outputPath];
        task.standardOutput = [NSPipe pipe];
        task.standardError = [NSPipe pipe];

        NSError *taskError = nil;
        [task launchAndReturnError:&taskError];

        if (taskError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"\nError creating archive: %@\n",
                                 taskError.localizedDescription]];
                [self->_progressIndicator stopAnimation:nil];
                self->_packageButton.enabled = YES;
            });
        } else {
            [task waitUntilExit];

            // Cleanup temp directory
            [fm removeItemAtPath:tempDir error:nil];

            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_progressIndicator stopAnimation:nil];
                self->_packageButton.enabled = YES;

                if (task.terminationStatus == 0) {
                    NSDictionary *attrs = [fm attributesOfItemAtPath:outputPath error:nil];
                    unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
                    NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:size
                                                                      countStyle:NSByteCountFormatterCountStyleFile];
                    [self appendLog:[NSString stringWithFormat:
                        @"\nPackage created successfully!\n  Files: %ld\n  Size: %@\n  Path: %@\n",
                        (long)filesToPackage.count, sizeStr, outputPath]];
                } else {
                    [self appendLog:@"\nFailed to create zip archive.\n"];
                }
            });
        }
    });
}

- (void)appendLog:(NSString *)text {
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };
    NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    [_logTextView.textStorage appendAttributedString:attrStr];
    [_logTextView scrollRangeToVisible:NSMakeRange(_logTextView.string.length, 0)];
}

- (void)closeDialog:(id)sender {
    [self.window close];
    if (_completionHandler) _completionHandler();
}

@end

// ============================================================================
#pragma mark - XLDownloadSequencesDialog
// ============================================================================

@interface XLDownloadSequencesDialog ()

@property (nonatomic, strong) NSTableView *downloadsTable;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *downloadButton;
@property (nonatomic, strong) NSButton *refreshButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *availableDownloads;
@property (nonatomic, strong) NSURLSession *urlSession;
@property (nonatomic, copy) void (^completionHandler)(void);

@end

@implementation XLDownloadSequencesDialog

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 650, 500)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Download Sequences & Lyrics";
    window.minSize = NSMakeSize(500, 350);
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        _availableDownloads = [NSMutableArray new];
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        _urlSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
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
    mainStack.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    [contentView addSubview:mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [mainStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [mainStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [mainStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];

    // Description
    NSTextField *desc = [NSTextField wrappingLabelWithString:
        @"Browse and download shared sequences, lyrics, and face definitions from the "
        @"xLights community repository. Downloaded files are saved to your show folder."];
    desc.font = [NSFont systemFontOfSize:12];
    desc.textColor = [NSColor secondaryLabelColor];
    [mainStack addArrangedSubview:desc];

    // Table
    _downloadsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _downloadsTable.dataSource = self;
    _downloadsTable.delegate = self;
    _downloadsTable.usesAlternatingRowBackgroundColors = YES;
    _downloadsTable.rowHeight = 24;
    _downloadsTable.allowsMultipleSelection = YES;

    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameCol.title = @"Name";
    nameCol.width = 250;
    nameCol.resizingMask = NSTableColumnAutoresizingMask;
    [_downloadsTable addTableColumn:nameCol];

    NSTableColumn *typeCol = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeCol.title = @"Type";
    typeCol.width = 100;
    [_downloadsTable addTableColumn:typeCol];

    NSTableColumn *sizeCol = [[NSTableColumn alloc] initWithIdentifier:@"size"];
    sizeCol.title = @"Size";
    sizeCol.width = 80;
    [_downloadsTable addTableColumn:sizeCol];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.documentView = _downloadsTable;
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    [scrollView setContentHuggingPriority:NSLayoutPriorityDefaultLow
                           forOrientation:NSLayoutConstraintOrientationVertical];
    [mainStack addArrangedSubview:scrollView];

    // Progress and status
    NSStackView *statusRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    statusRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    statusRow.spacing = 8;

    _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
    _progressIndicator.style = NSProgressIndicatorStyleBar;
    _progressIndicator.controlSize = NSControlSizeSmall;
    _progressIndicator.indeterminate = YES;
    _progressIndicator.hidden = YES;
    [_progressIndicator.widthAnchor constraintEqualToConstant:200].active = YES;
    [statusRow addArrangedSubview:_progressIndicator];

    _statusLabel = [NSTextField labelWithString:@"Click Refresh to fetch available downloads."];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    [statusRow addArrangedSubview:_statusLabel];
    [mainStack addArrangedSubview:statusRow];

    // Buttons
    NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 8;

    _refreshButton = [NSButton buttonWithTitle:@"Refresh List" target:self action:@selector(refreshList:)];
    [buttonRow addArrangedSubview:_refreshButton];

    NSButton *openRepoBtn = [NSButton buttonWithTitle:@"Open Repository..." target:self action:@selector(openRepository:)];
    [buttonRow addArrangedSubview:openRepoBtn];

    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [buttonRow addArrangedSubview:spacer];

    _downloadButton = [NSButton buttonWithTitle:@"Download Selected" target:self action:@selector(downloadSelected:)];
    _downloadButton.bezelColor = [NSColor controlAccentColor];
    _downloadButton.enabled = NO;
    [buttonRow addArrangedSubview:_downloadButton];

    _closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeDialog:)];
    [buttonRow addArrangedSubview:_closeButton];

    [mainStack addArrangedSubview:buttonRow];
}

- (void)showWithCompletion:(void (^)(void))completion {
    _completionHandler = completion;
    [self.window center];
    [self showWindow:nil];
}

- (void)refreshList:(id)sender {
    _refreshButton.enabled = NO;
    _progressIndicator.hidden = NO;
    [_progressIndicator startAnimation:nil];
    _statusLabel.stringValue = @"Fetching download list from xlights.org...";

    NSURL *url = [NSURL URLWithString:@"https://nutcracker123.com/xlights/jukebox/sequences.json"];

    NSURLSessionDataTask *task = [_urlSession dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_refreshButton.enabled = YES;
            self->_progressIndicator.hidden = YES;
            [self->_progressIndicator stopAnimation:nil];

            if (error) {
                self->_statusLabel.stringValue = [NSString stringWithFormat:@"Error: %@",
                                                  error.localizedDescription];
                return;
            }

            // Try to parse the response as JSON
            if (data) {
                NSError *jsonError = nil;
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

                if ([json isKindOfClass:[NSArray class]]) {
                    [self->_availableDownloads removeAllObjects];
                    for (id item in (NSArray *)json) {
                        if ([item isKindOfClass:[NSDictionary class]]) {
                            [self->_availableDownloads addObject:item];
                        }
                    }
                    [self->_downloadsTable reloadData];
                    self->_statusLabel.stringValue = [NSString stringWithFormat:@"%ld items available.",
                                                      (long)self->_availableDownloads.count];
                } else {
                    // Repository may not have a JSON endpoint; show helpful message
                    self->_statusLabel.stringValue =
                        @"Download list not available. Use 'Open Repository...' to browse manually.";
                }
            }
        });
    }];
    [task resume];
}

- (void)openRepository:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:
     [NSURL URLWithString:@"https://github.com/xLightsSequencer/xLights/wiki/Shared-Sequences"]];
}

- (void)downloadSelected:(id)sender {
    NSIndexSet *selectedRows = _downloadsTable.selectedRowIndexes;
    if (selectedRows.count == 0) return;

    _statusLabel.stringValue = @"Downloading is not yet implemented in the native build.";
}

- (void)closeDialog:(id)sender {
    [self.window close];
    if (_completionHandler) _completionHandler();
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _availableDownloads.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSDictionary *item = _availableDownloads[row];
    NSString *identifier = tableColumn.identifier;

    NSTextField *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = identifier;
        cell.font = [NSFont systemFontOfSize:11];
    }

    if ([identifier isEqualToString:@"name"]) {
        cell.stringValue = item[@"name"] ?: item[@"title"] ?: @"Unknown";
    } else if ([identifier isEqualToString:@"type"]) {
        cell.stringValue = item[@"type"] ?: item[@"category"] ?: @"Sequence";
    } else if ([identifier isEqualToString:@"size"]) {
        NSNumber *size = item[@"size"];
        if (size) {
            cell.stringValue = [NSByteCountFormatter stringFromByteCount:size.longLongValue
                                                             countStyle:NSByteCountFormatterCountStyleFile];
        } else {
            cell.stringValue = @"--";
        }
    }

    return cell;
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    _downloadButton.enabled = (_downloadsTable.selectedRowIndexes.count > 0);
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    // Will be implemented when download functionality is added
}

@end

// ============================================================================
#pragma mark - XLPrepareAudioDialog
// ============================================================================

@interface XLPrepareAudioDialog ()

@property (nonatomic, strong) NSTextField *inputPathField;
@property (nonatomic, strong) NSTextField *outputPathField;
@property (nonatomic, strong) NSPopUpButton *formatPopup;
@property (nonatomic, strong) NSPopUpButton *sampleRatePopup;
@property (nonatomic, strong) NSButton *normalizeCheckbox;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *processButton;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, copy) void (^completionHandler)(void);

@end

@implementation XLPrepareAudioDialog

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 550, 350)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Prepare Audio";
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
    mainStack.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    [contentView addSubview:mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [mainStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [mainStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [mainStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];

    // Description
    NSTextField *desc = [NSTextField wrappingLabelWithString:
        @"Convert and prepare audio files for use with xLights. Supports normalization "
        @"and conversion to compatible formats (MP3, WAV, OGG, M4A)."];
    desc.font = [NSFont systemFontOfSize:12];
    desc.textColor = [NSColor secondaryLabelColor];
    [mainStack addArrangedSubview:desc];

    // Input file
    NSStackView *inputRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    inputRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    inputRow.spacing = 8;

    NSTextField *inputLabel = [NSTextField labelWithString:@"Input File:"];
    inputLabel.alignment = NSTextAlignmentRight;
    [inputLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _inputPathField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _inputPathField.editable = NO;
    _inputPathField.placeholderString = @"Select an audio file...";
    [_inputPathField setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *inputBrowse = [NSButton buttonWithTitle:@"Browse..." target:self action:@selector(browseInput:)];

    [inputRow addArrangedSubview:inputLabel];
    [inputRow addArrangedSubview:_inputPathField];
    [inputRow addArrangedSubview:inputBrowse];
    [mainStack addArrangedSubview:inputRow];

    // Output format
    _formatPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_formatPopup addItemWithTitle:@"MP3 (recommended)"];
    [_formatPopup addItemWithTitle:@"WAV (uncompressed)"];
    [_formatPopup addItemWithTitle:@"M4A (AAC)"];
    [_formatPopup addItemWithTitle:@"OGG (Vorbis)"];

    NSStackView *formatRow = [self createFormRowWithLabel:@"Output Format:" control:_formatPopup];
    [mainStack addArrangedSubview:formatRow];

    // Sample rate
    _sampleRatePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_sampleRatePopup addItemWithTitle:@"44100 Hz (CD quality)"];
    [_sampleRatePopup addItemWithTitle:@"48000 Hz"];
    [_sampleRatePopup addItemWithTitle:@"22050 Hz"];

    NSStackView *rateRow = [self createFormRowWithLabel:@"Sample Rate:" control:_sampleRatePopup];
    [mainStack addArrangedSubview:rateRow];

    // Normalize checkbox
    _normalizeCheckbox = [NSButton checkboxWithTitle:@"Normalize audio levels" target:nil action:nil];
    _normalizeCheckbox.state = NSControlStateValueOn;

    NSStackView *normRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    normRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    normRow.spacing = 8;
    NSView *normSpacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [normSpacer.widthAnchor constraintEqualToConstant:kLabelWidth + 8].active = YES;
    [normRow addArrangedSubview:normSpacer];
    [normRow addArrangedSubview:_normalizeCheckbox];
    [mainStack addArrangedSubview:normRow];

    // Progress and status
    NSStackView *statusRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    statusRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    statusRow.spacing = 8;

    _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
    _progressIndicator.style = NSProgressIndicatorStyleSpinning;
    _progressIndicator.controlSize = NSControlSizeSmall;
    _progressIndicator.displayedWhenStopped = NO;
    [statusRow addArrangedSubview:_progressIndicator];

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    [statusRow addArrangedSubview:_statusLabel];
    [mainStack addArrangedSubview:statusRow];

    // Buttons
    NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 8;

    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [buttonRow addArrangedSubview:spacer];

    _processButton = [NSButton buttonWithTitle:@"Process" target:self action:@selector(processAudio:)];
    _processButton.bezelColor = [NSColor controlAccentColor];
    _processButton.enabled = NO;
    [buttonRow addArrangedSubview:_processButton];

    _closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeDialog:)];
    [buttonRow addArrangedSubview:_closeButton];

    [mainStack addArrangedSubview:buttonRow];
}

- (NSStackView *)createFormRowWithLabel:(NSString *)label control:(NSView *)control {
    NSStackView *row = [[NSStackView alloc] initWithFrame:NSZeroRect];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;

    NSTextField *lbl = [NSTextField labelWithString:label];
    lbl.alignment = NSTextAlignmentRight;
    [lbl.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    [row addArrangedSubview:lbl];
    [row addArrangedSubview:control];
    return row;
}

- (void)showWithCompletion:(void (^)(void))completion {
    _completionHandler = completion;
    [self.window center];
    [self showWindow:nil];
}

- (void)browseInput:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Select Audio File";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowedFileTypes = @[@"mp3", @"wav", @"m4a", @"ogg", @"flac", @"aac", @"wma", @"aiff"];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            self->_inputPathField.stringValue = panel.URL.path;
            self->_processButton.enabled = YES;
        }
    }];
}

- (void)processAudio:(id)sender {
    NSString *inputPath = _inputPathField.stringValue;
    if (inputPath.length == 0) return;

    _processButton.enabled = NO;
    [_progressIndicator startAnimation:nil];
    _statusLabel.stringValue = @"Processing audio...";

    // Use AVFoundation to process the audio
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Determine output format and extension
        NSArray *formats = @[@"mp3", @"wav", @"m4a", @"ogg"];
        NSInteger formatIndex = self->_formatPopup.indexOfSelectedItem;
        NSString *ext = (formatIndex >= 0 && formatIndex < (NSInteger)formats.count) ? formats[formatIndex] : @"mp3";

        NSString *outputPath = [[inputPath stringByDeletingPathExtension]
                                stringByAppendingFormat:@"_prepared.%@", ext];

        // Use afconvert (macOS built-in) for audio conversion
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/afconvert"];

        NSMutableArray *args = [NSMutableArray new];
        [args addObject:inputPath];
        [args addObject:outputPath];

        if ([ext isEqualToString:@"wav"]) {
            [args addObjectsFromArray:@[@"-d", @"LEI16", @"-f", @"WAVE"]];
        } else if ([ext isEqualToString:@"m4a"]) {
            [args addObjectsFromArray:@[@"-d", @"aac", @"-f", @"m4af"]];
        } else if ([ext isEqualToString:@"mp3"]) {
            // afconvert may not support mp3 output; fall back to copy
            [args addObjectsFromArray:@[@"-d", @"LEI16", @"-f", @"WAVE"]];
            outputPath = [[inputPath stringByDeletingPathExtension] stringByAppendingString:@"_prepared.wav"];
        }

        // Sample rate
        NSArray *rates = @[@"44100", @"48000", @"22050"];
        NSInteger rateIndex = self->_sampleRatePopup.indexOfSelectedItem;
        NSString *rate = (rateIndex >= 0 && rateIndex < (NSInteger)rates.count) ? rates[rateIndex] : @"44100";
        [args addObjectsFromArray:@[@"-r", rate]];

        task.arguments = args;
        task.standardOutput = [NSPipe pipe];
        task.standardError = [NSPipe pipe];

        NSError *taskError = nil;
        [task launchAndReturnError:&taskError];

        if (taskError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_statusLabel.stringValue = [NSString stringWithFormat:@"Error: %@",
                                                  taskError.localizedDescription];
                [self->_progressIndicator stopAnimation:nil];
                self->_processButton.enabled = YES;
            });
            return;
        }

        [task waitUntilExit];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_progressIndicator stopAnimation:nil];
            self->_processButton.enabled = YES;

            if (task.terminationStatus == 0) {
                self->_statusLabel.stringValue = [NSString stringWithFormat:
                    @"Audio prepared successfully: %@", outputPath.lastPathComponent];

                // Offer to copy to show folder
                NSString *showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
                if (showFolder) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Audio Prepared";
                    alert.informativeText = [NSString stringWithFormat:
                        @"Audio file processed successfully.\n\nOutput: %@\n\nCopy to show folder?",
                        outputPath.lastPathComponent];
                    [alert addButtonWithTitle:@"Copy to Show Folder"];
                    [alert addButtonWithTitle:@"Keep in Original Location"];

                    if ([alert runModal] == NSAlertFirstButtonReturn) {
                        NSString *dest = [showFolder stringByAppendingPathComponent:outputPath.lastPathComponent];
                        NSFileManager *fm = [NSFileManager defaultManager];
                        if ([fm fileExistsAtPath:dest]) {
                            [fm removeItemAtPath:dest error:nil];
                        }
                        [fm copyItemAtPath:outputPath toPath:dest error:nil];
                        self->_statusLabel.stringValue = [NSString stringWithFormat:
                            @"Copied to: %@", dest];
                    }
                }
            } else {
                NSData *errData = [(NSPipe *)task.standardError fileHandleForReading].availableData;
                NSString *errStr = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
                self->_statusLabel.stringValue = [NSString stringWithFormat:
                    @"Audio processing failed: %@", errStr ?: @"Unknown error"];
            }
        });
    });
}

- (void)closeDialog:(id)sender {
    [self.window close];
    if (_completionHandler) _completionHandler();
}

@end

// ============================================================================
#pragma mark - XLGeneratorPlaceholderDialog
// ============================================================================

@interface XLGeneratorPlaceholderDialog ()

@property (nonatomic, strong) NSImageView *iconView;

@end

@implementation XLGeneratorPlaceholderDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.minWidth = 450;
        self.minHeight = 250;
        self.okButtonTitle = @"OK";
        self.cancelButtonTitle = nil;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 16;

    // Icon
    if (@available(macOS 11.0, *)) {
        NSImage *icon = [NSImage imageWithSystemSymbolName:@"wrench.and.screwdriver"
                                  accessibilityDescription:@"Coming Soon"];
        _iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 48, 48)];
        _iconView.image = icon;
        _iconView.contentTintColor = [NSColor systemBlueColor];
        [_iconView.widthAnchor constraintEqualToConstant:48].active = YES;
        [_iconView.heightAnchor constraintEqualToConstant:48].active = YES;
        [stack addArrangedSubview:_iconView];
    }

    // Title
    self.title = [NSString stringWithFormat:@"%@ - Coming Soon", _featureName ?: @"Feature"];

    // Description
    NSTextField *descLabel = [NSTextField wrappingLabelWithString:_featureDescription ?: @""];
    descLabel.font = [NSFont systemFontOfSize:13];
    descLabel.alignment = NSTextAlignmentCenter;
    [descLabel.widthAnchor constraintLessThanOrEqualToConstant:380].active = YES;
    [stack addArrangedSubview:descLabel];

    // Planned capabilities
    if (_plannedCapabilities.count > 0) {
        NSTextField *capHeader = [NSTextField labelWithString:@"Planned capabilities:"];
        capHeader.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        capHeader.textColor = [NSColor secondaryLabelColor];
        [stack addArrangedSubview:capHeader];

        NSMutableString *capList = [NSMutableString new];
        for (NSString *cap in _plannedCapabilities) {
            [capList appendFormat:@"\u2022 %@\n", cap];
        }

        NSTextField *capLabel = [NSTextField wrappingLabelWithString:capList];
        capLabel.font = [NSFont systemFontOfSize:12];
        capLabel.textColor = [NSColor secondaryLabelColor];
        [capLabel.widthAnchor constraintLessThanOrEqualToConstant:350].active = YES;
        [stack addArrangedSubview:capLabel];
    }

    // Status badge
    NSTextField *statusLabel = [NSTextField labelWithString:@"This feature is coming soon in the native macOS build."];
    statusLabel.font = [NSFont systemFontOfSize:11];
    statusLabel.textColor = [NSColor tertiaryLabelColor];
    statusLabel.alignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:statusLabel];

    return stack;
}

@end
