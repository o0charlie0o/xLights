/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 **************************************************************/

// LegacyStubs.cpp
// Stub implementations for symbols needed by the native target but
// defined in source files that cannot be included (primarily
// xLightsMain.cpp). This file is compiled with -UXLIGHTS_NATIVE
// so XLIGHTS_NATIVE is NOT defined.
//
// NOTE: Most xLightsFrame methods are provided by the bulk-added
// legacy .cpp files (Tab*.cpp, Render.cpp, etc.). This file only
// provides symbols unique to xLightsMain.cpp.

#include <wx/app.h>
#include <wx/event.h>
#include <wx/taskbar.h>
#include <wx/glcanvas.h>
#include <wx/bmpbndl.h>
#include <wx/xml/xml.h>
#include <wx/filename.h>
#include <wx/init.h>
#include <wx/image.h>
#include "../../xLightsMain.h"
#include "../../xLightsApp.h"
#include "../../automation/LuaRunner.h"
#include "../../ai/AIColorPaletteDialog.h"
#include "../../ai/aiBase.h"
#include "../../ai/ServiceManager.h"
#include "../../xLightsVersion.h"
#include "../../Mouse3DManager.h"
#include "../../graphics/opengl/xlGLCanvas.h"
#include "../../../macOS/macOS-src/osxUtils/TouchBars.h"

// ISPC function headers (extern "C" declarations)
#include "../../effects/ispc/ButterflyFunctions.ispc.h"
#include "../../effects/ispc/PinwheelFunctions.ispc.h"
#include "../../effects/ispc/PlasmaFunctions.ispc.h"
#include "../../effects/ispc/VideoFunctions.ispc.h"
#include "../../effects/ispc/LayerBlendingFunctions.ispc.h"

// Forward declarations for types used in method stubs
class ModelGroup;

// ===================================================================
// Section 1: Event definitions (from xLightsMain.cpp)
// wxDEFINE_EVENT produces const with internal linkage by default.
// Redefine to use extern for external linkage.
// NOTE: EVT_ROW_HEADINGS_CHANGED, EVT_PLAY_MODEL_EFFECT,
// EVT_FORCE_SEQUENCER_REFRESH, EVT_RENDER_RANGE, and
// EVT_SELECTED_EFFECT_CHANGED are in LegacyEventDefs.cpp
// ===================================================================

#undef wxDEFINE_EVENT
#define wxDEFINE_EVENT(name, type) \
    extern const wxEventTypeTag<type> name(wxNewEventType())

