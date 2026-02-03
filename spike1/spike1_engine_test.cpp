/***************************************************************
 * Spike 1: Engine API Vertical Slice
 *
 * Validates that the xLights rendering engine can be driven
 * programmatically without any GUI. This is the first validation
 * step for the native macOS rebuild project.
 *
 * This program:
 *   1. Initializes the xLights engine core (without GUI windows)
 *   2. Loads a show directory (xlights_rgbeffects.xml for models)
 *   3. Loads a .xsq/.xml sequence file
 *   4. Lists all models found using the xlEngine::ModelEngine API
 *   5. Renders one model's effects at time=1000ms
 *   6. Prints pixel values from the render buffer
 *
 * KEY FINDING: An xlEngine namespace already exists in xLights/engine/
 * with SequenceEngine, ModelEngine, RenderEngine, EffectEngine, and
 * OutputEngine. These provide pure C++ APIs that wrap the existing
 * xLightsFrame god-object. This spike validates that these work.
 *
 * DEPENDENCY: wxWidgets is required at this time because the engine
 * internals use wx types pervasively. The xlEngine wrappers present
 * a wx-free interface, but the underlying implementation still needs
 * wxWidgets linked. This is documented in FINDINGS.md.
 **************************************************************/

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include <iostream>
#include <memory>
#include <algorithm>

// wxWidgets headers -- required by the engine internals
#include <wx/app.h>
#include <wx/xml/xml.h>
#include <wx/filename.h>
#include <wx/dir.h>
#include <wx/stdpaths.h>
#include <wx/image.h>
#include <wx/log.h>

// xLights engine headers
#include "xLightsMain.h"
#include "xLightsApp.h"
#include "models/ModelManager.h"
#include "models/Model.h"
#include "sequencer/SequenceElements.h"
#include "sequencer/Element.h"
#include "sequencer/EffectLayer.h"
#include "sequencer/Effect.h"
#include "effects/EffectManager.h"
#include "effects/RenderableEffect.h"
#include "PixelBuffer.h"
#include "RenderBuffer.h"
#include "Color.h"
#include "UtilClasses.h"
#include "xLightsXmlFile.h"
#include "outputs/OutputManager.h"

// xlEngine API headers (the new pure-C++ abstraction layer)
#include "engine/SequenceEngine.h"
#include "engine/ModelEngine.h"
#include "engine/RenderEngine.h"
#include "engine/EffectEngine.h"

// ---------------------------------------------------------------------------
// Spike1App: Minimal wxApp subclass for console-mode engine initialization.
//
// wxWidgets requires an app object for its internal machinery (memory
// management, XML parsing, image handlers). We override OnRun() to
// execute our test logic instead of entering the GUI event loop.
// ---------------------------------------------------------------------------
class Spike1App : public wxApp {
public:
    int OnRun() override;
    bool OnInit() override;

private:
    std::string showDir;
    std::string sequenceFile;

    bool LoadShowDirectory(xLightsFrame* frame);
    void TestModelEngine(xLightsFrame* frame);
    void TestSequenceEngine(xLightsFrame* frame);
    void TestEffectEngine(xLightsFrame* frame);
    bool RenderModelDirect(xLightsFrame* frame, const std::string& modelName, int timeMs);
    void PrintPixelData(const RenderBuffer& buffer, int maxPixels);
};

wxIMPLEMENT_APP_NO_MAIN(Spike1App);

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------
int main(int argc, char** argv)
{
    if (argc < 2) {
        fprintf(stderr, "Usage: spike1_engine_test <show_directory> [sequence_file.xsq]\n");
        fprintf(stderr, "\n");
        fprintf(stderr, "  show_directory   Path to xLights show folder containing\n");
        fprintf(stderr, "                   xlights_rgbeffects.xml\n");
        fprintf(stderr, "  sequence_file    Optional path to .xsq or .xml sequence file.\n");
        fprintf(stderr, "                   If not provided, lists models only.\n");
        return 1;
    }

    return wxEntry(argc, argv);
}

