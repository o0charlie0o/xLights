/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLSetupViewController.h"
#import "XLEngineBridge.h"
#import "XLAppDelegate.h"
#import "setup/XLControllerInspectorViewController.h"
#import "setup/XLControllerDefinitionLoader.h"
#import "setup/XLUploadProgressSheet.h"
#import "setup/XLMultiControllerUploadDialogController.h"
#import "setup/XLControllerModelWindowController.h"

@interface XLSetupViewController () <XLControllerInspectorDelegate, XLUploadProgressSheetDelegate, XLMultiControllerUploadDelegate>

@property (nonatomic, strong, readwrite) XLControllersViewController *controllersViewController;
@property (nonatomic, strong, readwrite) XLPortConfigurationView *portConfigurationView;
@property (nonatomic, strong, readwrite) XLControllerInspectorViewController *inspectorViewController;
@property (nonatomic, strong) NSSplitViewController *splitViewController;
@property (nonatomic, strong) XLUploadProgressSheet *uploadProgressSheet;
@property (nonatomic, strong) XLMultiControllerUploadDialogController *multiUploadDialog;
@property (nonatomic, strong) XLControllerModelWindowController *controllerModelWindowController;

// Show folder header bar
@property (nonatomic, strong) NSView *showFolderHeaderBar;
@property (nonatomic, strong) NSTextField *showFolderPathLabel;
@property (nonatomic, strong) NSButton *changeFolderButton;
@property (nonatomic, strong) NSButton *changeTempButton;

@end

