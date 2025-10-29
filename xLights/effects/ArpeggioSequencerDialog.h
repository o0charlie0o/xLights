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

#include <wx/dialog.h>
#include <wx/grid.h>
#include <wx/button.h>
#include <wx/sizer.h>
#include <wx/stattext.h>
#include <string>
#include <vector>

class ArpeggioSequencerDialog : public wxDialog
{
public:
    ArpeggioSequencerDialog(wxWindow* parent,
                           int numSteps,
                           int numProps,
                           const std::string& sequenceData = "");
    virtual ~ArpeggioSequencerDialog();

    // Get the sequence data as a serialized string
    std::string GetSequenceData() const;

    // Get the grid data as a 2D vector [step][prop]
    std::vector<std::vector<bool>> GetGridData() const;

private:
    void CreateControls();
    void OnCellLeftClick(wxGridEvent& event);
    void OnCellRightClick(wxGridEvent& event);
    void OnOK(wxCommandEvent& event);
    void OnCancel(wxCommandEvent& event);
    void OnClear(wxCommandEvent& event);
    void OnFill(wxCommandEvent& event);

    void LoadSequenceData(const std::string& data);
    void UpdateCellColor(int row, int col);

    wxGrid* m_grid;
    wxButton* m_okButton;
    wxButton* m_cancelButton;
    wxButton* m_clearButton;
    wxButton* m_fillButton;
    wxStaticText* m_infoText;

    int m_numSteps;
    int m_numProps;
    std::vector<std::vector<bool>> m_gridData; // [step][prop]

    static const long ID_GRID;
    static const long ID_CLEAR_BTN;
    static const long ID_FILL_BTN;

    wxDECLARE_EVENT_TABLE();
};
