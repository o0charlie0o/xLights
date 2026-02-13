/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "NativeOutputProvider.h"

#import <Foundation/Foundation.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cstring>
#include <algorithm>

// Protocol constants
namespace {
    // E1.31 Constants
    constexpr int E131_PORT = 5568;
    constexpr int E131_PACKET_HEADERLEN = 126;
    constexpr int E131_PACKET_LEN = E131_PACKET_HEADERLEN + 512;
    constexpr int E131_DEFAULT_PRIORITY = 100;
    const char* XLIGHTS_UUID = "c0de0080-c69b-11e0-9572-0800200c9a66";

    // ArtNet Constants
    constexpr int ARTNET_PORT = 0x1936;  // 6454
    constexpr int ARTNET_PACKET_HEADERLEN = 18;
    constexpr int ARTNET_PACKET_LEN = ARTNET_PACKET_HEADERLEN + 512;

    // DDP Constants
    constexpr int DDP_PORT = 4048;
    constexpr int DDP_PACKET_HEADERLEN = 10;
    constexpr int DDP_PACKET_LEN = DDP_PACKET_HEADERLEN + 1440;
    constexpr uint8_t DDP_FLAGS1_VER1 = 0x40;
    constexpr uint8_t DDP_FLAGS1_PUSH = 0x01;
    constexpr uint8_t DDP_ID_DISPLAY = 1;

    // Helper to parse UUID string into bytes
    void parseUUID(const char* uuid, uint8_t* dest) {
        std::string id(uuid);
        // Remove dashes
        id.erase(std::remove(id.begin(), id.end(), '-'), id.end());
        // Convert to lowercase
        std::transform(id.begin(), id.end(), id.begin(), ::tolower);

        for (size_t i = 0, j = 0; i < 32 && j < 16; i += 2, j++) {
            char msb = id[i];
            char lsb = id[i + 1];
            msb -= isdigit(msb) ? '0' : ('a' - 10);
            lsb -= isdigit(lsb) ? '0' : ('a' - 10);
            dest[j] = static_cast<uint8_t>((msb << 4) | lsb);
        }
    }
}

