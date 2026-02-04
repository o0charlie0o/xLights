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
 * @file Sequence.cpp
 * @brief Implementation of sequence data structures and serialization.
 */

#include "Sequence.h"

#include <fstream>
#include <sstream>
#include <algorithm>
#include <cstring>
#include <regex>

namespace xlCore {

// ============================================================================
// EffectSettings Implementation
// ============================================================================

std::string EffectSettings::toString() const {
    if (_settings.empty()) return "";

    std::string result;
    bool first = true;
    for (const auto& [key, value] : _settings) {
        if (!first) result += ",";
        first = false;
        result += key + "=" + value;
    }
    return result;
}

EffectSettings EffectSettings::fromString(const std::string& str) {
    EffectSettings settings;
    if (str.empty()) return settings;

    // Parse comma-separated key=value pairs
    // Handle quoted values that may contain commas
    size_t pos = 0;
    size_t len = str.length();

    while (pos < len) {
        // Find the key
        size_t eqPos = str.find('=', pos);
        if (eqPos == std::string::npos) break;

        std::string key = str.substr(pos, eqPos - pos);

        // Find the value (may be quoted)
        pos = eqPos + 1;
        std::string value;

        if (pos < len && str[pos] == '"') {
            // Quoted value - find closing quote
            pos++; // Skip opening quote
            size_t closeQuote = str.find('"', pos);
            if (closeQuote != std::string::npos) {
                value = str.substr(pos, closeQuote - pos);
                pos = closeQuote + 1;
                // Skip comma after quote
                if (pos < len && str[pos] == ',') pos++;
            }
        } else {
            // Unquoted value - find next comma
            size_t commaPos = str.find(',', pos);
            if (commaPos != std::string::npos) {
                value = str.substr(pos, commaPos - pos);
                pos = commaPos + 1;
            } else {
                value = str.substr(pos);
                pos = len;
            }
        }

        // Trim key and value
        key = strings::trim(key);
        value = strings::trim(value);

        if (!key.empty()) {
            settings.set(key, value);
        }
    }

    return settings;
}

void EffectSettings::merge(const EffectSettings& other, bool overwrite) {
    for (const auto& [key, value] : other._settings) {
        if (overwrite || !contains(key)) {
            _settings[key] = value;
        }
    }
}

void EffectSettings::removePrefix(const std::string& prefix) {
    for (auto it = _settings.begin(); it != _settings.end(); ) {
        if (strings::startsWith(it->first, prefix)) {
            it = _settings.erase(it);
        } else {
            ++it;
        }
    }
}

// ============================================================================
// ColorPalette Implementation
// ============================================================================

std::string ColorPalette::toString() const {
    std::string result;
    for (size_t i = 0; i < colors.size(); ++i) {
        if (i > 0) result += ",";

        // Format: C_BUTTON_Palette{n}=#RRGGBB,C_CHECKBOX_Palette{n}=0|1
        std::string idx = std::to_string(i + 1);
        result += "C_BUTTON_Palette" + idx + "=" + colors[i].toString();

        bool isActive = (i < active.size()) ? active[i] : false;
        result += ",C_CHECKBOX_Palette" + idx + "=" + (isActive ? "1" : "0");
    }
    return result;
}

ColorPalette ColorPalette::fromString(const std::string& str) {
    ColorPalette palette;
    if (str.empty()) return palette;

    // Parse the palette string
    // Format: C_BUTTON_Palette1=#FF0000,C_CHECKBOX_Palette1=1,...
    EffectSettings settings = EffectSettings::fromString(str);

    // Find all palette colors
    for (int i = 1; i <= 8; ++i) {  // Support up to 8 colors
        std::string buttonKey = "C_BUTTON_Palette" + std::to_string(i);
        std::string checkKey = "C_CHECKBOX_Palette" + std::to_string(i);

        if (settings.contains(buttonKey)) {
            std::string colorStr = settings.get(buttonKey);
            Color color(colorStr);
            palette.colors.push_back(color);

            bool isActive = settings.getBool(checkKey, false);
            palette.active.push_back(isActive);
        }
    }

    return palette;
}

Color ColorPalette::getColor(size_t index, const Color& defaultColor) const {
    if (index < colors.size()) {
        return colors[index];
    }
    return defaultColor;
}

bool ColorPalette::isActive(size_t index) const {
    if (index < active.size()) {
        return active[index];
    }
    return false;
}

// ============================================================================
// EffectLayer Implementation
// ============================================================================

SequenceEffect* EffectLayer::effectAtTime(int timeMS) {
    for (auto& effect : effects) {
        if (effect.containsTime(timeMS)) {
            return &effect;
        }
    }
    return nullptr;
}

const SequenceEffect* EffectLayer::effectAtTime(int timeMS) const {
    for (const auto& effect : effects) {
        if (effect.containsTime(timeMS)) {
            return &effect;
        }
    }
    return nullptr;
}

std::vector<SequenceEffect*> EffectLayer::effectsInRange(int startMS, int endMS) {
    std::vector<SequenceEffect*> result;
    for (auto& effect : effects) {
        if (effect.overlaps(startMS, endMS)) {
            result.push_back(&effect);
        }
    }
    return result;
}

void EffectLayer::addEffect(SequenceEffect effect) {
    effects.push_back(std::move(effect));
}

void EffectLayer::removeEffect(size_t index) {
    if (index < effects.size()) {
        effects.erase(effects.begin() + static_cast<std::ptrdiff_t>(index));
    }
}

void EffectLayer::clearEffects() {
    effects.clear();
}

void EffectLayer::sortEffects() {
    std::sort(effects.begin(), effects.end(),
        [](const SequenceEffect& a, const SequenceEffect& b) {
            return a.startTimeMS < b.startTimeMS;
        });
}

// ============================================================================
// SequenceElement Implementation
// ============================================================================

EffectLayer& SequenceElement::getLayer(size_t index) {
    ensureLayers(index + 1);
    return layers[index];
}

const EffectLayer& SequenceElement::getLayer(size_t index) const {
    static EffectLayer emptyLayer;
    if (index < layers.size()) {
        return layers[index];
    }
    return emptyLayer;
}

EffectLayer& SequenceElement::addLayer() {
    layers.emplace_back();
    return layers.back();
}

void SequenceElement::ensureLayers(size_t count) {
    while (layers.size() < count) {
        layers.emplace_back();
    }
}

std::vector<SequenceEffect*> SequenceElement::effectsAtTime(int timeMS) {
    std::vector<SequenceEffect*> result;
    for (auto& layer : layers) {
        if (auto* effect = layer.effectAtTime(timeMS)) {
            result.push_back(effect);
        }
    }
    return result;
}

// ============================================================================
// Sequence Implementation
// ============================================================================

SequenceElement* Sequence::getElement(const std::string& name) {
    for (auto& element : elements) {
        if (element.name == name) {
            return &element;
        }
    }
    return nullptr;
}

const SequenceElement* Sequence::getElement(const std::string& name) const {
    for (const auto& element : elements) {
        if (element.name == name) {
            return &element;
        }
    }
    return nullptr;
}

SequenceElement& Sequence::addElement(const std::string& name, ElementType type) {
    elements.emplace_back(name, type);
    return elements.back();
}

void Sequence::removeElement(const std::string& name) {
    auto it = std::remove_if(elements.begin(), elements.end(),
        [&name](const SequenceElement& elem) {
            return elem.name == name;
        });
    elements.erase(it, elements.end());
}

std::vector<SequenceElement*> Sequence::timingElements() {
    std::vector<SequenceElement*> result;
    for (auto& elem : elements) {
        if (elem.isTiming()) {
            result.push_back(&elem);
        }
    }
    return result;
}

std::vector<SequenceElement*> Sequence::modelElements() {
    std::vector<SequenceElement*> result;
    for (auto& elem : elements) {
        if (elem.isModel()) {
            result.push_back(&elem);
        }
    }
    return result;
}

std::vector<const SequenceElement*> Sequence::timingElements() const {
    std::vector<const SequenceElement*> result;
    for (const auto& elem : elements) {
        if (elem.isTiming()) {
            result.push_back(&elem);
        }
    }
    return result;
}

std::vector<const SequenceElement*> Sequence::modelElements() const {
    std::vector<const SequenceElement*> result;
    for (const auto& elem : elements) {
        if (elem.isModel()) {
            result.push_back(&elem);
        }
    }
    return result;
}

std::vector<SequenceEffect*> Sequence::effectsAtTime(int timeMS) {
    std::vector<SequenceEffect*> result;
    for (auto& elem : elements) {
        auto effects = elem.effectsAtTime(timeMS);
        result.insert(result.end(), effects.begin(), effects.end());
    }
    return result;
}

std::vector<const SequenceEffect*> Sequence::effectsAtTime(int timeMS) const {
    std::vector<const SequenceEffect*> result;
    for (const auto& elem : elements) {
        for (const auto& layer : elem.layers) {
            if (const auto* effect = layer.effectAtTime(timeMS)) {
                result.push_back(effect);
            }
        }
    }
    return result;
}

std::vector<SequenceEffect*> Sequence::effectsForElement(const std::string& elementName) {
    std::vector<SequenceEffect*> result;
    if (auto* elem = getElement(elementName)) {
        for (auto& layer : elem->layers) {
            for (auto& effect : layer.effects) {
                result.push_back(&effect);
            }
        }
    }
    return result;
}

std::vector<std::string> Sequence::usedEffectTypes() const {
    std::vector<std::string> types;
    for (const auto& elem : elements) {
        for (const auto& layer : elem.layers) {
            for (const auto& effect : layer.effects) {
                if (std::find(types.begin(), types.end(), effect.effectType) == types.end()) {
                    types.push_back(effect.effectType);
                }
            }
        }
    }
    return types;
}

std::vector<std::string> Sequence::fileReferences() const {
    std::vector<std::string> files;

    // Add media file if present
    if (!metadata.mediaFile.empty()) {
        files.push_back(metadata.mediaFile);
    }

    // Scan effect settings for file references
    // Common patterns: *_FILEPICKER*, *_File=*, etc.
    std::regex filePattern(".*(?:File|FILEPICKER|Picture|Video|Image).*");

    for (const auto& elem : elements) {
        for (const auto& layer : elem.layers) {
            for (const auto& effect : layer.effects) {
                for (const auto& [key, value] : effect.settings.getAll()) {
                    if (std::regex_match(key, filePattern) && !value.empty()) {
                        if (std::find(files.begin(), files.end(), value) == files.end()) {
                            files.push_back(value);
                        }
                    }
                }
            }
        }
    }

    return files;
}

void Sequence::clear() {
    metadata = SequenceMetadata();
    elements.clear();
    colorPalettes.clear();
    effectStrings.clear();
    nextEffectId = 1;
}

// ============================================================================
// SequenceData Implementation
// ============================================================================

SequenceData::SequenceData(size_t numChannels, size_t numFrames)
    : _numChannels(numChannels), _numFrames(numFrames) {
    _data.resize(numChannels * numFrames, 0);
}

void SequenceData::resize(size_t numChannels, size_t numFrames) {
    _numChannels = numChannels;
    _numFrames = numFrames;
    _data.resize(numChannels * numFrames, 0);
}

void SequenceData::clear() {
    _data.clear();
    _numChannels = 0;
    _numFrames = 0;
}

uint8_t* SequenceData::frameData(size_t frameIndex) {
    if (frameIndex >= _numFrames) return nullptr;
    return _data.data() + (frameIndex * _numChannels);
}

const uint8_t* SequenceData::frameData(size_t frameIndex) const {
    if (frameIndex >= _numFrames) return nullptr;
    return _data.data() + (frameIndex * _numChannels);
}

uint8_t SequenceData::getChannel(size_t frame, size_t channel) const {
    if (frame >= _numFrames || channel >= _numChannels) return 0;
    return _data[frame * _numChannels + channel];
}

void SequenceData::setChannel(size_t frame, size_t channel, uint8_t value) {
    if (frame >= _numFrames || channel >= _numChannels) return;
    _data[frame * _numChannels + channel] = value;
}

// ============================================================================
// SequenceSerializer Implementation
// ============================================================================

namespace {
    // Helper to read entire file
    bool readFile(const std::string& path, std::string& content) {
        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file) return false;

