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
 * @file GlediatorEffect.h
 * @brief Glediator file playback effect for xlCore.
 *
 * This effect plays back Glediator (.gled, .out) and CSV format files
 * which contain pre-rendered RGB data for matrix displays.
 *
 * Glediator file format:
 * - Raw RGB data, 3 bytes per pixel
 * - One frame per width*height*3 bytes
 * - No header, just raw data
 *
 * CSV file format:
 * - One frame per line
 * - Comma-separated channel values
 * - Single byte per channel (grayscale mode)
 */

#include "../Effect.h"

#include <fstream>
#include <memory>
#include <string>
#include <vector>

namespace xlCore {

/**
 * @brief Duration treatment options for Glediator effect.
 */
enum class GlediatorDurationTreatment {
    Normal,         // Play at normal speed
    Loop,           // Loop when data ends
    SlowAccelerate  // Adjust speed to match effect duration
};

/**
 * @brief Parse duration treatment string.
 */
GlediatorDurationTreatment parseGlediatorDurationTreatment(const std::string& treatment);

/**
 * @brief Reader for Glediator binary files (.gled, .out).
 */
class GlediatorFileReader {
public:
    GlediatorFileReader() = default;
    ~GlediatorFileReader();

    /**
     * @brief Open a Glediator file.
     *
     * @param filename Path to the file
     * @param width Expected matrix width
     * @param height Expected matrix height
     * @return true if file was opened successfully
     */
    bool open(const std::string& filename, int width, int height);

    /**
     * @brief Close the file.
     */
    void close();

    /**
     * @brief Check if file is open.
     */
    bool isOpen() const { return m_file.is_open(); }

    /**
     * @brief Get frame count.
     */
    size_t frameCount() const { return m_frameCount; }

    /**
     * @brief Get frame buffer size in bytes.
     */
    size_t frameSize() const { return m_frameSize; }

    /**
     * @brief Read a frame into buffer.
     *
     * @param frameIndex Frame to read (0-based)
     * @param buffer Output buffer (must be at least frameSize() bytes)
     * @return true if frame was read successfully
     */
    bool readFrame(size_t frameIndex, uint8_t* buffer);

private:
    std::ifstream m_file;
    std::string m_filename;
    int m_width = 0;
    int m_height = 0;
    size_t m_frameSize = 0;
    size_t m_frameCount = 0;
};

/**
 * @brief Reader for CSV format files.
 */
class CSVFileReader {
public:
    CSVFileReader() = default;
    ~CSVFileReader();

    /**
     * @brief Open a CSV file.
     *
     * @param filename Path to the file
     * @return true if file was opened successfully
     */
    bool open(const std::string& filename);

    /**
     * @brief Close the file.
     */
    void close();

    /**
     * @brief Check if file is open.
     */
    bool isOpen() const { return m_isOpen; }

    /**
     * @brief Get frame count.
     */
    size_t frameCount() const { return m_lines.size(); }

    /**
     * @brief Read a frame into buffer.
     *
     * @param frameIndex Frame to read (0-based)
     * @param buffer Output buffer
     * @param maxSize Maximum bytes to write
     * @return Number of bytes written
     */
    size_t readFrame(size_t frameIndex, uint8_t* buffer, size_t maxSize);

private:
    bool m_isOpen = false;
    std::string m_filename;
    std::vector<std::string> m_lines;
};

/**
 * @brief Render cache for Glediator effect.
 */
class GlediatorRenderCache {
public:
    GlediatorRenderCache() = default;
    ~GlediatorRenderCache() = default;

    std::unique_ptr<GlediatorFileReader> glediatorReader;
    std::unique_ptr<CSVFileReader> csvReader;
    std::string currentFile;
    int loops = 0;
    float frameMs = 50.0f;

    void reset() {
        glediatorReader.reset();
        csvReader.reset();
        currentFile.clear();
        loops = 0;
        frameMs = 50.0f;
    }
};

/**
 * @brief Glediator file playback effect.
 */
class GlediatorEffect : public Effect {
public:
    GlediatorEffect();
    ~GlediatorEffect() override = default;

    // ========== Identity ==========
    std::string name() const override { return "Glediator"; }
    std::string description() const override { return "Play Glediator format files"; }
    std::string category() const override { return "Media"; }

    // ========== Rendering ==========
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // ========== Capabilities ==========
    bool canBeRandom() const override { return false; }
    bool supportsRenderCache(const EffectSettings& settings) const override { return true; }

    // ========== Parameters ==========
    std::vector<EffectParameter> parameters() const override;

    // ========== File References ==========
    std::vector<std::string> fileReferences(const EffectSettings& settings) const override;

    // ========== Cloning ==========
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<GlediatorEffect>(*this);
    }

    // ========== Utility ==========

    /**
     * @brief Check if file is a Glediator format file.
     */
    static bool isGlediatorFile(const std::string& path);

    /**
     * @brief Check if file is a CSV format file.
     */
    static bool isCSVFile(const std::string& path);

private:
    mutable std::unique_ptr<GlediatorRenderCache> m_cache;
};

} // namespace xlCore
