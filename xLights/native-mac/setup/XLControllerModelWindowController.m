/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLControllerModelWindowController.h"
#import "../XLEngineBridge.h"
#import <string.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NSString * const XLControllerModelDragType = @"org.xlights.controllermodel.name";

#pragma mark - Drawing Constants

static const CGFloat kPortLabelWidth     = 120.0;
static const CGFloat kModelBoxWidth      = 130.0;
static const CGFloat kModelBoxHeight     = 50.0;
static const CGFloat kPortRowHeight      = 60.0;
static const CGFloat kVerticalGap        = 6.0;
static const CGFloat kHorizontalGap      = 6.0;
static const CGFloat kTopMargin          = 10.0;
static const CGFloat kLeftMargin         = 10.0;
static const CGFloat kCornerRadius       = 4.0;
static const CGFloat kFirstModelGap      = 30.0;

#pragma mark - Colors

static NSColor *PixelPortColor(void)       { return [NSColor colorWithRed:0.0 green:0.8 blue:0.9 alpha:1.0]; }
static NSColor *SerialPortColor(void)      { return [NSColor colorWithRed:0.0 green:0.75 blue:0.0 alpha:1.0]; }
static NSColor *ModelBoxColor(void)        { return [NSColor colorWithRed:0.53 green:0.81 blue:1.0 alpha:1.0]; }
static NSColor *ModelBoxDarkColor(void)    { return [NSColor colorWithRed:0.25 green:0.39 blue:0.55 alpha:1.0]; }
static NSColor *InvalidColor(void)         { return [NSColor colorWithRed:1.0 green:0.52 blue:0.52 alpha:1.0]; }
static NSColor *DropTargetColor(void)      { return [NSColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.3]; }
static NSColor *HoverOutlineColor(void)    { return [NSColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:1.0]; }

static NSColor *SmartRemoteColor(int sr) {
    switch (sr) {
        case 1: return [NSColor colorWithRed:0.53 green:0.81 blue:1.0 alpha:1.0];   // A - blue
        case 2: return [NSColor colorWithRed:0.6 green:1.0 blue:0.57 alpha:1.0];    // B - green
        case 3: return [NSColor colorWithRed:1.0 green:0.79 blue:0.59 alpha:1.0];   // C - orange
        case 4: return [NSColor colorWithRed:0.72 green:0.59 blue:1.0 alpha:1.0];   // D - purple
        case 5: return [NSColor colorWithRed:1.0 green:0.52 blue:1.0 alpha:1.0];    // E - pink
        case 6: return [NSColor colorWithRed:0.5 green:1.0 blue:1.0 alpha:1.0];     // F - cyan
        default: return ModelBoxColor();
    }
}

static BOOL IsDarkAppearance(void) {
    if (@available(macOS 10.14, *)) {
        NSString *name = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
                          @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        return [name isEqualToString:NSAppearanceNameDarkAqua];
    }
    return NO;
}

#pragma mark - Helper

static void SafeCopy(char *dest, size_t destSize, NSString *src) {
    if (!src) { dest[0] = '\0'; return; }
    const char *utf8 = [src UTF8String];
    if (utf8) {
        strncpy(dest, utf8, destSize - 1);
        dest[destSize - 1] = '\0';
    } else {
        dest[0] = '\0';
    }
}

static NSString *CStr(const char *c) {
    if (!c || c[0] == '\0') return @"";
    return [NSString stringWithUTF8String:c];
}

#pragma mark - XLCMModelListEntry

@implementation XLCMModelListEntry
@end

#pragma mark - XLControllerPortLayoutView

@interface XLControllerPortLayoutView ()
@property (nonatomic, assign) NSInteger hoverPortIndex;
@property (nonatomic, assign) NSInteger hoverModelIndex;
@property (nonatomic, assign) NSInteger dropTargetPortIndex;
@property (nonatomic, assign) NSPoint lastMousePoint;
@end

@implementation XLControllerPortLayoutView {
    XLCMPortRow *_ports;
    int _portCount;
    int _maxPorts;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _boxScale = 1.0;
        _hoverPortIndex = -1;
        _hoverModelIndex = -1;
        _dropTargetPortIndex = -1;
        _maxPorts = 128;
        _ports = calloc(_maxPorts, sizeof(XLCMPortRow));
        _portCount = 0;

        [self registerForDraggedTypes:@[XLControllerModelDragType]];

        NSTrackingArea *tracking = [[NSTrackingArea alloc]
            initWithRect:NSZeroRect
                 options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                         NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
                   owner:self
                userInfo:nil];
        [self addTrackingArea:tracking];
    }
    return self;
}