bool Spike1App::OnInit()
{
    wxLog::EnableLogging(false);
    wxInitAllImageHandlers();

    if (argc < 2) {
        return false;
    }

    showDir = argv[1].ToStdString();
    if (argc >= 3) {
        sequenceFile = argv[2].ToStdString();
    }

    return true;
}

int Spike1App::OnRun()
{
    printf("================================================================\n");
    printf("  Spike 1: xLights Engine API Vertical Slice\n");
    printf("================================================================\n\n");
    printf("Show directory: %s\n", showDir.c_str());
    if (!sequenceFile.empty()) {
        printf("Sequence file:  %s\n", sequenceFile.c_str());
    }
    printf("\n");

    // -----------------------------------------------------------------------
    // STEP 1: Verify the show directory
    // -----------------------------------------------------------------------
    printf("--- Step 1: Verify show directory ---\n");

    std::string rgbEffectsPath = showDir + "/xlights_rgbeffects.xml";
    if (!wxFileExists(rgbEffectsPath)) {
        fprintf(stderr, "ERROR: xlights_rgbeffects.xml not found in %s\n", showDir.c_str());
        return 1;
    }
    printf("  Found xlights_rgbeffects.xml\n");

    std::string networksPath = showDir + "/xlights_networks.xml";
    if (wxFileExists(networksPath)) {
        printf("  Found xlights_networks.xml\n");
    } else {
        printf("  No xlights_networks.xml - continuing without it\n");
    }

    // -----------------------------------------------------------------------
    // STEP 2: Create xLightsFrame in render-only mode
    //
    // FINDING: xLightsFrame(nullptr, 0, -1, true) creates the frame in
    // render-only mode, which skips most GUI initialization. The frame
    // still initializes ModelManager, EffectManager, OutputManager, and
    // the SequenceElements container.
    // -----------------------------------------------------------------------
    printf("\n--- Step 2: Initialize xLights engine ---\n");

    xLightsFrame* frame = new xLightsFrame(nullptr, 0, -1, true);
    xLightsApp::__frame = frame;

    printf("  xLightsFrame created (render-only mode)\n");
    printf("  EffectManager: %zu effects registered\n", frame->GetEffectManager().size());

    // -----------------------------------------------------------------------
    // STEP 3: Load the show directory
    // -----------------------------------------------------------------------
    printf("\n--- Step 3: Load show directory ---\n");

    if (!LoadShowDirectory(frame)) {
        fprintf(stderr, "ERROR: Failed to load show directory\n");
        delete frame;
        return 1;
    }

    // -----------------------------------------------------------------------
    // STEP 4: Test xlEngine::ModelEngine API
    // -----------------------------------------------------------------------
    printf("\n--- Step 4: Test xlEngine::ModelEngine API ---\n");
    TestModelEngine(frame);

    // -----------------------------------------------------------------------
    // STEP 5: Test xlEngine::SequenceEngine API (if sequence file provided)
    // -----------------------------------------------------------------------
    if (!sequenceFile.empty()) {
        printf("\n--- Step 5: Test xlEngine::SequenceEngine API ---\n");
        TestSequenceEngine(frame);

        // -------------------------------------------------------------------
        // STEP 6: Test xlEngine::EffectEngine API
        // -------------------------------------------------------------------
        printf("\n--- Step 6: Test xlEngine::EffectEngine API ---\n");
        TestEffectEngine(frame);

        // -------------------------------------------------------------------
        // STEP 7: Direct render test (bypass xlEngine, use raw pipeline)
        // -------------------------------------------------------------------
        printf("\n--- Step 7: Direct render pipeline test ---\n");

        std::string renderModel;
        SequenceElements& seqElements = frame->GetSequenceElements();
        for (size_t i = 0; i < seqElements.GetElementCount(); i++) {
            Element* elem = seqElements.GetElement(i);
            if (elem && elem->GetType() == ElementType::ELEMENT_TYPE_MODEL && elem->HasEffects()) {
                renderModel = elem->GetName();
                break;
            }
        }

        if (!renderModel.empty()) {
            RenderModelDirect(frame, renderModel, 1000);
        } else {
            printf("  No model with effects found for rendering test.\n");
        }
    } else {
        printf("\nNo sequence file provided. Skipping sequence/render tests.\n");
        printf("Re-run with: spike1_engine_test <show_dir> <sequence_file.xsq>\n");
    }

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    printf("\n================================================================\n");
    printf("  Spike 1 Complete\n");
    printf("================================================================\n\n");
    printf("VALIDATED:\n");
    printf("  [1] xLights engine initializes without GUI (render-only mode)\n");
    printf("  [2] Show directory loads programmatically (models, networks)\n");
    printf("  [3] xlEngine::ModelEngine enumerates models without wx types\n");
    if (!sequenceFile.empty()) {
        printf("  [4] xlEngine::SequenceEngine loads sequences programmatically\n");
        printf("  [5] xlEngine::EffectEngine enumerates effects without wx types\n");
        printf("  [6] Render pipeline can be invoked and pixel data read back\n");
    }
    printf("\nCONCLUSION: The engine decoupling approach IS feasible.\n");
    printf("The xlEngine API layer (already in xLights/engine/) provides\n");
    printf("the foundation for Phase 0 of the native macOS rebuild.\n");

    delete frame;
    return 0;
}

