/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "WaveEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../Math.h"

#include <cmath>
#include <algorithm>
#include <cstdlib>

namespace xlCore {

// Parameter range constants
constexpr int WAVE_NUMBER_MIN = 1;
constexpr int WAVE_NUMBER_MAX = 3600;
constexpr int WAVE_THICKNESS_MIN = 1;
constexpr int WAVE_THICKNESS_MAX = 100;
constexpr int WAVE_HEIGHT_MIN = 0;
constexpr int WAVE_HEIGHT_MAX = 100;
constexpr int WAVE_SPEED_MIN = 0;
constexpr int WAVE_SPEED_MAX = 5000;
constexpr int WAVE_YOFFSET_MIN = -100;
constexpr int WAVE_YOFFSET_MAX = 100;

std::vector<EffectParameter> WaveEffect::parameters() const {
    std::vector<std::string> typeChoices = {"Sine", "Triangle", "Square", "Decaying Sine", "Fractal/ivy"};
    std::vector<std::string> fillChoices = {"None", "Rainbow", "Palette"};
    std::vector<std::string> dirChoices = {"Left to Right", "Right to Left"};

    return {
        EffectParameter::createChoice("E_CHOICE_Wave_Type", "Wave Type", "Sine", typeChoices),
        EffectParameter::createChoice("E_CHOICE_Fill_Colors", "Fill Colors", "None", fillChoices),
        EffectParameter::createInt("E_SLIDER_Number_Waves", "Number of Waves", 900, WAVE_NUMBER_MIN, WAVE_NUMBER_MAX, true),
        EffectParameter::createInt("E_SLIDER_Thickness_Percentage", "Thickness", 5, WAVE_THICKNESS_MIN, WAVE_THICKNESS_MAX, true),
        EffectParameter::createInt("E_SLIDER_Wave_Height", "Height", 50, WAVE_HEIGHT_MIN, WAVE_HEIGHT_MAX, true),
        EffectParameter::createInt("E_TEXTCTRL_Wave_Speed", "Speed", 1000, WAVE_SPEED_MIN, WAVE_SPEED_MAX, true),
        EffectParameter::createInt("E_SLIDER_Wave_YOffset", "Y Offset", 0, WAVE_YOFFSET_MIN, WAVE_YOFFSET_MAX, true),
        EffectParameter::createChoice("E_CHOICE_Wave_Direction", "Direction", "Right to Left", dirChoices),
        EffectParameter::createBool("E_CHECKBOX_Mirror_Wave", "Mirror", false)
    };
}

WaveEffect::WaveType WaveEffect::parseWaveType(const std::string& str) {
    if (str == "Triangle") return WaveType::Triangle;
    if (str == "Square") return WaveType::Square;
    if (str == "Decaying Sine") return WaveType::DecaySine;
    if (str == "Fractal/ivy") return WaveType::IvyFractal;
    return WaveType::Sine;
}

WaveEffect::FillColorType WaveEffect::parseFillColor(const std::string& str) {
    if (str == "Rainbow") return FillColorType::Rainbow;
    if (str == "Palette") return FillColorType::Palette;
    return FillColorType::None;
}

void WaveEffect::prepareForRender(const EffectSettings& settings) {
    m_waveBuffer.clear();
    m_lastNumWaves = 0;
    m_lastWidth = 0;
}

void WaveEffect::cleanupAfterRender() {
    m_waveBuffer.clear();
}

void WaveEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Get parameters
    WaveType waveType = parseWaveType(settings.get("E_CHOICE_Wave_Type", "Sine"));
    FillColorType fillColor = parseFillColor(settings.get("E_CHOICE_Fill_Colors", "None"));
    bool mirrorWave = settings.getBool("E_CHECKBOX_Mirror_Wave", false);
    int numberWaves = settings.getInt("E_SLIDER_Number_Waves", 900);
    int thicknessWave = settings.getInt("E_SLIDER_Thickness_Percentage", 5);
    int waveHeight = settings.getInt("E_SLIDER_Wave_Height", 50);
    float wspeed = static_cast<float>(settings.getInt("E_TEXTCTRL_Wave_Speed", 1000)) / 100.0f;
    int yoffset = settings.getInt("E_SLIDER_Wave_YOffset", 0);
    bool waveDirection = settings.get("E_CHOICE_Wave_Direction", "Right to Left") == "Left to Right";

