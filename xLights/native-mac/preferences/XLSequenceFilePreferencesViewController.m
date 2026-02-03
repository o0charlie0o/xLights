//
//  XLSequenceFilePreferencesViewController.m
//  xLights
//

#import "XLSequenceFilePreferencesViewController.h"

@interface XLSequenceFilePreferencesViewController ()

@property (nonatomic, strong) NSButton *renderOnSaveCheckbox;
@property (nonatomic, strong) NSButton *lowDefinitionRenderCheckbox;
@property (nonatomic, strong) NSButton *fseqSaveCheckbox;
@property (nonatomic, strong) NSPopUpButton *modelBlendDefaultPopup;
@property (nonatomic, strong) NSPopUpButton *renderCachePopup;
@property (nonatomic, strong) NSPopUpButton *autoSaveIntervalPopup;
@property (nonatomic, strong) NSPopUpButton *fseqVersionPopup;
@property (nonatomic, strong) NSButton *renderCacheUseSh owFolderCheckbox;
@property (nonatomic, strong) NSPathControl *renderCachePathControl;
@property (nonatomic, strong) NSPopUpButton *maxRenderCacheSizePopup;
@property (nonatomic, strong) NSButton *fseqUseShowFolderCheckbox;
@property (nonatomic, strong) NSPathControl *fseqPathControl;
@property (nonatomic, strong) NSTableView *mediaDirectoriesTable;
@property (nonatomic, strong) NSPopUpButton *viewDefaultPopup;

@end

@implementation XLSequenceFilePreferencesViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 700)];

    NSStackView *stackView = [[NSStackView alloc] initWithFrame:self.view.bounds];
    stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    stackView.alignment = NSLayoutAttributeLeading;
    stackView.spacing = 16;
    stackView.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    stackView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:stackView];

    self.renderOnSaveCheckbox = [NSButton checkboxWithTitle:@"Render on Save" target:self action:@selector(settingChanged:)];
    [stackView addArrangedSubview:self.renderOnSaveCheckbox];

    self.lowDefinitionRenderCheckbox = [NSButton checkboxWithTitle:@"Low Definition Render" target:self action:@selector(settingChanged:)];
    [stackView addArrangedSubview:self.lowDefinitionRenderCheckbox];

    NSView *modelBlendRow = [self createLabeledControl:@"Default Model Blending for New Sequences:"
                                               control:({
        self.modelBlendDefaultPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [self.modelBlendDefaultPopup addItemsWithTitles:@[@"Enabled", @"Disabled"]];
        self.modelBlendDefaultPopup.target = self;
        self.modelBlendDefaultPopup.action = @selector(settingChanged:);
        self.modelBlendDefaultPopup;
    })];
    [stackView addArrangedSubview:modelBlendRow];

    NSView *renderCacheRow = [self createLabeledControl:@"Render Cache:"
                                                control:({
        self.renderCachePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [self.renderCachePopup addItemsWithTitles:@[@"Enabled", @"Locked Effects Only", @"Disabled"]];
        self.renderCachePopup.target = self;
        self.renderCachePopup.action = @selector(settingChanged:);
        self.renderCachePopup;
    })];
    [stackView addArrangedSubview:renderCacheRow];

    NSBox *renderCacheBox = [self createRenderCacheSection];
    [stackView addArrangedSubview:renderCacheBox];

    NSView *autoSaveRow = [self createLabeledControl:@"Auto Save Interval:"
                                             control:({
        self.autoSaveIntervalPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [self.autoSaveIntervalPopup addItemsWithTitles:@[@"Disabled", @"3 Minutes", @"5 Minutes", @"10 Minutes", @"15 Minutes", @"30 Minutes"]];
        self.autoSaveIntervalPopup.target = self;
        self.autoSaveIntervalPopup.action = @selector(settingChanged:);
        self.autoSaveIntervalPopup;
    })];
    [stackView addArrangedSubview:autoSaveRow];

    NSView *fseqVersionRow = [self createLabeledControl:@"FSEQ Version:"
                                                control:({
        self.fseqVersionPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [self.fseqVersionPopup addItemsWithTitles:@[@"V1", @"V2 ZSTD (Default)", @"V2 Uncompressed", @"V2 ZLIB", @"V2 ZSTD/sparse"]];
        self.fseqVersionPopup.target = self;
        self.fseqVersionPopup.action = @selector(settingChanged:);
        self.fseqVersionPopup;
    })];
    [stackView addArrangedSubview:fseqVersionRow];

    self.fseqSaveCheckbox = [NSButton checkboxWithTitle:@"Save FSEQ File On Save" target:self action:@selector(settingChanged:)];
    [stackView addArrangedSubview:self.fseqSaveCheckbox];

    NSBox *fseqBox = [self createFSEQDirectorySection];
    [stackView addArrangedSubview:fseqBox];

    NSView *viewDefaultRow = [self createLabeledControl:@"Default View:"
                                                control:({
        self.viewDefaultPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [self.viewDefaultPopup addItemsWithTitles:@[@"Sequencer", @"Layout", @"Setup"]];
        self.viewDefaultPopup.target = self;
        self.viewDefaultPopup.action = @selector(settingChanged:);
        self.viewDefaultPopup;
    })];
    [stackView addArrangedSubview:viewDefaultRow];
}

