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

// NativePixelBuffer: wx-free layer blending orchestrator for the native macOS
// render pipeline. Replaces PixelBufferClass from the legacy build.
//
// This class manages multiple effect layers (each backed by a NativeRenderBuffer)
// and blends them together using NativeColorBlending. The final blended pixels
// are stored internally and can be extracted to a raw channel output buffer
// via getColors().
//
// Design:
//   - Each layer has its own NativeRenderBuffer that effects render into
//   - calcOutput() blends all valid layers back-to-front per pixel
//   - Per-layer adjustments: HSV, brightness, contrast, sparkle, blur, fade
//   - getColors() maps blended pixels to controller output channels via node info
//
// Thread safety: Each NativePixelBuffer instance is used by one render thread.
// Multiple instances can safely run in parallel on different threads.

#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <set>
#include <string>
#include <vector>
#include <utility>

#include "NativeRenderBuffer.h"
#include "NativeColorBlending.h"
#include "MetalBlendingCompute.h"
#include "IRenderContext.h"
#include "../../Color.h"

namespace xlEngine {

// Describes how a single physical node maps to the buffer and output channels.
struct NativeNodeInfo {
    int bufX = 0;              // Buffer x coordinate for this node
    int bufY = 0;              // Buffer y coordinate for this node
    uint32_t actChannel = 0;   // Absolute channel offset in the output buffer
    int channelsPerNode = 3;   // 3 for RGB, 4 for RGBW, 1 for single channel
    int colorOrder[4] = {0, 1, 2, 3}; // Channel order offsets (e.g., GRB = {1,0,2})
};

// Per-model dimming curve: a 256-entry LUT per RGB channel.
// Built from the model's <dimmingCurve> XML element (gamma/brightness settings).
// When active is false, no dimming is applied (identity transform).
struct NativeDimmingCurve {
    bool active = false;
    std::array<uint8_t, 256> red;    // Red channel LUT
    std::array<uint8_t, 256> green;  // Green channel LUT
    std::array<uint8_t, 256> blue;   // Blue channel LUT

    NativeDimmingCurve() : active(false) {
        for (int i = 0; i < 256; ++i) {
            red[i] = green[i] = blue[i] = static_cast<uint8_t>(i);
        }
    }

    void apply(xlColor& c) const {
        if (!active) return;
        c.red   = red[c.red];
        c.green = green[c.green];
        c.blue  = blue[c.blue];
    }
};

// Transition type enum matching legacy PixelBuffer.cpp DecodeType() and
// the non-mask transitions in renderTransitions(). Mask-based transitions
// use a per-pixel uint8_t mask; non-mask transitions modify pixels directly.
enum class NativeTransitionType {
    Fade = 0,        // Simple linear alpha fade (no mask needed)
    Wipe,            // Mask: sweeps across based on angle
    Clock,           // Mask: radial clock sweep
    FromMiddle,      // Mask: expands/contracts from center line
    SquareExplode,   // Mask: rectangular expansion from center
    CircleExplode,   // Mask: circular expansion from center
    Blinds,          // Mask: venetian blind slats
    Blend,           // Mask: random block pattern
    SlideChecks,     // Mask: checkerboard slide
    SlideBars,       // Mask: sliding bars
    Fold,            // Non-mask: fold effect (pixel rewrite)
    Dissolve,        // Non-mask: random pixel dissolve using pattern texture
    CircularSwirl,   // Non-mask: spiral sweep
    BowTie,          // Non-mask: bow-tie reveal
    Zoom,            // Non-mask: zoom in/out
    Doorway,         // Non-mask: center-opening door
    Blobs,           // Non-mask: random blob pattern
    Pinwheel,        // Non-mask: pinwheel sweep
    Star,            // Non-mask: star-shaped reveal
    Swap,            // Non-mask: swap transition
    Shatter,         // Non-mask: shatter effect
    Circles          // Non-mask: expanding circles
};

// Per-layer settings controlling how a layer blends into the final output.
// Mirrors the settings from legacy PixelBufferClass::LayerInfo, but in a
// clean struct with no wx dependencies.
struct NativeLayerInfo {
    NativeMixType mixType = NativeMixType::Mix_Normal;
    float mixThreshold = 0.0f;
    bool effectMixVary = false;
    int sparkle_count = 0;
    float brightness = 100.0f;
    float hueAdjust = 0.0f;
    float saturationAdjust = 0.0f;
    float valueAdjust = 0.0f;
    int contrast = 0;
    float fadeFactor = 1.0f;
    bool use_music_sparkle_count = false;
    bool persistent = false;
    bool canvas = false;

