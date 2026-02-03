/***************************************************************
 * Name:      XLNativeDialogs.h
 * Purpose:   Native macOS dialog utilities for xLights
 * Author:    xLights Team
 * Created:   2026-02-03
 * Copyright: xLights (https://xlights.org)
 * License:   GPLv3
 **************************************************************/

#ifndef XL_NATIVE_DIALOGS_H
#define XL_NATIVE_DIALOGS_H

#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NS_ASSUME_NONNULL_BEGIN

// Forward declarations
@class XLProgressController;
@class XLMultiChoiceController;

// Alert style options matching wxWidgets patterns
typedef NS_ENUM(NSInteger, XLAlertStyle) {
    XLAlertStyleInformational = 0,
    XLAlertStyleWarning,
    XLAlertStyleCritical,
    XLAlertStyleQuestion
};

// Button configuration options
typedef NS_ENUM(NSInteger, XLAlertButtons) {
    XLAlertButtonsOK = 0,
    XLAlertButtonsOKCancel,
    XLAlertButtonsYesNo,
    XLAlertButtonsYesNoCancel
};

// Alert result values (matching wxWidgets return codes)
typedef NS_ENUM(NSInteger, XLAlertResult) {
    XLAlertResultOK = 5100,      // wxID_OK
    XLAlertResultCancel = 5101,  // wxID_CANCEL
    XLAlertResultYes = 5103,     // wxID_YES
    XLAlertResultNo = 5104       // wxID_NO
};

#pragma mark - XLNativeDialogs

/**
 * XLNativeDialogs provides native macOS equivalents for wxWidgets dialog types.
 * This is a utility class with class methods - no instance needed.
 *
 * Supported dialog types:
 * - Message alerts (wxMessageBox equivalent)
 * - File open panels (wxFileDialog with wxFD_OPEN)
 * - File save panels (wxFileDialog with wxFD_SAVE)
 * - Directory chooser panels (wxDirDialog equivalent)
 * - Text input dialogs (wxTextEntryDialog equivalent)
 * - Single choice dialogs (wxSingleChoiceDialog equivalent)
 * - Multi-choice dialogs (wxMultiChoiceDialog equivalent)
 * - Progress dialogs (wxProgressDialog equivalent)
 * - Color picker dialogs (wxColourDialog equivalent)
 */
@interface XLNativeDialogs : NSObject

#pragma mark - Alert Dialogs

/**
 * Show a simple alert dialog with custom buttons.
 * @param title The alert title
 * @param message The alert message text
 * @param style The alert style (informational, warning, critical, question)
 * @param buttons The button configuration
 * @param parentWindow Optional parent window for sheet presentation
 * @return XLAlertResult indicating which button was clicked
 */
+ (XLAlertResult)showAlertWithTitle:(NSString *)title
                            message:(NSString *)message
                              style:(XLAlertStyle)style
                            buttons:(XLAlertButtons)buttons
                       parentWindow:(nullable NSWindow *)parentWindow;

/**
 * Show an error alert.
 */
+ (void)showErrorWithTitle:(NSString *)title
                   message:(NSString *)message
              parentWindow:(nullable NSWindow *)parentWindow;

/**
 * Show a warning alert.
 */
+ (void)showWarningWithTitle:(NSString *)title
                     message:(NSString *)message
                parentWindow:(nullable NSWindow *)parentWindow;

/**
 * Show an informational alert.
 */
+ (void)showInfoWithTitle:(NSString *)title
                  message:(NSString *)message
             parentWindow:(nullable NSWindow *)parentWindow;

/**
 * Show a confirmation dialog (Yes/No).
 * @return YES if user clicked Yes, NO otherwise
 */
+ (BOOL)showConfirmationWithTitle:(NSString *)title
                          message:(NSString *)message
                     parentWindow:(nullable NSWindow *)parentWindow;

/**
 * Show a confirmation dialog with cancel option (Yes/No/Cancel).
 * @return XLAlertResultYes, XLAlertResultNo, or XLAlertResultCancel
 */
+ (XLAlertResult)showConfirmationWithCancelTitle:(NSString *)title
                                         message:(NSString *)message
                                    parentWindow:(nullable NSWindow *)parentWindow;

