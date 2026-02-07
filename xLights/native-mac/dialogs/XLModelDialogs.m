/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLModelDialogs.h"
#import "XLWiringDiagramView.h"
#import "XLVideoModelGenerator.h"
#import "../XLEngineBridge.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <AVFoundation/AVFoundation.h>

static const CGFloat kLabelWidth = 130.0;

#pragma mark - XLModelChainDialog

@interface XLModelChainDialog ()

@property (nonatomic, strong) NSPopUpButton *chainFromPopup;
@property (nonatomic, strong) NSTextField *currentModelLabel;

@end

@implementation XLModelChainDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Model Chaining";
        self.minWidth = 400;
        self.minHeight = 180;
        _availableModels = @[];
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Current model info
    _currentModelLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Configuring chain for: %@", _modelName ?: @"(none)"]];
    _currentModelLabel.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:_currentModelLabel];

    // Chain from selection
    _chainFromPopup = [XLBaseSheetController createPopUpButton];
    [_chainFromPopup addItemWithTitle:@"(Start of chain)"];

    for (NSString *model in _availableModels) {
        if (![model isEqualToString:_modelName]) {
            [_chainFromPopup addItemWithTitle:model];
        }
    }

    if (_chainFromModel) {
        [_chainFromPopup selectItemWithTitle:_chainFromModel];
    }

    NSStackView *chainRow = [XLBaseSheetController formRowWithLabel:@"Chain From:"
                                                            control:_chainFromPopup
                                                         labelWidth:kLabelWidth];
    [stack addArrangedSubview:chainRow];

    // Info text
    NSTextField *infoLabel = [NSTextField wrappingLabelWithString:
        @"When chained, this model's starting channel will follow the end of the selected model."];
    infoLabel.textColor = [NSColor secondaryLabelColor];
    infoLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:infoLabel];
    [infoLabel.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [infoLabel.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    return stack;
}

- (void)okClicked:(id)sender {
    if (_chainFromPopup.indexOfSelectedItem == 0) {
        _chainFromModel = nil;
    } else {
        _chainFromModel = _chainFromPopup.selectedItem.title;
    }
    [super okClicked:sender];
}

@end

#pragma mark - XLStrandNodeNamesDialog

@interface XLStrandNodeNamesDialog () <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableStrandNames;
@property (nonatomic, strong) NSMutableArray<NSMutableArray<NSString *> *> *mutableNodeNames;

@end

@implementation XLStrandNodeNamesDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Strand/Node Names";
        self.minWidth = 450;
        self.minHeight = 400;
        _strandCount = 1;
        _mutableStrandNames = [NSMutableArray array];
        _mutableNodeNames = [NSMutableArray array];
        _nodesPerStrand = @[];
    }
    return self;
}

- (void)setStrandNames:(NSArray<NSString *> *)strandNames {
    _mutableStrandNames = [strandNames mutableCopy];
}

- (NSArray<NSString *> *)strandNames {
    return [_mutableStrandNames copy];
}

- (void)setNodeNames:(NSArray<NSArray<NSString *> *> *)nodeNames {
    _mutableNodeNames = [NSMutableArray array];
    for (NSArray<NSString *> *nodes in nodeNames) {
        [_mutableNodeNames addObject:[nodes mutableCopy]];
    }
}

- (NSArray<NSArray<NSString *> *> *)nodeNames {
    return [_mutableNodeNames copy];
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Model info
    NSTextField *modelLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Model: %@", _modelName ?: @"(none)"]];
    modelLabel.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:modelLabel];

    // Outline view for strands and nodes
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:280].active = YES;

    _outlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
    _outlineView.dataSource = self;
    _outlineView.delegate = self;
    _outlineView.rowHeight = 24;
    _outlineView.usesAlternatingRowBackgroundColors = YES;

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Strand/Node";
    nameColumn.width = 150;
    [_outlineView addTableColumn:nameColumn];

    NSTableColumn *customNameColumn = [[NSTableColumn alloc] initWithIdentifier:@"customName"];
    customNameColumn.title = @"Custom Name";
    customNameColumn.width = 200;
    customNameColumn.editable = YES;
    [_outlineView addTableColumn:customNameColumn];

    _outlineView.outlineTableColumn = nameColumn;

    scrollView.documentView = _outlineView;

    [stack addArrangedSubview:scrollView];
    [scrollView.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [scrollView.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    return stack;
}

- (void)sheetDidLoad {
    [_outlineView reloadData];
    [_outlineView expandItem:nil expandChildren:YES];
}

// NSOutlineViewDataSource
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nil) {
        return _strandCount;
    }
    if ([item isKindOfClass:[NSNumber class]]) {
        NSInteger strandIndex = [item integerValue];
        if (strandIndex < _nodesPerStrand.count) {
            return [_nodesPerStrand[strandIndex] integerValue];
        }
    }
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nil) {
        return @(index);
    }
    return @[@([item integerValue]), @(index)];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[NSNumber class]];
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if ([tableColumn.identifier isEqualToString:@"name"]) {
        NSTextField *cell = [outlineView makeViewWithIdentifier:@"nameCell" owner:self];
        if (!cell) {
            cell = [NSTextField labelWithString:@""];
            cell.identifier = @"nameCell";
        }

        if ([item isKindOfClass:[NSNumber class]]) {
            cell.stringValue = [NSString stringWithFormat:@"Strand %ld", (long)([item integerValue] + 1)];
        } else if ([item isKindOfClass:[NSArray class]]) {
            NSArray *nodeInfo = item;
            cell.stringValue = [NSString stringWithFormat:@"Node %ld", (long)([nodeInfo[1] integerValue] + 1)];
        }
        return cell;
    } else {
        NSTextField *cell = [outlineView makeViewWithIdentifier:@"customCell" owner:self];
        if (!cell) {
            cell = [[NSTextField alloc] initWithFrame:NSZeroRect];
            cell.identifier = @"customCell";
            cell.bordered = YES;
            cell.editable = YES;
            cell.target = self;
            cell.action = @selector(nameEdited:);
        }

        if ([item isKindOfClass:[NSNumber class]]) {
            NSInteger strandIndex = [item integerValue];
            cell.stringValue = (strandIndex < _mutableStrandNames.count) ? _mutableStrandNames[strandIndex] : @"";
            cell.tag = strandIndex * 10000;
        } else if ([item isKindOfClass:[NSArray class]]) {
            NSArray *nodeInfo = item;
            NSInteger strandIndex = [nodeInfo[0] integerValue];
            NSInteger nodeIndex = [nodeInfo[1] integerValue];
            if (strandIndex < _mutableNodeNames.count && nodeIndex < _mutableNodeNames[strandIndex].count) {
                cell.stringValue = _mutableNodeNames[strandIndex][nodeIndex];
            } else {
                cell.stringValue = @"";
            }
            cell.tag = strandIndex * 10000 + nodeIndex + 1;
        }
        return cell;
    }
}

- (void)nameEdited:(NSTextField *)sender {
    NSInteger tag = sender.tag;
    NSInteger strandIndex = tag / 10000;
    NSInteger nodeOffset = tag % 10000;

    if (nodeOffset == 0) {
        // Strand name
        while (_mutableStrandNames.count <= strandIndex) {
            [_mutableStrandNames addObject:@""];
        }
        _mutableStrandNames[strandIndex] = sender.stringValue;
    } else {
        // Node name
        NSInteger nodeIndex = nodeOffset - 1;
        while (_mutableNodeNames.count <= strandIndex) {
            [_mutableNodeNames addObject:[NSMutableArray array]];
        }
        while (_mutableNodeNames[strandIndex].count <= nodeIndex) {
            [_mutableNodeNames[strandIndex] addObject:@""];
        }
        _mutableNodeNames[strandIndex][nodeIndex] = sender.stringValue;
    }
}

@end

#pragma mark - Dimming Curve Preview View

@interface XLDimmingCurvePreviewView : NSView
@property (nonatomic, strong) NSColor *curveColor;
- (void)updateWithBrightness:(NSInteger)brightness gamma:(double)gamma;
- (void)updateFromFile:(NSString *)filePath;
- (void)resetToIdentity;
@end

@implementation XLDimmingCurvePreviewView {
    unsigned char _curveData[256];
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _curveColor = [NSColor yellowColor];
        [self resetToIdentity];
    }
    return self;
}

- (void)resetToIdentity {
    for (int i = 0; i < 256; i++) _curveData[i] = i;
    [self setNeedsDisplay:YES];
}

- (void)updateWithBrightness:(NSInteger)brightness gamma:(double)gamma {
    if (gamma > 50.0) gamma = 50.0;
    if (gamma < 0.0) gamma = 0.0;
    double maxB = (brightness + 100) / 100.0 * 255.0;
    for (int x = 0; x < 256; x++) {
        double i = (maxB == 0.0) ? 0.0 : maxB * pow((double)x / 255.0, gamma);
        if (i > 255) i = 255;
        if (i < 0) i = 0;
        if (isnan(i)) i = 0;
        _curveData[x] = (unsigned char)i;
    }
    [self setNeedsDisplay:YES];
}

- (void)updateFromFile:(NSString *)filePath {
    [self resetToIdentity];
    if (!filePath || filePath.length == 0) return;
    NSString *contents = [NSString stringWithContentsOfFile:filePath
                                                  encoding:NSUTF8StringEncoding error:nil];
    if (!contents) return;
    NSArray<NSString *> *lines = [contents componentsSeparatedByCharactersInSet:
                                  [NSCharacterSet newlineCharacterSet]];
    int count = 0;
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) {
            int val = [trimmed intValue];
            if (val < 0) val = 0;
            if (val > 255) val = 255;
            _curveData[count] = (unsigned char)val;
            if (++count >= 256) break;
        }
    }
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect bounds = self.bounds;
    CGFloat w = bounds.size.width, h = bounds.size.height, pad = 2.0;

    [[NSColor colorWithWhite:0.1 alpha:1.0] setFill];
    NSRectFill(bounds);

    [[NSColor grayColor] setStroke];
    [[NSBezierPath bezierPathWithRect:NSInsetRect(bounds, 0.5, 0.5)] stroke];

    [[NSColor colorWithWhite:0.3 alpha:1.0] setStroke];
    NSBezierPath *identity = [NSBezierPath bezierPath];
    [identity moveToPoint:NSMakePoint(pad, h - pad)];
    [identity lineToPoint:NSMakePoint(w - pad, pad)];
    identity.lineWidth = 0.5;
    [identity stroke];

    [_curveColor setStroke];
    NSBezierPath *curvePath = [NSBezierPath bezierPath];
    curvePath.lineWidth = 1.5;
    for (int x = 0; x < 256; x++) {
        CGFloat xpos = (CGFloat)x * (w - 2 * pad) / 255.0 + pad;
        CGFloat ypos = h - pad - (CGFloat)_curveData[x] * (h - 2 * pad) / 255.0;
        if (x == 0) [curvePath moveToPoint:NSMakePoint(xpos, ypos)];
        else [curvePath lineToPoint:NSMakePoint(xpos, ypos)];
    }
    [curvePath stroke];
}

@end

#pragma mark - XLModelDimmingCurveDialog

@interface XLModelDimmingCurveDialog ()
@property (nonatomic, strong) NSPopUpButton *modePopup;
@property (nonatomic, strong) NSView *singleGammaContainer;
@property (nonatomic, strong) NSView *singleFileContainer;
@property (nonatomic, strong) NSView *rgbGammaContainer;
@property (nonatomic, strong) NSView *rgbFileContainer;
@property (nonatomic, strong) NSTextField *singleGammaField;
@property (nonatomic, strong) NSSlider *singleBrightnessSlider;
@property (nonatomic, strong) NSTextField *singleBrightnessField;
@property (nonatomic, strong) NSTextField *singleFileField;
@property (nonatomic, strong) NSButton *singleFileBrowseButton;
@property (nonatomic, strong) NSTextField *redGammaField;
@property (nonatomic, strong) NSSlider *redBrightnessSlider;
@property (nonatomic, strong) NSTextField *redBrightnessField;
@property (nonatomic, strong) NSTextField *greenGammaField;
@property (nonatomic, strong) NSSlider *greenBrightnessSlider;
@property (nonatomic, strong) NSTextField *greenBrightnessField;
@property (nonatomic, strong) NSTextField *blueGammaField;
@property (nonatomic, strong) NSSlider *blueBrightnessSlider;
@property (nonatomic, strong) NSTextField *blueBrightnessField;
@property (nonatomic, strong) NSTextField *redFileField;
@property (nonatomic, strong) NSButton *redFileBrowseButton;
@property (nonatomic, strong) NSTextField *greenFileField;
@property (nonatomic, strong) NSButton *greenFileBrowseButton;
@property (nonatomic, strong) NSTextField *blueFileField;
@property (nonatomic, strong) NSButton *blueFileBrowseButton;
@property (nonatomic, strong) XLDimmingCurvePreviewView *redPreview;
@property (nonatomic, strong) XLDimmingCurvePreviewView *greenPreview;
@property (nonatomic, strong) XLDimmingCurvePreviewView *bluePreview;
@end

@implementation XLModelDimmingCurveDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Dimming Curve";
        self.minWidth = 580;
        self.minHeight = 480;
        _mode = XLDimmingCurveModeSingleGamma;
        _singleGamma = 1.0;
        _singleBrightness = 0;
        _redGamma = 1.0;
        _greenGamma = 1.0;
        _blueGamma = 1.0;
        _redBrightness = 0;
        _greenBrightness = 0;
        _blueBrightness = 0;
    }
    return self;
}

- (void)initFromDimmingInfo:(NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)dimmingInfo {
    if (!dimmingInfo || dimmingInfo.count == 0) {
        _mode = XLDimmingCurveModeSingleGamma;
        _singleGamma = 1.0;
        _singleBrightness = 0;
        return;
    }
    NSDictionary *allInfo = dimmingInfo[@"all"];
    if (allInfo) {
        if (allInfo[@"filename"]) {
            _mode = XLDimmingCurveModeSingleFile;
            _singleFilePath = allInfo[@"filename"];
        } else {
            _mode = XLDimmingCurveModeSingleGamma;
            _singleGamma = [allInfo[@"gamma"] ?: @"1.0" doubleValue];
            if (_singleGamma > 50.0) _singleGamma = 50.0;
            _singleBrightness = [allInfo[@"brightness"] ?: @"0" integerValue];
        }
    } else {
        NSDictionary *redInfo = dimmingInfo[@"red"];
        NSDictionary *greenInfo = dimmingInfo[@"green"];
        NSDictionary *blueInfo = dimmingInfo[@"blue"];
        if (redInfo[@"filename"]) {
            _mode = XLDimmingCurveModeRGBFile;
            _redFilePath = redInfo[@"filename"];
            _greenFilePath = greenInfo[@"filename"];
            _blueFilePath = blueInfo[@"filename"];
        } else {
            _mode = XLDimmingCurveModeRGBGamma;
            _redGamma = [redInfo[@"gamma"] ?: @"1.0" doubleValue];
            _redBrightness = [redInfo[@"brightness"] ?: @"0" integerValue];
            _greenGamma = [greenInfo[@"gamma"] ?: @"1.0" doubleValue];
            _greenBrightness = [greenInfo[@"brightness"] ?: @"0" integerValue];
            _blueGamma = [blueInfo[@"gamma"] ?: @"1.0" doubleValue];
            _blueBrightness = [blueInfo[@"brightness"] ?: @"0" integerValue];
        }
    }
}

- (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)exportDimmingInfo {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    switch (_mode) {
        case XLDimmingCurveModeSingleGamma:
            result[@"all"] = @{
                @"brightness": [NSString stringWithFormat:@"%ld", (long)_singleBrightness],
                @"gamma": [NSString stringWithFormat:@"%.1f", _singleGamma],
            };
            break;
        case XLDimmingCurveModeSingleFile:
            if (_singleFilePath.length > 0)
                result[@"all"] = @{ @"filename": _singleFilePath };
            break;
        case XLDimmingCurveModeRGBGamma:
            result[@"red"] = @{
                @"brightness": [NSString stringWithFormat:@"%ld", (long)_redBrightness],
                @"gamma": [NSString stringWithFormat:@"%.1f", _redGamma],
            };
            result[@"green"] = @{
                @"brightness": [NSString stringWithFormat:@"%ld", (long)_greenBrightness],
                @"gamma": [NSString stringWithFormat:@"%.1f", _greenGamma],
            };
            result[@"blue"] = @{
                @"brightness": [NSString stringWithFormat:@"%ld", (long)_blueBrightness],
                @"gamma": [NSString stringWithFormat:@"%.1f", _blueGamma],
            };
            break;
        case XLDimmingCurveModeRGBFile:
            result[@"red"] = @{ @"filename": _redFilePath ?: @"" };
            result[@"green"] = @{ @"filename": _greenFilePath ?: @"" };
            result[@"blue"] = @{ @"filename": _blueFilePath ?: @"" };
            break;
    }
    return result;
}

