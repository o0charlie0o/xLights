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
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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
@property (nonatomic, strong) NSWindow *rgbEffectsSheet;
@property (nonatomic, strong) XLRGBEffectsImportController *rgbEffectsController;

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

    // LOR S5 preview files
    UTType *lorprevType = [UTType typeWithFilenameExtension:@"lorprev"];
    if (lorprevType) [types addObject:lorprevType];

    // XML files (for Vixen, LOR S5 LORPreviews.xml, etc.)
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
        case XLModelImportTypeRGBEffects:
            [self showRGBEffectsSelectionForFile:filePath];
            break;
        case XLModelImportTypeLOR:
            [self importLORS5File:filePath];
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

- (void)importLORS5File:(NSString *)filePath {
    // Get available previews from the LOR S5 file
    NSArray<NSString *> *previewNames = [_engineBridge getLORS5PreviewNames:filePath];

    if (!previewNames || previewNames.count == 0) {
        [self showImportError:@"No previews found in LOR S5 file."];
        return;
    }

    if (previewNames.count == 1) {
        // Single preview - import directly
        [self performLORS5Import:filePath previewName:previewNames[0]];
    } else {
        // Multiple previews - show selection
        [self showLORS5PreviewSelection:previewNames forFile:filePath];
    }
}

- (void)showLORS5PreviewSelection:(NSArray<NSString *> *)previewNames forFile:(NSString *)filePath {
    if (!_parentWindow) {
        [self performLORS5Import:filePath previewName:previewNames[0]];
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Select LOR S5 Preview";
    alert.informativeText = @"Choose which preview to import models from:";

    // Add a popup button as accessory view
    NSPopUpButton *previewPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 300, 28) pullsDown:NO];
    for (NSString *name in previewNames) {
        [previewPopup addItemWithTitle:name];
    }
    alert.accessoryView = previewPopup;

    [alert addButtonWithTitle:@"Import"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:_parentWindow completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString *selectedPreview = previewPopup.titleOfSelectedItem;
            [self performLORS5Import:filePath previewName:selectedPreview];
        } else {
            if (self.completion) {
                self.completion(NO, nil);
            }
        }
    }];
}

- (void)performLORS5Import:(NSString *)filePath previewName:(NSString *)previewName {
    NSString *layoutGroup = @"Default";

    NSArray<NSString *> *importedNames = [_engineBridge importModelsFromLORS5File:filePath
                                                                     previewName:previewName
                                                                     layoutGroup:layoutGroup];

    if (importedNames.count > 0) {
        if (_completion) {
            _completion(YES, importedNames);
        }
    } else {
        [self showImportError:@"No models could be imported from the LOR S5 file."];
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

#pragma mark - RGB Effects Import

- (void)showRGBEffectsImportForWindow:(NSWindow *)parentWindow
                           completion:(XLModelImportCompletion)completion {
    _parentWindow = parentWindow;
    _completion = completion;

    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    openPanel.title = @"Import Models from RGB Effects";
    openPanel.message = @"Select an xlights_rgbeffects.xml file to import models from";
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = NO;
    openPanel.allowsMultipleSelection = NO;

    UTType *xmlType = [UTType typeWithIdentifier:@"public.xml"];
    if (xmlType) {
        openPanel.allowedContentTypes = @[xmlType];
    }

    [openPanel beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && openPanel.URL) {
            [self showRGBEffectsSelectionForFile:openPanel.URL.path];
        } else {
            if (self.completion) {
                self.completion(NO, nil);
            }
        }
    }];
}

