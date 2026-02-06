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
#include "../RenderBuffer.h"
#include <wx/gdicmn.h>
#include <wx/colour.h>
#include <wx/dcmemory.h>
class wxString;
class PathDrawingContext;
#else
// Forward declare a simple Point struct for the native build
struct TendrilPoint {
    int x;
    int y;
    TendrilPoint(int x_ = 0, int y_ = 0) : x(x_), y(y_) {}
};
class NativePathDrawingContext;
#endif

#define TENDRIL_MOVEMENT_MIN 0
#define TENDRIL_MOVEMENT_MAX 20

#define TENDRIL_THICKNESS_MIN 1
#define TENDRIL_THICKNESS_MAX 20

#define TENDRIL_MANUALX_MIN 0
#define TENDRIL_MANUALX_MAX 100

#define TENDRIL_MANUALY_MIN 0
#define TENDRIL_MANUALY_MAX 100

#define TENDRIL_OFFSETX_MIN -100
#define TENDRIL_OFFSETX_MAX 100

#define TENDRIL_OFFSETY_MIN -100
#define TENDRIL_OFFSETY_MAX 100

class TendrilNode
{
    public:
    float x;
    float y;
    float vx;
    float vy;

    TendrilNode(float x_, float y_);
#ifndef XLIGHTS_NATIVE
    wxPoint* Point();
#else
    TendrilPoint* Point();
#endif
};

class ATendril
{
    float _friction;
	size_t _size;
	float _dampening;
	float _tension;
	float _spring;
	size_t _thickness;
    int _lastWidth = -1;
    int _lastHeight = -1;

    std::list<TendrilNode*> _nodes;

	public:

	~ATendril();
#ifndef XLIGHTS_NATIVE
	ATendril(float friction, int size, float dampening, float tension, float spring, const wxPoint& start);
    void Update(wxPoint* target, int tunemovement, int width, int height);
	void Draw(PathDrawingContext* gc, xlColor colour, int thickness);
	wxPoint* LastLocation();
#else
	ATendril(float friction, int size, float dampening, float tension, float spring, const TendrilPoint& start);
    void Update(TendrilPoint* target, int tunemovement, int width, int height);
	void Draw(NativePathDrawingContext* gc, xlColor colour, int thickness);
	TendrilPoint* LastLocation();
#endif
};

class Tendril
{
	std::list<ATendril*> _tendrils;

	public:

	~Tendril();
#ifndef XLIGHTS_NATIVE
	Tendril(float friction, int trails, int size, float dampening, float tension, float springbase, float springincr, const wxPoint& start);
	void UpdateRandomMove(int tunemovement, int width, int height);
    void Update(wxPoint* target, int tunemovement, size_t width, size_t height);
    void Update(int x, int y, int tunemovement, size_t width, size_t height);
    void Draw(PathDrawingContext* gc, xlColor colour, int thickness);
#else
	Tendril(float friction, int trails, int size, float dampening, float tension, float springbase, float springincr, const TendrilPoint& start);
	void UpdateRandomMove(int tunemovement, int width, int height);
    void Update(TendrilPoint* target, int tunemovement, size_t width, size_t height);
    void Update(int x, int y, int tunemovement, size_t width, size_t height);
    void Draw(NativePathDrawingContext* gc, xlColor colour, int thickness);
#endif
};

class TendrilEffect : public RenderableEffect
{
public:
    TendrilEffect(int id);
    virtual ~TendrilEffect();
    virtual void Render(Effect* effect, const SettingsMap& settings, RenderBuffer& buffer) override;
#ifndef XLIGHTS_NATIVE
    virtual void SetDefaultParameters() override;
#endif
#ifdef LINUX
    virtual bool CanRenderOnBackgroundThread(Effect* effect, const SettingsMap& settings, RenderBuffer& buffer) override
    {
        return false;
    }
#endif
    virtual bool AppropriateOnNodes() const override
    {
        return false;
    }
    virtual bool SupportsRenderCache(const SettingsMap& settings) const override
    {
        return true;
    }

    virtual double GetSettingVCMin(const std::string& name) const override
    {
        if (name == "E_VALUECURVE_Tendril_TuneMovement")
            return TENDRIL_MOVEMENT_MIN;
        if (name == "E_VALUECURVE_Tendril_Thickness")
            return TENDRIL_THICKNESS_MIN;
        if (name == "E_VALUECURVE_Tendril_ManualX")
            return TENDRIL_MANUALX_MIN;
        if (name == "E_VALUECURVE_Tendril_ManualY")
            return TENDRIL_MANUALY_MIN;
        if (name == "E_VALUECURVE_Tendril_XOffset")
            return TENDRIL_OFFSETX_MIN;
        if (name == "E_VALUECURVE_Tendril_YOffset")
            return TENDRIL_OFFSETY_MIN;
        return RenderableEffect::GetSettingVCMin(name);
    }

    virtual double GetSettingVCMax(const std::string& name) const override
    {
        if (name == "E_VALUECURVE_Tendril_TuneMovement")
            return TENDRIL_MOVEMENT_MAX;
        if (name == "E_VALUECURVE_Tendril_Thickness")
            return TENDRIL_THICKNESS_MAX;
        if (name == "E_VALUECURVE_Tendril_ManualX")
            return TENDRIL_MANUALX_MAX;
        if (name == "E_VALUECURVE_Tendril_ManualY")
            return TENDRIL_MANUALY_MAX;
        if (name == "E_VALUECURVE_Tendril_XOffset")
            return TENDRIL_OFFSETX_MAX;
        if (name == "E_VALUECURVE_Tendril_YOffset")
            return TENDRIL_OFFSETY_MAX;
        return RenderableEffect::GetSettingVCMax(name);
    }

protected:
#ifndef XLIGHTS_NATIVE
    virtual xlEffectPanel* CreatePanel(wxWindow* parent) override;
#endif
    virtual bool needToAdjustSettings(const std::string& version) override;
    virtual void adjustSettings(const std::string& version, Effect* effect, bool removeDefaults = true) override;
    int EncodeMovement(std::string movement);
    void Render(RenderBuffer& buffer,
                const std::string& movement, int tunemovement, int movementSpeed, int thickness,
                float friction, float dampening,
                float tension, int trails, int length, int xoffset, int yoffset, int manualx, int manualy);
};