- (NSView *)buildContentView {
    NSStackView *mainStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.alignment = NSLayoutAttributeLeading;
    mainStack.spacing = 12;

    _modePopup = [XLBaseSheetController createPopUpButton];
    [_modePopup addItemWithTitle:@"Single Brightness/Gamma"];
    [_modePopup addItemWithTitle:@"Single Curve From File"];
    [_modePopup addItemWithTitle:@"RGB Brightness/Gamma"];
    [_modePopup addItemWithTitle:@"RGB From File"];
    [_modePopup selectItemAtIndex:_mode];
    [_modePopup setTarget:self];
    [_modePopup setAction:@selector(modeChanged:)];
    NSStackView *modeRow = [XLBaseSheetController formRowWithLabel:@"Mode:" control:_modePopup labelWidth:kLabelWidth];
    [mainStack addArrangedSubview:modeRow];
    [modeRow.leadingAnchor constraintEqualToAnchor:mainStack.leadingAnchor].active = YES;
    [modeRow.trailingAnchor constraintEqualToAnchor:mainStack.trailingAnchor].active = YES;

    [self buildSingleGammaContainer];
    [self buildSingleFileContainer];
    [self buildRGBGammaContainer];
    [self buildRGBFileContainer];
    for (NSView *c in @[_singleGammaContainer, _singleFileContainer, _rgbGammaContainer, _rgbFileContainer]) {
        [mainStack addArrangedSubview:c];
        [c.leadingAnchor constraintEqualToAnchor:mainStack.leadingAnchor].active = YES;
        [c.trailingAnchor constraintEqualToAnchor:mainStack.trailingAnchor].active = YES;
    }

    NSStackView *previewRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    previewRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    previewRow.distribution = NSStackViewDistributionFillEqually;
    previewRow.spacing = 8;
    _redPreview = [self createPreviewWithTitle:@"Red" color:[NSColor redColor] container:previewRow];
    _greenPreview = [self createPreviewWithTitle:@"Green" color:[NSColor greenColor] container:previewRow];
    _bluePreview = [self createPreviewWithTitle:@"Blue" color:[NSColor blueColor] container:previewRow];
    [mainStack addArrangedSubview:previewRow];
    [previewRow.leadingAnchor constraintEqualToAnchor:mainStack.leadingAnchor].active = YES;
    [previewRow.trailingAnchor constraintEqualToAnchor:mainStack.trailingAnchor].active = YES;
    [previewRow.heightAnchor constraintEqualToConstant:130].active = YES;

    [self updateModeVisibility];
    [self updatePreviews];
    return mainStack;
}

