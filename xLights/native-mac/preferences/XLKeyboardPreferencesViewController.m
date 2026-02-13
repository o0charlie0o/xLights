/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLKeyboardPreferencesViewController.h"

#pragma mark - Binding Display Model

/**
 * Model class representing a single key binding for display in the table view.
 */
@interface XLKeyBindingItem : NSObject

@property (nonatomic, copy) NSString *actionName;       // Display name (formatted from type)
@property (nonatomic, copy) NSString *actionType;       // Raw type (e.g., "TOGGLE_PLAY")
@property (nonatomic, copy) NSString *shortcut;         // Key combination (e.g., "Space", "Cmd+S")
@property (nonatomic, copy) NSString *scopeName;        // Scope display name (e.g., "All", "Sequence")
@property (nonatomic, copy) NSString *tooltip;          // Description of the action
@property (nonatomic, assign) NSInteger scopeValue;     // Numeric scope for filtering (0=All, 1=Setup, 2=Layout, 3=Sequence)
@property (nonatomic, assign) BOOL isDisabled;          // Whether binding is disabled

+ (instancetype)itemWithActionType:(NSString *)type
                          shortcut:(NSString *)shortcut
                             scope:(NSInteger)scope
                           tooltip:(NSString *)tooltip
                        isDisabled:(BOOL)disabled;

@end

@implementation XLKeyBindingItem

+ (instancetype)itemWithActionType:(NSString *)type
                          shortcut:(NSString *)shortcut
                             scope:(NSInteger)scope
                           tooltip:(NSString *)tooltip
                        isDisabled:(BOOL)disabled {
    XLKeyBindingItem *item = [[XLKeyBindingItem alloc] init];
    item.actionType = type;
    item.shortcut = shortcut ?: @"Not Assigned";
    item.scopeValue = scope;
    item.tooltip = tooltip ?: @"";
    item.isDisabled = disabled;

    // Format action name from type (e.g., "TOGGLE_PLAY" -> "Toggle Play")
    item.actionName = [self formatActionName:type];

    // Set scope display name
    switch (scope) {
        case 0: item.scopeName = @"All"; break;
        case 1: item.scopeName = @"Setup"; break;
        case 2: item.scopeName = @"Layout"; break;
        case 3: item.scopeName = @"Sequence"; break;
        default: item.scopeName = @"Unknown"; break;
    }

    return item;
}

+ (NSString *)formatActionName:(NSString *)type {
    if (!type || type.length == 0) return @"";

    // Handle special types
    if ([type isEqualToString:@"EFFECT"]) return @"Effect Shortcut";
    if ([type isEqualToString:@"PRESET"]) return @"Preset Shortcut";
    if ([type isEqualToString:@"APPLYSETTING"]) return @"Apply Setting";

    // Replace underscores with spaces and capitalize each word
    NSMutableString *formatted = [NSMutableString string];
    NSArray *words = [type componentsSeparatedByString:@"_"];

    for (NSString *word in words) {
        if (word.length > 0) {
            NSString *capitalized = [[word substringToIndex:1] uppercaseString];
            NSString *rest = [[word substringFromIndex:1] lowercaseString];
            [formatted appendFormat:@"%@%@ ", capitalized, rest];
        }
    }

    return [formatted stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@end

#pragma mark - XLKeyboardPreferencesViewController

@interface XLKeyboardPreferencesViewController ()

@property (nonatomic, strong) NSMutableArray<XLKeyBindingItem *> *allBindings;
@property (nonatomic, strong) NSMutableArray<XLKeyBindingItem *> *filteredBindings;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSButton *resetButton;
@property (nonatomic, copy) NSString *currentSearchText;
@property (nonatomic, assign) NSInteger currentScopeFilter;  // -1 = all, 0-3 = specific scope

@end

@implementation XLKeyboardPreferencesViewController

#pragma mark - Initialization

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _allBindings = [NSMutableArray array];
        _filteredBindings = [NSMutableArray array];
        _currentSearchText = @"";
        _currentScopeFilter = -1;  // Show all scopes by default
    }
    return self;
}

#pragma mark - View Lifecycle

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 650, 500)];

    [self setupUI];
    [self loadDefaultBindings];
    [self applyFilters];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Register for show folder changes if needed
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showFolderDidChange:)
                                                 name:@"XLShowFolderDidChangeNotification"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI Setup