    // Transition settings
    float inTransitionAdjust = 0.0f;
    float outTransitionAdjust = 0.0f;
    bool inTransitionReverse = false;
    bool outTransitionReverse = false;
    NativeTransitionType inTransitionType = NativeTransitionType::Fade;
    NativeTransitionType outTransitionType = NativeTransitionType::Fade;
    float fadeInSteps = 0.0f;
    float fadeOutSteps = 0.0f;

    // Computed transition state (set by the render coordinator before calcOutput).
    // inMaskFactor/outMaskFactor are 0..1 progress values for non-Fade transitions.
    // For Fade transitions, fadeFactor is used directly instead.
    float inMaskFactor = 1.0f;
    float outMaskFactor = 1.0f;

    // Blur
    int blur = 1;

    // Chroma key
    bool isChromaKey = false;
    xlColor chromaKeyColour = xlBLACK;
    int chromaSensitivity = 1;

    // Sparkle color
    xlColor sparklesColour = xlWHITE;

    // RotoZoom: 2D rotation, 3D X/Y rotation, zoom with pivot points.
    // Applied per-layer after blur, before blending. Mirrors legacy RotoZoom().
    int rotation = 0;          // 2D rotation (0-100 slider, /100 = turns)
    int xRotation = 0;         // 3D X-axis rotation (0-360 degrees)
    int yRotation = 0;         // 3D Y-axis rotation (0-360 degrees)
    float rotations = 0.0f;    // Number of full rotations per effect duration
    float zoom = 1.0f;         // Zoom factor (1.0 = no zoom)
    int zoomQuality = 1;       // Interpolation quality (1-10)
    int pivotPointX = 50;      // Pivot X for 2D rotation/zoom (0-100%)
    int pivotPointY = 50;      // Pivot Y for 2D rotation/zoom (0-100%)
    int xPivot = 50;           // Pivot X for 3D X-axis rotation (0-100%)
    int yPivot = 50;           // Pivot Y for 3D Y-axis rotation (0-100%)
    std::string rotationOrder = "X-Y-Z"; // Order of 3D rotation axes

    // Freeze: stop rendering after this many frames into the effect.
    // Default 999999 means never freeze. When effectFrame >= freezeAfterFrame,
    // the layer buffer is preserved and the effect is not re-rendered.
    int freezeAfterFrame = 999999;

    // Suppress: skip blending this layer until this many frames into the effect.
    // Default 0 means no suppression. When effectFrame < suppressUntil,
    // the effect still renders (for state tracking) but the layer is excluded
    // from calcOutput() blending.
    int suppressUntil = 0;

    // Sub-buffer: viewport sub-region where the effect renders (pixel coords).
    bool hasSubBuffer = false;
    int subBufX1 = 0;
    int subBufY1 = 0;
    int subBufX2 = 0;
    int subBufY2 = 0;

