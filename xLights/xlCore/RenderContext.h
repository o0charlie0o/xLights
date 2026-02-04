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
 * @file RenderContext.h
 * @brief Pure C++ rendering context for effect rendering.
 *
 * This class replaces the wxWidgets-dependent RenderBuffer with a
 * pure C++17/20 implementation. It provides:
 * - Efficient pixel access for effects
 * - Drawing primitives (line, circle, rectangle, ellipse)
 * - Raw buffer access for GPU transfer (Metal/OpenGL)
 * - Double-buffering support for complex effects
 *
 * Thread-safety: Individual instances are NOT thread-safe.
 * Each effect layer should have its own RenderContext.
 */

#include <cstdint>
#include <cstddef>
#include <vector>
#include <memory>
#include <algorithm>
#include <cassert>

#include "Color.h"
#include "XLMath.h"

namespace xlCore {

/**
 * @brief Rendering context for effect rendering operations.
 *
 * This is the core rendering target that all effects draw to.
 * It maintains an RGBA pixel buffer and provides drawing primitives.
 *
 * Coordinate system: (0,0) is lower-left, matching xLights convention.
 */
class RenderContext {
public:
    /**
     * @brief Construct an empty rendering context.
     */
    RenderContext() = default;

    /**
     * @brief Construct a rendering context with specified dimensions.
     * @param width Buffer width in pixels
     * @param height Buffer height in pixels
     */
    RenderContext(int width, int height);

    /**
     * @brief Destructor.
     */
    ~RenderContext() = default;

    // Copy operations
    RenderContext(const RenderContext& other);
    RenderContext& operator=(const RenderContext& other);

    // Move operations
    RenderContext(RenderContext&& other) noexcept;
    RenderContext& operator=(RenderContext&& other) noexcept;

    // ========== Dimension Accessors ==========

    /**
     * @brief Get buffer width in pixels.
     */
    int width() const { return m_width; }

    /**
     * @brief Get buffer height in pixels.
     */
    int height() const { return m_height; }

    /**
     * @brief Get total pixel count.
     */
    size_t pixelCount() const { return static_cast<size_t>(m_width) * m_height; }

    /**
     * @brief Check if buffer is empty.
     */
    bool isEmpty() const { return m_pixels.empty(); }

    /**
     * @brief Resize the buffer (discards existing data).
     */
    void resize(int width, int height);

    // ========== Pixel Access (Bounds-Checked in Debug) ==========

    /**
     * @brief Set pixel color at coordinates.
     *
     * In debug builds, coordinates are bounds-checked and will assert.
     * In release builds, out-of-bounds writes are silently ignored.
     *
     * @param x X coordinate (0 is left)
     * @param y Y coordinate (0 is bottom)
     * @param color Color to set
     */
    void setPixel(int x, int y, const Color& color) {
#ifndef NDEBUG
        assert(x >= 0 && x < m_width && "setPixel: x out of bounds");
        assert(y >= 0 && y < m_height && "setPixel: y out of bounds");
#endif
        if (x >= 0 && x < m_width && y >= 0 && y < m_height) {
            m_pixels[y * m_width + x] = color;
        }
    }

    /**
     * @brief Set pixel color with optional wrapping.
     *
     * @param x X coordinate
     * @param y Y coordinate
     * @param color Color to set
     * @param wrap If true, wrap coordinates at buffer boundaries
     */
    void setPixel(int x, int y, const Color& color, bool wrap) {
        if (wrap) {
            while (x < 0) x += m_width;
            while (y < 0) y += m_height;
            while (x >= m_width) x -= m_width;
            while (y >= m_height) y -= m_height;
        }
        if (x >= 0 && x < m_width && y >= 0 && y < m_height) {
            m_pixels[y * m_width + x] = color;
        }
    }

    /**
     * @brief Set pixel color with alpha blending.
     *
     * Blends the new color onto the existing pixel using alpha.
     *
     * @param x X coordinate
     * @param y Y coordinate
     * @param color Color to blend (uses color.alpha for blending)
     */
    void setPixelBlended(int x, int y, const Color& color);

    /**
     * @brief Get pixel color at coordinates.
     *
     * In debug builds, coordinates are bounds-checked and will assert.
     * In release builds, out-of-bounds reads return black.
     *
     * @param x X coordinate
     * @param y Y coordinate
     * @return Color at (x, y) or black if out of bounds
     */
    Color getPixel(int x, int y) const {
#ifndef NDEBUG
        assert(x >= 0 && x < m_width && "getPixel: x out of bounds");
        assert(y >= 0 && y < m_height && "getPixel: y out of bounds");
#endif
        if (x >= 0 && x < m_width && y >= 0 && y < m_height) {
            return m_pixels[y * m_width + x];
        }
        return Color::Black();
    }

