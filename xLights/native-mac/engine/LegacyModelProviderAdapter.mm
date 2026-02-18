/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 **************************************************************/

#include "LegacyModelProviderAdapter.h"

#include "../../xLightsMain.h"
#include "../../models/Model.h"
#include "../../models/ModelGroup.h"
#include "../../models/ModelManager.h"

#include <wx/xml/xml.h>

namespace xlEngine {

LegacyModelProviderAdapter::LegacyModelProviderAdapter(xLightsFrame* frame)
    : _frame(frame)
{
}

size_t LegacyModelProviderAdapter::getModelCount() const {
    if (!_frame) return 0;
    return _frame->AllModels.size();
}

std::string LegacyModelProviderAdapter::getModelName(size_t index) const {
    if (!_frame) return "";
    size_t i = 0;
    for (auto it = _frame->AllModels.begin(); it != _frame->AllModels.end(); ++it, ++i) {
        if (i == index) return it->second->GetName();
    }
    return "";
}

std::vector<std::string> LegacyModelProviderAdapter::getModelNames() const {
    std::vector<std::string> names;
    if (!_frame) return names;

    for (auto it = _frame->AllModels.begin(); it != _frame->AllModels.end(); ++it) {
        if (it->second) {
            names.push_back(it->second->GetName());
        }
    }
    return names;
}

std::vector<std::string> LegacyModelProviderAdapter::getGroupNames() const {
    std::vector<std::string> groups;
    if (!_frame) return groups;

    for (auto it = _frame->AllModels.begin(); it != _frame->AllModels.end(); ++it) {
        if (it->second && it->second->GetDisplayAs() == "ModelGroup") {
            groups.push_back(it->second->GetName());
        }
    }
    return groups;
}

Model* LegacyModelProviderAdapter::getModel(const std::string& name) {
    if (!_frame) return nullptr;
    return _frame->AllModels[name];
}

const Model* LegacyModelProviderAdapter::getModel(const std::string& name) const {
    if (!_frame) return nullptr;
    return _frame->AllModels[name];
}

std::vector<std::string> LegacyModelProviderAdapter::getSubmodels(const std::string& modelName) const {
    std::vector<std::string> subs;
    if (!_frame) return subs;

    Model* m = _frame->AllModels[modelName];
    if (!m) return subs;

    for (int i = 0; i < m->GetNumSubModels(); i++) {
        Model* sm = m->GetSubModel(i);
        if (sm) {
            subs.push_back(sm->GetName());
        }
    }
    return subs;
}

std::map<std::string, std::string> LegacyModelProviderAdapter::getModelAttributes(const std::string& name) const {
    std::map<std::string, std::string> attrs;
    if (!_frame) return attrs;

    Model* m = _frame->AllModels[name];
    if (!m || !m->GetModelXml()) return attrs;

    // Extract all XML attributes from the model node
    wxXmlNode* xml = m->GetModelXml();
    wxXmlAttribute* attr = xml->GetAttributes();
    while (attr) {
        attrs[attr->GetName().ToStdString()] = attr->GetValue().ToStdString();
        attr = attr->GetNext();
    }
    return attrs;
}

} // namespace xlEngine
