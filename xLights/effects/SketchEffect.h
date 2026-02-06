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
#include <list>

#ifndef XLIGHTS_NATIVE
class wxImage;
class SketchAssistPanel;
class SketchPanel;
#endif
class SketchEffectSketch;

class SketchEffect : public RenderableEffect
{
public:
    SketchEffect( int id );
    virtual ~SketchEffect();

    bool CanBeRandom() override
    {
        return false;
    }
    void Render( Effect* effect, const SettingsMap& settings, RenderBuffer& buffer ) override;

    bool needToAdjustSettings( const std::string& version ) override;
    void adjustSettings( const std::string& version, Effect* effect, bool removeDefaults = true ) override;

    virtual double GetSettingVCMin(const std::string& name) const override;
    virtual double GetSettingVCMax(const std::string& name) const override;

#ifndef XLIGHTS_NATIVE
    void SetDefaultParameters() override;
    std::list<std::string> CheckEffectSettings( const SettingsMap& settings, AudioManager* media, Model* model, Effect* eff, bool renderCache ) override;
    virtual std::list<std::string> GetFileReferences(Model* model, const SettingsMap& SettingsMap) const override;
    virtual bool CleanupFileLocations(xLightsFrame* frame, SettingsMap& SettingsMap) override;

    AssistPanel* GetAssistPanel(wxWindow* parent, xLightsFrame* xl_frame) override;
    bool HasAssistPanel() override
    {
        return true;
    }
#endif

protected:
#ifndef XLIGHTS_NATIVE
    void RemoveDefaults( const std::string& version, Effect* effect ) override;
#endif
#ifndef XLIGHTS_NATIVE
    xlEffectPanel* CreatePanel( wxWindow* parent ) override;

    void renderSketch(const SketchEffectSketch& sketch,
                      wxImage& img, double progress,
                      double drawPercentage, int lineThickness, bool hasMotion, double motionPercentage,
                      const xlColorVector& colors);

    void updateSketchAssistBackground() const;

    SketchPanel* m_panel = nullptr;
    SketchAssistPanel* m_sketchAssistPanel = nullptr;
#endif
};
