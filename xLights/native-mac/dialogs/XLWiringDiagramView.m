/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLWiringDiagramView.h"
#import "../XLEngineBridge.h"

static const CGFloat kControllerBoxWidth = 180.0;
static const CGFloat kControllerHeaderHeight = 50.0;
static const CGFloat kPortHeight = 28.0;
static const CGFloat kPortSpacing = 4.0;
static const CGFloat kModelBoxWidth = 200.0;
static const CGFloat kModelBoxHeight = 60.0;
static const CGFloat kModelSpacing = 10.0;
static const CGFloat kControllerSpacing = 40.0;
static const CGFloat kConnectionSpacing = 160.0;
static const CGFloat kMargin = 30.0;
static const CGFloat kUnassignedSectionWidth = 220.0;

#pragma mark - XLWiringPort

@implementation XLWiringPort

- (instancetype)init {
    self = [super init];
    if (self) {
        _protocol = @"ws2811";
        _colorOrder = @"RGB";
        _brightness = 100;
        _gamma = 1.0;
    }
    return self;
}

@end

#pragma mark - XLWiringController

@implementation XLWiringController

- (instancetype)init {
    self = [super init];
    if (self) {
        _ports = [NSMutableArray array];
        _type = @"Ethernet";
    }
    return self;
}

@end

#pragma mark - XLWiringModel

@implementation XLWiringModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _displayColor = [NSColor systemBlueColor];
    }
    return self;
}

@end

#pragma mark - XLWiringDiagramView

@interface XLWiringDiagramView ()

@property (nonatomic, strong) NSMutableArray<XLWiringController *> *controllers;
@property (nonatomic, strong) NSMutableArray<XLWiringModel *> *models;
@property (nonatomic, strong) NSMutableArray<XLWiringModel *> *unassignedModels;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *controllerRects;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *modelRects;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *portRects;
@property (nonatomic, strong) NSTrackingArea *trackingArea;

@end

