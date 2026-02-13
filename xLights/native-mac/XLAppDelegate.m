#import "XLAppDelegate.h"
#import "XLDocumentController.h"
#import "XLToolbarExtensions.h"
#import "preferences/XLPreferencesWindowController.h"
#import "dialogs/XLSequenceDialogs.h"
#import "dialogs/XLBatchRenderDialog.h"
#import "dialogs/XLRenderProgressDialog.h"
#import "dialogs/XLToolsDialogs.h"
#import "dialogs/XLConvertDialogs.h"
#import "dialogs/XLModelDialogs.h"
#import "XLMainWindowController.h"
#import "XLEngineBridge.h"
#import "XLSequencerViewController.h"
#import "XLKeyBindingsWindowController.h"
#import "XLFPPConnectWindowController.h"
#import "XLScriptRunnerWindowController.h"
#import "XLSetupViewController.h"
#import "XLMCPServer.h"
#import "setup/XLMultiControllerUploadDialogController.h"
#import "layout/XLModelImportSheet.h"

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

NSNotificationName const XLShowFolderDidChangeNotification = @"XLShowFolderDidChangeNotification";

@interface XLAppDelegate ()

@property (nonatomic, strong) XLDocumentController *documentController;
@property (nonatomic, strong) XLFPPConnectWindowController *fppConnectWindow;
@property (nonatomic, strong) XLScriptRunnerWindowController *scriptRunnerWindow;
@property (nonatomic, strong) XLCleanupFileLocationsDialog *cleanupDialog;
@property (nonatomic, strong) XLPackageSequenceDialog *packageDialog;
@property (nonatomic, strong) XLDownloadSequencesDialog *downloadDialog;
@property (nonatomic, strong) XLPrepareAudioDialog *prepareAudioDialog;
@property (nonatomic, strong) XLConvertDialog *convertDialog;
@property (nonatomic, strong) XLModelImportSheet *activeImportSheet;
@property (nonatomic, strong) XLMultiControllerUploadDialogController *multiUploadDialog;
@property (nonatomic, strong) XLMCPServer *mcpServer;

