/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLBatchRenderDialog.h"
#import "../XLEngineBridge.h"

/// Sequence item for the table view - uses struct to avoid heap issues
typedef struct {
    __unsafe_unretained NSString *name;
    __unsafe_unretained NSString *modifiedDate;
    __unsafe_unretained NSString *renderedDate;
    BOOL selected;
} XLSequenceItem;

@interface XLBatchRenderDialog () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSPopUpButton *filterPopup;
@property (nonatomic, strong) NSPopUpButton *folderPopup;
@property (nonatomic, strong) NSTextField *selectedCountLabel;
@property (nonatomic, strong) NSButton *forceHDCheckbox;
@property (nonatomic, strong) NSTableView *sequenceTable;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *sequences;
@property (nonatomic, strong) NSMutableArray<NSString *> *allSequenceFiles;
@property (nonatomic, strong) NSMutableArray<NSString *> *subfolders;

@end

@implementation XLBatchRenderDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Batch Render";
        self.minWidth = 600;
        self.minHeight = 450;
        _forceHighDefinition = YES;
        _sequences = [NSMutableArray array];
        _allSequenceFiles = [NSMutableArray array];
        _subfolders = [NSMutableArray array];
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Filter row
    NSStackView *filterRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    filterRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    filterRow.spacing = 8;

    NSTextField *filterLabel = [NSTextField labelWithString:@"Filter:"];
    _filterPopup = [XLBaseSheetController createPopUpButton];
    [_filterPopup addItemWithTitle:@"Recursive Search"];
    [_filterPopup addItemWithTitle:@"Only Show Directory"];
    [_filterPopup setTarget:self];
    [_filterPopup setAction:@selector(filterChanged:)];
    [_filterPopup.widthAnchor constraintEqualToConstant:180].active = YES;

    [filterRow addArrangedSubview:filterLabel];
    [filterRow addArrangedSubview:_filterPopup];
    [stack addArrangedSubview:filterRow];

    // Folder row
    NSStackView *folderRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    folderRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    folderRow.spacing = 8;

    NSTextField *folderLabel = [NSTextField labelWithString:@"Folder:"];
    _folderPopup = [XLBaseSheetController createPopUpButton];
    [_folderPopup setTarget:self];
    [_folderPopup setAction:@selector(folderChanged:)];
    [_folderPopup.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;

    [folderRow addArrangedSubview:folderLabel];
    [folderRow addArrangedSubview:_folderPopup];
    [stack addArrangedSubview:folderRow];

    // Selected count row
    NSStackView *selectedRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    selectedRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    selectedRow.spacing = 8;

    NSTextField *selectedLabel = [NSTextField labelWithString:@"Selected:"];
    _selectedCountLabel = [NSTextField labelWithString:@"0"];
    _selectedCountLabel.alignment = NSTextAlignmentRight;
    [_selectedCountLabel.widthAnchor constraintEqualToConstant:60].active = YES;

    [selectedRow addArrangedSubview:selectedLabel];
    [selectedRow addArrangedSubview:_selectedCountLabel];
    [stack addArrangedSubview:selectedRow];

    // Force HD checkbox
    _forceHDCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Force High Definition"];
    _forceHDCheckbox.state = _forceHighDefinition ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_forceHDCheckbox];

    // Table view
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.borderType = NSBezelBorder;

    _sequenceTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _sequenceTable.dataSource = self;
    _sequenceTable.delegate = self;
    _sequenceTable.allowsMultipleSelection = YES;
    _sequenceTable.usesAlternatingRowBackgroundColors = YES;
    _sequenceTable.rowHeight = 20;

    // Checkbox column
    NSTableColumn *checkColumn = [[NSTableColumn alloc] initWithIdentifier:@"check"];
    checkColumn.title = @"";
    checkColumn.width = 30;
    checkColumn.minWidth = 30;
    checkColumn.maxWidth = 30;
    [_sequenceTable addTableColumn:checkColumn];

    // Name column
    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Sequence";
    nameColumn.width = 250;
    nameColumn.minWidth = 100;
    [nameColumn.headerCell setAlignment:NSTextAlignmentLeft];
    [_sequenceTable addTableColumn:nameColumn];

    // Modified date column
    NSTableColumn *modifiedColumn = [[NSTableColumn alloc] initWithIdentifier:@"modified"];
    modifiedColumn.title = @"Modified Date";
    modifiedColumn.width = 140;
    modifiedColumn.minWidth = 100;
    [_sequenceTable addTableColumn:modifiedColumn];

    // Rendered date column
    NSTableColumn *renderedColumn = [[NSTableColumn alloc] initWithIdentifier:@"rendered"];
    renderedColumn.title = @"Last Render Date";
    renderedColumn.width = 140;
    renderedColumn.minWidth = 100;
    [_sequenceTable addTableColumn:renderedColumn];

    scrollView.documentView = _sequenceTable;

    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    [stack addArrangedSubview:scrollView];
    [scrollView.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [scrollView.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    return stack;
}

- (void)sheetDidLoad {
    [self scanDirectory];
    [self populateControls];
    [self updateSequenceList];
}

- (void)scanDirectory {
    if (!_showDirectory || _showDirectory.length == 0) {
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;

    // Get subfolders
    [_subfolders removeAllObjects];
    [_subfolders addObject:@""]; // Root folder option

    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:_showDirectory error:&error];
    for (NSString *item in contents) {
        if ([item hasPrefix:@"."]) continue;
        if ([item isEqualToString:@"Backup"]) continue;

        NSString *fullPath = [_showDirectory stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:fullPath isDirectory:&isDir] && isDir) {
            [_subfolders addObject:item];
        }
    }

    // Get sequence files recursively
    [_allSequenceFiles removeAllObjects];
    [self scanDirectoryForSequences:_showDirectory basePath:_showDirectory];
}

