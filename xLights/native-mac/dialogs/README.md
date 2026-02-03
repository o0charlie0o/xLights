# Native macOS Dialogs for xLights

This directory contains native AppKit dialog implementations that replace wxWidgets dialogs in the native macOS build.

## Architecture

```
XLNativeDialogs.h/m      - Core Objective-C implementation using NSAlert, NSOpenPanel, etc.
XLDialogBridge.h/mm      - C++ bridge layer for use from C++ code
XLDialogHelpers.h        - Drop-in replacement helpers matching wxWidgets patterns
XLBaseSheetController.h/m - Base class for sheet/dialog controllers
```

## Dialog Organization

### Core Infrastructure
- **XLNativeDialogs** - Basic alert, file, and input dialogs
- **XLBaseSheetController** - Base class providing common sheet functionality
- **XLDialogBridge** - C++ bridge for calling dialogs from C++ code

### Specialized Dialog Files

| File | Purpose |
|------|---------|
| **XLSequenceDialogs** | New sequence, sequence settings, export, save changes |
| **XLMediaDialogs** | Media import, image resize, buffer size, layer select, rename |
| **XLUtilityDialogs** | Checkbox select, alignment, duplicate, timing select, viewpoint, palette management, note range, custom timing, email |
| **XLConvertDialogs** | File conversion, convert log, channel mapping, import dialogs |
| **XLModelDialogs** | Model chain, strand names, dimming curves, aliases, submodel generation, wiring, pixel test, seven segment, auto label |
| **XLColorDialog** | Extended color picker with presets and recent colors |
| **XLBatchRenderDialog** | Batch rendering configuration |
| **XLEffectTimingDialog** | Effect timing configuration |
| **XLIPEntryDialog** | IP address input with validation |
| **XLLyricsDialog** | Lyrics/phoneme editing |
| **XLNewTimingDialog** | New timing track creation |
| **XLRenderProgressDialog** | Render progress with per-model tracking |
| **XLStartChannelDialog** | Start channel configuration |
| **XLTimingImportDialog** | Timing track import from various sources |

### Complex Editor Windows (NSWindowController)
- **XLCustomModelWindow** - Custom model designer with grid editor and 3D preview
- **XLControllerModelWindow** - Controller/port configuration with drag-drop assignment
- **XLSubModelsWindow** - Submodel management with node selection
- **XLValueCurveWindow** - Value curve editor with bezier curves and presets
- **XLModelFaceWindow** - Face/mouth animation setup for lip sync
- **XLModelStateWindow** - State definitions for DMX fixtures (7-segment, custom states)
- **XLCheckSequenceReportWindow** - Sequence validation report with WKWebView

### Panels (NSView subclasses)
- **XLBufferPanel** - Buffer/layer management (buffer style, transform, RotoZoom, SubBuffer)

## Quick Migration Guide

### wxMessageBox Replacement

**Before (wxWidgets):**
```cpp
wxMessageBox("Error occurred", "Error", wxICON_ERROR | wxOK, parent);
int result = wxMessageBox("Save changes?", "Confirm", wxYES_NO | wxCANCEL, parent);
```

**After (Native macOS):**
```cpp
// Using helpers (recommended for quick migration)
XLHelpers::MessageBox("Error occurred", "Error", XL_ICON_ERROR | XL_OK, parent);
int result = XLHelpers::MessageBox("Save changes?", "Confirm", XL_YES_NO | XL_CANCEL, parent);

// Or using the C++ bridge directly
XLDialogs::showError("Error", "Error occurred", parent);
XLDialogs::AlertResult result = XLDialogs::showConfirmationWithCancel("Confirm", "Save changes?", parent);
```

### wxFileDialog Replacement

**Before (wxWidgets):**
```cpp
wxFileDialog dlg(parent, "Open Sequence", dir, "", "*.xlights;*.xsq", wxFD_OPEN);
if (dlg.ShowModal() == wxID_OK) {
    wxString path = dlg.GetPath();
}
```

**After (Native macOS):**
```cpp
std::string path = XLHelpers::FileOpenDialog("Open Sequence", dir, "", "xlights,xsq", parent);
if (!path.empty()) {
    // User selected a file
}

// Or for multiple files
std::vector<std::string> paths = XLDialogs::showOpenPanel(
    "Select Files", dir, {"xlights", "xsq"}, true, parent);
```

### wxTextEntryDialog Replacement

**Before (wxWidgets):**
```cpp
wxTextEntryDialog dlg(parent, "Enter name:", "New Group", "Group1");
if (dlg.ShowModal() == wxID_OK) {
    wxString name = dlg.GetValue();
}
```

**After (Native macOS):**
```cpp
std::string name = XLHelpers::GetTextFromUser("Enter name:", "New Group", "Group1", parent);
if (!name.empty()) {
    // User entered a name
}
```

### wxSingleChoiceDialog Replacement

**Before (wxWidgets):**
```cpp
wxArrayString choices;
choices.Add("Option A");
choices.Add("Option B");
wxSingleChoiceDialog dlg(parent, "Select option:", "Choose", choices);
dlg.SetSelection(0);
if (dlg.ShowModal() == wxID_OK) {
    int sel = dlg.GetSelection();
}
```

**After (Native macOS):**
```cpp
std::vector<std::string> choices = {"Option A", "Option B"};
int sel = XLDialogs::showSingleChoice("Choose", "Select option:", choices, 0, parent);
if (sel >= 0) {
    // User selected an option
}
```

### wxProgressDialog Replacement

**Before (wxWidgets):**
```cpp
wxProgressDialog dlg("Processing", "Please wait...", 100, parent);
for (int i = 0; i < 100; i++) {
    if (!dlg.Update(i, "Processing item " + std::to_string(i))) {
        break; // User cancelled
    }
}
```

