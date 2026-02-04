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

NS_ASSUME_NONNULL_BEGIN

/**
 * Preferences view controller for viewing and managing keyboard shortcuts.
 *
 * Displays all keyboard bindings in a table view with filtering by scope
 * and text search. Currently read-only with reset to defaults functionality.
 */
@interface XLKeyboardPreferencesViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>

/// Table view displaying all key bindings
@property (nonatomic, weak, nullable) IBOutlet NSTableView *bindingsTableView;

/// Segmented control for filtering by scope (All, Setup, Layout, Sequence)
@property (nonatomic, weak, nullable) IBOutlet NSSegmentedControl *scopeFilter;

/// Search field for filtering bindings by action name or shortcut
@property (nonatomic, weak, nullable) IBOutlet NSSearchField *searchField;

#pragma mark - Actions

/// Called when scope filter selection changes
- (IBAction)scopeFilterChanged:(nullable id)sender;

/// Called when search text changes
- (IBAction)searchTextChanged:(nullable id)sender;

/// Reset all key bindings to their default values
- (IBAction)resetToDefaults:(nullable id)sender;

#pragma mark - Public Methods

/// Reload bindings from the key bindings file
- (void)reloadBindings;

/// Get the current show folder path for loading bindings
@property (nonatomic, copy, nullable) NSString *showFolderPath;

@end

NS_ASSUME_NONNULL_END
