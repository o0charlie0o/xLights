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

#include <vector>

#include "RenderableEffect.h"

#define KALEIDOSCOPE_X_MIN 0
#define KALEIDOSCOPE_X_MAX 100

#define KALEIDOSCOPE_Y_MIN 0
#define KALEIDOSCOPE_Y_MAX 100

#define KALEIDOSCOPE_SIZE_MIN 2
#define KALEIDOSCOPE_SIZE_MAX 100

#define KALEIDOSCOPE_ROTATION_MIN 0
#define KALEIDOSCOPE_ROTATION_MAX 359

#ifndef XLIGHTS_NATIVE
struct KaleidoscopeEdge
{
    wxPoint _p1;
    wxPoint _p2;
    KaleidoscopeEdge(const wxPoint &p1, const wxPoint& p2) { _p1 = p1; _p2 = p2; }
};
#endif

class KaleidoscopeEffect : public RenderableEffect
{
    public:
        KaleidoscopeEffect(int id);
        virtual ~KaleidoscopeEffect();
        virtual bool CanBeRandom() override {return false;}
#ifndef XLIGHTS_NATIVE
        virtual void Render(Effect *effect, const SettingsMap &settings, RenderBuffer &buffer) override;
#endif
        virtual bool SupportsLinearColorCurves(const SettingsMap &SettingsMap) const override { return false; }
#ifndef XLIGHTS_NATIVE
        virtual void SetDefaultParameters() override;
        virtual std::list<std::string> CheckEffectSettings(const SettingsMap& settings, AudioManager* media, Model* model, Effect* eff, bool renderCache) override;
#endif

        virtual double GetSettingVCMin(const std::string& name) const override
        {
            if (name == "E_VALUECURVE_Kaleidoscope_X")
                return KALEIDOSCOPE_X_MIN;
            if (name == "E_VALUECURVE_Kaleidoscope_Y")
                return KALEIDOSCOPE_Y_MIN;
            if (name == "E_VALUECURVE_Kaleidoscope_Size")
                return KALEIDOSCOPE_SIZE_MIN;
            if (name == "E_VALUECURVE_Kaleidoscope_Rotation")
                return KALEIDOSCOPE_ROTATION_MIN;
            return RenderableEffect::GetSettingVCMin(name);
        }

        virtual double GetSettingVCMax(const std::string& name) const override
        {
            if (name == "E_VALUECURVE_Kaleidoscope_X")
                return KALEIDOSCOPE_X_MAX;
            if (name == "E_VALUECURVE_Kaleidoscope_Y")
                return KALEIDOSCOPE_Y_MAX;
            if (name == "E_VALUECURVE_Kaleidoscope_Size")
                return KALEIDOSCOPE_SIZE_MAX;
            if (name == "E_VALUECURVE_Kaleidoscope_Rotation")
                return KALEIDOSCOPE_ROTATION_MAX;
            return RenderableEffect::GetSettingVCMax(name);
        }

    protected:
#ifndef XLIGHTS_NATIVE
        virtual xlEffectPanel *CreatePanel(wxWindow *parent) override;
        bool KaleidoscopeDone(const std::vector<std::vector<bool>>& current);
        std::pair<int, int> GetSourceLocation(int x, int y, const KaleidoscopeEdge& edge, int width, int height);
#endif
};
