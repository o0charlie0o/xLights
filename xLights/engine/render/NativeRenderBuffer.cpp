/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "NativeRenderBuffer.h"
#include "IRenderContext.h"

#include <cstring>
#include <algorithm>
#include <cmath>
#include <cstdlib>

namespace xlEngine {

// =========================================================================
// Construction / Destruction
// =========================================================================

NativeRenderBuffer::NativeRenderBuffer(IRenderContext* context, int bufferWi, int bufferHt)
    : _context(context)
{
    BufferWi = bufferWi;
    BufferHt = bufferHt;

    size_t numPixels = static_cast<size_t>(BufferWi) * BufferHt;
    pixelVector.resize(numPixels, xlBLACK);
    tempbufVector.resize(numPixels, xlCLEAR);
    pixels = pixelVector.data();
    tempbuf = tempbufVector.data();
}

NativeRenderBuffer::~NativeRenderBuffer()
{
    for (auto& [key, cache] : infoCache) {
        delete cache;
    }
    infoCache.clear();
}

NativeRenderBuffer::NativeRenderBuffer(const NativeRenderBuffer& other)
    : _context(other._context),
      pixelVector(other.pixelVector),
      tempbufVector(other.tempbufVector),
      palette(other.palette),
      paletteHSV(other.paletteHSV),
      hsv(other.hsv),
      allowAlpha(other.allowAlpha),
      BufferHt(other.BufferHt),
      BufferWi(other.BufferWi),
      curPeriod(other.curPeriod),
      curEffStartPer(other.curEffStartPer),
      curEffEndPer(other.curEffEndPer),
      frameTimeInMs(other.frameTimeInMs),
      cur_model(other.cur_model),
      needToInit(other.needToInit),
      isTransformed(other.isTransformed),
      fadeinsteps(other.fadeinsteps),
      fadeoutsteps(other.fadeoutsteps),
      gpuRenderData(nullptr)
{
    pixels = pixelVector.data();
    tempbuf = tempbufVector.data();
    // infoCache is NOT copied — each buffer owns its own cache
}

void NativeRenderBuffer::InitBuffer(int newBufferHt, int newBufferWi, const std::string& bufferTransform)
{
    BufferHt = newBufferHt;
    BufferWi = newBufferWi;

    size_t numPixels = static_cast<size_t>(BufferWi) * BufferHt;
    pixelVector.resize(numPixels);
    tempbufVector.resize(numPixels);
    pixels = pixelVector.data();
    tempbuf = tempbufVector.data();

    Clear();
    ClearTempBuf();

    isTransformed = (bufferTransform != "None");
}

// =========================================================================
// Pixel Access
// =========================================================================

void NativeRenderBuffer::SetPixel(int x, int y, const xlColor& color, bool wrap, bool useAlpha)
{
    if (wrap) {
        while (x < 0) x += BufferWi;
        while (y < 0) y += BufferHt;
        while (x >= BufferWi) x -= BufferWi;
        while (y >= BufferHt) y -= BufferHt;
    }

    if (x >= 0 && x < BufferWi && y >= 0 && y < BufferHt) {
        size_t idx = static_cast<size_t>(y) * BufferWi + x;
        if (idx < pixelVector.size()) {
            if (useAlpha && color.Alpha() != 255) {
                xlColor pold = pixels[idx];
                xlColor c;
                int r = color.red + (pold.red * (255 - color.alpha)) / 255;
                if (r > 255) r = 255;
                c.red = static_cast<uint8_t>(r);
                int g = color.green + (pold.green * (255 - color.alpha)) / 255;
                if (g > 255) g = 255;
                c.green = static_cast<uint8_t>(g);
                int b = color.blue + (pold.blue * (255 - color.alpha)) / 255;
                if (b > 255) b = 255;
                c.blue = static_cast<uint8_t>(b);
                int a = color.alpha + (pold.alpha * (255 - color.alpha)) / 255;
                if (a > 255) a = 255;
                c.alpha = static_cast<uint8_t>(a);
                pixels[idx] = c;
            } else {
                pixels[idx] = color;
            }
        }
    }
}

void NativeRenderBuffer::SetPixel(int x, int y, const HSVValue& hsvVal, bool wrap)
{
    xlColor c(hsvVal);
    SetPixel(x, y, c, wrap);
}

void NativeRenderBuffer::GetPixel(int x, int y, xlColor& color) const
{
    if (x >= 0 && x < BufferWi && y >= 0 && y < BufferHt) {
        size_t idx = static_cast<size_t>(y) * BufferWi + x;
        if (idx < pixelVector.size()) {
            color = pixels[idx];
            return;
        }
    }
    color = allowAlpha ? xlCLEAR : xlBLACK;
}

const xlColor& NativeRenderBuffer::GetPixel(int x, int y) const
{
    if (x >= 0 && x < BufferWi && y >= 0 && y < BufferHt) {
        size_t idx = static_cast<size_t>(y) * BufferWi + x;
        if (idx < pixelVector.size()) {
            return pixels[idx];
        }
    }
    return allowAlpha ? xlCLEAR : xlBLACK;
}

void NativeRenderBuffer::CopyPixel(int srcx, int srcy, int destx, int desty)
{
    if (srcx >= 0 && srcx < BufferWi && srcy >= 0 && srcy < BufferHt &&
        destx >= 0 && destx < BufferWi && desty >= 0 && desty < BufferHt) {
        size_t si = static_cast<size_t>(srcy) * BufferWi + srcx;
        size_t di = static_cast<size_t>(desty) * BufferWi + destx;
        if (si < pixelVector.size() && di < pixelVector.size()) {
            pixels[di] = pixels[si];
        }
    }
}

void NativeRenderBuffer::ProcessPixel(int x, int y, const xlColor& color, bool wrap_x, bool wrap_y)
{
    if (wrap_x) {
        x %= BufferWi;
        if (x < 0) x += BufferWi;
    }
    if (wrap_y) {
        y %= BufferHt;
        if (y < 0) y += BufferHt;
    }
    SetPixel(x, y, color);
}

// =========================================================================
// Temp Buffer
// =========================================================================

void NativeRenderBuffer::ClearTempBuf()
{
    for (size_t i = 0; i < tempbufVector.size(); i++) {
        tempbuf[i].Set(0, 0, 0, 0);
    }
}

void NativeRenderBuffer::SetTempPixel(int x, int y, const xlColor& color)
{
    if (x >= 0 && x < BufferWi && y >= 0 && y < BufferHt) {
        size_t idx = static_cast<size_t>(y) * BufferWi + x;
        if (idx < tempbufVector.size()) {
            tempbuf[idx] = color;
        }
    }
}

void NativeRenderBuffer::SetTempPixel(int x, int y, const xlColor& color, int alpha)
{
    xlColor c(color.Red(), color.Green(), color.Blue(), static_cast<uint8_t>(alpha));
    SetTempPixel(x, y, c);
}

void NativeRenderBuffer::GetTempPixel(int x, int y, xlColor& color) const
{
    if (x >= 0 && x < BufferWi && y >= 0 && y < BufferHt) {
        size_t idx = static_cast<size_t>(y) * BufferWi + x;
        if (idx < tempbufVector.size()) {
            color = tempbuf[idx];
            return;
        }
    }
    color = allowAlpha ? xlCLEAR : xlBLACK;
}

const xlColor& NativeRenderBuffer::GetTempPixel(int x, int y) const
{
    if (x >= 0 && x < BufferWi && y >= 0 && y < BufferHt) {
        size_t idx = static_cast<size_t>(y) * BufferWi + x;
        if (idx < tempbufVector.size()) {
            return tempbuf[idx];
        }
    }
    return allowAlpha ? xlCLEAR : xlBLACK;
}

const xlColor& NativeRenderBuffer::GetTempPixelRGB(int x, int y) const
{
    return GetTempPixel(x, y);
}

void NativeRenderBuffer::CopyTempBufToPixels()
{
    std::memcpy(pixels, tempbuf, pixelVector.size() * sizeof(xlColor));
}

void NativeRenderBuffer::CopyPixelsToTempBuf()
{
    std::memcpy(tempbuf, pixels, pixelVector.size() * sizeof(xlColor));
}

// =========================================================================
// Buffer Operations
// =========================================================================

void NativeRenderBuffer::Clear()
{
    if (!pixelVector.empty()) {
        std::memset(pixels, 0x00, sizeof(xlColor) * pixelVector.size());
    }
}

void NativeRenderBuffer::Fill(const xlColor& color)
{
    std::fill_n(pixels, pixelVector.size(), color);
}

void NativeRenderBuffer::AlphaBlend(const NativeRenderBuffer& src)
{
    if (src.BufferWi != BufferWi || src.BufferHt != BufferHt) return;

    uint32_t count = GetPixelCount();
    for (uint32_t idx = 0; idx < count; idx++) {
        const xlColor& pnew = src.pixels[idx];
        xlColor& pold = pixels[idx];
        if (pnew.alpha == 255 || pold == xlBLACK) {
            pold = pnew;
        } else if (pnew.alpha > 0 && pnew != xlBLACK) {
            int r = pnew.red + pold.red * (255 - pnew.alpha) / 255;
            if (r > 255) r = 255;
            pold.red = static_cast<uint8_t>(r);
            int g = pnew.green + pold.green * (255 - pnew.alpha) / 255;
            if (g > 255) g = 255;
            pold.green = static_cast<uint8_t>(g);
            int b = pnew.blue + pold.blue * (255 - pnew.alpha) / 255;
            if (b > 255) b = 255;
            pold.blue = static_cast<uint8_t>(b);
            int a = pnew.alpha + pold.alpha * (255 - pnew.alpha) / 255;
            if (a > 255) a = 255;
            pold.alpha = static_cast<uint8_t>(a);
        }
    }
}

// =========================================================================
// Drawing Primitives
// =========================================================================

void NativeRenderBuffer::DrawHLine(int y, int xstart, int xend, const xlColor& color, bool wrap)
{
    if (xstart > xend) std::swap(xstart, xend);
    for (int x = xstart; x <= xend; x++) {
        SetPixel(x, y, color, wrap);
    }
}

void NativeRenderBuffer::DrawVLine(int x, int ystart, int yend, const xlColor& color, bool wrap)
{
    if (ystart > yend) std::swap(ystart, yend);
    for (int y = ystart; y <= yend; y++) {
        SetPixel(x, y, color, wrap);
    }
}

void NativeRenderBuffer::DrawBox(int x1, int y1, int x2, int y2, const xlColor& color, bool wrap, bool useAlpha)
{
    if (y1 > y2) std::swap(y1, y2);
    if (x1 > x2) std::swap(x1, x2);
    for (int x = x1; x <= x2; x++) {
        for (int y = y1; y <= y2; y++) {
            SetPixel(x, y, color, wrap, useAlpha);
        }
    }
}

// Bresenham's line algorithm
void NativeRenderBuffer::DrawLine(int x0, int y0, int x1, int y1, const xlColor& color, bool useAlpha)
{
    int dx = std::abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    int dy = std::abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    int err = (dx > dy ? dx : -dy) / 2;

    for (;;) {
        SetPixel(x0, y0, color, false, useAlpha);
        if (x0 == x1 && y0 == y1) break;
        int e2 = err;
        if (e2 > -dx) { err -= dy; x0 += sx; }
        if (e2 < dy)  { err += dx; y0 += sy; }
    }
}

void NativeRenderBuffer::DrawThickLine(int x1, int y1, int x2, int y2, const xlColor& color, int thickness, bool useAlpha)
{
    if (thickness < 1) return;
    if (thickness == 1) {
        DrawLine(x1, y1, x2, y2, color, useAlpha);
    } else {
        DrawCircle(x1, y1, thickness / 2, color, true);
        DrawCircle(x2, y2, thickness / 2, color, true);
        for (int i = 0; i < thickness; i++) {
            int adjust = i - thickness / 2;
            DrawLine(x1 + adjust, y1, x2 + adjust, y2, color, useAlpha);
            DrawLine(x1, y1 + adjust, x2, y2 + adjust, color, useAlpha);
            DrawLine(x1 + adjust, y1 + adjust, x2 + adjust, y2 + adjust, color, useAlpha);
        }
    }
}

void NativeRenderBuffer::DrawThickLine(int x0, int y0, int x1, int y1, const xlColor& color, bool direction)
{
    int lastx = x0;
    int lasty = y0;

    int dx = std::abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    int dy = std::abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    int err = (dx > dy ? dx : -dy) / 2, e2;

    int x0_ = x0, y0_ = y0, x1_ = x1, y1_ = y1;

    for (;;) {
        SetPixel(x0, y0, color);
        if ((x0 != lastx) && (y0 != lasty) && (x0_ != x1_) && (y0_ != y1_)) {
            int fix = 0;
            if (x0 > lastx) fix += 1;
            if (y0 > lasty) fix += 2;
            if (direction)  fix += 4;
            switch (fix) {
            case 2:
            case 4:
                if (x0 < BufferWi - 2) SetPixel(x0 + 1, y0, color);
                break;
            case 3:
            case 5:
                if (x0 > 0) SetPixel(x0 - 1, y0, color);
                break;
            case 0:
            case 1:
                if (y0 < BufferHt - 2) SetPixel(x0, y0 + 1, color);
                break;
            case 6:
            case 7:
                if (y0 > 0) SetPixel(x0, y0 - 1, color);
                break;
            default: break;
            }
        }
        lastx = x0;
        lasty = y0;
        if (x0 == x1 && y0 == y1) break;
        e2 = err;
        if (e2 > -dx) { err -= dy; x0 += sx; }
        if (e2 < dy)  { err += dx; y0 += sy; }
    }
}

// Midpoint circle algorithm
void NativeRenderBuffer::DrawCircle(int x0, int y0, int radius, const xlColor& rgb, bool filled, bool wrap)
{
    int x = radius;
    int y = 0;
    int radiusError = 1 - x;

    while (x >= y) {
        if (!filled) {
            SetPixel(x + x0,  y + y0, rgb, wrap);
            SetPixel(y + x0,  x + y0, rgb, wrap);
            SetPixel(-x + x0, y + y0, rgb, wrap);
            SetPixel(-y + x0, x + y0, rgb, wrap);
            SetPixel(-x + x0, -y + y0, rgb, wrap);
            SetPixel(-y + x0, -x + y0, rgb, wrap);
            SetPixel(x + x0,  -y + y0, rgb, wrap);
            SetPixel(y + x0,  -x + y0, rgb, wrap);
        } else {
            DrawVLine(x0 - x, y0 - y, y0 + y, rgb, wrap);
            DrawVLine(x0 + x, y0 - y, y0 + y, rgb, wrap);
            DrawVLine(x0 - y, y0 - x, y0 + x, rgb, wrap);
            DrawVLine(x0 + y, y0 - x, y0 + x, rgb, wrap);
        }
        y++;
        if (radiusError < 0) {
            radiusError += 2 * y + 1;
        } else {
            x--;
            radiusError += 2 * (y - x) + 1;
        }
    }
}

void NativeRenderBuffer::DrawFadingCircle(int x0, int y0, int radius, const xlColor& rgb, bool wrap)
{
    HSVValue hsvVal(rgb);
    xlColor color(rgb);

    double full_brightness = hsvVal.value;

    for (int x = -radius; x < radius; ++x) {
        for (int y = -radius; y < radius; ++y) {
            double d = std::sqrt(static_cast<double>(x * x + y * y));
            if (d <= radius) {
                if (allowAlpha) {
                    double alpha = static_cast<double>(rgb.alpha) - (static_cast<double>(rgb.alpha) * d) / static_cast<double>(radius);
                    if (alpha > 0.0) {
                        color.alpha = static_cast<uint8_t>(alpha);
                        SetPixel(x + x0, y + y0, color, wrap, false);
                    }
                } else {
                    double alpha = full_brightness - (full_brightness * d) / static_cast<double>(radius);
                    if (alpha > 0.0) {
                        hsvVal.value = alpha;
                        color = hsvVal;
                        SetPixel(x + x0, y + y0, color, wrap);
                    }
                }
            }
        }
    }
}

// Convex polygon fill using scan-line algorithm
// Based on Michael Abrash's Graphics Programming Black Book approach
static void ScanEdge(int x1, int y1, int x2, int y2, int setx, bool skip,
                     std::vector<std::pair<int, int>>& lines, int& eidx)
{
    int dx = x2 - x1;
    int dy = y2 - y1;
    if (dy <= 0) return;
    double invs = static_cast<double>(dx) / static_cast<double>(dy);

    int idx = eidx;
    for (int y = y1 + (skip ? 1 : 0); y < y2; ++y, ++idx) {
        if (setx)
            lines[idx].first = x1 + static_cast<int>(std::ceil((y - y1) * invs));
        else
            lines[idx].second = x1 + static_cast<int>(std::ceil((y - y1) * invs));
    }
    eidx = idx;
}

void NativeRenderBuffer::FillConvexPoly(const std::vector<std::pair<int, int>>& opoly, const xlColor& color)
{
    if (opoly.empty()) return;

    // Remove consecutive duplicates
    std::vector<std::pair<int, int>> poly;
    poly.push_back(opoly[0]);
    for (size_t i = 1; i < opoly.size(); ++i) {
        if (opoly[i] != opoly[i - 1]) {
            poly.push_back(opoly[i]);
        }
    }
    if (!poly.empty() && poly.front() == poly.back()) {
        poly.pop_back();
    }

    if (poly.size() < 3) return;

    int miny, maxy, minx, maxx;
    minx = maxx = poly[0].first;
    miny = maxy = poly[0].second;
    int minidxl = 0, maxidx = 0;

    for (size_t i = 1; i < poly.size(); ++i) {
        if (poly[i].second < miny) { minidxl = static_cast<int>(i); miny = poly[i].second; }
        if (poly[i].second > maxy) { maxidx = static_cast<int>(i); maxy = poly[i].second; }
        minx = std::min(minx, poly[i].first);
        maxx = std::max(maxx, poly[i].first);
    }

    if (miny == maxy) return;
    if (minx >= BufferWi || maxx <= 0) return;
    if (miny >= BufferHt || maxy <= 0) return;

    int polySize = static_cast<int>(poly.size());
    int minidxr = minidxl;
    while (poly[minidxr].second == miny)
        minidxr = (minidxr + 1) % polySize;
    minidxr = (minidxr + polySize - 1) % polySize;

    while (poly[minidxl].second == miny)
        minidxl = (minidxl + polySize - 1) % polySize;
    minidxl = (minidxl + 1) % polySize;

    int ledir = -1;
    bool tif = (poly[minidxl].first != poly[minidxr].first);
    if (tif) {
        if (poly[minidxl].first > poly[minidxr].first) {
            ledir = 1;
            std::swap(minidxl, minidxr);
        }
    } else {
        int nidx = (minidxr + 1) % polySize;
        int pidx = (minidxl + polySize - 1) % polySize;
        int dxn = poly[nidx].first - poly[minidxl].first;
        int dyn = poly[nidx].second - poly[minidxl].second;
        int dxp = poly[pidx].first - poly[minidxl].first;
        int dyp = poly[pidx].second - poly[minidxl].second;
        if ((static_cast<long long>(dxn) * dyp - static_cast<long long>(dyn) * dxp) < 0LL) {
            ledir = 1;
            std::swap(minidxl, minidxr);
        }
    }

    int wheight = maxy - miny - 1 + (tif ? 1 : 0);
    if (wheight <= 0) return;
    int ystart = miny + 1 - (tif ? 1 : 0);

    std::vector<std::pair<int, int>> hlines(wheight);

    int edgept = 0;
    int cidx = minidxl, pidx2 = minidxl;
    bool skip = tif ? false : true;

    // Scan convert left edge
    do {
        cidx = (cidx + polySize + ledir) % polySize;
        ScanEdge(poly[pidx2].first, poly[pidx2].second,
                 poly[cidx].first, poly[cidx].second,
                 true, skip, hlines, edgept);
        pidx2 = cidx;
        skip = false;
    } while (cidx != maxidx);

    edgept = 0;
    pidx2 = cidx = minidxr;
    skip = tif ? false : true;

    // Scan convert right edge
    do {
        cidx = (cidx + polySize - ledir) % polySize;
        ScanEdge(poly[pidx2].first - 1, poly[pidx2].second,
                 poly[cidx].first - 1, poly[cidx].second,
                 false, skip, hlines, edgept);
        pidx2 = cidx;
        skip = false;
    } while (cidx != maxidx);

    // Draw horizontal lines
    for (int y = ystart, en = 0; y < ystart + static_cast<int>(hlines.size()); ++y, ++en) {
        if (y < 0 || y >= BufferHt) continue;
        int sx = std::max(0, hlines[en].first);
        int ex = std::min(hlines[en].second, BufferWi - 1);
        for (int x = sx; x <= ex; ++x)
            SetPixel(x, y, color, false);
    }
}

// =========================================================================
// Color Blending
// =========================================================================

uint8_t NativeRenderBuffer::ChannelBlend(uint8_t c1, uint8_t c2, float ratio) const
{
    return static_cast<uint8_t>(c1 + std::floor(ratio * (c2 - c1) + 0.5f));
}

void NativeRenderBuffer::Get2ColorBlend(int coloridx1, int coloridx2, float ratio, xlColor& color)
{
    if (static_cast<size_t>(coloridx1) < palette.size()) {
        color = palette[coloridx1];
    } else {
        color = xlWHITE;
    }
    xlColor c2 = (static_cast<size_t>(coloridx2) < palette.size()) ? palette[coloridx2] : xlWHITE;
    Get2ColorBlend(color, c2, ratio);
}

void NativeRenderBuffer::Get2ColorBlend(xlColor& color, xlColor color2, float ratio)
{
    color.Set(ChannelBlend(color.Red(), color2.Red(), ratio),
              ChannelBlend(color.Green(), color2.Green(), ratio),
              ChannelBlend(color.Blue(), color2.Blue(), ratio));
}

void NativeRenderBuffer::Get2ColorAlphaBlend(const xlColor& c1, const xlColor& c2, float ratio, xlColor& color)
{
    color.Set(ChannelBlend(c1.Red(), c2.Red(), ratio),
              ChannelBlend(c1.Green(), c2.Green(), ratio),
              ChannelBlend(c1.Blue(), c2.Blue(), ratio));
}

static inline uint8_t SumUInt8(uint8_t c1, uint8_t c2)
{
    int x = c1;
    x += c2;
    if (x > 255) x = 255;
    return static_cast<uint8_t>(x);
}

HSVValue NativeRenderBuffer::Get2ColorAdditive(HSVValue& hsv1, HSVValue& hsv2) const
{
    xlColor rgb1(hsv1);
    xlColor rgb2(hsv2);
    xlColor rgb;
    rgb.red = SumUInt8(rgb1.red, rgb2.red);
    rgb.green = SumUInt8(rgb1.green, rgb2.green);
    rgb.blue = SumUInt8(rgb1.blue, rgb2.blue);
    return rgb.asHSV();
}

void NativeRenderBuffer::GetMultiColorBlend(float n, bool circular, xlColor& color, int reserveColors)
{
    size_t colorcnt = GetColorCount() - reserveColors;
    if (colorcnt <= 1) {
        if (!palette.empty()) {
            color = palette[0];
        } else {
            color = xlWHITE;
        }
        return;
    }

    if (n >= 1.0f) n = 0.99999f;
    if (n < 0.0f) n = 0.0f;
    float realidx = circular ? n * colorcnt : n * (colorcnt - 1);
    int coloridx1 = static_cast<int>(std::floor(realidx));
    int coloridx2 = (coloridx1 + 1) % static_cast<int>(colorcnt);
    float ratio = realidx - static_cast<float>(coloridx1);
    Get2ColorBlend(coloridx1, coloridx2, ratio, color);
}

// =========================================================================
// Color Utilities
// =========================================================================

void NativeRenderBuffer::SetRangeColor(const HSVValue& hsv1, const HSVValue& hsv2, HSVValue& newhsv)
{
    newhsv.hue = RandomRange(hsv1.hue, hsv2.hue);
    newhsv.saturation = RandomRange(hsv1.saturation, hsv2.saturation);
    newhsv.value = 1.0;
}

double NativeRenderBuffer::RandomRange(double num1, double num2) const
{
    double hi, lo;
    if (num1 < num2) {
        lo = num1;
        hi = num2;
    } else {
        lo = num2;
        hi = num1;
    }
    return rand01() * (hi - lo) + lo;
}

void NativeRenderBuffer::Color2HSV(const xlColor& color, HSVValue& hsvVal) const
{
    color.toHSV(hsvVal);
}

// =========================================================================
// Acceleration / Easing
// =========================================================================

double NativeRenderBuffer::calcAccel(double ratio, double accel) const
{
    if (accel == 0) return ratio;

    double pct_accel = (std::abs(accel) - 1.0) / 9.0;
    double new_accel1 = pct_accel * 5 + (1.0 - pct_accel) * 1.5;
    double new_accel2 = 1.5 + (ratio * new_accel1);
    double final_accel = pct_accel * new_accel2 + (1.0 - pct_accel) * new_accel1;

    if (accel > 0) {
        return std::pow(ratio, final_accel);
    } else {
        return (1.0 - std::pow(1.0 - ratio, new_accel1));
    }
}

// =========================================================================
// Effect Timing
// =========================================================================

float NativeRenderBuffer::GetEffectTimeIntervalPosition() const
{
    if (curEffEndPer == curEffStartPer) {
        return 0.0f;
    }
    return static_cast<float>(curPeriod - curEffStartPer) /
           static_cast<float>(curEffEndPer - curEffStartPer);
}

float NativeRenderBuffer::GetEffectTimeIntervalPosition(float cycles) const
{
    if (curEffEndPer == curEffStartPer) {
        return 0.0f;
    }
    float periods = static_cast<float>(curEffEndPer - curEffStartPer + 1); // inclusive
    float periodsPerCycle = periods / cycles;
    if (periodsPerCycle <= 1.0f) {
        return 0.0f;
    }
    float retval = static_cast<float>(curPeriod - curEffStartPer);
    while (retval >= periodsPerCycle) {
        retval -= periodsPerCycle;
    }
    retval /= (periodsPerCycle - 1);
    return retval > 1.0f ? 1.0f : retval;
}

void NativeRenderBuffer::SetState(int period, bool reset)
{
    if (reset) {
        needToInit = true;
    }
    curPeriod = period;
}

void NativeRenderBuffer::SetEffectDuration(int startMsec, int endMsec)
{
    curEffStartPer = startMsec / frameTimeInMs;
    curEffEndPer = (endMsec - 1) / frameTimeInMs;
}

void NativeRenderBuffer::GetEffectPeriods(int& startPer, int& endPer) const
{
    startPer = curEffStartPer;
    endPer = curEffEndPer;
}

// =========================================================================
// Palette
// =========================================================================

void NativeRenderBuffer::SetPalette(xlColorVector& colors)
{
    palette = colors;
    paletteHSV.clear();
    for (const auto& c : colors) {
        paletteHSV.push_back(c.asHSV());
    }
}

size_t NativeRenderBuffer::GetColorCount() const
{
    return std::max(size_t(1), palette.size());
}

// =========================================================================
// Audio Access
// =========================================================================

void* NativeRenderBuffer::GetMedia() const
{
    if (_context == nullptr) return nullptr;
    return _context->getAudioManager();
}

} // namespace xlEngine
