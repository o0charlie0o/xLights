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
 * @file ImageBuffer.h
 * @brief Raw pixel buffer for rendering operations.
 *
 * This class provides a pure C++17/20 replacement for wxImage in rendering
 * contexts. It manages RGBA pixel data with efficient access patterns
 * suitable for GPU upload and effect rendering.
 */

#include <cstdint>
#include <cstddef>
#include <vector>
#include <memory>
#include <algorithm>
#include <stdexcept>

#include "Color.h"

namespace xlCore {

/**
 * @brief Pixel format enumeration for buffer operations.
 */
enum class PixelFormat {
    RGBA,    // 4 bytes per pixel: R, G, B, A
    RGB,     // 3 bytes per pixel: R, G, B
    BGRA,    // 4 bytes per pixel: B, G, R, A (Windows DIB format)
    BGR      // 3 bytes per pixel: B, G, R
};

/**
 * @brief Raw pixel buffer for rendering operations.
 *
 * Thread-safety: Individual instances are NOT thread-safe.
 * For multi-threaded rendering, use separate buffers per thread
 * or implement external synchronization.
 */
class ImageBuffer {
public:
    /**
     * @brief Construct an empty buffer.
     */
    ImageBuffer() = default;

    /**
     * @brief Construct a buffer with specified dimensions.
     * @param width Buffer width in pixels
     * @param height Buffer height in pixels
     * @param format Pixel format (default RGBA)
     */
    ImageBuffer(size_t width, size_t height, PixelFormat format = PixelFormat::RGBA)
        : m_width(width), m_height(height), m_format(format) {
        allocate();
    }

    // Copy operations
    ImageBuffer(const ImageBuffer& other)
        : m_width(other.m_width), m_height(other.m_height), m_format(other.m_format),
          m_data(other.m_data) {}

    ImageBuffer& operator=(const ImageBuffer& other) {
        if (this != &other) {
            m_width = other.m_width;
            m_height = other.m_height;
            m_format = other.m_format;
            m_data = other.m_data;
        }
        return *this;
    }

    // Move operations
    ImageBuffer(ImageBuffer&& other) noexcept
        : m_width(other.m_width), m_height(other.m_height), m_format(other.m_format),
          m_data(std::move(other.m_data)) {
        other.m_width = 0;
        other.m_height = 0;
    }

    ImageBuffer& operator=(ImageBuffer&& other) noexcept {
        if (this != &other) {
            m_width = other.m_width;
            m_height = other.m_height;
            m_format = other.m_format;
            m_data = std::move(other.m_data);
            other.m_width = 0;
            other.m_height = 0;
        }
        return *this;
    }

    ~ImageBuffer() = default;

    // Dimension accessors
    size_t width() const { return m_width; }
    size_t height() const { return m_height; }
    size_t pixelCount() const { return m_width * m_height; }
    bool isEmpty() const { return m_data.empty(); }
    PixelFormat format() const { return m_format; }

    /**
     * @brief Get bytes per pixel for current format.
     */
    size_t bytesPerPixel() const {
        switch (m_format) {
            case PixelFormat::RGBA:
            case PixelFormat::BGRA:
                return 4;
            case PixelFormat::RGB:
            case PixelFormat::BGR:
                return 3;
        }
        return 4;
    }

    /**
     * @brief Get total buffer size in bytes.
     */
    size_t sizeBytes() const {
        return m_data.size();
    }

    /**
     * @brief Get row stride (bytes per row).
     */
    size_t stride() const {
        return m_width * bytesPerPixel();
    }

    /**
     * @brief Resize buffer (discards existing data).
     */
    void resize(size_t width, size_t height) {
        m_width = width;
        m_height = height;
        allocate();
    }

    /**
     * @brief Clear buffer to specified color.
     */
    void clear(const Color& color = Color::Black()) {
        if (m_format == PixelFormat::RGBA || m_format == PixelFormat::BGRA) {
            bool isBGR = (m_format == PixelFormat::BGRA);
            for (size_t i = 0; i < m_data.size(); i += 4) {
                if (isBGR) {
                    m_data[i] = color.blue;
                    m_data[i + 1] = color.green;
                    m_data[i + 2] = color.red;
                } else {
                    m_data[i] = color.red;
                    m_data[i + 1] = color.green;
                    m_data[i + 2] = color.blue;
                }
                m_data[i + 3] = color.alpha;
            }
        } else {
            bool isBGR = (m_format == PixelFormat::BGR);
            for (size_t i = 0; i < m_data.size(); i += 3) {
                if (isBGR) {
                    m_data[i] = color.blue;
                    m_data[i + 1] = color.green;
                    m_data[i + 2] = color.red;
                } else {
                    m_data[i] = color.red;
                    m_data[i + 1] = color.green;
                    m_data[i + 2] = color.blue;
                }
            }
        }
    }

    /**
     * @brief Clear buffer to black (optimized).
     */
    void clearBlack() {
        std::fill(m_data.begin(), m_data.end(), 0);
        // Set alpha to 255 for opaque black in RGBA/BGRA formats
        if (m_format == PixelFormat::RGBA || m_format == PixelFormat::BGRA) {
            for (size_t i = 3; i < m_data.size(); i += 4) {
                m_data[i] = 255;
            }
        }
    }

    /**
     * @brief Clear buffer to transparent (alpha = 0).
     */
    void clearTransparent() {
        std::fill(m_data.begin(), m_data.end(), 0);
    }

    // Raw data access
    uint8_t* data() { return m_data.data(); }
    const uint8_t* data() const { return m_data.data(); }

