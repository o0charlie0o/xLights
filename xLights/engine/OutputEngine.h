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

// OutputEngine: Pure C++ API for controller/output management.
// No wxWidgets types cross this boundary.
// Thread-safe for async operations (discovery, upload, ping).

#include <string>
#include <vector>
#include <map>
#include <functional>
#include <mutex>
#include <cstdint>
#include <memory>
#include <atomic>

class OutputManager;
class Controller;

namespace xlEngine {

// Ping / connectivity state
enum class PingState {
    OK,
    WebOK,
    Open,
    Opened,
    AllFailed,
    Unavailable,
    Unknown
};

// Controller active state
enum class ActiveState {
    Active,
    Inactive,
    ActiveInXLightsOnly
};

// Controller connection type
enum class ControllerType {
    Ethernet,
    Serial,
    Null
};

// Output protocol info
struct ProtocolInfo {
    std::string name;           // e.g. "E131", "ArtNet", "DDP", "DMX"
    bool isEthernet = false;
    bool isSerial = false;
    int maxChannels = 0;
};

// Represents a single output universe/port on a controller
struct OutputInfo {
    std::string protocol;       // e.g. "E131", "ArtNet", "DDP"
    std::string ip;
    int universe = 0;
    int32_t channels = 0;
    int32_t startChannel = -1;
    bool enabled = true;
    std::string fppProxy;
    std::string forceLocalIP;
    bool suppressDuplicateFrames = false;
};

// Port configuration for controller upload
struct PortConfig {
    int portNumber = 0;
    std::string protocol;
    int32_t startChannel = 0;
    int32_t channels = 0;
    int brightness = 100;
    float gamma = 1.0f;
    int nullPixels = 0;
    int endNullPixels = 0;
    std::string colorOrder;
    int groupCount = 1;
    bool reverse = false;
    int zigZag = 0;
    std::string smartRemoteType;
    std::map<std::string, std::string> extraProperties;
};

// Controller capabilities summary (derived from ControllerCaps)
struct ControllerCapabilities {
    bool supportsUpload = false;
    bool supportsInputOnlyUpload = false;
    bool supportsAutoLayout = false;
    bool supportsAutoUpload = false;
    bool supportsAutoSize = false;
    bool supportsFullxLightsControl = false;
    bool supportsPixelPortBrightness = false;
    bool supportsPixelPortGamma = false;
    bool supportsDefaultBrightness = false;
    bool supportsDefaultGamma = false;
    bool supportsSmartRemotes = false;
    bool supportsVirtualStrings = false;
    bool supportsUniversePerString = false;
    bool supportsLEDPanelMatrix = false;
    bool supportsVirtualMatrix = false;
    int maxPixelPort = 0;
    int maxSerialPort = 0;
    int maxPixelPortChannels = 0;
    int maxSerialPortChannels = 0;
    int maxInputE131Universes = 0;
    int smartRemoteCount = 0;
    std::vector<std::string> pixelProtocols;
    std::vector<std::string> serialProtocols;
    std::vector<std::string> inputProtocols;
};

// Full controller configuration
struct ControllerConfig {
    // Identity
    std::string name;
    std::string description;
    int id = 0;
    ControllerType type = ControllerType::Ethernet;

    // Connection
    std::string ip;                 // Ethernet controllers
    std::string commPort;           // Serial controllers
    int baudRate = 0;               // Serial controllers
    std::string protocol;           // "E131", "ArtNet", "DDP", "DMX", etc.
    std::string fppProxy;
    std::string forceLocalIP;

    // Hardware identification
    std::string vendor;
    std::string model;
    std::string variant;

    // Configuration
    ActiveState active = ActiveState::Active;
    bool autoLayout = true;
    bool autoSize = true;
    bool autoUpload = false;
    bool fullxLightsControl = true;
    int defaultBrightness = 100;
    float defaultGamma = 1.0f;
    bool suppressDuplicateFrames = false;
    bool monitor = true;
    bool managed = true;
    bool fromBase = false;

    // Ethernet-specific
    int priority = 100;
    int version = 1;
    bool universePerString = false;

    // Serial-specific
    std::string prefix;
    std::string postfix;

    // Channels
    int32_t startChannel = -1;
    int32_t endChannel = -1;
    int32_t channels = 0;
    int outputCount = 0;

    // State
    PingState lastPingState = PingState::Unknown;

    // Outputs on this controller
    std::vector<OutputInfo> outputs;

