/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "NativeModelProvider.h"

#import <Foundation/Foundation.h>

#ifndef XLIGHTS_NATIVE
// Legacy build: Full implementation using wxWidgets Model classes
#include "../../models/Model.h"
#include "../../models/ModelManager.h"
#include "../../models/ModelGroup.h"
#include "../../models/SubModel.h"

#include <algorithm>

namespace xlEngine {

// MARK: - Construction / Destruction

NativeModelProvider::NativeModelProvider()
    : _externalManager(nullptr)
{
}

NativeModelProvider::NativeModelProvider(ModelManager& manager)
    : _externalManager(&manager)
{
    rebuildModelNamesList();
}

NativeModelProvider::~NativeModelProvider()
{
    clearModels();
}

// MARK: - IModelProvider Implementation

size_t NativeModelProvider::getModelCount() const
{
    std::lock_guard<std::mutex> lock(_mutex);

    if (_externalManager) {
        return _externalManager->size();
    }
    return _models.size();
}

std::string NativeModelProvider::getModelName(size_t index) const
{
    std::lock_guard<std::mutex> lock(_mutex);

    if (_externalManager) {
        if (index >= _externalManager->size()) {
            return "";
        }
        auto it = _externalManager->begin();
        std::advance(it, index);
        return it->first;
    }

    if (index >= _modelNames.size()) {
        return "";
    }
    return _modelNames[index];
}

std::vector<std::string> NativeModelProvider::getModelNames() const
{
    std::lock_guard<std::mutex> lock(_mutex);

    if (_externalManager) {
        std::vector<std::string> names;
        names.reserve(_externalManager->size());
        for (auto it = _externalManager->begin(); it != _externalManager->end(); ++it) {
            names.push_back(it->first);
        }
        return names;
    }

    return _modelNames;
}

std::vector<std::string> NativeModelProvider::getGroupNames() const
{
    std::lock_guard<std::mutex> lock(_mutex);

    if (_externalManager) {
        std::vector<std::string> names;
        for (auto it = _externalManager->begin(); it != _externalManager->end(); ++it) {
            if (it->second != nullptr && it->second->GetDisplayAs() == "ModelGroup") {
                names.push_back(it->first);
            }
        }
        return names;
    }

    std::vector<std::string> names;
    for (const auto& [name, model] : _models) {
        if (model && model->GetDisplayAs() == "ModelGroup") {
            names.push_back(name);
        }
    }
    return names;
}

Model* NativeModelProvider::getModel(const std::string& name)
{
    std::lock_guard<std::mutex> lock(_mutex);

    if (_externalManager) {
        return _externalManager->GetModel(name);
    }

    auto it = _models.find(name);
    if (it != _models.end()) {
        return it->second.get();
    }
    return nullptr;
}

const Model* NativeModelProvider::getModel(const std::string& name) const
{
    std::lock_guard<std::mutex> lock(_mutex);

    if (_externalManager) {
        return _externalManager->GetModel(name);
    }

    auto it = _models.find(name);
    if (it != _models.end()) {
        return it->second.get();
    }
    return nullptr;
}

std::vector<std::string> NativeModelProvider::getSubmodels(const std::string& modelName) const
{
    std::lock_guard<std::mutex> lock(_mutex);

    std::vector<std::string> result;
    const Model* model = nullptr;

    if (_externalManager) {
        model = _externalManager->GetModel(modelName);
    } else {
        auto it = _models.find(modelName);
        if (it != _models.end()) {
            model = it->second.get();
        }
    }

    if (model == nullptr) {
        return result;
    }

    const auto& submodels = model->GetSubModels();
    result.reserve(submodels.size());
    for (const auto* sm : submodels) {
        if (sm) {
            result.push_back(sm->GetName());
        }
    }
    return result;
}

std::map<std::string, std::string> NativeModelProvider::getSubmodelAttributes(
    const std::string& modelName, const std::string& submodelName) const
{
    std::lock_guard<std::mutex> lock(_mutex);

    const Model* model = nullptr;
    if (_externalManager) {
        model = _externalManager->GetModel(modelName);
    } else {
        auto it = _models.find(modelName);
        if (it != _models.end()) model = it->second.get();
    }
    if (model == nullptr) return {};

    wxXmlNode* xml = model->GetModelXml();
    if (xml == nullptr) return {};

    for (wxXmlNode* child = xml->GetChildren(); child != nullptr; child = child->GetNext()) {
        if (child->GetName() == "subModel" && child->GetAttribute("name") == wxString(submodelName)) {
            std::map<std::string, std::string> attrs;
            for (wxXmlAttribute* attr = child->GetAttributes(); attr != nullptr; attr = attr->GetNext()) {
                attrs[attr->GetName().ToStdString()] = attr->GetValue().ToStdString();
            }
            return attrs;
        }
    }
    return {};
}

bool NativeModelProvider::setSubmodelAttributes(const std::string& modelName, const std::string& submodelName,
                                                const std::map<std::string, std::string>& attrs)
{
    // Legacy build: submodel mutation goes through ModelEngine -> wxXmlNode directly
    return false;
}

bool NativeModelProvider::deleteSubmodel(const std::string& modelName, const std::string& submodelName)
{
    return false;
}

bool NativeModelProvider::renameSubmodel(const std::string& modelName, const std::string& oldName,
                                         const std::string& newName)
{
    return false;
}

bool NativeModelProvider::hasModel(const std::string& name) const
{
    std::lock_guard<std::mutex> lock(_mutex);

    if (_externalManager) {
        return _externalManager->GetModel(name) != nullptr;
    }

    if (_models.find(name) != _models.end()) {
        return true;
    }

    // Fallback: check name list (for standalone XML-loaded models)
    return std::find(_modelNames.begin(), _modelNames.end(), name) != _modelNames.end();
}

std::map<std::string, std::string> NativeModelProvider::getModelAttributes(const std::string& name) const
{
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _modelAttributes.find(name);
    if (it != _modelAttributes.end()) {
        return it->second;
    }
    auto git = _groupAttributes.find(name);
    if (git != _groupAttributes.end()) {
        return git->second;
    }
    return {};
}

// MARK: - Native Model Loading

bool NativeModelProvider::loadModelsFromShowFolder(const std::string& showFolderPath)
{
    if (showFolderPath.empty()) {
        NSLog(@"NativeModelProvider: Cannot load models - show folder path is empty");
        return false;
    }

    NSString* folderPath = [NSString stringWithUTF8String:showFolderPath.c_str()];
    NSString* rgbEffectsPath = [folderPath stringByAppendingPathComponent:@"xlights_rgbeffects.xml"];

    // Check if file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:rgbEffectsPath]) {
        NSLog(@"NativeModelProvider: rgbeffects.xml not found at: %@", rgbEffectsPath);
        return false;
    }

