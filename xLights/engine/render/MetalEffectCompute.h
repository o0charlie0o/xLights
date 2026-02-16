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

// MetalEffectCompute: GPU-accelerated effect rendering via Metal compute shaders.
//
// This class provides a GPU rendering path for effects that are
// embarrassingly parallel (per-pixel computation with no frame state).
// The CPU effect code remains the fallback for small buffers, unsupported
// effects, or systems without Metal.
//
// Thread safety: Thread-safe for concurrent calls from different threads.
// Each call creates its own command buffer (lightweight). Pipeline state
// objects are immutable and shared safely.
//
// Usage:
//   auto& gpu = MetalEffectCompute::shared();
//   if (gpu.isAvailable() && totalPixels >= gpu.minPixelThreshold()) {
//       gpu.renderOn(outputPixels, width, height, params, palette);
//   }

#include <cstdint>
#include <cstddef>
#include <vector>
#include "../../Color.h"

namespace xlEngine {

// Parameter structs — must match NativeEffectShaders.metal layout exactly.
// Packed as plain uint/float for Metal buffer compatibility.

struct GPUOnParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    float startIntensity;   // 0.0-1.0
    float endIntensity;     // 0.0-1.0
    float effectPosition;   // 0.0-1.0
    uint32_t shimmer;       // 0 or 1
    uint32_t isShimmerOdd;  // 0 or 1
};

struct GPUColorWashParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    float effectPosition;   // 0.0-1.0 with cycles applied
    uint32_t horizFade;     // 0 or 1
    uint32_t vertFade;      // 0 or 1
    uint32_t reverseFades;  // 0 or 1
    uint32_t shimmerBlack;  // 0 or 1
    uint32_t paletteSize;
    uint32_t circularPalette; // 0 or 1
};

struct GPUBarsParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    uint32_t direction;         // 0=up,1=down,2=expand,3=compress,4=left,5=right,6=H-expand,7=H-compress,8=altUp,9=altDown,10=altLeft,11=altRight,12=customHorz,13=customVert
    uint32_t barCount;          // paletteRepeat * colorcnt (total bars)
    uint32_t colorcnt;          // number of palette colors (adjusted for highlight)
    uint32_t highlight;         // 0 or 1
    uint32_t useFirstColorForHighlight; // 0 or 1
    uint32_t show3D;            // 0 or 1
    uint32_t gradient;          // 0 or 1
    uint32_t paletteSize;       // actual number of colors in palette buffer
    float    position;          // GetEffectTimeIntervalPosition(cycles)
    float    center;            // center offset (-100..100 as raw value)
    uint32_t barDim;            // barHt or barWi depending on direction
    uint32_t blockDim;          // blockHt or blockWi (colorcnt * barDim)
    int32_t  fOffset;           // f_offset computed on CPU
    int32_t  newCenter;         // center in pixel coords
};

struct GPUButterflyParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    uint32_t style;         // 1-10
    uint32_t chunks;        // 1-10
    uint32_t skip;          // 2-10
    uint32_t colorScheme;   // 0=Rainbow, 1=Palette
    float offset;           // direction-adjusted time offset
    int32_t curState;       // (curPeriod - curEffStartPer) * speed * frameTimeInMs / 50
    float plasmaTime;       // plasma time for styles 6-10
    uint32_t paletteSize;
    uint32_t circularPalette; // 0 or 1 (always 0 for butterfly but included for get_multi_color_blend)
};

struct GPUPlasmaParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    uint32_t style;         // 1-6 (Plasma algorithm)
    uint32_t lineDensity;   // 1-10
    uint32_t colorScheme;   // 0=Normal, 1=Preset1, 2=Preset2, 3=Preset3, 4=Preset4
    float time;             // (state + 1.0) / Speed_plasma
    float sinTime5;         // sin(time / 5.0)
    float cosTime3;         // cos(time / 3.0)
    float sinTime2;         // sin(time / 2.0)
    uint32_t paletteSize;
    uint32_t circularPalette; // 0 or 1
};

struct GPUShimmerParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    uint32_t colorIdx;       // palette index for uniform mode
    uint32_t paletteSize;    // number of colors in palette
    uint32_t useAllColors;   // 0 or 1 — random color per pixel
    uint32_t frameSeed;      // deterministic seed for per-pixel random (curPeriod)
};

