/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLVendorModelWindowController.h"
#import "../XLEngineBridge.h"
#import <objc/runtime.h>

// Vendor catalog URLs
static NSString * const kVendorCatalogURL = @"https://raw.githubusercontent.com/xLightsSequencer/xLights/master/download/xlights_vendors.xml";
static NSString * const kVendorCatalogBackupURL = @"https://nutcracker123.com/xlights/vendors/xlights_vendors.xml";

// User defaults key for suppressed vendors
static NSString * const kSuppressedVendorsKey = @"XLVendorModelSuppressedVendors";

// Cache directory name
static NSString * const kCacheDirName = @"VendorModelCache";

#pragma mark - XLVendorCategoryNode

@implementation XLVendorCategoryNode

- (instancetype)init {
    self = [super init];
    if (self) {
        _children = [NSMutableArray array];
    }
    return self;
}

- (BOOL)hasDownloadableModel {
    return _xmodelURL.length > 0;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ name='%@' children=%lu>",
            NSStringFromClass([self class]), _name, (unsigned long)_children.count];
}

@end

#pragma mark - XLVendorModelWindowController

@interface XLVendorModelWindowController ()

@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSScrollView *outlineScrollView;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *statusLabel;

// Detail panel views
@property (nonatomic, strong) NSImageView *detailImageView;
@property (nonatomic, strong) NSTextField *detailNameLabel;
@property (nonatomic, strong) NSTextField *detailTextView;
@property (nonatomic, strong) NSButton *webLinkButton;
@property (nonatomic, strong) NSButton *insertModelButton;
@property (nonatomic, strong) NSButton *prevImageButton;
@property (nonatomic, strong) NSButton *nextImageButton;
@property (nonatomic, strong) NSTextField *imageCountLabel;
@property (nonatomic, strong) NSButton *suppressVendorCheckbox;

// Data
@property (nonatomic, strong) NSMutableArray<XLVendorCategoryNode *> *vendorNodes;
@property (nonatomic, strong) NSMutableArray<XLVendorCategoryNode *> *filteredNodes;
@property (nonatomic, assign) BOOL isFiltered;
@property (nonatomic, strong) NSURLSession *urlSession;
@property (nonatomic, copy) XLVendorModelCompletion completion;

// Image browsing state
@property (nonatomic, assign) NSInteger currentImageIndex;
@property (nonatomic, strong) NSMutableArray<NSImage *> *currentImages;
@property (nonatomic, strong) NSMutableArray<NSString *> *currentImageURLs;

// Cache
@property (nonatomic, copy) NSString *cacheDir;

@end

@implementation XLVendorModelWindowController

#pragma mark - Lifecycle

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 600)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Download Vendor Models";
    window.minSize = NSMakeSize(700, 400);
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        _vendorNodes = [NSMutableArray array];
        _filteredNodes = [NSMutableArray array];
        _currentImages = [NSMutableArray array];
        _currentImageURLs = [NSMutableArray array];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 30;
        config.timeoutIntervalForResource = 120;
        _urlSession = [NSURLSession sessionWithConfiguration:config];

        [self setupCacheDirectory];
        [self buildUI];
    }
    return self;
}

- (void)dealloc {
    [_urlSession invalidateAndCancel];
}

#pragma mark - Cache Directory

