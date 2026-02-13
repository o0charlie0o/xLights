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
#import "input/XLKeyboardHandler.h"

#include "xlCore/KeyBindings.h"
#include <memory>

NSNotificationName const XLKeyBindingsDidChangeNotification = @"XLKeyBindingsDidChangeNotification";

static const CGFloat kWindowWidth = 680.0;
static const CGFloat kWindowHeight = 520.0;

#pragma mark - XLKeyBindingEntry

@interface XLKeyBindingEntry : NSObject

@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) NSString *shortcut;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *tooltip;
@property (nonatomic, copy) NSString *actionType;   // raw xlCore type (e.g. "TIMING_ADD")
@property (nonatomic, assign) int bindingId;         // xlCore binding ID
@property (nonatomic, assign) BOOL isDisabled;
@property (nonatomic, assign) BOOL isDuplicate;

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

#pragma mark - Helpers

/// Format a raw type string like "TIMING_ADD" to "Timing Add"
static NSString *formatActionType(const std::string &type) {
    NSString *raw = [NSString stringWithUTF8String:type.c_str()];
    NSArray *parts = [raw componentsSeparatedByString:@"_"];
    NSMutableArray *formatted = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length == 0) continue;
        [formatted addObject:[NSString stringWithFormat:@"%@%@",
                              [part substringToIndex:1].uppercaseString,
                              [part substringFromIndex:1].lowercaseString]];
    }
    return [formatted componentsJoinedByString:@" "];
}

/// Build a macOS-style shortcut string from a KeyBinding
static NSString *macOSShortcutString(const xlCore::KeyBinding &binding) {
    if (binding.isDisabled()) return @"—";

    NSMutableString *result = [NSMutableString string];
    if (binding.requiresControl()) {
        [result appendString:@"\u2318"];  // Cmd
    }
    if (binding.requiresRawControl()) {
        [result appendString:@"\u2303"];  // Ctrl
    }
    if (binding.requiresAlt()) {
        [result appendString:@"\u2325"];  // Option
    }
    if (binding.requiresShift()) {
        [result appendString:@"\u21E7"];  // Shift
    }
    std::string keyStr = xlCore::KeyBinding::encodeKey(binding.getKey(), binding.requiresShift());
    [result appendString:[NSString stringWithUTF8String:keyStr.c_str()]];
    return result;
}

/// Map xlCore::KeyScope to a display category string
static NSString *categoryForScope(xlCore::KeyScope scope) {
    switch (scope) {
        case xlCore::KeyScope::All:      return @"All";
        case xlCore::KeyScope::Setup:    return @"Setup";
        case xlCore::KeyScope::Layout:   return @"Layout";
        case xlCore::KeyScope::Sequence: return @"Sequence";
        default:                         return @"Other";
    }
}

#pragma mark - XLKeyBindingsWindowController

static XLKeyBindingsWindowController *sharedInstance = nil;

@interface XLKeyBindingsWindowController () {
    std::unique_ptr<xlCore::KeyBindingMap> _bindingMap;
}

@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSPopUpButton *categoryFilter;
@property (nonatomic, strong) NSTextField *countLabel;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSButton *revertButton;

@property (nonatomic, strong) NSArray<XLKeyBindingEntry *> *allBindings;
@property (nonatomic, strong) NSArray<XLKeyBindingEntry *> *filteredBindings;
@property (nonatomic, strong) NSArray<NSString *> *categories;

