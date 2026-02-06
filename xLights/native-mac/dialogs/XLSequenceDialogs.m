/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLSequenceDialogs.h"
#import "../XLEngineBridge.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const CGFloat kLabelWidth = 120.0;

#pragma mark - XLNewSequenceDialog

@interface XLNewSequenceDialog () <NSTextFieldDelegate>

@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *durationField;
@property (nonatomic, strong) NSStepper *durationStepper;
@property (nonatomic, strong) NSPopUpButton *intervalPopup;
@property (nonatomic, strong) NSTextField *audioPathField;
@property (nonatomic, strong) NSButton *browseButton;
@property (nonatomic, strong) NSButton *clearAudioButton;

@end

@implementation XLNewSequenceDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"New Sequence";
        self.okButtonTitle = @"Create";
        self.minWidth = 450;
        self.minHeight = 220;
        _sequenceName = @"New Sequence";
        _durationSeconds = 60;
        _frameIntervalMs = 25;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Sequence name
    _nameField = [XLBaseSheetController createTextField];
    _nameField.stringValue = _sequenceName;
    _nameField.delegate = (id<NSTextFieldDelegate>)self;
    [_nameField.widthAnchor constraintEqualToConstant:200].active = YES;

    NSStackView *nameRow = [XLBaseSheetController formRowWithLabel:@"Sequence Name:"
                                                           control:_nameField
                                                        labelWidth:kLabelWidth];
    [stack addArrangedSubview:nameRow];

    // Duration
    NSStackView *durationRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    durationRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    durationRow.spacing = 8;

    NSTextField *durLabel = [NSTextField labelWithString:@"Duration:"];
    durLabel.alignment = NSTextAlignmentRight;
    [durLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _durationField = [XLBaseSheetController createNumericField];
    _durationField.integerValue = _durationSeconds;
    [_durationField setTarget:self];
    [_durationField setAction:@selector(durationFieldChanged:)];
    [_durationField.widthAnchor constraintEqualToConstant:60].active = YES;

    _durationStepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    _durationStepper.minValue = 1;
    _durationStepper.maxValue = 3600;
    _durationStepper.increment = 10;
    _durationStepper.integerValue = _durationSeconds;
    [_durationStepper setTarget:self];
    [_durationStepper setAction:@selector(durationStepperChanged:)];

    NSTextField *secLabel = [NSTextField labelWithString:@"seconds"];
    secLabel.textColor = [NSColor secondaryLabelColor];

    [durationRow addArrangedSubview:durLabel];
    [durationRow addArrangedSubview:_durationField];
    [durationRow addArrangedSubview:_durationStepper];
    [durationRow addArrangedSubview:secLabel];
    [stack addArrangedSubview:durationRow];

    // Frame interval
    _intervalPopup = [XLBaseSheetController createPopUpButton];
    [_intervalPopup addItemWithTitle:@"25 ms (40 fps)"];
    [_intervalPopup addItemWithTitle:@"50 ms (20 fps)"];
    [_intervalPopup addItemWithTitle:@"100 ms (10 fps)"];
    _intervalPopup.menu.itemArray[0].tag = 25;
    _intervalPopup.menu.itemArray[1].tag = 50;
    _intervalPopup.menu.itemArray[2].tag = 100;
    [_intervalPopup selectItemWithTag:_frameIntervalMs];

    NSStackView *intervalRow = [XLBaseSheetController formRowWithLabel:@"Frame Interval:"
                                                               control:_intervalPopup
                                                            labelWidth:kLabelWidth];
    [stack addArrangedSubview:intervalRow];

    // Audio file
    NSStackView *audioRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    audioRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    audioRow.spacing = 8;

    NSTextField *audioLabel = [NSTextField labelWithString:@"Audio File:"];
    audioLabel.alignment = NSTextAlignmentRight;
    [audioLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _audioPathField = [XLBaseSheetController createTextField];
    _audioPathField.editable = NO;
    _audioPathField.placeholderString = @"No audio file (animation sequence)";
    _audioPathField.stringValue = _audioFilePath ?: @"";
    [_audioPathField.widthAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;

    _browseButton = [NSButton buttonWithTitle:@"Browse..." target:self action:@selector(browseAudio:)];
    _clearAudioButton = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clearAudio:)];
    _clearAudioButton.hidden = (_audioFilePath == nil);

    [audioRow addArrangedSubview:audioLabel];
    [audioRow addArrangedSubview:_audioPathField];
    [audioRow addArrangedSubview:_browseButton];
    [audioRow addArrangedSubview:_clearAudioButton];
    [stack addArrangedSubview:audioRow];

    // Info label
    NSTextField *infoLabel = [NSTextField wrappingLabelWithString:
        @"Note: Duration will be set automatically if an audio file is selected."];
    infoLabel.textColor = [NSColor secondaryLabelColor];
    infoLabel.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:infoLabel];
    [infoLabel.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor].active = YES;
    [infoLabel.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor].active = YES;

    return stack;
}

