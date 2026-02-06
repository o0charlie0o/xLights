/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLFPPConnectWindowController.h"
#import "XLEngineBridge.h"

static const CGFloat kWindowWidth = 900.0;
static const CGFloat kWindowHeight = 600.0;
static const CGFloat kDevicePanelWidth = 320.0;

#pragma mark - FPP Device Model

/// Represents a discovered FPP device on the network.
@interface XLFPPDevice : NSObject

@property (nonatomic, copy) NSString *ipAddress;
@property (nonatomic, copy) NSString *hostname;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *platform;
@property (nonatomic, assign) BOOL reachable;

+ (instancetype)deviceWithIP:(NSString *)ip hostname:(NSString *)hostname;

@end

@implementation XLFPPDevice

+ (instancetype)deviceWithIP:(NSString *)ip hostname:(NSString *)hostname {
    XLFPPDevice *device = [[XLFPPDevice alloc] init];
    device.ipAddress = ip;
    device.hostname = hostname ?: ip;
    device.version = @"(checking...)";
    device.platform = @"";
    device.reachable = NO;
    return device;
}

@end

#pragma mark - FPP File Entry Model

/// Represents a file in the show folder that can be uploaded.
@interface XLFPPFileEntry : NSObject

@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy) NSString *fullPath;
@property (nonatomic, copy) NSString *fileType;
@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, assign) BOOL selected;

+ (instancetype)entryWithPath:(NSString *)path;

/// Human-readable file size string.
- (NSString *)fileSizeString;

@end

@implementation XLFPPFileEntry

+ (instancetype)entryWithPath:(NSString *)path {
    XLFPPFileEntry *entry = [[XLFPPFileEntry alloc] init];
    entry.fullPath = path;
    entry.filename = path.lastPathComponent;
    entry.selected = NO;

    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"fseq"]) {
        entry.fileType = @"Sequence";
    } else if ([ext isEqualToString:@"xml"]) {
        entry.fileType = @"Configuration";
    } else if ([ext isEqualToString:@"xlights"]) {
        entry.fileType = @"Sequence (XML)";
    } else if ([ext isEqualToString:@"mp3"] || [ext isEqualToString:@"wav"] ||
               [ext isEqualToString:@"ogg"] || [ext isEqualToString:@"m4a"]) {
        entry.fileType = @"Audio";
    } else if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] ||
               [ext isEqualToString:@"avi"]) {
        entry.fileType = @"Video";
    } else {
        entry.fileType = @"Other";
    }

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    entry.fileSize = [attrs fileSize];

    return entry;
}

- (NSString *)fileSizeString {
    if (_fileSize < 1024) {
        return [NSString stringWithFormat:@"%llu B", _fileSize];
    } else if (_fileSize < 1024 * 1024) {
        return [NSString stringWithFormat:@"%.1f KB", _fileSize / 1024.0];
    } else {
        return [NSString stringWithFormat:@"%.1f MB", _fileSize / (1024.0 * 1024.0)];
    }
}

@end

#pragma mark - XLFPPConnectWindowController

@interface XLFPPConnectWindowController () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>

// UI elements
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSTableView *deviceTableView;
@property (nonatomic, strong) NSTableView *fileTableView;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *uploadSelectedButton;
@property (nonatomic, strong) NSButton *uploadAllButton;

// Data
@property (nonatomic, strong) NSMutableArray<XLFPPDevice *> *devices;
@property (nonatomic, strong) NSMutableArray<XLFPPFileEntry *> *fileEntries;

// Bonjour discovery
@property (nonatomic, strong) NSNetServiceBrowser *serviceBrowser;
@property (nonatomic, strong) NSMutableArray<NSNetService *> *discoveredServices;

// Upload state
@property (nonatomic, strong) NSURLSession *uploadSession;
@property (nonatomic, assign) BOOL isUploading;

@end

@implementation XLFPPConnectWindowController

- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWindowWidth, kWindowHeight)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];

    self = [super initWithWindow:window];
    if (self) {
        _engineBridge = engineBridge;
        _devices = [NSMutableArray array];
        _fileEntries = [NSMutableArray array];
        _discoveredServices = [NSMutableArray array];
        _isUploading = NO;

        window.title = @"FPP Connect";
        window.minSize = NSMakeSize(700, 400);
        [window center];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 10.0;
        _uploadSession = [NSURLSession sessionWithConfiguration:config];

        [self setupToolbar];
        [self setupUI];
        [self refreshFileList];
    }
    return self;
}

- (void)dealloc {
    [_serviceBrowser stop];
    [_uploadSession invalidateAndCancel];
}

#pragma mark - Toolbar

- (void)setupToolbar {
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"FPPConnectToolbar"];
    toolbar.delegate = (id<NSToolbarDelegate>)self;
    toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    toolbar.allowsUserCustomization = NO;
    if (@available(macOS 11.0, *)) {
        self.window.toolbarStyle = NSWindowToolbarStyleUnified;
    }
    self.window.toolbar = toolbar;
}

// NSToolbarDelegate methods
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"discover", @"addIP", NSToolbarFlexibleSpaceItemIdentifier, @"uploadSelected", @"uploadAll"];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"discover", @"addIP", NSToolbarFlexibleSpaceItemIdentifier, @"uploadSelected", @"uploadAll"];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];

    if ([itemIdentifier isEqualToString:@"discover"]) {
        item.label = @"Discover";
        item.paletteLabel = @"Discover Devices";
        item.toolTip = @"Scan network for FPP devices";
        if (@available(macOS 11.0, *)) {
            item.image = [NSImage imageWithSystemSymbolName:@"antenna.radiowaves.left.and.right"
                                   accessibilityDescription:@"Discover"];
        }
        item.target = self;
        item.action = @selector(discoverDevices);
    } else if ([itemIdentifier isEqualToString:@"addIP"]) {
        item.label = @"Add IP";
        item.paletteLabel = @"Add IP Address";
        item.toolTip = @"Manually add an FPP device by IP address";
        if (@available(macOS 11.0, *)) {
            item.image = [NSImage imageWithSystemSymbolName:@"plus.circle"
                                   accessibilityDescription:@"Add IP"];
        }
        item.target = self;
        item.action = @selector(addIPManually:);
    } else if ([itemIdentifier isEqualToString:@"uploadSelected"]) {
        item.label = @"Upload Selected";
        item.paletteLabel = @"Upload Selected Files";
        item.toolTip = @"Upload checked files to selected FPP device";
        if (@available(macOS 11.0, *)) {
            item.image = [NSImage imageWithSystemSymbolName:@"arrow.up.doc"
                                   accessibilityDescription:@"Upload Selected"];
        }
        item.target = self;
        item.action = @selector(uploadSelected:);
    } else if ([itemIdentifier isEqualToString:@"uploadAll"]) {
        item.label = @"Upload All";
        item.paletteLabel = @"Upload All Files";
        item.toolTip = @"Upload all files to selected FPP device";
        if (@available(macOS 11.0, *)) {
            item.image = [NSImage imageWithSystemSymbolName:@"arrow.up.doc.fill"
                                   accessibilityDescription:@"Upload All"];
        }
        item.target = self;
        item.action = @selector(uploadAll:);
    }

    return item;
}

