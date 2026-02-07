/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLNodeWiringView.h"
#import "../XLEngineBridge.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#define MIN_FONT_SIZE 8
#define FONT_SIZE_INCREMENT 4
#define ADJUST_WIDTH 40.0
#define ADJUST_HEIGHT 80.0
#define FRONT_X_ADJUST (ADJUST_WIDTH / 2.0)
#define SCALE_WIDTH 0.8
#define SCALE_HEIGHT 0.8

#pragma mark - Color Theme

typedef struct {
    XLWiringTheme type;
    BOOL multiLightDark;
    CGFloat bgR, bgG, bgB;
    CGFloat msgR, msgG, msgB;
    CGFloat msgAltR, msgAltG, msgAltB;
    CGFloat msgOutR, msgOutG, msgOutB;
    CGFloat wireR, wireG, wireB;
    CGFloat wireOutR, wireOutG, wireOutB;
    CGFloat nodeR, nodeG, nodeB;
    CGFloat nodeOutR, nodeOutG, nodeOutB;
    CGFloat labelR, labelG, labelB;
    CGFloat labelOutR, labelOutG, labelOutB;
} XLWiringColorTheme;

static XLWiringColorTheme XLMakeTheme(XLWiringTheme type) {
    XLWiringColorTheme t;
    t.type = type;
    switch (type) {
        case XLWiringThemeDark:
            t.multiLightDark = YES;
            t.bgR = 0; t.bgG = 0; t.bgB = 0;
            t.msgR = 1; t.msgG = 1; t.msgB = 1;
            t.msgAltR = 0; t.msgAltG = 0; t.msgAltB = 1;
            t.msgOutR = 0; t.msgOutG = 0; t.msgOutB = 0;
            t.wireR = 1; t.wireG = 1; t.wireB = 1;
            t.wireOutR = 1; t.wireOutG = 1; t.wireOutB = 0;
            t.nodeR = 1; t.nodeG = 1; t.nodeB = 1;
            t.nodeOutR = 1; t.nodeOutG = 1; t.nodeOutB = 0;
            t.labelR = 0.75; t.labelG = 0.75; t.labelB = 0.75;
            t.labelOutR = 0; t.labelOutG = 0; t.labelOutB = 0;
            break;
        case XLWiringThemeGray:
            t.multiLightDark = YES;
            t.bgR = 0.188; t.bgG = 0.188; t.bgB = 0.188;
            t.msgR = 1; t.msgG = 1; t.msgB = 1;
            t.msgAltR = 1; t.msgAltG = 1; t.msgAltB = 0;
            t.msgOutR = 0.188; t.msgOutG = 0.188; t.msgOutB = 0.188;
            t.wireR = 1; t.wireG = 1; t.wireB = 1;
            t.wireOutR = 1; t.wireOutG = 1; t.wireOutB = 1;
            t.nodeR = 1; t.nodeG = 1; t.nodeB = 1;
            t.nodeOutR = 1; t.nodeOutG = 1; t.nodeOutB = 1;
            t.labelR = 1; t.labelG = 1; t.labelB = 1;
            t.labelOutR = 0.188; t.labelOutG = 0.188; t.labelOutB = 0.188;
            break;
        case XLWiringThemeLight:
            t.multiLightDark = NO;
            t.bgR = 1; t.bgG = 1; t.bgB = 1;
            t.msgR = 0; t.msgG = 0; t.msgB = 0;
            t.msgAltR = 0; t.msgAltG = 0; t.msgAltB = 1;
            t.msgOutR = 1; t.msgOutG = 1; t.msgOutB = 1;
            t.wireR = 1; t.wireG = 1; t.wireB = 1;
            t.wireOutR = 0; t.wireOutG = 0; t.wireOutB = 0;
            t.nodeR = 1; t.nodeG = 1; t.nodeB = 1;
            t.nodeOutR = 0; t.nodeOutG = 0; t.nodeOutB = 0;
            t.labelR = 0; t.labelG = 0; t.labelB = 0;
            t.labelOutR = 1; t.labelOutG = 1; t.labelOutB = 1;
            break;
    }
    return t;
}

