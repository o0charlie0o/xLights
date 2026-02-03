/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLCheckSequenceReportWindow.h"

/// Report section identifiers.
NSString * const kXLReportSectionNetwork = @"network";
NSString * const kXLReportSectionController = @"controller";
NSString * const kXLReportSectionModel = @"model";
NSString * const kXLReportSectionSequence = @"sequence";
NSString * const kXLReportSectionEffect = @"effect";
NSString * const kXLReportSectionMedia = @"media";
NSString * const kXLReportSectionPreference = @"preference";
NSString * const kXLReportSectionOS = @"os";

static const CGFloat kWindowWidth = 900.0;
static const CGFloat kWindowHeight = 700.0;
static const CGFloat kSidebarWidth = 200.0;

#pragma mark - XLReportSectionItem

@implementation XLReportSectionItem

- (instancetype)initWithId:(NSString *)sectionId
                     title:(NSString *)title
                      icon:(NSString *)iconName {
    self = [super init];
    if (self) {
        _sectionId = [sectionId copy];
        _title = [title copy];
        _iconName = [iconName copy];
        _errorCount = 0;
        _warningCount = 0;
        _infoCount = 0;
    }
    return self;
}

@end

#pragma mark - XLReportFilterBar

@interface XLReportFilterBar ()
@property (nonatomic, strong) NSSegmentedControl *severitySegment;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSTextField *countsLabel;
@end

@implementation XLReportFilterBar

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _severityFilter = -1;
        _searchText = @"";

        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];

        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // Severity filter segment
    _severitySegment = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(10, 8, 250, 24)];
    _severitySegment.segmentCount = 4;
    [_severitySegment setLabel:@"All" forSegment:0];
    [_severitySegment setLabel:@"Errors" forSegment:1];
    [_severitySegment setLabel:@"Warnings" forSegment:2];
    [_severitySegment setLabel:@"Info" forSegment:3];
    _severitySegment.selectedSegment = 0;
    _severitySegment.target = self;
    _severitySegment.action = @selector(severityChanged:);
    [self addSubview:_severitySegment];

    // Counts label
    _countsLabel = [NSTextField labelWithString:@"0 errors, 0 warnings, 0 info"];
    _countsLabel.frame = NSMakeRect(270, 10, 200, 20);
    _countsLabel.textColor = [NSColor secondaryLabelColor];
    [self addSubview:_countsLabel];

    // Search field
    _searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(self.bounds.size.width - 210, 6, 200, 28)];
    _searchField.autoresizingMask = NSViewMinXMargin;
    _searchField.placeholderString = @"Search issues...";
    _searchField.target = self;
    _searchField.action = @selector(searchChanged:);
    [self addSubview:_searchField];
}

- (void)setErrorCount:(NSInteger)errors warningCount:(NSInteger)warnings infoCount:(NSInteger)infos {
    _countsLabel.stringValue = [NSString stringWithFormat:@"%ld error%@, %ld warning%@, %ld info",
                                (long)errors, errors == 1 ? @"" : @"s",
                                (long)warnings, warnings == 1 ? @"" : @"s",
                                (long)infos];

    // Update segment labels with counts
    [_severitySegment setLabel:[NSString stringWithFormat:@"All (%ld)", (long)(errors + warnings + infos)] forSegment:0];
    [_severitySegment setLabel:[NSString stringWithFormat:@"Errors (%ld)", (long)errors] forSegment:1];
    [_severitySegment setLabel:[NSString stringWithFormat:@"Warnings (%ld)", (long)warnings] forSegment:2];
    [_severitySegment setLabel:[NSString stringWithFormat:@"Info (%ld)", (long)infos] forSegment:3];
}

- (void)severityChanged:(NSSegmentedControl *)sender {
    _severityFilter = sender.selectedSegment - 1; // -1 = all, 0 = error, 1 = warning, 2 = info

    if ([_delegate respondsToSelector:@selector(reportFilterBar:didChangeSeverityFilter:)]) {
        [_delegate reportFilterBar:self didChangeSeverityFilter:_severityFilter];
    }
}

- (void)searchChanged:(NSSearchField *)sender {
    _searchText = sender.stringValue;

    if ([_delegate respondsToSelector:@selector(reportFilterBar:didChangeSearchText:)]) {
        [_delegate reportFilterBar:self didChangeSearchText:_searchText];
    }
}

@end

#pragma mark - XLReportSidebarView

@interface XLReportSidebarView ()
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSScrollView *scrollView;
@end

