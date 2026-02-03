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

/// User defaults key for the native UI feature flag
extern const char* XLNativeUIEnabledKey;

/// Check if native UI is enabled via preference or -nativeUI flag and launch it.
/// Call from xLightsApp::OnInit() after the wxWidgets frame is created.
/// Returns 1 if the native window was launched, 0 otherwise.
int XLTryLaunchNativeWindow(void);

/// Check if native UI feature flag is enabled in user defaults.
/// Returns 1 if enabled, 0 if disabled.
int XLIsNativeUIEnabled(void);

/// Set the native UI feature flag in user defaults.
/// Pass 1 to enable, 0 to disable.
void XLSetNativeUIEnabled(int enabled);

#ifdef __cplusplus
}
#endif