@implementation XLWiringDiagramView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _zoomLevel = 1.0;
        _showChannelInfo = YES;
        _showPortNumbers = YES;
        _showUnassignedModels = YES;

        _controllers = [NSMutableArray array];
        _models = [NSMutableArray array];
        _unassignedModels = [NSMutableArray array];
        _controllerRects = [NSMutableDictionary dictionary];
        _modelRects = [NSMutableDictionary dictionary];
        _portRects = [NSMutableDictionary dictionary];

        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                options:(NSTrackingMouseEnteredAndExited |
                                                        NSTrackingMouseMoved |
                                                        NSTrackingActiveInKeyWindow)
                                                  owner:self
                                               userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
    NSString *hoveredModel = nil;

    for (NSString *modelName in _modelRects) {
        NSRect rect = [_modelRects[modelName] rectValue];
        if (NSPointInRect(location, rect)) {
            hoveredModel = modelName;
            break;
        }
    }

    if (![_hoveredModelName isEqualToString:hoveredModel]) {
        _hoveredModelName = hoveredModel;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseExited:(NSEvent *)event {
    if (_hoveredModelName) {
        _hoveredModelName = nil;
        [self setNeedsDisplay:YES];
    }
}

- (BOOL)isFlipped {
    return YES;
}

- (void)reloadData {
    [_controllers removeAllObjects];
    [_models removeAllObjects];
    [_unassignedModels removeAllObjects];
    [_controllerRects removeAllObjects];
    [_modelRects removeAllObjects];
    [_portRects removeAllObjects];

    if (!_engineBridge) {
        [self setNeedsDisplay:YES];
        return;
    }

    // Load controllers
    NSArray<NSString *> *controllerNames = [_engineBridge getControllerNames];
    for (NSString *controllerName in controllerNames) {
        if (_selectedController && ![_selectedController isEqualToString:controllerName]) {
            continue;
        }

        NSDictionary *info = [_engineBridge getControllerInfo:controllerName];
        if (!info) continue;

        XLWiringController *controller = [[XLWiringController alloc] init];
        controller.name = controllerName;
        controller.type = info[@"type"] ?: @"Unknown";
        controller.ip = info[@"ip"];
        controller.vendor = info[@"vendor"];
        controller.model = info[@"model"];
        controller.startChannel = [info[@"startChannel"] integerValue];
        controller.endChannel = [info[@"endChannel"] integerValue];

        // Load ports
        NSArray<NSDictionary *> *ports = [_engineBridge getPortsForController:controllerName];
        for (NSDictionary *portInfo in ports) {
            XLWiringPort *port = [[XLWiringPort alloc] init];
            port.portNumber = [portInfo[@"port"] integerValue];
            port.protocol = portInfo[@"protocol"] ?: @"ws2811";
            port.startChannel = [portInfo[@"startChannel"] integerValue];
            port.channelCount = [portInfo[@"channelCount"] integerValue];
            port.brightness = [portInfo[@"brightness"] integerValue];
            port.gamma = [portInfo[@"gamma"] floatValue];
            port.colorOrder = portInfo[@"colorOrder"] ?: @"RGB";
            [controller.ports addObject:port];
        }

        [_controllers addObject:controller];
    }

    // Load models and match to controllers/ports
    NSArray<NSString *> *modelNames = [_engineBridge getModelNamesExcludingGroups];
    NSArray<NSColor *> *modelColors = @[
        [NSColor systemBlueColor],
        [NSColor systemGreenColor],
        [NSColor systemOrangeColor],
        [NSColor systemPurpleColor],
        [NSColor systemTealColor],
        [NSColor systemPinkColor],
        [NSColor systemIndigoColor],
        [NSColor systemBrownColor]
    ];
    NSInteger colorIndex = 0;

    for (NSString *modelName in modelNames) {
        NSDictionary *info = [_engineBridge getModelInfo:modelName];
        if (!info) continue;

        XLWiringModel *model = [[XLWiringModel alloc] init];
        model.name = modelName;
        model.type = info[@"type"] ?: @"Unknown";
        model.nodeCount = [info[@"nodeCount"] integerValue];
        model.channelCount = [info[@"channelCount"] integerValue];
        model.startChannel = [info[@"firstChannel"] integerValue];
        model.endChannel = [info[@"endChannel"] integerValue];
        model.controllerName = info[@"controllerName"];
        model.port = [info[@"port"] integerValue];
        model.displayColor = modelColors[colorIndex % modelColors.count];
        colorIndex++;

        // Match model to controller port
        BOOL assigned = NO;
        if (model.controllerName.length > 0 && model.port > 0) {
            for (XLWiringController *controller in _controllers) {
                if ([controller.name isEqualToString:model.controllerName]) {
                    for (XLWiringPort *port in controller.ports) {
                        if (port.portNumber == model.port) {
                            port.modelName = model.name;
                            assigned = YES;
                            break;
                        }
                    }
                    break;
                }
            }
        }

        if (assigned) {
            [_models addObject:model];
        } else if (_showUnassignedModels) {
            [_unassignedModels addObject:model];
        }
    }

    // Update frame size
    NSSize idealSize = [self idealContentSize];
    NSRect newFrame = self.frame;
    newFrame.size.width = MAX(newFrame.size.width, idealSize.width);
    newFrame.size.height = MAX(newFrame.size.height, idealSize.height);
    self.frame = newFrame;

    [self setNeedsDisplay:YES];
}

- (NSSize)idealContentSize {
    CGFloat totalHeight = kMargin * 2;
    CGFloat totalWidth = kMargin * 2 + kControllerBoxWidth + kConnectionSpacing + kModelBoxWidth;

    for (XLWiringController *controller in _controllers) {
        CGFloat controllerHeight = kControllerHeaderHeight +
            (controller.ports.count * (kPortHeight + kPortSpacing)) + kPortSpacing;
        totalHeight += controllerHeight + kControllerSpacing;
    }

    if (_showUnassignedModels && _unassignedModels.count > 0) {
        totalWidth += kUnassignedSectionWidth;
    }

    return NSMakeSize(totalWidth * _zoomLevel, totalHeight * _zoomLevel);
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleBy:_zoomLevel];
    [transform concat];

    // Draw title
    [self drawTitle];

    // Draw controllers and ports
    CGFloat yOffset = kMargin + 40;
    for (XLWiringController *controller in _controllers) {
        yOffset = [self drawController:controller atY:yOffset];
    }

    // Draw connections
    [self drawConnections];

    // Draw unassigned models section
    if (_showUnassignedModels && _unassignedModels.count > 0) {
        [self drawUnassignedModels];
    }

    // Draw legend
    [self drawLegend];
}