    bool result = loadModelsFromFile([rgbEffectsPath UTF8String]);
    if (result) {
        std::lock_guard<std::mutex> lock(_mutex);
        _showFolderPath = showFolderPath;
    }
    return result;
}

bool NativeModelProvider::loadModelsFromFile(const std::string& xmlFilePath)
{
    if (xmlFilePath.empty()) {
        NSLog(@"NativeModelProvider: Cannot load models - file path is empty");
        return false;
    }

    NSString* filePath = [NSString stringWithUTF8String:xmlFilePath.c_str()];

    // Check if file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"NativeModelProvider: File not found: %@", filePath);
        return false;
    }

    // Read file content
    NSError* error = nil;
    NSString* content = [NSString stringWithContentsOfFile:filePath
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (error || !content) {
        NSLog(@"NativeModelProvider: Failed to read file: %@ - %@",
              filePath, error.localizedDescription);
        return false;
    }

    NSLog(@"NativeModelProvider: Loading models from %@", filePath);

    // For now, delegate to external manager if available
    // Full native XML parsing will be implemented in a future iteration
    if (_externalManager) {
        // The external manager loads models through its own mechanisms
        // We just need to refresh our cached names
        rebuildModelNamesList();
        NSLog(@"NativeModelProvider: Using external ModelManager, %zu models available",
              _externalManager->size());
        return true;
    }

    // Parse the XML content for standalone operation
    return parseModelsFromXML([content UTF8String]);
}

void NativeModelProvider::clearModels()
{
    std::lock_guard<std::mutex> lock(_mutex);
    _models.clear();
    _modelNames.clear();
    _groupAttributes.clear();
    _submodelAttributes.clear();
    _faceDefinitions.clear();
    _stateDefinitions.clear();
    _dimmingCurveInfo.clear();
    _showFolderPath.clear();
}

std::string NativeModelProvider::getShowFolderPath() const
{
    std::lock_guard<std::mutex> lock(_mutex);
    return _showFolderPath;
}

// MARK: - Model Management

bool NativeModelProvider::addModel(std::unique_ptr<Model> model)
{
    if (!model) {
        return false;
    }

    std::lock_guard<std::mutex> lock(_mutex);

    if (_externalManager) {
        // Cannot add to external manager through this interface
        NSLog(@"NativeModelProvider: Cannot add model when using external manager");
        return false;
    }

    std::string name = model->GetName();
    if (name.empty()) {
        NSLog(@"NativeModelProvider: Cannot add model with empty name");
        return false;
    }

    // Check for duplicate
    if (_models.find(name) != _models.end()) {
        NSLog(@"NativeModelProvider: Model '%s' already exists", name.c_str());
        return false;
    }

    _models[name] = std::move(model);
    rebuildModelNamesList();

    NSLog(@"NativeModelProvider: Added model '%s'", name.c_str());
    return true;
}

bool NativeModelProvider::removeModel(const std::string& name)
{
    std::lock_guard<std::mutex> lock(_mutex);

    if (_externalManager) {
        NSLog(@"NativeModelProvider: Cannot remove model when using external manager");
        return false;
    }

    auto it = _models.find(name);
    if (it == _models.end()) {
        return false;
    }

    _models.erase(it);
    rebuildModelNamesList();

    NSLog(@"NativeModelProvider: Removed model '%s'", name.c_str());
    return true;
}

// MARK: - Private Helpers

void NativeModelProvider::rebuildModelNamesList()
{
    // Note: Caller must hold _mutex
    _modelNames.clear();

    if (_externalManager) {
        _modelNames.reserve(_externalManager->size());
        for (auto it = _externalManager->begin(); it != _externalManager->end(); ++it) {
            _modelNames.push_back(it->first);
        }
    } else {
        _modelNames.reserve(_models.size());
        for (const auto& [name, model] : _models) {
            _modelNames.push_back(name);
        }
    }
}

bool NativeModelProvider::parseModelsFromXML(const std::string& xmlContent)
{
    // This is a placeholder for native XML parsing.
    if (xmlContent.empty()) {
        NSLog(@"NativeModelProvider: Empty XML content");
        return false;
    }

    NSData* xmlData = [NSData dataWithBytes:xmlContent.c_str() length:xmlContent.size()];
    NSError* error = nil;

    // Use NSXMLDocument for parsing
    NSXMLDocument* xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData
                                                        options:0
                                                          error:&error];
    if (error || !xmlDoc) {
        NSLog(@"NativeModelProvider: Failed to parse XML: %@", error.localizedDescription);
        return false;
    }

    // Find all model elements
    NSArray<NSXMLElement*>* modelElements = [xmlDoc.rootElement nodesForXPath:@"//models/model" error:&error];
    if (error) {
        NSLog(@"NativeModelProvider: XPath error: %@", error.localizedDescription);
        return false;
    }

    NSLog(@"NativeModelProvider: Found %lu model elements in XML", (unsigned long)modelElements.count);

    if (modelElements.count > 0) {
        NSLog(@"NativeModelProvider: Note: Native model creation not yet implemented. "
              "Use NativeModelProvider(ModelManager&) constructor for full functionality.");
    }

    return modelElements.count > 0;
}

std::map<std::string, std::string> NativeModelProvider::getGroupAttributes(const std::string& groupName) const
{
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _groupAttributes.find(groupName);
    if (it != _groupAttributes.end()) {
        return it->second;
    }
    return {};
}

bool NativeModelProvider::createGroup(const std::string& groupName, const std::string& modelNames)
{
    // Non-native build: delegate to external manager if available
    NSLog(@"NativeModelProvider: createGroup not implemented for non-native build");
    return false;
}

