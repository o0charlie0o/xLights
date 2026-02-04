/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "SequenceElementsAdapter.h"
#include "../../xLightsMain.h"
#include "../../sequencer/SequenceElements.h"
#include "../../sequencer/Element.h"
#include "../../sequencer/Effect.h"
#include "../../sequencer/EffectLayer.h"
#include "../../effects/EffectManager.h"
#include "../../effects/RenderableEffect.h"

namespace xlEngine {

SequenceElementsAdapter::SequenceElementsAdapter(xLightsFrame* frame)
    : _frame(frame)
{
}

// --- Internal Helpers ---

SequenceElements* SequenceElementsAdapter::getSequenceElements() const
{
    if (!_frame) return nullptr;
    return &_frame->GetSequenceElements();
}

EffectManager* SequenceElementsAdapter::getEffectManager() const
{
    if (!_frame) return nullptr;
    return &_frame->GetEffectManager();
}

Element* SequenceElementsAdapter::getElementByIndex(size_t index) const
{
    SequenceElements* se = getSequenceElements();
    if (!se) return nullptr;
    if (index >= se->GetElementCount()) return nullptr;
    return se->GetElement(index);
}

EffectInstanceInfo SequenceElementsAdapter::buildEffectInfo(Effect* effect, size_t elementIndex, size_t layerIndex) const
{
    EffectInstanceInfo info;
    if (!effect) return info;

    info.effectId = effect->GetID();
    info.elementIndex = elementIndex;
    info.layerIndex = layerIndex;
    info.effectType = effect->GetEffectName();
    info.effectTypeIndex = effect->GetEffectIndex();
    info.startTimeMS = effect->GetStartTimeMS();
    info.endTimeMS = effect->GetEndTimeMS();
    info.selected = (effect->GetSelected() != EFFECT_NOT_SELECTED);
    info.protected_ = effect->GetProtected();
    info.locked = effect->IsLocked();
    info.renderDisabled = effect->IsRenderDisabled();

    // Copy settings
    const SettingsMap& sm = effect->GetSettings();
    for (auto it = sm.begin(); it != sm.end(); ++it) {
        info.settings[it->first] = it->second;
    }

    // Copy palette
    const SettingsMap& pm = effect->GetPaletteMap();
    for (auto it = pm.begin(); it != pm.end(); ++it) {
        info.palette[it->first] = it->second;
    }

    return info;
}

Effect* SequenceElementsAdapter::findEffectById(int64_t effectId, size_t& outElementIndex, size_t& outLayerIndex) const
{
    SequenceElements* se = getSequenceElements();
    if (!se) return nullptr;

    for (size_t i = 0; i < se->GetElementCount(); ++i) {
        Element* elem = se->GetElement(i);
        if (!elem) continue;

        for (size_t layer = 0; layer < elem->GetEffectLayerCount(); ++layer) {
            EffectLayer* el = elem->GetEffectLayer(layer);
            if (!el) continue;

            for (int e = 0; e < el->GetEffectCount(); ++e) {
                Effect* eff = el->GetEffect(e);
                if (eff && eff->GetID() == (int)effectId) {
                    outElementIndex = i;
                    outLayerIndex = layer;
                    return eff;
                }
            }
        }

        // Also search submodels and strands for ModelElements
        if (elem->GetType() == ElementType::ELEMENT_TYPE_MODEL) {
            ModelElement* me = dynamic_cast<ModelElement*>(elem);
            if (me) {
                for (int s = 0; s < me->GetSubModelCount(); ++s) {
                    SubModelElement* sme = me->GetSubModel(s);
                    if (!sme) continue;
                    for (size_t layer = 0; layer < sme->GetEffectLayerCount(); ++layer) {
                        EffectLayer* el = sme->GetEffectLayer(layer);
                        if (!el) continue;
                        for (int e = 0; e < el->GetEffectCount(); ++e) {
                            Effect* eff = el->GetEffect(e);
                            if (eff && eff->GetID() == (int)effectId) {
                                outElementIndex = i;
                                outLayerIndex = layer;
                                return eff;
                            }
                        }
                    }
                }
                for (int s = 0; s < me->GetStrandCount(); ++s) {
                    StrandElement* strand = me->GetStrand(s);
                    if (!strand) continue;
                    for (size_t layer = 0; layer < strand->GetEffectLayerCount(); ++layer) {
                        EffectLayer* el = strand->GetEffectLayer(layer);
                        if (!el) continue;
                        for (int e = 0; e < el->GetEffectCount(); ++e) {
                            Effect* eff = el->GetEffect(e);
                            if (eff && eff->GetID() == (int)effectId) {
                                outElementIndex = i;
                                outLayerIndex = layer;
                                return eff;
                            }
                        }
                    }
                }
            }
        }
    }

    return nullptr;
}

// --- IEffectProvider Implementation: Element Access ---

size_t SequenceElementsAdapter::getElementCount() const
{
    SequenceElements* se = getSequenceElements();
    if (!se) return 0;
    return se->GetElementCount();
}

bool SequenceElementsAdapter::getElement(size_t index, ElementInfo& outInfo) const
{
    Element* elem = getElementByIndex(index);
    if (!elem) return false;

    outInfo.index = index;
    outInfo.name = elem->GetName();
    outInfo.fullName = elem->GetFullName();
    outInfo.modelName = elem->GetModelName();
    outInfo.visible = elem->GetVisible();
    outInfo.collapsed = elem->GetCollapsed();
    outInfo.renderDisabled = elem->IsRenderDisabled();
    outInfo.effectLayerCount = elem->GetEffectLayerCount();
    outInfo.effectCount = elem->GetEffectCount();

    switch (elem->GetType()) {
        case ElementType::ELEMENT_TYPE_MODEL:
            outInfo.type = SequenceElementType::Model;
            break;
        case ElementType::ELEMENT_TYPE_SUBMODEL:
            outInfo.type = SequenceElementType::Submodel;
            break;
        case ElementType::ELEMENT_TYPE_STRAND:
            outInfo.type = SequenceElementType::Strand;
            break;
        case ElementType::ELEMENT_TYPE_TIMING:
            outInfo.type = SequenceElementType::Timing;
            if (TimingElement* te = dynamic_cast<TimingElement*>(elem)) {
                outInfo.fixedTiming = te->GetFixedTiming();
                outInfo.isActive = te->GetActive();
            }
            break;
    }

    return true;
}

bool SequenceElementsAdapter::getElementByName(const std::string& name, ElementInfo& outInfo) const
{
    SequenceElements* se = getSequenceElements();
    if (!se) return false;

    Element* elem = se->GetElement(name);
    if (!elem) return false;

    // Find the index
    for (size_t i = 0; i < se->GetElementCount(); ++i) {
        if (se->GetElement(i) == elem) {
            return getElement(i, outInfo);
        }
    }
    return false;
}

size_t SequenceElementsAdapter::getElementIndex(const std::string& name) const
{
    SequenceElements* se = getSequenceElements();
    if (!se) return SIZE_MAX;

    int idx = se->GetElementIndex(name);
    if (idx < 0) return SIZE_MAX;
    return static_cast<size_t>(idx);
}

// --- IEffectProvider Implementation: Effect Layer Access ---

size_t SequenceElementsAdapter::getEffectLayerCount(size_t elementIndex) const
{
    Element* elem = getElementByIndex(elementIndex);
    if (!elem) return 0;
    return elem->GetEffectLayerCount();
}

size_t SequenceElementsAdapter::getEffectCount(size_t elementIndex, size_t layerIndex) const
{
    Element* elem = getElementByIndex(elementIndex);
    if (!elem) return 0;
    if (layerIndex >= elem->GetEffectLayerCount()) return 0;

    EffectLayer* el = elem->GetEffectLayer(layerIndex);
    if (!el) return 0;
    return el->GetEffectCount();
}

size_t SequenceElementsAdapter::getTotalEffectCount(size_t elementIndex) const
{
    Element* elem = getElementByIndex(elementIndex);
    if (!elem) return 0;
    return elem->GetEffectCount();
}

// --- IEffectProvider Implementation: Effect Queries ---

std::vector<EffectInstanceInfo> SequenceElementsAdapter::getEffectsInRange(
    size_t elementIndex,
    size_t layerIndex,
    int startTimeMS,
    int endTimeMS) const
{
    std::vector<EffectInstanceInfo> result;
    Element* elem = getElementByIndex(elementIndex);
    if (!elem) return result;
    if (layerIndex >= elem->GetEffectLayerCount()) return result;

    EffectLayer* el = elem->GetEffectLayer(layerIndex);
    if (!el) return result;

    std::vector<Effect*> effects = el->GetAllEffectsByTime(startTimeMS, endTimeMS);
    result.reserve(effects.size());
    for (Effect* eff : effects) {
        result.push_back(buildEffectInfo(eff, elementIndex, layerIndex));
    }

    return result;
}

std::vector<EffectInstanceInfo> SequenceElementsAdapter::getEffectsOnLayer(
    size_t elementIndex,
    size_t layerIndex) const
{
    std::vector<EffectInstanceInfo> result;
    Element* elem = getElementByIndex(elementIndex);
    if (!elem) return result;
    if (layerIndex >= elem->GetEffectLayerCount()) return result;

    EffectLayer* el = elem->GetEffectLayer(layerIndex);
    if (!el) return result;

    for (int e = 0; e < el->GetEffectCount(); ++e) {
        Effect* eff = el->GetEffect(e);
        if (eff) {
            result.push_back(buildEffectInfo(eff, elementIndex, layerIndex));
        }
    }

    return result;
}

std::vector<EffectInstanceInfo> SequenceElementsAdapter::getAllEffects(size_t elementIndex) const
{
    std::vector<EffectInstanceInfo> result;
    Element* elem = getElementByIndex(elementIndex);
    if (!elem) return result;

    for (size_t layer = 0; layer < elem->GetEffectLayerCount(); ++layer) {
        EffectLayer* el = elem->GetEffectLayer(layer);
        if (!el) continue;

        for (int e = 0; e < el->GetEffectCount(); ++e) {
            Effect* eff = el->GetEffect(e);
            if (eff) {
                result.push_back(buildEffectInfo(eff, elementIndex, layer));
            }
        }
    }

    return result;
}

bool SequenceElementsAdapter::getEffect(int64_t effectId, EffectInstanceInfo& outInfo) const
{
    size_t elementIndex = 0;
    size_t layerIndex = 0;
    Effect* eff = findEffectById(effectId, elementIndex, layerIndex);
    if (!eff) return false;

    outInfo = buildEffectInfo(eff, elementIndex, layerIndex);
    return true;
}

bool SequenceElementsAdapter::getEffectAtTime(
    size_t elementIndex,
    size_t layerIndex,
    int timeMS,
    EffectInstanceInfo& outInfo) const
{
    Element* elem = getElementByIndex(elementIndex);
    if (!elem) return false;
    if (layerIndex >= elem->GetEffectLayerCount()) return false;

    EffectLayer* el = elem->GetEffectLayer(layerIndex);
    if (!el) return false;

    Effect* eff = el->GetEffectAtTime(timeMS);
    if (!eff) return false;

    outInfo = buildEffectInfo(eff, elementIndex, layerIndex);
    return true;
}

// --- IEffectProvider Implementation: Effect Type Information ---

std::vector<std::string> SequenceElementsAdapter::getEffectTypes() const
{
    std::vector<std::string> result;
    EffectManager* em = getEffectManager();
    if (!em) return result;

    for (int i = 0; i < (int)em->size(); ++i) {
        RenderableEffect* re = em->GetEffect(i);
        if (re) {
            result.push_back(re->Name());
        }
    }
    return result;
}

size_t SequenceElementsAdapter::getEffectTypeCount() const
{
    EffectManager* em = getEffectManager();
    if (!em) return 0;
    return em->size();
}

std::string SequenceElementsAdapter::getEffectTypeName(size_t typeIndex) const
{
    EffectManager* em = getEffectManager();
    if (!em) return "";
    if (typeIndex >= em->size()) return "";

    RenderableEffect* re = em->GetEffect(typeIndex);
    if (!re) return "";
    return re->Name();
}

// --- IEffectProvider Implementation: Effect Settings Access ---

std::map<std::string, std::string> SequenceElementsAdapter::getEffectSettings(int64_t effectId) const
{
    std::map<std::string, std::string> result;
    size_t elementIndex = 0;
    size_t layerIndex = 0;
    Effect* eff = findEffectById(effectId, elementIndex, layerIndex);
    if (!eff) return result;

    const SettingsMap& sm = eff->GetSettings();
    for (auto it = sm.begin(); it != sm.end(); ++it) {
        result[it->first] = it->second;
    }
    return result;
}

std::string SequenceElementsAdapter::getEffectSetting(
    int64_t effectId,
    const std::string& key,
    const std::string& defaultValue) const
{
    size_t elementIndex = 0;
    size_t layerIndex = 0;
    Effect* eff = findEffectById(effectId, elementIndex, layerIndex);
    if (!eff) return defaultValue;

    std::string value = eff->GetSetting(key);
    return value.empty() ? defaultValue : value;
}

std::map<std::string, std::string> SequenceElementsAdapter::getEffectPalette(int64_t effectId) const
{
    std::map<std::string, std::string> result;
    size_t elementIndex = 0;
    size_t layerIndex = 0;
    Effect* eff = findEffectById(effectId, elementIndex, layerIndex);
    if (!eff) return result;

    const SettingsMap& pm = eff->GetPaletteMap();
    for (auto it = pm.begin(); it != pm.end(); ++it) {
        result[it->first] = it->second;
    }
    return result;
}

// --- IEffectProvider Implementation: Effect Modification - Create ---

EffectOperationResult SequenceElementsAdapter::createEffect(
    size_t elementIndex,
    size_t layerIndex,
    const std::string& effectType,
    int startTimeMS,
    int endTimeMS)
{
    EffectOperationResult result;

    Element* elem = getElementByIndex(elementIndex);
    if (!elem) {
        result.success = false;
        result.errorMessage = "Element not found";
        return result;
    }

    if (layerIndex >= elem->GetEffectLayerCount()) {
        result.success = false;
        result.errorMessage = "Layer index out of range";
        return result;
    }

    EffectLayer* el = elem->GetEffectLayer(layerIndex);
    if (!el) {
        result.success = false;
        result.errorMessage = "Layer not found";
        return result;
    }

    if (!el->GetRangeIsClearMS(startTimeMS, endTimeMS)) {
        result.success = false;
        result.errorMessage = "Time range is not clear";
        return result;
    }

    Effect* eff = el->AddEffect(0, effectType, "", "", startTimeMS, endTimeMS, EFFECT_NOT_SELECTED, false);
    if (!eff) {
        result.success = false;
        result.errorMessage = "Failed to create effect";
        return result;
    }

    result.success = true;
    result.effectId = eff->GetID();
    return result;
}

EffectOperationResult SequenceElementsAdapter::createEffectWithSettings(
    size_t elementIndex,
    size_t layerIndex,
    const std::string& effectType,
    int startTimeMS,
    int endTimeMS,
    const std::map<std::string, std::string>& settings,
    const std::map<std::string, std::string>& palette)
{
    EffectOperationResult result;

    Element* elem = getElementByIndex(elementIndex);
    if (!elem) {
        result.success = false;
        result.errorMessage = "Element not found";
        return result;
    }

    if (layerIndex >= elem->GetEffectLayerCount()) {
        result.success = false;
        result.errorMessage = "Layer index out of range";
        return result;
    }

    EffectLayer* el = elem->GetEffectLayer(layerIndex);
    if (!el) {
        result.success = false;
        result.errorMessage = "Layer not found";
        return result;
    }

    if (!el->GetRangeIsClearMS(startTimeMS, endTimeMS)) {
        result.success = false;
        result.errorMessage = "Time range is not clear";
        return result;
    }

    // Build settings string
    std::string settingsStr;
    for (const auto& [key, value] : settings) {
        if (!settingsStr.empty()) settingsStr += ",";
        std::string escapedValue = value;
        // Escape special characters
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
        settingsStr += key + "=" + escapedValue;
    }

    // Build palette string
    std::string paletteStr;
    for (const auto& [key, value] : palette) {
        if (!paletteStr.empty()) paletteStr += ",";
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
        paletteStr += key + "=" + escapedValue;
    }

    Effect* eff = el->AddEffect(0, effectType, settingsStr, paletteStr, startTimeMS, endTimeMS, EFFECT_NOT_SELECTED, false);
    if (!eff) {
        result.success = false;
        result.errorMessage = "Failed to create effect";
        return result;
    }

    result.success = true;
    result.effectId = eff->GetID();
    return result;
}

// --- IEffectProvider Implementation: Effect Modification - Delete ---

EffectOperationResult SequenceElementsAdapter::deleteEffect(int64_t effectId)
{
    EffectOperationResult result;

    size_t elementIndex = 0;
    size_t layerIndex = 0;
    Effect* eff = findEffectById(effectId, elementIndex, layerIndex);
    if (!eff) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    EffectLayer* el = eff->GetParentEffectLayer();
    if (!el) {
        result.success = false;
        result.errorMessage = "Effect layer not found";
        return result;
    }

    for (int i = 0; i < el->GetEffectCount(); ++i) {
        if (el->GetEffect(i) == eff) {
            el->RemoveEffect(i);
            result.success = true;
            result.effectId = effectId;
            return result;
        }
    }

    result.success = false;
    result.errorMessage = "Effect not found in layer";
    return result;
}

EffectOperationResult SequenceElementsAdapter::deleteEffects(const std::vector<int64_t>& effectIds)
{
    EffectOperationResult result;
    result.success = true;

    for (int64_t id : effectIds) {
        EffectOperationResult r = deleteEffect(id);
        if (!r.success) {
            result.success = false;
            result.errorMessage += r.errorMessage + "; ";
        }
    }

    return result;
}

// --- IEffectProvider Implementation: Effect Modification - Update ---

EffectOperationResult SequenceElementsAdapter::updateEffectTiming(
    int64_t effectId,
    int newStartTimeMS,
    int newEndTimeMS)
{
    EffectOperationResult result;

    if (newStartTimeMS >= newEndTimeMS) {
        result.success = false;
        result.errorMessage = "Invalid time range";
        return result;
    }

    size_t elementIndex = 0;
    size_t layerIndex = 0;
    Effect* eff = findEffectById(effectId, elementIndex, layerIndex);
    if (!eff) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    eff->SetStartTimeMS(newStartTimeMS);
    eff->SetEndTimeMS(newEndTimeMS);
    eff->IncrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult SequenceElementsAdapter::updateEffectSettings(
    int64_t effectId,
    const std::map<std::string, std::string>& settings)
{
    EffectOperationResult result;

    size_t elementIndex = 0;
    size_t layerIndex = 0;
    Effect* eff = findEffectById(effectId, elementIndex, layerIndex);
    if (!eff) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    // Build settings string
    std::string settingsStr;
    for (const auto& [key, value] : settings) {
        if (!settingsStr.empty()) settingsStr += ",";
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
        settingsStr += key + "=" + escapedValue;
    }

    eff->SetSettings(settingsStr, false);
    eff->IncrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult SequenceElementsAdapter::updateEffectSetting(
    int64_t effectId,
    const std::string& key,
    const std::string& value)
{
    EffectOperationResult result;

    size_t elementIndex = 0;
    size_t layerIndex = 0;
    Effect* eff = findEffectById(effectId, elementIndex, layerIndex);
    if (!eff) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    eff->SetSetting(key, value);
    eff->IncrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult SequenceElementsAdapter::updateEffectPalette(
    int64_t effectId,
    const std::map<std::string, std::string>& palette)
{
    EffectOperationResult result;

    size_t elementIndex = 0;
    size_t layerIndex = 0;
    Effect* eff = findEffectById(effectId, elementIndex, layerIndex);
    if (!eff) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    // Build palette string
    std::string paletteStr;
    for (const auto& [key, value] : palette) {
        if (!paletteStr.empty()) paletteStr += ",";
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
        paletteStr += key + "=" + escapedValue;
    }

    eff->SetPalette(paletteStr);
    eff->IncrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult SequenceElementsAdapter::updateEffectType(
    int64_t effectId,
    const std::string& newEffectType)
{
    EffectOperationResult result;

    EffectManager* em = getEffectManager();
    if (!em) {
        result.success = false;
        result.errorMessage = "Effect manager not available";
        return result;
    }

    int newIndex = em->GetEffectIndex(newEffectType);
    if (newIndex == -1) {
        result.success = false;
        result.errorMessage = "Unknown effect type: " + newEffectType;
        return result;
    }

    size_t elementIndex = 0;
    size_t layerIndex = 0;
    Effect* eff = findEffectById(effectId, elementIndex, layerIndex);
    if (!eff) {
        result.success = false;
        result.errorMessage = "Effect not found";
        return result;
    }

    eff->ConvertTo(newIndex);
    eff->IncrementChangeCount();

    result.success = true;
    result.effectId = effectId;
    return result;
}

EffectOperationResult SequenceElementsAdapter::moveEffectToLayer(
    int64_t effectId,
    size_t newLayerIndex)
{
    EffectOperationResult result;
    result.success = false;
    result.errorMessage = "moveEffectToLayer not yet implemented";
    return result;
}

// --- IEffectProvider Implementation: Layer Management ---

size_t SequenceElementsAdapter::addEffectLayer(size_t elementIndex)
{
    Element* elem = getElementByIndex(elementIndex);
    if (!elem) return SIZE_MAX;

    EffectLayer* newLayer = elem->AddEffectLayer();
    if (!newLayer) return SIZE_MAX;

    return elem->GetEffectLayerCount() - 1;
}

EffectOperationResult SequenceElementsAdapter::removeEffectLayer(size_t elementIndex, size_t layerIndex)
{
    EffectOperationResult result;

    Element* elem = getElementByIndex(elementIndex);
    if (!elem) {
        result.success = false;
        result.errorMessage = "Element not found";
        return result;
    }

    if (layerIndex >= elem->GetEffectLayerCount()) {
        result.success = false;
        result.errorMessage = "Layer index out of range";
        return result;
    }

    elem->RemoveEffectLayer(layerIndex);
    result.success = true;
    return result;
}

size_t SequenceElementsAdapter::insertEffectLayer(size_t elementIndex, size_t atIndex)
{
    Element* elem = getElementByIndex(elementIndex);
    if (!elem) return SIZE_MAX;

    EffectLayer* newLayer = elem->InsertEffectLayer(atIndex);
    if (!newLayer) return SIZE_MAX;

    return atIndex;
}

// --- IEffectProvider Implementation: Selection Management ---

bool SequenceElementsAdapter::selectEffect(int64_t effectId, bool addToSelection)
{
    if (!addToSelection) {
        deselectAllEffects();
    }

    size_t elementIndex = 0;
    size_t layerIndex = 0;
    Effect* eff = findEffectById(effectId, elementIndex, layerIndex);
    if (!eff) return false;

    eff->SetSelected(EFFECT_SELECTED);
    return true;
}

bool SequenceElementsAdapter::deselectEffect(int64_t effectId)
{
    size_t elementIndex = 0;
    size_t layerIndex = 0;
    Effect* eff = findEffectById(effectId, elementIndex, layerIndex);
    if (!eff) return false;

    eff->SetSelected(EFFECT_NOT_SELECTED);
    return true;
}

void SequenceElementsAdapter::deselectAllEffects()
{
    SequenceElements* se = getSequenceElements();
    if (se) {
        se->UnSelectAllEffects();
    }
}

std::vector<int64_t> SequenceElementsAdapter::getSelectedEffectIds() const
{
    std::vector<int64_t> result;
    SequenceElements* se = getSequenceElements();
    if (!se) return result;

    for (size_t i = 0; i < se->GetElementCount(); ++i) {
        Element* elem = se->GetElement(i);
        if (!elem) continue;

        for (size_t layer = 0; layer < elem->GetEffectLayerCount(); ++layer) {
            EffectLayer* el = elem->GetEffectLayer(layer);
            if (!el) continue;

            for (int e = 0; e < el->GetEffectCount(); ++e) {
                Effect* eff = el->GetEffect(e);
                if (eff && eff->GetSelected() != EFFECT_NOT_SELECTED) {
                    result.push_back(eff->GetID());
                }
            }
        }
    }

    return result;
}

// --- IEffectProvider Implementation: Undo/Redo Integration ---

void SequenceElementsAdapter::beginUndoGroup(const std::string& description)
{
    // TODO: Integrate with UndoManager when available
}

void SequenceElementsAdapter::endUndoGroup()
{
    // TODO: Integrate with UndoManager when available
}

void SequenceElementsAdapter::cancelUndoGroup()
{
    // TODO: Integrate with UndoManager when available
}

bool SequenceElementsAdapter::canUndo() const
{
    // TODO: Integrate with UndoManager when available
    return false;
}

bool SequenceElementsAdapter::canRedo() const
{
    // TODO: Integrate with UndoManager when available
    return false;
}

bool SequenceElementsAdapter::undo()
{
    // TODO: Integrate with UndoManager when available
    return false;
}

bool SequenceElementsAdapter::redo()
{
    // TODO: Integrate with UndoManager when available
    return false;
}

std::string SequenceElementsAdapter::getUndoDescription() const
{
    // TODO: Integrate with UndoManager when available
    return "";
}

std::string SequenceElementsAdapter::getRedoDescription() const
{
    // TODO: Integrate with UndoManager when available
    return "";
}

// --- IEffectProvider Implementation: Clipboard Operations ---

bool SequenceElementsAdapter::copySelectedEffects()
{
    // TODO: Integrate with clipboard system when available
    return false;
}

bool SequenceElementsAdapter::cutSelectedEffects()
{
    // TODO: Integrate with clipboard system when available
    return false;
}

std::vector<int64_t> SequenceElementsAdapter::pasteEffects(
    size_t elementIndex,
    size_t layerIndex,
    int startTimeMS)
{
    // TODO: Integrate with clipboard system when available
    return {};
}

bool SequenceElementsAdapter::canPaste() const
{
    // TODO: Integrate with clipboard system when available
    return false;
}

} // namespace xlEngine