- (void)dealloc {
    if (_ports) {
        free(_ports);
        _ports = NULL;
    }
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

#pragma mark - Data Loading

- (void)reloadPortLayout {
    _portCount = 0;
    if (!_controllerName || !_engineBridge) {
        [self setNeedsDisplay:YES];
        return;
    }

    NSArray<NSDictionary *> *ports = [_engineBridge getPortsForController:_controllerName];
    if (!ports || ports.count == 0) {
        // Generate from capabilities
        NSDictionary *caps = [_engineBridge getControllerCapabilities:_controllerName];
        int pixelPorts = caps ? [caps[@"maxPixelPorts"] intValue] : 16;
        int serialPorts = caps ? [caps[@"maxSerialPorts"] intValue] : 4;
        if (pixelPorts == 0) pixelPorts = 16;
        if (serialPorts == 0) serialPorts = 4;

        for (int i = 0; i < pixelPorts && _portCount < _maxPorts; i++) {
            XLCMPortRow *row = &_ports[_portCount];
            memset(row, 0, sizeof(XLCMPortRow));
            row->portNumber = i + 1;
            row->portType = 0; // pixel
            SafeCopy(row->protocol, 64, @"ws2811");
            row->maxChannels = 9999;
            _portCount++;
        }
        for (int i = 0; i < serialPorts && _portCount < _maxPorts; i++) {
            XLCMPortRow *row = &_ports[_portCount];
            memset(row, 0, sizeof(XLCMPortRow));
            row->portNumber = i + 1;
            row->portType = 1; // serial
            SafeCopy(row->protocol, 64, @"DMX");
            row->maxChannels = 512;
            _portCount++;
        }
    } else {
        for (NSDictionary *portDict in ports) {
            if (_portCount >= _maxPorts) break;

            XLCMPortRow *row = &_ports[_portCount];
            memset(row, 0, sizeof(XLCMPortRow));

            row->portNumber = [portDict[@"port"] intValue];
            SafeCopy(row->protocol, 64, portDict[@"protocol"]);
            row->totalChannels = [portDict[@"channelCount"] intValue];

            NSString *protocol = portDict[@"protocol"];
            if ([protocol isEqualToString:@"DMX"] || [protocol isEqualToString:@"LOR"] ||
                [protocol isEqualToString:@"Renard"] || [protocol isEqualToString:@"OpenDMX"]) {
                row->portType = 1;
                row->maxChannels = 512;
            } else {
                row->portType = 0;
                row->maxChannels = 999999;
            }

            // Populate models assigned to this port
            // The bridge getPortsForController returns port-level data.
            // For model assignments, look at the models themselves.
            _portCount++;
        }
    }

    // Populate model assignments by scanning all models
    [self populateModelAssignments];

    // Resize to fit content
    NSSize newSize = NSMakeSize(MAX(self.contentWidth, self.superview.bounds.size.width),
                                MAX(self.contentHeight, self.superview.bounds.size.height));
    [self setFrameSize:newSize];
    [self setNeedsDisplay:YES];
}

- (void)populateModelAssignments {
    if (!_engineBridge) return;

    // Clear existing model assignments
    for (int i = 0; i < _portCount; i++) {
        _ports[i].modelCount = 0;
    }

    NSArray<NSString *> *modelNames = [_engineBridge getModelNamesExcludingGroups];
    for (NSString *modelName in modelNames) {
        NSDictionary *info = [_engineBridge getModelInfo:modelName];
        if (!info) continue;

        NSString *controller = info[@"controller"];
        if (!controller || ![controller isEqualToString:_controllerName]) continue;

        NSNumber *portNum = info[@"port"];
        if (!portNum) continue;

        int port = portNum.intValue;

        // Find matching port row
        for (int i = 0; i < _portCount; i++) {
            if (_ports[i].portNumber == port && _ports[i].modelCount < XL_CM_MAX_MODELS_PER_PORT) {
                XLCMModelEntry *entry = &_ports[i].models[_ports[i].modelCount];
                memset(entry, 0, sizeof(XLCMModelEntry));
                SafeCopy(entry->modelName, 64, modelName);
                entry->channelCount = [info[@"channelCount"] intValue];
                entry->pixelCount = [info[@"nodeCount"] intValue];
                entry->startChannel = [info[@"startChannel"] intValue];
                entry->smartRemote = [info[@"smartRemote"] intValue];
                entry->isMain = YES;
                _ports[i].modelCount++;
                _ports[i].totalChannels += entry->channelCount;
                break;
            }
        }
    }
}

#pragma mark - Geometry

- (CGFloat)scaledBoxWidth {
    return kModelBoxWidth * _boxScale;
}

- (CGFloat)scaledBoxHeight {
    return kModelBoxHeight * _boxScale;
}

- (CGFloat)scaledRowHeight {
    return MAX(kPortRowHeight * _boxScale, [self scaledBoxHeight] + 2 * kVerticalGap);
}

- (CGFloat)contentHeight {
    return kTopMargin + _portCount * ([self scaledRowHeight] + kVerticalGap) + kTopMargin;
}

- (CGFloat)contentWidth {
    CGFloat maxW = kLeftMargin + kPortLabelWidth * _boxScale + kFirstModelGap;
    for (int i = 0; i < _portCount; i++) {
        CGFloat rowW = kLeftMargin + kPortLabelWidth * _boxScale + kFirstModelGap +
            _ports[i].modelCount * ([self scaledBoxWidth] + kHorizontalGap) + kLeftMargin;
        if (rowW > maxW) maxW = rowW;
    }
    return MAX(maxW, 800.0);
}

- (NSRect)portLabelRectForRow:(int)row {
    CGFloat y = kTopMargin + row * ([self scaledRowHeight] + kVerticalGap);
    return NSMakeRect(kLeftMargin, y, kPortLabelWidth * _boxScale, [self scaledRowHeight]);
}

- (NSRect)modelRectForRow:(int)row modelIndex:(int)modelIdx {
    CGFloat y = kTopMargin + row * ([self scaledRowHeight] + kVerticalGap);
    CGFloat x = kLeftMargin + kPortLabelWidth * _boxScale + kFirstModelGap +
        modelIdx * ([self scaledBoxWidth] + kHorizontalGap);
    CGFloat boxY = y + ([self scaledRowHeight] - [self scaledBoxHeight]) / 2.0;
    return NSMakeRect(x, boxY, [self scaledBoxWidth], [self scaledBoxHeight]);
}

- (NSRect)dropZoneRectForRow:(int)row {
    CGFloat y = kTopMargin + row * ([self scaledRowHeight] + kVerticalGap);
    CGFloat x = kLeftMargin + kPortLabelWidth * _boxScale + kFirstModelGap +
        _ports[row].modelCount * ([self scaledBoxWidth] + kHorizontalGap);
    CGFloat boxY = y + ([self scaledRowHeight] - [self scaledBoxHeight]) / 2.0;
    return NSMakeRect(x, boxY, [self scaledBoxWidth], [self scaledBoxHeight]);
}

#pragma mark - Hit Testing

- (NSInteger)portRowAtPoint:(NSPoint)point {
    for (int i = 0; i < _portCount; i++) {
        CGFloat y = kTopMargin + i * ([self scaledRowHeight] + kVerticalGap);
        if (point.y >= y && point.y < y + [self scaledRowHeight]) {
            return i;
        }
    }
    return -1;
}

- (NSInteger)modelIndexAtPoint:(NSPoint)point inRow:(NSInteger)row {
    if (row < 0 || row >= _portCount) return -1;
    for (int j = 0; j < _ports[row].modelCount; j++) {
        NSRect rect = [self modelRectForRow:(int)row modelIndex:j];
        if (NSPointInRect(point, rect)) {
            return j;
        }
    }
    return -1;
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    BOOL dark = IsDarkAppearance();
    NSColor *bgColor = dark ? [NSColor colorWithWhite:0.15 alpha:1.0] : [NSColor colorWithWhite:0.95 alpha:1.0];
    [bgColor setFill];
    NSRectFill(dirtyRect);

    NSColor *textColor = dark ? [NSColor whiteColor] : [NSColor blackColor];
    NSColor *portTextColor = dark ? [NSColor colorWithWhite:0.9 alpha:1.0] : [NSColor colorWithWhite:0.1 alpha:1.0];

    NSDictionary *portLabelAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:11.0 * _boxScale],
        NSForegroundColorAttributeName: portTextColor
    };
    NSDictionary *modelNameAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10.0 * _boxScale],
        NSForegroundColorAttributeName: textColor
    };
    NSDictionary *modelDetailAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9.0 * _boxScale],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };

    for (int i = 0; i < _portCount; i++) {
        XLCMPortRow *port = &_ports[i];

        // Draw port label background
        NSRect labelRect = [self portLabelRectForRow:i];
        NSColor *portColor = (port->portType == 0) ? PixelPortColor() : SerialPortColor();
        if (port->isInvalid) portColor = InvalidColor();

        NSBezierPath *labelPath = [NSBezierPath bezierPathWithRoundedRect:labelRect
                                                                  xRadius:kCornerRadius
                                                                  yRadius:kCornerRadius];
        [[portColor colorWithAlphaComponent:0.3] setFill];
        [labelPath fill];
        [portColor setStroke];
        [labelPath setLineWidth:1.5];
        [labelPath stroke];

        // Port label text
        NSString *portTypeStr = (port->portType == 0) ? @"Pixel" : @"Serial";
        NSString *labelText = [NSString stringWithFormat:@"%@ %d", portTypeStr, port->portNumber];
        NSSize labelSize = [labelText sizeWithAttributes:portLabelAttrs];
        NSPoint labelPt = NSMakePoint(labelRect.origin.x + 6,
                                      labelRect.origin.y + (labelRect.size.height - labelSize.height) / 2.0 - 6);
        [labelText drawAtPoint:labelPt withAttributes:portLabelAttrs];

        // Protocol and channel info below port label
        NSString *protoText = [NSString stringWithFormat:@"%@ - %d ch",
                               CStr(port->protocol), port->totalChannels];
        [protoText drawAtPoint:NSMakePoint(labelPt.x, labelPt.y + labelSize.height + 2)
                withAttributes:modelDetailAttrs];

        // Draw models on this port
        for (int j = 0; j < port->modelCount; j++) {
            XLCMModelEntry *model = &port->models[j];
            NSRect modelRect = [self modelRectForRow:i modelIndex:j];

            // Model box color based on smart remote
            NSColor *boxColor;
            if (model->smartRemote > 0) {
                boxColor = SmartRemoteColor(model->smartRemote);
            } else {
                boxColor = dark ? ModelBoxDarkColor() : ModelBoxColor();
            }

            NSBezierPath *boxPath = [NSBezierPath bezierPathWithRoundedRect:modelRect
                                                                    xRadius:kCornerRadius
                                                                    yRadius:kCornerRadius];
            [boxColor setFill];
            [boxPath fill];

            // Hover highlight
            if (i == _hoverPortIndex && j == _hoverModelIndex) {
                [HoverOutlineColor() setStroke];
                [boxPath setLineWidth:2.5];
                [boxPath stroke];
            } else {
                [[NSColor separatorColor] setStroke];
                [boxPath setLineWidth:0.5];
                [boxPath stroke];
            }

            // Model name
            NSString *name = CStr(model->modelName);
            NSRect textRect = NSInsetRect(modelRect, 4, 3);
            [name drawInRect:textRect withAttributes:modelNameAttrs];

            // Pixel/channel info
            NSString *detail;
            if (port->portType == 0 && model->pixelCount > 0) {
                detail = [NSString stringWithFormat:@"%d px / %d ch", model->pixelCount, model->channelCount];
            } else {
                detail = [NSString stringWithFormat:@"%d ch", model->channelCount];
            }
            NSRect detailRect = NSMakeRect(textRect.origin.x,
                                           textRect.origin.y + 14 * _boxScale,
                                           textRect.size.width, textRect.size.height - 14 * _boxScale);
            [detail drawInRect:detailRect withAttributes:modelDetailAttrs];

            // Smart remote label
            if (model->smartRemote > 0) {
                NSString *srLabel = [NSString stringWithFormat:@"SR:%c", (char)('A' + model->smartRemote - 1)];
                NSDictionary *srAttrs = @{
                    NSFontAttributeName: [NSFont boldSystemFontOfSize:8.0 * _boxScale],
                    NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
                };
                NSSize srSize = [srLabel sizeWithAttributes:srAttrs];
                NSPoint srPt = NSMakePoint(NSMaxX(modelRect) - srSize.width - 4,
                                           NSMaxY(modelRect) - srSize.height - 2);
                [srLabel drawAtPoint:srPt withAttributes:srAttrs];
            }
        }

        // Draw drop target zone if dragging over this port
        if (i == _dropTargetPortIndex) {
            NSRect dropRect = [self dropZoneRectForRow:i];
            NSBezierPath *dropPath = [NSBezierPath bezierPathWithRoundedRect:dropRect
                                                                     xRadius:kCornerRadius
                                                                     yRadius:kCornerRadius];
            [DropTargetColor() setFill];
            [dropPath fill];
            [[NSColor systemBlueColor] setStroke];
            CGFloat dashes[] = {4, 4};
            [dropPath setLineDash:dashes count:2 phase:0];
            [dropPath setLineWidth:1.5];
            [dropPath stroke];

            NSString *dropText = @"Drop here";
            NSDictionary *dropAttrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:10.0],
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
            };
            NSSize dropSize = [dropText sizeWithAttributes:dropAttrs];
            NSPoint dropPt = NSMakePoint(dropRect.origin.x + (dropRect.size.width - dropSize.width) / 2,
                                         dropRect.origin.y + (dropRect.size.height - dropSize.height) / 2);
            [dropText drawAtPoint:dropPt withAttributes:dropAttrs];
        }
    }

    // Empty state
    if (_portCount == 0) {
        NSString *emptyText = _controllerName ?
            @"No ports configured for this controller." :
            @"Select a controller to visualize.";
        NSDictionary *emptyAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:14.0],
            NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
        };
        NSSize emptySize = [emptyText sizeWithAttributes:emptyAttrs];
        NSPoint emptyPt = NSMakePoint((self.bounds.size.width - emptySize.width) / 2,
                                      (self.bounds.size.height - emptySize.height) / 2);
        [emptyText drawAtPoint:emptyPt withAttributes:emptyAttrs];
    }
}

