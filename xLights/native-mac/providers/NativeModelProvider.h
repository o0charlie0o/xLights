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

/// A sequencer view definition.
struct SequenceViewInfo {
    std::string name;                    // View name (e.g., "Groups", "Outline")
    std::vector<std::string> models;     // Model names in this view
};

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

    // --- View Management ---

    /// Get all view names.
    /// @return Vector of view names.
    std::vector<std::string> getViewNames() const;

    /// Get a view by name.
    /// @param name View name.
    /// @return View info, or empty view if not found.
    SequenceViewInfo getView(const std::string& name) const;

    /// Get view count.
    /// @return Number of views.
    size_t getViewCount() const;

    /// Get view by index.
    /// @param index View index (0-based).
    /// @return View info, or empty view if index out of range.
    SequenceViewInfo getViewAtIndex(size_t index) const;

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

    // Override hasModel to check names list (default impl calls getModel which
    // returns nullptr in native standalone mode)
    bool hasModel(const std::string& name) const override;

    /// Get all stored XML attributes for a model.
    /// Available in both native and non-native builds when models are loaded from XML.
    /// @param name Model name.
    /// @return Map of attribute name → value, or empty map if not found.
    std::map<std::string, std::string> getModelAttributes(const std::string& name) const override;

private:
#ifndef XLIGHTS_NATIVE
    // Internal model storage for standalone operation (uses Model class)
    std::map<std::string, std::unique_ptr<Model>> _models;
#endif

    // Model names in order (for indexed access)
    std::vector<std::string> _modelNames;

    // Group names in XML document order
    std::vector<std::string> _groupNames;

    // Parsed XML attributes per model (name → {attr → value})
    std::map<std::string, std::map<std::string, std::string>> _modelAttributes;

#ifndef XLIGHTS_NATIVE
    // External ModelManager for transition period (not owned)
    ModelManager* _externalManager;
#endif

    // Show folder path
    std::string _showFolderPath;

    // Views
    std::vector<SequenceViewInfo> _views;

    // Thread safety
    mutable std::mutex _mutex;

    // Helper to rebuild model names list
    void rebuildModelNamesList();

    // Parse models from XML data
    bool parseModelsFromXML(const std::string& xmlContent);

    // Parse views from XML data
    void parseViewsFromXML(const std::string& xmlContent);
};

} // namespace xlEngine
