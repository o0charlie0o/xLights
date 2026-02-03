/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLBaseSheetController.h"

NS_ASSUME_NONNULL_BEGIN

@class XLEngineBridge;

/// Start channel mode for the dialog
typedef NS_ENUM(NSInteger, XLStartChannelMode) {
    XLStartChannelModeAbsolute,      // Plain number
    XLStartChannelModeUniverse,      // #IP:Universe:Channel or #Universe:Channel
    XLStartChannelModeEndOfModel,    // >ModelName:Channel
    XLStartChannelModeStartOfModel,  // @ModelName:Channel
    XLStartChannelModeController,    // !ControllerName:Channel
};

/// Native macOS sheet for configuring model start channels.
///
/// Supports multiple addressing modes:
/// - Absolute: Direct channel number
/// - Universe: E1.31/ArtNet universe-based addressing
/// - End of Model: Chain after another model
/// - Start of Model: Reference another model's start
/// - Controller: Offset from controller
@interface XLStartChannelDialog : XLBaseSheetController

/// Engine bridge for querying models, controllers, and outputs
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// The start channel string in xLights format
@property (nonatomic, copy) NSString *startChannel;

/// Currently selected mode
@property (nonatomic, assign, readonly) XLStartChannelMode mode;

/// The channel offset value
@property (nonatomic, assign, readonly) NSInteger channelOffset;

/// Selected model name (for model reference modes)
@property (nonatomic, copy, readonly, nullable) NSString *selectedModel;

/// Selected controller name (for controller mode)
@property (nonatomic, copy, readonly, nullable) NSString *selectedController;

/// Selected universe (for universe mode)
@property (nonatomic, assign, readonly) NSInteger selectedUniverse;

/// Selected IP (for universe mode)
@property (nonatomic, copy, readonly, nullable) NSString *selectedIP;

/// The preview name to filter models (optional)
@property (nonatomic, copy, nullable) NSString *currentPreview;

/// The model being edited (to exclude from model list)
@property (nonatomic, copy, nullable) NSString *editingModelName;

/// Parse a start channel string and configure the dialog.
- (void)parseStartChannel:(NSString *)startChannel;

/// Generate the start channel string from current selections.
- (NSString *)generateStartChannelString;

@end

NS_ASSUME_NONNULL_END
