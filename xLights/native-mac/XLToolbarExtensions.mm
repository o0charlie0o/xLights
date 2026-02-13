/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLToolbarExtensions.h"

// Toolbar item identifiers
NSToolbarItemIdentifier const XLToolbarItemTransportGroup = @"XLToolbarItemTransportGroup";
NSToolbarItemIdentifier const XLToolbarItemSeekStart = @"XLToolbarItemSeekStart";
NSToolbarItemIdentifier const XLToolbarItemSeekEnd = @"XLToolbarItemSeekEnd";
NSToolbarItemIdentifier const XLToolbarItemToolMode = @"XLToolbarItemToolMode";
NSToolbarItemIdentifier const XLToolbarItemZoom = @"XLToolbarItemZoom";
NSToolbarItemIdentifier const XLToolbarItemSearch = @"XLToolbarItemSearch";
NSToolbarItemIdentifier const XLToolbarItemPreview = @"XLToolbarItemPreview";

@implementation XLToolbarBuilder

+ (NSToolbarItem *)createTransportGroupWithTarget:(id)target {
    NSToolbarItemGroup *group = [[NSToolbarItemGroup alloc] initWithItemIdentifier:XLToolbarItemTransportGroup];
    group.paletteLabel = @"Transport Controls";
    group.label = @"Transport";

    NSToolbarItem *seekStartItem = [[NSToolbarItem alloc] initWithItemIdentifier:XLToolbarItemSeekStart];
    seekStartItem.image = [NSImage imageWithSystemSymbolName:@"backward.end.fill" accessibilityDescription:@"Seek to Start"];
    seekStartItem.action = @selector(seekToStart:);
    seekStartItem.target = target;

    NSToolbarItem *playItem = [[NSToolbarItem alloc] initWithItemIdentifier:@"Play"];
    playItem.image = [NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:@"Play"];
    playItem.action = @selector(playSequence:);
    playItem.target = target;

    NSToolbarItem *pauseItem = [[NSToolbarItem alloc] initWithItemIdentifier:@"Pause"];
    pauseItem.image = [NSImage imageWithSystemSymbolName:@"pause.fill" accessibilityDescription:@"Pause"];
    pauseItem.action = @selector(pauseSequence:);
    pauseItem.target = target;

    NSToolbarItem *stopItem = [[NSToolbarItem alloc] initWithItemIdentifier:@"Stop"];
    stopItem.image = [NSImage imageWithSystemSymbolName:@"stop.fill" accessibilityDescription:@"Stop"];
    stopItem.action = @selector(stopSequence:);
    stopItem.target = target;

    NSToolbarItem *seekEndItem = [[NSToolbarItem alloc] initWithItemIdentifier:XLToolbarItemSeekEnd];
    seekEndItem.image = [NSImage imageWithSystemSymbolName:@"forward.end.fill" accessibilityDescription:@"Seek to End"];
    seekEndItem.action = @selector(seekToEnd:);
    seekEndItem.target = target;

    group.subitems = @[seekStartItem, playItem, pauseItem, stopItem, seekEndItem];
    return group;
}

+ (NSToolbarItem *)createToolModeControlWithTarget:(id)target {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:XLToolbarItemToolMode];

    NSSegmentedControl *control = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, 0, 280, 28)];
    control.segmentStyle = NSSegmentStyleTexturedRounded;
    control.segmentCount = 4;
    [control setLabel:@"Select" forSegment:0];
    [control setLabel:@"Effects Paint" forSegment:1];
    [control setLabel:@"Draw" forSegment:2];
    [control setLabel:@"Timing" forSegment:3];
    [control setWidth:70 forSegment:0];
    [control setWidth:70 forSegment:1];
    [control setWidth:70 forSegment:2];
    [control setWidth:70 forSegment:3];
    control.selectedSegment = 0;
    control.target = target;
    control.action = @selector(toolModeChanged:);

    item.label = @"Tool Mode";
    item.paletteLabel = @"Tool Mode";
    item.toolTip = @"Select editing tool mode";
    item.view = control;
    item.minSize = NSMakeSize(280, 28);
    item.maxSize = NSMakeSize(280, 28);

    return item;
}