#pragma mark - Mouse Tracking

- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    _lastMousePoint = point;

    NSInteger newPort = [self portRowAtPoint:point];
    NSInteger newModel = -1;
    if (newPort >= 0) {
        newModel = [self modelIndexAtPoint:point inRow:newPort];
    }

    if (newPort != _hoverPortIndex || newModel != _hoverModelIndex) {
        _hoverPortIndex = newPort;
        _hoverModelIndex = newModel;
        [self setNeedsDisplay:YES];

        // Update tooltip
        if (newPort >= 0 && newModel >= 0) {
            XLCMModelEntry *entry = &_ports[newPort].models[newModel];
            self.toolTip = [NSString stringWithFormat:@"%@ - %d channels, %d pixels\nStart Ch: %d",
                            CStr(entry->modelName), entry->channelCount, entry->pixelCount, entry->startChannel];
        } else if (newPort >= 0) {
            XLCMPortRow *port = &_ports[newPort];
            self.toolTip = [NSString stringWithFormat:@"%s Port %d - %d channels, %d models",
                            port->portType == 0 ? "Pixel" : "Serial",
                            port->portNumber, port->totalChannels, port->modelCount];
        } else {
            self.toolTip = nil;
        }
    }
}

- (void)mouseExited:(NSEvent *)event {
    _hoverPortIndex = -1;
    _hoverModelIndex = -1;
    [self setNeedsDisplay:YES];
}

