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

// Native macOS drawing contexts using CoreGraphics/CoreText.
// These replace the wx-based PathDrawingContext and TextDrawingContext
// for the native build (XLIGHTS_NATIVE). No wxWidgets dependencies.

#include <string>
#include <vector>
#include <queue>
#include <mutex>
#include <utility>
#include <cstdint>

class xlColor;

// Opaque CoreGraphics/CoreText types (avoid importing CG headers in header)
typedef struct CGContext* CGContextRef;
typedef struct CGPath* CGMutablePathRef;
typedef const struct __CTFont* CTFontRef;
typedef struct CGColorSpace* CGColorSpaceRef;

// ---------------------------------------------------------------------------
// NativePathDrawingContext
//
// Backed by a CGBitmapContext (RGBA, 8-bit per component, premultiplied alpha).
// Provides path creation, stroking, filling, and pixel extraction.
// Coordinate system is flipped to top-left origin (matching xLights convention).
// ---------------------------------------------------------------------------
class NativePathDrawingContext {
public:
    NativePathDrawingContext();
    ~NativePathDrawingContext();

    // Lifecycle
    void Initialize(int width, int height);
    void ResetSize(int width, int height);
    void Clear();

    // Dimensions
    int GetWidth() const { return _width; }
    int GetHeight() const { return _height; }

    // Path operations
    CGMutablePathRef CreatePath();
    void StrokePath(CGMutablePathRef path);
    void FillPath(CGMutablePathRef path, int fillRule); // 0 = winding, 1 = even-odd

    // Appearance
    void SetPen(const xlColor& color, float width);
    void SetBrush(const xlColor& color);
    void SetGradientBrush(const xlColor& color1, const xlColor& color2);

    // Pixel extraction
    std::vector<xlColor>* FlushAndGetPixels();
    void CopyToRenderBuffer(xlColor* destPixels, int bufW, int bufH);

    // Static pool access (mirrors legacy PathDrawingContext::GetContext/ReleaseContext)
    static NativePathDrawingContext* GetContext();
    static void ReleaseContext(NativePathDrawingContext* ctx);

private:
    void CreateBitmapContext();
    void DestroyBitmapContext();

    CGContextRef _cgContext = nullptr;
    CGColorSpaceRef _colorSpace = nullptr;
    uint8_t* _pixelData = nullptr;
    int _width = 0;
    int _height = 0;

    // Current stroke/fill state
    float _penWidth = 1.0f;
    float _penR = 0.0f, _penG = 0.0f, _penB = 0.0f, _penA = 1.0f;
    float _brushR = 0.0f, _brushG = 0.0f, _brushB = 0.0f, _brushA = 1.0f;

    // Gradient state
    bool _useGradient = false;
    float _grad1R = 0, _grad1G = 0, _grad1B = 0, _grad1A = 1;
    float _grad2R = 0, _grad2G = 0, _grad2B = 0, _grad2A = 1;

    // Pixel output cache
    std::vector<xlColor> _pixelOutput;
};

// ---------------------------------------------------------------------------
// NativeTextDrawingContext
//
// Backed by a CGBitmapContext. Uses CoreText for font management and text
// rendering. Thread-safe font caching via mutex.
// Coordinate system is flipped to top-left origin.
// ---------------------------------------------------------------------------
class NativeTextDrawingContext {
public:
    NativeTextDrawingContext();
    ~NativeTextDrawingContext();

    // Lifecycle
    void Initialize(int width, int height);
    void ResetSize(int width, int height);
    void Clear();

    // Dimensions
    int GetWidth() const { return _width; }
    int GetHeight() const { return _height; }

    // Font management
    void SetFont(const std::string& fontName, float size, bool bold, bool italic, const xlColor& color);

    // Text rendering
    void DrawText(const std::string& text, int x, int y);
    void DrawText(const std::string& text, int x, int y, double rotationDegrees);

    // Text measurement
    std::pair<int, int> GetTextExtent(const std::string& text);
    std::vector<double> GetTextExtents(const std::string& text);

    // Pixel extraction
    std::vector<xlColor>* FlushAndGetPixels();
    void CopyToRenderBuffer(xlColor* destPixels, int bufW, int bufH);

    // Static pool access
    static NativeTextDrawingContext* GetContext();
    static void ReleaseContext(NativeTextDrawingContext* ctx);

private:
    void CreateBitmapContext();
    void DestroyBitmapContext();

    CTFontRef GetOrCreateFont(const std::string& fontName, float size, bool bold, bool italic);

    CGContextRef _cgContext = nullptr;
    CGColorSpaceRef _colorSpace = nullptr;
    uint8_t* _pixelData = nullptr;
    int _width = 0;
    int _height = 0;

    // Current font state
    CTFontRef _currentFont = nullptr;
    float _fontR = 1.0f, _fontG = 1.0f, _fontB = 1.0f, _fontA = 1.0f;

    // Pixel output cache
    std::vector<xlColor> _pixelOutput;

public:
    // Font cache key type (public so the shared cache in .mm can use it)
    struct FontCacheKey {
        std::string name;
        float size;
        bool bold;
        bool italic;

        bool operator<(const FontCacheKey& o) const {
            if (name != o.name) return name < o.name;
            if (size != o.size) return size < o.size;
            if (bold != o.bold) return bold < o.bold;
            return italic < o.italic;
        }
    };
};

// ---------------------------------------------------------------------------
// Context Pool (thread-safe)
// ---------------------------------------------------------------------------
template<typename T>
class NativeContextPool {
public:
    NativeContextPool() = default;
    ~NativeContextPool() {
        std::lock_guard<std::mutex> guard(_lock);
        while (!_available.empty()) {
            delete _available.front();
            _available.pop();
        }
    }

    T* acquire() {
        std::lock_guard<std::mutex> guard(_lock);
        if (_available.empty()) {
            T* ctx = new T();
            ctx->Initialize(10, 10);
            return ctx;
        }
        T* ctx = _available.front();
        _available.pop();
        return ctx;
    }

    void release(T* ctx) {
        if (ctx == nullptr) return;
        std::lock_guard<std::mutex> guard(_lock);
        _available.push(ctx);
    }

private:
    std::queue<T*> _available;
    std::mutex _lock;
};

// ---------------------------------------------------------------------------
// Global initialization / cleanup
// ---------------------------------------------------------------------------
void NativeDrawingContext_Initialize();
void NativeDrawingContext_Cleanup();