#pragma mark - Node Data

@interface XLNodeData : NSObject
@property (nonatomic, assign) NSInteger nodeNumber;
@property (nonatomic, assign) NSInteger stringNum;
@property (nonatomic, assign) CGFloat x;
@property (nonatomic, assign) CGFloat y;
@end

@implementation XLNodeData
@end

#pragma mark - XLNodeWiringView

@interface XLNodeWiringView ()

@property (nonatomic, assign) CGFloat zoom;
@property (nonatomic, assign) CGPoint panOffset;
@property (nonatomic, assign) CGPoint lastMousePos;
@property (nonatomic, assign) BOOL isPanning;

@property (nonatomic, strong) NSMutableArray<NSMutableArray<XLNodeData *> *> *strings;
@property (nonatomic, assign) NSInteger cols;
@property (nonatomic, assign) NSInteger rows;
@property (nonatomic, assign) BOOL multilight;

@property (nonatomic, assign) XLWiringColorTheme theme;
@property (nonatomic, strong) NSTrackingArea *trackingArea;

@property (nonatomic, strong) NSMutableArray<NSMutableArray<XLNodeData *> *> *originalStrings;
@property (nonatomic, assign) BOOL hasRotated;

@end

@implementation XLNodeWiringView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _zoom = 1.0;
        _panOffset = CGPointZero;
        _lastMousePos = CGPointZero;
        _isPanning = NO;
        _rearView = YES;
        _colorTheme = XLWiringThemeDark;
        _fontSize = 12;
        _rotation = 0;
        _cols = 1;
        _rows = 1;
        _multilight = NO;
        _hasRotated = NO;
        _strings = [NSMutableArray array];
        _originalStrings = [NSMutableArray array];
        _theme = XLMakeTheme(XLWiringThemeDark);
    }
    return self;
}