@implementation XLReportSidebarView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _sections = @[];

        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.hasVerticalScroller = YES;

    _outlineView = [[NSOutlineView alloc] initWithFrame:_scrollView.bounds];
    _outlineView.delegate = self;
    _outlineView.dataSource = self;
    _outlineView.headerView = nil;
    _outlineView.rowHeight = 32.0;
    _outlineView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleSourceList;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"sections"];
    column.width = self.bounds.size.width - 20;
    [_outlineView addTableColumn:column];
    _outlineView.outlineTableColumn = column;

    _scrollView.documentView = _outlineView;
    [self addSubview:_scrollView];
}

- (void)setSections:(NSArray<XLReportSectionItem *> *)sections {
    _sections = [sections copy];
    [_outlineView reloadData];
}

- (void)updateSection:(NSString *)sectionId
          errorCount:(NSInteger)errors
        warningCount:(NSInteger)warnings
           infoCount:(NSInteger)infos {
    for (XLReportSectionItem *item in _sections) {
        if ([item.sectionId isEqualToString:sectionId]) {
            item.errorCount = errors;
            item.warningCount = warnings;
            item.infoCount = infos;
            break;
        }
    }
    [_outlineView reloadData];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nil) {
        return _sections.count;
    }
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nil) {
        return _sections[index];
    }
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return NO;
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    XLReportSectionItem *section = (XLReportSectionItem *)item;

    NSTableCellView *cellView = [outlineView makeViewWithIdentifier:@"sectionCell" owner:self];
    if (!cellView) {
        cellView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 180, 32)];
        cellView.identifier = @"sectionCell";

        NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(4, 6, 20, 20)];
        [cellView addSubview:imageView];
        cellView.imageView = imageView;

        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.frame = NSMakeRect(28, 8, 100, 16);
        [cellView addSubview:textField];
        cellView.textField = textField;

        NSTextField *countField = [NSTextField labelWithString:@""];
        countField.frame = NSMakeRect(130, 8, 40, 16);
        countField.alignment = NSTextAlignmentRight;
        countField.textColor = [NSColor secondaryLabelColor];
        countField.tag = 100;
        [cellView addSubview:countField];
    }

    // Set icon
    if (@available(macOS 11.0, *)) {
        cellView.imageView.image = [NSImage imageWithSystemSymbolName:section.iconName ?: @"doc"
                                             accessibilityDescription:section.title];
    }

    // Set title
    cellView.textField.stringValue = section.title;

    // Set count
    NSTextField *countField = [cellView viewWithTag:100];
    NSInteger total = section.errorCount + section.warningCount + section.infoCount;
    if (total > 0) {
        countField.stringValue = [NSString stringWithFormat:@"%ld", (long)total];

        // Color based on severity
        if (section.errorCount > 0) {
            countField.textColor = [NSColor systemRedColor];
        } else if (section.warningCount > 0) {
            countField.textColor = [NSColor systemOrangeColor];
        } else {
            countField.textColor = [NSColor secondaryLabelColor];
        }
    } else {
        countField.stringValue = @"";
    }

    return cellView;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = _outlineView.selectedRow;
    if (row >= 0 && row < (NSInteger)_sections.count) {
        _selectedSectionId = _sections[row].sectionId;

        if ([_delegate respondsToSelector:@selector(reportSidebar:didSelectSection:)]) {
            [_delegate reportSidebar:self didSelectSection:_selectedSectionId];
        }
    }
}

@end

#pragma mark - XLCheckSequenceReportWindow

@interface XLCheckSequenceReportWindow () <XLReportSidebarDelegate, XLReportFilterBarDelegate>
@property (nonatomic, strong) NSString *htmlContent;
@property (nonatomic, copy) NSString *sequencePath;
@property (nonatomic, copy) NSString *showFolder;
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) XLReportSidebarView *sidebarView;
@property (nonatomic, strong) XLReportFilterBar *filterBar;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSToolbar *toolbar;
@end

@implementation XLCheckSequenceReportWindow

- (instancetype)initWithHTMLContent:(NSString *)htmlContent {
    NSRect windowRect = NSMakeRect(0, 0, kWindowWidth, kWindowHeight);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:windowRect
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskMiniaturizable |
                                                            NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];

    self = [super initWithWindow:window];
    if (self) {
        _htmlContent = [htmlContent copy];
        _totalErrors = 0;
        _totalWarnings = 0;
        _totalInfos = 0;

        window.title = @"Check Sequence Report";
        window.delegate = (id<NSWindowDelegate>)self;
        [window center];

        [self setupToolbar];
        [self setupUI];
        [self loadReport];
    }
    return self;
}