- (NSView *)createLabeledControl:(NSString *)label control:(NSView *)control {
    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;

    NSTextField *labelField = [NSTextField labelWithString:label];
    [labelField setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addArrangedSubview:labelField];

    [control setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addArrangedSubview:control];

    return row;
}

- (NSBox *)createRenderCacheSection {
    NSBox *box = [[NSBox alloc] init];
    box.title = @"Render Cache Directory";
    box.boxType = NSBoxPrimary;

    NSStackView *content = [[NSStackView alloc] init];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.spacing = 8;
    content.edgeInsets = NSEdgeInsetsMake(8, 8, 8, 8);

    self.renderCacheUseShowFolderCheckbox = [NSButton checkboxWithTitle:@"Use Show Folder" target:self action:@selector(renderCacheLocationChanged:)];
    [content addArrangedSubview:self.renderCacheUseShowFolderCheckbox];

    self.renderCachePathControl = [[NSPathControl alloc] init];
    self.renderCachePathControl.pathStyle = NSPathStyleStandard;
    self.renderCachePathControl.target = self;
    self.renderCachePathControl.action = @selector(settingChanged:);
    [content addArrangedSubview:self.renderCachePathControl];

    NSView *maxSizeRow = [self createLabeledControl:@"Maximum Render Cache Size:"
                                            control:({
        self.maxRenderCacheSizePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [self.maxRenderCacheSizePopup addItemsWithTitles:@[@"Unlimited", @"100 MB", @"200 MB", @"500 MB", @"1 GB", @"3 GB", @"5 GB", @"10 GB", @"20 GB", @"50 GB", @"100 GB", @"200 GB"]];
        self.maxRenderCacheSizePopup.target = self;
        self.maxRenderCacheSizePopup.action = @selector(settingChanged:);
        self.maxRenderCacheSizePopup;
    })];
    [content addArrangedSubview:maxSizeRow];

    box.contentView = content;
    return box;
}

- (NSBox *)createFSEQDirectorySection {
    NSBox *box = [[NSBox alloc] init];
    box.title = @"FSEQ Directory";
    box.boxType = NSBoxPrimary;

    NSStackView *content = [[NSStackView alloc] init];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.spacing = 8;
    content.edgeInsets = NSEdgeInsetsMake(8, 8, 8, 8);

    self.fseqUseShowFolderCheckbox = [NSButton checkboxWithTitle:@"Use Show Folder" target:self action:@selector(fseqLocationChanged:)];
    [content addArrangedSubview:self.fseqUseShowFolderCheckbox];

    self.fseqPathControl = [[NSPathControl alloc] init];
    self.fseqPathControl.pathStyle = NSPathStyleStandard;
    self.fseqPathControl.target = self;
    self.fseqPathControl.action = @selector(settingChanged:);
    [content addArrangedSubview:self.fseqPathControl];

    box.contentView = content;
    return box;
}

- (void)renderCacheLocationChanged:(id)sender {
    self.renderCachePathControl.enabled = !self.renderCacheUseShowFolderCheckbox.state;
    [self settingChanged:sender];
}