struct GPUWaveParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    uint32_t waveType;          // 0=Sine, 1=Triangle, 2=Square, 3=DecaySine
    uint32_t fillColor;         // 0=Solid, 1=Rainbow, 2=Palette
    uint32_t mirrorWave;        // 0 or 1
    uint32_t numberWaves;       // 180-3600, default 900
    uint32_t thicknessWave;     // 0-100, default 5
    uint32_t waveHeight;        // 0-100, default 50
    uint32_t waveDirection;     // 0=Right-to-Left, 1=Left-to-Right
    float state;                // (curPeriod - curEffStartPer) * wspeed * (frameTimeInMs / 50.0)
    float yc;                   // BufferHt / 2.0
    float r;                    // radius (yc, or decayed for DecaySine)
    int32_t roundedWaveYOffset; // rounded Y offset in pixels
    uint32_t paletteSize;
    uint32_t circularPalette;   // 0 or 1
    // HSV color 0 packed as floats (for Solid fill)
    float hsv0_h;
    float hsv0_s;
    float hsv0_v;
};

struct GPUCurtainParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    uint32_t edge;          // 0=left, 1=center, 2=right, 3=bottom, 4=middle, 5=top
    int32_t  xlimit;        // horizontal pixel limit (after CurtainDir applied)
    int32_t  ylimit;        // vertical pixel limit (after CurtainDir applied)
    uint32_t swagLen;       // length of swag array (0 = no swag)
    uint32_t paletteSize;
    uint32_t circularPalette; // always 1 for curtain (matches CPU GetMultiColorBlend call)
};

struct GPUPinwheelParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    float pos;              // timing position (frame-based, not 0-1)
    float tmax;             // effective thickness in degrees
    float halfW;            // BufferWi / 2.0
    float halfH;            // BufferHt / 2.0
    float xc_adj_px;        // center X offset in pixels
    float yc_adj_px;        // center Y offset in pixels
    float max_radius;       // xc_half * armsize
    float pinwheel_twist;   // twist amount (float, from int slider)
    float poffset;          // rotation offset (float, from int slider)
    uint32_t pinwheel_arms; // number of arms (>=1)
    uint32_t degrees_per_arm; // 360 / pinwheel_arms
    uint32_t pinwheel_rotation; // 1 = CW, 0 = CCW
    uint32_t pw3dType;      // 0=None, 1=3D, 2=3D Inverted, 3=Sweep
    uint32_t paletteSize;
    uint32_t allowAlpha;    // 0 or 1
};

struct GPUSpiralsParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    uint32_t spiralCount;       // colorcnt * PaletteRepeat
    uint32_t colorcnt;          // palette color count
    float deltaStrands;         // (float)width / spiralCount
    float spiralThickness;      // adjusted thickness (after grow/shrink)
    float spiralState;          // SpiralState / 10.0 (pre-divided)
    float rotation;             // Rotation value (already divided by 10)
    uint32_t blend;             // 0 or 1
    uint32_t show3D;            // 0 or 1
    uint32_t allowAlpha;        // 0 or 1
    float rotationRaw;          // raw Rotation value (for 3D direction)
    uint32_t paletteSize;       // same as colorcnt
    uint32_t circularPalette;   // 0 (spirals uses non-circular blend)
};

struct GPUSpirographParams {
    uint32_t width;         // buffer width
    uint32_t height;        // buffer height
    uint32_t totalPixels;   // width * height (used to clear output)
    float xc;               // center x = width / 2.0
    float yc;               // center y = height / 2.0
    float R;                // outer radius (scaled)
    float r;                // inner radius (scaled, clamped, nonzero)
    float d;                // drawing distance (with animation applied)
    int32_t mod1440;        // state % 1440
    float lengthScaled;     // length * 18.0
    float stepCurve;        // 1.0 / width_param (curve sampling step)
    float stepWidth;        // 1.0 / (log10(width_param) + 1.0)
    float halfWidth;        // width_param / 2.0
    uint32_t paletteSize;   // number of palette colors
    int32_t d_mod;          // bufferWi / colorCount (for color index calc)
    uint32_t numCurveSamples;  // total threads = ceil(lengthScaled / stepCurve)
    uint32_t numWidthSamples;  // width samples per curve point
};

