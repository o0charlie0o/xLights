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
// Replaces wx-based DrawingContext for the XLIGHTS_NATIVE build.

#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>

#include "NativeDrawingContext.h"
#include "../../Color.h"

#include <cstring>
#include <cmath>
#include <map>
#include <mutex>

// ===========================================================================
// Static context pools
// ===========================================================================
static NativeContextPool<NativePathDrawingContext>* s_pathPool = nullptr;
static NativeContextPool<NativeTextDrawingContext>* s_textPool = nullptr;

void NativeDrawingContext_Initialize() {
    if (s_pathPool == nullptr) {
        s_pathPool = new NativeContextPool<NativePathDrawingContext>();
    }
    if (s_textPool == nullptr) {
        s_textPool = new NativeContextPool<NativeTextDrawingContext>();
    }
}

// Forward declaration of font cache cleanup (defined in anonymous namespace below)
static void cleanupFontCacheGlobal();

void NativeDrawingContext_Cleanup() {
    delete s_pathPool;
    s_pathPool = nullptr;
    delete s_textPool;
    s_textPool = nullptr;

    cleanupFontCacheGlobal();
}

// ===========================================================================
// Shared font cache (thread-safe)
// ===========================================================================
namespace {
    std::mutex& getFontCacheMutex() {
        static std::mutex mtx;
        return mtx;
    }

    std::map<NativeTextDrawingContext::FontCacheKey, CTFontRef>& getFontCache() {
        static std::map<NativeTextDrawingContext::FontCacheKey, CTFontRef> cache;
        return cache;
    }

    void cleanupFontCache() {
        std::lock_guard<std::mutex> guard(getFontCacheMutex());
        for (auto& pair : getFontCache()) {
            if (pair.second != nullptr) {
                CFRelease(pair.second);
            }
        }
        getFontCache().clear();
    }

    // Helper: un-premultiply alpha for a single pixel.
    // CoreGraphics uses premultiplied alpha internally, but xlColor expects
    // straight (non-premultiplied) RGBA.
    inline void unpremultiply(uint8_t* r, uint8_t* g, uint8_t* b, uint8_t a) {
        if (a == 0) {
            *r = *g = *b = 0;
            return;
        }
        if (a == 255) {
            return; // already correct
        }
        float inv = 255.0f / (float)a;
        int ri = (int)((float)(*r) * inv + 0.5f);
        int gi = (int)((float)(*g) * inv + 0.5f);
        int bi = (int)((float)(*b) * inv + 0.5f);
        *r = (uint8_t)(ri > 255 ? 255 : ri);
        *g = (uint8_t)(gi > 255 ? 255 : gi);
        *b = (uint8_t)(bi > 255 ? 255 : bi);
    }
}

static void cleanupFontCacheGlobal() {
    cleanupFontCache();
}

// ===========================================================================
// NativePathDrawingContext
// ===========================================================================

NativePathDrawingContext::NativePathDrawingContext() {}

NativePathDrawingContext::~NativePathDrawingContext() {
    DestroyBitmapContext();
}

void NativePathDrawingContext::Initialize(int width, int height) {
    _width = (width > 0) ? width : 1;
    _height = (height > 0) ? height : 1;
    CreateBitmapContext();
}

void NativePathDrawingContext::ResetSize(int width, int height) {
    DestroyBitmapContext();
    _width = (width > 0) ? width : 1;
    _height = (height > 0) ? height : 1;
    CreateBitmapContext();
}

void NativePathDrawingContext::CreateBitmapContext() {
    DestroyBitmapContext();

    size_t bytesPerRow = (size_t)_width * 4;
    _pixelData = (uint8_t*)calloc((size_t)_height * bytesPerRow, 1);

    _colorSpace = CGColorSpaceCreateDeviceRGB();

    _cgContext = CGBitmapContextCreate(
        _pixelData,
        (size_t)_width,
        (size_t)_height,
        8,                  // bits per component
        bytesPerRow,
        _colorSpace,
        kCGImageAlphaPremultipliedLast // RGBA, premultiplied alpha
    );

    if (_cgContext == nullptr) {
        return;
    }

    // Flip coordinate system: CoreGraphics is bottom-left origin,
    // xLights effects expect top-left origin.
    CGContextTranslateCTM(_cgContext, 0.0, (CGFloat)_height);
    CGContextScaleCTM(_cgContext, 1.0, -1.0);

    // Disable antialiasing to match legacy behavior
    CGContextSetShouldAntialias(_cgContext, false);
    CGContextSetAllowsAntialiasing(_cgContext, false);
    CGContextSetInterpolationQuality(_cgContext, kCGInterpolationNone);
}