#pragma mark - Mouse Down (Drag Start)

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger portRow = [self portRowAtPoint:point];
    if (portRow < 0) return;

    NSInteger modelIdx = [self modelIndexAtPoint:point inRow:portRow];
    if (modelIdx < 0) return;

    // Start drag
    XLCMModelEntry *entry = &_ports[portRow].models[modelIdx];
    NSString *modelName = CStr(entry->modelName);

    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setString:modelName forType:XLControllerModelDragType];

    NSDraggingItem *dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:pbItem];
    NSRect modelRect = [self modelRectForRow:(int)portRow modelIndex:(int)modelIdx];
    [dragItem setDraggingFrame:modelRect contents:[self imageForModelEntry:entry]];

    [self beginDraggingSessionWithItems:@[dragItem] event:event source:self];
}

- (NSImage *)imageForModelEntry:(XLCMModelEntry *)entry {
    NSSize size = NSMakeSize([self scaledBoxWidth], [self scaledBoxHeight]);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];

    NSColor *boxColor = entry->smartRemote > 0 ? SmartRemoteColor(entry->smartRemote) : ModelBoxColor();
    [boxColor setFill];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, size.width, size.height)
                                                         xRadius:kCornerRadius yRadius:kCornerRadius];
    [path fill];

    NSString *name = CStr(entry->modelName);
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10.0],
        NSForegroundColorAttributeName: [NSColor blackColor]
    };
    [name drawInRect:NSInsetRect(NSMakeRect(0, 0, size.width, size.height), 4, 3) withAttributes:attrs];

    [image unlockFocus];
    return image;
}

#pragma mark - NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationMove | NSDragOperationCopy;
}

#pragma mark - NSDraggingDestination

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return [self validateDrop:sender];
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
    NSInteger portRow = [self portRowAtPoint:point];

    if (portRow != _dropTargetPortIndex) {
        _dropTargetPortIndex = portRow;
        [self setNeedsDisplay:YES];
    }

    return [self validateDrop:sender];
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    _dropTargetPortIndex = -1;
    [self setNeedsDisplay:YES];
}

- (NSDragOperation)validateDrop:(id<NSDraggingInfo>)sender {
    NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
    NSInteger portRow = [self portRowAtPoint:point];
    if (portRow >= 0 && portRow < _portCount) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    _dropTargetPortIndex = -1;

    NSPasteboardItem *item = sender.draggingPasteboard.pasteboardItems.firstObject;
    NSString *modelName = [item stringForType:XLControllerModelDragType];
    if (!modelName) return NO;

    NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
    NSInteger portRow = [self portRowAtPoint:point];
    if (portRow < 0 || portRow >= _portCount) return NO;

    XLCMPortRow *port = &_ports[portRow];

    // Assign model to port via engine bridge
    BOOL success = [_engineBridge assignModel:modelName
                                 toController:_controllerName
                                         port:port->portNumber];

    if (success) {
        // Add to local data
        if (port->modelCount < XL_CM_MAX_MODELS_PER_PORT) {
            XLCMModelEntry *entry = &port->models[port->modelCount];
            memset(entry, 0, sizeof(XLCMModelEntry));
            SafeCopy(entry->modelName, 64, modelName);

            NSDictionary *modelInfo = [_engineBridge getModelInfo:modelName];
            if (modelInfo) {
                entry->channelCount = [modelInfo[@"channelCount"] intValue];
                entry->pixelCount = [modelInfo[@"nodeCount"] intValue];
                entry->startChannel = [modelInfo[@"startChannel"] intValue];
                entry->smartRemote = [modelInfo[@"smartRemote"] intValue];
            }
            entry->isMain = YES;
            port->modelCount++;
            port->totalChannels += entry->channelCount;
        }
    }

    [self setNeedsDisplay:YES];

    // Notify parent to refresh model list
    [[NSNotificationCenter defaultCenter] postNotificationName:@"XLControllerModelLayoutChanged" object:self];

    return success;
}

#pragma mark - Right-Click Context Menu

