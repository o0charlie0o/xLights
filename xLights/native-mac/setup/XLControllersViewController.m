/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLControllersViewController.h"
#import "XLNetworkDiscoveryController.h"
#import "XLDiscoveryResultsViewController.h"
#import "../XLEngineBridge.h"

NSString * const XLControllerColumnName     = @"Name";
NSString * const XLControllerColumnProtocol = @"Protocol";
NSString * const XLControllerColumnAddress  = @"Address";
NSString * const XLControllerColumnChannels = @"Channels";
NSString * const XLControllerColumnVendor   = @"Vendor";
NSString * const XLControllerColumnModel    = @"Model";
NSString * const XLControllerColumnActive   = @"Active";
NSString * const XLControllerColumnStatus   = @"Status";

static NSString * const kDragType = @"org.xlights.controller.row";

static const CGFloat kFooterHeight = 32.0;
static const CGFloat kStatusDotSize = 8.0;

#pragma mark - Status Dot Drawing

/// Returns a status indicator image (filled circle) for the given controller status.
static NSImage *StatusDotImage(XLControllerStatus status) {
    NSColor *color;
    switch (status) {
        case XLControllerStatusOK:
        case XLControllerStatusWebOK:
            color = [NSColor systemGreenColor];
            break;
        case XLControllerStatusOpenFail:
            color = [NSColor systemRedColor];
            break;
        case XLControllerStatusOpen:
        case XLControllerStatusAliveOnly:
            color = [NSColor systemYellowColor];
            break;
        case XLControllerStatusUnavailable:
            color = [NSColor tertiaryLabelColor];
            break;
        case XLControllerStatusUnknown:
        default:
            color = [NSColor tertiaryLabelColor];
            break;
    }

    NSImage *image = [NSImage imageWithSize:NSMakeSize(kStatusDotSize, kStatusDotSize)
                                    flipped:NO
                             drawingHandler:^BOOL(NSRect dstRect) {
        [color setFill];
        [[NSBezierPath bezierPathWithOvalInRect:dstRect] fill];
        return YES;
    }];
    image.accessibilityDescription = [NSString stringWithFormat:@"Status: %ld", (long)status];
    return image;
}

#pragma mark - XLControllersViewController

@interface XLControllersViewController ()

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong, readwrite) NSTableView *tableView;
@property (nonatomic, strong, readwrite) NSArray<NSDictionary *> *controllers;
@property (nonatomic, strong) NSView *footerView;
@property (nonatomic, strong) NSButton *addButton;
@property (nonatomic, strong) NSButton *removeButton;
@property (nonatomic, strong) NSButton *discoverButton;
@property (nonatomic, strong) NSProgressIndicator *discoverSpinner;
@property (nonatomic, assign) BOOL sortAscending;
@property (nonatomic, strong) NSString *sortColumnIdentifier;
@property (nonatomic, strong, readwrite) XLNetworkDiscoveryController *discoveryController;
@property (nonatomic, strong) NSPopover *discoveryPopover;
@property (nonatomic, strong) XLDiscoveryResultsViewController *discoveryResultsViewController;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *pingStatusCache;

@end

@implementation XLControllersViewController

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _controllers = @[];
        _sortAscending = YES;
        _sortColumnIdentifier = XLControllerColumnName;
        _pingStatusCache = [NSMutableDictionary dictionary];

        // Initialize discovery controller
        _discoveryController = [[XLNetworkDiscoveryController alloc] init];
        _discoveryController.delegate = self;
    }
    return self;
}

- (void)dealloc {
    _tableView.dataSource = nil;
    _tableView.delegate = nil;
    [_discoveryController stopBackgroundPing];
}

- (void)loadView {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 700, 400)];
    container.wantsLayer = YES;

    [self setupTableView];
    [self setupFooter];

    [container addSubview:_scrollView];
    [container addSubview:_footerView];

    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _footerView.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_footerView.topAnchor],

        [_footerView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_footerView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_footerView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [_footerView.heightAnchor constraintEqualToConstant:kFooterHeight],
    ]];

    self.view = container;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _discoveryController.engineBridge = _engineBridge;
    [self reloadData];

    // Start background ping monitoring
    [_discoveryController startBackgroundPing];
}

- (void)setEngineBridge:(XLEngineBridge *)engineBridge {
    _engineBridge = engineBridge;
    _discoveryController.engineBridge = engineBridge;
}

#pragma mark - Table View Setup

