#import <Cocoa/Cocoa.h>
#import "InspectorView.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, InspectorViewDelegate>

@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) InspectorView *inspectorView;
@property (nonatomic, strong) NSTextView *logView;

@end
