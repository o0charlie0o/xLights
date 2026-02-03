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

#pragma mark - Convert Dialog

/// Native macOS window for file format conversion.
@interface XLConvertDialog : NSWindowController

/// Engine bridge for accessing channel/output data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Show the conversion dialog as a window
- (void)showWithCompletion:(void (^)(void))completion;

@end

#pragma mark - Convert Log Dialog

/// Native macOS sheet for displaying conversion log.
@interface XLConvertLogDialog : XLBaseSheetController

/// Log text content
@property (nonatomic, copy) NSString *logText;

/// Whether conversion was successful
@property (nonatomic, assign) BOOL conversionSuccessful;

/// Number of errors encountered
@property (nonatomic, assign) NSInteger errorCount;

/// Number of warnings encountered
@property (nonatomic, assign) NSInteger warningCount;

/// Append text to the log
- (void)appendLog:(NSString *)text;

/// Append an error to the log
- (void)appendError:(NSString *)error;

/// Append a warning to the log
- (void)appendWarning:(NSString *)warning;

/// Clear the log
- (void)clearLog;

@end

#pragma mark - Channel Mapping Dialog

/// Native macOS window for mapping channels during import.
@interface XLChannelMappingDialog : NSWindowController

/// Source channel names
@property (nonatomic, copy) NSArray<NSString *> *sourceChannels;

/// Destination model names
@property (nonatomic, copy) NSArray<NSString *> *destinationModels;

/// Channel mapping dictionary (source index -> destination model name)
@property (nonatomic, copy, readonly) NSDictionary<NSNumber *, NSString *> *channelMapping;

/// Whether to map empty channels
@property (nonatomic, assign) BOOL mapEmptyChannels;

/// Show the mapping dialog
- (void)showWithCompletion:(void (^)(BOOL accepted))completion;

@end

#pragma mark - Import Previews Models Dialog

/// Native macOS sheet for importing previews and models from another show.
@interface XLImportPreviewsModelsDialog : XLBaseSheetController

/// Path to the source show directory
@property (nonatomic, copy) NSString *sourceShowPath;

/// Available previews to import
@property (nonatomic, copy) NSArray<NSString *> *availablePreviews;

/// Available models to import
@property (nonatomic, copy) NSArray<NSString *> *availableModels;

/// Selected preview indices
@property (nonatomic, copy) NSIndexSet *selectedPreviews;

/// Selected model indices
@property (nonatomic, copy) NSIndexSet *selectedModels;

/// Whether to include model groups
@property (nonatomic, assign) BOOL includeModelGroups;

/// Whether to include submodels
@property (nonatomic, assign) BOOL includeSubmodels;

@end

#pragma mark - SuperStar Import Dialog

/// Native macOS sheet for SuperStar sequence import options.
@interface XLSuperStarImportDialog : XLBaseSheetController

/// SuperStar file path
@property (nonatomic, copy) NSString *superStarFilePath;

/// Target model for import
@property (nonatomic, copy) NSString *targetModel;

/// Available models
@property (nonatomic, copy) NSArray<NSString *> *availableModels;

/// Timing track to use
@property (nonatomic, copy, nullable) NSString *timingTrack;

/// Image resize mode
@property (nonatomic, assign) NSInteger resizeMode;

/// Whether to flip horizontally
@property (nonatomic, assign) BOOL flipHorizontal;

/// Whether to flip vertically
@property (nonatomic, assign) BOOL flipVertical;

@end

#pragma mark - Vixen Import Dialog

/// Native macOS sheet for Vixen sequence import options.
@interface XLVixenImportDialog : XLBaseSheetController

/// Vixen file path
@property (nonatomic, copy) NSString *vixenFilePath;

/// Time resolution for import (in milliseconds)
@property (nonatomic, assign) NSInteger timeResolutionMs;

/// Available time resolutions
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *availableResolutions;

/// Whether to import controller mappings
@property (nonatomic, assign) BOOL importControllerMappings;

/// Channel mapping mode: 0 = none, 1 = show dialog, 2 = auto-map by name
@property (nonatomic, assign) NSInteger channelMappingMode;

@end

#pragma mark - LOR Import Dialog

/// Native macOS sheet for LOR (Light-O-Rama) import options.
@interface XLLORImportDialog : XLBaseSheetController

/// LOR file path
@property (nonatomic, copy) NSString *lorFilePath;

/// Time resolution for import (in centiseconds)
@property (nonatomic, assign) NSInteger timeResolutionCs;

/// Available time resolutions (in centiseconds)
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *availableResolutions;

/// Whether to map channels with no network
@property (nonatomic, assign) BOOL mapChannelsWithNoNetwork;

/// Channel mapping mode
@property (nonatomic, assign) NSInteger channelMappingMode;

@end

#pragma mark - HLS Import Dialog

/// Native macOS sheet for HLS (Hinkle's Light Sequencer) import.
@interface XLHLSImportDialog : XLBaseSheetController

/// HLS file path
@property (nonatomic, copy) NSString *hlsFilePath;

/// Whether to import timing tracks
@property (nonatomic, assign) BOOL importTimingTracks;

/// Whether to import universe/channel mappings
@property (nonatomic, assign) BOOL importMappings;

@end

#pragma mark - VSA Import Dialog

/// Native macOS sheet for VSA (Visual Show Automation) import.
@interface XLVSAImportDialog : XLBaseSheetController

/// VSA file path
@property (nonatomic, copy) NSString *vsaFilePath;

/// Servo mapping dictionary
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *servoMapping;

/// Available models
@property (nonatomic, copy) NSArray<NSString *> *availableModels;

@end

NS_ASSUME_NONNULL_END
