#import "XLAppDelegate.h"
#import "XLDocumentController.h"
#import "XLToolbarExtensions.h"
#import "preferences/XLPreferencesWindowController.h"
#import "dialogs/XLSequenceDialogs.h"
#import "XLMainWindowController.h"
#import "XLEngineBridge.h"
#import "XLSequencerViewController.h"

// Import Swift generated header for XLSwiftUIWindowHelper
// The header name depends on the target product name
#if __has_include("xLights_Native-Swift.h")
#import "xLights_Native-Swift.h"
#elif __has_include("xLights-Swift.h")
#import "xLights-Swift.h"
#endif

@interface XLAppDelegate ()

@property (nonatomic, strong) XLDocumentController *documentController;
@property (nonatomic, strong) XLMainWindowController *mainWindowController;

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
    // Build the full menu bar
    [XLMenuBuilder buildMenuBarForApplication:[NSApplication sharedApplication] target:self];

    // Create and show the main window
    _mainWindowController = [[XLMainWindowController alloc] init];
    [_mainWindowController.window setTitle:@"xLights"];

    // Set the frame explicitly before showing to avoid Auto Layout fighting
    NSRect defaultFrame = NSMakeRect(100, 100, 1600, 1000);
    [_mainWindowController.window setFrame:defaultFrame display:NO];

    [_mainWindowController showWindow:self];
    [_mainWindowController.window makeKeyAndOrderFront:self];

    // Activate the app to bring it to the foreground
    [NSApp activateIgnoringOtherApps:YES];

    // Force the frame again after layout to override Auto Layout sizing
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_mainWindowController.window setFrame:defaultFrame display:YES animate:NO];
        [self->_mainWindowController.window center];
        NSLog(@"XLAppDelegate: Forced window frame to %@", NSStringFromRect(defaultFrame));
    });

    NSLog(@"XLAppDelegate: Main window created and shown");

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
    [[XLPreferencesWindowController sharedController] showWindow:sender];
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

#pragma mark - Sequence Actions

- (IBAction)newSequence:(id)sender {
    NSWindow *keyWindow = [NSApp keyWindow];
    XLEngineBridge *engineBridge = nil;
    BOOL isSwiftUIWindow = NO;

    NSLog(@"XLAppDelegate: newSequence called, keyWindow=%@, title=%@",
          keyWindow, keyWindow.title);

    // Check if SwiftUI window is key using helper class
    XLSwiftUIWindowHelper *swiftHelper = [XLSwiftUIWindowHelper shared];
    BOOL swiftUIIsKey = swiftHelper.isSwiftUIWindowKey;
    NSLog(@"XLAppDelegate: isSwiftUIWindowKey returned %d", swiftUIIsKey);

    if (swiftUIIsKey) {
        engineBridge = swiftHelper.engineBridge;
        isSwiftUIWindow = YES;
        NSLog(@"XLAppDelegate: newSequence - using SwiftUI window, engineBridge=%@", engineBridge);
    } else {
        // Check for XLMainWindowController (ObjC window)
        NSWindowController *windowController = keyWindow.windowController;
        NSLog(@"XLAppDelegate: windowController class = %@", NSStringFromClass([windowController class]));
        if ([windowController isKindOfClass:[XLMainWindowController class]]) {
            XLMainWindowController *mainController = (XLMainWindowController *)windowController;
            engineBridge = mainController.engineBridge;
            NSLog(@"XLAppDelegate: newSequence - using ObjC window");
        }
    }

    // Fall back to the main window controller if no key window found
    if (!engineBridge && _mainWindowController) {
        engineBridge = _mainWindowController.engineBridge;
        keyWindow = _mainWindowController.window;
        NSLog(@"XLAppDelegate: newSequence - using main window controller fallback");
    }

    if (!engineBridge) {
        NSLog(@"XLAppDelegate: newSequence - no engine bridge available");
        return;
    }

    // Get show directory from user defaults
    NSString *showDirectory = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    if (!showDirectory) {
        showDirectory = NSHomeDirectory();
    }

    // Create and configure the new sequence dialog
    XLNewSequenceDialog *dialog = [[XLNewSequenceDialog alloc] init];
    dialog.engineBridge = engineBridge;
    dialog.showDirectory = showDirectory;
    dialog.sequenceName = @"New Sequence";
    dialog.durationSeconds = 60;
    dialog.frameIntervalMs = 50;

    // Show the dialog as a sheet
    [dialog presentAsSheetForWindow:keyWindow completion:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            // Convert duration to milliseconds
            NSInteger durationMS = dialog.durationSeconds * 1000;
            NSInteger frameMS = dialog.frameIntervalMs;
            NSString *audioFile = dialog.audioFilePath;

            // Create the sequence via engine bridge
            BOOL success = [engineBridge createSequence:durationMS
                                                frameMS:frameMS
                                              mediaFile:audioFile];

            if (success) {
                NSLog(@"XLAppDelegate: Created new sequence - duration: %ld sec, frame: %ld ms, audio: %@",
                      (long)dialog.durationSeconds, (long)frameMS, audioFile ?: @"(none)");

                if (isSwiftUIWindow) {
                    // Notify SwiftUI window to reload
                    [[XLSwiftUIWindowHelper shared] notifySequenceDataChanged];
                } else {
                    // Reload the ObjC sequencer view
                    NSWindowController *wc = keyWindow.windowController;
                    if ([wc isKindOfClass:[XLMainWindowController class]]) {
                        XLMainWindowController *mainController = (XLMainWindowController *)wc;
                        [mainController.sequencerViewController reloadSequenceData];
                        [mainController switchToTab:2];
                    }
                }
            } else {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Failed to Create Sequence";
                alert.informativeText = @"Unable to create a new sequence. Please check the log for details.";
                alert.alertStyle = NSAlertStyleWarning;
                [alert runModal];
            }
        }
    }];
}

- (IBAction)openSequence:(id)sender {
    // Use the document controller to present an open panel
    [_documentController presentOpenPanelWithCompletionHandler:^(NSArray<NSURL *> *urls) {
        if (urls.count > 0) {
            [self->_documentController openDocumentWithContentsOfURL:urls.firstObject
                                                             display:YES
                                                   completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error) {
                if (error) {
                    [NSApp presentError:error];
                }
            }];
        }
    }];
}

@end
