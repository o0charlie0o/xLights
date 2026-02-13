#import <Cocoa/Cocoa.h>

@class XLDocumentController;

/// Notification posted when the show folder changes (permanent or temporary).
/// UserInfo keys: @"path" (NSString), @"permanent" (NSNumber/BOOL)
extern NSNotificationName const XLShowFolderDidChangeNotification;

/// Application delegate for xLights native macOS UI.
///
/// Responsibilities:
/// - Initialize custom document controller
/// - Handle app lifecycle events
/// - Manage preferences window
/// - Handle URL schemes and file associations
/// - Manage permanent/temporary show folder switching
@interface XLAppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, readonly) XLDocumentController *documentController;

/// The permanent show folder path (saved to defaults).
@property (nonatomic, readonly) NSString *permanentShowFolder;

/// Whether the current show folder is a temporary override.
@property (nonatomic, readonly) BOOL isTemporaryFolder;

/// Show the preferences window.
- (IBAction)showPreferences:(id)sender;

/// Open the recent show folder, if any.
- (IBAction)openRecentShow:(id)sender;

/// Create a new sequence.
- (IBAction)newSequence:(id)sender;

/// Open an existing sequence.
- (IBAction)openSequence:(id)sender;

/// Close the current sequence and return to empty state.
- (IBAction)closeSequence:(id)sender;

/// Add a path to the recent sequences list and update the menu.
- (void)addRecentSequence:(NSString *)path;

/// Prompt user to select a show folder (saves permanently).
- (IBAction)selectShowFolder:(id)sender;

/// Select a show folder temporarily (doesn't save to defaults).
- (IBAction)selectShowFolderTemporarily:(id)sender;

/// Restore the permanent show folder after a temporary switch.
- (void)restorePermanentShowFolder;

/// Load a show folder, optionally saving it as the permanent default.
- (void)loadShowFolderPath:(NSString *)path permanent:(BOOL)permanent;

/// Recent show folders list (most recent first, max 10).
@property (nonatomic, readonly) NSArray<NSString *> *recentShowFolders;

@end
