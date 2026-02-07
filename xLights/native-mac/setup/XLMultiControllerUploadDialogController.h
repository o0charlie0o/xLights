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

@class XLEngineBridge;
@class XLMultiControllerUploadDialogController;

/// Upload mode for a controller.
typedef NS_ENUM(NSInteger, XLUploadMode) {
    XLUploadModeBoth = 0,      // Upload both input and output
    XLUploadModeOutputOnly,    // Upload output configuration only
    XLUploadModeInputOnly      // Upload input configuration only
};

/// Per-controller upload status in the multi-upload dialog.
typedef NS_ENUM(NSInteger, XLMultiUploadStatus) {
    XLMultiUploadStatusPending = 0,
    XLMultiUploadStatusInProgress,
    XLMultiUploadStatusSuccess,
    XLMultiUploadStatusFailed,
    XLMultiUploadStatusCancelled
};

/// Model object for a controller row in the multi-upload dialog.
@interface XLMultiUploadControllerEntry : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *address;
@property (nonatomic, assign) BOOL selected;
@property (nonatomic, assign) XLUploadMode uploadMode;
@property (nonatomic, assign) XLMultiUploadStatus status;
@property (nonatomic, copy) NSString *statusMessage;

@end

/// Delegate protocol for multi-controller upload completion.
@protocol XLMultiControllerUploadDelegate <NSObject>

@optional

/// Called when all uploads have completed.
- (void)multiControllerUploadDialog:(XLMultiControllerUploadDialogController *)dialog
              didCompleteWithResults:(NSArray<XLMultiUploadControllerEntry *> *)results;

/// Called when the dialog was cancelled.
- (void)multiControllerUploadDialogDidCancel:(XLMultiControllerUploadDialogController *)dialog;

@end

/// A dedicated dialog for selecting and uploading to multiple controllers.
///
/// Presents a table of all controllers with checkboxes, per-controller upload
/// mode selection, and real-time progress tracking. Supports global upload mode
/// override, select all/deselect all, and per-controller cancel.
@interface XLMultiControllerUploadDialogController : NSWindowController

/// Engine bridge for performing uploads and fetching controller data.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Delegate for completion callbacks.
@property (nonatomic, weak) id<XLMultiControllerUploadDelegate> delegate;

/// Whether the upload is currently in progress.
@property (nonatomic, readonly) BOOL isUploading;

/// Initialize with an engine bridge.
- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge;

/// Present the dialog as a sheet attached to the given window.
- (void)presentAsSheetOnWindow:(NSWindow *)parentWindow;

/// Present the dialog as a standalone window.
- (void)presentAsWindow;

@end
