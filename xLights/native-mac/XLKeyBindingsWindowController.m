/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLKeyBindingsWindowController.h"

static const CGFloat kWindowWidth = 680.0;
static const CGFloat kWindowHeight = 520.0;

#pragma mark - XLKeyBindingEntry

/// Internal model object representing a single key binding row.
@interface XLKeyBindingEntry : NSObject

@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) NSString *shortcut;
@property (nonatomic, copy) NSString *category;

+ (instancetype)entryWithAction:(NSString *)action
                       shortcut:(NSString *)shortcut
                       category:(NSString *)category;

@end

@implementation XLKeyBindingEntry

+ (instancetype)entryWithAction:(NSString *)action
                       shortcut:(NSString *)shortcut
                       category:(NSString *)category {
    XLKeyBindingEntry *entry = [[XLKeyBindingEntry alloc] init];
    entry.action = action;
    entry.shortcut = shortcut;
    entry.category = category;
    return entry;
}

@end

#pragma mark - XLKeyBindingsWindowController

static XLKeyBindingsWindowController *sharedInstance = nil;

@interface XLKeyBindingsWindowController ()

@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSPopUpButton *categoryFilter;
@property (nonatomic, strong) NSTextField *countLabel;

@property (nonatomic, strong) NSArray<XLKeyBindingEntry *> *allBindings;
@property (nonatomic, strong) NSArray<XLKeyBindingEntry *> *filteredBindings;
@property (nonatomic, strong) NSArray<NSString *> *categories;

@end

@implementation XLKeyBindingsWindowController

#pragma mark - Singleton

+ (instancetype)sharedController {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initPrivate];
    });
    return sharedInstance;
}

- (instancetype)initPrivate {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowWidth, kWindowHeight)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];

    self = [super initWithWindow:window];
    if (self) {
        window.title = @"Key Bindings";
        window.minSize = NSMakeSize(500, 350);
        [window center];

        [self setupUI];
        [self buildBindingsList];
        [self applyFilter];
    }
    return self;
}

