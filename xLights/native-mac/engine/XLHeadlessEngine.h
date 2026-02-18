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

// XLHeadlessEngine -- Headless facade replacing xLightsFrame for the native macOS build.
// Owns all core managers and implements the interface they expect from xLightsFrame.
// No wxFrame inheritance, no wx event loop. Uses wx only for utility types
// (wxString, wxXmlNode, wxImage) via wxInitialize().

#include <string>
#include <list>
#include <queue>
#include <mutex>
#include <functional>
#include <memory>
#include <atomic>
#include <vector>

// Forward declarations -- avoid pulling in heavy headers
class Model;
class ModelManager;
class OutputManager;
class OutputModelManager;
class EffectManager;
class SequenceElements;
class PixelBufferClass;
class SettingsMap;
class Effect;
class RenderEvent;
class RenderCache;
class JobPool;
class ColorManager;
class PhonemeDictionary;
class xLightsXmlFile;
class wxXmlNode;

// SequenceData is needed for the _seqData member type
#include "SequenceData.h"

typedef SequenceData SeqDataType;

// Forward declare the internal render tree node type (defined in Render.cpp)
class RenderTreeData;

/// XLHeadlessEngine is the central coordinator for the native macOS build.
/// It replaces xLightsFrame as the owner of all core engine managers.
///
/// The legacy render pipeline (Render.cpp, PixelBuffer.cpp, etc.) calls methods
/// on xLightsFrame*. This class implements those methods without inheriting from
/// wxFrame or creating any windows.
///
/// Usage:
///   XLHeadlessEngine engine;
///   engine.SetShowDirectory("/path/to/show");
///   engine.Initialize();
///   engine.LoadShow();
///   engine.LoadSequence("sequence.xsq");
///   engine.RenderAll([](bool success) { /* done */ });
///
class XLHeadlessEngine {
public:
    XLHeadlessEngine();
    ~XLHeadlessEngine();

    // Non-copyable, non-movable
    XLHeadlessEngine(const XLHeadlessEngine&) = delete;
    XLHeadlessEngine& operator=(const XLHeadlessEngine&) = delete;

    // =========================================================================
    // Lifecycle
    // =========================================================================

    /// Set the show directory (where .xshow, rgbeffects.xml, etc. live)
    void SetShowDirectory(const std::string& dir);
    const std::string& GetShowDirectory() const { return _showDirectory; }

    /// Initialize all managers. Call after SetShowDirectory.
    /// Calls wxInitialize() for wx utility types, then creates managers.
    bool Initialize();

    /// Load show data (models, outputs, etc.) from the show directory
    bool LoadShow();

    /// Load a sequence file (.xsq or .xml)
    bool LoadSequence(const std::string& path);

    /// Shut down cleanly -- releases all managers and calls wxUninitialize()
    void Shutdown();

    // =========================================================================
    // GROUP 1: Model Access
    // Called by: SequenceElements, RenderBuffer, Render.cpp, Effect.cpp
    // =========================================================================

    Model* GetModel(const std::string& name) const;

    /// Direct public member -- matches xLightsFrame::AllModels pattern.
    /// Heap-allocated by Initialize(), owned by this class.
    ModelManager* AllModels = nullptr;

    // =========================================================================
    // GROUP 2: Effect Manager
    // Called by: SequenceElements, Render.cpp
    // =========================================================================

    EffectManager& GetEffectManager();

    // =========================================================================
    // GROUP 3: Output Manager
    // Called by: ModelManager, Model, controller code
    // =========================================================================

    OutputManager* GetOutputManager();
    OutputModelManager* GetOutputModelManager();

    // =========================================================================
    // GROUP 4: Sequence Elements
    // Called by: Render.cpp, TabSequence
    // =========================================================================

    SequenceElements& GetSequenceElements();

    // =========================================================================
    // GROUP 5: Sequence Data (raw channel output buffer)
    // Called by: Render.cpp extensively -- public member matches xLightsFrame
    // =========================================================================

    SeqDataType _seqData;

    // =========================================================================
    // GROUP 6: Render Cache
    // Called by: Render.cpp for effect frame caching
    // =========================================================================

    RenderCache* GetRenderCache();

