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

/**
 * @file Output.h
 * @brief Output protocol abstractions for the xlCore library.
 *
 * This provides pure C++17/20 output protocol classes with no wxWidgets
 * dependencies. Uses BSD sockets directly for network protocols.
 *
 * Key components:
 * - OutputConfig: Configuration data for outputs
 * - OutputProtocol: Base class for all output protocols
 * - E131Output: sACN/E1.31 protocol implementation
 * - ArtNetOutput: Art-Net protocol implementation
 * - DDPOutput: Distributed Display Protocol implementation
 * - DMXOutput: DMX512 serial protocol implementation
 * - NullOutput: Test/null output for debugging
 * - OutputManager: Manages multiple outputs
 * - OutputFactory: Creates protocol instances by name
 *
 * Design principles:
 * - Zero wxWidgets dependencies
 * - Thread-safe for real-time output
 * - Uses BSD sockets (not wx networking)
 * - Modern C++17/20 idioms
 */

#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>
#include <map>
#include <memory>
#include <mutex>
#include <atomic>

namespace xlCore {

// Protocol type identifiers (compatible with existing xLights constants)
constexpr const char* PROTOCOL_E131 = "E131";
constexpr const char* PROTOCOL_ARTNET = "ArtNet";
constexpr const char* PROTOCOL_DDP = "DDP";
constexpr const char* PROTOCOL_DMX = "DMX";
constexpr const char* PROTOCOL_NULL = "NULL";
constexpr const char* PROTOCOL_OPC = "OPC";

// Common protocol constants
constexpr int E131_PORT = 5568;
constexpr int E131_DEFAULT_PRIORITY = 100;
constexpr int E131_MAX_CHANNELS = 512;
constexpr int ARTNET_PORT = 0x1936;  // 6454
constexpr int ARTNET_MAX_CHANNELS = 512;
constexpr int DDP_PORT = 4048;
constexpr int DDP_MAX_CHANNELS_PER_PACKET = 1440;
constexpr int DMX_MAX_CHANNELS = 512;

/**
 * @brief Configuration data for an output protocol.
 *
 * Stores protocol-agnostic configuration plus protocol-specific
 * settings as key-value pairs.
 */
struct OutputConfig {
    std::string name;
    bool enabled = true;
    size_t channelCount = 512;
    size_t startChannel = 1;

    // Protocol-specific settings stored as key-value pairs
    std::map<std::string, std::string> settings;

    // Convenience accessors for settings
    std::string getString(const std::string& key, const std::string& defaultValue = "") const;
    int getInt(const std::string& key, int defaultValue = 0) const;
    bool getBool(const std::string& key, bool defaultValue = false) const;
    double getDouble(const std::string& key, double defaultValue = 0.0) const;

    // Convenience setters
    void setString(const std::string& key, const std::string& value);
    void setInt(const std::string& key, int value);
    void setBool(const std::string& key, bool value);
    void setDouble(const std::string& key, double value);
};

/**
 * @brief Abstract base class for all output protocols.
 *
 * Provides a common interface for network and serial output protocols.
 * Each protocol implementation handles its specific packet format and
 * transmission details.
 *
 * Thread-safety: Individual instances are not thread-safe for concurrent
 * access. Use external synchronization if needed, or use OutputManager
 * which provides coordinated access.
 */
class OutputProtocol {
public:
    virtual ~OutputProtocol() = default;

    // Lifecycle

    /**
     * @brief Open the output connection.
     * @return true if connection opened successfully
     */
    virtual bool open() = 0;

    /**
     * @brief Close the output connection.
     */
    virtual void close() = 0;

    /**
     * @brief Check if output is currently open.
     */
    virtual bool isOpen() const = 0;

    // Configuration

    /**
     * @brief Configure the output with the given settings.
     * @param config Configuration data
     */
    virtual void configure(const OutputConfig& config);

    /**
     * @brief Get the current configuration.
     */
    virtual OutputConfig config() const { return _config; }

    // Data transmission

    /**
     * @brief Start a new frame.
     * @param timeMs Current time in milliseconds (for synchronization)
     */
    virtual void startFrame(int64_t timeMs);

    /**
     * @brief Send frame data to the output.
     * @param data Pointer to channel data
     * @param channels Number of channels to send
     * @return true if data sent successfully
     */
    virtual bool sendFrame(const uint8_t* data, size_t channels) = 0;

    /**
     * @brief End the current frame.
     * @param suppressFrames Number of frames to suppress (for duplicate suppression)
     */
    virtual void endFrame(int suppressFrames = 0);

    /**
     * @brief Set a single channel value.
     * @param channel Channel index (0-based)
     * @param value Channel value (0-255)
     */
    virtual void setChannel(size_t channel, uint8_t value);

    /**
     * @brief Set multiple channel values.
     * @param startChannel Starting channel index (0-based)
     * @param data Pointer to channel data
     * @param count Number of channels to set
     */
    virtual void setChannels(size_t startChannel, const uint8_t* data, size_t count);

    /**
     * @brief Turn all channels off (set to 0).
     */
    virtual void allOff();

