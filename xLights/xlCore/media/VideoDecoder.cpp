/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "VideoDecoder.h"

#include <algorithm>
#include <cctype>

namespace xlCore {

// Static member initialization
VideoDecoder::Factory VideoDecoder::s_factory = nullptr;

void VideoDecoder::setFactory(Factory factory) {
    s_factory = std::move(factory);
}

std::unique_ptr<VideoDecoder> VideoDecoder::create() {
    if (s_factory) {
        return s_factory();
    }
    return nullptr;
}

bool VideoDecoder::isVideoFile(const std::string& path) {
    // Extract extension
    size_t dotPos = path.rfind('.');
    if (dotPos == std::string::npos || dotPos == path.length() - 1) {
        return false;
    }

    std::string ext = path.substr(dotPos + 1);
    // Convert to lowercase
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) { return std::tolower(c); });

    auto supported = supportedExtensions();
    return std::find(supported.begin(), supported.end(), ext) != supported.end();
}

std::vector<std::string> VideoDecoder::supportedExtensions() {
    return {
        "mp4", "avi", "mov", "mkv", "wmv", "flv", "webm",
        "m4v", "mpg", "mpeg", "mts", "m2ts", "ts", "vob",
        "3gp", "ogv"
    };
}

// ============================================================================
// VideoFrameCache Implementation
// ============================================================================

VideoFrameCache::VideoFrameCache(size_t maxFrames)
    : m_maxFrames(maxFrames) {
}

const ImageBuffer* VideoFrameCache::get(int timeMs, int tolerance) const {
    for (const auto& cached : m_frames) {
        if (tolerance == 0) {
            if (cached.timeMs == timeMs) {
                return &cached.frame;
            }
        } else {
            if (std::abs(cached.timeMs - timeMs) <= tolerance) {
                return &cached.frame;
            }
        }
    }
    return nullptr;
}

void VideoFrameCache::put(int timeMs, ImageBuffer frame) {
    // Check if frame already exists
    for (auto& cached : m_frames) {
        if (cached.timeMs == timeMs) {
            cached.frame = std::move(frame);
            return;
        }
    }

    // Add new frame
    if (m_frames.size() >= m_maxFrames) {
        // Remove oldest frame (first in list)
        m_frames.erase(m_frames.begin());
    }

    m_frames.push_back({timeMs, std::move(frame)});
}

void VideoFrameCache::clear() {
    m_frames.clear();
}

void VideoFrameCache::setMaxFrames(size_t maxFrames) {
    m_maxFrames = maxFrames;
    while (m_frames.size() > m_maxFrames) {
        m_frames.erase(m_frames.begin());
    }
}

} // namespace xlCore
