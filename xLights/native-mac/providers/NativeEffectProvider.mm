/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "NativeEffectProvider.h"

#import <Foundation/Foundation.h>
#include <algorithm>
#include <fstream>
#include <iomanip>
#include <sstream>

namespace xlEngine {

// --- Internal Data Structures ---

struct NativeEffect {
    int64_t effectId = 0;
    std::string effectType;
    int effectTypeIndex = -1;
    int startTimeMS = 0;
    int endTimeMS = 0;
    bool selected = false;
    bool protected_ = false;
    bool locked = false;
    bool renderDisabled = false;
    std::map<std::string, std::string> settings;
    std::map<std::string, std::string> palette;

    NativeEffect() = default;
    NativeEffect(const NativeEffect&) = default;
    NativeEffect& operator=(const NativeEffect&) = default;
};

struct NativeEffectLayer {
    std::vector<std::unique_ptr<NativeEffect>> effects;

    NativeEffectLayer() = default;

    // Move effects sorted by start time
    void sortEffects() {
        std::sort(effects.begin(), effects.end(),
            [](const std::unique_ptr<NativeEffect>& a, const std::unique_ptr<NativeEffect>& b) {
                return a->startTimeMS < b->startTimeMS;
            });
    }
};

struct NativeElement {
    std::string name;
    std::string fullName;
    std::string modelName;
    SequenceElementType type = SequenceElementType::Model;
    bool visible = true;
    bool collapsed = false;
    bool renderDisabled = false;
    std::vector<std::unique_ptr<NativeEffectLayer>> layers;

    // For timing elements
    int fixedTiming = 0;
    bool isActive = true;

    // For submodels/strands
    std::string parentElementName;
    int strandIndex = -1;              // For strands: 0-based strand index

    // Track folder membership (empty = not in a folder)
    std::string folder;

    NativeElement() = default;

    size_t getEffectCount() const {
        size_t count = 0;
        for (const auto& layer : layers) {
            count += layer->effects.size();
        }
        return count;
    }
};

// --- Undo Action Types ---

struct UndoAction {
    virtual ~UndoAction() = default;
    virtual void undo(NativeEffectProvider& provider) = 0;
    virtual void redo(NativeEffectProvider& provider) = 0;
};

struct CreateEffectUndoAction : public UndoAction {
    int64_t effectId;
    size_t elementIndex;
    size_t layerIndex;
    std::string effectType;
    int startTimeMS;
    int endTimeMS;
    std::map<std::string, std::string> settings;
    std::map<std::string, std::string> palette;

    void undo(NativeEffectProvider& provider) override {
        provider.deleteEffect(effectId);
    }

    void redo(NativeEffectProvider& provider) override {
        auto result = provider.createEffectWithSettings(elementIndex, layerIndex, effectType,
            startTimeMS, endTimeMS, settings, palette);
        effectId = result.effectId;
    }
};

struct DeleteEffectUndoAction : public UndoAction {
    int64_t effectId;
    size_t elementIndex;
    size_t layerIndex;
    std::string effectType;
    int startTimeMS;
    int endTimeMS;
    std::map<std::string, std::string> settings;
    std::map<std::string, std::string> palette;

    void undo(NativeEffectProvider& provider) override {
        auto result = provider.createEffectWithSettings(elementIndex, layerIndex, effectType,
            startTimeMS, endTimeMS, settings, palette);
        effectId = result.effectId;
    }

    void redo(NativeEffectProvider& provider) override {
        provider.deleteEffect(effectId);
    }
};

struct UpdateEffectTimingUndoAction : public UndoAction {
    int64_t effectId;
    int oldStartTimeMS;
    int oldEndTimeMS;
    int newStartTimeMS;
    int newEndTimeMS;

    void undo(NativeEffectProvider& provider) override {
        provider.updateEffectTiming(effectId, oldStartTimeMS, oldEndTimeMS);
    }

    void redo(NativeEffectProvider& provider) override {
        provider.updateEffectTiming(effectId, newStartTimeMS, newEndTimeMS);
    }
};

struct UpdateEffectSettingsUndoAction : public UndoAction {
    int64_t effectId;
    std::map<std::string, std::string> oldSettings;
    std::map<std::string, std::string> newSettings;

    void undo(NativeEffectProvider& provider) override {
        provider.updateEffectSettings(effectId, oldSettings);
    }

    void redo(NativeEffectProvider& provider) override {
        provider.updateEffectSettings(effectId, newSettings);
    }
};

struct UpdateEffectPaletteUndoAction : public UndoAction {
    int64_t effectId;
    std::map<std::string, std::string> oldPalette;
    std::map<std::string, std::string> newPalette;

    void undo(NativeEffectProvider& provider) override {
        provider.updateEffectPalette(effectId, oldPalette);
    }

    void redo(NativeEffectProvider& provider) override {
        provider.updateEffectPalette(effectId, newPalette);
    }
};

// --- NativeEffectProvider Implementation ---

NativeEffectProvider::NativeEffectProvider()
{
}

NativeEffectProvider::~NativeEffectProvider()
{
}

// --- Initialization and Serialization ---

bool NativeEffectProvider::loadFromSequenceXML(const std::string& xmlContent)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    clear();

