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

#pragma mark - Export Format Types

/// Supported export formats for sequence conversion
typedef NS_ENUM(NSInteger, XLExportFormat) {
    XLExportFormatFSEQ,         // Falcon Player (.fseq) - default v2
    XLExportFormatFSEQv1,       // Falcon Player v1 (.fseq)
    XLExportFormatFSEQv2,       // Falcon Player v2 (.fseq)
    XLExportFormatVideo,        // Video file (.mp4)
    XLExportFormatGIF,          // Animated GIF (.gif)
    XLExportFormatMinleon,      // Minleon NDB (.ndb)
    XLExportFormatLOR,          // Light-O-Rama (.lms)
    XLExportFormatVixen2,       // Vixen 2 (.vix)
    XLExportFormatHLS,          // HLS (.hlsseq)
    XLExportFormatEseq,         // Effect Sequence (.eseq)
};

#pragma mark - Import Format Types

/// Supported import formats for sequence conversion
typedef NS_ENUM(NSInteger, XLImportFormat) {
    XLImportFormatVixen2,       // Vixen 2.x (.vix)
    XLImportFormatVixen3,       // Vixen 3.x (.tim)
    XLImportFormatLOR,          // Light-O-Rama (.lms, .las, .lss)
    XLImportFormatHLS,          // HLS (.hlsseq)
    XLImportFormatLSP,          // Light Show Pro (.msq)
    XLImportFormatFSEQ,         // Falcon Player (.fseq)
    XLImportFormatSuperStar,    // SuperStar (.sup)
    XLImportFormatGlediator,    // Glediator (.led)
    XLImportFormatConductor,    // Conductor (.seq)
};

#pragma mark - Export Sequence Dialog

/// Native macOS sheet for exporting sequences to various formats.
@interface XLExportSequenceDialog : XLBaseSheetController <NSTableViewDataSource, NSTableViewDelegate>

/// Engine bridge for accessing models and sequence data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Show directory
@property (nonatomic, copy) NSString *showDirectory;

/// Selected export format
@property (nonatomic, assign) XLExportFormat exportFormat;

/// Export destination path
@property (nonatomic, copy, nullable) NSString *exportPath;

/// Whether to export all models or selected only
@property (nonatomic, assign) BOOL exportAllModels;

/// Selected model names for export (when not exporting all)
@property (nonatomic, copy) NSArray<NSString *> *selectedModelNames;

/// Export start time in milliseconds (0 = beginning)
@property (nonatomic, assign) NSInteger startTimeMs;

/// Export end time in milliseconds (0 = end)
@property (nonatomic, assign) NSInteger endTimeMs;

/// Include audio in video/GIF export
@property (nonatomic, assign) BOOL includeAudio;

/// Video width for video/GIF export
@property (nonatomic, assign) NSInteger videoWidth;

/// Video height for video/GIF export
@property (nonatomic, assign) NSInteger videoHeight;

/// Frame rate for video export
@property (nonatomic, assign) NSInteger frameRate;

/// GIF quality (1-100)
@property (nonatomic, assign) NSInteger gifQuality;

/// FSEQ compression level (0-9)
@property (nonatomic, assign) NSInteger fseqCompressionLevel;

/// Get file extension for export format
+ (NSString *)fileExtensionForFormat:(XLExportFormat)format;

/// Get display name for export format
+ (NSString *)displayNameForFormat:(XLExportFormat)format;

@end

#pragma mark - Batch Convert Dialog

/// Native macOS sheet for batch converting multiple sequence files.
@interface XLBatchConvertDialog : XLBaseSheetController <NSTableViewDataSource, NSTableViewDelegate>

/// Engine bridge for accessing show directory
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Show directory to scan for sequences
@property (nonatomic, copy) NSString *showDirectory;

/// Source format filter (import from)
@property (nonatomic, assign) XLImportFormat sourceFormat;

/// Destination format (export to)
@property (nonatomic, assign) XLExportFormat destinationFormat;

/// Selected source files for conversion
@property (nonatomic, copy, readonly) NSArray<NSString *> *selectedSourceFiles;

/// Output directory for converted files
@property (nonatomic, copy, nullable) NSString *outputDirectory;

/// Whether to overwrite existing files
@property (nonatomic, assign) BOOL overwriteExisting;

/// Whether to preserve folder structure
@property (nonatomic, assign) BOOL preserveFolderStructure;

@end

#pragma mark - Conversion Progress Dialog

/// Non-modal dialog showing conversion progress for single or batch operations.
@interface XLConversionProgressDialog : NSObject

/// The progress window
@property (nonatomic, strong, readonly) NSWindow *window;

/// Overall progress (0.0 - 1.0)
@property (nonatomic, assign, readonly) double overallProgress;

/// Whether all conversions are complete
@property (nonatomic, assign, readonly) BOOL isComplete;

/// Whether the conversion was cancelled
@property (nonatomic, assign, readonly) BOOL wasCancelled;

/// Callback for when cancel is clicked
@property (nonatomic, copy, nullable) void (^onCancel)(void);

/// Show the progress dialog
- (void)showForWindow:(NSWindow *)parentWindow;

/// Close the dialog
- (void)close;

/// Set the current file being processed
- (void)setCurrentFile:(NSString *)filename;

/// Set the current status message
- (void)setStatusMessage:(NSString *)message;

/// Update progress for the current file (0.0 - 1.0)
- (void)setFileProgress:(double)progress;

/// Update overall progress (0.0 - 1.0)
- (void)setOverallProgress:(double)progress;

/// Mark conversion as complete with success/error message
- (void)markCompleteWithMessage:(nullable NSString *)message success:(BOOL)success;

/// Add a log entry
- (void)addLogEntry:(NSString *)entry;

/// Add an error entry (displayed in red)
- (void)addErrorEntry:(NSString *)error;

/// Add a warning entry (displayed in orange)
- (void)addWarningEntry:(NSString *)warning;

@end

#pragma mark - Import Sequence Dialog Helper

/// Helper class with format conversion utilities
@interface XLImportSequenceDialog : NSObject

/// Get file extension for import format
+ (NSString *)fileExtensionForFormat:(XLImportFormat)format;

/// Get display name for import format
+ (NSString *)displayNameForFormat:(XLImportFormat)format;

/// Get import format from file extension
+ (XLImportFormat)formatFromFileExtension:(NSString *)extension;

@end

NS_ASSUME_NONNULL_END