+ (NSToolbarItem *)createZoomControlWithTarget:(id)target {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:XLToolbarItemZoom];

    NSSegmentedControl *control = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, 0, 100, 28)];
    control.segmentStyle = NSSegmentStyleTexturedRounded;
    control.segmentCount = 3;
    [control setImage:[NSImage imageWithSystemSymbolName:@"minus.magnifyingglass" accessibilityDescription:@"Zoom Out"] forSegment:0];
    [control setImage:[NSImage imageWithSystemSymbolName:@"plus.magnifyingglass" accessibilityDescription:@"Zoom In"] forSegment:1];
    [control setImage:[NSImage imageWithSystemSymbolName:@"arrow.up.left.and.down.right.magnifyingglass" accessibilityDescription:@"Zoom to Fit"] forSegment:2];
    [control setWidth:33 forSegment:0];
    [control setWidth:33 forSegment:1];
    [control setWidth:34 forSegment:2];
    control.trackingMode = NSSegmentSwitchTrackingMomentary;
    control.target = target;
    control.action = @selector(zoomControlChanged:);

    item.label = @"Zoom";
    item.paletteLabel = @"Zoom Controls";
    item.toolTip = @"Zoom in/out/fit (⌘+/⌘-/⌘0)";
    item.view = control;
    item.minSize = NSMakeSize(100, 28);
    item.maxSize = NSMakeSize(100, 28);

    return item;
}

+ (NSToolbarItem *)createSearchFieldWithTarget:(id)target delegate:(id<NSSearchFieldDelegate>)delegate {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:XLToolbarItemSearch];

    NSSearchField *searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
    searchField.placeholderString = @"Search effects and models";
    searchField.delegate = delegate;
    searchField.target = target;
    searchField.action = @selector(searchFieldChanged:);

    item.label = @"Search";
    item.paletteLabel = @"Search";
    item.toolTip = @"Search for effects and models (⌘F)";
    item.view = searchField;
    item.minSize = NSMakeSize(150, 22);
    item.maxSize = NSMakeSize(300, 22);

    return item;
}

+ (NSToolbarItem *)createPreviewToggleWithTarget:(id)target {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:XLToolbarItemPreview];
    item.label = @"Preview";
    item.paletteLabel = @"Show/Hide Preview";
    item.toolTip = @"Toggle preview window (⌘⇧P)";
    item.image = [NSImage imageWithSystemSymbolName:@"eye.fill" accessibilityDescription:@"Preview"];
    item.action = @selector(togglePreview:);
    item.target = target;
    return item;
}

@end

@implementation XLMenuBuilder

+ (void)buildMenuBarForApplication:(NSApplication *)app target:(id)target {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    [self addApplicationMenuTo:mainMenu target:target];
    [self addFileMenuTo:mainMenu target:target];
    [self addEditMenuTo:mainMenu target:target];
    [self addViewMenuTo:mainMenu target:target];
    [self addSequenceMenuTo:mainMenu target:target];
    [self addModelMenuTo:mainMenu target:target];
    [self addEffectMenuTo:mainMenu target:target];
    [self addAudioMenuTo:mainMenu target:target];
    [self addToolsMenuTo:mainMenu target:target];
    [self addWindowMenuTo:mainMenu app:app];
    [self addHelpMenuTo:mainMenu target:target];

    [app setMainMenu:mainMenu];
}