#pragma mark - UI Setup

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    // Status bar at bottom
    NSView *statusBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kWindowWidth, 32)];
    statusBar.autoresizingMask = NSViewWidthSizable;
    statusBar.wantsLayer = YES;
    statusBar.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];

    _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(12, 8, 160, 16)];
    _progressIndicator.style = NSProgressIndicatorStyleBar;
    _progressIndicator.minValue = 0;
    _progressIndicator.maxValue = 100;
    _progressIndicator.doubleValue = 0;
    _progressIndicator.hidden = YES;
    [statusBar addSubview:_progressIndicator];

    _statusLabel = [NSTextField labelWithString:@"Ready. Add a device or run discovery to begin."];
    _statusLabel.frame = NSMakeRect(180, 8, kWindowWidth - 192, 16);
    _statusLabel.autoresizingMask = NSViewWidthSizable;
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    [statusBar addSubview:_statusLabel];

    [contentView addSubview:statusBar];

    // Split view for device panel + file panel
    _splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 32, kWindowWidth, kWindowHeight - 32)];
    _splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitView.vertical = YES;
    _splitView.delegate = self;

    // Left panel: device list
    NSView *devicePanel = [self createDevicePanel];
    [_splitView addSubview:devicePanel];

    // Right panel: file list
    NSView *filePanel = [self createFilePanel];
    [_splitView addSubview:filePanel];

    [_splitView setPosition:kDevicePanelWidth ofDividerAtIndex:0];

    [contentView addSubview:_splitView];
}

- (NSView *)createDevicePanel {
    NSView *panel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kDevicePanelWidth, kWindowHeight - 32)];

    // Header
    NSTextField *header = [NSTextField labelWithString:@"FPP Devices"];
    header.frame = NSMakeRect(12, panel.bounds.size.height - 28, kDevicePanelWidth - 24, 20);
    header.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    header.font = [NSFont boldSystemFontOfSize:13];
    [panel addSubview:header];

    // Device table
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kDevicePanelWidth, panel.bounds.size.height - 34)];
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSNoBorder;

    _deviceTableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    _deviceTableView.delegate = self;
    _deviceTableView.dataSource = self;
    _deviceTableView.usesAlternatingRowBackgroundColors = YES;
    _deviceTableView.rowHeight = 36.0;
    _deviceTableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;

    NSTableColumn *hostCol = [[NSTableColumn alloc] initWithIdentifier:@"hostname"];
    hostCol.title = @"Host";
    hostCol.width = 130;
    hostCol.minWidth = 80;
    [_deviceTableView addTableColumn:hostCol];

    NSTableColumn *ipCol = [[NSTableColumn alloc] initWithIdentifier:@"ip"];
    ipCol.title = @"IP Address";
    ipCol.width = 110;
    ipCol.minWidth = 80;
    [_deviceTableView addTableColumn:ipCol];

    NSTableColumn *versionCol = [[NSTableColumn alloc] initWithIdentifier:@"version"];
    versionCol.title = @"Version";
    versionCol.width = 70;
    versionCol.minWidth = 50;
    [_deviceTableView addTableColumn:versionCol];

    scrollView.documentView = _deviceTableView;
    [panel addSubview:scrollView];

    return panel;
}

- (NSView *)createFilePanel {
    CGFloat filePanelWidth = kWindowWidth - kDevicePanelWidth;
    NSView *panel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, filePanelWidth, kWindowHeight - 32)];

    // Header
    NSTextField *header = [NSTextField labelWithString:@"Files to Upload"];
    header.frame = NSMakeRect(12, panel.bounds.size.height - 28, filePanelWidth - 24, 20);
    header.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    header.font = [NSFont boldSystemFontOfSize:13];
    [panel addSubview:header];

    // Select All / None buttons
    NSButton *selectAllBtn = [NSButton buttonWithTitle:@"Select All" target:self action:@selector(selectAllFiles:)];
    selectAllBtn.frame = NSMakeRect(filePanelWidth - 220, panel.bounds.size.height - 30, 80, 24);
    selectAllBtn.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    selectAllBtn.bezelStyle = NSBezelStyleInline;
    selectAllBtn.controlSize = NSControlSizeSmall;
    [panel addSubview:selectAllBtn];

    NSButton *selectNoneBtn = [NSButton buttonWithTitle:@"Select None" target:self action:@selector(selectNoFiles:)];
    selectNoneBtn.frame = NSMakeRect(filePanelWidth - 130, panel.bounds.size.height - 30, 90, 24);
    selectNoneBtn.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    selectNoneBtn.bezelStyle = NSBezelStyleInline;
    selectNoneBtn.controlSize = NSControlSizeSmall;
    [panel addSubview:selectNoneBtn];

    // File table
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, filePanelWidth, panel.bounds.size.height - 34)];
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSNoBorder;

    _fileTableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    _fileTableView.delegate = self;
    _fileTableView.dataSource = self;
    _fileTableView.usesAlternatingRowBackgroundColors = YES;
    _fileTableView.rowHeight = 22.0;
    _fileTableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;

    NSTableColumn *checkCol = [[NSTableColumn alloc] initWithIdentifier:@"selected"];
    checkCol.title = @"";
    checkCol.width = 30;
    checkCol.minWidth = 30;
    checkCol.maxWidth = 30;
    [_fileTableView addTableColumn:checkCol];

    NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"filename"];
    nameCol.title = @"Filename";
    nameCol.width = 280;
    nameCol.minWidth = 150;
    nameCol.resizingMask = NSTableColumnAutoresizingMask;
    [_fileTableView addTableColumn:nameCol];

    NSTableColumn *typeCol = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeCol.title = @"Type";
    typeCol.width = 100;
    typeCol.minWidth = 60;
    [_fileTableView addTableColumn:typeCol];

    NSTableColumn *sizeCol = [[NSTableColumn alloc] initWithIdentifier:@"size"];
    sizeCol.title = @"Size";
    sizeCol.width = 80;
    sizeCol.minWidth = 50;
    [_fileTableView addTableColumn:sizeCol];

    scrollView.documentView = _fileTableView;
    [panel addSubview:scrollView];

    return panel;
}