- (XLDimmingCurvePreviewView *)createPreviewWithTitle:(NSString *)title color:(NSColor *)color container:(NSStackView *)container {
    NSStackView *wrapper = [[NSStackView alloc] initWithFrame:NSZeroRect];
    wrapper.orientation = NSUserInterfaceLayoutOrientationVertical;
    wrapper.alignment = NSLayoutAttributeCenterX;
    wrapper.spacing = 2;
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont boldSystemFontOfSize:10];
    label.textColor = color;
    label.alignment = NSTextAlignmentCenter;
    [wrapper addArrangedSubview:label];
    XLDimmingCurvePreviewView *preview = [[XLDimmingCurvePreviewView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    preview.curveColor = color;
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    [preview.heightAnchor constraintEqualToConstant:110].active = YES;
    [wrapper addArrangedSubview:preview];
    [container addArrangedSubview:wrapper];
    return preview;
}

- (void)buildSingleGammaContainer {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    _singleGammaField = [XLBaseSheetController createTextField];
    _singleGammaField.stringValue = [NSString stringWithFormat:@"%.1f", _singleGamma];
    _singleGammaField.target = self;
    _singleGammaField.action = @selector(singleGammaChanged:);
    [_singleGammaField.widthAnchor constraintEqualToConstant:80].active = YES;
    NSStackView *gammaRow = [XLBaseSheetController formRowWithLabel:@"Gamma:" control:_singleGammaField labelWidth:kLabelWidth];
    [stack addArrangedSubview:gammaRow];
    [gammaRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [gammaRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    NSStackView *brightRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    brightRow.translatesAutoresizingMaskIntoConstraints = NO;
    brightRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    brightRow.spacing = 8;
    NSTextField *brightLabel = [NSTextField labelWithString:@"Brightness:"];
    brightLabel.alignment = NSTextAlignmentRight;
    [brightLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;
    _singleBrightnessSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _singleBrightnessSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _singleBrightnessSlider.minValue = -100;
    _singleBrightnessSlider.maxValue = 100;
    _singleBrightnessSlider.integerValue = _singleBrightness;
    _singleBrightnessSlider.target = self;
    _singleBrightnessSlider.action = @selector(singleBrightnessSliderChanged:);
    [_singleBrightnessSlider.widthAnchor constraintEqualToConstant:200].active = YES;
    _singleBrightnessField = [XLBaseSheetController createTextField];
    _singleBrightnessField.stringValue = [NSString stringWithFormat:@"%ld", (long)_singleBrightness];
    _singleBrightnessField.target = self;
    _singleBrightnessField.action = @selector(singleBrightnessFieldChanged:);
    [_singleBrightnessField.widthAnchor constraintEqualToConstant:50].active = YES;
    [brightRow addArrangedSubview:brightLabel];
    [brightRow addArrangedSubview:_singleBrightnessSlider];
    [brightRow addArrangedSubview:_singleBrightnessField];
    [stack addArrangedSubview:brightRow];
    _singleGammaContainer = stack;
}

- (void)buildSingleFileContainer {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    NSStackView *fileRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    fileRow.translatesAutoresizingMaskIntoConstraints = NO;
    fileRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fileRow.spacing = 8;
    _singleFileField = [XLBaseSheetController createTextField];
    _singleFileField.stringValue = _singleFilePath ?: @"";
    _singleFileField.placeholderString = @"Select dimming curve file...";
    _singleFileField.editable = NO;
    _singleFileBrowseButton = [NSButton buttonWithTitle:@"Browse..." target:self action:@selector(browseSingleFile:)];
    [fileRow addArrangedSubview:_singleFileField];
    [fileRow addArrangedSubview:_singleFileBrowseButton];
    NSStackView *row = [XLBaseSheetController formRowWithLabel:@"File:" control:fileRow labelWidth:kLabelWidth];
    [stack addArrangedSubview:row];
    [row.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [row.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
    _singleFileContainer = stack;
}

- (void)buildRGBGammaContainer {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 4;
    [self addChannelGammaControlsTo:stack title:@"Red" gammaField:&_redGammaField brightnessSlider:&_redBrightnessSlider brightnessField:&_redBrightnessField gamma:_redGamma brightness:_redBrightness];
    [self addChannelGammaControlsTo:stack title:@"Green" gammaField:&_greenGammaField brightnessSlider:&_greenBrightnessSlider brightnessField:&_greenBrightnessField gamma:_greenGamma brightness:_greenBrightness];
    [self addChannelGammaControlsTo:stack title:@"Blue" gammaField:&_blueGammaField brightnessSlider:&_blueBrightnessSlider brightnessField:&_blueBrightnessField gamma:_blueGamma brightness:_blueBrightness];
    _rgbGammaContainer = stack;
}

- (void)addChannelGammaControlsTo:(NSStackView *)stack title:(NSString *)title gammaField:(NSTextField *__strong *)gammaField brightnessSlider:(NSSlider *__strong *)brightnessSlider brightnessField:(NSTextField *__strong *)brightnessField gamma:(double)gamma brightness:(NSInteger)brightness {
    NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.title = title;
    box.titlePosition = NSAtTop;
    box.boxType = NSBoxPrimary;
    NSStackView *inner = [[NSStackView alloc] initWithFrame:NSZeroRect];
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    inner.orientation = NSUserInterfaceLayoutOrientationVertical;
    inner.alignment = NSLayoutAttributeLeading;
    inner.spacing = 4;
    *gammaField = [XLBaseSheetController createTextField];
    (*gammaField).stringValue = [NSString stringWithFormat:@"%.1f", gamma];
    (*gammaField).target = self;
    (*gammaField).action = @selector(rgbGammaChanged:);
    (*gammaField).identifier = title;
    [(*gammaField).widthAnchor constraintEqualToConstant:60].active = YES;
    [inner addArrangedSubview:[XLBaseSheetController formRowWithLabel:@"Gamma:" control:*gammaField labelWidth:80]];

    NSStackView *bRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    bRow.translatesAutoresizingMaskIntoConstraints = NO;
    bRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bRow.spacing = 4;
    NSTextField *bLabel = [NSTextField labelWithString:@"Brightness:"];
    bLabel.alignment = NSTextAlignmentRight;
    [bLabel.widthAnchor constraintEqualToConstant:80].active = YES;
    *brightnessSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    (*brightnessSlider).translatesAutoresizingMaskIntoConstraints = NO;
    (*brightnessSlider).minValue = -100;
    (*brightnessSlider).maxValue = 100;
    (*brightnessSlider).integerValue = brightness;
    (*brightnessSlider).target = self;
    (*brightnessSlider).action = @selector(rgbBrightnessSliderChanged:);
    (*brightnessSlider).identifier = title;
    [(*brightnessSlider).widthAnchor constraintEqualToConstant:150].active = YES;
    *brightnessField = [XLBaseSheetController createTextField];
    (*brightnessField).stringValue = [NSString stringWithFormat:@"%ld", (long)brightness];
    (*brightnessField).target = self;
    (*brightnessField).action = @selector(rgbBrightnessFieldChanged:);
    (*brightnessField).identifier = title;
    [(*brightnessField).widthAnchor constraintEqualToConstant:50].active = YES;
    [bRow addArrangedSubview:bLabel];
    [bRow addArrangedSubview:*brightnessSlider];
    [bRow addArrangedSubview:*brightnessField];
    [inner addArrangedSubview:bRow];
    box.contentView = inner;
    [stack addArrangedSubview:box];
    [box.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [box.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
}

- (void)buildRGBFileContainer {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    [self addFileRowTo:stack label:@"Red:" field:&_redFileField browseButton:&_redFileBrowseButton action:@selector(browseRedFile:) path:_redFilePath];
    [self addFileRowTo:stack label:@"Green:" field:&_greenFileField browseButton:&_greenFileBrowseButton action:@selector(browseGreenFile:) path:_greenFilePath];
    [self addFileRowTo:stack label:@"Blue:" field:&_blueFileField browseButton:&_blueFileBrowseButton action:@selector(browseBlueFile:) path:_blueFilePath];
    _rgbFileContainer = stack;
}

- (void)addFileRowTo:(NSStackView *)stack label:(NSString *)label field:(NSTextField *__strong *)field browseButton:(NSButton *__strong *)button action:(SEL)action path:(NSString *)path {
    NSStackView *fileRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    fileRow.translatesAutoresizingMaskIntoConstraints = NO;
    fileRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fileRow.spacing = 4;
    *field = [XLBaseSheetController createTextField];
    (*field).stringValue = path ?: @"";
    (*field).placeholderString = @"Select file...";
    (*field).editable = NO;
    *button = [NSButton buttonWithTitle:@"Browse..." target:self action:action];
    [fileRow addArrangedSubview:*field];
    [fileRow addArrangedSubview:*button];
    NSStackView *row = [XLBaseSheetController formRowWithLabel:label control:fileRow labelWidth:kLabelWidth];
    [stack addArrangedSubview:row];
    [row.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [row.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;
}

- (void)modeChanged:(id)sender {
    _mode = (XLDimmingCurveMode)_modePopup.indexOfSelectedItem;
    [self updateModeVisibility];
    [self updatePreviews];
}

- (void)updateModeVisibility {
    _singleGammaContainer.hidden = (_mode != XLDimmingCurveModeSingleGamma);
    _singleFileContainer.hidden = (_mode != XLDimmingCurveModeSingleFile);
    _rgbGammaContainer.hidden = (_mode != XLDimmingCurveModeRGBGamma);
    _rgbFileContainer.hidden = (_mode != XLDimmingCurveModeRGBFile);
}

- (void)singleGammaChanged:(id)sender {
    _singleGamma = _singleGammaField.doubleValue;
    if (_singleGamma > 50.0) _singleGamma = 50.0;
    if (_singleGamma < 0.0) _singleGamma = 0.0;
    [self updatePreviews];
}

- (void)singleBrightnessSliderChanged:(id)sender {
    _singleBrightness = _singleBrightnessSlider.integerValue;
    _singleBrightnessField.stringValue = [NSString stringWithFormat:@"%ld", (long)_singleBrightness];
    [self updatePreviews];
}

- (void)singleBrightnessFieldChanged:(id)sender {
    NSInteger val = _singleBrightnessField.integerValue;
    if (val < -100) val = -100;
    if (val > 100) val = 100;
    _singleBrightness = val;
    _singleBrightnessSlider.integerValue = val;
    _singleBrightnessField.stringValue = [NSString stringWithFormat:@"%ld", (long)val];
    [self updatePreviews];
}

- (void)rgbGammaChanged:(id)sender {
    _redGamma = _redGammaField.doubleValue;
    _greenGamma = _greenGammaField.doubleValue;
    _blueGamma = _blueGammaField.doubleValue;
    [self updatePreviews];
}

- (void)rgbBrightnessSliderChanged:(id)sender {
    NSSlider *slider = (NSSlider *)sender;
    NSString *channel = slider.identifier;
    NSInteger val = slider.integerValue;
    if ([channel isEqualToString:@"Red"]) { _redBrightness = val; _redBrightnessField.stringValue = [NSString stringWithFormat:@"%ld", (long)val]; }
    else if ([channel isEqualToString:@"Green"]) { _greenBrightness = val; _greenBrightnessField.stringValue = [NSString stringWithFormat:@"%ld", (long)val]; }
    else if ([channel isEqualToString:@"Blue"]) { _blueBrightness = val; _blueBrightnessField.stringValue = [NSString stringWithFormat:@"%ld", (long)val]; }
    [self updatePreviews];
}

- (void)rgbBrightnessFieldChanged:(id)sender {
    NSTextField *field = (NSTextField *)sender;
    NSString *channel = field.identifier;
    NSInteger val = field.integerValue;
    if (val < -100) val = -100;
    if (val > 100) val = 100;
    field.stringValue = [NSString stringWithFormat:@"%ld", (long)val];
    if ([channel isEqualToString:@"Red"]) { _redBrightness = val; _redBrightnessSlider.integerValue = val; }
    else if ([channel isEqualToString:@"Green"]) { _greenBrightness = val; _greenBrightnessSlider.integerValue = val; }
    else if ([channel isEqualToString:@"Blue"]) { _blueBrightness = val; _blueBrightnessSlider.integerValue = val; }
    [self updatePreviews];
}

- (void)browseSingleFile:(id)sender {
    [self browseFileWithCompletion:^(NSString *path) { self.singleFilePath = path; self.singleFileField.stringValue = path; [self updatePreviews]; }];
}
- (void)browseRedFile:(id)sender {
    [self browseFileWithCompletion:^(NSString *path) { self.redFilePath = path; self.redFileField.stringValue = path; [self updatePreviews]; }];
}
- (void)browseGreenFile:(id)sender {
    [self browseFileWithCompletion:^(NSString *path) { self.greenFilePath = path; self.greenFileField.stringValue = path; [self updatePreviews]; }];
}
- (void)browseBlueFile:(id)sender {
    [self browseFileWithCompletion:^(NSString *path) { self.blueFilePath = path; self.blueFileField.stringValue = path; [self updatePreviews]; }];
}

- (void)browseFileWithCompletion:(void (^)(NSString *path))completion {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Select a dimming curve file (256 lines, one value per line)";
    [panel beginSheetModalForWindow:self.sheet completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) completion(panel.URL.path);
    }];
}

- (void)updatePreviews {
    switch (_mode) {
        case XLDimmingCurveModeSingleGamma:
            [_redPreview updateWithBrightness:_singleBrightness gamma:_singleGamma];
            [_greenPreview updateWithBrightness:_singleBrightness gamma:_singleGamma];
            [_bluePreview updateWithBrightness:_singleBrightness gamma:_singleGamma];
            break;
        case XLDimmingCurveModeSingleFile:
            [_redPreview updateFromFile:_singleFilePath];
            [_greenPreview updateFromFile:_singleFilePath];
            [_bluePreview updateFromFile:_singleFilePath];
            break;
        case XLDimmingCurveModeRGBGamma:
            [_redPreview updateWithBrightness:_redBrightness gamma:_redGamma];
            [_greenPreview updateWithBrightness:_greenBrightness gamma:_greenGamma];
            [_bluePreview updateWithBrightness:_blueBrightness gamma:_blueGamma];
            break;
        case XLDimmingCurveModeRGBFile:
            [_redPreview updateFromFile:_redFilePath];
            [_greenPreview updateFromFile:_greenFilePath];
            [_bluePreview updateFromFile:_blueFilePath];
            break;
    }
}

- (void)okClicked:(id)sender {
    switch (_mode) {
        case XLDimmingCurveModeSingleGamma:
            _singleGamma = _singleGammaField.doubleValue;
            _singleBrightness = _singleBrightnessSlider.integerValue;
            break;
        case XLDimmingCurveModeSingleFile:
            _singleFilePath = _singleFileField.stringValue;
            break;
        case XLDimmingCurveModeRGBGamma:
            _redGamma = _redGammaField.doubleValue;
            _redBrightness = _redBrightnessSlider.integerValue;
            _greenGamma = _greenGammaField.doubleValue;
            _greenBrightness = _greenBrightnessSlider.integerValue;
            _blueGamma = _blueGammaField.doubleValue;
            _blueBrightness = _blueBrightnessSlider.integerValue;
            break;
        case XLDimmingCurveModeRGBFile:
            _redFilePath = _redFileField.stringValue;
            _greenFilePath = _greenFileField.stringValue;
            _blueFilePath = _blueFileField.stringValue;
            break;
    }
    [super okClicked:sender];
}

- (NSString *)validate {
    if (_mode == XLDimmingCurveModeSingleGamma) {
        double g = _singleGammaField.doubleValue;
        if (g < 0.0 || g > 50.0) return @"Gamma must be between 0.0 and 50.0";
    } else if (_mode == XLDimmingCurveModeRGBGamma) {
        double rg = _redGammaField.doubleValue, gg = _greenGammaField.doubleValue, bg = _blueGammaField.doubleValue;
        if (rg < 0 || rg > 50 || gg < 0 || gg > 50 || bg < 0 || bg > 50) return @"Gamma values must be between 0.0 and 50.0";
    }
    return nil;
}

@end

#pragma mark - XLEditAliasesDialog

@interface XLEditAliasesDialog () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableAliases;

@end

@implementation XLEditAliasesDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Edit Aliases";
        self.minWidth = 400;
        self.minHeight = 300;
        _mutableAliases = [NSMutableArray array];
    }
    return self;
}

- (void)setAliases:(NSArray<NSString *> *)aliases {
    _mutableAliases = [aliases mutableCopy];
}

- (NSArray<NSString *> *)aliases {
    return [_mutableAliases copy];
}

- (void)addAlias:(NSString *)alias {
    [_mutableAliases addObject:alias];
    [_tableView reloadData];
}

- (void)removeAliasAtIndex:(NSUInteger)index {
    if (index < _mutableAliases.count) {
        [_mutableAliases removeObjectAtIndex:index];
        [_tableView reloadData];
    }
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Element name
    NSTextField *elementLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Aliases for: %@", _elementName ?: @"(none)"]];
    elementLabel.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:elementLabel];

    // Table
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 24;

    NSTableColumn *aliasColumn = [[NSTableColumn alloc] initWithIdentifier:@"alias"];
    aliasColumn.title = @"Alias";
    aliasColumn.width = 340;
    aliasColumn.editable = YES;
    [_tableView addTableColumn:aliasColumn];

    scrollView.documentView = _tableView;

    [stack addArrangedSubview:scrollView];
    [scrollView.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [scrollView.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    // Add/Remove buttons
    NSStackView *buttonRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.spacing = 8;

    NSButton *addBtn = [NSButton buttonWithTitle:@"Add Alias" target:self action:@selector(addNewAlias:)];
    NSButton *removeBtn = [NSButton buttonWithTitle:@"Remove" target:self action:@selector(removeSelectedAlias:)];

    [buttonRow addArrangedSubview:addBtn];
    [buttonRow addArrangedSubview:removeBtn];
    [stack addArrangedSubview:buttonRow];

    return stack;
}

- (void)addNewAlias:(id)sender {
    [_mutableAliases addObject:@"New Alias"];
    [_tableView reloadData];
    NSInteger lastRow = _mutableAliases.count - 1;
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:lastRow] byExtendingSelection:NO];
    [_tableView editColumn:0 row:lastRow withEvent:nil select:YES];
}

- (void)removeSelectedAlias:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row >= 0 && row < _mutableAliases.count) {
        [_mutableAliases removeObjectAtIndex:row];
        [_tableView reloadData];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _mutableAliases.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTextField *cell = [tableView makeViewWithIdentifier:@"aliasCell" owner:self];
    if (!cell) {
        cell = [[NSTextField alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"aliasCell";
        cell.bordered = YES;
        cell.editable = YES;
        cell.target = self;
        cell.action = @selector(aliasEdited:);
    }
    cell.stringValue = _mutableAliases[row];
    cell.tag = row;
    return cell;
}

- (void)aliasEdited:(NSTextField *)sender {
    NSInteger row = sender.tag;
    if (row >= 0 && row < _mutableAliases.count) {
        _mutableAliases[row] = sender.stringValue;
    }
}

@end

#pragma mark - XLSubModelGenerateDialog

@interface XLSubModelGenerateDialog ()

@property (nonatomic, strong) NSTextField *countField;
@property (nonatomic, strong) NSStepper *countStepper;
@property (nonatomic, strong) NSTextField *prefixField;
@property (nonatomic, strong) NSPopUpButton *typePopup;
@property (nonatomic, strong) NSButton *overlapCheckbox;

@end

@implementation XLSubModelGenerateDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Generate Submodels";
        self.minWidth = 400;
        self.minHeight = 250;
        _submodelCount = 4;
        _namingPrefix = @"Segment";
        _submodelType = @"horizontal";
        _allowOverlap = NO;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Model name
    NSTextField *modelLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Generate submodels for: %@", _modelName ?: @"(none)"]];
    modelLabel.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:modelLabel];

    // Number of submodels
    NSStackView *countRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    countRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    countRow.spacing = 8;

    NSTextField *countLabel = [NSTextField labelWithString:@"Number:"];
    countLabel.alignment = NSTextAlignmentRight;
    [countLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _countField = [XLBaseSheetController createNumericField];
    _countField.integerValue = _submodelCount;
    [_countField setTarget:self];
    [_countField setAction:@selector(countFieldChanged:)];
    [_countField.widthAnchor constraintEqualToConstant:60].active = YES;

    _countStepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    _countStepper.minValue = 2;
    _countStepper.maxValue = 100;
    _countStepper.integerValue = _submodelCount;
    [_countStepper setTarget:self];
    [_countStepper setAction:@selector(countStepperChanged:)];

    [countRow addArrangedSubview:countLabel];
    [countRow addArrangedSubview:_countField];
    [countRow addArrangedSubview:_countStepper];
    [stack addArrangedSubview:countRow];

    // Naming prefix
    _prefixField = [XLBaseSheetController createTextField];
    _prefixField.stringValue = _namingPrefix;
    [_prefixField.widthAnchor constraintEqualToConstant:150].active = YES;

    NSStackView *prefixRow = [XLBaseSheetController formRowWithLabel:@"Name Prefix:"
                                                             control:_prefixField
                                                          labelWidth:kLabelWidth];
    [stack addArrangedSubview:prefixRow];

    // Submodel type
    _typePopup = [XLBaseSheetController createPopUpButton];
    [_typePopup addItemWithTitle:@"Horizontal Segments"];
    [_typePopup addItemWithTitle:@"Vertical Segments"];
    [_typePopup addItemWithTitle:@"Node Ranges"];
    [_typePopup addItemWithTitle:@"Strand-based"];

    _typePopup.menu.itemArray[0].representedObject = @"horizontal";
    _typePopup.menu.itemArray[1].representedObject = @"vertical";
    _typePopup.menu.itemArray[2].representedObject = @"ranges";
    _typePopup.menu.itemArray[3].representedObject = @"strands";

    for (NSMenuItem *item in _typePopup.menu.itemArray) {
        if ([item.representedObject isEqualToString:_submodelType]) {
            [_typePopup selectItem:item];
            break;
        }
    }

    NSStackView *typeRow = [XLBaseSheetController formRowWithLabel:@"Type:"
                                                           control:_typePopup
                                                        labelWidth:kLabelWidth];
    [stack addArrangedSubview:typeRow];

    // Overlap option
    _overlapCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Allow overlapping submodels"];
    _overlapCheckbox.state = _allowOverlap ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_overlapCheckbox];

    return stack;
}

- (void)countFieldChanged:(id)sender {
    _countStepper.integerValue = _countField.integerValue;
}

- (void)countStepperChanged:(id)sender {
    _countField.integerValue = _countStepper.integerValue;
}

- (void)okClicked:(id)sender {
    _submodelCount = _countField.integerValue;
    _namingPrefix = _prefixField.stringValue;
    _submodelType = _typePopup.selectedItem.representedObject;
    _allowOverlap = (_overlapCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end

#pragma mark - XLSevenSegmentDialog

@interface XLSevenSegmentDialog ()

@property (nonatomic, strong) NSTextField *digitCountField;
@property (nonatomic, strong) NSSlider *thicknessSlider;
@property (nonatomic, strong) NSSlider *spacingSlider;
@property (nonatomic, strong) NSButton *decimalCheckbox;
@property (nonatomic, strong) NSButton *colonCheckbox;
@property (nonatomic, strong) NSPopUpButton *orderingPopup;

@end

@implementation XLSevenSegmentDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Seven Segment Configuration";
        self.minWidth = 400;
        self.minHeight = 300;
        _digitCount = 4;
        _segmentThickness = 3.0;
        _digitSpacing = 5.0;
        _includeDecimalPoints = NO;
        _includeColons = NO;
        _nodeOrdering = @"clockwise";
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Digit count
    _digitCountField = [XLBaseSheetController createNumericField];
    _digitCountField.integerValue = _digitCount;
    [_digitCountField.widthAnchor constraintEqualToConstant:60].active = YES;

    NSStackView *countRow = [XLBaseSheetController formRowWithLabel:@"Number of Digits:"
                                                            control:_digitCountField
                                                         labelWidth:kLabelWidth];
    [stack addArrangedSubview:countRow];

    // Segment thickness
    NSStackView *thickRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    thickRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    thickRow.spacing = 8;

    NSTextField *thickLabel = [NSTextField labelWithString:@"Thickness:"];
    thickLabel.alignment = NSTextAlignmentRight;
    [thickLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _thicknessSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _thicknessSlider.minValue = 1;
    _thicknessSlider.maxValue = 10;
    _thicknessSlider.doubleValue = _segmentThickness;
    [_thicknessSlider.widthAnchor constraintEqualToConstant:150].active = YES;

    [thickRow addArrangedSubview:thickLabel];
    [thickRow addArrangedSubview:_thicknessSlider];
    [stack addArrangedSubview:thickRow];

    // Digit spacing
    NSStackView *spaceRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    spaceRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    spaceRow.spacing = 8;

    NSTextField *spaceLabel = [NSTextField labelWithString:@"Digit Spacing:"];
    spaceLabel.alignment = NSTextAlignmentRight;
    [spaceLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _spacingSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _spacingSlider.minValue = 0;
    _spacingSlider.maxValue = 20;
    _spacingSlider.doubleValue = _digitSpacing;
    [_spacingSlider.widthAnchor constraintEqualToConstant:150].active = YES;

    [spaceRow addArrangedSubview:spaceLabel];
    [spaceRow addArrangedSubview:_spacingSlider];
    [stack addArrangedSubview:spaceRow];

    // Node ordering
    _orderingPopup = [XLBaseSheetController createPopUpButton];
    [_orderingPopup addItemWithTitle:@"Clockwise from Top"];
    [_orderingPopup addItemWithTitle:@"Counter-clockwise from Top"];
    [_orderingPopup addItemWithTitle:@"Standard (A-G)"];

    NSStackView *orderRow = [XLBaseSheetController formRowWithLabel:@"Node Ordering:"
                                                            control:_orderingPopup
                                                         labelWidth:kLabelWidth];
    [stack addArrangedSubview:orderRow];

    // Checkboxes
    _decimalCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Include decimal points"];
    _decimalCheckbox.state = _includeDecimalPoints ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_decimalCheckbox];

    _colonCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Include colons (for time display)"];
    _colonCheckbox.state = _includeColons ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_colonCheckbox];

    return stack;
}

- (void)okClicked:(id)sender {
    _digitCount = _digitCountField.integerValue;
    _segmentThickness = _thicknessSlider.doubleValue;
    _digitSpacing = _spacingSlider.doubleValue;
    _includeDecimalPoints = (_decimalCheckbox.state == NSControlStateValueOn);
    _includeColons = (_colonCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end

#pragma mark - XLAutoLabelDialog

@interface XLAutoLabelDialog ()

@property (nonatomic, strong) NSTextField *startField;
@property (nonatomic, strong) NSTextField *prefixField;
@property (nonatomic, strong) NSTextField *suffixField;
@property (nonatomic, strong) NSTextField *incrementField;
@property (nonatomic, strong) NSTextField *paddingField;

@end

@implementation XLAutoLabelDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Auto Label";
        self.minWidth = 350;
        self.minHeight = 250;
        _startNumber = 1;
        _prefix = @"";
        _suffix = @"";
        _incrementStep = 1;
        _padding = 0;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;

    // Start number
    _startField = [XLBaseSheetController createNumericField];
    _startField.integerValue = _startNumber;
    [_startField.widthAnchor constraintEqualToConstant:80].active = YES;

    NSStackView *startRow = [XLBaseSheetController formRowWithLabel:@"Start Number:"
                                                            control:_startField
                                                         labelWidth:100];
    [stack addArrangedSubview:startRow];

    // Prefix
    _prefixField = [XLBaseSheetController createTextField];
    _prefixField.stringValue = _prefix;
    _prefixField.placeholderString = @"e.g., Node_";
    [_prefixField.widthAnchor constraintEqualToConstant:120].active = YES;

    NSStackView *prefixRow = [XLBaseSheetController formRowWithLabel:@"Prefix:"
                                                             control:_prefixField
                                                          labelWidth:100];
    [stack addArrangedSubview:prefixRow];

    // Suffix
    _suffixField = [XLBaseSheetController createTextField];
    _suffixField.stringValue = _suffix;
    _suffixField.placeholderString = @"e.g., _LED";
    [_suffixField.widthAnchor constraintEqualToConstant:120].active = YES;

    NSStackView *suffixRow = [XLBaseSheetController formRowWithLabel:@"Suffix:"
                                                             control:_suffixField
                                                          labelWidth:100];
    [stack addArrangedSubview:suffixRow];

    // Increment
    _incrementField = [XLBaseSheetController createNumericField];
    _incrementField.integerValue = _incrementStep;
    [_incrementField.widthAnchor constraintEqualToConstant:60].active = YES;

    NSStackView *incRow = [XLBaseSheetController formRowWithLabel:@"Increment:"
                                                          control:_incrementField
                                                       labelWidth:100];
    [stack addArrangedSubview:incRow];

    // Padding
    _paddingField = [XLBaseSheetController createNumericField];
    _paddingField.integerValue = _padding;
    _paddingField.placeholderString = @"0";
    [_paddingField.widthAnchor constraintEqualToConstant:60].active = YES;

    NSStackView *padRow = [XLBaseSheetController formRowWithLabel:@"Zero Padding:"
                                                          control:_paddingField
                                                       labelWidth:100];
    [stack addArrangedSubview:padRow];

    // Preview
    NSTextField *previewLabel = [NSTextField labelWithString:@"Preview: Node_001_LED, Node_002_LED, ..."];
    previewLabel.textColor = [NSColor secondaryLabelColor];
    previewLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:previewLabel];

    return stack;
}

- (void)okClicked:(id)sender {
    _startNumber = _startField.integerValue;
    _prefix = _prefixField.stringValue;
    _suffix = _suffixField.stringValue;
    _incrementStep = _incrementField.integerValue;
    _padding = _paddingField.integerValue;
    [super okClicked:sender];
}

@end

#pragma mark - XLWiringDialog

@interface XLWiringDialog ()

@property (nonatomic, strong) XLWiringDiagramView *diagramView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSPopUpButton *controllerPopup;
@property (nonatomic, strong) NSSlider *zoomSlider;
@property (nonatomic, strong) NSTextField *zoomLabel;
@property (nonatomic, strong) NSButton *channelInfoCheckbox;
@property (nonatomic, strong) NSButton *portNumbersCheckbox;
@property (nonatomic, strong) NSButton *unassignedCheckbox;
@property (nonatomic, copy) void (^completionHandler)(void);

@end

@implementation XLWiringDialog

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskResizable |
                                                            NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Wiring Diagram";
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(600, 500);

    self = [super initWithWindow:window];
    if (self) {
        _showFrontView = YES;
        _showNodeNumbers = YES;
        _showControllerConnections = YES;
        _zoomLevel = 1.0;

        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    // Create toolbar area
    NSView *toolbarView = [[NSView alloc] initWithFrame:NSZeroRect];
    toolbarView.translatesAutoresizingMaskIntoConstraints = NO;
    toolbarView.wantsLayer = YES;
    toolbarView.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];
    [contentView addSubview:toolbarView];

    // Controller filter
    NSTextField *controllerLabel = [NSTextField labelWithString:@"Controller:"];
    controllerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbarView addSubview:controllerLabel];

    _controllerPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _controllerPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_controllerPopup addItemWithTitle:@"All Controllers"];
    [_controllerPopup setTarget:self];
    [_controllerPopup setAction:@selector(controllerChanged:)];
    [toolbarView addSubview:_controllerPopup];

    // Zoom controls
    NSTextField *zoomTitle = [NSTextField labelWithString:@"Zoom:"];
    zoomTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbarView addSubview:zoomTitle];

    _zoomSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _zoomSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _zoomSlider.minValue = 0.5;
    _zoomSlider.maxValue = 2.0;
    _zoomSlider.doubleValue = 1.0;
    [_zoomSlider setTarget:self];
    [_zoomSlider setAction:@selector(zoomChanged:)];
    [toolbarView addSubview:_zoomSlider];

    _zoomLabel = [NSTextField labelWithString:@"100%"];
    _zoomLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbarView addSubview:_zoomLabel];

    // Options checkboxes
    _channelInfoCheckbox = [NSButton checkboxWithTitle:@"Show Channels"
                                                target:self
                                                action:@selector(optionChanged:)];
    _channelInfoCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    _channelInfoCheckbox.state = NSControlStateValueOn;
    [toolbarView addSubview:_channelInfoCheckbox];

    _portNumbersCheckbox = [NSButton checkboxWithTitle:@"Port Numbers"
                                                target:self
                                                action:@selector(optionChanged:)];
    _portNumbersCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    _portNumbersCheckbox.state = NSControlStateValueOn;
    [toolbarView addSubview:_portNumbersCheckbox];

    _unassignedCheckbox = [NSButton checkboxWithTitle:@"Unassigned Models"
                                               target:self
                                               action:@selector(optionChanged:)];
    _unassignedCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    _unassignedCheckbox.state = NSControlStateValueOn;
    [toolbarView addSubview:_unassignedCheckbox];

    // Export buttons
    NSButton *exportPDFBtn = [NSButton buttonWithTitle:@"Export PDF"
                                                target:self
                                                action:@selector(exportPDF:)];
    exportPDFBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbarView addSubview:exportPDFBtn];

    NSButton *exportPNGBtn = [NSButton buttonWithTitle:@"Export PNG"
                                                target:self
                                                action:@selector(exportPNG:)];
    exportPNGBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbarView addSubview:exportPNGBtn];

    NSButton *printBtn = [NSButton buttonWithTitle:@"Print..."
                                            target:self
                                            action:@selector(printDiagram:)];
    printBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbarView addSubview:printBtn];

    // Scroll view for diagram
    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.borderType = NSBezelBorder;
    _scrollView.backgroundColor = [NSColor windowBackgroundColor];
    [contentView addSubview:_scrollView];

    // Diagram view
    _diagramView = [[XLWiringDiagramView alloc] initWithFrame:NSMakeRect(0, 0, 1200, 800)];
    _diagramView.showChannelInfo = YES;
    _diagramView.showPortNumbers = YES;
    _diagramView.showUnassignedModels = YES;
    _scrollView.documentView = _diagramView;

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Toolbar
        [toolbarView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [toolbarView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [toolbarView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [toolbarView.heightAnchor constraintEqualToConstant:50],

        // Controller label and popup
        [controllerLabel.leadingAnchor constraintEqualToAnchor:toolbarView.leadingAnchor constant:12],
        [controllerLabel.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [_controllerPopup.leadingAnchor constraintEqualToAnchor:controllerLabel.trailingAnchor constant:6],
        [_controllerPopup.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [_controllerPopup.widthAnchor constraintGreaterThanOrEqualToConstant:150],

        // Zoom controls
        [zoomTitle.leadingAnchor constraintEqualToAnchor:_controllerPopup.trailingAnchor constant:20],
        [zoomTitle.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [_zoomSlider.leadingAnchor constraintEqualToAnchor:zoomTitle.trailingAnchor constant:6],
        [_zoomSlider.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [_zoomSlider.widthAnchor constraintEqualToConstant:100],
        [_zoomLabel.leadingAnchor constraintEqualToAnchor:_zoomSlider.trailingAnchor constant:6],
        [_zoomLabel.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [_zoomLabel.widthAnchor constraintEqualToConstant:40],

        // Checkboxes
        [_channelInfoCheckbox.leadingAnchor constraintEqualToAnchor:_zoomLabel.trailingAnchor constant:20],
        [_channelInfoCheckbox.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [_portNumbersCheckbox.leadingAnchor constraintEqualToAnchor:_channelInfoCheckbox.trailingAnchor constant:12],
        [_portNumbersCheckbox.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [_unassignedCheckbox.leadingAnchor constraintEqualToAnchor:_portNumbersCheckbox.trailingAnchor constant:12],
        [_unassignedCheckbox.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],

        // Export buttons
        [printBtn.trailingAnchor constraintEqualToAnchor:toolbarView.trailingAnchor constant:-12],
        [printBtn.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [exportPNGBtn.trailingAnchor constraintEqualToAnchor:printBtn.leadingAnchor constant:-8],
        [exportPNGBtn.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],
        [exportPDFBtn.trailingAnchor constraintEqualToAnchor:exportPNGBtn.leadingAnchor constant:-8],
        [exportPDFBtn.centerYAnchor constraintEqualToAnchor:toolbarView.centerYAnchor],

        // Scroll view
        [_scrollView.topAnchor constraintEqualToAnchor:toolbarView.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
    ]];
}

- (void)setEngineBridge:(XLEngineBridge *)engineBridge {
    _engineBridge = engineBridge;
    _diagramView.engineBridge = engineBridge;

    // Populate controller popup
    [_controllerPopup removeAllItems];
    [_controllerPopup addItemWithTitle:@"All Controllers"];

    if (engineBridge) {
        NSArray<NSString *> *controllers = [engineBridge getControllerNames];
        for (NSString *name in controllers) {
            [_controllerPopup addItemWithTitle:name];
        }
    }
}

- (void)showWithCompletion:(void (^)(void))completion {
    _completionHandler = completion;

    [_diagramView reloadData];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)controllerChanged:(id)sender {
    if (_controllerPopup.indexOfSelectedItem == 0) {
        _diagramView.selectedController = nil;
    } else {
        _diagramView.selectedController = _controllerPopup.selectedItem.title;
    }
    [_diagramView reloadData];
}

- (void)zoomChanged:(id)sender {
    _zoomLevel = _zoomSlider.doubleValue;
    _diagramView.zoomLevel = _zoomLevel;
    _zoomLabel.stringValue = [NSString stringWithFormat:@"%ld%%", (long)(_zoomLevel * 100)];

    // Update scroll view content size
    NSSize idealSize = [_diagramView idealContentSize];
    NSRect frame = _diagramView.frame;
    frame.size = idealSize;
    _diagramView.frame = frame;

    [_diagramView setNeedsDisplay:YES];
}

- (void)optionChanged:(id)sender {
    _diagramView.showChannelInfo = (_channelInfoCheckbox.state == NSControlStateValueOn);
    _diagramView.showPortNumbers = (_portNumbersCheckbox.state == NSControlStateValueOn);
    _diagramView.showUnassignedModels = (_unassignedCheckbox.state == NSControlStateValueOn);

    _showNodeNumbers = _diagramView.showPortNumbers;
    _showControllerConnections = _diagramView.showChannelInfo;

    [_diagramView reloadData];
}

- (void)exportPDF:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"pdf"]];
    panel.nameFieldStringValue = @"WiringDiagram.pdf";

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSData *pdfData = [self->_diagramView exportAsPDF];
            if (pdfData) {
                [pdfData writeToURL:panel.URL atomically:YES];
            }
        }
    }];
}

- (void)exportPNG:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"png"]];
    panel.nameFieldStringValue = @"WiringDiagram.png";

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSData *pngData = [self->_diagramView exportAsPNG];
            if (pngData) {
                [pngData writeToURL:panel.URL atomically:YES];
            }
        }
    }];
}

