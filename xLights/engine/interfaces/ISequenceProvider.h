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

// ISequenceProvider: Abstract interface for sequence state access.
//
// This interface allows engines to access sequence information without
// direct dependency on xLightsFrame or wxWidgets types. All types used
// are standard C++ types only.
//
// Thread Safety: Implementations must ensure all methods are thread-safe
// for read access. Playback state methods may be called from any thread.

#include <string>
#include <functional>
#include <cstdint>

namespace xlEngine {

/// Playback state enumeration.
/// Note: This is also defined in SequenceEngine.h for backward compatibility.
/// Consider consolidating in a future refactor.
enum class PlaybackState {
    Stopped,
    Playing,
    Paused
};

/// Listener interface for sequence state change notifications.
/// All callbacks may be invoked from any thread. Implementers must handle
/// thread safety and dispatch to appropriate threads as needed.
class ISequenceProviderListener {
public:
    virtual ~ISequenceProviderListener() = default;

    /// Called when playback state changes (stopped/playing/paused).
    virtual void onPlaybackStateChanged(PlaybackState newState) = 0;

    /// Called when playback position changes during playback.
    /// @param positionSeconds Current playback position in seconds.
    virtual void onPlaybackPositionChanged(double positionSeconds) = 0;

    /// Called when a sequence is loaded.
    virtual void onSequenceLoaded() = 0;

    /// Called when a sequence is closed/unloaded.
    virtual void onSequenceClosed() = 0;

    /// Called when sequence data is modified.
    virtual void onSequenceModified() = 0;
};

/// Abstract interface for sequence state access.
///
/// This interface provides read-only access to sequence metadata and
/// playback control. It abstracts the sequence state from the underlying
/// implementation (xLightsFrame or standalone).
///
/// All methods use standard C++ types only - no wxWidgets types.
class ISequenceProvider {
public:
    virtual ~ISequenceProvider() = default;

    // ------------------------------------------------------------------
    // Sequence Metadata (read-only)
    // ------------------------------------------------------------------

    /// Get the full path to the currently loaded sequence file.
    /// @return Absolute path to the sequence file, or empty string if none loaded.
    virtual std::string getSequencePath() const = 0;

    /// Get the name of the currently loaded sequence (filename without path/extension).
    /// @return Sequence name, or empty string if none loaded.
    virtual std::string getSequenceName() const = 0;

    /// Get the total duration of the sequence.
    /// @return Duration in seconds, or 0.0 if no sequence loaded.
    virtual double getSequenceDuration() const = 0;

    /// Get the frame interval (milliseconds per frame).
    /// @return Frame interval in milliseconds (e.g., 50 for 20fps), or 0 if none loaded.
    virtual int getFrameMS() const = 0;

    /// Check if a sequence is currently loaded.
    /// @return true if a sequence is loaded and ready for playback.
    virtual bool isSequenceLoaded() const = 0;

    /// Get the path to the media file associated with the sequence.
    /// @return Absolute path to media file, or empty string if no media.
    virtual std::string getMediaPath() const = 0;

    /// Get the number of channels in the sequence.
    /// @return Number of channels, or 0 if no sequence loaded.
    virtual unsigned int getNumChannels() const = 0;

    /// Get the number of frames in the sequence.
    /// @return Number of frames, or 0 if no sequence loaded.
    virtual unsigned int getNumFrames() const = 0;

    // ------------------------------------------------------------------
    // Sequence File Operations
    // ------------------------------------------------------------------

    /// Load a sequence from the given path.
    /// @param path Path to the sequence file.
    /// @return true if the sequence was loaded successfully.
    virtual bool loadSequence(const std::string& path) = 0;

    /// Save the current sequence.
    /// @param path Path to save to, or empty to save to current file.
    /// @return true on success.
    virtual bool saveSequence(const std::string& path = "") = 0;

    /// Close the current sequence.
    /// @return true if closed successfully.
    virtual bool closeSequence() = 0;

    // ------------------------------------------------------------------
    // Playback State (read/write, thread-safe)
    // ------------------------------------------------------------------

    /// Get the current playback state.
    /// @return Current state: Stopped, Playing, or Paused.
    virtual PlaybackState getPlaybackState() const = 0;

    /// Get the current playback position.
    /// @return Position in seconds from start of sequence.
    virtual double getCurrentPosition() const = 0;

    /// Set the playback state.
    /// @param state The desired playback state.
    ///
    /// Calling with:
    /// - Playing: Starts or resumes playback from current position.
    /// - Paused: Pauses playback at current position.
    /// - Stopped: Stops playback and resets position to beginning.
    virtual void setPlaybackState(PlaybackState state) = 0;

    /// Seek to a specific position in the sequence.
    /// @param positionSeconds Target position in seconds.
    ///
    /// Position is clamped to valid range [0, duration].
    /// If playing, playback continues from the new position.
    /// If paused/stopped, position is updated but state is unchanged.
    virtual void seek(double positionSeconds) = 0;

    // ------------------------------------------------------------------
    // Listener Management
    // ------------------------------------------------------------------

    /// Add a listener for state change notifications.
    /// @param listener Pointer to listener. Caller retains ownership.
    ///
    /// The same listener should not be added multiple times.
    /// Listeners are called in the order they were added.
    virtual void addListener(ISequenceProviderListener* listener) = 0;

    /// Remove a previously added listener.
    /// @param listener Pointer to listener to remove.
    ///
    /// If the listener was not previously added, this is a no-op.
    virtual void removeListener(ISequenceProviderListener* listener) = 0;
};

} // namespace xlEngine