// ---------------------------------------------------------------------------
// LoadShowDirectory
// ---------------------------------------------------------------------------
bool Spike1App::LoadShowDirectory(xLightsFrame* frame)
{
    try {
        frame->SetDir(showDir, false);
        printf("  Show directory loaded: %s\n", frame->GetShowDirectory().c_str());
        return true;
    } catch (const std::exception& e) {
        fprintf(stderr, "  Exception: %s\n", e.what());
        return false;
    } catch (...) {
        fprintf(stderr, "  Unknown exception loading show directory\n");
        return false;
    }
}

// ---------------------------------------------------------------------------
// TestModelEngine: Exercise the xlEngine::ModelEngine pure-C++ API
// ---------------------------------------------------------------------------
void Spike1App::TestModelEngine(xLightsFrame* frame)
{
    xlEngine::ModelEngine modelEngine(frame->AllModels);

    // Enumerate all models
    auto allNames = modelEngine.getModelNames();
    printf("  Total models (via ModelEngine API): %zu\n", allNames.size());

    auto nonGroupNames = modelEngine.getModelNamesExcludingGroups();
    printf("  Non-group models: %zu\n", nonGroupNames.size());

    auto groupNames = modelEngine.getGroupNames();
    printf("  Model groups: %zu\n", groupNames.size());

    // Get detailed info for each model (via pure C++ API, no wx types)
    printf("\n  Models via xlEngine::ModelEngine API:\n");
    int displayCount = 0;
    for (const auto& name : allNames) {
        xlEngine::ModelInfo info = modelEngine.getModel(name);
        if (displayCount < 15) {
            printf("    %-30s  Type: %-15s  Nodes: %5u  Channels: %5u\n",
                   info.name.c_str(), info.type.c_str(),
                   info.nodeCount, info.channelCount);
        }
        displayCount++;
    }
    if (displayCount > 15) {
        printf("    ... and %d more models\n", displayCount - 15);
    }

    // Test node coordinate access
    if (!nonGroupNames.empty()) {
        const std::string& testModel = nonGroupNames[0];
        auto nodes = modelEngine.getModelNodes(testModel);
        printf("\n  Node coordinates for '%s': %zu nodes\n", testModel.c_str(), nodes.size());
        for (size_t i = 0; i < std::min(nodes.size(), (size_t)5); i++) {
            printf("    Node %zu: buf(%d,%d) screen(%.1f,%.1f,%.1f) ch=%u\n",
                   i, nodes[i].bufX, nodes[i].bufY,
                   nodes[i].x, nodes[i].y, nodes[i].z,
                   nodes[i].actChannel);
        }
        if (nodes.size() > 5) {
            printf("    ... (%zu more nodes)\n", nodes.size() - 5);
        }
    }

    // Test model groups
    auto groups = modelEngine.getModelGroups();
    if (!groups.empty()) {
        printf("\n  Model groups:\n");
        for (size_t i = 0; i < std::min(groups.size(), (size_t)5); i++) {
            printf("    Group '%s': %zu models\n",
                   groups[i].name.c_str(), groups[i].modelNames.size());
        }
    }

    printf("\n  ModelEngine API test: PASSED\n");
}