    int bufferWi = ctx.width();
    int bufferHt = ctx.height();

    if (numberWaves == 0) numberWaves = 1;

    double waveYOffset = (bufferHt / 2.0) * (yoffset * 0.01);
    int roundedWaveYOffset = static_cast<int>(std::round(waveYOffset));

    // Simple palette
    std::vector<Color> palette = {
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255)
    };
    Color baseColor = palette[0];

    int frameNum = state.frameIndex;
    float stateVal = static_cast<float>(frameNum) * wspeed;

    double yc = bufferHt / 2.0;
    double r = yc;

    // Handle decaying sine
    if (waveType == WaveType::DecaySine) {
        r -= stateVal / 4.0;
        if (r < 0) r = 0;
    }

    // Handle fractal/ivy wave initialization
    if (waveType == WaveType::IvyFractal) {
        int neededSize = numberWaves * bufferWi;
        if (static_cast<int>(m_waveBuffer.size()) != neededSize ||
            m_lastNumWaves != numberWaves || m_lastWidth != bufferWi) {
            m_waveBuffer.resize(neededSize);
            int delay = 0;
            int delta = 0;
            for (int x1 = 0; x1 < neededSize; ++x1) {
                m_waveBuffer[x1] = (delay-- > 0) ? m_waveBuffer[x1 - 1] + delta : static_cast<int>(2 * yc);
                if (m_waveBuffer[x1] >= 2 * bufferHt) {
                    delta = -2;
                    m_waveBuffer[x1] = 2 * bufferHt - 1;
                    if (delay > 1) delay = 1;
                }
                if (m_waveBuffer[x1] < 0) {
                    delta = 2;
                    m_waveBuffer[x1] = 0;
                    if (delay > 1) delay = 1;
                }
                if (delay < 1) {
                    delta = (std::rand() % 7) - 3;
                    delay = 2 + (std::rand() % 3);
                }
            }
            m_lastNumWaves = numberWaves;
            m_lastWidth = bufferWi;
        }
    }

    double degreePerX = static_cast<double>(numberWaves) / bufferWi;

    for (int x = 0; x < bufferWi; x++) {
        double degree;
        if (!waveDirection)
            degree = x * degreePerX + stateVal;
        else
            degree = x * degreePerX - stateVal;
        double radian = degree * math::DEG_TO_RAD;

        double degreeMinus1;
        if (!waveDirection)
            degreeMinus1 = (x - 1) * degreePerX + stateVal;
        else
            degreeMinus1 = (x - 1) * degreePerX - stateVal;
        double radianMinus1 = degreeMinus1 * math::DEG_TO_RAD;

        double sinrad = std::sin(radian);
        double sinradMinus1 = std::sin(radianMinus1);

        int ystart;
        if (waveType == WaveType::Triangle) {
            double waves = (static_cast<double>(numberWaves) / 180.0) / 5.0;
            int amp = bufferHt * waveHeight / 100;
            int xx = waveDirection ? bufferWi - x - 1 : x;

            if (amp == 0) {
                ystart = 0;
            } else {
                ystart = (bufferHt - amp) / 2 +
                         std::abs(static_cast<int>((stateVal / 10 + xx) * waves) % (2 * amp) - amp);
            }
            if (ystart > bufferHt - 1) ystart = bufferHt - 1;
        } else if (waveType == WaveType::IvyFractal) {
            int istate = static_cast<int>(std::round(stateVal));
            int effX = (waveDirection ? x : bufferWi - x - 1) + bufferWi * (istate / 2 / bufferWi);
            if (effX >= numberWaves * bufferWi) continue;
            if (!waveDirection) effX = numberWaves * bufferWi - effX - 1;
            bool ok = waveDirection ? (effX <= istate / 2) : (effX >= numberWaves * bufferWi - istate / 2 - 1);
            if (!ok) continue;
            ystart = m_waveBuffer[effX] / 2;
        } else {
            ystart = static_cast<int>(r * (waveHeight / 100.0) * sinrad + yc);
        }

        if (x >= 0 && x < bufferWi && ystart >= 0 && ystart < bufferHt) {
            int y1 = static_cast<int>(ystart - (r * (thicknessWave / 100.0)));
            int y2 = static_cast<int>(ystart + (r * (thicknessWave / 100.0)));
            if (y2 <= y1) y2 = y1 + 1;

            if (waveType == WaveType::Square) {
                bool signChange = (std::signbit(sinrad) != std::signbit(sinradMinus1));
                if (signChange) {
                    y1 = static_cast<int>(yc - yc * (waveHeight / 100.0));
                    y2 = static_cast<int>(yc + yc * (waveHeight / 100.0));
                } else if (sinrad > 0.0) {
                    y1 = static_cast<int>(yc + 1 + yc * (waveHeight / 100.0) * ((100.0 - thicknessWave) / 100.0));
                    y2 = static_cast<int>(yc + yc * (waveHeight / 100.0));
                } else {
                    y1 = static_cast<int>(yc - yc * (waveHeight / 100.0));
                    y2 = static_cast<int>(yc - yc * (waveHeight / 100.0) * ((100.0 - thicknessWave) / 100.0));
                }

                y1 = std::clamp(y1, 0, bufferHt - 1);
                y2 = std::clamp(y2, 1, bufferHt);
                if (y2 <= y1) y2 = y1 + 1;
            }

            int y1mirror = static_cast<int>(yc + (yc - y1));
            int y2mirror = static_cast<int>(yc + (yc - y2));
            double deltay = y2 - y1;

            for (int y = y1; y <= y2; y++) {
                int adjustedY = y + roundedWaveYOffset;
                if (adjustedY < 0 || adjustedY >= bufferHt) continue;

                Color color;
                if (fillColor == FillColorType::None) {
                    color = baseColor;
                } else if (fillColor == FillColorType::Rainbow) {
                    float hue = static_cast<float>(y - y1) / static_cast<float>(deltay);
                    color = Color::fromHSV(hue, 1.0f, 1.0f);
                } else { // Palette
                    float pos = static_cast<float>(y - y1) / static_cast<float>(deltay);
                    int idx1 = static_cast<int>(pos * (palette.size() - 1));
                    int idx2 = std::min(idx1 + 1, static_cast<int>(palette.size()) - 1);
                    float t = pos * (palette.size() - 1) - idx1;
                    color = palette[idx1].lerp(palette[idx2], t);
                }
                ctx.setPixel(x, adjustedY, color);
            }

            if (mirrorWave) {
                if (y1mirror < y2mirror) {
                    y1 = y1mirror;
                    y2 = y2mirror;
                } else {
                    y2 = y1mirror;
                    y1 = y2mirror;
                }

                for (int y = y1; y <= y2; y++) {
                    int adjustedY = y + roundedWaveYOffset;
                    if (adjustedY < 0 || adjustedY >= bufferHt) continue;

                    Color color;
                    if (fillColor == FillColorType::None) {
                        color = baseColor;
                    } else if (fillColor == FillColorType::Rainbow) {
                        float hue = static_cast<float>(y - y1) / static_cast<float>(deltay);
                        color = Color::fromHSV(hue, 1.0f, 1.0f);
                    } else {
                        float pos = static_cast<float>(y - y1) / static_cast<float>(deltay);
                        int idx1 = static_cast<int>(pos * (palette.size() - 1));
                        int idx2 = std::min(idx1 + 1, static_cast<int>(palette.size()) - 1);
                        float t = pos * (palette.size() - 1) - idx1;
                        color = palette[idx1].lerp(palette[idx2], t);
                    }
                    ctx.setPixel(x, adjustedY, color);
                }
            }
        }
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(WaveEffect)

} // namespace xlCore
