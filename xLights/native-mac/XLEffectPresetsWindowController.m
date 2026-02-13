/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLEffectPresetsWindowController.h"
#import "XLEngineBridge.h"

static NSString * const kWindowFrameKey = @"XLEffectPresetsWindowFrame";
static NSString * const kPresetsFolderName = @"Presets";

// Preset plist keys
static NSString * const kPresetKeyName = @"name";
static NSString * const kPresetKeyEffectType = @"effectType";
static NSString * const kPresetKeySettings = @"settings";
static NSString * const kPresetKeyPalette = @"palette";
static NSString * const kPresetKeyDateCreated = @"dateCreated";

#pragma mark - Preset Group Node

/// Represents a group (effect type) or individual preset in the outline view.
@interface XLPresetNode : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *effectType;
@property (nonatomic, strong) NSDictionary *presetData;    // nil for group nodes
@property (nonatomic, strong) NSMutableArray<XLPresetNode *> *children;  // nil for leaf nodes
@property (nonatomic, assign) BOOL isGroup;
@end

@implementation XLPresetNode
- (instancetype)initGroupWithName:(NSString *)name {
    self = [super init];
    if (self) {
        _name = [name copy];
        _effectType = [name copy];
        _isGroup = YES;
        _children = [NSMutableArray array];
    }
    return self;
}
- (instancetype)initPresetWithName:(NSString *)name effectType:(NSString *)effectType data:(NSDictionary *)data {
    self = [super init];
    if (self) {
        _name = [name copy];
        _effectType = [effectType copy];
        _presetData = data;
        _isGroup = NO;
    }
    return self;
}
@end

#pragma mark - Window Controller

@implementation XLEffectPresetsWindowController {
    NSOutlineView *_outlineView;
    NSScrollView *_scrollView;
    NSButton *_saveButton;
    NSButton *_loadButton;
    NSButton *_deleteButton;
    NSButton *_renameButton;
    NSMutableArray<XLPresetNode *> *_rootNodes;  // Group nodes (by effect type)
    NSInteger _currentEffectId;
}

- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(200, 200, 400, 500)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable |
                             NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];

    window.title = @"Effect Presets";
    window.minSize = NSMakeSize(300, 350);
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    window.level = NSFloatingWindowLevel;

    self = [super initWithWindow:window];
    if (self) {
        _engineBridge = engineBridge;
        _rootNodes = [NSMutableArray array];
        _currentEffectId = -1;

        [self setupUI];

        NSString *frameString = [[NSUserDefaults standardUserDefaults] stringForKey:kWindowFrameKey];
        if (frameString) {
            NSRect frame = NSRectFromString(frameString);
            if (frame.size.width > 0 && frame.size.height > 0) {
                [window setFrame:frame display:NO];
            }
        }

        [self reloadPresets];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;
    contentView.autoresizesSubviews = YES;

    // Button bar at the bottom
    CGFloat buttonBarHeight = 44.0;
    CGFloat buttonWidth = 80.0;
    CGFloat buttonSpacing = 8.0;
    CGFloat buttonY = 10.0;

    _saveButton = [NSButton buttonWithTitle:@"Save" target:self action:@selector(savePresetAction:)];
    _saveButton.bezelStyle = NSBezelStyleRounded;
    _saveButton.frame = NSMakeRect(buttonSpacing, buttonY, buttonWidth, 28);
    _saveButton.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [contentView addSubview:_saveButton];

    _loadButton = [NSButton buttonWithTitle:@"Load" target:self action:@selector(loadPresetAction:)];
    _loadButton.bezelStyle = NSBezelStyleRounded;
    _loadButton.frame = NSMakeRect(buttonSpacing + (buttonWidth + buttonSpacing), buttonY, buttonWidth, 28);
    _loadButton.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    _loadButton.enabled = NO;
    [contentView addSubview:_loadButton];

    _renameButton = [NSButton buttonWithTitle:@"Rename" target:self action:@selector(renamePresetAction:)];
    _renameButton.bezelStyle = NSBezelStyleRounded;
    _renameButton.frame = NSMakeRect(buttonSpacing + 2 * (buttonWidth + buttonSpacing), buttonY, buttonWidth, 28);
    _renameButton.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    _renameButton.enabled = NO;
    [contentView addSubview:_renameButton];

    _deleteButton = [NSButton buttonWithTitle:@"Delete" target:self action:@selector(deletePresetAction:)];
    _deleteButton.bezelStyle = NSBezelStyleRounded;
    _deleteButton.frame = NSMakeRect(buttonSpacing + 3 * (buttonWidth + buttonSpacing), buttonY, buttonWidth, 28);
    _deleteButton.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    _deleteButton.enabled = NO;
    [contentView addSubview:_deleteButton];

    // Outline view with scroll view
    NSRect scrollRect = NSMakeRect(0, buttonBarHeight,
                                   NSWidth(contentView.bounds),
                                   NSHeight(contentView.bounds) - buttonBarHeight);

    _scrollView = [[NSScrollView alloc] initWithFrame:scrollRect];
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.borderType = NSNoBorder;

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Presets";
    nameColumn.minWidth = 120;
    nameColumn.resizingMask = NSTableColumnAutoresizingMask;

    NSTableColumn *typeColumn = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeColumn.title = @"Effect Type";
    typeColumn.width = 120;
    typeColumn.minWidth = 80;

    _outlineView = [[NSOutlineView alloc] initWithFrame:_scrollView.bounds];
    [_outlineView addTableColumn:nameColumn];
    [_outlineView addTableColumn:typeColumn];
    _outlineView.outlineTableColumn = nameColumn;
    _outlineView.dataSource = self;
    _outlineView.delegate = self;
    _outlineView.headerView = nil;
    _outlineView.rowHeight = 22.0;
    _outlineView.usesAlternatingRowBackgroundColors = YES;
    _outlineView.allowsMultipleSelection = NO;
    _outlineView.target = self;
    _outlineView.doubleAction = @selector(loadPresetAction:);

    _scrollView.documentView = _outlineView;
    [contentView addSubview:_scrollView];
}