@property (nonatomic, assign) NSInteger recordingRow;
@property (nonatomic, assign) BOOL hasUnsavedChanges;
@property (nonatomic, strong) id keyEventMonitor;
@property (nonatomic, copy) NSString *showFolderPath;

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
        window.delegate = (id<NSWindowDelegate>)self;
        [window center];

        _recordingRow = -1;
        _hasUnsavedChanges = NO;

        [self setupUI];
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
    CGFloat bottomBarHeight = 40.0;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, bottomBarHeight, kWindowWidth, kWindowHeight - 44 - bottomBarHeight)];
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
    _tableView.doubleAction = @selector(tableViewDoubleClick:);
    _tableView.target = self;

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

    // Sorting
    NSSortDescriptor *actionSort = [NSSortDescriptor sortDescriptorWithKey:@"action" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    NSSortDescriptor *shortcutSort = [NSSortDescriptor sortDescriptorWithKey:@"shortcut" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    NSSortDescriptor *categorySort = [NSSortDescriptor sortDescriptorWithKey:@"category" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    actionColumn.sortDescriptorPrototype = actionSort;
    shortcutColumn.sortDescriptorPrototype = shortcutSort;
    categoryColumn.sortDescriptorPrototype = categorySort;

    scrollView.documentView = _tableView;
    [contentView addSubview:scrollView];

    // Bottom bar: count label + Save/Revert buttons
    NSView *bottomBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kWindowWidth, bottomBarHeight)];
    bottomBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;

    _countLabel = [NSTextField labelWithString:@""];
    _countLabel.frame = NSMakeRect(12, 10, 300, 18);
    _countLabel.textColor = [NSColor secondaryLabelColor];
    _countLabel.font = [NSFont systemFontOfSize:11];
    _countLabel.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [bottomBar addSubview:_countLabel];

    _revertButton = [NSButton buttonWithTitle:@"Revert" target:self action:@selector(revertClicked:)];
    _revertButton.frame = NSMakeRect(kWindowWidth - 170, 6, 72, 28);
    _revertButton.autoresizingMask = NSViewMinXMargin;
    _revertButton.enabled = NO;
    [bottomBar addSubview:_revertButton];

    _saveButton = [NSButton buttonWithTitle:@"Save" target:self action:@selector(saveClicked:)];
    _saveButton.frame = NSMakeRect(kWindowWidth - 90, 6, 72, 28);
    _saveButton.autoresizingMask = NSViewMinXMargin;
    _saveButton.bezelStyle = NSBezelStyleRounded;
    _saveButton.keyEquivalent = @"\r";
    _saveButton.enabled = NO;
    [bottomBar addSubview:_saveButton];

    [contentView addSubview:bottomBar];
}

#pragma mark - Loading Bindings from xlCore

- (void)loadBindingsFromShowFolder {
    _bindingMap = std::make_unique<xlCore::KeyBindingMap>();

    if (_showFolderPath.length > 0) {
        std::string path = std::string(_showFolderPath.UTF8String) + "/key_bindings.xml";
        _bindingMap->loadFromFile(path);
    } else {
        _bindingMap->loadDefaults();
    }

    [self buildBindingsListFromMap];
    [self applyFilter];
    self.hasUnsavedChanges = NO;
}

- (void)buildBindingsListFromMap {
    if (!_bindingMap) return;

    NSMutableArray<XLKeyBindingEntry *> *entries = [NSMutableArray array];
    const auto &bindings = _bindingMap->getBindings();

    for (const auto &binding : bindings) {
        XLKeyBindingEntry *entry = [[XLKeyBindingEntry alloc] init];

        // Display name
        const std::string &type = binding.getType();
        if (type == "EFFECT") {
            entry.action = [NSString stringWithFormat:@"Effect: %s", binding.getEffectName().c_str()];
        } else if (type == "PRESET") {
            entry.action = [NSString stringWithFormat:@"Preset: %s", binding.getEffectName().c_str()];
        } else if (type == "APPLYSETTING") {
            entry.action = [NSString stringWithFormat:@"Apply Setting: %s", binding.getEffectString().c_str()];
        } else {
            entry.action = formatActionType(type);
        }

        entry.shortcut = macOSShortcutString(binding);
        entry.category = categoryForScope(binding.getScope());
        entry.actionType = [NSString stringWithUTF8String:type.c_str()];
        entry.bindingId = binding.getId();
        entry.isDisabled = binding.isDisabled();

        // Tooltip
        std::string tip = binding.getTip();
        entry.tooltip = tip.empty() ? @"" : [NSString stringWithUTF8String:tip.c_str()];

        // Check for duplicates
        entry.isDuplicate = NO;
        if (!binding.isDisabled()) {
            for (const auto &other : bindings) {
                if (binding.isDuplicateKey(other)) {
                    entry.isDuplicate = YES;
                    break;
                }
            }
        }

        [entries addObject:entry];
    }

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
    [self loadBindingsFromShowFolder];
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
        if (selectedCategory && ![entry.category isEqualToString:selectedCategory]) continue;
        if (searchText.length > 0) {
            BOOL matchAction = [entry.action.lowercaseString containsString:searchText];
            BOOL matchShortcut = [entry.shortcut.lowercaseString containsString:searchText];
            BOOL matchCategory = [entry.category.lowercaseString containsString:searchText];
            if (!matchAction && !matchShortcut && !matchCategory) continue;
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

    if ([identifier isEqualToString:@"action"]) return entry.action;
    if ([identifier isEqualToString:@"shortcut"]) return entry.shortcut;
    if ([identifier isEqualToString:@"category"]) return entry.category;
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
        } else {
            textField.font = [NSFont systemFontOfSize:13];
        }

        [cellView addSubview:textField];
        cellView.textField = textField;
    }

    if (row >= 0 && row < (NSInteger)_filteredBindings.count) {
        XLKeyBindingEntry *entry = _filteredBindings[row];
        BOOL isRecording = (_recordingRow == row && [identifier isEqualToString:@"shortcut"]);

        if ([identifier isEqualToString:@"action"]) {
            cellView.textField.stringValue = entry.action;
            cellView.textField.textColor = entry.isDuplicate ? [NSColor systemRedColor] : [NSColor labelColor];
        } else if ([identifier isEqualToString:@"shortcut"]) {
            if (isRecording) {
                cellView.textField.stringValue = @"Press a key\u2026";
                cellView.textField.textColor = [NSColor systemOrangeColor];
            } else {
                cellView.textField.stringValue = entry.shortcut;
                cellView.textField.textColor = entry.isDuplicate ? [NSColor systemRedColor]
                                               : entry.isDisabled ? [NSColor tertiaryLabelColor]
                                               : [NSColor systemBlueColor];
            }
        } else if ([identifier isEqualToString:@"category"]) {
            cellView.textField.stringValue = entry.category;
            cellView.textField.textColor = [NSColor labelColor];
        }

        cellView.toolTip = entry.tooltip;
    }

    return cellView;
}

