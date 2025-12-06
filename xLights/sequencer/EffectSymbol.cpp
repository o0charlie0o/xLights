/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "EffectSymbol.h"
#include "Effect.h"
#include <wx/xml/xml.h>

EffectSymbol::EffectSymbol()
    : _id("")
    , _name("")
    , _effectType("")
    , _effectIndex(-1)
    , _palette("")
{
}

EffectSymbol::EffectSymbol(const std::string& id, const std::string& name)
    : _id(id)
    , _name(name)
    , _effectType("")
    , _effectIndex(-1)
    , _palette("")
{
}

EffectSymbol::~EffectSymbol()
{
}

void EffectSymbol::SetSettingsFromString(const std::string& settings)
{
    _settings.clear();
    // Parse comma-separated key=value pairs
    if (settings.empty()) return;

    size_t pos = 0;
    std::string remaining = settings;
    while (!remaining.empty()) {
        size_t commaPos = remaining.find(',');
        std::string pair;
        if (commaPos == std::string::npos) {
            pair = remaining;
            remaining = "";
        } else {
            pair = remaining.substr(0, commaPos);
            remaining = remaining.substr(commaPos + 1);
        }

        size_t eqPos = pair.find('=');
        if (eqPos != std::string::npos) {
            std::string key = pair.substr(0, eqPos);
            std::string value = pair.substr(eqPos + 1);
            // Unescape special characters
            size_t ampPos;
            while ((ampPos = value.find("&comma;")) != std::string::npos) {
                value.replace(ampPos, 7, ",");
            }
            while ((ampPos = value.find("&amp;")) != std::string::npos) {
                value.replace(ampPos, 5, "&");
            }
            _settings[key] = value;
        }
    }
}

void EffectSymbol::CopyFromEffect(const Effect* effect)
{
    if (effect == nullptr) return;

    _effectType = effect->GetEffectName();
    _effectIndex = effect->GetEffectIndex();
    _settings = effect->GetSettings();
    _palette = effect->GetPaletteAsString();
}

wxXmlNode* EffectSymbol::ToXml() const
{
    wxXmlNode* node = new wxXmlNode(wxXML_ELEMENT_NODE, "Symbol");
    node->AddAttribute("id", _id);
    node->AddAttribute("name", _name);
    node->AddAttribute("effectType", _effectType);
    node->AddAttribute("effectIndex", std::to_string(_effectIndex));

    // Settings as child element
    wxXmlNode* settingsNode = new wxXmlNode(wxXML_ELEMENT_NODE, "Settings");
    settingsNode->AddChild(new wxXmlNode(wxXML_TEXT_NODE, "", GetSettingsAsString()));
    node->AddChild(settingsNode);

    // Palette as child element
    wxXmlNode* paletteNode = new wxXmlNode(wxXML_ELEMENT_NODE, "Palette");
    paletteNode->AddChild(new wxXmlNode(wxXML_TEXT_NODE, "", _palette));
    node->AddChild(paletteNode);

    return node;
}

EffectSymbol* EffectSymbol::FromXml(wxXmlNode* node)
{
    if (node == nullptr || node->GetName() != "Symbol") {
        return nullptr;
    }

    std::string id = node->GetAttribute("id").ToStdString();
    std::string name = node->GetAttribute("name").ToStdString();
    std::string effectType = node->GetAttribute("effectType").ToStdString();
    int effectIndex = wxAtoi(node->GetAttribute("effectIndex", "-1"));

    EffectSymbol* symbol = new EffectSymbol(id, name);
    symbol->SetEffectType(effectType);
    symbol->SetEffectIndex(effectIndex);

    // Parse children
    for (wxXmlNode* child = node->GetChildren(); child != nullptr; child = child->GetNext()) {
        if (child->GetName() == "Settings") {
            wxString content = child->GetNodeContent();
            symbol->SetSettingsFromString(content.ToStdString());
        } else if (child->GetName() == "Palette") {
            wxString content = child->GetNodeContent();
            symbol->SetPalette(content.ToStdString());
        }
    }

    return symbol;
}
