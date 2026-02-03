/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class XLEngineBridge;
@class XLCheckSequenceReportWindow;

/// Issue severity levels matching C++ CheckSequenceReport::ReportIssue::Type.
typedef NS_ENUM(NSInteger, XLIssueSeverity) {
    XLIssueSeverityInfo = 0,
    XLIssueSeverityWarning = 1,
    XLIssueSeverityCritical = 2
};

/// Report issue structure using C types for heap safety.
typedef struct XLReportIssue {
    int severity;               // XLIssueSeverity
    char message[1024];         // Issue message
    char category[64];          // Issue category
} XLReportIssue;

/// Report section structure.
typedef struct XLReportSection {
    char sectionId[64];         // Unique identifier
    char icon[64];              // Icon identifier
    char title[256];            // Display title
    char description[512];      // Short description
    int errorCount;             // Number of errors
    int warningCount;           // Number of warnings
    int issueCount;             // Total issues
} XLReportSection;

/// Maximum report sections and issues.
#define XL_MAX_REPORT_SECTIONS 20
#define XL_MAX_ISSUES_PER_SECTION 1000

/// Report section identifiers.
extern NSString * const kXLReportSectionNetwork;
extern NSString * const kXLReportSectionController;
extern NSString * const kXLReportSectionModel;
extern NSString * const kXLReportSectionSequence;
extern NSString * const kXLReportSectionEffect;
extern NSString * const kXLReportSectionMedia;
extern NSString * const kXLReportSectionPreference;
extern NSString * const kXLReportSectionOS;

/// Forward protocol declarations.
@protocol XLCheckSequenceReportDelegate;
@protocol XLReportSidebarDelegate;
@protocol XLReportFilterBarDelegate;

/// Delegate protocol for report window actions.
@protocol XLCheckSequenceReportDelegate <NSObject>
@optional
- (void)checkSequenceReportDidClose:(XLCheckSequenceReportWindow *)window;
- (void)checkSequenceReport:(XLCheckSequenceReportWindow *)window didRequestNavigateToModel:(NSString *)modelName;
- (void)checkSequenceReport:(XLCheckSequenceReportWindow *)window didRequestNavigateToController:(NSString *)controllerName;
- (void)checkSequenceReport:(XLCheckSequenceReportWindow *)window didRequestNavigateToEffect:(NSString *)effectId;
@end

/// Sidebar section item for outline view.
@interface XLReportSectionItem : NSObject

@property (nonatomic, copy) NSString *sectionId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, assign) NSInteger errorCount;
@property (nonatomic, assign) NSInteger warningCount;
@property (nonatomic, assign) NSInteger infoCount;

- (instancetype)initWithId:(NSString *)sectionId
                     title:(NSString *)title
                      icon:(NSString *)iconName;

@end

/// Window controller for displaying sequence validation reports.
/// Uses WKWebView to display the HTML report with native navigation.
@interface XLCheckSequenceReportWindow : NSWindowController <WKNavigationDelegate, NSOutlineViewDelegate, NSOutlineViewDataSource>

/// Engine bridge for running checks.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Delegate for actions.
@property (nonatomic, weak) id<XLCheckSequenceReportDelegate> delegate;

/// Initialize with report HTML content.
- (instancetype)initWithHTMLContent:(NSString *)htmlContent;

/// Initialize and run checks immediately.
- (instancetype)initAndRunChecksForSequence:(NSString *)sequencePath
                                 showFolder:(NSString *)showFolder;

/// Show the window.
- (void)showWindow;

/// Refresh the report (re-run checks).
- (void)refreshReport;

/// Export report to file.
- (void)exportToFile:(NSURL *)fileURL;

/// Print the report.
- (void)printReport;

/// Filter issues by severity.
- (void)filterBySeverity:(XLIssueSeverity)severity;

/// Show all issues (clear filter).
- (void)clearFilter;

/// Jump to section.
- (void)scrollToSection:(NSString *)sectionId;

/// Report statistics.
@property (nonatomic, readonly) NSInteger totalErrors;
@property (nonatomic, readonly) NSInteger totalWarnings;
@property (nonatomic, readonly) NSInteger totalInfos;

@end

/// Native sidebar view for report sections.
@interface XLReportSidebarView : NSView <NSOutlineViewDelegate, NSOutlineViewDataSource>

/// Section items.
@property (nonatomic, strong) NSArray<XLReportSectionItem *> *sections;

/// Currently selected section.
@property (nonatomic, copy) NSString *selectedSectionId;

/// Delegate for selection changes.
@property (nonatomic, weak) id<XLReportSidebarDelegate> delegate;

/// Update section counts.
- (void)updateSection:(NSString *)sectionId
          errorCount:(NSInteger)errors
        warningCount:(NSInteger)warnings
           infoCount:(NSInteger)infos;

@end

@protocol XLReportSidebarDelegate <NSObject>
@optional
- (void)reportSidebar:(XLReportSidebarView *)sidebar didSelectSection:(NSString *)sectionId;
@end

/// Filter bar view for filtering report issues.
@interface XLReportFilterBar : NSView

/// Active severity filter (or -1 for all).
@property (nonatomic, assign) NSInteger severityFilter;

/// Search text filter.
@property (nonatomic, copy) NSString *searchText;

/// Delegate for filter changes.
@property (nonatomic, weak) id<XLReportFilterBarDelegate> delegate;

/// Update counts displayed in filter buttons.
- (void)setErrorCount:(NSInteger)errors warningCount:(NSInteger)warnings infoCount:(NSInteger)infos;

@end

@protocol XLReportFilterBarDelegate <NSObject>
@optional
- (void)reportFilterBar:(XLReportFilterBar *)filterBar didChangeSeverityFilter:(NSInteger)severity;
- (void)reportFilterBar:(XLReportFilterBar *)filterBar didChangeSearchText:(NSString *)searchText;
@end
