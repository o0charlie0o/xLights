/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 **************************************************************/

// LegacyEventDefs.cpp
// Event symbol definitions for the hybrid native+legacy build.
// These events are normally defined in xLightsMain.cpp which cannot
// be included in the native target (too many wx UI dependencies).
// This file provides just the event definitions needed by the
// legacy rendering pipeline files.

#include <wx/event.h>
#include "../../RenderCommandEvent.h"

// wxDEFINE_EVENT produces const with internal linkage by default.
// Redefine to use extern for external linkage so other TUs can see these.
#undef wxDEFINE_EVENT
#define wxDEFINE_EVENT(name, type) \
    extern const wxEventTypeTag<type> name(wxNewEventType())

// Events declared in xLightsMain.h
wxDEFINE_EVENT(EVT_ROW_HEADINGS_CHANGED, wxCommandEvent);
wxDEFINE_EVENT(EVT_PLAY_MODEL_EFFECT, wxCommandEvent);
wxDEFINE_EVENT(EVT_FORCE_SEQUENCER_REFRESH, wxCommandEvent);

// Events declared in RenderCommandEvent.h
wxDEFINE_EVENT(EVT_RENDER_RANGE, RenderCommandEvent);
wxDEFINE_EVENT(EVT_SELECTED_EFFECT_CHANGED, SelectedEffectChangedEvent);
