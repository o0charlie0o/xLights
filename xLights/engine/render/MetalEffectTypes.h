/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

// MetalEffectTypes.h
//
// Shared param structs and helper functions for Metal compute shader effects.
// Include this from both NativeEffectShaders.metal and MetalEffectCompute.h
// to keep struct definitions in sync.

#ifndef MetalEffectTypes_h
#define MetalEffectTypes_h

#include <metal_stdlib>
using namespace metal;

// =========================================================================
// Shared data types — must match MetalEffectCompute.h
// =========================================================================

struct OnParams {
    uint width;
    uint height;
    uint totalPixels;
    float startIntensity;   // 0.0-1.0
    float endIntensity;     // 0.0-1.0
    float effectPosition;   // 0.0-1.0 (position within effect duration)
    uint shimmer;           // 0 or 1
    uint isShimmerOdd;      // 0 or 1 (true on odd frames)
};

struct ColorWashParams {
    uint width;
    uint height;
    uint totalPixels;
    float effectPosition;   // 0.0-1.0 with cycles applied
    uint horizFade;         // 0 or 1
    uint vertFade;          // 0 or 1
    uint reverseFades;      // 0 or 1
    uint shimmerBlack;      // 0 or 1 (true on shimmer odd frames)
    uint paletteSize;
    uint circularPalette;   // 0 or 1
};

struct BarsParams {
    uint width;
    uint height;
    uint totalPixels;
    uint direction;
    uint barCount;
    uint colorcnt;
    uint highlight;
    uint useFirstColorForHighlight;
    uint show3D;
    uint gradient;
    uint paletteSize;
    float position;
    float center;
    uint barDim;
    uint blockDim;
    int  fOffset;
    int  newCenter;
};

struct ButterflyParams {
    uint width;
    uint height;
    uint totalPixels;
    uint style;             // 1-10
    uint chunks;            // 1-10
    uint skip;              // 2-10
    uint colorScheme;       // 0=Rainbow, 1=Palette
    float offset;           // direction-adjusted time offset
    int curState;           // (curPeriod - curEffStartPer) * speed * frameTimeInMs / 50
    float plasmaTime;       // plasma time for styles 6-10
    uint paletteSize;
    uint circularPalette;   // 0 or 1
};

struct PlasmaParams {
    uint width;
    uint height;
    uint totalPixels;
    uint style;             // 1-6
    uint lineDensity;       // 1-10
    uint colorScheme;       // 0=Normal, 1-4=Presets
    float time;
    float sinTime5;         // sin(time / 5.0)
    float cosTime3;         // cos(time / 3.0)
    float sinTime2;         // sin(time / 2.0)
    uint paletteSize;
    uint circularPalette;
};

struct ShimmerParams {
    uint width;
    uint height;
    uint totalPixels;
    uint colorIdx;       // palette index for uniform mode
    uint paletteSize;    // number of colors in palette
    uint useAllColors;   // 0 or 1
    uint frameSeed;      // deterministic seed for per-pixel random
};

struct WaveParams {
    uint width;
    uint height;
    uint totalPixels;
    uint waveType;          // 0=Sine, 1=Triangle, 2=Square, 3=DecaySine
    uint fillColor;         // 0=Solid, 1=Rainbow, 2=Palette
    uint mirrorWave;        // 0 or 1
    uint numberWaves;       // 180-3600
    uint thicknessWave;     // 0-100
    uint waveHeight;        // 0-100
    uint waveDirection;     // 0=Right-to-Left, 1=Left-to-Right
    float state;            // animation state
    float yc;               // BufferHt / 2.0
    float r;                // radius
    int roundedWaveYOffset; // Y offset in pixels
    uint paletteSize;
    uint circularPalette;   // 0 or 1
    float hsv0_h;
    float hsv0_s;
    float hsv0_v;
};

struct CurtainParams {
    uint width;
    uint height;
    uint totalPixels;
    uint edge;              // 0=left, 1=center, 2=right, 3=bottom, 4=middle, 5=top
    int  xlimit;            // horizontal pixel limit (after CurtainDir adjustment)
    int  ylimit;            // vertical pixel limit (after CurtainDir adjustment)
    uint swagLen;           // length of swag array
    uint paletteSize;
    uint circularPalette;   // 0 or 1
};

struct PinwheelParams {
    uint width;
    uint height;
    uint totalPixels;
    float pos;              // timing position
    float tmax;             // effective thickness in degrees
    float halfW;            // BufferWi / 2.0
    float halfH;            // BufferHt / 2.0
    float xc_adj_px;        // center X offset in pixels
    float yc_adj_px;        // center Y offset in pixels
    float max_radius;       // max arm radius in pixels
    float pinwheel_twist;   // twist amount
    float poffset;          // rotation offset
    uint pinwheel_arms;     // number of arms
    uint degrees_per_arm;   // 360 / pinwheel_arms
    uint pinwheel_rotation; // 1 = CW, 0 = CCW
    uint pw3dType;          // 0=None, 1=3D, 2=3D Inverted, 3=Sweep
    uint paletteSize;
    uint allowAlpha;        // 0 or 1
};

