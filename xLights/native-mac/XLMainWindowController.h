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

@class XLSetupViewController;
@class XLLayoutViewController;
@class XLSequencerViewController;
@class XLInspectorViewController;
@class XLEngineBridge;
@class XLPlaybackController;
@class XLRenderProgressIndicator;

/// Main window controller for the native macOS xLights UI.
///
/// Manages the three-region split view layout (Setup, Layout/Preview, Sequencer)
/// with collapsible right inspector and bottom panel regions.
/// Pattern: Logic Pro X / Final Cut Pro X split view hierarchy.
///
/// Layout structure:
/// - Top: NSToolbar (play controls, tool modes, view toggles)
/// - Center: NSSplitViewController with main content + inspector
/// - Bottom: Collapsible properties/color picker panel
///
/// All subsequent UI phases depend on this foundation.
@interface XLMainWindowController : NSWindowController <NSToolbarDelegate>

/// Current active tab (Setup=0, Layout=1, Sequencer=2)
@property (nonatomic, assign) NSInteger currentTab;

/// Engine bridge to C++ xlEngine APIs
@property (nonatomic, strong, readonly) XLEngineBridge *engineBridge;

/// View controllers for each tab region
@property (nonatomic, strong, readonly) XLSetupViewController *setupViewController;
@property (nonatomic, strong, readonly) XLLayoutViewController *layoutViewController;
@property (nonatomic, strong, readonly) XLSequencerViewController *sequencerViewController;

/// Inspector sidebar controller (right panel)
@property (nonatomic, strong, readonly) XLInspectorViewController *inspectorViewController;

/// Playback controller for synchronized preview rendering
@property (nonatomic, strong, readonly) XLPlaybackController *playbackController;

/// Render progress ring indicator in the toolbar
@property (nonatomic, strong, readonly) XLRenderProgressIndicator *renderProgressIndicator;

/// Show/hide inspector sidebar
- (void)toggleInspector:(id)sender;

/// Show/hide bottom panel
- (void)toggleBottomPanel:(id)sender;

/// Switch to a specific tab (0=Setup, 1=Layout, 2=Sequencer)
- (void)switchToTab:(NSInteger)tabIndex;

/// Save window state (frame, split positions) to user defaults
- (void)saveWindowState;

/// Restore window state from user defaults
- (void)restoreWindowState;

@end
