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
 * @file Sequence.h
 * @brief Sequence data structures and serialization for xlCore.
 *
 * This module provides a pure C++17/20 implementation of xLights sequence
 * file handling, replacing the wxXml-based xLightsXmlFile with modern
 * standards-compliant code.
 *
 * Key components:
 * - EffectSettings: Key-value storage for effect parameters
 * - SequenceEffect: Single effect on timeline
 * - EffectLayer: Layer containing effects
 * - SequenceElement: Model or timing track
 * - Sequence: Complete sequence data
 * - SequenceSerializer: Load/save operations
 * - SequenceData: Rendered frame data (for FSEQ)
 */

#include <string>
#include <vector>
#include <map>
#include <optional>
#include <cstdint>
#include <memory>
#include <functional>

#include "Color.h"
#include "StringUtils.h"

namespace xlCore {

/**
 * @brief Effect settings storage (key-value pairs).
 *
 * This replaces SettingsMap and provides storage for effect parameters.
 * Settings are stored as strings and can be converted to various types.
 */
class EffectSettings {
public:
    EffectSettings() = default;

    // Access
    std::string get(const std::string& key, const std::string& defaultValue = "") const;
    int getInt(const std::string& key, int defaultValue = 0) const;
    double getDouble(const std::string& key, double defaultValue = 0.0) const;
    bool getBool(const std::string& key, bool defaultValue = false) const;

    // Check existence
    bool contains(const std::string& key) const;

    // Modification
    void set(const std::string& key, const std::string& value);
    void setInt(const std::string& key, int value);
    void setDouble(const std::string& key, double value);
    void setBool(const std::string& key, bool value);
    void remove(const std::string& key);
    void clear();

    // Iteration
    const std::map<std::string, std::string>& getAll() const { return _settings; }
    size_t size() const { return _settings.size(); }
    bool empty() const { return _settings.empty(); }

    // Serialization (comma-separated key=value format)
    std::string toString() const;
    static EffectSettings fromString(const std::string& str);

    // Merge settings from another
    void merge(const EffectSettings& other, bool overwrite = true);

    // Remove settings starting with prefix
    void removePrefix(const std::string& prefix);

private:
    std::map<std::string, std::string> _settings;
};

/**
 * @brief Color palette for effects.
 *
 * Stores the color palette associated with an effect.
 */
struct ColorPalette {
    std::vector<Color> colors;
    std::vector<bool> active;  // Which colors are active

    ColorPalette() = default;

    // Serialization
    std::string toString() const;
    static ColorPalette fromString(const std::string& str);

    // Access
    Color getColor(size_t index, const Color& defaultColor = Color::Black()) const;
    bool isActive(size_t index) const;
    size_t size() const { return colors.size(); }
};

/**
 * @brief Single effect on timeline.
 *
 * Represents one effect instance with its type, timing, and parameters.
 */
struct SequenceEffect {
    std::string effectType;        // "Bars", "Fire", "On", etc.
    int startTimeMS = 0;           // Start time in milliseconds
    int endTimeMS = 0;             // End time in milliseconds
    EffectSettings settings;       // Effect-specific parameters
    ColorPalette palette;          // Color palette
    bool isProtected = false;      // Protected from modification
    bool isSelected = false;       // Currently selected in UI
    int id = 0;                    // Unique effect ID

    SequenceEffect() = default;
    SequenceEffect(const std::string& type, int startMS, int endMS)
        : effectType(type), startTimeMS(startMS), endTimeMS(endMS) {}

    // Timing helpers
    int durationMS() const { return endTimeMS - startTimeMS; }
    double startTimeSeconds() const { return startTimeMS / 1000.0; }
    double endTimeSeconds() const { return endTimeMS / 1000.0; }
    double durationSeconds() const { return durationMS() / 1000.0; }

    // Check if effect overlaps with time range
    bool overlaps(int rangeStartMS, int rangeEndMS) const {
        return startTimeMS < rangeEndMS && endTimeMS > rangeStartMS;
    }

    // Check if time is within effect
    bool containsTime(int timeMS) const {
        return timeMS >= startTimeMS && timeMS < endTimeMS;
    }
};

/**
 * @brief Layer containing effects.
 *
 * Each element can have multiple layers, each containing non-overlapping effects.
 */
struct EffectLayer {
    std::string name;                      // Optional layer name
    std::vector<SequenceEffect> effects;   // Effects in this layer

    EffectLayer() = default;
    explicit EffectLayer(const std::string& layerName) : name(layerName) {}

    // Find effects
    SequenceEffect* effectAtTime(int timeMS);
    const SequenceEffect* effectAtTime(int timeMS) const;
    std::vector<SequenceEffect*> effectsInRange(int startMS, int endMS);

    // Add/remove effects
    void addEffect(SequenceEffect effect);
    void removeEffect(size_t index);
    void clearEffects();

