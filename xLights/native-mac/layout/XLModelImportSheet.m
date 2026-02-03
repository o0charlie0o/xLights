/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLModelImportSheet.h"
#import "../XLEngineBridge.h"
#import <objc/runtime.h>

// File type constants - using C strings to avoid heap issues
static const char * const kXModelExtension = "xmodel";
static const char * const kXLightsExtension = "xlights";
static const char * const kLORExtension = "lor";
static const char * const kVixenExtension = "xml";

#pragma mark - XLModelImportSheet

@interface XLModelImportSheet ()

@property (nonatomic, weak) NSWindow *parentWindow;
@property (nonatomic, copy) XLModelImportCompletion completion;
@property (nonatomic, strong) NSWindow *previewSheet;
@property (nonatomic, strong) XLModelImportPreviewController *previewController;

@end

@implementation XLModelImportSheet

- (void)showAsSheetForWindow:(NSWindow *)parentWindow
                  completion:(XLModelImportCompletion)completion {
    _parentWindow = parentWindow;
    _completion = completion;

    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    openPanel.title = @"Import Model";
    openPanel.message = @"Select a model file to import";
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = NO;
    openPanel.allowsMultipleSelection = NO;
    openPanel.allowedContentTypes = [self allowedContentTypes];

    [openPanel beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && openPanel.URL) {
            [self processImportFile:openPanel.URL.path];
        } else {
            if (self.completion) {
                self.completion(NO, nil);
            }
        }
    }];
}

- (NSArray<UTType *> *)allowedContentTypes {
    // Create content types for our model formats
    NSMutableArray<UTType *> *types = [NSMutableArray array];

    // xModel files
    UTType *xmodelType = [UTType typeWithFilenameExtension:@"xmodel"];
    if (xmodelType) [types addObject:xmodelType];

    // xLights sequence files
    UTType *xlightsType = [UTType typeWithFilenameExtension:@"xlights"];
    if (xlightsType) [types addObject:xlightsType];

    // XML files (for Vixen, etc.)
    UTType *xmlType = [UTType typeWithIdentifier:@"public.xml"];
    if (xmlType) [types addObject:xmlType];

    return types;
}

- (void)importFromFile:(NSString *)filePath
            completion:(XLModelImportCompletion)completion {
    _completion = completion;
    [self processImportFile:filePath];
}

- (void)processImportFile:(NSString *)filePath {
    XLModelImportType importType = [XLModelImportSheet importTypeForFile:filePath];

    switch (importType) {
        case XLModelImportTypeXModel:
            [self importXModelFile:filePath];
            break;
        case XLModelImportTypeSequence:
            [self showModelSelectionForFile:filePath];
            break;
        case XLModelImportTypeLayout:
            [self showModelSelectionForFile:filePath];
            break;
        default:
            [self showImportError:@"Unsupported file format"];
            break;
    }
}

#pragma mark - Import Methods

- (void)importXModelFile:(NSString *)filePath {
    // For .xmodel files, import directly
    BOOL success = [_engineBridge importModelFromFile:filePath];

    if (success) {
        // Extract model name from filename
        NSString *filename = [[filePath lastPathComponent] stringByDeletingPathExtension];
        if (_completion) {
            _completion(YES, @[filename]);
        }
    } else {
        [self showImportError:@"Failed to import model file"];
    }
}

- (void)showModelSelectionForFile:(NSString *)filePath {
    // For sequence/layout files, show selection UI
    NSArray<NSDictionary *> *models = [_engineBridge getModelsInFile:filePath];

    if (models.count == 0) {
        [self showImportError:@"No models found in file"];
        return;
    }

    if (models.count == 1) {
        // Single model - import directly
        NSString *modelName = models[0][@"name"];
        BOOL success = [_engineBridge importModelFromFile:filePath modelName:modelName];

        if (_completion) {
            _completion(success, success ? @[modelName] : nil);
        }
        return;
    }

    // Multiple models - show selection UI
    [self showModelPreviewSheet:models forFile:filePath];
}

