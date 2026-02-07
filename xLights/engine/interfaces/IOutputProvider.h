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

// IOutputProvider: Abstract interface for output/controller access.
//
// This interface allows engines to access controller and output information
// without direct dependency on xLightsFrame or wxWidgets types.
//
// Design principles:
// - Pure virtual interface (no implementation)
// - Uses ONLY std:: types (no wxString, wxColour, etc.)
// - Thread-safe design (implementations must be thread-safe)
// - Supports gradual migration via getOutputManager() escape hatch
//
// See: DECOUPLING_GUIDE.md for the overall decoupling strategy.

#include <string>
#include <vector>
#include <cstdint>
#include <optional>

// Forward declaration for the migration escape hatch
class OutputManager;

namespace xlEngine {

// Controller connection type
enum class OutputControllerType {
    Ethernet,
    Serial,
    Null
};

// Basic controller info struct using only std:: types.
// This is a simplified view of controller data for the interface.
// For full configuration, use the ControllerConfig struct in OutputEngine.h.
struct ControllerInfo {
    std::string name;
    std::string description;
    int id = 0;

    // Connection info
    OutputControllerType type = OutputControllerType::Ethernet;
    std::string ip;                 // For Ethernet controllers
    std::string commPort;           // For Serial controllers
    std::string protocol;           // e.g., "E131", "ArtNet", "DDP", "DMX"
    std::string fppProxy;
    std::string forceLocalIP;

    // Hardware identification
    std::string vendor;
    std::string model;
    std::string variant;

    // Channel configuration
    int32_t startChannel = -1;
    int32_t endChannel = -1;
    int32_t channels = 0;
    int outputCount = 0;
    int priority = 100;

    // State
    bool active = true;
    bool autoLayout = true;
    bool autoSize = true;
    bool managed = true;
    bool autoUpload = false;
    bool fullxLightsControl = false;
    int defaultBrightness = 100;
    float defaultGamma = 1.0f;
    bool suppressDuplicateFrames = false;
    bool monitor = true;
    bool fromBase = false;
    bool universePerString = false;
    std::string activeState;        // "Active", "Inactive", "xLights Only"
};

// Abstract interface for output/controller access.
// Implementations must be thread-safe.
class IOutputProvider {
public:
    virtual ~IOutputProvider() = default;

    // ============================================================
    // Controller enumeration
    // ============================================================

    // Get the number of configured controllers
    virtual size_t getControllerCount() const = 0;

    // Get controller info by index (0-based)
    // Returns std::nullopt if index is out of range
    virtual std::optional<ControllerInfo> getController(size_t index) const = 0;

    // Get controller info by name
    // Returns std::nullopt if no controller with that name exists
    virtual std::optional<ControllerInfo> getControllerByName(const std::string& name) const = 0;

    // Get all controller names
    virtual std::vector<std::string> getControllerNames() const = 0;

    // Check if a controller with the given name exists
    virtual bool controllerExists(const std::string& name) const = 0;

    // ============================================================
    // Output state
    // ============================================================

    // Check if output is currently active (sending data to controllers)
    virtual bool isOutputting() const = 0;

    // Start output to controllers
    // Returns true if output was successfully started
    virtual bool startOutput() = 0;

    // Stop output to controllers
    virtual void stopOutput() = 0;

    // ============================================================
    // Channel information
    // ============================================================

    // Get total channel count across all controllers
    virtual int32_t getTotalChannels() const = 0;

    // ============================================================
    // Migration escape hatch
    // ============================================================

    // Get raw pointer to OutputManager for gradual migration.
    // This allows existing code to continue working while we migrate.
    // New code should prefer the interface methods above.
    //
    // IMPORTANT: This method is temporary and will be removed once
    // all code is migrated to use the interface methods.
    //
    // Returns nullptr if no OutputManager is available (e.g., in native-only builds).
    virtual OutputManager* getOutputManager() = 0;
    virtual const OutputManager* getOutputManager() const = 0;
};

} // namespace xlEngine
