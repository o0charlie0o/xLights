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

/// Native macOS sheet for editing effect timing.
@interface XLEffectTimingDialog : XLBaseSheetController

/// Start time in milliseconds
@property (nonatomic, assign) NSInteger startTimeMs;

/// End time in milliseconds
@property (nonatomic, assign) NSInteger endTimeMs;

/// Sequence duration in milliseconds (for validation)
@property (nonatomic, assign) NSInteger sequenceDurationMs;

/// Frame interval in milliseconds (for snapping)
@property (nonatomic, assign) NSInteger frameIntervalMs;

/// Effect name (for display)
@property (nonatomic, copy, nullable) NSString *effectName;

@end

NS_ASSUME_NONNULL_END
