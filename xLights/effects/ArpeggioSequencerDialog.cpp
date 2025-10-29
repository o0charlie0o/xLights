/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "ArpeggioSequencerDialog.h"
#include <wx/msgdlg.h>
#include <wx/settings.h>
#include <sstream>

const long ArpeggioSequencerDialog::ID_GRID = wxNewId();
const long ArpeggioSequencerDialog::ID_CLEAR_BTN = wxNewId();
const long ArpeggioSequencerDialog::ID_FILL_BTN = wxNewId();

wxBEGIN_EVENT_TABLE(ArpeggioSequencerDialog, wxDialog)
    EVT_GRID_CELL_LEFT_CLICK(ArpeggioSequencerDialog::OnCellLeftClick)
    EVT_GRID_CELL_RIGHT_CLICK(ArpeggioSequencerDialog::OnCellRightClick)
    EVT_BUTTON(wxID_OK, ArpeggioSequencerDialog::OnOK)
    EVT_BUTTON(wxID_CANCEL, ArpeggioSequencerDialog::OnCancel)
    EVT_BUTTON(ID_CLEAR_BTN, ArpeggioSequencerDialog::OnClear)
    EVT_BUTTON(ID_FILL_BTN, ArpeggioSequencerDialog::OnFill)
wxEND_EVENT_TABLE()

ArpeggioSequencerDialog::ArpeggioSequencerDialog(wxWindow* parent,
                                                 int numSteps,
                                                 int numProps,
                                                 const std::string& sequenceData)
    : wxDialog(parent, wxID_ANY, "Arpeggio Step Sequencer",
               wxDefaultPosition, wxDefaultSize,
               wxDEFAULT_DIALOG_STYLE | wxRESIZE_BORDER),
      m_numSteps(numSteps),
      m_numProps(numProps)
{
    // Initialize grid data (steps x props)
    m_gridData.resize(m_numSteps);
    for (int i = 0; i < m_numSteps; i++) {
        m_gridData[i].resize(m_numProps, false);
    }

    CreateControls();

    if (!sequenceData.empty()) {
        LoadSequenceData(sequenceData);
    }

    SetSize(800, 600);
    Centre();
}

ArpeggioSequencerDialog::~ArpeggioSequencerDialog()
{
}

void ArpeggioSequencerDialog::CreateControls()
{
    wxBoxSizer* mainSizer = new wxBoxSizer(wxVERTICAL);

    // Info text
    wxString info = wxString::Format(
        "Click cells to toggle props on/off for each step. Steps: %d, Props: %d",
        m_numSteps, m_numProps);
    m_infoText = new wxStaticText(this, wxID_ANY, info);
    mainSizer->Add(m_infoText, 0, wxALL | wxEXPAND, 10);

    // Create grid
    m_grid = new wxGrid(this, ID_GRID);
    m_grid->CreateGrid(m_numProps, m_numSteps);
    m_grid->EnableEditing(false);
    m_grid->EnableDragGridSize(false);
    m_grid->SetSelectionMode(wxGrid::wxGridSelectCells);

    // Set column labels (Step 1, Step 2, etc.)
    for (int col = 0; col < m_numSteps; col++) {
        m_grid->SetColLabelValue(col, wxString::Format("Step %d", col + 1));
        m_grid->SetColSize(col, 60);
    }

    // Set row labels (Prop 1, Prop 2, etc.)
    for (int row = 0; row < m_numProps; row++) {
        m_grid->SetRowLabelValue(row, wxString::Format("Prop %d", row + 1));
        m_grid->SetRowSize(row, 30);
    }

    // Initialize all cells to off (white background)
    for (int row = 0; row < m_numProps; row++) {
        for (int col = 0; col < m_numSteps; col++) {
            m_grid->SetCellValue(row, col, "");
            m_grid->SetCellBackgroundColour(row, col, *wxWHITE);
            m_grid->SetReadOnly(row, col, true);
        }
    }

    mainSizer->Add(m_grid, 1, wxALL | wxEXPAND, 10);

    // Button sizer
    wxBoxSizer* buttonSizer = new wxBoxSizer(wxHORIZONTAL);

    m_clearButton = new wxButton(this, ID_CLEAR_BTN, "Clear All");
    m_fillButton = new wxButton(this, ID_FILL_BTN, "Fill All");
    buttonSizer->Add(m_clearButton, 0, wxALL, 5);
    buttonSizer->Add(m_fillButton, 0, wxALL, 5);

    buttonSizer->AddStretchSpacer();

    m_okButton = new wxButton(this, wxID_OK, "OK");
    m_cancelButton = new wxButton(this, wxID_CANCEL, "Cancel");
    buttonSizer->Add(m_okButton, 0, wxALL, 5);
    buttonSizer->Add(m_cancelButton, 0, wxALL, 5);

    mainSizer->Add(buttonSizer, 0, wxALL | wxEXPAND, 10);

    SetSizer(mainSizer);
}

