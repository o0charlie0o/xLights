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
#include <wx/tokenzr.h>
#endif

#include "StateEffect.h"
#ifndef XLIGHTS_NATIVE
#include "StatePanel.h"
#endif
#include "../RenderBuffer.h"
#include "../UtilClasses.h"
#include "../UtilFunctions.h"
#include "../models/Model.h"
#include "../models/ModelGroup.h"
#include "../models/SubModel.h"
#include "../sequencer/Effect.h"
#include "../sequencer/SequenceElements.h"

#ifndef XLIGHTS_NATIVE
#include "../../include/state-16.xpm"
#include "../../include/state-64.xpm"
#endif

#ifndef XLIGHTS_NATIVE
#include <log4cpp/Category.hh>
#endif
#include <sstream>
#include <algorithm>

StateEffect::StateEffect(int id) :
    RenderableEffect(id, "State",
#ifndef XLIGHTS_NATIVE
    state_16, state_64, state_64, state_64, state_64
#else
    nullptr, nullptr, nullptr, nullptr, nullptr
#endif
    ) {
    // ctor
}

StateEffect::~StateEffect() {
    // dtor
}

#ifndef XLIGHTS_NATIVE
std::list<std::string> StateEffect::CheckEffectSettings(const SettingsMap& settings, AudioManager* media, Model* model, Effect* eff, bool renderCache) {
    std::list<std::string> res = RenderableEffect::CheckEffectSettings(settings, media, model, eff, renderCache);

    SubModel* sm = dynamic_cast<SubModel*>(model);
    if (sm != nullptr) {
        res.push_back(wxString::Format("    ERR: State effect on SubModel will not render properly. Model '%s', Start %s", model->GetFullName(), FORMATTIME(eff->GetStartTimeMS())).ToStdString());
    }

    // -Buffer not rotated
    wxString bufferTransform = settings.Get("B_CHOICE_BufferTransform", "None");

    if (bufferTransform != "None") {
        res.push_back(wxString::Format("    WARN: State effect with transformed buffer '%s' may not render correctly. Model '%s', Start %s", model->GetFullName(), bufferTransform, FORMATTIME(eff->GetStartTimeMS())).ToStdString());
    }

    wxString timing = settings.Get("E_CHOICE_State_TimingTrack", "");
    wxString state = settings.Get("E_CHOICE_State_State", "");

    // - Face chosen or specific phoneme
    if (state == "" && timing == "") {
        res.push_back(wxString::Format("    ERR: State effect with no timing selected. Model '%s', Start %s", model->GetFullName(), FORMATTIME(eff->GetStartTimeMS())).ToStdString());
    } else if (timing != "" && GetTiming(timing.ToStdString()) == nullptr) {
        res.push_back(wxString::Format("    ERR: State effect with unknown timing (%s) selected. Model '%s', Start %s", timing, model->GetFullName(), FORMATTIME(eff->GetStartTimeMS())).ToStdString());
    }
    return res;
}
#endif

std::list<std::string> StateEffect::GetStatesUsed(const SettingsMap& SettingsMap) {
    std::list<std::string> res;
    auto state = SettingsMap.Get("E_CHOICE_State_StateDefinition", "");
    if (state != "") {
        res.emplace_back(state);
    }
    return res;
}

