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

#ifndef XLIGHTS_NATIVE
#include "../outputs/OutputManager.h"
#include "../outputs/Controller.h"
#include "../outputs/ControllerEthernet.h"
#include "../outputs/ControllerSerial.h"
#include "../outputs/ControllerNull.h"
#include "../outputs/Output.h"
#include "../outputs/IPOutput.h"
#include "../controllers/ControllerCaps.h"
#include "../xLightsMain.h"
#endif

#include <algorithm>
#include <thread>

namespace xlEngine {

#ifdef XLIGHTS_NATIVE
// Native build: stub implementation
// The native build uses NativeOutputProvider instead of the legacy adapter

OutputEngine::OutputEngine(IOutputProvider* provider) : _provider(provider) {
    _initialized = (provider != nullptr);
}

OutputEngine::~OutputEngine() = default;

void OutputEngine::initialize(IOutputProvider* provider) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    _provider = provider;
    _initialized = (provider != nullptr);
}

static ControllerConfig controllerInfoToConfig(const ControllerInfo& info) {
    ControllerConfig cfg;
    cfg.name = info.name;
    cfg.ip = info.ip;
    cfg.description = info.description;
    cfg.vendor = info.vendor;
    cfg.model = info.model;
    cfg.variant = info.variant;
    cfg.protocol = info.protocol;
    cfg.fppProxy = info.fppProxy;
    cfg.forceLocalIP = info.forceLocalIP;
    cfg.channels = info.channels;
    cfg.startChannel = info.startChannel;
    cfg.endChannel = info.endChannel;
    cfg.outputCount = info.outputCount;
    cfg.commPort = info.commPort;
    cfg.priority = info.priority;
    cfg.autoLayout = info.autoLayout;
    cfg.autoSize = info.autoSize;
    cfg.managed = info.managed;
    cfg.autoUpload = info.autoUpload;
    cfg.fullxLightsControl = info.fullxLightsControl;
    cfg.defaultBrightness = info.defaultBrightness;
    cfg.defaultGamma = info.defaultGamma;
    cfg.suppressDuplicateFrames = info.suppressDuplicateFrames;
    cfg.monitor = info.monitor;
    cfg.fromBase = info.fromBase;
    cfg.universePerString = info.universePerString;

    // Map active state from string or bool
    if (!info.activeState.empty()) {
        if (info.activeState == "Inactive") {
            cfg.active = ActiveState::Inactive;
        } else if (info.activeState == "xLights Only") {
            cfg.active = ActiveState::ActiveInXLightsOnly;
        } else {
            cfg.active = ActiveState::Active;
        }
    } else {
        cfg.active = info.active ? ActiveState::Active : ActiveState::Inactive;
    }

    // Map controller type
    switch (info.type) {
        case OutputControllerType::Ethernet:
            cfg.type = ControllerType::Ethernet;
            break;
        case OutputControllerType::Serial:
            cfg.type = ControllerType::Serial;
            break;
        case OutputControllerType::Null:
        default:
            cfg.type = ControllerType::Null;
            break;
    }
    return cfg;
}

std::vector<ControllerConfig> OutputEngine::getControllers() const {
    if (!_provider) return {};
    std::vector<ControllerConfig> result;
    size_t count = _provider->getControllerCount();
    for (size_t i = 0; i < count; ++i) {
        auto info = _provider->getController(i);
        if (info) {
            result.push_back(controllerInfoToConfig(*info));
        }
    }
    return result;
}

ControllerConfig OutputEngine::getController(const std::string& name) const {
    if (!_provider) return {};
    auto info = _provider->getControllerByName(name);
    if (!info) return {};
    return controllerInfoToConfig(*info);
}

bool OutputEngine::controllerExists(const std::string& name) const {
    if (!_provider) return false;
    return _provider->getControllerByName(name).has_value();
}

int OutputEngine::getControllerCount() const {
    if (!_provider) return 0;
    return static_cast<int>(_provider->getControllerCount());
}

