#pragma once

/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include <string>
#include <map>
#include <vector>
#include <memory>
#include <set>

class EffectSymbol;
class Effect;
class wxXmlNode;

// Listener interface for symbol change notifications
class IEffectSymbolListener
{
public:
    virtual ~IEffectSymbolListener() = default;
    virtual void OnSymbolChanged(const std::string& symbolId) = 0;
    virtual void OnSymbolDeleted(const std::string& symbolId) = 0;
    virtual void OnSymbolCreated(const std::string& symbolId) = 0;
    virtual void OnSymbolRenamed(const std::string& symbolId, const std::string& oldName, const std::string& newName) = 0;
};

// Manages all EffectSymbols within a sequence.
// Handles creation, deletion, lookup, and change notification.
class EffectSymbolManager
{
public:
    EffectSymbolManager();
    ~EffectSymbolManager();

    // Clear all symbols (called when sequence is closed)
    void Clear();

    // Symbol Management
    EffectSymbol* CreateSymbol(const std::string& name, const Effect* sourceEffect);
    EffectSymbol* CreateEmptySymbol(const std::string& name, const std::string& effectType, int effectIndex);
    EffectSymbol* GetSymbol(const std::string& id) const;
    EffectSymbol* GetSymbolByName(const std::string& name) const;
    std::vector<EffectSymbol*> GetAllSymbols() const;
    size_t GetSymbolCount() const { return _symbols.size(); }
    bool DeleteSymbol(const std::string& id);
    bool RenameSymbol(const std::string& id, const std::string& newName);
    bool SymbolExists(const std::string& id) const;
    bool SymbolNameExists(const std::string& name) const;
    std::string GetUniqueSymbolName(const std::string& baseName) const;

    // Linked Effect Tracking
    void RegisterLinkedEffect(Effect* effect, const std::string& symbolId);
    void UnregisterLinkedEffect(Effect* effect);
    std::vector<Effect*> GetLinkedEffects(const std::string& symbolId) const;
    size_t GetLinkedEffectCount(const std::string& symbolId) const;

    // Symbol Updates (propagates to all linked effects)
    void UpdateSymbolSettings(const std::string& id, const std::string& settings);
    void UpdateSymbolPalette(const std::string& id, const std::string& palette);
    void NotifySymbolChanged(const std::string& symbolId);

    // Serialization
    void LoadFromXml(wxXmlNode* symbolsNode);
    wxXmlNode* SaveToXml() const;

    // Listeners
    void AddListener(IEffectSymbolListener* listener);
    void RemoveListener(IEffectSymbolListener* listener);

private:
    std::string GenerateUniqueId();

    std::map<std::string, std::unique_ptr<EffectSymbol>> _symbols;  // id -> symbol
    std::multimap<std::string, Effect*> _linkedEffects;             // symbolId -> effects
    std::vector<IEffectSymbolListener*> _listeners;
    int _nextSymbolId;
};