- (void)setupCacheDirectory {
    NSString *cacheBase = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"org.xlights.xlights";
    _cacheDir = [[cacheBase stringByAppendingPathComponent:bundleId] stringByAppendingPathComponent:kCacheDirName];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:_cacheDir]) {
        [fm createDirectoryAtPath:_cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (NSString *)cachedFilePathForURL:(NSString *)urlString extension:(NSString *)ext {
    NSString *hash = [NSString stringWithFormat:@"%lu", (unsigned long)[urlString hash]];
    if (ext.length > 0) {
        return [_cacheDir stringByAppendingPathComponent:[hash stringByAppendingPathExtension:ext]];
    }
    return [_cacheDir stringByAppendingPathComponent:hash];
}

#pragma mark - UI Construction

- (void)buildUI {
    NSView *contentView = self.window.contentView;

    // Main split: outline left, detail right
    NSSplitView *splitView = [[NSSplitView alloc] initWithFrame:contentView.bounds];
    splitView.dividerStyle = NSSplitViewDividerStyleThin;
    splitView.vertical = YES;
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:splitView];

    [NSLayoutConstraint activateConstraints:@[
        [splitView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [splitView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [splitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [splitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
    ]];

    // Left panel: search + tree + status
    NSView *leftPanel = [self buildLeftPanel];
    [splitView addSubview:leftPanel];

    // Right panel: detail view
    NSView *rightPanel = [self buildRightPanel];
    [splitView addSubview:rightPanel];

    // Set split position
    [splitView setPosition:300 ofDividerAtIndex:0];
    [splitView setHoldingPriority:NSLayoutPriorityDefaultLow - 1 forSubviewAtIndex:0];
}

- (NSView *)buildLeftPanel {
    NSView *panel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 600)];
    panel.translatesAutoresizingMaskIntoConstraints = NO;

    // Search field
    _searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.placeholderString = @"Search models...";
    _searchField.delegate = self;
    [panel addSubview:_searchField];

    // Outline view for vendor/category/model tree
    _outlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
    _outlineView.dataSource = self;
    _outlineView.delegate = self;
    _outlineView.allowsMultipleSelection = NO;
    _outlineView.usesAlternatingRowBackgroundColors = YES;
    _outlineView.rowHeight = 22;
    _outlineView.headerView = nil;

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Name";
    nameColumn.minWidth = 150;
    [_outlineView addTableColumn:nameColumn];
    _outlineView.outlineTableColumn = nameColumn;

    _outlineScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _outlineScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _outlineScrollView.documentView = _outlineView;
    _outlineScrollView.hasVerticalScroller = YES;
    _outlineScrollView.borderType = NSBezelBorder;
    [panel addSubview:_outlineScrollView];

    // Bottom status bar with progress indicator
    NSView *statusBar = [[NSView alloc] initWithFrame:NSZeroRect];
    statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:statusBar];

    _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _progressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _progressIndicator.style = NSProgressIndicatorStyleSpinning;
    _progressIndicator.controlSize = NSControlSizeSmall;
    _progressIndicator.displayedWhenStopped = NO;
    [statusBar addSubview:_progressIndicator];

    _statusLabel = [NSTextField labelWithString:@"Loading vendors..."];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [statusBar addSubview:_statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [panel.widthAnchor constraintGreaterThanOrEqualToConstant:200],

        [_searchField.topAnchor constraintEqualToAnchor:panel.topAnchor constant:8],
        [_searchField.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
        [_searchField.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],

        [_outlineScrollView.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:6],
        [_outlineScrollView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
        [_outlineScrollView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],
        [_outlineScrollView.bottomAnchor constraintEqualToAnchor:statusBar.topAnchor constant:-4],

        [statusBar.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
        [statusBar.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],
        [statusBar.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-6],
        [statusBar.heightAnchor constraintEqualToConstant:20],

        [_progressIndicator.leadingAnchor constraintEqualToAnchor:statusBar.leadingAnchor],
        [_progressIndicator.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],
        [_progressIndicator.widthAnchor constraintEqualToConstant:16],
        [_progressIndicator.heightAnchor constraintEqualToConstant:16],

        [_statusLabel.leadingAnchor constraintEqualToAnchor:_progressIndicator.trailingAnchor constant:6],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:statusBar.trailingAnchor],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],
    ]];

    return panel;
}

- (NSView *)buildRightPanel {
    NSView *panel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 600)];
    panel.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSNoBorder;
    scrollView.drawsBackground = NO;

    // Flipped container for top-to-bottom layout
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 800)];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    // Suppress vendor checkbox (hidden by default)
    _suppressVendorCheckbox = [NSButton checkboxWithTitle:@"Don't download this vendor's model list"
                                                  target:self
                                                  action:@selector(suppressVendorToggled:)];
    _suppressVendorCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    _suppressVendorCheckbox.hidden = YES;
    [container addSubview:_suppressVendorCheckbox];

    // Detail name label
    _detailNameLabel = [NSTextField labelWithString:@"Select a vendor or model"];
    _detailNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _detailNameLabel.font = [NSFont boldSystemFontOfSize:18];
    _detailNameLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _detailNameLabel.maximumNumberOfLines = 2;
    [container addSubview:_detailNameLabel];

    // Image browsing row
    NSView *imageRow = [[NSView alloc] initWithFrame:NSZeroRect];
    imageRow.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:imageRow];

    _prevImageButton = [NSButton buttonWithTitle:@"<" target:self action:@selector(prevImage:)];
    _prevImageButton.translatesAutoresizingMaskIntoConstraints = NO;
    _prevImageButton.bezelStyle = NSBezelStyleSmallSquare;
    _prevImageButton.hidden = YES;
    [imageRow addSubview:_prevImageButton];

    _detailImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _detailImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _detailImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _detailImageView.imageAlignment = NSImageAlignCenter;
    _detailImageView.wantsLayer = YES;
    _detailImageView.layer.cornerRadius = 4;
    _detailImageView.layer.borderColor = [[NSColor separatorColor] CGColor];
    _detailImageView.layer.borderWidth = 1;
    [imageRow addSubview:_detailImageView];

    _nextImageButton = [NSButton buttonWithTitle:@">" target:self action:@selector(nextImage:)];
    _nextImageButton.translatesAutoresizingMaskIntoConstraints = NO;
    _nextImageButton.bezelStyle = NSBezelStyleSmallSquare;
    _nextImageButton.hidden = YES;
    [imageRow addSubview:_nextImageButton];

    _imageCountLabel = [NSTextField labelWithString:@""];
    _imageCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _imageCountLabel.font = [NSFont systemFontOfSize:10];
    _imageCountLabel.textColor = [NSColor tertiaryLabelColor];
    _imageCountLabel.alignment = NSTextAlignmentCenter;
    [imageRow addSubview:_imageCountLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_prevImageButton.leadingAnchor constraintEqualToAnchor:imageRow.leadingAnchor],
        [_prevImageButton.centerYAnchor constraintEqualToAnchor:_detailImageView.centerYAnchor],
        [_prevImageButton.widthAnchor constraintEqualToConstant:28],

        [_detailImageView.leadingAnchor constraintEqualToAnchor:_prevImageButton.trailingAnchor constant:4],
        [_detailImageView.trailingAnchor constraintEqualToAnchor:_nextImageButton.leadingAnchor constant:-4],
        [_detailImageView.topAnchor constraintEqualToAnchor:imageRow.topAnchor],
        [_detailImageView.heightAnchor constraintEqualToConstant:220],

        [_nextImageButton.trailingAnchor constraintEqualToAnchor:imageRow.trailingAnchor],
        [_nextImageButton.centerYAnchor constraintEqualToAnchor:_detailImageView.centerYAnchor],
        [_nextImageButton.widthAnchor constraintEqualToConstant:28],

        [_imageCountLabel.topAnchor constraintEqualToAnchor:_detailImageView.bottomAnchor constant:2],
        [_imageCountLabel.centerXAnchor constraintEqualToAnchor:imageRow.centerXAnchor],
        [_imageCountLabel.bottomAnchor constraintEqualToAnchor:imageRow.bottomAnchor],
    ]];

    // Detail text (multiline)
    _detailTextView = [NSTextField wrappingLabelWithString:@""];
    _detailTextView.translatesAutoresizingMaskIntoConstraints = NO;
    _detailTextView.font = [NSFont systemFontOfSize:12];
    _detailTextView.selectable = YES;
    [container addSubview:_detailTextView];

    // Web link button
    _webLinkButton = [NSButton buttonWithTitle:@"Visit Website" target:self action:@selector(openWebLink:)];
    _webLinkButton.translatesAutoresizingMaskIntoConstraints = NO;
    _webLinkButton.bezelStyle = NSBezelStyleInline;
    _webLinkButton.hidden = YES;
    [container addSubview:_webLinkButton];

    // Insert model button
    _insertModelButton = [NSButton buttonWithTitle:@"Download & Insert Model" target:self action:@selector(insertModel:)];
    _insertModelButton.translatesAutoresizingMaskIntoConstraints = NO;
    _insertModelButton.bezelStyle = NSBezelStyleRegularSquare;
    _insertModelButton.controlSize = NSControlSizeLarge;
    _insertModelButton.keyEquivalent = @"\r";
    _insertModelButton.hidden = YES;
    [container addSubview:_insertModelButton];

    [NSLayoutConstraint activateConstraints:@[
        [_suppressVendorCheckbox.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [_suppressVendorCheckbox.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [_suppressVendorCheckbox.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],

        [_detailNameLabel.topAnchor constraintEqualToAnchor:_suppressVendorCheckbox.bottomAnchor constant:8],
        [_detailNameLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [_detailNameLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],

        [imageRow.topAnchor constraintEqualToAnchor:_detailNameLabel.bottomAnchor constant:12],
        [imageRow.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [imageRow.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],

        [_detailTextView.topAnchor constraintEqualToAnchor:imageRow.bottomAnchor constant:12],
        [_detailTextView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [_detailTextView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],

        [_webLinkButton.topAnchor constraintEqualToAnchor:_detailTextView.bottomAnchor constant:10],
        [_webLinkButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],

        [_insertModelButton.topAnchor constraintEqualToAnchor:_webLinkButton.bottomAnchor constant:16],
        [_insertModelButton.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [_insertModelButton.bottomAnchor constraintLessThanOrEqualToAnchor:container.bottomAnchor constant:-16],
    ]];

    scrollView.documentView = container;
    [panel addSubview:scrollView];

    // Make container fill width of scroll view
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:panel.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],

        [container.topAnchor constraintEqualToAnchor:scrollView.contentView.topAnchor],
        [container.leadingAnchor constraintEqualToAnchor:scrollView.contentView.leadingAnchor],
        [container.trailingAnchor constraintEqualToAnchor:scrollView.contentView.trailingAnchor],
    ]];

    return panel;
}

#pragma mark - Public API

- (void)showWithCompletion:(XLVendorModelCompletion)completion {
    _completion = completion;
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [self reloadVendors];
}

- (void)reloadVendors {
    [_vendorNodes removeAllObjects];
    [_filteredNodes removeAllObjects];
    [_outlineView reloadData];

    [_progressIndicator startAnimation:nil];
    _statusLabel.stringValue = @"Downloading vendor catalog...";

    __weak typeof(self) weakSelf = self;
    [self downloadXMLFromURL:kVendorCatalogURL completion:^(NSXMLDocument *doc, NSError *error) {
        if (!doc) {
            // Try backup URL
            [weakSelf downloadXMLFromURL:kVendorCatalogBackupURL completion:^(NSXMLDocument *backupDoc, NSError *backupError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (backupDoc) {
                        [weakSelf parseVendorCatalog:backupDoc];
                    } else {
                        [weakSelf showLoadError:@"Unable to download vendor catalog. Check your internet connection."];
                    }
                });
            }];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf parseVendorCatalog:doc];
            });
        }
    }];
}