- (void)rightMouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger portRow = [self portRowAtPoint:point];
    if (portRow < 0) return;

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Port Actions"];

    NSInteger modelIdx = [self modelIndexAtPoint:point inRow:portRow];

    if (modelIdx >= 0) {
        // Model context menu
        XLCMModelEntry *entry = &_ports[portRow].models[modelIdx];
        NSString *modelName = CStr(entry->modelName);

        NSMenuItem *nameItem = [menu addItemWithTitle:modelName action:nil keyEquivalent:@""];
        nameItem.enabled = NO;
        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *removeItem = [menu addItemWithTitle:@"Remove from Port"
                                                 action:@selector(contextRemoveModel:) keyEquivalent:@""];
        removeItem.tag = portRow * 1000 + modelIdx;
        removeItem.target = self;

        [menu addItem:[NSMenuItem separatorItem]];

        // Smart Remote submenu
        NSMenu *srMenu = [[NSMenu alloc] initWithTitle:@"Smart Remote"];
        NSMenuItem *srNone = [srMenu addItemWithTitle:@"None" action:@selector(contextSetSmartRemote:) keyEquivalent:@""];
        srNone.tag = portRow * 10000 + modelIdx * 100 + 0;
        srNone.target = self;
        srNone.state = (entry->smartRemote == 0) ? NSControlStateValueOn : NSControlStateValueOff;

        for (int sr = 1; sr <= 6; sr++) {
            NSString *title = [NSString stringWithFormat:@"%c", (char)('A' + sr - 1)];
            NSMenuItem *srItem = [srMenu addItemWithTitle:title action:@selector(contextSetSmartRemote:) keyEquivalent:@""];
            srItem.tag = portRow * 10000 + modelIdx * 100 + sr;
            srItem.target = self;
            srItem.state = (entry->smartRemote == sr) ? NSControlStateValueOn : NSControlStateValueOff;
        }

        NSMenuItem *srMenuItem = [[NSMenuItem alloc] initWithTitle:@"Smart Remote" action:nil keyEquivalent:@""];
        srMenuItem.submenu = srMenu;
        [menu addItem:srMenuItem];

    } else {
        // Port context menu
        XLCMPortRow *port = &_ports[portRow];
        NSString *portLabel = [NSString stringWithFormat:@"Port %d", port->portNumber];

        NSMenuItem *nameItem = [menu addItemWithTitle:portLabel action:nil keyEquivalent:@""];
        nameItem.enabled = NO;
        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *removeAllItem = [menu addItemWithTitle:@"Remove All Models"
                                                    action:@selector(contextRemoveAllModels:) keyEquivalent:@""];
        removeAllItem.tag = portRow;
        removeAllItem.target = self;
        removeAllItem.enabled = (port->modelCount > 0);

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *brightnessItem = [menu addItemWithTitle:@"Set Brightness..."
                                                     action:@selector(contextSetBrightness:) keyEquivalent:@""];
        brightnessItem.tag = portRow;
        brightnessItem.target = self;

        NSMenuItem *colorOrderItem = [menu addItemWithTitle:@"Set Color Order..."
                                                     action:@selector(contextSetColorOrder:) keyEquivalent:@""];
        colorOrderItem.tag = portRow;
        colorOrderItem.target = self;

        NSMenuItem *gammaItem = [menu addItemWithTitle:@"Set Gamma..."
                                               action:@selector(contextSetGamma:) keyEquivalent:@""];
        gammaItem.tag = portRow;
        gammaItem.target = self;

        NSMenuItem *nullsItem = [menu addItemWithTitle:@"Set Null Pixels..."
                                                action:@selector(contextSetNullPixels:) keyEquivalent:@""];
        nullsItem.tag = portRow;
        nullsItem.target = self;
    }

    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

#pragma mark - Context Menu Actions

- (void)contextRemoveModel:(NSMenuItem *)sender {
    NSInteger portRow = sender.tag / 1000;
    NSInteger modelIdx = sender.tag % 1000;

    if (portRow < 0 || portRow >= _portCount) return;
    XLCMPortRow *port = &_ports[portRow];
    if (modelIdx < 0 || modelIdx >= port->modelCount) return;

    NSString *modelName = CStr(port->models[modelIdx].modelName);

    // Remove from engine
    [_engineBridge removeModelFromController:_controllerName port:port->portNumber];

    // Remove from local data
    port->totalChannels -= port->models[modelIdx].channelCount;
    for (int j = (int)modelIdx; j < port->modelCount - 1; j++) {
        port->models[j] = port->models[j + 1];
    }
    port->modelCount--;

    [self setNeedsDisplay:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"XLControllerModelLayoutChanged"
                                                        object:self
                                                      userInfo:@{@"removedModel": modelName}];
}

- (void)contextRemoveAllModels:(NSMenuItem *)sender {
    NSInteger portRow = sender.tag;
    if (portRow < 0 || portRow >= _portCount) return;

    XLCMPortRow *port = &_ports[portRow];
    for (int j = 0; j < port->modelCount; j++) {
        [_engineBridge removeModelFromController:_controllerName port:port->portNumber];
    }
    port->modelCount = 0;
    port->totalChannels = 0;

    [self setNeedsDisplay:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"XLControllerModelLayoutChanged" object:self];
}

- (void)contextSetSmartRemote:(NSMenuItem *)sender {
    NSInteger portRow = sender.tag / 10000;
    NSInteger modelIdx = (sender.tag / 100) % 100;
    NSInteger sr = sender.tag % 100;

    if (portRow < 0 || portRow >= _portCount) return;
    XLCMPortRow *port = &_ports[portRow];
    if (modelIdx < 0 || modelIdx >= port->modelCount) return;

    NSString *modelName = CStr(port->models[modelIdx].modelName);
    port->models[modelIdx].smartRemote = (int)sr;

    // Update model property via engine bridge
    [_engineBridge updateModelProperty:modelName key:@"SmartRemote" value:@(sr)];

    [self setNeedsDisplay:YES];
}

- (void)contextSetBrightness:(NSMenuItem *)sender {
    NSInteger portRow = sender.tag;
    if (portRow < 0 || portRow >= _portCount) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Brightness";
    alert.informativeText = [NSString stringWithFormat:@"Enter brightness (0-100) for Port %d:", _ports[portRow].portNumber];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    input.stringValue = @"100";
    alert.accessoryView = input;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            int brightness = MAX(0, MIN(100, input.stringValue.intValue));
            [self->_engineBridge updatePort:self->_controllerName
                                       port:self->_ports[portRow].portNumber
                                 properties:@{@"brightness": @(brightness)}];
        }
    }];
}

