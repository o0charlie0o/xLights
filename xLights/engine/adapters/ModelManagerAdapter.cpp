/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "ModelManagerAdapter.h"
#include "../../models/ModelManager.h"
#include "../../models/Model.h"
#include "../../models/SubModel.h"

namespace xlEngine {

ModelManagerAdapter::ModelManagerAdapter(ModelManager& manager)
    : _manager(manager)
{
}

// --- IModelProvider Implementation ---

size_t ModelManagerAdapter::getModelCount() const
{
    return _manager.size();
}

std::string ModelManagerAdapter::getModelName(size_t index) const
{
    if (index >= _manager.size()) {
        return "";
    }

    auto it = _manager.begin();
    std::advance(it, index);
    return it->first;
}

std::vector<std::string> ModelManagerAdapter::getModelNames() const
{
    std::vector<std::string> names;
    names.reserve(_manager.size());
    for (auto it = _manager.begin(); it != _manager.end(); ++it) {
        names.push_back(it->first);
    }
    return names;
}

std::vector<std::string> ModelManagerAdapter::getGroupNames() const
{
    std::vector<std::string> names;
    for (auto it = _manager.begin(); it != _manager.end(); ++it) {
        if (it->second != nullptr && it->second->GetDisplayAs() == "ModelGroup") {
            names.push_back(it->first);
        }
    }
    return names;
}

Model* ModelManagerAdapter::getModel(const std::string& name)
{
    return _manager.GetModel(name);
}

const Model* ModelManagerAdapter::getModel(const std::string& name) const
{
    return _manager.GetModel(name);
}

std::vector<std::string> ModelManagerAdapter::getSubmodels(const std::string& modelName) const
{
    std::vector<std::string> result;
    const Model* model = _manager.GetModel(modelName);
    if (model == nullptr) {
        return result;
    }

    const auto& submodels = model->GetSubModels();
    result.reserve(submodels.size());
    for (const auto* sm : submodels) {
        result.push_back(sm->GetName());
    }
    return result;
}

// --- Extended Operations for ModelEngine ---

Model* ModelManagerAdapter::createDefaultModel(const std::string& type, const std::string& startChannel)
{
    return _manager.CreateDefaultModel(type, startChannel);
}

void ModelManagerAdapter::addModel(Model* model)
{
    _manager.AddModel(model);
}

bool ModelManagerAdapter::deleteModel(const std::string& name)
{
    return _manager.Delete(name);
}

bool ModelManagerAdapter::renameModel(const std::string& oldName, const std::string& newName)
{
    return _manager.Rename(oldName, newName);
}

std::vector<std::string> ModelManagerAdapter::getGroupsContainingModel(Model* model) const
{
    return _manager.GetGroupsContainingModel(model);
}

} // namespace xlEngine