- (void)setupTableView {
    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.borderType = NSNoBorder;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.allowsMultipleSelection = YES;
    _tableView.allowsColumnReordering = YES;
    _tableView.allowsColumnResizing = YES;
    _tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    _tableView.rowSizeStyle = NSTableViewRowSizeStyleDefault;
    _tableView.doubleAction = @selector(tableViewDoubleClicked:);
    _tableView.target = self;

    if (@available(macOS 11.0, *)) {
        _tableView.style = NSTableViewStyleInset;
    }

    [_tableView registerForDraggedTypes:@[kDragType]];

    [self addColumn:XLControllerColumnName     title:@"Name"       minWidth:120 maxWidth:400 defaultWidth:180];
    [self addColumn:XLControllerColumnProtocol title:@"Protocol"   minWidth:60  maxWidth:120 defaultWidth:80];
    [self addColumn:XLControllerColumnAddress  title:@"Address"    minWidth:80  maxWidth:200 defaultWidth:130];
    [self addColumn:XLControllerColumnChannels title:@"Channels"   minWidth:60  maxWidth:160 defaultWidth:100];
    [self addColumn:XLControllerColumnVendor   title:@"Vendor"     minWidth:60  maxWidth:160 defaultWidth:100];
    [self addColumn:XLControllerColumnModel    title:@"Model"      minWidth:60  maxWidth:160 defaultWidth:100];
    [self addColumn:XLControllerColumnActive   title:@"Active"     minWidth:50  maxWidth:100 defaultWidth:60];
    [self addColumn:XLControllerColumnStatus   title:@""           minWidth:24  maxWidth:32  defaultWidth:28];

    _scrollView.documentView = _tableView;

    _tableView.menu = [self buildContextMenu];
}

- (void)addColumn:(NSString *)identifier
            title:(NSString *)title
         minWidth:(CGFloat)minWidth
         maxWidth:(CGFloat)maxWidth
     defaultWidth:(CGFloat)defaultWidth {
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
    column.title = title;
    column.minWidth = minWidth;
    column.maxWidth = maxWidth;
    column.width = defaultWidth;
    column.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:identifier
                                                                  ascending:YES
                                                                   selector:@selector(localizedCaseInsensitiveCompare:)];
    [_tableView addTableColumn:column];
}

#pragma mark - Footer (Add/Remove Buttons)

- (void)setupFooter {
    _footerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _footerView.wantsLayer = YES;
    _footerView.layer.backgroundColor = CGColorCreateGenericGray(0.18, 1.0);

    NSView *separator = [[NSView alloc] initWithFrame:NSZeroRect];
    separator.wantsLayer = YES;
    separator.layer.backgroundColor = CGColorCreateGenericGray(0.3, 1.0);
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [_footerView addSubview:separator];

    _addButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"plus"
                                                     accessibilityDescription:@"Add Controller"]
                                    target:self
                                    action:@selector(addButtonClicked:)];
    _addButton.bezelStyle = NSBezelStyleSmallSquare;
    _addButton.bordered = NO;
    _addButton.translatesAutoresizingMaskIntoConstraints = NO;

    _removeButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"minus"
                                                       accessibilityDescription:@"Remove Controller"]
                                       target:self
                                       action:@selector(removeButtonClicked:)];
    _removeButton.bezelStyle = NSBezelStyleSmallSquare;
    _removeButton.bordered = NO;
    _removeButton.translatesAutoresizingMaskIntoConstraints = NO;

    // Discover button with network scanning icon
    _discoverButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"antenna.radiowaves.left.and.right"
                                                          accessibilityDescription:@"Discover Controllers"]
                                         target:self
                                         action:@selector(discoverButtonClicked:)];
    _discoverButton.bezelStyle = NSBezelStyleSmallSquare;
    _discoverButton.bordered = NO;
    _discoverButton.toolTip = @"Discover controllers on the network";
    _discoverButton.translatesAutoresizingMaskIntoConstraints = NO;

    // Spinner for discovery progress
    _discoverSpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _discoverSpinner.style = NSProgressIndicatorStyleSpinning;
    _discoverSpinner.controlSize = NSControlSizeSmall;
    _discoverSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _discoverSpinner.hidden = YES;

    [_footerView addSubview:_addButton];
    [_footerView addSubview:_removeButton];
    [_footerView addSubview:_discoverButton];
    [_footerView addSubview:_discoverSpinner];

    [NSLayoutConstraint activateConstraints:@[
        [separator.topAnchor constraintEqualToAnchor:_footerView.topAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:_footerView.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:_footerView.trailingAnchor],
        [separator.heightAnchor constraintEqualToConstant:1.0],

        [_addButton.leadingAnchor constraintEqualToAnchor:_footerView.leadingAnchor constant:4.0],
        [_addButton.centerYAnchor constraintEqualToAnchor:_footerView.centerYAnchor],
        [_addButton.widthAnchor constraintEqualToConstant:24.0],
        [_addButton.heightAnchor constraintEqualToConstant:24.0],

        [_removeButton.leadingAnchor constraintEqualToAnchor:_addButton.trailingAnchor constant:2.0],
        [_removeButton.centerYAnchor constraintEqualToAnchor:_footerView.centerYAnchor],
        [_removeButton.widthAnchor constraintEqualToConstant:24.0],
        [_removeButton.heightAnchor constraintEqualToConstant:24.0],

        // Discover button on the right side of the footer
        [_discoverButton.trailingAnchor constraintEqualToAnchor:_footerView.trailingAnchor constant:-4.0],
        [_discoverButton.centerYAnchor constraintEqualToAnchor:_footerView.centerYAnchor],
        [_discoverButton.widthAnchor constraintEqualToConstant:24.0],
        [_discoverButton.heightAnchor constraintEqualToConstant:24.0],

        // Spinner replaces discover button icon during scanning
        [_discoverSpinner.centerXAnchor constraintEqualToAnchor:_discoverButton.centerXAnchor],
        [_discoverSpinner.centerYAnchor constraintEqualToAnchor:_discoverButton.centerYAnchor],
        [_discoverSpinner.widthAnchor constraintEqualToConstant:16.0],
        [_discoverSpinner.heightAnchor constraintEqualToConstant:16.0],
    ]];
}