wxDEFINE_EVENT(EVT_ZOOM, wxCommandEvent);
wxDEFINE_EVENT(EVT_SCRUB, wxCommandEvent);
wxDEFINE_EVENT(EVT_GSCROLL, wxCommandEvent);
wxDEFINE_EVENT(EVT_TIME_SELECTED, wxCommandEvent);
wxDEFINE_EVENT(EVT_MOUSE_POSITION, wxCommandEvent);
wxDEFINE_EVENT(EVT_WINDOW_RESIZED, wxCommandEvent);
wxDEFINE_EVENT(EVT_SELECTED_ROW_CHANGED, wxCommandEvent);
wxDEFINE_EVENT(EVT_EFFECT_CHANGED, wxCommandEvent);
wxDEFINE_EVENT(EVT_UNSELECTED_EFFECT, wxCommandEvent);
wxDEFINE_EVENT(EVT_EFFECT_DROPPED, wxCommandEvent);
wxDEFINE_EVENT(EVT_EFFECTFILE_DROPPED, wxCommandEvent);
wxDEFINE_EVENT(EVT_EFFECT_UPDATED, wxCommandEvent);
wxDEFINE_EVENT(EVT_UPDATE_EFFECT, wxCommandEvent);
wxDEFINE_EVENT(EVT_EFFECT_RANDOMIZE, wxCommandEvent);
wxDEFINE_EVENT(EVT_EFFECT_PALETTE_UPDATED, wxCommandEvent);
wxDEFINE_EVENT(EVT_LOAD_PERSPECTIVE, wxCommandEvent);
wxDEFINE_EVENT(EVT_PERSPECTIVES_CHANGED, wxCommandEvent);
wxDEFINE_EVENT(EVT_SAVE_PERSPECTIVES, wxCommandEvent);
wxDEFINE_EVENT(EVT_EXPORT_MODEL, wxCommandEvent);
wxDEFINE_EVENT(EVT_PLAY_MODEL, wxCommandEvent);
wxDEFINE_EVENT(EVT_CUT_MODEL_EFFECTS, wxCommandEvent);
wxDEFINE_EVENT(EVT_COPY_MODEL_EFFECTS, wxCommandEvent);
wxDEFINE_EVENT(EVT_PASTE_MODEL_EFFECTS, wxCommandEvent);
wxDEFINE_EVENT(EVT_MODEL_SELECTED, wxCommandEvent);
wxDEFINE_EVENT(EVT_PLAY_SEQUENCE, wxCommandEvent);
wxDEFINE_EVENT(EVT_PAUSE_SEQUENCE, wxCommandEvent);
wxDEFINE_EVENT(EVT_TOGGLE_PLAY, wxCommandEvent);
wxDEFINE_EVENT(EVT_STOP_SEQUENCE, wxCommandEvent);
wxDEFINE_EVENT(EVT_SEQUENCE_FIRST_FRAME, wxCommandEvent);
wxDEFINE_EVENT(EVT_SEQUENCE_LAST_FRAME, wxCommandEvent);
wxDEFINE_EVENT(EVT_SEQUENCE_REWIND10, wxCommandEvent);
wxDEFINE_EVENT(EVT_SEQUENCE_FFORWARD10, wxCommandEvent);
wxDEFINE_EVENT(EVT_SEQUENCE_PRIOR_TAG, wxCommandEvent);
wxDEFINE_EVENT(EVT_SEQUENCE_NEXT_TAG, wxCommandEvent);
wxDEFINE_EVENT(EVT_SEQUENCE_SEEKTO, wxCommandEvent);
wxDEFINE_EVENT(EVT_SEQUENCE_REPLAY_SECTION, wxCommandEvent);
wxDEFINE_EVENT(EVT_SHOW_DISPLAY_ELEMENTS, wxCommandEvent);
wxDEFINE_EVENT(EVT_SHOW_SELECTED_EFFECTS, wxCommandEvent);
wxDEFINE_EVENT(EVT_IMPORT_TIMING, wxCommandEvent);
wxDEFINE_EVENT(EVT_IMPORT_NOTES, wxCommandEvent);
wxDEFINE_EVENT(EVT_CONVERT_DATA_TO_EFFECTS, wxCommandEvent);
wxDEFINE_EVENT(EVT_PROMOTE_EFFECTS, wxCommandEvent);
wxDEFINE_EVENT(EVT_RGBEFFECTS_CHANGED, wxCommandEvent);
wxDEFINE_EVENT(EVT_APPLYLAST, wxCommandEvent);
wxDEFINE_EVENT(EVT_TURNONOUTPUTTOLIGHTS, wxCommandEvent);
wxDEFINE_EVENT(EVT_PLAYJUKEBOXITEM, wxCommandEvent);
wxDEFINE_EVENT(EVT_COLOUR_CHANGED, wxCommandEvent);
wxDEFINE_EVENT(EVT_SETEFFECTCHOICE, wxCommandEvent);
wxDEFINE_EVENT(EVT_TIPOFDAY_READY, wxCommandEvent);
wxDEFINE_EVENT(EVT_SET_EFFECT_DURATION, wxCommandEvent);

// ===================================================================
// Section 2: Event table stubs (GetEventTable/GetEventHashTable)
// ===================================================================

wxBEGIN_EVENT_TABLE(xLightsFrame, xlFrame)
wxEND_EVENT_TABLE()

wxBEGIN_EVENT_TABLE(AIColorPaletteDialog, wxDialog)
wxEND_EVENT_TABLE()

// ===================================================================
// Section 3: xLightsFrame constructor/destructor + headless init
// ===================================================================

static xLightsFrame* s_headlessFrame = nullptr;