- (void)drawTitle {
    NSString *title = @"Wiring Diagram";
    if (_selectedController) {
        title = [NSString stringWithFormat:@"Wiring Diagram - %@", _selectedController];
    }

    NSDictionary *titleAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:18],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };

    [title drawAtPoint:NSMakePoint(kMargin, kMargin) withAttributes:titleAttrs];
}

- (CGFloat)drawController:(XLWiringController *)controller atY:(CGFloat)startY {
    CGFloat xPos = kMargin;
    CGFloat yPos = startY;

    // Calculate controller box height
    CGFloat controllerHeight = kControllerHeaderHeight +
        (controller.ports.count * (kPortHeight + kPortSpacing)) + kPortSpacing;

    // Draw controller box
    NSRect controllerRect = NSMakeRect(xPos, yPos, kControllerBoxWidth, controllerHeight);
    _controllerRects[controller.name] = [NSValue valueWithRect:controllerRect];

    // Background
    NSBezierPath *boxPath = [NSBezierPath bezierPathWithRoundedRect:controllerRect
                                                           xRadius:8.0
                                                           yRadius:8.0];
    [[NSColor controlBackgroundColor] setFill];
    [boxPath fill];

    // Border
    [[NSColor separatorColor] setStroke];
    boxPath.lineWidth = 1.0;
    [boxPath stroke];

    // Controller header
    NSRect headerRect = NSMakeRect(xPos, yPos, kControllerBoxWidth, kControllerHeaderHeight);
    NSBezierPath *headerPath = [NSBezierPath bezierPath];
    [headerPath moveToPoint:NSMakePoint(xPos + 8, yPos)];
    [headerPath lineToPoint:NSMakePoint(xPos + kControllerBoxWidth - 8, yPos)];
    [headerPath appendBezierPathWithArcFromPoint:NSMakePoint(xPos + kControllerBoxWidth, yPos)
                                         toPoint:NSMakePoint(xPos + kControllerBoxWidth, yPos + 8)
                                          radius:8];
    [headerPath lineToPoint:NSMakePoint(xPos + kControllerBoxWidth, yPos + kControllerHeaderHeight)];
    [headerPath lineToPoint:NSMakePoint(xPos, yPos + kControllerHeaderHeight)];
    [headerPath lineToPoint:NSMakePoint(xPos, yPos + 8)];
    [headerPath appendBezierPathWithArcFromPoint:NSMakePoint(xPos, yPos)
                                         toPoint:NSMakePoint(xPos + 8, yPos)
                                          radius:8];
    [headerPath closePath];

    [[NSColor controlAccentColor] setFill];
    [headerPath fill];

    // Controller name
    NSDictionary *nameAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:13],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSString *displayName = controller.name;
    NSSize nameSize = [displayName sizeWithAttributes:nameAttrs];
    [displayName drawAtPoint:NSMakePoint(xPos + (kControllerBoxWidth - nameSize.width) / 2,
                                         yPos + 8)
              withAttributes:nameAttrs];

    // Controller info
    NSDictionary *infoAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:1.0 alpha:0.8]
    };
    NSString *infoText = controller.ip ?: controller.type;
    if (controller.vendor.length > 0) {
        infoText = [NSString stringWithFormat:@"%@ %@", controller.vendor, controller.model ?: @""];
    }
    NSSize infoSize = [infoText sizeWithAttributes:infoAttrs];
    [infoText drawAtPoint:NSMakePoint(xPos + (kControllerBoxWidth - infoSize.width) / 2,
                                      yPos + 26)
           withAttributes:infoAttrs];

    // Draw ports
    CGFloat portY = yPos + kControllerHeaderHeight + kPortSpacing;
    for (XLWiringPort *port in controller.ports) {
        [self drawPort:port atX:xPos + 8 y:portY controllerName:controller.name];
        portY += kPortHeight + kPortSpacing;
    }

    return startY + controllerHeight + kControllerSpacing;
}

