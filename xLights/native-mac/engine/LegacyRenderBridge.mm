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

        // wxEntryStart (called inside CreateHeadless) replaces the NSApp
        // delegate with wxNSAppController. Save and restore ours.
        id savedDelegate = [[NSApplication sharedApplication] delegate];
        _frame = xLightsFrame::CreateHeadless();
        [[NSApplication sharedApplication] setDelegate:savedDelegate];
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
    if (!_frame || !_showLoaded || !path) {
        printf("[LRB-LOAD] BAIL: frame=%p showLoaded=%d path=%p\n", _frame, (int)_showLoaded, path);
        return NO;
    }

    std::string stdPath = [path UTF8String];
    printf("[LRB-LOAD] Loading sequence '%s'...\n", stdPath.c_str());

    @try {
        // Create xLightsXmlFile and open it
        wxString wxPath(stdPath);
        wxFileName wxFn(wxPath);
        xLightsXmlFile xmlFile(wxFn);

        wxString showDir(_showFolderPath);
        xmlFile.Open(showDir, true, wxFn); // showDir, ignore_audio, realFilename

        // Check if XML was parsed
        wxXmlDocument& doc = xmlFile.GetXmlDocument();
        wxXmlNode* root = doc.GetRoot();
        printf("[LRB-LOAD] XML root=%p", root);
        if (root) {
            printf(" name='%s'", (const char*)root->GetName().utf8_str());
            int childCount = 0;
            for (wxXmlNode* c = root->GetChildren(); c; c = c->GetNext()) {
                childCount++;
                if (childCount <= 8) printf(" child='%s'", (const char*)c->GetName().utf8_str());
            }
            printf(" totalChildren=%d", childCount);
        }
        printf("\n");

        // Get sequence timing info
        int frameTimeMS = xmlFile.GetFrameMS();
        if (frameTimeMS <= 0) frameTimeMS = 50;
        printf("[LRB-LOAD] frameTimeMS=%d\n", frameTimeMS);

        // If .xsq lacks DisplayElements (e.g., saved by native app in incomplete
        // format), synthesize one from ElementEffects so LoadSequencerFile can
        // create elements and then load effects into them.
        bool hasDisplayElements = false;
        wxXmlNode* elemEffectsNode = nullptr;
        for (wxXmlNode* c = root->GetChildren(); c; c = c->GetNext()) {
            if (c->GetName() == "DisplayElements") hasDisplayElements = true;
            if (c->GetName() == "ElementEffects") elemEffectsNode = c;
        }

        if (!hasDisplayElements && elemEffectsNode) {
            wxXmlNode* displayElements = new wxXmlNode(wxXML_ELEMENT_NODE, "DisplayElements");
            int deCount = 0;
            for (wxXmlNode* elemNode = elemEffectsNode->GetChildren(); elemNode; elemNode = elemNode->GetNext()) {
                if (elemNode->GetName() == "Element") {
                    wxString name = elemNode->GetAttribute("name");
                    wxString type = elemNode->GetAttribute("type", "model");
                    wxXmlNode* deNode = new wxXmlNode(wxXML_ELEMENT_NODE, "Element");
                    deNode->AddAttribute("name", name);
                    deNode->AddAttribute("type", type);
                    deNode->AddAttribute("visible", "1");
                    displayElements->AddChild(deNode);
                    deCount++;
                }
            }
            // Insert DisplayElements before the first child
            root->InsertChild(displayElements, root->GetChildren());
            printf("[LRB-LOAD] Synthesized DisplayElements with %d entries\n", deCount);
        } else if (hasDisplayElements) {
            printf("[LRB-LOAD] DisplayElements found in file\n");
        }

        // Load elements into SequenceElements
        SequenceElements& seqElems = _frame->GetSequenceElements();
        seqElems.Clear();
        seqElems.SetFrequency(1000 / frameTimeMS);
        seqElems.SetModelsNode(_frame->ModelsNode);

        printf("[LRB-LOAD] Calling LoadSequencerFile...\n");
        seqElems.LoadSequencerFile(xmlFile, showDir);

        int numElementsAfterLoad = seqElems.GetElementCount();
        printf("[LRB-LOAD] After LoadSequencerFile: elemCount=%d\n", numElementsAfterLoad);

        // Log first few elements
        for (int i = 0; i < numElementsAfterLoad && i < 5; i++) {
            Element* el = seqElems.GetElement(i);
            if (el) {
                printf("[LRB-LOAD] Element[%d]: name='%s' type=%d layers=%d\n",
                       i, el->GetName().c_str(), (int)el->GetType(),
                       el->GetEffectLayerCount());
            }
        }

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

        printf("[LRB-LOAD] Sequence loaded — %d elements, %u channels, %u frames @ %dms, duration=%.1fs\n",
               numElementsAfterLoad, totalChannels, numFrames, frameTimeMS, seqDurationMS / 1000.0);

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
    static int sDiagCount = 0;
    static int sDetailedDiagCount = 0;  // Counts actual renders for detailed diag
    // Reset counters on first call of a new session (detect via frame time jump)
    static int sLastFrameIdx = -1;
    bool diag = (sDiagCount < 20);  // Increased limit
    bool detailedDiag = (sDetailedDiagCount < 10);  // First 10 actual model renders

    if (!_frame || !_sequenceLoaded) {
        if (diag) printf("[LRB-DIAG] frame=%p sequenceLoaded=%d — BAIL\n", _frame, (int)_sequenceLoaded);
        return 0;
    }

    uint32_t numCh = _frame->_seqData.NumChannels();
    uint32_t frameTime = _frame->_seqData.FrameTime();
    if (frameTime == 0) frameTime = 50;
    int frameIndex = timeMS / (int)frameTime;
    if (frameIndex < 0) frameIndex = 0;
    if (frameIndex >= (int)_frame->_seqData.NumFrames()) {
        frameIndex = _frame->_seqData.NumFrames() - 1;
    }

    if (diag) printf("[LRB-DIAG] renderFrame(%dms): frameIdx=%d, numCh=%u, numFrames=%u, frameTime=%u\n",
                     timeMS, frameIndex, numCh, _frame->_seqData.NumFrames(), frameTime);

    // Zero the frame first
    _frame->_seqData[frameIndex].Zero();

    // Render each model that has effects at this time
    int modelsRendered = 0;
    int modelsWithEffects = 0;
    int initPixelBufferFails = 0;
    int totalEffectsRendered = 0;
    SequenceElements& seqElems = _frame->GetSequenceElements();
    int elemCount = seqElems.GetElementCount();

    if (diag) printf("[LRB-DIAG] elemCount=%d\n", elemCount);

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
        std::string firstEffectName;
        for (int layer = 0; layer < numLayers; layer++) {
            EffectLayer* elayer = me->GetEffectLayer(layer);
            if (!elayer) continue;
            for (int ei = 0; ei < elayer->GetEffectCount(); ei++) {
                Effect* eff = elayer->GetEffect(ei);
                if (eff && eff->GetStartTimeMS() <= timeMS && eff->GetEndTimeMS() > timeMS) {
                    hasEffect = true;
                    if (firstEffectName.empty()) firstEffectName = eff->GetEffectName();
                    break;
                }
            }
            if (hasEffect) break;
        }
        if (!hasEffect) continue;
        modelsWithEffects++;

        // Create PixelBuffer for this model
        PixelBufferClass buffer(_frame);
        if (!_frame->InitPixelBuffer(modelName, buffer, numLayers, false)) {
            initPixelBufferFails++;
            if (diag && initPixelBufferFails <= 3) {
                // Diagnose WHY it failed
                Model* dbgModel = _frame->GetModel(modelName);
                printf("[LRB-DIAG] InitPixelBuffer FAILED for '%s' (layers=%d): model=%p modelXml=%p displayAs='%s'\n",
                       modelName.c_str(), numLayers,
                       dbgModel,
                       dbgModel ? dbgModel->GetModelXml() : nullptr,
                       dbgModel ? dbgModel->GetDisplayAs().c_str() : "n/a");
            }
            continue;
        }

        // Render each layer
        std::vector<bool> validLayers(numLayers + 1, false);
        int layersRendered = 0;
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

                // [DIAG] Log buffer settings from effect (prefix stripped by CopySettingsMap)
                if (detailedDiag && layer == 0) {
                    std::string bufStyle = settingsMap.Get("CHOICE_BufferStyle", "?");
                    std::string bufTransform = settingsMap.Get("CHOICE_BufferTransform", "?");
                    std::string subBuf = settingsMap.Get("CUSTOM_SubBuffer", "");
                    printf("[LRB-DIAG] Effect settings: BufferStyle='%s' Transform='%s' SubBuffer='%s'\n",
                           bufStyle.c_str(), bufTransform.c_str(), subBuf.c_str());
                    // Also dump first few settings keys to see what's actually in there
                    int keyCount = 0;
                    for (auto it = settingsMap.begin(); it != settingsMap.end() && keyCount < 10; ++it, ++keyCount) {
                        printf("[LRB-DIAG]   setting[%d]: '%s' = '%s'\n", keyCount, it->first.c_str(), it->second.substr(0,40).c_str());
                    }
                }

                buffer.SetLayerSettings(layer, settingsMap, true);

                xlColorVector colors;
                xlColorCurveVector cc;
                eff->CopyPalette(colors, cc);
                buffer.SetPalette(layer, colors, cc);
                buffer.SetTimes(layer, eff->GetStartTimeMS(), eff->GetEndTimeMS());

                // [DIAG] Log palette colors
                if (detailedDiag && layer == 0) {
                    printf("[LRB-DIAG] Palette colors (%zu):", colors.size());
                    for (size_t ci = 0; ci < colors.size() && ci < 8; ci++) {
                        printf(" c%zu=(%d,%d,%d)", ci, colors[ci].red, colors[ci].green, colors[ci].blue);
                    }
                    printf("\n");
                }
            } else {
                SettingsMap empty;
                buffer.SetLayerSettings(layer, empty, false);
            }

            buffer.Clear(layer);

            // Render the effect
            if (eff) {
                bool resetState = true;

                // CRITICAL: Set curPeriod before rendering - effects use this for animation state
                buffer.SetLayer(layer, frameIndex, resetState);

                // [DIAG] Log effect details before rendering
                if (detailedDiag) {
                    RenderBuffer& diagRb = buffer.BufferForLayer(layer, -1);
                    printf("[LRB-DIAG] Rendering '%s' layer %d: effectIdx=%d effectName='%s' bufWi=%d bufHt=%d\n",
                           modelName.c_str(), layer, eff->GetEffectIndex(),
                           eff->GetEffectName().c_str(),
                           diagRb.BufferWi, diagRb.BufferHt);
                }

                SettingsMap settings;
                eff->CopySettingsMap(settings, true);

                // [DIAG] Check buffer state before render
                if (detailedDiag) {
                    RenderBuffer& preRb = buffer.BufferForLayer(layer, -1);
                    printf("[LRB-DIAG] Before RenderEffectFromMap: buffer.curPeriod=%d curEffStartPer=%d curEffEndPer=%d needToInit=%d\n",
                           preRb.curPeriod, preRb.curEffStartPer, preRb.curEffEndPer, (int)preRb.needToInit);
                }

                // Log first 3 effect renders unconditionally
                static int sEffectRenderCount = 0;
                bool logThisEffect = (sEffectRenderCount < 3);
                if (logThisEffect) {
                    RenderBuffer& rb = buffer.BufferForLayer(layer, -1);
                    size_t palSize = rb.GetPalette().Size();
                    printf("[LRB-EFFECT] Rendering effect '%s' (idx=%d) on '%s' layer %d, paletteSize=%zu:",
                           eff->GetEffectName().c_str(),
                           eff->GetEffectIndex(),
                           modelName.c_str(), layer, palSize);
                    for (size_t ci = 0; ci < palSize && ci < 4; ci++) {
                        xlColor c;
                        rb.palette.GetColor(ci, c);
                        printf(" c%zu=(%d,%d,%d)", ci, c.red, c.green, c.blue);
                    }
                    printf("\n");
                }

                bool renderResult = _frame->RenderEffectFromMap(false, eff, layer, frameIndex,
                                            settings, buffer, resetState, true, nullptr);

                if (logThisEffect) {
                    RenderBuffer& rb = buffer.BufferForLayer(layer, -1);
                    int nzPixels = 0;
                    for (int y = 0; y < rb.BufferHt && nzPixels == 0; y++) {
                        for (int x = 0; x < rb.BufferWi && nzPixels < 5; x++) {
                            const xlColor& c = rb.GetPixel(x, y);
                            if (c.red || c.green || c.blue) nzPixels++;
                        }
                    }
                    printf("[LRB-EFFECT] After render: result=%d, buffer=%dx%d, nonZeroPixels=%d\n",
                           renderResult, rb.BufferWi, rb.BufferHt, nzPixels);
                    sEffectRenderCount++;
                }

                if (detailedDiag) {
                    printf("[LRB-DIAG] RenderEffectFromMap returned %s\n", renderResult ? "true" : "false");
                }

                // [DIAG] Check if any pixels are non-zero in the render buffer after rendering
                if (detailedDiag) {
                    RenderBuffer& rb = buffer.BufferForLayer(layer, -1);
                    int nzPixels = 0;
                    int firstNzX = -1, firstNzY = -1;
                    for (int y = 0; y < rb.BufferHt; y++) {
                        for (int x = 0; x < rb.BufferWi; x++) {
                            const xlColor& c = rb.GetPixel(x, y);
                            if (c.red || c.green || c.blue) {
                                nzPixels++;
                                if (firstNzX < 0) { firstNzX = x; firstNzY = y; }
                            }
                        }
                    }
                    printf("[LRB-DIAG] After RenderEffectFromMap: rb=%dx%d nonZeroPixels=%d/%d firstNZ=(%d,%d)\n",
                           rb.BufferWi, rb.BufferHt, nzPixels, rb.BufferWi * rb.BufferHt, firstNzX, firstNzY);

                    // Check Node coordinates vs buffer size
                    const auto& nodes = rb.GetNodes();
                    int nodeCount = (int)nodes.size();
                    int nodesInBounds = 0;
                    int nodesOutOfBounds = 0;
                    for (int i = 0; i < nodeCount; i++) {
                        if (!nodes[i]->Coords.empty()) {
                            int bx = nodes[i]->Coords[0].bufX;
                            int by = nodes[i]->Coords[0].bufY;
                            if (bx >= 0 && bx < rb.BufferWi && by >= 0 && by < rb.BufferHt) {
                                nodesInBounds++;
                            } else {
                                nodesOutOfBounds++;
                            }
                        }
                    }
                    printf("[LRB-DIAG] Nodes: total=%d inBounds=%d outOfBounds=%d\n",
                           nodeCount, nodesInBounds, nodesOutOfBounds);
                    // Show first 3 node coords
                    for (int i = 0; i < std::min(3, nodeCount); i++) {
                        if (!nodes[i]->Coords.empty()) {
                            printf("[LRB-DIAG]   Node[%d] bufCoord=(%d,%d)\n",
                                   i, nodes[i]->Coords[0].bufX, nodes[i]->Coords[0].bufY);
                        }
                    }
                }

                validLayers[layer] = true;
                layersRendered++;
                totalEffectsRendered++;
            }
        }

        // Blend layers and write to channel data
        buffer.CalcOutput(frameIndex, validLayers);

        // [DIAG] Check Node colors after CalcOutput, before GetColors
        if (detailedDiag) {
            RenderBuffer& rb0 = buffer.BufferForLayer(0, -1);
            const auto& nodes = rb0.GetNodes();
            int nodeCount = (int)nodes.size();
            int nzNodes = 0;
            for (int i = 0; i < nodeCount && i < 100; i++) {
                xlColor nc;
                nodes[i]->GetColor(nc);
                if (nc.red || nc.green || nc.blue) nzNodes++;
            }
            printf("[LRB-DIAG] After CalcOutput: nodeCount=%d, nonZeroNodes(first100)=%d\n",
                   nodeCount, nzNodes);
            // Check first few nodes' ActChan
            for (int i = 0; i < std::min(5, nodeCount); i++) {
                xlColor nc;
                nodes[i]->GetColor(nc);
                printf("[LRB-DIAG]   Node[%d]: ActChan=%lu, color=(%d,%d,%d)\n",
                       i, (unsigned long)nodes[i]->ActChan, nc.red, nc.green, nc.blue);
            }
        }

        std::vector<bool> rangeRestriction; // empty = no restriction
        buffer.GetColors(&(_frame->_seqData[frameIndex][0]), rangeRestriction);

        // [DIAG] Check if this model wrote non-zero data
        if (detailedDiag) {
            Model* model = _frame->AllModels[modelName];
            uint32_t startCh = model ? model->GetFirstChannel() : 0;
            uint32_t endCh = model ? (model->GetLastChannel() + 1) : 0;
            uint32_t nz = 0;
            for (uint32_t ch = startCh; ch < endCh && ch < numCh; ch++) {
                if (_frame->_seqData[frameIndex][ch] != 0) nz++;
            }
            printf("[LRB-DIAG] Model '%s': effect='%s', layers=%d/%d, startCh=%u, endCh=%u, nonZeroCh=%u\n",
                   modelName.c_str(), firstEffectName.c_str(), layersRendered, numLayers,
                   startCh, endCh, nz);
            sDetailedDiagCount++;  // Count this render for limiting detailed diagnostics
        }

        modelsRendered++;
    }

    if (diag) {
        // Check total non-zero channels in the frame
        uint32_t totalNZ = 0;
        for (uint32_t i = 0; i < numCh; i++) {
            if (_frame->_seqData[frameIndex][i] != 0) totalNZ++;
        }
        printf("[LRB-DIAG] SUMMARY: modelsWithEffects=%d, rendered=%d, initFails=%d, effectsRendered=%d, totalNonZeroCh=%u/%u\n",
               modelsWithEffects, modelsRendered, initPixelBufferFails, totalEffectsRendered, totalNZ, numCh);
    }

    // Copy result to output
    _frameChannelBuffer.resize(numCh);
    std::memcpy(_frameChannelBuffer.data(), &(_frame->_seqData[frameIndex][0]), numCh);

    if (outBuffer) *outBuffer = _frameChannelBuffer.data();
    if (outNumChannels) *outNumChannels = numCh;

    sDiagCount++;
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