        auto size = file.tellg();
        file.seekg(0, std::ios::beg);

        content.resize(static_cast<size_t>(size));
        file.read(content.data(), size);
        return file.good();
    }

    // Helper to write file
    bool writeFile(const std::string& path, const std::string& content) {
        std::ofstream file(path, std::ios::binary);
        if (!file) return false;
        file.write(content.data(), static_cast<std::streamsize>(content.size()));
        return file.good();
    }

    // Simple XML attribute parser
    std::string getXmlAttribute(const std::string& tag, const std::string& attr) {
        std::string pattern = attr + "=\"";
        size_t start = tag.find(pattern);
        if (start == std::string::npos) {
            pattern = attr + "='";
            start = tag.find(pattern);
        }
        if (start == std::string::npos) return "";

        start += pattern.length();
        char quote = tag[start - 1];
        size_t end = tag.find(quote, start);
        if (end == std::string::npos) return "";

        return tag.substr(start, end - start);
    }

    // XML escape
    std::string xmlEscape(const std::string& str) {
        return strings::escapeXml(str);
    }

    // XML unescape
    std::string xmlUnescape(const std::string& str) {
        std::string result = str;
        result = strings::replaceAll(result, "&amp;", "&");
        result = strings::replaceAll(result, "&lt;", "<");
        result = strings::replaceAll(result, "&gt;", ">");
        result = strings::replaceAll(result, "&quot;", "\"");
        result = strings::replaceAll(result, "&apos;", "'");
        return result;
    }

