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

// NativeRenderBuffer: wx-free pixel buffer for the native macOS render pipeline.
//
// This class provides the same method signatures that effects expect from
// RenderBuffer, but without any wxWidgets dependencies. Pixel storage uses
// std::vector<xlColor> and all drawing primitives are implemented with
// standard C++ algorithms (Bresenham line, midpoint circle, etc.).
//
// Effects compiled into the native build call the same API they always have:
//   buffer.SetPixel(x, y, color);
//   buffer.GetMultiColorBlend(n, circular, color);
//   float pos = buffer.GetEffectTimeIntervalPosition();
//
// The only difference is the constructor: instead of taking xLightsFrame*,
// it takes IRenderContext* for audio/timing access.
//
// Thread safety: Individual NativeRenderBuffer instances are NOT thread-safe.
// Each render thread should have its own buffer instance (one per layer per model).

#include <vector>
#include <map>
#include <string>
#include <cstdint>
#include <cmath>
#include <cstdlib>
#include <utility>
#include <algorithm>

#include "../../Color.h"

namespace xlEngine {

struct IRenderContext;

// Forward declaration — effects that use the render cache store state here
class EffectRenderCache {
public:
    EffectRenderCache() = default;
    virtual ~EffectRenderCache() = default;
};

class NativeRenderBuffer {
public:
    // Construct a render buffer with given dimensions and optional context.
    // context may be nullptr if audio/timing access is not needed.
    NativeRenderBuffer(IRenderContext* context, int bufferWi, int bufferHt);
    ~NativeRenderBuffer();

    // Copy constructor (creates a snapshot of pixel data)
    NativeRenderBuffer(const NativeRenderBuffer& other);

    // Re-initialize with new dimensions. Clears all pixel data.
    void InitBuffer(int newBufferHt, int newBufferWi, const std::string& bufferTransform);

    // =========================================================================
    // Pixel access — 0,0 is lower left
    // =========================================================================

    void SetPixel(int x, int y, const xlColor& color, bool wrap = false, bool useAlpha = false);
    void SetPixel(int x, int y, const HSVValue& hsv, bool wrap = false);

    // Bounds-checked pixel read
    void GetPixel(int x, int y, xlColor& color) const;
    const xlColor& GetPixel(int x, int y) const;

    // Direct access — caller must ensure x,y are in bounds
    void SetPixelDirect(int x, int y, const xlColor& color) {
        pixels[y * BufferWi + x] = color;
    }
    const xlColor& GetPixelDirect(int x, int y) const {
        return pixels[y * BufferWi + x];
    }

    void CopyPixel(int srcx, int srcy, int destx, int desty);
    void ProcessPixel(int x, int y, const xlColor& color, bool wrap_x = false, bool wrap_y = false);

    uint32_t GetPixelCount() const { return static_cast<uint32_t>(pixelVector.size()); }
    xlColor* GetPixels() { return pixels; }
    const xlColor* GetPixels() const { return pixels; }

    // =========================================================================
    // Temp buffer (used by some effects as scratch space)
    // =========================================================================

    void ClearTempBuf();
    void SetTempPixel(int x, int y, const xlColor& color);
    void SetTempPixel(int x, int y, const xlColor& color, int alpha);
    void GetTempPixel(int x, int y, xlColor& color) const;
    const xlColor& GetTempPixel(int x, int y) const;
    const xlColor& GetTempPixelRGB(int x, int y) const;
    xlColor* GetTempBuf() { return tempbuf; }
    void CopyTempBufToPixels();
    void CopyPixelsToTempBuf();

    // =========================================================================
    // Buffer operations
    // =========================================================================

    void Clear();
    void Fill(const xlColor& color);
    void AlphaBlend(const NativeRenderBuffer& src);

    // =========================================================================
    // Drawing primitives
    // =========================================================================

    void DrawHLine(int y, int xstart, int xend, const xlColor& color, bool wrap = false);
    void DrawVLine(int x, int ystart, int yend, const xlColor& color, bool wrap = false);
    void DrawBox(int x1, int y1, int x2, int y2, const xlColor& color, bool wrap = false, bool useAlpha = false);
    void DrawLine(int x1, int y1, int x2, int y2, const xlColor& color, bool useAlpha = false);
    void DrawThickLine(int x1, int y1, int x2, int y2, const xlColor& color, int thickness, bool useAlpha = false);
    void DrawThickLine(int x1, int y1, int x2, int y2, const xlColor& color, bool direction);
    void DrawCircle(int xc, int yc, int radius, const xlColor& color, bool filled = false, bool wrap = false);
    void DrawFadingCircle(int xc, int yc, int radius, const xlColor& color, bool wrap = false);
    void FillConvexPoly(const std::vector<std::pair<int, int>>& poly, const xlColor& color);