    /**
     * @brief Get pixel color at coordinates (output parameter version).
     */
    void getPixel(int x, int y, Color& color) const {
        color = getPixel(x, y);
    }

    // ========== Unchecked Pixel Access (For Performance-Critical Code) ==========

    /**
     * @brief Set pixel without bounds checking.
     *
     * DANGER: No bounds checking is performed. Caller must ensure
     * coordinates are valid: 0 <= x < width() and 0 <= y < height().
     */
    void setPixelUnchecked(int x, int y, const Color& color) {
        m_pixels[y * m_width + x] = color;
    }

    /**
     * @brief Get pixel without bounds checking.
     *
     * DANGER: No bounds checking is performed. Caller must ensure
     * coordinates are valid: 0 <= x < width() and 0 <= y < height().
     */
    Color getPixelUnchecked(int x, int y) const {
        return m_pixels[y * m_width + x];
    }

    /**
     * @brief Get reference to pixel without bounds checking.
     */
    const Color& getPixelRefUnchecked(int x, int y) const {
        return m_pixels[y * m_width + x];
    }

    /**
     * @brief Get mutable reference to pixel without bounds checking.
     */
    Color& getPixelRefUnchecked(int x, int y) {
        return m_pixels[y * m_width + x];
    }

    // ========== Bulk Operations ==========

    /**
     * @brief Clear buffer to black.
     */
    void clear();

    /**
     * @brief Clear buffer to transparent black (alpha = 0).
     */
    void clearTransparent();

    /**
     * @brief Fill buffer with a single color.
     */
    void fill(const Color& color);

    /**
     * @brief Copy all pixels from another context.
     *
     * Dimensions must match or source will be clipped/padded.
     */
    void copyFrom(const RenderContext& other);

    /**
     * @brief Alpha-blend another context onto this one.
     *
     * Dimensions must match.
     */
    void alphaBlend(const RenderContext& src);

    /**
     * @brief Copy a pixel from one location to another.
     */
    void copyPixel(int srcX, int srcY, int dstX, int dstY);

    // ========== Drawing Primitives ==========

    /**
     * @brief Draw a horizontal line.
     * @param y Y coordinate
     * @param x1 Start X coordinate
     * @param x2 End X coordinate
     * @param color Line color
     * @param wrap If true, wrap at boundaries
     */
    void drawHLine(int y, int x1, int x2, const Color& color, bool wrap = false);

    /**
     * @brief Draw a vertical line.
     * @param x X coordinate
     * @param y1 Start Y coordinate
     * @param y2 End Y coordinate
     * @param color Line color
     * @param wrap If true, wrap at boundaries
     */
    void drawVLine(int x, int y1, int y2, const Color& color, bool wrap = false);

    /**
     * @brief Draw a line using Bresenham's algorithm.
     * @param x1 Start X coordinate
     * @param y1 Start Y coordinate
     * @param x2 End X coordinate
     * @param y2 End Y coordinate
     * @param color Line color
     * @param useAlpha If true, use alpha blending
     */
    void drawLine(int x1, int y1, int x2, int y2, const Color& color, bool useAlpha = false);

    /**
     * @brief Draw a thick line.
     * @param x1 Start X coordinate
     * @param y1 Start Y coordinate
     * @param x2 End X coordinate
     * @param y2 End Y coordinate
     * @param color Line color
     * @param thickness Line thickness in pixels
     * @param useAlpha If true, use alpha blending
     */
    void drawThickLine(int x1, int y1, int x2, int y2, const Color& color, int thickness, bool useAlpha = false);

    /**
     * @brief Draw a rectangle.
     * @param x1 First corner X
     * @param y1 First corner Y
     * @param x2 Second corner X
     * @param y2 Second corner Y
     * @param color Rectangle color
     * @param filled If true, fill the rectangle
     * @param wrap If true, wrap at boundaries
     * @param useAlpha If true, use alpha blending
     */
    void drawRect(int x1, int y1, int x2, int y2, const Color& color, bool filled = false, bool wrap = false, bool useAlpha = false);