- (void)durationFieldChanged:(id)sender {
    _durationStepper.integerValue = _durationField.integerValue;
}

- (void)durationStepperChanged:(id)sender {
    _durationField.integerValue = _durationStepper.integerValue;
}

- (void)browseAudio:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedContentTypes = @[
        [UTType typeWithMIMEType:@"audio/mpeg"],
        [UTType typeWithMIMEType:@"audio/wav"],
        [UTType typeWithMIMEType:@"audio/x-wav"],
        [UTType typeWithMIMEType:@"audio/mp4"],
        [UTType typeWithMIMEType:@"audio/ogg"],
        [UTType typeWithMIMEType:@"audio/flac"],
    ];

    [panel beginSheetModalForWindow:self.sheet completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            self.audioPathField.stringValue = panel.URL.path;
            self.audioFilePath = panel.URL.path;
            self.clearAudioButton.hidden = NO;

            // TODO: Get duration from audio file
        }
    }];
}

- (void)clearAudio:(id)sender {
    _audioPathField.stringValue = @"";
    _audioFilePath = nil;
    _clearAudioButton.hidden = YES;
}

- (BOOL)isMusicalSequence {
    return _audioFilePath != nil && _audioFilePath.length > 0;
}

- (NSString *)validate {
    if (_nameField.stringValue.length == 0) {
        return @"Please enter a sequence name.";
    }

    if (_durationField.integerValue < 1) {
        return @"Duration must be at least 1 second.";
    }

    // Check if file already exists
    if (_showDirectory) {
        NSString *path = [_showDirectory stringByAppendingPathComponent:
            [_nameField.stringValue stringByAppendingPathExtension:@"xsq"]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return @"A sequence with this name already exists.";
        }
    }

    return nil;
}

- (void)sheetDidLoad {
    // Generate a unique default name if the current one already exists
    if (_showDirectory) {
        NSString *baseName = _sequenceName;
        NSString *path = [_showDirectory stringByAppendingPathComponent:
            [baseName stringByAppendingPathExtension:@"xsq"]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            for (int suffix = 2; suffix < 1000; suffix++) {
                NSString *candidate = [NSString stringWithFormat:@"%@ (%d)", baseName, suffix];
                NSString *candidatePath = [_showDirectory stringByAppendingPathComponent:
                    [candidate stringByAppendingPathExtension:@"xsq"]];
                if (![[NSFileManager defaultManager] fileExistsAtPath:candidatePath]) {
                    _nameField.stringValue = candidate;
                    _sequenceName = candidate;
                    break;
                }
            }
        }
    }
    [self updateOKButtonState];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    [self updateOKButtonState];
}

- (void)okClicked:(id)sender {
    _sequenceName = _nameField.stringValue;
    _durationSeconds = _durationField.integerValue;
    _frameIntervalMs = _intervalPopup.selectedItem.tag;
    [super okClicked:sender];
}

@end

#pragma mark - XLSequenceSettingsDialog

@interface XLSequenceSettingsDialog ()

@property (nonatomic, strong) NSTabView *tabView;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *authorField;
@property (nonatomic, strong) NSTextField *emailField;
@property (nonatomic, strong) NSTextField *websiteField;
@property (nonatomic, strong) NSTextField *songField;
@property (nonatomic, strong) NSTextField *artistField;
@property (nonatomic, strong) NSTextField *albumField;
@property (nonatomic, strong) NSScrollView *commentsScrollView;
@property (nonatomic, strong) NSTextField *durationLabel;
@property (nonatomic, strong) NSTextField *intervalLabel;

@end

@implementation XLSequenceSettingsDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Sequence Settings";
        self.minWidth = 450;
        self.minHeight = 350;
        _frameIntervalMs = 50;
    }
    return self;
}

