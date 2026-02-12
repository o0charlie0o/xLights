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

#import <Cocoa/Cocoa.h>
#import "XLAudioLoader.h"

/// Data model for a single audio stem (vocals, drums, bass, etc.).
/// Holds the stem's metadata, file reference, and pre-computed waveform data.
@interface XLStemData : NSObject

/// Display name derived from filename (e.g., "Vocals", "Drums").
@property (nonatomic, copy) NSString *name;

/// Absolute path to the audio file.
@property (nonatomic, copy) NSString *filePath;

/// Path relative to the show folder, used for XML persistence.
@property (nonatomic, copy) NSString *relativePath;

/// Distinct color for this stem's waveform rendering.
@property (nonatomic, strong) NSColor *waveformColor;

/// Loaded PCM audio data (reuses existing XLAudioSampleData from XLAudioLoader).
@property (nonatomic, strong) XLAudioSampleData *audioData;

/// Pre-computed waveform overview buckets (NSArray of NSValue-wrapped XLWaveformBucket).
@property (nonatomic, strong) NSArray<NSValue *> *overviewBuckets;

/// Duration of the stem audio in milliseconds.
@property (nonatomic, assign) CGFloat durationMS;

/// Whether the stem is currently being loaded on a background thread.
@property (nonatomic, assign) BOOL isLoading;

@end
