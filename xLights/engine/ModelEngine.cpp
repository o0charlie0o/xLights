/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "ModelEngine.h"

#include <algorithm>

#include "../models/Model.h"
#include "../models/ModelManager.h"
#include "../models/ModelGroup.h"
#include "../models/SubModel.h"
#include "../models/Node.h"
#include "../models/BaseObject.h"

#include <wx/xml/xml.h>

namespace xlEngine {

ModelEngine::ModelEngine(ModelManager& modelManager)
    : _modelManager(modelManager)
{
}

ModelEngine::~ModelEngine()
{
}

// --- Private Helpers ---

Model* ModelEngine::findModel(const std::string& name) const
{
    return _modelManager.GetModel(name);
}

ModelInfo ModelEngine::buildModelInfo(const Model* model) const
{
    ModelInfo info;
    if (model == nullptr)
        return info;

    info.name = model->GetName();
    info.type = model->GetDisplayAs();
    info.description = model->description;
    info.nodeCount = model->GetNodeCount();
    info.channelCount = model->GetChanCount();
    info.firstChannel = model->GetFirstChannel();
    info.lastChannel = model->GetLastChannel();
    info.defaultBufferWi = model->GetDefaultBufferWi();
    info.defaultBufferHt = model->GetDefaultBufferHt();
    info.startChannel = model->ModelStartChannel;
    info.layoutGroup = model->GetLayoutGroup();
    info.controllerName = model->GetControllerName();
    info.controllerProtocol = model->GetControllerProtocol();
    info.controllerPort = model->GetControllerPort();
    info.isActive = model->IsActive();
    info.isGroupModel = (info.type == "ModelGroup");

    // Extract all XML attributes as string properties
    wxXmlNode* xml = model->GetModelXml();
    if (xml != nullptr) {
        for (wxXmlAttribute* attr = xml->GetAttributes(); attr != nullptr; attr = attr->GetNext()) {
            info.properties[attr->GetName().ToStdString()] = attr->GetValue().ToStdString();
        }
    }

    return info;
}

// --- Enumeration ---

std::vector<std::string> ModelEngine::getModelNames() const
{
    std::vector<std::string> names;
    for (auto it = _modelManager.begin(); it != _modelManager.end(); ++it) {
        names.push_back(it->first);
    }
    return names;
}

std::vector<std::string> ModelEngine::getModelNamesExcludingGroups() const
{
    std::vector<std::string> names;
    for (auto it = _modelManager.begin(); it != _modelManager.end(); ++it) {
        if (it->second != nullptr && it->second->GetDisplayAs() != "ModelGroup") {
            names.push_back(it->first);
        }
    }
    return names;
}

std::vector<std::string> ModelEngine::getGroupNames() const
{
    std::vector<std::string> names;
    for (auto it = _modelManager.begin(); it != _modelManager.end(); ++it) {
        if (it->second != nullptr && it->second->GetDisplayAs() == "ModelGroup") {
            names.push_back(it->first);
        }
    }
    return names;
}

// --- Model Metadata ---

bool ModelEngine::hasModel(const std::string& name) const
{
    return findModel(name) != nullptr;
}

ModelInfo ModelEngine::getModel(const std::string& name) const
{
    Model* m = findModel(name);
    return buildModelInfo(m);
}

std::map<std::string, std::string> ModelEngine::getModelProperties(const std::string& name) const
{
    std::map<std::string, std::string> props;
    Model* m = findModel(name);
    if (m == nullptr)
        return props;

    wxXmlNode* xml = m->GetModelXml();
    if (xml == nullptr)
        return props;

    for (wxXmlAttribute* attr = xml->GetAttributes(); attr != nullptr; attr = attr->GetNext()) {
        props[attr->GetName().ToStdString()] = attr->GetValue().ToStdString();
    }

    // Also include controller connection attributes
    wxXmlNode* cc = m->GetControllerConnection();
    if (cc != nullptr) {
        for (wxXmlAttribute* attr = cc->GetAttributes(); attr != nullptr; attr = attr->GetNext()) {
            std::string key = "ControllerConnection." + attr->GetName().ToStdString();
            props[key] = attr->GetValue().ToStdString();
        }
    }

    return props;
}

std::string ModelEngine::getModelProperty(const std::string& name, const std::string& key, const std::string& defaultValue) const
{
    Model* m = findModel(name);
    if (m == nullptr)
        return defaultValue;

    wxXmlNode* xml = m->GetModelXml();
    if (xml == nullptr)
        return defaultValue;

    wxString val = xml->GetAttribute(key, defaultValue);
    return val.ToStdString();
}

// --- Node Data ---

std::vector<NodeCoord> ModelEngine::getModelNodes(const std::string& name) const
{
    std::vector<NodeCoord> result;
    Model* m = findModel(name);
    if (m == nullptr)
        return result;

    uint32_t nodeCount = m->GetNodeCount();
    result.reserve(nodeCount);

    for (uint32_t i = 0; i < nodeCount; ++i) {
        NodeBaseClass* node = m->GetNode(i);
        if (node == nullptr)
            continue;

        NodeCoord nc;
        nc.actChannel = node->ActChan;
        nc.channelCount = node->GetChanCount();
        nc.stringNum = node->StringNum;

        // Use the first coordinate of the node for position
        if (!node->Coords.empty()) {
            nc.bufX = node->Coords[0].bufX;
            nc.bufY = node->Coords[0].bufY;
            nc.x = node->Coords[0].screenX;
            nc.y = node->Coords[0].screenY;
            nc.z = node->Coords[0].screenZ;
        }

        result.push_back(nc);
    }

    return result;
}

uint32_t ModelEngine::getModelNodeCount(const std::string& name) const
{
    Model* m = findModel(name);
    if (m == nullptr)
        return 0;
    return m->GetNodeCount();
}

uint32_t ModelEngine::getModelChannelCount(const std::string& name) const
{
    Model* m = findModel(name);
    if (m == nullptr)
        return 0;
    return m->GetChanCount();
}

// --- Model CRUD ---

OperationResult ModelEngine::createModel(const std::string& type, const std::string& name,
                                         const std::map<std::string, std::string>& properties)
{
    if (findModel(name) != nullptr)
        return {false, "Model '" + name + "' already exists"};

    std::string startChannel = "1";
    auto scIt = properties.find("StartChannel");
    if (scIt != properties.end()) {
        startChannel = scIt->second;
    }

    Model* model = _modelManager.CreateDefaultModel(type, startChannel);
    if (model == nullptr)
        return {false, "Failed to create model of type '" + type + "'"};

    wxXmlNode* xml = model->GetModelXml();
    if (xml != nullptr) {
        xml->DeleteAttribute("name");
        xml->AddAttribute("name", name);
    }
    model->name = name;

    for (const auto& [key, value] : properties) {
        if (key == "StartChannel")
            continue;
        if (xml != nullptr) {
            if (xml->HasAttribute(key)) {
                xml->DeleteAttribute(key);
            }
            xml->AddAttribute(key, value);
        }
    }

    model->SetFromXml(xml);
    _modelManager.AddModel(model);

    ModelChangeEvent event;
    event.type = ModelChangeType::Added;
    event.modelName = name;
    notifyModelChanged(event);

    return {true, ""};
}

OperationResult ModelEngine::deleteModel(const std::string& name)
{
    if (findModel(name) == nullptr)
        return {false, "Model '" + name + "' not found"};

    bool result = _modelManager.Delete(name);

    if (result) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Removed;
        event.modelName = name;
        notifyModelChanged(event);
    }