- (void)showModelPreviewSheet:(NSArray<NSDictionary *> *)models forFile:(NSString *)filePath {
    _previewController = [[XLModelImportPreviewController alloc] initWithModels:models];

    _previewSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 400)
                                                styleMask:NSWindowStyleMaskTitled
                                                  backing:NSBackingStoreBuffered
                                                    defer:YES];
    _previewSheet.title = @"Select Models to Import";

    // Build the preview UI
    NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 400)];

    // Add preview controller's view
    NSView *previewView = _previewController.view;
    previewView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:previewView];

    // Button bar
    NSView *buttonBar = [[NSView alloc] initWithFrame:NSZeroRect];
    buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:buttonBar];

    NSButton *cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(previewCancelClicked:)];
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    cancelButton.keyEquivalent = @"\033";
    [buttonBar addSubview:cancelButton];

    NSButton *importButton = [NSButton buttonWithTitle:@"Import Selected" target:self action:@selector(previewImportClicked:)];
    importButton.translatesAutoresizingMaskIntoConstraints = NO;
    importButton.keyEquivalent = @"\r";
    [buttonBar addSubview:importButton];

    [NSLayoutConstraint activateConstraints:@[
        [previewView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [previewView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [previewView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [previewView.bottomAnchor constraintEqualToAnchor:buttonBar.topAnchor],

        [buttonBar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [buttonBar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [buttonBar.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [buttonBar.heightAnchor constraintEqualToConstant:50],

        [cancelButton.leadingAnchor constraintEqualToAnchor:buttonBar.leadingAnchor constant:20],
        [cancelButton.centerYAnchor constraintEqualToAnchor:buttonBar.centerYAnchor],

        [importButton.trailingAnchor constraintEqualToAnchor:buttonBar.trailingAnchor constant:-20],
        [importButton.centerYAnchor constraintEqualToAnchor:buttonBar.centerYAnchor],
    ]];

    _previewSheet.contentView = contentView;

    // Store file path for import action
    objc_setAssociatedObject(_previewSheet, "filePath", filePath, OBJC_ASSOCIATION_COPY);

    [_parentWindow beginSheet:_previewSheet completionHandler:nil];
}

- (void)previewCancelClicked:(id)sender {
    [_parentWindow endSheet:_previewSheet];
    if (_completion) {
        _completion(NO, nil);
    }
}

- (void)previewImportClicked:(id)sender {
    NSString *filePath = objc_getAssociatedObject(_previewSheet, "filePath");
    NSArray<NSString *> *selectedNames = [_previewController selectedModelNames];

    if (selectedNames.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Models Selected";
        alert.informativeText = @"Please select at least one model to import.";
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:_previewSheet completionHandler:nil];
        return;
    }

    [_parentWindow endSheet:_previewSheet];

    // Import selected models
    NSMutableArray<NSString *> *importedNames = [NSMutableArray array];
    for (NSString *name in selectedNames) {
        BOOL success = [_engineBridge importModelFromFile:filePath modelName:name];
        if (success) {
            [importedNames addObject:name];
        }
    }

    if (_completion) {
        _completion(importedNames.count > 0, importedNames);
    }
}

#pragma mark - Error Handling

- (void)showImportError:(NSString *)message {
    if (!_parentWindow) {
        if (_completion) {
            _completion(NO, nil);
        }
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Import Error";
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"OK"];

    [alert beginSheetModalForWindow:_parentWindow completionHandler:^(NSModalResponse returnCode) {
        if (self.completion) {
            self.completion(NO, nil);
        }
    }];
}

#pragma mark - Class Methods

+ (XLModelImportType)importTypeForFile:(NSString *)filePath {
    NSString *extension = [[filePath pathExtension] lowercaseString];

    if ([extension isEqualToString:@"xmodel"]) {
        return XLModelImportTypeXModel;
    } else if ([extension isEqualToString:@"xlights"]) {
        // Check if it's a layout file or sequence file based on content
        // For now, treat as sequence
        return XLModelImportTypeSequence;
    } else if ([extension isEqualToString:@"lor"]) {
        return XLModelImportTypeLOR;
    } else if ([extension isEqualToString:@"xml"]) {
        // Could be Vixen or other XML format
        return XLModelImportTypeVixen;
    }

    return XLModelImportTypeUnknown;
}

+ (NSString *)fileExtensionForImportType:(XLModelImportType)importType {
    switch (importType) {
        case XLModelImportTypeXModel:
            return @"xmodel";
        case XLModelImportTypeSequence:
            return @"xlights";
        case XLModelImportTypeLayout:
            return @"xlights";
        case XLModelImportTypeLOR:
            return @"lor";
        case XLModelImportTypeVixen:
            return @"xml";
        default:
            return @"";
    }
}

@end

#pragma mark - XLModelImportPreviewController

@interface XLModelImportPreviewController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSButton *selectAllButton;
@property (nonatomic, strong) NSButton *selectNoneButton;

@end

@implementation XLModelImportPreviewController

- (instancetype)initWithModels:(NSArray<NSDictionary *> *)models {
    self = [super init];
    if (self) {
        _availableModels = [models copy];
        // Select all by default
        _selectedModelIndices = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, models.count)];
    }
    return self;
}

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 350)];

    // Info label
    NSTextField *infoLabel = [NSTextField labelWithString:@"Select models to import:"];
    infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    infoLabel.font = [NSFont boldSystemFontOfSize:13];
    [view addSubview:infoLabel];

    // Table view
    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.allowsMultipleSelection = YES;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.rowHeight = 24;
    _tableView.dataSource = self;
    _tableView.delegate = self;

    // Checkbox column
    NSTableColumn *checkColumn = [[NSTableColumn alloc] initWithIdentifier:@"selected"];
    checkColumn.title = @"";
    checkColumn.width = 30;
    checkColumn.minWidth = 30;
    checkColumn.maxWidth = 30;
    [_tableView addTableColumn:checkColumn];

    // Name column
    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Model Name";
    nameColumn.width = 200;
    [_tableView addTableColumn:nameColumn];

    // Type column
    NSTableColumn *typeColumn = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeColumn.title = @"Type";
    typeColumn.width = 100;
    [_tableView addTableColumn:typeColumn];

    // Channels column
    NSTableColumn *channelsColumn = [[NSTableColumn alloc] initWithIdentifier:@"channels"];
    channelsColumn.title = @"Channels";
    channelsColumn.width = 80;
    [_tableView addTableColumn:channelsColumn];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.documentView = _tableView;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    [view addSubview:scrollView];

    // Select All / Select None buttons
    _selectAllButton = [NSButton buttonWithTitle:@"Select All" target:self action:@selector(selectAllClicked:)];
    _selectAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:_selectAllButton];

    _selectNoneButton = [NSButton buttonWithTitle:@"Select None" target:self action:@selector(selectNoneClicked:)];
    _selectNoneButton.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:_selectNoneButton];

    [NSLayoutConstraint activateConstraints:@[
        [infoLabel.topAnchor constraintEqualToAnchor:view.topAnchor constant:16],
        [infoLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:16],

        [scrollView.topAnchor constraintEqualToAnchor:infoLabel.bottomAnchor constant:8],
        [scrollView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:16],
        [scrollView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-16],
        [scrollView.bottomAnchor constraintEqualToAnchor:_selectAllButton.topAnchor constant:-8],

        [_selectAllButton.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:16],
        [_selectAllButton.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-8],

        [_selectNoneButton.leadingAnchor constraintEqualToAnchor:_selectAllButton.trailingAnchor constant:8],
        [_selectNoneButton.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-8],
    ]];

    self.view = view;
}