#pragma mark - File Dialogs

/**
 * Show an open file dialog.
 * @param title Dialog title
 * @param directory Initial directory (nil for default)
 * @param fileTypes Array of allowed file extensions (without dots), or nil for all files
 * @param allowMultiple Allow selecting multiple files
 * @param parentWindow Optional parent window
 * @return Array of selected file URLs, or nil if cancelled
 */
+ (nullable NSArray<NSURL *> *)showOpenPanelWithTitle:(NSString *)title
                                            directory:(nullable NSString *)directory
                                            fileTypes:(nullable NSArray<NSString *> *)fileTypes
                                        allowMultiple:(BOOL)allowMultiple
                                         parentWindow:(nullable NSWindow *)parentWindow;

/**
 * Show a save file dialog.
 * @param title Dialog title
 * @param directory Initial directory (nil for default)
 * @param defaultName Default filename
 * @param fileTypes Array of allowed file extensions (without dots), or nil for all files
 * @param parentWindow Optional parent window
 * @return Selected file URL, or nil if cancelled
 */
+ (nullable NSURL *)showSavePanelWithTitle:(NSString *)title
                                 directory:(nullable NSString *)directory
                               defaultName:(nullable NSString *)defaultName
                                 fileTypes:(nullable NSArray<NSString *> *)fileTypes
                              parentWindow:(nullable NSWindow *)parentWindow;

/**
 * Show a directory chooser dialog.
 * @param title Dialog title
 * @param directory Initial directory (nil for default)
 * @param canCreateDirectories Allow creating new directories
 * @param parentWindow Optional parent window
 * @return Selected directory URL, or nil if cancelled
 */
+ (nullable NSURL *)showDirectoryPanelWithTitle:(NSString *)title
                                      directory:(nullable NSString *)directory
                           canCreateDirectories:(BOOL)canCreateDirectories
                                   parentWindow:(nullable NSWindow *)parentWindow;

#pragma mark - Text Input Dialogs

/**
 * Show a text input dialog.
 * @param title Dialog title
 * @param message Message/prompt text
 * @param defaultValue Initial text value
 * @param placeholder Placeholder text (shown when field is empty)
 * @param parentWindow Optional parent window
 * @return Entered text, or nil if cancelled
 */
+ (nullable NSString *)showTextInputWithTitle:(NSString *)title
                                      message:(NSString *)message
                                 defaultValue:(nullable NSString *)defaultValue
                                  placeholder:(nullable NSString *)placeholder
                                 parentWindow:(nullable NSWindow *)parentWindow;

/**
 * Show a secure text input dialog (for passwords).
 */
+ (nullable NSString *)showSecureTextInputWithTitle:(NSString *)title
                                            message:(NSString *)message
                                        placeholder:(nullable NSString *)placeholder
                                       parentWindow:(nullable NSWindow *)parentWindow;

#pragma mark - Choice Dialogs

/**
 * Show a single-choice dialog.
 * @param title Dialog title
 * @param message Message text
 * @param choices Array of choice strings
 * @param defaultSelection Initial selection index (-1 for none)
 * @param parentWindow Optional parent window
 * @return Selected index, or -1 if cancelled
 */
+ (NSInteger)showSingleChoiceWithTitle:(NSString *)title
                               message:(NSString *)message
                               choices:(NSArray<NSString *> *)choices
                      defaultSelection:(NSInteger)defaultSelection
                          parentWindow:(nullable NSWindow *)parentWindow;

/**
 * Show a single-choice dialog and return the selected string.
 * @return Selected string, or nil if cancelled
 */
+ (nullable NSString *)showSingleChoiceStringWithTitle:(NSString *)title
                                               message:(NSString *)message
                                               choices:(NSArray<NSString *> *)choices
                                      defaultSelection:(NSInteger)defaultSelection
                                          parentWindow:(nullable NSWindow *)parentWindow;

/**
 * Show a multi-choice dialog.
 * @param title Dialog title
 * @param message Message text
 * @param choices Array of choice strings
 * @param initialSelections Array of initially selected indices
 * @param parentWindow Optional parent window
 * @return Array of selected indices, or nil if cancelled
 */
