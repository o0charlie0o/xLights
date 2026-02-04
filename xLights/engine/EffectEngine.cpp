/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "EffectEngine.h"

#include "../xLightsMain.h"
#include "../effects/EffectManager.h"
#include "../effects/RenderableEffect.h"
#include "../effects/EffectPanelUtils.h"
#include "../sequencer/SequenceElements.h"
#include "../sequencer/Element.h"
#include "../sequencer/Effect.h"
#include "../sequencer/EffectLayer.h"

#include <wx/tokenzr.h>
#include <algorithm>

namespace xlEngine {

// ---------------------------------------------------------------------------
// Construction / Destruction
// ---------------------------------------------------------------------------

EffectEngine::EffectEngine(xLightsFrame* frame)
    : _frame(frame)
{
}

EffectEngine::~EffectEngine()
{
}

// ---------------------------------------------------------------------------
// Listener management
// ---------------------------------------------------------------------------

void EffectEngine::addListener(EffectEngineListener* listener)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.push_back(listener);
}

void EffectEngine::removeListener(EffectEngineListener* listener)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.erase(
        std::remove(_listeners.begin(), _listeners.end(), listener),
        _listeners.end());
}

// ---------------------------------------------------------------------------
// Internal accessors
// ---------------------------------------------------------------------------

EffectManager* EffectEngine::getEffectManager() const
{
    if (!_frame) return nullptr;
    return &_frame->GetEffectManager();
}

SequenceElements* EffectEngine::getSequenceElements() const
{
    if (!_frame) return nullptr;
    return &_frame->GetSequenceElements();
}

// ---------------------------------------------------------------------------
// Effect type enumeration
// ---------------------------------------------------------------------------

std::vector<EffectTypeInfo> EffectEngine::getEffectTypes() const
{
    std::lock_guard<std::mutex> lock(_engineMutex);
    std::vector<EffectTypeInfo> result;

    EffectManager* em = getEffectManager();
    if (!em) return result;

    for (int i = 0; i < (int)em->size(); ++i) {
        RenderableEffect* re = em->GetEffect(i);
        if (!re) continue;

        EffectTypeInfo info;
        info.id = re->GetId();
        info.name = re->Name();
        info.tooltip = re->ToolTip();
        info.canBeRandom = re->CanBeRandom();
        info.canRenderPartialTime = re->CanRenderPartialTimeInterval();
        info.maxColorCount = re->GetColorSupportedCount();
        info.appropriateOnNodes = re->AppropriateOnNodes();
        result.push_back(info);
    }

    return result;
}

bool EffectEngine::getEffectTypeInfo(const std::string& effectType, EffectTypeInfo& outInfo) const
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    EffectManager* em = getEffectManager();
    if (!em) return false;

    RenderableEffect* re = em->GetEffect(effectType);
    if (!re) return false;

    outInfo.id = re->GetId();
    outInfo.name = re->Name();
    outInfo.tooltip = re->ToolTip();
    outInfo.canBeRandom = re->CanBeRandom();
    outInfo.canRenderPartialTime = re->CanRenderPartialTimeInterval();
    outInfo.maxColorCount = re->GetColorSupportedCount();
    outInfo.appropriateOnNodes = re->AppropriateOnNodes();
    return true;
}

// ---------------------------------------------------------------------------
// Parameter definitions
//
// This builds parameter metadata from the known naming conventions used in
// xLights effect panels and SettingsMap keys. The naming convention is:
//
//   Control prefix     SettingsMap key prefix    ParameterType
//   ----------------   ----------------------   -------------
//   ID_SLIDER_         E_SLIDER_                Int (or Float with F1/F2 suffix)
//   ID_CHECKBOX_       E_CHECKBOX_              Bool
//   ID_CHOICE_         E_CHOICE_                Choice
//   ID_TEXTCTRL_       E_TEXTCTRL_              String
//   ID_FILEPICKER_     E_FILEPICKER_            File
//   ID_VALUECURVE_     E_VALUECURVE_            ValueCurve
//   ID_FONTPICKER_     E_FONTPICKER_            Font
//
// In the transition period, we build defaults from the effect type name.
// In the future, effects can provide their own parameter definitions
// directly, eliminating the need to parse wxSmith panels.
// ---------------------------------------------------------------------------