/// The permanent show folder path (stored in defaults).
@property (nonatomic, copy) NSString *permanentShowFolder;
/// YES when the current show folder is a temporary override.
@property (nonatomic, assign) BOOL isTemporaryFolder;

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

    // Initialize permanent folder from saved defaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *lastShowFolder = [defaults stringForKey:@"LastShowFolder"];
    _permanentShowFolder = [lastShowFolder copy];
    _isTemporaryFolder = NO;

    if (lastShowFolder && [[NSFileManager defaultManager] fileExistsAtPath:lastShowFolder isDirectory:NULL]) {
        // Restore last show folder
        [self loadShowFolderPath:lastShowFolder permanent:YES];
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
    // Stop MCP server
    [_mcpServer stop];
    _mcpServer = nil;

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

- (IBAction)toggleSongRegionOverlay:(id)sender {
    XLSwiftUIWindowHelper *helper = [XLSwiftUIWindowHelper shared];
    BOOL newState = ![helper isSongRegionOverlayVisible];
    [helper setSongRegionOverlayVisible:newState];
    // Update the grid view directly
    XLSequencerViewController *vc = helper.sequencerViewController;
    if (vc) {
        [vc setSongRegionOverlayVisible:newState];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(toggleSongRegionOverlay:)) {
        BOOL isOn = [[XLSwiftUIWindowHelper shared] isSongRegionOverlayVisible];
        menuItem.state = isOn ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    return YES;
}

- (IBAction)togglePreview:(id)sender {
    // Responder chain fallback — use the stored sequencer VC reference directly.
    XLSequencerViewController *vc = [XLSwiftUIWindowHelper shared].sequencerViewController;
    if (vc) {
        [vc toggleHousePreview];
        return;
    }
    // Legacy path: find XLMainWindowController if the SwiftUI window isn't active.
    for (NSWindow *window in [NSApp windows]) {
        NSWindowController *wc = window.windowController;
        if ([wc isKindOfClass:[XLMainWindowController class]]) {
            XLMainWindowController *mainController = (XLMainWindowController *)wc;
            [mainController.sequencerViewController toggleHousePreview];
            return;
        }
    }
}

#pragma mark - Private Helpers

- (void)loadShowFolderPath:(NSString *)path {
    [self loadShowFolderPath:path permanent:YES];
}

- (void)loadShowFolderPath:(NSString *)path permanent:(BOOL)permanent {
    NSLog(@"XLAppDelegate: Loading show folder: %@ (permanent=%d)", path, permanent);

    // Load the show folder into the engine bridge
    XLSwiftUIWindowHelper *swiftHelper = [XLSwiftUIWindowHelper shared];
    XLEngineBridge *engineBridge = swiftHelper.engineBridge;

    if (engineBridge) {
        BOOL success = [engineBridge loadShowFolder:path];
        if (success) {
            NSLog(@"XLAppDelegate: Show folder loaded successfully");

            if (permanent) {
                // Save as permanent show folder
                _permanentShowFolder = [path copy];
                _isTemporaryFolder = NO;
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setObject:path forKey:@"LastShowFolder"];
                // Add to MRU list
                [self addRecentShowFolder:path];
            } else {
                // Temporary folder — don't save to defaults
                _isTemporaryFolder = YES;
            }

            // Notify SwiftUI to refresh
            [swiftHelper notifySequenceDataChanged];
            // Notify observers that the show folder changed (for key bindings, etc.)
            [[NSNotificationCenter defaultCenter] postNotificationName:XLShowFolderDidChangeNotification
                                                                object:self
                                                              userInfo:@{@"path": path,
                                                                         @"permanent": @(permanent)}];
            // Start MCP server if not already running
            if (!_mcpServer) {
                _mcpServer = [[XLMCPServer alloc] initWithEngineBridge:engineBridge];
                if ([_mcpServer start]) {
                    NSLog(@"XLAppDelegate: MCP server started on port %u", _mcpServer.port);
                } else {
                    NSLog(@"XLAppDelegate: MCP server failed to start");
                }
            }
        } else {
            NSLog(@"XLAppDelegate: Failed to load show folder");
            // Prompt for a different folder
            [self promptForShowFolder];
        }
    } else {
        NSLog(@"XLAppDelegate: Engine bridge not available, deferring show folder load");
        // Store path and try again after a short delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self loadShowFolderPath:path permanent:permanent];
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

#pragma mark - File Menu Actions

- (IBAction)selectShowFolder:(id)sender {
    // "Select Show Folder" from menu always saves permanently
    [self promptForShowFolder];
}

- (IBAction)selectShowFolderTemporarily:(id)sender {
    NSLog(@"XLAppDelegate: Selecting temporary show folder");

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Select a temporary show folder (will revert on restart)";
    panel.prompt = @"Use Temporarily";

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            [self loadShowFolderPath:panel.URL.path permanent:NO];
        }
    }];
}

- (void)restorePermanentShowFolder {
    if (!_isTemporaryFolder) return;

    NSString *perm = _permanentShowFolder;
    if (perm && [[NSFileManager defaultManager] fileExistsAtPath:perm isDirectory:NULL]) {
        NSLog(@"XLAppDelegate: Restoring permanent show folder: %@", perm);
        [self loadShowFolderPath:perm permanent:YES];
    } else {
        NSLog(@"XLAppDelegate: No permanent show folder to restore");
        [self promptForShowFolder];
    }
}

#pragma mark - Recent Show Folders

- (NSArray<NSString *> *)recentShowFolders {
    return [[NSUserDefaults standardUserDefaults] arrayForKey:@"RecentShowFolders"] ?: @[];
}

