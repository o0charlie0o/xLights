/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "ArpeggioPanel.h"
#include "ArpeggioEffect.h"

//(*InternalHeaders(ArpeggioPanel)
#include <wx/bitmap.h>
#include <wx/bmpbuttn.h>
#include <wx/checkbox.h>
#include <wx/choice.h>
#include <wx/image.h>
#include <wx/intl.h>
#include <wx/sizer.h>
#include <wx/slider.h>
#include <wx/stattext.h>
#include <wx/string.h>
#include <wx/textctrl.h>
//*)

//(*IdInit(ArpeggioPanel)
const long ArpeggioPanel::ID_STATICTEXT_Arpeggio_TimingTrack = wxNewId();
const long ArpeggioPanel::ID_CHOICE_Arpeggio_TimingTrack = wxNewId();
const long ArpeggioPanel::ID_STATICTEXT_Arpeggio_Steps = wxNewId();
const long ArpeggioPanel::ID_TEXTCTRL_Arpeggio_Steps = wxNewId();
const long ArpeggioPanel::ID_STATICTEXT_Arpeggio_AutoSplit = wxNewId();
const long ArpeggioPanel::ID_TEXTCTRL_Arpeggio_AutoSplit = wxNewId();
const long ArpeggioPanel::ID_STATICTEXT_Arpeggio_PropsPerStep = wxNewId();
const long ArpeggioPanel::IDD_SLIDER_Arpeggio_PropsPerStep = wxNewId();
const long ArpeggioPanel::ID_TEXTCTRL_Arpeggio_PropsPerStep = wxNewId();
const long ArpeggioPanel::ID_CHECKBOX_Arpeggio_Loop = wxNewId();
const long ArpeggioPanel::ID_STATICTEXT_Arpeggio_Overlap = wxNewId();
const long ArpeggioPanel::IDD_SLIDER_Arpeggio_Overlap = wxNewId();
const long ArpeggioPanel::ID_VALUECURVE_Arpeggio_Overlap = wxNewId();
const long ArpeggioPanel::ID_TEXTCTRL_Arpeggio_Overlap = wxNewId();
const long ArpeggioPanel::ID_STATICTEXT_Arpeggio_Order = wxNewId();
const long ArpeggioPanel::ID_CHOICE_Arpeggio_Order = wxNewId();
const long ArpeggioPanel::ID_STATICTEXT_Arpeggio_Pattern = wxNewId();
const long ArpeggioPanel::ID_CHOICE_Arpeggio_Pattern = wxNewId();
const long ArpeggioPanel::ID_CHECKBOX_Arpeggio_Shimmer = wxNewId();
const long ArpeggioPanel::ID_CHECKBOX_Arpeggio_PerPropGradient = wxNewId();
const long ArpeggioPanel::ID_STATICTEXT_Arpeggio_FadeIn = wxNewId();
const long ArpeggioPanel::IDD_SLIDER_Arpeggio_FadeIn = wxNewId();
const long ArpeggioPanel::ID_VALUECURVE_Arpeggio_FadeIn = wxNewId();
const long ArpeggioPanel::ID_TEXTCTRL_Arpeggio_FadeIn = wxNewId();
const long ArpeggioPanel::ID_STATICTEXT_Arpeggio_FadeOut = wxNewId();
const long ArpeggioPanel::IDD_SLIDER_Arpeggio_FadeOut = wxNewId();
const long ArpeggioPanel::ID_VALUECURVE_Arpeggio_FadeOut = wxNewId();
const long ArpeggioPanel::ID_TEXTCTRL_Arpeggio_FadeOut = wxNewId();
//*)

BEGIN_EVENT_TABLE(ArpeggioPanel,wxPanel)
	//(*EventTable(ArpeggioPanel)
	//*)
    EVT_COMMAND(wxID_ANY, EVT_SETTIMINGTRACKS, ArpeggioPanel::SetTimingTracks)
END_EVENT_TABLE()