std::vector<ParameterDefinition> EffectEngine::getEffectParameters(const std::string& effectType) const
{
    std::lock_guard<std::mutex> lock(_engineMutex);
    return buildDefaultParameters(effectType);
}

std::vector<ParameterDefinition> EffectEngine::buildDefaultParameters(const std::string& effectType) const
{
    std::vector<ParameterDefinition> params;

    EffectManager* em = getEffectManager();
    if (!em) return params;

    RenderableEffect* re = em->GetEffect(effectType);
    if (!re) return params;

    // Find an existing effect of this type to extract its current settings as
    // a representative sample of what keys are used. If no effect of this type
    // exists in the sequence, we create a temporary one with default settings.
    //
    // For the transition period, we scan the SettingsMap keys for naming
    // convention patterns. This gives us reasonable parameter metadata without
    // having to parse wxSmith XML at runtime.

    SequenceElements* se = getSequenceElements();
    SettingsMap sampleSettings;
    bool foundSample = false;

    if (se) {
        for (size_t i = 0; i < se->GetElementCount(); ++i) {
            Element* elem = se->GetElement(i);
            if (!elem) continue;
            for (size_t layer = 0; layer < elem->GetEffectLayerCount(); ++layer) {
                EffectLayer* el = elem->GetEffectLayer(layer);
                if (!el) continue;
                for (int e = 0; e < el->GetEffectCount(); ++e) {
                    Effect* eff = el->GetEffect(e);
                    if (eff && eff->GetEffectName() == effectType) {
                        const SettingsMap& sm = eff->GetSettings();
                        for (auto it = sm.begin(); it != sm.end(); ++it) {
                            sampleSettings[it->first] = it->second;
                        }
                        // Only consider this a valid sample if we got actual settings
                        if (!sampleSettings.empty()) {
                            foundSample = true;
                        }
                        break;
                    }
                }
                if (foundSample) break;
            }
            if (foundSample) break;
        }
    }

    // If no sample settings found from existing effects, get defaults from the effect panel
    if (sampleSettings.empty() && _frame) {
        xlEffectPanel* panel = re->GetPanel(_frame);
        if (panel) {
            // Set controls to defaults
            re->SetDefaultParameters();

            // Extract default settings string from the panel
            wxString defaultsStr = re->GetEffectString();
            if (!defaultsStr.empty()) {
                // Parse the comma-separated key=value pairs
                wxStringTokenizer tokenizer(defaultsStr, ",");
                while (tokenizer.HasMoreTokens()) {
                    wxString token = tokenizer.GetNextToken();
                    int eqPos = token.Find('=');
                    if (eqPos != wxNOT_FOUND) {
                        wxString key = token.Left(eqPos);
                        wxString value = token.Mid(eqPos + 1);
                        // Unescape any special characters
                        value.Replace("&comma;", ",");
                        value.Replace("&amp;", "&");
                        sampleSettings[key.ToStdString()] = value.ToStdString();
                    }
                }
            }
        }
    }

    // Build parameters from the settings keys using naming conventions.
    // This handles the common patterns used across all 60+ effects.
    auto addParam = [&](const std::string& key, const std::string& value) {
        ParameterDefinition pd;
        pd.key = key;
        pd.group = "General";
        pd.sortOrder = (int)params.size();
        pd.lockable = true;

        // Extract the parameter name from the key for the display label.
        // Keys follow the pattern: E_TYPE_EffectName_ParamName
        // We want just the ParamName part, with underscores replaced by spaces.
        std::string paramLabel;
        size_t lastUnderscore = key.rfind('_');
        if (lastUnderscore != std::string::npos && lastUnderscore > 0) {
            // Find the effect name boundary (second underscore from the left for E_ prefix)
            size_t firstUnderscore = key.find('_');
            if (firstUnderscore != std::string::npos) {
                size_t secondUnderscore = key.find('_', firstUnderscore + 1);
                if (secondUnderscore != std::string::npos) {
                    paramLabel = key.substr(secondUnderscore + 1);
                    // Replace underscores with spaces for display
                    for (auto& c : paramLabel) {
                        if (c == '_') c = ' ';
                    }
                }
            }
        }
        if (paramLabel.empty()) {
            paramLabel = key;
        }
        pd.displayLabel = paramLabel;

        // Determine type from key prefix
        if (key.find("SLIDER_") != std::string::npos) {
            pd.type = ParameterType::Int;
            pd.minValue = 0;
            pd.maxValue = 100;
            pd.defaultValue = 0;
            pd.supportsValueCurve = true;

            // Try to parse the current value as the default (safely)
            if (!value.empty()) {
                // Check if value looks like a number before parsing
                bool isNumeric = true;
                bool hasDigit = false;
                bool hasDot = false;
                for (size_t i = 0; i < value.size(); ++i) {
                    char c = value[i];
                    if (c == '-' || c == '+') {
                        if (i != 0) { isNumeric = false; break; }
                    } else if (c == '.') {
                        if (hasDot) { isNumeric = false; break; }
                        hasDot = true;
                    } else if (c >= '0' && c <= '9') {
                        hasDigit = true;
                    } else {
                        isNumeric = false;
                        break;
                    }
                }
                if (isNumeric && hasDigit) {
                    try {
                        pd.defaultValue = std::stod(value);
                    } catch (const std::exception&) {
                        // Keep default of 0
                    }
                }
            }

            // Build the value curve key from the slider key
            std::string vcKey = "E_VALUECURVE_" + key.substr(key.find("SLIDER_") + 7);
            pd.valueCurveKey = vcKey;

            // Check if a value curve exists in the sample settings to confirm VC support
            if (sampleSettings.find(vcKey) != sampleSettings.end() ||
                sampleSettings.find("E_VALUECURVE_" + key.substr(key.find("SLIDER_") + 7)) != sampleSettings.end()) {
                pd.supportsValueCurve = true;
            }

            // Note: Min/max/divisor values are defined per-effect in header
            // constants (e.g. BARCOUNT_MIN, BARCOUNT_MAX). These are not
            // accessible generically at runtime through the current API.
            // For now we provide standard ranges. In Phase 5, effects will
            // register their own ParameterDefinitions with accurate ranges.
        }
        else if (key.find("CHECKBOX_") != std::string::npos) {
            pd.type = ParameterType::Bool;
            pd.defaultValue = (value == "1") ? 1.0 : 0.0;
            pd.supportsValueCurve = false;
        }
        else if (key.find("CHOICE_") != std::string::npos) {
            pd.type = ParameterType::Choice;
            pd.defaultString = value;
            pd.supportsValueCurve = false;
            // Choices are populated per-effect; we store the current value
            // as the only known choice. Full choice lists require panel metadata.
        }
        else if (key.find("TEXTCTRL_") != std::string::npos) {
            pd.type = ParameterType::String;
            pd.defaultString = value;
            pd.supportsValueCurve = false;
        }
        else if (key.find("FILEPICKER_") != std::string::npos) {
            pd.type = ParameterType::File;
            pd.defaultString = value;
            pd.supportsValueCurve = false;
        }
        else if (key.find("FONTPICKER_") != std::string::npos) {
            pd.type = ParameterType::Font;
            pd.defaultString = value;
            pd.supportsValueCurve = false;
        }
        else if (key.find("VALUECURVE_") != std::string::npos) {
            pd.type = ParameterType::ValueCurve;
            pd.defaultString = value;
            pd.supportsValueCurve = true;
        }
        else if (key.find("COLOURPICKER_") != std::string::npos ||
                 key.find("COLORPICKER_") != std::string::npos) {
            pd.type = ParameterType::Color;
            pd.defaultString = value;
            pd.supportsValueCurve = false;
        }
        else {
            pd.type = ParameterType::String;
            pd.defaultString = value;
            pd.supportsValueCurve = false;
        }

        params.push_back(pd);
    };

    // Process all keys from the sample settings
    for (auto it = sampleSettings.begin(); it != sampleSettings.end(); ++it) {
        const std::string& key = it->first;

        // Skip buffer/transition settings - those are managed separately
        if (key.size() > 2 && (key[0] == 'B' || key[0] == 'T') && key[1] == '_') {
            continue;
        }

        // Skip value curve entries (they are metadata for slider params)
        if (key.find("VALUECURVE_") != std::string::npos) {
            continue;
        }

        addParam(key, it->second);
    }

    return params;
}