    @autoreleasepool {
        NSData* data = [NSData dataWithBytes:xmlContent.c_str() length:xmlContent.size()];
        NSError* error = nil;
        NSXMLDocument* doc = [[NSXMLDocument alloc] initWithData:data options:0 error:&error];
        if (error || !doc) {
            return false;
        }

        NSXMLElement* root = [doc rootElement];
        if (!root) {
            return false;
        }

        // Parse sequence length from <head><sequenceDuration> element
        NSArray* durationElems = [root nodesForXPath:@"//head/sequenceDuration" error:nil];
        if (durationElems.count > 0) {
            double durationSec = [[durationElems[0] stringValue] doubleValue];
            if (durationSec > 0) {
                _sequenceLengthMS = (int)(durationSec * 1000.0);
            }
        }

        // Helper to parse a comma-separated key=value string into a map
        auto parseKVString = [](NSString* str, std::map<std::string, std::string>& outMap) {
            if (!str || str.length == 0) return;
            NSArray* pairs = [str componentsSeparatedByString:@","];
            for (NSString* pair in pairs) {
                NSRange eqRange = [pair rangeOfString:@"="];
                if (eqRange.location == NSNotFound) continue;
                NSString* key = [pair substringToIndex:eqRange.location];
                NSString* val = [pair substringFromIndex:eqRange.location + 1];
                if (key.length == 0) continue;
                std::string value = std::string([val UTF8String]);
                // Unescape special characters
                size_t pos = 0;
                while ((pos = value.find("&comma;", pos)) != std::string::npos) {
                    value.replace(pos, 7, ",");
                    pos += 1;
                }
                pos = 0;
                while ((pos = value.find("&amp;", pos)) != std::string::npos) {
                    value.replace(pos, 5, "&");
                    pos += 1;
                }
                outMap[std::string([key UTF8String])] = value;
            }
        };

        // Parse EffectDB — each entry is "EffectName,key=val,key=val,..."
        // The ref attribute on Effect elements indexes into this array
        std::vector<NSString*> effectDBEntries;
        NSArray* effectDBNodes = [root nodesForXPath:@"//EffectDB/Effect" error:nil];
        for (NSXMLNode* node in effectDBNodes) {
            effectDBEntries.push_back(node.stringValue ?: @"");
        }

        // Parse ColorPalettes — each entry is "key=val,key=val,..."
        std::vector<NSString*> colorPaletteEntries;
        NSArray* paletteNodes = [root nodesForXPath:@"//ColorPalettes/ColorPalette" error:nil];
        for (NSXMLNode* node in paletteNodes) {
            colorPaletteEntries.push_back(node.stringValue ?: @"");
        }

        // Parse elements from ElementEffects
        NSArray* elementNodes = [root nodesForXPath:@"//ElementEffects/Element" error:nil];
        for (NSXMLElement* elemNode in elementNodes) {
            auto element = std::make_unique<NativeElement>();

            NSXMLNode* typeAttr = [elemNode attributeForName:@"type"];
            NSString* typeStr = typeAttr ? typeAttr.stringValue : @"model";

            if ([typeStr isEqualToString:@"timing"]) {
                element->type = SequenceElementType::Timing;
                NSXMLNode* fixedAttr = [elemNode attributeForName:@"fixed"];
                if (fixedAttr) {
                    element->fixedTiming = [fixedAttr.stringValue intValue];
                }
                NSXMLNode* activeAttr = [elemNode attributeForName:@"Active"];
                element->isActive = activeAttr ? [activeAttr.stringValue boolValue] : YES;
            } else if ([typeStr isEqualToString:@"submodel"]) {
                element->type = SequenceElementType::Submodel;
            } else if ([typeStr isEqualToString:@"strand"]) {
                element->type = SequenceElementType::Strand;
            } else {
                element->type = SequenceElementType::Model;
            }

            NSXMLNode* nameAttr = [elemNode attributeForName:@"name"];
            element->name = nameAttr ? std::string([nameAttr.stringValue UTF8String]) : "";
            element->fullName = element->name;
            element->modelName = element->name;

            NSXMLNode* visAttr = [elemNode attributeForName:@"visible"];
            element->visible = visAttr ? [visAttr.stringValue boolValue] : YES;

            NSXMLNode* colAttr = [elemNode attributeForName:@"collapsed"];
            element->collapsed = colAttr ? [colAttr.stringValue boolValue] : NO;

            NSXMLNode* folderAttr = [elemNode attributeForName:@"folder"];
            if (folderAttr && folderAttr.stringValue.length > 0) {
                element->folder = std::string([folderAttr.stringValue UTF8String]);
            }

            // Parse effect layers
            NSArray* layerNodes = [elemNode nodesForXPath:@"EffectLayer" error:nil];
            for (NSXMLElement* layerNode in layerNodes) {
                auto layer = std::make_unique<NativeEffectLayer>();

                NSArray* effectNodes = [layerNode nodesForXPath:@"Effect" error:nil];
                for (NSXMLElement* effectNode in effectNodes) {
                    auto effect = std::make_unique<NativeEffect>();
                    effect->effectId = _nextEffectId++;

                    // Get effect name from the "name" attribute (regular effects)
                    // or "label" attribute (timing marks use "label" for their text)
                    NSXMLNode* nameAttrEff = [effectNode attributeForName:@"name"];
                    if (nameAttrEff && nameAttrEff.stringValue.length > 0) {
                        effect->effectType = std::string([nameAttrEff.stringValue UTF8String]);
                    } else {
                        NSXMLNode* labelAttrEff = [effectNode attributeForName:@"label"];
                        if (labelAttrEff && labelAttrEff.stringValue.length > 0) {
                            effect->effectType = std::string([labelAttrEff.stringValue UTF8String]);
                        }
                    }

                    // The "ref" attribute indexes into EffectDB for settings (legacy format)
                    // EffectDB entries are JUST settings: "key=val,key=val,..."
                    // (the effect type name comes from the "name" attribute, not EffectDB)
                    NSXMLNode* refAttr = [effectNode attributeForName:@"ref"];
                    if (refAttr) {
                        int refIdx = [refAttr.stringValue intValue];
                        if (refIdx >= 0 && (size_t)refIdx < effectDBEntries.size()) {
                            NSString* dbEntry = effectDBEntries[refIdx];
                            if (dbEntry.length > 0) {
                                parseKVString(dbEntry, effect->settings);
                            }
                        }
                    }

                    // Also support inline "settings" attribute (native save format)
                    if (effect->settings.empty()) {
                        NSXMLNode* inlineSettingsAttr = [effectNode attributeForName:@"settings"];
                        if (inlineSettingsAttr && inlineSettingsAttr.stringValue.length > 0) {
                            parseKVString(inlineSettingsAttr.stringValue, effect->settings);
                        }
                    }

                    // Find effect type index
                    for (size_t i = 0; i < _effectTypes.size(); ++i) {
                        if (_effectTypes[i].name == effect->effectType) {
                            effect->effectTypeIndex = static_cast<int>(i);
                            break;
                        }
                    }

                    NSXMLNode* startAttr = [effectNode attributeForName:@"startTime"];
                    effect->startTimeMS = startAttr ? [startAttr.stringValue intValue] : 0;

                    NSXMLNode* endAttr = [effectNode attributeForName:@"endTime"];
                    effect->endTimeMS = endAttr ? [endAttr.stringValue intValue] : 0;

                    NSXMLNode* protAttr = [effectNode attributeForName:@"protected"];
                    effect->protected_ = protAttr ? [protAttr.stringValue boolValue] : NO;

                    NSXMLNode* selAttr = [effectNode attributeForName:@"selected"];
                    effect->selected = selAttr ? [selAttr.stringValue boolValue] : NO;

                    // The "palette" attribute indexes into ColorPalettes (legacy format)
                    NSXMLNode* paletteAttr = [effectNode attributeForName:@"palette"];
                    if (paletteAttr) {
                        int palIdx = [paletteAttr.stringValue intValue];
                        if (palIdx >= 0 && (size_t)palIdx < colorPaletteEntries.size()) {
                            parseKVString(colorPaletteEntries[palIdx], effect->palette);
                        }
                    }

                    // Also support inline "palette" attribute (native save format)
                    if (effect->palette.empty() && paletteAttr && paletteAttr.stringValue.length > 0) {
                        // Check if the palette value is not just an integer index
                        // (contains '=' which indicates inline key-value format)
                        NSString* palStr = paletteAttr.stringValue;
                        if ([palStr containsString:@"="]) {
                            parseKVString(palStr, effect->palette);
                        }
                    }

                    _effectsById[effect->effectId] = effect.get();
                    layer->effects.push_back(std::move(effect));
                }

                layer->sortEffects();
                element->layers.push_back(std::move(layer));
            }

            // Ensure at least one layer
            if (element->layers.empty()) {
                element->layers.push_back(std::make_unique<NativeEffectLayer>());
            }

            // Debug: check for unexpected effect counts on known models
            {
                bool isMissing = (element->name == "Pixel Stake 50" ||
                                  element->name == "Pixel Stake 52" ||
                                  element->name == "Pixel Stake 54" ||
                                  element->name == "Large Gift 1" ||
                                  element->name == "Flake Icicle 41");
                if (isMissing) {
                    size_t effCount = element->getEffectCount();
                    printf("[PARSE_CHECK] '%s': idx=%zu layers=%zu effects=%zu\n",
                           element->name.c_str(), _elements.size(),
                           element->layers.size(), effCount);
                    // Print layer details
                    for (size_t li = 0; li < element->layers.size(); ++li) {
                        printf("[PARSE_CHECK]   layer %zu: %zu effects\n",
                               li, element->layers[li]->effects.size());
                        if (!element->layers[li]->effects.empty()) {
                            auto& eff = element->layers[li]->effects[0];
                            printf("[PARSE_CHECK]     first: '%s' %d-%dms\n",
                                   eff->effectType.c_str(), eff->startTimeMS, eff->endTimeMS);
                        }
                    }
                }
            }
            std::string parentModelName = element->name;
            _elementsByName[element->name] = _elements.size();
            _elements.push_back(std::move(element));

            // Parse SubModelEffectLayer nodes — submodel effects stored as
            // children of the parent model's Element node in the XML.
            NSArray* subModelNodes = [elemNode nodesForXPath:@"SubModelEffectLayer" error:nil];
            for (NSXMLElement* subNode in subModelNodes) {
                NSXMLNode* subNameAttr = [subNode attributeForName:@"name"];
                if (!subNameAttr || subNameAttr.stringValue.length == 0) continue;

                std::string subName = std::string([subNameAttr.stringValue UTF8String]);
                std::string fullSubName = parentModelName + "/" + subName;
                int layerIdx = 0;
                NSXMLNode* layerAttr = [subNode attributeForName:@"layer"];
                if (layerAttr) layerIdx = [layerAttr.stringValue intValue];

                auto subIt = _elementsByName.find(fullSubName);
                NativeElement* subElem = nullptr;
                if (subIt != _elementsByName.end()) {
                    subElem = _elements[subIt->second].get();
                } else {
                    auto newSub = std::make_unique<NativeElement>();
                    newSub->name = fullSubName;
                    newSub->fullName = fullSubName;
                    newSub->modelName = parentModelName;
                    newSub->type = SequenceElementType::Submodel;
                    newSub->parentElementName = parentModelName;
                    newSub->visible = true;
                    subElem = newSub.get();
                    _elementsByName[fullSubName] = _elements.size();
                    _elements.push_back(std::move(newSub));
                }

                while ((int)subElem->layers.size() <= layerIdx) {
                    subElem->layers.push_back(std::make_unique<NativeEffectLayer>());
                }

                NSArray* subEffectNodes = [subNode nodesForXPath:@"Effect" error:nil];
                for (NSXMLElement* effectNode in subEffectNodes) {
                    auto effect = std::make_unique<NativeEffect>();
                    effect->effectId = _nextEffectId++;

                    NSXMLNode* nameAttrEff = [effectNode attributeForName:@"name"];
                    if (nameAttrEff && nameAttrEff.stringValue.length > 0) {
                        effect->effectType = std::string([nameAttrEff.stringValue UTF8String]);
                    }

                    NSXMLNode* refAttr = [effectNode attributeForName:@"ref"];
                    if (refAttr) {
                        int refIdx = [refAttr.stringValue intValue];
                        if (refIdx >= 0 && (size_t)refIdx < effectDBEntries.size()) {
                            NSString* dbEntry = effectDBEntries[refIdx];
                            if (dbEntry.length > 0) parseKVString(dbEntry, effect->settings);
                        }
                    }
                    if (effect->settings.empty()) {
                        NSXMLNode* inlineAttr = [effectNode attributeForName:@"settings"];
                        if (inlineAttr && inlineAttr.stringValue.length > 0)
                            parseKVString(inlineAttr.stringValue, effect->settings);
                    }

                    for (size_t ei = 0; ei < _effectTypes.size(); ++ei) {
                        if (_effectTypes[ei].name == effect->effectType) {
                            effect->effectTypeIndex = static_cast<int>(ei);
                            break;
                        }
                    }

                    NSXMLNode* startAttr = [effectNode attributeForName:@"startTime"];
                    effect->startTimeMS = startAttr ? [startAttr.stringValue intValue] : 0;
                    NSXMLNode* endAttr = [effectNode attributeForName:@"endTime"];
                    effect->endTimeMS = endAttr ? [endAttr.stringValue intValue] : 0;

                    NSXMLNode* paletteAttr = [effectNode attributeForName:@"palette"];
                    if (paletteAttr) {
                        int palIdx = [paletteAttr.stringValue intValue];
                        if (palIdx >= 0 && (size_t)palIdx < colorPaletteEntries.size())
                            parseKVString(colorPaletteEntries[palIdx], effect->palette);
                    }
                    if (effect->palette.empty() && paletteAttr && paletteAttr.stringValue.length > 0) {
                        NSString* palStr = paletteAttr.stringValue;
                        if ([palStr containsString:@"="]) parseKVString(palStr, effect->palette);
                    }

                    _effectsById[effect->effectId] = effect.get();
                    subElem->layers[layerIdx]->effects.push_back(std::move(effect));
                }
                subElem->layers[layerIdx]->sortEffects();

                printf("[SUBMODEL_PARSE] '%s': layer=%d effects=%zu\n",
                       fullSubName.c_str(), layerIdx,
                       subElem->layers[layerIdx]->effects.size());
            }

            // Parse Strand nodes — strand effects stored as children of the parent
            NSArray* strandNodes = [elemNode nodesForXPath:@"Strand" error:nil];
            for (NSXMLElement* strandNode in strandNodes) {
                NSXMLNode* indexAttr = [strandNode attributeForName:@"index"];
                if (!indexAttr) continue;
                int strandIdx = [indexAttr.stringValue intValue];

                NSXMLNode* strandNameAttr = [strandNode attributeForName:@"name"];
                std::string strandName;
                if (strandNameAttr && strandNameAttr.stringValue.length > 0) {
                    strandName = std::string([strandNameAttr.stringValue UTF8String]);
                } else {
                    strandName = "Strand " + std::to_string(strandIdx + 1);
                }
                std::string fullStrandName = parentModelName + "/" + strandName;

                int layerIdx = 0;
                NSXMLNode* layerAttr = [strandNode attributeForName:@"layer"];
                if (layerAttr) layerIdx = [layerAttr.stringValue intValue];

                auto strandIt = _elementsByName.find(fullStrandName);
                NativeElement* strandElem = nullptr;
                if (strandIt != _elementsByName.end()) {
                    strandElem = _elements[strandIt->second].get();
                } else {
                    auto newStrand = std::make_unique<NativeElement>();
                    newStrand->name = fullStrandName;
                    newStrand->fullName = fullStrandName;
                    newStrand->modelName = parentModelName;
                    newStrand->type = SequenceElementType::Strand;
                    newStrand->parentElementName = parentModelName;
                    newStrand->strandIndex = strandIdx;
                    newStrand->visible = true;
                    strandElem = newStrand.get();
                    _elementsByName[fullStrandName] = _elements.size();
                    _elements.push_back(std::move(newStrand));
                }

                while ((int)strandElem->layers.size() <= layerIdx) {
                    strandElem->layers.push_back(std::make_unique<NativeEffectLayer>());
                }

                NSArray* strandEffectNodes = [strandNode nodesForXPath:@"Effect" error:nil];
                for (NSXMLElement* effectNode in strandEffectNodes) {
                    auto effect = std::make_unique<NativeEffect>();
                    effect->effectId = _nextEffectId++;

                    NSXMLNode* nameAttrEff = [effectNode attributeForName:@"name"];
                    if (nameAttrEff && nameAttrEff.stringValue.length > 0) {
                        effect->effectType = std::string([nameAttrEff.stringValue UTF8String]);
                    }

                    NSXMLNode* refAttr = [effectNode attributeForName:@"ref"];
                    if (refAttr) {
                        int refIdx = [refAttr.stringValue intValue];
                        if (refIdx >= 0 && (size_t)refIdx < effectDBEntries.size()) {
                            NSString* dbEntry = effectDBEntries[refIdx];
                            if (dbEntry.length > 0) parseKVString(dbEntry, effect->settings);
                        }
                    }
                    if (effect->settings.empty()) {
                        NSXMLNode* inlineAttr = [effectNode attributeForName:@"settings"];
                        if (inlineAttr && inlineAttr.stringValue.length > 0)
                            parseKVString(inlineAttr.stringValue, effect->settings);
                    }

                    for (size_t ei = 0; ei < _effectTypes.size(); ++ei) {
                        if (_effectTypes[ei].name == effect->effectType) {
                            effect->effectTypeIndex = static_cast<int>(ei);
                            break;
                        }
                    }

                    NSXMLNode* startAttr = [effectNode attributeForName:@"startTime"];
                    effect->startTimeMS = startAttr ? [startAttr.stringValue intValue] : 0;
                    NSXMLNode* endAttr = [effectNode attributeForName:@"endTime"];
                    effect->endTimeMS = endAttr ? [endAttr.stringValue intValue] : 0;

                    NSXMLNode* paletteAttr = [effectNode attributeForName:@"palette"];
                    if (paletteAttr) {
                        int palIdx = [paletteAttr.stringValue intValue];
                        if (palIdx >= 0 && (size_t)palIdx < colorPaletteEntries.size())
                            parseKVString(colorPaletteEntries[palIdx], effect->palette);
                    }
                    if (effect->palette.empty() && paletteAttr && paletteAttr.stringValue.length > 0) {
                        NSString* palStr = paletteAttr.stringValue;
                        if ([palStr containsString:@"="]) parseKVString(palStr, effect->palette);
                    }

                    _effectsById[effect->effectId] = effect.get();
                    strandElem->layers[layerIdx]->effects.push_back(std::move(effect));
                }
                strandElem->layers[layerIdx]->sortEffects();

                printf("[STRAND_PARSE] '%s': strandIdx=%d layer=%d effects=%zu\n",
                       fullStrandName.c_str(), strandIdx, layerIdx,
                       strandElem->layers[layerIdx]->effects.size());
            }
        }

        // Parse track folders
        NSArray* folderNodes = [root nodesForXPath:@"//TrackFolders/Folder" error:nil];
        for (NSXMLElement* folderNode in folderNodes) {
            TrackFolder folder;
            NSXMLNode* fnameAttr = [folderNode attributeForName:@"name"];
            folder.name = fnameAttr ? std::string([fnameAttr.stringValue UTF8String]) : "";
            NSXMLNode* fcollAttr = [folderNode attributeForName:@"collapsed"];
            folder.collapsed = fcollAttr ? [fcollAttr.stringValue boolValue] : NO;
            if (!folder.name.empty()) {
                _trackFolders.push_back(folder);
            }
        }

        // Parse song structure regions
        NSArray* regionNodes = [root nodesForXPath:@"//SongStructure/Region" error:nil];
        for (NSXMLElement* regionNode in regionNodes) {
            SongStructureRegion region;
            region.regionId = _nextRegionId++;

            NSXMLNode* startAttr = [regionNode attributeForName:@"startTimeMS"];
            region.startTimeMS = startAttr ? [startAttr.stringValue intValue] : 0;

            NSXMLNode* endAttr = [regionNode attributeForName:@"endTimeMS"];
            region.endTimeMS = endAttr ? [endAttr.stringValue intValue] : 0;

            NSXMLNode* nameAttr = [regionNode attributeForName:@"name"];
            region.name = nameAttr ? std::string([nameAttr.stringValue UTF8String]) : "";

            NSXMLNode* colorAttr = [regionNode attributeForName:@"color"];
            if (colorAttr) {
                unsigned long colorVal = strtoul([colorAttr.stringValue UTF8String], nullptr, 16);
                region.colorARGB = (uint32_t)colorVal;
            }

            _songRegions.push_back(region);
        }

        _isLoaded = true;
        _isModified = false;
        _changeCount = 0;

        return true;
    }
}

