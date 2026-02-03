#import <Cocoa/Cocoa.h>

@class XLDocumentController;

/// Application delegate for xLights native macOS UI.
///
/// Responsibilities:
/// - Initialize custom document controller
/// - Handle app lifecycle events
/// - Manage preferences window
/// - Handle URL schemes and file associations
@interface XLAppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, readonly) XLDocumentController *documentController;

/// Show the preferences window.
- (IBAction)showPreferences:(id)sender;

/// Open the recent show folder, if any.
- (IBAction)openRecentShow:(id)sender;

@end
