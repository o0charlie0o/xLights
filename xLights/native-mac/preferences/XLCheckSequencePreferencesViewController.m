//
//  XLCheckSequencePreferencesViewController.m
//  xLights
//

#import "XLCheckSequencePreferencesViewController.h"

@implementation XLCheckSequencePreferencesViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)];
    NSTextField *label = [NSTextField labelWithString:@"CheckSequence Settings (stub)"];
    label.frame = NSMakeRect(20, 20, 560, 20);
    [self.view addSubview:label];
}

@end