    // =========================================================================
    // GROUP 7: Render Pipeline
    // These are the core render orchestration methods from Render.cpp.
    // In the legacy code, these are methods on xLightsFrame.
    // We implement them here with the same signatures.
    // =========================================================================

    /// Initialize a pixel buffer for a model. Called by RenderJob.
    bool InitPixelBuffer(const std::string& modelName, PixelBufferClass& buffer,
                         int layerCount, bool zeroBased = false);

    /// Core per-effect render dispatch. Called from RenderJob.
    bool RenderEffectFromMap(bool suppress, Effect* effect, int layer, int period,
                            SettingsMap& settingsMap, PixelBufferClass& buffer,
                            bool& resetEffectState, bool bgThread = false,
                            RenderEvent* event = nullptr);

    /// Render all effects to sequence data
    void RenderAll(std::function<void(bool)>&& callback);

    /// Render only dirty (changed) models
    void RenderDirtyModels();

    /// Render a specific model's effects in a time range
    void RenderEffectForModel(const std::string& model, int startms, int endms,
                              bool clear = false);

    /// Render a time range for all models
    void RenderTimeSlice(int startms, int endms, bool clear);

    /// Abort all in-progress render jobs. Returns true if all stopped in time.
    bool AbortRender(int maxTimeMs = 60000, int* numThreadsAborted = nullptr);

    // =========================================================================
    // GROUP 8: Thread Pool
    // =========================================================================

    JobPool* GetJobPool();

    // =========================================================================
    // GROUP 9: Render State
    // Public members matching xLightsFrame layout for legacy code compatibility
    // =========================================================================

    bool _suspendRender = false;
    bool mRendering = false;
    bool _renderMode = false;
    int abortedRenderJobs = 0;
    unsigned int modelsChangeCount = 0;

    void SuspendRender(bool suspend) { _suspendRender = suspend; }
    bool IsRenderSuspended() const { return _suspendRender; }

    // =========================================================================
    // GROUP 10: Show Directory / Current Dir
    // Called by: SequenceElements, Render.cpp, ModelManager, Model
    // NOTE: Legacy code uses static wxString xLightsFrame::CurrentDir.
    //       We provide a non-static std::string; the static will be set
    //       during Initialize() if needed for legacy compatibility.
    // =========================================================================

    std::string CurrentDir;

    // =========================================================================
    // GROUP 11: Phoneme Dictionary
    // Called by: SequenceElements for word->phoneme breakdown
    // =========================================================================

    PhonemeDictionary* GetDictionary();

    // =========================================================================
    // GROUP 12: Dirty/Save Flags
    // Called by: ColorManager, ModelManager, OutputModelManager
    // =========================================================================

    bool UnsavedRgbEffectsChanges = false;
    void UpdateLayoutSave() { UnsavedRgbEffectsChanges = true; }
    void UpdateControllerSave() { UnsavedRgbEffectsChanges = true; }

    // =========================================================================
    // GROUP 13: State Queries
    // Called by: ModelManager, Render.cpp, SequenceElements
    // =========================================================================

    bool IsSequencerInitialize() const { return _sequencerInitialized; }
    bool IsRenderBell() const { return false; }

    // =========================================================================
    // GROUP 14: Preferences / Config
    // =========================================================================

    bool GetIgnoreVendorModelRecommendations() const { return false; }
    void SuspendAutoSave(bool suspend) { _autoSaveSuspended = suspend; }

    // =========================================================================
    // GROUP 15: Debug / Trace
    // =========================================================================

    void AddTraceMessage(const std::string& msg);

    // =========================================================================
    // GROUP 16: UI Stubs (no-ops in headless mode)
    // These are called by the render pipeline but do nothing without UI.
    // =========================================================================

    /// CallAfter replacement: dispatches to main queue via GCD.
    /// Implementation in .mm file uses dispatch_async(dispatch_get_main_queue()).
    void CallAfter(std::function<void()> func);

    /// Status text (logged instead of shown in status bar)
    void SetStatusText(const std::string& msg, int field = 0);

    /// No-op: layout preview refresh
    void RenderLayout() {}

    /// No-op: jukebox loading
    void LoadJukebox(wxXmlNode* /*node*/) {}

    /// Start output/render timer -- dispatches deferred render via GCD
    void StartOutputTimer();

    /// Signal that rendering is complete
    void RenderDone();

