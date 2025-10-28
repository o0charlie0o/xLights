/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include <sstream>
#include <cstdlib>
#include <cstdint>
#include <algorithm>
#include <vector>

#include "../../include/Arpeggio.xpm"

#include "ArpeggioEffect.h"
#include "ArpeggioPanel.h"
#include "../sequencer/Effect.h"
#include "../sequencer/EffectLayer.h"
#include "../RenderBuffer.h"
#include "../UtilClasses.h"
#include "../UtilFunctions.h"
#include "../models/Model.h"
#include "../models/ModelGroup.h"
#include <log4cpp/Category.hh>

static const std::string CHOICE_Arpeggio_TimingTrack("CHOICE_Arpeggio_TimingTrack");
static const std::string TEXTCTRL_Arpeggio_Steps("TEXTCTRL_Arpeggio_Steps");
static const std::string TEXTCTRL_Arpeggio_AutoSplit("TEXTCTRL_Arpeggio_AutoSplit");
static const std::string CHECKBOX_Arpeggio_Loop("CHECKBOX_Arpeggio_Loop");
static const std::string TEXTCTRL_Arpeggio_Overlap("TEXTCTRL_Arpeggio_Overlap");
static const std::string CHOICE_Arpeggio_Order("CHOICE_Arpeggio_Order");
static const std::string CHECKBOX_Arpeggio_Shimmer("CHECKBOX_Arpeggio_Shimmer");
static const std::string CHECKBOX_Arpeggio_PerPropGradient("CHECKBOX_Arpeggio_PerPropGradient");
static const std::string TEXTCTRL_Arpeggio_FadeIn("TEXTCTRL_Arpeggio_FadeIn");
static const std::string TEXTCTRL_Arpeggio_FadeOut("TEXTCTRL_Arpeggio_FadeOut");

ArpeggioEffect::ArpeggioEffect(int i) : RenderableEffect(i, "Arpeggio", Arpeggio, Arpeggio, Arpeggio, Arpeggio, Arpeggio)
{
    //ctor
}

ArpeggioEffect::~ArpeggioEffect()
{
    //dtor
}

xlEffectPanel *ArpeggioEffect::CreatePanel(wxWindow *parent) {
    return new ArpeggioPanel(parent);
}

void ArpeggioEffect::SetDefaultParameters() {
    ArpeggioPanel *p = (ArpeggioPanel*)panel;
    p->TextCtrlSteps->SetValue("0");
    p->TextCtrlAutoSplit->SetValue("8");
    p->CheckBoxLoop->SetValue(true);
    p->TextCtrlOverlap->SetValue("0");
    p->CheckBoxShimmer->SetValue(false);
    p->CheckBoxPerPropGradient->SetValue(false);
    p->TextCtrlFadeIn->SetValue("50");
    p->TextCtrlFadeOut->SetValue("50");
    p->ChoiceOrder->SetSelection(0);  // Group Order
    p->BitmapButton_Arpeggio_FadeIn->SetActive(false);
    p->BitmapButton_Arpeggio_FadeOut->SetActive(false);
    p->BitmapButton_Arpeggio_Overlap->SetActive(false);

    SetPanelTimingTracks();
}