- (void)addRecentShowFolder:(NSString *)path {
    if (!path || path.length == 0) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *recents = [[defaults arrayForKey:@"RecentShowFolders"] mutableCopy] ?: [NSMutableArray new];

    [recents removeObject:path];
    [recents insertObject:path atIndex:0];

    if (recents.count > 10) {
        [recents removeObjectsInRange:NSMakeRange(10, recents.count - 10)];
    }

    [defaults setObject:recents forKey:@"RecentShowFolders"];
}

- (IBAction)backupShowFolder:(id)sender {
    NSString *showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    if (!showFolder) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Show Folder";
        alert.informativeText = @"Please select a show folder first.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    // Create backup in show folder's Backup subdirectory
    NSString *backupDir = [showFolder stringByAppendingPathComponent:@"Backup"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;

    if (![fm fileExistsAtPath:backupDir]) {
        [fm createDirectoryAtPath:backupDir withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Backup Failed";
            alert.informativeText = [NSString stringWithFormat:@"Could not create backup directory: %@", error.localizedDescription];
            alert.alertStyle = NSAlertStyleWarning;
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
            return;
        }
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd_HHmmss";
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *backupPath = [backupDir stringByAppendingPathComponent:timestamp];

    [fm createDirectoryAtPath:backupPath withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Backup Failed";
        alert.informativeText = error.localizedDescription;
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    // Copy XML and xlights files to backup
    NSArray *contents = [fm contentsOfDirectoryAtPath:showFolder error:nil];
    NSInteger copiedCount = 0;
    for (NSString *file in contents) {
        NSString *ext = file.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"xml"] || [ext isEqualToString:@"xlights"] ||
            [ext isEqualToString:@"xsq"] || [ext isEqualToString:@"xbkp"]) {
            NSString *src = [showFolder stringByAppendingPathComponent:file];
            NSString *dst = [backupPath stringByAppendingPathComponent:file];
            [fm copyItemAtPath:src toPath:dst error:nil];
            copiedCount++;
        }
    }

    NSLog(@"XLAppDelegate: Backup complete - %ld files to %@", (long)copiedCount, backupPath);

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Backup Complete";
    alert.informativeText = [NSString stringWithFormat:@"Backed up %ld files to:\n%@", (long)copiedCount, backupPath];
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)restoreBackup:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Restore Backup";
    alert.informativeText = @"Not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)alternateBackup:(id)sender {
    NSString *showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    if (!showFolder) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Show Folder";
        alert.informativeText = @"Please select a show folder first.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Select alternate backup destination";
    panel.prompt = @"Backup Here";

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"yyyy-MM-dd_HHmmss";
            NSString *timestamp = [formatter stringFromDate:[NSDate date]];
            NSString *backupPath = [panel.URL.path stringByAppendingPathComponent:
                                    [NSString stringWithFormat:@"xLights_Backup_%@", timestamp]];

            NSError *error = nil;
            [fm createDirectoryAtPath:backupPath withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Alternate Backup Failed";
                alert.informativeText = error.localizedDescription;
                alert.alertStyle = NSAlertStyleWarning;
                [alert addButtonWithTitle:@"OK"];
                [alert runModal];
                return;
            }

            NSArray *contents = [fm contentsOfDirectoryAtPath:showFolder error:nil];
            NSInteger copiedCount = 0;
            for (NSString *file in contents) {
                NSString *ext = file.pathExtension.lowercaseString;
                if ([ext isEqualToString:@"xml"] || [ext isEqualToString:@"xlights"] ||
                    [ext isEqualToString:@"xsq"] || [ext isEqualToString:@"xbkp"]) {
                    NSString *src = [showFolder stringByAppendingPathComponent:file];
                    NSString *dst = [backupPath stringByAppendingPathComponent:file];
                    [fm copyItemAtPath:src toPath:dst error:nil];
                    copiedCount++;
                }
            }

            NSLog(@"XLAppDelegate: Alternate backup complete - %ld files to %@", (long)copiedCount, backupPath);

            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Alternate Backup Complete";
            alert.informativeText = [NSString stringWithFormat:@"Backed up %ld files to:\n%@", (long)copiedCount, backupPath];
            alert.alertStyle = NSAlertStyleInformational;
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        }
    }];
}

