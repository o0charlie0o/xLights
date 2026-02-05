/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLMediaDialogs.h"

static const CGFloat kLabelWidth = 140.0;

#pragma mark - XLMediaImportOptionsDialog

@interface XLMediaImportOptionsDialog ()

@property (nonatomic, strong) NSButton *timingCheckbox;
@property (nonatomic, strong) NSButton *backgroundVideoCheckbox;
@property (nonatomic, strong) NSPopUpButton *scaleModePopup;
@property (nonatomic, strong) NSSlider *volumeSlider;
@property (nonatomic, strong) NSTextField *volumeLabel;
@property (nonatomic, strong) NSButton *loopCheckbox;

@end

@implementation XLMediaImportOptionsDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Media Import Options";
        self.minWidth = 400;
        self.minHeight = 220;
        _createTimingMarks = NO;
        _useAsBackgroundVideo = NO;
        _videoScaleMode = @"Fit";
        _audioVolume = 1.0;
        _loopMedia = NO;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Timing marks checkbox
    _timingCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Create timing marks from audio"];
    _timingCheckbox.state = _createTimingMarks ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_timingCheckbox];

    // Background video checkbox
    _backgroundVideoCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Use as background video"];
    _backgroundVideoCheckbox.state = _useAsBackgroundVideo ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_backgroundVideoCheckbox];

    // Scale mode
    _scaleModePopup = [XLBaseSheetController createPopUpButton];
    [_scaleModePopup addItemWithTitle:@"Fit"];
    [_scaleModePopup addItemWithTitle:@"Fill"];
    [_scaleModePopup addItemWithTitle:@"Stretch"];
    [_scaleModePopup selectItemWithTitle:_videoScaleMode];

    NSStackView *scaleRow = [XLBaseSheetController formRowWithLabel:@"Video Scale Mode:"
                                                            control:_scaleModePopup
                                                         labelWidth:kLabelWidth];
    [stack addArrangedSubview:scaleRow];

    // Volume slider
    NSStackView *volumeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    volumeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    volumeRow.spacing = 8;

    NSTextField *volLabel = [NSTextField labelWithString:@"Audio Volume:"];
    volLabel.alignment = NSTextAlignmentRight;
    [volLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _volumeSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _volumeSlider.minValue = 0.0;
    _volumeSlider.maxValue = 1.0;
    _volumeSlider.doubleValue = _audioVolume;
    [_volumeSlider setTarget:self];
    [_volumeSlider setAction:@selector(volumeChanged:)];
    [_volumeSlider.widthAnchor constraintEqualToConstant:150].active = YES;

    _volumeLabel = [NSTextField labelWithString:@"100%"];
    [_volumeLabel.widthAnchor constraintEqualToConstant:40].active = YES;

    [volumeRow addArrangedSubview:volLabel];
    [volumeRow addArrangedSubview:_volumeSlider];
    [volumeRow addArrangedSubview:_volumeLabel];
    [stack addArrangedSubview:volumeRow];

    // Loop checkbox
    _loopCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Loop media"];
    _loopCheckbox.state = _loopMedia ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_loopCheckbox];

    return stack;
}

- (void)volumeChanged:(id)sender {
    _volumeLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", _volumeSlider.doubleValue * 100];
}

- (void)okClicked:(id)sender {
    _createTimingMarks = (_timingCheckbox.state == NSControlStateValueOn);
    _useAsBackgroundVideo = (_backgroundVideoCheckbox.state == NSControlStateValueOn);
    _videoScaleMode = _scaleModePopup.selectedItem.title;
    _audioVolume = _volumeSlider.doubleValue;
    _loopMedia = (_loopCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end

#pragma mark - XLResizeImageDialog

@interface XLResizeImageDialog ()

@property (nonatomic, strong) NSTextField *widthField;
@property (nonatomic, strong) NSTextField *heightField;
@property (nonatomic, strong) NSButton *aspectCheckbox;
@property (nonatomic, strong) NSTextField *originalLabel;
@property (nonatomic, assign, readwrite) NSInteger originalWidth;
@property (nonatomic, assign, readwrite) NSInteger originalHeight;
@property (nonatomic, assign) CGFloat aspectRatio;

@end

@implementation XLResizeImageDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Resize Image";
        self.minWidth = 300;
        self.minHeight = 180;
        _originalWidth = 100;
        _originalHeight = 100;
        _newWidth = 100;
        _newHeight = 100;
        _maintainAspectRatio = YES;
        _aspectRatio = 1.0;
    }
    return self;
}

