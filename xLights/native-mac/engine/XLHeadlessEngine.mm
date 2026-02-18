/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// XLHeadlessEngine.mm
// Implementation of the headless engine facade for native macOS build.
// This is Obj-C++ (.mm) because it uses GCD (dispatch_async) for CallAfter
// and NSLog for diagnostics.

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

#include "XLHeadlessEngine.h"

// wx initialization -- no windows, no event loop, just utility types
#include <wx/init.h>
#include <wx/image.h>

// Manager headers
// TODO: Uncomment these as legacy source files are added to the native target.
// Until then, the corresponding methods contain stub implementations.
//
// #include "models/ModelManager.h"
// #include "effects/EffectManager.h"
// #include "outputs/OutputManager.h"
// #include "OutputModelManager.h"
// #include "sequencer/SequenceElements.h"
// #include "RenderCache.h"
// #include "JobPool.h"
// #include "ColorManager.h"
// #include "PhonemeDictionary.h"
// #include "PixelBuffer.h"
// #include "xLightsXmlFile.h"

#pragma mark - Lifecycle

XLHeadlessEngine::XLHeadlessEngine() {
    NSLog(@"XLHeadlessEngine: Created");
}

XLHeadlessEngine::~XLHeadlessEngine() {
    Shutdown();
}

void XLHeadlessEngine::SetShowDirectory(const std::string& dir) {
    _showDirectory = dir;
    CurrentDir = dir;
}

bool XLHeadlessEngine::Initialize() {
    if (_initialized) return true;

    // Initialize wxWidgets utility types (no windows, no event loop).
    // This gives us wxString, wxXmlNode, wxImage, etc.
    if (!_wxInitialized) {
        if (!wxInitialize()) {
            NSLog(@"XLHeadlessEngine: wxInitialize() failed");
            return false;
        }
        wxInitAllImageHandlers();
        _wxInitialized = true;
        NSLog(@"XLHeadlessEngine: wxWidgets initialized (utility types only)");
    }

    // Create managers in dependency order.
    // TODO: Uncomment as legacy files are added to the native target.
    //
    // _outputManager = std::make_unique<OutputManager>();
    // _outputModelManager = std::make_unique<OutputModelManager>();
    // _outputModelManager->SetFrame(reinterpret_cast<xLightsFrame*>(this));
    //
    // AllModels = new ModelManager(_outputManager.get(),
    //                              reinterpret_cast<xLightsFrame*>(this));
    //
    // _effectManager = std::make_unique<EffectManager>();
    // _sequenceElements = std::make_unique<SequenceElements>(
    //                         reinterpret_cast<xLightsFrame*>(this));
    //
    // _jobPool = std::make_unique<JobPool>("RenderPool");
    // _jobPool->Start(std::thread::hardware_concurrency());
    //
    // _renderCache = std::make_unique<RenderCache>();
    // _colorManager = std::make_unique<ColorManager>(
    //                     reinterpret_cast<xLightsFrame*>(this));
    // _dictionary = std::make_unique<PhonemeDictionary>();

    _initialized = true;
    NSLog(@"XLHeadlessEngine: Initialized with show dir: %s", _showDirectory.c_str());
    return true;
}

bool XLHeadlessEngine::LoadShow() {
    if (!_initialized) return false;

    // TODO: Load models and outputs from the show directory XML files.
    // This will parse rgbeffects.xml for models and xlights_networks.xml
    // for outputs/controllers.
    //
    // wxXmlDocument effectsXml;
    // effectsXml.Load(CurrentDir + "/rgbeffects.xml");
    // wxXmlNode* modelsNode = ...find "models" node...
    // AllModels->LoadModels(modelsNode,
    //     _layoutPreview.GetVirtualCanvasWidth(),
    //     _layoutPreview.GetVirtualCanvasHeight());
    //
    // _outputManager->Load(CurrentDir + "/xlights_networks.xml");
    // AllModels->RecalcStartChannels();

    NSLog(@"XLHeadlessEngine: LoadShow() -- stub, not yet wired to legacy files");
    return true;
}

