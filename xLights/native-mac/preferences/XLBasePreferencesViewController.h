//
//  XLBasePreferencesViewController.h
//  xLights
//
//  Base class for preference pane view controllers.
//  Provides common functionality for loading/saving settings.
//

#import <Cocoa/Cocoa.h>

@interface XLBasePreferencesViewController : NSViewController

- (void)loadSettings;
- (void)saveSettings;

@end