bool NativeModelProvider::deleteGroup(const std::string& groupName)
{
    NSLog(@"NativeModelProvider: deleteGroup not implemented for non-native build");
    return false;
}

bool NativeModelProvider::renameGroup(const std::string& oldName, const std::string& newName)
{
    NSLog(@"NativeModelProvider: renameGroup not implemented for non-native build");
    return false;
}

bool NativeModelProvider::addModelToGroup(const std::string& groupName, const std::string& modelName)
{
    NSLog(@"NativeModelProvider: addModelToGroup not implemented for non-native build");
    return false;
}

bool NativeModelProvider::removeModelFromGroup(const std::string& groupName, const std::string& modelName)
{
    NSLog(@"NativeModelProvider: removeModelFromGroup not implemented for non-native build");
    return false;
}

} // namespace xlEngine

#else // XLIGHTS_NATIVE

// Native build: Stub implementation without wxWidgets dependencies

namespace xlEngine {

NativeModelProvider::NativeModelProvider() {}
NativeModelProvider::~NativeModelProvider() { clearModels(); }

size_t NativeModelProvider::getModelCount() const {
    std::lock_guard<std::mutex> lock(_mutex);
    return _modelNames.size();
}

std::string NativeModelProvider::getModelName(size_t index) const {
    std::lock_guard<std::mutex> lock(_mutex);
    if (index >= _modelNames.size()) return "";
    return _modelNames[index];
}

std::vector<std::string> NativeModelProvider::getModelNames() const {
    std::lock_guard<std::mutex> lock(_mutex);
    return _modelNames;
}

std::vector<std::string> NativeModelProvider::getGroupNames() const {
    std::lock_guard<std::mutex> lock(_mutex);
    return _groupNames;
}

Model* NativeModelProvider::getModel(const std::string& name) {
    return nullptr; // Model class not available in native build
}

const Model* NativeModelProvider::getModel(const std::string& name) const {
    return nullptr;
}

std::vector<std::string> NativeModelProvider::getSubmodels(const std::string& modelName) const {
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _submodelAttributes.find(modelName);
    if (it == _submodelAttributes.end()) return {};
    std::vector<std::string> result;
    result.reserve(it->second.size());
    for (const auto& pair : it->second) {
        result.push_back(pair.first);
    }
    return result;
}

std::map<std::string, std::string> NativeModelProvider::getSubmodelAttributes(
    const std::string& modelName, const std::string& submodelName) const {
    std::lock_guard<std::mutex> lock(_mutex);
    auto modelIt = _submodelAttributes.find(modelName);
    if (modelIt == _submodelAttributes.end()) return {};
    auto smIt = modelIt->second.find(submodelName);
    if (smIt == modelIt->second.end()) return {};
    return smIt->second;
}

bool NativeModelProvider::setSubmodelAttributes(const std::string& modelName, const std::string& submodelName,
                                                const std::map<std::string, std::string>& attrs) {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_modelAttributes.find(modelName) == _modelAttributes.end()) return false;
    _submodelAttributes[modelName][submodelName] = attrs;
    return true;
}

bool NativeModelProvider::deleteSubmodel(const std::string& modelName, const std::string& submodelName) {
    std::lock_guard<std::mutex> lock(_mutex);
    auto modelIt = _submodelAttributes.find(modelName);
    if (modelIt == _submodelAttributes.end()) return false;
    auto smIt = modelIt->second.find(submodelName);
    if (smIt == modelIt->second.end()) return false;
    modelIt->second.erase(smIt);
    return true;
}

bool NativeModelProvider::renameSubmodel(const std::string& modelName, const std::string& oldName,
                                         const std::string& newName) {
    std::lock_guard<std::mutex> lock(_mutex);
    auto modelIt = _submodelAttributes.find(modelName);
    if (modelIt == _submodelAttributes.end()) return false;
    auto smIt = modelIt->second.find(oldName);
    if (smIt == modelIt->second.end()) return false;
    if (modelIt->second.find(newName) != modelIt->second.end()) return false;
    auto attrs = smIt->second;
    attrs["name"] = newName;
    modelIt->second.erase(smIt);
    modelIt->second[newName] = std::move(attrs);
    return true;
}

bool NativeModelProvider::loadModelsFromShowFolder(const std::string& showFolderPath) {
    if (showFolderPath.empty()) {
        NSLog(@"NativeModelProvider: Cannot load models - show folder path is empty");
        return false;
    }

    NSString* folderPath = [NSString stringWithUTF8String:showFolderPath.c_str()];
    NSString* rgbEffectsPath = [folderPath stringByAppendingPathComponent:@"xlights_rgbeffects.xml"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:rgbEffectsPath]) {
        NSLog(@"NativeModelProvider: rgbeffects.xml not found at: %@", rgbEffectsPath);
        return false;
    }

    bool result = loadModelsFromFile([rgbEffectsPath UTF8String]);
    if (result) {
        std::lock_guard<std::mutex> lock(_mutex);
        _showFolderPath = showFolderPath;
    }
    return result;
}