- (void)drawPort:(XLWiringPort *)port atX:(CGFloat)xPos y:(CGFloat)yPos controllerName:(NSString *)controllerName {
    CGFloat portWidth = kControllerBoxWidth - 16;
    NSRect portRect = NSMakeRect(xPos, yPos, portWidth, kPortHeight);

    NSString *portKey = [NSString stringWithFormat:@"%@:%ld", controllerName, (long)port.portNumber];
    _portRects[portKey] = [NSValue valueWithRect:portRect];

    // Port background
    NSColor *portColor = port.modelName ?
        [[NSColor systemGreenColor] colorWithAlphaComponent:0.2] :
        [[NSColor secondaryLabelColor] colorWithAlphaComponent:0.1];

    NSBezierPath *portPath = [NSBezierPath bezierPathWithRoundedRect:portRect xRadius:4 yRadius:4];
    [portColor setFill];
    [portPath fill];

    [[NSColor separatorColor] setStroke];
    portPath.lineWidth = 0.5;
    [portPath stroke];

    // Port number
    if (_showPortNumbers) {
        NSDictionary *portNumAttrs = @{
            NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor labelColor]
        };
        NSString *portNumStr = [NSString stringWithFormat:@"P%ld", (long)port.portNumber];
        [portNumStr drawAtPoint:NSMakePoint(xPos + 6, yPos + 6) withAttributes:portNumAttrs];
    }

    // Protocol and channel info
    NSDictionary *detailAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };

    NSString *detailStr;
    if (_showChannelInfo && port.channelCount > 0) {
        detailStr = [NSString stringWithFormat:@"%@ Ch:%ld-%ld",
                     port.protocol,
                     (long)port.startChannel,
                     (long)(port.startChannel + port.channelCount - 1)];
    } else {
        detailStr = port.protocol;
    }
    [detailStr drawAtPoint:NSMakePoint(xPos + 36, yPos + 6) withAttributes:detailAttrs];
}

- (void)drawConnections {
    for (XLWiringModel *model in _models) {
        if (!model.controllerName || model.port == 0) continue;

        NSString *portKey = [NSString stringWithFormat:@"%@:%ld", model.controllerName, (long)model.port];
        NSValue *portRectValue = _portRects[portKey];
        NSValue *modelRectValue = _modelRects[model.name];

        if (!portRectValue || !modelRectValue) continue;

        NSRect portRect = [portRectValue rectValue];
        NSRect modelRect = [modelRectValue rectValue];

        // Calculate connection points
        NSPoint startPoint = NSMakePoint(NSMaxX(portRect), NSMidY(portRect));
        NSPoint endPoint = NSMakePoint(NSMinX(modelRect), NSMidY(modelRect));

        // Draw bezier curve connection
        NSBezierPath *connectionPath = [NSBezierPath bezierPath];
        [connectionPath moveToPoint:startPoint];

        CGFloat controlOffset = (endPoint.x - startPoint.x) / 2;
        NSPoint control1 = NSMakePoint(startPoint.x + controlOffset, startPoint.y);
        NSPoint control2 = NSMakePoint(endPoint.x - controlOffset, endPoint.y);
        [connectionPath curveToPoint:endPoint controlPoint1:control1 controlPoint2:control2];

        // Highlight if hovered
        BOOL isHovered = [_hoveredModelName isEqualToString:model.name];
        NSColor *lineColor = isHovered ? model.displayColor : [model.displayColor colorWithAlphaComponent:0.6];
        CGFloat lineWidth = isHovered ? 3.0 : 2.0;

        [lineColor setStroke];
        connectionPath.lineWidth = lineWidth;
        [connectionPath stroke];

        // Draw connection dot at port end
        NSRect dotRect = NSMakeRect(startPoint.x - 4, startPoint.y - 4, 8, 8);
        NSBezierPath *dotPath = [NSBezierPath bezierPathWithOvalInRect:dotRect];
        [lineColor setFill];
        [dotPath fill];
    }

    // Draw model boxes
    CGFloat modelX = kMargin + kControllerBoxWidth + kConnectionSpacing;
    CGFloat modelY = kMargin + 60;

    for (XLWiringModel *model in _models) {
        [self drawModel:model atX:modelX y:modelY];
        modelY += kModelBoxHeight + kModelSpacing;
    }
}

