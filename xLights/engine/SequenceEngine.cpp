/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "SequenceEngine.h"

#include "../xLightsMain.h"
#include "../xLightsXmlFile.h"
#include "../SequenceData.h"
#include "../sequencer/SequenceElements.h"

#include <algorithm>

namespace xlEngine {

SequenceEngine::SequenceEngine(xLightsFrame* frame)
    : _frame(frame)
{
}

SequenceEngine::~SequenceEngine()
{
}

// --- Listener management ---

void SequenceEngine::addListener(SequenceEngineListener* listener)
{
    if (!listener) return;
    std::lock_guard<std::mutex> lock(_listenerMutex);
    if (std::find(_listeners.begin(), _listeners.end(), listener) == _listeners.end()) {
        _listeners.push_back(listener);
    }
}

void SequenceEngine::removeListener(SequenceEngineListener* listener)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.erase(
        std::remove(_listeners.begin(), _listeners.end(), listener),
        _listeners.end());
}

// --- Notification helpers ---

void SequenceEngine::notifyPlaybackStateChanged(PlaybackState state)
{
    _cachedState.store(state);
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onPlaybackStateChanged(state);
    }
}

void SequenceEngine::notifyPositionChanged(int positionMS)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onPlaybackPositionChanged(positionMS);
    }
}

void SequenceEngine::notifySequenceLoaded(const SequenceInfo& info)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onSequenceLoaded(info);
    }
}

void SequenceEngine::notifySequenceClosed()
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onSequenceClosed();
    }
}

void SequenceEngine::notifySequenceSaved(const std::string& path)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onSequenceSaved(path);
    }
}

void SequenceEngine::notifyError(const std::string& message)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        listener->onError(message);
    }
}

// --- Sequence file operations ---

bool SequenceEngine::loadSequence(const std::string& path)
{
    if (!_frame) return false;
    if (path.empty()) return false;

    // Delegate to the existing xLightsFrame implementation.
    // The two-argument overload avoids the file-open dialog.
    _frame->OpenSequence(wxString(path), nullptr);

    // Check if a sequence was actually loaded.
    if (!isSequenceLoaded()) {
        notifyError("Failed to load sequence: " + path);
        return false;
    }

    SequenceInfo info = getSequenceInfo();
    notifySequenceLoaded(info);
    notifyPlaybackStateChanged(PlaybackState::Stopped);
    return true;
}

bool SequenceEngine::saveSequence(const std::string& path)
{
    if (!_frame) return false;
    if (!isSequenceLoaded()) {
        notifyError("No sequence is loaded to save.");
        return false;
    }

    if (!path.empty()) {
        _frame->SaveAsSequence(path);
    } else {
        _frame->SaveSequence();
    }

    notifySequenceSaved(path.empty() ? getSequenceInfo().name : path);
    return true;
}

bool SequenceEngine::closeSequence()
{
    if (!_frame) return false;

    bool closed = _frame->CloseSequence();
    if (closed) {
        notifyPlaybackStateChanged(PlaybackState::Stopped);
        notifySequenceClosed();
    }
    return closed;
}

bool SequenceEngine::isSequenceLoaded() const
{
    if (!_frame) return false;
    return (xLightsFrame::CurrentSeqXmlFile != nullptr &&
            _frame->IsSequenceDataValid());
}

SequenceInfo SequenceEngine::getSequenceInfo() const
{
    SequenceInfo info;
    if (!isSequenceLoaded()) return info;

    xLightsXmlFile* xmlFile = xLightsFrame::CurrentSeqXmlFile;
    if (!xmlFile) return info;

    info.name = xmlFile->GetName().ToStdString();
    info.mediaFile = xmlFile->GetMediaFile().ToStdString();
    info.sequenceType = xmlFile->GetSequenceType().ToStdString();
    info.durationMS = xmlFile->GetSequenceDurationMS();
    info.frameTimeMS = xmlFile->GetFrameMS();
    info.numChannels = _frame->_seqData.NumChannels();
    info.numFrames = _frame->_seqData.NumFrames();

    info.author = xmlFile->GetHeaderInfo(HEADER_INFO_TYPES::AUTHOR).ToStdString();
    info.song = xmlFile->GetHeaderInfo(HEADER_INFO_TYPES::SONG).ToStdString();
    info.artist = xmlFile->GetHeaderInfo(HEADER_INFO_TYPES::ARTIST).ToStdString();
    info.album = xmlFile->GetHeaderInfo(HEADER_INFO_TYPES::ALBUM).ToStdString();
    info.comment = xmlFile->GetHeaderInfo(HEADER_INFO_TYPES::COMMENT).ToStdString();

    return info;
}