namespace xlEngine {

// ============================================================================
// NativeE131Output Implementation
// ============================================================================

NativeE131Output::NativeE131Output(const std::string& ip, int universe,
                                   int32_t channels, int32_t startChannel,
                                   int priority)
    : _ip(ip)
    , _universe(universe)
    , _channels(std::min(channels, static_cast<int32_t>(512)))
    , _startChannel(startChannel)
    , _priority(priority)
{
    memset(_packet, 0, sizeof(_packet));
    memset(&_remoteAddr, 0, sizeof(_remoteAddr));
}

NativeE131Output::~NativeE131Output() {
    close();
}

bool NativeE131Output::isMulticast() const {
    return _ip.empty() || _ip == "MULTICAST" ||
           (_ip.length() > 7 && _ip.substr(0, 7) == "239.255");
}

void NativeE131Output::buildPacket() {
    // Build E1.31 packet header per ANSI E1.31-2018
    memset(_packet, 0, sizeof(_packet));

    // Root Layer
    _packet[1] = 0x10;   // RLP preamble size (low byte)

    // ACN Packet Identifier (12 bytes): "ASC-E1.17"
    _packet[4] = 'A';
    _packet[5] = 'S';
    _packet[6] = 'C';
    _packet[7] = '-';
    _packet[8] = 'E';
    _packet[9] = '1';
    _packet[10] = '.';
    _packet[11] = '1';
    _packet[12] = '7';

    // RLP Protocol flags and length (high byte has flags)
    int rlpLen = E131_PACKET_LEN - 16 - (512 - _channels);
    _packet[16] = static_cast<uint8_t>((rlpLen >> 8) | 0x70);
    _packet[17] = static_cast<uint8_t>(rlpLen & 0xFF);

    // Vector (0x00000004 for E1.31 data)
    _packet[21] = 0x04;

    // CID (Component Identifier) - 16 bytes
    parseUUID(XLIGHTS_UUID, &_packet[22]);

    // Framing Layer
    int framingLen = E131_PACKET_LEN - 38 - (512 - _channels);
    _packet[38] = static_cast<uint8_t>((framingLen >> 8) | 0x70);
    _packet[39] = static_cast<uint8_t>(framingLen & 0xFF);

    // Vector (0x00000002 for DMP)
    _packet[43] = 0x02;

    // Source Name (64 bytes) - identify as xLights native
    const char* sourceName = "xLights Native";
    strncpy(reinterpret_cast<char*>(&_packet[44]), sourceName, 63);

    // Priority
    _packet[108] = static_cast<uint8_t>(_priority);

    // Synchronization Address (0 = no sync)
    _packet[109] = 0;
    _packet[110] = 0;

    // Sequence Number (will be set per frame)
    _packet[111] = 0;

    // Options (0 = no options)
    _packet[112] = 0;

    // Universe Number
    _packet[113] = static_cast<uint8_t>(_universe >> 8);
    _packet[114] = static_cast<uint8_t>(_universe & 0xFF);

    // DMP Layer
    int dmpLen = E131_PACKET_LEN - 115 - (512 - _channels);
    _packet[115] = static_cast<uint8_t>((dmpLen >> 8) | 0x70);
    _packet[116] = static_cast<uint8_t>(dmpLen & 0xFF);

    // DMP Vector (0x02 = Set Property)
    _packet[117] = 0x02;

    // Address Type & Data Type (0xA1)
    _packet[118] = 0xA1;

    // First Property Address (0x0000)
    _packet[119] = 0;
    _packet[120] = 0;

    // Address Increment (0x0001)
    _packet[121] = 0;
    _packet[122] = 0x01;

    // Property value count (channels + 1 for start code)
    int valueCount = _channels + 1;
    _packet[123] = static_cast<uint8_t>(valueCount >> 8);
    _packet[124] = static_cast<uint8_t>(valueCount & 0xFF);

    // Start code (0x00 for DMX)
    _packet[125] = 0x00;
}

bool NativeE131Output::open() {
    if (_socket >= 0) return true;
    if (_ip.empty() && !isMulticast()) return false;

    // Create UDP socket
    _socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (_socket < 0) {
        NSLog(@"NativeE131Output: Failed to create socket for universe %d", _universe);
        return false;
    }

    // Set socket options for multicast
    if (isMulticast()) {
        int ttl = 1;
        setsockopt(_socket, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof(ttl));

        // Allow multiple sockets to use same port
        int reuse = 1;
        setsockopt(_socket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    }

    // Build remote address
    _remoteAddr.sin_family = AF_INET;
    _remoteAddr.sin_port = htons(E131_PORT);

    if (isMulticast()) {
        // Multicast address: 239.255.<universe_high>.<universe_low>
        uint8_t univHi = static_cast<uint8_t>(_universe >> 8);
        uint8_t univLo = static_cast<uint8_t>(_universe & 0xFF);
        char multicastAddr[32];
        snprintf(multicastAddr, sizeof(multicastAddr), "239.255.%d.%d", univHi, univLo);
        inet_aton(multicastAddr, &_remoteAddr.sin_addr);
    } else {
        inet_aton(_ip.c_str(), &_remoteAddr.sin_addr);
    }

    // Build the packet header
    buildPacket();
    _sequenceNum = 0;

    NSLog(@"NativeE131Output: Opened socket for universe %d -> %s:%d",
          _universe, isMulticast() ? "multicast" : _ip.c_str(), E131_PORT);

    return true;
}

void NativeE131Output::close() {
    if (_socket >= 0) {
        ::close(_socket);
        _socket = -1;
        NSLog(@"NativeE131Output: Closed socket for universe %d", _universe);
    }
}

void NativeE131Output::setChannelData(int32_t channel, const uint8_t* data, size_t size) {
    if (channel < 0 || channel >= _channels) return;

    size_t copySize = std::min(size, static_cast<size_t>(_channels - channel));

    // Channel data starts at offset 126 (E131_PACKET_HEADERLEN)
    if (memcmp(&_packet[E131_PACKET_HEADERLEN + channel], data, copySize) != 0) {
        memcpy(&_packet[E131_PACKET_HEADERLEN + channel], data, copySize);
        _changed = true;
    }
}

void NativeE131Output::sendFrame() {
    if (_socket < 0 || !_changed) return;

    // Update sequence number
    _packet[111] = _sequenceNum;
    _sequenceNum = (_sequenceNum == 255) ? 0 : _sequenceNum + 1;

    // Send the packet
    ssize_t sent = sendto(_socket, _packet, E131_PACKET_LEN - (512 - _channels),
                          0, reinterpret_cast<sockaddr*>(&_remoteAddr),
                          sizeof(_remoteAddr));

    if (sent < 0) {
        NSLog(@"NativeE131Output: Send failed for universe %d: %s",
              _universe, strerror(errno));
    }

    _changed = false;
}

void NativeE131Output::allOff() {
    memset(&_packet[E131_PACKET_HEADERLEN], 0, _channels);
    _changed = true;
}

// ============================================================================
// NativeArtNetOutput Implementation
// ============================================================================

NativeArtNetOutput::NativeArtNetOutput(const std::string& ip, int universe,
                                       int32_t channels, int32_t startChannel)
    : _ip(ip)
    , _universe(universe)
    , _channels(std::min(channels, static_cast<int32_t>(512)))
    , _startChannel(startChannel)
{
    memset(_packet, 0, sizeof(_packet));
    memset(&_remoteAddr, 0, sizeof(_remoteAddr));
}

NativeArtNetOutput::~NativeArtNetOutput() {
    close();
}

void NativeArtNetOutput::buildPacket() {
    memset(_packet, 0, sizeof(_packet));

    // Art-Net header "Art-Net" + null
    _packet[0] = 'A';
    _packet[1] = 'r';
    _packet[2] = 't';
    _packet[3] = '-';
    _packet[4] = 'N';
    _packet[5] = 'e';
    _packet[6] = 't';
    _packet[7] = 0x00;

    // OpCode for ArtDmx (0x5000, little endian)
    _packet[8] = 0x00;
    _packet[9] = 0x50;

    // Protocol version (14, big endian)
    _packet[10] = 0x00;
    _packet[11] = 0x0E;

    // Sequence (will be updated per frame)
    _packet[12] = 0;

    // Physical port (0)
    _packet[13] = 0;

    // Universe (SubUni | Net)
    // Low byte: SubUni (Subnet | Universe)
    // High byte: Net
    _packet[14] = static_cast<uint8_t>(_universe & 0xFF);
    _packet[15] = static_cast<uint8_t>((_universe >> 8) & 0x7F);

    // Length (big endian)
    _packet[16] = static_cast<uint8_t>(_channels >> 8);
    _packet[17] = static_cast<uint8_t>(_channels & 0xFF);
}

bool NativeArtNetOutput::open() {
    if (_socket >= 0) return true;
    if (_ip.empty()) return false;

    // Create UDP socket
    _socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (_socket < 0) {
        NSLog(@"NativeArtNetOutput: Failed to create socket for universe %d", _universe);
        return false;
    }

    // Build remote address
    _remoteAddr.sin_family = AF_INET;
    _remoteAddr.sin_port = htons(ARTNET_PORT);
    inet_aton(_ip.c_str(), &_remoteAddr.sin_addr);

    // Build the packet header
    buildPacket();
    _sequenceNum = 1;

    NSLog(@"NativeArtNetOutput: Opened socket for universe %d -> %s:%d",
          _universe, _ip.c_str(), ARTNET_PORT);

    return true;
}

void NativeArtNetOutput::close() {
    if (_socket >= 0) {
        ::close(_socket);
        _socket = -1;
        NSLog(@"NativeArtNetOutput: Closed socket for universe %d", _universe);
    }
}

void NativeArtNetOutput::setChannelData(int32_t channel, const uint8_t* data, size_t size) {
    if (channel < 0 || channel >= _channels) return;

    size_t copySize = std::min(size, static_cast<size_t>(_channels - channel));

    // Channel data starts at offset 18 (ARTNET_PACKET_HEADERLEN)
    if (memcmp(&_packet[ARTNET_PACKET_HEADERLEN + channel], data, copySize) != 0) {
        memcpy(&_packet[ARTNET_PACKET_HEADERLEN + channel], data, copySize);
        _changed = true;
    }
}

void NativeArtNetOutput::sendFrame() {
    if (_socket < 0 || !_changed) return;

    // Update sequence number
    _packet[12] = _sequenceNum;
    _sequenceNum = (_sequenceNum == 255) ? 1 : _sequenceNum + 1;

    // Send the packet
    ssize_t sent = sendto(_socket, _packet, ARTNET_PACKET_HEADERLEN + _channels,
                          0, reinterpret_cast<sockaddr*>(&_remoteAddr),
                          sizeof(_remoteAddr));

    if (sent < 0) {
        NSLog(@"NativeArtNetOutput: Send failed for universe %d: %s",
              _universe, strerror(errno));
    }

    _changed = false;
}

void NativeArtNetOutput::allOff() {
    memset(&_packet[ARTNET_PACKET_HEADERLEN], 0, _channels);
    _changed = true;
}

// ============================================================================
// NativeDDPOutput Implementation
// ============================================================================

NativeDDPOutput::NativeDDPOutput(const std::string& ip, int32_t channels,
                                 int32_t startChannel, int channelsPerPacket,
                                 bool keepChannelNumbers)
    : _ip(ip)
    , _channels(channels)
    , _startChannel(startChannel)
    , _channelsPerPacket(channelsPerPacket)
    , _keepChannelNumbers(keepChannelNumbers)
{
    memset(_packet, 0, sizeof(_packet));
    memset(&_remoteAddr, 0, sizeof(_remoteAddr));
}

NativeDDPOutput::~NativeDDPOutput() {
    close();
}

bool NativeDDPOutput::open() {
    if (_socket >= 0) return true;
    if (_ip.empty()) return false;

    // Create UDP socket
    _socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (_socket < 0) {
        NSLog(@"NativeDDPOutput: Failed to create socket for %s", _ip.c_str());
        return false;
    }

    // Build remote address
    _remoteAddr.sin_family = AF_INET;
    _remoteAddr.sin_port = htons(DDP_PORT);
    inet_aton(_ip.c_str(), &_remoteAddr.sin_addr);

    // Allocate channel buffer
    _fulldata.resize(_channels, 0);

    // Initialize packet header
    memset(_packet, 0, sizeof(_packet));
    _packet[2] = 0;  // Reserved
    _packet[3] = DDP_ID_DISPLAY;
    _sequenceNum = 1;

    NSLog(@"NativeDDPOutput: Opened socket for %s:%d (%d channels)",
          _ip.c_str(), DDP_PORT, _channels);

    return true;
}

void NativeDDPOutput::close() {
    if (_socket >= 0) {
        ::close(_socket);
        _socket = -1;
        _fulldata.clear();
        NSLog(@"NativeDDPOutput: Closed socket for %s", _ip.c_str());
    }
}

void NativeDDPOutput::setChannelData(int32_t channel, const uint8_t* data, size_t size) {
    if (channel < 0 || channel >= _channels || _fulldata.empty()) return;

    size_t copySize = std::min(size, static_cast<size_t>(_channels - channel));

    if (memcmp(&_fulldata[channel], data, copySize) != 0) {
        memcpy(&_fulldata[channel], data, copySize);
        _changed = true;
    }
}

void NativeDDPOutput::sendFrame() {
    if (_socket < 0 || !_changed || _fulldata.empty()) return;

    int32_t index = 0;
    int32_t chan = _keepChannelNumbers ? (_startChannel - 1) : 0;
    int32_t tosend = _channels;

    while (tosend > 0) {
        int32_t thissend = std::min(tosend, _channelsPerPacket);

        // Set flags
        if (tosend == thissend) {
            // Last packet - set PUSH flag
            _packet[0] = DDP_FLAGS1_VER1 | DDP_FLAGS1_PUSH;
        } else {
            _packet[0] = DDP_FLAGS1_VER1;
        }

        // Sequence number in lower 4 bits of byte 1
        _packet[1] = (_packet[1] & 0xF0) | (_sequenceNum & 0x0F);

        // Channel offset (big endian, 4 bytes)
        _packet[4] = static_cast<uint8_t>((chan >> 24) & 0xFF);
        _packet[5] = static_cast<uint8_t>((chan >> 16) & 0xFF);
        _packet[6] = static_cast<uint8_t>((chan >> 8) & 0xFF);
        _packet[7] = static_cast<uint8_t>(chan & 0xFF);

        // Data length (big endian, 2 bytes)
        _packet[8] = static_cast<uint8_t>((thissend >> 8) & 0xFF);
        _packet[9] = static_cast<uint8_t>(thissend & 0xFF);

        // Copy channel data
        memcpy(&_packet[DDP_PACKET_HEADERLEN], &_fulldata[index], thissend);

        // Send the packet
        ssize_t sent = sendto(_socket, _packet, DDP_PACKET_HEADERLEN + thissend,
                              0, reinterpret_cast<sockaddr*>(&_remoteAddr),
                              sizeof(_remoteAddr));

        if (sent < 0) {
            NSLog(@"NativeDDPOutput: Send failed for %s: %s",
                  _ip.c_str(), strerror(errno));
        }

        // Update sequence number (wraps 1-15, not 0-15)
        _sequenceNum = (_sequenceNum == 15) ? 1 : _sequenceNum + 1;

        tosend -= thissend;
        index += thissend;
        chan += thissend;
    }

    _changed = false;
}

void NativeDDPOutput::allOff() {
    if (!_fulldata.empty()) {
        memset(_fulldata.data(), 0, _fulldata.size());
        _changed = true;
    }
}

// ============================================================================
// NativeOutputProvider Implementation
// ============================================================================

NativeOutputProvider::NativeOutputProvider() {
}

NativeOutputProvider::~NativeOutputProvider() {
    stopOutput();
}

static std::string normalizeProtocol(NSString* proto) {
    if (!proto) return "";
    NSString* lower = [proto lowercaseString];
    if ([lower isEqualToString:@"e131"] || [lower isEqualToString:@"e1.31"]) return "E131";
    if ([lower isEqualToString:@"artnet"]) return "ArtNet";
    if ([lower isEqualToString:@"ddp"]) return "DDP";
    if ([lower isEqualToString:@"dmx"]) return "DMX";
    if ([lower isEqualToString:@"lor"]) return "LOR";
    if ([lower isEqualToString:@"renard"]) return "Renard";
    if ([lower isEqualToString:@"zcpp"]) return "ZCPP";
    if ([lower isEqualToString:@"opc"]) return "OPC";
    return [proto UTF8String];
}

static std::string getAttr(NSXMLElement* node, NSString* name) {
    NSString* val = [[node attributeForName:name] stringValue];
    return val ? [val UTF8String] : "";
}

static int getAttrInt(NSXMLElement* node, NSString* name, int defaultVal = 0) {
    NSString* val = [[node attributeForName:name] stringValue];
    return val ? [val intValue] : defaultVal;
}

static float getAttrFloat(NSXMLElement* node, NSString* name, float defaultVal = 0.0f) {
    NSString* val = [[node attributeForName:name] stringValue];
    return val ? [val floatValue] : defaultVal;
}

static bool getAttrBool(NSXMLElement* node, NSString* name, bool defaultVal = false) {
    NSString* val = [[node attributeForName:name] stringValue];
    if (!val) return defaultVal;
    return [val intValue] != 0 || [val caseInsensitiveCompare:@"TRUE"] == NSOrderedSame;
}

bool NativeOutputProvider::loadFromXML(const std::string& xmlPath) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    @autoreleasepool {
        NSString* path = [NSString stringWithUTF8String:xmlPath.c_str()];
        NSURL* url = [NSURL fileURLWithPath:path];

        NSError* error = nil;
        NSXMLDocument* doc = [[NSXMLDocument alloc] initWithContentsOfURL:url
                                                                  options:0
                                                                    error:&error];
        if (!doc) {
            NSLog(@"NativeOutputProvider: Failed to load XML from %@: %@",
                  path, error.localizedDescription);
            return false;
        }

        _controllers.clear();
        _cachedTotalChannels = -1;

        // Parse <Controller> elements — these are the real controllers
        NSArray* controllerNodes = [doc.rootElement nodesForXPath:@"Controller" error:nil];
        int32_t cumulativeChannel = 1;

        for (NSXMLElement* node in controllerNodes) {
            NSString* ctrlName = [[node attributeForName:@"Name"] stringValue];
            if (!ctrlName || ctrlName.length == 0) continue;

            NativeControllerConfig config;
            config.name = [ctrlName UTF8String];
            config.description = getAttr(node, @"Description");
            config.id = getAttrInt(node, @"Id");

            // Type
            std::string typeStr = getAttr(node, @"Type");
            if (typeStr == "Serial") {
                config.type = OutputControllerType::Serial;
            } else if (typeStr == "Null") {
                config.type = OutputControllerType::Null;
            } else {
                config.type = OutputControllerType::Ethernet;
            }

            // Connection
            config.ip = getAttr(node, @"IP");
            config.commPort = getAttr(node, @"CommPort");
            config.protocol = normalizeProtocol([[node attributeForName:@"Protocol"] stringValue]);
            config.priority = getAttrInt(node, @"Priority", 100);
            config.fppProxy = getAttr(node, @"FPPProxy");
            config.forceLocalIP = getAttr(node, @"ForceLocalIP");
            config.universePerString = getAttrBool(node, @"UPS");

            // Hardware ID
            config.vendor = getAttr(node, @"Vendor");
            config.model = getAttr(node, @"Model");
            config.variant = getAttr(node, @"Variant");

            // State
            std::string activeStr = getAttr(node, @"ActiveState");
            config.activeState = activeStr;
            config.active = (activeStr != "Inactive");
            config.autoLayout = getAttrBool(node, @"AutoLayout");
            config.autoSize = getAttrBool(node, @"AutoSize");
            config.autoUpload = getAttrBool(node, @"AutoUpload");
            config.suppressDuplicateFrames = getAttrBool(node, @"SuppressDuplicates");
            config.monitor = getAttrBool(node, @"Monitor", true);
            config.fromBase = getAttrBool(node, @"FromBase");
            config.fullxLightsControl = getAttrBool(node, @"FullxLightsControl");
            config.defaultBrightness = getAttrInt(node, @"DefaultBrightnessUnderFullControl", 100);
            config.defaultGamma = getAttrFloat(node, @"DefaultGammaUnderFullControl", 1.0f);

            // Parse child <network> elements as outputs
            int32_t totalChannels = 0;
            int firstUniverse = -1;
            int universeCount = 0;

            NSArray* children = [node children];
            for (NSXMLNode* child in children) {
                if (![child isKindOfClass:[NSXMLElement class]]) continue;
                NSXMLElement* childElem = (NSXMLElement*)child;
                if (![childElem.name isEqualToString:@"network"]) continue;

                NativeOutputConfig output;
                output.ip = getAttr(childElem, @"ComPort");
                output.universe = getAttrInt(childElem, @"BaudRate", 1);
                output.channels = getAttrInt(childElem, @"MaxChannels", 512);
                output.protocol = normalizeProtocol([[childElem attributeForName:@"NetworkType"] stringValue]);
                output.channelsPerPacket = getAttrInt(childElem, @"ChannelsPerPacket", 1440);
                output.keepChannelNumbers = getAttrBool(childElem, @"KeepChannelNumbers", true);
                output.startChannel = cumulativeChannel;

                totalChannels += output.channels;
                if (firstUniverse < 0) firstUniverse = output.universe;
                universeCount++;

                cumulativeChannel += output.channels;
                config.outputs.push_back(output);
            }

            // Set aggregate channel info from child outputs
            if (!config.outputs.empty()) {
                config.startChannel = config.outputs[0].startChannel;
                config.channels = totalChannels;
                config.universe = (firstUniverse >= 0) ? firstUniverse : 1;
                config.universeCount = universeCount;
            } else {
                config.startChannel = cumulativeChannel;
                config.channels = 0;
            }

            NSLog(@"NativeOutputProvider: Loaded controller '%s' — %s %s, %d outputs, %d channels",
                  config.name.c_str(), config.protocol.c_str(), config.ip.c_str(),
                  (int)config.outputs.size(), totalChannels);

            _controllers.push_back(config);
        }

        NSLog(@"NativeOutputProvider: Loaded %lu controllers from %@",
              (unsigned long)_controllers.size(), path);
        return true;
    }
}

bool NativeOutputProvider::parseController(const void* xmlNode, NativeControllerConfig& config) {
    @autoreleasepool {
        NSXMLElement* node = (__bridge NSXMLElement*)xmlNode;

        // Get type attribute to determine protocol
        NSString* typeAttr = [[node attributeForName:@"NetworkType"] stringValue];
        if (!typeAttr) {
            typeAttr = [[node attributeForName:@"Protocol"] stringValue];
        }

        if (!typeAttr) {
            // Check for specific protocol elements
            if ([[node attributeForName:@"ComPort"] stringValue]) {
                config.type = OutputControllerType::Serial;
                config.protocol = "DMX";
            } else {
                config.type = OutputControllerType::Ethernet;
                config.protocol = "E131";  // Default
            }
        } else {
            NSString* typeLower = [typeAttr lowercaseString];
            if ([typeLower isEqualToString:@"e131"] || [typeLower isEqualToString:@"e1.31"]) {
                config.protocol = "E131";
                config.type = OutputControllerType::Ethernet;
            } else if ([typeLower isEqualToString:@"artnet"]) {
                config.protocol = "ArtNet";
                config.type = OutputControllerType::Ethernet;
            } else if ([typeLower isEqualToString:@"ddp"]) {
                config.protocol = "DDP";
                config.type = OutputControllerType::Ethernet;
            } else if ([typeLower isEqualToString:@"dmx"]) {
                config.protocol = "DMX";
                config.type = OutputControllerType::Serial;
            } else {
                config.protocol = [typeAttr UTF8String];
                config.type = OutputControllerType::Ethernet;
            }
        }

        // Get common attributes
        NSString* name = [[node attributeForName:@"Name"] stringValue];
        if (name) config.name = [name UTF8String];

        NSString* desc = [[node attributeForName:@"Description"] stringValue];
        if (desc) config.description = [desc UTF8String];

        NSString* ip = [[node attributeForName:@"IP"] stringValue];
        if (!ip) ip = [[node attributeForName:@"ComPort"] stringValue];
        if (ip) config.ip = [ip UTF8String];

        NSString* universe = [[node attributeForName:@"Universe"] stringValue];
        if (!universe) universe = [[node attributeForName:@"BaudRate"] stringValue];
        if (universe) config.universe = [universe intValue];

        NSString* channels = [[node attributeForName:@"MaxChannels"] stringValue];
        if (!channels) channels = [[node attributeForName:@"Channels"] stringValue];
        if (!channels) channels = [[node attributeForName:@"NumChannels"] stringValue];
        if (channels) config.channels = [channels intValue];

        NSString* startChannel = [[node attributeForName:@"StartChannel"] stringValue];
        if (startChannel) config.startChannel = [startChannel intValue];

        NSString* priority = [[node attributeForName:@"Priority"] stringValue];
        if (priority) config.priority = [priority intValue];

        NSString* cpp = [[node attributeForName:@"ChannelsPerPacket"] stringValue];
        if (cpp) config.channelsPerPacket = [cpp intValue];

        NSString* vendor = [[node attributeForName:@"Vendor"] stringValue];
        if (vendor) config.vendor = [vendor UTF8String];

        NSString* model = [[node attributeForName:@"Model"] stringValue];
        if (model) config.model = [model UTF8String];

        NSString* enabled = [[node attributeForName:@"Enabled"] stringValue];
        if (enabled) config.active = ([enabled intValue] != 0);

        // Check child elements for newer Controller XML format
        // In the newer format, Protocol/Channels/etc. are on child <Connection> or <Output> elements
        NSArray* children = [node children];
        for (NSXMLNode* child in children) {
            if (![child isKindOfClass:[NSXMLElement class]]) continue;
            NSXMLElement* childElem = (NSXMLElement*)child;
            NSString* childName = childElem.name;

            if ([childName isEqualToString:@"Connection"] ||
                [childName isEqualToString:@"Output"] ||
                [childName isEqualToString:@"network"]) {
                // Read protocol from child (overrides parent defaults)
                NSString* proto = [[childElem attributeForName:@"Protocol"] stringValue];
                if (!proto) proto = [[childElem attributeForName:@"NetworkType"] stringValue];
                if (!proto) proto = [[childElem attributeForName:@"Type"] stringValue];
                if (proto) {
                    NSString* protoLower = [proto lowercaseString];
                    if ([protoLower isEqualToString:@"e131"] || [protoLower isEqualToString:@"e1.31"]) {
                        config.protocol = "E131";
                        config.type = OutputControllerType::Ethernet;
                    } else if ([protoLower isEqualToString:@"artnet"]) {
                        config.protocol = "ArtNet";
                        config.type = OutputControllerType::Ethernet;
                    } else if ([protoLower isEqualToString:@"ddp"]) {
                        config.protocol = "DDP";
                        config.type = OutputControllerType::Ethernet;
                    } else if ([protoLower isEqualToString:@"dmx"]) {
                        config.protocol = "DMX";
                        config.type = OutputControllerType::Serial;
                    } else {
                        config.protocol = [proto UTF8String];
                    }
                }

                // Read channels from child
                NSString* ch = [[childElem attributeForName:@"Channels"] stringValue];
                if (!ch) ch = [[childElem attributeForName:@"MaxChannels"] stringValue];
                if (!ch) ch = [[childElem attributeForName:@"NumChannels"] stringValue];
                if (ch && [ch intValue] > 0) config.channels = [ch intValue];

                // Read universe from child
                NSString* uni = [[childElem attributeForName:@"Universe"] stringValue];
                if (uni) config.universe = [uni intValue];

                // Read channels per packet from child (DDP)
                NSString* childCpp = [[childElem attributeForName:@"ChannelsPerPacket"] stringValue];
                if (childCpp) config.channelsPerPacket = [childCpp intValue];

                // Read priority from child (E1.31)
                NSString* childPri = [[childElem attributeForName:@"Priority"] stringValue];
                if (childPri) config.priority = [childPri intValue];

                // Read IP from child if not on parent
                if (config.ip.empty()) {
                    NSString* childIP = [[childElem attributeForName:@"IP"] stringValue];
                    if (childIP) config.ip = [childIP UTF8String];
                }

                // Only use the first connection element
                break;
            }
        }

        // Generate a name if not provided
        if (config.name.empty()) {
            if (!config.ip.empty()) {
                config.name = config.protocol + "_" + config.ip;
                if (config.protocol != "DDP") {
                    config.name += "_" + std::to_string(config.universe);
                }
            } else {
                config.name = "Controller_" + std::to_string(_controllers.size() + 1);
            }
        }

        // Default channels if not specified
        if (config.channels <= 0) {
            config.channels = (config.protocol == "DDP") ? 512 : 512;
        }

        NSLog(@"NativeOutputProvider: Parsed controller '%s' — protocol=%s, ip=%s, channels=%d, startChannel=%d",
              config.name.c_str(), config.protocol.c_str(), config.ip.c_str(),
              config.channels, config.startChannel);

        return !config.ip.empty() || !config.commPort.empty();
    }
}

bool NativeOutputProvider::saveToXML(const std::string& xmlPath) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    @autoreleasepool {
        NSXMLElement* root = [[NSXMLElement alloc] initWithName:@"Networks"];
        // Root attributes
        [root addAttribute:[NSXMLNode attributeWithName:@"computer" stringValue:[[NSHost currentHost] localizedName] ?: @""]];
        [root addAttribute:[NSXMLNode attributeWithName:@"GlobalFPPProxy" stringValue:@""]];
        [root addAttribute:[NSXMLNode attributeWithName:@"GlobalForceLocalIP" stringValue:@""]];

        NSXMLDocument* doc = [[NSXMLDocument alloc] initWithRootElement:root];

        for (const auto& config : _controllers) {
            NSXMLElement* ctrl = [[NSXMLElement alloc] initWithName:@"Controller"];

            // Controller attributes matching legacy format
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"Id" stringValue:[NSString stringWithFormat:@"%d", config.id]]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"Name" stringValue:[NSString stringWithUTF8String:config.name.c_str()]]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"Description" stringValue:[NSString stringWithUTF8String:config.description.c_str()]]];

            NSString* typeStr = @"Ethernet";
            if (config.type == OutputControllerType::Serial) typeStr = @"Serial";
            else if (config.type == OutputControllerType::Null) typeStr = @"Null";
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"Type" stringValue:typeStr]];

            [ctrl addAttribute:[NSXMLNode attributeWithName:@"Vendor" stringValue:[NSString stringWithUTF8String:config.vendor.c_str()]]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"Model" stringValue:[NSString stringWithUTF8String:config.model.c_str()]]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"Variant" stringValue:[NSString stringWithUTF8String:config.variant.c_str()]]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"AutoSize" stringValue:config.autoSize ? @"1" : @"0"]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"FromBase" stringValue:config.fromBase ? @"1" : @"0"]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"FullxLightsControl" stringValue:config.fullxLightsControl ? @"TRUE" : @"FALSE"]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"DefaultBrightnessUnderFullControl" stringValue:[NSString stringWithFormat:@"%d", config.defaultBrightness]]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"DefaultGammaUnderFullControl" stringValue:[NSString stringWithFormat:@"%.0f", config.defaultGamma]]];

            NSString* activeState = @"Active";
            if (!config.activeState.empty()) {
                activeState = [NSString stringWithUTF8String:config.activeState.c_str()];
            } else if (!config.active) {
                activeState = @"Inactive";
            }
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"ActiveState" stringValue:activeState]];

            [ctrl addAttribute:[NSXMLNode attributeWithName:@"AutoLayout" stringValue:config.autoLayout ? @"1" : @"0"]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"AutoUpload" stringValue:config.autoUpload ? @"1" : @"0"]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"SuppressDuplicates" stringValue:config.suppressDuplicateFrames ? @"1" : @"0"]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"Monitor" stringValue:config.monitor ? @"1" : @"0"]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"IP" stringValue:[NSString stringWithUTF8String:config.ip.c_str()]]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"Protocol" stringValue:[NSString stringWithUTF8String:config.protocol.c_str()]]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"FPPProxy" stringValue:[NSString stringWithUTF8String:config.fppProxy.c_str()]]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"Priority" stringValue:[NSString stringWithFormat:@"%d", config.priority]]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"ForceLocalIP" stringValue:[NSString stringWithUTF8String:config.forceLocalIP.c_str()]]];
            [ctrl addAttribute:[NSXMLNode attributeWithName:@"UPS" stringValue:config.universePerString ? @"TRUE" : @"FALSE"]];

            // Write child <network> elements for each output
            for (const auto& output : config.outputs) {
                NSXMLElement* network = [[NSXMLElement alloc] initWithName:@"network"];
                [network addAttribute:[NSXMLNode attributeWithName:@"ComPort" stringValue:[NSString stringWithUTF8String:output.ip.c_str()]]];
                [network addAttribute:[NSXMLNode attributeWithName:@"BaudRate" stringValue:[NSString stringWithFormat:@"%d", output.universe]]];
                [network addAttribute:[NSXMLNode attributeWithName:@"NetworkType" stringValue:[NSString stringWithUTF8String:output.protocol.c_str()]]];
                [network addAttribute:[NSXMLNode attributeWithName:@"MaxChannels" stringValue:[NSString stringWithFormat:@"%d", output.channels]]];

                if (output.protocol == "DDP") {
                    [network addAttribute:[NSXMLNode attributeWithName:@"ChannelsPerPacket" stringValue:[NSString stringWithFormat:@"%d", output.channelsPerPacket]]];
                    [network addAttribute:[NSXMLNode attributeWithName:@"KeepChannelNumbers" stringValue:output.keepChannelNumbers ? @"1" : @"0"]];
                }

                [ctrl addChild:network];
            }

            [root addChild:ctrl];
        }

        NSData* xmlData = [doc XMLDataWithOptions:NSXMLNodePrettyPrint];
        NSString* path = [NSString stringWithUTF8String:xmlPath.c_str()];

        NSError* error = nil;
        if (![xmlData writeToFile:path options:NSDataWritingAtomic error:&error]) {
            NSLog(@"NativeOutputProvider: Failed to save XML to %@: %@",
                  path, error.localizedDescription);
            return false;
        }

        NSLog(@"NativeOutputProvider: Saved %lu controllers to %@",
              (unsigned long)_controllers.size(), path);
        return true;
    }
}

