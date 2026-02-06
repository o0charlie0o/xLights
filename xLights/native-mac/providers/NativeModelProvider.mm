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

    // Parse group names first (from modelGroups section)
    NSArray<NSXMLElement*>* groupElements = [xmlDoc.rootElement nodesForXPath:@"//modelGroups/modelGroup" error:nil];
    for (NSXMLElement* elem in groupElements) {
        NSXMLNode* nameAttr = [elem attributeForName:@"name"];
        if (nameAttr && nameAttr.stringValue) {
            _groupNames.push_back([nameAttr.stringValue UTF8String]);
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
            _modelAttributes[name] = std::move(attrs);
        }
    }

    // Parse views
    parseViewsFromXML([content UTF8String]);

    NSLog(@"NativeModelProvider: Loaded %zu groups + %zu models with attributes from XML",
          _groupNames.size(), _modelNames.size());
    return true;
}

bool NativeModelProvider::hasModel(const std::string& name) const {
    std::lock_guard<std::mutex> lock(_mutex);
    return _modelAttributes.find(name) != _modelAttributes.end();
}

std::map<std::string, std::string> NativeModelProvider::getModelAttributes(const std::string& name) const {
    std::lock_guard<std::mutex> lock(_mutex);
    auto it = _modelAttributes.find(name);
    if (it != _modelAttributes.end()) {
        return it->second;
    }
    return {};
}

void NativeModelProvider::clearModels() {
    std::lock_guard<std::mutex> lock(_mutex);
    _modelNames.clear();
    _groupNames.clear();
    _modelAttributes.clear();
    _views.clear();
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

} // namespace xlEngine

#endif // XLIGHTS_NATIVE
