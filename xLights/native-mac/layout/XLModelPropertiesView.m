/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLModelPropertiesView.h"
#import "../XLEngineBridge.h"

#pragma mark - Section Header View

/// Clickable disclosure section header with triangle and bold title.
@interface XLPropertySectionHeader : NSView

@property (nonatomic, strong) NSButton *disclosureButton;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, assign) BOOL expanded;

- (instancetype)initWithTitle:(NSString *)title;
- (void)setContentView:(NSView *)contentView;

@end

@implementation XLPropertySectionHeader

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _expanded = YES;

        _disclosureButton = [NSButton buttonWithTitle:@""
                                               target:self
                                               action:@selector(toggleDisclosure:)];
        _disclosureButton.translatesAutoresizingMaskIntoConstraints = NO;
        _disclosureButton.bezelStyle = NSBezelStyleDisclosure;
        _disclosureButton.state = NSControlStateValueOn;
        [self addSubview:_disclosureButton];

        _titleLabel = [NSTextField labelWithString:title];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [NSFont boldSystemFontOfSize:11];
        _titleLabel.textColor = [NSColor secondaryLabelColor];
        [self addSubview:_titleLabel];

        NSClickGestureRecognizer *click = [[NSClickGestureRecognizer alloc]
                                            initWithTarget:self
                                            action:@selector(headerClicked:)];
        [self addGestureRecognizer:click];

        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:24],
            [_disclosureButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
            [_disclosureButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_disclosureButton.trailingAnchor constant:2],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)setContentView:(NSView *)contentView {
    _contentView = contentView;
}

- (void)toggleDisclosure:(id)sender {
    _expanded = !_expanded;
    _disclosureButton.state = _expanded ? NSControlStateValueOn : NSControlStateValueOff;
    _contentView.hidden = !_expanded;
}

- (void)headerClicked:(NSClickGestureRecognizer *)recognizer {
    [self toggleDisclosure:nil];
}

@end

#pragma mark - Property Row Builder

/// Helper that builds label + control rows for the property grid.
@interface XLPropertyRowBuilder : NSObject

+ (NSView *)rowWithLabel:(NSString *)label control:(NSView *)control;
+ (NSTextField *)editableTextField;
+ (NSTextField *)readOnlyTextField;
+ (NSTextField *)numericTextField;
+ (NSSlider *)sliderWithMin:(double)min max:(double)max value:(double)value;
+ (NSPopUpButton *)popUpWithItems:(NSArray<NSString *> *)items selectedTitle:(NSString *)selected;
+ (NSButton *)checkbox;

@end

@implementation XLPropertyRowBuilder

+ (NSView *)rowWithLabel:(NSString *)label control:(NSView *)control {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *lbl = [NSTextField labelWithString:label];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.font = [NSFont systemFontOfSize:11];
    lbl.textColor = [NSColor tertiaryLabelColor];
    lbl.alignment = NSTextAlignmentRight;
    lbl.lineBreakMode = NSLineBreakByTruncatingTail;
    [lbl setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addSubview:lbl];

    control.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:control];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:22],
        [lbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:8],
        [lbl.widthAnchor constraintEqualToConstant:80],
        [lbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [control.leadingAnchor constraintEqualToAnchor:lbl.trailingAnchor constant:6],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    return row;
}

+ (NSTextField *)editableTextField {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.bordered = YES;
    field.bezeled = YES;
    field.bezelStyle = NSTextFieldRoundedBezel;
    field.editable = YES;
    field.selectable = YES;
    field.drawsBackground = YES;
    field.font = [NSFont systemFontOfSize:11];
    field.controlSize = NSControlSizeSmall;
    [field.heightAnchor constraintEqualToConstant:20].active = YES;
    return field;
}

+ (NSTextField *)readOnlyTextField {
    NSTextField *field = [self editableTextField];
    field.editable = NO;
    field.selectable = YES;
    field.textColor = [NSColor secondaryLabelColor];
    return field;
}

+ (NSTextField *)numericTextField {
    NSTextField *field = [self editableTextField];
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.allowsFloats = YES;
    field.formatter = formatter;
    return field;
}

+ (NSSlider *)sliderWithMin:(double)min max:(double)max value:(double)value {
    NSSlider *slider = [NSSlider sliderWithValue:value minValue:min maxValue:max
                                          target:nil action:nil];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.controlSize = NSControlSizeSmall;
    [slider.heightAnchor constraintEqualToConstant:20].active = YES;
    return slider;
}

