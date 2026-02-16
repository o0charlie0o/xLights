/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "DiskRenderCache.h"

#include <algorithm>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <iomanip>
#include <sstream>
#include <vector>

namespace fs = std::filesystem;

namespace xlEngine {

static constexpr uint32_t CACHE_MAGIC   = 0x584C4352; // "XLCR"
static constexpr uint32_t CACHE_VERSION = 1;
static const std::string  FILE_PREFIX   = "effect_";
static const std::string  FILE_EXT      = ".bin";

// ---------------------------------------------------------------------------
// Construction / Destruction
// ---------------------------------------------------------------------------

DiskRenderCache::DiskRenderCache() = default;
DiskRenderCache::~DiskRenderCache() = default;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

void DiskRenderCache::setCacheDirectory(const std::string& path)
{
    _cacheDir = path;
    if (_cacheDir.empty()) {
        return;
    }

    // Ensure the directory exists. Silently ignore errors.
    std::error_code ec;
    fs::create_directories(_cacheDir, ec);
}

bool DiskRenderCache::isEnabled() const
{
    if (_cacheDir.empty()) {
        return false;
    }
    std::error_code ec;
    return fs::is_directory(_cacheDir, ec);
}

// ---------------------------------------------------------------------------
// Hashing
// ---------------------------------------------------------------------------

uint64_t DiskRenderCache::hashEffect(
    const std::string& effectType,
    const std::map<std::string, std::string>& settings,
    const std::map<std::string, std::string>& palette,
    int bufferWidth, int bufferHeight,
    int startTimeMS, int endTimeMS)
{
    // Build a deterministic composite string from all parameters.
    // std::map iterates in key order, so the hash is stable.
    std::string composite;
    composite.reserve(256);
    composite += effectType;
    composite += '|';
    for (const auto& [k, v] : settings) {
        composite += k;
        composite += '=';
        composite += v;
        composite += ';';
    }
    composite += '|';
    for (const auto& [k, v] : palette) {
        composite += k;
        composite += '=';
        composite += v;
        composite += ';';
    }
    composite += '|';
    composite += std::to_string(bufferWidth);
    composite += '|';
    composite += std::to_string(bufferHeight);
    composite += '|';
    composite += std::to_string(startTimeMS);
    composite += '|';
    composite += std::to_string(endTimeMS);

    return std::hash<std::string>{}(composite);
}

// ---------------------------------------------------------------------------
// Cache Queries
// ---------------------------------------------------------------------------

bool DiskRenderCache::hasEntry(uint64_t hash) const
{
    if (!isEnabled()) {
        return false;
    }
    std::error_code ec;
    return fs::exists(pathForHash(hash), ec);
}

std::vector<uint8_t> DiskRenderCache::loadEntry(uint64_t hash,
                                                 int& outWidth,
                                                 int& outHeight,
                                                 int& outFrameCount) const
{
    outWidth = 0;
    outHeight = 0;
    outFrameCount = 0;

    if (!isEnabled()) {
        return {};
    }

    std::string filePath = pathForHash(hash);
    std::ifstream file(filePath, std::ios::binary);
    if (!file.is_open()) {
        return {};
    }

    // Read header.
    CacheFileHeader header{};
    file.read(reinterpret_cast<char*>(&header), sizeof(header));
    if (!file.good()) {
        return {};
    }

    // Validate header.
    if (header.magic != CACHE_MAGIC) {
        return {};
    }
    if (header.version != CACHE_VERSION) {
        return {};
    }
    if (header.effectHash != hash) {
        return {};
    }

    // Sanity-check dimensions.
    uint32_t expectedBPF = header.bufferWidth * header.bufferHeight * 4;
    if (header.bytesPerFrame != expectedBPF) {
        return {};
    }
    if (header.frameCount == 0 || header.bufferWidth == 0 || header.bufferHeight == 0) {
        return {};
    }

    // Read pixel data.
    size_t totalBytes = static_cast<size_t>(header.frameCount) * header.bytesPerFrame;
    std::vector<uint8_t> data(totalBytes);
    file.read(reinterpret_cast<char*>(data.data()), static_cast<std::streamsize>(totalBytes));
    if (!file.good()) {
        return {};
    }

    outWidth = static_cast<int>(header.bufferWidth);
    outHeight = static_cast<int>(header.bufferHeight);
    outFrameCount = static_cast<int>(header.frameCount);
    return data;
}

// ---------------------------------------------------------------------------
// Cache Storage
// ---------------------------------------------------------------------------

void DiskRenderCache::storeEntry(uint64_t hash,
                                 int width, int height, int frameCount,
                                 const uint8_t* data, size_t dataSize)
{
    if (!isEnabled()) {
        return;
    }
    if (width <= 0 || height <= 0 || frameCount <= 0 || data == nullptr) {
        return;
    }

    size_t expectedSize = static_cast<size_t>(width) * height * 4 * frameCount;
    if (dataSize != expectedSize) {
        return;
    }

    std::string filePath = pathForHash(hash);
    std::ofstream file(filePath, std::ios::binary | std::ios::trunc);
    if (!file.is_open()) {
        return;
    }

    // Build and write header.
    CacheFileHeader header{};
    header.magic = CACHE_MAGIC;
    header.version = CACHE_VERSION;
    header.bufferWidth = static_cast<uint32_t>(width);
    header.bufferHeight = static_cast<uint32_t>(height);
    header.frameCount = static_cast<uint32_t>(frameCount);
    header.bytesPerFrame = static_cast<uint32_t>(width) * height * 4;
    header.effectHash = hash;
    std::memset(header.reserved, 0, sizeof(header.reserved));

    file.write(reinterpret_cast<const char*>(&header), sizeof(header));
    if (!file.good()) {
        return;
    }

    // Write pixel data.
    file.write(reinterpret_cast<const char*>(data), static_cast<std::streamsize>(dataSize));
}

// ---------------------------------------------------------------------------
// Frame-Level I/O
// ---------------------------------------------------------------------------

// We use a sentinel value in reserved[0] to mark incomplete write sessions.
// On beginWriteSession, reserved[0] is set to 0xDEADBEEF. On finish, it's
// zeroed. loadFrame rejects files with the sentinel still set.
static constexpr uint32_t WRITE_IN_PROGRESS_SENTINEL = 0xDEADBEEF;

bool DiskRenderCache::beginWriteSession(uint64_t hash, int width, int height,
                                         int frameCount)
{
    if (!isEnabled() || width <= 0 || height <= 0 || frameCount <= 0) {
        return false;
    }

    std::string filePath = pathForHash(hash);
    std::ofstream file(filePath, std::ios::binary | std::ios::trunc);
    if (!file.is_open()) {
        return false;
    }

    CacheFileHeader header{};
    header.magic = CACHE_MAGIC;
    header.version = CACHE_VERSION;
    header.bufferWidth = static_cast<uint32_t>(width);
    header.bufferHeight = static_cast<uint32_t>(height);
    header.frameCount = static_cast<uint32_t>(frameCount);
    header.bytesPerFrame = static_cast<uint32_t>(width) * height * 4;
    header.effectHash = hash;
    std::memset(header.reserved, 0, sizeof(header.reserved));
    header.reserved[0] = WRITE_IN_PROGRESS_SENTINEL;

    file.write(reinterpret_cast<const char*>(&header), sizeof(header));
    if (!file.good()) {
        return false;
    }

    // Pre-allocate file size: header + all frames.
    size_t totalSize = sizeof(CacheFileHeader) +
        static_cast<size_t>(header.frameCount) * header.bytesPerFrame;
    file.seekp(static_cast<std::streamoff>(totalSize - 1));
    file.put('\0');

    return file.good();
}

bool DiskRenderCache::writeFrame(uint64_t hash, int frameIndex,
                                  const uint8_t* data, size_t frameSize)
{
    if (!isEnabled() || data == nullptr || frameSize == 0) {
        return false;
    }

    std::string filePath = pathForHash(hash);
    std::fstream file(filePath, std::ios::binary | std::ios::in | std::ios::out);
    if (!file.is_open()) {
        return false;
    }

    // Verify header to ensure we're writing to the right file.
    CacheFileHeader header{};
    file.read(reinterpret_cast<char*>(&header), sizeof(header));
    if (!file.good() || header.magic != CACHE_MAGIC || header.effectHash != hash) {
        return false;
    }
    if (frameIndex < 0 || static_cast<uint32_t>(frameIndex) >= header.frameCount) {
        return false;
    }
    if (frameSize != header.bytesPerFrame) {
        return false;
    }

    // Seek to the frame's offset and write.
    size_t offset = sizeof(CacheFileHeader) +
        static_cast<size_t>(frameIndex) * header.bytesPerFrame;
    file.seekp(static_cast<std::streamoff>(offset));
    file.write(reinterpret_cast<const char*>(data), static_cast<std::streamsize>(frameSize));

    return file.good();
}

void DiskRenderCache::finishWriteSession(uint64_t hash)
{
    if (!isEnabled()) {
        return;
    }

    std::string filePath = pathForHash(hash);
    std::fstream file(filePath, std::ios::binary | std::ios::in | std::ios::out);
    if (!file.is_open()) {
        return;
    }

    // Clear the in-progress sentinel in the header.
    CacheFileHeader header{};
    file.read(reinterpret_cast<char*>(&header), sizeof(header));
    if (!file.good() || header.magic != CACHE_MAGIC || header.effectHash != hash) {
        return;
    }

    header.reserved[0] = 0;
    file.seekp(0);
    file.write(reinterpret_cast<const char*>(&header), sizeof(header));
}

bool DiskRenderCache::loadFrame(uint64_t hash, int frameIndex,
                                 int expectedWidth, int expectedHeight,
                                 uint8_t* outData) const
{
    if (!isEnabled() || outData == nullptr) {
        return false;
    }

    std::string filePath = pathForHash(hash);
    std::ifstream file(filePath, std::ios::binary);
    if (!file.is_open()) {
        return false;
    }

    CacheFileHeader header{};
    file.read(reinterpret_cast<char*>(&header), sizeof(header));
    if (!file.good()) {
        return false;
    }

    // Validate header.
    if (header.magic != CACHE_MAGIC || header.version != CACHE_VERSION) {
        return false;
    }
    if (header.effectHash != hash) {
        return false;
    }
    // Reject incomplete write sessions.
    if (header.reserved[0] == WRITE_IN_PROGRESS_SENTINEL) {
        return false;
    }
    if (static_cast<int>(header.bufferWidth) != expectedWidth ||
        static_cast<int>(header.bufferHeight) != expectedHeight) {
        return false;
    }
    if (frameIndex < 0 || static_cast<uint32_t>(frameIndex) >= header.frameCount) {
        return false;
    }

    size_t offset = sizeof(CacheFileHeader) +
        static_cast<size_t>(frameIndex) * header.bytesPerFrame;
    file.seekg(static_cast<std::streamoff>(offset));
    file.read(reinterpret_cast<char*>(outData),
              static_cast<std::streamsize>(header.bytesPerFrame));

    return file.good();
}

// ---------------------------------------------------------------------------
// Cache Management
// ---------------------------------------------------------------------------

void DiskRenderCache::deleteEntry(uint64_t hash)
{
    if (!isEnabled()) {
        return;
    }
    std::error_code ec;
    fs::remove(pathForHash(hash), ec);
}

void DiskRenderCache::registerModelHash(const std::string& modelName, uint64_t hash)
{
    if (!modelName.empty()) {
        _modelHashIndex[modelName].insert(hash);
    }
}

void DiskRenderCache::clearModel(const std::string& modelName)
{
    if (!isEnabled() || modelName.empty()) {
        return;
    }

    auto it = _modelHashIndex.find(modelName);
    if (it == _modelHashIndex.end()) {
        return;
    }

    std::error_code ec;
    for (uint64_t hash : it->second) {
        fs::remove(pathForHash(hash), ec);
    }
    _modelHashIndex.erase(it);
}

void DiskRenderCache::clearAll()
{
    if (!isEnabled()) {
        return;
    }

    std::error_code ec;
    for (const auto& entry : fs::directory_iterator(_cacheDir, ec)) {
        if (entry.is_regular_file(ec)) {
            fs::remove(entry.path(), ec);
        }
    }
    _modelHashIndex.clear();
}

size_t DiskRenderCache::getTotalCacheSize() const
{
    if (!isEnabled()) {
        return 0;
    }

    size_t total = 0;
    std::error_code ec;
    for (const auto& entry : fs::directory_iterator(_cacheDir, ec)) {
        if (entry.is_regular_file(ec)) {
            total += entry.file_size(ec);
        }
    }
    return total;
}

int DiskRenderCache::enforceMaxSize(size_t maxBytes)
{
    if (!isEnabled()) {
        return 0;
    }

    // Collect all cache files with their size and modification time.
    struct CacheEntry {
        fs::path path;
        size_t size;
        fs::file_time_type modTime;
    };

    std::vector<CacheEntry> entries;
    size_t totalSize = 0;

    std::error_code ec;
    for (const auto& dirEntry : fs::directory_iterator(_cacheDir, ec)) {
        if (!dirEntry.is_regular_file(ec)) {
            continue;
        }
        size_t sz = dirEntry.file_size(ec);
        auto mt = dirEntry.last_write_time(ec);
        entries.push_back({dirEntry.path(), sz, mt});
        totalSize += sz;
    }

    if (totalSize <= maxBytes) {
        return 0;
    }

    // Sort oldest first (earliest modification time first).
    std::sort(entries.begin(), entries.end(),
              [](const CacheEntry& a, const CacheEntry& b) {
                  return a.modTime < b.modTime;
              });

    // Delete oldest entries until we are under the limit.
    int deleted = 0;
    for (const auto& entry : entries) {
        if (totalSize <= maxBytes) {
            break;
        }
        std::error_code removeEc;
        if (fs::remove(entry.path, removeEc)) {
            totalSize -= entry.size;
            ++deleted;
        }
    }
    return deleted;
}

// ---------------------------------------------------------------------------
// Internal Helpers
// ---------------------------------------------------------------------------

std::string DiskRenderCache::pathForHash(uint64_t hash) const
{
    std::ostringstream oss;
    oss << FILE_PREFIX
        << std::hex << std::setfill('0') << std::setw(16) << hash
        << FILE_EXT;

    return (fs::path(_cacheDir) / oss.str()).string();
}

} // namespace xlEngine