xLightsFrame::xLightsFrame(wxWindow* parent, int ab, wxWindowID id, bool renderOnlyMode)
    : _exiting(false),
      jobPool("xLightsHeadless"), color_mgr(this),
      AllModels(&_outputManager, this), AllObjects(this),
      _sequenceElements(this), _presetSequenceElements(this)
{
    // EffectManager auto-registers all 60+ effects in its constructor,
    // so effectManager is already populated at this point.
    printf("[LegacyStubs] xLightsFrame constructed: %zu effects registered\n",
           effectManager.size());
}

xLightsFrame::~xLightsFrame() {
    if (s_headlessFrame == this) {
        s_headlessFrame = nullptr;
    }
}

// Minimal wxApp subclass for headless use.
// Provides GUI app traits (needed by wxTimer) without running an event loop.
class wxHeadlessApp : public wxApp {
public:
    bool OnInit() override { return true; }
};

// Ensure wxWidgets core is initialized with a GUI wxApp instance.
// Must be called before constructing xLightsFrame which has wxTimer members.
static bool s_wxInitialized = false;
static wxHeadlessApp* s_wxApp = nullptr;
static void EnsureWxInitialized() {
    if (s_wxInitialized) return;

    // Create and register a wxApp so wxTimer can get GUI traits.
    s_wxApp = new wxHeadlessApp();
    wxApp::SetInstance(s_wxApp);

    // wxEntryStart initializes the wx library with the registered app.
    int argc = 0;
    char* argv[] = { nullptr };
    if (!wxEntryStart(argc, argv)) {
        printf("[LegacyStubs] WARNING: wxEntryStart() failed\n");
        delete s_wxApp;
        s_wxApp = nullptr;
        wxApp::SetInstance(nullptr);
        return;
    }

    // Call OnInit to complete app setup (our OnInit just returns true).
    s_wxApp->CallOnInit();
    wxInitAllImageHandlers();

    s_wxInitialized = true;
    printf("[LegacyStubs] wxWidgets GUI app initialized for headless use\n");
}

// Create and return the headless xLightsFrame singleton.
// Safe to call multiple times — returns existing instance.
xLightsFrame* xLightsFrame::CreateHeadless() {
    if (!s_headlessFrame) {
        EnsureWxInitialized();
        s_headlessFrame = new xLightsFrame(nullptr, 0, wxID_ANY, true);
        xLightsApp::__frame = s_headlessFrame;
        printf("[LegacyStubs] Headless xLightsFrame created (%zu effects)\n",
               s_headlessFrame->effectManager.size());
    }
    return s_headlessFrame;
}

// Initialize the headless frame for a given show folder.
// Loads OutputManager, ModelManager, and recalculates start channels.
bool xLightsFrame::InitHeadless(const std::string& showDir) {
    CurrentDir = wxString(showDir);

    // Load output configuration (controllers / networks)
    std::string networksPath = showDir + "/xlights_networks.xml";
    if (wxFileExists(wxString(networksPath))) {
        _outputManager.Load(showDir);
        printf("[LegacyStubs] OutputManager loaded from '%s'\n", showDir.c_str());
    } else {
        printf("[LegacyStubs] No xlights_networks.xml found in '%s'\n", showDir.c_str());
    }

    // Load models from xlights_rgbeffects.xml
    std::string rgbPath = showDir + "/xlights_rgbeffects.xml";
    if (wxFileExists(wxString(rgbPath))) {
        wxXmlDocument doc;
        if (doc.Load(wxString(rgbPath))) {
            wxXmlNode* root = doc.GetRoot();
            // Find <models> node and load
            for (wxXmlNode* node = root->GetChildren(); node; node = node->GetNext()) {
                if (node->GetName() == "models") {
                    AllModels.LoadModels(node, 0, 0);
                    printf("[LegacyStubs] Models loaded: %zu models\n",
                           AllModels.size());
                    break;
                }
            }
        } else {
            printf("[LegacyStubs] Failed to parse '%s'\n", rgbPath.c_str());
            return false;
        }
    } else {
        printf("[LegacyStubs] No xlights_rgbeffects.xml found in '%s'\n", showDir.c_str());
        return false;
    }

    AllModels.RecalcStartChannels();
    printf("[LegacyStubs] Start channels recalculated\n");
    return true;
}

