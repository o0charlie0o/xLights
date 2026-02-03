/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "OutputEngine.h"

#include "../outputs/OutputManager.h"
#include "../outputs/Controller.h"
#include "../outputs/ControllerEthernet.h"
#include "../outputs/ControllerSerial.h"
#include "../outputs/ControllerNull.h"
#include "../outputs/Output.h"
#include "../outputs/IPOutput.h"
#include "../controllers/ControllerCaps.h"

#include <algorithm>
#include <thread>

namespace xlEngine {

OutputEngine::OutputEngine() = default;
OutputEngine::~OutputEngine() = default;

void OutputEngine::initialize(OutputManager* outputManager) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    _outputManager = outputManager;
    _initialized = true;
}

// Convert from Output::PINGSTATE to our PingState enum
PingState OutputEngine::convertPingState(int internalState) {
    switch (static_cast<Output::PINGSTATE>(internalState)) {
    case Output::PINGSTATE::PING_OK:          return PingState::OK;
    case Output::PINGSTATE::PING_WEBOK:       return PingState::WebOK;
    case Output::PINGSTATE::PING_OPEN:        return PingState::Open;
    case Output::PINGSTATE::PING_OPENED:      return PingState::Opened;
    case Output::PINGSTATE::PING_ALLFAILED:   return PingState::AllFailed;
    case Output::PINGSTATE::PING_UNAVAILABLE: return PingState::Unavailable;
    case Output::PINGSTATE::PING_UNKNOWN:
    default:                                  return PingState::Unknown;
    }
}

// Convert from Controller::ACTIVESTATE to our ActiveState enum
ActiveState OutputEngine::convertActiveState(int internalState) {
    switch (static_cast<Controller::ACTIVESTATE>(internalState)) {
    case Controller::ACTIVESTATE::ACTIVE:             return ActiveState::Active;
    case Controller::ACTIVESTATE::INACTIVE:           return ActiveState::Inactive;
    case Controller::ACTIVESTATE::ACTIVEINXLIGHTSONLY: return ActiveState::ActiveInXLightsOnly;
    default:                                          return ActiveState::Active;
    }
}

std::string OutputEngine::activeStateToString(ActiveState state) {
    switch (state) {
    case ActiveState::Active:             return "Active";
    case ActiveState::Inactive:           return "Inactive";
    case ActiveState::ActiveInXLightsOnly: return "xLights Only";
    default:                              return "Active";
    }
}

Controller* OutputEngine::findController(const std::string& name) const {
    if (!_outputManager) return nullptr;
    return _outputManager->GetController(name);
}

ControllerConfig OutputEngine::controllerToConfig(Controller* c) const {
    if (!c) return {};

    ControllerConfig config;

    config.name = c->GetName();
    config.description = c->GetDescription();
    config.id = c->GetId();

    auto typeStr = c->GetType();
    if (typeStr == CONTROLLER_ETHERNET) {
        config.type = ControllerType::Ethernet;
    } else if (typeStr == CONTROLLER_SERIAL) {
        config.type = ControllerType::Serial;
    } else {
        config.type = ControllerType::Null;
    }

    config.ip = c->GetIP();
    config.protocol = c->GetProtocol();
    config.fppProxy = c->GetFPPProxy();
    config.vendor = c->GetVendor();
    config.model = c->GetModel();
    config.variant = c->GetVariant();

    config.active = convertActiveState(static_cast<int>(c->GetActive()));
    config.autoLayout = c->IsAutoLayout();
    config.autoSize = c->IsAutoSize();
    config.autoUpload = c->IsAutoUpload();
    config.fullxLightsControl = c->IsFullxLightsControl();
    config.defaultBrightness = c->GetDefaultBrightnessUnderFullControl();
    config.defaultGamma = c->GetDefaultGammaUnderFullControl();
    config.suppressDuplicateFrames = c->IsSuppressDuplicateFrames();
    config.monitor = c->IsMonitoring();
    config.managed = c->IsManaged();
    config.fromBase = c->IsFromBase();

    config.startChannel = c->GetStartChannel();
    config.endChannel = c->GetEndChannel();
    config.channels = c->GetChannels();
    config.outputCount = c->GetOutputCount();

    config.lastPingState = convertPingState(static_cast<int>(c->GetLastPingState()));

    // Ethernet-specific properties
    auto eth = dynamic_cast<ControllerEthernet*>(c);
    if (eth) {
        config.forceLocalIP = eth->GetForceLocalIP();
        config.fppProxy = eth->GetFPPProxy();
        config.priority = eth->GetPriority();
        config.version = eth->GetVersion();
        config.universePerString = eth->IsUniversePerString();
    }

    // Serial-specific properties
    auto ser = dynamic_cast<ControllerSerial*>(c);
    if (ser) {
        config.commPort = ser->GetPort();
        config.baudRate = ser->GetSpeed();
        config.prefix = ser->GetSaveablePreFix();
        config.postfix = ser->GetSaveablePostFix();
    }

    // Build output info list
    for (const auto& output : c->GetOutputs()) {
        OutputInfo oi;
        oi.protocol = output->GetType();
        oi.ip = output->GetIP();
        oi.universe = output->GetUniverse();
        oi.channels = output->GetChannels();
        oi.startChannel = output->GetStartChannel();
        oi.enabled = output->IsEnabled();
        oi.fppProxy = output->GetFPPProxyIP();
        oi.forceLocalIP = output->GetForceLocalIP();
        oi.suppressDuplicateFrames = output->IsSuppressDuplicateFrames();
        config.outputs.push_back(oi);
    }

    return config;
}

