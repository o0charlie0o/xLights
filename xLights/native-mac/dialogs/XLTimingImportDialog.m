/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLTimingImportDialog.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const CGFloat kLabelWidth = 130.0;

@interface XLTimingImportDialog ()

@property (nonatomic, strong) NSPopUpButton *sourcePopup;
@property (nonatomic, strong) NSTextField *filePathField;
@property (nonatomic, strong) NSButton *browseButton;
@property (nonatomic, strong) NSTextField *trackNameField;
@property (nonatomic, strong) NSButton *replaceCheckbox;
@property (nonatomic, strong) NSSlider *sensitivitySlider;
@property (nonatomic, strong) NSTextField *sensitivityLabel;
@property (nonatomic, strong) NSPopUpButton *vampPopup;

@property (nonatomic, strong) NSStackView *fileRow;
@property (nonatomic, strong) NSStackView *sensitivityRow;
@property (nonatomic, strong) NSStackView *vampRow;

@end

@implementation XLTimingImportDialog

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Import Timing";
        self.minWidth = 500;
        self.minHeight = 280;
        _source = XLTimingSourceLyrics;
        _trackName = @"Imported Timing";
        _replaceExisting = NO;
        _beatSensitivity = 0.5;
        _availableVAMPPlugins = @[];
    }
    return self;
}

- (NSView *)buildContentView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;

    // Source selection
    _sourcePopup = [XLBaseSheetController createPopUpButton];
    [_sourcePopup addItemWithTitle:@"Lyrics File (.lrc, .txt)"];
    [_sourcePopup addItemWithTitle:@"Audio Analysis (Beat Detection)"];
    [_sourcePopup addItemWithTitle:@"VAMP Plugin"];
    [_sourcePopup addItemWithTitle:@"Papagayo Phonemes"];
    [_sourcePopup addItemWithTitle:@"MIDI File"];
    [_sourcePopup addItemWithTitle:@"Other Sequence"];

    _sourcePopup.menu.itemArray[0].tag = XLTimingSourceLyrics;
    _sourcePopup.menu.itemArray[1].tag = XLTimingSourceAudioAnalysis;
    _sourcePopup.menu.itemArray[2].tag = XLTimingSourceVAMP;
    _sourcePopup.menu.itemArray[3].tag = XLTimingSourcePapagayo;
    _sourcePopup.menu.itemArray[4].tag = XLTimingSourceMIDI;
    _sourcePopup.menu.itemArray[5].tag = XLTimingSourceOtherSequence;

    [_sourcePopup setTarget:self];
    [_sourcePopup setAction:@selector(sourceChanged:)];

    NSStackView *sourceRow = [XLBaseSheetController formRowWithLabel:@"Import From:"
                                                             control:_sourcePopup
                                                          labelWidth:kLabelWidth];
    [stack addArrangedSubview:sourceRow];

    // File path row
    _fileRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _fileRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _fileRow.spacing = 8;

    NSTextField *fileLabel = [NSTextField labelWithString:@"File:"];
    fileLabel.alignment = NSTextAlignmentRight;
    [fileLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _filePathField = [XLBaseSheetController createTextField];
    _filePathField.editable = NO;
    _filePathField.placeholderString = @"No file selected";
    [_filePathField.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;

    _browseButton = [NSButton buttonWithTitle:@"Browse..." target:self action:@selector(browseClicked:)];

    [_fileRow addArrangedSubview:fileLabel];
    [_fileRow addArrangedSubview:_filePathField];
    [_fileRow addArrangedSubview:_browseButton];
    [stack addArrangedSubview:_fileRow];

    // Sensitivity row (for audio analysis)
    _sensitivityRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _sensitivityRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _sensitivityRow.spacing = 8;

    NSTextField *sensLabel = [NSTextField labelWithString:@"Sensitivity:"];
    sensLabel.alignment = NSTextAlignmentRight;
    [sensLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _sensitivitySlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _sensitivitySlider.minValue = 0.0;
    _sensitivitySlider.maxValue = 1.0;
    _sensitivitySlider.doubleValue = _beatSensitivity;
    [_sensitivitySlider setTarget:self];
    [_sensitivitySlider setAction:@selector(sensitivityChanged:)];
    [_sensitivitySlider.widthAnchor constraintEqualToConstant:150].active = YES;

    _sensitivityLabel = [NSTextField labelWithString:@"50%"];
    [_sensitivityLabel.widthAnchor constraintEqualToConstant:40].active = YES;

    [_sensitivityRow addArrangedSubview:sensLabel];
    [_sensitivityRow addArrangedSubview:_sensitivitySlider];
    [_sensitivityRow addArrangedSubview:_sensitivityLabel];
    _sensitivityRow.hidden = YES;
    [stack addArrangedSubview:_sensitivityRow];

    // VAMP plugin row
    _vampRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _vampRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _vampRow.spacing = 8;

    NSTextField *vampLabel = [NSTextField labelWithString:@"Plugin:"];
    vampLabel.alignment = NSTextAlignmentRight;
    [vampLabel.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;

    _vampPopup = [XLBaseSheetController createPopUpButton];
    for (NSString *plugin in _availableVAMPPlugins) {
        [_vampPopup addItemWithTitle:plugin];
    }

    [_vampRow addArrangedSubview:vampLabel];
    [_vampRow addArrangedSubview:_vampPopup];
    _vampRow.hidden = YES;
    [stack addArrangedSubview:_vampRow];

    // Track name
    _trackNameField = [XLBaseSheetController createTextField];
    _trackNameField.stringValue = _trackName;

    NSStackView *trackRow = [XLBaseSheetController formRowWithLabel:@"Track Name:"
                                                            control:_trackNameField
                                                         labelWidth:kLabelWidth];
    [_trackNameField.widthAnchor constraintEqualToConstant:180].active = YES;
    [stack addArrangedSubview:trackRow];

    // Replace existing checkbox
    _replaceCheckbox = [XLBaseSheetController createCheckboxWithTitle:@"Replace existing timing marks"];
    _replaceCheckbox.state = _replaceExisting ? NSControlStateValueOn : NSControlStateValueOff;

    NSStackView *replaceRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    replaceRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    replaceRow.spacing = 8;

    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer.widthAnchor constraintEqualToConstant:kLabelWidth + 8].active = YES;

    [replaceRow addArrangedSubview:spacer];
    [replaceRow addArrangedSubview:_replaceCheckbox];
    [stack addArrangedSubview:replaceRow];

    return stack;
}

- (void)sheetDidLoad {
    [self updateVisibility];
}

- (void)updateVisibility {
    XLTimingSource source = (XLTimingSource)_sourcePopup.selectedItem.tag;

    // File row shown for file-based sources
    BOOL needsFile = (source == XLTimingSourceLyrics ||
                      source == XLTimingSourcePapagayo ||
                      source == XLTimingSourceMIDI ||
                      source == XLTimingSourceOtherSequence);
    _fileRow.hidden = !needsFile;

    // Sensitivity shown for audio analysis
    _sensitivityRow.hidden = (source != XLTimingSourceAudioAnalysis);

    // VAMP shown for VAMP source
    _vampRow.hidden = (source != XLTimingSourceVAMP);
}

#pragma mark - Actions

- (void)sourceChanged:(id)sender {
    [self updateVisibility];
    [self updateOKButtonState];
}

- (void)sensitivityChanged:(id)sender {
    _sensitivityLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", _sensitivitySlider.doubleValue * 100];
}

- (void)browseClicked:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;

    XLTimingSource source = (XLTimingSource)_sourcePopup.selectedItem.tag;

    // Set allowed file types based on source
    switch (source) {
        case XLTimingSourceLyrics:
            panel.allowedContentTypes = @[
                [UTType typeWithFilenameExtension:@"lrc"],
                [UTType typeWithFilenameExtension:@"txt"],
            ];
            break;

        case XLTimingSourcePapagayo:
            panel.allowedContentTypes = @[
                [UTType typeWithFilenameExtension:@"pgo"],
            ];
            break;

        case XLTimingSourceMIDI:
            panel.allowedContentTypes = @[
                [UTType typeWithFilenameExtension:@"mid"],
                [UTType typeWithFilenameExtension:@"midi"],
            ];
            break;

        case XLTimingSourceOtherSequence:
            panel.allowedContentTypes = @[
                [UTType typeWithFilenameExtension:@"xsq"],
                [UTType typeWithFilenameExtension:@"xml"],
            ];
            break;

        default:
            break;
    }

    [panel beginSheetModalForWindow:self.sheet completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            self.filePathField.stringValue = panel.URL.path;
            self.sourceFilePath = panel.URL.path;
            [self updateOKButtonState];
        }
    }];
}

