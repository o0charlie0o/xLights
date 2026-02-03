/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLBufferPanel.h"

static NSArray *kBufferStyleNames = nil;
static NSArray *kBufferTransformNames = nil;
static NSArray *kRotationOrderNames = nil;
static NSArray *kPresetNames = nil;

__attribute__((constructor))
static void initializeBufferConstants(void) {
    kBufferStyleNames = @[
        @"Default",
        @"Per Preview",
        @"Per Preview Camera",
        @"Single Line",
        @"As Pixel",
        @"Horizontal Per Strand",
        @"Vertical Per Strand",
        @"Horizontal Per Node",
        @"Vertical Per Node",
        @"Horizontal Per Model",
        @"Vertical Per Model",
        @"Horizontal Stack",
        @"Vertical Stack",
        @"Overlay - Centered",
        @"Overlay - Scaled",
        @"SubBuffer"
    ];

    kBufferTransformNames = @[
        @"None",
        @"Flip Horizontal",
        @"Flip Vertical",
        @"Flip Both",
        @"Rotate 90",
        @"Rotate 180",
        @"Rotate 270",
        @"Rotate 90 + Flip H",
        @"Rotate 90 + Flip V"
    ];

    kRotationOrderNames = @[
        @"X-Y-Z",
        @"X-Z-Y",
        @"Y-X-Z",
        @"Y-Z-X",
        @"Z-X-Y",
        @"Z-Y-X"
    ];

    kPresetNames = @[
        @"None",
        @"Spin CW",
        @"Spin CCW",
        @"Zoom In",
        @"Zoom Out",
        @"Spin CW + Zoom In",
        @"Spin CW + Zoom Out",
        @"Spin CCW + Zoom In",
        @"Spin CCW + Zoom Out"
    ];
}

#pragma mark - XLSubBufferSelectionView

@interface XLSubBufferSelectionView ()
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) NSPoint dragStart;
@property (nonatomic, assign) int dragHandle; // 0=none, 1-4=corners, 5-8=edges
@end

@implementation XLSubBufferSelectionView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _leftBound = 0;
        _bottomBound = 0;
        _rightBound = 100;
        _topBound = 100;
        _isDragging = NO;
        _dragHandle = 0;

        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor controlBackgroundColor] CGColor];
        self.layer.cornerRadius = 4.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [[NSColor separatorColor] CGColor];
    }
    return self;
}

- (NSString *)subBufferString {
    return [NSString stringWithFormat:@"%.0f,%.0f,%.0f,%.0f",
            _leftBound, _bottomBound, _rightBound, _topBound];
}

