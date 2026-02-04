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
 * @file Model.cpp
 * @brief Implementation of the xlCore Model class.
 */

#include "Model.h"
#include <algorithm>
#include <limits>
#include <cstring>

namespace xlCore {

// Static member initialization
const std::string Model::_emptyString;

//==============================================================================
// ModelNode implementation
//==============================================================================

void ModelNode::setFromChannels(const uint8_t* buf) {
    switch (_nodeType) {
        case NodeType::RGB:
        case NodeType::RGBW:
        case NodeType::RGBWW:
            // Apply RGB offsets for channel order
            _color.red = buf[_rgbOffsets[0]];
            _color.green = buf[_rgbOffsets[1]];
            _color.blue = buf[_rgbOffsets[2]];
            break;

        case NodeType::SingleRed:
            _color.set(buf[0], 0, 0);
            break;

        case NodeType::SingleGreen:
            _color.set(0, buf[0], 0);
            break;

        case NodeType::SingleBlue:
            _color.set(0, 0, buf[0]);
            break;

        case NodeType::SingleWhite:
            _color.set(buf[0], buf[0], buf[0]);
            break;

        case NodeType::Custom:
        case NodeType::Intensity: {
            // Use mask color's hue/saturation with the intensity value
            HSV hsv = _maskColor.toHSV();
            hsv.value = buf[0] / 255.0;
            _color.fromHSV(hsv);
            break;
        }

        case NodeType::SuperString:
            // SuperString handling would need custom logic based on the
            // specific color configuration - for now just use first 3 channels
            if (_channelCount >= 3) {
                _color.set(buf[0], buf[1], buf[2]);
            } else if (_channelCount == 1) {
                _color.set(buf[0], buf[0], buf[0]);
            }
            break;
    }
}

void ModelNode::getForChannels(uint8_t* buf) const {
    switch (_nodeType) {
        case NodeType::RGB:
            buf[_rgbOffsets[0]] = _color.red;
            buf[_rgbOffsets[1]] = _color.green;
            buf[_rgbOffsets[2]] = _color.blue;
            break;

        case NodeType::RGBW:
            buf[_rgbOffsets[0]] = _color.red;
            buf[_rgbOffsets[1]] = _color.green;
            buf[_rgbOffsets[2]] = _color.blue;
            // White channel - take minimum of RGB for a simple approach
            buf[3] = std::min({_color.red, _color.green, _color.blue});
            break;

        case NodeType::RGBWW:
            buf[_rgbOffsets[0]] = _color.red;
            buf[_rgbOffsets[1]] = _color.green;
            buf[_rgbOffsets[2]] = _color.blue;
            buf[3] = std::min({_color.red, _color.green, _color.blue});
            buf[4] = std::min({_color.red, _color.green, _color.blue});
            break;

        case NodeType::SingleRed:
            buf[0] = _color.red;
            break;

        case NodeType::SingleGreen:
            buf[0] = _color.green;
            break;

        case NodeType::SingleBlue:
            buf[0] = _color.blue;
            break;

        case NodeType::SingleWhite:
            buf[0] = std::min({_color.red, _color.green, _color.blue});
            break;

        case NodeType::Custom:
        case NodeType::Intensity: {
            HSV hsv = _color.toHSV();
            buf[0] = static_cast<uint8_t>(hsv.value * 255.0);
            break;
        }

        case NodeType::SuperString:
            // For SuperString, output first 3 channels as RGB
            if (_channelCount >= 3) {
                buf[0] = _color.red;
                buf[1] = _color.green;
                buf[2] = _color.blue;
            } else if (_channelCount == 1) {
                buf[0] = std::max({_color.red, _color.green, _color.blue});
            }
            break;
    }
}

//==============================================================================
// Model implementation
//==============================================================================

uint32_t Model::channelCount() const {
    if (_nodes.empty()) {
        return 0;
    }

    uint32_t minChannel = std::numeric_limits<uint32_t>::max();
    uint32_t maxChannel = 0;

    for (const auto& node : _nodes) {
        minChannel = std::min(minChannel, node.actChannel());
        uint32_t nodeEnd = node.actChannel() + node.channelCount() - 1;
        maxChannel = std::max(maxChannel, nodeEnd);
    }

    return maxChannel >= minChannel ? maxChannel - minChannel + 1 : 0;
}

void Model::setStringStartChannel(size_t stringIndex, uint32_t channel) {
    if (stringIndex >= _stringStartChannels.size()) {
        _stringStartChannels.resize(stringIndex + 1, 0);
    }
    _stringStartChannels[stringIndex] = channel;
}

void Model::setProperty(const std::string& key, const PropertyValue& value) {
    _properties[key] = value;
    incrementChangeCount();
}

std::optional<PropertyValue> Model::property(const std::string& key) const {
    auto it = _properties.find(key);
    if (it != _properties.end()) {
        return it->second;
    }
    return std::nullopt;
}

std::string Model::propertyString(const std::string& key, const std::string& defaultValue) const {
    auto prop = property(key);
    if (!prop.has_value()) {
        return defaultValue;
    }

    const PropertyValue& val = prop.value();
    if (std::holds_alternative<std::string>(val)) {
        return std::get<std::string>(val);
    } else if (std::holds_alternative<int64_t>(val)) {
        return std::to_string(std::get<int64_t>(val));
    } else if (std::holds_alternative<double>(val)) {
        return std::to_string(std::get<double>(val));
    } else if (std::holds_alternative<bool>(val)) {
        return std::get<bool>(val) ? "true" : "false";
    }

    return defaultValue;
}

int64_t Model::propertyInt(const std::string& key, int64_t defaultValue) const {
    auto prop = property(key);
    if (!prop.has_value()) {
        return defaultValue;
    }

    const PropertyValue& val = prop.value();
    if (std::holds_alternative<int64_t>(val)) {
        return std::get<int64_t>(val);
    } else if (std::holds_alternative<double>(val)) {
        return static_cast<int64_t>(std::get<double>(val));
    } else if (std::holds_alternative<std::string>(val)) {
        try {
            return std::stoll(std::get<std::string>(val));
        } catch (...) {
            return defaultValue;
        }
    } else if (std::holds_alternative<bool>(val)) {
        return std::get<bool>(val) ? 1 : 0;
    }

    return defaultValue;
}

double Model::propertyDouble(const std::string& key, double defaultValue) const {
    auto prop = property(key);
    if (!prop.has_value()) {
        return defaultValue;
    }

    const PropertyValue& val = prop.value();
    if (std::holds_alternative<double>(val)) {
        return std::get<double>(val);
    } else if (std::holds_alternative<int64_t>(val)) {
        return static_cast<double>(std::get<int64_t>(val));
    } else if (std::holds_alternative<std::string>(val)) {
        try {
            return std::stod(std::get<std::string>(val));
        } catch (...) {
            return defaultValue;
        }
    }

    return defaultValue;
}

bool Model::propertyBool(const std::string& key, bool defaultValue) const {
    auto prop = property(key);
    if (!prop.has_value()) {
        return defaultValue;
    }

    const PropertyValue& val = prop.value();
    if (std::holds_alternative<bool>(val)) {
        return std::get<bool>(val);
    } else if (std::holds_alternative<int64_t>(val)) {
        return std::get<int64_t>(val) != 0;
    } else if (std::holds_alternative<std::string>(val)) {
        const std::string& s = std::get<std::string>(val);
        return s == "true" || s == "1" || s == "yes" || s == "on";
    }

    return defaultValue;
}

void Model::updateBoundingBox() {
    if (_nodes.empty()) {
        _boundingBoxMin = Vec3::zero();
        _boundingBoxMax = Vec3::zero();
        return;
    }

    float minX = std::numeric_limits<float>::max();
    float minY = std::numeric_limits<float>::max();
    float minZ = std::numeric_limits<float>::max();
    float maxX = std::numeric_limits<float>::lowest();
    float maxY = std::numeric_limits<float>::lowest();
    float maxZ = std::numeric_limits<float>::lowest();

    for (const auto& node : _nodes) {
        for (const auto& coord : node.coords()) {
            minX = std::min(minX, coord.screenX);
            minY = std::min(minY, coord.screenY);
            minZ = std::min(minZ, coord.screenZ);
            maxX = std::max(maxX, coord.screenX);
            maxY = std::max(maxY, coord.screenY);
            maxZ = std::max(maxZ, coord.screenZ);
        }
    }

    _boundingBoxMin = Vec3(minX, minY, minZ);
    _boundingBoxMax = Vec3(maxX, maxY, maxZ);
}

void Model::setStrandName(size_t index, const std::string& name) {
    if (index >= _strandNames.size()) {
        _strandNames.resize(index + 1);
    }
    _strandNames[index] = name;
}

void Model::setNodeName(size_t index, const std::string& name) {
    if (index >= _nodeNames.size()) {
        _nodeNames.resize(index + 1);
    }
    _nodeNames[index] = name;
}

ModelNode& Model::addNode(uint32_t stringNum, NodeType type, uint32_t actChannel) {
    _nodes.emplace_back(stringNum, type, actChannel);
    return _nodes.back();
}

void Model::setNodeCount(size_t numStrings, size_t nodesPerString, const std::string& rgbOrder) {
    _nodes.clear();
    _rgbOrder = rgbOrder;

    // Parse RGB order to get offsets
    uint8_t rOffset = 0, gOffset = 1, bOffset = 2;
    if (rgbOrder.size() >= 3) {
        for (size_t i = 0; i < 3; ++i) {
            char c = std::toupper(rgbOrder[i]);
            if (c == 'R') rOffset = static_cast<uint8_t>(i);
            else if (c == 'G') gOffset = static_cast<uint8_t>(i);
            else if (c == 'B') bOffset = static_cast<uint8_t>(i);
        }
    }

    // Determine node type from string type
    NodeType nodeType = NodeType::RGB;
    if (_stringType.find("Single Color Red") != std::string::npos) {
        nodeType = NodeType::SingleRed;
    } else if (_stringType.find("Single Color Green") != std::string::npos) {
        nodeType = NodeType::SingleGreen;
    } else if (_stringType.find("Single Color Blue") != std::string::npos) {
        nodeType = NodeType::SingleBlue;
    } else if (_stringType.find("Single Color White") != std::string::npos) {
        nodeType = NodeType::SingleWhite;
    } else if (_stringType.find("RGBW") != std::string::npos) {
        if (_stringType.find("RGBWW") != std::string::npos) {
            nodeType = NodeType::RGBWW;
        } else {
            nodeType = NodeType::RGBW;
        }
    }

    _channelsPerNode = channelsForNodeType(nodeType);

    // Resize string start channels
    _stringStartChannels.resize(numStrings, 0);

    // Create nodes
    for (size_t s = 0; s < numStrings; ++s) {
        for (size_t n = 0; n < nodesPerString; ++n) {
            ModelNode& node = addNode(static_cast<uint32_t>(s), nodeType);
            node.setRGBOffsets(rOffset, gOffset, bOffset);
            // Allocate coordinate space
            node.resizeCoords(1);
        }
    }
}

//==============================================================================
// ModelFactory implementation
//==============================================================================

std::map<std::string, ModelFactory::Creator>& ModelFactory::registry() {
    static std::map<std::string, Creator> s_registry;
    return s_registry;
}

void ModelFactory::registerType(const std::string& type, Creator creator) {
    registry()[type] = creator;
}

std::unique_ptr<Model> ModelFactory::create(const std::string& type) {
    auto& reg = registry();
    auto it = reg.find(type);
    if (it != reg.end()) {
        return it->second();
    }
    return nullptr;
}

std::vector<std::string> ModelFactory::modelTypes() {
    std::vector<std::string> types;
    for (const auto& pair : registry()) {
        types.push_back(pair.first);
    }
    return types;
}

} // namespace xlCore
