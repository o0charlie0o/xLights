/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "RenderContext.h"
#include <cmath>
#include <cstring>
#include <utility>

namespace xlCore {

// ========== Construction / Assignment ==========

RenderContext::RenderContext(int width, int height)
    : m_width(width), m_height(height) {
    allocate();
}

RenderContext::RenderContext(const RenderContext& other)
    : m_pixels(other.m_pixels)
    , m_tempBuffer(other.m_tempBuffer)
    , m_width(other.m_width)
    , m_height(other.m_height)
    , m_allowAlpha(other.m_allowAlpha) {
}

RenderContext& RenderContext::operator=(const RenderContext& other) {
    if (this != &other) {
        m_pixels = other.m_pixels;
        m_tempBuffer = other.m_tempBuffer;
        m_width = other.m_width;
        m_height = other.m_height;
        m_allowAlpha = other.m_allowAlpha;
    }
    return *this;
}

RenderContext::RenderContext(RenderContext&& other) noexcept
    : m_pixels(std::move(other.m_pixels))
    , m_tempBuffer(std::move(other.m_tempBuffer))
    , m_width(other.m_width)
    , m_height(other.m_height)
    , m_allowAlpha(other.m_allowAlpha) {
    other.m_width = 0;
    other.m_height = 0;
}

RenderContext& RenderContext::operator=(RenderContext&& other) noexcept {
    if (this != &other) {
        m_pixels = std::move(other.m_pixels);
        m_tempBuffer = std::move(other.m_tempBuffer);
        m_width = other.m_width;
        m_height = other.m_height;
        m_allowAlpha = other.m_allowAlpha;
        other.m_width = 0;
        other.m_height = 0;
    }
    return *this;
}

void RenderContext::allocate() {
    size_t count = static_cast<size_t>(m_width) * m_height;
    m_pixels.resize(count);
    m_tempBuffer.resize(count);
    clear();
    clearTempBuffer();
}

void RenderContext::resize(int width, int height) {
    m_width = width;
    m_height = height;
    allocate();
}

// ========== Bulk Operations ==========

void RenderContext::clear() {
    std::fill(m_pixels.begin(), m_pixels.end(), Color::Black());
}

void RenderContext::clearTransparent() {
    std::fill(m_pixels.begin(), m_pixels.end(), Color::nil());
}

void RenderContext::fill(const Color& color) {
    std::fill(m_pixels.begin(), m_pixels.end(), color);
}

void RenderContext::copyFrom(const RenderContext& other) {
    if (m_width == other.m_width && m_height == other.m_height) {
        m_pixels = other.m_pixels;
    } else {
        // Clip/pad copy
        clear();
        int copyW = std::min(m_width, other.m_width);
        int copyH = std::min(m_height, other.m_height);
        for (int y = 0; y < copyH; ++y) {
            for (int x = 0; x < copyW; ++x) {
                m_pixels[y * m_width + x] = other.m_pixels[y * other.m_width + x];
            }
        }
    }
}

void RenderContext::alphaBlend(const RenderContext& src) {
    if (src.m_width != m_width || src.m_height != m_height) {
        return;
    }

    size_t count = m_pixels.size();
    for (size_t i = 0; i < count; ++i) {
        const Color& srcPixel = src.m_pixels[i];
        Color& dstPixel = m_pixels[i];

        if (srcPixel.alpha == 255 || (dstPixel.red == 0 && dstPixel.green == 0 && dstPixel.blue == 0)) {
            dstPixel = srcPixel;
        } else if (srcPixel.alpha > 0 && !(srcPixel.red == 0 && srcPixel.green == 0 && srcPixel.blue == 0)) {
            int r = srcPixel.red + dstPixel.red * (255 - srcPixel.alpha) / 255;
            if (r > 255) r = 255;
            dstPixel.red = static_cast<uint8_t>(r);

            int g = srcPixel.green + dstPixel.green * (255 - srcPixel.alpha) / 255;
            if (g > 255) g = 255;
            dstPixel.green = static_cast<uint8_t>(g);

            int b = srcPixel.blue + dstPixel.blue * (255 - srcPixel.alpha) / 255;
            if (b > 255) b = 255;
            dstPixel.blue = static_cast<uint8_t>(b);

            int a = srcPixel.alpha + dstPixel.alpha * (255 - srcPixel.alpha) / 255;
            if (a > 255) a = 255;
            dstPixel.alpha = static_cast<uint8_t>(a);
        }
    }
}

void RenderContext::copyPixel(int srcX, int srcY, int dstX, int dstY) {
    if (srcX >= 0 && srcX < m_width && srcY >= 0 && srcY < m_height &&
        dstX >= 0 && dstX < m_width && dstY >= 0 && dstY < m_height) {
        m_pixels[dstY * m_width + dstX] = m_pixels[srcY * m_width + srcX];
    }
}

void RenderContext::setPixelBlended(int x, int y, const Color& color) {
    if (x < 0 || x >= m_width || y < 0 || y >= m_height) {
        return;
    }

    if (color.alpha == 0) {
        return;
    }

    if (color.alpha == 255) {
        m_pixels[y * m_width + x] = color;
        return;
    }

    Color& dst = m_pixels[y * m_width + x];
    int r = color.red + dst.red * (255 - color.alpha) / 255;
    if (r > 255) r = 255;
    dst.red = static_cast<uint8_t>(r);

    int g = color.green + dst.green * (255 - color.alpha) / 255;
    if (g > 255) g = 255;
    dst.green = static_cast<uint8_t>(g);

    int b = color.blue + dst.blue * (255 - color.alpha) / 255;
    if (b > 255) b = 255;
    dst.blue = static_cast<uint8_t>(b);

    int a = color.alpha + dst.alpha * (255 - color.alpha) / 255;
    if (a > 255) a = 255;
    dst.alpha = static_cast<uint8_t>(a);
}

// ========== Drawing Primitives ==========

void RenderContext::drawHLine(int y, int x1, int x2, const Color& color, bool wrap) {
    if (x1 > x2) {
        std::swap(x1, x2);
    }
    for (int x = x1; x <= x2; ++x) {
        setPixel(x, y, color, wrap);
    }
}

void RenderContext::drawVLine(int x, int y1, int y2, const Color& color, bool wrap) {
    if (y1 > y2) {
        std::swap(y1, y2);
    }
    for (int y = y1; y <= y2; ++y) {
        setPixel(x, y, color, wrap);
    }
}

// Bresenham's line algorithm
void RenderContext::drawLine(int x1, int y1, int x2, int y2, const Color& color, bool useAlpha) {
    int x0 = x1;
    int y0 = y1;

    int dx = std::abs(x2 - x0);
    int dy = std::abs(y2 - y0);
    int sx = x0 < x2 ? 1 : -1;
    int sy = y0 < y2 ? 1 : -1;
    int err = (dx > dy ? dx : -dy) / 2;

    for (;;) {
        if (useAlpha) {
            setPixelBlended(x0, y0, color);
        } else {
            setPixel(x0, y0, color);
        }

        if (x0 == x2 && y0 == y2) {
            break;
        }

        int e2 = err;
        if (e2 > -dx) {
            err -= dy;
            x0 += sx;
        }
        if (e2 < dy) {
            err += dx;
            y0 += sy;
        }
    }
}

void RenderContext::drawThickLine(int x1, int y1, int x2, int y2, const Color& color, int thickness, bool useAlpha) {
    if (thickness < 1) return;

    if (thickness == 1) {
        drawLine(x1, y1, x2, y2, color, useAlpha);
        return;
    }

    // Draw circles at endpoints
    drawCircle(x1, y1, thickness / 2, color, true);
    drawCircle(x2, y2, thickness / 2, color, true);

    // Draw multiple offset lines
    for (int i = 0; i < thickness; ++i) {
        int adjust = i - thickness / 2;
        drawLine(x1 + adjust, y1, x2 + adjust, y2, color, useAlpha);
        drawLine(x1, y1 + adjust, x2, y2 + adjust, color, useAlpha);
        drawLine(x1 + adjust, y1 + adjust, x2 + adjust, y2 + adjust, color, useAlpha);
    }
}

void RenderContext::drawRect(int x1, int y1, int x2, int y2, const Color& color, bool filled, bool wrap, bool useAlpha) {
    if (y1 > y2) std::swap(y1, y2);
    if (x1 > x2) std::swap(x1, x2);

    if (filled) {
        for (int y = y1; y <= y2; ++y) {
            for (int x = x1; x <= x2; ++x) {
                if (useAlpha) {
                    setPixelBlended(x, y, color);
                } else {
                    setPixel(x, y, color, wrap);
                }
            }
        }
    } else {
        // Draw outline only
        drawHLine(y1, x1, x2, color, wrap);
        drawHLine(y2, x1, x2, color, wrap);
        drawVLine(x1, y1, y2, color, wrap);
        drawVLine(x2, y1, y2, color, wrap);
    }
}

// Bresenham's circle algorithm
void RenderContext::drawCircle(int cx, int cy, int radius, const Color& color, bool filled, bool wrap) {
    int x = radius;
    int y = 0;
    int radiusError = 1 - x;

    while (x >= y) {
        if (!filled) {
            setPixel(x + cx, y + cy, color, wrap);
            setPixel(y + cx, x + cy, color, wrap);
            setPixel(-x + cx, y + cy, color, wrap);
            setPixel(-y + cx, x + cy, color, wrap);
            setPixel(-x + cx, -y + cy, color, wrap);
            setPixel(-y + cx, -x + cy, color, wrap);
            setPixel(x + cx, -y + cy, color, wrap);
            setPixel(y + cx, -x + cy, color, wrap);
        } else {
            drawVLine(cx - x, cy - y, cy + y, color, wrap);
            drawVLine(cx + x, cy - y, cy + y, color, wrap);
            drawVLine(cx - y, cy - x, cy + x, color, wrap);
            drawVLine(cx + y, cy - x, cy + x, color, wrap);
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

void RenderContext::drawFadingCircle(int cx, int cy, int radius, const Color& color, bool wrap) {
    HSV hsv = color.toHSV();
    double fullValue = hsv.value;

    for (int x = -radius; x < radius; ++x) {
        for (int y = -radius; y < radius; ++y) {
            double d = std::sqrt(static_cast<double>(x * x + y * y));
            if (d <= radius) {
                if (m_allowAlpha) {
                    double alpha = static_cast<double>(color.alpha) - (static_cast<double>(color.alpha) * d) / static_cast<double>(radius);
                    if (alpha > 0.0) {
                        Color c = color;
                        c.alpha = static_cast<uint8_t>(alpha);
                        setPixel(x + cx, y + cy, c, wrap);
                    }
                } else {
                    double newValue = fullValue - (fullValue * d) / static_cast<double>(radius);
                    if (newValue > 0.0) {
                        HSV newHsv = hsv;
                        newHsv.value = newValue;
                        Color c(newHsv);
                        setPixel(x + cx, y + cy, c, wrap);
                    }
                }
            }
        }
    }
}

// Midpoint ellipse algorithm
void RenderContext::drawEllipse(int cx, int cy, int rx, int ry, const Color& color, bool filled, bool wrap) {
    if (rx <= 0 || ry <= 0) return;

    drawEllipseInternal(cx, cy, rx, ry, color, filled, wrap);
}

void RenderContext::drawEllipseInternal(int cx, int cy, int rx, int ry, const Color& color, bool filled, bool wrap) {
    // Midpoint ellipse algorithm
    int x = 0;
    int y = ry;

    // Region 1
    int64_t rx2 = static_cast<int64_t>(rx) * rx;
    int64_t ry2 = static_cast<int64_t>(ry) * ry;
    int64_t twoRx2 = 2 * rx2;
    int64_t twoRy2 = 2 * ry2;

    int64_t px = 0;
    int64_t py = twoRx2 * y;

    // Region 1 decision parameter
    int64_t p1 = ry2 - (rx2 * ry) + (rx2 / 4);

    while (px < py) {
        if (!filled) {
            setPixel(cx + x, cy + y, color, wrap);
            setPixel(cx - x, cy + y, color, wrap);
            setPixel(cx + x, cy - y, color, wrap);
            setPixel(cx - x, cy - y, color, wrap);
        } else {
            drawHLine(cy + y, cx - x, cx + x, color, wrap);
            drawHLine(cy - y, cx - x, cx + x, color, wrap);
        }

        x++;
        px += twoRy2;

        if (p1 < 0) {
            p1 += ry2 + px;
        } else {
            y--;
            py -= twoRx2;
            p1 += ry2 + px - py;
        }
    }

    // Region 2
    int64_t p2 = ry2 * (x + 0.5) * (x + 0.5) + rx2 * (y - 1) * (y - 1) - rx2 * ry2;

    while (y >= 0) {
        if (!filled) {
            setPixel(cx + x, cy + y, color, wrap);
            setPixel(cx - x, cy + y, color, wrap);
            setPixel(cx + x, cy - y, color, wrap);
            setPixel(cx - x, cy - y, color, wrap);
        } else {
            drawHLine(cy + y, cx - x, cx + x, color, wrap);
            drawHLine(cy - y, cx - x, cx + x, color, wrap);
        }

        y--;
        py -= twoRx2;

        if (p2 > 0) {
            p2 += rx2 - py;
        } else {
            x++;
            px += twoRy2;
            p2 += rx2 - py + px;
        }
    }
}

// Convex polygon fill using scan line algorithm
void RenderContext::fillConvexPoly(const std::vector<Point2D>& opoly, const Color& color) {
    if (opoly.empty()) return;

    // Remove consecutive duplicate points
    std::vector<Point2D> poly;
    poly.push_back(opoly[0]);
    for (size_t i = 1; i < opoly.size(); ++i) {
        if (opoly[i] != opoly[i - 1]) {
            poly.push_back(opoly[i]);
        }
    }
    if (!poly.empty() && poly[0] == poly[poly.size() - 1]) {
        poly.pop_back();
    }

    if (poly.size() < 3) return;

    // Find min/max Y and corresponding indices
    int minY = poly[0].y;
    int maxY = poly[0].y;
    int minX = poly[0].x;
    int maxX = poly[0].x;
    size_t minYIdx = 0;

    for (size_t i = 1; i < poly.size(); ++i) {
        if (poly[i].y < minY) {
            minY = poly[i].y;
            minYIdx = i;
        }
        maxY = std::max(maxY, poly[i].y);
        minX = std::min(minX, poly[i].x);
        maxX = std::max(maxX, poly[i].x);
    }

    // Early exit if off-screen
    if (maxX < 0 || minX >= m_width) return;
    if (maxY < 0 || minY >= m_height) return;
    if (minY == maxY) return;

    // Simple scan line fill
    for (int y = minY; y <= maxY; ++y) {
        if (y < 0 || y >= m_height) continue;

        // Find intersections with polygon edges
        std::vector<int> intersections;

        for (size_t i = 0; i < poly.size(); ++i) {
            size_t j = (i + 1) % poly.size();
            int y1 = poly[i].y;
            int y2 = poly[j].y;
            int x1 = poly[i].x;
            int x2 = poly[j].x;

            if ((y1 <= y && y < y2) || (y2 <= y && y < y1)) {
                // Edge crosses this scanline
                int x = x1 + (y - y1) * (x2 - x1) / (y2 - y1);
                intersections.push_back(x);
            }
        }

        // Sort intersections
        std::sort(intersections.begin(), intersections.end());

        // Fill between pairs
        for (size_t i = 0; i + 1 < intersections.size(); i += 2) {
            int startX = std::max(0, intersections[i]);
            int endX = std::min(m_width - 1, intersections[i + 1]);
            for (int x = startX; x <= endX; ++x) {
                setPixelUnchecked(x, y, color);
            }
        }
    }
}

// ========== Double Buffering ==========

void RenderContext::swapBuffers() {
    m_pixels.swap(m_tempBuffer);
}

void RenderContext::clearTempBuffer() {
    std::fill(m_tempBuffer.begin(), m_tempBuffer.end(), Color::Black());
}

void RenderContext::clearTempBufferTransparent() {
    std::fill(m_tempBuffer.begin(), m_tempBuffer.end(), Color::nil());
}

void RenderContext::setTempPixel(int x, int y, const Color& color) {
    if (x >= 0 && x < m_width && y >= 0 && y < m_height) {
        m_tempBuffer[y * m_width + x] = color;
    }
}

void RenderContext::setTempPixel(int x, int y, const Color& color, uint8_t alpha) {
    Color c = color;
    c.alpha = alpha;
    setTempPixel(x, y, c);
}

Color RenderContext::getTempPixel(int x, int y) const {
    if (x >= 0 && x < m_width && y >= 0 && y < m_height) {
        return m_tempBuffer[y * m_width + x];
    }
    return m_allowAlpha ? Color::nil() : Color::Black();
}

void RenderContext::getTempPixel(int x, int y, Color& color) const {
    color = getTempPixel(x, y);
}

void RenderContext::copyTempToPixels() {
    std::memcpy(m_pixels.data(), m_tempBuffer.data(), m_pixels.size() * sizeof(Color));
}

void RenderContext::copyPixelsToTemp() {
    std::memcpy(m_tempBuffer.data(), m_pixels.data(), m_tempBuffer.size() * sizeof(Color));
}

} // namespace xlCore
