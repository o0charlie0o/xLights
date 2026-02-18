/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 **************************************************************/

#import "LegacyRenderBridge.h"

// wx headers needed for legacy rendering
#include <wx/xml/xml.h>
#include <wx/filename.h>

// xLights core headers — NOT compiled with XLIGHTS_NATIVE
#include "../../xLightsMain.h"
#include "../../xLightsApp.h"
#include "../../PixelBuffer.h"
#include "../../RenderBuffer.h"
#include "../../SequenceData.h"
#include "../../xLightsXmlFile.h"
#include "../../sequencer/SequenceElements.h"
#include "../../sequencer/Element.h"
#include "../../sequencer/Effect.h"
#include "../../sequencer/EffectLayer.h"
#include "../../models/Model.h"
#include "../../models/ModelGroup.h"
#include "../../models/ModelManager.h"

#include <atomic>
#include <cstring>
#include <vector>

@implementation LegacyRenderBridge {
    xLightsFrame* _frame;
    BOOL _showLoaded;
    BOOL _sequenceLoaded;
    std::string _showFolderPath;

    // Per-frame render cache (reusable across renderFrameAtTimeMS calls)
    std::vector<uint8_t> _frameChannelBuffer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _showLoaded = NO;
        _sequenceLoaded = NO;
        _frame = xLightsFrame::CreateHeadless();
        if (_frame) {
            NSLog(@"LegacyRenderBridge: Headless xLightsFrame created (%zu effects)",
                  _frame->GetEffectManager().size());
        } else {
            NSLog(@"LegacyRenderBridge: ERROR - Failed to create headless xLightsFrame");
        }
    }
    return self;
}

- (BOOL)loadShowFolder:(NSString *)path {
    if (!_frame || !path) return NO;

    _showFolderPath = [path UTF8String];
    bool ok = _frame->InitHeadless(_showFolderPath);
    _showLoaded = ok ? YES : NO;

    if (ok) {
        NSLog(@"LegacyRenderBridge: Show loaded from '%@' — %zu models",
              path, _frame->AllModels.size());
    } else {
        NSLog(@"LegacyRenderBridge: Failed to load show from '%@'", path);
    }
    return _showLoaded;
}

- (BOOL)loadSequence:(NSString *)path {
    if (!_frame || !_showLoaded || !path) return NO;

    std::string stdPath = [path UTF8String];
    NSLog(@"LegacyRenderBridge: Loading sequence '%@'...", path);

    @try {
        // Create xLightsXmlFile and open it
        wxString wxPath(stdPath);
        wxFileName wxFn(wxPath);
        xLightsXmlFile xmlFile(wxFn);

        wxString showDir(_showFolderPath);
        xmlFile.Open(showDir, true, wxFn); // showDir, ignore_audio, realFilename

        // Get sequence timing info
        int frameTimeMS = xmlFile.GetFrameMS();
        if (frameTimeMS <= 0) frameTimeMS = 50;

        // Load elements into SequenceElements
        SequenceElements& seqElems = _frame->GetSequenceElements();
        seqElems.Clear();
        seqElems.SetFrequency(1000 / frameTimeMS);
        seqElems.SetViewsManager(nullptr); // no views in headless mode
        seqElems.LoadSequencerFile(xmlFile, showDir);

        // Calculate total channels needed
        uint32_t totalChannels = 0;
        for (auto it = _frame->AllModels.begin(); it != _frame->AllModels.end(); ++it) {
            Model* m = it->second;
            if (m) {
                uint32_t end = m->GetLastChannel() + 1;
                if (end > totalChannels) totalChannels = end;
            }
        }
        if (totalChannels == 0) totalChannels = 1; // avoid zero-size alloc

        // Calculate number of frames
        double seqDurationMS = xmlFile.GetSequenceDurationMS();
        if (seqDurationMS <= 0) seqDurationMS = 30000; // default 30s
        uint32_t numFrames = (uint32_t)(seqDurationMS / frameTimeMS);
        if (numFrames == 0) numFrames = 1;

        // Init SequenceData
        _frame->_seqData.init(totalChannels, numFrames, frameTimeMS);

        // Store the xml file as current
        xLightsFrame::CurrentSeqXmlFile = new xLightsXmlFile(wxFn);
        xLightsFrame::CurrentSeqXmlFile->Open(showDir, true, wxFn);

        _sequenceLoaded = YES;

        int numElements = seqElems.GetElementCount();
        NSLog(@"LegacyRenderBridge: Sequence loaded — %d elements, %u channels, "
              @"%u frames @ %dms, duration=%.1fs",
              numElements, totalChannels, numFrames, frameTimeMS,
              seqDurationMS / 1000.0);

        return YES;
    } @catch (NSException *exception) {
        NSLog(@"LegacyRenderBridge: Exception loading sequence: %@ - %@",
              exception.name, exception.reason);
        _sequenceLoaded = NO;
        return NO;
    }
}