    return {result, result ? "" : "Failed to delete model '" + name + "'"};
}

OperationResult ModelEngine::renameModel(const std::string& oldName, const std::string& newName)
{
    if (findModel(oldName) == nullptr)
        return {false, "Model '" + oldName + "' not found"};

    if (findModel(newName) != nullptr)
        return {false, "Model '" + newName + "' already exists"};

    bool result = _modelManager.Rename(oldName, newName);

    if (result) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Renamed;
        event.modelName = newName;
        event.oldName = oldName;
        notifyModelChanged(event);
    }

    return {result, result ? "" : "Failed to rename model"};
}

OperationResult ModelEngine::updateModelProperty(const std::string& name, const std::string& key, const std::string& value)
{
    Model* m = findModel(name);
    if (m == nullptr)
        return {false, "Model '" + name + "' not found"};

    m->SetProperty(wxString(key), wxString(value), true);

    ModelChangeEvent event;
    event.type = ModelChangeType::PropertyChanged;
    event.modelName = name;
    event.propertyKey = key;
    event.propertyValue = value;
    notifyModelChanged(event);

    return {true, ""};
}

// --- Submodels ---

std::vector<SubmodelInfo> ModelEngine::getSubmodels(const std::string& modelName) const
{
    std::vector<SubmodelInfo> result;
    Model* m = findModel(modelName);
    if (m == nullptr)
        return result;

    const auto& submodels = m->GetSubModels();
    result.reserve(submodels.size());

    for (const auto* sm : submodels) {
        SubmodelInfo info;
        info.name = sm->GetName();
        info.fullName = sm->GetFullName();
        info.nodeCount = sm->GetNodeCount();
        info.channelCount = sm->GetChanCount();
        result.push_back(info);
    }

    return result;
}