- (IBAction)showSequenceSettings:(id)sender {
    XLSwiftUIWindowHelper *swiftHelper = [XLSwiftUIWindowHelper shared];
    XLEngineBridge *engineBridge = swiftHelper.engineBridge;

    if (!engineBridge) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Engine";
        alert.informativeText = @"The engine is not initialized. Please open a show folder first.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    if (![engineBridge isSequenceLoaded]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Sequence Loaded";
        alert.informativeText = @"Please open a sequence before editing its settings.";
        alert.alertStyle = NSAlertStyleInformational;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    NSDictionary *seqInfo = [engineBridge getSequenceInfo];

    XLSequenceSettingsDialog *dialog = [[XLSequenceSettingsDialog alloc] init];
    dialog.sequenceName = seqInfo[@"name"] ?: @"";
    dialog.author = seqInfo[@"author"] ?: @"";
    dialog.authorEmail = @"";
    dialog.authorWebsite = @"";
    dialog.songName = seqInfo[@"song"] ?: @"";
    dialog.artistName = seqInfo[@"artist"] ?: @"";
    dialog.albumName = seqInfo[@"album"] ?: @"";
    dialog.comments = seqInfo[@"comment"] ?: @"";
    dialog.durationMs = [seqInfo[@"durationMS"] integerValue];
    dialog.frameIntervalMs = [seqInfo[@"frameTimeMS"] integerValue];

    NSWindow *parentWindow = [NSApp keyWindow] ?: [NSApp mainWindow];

    [dialog presentAsSheetForWindow:parentWindow completion:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            NSMutableDictionary *updates = [NSMutableDictionary dictionary];
            updates[@"author"] = dialog.author ?: @"";
            updates[@"song"] = dialog.songName ?: @"";
            updates[@"artist"] = dialog.artistName ?: @"";
            updates[@"album"] = dialog.albumName ?: @"";
            updates[@"comment"] = dialog.comments ?: @"";

            [engineBridge setSequenceInfo:updates];

            NSLog(@"XLAppDelegate: Sequence settings updated");
        }
    }];
}

- (IBAction)showKeyBindings:(id)sender {
    NSString *showFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    XLKeyBindingsWindowController *kbController = [XLKeyBindingsWindowController sharedController];
    if (showFolder.length > 0) {
        [kbController setShowFolderPath:showFolder];
    }
    [kbController showWindow:sender];
}

- (IBAction)exportHousePreviewVideo:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Export House Preview Video";
    alert.informativeText = @"Not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)importModels:(id)sender {
    NSWindow *window = [NSApp mainWindow];
    if (!window) return;

    XLSwiftUIWindowHelper *swiftHelper = [XLSwiftUIWindowHelper shared];
    XLEngineBridge *engineBridge = swiftHelper.engineBridge;
    if (!engineBridge) return;

    _activeImportSheet = [[XLModelImportSheet alloc] init];
    _activeImportSheet.engineBridge = engineBridge;

    __weak typeof(self) weakSelf = self;
    [_activeImportSheet showAsSheetForWindow:window
                                 completion:^(BOOL imported, NSArray<NSString *> *importedModelNames) {
        if (imported && importedModelNames.count > 0) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"XLModelsDidChangeNotification"
                                                                object:nil
                                                              userInfo:@{@"importedModels": importedModelNames}];
        }
        weakSelf.activeImportSheet = nil;
    }];
}

