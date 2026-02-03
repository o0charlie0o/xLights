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
    [importMenu addItemWithTitle:@"Import Controllers…" action:@selector(importControllers:) keyEquivalent:@""];
    importItem.submenu = importMenu;

    NSMenuItem *exportItem = [fileMenu addItemWithTitle:@"Export" action:nil keyEquivalent:@""];
    NSMenu *exportMenu = [[NSMenu alloc] initWithTitle:@"Export"];
    [exportMenu addItemWithTitle:@"Export Effects…" action:@selector(exportEffects:) keyEquivalent:@""];
    [exportMenu addItemWithTitle:@"Export Models…" action:@selector(exportModels:) keyEquivalent:@""];
    [exportMenu addItemWithTitle:@"Export Video…" action:@selector(exportVideo:) keyEquivalent:@""];
    exportItem.submenu = exportMenu;

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

    editMenuItem.submenu = editMenu;
}

+ (void)addViewMenuTo:(NSMenu *)mainMenu target:(id)target {
    NSMenuItem *viewMenuItem = [mainMenu addItemWithTitle:@"View" action:nil keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];

    [viewMenu addItemWithTitle:@"Show Inspector" action:@selector(toggleInspector:) keyEquivalent:@"i"];
    [viewMenu addItemWithTitle:@"Show Bottom Panel" action:@selector(toggleBottomPanel:) keyEquivalent:@"b"];
    [viewMenu addItemWithTitle:@"Show Preview" action:@selector(togglePreview:) keyEquivalent:@"p"]
        .keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
    [viewMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];
    [viewMenu addItemWithTitle:@"Zoom to Fit" action:@selector(zoomToFit:) keyEquivalent:@"0"];

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

+ (void)addHelpMenuTo:(NSMenu *)mainMenu target:(id)target {
    NSMenuItem *helpMenuItem = [mainMenu addItemWithTitle:@"Help" action:nil keyEquivalent:@""];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];

    [helpMenu addItemWithTitle:@"xLights Help" action:@selector(showHelp:) keyEquivalent:@"?"];
    [helpMenu addItemWithTitle:@"xLights Website" action:@selector(visitWebsite:) keyEquivalent:@""];
    [helpMenu addItem:[NSMenuItem separatorItem]];
    [helpMenu addItemWithTitle:@"Check for Updates…" action:@selector(checkForUpdates:) keyEquivalent:@""];
    [helpMenu addItemWithTitle:@"Release Notes" action:@selector(showReleaseNotes:) keyEquivalent:@""];

    [NSApp setHelpMenu:helpMenu];
    helpMenuItem.submenu = helpMenu;
}

@end
