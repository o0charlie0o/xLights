/***************************************************************
 * Name:      XLDialogHelpers.h
 * Purpose:   Drop-in replacement macros and helpers for wxWidgets dialogs
 * Author:    xLights Team
 * Created:   2026-02-03
 * Copyright: xLights (https://xlights.org)
 * License:   GPLv3
 **************************************************************/

#ifndef XL_DIALOG_HELPERS_H
#define XL_DIALOG_HELPERS_H

#include "XLDialogBridge.h"

// Only define these helpers when building for native macOS UI
#ifdef XLIGHTS_NATIVE_MAC

/**
 * This header provides drop-in replacement functions for common wxWidgets
 * dialog patterns. The goal is to make migration easier by providing
 * functions with similar signatures to wxWidgets.
 *
 * Usage:
 * Instead of:
 *   wxMessageBox("Error occurred", "Error", wxICON_ERROR | wxOK, parent);
 *
 * Use:
 *   XL_MessageBox("Error occurred", "Error", XL_ICON_ERROR | XL_OK, parent);
 *
 * The XL_ versions use native macOS dialogs.
 */

// Button flags (matching wxWidgets values)
#define XL_OK               0x00000004
#define XL_YES              0x00000002
#define XL_NO               0x00000008
#define XL_CANCEL           0x00000010
#define XL_YES_NO           (XL_YES | XL_NO)
#define XL_OK_CANCEL        (XL_OK | XL_CANCEL)
#define XL_YES_NO_CANCEL    (XL_YES | XL_NO | XL_CANCEL)

// Icon flags (matching wxWidgets values)
#define XL_ICON_ERROR       0x00000200
#define XL_ICON_WARNING     0x00000100
#define XL_ICON_QUESTION    0x00000400
#define XL_ICON_INFORMATION 0x00000800
#define XL_ICON_EXCLAMATION XL_ICON_WARNING

// Default button flags (matching wxWidgets values)
#define XL_NO_DEFAULT       0x00000080
#define XL_CANCEL_DEFAULT   0x80000000

// Return values (matching wxWidgets values)
#define XL_ID_OK     5100
#define XL_ID_CANCEL 5101
#define XL_ID_YES    5103
#define XL_ID_NO     5104