struct SpiralsParams {
    uint width;
    uint height;
    uint totalPixels;
    uint spiralCount;           // colorcnt * PaletteRepeat
    uint colorcnt;              // palette color count
    float deltaStrands;         // (float)width / spiralCount
    float spiralThickness;      // adjusted thickness (after grow/shrink)
    float spiralState;          // SpiralState / 10.0 (pre-divided)
    float rotation;             // Rotation value
    uint blend;                 // 0 or 1
    uint show3D;                // 0 or 1
    uint allowAlpha;            // 0 or 1
    float rotationRaw;          // raw Rotation value (for 3D direction check)
    uint paletteSize;
    uint circularPalette;       // 0
};

struct SpirographParams {
    uint width;
    uint height;
    uint totalPixels;
    float xc;              // center x
    float yc;              // center y
    float R;               // outer radius
    float r;               // inner radius
    float d;               // drawing distance
    int mod1440;           // state % 1440
    float lengthScaled;    // length * 18
    float stepCurve;       // curve sampling step
    float stepWidth;       // width sampling step
    float halfWidth;       // width / 2.0
    uint paletteSize;
    int d_mod;             // color distance modulus
    uint numCurveSamples;  // total curve sample count
    uint numWidthSamples;  // width samples per curve point
};

struct StrobeParams {
    uint width;
    uint height;
    uint totalPixels;
    uint strobeType;       // 1..4
    uint numDrawCommands;  // number of active strobe entries
    uint allowAlpha;       // 0 or 1
};

struct StrobeDrawCmd {
    int  x;           // center pixel x
    int  y;           // center pixel y
    uchar centerR;    // center pixel color
    uchar centerG;
    uchar centerB;
    uchar centerA;
    uchar surroundR;  // surrounding pixel color (dimmed)
    uchar surroundG;
    uchar surroundB;
    uchar surroundA;
    uint drawCenter;  // 1 if center should be drawn
    uint orientation; // 0 or 1 for type 2/4 random direction
};

struct TwinkleParams {
    uint width;
    uint height;
    uint totalPixels;
    uint count;             // twinkle percentage (2-100)
    uint steps;             // twinkle steps/duration (2-200)
    uint strobe;            // 0 or 1
    uint frameNumber;       // current frame index within effect
    uint seed;              // per-effect seed for deterministic randomness
    uint paletteSize;       // number of colors in palette
    uint allowAlpha;        // 0 or 1
};

struct SingleStrandParams {
    uint width;
    uint height;
    uint totalPixels;
    uint subType;           // 0=Skips, 1=Chase

    // --- Skips parameters ---
    int  bandSize;
    int  skipSize;
    int  startPos;
    int  direction;         // 0=Right, 1=Left, 2=FromMiddle, 3=ToMiddle
    float skipsPosition;
    uint paletteSize;

    // --- Chase parameters ---
    int  chaseWidth;
    int  scaledChaseWidth;
    int  numberChases;
    int  chaseDirection;
    uint colorScheme;       // 0=Rainbow, 1=Palette
    uint mirror;
    uint autoReverse;
    uint dualChases;
    uint isStatic;
    uint doubleEnd;
    uint fadeType;          // 0=None, 1=FromHead, 2=FromTail, 3=HeadAndTail, 4=Middle
    uint groupAll;
    float rtval;
    float dx;
    int  startState;
    float origV;
    uint bufferWi;
    uint bufferHt;
};

struct GarlandsParams {
    uint width;
    uint height;
    uint totalPixels;
    uint garlandType;       // 0-4
    uint spacing;           // 1-100
    uint dir;               // 0=Up, 1=Down, 2=Left, 3=Right
    uint buffMax;           // dimension along garland movement axis
    uint garlandWid;        // dimension across garland
    float pixelSpacing;     // computed pixel spacing
    float positionOffset;   // total * position
    uint paletteSize;
    uint circularPalette;   // 0 or 1
};

struct RippleParams {
    uint width;
    uint height;
    uint totalPixels;
    uint objectType;        // 0=Circle, 1=Square
    uint movement;          // 0=Explode, 1=Implode
    uint thickness;         // 1..100
    uint is3D;              // 0 or 1
    uint allowAlpha;        // 0 or 1
    float radius;           // current radius (circle)
    float radiusX;          // current radius X (square)
    float radiusY;          // current radius Y (square)
    float maxRadius;        // maximum radius
    int xc;                 // center X
    int yc;                 // center Y
    float baseH;            // HSV hue (0..1)
    float baseS;            // HSV saturation (0..1)
    float baseV;            // HSV value (0..1)
    uint baseR;             // RGB red (0..255)
    uint baseG;             // RGB green (0..255)
    uint baseB;             // RGB blue (0..255)
};

