/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLModelFaceDialogController.h"
#import "../XLEngineBridge.h"
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Face type constants
typedef NS_ENUM(NSInteger, XLFaceType) {
    XLFaceTypeNodeRange = 0,
    XLFaceTypeMatrix = 1,
};

// Node range row definitions
// Row labels for the phoneme grid (node range mode)
static NSArray<NSString *> *NodeRangeRowLabels(void) {
    return @[
        @"Face Outline",
        @"Face Outline 2",
        @"Mouth - AI",
        @"Mouth - E",
        @"Mouth - etc",
        @"Mouth - FV",
        @"Mouth - L",
        @"Mouth - MBP",
        @"Mouth - O",
        @"Mouth - rest",
        @"Mouth - U",
        @"Mouth - WQ",
        @"Eyes - Open",
        @"Eyes - Open 2",
        @"Eyes - Open 3",
        @"Eyes - Closed",
        @"Eyes - Closed 2",
        @"Eyes - Closed 3",
    ];
}

// Matrix row labels (phonemes for image mapping)
static NSArray<NSString *> *MatrixRowLabels(void) {
    return @[
        @"Mouth - AI",
        @"Mouth - E",
        @"Mouth - etc",
        @"Mouth - FV",
        @"Mouth - L",
        @"Mouth - MBP",
        @"Mouth - O",
        @"Mouth - rest",
        @"Mouth - U",
        @"Mouth - WQ",
    ];
}

// Convert row label to storage key (remove spaces)
static NSString *KeyFromLabel(NSString *label) {
    return [label stringByReplacingOccurrencesOfString:@" " withString:@""];
}

#pragma mark - Private Interface

@interface XLModelFaceDialogController ()

// UI elements
@property (nonatomic, strong) NSPopUpButton *faceNamePopup;
@property (nonatomic, strong) NSButton *addButton;
@property (nonatomic, strong) NSButton *moreButton;
@property (nonatomic, strong) NSSegmentedControl *faceTypeControl;
@property (nonatomic, strong) NSTableView *gridTableView;
@property (nonatomic, strong) NSScrollView *gridScrollView;
@property (nonatomic, strong) NSButton *customColorsCheckbox;
@property (nonatomic, strong) NSPopUpButton *imagePlacementPopup;
@property (nonatomic, strong) NSStackView *matrixOptionsStack;

// Data
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *faceData;
@property (nonatomic, copy) NSString *currentFaceName;
@property (nonatomic, assign) XLFaceType currentFaceType;
@property (nonatomic, copy) void (^completionHandler)(BOOL saved);

@end

#pragma mark - Implementation

@implementation XLModelFaceDialogController

#pragma mark - Lifecycle

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 550)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Face Definition";
    window.minSize = NSMakeSize(500, 400);
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        _faceData = [NSMutableDictionary dictionary];
        [self setupUI];
    }
    return self;
}