bool NativeEffectProvider::loadFromSequenceFile(const std::string& filePath)
{
    @autoreleasepool {
        NSString* path = [NSString stringWithUTF8String:filePath.c_str()];
        NSError* error = nil;
        NSString* content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
        if (error || !content) {
            return false;
        }
        return loadFromSequenceXML(std::string([content UTF8String]));
    }
}

std::string NativeEffectProvider::exportToSequenceXML(const SequenceMetadata& metadata) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    std::ostringstream xml;
    xml << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    xml << "<xsequence BaseChannel=\"0\" ChanCtrlBasic=\"0\" ChanCtrlColor=\"0\">\n";

    // Write <head> section with sequence metadata (legacy xLights compatible)
    xml << "  <head>\n";
    xml << "    <version>2024.15</version>\n";
    if (metadata.durationSeconds > 0) {
        xml << "    <sequenceDuration>" << std::fixed << std::setprecision(3)
            << metadata.durationSeconds << "</sequenceDuration>\n";
    } else if (_sequenceLengthMS > 0) {
        xml << "    <sequenceDuration>" << std::fixed << std::setprecision(3)
            << (_sequenceLengthMS / 1000.0) << "</sequenceDuration>\n";
    }
    if (metadata.frameMS > 0) {
        xml << "    <sequenceTiming>" << metadata.frameMS << " ms</sequenceTiming>\n";
    }
    if (!metadata.sequenceType.empty()) {
        xml << "    <sequenceType>" << metadata.sequenceType << "</sequenceType>\n";
    }
    if (!metadata.mediaFile.empty()) {
        xml << "    <mediaFile>" << metadata.mediaFile << "</mediaFile>\n";
    }
    if (!metadata.author.empty()) {
        xml << "    <author>" << metadata.author << "</author>\n";
    }
    NSLog(@"[STEMS] exportToSequenceXML: metadata.audioStems.size=%lu", (unsigned long)metadata.audioStems.size());
    if (!metadata.audioStems.empty()) {
        xml << "    <audioStems>\n";
        for (const auto& stem : metadata.audioStems) {
            NSLog(@"[STEMS]   writing stem: name=%s, relativePath=%s, color=%s",
                  stem.name.c_str(), stem.relativePath.c_str(), stem.color.c_str());
            xml << "      <stem name=\"" << stem.name
                << "\" relativePath=\"" << stem.relativePath
                << "\" color=\"" << stem.color << "\"/>\n";
        }
        xml << "    </audioStems>\n";
    }
    xml << "  </head>\n";

    xml << "  <ElementEffects>\n";

    for (const auto& elem : _elements) {
        xml << "    <Element name=\"" << elem->name << "\"";
        xml << " type=\"";
        switch (elem->type) {
            case SequenceElementType::Model: xml << "model"; break;
            case SequenceElementType::Submodel: xml << "submodel"; break;
            case SequenceElementType::Strand: xml << "strand"; break;
            case SequenceElementType::Timing: xml << "timing"; break;
        }
        xml << "\"";
        if (!elem->visible) xml << " visible=\"0\"";
        if (elem->collapsed) xml << " collapsed=\"1\"";
        if (!elem->folder.empty()) xml << " folder=\"" << elem->folder << "\"";
        if (elem->type == SequenceElementType::Timing) {
            if (elem->fixedTiming > 0) xml << " fixed=\"" << elem->fixedTiming << "\"";
            if (!elem->isActive) xml << " Active=\"0\"";
        }
        xml << ">\n";

        for (const auto& layer : elem->layers) {
            xml << "      <EffectLayer>\n";
            for (const auto& effect : layer->effects) {
                xml << "        <Effect name=\"" << effect->effectType << "\"";
                xml << " startTime=\"" << effect->startTimeMS << "\"";
                xml << " endTime=\"" << effect->endTimeMS << "\"";
                if (effect->protected_) xml << " protected=\"1\"";
                if (effect->selected) xml << " selected=\"1\"";

                if (!effect->settings.empty()) {
                    xml << " settings=\"";
                    bool first = true;
                    for (const auto& [key, value] : effect->settings) {
                        if (!first) xml << ",";
                        first = false;
                        std::string escapedValue = value;
                        size_t pos = 0;
                        while ((pos = escapedValue.find("&", pos)) != std::string::npos) {
                            escapedValue.replace(pos, 1, "&amp;");
                            pos += 5;
                        }
                        pos = 0;
                        while ((pos = escapedValue.find(",", pos)) != std::string::npos) {
                            escapedValue.replace(pos, 1, "&comma;");
                            pos += 7;
                        }
                        xml << key << "=" << escapedValue;
                    }
                    xml << "\"";
                }

                if (!effect->palette.empty()) {
                    xml << " palette=\"";
                    bool first = true;
                    for (const auto& [key, value] : effect->palette) {
                        if (!first) xml << ",";
                        first = false;
                        std::string escapedValue = value;
                        size_t pos = 0;
                        while ((pos = escapedValue.find("&", pos)) != std::string::npos) {
                            escapedValue.replace(pos, 1, "&amp;");
                            pos += 5;
                        }
                        pos = 0;
                        while ((pos = escapedValue.find(",", pos)) != std::string::npos) {
                            escapedValue.replace(pos, 1, "&comma;");
                            pos += 7;
                        }
                        xml << key << "=" << escapedValue;
                    }
                    xml << "\"";
                }

                xml << "/>\n";
            }
            xml << "      </EffectLayer>\n";
        }
        xml << "    </Element>\n";
    }

    xml << "  </ElementEffects>\n";

    // Write track folders
    if (!_trackFolders.empty()) {
        xml << "  <TrackFolders>\n";
        for (const auto& folder : _trackFolders) {
            xml << "    <Folder name=\"" << folder.name << "\"";
            xml << " collapsed=\"" << (folder.collapsed ? "1" : "0") << "\"";
            xml << "/>\n";
        }
        xml << "  </TrackFolders>\n";
    }

    // Write song structure regions
    if (!_songRegions.empty()) {
        xml << "  <SongStructure>\n";
        for (const auto& region : _songRegions) {
            xml << "    <Region startTimeMS=\"" << region.startTimeMS << "\"";
            xml << " endTimeMS=\"" << region.endTimeMS << "\"";
            xml << " name=\"" << region.name << "\"";
            xml << " color=\"" << std::hex << std::setw(8) << std::setfill('0') << region.colorARGB << std::dec << "\"";
            xml << "/>\n";
        }
        xml << "  </SongStructure>\n";
    }

    xml << "</xsequence>\n";

    return xml.str();
}

