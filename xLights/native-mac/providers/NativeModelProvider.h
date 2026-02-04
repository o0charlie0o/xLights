/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

// NativeModelProvider: Native macOS implementation of IModelProvider.
//
// This provider manages models without wxWidgets dependencies, loading model
// data from .xLights XML files using native macOS APIs (NSXMLParser).
//
// Part of the native macOS rebuild (Phase 3: Create Native Provider Implementations).
// See DECOUPLING_GUIDE.md for architectural context.
//
// Thread Safety:
// All methods are protected by an internal mutex for thread-safe access.
// The native macOS UI may call from the main thread while render operations
// occur on background threads.
//
// Usage:
// - Create a NativeModelProvider instance
// - Call loadModelsFromFile() with path to .xLights or rgbeffects.xml
// - Pass to ModelEngine as IModelProvider*
// - Models are owned by this provider - do not delete returned Model pointers

#include "../../engine/interfaces/IModelProvider.h"

#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

// Forward declarations
class Model;
#ifndef XLIGHTS_NATIVE
class ModelManager;
#endif

namespace xlEngine {

/// Native macOS implementation of IModelProvider.
///
/// This class provides model management without wxWidgets runtime dependencies.
/// It parses model XML using native APIs and creates Model instances directly.
/// For the transition period, it uses ModelManager internally but without
/// requiring wxWidgets UI components.
///
/// Long-term, this will be replaced with a fully native model storage system.
class NativeModelProvider : public IModelProvider {
public:
    /// Constructs an empty NativeModelProvider.
    NativeModelProvider();

#ifndef XLIGHTS_NATIVE
    /// Constructs a NativeModelProvider that wraps an existing ModelManager.
    /// This allows gradual transition from wxWidgets-based model loading.
    /// @param manager Reference to existing ModelManager. Must outlive this provider.
    explicit NativeModelProvider(ModelManager& manager);
#endif

    ~NativeModelProvider() override;

    // Non-copyable
    NativeModelProvider(const NativeModelProvider&) = delete;
    NativeModelProvider& operator=(const NativeModelProvider&) = delete;

    // --- IModelProvider Implementation ---

    size_t getModelCount() const override;
    std::string getModelName(size_t index) const override;
    std::vector<std::string> getModelNames() const override;
    std::vector<std::string> getGroupNames() const override;
    Model* getModel(const std::string& name) override;
    const Model* getModel(const std::string& name) const override;
    std::vector<std::string> getSubmodels(const std::string& modelName) const override;

    // --- Native Model Loading ---

    /// Loads models from an xLights show folder.
    /// @param showFolderPath Path to the show folder containing rgbeffects.xml.
    /// @return true if models were loaded successfully.
    bool loadModelsFromShowFolder(const std::string& showFolderPath);

    /// Loads models from an XML file (rgbeffects.xml or similar).
    /// @param xmlFilePath Full path to the XML file containing model definitions.
    /// @return true if models were loaded successfully.
    bool loadModelsFromFile(const std::string& xmlFilePath);

    /// Clears all loaded models.
    void clearModels();

    /// Returns the path to the currently loaded show folder.
    /// @return Show folder path, or empty string if no folder loaded.
    std::string getShowFolderPath() const;

    // --- Model Management (for future native implementation) ---

    /// Adds a model to the collection. The provider takes ownership.
    /// @param model Pointer to model to add. Provider takes ownership.
    /// @return true if added successfully.
    bool addModel(std::unique_ptr<Model> model);

    /// Removes a model by name.
    /// @param name Name of model to remove.
    /// @return true if model was found and removed.
    bool removeModel(const std::string& name);

    /// Returns whether this provider is using an external ModelManager.
    /// @return true if wrapping an external ModelManager.
#ifndef XLIGHTS_NATIVE
    bool isUsingExternalManager() const { return _externalManager != nullptr; }
#else
    bool isUsingExternalManager() const { return false; }
#endif

private:
#ifndef XLIGHTS_NATIVE
    // Internal model storage for standalone operation (uses Model class)
    std::map<std::string, std::unique_ptr<Model>> _models;
#endif

    // Model names in order (for indexed access)
    std::vector<std::string> _modelNames;

#ifndef XLIGHTS_NATIVE
    // External ModelManager for transition period (not owned)
    ModelManager* _externalManager;
#endif

    // Show folder path
    std::string _showFolderPath;

    // Thread safety
    mutable std::mutex _mutex;

    // Helper to rebuild model names list
    void rebuildModelNamesList();

    // Parse models from XML data
    bool parseModelsFromXML(const std::string& xmlContent);
};

} // namespace xlEngine