#pragma mark - NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return 200.0;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return splitView.bounds.size.width - 300.0;
}

#pragma mark - File List

- (void)refreshFileList {
    [_fileEntries removeAllObjects];

    NSString *showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    if (!showFolder) {
        _statusLabel.stringValue = @"No show folder selected.";
        [_fileTableView reloadData];
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:showFolder error:nil];

    NSSet *uploadableExtensions = [NSSet setWithArray:@[@"fseq", @"xml", @"xlights",
                                                         @"mp3", @"wav", @"ogg", @"m4a",
                                                         @"mp4", @"mov", @"avi"]];

    for (NSString *file in [contents sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        NSString *ext = file.pathExtension.lowercaseString;
        if ([uploadableExtensions containsObject:ext]) {
            NSString *fullPath = [showFolder stringByAppendingPathComponent:file];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:fullPath isDirectory:&isDir] && !isDir) {
                XLFPPFileEntry *entry = [XLFPPFileEntry entryWithPath:fullPath];
                // Auto-select FSEQ files
                if ([ext isEqualToString:@"fseq"]) {
                    entry.selected = YES;
                }
                [_fileEntries addObject:entry];
            }
        }
    }

    [_fileTableView reloadData];
    _statusLabel.stringValue = [NSString stringWithFormat:@"%ld files found in show folder.", (long)_fileEntries.count];
}

#pragma mark - Device Discovery

- (void)discoverDevices {
    _statusLabel.stringValue = @"Discovering FPP devices...";
    _progressIndicator.hidden = NO;
    _progressIndicator.indeterminate = YES;
    [_progressIndicator startAnimation:nil];

    // Stop any previous discovery
    [_serviceBrowser stop];
    [_discoveredServices removeAllObjects];

    // Start Bonjour discovery for FPP devices (_fpp._tcp)
    _serviceBrowser = [[NSNetServiceBrowser alloc] init];
    _serviceBrowser.delegate = self;
    [_serviceBrowser searchForServicesOfType:@"_fpp._tcp." inDomain:@"local."];

    // Also try _http._tcp as fallback for FPP devices that may not advertise _fpp._tcp
    // Stop discovery after a timeout
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self->_serviceBrowser stop];
        [self->_progressIndicator stopAnimation:nil];
        self->_progressIndicator.hidden = YES;

        if (self->_devices.count == 0) {
            self->_statusLabel.stringValue = @"No FPP devices found. Try adding an IP manually.";
        } else {
            self->_statusLabel.stringValue = [NSString stringWithFormat:@"Found %ld FPP device(s).", (long)self->_devices.count];
        }
    });
}

