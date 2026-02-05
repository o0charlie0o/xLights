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

// SwiftUI window launcher (defined in XLSwiftWindowLauncher.swift)
extern int XLLaunchSwiftUIWindow(void);

// Shared flag for command palette visibility, set from Swift via notification
static BOOL sCommandPaletteVisible = NO;

void XLSetCommandPaletteVisible(bool visible) {
    sCommandPaletteVisible = visible;
}

@interface XLAppDelegate ()

@property (nonatomic, strong) XLDocumentController *documentController;

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

    // Launch the SwiftUI-based main window
    // This window handles Auto Layout correctly and supports resize
    XLLaunchSwiftUIWindow();

    // Install local event monitor for Command Palette
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        BOOL isCmd = (flags & NSEventModifierFlagCommand) != 0;
        BOOL isShift = (flags & NSEventModifierFlagShift) != 0;
        NSString *chars = event.charactersIgnoringModifiers;

        // Cmd+Shift+K toggles the command palette
        if (isCmd && isShift && [chars caseInsensitiveCompare:@"k"] == NSOrderedSame) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"XLToggleCommandPalette"
                                                                object:nil];
            return nil;
        }

        // When command palette is visible, intercept all keys
        if (sCommandPaletteVisible) {
            NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
            NSLog(@"CommandPalette monitor: keyCode=%hu chars='%@' isCmd=%d isShift=%d",
                  event.keyCode, event.characters, isCmd, isShift);

            if (event.keyCode == 53) {
                // Escape
                [nc postNotificationName:@"XLDismissCommandPalette" object:nil];
            } else if (event.keyCode == 126) {
                // Up arrow
                [nc postNotificationName:@"XLCommandPaletteInput"
                                  object:nil
                                userInfo:@{@"action": @"up"}];
            } else if (event.keyCode == 125) {
                // Down arrow
                [nc postNotificationName:@"XLCommandPaletteInput"
                                  object:nil
                                userInfo:@{@"action": @"down"}];
            } else if (event.keyCode == 36 || event.keyCode == 76) {
                // Return / Enter
                [nc postNotificationName:@"XLCommandPaletteInput"
                                  object:nil
                                userInfo:@{@"action": @"execute"}];
            } else if (event.keyCode == 51) {
                // Backspace
                [nc postNotificationName:@"XLCommandPaletteInput"
                                  object:nil
                                userInfo:@{@"action": @"backspace"}];
            } else if (isCmd && [chars caseInsensitiveCompare:@"a"] == NSOrderedSame) {
                // Cmd+A: select all / clear text
                [nc postNotificationName:@"XLCommandPaletteInput"
                                  object:nil
                                userInfo:@{@"action": @"clearAll"}];
            } else if (!isCmd) {
                // Regular character input
                NSString *typed = event.characters;
                if (typed.length > 0) {
                    [nc postNotificationName:@"XLCommandPaletteInput"
                                      object:nil
                                    userInfo:@{@"action": @"type", @"text": typed}];
                }
            }
            // Consume ALL events when palette is open (nothing passes to AppKit views)
            return nil;
        }

        return event;
    }];

    // Activate the app to bring it to the foreground
    [NSApp activateIgnoringOtherApps:YES];

    NSLog(@"XLAppDelegate: SwiftUI window launched");

    // Check for last open show folder in user defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *lastShowFolder = [defaults stringForKey:@"LastShowFolder"];

    if (lastShowFolder && [[NSFileManager defaultManager] fileExistsAtPath:lastShowFolder isDirectory:NULL]) {
        // Restore last show folder
        [self loadShowFolderPath:lastShowFolder];
    } else {
        // No saved show folder - prompt user to select one
        [self promptForShowFolder];
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

- (void)loadShowFolderPath:(NSString *)path {
    NSLog(@"XLAppDelegate: Loading show folder: %@", path);

    // Load the show folder into the engine bridge
    XLSwiftUIWindowHelper *swiftHelper = [XLSwiftUIWindowHelper shared];
    XLEngineBridge *engineBridge = swiftHelper.engineBridge;

    if (engineBridge) {
        BOOL success = [engineBridge loadShowFolder:path];
        if (success) {
            NSLog(@"XLAppDelegate: Show folder loaded successfully");
            // Save as last show folder
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:path forKey:@"LastShowFolder"];
            // Notify SwiftUI to refresh
            [swiftHelper notifySequenceDataChanged];
            // Notify observers that the show folder changed (for key bindings, etc.)
            [[NSNotificationCenter defaultCenter] postNotificationName:@"XLShowFolderDidChangeNotification"
                                                                object:self
                                                              userInfo:@{@"path": path}];
        } else {
            NSLog(@"XLAppDelegate: Failed to load show folder");
            // Prompt for a different folder
            [self promptForShowFolder];
        }
    } else {
        NSLog(@"XLAppDelegate: Engine bridge not available, deferring show folder load");
        // Store path and try again after a short delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self loadShowFolderPath:path];
        });
    }
}

- (void)promptForShowFolder {
    NSLog(@"XLAppDelegate: Prompting user to select show folder");

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Select your xLights show folder";
    panel.prompt = @"Select Show Folder";

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            [self loadShowFolderPath:panel.URL.path];
        } else {
            // User cancelled - show an alert explaining the requirement
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Show Folder Required";
            alert.informativeText = @"xLights requires a show folder to function properly. Many features will be unavailable until you select a show folder.\n\nYou can select a show folder later from File > Open Show Folder.";
            alert.alertStyle = NSAlertStyleInformational;
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        }
    }];
}

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

    // Fall back to SwiftUI window helper if no key window found
    if (!engineBridge) {
        XLSwiftUIWindowHelper *swiftHelper = [XLSwiftUIWindowHelper shared];
        engineBridge = swiftHelper.engineBridge;
        if (engineBridge) {
            // Get the key window again - it should be the SwiftUI window
            keyWindow = [NSApp keyWindow];
            isSwiftUIWindow = YES;
            NSLog(@"XLAppDelegate: newSequence - using SwiftUI window helper fallback");
        }
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
    NSLog(@"XLAppDelegate: openSequence called");

    // Get the engine bridge from SwiftUI window
    XLSwiftUIWindowHelper *swiftHelper = [XLSwiftUIWindowHelper shared];
    XLEngineBridge *engineBridge = swiftHelper.engineBridge;

    if (!engineBridge) {
        NSLog(@"XLAppDelegate: Engine bridge not available for opening sequence");
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Cannot Open Sequence";
        alert.informativeText = @"The engine is not initialized. Please select a show folder first.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    // Show open panel for sequence files
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Open Sequence";
    panel.message = @"Select a sequence file to open";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedFileTypes = @[@"xlights", @"xsq", @"xml"];

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            NSString *sequencePath = panel.URL.path;
            NSLog(@"XLAppDelegate: Opening sequence: %@", sequencePath);

            // Load the sequence through the engine bridge
            BOOL success = [engineBridge loadSequence:sequencePath];

            if (success) {
                NSLog(@"XLAppDelegate: Sequence loaded successfully");
                // Notify SwiftUI to refresh
                [swiftHelper notifySequenceDataChanged];
            } else {
                NSLog(@"XLAppDelegate: Failed to load sequence");
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Failed to Open Sequence";
                alert.informativeText = [NSString stringWithFormat:@"Could not load the sequence file:\n%@", sequencePath];
                alert.alertStyle = NSAlertStyleWarning;
                [alert addButtonWithTitle:@"OK"];
                [alert runModal];
            }
        }
    }];
}

@end