#pragma mark - UI Setup

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    // Main vertical stack
    NSStackView *mainStack = [NSStackView stackViewWithViews:@[]];
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.alignment = NSLayoutAttributeLeading;
    mainStack.spacing = 8;
    mainStack.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [mainStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [mainStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [mainStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
    ]];

    // --- Top row: Name + Add + More ---
    NSStackView *topRow = [NSStackView stackViewWithViews:@[]];
    topRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    topRow.spacing = 6;

    NSTextField *nameLabel = [NSTextField labelWithString:@"Name:"];
    [topRow addArrangedSubview:nameLabel];

    self.faceNamePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.faceNamePopup.target = self;
    self.faceNamePopup.action = @selector(faceNameChanged:);
    [self.faceNamePopup setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    [topRow addArrangedSubview:self.faceNamePopup];

    self.addButton = [NSButton buttonWithTitle:@"Add" target:self action:@selector(addFace:)];
    [topRow addArrangedSubview:self.addButton];

    self.moreButton = [NSButton buttonWithTitle:@"..." target:self action:@selector(showMoreMenu:)];
    self.moreButton.bezelStyle = NSBezelStyleSmallSquare;
    [topRow addArrangedSubview:self.moreButton];

    topRow.translatesAutoresizingMaskIntoConstraints = NO;
    [mainStack addArrangedSubview:topRow];
    [topRow.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor constant:-24].active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [self.faceNamePopup.widthAnchor constraintGreaterThanOrEqualToConstant:200],
    ]];

    // --- Face type selector ---
    self.faceTypeControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Node Ranges", @"Matrix"]
                                                            trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                  target:self
                                                                  action:@selector(faceTypeChanged:)];
    self.faceTypeControl.selectedSegment = 0;
    self.faceTypeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [mainStack addArrangedSubview:self.faceTypeControl];

    // --- Options row (custom colors + image placement) ---
    NSStackView *optionsRow = [NSStackView stackViewWithViews:@[]];
    optionsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    optionsRow.spacing = 12;

    self.customColorsCheckbox = [NSButton checkboxWithTitle:@"Force Custom Colors"
                                                    target:self
                                                    action:@selector(customColorsChanged:)];
    [optionsRow addArrangedSubview:self.customColorsCheckbox];

    // Matrix options (image placement)
    self.matrixOptionsStack = [NSStackView stackViewWithViews:@[]];
    self.matrixOptionsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.matrixOptionsStack.spacing = 6;

    NSTextField *placementLabel = [NSTextField labelWithString:@"Image Placement:"];
    [self.matrixOptionsStack addArrangedSubview:placementLabel];

    self.imagePlacementPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.imagePlacementPopup addItemsWithTitles:@[@"Centered", @"Scaled", @"Scale Keep Aspect Ratio", @"Scale Keep Aspect Ratio Crop"]];
    [self.imagePlacementPopup selectItemWithTitle:@"Scaled"];
    self.imagePlacementPopup.target = self;
    self.imagePlacementPopup.action = @selector(imagePlacementChanged:);
    [self.matrixOptionsStack addArrangedSubview:self.imagePlacementPopup];
    self.matrixOptionsStack.hidden = YES;

    [optionsRow addArrangedSubview:self.matrixOptionsStack];
    optionsRow.translatesAutoresizingMaskIntoConstraints = NO;
    [mainStack addArrangedSubview:optionsRow];

    // --- Grid table view ---
    self.gridScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.gridScrollView.hasVerticalScroller = YES;
    self.gridScrollView.hasHorizontalScroller = YES;
    self.gridScrollView.autohidesScrollers = YES;
    self.gridScrollView.borderType = NSBezelBorder;
    self.gridScrollView.translatesAutoresizingMaskIntoConstraints = NO;

    self.gridTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.gridTableView.dataSource = self;
    self.gridTableView.delegate = self;
    self.gridTableView.usesAlternatingRowBackgroundColors = YES;
    self.gridTableView.allowsColumnReordering = NO;
    self.gridTableView.rowHeight = 22;
    self.gridTableView.gridStyleMask = NSTableViewSolidVerticalGridLineMask | NSTableViewSolidHorizontalGridLineMask;

    [self setupGridColumns];

    self.gridScrollView.documentView = self.gridTableView;
    [mainStack addArrangedSubview:self.gridScrollView];
    [self.gridScrollView.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor constant:-24].active = YES;
    [self.gridScrollView.heightAnchor constraintGreaterThanOrEqualToConstant:250].active = YES;

    // Make scroll view fill remaining space
    [mainStack setCustomSpacing:0 afterView:self.gridScrollView];
    [mainStack setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [self.gridScrollView setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];

    // --- Bottom buttons ---
    NSStackView *buttonRow = [NSStackView stackViewWithViews:@[]];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 8;

    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [buttonRow addArrangedSubview:spacer];

    NSButton *cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelClicked:)];
    cancelButton.keyEquivalent = @"\033"; // Escape
    [buttonRow addArrangedSubview:cancelButton];

    NSButton *okButton = [NSButton buttonWithTitle:@"OK" target:self action:@selector(okClicked:)];
    okButton.keyEquivalent = @"\r"; // Enter
    [buttonRow addArrangedSubview:okButton];

    buttonRow.translatesAutoresizingMaskIntoConstraints = NO;
    [mainStack addArrangedSubview:buttonRow];
    [buttonRow.widthAnchor constraintEqualToAnchor:mainStack.widthAnchor constant:-24].active = YES;
}

