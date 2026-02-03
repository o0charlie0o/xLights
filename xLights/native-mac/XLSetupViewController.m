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

@interface XLSetupViewController ()

@property (nonatomic, strong, readwrite) XLControllersViewController *controllersViewController;
@property (nonatomic, strong) NSSplitViewController *splitViewController;
@property (nonatomic, strong) NSView *detailPlaceholder;

@end

@implementation XLSetupViewController

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    view.wantsLayer = YES;
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _controllersViewController = [[XLControllersViewController alloc] init];
    _controllersViewController.engineBridge = _engineBridge;
    _controllersViewController.delegate = self;

    _splitViewController = [[NSSplitViewController alloc] init];
    _splitViewController.splitView.vertical = YES;
    _splitViewController.splitView.dividerStyle = NSSplitViewDividerStyleThin;

    NSSplitViewItem *listItem = [NSSplitViewItem splitViewItemWithViewController:_controllersViewController];
    listItem.canCollapse = NO;
    listItem.minimumThickness = 300.0;
    [_splitViewController addSplitViewItem:listItem];

    // Detail/inspector placeholder (will be replaced by ticket 2B)
    NSViewController *detailController = [[NSViewController alloc] init];
    _detailPlaceholder = [[NSView alloc] initWithFrame:NSZeroRect];
    _detailPlaceholder.wantsLayer = YES;
    _detailPlaceholder.layer.backgroundColor = [[NSColor colorWithWhite:0.16 alpha:1.0] CGColor];

    NSTextField *placeholder = [NSTextField labelWithString:@"Select a controller to view details"];
    placeholder.font = [NSFont systemFontOfSize:14 weight:NSFontWeightLight];
    placeholder.textColor = [NSColor tertiaryLabelColor];
    placeholder.alignment = NSTextAlignmentCenter;
    placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    [_detailPlaceholder addSubview:placeholder];
    [NSLayoutConstraint activateConstraints:@[
        [placeholder.centerXAnchor constraintEqualToAnchor:_detailPlaceholder.centerXAnchor],
        [placeholder.centerYAnchor constraintEqualToAnchor:_detailPlaceholder.centerYAnchor],
    ]];

    detailController.view = _detailPlaceholder;
    NSSplitViewItem *detailItem = [NSSplitViewItem splitViewItemWithViewController:detailController];
    detailItem.canCollapse = YES;
    detailItem.minimumThickness = 200.0;
    [_splitViewController addSplitViewItem:detailItem];

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
}

- (void)setEngineBridge:(XLEngineBridge *)engineBridge {
    _engineBridge = engineBridge;
    _controllersViewController.engineBridge = engineBridge;
}

#pragma mark - XLControllersViewDelegate

- (void)controllersView:(XLControllersViewController *)controllersView
    didSelectControllerAtIndex:(NSInteger)index {
    // Will update detail inspector (ticket 2B)
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
}

- (void)controllersView:(XLControllersViewController *)controllersView
    didRequestEditControllerAtIndex:(NSInteger)index {
    // Will open controller edit dialog (ticket 2B / 6B)
}

@end
