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

/**
 * @file Audio.h
 * @brief Platform-abstracted audio system for playback and analysis.
 *
 * This header provides audio playback and analysis functionality that is
 * independent of wxWidgets. It supports:
 * - Audio file loading and playback
 * - Precise seeking and position tracking
 * - Waveform visualization data
 * - Spectrum analysis (FFT)
 * - Beat detection
 *
 * Platform implementations:
 * - macOS: AVFoundation (AVAudioEngine)
 * - Windows: XAudio2 or WASAPI
 * - Linux: PulseAudio or ALSA
 * - Fallback: miniaudio (cross-platform)
 *
 * Design principles:
 * - Zero wxWidgets dependencies
 * - Thread-safe callbacks
 * - Precise timing for sequence synchronization
 * - Modern C++17/20 idioms
 */

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace xlCore {

/**
 * @brief Playback state enumeration.
 */
enum class AudioPlaybackState {
    Stopped = 0,
    Playing,
    Paused
};

/**
 * @brief Callback type for periodic position updates during playback.
 * @param positionSeconds Current playback position in seconds.
 */
using AudioPositionCallback = std::function<void(double positionSeconds)>;

/**
 * @brief Callback type for playback completion notification.
 */
using AudioCompletionCallback = std::function<void()>;

/**
 * @brief Callback type for playback state changes.
 * @param state New playback state.
 */
using AudioStateCallback = std::function<void(AudioPlaybackState state)>;

/**
 * @brief Callback type for error notifications.
 * @param errorMessage Description of the error.
 */
using AudioErrorCallback = std::function<void(const std::string& errorMessage)>;

/**
 * @brief Abstract audio player interface.
 *
 * Provides audio playback functionality with precise timing control,
 * suitable for synchronizing with lighting sequences.
 *
 * Thread Safety:
 * - All methods are safe to call from any thread
 * - Callbacks are dispatched to the callback thread (typically main thread)
 *
 * Example usage:
 * @code
 * auto player = xlCore::createAudioPlayer();
 * if (player->load("/path/to/audio.mp3")) {
 *     player->setPositionCallback([](double pos) {
 *         // Update UI with current position
 *     }, 0.05);  // 50ms updates
 *     player->play();
 * }
 * @endcode
 */
class AudioPlayer {
public:
    virtual ~AudioPlayer() = default;

    // Non-copyable, non-movable (use unique_ptr)
    AudioPlayer(const AudioPlayer&) = delete;
    AudioPlayer& operator=(const AudioPlayer&) = delete;
    AudioPlayer(AudioPlayer&&) = delete;
    AudioPlayer& operator=(AudioPlayer&&) = delete;

    // ========================================================================
    // Lifecycle
    // ========================================================================

    /**
     * @brief Load an audio file for playback.
     * @param filePath Full path to the audio file.
     * @return true if loaded successfully, false on failure.
     *
     * Supported formats depend on platform:
     * - macOS: MP3, AAC, M4A, WAV, AIFF, FLAC
     * - Windows: MP3, WAV, WMA, AAC
     * - Linux: MP3, WAV, OGG, FLAC
     */
    virtual bool load(const std::string& filePath) = 0;

    /**
     * @brief Unload the current audio file and release resources.
     */
    virtual void unload() = 0;

    /**
     * @brief Check if audio is loaded and ready to play.
     * @return true if audio is loaded.
     */
    [[nodiscard]] virtual bool isLoaded() const = 0;

    // ========================================================================
    // Playback Control
    // ========================================================================

    /**
     * @brief Start or resume playback from current position.
     */
    virtual void play() = 0;

    /**
     * @brief Start playback from a specific position.
     * @param positionSeconds Position in seconds to start from.
     */
    virtual void playFromPosition(double positionSeconds) = 0;

    /**
     * @brief Pause playback, maintaining current position.
     */
    virtual void pause() = 0;

    /**
     * @brief Stop playback and reset position to beginning.
     */
    virtual void stop() = 0;

    /**
     * @brief Toggle between play and pause states.
     */
    virtual void togglePlayPause() = 0;

    // ========================================================================
    // Seeking
    // ========================================================================

    /**
     * @brief Seek to a specific position.
     * @param positionSeconds Target position in seconds.
     */
    virtual void seek(double positionSeconds) = 0;

    /**
     * @brief Seek relative to current position.
     * @param deltaSeconds Offset in seconds (positive = forward, negative = backward).
     */
    virtual void seekRelative(double deltaSeconds) = 0;

    // ========================================================================
    // State
    // ========================================================================

    /**
     * @brief Get current playback state.
     * @return Current state (Stopped, Playing, or Paused).
     */
    [[nodiscard]] virtual AudioPlaybackState playbackState() const = 0;

    /**
     * @brief Check if currently playing.
     * @return true if playback state is Playing.
     */
    [[nodiscard]] virtual bool isPlaying() const = 0;

    /**
     * @brief Get current playback position.
     * @return Current position in seconds.
     */
    [[nodiscard]] virtual double position() const = 0;

    /**
     * @brief Get current playback position in milliseconds.
     * @return Current position in milliseconds.
     */
    [[nodiscard]] virtual int64_t positionMS() const = 0;

    /**
     * @brief Get total duration of loaded audio.
     * @return Duration in seconds, or 0 if no audio loaded.
     */
    [[nodiscard]] virtual double duration() const = 0;

    /**
     * @brief Get total duration in milliseconds.
     * @return Duration in milliseconds, or 0 if no audio loaded.
     */
    [[nodiscard]] virtual int64_t durationMS() const = 0;

    // ========================================================================
    // Volume and Rate
    // ========================================================================

    /**
     * @brief Set playback volume.
     * @param volume Volume level (0.0 = silent, 1.0 = full volume).
     */
    virtual void setVolume(float volume) = 0;

    /**
     * @brief Get current volume level.
     * @return Volume level (0.0 to 1.0).
     */
    [[nodiscard]] virtual float volume() const = 0;

    /**
     * @brief Set playback rate (speed).
     * @param rate Playback rate (1.0 = normal, 0.5 = half speed, 2.0 = double).
     *             Typical range: 0.25 to 4.0.
     */
    virtual void setPlaybackRate(float rate) = 0;

    /**
     * @brief Get current playback rate.
     * @return Playback rate.
     */
    [[nodiscard]] virtual float playbackRate() const = 0;

    // ========================================================================
    // Looping
    // ========================================================================

    /**
     * @brief Enable or disable looping.
     * @param enabled true to loop playback when reaching the end.
     */
    virtual void setLoopEnabled(bool enabled) = 0;

    /**
     * @brief Check if looping is enabled.
     * @return true if looping is enabled.
     */
    [[nodiscard]] virtual bool isLoopEnabled() const = 0;

    // ========================================================================
    // Callbacks
    // ========================================================================

    /**
     * @brief Set callback for periodic position updates during playback.
     * @param callback Function to call with current position.
     * @param intervalSeconds Interval between updates (default 0.05 = 50ms).
     *
     * The callback is dispatched to the main thread (or configured callback thread).
     * Pass nullptr to disable position callbacks.
     */
    virtual void setPositionCallback(AudioPositionCallback callback,
                                     double intervalSeconds = 0.05) = 0;

    /**
     * @brief Set callback for playback completion.
     * @param callback Function to call when playback reaches the end.
     *
     * Not called if looping is enabled (playback restarts instead).
     * Pass nullptr to disable completion callbacks.
     */
    virtual void setCompletionCallback(AudioCompletionCallback callback) = 0;

    /**
     * @brief Set callback for playback state changes.
     * @param callback Function to call when state changes.
     *
     * Pass nullptr to disable state callbacks.
     */
    virtual void setStateCallback(AudioStateCallback callback) = 0;

    /**
     * @brief Set callback for error notifications.
     * @param callback Function to call when an error occurs.
     *
     * Pass nullptr to disable error callbacks.
     */
    virtual void setErrorCallback(AudioErrorCallback callback) = 0;

    // ========================================================================
    // Audio Device Selection
    // ========================================================================

    /**
     * @brief Get list of available audio output devices.
     * @return Vector of device names.
     */
    [[nodiscard]] virtual std::vector<std::string> availableOutputDevices() const = 0;

    /**
     * @brief Set the audio output device.
     * @param deviceName Name of the device, or empty string for system default.
     * @return true if device was set successfully.
     */
    virtual bool setOutputDevice(const std::string& deviceName) = 0;

    /**
     * @brief Get currently selected output device name.
     * @return Device name, or empty string for system default.
     */
    [[nodiscard]] virtual std::string outputDevice() const = 0;

protected:
    AudioPlayer() = default;
};

/**
 * @brief Waveform peak data for visualization.
 */
struct WaveformPeak {
    float min;  ///< Minimum sample value in this bucket
    float max;  ///< Maximum sample value in this bucket
};

/**
 * @brief Abstract audio analyzer interface.
 *
 * Provides audio analysis functionality for waveform visualization,
 * spectrum analysis, and beat detection. Operates independently of
 * the AudioPlayer - can analyze files without playing them.
 *
 * Thread Safety:
 * - Thread-safe for concurrent read operations after loading
 * - Load/unload operations should be serialized
 *
 * Example usage:
 * @code
 * auto analyzer = xlCore::createAudioAnalyzer();
 * if (analyzer->load("/path/to/audio.mp3")) {
 *     // Get waveform data for display
 *     auto peaks = analyzer->getWaveformPeaks(0, 60, 1920);  // First minute, 1920 pixels
 *
 *     // Get spectrum at current position
 *     auto spectrum = analyzer->getSpectrum(30.0, 512);  // At 30 seconds
 * }
 * @endcode
 */
class AudioAnalyzer {
public:
    virtual ~AudioAnalyzer() = default;

    // Non-copyable, non-movable
    AudioAnalyzer(const AudioAnalyzer&) = delete;
    AudioAnalyzer& operator=(const AudioAnalyzer&) = delete;
    AudioAnalyzer(AudioAnalyzer&&) = delete;
    AudioAnalyzer& operator=(AudioAnalyzer&&) = delete;

    // ========================================================================
    // Loading
    // ========================================================================

    /**
     * @brief Load an audio file for analysis.
     * @param filePath Full path to the audio file.
     * @return true if loaded successfully, false on failure.
     *
     * Loading is typically fast as it may not decode the entire file upfront.
     * Some analysis operations may trigger deferred decoding.
     */
    virtual bool load(const std::string& filePath) = 0;

    /**
     * @brief Unload the current audio file and release resources.
     */
    virtual void unload() = 0;

    /**
     * @brief Check if audio is loaded.
     * @return true if audio is loaded and ready for analysis.
     */
    [[nodiscard]] virtual bool isLoaded() const = 0;

    // ========================================================================
    // Properties
    // ========================================================================

    /**
     * @brief Get total duration of the audio.
     * @return Duration in seconds.
     */
    [[nodiscard]] virtual double duration() const = 0;

    /**
     * @brief Get total duration in milliseconds.
     * @return Duration in milliseconds.
     */
    [[nodiscard]] virtual int64_t durationMS() const = 0;

    /**
     * @brief Get audio sample rate.
     * @return Sample rate in Hz (e.g., 44100, 48000).
     */
    [[nodiscard]] virtual int sampleRate() const = 0;

    /**
     * @brief Get number of audio channels.
     * @return Channel count (1 = mono, 2 = stereo).
     */
    [[nodiscard]] virtual int channels() const = 0;

    /**
     * @brief Get the file path of the loaded audio.
     * @return File path, or empty string if no audio loaded.
     */
    [[nodiscard]] virtual std::string filePath() const = 0;

    // ========================================================================
    // Waveform Data
    // ========================================================================

    /**
     * @brief Get waveform sample data for visualization.
     * @param startSeconds Start time in seconds.
     * @param endSeconds End time in seconds.
     * @param numBuckets Number of data points (typically matches pixel width).
     * @param channel Channel index (0 = left/mono, 1 = right).
     * @return Vector of normalized sample values (-1.0 to 1.0), averaged per bucket.
     *
     * This method returns averaged sample values for each bucket, suitable for
     * simple waveform displays.
     */
    [[nodiscard]] virtual std::vector<float> getWaveform(
        double startSeconds,
        double endSeconds,
        size_t numBuckets,
        int channel = 0) const = 0;

    /**
     * @brief Get waveform peak data for visualization.
     * @param startSeconds Start time in seconds.
     * @param endSeconds End time in seconds.
     * @param numBuckets Number of data points (typically matches pixel width).
     * @param channel Channel index (0 = left/mono, 1 = right).
     * @return Vector of WaveformPeak structs with min/max for each bucket.
     *
     * This method returns min/max pairs for each time bucket, providing better
     * detail for waveform visualization than averaged samples.
     */
    [[nodiscard]] virtual std::vector<WaveformPeak> getWaveformPeaks(
        double startSeconds,
        double endSeconds,
        size_t numBuckets,
        int channel = 0) const = 0;

    // ========================================================================
    // Spectrum Analysis
    // ========================================================================

    /**
     * @brief Get frequency spectrum at a specific time.
     * @param timeSeconds Time position in seconds.
     * @param numBands Number of frequency bands (typically power of 2, e.g., 512).
     * @return Vector of magnitude values (0.0 to ~1.0) for each frequency band.
     *
     * The spectrum is computed using FFT. Lower indices correspond to lower
     * frequencies. The maximum frequency is half the sample rate (Nyquist).
     */
    [[nodiscard]] virtual std::vector<float> getSpectrum(
        double timeSeconds,
        size_t numBands = 512) const = 0;

    // ========================================================================
    // Level Analysis
    // ========================================================================

    /**
     * @brief Get RMS (root mean square) level at a specific time.
     * @param timeSeconds Time position in seconds.
     * @param windowSeconds Duration of analysis window (default 0.05 = 50ms).
     * @return RMS level (0.0 to 1.0).
     *
     * RMS provides a measure of audio loudness at a given time, useful for
     * VU meter displays and audio-reactive effects.
     */
    [[nodiscard]] virtual float getRMSLevel(
        double timeSeconds,
        double windowSeconds = 0.05) const = 0;

    /**
     * @brief Get peak level at a specific time.
     * @param timeSeconds Time position in seconds.
     * @param windowSeconds Duration of analysis window (default 0.05 = 50ms).
     * @return Peak level (0.0 to 1.0).
     */
    [[nodiscard]] virtual float getPeakLevel(
        double timeSeconds,
        double windowSeconds = 0.05) const = 0;

    // ========================================================================
    // Beat Detection
    // ========================================================================

    /**
     * @brief Detect beats in the audio.
     * @return Vector of beat times in seconds.
     *
     * Beat detection is performed using onset detection algorithms.
     * This operation may be computationally expensive and results should
     * be cached by the caller.
     */
    [[nodiscard]] virtual std::vector<double> detectBeats() const = 0;

    /**
     * @brief Estimate tempo (beats per minute) of the audio.
     * @return Estimated BPM, or 0 if detection fails.
     */
    [[nodiscard]] virtual double estimateBPM() const = 0;

    // ========================================================================
    // Raw Sample Access
    // ========================================================================

    /**
     * @brief Get raw audio samples for a time range.
     * @param startSeconds Start time in seconds.
     * @param endSeconds End time in seconds.
     * @param channel Channel index (0 = left/mono, 1 = right).
     * @return Vector of normalized sample values (-1.0 to 1.0).
     *
     * Returns samples at the native sample rate. Use this for custom
     * analysis or when precise sample-level access is needed.
     */
    [[nodiscard]] virtual std::vector<float> getRawSamples(
        double startSeconds,
        double endSeconds,
        int channel = 0) const = 0;

protected:
    AudioAnalyzer() = default;
};

// ============================================================================
// Factory Functions
// ============================================================================

/**
 * @brief Create a platform-specific audio player.
 * @return Unique pointer to AudioPlayer implementation.
 *
 * Returns the best available implementation for the current platform:
 * - macOS: AVFoundation-based player
 * - Windows: XAudio2 or WASAPI-based player
 * - Linux: PulseAudio or ALSA-based player
 * - Fallback: miniaudio-based player
 */
std::unique_ptr<AudioPlayer> createAudioPlayer();

/**
 * @brief Create a platform-specific audio analyzer.
 * @return Unique pointer to AudioAnalyzer implementation.
 *
 * Returns the best available implementation for the current platform.
 */
std::unique_ptr<AudioAnalyzer> createAudioAnalyzer();

/**
 * @brief Get list of available audio input devices.
 * @return Vector of input device names.
 *
 * Useful for audio capture/recording functionality.
 */
std::vector<std::string> getAudioInputDevices();

/**
 * @brief Get list of available audio output devices.
 * @return Vector of output device names.
 */
std::vector<std::string> getAudioOutputDevices();

} // namespace xlCore