- (IBAction)importModelsFromRGBEffects:(id)sender {
    NSWindow *window = [NSApp mainWindow];
    if (!window) return;

    XLSwiftUIWindowHelper *swiftHelper = [XLSwiftUIWindowHelper shared];
    XLEngineBridge *engineBridge = swiftHelper.engineBridge;
    if (!engineBridge) return;

    _activeImportSheet = [[XLModelImportSheet alloc] init];
    _activeImportSheet.engineBridge = engineBridge;

    __weak typeof(self) weakSelf = self;
    [_activeImportSheet showRGBEffectsImportForWindow:window
                                           completion:^(BOOL imported, NSArray<NSString *> *importedModelNames) {
        if (imported && importedModelNames.count > 0) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"XLModelsDidChangeNotification"
                                                                object:nil
                                                              userInfo:@{@"importedModels": importedModelNames}];
        }
        weakSelf.activeImportSheet = nil;
    }];
}

#pragma mark - Audio Menu Actions

- (IBAction)setPlaybackSpeed:(id)sender {
    NSMenuItem *selectedItem = (NSMenuItem *)sender;
    NSMenu *menu = selectedItem.menu;

    // Clear all speed items (tags 25-400), set selected
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == @selector(setPlaybackSpeed:)) {
            item.state = (item == selectedItem) ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }

    NSInteger speedPercent = selectedItem.tag;
    double speed = speedPercent / 100.0;
    NSLog(@"XLAppDelegate: Playback speed set to %.2fx", speed);

    XLEngineBridge *engineBridge = [XLSwiftUIWindowHelper shared].engineBridge;
    if (engineBridge) {
        [engineBridge setPlaybackSpeed:speed];
    }
}

- (IBAction)setVolume:(id)sender {
    NSMenuItem *selectedItem = (NSMenuItem *)sender;
    NSMenu *menu = selectedItem.menu;

    // Clear all volume items, set selected
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == @selector(setVolume:)) {
            item.state = (item == selectedItem) ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }

    NSInteger volumePercent = selectedItem.tag;
    NSLog(@"XLAppDelegate: Volume set to %ld%%", (long)volumePercent);

    XLEngineBridge *engineBridge = [XLSwiftUIWindowHelper shared].engineBridge;
    if (engineBridge) {
        [engineBridge setAudioVolume:volumePercent];
    }
}

#pragma mark - Audio Stems Menu Actions

- (IBAction)importAudioStems:(id)sender {
    XLSequencerViewController *vc = [XLSwiftUIWindowHelper shared].sequencerViewController;
    if (vc) [vc importAudioStems:sender];
}

- (IBAction)importStemsFromFolder:(id)sender {
    XLSequencerViewController *vc = [XLSwiftUIWindowHelper shared].sequencerViewController;
    if (vc) [vc importStemsFromFolder:sender];
}

- (IBAction)removeAllAudioStems:(id)sender {
    XLSequencerViewController *vc = [XLSwiftUIWindowHelper shared].sequencerViewController;
    if (vc) [vc removeAllAudioStems:sender];
}

#pragma mark - Tools Menu Actions

- (IBAction)showTest:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Test";
    alert.informativeText = @"Not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)checkSequence:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Check Sequence";
    alert.informativeText = @"Not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)cleanupFileLocations:(id)sender {
    if (!_cleanupDialog) {
        _cleanupDialog = [[XLCleanupFileLocationsDialog alloc] init];
        _cleanupDialog.engineBridge = [XLSwiftUIWindowHelper shared].engineBridge;
    }
    [_cleanupDialog showWithCompletion:^{}];
}

- (IBAction)packageSequence:(id)sender {
    if (!_packageDialog) {
        _packageDialog = [[XLPackageSequenceDialog alloc] init];
        _packageDialog.engineBridge = [XLSwiftUIWindowHelper shared].engineBridge;
    }
    [_packageDialog showWithCompletion:^{}];
}

- (IBAction)downloadSequences:(id)sender {
    if (!_downloadDialog) {
        _downloadDialog = [[XLDownloadSequencesDialog alloc] init];
    }
    [_downloadDialog showWithCompletion:^{}];
}