#pragma mark - UI Setup

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    // Top bar: search field + category filter
    NSView *topBar = [[NSView alloc] initWithFrame:NSMakeRect(0, kWindowHeight - 44, kWindowWidth, 44)];
    topBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

    _searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(12, 8, 300, 28)];
    _searchField.placeholderString = @"Search key bindings...";
    _searchField.delegate = self;
    _searchField.target = self;
    _searchField.action = @selector(searchChanged:);
    _searchField.autoresizingMask = NSViewWidthSizable;
    [topBar addSubview:_searchField];

    _categoryFilter = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(kWindowWidth - 182, 10, 170, 24) pullsDown:NO];
    _categoryFilter.autoresizingMask = NSViewMinXMargin;
    _categoryFilter.target = self;
    _categoryFilter.action = @selector(categoryChanged:);
    [topBar addSubview:_categoryFilter];

    [contentView addSubview:topBar];

    // Table view in scroll view
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 30, kWindowWidth, kWindowHeight - 74)];
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSNoBorder;

    _tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.rowHeight = 24.0;
    _tableView.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    _tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;

    NSTableColumn *actionColumn = [[NSTableColumn alloc] initWithIdentifier:@"action"];
    actionColumn.title = @"Action";
    actionColumn.width = 280;
    actionColumn.minWidth = 150;
    actionColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:actionColumn];

    NSTableColumn *shortcutColumn = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    shortcutColumn.title = @"Shortcut";
    shortcutColumn.width = 180;
    shortcutColumn.minWidth = 100;
    shortcutColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:shortcutColumn];

    NSTableColumn *categoryColumn = [[NSTableColumn alloc] initWithIdentifier:@"category"];
    categoryColumn.title = @"Category";
    categoryColumn.width = 160;
    categoryColumn.minWidth = 80;
    categoryColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:categoryColumn];

    // Allow sorting by clicking column headers
    NSSortDescriptor *actionSort = [NSSortDescriptor sortDescriptorWithKey:@"action" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    NSSortDescriptor *shortcutSort = [NSSortDescriptor sortDescriptorWithKey:@"shortcut" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    NSSortDescriptor *categorySort = [NSSortDescriptor sortDescriptorWithKey:@"category" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    actionColumn.sortDescriptorPrototype = actionSort;
    shortcutColumn.sortDescriptorPrototype = shortcutSort;
    categoryColumn.sortDescriptorPrototype = categorySort;

    scrollView.documentView = _tableView;
    [contentView addSubview:scrollView];

    // Bottom bar: count label
    _countLabel = [NSTextField labelWithString:@""];
    _countLabel.frame = NSMakeRect(12, 6, 400, 18);
    _countLabel.textColor = [NSColor secondaryLabelColor];
    _countLabel.font = [NSFont systemFontOfSize:11];
    _countLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [contentView addSubview:_countLabel];
}

#pragma mark - Building Bindings List

- (void)buildBindingsList {
    NSMutableArray<XLKeyBindingEntry *> *entries = [NSMutableArray array];

    // -- File Menu --
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"New Sequence" shortcut:@"\u2318N" category:@"File"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Open Sequence" shortcut:@"\u2318O" category:@"File"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Save" shortcut:@"\u2318S" category:@"File"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Save As" shortcut:@"\u21E7\u2318S" category:@"File"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Close" shortcut:@"\u2318W" category:@"File"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Backup" shortcut:@"F10" category:@"File"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Alternate Backup" shortcut:@"F11" category:@"File"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Print" shortcut:@"\u2318P" category:@"File"]];

    // -- Edit Menu --
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Undo" shortcut:@"\u2318Z" category:@"Edit"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Redo" shortcut:@"\u21E7\u2318Z" category:@"Edit"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Cut" shortcut:@"\u2318X" category:@"Edit"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Copy" shortcut:@"\u2318C" category:@"Edit"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Paste" shortcut:@"\u2318V" category:@"Edit"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Select All" shortcut:@"\u2318A" category:@"Edit"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Find" shortcut:@"\u2318F" category:@"Edit"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Find Next" shortcut:@"\u2318G" category:@"Edit"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Find Previous" shortcut:@"\u21E7\u2318G" category:@"Edit"]];

    // -- View Menu --
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Show Inspector" shortcut:@"\u2318I" category:@"View"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Show Bottom Panel" shortcut:@"\u2318B" category:@"View"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Show Preview" shortcut:@"\u21E7\u2318P" category:@"View"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Zoom In" shortcut:@"\u2318+" category:@"View"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Zoom Out" shortcut:@"\u2318-" category:@"View"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Zoom to Fit" shortcut:@"\u23180" category:@"View"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Zoom to Selection" shortcut:@"Y" category:@"View"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Full Screen" shortcut:@"\u2303\u2318F" category:@"View"]];

    // -- Sequence / Transport --
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Play / Pause" shortcut:@"Space" category:@"Playback"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Stop" shortcut:@"\u2318." category:@"Playback"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Seek to Start" shortcut:@"\u2318[" category:@"Playback"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Seek to End" shortcut:@"\u2318]" category:@"Playback"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Render All" shortcut:@"\u2318R" category:@"Playback"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Render Selected" shortcut:@"\u21E7\u2318R" category:@"Playback"]];

    // -- Model Menu --
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Add Model" shortcut:@"\u2318M" category:@"Model"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Add Model Group" shortcut:@"\u21E7\u2318M" category:@"Model"]];

    // -- Effect Menu --
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Apply Effect" shortcut:@"\u2318E" category:@"Effect"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Duplicate Effect" shortcut:@"\u2318D" category:@"Effect"]];

    // -- Sequencer Grid --
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Delete Selected Effects" shortcut:@"Delete" category:@"Sequencer"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Move Effect Left" shortcut:@"Left Arrow" category:@"Sequencer"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Move Effect Right" shortcut:@"Right Arrow" category:@"Sequencer"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Stretch Effect Left" shortcut:@"\u21E7Left Arrow" category:@"Sequencer"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Stretch Effect Right" shortcut:@"\u21E7Right Arrow" category:@"Sequencer"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Select Previous Effect" shortcut:@"Up Arrow" category:@"Sequencer"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Select Next Effect" shortcut:@"Down Arrow" category:@"Sequencer"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Toggle Effect Selection" shortcut:@"\u2318 Click" category:@"Sequencer"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Snap to Timing Mark" shortcut:@"\u21E7 Drag" category:@"Sequencer"]];

    // -- Application --
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Preferences" shortcut:@"\u2318," category:@"Application"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Hide xLights" shortcut:@"\u2318H" category:@"Application"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Hide Others" shortcut:@"\u2325\u2318H" category:@"Application"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Quit xLights" shortcut:@"\u2318Q" category:@"Application"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Minimize" shortcut:@"\u2318M" category:@"Application"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Command Palette" shortcut:@"\u21E7\u2318K" category:@"Application"]];
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Help" shortcut:@"\u2318?" category:@"Application"]];

    // -- Layout / Preview --
    [entries addObject:[XLKeyBindingEntry entryWithAction:@"Zoom (Scroll)" shortcut:@"\u2318 Scroll" category:@"Layout"]];

    _allBindings = [entries copy];

    // Build category list
    NSMutableOrderedSet *catSet = [NSMutableOrderedSet orderedSet];
    for (XLKeyBindingEntry *entry in _allBindings) {
        [catSet addObject:entry.category];
    }
    _categories = [catSet array];

    // Populate category filter popup
    [_categoryFilter removeAllItems];
    [_categoryFilter addItemWithTitle:@"All Categories"];
    [[_categoryFilter menu] addItem:[NSMenuItem separatorItem]];
    for (NSString *cat in _categories) {
        [_categoryFilter addItemWithTitle:cat];
    }
}