// ---------------------------------------------------------------------------
// Effect CRUD
// ---------------------------------------------------------------------------

int EffectEngine::createEffect(const std::string& modelName, int layer,
                               const std::string& effectType,
                               int startTimeMS, int endTimeMS)
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    SequenceElements* se = getSequenceElements();
    if (!se) return -1;

    Element* elem = se->GetElement(modelName);
    if (!elem) return -1;

    if (layer < 0 || layer >= (int)elem->GetEffectLayerCount()) return -1;

    EffectLayer* el = elem->GetEffectLayer(layer);
    if (!el) return -1;

    // Check that the time range is clear
    if (!el->GetRangeIsClearMS(startTimeMS, endTimeMS)) return -1;

    Effect* eff = el->AddEffect(0, effectType, "", "", startTimeMS, endTimeMS, EFFECT_NOT_SELECTED, false);
    if (!eff) return -1;

    int id = eff->GetID();
    notifyEffectCreated(id, modelName, layer);
    return id;
}

bool EffectEngine::deleteEffect(int effectId)
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    std::string modelName;
    int layerIndex = -1;
    Effect* eff = findEffectById(effectId, modelName, layerIndex);
    if (!eff) return false;

    EffectLayer* el = eff->GetParentEffectLayer();
    if (!el) return false;

    // Find the index of this effect in the layer
    for (int i = 0; i < el->GetEffectCount(); ++i) {
        if (el->GetEffect(i) == eff) {
            el->RemoveEffect(i);
            notifyEffectDeleted(effectId, modelName, layerIndex);
            return true;
        }
    }

    return false;
}

