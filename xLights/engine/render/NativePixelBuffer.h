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
#include <vector>
#include <set>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <utility>

#include "NativeRenderBuffer.h"
#include "NativeColorBlending.h"
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
    int inTransitionType = 0;
    int outTransitionType = 0;
    float fadeInSteps = 0.0f;
    float fadeOutSteps = 0.0f;

    // Blur
    int blur = 1;

    // Chroma key
    bool isChromaKey = false;
    xlColor chromaKeyColour = xlBLACK;
    int chromaSensitivity = 1;

    // Sparkle color
    xlColor sparklesColour = xlWHITE;
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

        LayerState(IRenderContext* ctx, int w, int h)
            : buffer(ctx, w, h) {}
    };

    // Apply Gaussian blur to a layer's buffer.
    void applyBlur(LayerState& layer);

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

    // Sparkle state: per-node random counters
    std::vector<uint16_t> _sparkleState;

    // Dimming curve (gamma/brightness LUT) for this model
    NativeDimmingCurve _dimmingCurve;
};

} // namespace xlEngine
