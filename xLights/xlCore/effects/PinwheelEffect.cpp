/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "PinwheelEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../XLMath.h"

#include <cmath>
#include <algorithm>

namespace xlCore {

// Parameter range constants
constexpr int PINWHEEL_ARMS_MIN = 1;
constexpr int PINWHEEL_ARMS_MAX = 20;
constexpr int PINWHEEL_TWIST_MIN = -360;
constexpr int PINWHEEL_TWIST_MAX = 360;
constexpr int PINWHEEL_THICKNESS_MIN = 0;
constexpr int PINWHEEL_THICKNESS_MAX = 100;
constexpr int PINWHEEL_SPEED_MIN = 0;
constexpr int PINWHEEL_SPEED_MAX = 50;
constexpr int PINWHEEL_X_MIN = -100;
constexpr int PINWHEEL_X_MAX = 100;
constexpr int PINWHEEL_Y_MIN = -100;
constexpr int PINWHEEL_Y_MAX = 100;
constexpr int PINWHEEL_ARMSIZE_MIN = 0;
constexpr int PINWHEEL_ARMSIZE_MAX = 400;
constexpr int PINWHEEL_OFFSET_MIN = 0;
constexpr int PINWHEEL_OFFSET_MAX = 360;

std::vector<EffectParameter> PinwheelEffect::parameters() const {
    std::vector<std::string> styleChoices = {"none", "3D", "3D Inverted", "Sweep"};

    return {
        EffectParameter::createInt("E_SLIDER_Pinwheel_Arms", "Arms", 3, PINWHEEL_ARMS_MIN, PINWHEEL_ARMS_MAX),
        EffectParameter::createInt("E_SLIDER_Pinwheel_Twist", "Twist", 0, PINWHEEL_TWIST_MIN, PINWHEEL_TWIST_MAX, true),
        EffectParameter::createInt("E_SLIDER_Pinwheel_Thickness", "Thickness", 0, PINWHEEL_THICKNESS_MIN, PINWHEEL_THICKNESS_MAX, true),
        EffectParameter::createBool("E_CHECKBOX_Pinwheel_Rotation", "Clockwise", true),
        EffectParameter::createInt("E_SLIDER_Pinwheel_Speed", "Speed", 10, PINWHEEL_SPEED_MIN, PINWHEEL_SPEED_MAX, true),
        EffectParameter::createInt("E_SLIDER_PinwheelXC", "Center X", 0, PINWHEEL_X_MIN, PINWHEEL_X_MAX, true),
        EffectParameter::createInt("E_SLIDER_PinwheelYC", "Center Y", 0, PINWHEEL_Y_MIN, PINWHEEL_Y_MAX, true),
        EffectParameter::createInt("E_SLIDER_Pinwheel_ArmSize", "Arm Size", 100, PINWHEEL_ARMSIZE_MIN, PINWHEEL_ARMSIZE_MAX, true),
        EffectParameter::createInt("E_SLIDER_Pinwheel_Offset", "Offset", 0, PINWHEEL_OFFSET_MIN, PINWHEEL_OFFSET_MAX, true),
        EffectParameter::createChoice("E_CHOICE_Pinwheel_3D", "3D Style", "none", styleChoices)
    };
}

PinwheelEffect::Pinwheel3DType PinwheelEffect::to3DType(const std::string& str) {
    if (str == "3D") return Pinwheel3DType::ThreeD;
    if (str == "3D Inverted") return Pinwheel3DType::ThreeDInverted;
    if (str == "Sweep") return Pinwheel3DType::Sweep;
    return Pinwheel3DType::None;
}

void PinwheelEffect::adjustColor(Pinwheel3DType type, Color& color, bool allowAlpha, float round) const {
    switch (type) {
        case Pinwheel3DType::ThreeD:
            if (allowAlpha) {
                color = color.withAlpha(static_cast<uint8_t>(255.0f - 255.0f * std::abs(round - 0.5f) / 0.5f));
            } else {
                float value = 1.0f - color.value() * std::abs(round - 0.5f) / 0.5f;
                color = color.withValue(value);
            }
            break;

        case Pinwheel3DType::ThreeDInverted:
            if (allowAlpha) {
                color = color.withAlpha(static_cast<uint8_t>(255.0f * std::abs(round - 0.5f) / 0.5f));
            } else {
                float value = color.value() * std::abs(round - 0.5f) / 0.5f;
                color = color.withValue(value);
            }
            break;

        case Pinwheel3DType::Sweep:
            if (allowAlpha) {
                color = color.withAlpha(static_cast<uint8_t>(255.0f * round));
            } else {
                float value = color.value() * round;
                color = color.withValue(value);
            }
            break;

        default:
            break;
    }
}

void PinwheelEffect::drawArm(RenderContext& ctx, int baseDegrees, int maxRadius, int twist,
                             int xcAdj, int ycAdj, const Color& armColor, Pinwheel3DType type,
                             float round, bool allowAlpha) const {
    int xc = ctx.width() / 2;
    int yc = ctx.height() / 2;
    xc = xc + ((xcAdj * xc) / 100);
    yc = yc + ((ycAdj * yc) / 100);

    Color color = armColor;
    adjustColor(type, color, allowAlpha, round);

    if (maxRadius != 0) {
        for (float r = 0.0f; r <= maxRadius; r += 0.5f) {
            int degreesTwist = static_cast<int>((r / maxRadius) * twist);
            int degrees = baseDegrees + degreesTwist;
            float phi = math::toRadians(static_cast<float>(degrees));
            int x = static_cast<int>(r * std::cos(phi) + xc);
            int y = static_cast<int>(r * std::sin(phi) + yc);

            ctx.setPixel(x, y, color);
        }
    }
}

void PinwheelEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    int pinwheelArms = settings.getInt("E_SLIDER_Pinwheel_Arms", 3);
    int pinwheelTwist = settings.getInt("E_SLIDER_Pinwheel_Twist", 0);
    int pinwheelThickness = settings.getInt("E_SLIDER_Pinwheel_Thickness", 0);
    bool pinwheelRotation = settings.getBool("E_CHECKBOX_Pinwheel_Rotation", true);
    int pspeed = settings.getInt("E_SLIDER_Pinwheel_Speed", 10);
    int xcAdj = settings.getInt("E_SLIDER_PinwheelXC", 0);
    int ycAdj = settings.getInt("E_SLIDER_PinwheelYC", 0);
    int pinwheelArmSize = settings.getInt("E_SLIDER_Pinwheel_ArmSize", 100);
    int poffset = settings.getInt("E_SLIDER_Pinwheel_Offset", 0);
    std::string pinwheel3D = settings.get("E_CHOICE_Pinwheel_3D", "none");