    // =========================================================================
    // Math helpers (static, matching legacy RenderBuffer signatures)
    // =========================================================================

    static inline float sin(float rad) { return std::sin(rad); }
    static inline float cos(float rad) { return std::cos(rad); }
    static inline float cot(float rad) { return std::cos(rad) / std::sin(rad); }
    static inline float acot(float rad) { return static_cast<float>(M_PI) / 2.0f - std::atan(rad); }

    // =========================================================================
    // Color blending
    // =========================================================================

    uint8_t ChannelBlend(uint8_t c1, uint8_t c2, float ratio) const;
    void Get2ColorBlend(int coloridx1, int coloridx2, float ratio, xlColor& color);
    void Get2ColorBlend(xlColor& color, xlColor color2, float ratio);
    void Get2ColorAlphaBlend(const xlColor& c1, const xlColor& c2, float ratio, xlColor& color);
    void GetMultiColorBlend(float n, bool circular, xlColor& color, int reserveColors = 0);
    HSVValue Get2ColorAdditive(HSVValue& hsv1, HSVValue& hsv2) const;

    // =========================================================================
    // Color utilities
    // =========================================================================

    void SetRangeColor(const HSVValue& hsv1, const HSVValue& hsv2, HSVValue& newhsv);
    double RandomRange(double num1, double num2) const;
    void Color2HSV(const xlColor& color, HSVValue& hsv) const;

    // =========================================================================
    // Acceleration / easing
    // =========================================================================

    double calcAccel(double ratio, double accel) const;

    // =========================================================================
    // Effect timing
    // =========================================================================

    float GetEffectTimeIntervalPosition() const;
    float GetEffectTimeIntervalPosition(float cycles) const;

    void SetState(int period, bool reset);
    void SetEffectDuration(int startMsec, int endMsec);
    void GetEffectPeriods(int& startPer, int& endPer) const;
    void SetFrameTimeInMs(int ms) { frameTimeInMs = ms; }
    long GetStartTimeMS() const { return static_cast<long>(curEffStartPer) * frameTimeInMs; }
    long GetEndTimeMS() const { return static_cast<long>(curEffEndPer) * frameTimeInMs; }

    // =========================================================================
    // Palette
    // =========================================================================

    void SetPalette(xlColorVector& colors);
    size_t GetColorCount() const;

    // Palette color vector — effects read this directly
    xlColorVector palette;
    hsvVector paletteHSV;

    // Convenience HSV member used by some effects
    HSVValue hsv;

    // =========================================================================
    // Alpha channel support
    // =========================================================================

    bool allowAlpha = false;
    void SetAllowAlphaChannel(bool a) { allowAlpha = a; }

    // =========================================================================
    // Audio access
    // =========================================================================

    // Returns AudioManager* via the IRenderContext (cast from void*).
    // Returns nullptr if no context or no audio loaded.
    void* GetMedia() const;

    // =========================================================================
    // Public state (read by effects)
    // =========================================================================

    int BufferHt = 1;
    int BufferWi = 1;

    int curPeriod = 0;
    int curEffStartPer = 0;
    int curEffEndPer = 0;
    int frameTimeInMs = 50;

    std::string cur_model;  // model name currently being rendered

    bool needToInit = false;
    bool isTransformed = false;

    int fadeinsteps = 0;
    int fadeoutsteps = 0;

    // Effect render cache — effects store per-effect state here
    std::map<int, EffectRenderCache*> infoCache;

    // GPU render data slot (reserved for future use)
    void* gpuRenderData = nullptr;

private:
    IRenderContext* _context;

    xlColorVector pixelVector;
    xlColorVector tempbufVector;
    xlColor* pixels = nullptr;
    xlColor* tempbuf = nullptr;

    // Internal helper: generate random 0..1
    static double rand01() {
        return static_cast<double>(std::rand()) / static_cast<double>(RAND_MAX);
    }
};

} // namespace xlEngine