    // Sort effects by start time
    void sortEffects();
};

/**
 * @brief Element type enumeration.
 */
enum class ElementType {
    Model,       // Regular model
    ModelGroup,  // Group of models
    Timing,      // Timing track
    SubModel     // Submodel (part of another model)
};

/**
 * @brief Sequence element (model, model group, or timing track).
 */
struct SequenceElement {
    std::string name;              // Element name
    ElementType type = ElementType::Model;
    bool visible = true;           // Visible in sequencer
    bool collapsed = false;        // Collapsed in UI
    bool active = false;           // Active timing track (for timing elements)
    bool renderDisabled = false;   // Rendering disabled
    std::vector<EffectLayer> layers;

    // For timing tracks
    std::string timingType;        // "timing", "lyrics", etc.
    int fixedInterval = 0;         // Fixed timing interval in ms (0 = not fixed)

    SequenceElement() = default;
    SequenceElement(const std::string& elementName, ElementType elementType)
        : name(elementName), type(elementType) {}

    // Layer access
    EffectLayer& getLayer(size_t index);
    const EffectLayer& getLayer(size_t index) const;
    EffectLayer& addLayer();
    void ensureLayers(size_t count);
    size_t layerCount() const { return layers.size(); }

    // Find all effects at a time
    std::vector<SequenceEffect*> effectsAtTime(int timeMS);

    // Type helpers
    bool isModel() const { return type == ElementType::Model || type == ElementType::ModelGroup; }
    bool isTiming() const { return type == ElementType::Timing; }
    bool isModelGroup() const { return type == ElementType::ModelGroup; }
};

/**
 * @brief Sequence metadata.
 */
struct SequenceMetadata {
    std::string author;
    std::string authorEmail;
    std::string authorWebsite;
    std::string song;
    std::string artist;
    std::string album;
    std::string musicUrl;
    std::string comment;
    std::string version;           // xLights version that created this

    double durationSeconds = 30.0;
    int frameIntervalMS = 50;      // Frame interval in milliseconds (20fps = 50ms)
    std::string mediaFile;         // Audio/video file path
    std::string sequenceType = "Animation";  // "Animation" or "Media"
    std::string imageDir;          // Image directory
    bool supportsModelBlending = true;

    SequenceMetadata() = default;

    // Helpers
    int durationMS() const { return static_cast<int>(durationSeconds * 1000); }
    void setDurationMS(int ms) { durationSeconds = ms / 1000.0; }
    double frequency() const { return 1000.0 / frameIntervalMS; }
};

/**
 * @brief Complete sequence.
 *
 * Contains all sequence data including metadata, elements, and effects.
 */
class Sequence {
public:
    Sequence() = default;

    // Metadata
    SequenceMetadata metadata;

    // Elements
    std::vector<SequenceElement> elements;

    // Color palettes (shared across effects)
    std::vector<std::string> colorPalettes;

    // Effect strings database (for efficiency)
    std::vector<std::string> effectStrings;

    // Element access
    SequenceElement* getElement(const std::string& name);
    const SequenceElement* getElement(const std::string& name) const;
    SequenceElement& addElement(const std::string& name, ElementType type);
    void removeElement(const std::string& name);
    size_t elementCount() const { return elements.size(); }

    // Filtered element access
    std::vector<SequenceElement*> timingElements();
    std::vector<SequenceElement*> modelElements();
    std::vector<const SequenceElement*> timingElements() const;
    std::vector<const SequenceElement*> modelElements() const;

    // Find effects
    std::vector<SequenceEffect*> effectsAtTime(int timeMS);
    std::vector<const SequenceEffect*> effectsAtTime(int timeMS) const;
    std::vector<SequenceEffect*> effectsForElement(const std::string& elementName);

    // Get all unique effect types used
    std::vector<std::string> usedEffectTypes() const;

    // Get all file references (images, videos, etc.)
    std::vector<std::string> fileReferences() const;

    // Clear all data
    void clear();

    // Next effect ID generation
    int nextEffectId = 1;
    int generateEffectId() { return nextEffectId++; }
};

/**
 * @brief Rendered sequence data (for FSEQ format).
 *
 * Stores raw channel data for each frame of the sequence.
 */
class SequenceData {
public:
    SequenceData() = default;
    SequenceData(size_t numChannels, size_t numFrames);

    // Resize
    void resize(size_t numChannels, size_t numFrames);
    void clear();

    // Frame access
    uint8_t* frameData(size_t frameIndex);
    const uint8_t* frameData(size_t frameIndex) const;

    // Channel access
    uint8_t getChannel(size_t frame, size_t channel) const;
    void setChannel(size_t frame, size_t channel, uint8_t value);

    // Properties
    size_t numChannels() const { return _numChannels; }
    size_t numFrames() const { return _numFrames; }
    size_t totalSize() const { return _data.size(); }

    // Raw access
    const uint8_t* data() const { return _data.data(); }
    uint8_t* data() { return _data.data(); }

private:
    std::vector<uint8_t> _data;
    size_t _numChannels = 0;
    size_t _numFrames = 0;
};

/**
 * @brief FSEQ file variable header.
 */
struct FSEQVariableHeader {
    char code[2] = {0, 0};
    std::vector<uint8_t> data;
    bool extended = false;