- (void)setupGridColumns {
    // Remove existing columns
    while (self.gridTableView.tableColumns.count > 0) {
        [self.gridTableView removeTableColumn:self.gridTableView.tableColumns.lastObject];
    }

    if (self.currentFaceType == XLFaceTypeNodeRange) {
        // Phoneme label | Nodes | Color
        NSTableColumn *labelCol = [[NSTableColumn alloc] initWithIdentifier:@"label"];
        labelCol.title = @"Phoneme";
        labelCol.width = 140;
        labelCol.minWidth = 100;
        labelCol.editable = NO;
        [self.gridTableView addTableColumn:labelCol];

        NSTableColumn *nodesCol = [[NSTableColumn alloc] initWithIdentifier:@"nodes"];
        nodesCol.title = @"Nodes";
        nodesCol.width = 300;
        nodesCol.minWidth = 100;
        nodesCol.editable = YES;
        [self.gridTableView addTableColumn:nodesCol];

        NSTableColumn *colorCol = [[NSTableColumn alloc] initWithIdentifier:@"color"];
        colorCol.title = @"Color";
        colorCol.width = 50;
        colorCol.minWidth = 40;
        colorCol.editable = NO;
        [self.gridTableView addTableColumn:colorCol];
    } else {
        // Phoneme label | Eyes Open | Eyes Closed
        NSTableColumn *labelCol = [[NSTableColumn alloc] initWithIdentifier:@"label"];
        labelCol.title = @"Phoneme";
        labelCol.width = 140;
        labelCol.minWidth = 100;
        labelCol.editable = NO;
        [self.gridTableView addTableColumn:labelCol];

        NSTableColumn *eyesOpenCol = [[NSTableColumn alloc] initWithIdentifier:@"eyesOpen"];
        eyesOpenCol.title = @"Eyes Open";
        eyesOpenCol.width = 250;
        eyesOpenCol.minWidth = 100;
        eyesOpenCol.editable = YES;
        [self.gridTableView addTableColumn:eyesOpenCol];

        NSTableColumn *eyesClosedCol = [[NSTableColumn alloc] initWithIdentifier:@"eyesClosed"];
        eyesClosedCol.title = @"Eyes Closed";
        eyesClosedCol.width = 250;
        eyesClosedCol.minWidth = 100;
        eyesClosedCol.editable = YES;
        [self.gridTableView addTableColumn:eyesClosedCol];
    }
}

#pragma mark - Show Methods

- (void)showAsSheetOnWindow:(NSWindow *)parentWindow completion:(void (^)(BOOL))completion {
    self.completionHandler = completion;
    [self loadFaceData];
    [parentWindow beginSheet:self.window completionHandler:^(NSModalResponse returnCode) {
        if (self.completionHandler) {
            self.completionHandler(returnCode == NSModalResponseOK);
        }
    }];
}

- (void)showWithCompletion:(void (^)(BOOL))completion {
    self.completionHandler = completion;
    [self loadFaceData];
    [self showWindow:nil];
}

#pragma mark - Data Loading

- (void)loadFaceData {
    if (!self.engineBridge || !self.modelName) return;

    [self.faceData removeAllObjects];

    NSDictionary<NSString *, NSDictionary *> *allFaces = [self.engineBridge getAllFaceDefinitions:self.modelName];
    for (NSString *faceName in allFaces) {
        NSDictionary *faceDict = allFaces[faceName];
        self.faceData[faceName] = [faceDict mutableCopy];
    }

    [self.faceNamePopup removeAllItems];
    NSArray *sortedNames = [self.faceData.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *name in sortedNames) {
        [self.faceNamePopup addItemWithTitle:name];
    }

    if (self.faceNamePopup.numberOfItems > 0) {
        [self.faceNamePopup selectItemAtIndex:0];
        self.currentFaceName = self.faceNamePopup.titleOfSelectedItem;
        [self selectFace:self.currentFaceName];
    } else {
        self.currentFaceName = nil;
        self.faceTypeControl.enabled = NO;
    }
}

- (void)selectFace:(NSString *)faceName {
    if (!faceName) return;
    self.currentFaceName = faceName;

    NSMutableDictionary *info = self.faceData[faceName];
    if (!info) {
        info = [NSMutableDictionary dictionary];
        self.faceData[faceName] = info;
    }

    NSString *type = info[@"Type"];
    if (!type || type.length == 0) {
        type = @"NodeRange";
        info[@"Type"] = type;
    }

    if ([type isEqualToString:@"NodeRange"] || [type isEqualToString:@"SingleNode"]) {
        self.currentFaceType = XLFaceTypeNodeRange;
        self.faceTypeControl.selectedSegment = 0;
        self.matrixOptionsStack.hidden = YES;
        self.customColorsCheckbox.hidden = NO;
        BOOL customColors = [info[@"CustomColors"] isEqualToString:@"1"];
        self.customColorsCheckbox.state = customColors ? NSControlStateValueOn : NSControlStateValueOff;
    } else {
        self.currentFaceType = XLFaceTypeMatrix;
        self.faceTypeControl.selectedSegment = 1;
        self.matrixOptionsStack.hidden = NO;
        self.customColorsCheckbox.hidden = YES;

        NSString *placement = info[@"ImagePlacement"];
        if (placement.length > 0) {
            [self.imagePlacementPopup selectItemWithTitle:placement];
        } else {
            [self.imagePlacementPopup selectItemWithTitle:@"Scaled"];
        }
    }

    self.faceTypeControl.enabled = YES;
    [self setupGridColumns];
    [self.gridTableView reloadData];
}