namespace XLHelpers {

/**
 * wxMessageBox replacement.
 * @param message The message to display
 * @param caption The dialog title
 * @param style Style flags (XL_OK, XL_YES_NO, XL_ICON_ERROR, etc.)
 * @param parent Parent window (can be nullptr)
 * @return XL_ID_OK, XL_ID_CANCEL, XL_ID_YES, or XL_ID_NO
 */
inline int MessageBox(const std::string& message,
                      const std::string& caption = "Message",
                      int style = XL_OK | XL_ICON_INFORMATION,
                      void* parent = nullptr) {
    // Determine buttons
    XLDialogs::AlertButtons buttons = XLDialogs::AlertButtons::OK;
    if (style & XL_YES_NO) {
        if (style & XL_CANCEL) {
            buttons = XLDialogs::AlertButtons::YesNoCancel;
        } else {
            buttons = XLDialogs::AlertButtons::YesNo;
        }
    } else if (style & XL_CANCEL) {
        buttons = XLDialogs::AlertButtons::OKCancel;
    }

    // Determine style
    XLDialogs::AlertStyle alertStyle = XLDialogs::AlertStyle::Informational;
    if (style & XL_ICON_ERROR) {
        alertStyle = XLDialogs::AlertStyle::Critical;
    } else if (style & XL_ICON_WARNING) {
        alertStyle = XLDialogs::AlertStyle::Warning;
    } else if (style & XL_ICON_QUESTION) {
        alertStyle = XLDialogs::AlertStyle::Question;
    }

    XLDialogs::AlertResult result = XLDialogs::showAlert(caption, message, alertStyle, buttons, parent);

    switch (result) {
        case XLDialogs::AlertResult::OK: return XL_ID_OK;
        case XLDialogs::AlertResult::Cancel: return XL_ID_CANCEL;
        case XLDialogs::AlertResult::Yes: return XL_ID_YES;
        case XLDialogs::AlertResult::No: return XL_ID_NO;
    }
    return XL_ID_CANCEL;
}

/**
 * DisplayError replacement - matches xLights UtilFunctions.h signature.
 */
inline void DisplayError(const std::string& err, void* parent = nullptr) {
    XLDialogs::showError("Error", err, parent);
}

/**
 * DisplayWarning replacement - matches xLights UtilFunctions.h signature.
 */
inline void DisplayWarning(const std::string& warn, void* parent = nullptr) {
    XLDialogs::showWarning("Warning", warn, parent);
}

/**
 * DisplayInfo replacement - matches xLights UtilFunctions.h signature.
 */
inline void DisplayInfo(const std::string& info, void* parent = nullptr) {
    XLDialogs::showInfo("Information", info, parent);
}

/**
 * DisplayCrit replacement - matches xLights UtilFunctions.h signature.
 */
inline void DisplayCrit(const std::string& crit, void* parent = nullptr) {
    XLDialogs::showError("CRITICAL", crit, parent);
}

/**
 * Simple text entry dialog (wxTextEntryDialog replacement).
 * @param parent Parent window
 * @param message Prompt message
 * @param caption Dialog title
 * @param defaultValue Initial value
 * @param outValue Output value (only valid if returns true)
 * @return true if OK was clicked, false if cancelled
 */
inline bool GetTextFromUser(void* parent,
                            const std::string& message,
                            const std::string& caption,
                            const std::string& defaultValue,
                            std::string& outValue) {
    return XLDialogs::showTextInput(caption, message, defaultValue, "", parent, outValue);
}

/**
 * Simple text entry dialog (alternate signature).
 * @return Entered text, or empty string if cancelled
 */
inline std::string GetTextFromUser(const std::string& message,
                                   const std::string& caption,
                                   const std::string& defaultValue = "",
                                   void* parent = nullptr) {
    return XLDialogs::showTextInput(caption, message, defaultValue, parent);
}

/**
 * Single choice dialog (wxSingleChoiceDialog replacement).
 * @param message Message text
 * @param caption Dialog title
 * @param choices Vector of choices
 * @param selection Output: selected index (only valid if returns true)
 * @param parent Parent window
 * @return true if OK was clicked, false if cancelled
 */
inline bool GetSingleChoiceIndex(const std::string& message,
                                 const std::string& caption,
                                 const std::vector<std::string>& choices,
                                 int& selection,
                                 void* parent = nullptr) {
    int result = XLDialogs::showSingleChoice(caption, message, choices, selection, parent);
    if (result >= 0) {
        selection = result;
        return true;
    }
    return false;
}

/**
 * Single choice dialog returning string.
 * @return Selected string, or empty string if cancelled
 */
inline std::string GetSingleChoice(const std::string& message,
                                   const std::string& caption,
                                   const std::vector<std::string>& choices,
                                   int defaultSelection = 0,
                                   void* parent = nullptr) {
    std::string result;
    if (XLDialogs::showSingleChoiceString(caption, message, choices, defaultSelection, parent, result)) {
        return result;
    }
    return "";
}

/**
 * Multi-choice dialog (wxMultiChoiceDialog replacement).
 * @param message Message text
 * @param caption Dialog title
 * @param choices Vector of choices
 * @param selections Input: initial selections, Output: final selections
 * @param parent Parent window
 * @return true if OK was clicked, false if cancelled
 */
inline bool GetMultipleChoices(const std::string& message,
                               const std::string& caption,
                               const std::vector<std::string>& choices,
                               std::vector<int>& selections,
                               void* parent = nullptr) {
    std::vector<int> initial = selections;
    return XLDialogs::showMultiChoice(caption, message, choices, initial, parent, selections);
}

/**
 * File open dialog helper (wxFileDialog with wxFD_OPEN replacement).
 * @param title Dialog title
 * @param defaultDir Default directory
 * @param defaultFile Default filename
 * @param wildcard File type filter (e.g., "xlights,xsq" for extensions)
 * @param parent Parent window
 * @return Selected file path, or empty string if cancelled
 */
inline std::string FileOpenDialog(const std::string& title,
                                  const std::string& defaultDir = "",
                                  const std::string& defaultFile = "",
                                  const std::string& wildcard = "",
                                  void* parent = nullptr) {
    std::vector<std::string> fileTypes;
    if (!wildcard.empty()) {
        // Parse comma-separated extensions
        std::string ext;
        for (char c : wildcard) {
            if (c == ',' || c == ';') {
                if (!ext.empty()) {
                    fileTypes.push_back(ext);
                    ext.clear();
                }
            } else if (c != '*' && c != '.') {
                ext += c;
            }
        }
        if (!ext.empty()) {
            fileTypes.push_back(ext);
        }
    }
    return XLDialogs::showOpenPanelSingle(title, defaultDir, fileTypes, parent);
}

/**
 * File save dialog helper (wxFileDialog with wxFD_SAVE replacement).
 * @param title Dialog title
 * @param defaultDir Default directory
 * @param defaultFile Default filename
 * @param wildcard File type filter (e.g., "xlights" for extension)
 * @param parent Parent window
 * @return Selected file path, or empty string if cancelled
 */
inline std::string FileSaveDialog(const std::string& title,
                                  const std::string& defaultDir = "",
                                  const std::string& defaultFile = "",
                                  const std::string& wildcard = "",
                                  void* parent = nullptr) {
    std::vector<std::string> fileTypes;
    if (!wildcard.empty()) {
        // Parse comma-separated extensions
        std::string ext;
        for (char c : wildcard) {
            if (c == ',' || c == ';') {
                if (!ext.empty()) {
                    fileTypes.push_back(ext);
                    ext.clear();
                }
            } else if (c != '*' && c != '.') {
                ext += c;
            }
        }
        if (!ext.empty()) {
            fileTypes.push_back(ext);
        }
    }
    return XLDialogs::showSavePanel(title, defaultDir, defaultFile, fileTypes, parent);
}

/**
 * Directory dialog helper (wxDirDialog replacement).
 * @param title Dialog title
 * @param defaultPath Default directory
 * @param parent Parent window
 * @return Selected directory path, or empty string if cancelled
 */
inline std::string DirDialog(const std::string& title,
                             const std::string& defaultPath = "",
                             void* parent = nullptr) {
    return XLDialogs::showDirectoryPanel(title, defaultPath, true, parent);
}

/**
 * Progress dialog helper class (wxProgressDialog replacement).
 */
class ProgressDialog {
public:
    ProgressDialog(const std::string& title,
                   const std::string& message,
                   int maximum = 100,
                   void* parent = nullptr,
                   bool canCancel = true)
        : _dialog(XLDialogs::showProgress(title, message, maximum, canCancel, parent))
        , _maximum(maximum) {
    }

