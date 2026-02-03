//
//  XLOutputPreferencesViewController.m
//  xLights
//

#import "XLOutputPreferencesViewController.h"

@implementation XLOutputPreferencesViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)];
    NSTextField *label = [NSTextField labelWithString:@"Output Settings (stub)"];
    label.frame = NSMakeRect(20, 20, 560, 20);
    [self.view addSubview:label];
}

@end
