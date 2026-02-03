/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLStartChannelDialog.h"
#import "../XLEngineBridge.h"

static const CGFloat kLabelWidth = 120.0;

@interface XLStartChannelDialog ()

@property (nonatomic, strong) NSTextField *channelField;
@property (nonatomic, strong) NSMatrix *modeMatrix;
@property (nonatomic, strong) NSPopUpButton *ipPopup;
@property (nonatomic, strong) NSPopUpButton *universePopup;
@property (nonatomic, strong) NSPopUpButton *modelPopup;
@property (nonatomic, strong) NSPopUpButton *controllerPopup;
@property (nonatomic, strong) NSButton *fromPreviewCheckbox;

@property (nonatomic, assign, readwrite) XLStartChannelMode mode;
@property (nonatomic, assign, readwrite) NSInteger channelOffset;
@property (nonatomic, copy, readwrite) NSString *selectedModel;
@property (nonatomic, copy, readwrite) NSString *selectedController;
@property (nonatomic, assign, readwrite) NSInteger selectedUniverse;
@property (nonatomic, copy, readwrite) NSString *selectedIP;

@end

@implementation XLStartChannelDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Start Channel";
        self.okButtonTitle = @"OK";
        self.minWidth = 450;
        self.minHeight = 350;
        _startChannel = @"1";
        _mode = XLStartChannelModeAbsolute;
        _channelOffset = 1;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Channel field
    _channelField = [XLBaseSheetController createNumericField];
    _channelField.stringValue = @"1";
    [_channelField setTarget:self];
    [_channelField setAction:@selector(channelChanged:)];
    [_channelField.widthAnchor constraintEqualToConstant:100].active = YES;

    NSStackView *channelRow = [XLBaseSheetController formRowWithLabel:@"Start Channel:"
                                                              control:_channelField
                                                           labelWidth:kLabelWidth];
    [stack addArrangedSubview:channelRow];

    // Mode selection group box
    NSBox *modeBox = [[NSBox alloc] initWithFrame:NSZeroRect];
    modeBox.title = @"Offset From";
    modeBox.titlePosition = NSAtTop;
    modeBox.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *modeStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    modeStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    modeStack.alignment = NSLayoutAttributeLeading;
    modeStack.spacing = 8;
    modeStack.translatesAutoresizingMaskIntoConstraints = NO;

    // Radio buttons using NSMatrix for mutual exclusion
    NSButtonCell *protoCell = [[NSButtonCell alloc] init];
    protoCell.buttonType = NSButtonTypeRadio;

    _modeMatrix = [[NSMatrix alloc] initWithFrame:NSZeroRect
                                             mode:NSRadioModeMatrix
                                        prototype:protoCell
                                     numberOfRows:5
                                  numberOfColumns:1];
    _modeMatrix.translatesAutoresizingMaskIntoConstraints = NO;
    _modeMatrix.cellSize = NSMakeSize(150, 24);
    _modeMatrix.autorecalculatesCellSize = YES;
    _modeMatrix.target = self;
    _modeMatrix.action = @selector(modeChanged:);

    NSArray<NSCell *> *cells = _modeMatrix.cells;
    [cells[0] setTitle:@"None (Absolute)"];
    [cells[1] setTitle:@"Universe Number"];
    [cells[2] setTitle:@"End of Model"];
    [cells[3] setTitle:@"Start of Model"];
    [cells[4] setTitle:@"Controller"];

    [modeStack addArrangedSubview:_modeMatrix];

    // Universe controls
    NSStackView *universeRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    universeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    universeRow.spacing = 8;

    _ipPopup = [XLBaseSheetController createPopUpButton];
    [_ipPopup addItemWithTitle:@"ANY"];
    [_ipPopup setTarget:self];
    [_ipPopup setAction:@selector(ipChanged:)];
    [_ipPopup.widthAnchor constraintEqualToConstant:120].active = YES;

    _universePopup = [XLBaseSheetController createPopUpButton];
    [_universePopup.widthAnchor constraintEqualToConstant:80].active = YES;

    NSTextField *ipLabel = [NSTextField labelWithString:@"IP:"];
    NSTextField *uniLabel = [NSTextField labelWithString:@"Universe:"];

    [universeRow addArrangedSubview:ipLabel];
    [universeRow addArrangedSubview:_ipPopup];
    [universeRow addArrangedSubview:uniLabel];
    [universeRow addArrangedSubview:_universePopup];
    [modeStack addArrangedSubview:universeRow];

    // Model controls
    NSStackView *modelRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    modelRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    modelRow.spacing = 8;

    _modelPopup = [XLBaseSheetController createPopUpButton];
    [_modelPopup.widthAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;

    _fromPreviewCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"From this preview only"];
    _fromPreviewCheckbox.state = NSControlStateValueOn;
    [_fromPreviewCheckbox setTarget:self];
    [_fromPreviewCheckbox setAction:@selector(previewFilterChanged:)];

    NSTextField *modelLabel = [NSTextField labelWithString:@"Model:"];
    [modelRow addArrangedSubview:modelLabel];
    [modelRow addArrangedSubview:_modelPopup];
    [modelRow addArrangedSubview:_fromPreviewCheckbox];
    [modeStack addArrangedSubview:modelRow];

    // Controller controls
    NSStackView *controllerRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    controllerRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    controllerRow.spacing = 8;

    _controllerPopup = [XLBaseSheetController createPopUpButton];
    [_controllerPopup.widthAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;

    NSTextField *ctrlLabel = [NSTextField labelWithString:@"Controller:"];
    [controllerRow addArrangedSubview:ctrlLabel];
    [controllerRow addArrangedSubview:_controllerPopup];
    [modeStack addArrangedSubview:controllerRow];

    modeBox.contentView = modeStack;
    [modeStack.leadingAnchor constraintEqualToAnchor:modeBox.contentView.leadingAnchor constant:10].active = YES;
    [modeStack.trailingAnchor constraintEqualToAnchor:modeBox.contentView.trailingAnchor constant:-10].active = YES;
    [modeStack.topAnchor constraintEqualToAnchor:modeBox.contentView.topAnchor constant:10].active = YES;
    [modeStack.bottomAnchor constraintEqualToAnchor:modeBox.contentView.bottomAnchor constant:-10].active = YES;

    [stack addArrangedSubview:modeBox];

    [modeBox.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [modeBox.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    return stack;
}

- (void)sheetDidLoad {
    [self populateControls];
    [self parseStartChannel:_startChannel];
    [self updateControlStates];
}

- (void)populateControls {
    // Populate IPs
    [_ipPopup removeAllItems];
    [_ipPopup addItemWithTitle:@"ANY"];

    NSArray<NSString *> *ips = [_engineBridge getOutputIPs];
    for (NSString *ip in ips) {
        if (![ip isEqualToString:@"MULTICAST"]) {
            [_ipPopup addItemWithTitle:ip];
        }
    }

    // Populate models
    [self updateModelList];

    // Populate controllers
    [_controllerPopup removeAllItems];
    NSArray<NSString *> *controllers = [_engineBridge getControllerNames];
    for (NSString *name in controllers) {
        [_controllerPopup addItemWithTitle:name];
    }

    // Update universes based on IP
    [self updateUniverseList];
}

- (void)updateModelList {
    [_modelPopup removeAllItems];

    NSArray<NSString *> *models = [_engineBridge getModelNames];
    BOOL filterByPreview = (_fromPreviewCheckbox.state == NSControlStateValueOn);

    for (NSString *name in models) {
        // Skip the model being edited
        if (_editingModelName && [name isEqualToString:_editingModelName]) {
            continue;
        }

        // Skip model groups
        NSString *displayAs = [_engineBridge getModelProperty:name key:@"DisplayAs"];
        if ([displayAs isEqualToString:@"ModelGroup"]) {
            continue;
        }

        if (filterByPreview && _currentPreview) {
            NSString *layoutGroup = [_engineBridge getModelProperty:name key:@"LayoutGroup"];
            if (![layoutGroup isEqualToString:@"All Previews"] &&
                ![layoutGroup isEqualToString:_currentPreview]) {
                continue;
            }
        }

        [_modelPopup addItemWithTitle:name];
    }
}

- (void)updateUniverseList {
    [_universePopup removeAllItems];

    NSString *selectedIP = _ipPopup.selectedItem.title;
    NSArray<NSNumber *> *universes;

    if ([selectedIP isEqualToString:@"ANY"]) {
        universes = [_engineBridge getAllUniverses];
    } else {
        universes = [_engineBridge getUniversesForIP:selectedIP];
    }

    NSArray<NSNumber *> *sorted = [universes sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *uni in sorted) {
        [_universePopup addItemWithTitle:[uni stringValue]];
    }
}

- (void)updateControlStates {
    BOOL isUniverse = (_mode == XLStartChannelModeUniverse);
    BOOL isModel = (_mode == XLStartChannelModeEndOfModel || _mode == XLStartChannelModeStartOfModel);
    BOOL isController = (_mode == XLStartChannelModeController);

    _ipPopup.enabled = isUniverse;
    _universePopup.enabled = isUniverse;
    _modelPopup.enabled = isModel;
    _fromPreviewCheckbox.enabled = isModel;
    _controllerPopup.enabled = isController;

    // Update matrix selection
    [_modeMatrix selectCellAtRow:(NSInteger)_mode column:0];

    [self updateOKButtonState];
}

#pragma mark - Actions

- (void)modeChanged:(id)sender {
    _mode = (XLStartChannelMode)_modeMatrix.selectedRow;

    // Reset channel to 1 when switching to model reference modes
    if (_mode == XLStartChannelModeEndOfModel || _mode == XLStartChannelModeStartOfModel) {
        _channelField.stringValue = @"1";
    }

    [self updateControlStates];
}

- (void)ipChanged:(id)sender {
    [self updateUniverseList];
}

- (void)channelChanged:(id)sender {
    [self updateOKButtonState];
}

- (void)previewFilterChanged:(id)sender {
    [self updateModelList];
}

#pragma mark - Parsing

- (void)parseStartChannel:(NSString *)startChannel {
    if (!startChannel || startChannel.length == 0) {
        _mode = XLStartChannelModeAbsolute;
        _channelOffset = 1;
        _channelField.stringValue = @"1";
        [self updateControlStates];
        return;
    }

    NSRange colonRange = [startChannel rangeOfString:@":"];

    if (colonRange.location == NSNotFound) {
        // Simple absolute channel
        _mode = XLStartChannelModeAbsolute;
        _channelOffset = [startChannel integerValue];
        _channelField.stringValue = startChannel;
    } else {
        NSString *prefix = [startChannel substringToIndex:colonRange.location];
        NSString *suffix = [startChannel substringFromIndex:colonRange.location + 1];

        // Find last colon for channel number
        NSRange lastColon = [startChannel rangeOfString:@":" options:NSBackwardsSearch];
        NSString *channelStr = [startChannel substringFromIndex:lastColon.location + 1];
        _channelOffset = [channelStr integerValue];
        _channelField.stringValue = channelStr;

        unichar firstChar = [prefix characterAtIndex:0];

        switch (firstChar) {
            case '!': {
                // Controller mode: !ControllerName:Channel
                _mode = XLStartChannelModeController;
                NSString *controllerName = [prefix substringFromIndex:1];
                [_controllerPopup selectItemWithTitle:controllerName];
                break;
            }
            case '@': {
                // Start of model: @ModelName:Channel
                _mode = XLStartChannelModeStartOfModel;
                NSString *modelName = [prefix substringFromIndex:1];
                [_modelPopup selectItemWithTitle:modelName];
                break;
            }
            case '>':
            case '<': {
                // End of model: >ModelName:Channel or <ModelName:Channel
                _mode = XLStartChannelModeEndOfModel;
                NSString *modelName = [prefix substringFromIndex:1];
                [_modelPopup selectItemWithTitle:modelName];
                break;
            }
            case '#': {
                // Universe mode: #IP:Universe:Channel or #Universe:Channel
                _mode = XLStartChannelModeUniverse;

                NSArray<NSString *> *parts = [[startChannel substringFromIndex:1] componentsSeparatedByString:@":"];
                if (parts.count == 3) {
                    // IP:Universe:Channel
                    [_ipPopup selectItemWithTitle:parts[0]];
                    [self updateUniverseList];
                    [_universePopup selectItemWithTitle:parts[1]];
                } else if (parts.count == 2) {
                    // Universe:Channel
                    [_ipPopup selectItemWithTitle:@"ANY"];
                    [self updateUniverseList];
                    [_universePopup selectItemWithTitle:parts[0]];
                }
                break;
            }
            default: {
                // Legacy model name (without prefix)
                _mode = XLStartChannelModeEndOfModel;
                [_modelPopup selectItemWithTitle:prefix];
                break;
            }
        }
    }

    [self updateControlStates];
}

- (NSString *)generateStartChannelString {
    NSInteger channel = [_channelField integerValue];

    switch (_mode) {
        case XLStartChannelModeAbsolute:
            return [NSString stringWithFormat:@"%ld", (long)channel];

        case XLStartChannelModeUniverse: {
            NSString *ip = _ipPopup.selectedItem.title;
            NSString *universe = _universePopup.selectedItem.title;
            if ([ip isEqualToString:@"ANY"]) {
                return [NSString stringWithFormat:@"#%@:%ld", universe, (long)channel];
            } else {
                return [NSString stringWithFormat:@"#%@:%@:%ld", ip, universe, (long)channel];
            }
        }

        case XLStartChannelModeEndOfModel: {
            NSString *model = _modelPopup.selectedItem.title;
            return [NSString stringWithFormat:@">%@:%ld", model, (long)channel];
        }

        case XLStartChannelModeStartOfModel: {
            NSString *model = _modelPopup.selectedItem.title;
            return [NSString stringWithFormat:@"@%@:%ld", model, (long)channel];
        }

        case XLStartChannelModeController: {
            NSString *controller = _controllerPopup.selectedItem.title;
            return [NSString stringWithFormat:@"!%@:%ld", controller, (long)channel];
        }
    }

    return [NSString stringWithFormat:@"%ld", (long)channel];
}

- (void)okClicked:(id)sender {
    _startChannel = [self generateStartChannelString];
    _channelOffset = [_channelField integerValue];
    _selectedModel = _modelPopup.selectedItem.title;
    _selectedController = _controllerPopup.selectedItem.title;
    _selectedIP = _ipPopup.selectedItem.title;
    _selectedUniverse = [_universePopup.selectedItem.title integerValue];

    [super okClicked:sender];
}

- (NSString *)validate {
    NSInteger channel = [_channelField integerValue];
    if (channel < 1) {
        return @"Channel must be at least 1.";
    }

    switch (_mode) {
        case XLStartChannelModeEndOfModel:
        case XLStartChannelModeStartOfModel:
            if (_modelPopup.selectedItem == nil) {
                return @"Please select a model.";
            }
            break;

        case XLStartChannelModeController:
            if (_controllerPopup.selectedItem == nil) {
                return @"Please select a controller.";
            }
            break;

        case XLStartChannelModeUniverse:
            if (_universePopup.selectedItem == nil) {
                return @"Please select a universe.";
            }
            break;

        default:
            break;
    }

    return nil;
}

@end
