/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLSongRegionEditPopover.h"

@interface XLSongRegionEditPopover () <NSTextFieldDelegate>
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSColorWell *colorWell;
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, copy) XLSongRegionEditCompletion completion;
@end

@implementation XLSongRegionEditPopover

+ (void)showRelativeToRect:(NSRect)rect
                    ofView:(NSView *)view
                  withName:(NSString *)name
                     color:(NSColor *)color
                completion:(XLSongRegionEditCompletion)completion
{
    XLSongRegionEditPopover *vc = [[XLSongRegionEditPopover alloc] init];
    vc.completion = completion;

    // Build the content view
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 220, 70)];

    // Name label + field
    NSTextField *label = [NSTextField labelWithString:@"Name:"];
    label.frame = NSMakeRect(10, 40, 40, 20);
    label.font = [NSFont systemFontOfSize:11];
    [content addSubview:label];

    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(52, 38, 120, 24)];
    nameField.stringValue = name ?: @"";
    nameField.font = [NSFont systemFontOfSize:12];
    nameField.bezelStyle = NSTextFieldRoundedBezel;
    nameField.delegate = vc;
    [content addSubview:nameField];
    vc.nameField = nameField;

    // Color well
    NSColorWell *colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(180, 38, 30, 24)];
    colorWell.color = color ?: [NSColor blueColor];
    if (@available(macOS 13.0, *)) {
        colorWell.colorWellStyle = NSColorWellStyleMinimal;
    }
    [content addSubview:colorWell];
    vc.colorWell = colorWell;

    // Done button
    NSButton *doneBtn = [[NSButton alloc] initWithFrame:NSMakeRect(140, 6, 70, 26)];
    doneBtn.title = @"Done";
    doneBtn.bezelStyle = NSBezelStyleRounded;
    doneBtn.target = vc;
    doneBtn.action = @selector(donePressed:);
    doneBtn.keyEquivalent = @"\r";
    [content addSubview:doneBtn];

    vc.view = content;

    // Show popover
    NSPopover *popover = [[NSPopover alloc] init];
    popover.contentViewController = vc;
    popover.behavior = NSPopoverBehaviorTransient;
    popover.contentSize = NSMakeSize(220, 70);
    vc.popover = popover;

    [popover showRelativeToRect:rect ofView:view preferredEdge:NSRectEdgeMaxY];

    // Make the name field first responder
    dispatch_async(dispatch_get_main_queue(), ^{
        [nameField.window makeFirstResponder:nameField];
    });
}

- (void)donePressed:(id)sender {
    [self dismissWithCompletion];
}

- (void)dismissWithCompletion {
    NSString *name = self.nameField.stringValue;
    NSColor *color = self.colorWell.color;
    XLSongRegionEditCompletion completion = self.completion;

    [self.popover close];
    self.popover = nil;

    if (completion) {
        completion(name, color);
    }
}

@end
