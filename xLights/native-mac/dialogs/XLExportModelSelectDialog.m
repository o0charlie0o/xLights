/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLExportModelSelectDialog.h"
#import "../XLEngineBridge.h"

@interface XLExportModelSelectDialog ()

@property (nonatomic, strong) NSPopUpButton *modelPopup;
@property (nonatomic, copy, readwrite) NSString *selectedModel;

@end

@implementation XLExportModelSelectDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Select Model";
        self.minWidth = 350;
        self.minHeight = 130;
        _selectionLabel = @"Model to Export";
        _includeGroups = NO;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = 12;

    NSTextField *label = [NSTextField labelWithString:_selectionLabel];
    [stack addArrangedSubview:label];

    _modelPopup = [XLBaseSheetController createPopUpButton];
    [_modelPopup.widthAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;
    [stack addArrangedSubview:_modelPopup];

    return stack;
}

- (void)sheetDidLoad {
    [self populateModels];
}

- (void)populateModels {
    [_modelPopup removeAllItems];

    NSArray<NSString *> *models = [_engineBridge getModelNames];
    for (NSString *name in models) {
        NSString *displayAs = [_engineBridge getModelProperty:name key:@"DisplayAs"];

        // Filter model groups unless explicitly included
        if ([displayAs isEqualToString:@"ModelGroup"] && !_includeGroups) {
            continue;
        }

        [_modelPopup addItemWithTitle:name];
    }
}

- (NSString *)validate {
    if (_modelPopup.selectedItem == nil) {
        return @"Please select a model.";
    }
    return nil;
}

- (void)okClicked:(id)sender {
    _selectedModel = _modelPopup.selectedItem.title;
    [super okClicked:sender];
}

@end