@implementation XLSetupViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1200, 700)];
    view.wantsLayer = YES;
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // --- Show Folder Header Bar ---
    [self setupShowFolderHeader];

    // Initialize view controllers
    _controllersViewController = [[XLControllersViewController alloc] init];
    _controllersViewController.engineBridge = _engineBridge;
    _controllersViewController.delegate = self;

    _portConfigurationView = [[XLPortConfigurationView alloc] init];
    _portConfigurationView.engineBridge = _engineBridge;
    _portConfigurationView.delegate = self;

    _inspectorViewController = [[XLControllerInspectorViewController alloc] init];
    _inspectorViewController.engineBridge = _engineBridge;
    _inspectorViewController.delegate = self;

    // Create three-pane split view
    _splitViewController = [[NSSplitViewController alloc] init];
    _splitViewController.splitView.vertical = YES;
    _splitViewController.splitView.dividerStyle = NSSplitViewDividerStyleThin;

    // Left pane: Controller list (use contentList, not sidebar, to avoid
    // extending into the toolbar area when hosted inside NavigationStack)
    NSSplitViewItem *listItem = [NSSplitViewItem contentListWithViewController:_controllersViewController];
    listItem.canCollapse = NO;
    listItem.minimumThickness = 280.0;
    listItem.maximumThickness = 400.0;
    [_splitViewController addSplitViewItem:listItem];

    // Center pane: Port configuration grid
    NSSplitViewItem *portItem = [NSSplitViewItem contentListWithViewController:_portConfigurationView];
    portItem.canCollapse = NO;
    portItem.minimumThickness = 450.0;
    [_splitViewController addSplitViewItem:portItem];

    // Right pane: Controller inspector (use contentList, not inspector,
    // to prevent the split view from integrating with the toolbar area
    // when hosted inside the SwiftUI content view)
    NSSplitViewItem *inspectorItem = [NSSplitViewItem contentListWithViewController:_inspectorViewController];
    inspectorItem.canCollapse = YES;
    inspectorItem.minimumThickness = 260.0;
    inspectorItem.maximumThickness = 400.0;
    [_splitViewController addSplitViewItem:inspectorItem];

    [self addChildViewController:_splitViewController];
    NSView *splitView = _splitViewController.view;
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:splitView];

    [NSLayoutConstraint activateConstraints:@[
        [splitView.topAnchor constraintEqualToAnchor:_showFolderHeaderBar.bottomAnchor],
        [splitView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [splitView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [splitView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    // Register port view for model drags
    [_portConfigurationView registerForModelDrag];

    // Listen for show folder changes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showFolderDidChange:)
                                                 name:XLShowFolderDidChangeNotification
                                               object:nil];

    // Initial display
    [self updateShowFolderDisplay];
}

#pragma mark - Show Folder Header

- (void)setupShowFolderHeader {
    _showFolderHeaderBar = [[NSView alloc] init];
    _showFolderHeaderBar.wantsLayer = YES;
    _showFolderHeaderBar.layer.backgroundColor = [NSColor colorWithWhite:0.15 alpha:1.0].CGColor;
    _showFolderHeaderBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_showFolderHeaderBar];

    // Folder icon
    NSImageView *folderIcon = [[NSImageView alloc] init];
    folderIcon.image = [NSImage imageWithSystemSymbolName:@"folder.fill"
                                accessibilityDescription:@"Show Folder"];
    folderIcon.contentTintColor = [NSColor secondaryLabelColor];
    folderIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [_showFolderHeaderBar addSubview:folderIcon];

    // Path label
    _showFolderPathLabel = [NSTextField labelWithString:@"No show folder selected"];
    _showFolderPathLabel.font = [NSFont systemFontOfSize:12];
    _showFolderPathLabel.textColor = [NSColor labelColor];
    _showFolderPathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _showFolderPathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_showFolderPathLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                          forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_showFolderHeaderBar addSubview:_showFolderPathLabel];

    // "Change Show Folder" button
    _changeFolderButton = [NSButton buttonWithTitle:@"Change Show Folder"
                                             target:self
                                             action:@selector(changeShowFolderClicked:)];
    _changeFolderButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    _changeFolderButton.controlSize = NSControlSizeSmall;
    _changeFolderButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_showFolderHeaderBar addSubview:_changeFolderButton];

    // "Change Temporarily" / "Restore to Permanent" button
    _changeTempButton = [NSButton buttonWithTitle:@"Change Temporarily"
                                           target:self
                                           action:@selector(changeTempClicked:)];
    _changeTempButton.bezelStyle = NSBezelStyleAccessoryBarAction;
    _changeTempButton.controlSize = NSControlSizeSmall;
    _changeTempButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_showFolderHeaderBar addSubview:_changeTempButton];

    [NSLayoutConstraint activateConstraints:@[
        // Header bar
        [_showFolderHeaderBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_showFolderHeaderBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_showFolderHeaderBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_showFolderHeaderBar.heightAnchor constraintEqualToConstant:32],

        // Folder icon
        [folderIcon.leadingAnchor constraintEqualToAnchor:_showFolderHeaderBar.leadingAnchor constant:10],
        [folderIcon.centerYAnchor constraintEqualToAnchor:_showFolderHeaderBar.centerYAnchor],
        [folderIcon.widthAnchor constraintEqualToConstant:16],
        [folderIcon.heightAnchor constraintEqualToConstant:16],

        // Path label
        [_showFolderPathLabel.leadingAnchor constraintEqualToAnchor:folderIcon.trailingAnchor constant:6],
        [_showFolderPathLabel.centerYAnchor constraintEqualToAnchor:_showFolderHeaderBar.centerYAnchor],

        // Change Temporarily button (right side)
        [_changeTempButton.trailingAnchor constraintEqualToAnchor:_showFolderHeaderBar.trailingAnchor constant:-10],
        [_changeTempButton.centerYAnchor constraintEqualToAnchor:_showFolderHeaderBar.centerYAnchor],

        // Change Show Folder button
        [_changeFolderButton.trailingAnchor constraintEqualToAnchor:_changeTempButton.leadingAnchor constant:-6],
        [_changeFolderButton.centerYAnchor constraintEqualToAnchor:_showFolderHeaderBar.centerYAnchor],

        // Path label trails before the change folder button
        [_showFolderPathLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_changeFolderButton.leadingAnchor constant:-10],
    ]];
}