- (void)contextSetColorOrder:(NSMenuItem *)sender {
    NSInteger portRow = sender.tag;
    if (portRow < 0 || portRow >= _portCount) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Color Order";

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 24) pullsDown:NO];
    [popup addItemsWithTitles:@[@"RGB", @"RBG", @"GRB", @"GBR", @"BRG", @"BGR", @"RGBW", @"WRGB"]];
    alert.accessoryView = popup;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [self->_engineBridge updatePort:self->_controllerName
                                       port:self->_ports[portRow].portNumber
                                 properties:@{@"colorOrder": popup.selectedItem.title}];
        }
    }];
}

- (void)contextSetGamma:(NSMenuItem *)sender {
    NSInteger portRow = sender.tag;
    if (portRow < 0 || portRow >= _portCount) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Gamma";
    alert.informativeText = [NSString stringWithFormat:@"Enter gamma (0.1-5.0) for Port %d:", _ports[portRow].portNumber];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    input.stringValue = @"1.0";
    alert.accessoryView = input;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            float gamma = MAX(0.1f, MIN(5.0f, input.stringValue.floatValue));
            [self->_engineBridge updatePort:self->_controllerName
                                       port:self->_ports[portRow].portNumber
                                 properties:@{@"gamma": @(gamma)}];
        }
    }];
}

- (void)contextSetNullPixels:(NSMenuItem *)sender {
    NSInteger portRow = sender.tag;
    if (portRow < 0 || portRow >= _portCount) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Null Pixels";
    alert.informativeText = [NSString stringWithFormat:@"Enter null pixel count for Port %d:", _ports[portRow].portNumber];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    input.stringValue = @"0";
    alert.accessoryView = input;

    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            int nulls = MAX(0, input.stringValue.intValue);
            [self->_engineBridge updatePort:self->_controllerName
                                       port:self->_ports[portRow].portNumber
                                 properties:@{@"nullPixelsStart": @(nulls)}];
        }
    }];
}

@end

#pragma mark - ==========================================================
#pragma mark - XLControllerModelWindowController
#pragma mark - ==========================================================

@interface XLControllerModelWindowController ()

@property (nonatomic, copy) NSString *controllerName;
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSScrollView *modelListScrollView;
@property (nonatomic, strong) NSTableView *modelListTableView;
@property (nonatomic, strong) NSScrollView *portLayoutScrollView;
@property (nonatomic, strong) XLControllerPortLayoutView *portLayoutView;
@property (nonatomic, strong) NSView *toolbarView;
@property (nonatomic, strong) NSSlider *scaleSlider;
@property (nonatomic, strong) NSButton *hideOtherControllersCheckbox;
@property (nonatomic, strong) NSTextField *checkTextView;
@property (nonatomic, strong) NSButton *printButton;
@property (nonatomic, strong) NSButton *csvButton;
@property (nonatomic, strong) NSMutableArray<XLCMModelListEntry *> *modelList;
@property (nonatomic, strong) NSMutableArray<XLCMModelListEntry *> *filteredModelList;

@end

@implementation XLControllerModelWindowController

#pragma mark - Initialization