- (void)reloadBindings {
    [self buildBindingsList];
    [self applyFilter];
}

#pragma mark - Filtering

- (void)applyFilter {
    NSString *searchText = _searchField.stringValue.lowercaseString;
    NSString *selectedCategory = nil;
    if (_categoryFilter.indexOfSelectedItem > 1) {
        selectedCategory = _categoryFilter.titleOfSelectedItem;
    }

    NSMutableArray<XLKeyBindingEntry *> *results = [NSMutableArray array];
    for (XLKeyBindingEntry *entry in _allBindings) {
        // Category filter
        if (selectedCategory && ![entry.category isEqualToString:selectedCategory]) {
            continue;
        }
        // Search filter
        if (searchText.length > 0) {
            BOOL matchAction = [entry.action.lowercaseString containsString:searchText];
            BOOL matchShortcut = [entry.shortcut.lowercaseString containsString:searchText];
            BOOL matchCategory = [entry.category.lowercaseString containsString:searchText];
            if (!matchAction && !matchShortcut && !matchCategory) {
                continue;
            }
        }
        [results addObject:entry];
    }

    _filteredBindings = results;
    [_tableView reloadData];
    _countLabel.stringValue = [NSString stringWithFormat:@"%ld of %ld key bindings",
                               (long)_filteredBindings.count, (long)_allBindings.count];
}

- (void)searchChanged:(id)sender {
    [self applyFilter];
}

- (void)categoryChanged:(id)sender {
    [self applyFilter];
}

#pragma mark - NSSearchFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == _searchField) {
        [self applyFilter];
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_filteredBindings.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_filteredBindings.count) return nil;

    XLKeyBindingEntry *entry = _filteredBindings[row];
    NSString *identifier = tableColumn.identifier;

    if ([identifier isEqualToString:@"action"]) {
        return entry.action;
    } else if ([identifier isEqualToString:@"shortcut"]) {
        return entry.shortcut;
    } else if ([identifier isEqualToString:@"category"]) {
        return entry.category;
    }
    return nil;
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors {
    _filteredBindings = [_filteredBindings sortedArrayUsingDescriptors:tableView.sortDescriptors];
    [_tableView reloadData];
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *identifier = tableColumn.identifier;
    NSTableCellView *cellView = [tableView makeViewWithIdentifier:identifier owner:self];

    if (!cellView) {
        cellView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 24)];
        cellView.identifier = identifier;

        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.frame = cellView.bounds;
        textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;

        if ([identifier isEqualToString:@"shortcut"]) {
            textField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
            textField.textColor = [NSColor systemBlueColor];
        } else {
            textField.font = [NSFont systemFontOfSize:13];
        }

        [cellView addSubview:textField];
        cellView.textField = textField;
    }

    if (row >= 0 && row < (NSInteger)_filteredBindings.count) {
        XLKeyBindingEntry *entry = _filteredBindings[row];

        if ([identifier isEqualToString:@"action"]) {
            cellView.textField.stringValue = entry.action;
        } else if ([identifier isEqualToString:@"shortcut"]) {
            cellView.textField.stringValue = entry.shortcut;
        } else if ([identifier isEqualToString:@"category"]) {
            cellView.textField.stringValue = entry.category;
        }
    }

    return cellView;
}

#pragma mark - Show Window

- (void)showWindow:(id)sender {
    [self.window makeKeyAndOrderFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

@end