#pragma mark - Actions

- (void)faceNameChanged:(id)sender {
    NSString *name = self.faceNamePopup.titleOfSelectedItem;
    if (name) {
        [self saveCurrentGridToData];
        [self selectFace:name];
    }
}

- (void)faceTypeChanged:(id)sender {
    [self saveCurrentGridToData];

    XLFaceType newType = (XLFaceType)self.faceTypeControl.selectedSegment;
    self.currentFaceType = newType;

    if (self.currentFaceName) {
        NSMutableDictionary *info = self.faceData[self.currentFaceName];
        if (newType == XLFaceTypeNodeRange) {
            info[@"Type"] = @"NodeRange";
            self.matrixOptionsStack.hidden = YES;
            self.customColorsCheckbox.hidden = NO;
        } else {
            info[@"Type"] = @"Matrix";
            self.matrixOptionsStack.hidden = NO;
            self.customColorsCheckbox.hidden = YES;
        }
    }

    [self setupGridColumns];
    [self.gridTableView reloadData];
}

- (void)customColorsChanged:(id)sender {
    if (!self.currentFaceName) return;
    NSMutableDictionary *info = self.faceData[self.currentFaceName];
    if (self.customColorsCheckbox.state == NSControlStateValueOn) {
        info[@"CustomColors"] = @"1";
    } else {
        info[@"CustomColors"] = @"0";
        // Clear custom color values
        NSArray *keysToRemove = [info.allKeys filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
                return [key hasSuffix:@"-Color"];
            }]];
        for (NSString *key in keysToRemove) {
            [info removeObjectForKey:key];
        }
    }
    [self.gridTableView reloadData];
}

- (void)imagePlacementChanged:(id)sender {
    if (!self.currentFaceName) return;
    NSMutableDictionary *info = self.faceData[self.currentFaceName];
    info[@"ImagePlacement"] = self.imagePlacementPopup.titleOfSelectedItem;
}

- (void)addFace:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"New Face";
    alert.informativeText = @"Enter name for new face definition:";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    input.stringValue = @"";
    input.placeholderString = @"Face name";
    alert.accessoryView = input;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString *name = [input stringValue];
            if (name.length > 0 && !self.faceData[name]) {
                NSMutableDictionary *newFace = [NSMutableDictionary dictionary];
                newFace[@"Type"] = @"NodeRange";
                self.faceData[name] = newFace;
                [self.faceNamePopup addItemWithTitle:name];
                [self.faceNamePopup selectItemWithTitle:name];
                self.faceTypeControl.enabled = YES;
                [self selectFace:name];
            }
        }
    }];
}

- (void)showMoreMenu:(id)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"More"];

    if (self.faceNamePopup.numberOfItems > 0) {
        [menu addItemWithTitle:@"Copy" action:@selector(copyFace:) keyEquivalent:@""];
        [menu addItemWithTitle:@"Rename" action:@selector(renameFace:) keyEquivalent:@""];
        [menu addItemWithTitle:@"Delete" action:@selector(deleteFace:) keyEquivalent:@""];
        [menu addItem:[NSMenuItem separatorItem]];
    }

    [menu addItemWithTitle:@"Import From File" action:@selector(importFromFile:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Shift Nodes" action:@selector(shiftNodes:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Reverse Nodes" action:@selector(reverseNodes:) keyEquivalent:@""];

    for (NSMenuItem *item in menu.itemArray) {
        item.target = self;
    }

    NSRect buttonRect = [self.moreButton convertRect:self.moreButton.bounds toView:nil];
    NSPoint menuLocation = NSMakePoint(NSMinX(buttonRect), NSMinY(buttonRect));
    menuLocation = [self.window convertPointToScreen:menuLocation];

    [menu popUpMenuPositioningItem:nil atLocation:[self.moreButton convertPoint:NSMakePoint(0, self.moreButton.bounds.size.height) toView:nil] inView:nil];
}

