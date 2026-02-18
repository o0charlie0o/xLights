/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 **************************************************************/

#pragma once

// LegacyRenderBridge: Routes rendering through the proven legacy
// PixelBuffer/RenderJob pipeline instead of NativeRenderCoordinator.
//
// Architecture:
//   XLEngineBridge → LegacyRenderBridge → xLightsFrame (headless)
//                                          ├─ ModelManager (AllModels)
//                                          ├─ SequenceElements
//                                          ├─ EffectManager
//                                          ├─ PixelBufferClass
//                                          └─ _seqData (output)
//
// The bridge creates a headless xLightsFrame, loads models and sequences
// through the legacy XML parsing, and renders frames synchronously via
// the proven RenderEffectFromMap / CalcOutput / GetColors pipeline.

#import <Foundation/Foundation.h>

class xLightsFrame;

@interface LegacyRenderBridge : NSObject

// Initialize: creates headless xLightsFrame
- (instancetype)init;

// Load show folder: models, outputs, start channels
- (BOOL)loadShowFolder:(NSString *)path;

// Load sequence: parses XML into SequenceElements
- (BOOL)loadSequence:(NSString *)path;

// Render a single frame synchronously into the channel buffer.
// Returns the number of channels written. The buffer is owned by
// the bridge (lives as long as the bridge or until a new sequence is loaded).
- (uint32_t)renderFrameAtTimeMS:(int)timeMS
                     bufferOut:(const uint8_t **)outBuffer
                     numChannels:(uint32_t *)outNumChannels;

// Render all frames (batch). Populates _seqData for all frames.
// This uses the legacy RenderGridToSeqData pipeline.
- (BOOL)renderAll;

// Access raw channel data for a rendered frame.
// Returns nullptr if frame hasn't been rendered.
- (const uint8_t *)channelDataForFrame:(uint32_t)frameIndex
                           numChannels:(uint32_t *)outNumChannels;

// Query sequence info
- (uint32_t)numFrames;
- (uint32_t)numChannels;
- (uint32_t)frameTimeMS;

// Access the headless xLightsFrame
- (xLightsFrame *)frame;

// Check if show/sequence are loaded
- (BOOL)isShowLoaded;
- (BOOL)isSequenceLoaded;

@end