    ~ProgressDialog() {
        if (_dialog) {
            delete _dialog;
        }
    }

    bool Update(int value, const std::string& newMessage = "") {
        if (_dialog) {
            if (!newMessage.empty()) {
                _dialog->update(value, newMessage);
            } else {
                _dialog->updateProgress(value);
            }
            return !_dialog->wasCancelled();
        }
        return false;
    }

    bool Pulse(const std::string& newMessage = "") {
        if (_dialog) {
            if (!newMessage.empty()) {
                _dialog->updateMessage(newMessage);
            }
            _dialog->pulse();
            return !_dialog->wasCancelled();
        }
        return false;
    }

    bool WasCancelled() const {
        return _dialog ? _dialog->wasCancelled() : false;
    }

    void Close() {
        if (_dialog) {
            _dialog->close();
        }
    }

private:
    XLDialogs::ProgressDialog* _dialog;
    int _maximum;
};

/**
 * Number entry dialog (wxNumberEntryDialog / wxGetNumberFromUser replacement).
 * Shows a dialog with a spinner/stepper for number input.
 * @param message Prompt message
 * @param prompt Field prompt
 * @param caption Dialog title
 * @param value Initial value
 * @param min Minimum value
 * @param max Maximum value
 * @param parent Parent window
 * @return Entered value, or -1 if cancelled (check if min >= 0 to detect cancel)
 */
inline long GetNumberFromUser(const std::string& message,
                              const std::string& prompt,
                              const std::string& caption,
                              long value,
                              long min,
                              long max,
                              void* parent = nullptr) {
    return XLDialogs::showNumberEntry(caption, message, prompt, value, min, max, parent);
}

/**
 * Color picker dialog (wxColourDialog replacement).
 * @param initialColor Initial color (RGB values 0-255)
 * @param parent Parent window
 * @param outColor Output color (only valid if returns true)
 * @return true if OK was clicked, false if cancelled
 */
inline bool GetColorFromUser(unsigned char r, unsigned char g, unsigned char b,
                             void* parent,
                             unsigned char& outR, unsigned char& outG, unsigned char& outB) {
    XLDialogs::Color initial(r, g, b);
    XLDialogs::Color result;
    if (XLDialogs::showColorPicker(initial, parent, result)) {
        outR = result.r;
        outG = result.g;
        outB = result.b;
        return true;
    }
    return false;
}

/**
 * Show a "Save Changes?" dialog with Save/Don't Save/Cancel options.
 * Common pattern for unsaved changes prompts.
 * @param documentName Name of the document with unsaved changes
 * @param parent Parent window
 * @return 1 for Save, 0 for Don't Save, -1 for Cancel
 */
inline int ShowSaveChangesDialog(const std::string& documentName, void* parent = nullptr) {
    return XLDialogs::showSaveChangesDialog(documentName, parent);
}

/**
 * Show a "Delete Confirmation" dialog.
 * @param itemName Name of the item to be deleted
 * @param itemType Type of item (e.g., "model", "effect", "file")
 * @param parent Parent window
 * @return true if user confirmed deletion, false otherwise
 */
inline bool ShowDeleteConfirmation(const std::string& itemName,
                                   const std::string& itemType,
                                   void* parent = nullptr) {
    std::string message = "Are you sure you want to delete the " + itemType + " '" + itemName + "'?\n\nThis action cannot be undone.";
    return XLDialogs::showConfirmation("Confirm Delete", message, parent);
}

/**
 * Show an "Overwrite Confirmation" dialog.
 * @param fileName Name of the file that would be overwritten
 * @param parent Parent window
 * @return true if user confirmed overwrite, false otherwise
 */
inline bool ShowOverwriteConfirmation(const std::string& fileName,
                                      void* parent = nullptr) {
    std::string message = "A file named '" + fileName + "' already exists. Do you want to replace it?";
    return XLDialogs::showConfirmation("Confirm Overwrite", message, parent);
}

/**
 * Show a "Discard Changes" dialog.
 * @param parent Parent window
 * @return true if user confirmed discard, false otherwise
 */
inline bool ShowDiscardChangesConfirmation(void* parent = nullptr) {
    std::string message = "You have unsaved changes. Are you sure you want to discard them?";
    return XLDialogs::showConfirmation("Discard Changes?", message, parent);
}

} // namespace XLHelpers

// Convenience macros for drop-in replacement
#define XL_MessageBox(msg, cap, style, parent) XLHelpers::MessageBox(msg, cap, style, parent)
#define XL_DisplayError(err, parent) XLHelpers::DisplayError(err, parent)
#define XL_DisplayWarning(warn, parent) XLHelpers::DisplayWarning(warn, parent)
#define XL_DisplayInfo(info, parent) XLHelpers::DisplayInfo(info, parent)
#define XL_DisplayCrit(crit, parent) XLHelpers::DisplayCrit(crit, parent)

#endif // XLIGHTS_NATIVE_MAC

#endif // XL_DIALOG_HELPERS_H