- (void)addIPManually:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Add FPP Device";
    alert.informativeText = @"Enter the IP address of the FPP device:";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"Add"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *inputField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    inputField.placeholderString = @"192.168.1.100";
    alert.accessoryView = inputField;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString *ip = inputField.stringValue;
            if (ip.length > 0) {
                [self addDeviceWithIP:ip];
            }
        }
    }];

    // Make the text field first responder after the sheet appears
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [alert.window makeFirstResponder:inputField];
    });
}

- (void)addDeviceWithIP:(NSString *)ip {
    // Check for duplicates
    for (XLFPPDevice *device in _devices) {
        if ([device.ipAddress isEqualToString:ip]) {
            _statusLabel.stringValue = [NSString stringWithFormat:@"Device %@ already in list.", ip];
            return;
        }
    }

    XLFPPDevice *device = [XLFPPDevice deviceWithIP:ip hostname:ip];
    [_devices addObject:device];
    [_deviceTableView reloadData];

    // Query the device for info
    [self queryDeviceInfo:device];
}

- (void)queryDeviceInfo:(XLFPPDevice *)device {
    NSString *urlString = [NSString stringWithFormat:@"http://%@/api/fppd/status", device.ipAddress];
    NSURL *url = [NSURL URLWithString:urlString];

    NSURLSessionDataTask *task = [_uploadSession dataTaskWithURL:url
                                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                device.version = @"(unreachable)";
                device.reachable = NO;
                self->_statusLabel.stringValue = [NSString stringWithFormat:@"Could not reach %@: %@",
                                                  device.ipAddress, error.localizedDescription];
            } else {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                if (httpResponse.statusCode == 200 && data) {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if (json) {
                        device.version = json[@"version"] ?: json[@"FPPD"] ?: @"FPP";
                        device.hostname = json[@"HostName"] ?: json[@"hostname"] ?: device.ipAddress;
                        device.platform = json[@"Platform"] ?: @"";
                        device.reachable = YES;
                        self->_statusLabel.stringValue = [NSString stringWithFormat:@"Connected to %@ (%@)",
                                                          device.hostname, device.version];
                    } else {
                        device.version = @"FPP";
                        device.reachable = YES;
                    }
                } else {
                    device.version = [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode];
                    device.reachable = NO;
                }
            }
            [self->_deviceTableView reloadData];
        });
    }];
    [task resume];
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    [_discoveredServices addObject:service];
    service.delegate = self;
    [service resolveWithTimeout:5.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
         didRemoveService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    [_discoveredServices removeObject:service];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
             didNotSearch:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    NSLog(@"FPP Connect: Bonjour search failed: %@", errorDict);
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_statusLabel.stringValue = @"Bonjour discovery failed. Try adding IP manually.";
        [self->_progressIndicator stopAnimation:nil];
        self->_progressIndicator.hidden = YES;
    });
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender {
    // Extract IP address from resolved addresses
    NSString *ip = nil;
    for (NSData *addrData in sender.addresses) {
        struct sockaddr *addr = (struct sockaddr *)[addrData bytes];
        if (addr->sa_family == AF_INET) {
            struct sockaddr_in *ipv4 = (struct sockaddr_in *)addr;
            char addrBuf[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &ipv4->sin_addr, addrBuf, sizeof(addrBuf));
            ip = [NSString stringWithUTF8String:addrBuf];
            break;
        }
    }

    if (ip) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Check for duplicates
            for (XLFPPDevice *device in self->_devices) {
                if ([device.ipAddress isEqualToString:ip]) {
                    return;
                }
            }

            XLFPPDevice *device = [XLFPPDevice deviceWithIP:ip hostname:sender.name];
            [self->_devices addObject:device];
            [self->_deviceTableView reloadData];
            [self queryDeviceInfo:device];

            self->_statusLabel.stringValue = [NSString stringWithFormat:@"Found %ld FPP device(s).",
                                              (long)self->_devices.count];
        });
    }
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    NSLog(@"FPP Connect: Failed to resolve service %@: %@", sender.name, errorDict);
}