**After (Native macOS):**
```cpp
XLHelpers::ProgressDialog dlg("Processing", "Please wait...", 100, parent, true);
for (int i = 0; i < 100; i++) {
    if (!dlg.Update(i, "Processing item " + std::to_string(i))) {
        break; // User cancelled
    }
}
// Dialog automatically closes when dlg goes out of scope
```

### wxGetNumberFromUser Replacement

**Before (wxWidgets):**
```cpp
long value = wxGetNumberFromUser("Enter count:", "Count:", "Input", 10, 1, 100, parent);
if (value != -1) {
    // User entered a value
}
```

**After (Native macOS):**
```cpp
long value = XLHelpers::GetNumberFromUser("Enter count:", "Count:", "Input", 10, 1, 100, parent);
if (value != -1) {
    // User entered a value
}
```

### wxDirDialog Replacement

**Before (wxWidgets):**
```cpp
wxDirDialog dlg(parent, "Select Folder", defaultPath);
if (dlg.ShowModal() == wxID_OK) {
    wxString path = dlg.GetPath();
}
```

**After (Native macOS):**
```cpp
std::string path = XLHelpers::DirDialog("Select Folder", defaultPath, parent);
if (!path.empty()) {
    // User selected a folder
}
```

## API Reference

### XLDialogs Namespace (C++ Bridge)

#### Alert Dialogs
- `showAlert(title, message, style, buttons, parent)` - Full alert dialog
- `showError(title, message, parent)` - Error alert
- `showWarning(title, message, parent)` - Warning alert
- `showInfo(title, message, parent)` - Informational alert
- `showConfirmation(title, message, parent)` - Yes/No confirmation
- `showConfirmationWithCancel(title, message, parent)` - Yes/No/Cancel

#### File Dialogs
- `showOpenPanel(title, directory, fileTypes, allowMultiple, parent)` - Open file(s)
- `showOpenPanelSingle(title, directory, fileTypes, parent)` - Open single file
- `showSavePanel(title, directory, defaultName, fileTypes, parent)` - Save file
- `showDirectoryPanel(title, directory, canCreate, parent)` - Choose directory

#### Text Input Dialogs
- `showTextInput(title, message, defaultValue, placeholder, parent, outValue)` - Text entry
- `showTextInput(title, message, defaultValue, parent)` - Simple text entry
- `showSecureTextInput(title, message, placeholder, parent)` - Password entry

#### Choice Dialogs
- `showSingleChoice(title, message, choices, defaultSelection, parent)` - Single selection
- `showSingleChoiceString(...)` - Returns selected string
- `showMultiChoice(title, message, choices, initial, parent, outSelections)` - Multi-selection

#### Number Entry
- `showNumberEntry(title, message, prompt, value, min, max, parent)` - Number input

#### Progress Dialogs
- `showProgress(title, message, maximum, canCancel, parent)` - Returns ProgressDialog*

#### Color Dialogs
- `showColorPicker(initialColor, parent, outColor)` - Color selection

#### Save Changes
- `showSaveChangesDialog(documentName, parent)` - Save/Don't Save/Cancel

### XLHelpers Namespace (wxWidgets-style API)

Provides drop-in replacements with similar signatures to wxWidgets functions:

- `MessageBox(message, caption, style, parent)` - wxMessageBox replacement
- `DisplayError/Warning/Info/Crit(message, parent)` - UtilFunctions replacements
- `GetTextFromUser(message, caption, defaultValue, parent)` - Text input
- `GetSingleChoice(message, caption, choices, default, parent)` - Choice dialog
- `GetMultipleChoices(message, caption, choices, selections, parent)` - Multi-choice
- `GetNumberFromUser(message, prompt, caption, value, min, max, parent)` - Number input
- `FileOpenDialog(title, dir, file, wildcard, parent)` - Open file
- `FileSaveDialog(title, dir, file, wildcard, parent)` - Save file
- `DirDialog(title, defaultPath, parent)` - Directory selection
- `GetColorFromUser(r, g, b, parent, outR, outG, outB)` - Color picker
- `ShowSaveChangesDialog(documentName, parent)` - Save changes dialog
- `ShowDeleteConfirmation(itemName, itemType, parent)` - Delete confirmation
- `ShowOverwriteConfirmation(fileName, parent)` - Overwrite confirmation
- `ShowDiscardChangesConfirmation(parent)` - Discard changes confirmation

## Style Constants

The helper macros use constants matching wxWidgets values:

**Buttons:**
- `XL_OK`, `XL_CANCEL`, `XL_YES`, `XL_NO`
- `XL_OK_CANCEL`, `XL_YES_NO`, `XL_YES_NO_CANCEL`

**Icons:**
- `XL_ICON_ERROR`, `XL_ICON_WARNING`, `XL_ICON_QUESTION`, `XL_ICON_INFORMATION`

**Return Values:**
- `XL_ID_OK`, `XL_ID_CANCEL`, `XL_ID_YES`, `XL_ID_NO`

## Threading Considerations

All dialog functions must be called from the main thread. The implementation handles blocking appropriately using dispatch semaphores when presenting as sheets.

## Parent Window

All dialog functions accept an optional parent window parameter. When provided:
- Dialogs appear as sheets attached to the parent window
- The parent window is blocked while the dialog is visible

When null:
- Dialogs appear as standalone modal windows
- The entire application is blocked

## Converting from wxWidgets

1. Include `XLDialogHelpers.h` in files that need dialog functionality
2. Define `XLIGHTS_NATIVE_MAC` preprocessor macro for native builds
3. Replace wxWidgets calls with XLHelpers equivalents
4. Adjust parent window handling (convert wxWindow* to void* using native handle)

For new code, consider using the `XLDialogs` namespace directly for cleaner, more native-style code.