- (void)drawModel:(XLWiringModel *)model atX:(CGFloat)xPos y:(CGFloat)yPos {
    NSRect modelRect = NSMakeRect(xPos, yPos, kModelBoxWidth, kModelBoxHeight);
    _modelRects[model.name] = [NSValue valueWithRect:modelRect];

    BOOL isHovered = [_hoveredModelName isEqualToString:model.name];

    // Background
    NSColor *bgColor = isHovered ?
        [model.displayColor colorWithAlphaComponent:0.15] :
        [model.displayColor colorWithAlphaComponent:0.08];

    NSBezierPath *boxPath = [NSBezierPath bezierPathWithRoundedRect:modelRect xRadius:6 yRadius:6];
    [bgColor setFill];
    [boxPath fill];

    // Border
    NSColor *borderColor = isHovered ? model.displayColor : [model.displayColor colorWithAlphaComponent:0.5];
    [borderColor setStroke];
    boxPath.lineWidth = isHovered ? 2.0 : 1.0;
    [boxPath stroke];

    // Color indicator bar
    NSRect indicatorRect = NSMakeRect(xPos, yPos, 6, kModelBoxHeight);
    NSBezierPath *indicatorPath = [NSBezierPath bezierPath];
    [indicatorPath moveToPoint:NSMakePoint(xPos + 6, yPos)];
    [indicatorPath lineToPoint:NSMakePoint(xPos + 6, yPos + kModelBoxHeight)];
    [indicatorPath lineToPoint:NSMakePoint(xPos, yPos + kModelBoxHeight - 6)];
    [indicatorPath appendBezierPathWithArcFromPoint:NSMakePoint(xPos, yPos + kModelBoxHeight)
                                            toPoint:NSMakePoint(xPos, yPos + kModelBoxHeight - 6)
                                             radius:6];
    [indicatorPath lineToPoint:NSMakePoint(xPos, yPos + 6)];
    [indicatorPath appendBezierPathWithArcFromPoint:NSMakePoint(xPos, yPos)
                                            toPoint:NSMakePoint(xPos + 6, yPos)
                                             radius:6];
    [indicatorPath closePath];
    [model.displayColor setFill];
    [indicatorPath fill];

    // Model name
    NSDictionary *nameAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:12],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };
    NSString *displayName = model.name;
    if (displayName.length > 22) {
        displayName = [[displayName substringToIndex:19] stringByAppendingString:@"..."];
    }
    [displayName drawAtPoint:NSMakePoint(xPos + 12, yPos + 8) withAttributes:nameAttrs];

    // Model type
    NSDictionary *typeAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };
    [model.type drawAtPoint:NSMakePoint(xPos + 12, yPos + 24) withAttributes:typeAttrs];

    // Channel info
    if (_showChannelInfo) {
        NSDictionary *channelAttrs = @{
            NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
        };
        NSString *channelStr = [NSString stringWithFormat:@"%ld nodes, Ch %ld-%ld",
                                (long)model.nodeCount,
                                (long)model.startChannel,
                                (long)model.endChannel];
        [channelStr drawAtPoint:NSMakePoint(xPos + 12, yPos + 40) withAttributes:channelAttrs];
    }
}

- (void)drawUnassignedModels {
    CGFloat xPos = kMargin + kControllerBoxWidth + kConnectionSpacing + kModelBoxWidth + 40;
    CGFloat yPos = kMargin + 40;

    // Section header
    NSDictionary *headerAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:14],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };
    [@"Unassigned Models" drawAtPoint:NSMakePoint(xPos, yPos) withAttributes:headerAttrs];
    yPos += 30;

    // Draw unassigned models
    for (XLWiringModel *model in _unassignedModels) {
        NSRect modelRect = NSMakeRect(xPos, yPos, kUnassignedSectionWidth - 20, 40);
        _modelRects[model.name] = [NSValue valueWithRect:modelRect];

        BOOL isHovered = [_hoveredModelName isEqualToString:model.name];

        // Background
        NSColor *bgColor = isHovered ?
            [[NSColor systemYellowColor] colorWithAlphaComponent:0.15] :
            [[NSColor secondaryLabelColor] colorWithAlphaComponent:0.05];

        NSBezierPath *boxPath = [NSBezierPath bezierPathWithRoundedRect:modelRect xRadius:4 yRadius:4];
        [bgColor setFill];
        [boxPath fill];

        // Dashed border for unassigned
        [[NSColor systemYellowColor] setStroke];
        boxPath.lineWidth = 1.0;
        CGFloat dashPattern[] = {4, 2};
        [boxPath setLineDash:dashPattern count:2 phase:0];
        [boxPath stroke];

        // Model name
        NSDictionary *nameAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:11],
            NSForegroundColorAttributeName: [NSColor labelColor]
        };
        NSString *displayName = model.name;
        if (displayName.length > 20) {
            displayName = [[displayName substringToIndex:17] stringByAppendingString:@"..."];
        }
        [displayName drawAtPoint:NSMakePoint(xPos + 8, yPos + 6) withAttributes:nameAttrs];

        // Node count
        NSDictionary *nodeAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:9],
            NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
        };
        NSString *nodeStr = [NSString stringWithFormat:@"%ld nodes", (long)model.nodeCount];
        [nodeStr drawAtPoint:NSMakePoint(xPos + 8, yPos + 22) withAttributes:nodeAttrs];

        yPos += 50;
    }
}

