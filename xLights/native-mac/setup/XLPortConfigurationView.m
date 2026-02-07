/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLPortConfigurationView.h"
#import "../XLEngineBridge.h"
#import <string.h>
#import <objc/runtime.h>

#pragma mark - Column Identifiers

NSString * const XLPortColumnPort        = @"Port";
NSString * const XLPortColumnType        = @"Type";
NSString * const XLPortColumnProtocol    = @"Protocol";
NSString * const XLPortColumnModel       = @"Model";
NSString * const XLPortColumnStartChannel = @"Start Ch";
NSString * const XLPortColumnChannels    = @"Channels";
NSString * const XLPortColumnPixels      = @"Pixels";
NSString * const XLPortColumnBrightness  = @"Brightness";
NSString * const XLPortColumnGamma       = @"Gamma";
NSString * const XLPortColumnColorOrder  = @"Color Order";
NSString * const XLPortColumnNullPixels  = @"Null Px";
NSString * const XLPortColumnSmartRemote = @"Smart Remote";
NSString * const XLPortColumnStatus      = @"Status";

static NSString * const kModelDragType = @"org.xlights.model.name";

static const CGFloat kRowHeight = 24.0;
static const CGFloat kStatusDotSize = 10.0;

#pragma mark - Helper Functions

/// Copy a C string safely to a fixed buffer.
static void SafeStringCopy(char *dest, size_t destSize, NSString *src) {
    if (!src) {
        dest[0] = '\0';
        return;
    }
    const char *utf8 = [src UTF8String];
    if (utf8) {
        strncpy(dest, utf8, destSize - 1);
        dest[destSize - 1] = '\0';
    } else {
        dest[0] = '\0';
    }
}

/// Convert C string to NSString.
static NSString *StringFromCString(const char *cstr) {
    if (!cstr || cstr[0] == '\0') return @"";
    return [NSString stringWithUTF8String:cstr];
}

/// Initialize a port entry with default values.
static void InitPortEntry(XLPortEntry *entry, int portNum, XLPortType type) {
    memset(entry, 0, sizeof(XLPortEntry));
    entry->portNumber = portNum;
    entry->portType = type;
    entry->brightness = 100;
    entry->gamma = 1.0f;
    entry->groupCount = 1;
    SafeStringCopy(entry->colorOrder, XL_PORT_MAX_STRING_LEN, @"RGB");
    SafeStringCopy(entry->protocol, XL_PORT_MAX_STRING_LEN, type == XLPortTypePixel ? @"ws2811" : @"DMX");
    entry->validationStatus = XLPortValidationOK;
}

/// Initialize the port data source.
static void InitPortDataSource(XLPortDataSource *ds) {
    memset(ds, 0, sizeof(XLPortDataSource));
}

#pragma mark - Status Indicator

/// Returns a status indicator image for port validation status.
static NSImage *StatusIndicatorImage(XLPortValidationStatus status) {
    NSColor *color;
    switch (status) {
        case XLPortValidationOK:
            color = [NSColor systemGreenColor];
            break;
        case XLPortValidationWarning:
            color = [NSColor systemYellowColor];
            break;
        case XLPortValidationError:
            color = [NSColor systemRedColor];
            break;
    }

    NSImage *image = [NSImage imageWithSize:NSMakeSize(kStatusDotSize, kStatusDotSize)
                                    flipped:NO
                             drawingHandler:^BOOL(NSRect dstRect) {
        [color setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(dstRect, 1, 1)] fill];
        return YES;
    }];
    return image;
}

#pragma mark - XLPortConfigurationView

@interface XLPortConfigurationView () <NSTextFieldDelegate>

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong, readwrite) NSTableView *tableView;
@property (nonatomic, copy, readwrite) NSString *controllerName;
@property (nonatomic, strong) NSView *headerView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSPopUpButton *portFilterPopup;
@property (nonatomic, strong) NSArray<NSString *> *filteredPixelProtocols;
@property (nonatomic, strong) NSArray<NSString *> *filteredSerialProtocols;

@end

@implementation XLPortConfigurationView {
    XLPortDataSource _dataSource;
}

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        InitPortDataSource(&_dataSource);
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"XLChannelsDidRecalculateNotification" object:nil];
    _tableView.dataSource = nil;
    _tableView.delegate = nil;
}

- (void)loadView {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 400)];
    container.wantsLayer = YES;

    [self setupHeader];
    [self setupTableView];

    [container addSubview:_headerView];
    [container addSubview:_scrollView];

    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [_headerView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [_headerView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_headerView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_headerView.heightAnchor constraintEqualToConstant:32.0],

        [_scrollView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    self.view = container;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(channelsDidRecalculate:)
                                                 name:@"XLChannelsDidRecalculateNotification"
                                               object:nil];
}