+ (NSPopUpButton *)popUpWithItems:(NSArray<NSString *> *)items selectedTitle:(NSString *)selected {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.translatesAutoresizingMaskIntoConstraints = NO;
    popup.controlSize = NSControlSizeSmall;
    popup.font = [NSFont systemFontOfSize:11];
    [popup addItemsWithTitles:items];
    if (selected) {
        [popup selectItemWithTitle:selected];
    }
    [popup.heightAnchor constraintEqualToConstant:20].active = YES;
    return popup;
}

+ (NSButton *)checkbox {
    NSButton *btn = [NSButton checkboxWithTitle:@"" target:nil action:nil];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.controlSize = NSControlSizeSmall;
    return btn;
}

@end

#pragma mark - Three-Field Row

/// A row containing three labeled numeric fields (e.g., X / Y / Z).
@interface XLThreeFieldRow : NSView

@property (nonatomic, strong) NSTextField *field1;
@property (nonatomic, strong) NSTextField *field2;
@property (nonatomic, strong) NSTextField *field3;

- (instancetype)initWithLabels:(NSString *)l1 :(NSString *)l2 :(NSString *)l3;

@end

@implementation XLThreeFieldRow

- (instancetype)initWithLabels:(NSString *)l1 :(NSString *)l2 :(NSString *)l3 {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self.heightAnchor constraintEqualToConstant:22].active = YES;

        _field1 = [XLPropertyRowBuilder numericTextField];
        _field2 = [XLPropertyRowBuilder numericTextField];
        _field3 = [XLPropertyRowBuilder numericTextField];

        NSTextField *lbl1 = [NSTextField labelWithString:l1];
        NSTextField *lbl2 = [NSTextField labelWithString:l2];
        NSTextField *lbl3 = [NSTextField labelWithString:l3];

        for (NSTextField *lbl in @[lbl1, lbl2, lbl3]) {
            lbl.translatesAutoresizingMaskIntoConstraints = NO;
            lbl.font = [NSFont systemFontOfSize:9];
            lbl.textColor = [NSColor tertiaryLabelColor];
            [lbl setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        }

        [self addSubview:lbl1];
        [self addSubview:_field1];
        [self addSubview:lbl2];
        [self addSubview:_field2];
        [self addSubview:lbl3];
        [self addSubview:_field3];

        [NSLayoutConstraint activateConstraints:@[
            [lbl1.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [lbl1.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_field1.leadingAnchor constraintEqualToAnchor:lbl1.trailingAnchor constant:2],
            [_field1.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [lbl2.leadingAnchor constraintEqualToAnchor:_field1.trailingAnchor constant:6],
            [lbl2.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_field2.leadingAnchor constraintEqualToAnchor:lbl2.trailingAnchor constant:2],
            [_field2.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [lbl3.leadingAnchor constraintEqualToAnchor:_field2.trailingAnchor constant:6],
            [lbl3.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_field3.leadingAnchor constraintEqualToAnchor:lbl3.trailingAnchor constant:2],
            [_field3.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_field3.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

            [_field1.widthAnchor constraintEqualToAnchor:_field2.widthAnchor],
            [_field2.widthAnchor constraintEqualToAnchor:_field3.widthAnchor],
        ]];
    }
    return self;
}

@end

#pragma mark - XLModelPropertiesView

static NSString * const kMixedPlaceholder = @"Mixed";

@interface XLModelPropertiesView () <NSTextFieldDelegate>

@property (nonatomic, strong) NSStackView *stackView;

// Currently displayed model(s)
@property (nonatomic, copy) NSArray<NSString *> *currentModelNames;
@property (nonatomic, copy) NSArray<NSDictionary *> *currentModelInfos;

// General section controls
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *typeField;
@property (nonatomic, strong) NSTextField *descriptionField;
@property (nonatomic, strong) NSPopUpButton *displayAsPopup;

// Position & Size controls
@property (nonatomic, strong) XLThreeFieldRow *positionRow;
@property (nonatomic, strong) XLThreeFieldRow *sizeRow;
@property (nonatomic, strong) NSSlider *rotXSlider;
@property (nonatomic, strong) NSSlider *rotYSlider;
@property (nonatomic, strong) NSSlider *rotZSlider;
@property (nonatomic, strong) NSSlider *scaleSlider;
@property (nonatomic, strong) NSButton *lockedCheckbox;

// Controller controls
@property (nonatomic, strong) NSPopUpButton *controllerPopup;
@property (nonatomic, strong) NSPopUpButton *portPopup;
@property (nonatomic, strong) NSPopUpButton *protocolPopup;
@property (nonatomic, strong) NSTextField *startChannelField;
@property (nonatomic, strong) NSTextField *endChannelField;
@property (nonatomic, strong) NSTextField *channelCountField;

// Appearance controls
@property (nonatomic, strong) NSPopUpButton *colorOrderPopup;
@property (nonatomic, strong) NSSlider *brightnessSlider;
@property (nonatomic, strong) NSSlider *gammaSlider;
@property (nonatomic, strong) NSTextField *nullPixelsField;
@property (nonatomic, strong) NSButton *reverseCheckbox;
@property (nonatomic, strong) NSTextField *groupCountField;
@property (nonatomic, strong) NSTextField *zigZagField;

@end

@implementation XLModelPropertiesView

#pragma mark - Initialization

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    _stackView = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    _stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stackView.alignment = NSLayoutAttributeLeading;
    _stackView.spacing = 0;
    _stackView.distribution = NSStackViewDistributionFill;
    [self addSubview:_stackView];

    [NSLayoutConstraint activateConstraints:@[
        [_stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_stackView.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor],
    ]];

    [self buildSections];
}

#pragma mark - Section Building

- (void)buildSections {
    [self buildGeneralSection];
    [self buildPositionSection];
    [self buildControllerSection];
    [self buildAppearanceSection];
}

- (void)addSection:(NSString *)title contentBuilder:(NSView *(^)(void))builder {
    XLPropertySectionHeader *header = [[XLPropertySectionHeader alloc] initWithTitle:title];

    NSView *content = builder();
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [header setContentView:content];

    [_stackView addArrangedSubview:header];
    [_stackView addArrangedSubview:content];

    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:_stackView.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:_stackView.trailingAnchor],
        [content.leadingAnchor constraintEqualToAnchor:_stackView.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:_stackView.trailingAnchor],
    ]];

    // Separator line
    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.boxType = NSBoxSeparator;
    [_stackView addArrangedSubview:separator];
    [NSLayoutConstraint activateConstraints:@[
        [separator.leadingAnchor constraintEqualToAnchor:_stackView.leadingAnchor constant:8],
        [separator.trailingAnchor constraintEqualToAnchor:_stackView.trailingAnchor constant:-8],
    ]];
}

