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

NS_ASSUME_NONNULL_BEGIN

/// Completion handler for sheets. Response is NSModalResponseOK or NSModalResponseCancel.
typedef void (^XLSheetCompletion)(NSModalResponse response);

/// Base class for all native macOS sheet/dialog controllers.
///
/// Provides common functionality for:
/// - Sheet presentation with parent window attachment
/// - Window presentation for standalone dialogs
/// - Standard button bar layout (Cancel left, OK/action right)
/// - Keyboard navigation support
/// - Input validation framework
///
/// Subclasses override -buildContentView to provide dialog-specific content.
@interface XLBaseSheetController : NSObject

/// The sheet window (created on demand)
@property (nonatomic, strong, readonly) NSWindow *sheet;

/// The parent window when presented as sheet
@property (nonatomic, weak, readonly, nullable) NSWindow *parentWindow;

/// Title for the sheet
@property (nonatomic, copy) NSString *title;

/// OK button title (default: "OK")
@property (nonatomic, copy) NSString *okButtonTitle;

/// Cancel button title (default: "Cancel")
@property (nonatomic, copy) NSString *cancelButtonTitle;

/// Show a third action button (default: NO)
@property (nonatomic, assign) BOOL showsActionButton;

/// Third action button title
@property (nonatomic, copy, nullable) NSString *actionButtonTitle;

/// Minimum width for the sheet (default: 400)
@property (nonatomic, assign) CGFloat minWidth;

/// Minimum height for the sheet (default: 200)
@property (nonatomic, assign) CGFloat minHeight;

/// Present as a sheet attached to the parent window.
- (void)presentAsSheetForWindow:(NSWindow *)parentWindow
                     completion:(nullable XLSheetCompletion)completion;

/// Present as a standalone modal window.
- (void)presentAsModalWithCompletion:(nullable XLSheetCompletion)completion;

/// Dismiss the sheet/window with the given response code.
- (void)dismissWithResponse:(NSModalResponse)response;

/// Called when OK button is clicked. Validates and dismisses if valid.
/// Subclasses can override for custom behavior.
- (void)okClicked:(id)sender;

/// Called when Cancel button is clicked.
- (void)cancelClicked:(id)sender;

/// Called when Action button is clicked.
/// Subclasses must override if showsActionButton is YES.
- (void)actionClicked:(id)sender;

/// Validate the current state. Return nil if valid, or an error message.
/// Subclasses override to provide validation logic.
- (nullable NSString *)validate;

/// Update the enabled state of the OK button based on validation.
- (void)updateOKButtonState;

#pragma mark - Subclass Hooks

/// Build and return the main content view for the dialog.
/// Subclasses MUST override this method.
- (NSView *)buildContentView;

/// Called after the sheet is built but before presentation.
/// Subclasses can override for additional setup.
- (void)sheetDidLoad;

/// Called when the sheet is about to be dismissed.
/// Subclasses can override for cleanup.
- (void)sheetWillDismiss;

#pragma mark - Utility Methods

/// Create a labeled form row with label on left, control on right.
+ (NSStackView *)formRowWithLabel:(NSString *)label
                          control:(NSView *)control
                       labelWidth:(CGFloat)labelWidth;

/// Create a standard NSTextField for text input.
+ (NSTextField *)createTextField;

/// Create a standard NSTextField for numeric input.
+ (NSTextField *)createNumericField;

/// Create a standard NSPopUpButton.
+ (NSPopUpButton *)createPopUpButton;

/// Create a standard checkbox.
+ (NSButton *)createCheckboxWithTitle:(NSString *)title;

/// Create a standard NSTextView for multi-line text.
+ (NSScrollView *)createTextViewWithHeight:(CGFloat)height;

/// Get the text view from a scroll view created by createTextViewWithHeight.
+ (NSTextView *)textViewFromScrollView:(NSScrollView *)scrollView;

@end

NS_ASSUME_NONNULL_END
