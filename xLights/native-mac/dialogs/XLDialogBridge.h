/***************************************************************
 * Name:      XLDialogBridge.h
 * Purpose:   C++ bridge to native macOS dialogs
 * Author:    xLights Team
 * Created:   2026-02-03
 * Copyright: xLights (https://xlights.org)
 * License:   GPLv3
 **************************************************************/

#ifndef XL_DIALOG_BRIDGE_H
#define XL_DIALOG_BRIDGE_H

#include <string>
#include <vector>

#ifdef __OBJC__
@class NSWindow;
#else
typedef void NSWindow;
#endif

namespace XLDialogs {

// Result codes matching wxWidgets
enum class AlertResult {
    OK = 5100,      // wxID_OK
    Cancel = 5101,  // wxID_CANCEL
    Yes = 5103,     // wxID_YES
    No = 5104       // wxID_NO
};

// Alert style options
enum class AlertStyle {
    Informational,
    Warning,
    Critical,
    Question
};

// Button configurations
enum class AlertButtons {
    OK,
    OKCancel,
    YesNo,
    YesNoCancel
};

#pragma mark - Alert Dialogs

/**
 * Show an alert dialog.
 * @param title Alert title
 * @param message Alert message
 * @param style Alert style
 * @param buttons Button configuration
 * @param parentWindow Parent window (can be nullptr)
 * @return AlertResult indicating which button was clicked
 */
AlertResult showAlert(const std::string& title,
                      const std::string& message,
                      AlertStyle style = AlertStyle::Informational,
                      AlertButtons buttons = AlertButtons::OK,
                      void* parentWindow = nullptr);

/**
 * Show an error alert (convenience function).
 */
void showError(const std::string& title,
               const std::string& message,
               void* parentWindow = nullptr);

/**
 * Show a warning alert (convenience function).
 */
void showWarning(const std::string& title,
                 const std::string& message,
                 void* parentWindow = nullptr);

/**
 * Show an informational alert (convenience function).
 */
void showInfo(const std::string& title,
              const std::string& message,
              void* parentWindow = nullptr);

/**
 * Show a Yes/No confirmation dialog.
 * @return true if Yes was clicked, false otherwise
 */
bool showConfirmation(const std::string& title,
                      const std::string& message,
                      void* parentWindow = nullptr);

/**
 * Show a Yes/No/Cancel confirmation dialog.
 * @return AlertResult::Yes, AlertResult::No, or AlertResult::Cancel
 */
AlertResult showConfirmationWithCancel(const std::string& title,
                                       const std::string& message,
                                       void* parentWindow = nullptr);

#pragma mark - File Dialogs

/**
 * Show an open file dialog.
 * @param title Dialog title
 * @param directory Initial directory (empty for default)
 * @param fileTypes Vector of file extensions (without dots), empty for all files
 * @param allowMultiple Allow selecting multiple files
 * @param parentWindow Parent window (can be nullptr)
 * @return Vector of selected file paths, empty if cancelled
 */
std::vector<std::string> showOpenPanel(const std::string& title,
                                       const std::string& directory = "",
                                       const std::vector<std::string>& fileTypes = {},
                                       bool allowMultiple = false,
                                       void* parentWindow = nullptr);

/**
 * Show an open file dialog for a single file.
 * @return Selected file path, empty string if cancelled
 */
std::string showOpenPanelSingle(const std::string& title,
                                const std::string& directory = "",
                                const std::vector<std::string>& fileTypes = {},
                                void* parentWindow = nullptr);

/**
 * Show a save file dialog.
 * @param title Dialog title
 * @param directory Initial directory (empty for default)
 * @param defaultName Default filename
 * @param fileTypes Vector of file extensions (without dots), empty for all files
 * @param parentWindow Parent window (can be nullptr)
 * @return Selected file path, empty string if cancelled
 */
std::string showSavePanel(const std::string& title,
                          const std::string& directory = "",
                          const std::string& defaultName = "",
                          const std::vector<std::string>& fileTypes = {},
                          void* parentWindow = nullptr);

/**
 * Show a directory chooser dialog.
 * @param title Dialog title
 * @param directory Initial directory (empty for default)
 * @param canCreateDirectories Allow creating new directories
 * @param parentWindow Parent window (can be nullptr)
 * @return Selected directory path, empty string if cancelled
 */
std::string showDirectoryPanel(const std::string& title,
                               const std::string& directory = "",
                               bool canCreateDirectories = true,
                               void* parentWindow = nullptr);

#pragma mark - Text Input Dialogs

/**
 * Show a text input dialog.
 * @param title Dialog title
 * @param message Message/prompt text
 * @param defaultValue Initial text value
 * @param placeholder Placeholder text
 * @param parentWindow Parent window (can be nullptr)
 * @param outValue Output: entered text (only valid if returns true)
 * @return true if OK was clicked, false if cancelled
 */
bool showTextInput(const std::string& title,
                   const std::string& message,
                   const std::string& defaultValue,
                   const std::string& placeholder,
                   void* parentWindow,
                   std::string& outValue);

/**
 * Show a text input dialog (simpler overload).
 * @return Entered text, empty string if cancelled
 */
std::string showTextInput(const std::string& title,
                          const std::string& message,
                          const std::string& defaultValue = "",
                          void* parentWindow = nullptr);

/**
 * Show a secure text input dialog (for passwords).
 * @return Entered text, empty string if cancelled
 */
std::string showSecureTextInput(const std::string& title,
                                const std::string& message,
                                const std::string& placeholder = "",
                                void* parentWindow = nullptr);

#pragma mark - Choice Dialogs

/**
 * Show a single-choice dialog.
 * @param title Dialog title
 * @param message Message text
 * @param choices Vector of choice strings
 * @param defaultSelection Initial selection index (-1 for none)
 * @param parentWindow Parent window (can be nullptr)
 * @return Selected index, -1 if cancelled
 */
int showSingleChoice(const std::string& title,
                     const std::string& message,
                     const std::vector<std::string>& choices,
                     int defaultSelection = 0,
                     void* parentWindow = nullptr);

/**
 * Show a single-choice dialog and return the selected string.
 * @param outSelection Output: selected string (only valid if returns true)
 * @return true if OK was clicked, false if cancelled
 */
bool showSingleChoiceString(const std::string& title,
                            const std::string& message,
                            const std::vector<std::string>& choices,
                            int defaultSelection,
                            void* parentWindow,
                            std::string& outSelection);

/**
 * Show a multi-choice dialog.
 * @param title Dialog title
 * @param message Message text
 * @param choices Vector of choice strings
 * @param initialSelections Vector of initially selected indices
 * @param parentWindow Parent window (can be nullptr)
 * @param outSelections Output: vector of selected indices (only valid if returns true)
 * @return true if OK was clicked, false if cancelled
 */
bool showMultiChoice(const std::string& title,
                     const std::string& message,
                     const std::vector<std::string>& choices,
                     const std::vector<int>& initialSelections,
                     void* parentWindow,
                     std::vector<int>& outSelections);

#pragma mark - Progress Dialogs

/**
 * Progress dialog handle (opaque pointer).
 */
class ProgressDialog {
public:
    ProgressDialog(void* controller);
    ~ProgressDialog();

