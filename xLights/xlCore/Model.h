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
 * @file Model.h
 * @brief Abstract model class for lighting fixtures/props.
 *
 * This header provides the base Model class for the xlCore library.
 * Models define the physical layout of lights (pixels) in 3D space,
 * along with their channel mappings for controller output.
 *
 * Design principles:
 * - Zero wxWidgets dependencies
 * - Thread-safe (individual instances)
 * - Pure geometry and channel mapping
 * - Separates geometry from UI/rendering concerns
 */

#include <string>
#include <vector>
#include <map>
#include <memory>
#include <variant>
#include <optional>
#include <cstdint>

#include "Types.h"
#include "Math.h"
#include "Color.h"

namespace xlCore {

/**
 * @brief Coordinate structure for a single point in a node.
 *
 * Each node may have multiple coordinate points (e.g., for nodes
 * representing multiple physical lights).
 */
struct NodeCoord {
    int bufferX = 0;        ///< X position in render buffer
    int bufferY = 0;        ///< Y position in render buffer
    float screenX = 0.0f;   ///< X position on screen (0-1 normalized)
    float screenY = 0.0f;   ///< Y position on screen (0-1 normalized)
    float screenZ = 0.0f;   ///< Z position on screen (0-1 normalized)

    constexpr NodeCoord() = default;
    constexpr NodeCoord(int bx, int by, float sx = 0.0f, float sy = 0.0f, float sz = 0.0f)
        : bufferX(bx), bufferY(by), screenX(sx), screenY(sy), screenZ(sz) {}

    Vec3 screenPosition() const { return Vec3(screenX, screenY, screenZ); }
    Point2D bufferPosition() const { return Point2D(bufferX, bufferY); }
};

/**
 * @brief Node types matching the legacy xLights node types.
 */
enum class NodeType {
    RGB,            ///< Standard RGB node (3 channels)
    RGBW,           ///< RGBW node (4 channels)
    RGBWW,          ///< RGBWW node (5 channels)
    SingleRed,      ///< Single color red (1 channel)
    SingleGreen,    ///< Single color green (1 channel)
    SingleBlue,     ///< Single color blue (1 channel)
    SingleWhite,    ///< Single color white (1 channel)
    Custom,         ///< Custom single color
    Intensity,      ///< Intensity-only node
    SuperString     ///< Multi-channel superstring
};

/**
 * @brief Get the number of channels for a given node type.
 */
inline uint8_t channelsForNodeType(NodeType type) {
    switch (type) {
        case NodeType::RGB: return 3;
        case NodeType::RGBW: return 4;
        case NodeType::RGBWW: return 5;
        case NodeType::SingleRed:
        case NodeType::SingleGreen:
        case NodeType::SingleBlue:
        case NodeType::SingleWhite:
        case NodeType::Custom:
        case NodeType::Intensity: return 1;
        case NodeType::SuperString: return 0; // Variable
        default: return 3;
    }
}

/**
 * @brief A single node (pixel or group of pixels) in a model.
 *
 * Nodes represent the smallest addressable unit in a model.
 * Each node has:
 * - One or more screen/buffer coordinates
 * - A starting channel number
 * - A node type (RGB, RGBW, single color, etc.)
 * - A current color value
 */
class ModelNode {
public:
    ModelNode() = default;

    ModelNode(uint32_t stringNum, NodeType type, uint32_t actChannel = 0)
        : _stringNum(stringNum), _nodeType(type), _actChannel(actChannel),
          _channelCount(channelsForNodeType(type)) {}

    // Coordinate management
    void addCoord(const NodeCoord& coord) { _coords.push_back(coord); }
    void addCoord(int bufX, int bufY) { _coords.emplace_back(bufX, bufY); }
    void clearCoords() { _coords.clear(); }
    void resizeCoords(size_t count) { _coords.resize(count); }

    size_t coordCount() const { return _coords.size(); }
    const NodeCoord& coord(size_t index) const { return _coords[index]; }
    NodeCoord& coord(size_t index) { return _coords[index]; }
    const std::vector<NodeCoord>& coords() const { return _coords; }
    std::vector<NodeCoord>& coords() { return _coords; }

    // Channel information
    uint32_t actChannel() const { return _actChannel; }
    void setActChannel(uint32_t ch) { _actChannel = ch; }

    uint32_t stringNum() const { return _stringNum; }
    void setStringNum(uint32_t num) { _stringNum = num; }

    uint8_t channelCount() const { return _channelCount; }
    void setChannelCount(uint8_t count) { _channelCount = count; }

    NodeType nodeType() const { return _nodeType; }
    void setNodeType(NodeType type) {
        _nodeType = type;
        if (type != NodeType::SuperString) {
            _channelCount = channelsForNodeType(type);
        }
    }

    // Color
    const Color& color() const { return _color; }
    void setColor(const Color& c) { _color = c; }