- (NSView *)buildContentView {
    _tabView = [[NSTabView alloc] initWithFrame:NSZeroRect];
    _tabView.translatesAutoresizingMaskIntoConstraints = NO;

    // Info tab
    NSTabViewItem *infoTab = [[NSTabViewItem alloc] initWithIdentifier:@"info"];
    infoTab.label = @"Information";
    infoTab.view = [self buildInfoTab];
    [_tabView addTabViewItem:infoTab];

    // Media tab
    NSTabViewItem *mediaTab = [[NSTabViewItem alloc] initWithIdentifier:@"media"];
    mediaTab.label = @"Media";
    mediaTab.view = [self buildMediaTab];
    [_tabView addTabViewItem:mediaTab];

    return _tabView;
}

- (NSView *)buildInfoTab {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.edgeInsets = NSEdgeInsetsMake(10, 10, 10, 10);

    // Sequence name
    _nameField = [XLBaseSheetController createTextField];
    _nameField.stringValue = _sequenceName ?: @"";
    [_nameField.widthAnchor constraintEqualToConstant:250].active = YES;
    NSStackView *nameRow = [XLBaseSheetController formRowWithLabel:@"Sequence Name:" control:_nameField labelWidth:kLabelWidth];
    [stack addArrangedSubview:nameRow];

    // Author
    _authorField = [XLBaseSheetController createTextField];
    _authorField.stringValue = _author ?: @"";
    [_authorField.widthAnchor constraintEqualToConstant:200].active = YES;
    NSStackView *authorRow = [XLBaseSheetController formRowWithLabel:@"Author:" control:_authorField labelWidth:kLabelWidth];
    [stack addArrangedSubview:authorRow];

    // Email
    _emailField = [XLBaseSheetController createTextField];
    _emailField.stringValue = _authorEmail ?: @"";
    [_emailField.widthAnchor constraintEqualToConstant:200].active = YES;
    NSStackView *emailRow = [XLBaseSheetController formRowWithLabel:@"Email:" control:_emailField labelWidth:kLabelWidth];
    [stack addArrangedSubview:emailRow];

    // Website
    _websiteField = [XLBaseSheetController createTextField];
    _websiteField.stringValue = _authorWebsite ?: @"";
    [_websiteField.widthAnchor constraintEqualToConstant:250].active = YES;
    NSStackView *websiteRow = [XLBaseSheetController formRowWithLabel:@"Website:" control:_websiteField labelWidth:kLabelWidth];
    [stack addArrangedSubview:websiteRow];

    // Comments
    _commentsScrollView = [XLBaseSheetController createTextViewWithHeight:60];
    NSTextView *textView = [XLBaseSheetController textViewFromScrollView:_commentsScrollView];
    textView.string = _comments ?: @"";

    NSTextField *commentsLabel = [NSTextField labelWithString:@"Comments:"];
    commentsLabel.alignment = NSTextAlignmentRight;

    NSStackView *commentsRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    commentsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    commentsRow.alignment = NSLayoutAttributeTop;
    commentsRow.spacing = 8;
    [commentsLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;
    [commentsRow addArrangedSubview:commentsLabel];
    [commentsRow addArrangedSubview:_commentsScrollView];
    [stack addArrangedSubview:commentsRow];
    [_commentsScrollView.widthAnchor constraintEqualToConstant:250].active = YES;

    return stack;
}

- (NSView *)buildMediaTab {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.edgeInsets = NSEdgeInsetsMake(10, 10, 10, 10);

    // Song
    _songField = [XLBaseSheetController createTextField];
    _songField.stringValue = _songName ?: @"";
    [_songField.widthAnchor constraintEqualToConstant:200].active = YES;
    NSStackView *songRow = [XLBaseSheetController formRowWithLabel:@"Song:" control:_songField labelWidth:kLabelWidth];
    [stack addArrangedSubview:songRow];

    // Artist
    _artistField = [XLBaseSheetController createTextField];
    _artistField.stringValue = _artistName ?: @"";
    [_artistField.widthAnchor constraintEqualToConstant:200].active = YES;
    NSStackView *artistRow = [XLBaseSheetController formRowWithLabel:@"Artist:" control:_artistField labelWidth:kLabelWidth];
    [stack addArrangedSubview:artistRow];

    // Album
    _albumField = [XLBaseSheetController createTextField];
    _albumField.stringValue = _albumName ?: @"";
    [_albumField.widthAnchor constraintEqualToConstant:200].active = YES;
    NSStackView *albumRow = [XLBaseSheetController formRowWithLabel:@"Album:" control:_albumField labelWidth:kLabelWidth];
    [stack addArrangedSubview:albumRow];

    // Duration (read-only)
    NSInteger totalSec = _durationMs / 1000;
    NSInteger minutes = totalSec / 60;
    NSInteger seconds = totalSec % 60;
    _durationLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds]];
    NSStackView *durationRow = [XLBaseSheetController formRowWithLabel:@"Duration:" control:_durationLabel labelWidth:kLabelWidth];
    [stack addArrangedSubview:durationRow];

    // Frame interval (read-only)
    _intervalLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%ld ms", (long)_frameIntervalMs]];
    NSStackView *intervalRow = [XLBaseSheetController formRowWithLabel:@"Frame Interval:" control:_intervalLabel labelWidth:kLabelWidth];
    [stack addArrangedSubview:intervalRow];

    return stack;
}