    // Find content between tags
    std::string getTagContent(const std::string& xml, const std::string& tagName) {
        std::string openTag = "<" + tagName;
        std::string closeTag = "</" + tagName + ">";

        size_t start = xml.find(openTag);
        if (start == std::string::npos) return "";

        // Find end of opening tag
        size_t tagEnd = xml.find('>', start);
        if (tagEnd == std::string::npos) return "";

        // Check for self-closing tag
        if (xml[tagEnd - 1] == '/') return "";

        start = tagEnd + 1;
        size_t end = xml.find(closeTag, start);
        if (end == std::string::npos) return "";

        return xml.substr(start, end - start);
    }

    // Read 2-byte little-endian unsigned int
    uint16_t read2ByteLE(const uint8_t* data) {
        return static_cast<uint16_t>(data[0]) |
               (static_cast<uint16_t>(data[1]) << 8);
    }

    // Read 4-byte little-endian unsigned int
    uint32_t read4ByteLE(const uint8_t* data) {
        return static_cast<uint32_t>(data[0]) |
               (static_cast<uint32_t>(data[1]) << 8) |
               (static_cast<uint32_t>(data[2]) << 16) |
               (static_cast<uint32_t>(data[3]) << 24);
    }

    // Write 2-byte little-endian unsigned int
    void write2ByteLE(uint8_t* data, uint16_t value) {
        data[0] = static_cast<uint8_t>(value & 0xFF);
        data[1] = static_cast<uint8_t>((value >> 8) & 0xFF);
    }