void NativeOutputProvider::addController(const NativeControllerConfig& config) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    _controllers.push_back(config);
    _cachedTotalChannels = -1;
}

bool NativeOutputProvider::removeController(const std::string& name) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    auto it = std::find_if(_controllers.begin(), _controllers.end(),
                          [&name](const NativeControllerConfig& c) {
                              return c.name == name;
                          });

    if (it != _controllers.end()) {
        _controllers.erase(it);
        _outputs.erase(name);
        _cachedTotalChannels = -1;
        return true;
    }
    return false;
}

void NativeOutputProvider::clearControllers() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    stopOutput();
    _controllers.clear();
    _cachedTotalChannels = -1;
}

size_t NativeOutputProvider::getControllerCount() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return _controllers.size();
}

std::optional<ControllerInfo> NativeOutputProvider::getController(size_t index) const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    if (index >= _controllers.size()) return std::nullopt;
    return buildControllerInfo(_controllers[index]);
}

std::optional<ControllerInfo> NativeOutputProvider::getControllerByName(const std::string& name) const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    for (const auto& config : _controllers) {
        if (config.name == name) {
            return buildControllerInfo(config);
        }
    }
    return std::nullopt;
}

std::vector<std::string> NativeOutputProvider::getControllerNames() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    std::vector<std::string> names;
    names.reserve(_controllers.size());
    for (const auto& config : _controllers) {
        names.push_back(config.name);
    }
    return names;
}