- (void)printDiagram:(id)sender {
    NSPrintInfo *printInfo = [NSPrintInfo sharedPrintInfo];
    printInfo.orientation = NSPaperOrientationLandscape;
    printInfo.horizontalPagination = NSPrintingPaginationModeFit;
    printInfo.verticalPagination = NSPrintingPaginationModeFit;

    NSPrintOperation *printOp = [NSPrintOperation printOperationWithView:_diagramView printInfo:printInfo];
    printOp.showsPrintPanel = YES;
    printOp.showsProgressPanel = YES;

    [printOp runOperationModalForWindow:self.window delegate:nil didRunSelector:nil contextInfo:NULL];
}

@end

@interface XLPixelTestDialog () <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (nonatomic, strong) NSTimer *testTimer;
@property (nonatomic, strong) NSButton *outputToggleButton;
@property (nonatomic, strong) NSPopUpButton *patternPopup;
@property (nonatomic, strong) NSColorWell *foregroundColorWell;
@property (nonatomic, strong) NSColorWell *backgroundColorWell;
@property (nonatomic, strong) NSSlider *speedSlider;
@property (nonatomic, strong) NSTextField *speedLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSOutlineView *modelOutlineView;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedModels;
@property (nonatomic, copy) void (^completionBlock)(void);
@property (nonatomic, assign, readwrite) BOOL isOutputActive;
@property (nonatomic, assign) NSInteger chasePosition;
@property (nonatomic, assign) BOOL shimmerState;
@property (nonatomic, assign) NSInteger rgbCyclePhase;

@end

@implementation XLPixelTestDialog

static const CGFloat kPTDialogWidth = 500.0;
static const CGFloat kPTDialogHeight = 550.0;
static const CGFloat kPTPadding = 16.0;
static const CGFloat kPTControlHeight = 24.0;
static const CGFloat kPTSpacing = 12.0;

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kPTDialogWidth, kPTDialogHeight)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Pixel Test";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        _modelNames = nil;
        _testPattern = XLPixelTestPatternOff;
        _testColor = [NSColor whiteColor];
        _backgroundColor = [NSColor blackColor];
        _chaseSpeed = 50;
        _isOutputActive = NO;
        _selectedModels = [NSMutableSet set];
        _chasePosition = 0;
        _shimmerState = NO;
        _rgbCyclePhase = 0;

        [self buildUI];
    }
    return self;
}

- (void)dealloc {
    [self stopOutput];
}

- (void)buildUI {
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;

    CGFloat y = kPTDialogHeight - kPTPadding;

    // Output toggle button
    y -= kPTControlHeight + kPTSpacing;
    _outputToggleButton = [[NSButton alloc] initWithFrame:NSMakeRect(kPTPadding, y, 150, kPTControlHeight)];
    _outputToggleButton.title = @"Start Output";
    _outputToggleButton.bezelStyle = NSBezelStyleRounded;
    [_outputToggleButton setTarget:self];
    [_outputToggleButton setAction:@selector(toggleOutput:)];
    [contentView addSubview:_outputToggleButton];

    // Status label
    _statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(kPTPadding + 160, y, kPTDialogWidth - kPTPadding * 2 - 160, kPTControlHeight)];
    _statusLabel.stringValue = @"Output: Stopped";
    _statusLabel.bezeled = NO;
    _statusLabel.editable = NO;
    _statusLabel.selectable = NO;
    _statusLabel.drawsBackground = NO;
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    [contentView addSubview:_statusLabel];

    // Pattern selection
    y -= kPTControlHeight + kPTSpacing;
    NSTextField *patternLabel = [NSTextField labelWithString:@"Test Pattern:"];
    patternLabel.frame = NSMakeRect(kPTPadding, y, 100, kPTControlHeight);
    [contentView addSubview:patternLabel];

    _patternPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(kPTPadding + 110, y, 200, kPTControlHeight) pullsDown:NO];
    [_patternPopup addItemWithTitle:@"Off"];
    [_patternPopup addItemWithTitle:@"All On"];
    [_patternPopup addItemWithTitle:@"Chase (1 at a time)"];
    [_patternPopup addItemWithTitle:@"Chase (1 in 3)"];
    [_patternPopup addItemWithTitle:@"Chase (1 in 4)"];
    [_patternPopup addItemWithTitle:@"Chase (1 in 5)"];
    [_patternPopup addItemWithTitle:@"Alternate"];
    [_patternPopup addItemWithTitle:@"Twinkle 5%"];
    [_patternPopup addItemWithTitle:@"Twinkle 10%"];
    [_patternPopup addItemWithTitle:@"Twinkle 25%"];
    [_patternPopup addItemWithTitle:@"Twinkle 50%"];
    [_patternPopup addItemWithTitle:@"Shimmer"];
    [_patternPopup addItemWithTitle:@"RGB Cycle"];
    [_patternPopup addItemWithTitle:@"Color Blocks"];
    [_patternPopup setTarget:self];
    [_patternPopup setAction:@selector(patternChanged:)];
    [contentView addSubview:_patternPopup];

    // Foreground color
    y -= kPTControlHeight + kPTSpacing;
    NSTextField *fgColorLabel = [NSTextField labelWithString:@"Highlight Color:"];
    fgColorLabel.frame = NSMakeRect(kPTPadding, y, 100, kPTControlHeight);
    [contentView addSubview:fgColorLabel];

    _foregroundColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(kPTPadding + 110, y, 60, kPTControlHeight)];
    _foregroundColorWell.color = _testColor;
    [_foregroundColorWell setTarget:self];
    [_foregroundColorWell setAction:@selector(foregroundColorChanged:)];
    [contentView addSubview:_foregroundColorWell];

    // Background color
    NSTextField *bgColorLabel = [NSTextField labelWithString:@"Background:"];
    bgColorLabel.frame = NSMakeRect(kPTPadding + 190, y, 80, kPTControlHeight);
    [contentView addSubview:bgColorLabel];

    _backgroundColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(kPTPadding + 280, y, 60, kPTControlHeight)];
    _backgroundColorWell.color = _backgroundColor;
    [_backgroundColorWell setTarget:self];
    [_backgroundColorWell setAction:@selector(backgroundColorChanged:)];
    [contentView addSubview:_backgroundColorWell];

    // Speed slider
    y -= kPTControlHeight + kPTSpacing;
    NSTextField *speedTitleLabel = [NSTextField labelWithString:@"Speed:"];
    speedTitleLabel.frame = NSMakeRect(kPTPadding, y, 60, kPTControlHeight);
    [contentView addSubview:speedTitleLabel];

    _speedSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(kPTPadding + 70, y, 250, kPTControlHeight)];
    _speedSlider.minValue = 1;
    _speedSlider.maxValue = 100;
    _speedSlider.integerValue = _chaseSpeed;
    [_speedSlider setTarget:self];
    [_speedSlider setAction:@selector(speedChanged:)];
    [contentView addSubview:_speedSlider];

    _speedLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld", (long)_chaseSpeed]];
    _speedLabel.frame = NSMakeRect(kPTPadding + 330, y, 50, kPTControlHeight);
    [contentView addSubview:_speedLabel];

    // Model selection section header
    y -= kPTControlHeight + kPTSpacing * 2;
    NSTextField *modelHeader = [NSTextField labelWithString:@"Select Models to Test:"];
    modelHeader.font = [NSFont boldSystemFontOfSize:13];
    modelHeader.frame = NSMakeRect(kPTPadding, y, 250, kPTControlHeight);
    [contentView addSubview:modelHeader];

    // Select All / Deselect All buttons
    NSButton *selectAllButton = [NSButton buttonWithTitle:@"All" target:self action:@selector(selectAllModels:)];
    selectAllButton.frame = NSMakeRect(kPTDialogWidth - kPTPadding - 120, y, 50, kPTControlHeight);
    [contentView addSubview:selectAllButton];

    NSButton *deselectAllButton = [NSButton buttonWithTitle:@"None" target:self action:@selector(deselectAllModels:)];
    deselectAllButton.frame = NSMakeRect(kPTDialogWidth - kPTPadding - 60, y, 50, kPTControlHeight);
    [contentView addSubview:deselectAllButton];

    // Model outline view in scroll view
    y -= kPTSpacing;
    CGFloat listHeight = y - kPTPadding - kPTControlHeight - kPTSpacing;

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(kPTPadding, kPTPadding + kPTControlHeight + kPTSpacing, kPTDialogWidth - kPTPadding * 2, listHeight)];
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSBezelBorder;

    _modelOutlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
    _modelOutlineView.dataSource = self;
    _modelOutlineView.delegate = self;
    _modelOutlineView.rowHeight = 22;
    _modelOutlineView.usesAlternatingRowBackgroundColors = YES;

    NSTableColumn *checkColumn = [[NSTableColumn alloc] initWithIdentifier:@"check"];
    checkColumn.title = @"";
    checkColumn.width = 30;
    checkColumn.minWidth = 30;
    checkColumn.maxWidth = 30;
    [_modelOutlineView addTableColumn:checkColumn];

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Model";
    nameColumn.width = kPTDialogWidth - kPTPadding * 2 - 50;
    [_modelOutlineView addTableColumn:nameColumn];

    _modelOutlineView.outlineTableColumn = nameColumn;

    scrollView.documentView = _modelOutlineView;
    [contentView addSubview:scrollView];

    // Close button
    NSButton *closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeDialog:)];
    closeButton.frame = NSMakeRect(kPTDialogWidth - kPTPadding - 80, kPTPadding, 80, kPTControlHeight);
    closeButton.keyEquivalent = @"\033"; // Escape key
    [contentView addSubview:closeButton];
}

