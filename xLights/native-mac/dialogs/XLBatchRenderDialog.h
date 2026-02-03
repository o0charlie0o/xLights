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

/// Native macOS sheet for batch rendering sequences.
@interface XLBatchRenderDialog : XLBaseSheetController

/// Engine bridge for accessing show directory
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// The show directory to search for sequences
@property (nonatomic, copy) NSString *showDirectory;

/// Array of selected sequence file names
@property (nonatomic, copy, readonly) NSArray<NSString *> *selectedSequences;

/// Whether to force high definition rendering
@property (nonatomic, assign) BOOL forceHighDefinition;

@end

NS_ASSUME_NONNULL_END
