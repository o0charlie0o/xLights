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

/// Key bindings viewer window controller.
///
/// Displays all current keyboard shortcuts in a searchable, filterable table.
/// Shows Action, Shortcut Key, and Category columns. Read-only for now.
///
/// Populated from:
///   - Menu bar key equivalents (Cmd+S, Cmd+N, etc.)
///   - XLKeyboardHandler bindings loaded from key_bindings.xml
///   - Built-in sequencer/effects grid shortcuts
/// Posted when user saves changes in the key bindings editor.
extern NSNotificationName const XLKeyBindingsDidChangeNotification;

@interface XLKeyBindingsWindowController : NSWindowController <NSTableViewDelegate, NSTableViewDataSource, NSSearchFieldDelegate>

/// Shared singleton instance.
+ (instancetype)sharedController;

/// Show the key bindings window.
- (void)showWindow:(id)sender;

/// Reload bindings (e.g., after show folder changes).
- (void)reloadBindings;

/// Set the show folder path so bindings load/save from key_bindings.xml.
- (void)setShowFolderPath:(NSString *)showFolderPath;

@end