void OutputEngine::applyConfigToController(Controller* c, const ControllerConfig& config) const {
    if (!c) return;

    c->SetName(config.name);
    c->SetDescription(config.description);
    c->SetActive(activeStateToString(config.active));
    c->SetVendor(config.vendor);
    c->SetModel(config.model);
    c->SetVariant(config.variant);
    c->SetFullxLightsControl(config.fullxLightsControl);
    c->SetDefaultBrightnessUnderFullControl(config.defaultBrightness);
    c->SetDefaultGammaUnderFullControl(config.defaultGamma);
    c->SetSuppressDuplicateFrames(config.suppressDuplicateFrames);
    c->SetMonitoring(config.monitor);

    auto eth = dynamic_cast<ControllerEthernet*>(c);
    if (eth) {
        if (!config.ip.empty()) {
            eth->SetIP(config.ip);
        }
        if (!config.protocol.empty()) {
            eth->SetProtocol(config.protocol);
        }
        if (!config.forceLocalIP.empty()) {
            eth->SetForceLocalIP(config.forceLocalIP);
        }
        if (!config.fppProxy.empty()) {
            eth->SetFPPProxy(config.fppProxy);
        }
        eth->SetPriority(config.priority);
        eth->SetVersion(config.version);
        eth->SetUniversePerString(config.universePerString);
    }

    auto ser = dynamic_cast<ControllerSerial*>(c);
    if (ser) {
        if (!config.commPort.empty()) {
            ser->SetPort(config.commPort);
        }
        if (!config.protocol.empty()) {
            ser->SetProtocol(config.protocol);
        }
        if (config.baudRate > 0) {
            ser->SetSpeed(config.baudRate);
        }
        if (!config.prefix.empty()) {
            ser->SetPrefix(config.prefix);
        }
        if (!config.postfix.empty()) {
            ser->SetPostfix(config.postfix);
        }
    }

    // Extra properties
    for (const auto& [key, val] : config.extraProperties) {
        c->SetExtraProperty(key, val);
    }
}

std::vector<ControllerConfig> OutputEngine::getControllers() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return {};

    std::vector<ControllerConfig> result;
    for (auto* c : _outputManager->GetControllers()) {
        result.push_back(controllerToConfig(c));
    }
    return result;
}

ControllerConfig OutputEngine::getController(const std::string& name) const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    auto* c = findController(name);
    if (!c) return {};
    return controllerToConfig(c);
}

bool OutputEngine::controllerExists(const std::string& name) const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return findController(name) != nullptr;
}

int OutputEngine::getControllerCount() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return 0;
    return _outputManager->GetControllerCount();
}

std::vector<std::string> OutputEngine::getControllerNames() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return {};

    auto names = _outputManager->GetControllerNames();
    return std::vector<std::string>(names.begin(), names.end());
}

