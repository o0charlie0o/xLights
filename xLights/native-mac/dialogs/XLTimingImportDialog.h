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

/// Available timing sources
typedef NS_ENUM(NSInteger, XLTimingSource) {
    XLTimingSourceLyrics,           // Lyrics file (.lrc, .txt)
    XLTimingSourceAudioAnalysis,    // Audio beat detection
    XLTimingSourceVAMP,             // VAMP plugin
    XLTimingSourcePapagayo,         // Papagayo phoneme file
    XLTimingSourceMIDI,             // MIDI file
    XLTimingSourceOtherSequence,    // Another xLights sequence
};

/// Native macOS sheet for importing timing tracks.
@interface XLTimingImportDialog : XLBaseSheetController

/// The selected timing source
@property (nonatomic, assign) XLTimingSource source;

/// The file path for file-based sources
@property (nonatomic, copy, nullable) NSString *sourceFilePath;

/// The track name for the imported timing
@property (nonatomic, copy) NSString *trackName;

/// Whether to replace existing timing track (default: NO, appends)
@property (nonatomic, assign) BOOL replaceExisting;

/// For audio analysis: beat sensitivity (0.0-1.0)
@property (nonatomic, assign) double beatSensitivity;

/// For VAMP: plugin name
@property (nonatomic, copy, nullable) NSString *vampPlugin;

/// Available VAMP plugins
@property (nonatomic, copy) NSArray<NSString *> *availableVAMPPlugins;

@end

NS_ASSUME_NONNULL_END
