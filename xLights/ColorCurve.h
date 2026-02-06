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

#ifndef XLIGHTS_NATIVE
#include <wx/position.h>
#include <wx/string.h>
#include <wx/wx.h>
#include <wx/colour.h>
#include <wx/colourdata.h>
#endif

#include <list>
#include <string>
#include <cmath>
#include <cstdio>
#include <vector>
#include <sstream>

#include "Color.h"

#define CC_X_POINTS 100.0

class ccSortableColorPoint
{
public:

    static float Normalise(float v)
    {
        if (v < 0) v = 0;
        if (v > 1) v = 1;

        return std::round(v * CC_X_POINTS) / CC_X_POINTS;
    }

	float x; // 0-1 ... the start point of this point
	xlColor color; // the colour of the mid point of this
    bool donext;

    bool DoNext() const
    {
        return donext;
    }

    std::string Serialise() const
    {
        char buf[32];
        std::snprintf(buf, sizeof(buf), "%.3f", x);
        std::string res = "x=";
        res += buf;
        std::string c = (std::string)color;
        for (auto& ch : c) { if (ch == ',') ch = '@'; }
        res += "^c=" + c;
        return res;
    }

    void Deserialise(const std::string &s)
    {
        if (s.empty())
        {
            throw;
        }
        else if (s.find('^') == std::string::npos)
        {
            throw;
        }
        else
        {
            std::string remaining = s;
            while (!remaining.empty())
            {
                std::string token;
                size_t pos = remaining.find('^');
                if (pos == std::string::npos)
                {
                    token = remaining;
                    remaining.clear();
                }
                else
                {
                    token = remaining.substr(0, pos);
                    remaining = remaining.substr(pos + 1);
                }
                size_t eqPos = token.find('=');
                if (eqPos != std::string::npos)
                {
                    std::string k = token.substr(0, eqPos);
                    std::string v = token.substr(eqPos + 1);
                    SetSerialisedValue(k, v);
                }
            }
        }
    }

    void SetSerialisedValue(const std::string &k, const std::string &v)
    {
        if (k == "x")
        {
            x = ccSortableColorPoint::Normalise(std::stof(v));
        }
        else if (k == "c")
        {
            std::string c = v;
            for (auto& ch : c) { if (ch == '@') ch = ','; }
            color = xlColor(c);
        }
    }

    ccSortableColorPoint(const std::string& s)
    {
        Deserialise(s);
    }

    ccSortableColorPoint(float xx, xlColor c, bool dn = false)
    {
        x = Normalise(xx);
		color = c;
        donext = dn;
    }

    bool IsNear(float xx) const
    {
        return (x == Normalise(xx));
    }

    bool operator==(const ccSortableColorPoint& r) const
    {
        return x == r.x;
    }

    bool operator==(const float r) const
    {
        return x == Normalise(r);
    }

    bool operator<(const ccSortableColorPoint& r) const
    {
        return x < r.x;
    }

    bool operator<(const float r) const
    {
        return x < r;
    }

    bool operator<=(const ccSortableColorPoint& r) const
    {
        return x <= r.x;
    }

    bool operator<=(const float r) const
    {
        return x <= r;
    }

    bool operator>(const ccSortableColorPoint& r) const
    {
        return x > r.x;
    }
};

#define TC_TIME 0
#define TC_RIGHT 1
#define TC_DOWN 2
#define TC_LEFT 3
#define TC_UP 4
#define TC_RADIALIN 5
#define TC_RADIALOUT 6
#define TC_CW 7
#define TC_CCW 8

class ColorCurve
{
    std::list<ccSortableColorPoint> _values;
    std::string _type;
    std::string _id;
    bool _active;
    int _timecurve;

    void SetSerialisedValue(std::string k, std::string v);
    const ccSortableColorPoint* GetActivePoint(float x, float& duration) const;
    const ccSortableColorPoint* GetPriorActivePoint(float x, float& duration) const;
    const ccSortableColorPoint* GetNextActivePoint(float x, float& duration) const;

public:
    static std::string GetColorCurveFolder(const std::string& showFolder);
    static bool IsColorCurve(const std::string& s);
    bool IsOk() const { return !_id.empty(); }
    void NextTimeCurve(bool supportslinear, bool supportsradial);
    void SetValidTimeCurve(bool supportslinear, bool supportsradial);
    int GetTimeCurve() const { return _timecurve; }
    std::string GetId() const { return _id; }
    void SetId(const std::string& id) { _id = id; }
    ColorCurve();
    ColorCurve(const std::string& serialised);
    ColorCurve(const std::string& id, const std::string type, xlColor c = xlBLACK);
    std::string Serialise();
    void Deserialise(const std::string& s);
    void SetType(const std::string &type);
    xlColor GetValueAt(float offset) const;
    ccSortableColorPoint* GetPointAt(float offset);
#ifndef XLIGHTS_NATIVE
    wxBitmap GetImage(int x, int y, bool bars);
    static wxBitmap GetSolidColourImage(int x, int y, const wxColour& c);
#endif
    void SetActive(bool a) { _active = a; }
    bool IsActive() const { return _active && IsOk(); }
    void ToggleActive() { _active = !_active; }
    void SetValueAt(float offset, xlColor x);
    void DeletePoint(float offset);
    void Flip();
    bool IsSetPoint(float offset);
    int GetPointCount() const
    { return _values.size(); }
    std::string GetType() const
    { return _type; }
    std::list<ccSortableColorPoint> GetPoints() const
    { return _values; }
    bool NearPoint(float x);
    float FindMinPointLessThan(float point);
    float FindMaxPointGreaterThan(float point);
    void SetDefault(const xlColor& color);
#ifndef XLIGHTS_NATIVE
    void LoadXCC(const std::string& filename);
#endif
};

#ifndef XLIGHTS_NATIVE
wxDECLARE_EVENT(EVT_CC_CHANGED, wxCommandEvent);

class ColorCurveButton :
    public wxBitmapButton
{
    ColorCurve* _cc;
    std::string _color;
    void LeftClick(wxCommandEvent& event);
    void RightClick(wxContextMenuEvent& event);

public:
    ColorCurveButton(wxWindow *parent,
        wxWindowID id,
        const wxBitmap& bitmap,
        const wxPoint& pos = wxDefaultPosition,
        const wxSize& size = wxDefaultSize,
        long style = wxBU_AUTODRAW,
        const wxValidator& validator = wxDefaultValidator,
        const wxString& name = wxButtonNameStr);
    ~ColorCurveButton();
    virtual void SetValue(const wxString& value);
    ColorCurve* GetValue() const;
    void ToggleActive();
    void SetActive(bool active, bool notify = true);
    void UpdateState(bool notify = true);
    void UpdateBitmap();
    std::string GetColor() const { return _color; }
    void SetColor(std::string color, bool notify = true);
    void SetDefaultCC(const std::string& color);
    void NotifyChange(bool coloursPanelReload = false);
};
#endif