#pragma mark - Preset Storage

- (NSString *)presetsDirectory {
    NSString *showFolder = [_engineBridge getShowFolderPath];
    if (!showFolder || showFolder.length == 0) {
        showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    }
    if (!showFolder || showFolder.length == 0) return nil;

    NSString *presetsDir = [showFolder stringByAppendingPathComponent:kPresetsFolderName];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:presetsDir]) {
        [fm createDirectoryAtPath:presetsDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return presetsDir;
}

- (NSString *)sanitizedFilename:(NSString *)name {
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    return [[name componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@"_"];
}

- (NSString *)presetPathForName:(NSString *)presetName {
    NSString *dir = [self presetsDirectory];
    if (!dir) return nil;
    NSString *filename = [NSString stringWithFormat:@"%@.xlpreset", [self sanitizedFilename:presetName]];
    return [dir stringByAppendingPathComponent:filename];
}

- (NSDictionary *)loadPresetFromFile:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [NSDictionary dictionaryWithContentsOfFile:path];
}

- (BOOL)savePresetToFile:(NSDictionary *)presetData path:(NSString *)path {
    return [presetData writeToFile:path atomically:YES];
}

#pragma mark - Public API

- (void)reloadPresets {
    [_rootNodes removeAllObjects];

    NSString *presetsDir = [self presetsDirectory];
    if (!presetsDir) {
        [_outlineView reloadData];
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:presetsDir error:nil];

    // Group presets by effect type
    NSMutableDictionary<NSString *, XLPresetNode *> *groupMap = [NSMutableDictionary dictionary];

    for (NSString *file in files) {
        if (![file.pathExtension isEqualToString:@"xlpreset"]) continue;

        NSString *fullPath = [presetsDir stringByAppendingPathComponent:file];
        NSDictionary *data = [self loadPresetFromFile:fullPath];
        if (!data) continue;

        NSString *effectType = data[kPresetKeyEffectType] ?: @"Unknown";
        NSString *presetName = data[kPresetKeyName] ?: [file stringByDeletingPathExtension];

        XLPresetNode *groupNode = groupMap[effectType];
        if (!groupNode) {
            groupNode = [[XLPresetNode alloc] initGroupWithName:effectType];
            groupMap[effectType] = groupNode;
        }

        XLPresetNode *presetNode = [[XLPresetNode alloc] initPresetWithName:presetName
                                                                 effectType:effectType
                                                                       data:data];
        [groupNode.children addObject:presetNode];
    }

    // Sort groups alphabetically
    NSArray *sortedKeys = [[groupMap allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *key in sortedKeys) {
        XLPresetNode *group = groupMap[key];
        // Sort presets within group
        [group.children sortUsingComparator:^NSComparisonResult(XLPresetNode *a, XLPresetNode *b) {
            return [a.name localizedCaseInsensitiveCompare:b.name];
        }];
        [_rootNodes addObject:group];
    }

    [_outlineView reloadData];

    // Expand all groups
    for (XLPresetNode *group in _rootNodes) {
        [_outlineView expandItem:group];
    }
}

- (void)savePresetFromEffect:(NSInteger)effectId {
    _currentEffectId = effectId;
    if (effectId < 0 || !_engineBridge) return;

    NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
    if (!effectInfo) {
        NSLog(@"EffectPresets: Cannot get effect info for ID %ld", (long)effectId);
        return;
    }

    NSString *effectType = effectInfo[@"effectType"] ?: @"Unknown";
    NSString *settings = [_engineBridge getEffectSettings:effectId];
    NSString *palette = [_engineBridge getEffectPalette:effectId];

    // Prompt for preset name
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save Effect Preset";
    alert.informativeText = [NSString stringWithFormat:@"Save the current %@ effect settings as a preset:", effectType];
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    nameField.stringValue = [NSString stringWithFormat:@"My %@ Preset", effectType];
    nameField.placeholderString = @"Preset name";
    alert.accessoryView = nameField;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) return;

        NSString *presetName = nameField.stringValue;
        if (presetName.length == 0) return;

        NSMutableDictionary *presetData = [NSMutableDictionary dictionary];
        presetData[kPresetKeyName] = presetName;
        presetData[kPresetKeyEffectType] = effectType;
        presetData[kPresetKeyDateCreated] = [[NSDate date] description];

        if (settings) presetData[kPresetKeySettings] = settings;
        if (palette) presetData[kPresetKeyPalette] = palette;

        NSString *path = [self presetPathForName:presetName];
        if (path && [self savePresetToFile:presetData path:path]) {
            NSLog(@"EffectPresets: Saved preset '%@' to %@", presetName, path);
            [self reloadPresets];
        } else {
            NSLog(@"EffectPresets: Failed to save preset '%@'", presetName);
        }
    }];
}