wxString ArpeggioEffect::GetEffectString() {
    ArpeggioPanel *p = (ArpeggioPanel*)panel;
    std::stringstream ret;

    // Timing track
    if (p->ChoiceTimingTrack->GetStringSelection() != "") {
        ret << "E_CHOICE_Arpeggio_TimingTrack=";
        ret << p->ChoiceTimingTrack->GetStringSelection().ToStdString();
        ret << ",";
    }

    // Steps
    if (p->TextCtrlSteps->GetValue() != "0") {
        ret << "E_TEXTCTRL_Arpeggio_Steps=";
        ret << p->TextCtrlSteps->GetValue().ToStdString();
        ret << ",";
    }

    // Auto split
    if (p->TextCtrlAutoSplit->GetValue() != "8") {
        ret << "E_TEXTCTRL_Arpeggio_AutoSplit=";
        ret << p->TextCtrlAutoSplit->GetValue().ToStdString();
        ret << ",";
    }

    // Loop
    if (!p->CheckBoxLoop->GetValue()) {
        ret << "E_CHECKBOX_Arpeggio_Loop=0,";
    }

    // Overlap
    if (p->BitmapButton_Arpeggio_Overlap->GetValue()->IsActive()) {
        ret << "E_VALUECURVE_Arpeggio_Overlap=";
        ret << p->BitmapButton_Arpeggio_Overlap->GetValue()->Serialise();
        ret << ",";
    } else if (p->TextCtrlOverlap->GetValue() != "0") {
        ret << "E_TEXTCTRL_Arpeggio_Overlap=";
        ret << p->TextCtrlOverlap->GetValue().ToStdString();
        ret << ",";
    }

    // Order
    if (p->ChoiceOrder->GetSelection() != 0) {
        ret << "E_CHOICE_Arpeggio_Order=";
        ret << p->ChoiceOrder->GetStringSelection().ToStdString();
        ret << ",";
    }

    // Shimmer
    if (p->CheckBoxShimmer->GetValue()) {
        ret << "E_CHECKBOX_Arpeggio_Shimmer=1,";
    }

    // Per Prop Gradient
    if (p->CheckBoxPerPropGradient->GetValue()) {
        ret << "E_CHECKBOX_Arpeggio_PerPropGradient=1,";
    }

    // Fade In
    if (p->BitmapButton_Arpeggio_FadeIn->GetValue()->IsActive()) {
        ret << "E_VALUECURVE_Arpeggio_FadeIn=";
        ret << p->BitmapButton_Arpeggio_FadeIn->GetValue()->Serialise();
        ret << ",";
    } else if (p->TextCtrlFadeIn->GetValue() != "50") {
        ret << "E_TEXTCTRL_Arpeggio_FadeIn=";
        ret << p->TextCtrlFadeIn->GetValue().ToStdString();
        ret << ",";
    }

    // Fade Out
    if (p->BitmapButton_Arpeggio_FadeOut->GetValue()->IsActive()) {
        ret << "E_VALUECURVE_Arpeggio_FadeOut=";
        ret << p->BitmapButton_Arpeggio_FadeOut->GetValue()->Serialise();
        ret << ",";
    } else if (p->TextCtrlFadeOut->GetValue() != "50") {
        ret << "E_TEXTCTRL_Arpeggio_FadeOut=";
        ret << p->TextCtrlFadeOut->GetValue().ToStdString();
        ret << ",";
    }

    return ret.str();
}

void ArpeggioEffect::RemoveDefaults(const std::string &version, Effect *effect) {
    SettingsMap &settingsMap = effect->GetSettings();
    if (settingsMap.Get("E_TEXTCTRL_Arpeggio_Steps", "") == "0") {
        settingsMap.erase("E_TEXTCTRL_Arpeggio_Steps");
    }
    if (settingsMap.Get("E_TEXTCTRL_Arpeggio_AutoSplit", "") == "8") {
        settingsMap.erase("E_TEXTCTRL_Arpeggio_AutoSplit");
    }
    if (settingsMap.Get("E_CHECKBOX_Arpeggio_Loop", "") == "1") {
        settingsMap.erase("E_CHECKBOX_Arpeggio_Loop");
    }
    if (settingsMap.Get("E_TEXTCTRL_Arpeggio_Overlap", "") == "0") {
        settingsMap.erase("E_TEXTCTRL_Arpeggio_Overlap");
    }
    if (settingsMap.Get("E_CHECKBOX_Arpeggio_Shimmer", "") == "0") {
        settingsMap.erase("E_CHECKBOX_Arpeggio_Shimmer");
    }
    if (settingsMap.Get("E_CHECKBOX_Arpeggio_PerPropGradient", "") == "0") {
        settingsMap.erase("E_CHECKBOX_Arpeggio_PerPropGradient");
    }
    if (settingsMap.Get("E_TEXTCTRL_Arpeggio_FadeIn", "") == "50") {
        settingsMap.erase("E_TEXTCTRL_Arpeggio_FadeIn");
    }
    if (settingsMap.Get("E_TEXTCTRL_Arpeggio_FadeOut", "") == "50") {
        settingsMap.erase("E_TEXTCTRL_Arpeggio_FadeOut");
    }
    RenderableEffect::RemoveDefaults(version, effect);
}

void ArpeggioEffect::SetPanelStatus(Model* cls) {
    SetPanelTimingTracks();
}

void ArpeggioEffect::SetPanelTimingTracks() const {
    ArpeggioPanel *ap = static_cast<ArpeggioPanel*>(panel);
    if (ap == nullptr) {
        return;
    }

    if (mSequenceElements == nullptr) {
        return;
    }

    // Load the names of the timing tracks
    std::string timingtracks = GetTimingTracks(1);
    wxCommandEvent event(EVT_SETTIMINGTRACKS);
    event.SetString(timingtracks);
    wxPostEvent(ap, event);
}