#pragma mark - Vendor Catalog Parsing

- (void)parseVendorCatalog:(NSXMLDocument *)doc {
    NSXMLElement *root = [doc rootElement];
    NSArray<NSXMLElement *> *vendorElements = [root elementsForName:@"vendor"];

    NSInteger totalVendors = vendorElements.count;
    __block NSInteger loadedCount = 0;

    if (totalVendors == 0) {
        [self showLoadError:@"No vendors found in catalog"];
        return;
    }

    _statusLabel.stringValue = [NSString stringWithFormat:@"Loading 0/%ld vendors...", (long)totalVendors];

    for (NSXMLElement *vendorElem in vendorElements) {
        NSString *name = [[vendorElem elementsForName:@"name"].firstObject stringValue] ?: @"Unknown";
        NSString *link = [[vendorElem elementsForName:@"link"].firstObject stringValue];
        NSString *maxModelsStr = [[vendorElem elementsForName:@"maxmodels"].firstObject stringValue];
        NSInteger maxModels = maxModelsStr ? [maxModelsStr integerValue] : -1;

        if ([self isVendorSuppressed:name]) {
            // Create placeholder node for suppressed vendor
            XLVendorCategoryNode *vendorNode = [[XLVendorCategoryNode alloc] init];
            vendorNode.name = name;
            vendorNode.isVendor = YES;
            vendorNode.vendorSuppressed = YES;
            [_vendorNodes addObject:vendorNode];

            loadedCount++;
            [self updateLoadProgress:loadedCount total:totalVendors];
            continue;
        }

        if (!link || link.length == 0) {
            loadedCount++;
            [self updateLoadProgress:loadedCount total:totalVendors];
            continue;
        }

        __weak typeof(self) weakSelf = self;
        [self downloadXMLFromURL:link completion:^(NSXMLDocument *vendorDoc, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (vendorDoc) {
                    XLVendorCategoryNode *vendorNode = [weakSelf parseVendorDocument:vendorDoc maxModels:maxModels];
                    if (vendorNode) {
                        [weakSelf.vendorNodes addObject:vendorNode];
                    }
                } else {
                    NSLog(@"Failed to load vendor '%@': %@", name, error.localizedDescription);
                }

                loadedCount++;
                [weakSelf updateLoadProgress:loadedCount total:totalVendors];

                if (loadedCount >= totalVendors) {
                    [weakSelf vendorLoadingComplete];
                }
            });
        }];
    }

    // Handle case where all vendors are suppressed/skipped
    if (loadedCount >= totalVendors) {
        [self vendorLoadingComplete];
    }
}

- (void)updateLoadProgress:(NSInteger)loaded total:(NSInteger)total {
    _statusLabel.stringValue = [NSString stringWithFormat:@"Loading %ld/%ld vendors...", (long)loaded, (long)total];
}