- (BOOL)applyPreset:(NSString *)presetName toEffect:(NSInteger)effectId {
    if (!presetName || effectId < 0 || !_engineBridge) return NO;

    NSString *path = [self presetPathForName:presetName];
    NSDictionary *data = [self loadPresetFromFile:path];
    if (!data) {
        NSLog(@"EffectPresets: Cannot load preset '%@'", presetName);
        return NO;
    }

    // Verify the effect type matches
    NSDictionary *effectInfo = [_engineBridge getEffect:effectId];
    NSString *presetType = data[kPresetKeyEffectType];
    NSString *effectType = effectInfo[@"effectType"];

    if (presetType && effectType && ![presetType isEqualToString:effectType]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Type Mismatch";
        alert.informativeText = [NSString stringWithFormat:
            @"This preset is for '%@' but the selected effect is '%@'. Apply anyway?",
            presetType, effectType];
        [alert addButtonWithTitle:@"Apply"];
        [alert addButtonWithTitle:@"Cancel"];

        if ([alert runModal] != NSAlertFirstButtonReturn) {
            return NO;
        }
    }

    NSString *settings = data[kPresetKeySettings];
    NSString *palette = data[kPresetKeyPalette];

    BOOL success = YES;
    if (settings) {
        success = [_engineBridge setEffectSettings:effectId settings:settings] && success;
    }
    if (palette) {
        success = [_engineBridge setEffectPalette:effectId palette:palette] && success;
    }

    if (success) {
        NSLog(@"EffectPresets: Applied preset '%@' to effect %ld", presetName, (long)effectId);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"XLEffectPresetAppliedNotification"
                                                            object:self
                                                          userInfo:@{@"effectId": @(effectId)}];
    }
    return success;
}

- (NSArray<NSString *> *)presetNamesForEffectType:(NSString *)effectType {
    NSMutableArray *names = [NSMutableArray array];
    for (XLPresetNode *group in _rootNodes) {
        if (effectType && ![group.effectType isEqualToString:effectType]) continue;
        for (XLPresetNode *preset in group.children) {
            [names addObject:preset.name];
        }
    }
    return names;
}

- (BOOL)deletePreset:(NSString *)presetName {
    NSString *path = [self presetPathForName:presetName];
    if (!path) return NO;

    NSError *error = nil;
    BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    if (!removed) {
        NSLog(@"EffectPresets: Failed to delete '%@': %@", presetName, error.localizedDescription);
    }
    return removed;
}

- (BOOL)renamePreset:(NSString *)oldName toName:(NSString *)newName {
    NSString *oldPath = [self presetPathForName:oldName];
    if (!oldPath) return NO;

    NSDictionary *data = [self loadPresetFromFile:oldPath];
    if (!data) return NO;

    NSMutableDictionary *updated = [data mutableCopy];
    updated[kPresetKeyName] = newName;

    NSString *newPath = [self presetPathForName:newName];
    if (!newPath) return NO;

    if ([self savePresetToFile:updated path:newPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:oldPath error:nil];
        return YES;
    }
    return NO;
}

