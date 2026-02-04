/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "NativeSequenceProvider.h"

#import <Foundation/Foundation.h>
#import "../sequencer/XLAudioPlayer.h"

#include <algorithm>

// Position update interval in seconds (50ms = 20 updates/sec)
static const NSTimeInterval kPositionUpdateInterval = 0.050;

namespace xlEngine {

// MARK: - Construction / Destruction

NativeSequenceProvider::NativeSequenceProvider()
    : _audioPlayer(nil)
    , _positionTimer(nil)
{
}

NativeSequenceProvider::~NativeSequenceProvider()
{
    closeAndReleaseSequence();
}

// MARK: - ISequenceProvider: Sequence Metadata

std::string NativeSequenceProvider::getSequencePath() const
{
    std::lock_guard<std::mutex> lock(_metadataMutex);
    return _metadata.sequencePath;
}

std::string NativeSequenceProvider::getSequenceName() const
{
    std::lock_guard<std::mutex> lock(_metadataMutex);
    return _metadata.sequenceName;
}

double NativeSequenceProvider::getSequenceDuration() const
{
    std::lock_guard<std::mutex> lock(_metadataMutex);
    return _metadata.durationSeconds;
}

int NativeSequenceProvider::getFrameMS() const
{
    std::lock_guard<std::mutex> lock(_metadataMutex);
    return _metadata.frameMS;
}

bool NativeSequenceProvider::isSequenceLoaded() const
{
    return _sequenceLoaded.load();
}

std::string NativeSequenceProvider::getMediaPath() const
{
    std::lock_guard<std::mutex> lock(_metadataMutex);
    return _metadata.mediaPath;
}

unsigned int NativeSequenceProvider::getNumChannels() const
{
    // TODO: Parse channel count from sequence data
    // For now, return 0 as we don't have full sequence data parsing yet
    return 0;
}

unsigned int NativeSequenceProvider::getNumFrames() const
{
    std::lock_guard<std::mutex> lock(_metadataMutex);
    return static_cast<unsigned int>(_metadata.getFrameCount());
}

// MARK: - ISequenceProvider: File Operations

bool NativeSequenceProvider::loadSequence(const std::string& path)
{
    // Derive show folder path from sequence path
    NSString* nsPath = [NSString stringWithUTF8String:path.c_str()];
    NSString* showFolder = [nsPath stringByDeletingLastPathComponent];
    return loadSequenceWithShowFolder(path, [showFolder UTF8String]);
}

bool NativeSequenceProvider::saveSequence(const std::string& path)
{
    // TODO: Implement sequence saving
    NSLog(@"NativeSequenceProvider: saveSequence not yet implemented");
    return false;
}

bool NativeSequenceProvider::closeSequence()
{
    closeAndReleaseSequence();
    return true;
}

// MARK: - ISequenceProvider: Playback State

PlaybackState NativeSequenceProvider::getPlaybackState() const
{
    return _playbackState.load();
}

double NativeSequenceProvider::getCurrentPosition() const
{
    if (!_sequenceLoaded.load()) {
        return 0.0;
    }

    PlaybackState state = _playbackState.load();

    // During playback, get position from audio player for accurate sync
    if (state == PlaybackState::Playing && _audioPlayer != nil) {
        XLAudioPlayer* player = (__bridge XLAudioPlayer*)_audioPlayer;
        if (player.isLoaded) {
            return player.currentPositionMS / 1000.0;
        }
    }

    return _currentPosition.load();
}

void NativeSequenceProvider::setPlaybackState(PlaybackState state)
{
    if (!_sequenceLoaded.load()) {
        return;
    }

    PlaybackState current = _playbackState.load();
    if (current == state) {
        return;
    }

    XLAudioPlayer* player = (__bridge XLAudioPlayer*)_audioPlayer;

    switch (state) {
        case PlaybackState::Playing:
            if (current == PlaybackState::Paused) {
                // Resume from pause
                if (player && player.isLoaded) {
                    [player play];
                }
            } else {
                // Start fresh from current position
                double pos = _currentPosition.load();
                if (player && player.isLoaded) {
                    [player playFromPosition:(CGFloat)(pos * 1000.0)];
                }
            }
            startPositionTimer();
            _playbackState.store(PlaybackState::Playing);
            break;

        case PlaybackState::Paused:
            if (current == PlaybackState::Playing) {
                if (player && player.isLoaded) {
                    [player pause];
                }
                // Capture current position
                _currentPosition.store(getCurrentPosition());
                stopPositionTimer();
            }
            _playbackState.store(PlaybackState::Paused);
            break;

        case PlaybackState::Stopped:
            if (player && player.isLoaded) {
                [player stop];
            }
            _currentPosition.store(0.0);
            stopPositionTimer();
            _playbackState.store(PlaybackState::Stopped);
            break;
    }

    notifyPlaybackStateChanged(state);
    NSLog(@"NativeSequenceProvider: Playback state changed to %d", (int)state);
}

void NativeSequenceProvider::seek(double positionSeconds)
{
    if (!_sequenceLoaded.load()) {
        return;
    }

    // Clamp position to valid range
    double duration = getSequenceDuration();
    positionSeconds = std::max(0.0, std::min(positionSeconds, duration));

    _currentPosition.store(positionSeconds);

    // Seek audio player
    XLAudioPlayer* player = (__bridge XLAudioPlayer*)_audioPlayer;
    if (player && player.isLoaded) {
        [player seekToPosition:(CGFloat)(positionSeconds * 1000.0)];
    }

    notifyPositionChanged(positionSeconds);
    NSLog(@"NativeSequenceProvider: Seek to %.3f sec", positionSeconds);
}

// MARK: - ISequenceProvider: Listener Management

void NativeSequenceProvider::addListener(ISequenceProviderListener* listener)
{
    if (!listener) return;
    std::lock_guard<std::mutex> lock(_listenerMutex);
    if (std::find(_listeners.begin(), _listeners.end(), listener) == _listeners.end()) {
        _listeners.push_back(listener);
    }
}

void NativeSequenceProvider::removeListener(ISequenceProviderListener* listener)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.erase(
        std::remove(_listeners.begin(), _listeners.end(), listener),
        _listeners.end());
}