- (void)showRGBEffectsSelectionForFile:(NSString *)filePath {
    NSDictionary *parsedData = [_engineBridge parseRGBEffectsFile:filePath];
    NSArray *models = parsedData[@"models"];

    if (!models || models.count == 0) {
        [self showImportError:@"No models found in the RGB Effects file."];
        return;
    }

    _rgbEffectsController = [[XLRGBEffectsImportController alloc] initWithParsedData:parsedData];

    _rgbEffectsSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    _rgbEffectsSheet.title = @"Import Models from RGB Effects";

    NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 500)];

    NSView *controllerView = _rgbEffectsController.view;
    controllerView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:controllerView];

    // Button bar
    NSView *buttonBar = [[NSView alloc] initWithFrame:NSZeroRect];
    buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:buttonBar];

    NSButton *cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(rgbEffectsCancelClicked:)];
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    cancelButton.keyEquivalent = @"\033";
    [buttonBar addSubview:cancelButton];

    NSButton *importButton = [NSButton buttonWithTitle:@"Import Selected" target:self action:@selector(rgbEffectsImportClicked:)];
    importButton.translatesAutoresizingMaskIntoConstraints = NO;
    importButton.keyEquivalent = @"\r";
    [buttonBar addSubview:importButton];

    [NSLayoutConstraint activateConstraints:@[
        [controllerView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [controllerView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [controllerView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [controllerView.bottomAnchor constraintEqualToAnchor:buttonBar.topAnchor],

        [buttonBar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [buttonBar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [buttonBar.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [buttonBar.heightAnchor constraintEqualToConstant:50],

        [cancelButton.leadingAnchor constraintEqualToAnchor:buttonBar.leadingAnchor constant:20],
        [cancelButton.centerYAnchor constraintEqualToAnchor:buttonBar.centerYAnchor],

        [importButton.trailingAnchor constraintEqualToAnchor:buttonBar.trailingAnchor constant:-20],
        [importButton.centerYAnchor constraintEqualToAnchor:buttonBar.centerYAnchor],
    ]];

    _rgbEffectsSheet.contentView = contentView;

    // Store file path for import action
    objc_setAssociatedObject(_rgbEffectsSheet, "filePath", filePath, OBJC_ASSOCIATION_COPY);

    [_parentWindow beginSheet:_rgbEffectsSheet completionHandler:nil];
}

- (void)rgbEffectsCancelClicked:(id)sender {
    [_parentWindow endSheet:_rgbEffectsSheet];
    _rgbEffectsSheet = nil;
    _rgbEffectsController = nil;
    if (_completion) {
        _completion(NO, nil);
    }
}

- (void)rgbEffectsImportClicked:(id)sender {
    NSString *filePath = objc_getAssociatedObject(_rgbEffectsSheet, "filePath");
    NSArray<NSString *> *selectedNames = [_rgbEffectsController selectedModelNames];
    NSString *targetLayoutGroup = [_rgbEffectsController targetLayoutGroup];

    if (selectedNames.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Models Selected";
        alert.informativeText = @"Please select at least one model or model group to import.";
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:_rgbEffectsSheet completionHandler:nil];
        return;
    }

    [_parentWindow endSheet:_rgbEffectsSheet];
    _rgbEffectsSheet = nil;
    _rgbEffectsController = nil;

    NSArray<NSString *> *importedNames = [_engineBridge importModelsFromRGBEffectsFile:filePath
                                                                           modelNames:selectedNames
                                                                    targetLayoutGroup:targetLayoutGroup];

    if (_completion) {
        _completion(importedNames.count > 0, importedNames);
    }
}

#pragma mark - Class Methods

+ (XLModelImportType)importTypeForFile:(NSString *)filePath {
    NSString *extension = [[filePath pathExtension] lowercaseString];
    NSString *filename = [[filePath lastPathComponent] lowercaseString];

    // Check for xlights_rgbeffects.xml specifically
    if ([filename isEqualToString:@"xlights_rgbeffects.xml"]) {
        return XLModelImportTypeRGBEffects;
    }

    if ([extension isEqualToString:@"xmodel"]) {
        return XLModelImportTypeXModel;
    } else if ([extension isEqualToString:@"xlights"]) {
        // Check if it's a layout file or sequence file based on content
        // For now, treat as sequence
        return XLModelImportTypeSequence;
    } else if ([extension isEqualToString:@"lor"] || [extension isEqualToString:@"lorprev"]) {
        return XLModelImportTypeLOR;
    } else if ([extension isEqualToString:@"xml"]) {
        // Check for LOR S5 preview files (LORPreviews.xml or files with PreviewClass root)
        if ([filename hasPrefix:@"lorpreview"]) {
            return XLModelImportTypeLOR;
        }
        // Could be Vixen, rgbeffects, or other XML format
        // Try to detect rgbeffects by checking content
        NSData *xmlData = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:nil];
        if (xmlData) {
            NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:nil];
            if (xmlDoc) {
                NSXMLElement *root = [xmlDoc rootElement];
                if (root) {
                    NSString *rootName = [root name];
                    // LOR S5 preview files have <PreviewClass> root or contain <PreviewClass> children
                    if ([rootName isEqualToString:@"PreviewClass"]) {
                        return XLModelImportTypeLOR;
                    }
                    for (NSXMLElement *child in [root children]) {
                        if ([[child name] isEqualToString:@"PreviewClass"]) {
                            return XLModelImportTypeLOR;
                        }
                    }

                    // rgbeffects.xml has <xrgb> root with <models> and <modelGroups> children
                    NSArray *modelsNodes = [root nodesForXPath:@"models" error:nil];
                    NSArray *modelGroupsNodes = [root nodesForXPath:@"modelGroups" error:nil];
                    if (modelsNodes.count > 0 || modelGroupsNodes.count > 0) {
                        return XLModelImportTypeRGBEffects;
                    }
                }
            }
        }
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
        case XLModelImportTypeRGBEffects:
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

#pragma mark - XLRGBEffectsImportController

/// Item data for the outline view tree
@interface XLRGBEffectsTreeItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, assign) NSInteger channels;
@property (nonatomic, copy) NSString *layoutGroup;
@property (nonatomic, assign) BOOL isModelGroup;
@property (nonatomic, assign) BOOL isLayoutGroupHeader;
@property (nonatomic, assign) BOOL selected;
@property (nonatomic, strong) NSMutableArray<XLRGBEffectsTreeItem *> *children;
@end

@implementation XLRGBEffectsTreeItem
- (instancetype)init {
    self = [super init];
    if (self) {
        _children = [NSMutableArray array];
        _selected = NO;
        _isLayoutGroupHeader = NO;
        _isModelGroup = NO;
    }
    return self;
}
@end

@interface XLRGBEffectsImportController () <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSMutableArray<XLRGBEffectsTreeItem *> *rootItems;
@property (nonatomic, strong) NSPopUpButton *targetLayoutGroupPopup;
@property (nonatomic, strong) NSButton *selectAllButton;
@property (nonatomic, strong) NSButton *selectNoneButton;
@property (nonatomic, strong) NSButton *selectModelsOnlyButton;
@property (nonatomic, strong) NSButton *selectGroupsOnlyButton;

@end

@implementation XLRGBEffectsImportController

- (instancetype)initWithParsedData:(NSDictionary *)parsedData {
    self = [super init];
    if (self) {
        _parsedData = [parsedData copy];
        _rootItems = [NSMutableArray array];
        [self buildTree];
    }
    return self;
}

- (void)buildTree {
    NSArray<NSString *> *layoutGroups = _parsedData[@"layoutGroups"] ?: @[];
    NSArray<NSDictionary *> *models = _parsedData[@"models"] ?: @[];

    // Build a layout group -> items mapping
    for (NSString *lgName in layoutGroups) {
        XLRGBEffectsTreeItem *lgItem = [[XLRGBEffectsTreeItem alloc] init];
        lgItem.name = lgName;
        lgItem.isLayoutGroupHeader = YES;

        // Add model groups for this layout group
        for (NSDictionary *model in models) {
            if (![model[@"isModelGroup"] boolValue]) continue;
            NSString *modelLG = model[@"layoutGroup"] ?: @"Default";
            if (![modelLG isEqualToString:lgName]) continue;

            XLRGBEffectsTreeItem *item = [[XLRGBEffectsTreeItem alloc] init];
            item.name = model[@"name"];
            item.type = @"Model Group";
            item.channels = 0;
            item.layoutGroup = modelLG;
            item.isModelGroup = YES;
            item.selected = YES;
            [lgItem.children addObject:item];
        }

        // Add regular models for this layout group
        for (NSDictionary *model in models) {
            if ([model[@"isModelGroup"] boolValue]) continue;
            NSString *modelLG = model[@"layoutGroup"] ?: @"Default";
            if (![modelLG isEqualToString:lgName]) continue;

            XLRGBEffectsTreeItem *item = [[XLRGBEffectsTreeItem alloc] init];
            item.name = model[@"name"];
            item.type = model[@"type"] ?: @"Unknown";
            item.channels = [model[@"channels"] integerValue];
            item.layoutGroup = modelLG;
            item.isModelGroup = NO;
            item.selected = YES;
            [lgItem.children addObject:item];
        }

        // Only add layout groups that have items
        if (lgItem.children.count > 0) {
            [_rootItems addObject:lgItem];
        }
    }
}

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 450)];

    // Info label
    NSTextField *infoLabel = [NSTextField labelWithString:@"Select models and model groups to import:"];
    infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    infoLabel.font = [NSFont boldSystemFontOfSize:13];
    [view addSubview:infoLabel];

    // Target layout group selector
    NSTextField *targetLabel = [NSTextField labelWithString:@"Import into layout group:"];
    targetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:targetLabel];

    _targetLayoutGroupPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _targetLayoutGroupPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_targetLayoutGroupPopup addItemWithTitle:@"Keep Original"];
    [_targetLayoutGroupPopup addItemWithTitle:@"Default"];
    NSArray<NSString *> *layoutGroups = _parsedData[@"layoutGroups"] ?: @[];
    for (NSString *lg in layoutGroups) {
        if ([lg isEqualToString:@"Default"]) continue;
        [_targetLayoutGroupPopup addItemWithTitle:lg];
    }
    [view addSubview:_targetLayoutGroupPopup];

    // Outline view (tree)
    _outlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
    _outlineView.usesAlternatingRowBackgroundColors = YES;
    _outlineView.rowHeight = 22;
    _outlineView.dataSource = self;
    _outlineView.delegate = self;
    _outlineView.autoresizesOutlineColumn = YES;

    // Checkbox column
    NSTableColumn *checkColumn = [[NSTableColumn alloc] initWithIdentifier:@"selected"];
    checkColumn.title = @"";
    checkColumn.width = 30;
    checkColumn.minWidth = 30;
    checkColumn.maxWidth = 30;
    [_outlineView addTableColumn:checkColumn];

    // Name column
    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Name";
    nameColumn.width = 250;
    [_outlineView addTableColumn:nameColumn];

    // Type column
    NSTableColumn *typeColumn = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeColumn.title = @"Type";
    typeColumn.width = 120;
    [_outlineView addTableColumn:typeColumn];

    // Channels column
    NSTableColumn *channelsColumn = [[NSTableColumn alloc] initWithIdentifier:@"channels"];
    channelsColumn.title = @"Channels";
    channelsColumn.width = 80;
    [_outlineView addTableColumn:channelsColumn];

    [_outlineView setOutlineTableColumn:nameColumn];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.documentView = _outlineView;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    [view addSubview:scrollView];

    // Action buttons bar
    NSStackView *actionBar = [NSStackView stackViewWithViews:@[]];
    actionBar.translatesAutoresizingMaskIntoConstraints = NO;
    actionBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actionBar.spacing = 8;
    [view addSubview:actionBar];

    _selectAllButton = [NSButton buttonWithTitle:@"Select All" target:self action:@selector(selectAllClicked:)];
    [actionBar addArrangedSubview:_selectAllButton];

    _selectNoneButton = [NSButton buttonWithTitle:@"Select None" target:self action:@selector(selectNoneClicked:)];
    [actionBar addArrangedSubview:_selectNoneButton];

    _selectModelsOnlyButton = [NSButton buttonWithTitle:@"Models Only" target:self action:@selector(selectModelsOnlyClicked:)];
    [actionBar addArrangedSubview:_selectModelsOnlyButton];

    _selectGroupsOnlyButton = [NSButton buttonWithTitle:@"Groups Only" target:self action:@selector(selectGroupsOnlyClicked:)];
    [actionBar addArrangedSubview:_selectGroupsOnlyButton];

    [NSLayoutConstraint activateConstraints:@[
        [infoLabel.topAnchor constraintEqualToAnchor:view.topAnchor constant:16],
        [infoLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:16],

        [targetLabel.topAnchor constraintEqualToAnchor:infoLabel.bottomAnchor constant:8],
        [targetLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:16],
        [targetLabel.centerYAnchor constraintEqualToAnchor:_targetLayoutGroupPopup.centerYAnchor],

        [_targetLayoutGroupPopup.leadingAnchor constraintEqualToAnchor:targetLabel.trailingAnchor constant:8],
        [_targetLayoutGroupPopup.topAnchor constraintEqualToAnchor:infoLabel.bottomAnchor constant:4],
        [_targetLayoutGroupPopup.widthAnchor constraintGreaterThanOrEqualToConstant:180],

        [scrollView.topAnchor constraintEqualToAnchor:_targetLayoutGroupPopup.bottomAnchor constant:8],
        [scrollView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:16],
        [scrollView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-16],
        [scrollView.bottomAnchor constraintEqualToAnchor:actionBar.topAnchor constant:-8],

        [actionBar.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:16],
        [actionBar.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-8],
    ]];

    self.view = view;

    // Expand all layout groups by default
    for (XLRGBEffectsTreeItem *item in _rootItems) {
        [_outlineView expandItem:item];
    }
}