- (BOOL)isFlipped {
    return NO;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                options:(NSTrackingMouseEnteredAndExited |
                                                         NSTrackingActiveInKeyWindow)
                                                  owner:self
                                               userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

#pragma mark - Data Loading

- (void)loadModelData {
    [_strings removeAllObjects];
    _multilight = NO;

    if (!_engineBridge || !_modelName) return;

    NSArray<NSDictionary *> *nodes = [_engineBridge getModelNodes:_modelName];
    if (nodes.count == 0) return;

    CGFloat minX = CGFLOAT_MAX, minY = CGFLOAT_MAX;
    CGFloat maxX = -CGFLOAT_MAX, maxY = -CGFLOAT_MAX;

    for (NSDictionary *node in nodes) {
        CGFloat x = [node[@"bufX"] floatValue];
        CGFloat y = [node[@"bufY"] floatValue];
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
    }

    _cols = (NSInteger)(maxX - minX) + 8;
    _rows = (NSInteger)(maxY - minY) + 4;

    NSMutableDictionary<NSNumber *, NSMutableArray<XLNodeData *> *> *stringMap = [NSMutableDictionary dictionary];

    NSInteger nodeNum = 1;
    for (NSDictionary *node in nodes) {
        NSInteger stringNum = [node[@"stringNum"] integerValue];
        CGFloat x = [node[@"bufX"] floatValue] - minX;
        CGFloat y = [node[@"bufY"] floatValue] - minY + 2;
        y = _rows - y;

        XLNodeData *nd = [[XLNodeData alloc] init];
        nd.nodeNumber = nodeNum;
        nd.stringNum = stringNum;
        nd.x = x;
        nd.y = y;

        NSNumber *key = @(stringNum);
        if (!stringMap[key]) {
            stringMap[key] = [NSMutableArray array];
        }
        [stringMap[key] addObject:nd];
        nodeNum++;
    }

    NSArray *sortedKeys = [[stringMap allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *key in sortedKeys) {
        [_strings addObject:stringMap[key]];
    }

    [_originalStrings removeAllObjects];
    for (NSMutableArray<XLNodeData *> *string in _strings) {
        NSMutableArray<XLNodeData *> *copy = [NSMutableArray arrayWithCapacity:string.count];
        for (XLNodeData *nd in string) {
            XLNodeData *ndCopy = [[XLNodeData alloc] init];
            ndCopy.nodeNumber = nd.nodeNumber;
            ndCopy.stringNum = nd.stringNum;
            ndCopy.x = nd.x;
            ndCopy.y = nd.y;
            [copy addObject:ndCopy];
        }
        [_originalStrings addObject:copy];
    }

    _theme = XLMakeTheme(_colorTheme);
    [self setNeedsDisplay:YES];
}

- (void)setColorTheme:(XLWiringTheme)colorTheme {
    _colorTheme = colorTheme;
    _theme = XLMakeTheme(colorTheme);
    [self setNeedsDisplay:YES];
}

- (void)setRearView:(BOOL)rearView {
    _rearView = rearView;
    [self setNeedsDisplay:YES];
}

- (void)setFontSize:(NSInteger)fontSize {
    _fontSize = MAX(fontSize, MIN_FONT_SIZE);
    [self setNeedsDisplay:YES];
}

- (void)setRotation:(NSInteger)rotation {
    _rotation = rotation % 360;
    [self applyRotation];
    [self setNeedsDisplay:YES];
}

#pragma mark - Rotation

- (void)applyRotation {
    if (_rotation == 0) {
        [_strings removeAllObjects];
        for (NSMutableArray<XLNodeData *> *origString in _originalStrings) {
            NSMutableArray<XLNodeData *> *copy = [NSMutableArray arrayWithCapacity:origString.count];
            for (XLNodeData *nd in origString) {
                XLNodeData *ndCopy = [[XLNodeData alloc] init];
                ndCopy.nodeNumber = nd.nodeNumber;
                ndCopy.stringNum = nd.stringNum;
                ndCopy.x = nd.x;
                ndCopy.y = nd.y;
                [copy addObject:ndCopy];
            }
            [_strings addObject:copy];
        }
        return;
    }

    CGFloat centerX = (CGFloat)_cols / 2.0;
    CGFloat centerY = (CGFloat)_rows / 2.0;

    double radians = (M_PI / 180.0) * _rotation;
    double cosA = cos(radians);
    double sinA = sin(radians);

    [_strings removeAllObjects];
    for (NSMutableArray<XLNodeData *> *origString in _originalStrings) {
        NSMutableArray<XLNodeData *> *rotatedString = [NSMutableArray arrayWithCapacity:origString.count];
        for (XLNodeData *nd in origString) {
            XLNodeData *rnd = [[XLNodeData alloc] init];
            rnd.nodeNumber = nd.nodeNumber;
            rnd.stringNum = nd.stringNum;
            rnd.x = (cosA * (nd.x - centerX)) + (sinA * (nd.y - centerY)) + centerX;
            rnd.y = (cosA * (nd.y - centerY)) - (sinA * (nd.x - centerX)) + centerY;
            [rotatedString addObject:rnd];
        }
        [_strings addObject:rotatedString];
    }
}

#pragma mark - View Reset

- (void)resetView {
    _zoom = 1.0;
    _panOffset = CGPointZero;
    if (_hasRotated) {
        _rotation = 0;
        _hasRotated = NO;
        [self applyRotation];
    }
    [self setNeedsDisplay:YES];
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSColor *bgColor = [NSColor colorWithCalibratedRed:_theme.bgR green:_theme.bgG blue:_theme.bgB alpha:1.0];
    [bgColor setFill];
    NSRectFill(self.bounds);

    if (_strings.count == 0) {
        [self drawNoDataMessage];
        return;
    }

    [self drawNodes];
}

- (void)drawNoDataMessage {
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:16],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };
    NSString *msg = @"No node data available";
    if (_modelName) {
        msg = [NSString stringWithFormat:@"No node data for model \"%@\"", _modelName];
    }
    NSSize size = [msg sizeWithAttributes:attrs];
    CGFloat x = (self.bounds.size.width - size.width) / 2;
    CGFloat y = (self.bounds.size.height - size.height) / 2;
    [msg drawAtPoint:NSMakePoint(x, y) withAttributes:attrs];
}