std::string NativeEffectProvider::exportToSequenceXML() const
{
    SequenceMetadata meta;
    return exportToSequenceXML(meta);
}

bool NativeEffectProvider::saveToSequenceFile(const std::string& filePath, const SequenceMetadata& metadata) const
{
    std::string xml = exportToSequenceXML(metadata);

    @autoreleasepool {
        NSString* path = [NSString stringWithUTF8String:filePath.c_str()];
        NSString* content = [NSString stringWithUTF8String:xml.c_str()];
        NSError* error = nil;
        BOOL success = [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
        return success && !error;
    }
}

bool NativeEffectProvider::saveToSequenceFile(const std::string& filePath) const
{
    SequenceMetadata meta;
    return saveToSequenceFile(filePath, meta);
}

void NativeEffectProvider::clear()
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    _elements.clear();
    _effectsById.clear();
    _elementsByName.clear();
    _selectedEffects.clear();
    _clipboard.clear();
    _undoStack.clear();
    _redoStack.clear();
    _currentUndoGroup.reset();
    _trackFolders.clear();
    _songRegions.clear();
    _nextRegionId = 1;
    _nextEffectId = 1;
    _sequenceLengthMS = 0;
    _isLoaded = false;
    _isModified = false;
    _changeCount = 0;
}

void NativeEffectProvider::setEffectTypes(const std::vector<std::string>& types)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    _effectTypes.clear();
    _effectTypes.reserve(types.size());
    for (size_t i = 0; i < types.size(); ++i) {
        EffectTypeInfo info;
        info.name = types[i];
        info.index = static_cast<int>(i);
        _effectTypes.push_back(info);
    }
}

bool NativeEffectProvider::isLoaded() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return _isLoaded;
}

int NativeEffectProvider::getSequenceLengthMS() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return _sequenceLengthMS;
}

void NativeEffectProvider::setSequenceLengthMS(int lengthMS)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    _sequenceLengthMS = lengthMS;
}

// --- Internal Helpers ---

NativeElement* NativeEffectProvider::getElementPtr(size_t index) const
{
    if (index >= _elements.size()) return nullptr;
    return _elements[index].get();
}

NativeEffect* NativeEffectProvider::findEffectById(int64_t effectId) const
{
    auto it = _effectsById.find(effectId);
    if (it == _effectsById.end()) return nullptr;
    return it->second;
}

NativeEffect* NativeEffectProvider::findEffectById(int64_t effectId, size_t& outElementIndex, size_t& outLayerIndex) const
{
    for (size_t ei = 0; ei < _elements.size(); ++ei) {
        const auto& elem = _elements[ei];
        for (size_t li = 0; li < elem->layers.size(); ++li) {
            const auto& layer = elem->layers[li];
            for (const auto& effect : layer->effects) {
                if (effect->effectId == effectId) {
                    outElementIndex = ei;
                    outLayerIndex = li;
                    return effect.get();
                }
            }
        }
    }
    return nullptr;
}

