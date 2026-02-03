//
//  XLApplication.h
//  xLights
//
//  Native macOS application delegate integration.
//  Handles Cmd+, shortcut to open preferences.
//

#import <Cocoa/Cocoa.h>

@interface XLApplication : NSObject <NSApplicationDelegate>

+ (void)showPreferences;

@end
