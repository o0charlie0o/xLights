/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Check if -nativeUI flag is present and launch the native macOS window.
/// Call from xLightsApp::OnInit() after the wxWidgets frame is created.
/// Returns 1 if the native window was launched, 0 otherwise.
int XLTryLaunchNativeWindow(void);

#ifdef __cplusplus
}
#endif