struct GPUStrobeParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    uint32_t strobeType;       // 1..4
    uint32_t numDrawCommands;  // number of active strobe entries
    uint32_t allowAlpha;       // 0 or 1
};

// One draw command per active strobe entry.
// Pre-computed on CPU from the strobe cache.
struct GPUStrobeDrawCmd {
    int32_t  x;           // center pixel x
    int32_t  y;           // center pixel y
    uint8_t  centerR;     // center pixel color (full brightness)
    uint8_t  centerG;
    uint8_t  centerB;
    uint8_t  centerA;
    uint8_t  surroundR;   // surrounding pixel color (dimmed by duration)
    uint8_t  surroundG;
    uint8_t  surroundB;
    uint8_t  surroundA;
    uint32_t drawCenter;  // 1 if duration > 0 (draw center pixel)
    uint32_t orientation; // for type 2/4: 0=vertical/cross, 1=horizontal/X
};

struct GPUTwinkleParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    uint32_t count;         // twinkle percentage (2-100)
    uint32_t steps;         // twinkle steps/duration (2-200)
    uint32_t strobe;        // 0 or 1 (strobe mode: only peak frame lit)
    uint32_t frameNumber;   // current frame index within effect (curPeriod - curEffStartPer)
    uint32_t seed;          // per-effect seed for deterministic randomness
    uint32_t paletteSize;   // number of colors in palette
    uint32_t allowAlpha;    // 0 or 1 (use alpha channel vs HSV brightness)
};

struct GPUSingleStrandParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    uint32_t subType;           // 0=Skips, 1=Chase

    // --- Skips parameters (subType 0) ---
    int32_t  bandSize;
    int32_t  skipSize;
    int32_t  startPos;          // 1-based from UI
    int32_t  direction;         // 0=Right, 1=Left, 2=FromMiddle, 3=ToMiddle
    float    skipsPosition;     // effectPosition * (advances+1) * 0.99
    uint32_t paletteSize;

    // --- Chase parameters (subType 1) ---
    int32_t  chaseWidth;        // width (possibly halved for Mirror)
    int32_t  scaledChaseWidth;  // width * chaseSize / 100
    int32_t  numberChases;
    int32_t  chaseDirection;    // 0 or 1
    uint32_t colorScheme;       // 0=Rainbow, 1=Palette
    uint32_t mirror;            // 0 or 1
    uint32_t autoReverse;       // 0 or 1
    uint32_t dualChases;        // 0 or 1
    uint32_t isStatic;          // 0 or 1
    uint32_t doubleEnd;         // 0 or 1
    uint32_t fadeType;          // 0=None, 1=FromHead, 2=FromTail, 3=HeadAndTail, 4=Middle
    uint32_t groupAll;          // 0 or 1
    float    rtval;             // computed chase time position
    float    dx;                // width / numberChases
    int32_t  startState;        // computed start state
    float    origV;             // original HSV value of palette[0] (for fade)
    uint32_t bufferWi;          // original buffer width (before mirror halving)
    uint32_t bufferHt;          // original buffer height
};

struct GPUGarlandsParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    uint32_t garlandType;       // 0-4
    uint32_t spacing;           // 1-100
    uint32_t dir;               // 0=Up, 1=Down, 2=Left, 3=Right (after bounce fold)
    uint32_t buffMax;           // buffer dimension along garland axis
    uint32_t garlandWid;        // buffer dimension across garland
    float    pixelSpacing;      // computed: max(2.0, spacing * buffMax / 100.0)
    float    positionOffset;    // total * position
    uint32_t paletteSize;
    uint32_t circularPalette;   // 0 or 1
};

struct GPURippleParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    uint32_t objectType;     // 0=Circle, 1=Square
    uint32_t movement;       // 0=Explode, 1=Implode
    uint32_t thickness;      // 1..100
    uint32_t is3D;           // 0 or 1
    uint32_t allowAlpha;     // 0 or 1
    float radius;            // current radius (for circle)
    float radiusX;           // current radius X (for square)
    float radiusY;           // current radius Y (for square)
    float maxRadius;         // maximum radius
    int32_t xc;              // center X
    int32_t yc;              // center Y
    float baseH;             // HSV hue of selected color (0..1)
    float baseS;             // HSV saturation (0..1)
    float baseV;             // HSV value (0..1)
    uint32_t baseR;          // RGB red (0..255)
    uint32_t baseG;          // RGB green (0..255)
    uint32_t baseB;          // RGB blue (0..255)
};