// MARK: - Native-Specific Methods

bool NativeSequenceProvider::loadSequenceWithShowFolder(const std::string& sequencePath,
                                                        const std::string& showFolderPath)
{
    // Close any existing sequence
    closeAndReleaseSequence();

    if (sequencePath.empty()) {
        NSLog(@"NativeSequenceProvider: Cannot load sequence - path is empty");
        return false;
    }

    NSString* path = [NSString stringWithUTF8String:sequencePath.c_str()];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSLog(@"NativeSequenceProvider: Sequence file not found: %@", path);
        return false;
    }

    _showFolderPath = showFolderPath;

    // Parse the sequence XML
    if (!parseSequenceXML(sequencePath)) {
        NSLog(@"NativeSequenceProvider: Failed to parse sequence XML");
        return false;
    }

    // Load audio media if present
    if (!_metadata.mediaPath.empty()) {
        loadAudioMedia(_metadata.mediaPath);
    }

    _sequenceLoaded.store(true);
    _playbackState.store(PlaybackState::Stopped);
    _currentPosition.store(0.0);

    notifySequenceLoaded();

    NSLog(@"NativeSequenceProvider: Loaded sequence '%s' (%.1f sec, %d ms/frame)",
          _metadata.sequenceName.c_str(),
          _metadata.durationSeconds,
          _metadata.frameMS);

    return true;
}

void NativeSequenceProvider::closeAndReleaseSequence()
{
    // Stop playback
    if (_playbackState.load() != PlaybackState::Stopped) {
        setPlaybackState(PlaybackState::Stopped);
    }

    stopPositionTimer();
    unloadAudioMedia();

    {
        std::lock_guard<std::mutex> lock(_metadataMutex);
        _metadata = NativeSequenceMetadata();
    }

    _showFolderPath.clear();
    _sequenceLoaded.store(false);
    _currentPosition.store(0.0);

    notifySequenceClosed();

    NSLog(@"NativeSequenceProvider: Sequence closed");
}

NativeSequenceMetadata NativeSequenceProvider::getMetadata() const
{
    std::lock_guard<std::mutex> lock(_metadataMutex);
    return _metadata;
}