- (void)okClicked:(id)sender {
    _sequenceName = _nameField.stringValue;
    _author = _authorField.stringValue;
    _authorEmail = _emailField.stringValue;
    _authorWebsite = _websiteField.stringValue;
    _songName = _songField.stringValue;
    _artistName = _artistField.stringValue;
    _albumName = _albumField.stringValue;

    NSTextView *textView = [XLBaseSheetController textViewFromScrollView:_commentsScrollView];
    _comments = textView.string;

    [super okClicked:sender];
}

@end

#pragma mark - XLSequenceExportDialog

@interface XLSequenceExportDialog ()

@property (nonatomic, strong) NSPopUpButton *formatPopup;
@property (nonatomic, strong) NSTextField *pathField;
@property (nonatomic, strong) NSButton *browseButton;
@property (nonatomic, strong) NSButton *selectedOnlyCheckbox;
@property (nonatomic, strong) NSButton *includeAudioCheckbox;

@end

@implementation XLSequenceExportDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Export Sequence";
        self.okButtonTitle = @"Export";
        self.minWidth = 450;
        self.minHeight = 200;
        _exportFormat = @"FSEQ";
        _availableFormats = @[@"FSEQ", @"Falcon Pi Player", @"LOR S5", @"Vixen 3", @"HLS", @"Video"];
        _exportSelectedOnly = NO;
        _includeAudio = YES;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Format
    _formatPopup = [XLBaseSheetController createPopUpButton];
    for (NSString *format in _availableFormats) {
        [_formatPopup addItemWithTitle:format];
    }
    [_formatPopup selectItemWithTitle:_exportFormat];

    NSStackView *formatRow = [XLBaseSheetController formRowWithLabel:@"Format:"
                                                             control:_formatPopup
                                                          labelWidth:kLabelWidth];
    [stack addArrangedSubview:formatRow];

    // Path
    NSStackView *pathRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    pathRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    pathRow.spacing = 8;

    NSTextField *pathLabel = [NSTextField labelWithString:@"Export To:"];
    pathLabel.alignment = NSTextAlignmentRight;
    [pathLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _pathField = [XLBaseSheetController createTextField];
    _pathField.editable = NO;
    _pathField.stringValue = _exportPath ?: @"";
    [_pathField.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;

    _browseButton = [NSButton buttonWithTitle:@"Browse..." target:self action:@selector(browsePath:)];

    [pathRow addArrangedSubview:pathLabel];
    [pathRow addArrangedSubview:_pathField];
    [pathRow addArrangedSubview:_browseButton];
    [stack addArrangedSubview:pathRow];

    // Options
    _selectedOnlyCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Export selected models only"];
    _selectedOnlyCheckbox.state = _exportSelectedOnly ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_selectedOnlyCheckbox];

    _includeAudioCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Include audio in export"];
    _includeAudioCheckbox.state = _includeAudio ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_includeAudioCheckbox];

    return stack;
}

- (void)browsePath:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;

    [panel beginSheetModalForWindow:self.sheet completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            self.pathField.stringValue = panel.URL.path;
            self.exportPath = panel.URL.path;
        }
    }];
}

- (NSString *)validate {
    if (_pathField.stringValue.length == 0) {
        return @"Please select an export location.";
    }
    return nil;
}