// ===================================================================
// Section 4: xLightsFrame static data members
// ===================================================================

wxString xLightsFrame::CurrentDir;
wxString xLightsFrame::FseqDir;
wxString xLightsFrame::xlightsFilename;
xLightsXmlFile* xLightsFrame::CurrentSeqXmlFile = nullptr;

// ===================================================================
// Section 5: xLightsFrame static const IDs
// ===================================================================

const wxWindowID xLightsFrame::ID_AUITOOLBAR_SAVE = wxNewId();
const wxWindowID xLightsFrame::ID_AUITOOLBAR_SAVEAS = wxNewId();
const wxWindowID xLightsFrame::ID_AUITOOLBAR_RENDERALL = wxNewId();
const wxWindowID xLightsFrame::ID_AUITOOLBAR_PLAY_NOW = wxNewId();
const wxWindowID xLightsFrame::ID_AUITOOLBAR_PAUSE = wxNewId();
const wxWindowID xLightsFrame::ID_AUITOOLBAR_STOP = wxNewId();
const wxWindowID xLightsFrame::ID_AUITOOLBAR_FIRST_FRAME = wxNewId();
const wxWindowID xLightsFrame::ID_AUITOOLBAR_LAST_FRAME = wxNewId();
const wxWindowID xLightsFrame::ID_AUITOOLBAR_REPLAY_SECTION = wxNewId();
const wxWindowID xLightsFrame::ID_CHECKBOX_LIGHT_OUTPUT = wxNewId();
const wxWindowID xLightsFrame::ID_MENUITEM_OPENRECENTSEQUENCE = wxNewId();
const wxWindowID xLightsFrame::ID_MENUITEM_RECENTFOLDERS = wxNewId();

// ===================================================================
// Section 6: xLightsFrame static methods
// ===================================================================

xLightsFrame* xLightsFrame::GetFrame() { return s_headlessFrame; }
wxXmlNode* xLightsFrame::FindNode(wxXmlNode*, const wxString&, const wxString&, const wxString&, bool) { return nullptr; }
void xLightsFrame::AddTraceMessage(const std::string&) {}
bool xLightsFrame::IsCheckSequenceOptionDisabled(const std::string&) { return false; }
void xLightsFrame::SetCheckSequenceOptionDisable(const std::string&, bool) {}

// ===================================================================
// Section 7: xLightsFrame const methods
// ===================================================================

ModelPreview* xLightsFrame::GetHousePreview() const { return nullptr; }
std::string xLightsFrame::GetMinTipLevel() const { return ""; }
bool xLightsFrame::GetRecycleTips() const { return false; }
ModelGroup* xLightsFrame::GetSelectedModelGroup() const { return nullptr; }
wxString xLightsFrame::GetXmlSetting(const wxString&, const wxString& defaultValue) const { return defaultValue; }
bool xLightsFrame::IsInShowFolder(const std::string&) const { return false; }
bool xLightsFrame::IsNewModel(Model*) const { return false; }
bool xLightsFrame::IsPaneDocked(wxWindow*) const { return false; }
void xLightsFrame::LogPerspective(const wxString&) const {}
bool xLightsFrame::ShadersOnBackgroundThreads() const { return false; }
int xLightsFrame::SuppressDuplicateFrames() const { return 0; }
bool xLightsFrame::UseGPURendering() const { return false; }
Effect* xLightsFrame::GetPersistentEffectOnModelStartingAtTime(const std::string&, uint32_t) const { return nullptr; }

// ===================================================================
// Section 8: xLightsFrame getter methods
// ===================================================================