bool NativeOutputProvider::controllerExists(const std::string& name) const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    return std::any_of(_controllers.begin(), _controllers.end(),
                      [&name](const NativeControllerConfig& c) {
                          return c.name == name;
                      });
}

bool NativeOutputProvider::isOutputting() const {
    return _outputting.load();
}

bool NativeOutputProvider::startOutput() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (_outputting) return true;

    // Create outputs for all active controllers
    for (const auto& config : _controllers) {
        if (!config.active) continue;

        auto output = createOutput(config);
        if (output && output->open()) {
            _outputs[config.name] = std::move(output);
        } else {
            NSLog(@"NativeOutputProvider: Failed to open output for %s",
                  config.name.c_str());
        }
    }

    _outputting = true;
    NSLog(@"NativeOutputProvider: Started output with %lu active outputs",
          (unsigned long)_outputs.size());

    return true;
}

void NativeOutputProvider::stopOutput() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (!_outputting) return;

    // Turn all outputs off before closing
    for (auto& [name, output] : _outputs) {
        output->allOff();
        output->sendFrame();
        output->close();
    }
    _outputs.clear();

    _outputting = false;
    NSLog(@"NativeOutputProvider: Stopped output");
}

int32_t NativeOutputProvider::getTotalChannels() const {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (_cachedTotalChannels >= 0) return _cachedTotalChannels;

    int32_t total = 0;
    for (const auto& config : _controllers) {
        if (config.active) {
            total += config.channels;
        }
    }

    _cachedTotalChannels = total;
    return total;
}

