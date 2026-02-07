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
    XLModelImportTypeRGBEffects,   // xlights_rgbeffects.xml (import from another show folder)
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
/// - xlights_rgbeffects.xml (import from another show folder)
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

/// Show import specifically for RGB Effects files (xlights_rgbeffects.xml).
/// Presents a file chooser filtered for xlights_rgbeffects.xml, then shows
/// a tree-based selection UI with layout group organization.
/// @param parentWindow The window to attach the sheet to
/// @param completion Called when import is complete
- (void)showRGBEffectsImportForWindow:(NSWindow *)parentWindow
                           completion:(XLModelImportCompletion)completion;

/// Determine the import type from a file path
+ (XLModelImportType)importTypeForFile:(NSString *)filePath;

/// Get the file extension for an import type
+ (NSString *)fileExtensionForImportType:(XLModelImportType)importType;

@end

/// Tree-based selection controller for RGB Effects model import.
/// Organizes models by layout group, similar to legacy ImportPreviewsModelsDialog.
@interface XLRGBEffectsImportController : NSViewController

/// Parsed data from the RGB Effects file
@property (nonatomic, copy) NSDictionary *parsedData;

/// Initialize with parsed RGB Effects data
- (instancetype)initWithParsedData:(NSDictionary *)parsedData;

/// Get names of models/groups selected for import
- (NSArray<NSString *> *)selectedModelNames;

/// Get the target layout group for imported models (nil = keep original)
- (NSString *)targetLayoutGroup;

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