- (void)vendorLoadingComplete {
    [_progressIndicator stopAnimation:nil];

    // Sort vendors by name
    [_vendorNodes sortUsingComparator:^NSComparisonResult(XLVendorCategoryNode *a, XLVendorCategoryNode *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];

    // Remove empty categories
    for (XLVendorCategoryNode *vendor in _vendorNodes) {
        [self pruneEmptyCategories:vendor];
    }

    [_outlineView reloadData];

    // Expand vendors
    for (XLVendorCategoryNode *vendor in _vendorNodes) {
        [_outlineView expandItem:vendor];
    }

    NSInteger modelCount = [self countModelsInNodes:_vendorNodes];
    _statusLabel.stringValue = [NSString stringWithFormat:@"%ld vendors, %ld models",
                                (long)_vendorNodes.count, (long)modelCount];
}

- (NSInteger)countModelsInNodes:(NSArray<XLVendorCategoryNode *> *)nodes {
    NSInteger count = 0;
    for (XLVendorCategoryNode *node in nodes) {
        if (node.isModel || node.isWiring) {
            count++;
        }
        count += [self countModelsInNodes:node.children];
    }
    return count;
}

- (void)pruneEmptyCategories:(XLVendorCategoryNode *)node {
    // First prune children recursively
    for (XLVendorCategoryNode *child in [node.children copy]) {
        [self pruneEmptyCategories:child];
    }

    // Remove categories with no children (unless they are model/wiring nodes)
    NSMutableArray *toRemove = [NSMutableArray array];
    for (XLVendorCategoryNode *child in node.children) {
        if (!child.isModel && !child.isWiring && !child.isVendor && child.children.count == 0) {
            [toRemove addObject:child];
        }
    }
    [node.children removeObjectsInArray:toRemove];
}

#pragma mark - Vendor Document Parsing

- (XLVendorCategoryNode *)parseVendorDocument:(NSXMLDocument *)doc maxModels:(NSInteger)maxModels {
    NSXMLElement *root = [doc rootElement];
    if (![[root.name lowercaseString] isEqualToString:@"modelinventory"]) {
        return nil;
    }

    XLVendorCategoryNode *vendorNode = [[XLVendorCategoryNode alloc] init];
    vendorNode.isVendor = YES;

    // Parse vendor info
    NSXMLElement *vendorElem = [root elementsForName:@"vendor"].firstObject;
    if (vendorElem) {
        vendorNode.name = [self xmlChildText:vendorElem name:@"name"] ?: @"Unknown";
        vendorNode.vendorContact = [self xmlChildText:vendorElem name:@"contact"];
        vendorNode.vendorEmail = [self xmlChildText:vendorElem name:@"email"];
        vendorNode.vendorPhone = [self xmlChildText:vendorElem name:@"phone"];
        vendorNode.vendorWebsite = [self xmlChildText:vendorElem name:@"website"];
        vendorNode.vendorFacebook = [self xmlChildText:vendorElem name:@"facebook"];
        vendorNode.vendorNotes = [self xmlChildText:vendorElem name:@"notes"];
        vendorNode.vendorLogoURL = [self xmlChildText:vendorElem name:@"logolink"];
    }

    // Parse categories
    NSXMLElement *categoriesElem = [root elementsForName:@"categories"].firstObject;
    if (categoriesElem) {
        [self parseCategoriesElement:categoriesElem intoNode:vendorNode vendor:vendorNode];
    }

    // Parse models
    NSXMLElement *modelsElem = [root elementsForName:@"models"].firstObject;
    if (modelsElem) {
        NSInteger modelCount = 0;
        for (NSXMLElement *modelElem in [modelsElem elementsForName:@"model"]) {
            modelCount++;
            if (maxModels > 0 && modelCount >= maxModels) break;

            XLVendorCategoryNode *modelNode = [self parseModelElement:modelElem vendor:vendorNode];
            if (modelNode) {
                // Add to appropriate category
                [self addModelNode:modelNode toVendor:vendorNode];
            }
        }
    }

    return vendorNode;
}

- (void)parseCategoriesElement:(NSXMLElement *)categoriesElem
                      intoNode:(XLVendorCategoryNode *)parentNode
                        vendor:(XLVendorCategoryNode *)vendor {
    for (NSXMLElement *catElem in [categoriesElem elementsForName:@"category"]) {
        XLVendorCategoryNode *catNode = [[XLVendorCategoryNode alloc] init];
        catNode.name = [self xmlChildText:catElem name:@"name"] ?: @"Unknown";
        catNode.categoryId = [self xmlChildText:catElem name:@"id"];
        catNode.parent = parentNode;

        // Parse nested categories
        NSXMLElement *nestedCats = [catElem elementsForName:@"categories"].firstObject;
        if (nestedCats) {
            [self parseCategoriesElement:nestedCats intoNode:catNode vendor:vendor];
        }

        [parentNode.children addObject:catNode];
    }
}

- (XLVendorCategoryNode *)parseModelElement:(NSXMLElement *)modelElem vendor:(XLVendorCategoryNode *)vendor {
    XLVendorCategoryNode *modelNode = [[XLVendorCategoryNode alloc] init];
    modelNode.isModel = YES;
    modelNode.name = [self xmlChildText:modelElem name:@"name"] ?: @"Unknown Model";

    // Category IDs for placement in the tree
    NSMutableArray *catIds = [NSMutableArray array];
    for (NSXMLElement *catIdElem in [modelElem elementsForName:@"categoryid"]) {
        NSString *catId = [catIdElem stringValue];
        if (catId.length > 0) [catIds addObject:catId];
    }

    modelNode.modelType = [self xmlChildText:modelElem name:@"type"];
    modelNode.modelMaterial = [self xmlChildText:modelElem name:@"material"];
    modelNode.modelWidth = [self xmlChildText:modelElem name:@"width"];
    modelNode.modelHeight = [self xmlChildText:modelElem name:@"height"];
    modelNode.modelDepth = [self xmlChildText:modelElem name:@"depth"];
    modelNode.modelPixelCount = [self xmlChildText:modelElem name:@"pixelcount"];
    modelNode.modelPixelSpacing = [self xmlChildText:modelElem name:@"pixelspacing"];
    modelNode.modelPixelDescription = [self xmlChildText:modelElem name:@"pixeldescription"];
    modelNode.modelNotes = [self xmlChildText:modelElem name:@"notes"];
    modelNode.modelWebLink = [self xmlChildText:modelElem name:@"weblink"];

    // Collect image URLs
    NSMutableArray *imageURLs = [NSMutableArray array];
    for (NSXMLElement *imgElem in [modelElem elementsForName:@"imagefile"]) {
        NSString *url = [imgElem stringValue];
        if (url.length > 0) [imageURLs addObject:url];
    }
    modelNode.modelImageURLs = imageURLs;

    // Parse wiring options
    NSArray<NSXMLElement *> *wiringElements = [modelElem elementsForName:@"wiring"];
    if (wiringElements.count > 1) {
        // Multiple wiring options - add as children of model
        for (NSXMLElement *wiringElem in wiringElements) {
            XLVendorCategoryNode *wiringNode = [self parseWiringElement:wiringElem
                                                              modelNode:modelNode
                                                            parentImages:imageURLs];
            if (wiringNode) {
                wiringNode.parent = modelNode;
                [modelNode.children addObject:wiringNode];
            }
        }
    } else if (wiringElements.count == 1) {
        // Single wiring - store directly on model node
        NSXMLElement *wiringElem = wiringElements.firstObject;
        modelNode.isWiring = YES;
        modelNode.wiringDescription = [self xmlChildText:wiringElem name:@"description"];
        modelNode.xmodelURL = [self xmlChildText:wiringElem name:@"xmodellink"];

        NSMutableArray *wiringImages = [NSMutableArray arrayWithArray:imageURLs];
        for (NSXMLElement *imgElem in [wiringElem elementsForName:@"imagefile"]) {
            NSString *url = [imgElem stringValue];
            if (url.length > 0) [wiringImages addObject:url];
        }
        modelNode.wiringImageURLs = wiringImages;
    }

    // Store category IDs as associated object for tree placement
    objc_setAssociatedObject(modelNode, "categoryIds", catIds, OBJC_ASSOCIATION_COPY);

    return modelNode;
}

- (XLVendorCategoryNode *)parseWiringElement:(NSXMLElement *)wiringElem
                                    modelNode:(XLVendorCategoryNode *)modelNode
                                 parentImages:(NSArray<NSString *> *)parentImages {
    XLVendorCategoryNode *node = [[XLVendorCategoryNode alloc] init];
    node.isWiring = YES;
    node.name = [self xmlChildText:wiringElem name:@"name"] ?: @"Default Wiring";
    node.wiringDescription = [self xmlChildText:wiringElem name:@"description"];
    node.xmodelURL = [self xmlChildText:wiringElem name:@"xmodellink"];

    // Inherit model properties
    node.modelType = modelNode.modelType;
    node.modelWidth = modelNode.modelWidth;
    node.modelHeight = modelNode.modelHeight;
    node.modelDepth = modelNode.modelDepth;
    node.modelPixelCount = modelNode.modelPixelCount;
    node.modelPixelSpacing = modelNode.modelPixelSpacing;
    node.modelPixelDescription = modelNode.modelPixelDescription;
    node.modelNotes = modelNode.modelNotes;
    node.modelWebLink = modelNode.modelWebLink;

    // Combine parent and wiring images
    NSMutableArray *allImages = [NSMutableArray arrayWithArray:parentImages];
    for (NSXMLElement *imgElem in [wiringElem elementsForName:@"imagefile"]) {
        NSString *url = [imgElem stringValue];
        if (url.length > 0) [allImages addObject:url];
    }
    node.wiringImageURLs = allImages;

    return node;
}

- (void)addModelNode:(XLVendorCategoryNode *)modelNode toVendor:(XLVendorCategoryNode *)vendor {
    NSArray *catIds = objc_getAssociatedObject(modelNode, "categoryIds");

    if (catIds.count == 0) {
        // No category - add directly to vendor
        modelNode.parent = vendor;
        [vendor.children addObject:modelNode];
        return;
    }

    // Find first matching category and add there
    for (NSString *catId in catIds) {
        XLVendorCategoryNode *category = [self findCategoryWithId:catId inNode:vendor];
        if (category) {
            modelNode.parent = category;
            [category.children addObject:modelNode];
            return;
        }
    }

    // No matching category found - add to vendor root
    modelNode.parent = vendor;
    [vendor.children addObject:modelNode];
}

- (XLVendorCategoryNode *)findCategoryWithId:(NSString *)categoryId inNode:(XLVendorCategoryNode *)node {
    if ([node.categoryId isEqualToString:categoryId]) {
        return node;
    }
    for (XLVendorCategoryNode *child in node.children) {
        XLVendorCategoryNode *found = [self findCategoryWithId:categoryId inNode:child];
        if (found) return found;
    }
    return nil;
}

#pragma mark - XML Helpers

- (NSString *)xmlChildText:(NSXMLElement *)parent name:(NSString *)name {
    NSXMLElement *child = [parent elementsForName:name].firstObject;
    NSString *text = [child stringValue];
    return (text.length > 0) ? text : nil;
}

#pragma mark - Network

- (void)downloadXMLFromURL:(NSString *)urlString completion:(void (^)(NSXMLDocument *doc, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        completion(nil, [NSError errorWithDomain:@"XLVendor" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}]);
        return;
    }

    // Check cache first
    NSString *cachePath = [self cachedFilePathForURL:urlString extension:@"xml"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:cachePath]) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:cachePath error:nil];
        NSDate *modDate = attrs[NSFileModificationDate];
        // Cache valid for 24 hours
        if (modDate && [[NSDate date] timeIntervalSinceDate:modDate] < 86400) {
            NSError *error = nil;
            NSXMLDocument *doc = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:cachePath]
                                                                      options:0
                                                                        error:&error];
            if (doc) {
                completion(doc, nil);
                return;
            }
        }
    }

    NSURLSessionDataTask *task = [_urlSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            completion(nil, error);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            completion(nil, [NSError errorWithDomain:@"XLVendor" code:(NSInteger)httpResponse.statusCode
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]}]);
            return;
        }

        // Save to cache
        [data writeToFile:cachePath atomically:YES];

        NSError *xmlError = nil;
        NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:&xmlError];
        completion(doc, xmlError);
    }];
    [task resume];
}