    Pinwheel3DType pw3dType = to3DType(pinwheel3D);
    bool allowAlpha = ctx.allowAlpha();

    // Calculate timing
    int frameNum = state.frameIndex;
    float pos = static_cast<float>(frameNum * pspeed) / static_cast<float>(PINWHEEL_SPEED_MAX);

    int degreesPerArm = 1;
    if (pinwheelArms > 0) degreesPerArm = 360 / pinwheelArms;
    float armsize = pinwheelArmSize / 100.0f;

    // Build simple palette
    std::vector<Color> palette = {
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 0),
        Color(255, 0, 255),
        Color(0, 255, 255)
    };
    size_t colorCount = palette.size();

    int xc = std::max(ctx.width(), ctx.height()) / 2;

    for (int a = 1; a <= pinwheelArms; a++) {
        int colorIdx = a % colorCount;

        int baseDegrees;
        if (pinwheelRotation) {
            baseDegrees = static_cast<int>((a - 1) * degreesPerArm + pos + poffset);
        } else {
            baseDegrees = static_cast<int>((a - 1) * degreesPerArm - pos + poffset);
        }

        float tmax = (pinwheelThickness / 100.0f) * degreesPerArm / 2.0f;
        for (float t = baseDegrees - tmax; t <= baseDegrees + tmax; t += 1.0f) {
            float round = (t - baseDegrees + tmax) / (2.0f * tmax + 1.0f);
            drawArm(ctx, static_cast<int>(t), static_cast<int>(xc * armsize), pinwheelTwist,
                   xcAdj, ycAdj, palette[colorIdx], pw3dType, round, allowAlpha);
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(PinwheelEffect)

} // namespace xlCore
