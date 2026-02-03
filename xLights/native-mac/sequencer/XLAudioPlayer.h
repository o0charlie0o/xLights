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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class XLAudioPlayer;

/// Playback state for the audio player.
typedef NS_ENUM(NSInteger, XLAudioPlaybackState) {
    XLAudioPlaybackStateStopped = 0,
    XLAudioPlaybackStatePlaying,
    XLAudioPlaybackStatePaused
};

/// Delegate protocol for audio playback events.
@protocol XLAudioPlayerDelegate <NSObject>
@optional

/// Called when playback state changes.
- (void)audioPlayer:(XLAudioPlayer *)player didChangeState:(XLAudioPlaybackState)state;

/// Called periodically during playback with current position.
/// @param positionMS Current playback position in milliseconds.
- (void)audioPlayer:(XLAudioPlayer *)player didUpdatePosition:(CGFloat)positionMS;

/// Called when playback reaches the end of the audio.
- (void)audioPlayerDidReachEnd:(XLAudioPlayer *)player;

/// Called when an error occurs during playback.
- (void)audioPlayer:(XLAudioPlayer *)player didEncounterError:(NSError *)error;

@end

/// Native macOS audio player for sequence playback using AVFoundation.
///
/// This class provides audio playback functionality integrated with the
/// xLights sequencer, supporting:
/// - Loading audio files (MP3, WAV, AAC, M4A, etc.)
/// - Play, pause, stop controls
/// - Seeking to specific time positions
/// - Playback rate adjustment
/// - Volume control
/// - Periodic position updates for UI synchronization
///
/// The player uses AVAudioEngine for low-latency playback with precise
/// timing control, suitable for synchronizing with lighting sequences.
@interface XLAudioPlayer : NSObject

/// Delegate for receiving playback events.
@property (nonatomic, weak, nullable) id<XLAudioPlayerDelegate> delegate;

/// Current playback state.
@property (nonatomic, readonly) XLAudioPlaybackState playbackState;

/// Whether audio is currently loaded and ready to play.
@property (nonatomic, readonly) BOOL isLoaded;

/// Current playback position in milliseconds.
@property (nonatomic, readonly) CGFloat currentPositionMS;

/// Total duration of the loaded audio in milliseconds.
@property (nonatomic, readonly) CGFloat durationMS;

/// Playback rate (1.0 = normal speed, 0.5 = half speed, 2.0 = double speed).
/// Range: 0.25 to 4.0.
@property (nonatomic, assign) CGFloat playbackRate;

/// Volume level (0.0 = silent, 1.0 = full volume).
@property (nonatomic, assign) CGFloat volume;

/// Whether to loop playback when reaching the end.
@property (nonatomic, assign) BOOL loopEnabled;

/// Interval in milliseconds for position update callbacks.
/// Default is 50ms (20 updates per second).
@property (nonatomic, assign) CGFloat positionUpdateIntervalMS;

#pragma mark - Initialization

/// Create a new audio player instance.
+ (instancetype)sharedPlayer;

/// Initialize a new audio player.
- (instancetype)init;

#pragma mark - Loading

/// Load an audio file for playback.
/// @param path Full path to the audio file.
/// @return YES if loaded successfully, NO on failure.
- (BOOL)loadAudioFile:(NSString *)path;

/// Load an audio file for playback with completion handler.
/// @param path Full path to the audio file.
/// @param completion Called on main thread when loading completes or fails.
- (void)loadAudioFileAsync:(NSString *)path
                completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Unload the current audio file and release resources.
- (void)unload;

#pragma mark - Playback Control

/// Start or resume playback from current position.
- (void)play;

/// Start playback from a specific position.
/// @param positionMS Position in milliseconds to start from.
- (void)playFromPosition:(CGFloat)positionMS;

/// Pause playback, maintaining current position.
- (void)pause;

/// Stop playback and reset position to beginning.
- (void)stop;

/// Toggle between play and pause states.
- (void)togglePlayPause;

#pragma mark - Seeking

/// Seek to a specific position.
/// @param positionMS Target position in milliseconds.
- (void)seekToPosition:(CGFloat)positionMS;

/// Seek relative to current position.
/// @param deltaMS Offset in milliseconds (positive = forward, negative = backward).
- (void)seekRelative:(CGFloat)deltaMS;

/// Seek to the beginning of the audio.
- (void)seekToStart;

/// Seek to the end of the audio.
- (void)seekToEnd;

#pragma mark - Audio Output Device

/// Get list of available audio output devices.
+ (NSArray<NSString *> *)availableOutputDevices;

/// Set the audio output device.
/// @param deviceName Name of the device, or nil for system default.
/// @return YES if device was set successfully.
- (BOOL)setOutputDevice:(nullable NSString *)deviceName;

/// Currently selected output device name, or nil for system default.
@property (nonatomic, readonly, nullable) NSString *outputDeviceName;

@end

NS_ASSUME_NONNULL_END