#pragma mark - Actions

- (void)toggleOutput:(id)sender {
    if (_isOutputActive) {
        [self stopOutput];
    } else {
        [self startOutput];
    }
}

- (void)startOutput {
    if (_isOutputActive) return;

    // Start output via engine bridge
    if ([_engineBridge startOutput]) {
        _isOutputActive = YES;
        _outputToggleButton.title = @"Stop Output";
        _statusLabel.stringValue = @"Output: Running";
        _statusLabel.textColor = [NSColor systemGreenColor];

        // Reset animation state
        _chasePosition = 0;
        _shimmerState = NO;
        _rgbCyclePhase = 0;

        // Start the test timer
        NSTimeInterval interval = [self timerIntervalForSpeed:_chaseSpeed];
        _testTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                      target:self
                                                    selector:@selector(testTimerFired:)
                                                    userInfo:nil
                                                     repeats:YES];
    } else {
        _statusLabel.stringValue = @"Output: Failed to start";
        _statusLabel.textColor = [NSColor systemRedColor];
    }
}

- (void)stopOutput {
    if (!_isOutputActive) return;

    // Stop the timer
    [_testTimer invalidate];
    _testTimer = nil;

    // Turn off all channels and stop output
    [_engineBridge allTestChannelsOff];
    [_engineBridge endTestFrame];
    [_engineBridge stopOutput];

    _isOutputActive = NO;
    _outputToggleButton.title = @"Start Output";
    _statusLabel.stringValue = @"Output: Stopped";
    _statusLabel.textColor = [NSColor secondaryLabelColor];
}

- (void)patternChanged:(id)sender {
    _testPattern = (XLPixelTestPattern)_patternPopup.indexOfSelectedItem;
    _chasePosition = 0;
    _shimmerState = NO;
    _rgbCyclePhase = 0;
}

- (void)foregroundColorChanged:(id)sender {
    _testColor = _foregroundColorWell.color;
}

- (void)backgroundColorChanged:(id)sender {
    _backgroundColor = _backgroundColorWell.color;
}

- (void)speedChanged:(id)sender {
    _chaseSpeed = _speedSlider.integerValue;
    _speedLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)_chaseSpeed];

    // Update timer interval if running
    if (_testTimer) {
        [_testTimer invalidate];
        NSTimeInterval interval = [self timerIntervalForSpeed:_chaseSpeed];
        _testTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                      target:self
                                                    selector:@selector(testTimerFired:)
                                                    userInfo:nil
                                                     repeats:YES];
    }
}

- (void)selectAllModels:(id)sender {
    NSArray *models = [_engineBridge getModelNamesExcludingGroups];
    [_selectedModels removeAllObjects];
    [_selectedModels addObjectsFromArray:models];
    [_modelOutlineView reloadData];
}

- (void)deselectAllModels:(id)sender {
    [_selectedModels removeAllObjects];
    [_modelOutlineView reloadData];
}

- (void)closeDialog:(id)sender {
    [self stopOutput];
    [self.window close];
    if (_completionBlock) {
        _completionBlock();
    }
}

#pragma mark - Timer

- (NSTimeInterval)timerIntervalForSpeed:(NSInteger)speed {
    // Speed 1 = slow (500ms), speed 100 = fast (20ms)
    return 0.02 + (100 - speed) * 0.0048;
}

- (void)testTimerFired:(NSTimer *)timer {
    if (!_isOutputActive) return;

    [_engineBridge startTestFrame];
    [_engineBridge allTestChannelsOff];

    // Get all selected model channel ranges
    NSMutableArray<NSDictionary *> *allChannels = [NSMutableArray array];

    for (NSString *modelName in _selectedModels) {
        NSDictionary *channelInfo = [_engineBridge getModelChannelInfo:modelName];
        if (channelInfo) {
            NSInteger startChannel = [channelInfo[@"startChannel"] integerValue];
            NSInteger channelCount = [channelInfo[@"channelCount"] integerValue];
            [allChannels addObject:@{
                @"modelName": modelName,
                @"startChannel": @(startChannel),
                @"channelCount": @(channelCount)
            }];
        }
    }

    if (allChannels.count == 0) {
        [_engineBridge endTestFrame];
        return;
    }

    // Apply the test pattern
    [self applyTestPattern:_testPattern toChannels:allChannels];

    [_engineBridge endTestFrame];
}

- (void)applyTestPattern:(XLPixelTestPattern)pattern toChannels:(NSArray<NSDictionary *> *)channels {
    // Get RGB values from colors
    CGFloat fgR, fgG, fgB, fgA;
    CGFloat bgR, bgG, bgB, bgA;

    NSColor *fgColor = [_testColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    NSColor *bgColor = [_backgroundColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];

    [fgColor getRed:&fgR green:&fgG blue:&fgB alpha:&fgA];
    [bgColor getRed:&bgR green:&bgG blue:&bgB alpha:&bgA];

    uint8_t fgRed = (uint8_t)(fgR * 255);
    uint8_t fgGreen = (uint8_t)(fgG * 255);
    uint8_t fgBlue = (uint8_t)(fgB * 255);
    uint8_t bgRed = (uint8_t)(bgR * 255);
    uint8_t bgGreen = (uint8_t)(bgG * 255);
    uint8_t bgBlue = (uint8_t)(bgB * 255);

    // Count total nodes (assuming 3 channels per node for RGB)
    NSInteger totalNodes = 0;
    for (NSDictionary *ch in channels) {
        totalNodes += [ch[@"channelCount"] integerValue] / 3;
    }

    if (totalNodes == 0) totalNodes = 1;

    switch (pattern) {
        case XLPixelTestPatternOff:
            // All off - already done by allTestChannelsOff
            break;

        case XLPixelTestPatternAllOn:
            // Set all channels to foreground color
            for (NSDictionary *ch in channels) {
                NSInteger start = [ch[@"startChannel"] integerValue];
                NSInteger count = [ch[@"channelCount"] integerValue];

                for (NSInteger i = 0; i < count; i += 3) {
                    if (i + 2 < count) {
                        [_engineBridge setTestChannel:start + i value:fgRed];
                        [_engineBridge setTestChannel:start + i + 1 value:fgGreen];
                        [_engineBridge setTestChannel:start + i + 2 value:fgBlue];
                    }
                }
            }
            break;

        case XLPixelTestPatternChase:
        case XLPixelTestPatternChase3:
        case XLPixelTestPatternChase4:
        case XLPixelTestPatternChase5: {
            NSInteger chaseGrouping = 1;
            if (pattern == XLPixelTestPatternChase3) chaseGrouping = 3;
            else if (pattern == XLPixelTestPatternChase4) chaseGrouping = 4;
            else if (pattern == XLPixelTestPatternChase5) chaseGrouping = 5;

            NSInteger nodeIndex = 0;
            for (NSDictionary *ch in channels) {
                NSInteger start = [ch[@"startChannel"] integerValue];
                NSInteger count = [ch[@"channelCount"] integerValue];

                for (NSInteger i = 0; i < count; i += 3) {
                    BOOL isHighlight = ((nodeIndex % chaseGrouping) == (_chasePosition % chaseGrouping));
                    uint8_t r = isHighlight ? fgRed : bgRed;
                    uint8_t g = isHighlight ? fgGreen : bgGreen;
                    uint8_t b = isHighlight ? fgBlue : bgBlue;

                    if (i + 2 < count) {
                        [_engineBridge setTestChannel:start + i value:r];
                        [_engineBridge setTestChannel:start + i + 1 value:g];
                        [_engineBridge setTestChannel:start + i + 2 value:b];
                    }
                    nodeIndex++;
                }
            }
            _chasePosition = (_chasePosition + 1) % MAX(chaseGrouping, totalNodes);
            break;
        }

        case XLPixelTestPatternAlternate: {
            NSInteger nodeIndex = 0;
            for (NSDictionary *ch in channels) {
                NSInteger start = [ch[@"startChannel"] integerValue];
                NSInteger count = [ch[@"channelCount"] integerValue];

                for (NSInteger i = 0; i < count; i += 3) {
                    BOOL isHighlight = ((nodeIndex + _chasePosition) % 2) == 0;
                    uint8_t r = isHighlight ? fgRed : bgRed;
                    uint8_t g = isHighlight ? fgGreen : bgGreen;
                    uint8_t b = isHighlight ? fgBlue : bgBlue;

                    if (i + 2 < count) {
                        [_engineBridge setTestChannel:start + i value:r];
                        [_engineBridge setTestChannel:start + i + 1 value:g];
                        [_engineBridge setTestChannel:start + i + 2 value:b];
                    }
                    nodeIndex++;
                }
            }
            _chasePosition = (_chasePosition + 1) % 2;
            break;
        }

        case XLPixelTestPatternTwinkle5:
        case XLPixelTestPatternTwinkle10:
        case XLPixelTestPatternTwinkle25:
        case XLPixelTestPatternTwinkle50: {
            float probability = 0.05f;
            if (pattern == XLPixelTestPatternTwinkle10) probability = 0.10f;
            else if (pattern == XLPixelTestPatternTwinkle25) probability = 0.25f;
            else if (pattern == XLPixelTestPatternTwinkle50) probability = 0.50f;

            for (NSDictionary *ch in channels) {
                NSInteger start = [ch[@"startChannel"] integerValue];
                NSInteger count = [ch[@"channelCount"] integerValue];

                for (NSInteger i = 0; i < count; i += 3) {
                    BOOL isHighlight = (arc4random_uniform(1000) / 1000.0f) < probability;
                    uint8_t r = isHighlight ? fgRed : bgRed;
                    uint8_t g = isHighlight ? fgGreen : bgGreen;
                    uint8_t b = isHighlight ? fgBlue : bgBlue;

                    if (i + 2 < count) {
                        [_engineBridge setTestChannel:start + i value:r];
                        [_engineBridge setTestChannel:start + i + 1 value:g];
                        [_engineBridge setTestChannel:start + i + 2 value:b];
                    }
                }
            }
            break;
        }

        case XLPixelTestPatternShimmer: {
            uint8_t r = _shimmerState ? fgRed : bgRed;
            uint8_t g = _shimmerState ? fgGreen : bgGreen;
            uint8_t b = _shimmerState ? fgBlue : bgBlue;

            for (NSDictionary *ch in channels) {
                NSInteger start = [ch[@"startChannel"] integerValue];
                NSInteger count = [ch[@"channelCount"] integerValue];

                for (NSInteger i = 0; i < count; i += 3) {
                    if (i + 2 < count) {
                        [_engineBridge setTestChannel:start + i value:r];
                        [_engineBridge setTestChannel:start + i + 1 value:g];
                        [_engineBridge setTestChannel:start + i + 2 value:b];
                    }
                }
            }
            _shimmerState = !_shimmerState;
            break;
        }

        case XLPixelTestPatternRGBCycle: {
            // Cycle through R -> G -> B -> W -> Off
            uint8_t r = 0, g = 0, b = 0;
            switch (_rgbCyclePhase % 5) {
                case 0: r = 255; g = 0; b = 0; break;   // Red
                case 1: r = 0; g = 255; b = 0; break;   // Green
                case 2: r = 0; g = 0; b = 255; break;   // Blue
                case 3: r = 255; g = 255; b = 255; break; // White
                case 4: r = 0; g = 0; b = 0; break;     // Off
            }

            for (NSDictionary *ch in channels) {
                NSInteger start = [ch[@"startChannel"] integerValue];
                NSInteger count = [ch[@"channelCount"] integerValue];

                for (NSInteger i = 0; i < count; i += 3) {
                    if (i + 2 < count) {
                        [_engineBridge setTestChannel:start + i value:r];
                        [_engineBridge setTestChannel:start + i + 1 value:g];
                        [_engineBridge setTestChannel:start + i + 2 value:b];
                    }
                }
            }
            _rgbCyclePhase++;
            break;
        }

        case XLPixelTestPatternColorBlocks: {
            // Each model gets a different color from a palette
            NSArray *palette = @[
                [NSColor redColor],
                [NSColor greenColor],
                [NSColor blueColor],
                [NSColor yellowColor],
                [NSColor cyanColor],
                [NSColor magentaColor],
                [NSColor orangeColor],
                [NSColor purpleColor]
            ];

            NSInteger colorIndex = 0;
            for (NSDictionary *ch in channels) {
                NSInteger start = [ch[@"startChannel"] integerValue];
                NSInteger count = [ch[@"channelCount"] integerValue];

                NSColor *blockColor = [palette[colorIndex % palette.count] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
                CGFloat cR, cG, cB, cA;
                [blockColor getRed:&cR green:&cG blue:&cB alpha:&cA];

                for (NSInteger i = 0; i < count; i += 3) {
                    if (i + 2 < count) {
                        [_engineBridge setTestChannel:start + i value:(uint8_t)(cR * 255)];
                        [_engineBridge setTestChannel:start + i + 1 value:(uint8_t)(cG * 255)];
                        [_engineBridge setTestChannel:start + i + 2 value:(uint8_t)(cB * 255)];
                    }
                }
                colorIndex++;
            }
            break;
        }
    }
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nil) {
        // Root level - return number of models
        return [[_engineBridge getModelNamesExcludingGroups] count];
    }
    return 0; // No children for models
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nil) {
        NSArray *models = [_engineBridge getModelNamesExcludingGroups];
        if (index < (NSInteger)models.count) {
            return models[index];
        }
    }
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return NO; // Models are not expandable in this simple view
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    NSString *modelName = item;

    if ([tableColumn.identifier isEqualToString:@"check"]) {
        NSButton *checkbox = [outlineView makeViewWithIdentifier:@"checkCell" owner:self];
        if (!checkbox) {
            checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(modelCheckboxChanged:)];
            checkbox.identifier = @"checkCell";
        }
        checkbox.state = [_selectedModels containsObject:modelName] ? NSControlStateValueOn : NSControlStateValueOff;
        NSArray *models = [_engineBridge getModelNamesExcludingGroups];
        NSUInteger idx = [models indexOfObject:modelName];
        checkbox.tag = (idx != NSNotFound) ? (NSInteger)idx : -1;
        return checkbox;
    } else {
        NSTextField *textField = [outlineView makeViewWithIdentifier:@"nameCell" owner:self];
        if (!textField) {
            textField = [NSTextField labelWithString:@""];
            textField.identifier = @"nameCell";
        }
        textField.stringValue = modelName ?: @"";
        return textField;
    }
}