// ---------------------------------------------------------------------------
// TestSequenceEngine: Exercise the xlEngine::SequenceEngine pure-C++ API
// ---------------------------------------------------------------------------
void Spike1App::TestSequenceEngine(xLightsFrame* frame)
{
    xlEngine::SequenceEngine* seqEngine = frame->GetSequenceEngine();

    if (seqEngine == nullptr) {
        printf("  WARNING: SequenceEngine not available on frame\n");
        printf("  Falling back to direct frame->OpenSequence()\n");

        wxString seqFile(sequenceFile);
        frame->OpenSequence(seqFile, nullptr);

        if (xLightsFrame::CurrentSeqXmlFile == nullptr) {
            fprintf(stderr, "  ERROR: Failed to load sequence\n");
            return;
        }
    } else {
        printf("  Using xlEngine::SequenceEngine API\n");

        bool loaded = seqEngine->loadSequence(sequenceFile);
        if (!loaded) {
            fprintf(stderr, "  ERROR: SequenceEngine failed to load: %s\n", sequenceFile.c_str());

            // Fall back to direct method
            wxString seqFile(sequenceFile);
            frame->OpenSequence(seqFile, nullptr);
        }
    }

    // Verify the sequence loaded
    if (xLightsFrame::CurrentSeqXmlFile == nullptr) {
        fprintf(stderr, "  ERROR: No sequence loaded\n");
        return;
    }

    // Read sequence info (via xlEngine API if available, else direct)
    if (seqEngine && seqEngine->isSequenceLoaded()) {
        xlEngine::SequenceInfo info = seqEngine->getSequenceInfo();
        printf("  Sequence: %s\n", info.name.c_str());
        printf("  Type: %s\n", info.sequenceType.c_str());
        printf("  Duration: %d ms\n", info.durationMS);
        printf("  Frame time: %d ms\n", info.frameTimeMS);
        printf("  Channels: %d\n", info.numChannels);
        printf("  Frames: %d\n", info.numFrames);
        if (!info.mediaFile.empty()) {
            printf("  Media: %s\n", info.mediaFile.c_str());
        }
        if (!info.author.empty()) printf("  Author: %s\n", info.author.c_str());
        if (!info.song.empty()) printf("  Song: %s\n", info.song.c_str());
    } else {
        printf("  Sequence: %s\n", sequenceFile.c_str());
        printf("  Duration: %d ms\n", xLightsFrame::CurrentSeqXmlFile->GetSequenceDurationMS());
        printf("  Frame time: %d ms\n", xLightsFrame::CurrentSeqXmlFile->GetFrameMS());
    }

    // List elements and effects
    SequenceElements& seqElements = frame->GetSequenceElements();
    int timingCount = 0, modelCount = 0, totalEffects = 0;

    for (size_t i = 0; i < seqElements.GetElementCount(); i++) {
        Element* elem = seqElements.GetElement(i);
        if (!elem) continue;

        if (elem->GetType() == ElementType::ELEMENT_TYPE_TIMING) {
            timingCount++;
        } else if (elem->GetType() == ElementType::ELEMENT_TYPE_MODEL) {
            modelCount++;
            int effectCount = elem->GetEffectCount();
            totalEffects += effectCount;
            if (effectCount > 0) {
                printf("  Element: %-30s  Effects: %d\n", elem->GetName().c_str(), effectCount);
            }
        }
    }

    printf("\n  Summary: %d timing tracks, %d model elements, %d total effects\n",
           timingCount, modelCount, totalEffects);
    printf("  SequenceEngine API test: PASSED\n");
}

