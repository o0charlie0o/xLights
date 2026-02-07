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

@class XLEngineBridge;

/// Completion handler for vendor model download.
/// @param imported YES if a model was successfully imported
/// @param modelFilePath Path to the downloaded .xmodel file, or nil
typedef void (^XLVendorModelCompletion)(BOOL imported, NSString *_Nullable modelFilePath);

/// Vendor model category node for the outline view.
@interface XLVendorCategoryNode : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *categoryId;
@property (nonatomic, strong) NSMutableArray<XLVendorCategoryNode *> *children;
@property (nonatomic, weak) XLVendorCategoryNode *parent;
@property (nonatomic, assign) BOOL isVendor;
@property (nonatomic, assign) BOOL isModel;
@property (nonatomic, assign) BOOL isWiring;

/// Vendor-level properties
@property (nonatomic, copy, nullable) NSString *vendorContact;
@property (nonatomic, copy, nullable) NSString *vendorEmail;
@property (nonatomic, copy, nullable) NSString *vendorPhone;
@property (nonatomic, copy, nullable) NSString *vendorWebsite;
@property (nonatomic, copy, nullable) NSString *vendorFacebook;
@property (nonatomic, copy, nullable) NSString *vendorNotes;
@property (nonatomic, copy, nullable) NSString *vendorLogoURL;
@property (nonatomic, assign) BOOL vendorSuppressed;

/// Model-level properties
@property (nonatomic, copy, nullable) NSString *modelType;
@property (nonatomic, copy, nullable) NSString *modelMaterial;
@property (nonatomic, copy, nullable) NSString *modelWidth;
@property (nonatomic, copy, nullable) NSString *modelHeight;
@property (nonatomic, copy, nullable) NSString *modelDepth;
@property (nonatomic, copy, nullable) NSString *modelPixelCount;
@property (nonatomic, copy, nullable) NSString *modelPixelSpacing;
@property (nonatomic, copy, nullable) NSString *modelPixelDescription;
@property (nonatomic, copy, nullable) NSString *modelNotes;
@property (nonatomic, copy, nullable) NSString *modelWebLink;
@property (nonatomic, strong, nullable) NSArray<NSString *> *modelImageURLs;

/// Wiring-level properties
@property (nonatomic, copy, nullable) NSString *wiringDescription;
@property (nonatomic, copy, nullable) NSString *xmodelURL;
@property (nonatomic, strong, nullable) NSArray<NSString *> *wiringImageURLs;

/// Whether this item has a downloadable xmodel link
@property (nonatomic, readonly) BOOL hasDownloadableModel;

@end

/// Native macOS window controller for browsing and downloading vendor models.
///
/// Replicates the legacy VendorModelDialog functionality using native AppKit:
/// - Fetches vendor list from GitHub-hosted XML catalog
/// - Parses vendor XML files with categories and model definitions
/// - Displays hierarchical vendor/category/model tree
/// - Shows model details, images, and vendor information
/// - Downloads .xmodel files and imports them into the layout
///
/// Data source: https://raw.githubusercontent.com/xLightsSequencer/xLights/master/download/xlights_vendors.xml
@interface XLVendorModelWindowController : NSWindowController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate>

/// Engine bridge for importing downloaded models
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Show folder path for storing downloaded models
@property (nonatomic, copy) NSString *showFolderPath;

/// Show the vendor model browser as a standalone window.
/// @param completion Called when a model is downloaded and ready to import
- (void)showWithCompletion:(XLVendorModelCompletion)completion;

/// Reload the vendor list from the remote catalog
- (void)reloadVendors;

@end
