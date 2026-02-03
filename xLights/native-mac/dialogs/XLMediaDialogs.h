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

#pragma mark - Media Import Options Dialog

/// Native macOS sheet for media import options.
@interface XLMediaImportOptionsDialog : XLBaseSheetController

/// Whether to create timing marks from audio analysis
@property (nonatomic, assign) BOOL createTimingMarks;

/// Whether to set the media file as background video
@property (nonatomic, assign) BOOL useAsBackgroundVideo;

/// Video scaling mode (fit, fill, stretch)
@property (nonatomic, copy) NSString *videoScaleMode;

/// Audio volume (0.0 - 1.0)
@property (nonatomic, assign) double audioVolume;

/// Whether to loop the media
@property (nonatomic, assign) BOOL loopMedia;

@end

#pragma mark - Resize Image Dialog

/// Native macOS sheet for image resize options.
@interface XLResizeImageDialog : XLBaseSheetController

/// Original width
@property (nonatomic, assign, readonly) NSInteger originalWidth;

/// Original height
@property (nonatomic, assign, readonly) NSInteger originalHeight;

/// New width
@property (nonatomic, assign) NSInteger newWidth;

/// New height
@property (nonatomic, assign) NSInteger newHeight;

/// Whether to maintain aspect ratio
@property (nonatomic, assign) BOOL maintainAspectRatio;

/// Set the original image dimensions
- (void)setOriginalWidth:(NSInteger)width height:(NSInteger)height;

@end

#pragma mark - Buffer Size Dialog

/// Native macOS sheet for changing buffer size.
@interface XLBufferSizeDialog : XLBaseSheetController

/// Buffer width
@property (nonatomic, assign) NSInteger bufferWidth;

/// Buffer height
@property (nonatomic, assign) NSInteger bufferHeight;

/// Maximum allowed size
@property (nonatomic, assign) NSInteger maxSize;

@end

#pragma mark - Layer Select Dialog

/// Native macOS sheet for selecting layers.
@interface XLLayerSelectDialog : XLBaseSheetController

/// Number of available layers
@property (nonatomic, assign) NSInteger layerCount;

/// Selected layer indices
@property (nonatomic, copy) NSIndexSet *selectedLayers;

/// Whether to allow multiple selection (default: YES)
@property (nonatomic, assign) BOOL allowsMultipleSelection;

/// Prompt text
@property (nonatomic, copy) NSString *promptText;

@end

#pragma mark - Rename Dialog

/// Simple rename dialog for effects, models, etc.
@interface XLRenameDialog : XLBaseSheetController

/// The current name
@property (nonatomic, copy) NSString *currentName;

/// The new name (after OK)
@property (nonatomic, copy, readonly) NSString *newName;

/// Prompt text (e.g., "Effect Name:", "Model Name:")
@property (nonatomic, copy) NSString *promptText;

/// Names that are not allowed (for uniqueness check)
@property (nonatomic, copy, nullable) NSArray<NSString *> *disallowedNames;

/// Characters not allowed in the name
@property (nonatomic, copy, nullable) NSCharacterSet *disallowedCharacters;

@end

NS_ASSUME_NONNULL_END