- (IBAction)batchRender:(id)sender {
    XLSwiftUIWindowHelper *swiftHelper = [XLSwiftUIWindowHelper shared];
    XLEngineBridge *engineBridge = swiftHelper.engineBridge;

    if (!engineBridge) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Engine";
        alert.informativeText = @"The engine is not initialized. Please open a show folder first.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    NSString *showDirectory = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastShowFolder"];
    if (!showDirectory) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Show Folder";
        alert.informativeText = @"Please select a show folder first.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    XLBatchRenderDialog *dialog = [[XLBatchRenderDialog alloc] init];
    dialog.engineBridge = engineBridge;
    dialog.showDirectory = showDirectory;

    NSWindow *parentWindow = [NSApp keyWindow] ?: [NSApp mainWindow];

    [dialog presentAsSheetForWindow:parentWindow completion:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            NSArray<NSString *> *selectedSequences = dialog.selectedSequences;
            BOOL forceHD = dialog.forceHighDefinition;

            NSLog(@"XLAppDelegate: Batch render requested - %lu sequences, forceHD=%d",
                  (unsigned long)selectedSequences.count, forceHD);

            if (selectedSequences.count == 0) return;

            XLRenderProgressDialog *progressDialog = [[XLRenderProgressDialog alloc] init];
            for (NSString *seqName in selectedSequences) {
                [progressDialog addProgressItemForModel:seqName];
            }
            [progressDialog showForWindow:parentWindow];

            __block NSInteger completedCount = 0;
            __block NSInteger failedCount = 0;
            NSInteger totalCount = selectedSequences.count;

            for (NSInteger i = 0; i < (NSInteger)selectedSequences.count; i++) {
                NSString *seqName = selectedSequences[i];
                NSString *seqPath = [showDirectory stringByAppendingPathComponent:seqName];

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.1 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [progressDialog updateStatusForModel:seqName status:@"Rendering..."];

                    [engineBridge renderSequenceToFSEQ:seqPath outputPath:nil completion:^(BOOL success, NSString *message) {
                        completedCount++;

                        if (success) {
                            [progressDialog markCompleted:seqName];
                            [progressDialog updateStatusForModel:seqName status:@"Complete"];
                        } else {
                            failedCount++;
                            [progressDialog updateStatusForModel:seqName status:message ?: @"Failed"];
                            [progressDialog updateProgressForModel:seqName progress:1.0];
                        }

                        if (completedCount == totalCount) {
                            [progressDialog markAllCompleted];

                            NSString *summary;
                            if (failedCount == 0) {
                                summary = [NSString stringWithFormat:@"All %ld sequences rendered successfully.", (long)totalCount];
                            } else {
                                summary = [NSString stringWithFormat:@"%ld of %ld sequences rendered. %ld failed.",
                                           (long)(totalCount - failedCount), (long)totalCount, (long)failedCount];
                            }
                            NSLog(@"XLAppDelegate: Batch render complete - %@", summary);
                        }
                    }];
                });
            }
        }
    }];
}

- (IBAction)fppConnect:(id)sender {
    XLSwiftUIWindowHelper *swiftHelper = [XLSwiftUIWindowHelper shared];
    XLEngineBridge *engineBridge = swiftHelper.engineBridge;

    if (!_fppConnectWindow || !_fppConnectWindow.window.isVisible) {
        _fppConnectWindow = [[XLFPPConnectWindowController alloc] initWithEngineBridge:engineBridge];
    }

    [_fppConnectWindow showWindow:sender];
}

- (IBAction)bulkControllerUpload:(id)sender {
    XLEngineBridge *engineBridge = [XLSwiftUIWindowHelper shared].engineBridge;
    if (!engineBridge) return;

    NSWindow *parentWindow = [NSApp keyWindow];
    if (!parentWindow) parentWindow = [NSApp mainWindow];
    if (!parentWindow) return;

    // Try to use the setup view controller's sheet presentation if available
    for (NSWindow *window in [NSApp windows]) {
        NSWindowController *wc = window.windowController;
        if ([wc isKindOfClass:[XLMainWindowController class]]) {
            XLMainWindowController *mainController = (XLMainWindowController *)wc;
            if (mainController.setupViewController) {
                [mainController.setupViewController presentMultiControllerUploadDialog];
                return;
            }
        }
    }

    // Fallback: present as sheet on current window
    _multiUploadDialog = [[XLMultiControllerUploadDialogController alloc] initWithEngineBridge:engineBridge];
    [_multiUploadDialog presentAsSheetOnWindow:parentWindow];
}