    // Protocol information

    /**
     * @brief Get the protocol name.
     */
    virtual std::string protocolName() const = 0;

    /**
     * @brief Check if this is a network (IP-based) protocol.
     */
    virtual bool isNetworkProtocol() const = 0;

    /**
     * @brief Check if this is a serial protocol.
     */
    virtual bool isSerialProtocol() const { return !isNetworkProtocol(); }

    /**
     * @brief Get the maximum channels supported by this protocol.
     */
    virtual size_t maxChannels() const = 0;

    // Status

    /**
     * @brief Get a human-readable status string.
     */
    virtual std::string statusString() const;

    /**
     * @brief Get the number of frames sent.
     */
    size_t framesSent() const { return _framesSent; }

    /**
     * @brief Get the number of errors encountered.
     */
    size_t errors() const { return _errors; }

    /**
     * @brief Check if output is enabled.
     */
    bool isEnabled() const { return _config.enabled; }

    /**
     * @brief Enable or disable the output.
     */
    void setEnabled(bool enabled) { _config.enabled = enabled; }

protected:
    OutputConfig _config;
    std::vector<uint8_t> _frameData;
    size_t _framesSent = 0;
    size_t _errors = 0;
    int64_t _currentTimeMs = 0;
    bool _changed = false;

    /**
     * @brief Ensure frame data buffer is sized correctly.
     */
    void ensureFrameBuffer(size_t channels);
};

/**
 * @brief E1.31 (sACN) output protocol.
 *
 * Implements the E1.31 sACN protocol for sending DMX data over Ethernet.
 * Supports both unicast and multicast transmission.
 *
 * Protocol reference: ANSI E1.31-2018
 */
class E131Output : public OutputProtocol {
public:
    E131Output();
    ~E131Output() override;

    // Lifecycle
    bool open() override;
    void close() override;
    bool isOpen() const override { return _socket >= 0; }

    // Data transmission
    bool sendFrame(const uint8_t* data, size_t channels) override;

    // Protocol info
    std::string protocolName() const override { return PROTOCOL_E131; }
    bool isNetworkProtocol() const override { return true; }
    size_t maxChannels() const override { return E131_MAX_CHANNELS; }

    // E1.31-specific configuration
    void setUniverse(int universe);
    int universe() const { return _universe; }

    void setMulticast(bool multicast);
    bool isMulticast() const { return _multicast; }

    void setPriority(int priority);
    int priority() const { return _priority; }

    void setIP(const std::string& ip);
    std::string ip() const { return _ip; }

private:
    int _socket = -1;
    int _universe = 1;
    int _priority = E131_DEFAULT_PRIORITY;
    bool _multicast = true;
    std::string _ip;
    uint8_t _sequenceNum = 0;
    std::vector<uint8_t> _packet;

    void buildPacketHeader();
};

/**
 * @brief Art-Net output protocol.
 *
 * Implements the Art-Net protocol for sending DMX data over Ethernet.
 *
 * Protocol reference: Art-Net 4 Protocol Release V1.4
 */
class ArtNetOutput : public OutputProtocol {
public:
    ArtNetOutput();
    ~ArtNetOutput() override;

    // Lifecycle
    bool open() override;
    void close() override;
    bool isOpen() const override { return _socket >= 0; }

    // Data transmission
    bool sendFrame(const uint8_t* data, size_t channels) override;

    // Protocol info
    std::string protocolName() const override { return PROTOCOL_ARTNET; }
    bool isNetworkProtocol() const override { return true; }
    size_t maxChannels() const override { return ARTNET_MAX_CHANNELS; }

    // Art-Net-specific configuration
    void setUniverse(int universe);
    int universe() const { return _universe; }

    void setIP(const std::string& ip);
    std::string ip() const { return _ip; }

    // Art-Net universe breakdown
    static int getNet(int universe) { return (universe & 0x7F00) >> 8; }
    static int getSubnet(int universe) { return (universe & 0x00F0) >> 4; }
    static int getUniversePart(int universe) { return universe & 0x000F; }
    static int combinedUniverse(int net, int subnet, int universe) {
        return ((net & 0x007F) << 8) + ((subnet & 0x000F) << 4) + (universe & 0x000F);
    }

private:
    int _socket = -1;
    int _universe = 0;
    std::string _ip;
    uint8_t _sequenceNum = 0;
    std::vector<uint8_t> _packet;

    void buildPacketHeader();
};

/**
 * @brief DDP (Distributed Display Protocol) output.
 *
 * Implements the DDP protocol for sending pixel data over Ethernet.
 * Supports larger channel counts than DMX-based protocols.
 *
 * Protocol reference: http://www.3waylabs.com/ddp/
 */
class DDPOutput : public OutputProtocol {
public:
    DDPOutput();
    ~DDPOutput() override;

    // Lifecycle
    bool open() override;
    void close() override;
    bool isOpen() const override { return _socket >= 0; }

    // Data transmission
    bool sendFrame(const uint8_t* data, size_t channels) override;

