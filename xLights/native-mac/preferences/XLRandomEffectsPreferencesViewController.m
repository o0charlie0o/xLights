//
//  XLRandomEffectsPreferencesViewController.m
//  xLights
//

#import "XLRandomEffectsPreferencesViewController.h"

@implementation XLRandomEffectsPreferencesViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)];
    NSTextField *label = [NSTextField labelWithString:@"RandomEffects Settings (stub)"];
    label.frame = NSMakeRect(20, 20, 560, 20);
    [self.view addSubview:label];
}

@end
