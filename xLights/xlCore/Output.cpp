/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

/**
 * @file Output.cpp
 * @brief Implementation of xlCore output protocol classes.
 *
 * This file provides stub implementations for the output protocol classes.
 * The actual socket and serial port operations are placeholders that will
 * need platform-specific implementations.
 */

#include "Output.h"

#include <cstring>
#include <algorithm>
#include <stdexcept>

// Platform-specific includes for sockets
#ifdef _WIN32
    #include <winsock2.h>
    #include <ws2tcpip.h>
    #pragma comment(lib, "ws2_32.lib")
    #define SOCKET_ERROR_CODE WSAGetLastError()
    #define CLOSE_SOCKET(s) closesocket(s)
#else
    #include <sys/socket.h>
    #include <netinet/in.h>
    #include <arpa/inet.h>
    #include <unistd.h>
    #include <fcntl.h>
    #include <termios.h>
    #include <errno.h>
    #define SOCKET_ERROR_CODE errno
    #define CLOSE_SOCKET(s) ::close(s)
    #define INVALID_SOCKET -1
    #define SOCKET_ERROR -1
#endif

namespace xlCore {

// ============================================================================
// OutputConfig implementation
// ============================================================================

std::string OutputConfig::getString(const std::string& key, const std::string& defaultValue) const {
    auto it = settings.find(key);
    if (it != settings.end()) {
        return it->second;
    }
    return defaultValue;
}

int OutputConfig::getInt(const std::string& key, int defaultValue) const {
    auto it = settings.find(key);
    if (it != settings.end()) {
        try {
            return std::stoi(it->second);
        } catch (...) {
            return defaultValue;
        }
    }
    return defaultValue;
}

bool OutputConfig::getBool(const std::string& key, bool defaultValue) const {
    auto it = settings.find(key);
    if (it != settings.end()) {
        const std::string& val = it->second;
        if (val == "true" || val == "1" || val == "yes" || val == "True" || val == "TRUE") {
            return true;
        }
        if (val == "false" || val == "0" || val == "no" || val == "False" || val == "FALSE") {
            return false;
        }
    }
    return defaultValue;
}

double OutputConfig::getDouble(const std::string& key, double defaultValue) const {
    auto it = settings.find(key);
    if (it != settings.end()) {
        try {
            return std::stod(it->second);
        } catch (...) {
            return defaultValue;
        }
    }
    return defaultValue;
}

void OutputConfig::setString(const std::string& key, const std::string& value) {
    settings[key] = value;
}

void OutputConfig::setInt(const std::string& key, int value) {
    settings[key] = std::to_string(value);
}

void OutputConfig::setBool(const std::string& key, bool value) {
    settings[key] = value ? "true" : "false";
}

void OutputConfig::setDouble(const std::string& key, double value) {
    settings[key] = std::to_string(value);
}

// ============================================================================
// OutputProtocol base class implementation
// ============================================================================

void OutputProtocol::configure(const OutputConfig& config) {
    _config = config;
    ensureFrameBuffer(_config.channelCount);
}

void OutputProtocol::startFrame(int64_t timeMs) {
    _currentTimeMs = timeMs;
    _changed = false;
}

void OutputProtocol::endFrame(int suppressFrames) {
    // Base implementation does nothing
    // Derived classes may use this for duplicate frame suppression
}

void OutputProtocol::setChannel(size_t channel, uint8_t value) {
    if (channel < _frameData.size()) {
        if (_frameData[channel] != value) {
            _frameData[channel] = value;
            _changed = true;
        }
    }
}

void OutputProtocol::setChannels(size_t startChannel, const uint8_t* data, size_t count) {
    if (startChannel >= _frameData.size()) return;

    size_t copyCount = std::min(count, _frameData.size() - startChannel);
    if (std::memcmp(&_frameData[startChannel], data, copyCount) != 0) {
        std::memcpy(&_frameData[startChannel], data, copyCount);
        _changed = true;
    }
}

void OutputProtocol::allOff() {
    if (!_frameData.empty()) {
        std::memset(_frameData.data(), 0, _frameData.size());
        _changed = true;
    }
}

std::string OutputProtocol::statusString() const {
    if (isOpen()) {
        return "Connected";
    }
    return "Disconnected";
}

void OutputProtocol::ensureFrameBuffer(size_t channels) {
    if (_frameData.size() != channels) {
        _frameData.resize(channels, 0);
    }
}

// ============================================================================
// E131Output implementation
// ============================================================================

// E1.31 packet constants
constexpr size_t E131_PACKET_HEADERLEN = 126;
constexpr size_t E131_PACKET_LEN = E131_PACKET_HEADERLEN + 512;

// xLights UUID for source identification
static const char* XLIGHTS_UUID = "c0de0080-c69b-11e0-9572-0800200c9a66";

E131Output::E131Output() {
    _packet.resize(E131_PACKET_LEN, 0);
}

E131Output::~E131Output() {
    close();
}

bool E131Output::open() {
    if (!_config.enabled) return true;
    if (_ip.empty() && !_multicast) return false;

    // Create UDP socket
    _socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (_socket == INVALID_SOCKET) {
        _errors++;
        return false;
    }

    // Enable broadcast/multicast
    int one = 1;
    setsockopt(_socket, SOL_SOCKET, SO_BROADCAST, (const char*)&one, sizeof(one));

    // Build the packet header
    buildPacketHeader();

    _sequenceNum = 0;
    _framesSent = 0;
    return true;
}

void E131Output::close() {
    if (_socket >= 0) {
        CLOSE_SOCKET(_socket);
        _socket = -1;
    }
}

bool E131Output::sendFrame(const uint8_t* data, size_t channels) {
    if (!isOpen() || !_config.enabled) return false;
    if (_socket < 0) return false;

    size_t sendChannels = std::min(channels, static_cast<size_t>(E131_MAX_CHANNELS));

    // Update sequence number
    _packet[111] = _sequenceNum;

    // Copy channel data into packet (starting after header + start code)
    std::memcpy(&_packet[E131_PACKET_HEADERLEN], data, sendChannels);

    // Build destination address
    struct sockaddr_in destAddr;
    std::memset(&destAddr, 0, sizeof(destAddr));
    destAddr.sin_family = AF_INET;
    destAddr.sin_port = htons(E131_PORT);

    if (_multicast) {
        // Multicast address: 239.255.{universe_high}.{universe_low}
        uint8_t univHi = (_universe >> 8) & 0xFF;
        uint8_t univLo = _universe & 0xFF;
        char mcAddr[32];
        snprintf(mcAddr, sizeof(mcAddr), "239.255.%d.%d", univHi, univLo);
        inet_pton(AF_INET, mcAddr, &destAddr.sin_addr);
    } else {
        inet_pton(AF_INET, _ip.c_str(), &destAddr.sin_addr);
    }

    // Calculate actual packet size based on channel count
    size_t packetSize = E131_PACKET_HEADERLEN + sendChannels;

    // Send the packet
    ssize_t sent = sendto(_socket, (const char*)_packet.data(), packetSize, 0,
                          (struct sockaddr*)&destAddr, sizeof(destAddr));

    if (sent < 0) {
        _errors++;
        return false;
    }

    _sequenceNum++;
    _framesSent++;
    return true;
}

void E131Output::setUniverse(int universe) {
    _universe = universe;
    if (isOpen()) {
        // Update universe in packet header
        _packet[113] = (_universe >> 8) & 0xFF;
        _packet[114] = _universe & 0xFF;
    }
}

void E131Output::setMulticast(bool multicast) {
    _multicast = multicast;
}

void E131Output::setPriority(int priority) {
    _priority = std::clamp(priority, 0, 200);
    if (isOpen()) {
        _packet[108] = static_cast<uint8_t>(_priority);
    }
}

void E131Output::setIP(const std::string& ip) {
    _ip = ip;
}

void E131Output::buildPacketHeader() {
    std::memset(_packet.data(), 0, _packet.size());

    // RLP preamble
    _packet[1] = 0x10;  // Preamble size (low byte)

    // ACN Packet Identifier "ASC-E1.17"
    _packet[4] = 0x41;  // 'A'
    _packet[5] = 0x53;  // 'S'
    _packet[6] = 0x43;  // 'C'
    _packet[7] = 0x2d;  // '-'
    _packet[8] = 0x45;  // 'E'
    _packet[9] = 0x31;  // '1'
    _packet[10] = 0x2e; // '.'
    _packet[11] = 0x31; // '1'
    _packet[12] = 0x37; // '7'

    // RLP Protocol flags and length
    size_t rlpLen = E131_PACKET_LEN - 16;
    _packet[16] = 0x70 | ((rlpLen >> 8) & 0x0F);
    _packet[17] = rlpLen & 0xFF;

    // Vector (VECTOR_ROOT_E131_DATA = 0x00000004)
    _packet[21] = 0x04;

    // CID (Component Identifier) - parse UUID
    const char* uuid = XLIGHTS_UUID;
    int j = 22;
    for (int i = 0; uuid[i] != '\0' && j < 38; i++) {
        if (uuid[i] == '-') continue;
        char hex[3] = {uuid[i], uuid[i+1], '\0'};
        i++;
        _packet[j++] = static_cast<uint8_t>(strtol(hex, nullptr, 16));
    }

    // Framing layer flags and length
    size_t frameLen = E131_PACKET_LEN - 38;
    _packet[38] = 0x70 | ((frameLen >> 8) & 0x0F);
    _packet[39] = frameLen & 0xFF;

    // Vector (VECTOR_E131_DATA_PACKET = 0x00000002)
    _packet[43] = 0x02;

    // Source name (64 bytes at offset 44)
    const char* sourceName = "xLights xlCore";
    std::strncpy(reinterpret_cast<char*>(&_packet[44]), sourceName, 63);

    // Priority
    _packet[108] = static_cast<uint8_t>(_priority);

    // Synchronization address (universe 0 = no sync)
    _packet[109] = 0;
    _packet[110] = 0;

    // Sequence number (will be updated per frame)
    _packet[111] = 0;

    // Options (no preview, no stream terminated)
    _packet[112] = 0;

    // Universe
    _packet[113] = (_universe >> 8) & 0xFF;
    _packet[114] = _universe & 0xFF;

    // DMP layer
    size_t dmpLen = E131_PACKET_LEN - 115;
    _packet[115] = 0x70 | ((dmpLen >> 8) & 0x0F);
    _packet[116] = dmpLen & 0xFF;

    // DMP Vector (VECTOR_DMP_SET_PROPERTY = 0x02)
    _packet[117] = 0x02;

    // Address type & data type
    _packet[118] = 0xa1;

    // First property address
    _packet[119] = 0;
    _packet[120] = 0;

    // Address increment
    _packet[121] = 0;
    _packet[122] = 0x01;

    // Property value count (channels + 1 for start code)
    size_t propCount = _config.channelCount + 1;
    _packet[123] = (propCount >> 8) & 0xFF;
    _packet[124] = propCount & 0xFF;

    // Start code (0 for DMX)
    _packet[125] = 0;
}

// ============================================================================
// ArtNetOutput implementation
// ============================================================================

// Art-Net packet constants
constexpr size_t ARTNET_PACKET_HEADERLEN = 18;
constexpr size_t ARTNET_PACKET_LEN = ARTNET_PACKET_HEADERLEN + 512;

ArtNetOutput::ArtNetOutput() {
    _packet.resize(ARTNET_PACKET_LEN, 0);
}

ArtNetOutput::~ArtNetOutput() {
    close();
}

bool ArtNetOutput::open() {
    if (!_config.enabled) return true;
    if (_ip.empty()) return false;

    _socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (_socket == INVALID_SOCKET) {
        _errors++;
        return false;
    }

    int one = 1;
    setsockopt(_socket, SOL_SOCKET, SO_BROADCAST, (const char*)&one, sizeof(one));

    buildPacketHeader();

    _sequenceNum = 0;
    _framesSent = 0;
    return true;
}

void ArtNetOutput::close() {
    if (_socket >= 0) {
        CLOSE_SOCKET(_socket);
        _socket = -1;
    }
}

bool ArtNetOutput::sendFrame(const uint8_t* data, size_t channels) {
    if (!isOpen() || !_config.enabled) return false;
    if (_socket < 0) return false;

    size_t sendChannels = std::min(channels, static_cast<size_t>(ARTNET_MAX_CHANNELS));

    // Update sequence number
    _packet[12] = _sequenceNum;

    // Update length (high, low)
    _packet[16] = (sendChannels >> 8) & 0xFF;
    _packet[17] = sendChannels & 0xFF;

    // Copy channel data
    std::memcpy(&_packet[ARTNET_PACKET_HEADERLEN], data, sendChannels);

    // Build destination address
    struct sockaddr_in destAddr;
    std::memset(&destAddr, 0, sizeof(destAddr));
    destAddr.sin_family = AF_INET;
    destAddr.sin_port = htons(ARTNET_PORT);
    inet_pton(AF_INET, _ip.c_str(), &destAddr.sin_addr);

    size_t packetSize = ARTNET_PACKET_HEADERLEN + sendChannels;

    ssize_t sent = sendto(_socket, (const char*)_packet.data(), packetSize, 0,
                          (struct sockaddr*)&destAddr, sizeof(destAddr));

    if (sent < 0) {
        _errors++;
        return false;
    }

    _sequenceNum++;
    _framesSent++;
    return true;
}

void ArtNetOutput::setUniverse(int universe) {
    _universe = universe;
    if (isOpen()) {
        _packet[14] = _universe & 0xFF;
        _packet[15] = (_universe >> 8) & 0xFF;
    }
}

void ArtNetOutput::setIP(const std::string& ip) {
    _ip = ip;
}

void ArtNetOutput::buildPacketHeader() {
    std::memset(_packet.data(), 0, _packet.size());

    // Art-Net header "Art-Net\0"
    _packet[0] = 'A';
    _packet[1] = 'r';
    _packet[2] = 't';
    _packet[3] = '-';
    _packet[4] = 'N';
    _packet[5] = 'e';
    _packet[6] = 't';
    _packet[7] = 0;

    // OpCode (ArtDmx = 0x5000) - little endian
    _packet[8] = 0x00;
    _packet[9] = 0x50;

    // Protocol version (14) - big endian
    _packet[10] = 0;
    _packet[11] = 14;

    // Sequence (will be updated per frame)
    _packet[12] = 0;

    // Physical port
    _packet[13] = 0;

    // Universe (little endian)
    _packet[14] = _universe & 0xFF;
    _packet[15] = (_universe >> 8) & 0xFF;

    // Length (big endian) - will be updated per frame
    _packet[16] = 0x02;  // 512 >> 8
    _packet[17] = 0x00;  // 512 & 0xFF
}

// ============================================================================
// DDPOutput implementation
// ============================================================================

// DDP packet constants
constexpr size_t DDP_PACKET_HEADERLEN = 10;

DDPOutput::DDPOutput() = default;

DDPOutput::~DDPOutput() {
    close();
}

bool DDPOutput::open() {
    if (!_config.enabled) return true;
    if (_ip.empty()) return false;

    _socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (_socket == INVALID_SOCKET) {
        _errors++;
        return false;
    }

    _sequenceNum = 0;
    _framesSent = 0;
    return true;
}

void DDPOutput::close() {
    if (_socket >= 0) {
        CLOSE_SOCKET(_socket);
        _socket = -1;
    }
}

bool DDPOutput::sendFrame(const uint8_t* data, size_t channels) {
    if (!isOpen() || !_config.enabled) return false;
    if (_socket < 0) return false;

    struct sockaddr_in destAddr;
    std::memset(&destAddr, 0, sizeof(destAddr));
    destAddr.sin_family = AF_INET;
    destAddr.sin_port = htons(DDP_PORT);
    inet_pton(AF_INET, _ip.c_str(), &destAddr.sin_addr);

    // DDP can send large amounts of data, split into packets
    size_t offset = 0;
    while (offset < channels) {
        size_t chunkSize = std::min(static_cast<size_t>(_channelsPerPacket), channels - offset);
        bool isLast = (offset + chunkSize >= channels);

        // Build DDP packet
        std::vector<uint8_t> packet(DDP_PACKET_HEADERLEN + chunkSize);

        // Flags
        uint8_t flags = 0x41;  // Version 1, no timecode
        if (isLast) flags |= 0x01;  // Push flag on last packet
        packet[0] = flags;

        // Sequence
        packet[1] = _sequenceNum & 0x0F;

        // Data type (1 = RGB)
        packet[2] = 0x01;

        // ID
        packet[3] = static_cast<uint8_t>(_id);

        // Offset (big endian 32-bit)
        packet[4] = (offset >> 24) & 0xFF;
        packet[5] = (offset >> 16) & 0xFF;
        packet[6] = (offset >> 8) & 0xFF;
        packet[7] = offset & 0xFF;

        // Length (big endian 16-bit)
        packet[8] = (chunkSize >> 8) & 0xFF;
        packet[9] = chunkSize & 0xFF;

        // Data
        std::memcpy(&packet[DDP_PACKET_HEADERLEN], data + offset, chunkSize);

        ssize_t sent = sendto(_socket, (const char*)packet.data(), packet.size(), 0,
                              (struct sockaddr*)&destAddr, sizeof(destAddr));

        if (sent < 0) {
            _errors++;
            return false;
        }

        offset += chunkSize;
    }

    _sequenceNum++;
    _framesSent++;
    return true;
}

void DDPOutput::setID(int id) {
    _id = id;
}

void DDPOutput::setIP(const std::string& ip) {
    _ip = ip;
}

void DDPOutput::setChannelsPerPacket(int cpp) {
    _channelsPerPacket = std::clamp(cpp, 1, DDP_MAX_CHANNELS_PER_PACKET);
}

// ============================================================================
// DMXOutput implementation
// ============================================================================

DMXOutput::DMXOutput() = default;

DMXOutput::~DMXOutput() {
    close();
}

bool DMXOutput::open() {
    if (!_config.enabled) return true;
    if (_port.empty()) return false;

#ifdef _WIN32
    // Windows serial port implementation would use CreateFile
    // This is a stub - actual implementation needed
    _errors++;
    return false;
#else
    // POSIX serial port
    _serialFd = ::open(_port.c_str(), O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (_serialFd < 0) {
        _errors++;
        return false;
    }

    // Configure serial port for DMX
    struct termios tty;
    if (tcgetattr(_serialFd, &tty) != 0) {
        close();
        _errors++;
        return false;
    }

    // Set baud rate - DMX uses 250kbaud
    // Note: B250000 may not be available on all platforms
    // macOS uses a different approach with IOSSIOSPEED ioctl
#ifdef B250000
    cfsetospeed(&tty, B250000);
    cfsetispeed(&tty, B250000);
#else
    // Fall back to B230400 as closest standard baud rate
    // Real DMX output may need platform-specific handling
    cfsetospeed(&tty, B230400);
    cfsetispeed(&tty, B230400);
#endif

    // 8N2 (8 data bits, no parity, 2 stop bits)
    tty.c_cflag &= ~PARENB;
    tty.c_cflag |= CSTOPB;
    tty.c_cflag &= ~CSIZE;
    tty.c_cflag |= CS8;
    tty.c_cflag &= ~CRTSCTS;
    tty.c_cflag |= CREAD | CLOCAL;

    tty.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
    tty.c_iflag &= ~(IXON | IXOFF | IXANY);
    tty.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL);
    tty.c_oflag &= ~OPOST;

    tty.c_cc[VMIN] = 0;
    tty.c_cc[VTIME] = 0;

    if (tcsetattr(_serialFd, TCSANOW, &tty) != 0) {
        close();
        _errors++;
        return false;
    }
#endif

    _framesSent = 0;
    return true;
}

void DMXOutput::close() {
    if (_serialFd >= 0) {
#ifdef _WIN32
        // Windows: CloseHandle
#else
        ::close(_serialFd);
#endif
        _serialFd = -1;
    }
}

bool DMXOutput::sendFrame(const uint8_t* data, size_t channels) {
    if (!isOpen() || !_config.enabled) return false;
    if (_serialFd < 0) return false;

    size_t sendChannels = std::min(channels, static_cast<size_t>(DMX_MAX_CHANNELS));

    // DMX frame: break, MAB, start code, data
    // Note: This is a simplified stub. Real DMX requires precise timing
    // for the break and MAB (Mark After Break) signals.

#ifndef _WIN32
    // Send break (low for >= 88us)
    tcsendbreak(_serialFd, 0);

    // Build DMX packet (start code + data)
    std::vector<uint8_t> packet(sendChannels + 1);
    packet[0] = 0;  // Start code (0 for DMX)
    std::memcpy(&packet[1], data, sendChannels);

    ssize_t written = write(_serialFd, packet.data(), packet.size());
    if (written < 0) {
        _errors++;
        return false;
    }
#endif

    _framesSent++;
    return true;
}

void DMXOutput::setSerialPort(const std::string& port) {
    _port = port;
}

void DMXOutput::setBaudRate(int baud) {
    _baudRate = baud;
}

// ============================================================================
// NullOutput implementation
// ============================================================================

NullOutput::NullOutput() = default;

bool NullOutput::sendFrame(const uint8_t* data, size_t channels) {
    if (!_isOpen || !_config.enabled) return false;
    _framesSent++;
    return true;
}

// ============================================================================
// OutputManager implementation
// ============================================================================

OutputManager::OutputManager() = default;

OutputManager::~OutputManager() {
    closeAll();
}

void OutputManager::addOutput(std::unique_ptr<OutputProtocol> output) {
    std::lock_guard<std::mutex> lock(_mutex);
    std::string name = output->config().name;
    _nameIndex[name] = output.get();
    _outputs.push_back(std::move(output));
}

void OutputManager::removeOutput(const std::string& name) {
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _nameIndex.find(name);
    if (it != _nameIndex.end()) {
        OutputProtocol* ptr = it->second;
        _nameIndex.erase(it);

        auto outputIt = std::find_if(_outputs.begin(), _outputs.end(),
            [ptr](const std::unique_ptr<OutputProtocol>& p) {
                return p.get() == ptr;
            });

        if (outputIt != _outputs.end()) {
            (*outputIt)->close();
            _outputs.erase(outputIt);
        }
    }
}

OutputProtocol* OutputManager::getOutput(const std::string& name) {
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _nameIndex.find(name);
    if (it != _nameIndex.end()) {
        return it->second;
    }
    return nullptr;
}

std::vector<std::string> OutputManager::outputNames() const {
    std::lock_guard<std::mutex> lock(_mutex);
    std::vector<std::string> names;
    names.reserve(_outputs.size());
    for (const auto& output : _outputs) {
        names.push_back(output->config().name);
    }
    return names;
}

size_t OutputManager::outputCount() const {
    std::lock_guard<std::mutex> lock(_mutex);
    return _outputs.size();
}

bool OutputManager::openAll() {
    std::lock_guard<std::mutex> lock(_mutex);
    bool allOk = true;
    for (auto& output : _outputs) {
        if (!output->open()) {
            allOk = false;
        }
    }
    return allOk;
}

void OutputManager::closeAll() {
    std::lock_guard<std::mutex> lock(_mutex);
    for (auto& output : _outputs) {
        output->close();
    }
}

void OutputManager::startFrame(int64_t timeMs) {
    std::lock_guard<std::mutex> lock(_mutex);
    for (auto& output : _outputs) {
        output->startFrame(timeMs);
    }
}

bool OutputManager::sendFrame(const uint8_t* data, size_t totalChannels) {
    std::lock_guard<std::mutex> lock(_mutex);
    bool allOk = true;

    for (auto& output : _outputs) {
        if (output->isEnabled() && output->isOpen()) {
            const auto& config = output->config();
            size_t start = config.startChannel - 1;  // Convert to 0-based
            size_t count = config.channelCount;

            if (start < totalChannels) {
                count = std::min(count, totalChannels - start);
                if (!output->sendFrame(data + start, count)) {
                    allOk = false;
                }
            }
        }
    }

    return allOk;
}

void OutputManager::endFrame(int suppressFrames) {
    std::lock_guard<std::mutex> lock(_mutex);
    for (auto& output : _outputs) {
        output->endFrame(suppressFrames);
    }
}

void OutputManager::allOff() {
    std::lock_guard<std::mutex> lock(_mutex);
    for (auto& output : _outputs) {
        output->allOff();
    }
}

size_t OutputManager::totalFramesSent() const {
    std::lock_guard<std::mutex> lock(_mutex);
    size_t total = 0;
    for (const auto& output : _outputs) {
        total += output->framesSent();
    }
    return total;
}

size_t OutputManager::totalErrors() const {
    std::lock_guard<std::mutex> lock(_mutex);
    size_t total = 0;
    for (const auto& output : _outputs) {
        total += output->errors();
    }
    return total;
}

// ============================================================================
// OutputFactory implementation
// ============================================================================

std::unique_ptr<OutputProtocol> OutputFactory::create(const std::string& protocolName) {
    if (protocolName == PROTOCOL_E131) {
        return std::make_unique<E131Output>();
    }
    if (protocolName == PROTOCOL_ARTNET) {
        return std::make_unique<ArtNetOutput>();
    }
    if (protocolName == PROTOCOL_DDP) {
        return std::make_unique<DDPOutput>();
    }
    if (protocolName == PROTOCOL_DMX) {
        return std::make_unique<DMXOutput>();
    }
    if (protocolName == PROTOCOL_NULL) {
        return std::make_unique<NullOutput>();
    }
    return nullptr;
}

std::vector<std::string> OutputFactory::availableProtocols() {
    return {
        PROTOCOL_E131,
        PROTOCOL_ARTNET,
        PROTOCOL_DDP,
        PROTOCOL_DMX,
        PROTOCOL_NULL
    };
}

} // namespace xlCore