- (void)channelsDidRecalculate:(NSNotification *)notification {
    [self reloadData];
}

#pragma mark - Header Setup

- (void)setupHeader {
    _headerView = [[NSView alloc] initWithFrame:NSZeroRect];
    _headerView.wantsLayer = YES;
    _headerView.layer.backgroundColor = CGColorCreateGenericGray(0.15, 1.0);

    _titleLabel = [NSTextField labelWithString:@"Port Configuration"];
    _titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _titleLabel.textColor = [NSColor secondaryLabelColor];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _portFilterPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_portFilterPopup addItemsWithTitles:@[@"All Ports", @"Pixel Ports", @"Serial Ports", @"Assigned Only", @"Unassigned Only"]];
    _portFilterPopup.font = [NSFont systemFontOfSize:11];
    _portFilterPopup.target = self;
    _portFilterPopup.action = @selector(filterChanged:);
    _portFilterPopup.translatesAutoresizingMaskIntoConstraints = NO;

    [_headerView addSubview:_titleLabel];
    [_headerView addSubview:_portFilterPopup];

    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:8.0],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],

        [_portFilterPopup.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-8.0],
        [_portFilterPopup.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_portFilterPopup.widthAnchor constraintEqualToConstant:130.0],
    ]];
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
    _tableView.allowsMultipleSelection = NO;
    _tableView.allowsColumnReordering = YES;
    _tableView.allowsColumnResizing = YES;
    _tableView.rowHeight = kRowHeight;
    _tableView.gridStyleMask = NSTableViewSolidVerticalGridLineMask;

    if (@available(macOS 11.0, *)) {
        _tableView.style = NSTableViewStyleInset;
    }

    // Add columns
    [self addColumn:XLPortColumnPort        title:@"Port"        minWidth:40  maxWidth:60   width:50   editable:NO];
    [self addColumn:XLPortColumnType        title:@"Type"        minWidth:50  maxWidth:80   width:60   editable:NO];
    [self addColumn:XLPortColumnProtocol    title:@"Protocol"    minWidth:60  maxWidth:100  width:80   editable:YES];
    [self addColumn:XLPortColumnModel       title:@"Model"       minWidth:100 maxWidth:300  width:150  editable:NO];
    [self addColumn:XLPortColumnStartChannel title:@"Start Ch"   minWidth:60  maxWidth:100  width:70   editable:YES];
    [self addColumn:XLPortColumnChannels    title:@"Channels"    minWidth:60  maxWidth:100  width:70   editable:NO];
    [self addColumn:XLPortColumnPixels      title:@"Pixels"      minWidth:50  maxWidth:80   width:60   editable:NO];
    [self addColumn:XLPortColumnBrightness  title:@"Bright%"     minWidth:50  maxWidth:80   width:60   editable:YES];
    [self addColumn:XLPortColumnGamma       title:@"Gamma"       minWidth:50  maxWidth:80   width:60   editable:YES];
    [self addColumn:XLPortColumnColorOrder  title:@"Color"       minWidth:50  maxWidth:80   width:60   editable:YES];
    [self addColumn:XLPortColumnNullPixels  title:@"Null"        minWidth:40  maxWidth:60   width:50   editable:YES];
    [self addColumn:XLPortColumnSmartRemote title:@"SR"          minWidth:40  maxWidth:60   width:50   editable:YES];
    [self addColumn:XLPortColumnStatus      title:@""            minWidth:24  maxWidth:32   width:28   editable:NO];

    _scrollView.documentView = _tableView;

    // Context menu
    _tableView.menu = [self buildContextMenu];
}

- (void)addColumn:(NSString *)identifier
            title:(NSString *)title
         minWidth:(CGFloat)minWidth
         maxWidth:(CGFloat)maxWidth
            width:(CGFloat)width
         editable:(BOOL)editable {
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
    column.title = title;
    column.minWidth = minWidth;
    column.maxWidth = maxWidth;
    column.width = width;
    column.editable = editable;
    column.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:identifier
                                                                   ascending:YES
                                                                    selector:@selector(compare:)];
    [_tableView addTableColumn:column];
}

#pragma mark - Context Menu