void ArpeggioSequencerDialog::OnCellLeftClick(wxGridEvent& event)
{
    int row = event.GetRow();
    int col = event.GetCol();

    if (row >= 0 && row < m_numProps && col >= 0 && col < m_numSteps) {
        // Toggle the cell state
        m_gridData[col][row] = !m_gridData[col][row];
        UpdateCellColor(row, col);
    }

    event.Skip();
}

void ArpeggioSequencerDialog::OnCellRightClick(wxGridEvent& event)
{
    // Right click also toggles
    OnCellLeftClick(event);
}

void ArpeggioSequencerDialog::UpdateCellColor(int row, int col)
{
    if (m_gridData[col][row]) {
        // Cell is on - use green
        m_grid->SetCellBackgroundColour(row, col, wxColour(144, 238, 144)); // Light green
        m_grid->SetCellValue(row, col, "X");
    } else {
        // Cell is off - use white
        m_grid->SetCellBackgroundColour(row, col, *wxWHITE);
        m_grid->SetCellValue(row, col, "");
    }
    m_grid->ForceRefresh();
}

void ArpeggioSequencerDialog::OnOK(wxCommandEvent& event)
{
    EndModal(wxID_OK);
}

void ArpeggioSequencerDialog::OnCancel(wxCommandEvent& event)
{
    EndModal(wxID_CANCEL);
}

void ArpeggioSequencerDialog::OnClear(wxCommandEvent& event)
{
    // Clear all cells
    for (int step = 0; step < m_numSteps; step++) {
        for (int prop = 0; prop < m_numProps; prop++) {
            m_gridData[step][prop] = false;
            UpdateCellColor(prop, step);
        }
    }
}

void ArpeggioSequencerDialog::OnFill(wxCommandEvent& event)
{
    // Fill all cells
    for (int step = 0; step < m_numSteps; step++) {
        for (int prop = 0; prop < m_numProps; prop++) {
            m_gridData[step][prop] = true;
            UpdateCellColor(prop, step);
        }
    }
}

std::string ArpeggioSequencerDialog::GetSequenceData() const
{
    // Serialize grid data to string format:
    // Format: step1_prop1,prop2;step2_prop3,prop4;...
    // Example: "0,2;1,3;0,1,2" means:
    //   Step 1: props 0 and 2 are on
    //   Step 2: props 1 and 3 are on
    //   Step 3: props 0, 1, and 2 are on

    std::stringstream ss;
    for (int step = 0; step < m_numSteps; step++) {
        bool firstProp = true;
        for (int prop = 0; prop < m_numProps; prop++) {
            if (m_gridData[step][prop]) {
                if (!firstProp) {
                    ss << ",";
                }
                ss << prop;
                firstProp = false;
            }
        }

        if (step < m_numSteps - 1) {
            ss << ";";
        }
    }

    return ss.str();
}

std::vector<std::vector<bool>> ArpeggioSequencerDialog::GetGridData() const
{
    return m_gridData;
}

void ArpeggioSequencerDialog::LoadSequenceData(const std::string& data)
{
    if (data.empty()) {
        return;
    }

    try {
        // Parse format: "0,2;1,3;0,1,2"
        std::stringstream ss(data);
        std::string stepData;
        int step = 0;

        while (std::getline(ss, stepData, ';') && step < m_numSteps) {
            // Clear this step first
            for (int prop = 0; prop < m_numProps; prop++) {
                m_gridData[step][prop] = false;
            }

            if (!stepData.empty()) {
                std::stringstream stepSS(stepData);
                std::string propStr;

                while (std::getline(stepSS, propStr, ',')) {
                    int prop = std::stoi(propStr);
                    if (prop >= 0 && prop < m_numProps) {
                        m_gridData[step][prop] = true;
                    }
                }
            }

            step++;
        }

        // Update all cell colors
        for (int s = 0; s < m_numSteps; s++) {
            for (int p = 0; p < m_numProps; p++) {
                UpdateCellColor(p, s);
            }
        }
    }
    catch (...) {
        // If parsing fails, just clear the grid
        for (int step = 0; step < m_numSteps; step++) {
            for (int prop = 0; prop < m_numProps; prop++) {
                m_gridData[step][prop] = false;
                UpdateCellColor(prop, step);
            }
        }
    }
}