static void RenderOutlinedText(NSString *text, NSPoint pt, NSColor *foreColor, NSColor *outlineColor, NSFont *font) {
    NSDictionary *outAttrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: outlineColor
    };
    NSDictionary *fgAttrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: foreColor
    };
    [text drawAtPoint:NSMakePoint(pt.x - 1, pt.y) withAttributes:outAttrs];
    [text drawAtPoint:NSMakePoint(pt.x + 1, pt.y) withAttributes:outAttrs];
    [text drawAtPoint:NSMakePoint(pt.x, pt.y - 1) withAttributes:outAttrs];
    [text drawAtPoint:NSMakePoint(pt.x, pt.y + 1) withAttributes:outAttrs];
    [text drawAtPoint:pt withAttributes:fgAttrs];
}

- (CGFloat)adjustX:(CGFloat)x {
    return x + ADJUST_WIDTH / 2.0;
}

- (CGFloat)adjustY:(CGFloat)y {
    return y + ADJUST_HEIGHT / 2.0;
}

- (void)drawNodes {
    CGFloat viewWidth = self.bounds.size.width;
    CGFloat viewHeight = self.bounds.size.height;

    CGFloat pageWidth = viewWidth * SCALE_WIDTH;
    CGFloat pageHeight = viewHeight * SCALE_HEIGHT;

    NSInteger width = _cols;
    NSInteger height = _rows;

    if (width == 0) width = 1;
    if (height == 0) height = 1;

    CGFloat r = 0.6 * MIN(pageWidth / width / 2.0, pageHeight / height / 2.0);
    if (r == 0) r = 1;
    if (r > 5) r = 5;
    if (r < 3) r = 3;

    NSFont *font = [NSFont boldSystemFontOfSize:_fontSize];
    CGFloat penWidth = 2.0;

    NSColor *wireColor = [NSColor colorWithCalibratedRed:_theme.wireOutR green:_theme.wireOutG blue:_theme.wireOutB alpha:1.0];
    NSColor *labelFillColor = [NSColor colorWithCalibratedRed:_theme.labelR green:_theme.labelG blue:_theme.labelB alpha:1.0];
    NSColor *nodeFillColor = [NSColor colorWithCalibratedRed:_theme.nodeR green:_theme.nodeG blue:_theme.nodeB alpha:1.0];
    NSColor *nodeOutlineColor = [NSColor colorWithCalibratedRed:_theme.nodeOutR green:_theme.nodeOutG blue:_theme.nodeOutB alpha:1.0];
    NSColor *firstNodeColor = [NSColor colorWithCalibratedRed:_theme.msgAltR green:_theme.msgAltG blue:_theme.msgAltB alpha:1.0];
    NSColor *labelOutlineColor = [NSColor colorWithCalibratedRed:_theme.labelOutR green:_theme.labelOutG blue:_theme.labelOutB alpha:1.0];

    NSInteger stringIndex = 0;
    for (NSMutableArray<XLNodeData *> *string in _strings) {
        // Draw wiring lines
        NSColor *lineColor;
        if (stringIndex % 2 == 0) {
            lineColor = wireColor;
        } else {
            lineColor = labelFillColor;
        }
        [lineColor setStroke];

        for (NSInteger i = 1; i < (NSInteger)string.count; i++) {
            XLNodeData *prev = string[i - 1];
            XLNodeData *curr = string[i];

            if (curr.nodeNumber != prev.nodeNumber + 1) continue;

            CGFloat x1 = (width - prev.x) * pageWidth / width;
            if (!_rearView) x1 = pageWidth - x1 + FRONT_X_ADJUST;
            CGFloat y1 = prev.y * pageHeight / height;

            CGFloat x2 = (width - curr.x) * pageWidth / width;
            if (!_rearView) x2 = pageWidth - x2 + FRONT_X_ADJUST;
            CGFloat y2 = curr.y * pageHeight / height;

            NSBezierPath *line = [NSBezierPath bezierPath];
            line.lineWidth = penWidth;
            [line moveToPoint:NSMakePoint(([self adjustX:x1] * _zoom) + _panOffset.x,
                                          ([self adjustY:y1] * _zoom) + _panOffset.y)];
            [line lineToPoint:NSMakePoint(([self adjustX:x2] * _zoom) + _panOffset.x,
                                          ([self adjustY:y2] * _zoom) + _panOffset.y)];
            [line stroke];
        }

        // Draw node circles
        BOOL first = YES;
        for (XLNodeData *nd in string) {
            CGFloat x = (width - nd.x) * pageWidth / width;
            if (!_rearView) x = pageWidth - x + FRONT_X_ADJUST;
            CGFloat y = nd.y * pageHeight / height;

            CGFloat cx = ([self adjustX:x] * _zoom) + _panOffset.x;
            CGFloat cy = ([self adjustY:y] * _zoom) + _panOffset.y;

            NSRect circleRect = NSMakeRect(cx - r, cy - r, r * 2, r * 2);
            NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:circleRect];
            circle.lineWidth = penWidth;

            if (first) {
                [firstNodeColor setFill];
                [firstNodeColor setStroke];
                first = NO;
            } else {
                [nodeFillColor setFill];
                [nodeOutlineColor setStroke];
            }
            [circle fill];
            [circle stroke];
        }

        // Draw labels
        BOOL useStringNodeFormat = (_strings.count > 1);
        for (XLNodeData *nd in string) {
            CGFloat x = (width - nd.x) * pageWidth / width;
            if (!_rearView) x = pageWidth - x + FRONT_X_ADJUST;
            CGFloat y = nd.y * pageHeight / height;

            NSString *label;
            if (useStringNodeFormat) {
                label = [NSString stringWithFormat:@"%ld:%ld", (long)(stringIndex + 1), (long)nd.nodeNumber];
            } else {
                label = [NSString stringWithFormat:@"%ld", (long)nd.nodeNumber];
            }

            CGFloat lx = ([self adjustX:x + r + 2] * _zoom) + _panOffset.x;
            CGFloat ly = ([self adjustY:y] * _zoom) + _panOffset.y;

            RenderOutlinedText(label, NSMakePoint(lx, ly), labelFillColor, labelOutlineColor, font);
        }

        stringIndex++;
    }

    // Draw header text
    NSColor *msgColor = [NSColor colorWithCalibratedRed:_theme.msgR green:_theme.msgG blue:_theme.msgB alpha:1.0];
    NSColor *msgAltColor = [NSColor colorWithCalibratedRed:_theme.msgAltR green:_theme.msgAltG blue:_theme.msgAltB alpha:1.0];
    NSColor *msgOutColor = [NSColor colorWithCalibratedRed:_theme.msgOutR green:_theme.msgOutG blue:_theme.msgOutB alpha:1.0];

    NSFont *headerFont = [NSFont boldSystemFontOfSize:_fontSize];

    if (_rearView) {
        RenderOutlinedText(@"CAUTION: Reverse view",
                          NSMakePoint([self adjustX:0] + _panOffset.x, 20 + _panOffset.y),
                          msgColor, msgOutColor, headerFont);
    } else {
        RenderOutlinedText(@"CAUTION: Front view",
                          NSMakePoint([self adjustX:0] + _panOffset.x, 20 + _panOffset.y),
                          msgAltColor, msgOutColor, headerFont);
    }

    NSString *modelText = [NSString stringWithFormat:@"Model: %@", _modelName ?: @"Unknown"];
    RenderOutlinedText(modelText,
                      NSMakePoint([self adjustX:0] + _panOffset.x, 20 + _fontSize + 4 + _panOffset.y),
                      msgColor, msgOutColor, headerFont);

    NSString *rotationText = [NSString stringWithFormat:@"Rotation: %ld", (long)_rotation];
    RenderOutlinedText(rotationText,
                      NSMakePoint([self adjustX:0] + _panOffset.x, 35 + _fontSize + 4 + _panOffset.y),
                      msgColor, msgOutColor, headerFont);
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event {
    _lastMousePos = [self convertPoint:event.locationInWindow fromView:nil];
    _isPanning = YES;
}

