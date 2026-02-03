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
#import "XLMainWindowController.h"

// SwiftUI window launcher (defined in XLSwiftWindowLauncher.swift)
extern int XLLaunchSwiftUIWindow(void);

// Set to 1 to use legacy AppKit window, 0 for new SwiftUI window
#define USE_LEGACY_APPKIT_WINDOW 0

#if USE_LEGACY_APPKIT_WINDOW
static XLMainWindowController *sNativeWindowController = nil;
#endif

int XLTryLaunchNativeWindow(void) {
#if USE_LEGACY_APPKIT_WINDOW
    // Legacy AppKit-based window (has resize issues due to Auto Layout conflicts)
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"NativeUI [launcher]: creating AppKit window controller (legacy)");
        sNativeWindowController = [[XLMainWindowController alloc] init];
        NSWindow *win = sNativeWindowController.window;

        NSLog(@"NativeUI [launcher]: after init, frame=%@  isVisible=%d",
              NSStringFromRect(win.frame), win.isVisible);

        [win setTitle:@"xLights — Native macOS Preview"];

        // Remember the target frame before makeKeyAndOrderFront (which triggers
        // Auto Layout and may collapse the window).
        NSRect targetFrame = win.frame;
        [win makeKeyAndOrderFront:nil];

        NSLog(@"NativeUI [launcher]: after makeKey, frame=%@  isVisible=%d  isOnActiveSpace=%d",
              NSStringFromRect(win.frame), win.isVisible, win.isOnActiveSpace);

        // After the initial layout pass, force the frame back to the intended size.
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"NativeUI [launcher async]: restoring frame to %@  (current: %@)",
                  NSStringFromRect(targetFrame), NSStringFromRect(win.frame));
            [win setFrame:targetFrame display:YES animate:NO];
            NSLog(@"NativeUI [launcher async]: after setFrame: %@", NSStringFromRect(win.frame));
        });
    });
    return 1;
#else
    // New SwiftUI-based window (solves resize issues)
    NSLog(@"NativeUI [launcher]: launching SwiftUI-based window");
    return XLLaunchSwiftUIWindow();
#endif
}