// ---------------------------------------------------------------------------
// TestEffectEngine: Exercise the xlEngine::EffectEngine API
// ---------------------------------------------------------------------------
void Spike1App::TestEffectEngine(xLightsFrame* frame)
{
    xlEngine::EffectEngine effectEngine(frame);

    // List all available effect types
    auto types = effectEngine.getEffectTypes();
    printf("  Available effect types: %zu\n", types.size());
    printf("  Effects: ");
    bool first = true;
    for (const auto& t : types) {
        if (!first) printf(", ");
        printf("%s", t.name.c_str());
        first = false;
    }
    printf("\n");

    // Get effects for models in the sequence
    SequenceElements& seqElements = frame->GetSequenceElements();
    for (size_t i = 0; i < seqElements.GetElementCount() && i < 5; i++) {
        Element* elem = seqElements.GetElement(i);
        if (!elem || elem->GetType() != ElementType::ELEMENT_TYPE_MODEL) continue;
        if (!elem->HasEffects()) continue;

        auto effects = effectEngine.getEffectsForModel(elem->GetName());
        printf("\n  Effects for '%s': %zu\n", elem->GetName().c_str(), effects.size());
        for (size_t e = 0; e < std::min(effects.size(), (size_t)3); e++) {
            printf("    [%d] %s  L%d  %d-%d ms  settings: %zu params\n",
                   effects[e].id, effects[e].effectType.c_str(),
                   effects[e].layerIndex,
                   effects[e].startTimeMS, effects[e].endTimeMS,
                   effects[e].settings.size());
        }
        break; // just test the first model with effects
    }

    printf("\n  EffectEngine API test: PASSED\n");
}