OperationResult OutputEngine::addControllerInternal(const ControllerConfig& config) {
    if (!_outputManager) return {false, "OutputEngine not initialized"};

    if (findController(config.name) != nullptr) {
        return {false, "Controller with name '" + config.name + "' already exists"};
    }

    Controller* c = nullptr;
    switch (config.type) {
    case ControllerType::Ethernet:
        c = new ControllerEthernet(_outputManager);
        break;
    case ControllerType::Serial:
        c = new ControllerSerial(_outputManager);
        break;
    case ControllerType::Null:
        c = new ControllerNull(_outputManager);
        break;
    }

    if (!c) {
        return {false, "Failed to create controller"};
    }

    applyConfigToController(c, config);
    _outputManager->AddController(c);

    return {true, "Controller '" + config.name + "' added"};
}

OperationResult OutputEngine::addController(const ControllerConfig& config) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return addControllerInternal(config);
}

OperationResult OutputEngine::removeController(const std::string& name) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return {false, "OutputEngine not initialized"};

    auto* c = findController(name);
    if (!c) {
        return {false, "Controller '" + name + "' not found"};
    }

    _outputManager->DeleteController(name);
    return {true, "Controller '" + name + "' removed"};
}

OperationResult OutputEngine::updateController(const std::string& name, const ControllerConfig& config) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return {false, "OutputEngine not initialized"};

    auto* c = findController(name);
    if (!c) {
        return {false, "Controller '" + name + "' not found"};
    }

    applyConfigToController(c, config);
    return {true, "Controller '" + name + "' updated"};
}

std::vector<PortConfig> OutputEngine::getControllerPorts(const std::string& name) const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    // Port configuration is determined at upload time via UDController,
    // which requires the full ModelManager context. At the API level, we
    // can return the output-based port information that is directly available.
    auto* c = findController(name);
    if (!c) return {};

    std::vector<PortConfig> ports;
    int portNum = 0;
    for (const auto& output : c->GetOutputs()) {
        PortConfig pc;
        pc.portNumber = portNum++;
        pc.protocol = output->GetType();
        pc.startChannel = output->GetStartChannel();
        pc.channels = output->GetChannels();
        ports.push_back(pc);
    }
    return ports;
}

OperationResult OutputEngine::setPortConfig(const std::string& name, int port, const PortConfig& config) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    auto* c = findController(name);
    if (!c) {
        return {false, "Controller '" + name + "' not found"};
    }

    auto* output = c->GetOutput(port);
    if (!output) {
        return {false, "Port " + std::to_string(port) + " not found on controller '" + name + "'"};
    }

    output->SetChannels(config.channels);
    return {true, "Port " + std::to_string(port) + " updated on controller '" + name + "'"};
}

ControllerCapabilities OutputEngine::getControllerCapabilities(const std::string& name) const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    auto* c = findController(name);
    if (!c) return {};

    auto* caps = ControllerCaps::GetControllerConfig(c->GetVendor(), c->GetModel(), c->GetVariant());
    if (!caps) return {};

    ControllerCapabilities result;
    result.supportsUpload = caps->SupportsUpload();
    result.supportsInputOnlyUpload = caps->SupportsInputOnlyUpload();
    result.supportsAutoLayout = caps->SupportsAutoLayout();
    result.supportsAutoUpload = caps->SupportsAutoUpload();
    result.supportsAutoSize = c->SupportsAutoSize();
    result.supportsFullxLightsControl = caps->SupportsFullxLightsControl();
    result.supportsPixelPortBrightness = caps->SupportsPixelPortBrightness();
    result.supportsPixelPortGamma = caps->SupportsPixelPortGamma();
    result.supportsDefaultBrightness = caps->SupportsDefaultBrightness();
    result.supportsDefaultGamma = caps->SupportsDefaultGamma();
    result.supportsSmartRemotes = caps->SupportsSmartRemotes();
    result.supportsVirtualStrings = caps->SupportsVirtualStrings();
    result.supportsUniversePerString = caps->SupportsUniversePerString();
    result.supportsLEDPanelMatrix = caps->SupportsLEDPanelMatrix();
    result.supportsVirtualMatrix = caps->SupportsVirtualMatrix();
    result.maxPixelPort = caps->GetMaxPixelPort();
    result.maxSerialPort = caps->GetMaxSerialPort();
    result.maxPixelPortChannels = caps->GetMaxPixelPortChannels();
    result.maxSerialPortChannels = caps->GetMaxSerialPortChannels();
    result.maxInputE131Universes = caps->GetMaxInputE131Universes();
    result.smartRemoteCount = caps->GetSmartRemoteCount();
    result.pixelProtocols = caps->GetPixelProtocols();
    result.serialProtocols = caps->GetSerialProtocols();
    result.inputProtocols = caps->GetInputProtocols();

    return result;
}