int xLightsFrame::GetACIntensity() { return 100; }
void xLightsFrame::GetACRampValues(int& a, int& b) { a = 0; b = 100; }
void xLightsFrame::GetACSettings(ACTYPE& t, ACSTYLE& s, ACTOOL& tl, ACMODE& m) {}
aiBase* xLightsFrame::GetAIService(aiType::TYPE) { return nullptr; }
void xLightsFrame::GetAltBackupFolder(std::string&) {}
void xLightsFrame::GetBackupFolder(bool& b, std::string&) { b = false; }
void xLightsFrame::GetFSEQFolder(bool& b, std::string&) { b = false; }
uint32_t xLightsFrame::GetMaxNumChannels() { return 0; }
float xLightsFrame::GetPlaySpeed() { return 1.0f; }
void xLightsFrame::GetRenderCacheFolder(bool& b, std::string&) { b = false; }
wxArrayString xLightsFrame::GetSequenceViews() { return wxArrayString(); }
wxString xLightsFrame::GetSeqXmlFileName() { return wxEmptyString; }
wxString xLightsFrame::GetThreadStatusReport() { return wxEmptyString; }
std::string xLightsFrame::GetUniqueTimingName(const std::string& name) { return name; }

// ===================================================================
// Section 9: xLightsFrame boolean query methods
// ===================================================================

bool xLightsFrame::IsACActive() { return false; }
bool xLightsFrame::IsDockable(const std::string&) { return true; }
bool xLightsFrame::IsDrawRamps() { return false; }

// ===================================================================
// Section 10: xLightsFrame setter methods
// ===================================================================

void xLightsFrame::SetACSettings(ACMODE) {}
void xLightsFrame::SetACSettings(ACSTYLE) {}
void xLightsFrame::SetACSettings(ACTOOL) {}
void xLightsFrame::SetACSettings(ACTYPE) {}
void xLightsFrame::SetAltBackupFolder(const std::string&) {}
void xLightsFrame::SetAutoSaveInterval(int) {}
void xLightsFrame::SetAutoShowHousePreview(bool) {}
void xLightsFrame::SetBackupFolder(bool, const std::string&) {}
void xLightsFrame::SetBackupPurgeDays(int) {}
void xLightsFrame::SetCrosshairSize(int) {}
void xLightsFrame::SetDefaultSeqView(const wxString&) {}
void xLightsFrame::SetDisableKeyAcceleration(bool) {}
void xLightsFrame::SetEffectAssistMode(int) {}
void xLightsFrame::SetEffectAssistWindowState(bool) {}
void xLightsFrame::SetEnableRenderCache(const wxString&) {}
void xLightsFrame::SetFrequency(int) {}
void xLightsFrame::SetFSEQFolder(bool, const std::string&) {}
void xLightsFrame::SetGridIconBackgrounds(bool) {}
void xLightsFrame::SetGridNodeValues(bool) {}
void xLightsFrame::SetGridSpacing(int) {}
void xLightsFrame::SetHardwareVideoAccelerated(bool) {}
void xLightsFrame::SetHidePresetPreview(bool) {}
void xLightsFrame::SetMediaFolders(const std::list<std::string>&) {}
void xLightsFrame::SetMinTipLevel(const wxString&) {}
void xLightsFrame::SetModelHandleSize(int) {}
void xLightsFrame::SetPlayControlsOnPreview(bool) {}
void xLightsFrame::SetPlaySpeedTo(float) {}
void xLightsFrame::SetPreviewSize(int, int) {}
void xLightsFrame::SetRandomEffectsToUse(const wxArrayString&) {}
void xLightsFrame::SetRecycleTips(bool) {}
void xLightsFrame::SetRenameModelAliasPromptBehavior(const wxString&) {}
void xLightsFrame::SetRenderCacheFolder(bool, const std::string&) {}
void xLightsFrame::SetRenderCacheMaximumSizeMB(size_t) {}
void xLightsFrame::SetRenderOnSave(bool) {}
void xLightsFrame::SetSaveFseqOnSave(bool) {}
void xLightsFrame::SetShadersOnBackgroundThreads(bool) {}
void xLightsFrame::SetShowAlternateTimingFormat(bool) {}
void xLightsFrame::SetShowBaseShowFolder(bool) {}
void xLightsFrame::SetShowGroupEffectIndicator(bool) {}
void xLightsFrame::SetSmallWaveform(bool) {}
void xLightsFrame::SetSnapToTimingMarks(bool) {}
void xLightsFrame::SetSuppressColorWarn(bool) {}
void xLightsFrame::SetSuppressDuplicateFrames(int) {}
void xLightsFrame::SetSuppressFadeHints(bool) {}
void xLightsFrame::SetTimingPlayOnDClick(bool) {}
void xLightsFrame::SetToolIconSize(int) {}
void xLightsFrame::SetUseGPURendering(bool) {}
void xLightsFrame::SetUserEMAIL(const wxString&) {}
void xLightsFrame::SetVideoExportBitrate(int) {}
void xLightsFrame::SetVideoExportCodec(const wxString&) {}
void xLightsFrame::SetXFadePort(int) {}
void xLightsFrame::SetXmlSetting(const wxString&, const wxString&) {}
void xLightsFrame::SetZoomMethodToCursor(bool) {}

