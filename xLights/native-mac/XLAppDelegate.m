#import "XLAppDelegate.h"
#import "XLDocumentController.h"

@interface XLAppDelegate ()

@property (nonatomic, strong) XLDocumentController *documentController;
@property (nonatomic, strong) NSWindowController *preferencesWindowController;

@end

@implementation XLAppDelegate

#pragma mark - NSApplicationDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    // Initialize custom document controller
    // This must happen in willFinishLaunching, before NSDocumentController
    // auto-initializes
    _documentController = [[XLDocumentController alloc] init];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Additional setup after launch

    // Check for last open show folder in user defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *lastShowFolder = [defaults stringForKey:@"LastShowFolder"];

    if (lastShowFolder) {
        NSURL *url = [NSURL fileURLWithPath:lastShowFolder];
        if ([[NSFileManager defaultManager] fileExistsAtPath:lastShowFolder]) {
            // Optionally restore last show folder
            // (Commented out to avoid auto-opening on launch)
            // [self openShowFolderAtURL:url];
        }
    }
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
    // Don't open an untitled document on launch
    // xLights requires opening an existing show folder or sequence
    return NO;
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender {
    // Show open panel instead of creating new untitled document
    [_documentController presentOpenPanelWithCompletionHandler:^(NSArray<NSURL *> *urls) {
        if (urls.count > 0) {
            [self->_documentController openDocumentWithContentsOfURL:urls.firstObject
                                                             display:YES
                                                   completionHandler:nil];
        }
    }];
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    // Save last show folder to user defaults
    // This will be set by XLDocument when opening show folders
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    // Keep app running even when last window is closed
    // (Common on macOS for document-based apps)
    return NO;
}

#pragma mark - Actions

- (IBAction)showPreferences:(id)sender {
    if (!_preferencesWindowController) {
        // TODO: Create preferences window controller (Phase 1D)
        // For now, show a placeholder alert
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Preferences";
        alert.informativeText = @"Preferences window not yet implemented.\n\nThis will be added in Phase 1D.";
        alert.alertStyle = NSAlertStyleInformational;
        [alert runModal];
        return;
    }

    [_preferencesWindowController showWindow:sender];
}

- (IBAction)openRecentShow:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *lastShowFolder = [defaults stringForKey:@"LastShowFolder"];

    if (lastShowFolder) {
        NSURL *url = [NSURL fileURLWithPath:lastShowFolder];
        [self openShowFolderAtURL:url];
    } else {
        // No recent show, prompt to open one
        [_documentController presentOpenPanelWithCompletionHandler:^(NSArray<NSURL *> *urls) {
            if (urls.count > 0) {
                [self openShowFolderAtURL:urls.firstObject];
            }
        }];
    }
}

#pragma mark - Private Helpers

- (void)openShowFolderAtURL:(NSURL *)url {
    [_documentController openDocumentWithContentsOfURL:url
                                              display:YES
                                    completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error) {
        if (error) {
            [NSApp presentError:error];
        } else if (document) {
            // Save as last show folder
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:url.path forKey:@"LastShowFolder"];
        }
    }];
}

@end