- (void)downloadFileFromURL:(NSString *)urlString completion:(void (^)(NSString *localPath, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        completion(nil, [NSError errorWithDomain:@"XLVendor" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}]);
        return;
    }

    // Determine extension from URL
    NSString *ext = [urlString pathExtension];
    if (ext.length == 0) ext = @"xmodel";

    NSString *cachePath = [self cachedFilePathForURL:urlString extension:ext];
    NSFileManager *fm = [NSFileManager defaultManager];

    // Check cache
    if ([fm fileExistsAtPath:cachePath]) {
        completion(cachePath, nil);
        return;
    }

    NSURLSessionDownloadTask *task = [_urlSession downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || !location) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            return;
        }

        NSError *moveError = nil;
        NSURL *destURL = [NSURL fileURLWithPath:cachePath];
        // Remove old file if exists
        [fm removeItemAtURL:destURL error:nil];
        [fm moveItemAtURL:location toURL:destURL error:&moveError];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (moveError) {
                completion(nil, moveError);
            } else {
                completion(cachePath, nil);
            }
        });
    }];
    [task resume];
}

- (void)downloadImageFromURL:(NSString *)urlString completion:(void (^)(NSImage *image))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        completion(nil);
        return;
    }

    NSString *ext = [urlString pathExtension] ?: @"png";
    NSString *cachePath = [self cachedFilePathForURL:urlString extension:ext];
    NSFileManager *fm = [NSFileManager defaultManager];

    // Check cache
    if ([fm fileExistsAtPath:cachePath]) {
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:cachePath];
        completion(image);
        return;
    }

    NSURLSessionDownloadTask *task = [_urlSession downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        NSImage *image = nil;
        if (location && !error) {
            NSURL *destURL = [NSURL fileURLWithPath:cachePath];
            [fm removeItemAtURL:destURL error:nil];
            [fm moveItemAtURL:location toURL:destURL error:nil];
            image = [[NSImage alloc] initWithContentsOfFile:cachePath];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(image);
        });
    }];
    [task resume];
}

#pragma mark - Vendor Suppression

- (BOOL)isVendorSuppressed:(NSString *)vendorName {
    NSArray *suppressed = [[NSUserDefaults standardUserDefaults] arrayForKey:kSuppressedVendorsKey];
    return [suppressed containsObject:vendorName];
}

- (void)setSuppressed:(BOOL)suppress forVendor:(NSString *)vendorName {
    NSMutableArray *suppressed = [[[NSUserDefaults standardUserDefaults] arrayForKey:kSuppressedVendorsKey] mutableCopy] ?: [NSMutableArray array];

    if (suppress && ![suppressed containsObject:vendorName]) {
        [suppressed addObject:vendorName];
    } else if (!suppress) {
        [suppressed removeObject:vendorName];
    }

    [[NSUserDefaults standardUserDefaults] setObject:suppressed forKey:kSuppressedVendorsKey];
}

#pragma mark - Error Display