    // Extra properties
    std::map<std::string, std::string> extraProperties;
};

// Discovered controller info (from network discovery)
struct DiscoveredController {
    std::string ip;
    std::string hostname;
    std::string vendor;
    std::string model;
    std::string variant;
    std::string description;
    std::string version;
    std::string mode;               // "bridge", "player", etc.
    std::string platform;
    std::string platformModel;
    std::string uuid;
    std::string proxy;
    int majorVersion = 0;
    int minorVersion = 0;
    int patchVersion = 0;
    bool alreadyConfigured = false; // true if already in our controller list
    std::string existingName;       // name of matching existing controller, if any
};

// Callback types for async operations
using DiscoveryCallback = std::function<void(bool success, const std::vector<DiscoveredController>& controllers)>;
using UploadCallback = std::function<void(bool success, const std::string& message)>;
using PingCallback = std::function<void(const std::string& controllerId, PingState state)>;
using ErrorCallback = std::function<void(const std::string& message)>;

// Result type for operations that can fail
struct OperationResult {
    bool success = false;
    std::string message;
};

class OutputEngine {
public:
    OutputEngine();
    ~OutputEngine();

    // Initialization - must be called before use
    // The OutputEngine wraps the existing OutputManager. It does not own it.
    void initialize(OutputManager* outputManager);

    // Controller enumeration
    std::vector<ControllerConfig> getControllers() const;
    ControllerConfig getController(const std::string& name) const;
    bool controllerExists(const std::string& name) const;
    int getControllerCount() const;
    std::vector<std::string> getControllerNames() const;

    // Controller CRUD
    OperationResult addController(const ControllerConfig& config);
    OperationResult removeController(const std::string& name);
    OperationResult updateController(const std::string& name, const ControllerConfig& config);

    // Port configuration
    std::vector<PortConfig> getControllerPorts(const std::string& name) const;
    OperationResult setPortConfig(const std::string& name, int port, const PortConfig& config);

    // Controller capabilities
    ControllerCapabilities getControllerCapabilities(const std::string& name) const;

    // Protocol information
    std::vector<ProtocolInfo> getOutputProtocols() const;
    std::vector<std::string> getVendors(const std::string& controllerType) const;
    std::vector<std::string> getModels(const std::string& controllerType, const std::string& vendor) const;
    std::vector<std::string> getVariants(const std::string& controllerType, const std::string& vendor, const std::string& model) const;

    // Connectivity testing (async)
    void testController(const std::string& name, PingCallback callback);
    void testAllControllers(PingCallback callback);
    PingState getLastPingState(const std::string& name) const;

    // Network discovery (async)
    void discoverControllers(DiscoveryCallback callback);
    OperationResult addDiscoveredController(const DiscoveredController& discovered);

    // Upload to controller (async)
    void uploadInputToController(const std::string& name, UploadCallback callback);
    void uploadOutputToController(const std::string& name, UploadCallback callback);
    void uploadToController(const std::string& name, UploadCallback callback);

    // Output control
    bool startOutput();
    void stopOutput();
    bool isOutputting() const;

    // Ordering
    void sortControllersByName();
    void sortControllersByID();
    void sortControllersByIP();

    // Dirty state
    bool isDirty() const;
    OperationResult save();

    // Global settings
    std::string getGlobalFPPProxy() const;
    void setGlobalFPPProxy(const std::string& proxy);
    std::string getGlobalForceLocalIP() const;
    void setGlobalForceLocalIP(const std::string& ip);

    int getSuppressFrames() const;
    void setSuppressFrames(int frames);

    bool isParallelTransmission() const;
    void setParallelTransmission(bool parallel);

    // Channel info
    int32_t getTotalChannels() const;

    // Error callback registration
    void setErrorCallback(ErrorCallback callback);

private:
    // Convert between internal types and engine API types
    ControllerConfig controllerToConfig(Controller* c) const;
    void applyConfigToController(Controller* c, const ControllerConfig& config) const;
    static PingState convertPingState(int internalState);
    static ActiveState convertActiveState(int internalState);
    static std::string activeStateToString(ActiveState state);

    Controller* findController(const std::string& name) const;

    // Internal versions of public methods that assume the lock is already held
    OperationResult addControllerInternal(const ControllerConfig& config);

    OutputManager* _outputManager = nullptr;
    mutable std::recursive_mutex _mutex;
    ErrorCallback _errorCallback;
    std::atomic<bool> _initialized{false};
};

} // namespace xlEngine