- (instancetype)initWithControllerName:(NSString *)controllerName
                          engineBridge:(XLEngineBridge *)engineBridge {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1100, 700)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:YES];
    window.title = [NSString stringWithFormat:@"Controller Visualiser - %@", controllerName];
    window.minSize = NSMakeSize(700, 400);

    self = [super initWithWindow:window];
    if (self) {
        _controllerName = [controllerName copy];
        _engineBridge = engineBridge;
        _modelList = [NSMutableArray array];
        _filteredModelList = [NSMutableArray array];

        [self setupUI];
        [self loadData];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(layoutChanged:)
                                                     name:@"XLControllerModelLayoutChanged"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI Setup

- (void)setupUI {
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;

    // Main vertical stack: toolbar at top, split view in center, check text at bottom
    _toolbarView = [self createToolbar];
    _splitView = [self createSplitView];
    _checkTextView = [self createCheckTextView];

    _toolbarView.translatesAutoresizingMaskIntoConstraints = NO;
    _splitView.translatesAutoresizingMaskIntoConstraints = NO;
    _checkTextView.translatesAutoresizingMaskIntoConstraints = NO;

    [contentView addSubview:_toolbarView];
    [contentView addSubview:_splitView];
    [contentView addSubview:_checkTextView];

    [NSLayoutConstraint activateConstraints:@[
        [_toolbarView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [_toolbarView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [_toolbarView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [_toolbarView.heightAnchor constraintEqualToConstant:36.0],

        [_splitView.topAnchor constraintEqualToAnchor:_toolbarView.bottomAnchor],
        [_splitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [_splitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [_splitView.bottomAnchor constraintEqualToAnchor:_checkTextView.topAnchor],

        [_checkTextView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [_checkTextView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [_checkTextView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [_checkTextView.heightAnchor constraintEqualToConstant:80.0],
    ]];
}

- (NSView *)createToolbar {
    NSView *toolbar = [[NSView alloc] initWithFrame:NSZeroRect];
    toolbar.wantsLayer = YES;
    toolbar.layer.backgroundColor = CGColorCreateGenericGray(0.18, 1.0);

    // Scale slider
    NSTextField *scaleLabel = [NSTextField labelWithString:@"Box Size:"];
    scaleLabel.font = [NSFont systemFontOfSize:11];
    scaleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _scaleSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _scaleSlider.minValue = 0.5;
    _scaleSlider.maxValue = 3.0;
    _scaleSlider.doubleValue = 1.0;
    _scaleSlider.target = self;
    _scaleSlider.action = @selector(scaleChanged:);
    _scaleSlider.translatesAutoresizingMaskIntoConstraints = NO;

    // Hide other controllers checkbox
    _hideOtherControllersCheckbox = [NSButton checkboxWithTitle:@"Hide models on other controllers"
                                                         target:self
                                                         action:@selector(filterChanged:)];
    _hideOtherControllersCheckbox.font = [NSFont systemFontOfSize:11];
    _hideOtherControllersCheckbox.translatesAutoresizingMaskIntoConstraints = NO;

    // Print button (stub)
    _printButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"printer"
                                                       accessibilityDescription:@"Print"]
                                      target:self
                                      action:@selector(printLayout:)];
    _printButton.bezelStyle = NSBezelStyleSmallSquare;
    _printButton.bordered = NO;
    _printButton.toolTip = @"Print layout";
    _printButton.translatesAutoresizingMaskIntoConstraints = NO;

    // CSV export button (stub)
    _csvButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"tablecells"
                                                     accessibilityDescription:@"Export CSV"]
                                    target:self
                                    action:@selector(exportCSV:)];
    _csvButton.bezelStyle = NSBezelStyleSmallSquare;
    _csvButton.bordered = NO;
    _csvButton.toolTip = @"Export as CSV";
    _csvButton.translatesAutoresizingMaskIntoConstraints = NO;

    [toolbar addSubview:scaleLabel];
    [toolbar addSubview:_scaleSlider];
    [toolbar addSubview:_hideOtherControllersCheckbox];
    [toolbar addSubview:_printButton];
    [toolbar addSubview:_csvButton];

    [NSLayoutConstraint activateConstraints:@[
        [scaleLabel.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:8],
        [scaleLabel.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [_scaleSlider.leadingAnchor constraintEqualToAnchor:scaleLabel.trailingAnchor constant:4],
        [_scaleSlider.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [_scaleSlider.widthAnchor constraintEqualToConstant:120],

        [_hideOtherControllersCheckbox.leadingAnchor constraintEqualToAnchor:_scaleSlider.trailingAnchor constant:16],
        [_hideOtherControllersCheckbox.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [_csvButton.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor constant:-8],
        [_csvButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [_csvButton.widthAnchor constraintEqualToConstant:24],

        [_printButton.trailingAnchor constraintEqualToAnchor:_csvButton.leadingAnchor constant:-4],
        [_printButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [_printButton.widthAnchor constraintEqualToConstant:24],
    ]];

    return toolbar;
}

- (NSSplitView *)createSplitView {
    NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSZeroRect];
    split.vertical = YES;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    split.delegate = self;

    // Left: Model list panel
    NSView *leftPanel = [self createModelListPanel];

    // Right: Port layout panel
    NSView *rightPanel = [self createPortLayoutPanel];

    [split addSubview:leftPanel];
    [split addSubview:rightPanel];

    // Set initial divider position
    [split setPosition:250.0 ofDividerAtIndex:0];

    return split;
}

- (NSView *)createModelListPanel {
    NSView *panel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 500)];
    panel.wantsLayer = YES;

    // Header label
    NSTextField *header = [NSTextField labelWithString:@"Available Models"];
    header.font = [NSFont boldSystemFontOfSize:12];
    header.textColor = [NSColor secondaryLabelColor];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:header];

    // Model table view
    _modelListScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _modelListScrollView.hasVerticalScroller = YES;
    _modelListScrollView.autohidesScrollers = YES;
    _modelListScrollView.borderType = NSNoBorder;
    _modelListScrollView.translatesAutoresizingMaskIntoConstraints = NO;

    _modelListTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _modelListTableView.dataSource = self;
    _modelListTableView.delegate = self;
    _modelListTableView.usesAlternatingRowBackgroundColors = YES;
    _modelListTableView.allowsMultipleSelection = NO;
    _modelListTableView.rowHeight = 28.0;
    _modelListTableView.headerView = nil; // No header - single column list

    if (@available(macOS 11.0, *)) {
        _modelListTableView.style = NSTableViewStyleInset;
    }

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"Name"];
    nameColumn.title = @"Model";
    nameColumn.minWidth = 100;
    nameColumn.width = 200;
    [_modelListTableView addTableColumn:nameColumn];

    NSTableColumn *infoColumn = [[NSTableColumn alloc] initWithIdentifier:@"Info"];
    infoColumn.title = @"Strings";
    infoColumn.minWidth = 40;
    infoColumn.maxWidth = 60;
    infoColumn.width = 50;
    [_modelListTableView addTableColumn:infoColumn];

    _modelListScrollView.documentView = _modelListTableView;

    // Register as drag source
    [_modelListTableView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];

    [panel addSubview:_modelListScrollView];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:panel.topAnchor constant:6],
        [header.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8],
        [header.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8],

        [_modelListScrollView.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:4],
        [_modelListScrollView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [_modelListScrollView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [_modelListScrollView.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor],
    ]];

    return panel;
}

- (NSView *)createPortLayoutPanel {
    NSView *panel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 500)];
    panel.wantsLayer = YES;

    _portLayoutScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _portLayoutScrollView.hasVerticalScroller = YES;
    _portLayoutScrollView.hasHorizontalScroller = YES;
    _portLayoutScrollView.autohidesScrollers = YES;
    _portLayoutScrollView.borderType = NSNoBorder;
    _portLayoutScrollView.translatesAutoresizingMaskIntoConstraints = NO;

    _portLayoutView = [[XLControllerPortLayoutView alloc] initWithFrame:NSMakeRect(0, 0, 800, 1000)];
    _portLayoutView.engineBridge = _engineBridge;
    _portLayoutView.controllerName = _controllerName;

    _portLayoutScrollView.documentView = _portLayoutView;

    [panel addSubview:_portLayoutScrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_portLayoutScrollView.topAnchor constraintEqualToAnchor:panel.topAnchor],
        [_portLayoutScrollView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [_portLayoutScrollView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [_portLayoutScrollView.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor],
    ]];

    return panel;
}

- (NSTextField *)createCheckTextView {
    NSTextField *textView = [[NSTextField alloc] initWithFrame:NSZeroRect];
    textView.editable = NO;
    textView.selectable = YES;
    textView.bordered = YES;
    textView.bezeled = YES;
    textView.bezelStyle = NSTextFieldSquareBezel;
    textView.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    textView.textColor = [NSColor secondaryLabelColor];
    textView.backgroundColor = [NSColor textBackgroundColor];
    textView.lineBreakMode = NSLineBreakByWordWrapping;
    textView.usesSingleLineMode = NO;
    textView.maximumNumberOfLines = 0;
    textView.stringValue = @"";
    return textView;
}

#pragma mark - Data Loading

- (void)loadData {
    [self loadModelList];
    [_portLayoutView reloadPortLayout];
    [self updateCheckText];
}

- (void)loadModelList {
    [_modelList removeAllObjects];

    NSArray<NSString *> *allModels = [_engineBridge getModelNamesExcludingGroups];
    BOOL hideOther = (_hideOtherControllersCheckbox.state == NSControlStateValueOn);

    for (NSString *modelName in allModels) {
        NSDictionary *info = [_engineBridge getModelInfo:modelName];
        if (!info) continue;

        NSString *controller = info[@"controller"];
        BOOL assignedToThis = [controller isEqualToString:_controllerName];

        // Check if model is already on a port of this controller (assigned in layout)
        // If so, skip it from the available list
        NSDictionary *portInfo = info[@"port"];
        if (assignedToThis && portInfo) continue;

        // If hide other controllers is on, skip models assigned to other controllers
        if (hideOther && controller.length > 0 && !assignedToThis) continue;

        XLCMModelListEntry *entry = [[XLCMModelListEntry alloc] init];
        entry.name = modelName;
        entry.channelCount = [info[@"channelCount"] intValue];
        entry.stringCount = [info[@"stringCount"] intValue];
        entry.controllerName = controller ?: @"";
        entry.isAssignedToThisController = assignedToThis;
        [_modelList addObject:entry];
    }

    // Sort alphabetically
    [_modelList sortUsingComparator:^NSComparisonResult(XLCMModelListEntry *a, XLCMModelListEntry *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];

    _filteredModelList = [_modelList mutableCopy];
    [_modelListTableView reloadData];
}

- (void)updateCheckText {
    NSMutableString *check = [NSMutableString string];

    NSDictionary *controllerInfo = [_engineBridge getControllerInfo:_controllerName];
    if (controllerInfo) {
        NSString *active = controllerInfo[@"Active"];
        if ([active isEqualToString:@"Inactive"]) {
            [check appendString:@"WARN: Controller is inactive.\n"];
        }
    }

    if (check.length == 0) {
        [check appendString:@"No issues found."];
    }

    _checkTextView.stringValue = check;
}

#pragma mark - NSTableViewDataSource (Model List)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_filteredModelList.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_filteredModelList.count) return nil;

    XLCMModelListEntry *entry = _filteredModelList[row];
    NSString *identifier = tableColumn.identifier;

    if ([identifier isEqualToString:@"Name"]) {
        return entry.name;
    } else if ([identifier isEqualToString:@"Info"]) {
        return [NSString stringWithFormat:@"%d str", entry.stringCount];
    }
    return nil;
}

#pragma mark - NSTableViewDelegate (Model List)

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_filteredModelList.count) return nil;

    XLCMModelListEntry *entry = _filteredModelList[row];
    NSString *identifier = tableColumn.identifier;

    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = identifier;

        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.font = [NSFont systemFontOfSize:11];
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:textField];
        cell.textField = textField;

        [NSLayoutConstraint activateConstraints:@[
            [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
            [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    if ([identifier isEqualToString:@"Name"]) {
        cell.textField.stringValue = entry.name;
        // Dim models assigned to other controllers
        if (entry.controllerName.length > 0 && !entry.isAssignedToThisController) {
            cell.textField.textColor = [NSColor tertiaryLabelColor];
        } else {
            cell.textField.textColor = [NSColor labelColor];
        }
    } else if ([identifier isEqualToString:@"Info"]) {
        cell.textField.stringValue = [NSString stringWithFormat:@"%d str", entry.stringCount];
        cell.textField.textColor = [NSColor secondaryLabelColor];
    }

    return cell;
}

#pragma mark - Model List Drag Source

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_filteredModelList.count) return nil;

    XLCMModelListEntry *entry = _filteredModelList[row];
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setString:entry.name forType:XLControllerModelDragType];
    return pbItem;
}

