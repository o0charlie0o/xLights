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

#pragma mark - Checkbox Select Dialog

/// Native macOS sheet for multi-selection from a checklist.
/// Replaces wxCheckListBox-based dialogs.
@interface XLCheckboxSelectDialog : XLBaseSheetController

/// Items to display in the list
@property (nonatomic, copy) NSArray<NSString *> *items;

/// Currently selected items (by index)
@property (nonatomic, copy) NSIndexSet *selectedIndices;

/// Get selected items as strings
@property (nonatomic, copy, readonly) NSArray<NSString *> *selectedItems;

/// Prompt text above the list
@property (nonatomic, copy) NSString *promptText;

/// Whether to show Select All / Select None buttons (default: YES)
@property (nonatomic, assign) BOOL showSelectionButtons;

/// Initialize with items
- (instancetype)initWithItems:(NSArray<NSString *> *)items;

/// Initialize with items and pre-selected indices
- (instancetype)initWithItems:(NSArray<NSString *> *)items
             selectedIndices:(nullable NSIndexSet *)selectedIndices;

@end

#pragma mark - Alignment Dialog

/// Horizontal alignment options
typedef NS_ENUM(NSInteger, XLHorizontalAlignment) {
    XLHorizontalAlignmentLeft = 0,
    XLHorizontalAlignmentCenter,
    XLHorizontalAlignmentRight
};

/// Vertical alignment options
typedef NS_ENUM(NSInteger, XLVerticalAlignment) {
    XLVerticalAlignmentTop = 0,
    XLVerticalAlignmentMiddle,
    XLVerticalAlignmentBottom
};

/// Native macOS sheet for selecting alignment (3x3 grid).
@interface XLAlignmentDialog : XLBaseSheetController

/// Selected horizontal alignment
@property (nonatomic, assign) XLHorizontalAlignment horizontalAlignment;

/// Selected vertical alignment
@property (nonatomic, assign) XLVerticalAlignment verticalAlignment;

@end

#pragma mark - Duplicate Dialog

/// Native macOS sheet for duplicating effects/models.
@interface XLDuplicateDialog : XLBaseSheetController

/// Number of copies to create
@property (nonatomic, assign) NSInteger copyCount;

/// Gap between copies in milliseconds (for effects)
@property (nonatomic, assign) NSInteger gapMs;

/// Whether to retain original duration
@property (nonatomic, assign) BOOL retainDuration;

/// Maximum allowed copies
@property (nonatomic, assign) NSInteger maxCopies;

/// Whether gap field is visible (for non-timing operations)
@property (nonatomic, assign) BOOL showGapField;

@end

#pragma mark - Select Timings Dialog

/// Native macOS sheet for selecting timing tracks.
@interface XLSelectTimingsDialog : XLBaseSheetController

/// Available timing track names
@property (nonatomic, copy) NSArray<NSString *> *timingTracks;

/// Selected timing track indices
@property (nonatomic, copy) NSIndexSet *selectedIndices;

/// Get selected timing track names
@property (nonatomic, copy, readonly) NSArray<NSString *> *selectedTimings;

@end

#pragma mark - Viewpoint Dialog

/// Native macOS sheet for managing 3D viewpoints.
@interface XLViewpointDialog : XLBaseSheetController

/// Viewpoint name
@property (nonatomic, copy) NSString *viewpointName;

/// Camera position X
@property (nonatomic, assign) double positionX;

/// Camera position Y
@property (nonatomic, assign) double positionY;

/// Camera position Z
@property (nonatomic, assign) double positionZ;

/// Camera rotation X (pitch)
@property (nonatomic, assign) double rotationX;

/// Camera rotation Y (yaw)
@property (nonatomic, assign) double rotationY;

/// Camera rotation Z (roll)
@property (nonatomic, assign) double rotationZ;

/// Field of view angle
@property (nonatomic, assign) double fieldOfView;

/// Zoom level
@property (nonatomic, assign) double zoom;

/// Whether this is a new viewpoint (controls title)
@property (nonatomic, assign) BOOL isNewViewpoint;

@end

#pragma mark - Palette Management Dialog

/// Native macOS window for managing color palettes.
@interface XLPaletteManagementDialog : XLBaseSheetController

/// Available palette names
@property (nonatomic, copy) NSArray<NSString *> *paletteNames;

/// Completion handler called when a palette action is performed
/// Action: "load", "save", "delete", "copy"
/// paletteName: The affected palette name
@property (nonatomic, copy, nullable) void (^paletteActionHandler)(NSString *action, NSString *paletteName);

@end

#pragma mark - Note Range Dialog

/// Native macOS sheet for setting note/pitch ranges.
@interface XLNoteRangeDialog : XLBaseSheetController

/// Minimum note value (0-127 MIDI)
@property (nonatomic, assign) NSInteger minNote;

/// Maximum note value (0-127 MIDI)
@property (nonatomic, assign) NSInteger maxNote;

/// Whether to include note names in display
@property (nonatomic, assign) BOOL showNoteNames;

@end

#pragma mark - Custom Timing Dialog

/// Native macOS sheet for creating custom timing intervals.
@interface XLCustomTimingDialog : XLBaseSheetController

/// Timing interval in milliseconds
@property (nonatomic, assign) NSInteger intervalMs;

/// Timing name
@property (nonatomic, copy) NSString *timingName;

/// Whether to create as fixed timing
@property (nonatomic, assign) BOOL isFixedTiming;

@end

#pragma mark - Email Dialog

/// Native macOS sheet for email configuration.
@interface XLEmailDialog : XLBaseSheetController

/// Recipient email address
@property (nonatomic, copy) NSString *recipientEmail;

/// Email subject
@property (nonatomic, copy) NSString *subject;

/// Email body
@property (nonatomic, copy) NSString *body;

/// Whether to include attachment
@property (nonatomic, assign) BOOL includeAttachment;

/// Attachment path (if includeAttachment is YES)
@property (nonatomic, copy, nullable) NSString *attachmentPath;

@end

NS_ASSUME_NONNULL_END