- (void)setFromSubBufferString:(NSString *)string {
    NSArray *parts = [string componentsSeparatedByString:@","];
    if (parts.count >= 4) {
        _leftBound = [parts[0] floatValue];
        _bottomBound = [parts[1] floatValue];
        _rightBound = [parts[2] floatValue];
        _topBound = [parts[3] floatValue];
        [self setNeedsDisplay:YES];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;
    CGFloat margin = 10.0;
    NSRect drawRect = NSInsetRect(bounds, margin, margin);

    // Draw background grid
    [[NSColor separatorColor] setStroke];
    NSBezierPath *gridPath = [NSBezierPath bezierPath];
    gridPath.lineWidth = 0.5;

    for (int i = 0; i <= 10; i++) {
        CGFloat x = drawRect.origin.x + (i * drawRect.size.width / 10.0);
        [gridPath moveToPoint:NSMakePoint(x, drawRect.origin.y)];
        [gridPath lineToPoint:NSMakePoint(x, drawRect.origin.y + drawRect.size.height)];

        CGFloat y = drawRect.origin.y + (i * drawRect.size.height / 10.0);
        [gridPath moveToPoint:NSMakePoint(drawRect.origin.x, y)];
        [gridPath lineToPoint:NSMakePoint(drawRect.origin.x + drawRect.size.width, y)];
    }

    CGFloat pattern[] = {2.0, 2.0};
    [gridPath setLineDash:pattern count:2 phase:0];
    [gridPath stroke];

    // Draw sub-buffer region
    CGFloat regionX = drawRect.origin.x + ((_leftBound + 100) / 200.0) * drawRect.size.width;
    CGFloat regionY = drawRect.origin.y + ((_bottomBound + 100) / 200.0) * drawRect.size.height;
    CGFloat regionW = ((_rightBound - _leftBound) / 200.0) * drawRect.size.width;
    CGFloat regionH = ((_topBound - _bottomBound) / 200.0) * drawRect.size.height;

    NSRect regionRect = NSMakeRect(regionX, regionY, regionW, regionH);

    NSColor *fillColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.2];
    [fillColor setFill];
    NSRectFill(regionRect);

    [[NSColor controlAccentColor] setStroke];
    NSBezierPath *regionPath = [NSBezierPath bezierPathWithRect:regionRect];
    regionPath.lineWidth = 2.0;
    [regionPath stroke];

    // Draw handles
    CGFloat handleSize = 8.0;
    NSColor *handleColor = [NSColor controlAccentColor];
    [handleColor setFill];

    // Corner handles
    NSRect handles[4] = {
        NSMakeRect(regionRect.origin.x - handleSize/2, regionRect.origin.y - handleSize/2, handleSize, handleSize),
        NSMakeRect(NSMaxX(regionRect) - handleSize/2, regionRect.origin.y - handleSize/2, handleSize, handleSize),
        NSMakeRect(NSMaxX(regionRect) - handleSize/2, NSMaxY(regionRect) - handleSize/2, handleSize, handleSize),
        NSMakeRect(regionRect.origin.x - handleSize/2, NSMaxY(regionRect) - handleSize/2, handleSize, handleSize)
    };

    for (int i = 0; i < 4; i++) {
        NSRectFill(handles[i]);
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect bounds = self.bounds;
    CGFloat margin = 10.0;
    NSRect drawRect = NSInsetRect(bounds, margin, margin);

    CGFloat regionX = drawRect.origin.x + ((_leftBound + 100) / 200.0) * drawRect.size.width;
    CGFloat regionY = drawRect.origin.y + ((_bottomBound + 100) / 200.0) * drawRect.size.height;
    CGFloat regionW = ((_rightBound - _leftBound) / 200.0) * drawRect.size.width;
    CGFloat regionH = ((_topBound - _bottomBound) / 200.0) * drawRect.size.height;

    CGFloat handleSize = 12.0;

    // Check corner handles
    NSRect handles[4] = {
        NSMakeRect(regionX - handleSize/2, regionY - handleSize/2, handleSize, handleSize),
        NSMakeRect(regionX + regionW - handleSize/2, regionY - handleSize/2, handleSize, handleSize),
        NSMakeRect(regionX + regionW - handleSize/2, regionY + regionH - handleSize/2, handleSize, handleSize),
        NSMakeRect(regionX - handleSize/2, regionY + regionH - handleSize/2, handleSize, handleSize)
    };

    _dragHandle = 0;
    for (int i = 0; i < 4; i++) {
        if (NSPointInRect(point, handles[i])) {
            _dragHandle = i + 1;
            break;
        }
    }

    _isDragging = (_dragHandle != 0);
    _dragStart = point;
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_isDragging) return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect bounds = self.bounds;
    CGFloat margin = 10.0;
    NSRect drawRect = NSInsetRect(bounds, margin, margin);

    // Convert point to sub-buffer coordinates
    float newX = ((point.x - drawRect.origin.x) / drawRect.size.width) * 200.0 - 100.0;
    float newY = ((point.y - drawRect.origin.y) / drawRect.size.height) * 200.0 - 100.0;

    newX = MAX(-100, MIN(200, newX));
    newY = MAX(-100, MIN(200, newY));

    switch (_dragHandle) {
        case 1: // Bottom-left
            _leftBound = MIN(newX, _rightBound - 1);
            _bottomBound = MIN(newY, _topBound - 1);
            break;
        case 2: // Bottom-right
            _rightBound = MAX(newX, _leftBound + 1);
            _bottomBound = MIN(newY, _topBound - 1);
            break;
        case 3: // Top-right
            _rightBound = MAX(newX, _leftBound + 1);
            _topBound = MAX(newY, _bottomBound + 1);
            break;
        case 4: // Top-left
            _leftBound = MIN(newX, _rightBound - 1);
            _topBound = MAX(newY, _bottomBound + 1);
            break;
    }

    [self setNeedsDisplay:YES];

    if ([_delegate respondsToSelector:@selector(subBufferSelectionViewDidChange:)]) {
        [_delegate subBufferSelectionViewDidChange:self];
    }
}