    // RGB channel offsets (for non-standard channel orders)
    void setRGBOffsets(uint8_t r, uint8_t g, uint8_t b) {
        _rgbOffsets[0] = r;
        _rgbOffsets[1] = g;
        _rgbOffsets[2] = b;
    }
    const uint8_t* rgbOffsets() const { return _rgbOffsets; }

    // Name (optional)
    const std::string& name() const { return _name; }
    void setName(const std::string& n) { _name = n; }
    bool hasName() const { return !_name.empty(); }

    // Mask color (for custom/intensity nodes)
    const Color& maskColor() const { return _maskColor; }
    void setMaskColor(const Color& c) { _maskColor = c; }

    // Visibility
    bool isVisible() const { return !_coords.empty(); }

    // Check if channel is within this node
    bool containsChannel(uint32_t startCh, uint32_t endCh) const {
        return !(endCh < _actChannel || startCh > _actChannel + _channelCount - 1);
    }

    // Get color from channel values
    void setFromChannels(const uint8_t* buf);
    void getForChannels(uint8_t* buf) const;

private:
    std::vector<NodeCoord> _coords;
    uint32_t _actChannel = 0;       ///< Actual channel number (0-based)
    uint32_t _stringNum = 0;        ///< String number this node belongs to
    uint8_t _channelCount = 3;      ///< Number of channels for this node
    NodeType _nodeType = NodeType::RGB;
    uint8_t _rgbOffsets[3] = {0, 1, 2}; ///< Channel offsets for R, G, B
    Color _color;
    Color _maskColor = Color::White();
    std::string _name;
};

/**
 * @brief Property value type for model properties.
 *
 * Properties can be strings, integers, floating-point numbers, or booleans.
 */
using PropertyValue = std::variant<std::string, int64_t, double, bool>;

/**
 * @brief Abstract base class for all model types.
 *
 * Models represent physical lighting fixtures/props with:
 * - A collection of nodes (pixels)
 * - 3D spatial layout
 * - Channel mapping for controller output
 * - Named properties
 *
 * Subclasses implement specific model types (SingleLine, Matrix, etc.)
 * by overriding initializeGeometry().
 */
class Model {
public:
    virtual ~Model() = default;

    // Identity
    const std::string& name() const { return _name; }
    void setName(const std::string& n) { _name = n; }

    /**
     * @brief Get the model type name (e.g., "Single Line", "Matrix").
     */
    virtual std::string modelType() const = 0;

    // Geometry initialization
    /**
     * @brief Initialize the model geometry.
     *
     * Subclasses must implement this to create nodes with proper
     * coordinates based on model properties. This is called after
     * properties are set and when the model needs to be rebuilt.
     */
    virtual void initializeGeometry() = 0;

    /**
     * @brief Check if geometry has been initialized.
     */
    bool isInitialized() const { return _initialized; }

    // Node access
    size_t nodeCount() const { return _nodes.size(); }
    const ModelNode& node(size_t index) const { return _nodes[index]; }
    ModelNode& node(size_t index) { return _nodes[index]; }
    const std::vector<ModelNode>& nodes() const { return _nodes; }
    std::vector<ModelNode>& nodes() { return _nodes; }

    // Buffer dimensions
    int bufferWidth() const { return _bufferWidth; }
    int bufferHeight() const { return _bufferHeight; }
    int bufferDepth() const { return _bufferDepth; }

    // Channel mapping
    uint32_t startChannel() const { return _startChannel; }
    void setStartChannel(uint32_t ch) { _startChannel = ch; }

    /**
     * @brief Get total channel count for this model.
     */
    uint32_t channelCount() const;

    /**
     * @brief Get channel count per node for the primary string type.
     */
    uint8_t channelsPerNode() const { return _channelsPerNode; }

    // String management
    size_t stringCount() const { return _stringStartChannels.size(); }
    uint32_t stringStartChannel(size_t stringIndex) const {
        return stringIndex < _stringStartChannels.size() ? _stringStartChannels[stringIndex] : 0;
    }
    void setStringStartChannel(size_t stringIndex, uint32_t channel);

    // RGB order
    const std::string& rgbOrder() const { return _rgbOrder; }
    void setRgbOrder(const std::string& order) { _rgbOrder = order; }

    // String type
    const std::string& stringType() const { return _stringType; }
    void setStringType(const std::string& type) { _stringType = type; }

    // Single node/channel flags
    bool isSingleNode() const { return _singleNode; }
    void setSingleNode(bool single) { _singleNode = single; }

    bool isSingleChannel() const { return _singleChannel; }
    void setSingleChannel(bool single) { _singleChannel = single; }

    // Direction
    bool isLeftToRight() const { return _isLtoR; }
    void setLeftToRight(bool ltr) { _isLtoR = ltr; }

    bool isBottomToTop() const { return _isBotToTop; }
    void setBottomToTop(bool btt) { _isBotToTop = btt; }

    // Custom color (for single-color models)
    const Color& customColor() const { return _customColor; }
    void setCustomColor(const Color& c) { _customColor = c; }