    // Write 4-byte little-endian unsigned int
    void write4ByteLE(uint8_t* data, uint32_t value) {
        data[0] = static_cast<uint8_t>(value & 0xFF);
        data[1] = static_cast<uint8_t>((value >> 8) & 0xFF);
        data[2] = static_cast<uint8_t>((value >> 16) & 0xFF);
        data[3] = static_cast<uint8_t>((value >> 24) & 0xFF);
    }

} // anonymous namespace

SerializerResult SequenceSerializer::loadXLights(const std::string& path, Sequence& seq) {
    std::string content;
    if (!readFile(path, content)) {
        return { SerializerError::FileNotFound, "Cannot read file: " + path };
    }

    seq.clear();

    // Check for xsequence tag
    if (content.find("<xsequence") == std::string::npos) {
        return { SerializerError::InvalidFormat, "Not a valid xLights sequence file" };
    }

    // Parse header
    auto result = parseXMLHeader(content, seq);
    if (!result.success()) return result;

    // Parse display elements
    result = parseXMLDisplayElements(content, seq);
    if (!result.success()) return result;

    // Parse element effects
    result = parseXMLEffects(content, seq);
    if (!result.success()) return result;

    return { SerializerError::None };
}

SerializerResult SequenceSerializer::parseXMLHeader(const std::string& content, Sequence& seq) {
    // Get head section
    std::string head = getTagContent(content, "head");

    // Parse metadata fields
    seq.metadata.author = xmlUnescape(getTagContent(head, "author"));
    seq.metadata.authorEmail = xmlUnescape(getTagContent(head, "author-email"));
    seq.metadata.authorWebsite = xmlUnescape(getTagContent(head, "author-website"));
    seq.metadata.song = xmlUnescape(getTagContent(head, "song"));
    seq.metadata.artist = xmlUnescape(getTagContent(head, "artist"));
    seq.metadata.album = xmlUnescape(getTagContent(head, "album"));
    seq.metadata.musicUrl = xmlUnescape(getTagContent(head, "MusicURL"));
    seq.metadata.comment = xmlUnescape(getTagContent(head, "comment"));
    seq.metadata.version = xmlUnescape(getTagContent(head, "version"));
    seq.metadata.mediaFile = xmlUnescape(getTagContent(head, "mediaFile"));
    seq.metadata.sequenceType = xmlUnescape(getTagContent(head, "sequenceType"));
    seq.metadata.imageDir = xmlUnescape(getTagContent(head, "imageDir"));

    // Parse duration
    std::string durationStr = getTagContent(head, "sequenceDuration");
    if (!durationStr.empty()) {
        seq.metadata.durationSeconds = strings::parseDouble(durationStr, 30.0);
    }

    // Parse timing
    std::string timingStr = getTagContent(head, "sequenceTiming");
    if (!timingStr.empty()) {
        seq.metadata.frameIntervalMS = strings::parseInt(timingStr, 50);
    }

    // Get root attributes
    size_t rootStart = content.find("<xsequence");
    if (rootStart != std::string::npos) {
        size_t rootEnd = content.find('>', rootStart);
        if (rootEnd != std::string::npos) {
            std::string rootTag = content.substr(rootStart, rootEnd - rootStart + 1);

            std::string blending = getXmlAttribute(rootTag, "ModelBlending");
            seq.metadata.supportsModelBlending = strings::parseBool(blending, true);
        }
    }

    // Parse color palettes
    std::string palettesSection = getTagContent(content, "ColorPalettes");
    if (!palettesSection.empty()) {
        // Find all ColorPalette entries
        size_t pos = 0;
        while ((pos = palettesSection.find("<ColorPalette", pos)) != std::string::npos) {
            size_t endTag = palettesSection.find("</ColorPalette>", pos);
            if (endTag == std::string::npos) break;

            size_t contentStart = palettesSection.find('>', pos) + 1;
            std::string palette = palettesSection.substr(contentStart, endTag - contentStart);
            seq.colorPalettes.push_back(xmlUnescape(palette));

            pos = endTag + 1;
        }
    }

    // Parse effect strings
    std::string effectDB = getTagContent(content, "EffectDB");
    if (!effectDB.empty()) {
        size_t pos = 0;
        while ((pos = effectDB.find("<Effect", pos)) != std::string::npos) {
            size_t endTag = effectDB.find("</Effect>", pos);
            if (endTag == std::string::npos) break;

            size_t contentStart = effectDB.find('>', pos) + 1;
            std::string effectStr = effectDB.substr(contentStart, endTag - contentStart);
            seq.effectStrings.push_back(xmlUnescape(effectStr));

            pos = endTag + 1;
        }
    }

    // Parse nextid
    std::string nextIdStr = getTagContent(content, "nextid");
    if (!nextIdStr.empty()) {
        seq.nextEffectId = strings::parseInt(nextIdStr, 1);
    }

    return { SerializerError::None };
}

