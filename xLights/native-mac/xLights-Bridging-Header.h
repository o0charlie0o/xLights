/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#ifndef xLights_Bridging_Header_h
#define xLights_Bridging_Header_h

// Core AppKit view controllers for embedding in SwiftUI
#import "XLSetupViewController.h"
#import "XLLayoutViewController.h"
#import "XLSequencerViewController.h"
#import "XLInspectorViewController.h"
#import "XLEffectPropertiesViewController.h"
#import "XLColorPaletteViewController.h"
#import "XLEngineBridge.h"
#import "XLPlaybackController.h"
#import "layout/XLMetalPreviewView.h"

// Input handling
#import "input/XLKeyboardHandler.h"

// Command palette visibility flag (used by local event monitor)
#ifdef __cplusplus
extern "C" {
#endif
void XLSetCommandPaletteVisible(bool visible);
#ifdef __cplusplus
}
#endif

#endif /* xLights_Bridging_Header_h */