- (void)mouseUp:(NSEvent *)event {
    _isDragging = NO;
    _dragHandle = 0;
}

@end

#pragma mark - XLBufferPanel

@interface XLBufferPanel () <XLSubBufferSelectionDelegate>
@property (nonatomic, strong) NSTabView *tabView;

// Buffer tab controls
@property (nonatomic, strong) NSPopUpButton *internalBufferStylePopup;
@property (nonatomic, strong) NSPopUpButton *internalBufferTransformPopup;
@property (nonatomic, strong) NSStepper *internalBufferStaggerStepper;
@property (nonatomic, strong) NSTextField *bufferStaggerField;
@property (nonatomic, strong) NSPopUpButton *internalCameraPopup;
@property (nonatomic, strong) NSSlider *internalBlurSlider;
@property (nonatomic, strong) NSTextField *blurField;
@property (nonatomic, strong) NSButton *internalOverlayBackgroundCheckbox;

// RotoZoom tab controls
@property (nonatomic, strong) NSPopUpButton *internalPresetPopup;
@property (nonatomic, strong) NSSlider *internalRotationSlider;
@property (nonatomic, strong) NSTextField *rotationField;
@property (nonatomic, strong) NSSlider *internalRotationsSlider;
@property (nonatomic, strong) NSTextField *rotationsField;
@property (nonatomic, strong) NSSlider *internalPivotXSlider;
@property (nonatomic, strong) NSTextField *pivotXField;
@property (nonatomic, strong) NSSlider *internalPivotYSlider;
@property (nonatomic, strong) NSTextField *pivotYField;
@property (nonatomic, strong) NSSlider *internalZoomSlider;
@property (nonatomic, strong) NSTextField *zoomField;
@property (nonatomic, strong) NSSlider *internalZoomQualitySlider;
@property (nonatomic, strong) NSTextField *zoomQualityField;
@property (nonatomic, strong) NSSlider *internalXRotationSlider;
@property (nonatomic, strong) NSTextField *xRotationField;
@property (nonatomic, strong) NSSlider *internalYRotationSlider;
@property (nonatomic, strong) NSTextField *yRotationField;
@property (nonatomic, strong) NSSlider *internalXPivotSlider;
@property (nonatomic, strong) NSTextField *xPivotField;
@property (nonatomic, strong) NSSlider *internalYPivotSlider;
@property (nonatomic, strong) NSTextField *yPivotField;
@property (nonatomic, strong) NSPopUpButton *internalRotationOrderPopup;

// SubBuffer tab
@property (nonatomic, strong) XLSubBufferSelectionView *internalSubBufferView;
@end

@implementation XLBufferPanel

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _resetOnEffectChange = NO;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    _tabView = [[NSTabView alloc] initWithFrame:self.bounds];
    _tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    [self setupBufferTab];
    [self setupRotoZoomTab];
    [self setupSubBufferTab];

    [self addSubview:_tabView];
}

