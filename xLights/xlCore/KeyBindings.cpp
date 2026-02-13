/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "KeyBindings.h"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>
#include <map>

// Simple XML parsing - we'll use a minimal approach without external dependencies
// For a production implementation, consider using tinyxml2 or similar

namespace xlCore {

// Static ID counter
static int s_nextId = 0;

int KeyBinding::nextId() {
    return s_nextId++;
}

// Version string for new bindings
static const std::string XLIGHTS_VERSION = "2024.1";

#pragma region Key Binding Types

// All 150+ binding types with their scopes - copied from legacy implementation
static const std::vector<std::pair<std::string, KeyScope>> s_keyBindingTypes = {
    { "TIMING_ADD", KeyScope::Sequence },
    { "TIMING_SPLIT", KeyScope::Sequence },
    { "TIMING_DIVIDE_2", KeyScope::Sequence },
    { "TIMING_DIVIDE_3", KeyScope::Sequence },
    { "TIMING_DIVIDE_4", KeyScope::Sequence },
    { "TIMING_DIVIDE_6", KeyScope::Sequence },
    { "TIMING_DIVIDE_8", KeyScope::Sequence },
    { "TIMING_DIVIDE_12", KeyScope::Sequence },
    { "TIMING_DIVIDE_16", KeyScope::Sequence },
    { "PHONEME_ETC", KeyScope::Sequence },
    { "PHONEME_AI", KeyScope::Sequence },
    { "PHONEME_E", KeyScope::Sequence },
    { "PHONEME_O", KeyScope::Sequence },
    { "PHONEME_WQ", KeyScope::Sequence },
    { "PHONEME_FV", KeyScope::Sequence },
    { "PHONEME_MBP", KeyScope::Sequence },
    { "PHONEME_REST", KeyScope::Sequence },
    { "PHONEME_L", KeyScope::Sequence },
    { "DUPLICATE_RIGHT", KeyScope::Sequence },
    { "DUPLICATE_LEFT", KeyScope::Sequence },
    { "DUPLICATE_UP", KeyScope::Sequence },
    { "DUPLICATE_DOWN", KeyScope::Sequence },
    { "AUTO_ETC_PHONEME", KeyScope::Sequence },
    { "ZOOM_IN", KeyScope::Sequence },
    { "ZOOM_OUT", KeyScope::Sequence },
    { "ZOOM_SEL", KeyScope::Sequence },
    { "RANDOM", KeyScope::Sequence },
    { "RENDER_ALL", KeyScope::All },
    { "SAVE_CURRENT_TAB", KeyScope::All },
    { "LIGHTS_TOGGLE", KeyScope::All },
    { "OPEN_SEQUENCE", KeyScope::All },
    { "CLOSE_SEQUENCE", KeyScope::All },
    { "NEW_SEQUENCE", KeyScope::All },
    { "PASTE_BY_CELL", KeyScope::All },
    { "PASTE_BY_TIME", KeyScope::All },
    { "BACKUP", KeyScope::All },
    { "ALTERNATE_BACKUP", KeyScope::All },
    { "SELECT_SHOW_FOLDER", KeyScope::All },
    { "SAVEAS_SEQUENCE", KeyScope::Sequence },
    { "SAVE_SEQUENCE", KeyScope::Sequence },
    { "EFFECT_SETTINGS_TOGGLE", KeyScope::Sequence },
    { "EFFECT_ASSIST_TOGGLE", KeyScope::Sequence },
    { "COLOR_TOGGLE", KeyScope::Sequence },
    { "LAYER_SETTING_TOGGLE", KeyScope::Sequence },
    { "LAYER_BLENDING_TOGGLE", KeyScope::Sequence },
    { "MODEL_PREVIEW_TOGGLE", KeyScope::Sequence },
    { "HOUSE_PREVIEW_TOGGLE", KeyScope::Sequence },
    { "EFFECTS_TOGGLE", KeyScope::Sequence },
    { "DISPLAY_ELEMENTS_TOGGLE", KeyScope::Sequence },
    { "JUKEBOX_TOGGLE", KeyScope::Sequence },
    { "SEQUENCE_SETTINGS", KeyScope::All },
    { "LOCK_EFFECT", KeyScope::Sequence },
    { "UNLOCK_EFFECT", KeyScope::Sequence },
    { "MARK_SPOT", KeyScope::Sequence },
    { "RETURN_TO_SPOT", KeyScope::Sequence },
    { "EFFECT_DESCRIPTION", KeyScope::Sequence },
    { "EFFECT_ALIGN_START", KeyScope::Sequence },
    { "EFFECT_ALIGN_END", KeyScope::Sequence },
    { "EFFECT_ALIGN_BOTH", KeyScope::Sequence },
    { "INSERT_LAYER_ABOVE", KeyScope::Sequence },
    { "INSERT_LAYER_BELOW", KeyScope::Sequence },
    { "TOGGLE_ELEMENT_EXPAND", KeyScope::Sequence },
    { "SELECT_ALL", KeyScope::Sequence },
    { "SELECT_ALL_NO_TIMING", KeyScope::Sequence },
    { "SHOW_PRESETS", KeyScope::Sequence },
    { "SEARCH_TOGGLE", KeyScope::Sequence },
    { "PERSPECTIVES_TOGGLE", KeyScope::Sequence },
    { "EFFECT_UPDATE", KeyScope::Sequence },
    { "COLOR_UPDATE", KeyScope::Sequence },
    { "SET_COLOR_1", KeyScope::Sequence },
    { "SET_COLOR_2", KeyScope::Sequence },
    { "SET_COLOR_3", KeyScope::Sequence },
    { "SET_COLOR_4", KeyScope::Sequence },
    { "SET_COLOR_5", KeyScope::Sequence },
    { "SET_COLOR_6", KeyScope::Sequence },
    { "SET_COLOR_7", KeyScope::Sequence },
    { "SET_COLOR_8", KeyScope::Sequence },
    { "PLAY_LOOP", KeyScope::All },
    { "PLAY", KeyScope::All },
    { "TOGGLE_PLAY", KeyScope::All },
    { "START_OF_SONG", KeyScope::All },
    { "END_OF_SONG", KeyScope::All },
    { "STOP", KeyScope::All },
    { "PAUSE", KeyScope::All },
    { "EFFECT", KeyScope::Sequence },
    { "APPLYSETTING", KeyScope::Sequence },
    { "PRESET", KeyScope::Sequence },
    { "LOCK_MODEL", KeyScope::Layout },
    { "UNLOCK_MODEL", KeyScope::Layout },
    { "GROUP_MODELS", KeyScope::Layout },
    { "WIRING_VIEW", KeyScope::Layout },
    { "EXPORT_MODEL_CAD", KeyScope::Layout },
    { "EXPORT_LAYOUT_DXF", KeyScope::Layout },
    { "NODE_LAYOUT", KeyScope::Layout },
    { "SAVE_LAYOUT", KeyScope::Layout },
    { "SELECT_ALL_MODELS", KeyScope::Layout },
    { "MODEL_ALIGN_TOP", KeyScope::Layout },
    { "MODEL_ALIGN_BOTTOM", KeyScope::Layout },
    { "MODEL_ALIGN_LEFT", KeyScope::Layout },
    { "MODEL_ALIGN_RIGHT", KeyScope::Layout },
    { "MODEL_ALIGN_CENTER_VERT", KeyScope::Layout },
    { "MODEL_ALIGN_CENTER_HORIZ", KeyScope::Layout },
    { "MODEL_ALIGN_BACKS", KeyScope::Layout },
    { "MODEL_ALIGN_FRONTS", KeyScope::Layout },
    { "MODEL_ALIGN_GROUND", KeyScope::Layout },
    { "MODEL_DISTRIBUTE_HORIZ", KeyScope::Layout },
    { "MODEL_DISTRIBUTE_VERT", KeyScope::Layout },
    { "MODEL_FLIP_HORIZ", KeyScope::Layout },
    { "MODEL_FLIP_VERT", KeyScope::Layout },
    { "MODEL_SUBMODELS", KeyScope::Layout },
    { "MODEL_FACES", KeyScope::Layout },
    { "MODEL_STATES", KeyScope::Layout },
    { "MODEL_MODELDATA", KeyScope::Layout },
    { "CANCEL_RENDER", KeyScope::Sequence },
    { "TOGGLE_RENDER", KeyScope::Sequence },
    { "PRESETS_TOGGLE", KeyScope::Sequence },
    { "APPLY_SELECTED_PRESET", KeyScope::Sequence },
    { "FOCUS_SEQUENCER", KeyScope::All },
    { "VALUECURVES_TOGGLE", KeyScope::Sequence },
    { "COLOR_DROPPER_TOGGLE", KeyScope::Sequence },
    { "AUDIO_FULL_SPEED", KeyScope::Sequence },
    { "AUDIO_F_1_5_SPEED", KeyScope::Sequence },
    { "AUDIO_F_2_SPEED", KeyScope::Sequence },
    { "AUDIO_F_3_SPEED", KeyScope::Sequence },
    { "AUDIO_F_4_SPEED", KeyScope::Sequence },
    { "AUDIO_S_3_4_SPEED", KeyScope::Sequence },
    { "AUDIO_S_1_2_SPEED", KeyScope::Sequence },
    { "AUDIO_S_1_4_SPEED", KeyScope::Sequence },
    { "PRIOR_TAG", KeyScope::Sequence },
    { "NEXT_TAG", KeyScope::Sequence },
    { "PLAY_PRIOR_TAG", KeyScope::Sequence },
    { "PLAY_NEXT_TAG", KeyScope::Sequence },
    { "MODEL_TOGGLE", KeyScope::Sequence },
    { "MODEL_DISABLE", KeyScope::Sequence },
    { "MODEL_ENABLE", KeyScope::Sequence },
    { "EFFECT_TOGGLE", KeyScope::Sequence },
    { "EFFECT_DISABLE", KeyScope::Sequence },
    { "EFFECT_ENABLE", KeyScope::Sequence },
    { "MODEL_EFFECT_TOGGLE", KeyScope::Sequence },
    { "EFFECTS_TO_TIMING", KeyScope::Sequence },
    { "SELECT_TIMING_1", KeyScope::Sequence },
    { "SELECT_TIMING_2", KeyScope::Sequence },
    { "SELECT_TIMING_3", KeyScope::Sequence },
    { "SELECT_TIMING_4", KeyScope::Sequence },
    { "SELECT_TIMING_5", KeyScope::Sequence },
    { "SELECT_TIMING_6", KeyScope::Sequence },
    { "SELECT_TIMING_7", KeyScope::Sequence },
    { "SELECT_TIMING_8", KeyScope::Sequence },
    { "SELECT_TIMING_9", KeyScope::Sequence },
    { "SELECT_NO_TIMING", KeyScope::Sequence },
    { "INCREASE_SPEED", KeyScope::Sequence },
    { "DECREASE_SPEED", KeyScope::Sequence },
    { "JUKEBOX_BTN_1", KeyScope::Sequence },
    { "JUKEBOX_BTN_2", KeyScope::Sequence },
    { "JUKEBOX_BTN_3", KeyScope::Sequence },
    { "JUKEBOX_BTN_4", KeyScope::Sequence },
    { "JUKEBOX_BTN_5", KeyScope::Sequence },
    { "FPP_CONNECT", KeyScope::All }
};

#pragma endregion

#pragma region Key Binding Tips

static const std::map<std::string, std::string> s_keyBindingTips = {
    { "TIMING_ADD", "Add a timing mark." },
    { "TIMING_SPLIT", "Split a timing mark." },
    { "DUPLICATE_RIGHT", "Duplicate selected effect(s) to the right." },
    { "DUPLICATE_LEFT", "Duplicate selected effect(s) to the left." },
    { "DUPLICATE_UP", "Duplicate selected effect(s) to the track above." },
    { "DUPLICATE_DOWN", "Duplicate selected effect(s) to the track below." },
    { "AUTO_ETC_PHONEME", "Split selected phoneme timing in half, setting first half to 'etc'." },
    { "ZOOM_IN", "Zoom into the effects grid." },
    { "ZOOM_OUT", "Zoom out of the effects grid." },
    { "ZOOM_SEL", "Zoom so selected timeline fills the screen." },
    { "RANDOM", "Insert random effects." },
    { "RENDER_ALL", "Render all." },
    { "SAVE_CURRENT_TAB", "Save the currently selected tab." },
    { "LIGHTS_TOGGLE", "Toggle output to lights on/off." },
    { "OPEN_SEQUENCE", "Open a sequence." },
    { "CLOSE_SEQUENCE", "Close the open sequence." },
    { "NEW_SEQUENCE", "Create a new sequence." },
    { "PASTE_BY_CELL", "Put cut/copy/paste into Paste By Cell mode." },
    { "PASTE_BY_TIME", "Put cut/copy/paste into Paste By Time mode." },
    { "BACKUP", "Backup your show folder." },
    { "ALTERNATE_BACKUP", "Backup your show folder to the alternate backup location." },
    { "SELECT_SHOW_FOLDER", "Change your current show folder." },
    { "SAVEAS_SEQUENCE", "Save the current sequence to a new file." },
    { "SAVE_SEQUENCE", "Save the current sequence." },
    { "EFFECT_SETTINGS_TOGGLE", "Toggle display of the effect settings panel." },
    { "EFFECT_ASSIST_TOGGLE", "Toggle display of the effect assist panel." },
    { "COLOR_TOGGLE", "Toggle display of the color panel." },
    { "LAYER_SETTING_TOGGLE", "Toggle display of the layer settings panel." },
    { "LAYER_BLENDING_TOGGLE", "Toggle display of the layer blending panel." },
    { "MODEL_PREVIEW_TOGGLE", "Toggle display of the model preview panel." },
    { "HOUSE_PREVIEW_TOGGLE", "Toggle display of the house preview panel." },
    { "EFFECTS_TOGGLE", "Toggle display of the effect dropper panel." },
    { "DISPLAY_ELEMENTS_TOGGLE", "Toggle display of the display elements panel." },
    { "JUKEBOX_TOGGLE", "Toggle display of the jukebox panel." },
    { "SEQUENCE_SETTINGS", "Display the sequence settings." },
    { "LOCK_EFFECT", "Lock the selected effects." },
    { "UNLOCK_EFFECT", "Unlock the selected effects." },
    { "MARK_SPOT", "Mark the current spot in the sequencer so you can return to it." },
    { "RETURN_TO_SPOT", "Return to the previously marked spot in the sequencer." },
    { "EFFECT_DESCRIPTION", "Open the effect description dialog." },
    { "EFFECT_ALIGN_START", "Align the selected effects to have the same start times." },
    { "EFFECT_ALIGN_END", "Align the selected effects to have the same end times." },
    { "EFFECT_ALIGN_BOTH", "Align the selected effects to have the same start and end times." },
    { "INSERT_LAYER_ABOVE", "Insert a sequencing layer above the current row." },
    { "INSERT_LAYER_BELOW", "Insert a sequencing layer below the current row." },
    { "TOGGLE_ELEMENT_EXPAND", "Expand the current element." },
    { "SELECT_ALL", "Select all effects and timing marks." },
    { "SELECT_ALL_NO_TIMING", "Select all effects but not timing marks." },
    { "SHOW_PRESETS", "Show the effect presets panel." },
    { "SEARCH_TOGGLE", "Toggle display of the effect search panel." },
    { "PERSPECTIVES_TOGGLE", "Toggle display of the perspectives panel." },
    { "EFFECT_UPDATE", "Apply the current effect settings to all selected effects." },
    { "COLOR_UPDATE", "Apply the current colors to all selected effects." },
    { "SET_COLOR_1", "Set selected effects to palette color 1 (white)." },
    { "SET_COLOR_2", "Set selected effects to palette color 2 (red)." },
    { "SET_COLOR_3", "Set selected effects to palette color 3 (green)." },
    { "SET_COLOR_4", "Set selected effects to palette color 4 (blue)." },
    { "SET_COLOR_5", "Set selected effects to palette color 5 (yellow)." },
    { "SET_COLOR_6", "Set selected effects to palette color 6 (black)." },
    { "SET_COLOR_7", "Set selected effects to palette color 7 (cyan)." },
    { "SET_COLOR_8", "Set selected effects to palette color 8 (magenta)." },
    { "PLAY_LOOP", "Play the selected part of the song repeatedly." },
    { "PLAY", "Play the song." },
    { "TOGGLE_PLAY", "Play/Stop playing the song." },
    { "START_OF_SONG", "Jump to the start of the song." },
    { "END_OF_SONG", "Jump to the end of the song." },
    { "STOP", "Stop sequence playback." },
    { "PAUSE", "Pause sequence playback." },
    { "EFFECT", "Insert an effect." },
    { "APPLYSETTING", "Apply setting to selected effects." },
    { "PRESET", "Insert a preset effect." },
    { "LOCK_MODEL", "Lock the selected models." },
    { "UNLOCK_MODEL", "Unlock the selected models." },
    { "GROUP_MODELS", "Create a group from the selected models." },
    { "WIRING_VIEW", "Display the wiring view for the selected model." },
    { "EXPORT_MODEL_CAD", "Export the selected model as a DXF or STL or VRML File." },
    { "EXPORT_LAYOUT_DXF", "Export the default layout as a DXF File." },
    { "NODE_LAYOUT", "Display the node layout for the selected model." },
    { "SAVE_LAYOUT", "Save the layout tab." },
    { "SELECT_ALL_MODELS", "Select all models." },
    { "MODEL_ALIGN_TOP", "Align the selected models to the top edge." },
    { "MODEL_ALIGN_BOTTOM", "Align the selected models to the bottom edge." },
    { "MODEL_ALIGN_LEFT", "Align the selected models to the left edge." },
    { "MODEL_ALIGN_RIGHT", "Align the selected models to the right edge." },
    { "MODEL_ALIGN_CENTER_VERT", "Align the selected models to be vertically centered." },
    { "MODEL_ALIGN_CENTER_HORIZ", "Align the selected models to be horizontally centered." },
    { "MODEL_ALIGN_FRONTS", "Align the selected models to the front edge." },
    { "MODEL_ALIGN_BACKS", "Align the selected models to the back edge." },
    { "MODEL_ALIGN_GROUND", "Align the selected models to the ground." },
    { "MODEL_DISTRIBUTE_HORIZ", "Distribute the selected model horizontally." },
    { "MODEL_DISTRIBUTE_VERT", "Distribute the selected models vertically." },
    { "MODEL_FLIP_HORIZ", "Flip the selected models horizontally." },
    { "MODEL_FLIP_VERT", "Flip the selected models vertically." },
    { "CANCEL_RENDER", "Cancel current rendering activity." },
    { "TOGGLE_RENDER", "Toggle background rendering." },
    { "PRESETS_TOGGLE", "Toggle display of the presets panel." },
    { "APPLY_SELECTED_PRESET", "Apply the currently selected preset in the presets panel." },
    { "FOCUS_SEQUENCER", "Force keyboard focus to the effects grid." },
    { "VALUECURVES_TOGGLE", "Toggle display of the value curves dropper panel." },
    { "COLOR_DROPPER_TOGGLE", "Toggle display of the color dropper panel." },
    { "AUDIO_FULL_SPEED", "Playback audio at normal speed." },
    { "AUDIO_F_1_5_SPEED", "Playback audio at 1.5 times speed." },
    { "AUDIO_F_2_SPEED", "Playback audio at 2 times speed." },
    { "AUDIO_F_3_SPEED", "Playback audio at 3 times speed." },
    { "AUDIO_F_4_SPEED", "Playback audio at 4 times speed." },
    { "AUDIO_S_3_4_SPEED", "Playback audio at 3/4 speed." },
    { "AUDIO_S_1_2_SPEED", "Playback audio at 1/2 speed." },
    { "AUDIO_S_1_4_SPEED", "Playback audio at 1/4 speed." },
    { "PRIOR_TAG", "Jump to prior audio tag." },
    { "NEXT_TAG", "Jump to next audio tag." },
    { "PLAY_PRIOR_TAG", "Play from prior audio tag." },
    { "PLAY_NEXT_TAG", "Play from next audio tag." },
    { "MODEL_SUBMODELS", "Edit model submodels." },
    { "MODEL_FACES", "Edit model faces." },
    { "MODEL_STATES", "Edit model states." },
    { "MODEL_MODELDATA", "Edit custom model data." },
    { "MODEL_TOGGLE", "Toggle (Enable/Disable) rendering of the selected model in the sequencer" },
    { "MODEL_DISABLE", "Disable rendering of the selected model in the sequencer" },
    { "MODEL_ENABLE", "Enable rendering of the selected model in the sequencer" },
    { "EFFECT_TOGGLE", "Toggle (Enable/Disable) rendering of the selected effects in the sequencer" },
    { "EFFECT_DISABLE", "Disable rendering of the selected effects in the sequencer" },
    { "EFFECT_ENABLE", "Enable rendering of the selected effects in the sequencer" },
    { "MODEL_EFFECT_TOGGLE", "Toggle (Enable/Disable) rendering of the selected model or the effects in the sequencer" },
    { "EFFECTS_TO_TIMING", "Convert selected effects to timing marks." },
    { "SELECT_TIMING_1", "Select first timing." },
    { "SELECT_TIMING_2", "Select second timing." },
    { "SELECT_TIMING_3", "Select third timing." },
    { "SELECT_TIMING_4", "Select fourth timing." },
    { "SELECT_TIMING_5", "Select fifth timing." },
    { "SELECT_TIMING_6", "Select sixth timing." },
    { "SELECT_TIMING_7", "Select seventh timing." },
    { "SELECT_TIMING_8", "Select eighth timing." },
    { "SELECT_TIMING_9", "Select ninth timing." },
    { "SELECT_NO_TIMING", "Select no timing tracks." },
    { "INCREASE_SPEED", "Increase speed." },
    { "DECREASE_SPEED", "Decrease speed." },
    { "JUKEBOX_BTN_1", "Jukebox Button 1." },
    { "JUKEBOX_BTN_2", "Jukebox Button 2." },
    { "JUKEBOX_BTN_3", "Jukebox Button 3." },
    { "JUKEBOX_BTN_4", "Jukebox Button 4." },
    { "JUKEBOX_BTN_5", "Jukebox Button 5." },
    { "FPP_CONNECT", "Run FPP Connect" },
};

#pragma endregion

#pragma region Key Equivalents

// Keys we consider equivalent (e.g., numpad keys to regular keys)
static const std::vector<std::pair<KeyCode, KeyCode>> s_keyEquivalents = {
    // Numpad numbers to regular numbers
    { static_cast<KeyCode>('0'), static_cast<KeyCode>(0x60) }, // NUMPAD0
    { static_cast<KeyCode>('1'), static_cast<KeyCode>(0x61) },
    { static_cast<KeyCode>('2'), static_cast<KeyCode>(0x62) },
    { static_cast<KeyCode>('3'), static_cast<KeyCode>(0x63) },
    { static_cast<KeyCode>('4'), static_cast<KeyCode>(0x64) },
    { static_cast<KeyCode>('5'), static_cast<KeyCode>(0x65) },
    { static_cast<KeyCode>('6'), static_cast<KeyCode>(0x66) },
    { static_cast<KeyCode>('7'), static_cast<KeyCode>(0x67) },
    { static_cast<KeyCode>('8'), static_cast<KeyCode>(0x68) },
    { static_cast<KeyCode>('9'), static_cast<KeyCode>(0x69) },
    // Numpad operators
    { static_cast<KeyCode>('*'), static_cast<KeyCode>(0x6A) }, // MULTIPLY
    { static_cast<KeyCode>('+'), static_cast<KeyCode>(0x6B) }, // ADD
    { static_cast<KeyCode>('-'), static_cast<KeyCode>(0x6D) }, // SUBTRACT
    { static_cast<KeyCode>('.'), static_cast<KeyCode>(0x6E) }, // DECIMAL
    { static_cast<KeyCode>('/'), static_cast<KeyCode>(0x6F) }, // DIVIDE
};

#pragma endregion

#pragma region Default Bindings

// Default key bindings - matches legacy xLights defaults
static std::vector<KeyBinding> createDefaultBindings() {
    std::vector<KeyBinding> bindings;

    // Layout shortcuts
    bindings.emplace_back("a", false, "SELECT_ALL_MODELS", true);
    bindings.emplace_back("a", false, "SELECT_ALL", true, true);
    bindings.emplace_back("a", false, "SELECT_ALL_NO_TIMING", true);

    // File operations
    bindings.emplace_back("F10", false, "BACKUP");
    bindings.emplace_back("F11", false, "ALTERNATE_BACKUP");
    bindings.emplace_back("F9", false, "SELECT_SHOW_FOLDER");
    bindings.emplace_back("", true, "LIGHTS_TOGGLE");
    bindings.emplace_back("o", false, "OPEN_SEQUENCE", true);
    bindings.emplace_back("w", false, "CLOSE_SEQUENCE", true);
    bindings.emplace_back("n", false, "NEW_SEQUENCE", true);
    bindings.emplace_back("", true, "RENDER_ALL");
    bindings.emplace_back("", true, "PASTE_BY_CELL");
    bindings.emplace_back("", true, "PASTE_BY_TIME");
    bindings.emplace_back("", true, "SEQUENCE_SETTINGS");

    // Playback
    bindings.emplace_back("", true, "PLAY_LOOP");
    bindings.emplace_back("HOME", false, "START_OF_SONG");
    bindings.emplace_back("END", false, "END_OF_SONG");
    bindings.emplace_back("", true, "PLAY");
    bindings.emplace_back("SPACE", false, "TOGGLE_PLAY");
    bindings.emplace_back("", true, "STOP");
    bindings.emplace_back("PAUSE", false, "PAUSE");

    // Audio speed
    bindings.emplace_back("", true, "AUDIO_FULL_SPEED", true, true);
    bindings.emplace_back("", true, "AUDIO_F_1_5_SPEED", true, true);
    bindings.emplace_back("", true, "AUDIO_F_2_SPEED", true, true);
    bindings.emplace_back("", true, "AUDIO_F_3_SPEED", true, true);
    bindings.emplace_back("", true, "AUDIO_F_4_SPEED", true, true);
    bindings.emplace_back("", true, "AUDIO_S_3_4_SPEED", true, true);
    bindings.emplace_back("", true, "AUDIO_S_1_2_SPEED", true, true);
    bindings.emplace_back("", true, "AUDIO_S_1_4_SPEED", true, true);

    // Tags
    bindings.emplace_back("", true, "PRIOR_TAG", true, true);
    bindings.emplace_back("", true, "NEXT_TAG", true, true);
    bindings.emplace_back("", true, "INCREASE_SPEED", true, true);
    bindings.emplace_back("", true, "DECREASE_SPEED", true, true);

    // Jukebox
    bindings.emplace_back("", true, "JUKEBOX_BTN_1", true, true);
    bindings.emplace_back("", true, "JUKEBOX_BTN_2", true, true);
    bindings.emplace_back("", true, "JUKEBOX_BTN_3", true, true);
    bindings.emplace_back("", true, "JUKEBOX_BTN_4", true, true);
    bindings.emplace_back("", true, "JUKEBOX_BTN_5", true, true);
    bindings.emplace_back("", true, "FPP_CONNECT", true, true);

    // Save operations
    bindings.emplace_back("s", false, "SAVE_CURRENT_TAB", true);
    bindings.emplace_back("", true, "SAVE_SEQUENCE", true);
    bindings.emplace_back("", true, "SAVEAS_SEQUENCE", true, false, true);

    // Timing
    bindings.emplace_back("t", false, "TIMING_ADD");
    bindings.emplace_back("s", false, "TIMING_SPLIT");

    // Duplicate
    bindings.emplace_back("RIGHT", false, "DUPLICATE_RIGHT", false, true, true);
    bindings.emplace_back("LEFT", false, "DUPLICATE_LEFT", false, true, true);
    bindings.emplace_back("UP", false, "DUPLICATE_UP", false, true, true);
    bindings.emplace_back("DOWN", false, "DUPLICATE_DOWN", false, true, true);
    bindings.emplace_back("", false, "AUTO_ETC_PHONEME");

    // Zoom
    bindings.emplace_back("+", false, "ZOOM_IN");
    bindings.emplace_back("-", false, "ZOOM_OUT");
    bindings.emplace_back("Y", false, "ZOOM_SEL");

    // Random
    bindings.emplace_back("R", false, "RANDOM", false, false, true);

    // Panel toggles
    bindings.emplace_back("F1", false, "EFFECT_SETTINGS_TOGGLE", true);
    bindings.emplace_back("F8", false, "EFFECT_ASSIST_TOGGLE", true);
    bindings.emplace_back("F2", false, "COLOR_TOGGLE", true);
    bindings.emplace_back("F3", false, "LAYER_SETTING_TOGGLE", true);
    bindings.emplace_back("F4", false, "LAYER_BLENDING_TOGGLE", true);
    bindings.emplace_back("F5", false, "MODEL_PREVIEW_TOGGLE", true);
    bindings.emplace_back("F6", false, "HOUSE_PREVIEW_TOGGLE", true);
    bindings.emplace_back("F9", false, "EFFECTS_TOGGLE", true);
    bindings.emplace_back("F7", false, "DISPLAY_ELEMENTS_TOGGLE", true);
    bindings.emplace_back("F8", false, "JUKEBOX_TOGGLE", true, true);

    // Lock/unlock
    bindings.emplace_back("l", false, "LOCK_EFFECT", true);
    bindings.emplace_back("u", false, "UNLOCK_EFFECT", true);

    // Mark/return
    bindings.emplace_back(".", false, "MARK_SPOT", true);
    bindings.emplace_back("/", false, "RETURN_TO_SPOT", true);
    bindings.emplace_back(".", false, "MARK_SPOT", false, false, false, true);
    bindings.emplace_back("/", false, "RETURN_TO_SPOT", false, false, false, true);

    // Alignment
    bindings.emplace_back("", true, "EFFECT_DESCRIPTION", true);
    bindings.emplace_back("", true, "EFFECT_ALIGN_START", true, true);
    bindings.emplace_back("", true, "EFFECT_ALIGN_END", true, true);
    bindings.emplace_back("", true, "EFFECT_ALIGN_BOTH", true, true);

    // Layers
    bindings.emplace_back("I", false, "INSERT_LAYER_ABOVE", true, false, true);
    bindings.emplace_back("A", false, "INSERT_LAYER_BELOW", true, false, true);
    bindings.emplace_back("X", false, "TOGGLE_ELEMENT_EXPAND", true, false, true);

    // Presets
    bindings.emplace_back("", false, "SHOW_PRESETS");
    bindings.emplace_back("F10", false, "PRESETS_TOGGLE", true);
    bindings.emplace_back("", false, "APPLY_SELECTED_PRESET");
    bindings.emplace_back("F12", false, "VALUECURVES_TOGGLE", false, true);
    bindings.emplace_back("F11", false, "COLOR_DROPPER_TOGGLE", false, true);
    bindings.emplace_back("F12", false, "FOCUS_SEQUENCER");
    bindings.emplace_back("F11", false, "SEARCH_TOGGLE", true);
    bindings.emplace_back("F12", false, "PERSPECTIVES_TOGGLE", true);

    // Update
    bindings.emplace_back("F5", false, "EFFECT_UPDATE");
    bindings.emplace_back("F5", false, "COLOR_UPDATE", false, false, true);

    // Colors
    bindings.emplace_back("1", false, "SET_COLOR_1", true);
    bindings.emplace_back("2", false, "SET_COLOR_2", true);
    bindings.emplace_back("3", false, "SET_COLOR_3", true);
    bindings.emplace_back("4", false, "SET_COLOR_4", true);
    bindings.emplace_back("5", false, "SET_COLOR_5", true);
    bindings.emplace_back("6", false, "SET_COLOR_6", true);
    bindings.emplace_back("7", false, "SET_COLOR_7", true);
    bindings.emplace_back("8", false, "SET_COLOR_8", true);

    // Render
    bindings.emplace_back("ESCAPE", false, "CANCEL_RENDER");
    bindings.emplace_back("", false, "TOGGLE_RENDER");

    // Layout model operations
    bindings.emplace_back("l", false, "LOCK_MODEL", true);
    bindings.emplace_back("u", false, "UNLOCK_MODEL", true);
    bindings.emplace_back("g", false, "GROUP_MODELS", true);
    bindings.emplace_back("", true, "WIRING_VIEW", true);
    bindings.emplace_back("", true, "EXPORT_MODEL_CAD", true);
    bindings.emplace_back("", true, "EXPORT_LAYOUT_DXF", true);
    bindings.emplace_back("", true, "NODE_LAYOUT", true);
    bindings.emplace_back("", true, "SAVE_LAYOUT", true, false, true);
    bindings.emplace_back("", true, "MODEL_ALIGN_TOP", true, false, true);
    bindings.emplace_back("", true, "MODEL_ALIGN_BOTTOM", true, false, true);
    bindings.emplace_back("", true, "MODEL_ALIGN_LEFT", true, false, true);
    bindings.emplace_back("", true, "MODEL_ALIGN_RIGHT", true, false, true);
    bindings.emplace_back("", true, "MODEL_ALIGN_CENTER_VERT", true, false, true);
    bindings.emplace_back("", true, "MODEL_ALIGN_CENTER_HORIZ", true, false, true);
    bindings.emplace_back("", true, "MODEL_ALIGN_BACKS", true, false, true);
    bindings.emplace_back("", true, "MODEL_ALIGN_FRONTS", true, false, true);
    bindings.emplace_back("", true, "MODEL_ALIGN_GROUND", true, false, true);
    bindings.emplace_back("", true, "MODEL_DISTRIBUTE_HORIZ", true, false, true);
    bindings.emplace_back("", true, "MODEL_DISTRIBUTE_VERT", true, false, true);
    bindings.emplace_back("", true, "MODEL_FLIP_HORIZ", true, false, true);
    bindings.emplace_back("", true, "MODEL_FLIP_VERT", true, false, true);
    bindings.emplace_back("", true, "MODEL_SUBMODELS", true);
    bindings.emplace_back("", true, "MODEL_FACES", true);
    bindings.emplace_back("", true, "MODEL_STATES", true);
    bindings.emplace_back("", true, "MODEL_MODELDATA", true);

    // Effect shortcuts
    bindings.emplace_back("o", false, "On", "E_TEXTCTRL_Eff_On_End=100,E_TEXTCTRL_Eff_On_Start=100", XLIGHTS_VERSION);
    bindings.emplace_back("u", false, "On", "E_TEXTCTRL_Eff_On_End=100,E_TEXTCTRL_Eff_On_Start=0", XLIGHTS_VERSION);
    bindings.emplace_back("d", false, "On", "E_TEXTCTRL_Eff_On_End=0,E_TEXTCTRL_Eff_On_Start=100", XLIGHTS_VERSION);
    bindings.emplace_back("m", false, "Morph", "", XLIGHTS_VERSION);
    bindings.emplace_back("c", false, "Curtain", "", XLIGHTS_VERSION);
    bindings.emplace_back("i", false, "Circles", "", XLIGHTS_VERSION);
    bindings.emplace_back("b", false, "Bars", "", XLIGHTS_VERSION);
    bindings.emplace_back("y", false, "Butterfly", "", XLIGHTS_VERSION);
    bindings.emplace_back("f", false, "Fire", "", XLIGHTS_VERSION);
    bindings.emplace_back("g", false, "Garlands", "", XLIGHTS_VERSION);
    bindings.emplace_back("p", false, "Pinwheel", "", XLIGHTS_VERSION);
    bindings.emplace_back("r", false, "Ripple", "", XLIGHTS_VERSION);
    bindings.emplace_back("x", false, "Text", "", XLIGHTS_VERSION);
    bindings.emplace_back("S", false, "Spirals", "", XLIGHTS_VERSION, false, false, true);
    bindings.emplace_back("w", false, "Color Wash", "", XLIGHTS_VERSION);
    bindings.emplace_back("n", false, "Snowflakes", "", XLIGHTS_VERSION);
    bindings.emplace_back("O", false, "Off", "", XLIGHTS_VERSION, false, false, true);
    bindings.emplace_back("F", false, "Fan", "", XLIGHTS_VERSION, false, false, true);

    // Apply setting shortcuts
    bindings.emplace_back(true, "U", "T_TEXTCTRL_Fadein=1.00", XLIGHTS_VERSION, false, false, true, false, true);
    bindings.emplace_back(true, "D", "T_TEXTCTRL_Fadeout=1.00", XLIGHTS_VERSION, false, false, true, false, true);

    return bindings;
}

static std::vector<KeyBinding> s_defaultBindings;

#pragma endregion

#pragma region Utility Functions

std::string scopeToString(KeyScope scope) {
    switch (scope) {
        case KeyScope::All: return "All";
        case KeyScope::Setup: return "Setup";
        case KeyScope::Layout: return "Layout";
        case KeyScope::Sequence: return "Sequence";
        default: return "Invalid";
    }
}

KeyScope stringToScope(const std::string& str) {
    if (str == "All") return KeyScope::All;
    if (str == "Setup") return KeyScope::Setup;
    if (str == "Layout") return KeyScope::Layout;
    if (str == "Sequence") return KeyScope::Sequence;
    return KeyScope::Invalid;
}

const std::vector<std::pair<std::string, KeyScope>>& getKeyBindingTypes() {
    return s_keyBindingTypes;
}

const std::vector<KeyBinding>& getDefaultBindings() {
    if (s_defaultBindings.empty()) {
        s_defaultBindings = createDefaultBindings();
    }
    return s_defaultBindings;
}

std::string getBindingTip(const std::string& type) {
    auto it = s_keyBindingTips.find(type);
    if (it != s_keyBindingTips.end()) {
        return it->second;
    }
    return "";
}

// String utility functions
static std::string toUpper(const std::string& str) {
    std::string result = str;
    std::transform(result.begin(), result.end(), result.begin(), ::toupper);
    return result;
}

static std::string toLower(const std::string& str) {
    std::string result = str;
    std::transform(result.begin(), result.end(), result.begin(), ::tolower);
    return result;
}

static std::string trim(const std::string& str) {
    size_t first = str.find_first_not_of(" \t\n\r");
    if (first == std::string::npos) return "";
    size_t last = str.find_last_not_of(" \t\n\r");
    return str.substr(first, last - first + 1);
}

static std::string capitalize(const std::string& str) {
    if (str.empty()) return str;
    std::string result = toLower(str);
    result[0] = static_cast<char>(std::toupper(result[0]));
    return result;
}

#pragma endregion

#pragma region KeyBinding Implementation

bool KeyBinding::isShiftedKey(int ch) noexcept {
    if (ch > 127) return false;
    static const std::string shiftedChars = "~!@#$%^&*()_+{}|\":<>?";
    return shiftedChars.find(static_cast<char>(ch)) != std::string::npos;
}

std::string KeyBinding::parseKey(const std::string& k, bool& ctrl, bool& alt,
                                  bool& shift, bool& rawCtrl) noexcept {
    std::string key = k;
    auto pos = key.find('+');
    while (pos != std::string::npos) {
        std::string prefix = key.substr(0, pos);
        if (prefix == "ALT") alt = true;
        if (prefix == "SHIFT") shift = true;
        if (prefix == "CTRL") ctrl = true;
        if (prefix == "RCTRL") rawCtrl = true;
        key = key.substr(pos + 1);
        pos = key.find('+');
    }
    return key;
}

const std::vector<KeyCode>& KeyBinding::getPossibleKeys() {
    static bool init = false;
    static std::vector<KeyCode> keys;

    if (!init) {
        init = true;
        keys = {
            KeyCode::Escape,
            KeyCode::Home,
            KeyCode::End,
            KeyCode::Insert,
            KeyCode::Space,
            KeyCode::Delete,
            KeyCode::Backspace,
            KeyCode::Tab,
            KeyCode::Down,
            KeyCode::Up,
            KeyCode::Left,
            KeyCode::Right,
            KeyCode::PageUp,
            KeyCode::PageDown,
            KeyCode::Pause,
            KeyCode::Return,
            KeyCode::F1, KeyCode::F2, KeyCode::F3, KeyCode::F4,
            KeyCode::F5, KeyCode::F6, KeyCode::F7, KeyCode::F8,
            KeyCode::F9, KeyCode::F10, KeyCode::F11, KeyCode::F12,
            KeyCode::F13, KeyCode::F14, KeyCode::F15, KeyCode::F16,
            KeyCode::F17, KeyCode::F18, KeyCode::F19, KeyCode::F20,
            KeyCode::F21, KeyCode::F22, KeyCode::F23, KeyCode::F24
        };

        // Add printable characters (! through @, [ through ~)
        for (int i = 33; i < 65; i++) {
            keys.push_back(static_cast<KeyCode>(i));
        }
        for (int i = 91; i < 127; i++) {
            keys.push_back(static_cast<KeyCode>(i));
        }
    }

    return keys;
}

std::string KeyBinding::encodeKey(KeyCode key, bool shift) noexcept {
    switch (key) {
        case KeyCode::Escape: return "ESCAPE";
        case KeyCode::Home: return "HOME";
        case KeyCode::End: return "END";
        case KeyCode::Insert: return "INSERT";
        case KeyCode::Space: return "SPACE";
        case KeyCode::Delete: return "DELETE";
        case KeyCode::Backspace: return "BACKSPACE";
        case KeyCode::Tab: return "TAB";
        case KeyCode::Down: return "DOWN";
        case KeyCode::Up: return "UP";
        case KeyCode::Left: return "LEFT";
        case KeyCode::Right: return "RIGHT";
        case KeyCode::PageUp: return "PGUP";
        case KeyCode::PageDown: return "PGDOWN";
        case KeyCode::Pause: return "PAUSE";
        case KeyCode::Return: return "ENTER";
        case KeyCode::F1: return "F1";
        case KeyCode::F2: return "F2";
        case KeyCode::F3: return "F3";
        case KeyCode::F4: return "F4";
        case KeyCode::F5: return "F5";
        case KeyCode::F6: return "F6";
        case KeyCode::F7: return "F7";
        case KeyCode::F8: return "F8";
        case KeyCode::F9: return "F9";
        case KeyCode::F10: return "F10";
        case KeyCode::F11: return "F11";
        case KeyCode::F12: return "F12";
        case KeyCode::F13: return "F13";
        case KeyCode::F14: return "F14";
        case KeyCode::F15: return "F15";
        case KeyCode::F16: return "F16";
        case KeyCode::F17: return "F17";
        case KeyCode::F18: return "F18";
        case KeyCode::F19: return "F19";
        case KeyCode::F20: return "F20";
        case KeyCode::F21: return "F21";
        case KeyCode::F22: return "F22";
        case KeyCode::F23: return "F23";
        case KeyCode::F24: return "F24";
        case KeyCode::None: return "";
        default: {
            int keyInt = static_cast<int>(key);
            if (keyInt > 32 && keyInt < 128) {
                char c = static_cast<char>(keyInt);
                if (shift) {
                    return std::string(1, static_cast<char>(std::toupper(c)));
                } else {
                    return std::string(1, static_cast<char>(std::tolower(c)));
                }
            }
            return "";
        }
    }
}

KeyCode KeyBinding::decodeKey(const std::string& keyStr) noexcept {
    std::string key = toUpper(keyStr);

    if (key.empty()) return KeyCode::None;
    if (key == "ESC" || key == "ESCAPE") return KeyCode::Escape;
    if (key == "DEL" || key == "DELETE") return KeyCode::Delete;
    if (key == "BACK" || key == "BACKSPACE") return KeyCode::Backspace;
    if (key == "TAB") return KeyCode::Tab;
    if (key == "SPACE") return KeyCode::Space;
    if (key == "DOWN") return KeyCode::Down;
    if (key == "UP") return KeyCode::Up;
    if (key == "LEFT") return KeyCode::Left;
    if (key == "RIGHT") return KeyCode::Right;
    if (key == "HOME") return KeyCode::Home;
    if (key == "END") return KeyCode::End;
    if (key == "INSERT") return KeyCode::Insert;
    if (key == "PGUP" || key == "PAGEUP") return KeyCode::PageUp;
    if (key == "PGDN" || key == "PAGEDOWN") return KeyCode::PageDown;
    if (key == "PAUSE") return KeyCode::Pause;
    if (key == "RETURN" || key == "ENTER") return KeyCode::Return;
    if (key == "F1") return KeyCode::F1;
    if (key == "F2") return KeyCode::F2;
    if (key == "F3") return KeyCode::F3;
    if (key == "F4") return KeyCode::F4;
    if (key == "F5") return KeyCode::F5;
    if (key == "F6") return KeyCode::F6;
    if (key == "F7") return KeyCode::F7;
    if (key == "F8") return KeyCode::F8;
    if (key == "F9") return KeyCode::F9;
    if (key == "F10") return KeyCode::F10;
    if (key == "F11") return KeyCode::F11;
    if (key == "F12") return KeyCode::F12;
    if (key == "F13") return KeyCode::F13;
    if (key == "F14") return KeyCode::F14;
    if (key == "F15") return KeyCode::F15;
    if (key == "F16") return KeyCode::F16;
    if (key == "F17") return KeyCode::F17;
    if (key == "F18") return KeyCode::F18;
    if (key == "F19") return KeyCode::F19;
    if (key == "F20") return KeyCode::F20;
    if (key == "F21") return KeyCode::F21;
    if (key == "F22") return KeyCode::F22;
    if (key == "F23") return KeyCode::F23;
    if (key == "F24") return KeyCode::F24;

    // Single character - use ASCII value
    if (keyStr.size() == 1) {
        return static_cast<KeyCode>(static_cast<unsigned char>(std::toupper(keyStr[0])));
    }

    return KeyCode::None;
}

bool KeyBinding::isControlEqual(const KeyBinding& binding, bool ctrl, bool rawCtrl) {
#if !defined(__APPLE__)
    // On non-macOS, Ctrl and RawCtrl are often equivalent
    if (ctrl && binding.requiresControl() == ctrl) {
        return true;
    }
    if (rawCtrl && binding.requiresRawControl() == rawCtrl) {
        return true;
    }
#endif
    return binding.requiresControl() == ctrl && binding.requiresRawControl() == rawCtrl;
}

void KeyBinding::initFromType(const std::string& type) {
    auto it = std::find_if(s_keyBindingTypes.begin(), s_keyBindingTypes.end(),
        [&type](const auto& kbt) { return kbt.first == type; });

    if (it == s_keyBindingTypes.end()) {
        _disabled = true;
        _scope = KeyScope::Invalid;
    } else {
        _scope = it->second;
    }
}

void KeyBinding::initTip(const std::string& type) {
    auto it = s_keyBindingTips.find(type);
    if (it != s_keyBindingTips.end()) {
        _tip = it->second;
    }
}

// Standard binding constructors
KeyBinding::KeyBinding(KeyCode key, bool disabled, const std::string& type,
                       bool ctrl, bool alt, bool shift, bool rawCtrl)
    : _type(type), _ctrl(ctrl), _rawCtrl(rawCtrl), _alt(alt), _shift(shift),
      _disabled(disabled), _key(key)
{
    _id = nextId();
    initFromType(type);
    initTip(type);
    _shift |= isShiftedKey(static_cast<int>(_key));
}

KeyBinding::KeyBinding(const std::string& keyStr, bool disabled, const std::string& type,
                       bool ctrl, bool alt, bool shift, bool rawCtrl)
    : _type(type), _ctrl(ctrl), _rawCtrl(rawCtrl), _alt(alt), _shift(shift),
      _disabled(disabled)
{
    _id = nextId();
    _key = decodeKey(keyStr);
    if (_key == KeyCode::None) _disabled = true;
    initFromType(type);
    initTip(type);
    _shift |= isShiftedKey(static_cast<int>(_key));
}

// Effect binding constructors
KeyBinding::KeyBinding(KeyCode key, bool disabled, const std::string& effectName,
                       const std::string& effectSettings, const std::string& version,
                       bool ctrl, bool alt, bool shift, bool rawCtrl)
    : _type("EFFECT"), _effectName(effectName), _effectString(effectSettings),
      _effectDataVersion(version), _ctrl(ctrl), _rawCtrl(rawCtrl), _alt(alt),
      _shift(shift), _disabled(disabled), _key(key)
{
    _id = nextId();
    _scope = KeyScope::Sequence;
    _shift |= isShiftedKey(static_cast<int>(_key));
    _tip = "Insert an effect.";
}

KeyBinding::KeyBinding(const std::string& keyStr, bool disabled, const std::string& effectName,
                       const std::string& effectSettings, const std::string& version,
                       bool ctrl, bool alt, bool shift, bool rawCtrl)
    : _type("EFFECT"), _effectName(effectName), _effectString(effectSettings),
      _effectDataVersion(version), _ctrl(ctrl), _rawCtrl(rawCtrl), _alt(alt),
      _shift(shift), _disabled(disabled)
{
    _id = nextId();
    _key = decodeKey(keyStr);
    if (_key == KeyCode::None) _disabled = true;
    _scope = KeyScope::Sequence;
    _shift |= isShiftedKey(static_cast<int>(_key));
    _tip = "Insert an effect.";
}

// Preset binding constructors
KeyBinding::KeyBinding(bool disabled, KeyCode key, const std::string& presetName,
                       bool ctrl, bool alt, bool shift, bool rawCtrl)
    : _type("PRESET"), _effectName(presetName), _ctrl(ctrl), _rawCtrl(rawCtrl),
      _alt(alt), _shift(shift), _disabled(disabled), _key(key)
{
    _id = nextId();
    _scope = KeyScope::Sequence;
    _shift |= isShiftedKey(static_cast<int>(_key));
    _tip = "Insert a preset effect.";
}

KeyBinding::KeyBinding(bool disabled, const std::string& keyStr, const std::string& presetName,
                       bool ctrl, bool alt, bool shift, bool rawCtrl)
    : _type("PRESET"), _effectName(presetName), _ctrl(ctrl), _rawCtrl(rawCtrl),
      _alt(alt), _shift(shift), _disabled(disabled)
{
    _id = nextId();
    _key = decodeKey(keyStr);
    if (_key == KeyCode::None) _disabled = true;
    _scope = KeyScope::Sequence;
    _shift |= isShiftedKey(static_cast<int>(_key));
    _tip = "Insert a preset effect.";
}

// Apply-setting binding constructors
KeyBinding::KeyBinding(bool disabled, KeyCode key, const std::string& settings,
                       const std::string& version, bool ctrl, bool alt, bool shift, bool rawCtrl,
                       bool /* isApplySetting */)
    : _type("APPLYSETTING"), _effectString(settings), _effectDataVersion(version),
      _ctrl(ctrl), _rawCtrl(rawCtrl), _alt(alt), _shift(shift), _disabled(disabled), _key(key)
{
    _id = nextId();
    _scope = KeyScope::Sequence;
    _shift |= isShiftedKey(static_cast<int>(_key));
    _tip = "Apply setting to selected effects.";
}

KeyBinding::KeyBinding(bool disabled, const std::string& keyStr, const std::string& settings,
                       const std::string& version, bool ctrl, bool alt, bool shift, bool rawCtrl,
                       bool /* isApplySetting */)
    : _type("APPLYSETTING"), _effectString(settings), _effectDataVersion(version),
      _ctrl(ctrl), _rawCtrl(rawCtrl), _alt(alt), _shift(shift), _disabled(disabled)
{
    _id = nextId();
    _key = decodeKey(keyStr);
    if (_key == KeyCode::None) _disabled = true;
    _scope = KeyScope::Sequence;
    _shift |= isShiftedKey(static_cast<int>(_key));
    _tip = "Apply setting to selected effects.";
}

std::string KeyBinding::keyDescription() const noexcept {
    if (_disabled) {
        return "N/A";
    }

    std::string res;
    if (_ctrl) res += "CTRL+";
    if (_rawCtrl) res += "RCTRL+";
    if (_alt) res += "ALT+";

    bool s = _shift;
    if (s && isShiftedKey(static_cast<int>(_key))) s = false;
    if (s) res += "SHIFT+";

    res += encodeKey(_key, _shift);
    return res;
}

std::string KeyBinding::description() const noexcept {
    std::string res = keyDescription();

    // Pad to fixed width
    while (res.size() < 22) {
        res += " ";
    }

    res += ": ";

    if (_type == "EFFECT" || _type == "PRESET") {
        res += _type + " " + _effectName;
    } else {
        std::string t = _type;
        // Capitalize and replace underscores
        std::transform(t.begin(), t.end(), t.begin(), [](char c) {
            return c == '_' ? ' ' : c;
        });
        // Capitalize first letter of each word
        bool capitalize_next = true;
        for (char& c : t) {
            if (capitalize_next && std::isalpha(c)) {
                c = static_cast<char>(std::toupper(c));
                capitalize_next = false;
            } else if (c == ' ') {
                capitalize_next = true;
            } else {
                c = static_cast<char>(std::tolower(c));
            }
        }
        res += t;
    }

    return res;
}

void KeyBinding::setKey(const std::string& keyStr) {
    if (keyStr.empty()) {
        _key = KeyCode::None;
        _disabled = true;
    } else {
        _key = decodeKey(keyStr);
        _disabled = (_key == KeyCode::None);
    }
}

void KeyBinding::setKey(KeyCode key) {
    _key = key;
    // Normalize lowercase letters to uppercase
    int keyInt = static_cast<int>(_key);
    if (keyInt >= 'a' && keyInt <= 'z') {
        _key = static_cast<KeyCode>(keyInt - 32);
    }
    _disabled = (_key == KeyCode::None);
}

bool KeyBinding::isEquivalentKey(KeyCode key) const noexcept {
    for (const auto& [to, from] : s_keyEquivalents) {
        if (from == key && _key == to) {
            return true;
        }
    }
    return false;
}

bool KeyBinding::isDuplicateKey(const KeyBinding& other) const {
    if (_id == other.getId()) return false;

    if (other.getScope() == getScope() ||
        getScope() == KeyScope::All ||
        other.getScope() == KeyScope::All) {

        if (other.getKey() == getKey() &&
            other.requiresAlt() == requiresAlt() &&
            isControlEqual(other, requiresControl(), requiresRawControl()) &&
            other.requiresShift() == requiresShift()) {
            return true;
        }
    }
    return false;
}

#pragma endregion

#pragma region Simple XML Parser

// Minimal XML parsing utilities for key_bindings.xml
// This is a simplified parser that handles the specific format used by xLights

struct XmlAttribute {
    std::string name;
    std::string value;
};

struct XmlElement {
    std::string name;
    std::vector<XmlAttribute> attributes;
    std::string textContent;
    std::vector<XmlElement> children;
};

static std::string getAttribute(const XmlElement& elem, const std::string& name,
                                const std::string& defaultValue = "") {
    for (const auto& attr : elem.attributes) {
        if (attr.name == name) return attr.value;
    }
    return defaultValue;
}

// Simple XML parser - handles the basic structure of key_bindings.xml
static bool parseXmlFile(const std::string& path, XmlElement& root) {
    std::ifstream file(path);
    if (!file.is_open()) return false;

    std::string content((std::istreambuf_iterator<char>(file)),
                        std::istreambuf_iterator<char>());
    file.close();

    // Simple state machine parser
    size_t pos = 0;

    auto skipWhitespace = [&]() {
        while (pos < content.size() && std::isspace(content[pos])) pos++;
    };

    auto parseString = [&](char delimiter) -> std::string {
        std::string result;
        pos++; // skip opening quote
        while (pos < content.size() && content[pos] != delimiter) {
            if (content[pos] == '&') {
                // Handle XML entities
                size_t end = content.find(';', pos);
                if (end != std::string::npos) {
                    std::string entity = content.substr(pos, end - pos + 1);
                    if (entity == "&lt;") result += '<';
                    else if (entity == "&gt;") result += '>';
                    else if (entity == "&amp;") result += '&';
                    else if (entity == "&quot;") result += '"';
                    else if (entity == "&apos;") result += '\'';
                    else result += entity;
                    pos = end + 1;
                    continue;
                }
            }
            result += content[pos++];
        }
        if (pos < content.size()) pos++; // skip closing quote
        return result;
    };

    auto parseName = [&]() -> std::string {
        std::string result;
        while (pos < content.size() &&
               (std::isalnum(content[pos]) || content[pos] == '_' || content[pos] == '-' || content[pos] == ':')) {
            result += content[pos++];
        }
        return result;
    };

    std::function<bool(XmlElement&)> parseElement;
    parseElement = [&](XmlElement& elem) -> bool {
        skipWhitespace();

        // Skip XML declaration and comments
        while (pos < content.size()) {
            if (content.compare(pos, 2, "<?") == 0) {
                size_t end = content.find("?>", pos);
                if (end == std::string::npos) return false;
                pos = end + 2;
                skipWhitespace();
            } else if (content.compare(pos, 4, "<!--") == 0) {
                size_t end = content.find("-->", pos);
                if (end == std::string::npos) return false;
                pos = end + 3;
                skipWhitespace();
            } else {
                break;
            }
        }

        if (pos >= content.size() || content[pos] != '<') return false;
        pos++; // skip <

        // Check for closing tag
        if (pos < content.size() && content[pos] == '/') {
            return false; // closing tag
        }

        // Parse element name
        elem.name = parseName();
        if (elem.name.empty()) return false;

        // Parse attributes
        while (pos < content.size()) {
            skipWhitespace();
            if (content[pos] == '/' || content[pos] == '>') break;

            XmlAttribute attr;
            attr.name = parseName();
            skipWhitespace();
            if (content[pos] == '=') {
                pos++;
                skipWhitespace();
                if (content[pos] == '"' || content[pos] == '\'') {
                    attr.value = parseString(content[pos]);
                }
            }
            elem.attributes.push_back(attr);
        }

        // Handle self-closing tag
        if (pos < content.size() && content[pos] == '/') {
            pos++;
            if (pos < content.size() && content[pos] == '>') {
                pos++;
                return true;
            }
            return false;
        }

        if (pos >= content.size() || content[pos] != '>') return false;
        pos++; // skip >

        // Parse children and text content
        while (pos < content.size()) {
            skipWhitespace();

            // Check for closing tag
            if (pos + 1 < content.size() && content[pos] == '<' && content[pos + 1] == '/') {
                pos += 2;
                std::string closeName = parseName();
                if (closeName != elem.name) return false;
                skipWhitespace();
                if (content[pos] != '>') return false;
                pos++;
                return true;
            }

            // Check for child element
            if (content[pos] == '<') {
                XmlElement child;
                if (parseElement(child)) {
                    elem.children.push_back(child);
                }
            } else {
                // Text content
                while (pos < content.size() && content[pos] != '<') {
                    elem.textContent += content[pos++];
                }
                elem.textContent = trim(elem.textContent);
            }
        }

        return true;
    };

    return parseElement(root);
}

static std::string escapeXml(const std::string& str) {
    std::string result;
    for (char c : str) {
        switch (c) {
            case '<': result += "&lt;"; break;
            case '>': result += "&gt;"; break;
            case '&': result += "&amp;"; break;
            case '"': result += "&quot;"; break;
            case '\'': result += "&apos;"; break;
            default: result += c;
        }
    }
    return result;
}

#pragma endregion

#pragma region KeyBindingMap Implementation

void KeyBindingMap::loadDefaults() noexcept {
    _bindings = createDefaultBindings();
}

bool KeyBindingMap::loadFromFile(const std::string& path) noexcept {
    _filePath = path;

    XmlElement root;
    if (!parseXmlFile(path, root)) {
        // File doesn't exist or is invalid - save defaults
        loadDefaults();
        saveToFile(path);
        return true;
    }

    if (root.name != "keybindings") {
        return false;
    }

    _bindings.clear();

    for (const auto& child : root.children) {
        if (child.name != "keybinding") continue;

        std::string type = getAttribute(child, "type");
        std::string keycode = getAttribute(child, "keycode");
        std::string oldKey = getAttribute(child, "key"); // Legacy attribute

        bool ctrl = getAttribute(child, "control", "FALSE") == "TRUE";
        bool alt = getAttribute(child, "alt", "FALSE") == "TRUE";
        bool shift = getAttribute(child, "shift", "FALSE") == "TRUE";
        bool rawCtrl = getAttribute(child, "rawControl", "FALSE") == "TRUE";

        // Handle legacy "key" attribute
        if (!oldKey.empty()) {
            keycode = oldKey;
            if (!keycode.empty() && keycode[0] >= 'A' && keycode[0] <= 'Z') {
                shift = true;
            } else {
                shift = false;
            }
        }

        bool disabled = keycode.empty();

        if (type == "EFFECT") {
            std::string effect = getAttribute(child, "effect");
            std::string settings = child.textContent;
            std::string version = getAttribute(child, "xLightsVersion", "4.0");

            if (!effect.empty()) {
                _bindings.emplace_back(keycode, disabled, effect, settings, version,
                                       ctrl, alt, shift, rawCtrl);
            }
        } else if (type == "PRESET") {
            std::string presetName = getAttribute(child, "effect");
            _bindings.emplace_back(disabled, keycode, presetName, ctrl, alt, shift, rawCtrl);
        } else if (type == "APPLYSETTING") {
            std::string settings = child.textContent;
            std::string version = getAttribute(child, "xLightsVersion", "4.0");

            if (!settings.empty()) {
                _bindings.emplace_back(disabled, keycode, settings, version,
                                       ctrl, alt, shift, rawCtrl, true);
            }
        } else {
            _bindings.emplace_back(keycode, disabled, type, ctrl, alt, shift, rawCtrl);
        }
    }

    // Essential keys that must be present (for backwards compatibility)
    static const std::vector<std::pair<std::string, std::string>> convertKeys = {
        { "OPEN_SEQUENCE", "CTRL+o" },
        { "NEW_SEQUENCE", "CTRL+n" },
        { "PAUSE", "PAUSE" },
        { "START_OF_SONG", "HOME" },
        { "END_OF_SONG", "END" },
        { "SAVE_CURRENT_TAB", "CTRL+s" },
        { "MARK_SPOT", "CTRL+." },
        { "RETURN_TO_SPOT", "CTRL+/" },
        { "MARK_SPOT", "RCTRL+." },
        { "RETURN_TO_SPOT", "RCTRL+/" },
        { "TOGGLE_PLAY", "SPACE" },
        { "BACKUP", "F10" },
        { "ALTERNATE_BACKUP", "F11" },
        { "SELECT_SHOW_FOLDER", "F9" },
        { "CANCEL_RENDER", "ESCAPE" },
        { "FOCUS_SEQUENCER", "F12" },
        { "COLOR_UPDATE", "SHIFT+F5" }
    };

    // Add missing essential bindings
    for (const auto& [type, keyStr] : convertKeys) {
        bool found = std::find_if(_bindings.begin(), _bindings.end(),
            [&type, &keyStr](const KeyBinding& b) {
                return b.getType() == type && b.keyDescription() == keyStr;
            }) != _bindings.end();

        if (!found) {
            bool ctrl = false, alt = false, shift = false, rawCtrl = false;
            std::string k = KeyBinding::parseKey(keyStr, ctrl, alt, shift, rawCtrl);
            _bindings.emplace_back(k, false, type, ctrl, alt, shift, rawCtrl);
        }
    }

    // Add all missing binding types (disabled)
    for (const auto& [type, scope] : s_keyBindingTypes) {
        if (type != "EFFECT" && type != "PRESET" && type != "APPLYSETTING") {
            bool found = std::find_if(_bindings.begin(), _bindings.end(),
                [&type](const KeyBinding& b) { return b.getType() == type; })
                != _bindings.end();

            if (!found) {
                _bindings.emplace_back(KeyCode::None, true, type, false, false, false, false);
            }
        }
    }

    return true;
}

bool KeyBindingMap::save() const noexcept {
    if (_filePath.empty()) return false;
    return saveToFile(_filePath);
}

bool KeyBindingMap::saveToFile(const std::string& path) const noexcept {
    std::ofstream file(path);
    if (!file.is_open()) return false;

    file << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    file << "<keybindings>\n";

    for (const auto& binding : _bindings) {
        file << "  <keybinding";

        if (binding.isDisabled()) {
            file << " keycode=\"\"";
        } else {
            file << " keycode=\"" << escapeXml(KeyBinding::encodeKey(
                binding.getKey(), binding.requiresShift())) << "\"";
        }

        file << " alt=\"" << (binding.requiresAlt() ? "TRUE" : "FALSE") << "\"";
        file << " control=\"" << (binding.requiresControl() ? "TRUE" : "FALSE") << "\"";

        if (binding.requiresRawControl()) {
            file << " rawControl=\"TRUE\"";
        }

        file << " shift=\"" << (binding.requiresShift() ? "TRUE" : "FALSE") << "\"";
        file << " type=\"" << escapeXml(binding.getType()) << "\"";

        if (binding.getType() == "EFFECT") {
            file << " effect=\"" << escapeXml(binding.getEffectName()) << "\"";
            file << " xLightsVersion=\"" << escapeXml(binding.getEffectDataVersion()) << "\"";
            if (!binding.getEffectString().empty()) {
                file << ">" << escapeXml(binding.getEffectString()) << "</keybinding>\n";
            } else {
                file << "/>\n";
            }
        } else if (binding.getType() == "PRESET") {
            file << " effect=\"" << escapeXml(binding.getEffectName()) << "\"/>\n";
        } else if (binding.getType() == "APPLYSETTING") {
            file << " xLightsVersion=\"" << escapeXml(binding.getEffectDataVersion()) << "\"";
            file << ">" << escapeXml(binding.getEffectString()) << "</keybinding>\n";
        } else {
            file << "/>\n";
        }
    }

    file << "</keybindings>\n";
    file.close();

    return true;
}

int KeyBindingMap::addBinding(const KeyBinding& binding) {
    _bindings.push_back(binding);
    return binding.getId();
}

void KeyBindingMap::deleteBinding(int id) {
    auto it = std::find_if(_bindings.begin(), _bindings.end(),
        [id](const KeyBinding& b) { return b.getId() == id; });

    if (it != _bindings.end()) {
        _bindings.erase(it);
    }
}

std::shared_ptr<const KeyBinding> KeyBindingMap::find(KeyCode key, bool ctrl, bool alt,
                                                       bool shift, bool rawCtrl,
                                                       KeyScope scope) const noexcept {
    for (const auto& b : _bindings) {
        if (!b.isDisabled() &&
            b.requiresAlt() == alt &&
            KeyBinding::isControlEqual(b, ctrl, rawCtrl) &&
            ((b.requiresShift() == shift && b.isKey(key)) || b.isEquivalentKey(key)) &&
            (b.inScope(scope) || b.getScope() == KeyScope::All)) {
            return std::make_shared<const KeyBinding>(b);
        }
    }
    return nullptr;
}

KeyBinding* KeyBindingMap::getBinding(int id) {
    for (auto& b : _bindings) {
        if (b.getId() == id) return &b;
    }
    return nullptr;
}

const KeyBinding* KeyBindingMap::getBinding(int id) const {
    for (const auto& b : _bindings) {
        if (b.getId() == id) return &b;
    }
    return nullptr;
}

bool KeyBindingMap::isDuplicateKey(const KeyBinding& binding) const {
    for (const auto& b : _bindings) {
        if (b.isDuplicateKey(binding)) {
            return true;
        }
    }
    return false;
}

std::string KeyBindingMap::dump() const noexcept {
    std::string result;

    result += "Scope: Everywhere\n";
    for (const auto& b : _bindings) {
        if (b.inScope(KeyScope::All) && !b.isDisabled()) {
            result += "    " + b.description() + "\n";
        }
    }

    result += "\nScope: Layout\n";
    for (const auto& b : _bindings) {
        if (b.getScope() == KeyScope::Layout && !b.isDisabled()) {
            result += "    " + b.description() + "\n";
        }
    }

    result += "\nScope: Sequencer\n";
    for (const auto& b : _bindings) {
        if (b.getScope() == KeyScope::Sequence && !b.isDisabled()) {
            result += "    " + b.description() + "\n";
        }
    }

    return result;
}

#pragma endregion

} // namespace xlCore