- (void)mouseUp:(NSEvent *)event {
    _isPanning = NO;
}

- (void)mouseDragged:(NSEvent *)event {
    if (_isPanning) {
        NSPoint currentPos = [self convertPoint:event.locationInWindow fromView:nil];
        CGFloat dx = currentPos.x - _lastMousePos.x;
        CGFloat dy = currentPos.y - _lastMousePos.y;
        _panOffset = CGPointMake(_panOffset.x + dx, _panOffset.y + dy);
        _lastMousePos = currentPos;
        [self setNeedsDisplay:YES];
    }
}

- (void)scrollWheel:(NSEvent *)event {
    if (fabs(event.scrollingDeltaY) < 0.001) return;

    CGFloat zoomDelta = event.scrollingDeltaY > 0 ? 0.1 : -0.1;
    if (_zoom + zoomDelta < 0.1) return;

    NSPoint mouseLoc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat mx = (mouseLoc.x - _panOffset.x) / _zoom;
    CGFloat my = (mouseLoc.y - _panOffset.y) / _zoom;

    _zoom += zoomDelta;

    CGFloat sx = mouseLoc.x - (mx * _zoom);
    CGFloat sy = mouseLoc.y - (my * _zoom);
    _panOffset = CGPointMake(sx, sy);

    [self setNeedsDisplay:YES];
}

