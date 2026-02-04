/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "DMXEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <cmath>
#include <algorithm>
#include <sstream>

namespace xlCore {

std::vector<EffectParameter> DMXEffect::parameters() const {
    std::vector<EffectParameter> params;

    // Create parameters for all 48 DMX channels
    for (int i = 1; i <= DMX_CHANNELS; i++) {
        std::ostringstream sliderName, sliderLabel, invertName, invertLabel;
        sliderName << "E_SLIDER_DMX" << i;
        sliderLabel << "Channel " << i;
        invertName << "E_CHECKBOX_INVDMX" << i;
        invertLabel << "Invert " << i;

        params.push_back(EffectParameter::createInt(
            sliderName.str(),
            sliderLabel.str(),
            0, DMX_MIN, DMX_MAX,
            true  // Supports value curve
        ));

        params.push_back(EffectParameter::createBool(
            invertName.str(),
            invertLabel.str(),
            false
        ));
    }

    return params;
}

int DMXEffect::getDMXValue(const EffectSettings& settings, int channel) const {
    std::ostringstream sliderName, invertName;
    sliderName << "E_SLIDER_DMX" << channel;
    invertName << "E_CHECKBOX_INVDMX" << channel;

    int value = settings.getInt(sliderName.str(), 0);
    bool invert = settings.getBool(invertName.str(), false);

    if (invert) {
        value = 255 - value;
    }

    return std::clamp(value, DMX_MIN, DMX_MAX);
}

void DMXEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Determine how many pixels we can control
    int numPixels = ctx.width() * ctx.height();

    // For simplicity, treat the buffer as a linear array of pixels
    // Each pixel gets one DMX channel value as grayscale
    // (In the full xLights implementation, this would depend on model string type)

    // Mode 1: Single-color mode - each channel controls one pixel
    // Each DMX channel (1-48) maps to one pixel
    for (int channel = 1; channel <= DMX_CHANNELS && channel <= numPixels; channel++) {
        int value = getDMXValue(settings, channel);

        // Convert pixel index to x,y coordinates
        int pixelIndex = channel - 1;  // 0-indexed
        int x = pixelIndex % ctx.width();
        int y = pixelIndex / ctx.width();

        if (x < ctx.width() && y < ctx.height()) {
            // Output as grayscale
            Color color(static_cast<uint8_t>(value),
                       static_cast<uint8_t>(value),
                       static_cast<uint8_t>(value));
            ctx.setPixel(x, y, color);
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(DMXEffect)

} // namespace xlCore