SerializerResult SequenceSerializer::parseXMLDisplayElements(const std::string& content, Sequence& seq) {
    std::string displayElements = getTagContent(content, "DisplayElements");
    if (displayElements.empty()) {
        return { SerializerError::None };  // No display elements is valid
    }

    // Parse each Element
    size_t pos = 0;
    while ((pos = displayElements.find("<Element ", pos)) != std::string::npos) {
        size_t tagEnd = displayElements.find("/>", pos);
        size_t tagEndAlt = displayElements.find(">", pos);

        // Use whichever comes first
        size_t actualEnd = std::min(tagEnd, tagEndAlt);
        if (actualEnd == std::string::npos) break;

        std::string tag = displayElements.substr(pos, actualEnd - pos + (tagEnd < tagEndAlt ? 2 : 1));

        // Extract attributes
        std::string name = xmlUnescape(getXmlAttribute(tag, "name"));
        std::string typeStr = getXmlAttribute(tag, "type");
        std::string visibleStr = getXmlAttribute(tag, "visible");
        std::string collapsedStr = getXmlAttribute(tag, "collapsed");
        std::string activeStr = getXmlAttribute(tag, "active");
        std::string renderDisabledStr = getXmlAttribute(tag, "renderDisabled");

        if (!name.empty()) {
            ElementType type = ElementType::Model;
            if (typeStr == "timing") type = ElementType::Timing;
            else if (typeStr == "modelgroup") type = ElementType::ModelGroup;
            else if (typeStr == "submodel") type = ElementType::SubModel;

            auto& elem = seq.addElement(name, type);
            elem.visible = strings::parseBool(visibleStr, true);
            elem.collapsed = strings::parseBool(collapsedStr, false);
            elem.active = strings::parseBool(activeStr, false);
            elem.renderDisabled = strings::parseBool(renderDisabledStr, false);
        }

        pos = actualEnd + 1;
    }

    return { SerializerError::None };
}

SerializerResult SequenceSerializer::parseXMLEffects(const std::string& content, Sequence& seq) {
    std::string elementEffects = getTagContent(content, "ElementEffects");
    if (elementEffects.empty()) {
        return { SerializerError::None };
    }

    // Parse each Element
    size_t pos = 0;
    while ((pos = elementEffects.find("<Element ", pos)) != std::string::npos) {
        // Find end of Element
        size_t elementEnd = elementEffects.find("</Element>", pos);
        if (elementEnd == std::string::npos) break;

        std::string elementSection = elementEffects.substr(pos, elementEnd - pos);

        // Get element attributes
        size_t tagEnd = elementSection.find('>');
        std::string tag = elementSection.substr(0, tagEnd + 1);
        std::string elemName = xmlUnescape(getXmlAttribute(tag, "name"));
        std::string elemType = getXmlAttribute(tag, "type");

        // Find or create element
        SequenceElement* elem = seq.getElement(elemName);
        if (!elem) {
            ElementType type = ElementType::Model;
            if (elemType == "timing") type = ElementType::Timing;
            else if (elemType == "modelgroup") type = ElementType::ModelGroup;
            elem = &seq.addElement(elemName, type);
        }

        // Check for fixed timing
        std::string fixedStr = getXmlAttribute(tag, "fixed");
        if (!fixedStr.empty()) {
            elem->fixedInterval = strings::parseInt(fixedStr, 0);
        }

        // Parse EffectLayers
        size_t layerPos = tagEnd + 1;
        int layerIndex = 0;

        while ((layerPos = elementSection.find("<EffectLayer", layerPos)) != std::string::npos) {
            size_t layerEnd = elementSection.find("</EffectLayer>", layerPos);
            if (layerEnd == std::string::npos) break;

            std::string layerSection = elementSection.substr(layerPos, layerEnd - layerPos);

            // Ensure layer exists
            elem->ensureLayers(layerIndex + 1);
            EffectLayer& layer = elem->layers[layerIndex];

            // Parse Effects
            size_t effectPos = 0;
            while ((effectPos = layerSection.find("<Effect ", effectPos)) != std::string::npos) {
                // Find end of effect tag
                size_t effectEnd = layerSection.find("/>", effectPos);
                size_t effectEndAlt = layerSection.find("</Effect>", effectPos);

                if (effectEnd == std::string::npos) effectEnd = effectEndAlt;
                else if (effectEndAlt != std::string::npos) effectEnd = std::min(effectEnd, effectEndAlt);
                if (effectEnd == std::string::npos) break;

                // Get the effect tag content
                size_t effectTagEnd = layerSection.find('>', effectPos);
                std::string effectTag = layerSection.substr(effectPos, effectTagEnd - effectPos + 1);

                // Get effect content if not self-closing
                std::string effectContent;
                if (effectTagEnd != effectEnd && effectEndAlt != std::string::npos && effectEndAlt < effectEnd + 2) {
                    effectContent = layerSection.substr(effectTagEnd + 1, effectEndAlt - effectTagEnd - 1);
                }

                // Extract attributes
                std::string effectName = getXmlAttribute(effectTag, "name");
                std::string label = xmlUnescape(getXmlAttribute(effectTag, "label"));  // For timing effects
                std::string startTimeStr = getXmlAttribute(effectTag, "startTime");
                std::string endTimeStr = getXmlAttribute(effectTag, "endTime");
                std::string protectedStr = getXmlAttribute(effectTag, "protected");
                std::string selectedStr = getXmlAttribute(effectTag, "selected");
                std::string idStr = getXmlAttribute(effectTag, "id");
                std::string paletteIdx = getXmlAttribute(effectTag, "palette");

                SequenceEffect effect;
                effect.effectType = effectName.empty() ? label : effectName;
                effect.startTimeMS = strings::parseInt(startTimeStr, 0);
                effect.endTimeMS = strings::parseInt(endTimeStr, 0);
                effect.isProtected = strings::parseBool(protectedStr, false);
                effect.isSelected = strings::parseBool(selectedStr, false);
                effect.id = strings::parseInt(idStr, seq.generateEffectId());

                // Parse settings from content
                if (!effectContent.empty()) {
                    effect.settings = EffectSettings::fromString(xmlUnescape(effectContent));
                }

                // Get palette
                if (!paletteIdx.empty()) {
                    int idx = strings::parseInt(paletteIdx, -1);
                    if (idx >= 0 && idx < static_cast<int>(seq.colorPalettes.size())) {
                        effect.palette = ColorPalette::fromString(seq.colorPalettes[idx]);
                    }
                }

                layer.addEffect(std::move(effect));
                effectPos = effectEnd + 1;
            }

            layerPos = layerEnd + 1;
            layerIndex++;
        }

        pos = elementEnd + 1;
    }

    return { SerializerError::None };
}

