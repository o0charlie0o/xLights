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

// ModelEngine: Pure C++ API for model management, decoupled from wxWidgets.
// Part of the xlEngine abstraction layer (Phase 2: Update Engines).
//
// This API uses IModelProvider interface to access model data, allowing it
// to work with both the legacy wxWidgets UI (via ModelManagerAdapter) and
// future native AppKit UI (via NativeModelProvider).
//
// All data exchange uses std::string, std::vector, std::map, and plain structs.
// No wxWidgets types are exposed in the public API.
//
// See DECOUPLING_GUIDE.md for architectural context.

#include <string>
#include <vector>
#include <map>
#include <mutex>
#include <memory>
#include <cstdint>

#include "EngineTypes.h"
#include "interfaces/IModelProvider.h"

class Model;
class ModelManager;

namespace xlEngine {

struct NodeCoord {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
    int bufX = 0;
    int bufY = 0;
    uint32_t actChannel = 0;
    uint32_t channelCount = 0;
    uint32_t stringNum = 0;
};

// Generate node coordinates from model XML attributes.
// Used by both ModelEngine (for preview) and NativeRenderCoordinator (for rendering).
std::vector<NodeCoord> generateNodesFromAttributes(
    const std::map<std::string, std::string>& attrs);

struct ModelInfo {
    std::string name;
    std::string type;           // DisplayAs value (e.g. "Custom", "SingleLine", "Matrix")
    std::string description;
    uint32_t nodeCount = 0;
    uint32_t channelCount = 0;
    uint32_t firstChannel = 0;
    uint32_t lastChannel = 0;
    int defaultBufferWi = 0;
    int defaultBufferHt = 0;
    std::string startChannel;
    std::string layoutGroup;
    std::string controllerName;
    std::string controllerProtocol;
    int controllerPort = 0;
    int smartRemote = 0;        // 0=None, 1=A, 2=B, 3=C, etc.
    std::string smartRemoteType;
    bool isActive = true;
    bool isGroupModel = false;
    std::map<std::string, std::string> properties;
};

struct SubmodelInfo {
    std::string name;
    std::string fullName;       // "ParentModel/SubmodelName"
    uint32_t nodeCount = 0;
    uint32_t channelCount = 0;
};

struct SubmodelDefinition {
    std::string name;
    bool isRanges = true;       // true = "ranges", false = "subbuffer"
    bool vertical = false;      // layout: "vertical" or "horizontal"
    std::string bufferStyle;    // e.g. "Default", "Keep XY", "Stacked Strands"
    std::string subBuffer;      // sub-buffer definition (when isRanges == false)
    std::vector<std::string> strands;  // line0, line1, ... (when isRanges == true)
};

struct ModelGroupInfo {
    std::string name;
    std::vector<std::string> modelNames;
    std::string defaultBufferStyle;
};

enum class ModelChangeType {
    Added,
    Removed,
    Modified,
    Renamed,
    PropertyChanged
};

struct ModelChangeEvent {
    ModelChangeType type;
    std::string modelName;
    std::string oldName;        // only set for Renamed
    std::string propertyKey;    // only set for PropertyChanged
    std::string propertyValue;  // only set for PropertyChanged
};

// Callback interface for model change events.
// All callbacks are invoked on the thread that triggers them.
// Implementers must handle thread safety in their callback bodies.
class ModelEngineListener {
public:
    virtual ~ModelEngineListener() = default;

    virtual void onModelAdded(const ModelChangeEvent& event) {}
    virtual void onModelRemoved(const ModelChangeEvent& event) {}
    virtual void onModelModified(const ModelChangeEvent& event) {}
    virtual void onModelRenamed(const ModelChangeEvent& event) {}
    virtual void onModelPropertyChanged(const ModelChangeEvent& event) {}
    virtual void onError(const std::string& message) {}
};

// Forward declaration for extended operations adapter
class ModelManagerAdapter;

// ModelEngine provides a pure C++ API for model management.
//
// Thread safety: All public methods are safe to call from any thread.
// The engine uses internal locking where necessary. Callbacks may be
// invoked from any thread; callers must dispatch to their own UI
// thread if needed.
//
// This class uses IModelProvider for model access, allowing it to work
// with different backend implementations:
// - ModelManagerAdapter: Wraps legacy ModelManager for wxWidgets UI
// - NativeModelProvider: Native macOS implementation (future)
class ModelEngine {
public:
    /// Constructs a ModelEngine using the given model provider.
    /// @param provider Pointer to the model provider. The provider must
    ///                 outlive this engine. The engine does NOT take ownership.
    explicit ModelEngine(IModelProvider* provider);

#ifndef XLIGHTS_NATIVE
    /// Legacy constructor for backward compatibility during transition.
    /// Creates an internal ModelManagerAdapter to wrap the ModelManager.
    /// @deprecated Use the IModelProvider* constructor instead.
    explicit ModelEngine(ModelManager& modelManager);
#endif

