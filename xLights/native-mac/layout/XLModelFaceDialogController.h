/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import <Cocoa/Cocoa.h>

@class XLEngineBridge;

/// Native macOS dialog for managing model face definitions.
///
/// Replicates the legacy ModelFaceDialog functionality:
/// - List of face definitions per model
/// - Phoneme-to-node-range mapping (Node Range type)
/// - Phoneme-to-image mapping (Matrix type)
/// - Add/remove/rename/copy face definitions
/// - Force custom colors option
///
/// Face types supported:
/// - Node Ranges: Maps phonemes to node number ranges (e.g., "1-5,10-15")
/// - Matrix: Maps phonemes to image files for matrix/tree displays
///
/// Standard phonemes: AI, E, etc, FV, L, MBP, O, rest, U, WQ
/// Additional rows: Face Outline, Eyes Open/Closed
@interface XLModelFaceDialogController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

/// Engine bridge for reading/writing face data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// The model name to edit faces for
@property (nonatomic, copy) NSString *modelName;

/// Show the face dialog as a modal sheet on the given window.
/// @param parentWindow The window to attach the sheet to
/// @param completion Called when the dialog is dismissed. YES if changes were saved.
- (void)showAsSheetOnWindow:(NSWindow *)parentWindow
                 completion:(void (^)(BOOL saved))completion;

/// Show the face dialog as a standalone window.
/// @param completion Called when the dialog is dismissed. YES if changes were saved.
- (void)showWithCompletion:(void (^)(BOOL saved))completion;

@end