int NativeSequenceProvider::getCurrentFrameIndex() const
{
    if (!_sequenceLoaded.load()) {
        return 0;
    }

    double position = getCurrentPosition();
    int frameMS = getFrameMS();
    if (frameMS <= 0) {
        frameMS = 50;
    }

    return static_cast<int>((position * 1000.0) / frameMS);
}

void NativeSequenceProvider::setLoopEnabled(bool enabled)
{
    _loopEnabled.store(enabled);

    XLAudioPlayer* player = (__bridge XLAudioPlayer*)_audioPlayer;
    if (player) {
        player.loopEnabled = enabled;
    }
}

bool NativeSequenceProvider::isLoopEnabled() const
{
    return _loopEnabled.load();
}

void NativeSequenceProvider::setPlaybackRate(double rate)
{
    rate = std::max(0.25, std::min(rate, 4.0));
    _playbackRate.store(rate);

    XLAudioPlayer* player = (__bridge XLAudioPlayer*)_audioPlayer;
    if (player) {
        player.playbackRate = (CGFloat)rate;
    }
}

double NativeSequenceProvider::getPlaybackRate() const
{
    return _playbackRate.load();
}

void NativeSequenceProvider::setVolume(double volume)
{
    volume = std::max(0.0, std::min(volume, 1.0));
    _volume.store(volume);

    XLAudioPlayer* player = (__bridge XLAudioPlayer*)_audioPlayer;
    if (player) {
        player.volume = (CGFloat)volume;
    }
}

double NativeSequenceProvider::getVolume() const
{
    return _volume.load();
}

bool NativeSequenceProvider::hasAudioMedia() const
{
    XLAudioPlayer* player = (__bridge XLAudioPlayer*)_audioPlayer;
    return player != nil && player.isLoaded;
}

void NativeSequenceProvider::setFrameTickCallback(FrameTickCallback callback)
{
    std::lock_guard<std::mutex> lock(_callbackMutex);
    _frameTickCallback = callback;
}

// MARK: - Private: XML Parsing

bool NativeSequenceProvider::parseSequenceXML(const std::string& filePath)
{
    NSString* path = [NSString stringWithUTF8String:filePath.c_str()];
    NSError* error = nil;

    // Read file content
    NSData* xmlData = [NSData dataWithContentsOfFile:path options:0 error:&error];
    if (!xmlData || error) {
        NSLog(@"NativeSequenceProvider: Failed to read file: %@ - %@",
              path, error.localizedDescription);
        return false;
    }

    // Parse XML
    NSXMLDocument* xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData
                                                        options:0
                                                          error:&error];
    if (!xmlDoc || error) {
        NSLog(@"NativeSequenceProvider: Failed to parse XML: %@", error.localizedDescription);
        return false;
    }

    // Extract sequence metadata from root element
    NSXMLElement* root = [xmlDoc rootElement];
    if (!root) {
        NSLog(@"NativeSequenceProvider: No root element found");
        return false;
    }

    std::lock_guard<std::mutex> lock(_metadataMutex);

    // Store file path info
    _metadata.sequencePath = filePath;
    _metadata.sequenceName = [[path lastPathComponent] stringByDeletingPathExtension].UTF8String;

    // Look for head element with sequence settings
    NSArray<NSXMLElement*>* headElements = [root elementsForName:@"head"];
    if (headElements.count > 0) {
        NSXMLElement* head = headElements[0];

        // Duration - try multiple attribute names
        NSString* duration = [[head attributeForName:@"duration"] stringValue];
        if (!duration) {
            // Try 'sequenceDuration' attribute
            duration = [[head attributeForName:@"sequenceDuration"] stringValue];
        }
        if (duration) {
            _metadata.durationSeconds = duration.doubleValue;
        }

        // Frame timing
        NSString* timing = [[head attributeForName:@"sequenceTiming"] stringValue];
        if (!timing) {
            timing = [[head attributeForName:@"frameMS"] stringValue];
        }
        if (timing) {
            _metadata.frameMS = timing.intValue;
        }

        // Sequence type
        NSString* type = [[head attributeForName:@"sequenceType"] stringValue];
        if (type) {
            _metadata.sequenceType = type.UTF8String;
        }

        // Media file
        NSString* mediaFile = [[head attributeForName:@"mediaFile"] stringValue];
        if (mediaFile && mediaFile.length > 0) {
            _metadata.mediaPath = resolveMediaPath(mediaFile.UTF8String);
        }

        // Author metadata
        NSString* author = [[head attributeForName:@"author"] stringValue];
        if (author) {
            _metadata.author = author.UTF8String;
        }

        // Song metadata
        NSString* song = [[head attributeForName:@"song"] stringValue];
        if (song) {
            _metadata.song = song.UTF8String;
        }

        // Artist metadata
        NSString* artist = [[head attributeForName:@"artist"] stringValue];
        if (artist) {
            _metadata.artist = artist.UTF8String;
        }
    }

    // Try to get attributes from root if not found in head
    if (_metadata.durationSeconds <= 0) {
        NSString* duration = [[root attributeForName:@"duration"] stringValue];
        if (duration) {
            _metadata.durationSeconds = duration.doubleValue;
        }
    }

    if (_metadata.frameMS <= 0) {
        NSString* timing = [[root attributeForName:@"sequenceTiming"] stringValue];
        if (timing) {
            _metadata.frameMS = timing.intValue;
        }
    }

    // Default frame MS if not specified
    if (_metadata.frameMS <= 0) {
        _metadata.frameMS = 50;  // 20 FPS default
    }

    // Validate duration
    if (_metadata.durationSeconds <= 0) {
        NSLog(@"NativeSequenceProvider: Warning - sequence has no duration specified");
        // Set a default duration if we have media
        if (!_metadata.mediaPath.empty()) {
            NSLog(@"NativeSequenceProvider: Will get duration from audio file");
        }
    }

    NSLog(@"NativeSequenceProvider: Parsed metadata - duration: %.1f sec, frameMS: %d, media: %s",
          _metadata.durationSeconds, _metadata.frameMS,
          _metadata.mediaPath.empty() ? "(none)" : _metadata.mediaPath.c_str());

    return true;
}