#ifndef XLIGHTS_NATIVE
void StateEffect::SetPanelStatus(Model* cls) {
    StatePanel* fp = (StatePanel*)panel;
    if (fp == nullptr) {
        return;
    }

    auto lastTiming = fp->Choice_State_TimingTrack->GetStringSelection();
    auto lastState = fp->Choice_StateDefinitonChoice->GetStringSelection();
    fp->Choice_State_TimingTrack->Clear();
    fp->Choice_StateDefinitonChoice->Clear();

    for (const auto& it : wxSplit(GetTimingTracks(1), '|')) {
        fp->Choice_State_TimingTrack->Append(it);
    }

    if (fp->Choice_State_TimingTrack->GetCount() > 0) {
        fp->Choice_State_TimingTrack->SetSelection(0);
    }

    if (cls != nullptr) {
        Model* m = cls;
        if (cls->GetDisplayAs() == "ModelGroup") {
            m = ((ModelGroup*)cls)->GetFirstModel();
        }

        std::list<std::string> used;
        if (m != nullptr) {
            for (const auto& it : m->GetStateInfo()) {
                if (std::find(begin(used), end(used), it.first) == end(used)) {
                    fp->Choice_StateDefinitonChoice->Append(it.first);
                    used.push_back(it.first);
                }
            }
        }
    }

    if (lastTiming != "")
        fp->Choice_State_TimingTrack->SetStringSelection(lastTiming);
    if (lastState != "") {
        fp->Choice_StateDefinitonChoice->SetStringSelection(lastState);
    }

    if (fp->Choice_StateDefinitonChoice->GetSelection() == -1 && fp->Choice_StateDefinitonChoice->GetCount() > 0) {
        fp->Choice_StateDefinitonChoice->SetSelection(0);
    }

    fp->SetEffect(this, cls);
}
#endif

#ifndef XLIGHTS_NATIVE
std::list<std::string> StateEffect::GetStates(Model* cls, std::string model) {
    std::list<std::string> res;

    if (cls != nullptr) {
        Model* m = cls;
        if (cls->GetDisplayAs() == "ModelGroup") {
            m = ((ModelGroup*)cls)->GetFirstModel();
        }

        if (m != nullptr) {
            for (const auto& it : m->GetStateInfo()) {
                if (model == it.first) {
                    for (const auto& it2 : it.second) {
                        if (EndsWith(it2.first, "-Name") && it2.second != "" && std::find(begin(res), end(res), it2.second) == end(res)) {
                            res.push_back(it2.second);
                        }
                    }
                }
            }
        }
    }

    return res;
}
#endif

#ifndef XLIGHTS_NATIVE
xlEffectPanel* StateEffect::CreatePanel(wxWindow* parent) {
    return new StatePanel(parent);
}

void StateEffect::SetDefaultParameters() {
    StatePanel* sp = (StatePanel*)panel;
    if (sp == nullptr) {
        return;
    }

    sp->SetEffect(nullptr, nullptr);
    SetChoiceValue(sp->Choice_State_Mode, "Default");
    SetChoiceValue(sp->Choice_State_Color, "Graduate");
    sp->Choice_StateDefinitonChoice->SetSelection(0);
    SetRadioValue(sp->RadioButton1);
    sp->ValidateWindow();
}
#endif

void StateEffect::RenameTimingTrack(std::string oldname, std::string newname, Effect* effect) {
    std::string timing = effect->GetSettings().Get("E_CHOICE_State_TimingTrack", "");

    if (timing == oldname) {
        effect->GetSettings()["E_CHOICE_State_TimingTrack"] = newname;
    }
}

#ifndef XLIGHTS_NATIVE
void StateEffect::Render(Effect* effect, const SettingsMap& SettingsMap, RenderBuffer& buffer) {
    RenderState(buffer,
                effect->GetParentEffectLayer()->GetParentElement()->GetSequenceElements(),
                SettingsMap.Get("CHOICE_State_StateDefinition", ""),
                SettingsMap["CHOICE_State_State"],
                SettingsMap["CHOICE_State_TimingTrack"],
                SettingsMap["CHOICE_State_Mode"],
                SettingsMap["CHOICE_State_Color"],
                SettingsMap.GetInt("SLIDER_State_Fade_Time", 0));
}

std::string StateEffect::FindState(std::map<std::string, std::string>& map, std::string name) {
    for (const auto& it2 : map) {
        if (EndsWith(it2.first, "-Name") && it2.second == name) {
            return it2.first.substr(0, it2.first.size() - 5);
        }
    }

    return "";
}

static const std::string &findKey(const std::map<std::string, std::string> &m, const std::string &k, const std::string &dv = xlEMPTY_STRING) {
    const auto &v = m.find(k);
    if (v == m.end()) {
        return dv;
    }
    return v->second;
}