SerializerResult SequenceSerializer::saveXLights(const std::string& path, const Sequence& seq) {
    std::string xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    xml += "<xsequence BaseChannel=\"0\" ChanCtrlBasic=\"0\" ChanCtrlColor=\"0\" ";
    xml += "FixedPointTiming=\"1\" ";
    xml += "ModelBlending=\"" + std::string(seq.metadata.supportsModelBlending ? "true" : "false") + "\">\n";

    // Generate header
    xml += generateXMLHeader(seq);

    // Generate nextid
    xml += "  <nextid>" + std::to_string(seq.nextEffectId) + "</nextid>\n";

    // Generate color palettes
    xml += "  <ColorPalettes>\n";
    for (const auto& palette : seq.colorPalettes) {
        xml += "    <ColorPalette>" + xmlEscape(palette) + "</ColorPalette>\n";
    }
    xml += "  </ColorPalettes>\n";

    // Generate effect strings
    xml += "  <EffectDB>\n";
    for (const auto& effectStr : seq.effectStrings) {
        xml += "    <Effect>" + xmlEscape(effectStr) + "</Effect>\n";
    }
    xml += "  </EffectDB>\n";

    // Generate display elements
    xml += generateXMLDisplayElements(seq);

    // Generate element effects
    xml += generateXMLEffects(seq);

    xml += "</xsequence>\n";

    if (!writeFile(path, xml)) {
        return { SerializerError::FileWriteError, "Cannot write file: " + path };
    }

    return { SerializerError::None };
}

std::string SequenceSerializer::generateXMLHeader(const Sequence& seq) const {
    std::string xml = "  <head>\n";

    xml += "    <version>" + xmlEscape(seq.metadata.version) + "</version>\n";
    xml += "    <author>" + xmlEscape(seq.metadata.author) + "</author>\n";
    xml += "    <author-email>" + xmlEscape(seq.metadata.authorEmail) + "</author-email>\n";
    xml += "    <author-website>" + xmlEscape(seq.metadata.authorWebsite) + "</author-website>\n";
    xml += "    <song>" + xmlEscape(seq.metadata.song) + "</song>\n";
    xml += "    <artist>" + xmlEscape(seq.metadata.artist) + "</artist>\n";
    xml += "    <album>" + xmlEscape(seq.metadata.album) + "</album>\n";
    xml += "    <MusicURL>" + xmlEscape(seq.metadata.musicUrl) + "</MusicURL>\n";
    xml += "    <comment>" + xmlEscape(seq.metadata.comment) + "</comment>\n";
    xml += "    <sequenceTiming>" + std::to_string(seq.metadata.frameIntervalMS) + " ms</sequenceTiming>\n";
    xml += "    <sequenceType>" + xmlEscape(seq.metadata.sequenceType) + "</sequenceType>\n";
    xml += "    <mediaFile>" + xmlEscape(seq.metadata.mediaFile) + "</mediaFile>\n";
    xml += "    <sequenceDuration>" + strings::toString(seq.metadata.durationSeconds, 3) + "</sequenceDuration>\n";
    xml += "    <imageDir>" + xmlEscape(seq.metadata.imageDir) + "</imageDir>\n";

    xml += "  </head>\n";
    return xml;
}