std::vector<std::string> OutputEngine::getControllerNames() const {
    if (!_provider) return {};
    return _provider->getControllerNames();
}
OperationResult OutputEngine::addController(const ControllerConfig& config) { return {false, "Native build: not implemented"}; }
OperationResult OutputEngine::removeController(const std::string& name) { return {false, "Native build: not implemented"}; }
OperationResult OutputEngine::updateController(const std::string& name, const ControllerConfig& config) { return {false, "Native build: not implemented"}; }
std::vector<PortConfig> OutputEngine::getControllerPorts(const std::string& name) const { return {}; }
OperationResult OutputEngine::setPortConfig(const std::string& name, int port, const PortConfig& config) { return {false, "Native build: not implemented"}; }
ControllerCapabilities OutputEngine::getControllerCapabilities(const std::string& name) const { return {}; }
std::vector<ProtocolInfo> OutputEngine::getOutputProtocols() const { return {}; }
std::vector<std::string> OutputEngine::getVendors(const std::string& controllerType) const { return {}; }
std::vector<std::string> OutputEngine::getModels(const std::string& controllerType, const std::string& vendor) const { return {}; }
std::vector<std::string> OutputEngine::getVariants(const std::string& controllerType, const std::string& vendor, const std::string& model) const { return {}; }
void OutputEngine::testController(const std::string& name, PingCallback callback) { if (callback) callback(name, PingState::Unknown); }
void OutputEngine::testAllControllers(PingCallback callback) {}
PingState OutputEngine::getLastPingState(const std::string& name) const { return PingState::Unknown; }
void OutputEngine::discoverControllers(DiscoveryCallback callback) { if (callback) callback(false, {}); }
OperationResult OutputEngine::addDiscoveredController(const DiscoveredController& discovered) { return {false, "Native build: not implemented"}; }
void OutputEngine::uploadInputToController(const std::string& name, UploadCallback callback) { if (callback) callback(false, "Native build: not implemented"); }
void OutputEngine::uploadOutputToController(const std::string& name, UploadCallback callback) { if (callback) callback(false, "Native build: not implemented"); }
void OutputEngine::uploadToController(const std::string& name, UploadCallback callback) { if (callback) callback(false, "Native build: not implemented"); }
bool OutputEngine::startOutput() { return false; }
void OutputEngine::stopOutput() {}
bool OutputEngine::isOutputting() const { return false; }
void OutputEngine::sortControllersByName() {}
void OutputEngine::sortControllersByID() {}
void OutputEngine::sortControllersByIP() {}
bool OutputEngine::isDirty() const { return false; }
OperationResult OutputEngine::save() { return {false, "Native build: not implemented"}; }
std::string OutputEngine::getGlobalFPPProxy() const { return ""; }
void OutputEngine::setGlobalFPPProxy(const std::string& proxy) {}
std::string OutputEngine::getGlobalForceLocalIP() const { return ""; }
void OutputEngine::setGlobalForceLocalIP(const std::string& ip) {}
int OutputEngine::getSuppressFrames() const { return 0; }
void OutputEngine::setSuppressFrames(int frames) {}
bool OutputEngine::isParallelTransmission() const { return false; }
void OutputEngine::setParallelTransmission(bool parallel) {}
int32_t OutputEngine::getTotalChannels() const { return 0; }
void OutputEngine::setErrorCallback(ErrorCallback callback) { _errorCallback = std::move(callback); }

#else
// Legacy build: full implementation using OutputManager and Controller classes

OutputEngine::OutputEngine(IOutputProvider* provider) : _provider(provider) {
    _initialized = (provider != nullptr);
}

OutputEngine::~OutputEngine() = default;

void OutputEngine::initialize(IOutputProvider* provider) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    _provider = provider;
    _initialized = (provider != nullptr);
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
    if (!_provider) return nullptr;
    auto* om = _provider->getOutputManager();
    if (!om) return nullptr;
    return om->GetController(name);
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
    if (!_provider) return {};
    auto* om = _provider->getOutputManager();
    if (!om) return {};

    std::vector<ControllerConfig> result;
    for (auto* c : om->GetControllers()) {
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
    if (!_provider) return 0;
    return static_cast<int>(_provider->getControllerCount());
}

std::vector<std::string> OutputEngine::getControllerNames() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return {};
    return _provider->getControllerNames();
}