static std::list<int> const& findNodeKey(std::map<std::string, std::list<int>> const& m, std::string const& k) {
    const auto& v = m.find(k);
    if (v == m.end()) {
        static std::list<int> emptyList;
        return emptyList;
    }
    return v->second;
}

void StateEffect::RenderState(RenderBuffer& buffer,
                              SequenceElements* elements, const std::string& faceDefinition,
                              const std::string& Phoneme, const std::string& trackName, const std::string& mode, const std::string& colourmode, int fadeTime) {
    if (buffer.needToInit) {
        buffer.needToInit = false;
        elements->AddRenderDependency(trackName, buffer.cur_model);

        if (buffer.isTransformed) {
            log4cpp::Category& logger_base = log4cpp::Category::getInstance(std::string("log_base"));
            logger_base.warn("State effect starting at %dms until %dms on model %s has a transformed buffer. This may not work as expected.", buffer.curEffStartPer * buffer.frameTimeInMs, buffer.curEffEndPer * buffer.frameTimeInMs, (const char*)buffer.cur_model.c_str());
        }
    }

    if (buffer.cur_model.empty()) {
        return;
    }

    const Model* model_info = buffer.GetModel();
    std::string definition = faceDefinition;
    bool found = true;
    std::map<std::string, std::map<std::string, std::string>>::const_iterator it = model_info->GetStateInfo().find(definition);
    if (it == model_info->GetStateInfo().end()) {
        // not found
        found = false;
    }
    if (!found) {
        if ("Coro" == definition && model_info->GetStateInfo().find("SingleNode") != model_info->GetStateInfo().end()) {
            definition = "SingleNode";
            found = true;
        } else if ("SingleNode" == definition && model_info->GetStateInfo().find("Coro") != model_info->GetStateInfo().end()) {
            definition = "Coro";
            found = true;
        }
    }

    if (definition.empty()) {
        return;
    }
    std::map<std::string, std::string> emptyMap;
    const std::map<std::string, std::string>& definitionSi = found ? model_info->GetStateInfo().find(definition)->second : emptyMap;
    std::string modelType = findKey(definitionSi, "Type", definition);
    if (modelType == "") {
        modelType = definition;
    }

    int type = 1;

    if ("SingleNode" == modelType) {
        type = 0;
    } else if ("NodeRange" == modelType) {
        type = 1;
    }

    std::string tstates = Phoneme;
    int intervalnumber = 0;
    // GET label from timing track
    int startms = -1;
    int endms = -1;
    int posms = -1;

    if (tstates == "") {
        Element* track = elements->GetElement(trackName);

        // if we dont have a track then exit
        if (track == nullptr) {
            return;
        }

        std::recursive_timed_mutex* lock = &track->GetChangeLock();
        std::unique_lock<std::recursive_timed_mutex> locker(*lock);

        EffectLayer* layer = track->GetEffectLayer(0);
        int time = buffer.curPeriod * buffer.frameTimeInMs + 1;
        posms = buffer.curPeriod * buffer.frameTimeInMs;
        Effect* ef = layer->GetEffectByTime(time);
        if (ef == nullptr) {
            tstates = "";
        } else {
            startms = ef->GetStartTimeMS();
            endms = ef->GetEndTimeMS();
            tstates = ef->GetEffectName();
        }

        ef = layer->GetEffectByTime(buffer.curEffStartPer * buffer.frameTimeInMs + 1);
        while (ef != nullptr && ef->GetStartTimeMS() <= time) {
            intervalnumber++;
            int endtime = ef->GetEndTimeMS();
            ef = layer->GetEffectByTime(endtime + 1);
            if (ef == nullptr) {
                ef = layer->GetEffectAfterTime(endtime + 1);
            }
        }
    }
    uint8_t const alpha = CalculateAlpha(fadeTime,posms, startms, endms, buffer);
    std::vector<std::string> sstates;

    if (mode == "Default" || startms == -1) {
        std::stringstream ss(tstates);
        std::string token;
        while (std::getline(ss, token)) {
            std::string remaining = token;
            size_t pos = 0;
            while (pos < remaining.size()) {
                size_t next = remaining.find_first_of(" ,;:", pos);
                std::string t;
                if (next == std::string::npos) {
                    t = remaining.substr(pos);
                    pos = remaining.size();
                } else {
                    t = remaining.substr(pos, next - pos);
                    pos = next + 1;
                }
                if (t.empty()) continue;
                if (t == "*" || t == "<ALL>") {
                    for (auto it2 : definitionSi) {
                        if (EndsWith(it2.first, "-Name") && it2.second != "") {
                            sstates.push_back(Lower(it2.second));
                        }
                    }
                } else {
                    std::string lower_t = t;
                    std::transform(lower_t.begin(), lower_t.end(), lower_t.begin(), ::tolower);
                    sstates.push_back(lower_t);
                }
            }
        }
    } else if (mode == "Countdown") {
        // tstates should contain the starting number
        int val = std::atoi(tstates.c_str());

        val = val * 1000;
        int subtracttime = (posms - startms);
        val = val - subtracttime;
        val = val / 1000;

        int v = val;
        bool force = false;
        if ((v / 1000) * 1000 > 0) {
            sstates.push_back(std::to_string((v / 1000) * 1000));
            force = true;
        }
        v = v - (v / 1000) * 1000;
        if ((v / 100) * 100 > 0) {
            sstates.push_back(std::to_string((v / 100) * 100));
            force = true;
        } else {
            if (force) {
                sstates.push_back("000");
            }
        }
        v = v - (v / 100) * 100;
        if ((v / 10) * 10 > 0) {
            sstates.push_back(std::to_string((v / 10) * 10));
        } else {
            if (force) {
                sstates.push_back("00");
            }
        }
        v = v - (v / 10) * 10;
        sstates.push_back(std::to_string(v));
    } else if (mode == "Time Countdown") {
#ifndef XLIGHTS_NATIVE
        wxDateTime dt;
        dt.ParseFormat(tstates.c_str(), "%H:%M:%S");

        if (!dt.IsValid()) {
            dt.ParseFormat(tstates.c_str(), "%M:%S");
        }

        if (dt.IsValid()) {
            dt.Subtract(wxTimeSpan(0, 0, 0, (buffer.curPeriod - buffer.curEffStartPer) * buffer.frameTimeInMs));
            int m = dt.GetMinute();
            if ((m / 10) * 1000 > 0) {
                sstates.push_back(std::to_string((m / 10) * 1000));
            } else {
                sstates.push_back("0000");
            }
            m = m - (m / 10) * 10;
            if (m * 100 > 0) {
                sstates.push_back(std::to_string(m * 100));
            } else {
                sstates.push_back("000");
            }
            int s = dt.GetSecond();
            if ((s / 10) * 10 > 0) {
                sstates.push_back(std::to_string((s / 10) * 10));
            } else {
                sstates.push_back("00");
            }
            s = s - (s / 10) * 10;
            sstates.push_back(std::to_string(s));
        }
#endif
        sstates.push_back("colon");
    } else if (mode == "Number") // used for FM frequencies
    {
        double f = std::atof(tstates.c_str());
        sstates.push_back("dot");
        double f2 = f - int(f);
        f2 = (int)(f2 * 10 + 0.5);
        sstates.push_back(std::to_string((int)f2));

        int v = f;
        bool force = false;
        if ((v / 100) * 1000 > 0) {
            sstates.push_back(std::to_string((v / 100) * 1000));
            force = true;
        }
        v = v - (v / 100) * 100;
        if ((v / 10) * 100 > 0) {
            sstates.push_back(std::to_string((v / 10) * 100));
        } else {
            if (force) {
                sstates.push_back("000");
            }
        }
        v = v - (v / 10) * 10;
        if (v * 10 > 0) {
            sstates.push_back(std::to_string(v * 10));
        } else {
            sstates.push_back("00");
        }
    } else if (mode == "Iterate") {
        float progressthroughtimeinterval = ((float)posms - (float)startms) / ((float)endms - (float)startms);

        std::vector<std::string> tmpstates;
        std::string remaining2 = tstates;
        size_t pos2 = 0;
        while (pos2 < remaining2.size()) {
            size_t next2 = remaining2.find_first_of(" ,;:", pos2);
            std::string t2;
            if (next2 == std::string::npos) {
                t2 = remaining2.substr(pos2);
                pos2 = remaining2.size();
            } else {
                t2 = remaining2.substr(pos2, next2 - pos2);
                pos2 = next2 + 1;
            }
            if (t2.empty()) continue;
            if (t2 == "*" || t2 == "<ALL>") {
                for (auto it2 : definitionSi) {
                    if (EndsWith(it2.first, "-Name") && it2.second != "") {
                        sstates.push_back(Lower(it2.second));
                    }
                }
            } else {
                std::string lower_t2 = t2;
                std::transform(lower_t2.begin(), lower_t2.end(), lower_t2.begin(), ::tolower);
                tmpstates.push_back(lower_t2);
            }
        }

        int which = tmpstates.size() * progressthroughtimeinterval;

        if (which < tmpstates.size()) {
            sstates.push_back(tmpstates[which]);
        }
    }

    bool customColor = found ? findKey(definitionSi, "CustomColors") == "1" : false;

    // process each token
    for (size_t i = 0; i < sstates.size(); i++) {
        for (const auto& it : definitionSi) {
            if (it.second == sstates[i] && EndsWith(it.first, "-Name")) {
                // get the channels
                std::string statename = BeforeFirst(it.first, '-'); // FindState(model_info->stateInfo[definition], sstates[i]);
                std::string channels = findKey(definitionSi, statename);

                if (statename != "" && channels != "") {
                    xlColor color;
                    if (colourmode == "Graduate") {
                        buffer.GetMultiColorBlend(buffer.GetEffectTimeIntervalPosition(), false, color);
                    } else if (colourmode == "Cycle") {
                        buffer.palette.GetColor((intervalnumber - 1) % buffer.GetColorCount(), color);
                    } else {
                        // allocate
                        int statenum = std::atoi(statename.substr(1).c_str());
                        buffer.palette.GetColor((statenum - 1) % buffer.GetColorCount(), color);
                    }
                    if (customColor) {
                        std::string cname = findKey(definitionSi, statename + "-Color");
                        if (cname == "") {
                            color = xlWHITE;
                        } else {
                            color = xlColor(cname);
                        }
                    }
                    color.alpha = ((int)alpha * color.alpha) / 255;
                    if (type == 1) {
                        for (const auto it : findNodeKey(model_info->GetStateInfoNodes().at(definition), statename)) {
                            buffer.SetNodePixel(it, color, true);
                        }
                    } else {
                        std::stringstream wtkz(channels);
                        std::string valstr;
                        while (std::getline(wtkz, valstr, ',')) {
                            if (type == 0) {
                                for (size_t n = 0; n < model_info->GetNodeCount(); n++) {
                                    std::string nn = model_info->GetNodeName(n, true);
                                    if (nn == valstr) {
                                        buffer.SetNodePixel(n, color, true);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

uint8_t StateEffect::CalculateAlpha(int fadeTime, int currentTime, int startTime, int endTime, RenderBuffer& buffer) {
    if (0 == fadeTime || -1 == currentTime || -1 == startTime || -1 == endTime) {
        return 255;
    }
    uint8_t beforeAlpha = 0;
    uint8_t afterAlpha = 0;
    if (endTime - currentTime < fadeTime) {                       
        beforeAlpha = ((endTime - currentTime) * 255) / fadeTime;                        
    } else if (currentTime + buffer.frameTimeInMs - startTime < fadeTime) { // buffer.frameTimeInMs
        afterAlpha = ((currentTime + buffer.frameTimeInMs - startTime) * 255) / fadeTime;
    } else {
        return 255;
    }         
    return std::max(beforeAlpha, afterAlpha);
}
#endif