std::string SequenceSerializer::generateXMLDisplayElements(const Sequence& seq) const {
    std::string xml = "  <DisplayElements>\n";

    for (const auto& elem : seq.elements) {
        std::string typeStr;
        switch (elem.type) {
            case ElementType::Model: typeStr = "model"; break;
            case ElementType::ModelGroup: typeStr = "modelgroup"; break;
            case ElementType::Timing: typeStr = "timing"; break;
            case ElementType::SubModel: typeStr = "submodel"; break;
        }

        xml += "    <Element name=\"" + xmlEscape(elem.name) + "\" ";
        xml += "type=\"" + typeStr + "\" ";
        xml += "visible=\"" + std::string(elem.visible ? "1" : "0") + "\" ";
        xml += "collapsed=\"" + std::string(elem.collapsed ? "1" : "0") + "\" ";
        xml += "active=\"" + std::string(elem.active ? "1" : "0") + "\" ";
        xml += "renderDisabled=\"" + std::string(elem.renderDisabled ? "1" : "0") + "\"/>\n";
    }

    xml += "  </DisplayElements>\n";
    return xml;
}

std::string SequenceSerializer::generateXMLEffects(const Sequence& seq) const {
    std::string xml = "  <ElementEffects>\n";

    // Build palette cache for efficiency
    std::map<std::string, int> paletteCache;
    for (size_t i = 0; i < seq.colorPalettes.size(); ++i) {
        paletteCache[seq.colorPalettes[i]] = static_cast<int>(i);
    }

    for (const auto& elem : seq.elements) {
        std::string typeStr;
        switch (elem.type) {
            case ElementType::Model: typeStr = "model"; break;
            case ElementType::ModelGroup: typeStr = "modelgroup"; break;
            case ElementType::Timing: typeStr = "timing"; break;
            case ElementType::SubModel: typeStr = "submodel"; break;
        }

        xml += "    <Element type=\"" + typeStr + "\" name=\"" + xmlEscape(elem.name) + "\"";
        if (elem.fixedInterval > 0) {
            xml += " fixed=\"" + std::to_string(elem.fixedInterval) + "\"";
        }
        xml += ">\n";

        for (const auto& layer : elem.layers) {
            xml += "      <EffectLayer>\n";

            for (const auto& effect : layer.effects) {
                xml += "        <Effect ";

                if (elem.isTiming()) {
                    xml += "label=\"" + xmlEscape(effect.effectType) + "\" ";
                } else {
                    xml += "name=\"" + xmlEscape(effect.effectType) + "\" ";
                }

                xml += "protected=\"" + std::string(effect.isProtected ? "1" : "0") + "\" ";
                xml += "selected=\"" + std::string(effect.isSelected ? "0" : "0") + "\" ";
                xml += "id=\"" + std::to_string(effect.id) + "\" ";
                xml += "startTime=\"" + std::to_string(effect.startTimeMS) + "\" ";
                xml += "endTime=\"" + std::to_string(effect.endTimeMS) + "\" ";

                // Palette
                std::string paletteStr = effect.palette.toString();
                auto it = paletteCache.find(paletteStr);
                int paletteIdx = 0;
                if (it != paletteCache.end()) {
                    paletteIdx = it->second;
                }
                xml += "palette=\"" + std::to_string(paletteIdx) + "\"";

                // Settings content
                std::string settings = effect.settings.toString();
                if (settings.empty()) {
                    xml += "/>\n";
                } else {
                    xml += ">" + xmlEscape(settings) + "</Effect>\n";
                }
            }

            xml += "      </EffectLayer>\n";
        }

        xml += "    </Element>\n";
    }

    xml += "  </ElementEffects>\n";
    return xml;
}

SerializerResult SequenceSerializer::loadFSEQ(const std::string& path, FSEQInfo& info) {
    return getFSEQInfo(path, info);
}

SerializerResult SequenceSerializer::getFSEQInfo(const std::string& path, FSEQInfo& info) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        return { SerializerError::FileNotFound, "Cannot open file: " + path };
    }

    info.filename = path;

    // Read header (minimum 8 bytes to get header size)
    std::vector<uint8_t> headerPeek(8);
    file.read(reinterpret_cast<char*>(headerPeek.data()), 8);
    if (!file) {
        return { SerializerError::FileReadError, "Cannot read FSEQ header" };
    }

    // Validate magic
    bool isEseq = headerPeek[0] == 'E';
    if (!isEseq && headerPeek[0] != 'P' && headerPeek[0] != 'F') {
        return { SerializerError::InvalidFormat, "Invalid FSEQ magic" };
    }
    if (headerPeek[1] != 'S' || headerPeek[2] != 'E' || headerPeek[3] != 'Q') {
        return { SerializerError::InvalidFormat, "Invalid FSEQ magic" };
    }

    // ESEQ has different format
    if (isEseq) {
        info.versionMajor = 2;
        info.versionMinor = 0;
        info.stepTimeMS = 50;

        // Read more for ESEQ header
        file.seekg(0);
        std::vector<uint8_t> header(20);
        file.read(reinterpret_cast<char*>(header.data()), 20);
        if (!file) {
            return { SerializerError::FileReadError, "Cannot read ESEQ header" };
        }

        info.channelCount = read4ByteLE(&header[8]);

        // Calculate frame count from file size
        file.seekg(0, std::ios::end);
        uint64_t fileSize = static_cast<uint64_t>(file.tellg());
        info.numFrames = static_cast<uint32_t>((fileSize - 20) / info.channelCount);

        return { SerializerError::None };
    }

    // Standard FSEQ
    uint16_t headerLen = read2ByteLE(&headerPeek[4]);
    info.versionMinor = headerPeek[6];
    info.versionMajor = headerPeek[7];

    // Read full header
    file.seekg(0);
    std::vector<uint8_t> header(headerLen);
    file.read(reinterpret_cast<char*>(header.data()), headerLen);
    if (!file) {
        return { SerializerError::FileReadError, "Cannot read full FSEQ header" };
    }

    return parseFSEQHeader(header, info);
}