// --- Playback control ---

void SequenceEngine::play()
{
    if (!_frame) return;
    if (!isSequenceLoaded()) return;

    wxCommandEvent evt(EVT_PLAY_SEQUENCE);
    wxPostEvent(_frame, evt);
    notifyPlaybackStateChanged(PlaybackState::Playing);
}

void SequenceEngine::pause()
{
    if (!_frame) return;
    if (!isSequenceLoaded()) return;

    PlaybackState current = getPlaybackState();
    if (current == PlaybackState::Playing) {
        wxCommandEvent evt(EVT_PAUSE_SEQUENCE);
        wxPostEvent(_frame, evt);
        notifyPlaybackStateChanged(PlaybackState::Paused);
    } else if (current == PlaybackState::Paused) {
        wxCommandEvent evt(EVT_PAUSE_SEQUENCE);
        wxPostEvent(_frame, evt);
        notifyPlaybackStateChanged(PlaybackState::Playing);
    }
}

void SequenceEngine::stop()
{
    if (!_frame) return;
    if (!isSequenceLoaded()) return;

    wxCommandEvent evt(EVT_STOP_SEQUENCE);
    wxPostEvent(_frame, evt);
    notifyPlaybackStateChanged(PlaybackState::Stopped);
}

void SequenceEngine::seek(int positionMS)
{
    if (!_frame) return;
    if (!isSequenceLoaded()) return;

    if (positionMS < 0) positionMS = 0;
    int duration = getDuration();
    if (positionMS > duration) positionMS = duration;

    wxCommandEvent evt(EVT_SEQUENCE_SEEKTO);
    evt.SetInt(positionMS);
    wxPostEvent(_frame, evt);

    notifyPositionChanged(positionMS);
}

void SequenceEngine::seekToStart()
{
    seek(0);
}

void SequenceEngine::seekToEnd()
{
    seek(getDuration());
}

void SequenceEngine::seekRelative(int deltaMS)
{
    int current = getPosition();
    seek(current + deltaMS);
}

// --- Playback state queries ---

PlaybackState SequenceEngine::getPlaybackState() const
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

int SequenceEngine::getPosition() const
{
    if (!_frame) return 0;
    if (!isSequenceLoaded()) return 0;
    return _frame->GetCurrentPlayTime();
}

int SequenceEngine::getDuration() const
{
    if (!isSequenceLoaded()) return 0;
    xLightsXmlFile* xmlFile = xLightsFrame::CurrentSeqXmlFile;
    if (!xmlFile) return 0;
    return xmlFile->GetSequenceDurationMS();
}

int SequenceEngine::getFrameRate() const
{
    int ft = getFrameTimeMS();
    if (ft <= 0) return 0;
    return 1000 / ft;
}

int SequenceEngine::getFrameTimeMS() const
{
    if (!isSequenceLoaded()) return 0;
    return _frame->_seqData.FrameTime();
}

// --- Sequence data access ---

unsigned int SequenceEngine::getNumChannels() const
{
    if (!_frame) return 0;
    return _frame->_seqData.NumChannels();
}

unsigned int SequenceEngine::getNumFrames() const
{
    if (!_frame) return 0;
    return _frame->_seqData.NumFrames();
}

FrameDataView SequenceEngine::getFrameData(unsigned int frame) const
{
    if (!_frame) return FrameDataView();
    if (frame >= _frame->_seqData.NumFrames()) return FrameDataView();

    // SequenceData::FrameData provides access to the raw channel buffer.
    // We access it through the const operator[] which returns a const FrameData&.
    const SequenceData::FrameData& fd = _frame->_seqData[frame];
    // The FrameData class provides operator[] returning const unsigned char*
    // when called with channel 0 on a const object.
    const unsigned char* data = fd[0];
    return FrameDataView(data, _frame->_seqData.NumChannels());
}

const SequenceData* SequenceEngine::getSequenceData() const
{
    if (!_frame) return nullptr;
    return &_frame->_seqData;
}

} // namespace xlEngine
