/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

/**
 * @file main_native.mm
 * @brief Native macOS entry point for xLights
 *
 * This file provides the main() entry point for the fully native macOS version
 * of xLights. It replaces the wxWidgets entry point (wxEntry) with the standard
 * AppKit application lifecycle.
 *
 * Entry Point Flow:
 *   Old: main() -> wxEntry() -> xLightsApp::OnInit() -> xLightsFrame
 *   New: main() -> NSApplicationMain() -> XLAppDelegate -> Native UI
 *
 * Initialization Sequence:
 *   1. main_native.mm called
 *   2. NSApplication sharedApplication created
 *   3. XLAppDelegate instantiated and set as delegate
 *   4. NSApplicationMain starts AppKit event loop
 *   5. XLAppDelegate applicationWillFinishLaunching: (document controller setup)
 *   6. XLAppDelegate applicationDidFinishLaunching: (menu bar, window)
 *   7. XLEngineBridge operates in standalone mode (no wxWidgets)
 *   8. Ready to use
 *
 * This entry point is used by the native-only Xcode target which excludes
 * wxWidgets dependencies entirely.
 *
 * @see XLAppDelegate - Handles application lifecycle
 * @see XLEngineBridge - Provides engine functionality in standalone mode
 * @see DECOUPLING_GUIDE.md - Phase 5 documentation
 */

#import <Cocoa/Cocoa.h>
#import "XLAppDelegate.h"

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        // Create the shared application instance
        NSApplication *app = [NSApplication sharedApplication];

        // Set activation policy to regular (foreground app with dock icon and menu bar)
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        // Create and set the application delegate
        // This must be done before the app finishes launching
        XLAppDelegate *delegate = [[XLAppDelegate alloc] init];
        [app setDelegate:delegate];

        // Run the application
        // This starts the event loop and triggers applicationDidFinishLaunching:
        [app run];

        return 0;
    }
}
