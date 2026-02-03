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
@class XLModelImportSheet;

/// Supported import file types
typedef NS_ENUM(NSInteger, XLModelImportType) {
    XLModelImportTypeXModel,       // .xmodel files (xLights native)
    XLModelImportTypeSequence,     // .xlights sequence files
    XLModelImportTypeLayout,       // Layout (.xlights layout)
    XLModelImportTypeLOR,          // Light-O-Rama
    XLModelImportTypeVixen,        // Vixen 3
    XLModelImportTypeUnknown,
};

/// Completion handler for model import sheet.
typedef void (^XLModelImportCompletion)(BOOL imported, NSArray<NSString *> *_Nullable importedModelNames);

/// Native macOS sheet for importing models from files.
///
/// Supports multiple import formats:
/// - .xmodel files (xLights native model format)
/// - .xlights sequence files (extract models)
/// - Layout files from other xLights installations
/// - Third-party formats (LOR, Vixen)
@interface XLModelImportSheet : NSObject

/// Engine bridge for importing models
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Show the import sheet as a file open panel attached to the parent window.
/// @param parentWindow The window to attach the sheet to
/// @param completion Called when import is complete
- (void)showAsSheetForWindow:(NSWindow *)parentWindow
                  completion:(XLModelImportCompletion)completion;

/// Import models directly from a file path (for drag-and-drop).
/// @param filePath Path to the file to import
/// @param completion Called when import is complete
- (void)importFromFile:(NSString *)filePath
            completion:(XLModelImportCompletion)completion;

/// Determine the import type from a file path
+ (XLModelImportType)importTypeForFile:(NSString *)filePath;

/// Get the file extension for an import type
+ (NSString *)fileExtensionForImportType:(XLModelImportType)importType;

@end

/// Model preview controller for import sheet.
/// Shows a preview of models to be imported with options to select/deselect.
@interface XLModelImportPreviewController : NSViewController

/// Models found in the file (array of dictionaries with model info)
@property (nonatomic, copy) NSArray<NSDictionary *> *availableModels;

/// Indices of models selected for import
@property (nonatomic, copy) NSIndexSet *selectedModelIndices;

/// Initialize with models from an import file
- (instancetype)initWithModels:(NSArray<NSDictionary *> *)models;

/// Get names of models selected for import
- (NSArray<NSString *> *)selectedModelNames;

@end