#pragma mark - Context Menu

- (NSMenu *)buildContextMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Controller Actions"];

    [menu addItemWithTitle:@"Edit Controller" action:@selector(contextEditController:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Add Ethernet Controller" action:@selector(contextAddEthernet:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Add Serial Controller" action:@selector(contextAddSerial:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Add NULL Controller" action:@selector(contextAddNull:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *activateItem = [menu addItemWithTitle:@"Activate" action:@selector(contextActivate:) keyEquivalent:@""];
    activateItem.tag = 1;
    NSMenuItem *activateXLItem = [menu addItemWithTitle:@"Activate in xLights Only" action:@selector(contextActivateXLightsOnly:) keyEquivalent:@""];
    activateXLItem.tag = 2;
    NSMenuItem *deactivateItem = [menu addItemWithTitle:@"Deactivate" action:@selector(contextDeactivate:) keyEquivalent:@""];
    deactivateItem.tag = 3;

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Delete Controller" action:@selector(contextDeleteController:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Upload Configuration" action:@selector(contextUploadConfig:) keyEquivalent:@""];

    NSMenu *sortMenu = [[NSMenu alloc] initWithTitle:@"Sort"];
    [sortMenu addItemWithTitle:@"by Name" action:@selector(sortByName:) keyEquivalent:@""];
    [sortMenu addItemWithTitle:@"by IP" action:@selector(sortByAddress:) keyEquivalent:@""];
    [sortMenu addItemWithTitle:@"by Protocol" action:@selector(sortByProtocol:) keyEquivalent:@""];
    [sortMenu addItemWithTitle:@"by Vendor" action:@selector(sortByVendor:) keyEquivalent:@""];
    NSMenuItem *sortItem = [[NSMenuItem alloc] initWithTitle:@"Sort" action:nil keyEquivalent:@""];
    sortItem.submenu = sortMenu;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:sortItem];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Discover Controllers..." action:@selector(discoverButtonClicked:) keyEquivalent:@""];

    return menu;
}

#pragma mark - Data Loading

