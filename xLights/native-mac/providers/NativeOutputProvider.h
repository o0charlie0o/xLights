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

// NativeOutputProvider: Native macOS implementation of IOutputProvider.
//
// This provider implements output management without wxWidgets dependencies,
// using BSD sockets for network protocols and IOKit for serial outputs.
//
// Supported protocols (priority order):
// 1. E1.31 (sACN) - UDP multicast/unicast on port 5568
// 2. ArtNet - UDP on port 6454
// 3. DDP - UDP on port 4048
//
// This is part of the native macOS rebuild effort to create a fully
// decoupled xLights application. See DECOUPLING_GUIDE.md for details.

#include "../../engine/interfaces/IOutputProvider.h"

#include <string>
#include <vector>
#include <map>
#include <memory>
#include <mutex>
#include <atomic>
#include <thread>
#include <netinet/in.h>

namespace xlEngine {

// Forward declarations for internal protocol handlers
class NativeE131Output;
class NativeArtNetOutput;
class NativeDDPOutput;

// Native controller configuration loaded from XML
struct NativeControllerConfig {
    std::string name;
    std::string description;
    int id = 0;

    // Connection info
    OutputControllerType type = OutputControllerType::Ethernet;
    std::string ip;
    std::string commPort;
    std::string protocol;  // "E131", "ArtNet", "DDP"

    // Hardware identification
    std::string vendor;
    std::string model;
    std::string variant;

    // Channel configuration
    int32_t startChannel = 1;
    int32_t channels = 512;
    int universe = 1;
    int priority = 100;  // E1.31 priority
    int channelsPerPacket = 1440;  // DDP
    bool keepChannelNumbers = true;  // DDP

    // State
    bool active = true;
    bool autoLayout = true;
    bool autoSize = true;
    bool managed = true;
};

// Abstract base class for native protocol outputs
class NativeProtocolOutput {
public:
    virtual ~NativeProtocolOutput() = default;

    virtual bool open() = 0;
    virtual void close() = 0;
    virtual bool isOpen() const = 0;

    virtual void setChannelData(int32_t channel, const uint8_t* data, size_t size) = 0;
    virtual void sendFrame() = 0;
    virtual void allOff() = 0;

    virtual std::string getProtocol() const = 0;
    virtual int32_t getChannels() const = 0;
    virtual int32_t getStartChannel() const = 0;
};

// E1.31 (sACN) output using BSD sockets
class NativeE131Output : public NativeProtocolOutput {
public:
    NativeE131Output(const std::string& ip, int universe, int32_t channels,
                     int32_t startChannel, int priority = 100);
    ~NativeE131Output() override;

    bool open() override;
    void close() override;
    bool isOpen() const override { return _socket >= 0; }

    void setChannelData(int32_t channel, const uint8_t* data, size_t size) override;
    void sendFrame() override;
    void allOff() override;

    std::string getProtocol() const override { return "E131"; }
    int32_t getChannels() const override { return _channels; }
    int32_t getStartChannel() const override { return _startChannel; }

    int getUniverse() const { return _universe; }
    void setPriority(int priority) { _priority = priority; }

private:
    void buildPacket();
    bool isMulticast() const;

    std::string _ip;
    int _universe;
    int32_t _channels;
    int32_t _startChannel;
    int _priority;

    int _socket = -1;
    struct sockaddr_in _remoteAddr;

    uint8_t _packet[638];  // E131_PACKET_LEN
    uint8_t _sequenceNum = 0;
    bool _changed = false;
};

// ArtNet output using BSD sockets
class NativeArtNetOutput : public NativeProtocolOutput {
public:
    NativeArtNetOutput(const std::string& ip, int universe, int32_t channels,
                       int32_t startChannel);
    ~NativeArtNetOutput() override;

    bool open() override;
    void close() override;
    bool isOpen() const override { return _socket >= 0; }

    void setChannelData(int32_t channel, const uint8_t* data, size_t size) override;
    void sendFrame() override;
    void allOff() override;

    std::string getProtocol() const override { return "ArtNet"; }
    int32_t getChannels() const override { return _channels; }
    int32_t getStartChannel() const override { return _startChannel; }

    int getUniverse() const { return _universe; }

    // ArtNet universe breakdown
    static int getNet(int universe) { return (universe & 0x7F00) >> 8; }
    static int getSubnet(int universe) { return (universe & 0x00F0) >> 4; }
    static int getArtNetUniverse(int universe) { return universe & 0x000F; }

private:
    void buildPacket();