    // Update progress value (0 to maximum)
    void updateProgress(unsigned int value);

    // Update message text
    void updateMessage(const std::string& message);

    // Update both progress and message
    void update(unsigned int value, const std::string& message);

    // Set indeterminate mode
    void setIndeterminate(bool indeterminate);

    // Check if user requested cancellation
    bool wasCancelled() const;

    // Close the dialog
    void close();

    // Pulse the progress bar (for indeterminate mode)
    void pulse();

private:
    void* _controller;  // XLProgressController*
};

/**
 * Create and show a progress dialog.
 * @param title Dialog title
 * @param message Initial message
 * @param maximum Maximum progress value (0 for indeterminate)
 * @param canCancel Allow cancellation
 * @param parentWindow Parent window (can be nullptr)
 * @return ProgressDialog object to control the dialog
 */
ProgressDialog* showProgress(const std::string& title,
                             const std::string& message,
                             unsigned int maximum = 100,
                             bool canCancel = true,
                             void* parentWindow = nullptr);

#pragma mark - Color Dialogs

/**
 * Color structure for RGB values.
 */
struct Color {
    unsigned char r, g, b, a;

    Color() : r(0), g(0), b(0), a(255) {}
    Color(unsigned char red, unsigned char green, unsigned char blue, unsigned char alpha = 255)
        : r(red), g(green), b(blue), a(alpha) {}
};

/**
 * Show a color picker dialog.
 * @param initialColor Initial color
 * @param parentWindow Parent window (can be nullptr)
 * @param outColor Output: selected color (only valid if returns true)
 * @return true if OK was clicked, false if cancelled
 */
bool showColorPicker(const Color& initialColor,
                     void* parentWindow,
                     Color& outColor);

#pragma mark - Number Entry Dialogs

/**
 * Show a number entry dialog.
 * @param title Dialog title
 * @param message Message text
 * @param prompt Field prompt
 * @param value Initial value
 * @param min Minimum value
 * @param max Maximum value
 * @param parentWindow Parent window (can be nullptr)
 * @param outValue Output value (only valid if returns true)
 * @return true if OK was clicked, false if cancelled
 */
bool showNumberEntry(const std::string& title,
                     const std::string& message,
                     const std::string& prompt,
                     long value,
                     long min,
                     long max,
                     void* parentWindow,
                     long& outValue);

/**
 * Show a number entry dialog (simpler overload).
 * @return Entered value, or -1 if cancelled
 */
long showNumberEntry(const std::string& title,
                     const std::string& message,
                     const std::string& prompt,
                     long value,
                     long min,
                     long max,
                     void* parentWindow = nullptr);

#pragma mark - Save Changes Dialogs

/**
 * Show a "Save Changes?" dialog with Save/Don't Save/Cancel options.
 * @param documentName Name of the document with unsaved changes
 * @param parentWindow Parent window (can be nullptr)
 * @return 1 for Save, 0 for Don't Save, -1 for Cancel
 */
int showSaveChangesDialog(const std::string& documentName, void* parentWindow = nullptr);

} // namespace XLDialogs

#endif // XL_DIALOG_BRIDGE_H
