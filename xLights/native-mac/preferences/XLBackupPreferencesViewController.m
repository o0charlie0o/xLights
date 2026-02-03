//
//  XLBackupPreferencesViewController.m
//  xLights
//

#import "XLBackupPreferencesViewController.h"

@implementation XLBackupPreferencesViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)];
    NSTextField *label = [NSTextField labelWithString:@"Backup Settings (stub)"];
    label.frame = NSMakeRect(20, 20, 560, 20);
    [self.view addSubview:label];
}

@end