void NativeOutputProvider::setControllerData(const std::string& name, int32_t channel,
                                             const uint8_t* data, size_t size) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    auto it = _outputs.find(name);
    if (it != _outputs.end()) {
        it->second->setChannelData(channel, data, size);
    }
}

void NativeOutputProvider::setChannelData(int32_t startChannel, const uint8_t* data, size_t size) {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    // Find the output(s) that contain this channel range and set data
    for (auto& [name, output] : _outputs) {
        int32_t outStart = output->getStartChannel();
        int32_t outEnd = outStart + output->getChannels() - 1;

        // Check if ranges overlap
        if (startChannel <= outEnd && static_cast<int32_t>(startChannel + size - 1) >= outStart) {
            // Calculate the overlap
            int32_t overlapStart = std::max(startChannel, outStart);
            int32_t overlapEnd = std::min(static_cast<int32_t>(startChannel + size - 1), outEnd);

            // Calculate offsets
            int32_t dataOffset = overlapStart - startChannel;
            int32_t channelOffset = overlapStart - outStart;
            size_t copySize = overlapEnd - overlapStart + 1;

            output->setChannelData(channelOffset, data + dataOffset, copySize);
        }
    }
}

void NativeOutputProvider::sendFrame() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    for (auto& [name, output] : _outputs) {
        output->sendFrame();
    }
}