#pragma mark - Double-click to record

- (void)tableViewDoubleClick:(id)sender {
    NSInteger row = _tableView.clickedRow;
    NSInteger col = _tableView.clickedColumn;
    if (row < 0 || row >= (NSInteger)_filteredBindings.count) return;

    // Only start recording when double-clicking the shortcut column
    NSTableColumn *column = _tableView.tableColumns[col];
    if (![column.identifier isEqualToString:@"shortcut"]) return;

    [self startRecordingForRow:row];
}

- (void)startRecordingForRow:(NSInteger)row {
    _recordingRow = row;
    [_tableView reloadData];

    // Install local key event monitor to capture the next keypress
    __weak typeof(self) weakSelf = self;
    _keyEventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return event;
        [strongSelf handleRecordedKeyEvent:event];
        return nil; // consume the event
    }];
}

- (void)stopRecording {
    if (_keyEventMonitor) {
        [NSEvent removeMonitor:_keyEventMonitor];
        _keyEventMonitor = nil;
    }
    _recordingRow = -1;
}

#pragma mark - Key capture

- (void)handleRecordedKeyEvent:(NSEvent *)event {
    if (_recordingRow < 0 || _recordingRow >= (NSInteger)_filteredBindings.count) {
        [self stopRecording];
        return;
    }

    XLKeyBindingEntry *entry = _filteredBindings[_recordingRow];
    [self stopRecording];

    // Escape: cancel
    if (event.keyCode == 53 /* kVK_Escape */) {
        [_tableView reloadData];
        return;
    }

    xlCore::KeyBinding *binding = _bindingMap ? _bindingMap->getBinding(entry.bindingId) : nullptr;
    if (!binding) {
        [_tableView reloadData];
        return;
    }

    // Delete/Backspace: clear binding
    if (event.keyCode == 51 /* kVK_Delete */ || event.keyCode == 117 /* kVK_ForwardDelete */) {
        binding->setDisabled(true);
        binding->setKey(xlCore::KeyCode::None);
        [self markChanged];
        [self rebuildAndReload];
        return;
    }

    // Convert NSEvent to xlCore key code
    int xlKeyCode = [XLKeyboardHandler xlCoreKeyCodeFromNSEventKeyCode:event.keyCode
                                                            characters:event.charactersIgnoringModifiers];
    if (xlKeyCode == 0) {
        [_tableView reloadData];
        return;
    }

    // Parse modifiers: Cmd → control, physical Ctrl → rawControl
    NSEventModifierFlags flags = event.modifierFlags;
    bool cmd = (flags & NSEventModifierFlagCommand) != 0;
    bool option = (flags & NSEventModifierFlagOption) != 0;
    bool control = (flags & NSEventModifierFlagControl) != 0;
    bool shift = (flags & NSEventModifierFlagShift) != 0;

    // Check for conflicts (excluding self) — same key combo in overlapping scope
    auto newKey = static_cast<xlCore::KeyCode>(xlKeyCode);
    auto myScope = binding->getScope();
    xlCore::KeyBinding *conflicting = nullptr;
    for (auto &other : _bindingMap->getBindings()) {
        if (other.getId() == binding->getId()) continue;
        if (other.isDisabled()) continue;
        // Check overlapping scope
        auto otherScope = other.getScope();
        if (otherScope != myScope && otherScope != xlCore::KeyScope::All && myScope != xlCore::KeyScope::All) continue;
        // Check same key combo
        if (other.getKey() != newKey) continue;
        if (other.requiresAlt() != option) continue;
        if (other.requiresShift() != shift) continue;
        if (!xlCore::KeyBinding::isControlEqual(other, cmd, control)) continue;
        conflicting = &other;
        break;
    }

    if (conflicting) {
        // Show conflict alert
        NSString *conflictName;
        const std::string &ctype = conflicting->getType();
        if (ctype == "EFFECT") {
            conflictName = [NSString stringWithFormat:@"Effect: %s", conflicting->getEffectName().c_str()];
        } else {
            conflictName = formatActionType(ctype);
        }

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Key Conflict";
        alert.informativeText = [NSString stringWithFormat:
                                 @"This key is already assigned to \"%@\".\n\nReassign it to \"%@\"?",
                                 conflictName, entry.action];
        [alert addButtonWithTitle:@"Reassign"];
        [alert addButtonWithTitle:@"Cancel"];
        alert.alertStyle = NSAlertStyleWarning;

        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response == NSAlertFirstButtonReturn) {
                // Clear the conflicting binding
                conflicting->setDisabled(true);
                conflicting->setKey(xlCore::KeyCode::None);

                // Apply to our binding
                binding->setKey(static_cast<xlCore::KeyCode>(xlKeyCode));
                binding->setControl(cmd);
                binding->setRawControl(control);
                binding->setAlt(option);
                binding->setShift(shift);
                binding->setDisabled(false);

                [self markChanged];
                [self rebuildAndReload];
            } else {
                [self->_tableView reloadData];
            }
        }];
        return;
    }

    // No conflict — apply directly
    binding->setKey(static_cast<xlCore::KeyCode>(xlKeyCode));
    binding->setControl(cmd);
    binding->setRawControl(control);
    binding->setAlt(option);
    binding->setShift(shift);
    binding->setDisabled(false);

    [self markChanged];
    [self rebuildAndReload];
}

