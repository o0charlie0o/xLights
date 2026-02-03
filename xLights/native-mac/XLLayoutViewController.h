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
#import "layout/XLMetalPreviewView.h"
#import "layout/XLModelTreeViewController.h"

@class XLEngineBridge;

/// View controller for the Layout/Preview tab.
///
/// Displays Metal-based 3D preview, model tree, and manipulation handles.
/// Layout: Left sidebar (model tree) | Center (Metal preview)
/// The preview already uses Metal — the main work is replacing the wxWidgets
/// wrapper with native NSView-based Metal view.
@interface XLLayoutViewController : NSViewController <XLMetalPreviewDelegate, XLModelTreeDelegate>

@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// The Metal preview view (3D model rendering surface)
@property (nonatomic, strong, readonly) XLMetalPreviewView *previewView;

/// The model tree view controller (left sidebar)
@property (nonatomic, strong, readonly) XLModelTreeViewController *modelTreeController;

@end
