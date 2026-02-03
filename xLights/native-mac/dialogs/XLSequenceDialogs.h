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

#pragma mark - New Sequence Dialog

/// Native macOS sheet for creating new sequences.
@interface XLNewSequenceDialog : XLBaseSheetController

/// Engine bridge for querying available models
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Sequence name (without extension)
@property (nonatomic, copy) NSString *sequenceName;

/// Sequence duration in seconds
@property (nonatomic, assign) NSInteger durationSeconds;

/// Frame interval in milliseconds (default: 50)
@property (nonatomic, assign) NSInteger frameIntervalMs;

/// Audio file path (optional)
@property (nonatomic, copy, nullable) NSString *audioFilePath;

/// Whether this is a musical sequence (has audio)
@property (nonatomic, assign, readonly) BOOL isMusicalSequence;

/// Show directory for the new sequence
@property (nonatomic, copy) NSString *showDirectory;

@end

#pragma mark - Sequence Settings Dialog

/// Native macOS sheet for editing sequence settings.
@interface XLSequenceSettingsDialog : XLBaseSheetController

/// Sequence name
@property (nonatomic, copy) NSString *sequenceName;

/// Author name
@property (nonatomic, copy, nullable) NSString *author;

/// Author email
@property (nonatomic, copy, nullable) NSString *authorEmail;

/// Author website
@property (nonatomic, copy, nullable) NSString *authorWebsite;

/// Song name
@property (nonatomic, copy, nullable) NSString *songName;

/// Artist name
@property (nonatomic, copy, nullable) NSString *artistName;

/// Album name
@property (nonatomic, copy, nullable) NSString *albumName;

/// Comments/notes
@property (nonatomic, copy, nullable) NSString *comments;

/// Sequence duration in milliseconds
@property (nonatomic, assign) NSInteger durationMs;

/// Frame interval in milliseconds
@property (nonatomic, assign) NSInteger frameIntervalMs;

@end

#pragma mark - Sequence Export Dialog

/// Native macOS sheet for sequence export options.
@interface XLSequenceExportDialog : XLBaseSheetController

/// Export format
@property (nonatomic, copy) NSString *exportFormat;

/// Available export formats
@property (nonatomic, copy) NSArray<NSString *> *availableFormats;

/// Export path
@property (nonatomic, copy, nullable) NSString *exportPath;

/// Whether to export selected models only
@property (nonatomic, assign) BOOL exportSelectedOnly;

/// Whether to include audio in export
@property (nonatomic, assign) BOOL includeAudio;

/// Start time for export (0 for beginning)
@property (nonatomic, assign) NSInteger startTimeMs;

/// End time for export (0 for end)
@property (nonatomic, assign) NSInteger endTimeMs;

@end

#pragma mark - Save Changes Dialog

/// Native macOS alert for unsaved changes.
@interface XLSaveChangesDialog : NSObject

/// Document name being saved
@property (nonatomic, copy) NSString *documentName;

/// Show the dialog and return the result.
/// Returns NSModalResponseOK (save), NSAlertSecondButtonReturn (don't save), or NSModalResponseCancel.
- (NSModalResponse)runModalForWindow:(NSWindow *)parentWindow;

@end

#pragma mark - Metronome Label Dialog

/// Dialog for metronome timing configuration.
@interface XLMetronomeLabelDialog : XLBaseSheetController

/// Beats per minute
@property (nonatomic, assign) double bpm;

/// Beats per measure
@property (nonatomic, assign) NSInteger beatsPerMeasure;

/// Start offset in milliseconds
@property (nonatomic, assign) NSInteger startOffsetMs;

/// Whether to add tags
@property (nonatomic, assign) BOOL addTags;

/// Tag labels (e.g., "Verse", "Chorus")
@property (nonatomic, copy, nullable) NSArray<NSString *> *tagLabels;

@end

NS_ASSUME_NONNULL_END
