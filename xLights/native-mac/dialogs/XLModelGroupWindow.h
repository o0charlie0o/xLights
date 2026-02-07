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

/// Completion handler for the model group management window.
typedef void (^XLModelGroupWindowCompletion)(BOOL changed);

/// Window controller for managing model groups.
///
/// Provides a two-pane interface for editing model group membership:
///   - Left: list of groups, with create/delete/rename buttons
///   - Right top: models in the selected group
///   - Right bottom: available models that can be added
///
/// Uses the existing XLEngineBridge group CRUD methods.
@interface XLModelGroupWindow : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>

/// Engine bridge for model and group operations
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Show the window and call completion when closed
- (void)showWithCompletion:(XLModelGroupWindowCompletion)completion;

/// Whether changes were made (triggers layout reload)
@property (nonatomic, readonly) BOOL hasChanges;

@end