- (void)setupBufferTab {
    NSTabViewItem *bufferTab = [[NSTabViewItem alloc] initWithIdentifier:@"buffer"];
    bufferTab.label = @"Buffer";

    NSView *content = bufferTab.view;
    CGFloat y = content.bounds.size.height - 40;
    CGFloat labelWidth = 120.0;
    CGFloat controlWidth = 180.0;

    // Buffer Style
    NSTextField *styleLabel = [NSTextField labelWithString:@"Buffer Style:"];
    styleLabel.frame = NSMakeRect(10, y, labelWidth, 20);
    [content addSubview:styleLabel];

    _internalBufferStylePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(labelWidth + 15, y - 3, controlWidth, 26) pullsDown:NO];
    for (NSString *name in kBufferStyleNames) {
        [_internalBufferStylePopup addItemWithTitle:name];
    }
    _internalBufferStylePopup.target = self;
    _internalBufferStylePopup.action = @selector(controlChanged:);
    [content addSubview:_internalBufferStylePopup];

    y -= 35;

    // Camera
    NSTextField *cameraLabel = [NSTextField labelWithString:@"Camera:"];
    cameraLabel.frame = NSMakeRect(10, y, labelWidth, 20);
    [content addSubview:cameraLabel];

    _internalCameraPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(labelWidth + 15, y - 3, controlWidth, 26) pullsDown:NO];
    [_internalCameraPopup addItemWithTitle:@"2D"];
    [_internalCameraPopup addItemWithTitle:@"3D"];
    _internalCameraPopup.target = self;
    _internalCameraPopup.action = @selector(controlChanged:);
    [content addSubview:_internalCameraPopup];

    y -= 35;

    // Buffer Transform
    NSTextField *transformLabel = [NSTextField labelWithString:@"Transform:"];
    transformLabel.frame = NSMakeRect(10, y, labelWidth, 20);
    [content addSubview:transformLabel];

    _internalBufferTransformPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(labelWidth + 15, y - 3, controlWidth, 26) pullsDown:NO];
    for (NSString *name in kBufferTransformNames) {
        [_internalBufferTransformPopup addItemWithTitle:name];
    }
    _internalBufferTransformPopup.target = self;
    _internalBufferTransformPopup.action = @selector(controlChanged:);
    [content addSubview:_internalBufferTransformPopup];

    y -= 35;

    // Buffer Stagger
    NSTextField *staggerLabel = [NSTextField labelWithString:@"Stagger:"];
    staggerLabel.frame = NSMakeRect(10, y, labelWidth, 20);
    [content addSubview:staggerLabel];

    _bufferStaggerField = [[NSTextField alloc] initWithFrame:NSMakeRect(labelWidth + 15, y - 2, 50, 22)];
    _bufferStaggerField.integerValue = 0;
    [content addSubview:_bufferStaggerField];

    _internalBufferStaggerStepper = [[NSStepper alloc] initWithFrame:NSMakeRect(labelWidth + 70, y - 2, 20, 22)];
    _internalBufferStaggerStepper.minValue = 0;
    _internalBufferStaggerStepper.maxValue = 1000;
    _internalBufferStaggerStepper.increment = 1;
    _internalBufferStaggerStepper.target = self;
    _internalBufferStaggerStepper.action = @selector(stepperChanged:);
    [content addSubview:_internalBufferStaggerStepper];

    y -= 35;

    // Blur
    NSTextField *blurLabel = [NSTextField labelWithString:@"Blur:"];
    blurLabel.frame = NSMakeRect(10, y, labelWidth, 20);
    [content addSubview:blurLabel];

    _internalBlurSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(labelWidth + 15, y, controlWidth - 60, 20)];
    _internalBlurSlider.minValue = XL_BLUR_MIN;
    _internalBlurSlider.maxValue = XL_BLUR_MAX;
    _internalBlurSlider.integerValue = 1;
    _internalBlurSlider.target = self;
    _internalBlurSlider.action = @selector(sliderChanged:);
    [content addSubview:_internalBlurSlider];

    _blurField = [[NSTextField alloc] initWithFrame:NSMakeRect(labelWidth + 15 + controlWidth - 55, y - 2, 50, 22)];
    _blurField.integerValue = 1;
    [content addSubview:_blurField];

    y -= 35;

    // Overlay Background
    _internalOverlayBackgroundCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(10, y, 200, 20)];
    _internalOverlayBackgroundCheckbox.buttonType = NSButtonTypeSwitch;
    _internalOverlayBackgroundCheckbox.title = @"Overlay Background";
    _internalOverlayBackgroundCheckbox.target = self;
    _internalOverlayBackgroundCheckbox.action = @selector(controlChanged:);
    [content addSubview:_internalOverlayBackgroundCheckbox];

    [_tabView addTabViewItem:bufferTab];
}

