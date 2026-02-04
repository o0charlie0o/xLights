/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "ServoEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

std::vector<EffectParameter> ServoEffect::parameters() const {
    return {
        EffectParameter::createFloat(
            "E_TEXTCTRL_Servo",
            "Start Position",
            0.0f, 0.0f, 100.0f,
            true  // Supports value curve
        ),
        EffectParameter::createFloat(
            "E_TEXTCTRL_EndValue",
            "End Position",
            0.0f, 0.0f, 100.0f,
            true
        ),
        EffectParameter::createInt(
            "E_SLIDER_Servo_Channel",
            "Channel",
            1, 1, 512,
            false
        ),
        EffectParameter::createBool(
            "E_CHECKBOX_16bit",
            "16-bit",
            false
        )
    };
}

void ServoEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    float startPosition = settings.getFloat("E_TEXTCTRL_Servo", 0.0f);
    float endPosition = settings.getFloat("E_TEXTCTRL_EndValue", 0.0f);
    int channel = settings.getInt("E_SLIDER_Servo_Channel", 1);
    bool is16bit = settings.getBool("E_CHECKBOX_16bit", false);

    // Calculate current position based on effect progress
    float progress = state.progress();
    float position = startPosition + (endPosition - startPosition) * progress;

    // Clamp position to 0-100 range
    position = std::clamp(position, 0.0f, 100.0f);

    // Convert position (0-100) to DMX value (0-65535 for 16-bit, 0-255 for 8-bit)
    uint16_t dmxValue;
    if (is16bit) {
        dmxValue = static_cast<uint16_t>(position * 65535.0f / 100.0f);
    } else {
        dmxValue = static_cast<uint16_t>(position * 255.0f / 100.0f);
    }

    // Create color from DMX value to represent the channel output
    // In a real implementation, this would write directly to DMX channels
    // For xlCore, we output as grayscale to represent intensity
    uint8_t msb = (dmxValue >> 8) & 0xFF;
    uint8_t lsb = dmxValue & 0xFF;

    // Output to the specified channel position in the buffer
    // Channel is 1-indexed, convert to 0-indexed pixel position
    int pixelX = (channel - 1) % ctx.width();
    int pixelY = (channel - 1) / ctx.width();

    if (pixelX >= 0 && pixelX < ctx.width() && pixelY >= 0 && pixelY < ctx.height()) {
        if (is16bit) {
            // For 16-bit, use MSB as the primary value
            Color c(msb, msb, msb);
            ctx.setPixel(pixelX, pixelY, c);

            // If there's a next channel for LSB, set it too
            int lsbX = pixelX + 1;
            int lsbY = pixelY;
            if (lsbX >= ctx.width()) {
                lsbX = 0;
                lsbY++;
            }
            if (lsbY < ctx.height()) {
                Color lsbColor(lsb, lsb, lsb);
                ctx.setPixel(lsbX, lsbY, lsbColor);
            }
        } else {
            // For 8-bit, just use the LSB
            Color c(lsb, lsb, lsb);
            ctx.setPixel(pixelX, pixelY, c);
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(ServoEffect)

} // namespace xlCore