#pragma mark - Validation

- (NSString *)validate {
    XLTimingSource source = (XLTimingSource)_sourcePopup.selectedItem.tag;

    // Validate file path for file-based sources
    BOOL needsFile = (source == XLTimingSourceLyrics ||
                      source == XLTimingSourcePapagayo ||
                      source == XLTimingSourceMIDI ||
                      source == XLTimingSourceOtherSequence);

    if (needsFile && (_filePathField.stringValue.length == 0)) {
        return @"Please select a file.";
    }

    if (needsFile && _filePathField.stringValue.length > 0) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:_filePathField.stringValue]) {
            return @"Selected file does not exist.";
        }
    }

    // Validate VAMP plugin
    if (source == XLTimingSourceVAMP && _vampPopup.selectedItem == nil) {
        return @"Please select a VAMP plugin.";
    }

    // Validate track name
    if (_trackNameField.stringValue.length == 0) {
        return @"Please enter a track name.";
    }

    return nil;
}

- (void)okClicked:(id)sender {
    _source = (XLTimingSource)_sourcePopup.selectedItem.tag;
    _sourceFilePath = _filePathField.stringValue;
    _trackName = _trackNameField.stringValue;
    _replaceExisting = (_replaceCheckbox.state == NSControlStateValueOn);
    _beatSensitivity = _sensitivitySlider.doubleValue;
    _vampPlugin = _vampPopup.selectedItem.title;

    [super okClicked:sender];
}

@end
