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

// SequenceEngine: Pure C++ API for sequence operations.
// No wxWidgets types cross this boundary. This allows both the existing
// wxWidgets UI and a future AppKit UI to drive the same engine.
//
// This engine uses the ISequenceProvider interface to access sequence state,
// enabling decoupling from the xLightsFrame. For legacy support, use the
// SequenceStateAdapter to wrap an xLightsFrame instance.

#include <string>
#include <functional>
#include <vector>
#include <mutex>
#include <atomic>
#include <memory>

#include "interfaces/ISequenceProvider.h"

class SequenceData;

namespace xlEngine {

// PlaybackState is now defined in interfaces/ISequenceProvider.h
// (included above) to avoid duplication.

struct SequenceInfo {
    std::string name;
    std::string mediaFile;
    std::string sequenceType; // "Media" or "Animation"
    int durationMS = 0;
    int frameTimeMS = 0;
    int numChannels = 0;
    int numFrames = 0;
    std::string author;
    std::string song;
    std::string artist;
    std::string album;
    std::string comment;
};

// Read-only view into raw channel data for a single frame.
// Does not own the data; valid only while the sequence is loaded.
class FrameDataView {
public:
    FrameDataView() : _data(nullptr), _numChannels(0) {}
    FrameDataView(const unsigned char* data, unsigned int numChannels)
        : _data(data), _numChannels(numChannels) {}

    const unsigned char* data() const { return _data; }
    unsigned int numChannels() const { return _numChannels; }
    bool isValid() const { return _data != nullptr; }

    unsigned char operator[](unsigned int channel) const {
        if (channel < _numChannels && _data) return _data[channel];
        return 0;
    }

private:
    const unsigned char* _data;
    unsigned int _numChannels;
};

// Callback interface for sequence engine events.
// All callbacks are invoked on the thread that triggers them (which may
// be the render thread or the UI thread). Implementers must handle
// thread safety in their callback bodies.
class SequenceEngineListener {
public:
    virtual ~SequenceEngineListener() = default;

    virtual void onSequenceLoaded(const SequenceInfo& info) {}
    virtual void onSequenceClosed() {}
    virtual void onSequenceSaved(const std::string& path) {}
    virtual void onPlaybackStateChanged(PlaybackState newState) {}
    virtual void onPlaybackPositionChanged(int positionMS) {}
    virtual void onSequenceModified() {}
    virtual void onError(const std::string& message) {}
};

// SequenceEngine provides a pure C++ API for sequence operations.
//
// Thread safety: All public methods are safe to call from any thread.
// The engine uses internal locking where necessary. Callbacks may be
// invoked from any thread; callers must dispatch to their own UI
// thread if needed.
//
// The engine uses the ISequenceProvider interface to access sequence state,
// allowing it to work with different provider implementations:
// - SequenceStateAdapter: Wraps xLightsFrame for legacy wxWidgets UI
// - NativeSequenceProvider: For future native macOS implementation
class SequenceEngine {
public:
    explicit SequenceEngine(ISequenceProvider* provider);
    ~SequenceEngine();

    SequenceEngine(const SequenceEngine&) = delete;
    SequenceEngine& operator=(const SequenceEngine&) = delete;

    // --- Listener management ---
    void addListener(SequenceEngineListener* listener);
    void removeListener(SequenceEngineListener* listener);

    // --- Sequence file operations ---

    // Load a sequence from the given path. Supports .xsq, .xml, and .fseq files.
    // Returns true if the sequence was loaded successfully.
    bool loadSequence(const std::string& path);

    // Save the current sequence. If path is empty, saves to the current file.
    // Returns true on success.
    bool saveSequence(const std::string& path = "");

    // Close the current sequence.
    // Returns true if closed (false if the user cancelled e.g. due to unsaved changes).
    bool closeSequence();

    // Returns true if a sequence is currently loaded.
    bool isSequenceLoaded() const;

    // Get metadata about the currently loaded sequence.
    SequenceInfo getSequenceInfo() const;

    // --- Playback control ---

    void play();
    void pause();
    void stop();
    void seek(int positionMS);

    // Seek to the beginning of the sequence.
    void seekToStart();

    // Seek to the end of the sequence.
    void seekToEnd();

    // Seek forward or backward by the given number of milliseconds.
    void seekRelative(int deltaMS);

    // --- Playback state queries ---

    PlaybackState getPlaybackState() const;
    int getPosition() const;
    int getDuration() const;
    int getFrameRate() const;
    int getFrameTimeMS() const;

    // --- Sequence data access ---

    // Get the total number of channels in the sequence.
    unsigned int getNumChannels() const;

    // Get the total number of frames in the sequence.
    unsigned int getNumFrames() const;

    // Get a read-only view of the channel data for a given frame.
    // Returns an invalid FrameDataView if the frame is out of range
    // or no sequence is loaded.
    FrameDataView getFrameData(unsigned int frame) const;

    // Get access to the underlying SequenceData object.
    // This is provided for the transition period while the existing
    // code still needs direct access. New code should prefer
    // getFrameData() instead.
    const SequenceData* getSequenceData() const;

private:
    void notifyPlaybackStateChanged(PlaybackState state);
    void notifyPositionChanged(int positionMS);
    void notifySequenceLoaded(const SequenceInfo& info);
    void notifySequenceClosed();
    void notifySequenceSaved(const std::string& path);
    void notifyError(const std::string& message);

    ISequenceProvider* _provider; // sequence state provider (interface)
    std::vector<SequenceEngineListener*> _listeners;
    mutable std::mutex _listenerMutex;
    std::atomic<PlaybackState> _cachedState{PlaybackState::Stopped};
};

} // namespace xlEngine
