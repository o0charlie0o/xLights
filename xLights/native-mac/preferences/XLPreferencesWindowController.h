//
//  XLPreferencesWindowController.h
//  xLights
//
//  Native macOS Preferences window controller.
//  Uses NSToolbar-based tab switching following the standard macOS pattern.
//

#import <Cocoa/Cocoa.h>

@interface XLPreferencesWindowController : NSWindowController <NSToolbarDelegate>

+ (instancetype)sharedController;

- (void)showWindow:(id)sender;

@end