OperationResult OutputEngine::addControllerInternal(const ControllerConfig& config) {
    if (!_provider) return {false, "OutputEngine not initialized"};
    auto* om = _provider->getOutputManager();
    if (!om) return {false, "OutputManager not available"};

    if (findController(config.name) != nullptr) {
        return {false, "Controller with name '" + config.name + "' already exists"};
    }

    Controller* c = nullptr;
    switch (config.type) {
    case ControllerType::Ethernet:
        c = new ControllerEthernet(om);
        break;
    case ControllerType::Serial:
        c = new ControllerSerial(om);
        break;
    case ControllerType::Null:
        c = new ControllerNull(om);
        break;
    }

    if (!c) {
        return {false, "Failed to create controller"};
    }

    applyConfigToController(c, config);
    om->AddController(c);

    return {true, "Controller '" + config.name + "' added"};
}

OperationResult OutputEngine::addController(const ControllerConfig& config) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return addControllerInternal(config);
}

OperationResult OutputEngine::removeController(const std::string& name) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return {false, "OutputEngine not initialized"};
    auto* om = _provider->getOutputManager();
    if (!om) return {false, "OutputManager not available"};

    auto* c = findController(name);
    if (!c) {
        return {false, "Controller '" + name + "' not found"};
    }

    om->DeleteController(name);
    return {true, "Controller '" + name + "' removed"};
}

OperationResult OutputEngine::updateController(const std::string& name, const ControllerConfig& config) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return {false, "OutputEngine not initialized"};

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
    if (!_provider) {
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
    if (!_provider) return;

    std::vector<std::string> names;
    {
        std::lock_guard<std::recursive_mutex> lock(_mutex);
        names = _provider->getControllerNames();
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
    if (!_provider) return false;
    return _provider->startOutput();
}

void OutputEngine::stopOutput() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return;
    _provider->stopOutput();
}

bool OutputEngine::isOutputting() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return false;
    return _provider->isOutputting();
}

void OutputEngine::sortControllersByName() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return;
    auto* om = _provider->getOutputManager();
    if (om) om->SortControllersbyName();
}

void OutputEngine::sortControllersByID() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return;
    auto* om = _provider->getOutputManager();
    if (om) om->SortControllersbyID();
}

void OutputEngine::sortControllersByIP() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return;
    auto* om = _provider->getOutputManager();
    if (om) om->SortControllersbyIP();
}

bool OutputEngine::isDirty() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return false;
    auto* om = _provider->getOutputManager();
    if (!om) return false;
    return om->IsDirty();
}

OperationResult OutputEngine::save() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return {false, "OutputEngine not initialized"};
    auto* om = _provider->getOutputManager();
    if (!om) return {false, "OutputManager not available"};

    if (om->Save()) {
        return {true, "Configuration saved"};
    }
    return {false, "Failed to save configuration"};
}

std::string OutputEngine::getGlobalFPPProxy() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return "";
    auto* om = _provider->getOutputManager();
    if (!om) return "";
    return om->GetGlobalFPPProxy();
}

void OutputEngine::setGlobalFPPProxy(const std::string& proxy) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return;
    auto* om = _provider->getOutputManager();
    if (om) om->SetGlobalFPPProxy(proxy);
}

std::string OutputEngine::getGlobalForceLocalIP() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return "";
    auto* om = _provider->getOutputManager();
    if (!om) return "";
    return om->GetGlobalForceLocalIP();
}

void OutputEngine::setGlobalForceLocalIP(const std::string& ip) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return;
    auto* om = _provider->getOutputManager();
    if (om) om->SetGlobalForceLocalIP(ip);
}

int OutputEngine::getSuppressFrames() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return 0;
    auto* om = _provider->getOutputManager();
    if (!om) return 0;
    return om->GetSuppressFrames();
}

void OutputEngine::setSuppressFrames(int frames) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return;
    auto* om = _provider->getOutputManager();
    if (om) om->SetSuppressFrames(frames);
}

bool OutputEngine::isParallelTransmission() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return false;
    auto* om = _provider->getOutputManager();
    if (!om) return false;
    return om->GetParallelTransmission();
}

void OutputEngine::setParallelTransmission(bool parallel) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return;
    auto* om = _provider->getOutputManager();
    if (om) om->SetParallelTransmission(parallel);
}

int32_t OutputEngine::getTotalChannels() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (!_provider) return 0;
    return _provider->getTotalChannels();
}