bool NativeModelProvider::loadModelsFromFile(const std::string& xmlFilePath) {
    if (xmlFilePath.empty()) return false;

    NSString* filePath = [NSString stringWithUTF8String:xmlFilePath.c_str()];
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        return false;
    }

    // Parse XML to extract model names and attributes
    NSError* error = nil;
    NSString* content = [NSString stringWithContentsOfFile:filePath
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (error || !content) return false;

    NSData* xmlData = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSXMLDocument* xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (error || !xmlDoc) return false;

    NSArray<NSXMLElement*>* modelElements = [xmlDoc.rootElement nodesForXPath:@"//models/model" error:&error];
    if (error) return false;

    std::lock_guard<std::mutex> lock(_mutex);
    _modelNames.clear();
    _groupNames.clear();
    _modelAttributes.clear();
    _submodelAttributes.clear();

    // Parse group names and attributes (from modelGroups section)
    NSArray<NSXMLElement*>* groupElements = [xmlDoc.rootElement nodesForXPath:@"//modelGroups/modelGroup" error:nil];
    for (NSXMLElement* elem in groupElements) {
        NSXMLNode* nameAttr = [elem attributeForName:@"name"];
        if (nameAttr && nameAttr.stringValue) {
            std::string gName = [nameAttr.stringValue UTF8String];
            _groupNames.push_back(gName);

            // Store all XML attributes (includes "models" list of member names)
            std::map<std::string, std::string> gAttrs;
            for (NSXMLNode* attr in [elem attributes]) {
                if (attr.name && attr.stringValue) {
                    gAttrs[[attr.name UTF8String]] = [attr.stringValue UTF8String];
                }
            }
            _groupAttributes[gName] = std::move(gAttrs);
        }
    }

    for (NSXMLElement* elem in modelElements) {
        NSXMLNode* nameAttr = [elem attributeForName:@"name"];
        if (nameAttr && nameAttr.stringValue) {
            std::string name = [nameAttr.stringValue UTF8String];
            _modelNames.push_back(name);

            // Store all XML attributes for this model
            std::map<std::string, std::string> attrs;
            for (NSXMLNode* attr in [elem attributes]) {
                if (attr.name && attr.stringValue) {
                    attrs[[attr.name UTF8String]] = [attr.stringValue UTF8String];
                }
            }
            // Parse ControllerConnection child element attributes
            NSArray<NSXMLElement*>* ccElements = [elem elementsForName:@"ControllerConnection"];
            if (ccElements.count > 0) {
                NSXMLElement* ccElem = ccElements.firstObject;
                for (NSXMLNode* ccAttr in [ccElem attributes]) {
                    if (ccAttr.name && ccAttr.stringValue) {
                        std::string ccKey = "ControllerConnection." + std::string([ccAttr.name UTF8String]);
                        attrs[ccKey] = [ccAttr.stringValue UTF8String];
                    }
                }
            }

            _modelAttributes[name] = std::move(attrs);

            // Parse subModel child elements
            NSArray<NSXMLElement*>* smElements = [elem elementsForName:@"subModel"];
            if (smElements.count > 0) {
                std::map<std::string, std::map<std::string, std::string>> submodels;
                for (NSXMLElement* smElem in smElements) {
                    NSXMLNode* smNameAttr = [smElem attributeForName:@"name"];
                    if (smNameAttr && smNameAttr.stringValue) {
                        std::string smName = [smNameAttr.stringValue UTF8String];
                        std::map<std::string, std::string> smAttrs;
                        for (NSXMLNode* smAttr in [smElem attributes]) {
                            if (smAttr.name && smAttr.stringValue) {
                                smAttrs[[smAttr.name UTF8String]] = [smAttr.stringValue UTF8String];
                            }
                        }
                        submodels[smName] = std::move(smAttrs);
                    }
                }
                if (!submodels.empty()) {
                    _submodelAttributes[name] = std::move(submodels);
                }
            }

            // Parse faceInfo child elements
            NSArray<NSXMLElement*>* faceElements = [elem elementsForName:@"faceInfo"];
            if (faceElements.count > 0) {
                std::map<std::string, std::map<std::string, std::string>> faces;
                for (NSXMLElement* faceElem in faceElements) {
                    NSXMLNode* faceNameAttr = [faceElem attributeForName:@"Name"];
                    if (faceNameAttr && faceNameAttr.stringValue) {
                        std::string faceName = [faceNameAttr.stringValue UTF8String];
                        std::map<std::string, std::string> faceAttrs;
                        for (NSXMLNode* faceAttr in [faceElem attributes]) {
                            if (faceAttr.name && faceAttr.stringValue) {
                                std::string attrName = [faceAttr.name UTF8String];
                                if (attrName != "Name") {
                                    faceAttrs[attrName] = [faceAttr.stringValue UTF8String];
                                }
                            }
                        }
                        faces[faceName] = std::move(faceAttrs);
                    }
                }
                if (!faces.empty()) {
                    _faceDefinitions[name] = std::move(faces);
                }
            }

            // Parse stateInfo child elements
            NSArray<NSXMLElement*>* stateElements = [elem elementsForName:@"stateInfo"];
            if (stateElements.count > 0) {
                std::map<std::string, std::map<std::string, std::string>> states;
                for (NSXMLElement* stateElem in stateElements) {
                    NSXMLNode* stateNameAttr = [stateElem attributeForName:@"Name"];
                    if (stateNameAttr && stateNameAttr.stringValue) {
                        std::string stateName = [stateNameAttr.stringValue UTF8String];
                        std::map<std::string, std::string> stateAttrs;
                        for (NSXMLNode* stateAttr in [stateElem attributes]) {
                            if (stateAttr.name && stateAttr.stringValue) {
                                std::string attrName = [stateAttr.name UTF8String];
                                if (attrName != "Name") {
                                    stateAttrs[attrName] = [stateAttr.stringValue UTF8String];
                                }
                            }
                        }
                        states[stateName] = std::move(stateAttrs);
                    }
                }
                if (!states.empty()) {
                    _stateDefinitions[name] = std::move(states);
                }
            }

            // Parse dimmingCurve child element
            NSArray<NSXMLElement*>* dimmingElements = [elem elementsForName:@"dimmingCurve"];
            if (dimmingElements.count > 0) {
                NSXMLElement* dimmingElem = dimmingElements.firstObject;
                std::map<std::string, std::map<std::string, std::string>> dimInfo;
                for (NSXMLElement* channelElem in [dimmingElem children]) {
                    if (![channelElem isKindOfClass:[NSXMLElement class]]) continue;
                    std::string channelName = [channelElem.name UTF8String];
                    std::map<std::string, std::string> channelAttrs;
                    for (NSXMLNode* attr in [channelElem attributes]) {
                        if (attr.name && attr.stringValue) {
                            channelAttrs[[attr.name UTF8String]] = [attr.stringValue UTF8String];
                        }
                    }
                    if (!channelAttrs.empty()) {
                        dimInfo[channelName] = std::move(channelAttrs);
                    }
                }
                if (!dimInfo.empty()) {
                    _dimmingCurveInfo[name] = std::move(dimInfo);
                }
            }
        }
    }

    // Parse views
    parseViewsFromXML([content UTF8String]);

    // Parse layout groups
    parseLayoutGroupsFromXML([content UTF8String]);

    NSLog(@"NativeModelProvider: Loaded %zu groups + %zu models + %zu layout groups from XML",
          _groupNames.size(), _modelNames.size(), _layoutGroups.size());
    return true;
}