- (void)showLoadError:(NSString *)message {
    [_progressIndicator stopAnimation:nil];
    _statusLabel.stringValue = message;
    _statusLabel.textColor = [NSColor systemRedColor];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (!item) {
        return _isFiltered ? (NSInteger)_filteredNodes.count : (NSInteger)_vendorNodes.count;
    }

    XLVendorCategoryNode *node = (XLVendorCategoryNode *)item;
    return (NSInteger)node.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (!item) {
        NSArray *source = _isFiltered ? _filteredNodes : _vendorNodes;
        if (index >= 0 && index < (NSInteger)source.count) {
            return source[(NSUInteger)index];
        }
        return nil;
    }

    XLVendorCategoryNode *node = (XLVendorCategoryNode *)item;
    if (index >= 0 && index < (NSInteger)node.children.count) {
        return node.children[(NSUInteger)index];
    }
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    XLVendorCategoryNode *node = (XLVendorCategoryNode *)item;
    return node.children.count > 0;
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    XLVendorCategoryNode *node = (XLVendorCategoryNode *)item;

    NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"VendorCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"VendorCell";

        NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [cell addSubview:imageView];
        cell.imageView = imageView;

        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:textField];
        cell.textField = textField;

        [NSLayoutConstraint activateConstraints:@[
            [imageView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [imageView.widthAnchor constraintEqualToConstant:16],
            [imageView.heightAnchor constraintEqualToConstant:16],

            [textField.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor constant:4],
            [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    cell.textField.stringValue = node.name ?: @"";

    // Set icon and color based on node type
    if (node.isVendor) {
        cell.imageView.image = [NSImage imageWithSystemSymbolName:@"building.2" accessibilityDescription:@"Vendor"];
        cell.textField.font = [NSFont boldSystemFontOfSize:13];
        cell.textField.textColor = node.vendorSuppressed ? [NSColor tertiaryLabelColor] : [NSColor labelColor];
    } else if (node.isModel || node.isWiring) {
        cell.imageView.image = [NSImage imageWithSystemSymbolName:@"cube" accessibilityDescription:@"Model"];
        cell.textField.font = [NSFont systemFontOfSize:12];
        // Blue/cyan for models with download, orange for those without
        if (node.hasDownloadableModel || (node.children.count > 0 && node.children.firstObject.hasDownloadableModel)) {
            cell.textField.textColor = [NSColor systemCyanColor];
        } else {
            cell.textField.textColor = [NSColor systemOrangeColor];
        }
    } else {
        // Category
        cell.imageView.image = [NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:@"Category"];
        cell.textField.font = [NSFont systemFontOfSize:12];
        cell.textField.textColor = [NSColor labelColor];
    }

    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = _outlineView.selectedRow;
    if (row < 0) {
        [self clearDetailPanel];
        return;
    }

    XLVendorCategoryNode *node = [_outlineView itemAtRow:row];
    if (!node) {
        [self clearDetailPanel];
        return;
    }

    if (node.isVendor) {
        [self showVendorDetail:node];
    } else if (node.isWiring) {
        [self showModelDetail:node];
    } else if (node.isModel) {
        [self showModelDetail:node];
    } else {
        // Category - show vendor info for the parent vendor
        XLVendorCategoryNode *vendor = [self findVendorForNode:node];
        if (vendor) {
            [self showVendorDetail:vendor];
        } else {
            [self clearDetailPanel];
        }
    }
}

#pragma mark - Detail Panel

- (void)clearDetailPanel {
    _detailNameLabel.stringValue = @"Select a vendor or model";
    _detailTextView.stringValue = @"";
    _detailImageView.image = nil;
    _webLinkButton.hidden = YES;
    _insertModelButton.hidden = YES;
    _prevImageButton.hidden = YES;
    _nextImageButton.hidden = YES;
    _imageCountLabel.stringValue = @"";
    _suppressVendorCheckbox.hidden = YES;
    [_currentImages removeAllObjects];
    [_currentImageURLs removeAllObjects];
    _currentImageIndex = 0;
}

- (void)showVendorDetail:(XLVendorCategoryNode *)vendor {
    _detailNameLabel.stringValue = vendor.name ?: @"Unknown Vendor";
    _insertModelButton.hidden = YES;

    // Suppress checkbox
    _suppressVendorCheckbox.hidden = NO;
    _suppressVendorCheckbox.state = vendor.vendorSuppressed ? NSControlStateValueOn : NSControlStateValueOff;

    // Build description text
    NSMutableString *desc = [NSMutableString string];
    if (vendor.vendorContact.length > 0) {
        [desc appendFormat:@"Contact: %@\n", vendor.vendorContact];
    }
    if (vendor.vendorPhone.length > 0) {
        [desc appendFormat:@"Phone: %@\n", vendor.vendorPhone];
    }
    if (vendor.vendorEmail.length > 0) {
        [desc appendFormat:@"Email: %@\n", vendor.vendorEmail];
    }
    if (vendor.vendorNotes.length > 0) {
        [desc appendFormat:@"\n%@\n", vendor.vendorNotes];
    }
    _detailTextView.stringValue = desc;

    // Website link
    if (vendor.vendorWebsite.length > 0) {
        _webLinkButton.hidden = NO;
        _webLinkButton.title = [NSString stringWithFormat:@"Visit %@", vendor.vendorWebsite];
        _webLinkButton.toolTip = vendor.vendorWebsite;
    } else {
        _webLinkButton.hidden = YES;
    }

    // Load vendor logo
    [_currentImages removeAllObjects];
    [_currentImageURLs removeAllObjects];
    _currentImageIndex = 0;
    _prevImageButton.hidden = YES;
    _nextImageButton.hidden = YES;
    _imageCountLabel.stringValue = @"";

    if (vendor.vendorLogoURL.length > 0) {
        __weak typeof(self) weakSelf = self;
        [self downloadImageFromURL:vendor.vendorLogoURL completion:^(NSImage *image) {
            if (image) {
                weakSelf.detailImageView.image = image;
            } else {
                weakSelf.detailImageView.image = nil;
            }
        }];
    } else {
        _detailImageView.image = nil;
    }
}

- (void)showModelDetail:(XLVendorCategoryNode *)node {
    _detailNameLabel.stringValue = node.name ?: @"Unknown Model";
    _suppressVendorCheckbox.hidden = YES;

    // Build description text
    NSMutableString *desc = [NSMutableString string];
    if (node.modelType.length > 0) {
        [desc appendFormat:@"Type: %@\n", node.modelType];
    }
    if (node.modelMaterial.length > 0) {
        [desc appendFormat:@"Material: %@\n", node.modelMaterial];
    }
    if (node.modelWidth.length > 0) {
        [desc appendFormat:@"Width: %@\n", node.modelWidth];
    }
    if (node.modelHeight.length > 0) {
        [desc appendFormat:@"Height: %@\n", node.modelHeight];
    }
    if (node.modelDepth.length > 0) {
        [desc appendFormat:@"Depth: %@\n", node.modelDepth];
    }
    if (node.modelPixelCount.length > 0) {
        [desc appendFormat:@"Pixel Count: %@\n", node.modelPixelCount];
    }
    if (node.modelPixelSpacing.length > 0) {
        [desc appendFormat:@"Pixel Spacing: %@\n", node.modelPixelSpacing];
    }
    if (node.modelPixelDescription.length > 0) {
        [desc appendFormat:@"Pixel Description: %@\n", node.modelPixelDescription];
    }
    if (node.modelNotes.length > 0) {
        [desc appendFormat:@"\n%@\n", node.modelNotes];
    }
    if (node.isWiring && node.wiringDescription.length > 0) {
        [desc appendFormat:@"\nWiring: %@\n", node.wiringDescription];
    }
    _detailTextView.stringValue = desc;

    // Web link
    if (node.modelWebLink.length > 0) {
        _webLinkButton.hidden = NO;
        NSURL *webURL = [NSURL URLWithString:node.modelWebLink];
        _webLinkButton.title = [NSString stringWithFormat:@"View at %@", webURL.host ?: node.modelWebLink];
        _webLinkButton.toolTip = node.modelWebLink;
    } else {
        _webLinkButton.hidden = YES;
    }

    // Insert model button
    if (node.hasDownloadableModel) {
        _insertModelButton.hidden = NO;
    } else {
        _insertModelButton.hidden = YES;
    }

    // Load images
    [_currentImages removeAllObjects];
    [_currentImageURLs removeAllObjects];
    _currentImageIndex = 0;

    NSArray<NSString *> *imageURLs = node.wiringImageURLs ?: node.modelImageURLs;
    if (imageURLs.count > 0) {
        [_currentImageURLs addObjectsFromArray:imageURLs];
        [self loadImageAtIndex:0];

        _prevImageButton.hidden = (imageURLs.count <= 1);
        _nextImageButton.hidden = (imageURLs.count <= 1);
        [self updateImageNavigationState];
    } else {
        _detailImageView.image = nil;
        _prevImageButton.hidden = YES;
        _nextImageButton.hidden = YES;
        _imageCountLabel.stringValue = @"";
    }
}

#pragma mark - Image Navigation

- (void)loadImageAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_currentImageURLs.count) return;

    _currentImageIndex = index;
    [self updateImageNavigationState];

    // Check if already loaded
    if (index < (NSInteger)_currentImages.count && _currentImages[(NSUInteger)index] != (id)[NSNull null]) {
        _detailImageView.image = _currentImages[(NSUInteger)index];
        return;
    }

    // Ensure array is large enough
    while ((NSInteger)_currentImages.count <= index) {
        [_currentImages addObject:(id)[NSNull null]];
    }

    NSString *urlString = _currentImageURLs[(NSUInteger)index];
    _detailImageView.image = nil;

    __weak typeof(self) weakSelf = self;
    [self downloadImageFromURL:urlString completion:^(NSImage *image) {
        if (image && index < (NSInteger)weakSelf.currentImages.count) {
            weakSelf.currentImages[(NSUInteger)index] = image;
            if (weakSelf.currentImageIndex == index) {
                weakSelf.detailImageView.image = image;
            }
        }
    }];
}

- (void)updateImageNavigationState {
    _prevImageButton.enabled = (_currentImageIndex > 0);
    _nextImageButton.enabled = (_currentImageIndex < (NSInteger)_currentImageURLs.count - 1);

    if (_currentImageURLs.count > 1) {
        _imageCountLabel.stringValue = [NSString stringWithFormat:@"%ld of %lu",
                                        (long)(_currentImageIndex + 1),
                                        (unsigned long)_currentImageURLs.count];
    } else {
        _imageCountLabel.stringValue = @"";
    }
}

- (void)prevImage:(id)sender {
    if (_currentImageIndex > 0) {
        [self loadImageAtIndex:_currentImageIndex - 1];
    }
}

- (void)nextImage:(id)sender {
    if (_currentImageIndex < (NSInteger)_currentImageURLs.count - 1) {
        [self loadImageAtIndex:_currentImageIndex + 1];
    }
}

#pragma mark - Actions

- (void)openWebLink:(id)sender {
    NSInteger row = _outlineView.selectedRow;
    if (row < 0) return;

    XLVendorCategoryNode *node = [_outlineView itemAtRow:row];
    NSString *urlString = nil;

    if (node.isVendor) {
        urlString = node.vendorWebsite;
    } else {
        urlString = node.modelWebLink;
    }

    if (urlString.length > 0) {
        NSURL *url = [NSURL URLWithString:urlString];
        if (url) {
            [[NSWorkspace sharedWorkspace] openURL:url];
        }
    }
}

- (void)insertModel:(id)sender {
    NSInteger row = _outlineView.selectedRow;
    if (row < 0) return;

    XLVendorCategoryNode *node = [_outlineView itemAtRow:row];
    if (!node.hasDownloadableModel) return;

    [self downloadAndImportModel:node];
}

- (void)suppressVendorToggled:(NSButton *)sender {
    NSInteger row = _outlineView.selectedRow;
    if (row < 0) return;

    XLVendorCategoryNode *node = [_outlineView itemAtRow:row];
    if (!node.isVendor) return;

    BOOL suppress = (sender.state == NSControlStateValueOn);
    [self setSuppressed:suppress forVendor:node.name];
    node.vendorSuppressed = suppress;

    if (!suppress) {
        // User unchecked - inform they need to reload
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Reload Required";
        alert.informativeText = @"Close and reopen the vendor download window to load this vendor's model list.";
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }
}

#pragma mark - Model Download & Import

- (void)downloadAndImportModel:(XLVendorCategoryNode *)node {
    NSString *xmodelURL = node.xmodelURL;
    if (!xmodelURL || xmodelURL.length == 0) return;

    _insertModelButton.enabled = NO;
    _insertModelButton.title = @"Downloading...";
    [_progressIndicator startAnimation:nil];
    _statusLabel.stringValue = @"Downloading model file...";

    __weak typeof(self) weakSelf = self;
    [self downloadFileFromURL:xmodelURL completion:^(NSString *localPath, NSError *error) {
        weakSelf.insertModelButton.enabled = YES;
        weakSelf.insertModelButton.title = @"Download & Insert Model";
        [weakSelf.progressIndicator stopAnimation:nil];

        if (error || !localPath) {
            weakSelf.statusLabel.stringValue = @"Download failed";
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Download Failed";
            alert.informativeText = error.localizedDescription ?: @"Unable to download model file.";
            alert.alertStyle = NSAlertStyleWarning;
            [alert addButtonWithTitle:@"OK"];
            [alert beginSheetModalForWindow:weakSelf.window completionHandler:nil];
            return;
        }

        // Handle zip files
        NSString *modelFilePath = localPath;
        if ([[localPath pathExtension].lowercaseString isEqualToString:@"zip"]) {
            modelFilePath = [weakSelf extractXModelFromZip:localPath];
            if (!modelFilePath) {
                weakSelf.statusLabel.stringValue = @"No .xmodel found in archive";
                return;
            }
        }

        weakSelf.statusLabel.stringValue = @"Model downloaded successfully";

        // Copy to show folder's modeldownload directory if we have a show folder
        NSString *finalPath = modelFilePath;
        if (weakSelf.showFolderPath.length > 0) {
            NSString *downloadDir = [weakSelf.showFolderPath stringByAppendingPathComponent:@"modeldownload"];
            NSFileManager *fm = [NSFileManager defaultManager];
            if (![fm fileExistsAtPath:downloadDir]) {
                [fm createDirectoryAtPath:downloadDir withIntermediateDirectories:YES attributes:nil error:nil];
            }

            NSString *destPath = [downloadDir stringByAppendingPathComponent:[modelFilePath lastPathComponent]];
            if (![fm fileExistsAtPath:destPath]) {
                [fm copyItemAtPath:modelFilePath toPath:destPath error:nil];
            }
            finalPath = destPath;
        }

        // Import via engine bridge if available
        if (weakSelf.engineBridge) {
            BOOL imported = [weakSelf.engineBridge importModelFromFile:finalPath];
            if (imported) {
                weakSelf.statusLabel.stringValue = @"Model imported successfully";
            }
        }

        // Notify completion
        if (weakSelf.completion) {
            weakSelf.completion(YES, finalPath);
        }
    }];
}

- (NSString *)extractXModelFromZip:(NSString *)zipPath {
    // Use NSFileManager and built-in unzip support
    NSString *extractDir = [[zipPath stringByDeletingPathExtension] stringByAppendingString:@"_extracted"];
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:extractDir]) {
        [fm createDirectoryAtPath:extractDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // Use /usr/bin/ditto to extract zip (standard macOS tool)
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
    task.arguments = @[@"-xk", zipPath, extractDir];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    NSError *error = nil;
    [task launchAndReturnError:&error];
    if (error) {
        NSLog(@"Failed to extract zip: %@", error);
        return nil;
    }
    [task waitUntilExit];

    // Find .xmodel file in extracted directory
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:extractDir];
    NSString *filename;
    while ((filename = [enumerator nextObject])) {
        if ([[filename pathExtension].lowercaseString isEqualToString:@"xmodel"]) {
            return [extractDir stringByAppendingPathComponent:filename];
        }
    }

    return nil;
}