EffectInstanceInfo NativeEffectProvider::buildEffectInfo(const NativeEffect* effect, size_t elementIndex, size_t layerIndex) const
{
    EffectInstanceInfo info;
    if (!effect) return info;

    info.effectId = effect->effectId;
    info.elementIndex = elementIndex;
    info.layerIndex = layerIndex;
    info.effectType = effect->effectType;
    info.effectTypeIndex = effect->effectTypeIndex;
    info.startTimeMS = effect->startTimeMS;
    info.endTimeMS = effect->endTimeMS;
    info.selected = effect->selected;
    info.protected_ = effect->protected_;
    info.locked = effect->locked;
    info.renderDisabled = effect->renderDisabled;
    info.settings = effect->settings;
    info.palette = effect->palette;

    return info;
}

bool NativeEffectProvider::isRangeClear(size_t elementIndex, size_t layerIndex, int startTimeMS, int endTimeMS, int64_t excludeEffectId) const
{
    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) return false;
    if (layerIndex >= elem->layers.size()) return false;

    const auto& layer = elem->layers[layerIndex];
    for (const auto& effect : layer->effects) {
        if (excludeEffectId >= 0 && effect->effectId == excludeEffectId) continue;
        if (effect->startTimeMS < endTimeMS && effect->endTimeMS > startTimeMS) {
            return false;
        }
    }
    return true;
}

int64_t NativeEffectProvider::generateEffectId()
{
    return _nextEffectId++;
}

void NativeEffectProvider::recordUndoAction(std::unique_ptr<UndoAction> action)
{
    if (_currentUndoGroup) {
        _currentUndoGroup->actions.push_back(std::move(action));
    } else {
        auto group = std::make_unique<UndoGroup>();
        group->description = "Edit";
        group->actions.push_back(std::move(action));
        _undoStack.push_back(std::move(group));
        if (_undoStack.size() > kMaxUndoLevels) {
            _undoStack.pop_front();
        }
    }
    clearRedoStack();
}

void NativeEffectProvider::clearRedoStack()
{
    _redoStack.clear();
}

void NativeEffectProvider::incrementChangeCount()
{
    _changeCount++;
    _isModified = true;
}

// --- IEffectProvider Implementation: Element Access ---

size_t NativeEffectProvider::getElementCount() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return _elements.size();
}

bool NativeEffectProvider::getElement(size_t index, ElementInfo& outInfo) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    NativeElement* elem = getElementPtr(index);
    if (!elem) return false;

    outInfo.index = index;
    outInfo.name = elem->name;
    outInfo.fullName = elem->fullName;
    outInfo.modelName = elem->modelName;
    outInfo.type = elem->type;
    outInfo.visible = elem->visible;
    outInfo.collapsed = elem->collapsed;
    outInfo.renderDisabled = elem->renderDisabled;
    outInfo.effectLayerCount = elem->layers.size();
    outInfo.effectCount = elem->getEffectCount();
    outInfo.fixedTiming = elem->fixedTiming;
    outInfo.isActive = elem->isActive;
    outInfo.parentElementName = elem->parentElementName;
    outInfo.strandIndex = elem->strandIndex;

    return true;
}

bool NativeEffectProvider::getElementByName(const std::string& name, ElementInfo& outInfo) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    auto it = _elementsByName.find(name);
    if (it == _elementsByName.end()) return false;

    return getElement(it->second, outInfo);
}

size_t NativeEffectProvider::getElementIndex(const std::string& name) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    auto it = _elementsByName.find(name);
    if (it == _elementsByName.end()) return SIZE_MAX;
    return it->second;
}

// --- IEffectProvider Implementation: Effect Layer Access ---

size_t NativeEffectProvider::getEffectLayerCount(size_t elementIndex) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) return 0;
    return elem->layers.size();
}

size_t NativeEffectProvider::getEffectCount(size_t elementIndex, size_t layerIndex) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) return 0;
    if (layerIndex >= elem->layers.size()) return 0;
    return elem->layers[layerIndex]->effects.size();
}

size_t NativeEffectProvider::getTotalEffectCount(size_t elementIndex) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) return 0;
    return elem->getEffectCount();
}

// --- IEffectProvider Implementation: Effect Queries ---

std::vector<EffectInstanceInfo> NativeEffectProvider::getEffectsInRange(
    size_t elementIndex,
    size_t layerIndex,
    int startTimeMS,
    int endTimeMS) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    std::vector<EffectInstanceInfo> result;
    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) return result;
    if (layerIndex >= elem->layers.size()) return result;

    const auto& layer = elem->layers[layerIndex];
    for (const auto& effect : layer->effects) {
        if (effect->startTimeMS < endTimeMS && effect->endTimeMS > startTimeMS) {
            result.push_back(buildEffectInfo(effect.get(), elementIndex, layerIndex));
        }
    }

    return result;
}

std::vector<EffectInstanceInfo> NativeEffectProvider::getEffectsOnLayer(
    size_t elementIndex,
    size_t layerIndex) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    std::vector<EffectInstanceInfo> result;
    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) return result;
    if (layerIndex >= elem->layers.size()) return result;

    const auto& layer = elem->layers[layerIndex];
    result.reserve(layer->effects.size());
    for (const auto& effect : layer->effects) {
        result.push_back(buildEffectInfo(effect.get(), elementIndex, layerIndex));
    }

    return result;
}

std::vector<EffectInstanceInfo> NativeEffectProvider::getAllEffects(size_t elementIndex) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    std::vector<EffectInstanceInfo> result;
    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) return result;

    for (size_t li = 0; li < elem->layers.size(); ++li) {
        const auto& layer = elem->layers[li];
        for (const auto& effect : layer->effects) {
            result.push_back(buildEffectInfo(effect.get(), elementIndex, li));
        }
    }

    return result;
}

bool NativeEffectProvider::getEffect(int64_t effectId, EffectInstanceInfo& outInfo) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    size_t elementIndex = 0;
    size_t layerIndex = 0;
    NativeEffect* effect = findEffectById(effectId, elementIndex, layerIndex);
    if (!effect) return false;

    outInfo = buildEffectInfo(effect, elementIndex, layerIndex);
    return true;
}

bool NativeEffectProvider::getEffectAtTime(
    size_t elementIndex,
    size_t layerIndex,
    int timeMS,
    EffectInstanceInfo& outInfo) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) return false;
    if (layerIndex >= elem->layers.size()) return false;

    const auto& layer = elem->layers[layerIndex];
    for (const auto& effect : layer->effects) {
        if (effect->startTimeMS <= timeMS && effect->endTimeMS > timeMS) {
            outInfo = buildEffectInfo(effect.get(), elementIndex, layerIndex);
            return true;
        }
    }

    return false;
}

// --- IEffectProvider Implementation: Effect Type Information ---

std::vector<std::string> NativeEffectProvider::getEffectTypes() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    std::vector<std::string> result;
    result.reserve(_effectTypes.size());
    for (const auto& info : _effectTypes) {
        result.push_back(info.name);
    }
    return result;
}

size_t NativeEffectProvider::getEffectTypeCount() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return _effectTypes.size();
}

std::string NativeEffectProvider::getEffectTypeName(size_t typeIndex) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (typeIndex >= _effectTypes.size()) return "";
    return _effectTypes[typeIndex].name;
}

// --- IEffectProvider Implementation: Effect Settings Access ---

std::map<std::string, std::string> NativeEffectProvider::getEffectSettings(int64_t effectId) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    NativeEffect* effect = findEffectById(effectId);
    if (!effect) return {};
    return effect->settings;
}

std::string NativeEffectProvider::getEffectSetting(
    int64_t effectId,
    const std::string& key,
    const std::string& defaultValue) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    NativeEffect* effect = findEffectById(effectId);
    if (!effect) return defaultValue;

    auto it = effect->settings.find(key);
    if (it == effect->settings.end()) return defaultValue;
    return it->second;
}

std::map<std::string, std::string> NativeEffectProvider::getEffectPalette(int64_t effectId) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    NativeEffect* effect = findEffectById(effectId);
    if (!effect) return {};
    return effect->palette;
}

// --- IEffectProvider Implementation: Effect Modification - Create ---

EffectOperationResult NativeEffectProvider::createEffect(
    size_t elementIndex,
    size_t layerIndex,
    const std::string& effectType,
    int startTimeMS,
    int endTimeMS)
{
    return createEffectWithSettings(elementIndex, layerIndex, effectType, startTimeMS, endTimeMS, {}, {});
}