// ===================================================================
// Section 11: xLightsFrame action/UI methods
// ===================================================================

void xLightsFrame::AddPreviewOption(LayoutGroup*) {}
void xLightsFrame::ApplySelectedPreset() {}
std::string xLightsFrame::CheckSequence(bool, bool) { return ""; }
void xLightsFrame::CheckUnsavedChanges() {}
void xLightsFrame::CreateDebugReport(xlCrashHandler*) {}
void xLightsFrame::CycleOutputsIfOn() {}
bool xLightsFrame::DisableOutputs() { return false; }
void xLightsFrame::DoBackup(bool, bool, bool) {}
bool xLightsFrame::EnableOutputs(bool) { return false; }
void xLightsFrame::EnableToolbarButton(wxAuiToolBar*, int, bool) {}
bool xLightsFrame::ForceEnableOutputs(bool) { return false; }
bool xLightsFrame::HandleAllKeyBinding(wxKeyEvent&) { return false; }
void xLightsFrame::LoadJukebox(wxXmlNode*) {}
void xLightsFrame::MarkEffectsFileDirty() {}
void xLightsFrame::MarkModelsAsNeedingRender() {}
std::string xLightsFrame::MoveToShowFolder(const std::string&, const std::string& dest, bool) { return dest; }
void xLightsFrame::PlayerError(const wxString&) {}
void xLightsFrame::PopTraceContext() {}
void xLightsFrame::PushTraceContext() {}
void xLightsFrame::RecalcModels() {}
void xLightsFrame::RemovePreviewOption(LayoutGroup*) {}
void xLightsFrame::RenderLayout() {}
void xLightsFrame::ReplaceModelWithModelFixGroups(const std::string&, const std::string&) {}
void xLightsFrame::ResetAllSequencerWindows() {}
bool xLightsFrame::ShowFolderIsInBackup(const std::string) { return false; }
void xLightsFrame::ShowHideAllSequencerWindows(bool) {}
void xLightsFrame::ShowPresetsPanel() {}
void xLightsFrame::ShowDataFindPanel() {}
void xLightsFrame::TimerOutput(int) {}
void xLightsFrame::TogglePresetsPanel() {}
void xLightsFrame::UpdateACToolbar(bool) {}
void xLightsFrame::UpdateEffectAssistWindow(Effect*, RenderableEffect*) {}
void xLightsFrame::UpdateFromBaseShowFolder(bool) {}
void xLightsFrame::UpdateSequenceLength() {}
void xLightsFrame::UpdateViewMenu() {}
void xLightsFrame::ValidateEffectAssets() {}
void xLightsFrame::ValidateWindow() {}

// ===================================================================
// Section 12: xLightsFrame event handler methods
// ===================================================================

void xLightsFrame::OnAuiToolBarFirstFrameClick(wxCommandEvent&) {}
void xLightsFrame::OnAuiToolBarItemPauseButtonClick(wxCommandEvent&) {}
void xLightsFrame::OnAuiToolBarItemPlayButtonClick(wxCommandEvent&) {}
void xLightsFrame::OnAuiToolBarItemStopClick(wxCommandEvent&) {}
void xLightsFrame::OnAuiToolBarLastFrameClick(wxCommandEvent&) {}
void xLightsFrame::OnMenuItem_ColourDropperSelected(wxCommandEvent&) {}
void xLightsFrame::OnMenuItem_FPP_ConnectSelected(wxCommandEvent&) {}
void xLightsFrame::OnMenuItem_JukeboxSelected(wxCommandEvent&) {}
void xLightsFrame::OnMenuItem_ValueCurvesSelected(wxCommandEvent&) {}
void xLightsFrame::OnMenuItemSelectEffectSelected(wxCommandEvent&) {}