#pragma mark - NSSearchFieldDelegate

- (void)controlTextDidChange:(NSNotification *)notification {
    NSSearchField *searchField = notification.object;
    if (searchField != _searchField) return;

    NSString *query = [searchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (query.length == 0) {
        _isFiltered = NO;
        [_filteredNodes removeAllObjects];
        [_outlineView reloadData];

        // Re-expand vendors
        for (XLVendorCategoryNode *vendor in _vendorNodes) {
            [_outlineView expandItem:vendor];
        }
        return;
    }

    _isFiltered = YES;
    [_filteredNodes removeAllObjects];

    // Search through all vendors and models
    for (XLVendorCategoryNode *vendor in _vendorNodes) {
        XLVendorCategoryNode *filteredVendor = [self filterNode:vendor query:query];
        if (filteredVendor) {
            [_filteredNodes addObject:filteredVendor];
        }
    }

    [_outlineView reloadData];

    // Expand all in filtered results
    for (XLVendorCategoryNode *vendor in _filteredNodes) {
        [_outlineView expandItem:vendor expandChildren:YES];
    }
}

- (XLVendorCategoryNode *)filterNode:(XLVendorCategoryNode *)node query:(NSString *)query {
    BOOL nameMatches = [node.name localizedCaseInsensitiveContainsString:query];

    // For leaf nodes (models/wiring), return if name matches
    if ((node.isModel || node.isWiring) && node.children.count == 0) {
        return nameMatches ? node : nil;
    }

    // For non-leaf nodes, check children
    NSMutableArray *matchedChildren = [NSMutableArray array];
    for (XLVendorCategoryNode *child in node.children) {
        XLVendorCategoryNode *matched = [self filterNode:child query:query];
        if (matched) {
            [matchedChildren addObject:matched];
        }
    }

    if (nameMatches || matchedChildren.count > 0) {
        XLVendorCategoryNode *filtered = [[XLVendorCategoryNode alloc] init];
        filtered.name = node.name;
        filtered.categoryId = node.categoryId;
        filtered.isVendor = node.isVendor;
        filtered.isModel = node.isModel;
        filtered.isWiring = node.isWiring;
        filtered.vendorContact = node.vendorContact;
        filtered.vendorEmail = node.vendorEmail;
        filtered.vendorPhone = node.vendorPhone;
        filtered.vendorWebsite = node.vendorWebsite;
        filtered.vendorFacebook = node.vendorFacebook;
        filtered.vendorNotes = node.vendorNotes;
        filtered.vendorLogoURL = node.vendorLogoURL;
        filtered.vendorSuppressed = node.vendorSuppressed;
        filtered.modelType = node.modelType;
        filtered.modelWebLink = node.modelWebLink;
        filtered.modelImageURLs = node.modelImageURLs;
        filtered.xmodelURL = node.xmodelURL;
        filtered.wiringImageURLs = node.wiringImageURLs;
        filtered.wiringDescription = node.wiringDescription;
        filtered.modelNotes = node.modelNotes;
        filtered.modelPixelCount = node.modelPixelCount;
        filtered.modelWidth = node.modelWidth;
        filtered.modelHeight = node.modelHeight;
        filtered.modelDepth = node.modelDepth;
        filtered.modelMaterial = node.modelMaterial;
        filtered.modelPixelSpacing = node.modelPixelSpacing;
        filtered.modelPixelDescription = node.modelPixelDescription;

        if (matchedChildren.count > 0) {
            [filtered.children addObjectsFromArray:matchedChildren];
        } else if (nameMatches) {
            // Include all original children if parent name matches
            [filtered.children addObjectsFromArray:node.children];
        }

        return filtered;
    }

    return nil;
}

#pragma mark - Helpers

- (XLVendorCategoryNode *)findVendorForNode:(XLVendorCategoryNode *)node {
    if (node.isVendor) return node;
    if (node.parent) return [self findVendorForNode:node.parent];

    // Walk up the outline view
    for (XLVendorCategoryNode *vendor in _vendorNodes) {
        if ([self node:vendor containsChild:node]) return vendor;
    }
    return nil;
}

- (BOOL)node:(XLVendorCategoryNode *)parent containsChild:(XLVendorCategoryNode *)target {
    if (parent == target) return YES;
    for (XLVendorCategoryNode *child in parent.children) {
        if ([self node:child containsChild:target]) return YES;
    }
    return NO;
}

@end
