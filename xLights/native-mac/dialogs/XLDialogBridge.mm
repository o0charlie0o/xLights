/***************************************************************
 * Name:      XLDialogBridge.mm
 * Purpose:   C++ bridge to native macOS dialogs - Implementation
 * Author:    xLights Team
 * Created:   2026-02-03
 * Copyright: xLights (https://xlights.org)
 * License:   GPLv3
 **************************************************************/

#import "XLDialogBridge.h"
#import "XLNativeDialogs.h"

namespace XLDialogs {

#pragma mark - Helper Functions

static NSString* toNSString(const std::string& str) {
    return [NSString stringWithUTF8String:str.c_str()];
}

static std::string toStdString(NSString* str) {
    return str ? std::string([str UTF8String]) : std::string();
}

static NSArray<NSString*>* toNSArray(const std::vector<std::string>& vec) {
    NSMutableArray<NSString*>* array = [NSMutableArray arrayWithCapacity:vec.size()];
    for (const auto& str : vec) {
        [array addObject:toNSString(str)];
    }
    return array;
}

static NSArray<NSNumber*>* toNSNumberArray(const std::vector<int>& vec) {
    NSMutableArray<NSNumber*>* array = [NSMutableArray arrayWithCapacity:vec.size()];
    for (int val : vec) {
        [array addObject:@(val)];
    }
    return array;
}

static XLAlertStyle toNativeStyle(AlertStyle style) {
    switch (style) {
        case AlertStyle::Informational: return XLAlertStyleInformational;
        case AlertStyle::Warning: return XLAlertStyleWarning;
        case AlertStyle::Critical: return XLAlertStyleCritical;
        case AlertStyle::Question: return XLAlertStyleQuestion;
    }
    return XLAlertStyleInformational;
}

static XLAlertButtons toNativeButtons(AlertButtons buttons) {
    switch (buttons) {
        case AlertButtons::OK: return XLAlertButtonsOK;
        case AlertButtons::OKCancel: return XLAlertButtonsOKCancel;
        case AlertButtons::YesNo: return XLAlertButtonsYesNo;
        case AlertButtons::YesNoCancel: return XLAlertButtonsYesNoCancel;
    }
    return XLAlertButtonsOK;
}

static AlertResult fromNativeResult(XLAlertResult result) {
    switch (result) {
        case XLAlertResultOK: return AlertResult::OK;
        case XLAlertResultCancel: return AlertResult::Cancel;
        case XLAlertResultYes: return AlertResult::Yes;
        case XLAlertResultNo: return AlertResult::No;
    }
    return AlertResult::Cancel;
}

#pragma mark - Alert Dialogs

AlertResult showAlert(const std::string& title,
                      const std::string& message,
                      AlertStyle style,
                      AlertButtons buttons,
                      void* parentWindow) {
    @autoreleasepool {
        XLAlertResult result = [XLNativeDialogs showAlertWithTitle:toNSString(title)
                                                           message:toNSString(message)
                                                             style:toNativeStyle(style)
                                                           buttons:toNativeButtons(buttons)
                                                      parentWindow:(__bridge NSWindow*)parentWindow];
        return fromNativeResult(result);
    }
}

void showError(const std::string& title,
               const std::string& message,
               void* parentWindow) {
    @autoreleasepool {
        [XLNativeDialogs showErrorWithTitle:toNSString(title)
                                    message:toNSString(message)
                               parentWindow:(__bridge NSWindow*)parentWindow];
    }
}

void showWarning(const std::string& title,
                 const std::string& message,
                 void* parentWindow) {
    @autoreleasepool {
        [XLNativeDialogs showWarningWithTitle:toNSString(title)
                                      message:toNSString(message)
                                 parentWindow:(__bridge NSWindow*)parentWindow];
    }
}

void showInfo(const std::string& title,
              const std::string& message,
              void* parentWindow) {
    @autoreleasepool {
        [XLNativeDialogs showInfoWithTitle:toNSString(title)
                                   message:toNSString(message)
                              parentWindow:(__bridge NSWindow*)parentWindow];
    }
}

bool showConfirmation(const std::string& title,
                      const std::string& message,
                      void* parentWindow) {
    @autoreleasepool {
        return [XLNativeDialogs showConfirmationWithTitle:toNSString(title)
                                                  message:toNSString(message)
                                             parentWindow:(__bridge NSWindow*)parentWindow];
    }
}

AlertResult showConfirmationWithCancel(const std::string& title,
                                       const std::string& message,
                                       void* parentWindow) {
    @autoreleasepool {
        XLAlertResult result = [XLNativeDialogs showConfirmationWithCancelTitle:toNSString(title)
                                                                        message:toNSString(message)
                                                                   parentWindow:(__bridge NSWindow*)parentWindow];
        return fromNativeResult(result);
    }
}

#pragma mark - File Dialogs

std::vector<std::string> showOpenPanel(const std::string& title,
                                       const std::string& directory,
                                       const std::vector<std::string>& fileTypes,
                                       bool allowMultiple,
                                       void* parentWindow) {
    @autoreleasepool {
        NSArray<NSURL*>* urls = [XLNativeDialogs showOpenPanelWithTitle:toNSString(title)
                                                              directory:directory.empty() ? nil : toNSString(directory)
                                                              fileTypes:fileTypes.empty() ? nil : toNSArray(fileTypes)
                                                          allowMultiple:allowMultiple
                                                           parentWindow:(__bridge NSWindow*)parentWindow];

        std::vector<std::string> result;
        if (urls) {
            for (NSURL* url in urls) {
                result.push_back(toStdString(url.path));
            }
        }
        return result;
    }
}

std::string showOpenPanelSingle(const std::string& title,
                                const std::string& directory,
                                const std::vector<std::string>& fileTypes,
                                void* parentWindow) {
    std::vector<std::string> paths = showOpenPanel(title, directory, fileTypes, false, parentWindow);
    return paths.empty() ? std::string() : paths[0];
}

std::string showSavePanel(const std::string& title,
                          const std::string& directory,
                          const std::string& defaultName,
                          const std::vector<std::string>& fileTypes,
                          void* parentWindow) {
    @autoreleasepool {
        NSURL* url = [XLNativeDialogs showSavePanelWithTitle:toNSString(title)
                                                   directory:directory.empty() ? nil : toNSString(directory)
                                                 defaultName:defaultName.empty() ? nil : toNSString(defaultName)
                                                   fileTypes:fileTypes.empty() ? nil : toNSArray(fileTypes)
                                                parentWindow:(__bridge NSWindow*)parentWindow];

        return url ? toStdString(url.path) : std::string();
    }
}

std::string showDirectoryPanel(const std::string& title,
                               const std::string& directory,
                               bool canCreateDirectories,
                               void* parentWindow) {
    @autoreleasepool {
        NSURL* url = [XLNativeDialogs showDirectoryPanelWithTitle:toNSString(title)
                                                        directory:directory.empty() ? nil : toNSString(directory)
                                             canCreateDirectories:canCreateDirectories
                                                     parentWindow:(__bridge NSWindow*)parentWindow];

        return url ? toStdString(url.path) : std::string();
    }
}

#pragma mark - Text Input Dialogs

bool showTextInput(const std::string& title,
                   const std::string& message,
                   const std::string& defaultValue,
                   const std::string& placeholder,
                   void* parentWindow,
                   std::string& outValue) {
    @autoreleasepool {
        NSString* result = [XLNativeDialogs showTextInputWithTitle:toNSString(title)
                                                           message:toNSString(message)
                                                      defaultValue:defaultValue.empty() ? nil : toNSString(defaultValue)
                                                       placeholder:placeholder.empty() ? nil : toNSString(placeholder)
                                                      parentWindow:(__bridge NSWindow*)parentWindow];

        if (result) {
            outValue = toStdString(result);
            return true;
        }
        return false;
    }
}

std::string showTextInput(const std::string& title,
                          const std::string& message,
                          const std::string& defaultValue,
                          void* parentWindow) {
    std::string result;
    if (showTextInput(title, message, defaultValue, "", parentWindow, result)) {
        return result;
    }
    return std::string();
}

std::string showSecureTextInput(const std::string& title,
                                const std::string& message,
                                const std::string& placeholder,
                                void* parentWindow) {
    @autoreleasepool {
        NSString* result = [XLNativeDialogs showSecureTextInputWithTitle:toNSString(title)
                                                                 message:toNSString(message)
                                                             placeholder:placeholder.empty() ? nil : toNSString(placeholder)
                                                            parentWindow:(__bridge NSWindow*)parentWindow];

        return result ? toStdString(result) : std::string();
    }
}

#pragma mark - Choice Dialogs

int showSingleChoice(const std::string& title,
                     const std::string& message,
                     const std::vector<std::string>& choices,
                     int defaultSelection,
                     void* parentWindow) {
    @autoreleasepool {
        NSInteger result = [XLNativeDialogs showSingleChoiceWithTitle:toNSString(title)
                                                              message:toNSString(message)
                                                              choices:toNSArray(choices)
                                                     defaultSelection:defaultSelection
                                                         parentWindow:(__bridge NSWindow*)parentWindow];
        return (int)result;
    }
}

bool showSingleChoiceString(const std::string& title,
                            const std::string& message,
                            const std::vector<std::string>& choices,
                            int defaultSelection,
                            void* parentWindow,
                            std::string& outSelection) {
    @autoreleasepool {
        NSString* result = [XLNativeDialogs showSingleChoiceStringWithTitle:toNSString(title)
                                                                    message:toNSString(message)
                                                                    choices:toNSArray(choices)
                                                           defaultSelection:defaultSelection
                                                               parentWindow:(__bridge NSWindow*)parentWindow];

        if (result) {
            outSelection = toStdString(result);
            return true;
        }
        return false;
    }
}

bool showMultiChoice(const std::string& title,
                     const std::string& message,
                     const std::vector<std::string>& choices,
                     const std::vector<int>& initialSelections,
                     void* parentWindow,
                     std::vector<int>& outSelections) {
    @autoreleasepool {
        NSArray<NSNumber*>* result = [XLNativeDialogs showMultiChoiceWithTitle:toNSString(title)
                                                                       message:toNSString(message)
                                                                       choices:toNSArray(choices)
                                                            initialSelections:toNSNumberArray(initialSelections)
                                                                  parentWindow:(__bridge NSWindow*)parentWindow];

        if (result) {
            outSelections.clear();
            for (NSNumber* num in result) {
                outSelections.push_back(num.intValue);
            }
            return true;
        }
        return false;
    }
}

#pragma mark - Progress Dialogs

ProgressDialog::ProgressDialog(void* controller) : _controller(controller) {
    // Retain the controller
    CFRetain(_controller);
}

ProgressDialog::~ProgressDialog() {
    close();
    if (_controller) {
        CFRelease(_controller);
        _controller = nullptr;
    }
}

void ProgressDialog::updateProgress(unsigned int value) {
    @autoreleasepool {
        [(__bridge XLProgressController*)_controller updateProgress:value];
    }
}

void ProgressDialog::updateMessage(const std::string& message) {
    @autoreleasepool {
        [(__bridge XLProgressController*)_controller updateMessage:toNSString(message)];
    }
}

void ProgressDialog::update(unsigned int value, const std::string& message) {
    @autoreleasepool {
        [(__bridge XLProgressController*)_controller updateProgress:value message:toNSString(message)];
    }
}

void ProgressDialog::setIndeterminate(bool indeterminate) {
    @autoreleasepool {
        [(__bridge XLProgressController*)_controller setIndeterminate:indeterminate];
    }
}

bool ProgressDialog::wasCancelled() const {
    @autoreleasepool {
        return ((__bridge XLProgressController*)_controller).wasCancelled;
    }
}

void ProgressDialog::close() {
    @autoreleasepool {
        [(__bridge XLProgressController*)_controller close];
    }
}

void ProgressDialog::pulse() {
    @autoreleasepool {
        [(__bridge XLProgressController*)_controller pulse];
    }
}

ProgressDialog* showProgress(const std::string& title,
                             const std::string& message,
                             unsigned int maximum,
                             bool canCancel,
                             void* parentWindow) {
    @autoreleasepool {
        XLProgressController* controller = [XLNativeDialogs showProgressWithTitle:toNSString(title)
                                                                          message:toNSString(message)
                                                                          maximum:maximum
                                                                        canCancel:canCancel
                                                                     parentWindow:(__bridge NSWindow*)parentWindow];

        return new ProgressDialog((__bridge void*)controller);
    }
}

#pragma mark - Color Dialogs

bool showColorPicker(const Color& initialColor,
                     void* parentWindow,
                     Color& outColor) {
    @autoreleasepool {
        NSColor* initial = [NSColor colorWithRed:initialColor.r / 255.0
                                           green:initialColor.g / 255.0
                                            blue:initialColor.b / 255.0
                                           alpha:initialColor.a / 255.0];

        NSColor* result = [XLNativeDialogs showColorPickerWithInitialColor:initial
                                                              parentWindow:(__bridge NSWindow*)parentWindow];

        if (result) {
            // Convert to RGB color space if needed
            NSColor* rgbColor = [result colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
            if (rgbColor) {
                outColor.r = (unsigned char)(rgbColor.redComponent * 255);
                outColor.g = (unsigned char)(rgbColor.greenComponent * 255);
                outColor.b = (unsigned char)(rgbColor.blueComponent * 255);
                outColor.a = (unsigned char)(rgbColor.alphaComponent * 255);
                return true;
            }
        }
        return false;
    }
}

#pragma mark - Number Entry Dialogs

bool showNumberEntry(const std::string& title,
                     const std::string& message,
                     const std::string& prompt,
                     long value,
                     long min,
                     long max,
                     void* parentWindow,
                     long& outValue) {
    @autoreleasepool {
        NSInteger result;
        BOOL ok = [XLNativeDialogs showNumberEntryWithTitle:toNSString(title)
                                                    message:toNSString(message)
                                                     prompt:toNSString(prompt)
                                                      value:value
                                                        min:min
                                                        max:max
                                               parentWindow:(__bridge NSWindow*)parentWindow
                                                   outValue:&result];

        if (ok) {
            outValue = (long)result;
            return true;
        }
        return false;
    }
}

long showNumberEntry(const std::string& title,
                     const std::string& message,
                     const std::string& prompt,
                     long value,
                     long min,
                     long max,
                     void* parentWindow) {
    long result;
    if (showNumberEntry(title, message, prompt, value, min, max, parentWindow, result)) {
        return result;
    }
    return -1;
}

#pragma mark - Save Changes Dialogs

int showSaveChangesDialog(const std::string& documentName, void* parentWindow) {
    @autoreleasepool {
        return (int)[XLNativeDialogs showSaveChangesDialogForDocument:toNSString(documentName)
                                                         parentWindow:(__bridge NSWindow*)parentWindow];
    }
}

} // namespace XLDialogs