- (void)setOriginalWidth:(NSInteger)width height:(NSInteger)height {
    _originalWidth = width;
    _originalHeight = height;
    _newWidth = width;
    _newHeight = height;
    _aspectRatio = (CGFloat)width / (CGFloat)height;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Original size label
    _originalLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Original Size: %ld x %ld", (long)_originalWidth, (long)_originalHeight]];
    _originalLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:_originalLabel];

    // Width
    _widthField = [XLBaseSheetController createNumericField];
    _widthField.integerValue = _newWidth;
    [_widthField setTarget:self];
    [_widthField setAction:@selector(widthChanged:)];
    [_widthField.widthAnchor constraintEqualToConstant:80].active = YES;

    NSStackView *widthRow = [XLBaseSheetController formRowWithLabel:@"Width:" control:_widthField labelWidth:80];
    [stack addArrangedSubview:widthRow];

    // Height
    _heightField = [XLBaseSheetController createNumericField];
    _heightField.integerValue = _newHeight;
    [_heightField setTarget:self];
    [_heightField setAction:@selector(heightChanged:)];
    [_heightField.widthAnchor constraintEqualToConstant:80].active = YES;

    NSStackView *heightRow = [XLBaseSheetController formRowWithLabel:@"Height:" control:_heightField labelWidth:80];
    [stack addArrangedSubview:heightRow];

    // Aspect ratio checkbox
    _aspectCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Maintain aspect ratio"];
    _aspectCheckbox.state = _maintainAspectRatio ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_aspectCheckbox];

    return stack;
}

- (void)widthChanged:(id)sender {
    if (_aspectCheckbox.state == NSControlStateValueOn && _aspectRatio > 0) {
        _heightField.integerValue = (NSInteger)(_widthField.integerValue / _aspectRatio);
    }
}

- (void)heightChanged:(id)sender {
    if (_aspectCheckbox.state == NSControlStateValueOn && _aspectRatio > 0) {
        _widthField.integerValue = (NSInteger)(_heightField.integerValue * _aspectRatio);
    }
}

- (NSString *)validate {
    if (_widthField.integerValue < 1 || _widthField.integerValue > 10000) {
        return @"Width must be between 1 and 10000.";
    }
    if (_heightField.integerValue < 1 || _heightField.integerValue > 10000) {
        return @"Height must be between 1 and 10000.";
    }
    return nil;
}