#pragma mark - Save / Revert

- (void)markChanged {
    self.hasUnsavedChanges = YES;
    _saveButton.enabled = YES;
    _revertButton.enabled = YES;
    self.window.documentEdited = YES;
}

- (void)rebuildAndReload {
    [self buildBindingsListFromMap];
    [self applyFilter];
}

- (void)saveClicked:(id)sender {
    if (!_bindingMap) return;

    _bindingMap->save();
    self.hasUnsavedChanges = NO;
    _saveButton.enabled = NO;
    _revertButton.enabled = NO;
    self.window.documentEdited = NO;

    [[NSNotificationCenter defaultCenter] postNotificationName:XLKeyBindingsDidChangeNotification
                                                        object:self];
}

- (void)revertClicked:(id)sender {
    [self loadBindingsFromShowFolder];
    _saveButton.enabled = NO;
    _revertButton.enabled = NO;
    self.window.documentEdited = NO;
}

#pragma mark - Window delegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
    [self stopRecording];
    if (!self.hasUnsavedChanges) return YES;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Unsaved Changes";
    alert.informativeText = @"You have unsaved key binding changes. Do you want to save them?";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Don\u2019t Save"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [self saveClicked:nil];
            [self.window close];
        } else if (response == NSAlertSecondButtonReturn) {
            self.hasUnsavedChanges = NO;
            self.window.documentEdited = NO;
            [self.window close];
        }
        // Cancel: do nothing
    }];
    return NO;
}

#pragma mark - Show Folder Path

- (void)setShowFolderPath:(NSString *)showFolderPath {
    if ([_showFolderPath isEqualToString:showFolderPath]) return;
    _showFolderPath = [showFolderPath copy];
    // Reload if we already have bindings loaded (otherwise, loadBindingsFromShowFolder
    // will be called on first showWindow:)
    if (_bindingMap) {
        [self loadBindingsFromShowFolder];
    }
}

#pragma mark - Show Window

- (void)showWindow:(id)sender {
    if (!_bindingMap) {
        [self loadBindingsFromShowFolder];
    }
    [self.window makeKeyAndOrderFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

@end
