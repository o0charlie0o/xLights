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

/// Timing interval options
typedef NS_ENUM(NSInteger, XLTimingInterval) {
    XLTimingIntervalEmpty,
    XLTimingInterval25ms,
    XLTimingInterval50ms,
    XLTimingInterval100ms,
    XLTimingIntervalMetronome,
    XLTimingIntervalMetronomeWithTags,
    XLTimingIntervalFPPCommands,
    XLTimingIntervalFPPEffects,
};

/// Native macOS sheet for creating new timing tracks.
@interface XLNewTimingDialog : XLBaseSheetController

/// The track name entered by the user
@property (nonatomic, copy) NSString *trackName;

/// The selected timing interval
@property (nonatomic, assign) XLTimingInterval selectedInterval;

/// Array of intervals to exclude from the choices
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *excludedIntervals;

/// Existing track names (to prevent duplicates)
@property (nonatomic, copy, nullable) NSArray<NSString *> *existingTrackNames;

/// Get the display name for a timing interval
+ (NSString *)displayNameForInterval:(XLTimingInterval)interval;

/// Get the timing name (for creating the track) for an interval
+ (nullable NSString *)timingNameForInterval:(XLTimingInterval)interval;

@end

NS_ASSUME_NONNULL_END