- (IBAction)runScripts:(id)sender {
    if (!_scriptRunnerWindow) {
        _scriptRunnerWindow = [[XLScriptRunnerWindowController alloc] init];
        _scriptRunnerWindow.engineBridge = [XLSwiftUIWindowHelper shared].engineBridge;
    }
    [_scriptRunnerWindow showWindow:sender];
}

- (IBAction)exportModelsFromTools:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Export Models";
    alert.informativeText = @"Not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)exportEffectsFromTools:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Export Effects";
    alert.informativeText = @"Not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)exportControllerConnections:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Export Controller Connections";
    alert.informativeText = @"Not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)viewLog:(id)sender {
    // Open the log file in Console.app or default text editor
    NSString *logPath = [NSString stringWithFormat:@"%@/Library/Logs/xLights", NSHomeDirectory()];
    NSFileManager *fm = [NSFileManager defaultManager];

    // Find the most recent log file
    NSArray *contents = [fm contentsOfDirectoryAtPath:logPath error:nil];
    NSString *latestLog = nil;
    NSDate *latestDate = nil;

    for (NSString *file in contents) {
        if ([file.pathExtension isEqualToString:@"log"]) {
            NSString *fullPath = [logPath stringByAppendingPathComponent:file];
            NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
            NSDate *modDate = attrs[NSFileModificationDate];
            if (!latestDate || [modDate compare:latestDate] == NSOrderedDescending) {
                latestDate = modDate;
                latestLog = fullPath;
            }
        }
    }

    if (latestLog) {
        [[NSWorkspace sharedWorkspace] openFile:latestLog];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Log File Found";
        alert.informativeText = @"Could not find any xLights log files.";
        alert.alertStyle = NSAlertStyleInformational;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
}

- (IBAction)packageLogFiles:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Package Log Files";
    alert.informativeText = @"Not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)purgeDownloadCache:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Purge Download Cache";
    alert.informativeText = @"Not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)purgeRenderCache:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Purge Render Cache";
    alert.informativeText = @"Not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)generate2DPath:(id)sender {
    XLGeneratorPlaceholderDialog *dialog = [[XLGeneratorPlaceholderDialog alloc] init];
    dialog.featureName = @"Generate 2D Path";
    dialog.featureDescription = @"Generates a 2D motion path for effects like Marquee, Servo, and "
        @"other position-based effects. Draw or import a path that effects can follow over time.";
    dialog.plannedCapabilities = @[
        @"Interactive path drawing canvas",
        @"Import paths from SVG files",
        @"Preview path with timing visualization",
        @"Export path data for use in effects",
        @"Bezier curve and linear segment support"
    ];
    [dialog presentAsModalWithCompletion:nil];
}

- (IBAction)generateCustomModel:(id)sender {
    XLSwiftUIWindowHelper *swiftHelper = [XLSwiftUIWindowHelper shared];
    XLEngineBridge *engineBridge = swiftHelper.engineBridge;

    XLGenerateCustomModelDialog *dialog = [[XLGenerateCustomModelDialog alloc] init];
    dialog.engineBridge = engineBridge;
    [dialog showWithCompletion:^(BOOL accepted) {
        if (accepted && dialog.generatedModelData.length > 0) {
            NSLog(@"Generated custom model '%@' with %ld nodes, grid %ld x %ld",
                  dialog.modelName, (long)dialog.generatedNodeCount,
                  (long)dialog.gridWidth, (long)dialog.gridHeight);
        }
    }];
}