struct ShockwaveParams {
    uint width;
    uint height;
    uint totalPixels;
    float centerX;          // center X in pixel coords
    float centerY;          // center Y in pixel coords
    float radius1;          // inner radius of ring
    float radius2;          // outer radius of ring
    float radiusCenter;     // center of ring band
    float halfWidth;        // half ring width (for edge blend)
    uint blendEdges;        // 0 or 1
    uint allowAlpha;        // 0 or 1
    uint paletteSize;       // number of palette colors
    float effPosAdj;        // acceleration-adjusted effect position
};

struct FanParams {
    uint width;
    uint height;
    uint totalPixels;
    float centerX;
    float centerY;
    float radius1;
    float radius2;
    float maxRadius;
    float bladeDivAngle;
    float bladeWidthAngle;
    float colorAngle;
    float angleOffset;
    float elementAngle;
    float elementSize;
    float bladeAngle;
    float startAngle;
    uint reverseDir;
    uint blendEdges;
    uint allowAlpha;
    uint numColors;
};

struct MarqueeParams {
    uint width;
    uint height;
    uint totalPixels;
    int  bandSize;
    int  skipSize;
    int  thickness;
    int  stagger;
    int  speed;
    int  startOffset;
    int  corner_x1;
    int  corner_y1;
    int  corner_x2;
    int  corner_y2;
    int  xoffset_adj;
    int  yoffset_adj;
    int  sign;
    int  effPos;
    uint paletteSize;
    uint wrapX;
    uint wrapY;
};

// =========================================================================
// HSV <-> RGB conversion -- matches xLights Color.cpp exactly
// =========================================================================

// Optimized RGB->HSV from http://lolengine.net/blog/2013/01/13/fast-rgb-to-hsv
static float3 rgb_to_hsv(float3 rgb) {
    float r = rgb.r;
    float g = rgb.g;
    float b = rgb.b;

    float K = 0.0;
    if (g < b) {
        float tmp = g; g = b; b = tmp;
        K = -1.0;
    }
    float min_gb = b;
    if (r < g) {
        float tmp = r; r = g; g = tmp;
        K = -2.0 / 6.0 - K;
        min_gb = min(g, b);
    }
    float chroma = r - min_gb;
    float hue = abs(K + (g - b) / (6.0 * chroma + 1e-20));
    float saturation = chroma / (r + 1e-20);
    float value = r;
    return float3(hue, saturation, value);
}

// HSV->RGB matching xLights fromHSV() in Color.cpp
static float3 hsv_to_rgb(float3 hsv) {
    float h = clamp(hsv.x, 0.0, 1.0);
    float s = clamp(hsv.y, 0.0, 1.0);
    float v = clamp(hsv.z, 0.0, 1.0);

    if (s == 0.0) {
        return float3(v, v, v);
    }

    float hue6 = h * 6.0;
    int i = int(floor(hue6));
    float f = hue6 - float(i);
    float p = v * (1.0 - s);

    float r, g, b;
    switch (i) {
        case 6:
        case 0:
            r = v;
            g = v * (1.0 - s * (1.0 - f));
            b = p;
            break;
        case 1:
            r = v * (1.0 - s * f);
            g = v;
            b = p;
            break;
        case 2:
            r = p;
            g = v;
            b = v * (1.0 - s * (1.0 - f));
            break;
        case 3:
            r = p;
            g = v * (1.0 - s * f);
            b = v;
            break;
        case 4:
            r = v * (1.0 - s * (1.0 - f));
            g = p;
            b = v;
            break;
        default: // case 5
            r = v;
            g = p;
            b = v * (1.0 - s * f);
            break;
    }
    return float3(r, g, b);
}

// Apply brightness multiplier via HSV value channel
static uchar4 apply_brightness(float3 rgb, float brightness) {
    float3 hsv = rgb_to_hsv(rgb);
    hsv.z *= brightness;
    float3 result = hsv_to_rgb(hsv);
    return uchar4(uint8_t(result.r * 255.0),
                  uint8_t(result.g * 255.0),
                  uint8_t(result.b * 255.0),
                  255);
}

// =========================================================================
// Palette blending -- matches NativeRenderBuffer::GetMultiColorBlend()
// =========================================================================

// Blend between two colors by ratio (0.0 = c1, 1.0 = c2)
static float4 blend_colors(float4 c1, float4 c2, float ratio) {
    return float4(c1.r + (c2.r - c1.r) * ratio,
                  c1.g + (c2.g - c1.g) * ratio,
                  c1.b + (c2.b - c1.b) * ratio,
                  1.0);
}

static float4 get_multi_color_blend(float n, device const float4* palette,
                                     uint paletteSize, bool circular) {
    if (paletteSize <= 1) {
        return palette[0];
    }

    n = clamp(n, 0.0f, 0.99999f);
    float realidx = circular ? n * float(paletteSize) : n * float(paletteSize - 1);
    int coloridx1 = int(floor(realidx));
    int coloridx2 = (coloridx1 + 1) % int(paletteSize);
    float ratio = realidx - float(coloridx1);
    return blend_colors(palette[coloridx1], palette[coloridx2], ratio);
}

#endif