- (void)okClicked:(id)sender {
    _exportFormat = _formatPopup.selectedItem.title;
    _exportPath = _pathField.stringValue;
    _exportSelectedOnly = (_selectedOnlyCheckbox.state == NSControlStateValueOn);
    _includeAudio = (_includeAudioCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end

#pragma mark - XLSaveChangesDialog

@implementation XLSaveChangesDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        _documentName = @"Untitled";
    }
    return self;
}

- (NSModalResponse)runModalForWindow:(NSWindow *)parentWindow {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Do you want to save the changes made to \"%@\"?", _documentName];
    alert.informativeText = @"Your changes will be lost if you don't save them.";
    alert.alertStyle = NSAlertStyleWarning;

    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Don't Save"];
    [alert addButtonWithTitle:@"Cancel"];

    if (parentWindow) {
        __block NSModalResponse response = NSModalResponseCancel;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        [alert beginSheetModalForWindow:parentWindow completionHandler:^(NSModalResponse returnCode) {
            response = returnCode;
            dispatch_semaphore_signal(sem);
        }];

        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        return response;
    } else {
        return [alert runModal];
    }
}

@end

#pragma mark - XLMetronomeLabelDialog

@interface XLMetronomeLabelDialog ()

@property (nonatomic, strong) NSTextField *bpmField;
@property (nonatomic, strong) NSPopUpButton *beatsPopup;
@property (nonatomic, strong) NSTextField *offsetField;
@property (nonatomic, strong) NSButton *tagsCheckbox;

@end

@implementation XLMetronomeLabelDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Metronome Settings";
        self.minWidth = 350;
        self.minHeight = 200;
        _bpm = 120.0;
        _beatsPerMeasure = 4;
        _startOffsetMs = 0;
        _addTags = NO;
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // BPM
    _bpmField = [XLBaseSheetController createTextField];
    _bpmField.stringValue = [NSString stringWithFormat:@"%.1f", _bpm];
    [_bpmField.widthAnchor constraintEqualToConstant:80].active = YES;

    NSStackView *bpmRow = [XLBaseSheetController formRowWithLabel:@"BPM:" control:_bpmField labelWidth:kLabelWidth];
    [stack addArrangedSubview:bpmRow];

    // Beats per measure
    _beatsPopup = [XLBaseSheetController createPopUpButton];
    for (int i = 2; i <= 12; i++) {
        [_beatsPopup addItemWithTitle:[NSString stringWithFormat:@"%d", i]];
        _beatsPopup.lastItem.tag = i;
    }
    [_beatsPopup selectItemWithTag:_beatsPerMeasure];

    NSStackView *beatsRow = [XLBaseSheetController formRowWithLabel:@"Beats/Measure:" control:_beatsPopup labelWidth:kLabelWidth];
    [stack addArrangedSubview:beatsRow];

    // Start offset
    _offsetField = [XLBaseSheetController createNumericField];
    _offsetField.integerValue = _startOffsetMs;
    [_offsetField.widthAnchor constraintEqualToConstant:80].active = YES;

    NSStackView *offsetRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    offsetRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    offsetRow.spacing = 8;

    NSTextField *offsetLabel = [NSTextField labelWithString:@"Start Offset:"];
    offsetLabel.alignment = NSTextAlignmentRight;
    [offsetLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    NSTextField *msLabel = [NSTextField labelWithString:@"ms"];
    msLabel.textColor = [NSColor secondaryLabelColor];

    [offsetRow addArrangedSubview:offsetLabel];
    [offsetRow addArrangedSubview:_offsetField];
    [offsetRow addArrangedSubview:msLabel];
    [stack addArrangedSubview:offsetRow];

    // Tags checkbox
    _tagsCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Add section tags (Verse, Chorus, etc.)"];
    _tagsCheckbox.state = _addTags ? NSControlStateValueOn : NSControlStateValueOff;
    [stack addArrangedSubview:_tagsCheckbox];

    return stack;
}

- (NSString *)validate {
    double bpm = [_bpmField doubleValue];
    if (bpm < 20 || bpm > 400) {
        return @"BPM must be between 20 and 400.";
    }
    return nil;
}

- (void)okClicked:(id)sender {
    _bpm = [_bpmField doubleValue];
    _beatsPerMeasure = _beatsPopup.selectedItem.tag;
    _startOffsetMs = _offsetField.integerValue;
    _addTags = (_tagsCheckbox.state == NSControlStateValueOn);
    [super okClicked:sender];
}

@end