std::string NativeSequenceProvider::resolveMediaPath(const std::string& mediaFile)
{
    if (mediaFile.empty()) {
        return "";
    }

    NSString* file = [NSString stringWithUTF8String:mediaFile.c_str()];

    // If it's an absolute path, use it directly
    if ([file hasPrefix:@"/"]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:file]) {
            return mediaFile;
        }
    }

    // Try relative to show folder
    if (!_showFolderPath.empty()) {
        NSString* showFolder = [NSString stringWithUTF8String:_showFolderPath.c_str()];
        NSString* fullPath = [showFolder stringByAppendingPathComponent:file];
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
            return fullPath.UTF8String;
        }
    }

    // Try relative to sequence file
    {
        std::lock_guard<std::mutex> lock(_metadataMutex);
        if (!_metadata.sequencePath.empty()) {
            NSString* seqPath = [NSString stringWithUTF8String:_metadata.sequencePath.c_str()];
            NSString* seqDir = [seqPath stringByDeletingLastPathComponent];
            NSString* fullPath = [seqDir stringByAppendingPathComponent:file];
            if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
                return fullPath.UTF8String;
            }
        }
    }

    NSLog(@"NativeSequenceProvider: Could not resolve media path: %@", file);
    return "";
}

// MARK: - Private: Audio Management

void NativeSequenceProvider::loadAudioMedia(const std::string& mediaPath)
{
    if (mediaPath.empty()) {
        return;
    }

    // Create audio player if needed
    if (_audioPlayer == nil) {
        XLAudioPlayer* player = [[XLAudioPlayer alloc] init];
        _audioPlayer = (__bridge_retained void*)player;
    }

    XLAudioPlayer* player = (__bridge XLAudioPlayer*)_audioPlayer;

    NSString* path = [NSString stringWithUTF8String:mediaPath.c_str()];
    if ([player loadAudioFile:path]) {
        // Apply current settings
        player.loopEnabled = _loopEnabled.load();
        player.playbackRate = (CGFloat)_playbackRate.load();
        player.volume = (CGFloat)_volume.load();

        // Update duration from audio file if not set
        {
            std::lock_guard<std::mutex> lock(_metadataMutex);
            if (_metadata.durationSeconds <= 0 && player.durationMS > 0) {
                _metadata.durationSeconds = player.durationMS / 1000.0;
                NSLog(@"NativeSequenceProvider: Got duration from audio: %.1f sec",
                      _metadata.durationSeconds);
            }
        }

        NSLog(@"NativeSequenceProvider: Loaded audio media: %@", path);
    } else {
        NSLog(@"NativeSequenceProvider: Failed to load audio media: %@", path);
    }
}

