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

//(*Headers(ArpeggioPanel)
#include <wx/panel.h>
class wxBitmapButton;
class wxCheckBox;
class wxChoice;
class wxFlexGridSizer;
class wxSlider;
class wxStaticText;
class wxTextCtrl;
//*)

#include "../BulkEditControls.h"
#include "EffectPanelUtils.h"

class ArpeggioPanel: public xlEffectPanel
{
	public:

		ArpeggioPanel(wxWindow* parent);
		virtual ~ArpeggioPanel();
		virtual void ValidateWindow() override;
		void SetTimingTracks(wxCommandEvent& event);

		//(*Declarations(ArpeggioPanel)
		BulkEditChoice* ChoiceTimingTrack;
		BulkEditTextCtrl* TextCtrlSteps;
		BulkEditTextCtrl* TextCtrlAutoSplit;
		BulkEditCheckBox* CheckBoxLoop;
		BulkEditSlider* SliderOverlap;
		BulkEditTextCtrl* TextCtrlOverlap;
		BulkEditValueCurveButton* BitmapButton_Arpeggio_Overlap;
		BulkEditChoice* ChoiceOrder;
		BulkEditCheckBox* CheckBoxShimmer;
		BulkEditCheckBox* CheckBoxPerPropGradient;
		BulkEditSlider* SliderFadeIn;
		BulkEditTextCtrl* TextCtrlFadeIn;
		BulkEditValueCurveButton* BitmapButton_Arpeggio_FadeIn;
		BulkEditSlider* SliderFadeOut;
		BulkEditTextCtrl* TextCtrlFadeOut;
		BulkEditValueCurveButton* BitmapButton_Arpeggio_FadeOut;
		wxStaticText* StaticText_TimingTrack;
		wxStaticText* StaticText_Steps;
		wxStaticText* StaticText_AutoSplit;
		wxStaticText* StaticText_Overlap;
		wxStaticText* StaticText_Order;
		wxStaticText* StaticText_FadeIn;
		wxStaticText* StaticText_FadeOut;
		//*)

	protected:

		//(*Identifiers(ArpeggioPanel)
		static const long ID_STATICTEXT_Arpeggio_TimingTrack;
		static const long ID_CHOICE_Arpeggio_TimingTrack;
		static const long ID_STATICTEXT_Arpeggio_Steps;
		static const long ID_TEXTCTRL_Arpeggio_Steps;
		static const long ID_STATICTEXT_Arpeggio_AutoSplit;
		static const long ID_TEXTCTRL_Arpeggio_AutoSplit;
		static const long ID_CHECKBOX_Arpeggio_Loop;
		static const long ID_STATICTEXT_Arpeggio_Overlap;
		static const long IDD_SLIDER_Arpeggio_Overlap;
		static const long ID_VALUECURVE_Arpeggio_Overlap;
		static const long ID_TEXTCTRL_Arpeggio_Overlap;
		static const long ID_STATICTEXT_Arpeggio_Order;
		static const long ID_CHOICE_Arpeggio_Order;
		static const long ID_CHECKBOX_Arpeggio_Shimmer;
		static const long ID_CHECKBOX_Arpeggio_PerPropGradient;
		static const long ID_STATICTEXT_Arpeggio_FadeIn;
		static const long IDD_SLIDER_Arpeggio_FadeIn;
		static const long ID_VALUECURVE_Arpeggio_FadeIn;
		static const long ID_TEXTCTRL_Arpeggio_FadeIn;
		static const long ID_STATICTEXT_Arpeggio_FadeOut;
		static const long IDD_SLIDER_Arpeggio_FadeOut;
		static const long ID_VALUECURVE_Arpeggio_FadeOut;
		static const long ID_TEXTCTRL_Arpeggio_FadeOut;
		//*)

	private:

	    //(*Handlers(ArpeggioPanel)
		//*)

		DECLARE_EVENT_TABLE()
};