    std::string codeString() const { return std::string(code, 2); }
};

/**
 * @brief FSEQ file information.
 */
struct FSEQInfo {
    std::string filename;
    int versionMajor = 2;
    int versionMinor = 0;
    uint32_t numFrames = 0;
    uint32_t channelCount = 0;
    int stepTimeMS = 50;
    uint64_t uniqueId = 0;
    std::string mediaFilename;
    std::vector<FSEQVariableHeader> variableHeaders;

    // Compression info
    enum class CompressionType { None, Zstd, Zlib };
    CompressionType compression = CompressionType::Zstd;
    int compressionLevel = -1;  // -1 = default

    // Sparse ranges (V2)
    std::vector<std::pair<uint32_t, uint32_t>> sparseRanges;
};

/**
 * @brief Sequence serialization errors.
 */
enum class SerializerError {
    None,
    FileNotFound,
    FileReadError,
    FileWriteError,
    InvalidFormat,
    UnsupportedVersion,
    ParseError,
    CompressionError,
    OutOfMemory
};

/**
 * @brief Sequence serialization result.
 */
struct SerializerResult {
    SerializerError error = SerializerError::None;
    std::string errorMessage;
    std::string warningMessage;

    bool success() const { return error == SerializerError::None; }
    operator bool() const { return success(); }
};

/**
 * @brief Sequence serializer - handles loading and saving.
 *
 * Supports:
 * - xLights XML format (.xLights, .xlights)
 * - FSEQ binary format (.fseq)
 */
class SequenceSerializer {
public:
    SequenceSerializer() = default;

    // xLights XML format
    SerializerResult loadXLights(const std::string& path, Sequence& seq);
    SerializerResult saveXLights(const std::string& path, const Sequence& seq);

    // FSEQ binary format
    SerializerResult loadFSEQ(const std::string& path, FSEQInfo& info);
    SerializerResult loadFSEQData(const std::string& path, SequenceData& data);
    SerializerResult saveFSEQ(const std::string& path, const FSEQInfo& info, const SequenceData& data);

    // Get FSEQ info without loading data
    SerializerResult getFSEQInfo(const std::string& path, FSEQInfo& info);

    // Utility functions
    static std::string getMediaFilenameFromFSEQ(const std::string& path);
    static bool isXLightsFile(const std::string& path);
    static bool isFSEQFile(const std::string& path);

    // Progress callback for long operations
    using ProgressCallback = std::function<void(double progress, const std::string& message)>;
    void setProgressCallback(ProgressCallback callback) { _progressCallback = callback; }

private:
    // XML parsing helpers
    SerializerResult parseXMLHeader(const std::string& content, Sequence& seq);
    SerializerResult parseXMLElements(const std::string& content, Sequence& seq);
    SerializerResult parseXMLDisplayElements(const std::string& content, Sequence& seq);
    SerializerResult parseXMLEffects(const std::string& content, Sequence& seq);

    // XML writing helpers
    std::string generateXMLHeader(const Sequence& seq) const;
    std::string generateXMLElements(const Sequence& seq) const;
    std::string generateXMLDisplayElements(const Sequence& seq) const;
    std::string generateXMLEffects(const Sequence& seq) const;

    // FSEQ helpers
    SerializerResult parseFSEQHeader(const std::vector<uint8_t>& header, FSEQInfo& info);

    ProgressCallback _progressCallback;
};

// ============================================================================
// Inline implementations for small methods
// ============================================================================

inline std::string EffectSettings::get(const std::string& key, const std::string& defaultValue) const {
    auto it = _settings.find(key);
    return (it != _settings.end()) ? it->second : defaultValue;
}

inline int EffectSettings::getInt(const std::string& key, int defaultValue) const {
    auto it = _settings.find(key);
    if (it == _settings.end()) return defaultValue;
    return strings::parseInt(it->second, defaultValue);
}

inline double EffectSettings::getDouble(const std::string& key, double defaultValue) const {
    auto it = _settings.find(key);
    if (it == _settings.end()) return defaultValue;
    return strings::parseDouble(it->second, defaultValue);
}

inline bool EffectSettings::getBool(const std::string& key, bool defaultValue) const {
    auto it = _settings.find(key);
    if (it == _settings.end()) return defaultValue;
    return strings::parseBool(it->second, defaultValue);
}

inline bool EffectSettings::contains(const std::string& key) const {
    return _settings.find(key) != _settings.end();
}

inline void EffectSettings::set(const std::string& key, const std::string& value) {
    _settings[key] = value;
}

inline void EffectSettings::setInt(const std::string& key, int value) {
    _settings[key] = std::to_string(value);
}

inline void EffectSettings::setDouble(const std::string& key, double value) {
    _settings[key] = std::to_string(value);
}

inline void EffectSettings::setBool(const std::string& key, bool value) {
    _settings[key] = value ? "1" : "0";
}

inline void EffectSettings::remove(const std::string& key) {
    _settings.erase(key);
}

inline void EffectSettings::clear() {
    _settings.clear();
}

} // namespace xlCore