- (void)reloadData {
    NSMutableArray<NSDictionary *> *newControllers = [NSMutableArray array];

    NSArray<NSString *> *controllerNames = [_engineBridge getControllerNames];
    for (NSString *name in controllerNames) {
        NSDictionary *info = [_engineBridge getControllerInfo:name];
        if (info) {
            NSMutableDictionary *row = [NSMutableDictionary dictionaryWithDictionary:info];
            row[XLControllerColumnName] = name;
            if (!row[XLControllerColumnProtocol]) row[XLControllerColumnProtocol] = @"";
            if (!row[XLControllerColumnAddress])  row[XLControllerColumnAddress]  = @"";
            if (!row[XLControllerColumnChannels]) row[XLControllerColumnChannels] = @"";
            if (!row[XLControllerColumnVendor])   row[XLControllerColumnVendor]   = @"";
            if (!row[XLControllerColumnModel])    row[XLControllerColumnModel]    = @"";
            if (!row[XLControllerColumnActive])   row[XLControllerColumnActive]   = @"Active";
            if (!row[XLControllerColumnStatus])   row[XLControllerColumnStatus]   = @(XLControllerStatusUnknown);
            [newControllers addObject:[row copy]];
        }
    }

    _controllers = [newControllers copy];
    [self sortControllersIfNeeded];
    [_tableView reloadData];
    [self updateRemoveButtonState];
}

- (void)sortControllersIfNeeded {
    if (_sortColumnIdentifier && _controllers.count > 1) {
        _controllers = [_controllers sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSString *va = a[self->_sortColumnIdentifier] ?: @"";
            NSString *vb = b[self->_sortColumnIdentifier] ?: @"";
            if ([va isKindOfClass:[NSNumber class]]) va = [(NSNumber *)va stringValue];
            if ([vb isKindOfClass:[NSNumber class]]) vb = [(NSNumber *)vb stringValue];
            NSComparisonResult result = [va localizedCaseInsensitiveCompare:vb];
            return self->_sortAscending ? result : -result;
        }];
    }
}

#pragma mark - Selection

- (void)selectControllerAtIndex:(NSInteger)index {
    if (index >= 0 && index < (NSInteger)_controllers.count) {
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:index];
        [_tableView selectRowIndexes:indexSet byExtendingSelection:NO];
        [_tableView scrollRowToVisible:index];
    } else {
        [_tableView deselectAll:nil];
    }
}

- (NSInteger)selectedControllerIndex {
    return _tableView.selectedRow;
}

- (NSString *)selectedControllerName {
    NSInteger index = _tableView.selectedRow;
    if (index >= 0 && index < (NSInteger)_controllers.count) {
        return _controllers[index][XLControllerColumnName];
    }
    return nil;
}

- (void)updateRemoveButtonState {
    _removeButton.enabled = (_tableView.selectedRow >= 0);
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _controllers ? (NSInteger)_controllers.count : 0;
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
    row:(NSInteger)row {
    if (!_controllers || row < 0 || row >= (NSInteger)_controllers.count) return nil;
    return _controllers[row][tableColumn.identifier];
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView
    viewForTableColumn:(NSTableColumn *)tableColumn
                   row:(NSInteger)row {
    if (!_controllers || row < 0 || row >= (NSInteger)_controllers.count) return nil;

    NSString *identifier = tableColumn.identifier;
    NSDictionary *controller = _controllers[row];

    if ([identifier isEqualToString:XLControllerColumnStatus]) {
        return [self statusCellForRow:row controller:controller reusingView:
                [tableView makeViewWithIdentifier:@"StatusCell" owner:self]];
    }

    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [self makeTextCellWithIdentifier:identifier];
    }

    NSString *value = controller[identifier];
    if ([value isKindOfClass:[NSNumber class]]) {
        value = [(NSNumber *)value stringValue];
    }
    cell.textField.stringValue = value ?: @"";

    // Dim inactive controllers
    NSString *activeState = controller[XLControllerColumnActive];
    if ([activeState isEqualToString:@"Inactive"]) {
        cell.textField.textColor = [NSColor tertiaryLabelColor];
    } else {
        cell.textField.textColor = [NSColor labelColor];
    }

    return cell;
}

- (NSTableCellView *)makeTextCellWithIdentifier:(NSString *)identifier {
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
    cell.identifier = identifier;

    NSTextField *textField = [NSTextField labelWithString:@""];
    textField.lineBreakMode = NSLineBreakByTruncatingTail;
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:textField];
    cell.textField = textField;

    [NSLayoutConstraint activateConstraints:@[
        [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4.0],
        [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4.0],
        [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];

    return cell;
}

- (NSView *)statusCellForRow:(NSInteger)row
                  controller:(NSDictionary *)controller
                 reusingView:(NSView *)existingView {
    NSTableCellView *cell = (NSTableCellView *)existingView;
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"StatusCell";

        NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:imageView];
        cell.imageView = imageView;

        [NSLayoutConstraint activateConstraints:@[
            [imageView.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor],
            [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [imageView.widthAnchor constraintEqualToConstant:kStatusDotSize],
            [imageView.heightAnchor constraintEqualToConstant:kStatusDotSize],
        ]];
    }

    // Check ping status cache first, then fall back to controller data
    NSString *name = controller[XLControllerColumnName];
    XLControllerStatus status = XLControllerStatusUnknown;

    if (name && _pingStatusCache[name]) {
        status = (XLControllerStatus)_pingStatusCache[name].integerValue;
    } else {
        NSNumber *statusNumber = controller[XLControllerColumnStatus];
        status = statusNumber ? (XLControllerStatus)statusNumber.integerValue : XLControllerStatusUnknown;
    }

    cell.imageView.image = StatusDotImage(status);

    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateRemoveButtonState];

    NSInteger selected = _tableView.selectedRow;
    if ([_delegate respondsToSelector:@selector(controllersView:didSelectControllerAtIndex:)]) {
        [_delegate controllersView:self didSelectControllerAtIndex:selected];
    }
}