bool ModelEngine::hasSubmodel(const std::string& modelName, const std::string& submodelName) const
{
    Model* m = findModel(modelName);
    if (m == nullptr)
        return false;
    return m->GetSubModel(submodelName) != nullptr;
}

// --- Groups ---

std::vector<ModelGroupInfo> ModelEngine::getModelGroups() const
{
    std::vector<ModelGroupInfo> result;
    for (auto it = _modelManager.begin(); it != _modelManager.end(); ++it) {
        if (it->second != nullptr && it->second->GetDisplayAs() == "ModelGroup") {
            ModelGroup* grp = dynamic_cast<ModelGroup*>(it->second);
            if (grp != nullptr) {
                ModelGroupInfo info;
                info.name = grp->GetName();
                info.modelNames = grp->ModelNames();
                result.push_back(info);
            }
        }
    }
    return result;
}

ModelGroupInfo ModelEngine::getModelGroup(const std::string& groupName) const
{
    ModelGroupInfo info;
    Model* m = findModel(groupName);
    if (m == nullptr || m->GetDisplayAs() != "ModelGroup")
        return info;

    ModelGroup* grp = dynamic_cast<ModelGroup*>(m);
    if (grp == nullptr)
        return info;

    info.name = grp->GetName();
    info.modelNames = grp->ModelNames();
    return info;
}

std::vector<std::string> ModelEngine::getGroupsContainingModel(const std::string& modelName) const
{
    std::vector<std::string> result;
    Model* model = findModel(modelName);
    if (model == nullptr)
        return result;

    auto groups = _modelManager.GetGroupsContainingModel(model);
    for (const auto& g : groups) {
        result.push_back(g);
    }
    return result;
}

// --- Position & Geometry ---

ModelEngine::BoundingBox ModelEngine::getModelBounds(const std::string& name) const
{
    BoundingBox box;
    Model* m = findModel(name);
    if (m == nullptr)
        return box;

    // Use the screen location to get bounds
    const ModelScreenLocation& loc = m->GetModelScreenLocation();
    box.minX = loc.GetLeft();
    box.maxX = loc.GetRight();
    box.minY = loc.GetBottom();
    box.maxY = loc.GetTop();
    box.minZ = loc.GetFront();
    box.maxZ = loc.GetBack();

    return box;
}

// --- Listener Management ---

void ModelEngine::addListener(ModelEngineListener* listener)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.push_back(listener);
}

void ModelEngine::removeListener(ModelEngineListener* listener)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.erase(
        std::remove(_listeners.begin(), _listeners.end(), listener),
        _listeners.end());
}

void ModelEngine::notifyModelChanged(const ModelChangeEvent& event)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        switch (event.type) {
            case ModelChangeType::Added:
                listener->onModelAdded(event);
                break;
            case ModelChangeType::Removed:
                listener->onModelRemoved(event);
                break;
            case ModelChangeType::Modified:
                listener->onModelModified(event);
                break;
            case ModelChangeType::Renamed:
                listener->onModelRenamed(event);
                break;
            case ModelChangeType::PropertyChanged:
                listener->onModelPropertyChanged(event);
                break;
        }
    }
}

} // namespace xlEngine
