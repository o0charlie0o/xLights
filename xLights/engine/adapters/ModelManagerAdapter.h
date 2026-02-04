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

// ModelManagerAdapter: Implements IModelProvider by wrapping ModelManager.
//
// This adapter allows ModelEngine (and other engines) to use the IModelProvider
// interface while still having access to the underlying ModelManager for
// write operations during the transition period.
//
// Part of the xlEngine abstraction layer (Phase 2: Update Engines).
// See DECOUPLING_GUIDE.md for architectural context.
//
// Usage:
// - Legacy wxWidgets code creates ModelManager as before
// - Creates ModelManagerAdapter wrapping the ModelManager
// - Passes adapter to ModelEngine as IModelProvider*
// - ModelEngine uses interface for all operations

#include "../interfaces/IModelProvider.h"
#include <string>

class ModelManager;
class Model;

namespace xlEngine {

/// Adapter that wraps ModelManager to implement IModelProvider.
///
/// This class provides backward compatibility during the transition from
/// direct ModelManager usage to interface-based design. It implements the
/// read-only IModelProvider interface and additionally exposes write operations
/// needed by ModelEngine.
///
/// Thread Safety:
/// All methods delegate to ModelManager which has its own mutex protection.
class ModelManagerAdapter : public IModelProvider {
public:
    /// Constructs an adapter wrapping the given ModelManager.
    /// @param manager Reference to the ModelManager to wrap. The manager must
    ///                outlive this adapter.
    explicit ModelManagerAdapter(ModelManager& manager);

    ~ModelManagerAdapter() override = default;

    // Non-copyable
    ModelManagerAdapter(const ModelManagerAdapter&) = delete;
    ModelManagerAdapter& operator=(const ModelManagerAdapter&) = delete;

    // --- IModelProvider Implementation ---

    size_t getModelCount() const override;
    std::string getModelName(size_t index) const override;
    std::vector<std::string> getModelNames() const override;
    std::vector<std::string> getGroupNames() const override;
    Model* getModel(const std::string& name) override;
    const Model* getModel(const std::string& name) const override;
    std::vector<std::string> getSubmodels(const std::string& modelName) const override;

    // --- Extended Operations for ModelEngine ---
    //
    // These methods are not part of IModelProvider but are needed by ModelEngine
    // for write operations during the transition period. Native implementations
    // will provide these through a different mechanism.

    /// Creates a new model with default settings.
    /// @param type Model type (e.g., "SingleLine", "Matrix", "Custom")
    /// @param startChannel Starting channel for the model
    /// @return Pointer to the created model, or nullptr on failure.
    ///         The caller does NOT own this pointer - it's managed by ModelManager.
    Model* createDefaultModel(const std::string& type, const std::string& startChannel);

    /// Adds a model to the manager.
    /// @param model Pointer to the model to add. ModelManager takes ownership.
    void addModel(Model* model);

    /// Deletes a model by name.
    /// @param name Name of the model to delete.
    /// @return true if the model was deleted, false if not found.
    bool deleteModel(const std::string& name);

    /// Renames a model.
    /// @param oldName Current name of the model.
    /// @param newName New name for the model.
    /// @return true if renamed successfully, false otherwise.
    bool renameModel(const std::string& oldName, const std::string& newName);

    /// Returns names of all groups containing the specified model.
    /// @param model Pointer to the model to check.
    /// @return Vector of group names containing the model.
    std::vector<std::string> getGroupsContainingModel(Model* model) const;

    /// Provides direct access to the underlying ModelManager.
    /// @note This is provided for legacy code that still needs direct access.
    ///       New code should use interface methods instead.
    ModelManager& getModelManager() { return _manager; }
    const ModelManager& getModelManager() const { return _manager; }

private:
    ModelManager& _manager;
};

} // namespace xlEngine