- (NSArray<NSTableViewRowAction *> *)tableView:(NSTableView *)tableView
                          rowActionsForRow:(NSInteger)row
                                      edge:(NSTableRowActionEdge)edge {
    if (edge == NSTableRowActionEdgeTrailing) {
        NSTableViewRowAction *deleteAction = [NSTableViewRowAction rowActionWithStyle:NSTableViewRowActionStyleDestructive
            title:@"Delete"
            handler:^(NSTableViewRowAction *action, NSInteger actionRow) {
                [self confirmDeleteControllerAtIndex:actionRow];
            }];
        return @[deleteAction];
    }
    return @[];
}

#pragma mark - Drag and Drop Reordering

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView
              pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setString:[NSString stringWithFormat:@"%ld", (long)row] forType:kDragType];
    return item;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    if (dropOperation == NSTableViewDropAbove) {
        return NSDragOperationMove;
    }
    return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation {
    NSPasteboardItem *item = info.draggingPasteboard.pasteboardItems.firstObject;
    NSString *rowStr = [item stringForType:kDragType];
    if (!rowStr) return NO;

    NSInteger fromRow = [rowStr integerValue];
    if (fromRow == row || fromRow == row - 1) return NO;

    if ([_delegate respondsToSelector:@selector(controllersView:didMoveControllerFromIndex:toIndex:)]) {
        [_delegate controllersView:self didMoveControllerFromIndex:fromRow toIndex:row];
    }

    [self reloadData];
    return YES;
}

#pragma mark - Column Sorting

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors {
    NSSortDescriptor *descriptor = tableView.sortDescriptors.firstObject;
    if (descriptor) {
        _sortColumnIdentifier = descriptor.key;
        _sortAscending = descriptor.ascending;
        [self sortControllersIfNeeded];
        [_tableView reloadData];
    }
}

#pragma mark - Double-Click

- (void)tableViewDoubleClicked:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) return;

    if ([_delegate respondsToSelector:@selector(controllersView:didRequestEditControllerAtIndex:)]) {
        [_delegate controllersView:self didRequestEditControllerAtIndex:row];
    }
}

#pragma mark - Footer Button Actions

- (void)addButtonClicked:(id)sender {
    NSMenu *addMenu = [[NSMenu alloc] initWithTitle:@"Add Controller"];
    [addMenu addItemWithTitle:@"Ethernet (E1.31/ArtNet/DDP/ZCPP)" action:@selector(contextAddEthernet:) keyEquivalent:@""];
    [addMenu addItemWithTitle:@"Serial (DMX/LOR/Renard)" action:@selector(contextAddSerial:) keyEquivalent:@""];
    [addMenu addItemWithTitle:@"NULL" action:@selector(contextAddNull:) keyEquivalent:@""];

    NSPoint location = NSMakePoint(0, _addButton.bounds.size.height);
    [addMenu popUpMenuPositioningItem:nil atLocation:location inView:_addButton];
}

- (void)removeButtonClicked:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row < 0) return;
    [self confirmDeleteControllerAtIndex:row];
}

#pragma mark - Context Menu Actions

- (void)contextEditController:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0) return;

    if ([_delegate respondsToSelector:@selector(controllersView:didRequestEditControllerAtIndex:)]) {
        [_delegate controllersView:self didRequestEditControllerAtIndex:row];
    }
}