bool XLHeadlessEngine::LoadSequence(const std::string& path) {
    if (!_initialized) return false;

    // TODO: Load sequence using xLightsXmlFile.
    // This will parse the .xsq/.xml file, populate SequenceElements,
    // and initialize _seqData with the correct channel/frame counts.
    //
    // xLightsXmlFile xmlFile(wxFileName(path));
    // _sequenceElements->LoadSequencerFile(xmlFile, CurrentDir);
    // _seqData.init(numChannels, numFrames, frameTime);
    // CurrentSeqXmlFile = &xmlFile;  // need to manage lifetime
    // _sequencerInitialized = true;

    NSLog(@"XLHeadlessEngine: LoadSequence(%s) -- stub, not yet wired to legacy files",
          path.c_str());
    return true;
}

void XLHeadlessEngine::Shutdown() {
    if (!_initialized) return;

    NSLog(@"XLHeadlessEngine: Shutting down...");

    AbortRender(5000);

    // Release managers in reverse order of creation
    _dictionary.reset();
    _colorManager.reset();
    _renderCache.reset();
    _jobPool.reset();
    _sequenceElements.reset();
    _effectManager.reset();
    delete AllModels;
    AllModels = nullptr;
    _outputModelManager.reset();
    _outputManager.reset();

    CurrentSeqXmlFile = nullptr;

    if (_wxInitialized) {
        wxUninitialize();
        _wxInitialized = false;
    }

    _initialized = false;
    _sequencerInitialized = false;
    NSLog(@"XLHeadlessEngine: Shutdown complete");
}

#pragma mark - Model Access

Model* XLHeadlessEngine::GetModel(const std::string& name) const {
    if (!AllModels) return nullptr;
    // TODO: Uncomment once ModelManager is in the target
    // return (*AllModels)[name];
    return nullptr;
}

#pragma mark - Manager Access

EffectManager& XLHeadlessEngine::GetEffectManager() {
    return *_effectManager;
}

OutputManager* XLHeadlessEngine::GetOutputManager() {
    return _outputManager.get();
}

OutputModelManager* XLHeadlessEngine::GetOutputModelManager() {
    return _outputModelManager.get();
}

SequenceElements& XLHeadlessEngine::GetSequenceElements() {
    return *_sequenceElements;
}

RenderCache* XLHeadlessEngine::GetRenderCache() {
    return _renderCache.get();
}

JobPool* XLHeadlessEngine::GetJobPool() {
    return _jobPool.get();
}

PhonemeDictionary* XLHeadlessEngine::GetDictionary() {
    return _dictionary.get();
}

#pragma mark - Render Pipeline

bool XLHeadlessEngine::InitPixelBuffer(const std::string& modelName,
                                        PixelBufferClass& buffer,
                                        int layerCount, bool zeroBased) {
    // Adapted from tabSequencer.cpp InitPixelBuffer.
    // TODO: Implement once PixelBuffer.h and Model.h are in the target.
    //
    // Model* model = GetModel(modelName);
    // if (!model) return false;
    // buffer.InitBuffer(*model, layerCount, _seqData.FrameTime(), zeroBased);
    // return true;

    NSLog(@"XLHeadlessEngine: InitPixelBuffer(%s) -- stub", modelName.c_str());
    return false;
}

bool XLHeadlessEngine::RenderEffectFromMap(bool suppress, Effect* effect, int layer,
                                            int period, SettingsMap& settingsMap,
                                            PixelBufferClass& buffer,
                                            bool& resetEffectState, bool bgThread,
                                            RenderEvent* event) {
    // Core render dispatch, adapted from Render.cpp:2134-2300.
    // ~170 lines of render dispatch logic.
    // TODO: Implement once the full effect system is wired in.

    NSLog(@"XLHeadlessEngine: RenderEffectFromMap -- stub");
    return false;
}

void XLHeadlessEngine::RenderAll(std::function<void(bool)>&& callback) {
    if (_suspendRender || mRendering) {
        if (callback) callback(false);
        return;
    }
    mRendering = true;

    // TODO: Implement once the render pipeline is wired.
    // RenderGridToSeqData(std::move(callback));

    NSLog(@"XLHeadlessEngine: RenderAll -- stub");
    mRendering = false;
    if (callback) callback(true);
}

void XLHeadlessEngine::RenderDirtyModels() {
    // Adapted from Render.cpp:1670-1731.
    // TODO: Implement once render tree and model system are wired.
}