    // Buffer style: node-to-buffer mapping ("Default", "Single Line", "As Pixel").
    std::string bufferStyle = "Default";
};

// NativePixelBuffer: manages effect layers and blends them for a single model.
//
// Usage:
//   1. Construct with context, buffer dimensions, layer count, and node mapping
//   2. Effects render into getLayerBuffer(layer) for each layer
//   3. Call setLayerSettings() to configure per-layer blend parameters
//   4. Call calcOutput() to blend all layers
//   5. Call getColors() to extract final channel data to the output buffer
class NativePixelBuffer {
public:
    // Construct a pixel buffer for a model.
    //
    // @param context     Render context for audio/timing access (may be nullptr)
    // @param bufferWi    Buffer width in pixels
    // @param bufferHt    Buffer height in pixels
    // @param numLayers   Number of effect layers
    // @param nodes       Node-to-channel mapping for getColors() output
    NativePixelBuffer(IRenderContext* context, int bufferWi, int bufferHt,
                      int numLayers, const std::vector<NativeNodeInfo>& nodes);

    ~NativePixelBuffer();

    // Disallow copy (each instance owns its layer buffers)
    NativePixelBuffer(const NativePixelBuffer&) = delete;
    NativePixelBuffer& operator=(const NativePixelBuffer&) = delete;

    // Move is allowed
    NativePixelBuffer(NativePixelBuffer&&) = default;
    NativePixelBuffer& operator=(NativePixelBuffer&&) = default;

    // =========================================================================
    // Layer access
    // =========================================================================

    // Get the render buffer for a given layer. Effects render into this.
    NativeRenderBuffer& getLayerBuffer(int layer);
    const NativeRenderBuffer& getLayerBuffer(int layer) const;

    // Return the number of layers.
    int getLayerCount() const;

    // Return buffer dimensions.
    int getBufferWi() const { return _bufferWi; }
    int getBufferHt() const { return _bufferHt; }

    // Return node count.
    uint32_t getNodeCount() const { return static_cast<uint32_t>(_nodes.size()); }

    // Enable batch mode: calcOutput() only blends at node pixel positions,
    // skipping the full buffer. Dramatically faster for sparse models where
    // nodeCount << bufferWi * bufferHt. Not suitable for live preview where
    // the full pixel buffer is displayed as a texture.
    void setBatchMode(bool batch) { _batchMode = batch; }
    bool isBatchMode() const { return _batchMode; }

    // Clear output pixel buffer to black. Used for early-exit when no effects
    // are active, so getColors() writes zeros to the output channel buffer.
    void clearOutputPixels() {
        if (!_outputPixels.empty()) {
            std::memset(_outputPixels.data(), 0, _outputPixels.size() * sizeof(xlColor));
        }
    }

    // Reset all per-effect state so effects start fresh (as if newly created).
    // Clears layer pixel data, output pixels, and effect render caches.
    // Keeps buffer dimensions, nodes, and structural config intact.
    void resetEffectState();

    // Sorted unique pixel indices (bufY * bufferWi + bufX) for node positions.
    const std::vector<int>& getNodePixelIndices() const { return _nodePixelIndices; }

    // =========================================================================
    // Layer settings
    // =========================================================================

    // Set all layer settings at once.
    void setLayerSettings(int layer, const NativeLayerInfo& settings);

    // Set just the mix type for a layer.
    void setMixType(int layer, NativeMixType type);

    // Returns true if this layer uses canvas mode.
    bool isCanvasMix(int layer) const;

    // =========================================================================
    // Core output calculation — blend all layers
    // =========================================================================

    // Blend all valid layers at each pixel position and store the result.
    //
    // For each pixel (x,y):
    //   1. Iterate layers from back (highest index) to front (index 0)
    //   2. Apply per-layer blur if configured
    //   3. Apply per-layer sparkle
    //   4. Apply per-layer HSV adjustment
    //   5. Apply per-layer brightness/contrast
    //   6. Blend with accumulated result using NativeColorBlending::mixColors()
    //   7. Store final blended color
    //
    // @param effectPeriod  Current effect period (frame index)
    // @param validLayers   Boolean vector indicating which layers are active
    void calcOutput(int effectPeriod, const std::vector<bool>& validLayers);

    // =========================================================================
    // Output extraction
    // =========================================================================