#include "EffectPanelUtils.h"

ArpeggioPanel::ArpeggioPanel(wxWindow* parent) : xlEffectPanel(parent)
{
	//(*Initialize(ArpeggioPanel)
	wxFlexGridSizer* FlexGridSizer1;
	wxFlexGridSizer* FlexGridSizer2;
	wxFlexGridSizer* FlexGridSizer3;
	wxFlexGridSizer* FlexGridSizer4;
	wxFlexGridSizer* FlexGridSizer5;
	wxFlexGridSizer* FlexGridSizer6;
	wxFlexGridSizer* FlexGridSizer7;
	wxFlexGridSizer* FlexGridSizerMain;
	wxFlexGridSizer* FlexGridSizerTimingSection;
	wxFlexGridSizer* FlexGridSizerSettings;

	Create(parent, wxID_ANY, wxDefaultPosition, wxDefaultSize, wxTAB_TRAVERSAL, _T("wxID_ANY"));
	FlexGridSizerMain = new wxFlexGridSizer(0, 1, 0, 0);
	FlexGridSizerMain->AddGrowableCol(0);

	// Timing Section
	FlexGridSizerTimingSection = new wxFlexGridSizer(0, 1, 0, 0);
	FlexGridSizerTimingSection->AddGrowableCol(0);
	FlexGridSizerSettings = new wxFlexGridSizer(0, 2, 0, 0);
	FlexGridSizerSettings->AddGrowableCol(1);

	// Timing Track
	StaticText_TimingTrack = new wxStaticText(this, ID_STATICTEXT_Arpeggio_TimingTrack, _("Timing Track"), wxDefaultPosition, wxDefaultSize, 0, _T("ID_STATICTEXT_Arpeggio_TimingTrack"));
	FlexGridSizerSettings->Add(StaticText_TimingTrack, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 2);
	ChoiceTimingTrack = new BulkEditChoice(this, ID_CHOICE_Arpeggio_TimingTrack, wxDefaultPosition, wxDefaultSize, 0, 0, 0, wxDefaultValidator, _T("ID_CHOICE_Arpeggio_TimingTrack"));
	FlexGridSizerSettings->Add(ChoiceTimingTrack, 1, wxALL|wxEXPAND, 2);

	// Steps
	StaticText_Steps = new wxStaticText(this, ID_STATICTEXT_Arpeggio_Steps, _("Steps (0=Auto)"), wxDefaultPosition, wxDefaultSize, 0, _T("ID_STATICTEXT_Arpeggio_Steps"));
	FlexGridSizerSettings->Add(StaticText_Steps, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 2);
	TextCtrlSteps = new BulkEditTextCtrl(this, ID_TEXTCTRL_Arpeggio_Steps, _("0"), wxDefaultPosition, wxDLG_UNIT(this,wxSize(30,-1)), wxTE_PROCESS_ENTER, wxDefaultValidator, _T("ID_TEXTCTRL_Arpeggio_Steps"));
	TextCtrlSteps->SetMaxLength(2);
	FlexGridSizerSettings->Add(TextCtrlSteps, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 2);

	// Auto Split
	StaticText_AutoSplit = new wxStaticText(this, ID_STATICTEXT_Arpeggio_AutoSplit, _("Auto Split"), wxDefaultPosition, wxDefaultSize, 0, _T("ID_STATICTEXT_Arpeggio_AutoSplit"));
	FlexGridSizerSettings->Add(StaticText_AutoSplit, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 2);
	TextCtrlAutoSplit = new BulkEditTextCtrl(this, ID_TEXTCTRL_Arpeggio_AutoSplit, _("8"), wxDefaultPosition, wxDLG_UNIT(this,wxSize(30,-1)), wxTE_PROCESS_ENTER, wxDefaultValidator, _T("ID_TEXTCTRL_Arpeggio_AutoSplit"));
	TextCtrlAutoSplit->SetMaxLength(3);
	FlexGridSizerSettings->Add(TextCtrlAutoSplit, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 2);

	// Props Per Step
	StaticText_PropsPerStep = new wxStaticText(this, ID_STATICTEXT_Arpeggio_PropsPerStep, _("Props Per Step"), wxDefaultPosition, wxDefaultSize, 0, _T("ID_STATICTEXT_Arpeggio_PropsPerStep"));
	FlexGridSizerSettings->Add(StaticText_PropsPerStep, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 2);
	wxFlexGridSizer* FlexGridSizerPropsPerStep = new wxFlexGridSizer(0, 2, 0, 0);
	FlexGridSizerPropsPerStep->AddGrowableCol(0);
	SliderPropsPerStep = new BulkEditSlider(this, IDD_SLIDER_Arpeggio_PropsPerStep, 1, 1, 16, wxDefaultPosition, wxDefaultSize, 0, wxDefaultValidator, _T("IDD_SLIDER_Arpeggio_PropsPerStep"));
	FlexGridSizerPropsPerStep->Add(SliderPropsPerStep, 1, wxALL|wxEXPAND, 2);
	TextCtrlPropsPerStep = new BulkEditTextCtrl(this, ID_TEXTCTRL_Arpeggio_PropsPerStep, _("1"), wxDefaultPosition, wxDLG_UNIT(this,wxSize(20,-1)), 0, wxDefaultValidator, _T("ID_TEXTCTRL_Arpeggio_PropsPerStep"));
	TextCtrlPropsPerStep->SetMaxLength(2);
	FlexGridSizerPropsPerStep->Add(TextCtrlPropsPerStep, 1, wxALL|wxALIGN_CENTER_HORIZONTAL|wxALIGN_CENTER_VERTICAL, 2);
	FlexGridSizerSettings->Add(FlexGridSizerPropsPerStep, 1, wxALL|wxEXPAND, 0);

	// Overlap
	StaticText_Overlap = new wxStaticText(this, ID_STATICTEXT_Arpeggio_Overlap, _("Overlap %"), wxDefaultPosition, wxDefaultSize, 0, _T("ID_STATICTEXT_Arpeggio_Overlap"));
	FlexGridSizerSettings->Add(StaticText_Overlap, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 2);
	FlexGridSizer4 = new wxFlexGridSizer(0, 3, 0, 0);
	FlexGridSizer4->AddGrowableCol(0);
	SliderOverlap = new BulkEditSlider(this, IDD_SLIDER_Arpeggio_Overlap, 0, 0, 100, wxDefaultPosition, wxDefaultSize, 0, wxDefaultValidator, _T("IDD_SLIDER_Arpeggio_Overlap"));
	FlexGridSizer4->Add(SliderOverlap, 1, wxALL|wxEXPAND, 2);
	BitmapButton_Arpeggio_Overlap = new BulkEditValueCurveButton(this, ID_VALUECURVE_Arpeggio_Overlap, GetValueCurveNotSelectedBitmap(), wxDefaultPosition, wxDefaultSize, wxBU_AUTODRAW|wxBORDER_NONE, wxDefaultValidator, _T("ID_VALUECURVE_Arpeggio_Overlap"));
	FlexGridSizer4->Add(BitmapButton_Arpeggio_Overlap, 1, wxALIGN_CENTER_HORIZONTAL|wxALIGN_CENTER_VERTICAL, 0);
	TextCtrlOverlap = new BulkEditTextCtrl(this, ID_TEXTCTRL_Arpeggio_Overlap, _("0"), wxDefaultPosition, wxDLG_UNIT(this,wxSize(30,-1)), 0, wxDefaultValidator, _T("ID_TEXTCTRL_Arpeggio_Overlap"));
	TextCtrlOverlap->SetMaxLength(3);
	FlexGridSizer4->Add(TextCtrlOverlap, 1, wxALL|wxALIGN_CENTER_HORIZONTAL|wxALIGN_CENTER_VERTICAL, 2);
	FlexGridSizerSettings->Add(FlexGridSizer4, 1, wxALL|wxEXPAND, 0);

	// Order
	StaticText_Order = new wxStaticText(this, ID_STATICTEXT_Arpeggio_Order, _("Order"), wxDefaultPosition, wxDefaultSize, 0, _T("ID_STATICTEXT_Arpeggio_Order"));
	FlexGridSizerSettings->Add(StaticText_Order, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 2);
	ChoiceOrder = new BulkEditChoice(this, ID_CHOICE_Arpeggio_Order, wxDefaultPosition, wxDefaultSize, 0, 0, 0, wxDefaultValidator, _T("ID_CHOICE_Arpeggio_Order"));
	ChoiceOrder->Append(_("Forward"));
	ChoiceOrder->Append(_("Reverse"));
	ChoiceOrder->Append(_("Ping-Pong"));
	ChoiceOrder->Append(_("Even"));
	ChoiceOrder->Append(_("Odd"));
	ChoiceOrder->Append(_("Random"));
	ChoiceOrder->SetSelection(0);
	FlexGridSizerSettings->Add(ChoiceOrder, 1, wxALL|wxEXPAND, 2);

	// Pattern Presets
	StaticText_Pattern = new wxStaticText(this, ID_STATICTEXT_Arpeggio_Pattern, _("Pattern"), wxDefaultPosition, wxDefaultSize, 0, _T("ID_STATICTEXT_Arpeggio_Pattern"));
	FlexGridSizerSettings->Add(StaticText_Pattern, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 2);
	ChoicePattern = new BulkEditChoice(this, ID_CHOICE_Arpeggio_Pattern, wxDefaultPosition, wxDefaultSize, 0, 0, 0, wxDefaultValidator, _T("ID_CHOICE_Arpeggio_Pattern"));
	ChoicePattern->Append(_("None"));
	ChoicePattern->Append(_("Center Out"));
	ChoicePattern->Append(_("Edges In"));
	ChoicePattern->Append(_("Left to Right"));
	ChoicePattern->Append(_("Right to Left"));
	ChoicePattern->Append(_("Alternating"));
	ChoicePattern->Append(_("Split"));
	ChoicePattern->SetSelection(0);
	FlexGridSizerSettings->Add(ChoicePattern, 1, wxALL|wxEXPAND, 2);

	// Fade In
	StaticText_FadeIn = new wxStaticText(this, ID_STATICTEXT_Arpeggio_FadeIn, _("Fade In (ms)"), wxDefaultPosition, wxDefaultSize, 0, _T("ID_STATICTEXT_Arpeggio_FadeIn"));
	FlexGridSizerSettings->Add(StaticText_FadeIn, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 2);
	FlexGridSizer6 = new wxFlexGridSizer(0, 3, 0, 0);
	FlexGridSizer6->AddGrowableCol(0);
	SliderFadeIn = new BulkEditSlider(this, IDD_SLIDER_Arpeggio_FadeIn, 50, 0, 1000, wxDefaultPosition, wxDefaultSize, 0, wxDefaultValidator, _T("IDD_SLIDER_Arpeggio_FadeIn"));
	FlexGridSizer6->Add(SliderFadeIn, 1, wxALL|wxEXPAND, 2);
	BitmapButton_Arpeggio_FadeIn = new BulkEditValueCurveButton(this, ID_VALUECURVE_Arpeggio_FadeIn, GetValueCurveNotSelectedBitmap(), wxDefaultPosition, wxDefaultSize, wxBU_AUTODRAW|wxBORDER_NONE, wxDefaultValidator, _T("ID_VALUECURVE_Arpeggio_FadeIn"));
	FlexGridSizer6->Add(BitmapButton_Arpeggio_FadeIn, 1, wxALIGN_CENTER_HORIZONTAL|wxALIGN_CENTER_VERTICAL, 0);
	TextCtrlFadeIn = new BulkEditTextCtrl(this, ID_TEXTCTRL_Arpeggio_FadeIn, _("50"), wxDefaultPosition, wxDLG_UNIT(this,wxSize(30,-1)), 0, wxDefaultValidator, _T("ID_TEXTCTRL_Arpeggio_FadeIn"));
	TextCtrlFadeIn->SetMaxLength(4);
	FlexGridSizer6->Add(TextCtrlFadeIn, 1, wxALL|wxALIGN_CENTER_HORIZONTAL|wxALIGN_CENTER_VERTICAL, 2);
	FlexGridSizerSettings->Add(FlexGridSizer6, 1, wxALL|wxEXPAND, 0);

	// Fade Out
	StaticText_FadeOut = new wxStaticText(this, ID_STATICTEXT_Arpeggio_FadeOut, _("Fade Out (ms)"), wxDefaultPosition, wxDefaultSize, 0, _T("ID_STATICTEXT_Arpeggio_FadeOut"));
	FlexGridSizerSettings->Add(StaticText_FadeOut, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 2);
	FlexGridSizer7 = new wxFlexGridSizer(0, 3, 0, 0);
	FlexGridSizer7->AddGrowableCol(0);
	SliderFadeOut = new BulkEditSlider(this, IDD_SLIDER_Arpeggio_FadeOut, 50, 0, 1000, wxDefaultPosition, wxDefaultSize, 0, wxDefaultValidator, _T("IDD_SLIDER_Arpeggio_FadeOut"));
	FlexGridSizer7->Add(SliderFadeOut, 1, wxALL|wxEXPAND, 2);
	BitmapButton_Arpeggio_FadeOut = new BulkEditValueCurveButton(this, ID_VALUECURVE_Arpeggio_FadeOut, GetValueCurveNotSelectedBitmap(), wxDefaultPosition, wxDefaultSize, wxBU_AUTODRAW|wxBORDER_NONE, wxDefaultValidator, _T("ID_VALUECURVE_Arpeggio_FadeOut"));
	FlexGridSizer7->Add(BitmapButton_Arpeggio_FadeOut, 1, wxALIGN_CENTER_HORIZONTAL|wxALIGN_CENTER_VERTICAL, 0);
	TextCtrlFadeOut = new BulkEditTextCtrl(this, ID_TEXTCTRL_Arpeggio_FadeOut, _("50"), wxDefaultPosition, wxDLG_UNIT(this,wxSize(30,-1)), 0, wxDefaultValidator, _T("ID_TEXTCTRL_Arpeggio_FadeOut"));
	TextCtrlFadeOut->SetMaxLength(4);
	FlexGridSizer7->Add(TextCtrlFadeOut, 1, wxALL|wxALIGN_CENTER_HORIZONTAL|wxALIGN_CENTER_VERTICAL, 2);
	FlexGridSizerSettings->Add(FlexGridSizer7, 1, wxALL|wxEXPAND, 0);

	FlexGridSizerTimingSection->Add(FlexGridSizerSettings, 1, wxALL|wxEXPAND, 2);
	FlexGridSizerMain->Add(FlexGridSizerTimingSection, 1, wxALL|wxEXPAND, 2);

	// Checkboxes
	CheckBoxLoop = new BulkEditCheckBox(this, ID_CHECKBOX_Arpeggio_Loop, _("Loop"), wxDefaultPosition, wxDefaultSize, 0, wxDefaultValidator, _T("ID_CHECKBOX_Arpeggio_Loop"));
	CheckBoxLoop->SetValue(true);
	FlexGridSizerMain->Add(CheckBoxLoop, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 5);

	CheckBoxShimmer = new BulkEditCheckBox(this, ID_CHECKBOX_Arpeggio_Shimmer, _("Shimmer"), wxDefaultPosition, wxDefaultSize, 0, wxDefaultValidator, _T("ID_CHECKBOX_Arpeggio_Shimmer"));
	CheckBoxShimmer->SetValue(false);
	FlexGridSizerMain->Add(CheckBoxShimmer, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 5);

	CheckBoxPerPropGradient = new BulkEditCheckBox(this, ID_CHECKBOX_Arpeggio_PerPropGradient, _("Per Prop Gradient"), wxDefaultPosition, wxDefaultSize, 0, wxDefaultValidator, _T("ID_CHECKBOX_Arpeggio_PerPropGradient"));
	CheckBoxPerPropGradient->SetValue(false);
	FlexGridSizerMain->Add(CheckBoxPerPropGradient, 1, wxALL|wxALIGN_LEFT|wxALIGN_CENTER_VERTICAL, 5);

	SetSizer(FlexGridSizerMain);

	Connect(ID_VALUECURVE_Arpeggio_Overlap,wxEVT_COMMAND_BUTTON_CLICKED,(wxObjectEventFunction)&ArpeggioPanel::OnVCButtonClick);
	Connect(ID_VALUECURVE_Arpeggio_FadeIn,wxEVT_COMMAND_BUTTON_CLICKED,(wxObjectEventFunction)&ArpeggioPanel::OnVCButtonClick);
	Connect(ID_VALUECURVE_Arpeggio_FadeOut,wxEVT_COMMAND_BUTTON_CLICKED,(wxObjectEventFunction)&ArpeggioPanel::OnVCButtonClick);
	//*)

    Connect(wxID_ANY, EVT_VC_CHANGED, (wxObjectEventFunction)&ArpeggioPanel::OnVCChanged, 0, this);
    Connect(wxID_ANY, EVT_VALIDATEWINDOW, (wxObjectEventFunction)&ArpeggioPanel::OnValidateWindow, 0, this);

    BitmapButton_Arpeggio_Overlap->SetLimits(ARPEGGIO_OVERLAP_MIN, ARPEGGIO_OVERLAP_MAX);
    BitmapButton_Arpeggio_FadeIn->SetLimits(ARPEGGIO_FADEIN_MIN, ARPEGGIO_FADEIN_MAX);
    BitmapButton_Arpeggio_FadeOut->SetLimits(ARPEGGIO_FADEOUT_MIN, ARPEGGIO_FADEOUT_MAX);

    SetName("ID_PANEL_ARPEGGIO");

	ValidateWindow();
}