bool NativeModelProvider::hasModel(const std::string& name) const {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_modelAttributes.find(name) != _modelAttributes.end()) return true;
    if (_groupAttributes.find(name) != _groupAttributes.end()) return true;
    return false;
}

std::map<std::string, std::string> NativeModelProvider::getModelAttributes(const std::string& name) const {
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _modelAttributes.find(name);
    if (it != _modelAttributes.end()) {
        return it->second;
    }
    auto git = _groupAttributes.find(name);
    if (git != _groupAttributes.end()) {
        return git->second;
    }
    return {};
}

bool NativeModelProvider::setModelAttribute(const std::string& modelName, const std::string& key, const std::string& value) {
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _modelAttributes.find(modelName);
    if (it == _modelAttributes.end()) {
        return false;
    }
    it->second[key] = value;
    return true;
}

void NativeModelProvider::clearModels() {
    std::lock_guard<std::mutex> lock(_mutex);
    _modelNames.clear();
    _groupNames.clear();
    _modelAttributes.clear();
    _groupAttributes.clear();
    _submodelAttributes.clear();
    _faceDefinitions.clear();
    _stateDefinitions.clear();
    _dimmingCurveInfo.clear();
    _views.clear();
    _layoutGroups.clear();
    _showFolderPath.clear();
}

std::string NativeModelProvider::getShowFolderPath() const {
    std::lock_guard<std::mutex> lock(_mutex);
    return _showFolderPath;
}

std::vector<std::string> NativeModelProvider::getViewNames() const {
    std::lock_guard<std::mutex> lock(_mutex);
    std::vector<std::string> names;
    names.reserve(_views.size() + 1);
    names.push_back("Master View");  // Always include Master View first
    for (const auto& view : _views) {
        names.push_back(view.name);
    }
    return names;
}

SequenceViewInfo NativeModelProvider::getView(const std::string& name) const {
    std::lock_guard<std::mutex> lock(_mutex);
    for (const auto& view : _views) {
        if (view.name == name) {
            return view;
        }
    }
    return SequenceViewInfo{};
}

size_t NativeModelProvider::getViewCount() const {
    std::lock_guard<std::mutex> lock(_mutex);
    return _views.size() + 1;  // +1 for Master View
}

SequenceViewInfo NativeModelProvider::getViewAtIndex(size_t index) const {
    std::lock_guard<std::mutex> lock(_mutex);
    if (index == 0) {
        // Master View: groups first, then individual models (matches legacy AddAllModelsToSequence)
        SequenceViewInfo masterView;
        masterView.name = "Master View";
        masterView.models.reserve(_groupNames.size() + _modelNames.size());
        for (const auto& g : _groupNames) {
            masterView.models.push_back(g);
        }
        for (const auto& m : _modelNames) {
            masterView.models.push_back(m);
        }
        return masterView;
    }
    if (index - 1 >= _views.size()) {
        return SequenceViewInfo{};
    }
    return _views[index - 1];
}

bool NativeModelProvider::addModel(std::unique_ptr<Model> model) {
    return false; // Not supported in native standalone mode
}

bool NativeModelProvider::removeModel(const std::string& name) {
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = std::find(_modelNames.begin(), _modelNames.end(), name);
    if (it == _modelNames.end()) return false;
    _modelNames.erase(it);
    return true;
}

void NativeModelProvider::rebuildModelNamesList() {
    // No-op in native mode - names are managed directly
}

bool NativeModelProvider::parseModelsFromXML(const std::string& xmlContent) {
    return false; // Use loadModelsFromFile instead
}

void NativeModelProvider::parseViewsFromXML(const std::string& xmlContent) {
    // Parse views from xlights_rgbeffects.xml
    // Views are stored as: <views><view name="Groups" models="Model1,Model2,..."/></views>

    if (xmlContent.empty()) {
        return;
    }

    NSData* xmlData = [NSData dataWithBytes:xmlContent.c_str() length:xmlContent.size()];
    NSError* error = nil;
    NSXMLDocument* xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (error || !xmlDoc) {
        NSLog(@"NativeModelProvider: Failed to parse XML for views: %@", error.localizedDescription);
        return;
    }

    // Find views element - try XPath first
    NSArray<NSXMLElement*>* viewElements = [xmlDoc.rootElement nodesForXPath:@"//views/view" error:&error];
    if (error) {
        NSLog(@"NativeModelProvider: XPath error for views: %@", error.localizedDescription);
        return;
    }

    // Clear existing views (but keep _views as the internal storage)
    _views.clear();

    for (NSXMLElement* viewElem in viewElements) {
        NSXMLNode* nameAttr = [viewElem attributeForName:@"name"];
        NSXMLNode* modelsAttr = [viewElem attributeForName:@"models"];

        if (nameAttr && nameAttr.stringValue) {
            SequenceViewInfo viewInfo;
            viewInfo.name = [nameAttr.stringValue UTF8String];

            // Parse models attribute (comma-separated list)
            if (modelsAttr && modelsAttr.stringValue && [modelsAttr.stringValue length] > 0) {
                NSArray<NSString*>* modelNames = [modelsAttr.stringValue componentsSeparatedByString:@","];
                for (NSString* modelName in modelNames) {
                    NSString* trimmedName = [modelName stringByTrimmingCharactersInSet:
                                            [NSCharacterSet whitespaceCharacterSet]];
                    if (trimmedName.length > 0) {
                        viewInfo.models.push_back([trimmedName UTF8String]);
                    }
                }
            }

            _views.push_back(viewInfo);
        }
    }

    NSLog(@"NativeModelProvider: Loaded %zu views from XML", _views.size());
}

std::map<std::string, std::string> NativeModelProvider::getGroupAttributes(const std::string& groupName) const {
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _groupAttributes.find(groupName);
    if (it != _groupAttributes.end()) {
        return it->second;
    }
    return {};
}