void ArpeggioEffect::Render(Effect *eff, const SettingsMap &SettingsMap, RenderBuffer &buffer) {
    // Get parameters
    std::string timingTrack = SettingsMap.Get(CHOICE_Arpeggio_TimingTrack, "");
    int steps = SettingsMap.GetInt(TEXTCTRL_Arpeggio_Steps, 0);
    int autoSplit = SettingsMap.GetInt(TEXTCTRL_Arpeggio_AutoSplit, 8);
    bool loop = SettingsMap.GetInt(CHECKBOX_Arpeggio_Loop, 1) > 0;
    bool shimmer = SettingsMap.GetInt(CHECKBOX_Arpeggio_Shimmer, 0) > 0;
    bool perPropGradient = SettingsMap.GetInt(CHECKBOX_Arpeggio_PerPropGradient, 0) > 0;
    std::string orderStr = SettingsMap.Get(CHOICE_Arpeggio_Order, "Group Order");

    double adjust = buffer.GetEffectTimeIntervalPosition();
    int fadeIn = GetValueCurveInt("Arpeggio_FadeIn", 50, SettingsMap, adjust,
                                   ARPEGGIO_FADEIN_MIN, ARPEGGIO_FADEIN_MAX,
                                   buffer.GetStartTimeMS(), buffer.GetEndTimeMS());
    int fadeOut = GetValueCurveInt("Arpeggio_FadeOut", 50, SettingsMap, adjust,
                                    ARPEGGIO_FADEOUT_MIN, ARPEGGIO_FADEOUT_MAX,
                                    buffer.GetStartTimeMS(), buffer.GetEndTimeMS());
    int overlap = GetValueCurveInt("Arpeggio_Overlap", 0, SettingsMap, adjust,
                                    ARPEGGIO_OVERLAP_MIN, ARPEGGIO_OVERLAP_MAX,
                                    buffer.GetStartTimeMS(), buffer.GetEndTimeMS());

    // Get current time in milliseconds within the effect
    int currentMS = buffer.curPeriod * buffer.frameTimeInMs;
    int effectStartMS = buffer.curEffStartPer * buffer.frameTimeInMs;
    int effectEndMS = buffer.curEffEndPer * buffer.frameTimeInMs;
    int effectDurationMS = effectEndMS - effectStartMS;
    int timeIntoEffectMS = currentMS - effectStartMS;

    // Determine number of steps/props
    int numSteps = steps;
    if (numSteps <= 0) {
        // Try to get from model group
        const Model* model = buffer.GetModel();
        if (model != nullptr && model->GetDisplayAs() == "ModelGroup") {
            const ModelGroup* group = dynamic_cast<const ModelGroup*>(model);
            if (group != nullptr) {
                numSteps = group->Models().size();
            }
        }
        if (numSteps <= 0) {
            numSteps = 1;  // Fallback to single prop
        }
    }

    // Create order mapping array based on Order parameter
    std::vector<int> orderMap;
    if (orderStr == "Random") {
        // Create randomized order
        // Use effect pointer combined with start time for unique but consistent seed
        uintptr_t effectPtr = reinterpret_cast<uintptr_t>(eff);
        unsigned int seed = static_cast<unsigned int>(effectPtr ^ effectStartMS);
        std::srand(seed);
        for (int i = 0; i < numSteps; i++) {
            orderMap.push_back(i);
        }
        // Fisher-Yates shuffle
        for (int i = numSteps - 1; i > 0; i--) {
            int j = std::rand() % (i + 1);
            std::swap(orderMap[i], orderMap[j]);
        }
    } else {
        // Group Order - sequential
        for (int i = 0; i < numSteps; i++) {
            orderMap.push_back(i);
        }
    }

    // Calculate step times based on timing track or auto-split
    std::vector<std::pair<int, int>> stepTimes;  // start, end pairs in MS

    if (!timingTrack.empty()) {
        // Use timing track markers
        EffectLayer* timingLayer = GetTiming(timingTrack);
        if (timingLayer != nullptr) {
            for (int j = 0; j < timingLayer->GetEffectCount(); j++) {
                Effect* timingEffect = timingLayer->GetEffect(j);
                int startMS = timingEffect->GetStartTimeMS();
                int endMS = timingEffect->GetEndTimeMS();

                // Only include timing marks within effect duration
                if (startMS < effectEndMS && endMS > effectStartMS) {
                    startMS = std::max(startMS, effectStartMS);
                    endMS = std::min(endMS, effectEndMS);
                    stepTimes.push_back(std::make_pair(startMS, endMS));
                }
            }
        }
    }

    // If no timing track or no marks, auto-split
    if (stepTimes.empty()) {
        int stepDuration = effectDurationMS / autoSplit;
        for (int i = 0; i < autoSplit; i++) {
            int startMS = effectStartMS + (i * stepDuration);
            int endMS = (i == autoSplit - 1) ? effectEndMS : (startMS + stepDuration);
            stepTimes.push_back(std::make_pair(startMS, endMS));
        }
    }

    // Determine which step(s) should be active at current time
    int activeStepIndex = -1;
    for (size_t i = 0; i < stepTimes.size(); i++) {
        int startMS = stepTimes[i].first;
        int endMS = stepTimes[i].second;
        int duration = endMS - startMS;

        // Apply overlap (extend both directions)
        int overlapMS = (duration * overlap) / 200;  // Divide by 200 because overlap extends both ways
        startMS -= overlapMS;
        endMS += overlapMS;

        if (currentMS >= startMS && currentMS < endMS) {
            activeStepIndex = i;
            break;
        }
    }

    if (activeStepIndex < 0) {
        return;  // No active step, render nothing
    }

    // Map step to prop index
    int stepIndexWrapped = activeStepIndex % numSteps;
    if (!loop && activeStepIndex >= numSteps) {
        return;  // Don't wrap if loop is disabled
    }

    // Apply order mapping to get actual prop index
    int propIndex = orderMap[stepIndexWrapped];

    // Calculate intensity based on fade in/out
    int startMS = stepTimes[activeStepIndex].first;
    int endMS = stepTimes[activeStepIndex].second;
    int duration = endMS - startMS;
    int timeIntoStep = currentMS - startMS;
    int timeFromEnd = endMS - currentMS;

    double intensity = 1.0;

    // Fade in
    if (fadeIn > 0 && timeIntoStep < fadeIn) {
        intensity = (double)timeIntoStep / (double)fadeIn;
    }

    // Fade out
    if (fadeOut > 0 && timeFromEnd < fadeOut) {
        intensity = std::min(intensity, (double)timeFromEnd / (double)fadeOut);
    }

    // Apply shimmer
    int cidx = 0;
    if (shimmer) {
        int tot = buffer.curPeriod - buffer.curEffStartPer;
        if (tot % 2) {
            if (buffer.palette.Size() <= 1) {
                return;
            }
            cidx = 1;
        }
    }

    // Get color for this step
    xlColor color;
    if (perPropGradient) {
        // Use gradient position based on time within this step
        // Calculate position in step (0.0 = start, 1.0 = end)
        float stepPosition = (float)timeIntoStep / (float)duration;
        if (duration <= 0) stepPosition = 0.0f;
        stepPosition = std::max(0.0f, std::min(1.0f, stepPosition)); // Clamp to 0-1

        // Get color from first palette color's gradient at this time position
        // Use color index 0 (or cidx for shimmer) and progress through the gradient
        int colorIdx = cidx % buffer.palette.Size();
        buffer.palette.GetColor(colorIdx, color, stepPosition);
    } else {
        // Use palette index based on prop position (old behavior)
        int colorIndex = (propIndex + cidx) % buffer.palette.Size();
        buffer.palette.GetColor(colorIndex, color);
    }

    // Apply intensity
    HSVValue hsv = color.asHSV();
    hsv.value = hsv.value * intensity;
    color = hsv;

    // Render based on whether we're in a ModelGroup or single model
    const Model* model = buffer.GetModel();
    if (model != nullptr && model->GetDisplayAs() == "ModelGroup") {
        const ModelGroup* group = dynamic_cast<const ModelGroup*>(model);
        if (group != nullptr) {
            // Get the list of models in the group
            auto& models = group->Models();

            // Only light up the prop at propIndex
            if (propIndex < (int)models.size()) {
                // Calculate which nodes belong to this model
                // Nodes are added to the buffer in the same order as models
                int totalNodes = buffer.GetNodeCount();
                int nodesPerModel = totalNodes / numSteps;  // Approximate

                // For more accurate rendering, get actual node counts per model
                std::vector<int> nodeCounts;
                int totalNodesAccounted = 0;
                for (const auto& m : models) {
                    int nodeCount = m->GetNodeCount();
                    nodeCounts.push_back(nodeCount);
                    totalNodesAccounted += nodeCount;
                }

                // Calculate start and end node indices for the active model
                int startNodeIndex = 0;
                for (int i = 0; i < propIndex; i++) {
                    if (i < (int)nodeCounts.size()) {
                        startNodeIndex += nodeCounts[i];
                    }
                }

                int endNodeIndex = startNodeIndex;
                if (propIndex < (int)nodeCounts.size()) {
                    endNodeIndex += nodeCounts[propIndex];
                }

                // Render only the nodes for this model
                auto& nodes = buffer.GetNodes();
                for (int i = startNodeIndex; i < endNodeIndex && i < (int)nodes.size(); i++) {
                    for (auto& coord : nodes[i]->Coords) {
                        buffer.SetPixel(coord.bufX, coord.bufY, color);
                    }
                }
            }
        }
    } else {
        // Single model - fill entire buffer
        buffer.Fill(color);
    }
}