    /**
     * @brief Draw a circle using Bresenham's algorithm.
     * @param cx Center X coordinate
     * @param cy Center Y coordinate
     * @param radius Circle radius
     * @param color Circle color
     * @param filled If true, fill the circle
     * @param wrap If true, wrap at boundaries
     */
    void drawCircle(int cx, int cy, int radius, const Color& color, bool filled = false, bool wrap = false);

    /**
     * @brief Draw a fading circle (brightness decreases from center).
     * @param cx Center X coordinate
     * @param cy Center Y coordinate
     * @param radius Circle radius
     * @param color Circle color (center color, fades to transparent at edge)
     * @param wrap If true, wrap at boundaries
     */
    void drawFadingCircle(int cx, int cy, int radius, const Color& color, bool wrap = false);

    /**
     * @brief Draw an ellipse.
     * @param cx Center X coordinate
     * @param cy Center Y coordinate
     * @param rx Horizontal radius
     * @param ry Vertical radius
     * @param color Ellipse color
     * @param filled If true, fill the ellipse
     * @param wrap If true, wrap at boundaries
     */
    void drawEllipse(int cx, int cy, int rx, int ry, const Color& color, bool filled = false, bool wrap = false);

    /**
     * @brief Fill a convex polygon.
     * @param points Vector of (x, y) coordinate pairs
     * @param color Fill color
     */
    void fillConvexPoly(const std::vector<Point2D>& points, const Color& color);

    // ========== Raw Data Access for GPU Transfer ==========

    /**
     * @brief Get pointer to raw pixel data (RGBA format).
     *
     * Pixel at (x,y) is at offset: (y * width + x)
     * Each pixel is 4 bytes: R, G, B, A
     */
    const uint8_t* pixelData() const {
        return reinterpret_cast<const uint8_t*>(m_pixels.data());
    }

    /**
     * @brief Get mutable pointer to raw pixel data.
     */
    uint8_t* pixelData() {
        return reinterpret_cast<uint8_t*>(m_pixels.data());
    }

    /**
     * @brief Get raw pixel data size in bytes.
     */
    size_t pixelDataSize() const {
        return m_pixels.size() * sizeof(Color);
    }

    /**
     * @brief Get bytes per row (stride).
     */
    size_t bytesPerRow() const {
        return static_cast<size_t>(m_width) * sizeof(Color);
    }

    /**
     * @brief Get pointer to Color array.
     */
    Color* pixels() { return m_pixels.data(); }
    const Color* pixels() const { return m_pixels.data(); }

    // ========== Double Buffering Support ==========

    /**
     * @brief Swap pixels with temp buffer.
     *
     * After this call, what was in the main buffer is in temp,
     * and what was in temp is in the main buffer.
     */
    void swapBuffers();

    /**
     * @brief Clear the temp buffer to black.
     */
    void clearTempBuffer();

    /**
     * @brief Clear the temp buffer to transparent.
     */
    void clearTempBufferTransparent();

    /**
     * @brief Set pixel in temp buffer.
     */
    void setTempPixel(int x, int y, const Color& color);

    /**
     * @brief Set pixel in temp buffer with alpha value.
     */
    void setTempPixel(int x, int y, const Color& color, uint8_t alpha);

    /**
     * @brief Get pixel from temp buffer.
     */
    Color getTempPixel(int x, int y) const;

    /**
     * @brief Get pixel from temp buffer (output parameter version).
     */
    void getTempPixel(int x, int y, Color& color) const;

    /**
     * @brief Copy temp buffer to main pixel buffer.
     */
    void copyTempToPixels();

    /**
     * @brief Copy main pixel buffer to temp buffer.
     */
    void copyPixelsToTemp();

    /**
     * @brief Get direct access to temp buffer.
     */
    Color* tempBuffer() { return m_tempBuffer.data(); }
    const Color* tempBuffer() const { return m_tempBuffer.data(); }

    // ========== Allow Alpha Flag ==========

    /**
     * @brief Set whether alpha channel effects are allowed.
     *
     * Some effects need to know if they can use alpha transparency.
     */
    void setAllowAlpha(bool allow) { m_allowAlpha = allow; }
    bool allowAlpha() const { return m_allowAlpha; }

private:
    std::vector<Color> m_pixels;
    std::vector<Color> m_tempBuffer;
    int m_width = 0;
    int m_height = 0;
    bool m_allowAlpha = false;

    /**
     * @brief Allocate pixel storage.
     */
    void allocate();

    /**
     * @brief Internal ellipse drawing helper.
     */
    void drawEllipseInternal(int cx, int cy, int rx, int ry, const Color& color, bool filled, bool wrap);
};

} // namespace xlCore