- (void)updateShowFolderDisplay {
    XLAppDelegate *appDelegate = (XLAppDelegate *)[NSApp delegate];
    NSString *currentFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    BOOL isTemp = appDelegate.isTemporaryFolder;

    if (currentFolder.length > 0) {
        _showFolderPathLabel.stringValue = currentFolder;
    } else {
        _showFolderPathLabel.stringValue = @"No show folder selected";
    }

    if (isTemp) {
        // Bold yellow text when using temporary folder
        _showFolderPathLabel.textColor = [NSColor systemYellowColor];
        _showFolderPathLabel.font = [NSFont boldSystemFontOfSize:12];
        [_changeTempButton setTitle:@"Restore to Permanent"];
        _changeTempButton.action = @selector(restorePermanentClicked:);
    } else {
        // Normal text for permanent folder
        _showFolderPathLabel.textColor = [NSColor labelColor];
        _showFolderPathLabel.font = [NSFont systemFontOfSize:12];
        [_changeTempButton setTitle:@"Change Temporarily"];
        _changeTempButton.action = @selector(changeTempClicked:);
    }
}

- (void)showFolderDidChange:(NSNotification *)notification {
    [self updateShowFolderDisplay];
}

- (void)changeShowFolderClicked:(id)sender {
    XLAppDelegate *appDelegate = (XLAppDelegate *)[NSApp delegate];
    [appDelegate selectShowFolder:sender];
}

- (void)changeTempClicked:(id)sender {
    XLAppDelegate *appDelegate = (XLAppDelegate *)[NSApp delegate];
    [appDelegate selectShowFolderTemporarily:sender];
}