    // =========================================================================
    // GROUP 17: Layout Preview Stub
    // Called by: ModelManager, Model for canvas dimensions.
    // In legacy code, modelPreview is a ModelPreview* (a wxGLCanvas subclass).
    // We provide a lightweight stub with just the dimension methods that
    // the render pipeline and model code actually call.
    // =========================================================================

    struct LayoutPreviewStub {
        int GetVirtualCanvasWidth() const { return width; }
        int GetVirtualCanvasHeight() const { return height; }
        int getWidth() const { return width; }
        int getHeight() const { return height; }
        int width = 1920;
        int height = 1080;
    };

    LayoutPreviewStub* GetLayoutPreview() { return &_layoutPreview; }
    LayoutPreviewStub* modelPreview = &_layoutPreview;

    // =========================================================================
    // GROUP 18: Sequence file pointer
    // Legacy code checks CurrentSeqXmlFile != nullptr to see if a sequence
    // is open. We store it as xLightsXmlFile* for type compatibility.
    // =========================================================================

    xLightsXmlFile* CurrentSeqXmlFile = nullptr;

    // =========================================================================
    // GROUP 19: Render Cache Size
    // =========================================================================

    size_t GetRenderCacheMaxSizeMB() const { return _renderCacheMaxMB; }
    void SetRenderCacheMaxSizeMB(size_t mb) { _renderCacheMaxMB = mb; }

    // =========================================================================
    // GROUP 20: Progress Callback (replaces wx progress dialog)
    // Native UI can attach a callback to receive render progress updates.
    // =========================================================================

    using ProgressCallback = std::function<void(int current, int total, const std::string& msg)>;
    void SetProgressCallback(ProgressCallback cb) { _progressCallback = std::move(cb); }

    // =========================================================================
    // GROUP 21: Render helpers called from Render.cpp
    // =========================================================================

    void RenderGridToSeqData(std::function<void(bool)>&& callback);
    void UpdateRenderStatus();
    void LogRenderStatus();
    void RenderMainThreadEffects();
    void RenderEffectOnMainThread(RenderEvent* evt);
    void BuildRenderTree();

    void Render(SequenceElements& seqElements,
                SequenceData& seqData,
                const std::list<Model*> models,
                const std::list<Model*>& restrictToModels,
                int startFrame, int endFrame,
                bool progressDialog, bool clear,
                std::function<void(bool)>&& callback);

private:
    // =========================================================================
    // Owned managers
    //
    // Most use unique_ptr because they require constructor arguments (like
    // a pointer to this engine), so they cannot be stack members initialized
    // in the member initializer list.
    //
    // AllModels is a raw pointer (public, above) because legacy code accesses
    // it as AllModels[name] and many callers take it by pointer/reference.
    // =========================================================================

    std::unique_ptr<OutputManager> _outputManager;
    std::unique_ptr<OutputModelManager> _outputModelManager;
    std::unique_ptr<EffectManager> _effectManager;
    std::unique_ptr<SequenceElements> _sequenceElements;
    std::unique_ptr<RenderCache> _renderCache;
    std::unique_ptr<ColorManager> _colorManager;
    std::unique_ptr<PhonemeDictionary> _dictionary;
    std::unique_ptr<JobPool> _jobPool;

    // =========================================================================
    // Internal state
    // =========================================================================

    std::string _showDirectory;
    bool _initialized = false;
    bool _sequencerInitialized = false;
    bool _autoSaveSuspended = false;
    size_t _renderCacheMaxMB = 0;
    LayoutPreviewStub _layoutPreview;

    // =========================================================================
    // Render state
    // =========================================================================

    class RenderTree {
    public:
        RenderTree() : renderTreeChangeCount(0) {}
        ~RenderTree() { Clear(); }
        void Clear();
        void Add(Model* el);

        unsigned int renderTreeChangeCount;
        std::list<RenderTreeData*> data;
    } renderTree;

    std::list<void*> renderProgressInfo;  // RenderProgressInfo* (defined in Render.cpp)
    std::queue<RenderEvent*> mainThreadRenderEvents;
    std::mutex renderEventLock;

    // =========================================================================
    // Progress
    // =========================================================================

    ProgressCallback _progressCallback;

    // =========================================================================
    // wx initialization tracking
    // =========================================================================

    bool _wxInitialized = false;
};
