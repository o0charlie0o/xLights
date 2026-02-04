#pragma once

/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// IModelProvider: Abstract interface for model access.
//
// This interface defines the contract for accessing model data from the
// rendering engine, decoupled from any specific implementation (ModelManager,
// xLightsFrame, etc.). It uses only standard C++ types to ensure the
// interface can be used without wxWidgets dependencies.
//
// Part of the xlEngine abstraction layer (Phase 1: Create Abstract Interfaces).
// See DECOUPLING_GUIDE.md for architectural context.
//
// Thread Safety:
// All methods must be safe to call from any thread. Implementations are
// responsible for providing appropriate synchronization. The native macOS
// UI may call these methods from the main thread while the render engine
// operates on background threads.
//
// Usage:
// - Engines (ModelEngine, RenderEngine, etc.) depend on this interface
// - Native providers implement this interface wrapping platform-specific code
// - wxWidgets provider wraps existing ModelManager for legacy UI support

#include <cstddef>
#include <string>
#include <vector>

// Forward declaration - Model class is defined elsewhere
// Engines receive Model* for direct rendering access while we transition.
// Long-term, this dependency should be replaced with pure data structures.
class Model;

namespace xlEngine {

/// Abstract interface for accessing model data.
///
/// This interface provides read-only access to the model collection. It does
/// not support model creation, deletion, or modification - those operations
/// should go through ModelEngine which handles change notifications and
/// maintains consistency.
class IModelProvider {
public:
    virtual ~IModelProvider() = default;

    // --- Model Count ---

    /// Returns the total number of models (including groups).
    /// @return Number of models in the collection.
    virtual size_t getModelCount() const = 0;

    // --- Model Name Access ---

    /// Returns the name of the model at the given index.
    /// @param index Zero-based index into the model collection.
    /// @return Model name, or empty string if index is out of range.
    virtual std::string getModelName(size_t index) const = 0;

    /// Returns all model names (including groups).
    /// @return Vector of model names. Order is not guaranteed to be stable
    ///         across calls or between sessions.
    virtual std::vector<std::string> getModelNames() const = 0;

    /// Returns names of all model groups.
    /// @return Vector of group names.
    virtual std::vector<std::string> getGroupNames() const = 0;

    // --- Model Lookup ---

    /// Returns the Model pointer for the given name.
    /// @param name Model name (case-sensitive).
    /// @return Pointer to the Model, or nullptr if not found.
    /// @note The returned pointer is owned by the underlying implementation.
    ///       Do not delete it. The pointer may become invalid after model
    ///       collection changes.
    virtual Model* getModel(const std::string& name) = 0;

    /// Returns the Model pointer for the given name (const version).
    /// @param name Model name (case-sensitive).
    /// @return Const pointer to the Model, or nullptr if not found.
    virtual const Model* getModel(const std::string& name) const = 0;

    // --- Submodel Access ---

    /// Returns names of all submodels for a given model.
    /// @param modelName Name of the parent model.
    /// @return Vector of submodel names. Returns empty vector if model not
    ///         found or has no submodels.
    virtual std::vector<std::string> getSubmodels(const std::string& modelName) const = 0;

    // --- Convenience Methods ---

    /// Checks if a model with the given name exists.
    /// @param name Model name to check.
    /// @return true if the model exists, false otherwise.
    virtual bool hasModel(const std::string& name) const {
        return getModel(name) != nullptr;
    }
};

} // namespace xlEngine
