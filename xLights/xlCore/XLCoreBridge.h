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
 * @file XLCoreBridge.h
 * @brief C bridge interface for xlCore library.
 *
 * This header provides a C-compatible interface to the xlCore library
 * for use by the native macOS UI layer. The Objective-C++ wrapper
 * (XLCoreBridge.mm) implements these functions using xlCore C++ classes.
 *
 * This allows the native macOS UI (Swift/Objective-C) to use xlCore
 * without directly including C++ headers.
 */

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// ============================================================================
// Opaque handle types
// ============================================================================

typedef struct XLCoreEngine_* XLCoreEngineRef;
typedef struct XLCoreEffect_* XLCoreEffectRef;
typedef struct XLCoreRenderContext_* XLCoreRenderContextRef;
typedef struct XLCoreSequence_* XLCoreSequenceRef;

// ============================================================================
// Callback types
// ============================================================================

typedef void (*XLCoreProgressCallback)(int current, int total, const char* message, void* context);
typedef void (*XLCoreCompletionCallback)(bool success, const char* message, void* context);

// ============================================================================
// Engine lifecycle
// ============================================================================

/**
 * @brief Create and initialize the xlCore engine.
 */
XLCoreEngineRef XLCoreEngineCreate(void);

/**
 * @brief Destroy the xlCore engine and free resources.
 */
void XLCoreEngineDestroy(XLCoreEngineRef engine);

/**
 * @brief Check if the engine is initialized.
 */
bool XLCoreEngineIsInitialized(XLCoreEngineRef engine);

// ============================================================================
// Effect management
// ============================================================================

/**
 * @brief Get the number of registered effects.
 */
int XLCoreGetEffectCount(XLCoreEngineRef engine);

/**
 * @brief Get effect name at index.
 *
 * @param buffer Output buffer (must be at least bufferSize bytes)
 * @param bufferSize Size of buffer
 * @return Actual length of effect name (excluding null terminator)
 */
int XLCoreGetEffectNameAtIndex(XLCoreEngineRef engine, int index, char* buffer, int bufferSize);

/**
 * @brief Check if an effect exists.
 */
bool XLCoreHasEffect(XLCoreEngineRef engine, const char* effectName);

/**
 * @brief Get effect description.
 */
int XLCoreGetEffectDescription(XLCoreEngineRef engine, const char* effectName,
                                char* buffer, int bufferSize);

/**
 * @brief Get effect category.
 */
int XLCoreGetEffectCategory(XLCoreEngineRef engine, const char* effectName,
                             char* buffer, int bufferSize);

/**
 * @brief Get number of parameters for an effect.
 */
int XLCoreGetEffectParameterCount(XLCoreEngineRef engine, const char* effectName);

/**
 * @brief Get effect parameter info at index.
 *
 * @param parameterInfo Output struct with parameter details
 * @return true if successful
 */
typedef struct {
    char key[128];
    char displayName[128];
    char description[256];
    int type;  // 0=Int, 1=Double, 2=Bool, 3=String, 4=Color, 5=Choice, 6=File
    char defaultValue[128];
    double minValue;
    double maxValue;
    double step;
    bool supportsValueCurve;
} XLCoreParameterInfo;

bool XLCoreGetEffectParameterInfo(XLCoreEngineRef engine, const char* effectName,
                                   int index, XLCoreParameterInfo* parameterInfo);

// ============================================================================
// Category management
// ============================================================================

/**
 * @brief Get the number of effect categories.
 */
int XLCoreGetCategoryCount(XLCoreEngineRef engine);

/**
 * @brief Get category name at index.
 */
int XLCoreGetCategoryNameAtIndex(XLCoreEngineRef engine, int index,
                                  char* buffer, int bufferSize);

/**
 * @brief Get number of effects in a category.
 */
int XLCoreGetEffectsInCategoryCount(XLCoreEngineRef engine, const char* categoryName);

/**
 * @brief Get effect name at index within a category.
 */
int XLCoreGetEffectInCategoryAtIndex(XLCoreEngineRef engine, const char* categoryName,
                                      int index, char* buffer, int bufferSize);

// ============================================================================
// Rendering
// ============================================================================

/**
 * @brief Create a render context.
 */
XLCoreRenderContextRef XLCoreRenderContextCreate(int width, int height);

/**
 * @brief Destroy a render context.
 */
void XLCoreRenderContextDestroy(XLCoreRenderContextRef context);

/**
 * @brief Clear the render context to black.
 */
void XLCoreRenderContextClear(XLCoreRenderContextRef context);

/**
 * @brief Clear the render context to transparent.
 */
void XLCoreRenderContextClearTransparent(XLCoreRenderContextRef context);

/**
 * @brief Get render context width.
 */
int XLCoreRenderContextGetWidth(XLCoreRenderContextRef context);

/**
 * @brief Get render context height.
 */
int XLCoreRenderContextGetHeight(XLCoreRenderContextRef context);

/**
 * @brief Get raw pixel data (RGBA, 4 bytes per pixel).
 *
 * @return Pointer to pixel data (valid until context is modified/destroyed)
 */