bool EffectEngine::getEffect(int effectId, EffectInfo& outInfo) const
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    std::string modelName;
    int layerIndex = -1;
    Effect* eff = findEffectById(effectId, modelName, layerIndex);
    if (!eff) return false;

    outInfo = buildEffectInfo(eff, modelName, layerIndex);
    return true;
}

// ---------------------------------------------------------------------------
// Effect parameter access
// ---------------------------------------------------------------------------

bool EffectEngine::setEffectParameter(int effectId, const std::string& key, const std::string& value)
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    std::string modelName;
    int layerIndex = -1;
    Effect* eff = findEffectById(effectId, modelName, layerIndex);
    if (!eff) return false;

    bool changed = eff->SetSetting(key, value);
    if (changed) {
        eff->IncrementChangeCount();
        notifyEffectSettingChanged(effectId, key, value);
    }
    return true;
}

std::string EffectEngine::getEffectParameter(int effectId, const std::string& key) const
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    std::string modelName;
    int layerIndex = -1;
    Effect* eff = findEffectById(effectId, modelName, layerIndex);
    if (!eff) return "";

    return eff->GetSetting(key);
}

bool EffectEngine::setEffectSettings(int effectId, const std::string& settings)
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    std::string modelName;
    int layerIndex = -1;
    Effect* eff = findEffectById(effectId, modelName, layerIndex);
    if (!eff) return false;

    eff->SetSettings(settings, false);
    eff->IncrementChangeCount();
    notifyEffectSettingChanged(effectId, "", "");
    return true;
}

std::string EffectEngine::getEffectSettings(int effectId) const
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    std::string modelName;
    int layerIndex = -1;
    Effect* eff = findEffectById(effectId, modelName, layerIndex);
    if (!eff) return "";

    return eff->GetSettingsAsString();
}

// ---------------------------------------------------------------------------
// Effect palette access
// ---------------------------------------------------------------------------

bool EffectEngine::setEffectPalette(int effectId, const std::string& palette)
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    std::string modelName;
    int layerIndex = -1;
    Effect* eff = findEffectById(effectId, modelName, layerIndex);
    if (!eff) return false;

    eff->SetPalette(palette);
    eff->IncrementChangeCount();
    notifyEffectPaletteChanged(effectId, modelName, layerIndex);
    return true;
}

std::string EffectEngine::getEffectPalette(int effectId) const
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    std::string modelName;
    int layerIndex = -1;
    Effect* eff = findEffectById(effectId, modelName, layerIndex);
    if (!eff) return "";

    return eff->GetPaletteAsString();
}

// ---------------------------------------------------------------------------
// Effect positioning
// ---------------------------------------------------------------------------

bool EffectEngine::moveEffect(int effectId, int newStartTimeMS, int newEndTimeMS)
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    if (newStartTimeMS >= newEndTimeMS) return false;

    std::string modelName;
    int layerIndex = -1;
    Effect* eff = findEffectById(effectId, modelName, layerIndex);
    if (!eff) return false;

    eff->SetStartTimeMS(newStartTimeMS);
    eff->SetEndTimeMS(newEndTimeMS);
    eff->IncrementChangeCount();
    notifyEffectMoved(effectId, modelName, layerIndex);
    return true;
}