ArpeggioPanel::~ArpeggioPanel()
{
	//(*Destroy(ArpeggioPanel)
	//*)
}

void ArpeggioPanel::ValidateWindow()
{
}

void ArpeggioPanel::SetTimingTracks(wxCommandEvent& event)
{
    auto timingtracks = wxSplit(event.GetString(), '|');

    wxString selection = ChoiceTimingTrack->GetStringSelection();

    // Remove timing tracks that no longer exist
    for (size_t i = 0; i < ChoiceTimingTrack->GetCount(); i++)
    {
        bool found = false;
        for (const auto& it : timingtracks)
        {
            if (it == ChoiceTimingTrack->GetString(i))
            {
                found = true;
                break;
            }
        }
        if (!found)
        {
            ChoiceTimingTrack->Clear();
            break;
        }
    }

    // Add any new timing tracks
    for (const auto& it : timingtracks)
    {
        bool found = false;
        for (size_t i = 0; i < ChoiceTimingTrack->GetCount(); i++)
        {
            if (it == ChoiceTimingTrack->GetString(i))
            {
                found = true;
                break;
            }
        }
        if (!found)
        {
            ChoiceTimingTrack->Append(it);
        }
    }

    // Restore previous selection if still valid
    if (selection != "")
    {
        ChoiceTimingTrack->SetStringSelection(selection);
    }

    // Default to first item if nothing selected
    if (ChoiceTimingTrack->GetStringSelection() == "" && ChoiceTimingTrack->GetCount() > 0)
    {
        ChoiceTimingTrack->SetSelection(0);
    }
}