+ (nullable NSArray<NSNumber *> *)showMultiChoiceWithTitle:(NSString *)title
                                                   message:(NSString *)message
                                                   choices:(NSArray<NSString *> *)choices
                                        initialSelections:(nullable NSArray<NSNumber *> *)initialSelections
                                              parentWindow:(nullable NSWindow *)parentWindow;

#pragma mark - Progress Dialogs

/**
 * Create and show a progress dialog.
 * @param title Dialog title
 * @param message Initial message
 * @param maximum Maximum progress value (0 for indeterminate)
 * @param canCancel Allow cancellation
 * @param parentWindow Optional parent window
 * @return Progress controller that can be used to update/close the dialog
 */
+ (XLProgressController *)showProgressWithTitle:(NSString *)title
                                        message:(NSString *)message
                                        maximum:(NSUInteger)maximum
                                      canCancel:(BOOL)canCancel
                                   parentWindow:(nullable NSWindow *)parentWindow;

#pragma mark - Color Dialogs

/**
 * Show a color picker dialog.
 * @param initialColor Initial color (nil for default)
 * @param parentWindow Optional parent window
 * @return Selected color, or nil if cancelled
 */
+ (nullable NSColor *)showColorPickerWithInitialColor:(nullable NSColor *)initialColor
                                         parentWindow:(nullable NSWindow *)parentWindow;

#pragma mark - Number Entry Dialogs

/**
 * Show a number entry dialog.
 * @param title Dialog title
 * @param message Message text
 * @param prompt Field prompt
 * @param value Initial value
 * @param min Minimum value
 * @param max Maximum value
 * @param parentWindow Optional parent window
 * @param outValue Output value (only valid if returns YES)
 * @return YES if OK was clicked, NO if cancelled
 */
+ (BOOL)showNumberEntryWithTitle:(NSString *)title
                         message:(NSString *)message
                          prompt:(NSString *)prompt
                           value:(NSInteger)value
                             min:(NSInteger)min
                             max:(NSInteger)max
                    parentWindow:(nullable NSWindow *)parentWindow
                        outValue:(NSInteger *)outValue;

#pragma mark - Save Changes Dialogs

/**
 * Show a "Save Changes?" dialog with Save/Don't Save/Cancel options.
 * @param documentName Name of the document with unsaved changes
 * @param parentWindow Optional parent window
 * @return 1 for Save, 0 for Don't Save, -1 for Cancel
 */
+ (NSInteger)showSaveChangesDialogForDocument:(NSString *)documentName
                                 parentWindow:(nullable NSWindow *)parentWindow;

@end

#pragma mark - XLProgressController

/**
 * Controller for managing a progress dialog.
 */
@interface XLProgressController : NSObject

/**
 * Update the progress value.
 * @param value New progress value
 */
- (void)updateProgress:(NSUInteger)value;

/**
 * Update the progress message.
 * @param message New message text
 */
- (void)updateMessage:(NSString *)message;

/**
 * Update both progress and message.
 */
- (void)updateProgress:(NSUInteger)value message:(NSString *)message;

/**
 * Set progress to indeterminate mode.
 */
- (void)setIndeterminate:(BOOL)indeterminate;

/**
 * Check if user requested cancellation.
 */
@property (nonatomic, readonly) BOOL wasCancelled;

/**
 * Close the progress dialog.
 */
- (void)close;

/**
 * Pulse the progress bar (for indeterminate mode).
 */
- (void)pulse;

@end

#pragma mark - XLMultiChoiceController

/**
 * Internal controller for multi-choice dialogs.
 */
@interface XLMultiChoiceController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong, readonly) NSArray<NSString *> *choices;
@property (nonatomic, strong, readonly) NSMutableIndexSet *selectedIndices;

- (instancetype)initWithChoices:(NSArray<NSString *> *)choices
             initialSelections:(nullable NSArray<NSNumber *> *)initialSelections;

@end

NS_ASSUME_NONNULL_END

#endif // XL_NATIVE_DIALOGS_H
