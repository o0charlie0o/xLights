/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLBaseSheetController.h"

NS_ASSUME_NONNULL_BEGIN

/// Progress item for a rendering model
@interface XLRenderProgressItem : NSObject

@property (nonatomic, copy) NSString *modelName;
@property (nonatomic, assign) double progress;      // 0.0 - 1.0
@property (nonatomic, copy, nullable) NSString *status;
@property (nonatomic, assign) BOOL completed;

@end

/// Native macOS dialog for displaying render progress.
///
/// Shows progress bars for each model being rendered.
@interface XLRenderProgressDialog : NSObject

/// The dialog window
@property (nonatomic, strong, readonly) NSWindow *window;

/// Whether rendering is complete
@property (nonatomic, assign, readonly) BOOL isComplete;

/// Show the progress dialog as a non-modal window.
- (void)showForWindow:(NSWindow *)parentWindow;

/// Hide and close the dialog.
- (void)close;

/// Add a new progress item for a model.
- (void)addProgressItemForModel:(NSString *)modelName;

/// Update progress for a model.
- (void)updateProgressForModel:(NSString *)modelName progress:(double)progress;

/// Update status text for a model.
- (void)updateStatusForModel:(NSString *)modelName status:(NSString *)status;

/// Mark a model as completed.
- (void)markCompleted:(NSString *)modelName;

/// Mark all models as completed.
- (void)markAllCompleted;

/// Clear all progress items.
- (void)clearAll;

@end

NS_ASSUME_NONNULL_END