    // Properties
    void setProperty(const std::string& key, const PropertyValue& value);
    std::optional<PropertyValue> property(const std::string& key) const;

    std::string propertyString(const std::string& key, const std::string& defaultValue = "") const;
    int64_t propertyInt(const std::string& key, int64_t defaultValue = 0) const;
    double propertyDouble(const std::string& key, double defaultValue = 0.0) const;
    bool propertyBool(const std::string& key, bool defaultValue = false) const;

    // Common properties (parm1, parm2, parm3)
    int64_t parm1() const { return propertyInt("parm1", 0); }
    void setParm1(int64_t v) { setProperty("parm1", v); }

    int64_t parm2() const { return propertyInt("parm2", 0); }
    void setParm2(int64_t v) { setProperty("parm2", v); }

    int64_t parm3() const { return propertyInt("parm3", 0); }
    void setParm3(int64_t v) { setProperty("parm3", v); }

    // Bounding box
    Vec3 boundingBoxMin() const { return _boundingBoxMin; }
    Vec3 boundingBoxMax() const { return _boundingBoxMax; }
    Vec3 center() const {
        return (_boundingBoxMin + _boundingBoxMax) * 0.5f;
    }

    /**
     * @brief Recalculate bounding box from node coordinates.
     */
    void updateBoundingBox();

    // Strand/Node names
    const std::string& strandName(size_t index) const {
        return index < _strandNames.size() ? _strandNames[index] : _emptyString;
    }
    void setStrandName(size_t index, const std::string& name);

    const std::string& nodeName(size_t index) const {
        return index < _nodeNames.size() ? _nodeNames[index] : _emptyString;
    }
    void setNodeName(size_t index, const std::string& name);

    // Virtual methods for model-specific behavior

    /**
     * @brief Get number of strands in this model.
     */
    virtual int strandCount() const { return 1; }

    /**
     * @brief Get number of nodes per string.
     */
    virtual int nodesPerString() const { return static_cast<int>(_nodes.size()); }

    /**
     * @brief Map strand and node indices to node index.
     */
    virtual int mapToNodeIndex(int strand, int node) const {
        return strand * nodesPerString() + node;
    }

    /**
     * @brief Get strand length for a specific strand.
     */
    virtual int strandLength(int strand) const {
        return nodesPerString();
    }

    // Change tracking
    uint64_t changeCount() const { return _changeCount; }
    void incrementChangeCount() { ++_changeCount; }

protected:
    // Protected constructor - only subclasses can be instantiated
    Model() = default;

    // Helper methods for geometry initialization
    void clearNodes() { _nodes.clear(); }

    ModelNode& addNode(uint32_t stringNum, NodeType type, uint32_t actChannel = 0);

    void setBufferSize(int width, int height, int depth = 1) {
        _bufferWidth = width;
        _bufferHeight = height;
        _bufferDepth = depth;
    }

    void setNodeCount(size_t numStrings, size_t nodesPerString, const std::string& rgbOrder);

    void markInitialized() { _initialized = true; }

    // Protected data members
    std::vector<ModelNode> _nodes;
    std::vector<uint32_t> _stringStartChannels;
    std::vector<std::string> _strandNames;
    std::vector<std::string> _nodeNames;
    std::map<std::string, PropertyValue> _properties;

    std::string _name;
    std::string _rgbOrder = "RGB";
    std::string _stringType = "RGB Nodes";

    int _bufferWidth = 0;
    int _bufferHeight = 0;
    int _bufferDepth = 0;

    uint32_t _startChannel = 0;
    uint8_t _channelsPerNode = 3;

    bool _singleNode = false;
    bool _singleChannel = false;
    bool _isLtoR = true;
    bool _isBotToTop = true;
    bool _initialized = false;

    Color _customColor;

    Vec3 _boundingBoxMin;
    Vec3 _boundingBoxMax;

    uint64_t _changeCount = 0;

    static const std::string _emptyString;
};

/**
 * @brief Factory for creating model instances by type name.
 */
class ModelFactory {
public:
    /**
     * @brief Create a model of the specified type.
     * @param type The model type name (e.g., "Single Line", "Matrix")
     * @return A unique_ptr to the created model, or nullptr if type unknown
     */
    static std::unique_ptr<Model> create(const std::string& type);

    /**
     * @brief Get list of available model type names.
     */
    static std::vector<std::string> modelTypes();

    /**
     * @brief Register a model type with the factory.
     * @param type The model type name
     * @param creator Function that creates an instance of the model
     */
    using Creator = std::unique_ptr<Model>(*)();
    static void registerType(const std::string& type, Creator creator);

private:
    static std::map<std::string, Creator>& registry();
};

/**
 * @brief Helper template for registering model types.
 */
template<typename T>
class ModelRegistrar {
public:
    explicit ModelRegistrar(const std::string& type) {
        ModelFactory::registerType(type, []() -> std::unique_ptr<Model> {
            return std::make_unique<T>();
        });
    }
};

} // namespace xlCore
