#import "AppDelegate.h"

static const CGFloat kWindowWidth = 720.0;
static const CGFloat kWindowHeight = 700.0;
static const CGFloat kInspectorWidth = 320.0;

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSRect frame = NSMakeRect(200, 200, kWindowWidth, kWindowHeight);
    NSWindowStyleMask style = NSWindowStyleMaskTitled
        | NSWindowStyleMaskClosable
        | NSWindowStyleMaskResizable
        | NSWindowStyleMaskMiniaturizable;
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:style
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = @"AppKit Inspector Spike";
    _window.minSize = NSMakeSize(500, 400);

    [self buildUI];
    [self populateInspector];
    [_window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

#pragma mark - UI Construction

- (void)buildUI {
    NSSplitView *splitView = [[NSSplitView alloc] initWithFrame:_window.contentView.bounds];
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    splitView.dividerStyle = NSSplitViewDividerStyleThin;
    splitView.vertical = YES;
    [_window.contentView addSubview:splitView];

    [NSLayoutConstraint activateConstraints:@[
        [splitView.topAnchor constraintEqualToAnchor:_window.contentView.topAnchor],
        [splitView.bottomAnchor constraintEqualToAnchor:_window.contentView.bottomAnchor],
        [splitView.leadingAnchor constraintEqualToAnchor:_window.contentView.leadingAnchor],
        [splitView.trailingAnchor constraintEqualToAnchor:_window.contentView.trailingAnchor],
    ]];

    // Left pane: log output
    NSView *leftPane = [self buildLogPane];
    [splitView addSubview:leftPane];

    // Right pane: inspector
    _inspectorView = [[InspectorView alloc] initWithFrame:NSMakeRect(0, 0, kInspectorWidth, kWindowHeight)];
    _inspectorView.delegate = self;
    [splitView addSubview:_inspectorView];

    [splitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:0];
    [splitView setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:1];

    // Set initial position after layout
    dispatch_async(dispatch_get_main_queue(), ^{
        [splitView setPosition:kWindowWidth - kInspectorWidth ofDividerAtIndex:0];
    });

    // Toolbar with Expand All / Collapse All / Read Values buttons
    [self buildToolbar];
}

- (NSView *)buildLogPane {
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;

    _logView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, kWindowHeight)];
    _logView.editable = NO;
    _logView.selectable = YES;
    _logView.font = [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightRegular];
    _logView.textColor = [NSColor labelColor];
    _logView.backgroundColor = [NSColor textBackgroundColor];
    _logView.textContainerInset = NSMakeSize(8, 8);
    scrollView.documentView = _logView;

    [self appendLog:@"Inspector Spike Ready\n"];
    [self appendLog:@"Change values in the inspector to see events logged here.\n\n"];

    return scrollView;
}

- (void)buildToolbar {
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"InspectorSpikeToolbar"];
    toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    toolbar.delegate = (id<NSToolbarDelegate>)self;
    _window.toolbar = toolbar;
}

// NSToolbarDelegate methods
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"ExpandAll", @"CollapseAll", NSToolbarFlexibleSpaceItemIdentifier, @"ReadValues", @"StressTest"];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"ExpandAll", @"CollapseAll", NSToolbarFlexibleSpaceItemIdentifier, @"ReadValues", @"StressTest"];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];

    if ([itemIdentifier isEqualToString:@"ExpandAll"]) {
        item.label = @"Expand All";
        item.image = [NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:@"Expand"];
        item.target = self;
        item.action = @selector(expandAll:);
    } else if ([itemIdentifier isEqualToString:@"CollapseAll"]) {
        item.label = @"Collapse All";
        item.image = [NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:@"Collapse"];
        item.target = self;
        item.action = @selector(collapseAll:);
    } else if ([itemIdentifier isEqualToString:@"ReadValues"]) {
        item.label = @"Read Values";
        item.image = [NSImage imageWithSystemSymbolName:@"doc.text" accessibilityDescription:@"Read"];
        item.target = self;
        item.action = @selector(readAllValues:);
    } else if ([itemIdentifier isEqualToString:@"StressTest"]) {
        item.label = @"50+ Props";
        item.image = [NSImage imageWithSystemSymbolName:@"gauge.with.dots.needle.67percent" accessibilityDescription:@"Stress"];
        item.target = self;
        item.action = @selector(runStressTest:);
    }

    return item;
}

#pragma mark - Inspector Population

- (void)populateInspector {
    NSArray<InspectorGroup *> *groups = [self buildModelPropertyGroups];
    [_inspectorView setGroups:groups];
    [self appendLog:@"Populated inspector with sample model properties.\n"];
}