- (void)buildGeneralSection {
    [self addSection:@"General" contentBuilder:^NSView *{
        NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 4;

        // Name
        self.nameField = [XLPropertyRowBuilder editableTextField];
        self.nameField.identifier = @"name";
        self.nameField.delegate = self;
        NSView *nameRow = [XLPropertyRowBuilder rowWithLabel:@"Name" control:self.nameField];
        [stack addArrangedSubview:nameRow];
        [nameRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [nameRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Type (read-only)
        self.typeField = [XLPropertyRowBuilder readOnlyTextField];
        NSView *typeRow = [XLPropertyRowBuilder rowWithLabel:@"Type" control:self.typeField];
        [stack addArrangedSubview:typeRow];
        [typeRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [typeRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Description
        self.descriptionField = [XLPropertyRowBuilder editableTextField];
        self.descriptionField.identifier = @"description";
        self.descriptionField.delegate = self;
        self.descriptionField.placeholderString = @"Optional description";
        NSView *descRow = [XLPropertyRowBuilder rowWithLabel:@"Description" control:self.descriptionField];
        [stack addArrangedSubview:descRow];
        [descRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [descRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Display As
        self.displayAsPopup = [XLPropertyRowBuilder popUpWithItems:@[
            @"Default", @"Wireframe", @"Solid", @"Pointed"
        ] selectedTitle:@"Default"];
        self.displayAsPopup.target = self;
        self.displayAsPopup.action = @selector(popupChanged:);
        self.displayAsPopup.identifier = @"displayAs";
        NSView *displayRow = [XLPropertyRowBuilder rowWithLabel:@"Display As" control:self.displayAsPopup];
        [stack addArrangedSubview:displayRow];
        [displayRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [displayRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Bottom padding
        NSView *pad = [[NSView alloc] initWithFrame:NSZeroRect];
        pad.translatesAutoresizingMaskIntoConstraints = NO;
        [pad.heightAnchor constraintEqualToConstant:8].active = YES;
        [stack addArrangedSubview:pad];

        return stack;
    }];
}

- (void)buildPositionSection {
    [self addSection:@"Position & Size" contentBuilder:^NSView *{
        NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 4;

        // Position X/Y/Z
        self.positionRow = [[XLThreeFieldRow alloc] initWithLabels:@"X" :@"Y" :@"Z"];
        self.positionRow.field1.identifier = @"x";
        self.positionRow.field2.identifier = @"y";
        self.positionRow.field3.identifier = @"z";
        self.positionRow.field1.delegate = self;
        self.positionRow.field2.delegate = self;
        self.positionRow.field3.delegate = self;
        NSView *posRow = [XLPropertyRowBuilder rowWithLabel:@"Position" control:self.positionRow];
        [stack addArrangedSubview:posRow];
        [posRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [posRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Size W/H/D
        self.sizeRow = [[XLThreeFieldRow alloc] initWithLabels:@"W" :@"H" :@"D"];
        self.sizeRow.field1.identifier = @"width";
        self.sizeRow.field2.identifier = @"height";
        self.sizeRow.field3.identifier = @"depth";
        self.sizeRow.field1.delegate = self;
        self.sizeRow.field2.delegate = self;
        self.sizeRow.field3.delegate = self;
        NSView *szRow = [XLPropertyRowBuilder rowWithLabel:@"Size" control:self.sizeRow];
        [stack addArrangedSubview:szRow];
        [szRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [szRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Rotation X
        self.rotXSlider = [XLPropertyRowBuilder sliderWithMin:-180 max:180 value:0];
        self.rotXSlider.target = self;
        self.rotXSlider.action = @selector(sliderChanged:);
        self.rotXSlider.identifier = @"rotationX";
        NSView *rxRow = [XLPropertyRowBuilder rowWithLabel:@"Rotation X" control:self.rotXSlider];
        [stack addArrangedSubview:rxRow];
        [rxRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [rxRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Rotation Y
        self.rotYSlider = [XLPropertyRowBuilder sliderWithMin:-180 max:180 value:0];
        self.rotYSlider.target = self;
        self.rotYSlider.action = @selector(sliderChanged:);
        self.rotYSlider.identifier = @"rotationY";
        NSView *ryRow = [XLPropertyRowBuilder rowWithLabel:@"Rotation Y" control:self.rotYSlider];
        [stack addArrangedSubview:ryRow];
        [ryRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [ryRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Rotation Z
        self.rotZSlider = [XLPropertyRowBuilder sliderWithMin:-180 max:180 value:0];
        self.rotZSlider.target = self;
        self.rotZSlider.action = @selector(sliderChanged:);
        self.rotZSlider.identifier = @"rotationZ";
        NSView *rzRow = [XLPropertyRowBuilder rowWithLabel:@"Rotation Z" control:self.rotZSlider];
        [stack addArrangedSubview:rzRow];
        [rzRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [rzRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Scale
        self.scaleSlider = [XLPropertyRowBuilder sliderWithMin:0.1 max:10.0 value:1.0];
        self.scaleSlider.target = self;
        self.scaleSlider.action = @selector(sliderChanged:);
        self.scaleSlider.identifier = @"scale";
        NSView *scRow = [XLPropertyRowBuilder rowWithLabel:@"Scale" control:self.scaleSlider];
        [stack addArrangedSubview:scRow];
        [scRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [scRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Locked
        self.lockedCheckbox = [XLPropertyRowBuilder checkbox];
        self.lockedCheckbox.target = self;
        self.lockedCheckbox.action = @selector(checkboxChanged:);
        self.lockedCheckbox.identifier = @"locked";
        NSView *lockRow = [XLPropertyRowBuilder rowWithLabel:@"Locked" control:self.lockedCheckbox];
        [stack addArrangedSubview:lockRow];
        [lockRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [lockRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        NSView *pad = [[NSView alloc] initWithFrame:NSZeroRect];
        pad.translatesAutoresizingMaskIntoConstraints = NO;
        [pad.heightAnchor constraintEqualToConstant:8].active = YES;
        [stack addArrangedSubview:pad];

        return stack;
    }];
}

- (void)buildControllerSection {
    [self addSection:@"Controller" contentBuilder:^NSView *{
        NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 4;

        // Controller Name
        NSArray<NSString *> *controllerNames = @[@"No Controller"];
        if (self.engineBridge) {
            NSArray *names = [self.engineBridge getControllerNames];
            if (names.count > 0) {
                controllerNames = [@[@"No Controller"] arrayByAddingObjectsFromArray:names];
            }
        }
        self.controllerPopup = [XLPropertyRowBuilder popUpWithItems:controllerNames selectedTitle:@"No Controller"];
        self.controllerPopup.target = self;
        self.controllerPopup.action = @selector(popupChanged:);
        self.controllerPopup.identifier = @"controllerName";
        NSView *ctrlRow = [XLPropertyRowBuilder rowWithLabel:@"Controller" control:self.controllerPopup];
        [stack addArrangedSubview:ctrlRow];
        [ctrlRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [ctrlRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Port
        NSMutableArray<NSString *> *portNumbers = [[NSMutableArray alloc] init];
        for (int i = 1; i <= 48; i++) {
            [portNumbers addObject:[NSString stringWithFormat:@"%d", i]];
        }
        self.portPopup = [XLPropertyRowBuilder popUpWithItems:portNumbers selectedTitle:@"1"];
        self.portPopup.target = self;
        self.portPopup.action = @selector(popupChanged:);
        self.portPopup.identifier = @"port";
        NSView *portRow = [XLPropertyRowBuilder rowWithLabel:@"Port" control:self.portPopup];
        [stack addArrangedSubview:portRow];
        [portRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [portRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Protocol
        self.protocolPopup = [XLPropertyRowBuilder popUpWithItems:@[
            @"ws2811", @"DMX", @"LPD8806", @"WS2801", @"TM1809",
            @"TM1814", @"SM16703", @"UCS1903", @"UCS2903", @"GS8208",
        ] selectedTitle:@"ws2811"];
        self.protocolPopup.target = self;
        self.protocolPopup.action = @selector(popupChanged:);
        self.protocolPopup.identifier = @"protocol";
        NSView *protoRow = [XLPropertyRowBuilder rowWithLabel:@"Protocol" control:self.protocolPopup];
        [stack addArrangedSubview:protoRow];
        [protoRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [protoRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Start Channel
        self.startChannelField = [XLPropertyRowBuilder numericTextField];
        self.startChannelField.identifier = @"startChannel";
        self.startChannelField.delegate = self;
        NSView *startRow = [XLPropertyRowBuilder rowWithLabel:@"Start Channel" control:self.startChannelField];
        [stack addArrangedSubview:startRow];
        [startRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [startRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // End Channel (read-only)
        self.endChannelField = [XLPropertyRowBuilder readOnlyTextField];
        NSView *endRow = [XLPropertyRowBuilder rowWithLabel:@"End Channel" control:self.endChannelField];
        [stack addArrangedSubview:endRow];
        [endRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [endRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Channel Count (read-only)
        self.channelCountField = [XLPropertyRowBuilder readOnlyTextField];
        NSView *countRow = [XLPropertyRowBuilder rowWithLabel:@"Channels" control:self.channelCountField];
        [stack addArrangedSubview:countRow];
        [countRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [countRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        NSView *pad = [[NSView alloc] initWithFrame:NSZeroRect];
        pad.translatesAutoresizingMaskIntoConstraints = NO;
        [pad.heightAnchor constraintEqualToConstant:8].active = YES;
        [stack addArrangedSubview:pad];

        return stack;
    }];
}

- (void)buildAppearanceSection {
    [self addSection:@"Appearance" contentBuilder:^NSView *{
        NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 4;

        // Color Order
        self.colorOrderPopup = [XLPropertyRowBuilder popUpWithItems:@[
            @"RGB", @"RBG", @"GRB", @"GBR", @"BRG", @"BGR"
        ] selectedTitle:@"RGB"];
        self.colorOrderPopup.target = self;
        self.colorOrderPopup.action = @selector(popupChanged:);
        self.colorOrderPopup.identifier = @"colorOrder";
        NSView *coRow = [XLPropertyRowBuilder rowWithLabel:@"Color Order" control:self.colorOrderPopup];
        [stack addArrangedSubview:coRow];
        [coRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [coRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Brightness
        self.brightnessSlider = [XLPropertyRowBuilder sliderWithMin:0 max:100 value:100];
        self.brightnessSlider.target = self;
        self.brightnessSlider.action = @selector(sliderChanged:);
        self.brightnessSlider.identifier = @"brightness";
        self.brightnessSlider.numberOfTickMarks = 0;
        NSView *brightRow = [XLPropertyRowBuilder rowWithLabel:@"Brightness" control:self.brightnessSlider];
        [stack addArrangedSubview:brightRow];
        [brightRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [brightRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Gamma
        self.gammaSlider = [XLPropertyRowBuilder sliderWithMin:0.1 max:5.0 value:1.0];
        self.gammaSlider.target = self;
        self.gammaSlider.action = @selector(sliderChanged:);
        self.gammaSlider.identifier = @"gamma";
        NSView *gammaRow = [XLPropertyRowBuilder rowWithLabel:@"Gamma" control:self.gammaSlider];
        [stack addArrangedSubview:gammaRow];
        [gammaRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [gammaRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Null Pixels
        self.nullPixelsField = [XLPropertyRowBuilder numericTextField];
        self.nullPixelsField.identifier = @"nullPixels";
        self.nullPixelsField.delegate = self;
        NSNumberFormatter *npFmt = [[NSNumberFormatter alloc] init];
        npFmt.numberStyle = NSNumberFormatterNoStyle;
        npFmt.minimum = @0;
        npFmt.maximum = @50;
        self.nullPixelsField.formatter = npFmt;
        NSView *npRow = [XLPropertyRowBuilder rowWithLabel:@"Null Pixels" control:self.nullPixelsField];
        [stack addArrangedSubview:npRow];
        [npRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [npRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Reverse
        self.reverseCheckbox = [XLPropertyRowBuilder checkbox];
        self.reverseCheckbox.target = self;
        self.reverseCheckbox.action = @selector(checkboxChanged:);
        self.reverseCheckbox.identifier = @"reverse";
        NSView *revRow = [XLPropertyRowBuilder rowWithLabel:@"Reverse" control:self.reverseCheckbox];
        [stack addArrangedSubview:revRow];
        [revRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [revRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Group Count
        self.groupCountField = [XLPropertyRowBuilder numericTextField];
        self.groupCountField.identifier = @"groupCount";
        self.groupCountField.delegate = self;
        NSView *gcRow = [XLPropertyRowBuilder rowWithLabel:@"Group Count" control:self.groupCountField];
        [stack addArrangedSubview:gcRow];
        [gcRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [gcRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        // Zig Zag
        self.zigZagField = [XLPropertyRowBuilder numericTextField];
        self.zigZagField.identifier = @"zigZag";
        self.zigZagField.delegate = self;
        NSView *zzRow = [XLPropertyRowBuilder rowWithLabel:@"Zig Zag" control:self.zigZagField];
        [stack addArrangedSubview:zzRow];
        [zzRow.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
        [zzRow.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

        NSView *pad = [[NSView alloc] initWithFrame:NSZeroRect];
        pad.translatesAutoresizingMaskIntoConstraints = NO;
        [pad.heightAnchor constraintEqualToConstant:8].active = YES;
        [stack addArrangedSubview:pad];

        return stack;
    }];
}

#pragma mark - Public Interface

- (void)showPropertiesForModel:(NSString *)modelName info:(NSDictionary *)modelInfo {
    _currentModelNames = @[modelName];
    _currentModelInfos = @[modelInfo];
    [self populateFromInfo:modelInfo isMixed:NO];
}

- (void)showPropertiesForModels:(NSArray<NSString *> *)modelNames infos:(NSArray<NSDictionary *> *)modelInfos {
    if (modelNames.count == 0) {
        [self clearProperties];
        return;
    }
    if (modelNames.count == 1) {
        [self showPropertiesForModel:modelNames.firstObject info:modelInfos.firstObject];
        return;
    }

    _currentModelNames = [modelNames copy];
    _currentModelInfos = [modelInfos copy];

    NSDictionary *merged = [self mergedInfoFromInfos:modelInfos];
    [self populateFromInfo:merged isMixed:YES];
}

- (void)clearProperties {
    _currentModelNames = nil;
    _currentModelInfos = nil;

    // Reset all controls to empty/default state
    _nameField.stringValue = @"";
    _typeField.stringValue = @"";
    _descriptionField.stringValue = @"";
    [_displayAsPopup selectItemAtIndex:0];

    _positionRow.field1.stringValue = @"";
    _positionRow.field2.stringValue = @"";
    _positionRow.field3.stringValue = @"";
    _sizeRow.field1.stringValue = @"";
    _sizeRow.field2.stringValue = @"";
    _sizeRow.field3.stringValue = @"";
    _rotXSlider.doubleValue = 0;
    _rotYSlider.doubleValue = 0;
    _rotZSlider.doubleValue = 0;
    _scaleSlider.doubleValue = 1.0;
    _lockedCheckbox.state = NSControlStateValueOff;

    [_controllerPopup selectItemAtIndex:0];
    [_portPopup selectItemAtIndex:0];
    [_protocolPopup selectItemAtIndex:0];
    _startChannelField.stringValue = @"";
    _endChannelField.stringValue = @"";
    _channelCountField.stringValue = @"";

    [_colorOrderPopup selectItemAtIndex:0];
    _brightnessSlider.doubleValue = 100;
    _gammaSlider.doubleValue = 1.0;
    _nullPixelsField.stringValue = @"";
    _reverseCheckbox.state = NSControlStateValueOff;
    _groupCountField.stringValue = @"";
    _zigZagField.stringValue = @"";
}

#pragma mark - Population

- (void)populateFromInfo:(NSDictionary *)info isMixed:(BOOL)mixed {
    // General
    [self setTextField:_nameField value:info[@"name"] mixed:mixed];
    [self setTextField:_typeField value:info[@"type"] mixed:mixed];
    [self setTextField:_descriptionField value:info[@"description"] mixed:mixed];
    [self setPopUp:_displayAsPopup value:info[@"displayAs"] mixed:mixed];

    if (mixed) {
        _nameField.editable = NO;
    } else {
        _nameField.editable = YES;
    }

    // Position
    [self setTextField:_positionRow.field1 fromNumber:info[@"x"] mixed:mixed];
    [self setTextField:_positionRow.field2 fromNumber:info[@"y"] mixed:mixed];
    [self setTextField:_positionRow.field3 fromNumber:info[@"z"] mixed:mixed];

    // Size
    [self setTextField:_sizeRow.field1 fromNumber:info[@"width"] mixed:mixed];
    [self setTextField:_sizeRow.field2 fromNumber:info[@"height"] mixed:mixed];
    [self setTextField:_sizeRow.field3 fromNumber:info[@"depth"] mixed:mixed];

    // Rotation
    [self setSlider:_rotXSlider fromNumber:info[@"rotationX"] mixed:mixed];
    [self setSlider:_rotYSlider fromNumber:info[@"rotationY"] mixed:mixed];
    [self setSlider:_rotZSlider fromNumber:info[@"rotationZ"] mixed:mixed];

    // Scale
    [self setSlider:_scaleSlider fromNumber:info[@"scale"] mixed:mixed];

    // Locked
    [self setCheckbox:_lockedCheckbox fromNumber:info[@"locked"] mixed:mixed];

    // Controller
    [self setPopUp:_controllerPopup value:info[@"controllerName"] mixed:mixed];
    if (info[@"port"]) {
        NSString *portStr = [NSString stringWithFormat:@"%@", info[@"port"]];
        [self setPopUp:_portPopup value:portStr mixed:mixed];
    }
    [self setPopUp:_protocolPopup value:info[@"protocol"] mixed:mixed];
    [self setTextField:_startChannelField fromNumber:info[@"startChannel"] mixed:mixed];
    [self setTextField:_endChannelField fromNumber:info[@"endChannel"] mixed:mixed];
    [self setTextField:_channelCountField fromNumber:info[@"channelCount"] mixed:mixed];

    // Appearance
    [self setPopUp:_colorOrderPopup value:info[@"colorOrder"] mixed:mixed];
    [self setSlider:_brightnessSlider fromNumber:info[@"brightness"] mixed:mixed];
    [self setSlider:_gammaSlider fromNumber:info[@"gamma"] mixed:mixed];
    [self setTextField:_nullPixelsField fromNumber:info[@"nullPixels"] mixed:mixed];
    [self setCheckbox:_reverseCheckbox fromNumber:info[@"reverse"] mixed:mixed];
    [self setTextField:_groupCountField fromNumber:info[@"groupCount"] mixed:mixed];
    [self setTextField:_zigZagField fromNumber:info[@"zigZag"] mixed:mixed];
}

#pragma mark - Control Value Helpers

- (void)setTextField:(NSTextField *)field value:(id)value mixed:(BOOL)mixed {
    if (!value || value == [NSNull null]) {
        field.stringValue = @"";
        if (mixed) {
            field.placeholderString = kMixedPlaceholder;
        }
        return;
    }
    field.stringValue = [NSString stringWithFormat:@"%@", value];
    field.placeholderString = nil;
}

- (void)setTextField:(NSTextField *)field fromNumber:(NSNumber *)value mixed:(BOOL)mixed {
    if (!value || value == (id)[NSNull null]) {
        field.stringValue = @"";
        if (mixed) {
            field.placeholderString = kMixedPlaceholder;
        }
        return;
    }
    field.stringValue = [NSString stringWithFormat:@"%@", value];
    field.placeholderString = nil;
}

- (void)setSlider:(NSSlider *)slider fromNumber:(NSNumber *)value mixed:(BOOL)mixed {
    if (!value || value == (id)[NSNull null]) {
        slider.doubleValue = (slider.minValue + slider.maxValue) / 2.0;
        slider.enabled = !mixed;
        return;
    }
    slider.doubleValue = value.doubleValue;
    slider.enabled = YES;
}

- (void)setPopUp:(NSPopUpButton *)popup value:(id)value mixed:(BOOL)mixed {
    if (!value || value == [NSNull null]) {
        if (mixed) {
            // Insert a "Mixed" item at position 0 if not already there
            if (popup.numberOfItems == 0 || ![[popup itemAtIndex:0].title isEqualToString:kMixedPlaceholder]) {
                [popup insertItemWithTitle:kMixedPlaceholder atIndex:0];
                NSMenuItem *mixedItem = [popup itemAtIndex:0];
                NSMutableAttributedString *attr = [[NSMutableAttributedString alloc]
                    initWithString:kMixedPlaceholder
                    attributes:@{
                        NSFontAttributeName: [[NSFontManager sharedFontManager] convertFont:[NSFont systemFontOfSize:11] toHaveTrait:NSItalicFontMask],
                        NSForegroundColorAttributeName: [NSColor tertiaryLabelColor],
                    }];
                mixedItem.attributedTitle = attr;
            }
            [popup selectItemAtIndex:0];
        }
        return;
    }
    // Remove any previous "Mixed" placeholder item
    NSInteger mixedIdx = [popup indexOfItemWithTitle:kMixedPlaceholder];
    if (mixedIdx >= 0) {
        [popup removeItemAtIndex:mixedIdx];
    }
    [popup selectItemWithTitle:[NSString stringWithFormat:@"%@", value]];
}

- (void)setCheckbox:(NSButton *)checkbox fromNumber:(NSNumber *)value mixed:(BOOL)mixed {
    if (!value || value == (id)[NSNull null]) {
        checkbox.state = NSControlStateValueMixed;
        checkbox.allowsMixedState = YES;
        return;
    }
    checkbox.allowsMixedState = NO;
    checkbox.state = value.boolValue ? NSControlStateValueOn : NSControlStateValueOff;
}

#pragma mark - Multi-Model Merging

- (NSDictionary *)mergedInfoFromInfos:(NSArray<NSDictionary *> *)infos {
    if (infos.count == 0) return @{};

    NSMutableDictionary *merged = [infos.firstObject mutableCopy];

    for (NSUInteger i = 1; i < infos.count; i++) {
        NSDictionary *info = infos[i];
        for (NSString *key in [merged allKeys]) {
            id mergedVal = merged[key];
            id infoVal = info[key];

            if (!infoVal || ![mergedVal isEqual:infoVal]) {
                merged[key] = [NSNull null]; // mark as mixed
            }
        }
    }

    // Name is always "mixed" for multi-selection
    merged[@"name"] = [NSNull null];

    return [merged copy];
}

#pragma mark - Control Actions

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *field = notification.object;
    NSString *identifier = field.identifier;
    if (!identifier) return;

    id value = field.stringValue;

    // Convert numeric fields to NSNumber
    if ([self isNumericKey:identifier]) {
        value = @(field.doubleValue);
    }

    [self notifyPropertyChange:identifier value:value];
}

- (void)sliderChanged:(NSSlider *)sender {
    NSString *identifier = sender.identifier;
    if (!identifier) return;

    NSNumber *value = @(sender.doubleValue);
    [self notifyPropertyChange:identifier value:value];
}

- (void)popupChanged:(NSPopUpButton *)sender {
    NSString *identifier = sender.identifier;
    if (!identifier) return;

    NSString *value = sender.titleOfSelectedItem;

    // Skip the "Mixed" placeholder
    if ([value isEqualToString:kMixedPlaceholder]) return;

    // Convert port to number
    if ([identifier isEqualToString:@"port"]) {
        [self notifyPropertyChange:identifier value:@(value.integerValue)];
        return;
    }

    [self notifyPropertyChange:identifier value:value];
}

- (void)checkboxChanged:(NSButton *)sender {
    NSString *identifier = sender.identifier;
    if (!identifier) return;

    NSNumber *value = @(sender.state == NSControlStateValueOn);
    [self notifyPropertyChange:identifier value:value];
}

#pragma mark - Delegate Notification

- (void)notifyPropertyChange:(NSString *)key value:(id)value {
    if (!_currentModelNames || _currentModelNames.count == 0) return;

    if ([_delegate respondsToSelector:@selector(modelProperties:didChangeProperty:value:forModel:)]) {
        for (NSString *modelName in _currentModelNames) {
            [_delegate modelProperties:self didChangeProperty:key value:value forModel:modelName];
        }
    }
}

#pragma mark - Helpers

- (BOOL)isNumericKey:(NSString *)key {
    static NSSet *numericKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        numericKeys = [NSSet setWithArray:@[
            @"x", @"y", @"z",
            @"width", @"height", @"depth",
            @"startChannel",
            @"nullPixels", @"groupCount", @"zigZag",
        ]];
    });
    return [numericKeys containsObject:key];
}

@end