EffectOperationResult NativeEffectProvider::createEffectWithSettings(
    size_t elementIndex,
    size_t layerIndex,
    const std::string& effectType,
    int startTimeMS,
    int endTimeMS,
    const std::map<std::string, std::string>& settings,
    const std::map<std::string, std::string>& palette)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;

    if (startTimeMS >= endTimeMS) {
        result.success = false;
        result.errorMessage = "Invalid time range";
        return result;
    }

    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) {
        result.success = false;
        result.errorMessage = "Element not found";
        return result;
    }

    if (layerIndex >= elem->layers.size()) {
        result.success = false;
        result.errorMessage = "Layer index out of range";
        return result;
    }

    if (!isRangeClear(elementIndex, layerIndex, startTimeMS, endTimeMS)) {
        result.success = false;
        result.errorMessage = "Time range is not clear";
        return result;
    }

    auto effect = std::make_unique<NativeEffect>();
    effect->effectId = generateEffectId();
    effect->effectType = effectType;
    effect->startTimeMS = startTimeMS;
    effect->endTimeMS = endTimeMS;
    effect->settings = settings;
    effect->palette = palette;

    // Apply default palette if none provided (matches legacy xLights defaults)
    if (effect->palette.empty()) {
        effect->palette["C_BUTTON_Palette1"] = "#FFFFFF";
        effect->palette["C_BUTTON_Palette2"] = "#FF0000";
        effect->palette["C_BUTTON_Palette3"] = "#00FF00";
        effect->palette["C_BUTTON_Palette4"] = "#0000FF";
        effect->palette["C_BUTTON_Palette5"] = "#FFFF00";
        effect->palette["C_BUTTON_Palette6"] = "#000000";
        effect->palette["C_BUTTON_Palette7"] = "#00FFFF";
        effect->palette["C_BUTTON_Palette8"] = "#FF00FF";
        effect->palette["C_CHECKBOX_Palette1"] = "1";
        effect->palette["C_CHECKBOX_Palette2"] = "1";
    }

    // Find effect type index
    for (size_t i = 0; i < _effectTypes.size(); ++i) {
        if (_effectTypes[i].name == effectType) {
            effect->effectTypeIndex = static_cast<int>(i);
            break;
        }
    }

    int64_t effectId = effect->effectId;
    NativeEffect* effectPtr = effect.get();
    _effectsById[effectId] = effectPtr;
    elem->layers[layerIndex]->effects.push_back(std::move(effect));
    elem->layers[layerIndex]->sortEffects();

    // Record undo action
    auto undoAction = std::make_unique<CreateEffectUndoAction>();
    undoAction->effectId = effectId;
    undoAction->elementIndex = elementIndex;
    undoAction->layerIndex = layerIndex;
    undoAction->effectType = effectType;
    undoAction->startTimeMS = startTimeMS;
    undoAction->endTimeMS = endTimeMS;
    undoAction->settings = settings;
    undoAction->palette = palette;
    recordUndoAction(std::move(undoAction));

    incrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

// --- IEffectProvider Implementation: Effect Modification - Delete ---

EffectOperationResult NativeEffectProvider::deleteEffect(int64_t effectId)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;

    size_t elementIndex = 0;
    size_t layerIndex = 0;
    NativeEffect* effect = findEffectById(effectId, elementIndex, layerIndex);
    if (!effect) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    // Record undo action before deletion
    auto undoAction = std::make_unique<DeleteEffectUndoAction>();
    undoAction->effectId = effectId;
    undoAction->elementIndex = elementIndex;
    undoAction->layerIndex = layerIndex;
    undoAction->effectType = effect->effectType;
    undoAction->startTimeMS = effect->startTimeMS;
    undoAction->endTimeMS = effect->endTimeMS;
    undoAction->settings = effect->settings;
    undoAction->palette = effect->palette;

    // Remove from effectsById
    _effectsById.erase(effectId);

    // Remove from selection
    auto selIt = std::find(_selectedEffects.begin(), _selectedEffects.end(), effectId);
    if (selIt != _selectedEffects.end()) {
        _selectedEffects.erase(selIt);
    }

    // Remove from layer
    NativeElement* elem = getElementPtr(elementIndex);
    auto& effects = elem->layers[layerIndex]->effects;
    effects.erase(
        std::remove_if(effects.begin(), effects.end(),
            [effectId](const std::unique_ptr<NativeEffect>& e) { return e->effectId == effectId; }),
        effects.end());

    recordUndoAction(std::move(undoAction));
    incrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult NativeEffectProvider::deleteEffects(const std::vector<int64_t>& effectIds)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;
    result.success = true;

    beginUndoGroup("Delete Multiple Effects");

    for (int64_t id : effectIds) {
        EffectOperationResult r = deleteEffect(id);
        if (!r.success) {
            result.success = false;
            result.errorMessage += r.errorMessage + "; ";
        }
    }

    endUndoGroup();

    return result;
}

// --- IEffectProvider Implementation: Effect Property Modification ---

EffectOperationResult NativeEffectProvider::setEffectLocked(int64_t effectId, bool locked)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;
    NativeEffect* effect = findEffectById(effectId);
    if (!effect) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    effect->locked = locked;
    incrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult NativeEffectProvider::setEffectRenderDisabled(int64_t effectId, bool disabled)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;
    NativeEffect* effect = findEffectById(effectId);
    if (!effect) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    effect->renderDisabled = disabled;
    incrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult NativeEffectProvider::resetEffectToDefaults(int64_t effectId)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;
    NativeEffect* effect = findEffectById(effectId);
    if (!effect) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    // Record undo action before clearing
    beginUndoGroup("Reset Effect to Defaults");

    effect->settings.clear();
    effect->palette.clear();
    incrementChangeCount();

    endUndoGroup();

    result.success = true;
    result.effectId = effectId;
    return result;
}

// --- IEffectProvider Implementation: Effect Modification - Update ---

EffectOperationResult NativeEffectProvider::updateEffectTiming(
    int64_t effectId,
    int newStartTimeMS,
    int newEndTimeMS)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;

    if (newStartTimeMS >= newEndTimeMS) {
        result.success = false;
        result.errorMessage = "Invalid time range";
        return result;
    }

    size_t elementIndex = 0;
    size_t layerIndex = 0;
    NativeEffect* effect = findEffectById(effectId, elementIndex, layerIndex);
    if (!effect) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    if (!isRangeClear(elementIndex, layerIndex, newStartTimeMS, newEndTimeMS, effectId)) {
        result.success = false;
        result.errorMessage = "Time range is not clear";
        return result;
    }

    // Record undo action
    auto undoAction = std::make_unique<UpdateEffectTimingUndoAction>();
    undoAction->effectId = effectId;
    undoAction->oldStartTimeMS = effect->startTimeMS;
    undoAction->oldEndTimeMS = effect->endTimeMS;
    undoAction->newStartTimeMS = newStartTimeMS;
    undoAction->newEndTimeMS = newEndTimeMS;

    effect->startTimeMS = newStartTimeMS;
    effect->endTimeMS = newEndTimeMS;

    // Re-sort the layer
    NativeElement* elem = getElementPtr(elementIndex);
    elem->layers[layerIndex]->sortEffects();

    recordUndoAction(std::move(undoAction));
    incrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult NativeEffectProvider::updateEffectSettings(
    int64_t effectId,
    const std::map<std::string, std::string>& settings)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;

    NativeEffect* effect = findEffectById(effectId);
    if (!effect) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    // Record undo action
    auto undoAction = std::make_unique<UpdateEffectSettingsUndoAction>();
    undoAction->effectId = effectId;
    undoAction->oldSettings = effect->settings;
    undoAction->newSettings = settings;

    effect->settings = settings;

    recordUndoAction(std::move(undoAction));
    incrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult NativeEffectProvider::updateEffectSetting(
    int64_t effectId,
    const std::string& key,
    const std::string& value)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;

    NativeEffect* effect = findEffectById(effectId);
    if (!effect) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    auto oldSettings = effect->settings;
    effect->settings[key] = value;

    auto undoAction = std::make_unique<UpdateEffectSettingsUndoAction>();
    undoAction->effectId = effectId;
    undoAction->oldSettings = oldSettings;
    undoAction->newSettings = effect->settings;
    recordUndoAction(std::move(undoAction));

    incrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult NativeEffectProvider::updateEffectPalette(
    int64_t effectId,
    const std::map<std::string, std::string>& palette)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;

    NativeEffect* effect = findEffectById(effectId);
    if (!effect) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    auto undoAction = std::make_unique<UpdateEffectPaletteUndoAction>();
    undoAction->effectId = effectId;
    undoAction->oldPalette = effect->palette;
    undoAction->newPalette = palette;

    effect->palette = palette;

    recordUndoAction(std::move(undoAction));
    incrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult NativeEffectProvider::updateEffectType(
    int64_t effectId,
    const std::string& newEffectType)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;

    NativeEffect* effect = findEffectById(effectId);
    if (!effect) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    // Verify the new type exists
    int newTypeIndex = -1;
    for (size_t i = 0; i < _effectTypes.size(); ++i) {
        if (_effectTypes[i].name == newEffectType) {
            newTypeIndex = static_cast<int>(i);
            break;
        }
    }

    effect->effectType = newEffectType;
    effect->effectTypeIndex = (newTypeIndex != -1) ? newTypeIndex : effect->effectTypeIndex;

    incrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult NativeEffectProvider::moveEffectToLayer(
    int64_t effectId,
    size_t newLayerIndex)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;

    size_t elementIndex = 0;
    size_t oldLayerIndex = 0;
    NativeEffect* effect = findEffectById(effectId, elementIndex, oldLayerIndex);
    if (!effect) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    NativeElement* elem = getElementPtr(elementIndex);
    if (newLayerIndex >= elem->layers.size()) {
        result.success = false;
        result.errorMessage = "Target layer index out of range";
        return result;
    }

    if (oldLayerIndex == newLayerIndex) {
        result.success = true;
        result.effectId = effectId;
        return result;
    }

    if (!isRangeClear(elementIndex, newLayerIndex, effect->startTimeMS, effect->endTimeMS)) {
        result.success = false;
        result.errorMessage = "Target time range is not clear";
        return result;
    }

    // Find and move the effect
    auto& oldEffects = elem->layers[oldLayerIndex]->effects;
    std::unique_ptr<NativeEffect> movedEffect;
    for (auto it = oldEffects.begin(); it != oldEffects.end(); ++it) {
        if ((*it)->effectId == effectId) {
            movedEffect = std::move(*it);
            oldEffects.erase(it);
            break;
        }
    }

    if (movedEffect) {
        elem->layers[newLayerIndex]->effects.push_back(std::move(movedEffect));
        elem->layers[newLayerIndex]->sortEffects();
    }

    incrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

