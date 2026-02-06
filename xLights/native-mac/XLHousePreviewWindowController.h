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

@class XLMetalPreviewView;
@class XLEngineBridge;
@class XLCameraController;
@class XLPlaybackController;

/// House preview window with toolbar controls for playback and viewpoint switching.
///
/// Shows all models in their layout positions with real-time effect colors.
/// The preview view can be wired to XLPlaybackController.previewView to receive
/// rendered pixel data during playback.
@protocol XLMetalPreviewDelegate;

@interface XLHousePreviewWindowController : NSWindowController <NSWindowDelegate, NSToolbarDelegate, XLMetalPreviewDelegate>

/// The Metal-backed preview view that renders models.
@property (nonatomic, strong, readonly) XLMetalPreviewView *previewView;

/// Engine bridge for querying model data.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Playback controller for transport controls (play/pause/stop).
@property (nonatomic, weak) XLPlaybackController *playbackController;

/// Initialize with an engine bridge.
- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge;

/// Reload model data from the engine bridge.
- (void)reloadModels;

@end