const uint8_t* XLCoreRenderContextGetPixelData(XLCoreRenderContextRef context);

/**
 * @brief Get pixel data size in bytes.
 */
size_t XLCoreRenderContextGetPixelDataSize(XLCoreRenderContextRef context);

/**
 * @brief Render an effect to a context.
 *
 * @param context Render context
 * @param effectName Effect type name
 * @param settings Settings string (key=value pairs, comma-separated)
 * @param progress Render progress (0.0 to 1.0)
 * @return true if successful
 */
bool XLCoreRenderEffect(XLCoreRenderContextRef context,
                         const char* effectName,
                         const char* settings,
                         double progress);

/**
 * @brief Render an effect with full timing parameters.
 */
bool XLCoreRenderEffectWithTiming(XLCoreRenderContextRef context,
                                   const char* effectName,
                                   const char* settings,
                                   double timeSeconds,
                                   double effectStartTime,
                                   double effectEndTime,
                                   int frameIndex);

// ============================================================================
// Sequence operations
// ============================================================================

/**
 * @brief Load a sequence from file.
 */
XLCoreSequenceRef XLCoreSequenceLoad(XLCoreEngineRef engine, const char* path);

/**
 * @brief Create a new sequence.
 */
XLCoreSequenceRef XLCoreSequenceCreate(XLCoreEngineRef engine,
                                        int durationMS,
                                        int frameIntervalMS);

/**
 * @brief Destroy a sequence.
 */
void XLCoreSequenceDestroy(XLCoreSequenceRef sequence);

/**
 * @brief Save a sequence to file.
 */
bool XLCoreSequenceSave(XLCoreSequenceRef sequence, const char* path);

/**
 * @brief Get sequence duration in milliseconds.
 */
int XLCoreSequenceGetDuration(XLCoreSequenceRef sequence);

/**
 * @brief Get sequence frame interval in milliseconds.
 */
int XLCoreSequenceGetFrameInterval(XLCoreSequenceRef sequence);

/**
 * @brief Get number of elements in sequence.
 */
int XLCoreSequenceGetElementCount(XLCoreSequenceRef sequence);

/**
 * @brief Get element name at index.
 */
int XLCoreSequenceGetElementName(XLCoreSequenceRef sequence, int index,
                                  char* buffer, int bufferSize);

// ============================================================================
// Render pipeline
// ============================================================================

/**
 * @brief Set up the render pipeline for a sequence.
 */
void XLCoreSetupRenderPipeline(XLCoreEngineRef engine, XLCoreSequenceRef sequence);

/**
 * @brief Add a model to the render pipeline.
 */
void XLCoreAddModelToPipeline(XLCoreEngineRef engine,
                               const char* modelName,
                               int bufferWidth,
                               int bufferHeight);

/**
 * @brief Render a single frame for a model.
 *
 * @param buffer Output buffer (must be at least width*height*4 bytes)
 * @return true if successful
 */
bool XLCoreRenderModelFrame(XLCoreEngineRef engine,
                             const char* modelName,
                             int timeMS,
                             uint8_t* buffer,
                             size_t bufferSize);

/**
 * @brief Render all frames in range (batch rendering).
 */
void XLCoreRenderRange(XLCoreEngineRef engine,
                        int startMS,
                        int endMS,
                        XLCoreProgressCallback progressCallback,
                        XLCoreCompletionCallback completionCallback,
                        void* callbackContext);

/**
 * @brief Abort rendering in progress.
 */
void XLCoreAbortRender(XLCoreEngineRef engine);

/**
 * @brief Check if rendering is in progress.
 */
bool XLCoreIsRendering(XLCoreEngineRef engine);

// ============================================================================
// Statistics
// ============================================================================

typedef struct {
    size_t framesRendered;
    size_t cacheHits;
    size_t cacheMisses;
    double avgRenderTimeMs;
    double totalRenderTimeMs;
} XLCoreRenderStatistics;

/**
 * @brief Get render statistics.
 */
void XLCoreGetRenderStatistics(XLCoreEngineRef engine, XLCoreRenderStatistics* stats);

/**
 * @brief Reset render statistics.
 */
void XLCoreResetRenderStatistics(XLCoreEngineRef engine);

// ============================================================================
// Color utilities
// ============================================================================

/**
 * @brief Parse a color string (hex or RGB).
 */
bool XLCoreParseColor(const char* colorStr, uint8_t* r, uint8_t* g, uint8_t* b);

/**
 * @brief Convert color to string.
 */
int XLCoreColorToString(uint8_t r, uint8_t g, uint8_t b, char* buffer, int bufferSize);

/**
 * @brief Convert HSV to RGB.
 */
void XLCoreHSVToRGB(double h, double s, double v, uint8_t* r, uint8_t* g, uint8_t* b);

/**
 * @brief Convert RGB to HSV.
 */
void XLCoreRGBToHSV(uint8_t r, uint8_t g, uint8_t b, double* h, double* s, double* v);

#ifdef __cplusplus
}
#endif
