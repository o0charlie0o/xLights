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

// Common types shared across all xlEngine APIs.

#include <string>

namespace xlEngine {

// Result type for operations that can fail.
struct OperationResult {
    bool success = false;
    std::string message;
};

} // namespace xlEngine
