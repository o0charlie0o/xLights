/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "SequenceStateAdapter.h"

#include "../../xLightsMain.h"
#include "../../xLightsXmlFile.h"
#include "../../SequenceData.h"

#include <algorithm>

namespace xlEngine {

SequenceStateAdapter::SequenceStateAdapter(xLightsFrame* frame)
    : _frame(frame)
{
}

SequenceStateAdapter::~SequenceStateAdapter()
{
}

// --- Sequence Metadata ---

std::string SequenceStateAdapter::getSequencePath() const
{
    if (!_frame) return "";
    xLightsXmlFile* xmlFile = xLightsFrame::CurrentSeqXmlFile;
    if (!xmlFile) return "";
    return xmlFile->GetFullPath().ToStdString();
}

std::string SequenceStateAdapter::getSequenceName() const
{
    if (!_frame) return "";
    xLightsXmlFile* xmlFile = xLightsFrame::CurrentSeqXmlFile;
    if (!xmlFile) return "";
    return xmlFile->GetName().ToStdString();
}

double SequenceStateAdapter::getSequenceDuration() const
{
    if (!isSequenceLoaded()) return 0.0;
    xLightsXmlFile* xmlFile = xLightsFrame::CurrentSeqXmlFile;
    if (!xmlFile) return 0.0;
    return xmlFile->GetSequenceDurationMS() / 1000.0;
}

int SequenceStateAdapter::getFrameMS() const
{
    if (!isSequenceLoaded()) return 0;
    xLightsXmlFile* xmlFile = xLightsFrame::CurrentSeqXmlFile;
    if (!xmlFile) return 0;
    return xmlFile->GetFrameMS();
}

bool SequenceStateAdapter::isSequenceLoaded() const
{
    if (!_frame) return false;
    return (xLightsFrame::CurrentSeqXmlFile != nullptr &&
            _frame->IsSequenceDataValid());
}

std::string SequenceStateAdapter::getMediaPath() const
{
    if (!isSequenceLoaded()) return "";
    xLightsXmlFile* xmlFile = xLightsFrame::CurrentSeqXmlFile;
    if (!xmlFile) return "";
    return xmlFile->GetMediaFile().ToStdString();
}

unsigned int SequenceStateAdapter::getNumChannels() const
{
    if (!_frame) return 0;
    if (!isSequenceLoaded()) return 0;
    return _frame->_seqData.NumChannels();
}

unsigned int SequenceStateAdapter::getNumFrames() const
{
    if (!_frame) return 0;
    if (!isSequenceLoaded()) return 0;
    return _frame->_seqData.NumFrames();
}

// --- File Operations ---

bool SequenceStateAdapter::loadSequence(const std::string& path)
{
    if (!_frame) return false;
    if (path.empty()) return false;
    _frame->OpenSequence(wxString(path), nullptr);
    return isSequenceLoaded();
}

bool SequenceStateAdapter::saveSequence(const std::string& path)
{
    if (!_frame) return false;
    if (!isSequenceLoaded()) return false;
    if (!path.empty()) {
        _frame->SaveAsSequence(path);
    } else {
        _frame->SaveSequence();
    }
    return true;
}

bool SequenceStateAdapter::closeSequence()
{
    if (!_frame) return false;
    return _frame->CloseSequence();
}

// --- Playback State ---

PlaybackState SequenceStateAdapter::getPlaybackState() const
{
    if (!_frame) return PlaybackState::Stopped;

    int playStatus = _frame->GetPlayStatus();
    switch (playStatus) {
        case PLAY_TYPE_STOPPED:
            return PlaybackState::Stopped;
        case PLAY_TYPE_EFFECT:
        case PLAY_TYPE_MODEL:
            return PlaybackState::Playing;
        case PLAY_TYPE_EFFECT_PAUSED:
        case PLAY_TYPE_MODEL_PAUSED:
            return PlaybackState::Paused;
        default:
            return PlaybackState::Stopped;
    }
}

double SequenceStateAdapter::getCurrentPosition() const
{
    if (!_frame) return 0.0;
    if (!isSequenceLoaded()) return 0.0;
    return _frame->GetCurrentPlayTime() / 1000.0;
}

void SequenceStateAdapter::setPlaybackState(PlaybackState state)
{
    if (!_frame) return;
    if (!isSequenceLoaded()) return;

    PlaybackState current = getPlaybackState();

    switch (state) {
        case PlaybackState::Playing:
            if (current != PlaybackState::Playing) {
                wxCommandEvent evt(EVT_PLAY_SEQUENCE);
                wxPostEvent(_frame, evt);
                notifyPlaybackStateChanged(PlaybackState::Playing);
            }
            break;

        case PlaybackState::Paused:
            if (current == PlaybackState::Playing) {
                wxCommandEvent evt(EVT_PAUSE_SEQUENCE);
                wxPostEvent(_frame, evt);
                notifyPlaybackStateChanged(PlaybackState::Paused);
            } else if (current == PlaybackState::Paused) {
                // Toggle: resume playback
                wxCommandEvent evt(EVT_PAUSE_SEQUENCE);
                wxPostEvent(_frame, evt);
                notifyPlaybackStateChanged(PlaybackState::Playing);
            }
            break;

        case PlaybackState::Stopped:
            if (current != PlaybackState::Stopped) {
                wxCommandEvent evt(EVT_STOP_SEQUENCE);
                wxPostEvent(_frame, evt);
                notifyPlaybackStateChanged(PlaybackState::Stopped);
            }
            break;
    }
}

void SequenceStateAdapter::seek(double positionSeconds)
{
    if (!_frame) return;
    if (!isSequenceLoaded()) return;

    int positionMS = static_cast<int>(positionSeconds * 1000.0);
    if (positionMS < 0) positionMS = 0;

    double duration = getSequenceDuration();
    int durationMS = static_cast<int>(duration * 1000.0);
    if (positionMS > durationMS) positionMS = durationMS;

    wxCommandEvent evt(EVT_SEQUENCE_SEEKTO);
    evt.SetInt(positionMS);
    wxPostEvent(_frame, evt);

    notifyPositionChanged(positionMS / 1000.0);
}

// --- Listener Management ---

void SequenceStateAdapter::addListener(ISequenceProviderListener* listener)
{
    if (!listener) return;
    std::lock_guard<std::mutex> lock(_listenerMutex);
    if (std::find(_listeners.begin(), _listeners.end(), listener) == _listeners.end()) {
        _listeners.push_back(listener);
    }
}

void SequenceStateAdapter::removeListener(ISequenceProviderListener* listener)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.erase(
        std::remove(_listeners.begin(), _listeners.end(), listener),
        _listeners.end());
}

// --- Notification Helpers ---

void SequenceStateAdapter::notifyPlaybackStateChanged(PlaybackState state)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onPlaybackStateChanged(state);
    }
}

void SequenceStateAdapter::notifyPositionChanged(double positionSeconds)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onPlaybackPositionChanged(positionSeconds);
    }
}

void SequenceStateAdapter::notifySequenceLoaded()
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onSequenceLoaded();
    }
}

void SequenceStateAdapter::notifySequenceClosed()
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onSequenceClosed();
    }
}

void SequenceStateAdapter::notifySequenceModified()
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onSequenceModified();
    }
}

} // namespace xlEngine
