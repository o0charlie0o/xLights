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

/// Native macOS sheet for entering lyrics for timing tracks.
///
/// Users can paste or type lyrics which will be parsed into timing marks.
@interface XLLyricsDialog : XLBaseSheetController

/// The lyrics text (one word/phrase per line)
@property (nonatomic, copy) NSString *lyricsText;

/// Start time in seconds
@property (nonatomic, assign) double startTime;

/// End time in seconds
@property (nonatomic, assign) double endTime;

/// Sequence duration in milliseconds (for validation)
@property (nonatomic, assign) NSInteger sequenceDurationMs;

@end

NS_ASSUME_NONNULL_END