void NativePathDrawingContext::DestroyBitmapContext() {
    if (_cgContext != nullptr) {
        CGContextRelease(_cgContext);
        _cgContext = nullptr;
    }
    if (_colorSpace != nullptr) {
        CGColorSpaceRelease(_colorSpace);
        _colorSpace = nullptr;
    }
    if (_pixelData != nullptr) {
        free(_pixelData);
        _pixelData = nullptr;
    }
}

void NativePathDrawingContext::Clear() {
    if (_cgContext == nullptr || _pixelData == nullptr) return;

    // Zero out all pixel data (transparent black)
    memset(_pixelData, 0, (size_t)_width * (size_t)_height * 4);

    _useGradient = false;
}

CGMutablePathRef NativePathDrawingContext::CreatePath() {
    return CGPathCreateMutable();
}

void NativePathDrawingContext::StrokePath(CGMutablePathRef path) {
    if (_cgContext == nullptr || path == nullptr) return;

    CGContextSetRGBStrokeColor(_cgContext, _penR, _penG, _penB, _penA);
    CGContextSetLineWidth(_cgContext, _penWidth);
    CGContextAddPath(_cgContext, path);
    CGContextStrokePath(_cgContext);
    CGPathRelease(path);
}

void NativePathDrawingContext::FillPath(CGMutablePathRef path, int fillRule) {
    if (_cgContext == nullptr || path == nullptr) return;

    if (_useGradient) {
        // Save state for gradient fill
        CGContextSaveGState(_cgContext);
        CGContextAddPath(_cgContext, path);

        if (fillRule == 1) {
            CGContextEOClip(_cgContext);
        } else {
            CGContextClip(_cgContext);
        }

        // Create and draw a linear gradient (top to bottom)
        CGFloat colors[] = {
            _grad1R, _grad1G, _grad1B, _grad1A,
            _grad2R, _grad2G, _grad2B, _grad2A
        };
        CGFloat locations[] = { 0.0, 1.0 };
        CGGradientRef gradient = CGGradientCreateWithColorComponents(
            _colorSpace, colors, locations, 2
        );

        // Draw gradient from top to bottom of the path bounding box
        CGRect bounds = CGPathGetBoundingBox(path);
        // Note: coordinates are already flipped, so start=top, end=bottom
        CGPoint startPoint = CGPointMake(CGRectGetMidX(bounds), CGRectGetMinY(bounds));
        CGPoint endPoint = CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds));

        CGContextDrawLinearGradient(
            _cgContext, gradient, startPoint, endPoint,
            kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation
        );

        CGGradientRelease(gradient);
        CGContextRestoreGState(_cgContext);
    } else {
        CGContextSetRGBFillColor(_cgContext, _brushR, _brushG, _brushB, _brushA);
        CGContextAddPath(_cgContext, path);

        if (fillRule == 1) {
            CGContextEOFillPath(_cgContext);
        } else {
            CGContextFillPath(_cgContext);
        }
    }

    CGPathRelease(path);
}

void NativePathDrawingContext::SetPen(const xlColor& color, float width) {
    _penR = color.red / 255.0f;
    _penG = color.green / 255.0f;
    _penB = color.blue / 255.0f;
    _penA = color.alpha / 255.0f;
    _penWidth = width;
    _useGradient = false;
}

void NativePathDrawingContext::SetBrush(const xlColor& color) {
    _brushR = color.red / 255.0f;
    _brushG = color.green / 255.0f;
    _brushB = color.blue / 255.0f;
    _brushA = color.alpha / 255.0f;
    _useGradient = false;
}

void NativePathDrawingContext::SetGradientBrush(const xlColor& color1, const xlColor& color2) {
    _grad1R = color1.red / 255.0f;
    _grad1G = color1.green / 255.0f;
    _grad1B = color1.blue / 255.0f;
    _grad1A = color1.alpha / 255.0f;
    _grad2R = color2.red / 255.0f;
    _grad2G = color2.green / 255.0f;
    _grad2B = color2.blue / 255.0f;
    _grad2A = color2.alpha / 255.0f;
    _useGradient = true;
}

