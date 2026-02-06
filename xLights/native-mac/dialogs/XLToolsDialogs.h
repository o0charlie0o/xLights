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

@class XLEngineBridge;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Cleanup File Locations Dialog

/// Scans the show folder for missing or moved files referenced by sequences
/// and displays results in a table view.
@interface XLCleanupFileLocationsDialog : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

/// Engine bridge for accessing show data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Show the dialog
- (void)showWithCompletion:(void (^)(void))completion;

@end

#pragma mark - Package Sequence Dialog

/// Creates a zip archive containing the sequence file and all referenced media.
@interface XLPackageSequenceDialog : NSWindowController

/// Engine bridge for accessing sequence and media info
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Show the dialog
- (void)showWithCompletion:(void (^)(void))completion;

@end

#pragma mark - Download Sequences Dialog

/// Downloads sequences, lyrics, and other resources from the xLights repository.
@interface XLDownloadSequencesDialog : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSURLSessionDownloadDelegate>

/// Show the dialog
- (void)showWithCompletion:(void (^)(void))completion;

@end

#pragma mark - Prepare Audio Dialog

/// Processes audio files for use with xLights (normalize, convert format).
@interface XLPrepareAudioDialog : NSWindowController

/// Show the dialog
- (void)showWithCompletion:(void (^)(void))completion;

@end

#pragma mark - Generator Placeholder Dialog

/// Informational placeholder for generator features not yet available in the native build.
/// Used for: Generate 2D Path, Generate Custom Model, Remap Custom Model, Generate Lyrics.
@interface XLGeneratorPlaceholderDialog : XLBaseSheetController

/// Feature name for the dialog title
@property (nonatomic, copy) NSString *featureName;

/// Description of what the feature will do
@property (nonatomic, copy) NSString *featureDescription;

/// Expected capabilities when implemented
@property (nonatomic, copy, nullable) NSArray<NSString *> *plannedCapabilities;

@end

NS_ASSUME_NONNULL_END