// ===================================================================
// Section 13: xLightsApp stubs
// ===================================================================

xLightsFrame* xLightsApp::__frame = nullptr;
wxString xLightsApp::showDir;
wxString xLightsApp::mediaDir;
wxString xLightsApp::cleanupDir;
wxArrayString xLightsApp::sequenceFiles;

// ===================================================================
// Section 14: LuaRunner stubs
// ===================================================================

LuaRunner::LuaRunner(xLightsFrame* frame) : _frame(frame) {}
std::string LuaRunner::GetSystemScriptFolder() { return ""; }
std::string LuaRunner::GetUserScriptFolder() const { return ""; }
bool LuaRunner::Run_Script(std::string const& filepath, std::function<void(std::string const& msg)> SendResponse) { return false; }

// ===================================================================
// Section 15: AI services stubs
// ===================================================================

AIColorPaletteDialog::AIColorPaletteDialog(wxWindow* parent, wxWindowID id) : wxDialog(parent, id, "AI Color Palette") {}
AIColorPaletteDialog::~AIColorPaletteDialog() {}
wxArrayString AIColorPaletteDialog::GetColorStrings() { return wxArrayString(); }

ServiceManager::ServiceManager(xLightsFrame* xl) {}
ServiceManager::~ServiceManager() {}
aiBase* ServiceManager::getService(std::string const& serviceName) { return nullptr; }
void ServiceManager::addService(std::unique_ptr<aiBase> service) {}
aiBase* ServiceManager::findService(aiType::TYPE serviceType) { return nullptr; }
void ServiceManager::setServiceSetting(std::string const& key, int value) {}
void ServiceManager::setServiceSetting(std::string const& key, bool value) {}
void ServiceManager::setServiceSetting(std::string const& key, std::string const& value) {}
int ServiceManager::getServiceSetting(std::string const& key, int defaultValue) const { return defaultValue; }
bool ServiceManager::getServiceSetting(std::string const& key, bool defaultValue) const { return defaultValue; }
std::string ServiceManager::getServiceSetting(std::string const& key, std::string const& defaultValue) const { return defaultValue; }
std::string ServiceManager::getSecretServiceToken(std::string const& service) const { return ""; }
void ServiceManager::setSecretServiceToken(std::string const& service, std::string const& token) {}

// ===================================================================
// Section 16: AUIToolbarButtonWrapper stubs
// ===================================================================

bool AUIToolbarButtonWrapper::IsChecked() { return false; }
void AUIToolbarButtonWrapper::SetValue(bool b) {}
void AUIToolbarButtonWrapper::Enable(bool b) {}
void AUIToolbarButtonWrapper::SetBitmap(const wxBitmapBundle &bmp) {}

// ===================================================================
// Section 17: ISPC function stubs
// ===================================================================