SerializerResult SequenceSerializer::parseFSEQHeader(const std::vector<uint8_t>& header, FSEQInfo& info) {
    if (header.size() < 22) {
        return { SerializerError::InvalidFormat, "FSEQ header too short" };
    }

    info.channelCount = read4ByteLE(&header[10]);
    info.numFrames = read4ByteLE(&header[14]);
    info.stepTimeMS = header[18];

    if (info.versionMajor >= 2) {
        // V2 has compression type and UUID
        if (header.size() >= 22) {
            uint8_t compType = header[20];
            switch (compType) {
                case 0: info.compression = FSEQInfo::CompressionType::None; break;
                case 1: info.compression = FSEQInfo::CompressionType::Zstd; break;
                case 2: info.compression = FSEQInfo::CompressionType::Zlib; break;
                default: info.compression = FSEQInfo::CompressionType::None; break;
            }
        }

        // Parse variable headers
        // Variable headers start after fixed header (offset depends on version)
        size_t varHeaderStart = 32;  // V2 fixed header size
        if (varHeaderStart < header.size()) {
            size_t pos = varHeaderStart;
            while (pos + 4 <= header.size()) {
                uint16_t len = read2ByteLE(&header[pos]);
                if (len < 4 || pos + len > header.size()) break;

                FSEQVariableHeader vh;
                vh.code[0] = static_cast<char>(header[pos + 2]);
                vh.code[1] = static_cast<char>(header[pos + 3]);
                vh.data.assign(header.begin() + pos + 4, header.begin() + pos + len);

                // Check for media filename ('mf')
                if (vh.code[0] == 'm' && vh.code[1] == 'f' && !vh.data.empty()) {
                    info.mediaFilename = std::string(vh.data.begin(), vh.data.end());
                    // Remove null terminator if present
                    if (!info.mediaFilename.empty() && info.mediaFilename.back() == '\0') {
                        info.mediaFilename.pop_back();
                    }
                }

                info.variableHeaders.push_back(std::move(vh));
                pos += len;
            }
        }
    }

    return { SerializerError::None };
}

SerializerResult SequenceSerializer::loadFSEQData(const std::string& path, SequenceData& data) {
    // Note: Full FSEQ data loading with decompression would require zstd/zlib
    // This is a placeholder that indicates the capability
    return { SerializerError::UnsupportedVersion,
             "Full FSEQ data loading requires linking with zstd library" };
}

SerializerResult SequenceSerializer::saveFSEQ(const std::string& path, const FSEQInfo& info,
                                               const SequenceData& data) {
    // Note: Full FSEQ writing with compression would require zstd/zlib
    // This is a placeholder that indicates the capability
    return { SerializerError::UnsupportedVersion,
             "Full FSEQ writing requires linking with zstd library" };
}

std::string SequenceSerializer::getMediaFilenameFromFSEQ(const std::string& path) {
    FSEQInfo info;
    SequenceSerializer serializer;
    if (serializer.getFSEQInfo(path, info).success()) {
        return info.mediaFilename;
    }
    return "";
}

bool SequenceSerializer::isXLightsFile(const std::string& path) {
    // Check extension
    if (strings::endsWithIgnoreCase(path, ".xLights") ||
        strings::endsWithIgnoreCase(path, ".xlights")) {
        return true;
    }

    // Check content
    std::ifstream file(path, std::ios::binary);
    if (!file) return false;

    char buf[256];
    file.read(buf, sizeof(buf) - 1);
    buf[file.gcount()] = '\0';

    return std::string(buf).find("<xsequence") != std::string::npos;
}

bool SequenceSerializer::isFSEQFile(const std::string& path) {
    if (!strings::endsWithIgnoreCase(path, ".fseq")) {
        return false;
    }

    std::ifstream file(path, std::ios::binary);
    if (!file) return false;

    char magic[4];
    file.read(magic, 4);
    if (!file) return false;

    return (magic[0] == 'P' || magic[0] == 'F' || magic[0] == 'E') &&
            magic[1] == 'S' && magic[2] == 'E' && magic[3] == 'Q';
}

} // namespace xlCore
