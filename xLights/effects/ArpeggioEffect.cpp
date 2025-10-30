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
static const std::string TEXTCTRL_Arpeggio_PropsPerStep("TEXTCTRL_Arpeggio_PropsPerStep");
static const std::string CHECKBOX_Arpeggio_Loop("CHECKBOX_Arpeggio_Loop");
static const std::string TEXTCTRL_Arpeggio_Overlap("TEXTCTRL_Arpeggio_Overlap");
static const std::string CHOICE_Arpeggio_Order("CHOICE_Arpeggio_Order");
static const std::string CHOICE_Arpeggio_Pattern("CHOICE_Arpeggio_Pattern");
static const std::string CHECKBOX_Arpeggio_Shimmer("CHECKBOX_Arpeggio_Shimmer");
static const std::string CHECKBOX_Arpeggio_PerPropGradient("CHECKBOX_Arpeggio_PerPropGradient");
static const std::string TEXTCTRL_Arpeggio_FadeIn("TEXTCTRL_Arpeggio_FadeIn");
static const std::string TEXTCTRL_Arpeggio_FadeOut("TEXTCTRL_Arpeggio_FadeOut");
static const std::string CHECKBOX_Arpeggio_ManualMode("CHECKBOX_Arpeggio_ManualMode");
static const std::string TEXTCTRL_Arpeggio_SequencerData("TEXTCTRL_Arpeggio_SequencerData");

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
    p->SliderPropsPerStep->SetValue(1);
    p->TextCtrlPropsPerStep->SetValue("1");
    p->CheckBoxLoop->SetValue(true);
    p->TextCtrlOverlap->SetValue("0");
    p->CheckBoxShimmer->SetValue(false);
    p->CheckBoxPerPropGradient->SetValue(false);
    p->TextCtrlFadeIn->SetValue("50");
    p->TextCtrlFadeOut->SetValue("50");
    p->ChoiceOrder->SetSelection(0);  // Forward
    p->ChoicePattern->SetSelection(0);  // None
    p->CheckBoxManualMode->SetValue(false);
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

    // Props Per Step
    if (p->TextCtrlPropsPerStep->GetValue() != "1") {
        ret << "E_TEXTCTRL_Arpeggio_PropsPerStep=";
        ret << p->TextCtrlPropsPerStep->GetValue().ToStdString();
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

    // Pattern
    if (p->ChoicePattern->GetSelection() != 0) {
        ret << "E_CHOICE_Arpeggio_Pattern=";
        ret << p->ChoicePattern->GetStringSelection().ToStdString();
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

    // Manual Mode
    if (p->CheckBoxManualMode->GetValue()) {
        ret << "E_CHECKBOX_Arpeggio_ManualMode=1,";
    }

    // Sequencer Data
    std::string sequencerData = p->GetSequencerData();
    if (!sequencerData.empty()) {
        ret << "E_TEXTCTRL_Arpeggio_SequencerData=";
        ret << sequencerData;
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
    if (settingsMap.Get("E_TEXTCTRL_Arpeggio_PropsPerStep", "") == "1") {
        settingsMap.erase("E_TEXTCTRL_Arpeggio_PropsPerStep");
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
    if (settingsMap.Get("E_CHOICE_Arpeggio_Pattern", "") == "None") {
        settingsMap.erase("E_CHOICE_Arpeggio_Pattern");
    }
    if (settingsMap.Get("E_CHECKBOX_Arpeggio_ManualMode", "") == "0") {
        settingsMap.erase("E_CHECKBOX_Arpeggio_ManualMode");
    }
    if (settingsMap.Get("E_TEXTCTRL_Arpeggio_SequencerData", "") == "") {
        settingsMap.erase("E_TEXTCTRL_Arpeggio_SequencerData");
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
    int propsPerStep = SettingsMap.GetInt(TEXTCTRL_Arpeggio_PropsPerStep, 1);
    bool loop = SettingsMap.GetInt(CHECKBOX_Arpeggio_Loop, 1) > 0;
    bool shimmer = SettingsMap.GetInt(CHECKBOX_Arpeggio_Shimmer, 0) > 0;
    bool perPropGradient = SettingsMap.GetInt(CHECKBOX_Arpeggio_PerPropGradient, 0) > 0;
    std::string orderStr = SettingsMap.Get(CHOICE_Arpeggio_Order, "Forward");
    std::string pattern = SettingsMap.Get(CHOICE_Arpeggio_Pattern, "None");
    bool manualMode = SettingsMap.GetInt(CHECKBOX_Arpeggio_ManualMode, 0) > 0;
    std::string sequencerData = SettingsMap.Get(TEXTCTRL_Arpeggio_SequencerData, "");

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
    } else if (orderStr == "Reverse") {
        // Reverse order
        for (int i = numSteps - 1; i >= 0; i--) {
            orderMap.push_back(i);
        }
    } else if (orderStr == "Ping-Pong") {
        // Ping-pong: alternates between first and last moving inward
        // Pattern: 0, numSteps-1, 1, numSteps-2, 2, numSteps-3...
        int left = 0;
        int right = numSteps - 1;
        while (left <= right) {
            orderMap.push_back(left);
            if (left != right) {
                orderMap.push_back(right);
            }
            left++;
            right--;
        }
    } else if (orderStr == "Even") {
        // Even props (2nd, 4th, 6th...) which are indices 1,3,5,7...
        for (int i = 1; i < numSteps; i += 2) {
            orderMap.push_back(i);
        }
    } else if (orderStr == "Odd") {
        // Odd props (1st, 3rd, 5th...) which are indices 0,2,4,6...
        for (int i = 0; i < numSteps; i += 2) {
            orderMap.push_back(i);
        }
    } else {
        // Forward (default)
        for (int i = 0; i < numSteps; i++) {
            orderMap.push_back(i);
        }
    }

    // Apply pattern presets (overrides orderMap if pattern is not "None")
    if (pattern != "None") {
        orderMap.clear();

        if (pattern == "Center Out") {
            // Start from center and expand outward
            int mid = numSteps / 2;
            for (int i = 0; i < numSteps; i++) {
                int offset = (i + 1) / 2;
                if (i % 2 == 0) {
                    // Even index: go right from center
                    int idx = mid + offset;
                    if (idx < numSteps) orderMap.push_back(idx);
                } else {
                    // Odd index: go left from center
                    int idx = mid - offset;
                    if (idx >= 0) orderMap.push_back(idx);
                }
            }
        } else if (pattern == "Edges In") {
            // Start from edges and move inward, grouping edge pairs together
            // This creates pairs: [0,numSteps-1], [1,numSteps-2], [2,numSteps-3]...
            // With Props Per Step = 2, both edges will light at the same time
            int left = 0;
            int right = numSteps - 1;
            while (left < right) {
                orderMap.push_back(left);
                orderMap.push_back(right);
                left++;
                right--;
            }
            // If odd number of props, add the middle one
            if (left == right) {
                orderMap.push_back(left);
            }
        } else if (pattern == "Left to Right") {
            // Simple left to right (same as Forward)
            for (int i = 0; i < numSteps; i++) {
                orderMap.push_back(i);
            }
        } else if (pattern == "Right to Left") {
            // Right to left (same as Reverse)
            for (int i = numSteps - 1; i >= 0; i--) {
                orderMap.push_back(i);
            }
        } else if (pattern == "Alternating") {
            // Alternate between odd and even positions: 0,1,2,3 becomes 0,2,1,3
            // First all odd positions (1st, 3rd, 5th...), then even positions (2nd, 4th, 6th...)
            for (int i = 0; i < numSteps; i += 2) {
                orderMap.push_back(i);  // Odd positions (indices 0,2,4...)
            }
            for (int i = 1; i < numSteps; i += 2) {
                orderMap.push_back(i);  // Even positions (indices 1,3,5...)
            }
        } else if (pattern == "Split") {
            // Split into two halves and alternate
            int mid = numSteps / 2;
            for (int i = 0; i < mid; i++) {
                orderMap.push_back(i);
                if (mid + i < numSteps) {
                    orderMap.push_back(mid + i);
                }
            }
            // If odd number of steps, add the remaining middle element
            if (numSteps % 2 != 0) {
                orderMap.push_back(mid);
            }
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

    // Map step to prop index(es)
    // Wrap based on orderMap size (which may be different from numSteps for patterns like Ping-Pong)
    int orderMapSize = orderMap.size();
    if (orderMapSize == 0) {
        return;  // No order map, nothing to render
    }

    // Calculate the starting position in orderMap
    // Multiply by propsPerStep so each time step advances by the right amount
    int orderMapPosition = (activeStepIndex * propsPerStep) % orderMapSize;

    // In normal mode, don't wrap if loop is disabled
    // In manual mode, let the sequencer data determine what renders
    if (!manualMode && !loop && (activeStepIndex * propsPerStep) >= orderMapSize) {
        return;  // Don't wrap if loop is disabled (normal mode only)
    }

    // Apply order mapping to get actual prop indices
    std::vector<int> activePropIndices;

    if (manualMode && !sequencerData.empty()) {
        // Manual mode: parse sequencer data to get which props are active at this step
        // Format: "0|2:1|3:0|1|2" where colons separate steps and pipes separate prop indices

        // Count total number of steps in sequence data
        int totalStepsInData = 0;
        std::istringstream countSS(sequencerData);
        std::string tempStep;
        while (std::getline(countSS, tempStep, ':')) {
            totalStepsInData++;
        }

        // Map the timing interval index to the configured step number
        // If we have more timing intervals than configured steps, we need to map them
        int mappedStepIndex = activeStepIndex;
        if (totalStepsInData > 0 && activeStepIndex >= totalStepsInData) {
            if (loop) {
                // Wrap around to the beginning
                mappedStepIndex = activeStepIndex % totalStepsInData;
            } else {
                // Past the end with loop off - don't render
                return;
            }
        }

        std::istringstream ss(sequencerData);
        std::string stepData;
        int stepIndex = 0;

        // Find the data for the mapped step
        while (std::getline(ss, stepData, ':') && stepIndex < mappedStepIndex) {
            stepIndex++;
        }

        if (stepIndex == mappedStepIndex && !stepData.empty()) {
            // Parse the prop indices for this step
            std::istringstream stepSS(stepData);
            std::string propStr;

            while (std::getline(stepSS, propStr, '|')) {
                // Trim whitespace and check if non-empty
                if (!propStr.empty() && propStr.find_first_not_of(" \t\n\r") != std::string::npos) {
                    try {
                        int propIndex = std::stoi(propStr);
                        if (propIndex >= 0) {
                            activePropIndices.push_back(propIndex);
                        }
                    } catch (const std::exception& e) {
                        // Ignore invalid prop indices
                    }
                }
            }
        }
    } else {
        // Normal mode: use order map and props per step
        for (int p = 0; p < propsPerStep; p++) {
            int idx = (orderMapPosition + p) % orderMapSize;
            int propIndex = orderMap[idx];
            activePropIndices.push_back(propIndex);
        }
    }

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

    // Render based on whether we're in a ModelGroup or single model
    const Model* model = buffer.GetModel();
    if (model != nullptr && model->GetDisplayAs() == "ModelGroup") {
        const ModelGroup* group = dynamic_cast<const ModelGroup*>(model);
        if (group != nullptr) {
            // Get the list of models in the group
            auto& models = group->Models();

            // Render all active props
            for (int propIndex : activePropIndices) {
                if (propIndex >= (int)models.size()) continue;

                // Get color for this prop
                xlColor color;
                if (perPropGradient) {
                    // Use gradient position based on time within this step
                    float stepPosition = (float)timeIntoStep / (float)duration;
                    if (duration <= 0) stepPosition = 0.0f;
                    stepPosition = std::max(0.0f, std::min(1.0f, stepPosition));

                    // Get color from palette gradient
                    int colorIdx = cidx % buffer.palette.Size();
                    buffer.palette.GetColor(colorIdx, color, stepPosition);
                } else {
                    // Use palette index based on prop position
                    int colorIndex = (propIndex + cidx) % buffer.palette.Size();
                    buffer.palette.GetColor(colorIndex, color);
                }

                // Apply intensity
                HSVValue hsv = color.asHSV();
                hsv.value = hsv.value * intensity;
                color = hsv;
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
        // Single model - use first active prop's color
        if (!activePropIndices.empty()) {
            int propIndex = activePropIndices[0];

            xlColor color;
            if (perPropGradient) {
                float stepPosition = (float)timeIntoStep / (float)duration;
                if (duration <= 0) stepPosition = 0.0f;
                stepPosition = std::max(0.0f, std::min(1.0f, stepPosition));
                int colorIdx = cidx % buffer.palette.Size();
                buffer.palette.GetColor(colorIdx, color, stepPosition);
            } else {
                int colorIndex = (propIndex + cidx) % buffer.palette.Size();
                buffer.palette.GetColor(colorIndex, color);
            }

            // Apply intensity
            HSVValue hsv = color.asHSV();
            hsv.value = hsv.value * intensity;
            color = hsv;

            buffer.Fill(color);
        }
    }
}