- (void)setupRotoZoomTab {
    NSTabViewItem *rotoZoomTab = [[NSTabViewItem alloc] initWithIdentifier:@"rotoZoom"];
    rotoZoomTab.label = @"RotoZoom";

    NSView *content = rotoZoomTab.view;
    CGFloat y = content.bounds.size.height - 40;
    CGFloat labelWidth = 100.0;
    CGFloat sliderWidth = 140.0;

    // Preset
    NSTextField *presetLabel = [NSTextField labelWithString:@"Preset:"];
    presetLabel.frame = NSMakeRect(10, y, labelWidth, 20);
    [content addSubview:presetLabel];

    _internalPresetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(labelWidth + 15, y - 3, 150, 26) pullsDown:NO];
    for (NSString *name in kPresetNames) {
        [_internalPresetPopup addItemWithTitle:name];
    }
    _internalPresetPopup.target = self;
    _internalPresetPopup.action = @selector(presetChanged:);
    [content addSubview:_internalPresetPopup];

    y -= 35;

    // Rotation
    NSArray *rotationControls = [self createSliderRowInView:content label:@"Rotation:" y:y
                                                        min:XL_ROTATION_MIN max:XL_ROTATION_MAX value:0
                                                 labelWidth:labelWidth sliderWidth:sliderWidth];
    _internalRotationSlider = rotationControls[0];
    _rotationField = rotationControls[1];
    y -= 30;

    // Rotations
    NSArray *rotationsControls = [self createSliderRowInView:content label:@"Rotations:" y:y
                                                         min:XL_ROTATIONS_MIN max:XL_ROTATIONS_MAX value:0
                                                  labelWidth:labelWidth sliderWidth:sliderWidth];
    _internalRotationsSlider = rotationsControls[0];
    _rotationsField = rotationsControls[1];
    y -= 30;

    // Pivot X
    NSArray *pivotXControls = [self createSliderRowInView:content label:@"Pivot X:" y:y
                                                      min:XL_PIVOT_MIN max:XL_PIVOT_MAX value:50
                                               labelWidth:labelWidth sliderWidth:sliderWidth];
    _internalPivotXSlider = pivotXControls[0];
    _pivotXField = pivotXControls[1];
    y -= 30;

    // Pivot Y
    NSArray *pivotYControls = [self createSliderRowInView:content label:@"Pivot Y:" y:y
                                                      min:XL_PIVOT_MIN max:XL_PIVOT_MAX value:50
                                               labelWidth:labelWidth sliderWidth:sliderWidth];
    _internalPivotYSlider = pivotYControls[0];
    _pivotYField = pivotYControls[1];
    y -= 30;

    // Zoom
    NSArray *zoomControls = [self createSliderRowInView:content label:@"Zoom:" y:y
                                                    min:XL_ZOOM_MIN max:XL_ZOOM_MAX value:10
                                             labelWidth:labelWidth sliderWidth:sliderWidth];
    _internalZoomSlider = zoomControls[0];
    _zoomField = zoomControls[1];
    y -= 30;

    // Zoom Quality
    NSArray *qualityControls = [self createSliderRowInView:content label:@"Quality:" y:y
                                                       min:1 max:10 value:1
                                                labelWidth:labelWidth sliderWidth:sliderWidth];
    _internalZoomQualitySlider = qualityControls[0];
    _zoomQualityField = qualityControls[1];
    y -= 30;

    // X Rotation
    NSArray *xRotControls = [self createSliderRowInView:content label:@"X Rotation:" y:y
                                                    min:XL_XY_ROTATION_MIN max:XL_XY_ROTATION_MAX value:0
                                             labelWidth:labelWidth sliderWidth:sliderWidth];
    _internalXRotationSlider = xRotControls[0];
    _xRotationField = xRotControls[1];
    y -= 30;

    // X Pivot
    NSArray *xPivotControls = [self createSliderRowInView:content label:@"X Pivot:" y:y
                                                      min:XL_PIVOT_MIN max:XL_PIVOT_MAX value:50
                                               labelWidth:labelWidth sliderWidth:sliderWidth];
    _internalXPivotSlider = xPivotControls[0];
    _xPivotField = xPivotControls[1];
    y -= 30;

    // Y Rotation
    NSArray *yRotControls = [self createSliderRowInView:content label:@"Y Rotation:" y:y
                                                    min:XL_XY_ROTATION_MIN max:XL_XY_ROTATION_MAX value:0
                                             labelWidth:labelWidth sliderWidth:sliderWidth];
    _internalYRotationSlider = yRotControls[0];
    _yRotationField = yRotControls[1];
    y -= 30;

    // Y Pivot
    NSArray *yPivotControls = [self createSliderRowInView:content label:@"Y Pivot:" y:y
                                                      min:XL_PIVOT_MIN max:XL_PIVOT_MAX value:50
                                               labelWidth:labelWidth sliderWidth:sliderWidth];
    _internalYPivotSlider = yPivotControls[0];
    _yPivotField = yPivotControls[1];
    y -= 30;

    // Rotation Order
    NSTextField *orderLabel = [NSTextField labelWithString:@"Order:"];
    orderLabel.frame = NSMakeRect(10, y, labelWidth, 20);
    [content addSubview:orderLabel];

    _internalRotationOrderPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(labelWidth + 15, y - 3, 100, 26) pullsDown:NO];
    for (NSString *name in kRotationOrderNames) {
        [_internalRotationOrderPopup addItemWithTitle:name];
    }
    _internalRotationOrderPopup.target = self;
    _internalRotationOrderPopup.action = @selector(controlChanged:);
    [content addSubview:_internalRotationOrderPopup];

    [_tabView addTabViewItem:rotoZoomTab];
}