// --- IEffectProvider Implementation: Layer Management ---

size_t NativeEffectProvider::addEffectLayer(size_t elementIndex)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) return SIZE_MAX;

    elem->layers.push_back(std::make_unique<NativeEffectLayer>());
    incrementChangeCount();

    return elem->layers.size() - 1;
}

EffectOperationResult NativeEffectProvider::removeEffectLayer(size_t elementIndex, size_t layerIndex)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    EffectOperationResult result;

    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) {
        result.success = false;
        result.errorMessage = "Element not found";
        return result;
    }

    if (layerIndex >= elem->layers.size()) {
        result.success = false;
        result.errorMessage = "Layer index out of range";
        return result;
    }

    if (elem->layers.size() == 1) {
        result.success = false;
        result.errorMessage = "Cannot remove the last layer";
        return result;
    }

    // Remove all effects from effectsById
    for (const auto& effect : elem->layers[layerIndex]->effects) {
        _effectsById.erase(effect->effectId);
        auto selIt = std::find(_selectedEffects.begin(), _selectedEffects.end(), effect->effectId);
        if (selIt != _selectedEffects.end()) {
            _selectedEffects.erase(selIt);
        }
    }

    elem->layers.erase(elem->layers.begin() + layerIndex);
    incrementChangeCount();

    result.success = true;
    return result;
}

size_t NativeEffectProvider::insertEffectLayer(size_t elementIndex, size_t atIndex)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) return SIZE_MAX;

    if (atIndex > elem->layers.size()) {
        atIndex = elem->layers.size();
    }

    elem->layers.insert(elem->layers.begin() + atIndex, std::make_unique<NativeEffectLayer>());
    incrementChangeCount();

    return atIndex;
}

// --- IEffectProvider Implementation: Selection Management ---

bool NativeEffectProvider::selectEffect(int64_t effectId, bool addToSelection)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    NativeEffect* effect = findEffectById(effectId);
    if (!effect) return false;

    if (!addToSelection) {
        deselectAllEffects();
    }

    if (std::find(_selectedEffects.begin(), _selectedEffects.end(), effectId) == _selectedEffects.end()) {
        _selectedEffects.push_back(effectId);
    }
    effect->selected = true;

    return true;
}

bool NativeEffectProvider::deselectEffect(int64_t effectId)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    NativeEffect* effect = findEffectById(effectId);
    if (!effect) return false;

    effect->selected = false;
    auto it = std::find(_selectedEffects.begin(), _selectedEffects.end(), effectId);
    if (it != _selectedEffects.end()) {
        _selectedEffects.erase(it);
    }

    return true;
}

void NativeEffectProvider::deselectAllEffects()
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    for (int64_t id : _selectedEffects) {
        NativeEffect* effect = findEffectById(id);
        if (effect) {
            effect->selected = false;
        }
    }
    _selectedEffects.clear();
}

std::vector<int64_t> NativeEffectProvider::getSelectedEffectIds() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return _selectedEffects;
}

// --- IEffectProvider Implementation: Undo/Redo Integration ---

void NativeEffectProvider::beginUndoGroup(const std::string& description)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (_currentUndoGroup) {
        endUndoGroup();
    }

    _currentUndoGroup = std::make_unique<UndoGroup>();
    _currentUndoGroup->description = description;
}

void NativeEffectProvider::endUndoGroup()
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (!_currentUndoGroup) return;

    if (!_currentUndoGroup->actions.empty()) {
        _undoStack.push_back(std::move(_currentUndoGroup));
        if (_undoStack.size() > kMaxUndoLevels) {
            _undoStack.pop_front();
        }
    }
    _currentUndoGroup.reset();
}

void NativeEffectProvider::cancelUndoGroup()
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    _currentUndoGroup.reset();
}

bool NativeEffectProvider::canUndo() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return !_undoStack.empty();
}

bool NativeEffectProvider::canRedo() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return !_redoStack.empty();
}

bool NativeEffectProvider::undo()
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (_undoStack.empty()) return false;

    auto group = std::move(_undoStack.back());
    _undoStack.pop_back();

    // Execute undo actions in reverse order
    for (auto it = group->actions.rbegin(); it != group->actions.rend(); ++it) {
        (*it)->undo(*this);
    }

    _redoStack.push_back(std::move(group));

    return true;
}

bool NativeEffectProvider::redo()
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (_redoStack.empty()) return false;

    auto group = std::move(_redoStack.back());
    _redoStack.pop_back();

    // Execute redo actions in forward order
    for (auto& action : group->actions) {
        action->redo(*this);
    }

    _undoStack.push_back(std::move(group));

    return true;
}

std::string NativeEffectProvider::getUndoDescription() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (_undoStack.empty()) return "";
    return _undoStack.back()->description;
}

std::string NativeEffectProvider::getRedoDescription() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (_redoStack.empty()) return "";
    return _redoStack.back()->description;
}

// --- IEffectProvider Implementation: Clipboard Operations ---

bool NativeEffectProvider::copySelectedEffects()
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (_selectedEffects.empty()) return false;

    _clipboard.clear();

    // Find the minimum start time and layer index for relative positioning
    int minStartTime = INT_MAX;
    size_t minLayerIndex = SIZE_MAX;

    for (int64_t id : _selectedEffects) {
        size_t elementIndex = 0;
        size_t layerIndex = 0;
        NativeEffect* effect = findEffectById(id, elementIndex, layerIndex);
        if (effect) {
            minStartTime = std::min(minStartTime, effect->startTimeMS);
            minLayerIndex = std::min(minLayerIndex, layerIndex);
        }
    }

    for (int64_t id : _selectedEffects) {
        size_t elementIndex = 0;
        size_t layerIndex = 0;
        NativeEffect* effect = findEffectById(id, elementIndex, layerIndex);
        if (effect) {
            ClipboardEffect ce;
            ce.effectType = effect->effectType;
            ce.durationMS = effect->endTimeMS - effect->startTimeMS;
            ce.settings = effect->settings;
            ce.palette = effect->palette;
            ce.relativeLayerIndex = layerIndex - minLayerIndex;
            ce.relativeStartTimeMS = effect->startTimeMS - minStartTime;
            _clipboard.push_back(ce);
        }
    }

    return !_clipboard.empty();
}

bool NativeEffectProvider::cutSelectedEffects()
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (!copySelectedEffects()) return false;

    std::vector<int64_t> toDelete = _selectedEffects;
    beginUndoGroup("Cut Effects");
    for (int64_t id : toDelete) {
        deleteEffect(id);
    }
    endUndoGroup();

    return true;
}

std::vector<int64_t> NativeEffectProvider::pasteEffects(
    size_t elementIndex,
    size_t layerIndex,
    int startTimeMS)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    std::vector<int64_t> pastedIds;

    if (_clipboard.empty()) return pastedIds;

    NativeElement* elem = getElementPtr(elementIndex);
    if (!elem) return pastedIds;

    beginUndoGroup("Paste Effects");

    for (const auto& ce : _clipboard) {
        size_t targetLayer = layerIndex + ce.relativeLayerIndex;
        if (targetLayer >= elem->layers.size()) {
            targetLayer = elem->layers.size() - 1;
        }

        int targetStart = startTimeMS + ce.relativeStartTimeMS;
        int targetEnd = targetStart + ce.durationMS;

        auto result = createEffectWithSettings(elementIndex, targetLayer, ce.effectType,
            targetStart, targetEnd, ce.settings, ce.palette);

        if (result.success) {
            pastedIds.push_back(result.effectId);
        }
    }

    endUndoGroup();

    return pastedIds;
}

bool NativeEffectProvider::canPaste() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return !_clipboard.empty();
}

// --- Extended Operations for Native Use ---

size_t NativeEffectProvider::addElement(const std::string& name, SequenceElementType type)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (_elementsByName.find(name) != _elementsByName.end()) {
        return SIZE_MAX; // Element already exists
    }

    auto element = std::make_unique<NativeElement>();
    element->name = name;
    element->fullName = name;
    element->modelName = name;
    element->type = type;
    element->layers.push_back(std::make_unique<NativeEffectLayer>());

    size_t index = _elements.size();
    _elementsByName[name] = index;
    _elements.push_back(std::move(element));

    incrementChangeCount();

    return index;
}

