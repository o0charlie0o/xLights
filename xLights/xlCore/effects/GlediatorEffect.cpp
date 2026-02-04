/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "GlediatorEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../StringUtils.h"

#include <algorithm>
#include <sstream>
#include <cctype>

namespace xlCore {

// ============================================================================
// Duration Treatment Parsing
// ============================================================================

GlediatorDurationTreatment parseGlediatorDurationTreatment(const std::string& treatment) {
    if (treatment == "Loop") return GlediatorDurationTreatment::Loop;
    if (treatment == "Slow/Accelerate") return GlediatorDurationTreatment::SlowAccelerate;
    return GlediatorDurationTreatment::Normal;
}

// ============================================================================
// GlediatorFileReader Implementation
// ============================================================================

GlediatorFileReader::~GlediatorFileReader() {
    close();
}

bool GlediatorFileReader::open(const std::string& filename, int width, int height) {
    close();

    m_filename = filename;
    m_width = width;
    m_height = height;
    m_frameSize = static_cast<size_t>(width) * height * 3; // RGB, 3 bytes per pixel

    m_file.open(filename, std::ios::binary);
    if (!m_file.is_open()) {
        return false;
    }

    // Get file size to calculate frame count
    m_file.seekg(0, std::ios::end);
    size_t fileSize = m_file.tellg();
    m_file.seekg(0, std::ios::beg);

    if (m_frameSize > 0) {
        m_frameCount = fileSize / m_frameSize;
    } else {
        m_frameCount = 0;
    }

    return m_frameCount > 0;
}

void GlediatorFileReader::close() {
    if (m_file.is_open()) {
        m_file.close();
    }
    m_frameCount = 0;
}

bool GlediatorFileReader::readFrame(size_t frameIndex, uint8_t* buffer) {
    if (!m_file.is_open() || frameIndex >= m_frameCount || !buffer) {
        // Fill with red for invalid frame
        for (size_t i = 0; i < m_frameSize; i += 3) {
            buffer[i] = 255;     // R
            buffer[i + 1] = 0;   // G
            buffer[i + 2] = 0;   // B
        }
        return false;
    }

    size_t offset = frameIndex * m_frameSize;
    m_file.seekg(offset, std::ios::beg);
    m_file.read(reinterpret_cast<char*>(buffer), m_frameSize);

    return m_file.good();
}

// ============================================================================
// CSVFileReader Implementation
// ============================================================================

CSVFileReader::~CSVFileReader() {
    close();
}

bool CSVFileReader::open(const std::string& filename) {
    close();

    m_filename = filename;
    std::ifstream file(filename);
    if (!file.is_open()) {
        return false;
    }

    // Read all lines into memory
    m_lines.clear();
    std::string line;
    while (std::getline(file, line)) {
        // Trim whitespace
        size_t start = line.find_first_not_of(" \t\r\n");
        if (start == std::string::npos) continue;
        size_t end = line.find_last_not_of(" \t\r\n");
        line = line.substr(start, end - start + 1);

        if (!line.empty()) {
            m_lines.push_back(line);
        }
    }

    m_isOpen = !m_lines.empty();
    return m_isOpen;
}

void CSVFileReader::close() {
    m_lines.clear();
    m_isOpen = false;
}

size_t CSVFileReader::readFrame(size_t frameIndex, uint8_t* buffer, size_t maxSize) {
    if (!m_isOpen || frameIndex >= m_lines.size() || !buffer) {
        return 0;
    }

    const std::string& line = m_lines[frameIndex];
    std::istringstream iss(line);
    std::string token;
    size_t bytesWritten = 0;

    while (std::getline(iss, token, ',') && bytesWritten < maxSize) {
        int value = strings::parseInt(token, 0);
        buffer[bytesWritten++] = static_cast<uint8_t>(std::clamp(value, 0, 255));
    }

    return bytesWritten;
}

// ============================================================================
// GlediatorEffect Implementation
// ============================================================================

GlediatorEffect::GlediatorEffect() = default;

std::vector<EffectParameter> GlediatorEffect::parameters() const {
    std::vector<EffectParameter> params;

    // File picker
    auto file = EffectParameter::createFile(
        "E_FILEPICKERCTRL_Glediator_Filename",
        "Glediator File",
        "Glediator files|*.gled;*.out;*.csv");
    file.group = "File";
    params.push_back(file);

    // Duration treatment
    auto duration = EffectParameter::createChoice(
        "E_CHOICE_Glediator_DurationTreatment",
        "Duration Treatment",
        "Normal",
        {"Normal", "Loop", "Slow/Accelerate"});
    duration.group = "Timing";
    params.push_back(duration);

    return params;
}

std::vector<std::string> GlediatorEffect::fileReferences(const EffectSettings& settings) const {
    std::vector<std::string> refs;
    std::string file = settings.get("E_FILEPICKERCTRL_Glediator_Filename");
    if (!file.empty()) {
        refs.push_back(file);
    }
    return refs;
}

bool GlediatorEffect::isGlediatorFile(const std::string& path) {
    size_t dotPos = path.rfind('.');
    if (dotPos == std::string::npos) return false;

    std::string ext = path.substr(dotPos + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) { return std::tolower(c); });

    return (ext == "gled" || ext == "csv" || ext == "out");
}

bool GlediatorEffect::isCSVFile(const std::string& path) {
    size_t dotPos = path.rfind('.');
    if (dotPos == std::string::npos) return false;

    std::string ext = path.substr(dotPos + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) { return std::tolower(c); });

    return (ext == "csv");
}

void GlediatorEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Initialize cache if needed
    if (!m_cache) {
        m_cache = std::make_unique<GlediatorRenderCache>();
    }

    // Get parameters
    std::string filename = settings.get("E_FILEPICKERCTRL_Glediator_Filename");
    std::string durationStr = settings.get("E_CHOICE_Glediator_DurationTreatment", "Normal");
    GlediatorDurationTreatment durationTreatment = parseGlediatorDurationTreatment(durationStr);

    int bufferWi = state.bufferWidth;
    int bufferHt = state.bufferHeight;

    // Handle empty filename
    if (filename.empty()) {
        ctx.fill(Color::Red());
        return;
    }

    // Initialize on first frame
    if (state.frameIndex == 0) {
        m_cache->reset();
        m_cache->frameMs = 50.0f; // Assume 20fps default

        if (isCSVFile(filename)) {
            auto reader = std::make_unique<CSVFileReader>();
            if (reader->open(filename)) {
                m_cache->csvReader = std::move(reader);
                m_cache->currentFile = filename;

                // Adjust timing for Slow/Accelerate mode
                if (durationTreatment == GlediatorDurationTreatment::SlowAccelerate) {
                    size_t frameCount = m_cache->csvReader->frameCount();
                    size_t effectFrames = state.totalFrames;
                    if (effectFrames > 0) {
                        float speedFactor = static_cast<float>(frameCount) / effectFrames;
                        m_cache->frameMs = 50.0f * speedFactor;
                    }
                }
            }
        } else {
            auto reader = std::make_unique<GlediatorFileReader>();
            if (reader->open(filename, bufferWi, bufferHt)) {
                m_cache->glediatorReader = std::move(reader);
                m_cache->currentFile = filename;

                // Adjust timing for Slow/Accelerate mode
                if (durationTreatment == GlediatorDurationTreatment::SlowAccelerate) {
                    size_t frameCount = m_cache->glediatorReader->frameCount();
                    size_t effectFrames = state.totalFrames;
                    if (effectFrames > 0) {
                        float speedFactor = static_cast<float>(frameCount) / effectFrames;
                        m_cache->frameMs = 50.0f * speedFactor;
                    }
                }
            }
        }
    }

    // Render from CSV reader
    if (m_cache->csvReader && m_cache->csvReader->isOpen()) {
        size_t frameCount = m_cache->csvReader->frameCount();
        size_t targetFrame = static_cast<size_t>(
            (state.frameIndex - m_cache->loops * frameCount) * m_cache->frameMs / 50.0f);

        // Handle looping
        if (targetFrame >= frameCount && durationTreatment == GlediatorDurationTreatment::Loop) {
            m_cache->loops++;
            targetFrame = static_cast<size_t>(
                (state.frameIndex - m_cache->loops * frameCount) * m_cache->frameMs / 50.0f);
        }

        if (targetFrame >= frameCount) {
            // Past end, do nothing (leave black)
            return;
        }

        size_t bufSize = static_cast<size_t>(bufferWi) * bufferHt;
        std::vector<uint8_t> frameBuffer(bufSize, 0);

        size_t bytesRead = m_cache->csvReader->readFrame(targetFrame, frameBuffer.data(), bufSize);

        // CSV format is grayscale, one byte per pixel
        for (size_t j = 0; j < std::min(bytesRead, bufSize); j++) {
            uint8_t val = frameBuffer[j];
            Color c(val, val, val);
            int x = j % bufferWi;
            int y = (bufferHt - 1) - (j / bufferWi); // Flip Y
            if (x < bufferWi && y >= 0 && y < bufferHt) {
                ctx.setPixel(x, y, c);
            }
        }
        return;
    }

    // Render from Glediator reader
    if (m_cache->glediatorReader && m_cache->glediatorReader->isOpen()) {
        size_t frameCount = m_cache->glediatorReader->frameCount();
        size_t targetFrame = static_cast<size_t>(
            (state.frameIndex - m_cache->loops * frameCount) * m_cache->frameMs / 50.0f);

        // Handle looping
        if (targetFrame >= frameCount && durationTreatment == GlediatorDurationTreatment::Loop) {
            m_cache->loops++;
            targetFrame = static_cast<size_t>(
                (state.frameIndex - m_cache->loops * frameCount) * m_cache->frameMs / 50.0f);
        }

        if (targetFrame >= frameCount) {
            // Past end, show black
            ctx.clear();
            return;
        }

        size_t bufSize = m_cache->glediatorReader->frameSize();
        std::vector<uint8_t> frameBuffer(bufSize);

        if (m_cache->glediatorReader->readFrame(targetFrame, frameBuffer.data())) {
            // Glediator format is RGB, 3 bytes per pixel
            for (size_t j = 0; j < bufSize; j += 3) {
                Color c(frameBuffer[j], frameBuffer[j + 1], frameBuffer[j + 2]);
                int x = (j % (bufferWi * 3)) / 3;
                int y = (bufferHt - 1) - (j / (bufferWi * 3)); // Flip Y
                if (x < bufferWi && y >= 0 && y < bufferHt) {
                    ctx.setPixel(x, y, c);
                }
            }
        } else {
            // Read failed, show red
            ctx.fill(Color::Red());
        }
        return;
    }

    // No reader initialized, show red
    ctx.fill(Color::Red());
}

// Register the effect
XLCORE_REGISTER_EFFECT(GlediatorEffect)

} // namespace xlCore