- (NSMenu *)buildContextMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Port Actions"];

    [menu addItemWithTitle:@"Assign Model..." action:@selector(contextAssignModel:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Remove Model" action:@selector(contextRemoveModel:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Set Protocol..." action:@selector(contextSetProtocol:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Set Brightness..." action:@selector(contextSetBrightness:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Set Color Order..." action:@selector(contextSetColorOrder:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Clear Null Pixels" action:@selector(contextClearNullPixels:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Clear Smart Remote" action:@selector(contextClearSmartRemote:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Show Validation Details" action:@selector(contextShowValidation:) keyEquivalent:@""];

    return menu;
}

#pragma mark - Data Loading

- (void)loadPortsForController:(NSString *)controllerName {
    _controllerName = [controllerName copy];
    SafeStringCopy(_dataSource.controllerName, XL_PORT_MAX_STRING_LEN, controllerName);

    [self reloadData];
}

- (void)reloadData {
    if (!_controllerName || _controllerName.length == 0) {
        [self clearPorts];
        return;
    }

    // Reset the data source
    InitPortDataSource(&_dataSource);
    SafeStringCopy(_dataSource.controllerName, XL_PORT_MAX_STRING_LEN, _controllerName);

    // Get controller info from engine bridge
    NSDictionary *controllerInfo = [_engineBridge getControllerInfo:_controllerName];
    if (!controllerInfo) {
        [_tableView reloadData];
        return;
    }

    // Get real port data from the engine bridge
    NSArray<NSDictionary *> *ports = [_engineBridge getPortsForController:_controllerName];

    if (ports.count > 0) {
        // Populate from real port data
        for (NSDictionary *portDict in ports) {
            if (_dataSource.portCount >= XL_PORT_MAX_PORTS) break;

            XLPortEntry *entry = &_dataSource.ports[_dataSource.portCount];
            memset(entry, 0, sizeof(XLPortEntry));

            entry->portNumber = [portDict[@"port"] intValue];
            SafeStringCopy(entry->protocol, XL_PORT_MAX_STRING_LEN, portDict[@"protocol"]);
            entry->startChannel = [portDict[@"startChannel"] intValue];
            entry->channelCount = [portDict[@"channelCount"] intValue];
            entry->endChannel = entry->startChannel + entry->channelCount - 1;
            entry->brightness = [portDict[@"brightness"] intValue];
            entry->gamma = [portDict[@"gamma"] floatValue];
            entry->nullPixelsStart = [portDict[@"nullPixelsStart"] intValue];
            entry->nullPixelsEnd = [portDict[@"nullPixelsEnd"] intValue];
            SafeStringCopy(entry->colorOrder, XL_PORT_MAX_STRING_LEN, portDict[@"colorOrder"]);
            entry->groupCount = [portDict[@"groupCount"] intValue];
            entry->reverse = [portDict[@"reverse"] boolValue];
            entry->zigZag = [portDict[@"zigZag"] intValue];
            SafeStringCopy(entry->smartRemoteType, XL_PORT_MAX_STRING_LEN, portDict[@"smartRemoteType"]);

            // Determine port type based on protocol
            NSString *protocol = portDict[@"protocol"];
            if ([protocol isEqualToString:@"DMX"] ||
                [protocol isEqualToString:@"LOR"] ||
                [protocol isEqualToString:@"Renard"] ||
                [protocol isEqualToString:@"OpenDMX"]) {
                entry->portType = XLPortTypeSerial;
                _dataSource.serialPortCount++;
            } else {
                entry->portType = XLPortTypePixel;
                _dataSource.pixelPortCount++;
            }

            entry->validationStatus = XLPortValidationOK;
            _dataSource.portCount++;
        }
    } else {
        // Fallback: generate port structure based on controller capabilities
        NSDictionary *caps = [_engineBridge getControllerCapabilities:_controllerName];
        int pixelPorts = caps ? [caps[@"maxPixelPorts"] intValue] : 16;
        int serialPorts = caps ? [caps[@"maxSerialPorts"] intValue] : 4;

        if (pixelPorts == 0) pixelPorts = 16;  // Default for typical Ethernet controller
        if (serialPorts == 0) serialPorts = 4;

        // Populate pixel ports
        for (int i = 0; i < pixelPorts && _dataSource.portCount < XL_PORT_MAX_PORTS; i++) {
            XLPortEntry *entry = &_dataSource.ports[_dataSource.portCount];
            InitPortEntry(entry, i + 1, XLPortTypePixel);
            _dataSource.portCount++;
            _dataSource.pixelPortCount++;
        }

        // Populate serial ports
        for (int i = 0; i < serialPorts && _dataSource.portCount < XL_PORT_MAX_PORTS; i++) {
            XLPortEntry *entry = &_dataSource.ports[_dataSource.portCount];
            InitPortEntry(entry, i + 1, XLPortTypeSerial);
            SafeStringCopy(entry->protocol, XL_PORT_MAX_STRING_LEN, @"DMX");
            _dataSource.portCount++;
            _dataSource.serialPortCount++;
        }
    }

    // Run validation
    [self runValidation];

    // Update title
    _titleLabel.stringValue = [NSString stringWithFormat:@"Port Configuration - %@", _controllerName];

    [_tableView reloadData];
}

- (void)clearPorts {
    InitPortDataSource(&_dataSource);
    _controllerName = nil;
    _titleLabel.stringValue = @"Port Configuration";
    [_tableView reloadData];
}

#pragma mark - Capability Configuration

- (void)configureForPixelPorts:(NSInteger)pixelPorts serialPorts:(NSInteger)serialPorts {
    InitPortDataSource(&_dataSource);
    SafeStringCopy(_dataSource.controllerName, XL_PORT_MAX_STRING_LEN, _controllerName);

    for (NSInteger i = 0; i < pixelPorts && _dataSource.portCount < XL_PORT_MAX_PORTS; i++) {
        XLPortEntry *entry = &_dataSource.ports[_dataSource.portCount];
        InitPortEntry(entry, (int)(i + 1), XLPortTypePixel);
        _dataSource.portCount++;
        _dataSource.pixelPortCount++;
    }

    for (NSInteger i = 0; i < serialPorts && _dataSource.portCount < XL_PORT_MAX_PORTS; i++) {
        XLPortEntry *entry = &_dataSource.ports[_dataSource.portCount];
        InitPortEntry(entry, (int)(i + 1), XLPortTypeSerial);
        SafeStringCopy(entry->protocol, XL_PORT_MAX_STRING_LEN, @"DMX");
        _dataSource.portCount++;
        _dataSource.serialPortCount++;
    }

    _titleLabel.stringValue = _controllerName
        ? [NSString stringWithFormat:@"Port Configuration - %@", _controllerName]
        : @"Port Configuration";

    [_tableView reloadData];
}

- (void)setAvailablePixelProtocols:(NSArray<NSString *> *)pixelProtocols
                   serialProtocols:(NSArray<NSString *> *)serialProtocols {
    _filteredPixelProtocols = (pixelProtocols.count > 0) ? [pixelProtocols copy] : nil;
    _filteredSerialProtocols = (serialProtocols.count > 0) ? [serialProtocols copy] : nil;
    [_tableView reloadData];
}

- (void)setSmartRemotesVisible:(BOOL)visible {
    NSTableColumn *srColumn = [_tableView tableColumnWithIdentifier:XLPortColumnSmartRemote];
    if (srColumn) {
        srColumn.hidden = !visible;
    }
}

- (NSArray<NSString *> *)protocolOptionsForPortType:(XLPortType)portType {
    if (portType == XLPortTypePixel && _filteredPixelProtocols) {
        return _filteredPixelProtocols;
    } else if (portType == XLPortTypeSerial && _filteredSerialProtocols) {
        return _filteredSerialProtocols;
    }
    if (portType == XLPortTypePixel) {
        return @[@"ws2811", @"ws2801", @"TM18XX", @"TM1814", @"LPD6803", @"LPD8806",
                 @"APA102", @"APA109", @"SM16716", @"UCS8903", @"UCS8904"];
    }
    return @[@"DMX", @"LOR", @"Renard", @"OpenDMX"];
}

#pragma mark - Validation

- (void)runValidation {
    // Check for channel overlaps and unassigned models
    for (int i = 0; i < _dataSource.portCount; i++) {
        XLPortEntry *port = &_dataSource.ports[i];
        port->validationStatus = XLPortValidationOK;
        port->validationMessage[0] = '\0';

        // Check if port has a model assigned
        if (port->assignedModelName[0] == '\0') {
            // Unassigned port - just a visual indicator, not an error
            continue;
        }

        // Check for channel overlap with other ports
        for (int j = 0; j < _dataSource.portCount; j++) {
            if (i == j) continue;
            XLPortEntry *other = &_dataSource.ports[j];

            if (other->assignedModelName[0] == '\0') continue;
            if (port->channelCount == 0 || other->channelCount == 0) continue;

            int32_t pStart = port->startChannel;
            int32_t pEnd = port->endChannel;
            int32_t oStart = other->startChannel;
            int32_t oEnd = other->endChannel;

            if ((pStart >= oStart && pStart <= oEnd) ||
                (pEnd >= oStart && pEnd <= oEnd) ||
                (pStart <= oStart && pEnd >= oEnd)) {
                port->validationStatus = XLPortValidationError;
                snprintf(port->validationMessage, sizeof(port->validationMessage),
                         "Channel overlap with port %d", other->portNumber);
                break;
            }
        }
    }
}

- (BOOL)validatePorts {
    [self runValidation];

    for (int i = 0; i < _dataSource.portCount; i++) {
        if (_dataSource.ports[i].validationStatus == XLPortValidationError) {
            return NO;
        }
    }
    return YES;
}

#pragma mark - Selection

- (void)selectPortAtIndex:(NSInteger)index {
    if (index >= 0 && index < _dataSource.portCount) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
        [_tableView scrollRowToVisible:index];
    } else {
        [_tableView deselectAll:nil];
    }
}

- (NSInteger)selectedPortIndex {
    return _tableView.selectedRow;
}

- (const XLPortDataSource *)portDataSource {
    return &_dataSource;
}

#pragma mark - Drag and Drop Registration

- (void)registerForModelDrag {
    [_tableView registerForDraggedTypes:@[kModelDragType]];
}

#pragma mark - Filter

- (void)filterChanged:(id)sender {
    // Filter implementation would filter _dataSource and reload
    // For now, just reload all data
    [_tableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _dataSource.portCount;
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
    row:(NSInteger)row {
    if (row < 0 || row >= _dataSource.portCount) return nil;

    XLPortEntry *port = &_dataSource.ports[row];
    NSString *identifier = tableColumn.identifier;

    if ([identifier isEqualToString:XLPortColumnPort]) {
        return @(port->portNumber);
    } else if ([identifier isEqualToString:XLPortColumnType]) {
        switch (port->portType) {
            case XLPortTypePixel: return @"Pixel";
            case XLPortTypeSerial: return @"Serial";
            case XLPortTypePWM: return @"PWM";
            case XLPortTypeVirtualMatrix: return @"VMat";
            case XLPortTypeLEDPanel: return @"LED";
        }
    } else if ([identifier isEqualToString:XLPortColumnProtocol]) {
        return StringFromCString(port->protocol);
    } else if ([identifier isEqualToString:XLPortColumnModel]) {
        return StringFromCString(port->assignedModelName);
    } else if ([identifier isEqualToString:XLPortColumnStartChannel]) {
        return port->startChannel > 0 ? @(port->startChannel) : @"";
    } else if ([identifier isEqualToString:XLPortColumnChannels]) {
        return port->channelCount > 0 ? @(port->channelCount) : @"";
    } else if ([identifier isEqualToString:XLPortColumnPixels]) {
        return port->pixelCount > 0 ? @(port->pixelCount) : @"";
    } else if ([identifier isEqualToString:XLPortColumnBrightness]) {
        return @(port->brightness);
    } else if ([identifier isEqualToString:XLPortColumnGamma]) {
        return [NSString stringWithFormat:@"%.1f", port->gamma];
    } else if ([identifier isEqualToString:XLPortColumnColorOrder]) {
        return StringFromCString(port->colorOrder);
    } else if ([identifier isEqualToString:XLPortColumnNullPixels]) {
        int total = port->nullPixelsStart + port->nullPixelsEnd;
        return total > 0 ? @(total) : @"";
    } else if ([identifier isEqualToString:XLPortColumnSmartRemote]) {
        if (port->smartRemoteIndex > 0) {
            char letter = 'A' + (port->smartRemoteIndex - 1);
            return [NSString stringWithFormat:@"%c", letter];
        }
        return @"";
    }

    return nil;
}

- (void)tableView:(NSTableView *)tableView
   setObjectValue:(id)object
   forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row {
    if (row < 0 || row >= _dataSource.portCount) return;

    XLPortEntry *port = &_dataSource.ports[row];
    NSString *identifier = tableColumn.identifier;
    NSString *value = [object description];

    if ([identifier isEqualToString:XLPortColumnProtocol]) {
        SafeStringCopy(port->protocol, XL_PORT_MAX_STRING_LEN, value);
    } else if ([identifier isEqualToString:XLPortColumnStartChannel]) {
        port->startChannel = [value intValue];
        port->endChannel = port->startChannel + port->channelCount - 1;
    } else if ([identifier isEqualToString:XLPortColumnBrightness]) {
        port->brightness = MAX(0, MIN(100, [value intValue]));
    } else if ([identifier isEqualToString:XLPortColumnGamma]) {
        port->gamma = MAX(0.1f, MIN(5.0f, [value floatValue]));
    } else if ([identifier isEqualToString:XLPortColumnColorOrder]) {
        SafeStringCopy(port->colorOrder, XL_PORT_MAX_STRING_LEN, value);
    } else if ([identifier isEqualToString:XLPortColumnNullPixels]) {
        port->nullPixelsStart = [value intValue];
    } else if ([identifier isEqualToString:XLPortColumnSmartRemote]) {
        if ([value length] > 0) {
            char c = toupper([value characterAtIndex:0]);
            if (c >= 'A' && c <= 'F') {
                port->smartRemoteIndex = c - 'A' + 1;
            }
        } else {
            port->smartRemoteIndex = 0;
        }
    }

    // Notify delegate of change
    if ([_delegate respondsToSelector:@selector(portConfigurationView:didEditPortAtIndex:property:value:)]) {
        [_delegate portConfigurationView:self didEditPortAtIndex:row property:identifier value:object];
    }

    // Revalidate
    [self runValidation];
    [_tableView reloadData];
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    if (row < 0 || row >= _dataSource.portCount) return nil;

    XLPortEntry *port = &_dataSource.ports[row];
    NSString *identifier = tableColumn.identifier;

    // Status column uses image view
    if ([identifier isEqualToString:XLPortColumnStatus]) {
        return [self statusCellForPort:port reusingView:[tableView makeViewWithIdentifier:@"StatusCell" owner:self]];
    }

    // Model column uses popup button
    if ([identifier isEqualToString:XLPortColumnModel]) {
        return [self modelCellForPort:port row:row reusingView:[tableView makeViewWithIdentifier:@"ModelCell" owner:self]];
    }

    // Protocol column uses popup button for filtered protocol selection
    if ([identifier isEqualToString:XLPortColumnProtocol]) {
        NSArray<NSString *> *protocols = [self protocolOptionsForPortType:port->portType];
        return [self protocolCellForPort:port row:row protocols:protocols reusingView:[tableView makeViewWithIdentifier:@"ProtocolCell" owner:self]];
    }

    // Other columns use text cells
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [self makeTextCellWithIdentifier:identifier editable:tableColumn.isEditable];
    }

    id value = [self tableView:tableView objectValueForTableColumn:tableColumn row:row];
    cell.textField.stringValue = value ? [value description] : @"";

    // Style unassigned ports
    if (port->assignedModelName[0] == '\0' && port->portType == XLPortTypePixel) {
        cell.textField.textColor = [NSColor tertiaryLabelColor];
    } else {
        cell.textField.textColor = [NSColor labelColor];
    }

    // Style port type column
    if ([identifier isEqualToString:XLPortColumnType]) {
        switch (port->portType) {
            case XLPortTypePixel:
                cell.textField.textColor = [NSColor systemRedColor];
                break;
            case XLPortTypeSerial:
                cell.textField.textColor = [NSColor systemGreenColor];
                break;
            default:
                cell.textField.textColor = [NSColor systemBlueColor];
                break;
        }
    }

    return cell;
}

- (NSTableCellView *)makeTextCellWithIdentifier:(NSString *)identifier editable:(BOOL)editable {
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
    cell.identifier = identifier;

    NSTextField *textField;
    if (editable) {
        textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        textField.bordered = NO;
        textField.drawsBackground = NO;
        textField.delegate = self;
    } else {
        textField = [NSTextField labelWithString:@""];
    }
    textField.font = [NSFont systemFontOfSize:11];
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

- (NSView *)statusCellForPort:(XLPortEntry *)port reusingView:(NSView *)existingView {
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

    cell.imageView.image = StatusIndicatorImage(port->validationStatus);

    // Tooltip for validation message
    if (port->validationMessage[0] != '\0') {
        cell.toolTip = StringFromCString(port->validationMessage);
    } else {
        cell.toolTip = nil;
    }

    return cell;
}

- (NSView *)protocolCellForPort:(XLPortEntry *)port row:(NSInteger)row protocols:(NSArray<NSString *> *)protocols reusingView:(NSView *)existingView {
    NSTableCellView *cell = (NSTableCellView *)existingView;
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"ProtocolCell";

        NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        popup.font = [NSFont systemFontOfSize:11];
        popup.bordered = NO;
        popup.translatesAutoresizingMaskIntoConstraints = NO;
        popup.tag = row;
        popup.target = self;
        popup.action = @selector(protocolSelectionChanged:);
        [cell addSubview:popup];

        [NSLayoutConstraint activateConstraints:@[
            [popup.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor],
            [popup.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor],
            [popup.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];

        objc_setAssociatedObject(cell, @selector(protocolPopup), popup, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSPopUpButton *popup = objc_getAssociatedObject(cell, @selector(protocolPopup));
    popup.tag = row;

    [popup removeAllItems];
    [popup addItemsWithTitles:protocols];

    NSString *current = StringFromCString(port->protocol);
    if (current.length > 0) {
        [popup selectItemWithTitle:current];
        if (popup.selectedItem == nil && popup.numberOfItems > 0) {
            [popup selectItemAtIndex:0];
        }
    }

    return cell;
}

- (void)protocolSelectionChanged:(NSPopUpButton *)sender {
    NSInteger row = sender.tag;
    if (row < 0 || row >= _dataSource.portCount) return;

    XLPortEntry *port = &_dataSource.ports[row];
    NSString *selected = sender.selectedItem.title;
    SafeStringCopy(port->protocol, XL_PORT_MAX_STRING_LEN, selected);

    if ([_delegate respondsToSelector:@selector(portConfigurationView:didEditPortAtIndex:property:value:)]) {
        [_delegate portConfigurationView:self didEditPortAtIndex:row property:XLPortColumnProtocol value:selected];
    }

    [_tableView reloadData];
}

- (NSView *)modelCellForPort:(XLPortEntry *)port row:(NSInteger)row reusingView:(NSView *)existingView {
    NSTableCellView *cell = (NSTableCellView *)existingView;
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"ModelCell";

        NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        popup.font = [NSFont systemFontOfSize:11];
        popup.bordered = NO;
        popup.translatesAutoresizingMaskIntoConstraints = NO;
        popup.tag = row;
        popup.target = self;
        popup.action = @selector(modelSelectionChanged:);
        [cell addSubview:popup];

        [NSLayoutConstraint activateConstraints:@[
            [popup.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor],
            [popup.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor],
            [popup.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];

        // Store popup in a custom property via associated object
        objc_setAssociatedObject(cell, @selector(popup), popup, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSPopUpButton *popup = objc_getAssociatedObject(cell, @selector(popup));
    popup.tag = row;

    [popup removeAllItems];
    [popup addItemWithTitle:@"(None)"];

    // Add available models from engine bridge
    NSArray<NSString *> *modelNames = [_engineBridge getModelNames];
    for (NSString *name in modelNames) {
        [popup addItemWithTitle:name];
    }

    // Select current model
    NSString *currentModel = StringFromCString(port->assignedModelName);
    if (currentModel.length > 0) {
        [popup selectItemWithTitle:currentModel];
    } else {
        [popup selectItemAtIndex:0];
    }

    return cell;
}

- (void)modelSelectionChanged:(NSPopUpButton *)sender {
    NSInteger row = sender.tag;
    if (row < 0 || row >= _dataSource.portCount) return;

    XLPortEntry *port = &_dataSource.ports[row];
    NSString *selectedModel = sender.selectedItem.title;

    if ([selectedModel isEqualToString:@"(None)"]) {
        port->assignedModelName[0] = '\0';
        port->channelCount = 0;
        port->pixelCount = 0;
        port->startChannel = 0;
        port->endChannel = 0;
    } else {
        SafeStringCopy(port->assignedModelName, XL_PORT_MAX_STRING_LEN, selectedModel);

        // Get model info to populate channel data
        NSDictionary *modelInfo = [_engineBridge getModelInfo:selectedModel];
        if (modelInfo) {
            port->channelCount = [modelInfo[@"channelCount"] intValue];
            port->startChannel = [modelInfo[@"startChannel"] intValue];
            port->endChannel = port->startChannel + port->channelCount - 1;
            port->pixelCount = [modelInfo[@"nodeCount"] intValue];
        }
    }

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(portConfigurationView:didEditPortAtIndex:property:value:)]) {
        [_delegate portConfigurationView:self didEditPortAtIndex:row property:@"model" value:selectedModel];
    }

    [self runValidation];
    [_tableView reloadData];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger selected = _tableView.selectedRow;
    if ([_delegate respondsToSelector:@selector(portConfigurationView:didSelectPortAtIndex:)]) {
        [_delegate portConfigurationView:self didSelectPortAtIndex:selected];
    }
}

#pragma mark - Drag and Drop

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    if (dropOperation == NSTableViewDropOn && row >= 0 && row < _dataSource.portCount) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation {
    NSPasteboardItem *item = info.draggingPasteboard.pasteboardItems.firstObject;
    NSString *modelName = [item stringForType:kModelDragType];
    if (!modelName || row < 0 || row >= _dataSource.portCount) return NO;

    XLPortEntry *port = &_dataSource.ports[row];
    SafeStringCopy(port->assignedModelName, XL_PORT_MAX_STRING_LEN, modelName);

    // Get model info
    NSDictionary *modelInfo = [_engineBridge getModelInfo:modelName];
    if (modelInfo) {
        port->channelCount = [modelInfo[@"channelCount"] intValue];
        port->startChannel = [modelInfo[@"startChannel"] intValue];
        port->endChannel = port->startChannel + port->channelCount - 1;
        port->pixelCount = [modelInfo[@"nodeCount"] intValue];
    }

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(portConfigurationView:didDropModel:onPortAtIndex:)]) {
        [_delegate portConfigurationView:self didDropModel:modelName onPortAtIndex:row];
    }

    [self runValidation];
    [_tableView reloadData];
    return YES;
}

#pragma mark - Context Menu Actions

- (void)contextAssignModel:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0) return;

    if ([_delegate respondsToSelector:@selector(portConfigurationView:didRequestAssignModelToPort:)]) {
        [_delegate portConfigurationView:self didRequestAssignModelToPort:row];
    }
}

- (void)contextRemoveModel:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0 || row >= _dataSource.portCount) return;

    XLPortEntry *port = &_dataSource.ports[row];
    port->assignedModelName[0] = '\0';
    port->channelCount = 0;
    port->pixelCount = 0;
    port->startChannel = 0;
    port->endChannel = 0;

    if ([_delegate respondsToSelector:@selector(portConfigurationView:didRequestRemoveModelAtIndex:fromPortAtIndex:)]) {
        [_delegate portConfigurationView:self didRequestRemoveModelAtIndex:0 fromPortAtIndex:row];
    }

    [self runValidation];
    [_tableView reloadData];
}

- (void)contextSetProtocol:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0 || row >= _dataSource.portCount) return;

    XLPortEntry *port = &_dataSource.ports[row];
    NSArray<NSString *> *protocols = [self protocolOptionsForPortType:port->portType];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Protocol";
    alert.informativeText = [NSString stringWithFormat:@"Select protocol for port %d:", port->portNumber];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 24) pullsDown:NO];
    [popup addItemsWithTitles:protocols];
    NSString *current = StringFromCString(port->protocol);
    if (current.length > 0) {
        [popup selectItemWithTitle:current];
    }
    alert.accessoryView = popup;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            SafeStringCopy(port->protocol, XL_PORT_MAX_STRING_LEN, popup.selectedItem.title);
            [self.tableView reloadData];
        }
    }];
}

