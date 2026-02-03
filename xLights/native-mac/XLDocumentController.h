#import <Cocoa/Cocoa.h>

/// Custom document controller for xLights.
///
/// Handles:
/// - Recent Files menu (via NSDocumentController)
/// - Custom Open dialog that supports both files and show folders
/// - Drag-and-drop of files onto app
/// - Default document type selection
@interface XLDocumentController : NSDocumentController

/// Open a show folder by URL.
/// This creates a new document representing the entire show folder.
- (void)openShowFolder:(NSURL *)url completionHandler:(void (^)(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error))completionHandler;

/// Present a custom open panel that allows selecting either:
/// - Individual sequence files (.xlights, .fseq)
/// - Show folders
- (void)presentOpenPanelWithCompletionHandler:(void (^)(NSArray<NSURL *> *urls))completionHandler;

@end