- (void)modelCheckboxChanged:(NSButton *)sender {
    NSArray *models = [_engineBridge getModelNamesExcludingGroups];
    NSInteger index = sender.tag;
    if (index >= 0 && index < (NSInteger)models.count) {
        NSString *modelName = models[index];
        if (sender.state == NSControlStateValueOn) {
            [_selectedModels addObject:modelName];
        } else {
            [_selectedModels removeObject:modelName];
        }
    }
}

#pragma mark - Public

- (void)showWithCompletion:(void (^)(void))completion {
    _completionBlock = completion;

    // Reload the model list
    [_modelOutlineView reloadData];

    // If models were preset, select them
    if (_modelNames && _modelNames.count > 0) {
        [_selectedModels removeAllObjects];
        [_selectedModels addObjectsFromArray:_modelNames];
        [_modelOutlineView reloadData];
    }

    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

@end

#pragma mark - XLGenerateCustomModelDialog Private Interface

@interface XLGenerateCustomModelDialog ()

@property (nonatomic, strong) NSTabView *sourceTabView;
@property (nonatomic, strong) NSImageView *previewImageView;
@property (nonatomic, strong) NSImageView *sourceImageView;
@property (nonatomic, strong) NSTextField *nodeCountLabel;
@property (nonatomic, strong) NSTextField *dimensionsLabel;
@property (nonatomic, strong) NSTextField *modelNameField;
@property (nonatomic, strong) NSSlider *thresholdSlider;
@property (nonatomic, strong) NSTextField *thresholdLabel;
@property (nonatomic, strong) NSSlider *brightnessSlider;
@property (nonatomic, strong) NSTextField *brightnessLabel;
@property (nonatomic, strong) NSSlider *scaleSlider;
@property (nonatomic, strong) NSTextField *scaleLabel;
@property (nonatomic, strong) NSButton *invertCheckbox;
@property (nonatomic, strong) NSTextField *gridColumnsField;
@property (nonatomic, strong) NSTextField *gridRowsField;
@property (nonatomic, strong) NSTextField *hSpacingField;
@property (nonatomic, strong) NSTextField *vSpacingField;
@property (nonatomic, strong) NSPopUpButton *numberingPopup;
@property (nonatomic, strong) NSPopUpButton *startCornerPopup;
@property (nonatomic, strong) NSButton *snakeCheckbox;
@property (nonatomic, strong) NSImage *loadedSourceImage;
@property (nonatomic, strong) NSImage *currentPreviewImage;
@property (nonatomic, assign) NSInteger internalGridWidth;
@property (nonatomic, assign) NSInteger internalGridHeight;
@property (nonatomic, assign) NSInteger internalNodeCount;
@property (nonatomic, copy) NSString *internalModelData;
@property (nonatomic, copy) void (^completionHandler)(BOOL);
@property (nonatomic, strong) NSMutableArray<NSValue *> *detectedPixels;

// Video source properties
@property (nonatomic, strong) XLVideoModelGenerator *videoGenerator;
@property (nonatomic, strong) NSImageView *videoPreviewImageView;
@property (nonatomic, strong) NSTextField *videoFileLabel;
@property (nonatomic, strong) NSTextField *videoNodeCountField;
@property (nonatomic, strong) NSButton *videoSteadyCheckbox;
@property (nonatomic, strong) NSSlider *videoSensitivitySlider;
@property (nonatomic, strong) NSTextField *videoSensitivityLabel;
@property (nonatomic, strong) NSSlider *videoContrastSlider;
@property (nonatomic, strong) NSTextField *videoContrastLabel;
@property (nonatomic, strong) NSSlider *videoBlurSlider;
@property (nonatomic, strong) NSTextField *videoBlurLabel;
@property (nonatomic, strong) NSSlider *videoGammaSlider;
@property (nonatomic, strong) NSTextField *videoGammaLabel;
@property (nonatomic, strong) NSSlider *videoMinSepSlider;
@property (nonatomic, strong) NSTextField *videoMinSepLabel;
@property (nonatomic, strong) NSProgressIndicator *videoProgressBar;
@property (nonatomic, strong) NSTextField *videoStatusLabel;
@property (nonatomic, strong) NSTextField *videoStatsLabel;
@property (nonatomic, strong) NSButton *videoProcessButton;

@end

@implementation XLGenerateCustomModelDialog

static const CGFloat kGenDialogWidth = 900.0;
static const CGFloat kGenDialogHeight = 650.0;
static const CGFloat kGenLabelWidth = 120.0;

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kGenDialogWidth, kGenDialogHeight)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    window.title = @"Generate Custom Model";
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(700, 500);

    self = [super initWithWindow:window];
    if (self) {
        _generationSource = XLCustomModelGenerationSourceImage;
        _detectionThreshold = 128;
        _minimumBrightness = 10;
        _modelName = @"Custom Model";
        _blurAmount = 0;
        _invertDetection = NO;
        _scaleFactor = 1;
        _gridColumns = 10;
        _gridRows = 10;
        _horizontalSpacing = 1;
        _verticalSpacing = 1;
        _gridNumberingDirection = @"horizontal";
        _gridSnakeNumbering = NO;
        _gridStartCorner = @"topleft";
        _svgNodeCount = 50;
        _mathXMin = -1.0;
        _mathXMax = 1.0;
        _mathYMin = -1.0;
        _mathYMax = 1.0;
        _mathResolution = 50;
        _detectedPixels = [NSMutableArray array];
        _videoExpectedNodes = 100;
        _videoSteadyCamera = YES;
        _videoGenerator = [[XLVideoModelGenerator alloc] init];

        [self buildGenUI];
    }
    return self;
}

- (NSImage *)sourceImage { return _loadedSourceImage; }
- (NSInteger)generatedNodeCount { return _internalNodeCount; }
- (NSString *)generatedModelData { return _internalModelData; }
- (NSInteger)gridWidth { return _internalGridWidth; }
- (NSInteger)gridHeight { return _internalGridHeight; }

#pragma mark - UI Building

- (void)buildGenUI {
    NSView *contentView = self.window.contentView;

    NSSplitView *splitView = [[NSSplitView alloc] initWithFrame:contentView.bounds];
    splitView.translatesAutoresizingMaskIntoConstraints = NO;
    splitView.vertical = YES;
    splitView.dividerStyle = NSSplitViewDividerStyleThin;
    [contentView addSubview:splitView];

    NSView *leftPanel = [[NSView alloc] initWithFrame:NSZeroRect];
    [splitView addArrangedSubview:leftPanel];

    NSView *rightPanel = [[NSView alloc] initWithFrame:NSZeroRect];
    [splitView addArrangedSubview:rightPanel];

    [NSLayoutConstraint activateConstraints:@[
        [splitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [splitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [splitView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [splitView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-60],
        [leftPanel.widthAnchor constraintEqualToConstant:400],
    ]];

    [self buildGenLeftPanel:leftPanel];
    [self buildGenRightPanel:rightPanel];
    [self buildGenButtonBar:contentView];
}

- (void)buildGenLeftPanel:(NSView *)panel {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 12;
    stack.alignment = NSLayoutAttributeLeading;
    [panel addSubview:stack];

    NSTextField *nameLabel = [NSTextField labelWithString:@"Model Name:"];
    _modelNameField = [XLBaseSheetController createTextField];
    _modelNameField.stringValue = _modelName;
    [_modelNameField.widthAnchor constraintEqualToConstant:200].active = YES;

    NSStackView *nameRow = [NSStackView stackViewWithViews:@[nameLabel, _modelNameField]];
    nameRow.spacing = 8;
    [stack addArrangedSubview:nameRow];

    _sourceTabView = [[NSTabView alloc] initWithFrame:NSZeroRect];
    _sourceTabView.translatesAutoresizingMaskIntoConstraints = NO;
    _sourceTabView.tabViewType = NSTopTabsBezelBorder;

    NSTabViewItem *imageTab = [[NSTabViewItem alloc] initWithIdentifier:@"image"];
    imageTab.label = @"Image";
    imageTab.view = [self buildGenImageSourceView];
    [_sourceTabView addTabViewItem:imageTab];

    NSTabViewItem *videoTab = [[NSTabViewItem alloc] initWithIdentifier:@"video"];
    videoTab.label = @"Video";
    videoTab.view = [self buildGenVideoSourceView];
    [_sourceTabView addTabViewItem:videoTab];

    NSTabViewItem *gridTab = [[NSTabViewItem alloc] initWithIdentifier:@"grid"];
    gridTab.label = @"Grid";
    gridTab.view = [self buildGenGridSourceView];
    [_sourceTabView addTabViewItem:gridTab];

    NSTabViewItem *svgTab = [[NSTabViewItem alloc] initWithIdentifier:@"svg"];
    svgTab.label = @"SVG Path";
    svgTab.view = [self buildGenPlaceholderView:@"SVG path import coming soon."];
    [_sourceTabView addTabViewItem:svgTab];

    NSTabViewItem *mathTab = [[NSTabViewItem alloc] initWithIdentifier:@"math"];
    mathTab.label = @"Math Function";
    mathTab.view = [self buildGenPlaceholderView:@"Mathematical function generation coming soon."];
    [_sourceTabView addTabViewItem:mathTab];

    NSTabViewItem *importTab = [[NSTabViewItem alloc] initWithIdentifier:@"import"];
    importTab.label = @"Import";
    importTab.view = [self buildGenPlaceholderView:@"Import from other formats coming soon."];
    [_sourceTabView addTabViewItem:importTab];

    [stack addArrangedSubview:_sourceTabView];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12],
        [_sourceTabView.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_sourceTabView.heightAnchor constraintGreaterThanOrEqualToConstant:400],
    ]];
}

- (NSView *)buildGenImageSourceView {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 10;
    stack.alignment = NSLayoutAttributeLeading;
    stack.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);

    NSButton *loadButton = [NSButton buttonWithTitle:@"Load Image..." target:self action:@selector(genLoadImageClicked:)];
    [stack addArrangedSubview:loadButton];

    _sourceImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 150, 100)];
    _sourceImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _sourceImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _sourceImageView.wantsLayer = YES;
    _sourceImageView.layer.borderWidth = 1;
    _sourceImageView.layer.borderColor = [[NSColor gridColor] CGColor];
    [_sourceImageView.widthAnchor constraintEqualToConstant:150].active = YES;
    [_sourceImageView.heightAnchor constraintEqualToConstant:100].active = YES;
    [stack addArrangedSubview:_sourceImageView];

    _thresholdSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _thresholdSlider.minValue = 0;
    _thresholdSlider.maxValue = 255;
    _thresholdSlider.integerValue = _detectionThreshold;
    [_thresholdSlider setTarget:self];
    [_thresholdSlider setAction:@selector(genThresholdChanged:)];
    [_thresholdSlider.widthAnchor constraintEqualToConstant:150].active = YES;
    _thresholdLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld", (long)_detectionThreshold]];
    [_thresholdLabel.widthAnchor constraintEqualToConstant:40].active = YES;
    [stack addArrangedSubview:[self genSliderRowWithLabel:@"Threshold:" slider:_thresholdSlider valueLabel:_thresholdLabel]];

    _brightnessSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _brightnessSlider.minValue = 0;
    _brightnessSlider.maxValue = 255;
    _brightnessSlider.integerValue = _minimumBrightness;
    [_brightnessSlider setTarget:self];
    [_brightnessSlider setAction:@selector(genBrightnessChanged:)];
    [_brightnessSlider.widthAnchor constraintEqualToConstant:150].active = YES;
    _brightnessLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld", (long)_minimumBrightness]];
    [_brightnessLabel.widthAnchor constraintEqualToConstant:40].active = YES;
    [stack addArrangedSubview:[self genSliderRowWithLabel:@"Min Brightness:" slider:_brightnessSlider valueLabel:_brightnessLabel]];

    _scaleSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _scaleSlider.minValue = 1;
    _scaleSlider.maxValue = 10;
    _scaleSlider.integerValue = _scaleFactor;
    [_scaleSlider setTarget:self];
    [_scaleSlider setAction:@selector(genScaleChanged:)];
    [_scaleSlider.widthAnchor constraintEqualToConstant:150].active = YES;
    _scaleLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld:1", (long)_scaleFactor]];
    [_scaleLabel.widthAnchor constraintEqualToConstant:40].active = YES;
    [stack addArrangedSubview:[self genSliderRowWithLabel:@"Scale Factor:" slider:_scaleSlider valueLabel:_scaleLabel]];

    _invertCheckbox = [NSButton checkboxWithTitle:@"Invert detection (detect dark pixels)" target:self action:@selector(genInvertChanged:)];
    _invertCheckbox.state = _invertDetection ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_invertCheckbox];

    NSButton *generateButton = [NSButton buttonWithTitle:@"Generate Preview" target:self action:@selector(genPreviewClicked:)];
    [stack addArrangedSubview:generateButton];

    NSTextField *infoLabel = [NSTextField wrappingLabelWithString:@"Load an image and adjust the threshold to detect pixels. Light pixels above the threshold will become nodes."];
    infoLabel.textColor = [NSColor secondaryLabelColor];
    infoLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:infoLabel];

    return stack;
}

- (NSStackView *)genSliderRowWithLabel:(NSString *)label slider:(NSSlider *)slider valueLabel:(NSTextField *)valueLabel {
    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 8;
    NSTextField *title = [NSTextField labelWithString:label];
    title.alignment = NSTextAlignmentRight;
    [title.widthAnchor constraintEqualToConstant:kGenLabelWidth].active = YES;
    [row addArrangedSubview:title];
    [row addArrangedSubview:slider];
    [row addArrangedSubview:valueLabel];
    return row;
}