std::vector<xlColor>* NativePathDrawingContext::FlushAndGetPixels() {
    if (_cgContext == nullptr || _pixelData == nullptr) {
        _pixelOutput.clear();
        return &_pixelOutput;
    }

    CGContextFlush(_cgContext);

    size_t totalPixels = (size_t)_width * (size_t)_height;
    _pixelOutput.resize(totalPixels);

    for (size_t i = 0; i < totalPixels; i++) {
        size_t offset = i * 4;
        uint8_t r = _pixelData[offset + 0];
        uint8_t g = _pixelData[offset + 1];
        uint8_t b = _pixelData[offset + 2];
        uint8_t a = _pixelData[offset + 3];

        // Un-premultiply alpha
        unpremultiply(&r, &g, &b, a);

        _pixelOutput[i].red = r;
        _pixelOutput[i].green = g;
        _pixelOutput[i].blue = b;
        _pixelOutput[i].alpha = a;
    }

    return &_pixelOutput;
}

void NativePathDrawingContext::CopyToRenderBuffer(xlColor* destPixels, int bufW, int bufH) {
    if (destPixels == nullptr || _cgContext == nullptr || _pixelData == nullptr) return;

    CGContextFlush(_cgContext);

    int copyW = (_width < bufW) ? _width : bufW;
    int copyH = (_height < bufH) ? _height : bufH;

    for (int y = 0; y < copyH; y++) {
        for (int x = 0; x < copyW; x++) {
            size_t srcOffset = ((size_t)y * (size_t)_width + (size_t)x) * 4;
            uint8_t r = _pixelData[srcOffset + 0];
            uint8_t g = _pixelData[srcOffset + 1];
            uint8_t b = _pixelData[srcOffset + 2];
            uint8_t a = _pixelData[srcOffset + 3];

            unpremultiply(&r, &g, &b, a);

            // RenderBuffer pixel layout: pixels[y * bufW + x]
            xlColor& dest = destPixels[y * bufW + x];
            if (a > 0) {
                dest.red = r;
                dest.green = g;
                dest.blue = b;
                dest.alpha = a;
            }
        }
    }
}

NativePathDrawingContext* NativePathDrawingContext::GetContext() {
    if (s_pathPool != nullptr) {
        return s_pathPool->acquire();
    }
    return nullptr;
}

void NativePathDrawingContext::ReleaseContext(NativePathDrawingContext* ctx) {
    if (s_pathPool != nullptr && ctx != nullptr) {
        s_pathPool->release(ctx);
    }
}

// ===========================================================================
// NativeTextDrawingContext
// ===========================================================================

NativeTextDrawingContext::NativeTextDrawingContext() {}

NativeTextDrawingContext::~NativeTextDrawingContext() {
    DestroyBitmapContext();
    // _currentFont is owned by the shared font cache, do not release here
    _currentFont = nullptr;
}

void NativeTextDrawingContext::Initialize(int width, int height) {
    _width = (width > 0) ? width : 1;
    _height = (height > 0) ? height : 1;
    CreateBitmapContext();
}

void NativeTextDrawingContext::ResetSize(int width, int height) {
    DestroyBitmapContext();
    _width = (width > 0) ? width : 1;
    _height = (height > 0) ? height : 1;
    CreateBitmapContext();
}

void NativeTextDrawingContext::CreateBitmapContext() {
    DestroyBitmapContext();

    size_t bytesPerRow = (size_t)_width * 4;
    _pixelData = (uint8_t*)calloc((size_t)_height * bytesPerRow, 1);

    _colorSpace = CGColorSpaceCreateDeviceRGB();

    _cgContext = CGBitmapContextCreate(
        _pixelData,
        (size_t)_width,
        (size_t)_height,
        8,
        bytesPerRow,
        _colorSpace,
        kCGImageAlphaPremultipliedLast
    );

    if (_cgContext == nullptr) {
        return;
    }

    // Flip coordinate system for top-left origin
    CGContextTranslateCTM(_cgContext, 0.0, (CGFloat)_height);
    CGContextScaleCTM(_cgContext, 1.0, -1.0);

    // Disable antialiasing to match legacy pixel-precise text rendering
    CGContextSetShouldAntialias(_cgContext, false);
    CGContextSetAllowsAntialiasing(_cgContext, false);
    CGContextSetInterpolationQuality(_cgContext, kCGInterpolationNone);

    // Disable font smoothing (subpixel antialiasing)
    CGContextSetShouldSmoothFonts(_cgContext, false);
}

