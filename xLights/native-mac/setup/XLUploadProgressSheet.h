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
@class XLUploadProgressSheet;

/// Upload result status for a single controller
typedef NS_ENUM(NSInteger, XLUploadStatus) {
    XLUploadStatusPending = 0,
    XLUploadStatusInProgress,
    XLUploadStatusSuccess,
    XLUploadStatusFailed,
    XLUploadStatusCancelled
};

/// Upload result for a single controller
@interface XLUploadResult : NSObject

@property (nonatomic, copy) NSString *controllerName;
@property (nonatomic, copy) NSString *controllerAddress;
@property (nonatomic, assign) XLUploadStatus status;
@property (nonatomic, copy) NSString *inputMessage;
@property (nonatomic, copy) NSString *outputMessage;
@property (nonatomic, copy) NSString *errorMessage;

@end

/// Delegate protocol for upload progress callbacks
@protocol XLUploadProgressSheetDelegate <NSObject>

@optional

/// Called when all uploads have completed
- (void)uploadProgressSheet:(XLUploadProgressSheet *)sheet
     didCompleteWithResults:(NSArray<XLUploadResult *> *)results;

/// Called when the user cancels the upload
- (void)uploadProgressSheetDidCancel:(XLUploadProgressSheet *)sheet;

@end

/// Sheet dialog showing upload progress for controller configuration upload.
///
/// Supports both single controller and multi-controller batch uploads.
/// Displays:
/// - Progress bar with percentage
/// - Current controller/operation being processed
/// - Scrolling log of results
/// - Cancel button
/// - Success/error summary at completion
@interface XLUploadProgressSheet : NSWindowController

/// Engine bridge for performing uploads
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Delegate for completion callbacks
@property (nonatomic, weak) id<XLUploadProgressSheetDelegate> delegate;

/// Whether the upload is currently in progress
@property (nonatomic, readonly) BOOL isUploading;

/// Whether the upload was cancelled
@property (nonatomic, readonly) BOOL wasCancelled;

/// Results of completed uploads
@property (nonatomic, readonly) NSArray<XLUploadResult *> *results;

/// Initialize with an engine bridge
- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge;

/// Begin a single controller upload as a sheet attached to the parent window.
/// @param controllerName Name of the controller to upload to
/// @param parentWindow Window to attach the sheet to
- (void)uploadToController:(NSString *)controllerName
         attachedToWindow:(NSWindow *)parentWindow;

/// Begin a multi-controller batch upload as a sheet attached to the parent window.
/// @param controllerNames Array of controller names to upload to
/// @param parentWindow Window to attach the sheet to
- (void)uploadToControllers:(NSArray<NSString *> *)controllerNames
          attachedToWindow:(NSWindow *)parentWindow;

/// Cancel the current upload operation
- (void)cancelUpload;

/// Close the sheet
- (void)closeSheet;

@end
