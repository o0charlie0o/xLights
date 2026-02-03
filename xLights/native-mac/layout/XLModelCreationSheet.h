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
@class XLModelCreationSheet;

/// Model type definition for the type picker grid.
/// Uses C struct instead of NSObject to avoid heap corruption from wxWidgets.
typedef struct XLModelTypeDef {
    const char *typeId;          // e.g., "Single Line", "Matrix", "Custom"
    const char *displayName;     // Human-readable display name
    const char *iconName;        // SF Symbol name
    const char *description;     // Brief description
} XLModelTypeDef;

/// Completion handler for model creation sheet.
/// Returns YES if model was created, NO if cancelled.
typedef void (^XLModelCreationCompletion)(BOOL created, NSString *_Nullable modelName);

/// Native macOS sheet for creating new models.
///
/// Presents a two-phase workflow:
/// 1. Model type selection grid
/// 2. Type-specific configuration panel
///
/// The sheet slides from the title bar using NSWindow sheet presentation.
/// Uses C arrays for model type definitions to avoid heap corruption
/// from wxWidgets/Objective-C heap region conflicts.
@interface XLModelCreationSheet : NSObject

/// Engine bridge for creating models and querying data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Show the model creation sheet as a sheet attached to the parent window.
/// @param parentWindow The window to attach the sheet to
/// @param modelType Optional pre-selected model type (nil shows type picker)
/// @param completion Called when sheet is dismissed
- (void)showAsSheetForWindow:(NSWindow *)parentWindow
               withModelType:(NSString *_Nullable)modelType
                  completion:(XLModelCreationCompletion)completion;

/// Dismiss the sheet (for programmatic dismissal)
- (void)dismiss;

@end

/// Model configuration view controller base class.
///
/// Subclasses implement type-specific configuration panels.
@interface XLModelConfigViewController : NSViewController

/// The model type being configured
@property (nonatomic, copy, readonly) NSString *modelType;

/// The model name (user-editable)
@property (nonatomic, copy) NSString *modelName;

/// Initialize with model type
- (instancetype)initWithModelType:(NSString *)modelType;

/// Collect configuration properties into a dictionary for model creation.
/// Subclasses override to provide type-specific properties.
- (NSDictionary<NSString *, id> *)configurationProperties;

/// Validate the current configuration. Returns nil if valid,
/// or an error message if invalid.
- (NSString *_Nullable)validateConfiguration;

@end

/// Single Line model configuration
@interface XLSingleLineConfigViewController : XLModelConfigViewController
@end

/// Matrix model configuration
@interface XLMatrixConfigViewController : XLModelConfigViewController
@end

/// Arch model configuration
@interface XLArchConfigViewController : XLModelConfigViewController
@end

/// Tree model configuration
@interface XLTreeConfigViewController : XLModelConfigViewController
@end

/// Star model configuration
@interface XLStarConfigViewController : XLModelConfigViewController
@end

/// Circle model configuration
@interface XLCircleConfigViewController : XLModelConfigViewController
@end

/// Cube model configuration
@interface XLCubeConfigViewController : XLModelConfigViewController
@end

/// Sphere model configuration
@interface XLSphereConfigViewController : XLModelConfigViewController
@end

/// Custom model configuration (simplified - full designer in separate ticket)
@interface XLCustomConfigViewController : XLModelConfigViewController
@end

/// Generic model configuration for types without specialized UI
@interface XLGenericConfigViewController : XLModelConfigViewController
@end