- (NSArray<InspectorGroup *> *)buildModelPropertyGroups {
    // General group
    InspectorGroup *general = [InspectorGroup groupWithTitle:@"General"
                                                  identifier:@"general"
                                                  properties:@[
        [InspectorProperty textPropertyWithId:@"name" label:@"Name" value:@"Mega Tree 1"],
        [InspectorProperty choicePropertyWithId:@"type" label:@"Type"
                                        choices:@[@"Single Line", @"Matrix", @"Arch", @"Custom", @"Sphere", @"Cube"]
                                  selectedIndex:0],
        [InspectorProperty textPropertyWithId:@"description" label:@"Description" value:@"Front yard mega tree"],
    ]];

    // Position group
    InspectorGroup *position = [InspectorGroup groupWithTitle:@"Position"
                                                   identifier:@"position"
                                                   properties:@[
        [InspectorProperty sliderPropertyWithId:@"posX" label:@"X" value:50.0 min:-100.0 max:100.0],
        [InspectorProperty sliderPropertyWithId:@"posY" label:@"Y" value:0.0 min:-100.0 max:100.0],
        [InspectorProperty sliderPropertyWithId:@"posZ" label:@"Z" value:0.0 min:-100.0 max:100.0],
        [InspectorProperty sliderPropertyWithId:@"rotX" label:@"Rotate X" value:0.0 min:0.0 max:360.0],
        [InspectorProperty sliderPropertyWithId:@"rotY" label:@"Rotate Y" value:0.0 min:0.0 max:360.0],
        [InspectorProperty sliderPropertyWithId:@"rotZ" label:@"Rotate Z" value:0.0 min:0.0 max:360.0],
        [InspectorProperty sliderPropertyWithId:@"scaleX" label:@"Scale X" value:1.0 min:0.1 max:10.0],
        [InspectorProperty sliderPropertyWithId:@"scaleY" label:@"Scale Y" value:1.0 min:0.1 max:10.0],
        [InspectorProperty sliderPropertyWithId:@"scaleZ" label:@"Scale Z" value:1.0 min:0.1 max:10.0],
    ]];

    // Controller group
    InspectorGroup *controller = [InspectorGroup groupWithTitle:@"Controller"
                                                     identifier:@"controller"
                                                     properties:@[
        [InspectorProperty choicePropertyWithId:@"controller" label:@"Controller"
                                        choices:@[@"No Controller", @"FPP (192.168.1.10)", @"Falcon F48 (192.168.1.20)", @"ESPixelStick (192.168.1.30)"]
                                  selectedIndex:1],
        [InspectorProperty choicePropertyWithId:@"port" label:@"Port"
                                        choices:@[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8"]
                                  selectedIndex:0],
        [InspectorProperty numberPropertyWithId:@"startChannel" label:@"Start Channel" value:@1],
        [InspectorProperty choicePropertyWithId:@"protocol" label:@"Protocol"
                                        choices:@[@"ws2811", @"ws2812b", @"APA102", @"SK6812", @"TM1814"]
                                  selectedIndex:0],
        [InspectorProperty togglePropertyWithId:@"autoSize" label:@"Auto Size" value:YES],
    ]];

    // Appearance group
    InspectorGroup *appearance = [InspectorGroup groupWithTitle:@"Appearance"
                                                    identifier:@"appearance"
                                                    properties:@[
        [InspectorProperty colorPropertyWithId:@"color" label:@"Color"
                                         color:[NSColor colorWithRed:0.2 green:0.8 blue:0.3 alpha:1.0]],
        [InspectorProperty sliderPropertyWithId:@"brightness" label:@"Brightness" value:100.0 min:0.0 max:100.0],
        [InspectorProperty sliderPropertyWithId:@"gamma" label:@"Gamma" value:2.2 min:0.1 max:5.0],
        [InspectorProperty choicePropertyWithId:@"colorOrder" label:@"Color Order"
                                        choices:@[@"RGB", @"RBG", @"GRB", @"GBR", @"BRG", @"BGR"]
                                  selectedIndex:0],
        [InspectorProperty togglePropertyWithId:@"active" label:@"Active" value:YES],
    ]];

    // Strings group
    InspectorGroup *strings = [InspectorGroup groupWithTitle:@"Strings"
                                                  identifier:@"strings"
                                                  properties:@[
        [InspectorProperty numberPropertyWithId:@"stringCount" label:@"String Count" value:@16],
        [InspectorProperty numberPropertyWithId:@"nodesPerString" label:@"Nodes/String" value:@100],
        [InspectorProperty numberPropertyWithId:@"strandsPerString" label:@"Strands/String" value:@1],
        [InspectorProperty choicePropertyWithId:@"startSide" label:@"Start Side"
                                        choices:@[@"Bottom", @"Top", @"Left", @"Right"]
                                  selectedIndex:0],
        [InspectorProperty choicePropertyWithId:@"direction" label:@"Direction"
                                        choices:@[@"Up", @"Down"]
                                  selectedIndex:0],
    ]];

    // Files group
    InspectorGroup *files = [InspectorGroup groupWithTitle:@"Files"
                                                identifier:@"files"
                                                properties:@[
        [InspectorProperty pathPropertyWithId:@"customModel" label:@"Custom Model"
                                         path:@""
                                allowedTypes:@[@"xmodel", @"xml"]],
        [InspectorProperty pathPropertyWithId:@"faceDefinition" label:@"Face Def"
                                         path:@""
                                allowedTypes:@[@"json", @"xml"]],
    ]];

    return @[general, position, controller, appearance, strings, files];
}

#pragma mark - InspectorViewDelegate

- (void)inspectorView:(InspectorView *)inspectorView
    didChangeProperty:(InspectorProperty *)property
              inGroup:(InspectorGroup *)group {
    NSString *valueStr;
    if ([property.value isKindOfClass:[NSColor class]]) {
        NSColor *c = (NSColor *)property.value;
        NSColor *rgb = [c colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        if (rgb) {
            valueStr = [NSString stringWithFormat:@"(%.2f, %.2f, %.2f)",
                        rgb.redComponent, rgb.greenComponent, rgb.blueComponent];
        } else {
            valueStr = [c description];
        }
    } else {
        valueStr = [property.value description];
    }
    NSString *msg = [NSString stringWithFormat:@"[%@] %@ = %@\n",
                     group.title, property.identifier, valueStr];
    [self appendLog:msg];
}

#pragma mark - Toolbar Actions

- (void)expandAll:(id)sender {
    [_inspectorView expandAll];
    [self appendLog:@"Expanded all groups.\n"];
}

- (void)collapseAll:(id)sender {
    [_inspectorView collapseAll];
    [self appendLog:@"Collapsed all groups.\n"];
}

- (void)readAllValues:(id)sender {
    NSDictionary *values = [_inspectorView allValues];
    [self appendLog:@"\n--- All Property Values ---\n"];
    NSArray *sortedKeys = [values.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sortedKeys) {
        id val = values[key];
        NSString *valueStr;
        if ([val isKindOfClass:[NSColor class]]) {
            NSColor *c = (NSColor *)val;
            NSColor *rgb = [c colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            if (rgb) {
                valueStr = [NSString stringWithFormat:@"(%.2f, %.2f, %.2f)",
                            rgb.redComponent, rgb.greenComponent, rgb.blueComponent];
            } else {
                valueStr = [c description];
            }
        } else {
            valueStr = [val description];
        }
        [self appendLog:[NSString stringWithFormat:@"  %@ = %@\n", key, valueStr]];
    }
    [self appendLog:@"--- End ---\n\n"];
}

- (void)runStressTest:(id)sender {
    [self appendLog:@"\n--- Stress Test: Building 50+ properties ---\n"];

    NSDate *start = [NSDate date];

    NSMutableArray<InspectorGroup *> *groups = [NSMutableArray array];

    // Keep the standard groups
    [groups addObjectsFromArray:[self buildModelPropertyGroups]];

    // Add stress test groups with many properties
    for (int g = 0; g < 5; g++) {
        NSMutableArray<InspectorProperty *> *props = [NSMutableArray array];
        for (int p = 0; p < 12; p++) {
            NSString *pid = [NSString stringWithFormat:@"stress_%d_%d", g, p];
            NSString *label = [NSString stringWithFormat:@"Param %d", p + 1];
            InspectorProperty *prop;
            switch (p % 6) {
                case 0:
                    prop = [InspectorProperty textPropertyWithId:pid label:label
                                                           value:[NSString stringWithFormat:@"Value %d", p]];
                    break;
                case 1:
                    prop = [InspectorProperty sliderPropertyWithId:pid label:label
                                                             value:50.0 min:0.0 max:100.0];
                    break;
                case 2:
                    prop = [InspectorProperty choicePropertyWithId:pid label:label
                                                           choices:@[@"A", @"B", @"C", @"D"]
                                                     selectedIndex:0];
                    break;
                case 3:
                    prop = [InspectorProperty togglePropertyWithId:pid label:label value:YES];
                    break;
                case 4:
                    prop = [InspectorProperty colorPropertyWithId:pid label:label
                                                            color:[NSColor colorWithHue:(p * 0.08)
                                                                             saturation:0.8
                                                                             brightness:0.9
                                                                                  alpha:1.0]];
                    break;
                case 5:
                    prop = [InspectorProperty numberPropertyWithId:pid label:label value:@(p * 10)];
                    break;
            }
            [props addObject:prop];
        }
        NSString *title = [NSString stringWithFormat:@"Stress Group %d", g + 1];
        NSString *gid = [NSString stringWithFormat:@"stress_%d", g];
        InspectorGroup *group = [InspectorGroup groupWithTitle:title identifier:gid properties:props];
        [groups addObject:group];
    }

    [_inspectorView setGroups:groups];

    NSTimeInterval elapsed = -[start timeIntervalSinceNow];

    NSInteger totalProps = 0;
    for (InspectorGroup *g in groups) {
        totalProps += g.properties.count;
    }

    [self appendLog:[NSString stringWithFormat:@"Built %ld groups with %ld total properties in %.1f ms\n",
                     (long)groups.count, (long)totalProps, elapsed * 1000.0]];
    [self appendLog:@"--- Stress Test Complete ---\n\n"];
}

#pragma mark - Logging

- (void)appendLog:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAttributedString *attr = [[NSAttributedString alloc]
            initWithString:message
                attributes:@{
                    NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightRegular],
                    NSForegroundColorAttributeName: [NSColor labelColor],
                }];
        [self.logView.textStorage appendAttributedString:attr];
        [self.logView scrollToEndOfDocument:nil];
    });
}

@end