- (void)setupUI {
    NSStackView *mainStack = [[NSStackView alloc] initWithFrame:self.view.bounds];
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.alignment = NSLayoutAttributeWidth;
    mainStack.spacing = 12;
    mainStack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [mainStack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    // Title
    NSTextField *titleLabel = [NSTextField labelWithString:@"Keyboard Shortcuts"];
    titleLabel.font = [NSFont boldSystemFontOfSize:14];
    [mainStack addArrangedSubview:titleLabel];

    // Filter controls row
    NSStackView *filterRow = [[NSStackView alloc] init];
    filterRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    filterRow.alignment = NSLayoutAttributeCenterY;
    filterRow.spacing = 12;
    filterRow.distribution = NSStackViewDistributionFill;

    // Scope filter
    NSTextField *scopeLabel = [NSTextField labelWithString:@"Scope:"];
    [filterRow addArrangedSubview:scopeLabel];

    self.scopeFilter = [[NSSegmentedControl alloc] init];
    [self.scopeFilter setSegmentCount:5];
    [self.scopeFilter setLabel:@"All" forSegment:0];
    [self.scopeFilter setLabel:@"Setup" forSegment:1];
    [self.scopeFilter setLabel:@"Layout" forSegment:2];
    [self.scopeFilter setLabel:@"Sequence" forSegment:3];
    [self.scopeFilter setLabel:@"Everywhere" forSegment:4];
    [self.scopeFilter setSelectedSegment:0];
    self.scopeFilter.target = self;
    self.scopeFilter.action = @selector(scopeFilterChanged:);
    [self.scopeFilter setWidth:60 forSegment:0];
    [self.scopeFilter setWidth:60 forSegment:1];
    [self.scopeFilter setWidth:60 forSegment:2];
    [self.scopeFilter setWidth:75 forSegment:3];
    [self.scopeFilter setWidth:80 forSegment:4];
    [filterRow addArrangedSubview:self.scopeFilter];

    // Spacer
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [filterRow addArrangedSubview:spacer];

    // Search field
    self.searchField = [[NSSearchField alloc] init];
    self.searchField.placeholderString = @"Search shortcuts...";
    self.searchField.delegate = self;
    [self.searchField setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.searchField.widthAnchor constraintEqualToConstant:200].active = YES;
    [filterRow addArrangedSubview:self.searchField];

    [mainStack addArrangedSubview:filterRow];

    // Table view in scroll view
    [self setupTableView];
    [mainStack addArrangedSubview:self.scrollView];

    // Make scroll view expand to fill available space
    [self.scrollView setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [self.scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;

    // Bottom row with reset button and info
    NSStackView *bottomRow = [[NSStackView alloc] init];
    bottomRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bottomRow.alignment = NSLayoutAttributeCenterY;
    bottomRow.spacing = 12;

    self.resetButton = [NSButton buttonWithTitle:@"Reset to Defaults" target:self action:@selector(resetToDefaults:)];
    [bottomRow addArrangedSubview:self.resetButton];

    NSView *bottomSpacer = [[NSView alloc] init];
    [bottomSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [bottomRow addArrangedSubview:bottomSpacer];

    NSTextField *infoLabel = [NSTextField labelWithString:@"Shortcuts can be customized in key_bindings.xml"];
    infoLabel.textColor = [NSColor secondaryLabelColor];
    infoLabel.font = [NSFont systemFontOfSize:11];
    [bottomRow addArrangedSubview:infoLabel];

    [mainStack addArrangedSubview:bottomRow];
}

- (void)setupTableView {
    self.scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 610, 350)];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.hasHorizontalScroller = NO;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.borderType = NSBezelBorder;

    self.bindingsTableView = [[NSTableView alloc] initWithFrame:self.scrollView.bounds];
    self.bindingsTableView.dataSource = self;
    self.bindingsTableView.delegate = self;
    self.bindingsTableView.usesAlternatingRowBackgroundColors = YES;
    self.bindingsTableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    self.bindingsTableView.allowsMultipleSelection = NO;
    self.bindingsTableView.allowsColumnReordering = NO;
    self.bindingsTableView.rowHeight = 24;

    // Action column
    NSTableColumn *actionColumn = [[NSTableColumn alloc] initWithIdentifier:@"action"];
    actionColumn.title = @"Action";
    actionColumn.width = 250;
    actionColumn.minWidth = 150;
    actionColumn.maxWidth = 400;
    actionColumn.resizingMask = NSTableColumnUserResizingMask;
    [self.bindingsTableView addTableColumn:actionColumn];

    // Shortcut column
    NSTableColumn *shortcutColumn = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    shortcutColumn.title = @"Shortcut";
    shortcutColumn.width = 150;
    shortcutColumn.minWidth = 80;
    shortcutColumn.maxWidth = 200;
    shortcutColumn.resizingMask = NSTableColumnUserResizingMask;
    [self.bindingsTableView addTableColumn:shortcutColumn];

    // Scope column
    NSTableColumn *scopeColumn = [[NSTableColumn alloc] initWithIdentifier:@"scope"];
    scopeColumn.title = @"Scope";
    scopeColumn.width = 100;
    scopeColumn.minWidth = 70;
    scopeColumn.maxWidth = 120;
    scopeColumn.resizingMask = NSTableColumnUserResizingMask;
    [self.bindingsTableView addTableColumn:scopeColumn];

    self.scrollView.documentView = self.bindingsTableView;
}

#pragma mark - Data Loading

- (void)loadDefaultBindings {
    [self.allBindings removeAllObjects];

    // Load from default key binding data
    // These are the standard xLights key bindings organized by scope

    // All scope bindings
    [self addBindingWithType:@"RENDER_ALL" shortcut:@"" scope:0 tooltip:@"Render all."];
    [self addBindingWithType:@"SAVE_CURRENT_TAB" shortcut:@"\u2318S" scope:0 tooltip:@"Save the currently selected tab."];
    [self addBindingWithType:@"LIGHTS_TOGGLE" shortcut:@"" scope:0 tooltip:@"Toggle output to lights on/off."];
    [self addBindingWithType:@"OPEN_SEQUENCE" shortcut:@"\u2318O" scope:0 tooltip:@"Open a sequence."];
    [self addBindingWithType:@"CLOSE_SEQUENCE" shortcut:@"\u2318W" scope:0 tooltip:@"Close the open sequence."];
    [self addBindingWithType:@"NEW_SEQUENCE" shortcut:@"\u2318N" scope:0 tooltip:@"Create a new sequence."];
    [self addBindingWithType:@"PASTE_BY_CELL" shortcut:@"" scope:0 tooltip:@"Put cut/copy/paste into Paste By Cell mode."];
    [self addBindingWithType:@"PASTE_BY_TIME" shortcut:@"" scope:0 tooltip:@"Put cut/copy/paste into Paste By Time mode."];
    [self addBindingWithType:@"BACKUP" shortcut:@"F10" scope:0 tooltip:@"Backup your show folder."];
    [self addBindingWithType:@"ALTERNATE_BACKUP" shortcut:@"F11" scope:0 tooltip:@"Backup your show folder to the alternate backup location."];
    [self addBindingWithType:@"SELECT_SHOW_FOLDER" shortcut:@"F9" scope:0 tooltip:@"Change your current show folder."];
    [self addBindingWithType:@"SEQUENCE_SETTINGS" shortcut:@"" scope:0 tooltip:@"Display the sequence settings."];
    [self addBindingWithType:@"PLAY_LOOP" shortcut:@"" scope:0 tooltip:@"Play the selected part of the song repeatedly."];
    [self addBindingWithType:@"PLAY" shortcut:@"" scope:0 tooltip:@"Play the song."];
    [self addBindingWithType:@"TOGGLE_PLAY" shortcut:@"Space" scope:0 tooltip:@"Play/Stop playing the song."];
    [self addBindingWithType:@"START_OF_SONG" shortcut:@"Home" scope:0 tooltip:@"Jump to the start of the song."];
    [self addBindingWithType:@"END_OF_SONG" shortcut:@"End" scope:0 tooltip:@"Jump to the end of the song."];
    [self addBindingWithType:@"STOP" shortcut:@"" scope:0 tooltip:@"Stop sequence playback."];
    [self addBindingWithType:@"PAUSE" shortcut:@"Pause" scope:0 tooltip:@"Pause sequence playback."];
    [self addBindingWithType:@"FOCUS_SEQUENCER" shortcut:@"F12" scope:0 tooltip:@"Force keyboard focus to the effects grid."];
    [self addBindingWithType:@"FPP_CONNECT" shortcut:@"" scope:0 tooltip:@"Run FPP Connect."];

    // Sequence scope bindings
    [self addBindingWithType:@"TIMING_ADD" shortcut:@"T" scope:3 tooltip:@"Add a timing mark."];
    [self addBindingWithType:@"TIMING_SPLIT" shortcut:@"S" scope:3 tooltip:@"Split a timing mark."];
    [self addBindingWithType:@"TIMING_DIVIDE_2" shortcut:@"" scope:3 tooltip:@"Divide timing by 2."];
    [self addBindingWithType:@"TIMING_DIVIDE_3" shortcut:@"" scope:3 tooltip:@"Divide timing by 3."];
    [self addBindingWithType:@"TIMING_DIVIDE_4" shortcut:@"" scope:3 tooltip:@"Divide timing by 4."];
    [self addBindingWithType:@"DUPLICATE_RIGHT" shortcut:@"\u2325\u21E7\u2192" scope:3 tooltip:@"Duplicate selected effect(s) to the right."];
    [self addBindingWithType:@"DUPLICATE_LEFT" shortcut:@"\u2325\u21E7\u2190" scope:3 tooltip:@"Duplicate selected effect(s) to the left."];
    [self addBindingWithType:@"DUPLICATE_UP" shortcut:@"\u2325\u21E7\u2191" scope:3 tooltip:@"Duplicate selected effect(s) to the track above."];
    [self addBindingWithType:@"DUPLICATE_DOWN" shortcut:@"\u2325\u21E7\u2193" scope:3 tooltip:@"Duplicate selected effect(s) to the track below."];
    [self addBindingWithType:@"ZOOM_IN" shortcut:@"+" scope:3 tooltip:@"Zoom into the effects grid."];
    [self addBindingWithType:@"ZOOM_OUT" shortcut:@"-" scope:3 tooltip:@"Zoom out of the effects grid."];
    [self addBindingWithType:@"ZOOM_SEL" shortcut:@"" scope:3 tooltip:@"Zoom so selected timeline fills the screen."];
    [self addBindingWithType:@"RANDOM" shortcut:@"\u21E7R" scope:3 tooltip:@"Insert random effects."];
    [self addBindingWithType:@"SAVEAS_SEQUENCE" shortcut:@"\u2318\u21E7S" scope:3 tooltip:@"Save the current sequence to a new file."];
    [self addBindingWithType:@"SAVE_SEQUENCE" shortcut:@"" scope:3 tooltip:@"Save the current sequence."];
    [self addBindingWithType:@"EFFECT_SETTINGS_TOGGLE" shortcut:@"\u2318F1" scope:3 tooltip:@"Toggle display of the effect settings panel."];
    [self addBindingWithType:@"EFFECT_ASSIST_TOGGLE" shortcut:@"\u2318F8" scope:3 tooltip:@"Toggle display of the effect assist panel."];
    [self addBindingWithType:@"COLOR_TOGGLE" shortcut:@"\u2318F2" scope:3 tooltip:@"Toggle display of the color panel."];
    [self addBindingWithType:@"LAYER_SETTING_TOGGLE" shortcut:@"\u2318F3" scope:3 tooltip:@"Toggle display of the layer settings panel."];
    [self addBindingWithType:@"LAYER_BLENDING_TOGGLE" shortcut:@"\u2318F4" scope:3 tooltip:@"Toggle display of the layer blending panel."];
    [self addBindingWithType:@"MODEL_PREVIEW_TOGGLE" shortcut:@"\u2318F5" scope:3 tooltip:@"Toggle display of the model preview panel."];
    [self addBindingWithType:@"HOUSE_PREVIEW_TOGGLE" shortcut:@"\u2318F6" scope:3 tooltip:@"Toggle display of the house preview panel."];
    [self addBindingWithType:@"EFFECTS_TOGGLE" shortcut:@"\u2318F9" scope:3 tooltip:@"Toggle display of the effect dropper panel."];
    [self addBindingWithType:@"DISPLAY_ELEMENTS_TOGGLE" shortcut:@"\u2318F7" scope:3 tooltip:@"Toggle display of the display elements panel."];
    [self addBindingWithType:@"JUKEBOX_TOGGLE" shortcut:@"\u2318\u2325F8" scope:3 tooltip:@"Toggle display of the jukebox panel."];
    [self addBindingWithType:@"LOCK_EFFECT" shortcut:@"\u2318L" scope:3 tooltip:@"Lock the selected effects."];
    [self addBindingWithType:@"UNLOCK_EFFECT" shortcut:@"\u2318U" scope:3 tooltip:@"Unlock the selected effects."];
    [self addBindingWithType:@"MARK_SPOT" shortcut:@"\u2318." scope:3 tooltip:@"Mark the current spot in the sequencer so you can return to it."];
    [self addBindingWithType:@"RETURN_TO_SPOT" shortcut:@"\u2318/" scope:3 tooltip:@"Return to the previously marked spot in the sequencer."];
    [self addBindingWithType:@"EFFECT_DESCRIPTION" shortcut:@"" scope:3 tooltip:@"Open the effect description dialog."];
    [self addBindingWithType:@"EFFECT_ALIGN_START" shortcut:@"" scope:3 tooltip:@"Align the selected effects to have the same start times."];
    [self addBindingWithType:@"EFFECT_ALIGN_END" shortcut:@"" scope:3 tooltip:@"Align the selected effects to have the same end times."];
    [self addBindingWithType:@"EFFECT_ALIGN_BOTH" shortcut:@"" scope:3 tooltip:@"Align the selected effects to have the same start and end times."];
    [self addBindingWithType:@"INSERT_LAYER_ABOVE" shortcut:@"\u2318\u21E7I" scope:3 tooltip:@"Insert a sequencing layer above the current row."];
    [self addBindingWithType:@"INSERT_LAYER_BELOW" shortcut:@"\u2318\u21E7A" scope:3 tooltip:@"Insert a sequencing layer below the current row."];
    [self addBindingWithType:@"TOGGLE_ELEMENT_EXPAND" shortcut:@"\u2318\u21E7X" scope:3 tooltip:@"Expand the current element."];
    [self addBindingWithType:@"SELECT_ALL" shortcut:@"\u2318\u2325A" scope:3 tooltip:@"Select all effects and timing marks."];
    [self addBindingWithType:@"SELECT_ALL_NO_TIMING" shortcut:@"\u2318A" scope:3 tooltip:@"Select all effects but not timing marks."];
    [self addBindingWithType:@"SHOW_PRESETS" shortcut:@"" scope:3 tooltip:@"Show the effect presets panel."];
    [self addBindingWithType:@"SEARCH_TOGGLE" shortcut:@"\u2318F11" scope:3 tooltip:@"Toggle display of the effect search panel."];
    [self addBindingWithType:@"PERSPECTIVES_TOGGLE" shortcut:@"\u2318F12" scope:3 tooltip:@"Toggle display of the perspectives panel."];
    [self addBindingWithType:@"EFFECT_UPDATE" shortcut:@"F5" scope:3 tooltip:@"Apply the current effect settings to all selected effects."];
    [self addBindingWithType:@"COLOR_UPDATE" shortcut:@"\u21E7F5" scope:3 tooltip:@"Apply the current colors to all selected effects."];
    [self addBindingWithType:@"SET_COLOR_1" shortcut:@"\u23181" scope:3 tooltip:@"Set selected effects to palette color 1 (white)."];
    [self addBindingWithType:@"SET_COLOR_2" shortcut:@"\u23182" scope:3 tooltip:@"Set selected effects to palette color 2 (red)."];
    [self addBindingWithType:@"SET_COLOR_3" shortcut:@"\u23183" scope:3 tooltip:@"Set selected effects to palette color 3 (green)."];
    [self addBindingWithType:@"SET_COLOR_4" shortcut:@"\u23184" scope:3 tooltip:@"Set selected effects to palette color 4 (blue)."];
    [self addBindingWithType:@"SET_COLOR_5" shortcut:@"\u23185" scope:3 tooltip:@"Set selected effects to palette color 5 (yellow)."];
    [self addBindingWithType:@"SET_COLOR_6" shortcut:@"\u23186" scope:3 tooltip:@"Set selected effects to palette color 6 (black)."];
    [self addBindingWithType:@"SET_COLOR_7" shortcut:@"\u23187" scope:3 tooltip:@"Set selected effects to palette color 7 (cyan)."];
    [self addBindingWithType:@"SET_COLOR_8" shortcut:@"\u23188" scope:3 tooltip:@"Set selected effects to palette color 8 (magenta)."];
    [self addBindingWithType:@"CANCEL_RENDER" shortcut:@"Escape" scope:3 tooltip:@"Cancel current rendering activity."];
    [self addBindingWithType:@"TOGGLE_RENDER" shortcut:@"" scope:3 tooltip:@"Toggle background rendering."];
    [self addBindingWithType:@"PRESETS_TOGGLE" shortcut:@"\u2318F10" scope:3 tooltip:@"Toggle display of the presets panel."];
    [self addBindingWithType:@"APPLY_SELECTED_PRESET" shortcut:@"" scope:3 tooltip:@"Apply the currently selected preset in the presets panel."];
    [self addBindingWithType:@"VALUECURVES_TOGGLE" shortcut:@"\u2325F12" scope:3 tooltip:@"Toggle display of the value curves dropper panel."];
    [self addBindingWithType:@"COLOR_DROPPER_TOGGLE" shortcut:@"\u2325F11" scope:3 tooltip:@"Toggle display of the color dropper panel."];
    [self addBindingWithType:@"AUDIO_FULL_SPEED" shortcut:@"" scope:3 tooltip:@"Playback audio at normal speed."];
    [self addBindingWithType:@"AUDIO_S_1_2_SPEED" shortcut:@"" scope:3 tooltip:@"Playback audio at 1/2 speed."];
    [self addBindingWithType:@"AUDIO_S_1_4_SPEED" shortcut:@"" scope:3 tooltip:@"Playback audio at 1/4 speed."];
    [self addBindingWithType:@"MODEL_TOGGLE" shortcut:@"" scope:3 tooltip:@"Toggle rendering of the selected model."];
    [self addBindingWithType:@"EFFECT_TOGGLE" shortcut:@"" scope:3 tooltip:@"Toggle rendering of the selected effects."];
    [self addBindingWithType:@"FILL_REGION_TIMING" shortcut:@"" scope:3 tooltip:@"Fill the current song region with copies of the selected effect at each timing mark."];
    [self addBindingWithType:@"FILL_REGION_TIMING_SYMBOL" shortcut:@"" scope:3 tooltip:@"Fill the current song region with symbol-linked copies of the selected effect at each timing mark."];

    // Layout scope bindings
    [self addBindingWithType:@"LOCK_MODEL" shortcut:@"\u2318L" scope:2 tooltip:@"Lock the selected models."];
    [self addBindingWithType:@"UNLOCK_MODEL" shortcut:@"\u2318U" scope:2 tooltip:@"Unlock the selected models."];
    [self addBindingWithType:@"GROUP_MODELS" shortcut:@"\u2318G" scope:2 tooltip:@"Create a group from the selected models."];
    [self addBindingWithType:@"WIRING_VIEW" shortcut:@"" scope:2 tooltip:@"Display the wiring view for the selected model."];
    [self addBindingWithType:@"EXPORT_MODEL_CAD" shortcut:@"" scope:2 tooltip:@"Export the selected model as a DXF or STL or VRML File."];
    [self addBindingWithType:@"EXPORT_LAYOUT_DXF" shortcut:@"" scope:2 tooltip:@"Export the default layout as a DXF File."];
    [self addBindingWithType:@"NODE_LAYOUT" shortcut:@"" scope:2 tooltip:@"Display the node layout for the selected model."];
    [self addBindingWithType:@"SAVE_LAYOUT" shortcut:@"" scope:2 tooltip:@"Save the layout tab."];
    [self addBindingWithType:@"SELECT_ALL_MODELS" shortcut:@"\u2318A" scope:2 tooltip:@"Select all models."];
    [self addBindingWithType:@"MODEL_ALIGN_TOP" shortcut:@"" scope:2 tooltip:@"Align the selected models to the top edge."];
    [self addBindingWithType:@"MODEL_ALIGN_BOTTOM" shortcut:@"" scope:2 tooltip:@"Align the selected models to the bottom edge."];
    [self addBindingWithType:@"MODEL_ALIGN_LEFT" shortcut:@"" scope:2 tooltip:@"Align the selected models to the left edge."];
    [self addBindingWithType:@"MODEL_ALIGN_RIGHT" shortcut:@"" scope:2 tooltip:@"Align the selected models to the right edge."];
    [self addBindingWithType:@"MODEL_ALIGN_CENTER_VERT" shortcut:@"" scope:2 tooltip:@"Align the selected models to be vertically centered."];
    [self addBindingWithType:@"MODEL_ALIGN_CENTER_HORIZ" shortcut:@"" scope:2 tooltip:@"Align the selected models to be horizontally centered."];
    [self addBindingWithType:@"MODEL_DISTRIBUTE_HORIZ" shortcut:@"" scope:2 tooltip:@"Distribute the selected models horizontally."];
    [self addBindingWithType:@"MODEL_DISTRIBUTE_VERT" shortcut:@"" scope:2 tooltip:@"Distribute the selected models vertically."];
    [self addBindingWithType:@"MODEL_FLIP_HORIZ" shortcut:@"" scope:2 tooltip:@"Flip the selected models horizontally."];
    [self addBindingWithType:@"MODEL_FLIP_VERT" shortcut:@"" scope:2 tooltip:@"Flip the selected models vertically."];
    [self addBindingWithType:@"MODEL_SUBMODELS" shortcut:@"" scope:2 tooltip:@"Edit model submodels."];
    [self addBindingWithType:@"MODEL_FACES" shortcut:@"" scope:2 tooltip:@"Edit model faces."];
    [self addBindingWithType:@"MODEL_STATES" shortcut:@"" scope:2 tooltip:@"Edit model states."];
    [self addBindingWithType:@"MODEL_MODELDATA" shortcut:@"" scope:2 tooltip:@"Edit custom model data."];

    // Effect shortcuts (Sequence scope)
    [self addBindingWithType:@"EFFECT" shortcut:@"O" scope:3 tooltip:@"On effect (100% brightness)."];
    [self addBindingWithType:@"EFFECT" shortcut:@"U" scope:3 tooltip:@"On effect (ramp up)."];
    [self addBindingWithType:@"EFFECT" shortcut:@"D" scope:3 tooltip:@"On effect (ramp down)."];
    [self addBindingWithType:@"EFFECT" shortcut:@"M" scope:3 tooltip:@"Morph effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"C" scope:3 tooltip:@"Curtain effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"I" scope:3 tooltip:@"Circles effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"B" scope:3 tooltip:@"Bars effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"Y" scope:3 tooltip:@"Butterfly effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"F" scope:3 tooltip:@"Fire effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"G" scope:3 tooltip:@"Garlands effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"P" scope:3 tooltip:@"Pinwheel effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"R" scope:3 tooltip:@"Ripple effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"X" scope:3 tooltip:@"Text effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"\u21E7S" scope:3 tooltip:@"Spirals effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"W" scope:3 tooltip:@"Color Wash effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"N" scope:3 tooltip:@"Snowflakes effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"\u21E7O" scope:3 tooltip:@"Off effect."];
    [self addBindingWithType:@"EFFECT" shortcut:@"\u21E7F" scope:3 tooltip:@"Fan effect."];

    // Sort by action name
    [self.allBindings sortUsingComparator:^NSComparisonResult(XLKeyBindingItem *item1, XLKeyBindingItem *item2) {
        return [item1.actionName compare:item2.actionName options:NSCaseInsensitiveSearch];
    }];
}

- (void)addBindingWithType:(NSString *)type
                  shortcut:(NSString *)shortcut
                     scope:(NSInteger)scope
                   tooltip:(NSString *)tooltip {
    BOOL disabled = (shortcut.length == 0);
    XLKeyBindingItem *item = [XLKeyBindingItem itemWithActionType:type
                                                         shortcut:disabled ? @"Not Assigned" : shortcut
                                                            scope:scope
                                                          tooltip:tooltip
                                                       isDisabled:disabled];
    [self.allBindings addObject:item];
}

- (void)reloadBindings {
    [self loadDefaultBindings];
    [self applyFilters];
}

#pragma mark - Filtering

- (void)applyFilters {
    [self.filteredBindings removeAllObjects];

    for (XLKeyBindingItem *item in self.allBindings) {
        // Apply scope filter
        // currentScopeFilter: -1 = show all scopes
        //                     0 = show only "All" scope (scope value 0)
        //                     1 = Setup only
        //                     2 = Layout only
        //                     3 = Sequence only
        //                     4 = "Everywhere" - bindings that work in all scopes (scope value 0)
        if (self.currentScopeFilter >= 0) {
            if (self.currentScopeFilter == 4) {
                // "Everywhere" filter - show only scope 0 (All)
                if (item.scopeValue != 0) continue;
            } else if (self.currentScopeFilter == 0) {
                // "All" filter - show everything (no scope filtering)
            } else {
                // Specific scope filter (1=Setup, 2=Layout, 3=Sequence)
                if (item.scopeValue != self.currentScopeFilter) continue;
            }
        }

        // Apply text search filter
        if (self.currentSearchText.length > 0) {
            NSString *searchLower = self.currentSearchText.lowercaseString;
            BOOL matches = NO;

            if ([item.actionName.lowercaseString containsString:searchLower]) matches = YES;
            else if ([item.shortcut.lowercaseString containsString:searchLower]) matches = YES;
            else if ([item.tooltip.lowercaseString containsString:searchLower]) matches = YES;
            else if ([item.actionType.lowercaseString containsString:searchLower]) matches = YES;

            if (!matches) continue;
        }

        [self.filteredBindings addObject:item];
    }

    [self.bindingsTableView reloadData];
}

#pragma mark - Actions

- (IBAction)scopeFilterChanged:(id)sender {
    NSInteger selectedSegment = self.scopeFilter.selectedSegment;

    // Map segment to scope filter value
    // Segment 0 = "All" (show everything, no filter)
    // Segment 1 = "Setup" (scope 1)
    // Segment 2 = "Layout" (scope 2)
    // Segment 3 = "Sequence" (scope 3)
    // Segment 4 = "Everywhere" (scope 0 only)

    if (selectedSegment == 0) {
        self.currentScopeFilter = -1;  // Show all
    } else if (selectedSegment == 4) {
        self.currentScopeFilter = 4;   // "Everywhere" = only scope 0
    } else {
        self.currentScopeFilter = selectedSegment;  // 1, 2, or 3
    }

    [self applyFilters];
}

- (IBAction)searchTextChanged:(id)sender {
    self.currentSearchText = self.searchField.stringValue;
    [self applyFilters];
}

- (IBAction)resetToDefaults:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Reset to Default Shortcuts?";
    alert.informativeText = @"This will reset all keyboard shortcuts to their default values. Any custom bindings in key_bindings.xml will be overwritten.";
    [alert addButtonWithTitle:@"Reset"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            // Delete the key_bindings.xml file if it exists
            if (self.showFolderPath.length > 0) {
                NSString *keyBindingsPath = [self.showFolderPath stringByAppendingPathComponent:@"key_bindings.xml"];
                NSError *error = nil;
                if ([[NSFileManager defaultManager] fileExistsAtPath:keyBindingsPath]) {
                    [[NSFileManager defaultManager] removeItemAtPath:keyBindingsPath error:&error];
                    if (error) {
                        NSLog(@"Failed to remove key_bindings.xml: %@", error);
                    }
                }
            }

            // Reload defaults
            [self loadDefaultBindings];
            [self applyFilters];

            // Post notification that bindings were reset
            [[NSNotificationCenter defaultCenter] postNotificationName:@"XLKeyBindingsDidResetNotification" object:self];
        }
    }];
}