+ (void)addApplicationMenuTo:(NSMenu *)mainMenu target:(id)target {
    NSMenuItem *appMenuItem = [mainMenu addItemWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"xLights"];

    [appMenu addItemWithTitle:@"About xLights" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Preferences…" action:@selector(showPreferences:) keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Services" action:nil keyEquivalent:@""].submenu = [NSApp servicesMenu];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide xLights" action:@selector(hide:) keyEquivalent:@"h"];
    [[appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"]
        setKeyEquivalentModifierMask:NSEventModifierFlagOption | NSEventModifierFlagCommand];
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit xLights" action:@selector(terminate:) keyEquivalent:@"q"];

    appMenuItem.submenu = appMenu;
}

+ (void)addFileMenuTo:(NSMenu *)mainMenu target:(id)target {
    NSMenuItem *fileMenuItem = [mainMenu addItemWithTitle:@"File" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];

    [fileMenu addItemWithTitle:@"New Sequence" action:@selector(newSequence:) keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"Open Sequence…" action:@selector(openSequence:) keyEquivalent:@"o"];

    NSMenuItem *recentItem = [fileMenu addItemWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
    NSMenu *recentMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    [recentMenu performSelector:@selector(_setMenuName:) withObject:@"NSRecentDocumentsMenu"];
    [recentMenu addItemWithTitle:@"Clear Menu" action:@selector(clearRecentDocuments:) keyEquivalent:@""];
    recentItem.submenu = recentMenu;

    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    [fileMenu addItemWithTitle:@"Save" action:@selector(saveDocument:) keyEquivalent:@"s"];
    [fileMenu addItemWithTitle:@"Save As…" action:@selector(saveDocumentAs:) keyEquivalent:@"S"];
    [fileMenu addItemWithTitle:@"Revert to Saved…" action:@selector(revertDocumentToSaved:) keyEquivalent:@""];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *importItem = [fileMenu addItemWithTitle:@"Import" action:nil keyEquivalent:@""];
    NSMenu *importMenu = [[NSMenu alloc] initWithTitle:@"Import"];
    [importMenu addItemWithTitle:@"Import Effects…" action:@selector(importEffects:) keyEquivalent:@""];
    [importMenu addItemWithTitle:@"Import Models…" action:@selector(importModels:) keyEquivalent:@""];
    [importMenu addItemWithTitle:@"Import LOR S5 Models/Groups…" action:@selector(importLORS5Models:) keyEquivalent:@""];
    [importMenu addItemWithTitle:@"Import Models from RGB Effects…" action:@selector(importModelsFromRGBEffects:) keyEquivalent:@""];
    [importMenu addItemWithTitle:@"Import Controllers…" action:@selector(importControllers:) keyEquivalent:@""];
    importItem.submenu = importMenu;

    NSMenuItem *exportItem = [fileMenu addItemWithTitle:@"Export" action:nil keyEquivalent:@""];
    NSMenu *exportMenu = [[NSMenu alloc] initWithTitle:@"Export"];
    [exportMenu addItemWithTitle:@"Export Effects…" action:@selector(exportEffects:) keyEquivalent:@""];
    [exportMenu addItemWithTitle:@"Export Models…" action:@selector(exportModels:) keyEquivalent:@""];
    [exportMenu addItemWithTitle:@"Export Video…" action:@selector(exportVideo:) keyEquivalent:@""];
    exportItem.submenu = exportMenu;

    [fileMenu addItem:[NSMenuItem separatorItem]];

    [fileMenu addItemWithTitle:@"Select Show Folder…" action:@selector(selectShowFolder:) keyEquivalent:@""];

    NSMenuItem *recentFoldersItem = [fileMenu addItemWithTitle:@"Recent Show Folders" action:nil keyEquivalent:@""];
    NSMenu *recentFoldersMenu = [[NSMenu alloc] initWithTitle:@"Recent Show Folders"];
    [recentFoldersMenu addItemWithTitle:@"(No Recent Folders)" action:nil keyEquivalent:@""].enabled = NO;
    recentFoldersItem.submenu = recentFoldersMenu;

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *backupItem = [fileMenu addItemWithTitle:@"Backup" action:@selector(backupShowFolder:) keyEquivalent:@""];
    backupItem.keyEquivalent = [NSString stringWithFormat:@"%C", (unichar)NSF10FunctionKey];
    backupItem.keyEquivalentModifierMask = 0;

    [fileMenu addItemWithTitle:@"Restore Backup…" action:@selector(restoreBackup:) keyEquivalent:@""];

    NSMenuItem *altBackupItem = [fileMenu addItemWithTitle:@"Alternate Backup…" action:@selector(alternateBackup:) keyEquivalent:@""];
    altBackupItem.keyEquivalent = [NSString stringWithFormat:@"%C", (unichar)NSF11FunctionKey];
    altBackupItem.keyEquivalentModifierMask = 0;

    [fileMenu addItem:[NSMenuItem separatorItem]];

    [fileMenu addItemWithTitle:@"Sequence Settings…" action:@selector(showSequenceSettings:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Key Bindings…" action:@selector(showKeyBindings:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Export House Preview Video…" action:@selector(exportHousePreviewVideo:) keyEquivalent:@""];

    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Page Setup…" action:@selector(runPageLayout:) keyEquivalent:@"P"];
    [fileMenu addItemWithTitle:@"Print…" action:@selector(printDocument:) keyEquivalent:@"p"];

    fileMenuItem.submenu = fileMenu;
}

+ (void)addEditMenuTo:(NSMenu *)mainMenu target:(id)target {
    NSMenuItem *editMenuItem = [mainMenu addItemWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];

    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Delete" action:@selector(delete:) keyEquivalent:@""];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];

    [editMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *findItem = [editMenu addItemWithTitle:@"Find" action:nil keyEquivalent:@""];
    NSMenu *findMenu = [[NSMenu alloc] initWithTitle:@"Find"];
    [findMenu addItemWithTitle:@"Find…" action:@selector(performFindPanelAction:) keyEquivalent:@"f"].tag = NSTextFinderActionShowFindInterface;
    [findMenu addItemWithTitle:@"Find Next" action:@selector(performFindPanelAction:) keyEquivalent:@"g"].tag = NSTextFinderActionNextMatch;
    [findMenu addItemWithTitle:@"Find Previous" action:@selector(performFindPanelAction:) keyEquivalent:@"G"].tag = NSTextFinderActionPreviousMatch;
    [findMenu addItemWithTitle:@"Use Selection for Find" action:@selector(performFindPanelAction:) keyEquivalent:@"e"].tag = NSTextFinderActionSetSearchString;
    findItem.submenu = findMenu;

    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Effect Symbol Library…" action:@selector(showSymbolLibrary:) keyEquivalent:@""];
    [editMenu addItemWithTitle:@"Convert All Symbols to Effects" action:@selector(convertAllSymbolsToEffects:) keyEquivalent:@""];

    editMenuItem.submenu = editMenu;
}

+ (void)addViewMenuTo:(NSMenu *)mainMenu target:(id)target {
    NSMenuItem *viewMenuItem = [mainMenu addItemWithTitle:@"View" action:nil keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];

    [viewMenu addItemWithTitle:@"Show Inspector" action:@selector(toggleInspector:) keyEquivalent:@"i"];
    [viewMenu addItemWithTitle:@"Show Bottom Panel" action:@selector(toggleBottomPanel:) keyEquivalent:@"b"];
    [viewMenu addItemWithTitle:@"Show Preview" action:@selector(togglePreview:) keyEquivalent:@"p"]
        .keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [viewMenu addItemWithTitle:@"Show Stems Panel" action:@selector(toggleStemsPanel:) keyEquivalent:@""];
    [viewMenu addItemWithTitle:@"Show Song Regions in Grid" action:@selector(toggleSongRegionOverlay:) keyEquivalent:@"r"]
        .keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
    [viewMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];
    [viewMenu addItemWithTitle:@"Zoom to Fit" action:@selector(zoomToFit:) keyEquivalent:@"0"];

    [viewMenu addItem:[NSMenuItem separatorItem]];

    // --- Windows submenu (panel visibility toggles) ---
    NSMenuItem *windowsItem = [viewMenu addItemWithTitle:@"Windows" action:nil keyEquivalent:@""];
    NSMenu *windowsMenu = [[NSMenu alloc] initWithTitle:@"Windows"];

    NSMenuItem *displayElementsItem = [windowsMenu addItemWithTitle:@"Display Elements" action:@selector(toggleDisplayElements:) keyEquivalent:@""];
    displayElementsItem.state = NSControlStateValueOff;

    NSMenuItem *modelPreviewItem = [windowsMenu addItemWithTitle:@"Model Preview" action:@selector(toggleModelPreview:) keyEquivalent:@""];
    modelPreviewItem.state = NSControlStateValueOff;

    NSMenuItem *housePreviewItem = [windowsMenu addItemWithTitle:@"House Preview" action:@selector(toggleHousePreview:) keyEquivalent:@""];
    housePreviewItem.state = NSControlStateValueOff;

    NSMenuItem *effectSettingsItem = [windowsMenu addItemWithTitle:@"Effect Settings" action:@selector(toggleEffectSettings:) keyEquivalent:@""];
    effectSettingsItem.state = NSControlStateValueOff;

    NSMenuItem *colorsItem = [windowsMenu addItemWithTitle:@"Colors" action:@selector(toggleColors:) keyEquivalent:@""];
    colorsItem.state = NSControlStateValueOff;

    NSMenuItem *layerBlendingItem = [windowsMenu addItemWithTitle:@"Layer Blending" action:@selector(toggleLayerBlending:) keyEquivalent:@""];
    layerBlendingItem.state = NSControlStateValueOff;

    NSMenuItem *layerSettingsItem = [windowsMenu addItemWithTitle:@"Layer Settings" action:@selector(toggleLayerSettings:) keyEquivalent:@""];
    layerSettingsItem.state = NSControlStateValueOff;

    NSMenuItem *effectDropperItem = [windowsMenu addItemWithTitle:@"Effect Dropper" action:@selector(toggleEffectDropper:) keyEquivalent:@""];
    effectDropperItem.state = NSControlStateValueOff;

    NSMenuItem *valueCurvesItem = [windowsMenu addItemWithTitle:@"Value Curves" action:@selector(toggleValueCurves:) keyEquivalent:@""];
    valueCurvesItem.state = NSControlStateValueOff;

    NSMenuItem *colorDropperItem = [windowsMenu addItemWithTitle:@"Color Dropper" action:@selector(toggleColorDropper:) keyEquivalent:@""];
    colorDropperItem.state = NSControlStateValueOff;

    NSMenuItem *effectAssistItem = [windowsMenu addItemWithTitle:@"Effect Assist" action:@selector(toggleEffectAssist:) keyEquivalent:@""];
    effectAssistItem.state = NSControlStateValueOff;

    NSMenuItem *selectEffectItem = [windowsMenu addItemWithTitle:@"Select Effect" action:@selector(toggleSelectEffect:) keyEquivalent:@""];
    selectEffectItem.state = NSControlStateValueOff;

    NSMenuItem *searchEffectsItem = [windowsMenu addItemWithTitle:@"Search Effects" action:@selector(toggleSearchEffects:) keyEquivalent:@""];
    searchEffectsItem.state = NSControlStateValueOff;

    NSMenuItem *videoPreviewItem = [windowsMenu addItemWithTitle:@"Video Preview" action:@selector(toggleVideoPreview:) keyEquivalent:@""];
    videoPreviewItem.state = NSControlStateValueOff;

    NSMenuItem *jukeboxItem = [windowsMenu addItemWithTitle:@"Jukebox" action:@selector(toggleJukebox:) keyEquivalent:@""];
    jukeboxItem.state = NSControlStateValueOff;

    NSMenuItem *findEffectDataItem = [windowsMenu addItemWithTitle:@"Find Effect Data" action:@selector(toggleFindEffectData:) keyEquivalent:@""];
    findEffectDataItem.state = NSControlStateValueOff;

    [windowsMenu addItem:[NSMenuItem separatorItem]];
    [windowsMenu addItemWithTitle:@"Dock All" action:@selector(dockAllPanels:) keyEquivalent:@""];
    [windowsMenu addItemWithTitle:@"Reset to Defaults" action:@selector(resetWindowLayout:) keyEquivalent:@""];

    windowsItem.submenu = windowsMenu;

    // --- Perspectives submenu ---
    NSMenuItem *perspectivesItem = [viewMenu addItemWithTitle:@"Perspectives" action:nil keyEquivalent:@""];
    NSMenu *perspectivesMenu = [[NSMenu alloc] initWithTitle:@"Perspectives"];

    [perspectivesMenu addItemWithTitle:@"Save Current" action:@selector(savePerspective:) keyEquivalent:@""];
    [perspectivesMenu addItemWithTitle:@"Save As New" action:@selector(saveAsNewPerspective:) keyEquivalent:@""];

    NSMenuItem *loadPerspectiveItem = [perspectivesMenu addItemWithTitle:@"Load Perspective" action:nil keyEquivalent:@""];
    NSMenu *loadPerspectiveMenu = [[NSMenu alloc] initWithTitle:@"Load Perspective"];
    NSMenuItem *noPerspectivesItem = [loadPerspectiveMenu addItemWithTitle:@"(No Saved Perspectives)" action:nil keyEquivalent:@""];
    noPerspectivesItem.enabled = NO;
    loadPerspectiveItem.submenu = loadPerspectiveMenu;

    [perspectivesMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *autoSavePerspectiveItem = [perspectivesMenu addItemWithTitle:@"Auto Save" action:@selector(toggleAutoSavePerspective:) keyEquivalent:@""];
    autoSavePerspectiveItem.state = NSControlStateValueOff;

    perspectivesItem.submenu = perspectivesMenu;

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"]
        .keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Customize Toolbar…" action:@selector(runToolbarCustomizationPalette:) keyEquivalent:@""];

    viewMenuItem.submenu = viewMenu;
}

+ (void)addSequenceMenuTo:(NSMenu *)mainMenu target:(id)target {
    NSMenuItem *sequenceMenuItem = [mainMenu addItemWithTitle:@"Sequence" action:nil keyEquivalent:@""];
    NSMenu *sequenceMenu = [[NSMenu alloc] initWithTitle:@"Sequence"];

    [sequenceMenu addItemWithTitle:@"Play" action:@selector(playSequence:) keyEquivalent:@" "];
    [sequenceMenu addItemWithTitle:@"Pause" action:@selector(pauseSequence:) keyEquivalent:@""];
    [sequenceMenu addItemWithTitle:@"Stop" action:@selector(stopSequence:) keyEquivalent:@"."];
    [sequenceMenu addItemWithTitle:@"Seek to Start" action:@selector(seekToStart:) keyEquivalent:@"["];
    [sequenceMenu addItemWithTitle:@"Seek to End" action:@selector(seekToEnd:) keyEquivalent:@"]"];

    [sequenceMenu addItem:[NSMenuItem separatorItem]];
    [sequenceMenu addItemWithTitle:@"Render All" action:@selector(renderAll:) keyEquivalent:@"r"];
    [sequenceMenu addItemWithTitle:@"Render Selected" action:@selector(renderSelected:) keyEquivalent:@"R"];

    [sequenceMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *timingItem = [sequenceMenu addItemWithTitle:@"Timing" action:nil keyEquivalent:@""];
    NSMenu *timingMenu = [[NSMenu alloc] initWithTitle:@"Timing"];
    [timingMenu addItemWithTitle:@"Add Timing Track…" action:@selector(addTimingTrack:) keyEquivalent:@""];
    [timingMenu addItemWithTitle:@"Import Timing…" action:@selector(importTiming:) keyEquivalent:@""];
    [timingMenu addItemWithTitle:@"Generate Timing from Audio…" action:@selector(generateTiming:) keyEquivalent:@""];
    timingItem.submenu = timingMenu;

    [sequenceMenu addItem:[NSMenuItem separatorItem]];
    [sequenceMenu addItemWithTitle:@"Sequence Properties…" action:@selector(showSequenceProperties:) keyEquivalent:@""];

    sequenceMenuItem.submenu = sequenceMenu;
}

+ (void)addModelMenuTo:(NSMenu *)mainMenu target:(id)target {
    NSMenuItem *modelMenuItem = [mainMenu addItemWithTitle:@"Model" action:nil keyEquivalent:@""];
    NSMenu *modelMenu = [[NSMenu alloc] initWithTitle:@"Model"];

    [modelMenu addItemWithTitle:@"Add Model…" action:@selector(addModel:) keyEquivalent:@"m"];
    [modelMenu addItemWithTitle:@"Add Model Group…" action:@selector(addModelGroup:) keyEquivalent:@"M"];
    [modelMenu addItemWithTitle:@"Clone Model…" action:@selector(cloneModel:) keyEquivalent:@""];
    [modelMenu addItemWithTitle:@"Delete Model" action:@selector(deleteModel:) keyEquivalent:@""];

    [modelMenu addItem:[NSMenuItem separatorItem]];
    [modelMenu addItemWithTitle:@"Download Vendor Models…" action:@selector(downloadVendorModels:) keyEquivalent:@""];

    [modelMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *importModelItem = [modelMenu addItemWithTitle:@"Import Model…" action:@selector(importModels:) keyEquivalent:@"I"];
    importModelItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [modelMenu addItemWithTitle:@"Import LOR S5 Models/Groups…" action:@selector(importLORS5Models:) keyEquivalent:@""];
    [modelMenu addItemWithTitle:@"Import from RGB Effects…" action:@selector(importModelsFromRGBEffects:) keyEquivalent:@""];
    [modelMenu addItemWithTitle:@"Export Model…" action:@selector(exportModelToFile:) keyEquivalent:@""];

    [modelMenu addItem:[NSMenuItem separatorItem]];
    [modelMenu addItemWithTitle:@"Model Properties…" action:@selector(showModelProperties:) keyEquivalent:@""];
    [modelMenu addItemWithTitle:@"Edit Submodels…" action:@selector(editSubmodels:) keyEquivalent:@""];
    [modelMenu addItemWithTitle:@"Edit States…" action:@selector(editModelStates:) keyEquivalent:@""];

    [modelMenu addItem:[NSMenuItem separatorItem]];
    [modelMenu addItemWithTitle:@"Align Models…" action:@selector(alignModels:) keyEquivalent:@""];
    [modelMenu addItemWithTitle:@"Distribute Models…" action:@selector(distributeModels:) keyEquivalent:@""];

    modelMenuItem.submenu = modelMenu;
}

+ (void)addEffectMenuTo:(NSMenu *)mainMenu target:(id)target {
    NSMenuItem *effectMenuItem = [mainMenu addItemWithTitle:@"Effect" action:nil keyEquivalent:@""];
    NSMenu *effectMenu = [[NSMenu alloc] initWithTitle:@"Effect"];

    [effectMenu addItemWithTitle:@"Apply Effect…" action:@selector(applyEffect:) keyEquivalent:@"e"];
    [effectMenu addItemWithTitle:@"Copy Effect" action:@selector(copyEffect:) keyEquivalent:@""];
    [effectMenu addItemWithTitle:@"Paste Effect" action:@selector(pasteEffect:) keyEquivalent:@""];
    [effectMenu addItemWithTitle:@"Delete Effect" action:@selector(deleteEffect:) keyEquivalent:@""];

    [effectMenu addItem:[NSMenuItem separatorItem]];
    [effectMenu addItemWithTitle:@"Convert Effect Type…" action:@selector(convertEffectType:) keyEquivalent:@""];
    [effectMenu addItemWithTitle:@"Duplicate Effect" action:@selector(duplicateEffect:) keyEquivalent:@"d"];

    [effectMenu addItem:[NSMenuItem separatorItem]];
    [effectMenu addItemWithTitle:@"Fill Region from Timing" action:@selector(fillRegionFromTiming:) keyEquivalent:@""];
    [effectMenu addItemWithTitle:@"Fill Region from Timing as Symbol" action:@selector(fillRegionFromTimingAsSymbol:) keyEquivalent:@""];

    [effectMenu addItem:[NSMenuItem separatorItem]];
    [effectMenu addItemWithTitle:@"Effect Presets…" action:@selector(showEffectPresets:) keyEquivalent:@""];

    effectMenuItem.submenu = effectMenu;
}

+ (void)addWindowMenuTo:(NSMenu *)mainMenu app:(NSApplication *)app {
    NSMenuItem *windowMenuItem = [mainMenu addItemWithTitle:@"Window" action:nil keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];

    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];

    [app setWindowsMenu:windowMenu];
    windowMenuItem.submenu = windowMenu;
}

+ (void)addAudioMenuTo:(NSMenu *)mainMenu target:(id)target {
    NSMenuItem *audioMenuItem = [mainMenu addItemWithTitle:@"Audio" action:nil keyEquivalent:@""];
    NSMenu *audioMenu = [[NSMenu alloc] initWithTitle:@"Audio"];

    // Playback speed radio group
    NSMenuItem *fullSpeedItem = [audioMenu addItemWithTitle:@"Play Full Speed" action:@selector(setPlaybackSpeed:) keyEquivalent:@""];
    fullSpeedItem.tag = 100;
    fullSpeedItem.state = NSControlStateValueOn;

    NSMenuItem *speed15Item = [audioMenu addItemWithTitle:@"Play 1.5x Speed" action:@selector(setPlaybackSpeed:) keyEquivalent:@""];
    speed15Item.tag = 150;

    NSMenuItem *speed2Item = [audioMenu addItemWithTitle:@"Play 2x Speed" action:@selector(setPlaybackSpeed:) keyEquivalent:@""];
    speed2Item.tag = 200;

    NSMenuItem *speed3Item = [audioMenu addItemWithTitle:@"Play 3x Speed" action:@selector(setPlaybackSpeed:) keyEquivalent:@""];
    speed3Item.tag = 300;

    NSMenuItem *speed4Item = [audioMenu addItemWithTitle:@"Play 4x Speed" action:@selector(setPlaybackSpeed:) keyEquivalent:@""];
    speed4Item.tag = 400;

    NSMenuItem *speed34Item = [audioMenu addItemWithTitle:@"Play 3/4 Speed" action:@selector(setPlaybackSpeed:) keyEquivalent:@""];
    speed34Item.tag = 75;

    NSMenuItem *speed12Item = [audioMenu addItemWithTitle:@"Play 1/2 Speed" action:@selector(setPlaybackSpeed:) keyEquivalent:@""];
    speed12Item.tag = 50;

    NSMenuItem *speed14Item = [audioMenu addItemWithTitle:@"Play 1/4 Speed" action:@selector(setPlaybackSpeed:) keyEquivalent:@""];
    speed14Item.tag = 25;

    [audioMenu addItem:[NSMenuItem separatorItem]];

    // Volume radio group
    NSMenuItem *loudItem = [audioMenu addItemWithTitle:@"Loud" action:@selector(setVolume:) keyEquivalent:@""];
    loudItem.tag = 100;
    loudItem.state = NSControlStateValueOn;

    NSMenuItem *mediumItem = [audioMenu addItemWithTitle:@"Medium" action:@selector(setVolume:) keyEquivalent:@""];
    mediumItem.tag = 66;

    NSMenuItem *quietItem = [audioMenu addItemWithTitle:@"Quiet" action:@selector(setVolume:) keyEquivalent:@""];
    quietItem.tag = 33;

    NSMenuItem *veryQuietItem = [audioMenu addItemWithTitle:@"Very Quiet" action:@selector(setVolume:) keyEquivalent:@""];
    veryQuietItem.tag = 10;

    NSMenuItem *silentItem = [audioMenu addItemWithTitle:@"Silent" action:@selector(setVolume:) keyEquivalent:@""];
    silentItem.tag = 0;

    [audioMenu addItem:[NSMenuItem separatorItem]];

    // Audio Stems
    [audioMenu addItemWithTitle:@"Import Audio Stems\u2026" action:@selector(importAudioStems:) keyEquivalent:@""];
    [audioMenu addItemWithTitle:@"Import Stems from Folder\u2026" action:@selector(importStemsFromFolder:) keyEquivalent:@""];
    [audioMenu addItemWithTitle:@"Remove All Audio Stems" action:@selector(removeAllAudioStems:) keyEquivalent:@""];

    audioMenuItem.submenu = audioMenu;
}

+ (void)addToolsMenuTo:(NSMenu *)mainMenu target:(id)target {
    NSMenuItem *toolsMenuItem = [mainMenu addItemWithTitle:@"Tools" action:nil keyEquivalent:@""];
    NSMenu *toolsMenu = [[NSMenu alloc] initWithTitle:@"Tools"];

    [toolsMenu addItemWithTitle:@"Test" action:@selector(showTest:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Check Sequence" action:@selector(checkSequence:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Cleanup File Locations" action:@selector(cleanupFileLocations:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Package Sequence" action:@selector(packageSequence:) keyEquivalent:@""];

    [toolsMenu addItem:[NSMenuItem separatorItem]];

    [toolsMenu addItemWithTitle:@"Download Sequences/Lyrics" action:@selector(downloadSequences:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Batch Render" action:@selector(batchRender:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"FPP Connect" action:@selector(fppConnect:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Bulk Controller Upload" action:@selector(bulkControllerUpload:) keyEquivalent:@""];

    [toolsMenu addItem:[NSMenuItem separatorItem]];

    [toolsMenu addItemWithTitle:@"Run Scripts" action:@selector(runScripts:) keyEquivalent:@""];

    [toolsMenu addItem:[NSMenuItem separatorItem]];

    [toolsMenu addItemWithTitle:@"Export Models" action:@selector(exportModelsFromTools:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Export Effects" action:@selector(exportEffectsFromTools:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Export Controller Connections" action:@selector(exportControllerConnections:) keyEquivalent:@""];

    [toolsMenu addItem:[NSMenuItem separatorItem]];

    [toolsMenu addItemWithTitle:@"View Log" action:@selector(viewLog:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Package Log Files" action:@selector(packageLogFiles:) keyEquivalent:@""];

    [toolsMenu addItem:[NSMenuItem separatorItem]];

    [toolsMenu addItemWithTitle:@"Purge Download Cache" action:@selector(purgeDownloadCache:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Purge Render Cache" action:@selector(purgeRenderCache:) keyEquivalent:@""];

    [toolsMenu addItem:[NSMenuItem separatorItem]];

    [toolsMenu addItemWithTitle:@"Generate 2D Path" action:@selector(generate2DPath:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Generate Custom Model" action:@selector(generateCustomModel:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Remap Custom Model" action:@selector(remapCustomModel:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Generate Lyrics From Data" action:@selector(generateLyricsFromData:) keyEquivalent:@""];

    [toolsMenu addItem:[NSMenuItem separatorItem]];

    [toolsMenu addItemWithTitle:@"Convert" action:@selector(convertSequence:) keyEquivalent:@""];
    [toolsMenu addItemWithTitle:@"Prepare Audio" action:@selector(prepareAudio:) keyEquivalent:@""];

    toolsMenuItem.submenu = toolsMenu;
}

+ (void)addHelpMenuTo:(NSMenu *)mainMenu target:(id)target {
    NSMenuItem *helpMenuItem = [mainMenu addItemWithTitle:@"Help" action:nil keyEquivalent:@""];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];

    [helpMenu addItemWithTitle:@"xLights Help" action:@selector(showHelp:) keyEquivalent:@"?"];
    [helpMenu addItemWithTitle:@"xLights Website" action:@selector(visitWebsite:) keyEquivalent:@""];
    [helpMenu addItemWithTitle:@"Tip of the Day" action:@selector(showTipOfTheDay:) keyEquivalent:@""];
    [helpMenu addItemWithTitle:@"User Manual" action:@selector(showUserManual:) keyEquivalent:@""];

    [helpMenu addItem:[NSMenuItem separatorItem]];

    [helpMenu addItemWithTitle:@"Key Bindings" action:@selector(showKeyBindings:) keyEquivalent:@""];

    [helpMenu addItem:[NSMenuItem separatorItem]];

    [helpMenu addItemWithTitle:@"Forum" action:@selector(visitForum:) keyEquivalent:@""];
    [helpMenu addItemWithTitle:@"Video Tutorials" action:@selector(showVideoTutorials:) keyEquivalent:@""];
    [helpMenu addItemWithTitle:@"Facebook" action:@selector(visitFacebook:) keyEquivalent:@""];

    [helpMenu addItem:[NSMenuItem separatorItem]];

    [helpMenu addItemWithTitle:@"Check for Updates…" action:@selector(checkForUpdates:) keyEquivalent:@""];
    [helpMenu addItemWithTitle:@"Release Notes" action:@selector(showReleaseNotes:) keyEquivalent:@""];
    [helpMenu addItemWithTitle:@"Issue Tracker" action:@selector(visitIssueTracker:) keyEquivalent:@""];
    [helpMenu addItemWithTitle:@"Donate" action:@selector(showDonate:) keyEquivalent:@""];

    [NSApp setHelpMenu:helpMenu];
    helpMenuItem.submenu = helpMenu;
}

@end