#pragma mark - Upload Actions

- (void)uploadSelected:(id)sender {
    XLFPPDevice *device = [self selectedDevice];
    if (!device) {
        [self showAlert:@"No Device Selected" message:@"Please select an FPP device from the list first."];
        return;
    }
    if (!device.reachable) {
        [self showAlert:@"Device Unreachable" message:@"The selected device is not reachable. Please verify the IP address."];
        return;
    }

    NSMutableArray<XLFPPFileEntry *> *selectedFiles = [NSMutableArray array];
    for (XLFPPFileEntry *entry in _fileEntries) {
        if (entry.selected) {
            [selectedFiles addObject:entry];
        }
    }

    if (selectedFiles.count == 0) {
        [self showAlert:@"No Files Selected" message:@"Please select at least one file to upload."];
        return;
    }

    [self uploadFiles:selectedFiles toDevice:device];
}

- (void)uploadAll:(id)sender {
    XLFPPDevice *device = [self selectedDevice];
    if (!device) {
        [self showAlert:@"No Device Selected" message:@"Please select an FPP device from the list first."];
        return;
    }
    if (!device.reachable) {
        [self showAlert:@"Device Unreachable" message:@"The selected device is not reachable. Please verify the IP address."];
        return;
    }

    if (_fileEntries.count == 0) {
        [self showAlert:@"No Files" message:@"No uploadable files found in the show folder."];
        return;
    }

    [self uploadFiles:_fileEntries toDevice:device];
}

- (void)uploadFiles:(NSArray<XLFPPFileEntry *> *)files toDevice:(XLFPPDevice *)device {
    if (_isUploading) {
        _statusLabel.stringValue = @"Upload already in progress...";
        return;
    }

    _isUploading = YES;
    _progressIndicator.hidden = NO;
    _progressIndicator.indeterminate = NO;
    _progressIndicator.doubleValue = 0;

    __block NSInteger completed = 0;
    NSInteger total = (NSInteger)files.count;
    _statusLabel.stringValue = [NSString stringWithFormat:@"Uploading %ld file(s) to %@...", (long)total, device.hostname];

    for (XLFPPFileEntry *file in files) {
        [self uploadFile:file toDevice:device completion:^(BOOL success, NSString *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completed++;
                self->_progressIndicator.doubleValue = (double)completed / (double)total * 100.0;

                if (!success) {
                    NSLog(@"FPP Connect: Failed to upload %@: %@", file.filename, error);
                }

                if (completed == total) {
                    self->_isUploading = NO;
                    self->_progressIndicator.hidden = YES;
                    self->_statusLabel.stringValue = [NSString stringWithFormat:@"Upload complete: %ld file(s) sent to %@.",
                                                      (long)total, device.hostname];
                }
            });
        }];
    }
}

- (void)uploadFile:(XLFPPFileEntry *)file
          toDevice:(XLFPPDevice *)device
        completion:(void (^)(BOOL success, NSString *error))completion {

    NSString *urlString = [NSString stringWithFormat:@"http://%@/api/file/upload", device.ipAddress];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";

    // Build multipart form data
    NSString *boundary = [[NSUUID UUID] UUIDString];
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request setValue:contentType forHTTPHeaderField:@"Content-Type"];

    NSMutableData *body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n", file.filename]
                       dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];

    NSData *fileData = [NSData dataWithContentsOfFile:file.fullPath];
    if (!fileData) {
        completion(NO, @"Could not read file");
        return;
    }

    [body appendData:fileData];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    NSURLSessionUploadTask *task = [_uploadSession uploadTaskWithRequest:request
                                                               fromData:body
                                                      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(NO, error.localizedDescription);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
            completion(YES, nil);
        } else {
            completion(NO, [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]);
        }
    }];
    [task resume];
}

#pragma mark - Selection Helpers

- (XLFPPDevice *)selectedDevice {
    NSInteger row = _deviceTableView.selectedRow;
    if (row >= 0 && row < (NSInteger)_devices.count) {
        return _devices[row];
    }
    return nil;
}