- (void)magnifyWithEvent:(NSEvent *)event {
    if (fabs(event.magnification) < 0.001) return;

    CGFloat zoomDelta = event.magnification > 0 ? 0.1 : -0.1;
    if (_zoom + zoomDelta < 0.1) return;

    NSPoint mouseLoc = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat mx = (mouseLoc.x - _panOffset.x) / _zoom;
    CGFloat my = (mouseLoc.y - _panOffset.y) / _zoom;

    _zoom += zoomDelta;

    CGFloat sx = mouseLoc.x - (mx * _zoom);
    CGFloat sy = mouseLoc.y - (my * _zoom);
    _panOffset = CGPointMake(sx, sy);

    [self setNeedsDisplay:YES];
}

- (void)mouseDoubleClick:(NSEvent *)event {
    [self resetView];
}

#pragma mark - Right-Click Context Menu

- (void)rightMouseDown:(NSEvent *)event {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Wiring Options"];

    [menu addItemWithTitle:@"Reset" action:@selector(menuReset:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Copy to Clipboard" action:@selector(menuCopyClipboard:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Export..." action:@selector(menuExport:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Export Large..." action:@selector(menuExportLarge:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *darkItem = [menu addItemWithTitle:@"Dark" action:@selector(menuDark:) keyEquivalent:@""];
    darkItem.state = (_colorTheme == XLWiringThemeDark) ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem *grayItem = [menu addItemWithTitle:@"Gray" action:@selector(menuGray:) keyEquivalent:@""];
    grayItem.state = (_colorTheme == XLWiringThemeGray) ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem *lightItem = [menu addItemWithTitle:@"Light" action:@selector(menuLight:) keyEquivalent:@""];
    lightItem.state = (_colorTheme == XLWiringThemeLight) ? NSControlStateValueOn : NSControlStateValueOff;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *smallerFont = [menu addItemWithTitle:@"Smaller Font" action:@selector(menuFontSmaller:) keyEquivalent:@""];
    if (_fontSize <= MIN_FONT_SIZE) smallerFont.enabled = NO;
    [menu addItemWithTitle:@"Larger Font" action:@selector(menuFontLarger:) keyEquivalent:@""];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *frontItem = [menu addItemWithTitle:@"Front" action:@selector(menuFront:) keyEquivalent:@""];
    frontItem.state = !_rearView ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem *rearItem = [menu addItemWithTitle:@"Rear" action:@selector(menuRear:) keyEquivalent:@""];
    rearItem.state = _rearView ? NSControlStateValueOn : NSControlStateValueOff;

    [menu addItemWithTitle:@"Rotate 90" action:@selector(menuRotate:) keyEquivalent:@""];

    for (NSMenuItem *item in menu.itemArray) {
        if (item.action) item.target = self;
    }

    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)menuReset:(id)sender {
    [self resetView];
}

- (void)menuExport:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"png"]];
    panel.nameFieldStringValue = [NSString stringWithFormat:@"%@_wiring.png", _modelName ?: @"model"];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSData *data = [self exportAsPNG];
            if (data) {
                [data writeToURL:panel.URL atomically:YES];
            }
        }
    }];
}