std::vector<ProtocolInfo> OutputEngine::getOutputProtocols() const {
    std::vector<ProtocolInfo> protocols;

    // Ethernet protocols
    protocols.push_back({OUTPUT_E131, true, false, 512});
    protocols.push_back({OUTPUT_ARTNET, true, false, 512});
    protocols.push_back({OUTPUT_DDP, true, false, 2000000});
    protocols.push_back({OUTPUT_KINET, true, false, 512});
    protocols.push_back({OUTPUT_OPC, true, false, 0});
    protocols.push_back({OUTPUT_ZCPP, true, false, 0});
    protocols.push_back({OUTPUT_xxxETHERNET, true, false, 0});
    protocols.push_back({OUTPUT_TWINKLY, true, false, 0});
    protocols.push_back({OUTPUT_PLAYER_ONLY, true, false, 0});

    // Serial protocols
    protocols.push_back({OUTPUT_DMX, false, true, 512});
    protocols.push_back({OUTPUT_PIXELNET, false, true, 4096});
    protocols.push_back({OUTPUT_LOR, false, true, 0});
    protocols.push_back({OUTPUT_LOR_OPT, false, true, 0});
    protocols.push_back({OUTPUT_DLIGHT, false, true, 512});
    protocols.push_back({OUTPUT_RENARD, false, true, 0});
    protocols.push_back({OUTPUT_OPENDMX, false, true, 512});
    protocols.push_back({OUTPUT_OPENPIXELNET, false, true, 0});
    protocols.push_back({OUTPUT_GENERICSERIAL, false, true, 0});
    protocols.push_back({OUTPUT_xxxSERIAL, false, true, 0});

    return protocols;
}

std::vector<std::string> OutputEngine::getVendors(const std::string& controllerType) const {
    auto vendors = ControllerCaps::GetVendors(controllerType);
    return std::vector<std::string>(vendors.begin(), vendors.end());
}

std::vector<std::string> OutputEngine::getModels(const std::string& controllerType, const std::string& vendor) const {
    auto models = ControllerCaps::GetModels(controllerType, vendor);
    return std::vector<std::string>(models.begin(), models.end());
}

std::vector<std::string> OutputEngine::getVariants(const std::string& controllerType, const std::string& vendor, const std::string& model) const {
    auto variants = ControllerCaps::GetVariants(controllerType, vendor, model);
    return std::vector<std::string>(variants.begin(), variants.end());
}

void OutputEngine::testController(const std::string& name, PingCallback callback) {
    if (!_outputManager) {
        if (callback) callback(name, PingState::Unknown);
        return;
    }

    // Run ping in a background thread to avoid blocking
    std::thread([this, name, callback]() {
        Controller* c = nullptr;
        {
            std::lock_guard<std::recursive_mutex> lock(_mutex);
            c = findController(name);
        }

        PingState result = PingState::Unknown;
        if (c) {
            auto pingResult = c->Ping();
            result = convertPingState(static_cast<int>(pingResult));
        }

        if (callback) {
            callback(name, result);
        }
    }).detach();
}

void OutputEngine::testAllControllers(PingCallback callback) {
    if (!_outputManager) return;

    std::vector<std::string> names;
    {
        std::lock_guard<std::recursive_mutex> lock(_mutex);
        auto namesList = _outputManager->GetControllerNames();
        names.assign(namesList.begin(), namesList.end());
    }

    for (const auto& name : names) {
        testController(name, callback);
    }
}

PingState OutputEngine::getLastPingState(const std::string& name) const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    auto* c = findController(name);
    if (!c) return PingState::Unknown;
    return convertPingState(static_cast<int>(c->GetLastPingState()));
}

void OutputEngine::discoverControllers(DiscoveryCallback callback) {
    // Discovery requires wx infrastructure (wxDatagramSocket, wxWindow parent).
    // This method provides a pure C++ callback interface, but internally still
    // relies on the wx-based Discovery class. The actual discovery must be
    // dispatched on the main (wx) thread for socket operations.
    //
    // For now, we provide the callback structure so the native UI layer
    // can wire this up through Objective-C++ bridging. The actual discovery
    // invocation will be coordinated through the existing Discovery class
    // from the wx layer, with results converted and passed through the callback.
    //
    // TODO: When Discovery is refactored to use POSIX sockets directly,
    // this can run entirely on a background thread.
    if (callback) {
        callback(false, {});
    }
}