- (void)drawLegend {
    CGFloat yPos = self.bounds.size.height / _zoomLevel - 60;
    CGFloat xPos = kMargin;

    NSDictionary *legendAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };

    // Connected port
    NSRect connectedRect = NSMakeRect(xPos, yPos, 16, 16);
    NSBezierPath *connectedPath = [NSBezierPath bezierPathWithRoundedRect:connectedRect xRadius:2 yRadius:2];
    [[[NSColor systemGreenColor] colorWithAlphaComponent:0.2] setFill];
    [connectedPath fill];
    [[NSColor separatorColor] setStroke];
    [connectedPath stroke];
    [@"Port with model" drawAtPoint:NSMakePoint(xPos + 22, yPos + 2) withAttributes:legendAttrs];

    // Empty port
    xPos += 130;
    NSRect emptyRect = NSMakeRect(xPos, yPos, 16, 16);
    NSBezierPath *emptyPath = [NSBezierPath bezierPathWithRoundedRect:emptyRect xRadius:2 yRadius:2];
    [[[NSColor secondaryLabelColor] colorWithAlphaComponent:0.1] setFill];
    [emptyPath fill];
    [[NSColor separatorColor] setStroke];
    [emptyPath stroke];
    [@"Empty port" drawAtPoint:NSMakePoint(xPos + 22, yPos + 2) withAttributes:legendAttrs];

    // Unassigned
    if (_showUnassignedModels) {
        xPos += 100;
        NSRect unassignedRect = NSMakeRect(xPos, yPos, 16, 16);
        NSBezierPath *unassignedPath = [NSBezierPath bezierPathWithRoundedRect:unassignedRect xRadius:2 yRadius:2];
        [[NSColor systemYellowColor] setStroke];
        unassignedPath.lineWidth = 1.0;
        CGFloat dashPattern[] = {3, 2};
        [unassignedPath setLineDash:dashPattern count:2 phase:0];
        [unassignedPath stroke];
        [@"Unassigned model" drawAtPoint:NSMakePoint(xPos + 22, yPos + 2) withAttributes:legendAttrs];
    }
}

- (NSData *)exportAsPDF {
    NSSize contentSize = [self idealContentSize];
    NSRect pdfRect = NSMakeRect(0, 0, contentSize.width, contentSize.height);

    NSMutableData *pdfData = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)pdfData);

    CGRect mediaBox = CGRectMake(0, 0, pdfRect.size.width, pdfRect.size.height);
    CGContextRef pdfContext = CGPDFContextCreate(consumer, &mediaBox, NULL);
    CGDataConsumerRelease(consumer);

    if (!pdfContext) return nil;

    CGPDFContextBeginPage(pdfContext, NULL);

    NSGraphicsContext *graphicsContext = [NSGraphicsContext graphicsContextWithCGContext:pdfContext flipped:YES];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:graphicsContext];

    // Draw the diagram
    CGFloat savedZoom = _zoomLevel;
    _zoomLevel = 1.0;
    [self drawRect:pdfRect];
    _zoomLevel = savedZoom;

    [NSGraphicsContext restoreGraphicsState];

    CGPDFContextEndPage(pdfContext);
    CGPDFContextClose(pdfContext);
    CGContextRelease(pdfContext);

    return pdfData;
}

- (NSData *)exportAsPNG {
    NSSize contentSize = [self idealContentSize];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
                             initWithBitmapDataPlanes:NULL
                             pixelsWide:contentSize.width
                             pixelsHigh:contentSize.height
                             bitsPerSample:8
                             samplesPerPixel:4
                             hasAlpha:YES
                             isPlanar:NO
                             colorSpaceName:NSCalibratedRGBColorSpace
                             bytesPerRow:0
                             bitsPerPixel:0];

    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];

    // Fill background
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(NSMakeRect(0, 0, contentSize.width, contentSize.height));

    // Draw the diagram
    CGFloat savedZoom = _zoomLevel;
    _zoomLevel = 1.0;
    [self drawRect:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
    _zoomLevel = savedZoom;

    [NSGraphicsContext restoreGraphicsState];

    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

@end