// ---------------------------------------------------------------------------
// Effect queries
// ---------------------------------------------------------------------------

std::vector<EffectInfo> EffectEngine::getEffectsForModel(const std::string& modelName) const
{
    std::lock_guard<std::mutex> lock(_engineMutex);
    std::vector<EffectInfo> result;

    SequenceElements* se = getSequenceElements();
    if (!se) return result;

    Element* elem = se->GetElement(modelName);
    if (!elem) return result;

    for (size_t layer = 0; layer < elem->GetEffectLayerCount(); ++layer) {
        EffectLayer* el = elem->GetEffectLayer(layer);
        if (!el) continue;

        for (int e = 0; e < el->GetEffectCount(); ++e) {
            Effect* eff = el->GetEffect(e);
            if (eff) {
                result.push_back(buildEffectInfo(eff, modelName, (int)layer));
            }
        }
    }

    return result;
}

std::vector<EffectInfo> EffectEngine::getEffectsAtTime(const std::string& modelName, int timeMS) const
{
    std::lock_guard<std::mutex> lock(_engineMutex);
    std::vector<EffectInfo> result;

    SequenceElements* se = getSequenceElements();
    if (!se) return result;

    Element* elem = se->GetElement(modelName);
    if (!elem) return result;

    for (size_t layer = 0; layer < elem->GetEffectLayerCount(); ++layer) {
        EffectLayer* el = elem->GetEffectLayer(layer);
        if (!el) continue;

        Effect* eff = el->GetEffectAtTime(timeMS);
        if (eff) {
            result.push_back(buildEffectInfo(eff, modelName, (int)layer));
        }
    }

    return result;
}

std::vector<EffectInfo> EffectEngine::getEffectsForLayer(const std::string& modelName, int layer) const
{
    std::lock_guard<std::mutex> lock(_engineMutex);
    std::vector<EffectInfo> result;

    SequenceElements* se = getSequenceElements();
    if (!se) return result;

    Element* elem = se->GetElement(modelName);
    if (!elem) return result;

    if (layer < 0 || layer >= (int)elem->GetEffectLayerCount()) return result;

    EffectLayer* el = elem->GetEffectLayer(layer);
    if (!el) return result;

    for (int e = 0; e < el->GetEffectCount(); ++e) {
        Effect* eff = el->GetEffect(e);
        if (eff) {
            result.push_back(buildEffectInfo(eff, modelName, layer));
        }
    }

    return result;
}

int EffectEngine::getLayerCount(const std::string& modelName) const
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    SequenceElements* se = getSequenceElements();
    if (!se) return 0;

    Element* elem = se->GetElement(modelName);
    if (!elem) return 0;

    return (int)elem->GetEffectLayerCount();
}

// ---------------------------------------------------------------------------
// Layer management
// ---------------------------------------------------------------------------

int EffectEngine::addLayer(const std::string& modelName)
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    SequenceElements* se = getSequenceElements();
    if (!se) return -1;

    Element* elem = se->GetElement(modelName);
    if (!elem) return -1;

    EffectLayer* newLayer = elem->AddEffectLayer();
    if (!newLayer) return -1;

    return (int)elem->GetEffectLayerCount() - 1;
}

bool EffectEngine::removeLayer(const std::string& modelName, int layer)
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    SequenceElements* se = getSequenceElements();
    if (!se) return false;

    Element* elem = se->GetElement(modelName);
    if (!elem) return false;

    if (layer < 0 || layer >= (int)elem->GetEffectLayerCount()) return false;

    elem->RemoveEffectLayer(layer);
    return true;
}

// ---------------------------------------------------------------------------
// Selection
// ---------------------------------------------------------------------------

bool EffectEngine::selectEffect(int effectId)
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    std::string modelName;
    int layerIndex = -1;
    Effect* eff = findEffectById(effectId, modelName, layerIndex);
    if (!eff) return false;

    eff->SetSelected(EFFECT_SELECTED);
    return true;
}

void EffectEngine::deselectAllEffects()
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    SequenceElements* se = getSequenceElements();
    if (!se) return;

    se->UnSelectAllEffects();
}