- (void)copyFace:(id)sender {
    if (!self.currentFaceName) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Copy Face";
    alert.informativeText = @"Enter name for the copy:";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    input.stringValue = [NSString stringWithFormat:@"%@ - Copy", self.currentFaceName];
    alert.accessoryView = input;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString *newName = [input stringValue];
            if (newName.length > 0 && !self.faceData[newName]) {
                [self saveCurrentGridToData];
                NSMutableDictionary *copy = [self.faceData[self.currentFaceName] mutableCopy];
                self.faceData[newName] = copy;
                [self.faceNamePopup addItemWithTitle:newName];
                [self.faceNamePopup selectItemWithTitle:newName];
                [self selectFace:newName];
            }
        }
    }];
}

- (void)renameFace:(id)sender {
    if (!self.currentFaceName) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename Face";
    alert.informativeText = @"Enter new name:";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    input.stringValue = self.currentFaceName;
    alert.accessoryView = input;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString *newName = [input stringValue];
            if (newName.length > 0 && ![newName isEqualToString:self.currentFaceName] && !self.faceData[newName]) {
                [self saveCurrentGridToData];
                NSMutableDictionary *data = self.faceData[self.currentFaceName];
                [self.faceData removeObjectForKey:self.currentFaceName];
                self.faceData[newName] = data;

                NSInteger idx = [self.faceNamePopup indexOfItemWithTitle:self.currentFaceName];
                if (idx >= 0) {
                    [self.faceNamePopup removeItemAtIndex:idx];
                    [self.faceNamePopup insertItemWithTitle:newName atIndex:idx];
                    [self.faceNamePopup selectItemWithTitle:newName];
                }
                [self selectFace:newName];
            }
        }
    }];
}

- (void)deleteFace:(id)sender {
    if (!self.currentFaceName) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Delete Face Definition";
    alert.informativeText = [NSString stringWithFormat:@"Are you sure you want to delete '%@'?", self.currentFaceName];
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [self.faceData removeObjectForKey:self.currentFaceName];
            [self.faceNamePopup removeItemWithTitle:self.currentFaceName];
            if (self.faceNamePopup.numberOfItems > 0) {
                [self.faceNamePopup selectItemAtIndex:0];
                [self selectFace:self.faceNamePopup.titleOfSelectedItem];
            } else {
                self.currentFaceName = nil;
                self.faceTypeControl.enabled = NO;
                [self.gridTableView reloadData];
            }
        }
    }];
}

- (void)importFromFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"xmodel"]];
    panel.allowsMultipleSelection = NO;
    panel.message = @"Choose an xmodel file to import face definitions from";

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            [self importFacesFromXModelFile:panel.URL.path];
        }
    }];
}

- (void)importFacesFromXModelFile:(NSString *)filePath {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    if (!data) return;

    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:&error];
    if (!doc || error) return;

    NSArray<NSXMLElement *> *faceElements = [doc.rootElement elementsForName:@"faceInfo"];
    for (NSXMLElement *faceElem in faceElements) {
        NSXMLNode *nameAttr = [faceElem attributeForName:@"Name"];
        if (!nameAttr || !nameAttr.stringValue) continue;

        NSString *faceName = nameAttr.stringValue;
        NSMutableDictionary *faceDict = [NSMutableDictionary dictionary];

        for (NSXMLNode *attr in [faceElem attributes]) {
            if (![attr.name isEqualToString:@"Name"]) {
                faceDict[attr.name] = attr.stringValue;
            }
        }

        // Avoid overwriting existing faces
        NSString *finalName = faceName;
        int suffix = 1;
        while (self.faceData[finalName]) {
            finalName = [NSString stringWithFormat:@"%@-%d", faceName, suffix++];
        }

        self.faceData[finalName] = faceDict;
        [self.faceNamePopup addItemWithTitle:finalName];
    }

    if (self.faceNamePopup.numberOfItems > 0) {
        self.faceTypeControl.enabled = YES;
        [self.faceNamePopup selectItemAtIndex:self.faceNamePopup.numberOfItems - 1];
        [self selectFace:self.faceNamePopup.titleOfSelectedItem];
    }
}

