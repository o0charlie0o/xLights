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

@class XLEngineBridge;

/// FPP Connect window controller.
///
/// Provides UI for discovering Falcon Player (FPP) devices on the local network
/// and uploading FSEQ sequence files and configuration to them.
///
/// Layout:
///   - Left panel: Table of discovered FPP devices (IP, hostname, version)
///   - Right panel: File list with checkboxes for files to upload
///   - Toolbar: Discover, Add IP, Upload Selected, Upload All
///   - Status bar: Progress indicator and status text
@interface XLFPPConnectWindowController : NSWindowController <NSTableViewDelegate, NSTableViewDataSource, NSSplitViewDelegate>

/// Engine bridge for querying show folder path and sequence data.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Initialize with an engine bridge.
- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge;

/// Refresh the file list from the current show folder.
- (void)refreshFileList;

/// Start device discovery.
- (void)discoverDevices;

@end