    // Extract the blended pixel data into a raw channel output buffer.
    //
    // For each node:
    //   - Reads the blended pixel at (bufX, bufY)
    //   - Writes R, G, B (and optionally W) channels to outputBuffer
    //     at the node's actChannel offset, respecting colorOrder
    //
    // @param outputBuffer  Destination buffer for channel data
    // @param bufferSize    Size of outputBuffer in bytes (for bounds checking)
    void getColors(uint8_t* outputBuffer, uint32_t bufferSize) const;

    // Set the dimming curve (gamma/brightness LUT) for this model.
    // Applied in getColors() before writing each channel to the output buffer.
    void setDimmingCurve(const NativeDimmingCurve& curve);

    // Set a submodel mask. When set, getColors() will only write channel data
    // for nodes whose (bufX, bufY) coordinates are in the mask set. Nodes outside
    // the mask will have their channels written as zero. An empty mask means no masking.
    void setSubmodelMask(const std::set<std::pair<int,int>>& mask);

    // Clear the submodel mask (disable masking).
    void clearSubmodelMask();

    // Load raw channel data from an output buffer into a specific layer.
    // Used to populate the blend layer with existing rendered data (e.g., group
    // output) before rendering model effects on top. Reads each node's channels
    // from the output buffer and sets the corresponding pixel in the layer buffer.
    // Reverses the dimming curve so the loaded data matches the linear render space.
    //
    // @param layer        Layer index to load into
    // @param outputBuffer Source channel data (full frame)
    // @param bufferSize   Size of outputBuffer in bytes
    void loadChannelData(int layer, const uint8_t* outputBuffer, uint32_t bufferSize);

    // Get the blended color for a specific pixel coordinate.
    xlColor getBlendedPixel(int x, int y) const;

    // Get a pointer to the raw blended pixel data (RGBA, bufferWi * bufferHt * 4 bytes).
    // Valid after calcOutput(). Returns nullptr if no output has been calculated.
    const uint8_t* getBlendedPixelData() const;

    // Get the size in bytes of the blended pixel data.
    size_t getBlendedPixelDataSize() const;

    // =========================================================================
    // Reset / clear
    // =========================================================================

    // Clear all layer buffers and the output pixel array.
    void clear();

    // Clear a single layer buffer.
    void clearLayer(int layer);

    // Prepare a layer for sub-buffer rendering (resize to sub-region).
    void prepareSubBuffer(int layer);
    // Expand sub-buffer back to full size after effect rendering.
    void expandSubBuffer(int layer);

    // Prepare a layer for non-default buffer style (resize for style).
    void prepareBufferStyle(int layer);
    // Expand buffer style back to full size after effect rendering.
    void expandBufferStyle(int layer);

    // Set the combined group spatial layout for "Per Preview" and other spatial
    // buffer styles on group layers. When set, prepareBufferStyle("Per Preview")
    // reshapes the layer buffer to these combined dimensions. expandBufferStyle()
    // then maps each node's pixel from its spatial position back to its local
    // (bufX, bufY) in the model's own buffer.
    //
    // @param combinedW        Width of the combined spatial grid
    // @param combinedH        Height of the combined spatial grid
    // @param spatialPositions Per-node (x, y) position in the combined grid.
    //                         Must have exactly _nodes.size() entries.
    // @param groupLayerCount  Number of leading group layers. Only these layers
    //                         use the spatial layout; model's own layers don't.
    void setGroupSpatialLayout(int combinedW, int combinedH,
                                const std::vector<std::pair<int,int>>& spatialPositions,
                                size_t groupLayerCount);

    // Returns true if this buffer has a spatial group layout (set via setGroupSpatialLayout).
    bool hasSpatialGroupLayout() const { return _spatialBufW > 0 && _spatialBufH > 0; }

    // Check if a layer's buffer style or sub-buffer is active (was set by prepare*).
    // Used to skip redundant Clear() calls when prepare already cleared the buffer.
    bool isLayerBufferStyleActive(int layer) const {
        return layer >= 0 && layer < static_cast<int>(_layers.size()) && _layers[layer].bufferStyleActive;
    }
    bool isLayerSubBufferActive(int layer) const {
        return layer >= 0 && layer < static_cast<int>(_layers.size()) && _layers[layer].subBufferActive;
    }

private:
    // Internal structure holding per-layer state
    struct LayerState {
        NativeRenderBuffer buffer;
        NativeLayerInfo settings;