- (void)menuExportLarge:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"png"]];
    panel.nameFieldStringValue = [NSString stringWithFormat:@"%@_wiring_large.png", _modelName ?: @"model"];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSData *data = [self exportAsLargePNG];
            if (data) {
                [data writeToURL:panel.URL atomically:YES];
            }
        }
    }];
}

- (void)menuCopyClipboard:(id)sender {
    [self copyToClipboard];
}

- (void)menuDark:(id)sender {
    self.colorTheme = XLWiringThemeDark;
}

- (void)menuGray:(id)sender {
    self.colorTheme = XLWiringThemeGray;
}

- (void)menuLight:(id)sender {
    self.colorTheme = XLWiringThemeLight;
}

- (void)menuFontSmaller:(id)sender {
    self.fontSize = _fontSize - FONT_SIZE_INCREMENT;
}

- (void)menuFontLarger:(id)sender {
    self.fontSize = _fontSize + FONT_SIZE_INCREMENT;
}

- (void)menuFront:(id)sender {
    self.rearView = NO;
}

- (void)menuRear:(id)sender {
    self.rearView = YES;
}

- (void)menuRotate:(id)sender {
    if (!_hasRotated) {
        _hasRotated = YES;
    }
    self.rotation = _rotation + 90;
    _zoom = 1.0;
    _panOffset = CGPointZero;
    [self setNeedsDisplay:YES];
}

#pragma mark - Export

- (NSData *)exportAsPNG {
    return [self renderPNGWithWidth:(NSInteger)self.bounds.size.width
                             height:(NSInteger)self.bounds.size.height];
}

- (NSData *)exportAsLargePNG {
    return [self renderPNGWithWidth:4096 height:2048];
}

- (NSData *)renderPNGWithWidth:(NSInteger)w height:(NSInteger)h {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
                             initWithBitmapDataPlanes:NULL
                             pixelsWide:w
                             pixelsHigh:h
                             bitsPerSample:8
                             samplesPerPixel:4
                             hasAlpha:YES
                             isPlanar:NO
                             colorSpaceName:NSCalibratedRGBColorSpace
                             bytesPerRow:0
                             bitsPerPixel:0];

    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:ctx];

    CGFloat savedZoom = _zoom;
    CGPoint savedOffset = _panOffset;
    NSRect savedBounds = self.bounds;

    _zoom = 1.0;
    _panOffset = CGPointZero;

    NSRect exportBounds = NSMakeRect(0, 0, w, h);
    NSColor *bgColor = [NSColor colorWithCalibratedRed:_theme.bgR green:_theme.bgG blue:_theme.bgB alpha:1.0];
    [bgColor setFill];
    NSRectFill(exportBounds);

    // Temporarily adjust bounds for rendering
    [self setBoundsSize:exportBounds.size];
    [self drawNodes];
    [self setBoundsSize:savedBounds.size];

    _zoom = savedZoom;
    _panOffset = savedOffset;

    [NSGraphicsContext restoreGraphicsState];

    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

- (NSImage *)imageForPrinting {
    XLWiringTheme savedTheme = _colorTheme;
    self.colorTheme = XLWiringThemeLight;

    NSData *pngData = [self exportAsPNG];

    self.colorTheme = savedTheme;

    if (!pngData) return nil;
    return [[NSImage alloc] initWithData:pngData];
}

- (void)copyToClipboard {
    NSData *pngData = [self exportAsPNG];
    if (!pngData) return;

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];

    NSImage *image = [[NSImage alloc] initWithData:pngData];
    if (image) {
        [pasteboard writeObjects:@[image]];
    }
}

@end