- (NSView *)buildGenVideoSourceView {
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.drawsBackground = NO;

    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 10;
    stack.alignment = NSLayoutAttributeLeading;
    stack.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);

    // Description
    NSTextField *descLabel = [NSTextField wrappingLabelWithString:
        @"Generate a custom model from a video recording of your physical display. "
        @"Record a video while xLights runs the identification sequence, then load the video here to detect pixel positions."];
    descLabel.textColor = [NSColor secondaryLabelColor];
    descLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:descLabel];

    // Load video button and file label
    NSButton *loadButton = [NSButton buttonWithTitle:@"Load Video..." target:self action:@selector(genVideoLoadClicked:)];
    _videoFileLabel = [NSTextField labelWithString:@"No video loaded"];
    _videoFileLabel.textColor = [NSColor secondaryLabelColor];
    _videoFileLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSStackView *loadRow = [NSStackView stackViewWithViews:@[loadButton, _videoFileLabel]];
    loadRow.spacing = 8;
    [stack addArrangedSubview:loadRow];

    // Video preview
    _videoPreviewImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 340, 200)];
    _videoPreviewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _videoPreviewImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _videoPreviewImageView.wantsLayer = YES;
    _videoPreviewImageView.layer.borderWidth = 1;
    _videoPreviewImageView.layer.borderColor = [[NSColor gridColor] CGColor];
    _videoPreviewImageView.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];
    [_videoPreviewImageView.widthAnchor constraintEqualToConstant:340].active = YES;
    [_videoPreviewImageView.heightAnchor constraintEqualToConstant:200].active = YES;
    [stack addArrangedSubview:_videoPreviewImageView];

    // Expected node count
    _videoNodeCountField = [XLBaseSheetController createNumericField];
    _videoNodeCountField.integerValue = _videoExpectedNodes;
    [_videoNodeCountField.widthAnchor constraintEqualToConstant:80].active = YES;
    [stack addArrangedSubview:[XLBaseSheetController formRowWithLabel:@"Expected Nodes:" control:_videoNodeCountField labelWidth:kGenLabelWidth]];

    // Steady camera checkbox
    _videoSteadyCheckbox = [NSButton checkboxWithTitle:@"Camera is stationary (enables background subtraction)" target:nil action:nil];
    _videoSteadyCheckbox.state = _videoSteadyCamera ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_videoSteadyCheckbox];

    // Separator
    NSBox *sep1 = [[NSBox alloc] init];
    sep1.boxType = NSBoxSeparator;
    [sep1.widthAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;
    [stack addArrangedSubview:sep1];

    // Processing parameters header
    NSTextField *paramsHeader = [NSTextField labelWithString:@"Processing Parameters"];
    paramsHeader.font = [NSFont boldSystemFontOfSize:12];
    [stack addArrangedSubview:paramsHeader];

    // Sensitivity (threshold)
    _videoSensitivitySlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _videoSensitivitySlider.minValue = 1;
    _videoSensitivitySlider.maxValue = 255;
    _videoSensitivitySlider.integerValue = 128;
    [_videoSensitivitySlider setTarget:self];
    [_videoSensitivitySlider setAction:@selector(genVideoSensitivityChanged:)];
    [_videoSensitivitySlider.widthAnchor constraintEqualToConstant:140].active = YES;
    _videoSensitivityLabel = [NSTextField labelWithString:@"128"];
    [_videoSensitivityLabel.widthAnchor constraintEqualToConstant:35].active = YES;
    [stack addArrangedSubview:[self genSliderRowWithLabel:@"Sensitivity:" slider:_videoSensitivitySlider valueLabel:_videoSensitivityLabel]];

    // Contrast
    _videoContrastSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _videoContrastSlider.minValue = -100;
    _videoContrastSlider.maxValue = 100;
    _videoContrastSlider.integerValue = 0;
    [_videoContrastSlider setTarget:self];
    [_videoContrastSlider setAction:@selector(genVideoContrastChanged:)];
    [_videoContrastSlider.widthAnchor constraintEqualToConstant:140].active = YES;
    _videoContrastLabel = [NSTextField labelWithString:@"0"];
    [_videoContrastLabel.widthAnchor constraintEqualToConstant:35].active = YES;
    [stack addArrangedSubview:[self genSliderRowWithLabel:@"Contrast:" slider:_videoContrastSlider valueLabel:_videoContrastLabel]];

    // Blur
    _videoBlurSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _videoBlurSlider.minValue = 0;
    _videoBlurSlider.maxValue = 20;
    _videoBlurSlider.integerValue = 1;
    [_videoBlurSlider setTarget:self];
    [_videoBlurSlider setAction:@selector(genVideoBlurChanged:)];
    [_videoBlurSlider.widthAnchor constraintEqualToConstant:140].active = YES;
    _videoBlurLabel = [NSTextField labelWithString:@"1"];
    [_videoBlurLabel.widthAnchor constraintEqualToConstant:35].active = YES;
    [stack addArrangedSubview:[self genSliderRowWithLabel:@"Blur:" slider:_videoBlurSlider valueLabel:_videoBlurLabel]];

    // Gamma
    _videoGammaSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _videoGammaSlider.minValue = 1;
    _videoGammaSlider.maxValue = 50;
    _videoGammaSlider.integerValue = 10;
    [_videoGammaSlider setTarget:self];
    [_videoGammaSlider setAction:@selector(genVideoGammaChanged:)];
    [_videoGammaSlider.widthAnchor constraintEqualToConstant:140].active = YES;
    _videoGammaLabel = [NSTextField labelWithString:@"1.0"];
    [_videoGammaLabel.widthAnchor constraintEqualToConstant:35].active = YES;
    [stack addArrangedSubview:[self genSliderRowWithLabel:@"Gamma:" slider:_videoGammaSlider valueLabel:_videoGammaLabel]];

    // Min separation
    _videoMinSepSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _videoMinSepSlider.minValue = 1;
    _videoMinSepSlider.maxValue = 50;
    _videoMinSepSlider.integerValue = 5;
    [_videoMinSepSlider setTarget:self];
    [_videoMinSepSlider setAction:@selector(genVideoMinSepChanged:)];
    [_videoMinSepSlider.widthAnchor constraintEqualToConstant:140].active = YES;
    _videoMinSepLabel = [NSTextField labelWithString:@"5"];
    [_videoMinSepLabel.widthAnchor constraintEqualToConstant:35].active = YES;
    [stack addArrangedSubview:[self genSliderRowWithLabel:@"Min Separation:" slider:_videoMinSepSlider valueLabel:_videoMinSepLabel]];

    // Separator
    NSBox *sep2 = [[NSBox alloc] init];
    sep2.boxType = NSBoxSeparator;
    [sep2.widthAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;
    [stack addArrangedSubview:sep2];

    // Progress bar
    _videoProgressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _videoProgressBar.translatesAutoresizingMaskIntoConstraints = NO;
    _videoProgressBar.style = NSProgressIndicatorStyleBar;
    _videoProgressBar.minValue = 0;
    _videoProgressBar.maxValue = 1.0;
    _videoProgressBar.doubleValue = 0;
    [_videoProgressBar.widthAnchor constraintEqualToConstant:340].active = YES;
    _videoProgressBar.hidden = YES;
    [stack addArrangedSubview:_videoProgressBar];

    // Status label
    _videoStatusLabel = [NSTextField labelWithString:@""];
    _videoStatusLabel.textColor = [NSColor secondaryLabelColor];
    _videoStatusLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:_videoStatusLabel];

    // Process button
    _videoProcessButton = [NSButton buttonWithTitle:@"Detect Pixels from Video" target:self action:@selector(genVideoProcessClicked:)];
    _videoProcessButton.bezelStyle = NSBezelStyleRounded;
    [stack addArrangedSubview:_videoProcessButton];

    // Stats label
    _videoStatsLabel = [NSTextField wrappingLabelWithString:@""];
    _videoStatsLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    [stack addArrangedSubview:_videoStatsLabel];

    // Instructions
    NSTextField *infoLabel = [NSTextField wrappingLabelWithString:
        @"Workflow:\n"
        @"1. In xLights, run the Generate Custom Model sequence on your physical display\n"
        @"2. Record a video of the display during the sequence\n"
        @"3. Load the video above and click 'Detect Pixels'\n"
        @"4. Adjust parameters if needed and re-detect\n"
        @"5. Click 'Generate Model' to create the custom model"];
    infoLabel.textColor = [NSColor tertiaryLabelColor];
    infoLabel.font = [NSFont systemFontOfSize:10];
    [stack addArrangedSubview:infoLabel];

    scrollView.documentView = stack;

    // Size the stack within the scroll view
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scrollView.contentView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.contentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.contentView.trailingAnchor],
    ]];

    return scrollView;
}

#pragma mark - Video Actions

- (void)genVideoLoadClicked:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[
        [UTType typeWithIdentifier:@"public.movie"],
        [UTType typeWithIdentifier:@"public.mpeg-4"],
        [UTType typeWithIdentifier:@"com.apple.quicktime-movie"],
    ];
    panel.allowsMultipleSelection = NO;

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            [self loadVideoFromPath:panel.URL.path];
        }
    }];
}

- (BOOL)loadVideoFromPath:(NSString *)path {
    NSError *error = nil;
    BOOL success = [_videoGenerator loadVideoFromURL:[NSURL fileURLWithPath:path] error:&error];

    if (!success) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Failed to load video";
        alert.informativeText = error.localizedDescription ?: @"Unknown error";
        [alert runModal];
        return NO;
    }

    _videoFilePath = path;
    _videoFileLabel.stringValue = [path lastPathComponent];
    _videoPreviewImageView.image = _videoGenerator.firstFrameImage;

    _videoStatusLabel.stringValue = [NSString stringWithFormat:@"Video loaded: %.1fs, %.0fx%.0f, %.1f fps",
        _videoGenerator.videoDuration,
        _videoGenerator.videoDimensions.width,
        _videoGenerator.videoDimensions.height,
        _videoGenerator.videoFrameRate];

    return YES;
}

- (void)genVideoSensitivityChanged:(id)sender {
    _videoSensitivityLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)_videoSensitivitySlider.integerValue];
}

- (void)genVideoContrastChanged:(id)sender {
    _videoContrastLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)_videoContrastSlider.integerValue];
}

- (void)genVideoBlurChanged:(id)sender {
    _videoBlurLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)_videoBlurSlider.integerValue];
}

- (void)genVideoGammaChanged:(id)sender {
    float gamma = _videoGammaSlider.integerValue / 10.0;
    _videoGammaLabel.stringValue = [NSString stringWithFormat:@"%.1f", gamma];
}

- (void)genVideoMinSepChanged:(id)sender {
    _videoMinSepLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)_videoMinSepSlider.integerValue];
}

- (void)genVideoProcessClicked:(id)sender {
    if (!_videoGenerator.videoURL) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No video loaded";
        alert.informativeText = @"Please load a video file first.";
        [alert runModal];
        return;
    }

    // Read parameters from UI
    _videoGenerator.expectedNodeCount = _videoNodeCountField.integerValue;
    _videoGenerator.isSteadyCamera = (_videoSteadyCheckbox.state == NSControlStateValueOn);
    _videoGenerator.sensitivity = _videoSensitivitySlider.integerValue;
    _videoGenerator.contrast = _videoContrastSlider.integerValue;
    _videoGenerator.blur = _videoBlurSlider.integerValue;
    _videoGenerator.gamma = _videoGammaSlider.integerValue / 10.0;
    _videoGenerator.minSeparation = _videoMinSepSlider.integerValue;

    // Disable UI during processing
    _videoProcessButton.enabled = NO;
    _videoProgressBar.hidden = NO;
    _videoProgressBar.doubleValue = 0;

    __weak typeof(self) weakSelf = self;

    _videoGenerator.progressCallback = ^(float progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.videoProgressBar.doubleValue = progress;
        });
    };

    _videoGenerator.statusCallback = ^(NSString *status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.videoStatusLabel.stringValue = status;
        });
    };

    _videoGenerator.frameDisplayCallback = ^(NSImage *frame) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.videoPreviewImageView.image = frame;
        });
    };

    // Run processing on background thread
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Step 1: Find start frame
        BOOL startFound = [self->_videoGenerator findStartFrame];

        if (!startFound) {
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.videoProcessButton.enabled = YES;
                weakSelf.videoProgressBar.hidden = YES;
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Start pattern not found";
                alert.informativeText = @"Could not detect the start flash pattern in the video. "
                    @"Make sure the video was recorded during the xLights identification sequence, "
                    @"and that the camera can clearly see the display.";
                [alert runModal];
            });
            return;
        }

        // Step 2: Read node frames
        BOOL framesRead = [self->_videoGenerator readNodeFrames];

        if (!framesRead) {
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.videoProcessButton.enabled = YES;
                weakSelf.videoProgressBar.hidden = YES;
                weakSelf.videoStatusLabel.stringValue = @"Failed to read all expected frames from video.";
            });
            return;
        }

        // Step 3: Identify nodes
        NSInteger found = [self->_videoGenerator identifyNodes];

        // Step 4: Generate model data
        NSString *modelData = [self->_videoGenerator generateModelData];

        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.videoProcessButton.enabled = YES;
            weakSelf.videoProgressBar.hidden = YES;

            if (found > 0 && modelData) {
                // Update the shared model data
                NSRect bounds = [self->_videoGenerator detectedNodesBounds];
                NSInteger gridPadding = 4; // extra rows/columns for spacing
                NSInteger gridW = (NSInteger)(bounds.size.width / MAX(1, self->_videoGenerator.minSeparation)) + 1 + gridPadding;
                NSInteger gridH = (NSInteger)(bounds.size.height / MAX(1, self->_videoGenerator.minSeparation)) + 1 + gridPadding;

                weakSelf.internalGridWidth = gridW;
                weakSelf.internalGridHeight = gridH;
                weakSelf.internalNodeCount = found;
                weakSelf.internalModelData = modelData;

                // Update preview
                NSImage *preview = [self->_videoGenerator detectionPreviewImage];
                if (preview) {
                    weakSelf.previewImageView.image = preview;
                    weakSelf.videoPreviewImageView.image = preview;
                }

                weakSelf.nodeCountLabel.stringValue = [NSString stringWithFormat:@"Nodes: %ld", (long)found];
                weakSelf.dimensionsLabel.stringValue = [NSString stringWithFormat:@"Dimensions: %ld x %ld", (long)gridW, (long)gridH];

                // Update stats
                NSDictionary *stats = [self->_videoGenerator detectionStatistics];
                weakSelf.videoStatsLabel.stringValue = [NSString stringWithFormat:
                    @"Found: %@/%@ nodes\nMissing: %@\nGrid: %@ x %@",
                    stats[@"totalFound"], stats[@"totalExpected"],
                    stats[@"missingNodes"],
                    @(gridW), @(gridH)];
            } else {
                weakSelf.videoStatsLabel.stringValue = @"No nodes detected. Try adjusting parameters.";
            }
        });
    });
}

- (NSView *)buildGenGridSourceView {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 10;
    stack.alignment = NSLayoutAttributeLeading;
    stack.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);

    _gridColumnsField = [XLBaseSheetController createNumericField];
    _gridColumnsField.integerValue = _gridColumns;
    [_gridColumnsField.widthAnchor constraintEqualToConstant:60].active = YES;
    [stack addArrangedSubview:[XLBaseSheetController formRowWithLabel:@"Columns:" control:_gridColumnsField labelWidth:kGenLabelWidth]];

    _gridRowsField = [XLBaseSheetController createNumericField];
    _gridRowsField.integerValue = _gridRows;
    [_gridRowsField.widthAnchor constraintEqualToConstant:60].active = YES;
    [stack addArrangedSubview:[XLBaseSheetController formRowWithLabel:@"Rows:" control:_gridRowsField labelWidth:kGenLabelWidth]];

    _hSpacingField = [XLBaseSheetController createNumericField];
    _hSpacingField.integerValue = _horizontalSpacing;
    [_hSpacingField.widthAnchor constraintEqualToConstant:60].active = YES;
    [stack addArrangedSubview:[XLBaseSheetController formRowWithLabel:@"H Spacing:" control:_hSpacingField labelWidth:kGenLabelWidth]];

    _vSpacingField = [XLBaseSheetController createNumericField];
    _vSpacingField.integerValue = _verticalSpacing;
    [_vSpacingField.widthAnchor constraintEqualToConstant:60].active = YES;
    [stack addArrangedSubview:[XLBaseSheetController formRowWithLabel:@"V Spacing:" control:_vSpacingField labelWidth:kGenLabelWidth]];

    _startCornerPopup = [XLBaseSheetController createPopUpButton];
    [_startCornerPopup addItemWithTitle:@"Top Left"];
    [_startCornerPopup addItemWithTitle:@"Top Right"];
    [_startCornerPopup addItemWithTitle:@"Bottom Left"];
    [_startCornerPopup addItemWithTitle:@"Bottom Right"];
    _startCornerPopup.menu.itemArray[0].representedObject = @"topleft";
    _startCornerPopup.menu.itemArray[1].representedObject = @"topright";
    _startCornerPopup.menu.itemArray[2].representedObject = @"bottomleft";
    _startCornerPopup.menu.itemArray[3].representedObject = @"bottomright";
    [stack addArrangedSubview:[XLBaseSheetController formRowWithLabel:@"Start Corner:" control:_startCornerPopup labelWidth:kGenLabelWidth]];

    _numberingPopup = [XLBaseSheetController createPopUpButton];
    [_numberingPopup addItemWithTitle:@"Horizontal"];
    [_numberingPopup addItemWithTitle:@"Vertical"];
    _numberingPopup.menu.itemArray[0].representedObject = @"horizontal";
    _numberingPopup.menu.itemArray[1].representedObject = @"vertical";
    [stack addArrangedSubview:[XLBaseSheetController formRowWithLabel:@"Numbering:" control:_numberingPopup labelWidth:kGenLabelWidth]];

    _snakeCheckbox = [NSButton checkboxWithTitle:@"Snake numbering" target:nil action:nil];
    _snakeCheckbox.state = _gridSnakeNumbering ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_snakeCheckbox];

    NSButton *generateButton = [NSButton buttonWithTitle:@"Generate Preview" target:self action:@selector(genGridPreviewClicked:)];
    [stack addArrangedSubview:generateButton];

    NSTextField *infoLabel = [NSTextField wrappingLabelWithString:@"Generate a regular grid of nodes with customizable spacing and numbering order."];
    infoLabel.textColor = [NSColor secondaryLabelColor];
    infoLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:infoLabel];

    return stack;
}