#pragma mark - Notifications

- (void)showFolderDidChange:(NSNotification *)notification {
    NSString *newPath = notification.userInfo[@"path"];
    if (newPath) {
        self.showFolderPath = newPath;
        [self reloadBindings];
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.filteredBindings.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.filteredBindings.count) return nil;

    XLKeyBindingItem *item = self.filteredBindings[row];
    NSString *identifier = tableColumn.identifier;

    NSTextField *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = identifier;
        cell.lineBreakMode = NSLineBreakByTruncatingTail;
    }

    if ([identifier isEqualToString:@"action"]) {
        cell.stringValue = item.actionName;
        cell.toolTip = item.tooltip.length > 0 ? item.tooltip : item.actionType;
    }
    else if ([identifier isEqualToString:@"shortcut"]) {
        cell.stringValue = item.shortcut;
        if (item.isDisabled) {
            cell.textColor = [NSColor tertiaryLabelColor];
        } else {
            cell.textColor = [NSColor labelColor];
        }
    }
    else if ([identifier isEqualToString:@"scope"]) {
        cell.stringValue = item.scopeName;
        cell.textColor = [NSColor secondaryLabelColor];
    }

    return cell;
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation {
    if (row < 0 || row >= (NSInteger)self.filteredBindings.count) return nil;

    XLKeyBindingItem *item = self.filteredBindings[row];
    return item.tooltip.length > 0 ? item.tooltip : nil;
}

#pragma mark - NSSearchFieldDelegate

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.searchField) {
        [self searchTextChanged:self.searchField];
    }
}

@end
