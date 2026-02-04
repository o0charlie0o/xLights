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

// SequenceStateAdapter: Legacy adapter that wraps xLightsFrame to provide
// the ISequenceProvider interface. This allows SequenceEngine to work with
// the existing wxWidgets-based infrastructure while being decoupled from
// direct xLightsFrame dependencies.
//
// This class is part of the transition strategy. Once the native macOS UI
// has its own NativeSequenceProvider implementation, this adapter will only
// be used by the legacy wxWidgets UI.

#include "../interfaces/ISequenceProvider.h"
#include <mutex>
#include <vector>

class xLightsFrame;

namespace xlEngine {

class SequenceStateAdapter : public ISequenceProvider {
public:
    explicit SequenceStateAdapter(xLightsFrame* frame);
    ~SequenceStateAdapter() override;

    SequenceStateAdapter(const SequenceStateAdapter&) = delete;
    SequenceStateAdapter& operator=(const SequenceStateAdapter&) = delete;

    // --- ISequenceProvider: Sequence Metadata ---
    std::string getSequencePath() const override;
    std::string getSequenceName() const override;
    double getSequenceDuration() const override;
    int getFrameMS() const override;
    bool isSequenceLoaded() const override;
    std::string getMediaPath() const override;
    unsigned int getNumChannels() const override;
    unsigned int getNumFrames() const override;

    // --- ISequenceProvider: File Operations ---
    bool loadSequence(const std::string& path) override;
    bool saveSequence(const std::string& path = "") override;
    bool closeSequence() override;

    // --- ISequenceProvider: Playback State ---
    PlaybackState getPlaybackState() const override;
    double getCurrentPosition() const override;
    void setPlaybackState(PlaybackState state) override;
    void seek(double positionSeconds) override;

    // --- ISequenceProvider: Listener Management ---
    void addListener(ISequenceProviderListener* listener) override;
    void removeListener(ISequenceProviderListener* listener) override;

    // --- Legacy Accessors (for transition period) ---

    // Get the underlying xLightsFrame pointer.
    // This should only be used during the transition period for functionality
    // not yet abstracted into the interface.
    xLightsFrame* getFrame() const { return _frame; }

protected:
    // Notify all listeners of state changes
    void notifyPlaybackStateChanged(PlaybackState state);
    void notifyPositionChanged(double positionSeconds);
    void notifySequenceLoaded();
    void notifySequenceClosed();
    void notifySequenceModified();

private:
    xLightsFrame* _frame;
    std::vector<ISequenceProviderListener*> _listeners;
    mutable std::mutex _listenerMutex;
};

} // namespace xlEngine
