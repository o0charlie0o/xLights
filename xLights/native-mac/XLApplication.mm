//
//  XLApplication.mm
//  xLights
//

#import "XLApplication.h"
#import "preferences/XLPreferencesWindowController.h"

@implementation XLApplication

+ (void)showPreferences {
    [[XLPreferencesWindowController sharedController] showWindow:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self setupMenus];
}

- (void)setupMenus {
    NSApplication *app = [NSApplication sharedApplication];
    NSMenu *mainMenu = app.mainMenu;

    if (!mainMenu) {
        mainMenu = [[NSMenu alloc] initWithTitle:@"xLights"];
        app.mainMenu = mainMenu;
    }

    NSMenuItem *appMenuItem = [mainMenu itemAtIndex:0];
    if (!appMenuItem) {
        appMenuItem = [[NSMenuItem alloc] initWithTitle:@"xLights" action:nil keyEquivalent:@""];
        [mainMenu insertItem:appMenuItem atIndex:0];
    }

    NSMenu *appMenu = appMenuItem.submenu;
    if (!appMenu) {
        appMenu = [[NSMenu alloc] initWithTitle:@"xLights"];
        appMenuItem.submenu = appMenu;
    }

    NSMenuItem *preferencesItem = [[NSMenuItem alloc] initWithTitle:@"Preferences..."
                                                             action:@selector(showPreferencesMenu:)
                                                      keyEquivalent:@","];
    preferencesItem.target = self;

    NSUInteger aboutIndex = [appMenu indexOfItemWithTitle:@"About xLights"];
    if (aboutIndex != NSNotFound) {
        [appMenu insertItem:preferencesItem atIndex:aboutIndex + 1];
        [appMenu insertItem:[NSMenuItem separatorItem] atIndex:aboutIndex + 2];
    } else {
        [appMenu addItem:preferencesItem];
    }
}

- (void)showPreferencesMenu:(id)sender {
    [[XLPreferencesWindowController sharedController] showWindow:sender];
}

@end