bool NativeModelProvider::createGroup(const std::string& groupName, const std::string& modelNames) {
    if (groupName.empty()) return false;

    std::lock_guard<std::mutex> lock(_mutex);

    if (std::find(_groupNames.begin(), _groupNames.end(), groupName) != _groupNames.end()) {
        NSLog(@"NativeModelProvider: Group '%s' already exists", groupName.c_str());
        return false;
    }

    _groupNames.push_back(groupName);

    std::map<std::string, std::string> attrs;
    attrs["name"] = groupName;
    attrs["models"] = modelNames;
    attrs["DisplayAs"] = "ModelGroup";
    attrs["GridSize"] = "400";
    attrs["layout"] = "minimalGrid";
    _groupAttributes[groupName] = std::move(attrs);

    NSLog(@"NativeModelProvider: Created group '%s'", groupName.c_str());
    return true;
}

bool NativeModelProvider::deleteGroup(const std::string& groupName) {
    if (groupName.empty()) return false;

    std::lock_guard<std::mutex> lock(_mutex);

    auto it = std::find(_groupNames.begin(), _groupNames.end(), groupName);
    if (it == _groupNames.end()) {
        return false;
    }

    _groupNames.erase(it);
    _groupAttributes.erase(groupName);

    NSLog(@"NativeModelProvider: Deleted group '%s'", groupName.c_str());
    return true;
}

bool NativeModelProvider::renameGroup(const std::string& oldName, const std::string& newName) {
    if (oldName.empty() || newName.empty()) return false;

    std::lock_guard<std::mutex> lock(_mutex);

    auto it = std::find(_groupNames.begin(), _groupNames.end(), oldName);
    if (it == _groupNames.end()) {
        return false;
    }

    if (std::find(_groupNames.begin(), _groupNames.end(), newName) != _groupNames.end()) {
        NSLog(@"NativeModelProvider: Cannot rename - group '%s' already exists", newName.c_str());
        return false;
    }

    *it = newName;

    auto attrsIt = _groupAttributes.find(oldName);
    if (attrsIt != _groupAttributes.end()) {
        auto attrs = std::move(attrsIt->second);
        _groupAttributes.erase(attrsIt);
        attrs["name"] = newName;
        _groupAttributes[newName] = std::move(attrs);
    }

    NSLog(@"NativeModelProvider: Renamed group '%s' to '%s'", oldName.c_str(), newName.c_str());
    return true;
}

bool NativeModelProvider::addModelToGroup(const std::string& groupName, const std::string& modelName) {
    if (groupName.empty() || modelName.empty()) return false;

    std::lock_guard<std::mutex> lock(_mutex);

    auto it = _groupAttributes.find(groupName);
    if (it == _groupAttributes.end()) {
        return false;
    }

    std::string& models = it->second["models"];
    if (!models.empty()) {
        models += ",";
    }
    models += modelName;

    NSLog(@"NativeModelProvider: Added model '%s' to group '%s'", modelName.c_str(), groupName.c_str());
    return true;
}

bool NativeModelProvider::removeModelFromGroup(const std::string& groupName, const std::string& modelName) {
    if (groupName.empty() || modelName.empty()) return false;

    std::lock_guard<std::mutex> lock(_mutex);

    auto it = _groupAttributes.find(groupName);
    if (it == _groupAttributes.end()) {
        return false;
    }

    std::string& modelsStr = it->second["models"];
    std::vector<std::string> modelList;
    std::istringstream stream(modelsStr);
    std::string token;
    while (std::getline(stream, token, ',')) {
        size_t start = token.find_first_not_of(" \t");
        size_t end = token.find_last_not_of(" \t");
        if (start != std::string::npos) {
            std::string trimmed = token.substr(start, end - start + 1);
            if (trimmed != modelName) {
                modelList.push_back(trimmed);
            }
        }
    }

    std::string newModels;
    for (size_t i = 0; i < modelList.size(); i++) {
        if (i > 0) newModels += ",";
        newModels += modelList[i];
    }
    modelsStr = newModels;

    NSLog(@"NativeModelProvider: Removed model '%s' from group '%s'", modelName.c_str(), groupName.c_str());
    return true;
}

// MARK: - Layout Group Management

std::vector<std::string> NativeModelProvider::getLayoutGroupNames() const {
    std::lock_guard<std::mutex> lock(_mutex);
    std::vector<std::string> names;
    names.push_back("Default");
    names.push_back("All Models");
    names.push_back("Unassigned");
    for (const auto& grp : _layoutGroups) {
        if (grp.name != "Default") {
            names.push_back(grp.name);
        }
    }
    return names;
}

LayoutGroupInfo NativeModelProvider::getLayoutGroup(const std::string& name) const {
    std::lock_guard<std::mutex> lock(_mutex);
    for (const auto& grp : _layoutGroups) {
        if (grp.name == name) {
            return grp;
        }
    }
    LayoutGroupInfo defaultInfo;
    defaultInfo.name = name;
    return defaultInfo;
}

std::vector<LayoutGroupInfo> NativeModelProvider::getLayoutGroups() const {
    std::lock_guard<std::mutex> lock(_mutex);
    return _layoutGroups;
}

bool NativeModelProvider::createLayoutGroup(const std::string& name) {
    if (name.empty() || name == "Default" || name == "All Models" || name == "Unassigned") {
        return false;
    }

    std::lock_guard<std::mutex> lock(_mutex);

    for (const auto& grp : _layoutGroups) {
        if (grp.name == name) {
            NSLog(@"NativeModelProvider: Layout group '%s' already exists", name.c_str());
            return false;
        }
    }

    LayoutGroupInfo info;
    info.name = name;
    _layoutGroups.push_back(info);

    NSLog(@"NativeModelProvider: Created layout group '%s'", name.c_str());
    return true;
}