- (void)restorePermanentClicked:(id)sender {
    XLAppDelegate *appDelegate = (XLAppDelegate *)[NSApp delegate];
    [appDelegate restorePermanentShowFolder];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setEngineBridge:(XLEngineBridge *)engineBridge {
    _engineBridge = engineBridge;
    _controllersViewController.engineBridge = engineBridge;
    _portConfigurationView.engineBridge = engineBridge;
    _inspectorViewController.engineBridge = engineBridge;
}

#pragma mark - XLControllersViewDelegate

- (void)controllersView:(XLControllersViewController *)controllersView
    didSelectControllerAtIndex:(NSInteger)index {
    if (index < 0) {
        [_portConfigurationView clearPorts];
        [_inspectorViewController clearInspector];
        return;
    }

    NSString *controllerName = [controllersView selectedControllerName];
    if (controllerName) {
        // Load port configuration for selected controller
        [_portConfigurationView loadPortsForController:controllerName];

        // Update inspector with controller details
        NSDictionary *info = [_engineBridge getControllerInfo:controllerName];
        if (info) {
            [_inspectorViewController setControllerData:info];
        }

        // Wire capability data from XLControllerDefinitionLoader to the port config view
        [self applyCapabilitiesToPortConfigFromControllerInfo:info];
    }
}

- (void)applyCapabilitiesToPortConfigFromControllerInfo:(NSDictionary *)info {
    if (!info) return;

    NSString *vendor = info[@"vendor"] ?: @"";
    NSString *model = info[@"model"] ?: @"";
    NSString *variant = info[@"variant"] ?: @"";

    if (vendor.length == 0 || model.length == 0 || variant.length == 0) {
        // No valid hardware selection -- use defaults
        [_portConfigurationView setAvailablePixelProtocols:nil serialProtocols:nil];
        [_portConfigurationView setSmartRemotesVisible:NO];
        return;
    }

    XLControllerVariantInfo *variantInfo = [[XLControllerDefinitionLoader sharedLoader]
                                            variantInfoForVendor:vendor model:model variant:variant];
    if (!variantInfo) {
        [_portConfigurationView setAvailablePixelProtocols:nil serialProtocols:nil];
        [_portConfigurationView setSmartRemotesVisible:NO];
        return;
    }

    // Configure port counts from capabilities
    [_portConfigurationView configureForPixelPorts:variantInfo.maxPixelPort
                                       serialPorts:variantInfo.maxSerialPort];

    // Filter protocol options based on controller capabilities
    [_portConfigurationView setAvailablePixelProtocols:variantInfo.pixelProtocols
                                       serialProtocols:variantInfo.serialProtocols];

    // Show/hide Smart Remote column based on controller support
    [_portConfigurationView setSmartRemotesVisible:variantInfo.supportsSmartRemotes];
}

- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestAddController:(XLControllerType)type {
    // Engine bridge call will be wired when OutputEngine API supports add
    [controllersView reloadData];
}

- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestDeleteControllerAtIndex:(NSInteger)index {
    // Engine bridge call will be wired when OutputEngine API supports delete
    [controllersView reloadData];
    [_portConfigurationView clearPorts];
    [_inspectorViewController clearInspector];
}

- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestEditControllerAtIndex:(NSInteger)index {
    // Focus the inspector for editing
    // Could also open a modal dialog for complex edits
}

- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestVisualiseControllerAtIndex:(NSInteger)index {
    NSString *controllerName = [controllersView selectedControllerName];
    if (!controllerName) return;

    _controllerModelWindowController = [[XLControllerModelWindowController alloc]
        initWithControllerName:controllerName engineBridge:_engineBridge];
    [_controllerModelWindowController showWindow:self];
}

- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestUploadControllerAtIndex:(NSInteger)index {
    NSString *controllerName = controllersView.controllers[index][XLControllerColumnName];
    if (!controllerName) return;

    // Create and show upload progress sheet
    _uploadProgressSheet = [[XLUploadProgressSheet alloc] initWithEngineBridge:_engineBridge];
    _uploadProgressSheet.delegate = self;

    [_uploadProgressSheet uploadToController:controllerName
                           attachedToWindow:self.view.window];
}

- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestUploadControllersAtIndices:(NSIndexSet *)indices {
    if (indices.count == 0) return;

    // Collect controller names
    NSMutableArray<NSString *> *controllerNames = [NSMutableArray arrayWithCapacity:indices.count];
    [indices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSString *name = controllersView.controllers[idx][XLControllerColumnName];
        if (name) {
            [controllerNames addObject:name];
        }
    }];

    if (controllerNames.count == 0) return;

    // Create and show upload progress sheet for batch upload
    _uploadProgressSheet = [[XLUploadProgressSheet alloc] initWithEngineBridge:_engineBridge];
    _uploadProgressSheet.delegate = self;

    [_uploadProgressSheet uploadToControllers:controllerNames
                            attachedToWindow:self.view.window];
}

- (void)controllersViewDidRequestBulkUpload:(XLControllersViewController *)controllersView {
    [self presentMultiControllerUploadDialog];
}

- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestUnlinkFromBaseAtIndices:(NSIndexSet *)indices {
    if (indices.count == 0) return;

    [indices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSString *name = controllersView.controllers[idx][XLControllerColumnName];
        if (name) {
            [self->_engineBridge unlinkControllerFromBase:name];
        }
    }];

    [controllersView reloadData];

    NSString *selectedName = [controllersView selectedControllerName];
    if (selectedName) {
        NSDictionary *info = [_engineBridge getControllerInfo:selectedName];
        if (info) {
            [_inspectorViewController setControllerData:info];
        }
    }
}

#pragma mark - XLUploadProgressSheetDelegate

- (void)uploadProgressSheet:(XLUploadProgressSheet *)sheet
     didCompleteWithResults:(NSArray<XLUploadResult *> *)results {
    _uploadProgressSheet = nil;

    // Refresh controller list to update status
    [_controllersViewController reloadData];
}

- (void)uploadProgressSheetDidCancel:(XLUploadProgressSheet *)sheet {
    _uploadProgressSheet = nil;
}

