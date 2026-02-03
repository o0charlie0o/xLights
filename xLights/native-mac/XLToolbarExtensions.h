#pragma once

/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import <Cocoa/Cocoa.h>

// Extended toolbar item identifiers for xLights native macOS UI.
// These supplement the basic identifiers in XLMainWindowController.mm
extern NSToolbarItemIdentifier const XLToolbarItemTransportGroup;
extern NSToolbarItemIdentifier const XLToolbarItemSeekStart;
extern NSToolbarItemIdentifier const XLToolbarItemSeekEnd;
extern NSToolbarItemIdentifier const XLToolbarItemToolMode;
extern NSToolbarItemIdentifier const XLToolbarItemZoom;
extern NSToolbarItemIdentifier const XLToolbarItemSearch;
extern NSToolbarItemIdentifier const XLToolbarItemPreview;

// XLToolbarBuilder provides factory methods for creating complex toolbar items
// following Logic Pro X / Final Cut Pro X patterns:
//   - Transport group (centered, like Logic Pro)
//   - Tool mode selector (Select, Effects Paint, Draw, Timing)
//   - Zoom controls (in/out/fit)
//   - Search field
//
// This pattern keeps toolbar setup code out of the main window controller
// and makes items reusable across windows if needed.
@interface XLToolbarBuilder : NSObject

+ (NSToolbarItem *)createTransportGroupWithTarget:(id)target;
+ (NSToolbarItem *)createToolModeControlWithTarget:(id)target;
+ (NSToolbarItem *)createZoomControlWithTarget:(id)target;
+ (NSToolbarItem *)createSearchFieldWithTarget:(id)target delegate:(id<NSSearchFieldDelegate>)delegate;
+ (NSToolbarItem *)createPreviewToggleWithTarget:(id)target;

@end

// XLMenuBuilder provides factory methods for building the complete xLights menu bar
// following macOS conventions:
//   - Application menu (About, Preferences, Services, Quit)
//   - File menu (New, Open, Save, Import, Export)
//   - Edit menu (Undo, Redo, Cut, Copy, Paste, Find)
//   - View menu (Panels, Zoom, Full Screen, Toolbar)
//   - Sequence menu (Play, Stop, Render, Timing)
//   - Model menu (Add, Group, Properties)
//   - Effect menu (Apply, Copy, Paste, Presets)
//   - Window menu (Minimize, Zoom, Bring All to Front)
//   - Help menu (Documentation, Updates)
//
// This builder pattern keeps menu setup code organized and testable.
@interface XLMenuBuilder : NSObject

+ (void)buildMenuBarForApplication:(NSApplication *)app target:(id)target;

+ (void)addApplicationMenuTo:(NSMenu *)mainMenu target:(id)target;
+ (void)addFileMenuTo:(NSMenu *)mainMenu target:(id)target;
+ (void)addEditMenuTo:(NSMenu *)mainMenu target:(id)target;
+ (void)addViewMenuTo:(NSMenu *)mainMenu target:(id)target;
+ (void)addSequenceMenuTo:(NSMenu *)mainMenu target:(id)target;
+ (void)addModelMenuTo:(NSMenu *)mainMenu target:(id)target;
+ (void)addEffectMenuTo:(NSMenu *)mainMenu target:(id)target;
+ (void)addWindowMenuTo:(NSMenu *)mainMenu app:(NSApplication *)app;
+ (void)addHelpMenuTo:(NSMenu *)mainMenu target:(id)target;

@end
