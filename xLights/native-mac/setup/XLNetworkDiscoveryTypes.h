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

/// C-compatible struct for discovered controller data.
/// Uses fixed-size char arrays instead of NSString/std::string to avoid
/// heap corruption issues when wxWidgets/C++ interacts with ObjC runtime.
typedef struct XLDiscoveredController {
    char ip[46];              // IPv4 or IPv6 address
    char hostname[256];       // Resolved hostname
    char mac[18];             // MAC address (XX:XX:XX:XX:XX:XX)
    char vendor[64];          // Controller vendor (e.g., "Falcon")
    char model[64];           // Controller model (e.g., "F48")
    char variant[64];         // Controller variant
    char description[256];    // User-friendly description
    char version[32];         // Firmware version string
    char mode[32];            // Controller mode (bridge, player, etc.)
    char platform[64];        // Platform type
    char platformModel[64];   // Platform model
    char uuid[64];            // Unique identifier
    char proxy[256];          // FPP proxy address if any
    int majorVersion;         // Firmware major version
    int minorVersion;         // Firmware minor version
    int patchVersion;         // Firmware patch version
    int alreadyConfigured;    // 1 if controller is already in our config
    char existingName[256];   // Name of matching existing controller
} XLDiscoveredController;

/// Maximum number of discovered controllers we can store.
/// Using a fixed array size to avoid heap allocation issues.
#define XL_MAX_DISCOVERED_CONTROLLERS 256

/// C-compatible struct for MAC vendor lookup entry.
typedef struct XLMacVendorEntry {
    char prefix[7];           // First 6 hex digits of MAC (no separators)
    char vendor[128];         // Vendor name
} XLMacVendorEntry;

/// Maximum number of MAC vendor entries.
#define XL_MAX_MAC_VENDORS 32768

/// Discovery state enum.
typedef enum XLDiscoveryState {
    XLDiscoveryStateIdle = 0,
    XLDiscoveryStateScanning,
    XLDiscoveryStateComplete,
    XLDiscoveryStateFailed
} XLDiscoveryState;

/// Ping state enum (matches xlEngine::PingState).
typedef enum XLPingState {
    XLPingStateOK = 0,
    XLPingStateWebOK,
    XLPingStateOpen,
    XLPingStateOpened,
    XLPingStateAllFailed,
    XLPingStateUnavailable,
    XLPingStateUnknown
} XLPingState;

/// Helper to copy a string safely into a fixed-size buffer.
static inline void xl_safe_strcpy(char *dest, size_t destSize, const char *src) {
    if (!dest || destSize == 0) return;
    if (!src) {
        dest[0] = '\0';
        return;
    }
    size_t srcLen = strlen(src);
    size_t copyLen = (srcLen < destSize - 1) ? srcLen : destSize - 1;
    memcpy(dest, src, copyLen);
    dest[copyLen] = '\0';
}

/// Initialize a discovered controller struct to empty state.
static inline void xl_init_discovered_controller(XLDiscoveredController *dc) {
    if (!dc) return;
    memset(dc, 0, sizeof(XLDiscoveredController));
}