#pragma mark - NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return 180.0;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return splitView.bounds.size.width - 400.0;
}

#pragma mark - Toolbar Actions

- (void)scaleChanged:(NSSlider *)sender {
    _portLayoutView.boxScale = sender.doubleValue;
    NSSize newSize = NSMakeSize(MAX(_portLayoutView.contentWidth, _portLayoutScrollView.bounds.size.width),
                                MAX(_portLayoutView.contentHeight, _portLayoutScrollView.bounds.size.height));
    [_portLayoutView setFrameSize:newSize];
    [_portLayoutView setNeedsDisplay:YES];
}

- (void)filterChanged:(id)sender {
    [self loadModelList];
}

- (void)printLayout:(id)sender {
    // Print stub - show print panel for the port layout view
    NSPrintInfo *printInfo = [NSPrintInfo sharedPrintInfo];
    printInfo.horizontalPagination = NSPrintingPaginationModeAutomatic;
    printInfo.verticalPagination = NSPrintingPaginationModeAutomatic;

    NSPrintOperation *printOp = [NSPrintOperation printOperationWithView:_portLayoutView printInfo:printInfo];
    [printOp runOperationModalForWindow:self.window delegate:nil didRunSelector:nil contextInfo:NULL];
}

- (void)exportCSV:(id)sender {
    // CSV export stub
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"csv"]];
    panel.nameFieldStringValue = [NSString stringWithFormat:@"%@_ports.csv", _controllerName];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            [self writeCSVToURL:panel.URL];
        }
    }];
}

- (void)writeCSVToURL:(NSURL *)url {
    NSMutableString *csv = [NSMutableString string];
    [csv appendString:@"Port,Type,Protocol,Model,Channels,Pixels,Start Channel,Smart Remote\n"];

    // Access port data from the layout view
    // For now, basic stub
    [csv appendFormat:@"# Controller: %@\n", _controllerName];
    [csv appendString:@"# Export not yet fully implemented\n"];

    NSError *error;
    [csv writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error];

    if (error) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Export Failed";
        alert.informativeText = error.localizedDescription;
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }
}

#pragma mark - Notifications

- (void)layoutChanged:(NSNotification *)notification {
    [self loadModelList];
    [self updateCheckText];
}

#pragma mark - Presentation

- (void)showAsSheetForWindow:(NSWindow *)parentWindow {
    [parentWindow beginSheet:self.window completionHandler:^(NSModalResponse returnCode) {
        // Sheet dismissed
    }];
}

- (void)showWindow:(id)sender {
    [self.window center];
    [super showWindow:sender];
    [self.window makeKeyAndOrderFront:sender];
}

@end
