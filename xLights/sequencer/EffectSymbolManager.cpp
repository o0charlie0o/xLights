/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "EffectSymbolManager.h"
#include "EffectSymbol.h"
#include "Effect.h"
#include <wx/xml/xml.h>
#include <algorithm>

EffectSymbolManager::EffectSymbolManager()
    : _nextSymbolId(1)
{
}

EffectSymbolManager::~EffectSymbolManager()
{
    Clear();
}

void EffectSymbolManager::Clear()
{
    _linkedEffects.clear();
    _symbols.clear();
    _nextSymbolId = 1;
}

std::string EffectSymbolManager::GenerateUniqueId()
{
    std::string id;
    do {
        id = "sym_" + std::to_string(_nextSymbolId++);
    } while (_symbols.find(id) != _symbols.end());
    return id;
}

EffectSymbol* EffectSymbolManager::CreateSymbol(const std::string& name, const Effect* sourceEffect)
{
    if (sourceEffect == nullptr) return nullptr;

    // Ensure unique name
    std::string uniqueName = name;
    if (SymbolNameExists(name)) {
        uniqueName = GetUniqueSymbolName(name);
    }

    std::string id = GenerateUniqueId();
    auto symbol = std::make_unique<EffectSymbol>(id, uniqueName);
    symbol->CopyFromEffect(sourceEffect);

    EffectSymbol* ptr = symbol.get();
    _symbols[id] = std::move(symbol);

    // Notify listeners
    for (auto* listener : _listeners) {
        listener->OnSymbolCreated(id);
    }

    return ptr;
}

EffectSymbol* EffectSymbolManager::CreateEmptySymbol(const std::string& name, const std::string& effectType, int effectIndex)
{
    // Ensure unique name
    std::string uniqueName = name;
    if (SymbolNameExists(name)) {
        uniqueName = GetUniqueSymbolName(name);
    }

    std::string id = GenerateUniqueId();
    auto symbol = std::make_unique<EffectSymbol>(id, uniqueName);
    symbol->SetEffectType(effectType);
    symbol->SetEffectIndex(effectIndex);

    EffectSymbol* ptr = symbol.get();
    _symbols[id] = std::move(symbol);

    // Notify listeners
    for (auto* listener : _listeners) {
        listener->OnSymbolCreated(id);
    }

    return ptr;
}

EffectSymbol* EffectSymbolManager::GetSymbol(const std::string& id) const
{
    auto it = _symbols.find(id);
    if (it != _symbols.end()) {
        return it->second.get();
    }
    return nullptr;
}

EffectSymbol* EffectSymbolManager::GetSymbolByName(const std::string& name) const
{
    for (const auto& pair : _symbols) {
        if (pair.second->GetName() == name) {
            return pair.second.get();
        }
    }
    return nullptr;
}

std::vector<EffectSymbol*> EffectSymbolManager::GetAllSymbols() const
{
    std::vector<EffectSymbol*> result;
    result.reserve(_symbols.size());
    for (const auto& pair : _symbols) {
        result.push_back(pair.second.get());
    }
    return result;
}

bool EffectSymbolManager::DeleteSymbol(const std::string& id)
{
    auto it = _symbols.find(id);
    if (it == _symbols.end()) {
        return false;
    }

    // Unlink all effects linked to this symbol
    auto range = _linkedEffects.equal_range(id);
    std::vector<Effect*> effectsToUnlink;
    for (auto iter = range.first; iter != range.second; ++iter) {
        effectsToUnlink.push_back(iter->second);
    }
    for (Effect* effect : effectsToUnlink) {
        effect->UnlinkFromSymbol();
    }

    // Remove from linked effects map
    _linkedEffects.erase(id);

    // Notify listeners before deletion
    for (auto* listener : _listeners) {
        listener->OnSymbolDeleted(id);
    }

    // Remove the symbol
    _symbols.erase(it);
    return true;
}

bool EffectSymbolManager::RenameSymbol(const std::string& id, const std::string& newName)
{
    auto it = _symbols.find(id);
    if (it == _symbols.end()) {
        return false;
    }

    // Check if new name already exists (for a different symbol)
    EffectSymbol* existing = GetSymbolByName(newName);
    if (existing != nullptr && existing->GetId() != id) {
        return false; // Name conflict
    }

    std::string oldName = it->second->GetName();
    it->second->SetName(newName);

    // Notify listeners
    for (auto* listener : _listeners) {
        listener->OnSymbolRenamed(id, oldName, newName);
    }

    return true;
}

bool EffectSymbolManager::SymbolExists(const std::string& id) const
{
    return _symbols.find(id) != _symbols.end();
}