void NativeTextDrawingContext::DestroyBitmapContext() {
    if (_cgContext != nullptr) {
        CGContextRelease(_cgContext);
        _cgContext = nullptr;
    }
    if (_colorSpace != nullptr) {
        CGColorSpaceRelease(_colorSpace);
        _colorSpace = nullptr;
    }
    if (_pixelData != nullptr) {
        free(_pixelData);
        _pixelData = nullptr;
    }
}

void NativeTextDrawingContext::Clear() {
    if (_cgContext == nullptr || _pixelData == nullptr) return;

    memset(_pixelData, 0, (size_t)_width * (size_t)_height * 4);
}

CTFontRef NativeTextDrawingContext::GetOrCreateFont(const std::string& fontName,
                                                     float size,
                                                     bool bold,
                                                     bool italic) {
    FontCacheKey key{fontName, size, bold, italic};

    std::lock_guard<std::mutex> guard(getFontCacheMutex());
    auto& cache = getFontCache();
    auto it = cache.find(key);
    if (it != cache.end()) {
        return it->second;
    }

    // Create CoreText font
    CFStringRef cfFontName = CFStringCreateWithCString(
        kCFAllocatorDefault, fontName.c_str(), kCFStringEncodingUTF8
    );

    CTFontRef baseFont = CTFontCreateWithName(cfFontName, (CGFloat)size, nullptr);
    CFRelease(cfFontName);

    if (baseFont == nullptr) {
        // Fallback to system font
        baseFont = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, (CGFloat)size, nullptr);
    }

    // Apply bold/italic traits
    CTFontRef styledFont = baseFont;
    if (bold || italic) {
        CTFontSymbolicTraits traits = 0;
        if (bold) traits |= kCTFontBoldTrait;
        if (italic) traits |= kCTFontItalicTrait;

        CTFontRef traitFont = CTFontCreateCopyWithSymbolicTraits(
            baseFont, (CGFloat)size, nullptr, traits, traits
        );
        if (traitFont != nullptr) {
            CFRelease(baseFont);
            styledFont = traitFont;
        }
        // If trait application fails, keep the base font
    }

    cache[key] = styledFont;
    return styledFont;
}

void NativeTextDrawingContext::SetFont(const std::string& fontName,
                                        float size,
                                        bool bold,
                                        bool italic,
                                        const xlColor& color) {
    _currentFont = GetOrCreateFont(fontName, size, bold, italic);
    _fontR = color.red / 255.0f;
    _fontG = color.green / 255.0f;
    _fontB = color.blue / 255.0f;
    _fontA = color.alpha / 255.0f;
}

void NativeTextDrawingContext::DrawText(const std::string& text, int x, int y) {
    if (_cgContext == nullptr || _currentFont == nullptr || text.empty()) return;

    @autoreleasepool {
        NSString* nsText = [NSString stringWithUTF8String:text.c_str()];
        if (nsText == nil) return;

        // Create color for text
        CGColorRef cgColor = CGColorCreateSRGB(_fontR, _fontG, _fontB, _fontA);

        // Build attributed string
        NSDictionary* attrs = @{
            (__bridge NSString*)kCTFontAttributeName: (__bridge id)_currentFont,
            (__bridge NSString*)kCTForegroundColorAttributeName: (__bridge id)cgColor
        };

        NSAttributedString* attrStr = [[NSAttributedString alloc]
            initWithString:nsText attributes:attrs];

        CTLineRef line = CTLineCreateWithAttributedString(
            (__bridge CFAttributedStringRef)attrStr
        );

        // CoreText draws with baseline at the specified point.
        // We need to account for the coordinate flip. Since we already
        // flipped the context (translate + scale), we need to undo the
        // flip locally for text rendering because CoreText expects
        // normal (bottom-up) coordinates.
        CGContextSaveGState(_cgContext);

        // Undo the global flip for this text draw
        CGContextTranslateCTM(_cgContext, 0.0, (CGFloat)_height);
        CGContextScaleCTM(_cgContext, 1.0, -1.0);

        // Now in bottom-left coords: convert our top-left (x, y) to bottom-left
        // In top-left coords, y is distance from top.
        // In bottom-left coords, the text baseline should be at (_height - y - ascent)
        CGFloat ascent = CTFontGetAscent(_currentFont);
        CGFloat bottomLeftY = (CGFloat)_height - (CGFloat)y - ascent;

        CGContextSetTextPosition(_cgContext, (CGFloat)x, bottomLeftY);
        CTLineDraw(line, _cgContext);

        CGContextRestoreGState(_cgContext);

        CFRelease(line);
        CGColorRelease(cgColor);
    }
}