#pragma mark - Selection Actions

- (void)selectAllClicked:(id)sender {
    [self setAllItemsSelected:YES];
    [_outlineView reloadData];
}

- (void)selectNoneClicked:(id)sender {
    [self setAllItemsSelected:NO];
    [_outlineView reloadData];
}

- (void)selectModelsOnlyClicked:(id)sender {
    for (XLRGBEffectsTreeItem *lgItem in _rootItems) {
        for (XLRGBEffectsTreeItem *child in lgItem.children) {
            child.selected = !child.isModelGroup;
        }
    }
    [_outlineView reloadData];
}

- (void)selectGroupsOnlyClicked:(id)sender {
    for (XLRGBEffectsTreeItem *lgItem in _rootItems) {
        for (XLRGBEffectsTreeItem *child in lgItem.children) {
            child.selected = child.isModelGroup;
        }
    }
    [_outlineView reloadData];
}

- (void)setAllItemsSelected:(BOOL)selected {
    for (XLRGBEffectsTreeItem *lgItem in _rootItems) {
        for (XLRGBEffectsTreeItem *child in lgItem.children) {
            child.selected = selected;
        }
    }
}

#pragma mark - Public API

- (NSArray<NSString *> *)selectedModelNames {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (XLRGBEffectsTreeItem *lgItem in _rootItems) {
        for (XLRGBEffectsTreeItem *child in lgItem.children) {
            if (child.selected && child.name) {
                [names addObject:child.name];
            }
        }
    }
    return names;
}