void NativeSequenceProvider::unloadAudioMedia()
{
    if (_audioPlayer != nil) {
        XLAudioPlayer* player = (__bridge_transfer XLAudioPlayer*)_audioPlayer;
        [player unload];
        _audioPlayer = nil;
    }
}

// MARK: - Private: Position Timer

void NativeSequenceProvider::startPositionTimer()
{
    stopPositionTimer();

    // Capture raw pointer for use in timer callback
    // Timer runs on main thread and we ensure provider outlives the timer
    NativeSequenceProvider* provider = this;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimer* timer = [NSTimer scheduledTimerWithTimeInterval:kPositionUpdateInterval
                                                         repeats:YES
                                                           block:^(NSTimer* t) {
            provider->onPositionTimerTick();
        }];

        provider->_positionTimer = (__bridge_retained void*)timer;
    });
}

void NativeSequenceProvider::stopPositionTimer()
{
    void* timerPtr = _positionTimer;
    if (timerPtr != nil) {
        _positionTimer = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSTimer* timer = (__bridge_transfer NSTimer*)timerPtr;
            [timer invalidate];
        });
    }
}

void NativeSequenceProvider::onPositionTimerTick()
{
    if (_playbackState.load() != PlaybackState::Playing) {
        return;
    }

    double position = getCurrentPosition();
    double duration = getSequenceDuration();

    // Check for end of sequence
    if (position >= duration) {
        if (_loopEnabled.load()) {
            seek(0.0);
            // Position will update on next tick
        } else {
            setPlaybackState(PlaybackState::Stopped);
        }
        return;
    }

    // Store current position
    _currentPosition.store(position);

    // Notify position change
    notifyPositionChanged(position);

    // Call frame tick callback
    {
        std::lock_guard<std::mutex> lock(_callbackMutex);
        if (_frameTickCallback) {
            _frameTickCallback(position);
        }
    }
}

void NativeSequenceProvider::syncAudioToPosition(double positionSeconds)
{
    XLAudioPlayer* player = (__bridge XLAudioPlayer*)_audioPlayer;
    if (player && player.isLoaded) {
        [player seekToPosition:(CGFloat)(positionSeconds * 1000.0)];
    }
}

double NativeSequenceProvider::getAudioPosition() const
{
    XLAudioPlayer* player = (__bridge XLAudioPlayer*)_audioPlayer;
    if (player && player.isLoaded) {
        return player.currentPositionMS / 1000.0;
    }
    return _currentPosition.load();
}

// MARK: - Private: Notification Helpers

void NativeSequenceProvider::notifyPlaybackStateChanged(PlaybackState state)
{
    dispatchToMainThread([this, state]() {
        std::lock_guard<std::mutex> lock(_listenerMutex);
        for (auto* listener : _listeners) {
            listener->onPlaybackStateChanged(state);
        }
    });
}

void NativeSequenceProvider::notifyPositionChanged(double positionSeconds)
{
    dispatchToMainThread([this, positionSeconds]() {
        std::lock_guard<std::mutex> lock(_listenerMutex);
        for (auto* listener : _listeners) {
            listener->onPlaybackPositionChanged(positionSeconds);
        }
    });
}

void NativeSequenceProvider::notifySequenceLoaded()
{
    dispatchToMainThread([this]() {
        std::lock_guard<std::mutex> lock(_listenerMutex);
        for (auto* listener : _listeners) {
            listener->onSequenceLoaded();
        }
    });
}

void NativeSequenceProvider::notifySequenceClosed()
{
    dispatchToMainThread([this]() {
        std::lock_guard<std::mutex> lock(_listenerMutex);
        for (auto* listener : _listeners) {
            listener->onSequenceClosed();
        }
    });
}

void NativeSequenceProvider::notifySequenceModified()
{
    dispatchToMainThread([this]() {
        std::lock_guard<std::mutex> lock(_listenerMutex);
        for (auto* listener : _listeners) {
            listener->onSequenceModified();
        }
    });
}

void NativeSequenceProvider::dispatchToMainThread(std::function<void()> block)
{
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            block();
        });
    }
}

} // namespace xlEngine