- (void)okClicked:(id)sender {
    _newWidth = _widthField.integerValue;
    _newHeight = _heightField.integerValue;
    _maintainAspectRatio = (_aspectCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end

#pragma mark - XLBufferSizeDialog

@interface XLBufferSizeDialog ()

@property (nonatomic, strong) NSTextField *widthField;
@property (nonatomic, strong) NSTextField *heightField;

@end

@implementation XLBufferSizeDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Buffer Size";
        self.minWidth = 280;
        self.minHeight = 140;
        _bufferWidth = 100;
        _bufferHeight = 100;
        _maxSize = 10000;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Width
    _widthField = [XLBaseSheetController createNumericField];
    _widthField.integerValue = _bufferWidth;
    [_widthField.widthAnchor constraintEqualToConstant:80].active = YES;

    NSStackView *widthRow = [XLBaseSheetController formRowWithLabel:@"Width:" control:_widthField labelWidth:60];
    [stack addArrangedSubview:widthRow];

    // Height
    _heightField = [XLBaseSheetController createNumericField];
    _heightField.integerValue = _bufferHeight;
    [_heightField.widthAnchor constraintEqualToConstant:80].active = YES;

    NSStackView *heightRow = [XLBaseSheetController formRowWithLabel:@"Height:" control:_heightField labelWidth:60];
    [stack addArrangedSubview:heightRow];

    return stack;
}

- (NSString *)validate {
    if (_widthField.integerValue < 1 || _widthField.integerValue > _maxSize) {
        return [NSString stringWithFormat:@"Width must be between 1 and %ld.", (long)_maxSize];
    }
    if (_heightField.integerValue < 1 || _heightField.integerValue > _maxSize) {
        return [NSString stringWithFormat:@"Height must be between 1 and %ld.", (long)_maxSize];
    }
    return nil;
}

- (void)okClicked:(id)sender {
    _bufferWidth = _widthField.integerValue;
    _bufferHeight = _heightField.integerValue;
    [super okClicked:sender];
}

@end

#pragma mark - XLLayerSelectDialog

@interface XLLayerSelectDialog () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSTableView *layerTable;

@end

@implementation XLLayerSelectDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Select Layers";
        self.minWidth = 250;
        self.minHeight = 250;
        _layerCount = 5;
        _selectedLayers = [NSIndexSet indexSet];
        _allowsMultipleSelection = YES;
        _promptText = @"Select layer(s):";
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Prompt
    NSTextField *prompt = [NSTextField labelWithString:_promptText];
    [stack addArrangedSubview:prompt];

    // Table
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    [scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;

    _layerTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _layerTable.dataSource = self;
    _layerTable.delegate = self;
    _layerTable.allowsMultipleSelection = _allowsMultipleSelection;
    _layerTable.rowHeight = 22;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"layer"];
    column.title = @"Layer";
    column.width = 180;
    [_layerTable addTableColumn:column];

    scrollView.documentView = _layerTable;

    [stack addArrangedSubview:scrollView];
    [scrollView.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [scrollView.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    return stack;
}

- (void)sheetDidLoad {
    [_layerTable selectRowIndexes:_selectedLayers byExtendingSelection:NO];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _layerCount;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTextField *cell = [tableView makeViewWithIdentifier:@"cell" owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = @"cell";
    }
    cell.stringValue = [NSString stringWithFormat:@"Layer %ld", (long)(row + 1)];
    return cell;
}

- (NSString *)validate {
    if (_layerTable.selectedRowIndexes.count == 0) {
        return @"Please select at least one layer.";
    }
    return nil;
}

- (void)okClicked:(id)sender {
    _selectedLayers = [_layerTable.selectedRowIndexes copy];
    [super okClicked:sender];
}

@end

#pragma mark - XLRenameDialog

@interface XLRenameDialog ()

@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, copy, readwrite) NSString *enteredName;

@end

@implementation XLRenameDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Rename";
        self.minWidth = 350;
        self.minHeight = 120;
        _currentName = @"";
        _promptText = @"Name:";
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    _nameField = [XLBaseSheetController createTextField];
    _nameField.stringValue = _currentName;
    [_nameField.widthAnchor constraintGreaterThanOrEqualToConstant:250].active = YES;

    NSStackView *row = [XLBaseSheetController formRowWithLabel:_promptText control:_nameField labelWidth:80];
    [stack addArrangedSubview:row];

    return stack;
}

- (void)sheetDidLoad {
    [self.sheet makeFirstResponder:_nameField];
    _nameField.currentEditor.selectedRange = NSMakeRange(0, _nameField.stringValue.length);
}

- (NSString *)validate {
    NSString *name = _nameField.stringValue;

    if (name.length == 0) {
        return @"Name cannot be empty.";
    }

    // Check for disallowed characters
    if (_disallowedCharacters) {
        NSRange range = [name rangeOfCharacterFromSet:_disallowedCharacters];
        if (range.location != NSNotFound) {
            return @"Name contains invalid characters.";
        }
    }

    // Check for duplicate names
    if (_disallowedNames) {
        for (NSString *disallowed in _disallowedNames) {
            if ([name caseInsensitiveCompare:disallowed] == NSOrderedSame) {
                return @"This name is already in use.";
            }
        }
    }

    return nil;
}

- (void)okClicked:(id)sender {
    _enteredName = _nameField.stringValue;
    [super okClicked:sender];
}

@end