void NativeTextDrawingContext::DrawText(const std::string& text, int x, int y, double rotationDegrees) {
    if (_cgContext == nullptr || _currentFont == nullptr || text.empty()) return;
    if (rotationDegrees == 0.0) {
        DrawText(text, x, y);
        return;
    }

    @autoreleasepool {
        NSString* nsText = [NSString stringWithUTF8String:text.c_str()];
        if (nsText == nil) return;

        CGColorRef cgColor = CGColorCreateSRGB(_fontR, _fontG, _fontB, _fontA);

        NSDictionary* attrs = @{
            (__bridge NSString*)kCTFontAttributeName: (__bridge id)_currentFont,
            (__bridge NSString*)kCTForegroundColorAttributeName: (__bridge id)cgColor
        };

        NSAttributedString* attrStr = [[NSAttributedString alloc]
            initWithString:nsText attributes:attrs];

        CTLineRef line = CTLineCreateWithAttributedString(
            (__bridge CFAttributedStringRef)attrStr
        );

        CGContextSaveGState(_cgContext);

        // Undo global flip for text
        CGContextTranslateCTM(_cgContext, 0.0, (CGFloat)_height);
        CGContextScaleCTM(_cgContext, 1.0, -1.0);

        CGFloat ascent = CTFontGetAscent(_currentFont);
        CGFloat bottomLeftY = (CGFloat)_height - (CGFloat)y - ascent;

        // Apply rotation around the text origin point
        double radians = rotationDegrees * M_PI / 180.0;
        CGContextTranslateCTM(_cgContext, (CGFloat)x, bottomLeftY);
        CGContextRotateCTM(_cgContext, (CGFloat)radians);

        CGContextSetTextPosition(_cgContext, 0.0, 0.0);
        CTLineDraw(line, _cgContext);

        CGContextRestoreGState(_cgContext);

        CFRelease(line);
        CGColorRelease(cgColor);
    }
}

std::pair<int, int> NativeTextDrawingContext::GetTextExtent(const std::string& text) {
    if (_currentFont == nullptr || text.empty()) {
        return {0, 0};
    }

    @autoreleasepool {
        NSString* nsText = [NSString stringWithUTF8String:text.c_str()];
        if (nsText == nil) return {0, 0};

        NSDictionary* attrs = @{
            (__bridge NSString*)kCTFontAttributeName: (__bridge id)_currentFont
        };

        NSAttributedString* attrStr = [[NSAttributedString alloc]
            initWithString:nsText attributes:attrs];

        CTLineRef line = CTLineCreateWithAttributedString(
            (__bridge CFAttributedStringRef)attrStr
        );

        CGFloat ascent = 0, descent = 0, leading = 0;
        double width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);

        int totalHeight = (int)std::ceil(ascent + descent + leading);
        int totalWidth = (int)std::ceil(width);

        CFRelease(line);

        return {totalWidth, totalHeight};
    }
}

