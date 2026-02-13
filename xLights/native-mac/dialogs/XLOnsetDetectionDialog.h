/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

#import "XLBaseSheetController.h"

@class XLStemData;
@class XLOnsetResult;
@class XLOnsetDetectionDialog;

NS_ASSUME_NONNULL_BEGIN

/// Preset configurations for different instrument types.
typedef NS_ENUM(NSInteger, XLOnsetPreset) {
    XLOnsetPresetKick = 0,
    XLOnsetPresetSnare,
    XLOnsetPresetHiHat,
    XLOnsetPresetToms,
    XLOnsetPresetFullRange,
    XLOnsetPresetCustom,
};

/// Delegate for receiving onset preview updates and dismissal.
@protocol XLOnsetDetectionDialogDelegate <NSObject>
- (void)onsetDetectionDialog:(XLOnsetDetectionDialog *)dialog
       didUpdatePreviewOnsets:(NSArray<NSNumber *> *)onsetTimesMS
                forStemIndex:(NSUInteger)stemIndex;
- (void)onsetDetectionDialogDidDismiss:(XLOnsetDetectionDialog *)dialog;
@end

/// Sheet dialog for configuring and previewing onset detection on a stem.
@interface XLOnsetDetectionDialog : XLBaseSheetController

/// The stem to analyze.
@property (nonatomic, strong) XLStemData *stemData;

/// Index of the stem in the stems container (for delegate callbacks).
@property (nonatomic, assign) NSUInteger stemIndex;

/// Existing timing track names (for duplicate validation).
@property (nonatomic, copy, nullable) NSArray<NSString *> *existingTrackNames;

/// Delegate for preview updates.
@property (nonatomic, weak, nullable) id<XLOnsetDetectionDialogDelegate> onsetDelegate;

/// The chosen track name (valid after OK response).
@property (nonatomic, copy, readonly) NSString *trackName;

/// The detected onset times in milliseconds (valid after OK response).
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *detectedOnsets;

@end

NS_ASSUME_NONNULL_END