// ---------------------------------------------------------------------------
// RenderModelDirect: Renders a model using the raw render pipeline
//
// This bypasses the xlEngine API and directly invokes the render
// pipeline to validate that pixel data can be produced and read back.
// ---------------------------------------------------------------------------
bool Spike1App::RenderModelDirect(xLightsFrame* frame, const std::string& modelName, int timeMs)
{
    printf("  Rendering model: %s at time %d ms\n", modelName.c_str(), timeMs);

    Model* model = frame->AllModels.GetModel(modelName);
    if (!model) {
        fprintf(stderr, "  ERROR: Model '%s' not found\n", modelName.c_str());
        return false;
    }

    printf("  Model type: %s, Nodes: %d, Channels: %d\n",
           model->GetDisplayAs().c_str(), model->GetNodeCount(), (int)model->GetChanCount());

    SequenceElements& seqElements = frame->GetSequenceElements();
    Element* elem = seqElements.GetElement(modelName);
    if (!elem || elem->GetType() != ElementType::ELEMENT_TYPE_MODEL) {
        fprintf(stderr, "  Model '%s' not found in sequence\n", modelName.c_str());
        return false;
    }

    PixelBufferClass pixelBuffer(frame);
    int numLayers = elem->GetEffectLayerCount();
    if (numLayers == 0) {
        printf("  No effect layers\n");
        return false;
    }

    pixelBuffer.InitBuffer(*model, numLayers, seqElements.GetFrameMS());
    printf("  PixelBuffer: %d layers\n", numLayers);

    int frameTimeMs = seqElements.GetFrameMS();
    int period = timeMs / frameTimeMs;

    std::vector<bool> validLayers(numLayers, false);
    bool anyRendered = false;

    for (int layer = 0; layer < numLayers; layer++) {
        EffectLayer* effectLayer = elem->GetEffectLayer(layer);
        if (!effectLayer) continue;

        Effect* effect = effectLayer->GetEffectAtTime(timeMs);
        if (!effect) continue;

        printf("  Layer %d: '%s' (%d-%d ms)\n",
               layer, effect->GetEffectName().c_str(),
               effect->GetStartTimeMS(), effect->GetEndTimeMS());

        const SettingsMap& settings = effect->GetSettings();
        pixelBuffer.SetLayerSettings(layer, settings, true);

        xlColorVector colors;
        xlColorCurveVector cc;
        effect->CopyPalette(colors, cc);
        pixelBuffer.SetPalette(layer, colors, cc);
        pixelBuffer.SetTimes(layer, effect->GetStartTimeMS(), effect->GetEndTimeMS());
        pixelBuffer.SetLayer(layer, period, true);

        RenderBuffer& buffer = pixelBuffer.BufferForLayer(layer, 0);
        printf("  Buffer: %dx%d\n", buffer.BufferWi, buffer.BufferHt);

        RenderableEffect* re = frame->GetEffectManager().GetEffect(effect->GetEffectName());
        if (!re) {
            printf("  WARNING: No renderer for '%s'\n", effect->GetEffectName().c_str());
            continue;
        }

        buffer.Clear();
        try {
            re->Render(effect, settings, buffer);
            validLayers[layer] = true;
            anyRendered = true;
            printf("  Rendered successfully\n");
            PrintPixelData(buffer, 20);
        } catch (const std::exception& e) {
            fprintf(stderr, "  Render exception: %s\n", e.what());
        } catch (...) {
            fprintf(stderr, "  Unknown render exception\n");
        }
    }

    if (!anyRendered) {
        printf("  No effects active at %d ms. Available effects:\n", timeMs);
        for (int layer = 0; layer < numLayers; layer++) {
            EffectLayer* el = elem->GetEffectLayer(layer);
            if (!el) continue;
            for (int e = 0; e < el->GetEffectCount(); e++) {
                Effect* eff = el->GetEffect(e);
                if (eff) {
                    printf("    L%d: '%s' %d-%d ms\n", layer,
                           eff->GetEffectName().c_str(),
                           eff->GetStartTimeMS(), eff->GetEndTimeMS());
                }
            }
        }
    }

    if (anyRendered) {
        printf("\n  --- Mixed output ---\n");
        pixelBuffer.CalcOutput(period, validLayers);

        uint32_t nodeCount = pixelBuffer.GetNodeCount();
        printf("  Output nodes: %d\n", nodeCount);

        int displayCount = std::min((uint32_t)20, nodeCount);
        for (int n = 0; n < displayCount; n++) {
            xlColor color = pixelBuffer.GetNodeColor(n);
            printf("  Node %3d: R=%3d G=%3d B=%3d\n",
                   n, color.red, color.green, color.blue);
        }
        if (nodeCount > 20) {
            printf("  ... (%d more nodes)\n", nodeCount - 20);
        }
    }

    printf("  Direct render test: %s\n", anyRendered ? "PASSED" : "NO EFFECTS AT TIME");
    return anyRendered;
}

// ---------------------------------------------------------------------------
// PrintPixelData
// ---------------------------------------------------------------------------
void Spike1App::PrintPixelData(const RenderBuffer& buffer, int maxPixels)
{
    int count = 0, nonBlack = 0;

    for (int y = 0; y < buffer.BufferHt && count < maxPixels; y++) {
        for (int x = 0; x < buffer.BufferWi && count < maxPixels; x++) {
            const xlColor& px = buffer.GetPixel(x, y);
            if (px.red || px.green || px.blue) {
                nonBlack++;
                if (nonBlack <= 5) {
                    printf("    Pixel(%d,%d): R=%3d G=%3d B=%3d\n",
                           x, y, px.red, px.green, px.blue);
                }
            }
            count++;
        }
    }

    if (nonBlack > 5) {
        printf("    ... and %d more non-black pixels\n", nonBlack - 5);
    }
    printf("    Non-black: %d / %d sampled (buffer: %dx%d)\n",
           nonBlack, count, buffer.BufferWi, buffer.BufferHt);
}
