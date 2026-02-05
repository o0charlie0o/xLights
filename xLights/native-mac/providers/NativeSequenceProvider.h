/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

// NativeSequenceProvider: Native macOS implementation of ISequenceProvider.
//
// This provider manages sequence state and playback natively without wxWidgets
// dependencies. It coordinates with XLAudioPlayer (AVFoundation) for audio
// playback and uses CADisplayLink for frame timing.
//
// Part of the native macOS rebuild (Phase 3: Create Native Provider Implementations).
// See DECOUPLING_GUIDE.md for architectural context.
//
// Thread Safety:
// All methods are protected by internal mutexes for thread-safe access.
// Playback state methods may be called from any thread. Listener callbacks
// are always dispatched to the main thread for UI safety.
//
// Usage:
// - Create a NativeSequenceProvider instance
// - Call loadSequence() with path to .xLights sequence file
// - Use playback controls: setPlaybackState(), seek()
// - Register listeners for state change notifications
// - Provider coordinates internally with XLAudioPlayer for audio sync
//
// Audio Coordination:
// This provider owns and manages an XLAudioPlayer instance for audio playback.
// The audio player position is used as the authoritative time source during
// playback to ensure tight audio-visual synchronization.

#include "../../engine/interfaces/ISequenceProvider.h"

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

// Forward declarations for Objective-C types
#ifdef __OBJC__
@class XLAudioPlayer;
@class NSXMLDocument;
@class NSXMLElement;
@class NSTimer;
#else
typedef void* id;
typedef void* NSXMLElement;
#endif

namespace xlEngine {

/// Sequence metadata parsed from .xLights XML files.
/// This structure holds the essential metadata needed for playback without
/// requiring the full wxWidgets-based xLightsXmlFile parser.
struct NativeSequenceMetadata {
    std::string sequencePath;        // Full path to .xLights file
    std::string sequenceName;        // Filename without extension
    std::string mediaPath;           // Path to associated media file (audio/video)
    double durationSeconds = 0.0;    // Total sequence duration in seconds
    int frameMS = 50;                // Milliseconds per frame (default 20fps)
    std::string sequenceType;        // "Animation" or "Media"
    std::string author;              // Author metadata
    std::string song;                // Song name metadata
    std::string artist;              // Artist metadata

    /// Calculate frame count from duration and frame interval.
    int getFrameCount() const {
        if (frameMS <= 0) return 0;
        return static_cast<int>((durationSeconds * 1000.0) / frameMS) + 1;
    }

    /// Get frames per second.
    double getFPS() const {
        if (frameMS <= 0) return 20.0;
        return 1000.0 / frameMS;
    }
};

/// An effect within a sequence element layer.
struct NativeSequenceEffect {
    std::string name;                // Effect type name (e.g., "On", "Bars", "Fire")
    int startTimeMS = 0;             // Start time in milliseconds
    int endTimeMS = 0;               // End time in milliseconds
    int paletteIndex = 0;            // Index into color palettes
    int effectIndex = 0;             // Index into effect definitions
    std::string settings;            // Effect settings string
};

/// A layer within a sequence element (model/timing track).
struct NativeSequenceLayer {
    std::vector<NativeSequenceEffect> effects;
};

/// A sequence element (model or timing track).
struct NativeSequenceElement {
    std::string name;                // Element name (model or timing track name)
    std::string type;                // "model" or "timing"
    bool visible = true;
    bool collapsed = false;
    std::vector<NativeSequenceLayer> layers;
};

/// Native macOS implementation of ISequenceProvider.
///
/// This class provides sequence state management without wxWidgets runtime
/// dependencies. It parses sequence XML using native NSXMLDocument and
/// coordinates playback with XLAudioPlayer (AVFoundation).
///
/// Key features:
/// - Native XML parsing for sequence metadata
/// - Audio playback via XLAudioPlayer (AVFoundation)
/// - CADisplayLink-based frame timing for smooth playback
/// - Thread-safe state management
/// - Listener-based state change notifications
class NativeSequenceProvider : public ISequenceProvider {
public:
    /// Constructs an empty NativeSequenceProvider.
    NativeSequenceProvider();

    ~NativeSequenceProvider() override;

    // Non-copyable
    NativeSequenceProvider(const NativeSequenceProvider&) = delete;
    NativeSequenceProvider& operator=(const NativeSequenceProvider&) = delete;

    // =========================================================================
    // ISequenceProvider Implementation
    // =========================================================================

    // --- Sequence Metadata (read-only) ---
    std::string getSequencePath() const override;
    std::string getSequenceName() const override;
    double getSequenceDuration() const override;
    int getFrameMS() const override;
    bool isSequenceLoaded() const override;
    std::string getMediaPath() const override;
    unsigned int getNumChannels() const override;
    unsigned int getNumFrames() const override;