    /**
     * @brief Get pointer to specific row.
     */
    uint8_t* rowPtr(size_t y) {
        return m_data.data() + y * stride();
    }

    const uint8_t* rowPtr(size_t y) const {
        return m_data.data() + y * stride();
    }

    /**
     * @brief Get pixel at coordinates (bounds checked in debug).
     */
    Color getPixel(size_t x, size_t y) const {
#ifndef NDEBUG
        if (x >= m_width || y >= m_height) {
            throw std::out_of_range("ImageBuffer::getPixel: coordinates out of bounds");
        }
#endif
        return getPixelUnchecked(x, y);
    }

    /**
     * @brief Get pixel at coordinates (no bounds check).
     */
    Color getPixelUnchecked(size_t x, size_t y) const {
        const uint8_t* p = m_data.data() + (y * m_width + x) * bytesPerPixel();
        if (m_format == PixelFormat::RGBA) {
            return Color(p[0], p[1], p[2], p[3]);
        } else if (m_format == PixelFormat::BGRA) {
            return Color(p[2], p[1], p[0], p[3]);
        } else if (m_format == PixelFormat::RGB) {
            return Color(p[0], p[1], p[2]);
        } else { // BGR
            return Color(p[2], p[1], p[0]);
        }
    }

    /**
     * @brief Set pixel at coordinates (bounds checked in debug).
     */
    void setPixel(size_t x, size_t y, const Color& color) {
#ifndef NDEBUG
        if (x >= m_width || y >= m_height) {
            throw std::out_of_range("ImageBuffer::setPixel: coordinates out of bounds");
        }
#endif
        setPixelUnchecked(x, y, color);
    }

    /**
     * @brief Set pixel at coordinates (no bounds check).
     */
    void setPixelUnchecked(size_t x, size_t y, const Color& color) {
        uint8_t* p = m_data.data() + (y * m_width + x) * bytesPerPixel();
        if (m_format == PixelFormat::RGBA) {
            p[0] = color.red;
            p[1] = color.green;
            p[2] = color.blue;
            p[3] = color.alpha;
        } else if (m_format == PixelFormat::BGRA) {
            p[0] = color.blue;
            p[1] = color.green;
            p[2] = color.red;
            p[3] = color.alpha;
        } else if (m_format == PixelFormat::RGB) {
            p[0] = color.red;
            p[1] = color.green;
            p[2] = color.blue;
        } else { // BGR
            p[0] = color.blue;
            p[1] = color.green;
            p[2] = color.red;
        }
    }

    /**
     * @brief Set pixel with alpha blending onto existing color.
     */
    void setPixelBlended(size_t x, size_t y, const Color& color) {
        if (color.alpha == 0) return;
        if (color.alpha == 255) {
            setPixel(x, y, color);
            return;
        }

        Color existing = getPixel(x, y);
        setPixel(x, y, color.alphaBlend(existing));
    }

    /**
     * @brief Fill rectangle with color.
     */
    void fillRect(size_t x, size_t y, size_t w, size_t h, const Color& color) {
        size_t x2 = std::min(x + w, m_width);
        size_t y2 = std::min(y + h, m_height);

        for (size_t py = y; py < y2; ++py) {
            for (size_t px = x; px < x2; ++px) {
                setPixelUnchecked(px, py, color);
            }
        }
    }

    /**
     * @brief Copy from another buffer (must have same dimensions and format).
     */
    void copyFrom(const ImageBuffer& src) {
        if (m_width != src.m_width || m_height != src.m_height || m_format != src.m_format) {
            throw std::invalid_argument("ImageBuffer::copyFrom: dimension/format mismatch");
        }
        m_data = src.m_data;
    }

    /**
     * @brief Copy region from another buffer.
     * @param src Source buffer
     * @param srcX Source X coordinate
     * @param srcY Source Y coordinate
     * @param dstX Destination X coordinate
     * @param dstY Destination Y coordinate
     * @param w Width to copy
     * @param h Height to copy
     */
    void copyRegion(const ImageBuffer& src,
                    size_t srcX, size_t srcY,
                    size_t dstX, size_t dstY,
                    size_t w, size_t h) {
        // Clip to bounds
        if (srcX >= src.m_width || srcY >= src.m_height) return;
        if (dstX >= m_width || dstY >= m_height) return;

        w = std::min(w, std::min(src.m_width - srcX, m_width - dstX));
        h = std::min(h, std::min(src.m_height - srcY, m_height - dstY));

        // Row-by-row copy
        size_t bpp = bytesPerPixel();
        for (size_t row = 0; row < h; ++row) {
            const uint8_t* srcRow = src.rowPtr(srcY + row) + srcX * bpp;
            uint8_t* dstRow = rowPtr(dstY + row) + dstX * bpp;
            std::copy(srcRow, srcRow + w * bpp, dstRow);
        }
    }

    /**
     * @brief Swap contents with another buffer.
     */
    void swap(ImageBuffer& other) noexcept {
        std::swap(m_width, other.m_width);
        std::swap(m_height, other.m_height);
        std::swap(m_format, other.m_format);
        m_data.swap(other.m_data);
    }

private:
    void allocate() {
        size_t size = m_width * m_height * bytesPerPixel();
        m_data.resize(size);
        std::fill(m_data.begin(), m_data.end(), 0);
    }

    size_t m_width = 0;
    size_t m_height = 0;
    PixelFormat m_format = PixelFormat::RGBA;
    std::vector<uint8_t> m_data;
};

} // namespace xlCore