- (NSView *)buildGenPlaceholderView:(NSString *)message {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 12;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.edgeInsets = NSEdgeInsetsMake(40, 20, 20, 20);

    NSImageView *iconView = [[NSImageView alloc] init];
    iconView.image = [NSImage imageWithSystemSymbolName:@"wrench.and.screwdriver" accessibilityDescription:@"Coming soon"];
    iconView.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:48 weight:NSFontWeightLight];
    iconView.contentTintColor = [NSColor tertiaryLabelColor];
    [stack addArrangedSubview:iconView];

    NSTextField *label = [NSTextField wrappingLabelWithString:message];
    label.alignment = NSTextAlignmentCenter;
    label.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:label];

    return stack;
}

- (void)buildGenRightPanel:(NSView *)panel {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 12;
    stack.alignment = NSLayoutAttributeLeading;
    [panel addSubview:stack];

    NSTextField *previewTitle = [NSTextField labelWithString:@"Preview"];
    previewTitle.font = [NSFont boldSystemFontOfSize:13];
    [stack addArrangedSubview:previewTitle];

    _previewImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    _previewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _previewImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _previewImageView.wantsLayer = YES;
    _previewImageView.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];
    _previewImageView.layer.borderWidth = 1;
    _previewImageView.layer.borderColor = [[NSColor gridColor] CGColor];
    [stack addArrangedSubview:_previewImageView];

    _nodeCountLabel = [NSTextField labelWithString:@"Nodes: 0"];
    _nodeCountLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    [stack addArrangedSubview:_nodeCountLabel];

    _dimensionsLabel = [NSTextField labelWithString:@"Dimensions: 0 x 0"];
    _dimensionsLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    [stack addArrangedSubview:_dimensionsLabel];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12],
        [_previewImageView.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_previewImageView.heightAnchor constraintEqualToConstant:400],
    ]];
}

- (void)buildGenButtonBar:(NSView *)contentView {
    NSStackView *buttonBar = [[NSStackView alloc] init];
    buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
    buttonBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonBar.spacing = 12;
    [contentView addSubview:buttonBar];

    NSButton *cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(genCancelClicked:)];
    cancelButton.keyEquivalent = @"\033";
    NSButton *okButton = [NSButton buttonWithTitle:@"Generate Model" target:self action:@selector(genOkClicked:)];
    okButton.keyEquivalent = @"\r";
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    [buttonBar addArrangedSubview:spacer];
    [buttonBar addArrangedSubview:cancelButton];
    [buttonBar addArrangedSubview:okButton];

    [NSLayoutConstraint activateConstraints:@[
        [buttonBar.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-12],
        [buttonBar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:12],
        [buttonBar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-12],
        [buttonBar.heightAnchor constraintEqualToConstant:30],
    ]];
}

#pragma mark - Actions

- (void)genLoadImageClicked:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithIdentifier:@"public.image"]];
    panel.allowsMultipleSelection = NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            [self loadImageFromPath:panel.URL.path];
        }
    }];
}

- (BOOL)loadImageFromPath:(NSString *)path {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    if (!image) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Failed to load image";
        alert.informativeText = [NSString stringWithFormat:@"Could not load image from: %@", path];
        [alert runModal];
        return NO;
    }
    _sourceImagePath = path;
    _loadedSourceImage = image;
    _sourceImageView.image = image;
    [self genGeneratePreviewFromImage];
    return YES;
}

- (void)genThresholdChanged:(id)sender {
    _detectionThreshold = _thresholdSlider.integerValue;
    _thresholdLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)_detectionThreshold];
    if (_loadedSourceImage) [self genGeneratePreviewFromImage];
}

- (void)genBrightnessChanged:(id)sender {
    _minimumBrightness = _brightnessSlider.integerValue;
    _brightnessLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)_minimumBrightness];
    if (_loadedSourceImage) [self genGeneratePreviewFromImage];
}

- (void)genScaleChanged:(id)sender {
    _scaleFactor = _scaleSlider.integerValue;
    _scaleLabel.stringValue = [NSString stringWithFormat:@"%ld:1", (long)_scaleFactor];
    if (_loadedSourceImage) [self genGeneratePreviewFromImage];
}

- (void)genInvertChanged:(id)sender {
    _invertDetection = (_invertCheckbox.state == NSControlStateValueOn);
    if (_loadedSourceImage) [self genGeneratePreviewFromImage];
}

- (void)genPreviewClicked:(id)sender {
    if (!_loadedSourceImage) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No image loaded";
        alert.informativeText = @"Please load an image first.";
        [alert runModal];
        return;
    }
    [self genGeneratePreviewFromImage];
}

- (void)genGridPreviewClicked:(id)sender {
    [self genGeneratePreviewFromGrid];
}

- (void)genCancelClicked:(id)sender {
    [self.window close];
    if (_completionHandler) _completionHandler(NO);
}

- (void)genOkClicked:(id)sender {
    _modelName = _modelNameField.stringValue;
    if (_modelName.length == 0) _modelName = @"Custom Model";
    if (_internalNodeCount == 0 || !_internalModelData) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No model generated";
        alert.informativeText = @"Please generate a preview first.";
        [alert runModal];
        return;
    }
    [self.window close];
    if (_completionHandler) _completionHandler(YES);
}

#pragma mark - Image Processing

- (void)genGeneratePreviewFromImage {
    if (!_loadedSourceImage) return;

    NSBitmapImageRep *bitmap = nil;
    for (NSImageRep *rep in _loadedSourceImage.representations) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            bitmap = (NSBitmapImageRep *)rep;
            break;
        }
    }

    if (!bitmap) {
        NSSize size = _loadedSourceImage.size;
        bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                        pixelsWide:(NSInteger)size.width
                                                        pixelsHigh:(NSInteger)size.height
                                                     bitsPerSample:8
                                                   samplesPerPixel:4
                                                          hasAlpha:YES
                                                          isPlanar:NO
                                                    colorSpaceName:NSCalibratedRGBColorSpace
                                                       bytesPerRow:0
                                                      bitsPerPixel:0];
        NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:ctx];
        [_loadedSourceImage drawInRect:NSMakeRect(0, 0, size.width, size.height)];
        [NSGraphicsContext restoreGraphicsState];
    }

    NSInteger width = bitmap.pixelsWide;
    NSInteger height = bitmap.pixelsHigh;
    NSInteger scaledWidth = MAX(1, width / _scaleFactor);
    NSInteger scaledHeight = MAX(1, height / _scaleFactor);

    [_detectedPixels removeAllObjects];

    for (NSInteger y = 0; y < scaledHeight; y++) {
        for (NSInteger x = 0; x < scaledWidth; x++) {
            NSInteger srcX = MIN(x * _scaleFactor + _scaleFactor / 2, width - 1);
            NSInteger srcY = MIN(y * _scaleFactor + _scaleFactor / 2, height - 1);
            NSColor *color = [bitmap colorAtX:srcX y:srcY];
            if (!color) continue;
            CGFloat brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3.0 * 255.0;
            BOOL detected = _invertDetection
                ? (brightness < _detectionThreshold && brightness <= (255 - _minimumBrightness))
                : (brightness >= _detectionThreshold && brightness >= _minimumBrightness);
            if (detected) {
                [_detectedPixels addObject:[NSValue valueWithPoint:NSMakePoint(x, y)]];
            }
        }
    }

    _internalGridWidth = scaledWidth;
    _internalGridHeight = scaledHeight;
    _internalNodeCount = _detectedPixels.count;

    [self genGenerateModelDataFromDetectedPixels];
    [self genCreatePreviewImage:scaledWidth height:scaledHeight];

    _nodeCountLabel.stringValue = [NSString stringWithFormat:@"Nodes: %ld", (long)_internalNodeCount];
    _dimensionsLabel.stringValue = [NSString stringWithFormat:@"Dimensions: %ld x %ld", (long)scaledWidth, (long)scaledHeight];
}

- (void)genGenerateModelDataFromDetectedPixels {
    if (_detectedPixels.count == 0) { _internalModelData = @""; return; }

    NSInteger width = _internalGridWidth;
    NSInteger height = _internalGridHeight;
    int *grid = (int *)calloc(width * height, sizeof(int));

    int nodeNum = 1;
    for (NSValue *val in _detectedPixels) {
        NSPoint pt = val.pointValue;
        NSInteger x = (NSInteger)pt.x;
        NSInteger y = (NSInteger)pt.y;
        if (x >= 0 && x < width && y >= 0 && y < height) {
            grid[y * width + x] = nodeNum++;
        }
    }

    NSMutableString *result = [NSMutableString string];
    for (NSInteger y = 0; y < height; y++) {
        NSMutableArray *rowCells = [NSMutableArray array];
        for (NSInteger x = 0; x < width; x++) {
            int num = grid[y * width + x];
            [rowCells addObject:(num > 0) ? [NSString stringWithFormat:@"%d", num] : @""];
        }
        [result appendString:[rowCells componentsJoinedByString:@","]];
        if (y < height - 1) [result appendString:@";"];
    }
    free(grid);
    _internalModelData = result;
}

- (void)genGeneratePreviewFromGrid {
    _gridColumns = MAX(1, _gridColumnsField.integerValue);
    _gridRows = MAX(1, _gridRowsField.integerValue);
    _horizontalSpacing = MAX(1, _hSpacingField.integerValue);
    _verticalSpacing = MAX(1, _vSpacingField.integerValue);
    _gridStartCorner = _startCornerPopup.selectedItem.representedObject ?: @"topleft";
    _gridNumberingDirection = _numberingPopup.selectedItem.representedObject ?: @"horizontal";
    _gridSnakeNumbering = (_snakeCheckbox.state == NSControlStateValueOn);

    NSInteger width = _gridColumns * _horizontalSpacing;
    NSInteger height = _gridRows * _verticalSpacing;

    _internalGridWidth = width;
    _internalGridHeight = height;
    _internalNodeCount = _gridColumns * _gridRows;

    [_detectedPixels removeAllObjects];
    int *grid = (int *)calloc(width * height, sizeof(int));

    BOOL startLeft = ![_gridStartCorner hasSuffix:@"right"];
    BOOL startTop = [_gridStartCorner hasPrefix:@"top"];
    BOOL horizontal = [_gridNumberingDirection isEqualToString:@"horizontal"];

    int nodeNum = 1;
    if (horizontal) {
        for (NSInteger row = 0; row < _gridRows; row++) {
            NSInteger y = startTop ? (row * _verticalSpacing) : (((_gridRows - 1) - row) * _verticalSpacing);
            BOOL leftToRight = startLeft;
            if (_gridSnakeNumbering && (row % 2 == 1)) leftToRight = !leftToRight;
            for (NSInteger col = 0; col < _gridColumns; col++) {
                NSInteger actualCol = leftToRight ? col : ((_gridColumns - 1) - col);
                NSInteger x = actualCol * _horizontalSpacing;
                grid[y * width + x] = nodeNum++;
                [_detectedPixels addObject:[NSValue valueWithPoint:NSMakePoint(x, y)]];
            }
        }
    } else {
        for (NSInteger col = 0; col < _gridColumns; col++) {
            NSInteger x = startLeft ? (col * _horizontalSpacing) : (((_gridColumns - 1) - col) * _horizontalSpacing);
            BOOL topToBottom = startTop;
            if (_gridSnakeNumbering && (col % 2 == 1)) topToBottom = !topToBottom;
            for (NSInteger row = 0; row < _gridRows; row++) {
                NSInteger actualRow = topToBottom ? row : ((_gridRows - 1) - row);
                NSInteger y = actualRow * _verticalSpacing;
                grid[y * width + x] = nodeNum++;
                [_detectedPixels addObject:[NSValue valueWithPoint:NSMakePoint(x, y)]];
            }
        }
    }

    NSMutableString *result = [NSMutableString string];
    for (NSInteger y = 0; y < height; y++) {
        NSMutableArray *rowCells = [NSMutableArray array];
        for (NSInteger x = 0; x < width; x++) {
            int num = grid[y * width + x];
            [rowCells addObject:(num > 0) ? [NSString stringWithFormat:@"%d", num] : @""];
        }
        [result appendString:[rowCells componentsJoinedByString:@","]];
        if (y < height - 1) [result appendString:@";"];
    }
    free(grid);
    _internalModelData = result;

    [self genCreatePreviewImage:width height:height];

    _nodeCountLabel.stringValue = [NSString stringWithFormat:@"Nodes: %ld", (long)_internalNodeCount];
    _dimensionsLabel.stringValue = [NSString stringWithFormat:@"Dimensions: %ld x %ld", (long)width, (long)height];
}

- (void)genCreatePreviewImage:(NSInteger)width height:(NSInteger)height {
    CGFloat previewSize = 380.0;
    CGFloat cellSize = MIN(MIN(previewSize / width, previewSize / height), 20.0);
    cellSize = MAX(cellSize, 2.0);

    CGFloat imageWidth = width * cellSize;
    CGFloat imageHeight = height * cellSize;

    NSImage *previewImage = [[NSImage alloc] initWithSize:NSMakeSize(imageWidth, imageHeight)];
    [previewImage lockFocus];

    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(NSMakeRect(0, 0, imageWidth, imageHeight));

    [[NSColor controlAccentColor] setFill];
    for (NSValue *val in _detectedPixels) {
        NSPoint pt = val.pointValue;
        NSRect cellRect = NSMakeRect(pt.x * cellSize, (height - 1 - pt.y) * cellSize, cellSize - 1, cellSize - 1);
        NSRectFill(cellRect);
    }

    if (width <= 100 && height <= 100) {
        [[NSColor gridColor] setStroke];
        NSBezierPath *gridPath = [NSBezierPath bezierPath];
        gridPath.lineWidth = 0.25;
        for (NSInteger x = 0; x <= width; x++) {
            [gridPath moveToPoint:NSMakePoint(x * cellSize, 0)];
            [gridPath lineToPoint:NSMakePoint(x * cellSize, imageHeight)];
        }
        for (NSInteger y = 0; y <= height; y++) {
            [gridPath moveToPoint:NSMakePoint(0, y * cellSize)];
            [gridPath lineToPoint:NSMakePoint(imageWidth, y * cellSize)];
        }
        [gridPath stroke];
    }

    [previewImage unlockFocus];
    _currentPreviewImage = previewImage;
    _previewImageView.image = previewImage;
}

- (NSImage *)getPreviewImage { return _currentPreviewImage; }

- (BOOL)generateModel { return (_internalModelData != nil && _internalModelData.length > 0); }

- (void)showWithCompletion:(void (^)(BOOL accepted))completion {
    _completionHandler = completion;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

@end

@implementation XLPathGenerationDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Path Generation";
        self.minWidth = 350;
        self.minHeight = 200;
        _nodeCount = 50;
        _pathType = @"linear";
        _reverseDirection = NO;
        _closedLoop = NO;
    }
    return self;
}

- (NSView *)buildContentView {
    // TODO: Full implementation
    NSTextField *placeholder = [NSTextField labelWithString:@"Path generation options will appear here"];
    return placeholder;
}

@end