/// Helper method that returns an array containing [NSSlider, NSTextField].
- (NSArray *)createSliderRowInView:(NSView *)content label:(NSString *)labelText y:(CGFloat)y
                               min:(double)minVal max:(double)maxVal value:(double)value
                        labelWidth:(CGFloat)labelWidth sliderWidth:(CGFloat)sliderWidth {

    NSTextField *label = [NSTextField labelWithString:labelText];
    label.frame = NSMakeRect(10, y, labelWidth, 20);
    [content addSubview:label];

    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(labelWidth + 15, y, sliderWidth, 20)];
    slider.minValue = minVal;
    slider.maxValue = maxVal;
    slider.doubleValue = value;
    slider.target = self;
    slider.action = @selector(sliderChanged:);
    [content addSubview:slider];

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(labelWidth + 20 + sliderWidth, y - 2, 50, 22)];
    field.doubleValue = value;
    [content addSubview:field];

    return @[slider, field];
}

- (void)setupSubBufferTab {
    NSTabViewItem *subBufferTab = [[NSTabViewItem alloc] initWithIdentifier:@"subBuffer"];
    subBufferTab.label = @"SubBuffer";

    NSView *content = subBufferTab.view;

    _internalSubBufferView = [[XLSubBufferSelectionView alloc] initWithFrame:NSMakeRect(10, 10, content.bounds.size.width - 20, content.bounds.size.height - 20)];
    _internalSubBufferView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _internalSubBufferView.delegate = self;
    [content addSubview:_internalSubBufferView];

    [_tabView addTabViewItem:subBufferTab];
}

#pragma mark - Property Accessors

- (NSPopUpButton *)bufferStylePopup { return _internalBufferStylePopup; }
- (NSPopUpButton *)bufferTransformPopup { return _internalBufferTransformPopup; }
- (NSStepper *)bufferStaggerStepper { return _internalBufferStaggerStepper; }
- (NSPopUpButton *)cameraPopup { return _internalCameraPopup; }
- (NSSlider *)blurSlider { return _internalBlurSlider; }
- (NSButton *)overlayBackgroundCheckbox { return _internalOverlayBackgroundCheckbox; }
- (NSSlider *)rotationSlider { return _internalRotationSlider; }
- (NSSlider *)rotationsSlider { return _internalRotationsSlider; }
- (NSSlider *)pivotXSlider { return _internalPivotXSlider; }
- (NSSlider *)pivotYSlider { return _internalPivotYSlider; }
- (NSSlider *)zoomSlider { return _internalZoomSlider; }
- (NSSlider *)zoomQualitySlider { return _internalZoomQualitySlider; }
- (NSSlider *)xRotationSlider { return _internalXRotationSlider; }
- (NSSlider *)yRotationSlider { return _internalYRotationSlider; }
- (NSSlider *)xPivotSlider { return _internalXPivotSlider; }
- (NSSlider *)yPivotSlider { return _internalYPivotSlider; }
- (NSPopUpButton *)rotationOrderPopup { return _internalRotationOrderPopup; }
- (NSPopUpButton *)presetPopup { return _internalPresetPopup; }
- (XLSubBufferSelectionView *)subBufferView { return _internalSubBufferView; }

#pragma mark - Settings