- (void)fseqLocationChanged:(id)sender {
    self.fseqPathControl.enabled = !self.fseqUseShowFolderCheckbox.state;
    [self settingChanged:sender];
}

- (void)settingChanged:(id)sender {
    [self saveSettings];
}

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    self.renderOnSaveCheckbox.state = [defaults boolForKey:@"RenderOnSave"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.lowDefinitionRenderCheckbox.state = [defaults boolForKey:@"LowDefinitionRender"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.fseqSaveCheckbox.state = [defaults boolForKey:@"SaveFSEQOnSave"] ? NSControlStateValueOn : NSControlStateValueOff;

    [self.modelBlendDefaultPopup selectItemAtIndex:[defaults integerForKey:@"ModelBlendDefault"]];
    [self.renderCachePopup selectItemAtIndex:[defaults integerForKey:@"RenderCache"]];
    [self.autoSaveIntervalPopup selectItemAtIndex:[defaults integerForKey:@"AutoSaveInterval"]];
    [self.fseqVersionPopup selectItemAtIndex:[defaults integerForKey:@"FSEQVersion"]];
    [self.viewDefaultPopup selectItemAtIndex:[defaults integerForKey:@"DefaultView"]];
    [self.maxRenderCacheSizePopup selectItemAtIndex:[defaults integerForKey:@"MaxRenderCacheSize"]];

    self.renderCacheUseShowFolderCheckbox.state = [defaults boolForKey:@"RenderCacheUseShowFolder"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.fseqUseShowFolderCheckbox.state = [defaults boolForKey:@"FSEQUseShowFolder"] ? NSControlStateValueOn : NSControlStateValueOff;

    NSString *renderCachePath = [defaults stringForKey:@"RenderCachePath"];
    if (renderCachePath) {
        self.renderCachePathControl.URL = [NSURL fileURLWithPath:renderCachePath];
    }

    NSString *fseqPath = [defaults stringForKey:@"FSEQPath"];
    if (fseqPath) {
        self.fseqPathControl.URL = [NSURL fileURLWithPath:fseqPath];
    }

    self.renderCachePathControl.enabled = !self.renderCacheUseShowFolderCheckbox.state;
    self.fseqPathControl.enabled = !self.fseqUseShowFolderCheckbox.state;
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [defaults setBool:(self.renderOnSaveCheckbox.state == NSControlStateValueOn) forKey:@"RenderOnSave"];
    [defaults setBool:(self.lowDefinitionRenderCheckbox.state == NSControlStateValueOn) forKey:@"LowDefinitionRender"];
    [defaults setBool:(self.fseqSaveCheckbox.state == NSControlStateValueOn) forKey:@"SaveFSEQOnSave"];

    [defaults setInteger:self.modelBlendDefaultPopup.indexOfSelectedItem forKey:@"ModelBlendDefault"];
    [defaults setInteger:self.renderCachePopup.indexOfSelectedItem forKey:@"RenderCache"];
    [defaults setInteger:self.autoSaveIntervalPopup.indexOfSelectedItem forKey:@"AutoSaveInterval"];
    [defaults setInteger:self.fseqVersionPopup.indexOfSelectedItem forKey:@"FSEQVersion"];
    [defaults setInteger:self.viewDefaultPopup.indexOfSelectedItem forKey:@"DefaultView"];
    [defaults setInteger:self.maxRenderCacheSizePopup.indexOfSelectedItem forKey:@"MaxRenderCacheSize"];

    [defaults setBool:(self.renderCacheUseShowFolderCheckbox.state == NSControlStateValueOn) forKey:@"RenderCacheUseShowFolder"];
    [defaults setBool:(self.fseqUseShowFolderCheckbox.state == NSControlStateValueOn) forKey:@"FSEQUseShowFolder"];

    if (self.renderCachePathControl.URL) {
        [defaults setObject:self.renderCachePathControl.URL.path forKey:@"RenderCachePath"];
    }

    if (self.fseqPathControl.URL) {
        [defaults setObject:self.fseqPathControl.URL.path forKey:@"FSEQPath"];
    }

    [defaults synchronize];
}

@end
