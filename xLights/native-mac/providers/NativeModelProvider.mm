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
    return {}; // Not implemented in native standalone mode
}

Model* NativeModelProvider::getModel(const std::string& name) {
    return nullptr; // Model class not available in native build
}

const Model* NativeModelProvider::getModel(const std::string& name) const {
    return nullptr;
}

std::vector<std::string> NativeModelProvider::getSubmodels(const std::string& modelName) const {
    return {};
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

    // Parse XML to extract model names only
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
    for (NSXMLElement* elem in modelElements) {
        NSXMLNode* nameAttr = [elem attributeForName:@"name"];
        if (nameAttr && nameAttr.stringValue) {
            _modelNames.push_back([nameAttr.stringValue UTF8String]);
        }
    }

    NSLog(@"NativeModelProvider: Loaded %zu model names from XML", _modelNames.size());
    return true;
}

void NativeModelProvider::clearModels() {
    std::lock_guard<std::mutex> lock(_mutex);
    _modelNames.clear();
    _showFolderPath.clear();
}

std::string NativeModelProvider::getShowFolderPath() const {
    std::lock_guard<std::mutex> lock(_mutex);
    return _showFolderPath;
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

} // namespace xlEngine

#endif // XLIGHTS_NATIVE