void XLHeadlessEngine::RenderEffectForModel(const std::string& model,
                                             int startms, int endms, bool clear) {
    // Adapted from Render.cpp:1842-1908.
    // TODO: Implement.
}

void XLHeadlessEngine::RenderTimeSlice(int startms, int endms, bool clear) {
    // Adapted from Render.cpp:1911-1973.
    // TODO: Implement.
}

bool XLHeadlessEngine::AbortRender(int maxTimeMs, int* numThreadsAborted) {
    // Adapted from Render.cpp:1734-1786.
    // TODO: Implement once JobPool is wired.
    if (numThreadsAborted) *numThreadsAborted = 0;
    return true;
}

void XLHeadlessEngine::RenderGridToSeqData(std::function<void(bool)>&& callback) {
    // Adapted from Render.cpp:1788-1838.
    // This is the top-level render coordinator that creates RenderJobs for
    // each model and pushes them to the JobPool.
    // TODO: Implement.
    if (callback) callback(false);
}

void XLHeadlessEngine::BuildRenderTree() {
    // Adapted from Render.cpp:1440-1462.
    // Builds dependency graph of models based on channel overlap.
    // TODO: Implement.
}

void XLHeadlessEngine::RenderMainThreadEffects() {
    // Adapted from Render.cpp:1099.
    // Drains the mainThreadRenderEvents queue, calling
    // RenderEffectOnMainThread for each event.
    std::lock_guard<std::mutex> lock(renderEventLock);
    while (!mainThreadRenderEvents.empty()) {
        RenderEvent* evt = mainThreadRenderEvents.front();
        mainThreadRenderEvents.pop();
        RenderEffectOnMainThread(evt);
    }
}

void XLHeadlessEngine::RenderEffectOnMainThread(RenderEvent* evt) {
    // Adapted from Render.cpp:1111.
    // Some effects (like Text) must render on the main thread.
    // TODO: Implement once RenderEvent is available.
}

void XLHeadlessEngine::UpdateRenderStatus() {
    // Adapted from Render.cpp:1226-1323.
    // Checks render progress and updates status/cleans up completed jobs.
    // TODO: Implement.
}

void XLHeadlessEngine::LogRenderStatus() {
    // Adapted from Render.cpp:1148-1186.
    // Logs detailed render progress for diagnostics.
    // TODO: Implement.
}

void XLHeadlessEngine::Render(SequenceElements& seqElements, SequenceData& seqData,
                               const std::list<Model*> models,
                               const std::list<Model*>& restrictToModels,
                               int startFrame, int endFrame,
                               bool progressDialog, bool clear,
                               std::function<void(bool)>&& callback) {
    // Master render orchestrator from Render.cpp:1463-1632.
    // Creates render jobs for each model, pushes to thread pool,
    // and tracks progress via RenderProgressInfo.
    // TODO: Implement.
    if (callback) callback(false);
}

#pragma mark - UI Stubs

void XLHeadlessEngine::CallAfter(std::function<void()> func) {
    // Replacement for wxFrame::CallAfter.
    // Dispatches the callable to the main queue via GCD.
    if (!func) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        func();
    });
}

void XLHeadlessEngine::SetStatusText(const std::string& msg, int field) {
    NSLog(@"XLHeadlessEngine Status[%d]: %s", field, msg.c_str());
}

void XLHeadlessEngine::StartOutputTimer() {
    // In legacy code, this starts a wxTimer that triggers periodic rendering.
    // In headless mode, dispatch a deferred render to the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!_suspendRender) {
            RenderDirtyModels();
        }
    });
}

void XLHeadlessEngine::RenderDone() {
    mRendering = false;
    NSLog(@"XLHeadlessEngine: Render complete");
}

void XLHeadlessEngine::AddTraceMessage(const std::string& msg) {
    NSLog(@"XLHeadlessEngine Trace: %s", msg.c_str());
}

#pragma mark - Render Tree

void XLHeadlessEngine::RenderTree::Clear() {
    for (auto* d : data) {
        delete d;
    }
    data.clear();
}

void XLHeadlessEngine::RenderTree::Add(Model* el) {
    // Adapted from Render.cpp RenderTree::Add.
    // Creates a RenderTreeData node and inserts it, respecting
    // channel overlap ordering.
    // TODO: Implement once RenderTreeData is available.
}