- (void)shiftNodes:(id)sender {
    if (!self.currentFaceName) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Shift Nodes";
    alert.informativeText = @"Enter the number of nodes to shift by (negative to shift down):";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    input.stringValue = @"0";
    alert.accessoryView = input;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSInteger shift = [input stringValue].integerValue;
            if (shift != 0) {
                [self saveCurrentGridToData];
                [self performNodeShift:shift];
                [self.gridTableView reloadData];
            }
        }
    }];
}

- (void)performNodeShift:(NSInteger)shift {
    if (!self.currentFaceName) return;
    NSMutableDictionary *info = self.faceData[self.currentFaceName];
    if (!info) return;

    NSArray<NSString *> *labels = (self.currentFaceType == XLFaceTypeNodeRange) ? NodeRangeRowLabels() : @[];

    for (NSString *label in labels) {
        NSString *key = KeyFromLabel(label);
        NSString *value = info[key];
        if (!value || value.length == 0) continue;

        NSMutableArray<NSString *> *newParts = [NSMutableArray array];
        NSArray<NSString *> *parts = [value componentsSeparatedByString:@","];
        for (NSString *part in parts) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([trimmed containsString:@"-"]) {
                NSArray *range = [trimmed componentsSeparatedByString:@"-"];
                if (range.count == 2) {
                    NSInteger start = [range[0] integerValue] + shift;
                    NSInteger end = [range[1] integerValue] + shift;
                    if (start >= 1 && end >= 1) {
                        [newParts addObject:[NSString stringWithFormat:@"%ld-%ld", (long)start, (long)end]];
                    }
                }
            } else {
                NSInteger node = [trimmed integerValue] + shift;
                if (node >= 1) {
                    [newParts addObject:[NSString stringWithFormat:@"%ld", (long)node]];
                }
            }
        }
        info[key] = [newParts componentsJoinedByString:@","];
    }
}

- (void)reverseNodes:(id)sender {
    if (!self.currentFaceName) return;
    [self saveCurrentGridToData];

    NSMutableDictionary *info = self.faceData[self.currentFaceName];
    if (!info) return;

    NSUInteger nodeCount = [self.engineBridge getModelNodeCount:self.modelName];
    if (nodeCount == 0) return;

    NSArray<NSString *> *labels = (self.currentFaceType == XLFaceTypeNodeRange) ? NodeRangeRowLabels() : @[];

    for (NSString *label in labels) {
        NSString *key = KeyFromLabel(label);
        NSString *value = info[key];
        if (!value || value.length == 0) continue;

        NSMutableArray<NSString *> *newParts = [NSMutableArray array];
        NSArray<NSString *> *parts = [value componentsSeparatedByString:@","];
        for (NSString *part in parts) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([trimmed containsString:@"-"]) {
                NSArray *range = [trimmed componentsSeparatedByString:@"-"];
                if (range.count == 2) {
                    NSInteger start = (NSInteger)nodeCount + 1 - [range[1] integerValue];
                    NSInteger end = (NSInteger)nodeCount + 1 - [range[0] integerValue];
                    if (start >= 1 && end >= 1) {
                        [newParts addObject:[NSString stringWithFormat:@"%ld-%ld", (long)start, (long)end]];
                    }
                }
            } else {
                NSInteger node = (NSInteger)nodeCount + 1 - [trimmed integerValue];
                if (node >= 1) {
                    [newParts addObject:[NSString stringWithFormat:@"%ld", (long)node]];
                }
            }
        }
        info[key] = [newParts componentsJoinedByString:@","];
    }

    [self.gridTableView reloadData];
}

- (void)okClicked:(id)sender {
    [self saveCurrentGridToData];

    // Write all face data back via bridge
    if (self.engineBridge && self.modelName) {
        // Convert NSMutableDictionary to NSDictionary for the bridge
        NSMutableDictionary *cleanData = [NSMutableDictionary dictionary];
        for (NSString *faceName in self.faceData) {
            NSMutableDictionary *faceInfo = self.faceData[faceName];
            // Skip empty face definitions
            if (faceInfo.count > 0) {
                cleanData[faceName] = [faceInfo copy];
            }
        }
        [self.engineBridge setAllFaceDefinitions:self.modelName definitions:cleanData];
    }

    if (self.window.sheetParent) {
        [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];
    } else {
        [self.window close];
        if (self.completionHandler) {
            self.completionHandler(YES);
        }
    }
}

