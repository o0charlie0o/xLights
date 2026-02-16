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

// DiskRenderCache: Persistent disk-backed cache for rendered effect pixel data.
//
// This cache stores rendered RGBA frames on disk so they can be reloaded when a
// sequence is reopened, avoiding expensive re-rendering of unchanged effects.
//
// Cache location: ShowFolder/RenderCache/SeqName_NATIVE_CACHE/
// Each cached effect is stored as a separate binary file keyed by a hash of the
// effect type, settings, palette, buffer dimensions, and timing info.
//
// File format: CacheFileHeader struct followed by raw RGBA pixel data.
//
// Thread safety: NOT thread-safe. The caller (NativeRenderCoordinator) must
// ensure proper synchronization when accessing from multiple threads.

#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace xlEngine {

struct CacheFileHeader {
    uint32_t magic;           // 0x584C4352 ("XLCR")
    uint32_t version;         // 1
    uint32_t bufferWidth;     // effect buffer width
    uint32_t bufferHeight;    // effect buffer height
    uint32_t frameCount;      // number of frames cached
    uint32_t bytesPerFrame;   // bufferWidth * bufferHeight * 4 (RGBA)
    uint64_t effectHash;      // for verification
    uint32_t reserved[4];     // future use, zero-filled
};

static_assert(sizeof(CacheFileHeader) == 48, "CacheFileHeader must be 48 bytes");

class DiskRenderCache {
public:
    DiskRenderCache();
    ~DiskRenderCache();

    // Set the cache directory path. Must be called before any cache operations.
    // Creates the directory if it doesn't exist.
    void setCacheDirectory(const std::string& path);

    // Check if the cache directory is set and valid.
    bool isEnabled() const;

    // Generate a cache key hash from effect parameters.
    static uint64_t hashEffect(const std::string& effectType,
                               const std::map<std::string, std::string>& settings,
                               const std::map<std::string, std::string>& palette,
                               int bufferWidth, int bufferHeight,
                               int startTimeMS, int endTimeMS);

    // Check if a cached entry exists for the given hash.
    bool hasEntry(uint64_t hash) const;

    // Load cached pixel data for a hash. Returns empty vector on miss.
    // The returned data is frameCount * bytesPerFrame bytes of RGBA.
    // Also returns dimensions and frame count via out params.
    std::vector<uint8_t> loadEntry(uint64_t hash,
                                   int& outWidth, int& outHeight,
                                   int& outFrameCount) const;

    // Store pixel data to disk cache. data should be frameCount * w * h * 4 bytes.
    void storeEntry(uint64_t hash,
                    int width, int height, int frameCount,
                    const uint8_t* data, size_t dataSize);

    // Begin a write session: create a cache file with the header and
    // pre-allocated space for frameCount frames. Call writeFrame() to fill
    // each frame, and finishWriteSession() to mark completion. Returns true
    // if the file was created successfully.
    bool beginWriteSession(uint64_t hash, int width, int height, int frameCount);

    // Write a single frame into an open write session. frameIndex is 0-based.
    bool writeFrame(uint64_t hash, int frameIndex,
                    const uint8_t* data, size_t frameSize);

    // Mark a write session as complete. Incomplete sessions (e.g. from a
    // crash) are detected and rejected on load.
    void finishWriteSession(uint64_t hash);

    // Load a single frame from a cached entry. outData must point to a buffer
    // of at least expectedWidth * expectedHeight * 4 bytes.
    bool loadFrame(uint64_t hash, int frameIndex,
                   int expectedWidth, int expectedHeight,
                   uint8_t* outData) const;

    // Delete a specific cache entry.
    void deleteEntry(uint64_t hash);

    // Register that a cache entry (identified by hash) belongs to a model.
    // Called when writing cache entries so clearModel() can find them later.
    void registerModelHash(const std::string& modelName, uint64_t hash);

    // Clear all cache entries belonging to a specific model.
    // Uses the model-to-hash index built by registerModelHash().
    void clearModel(const std::string& modelName);

    // Clear all cache entries in the cache directory.
    void clearAll();

    // Get total cache size in bytes.
    size_t getTotalCacheSize() const;

    // Enforce a maximum cache size by deleting oldest entries (by modification time).
    // Returns number of entries deleted.
    int enforceMaxSize(size_t maxBytes);

private:
    std::string _cacheDir;

    // In-memory index: model name → set of effect hashes written for that model.
    // Populated by registerModelHash(), used by clearModel().
    std::map<std::string, std::set<uint64_t>> _modelHashIndex;

    // Build the file path for a given hash.
    std::string pathForHash(uint64_t hash) const;
};

} // namespace xlEngine