std::vector<int> EffectEngine::getSelectedEffectIds() const
{
    std::lock_guard<std::mutex> lock(_engineMutex);
    std::vector<int> result;

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

// ---------------------------------------------------------------------------
// Effect type conversion
// ---------------------------------------------------------------------------

bool EffectEngine::convertEffectType(int effectId, const std::string& newEffectType)
{
    std::lock_guard<std::mutex> lock(_engineMutex);

    EffectManager* em = getEffectManager();
    if (!em) return false;

    int newIndex = em->GetEffectIndex(newEffectType);
    if (newIndex == -1) return false;

    std::string modelName;
    int layerIndex = -1;
    Effect* eff = findEffectById(effectId, modelName, layerIndex);
    if (!eff) return false;

    eff->ConvertTo(newIndex);
    eff->IncrementChangeCount();

    {
        EffectEvent event;
        event.type = EffectEventType::EffectTypeChanged;
        event.effectId = effectId;
        event.modelName = modelName;
        event.layerIndex = layerIndex;

        std::lock_guard<std::mutex> llock(_listenerMutex);
        for (auto* listener : _listeners) {
            listener->onEffectTypeChanged(event);
        }
    }

    return true;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

Effect* EffectEngine::findEffectById(int effectId, std::string& modelName, int& layerIndex) const
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
                if (eff && eff->GetID() == effectId) {
                    modelName = elem->GetName();
                    layerIndex = (int)layer;
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
                            if (eff && eff->GetID() == effectId) {
                                modelName = sme->GetFullName();
                                layerIndex = (int)layer;
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
                            if (eff && eff->GetID() == effectId) {
                                modelName = strand->GetFullName();
                                layerIndex = (int)layer;
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

EffectInfo EffectEngine::buildEffectInfo(Effect* effect, const std::string& modelName, int layerIndex) const
{
    EffectInfo info;
    if (!effect) return info;

    info.id = effect->GetID();
    info.effectType = effect->GetEffectName();
    info.effectIndex = effect->GetEffectIndex();
    info.modelName = modelName;
    info.layerIndex = layerIndex;
    info.startTimeMS = effect->GetStartTimeMS();
    info.endTimeMS = effect->GetEndTimeMS();
    info.isSelected = (effect->GetSelected() != EFFECT_NOT_SELECTED);
    info.isProtected = effect->GetProtected();
    info.isLocked = effect->IsLocked();
    info.isRenderDisabled = effect->IsRenderDisabled();

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

// ---------------------------------------------------------------------------
// Notification helpers
// ---------------------------------------------------------------------------

void EffectEngine::notifyEffectCreated(int effectId, const std::string& modelName, int layerIndex)
{
    EffectEvent event;
    event.type = EffectEventType::EffectCreated;
    event.effectId = effectId;
    event.modelName = modelName;
    event.layerIndex = layerIndex;

    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onEffectCreated(event);
    }
}

void EffectEngine::notifyEffectDeleted(int effectId, const std::string& modelName, int layerIndex)
{
    EffectEvent event;
    event.type = EffectEventType::EffectDeleted;
    event.effectId = effectId;
    event.modelName = modelName;
    event.layerIndex = layerIndex;

    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onEffectDeleted(event);
    }
}

void EffectEngine::notifyEffectMoved(int effectId, const std::string& modelName, int layerIndex)
{
    EffectEvent event;
    event.type = EffectEventType::EffectMoved;
    event.effectId = effectId;
    event.modelName = modelName;
    event.layerIndex = layerIndex;

    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onEffectMoved(event);
    }
}

void EffectEngine::notifyEffectSettingChanged(int effectId, const std::string& key, const std::string& value)
{
    EffectEvent event;
    event.type = EffectEventType::EffectSettingChanged;
    event.effectId = effectId;
    event.paramKey = key;
    event.paramValue = value;

    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onEffectSettingChanged(event);
    }
}

void EffectEngine::notifyEffectPaletteChanged(int effectId, const std::string& modelName, int layerIndex)
{
    EffectEvent event;
    event.type = EffectEventType::EffectPaletteChanged;
    event.effectId = effectId;
    event.modelName = modelName;
    event.layerIndex = layerIndex;

    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onEffectPaletteChanged(event);
    }
}

void EffectEngine::notifyError(const std::string& message)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onError(message);
    }
}

} // namespace xlEngine