- (void)contextSetBrightness:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0 || row >= _dataSource.portCount) return;

    XLPortEntry *port = &_dataSource.ports[row];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Brightness";
    alert.informativeText = [NSString stringWithFormat:@"Enter brightness (0-100) for port %d:", port->portNumber];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    input.stringValue = [NSString stringWithFormat:@"%d", port->brightness];
    alert.accessoryView = input;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            port->brightness = MAX(0, MIN(100, input.stringValue.intValue));
            [self.tableView reloadData];
        }
    }];
}

- (void)contextSetColorOrder:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0 || row >= _dataSource.portCount) return;

    XLPortEntry *port = &_dataSource.ports[row];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Color Order";
    alert.informativeText = @"Select color order:";

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 24) pullsDown:NO];
    [popup addItemsWithTitles:@[@"RGB", @"RBG", @"GRB", @"GBR", @"BRG", @"BGR", @"RGBW", @"WRGB"]];
    [popup selectItemWithTitle:StringFromCString(port->colorOrder)];
    alert.accessoryView = popup;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            SafeStringCopy(port->colorOrder, XL_PORT_MAX_STRING_LEN, popup.selectedItem.title);
            [self.tableView reloadData];
        }
    }];
}

- (void)contextClearNullPixels:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0 || row >= _dataSource.portCount) return;

    XLPortEntry *port = &_dataSource.ports[row];
    port->nullPixelsStart = 0;
    port->nullPixelsEnd = 0;
    [_tableView reloadData];
}