bool NativeModelProvider::deleteLayoutGroup(const std::string& name) {
    if (name.empty() || name == "Default") {
        return false;
    }

    std::lock_guard<std::mutex> lock(_mutex);

    auto it = std::find_if(_layoutGroups.begin(), _layoutGroups.end(),
                           [&](const LayoutGroupInfo& g) { return g.name == name; });
    if (it == _layoutGroups.end()) {
        return false;
    }

    _layoutGroups.erase(it);

    // Reassign models from this group to "Unassigned"
    for (auto& [modelName, attrs] : _modelAttributes) {
        auto lgIt = attrs.find("LayoutGroup");
        if (lgIt != attrs.end() && lgIt->second == name) {
            lgIt->second = "Unassigned";
        }
    }

    NSLog(@"NativeModelProvider: Deleted layout group '%s'", name.c_str());
    return true;
}

bool NativeModelProvider::renameLayoutGroup(const std::string& oldName, const std::string& newName) {
    if (oldName.empty() || newName.empty() || oldName == "Default") {
        return false;
    }
    if (newName == "Default" || newName == "All Models" || newName == "Unassigned") {
        return false;
    }

    std::lock_guard<std::mutex> lock(_mutex);

    auto it = std::find_if(_layoutGroups.begin(), _layoutGroups.end(),
                           [&](const LayoutGroupInfo& g) { return g.name == oldName; });
    if (it == _layoutGroups.end()) {
        return false;
    }

    // Check new name doesn't already exist
    auto existIt = std::find_if(_layoutGroups.begin(), _layoutGroups.end(),
                                [&](const LayoutGroupInfo& g) { return g.name == newName; });
    if (existIt != _layoutGroups.end()) {
        return false;
    }

    it->name = newName;

    // Update model assignments
    for (auto& [modelName, attrs] : _modelAttributes) {
        auto lgIt = attrs.find("LayoutGroup");
        if (lgIt != attrs.end() && lgIt->second == oldName) {
            lgIt->second = newName;
        }
    }

    NSLog(@"NativeModelProvider: Renamed layout group '%s' to '%s'", oldName.c_str(), newName.c_str());
    return true;
}

bool NativeModelProvider::updateLayoutGroup(const std::string& name, const LayoutGroupInfo& info) {
    std::lock_guard<std::mutex> lock(_mutex);

    auto it = std::find_if(_layoutGroups.begin(), _layoutGroups.end(),
                           [&](const LayoutGroupInfo& g) { return g.name == name; });
    if (it == _layoutGroups.end()) {
        return false;
    }

    it->backgroundImage = info.backgroundImage;
    it->backgroundBrightness = info.backgroundBrightness;
    it->backgroundAlpha = info.backgroundAlpha;
    it->scaleBackgroundImage = info.scaleBackgroundImage;

    return true;
}

std::vector<std::string> NativeModelProvider::getModelsForLayoutGroup(const std::string& groupName) const {
    std::lock_guard<std::mutex> lock(_mutex);

    std::vector<std::string> result;

    for (const auto& name : _modelNames) {
        auto attrIt = _modelAttributes.find(name);
        std::string modelGroup;
        if (attrIt != _modelAttributes.end()) {
            auto lgIt = attrIt->second.find("LayoutGroup");
            if (lgIt != attrIt->second.end()) {
                modelGroup = lgIt->second;
            }
        }

        if (groupName == "All Models") {
            result.push_back(name);
        } else if (groupName == "Default") {
            if (modelGroup.empty() || modelGroup == "Default" || modelGroup == "All Previews") {
                result.push_back(name);
            }
        } else if (groupName == "Unassigned") {
            if (modelGroup.empty() || modelGroup == "Unassigned") {
                result.push_back(name);
            }
        } else {
            if (modelGroup == groupName || modelGroup == "All Previews") {
                result.push_back(name);
            }
        }
    }

    return result;
}

// MARK: - Face Definition Management

std::vector<std::string> NativeModelProvider::getFaceNames(const std::string& modelName) const {
    std::lock_guard<std::mutex> lock(_mutex);
    std::vector<std::string> names;
    auto it = _faceDefinitions.find(modelName);
    if (it != _faceDefinitions.end()) {
        for (const auto& face : it->second) {
            names.push_back(face.first);
        }
    }
    return names;
}

std::map<std::string, std::string> NativeModelProvider::getFaceDefinition(
    const std::string& modelName, const std::string& faceName) const {
    std::lock_guard<std::mutex> lock(_mutex);
    auto modelIt = _faceDefinitions.find(modelName);
    if (modelIt != _faceDefinitions.end()) {
        auto faceIt = modelIt->second.find(faceName);
        if (faceIt != modelIt->second.end()) {
            return faceIt->second;
        }
    }
    return {};
}

std::map<std::string, std::map<std::string, std::string>> NativeModelProvider::getAllFaceDefinitions(
    const std::string& modelName) const {
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _faceDefinitions.find(modelName);
    if (it != _faceDefinitions.end()) {
        return it->second;
    }
    return {};
}

bool NativeModelProvider::setFaceDefinition(const std::string& modelName, const std::string& faceName,
                                            const std::map<std::string, std::string>& definition) {
    std::lock_guard<std::mutex> lock(_mutex);
    _faceDefinitions[modelName][faceName] = definition;
    return true;
}

bool NativeModelProvider::setAllFaceDefinitions(const std::string& modelName,
    const std::map<std::string, std::map<std::string, std::string>>& definitions) {
    std::lock_guard<std::mutex> lock(_mutex);
    _faceDefinitions[modelName] = definitions;
    return true;
}

bool NativeModelProvider::deleteFaceDefinition(const std::string& modelName, const std::string& faceName) {
    std::lock_guard<std::mutex> lock(_mutex);
    auto modelIt = _faceDefinitions.find(modelName);
    if (modelIt == _faceDefinitions.end()) return false;
    auto faceIt = modelIt->second.find(faceName);
    if (faceIt == modelIt->second.end()) return false;
    modelIt->second.erase(faceIt);
    if (modelIt->second.empty()) {
        _faceDefinitions.erase(modelIt);
    }
    return true;
}

bool NativeModelProvider::renameFaceDefinition(const std::string& modelName,
                                               const std::string& oldName, const std::string& newName) {
    if (oldName.empty() || newName.empty() || oldName == newName) return false;
    std::lock_guard<std::mutex> lock(_mutex);
    auto modelIt = _faceDefinitions.find(modelName);
    if (modelIt == _faceDefinitions.end()) return false;
    auto faceIt = modelIt->second.find(oldName);
    if (faceIt == modelIt->second.end()) return false;
    if (modelIt->second.find(newName) != modelIt->second.end()) return false;
    auto data = std::move(faceIt->second);
    modelIt->second.erase(faceIt);
    modelIt->second[newName] = std::move(data);
    return true;
}