    // Protocol info
    std::string protocolName() const override { return PROTOCOL_DDP; }
    bool isNetworkProtocol() const override { return true; }
    size_t maxChannels() const override { return 2000000; }

    // DDP-specific configuration
    void setID(int id);
    int id() const { return _id; }

    void setIP(const std::string& ip);
    std::string ip() const { return _ip; }

    void setChannelsPerPacket(int cpp);
    int channelsPerPacket() const { return _channelsPerPacket; }

private:
    int _socket = -1;
    int _id = 1;
    std::string _ip;
    int _channelsPerPacket = DDP_MAX_CHANNELS_PER_PACKET;
    uint8_t _sequenceNum = 0;
};

/**
 * @brief DMX serial output protocol.
 *
 * Implements DMX512 output over a serial port (USB-to-DMX adapter).
 */
class DMXOutput : public OutputProtocol {
public:
    DMXOutput();
    ~DMXOutput() override;

    // Lifecycle
    bool open() override;
    void close() override;
    bool isOpen() const override { return _serialFd >= 0; }

    // Data transmission
    bool sendFrame(const uint8_t* data, size_t channels) override;

    // Protocol info
    std::string protocolName() const override { return PROTOCOL_DMX; }
    bool isNetworkProtocol() const override { return false; }
    size_t maxChannels() const override { return DMX_MAX_CHANNELS; }

    // DMX-specific configuration
    void setSerialPort(const std::string& port);
    std::string serialPort() const { return _port; }

    void setBaudRate(int baud);
    int baudRate() const { return _baudRate; }

private:
    int _serialFd = -1;
    std::string _port;
    int _baudRate = 250000;
};

/**
 * @brief Null output for testing.
 *
 * Accepts data but does not transmit it anywhere.
 * Useful for testing and debugging.
 */
class NullOutput : public OutputProtocol {
public:
    NullOutput();
    ~NullOutput() override = default;

    // Lifecycle
    bool open() override { _isOpen = true; return true; }
    void close() override { _isOpen = false; }
    bool isOpen() const override { return _isOpen; }

    // Data transmission
    bool sendFrame(const uint8_t* data, size_t channels) override;

    // Protocol info
    std::string protocolName() const override { return PROTOCOL_NULL; }
    bool isNetworkProtocol() const override { return false; }
    size_t maxChannels() const override { return 2000000; }

private:
    bool _isOpen = false;
};

/**
 * @brief Manages multiple output protocols.
 *
 * Provides coordinated frame transmission across multiple outputs
 * and thread-safe access to the output list.
 */
class OutputManager {
public:
    OutputManager();
    ~OutputManager();

    // Output management

    /**
     * @brief Add an output to the manager.
     * @param output Output protocol to add (takes ownership)
     */
    void addOutput(std::unique_ptr<OutputProtocol> output);

    /**
     * @brief Remove an output by name.
     * @param name Output name to remove
     */
    void removeOutput(const std::string& name);

    /**
     * @brief Get an output by name.
     * @param name Output name
     * @return Pointer to output, or nullptr if not found
     */
    OutputProtocol* getOutput(const std::string& name);

    /**
     * @brief Get all output names.
     */
    std::vector<std::string> outputNames() const;

    /**
     * @brief Get the number of outputs.
     */
    size_t outputCount() const;

    // Lifecycle

    /**
     * @brief Open all outputs.
     * @return true if all outputs opened successfully
     */
    bool openAll();

    /**
     * @brief Close all outputs.
     */
    void closeAll();

    // Frame transmission

    /**
     * @brief Start a frame on all outputs.
     * @param timeMs Current time in milliseconds
     */
    void startFrame(int64_t timeMs);

    /**
     * @brief Send frame data to all enabled outputs.
     * @param data Pointer to channel data
     * @param totalChannels Total number of channels
     * @return true if all sends succeeded
     */
    bool sendFrame(const uint8_t* data, size_t totalChannels);

    /**
     * @brief End frame on all outputs.
     * @param suppressFrames Number of frames to suppress
     */
    void endFrame(int suppressFrames = 0);

    /**
     * @brief Turn all channels off on all outputs.
     */
    void allOff();

    // Statistics

    /**
     * @brief Get total frames sent across all outputs.
     */
    size_t totalFramesSent() const;

    /**
     * @brief Get total errors across all outputs.
     */
    size_t totalErrors() const;

private:
    std::vector<std::unique_ptr<OutputProtocol>> _outputs;
    std::map<std::string, OutputProtocol*> _nameIndex;
    mutable std::mutex _mutex;
};

/**
 * @brief Factory for creating output protocols by name.
 */
class OutputFactory {
public:
    /**
     * @brief Create an output protocol by name.
     * @param protocolName Protocol name (e.g., "E131", "ArtNet")
     * @return New protocol instance, or nullptr if unknown
     */
    static std::unique_ptr<OutputProtocol> create(const std::string& protocolName);

    /**
     * @brief Get list of available protocol names.
     */
    static std::vector<std::string> availableProtocols();
};

} // namespace xlCore
