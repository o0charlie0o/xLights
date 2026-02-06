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

#include <string>
#include <map>
class SequenceElements;

class StateEffect : public RenderableEffect
{
    public:
        StateEffect(int id);
        virtual ~StateEffect();
        virtual bool CanBeRandom() override {return false;}
#ifndef XLIGHTS_NATIVE
        virtual void SetDefaultParameters() override;
        virtual void SetPanelStatus(Model *cls) override;
#endif
#ifndef XLIGHTS_NATIVE
        virtual void Render(Effect *effect, const SettingsMap &settings, RenderBuffer &buffer) override;
#endif
        std::list<std::string> GetStates(Model* cls, std::string model);
        virtual void RenameTimingTrack(std::string oldname, std::string newname, Effect* effect) override;
#ifndef XLIGHTS_NATIVE
        virtual std::list<std::string> CheckEffectSettings(const SettingsMap& settings, AudioManager* media, Model* model, Effect* eff, bool renderCache) override;
#endif
        virtual bool CanRenderPartialTimeInterval() const override { return true; }
        std::list<std::string> GetStatesUsed(const SettingsMap& SettingsMap);
    protected:
#ifndef XLIGHTS_NATIVE
        virtual xlEffectPanel *CreatePanel(wxWindow *parent) override;
#endif
    private:
        void RenderState(RenderBuffer &buffer, SequenceElements *elements, const std::string &faceDefintion,
                         const std::string& Phoneme, const std::string& track, const std::string& mode, const std::string& colourmode, int fadeTime);
        std::string FindState(std::map<std::string, std::string>& map, std::string name);
        uint8_t CalculateAlpha(int fadeTime, int currentTime, int startTime, int endTime, RenderBuffer& buffer);
};
