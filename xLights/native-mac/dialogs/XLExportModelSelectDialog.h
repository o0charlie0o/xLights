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

/// Native macOS sheet for selecting a model to export.
@interface XLExportModelSelectDialog : XLBaseSheetController

/// Engine bridge for querying models
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// The selected model name
@property (nonatomic, copy, readonly, nullable) NSString *selectedModel;

/// Custom label for the model selection (default: "Model to Export")
@property (nonatomic, copy) NSString *selectionLabel;

/// Whether to include model groups (default: NO)
@property (nonatomic, assign) BOOL includeGroups;

@end

NS_ASSUME_NONNULL_END