OperationResult OutputEngine::addDiscoveredController(const DiscoveredController& discovered) {
    ControllerConfig config;
    config.type = ControllerType::Ethernet;
    config.ip = discovered.ip;
    config.name = discovered.hostname.empty() ? discovered.ip : discovered.hostname;
    config.vendor = discovered.vendor;
    config.model = discovered.model;
    config.variant = discovered.variant;
    config.description = discovered.description;
    config.protocol = OUTPUT_DDP; // sensible default; caller should override
    config.active = ActiveState::Active;
    config.autoLayout = true;

    return addController(config);
}

void OutputEngine::uploadInputToController(const std::string& name, UploadCallback callback) {
    // Upload requires the full ModelManager and wx UI context (for progress
    // dialogs and error prompts). This method provides the async callback
    // interface for the native UI layer to use, but the actual upload
    // must be coordinated through xLightsFrame for now.
    //
    // The native UI layer should:
    // 1. Call this method to initiate
    // 2. Bridge into the existing upload path via xLightsFrame
    // 3. Call the callback with the result
    //
    // TODO: When BaseController upload methods are refactored to not
    // require wxWindow* parent, this can run directly from here.
    if (callback) {
        callback(false, "Upload requires coordination with xLightsFrame. Use the bridged upload path.");
    }
}

void OutputEngine::uploadOutputToController(const std::string& name, UploadCallback callback) {
    // Same constraints as uploadInputToController - see comments above.
    if (callback) {
        callback(false, "Upload requires coordination with xLightsFrame. Use the bridged upload path.");
    }
}

void OutputEngine::uploadToController(const std::string& name, UploadCallback callback) {
    // Combined input + output upload.
    // Same constraints apply - see uploadInputToController comments.
    if (callback) {
        callback(false, "Upload requires coordination with xLightsFrame. Use the bridged upload path.");
    }
}

bool OutputEngine::startOutput() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return false;
    return _outputManager->StartOutput();
}

void OutputEngine::stopOutput() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return;
    _outputManager->StopOutput();
}

bool OutputEngine::isOutputting() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return false;
    return _outputManager->IsOutputting();
}

void OutputEngine::sortControllersByName() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return;
    _outputManager->SortControllersbyName();
}

void OutputEngine::sortControllersByID() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return;
    _outputManager->SortControllersbyID();
}

void OutputEngine::sortControllersByIP() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return;
    _outputManager->SortControllersbyIP();
}

bool OutputEngine::isDirty() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return false;
    return _outputManager->IsDirty();
}

OperationResult OutputEngine::save() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return {false, "OutputEngine not initialized"};

    if (_outputManager->Save()) {
        return {true, "Configuration saved"};
    }
    return {false, "Failed to save configuration"};
}

std::string OutputEngine::getGlobalFPPProxy() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return "";
    return _outputManager->GetGlobalFPPProxy();
}

void OutputEngine::setGlobalFPPProxy(const std::string& proxy) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return;
    _outputManager->SetGlobalFPPProxy(proxy);
}

std::string OutputEngine::getGlobalForceLocalIP() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return "";
    return _outputManager->GetGlobalForceLocalIP();
}

void OutputEngine::setGlobalForceLocalIP(const std::string& ip) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return;
    _outputManager->SetGlobalForceLocalIP(ip);
}

int OutputEngine::getSuppressFrames() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return 0;
    return _outputManager->GetSuppressFrames();
}

void OutputEngine::setSuppressFrames(int frames) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return;
    _outputManager->SetSuppressFrames(frames);
}

bool OutputEngine::isParallelTransmission() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return false;
    return _outputManager->GetParallelTransmission();
}

void OutputEngine::setParallelTransmission(bool parallel) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return;
    _outputManager->SetParallelTransmission(parallel);
}

int32_t OutputEngine::getTotalChannels() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_outputManager) return 0;
    return _outputManager->GetTotalChannels();
}

void OutputEngine::setErrorCallback(ErrorCallback callback) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    _errorCallback = std::move(callback);
}

} // namespace xlEngine