    // --- File Operations (interface) ---
    bool loadSequence(const std::string& path) override;
    bool saveSequence(const std::string& path = "") override;
    bool closeSequence() override;

    // --- Playback State (thread-safe) ---
    PlaybackState getPlaybackState() const override;
    double getCurrentPosition() const override;
    void setPlaybackState(PlaybackState state) override;
    void seek(double positionSeconds) override;

    // --- Listener Management ---
    void addListener(ISequenceProviderListener* listener) override;
    void removeListener(ISequenceProviderListener* listener) override;

    // =========================================================================
    // Native-Specific Methods
    // =========================================================================

    /// Load a sequence from an .xLights file with explicit show folder path.
    /// @param sequencePath Full path to the .xLights sequence file.
    /// @param showFolderPath Path to the show folder (for resolving relative media paths).
    /// @return true if the sequence was loaded successfully.
    bool loadSequenceWithShowFolder(const std::string& sequencePath, const std::string& showFolderPath);

    /// Close the current sequence and release resources.
    void closeAndReleaseSequence();

    /// Get the loaded sequence metadata.
    /// @return Metadata structure, or empty struct if no sequence loaded.
    NativeSequenceMetadata getMetadata() const;

    /// Get the current frame index based on playback position.
    /// @return Current frame index (0-based), or 0 if not playing.
    int getCurrentFrameIndex() const;

    /// Set the loop playback mode.
    /// @param enabled If true, playback will loop from beginning when reaching end.
    void setLoopEnabled(bool enabled);

    /// Get the loop playback mode.
    /// @return true if looping is enabled.
    bool isLoopEnabled() const;

    /// Set the playback rate.
    /// @param rate Playback rate multiplier (1.0 = normal speed).
    void setPlaybackRate(double rate);

    /// Get the current playback rate.
    /// @return Current playback rate (1.0 = normal speed).
    double getPlaybackRate() const;

    /// Set audio volume.
    /// @param volume Volume level (0.0 = mute, 1.0 = full).
    void setVolume(double volume);

    /// Get current audio volume.
    /// @return Volume level (0.0 to 1.0).
    double getVolume() const;

    /// Check if the sequence has audio media.
    /// @return true if audio is available and loaded.
    bool hasAudioMedia() const;

    /// Get all sequence elements (models and timing tracks).
    /// @return Vector of sequence elements with their effects.
    const std::vector<NativeSequenceElement>& getElements() const;

    /// Get element count.
    /// @return Number of elements in the sequence.
    size_t getElementCount() const;

    /// Callback type for frame tick notifications during playback.
    /// The callback receives the current position in seconds.
    using FrameTickCallback = std::function<void(double positionSeconds)>;

    /// Set a callback for frame tick notifications.
    /// This is called on each display frame during playback for UI updates.
    /// The callback is invoked on the main thread.
    /// @param callback The callback function, or nullptr to remove.
    void setFrameTickCallback(FrameTickCallback callback);

private:
    // Sequence metadata
    NativeSequenceMetadata _metadata;
    std::atomic<bool> _sequenceLoaded{false};

    // Sequence elements (models and timing tracks with their effects)
    std::vector<NativeSequenceElement> _elements;
    mutable std::mutex _elementsMutex;

    // Playback state
    std::atomic<PlaybackState> _playbackState{PlaybackState::Stopped};
    std::atomic<double> _currentPosition{0.0};
    std::atomic<bool> _loopEnabled{false};
    std::atomic<double> _playbackRate{1.0};
    std::atomic<double> _volume{1.0};

    // Show folder path (for resolving relative paths)
    std::string _showFolderPath;

    // Audio player (Objective-C, managed via pointer)
    void* _audioPlayer;  // XLAudioPlayer*

    // Frame tick callback
    FrameTickCallback _frameTickCallback;

    // Position update timer (Objective-C)
    void* _positionTimer;  // NSTimer*

    // Listeners
    std::vector<ISequenceProviderListener*> _listeners;
    mutable std::mutex _listenerMutex;
    mutable std::mutex _metadataMutex;
    mutable std::mutex _callbackMutex;

    // Private methods
    bool parseSequenceXML(const std::string& filePath);
    void parseElementEffects(NSXMLElement* root);
    std::string resolveMediaPath(const std::string& mediaFile);
    void loadAudioMedia(const std::string& mediaPath);
    void unloadAudioMedia();

    void startPositionTimer();
    void stopPositionTimer();
    void onPositionTimerTick();

    void syncAudioToPosition(double positionSeconds);
    double getAudioPosition() const;

    // Notification helpers
    void notifyPlaybackStateChanged(PlaybackState state);
    void notifyPositionChanged(double positionSeconds);
    void notifySequenceLoaded();
    void notifySequenceClosed();
    void notifySequenceModified();

    // Dispatch to main thread
    void dispatchToMainThread(std::function<void()> block);
};

} // namespace xlEngine