- (instancetype)initAndRunChecksForSequence:(NSString *)sequencePath
                                 showFolder:(NSString *)showFolder {
    self = [self initWithHTMLContent:@"<html><body><p>Running checks...</p></body></html>"];
    if (self) {
        _sequencePath = [sequencePath copy];
        _showFolder = [showFolder copy];
        // Checks would be run via engine bridge
    }
    return self;
}

- (void)setupToolbar {
    _toolbar = [[NSToolbar alloc] initWithIdentifier:@"CheckSequenceReportToolbar"];
    _toolbar.delegate = (id<NSToolbarDelegate>)self;
    _toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    self.window.toolbar = _toolbar;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    // Filter bar at top
    _filterBar = [[XLReportFilterBar alloc] initWithFrame:NSMakeRect(0, kWindowHeight - 40, kWindowWidth, 40)];
    _filterBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _filterBar.delegate = self;
    [contentView addSubview:_filterBar];

    // Split view
    _splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, kWindowWidth, kWindowHeight - 40)];
    _splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitView.vertical = YES;

    // Sidebar
    _sidebarView = [[XLReportSidebarView alloc] initWithFrame:NSMakeRect(0, 0, kSidebarWidth, kWindowHeight - 40)];
    _sidebarView.delegate = self;

    // Default sections
    _sidebarView.sections = @[
        [[XLReportSectionItem alloc] initWithId:kXLReportSectionNetwork title:@"Network" icon:@"network"],
        [[XLReportSectionItem alloc] initWithId:kXLReportSectionController title:@"Controllers" icon:@"cpu"],
        [[XLReportSectionItem alloc] initWithId:kXLReportSectionModel title:@"Models" icon:@"cube"],
        [[XLReportSectionItem alloc] initWithId:kXLReportSectionSequence title:@"Sequence" icon:@"doc.text"],
        [[XLReportSectionItem alloc] initWithId:kXLReportSectionEffect title:@"Effects" icon:@"wand.and.stars"],
        [[XLReportSectionItem alloc] initWithId:kXLReportSectionMedia title:@"Media" icon:@"photo.on.rectangle"],
        [[XLReportSectionItem alloc] initWithId:kXLReportSectionPreference title:@"Preferences" icon:@"gearshape"],
        [[XLReportSectionItem alloc] initWithId:kXLReportSectionOS title:@"System" icon:@"desktopcomputer"]
    ];

    [_splitView addSubview:_sidebarView];

    // WebView for HTML report
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    _webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, kWindowWidth - kSidebarWidth, kWindowHeight - 40)
                                  configuration:config];
    _webView.navigationDelegate = self;
    [_splitView addSubview:_webView];

    [_splitView setPosition:kSidebarWidth ofDividerAtIndex:0];

    [contentView addSubview:_splitView];
}

- (void)loadReport {
    if (_htmlContent) {
        [_webView loadHTMLString:_htmlContent baseURL:nil];
    }
}

- (void)showWindow {
    [self showWindow:nil];
}

- (void)refreshReport {
    if (_engineBridge && _sequencePath) {
        // Re-run checks via engine bridge
        // Update _htmlContent with new results
        [self loadReport];
    }
}

- (void)exportToFile:(NSURL *)fileURL {
    NSError *error = nil;
    [_htmlContent writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];

    if (error) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Export Failed";
        alert.informativeText = error.localizedDescription;
        [alert runModal];
    }
}

- (void)printReport {
    NSPrintInfo *printInfo = [NSPrintInfo sharedPrintInfo];
    NSPrintOperation *printOp = [_webView printOperationWithPrintInfo:printInfo];
    [printOp runOperationModalForWindow:self.window delegate:nil didRunSelector:nil contextInfo:nil];
}

- (void)filterBySeverity:(XLIssueSeverity)severity {
    // Execute JavaScript to filter displayed issues
    NSString *script = [NSString stringWithFormat:@"filterBySeverity(%ld);", (long)severity];
    [_webView evaluateJavaScript:script completionHandler:nil];
}

- (void)clearFilter {
    [_webView evaluateJavaScript:@"clearFilter();" completionHandler:nil];
}

- (void)scrollToSection:(NSString *)sectionId {
    NSString *script = [NSString stringWithFormat:@"document.getElementById('%@').scrollIntoView({behavior: 'smooth'});", sectionId];
    [_webView evaluateJavaScript:script completionHandler:nil];
}

#pragma mark - XLReportSidebarDelegate