- (void)contextAddEthernet:(id)sender {
    if ([_delegate respondsToSelector:@selector(controllersView:didRequestAddController:)]) {
        [_delegate controllersView:self didRequestAddController:XLControllerTypeEthernet];
    }
}

- (void)contextAddSerial:(id)sender {
    if ([_delegate respondsToSelector:@selector(controllersView:didRequestAddController:)]) {
        [_delegate controllersView:self didRequestAddController:XLControllerTypeSerial];
    }
}

- (void)contextAddNull:(id)sender {
    if ([_delegate respondsToSelector:@selector(controllersView:didRequestAddController:)]) {
        [_delegate controllersView:self didRequestAddController:XLControllerTypeNull];
    }
}

- (void)contextActivate:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0) return;

    if ([_delegate respondsToSelector:@selector(controllersView:didRequestSetActive:forControllerAtIndex:)]) {
        [_delegate controllersView:self didRequestSetActive:@"Active" forControllerAtIndex:row];
    }
}

- (void)contextActivateXLightsOnly:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0) return;

    if ([_delegate respondsToSelector:@selector(controllersView:didRequestSetActive:forControllerAtIndex:)]) {
        [_delegate controllersView:self didRequestSetActive:@"xLights Only" forControllerAtIndex:row];
    }
}

- (void)contextDeactivate:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0) return;

    if ([_delegate respondsToSelector:@selector(controllersView:didRequestSetActive:forControllerAtIndex:)]) {
        [_delegate controllersView:self didRequestSetActive:@"Inactive" forControllerAtIndex:row];
    }
}

- (void)contextDeleteController:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0) return;
    [self confirmDeleteControllerAtIndex:row];
}

- (void)contextUploadConfig:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0) return;

    if ([_delegate respondsToSelector:@selector(controllersView:didRequestUploadControllerAtIndex:)]) {
        [_delegate controllersView:self didRequestUploadControllerAtIndex:row];
    }
}

#pragma mark - Sort Menu Actions

- (void)sortByName:(id)sender {
    _sortColumnIdentifier = XLControllerColumnName;
    _sortAscending = YES;
    [self sortControllersIfNeeded];
    [_tableView reloadData];
}

- (void)sortByAddress:(id)sender {
    _sortColumnIdentifier = XLControllerColumnAddress;
    _sortAscending = YES;
    [self sortControllersIfNeeded];
    [_tableView reloadData];
}

- (void)sortByProtocol:(id)sender {
    _sortColumnIdentifier = XLControllerColumnProtocol;
    _sortAscending = YES;
    [self sortControllersIfNeeded];
    [_tableView reloadData];
}

- (void)sortByVendor:(id)sender {
    _sortColumnIdentifier = XLControllerColumnVendor;
    _sortAscending = YES;
    [self sortControllersIfNeeded];
    [_tableView reloadData];
}

#pragma mark - Delete Confirmation

- (void)confirmDeleteControllerAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_controllers.count) return;

    NSString *name = _controllers[index][XLControllerColumnName] ?: @"this controller";
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Delete \"%@\"?", name];
    alert.informativeText = @"This action cannot be undone.";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            if ([self.delegate respondsToSelector:@selector(controllersView:didRequestDeleteControllerAtIndex:)]) {
                [self.delegate controllersView:self didRequestDeleteControllerAtIndex:index];
            }
        }
    }];
}

#pragma mark - Menu Validation

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;

    SEL action = menuItem.action;

    if (action == @selector(contextEditController:) ||
        action == @selector(contextDeleteController:) ||
        action == @selector(contextActivate:) ||
        action == @selector(contextActivateXLightsOnly:) ||
        action == @selector(contextDeactivate:) ||
        action == @selector(contextUploadConfig:)) {
        return (row >= 0);
    }

    return YES;
}

#pragma mark - Network Discovery

- (void)discoverButtonClicked:(id)sender {
    [self startDiscovery];
}

- (void)startDiscovery {
    // Show discovery popover
    if (!_discoveryResultsViewController) {
        _discoveryResultsViewController = [[XLDiscoveryResultsViewController alloc] init];
        _discoveryResultsViewController.delegate = self;
        _discoveryResultsViewController.discoveryController = _discoveryController;
    }

    if (!_discoveryPopover) {
        _discoveryPopover = [[NSPopover alloc] init];
        _discoveryPopover.behavior = NSPopoverBehaviorSemitransient;
        _discoveryPopover.contentViewController = _discoveryResultsViewController;
    }

    // Show the popover anchored to the discover button
    [_discoveryPopover showRelativeToRect:_discoverButton.bounds
                                   ofView:_discoverButton
                            preferredEdge:NSMaxYEdge];

    // Start discovery
    [_discoveryController startDiscovery];
}