- (void)contextClearSmartRemote:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0 || row >= _dataSource.portCount) return;

    XLPortEntry *port = &_dataSource.ports[row];
    port->smartRemoteIndex = 0;
    port->smartRemoteType[0] = '\0';
    [_tableView reloadData];
}

- (void)contextShowValidation:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;
    if (row < 0 || row >= _dataSource.portCount) return;

    XLPortEntry *port = &_dataSource.ports[row];

    if ([_delegate respondsToSelector:@selector(portConfigurationView:didRequestShowValidationForPortAtIndex:)]) {
        [_delegate portConfigurationView:self didRequestShowValidationForPortAtIndex:row];
        return;
    }

    // Default: show alert with validation info
    NSString *message;
    if (port->validationMessage[0] != '\0') {
        message = StringFromCString(port->validationMessage);
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

#pragma mark - Menu Validation

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    NSInteger row = _tableView.clickedRow;
    if (row < 0) row = _tableView.selectedRow;

    SEL action = menuItem.action;

    // These require a valid row
    if (action == @selector(contextAssignModel:) ||
        action == @selector(contextRemoveModel:) ||
        action == @selector(contextSetProtocol:) ||
        action == @selector(contextSetBrightness:) ||
        action == @selector(contextSetColorOrder:) ||
        action == @selector(contextClearNullPixels:) ||
        action == @selector(contextClearSmartRemote:) ||
        action == @selector(contextShowValidation:)) {
        return (row >= 0 && row < _dataSource.portCount);
    }

    // Remove model only valid if model is assigned
    if (action == @selector(contextRemoveModel:)) {
        if (row >= 0 && row < _dataSource.portCount) {
            return _dataSource.ports[row].assignedModelName[0] != '\0';
        }
        return NO;
    }

    return YES;
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    NSTextField *textField = obj.object;
    NSInteger row = [_tableView rowForView:textField];
    NSInteger column = [_tableView columnForView:textField];

    if (row >= 0 && column >= 0) {
        NSTableColumn *tableColumn = _tableView.tableColumns[column];
        [self tableView:_tableView setObjectValue:textField.stringValue forTableColumn:tableColumn row:row];
    }
}

@end