struct GPUShockwaveParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    float centerX;          // center X in pixel coords
    float centerY;          // center Y in pixel coords
    float radius1;          // inner radius of ring (after all scaling/accel)
    float radius2;          // outer radius of ring
    float radiusCenter;     // center of ring band
    float halfWidth;        // half the ring width (for edge blending)
    uint32_t blendEdges;    // 0 or 1
    uint32_t allowAlpha;    // 0 or 1 (use alpha vs HSV dimming for edges)
    uint32_t paletteSize;   // number of palette colors
    float effPosAdj;        // acceleration-adjusted effect position (0.0-1.0)
};

struct GPUFanParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    float centerX;          // adjusted pixel center X (float)
    float centerY;          // adjusted pixel center Y (float)
    float radius1;          // inner radius (after scale + ramp)
    float radius2;          // outer radius (after scale + ramp)
    float maxRadius;        // max(start_radius, end_radius) after scale
    float bladeDivAngle;    // 360.0 / num_blades (degrees)
    float bladeWidthAngle;  // blade_div_angle * blade_width / 100.0
    float colorAngle;       // blade_width_angle / num_colors
    float angleOffset;      // eff_pos_adj * revolutions
    float elementAngle;     // color_angle / num_elements
    float elementSize;      // element_angle * element_width / 100.0
    float bladeAngle;       // twist angle parameter (degrees)
    float startAngle;       // starting angle offset (degrees)
    uint32_t reverseDir;    // 0 or 1
    uint32_t blendEdges;    // 0 or 1
    uint32_t allowAlpha;    // 0 or 1
    uint32_t numColors;     // palette color count
};

struct GPUMarqueeParams {
    uint32_t width;
    uint32_t height;
    uint32_t totalPixels;
    int32_t  bandSize;       // size of colored band in repeating pattern
    int32_t  skipSize;       // size of gap (transparent) in repeating pattern
    int32_t  thickness;      // number of concentric rectangle rings
    int32_t  stagger;        // stagger offset between rings
    int32_t  speed;          // mSpeed parameter
    int32_t  startOffset;    // mStart parameter
    int32_t  corner_x1;     // initial corner (always 0 before offset)
    int32_t  corner_y1;     // initial corner (always 0 before offset)
    int32_t  corner_x2;     // scaled width corner
    int32_t  corner_y2;     // scaled height corner
    int32_t  xoffset_adj;   // x center offset (pixels)
    int32_t  yoffset_adj;   // y center offset (pixels)
    int32_t  sign;           // +1 or -1 for direction
    int32_t  effPos;         // effective position: (mSpeed * eff_pos) / 5
    uint32_t paletteSize;    // number of colors in palette
    uint32_t wrapX;          // 0 or 1
    uint32_t wrapY;          // 0 or 1
};

struct MetalEffectComputeImpl;

class MetalEffectCompute {
public:
    // Access the shared singleton instance.
    // Lazily initializes Metal on first call.
    static MetalEffectCompute& shared();

    ~MetalEffectCompute();

    MetalEffectCompute(const MetalEffectCompute&) = delete;
    MetalEffectCompute& operator=(const MetalEffectCompute&) = delete;

    // Returns true if Metal compute is available on this system.
    bool isAvailable() const;

    // Minimum pixel count for GPU rendering to be worthwhile.
    // Below this threshold, CPU rendering is faster due to dispatch overhead.
    static constexpr int minPixelThreshold() { return 5000; }

    // Render the On effect directly into the output pixel buffer.
    // outputPixels must be at least width * height * 4 bytes (RGBA).
    // palette is an array of {r,g,b,a} float4 colors (0.0-1.0 range).
    // Returns true if GPU rendering succeeded.
    bool renderOn(xlColor* outputPixels, int width, int height,
                  const GPUOnParams& params,
                  const std::vector<float>& palette);

    // Render the ColorWash effect directly into the output pixel buffer.
    bool renderColorWash(xlColor* outputPixels, int width, int height,
                         const GPUColorWashParams& params,
                         const std::vector<float>& palette);