- (void)reportSidebar:(XLReportSidebarView *)sidebar didSelectSection:(NSString *)sectionId {
    [self scrollToSection:sectionId];
}

#pragma mark - XLReportFilterBarDelegate

- (void)reportFilterBar:(XLReportFilterBar *)filterBar didChangeSeverityFilter:(NSInteger)severity {
    if (severity < 0) {
        [self clearFilter];
    } else {
        [self filterBySeverity:(XLIssueSeverity)severity];
    }
}

- (void)reportFilterBar:(XLReportFilterBar *)filterBar didChangeSearchText:(NSString *)searchText {
    NSString *escaped = [searchText stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    NSString *script = [NSString stringWithFormat:@"searchIssues('%@');", escaped];
    [_webView evaluateJavaScript:script completionHandler:nil];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {

    NSURL *url = navigationAction.request.URL;

    // Handle internal links
    if ([url.scheme isEqualToString:@"xlights"]) {
        NSString *host = url.host;
        NSString *path = url.path;

        if ([host isEqualToString:@"model"]) {
            // Navigate to model
            NSString *modelName = [path stringByReplacingOccurrencesOfString:@"/" withString:@""];
            if ([_delegate respondsToSelector:@selector(checkSequenceReport:didRequestNavigateToModel:)]) {
                [_delegate checkSequenceReport:self didRequestNavigateToModel:modelName];
            }
        } else if ([host isEqualToString:@"controller"]) {
            // Navigate to controller
            NSString *controllerName = [path stringByReplacingOccurrencesOfString:@"/" withString:@""];
            if ([_delegate respondsToSelector:@selector(checkSequenceReport:didRequestNavigateToController:)]) {
                [_delegate checkSequenceReport:self didRequestNavigateToController:controllerName];
            }
        } else if ([host isEqualToString:@"effect"]) {
            // Navigate to effect
            NSString *effectId = [path stringByReplacingOccurrencesOfString:@"/" withString:@""];
            if ([_delegate respondsToSelector:@selector(checkSequenceReport:didRequestNavigateToEffect:)]) {
                [_delegate checkSequenceReport:self didRequestNavigateToEffect:effectId];
            }
        }

        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    // Allow other navigation
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // Parse report statistics from HTML
    [_webView evaluateJavaScript:@"getReportStats();" completionHandler:^(id result, NSError *error) {
        if ([result isKindOfClass:[NSDictionary class]]) {
            NSDictionary *stats = (NSDictionary *)result;
            self->_totalErrors = [stats[@"errors"] integerValue];
            self->_totalWarnings = [stats[@"warnings"] integerValue];
            self->_totalInfos = [stats[@"infos"] integerValue];

            [self->_filterBar setErrorCount:self->_totalErrors
                               warningCount:self->_totalWarnings
                                  infoCount:self->_totalInfos];
        }
    }];
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"refresh", @"export", @"print", NSToolbarFlexibleSpaceItemIdentifier];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"refresh", NSToolbarFlexibleSpaceItemIdentifier, @"export", @"print"];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];

    if ([itemIdentifier isEqualToString:@"refresh"]) {
        item.label = @"Refresh";
        item.paletteLabel = @"Refresh Report";
        if (@available(macOS 11.0, *)) {
            item.image = [NSImage imageWithSystemSymbolName:@"arrow.clockwise"
                                   accessibilityDescription:@"Refresh"];
        }
        item.target = self;
        item.action = @selector(refreshReport);
    } else if ([itemIdentifier isEqualToString:@"export"]) {
        item.label = @"Export";
        item.paletteLabel = @"Export Report";
        if (@available(macOS 11.0, *)) {
            item.image = [NSImage imageWithSystemSymbolName:@"square.and.arrow.up"
                                   accessibilityDescription:@"Export"];
        }
        item.target = self;
        item.action = @selector(exportClicked:);
    } else if ([itemIdentifier isEqualToString:@"print"]) {
        item.label = @"Print";
        item.paletteLabel = @"Print Report";
        if (@available(macOS 11.0, *)) {
            item.image = [NSImage imageWithSystemSymbolName:@"printer"
                                   accessibilityDescription:@"Print"];
        }
        item.target = self;
        item.action = @selector(printReport);
    }

    return item;
}

- (void)exportClicked:(id)sender {
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    savePanel.allowedFileTypes = @[@"html"];
    savePanel.nameFieldStringValue = @"CheckSequenceReport.html";

    [savePanel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && savePanel.URL) {
            [self exportToFile:savePanel.URL];
        }
    }];
}

@end