std::vector<double> NativeTextDrawingContext::GetTextExtents(const std::string& text) {
    std::vector<double> extents;
    if (_currentFont == nullptr || text.empty()) {
        return extents;
    }

    @autoreleasepool {
        NSString* nsText = [NSString stringWithUTF8String:text.c_str()];
        if (nsText == nil) return extents;

        NSDictionary* attrs = @{
            (__bridge NSString*)kCTFontAttributeName: (__bridge id)_currentFont
        };

        NSAttributedString* attrStr = [[NSAttributedString alloc]
            initWithString:nsText attributes:attrs];

        CTLineRef line = CTLineCreateWithAttributedString(
            (__bridge CFAttributedStringRef)attrStr
        );

        // Get per-character cumulative advances (matching wxGraphicsContext::GetPartialTextExtents)
        CFArrayRef runs = CTLineGetGlyphRuns(line);
        CFIndex runCount = CFArrayGetCount(runs);

        // Build a mapping from string index to cumulative advance
        NSUInteger charCount = [nsText length];
        extents.resize(charCount, 0.0);

        double cumulativeAdvance = 0.0;

        for (CFIndex r = 0; r < runCount; r++) {
            CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
            CFIndex glyphCount = CTRunGetGlyphCount(run);

            if (glyphCount == 0) continue;

            // Get advances for all glyphs in this run
            std::vector<CGSize> advances(glyphCount);
            CTRunGetAdvances(run, CFRangeMake(0, glyphCount), advances.data());

            // Get string indices for glyphs
            std::vector<CFIndex> indices(glyphCount);
            CTRunGetStringIndices(run, CFRangeMake(0, glyphCount), indices.data());

            for (CFIndex g = 0; g < glyphCount; g++) {
                cumulativeAdvance += advances[g].width;
                CFIndex strIdx = indices[g];
                if (strIdx >= 0 && (NSUInteger)strIdx < charCount) {
                    extents[(size_t)strIdx] = cumulativeAdvance;
                }
            }
        }

        // Fill in any gaps (surrogate pairs, combined characters)
        // Ensure monotonically increasing values
        double lastVal = 0.0;
        for (size_t i = 0; i < extents.size(); i++) {
            if (extents[i] < lastVal) {
                extents[i] = lastVal;
            }
            lastVal = extents[i];
        }

        CFRelease(line);
    }

    return extents;
}

std::vector<xlColor>* NativeTextDrawingContext::FlushAndGetPixels() {
    if (_cgContext == nullptr || _pixelData == nullptr) {
        _pixelOutput.clear();
        return &_pixelOutput;
    }

    CGContextFlush(_cgContext);

    size_t totalPixels = (size_t)_width * (size_t)_height;
    _pixelOutput.resize(totalPixels);

    for (size_t i = 0; i < totalPixels; i++) {
        size_t offset = i * 4;
        uint8_t r = _pixelData[offset + 0];
        uint8_t g = _pixelData[offset + 1];
        uint8_t b = _pixelData[offset + 2];
        uint8_t a = _pixelData[offset + 3];

        unpremultiply(&r, &g, &b, a);

        _pixelOutput[i].red = r;
        _pixelOutput[i].green = g;
        _pixelOutput[i].blue = b;
        _pixelOutput[i].alpha = a;
    }

    return &_pixelOutput;
}

void NativeTextDrawingContext::CopyToRenderBuffer(xlColor* destPixels, int bufW, int bufH) {
    if (destPixels == nullptr || _cgContext == nullptr || _pixelData == nullptr) return;

    CGContextFlush(_cgContext);

    int copyW = (_width < bufW) ? _width : bufW;
    int copyH = (_height < bufH) ? _height : bufH;

    for (int y = 0; y < copyH; y++) {
        for (int x = 0; x < copyW; x++) {
            size_t srcOffset = ((size_t)y * (size_t)_width + (size_t)x) * 4;
            uint8_t r = _pixelData[srcOffset + 0];
            uint8_t g = _pixelData[srcOffset + 1];
            uint8_t b = _pixelData[srcOffset + 2];
            uint8_t a = _pixelData[srcOffset + 3];

            unpremultiply(&r, &g, &b, a);

            xlColor& dest = destPixels[y * bufW + x];
            if (a > 0) {
                dest.red = r;
                dest.green = g;
                dest.blue = b;
                dest.alpha = a;
            }
        }
    }
}

NativeTextDrawingContext* NativeTextDrawingContext::GetContext() {
    if (s_textPool != nullptr) {
        return s_textPool->acquire();
    }
    return nullptr;
}

void NativeTextDrawingContext::ReleaseContext(NativeTextDrawingContext* ctx) {
    if (s_textPool != nullptr && ctx != nullptr) {
        s_textPool->release(ctx);
    }
}