void NativeOutputProvider::allOff() {
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    for (auto& [name, output] : _outputs) {
        output->allOff();
    }
}

ControllerInfo NativeOutputProvider::buildControllerInfo(const NativeControllerConfig& config) const {
    ControllerInfo info;

    info.name = config.name;
    info.description = config.description;
    info.id = config.id;
    info.type = config.type;
    info.ip = config.ip;
    info.commPort = config.commPort;
    info.protocol = config.protocol;
    info.fppProxy = config.fppProxy;
    info.forceLocalIP = config.forceLocalIP;
    info.vendor = config.vendor;
    info.model = config.model;
    info.variant = config.variant;
    info.startChannel = config.startChannel;
    info.endChannel = config.startChannel + config.channels - 1;
    info.channels = config.channels;
    info.outputCount = config.outputs.empty() ? 1 : (int)config.outputs.size();
    info.startUniverse = config.universe;
    info.priority = config.priority;
    info.active = config.active;
    info.autoLayout = config.autoLayout;
    info.autoSize = config.autoSize;
    info.managed = config.managed;
    info.autoUpload = config.autoUpload;
    info.fullxLightsControl = config.fullxLightsControl;
    info.defaultBrightness = config.defaultBrightness;
    info.defaultGamma = config.defaultGamma;
    info.suppressDuplicateFrames = config.suppressDuplicateFrames;
    info.monitor = config.monitor;
    info.fromBase = config.fromBase;
    info.universePerString = config.universePerString;
    info.activeState = config.activeState;

    return info;
}

std::unique_ptr<NativeProtocolOutput> NativeOutputProvider::createOutput(
    const NativeControllerConfig& config) {

    if (config.protocol == "E131" || config.protocol == "E1.31") {
        return std::make_unique<NativeE131Output>(
            config.ip, config.universe, config.channels,
            config.startChannel, config.priority);
    }
    else if (config.protocol == "ArtNet") {
        return std::make_unique<NativeArtNetOutput>(
            config.ip, config.universe, config.channels, config.startChannel);
    }
    else if (config.protocol == "DDP") {
        return std::make_unique<NativeDDPOutput>(
            config.ip, config.channels, config.startChannel,
            config.channelsPerPacket, config.keepChannelNumbers);
    }

    NSLog(@"NativeOutputProvider: Unsupported protocol %s for controller %s",
          config.protocol.c_str(), config.name.c_str());
    return nullptr;
}

} // namespace xlEngine