#pragma mark - Button Actions

- (void)savePresetAction:(id)sender {
    // If we have a current effect, save it
    if (_currentEffectId >= 0) {
        [self savePresetFromEffect:_currentEffectId];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Effect Selected";
        alert.informativeText = @"Select an effect in the sequencer to save it as a preset.";
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }
}

- (void)loadPresetAction:(id)sender {
    XLPresetNode *selected = [self selectedPresetNode];
    if (!selected || selected.isGroup) return;
    if (_currentEffectId < 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Effect Selected";
        alert.informativeText = @"Select an effect in the sequencer to apply a preset to it.";
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    [self applyPreset:selected.name toEffect:_currentEffectId];
}

- (void)deletePresetAction:(id)sender {
    XLPresetNode *selected = [self selectedPresetNode];
    if (!selected || selected.isGroup) return;

    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Delete Preset";
    confirm.informativeText = [NSString stringWithFormat:@"Delete the preset '%@'? This cannot be undone.", selected.name];
    [confirm addButtonWithTitle:@"Delete"];
    [confirm addButtonWithTitle:@"Cancel"];
    confirm.alertStyle = NSAlertStyleWarning;

    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            if ([self deletePreset:selected.name]) {
                [self reloadPresets];
            }
        }
    }];
}

- (void)renamePresetAction:(id)sender {
    XLPresetNode *selected = [self selectedPresetNode];
    if (!selected || selected.isGroup) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename Preset";
    alert.informativeText = @"Enter a new name for this preset:";
    [alert addButtonWithTitle:@"Rename"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    nameField.stringValue = selected.name;
    alert.accessoryView = nameField;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString *newName = nameField.stringValue;
            if (newName.length > 0 && ![newName isEqualToString:selected.name]) {
                if ([self renamePreset:selected.name toName:newName]) {
                    [self reloadPresets];
                }
            }
        }
    }];
}

#pragma mark - Helpers

- (XLPresetNode *)selectedPresetNode {
    NSInteger row = _outlineView.selectedRow;
    if (row < 0) return nil;
    return [_outlineView itemAtRow:row];
}

- (void)setCurrentEffectId:(NSInteger)effectId {
    _currentEffectId = effectId;
}

- (NSString *)selectedPresetName {
    XLPresetNode *selected = [self selectedPresetNode];
    if (!selected || selected.isGroup) return nil;
    return selected.name;
}

- (NSDictionary *)selectedPresetData {
    XLPresetNode *selected = [self selectedPresetNode];
    if (!selected || selected.isGroup) return nil;
    return selected.presetData;
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (!item) return _rootNodes.count;
    XLPresetNode *node = (XLPresetNode *)item;
    return node.isGroup ? node.children.count : 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (!item) return _rootNodes[index];
    XLPresetNode *node = (XLPresetNode *)item;
    return node.children[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    XLPresetNode *node = (XLPresetNode *)item;
    return node.isGroup;
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    XLPresetNode *node = (XLPresetNode *)item;

    NSString *identifier = tableColumn.identifier;
    NSTableCellView *cellView = [outlineView makeViewWithIdentifier:identifier owner:self];

    if (!cellView) {
        cellView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 22)];
        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.frame = cellView.bounds;
        textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        cellView.textField = textField;
        [cellView addSubview:textField];
        cellView.identifier = identifier;
    }

    if ([identifier isEqualToString:@"name"]) {
        cellView.textField.stringValue = node.name ?: @"";
        if (node.isGroup) {
            cellView.textField.font = [NSFont boldSystemFontOfSize:12];
        } else {
            cellView.textField.font = [NSFont systemFontOfSize:12];
        }
    } else if ([identifier isEqualToString:@"type"]) {
        cellView.textField.stringValue = node.isGroup ? @"" : (node.effectType ?: @"");
        cellView.textField.font = [NSFont systemFontOfSize:11];
        cellView.textField.textColor = [NSColor secondaryLabelColor];
    }

    return cellView;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    XLPresetNode *selected = [self selectedPresetNode];
    BOOL isPreset = (selected && !selected.isGroup);
    _loadButton.enabled = isPreset;
    _deleteButton.enabled = isPreset;
    _renameButton.enabled = isPreset;
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    NSString *frameString = NSStringFromRect(self.window.frame);
    [[NSUserDefaults standardUserDefaults] setObject:frameString forKey:kWindowFrameKey];
}

@end
