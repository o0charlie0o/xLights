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
#import "setup/XLControllerInspectorViewController.h"

@interface XLSetupViewController () <XLControllerInspectorDelegate>

@property (nonatomic, strong, readwrite) XLControllersViewController *controllersViewController;
@property (nonatomic, strong, readwrite) XLPortConfigurationView *portConfigurationView;
@property (nonatomic, strong, readwrite) XLControllerInspectorViewController *inspectorViewController;
@property (nonatomic, strong) NSSplitViewController *splitViewController;

@end

@implementation XLSetupViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1200, 700)];
    view.wantsLayer = YES;
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];

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

    // Left pane: Controller list
    NSSplitViewItem *listItem = [NSSplitViewItem sidebarWithViewController:_controllersViewController];
    listItem.canCollapse = NO;
    listItem.minimumThickness = 280.0;
    listItem.maximumThickness = 400.0;
    [_splitViewController addSplitViewItem:listItem];

    // Center pane: Port configuration grid
    NSSplitViewItem *portItem = [NSSplitViewItem contentListWithViewController:_portConfigurationView];
    portItem.canCollapse = NO;
    portItem.minimumThickness = 450.0;
    [_splitViewController addSplitViewItem:portItem];

    // Right pane: Controller inspector
    NSSplitViewItem *inspectorItem = [NSSplitViewItem inspectorWithViewController:_inspectorViewController];
    inspectorItem.canCollapse = YES;
    inspectorItem.minimumThickness = 260.0;
    inspectorItem.maximumThickness = 400.0;
    [_splitViewController addSplitViewItem:inspectorItem];

    [self addChildViewController:_splitViewController];
    NSView *splitView = _splitViewController.view;
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:splitView];

    [NSLayoutConstraint activateConstraints:@[
        [splitView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [splitView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [splitView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [splitView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    // Register port view for model drags
    [_portConfigurationView registerForModelDrag];
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
    }
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
    didRequestUploadControllerAtIndex:(NSInteger)index {
    NSString *controllerName = controllersView.controllers[index][XLControllerColumnName];
    if (!controllerName) return;

    // Show upload progress
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Uploading Configuration";
    alert.informativeText = [NSString stringWithFormat:@"Uploading to %@...", controllerName];
    alert.alertStyle = NSAlertStyleInformational;

    // In production, this would call OutputEngine::uploadToController()
    // For now, show stub feedback
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
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
    }
}

@end
