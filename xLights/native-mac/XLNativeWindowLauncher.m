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

static XLMainWindowController *sNativeWindowController = nil;

int XLTryLaunchNativeWindow(void) {
    NSProcessInfo *info = [NSProcessInfo processInfo];
    if (![info.arguments containsObject:@"-nativeUI"]) {
        return 0;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        sNativeWindowController = [[XLMainWindowController alloc] init];
        [sNativeWindowController.window setTitle:@"xLights — Native macOS Preview"];
        [sNativeWindowController.window makeKeyAndOrderFront:nil];
    });

    return 1;
}