bool NativeEffectProvider::removeElement(size_t elementIndex)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (elementIndex >= _elements.size()) return false;

    // Remove all effects from this element
    for (const auto& layer : _elements[elementIndex]->layers) {
        for (const auto& effect : layer->effects) {
            _effectsById.erase(effect->effectId);
            auto selIt = std::find(_selectedEffects.begin(), _selectedEffects.end(), effect->effectId);
            if (selIt != _selectedEffects.end()) {
                _selectedEffects.erase(selIt);
            }
        }
    }

    std::string removedName = _elements[elementIndex]->name;
    _elements.erase(_elements.begin() + elementIndex);

    // Rebuild name index
    _elementsByName.clear();
    for (size_t i = 0; i < _elements.size(); ++i) {
        _elementsByName[_elements[i]->name] = i;
    }

    incrementChangeCount();

    return true;
}

bool NativeEffectProvider::setTimingTrackActive(const std::string& name)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    bool found = false;
    for (auto& elem : _elements) {
        if (elem->type != SequenceElementType::Timing) continue;
        if (elem->name == name) {
            elem->isActive = true;
            found = true;
        } else {
            elem->isActive = false;
        }
    }
    return found;
}

void NativeEffectProvider::deactivateAllTimingTracks()
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    for (auto& elem : _elements) {
        if (elem->type == SequenceElementType::Timing) {
            elem->isActive = false;
        }
    }
}

// --- Song Structure Regions ---

// Default color palette (8 semi-transparent colors, cycled on creation)
static const uint32_t kSongRegionPalette[] = {
    0x404488CC, // Blue
    0x4044AA66, // Green
    0x40DD8833, // Orange
    0x409966CC, // Purple
    0x4033AAAA, // Teal
    0x40CC4444, // Red
    0x40667788, // Slate
    0x40CC9944, // Amber
};
static const size_t kSongRegionPaletteCount = sizeof(kSongRegionPalette) / sizeof(kSongRegionPalette[0]);

std::vector<SongStructureRegion> NativeEffectProvider::getSongStructureRegions() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return _songRegions;
}

void NativeEffectProvider::addSongStructureBoundary(int timeMS)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    int duration = _sequenceLengthMS > 0 ? _sequenceLengthMS : 300000;
    if (timeMS <= 0 || timeMS >= duration) return;

    if (_songRegions.empty()) {
        // First boundary: create two regions spanning the full sequence
        SongStructureRegion left;
        left.regionId = _nextRegionId++;
        left.startTimeMS = 0;
        left.endTimeMS = timeMS;
        left.name = "Region 1";
        left.colorARGB = kSongRegionPalette[0];

        SongStructureRegion right;
        right.regionId = _nextRegionId++;
        right.startTimeMS = timeMS;
        right.endTimeMS = duration;
        right.name = "Region 2";
        right.colorARGB = kSongRegionPalette[1];

        _songRegions.push_back(left);
        _songRegions.push_back(right);
    } else {
        // Find the region containing timeMS and split it
        for (size_t i = 0; i < _songRegions.size(); i++) {
            auto& region = _songRegions[i];
            if (timeMS > region.startTimeMS && timeMS < region.endTimeMS) {
                SongStructureRegion newRegion;
                newRegion.regionId = _nextRegionId++;
                newRegion.startTimeMS = timeMS;
                newRegion.endTimeMS = region.endTimeMS;
                newRegion.name = "Region " + std::to_string(_songRegions.size() + 1);
                newRegion.colorARGB = kSongRegionPalette[_songRegions.size() % kSongRegionPaletteCount];

                region.endTimeMS = timeMS;

                _songRegions.insert(_songRegions.begin() + i + 1, newRegion);
                break;
            }
        }
    }

    incrementChangeCount();
}

void NativeEffectProvider::moveSongStructureBoundary(size_t idx, int newTimeMS)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    // idx is the boundary between region[idx] and region[idx+1]
    if (idx >= _songRegions.size() - 1) return;
    if (_songRegions.size() < 2) return;

    // Clamp: must stay between left region's start and right region's end
    int minTime = _songRegions[idx].startTimeMS + 1;
    int maxTime = _songRegions[idx + 1].endTimeMS - 1;
    if (newTimeMS < minTime) newTimeMS = minTime;
    if (newTimeMS > maxTime) newTimeMS = maxTime;

    _songRegions[idx].endTimeMS = newTimeMS;
    _songRegions[idx + 1].startTimeMS = newTimeMS;

    incrementChangeCount();
}

void NativeEffectProvider::deleteSongStructureBoundary(size_t idx)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    // idx is the boundary between region[idx] and region[idx+1]
    if (idx >= _songRegions.size() - 1) return;
    if (_songRegions.size() < 2) return;

    // Merge: extend left region to cover the right, then remove right
    _songRegions[idx].endTimeMS = _songRegions[idx + 1].endTimeMS;
    _songRegions.erase(_songRegions.begin() + idx + 1);

    // If only one region remains, clear it entirely (no boundaries = no structure)
    if (_songRegions.size() == 1) {
        _songRegions.clear();
    }

    incrementChangeCount();
}

void NativeEffectProvider::updateSongStructureRegion(int64_t regionId, const std::string& name, uint32_t colorARGB)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    for (auto& region : _songRegions) {
        if (region.regionId == regionId) {
            region.name = name;
            region.colorARGB = colorARGB;
            incrementChangeCount();
            return;
        }
    }
}

void NativeEffectProvider::clearSongStructure()
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    _songRegions.clear();
    incrementChangeCount();
}

// --- Track Folder Operations ---

std::vector<TrackFolder> NativeEffectProvider::getTrackFolders() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return _trackFolders;
}

bool NativeEffectProvider::createTrackFolder(const std::string& name)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (name.empty()) return false;

    for (const auto& f : _trackFolders) {
        if (f.name == name) return false;
    }

    TrackFolder folder;
    folder.name = name;
    folder.collapsed = false;
    _trackFolders.push_back(folder);
    incrementChangeCount();
    return true;
}

bool NativeEffectProvider::deleteTrackFolder(const std::string& name)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    auto it = std::find_if(_trackFolders.begin(), _trackFolders.end(),
        [&name](const TrackFolder& f) { return f.name == name; });
    if (it == _trackFolders.end()) return false;

    _trackFolders.erase(it);

    // Ungroup all elements in this folder
    for (auto& elem : _elements) {
        if (elem->folder == name) {
            elem->folder.clear();
        }
    }

    incrementChangeCount();
    return true;
}

bool NativeEffectProvider::renameTrackFolder(const std::string& oldName, const std::string& newName)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    if (newName.empty()) return false;

    // Check new name doesn't conflict
    for (const auto& f : _trackFolders) {
        if (f.name == newName) return false;
    }

    auto it = std::find_if(_trackFolders.begin(), _trackFolders.end(),
        [&oldName](const TrackFolder& f) { return f.name == oldName; });
    if (it == _trackFolders.end()) return false;

    it->name = newName;

    // Update all elements referencing the old folder name
    for (auto& elem : _elements) {
        if (elem->folder == oldName) {
            elem->folder = newName;
        }
    }

    incrementChangeCount();
    return true;
}

bool NativeEffectProvider::setElementFolder(const std::string& elementName, const std::string& folderName)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    auto nameIt = _elementsByName.find(elementName);
    if (nameIt == _elementsByName.end()) return false;

    NativeElement* elem = _elements[nameIt->second].get();

    // Don't allow timing tracks in folders
    if (elem->type == SequenceElementType::Timing) return false;

    // If assigning to a folder, verify it exists (or create it)
    if (!folderName.empty()) {
        bool found = false;
        for (const auto& f : _trackFolders) {
            if (f.name == folderName) { found = true; break; }
        }
        if (!found) {
            createTrackFolder(folderName);
        }
    }

    elem->folder = folderName;
    incrementChangeCount();
    return true;
}

std::string NativeEffectProvider::getElementFolder(const std::string& elementName) const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    auto nameIt = _elementsByName.find(elementName);
    if (nameIt == _elementsByName.end()) return "";

    return _elements[nameIt->second]->folder;
}

bool NativeEffectProvider::setTrackFolderCollapsed(const std::string& name, bool collapsed)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);

    for (auto& f : _trackFolders) {
        if (f.name == name) {
            f.collapsed = collapsed;
            return true;
        }
    }
    return false;
}

void NativeEffectProvider::setModified(bool modified)
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    _isModified = modified;
    if (!modified) {
        _changeCount = 0;
    }
}

bool NativeEffectProvider::isModified() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return _isModified;
}

int NativeEffectProvider::getChangeCount() const
{
    std::lock_guard<std::recursive_mutex> lock(_mutex);
    return _changeCount;
}

} // namespace xlEngine
