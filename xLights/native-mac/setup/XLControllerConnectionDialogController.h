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

/// Result structure returned when the dialog completes with Apply.
/// Only fields whose corresponding `apply*` flag is YES should be written.
@interface XLControllerConnectionResult : NSObject

@property (nonatomic, assign) BOOL applyProtocol;
@property (nonatomic, copy)   NSString *protocol;

@property (nonatomic, assign) BOOL applyPort;
@property (nonatomic, assign) NSInteger port;

@property (nonatomic, assign) BOOL applyDirection;
@property (nonatomic, assign) NSInteger direction; // 0=Forward, 1=Reverse

@property (nonatomic, assign) BOOL applyColorOrder;
@property (nonatomic, copy)   NSString *colorOrder;

@property (nonatomic, assign) BOOL applyStartNullNodes;
@property (nonatomic, assign) NSInteger startNullNodes;

@property (nonatomic, assign) BOOL applyEndNullNodes;
@property (nonatomic, assign) NSInteger endNullNodes;

@property (nonatomic, assign) BOOL applyBrightness;
@property (nonatomic, assign) NSInteger brightness;

@property (nonatomic, assign) BOOL applyGamma;
@property (nonatomic, assign) double gamma;

@property (nonatomic, assign) BOOL applyGroupCount;
@property (nonatomic, assign) NSInteger groupCount;

@property (nonatomic, assign) BOOL applySmartRemote;
@property (nonatomic, assign) NSInteger smartRemote; // 0=None, 1=A, 2=B, ...

@end

/// Completion handler called when the dialog is dismissed.
/// result is non-nil if the user clicked Apply, nil if cancelled.
typedef void (^XLControllerConnectionCompletion)(XLControllerConnectionResult * _Nullable result);

/// Native bulk-edit dialog for model controller connections.
///
/// Shows a sheet with all connection properties (protocol, port, color order,
/// gamma, brightness, null pixels, smart remote, direction, group count).
/// Each field has an enable checkbox -- only checked fields are applied,
/// allowing partial updates across multiple selected models.
///
/// Usage:
///   XLControllerConnectionDialogController *dialog =
///       [[XLControllerConnectionDialogController alloc] initWithModelCount:selectedModels.count];
///   [dialog showAsSheetForWindow:parentWindow completion:^(XLControllerConnectionResult *result) {
///       if (result) { /* apply result to selected models */ }
///   }];
@interface XLControllerConnectionDialogController : NSWindowController

/// Number of models that will be affected (shown in the title).
@property (nonatomic, assign, readonly) NSUInteger modelCount;

/// Initialize with the count of models to be edited.
- (instancetype)initWithModelCount:(NSUInteger)count;

/// Present as a sheet attached to parentWindow.
- (void)showAsSheetForWindow:(NSWindow *)parentWindow
                  completion:(XLControllerConnectionCompletion)completion;

@end