- (IBAction)remapCustomModel:(id)sender {
    XLGeneratorPlaceholderDialog *dialog = [[XLGeneratorPlaceholderDialog alloc] init];
    dialog.featureName = @"Remap Custom Model";
    dialog.featureDescription = @"Remaps pixel numbering in an existing custom model. Useful when you need to "
        @"change wiring order, reverse strings, or reorganize pixel assignments without recreating the model.";
    dialog.plannedCapabilities = @[
        @"Visual pixel renumbering interface",
        @"Bulk renumber with offset/reverse",
        @"String reordering tools",
        @"Preview before and after mapping",
        @"Undo/redo support for remapping changes"
    ];
    [dialog presentAsModalWithCompletion:nil];
}

- (IBAction)generateLyricsFromData:(id)sender {
    XLGeneratorPlaceholderDialog *dialog = [[XLGeneratorPlaceholderDialog alloc] init];
    dialog.featureName = @"Generate Lyrics From Data";
    dialog.featureDescription = @"Extracts lyric timing data from an existing sequence and generates "
        @"a lyrics timing track. Analyzes phoneme and word timing information from face effects.";
    dialog.plannedCapabilities = @[
        @"Extract lyrics from face effect data",
        @"Generate word-level timing marks",
        @"Generate phoneme-level timing marks",
        @"Export as lyrics text file",
        @"Import timing from LRC/SRT subtitle files"
    ];
    [dialog presentAsModalWithCompletion:nil];
}

- (IBAction)convertSequence:(id)sender {
    if (!_convertDialog) {
        _convertDialog = [[XLConvertDialog alloc] init];
        _convertDialog.engineBridge = [XLSwiftUIWindowHelper shared].engineBridge;
    }
    [_convertDialog showWithCompletion:^{}];
}

- (IBAction)prepareAudio:(id)sender {
    if (!_prepareAudioDialog) {
        _prepareAudioDialog = [[XLPrepareAudioDialog alloc] init];
    }
    [_prepareAudioDialog showWithCompletion:^{}];
}

#pragma mark - Help Menu Actions

- (IBAction)showTipOfTheDay:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Tip of the Day";
    alert.informativeText = @"Not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)showUserManual:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://manual.xlights.org"]];
}

- (IBAction)visitForum:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://nutcracker123.com/forum/"]];
}

- (IBAction)showVideoTutorials:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://videos.xlights.org"]];
}

- (IBAction)visitFacebook:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.facebook.com/groups/628061113896314/"]];
}

- (IBAction)visitIssueTracker:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/xLightsSequencer/xLights/issues"]];
}

- (IBAction)showDonate:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.xlights.org/donate/"]];
}

- (IBAction)visitWebsite:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.xlights.org"]];
}

- (IBAction)showReleaseNotes:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/xLightsSequencer/xLights/releases"]];
}

- (IBAction)checkForUpdates:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Check for Updates";
    alert.informativeText = @"Not yet implemented.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
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
    dialog.frameIntervalMs = 25;

    // Show the dialog as a sheet
    [dialog presentAsSheetForWindow:keyWindow completion:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            // Convert duration to milliseconds
            NSInteger durationMS = dialog.durationSeconds * 1000;
            NSInteger frameMS = dialog.frameIntervalMs;
            NSString *audioFile = dialog.audioFilePath;

            // Create the sequence via engine bridge
            BOOL success = [engineBridge createSequence:dialog.sequenceName
                                             durationMS:durationMS
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
                [self addRecentSequence:sequencePath];
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

#pragma mark - Recent Sequences

- (void)addRecentSequence:(NSString *)path {
    if (!path || path.length == 0) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *recents = [[defaults arrayForKey:@"RecentSequences"] mutableCopy] ?: [NSMutableArray new];

    [recents removeObject:path];
    [recents insertObject:path atIndex:0];

    if (recents.count > 10) {
        [recents removeObjectsInRange:NSMakeRange(10, recents.count - 10)];
    }

    [defaults setObject:recents forKey:@"RecentSequences"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"XLRecentSequencesDidChange" object:nil];
}

@end