        // Cached output parameters (computed per frame in calcOutput)
        float outputHueAdjust = 0.0f;
        float outputSaturationAdjust = 0.0f;
        float outputValueAdjust = 0.0f;
        int outputBrightness = 100;
        float outputEffectMixThreshold = 0.0f;
        int outputSparkleCount = 0;

        // Transition mask: per-pixel uint8_t array (bufferWi * bufferHt).
        // 0 = visible, >0 = masked (hidden). Layout: mask[x * bufferHt + y].
        std::vector<uint8_t> transitionMask;
        int maskSize = 0;

        // Sub-buffer/buffer-style tracking
        bool subBufferActive = false;
        int subBufOrigW = 0, subBufOrigH = 0;
        bool bufferStyleActive = false;
        int styleOrigW = 0, styleOrigH = 0;

        LayerState(IRenderContext* ctx, int w, int h)
            : buffer(ctx, w, h) {}
    };

    // Apply Gaussian blur to a layer's buffer.
    void applyBlur(LayerState& layer);

    // Apply RotoZoom transforms (2D rotation, 3D X/Y rotation, zoom) to a
    // layer's buffer. Mirrors legacy PixelBufferClass::RotoZoom().
    // @param offset  Effect time position (0.0 to 1.0)
    void applyRotoZoom(LayerState& layer, float offset);

    // Compute and apply transition masks for a layer.
    void applyTransitions(LayerState& layer);

    // Apply sparkle effect to a pixel color.
    void applySparkle(xlColor& color, int nodeIndex, int sparkleCount,
                      const xlColor& sparkleColour) const;

    IRenderContext* _context;
    int _bufferWi;
    int _bufferHt;
    std::vector<LayerState> _layers;
    std::vector<NativeNodeInfo> _nodes;
    std::vector<xlColor> _outputPixels; // Final blended result (bufferWi * bufferHt)

    // Submodel mask: when non-empty, only nodes at these (bufX, bufY) positions
    // will have their channel data written by getColors(). All other nodes write zero.
    std::set<std::pair<int,int>> _submodelMask;
    bool _hasSubmodelMask = false;

    // Batch mode: when true, calcOutput() only processes pixels at node
    // positions instead of the full buffer. See setBatchMode().
    bool _batchMode = false;

    // Sorted unique pixel indices for node positions (bufY * bufferWi + bufX).
    // Populated in constructor. Used by calcOutput() in batch mode.
    std::vector<int> _nodePixelIndices;

    // Group spatial layout: combined group buffer dimensions and per-node
    // spatial positions for "Per Preview" / "Horizontal Stack" / etc. styles.
    // Populated via setGroupSpatialLayout(). Used by prepareBufferStyle() and
    // expandBufferStyle() to reshape group layers to the combined geometry.
    // Only applies to the first _spatialGroupLayerCount layers (group layers).
    int _spatialBufW = 0;
    int _spatialBufH = 0;
    size_t _spatialGroupLayerCount = 0;
    std::vector<std::pair<int,int>> _spatialNodePositions;

    // Sparkle state: per-node random counters
    std::vector<uint16_t> _sparkleState;

    // Dimming curve (gamma/brightness LUT) for this model
    NativeDimmingCurve _dimmingCurve;

    // GPU-accelerated blending via Metal compute shaders.
    // Lazily initialized on first use if Metal is available.
    std::unique_ptr<MetalBlendingCompute> _metalCompute;
    bool _metalComputeInitialized = false;

    // Attempt GPU-accelerated blending. Returns true if GPU path was used.
    // Falls back to CPU if Metal is unavailable or the dispatch fails.
    bool calcOutputGPU(const std::vector<bool>& validLayers);
};

} // namespace xlEngine
