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

#ifndef XLIGHTS_NATIVE
#include "adapters/SequenceStateAdapter.h"
#include "../xLightsMain.h"
#include "../xLightsXmlFile.h"
#include "../SequenceData.h"
#include "../sequencer/SequenceElements.h"
#endif

#include <algorithm>

namespace xlEngine {

SequenceEngine::SequenceEngine(ISequenceProvider* provider)
    : _provider(provider)
{
}

SequenceEngine::~SequenceEngine()
{
}

#ifndef XLIGHTS_NATIVE
// --- Helper to get xLightsFrame during transition ---
// Returns the underlying xLightsFrame if available through SequenceStateAdapter.
// This is a temporary bridge during the transition period.
static xLightsFrame* getFrameFromProvider(ISequenceProvider* provider)
{
    if (!provider) return nullptr;

    // Try to cast to SequenceStateAdapter (legacy wrapper)
    auto* adapter = dynamic_cast<SequenceStateAdapter*>(provider);
    if (adapter) {
        return adapter->getFrame();
    }

    return nullptr;
}
#endif

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
// Note: These methods require xLightsFrame access during transition.
// In the future, file I/O may be handled by a separate component.

bool SequenceEngine::loadSequence(const std::string& path)
{
#ifdef XLIGHTS_NATIVE
    // For native build, use provider directly
    if (!_provider) return false;
    if (path.empty()) return false;

    bool loaded = _provider->loadSequence(path);
    if (!loaded) {
        notifyError("Failed to load sequence: " + path);
        return false;
    }

    SequenceInfo info = getSequenceInfo();
    notifySequenceLoaded(info);
    notifyPlaybackStateChanged(PlaybackState::Stopped);
    return true;
#else
    xLightsFrame* frame = getFrameFromProvider(_provider);
    if (!frame) return false;
    if (path.empty()) return false;

    // Delegate to the existing xLightsFrame implementation.
    // The two-argument overload avoids the file-open dialog.
    frame->OpenSequence(wxString(path), nullptr);

    // Check if a sequence was actually loaded.
    if (!isSequenceLoaded()) {
        notifyError("Failed to load sequence: " + path);
        return false;
    }

    SequenceInfo info = getSequenceInfo();
    notifySequenceLoaded(info);
    notifyPlaybackStateChanged(PlaybackState::Stopped);
    return true;
#endif
}

bool SequenceEngine::saveSequence(const std::string& path)
{
#ifdef XLIGHTS_NATIVE
    // For native build, use provider directly
    if (!_provider) return false;
    if (!isSequenceLoaded()) {
        notifyError("No sequence is loaded to save.");
        return false;
    }

    bool saved = _provider->saveSequence(path);
    if (saved) {
        notifySequenceSaved(path.empty() ? getSequenceInfo().name : path);
    }
    return saved;
#else
    xLightsFrame* frame = getFrameFromProvider(_provider);
    if (!frame) return false;
    if (!isSequenceLoaded()) {
        notifyError("No sequence is loaded to save.");
        return false;
    }

    if (!path.empty()) {
        frame->SaveAsSequence(path);
    } else {
        frame->SaveSequence();
    }

    notifySequenceSaved(path.empty() ? getSequenceInfo().name : path);
    return true;
#endif
}

bool SequenceEngine::closeSequence()
{
#ifdef XLIGHTS_NATIVE
    // For native build, use provider directly
    if (!_provider) return false;

    bool closed = _provider->closeSequence();
    if (closed) {
        notifyPlaybackStateChanged(PlaybackState::Stopped);
        notifySequenceClosed();
    }
    return closed;
#else
    xLightsFrame* frame = getFrameFromProvider(_provider);
    if (!frame) return false;

    bool closed = frame->CloseSequence();
    if (closed) {
        notifyPlaybackStateChanged(PlaybackState::Stopped);
        notifySequenceClosed();
    }
    return closed;
#endif
}

bool SequenceEngine::isSequenceLoaded() const
{
    if (!_provider) return false;
    return _provider->isSequenceLoaded();
}

SequenceInfo SequenceEngine::getSequenceInfo() const
{
    SequenceInfo info;
    if (!isSequenceLoaded()) return info;

    // Use interface methods for basic metadata
    info.name = _provider->getSequenceName();
    info.mediaFile = _provider->getMediaPath();
    info.durationMS = static_cast<int>(_provider->getSequenceDuration() * 1000.0);
    info.frameTimeMS = _provider->getFrameMS();

#ifdef XLIGHTS_NATIVE
    // For native build, extended metadata comes from provider
    info.numChannels = _provider->getNumChannels();
    info.numFrames = _provider->getNumFrames();
#else
    // Extended metadata requires xLightsFrame access during transition
    xLightsFrame* frame = getFrameFromProvider(_provider);
    if (frame) {
        xLightsXmlFile* xmlFile = xLightsFrame::CurrentSeqXmlFile;
        if (xmlFile) {
            info.sequenceType = xmlFile->GetSequenceType().ToStdString();
            info.author = xmlFile->GetHeaderInfo(HEADER_INFO_TYPES::AUTHOR).ToStdString();
            info.song = xmlFile->GetHeaderInfo(HEADER_INFO_TYPES::SONG).ToStdString();
            info.artist = xmlFile->GetHeaderInfo(HEADER_INFO_TYPES::ARTIST).ToStdString();
            info.album = xmlFile->GetHeaderInfo(HEADER_INFO_TYPES::ALBUM).ToStdString();
            info.comment = xmlFile->GetHeaderInfo(HEADER_INFO_TYPES::COMMENT).ToStdString();
        }
        info.numChannels = frame->_seqData.NumChannels();
        info.numFrames = frame->_seqData.NumFrames();
    }
#endif

    return info;
}

// --- Playback control ---
// These methods use the ISequenceProvider interface for playback state.

void SequenceEngine::play()
{
    if (!_provider) return;
    if (!isSequenceLoaded()) return;

    _provider->setPlaybackState(PlaybackState::Playing);
    notifyPlaybackStateChanged(PlaybackState::Playing);
}

void SequenceEngine::pause()
{
    if (!_provider) return;
    if (!isSequenceLoaded()) return;

    PlaybackState current = getPlaybackState();
    if (current == PlaybackState::Playing) {
        _provider->setPlaybackState(PlaybackState::Paused);
        notifyPlaybackStateChanged(PlaybackState::Paused);
    } else if (current == PlaybackState::Paused) {
        _provider->setPlaybackState(PlaybackState::Playing);
        notifyPlaybackStateChanged(PlaybackState::Playing);
    }
}

void SequenceEngine::stop()
{
    if (!_provider) return;
    if (!isSequenceLoaded()) return;

    _provider->setPlaybackState(PlaybackState::Stopped);
    notifyPlaybackStateChanged(PlaybackState::Stopped);
}

void SequenceEngine::seek(int positionMS)
{
    if (!_provider) return;
    if (!isSequenceLoaded()) return;

    if (positionMS < 0) positionMS = 0;
    int duration = getDuration();
    if (positionMS > duration) positionMS = duration;

    _provider->seek(positionMS / 1000.0);
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
// These methods use the ISequenceProvider interface.

PlaybackState SequenceEngine::getPlaybackState() const
{
    if (!_provider) return PlaybackState::Stopped;
    return _provider->getPlaybackState();
}

int SequenceEngine::getPosition() const
{
    if (!_provider) return 0;
    if (!isSequenceLoaded()) return 0;
    return static_cast<int>(_provider->getCurrentPosition() * 1000.0);
}

int SequenceEngine::getDuration() const
{
    if (!_provider) return 0;
    if (!isSequenceLoaded()) return 0;
    return static_cast<int>(_provider->getSequenceDuration() * 1000.0);
}

int SequenceEngine::getFrameRate() const
{
    int ft = getFrameTimeMS();
    if (ft <= 0) return 0;
    return 1000 / ft;
}

int SequenceEngine::getFrameTimeMS() const
{
    if (!_provider) return 0;
    if (!isSequenceLoaded()) return 0;
    return _provider->getFrameMS();
}

// --- Sequence data access ---
// These methods require xLightsFrame access during transition.
// In the future, this may be handled by a separate data provider interface.

unsigned int SequenceEngine::getNumChannels() const
{
#ifdef XLIGHTS_NATIVE
    if (!_provider) return 0;
    return _provider->getNumChannels();
#else
    xLightsFrame* frame = getFrameFromProvider(_provider);
    if (!frame) return 0;
    return frame->_seqData.NumChannels();
#endif
}

unsigned int SequenceEngine::getNumFrames() const
{
#ifdef XLIGHTS_NATIVE
    if (!_provider) return 0;
    return _provider->getNumFrames();
#else
    xLightsFrame* frame = getFrameFromProvider(_provider);
    if (!frame) return 0;
    return frame->_seqData.NumFrames();
#endif
}

FrameDataView SequenceEngine::getFrameData(unsigned int frameIndex) const
{
#ifdef XLIGHTS_NATIVE
    // For native build, frame data access is not yet implemented
    // TODO: Add frame data access to native provider
    return FrameDataView();
#else
    xLightsFrame* frame = getFrameFromProvider(_provider);
    if (!frame) return FrameDataView();
    if (frameIndex >= frame->_seqData.NumFrames()) return FrameDataView();

    // SequenceData::FrameData provides access to the raw channel buffer.
    // We access it through the const operator[] which returns a const FrameData&.
    const SequenceData::FrameData& fd = frame->_seqData[frameIndex];
    // The FrameData class provides operator[] returning const unsigned char*
    // when called with channel 0 on a const object.
    const unsigned char* data = fd[0];
    return FrameDataView(data, frame->_seqData.NumChannels());
#endif
}

const SequenceData* SequenceEngine::getSequenceData() const
{
#ifdef XLIGHTS_NATIVE
    // For native build, SequenceData is not directly available
    return nullptr;
#else
    xLightsFrame* frame = getFrameFromProvider(_provider);
    if (!frame) return nullptr;
    return &frame->_seqData;
#endif
}

} // namespace xlEngine
