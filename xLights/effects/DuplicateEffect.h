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

class DuplicateEffect : public RenderableEffect
{
    public:
        DuplicateEffect(int id);
        virtual ~DuplicateEffect();
        virtual bool CanBeRandom() override {return false;}
#ifndef XLIGHTS_NATIVE
        virtual void Render(Effect *effect, const SettingsMap &settings, RenderBuffer &buffer) override;
#endif
#ifndef XLIGHTS_NATIVE
        virtual void SetDefaultParameters() override;
        virtual void SetPanelStatus(Model* cls) override;
#endif
        virtual bool CanRenderPartialTimeInterval() const override
        {
            return true;
        }
#ifndef XLIGHTS_NATIVE
        virtual std::list<std::string> CheckEffectSettings(const SettingsMap& settings, AudioManager* media, Model* model, Effect* eff, bool renderCache) override;
        static int GetLayersForModel(const wxString& model);
#endif

    protected:
#ifndef XLIGHTS_NATIVE
        virtual xlEffectPanel *CreatePanel(wxWindow *parent) override;
#endif
    private:
};