- (XLBufferSettings)bufferSettings {
    XLBufferSettings settings = {0};

    settings.bufferStyle = (int)_internalBufferStylePopup.indexOfSelectedItem;
    settings.bufferTransform = (int)_internalBufferTransformPopup.indexOfSelectedItem;
    settings.bufferStagger = (int)_internalBufferStaggerStepper.integerValue;
    settings.blur = (int)_internalBlurSlider.integerValue;
    settings.overlayBackground = (_internalOverlayBackgroundCheckbox.state == NSControlStateValueOn);

    NSString *camera = _internalCameraPopup.selectedItem.title;
    strlcpy(settings.cameraName, [camera UTF8String], sizeof(settings.cameraName));

    settings.rotation = _internalRotationSlider.floatValue;
    settings.rotations = _internalRotationsSlider.floatValue;
    settings.pivotX = _internalPivotXSlider.floatValue;
    settings.pivotY = _internalPivotYSlider.floatValue;
    settings.zoom = _internalZoomSlider.floatValue;
    settings.zoomQuality = (int)_internalZoomQualitySlider.integerValue;
    settings.xRotation = _internalXRotationSlider.floatValue;
    settings.yRotation = _internalYRotationSlider.floatValue;
    settings.xPivot = _internalXPivotSlider.floatValue;
    settings.yPivot = _internalYPivotSlider.floatValue;
    settings.rotationOrder = (int)_internalRotationOrderPopup.indexOfSelectedItem;

    settings.subBufferLeft = _internalSubBufferView.leftBound;
    settings.subBufferBottom = _internalSubBufferView.bottomBound;
    settings.subBufferRight = _internalSubBufferView.rightBound;
    settings.subBufferTop = _internalSubBufferView.topBound;

    return settings;
}

- (void)setBufferSettings:(XLBufferSettings)settings {
    [_internalBufferStylePopup selectItemAtIndex:settings.bufferStyle];
    [_internalBufferTransformPopup selectItemAtIndex:settings.bufferTransform];
    _internalBufferStaggerStepper.integerValue = settings.bufferStagger;
    _bufferStaggerField.integerValue = settings.bufferStagger;
    _internalBlurSlider.integerValue = settings.blur;
    _blurField.integerValue = settings.blur;
    _internalOverlayBackgroundCheckbox.state = settings.overlayBackground ? NSControlStateValueOn : NSControlStateValueOff;

    NSString *camera = [NSString stringWithUTF8String:settings.cameraName];
    if ([_internalCameraPopup itemWithTitle:camera]) {
        [_internalCameraPopup selectItemWithTitle:camera];
    }

    _internalRotationSlider.floatValue = settings.rotation;
    _rotationField.floatValue = settings.rotation;
    _internalRotationsSlider.floatValue = settings.rotations;
    _rotationsField.floatValue = settings.rotations;
    _internalPivotXSlider.floatValue = settings.pivotX;
    _pivotXField.floatValue = settings.pivotX;
    _internalPivotYSlider.floatValue = settings.pivotY;
    _pivotYField.floatValue = settings.pivotY;
    _internalZoomSlider.floatValue = settings.zoom;
    _zoomField.floatValue = settings.zoom;
    _internalZoomQualitySlider.integerValue = settings.zoomQuality;
    _zoomQualityField.integerValue = settings.zoomQuality;
    _internalXRotationSlider.floatValue = settings.xRotation;
    _xRotationField.floatValue = settings.xRotation;
    _internalYRotationSlider.floatValue = settings.yRotation;
    _yRotationField.floatValue = settings.yRotation;
    _internalXPivotSlider.floatValue = settings.xPivot;
    _xPivotField.floatValue = settings.xPivot;
    _internalYPivotSlider.floatValue = settings.yPivot;
    _yPivotField.floatValue = settings.yPivot;
    [_internalRotationOrderPopup selectItemAtIndex:settings.rotationOrder];

    _internalSubBufferView.leftBound = settings.subBufferLeft;
    _internalSubBufferView.bottomBound = settings.subBufferBottom;
    _internalSubBufferView.rightBound = settings.subBufferRight;
    _internalSubBufferView.topBound = settings.subBufferTop;
    [_internalSubBufferView setNeedsDisplay:YES];
}

- (NSString *)bufferString {
    // Generate string representation similar to wxWidgets format
    XLBufferSettings settings = [self bufferSettings];
    return [NSString stringWithFormat:@"B_CHOICE_BufferStyle=%d,B_CHOICE_BufferTransform=%d,B_SPINCTRL_BufferStagger=%d,B_SLIDER_Blur=%d",
            settings.bufferStyle, settings.bufferTransform, settings.bufferStagger, settings.blur];
}