- (void)updatePingStatus:(XLControllerStatus)status forControllerNamed:(NSString *)name {
    if (!name) return;

    _pingStatusCache[name] = @(status);

    // Find the row for this controller and refresh it
    NSInteger rowIndex = -1;
    for (NSUInteger i = 0; i < _controllers.count; i++) {
        if ([_controllers[i][XLControllerColumnName] isEqualToString:name]) {
            rowIndex = (NSInteger)i;
            break;
        }
    }

    if (rowIndex >= 0) {
        NSIndexSet *rowSet = [NSIndexSet indexSetWithIndex:rowIndex];
        NSIndexSet *columnSet = [NSIndexSet indexSetWithIndex:[_tableView columnWithIdentifier:XLControllerColumnStatus]];
        [_tableView reloadDataForRowIndexes:rowSet columnIndexes:columnSet];
    }
}

#pragma mark - XLNetworkDiscoveryDelegate

- (void)discoveryController:(XLNetworkDiscoveryController *)controller
         didChangeState:(XLDiscoveryState)state {
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (state) {
            case XLDiscoveryStateScanning:
                self->_discoverSpinner.hidden = NO;
                [self->_discoverSpinner startAnimation:nil];
                self->_discoverButton.image = nil;
                break;

            case XLDiscoveryStateComplete:
            case XLDiscoveryStateFailed:
            case XLDiscoveryStateIdle:
                [self->_discoverSpinner stopAnimation:nil];
                self->_discoverSpinner.hidden = YES;
                self->_discoverButton.image = [NSImage imageWithSystemSymbolName:@"antenna.radiowaves.left.and.right"
                                                        accessibilityDescription:@"Discover Controllers"];
                break;
        }

        [self->_discoveryResultsViewController setDiscoveryState:state];
    });
}

- (void)discoveryController:(XLNetworkDiscoveryController *)controller
   didDiscoverControllers:(const XLDiscoveredController *)controllers
                    count:(NSUInteger)count {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_discoveryResultsViewController reloadResults];
    });
}

- (void)discoveryController:(XLNetworkDiscoveryController *)controller
       didFailWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Discovery Failed";
        alert.informativeText = error.localizedDescription ?: @"An unknown error occurred during network discovery.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    });
}

- (void)discoveryController:(XLNetworkDiscoveryController *)controller
     didUpdatePingStatus:(XLPingState)status
       forControllerName:(NSString *)name {
    // Convert XLPingState to XLControllerStatus
    XLControllerStatus controllerStatus;
    switch (status) {
        case XLPingStateOK:
            controllerStatus = XLControllerStatusOK;
            break;
        case XLPingStateWebOK:
            controllerStatus = XLControllerStatusWebOK;
            break;
        case XLPingStateOpen:
        case XLPingStateOpened:
            controllerStatus = XLControllerStatusOpen;
            break;
        case XLPingStateAllFailed:
            controllerStatus = XLControllerStatusOpenFail;
            break;
        case XLPingStateUnavailable:
            controllerStatus = XLControllerStatusUnavailable;
            break;
        case XLPingStateUnknown:
        default:
            controllerStatus = XLControllerStatusUnknown;
            break;
    }

    [self updatePingStatus:controllerStatus forControllerNamed:name];
}

#pragma mark - XLDiscoveryResultsDelegate

- (void)discoveryResults:(XLDiscoveryResultsViewController *)controller
    didRequestAddControllers:(NSArray<NSNumber *> *)controllerIndices {
    for (NSNumber *indexNum in controllerIndices) {
        NSUInteger index = indexNum.unsignedIntegerValue;
        [_discoveryController addDiscoveredControllerAtIndex:index];
    }

    // Refresh controller list after adding
    [self reloadData];

    // Close the popover
    [_discoveryPopover close];
}

- (void)discoveryResultsDidDismiss:(XLDiscoveryResultsViewController *)controller {
    [_discoveryPopover close];
}

- (void)discoveryResultsDidRequestRescan:(XLDiscoveryResultsViewController *)controller {
    [_discoveryController startDiscovery];
}

@end
