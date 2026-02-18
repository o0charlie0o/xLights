/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 **************************************************************/

#pragma once

// LegacyModelProviderAdapter: Wraps the real ModelManager as an IModelProvider.
//
// This adapter bridges the native RenderEngine (which depends on IModelProvider)
// with the real legacy ModelManager (which contains real Model objects with
// proper InitModel, node coordinates, channel mappings, etc.).
//
// Unlike NativeModelProvider (which parses XML into lightweight data),
// this adapter provides real Model* objects, making buildModelChannelMap()
// produce correct channel mappings that match the legacy rendering pipeline.

#include "../../engine/interfaces/IModelProvider.h"

class ModelManager;
class xLightsFrame;

namespace xlEngine {

class LegacyModelProviderAdapter : public IModelProvider {
public:
    explicit LegacyModelProviderAdapter(xLightsFrame* frame);
    ~LegacyModelProviderAdapter() override = default;

    // --- IModelProvider interface ---
    size_t getModelCount() const override;
    std::string getModelName(size_t index) const override;
    std::vector<std::string> getModelNames() const override;
    std::vector<std::string> getGroupNames() const override;
    Model* getModel(const std::string& name) override;
    const Model* getModel(const std::string& name) const override;
    std::vector<std::string> getSubmodels(const std::string& modelName) const override;
    std::map<std::string, std::string> getModelAttributes(const std::string& name) const override;

private:
    xLightsFrame* _frame;
};

} // namespace xlEngine
