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

#include "RenderableEffect.h"

#define ARPEGGIO_STEPS_MIN 1
#define ARPEGGIO_STEPS_MAX 32
#define ARPEGGIO_FADEIN_MIN 0
#define ARPEGGIO_FADEIN_MAX 1000
#define ARPEGGIO_FADEOUT_MIN 0
#define ARPEGGIO_FADEOUT_MAX 1000
#define ARPEGGIO_OVERLAP_MIN 0
#define ARPEGGIO_OVERLAP_MAX 100

class ArpeggioEffect : public RenderableEffect
{
public:
    ArpeggioEffect(int id);
    virtual ~ArpeggioEffect();
    virtual bool CanBeRandom() override
    {
        return false;
    }
    virtual void Render(Effect* effect, const SettingsMap& settings, RenderBuffer& buffer) override;
    virtual void SetDefaultParameters() override;
    virtual wxString GetEffectString() override;
    virtual bool CanRenderPartialTimeInterval() const override
    {
        return true;
    }

    virtual double GetSettingVCMin(const std::string& name) const override
    {
        if (name == "E_VALUECURVE_Arpeggio_FadeIn")
            return ARPEGGIO_FADEIN_MIN;
        if (name == "E_VALUECURVE_Arpeggio_FadeOut")
            return ARPEGGIO_FADEOUT_MIN;
        if (name == "E_VALUECURVE_Arpeggio_Overlap")
            return ARPEGGIO_OVERLAP_MIN;
        return RenderableEffect::GetSettingVCMin(name);
    }
    virtual double GetSettingVCMax(const std::string& name) const override
    {
        if (name == "E_VALUECURVE_Arpeggio_FadeIn")
            return ARPEGGIO_FADEIN_MAX;
        if (name == "E_VALUECURVE_Arpeggio_FadeOut")
            return ARPEGGIO_FADEOUT_MAX;
        if (name == "E_VALUECURVE_Arpeggio_Overlap")
            return ARPEGGIO_OVERLAP_MAX;
        return RenderableEffect::GetSettingVCMax(name);
    }

protected:
    virtual void RemoveDefaults(const std::string& version, Effect* effect) override;
    virtual xlEffectPanel* CreatePanel(wxWindow* parent) override;
    virtual void SetPanelStatus(Model* cls) override;
    void SetPanelTimingTracks() const;
};