    // Render the Bars effect directly into the output pixel buffer.
    bool renderBars(xlColor* outputPixels, int width, int height,
                    const GPUBarsParams& params,
                    const std::vector<float>& palette);

    // Render the Butterfly effect directly into the output pixel buffer.
    bool renderButterfly(xlColor* outputPixels, int width, int height,
                         const GPUButterflyParams& params,
                         const std::vector<float>& palette);

    // Render the Plasma effect directly into the output pixel buffer.
    bool renderPlasma(xlColor* outputPixels, int width, int height,
                      const GPUPlasmaParams& params,
                      const std::vector<float>& palette);

    // Render the Shimmer effect directly into the output pixel buffer.
    // The CPU caller pre-computes duty cycle: if the frame is black,
    // the caller simply skips the GPU dispatch entirely.
    bool renderShimmer(xlColor* outputPixels, int width, int height,
                       const GPUShimmerParams& params,
                       const std::vector<float>& palette);

    // Render the Wave effect directly into the output pixel buffer.
    // Supports wave types 0-3 (Sine, Triangle, Square, DecaySine).
    // IvyFractal (type 4) must fall back to CPU.
    bool renderWave(xlColor* outputPixels, int width, int height,
                    const GPUWaveParams& params,
                    const std::vector<float>& palette);

    // Render the Curtain effect directly into the output pixel buffer.
    // swagArray contains pre-computed swag height values (may be empty).
    bool renderCurtain(xlColor* outputPixels, int width, int height,
                       const GPUCurtainParams& params,
                       const std::vector<float>& palette,
                       const std::vector<int32_t>& swagArray);

    // Render the Pinwheel effect (New Render Method only).
    bool renderPinwheel(xlColor* outputPixels, int width, int height,
                        const GPUPinwheelParams& params,
                        const std::vector<float>& palette);

    // Render the Spirals effect directly into the output pixel buffer.
    bool renderSpirals(xlColor* outputPixels, int width, int height,
                       const GPUSpiralsParams& params,
                       const std::vector<float>& palette);

    // Render the Spirograph effect directly into the output pixel buffer.
    // Caller must clear the buffer to black before calling (or the kernel handles it).
    bool renderSpirograph(xlColor* outputPixels, int width, int height,
                          const GPUSpirographParams& params,
                          const std::vector<float>& palette);

    // Render the Strobe effect directly into the output pixel buffer.
    // drawCmds contains pre-computed draw commands (one per active strobe entry).
    // Returns true if GPU rendering succeeded.
    bool renderStrobe(xlColor* outputPixels, int width, int height,
                      const GPUStrobeParams& params,
                      const std::vector<GPUStrobeDrawCmd>& drawCmds);

    // Render the Twinkle effect directly into the output pixel buffer.
    bool renderTwinkle(xlColor* outputPixels, int width, int height,
                       const GPUTwinkleParams& params,
                       const std::vector<float>& palette);

    bool renderSingleStrand(xlColor* outputPixels, int width, int height,
                            const GPUSingleStrandParams& params,
                            const std::vector<float>& palette);

    // Render the Garlands effect directly into the output pixel buffer.
    bool renderGarlands(xlColor* outputPixels, int width, int height,
                        const GPUGarlandsParams& params,
                        const std::vector<float>& palette);

    // Render the Ripple effect (Circle and Square shapes only).
    // Other shapes should fall back to CPU rendering.
    bool renderRipple(xlColor* outputPixels, int width, int height,
                      const GPURippleParams& params);

    // Render the Shockwave effect directly into the output pixel buffer.
    bool renderShockwave(xlColor* outputPixels, int width, int height,
                         const GPUShockwaveParams& params,
                         const std::vector<float>& palette);

    // Render the Fan effect directly into the output pixel buffer.
    bool renderFan(xlColor* outputPixels, int width, int height,
                   const GPUFanParams& params,
                   const std::vector<float>& palette);

    // Render the Marquee effect directly into the output pixel buffer.
    bool renderMarquee(xlColor* outputPixels, int width, int height,
                       const GPUMarqueeParams& params,
                       const std::vector<float>& palette);

private:
    MetalEffectCompute();
    MetalEffectComputeImpl* _impl;
};

} // namespace xlEngine