- (NSString *)targetLayoutGroup {
    NSString *selected = [_targetLayoutGroupPopup titleOfSelectedItem];
    if ([selected isEqualToString:@"Keep Original"]) {
        return nil;
    }
    return selected;
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (!item) {
        return (NSInteger)_rootItems.count;
    }
    XLRGBEffectsTreeItem *treeItem = (XLRGBEffectsTreeItem *)item;
    return (NSInteger)treeItem.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (!item) {
        return _rootItems[(NSUInteger)index];
    }
    XLRGBEffectsTreeItem *treeItem = (XLRGBEffectsTreeItem *)item;
    return treeItem.children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    XLRGBEffectsTreeItem *treeItem = (XLRGBEffectsTreeItem *)item;
    return treeItem.children.count > 0;
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    XLRGBEffectsTreeItem *treeItem = (XLRGBEffectsTreeItem *)item;
    NSString *identifier = tableColumn.identifier;

    if ([identifier isEqualToString:@"selected"]) {
        if (treeItem.isLayoutGroupHeader) {
            // No checkbox for layout group headers
            return nil;
        }
        NSButton *checkbox = [outlineView makeViewWithIdentifier:@"rgbCheckbox" owner:self];
        if (!checkbox) {
            checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(itemCheckboxClicked:)];
            checkbox.identifier = @"rgbCheckbox";
        }
        checkbox.state = treeItem.selected ? NSControlStateValueOn : NSControlStateValueOff;
        objc_setAssociatedObject(checkbox, "treeItem", treeItem, OBJC_ASSOCIATION_ASSIGN);
        return checkbox;
    }

    NSTableCellView *cell = [outlineView makeViewWithIdentifier:[NSString stringWithFormat:@"rgb_%@", identifier] owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = [NSString stringWithFormat:@"rgb_%@", identifier];

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
        if (treeItem.isLayoutGroupHeader) {
            cell.textField.stringValue = [NSString stringWithFormat:@"[%@]", treeItem.name];
            cell.textField.font = [NSFont boldSystemFontOfSize:12];
        } else if (treeItem.isModelGroup) {
            cell.textField.stringValue = [NSString stringWithFormat:@"%@ (Group)", treeItem.name];
            cell.textField.font = [NSFont systemFontOfSize:12];
        } else {
            cell.textField.stringValue = treeItem.name ?: @"";
            cell.textField.font = [NSFont systemFontOfSize:12];
        }
    } else if ([identifier isEqualToString:@"type"]) {
        cell.textField.stringValue = treeItem.isLayoutGroupHeader ? @"" : (treeItem.type ?: @"");
    } else if ([identifier isEqualToString:@"channels"]) {
        if (treeItem.isLayoutGroupHeader || treeItem.isModelGroup) {
            cell.textField.stringValue = @"";
        } else {
            cell.textField.stringValue = [NSString stringWithFormat:@"%ld", (long)treeItem.channels];
        }
    }

    return cell;
}

- (void)itemCheckboxClicked:(NSButton *)sender {
    XLRGBEffectsTreeItem *treeItem = objc_getAssociatedObject(sender, "treeItem");
    if (treeItem) {
        treeItem.selected = (sender.state == NSControlStateValueOn);
    }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item {
    XLRGBEffectsTreeItem *treeItem = (XLRGBEffectsTreeItem *)item;
    return treeItem.isLayoutGroupHeader;
}

@end