- (void)setFromBufferString:(NSString *)string {
    // Parse string and set controls
    // Implementation would parse key=value pairs
}

- (void)updateBufferStylesForModel:(NSString *)modelName {
    // Model-specific buffer styles would be updated here
}

- (void)updateCameraChoicesForModel:(NSString *)modelName {
    // Model-specific camera choices would be updated here
}

- (void)setDefaultControlsForModel:(NSString *)modelName optionBased:(BOOL)optionBased {
    [self resetToDefaults];
}

- (void)resetToDefaults {
    XLBufferSettings defaults = {0};
    defaults.bufferStyle = 0;
    defaults.bufferTransform = 0;
    defaults.bufferStagger = 0;
    defaults.blur = 1;
    defaults.overlayBackground = NO;
    strlcpy(defaults.cameraName, "2D", sizeof(defaults.cameraName));
    defaults.rotation = 0;
    defaults.rotations = 0;
    defaults.pivotX = 50;
    defaults.pivotY = 50;
    defaults.zoom = 10;
    defaults.zoomQuality = 1;
    defaults.xRotation = 0;
    defaults.yRotation = 0;
    defaults.xPivot = 50;
    defaults.yPivot = 50;
    defaults.rotationOrder = 0;
    defaults.subBufferLeft = 0;
    defaults.subBufferBottom = 0;
    defaults.subBufferRight = 100;
    defaults.subBufferTop = 100;

    [self setBufferSettings:defaults];
}

- (void)validateSettings {
    // Ensure settings are within valid ranges
}

#pragma mark - Actions

- (void)controlChanged:(id)sender {
    [self notifyDelegate];
}

- (void)sliderChanged:(NSSlider *)sender {
    // Update corresponding text field
    if (sender == _internalBlurSlider) {
        _blurField.integerValue = sender.integerValue;
    } else if (sender == _internalRotationSlider) {
        _rotationField.floatValue = sender.floatValue;
    } else if (sender == _internalRotationsSlider) {
        _rotationsField.floatValue = sender.floatValue;
    } else if (sender == _internalPivotXSlider) {
        _pivotXField.floatValue = sender.floatValue;
    } else if (sender == _internalPivotYSlider) {
        _pivotYField.floatValue = sender.floatValue;
    } else if (sender == _internalZoomSlider) {
        _zoomField.floatValue = sender.floatValue;
    } else if (sender == _internalZoomQualitySlider) {
        _zoomQualityField.integerValue = sender.integerValue;
    } else if (sender == _internalXRotationSlider) {
        _xRotationField.floatValue = sender.floatValue;
    } else if (sender == _internalYRotationSlider) {
        _yRotationField.floatValue = sender.floatValue;
    } else if (sender == _internalXPivotSlider) {
        _xPivotField.floatValue = sender.floatValue;
    } else if (sender == _internalYPivotSlider) {
        _yPivotField.floatValue = sender.floatValue;
    }

    [self notifyDelegate];
}

- (void)stepperChanged:(NSStepper *)sender {
    _bufferStaggerField.integerValue = sender.integerValue;
    [self notifyDelegate];
}

- (void)presetChanged:(NSPopUpButton *)sender {
    NSInteger preset = sender.indexOfSelectedItem;

    // Apply preset values
    switch (preset) {
        case 1: // Spin CW
            _internalRotationSlider.floatValue = 0;
            _internalRotationsSlider.floatValue = 10;
            break;
        case 2: // Spin CCW
            _internalRotationSlider.floatValue = 100;
            _internalRotationsSlider.floatValue = 10;
            break;
        case 3: // Zoom In
            _internalZoomSlider.floatValue = 0;
            break;
        case 4: // Zoom Out
            _internalZoomSlider.floatValue = 30;
            break;
        default:
            break;
    }

    [self notifyDelegate];
}

- (void)notifyDelegate {
    if ([_delegate respondsToSelector:@selector(bufferPanelSettingsDidChange:)]) {
        [_delegate bufferPanelSettingsDidChange:self];
    }
}

#pragma mark - XLSubBufferSelectionDelegate

- (void)subBufferSelectionViewDidChange:(XLSubBufferSelectionView *)view {
    [self notifyDelegate];
}

@end
