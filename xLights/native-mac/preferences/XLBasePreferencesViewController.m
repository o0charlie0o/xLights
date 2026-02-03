//
//  XLBasePreferencesViewController.m
//  xLights
//

#import "XLBasePreferencesViewController.h"

@implementation XLBasePreferencesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadSettings];
}

- (void)viewWillDisappear {
    [super viewWillDisappear];
    [self saveSettings];
}

- (void)loadSettings {
}

- (void)saveSettings {
}

@end
