//
//  XLPreferencesWindowController.mm
//  xLights
//
//  Native macOS Preferences window controller.
//

#import "XLPreferencesWindowController.h"
#import "XLSequenceFilePreferencesViewController.h"
#import "XLEffectsGridPreferencesViewController.h"
#import "XLOutputPreferencesViewController.h"
#import "XLViewPreferencesViewController.h"
#import "XLColorManagerPreferencesViewController.h"
#import "XLCheckSequencePreferencesViewController.h"
#import "XLBackupPreferencesViewController.h"
#import "XLOtherPreferencesViewController.h"
#import "XLRandomEffectsPreferencesViewController.h"
#import "XLServicesPreferencesViewController.h"

static XLPreferencesWindowController *sharedInstance = nil;

@interface XLPreferencesWindowController ()

@property (nonatomic, strong) NSToolbar *toolbar;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSViewController *> *viewControllers;
@property (nonatomic, strong) NSViewController *currentViewController;
@property (nonatomic, strong) NSView *contentContainerView;

@end

@implementation XLPreferencesWindowController

+ (instancetype)sharedController {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500)
                                                    styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable)
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];

    self = [super initWithWindow:window];
    if (self) {
        [self setupWindow];
        [self setupToolbar];
        [self setupViewControllers];
        [self selectPaneWithIdentifier:@"sequences"];
    }
    return self;
}

- (void)setupWindow {
    self.window.title = @"Preferences";
    self.window.titleVisibility = NSWindowTitleHidden;

    self.contentContainerView = [[NSView alloc] initWithFrame:self.window.contentView.bounds];
    self.contentContainerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.window.contentView addSubview:self.contentContainerView];

    [self.window center];
}

- (void)setupToolbar {
    self.toolbar = [[NSToolbar alloc] initWithIdentifier:@"XLPreferencesToolbar"];
    self.toolbar.delegate = self;
    self.toolbar.allowsUserCustomization = NO;
    self.toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    self.toolbar.sizeMode = NSToolbarSizeModeRegular;
    self.toolbar.selectedItemIdentifier = @"sequences";
    self.window.toolbar = self.toolbar;
}

- (void)setupViewControllers {
    self.viewControllers = [NSMutableDictionary dictionary];

    self.viewControllers[@"sequences"] = [[XLSequenceFilePreferencesViewController alloc] init];
    self.viewControllers[@"effectsGrid"] = [[XLEffectsGridPreferencesViewController alloc] init];
    self.viewControllers[@"output"] = [[XLOutputPreferencesViewController alloc] init];
    self.viewControllers[@"view"] = [[XLViewPreferencesViewController alloc] init];
    self.viewControllers[@"colorManager"] = [[XLColorManagerPreferencesViewController alloc] init];
    self.viewControllers[@"checkSequence"] = [[XLCheckSequencePreferencesViewController alloc] init];
    self.viewControllers[@"backup"] = [[XLBackupPreferencesViewController alloc] init];
    self.viewControllers[@"randomEffects"] = [[XLRandomEffectsPreferencesViewController alloc] init];
    self.viewControllers[@"other"] = [[XLOtherPreferencesViewController alloc] init];

#ifdef ENABLE_SERVICES
    self.viewControllers[@"services"] = [[XLServicesPreferencesViewController alloc] init];
#endif
}

- (void)selectPaneWithIdentifier:(NSString *)identifier {
    NSViewController *viewController = self.viewControllers[identifier];
    if (!viewController) return;

    if (self.currentViewController) {
        [self.currentViewController.view removeFromSuperview];
    }

    self.currentViewController = viewController;

    NSView *newView = viewController.view;
    newView.frame = self.contentContainerView.bounds;
    newView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.contentContainerView addSubview:newView];

    self.toolbar.selectedItemIdentifier = identifier;

    [self resizeWindowForViewController:viewController];
}

- (void)resizeWindowForViewController:(NSViewController *)viewController {
    NSSize contentSize = viewController.view.fittingSize;
    NSRect windowFrame = self.window.frame;
    NSRect contentRect = [self.window contentRectForFrameRect:windowFrame];

    CGFloat toolbarHeight = windowFrame.size.height - contentRect.size.height;
    CGFloat newHeight = contentSize.height + toolbarHeight;
    CGFloat newWidth = MAX(contentSize.width, 600);

    NSRect newFrame = NSMakeRect(windowFrame.origin.x,
                                windowFrame.origin.y + windowFrame.size.height - newHeight,
                                newWidth,
                                newHeight);

    [self.window setFrame:newFrame display:YES animate:self.window.isVisible];
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    NSMutableArray *items = [NSMutableArray arrayWithObjects:
                            @"backup",
                            @"view",
                            @"effectsGrid",
                            @"sequences",
                            @"output",
                            @"checkSequence",
                            @"randomEffects",
                            @"colorManager",
                            @"other",
                            nil];

#ifdef ENABLE_SERVICES
    [items addObject:@"services"];
#endif

    return items;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];

    if ([itemIdentifier isEqualToString:@"backup"]) {
        item.label = @"Backup";
        item.image = [NSImage imageWithSystemSymbolName:@"externaldrive" accessibilityDescription:@"Backup"];
    }
    else if ([itemIdentifier isEqualToString:@"view"]) {
        item.label = @"View";
        item.image = [NSImage imageWithSystemSymbolName:@"eye" accessibilityDescription:@"View"];
    }
    else if ([itemIdentifier isEqualToString:@"effectsGrid"]) {
        item.label = @"Effects Grid";
        item.image = [NSImage imageWithSystemSymbolName:@"square.grid.3x3" accessibilityDescription:@"Effects Grid"];
    }
    else if ([itemIdentifier isEqualToString:@"sequences"]) {
        item.label = @"Sequences";
        item.image = [NSImage imageWithSystemSymbolName:@"list.bullet" accessibilityDescription:@"Sequences"];
    }
    else if ([itemIdentifier isEqualToString:@"output"]) {
        item.label = @"Output";
        item.image = [NSImage imageWithSystemSymbolName:@"lightbulb" accessibilityDescription:@"Output"];
    }
    else if ([itemIdentifier isEqualToString:@"checkSequence"]) {
        item.label = @"Check Sequence";
        item.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle" accessibilityDescription:@"Check Sequence"];
    }
    else if ([itemIdentifier isEqualToString:@"randomEffects"]) {
        item.label = @"Random Effects";
        item.image = [NSImage imageWithSystemSymbolName:@"die.face.5" accessibilityDescription:@"Random Effects"];
    }
    else if ([itemIdentifier isEqualToString:@"colorManager"]) {
        item.label = @"Colors";
        item.image = [NSImage imageWithSystemSymbolName:@"paintpalette" accessibilityDescription:@"Colors"];
    }
    else if ([itemIdentifier isEqualToString:@"other"]) {
        item.label = @"Other";
        item.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"Other"];
    }
    else if ([itemIdentifier isEqualToString:@"services"]) {
        item.label = @"Services";
        item.image = [NSImage imageWithSystemSymbolName:@"cloud" accessibilityDescription:@"Services"];
    }

    item.target = self;
    item.action = @selector(toolbarItemSelected:);

    return item;
}

- (void)toolbarItemSelected:(NSToolbarItem *)item {
    [self selectPaneWithIdentifier:item.itemIdentifier];
}

@end