- (void)cancelClicked:(id)sender {
    if (self.window.sheetParent) {
        [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseCancel];
    } else {
        [self.window close];
        if (self.completionHandler) {
            self.completionHandler(NO);
        }
    }
}

#pragma mark - Grid Data Sync

- (void)saveCurrentGridToData {
    if (!self.currentFaceName) return;
    // Data is saved directly to faceData on cell edits, no additional sync needed
}

- (NSArray<NSString *> *)currentRowLabels {
    if (self.currentFaceType == XLFaceTypeNodeRange) {
        return NodeRangeRowLabels();
    } else {
        return MatrixRowLabels();
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (!self.currentFaceName) return 0;
    return (NSInteger)[self currentRowLabels].count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *identifier = tableColumn.identifier;
    NSArray<NSString *> *labels = [self currentRowLabels];

    if (row < 0 || row >= (NSInteger)labels.count) return nil;

    NSString *label = labels[row];
    NSString *key = KeyFromLabel(label);
    NSMutableDictionary *info = self.faceData[self.currentFaceName];

    if ([identifier isEqualToString:@"label"]) {
        NSTextField *field = [tableView makeViewWithIdentifier:@"LabelCell" owner:self];
        if (!field) {
            field = [NSTextField labelWithString:@""];
            field.identifier = @"LabelCell";
        }
        field.stringValue = label;
        return field;
    }

    if ([identifier isEqualToString:@"nodes"]) {
        NSTextField *field = [tableView makeViewWithIdentifier:@"NodesCell" owner:self];
        if (!field) {
            field = [[NSTextField alloc] initWithFrame:NSZeroRect];
            field.identifier = @"NodesCell";
            field.bordered = NO;
            field.drawsBackground = NO;
            field.editable = YES;
            field.target = self;
            field.action = @selector(nodeCellEdited:);
            field.placeholderString = @"e.g. 1-5,10-15";
        }
        field.stringValue = info[key] ?: @"";
        field.tag = row;
        return field;
    }

    if ([identifier isEqualToString:@"color"]) {
        BOOL showColors = [info[@"CustomColors"] isEqualToString:@"1"];
        if (!showColors) {
            NSTextField *field = [NSTextField labelWithString:@""];
            return field;
        }
        NSString *colorKey = [key stringByAppendingString:@"-Color"];
        NSString *colorStr = info[colorKey];

        NSButton *colorButton = [tableView makeViewWithIdentifier:@"ColorCell" owner:self];
        if (!colorButton) {
            colorButton = [[NSButton alloc] initWithFrame:NSZeroRect];
            colorButton.identifier = @"ColorCell";
            colorButton.bordered = YES;
            colorButton.bezelStyle = NSBezelStyleSmallSquare;
            colorButton.title = @"";
            colorButton.target = self;
            colorButton.action = @selector(colorCellClicked:);
        }
        colorButton.tag = row;

        NSColor *color = [NSColor whiteColor];
        if (colorStr.length > 0 && [colorStr hasPrefix:@"#"]) {
            unsigned int hex = 0;
            NSScanner *scanner = [NSScanner scannerWithString:[colorStr substringFromIndex:1]];
            [scanner scanHexInt:&hex];
            CGFloat r = ((hex >> 16) & 0xFF) / 255.0;
            CGFloat g = ((hex >> 8) & 0xFF) / 255.0;
            CGFloat b = (hex & 0xFF) / 255.0;
            color = [NSColor colorWithRed:r green:g blue:b alpha:1.0];
        }
        colorButton.layer.backgroundColor = color.CGColor;
        colorButton.wantsLayer = YES;
        return colorButton;
    }

    if ([identifier isEqualToString:@"eyesOpen"] || [identifier isEqualToString:@"eyesClosed"]) {
        NSString *colKey;
        if ([identifier isEqualToString:@"eyesOpen"]) {
            colKey = [NSString stringWithFormat:@"Mouth-%@-EyesOpen", [key stringByReplacingOccurrencesOfString:@"Mouth-" withString:@""]];
        } else {
            colKey = [NSString stringWithFormat:@"Mouth-%@-EyesClosed", [key stringByReplacingOccurrencesOfString:@"Mouth-" withString:@""]];
        }

        NSTextField *field = [tableView makeViewWithIdentifier:identifier owner:self];
        if (!field) {
            field = [[NSTextField alloc] initWithFrame:NSZeroRect];
            field.identifier = identifier;
            field.bordered = NO;
            field.drawsBackground = NO;
            field.editable = YES;
            field.target = self;
            field.action = @selector(matrixCellEdited:);
            field.placeholderString = @"Click to set image...";
        }
        field.stringValue = info[colKey] ?: @"";
        field.tag = row;
        return field;
    }

    return nil;
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"label"]) return NO;
    if ([tableColumn.identifier isEqualToString:@"color"]) return NO;
    return YES;
}