- (void)selectAllClicked:(id)sender {
    _selectedModelIndices = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _availableModels.count)];
    [_tableView reloadData];
}

- (void)selectNoneClicked:(id)sender {
    _selectedModelIndices = [NSIndexSet indexSet];
    [_tableView reloadData];
}

- (NSArray<NSString *> *)selectedModelNames {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    [_selectedModelIndices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if (idx < self.availableModels.count) {
            NSString *name = self.availableModels[idx][@"name"];
            if (name) {
                [names addObject:name];
            }
        }
    }];
    return names;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_availableModels.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *identifier = tableColumn.identifier;

    if (row < 0 || row >= (NSInteger)_availableModels.count) {
        return nil;
    }

    NSDictionary *model = _availableModels[(NSUInteger)row];

    if ([identifier isEqualToString:@"selected"]) {
        NSButton *checkbox = [tableView makeViewWithIdentifier:identifier owner:self];
        if (!checkbox) {
            checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkboxClicked:)];
            checkbox.identifier = identifier;
        }
        checkbox.tag = row;
        checkbox.state = [_selectedModelIndices containsIndex:(NSUInteger)row] ? NSControlStateValueOn : NSControlStateValueOff;
        return checkbox;
    }

    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = identifier;

        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:textField];
        cell.textField = textField;

        [NSLayoutConstraint activateConstraints:@[
            [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
            [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    if ([identifier isEqualToString:@"name"]) {
        cell.textField.stringValue = model[@"name"] ?: @"";
    } else if ([identifier isEqualToString:@"type"]) {
        cell.textField.stringValue = model[@"type"] ?: @"";
    } else if ([identifier isEqualToString:@"channels"]) {
        NSNumber *channels = model[@"channels"];
        cell.textField.stringValue = channels ? [channels stringValue] : @"";
    }

    return cell;
}

- (void)checkboxClicked:(NSButton *)sender {
    NSInteger row = sender.tag;
    if (row < 0 || row >= (NSInteger)_availableModels.count) return;

    NSMutableIndexSet *newSelection = [_selectedModelIndices mutableCopy];
    if (sender.state == NSControlStateValueOn) {
        [newSelection addIndex:(NSUInteger)row];
    } else {
        [newSelection removeIndex:(NSUInteger)row];
    }
    _selectedModelIndices = newSelection;
}

@end