void OutputEngine::setErrorCallback(ErrorCallback callback) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    _errorCallback = std::move(callback);
}

// ============================================================================
// OutputManagerAdapter implementation
// ============================================================================

OutputManagerAdapter::OutputManagerAdapter(OutputManager* manager, xLightsFrame* frame)
    : _manager(manager), _frame(frame) {
}

size_t OutputManagerAdapter::getControllerCount() const {
    if (!_manager) return 0;
    return static_cast<size_t>(_manager->GetControllerCount());
}

std::optional<ControllerInfo> OutputManagerAdapter::getController(size_t index) const {
    if (!_manager) return std::nullopt;
    auto controllers = _manager->GetControllers();
    if (index >= controllers.size()) return std::nullopt;
    auto it = controllers.begin();
    std::advance(it, index);
    return buildControllerInfo(*it);
}

std::optional<ControllerInfo> OutputManagerAdapter::getControllerByName(const std::string& name) const {
    if (!_manager) return std::nullopt;
    auto* controller = _manager->GetController(name);
    if (!controller) return std::nullopt;
    return buildControllerInfo(controller);
}

std::vector<std::string> OutputManagerAdapter::getControllerNames() const {
    if (!_manager) return {};
    auto names = _manager->GetControllerNames();
    return std::vector<std::string>(names.begin(), names.end());
}

bool OutputManagerAdapter::controllerExists(const std::string& name) const {
    if (!_manager) return false;
    return _manager->GetController(name) != nullptr;
}

bool OutputManagerAdapter::isOutputting() const {
    if (!_manager) return false;
    return _manager->IsOutputting();
}

bool OutputManagerAdapter::startOutput() {
    if (!_manager) return false;

#ifndef XLIGHTS_NATIVE
    // If we have access to xLightsFrame, use its EnableOutputs method
    // which properly sets the UI checkbox state and handles auto-upload
    if (_frame) {
        return _frame->EnableOutputs(true);
    }
#endif

    // Fallback to direct OutputManager call (checkbox state won't be updated)
    return _manager->StartOutput();
}

void OutputManagerAdapter::stopOutput() {
    if (!_manager) return;

#ifndef XLIGHTS_NATIVE
    // If we have access to xLightsFrame, use its DisableOutputs method
    // which properly clears the UI checkbox state
    if (_frame) {
        _frame->DisableOutputs();
        return;
    }
#endif

    // Fallback to direct OutputManager call
    _manager->StopOutput();
}

int32_t OutputManagerAdapter::getTotalChannels() const {
    if (!_manager) return 0;
    return _manager->GetTotalChannels();
}

OutputManager* OutputManagerAdapter::getOutputManager() {
    return _manager;
}

const OutputManager* OutputManagerAdapter::getOutputManager() const {
    return _manager;
}

ControllerInfo OutputManagerAdapter::buildControllerInfo(Controller* c) const {
    if (!c) return {};

    ControllerInfo info;
    info.name = c->GetName();
    info.description = c->GetDescription();
    info.id = c->GetId();

    auto typeStr = c->GetType();
    if (typeStr == CONTROLLER_ETHERNET) {
        info.type = OutputControllerType::Ethernet;
    } else if (typeStr == CONTROLLER_SERIAL) {
        info.type = OutputControllerType::Serial;
    } else {
        info.type = OutputControllerType::Null;
    }

    info.ip = c->GetIP();
    info.protocol = c->GetProtocol();
    info.vendor = c->GetVendor();
    info.model = c->GetModel();
    info.variant = c->GetVariant();

    info.startChannel = c->GetStartChannel();
    info.endChannel = c->GetEndChannel();
    info.channels = c->GetChannels();
    info.outputCount = c->GetOutputCount();

    info.active = (c->GetActive() == Controller::ACTIVESTATE::ACTIVE);
    info.autoLayout = c->IsAutoLayout();
    info.autoSize = c->IsAutoSize();
    info.managed = c->IsManaged();

    // Serial-specific
    auto* ser = dynamic_cast<ControllerSerial*>(c);
    if (ser) {
        info.commPort = ser->GetPort();
    }

    return info;
}

#endif // XLIGHTS_NATIVE

} // namespace xlEngine