    ~ModelEngine();

    ModelEngine(const ModelEngine&) = delete;
    ModelEngine& operator=(const ModelEngine&) = delete;

    // --- Listener management ---
    //
    // Thread safety: addListener/removeListener are thread-safe.
    // Callbacks may fire from any thread; the listener must dispatch
    // to its own UI thread if needed.
    void addListener(ModelEngineListener* listener);
    void removeListener(ModelEngineListener* listener);

    // --- Enumeration ---

    std::vector<std::string> getModelNames() const;
    std::vector<std::string> getModelNamesExcludingGroups() const;
    std::vector<std::string> getGroupNames() const;

    // --- Model Metadata ---

    bool hasModel(const std::string& name) const;
    ModelInfo getModel(const std::string& name) const;
    std::map<std::string, std::string> getModelProperties(const std::string& name) const;
    std::string getModelProperty(const std::string& name, const std::string& key, const std::string& defaultValue = "") const;

    // --- Node Data ---

    std::vector<NodeCoord> getModelNodes(const std::string& name) const;
    uint32_t getModelNodeCount(const std::string& name) const;
    uint32_t getModelChannelCount(const std::string& name) const;

    // --- Model CRUD ---

    OperationResult createModel(const std::string& type, const std::string& name,
                                const std::map<std::string, std::string>& properties = {});
    OperationResult deleteModel(const std::string& name);
    OperationResult renameModel(const std::string& oldName, const std::string& newName);
    OperationResult updateModelProperty(const std::string& name, const std::string& key, const std::string& value);

    // --- Smart Remote ---

    int getSmartRemote(const std::string& name) const;
    std::string getSmartRemoteType(const std::string& name) const;
    OperationResult setSmartRemote(const std::string& name, int smartRemote);
    OperationResult setSmartRemoteType(const std::string& name, const std::string& type);

    // --- Submodels ---

    std::vector<SubmodelInfo> getSubmodels(const std::string& modelName) const;
    bool hasSubmodel(const std::string& modelName, const std::string& submodelName) const;
    SubmodelDefinition getSubmodelDefinition(const std::string& modelName, const std::string& submodelName) const;
    OperationResult setSubmodel(const std::string& modelName, const std::string& submodelName,
                                const SubmodelDefinition& definition);
    OperationResult deleteSubmodel(const std::string& modelName, const std::string& submodelName);
    OperationResult renameSubmodel(const std::string& modelName, const std::string& oldName,
                                   const std::string& newName);

    // --- Groups ---

    std::vector<ModelGroupInfo> getModelGroups() const;
    ModelGroupInfo getModelGroup(const std::string& groupName) const;
    std::vector<std::string> getGroupsContainingModel(const std::string& modelName) const;

    // --- Group CRUD ---

    OperationResult createModelGroup(const std::string& groupName,
                                     const std::vector<std::string>& modelNames = {});
    OperationResult deleteModelGroup(const std::string& groupName);
    OperationResult renameModelGroup(const std::string& oldName, const std::string& newName);
    OperationResult addModelToGroup(const std::string& groupName, const std::string& modelName);
    OperationResult removeModelFromGroup(const std::string& groupName, const std::string& modelName);

    // --- Position & Geometry ---

    struct BoundingBox {
        float minX = 0, maxX = 0;
        float minY = 0, maxY = 0;
        float minZ = 0, maxZ = 0;
    };

    BoundingBox getModelBounds(const std::string& name) const;

    // Called by the existing UI layer to notify the engine of changes
    // that occurred through the old code path. This allows the engine
    // to forward them to any registered listeners.
    void notifyModelChanged(const ModelChangeEvent& event);

private:
    Model* findModel(const std::string& name) const;
    ModelInfo buildModelInfo(const Model* model) const;

    // Returns the adapter for extended operations (write operations).
    // Returns nullptr if provider is not a ModelManagerAdapter.
    ModelManagerAdapter* getAdapter() const;

    IModelProvider* _provider;

#ifndef XLIGHTS_NATIVE
    // Owned adapter when using the legacy ModelManager& constructor.
    // null when using the IModelProvider* constructor directly.
    std::unique_ptr<ModelManagerAdapter> _ownedAdapter;
#endif

    mutable std::mutex _listenerMutex;
    std::vector<ModelEngineListener*> _listeners;
};

} // namespace xlEngine