// MARK: - State Definition Management

std::vector<std::string> NativeModelProvider::getStateNames(const std::string& modelName) const {
    std::lock_guard<std::mutex> lock(_mutex);
    std::vector<std::string> names;
    auto it = _stateDefinitions.find(modelName);
    if (it != _stateDefinitions.end()) {
        for (const auto& state : it->second) {
            names.push_back(state.first);
        }
    }
    return names;
}

std::map<std::string, std::string> NativeModelProvider::getStateDefinition(
    const std::string& modelName, const std::string& stateName) const {
    std::lock_guard<std::mutex> lock(_mutex);
    auto modelIt = _stateDefinitions.find(modelName);
    if (modelIt != _stateDefinitions.end()) {
        auto stateIt = modelIt->second.find(stateName);
        if (stateIt != modelIt->second.end()) {
            return stateIt->second;
        }
    }
    return {};
}

std::map<std::string, std::map<std::string, std::string>> NativeModelProvider::getAllStateDefinitions(
    const std::string& modelName) const {
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _stateDefinitions.find(modelName);
    if (it != _stateDefinitions.end()) {
        return it->second;
    }
    return {};
}

bool NativeModelProvider::setStateDefinition(const std::string& modelName, const std::string& stateName,
                                             const std::map<std::string, std::string>& definition) {
    std::lock_guard<std::mutex> lock(_mutex);
    _stateDefinitions[modelName][stateName] = definition;
    return true;
}

bool NativeModelProvider::setAllStateDefinitions(const std::string& modelName,
    const std::map<std::string, std::map<std::string, std::string>>& definitions) {
    std::lock_guard<std::mutex> lock(_mutex);
    _stateDefinitions[modelName] = definitions;
    return true;
}

bool NativeModelProvider::deleteStateDefinition(const std::string& modelName, const std::string& stateName) {
    std::lock_guard<std::mutex> lock(_mutex);
    auto modelIt = _stateDefinitions.find(modelName);
    if (modelIt == _stateDefinitions.end()) return false;
    auto stateIt = modelIt->second.find(stateName);
    if (stateIt == modelIt->second.end()) return false;
    modelIt->second.erase(stateIt);
    if (modelIt->second.empty()) {
        _stateDefinitions.erase(modelIt);
    }
    return true;
}

bool NativeModelProvider::renameStateDefinition(const std::string& modelName,
                                                const std::string& oldName, const std::string& newName) {
    if (oldName.empty() || newName.empty() || oldName == newName) return false;
    std::lock_guard<std::mutex> lock(_mutex);
    auto modelIt = _stateDefinitions.find(modelName);
    if (modelIt == _stateDefinitions.end()) return false;
    auto stateIt = modelIt->second.find(oldName);
    if (stateIt == modelIt->second.end()) return false;
    if (modelIt->second.find(newName) != modelIt->second.end()) return false;
    auto data = std::move(stateIt->second);
    modelIt->second.erase(stateIt);
    modelIt->second[newName] = std::move(data);
    return true;
}

// --- Dimming Curve Management ---

std::map<std::string, std::map<std::string, std::string>> NativeModelProvider::getDimmingInfo(
    const std::string& modelName) const {
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _dimmingCurveInfo.find(modelName);
    if (it != _dimmingCurveInfo.end()) {
        return it->second;
    }
    return {};
}

bool NativeModelProvider::setDimmingInfo(const std::string& modelName,
    const std::map<std::string, std::map<std::string, std::string>>& dimmingInfo) {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_modelAttributes.find(modelName) == _modelAttributes.end()) return false;
    if (dimmingInfo.empty()) {
        _dimmingCurveInfo.erase(modelName);
    } else {
        _dimmingCurveInfo[modelName] = dimmingInfo;
    }
    return true;
}

void NativeModelProvider::parseLayoutGroupsFromXML(const std::string& xmlContent) {
    if (xmlContent.empty()) return;

    NSData* xmlData = [NSData dataWithBytes:xmlContent.c_str() length:xmlContent.size()];
    NSError* error = nil;
    NSXMLDocument* xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&error];
    if (error || !xmlDoc) return;

    NSArray<NSXMLElement*>* groupElements =
        [xmlDoc.rootElement nodesForXPath:@"//layoutGroups/layoutGroup" error:&error];
    if (error) return;

    // Note: _mutex is already held by loadModelsFromFile caller context
    _layoutGroups.clear();

    for (NSXMLElement* elem in groupElements) {
        NSXMLNode* nameAttr = [elem attributeForName:@"name"];
        if (!nameAttr || !nameAttr.stringValue) continue;

        LayoutGroupInfo info;
        info.name = [nameAttr.stringValue UTF8String];

        NSXMLNode* bgAttr = [elem attributeForName:@"backgroundImage"];
        if (bgAttr && bgAttr.stringValue) {
            info.backgroundImage = [bgAttr.stringValue UTF8String];
        }

        NSXMLNode* brightAttr = [elem attributeForName:@"backgroundBrightness"];
        if (brightAttr && brightAttr.stringValue) {
            info.backgroundBrightness = [brightAttr.stringValue intValue];
        }

        NSXMLNode* alphaAttr = [elem attributeForName:@"backgroundAlpha"];
        if (alphaAttr && alphaAttr.stringValue) {
            info.backgroundAlpha = [alphaAttr.stringValue intValue];
        }

        NSXMLNode* scaleAttr = [elem attributeForName:@"scaleImage"];
        if (scaleAttr && scaleAttr.stringValue) {
            info.scaleBackgroundImage = [scaleAttr.stringValue intValue] > 0;
        }

        _layoutGroups.push_back(info);
    }

    NSLog(@"NativeModelProvider: Loaded %zu layout groups from XML", _layoutGroups.size());
}

} // namespace xlEngine

#endif // XLIGHTS_NATIVE