bool EffectSymbolManager::SymbolNameExists(const std::string& name) const
{
    return GetSymbolByName(name) != nullptr;
}

std::string EffectSymbolManager::GetUniqueSymbolName(const std::string& baseName) const
{
    if (!SymbolNameExists(baseName)) {
        return baseName;
    }

    int counter = 2;
    std::string candidate;
    do {
        candidate = baseName + " " + std::to_string(counter++);
    } while (SymbolNameExists(candidate));

    return candidate;
}

void EffectSymbolManager::RegisterLinkedEffect(Effect* effect, const std::string& symbolId)
{
    if (effect == nullptr || !SymbolExists(symbolId)) return;

    // Remove any existing registration for this effect
    UnregisterLinkedEffect(effect);

    // Add new registration
    _linkedEffects.insert({symbolId, effect});
}

void EffectSymbolManager::UnregisterLinkedEffect(Effect* effect)
{
    if (effect == nullptr) return;

    // Find and remove this effect from the multimap
    for (auto it = _linkedEffects.begin(); it != _linkedEffects.end(); ) {
        if (it->second == effect) {
            it = _linkedEffects.erase(it);
        } else {
            ++it;
        }
    }
}

std::vector<Effect*> EffectSymbolManager::GetLinkedEffects(const std::string& symbolId) const
{
    std::vector<Effect*> result;
    auto range = _linkedEffects.equal_range(symbolId);
    for (auto it = range.first; it != range.second; ++it) {
        result.push_back(it->second);
    }
    return result;
}

size_t EffectSymbolManager::GetLinkedEffectCount(const std::string& symbolId) const
{
    return _linkedEffects.count(symbolId);
}

void EffectSymbolManager::UpdateSymbolSettings(const std::string& id, const std::string& settings)
{
    EffectSymbol* symbol = GetSymbol(id);
    if (symbol == nullptr) return;

    symbol->SetSettingsFromString(settings);
    NotifySymbolChanged(id);
}

void EffectSymbolManager::UpdateSymbolPalette(const std::string& id, const std::string& palette)
{
    EffectSymbol* symbol = GetSymbol(id);
    if (symbol == nullptr) return;

    symbol->SetPalette(palette);
    NotifySymbolChanged(id);
}

void EffectSymbolManager::NotifySymbolChanged(const std::string& symbolId)
{
    // Update all linked effects
    EffectSymbol* symbol = GetSymbol(symbolId);
    if (symbol == nullptr) return;

    auto linkedEffects = GetLinkedEffects(symbolId);
    for (Effect* effect : linkedEffects) {
        // Update effect settings from symbol
        effect->SetSettings(symbol->GetSettingsAsString(), false);
        effect->SetPalette(symbol->GetPalette());
        effect->IncrementChangeCount();
    }

    // Notify listeners
    for (auto* listener : _listeners) {
        listener->OnSymbolChanged(symbolId);
    }
}

void EffectSymbolManager::LoadFromXml(wxXmlNode* symbolsNode)
{
    if (symbolsNode == nullptr || symbolsNode->GetName() != "EffectSymbols") {
        return;
    }

    Clear();

    // Track highest ID for next symbol generation
    int maxId = 0;

    for (wxXmlNode* child = symbolsNode->GetChildren(); child != nullptr; child = child->GetNext()) {
        if (child->GetName() == "Symbol") {
            EffectSymbol* symbol = EffectSymbol::FromXml(child);
            if (symbol != nullptr) {
                std::string id = symbol->GetId();
                _symbols[id] = std::unique_ptr<EffectSymbol>(symbol);

                // Track max ID
                if (id.substr(0, 4) == "sym_") {
                    try {
                        int num = std::stoi(id.substr(4));
                        if (num >= maxId) {
                            maxId = num + 1;
                        }
                    } catch (...) {
                        // Ignore parse errors
                    }
                }
            }
        }
    }

    _nextSymbolId = maxId > 0 ? maxId : 1;
}

wxXmlNode* EffectSymbolManager::SaveToXml() const
{
    wxXmlNode* node = new wxXmlNode(wxXML_ELEMENT_NODE, "EffectSymbols");

    for (const auto& pair : _symbols) {
        wxXmlNode* symbolNode = pair.second->ToXml();
        node->AddChild(symbolNode);
    }

    return node;
}

void EffectSymbolManager::AddListener(IEffectSymbolListener* listener)
{
    if (listener != nullptr) {
        _listeners.push_back(listener);
    }
}

void EffectSymbolManager::RemoveListener(IEffectSymbolListener* listener)
{
    _listeners.erase(
        std::remove(_listeners.begin(), _listeners.end(), listener),
        _listeners.end()
    );
}