    std::string _ip;
    int _universe;
    int32_t _channels;
    int32_t _startChannel;

    int _socket = -1;
    struct sockaddr_in _remoteAddr;

    uint8_t _packet[530];  // ARTNET_PACKET_LEN
    uint8_t _sequenceNum = 0;
    bool _changed = false;
};

// DDP output using BSD sockets
class NativeDDPOutput : public NativeProtocolOutput {
public:
    NativeDDPOutput(const std::string& ip, int32_t channels, int32_t startChannel,
                    int channelsPerPacket = 1440, bool keepChannelNumbers = true);
    ~NativeDDPOutput() override;

    bool open() override;
    void close() override;
    bool isOpen() const override { return _socket >= 0; }

    void setChannelData(int32_t channel, const uint8_t* data, size_t size) override;
    void sendFrame() override;
    void allOff() override;

    std::string getProtocol() const override { return "DDP"; }
    int32_t getChannels() const override { return _channels; }
    int32_t getStartChannel() const override { return _startChannel; }

    void setChannelsPerPacket(int cpp) { _channelsPerPacket = cpp; }
    void setKeepChannelNumbers(bool keep) { _keepChannelNumbers = keep; }

private:
    std::string _ip;
    int32_t _channels;
    int32_t _startChannel;
    int _channelsPerPacket;
    bool _keepChannelNumbers;

    int _socket = -1;
    struct sockaddr_in _remoteAddr;

    std::vector<uint8_t> _fulldata;
    uint8_t _packet[1450];  // DDP_PACKET_LEN
    uint8_t _sequenceNum = 1;
    bool _changed = false;
};

// NativeOutputProvider: Implements IOutputProvider for native macOS builds
//
// This provider loads controller configuration from XML files and manages
// output using native BSD sockets, without any wxWidgets dependencies.
class NativeOutputProvider : public IOutputProvider {
public:
    NativeOutputProvider();
    ~NativeOutputProvider() override;

    // ============================================================
    // Configuration management
    // ============================================================

    // Load controller configuration from an XML file (networks XML)
    bool loadFromXML(const std::string& xmlPath);

    // Save controller configuration to an XML file
    bool saveToXML(const std::string& xmlPath);

    // Add a controller programmatically
    void addController(const NativeControllerConfig& config);

    // Remove a controller by name
    bool removeController(const std::string& name);

    // Clear all controllers
    void clearControllers();

    // ============================================================
    // IOutputProvider interface implementation
    // ============================================================

    size_t getControllerCount() const override;
    std::optional<ControllerInfo> getController(size_t index) const override;
    std::optional<ControllerInfo> getControllerByName(const std::string& name) const override;
    std::vector<std::string> getControllerNames() const override;
    bool controllerExists(const std::string& name) const override;

    bool isOutputting() const override;
    bool startOutput() override;
    void stopOutput() override;

    int32_t getTotalChannels() const override;

    // Migration escape hatch - returns nullptr for native builds
    OutputManager* getOutputManager() override { return nullptr; }
    const OutputManager* getOutputManager() const override { return nullptr; }

    // ============================================================
    // Frame data management
    // ============================================================

    // Set channel data for a specific controller
    void setControllerData(const std::string& name, int32_t channel,
                          const uint8_t* data, size_t size);

    // Set channel data by absolute channel number
    void setChannelData(int32_t startChannel, const uint8_t* data, size_t size);

    // Send current frame to all controllers
    void sendFrame();

    // Turn all outputs off
    void allOff();

private:
    // Build ControllerInfo from internal config
    ControllerInfo buildControllerInfo(const NativeControllerConfig& config) const;

    // Create protocol output for a controller
    std::unique_ptr<NativeProtocolOutput> createOutput(const NativeControllerConfig& config);

    // Parse controller from XML node
    bool parseController(const void* xmlNode, NativeControllerConfig& config);

    // Controller configurations
    std::vector<NativeControllerConfig> _controllers;

    // Protocol outputs (created when startOutput is called)
    std::map<std::string, std::unique_ptr<NativeProtocolOutput>> _outputs;

    // Output state
    std::atomic<bool> _outputting{false};
    mutable std::recursive_mutex _mutex;

    // Cached total channels
    mutable int32_t _cachedTotalChannels = -1;
};

} // namespace xlEngine