extern "C" {

void ButterflyEffectPlasmaStyles(const ispc::ButterflyData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}
void ButterflyEffectStyle1(const ispc::ButterflyData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}
void ButterflyEffectStyle2(const ispc::ButterflyData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}
void ButterflyEffectStyle3(const ispc::ButterflyData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}
void ButterflyEffectStyle4(const ispc::ButterflyData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}
void ButterflyEffectStyle5(const ispc::ButterflyData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}

void PinwheelEffectStyle0(const ispc::PinwheelData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}

void PlasmaEffectStyle0(const ispc::PlasmaData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}
void PlasmaEffectStyle1(const ispc::PlasmaData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}
void PlasmaEffectStyle2(const ispc::PlasmaData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}
void PlasmaEffectStyle3(const ispc::PlasmaData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}
void PlasmaEffectStyle4(const ispc::PlasmaData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}

void VideoEffectProcess(const ispc::VideoData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}
void VideoEffectProcessSample(const ispc::VideoData &data, int32_t startIdx, int32_t endIdx, ispc::uint8_t4 *result) {}

void AdditiveFunction(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void AdjustBrightnessContrast(const ispc::LayerBlendingData &data, uint32_t *result) {}
void AdjustBrightnessLevel(const ispc::LayerBlendingData &data, uint32_t *result) {}
void AdjustHSV(const ispc::LayerBlendingData &data, uint32_t *result) {}
void ApplySparkles(const ispc::LayerBlendingData &data, uint32_t *result, uint16_t *sparkles) {}
void AsBrightnessFunction(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void AveragedFunction(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void BottomTopFunction(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void Effect1_2_Function(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void FirstLayerFade(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src) {}
void GetColorsISPCKernel(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint8_t *mask, const uint32_t *indexes) {}
void GetColorsISPCKernelSimple(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint8_t *mask, const uint32_t *indexes) {}
void HighlightFunction(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void HighlightVibrantFunction(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void LayeredFunction(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void LeftRightFunction(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void Mask1Function(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void Mask2Function(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void MaxFunction(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void MinFunction(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void NonAlphaFade(const ispc::LayerBlendingData &data, uint32_t *result) {}
void NormalBlendFunction(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void PutColorsForNodes(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint8_t *mask, const uint32_t *indexes) {}
void PutColorsForNodesSimple(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint8_t *mask, const uint32_t *indexes) {}
void Reveal12Function(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void Reveal21Function(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void Shadow_1on2Function(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void Shadow_2on1Function(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void SubtractiveFunction(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void TrueUnmask1Function(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void TrueUnmask2Function(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void Unmask1Function(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}
void Unmask2Function(const ispc::LayerBlendingData &data, uint32_t *result, const uint32_t *src, const uint32_t *indexes) {}

} // extern "C"

// ===================================================================
// Section 18: xlGLCanvas stubs (native app uses Metal, not OpenGL)
// ===================================================================

wxGLContext* xlGLCanvas::m_sharedContext = nullptr;
bool xlGLCanvas::bindVertexArrayID(unsigned int) { return false; }

// ===================================================================
// Section 19: TouchBar stubs (not needed for native app)
// ===================================================================

xlTouchBarSupport::xlTouchBarSupport() : window(nullptr), parent(nullptr), controllerData(nullptr), currentBar(nullptr) {}
xlTouchBarSupport::~xlTouchBarSupport() {}
void xlTouchBarSupport::Init(wxWindow*) {}
void xlTouchBarSupport::SetActive(xlTouchBar*) {}

TouchBarItem::~TouchBarItem() {}
TouchBarItemData* TouchBarItem::GetData() { return nullptr; }

wxControlTouchBarItem::wxControlTouchBarItem(wxWindow* c) : TouchBarItem(""), control(c) {}

GroupTouchBarItem::~GroupTouchBarItem() {}

ColorPanelTouchBar::ColorPanelTouchBar(ColorChangedFunction f, SliderItemChangedFunction spark, xlTouchBarSupport& s)
    : xlTouchBar(s), colorCallback(f), sparkCallback(spark), lastBar(nullptr), inCallback(false) {}
ColorPanelTouchBar::~ColorPanelTouchBar() {}
void ColorPanelTouchBar::SetColor(int, const wxBitmap&, wxColor&) {}
void ColorPanelTouchBar::SetSparkles(int) {}
void ColorPanelTouchBar::SetActive() {}

EffectGridTouchBar::EffectGridTouchBar(xlTouchBarSupport& s, std::vector<TouchBarItem*>& i)
    : xlTouchBar(s, i) {}
EffectGridTouchBar::~EffectGridTouchBar() {}

xlTouchBar::xlTouchBar(xlTouchBarSupport& s) : support(s) {}
xlTouchBar::xlTouchBar(xlTouchBarSupport& s, std::vector<TouchBarItem*>& i) : support(s), items(i) {}
xlTouchBar::~xlTouchBar() {}

void ColorPickerItem::SetColor(const wxBitmap&, wxColor&) {}
void SliderItem::SetValue(int) {}