#pragma mark - Multi-Controller Upload

- (void)presentMultiControllerUploadDialog {
    _multiUploadDialog = [[XLMultiControllerUploadDialogController alloc] initWithEngineBridge:_engineBridge];
    _multiUploadDialog.delegate = self;
    [_multiUploadDialog presentAsSheetOnWindow:self.view.window];
}

#pragma mark - XLMultiControllerUploadDelegate

- (void)multiControllerUploadDialog:(XLMultiControllerUploadDialogController *)dialog
              didCompleteWithResults:(NSArray<XLMultiUploadControllerEntry *> *)results {
    _multiUploadDialog = nil;
    [_controllersViewController reloadData];
}

- (void)multiControllerUploadDialogDidCancel:(XLMultiControllerUploadDialogController *)dialog {
    _multiUploadDialog = nil;
}

#pragma mark - XLPortConfigurationViewDelegate

- (void)portConfigurationView:(XLPortConfigurationView *)view
          didSelectPortAtIndex:(NSInteger)index {
    // Could update a port details panel if we add one
}

- (void)portConfigurationView:(XLPortConfigurationView *)view
              didEditPortAtIndex:(NSInteger)index
                        property:(NSString *)property
                           value:(id)value {
    // Persist port change to engine
    // In production: OutputEngine::setPortConfig()
    NSLog(@"Port %ld property %@ changed to %@", (long)index, property, value);
}

- (void)portConfigurationView:(XLPortConfigurationView *)view
    didRequestAssignModelToPort:(NSInteger)portIndex {
    // Show model picker dialog
    NSArray<NSString *> *models = [_engineBridge getModelNames];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Assign Model to Port";
    alert.informativeText = @"Select a model:";

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 24) pullsDown:NO];
    [popup addItemsWithTitles:models];
    alert.accessoryView = popup;

    [alert addButtonWithTitle:@"Assign"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString *selectedModel = popup.selectedItem.title;
            // Apply assignment through the port view
            // The port view will update its data source and notify via delegate
        }
    }];
}

- (void)portConfigurationView:(XLPortConfigurationView *)view
                  didDropModel:(NSString *)modelName
                      onPortAtIndex:(NSInteger)portIndex {
    NSLog(@"Model %@ dropped on port %ld", modelName, (long)portIndex);
    // Persist to engine in production
}

- (void)portConfigurationView:(XLPortConfigurationView *)view
    didRequestRemoveModelAtIndex:(NSInteger)modelIndex
                    fromPortAtIndex:(NSInteger)portIndex {
    NSLog(@"Remove model from port %ld", (long)portIndex);
    // Persist to engine in production
}

- (void)portConfigurationView:(XLPortConfigurationView *)view
    didRequestShowValidationForPortAtIndex:(NSInteger)portIndex {
    const XLPortDataSource *ds = [view portDataSource];
    if (portIndex < 0 || portIndex >= ds->portCount) return;

    const XLPortEntry *port = &ds->ports[portIndex];

    NSString *message;
    if (port->validationMessage[0] != '\0') {
        message = [NSString stringWithUTF8String:port->validationMessage];
    } else {
        message = @"No validation issues found.";
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Port %d Validation", port->portNumber];
    alert.informativeText = message;
    alert.alertStyle = port->validationStatus == XLPortValidationError ? NSAlertStyleWarning : NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
}

#pragma mark - XLControllerInspectorDelegate

- (void)inspectorDidUpdateController:(XLControllerInspectorViewController *)inspector {
    // Refresh controller list and port configuration
    [_controllersViewController reloadData];

    NSString *selectedController = [_controllersViewController selectedControllerName];
    if (selectedController) {
        [_portConfigurationView loadPortsForController:selectedController];

        // Re-apply capabilities in case vendor/model/variant changed
        NSDictionary *info = [_engineBridge getControllerInfo:selectedController];
        [self applyCapabilitiesToPortConfigFromControllerInfo:info];
    }
}

@end