#pragma mark - Cell Editing

- (void)nodeCellEdited:(NSTextField *)sender {
    NSInteger row = sender.tag;
    NSArray<NSString *> *labels = [self currentRowLabels];
    if (row < 0 || row >= (NSInteger)labels.count) return;

    NSString *key = KeyFromLabel(labels[row]);
    NSMutableDictionary *info = self.faceData[self.currentFaceName];
    info[key] = sender.stringValue;
}

- (void)matrixCellEdited:(NSTextField *)sender {
    NSInteger row = sender.tag;
    NSArray<NSString *> *labels = [self currentRowLabels];
    if (row < 0 || row >= (NSInteger)labels.count) return;

    NSString *phonemeKey = KeyFromLabel(labels[row]);
    NSString *stripped = [phonemeKey stringByReplacingOccurrencesOfString:@"Mouth-" withString:@""];

    // Determine column from field identifier
    NSString *colKey;
    if ([sender.identifier isEqualToString:@"eyesOpen"]) {
        colKey = [NSString stringWithFormat:@"Mouth-%@-EyesOpen", stripped];
    } else {
        colKey = [NSString stringWithFormat:@"Mouth-%@-EyesClosed", stripped];
    }

    NSMutableDictionary *info = self.faceData[self.currentFaceName];
    info[colKey] = sender.stringValue;
}

- (void)colorCellClicked:(NSButton *)sender {
    NSInteger row = sender.tag;
    NSArray<NSString *> *labels = [self currentRowLabels];
    if (row < 0 || row >= (NSInteger)labels.count) return;

    NSString *key = KeyFromLabel(labels[row]);
    NSString *colorKey = [key stringByAppendingString:@"-Color"];

    NSColorPanel *colorPanel = [NSColorPanel sharedColorPanel];

    // Parse current color
    NSMutableDictionary *info = self.faceData[self.currentFaceName];
    NSString *colorStr = info[colorKey];
    NSColor *currentColor = [NSColor whiteColor];
    if (colorStr.length > 0 && [colorStr hasPrefix:@"#"]) {
        unsigned int hex = 0;
        NSScanner *scanner = [NSScanner scannerWithString:[colorStr substringFromIndex:1]];
        [scanner scanHexInt:&hex];
        CGFloat r = ((hex >> 16) & 0xFF) / 255.0;
        CGFloat g = ((hex >> 8) & 0xFF) / 255.0;
        CGFloat b = (hex & 0xFF) / 255.0;
        currentColor = [NSColor colorWithRed:r green:g blue:b alpha:1.0];
    }

    colorPanel.color = currentColor;
    colorPanel.continuous = NO;

    // Use a simple block-based approach
    __weak typeof(self) weakSelf = self;
    colorPanel.target = nil;
    colorPanel.action = nil;

    // Store row info for the color callback
    objc_setAssociatedObject(self, "colorEditRow", @(row), OBJC_ASSOCIATION_RETAIN);

    colorPanel.target = self;
    colorPanel.action = @selector(colorPanelChanged:);
    [colorPanel orderFront:nil];
}

- (void)colorPanelChanged:(id)sender {
    NSNumber *rowNum = objc_getAssociatedObject(self, "colorEditRow");
    if (!rowNum) return;

    NSInteger row = rowNum.integerValue;
    NSArray<NSString *> *labels = [self currentRowLabels];
    if (row < 0 || row >= (NSInteger)labels.count) return;

    NSString *key = KeyFromLabel(labels[row]);
    NSString *colorKey = [key stringByAppendingString:@"-Color"];

    NSColor *color = [[NSColorPanel sharedColorPanel].color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    NSString *hexStr = [NSString stringWithFormat:@"#%02X%02X%02X",
                        (int)(color.redComponent * 255),
                        (int)(color.greenComponent * 255),
                        (int)(color.blueComponent * 255)];

    NSMutableDictionary *info = self.faceData[self.currentFaceName];
    info[colorKey] = hexStr;

    [self.gridTableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
                                  columnIndexes:[NSIndexSet indexSetWithIndex:2]]; // color column
}

@end