- (void)scanDirectoryForSequences:(NSString *)path basePath:(NSString *)basePath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;

    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:path error:&error];
    if (error) return;

    for (NSString *item in contents) {
        if ([item hasPrefix:@"."]) continue;
        if ([item hasPrefix:@"._"]) continue;
        if ([item isEqualToString:@"Backup"]) continue;

        NSString *fullPath = [path stringByAppendingPathComponent:item];
        BOOL isDir = NO;

        if ([fm fileExistsAtPath:fullPath isDirectory:&isDir]) {
            if (isDir) {
                [self scanDirectoryForSequences:fullPath basePath:basePath];
            } else {
                NSString *ext = item.pathExtension.lowercaseString;
                if ([ext isEqualToString:@"xsq"] || [ext isEqualToString:@"xml"]) {
                    // Skip xlights_ prefixed files
                    if ([item hasPrefix:@"xlights_"]) continue;

                    // Get relative path
                    NSString *relativePath = [fullPath substringFromIndex:basePath.length];
                    if ([relativePath hasPrefix:@"/"]) {
                        relativePath = [relativePath substringFromIndex:1];
                    }
                    [_allSequenceFiles addObject:relativePath];
                }
            }
        }
    }
}

- (void)populateControls {
    [_folderPopup removeAllItems];
    for (NSString *folder in _subfolders) {
        [_folderPopup addItemWithTitle:folder.length > 0 ? folder : @"(All)"];
    }
}

- (void)updateSequenceList {
    [_sequences removeAllObjects];

    NSInteger filterType = _filterPopup.indexOfSelectedItem;
    NSString *selectedFolder = _subfolders[_folderPopup.indexOfSelectedItem];

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";

    for (NSString *file in _allSequenceFiles) {
        BOOL include = NO;

        if (filterType == 0) {
            // Recursive - filter by folder prefix
            if (selectedFolder.length == 0 || [file hasPrefix:selectedFolder]) {
                include = YES;
            }
        } else {
            // Only show directory - no subfolders
            if (![file containsString:@"/"]) {
                include = YES;
            }
        }

        if (include) {
            NSMutableDictionary *item = [NSMutableDictionary dictionary];
            item[@"name"] = file;
            item[@"selected"] = @NO;

            // Get file dates
            NSString *fullPath = [_showDirectory stringByAppendingPathComponent:file];
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:nil];
            if (attrs) {
                NSDate *modDate = attrs[NSFileModificationDate];
                if (modDate) {
                    item[@"modified"] = [dateFormatter stringFromDate:modDate];
                }
            }

            // Check for rendered FSEQ file
            NSString *fseqPath = [[fullPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"fseq"];
            NSDictionary *fseqAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:fseqPath error:nil];
            if (fseqAttrs) {
                NSDate *renderDate = fseqAttrs[NSFileModificationDate];
                if (renderDate) {
                    item[@"rendered"] = [dateFormatter stringFromDate:renderDate];
                }
            }

            [_sequences addObject:item];
        }
    }

    // Sort by name
    [_sequences sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] compare:b[@"name"]];
    }];

    [_sequenceTable reloadData];
    [self updateSelectedCount];
}

- (void)updateSelectedCount {
    NSInteger count = 0;
    for (NSDictionary *item in _sequences) {
        if ([item[@"selected"] boolValue]) {
            count++;
        }
    }
    _selectedCountLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)count];
    [self updateOKButtonState];
}

#pragma mark - Actions

- (void)filterChanged:(id)sender {
    _folderPopup.enabled = (_filterPopup.indexOfSelectedItem == 0);
    [self updateSequenceList];
}

- (void)folderChanged:(id)sender {
    [self updateSequenceList];
}

- (void)checkboxClicked:(id)sender {
    NSButton *checkbox = (NSButton *)sender;
    NSInteger row = checkbox.tag;

    if (row >= 0 && row < (NSInteger)_sequences.count) {
        _sequences[row][@"selected"] = @(checkbox.state == NSControlStateValueOn);
        [self updateSelectedCount];
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _sequences.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_sequences.count) return nil;

    NSDictionary *item = _sequences[row];
    NSString *identifier = tableColumn.identifier;

    if ([identifier isEqualToString:@"check"]) {
        NSButton *checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxClicked:)];
        checkbox.tag = row;
        checkbox.state = [item[@"selected"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        return checkbox;
    }

    NSTextField *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = identifier;
    }

    if ([identifier isEqualToString:@"name"]) {
        cell.stringValue = item[@"name"] ?: @"";
    } else if ([identifier isEqualToString:@"modified"]) {
        cell.stringValue = item[@"modified"] ?: @"";
    } else if ([identifier isEqualToString:@"rendered"]) {
        cell.stringValue = item[@"rendered"] ?: @"";
    }

    return cell;
}

#pragma mark - Validation & Results

- (NSString *)validate {
    NSInteger count = 0;
    for (NSDictionary *item in _sequences) {
        if ([item[@"selected"] boolValue]) {
            count++;
        }
    }

    if (count == 0) {
        return @"Please select at least one sequence to render.";
    }

    return nil;
}

- (void)okClicked:(id)sender {
    _forceHighDefinition = (_forceHDCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

- (NSArray<NSString *> *)selectedSequences {
    NSMutableArray<NSString *> *selected = [NSMutableArray array];
    for (NSDictionary *item in _sequences) {
        if ([item[@"selected"] boolValue]) {
            [selected addObject:item[@"name"]];
        }
    }
    return [selected copy];
}

@end