- (uint32_t)renderFrameAtTimeMS:(int)timeMS
                     bufferOut:(const uint8_t **)outBuffer
                     numChannels:(uint32_t *)outNumChannels {
    if (!_frame || !_sequenceLoaded) return 0;

    uint32_t numCh = _frame->_seqData.NumChannels();
    uint32_t frameTime = _frame->_seqData.FrameTime();
    if (frameTime == 0) frameTime = 50;
    int frameIndex = timeMS / (int)frameTime;
    if (frameIndex < 0) frameIndex = 0;
    if (frameIndex >= (int)_frame->_seqData.NumFrames()) {
        frameIndex = _frame->_seqData.NumFrames() - 1;
    }

    // Zero the frame first
    _frame->_seqData[frameIndex].Zero();

    // Render each model that has effects at this time
    int modelsRendered = 0;
    SequenceElements& seqElems = _frame->GetSequenceElements();
    int elemCount = seqElems.GetElementCount();

    for (int e = 0; e < elemCount; e++) {
        Element* elem = seqElems.GetElement(e);
        if (!elem || elem->GetType() != ElementType::ELEMENT_TYPE_MODEL) continue;

        ModelElement* me = dynamic_cast<ModelElement*>(elem);
        if (!me) continue;

        std::string modelName = me->GetModelName();
        int numLayers = me->GetEffectLayerCount();
        if (numLayers == 0) continue;

        // Check if any layer has an effect at this time
        bool hasEffect = false;
        for (int layer = 0; layer < numLayers; layer++) {
            EffectLayer* elayer = me->GetEffectLayer(layer);
            if (!elayer) continue;
            for (int ei = 0; ei < elayer->GetEffectCount(); ei++) {
                Effect* eff = elayer->GetEffect(ei);
                if (eff && eff->GetStartTimeMS() <= timeMS && eff->GetEndTimeMS() > timeMS) {
                    hasEffect = true;
                    break;
                }
            }
            if (hasEffect) break;
        }
        if (!hasEffect) continue;

        // Create PixelBuffer for this model
        PixelBufferClass buffer(_frame);
        if (!_frame->InitPixelBuffer(modelName, buffer, numLayers, false)) {
            continue;
        }

        // Render each layer
        std::vector<bool> validLayers(numLayers + 1, false);
        for (int layer = numLayers - 1; layer >= 0; --layer) {
            EffectLayer* elayer = me->GetEffectLayer(layer);
            if (!elayer) continue;

            // Find effect at this time
            Effect* eff = nullptr;
            for (int ei = 0; ei < elayer->GetEffectCount(); ei++) {
                Effect* e = elayer->GetEffect(ei);
                if (e && e->GetStartTimeMS() <= timeMS && e->GetEndTimeMS() > timeMS) {
                    eff = e;
                    break;
                }
            }

            // Initialize layer settings from effect
            if (eff && eff->GetEffectIndex() >= 0) {
                SettingsMap settingsMap;
                eff->CopySettingsMap(settingsMap, true);
                buffer.SetLayerSettings(layer, settingsMap, true);

                xlColorVector colors;
                xlColorCurveVector cc;
                eff->CopyPalette(colors, cc);
                buffer.SetPalette(layer, colors, cc);
                buffer.SetTimes(layer, eff->GetStartTimeMS(), eff->GetEndTimeMS());
            } else {
                SettingsMap empty;
                buffer.SetLayerSettings(layer, empty, false);
            }

            buffer.Clear(layer);

            // Render the effect
            if (eff) {
                bool resetState = true;
                SettingsMap settings;
                eff->CopySettingsMap(settings, true);
                _frame->RenderEffectFromMap(false, eff, layer, frameIndex,
                                            settings, buffer, resetState, true, nullptr);
                validLayers[layer] = true;
            }
        }

        // Blend layers and write to channel data
        buffer.CalcOutput(frameIndex, validLayers);
        std::vector<bool> rangeRestriction; // empty = no restriction
        buffer.GetColors(&(_frame->_seqData[frameIndex][0]), rangeRestriction);

        modelsRendered++;
    }

    // Copy result to output
    _frameChannelBuffer.resize(numCh);
    std::memcpy(_frameChannelBuffer.data(), &(_frame->_seqData[frameIndex][0]), numCh);

    if (outBuffer) *outBuffer = _frameChannelBuffer.data();
    if (outNumChannels) *outNumChannels = numCh;

    return numCh;
}

- (BOOL)renderAll {
    if (!_frame || !_sequenceLoaded) return NO;

    NSLog(@"LegacyRenderBridge: Starting batch render of %u frames...",
          _frame->_seqData.NumFrames());

    uint32_t numFrames = _frame->_seqData.NumFrames();
    uint32_t frameTime = _frame->_seqData.FrameTime();
    int framesRendered = 0;

    for (uint32_t fi = 0; fi < numFrames; fi++) {
        int timeMS = fi * frameTime;
        const uint8_t* buf = nullptr;
        uint32_t numCh = 0;
        [self renderFrameAtTimeMS:timeMS bufferOut:&buf numChannels:&numCh];
        framesRendered++;

        if (fi % 100 == 0) {
            printf("[LegacyRenderBridge] Rendered frame %u/%u (%.1f%%)\n",
                   fi, numFrames, 100.0f * fi / numFrames);
        }
    }

    NSLog(@"LegacyRenderBridge: Batch render complete — %d frames rendered", framesRendered);
    return YES;
}

- (const uint8_t *)channelDataForFrame:(uint32_t)frameIndex
                           numChannels:(uint32_t *)outNumChannels {
    if (!_frame || !_sequenceLoaded) return nullptr;
    if (frameIndex >= _frame->_seqData.NumFrames()) return nullptr;

    uint32_t numCh = _frame->_seqData.NumChannels();
    if (outNumChannels) *outNumChannels = numCh;
    return &(_frame->_seqData[frameIndex][0]);
}

- (uint32_t)numFrames {
    if (!_frame || !_sequenceLoaded) return 0;
    return _frame->_seqData.NumFrames();
}

- (uint32_t)numChannels {
    if (!_frame || !_sequenceLoaded) return 0;
    return _frame->_seqData.NumChannels();
}

- (uint32_t)frameTimeMS {
    if (!_frame || !_sequenceLoaded) return 50;
    return _frame->_seqData.FrameTime();
}

- (xLightsFrame *)frame {
    return _frame;
}

- (BOOL)isShowLoaded {
    return _showLoaded;
}

- (BOOL)isSequenceLoaded {
    return _sequenceLoaded;
}

@end