- (void)selectAllFiles:(id)sender {
    for (XLFPPFileEntry *entry in _fileEntries) {
        entry.selected = YES;
    }
    [_fileTableView reloadData];
}

- (void)selectNoFiles:(id)sender {
    for (XLFPPFileEntry *entry in _fileEntries) {
        entry.selected = NO;
    }
    [_fileTableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == _deviceTableView) {
        return (NSInteger)_devices.count;
    } else if (tableView == _fileTableView) {
        return (NSInteger)_fileEntries.count;
    }
    return 0;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *identifier = tableColumn.identifier;

    if (tableView == _deviceTableView) {
        return [self deviceCellForColumn:identifier row:row inTable:tableView];
    } else if (tableView == _fileTableView) {
        return [self fileCellForColumn:identifier row:row inTable:tableView];
    }
    return nil;
}

- (NSView *)deviceCellForColumn:(NSString *)identifier row:(NSInteger)row inTable:(NSTableView *)tableView {
    if (row < 0 || row >= (NSInteger)_devices.count) return nil;

    XLFPPDevice *device = _devices[row];

    NSTableCellView *cellView = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cellView) {
        cellView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 36)];
        cellView.identifier = identifier;

        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.frame = cellView.bounds;
        textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        textField.font = [NSFont systemFontOfSize:12];
        [cellView addSubview:textField];
        cellView.textField = textField;
    }

    if ([identifier isEqualToString:@"hostname"]) {
        cellView.textField.stringValue = device.hostname ?: @"";
        cellView.textField.textColor = device.reachable ? [NSColor labelColor] : [NSColor tertiaryLabelColor];
    } else if ([identifier isEqualToString:@"ip"]) {
        cellView.textField.stringValue = device.ipAddress ?: @"";
    } else if ([identifier isEqualToString:@"version"]) {
        cellView.textField.stringValue = device.version ?: @"";
        cellView.textField.textColor = device.reachable ? [NSColor secondaryLabelColor] : [NSColor tertiaryLabelColor];
    }

    return cellView;
}

- (NSView *)fileCellForColumn:(NSString *)identifier row:(NSInteger)row inTable:(NSTableView *)tableView {
    if (row < 0 || row >= (NSInteger)_fileEntries.count) return nil;

    XLFPPFileEntry *entry = _fileEntries[row];

    if ([identifier isEqualToString:@"selected"]) {
        NSButton *checkbox = [tableView makeViewWithIdentifier:@"selectedCheckbox" owner:self];
        if (!checkbox) {
            checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(fileCheckboxChanged:)];
            checkbox.identifier = @"selectedCheckbox";
        }
        checkbox.state = entry.selected ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.tag = row;
        return checkbox;
    }

    NSTableCellView *cellView = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cellView) {
        cellView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 22)];
        cellView.identifier = identifier;

        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.frame = cellView.bounds;
        textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        textField.font = [NSFont systemFontOfSize:12];
        [cellView addSubview:textField];
        cellView.textField = textField;
    }

    if ([identifier isEqualToString:@"filename"]) {
        cellView.textField.stringValue = entry.filename;
    } else if ([identifier isEqualToString:@"type"]) {
        cellView.textField.stringValue = entry.fileType;
        cellView.textField.textColor = [NSColor secondaryLabelColor];
    } else if ([identifier isEqualToString:@"size"]) {
        cellView.textField.stringValue = [entry fileSizeString];
        cellView.textField.textColor = [NSColor secondaryLabelColor];
        cellView.textField.alignment = NSTextAlignmentRight;
    }

    return cellView;
}

- (void)fileCheckboxChanged:(NSButton *)sender {
    NSInteger row = sender.tag;
    if (row >= 0 && row < (NSInteger)_fileEntries.count) {
        _fileEntries[row].selected = (sender.state == NSControlStateValueOn);
    }
}

#pragma mark - Utility

- (void)showAlert:(NSString *)title message:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

@end
